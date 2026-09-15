import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  attachmentReference,
  isCanonicalPrivateAttachmentPath,
  isTrustedLegacyMessagingUrl,
  PRIVATE_MESSAGING_BUCKET,
  stringValue as attachmentStringValue,
  validateMessagingAttachment,
} from "../_shared/messaging_attachments.ts";
import { buildJobActionToken } from "../_shared/whatsapp_action_tokens.ts";
import {
  buildDirectSendUtilityPayload,
  directSendUtilityStrategy,
  resolveDirectSendUtility,
} from "../_shared/whatsapp_direct_send.ts";
import {
  type DirectSendPolicyBlock,
  directSendPolicyBlockFromEvents,
} from "../_shared/whatsapp_direct_send_integrity.ts";
import {
  durableWhatsAppSendReceipt,
  whatsappProviderFailureHttpStatus,
} from "../_shared/whatsapp_send_receipts.ts";
import { normalizeWhatsAppTemplateGreeting } from "../_shared/whatsapp_template_greeting.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const WHATSAPP_ACCESS_TOKEN = Deno.env.get("WHATSAPP_ACCESS_TOKEN") ?? "";
const WHATSAPP_API_VERSION = Deno.env.get("WHATSAPP_API_VERSION") ?? "v26.0";
const CACHE_TTL_MS = 5 * 60 * 1000;

type JsonRecord = Record<string, unknown>;
// Edge Functions intentionally use the runtime schema; generated DB types are
// not bundled in this directory.
// deno-lint-ignore no-explicit-any
type SupabaseClientLike = ReturnType<typeof createClient<any>>;

/** Only an authenticated outbox worker supplies this; never populated from JSON. */
export interface TrustedWhatsAppOutbox {
  adminClient: SupabaseClientLike;
  userId: string;
  tenantId: string;
  messageId: string;
  beforeProviderSend: () => Promise<boolean>;
  persist: (patch: {
    externalMessageId?: string;
    externalStatus: "accepted" | "failed" | null;
    metadata: JsonRecord;
    content: string;
    type: string;
  }) => Promise<void>;
}

class WhatsAppPersistenceError extends Error {
  constructor(
    message: string,
    readonly stage: string,
    readonly messageId?: string,
  ) {
    super(message);
    this.name = "WhatsAppPersistenceError";
  }
}

interface CacheEntry<T> {
  value: T;
  expiresAt: number;
}

interface WhatsAppChannelRecord {
  id: string;
  phone_number_id: string;
  display_name?: string | null;
  display_phone_number?: string | null;
  is_active: boolean;
}

const tenantIdByUserId = new Map<string, CacheEntry<string>>();
const activeChannelByTenantKey = new Map<string, CacheEntry<WhatsAppChannelRecord>>();

interface SendRequest {
  conversationId?: string;
  customerId?: string;
  phoneNumber: string;
  phoneNumberId?: string;
  contactName?: string;
  contextType?: string;
  contextId?: string;
  jobId?: string;
  type: "text" | "image" | "document" | "audio" | "template" | "interactive" | "reaction";
  text?: string;
  caption?: string;
  attachmentId?: string;
  contentType?: string;
  // Legacy, trusted-storage-only document header for interactive messages.
  // Image/document messages require attachmentId and never accept a URL.
  documentUrl?: string;
  documentFilename?: string;
  templateName?: string;
  templateLanguage?: string;
  templateComponents?: unknown[];
  deliveryStrategy?: "direct_send_utility";
  interactive?: JsonRecord;
  replyToMessageId?: string;
  // Reacción: el wamid del mensaje anotado y el emoji. Un emoji vacío la
  // retira, que es como WhatsApp expresa «me arrepentí».
  reactionToExternalMessageId?: string;
  reactionEmoji?: string;
  // Fila local del mensaje anotado, para colgar la reacción sin re-resolver.
  reactionToMessageId?: string;
  reactionConversationId?: string;
  metadata?: JsonRecord;
  actionType?: string;
  actionTargetId?: string;
  actionKind?: "job" | "invoice";
  amount?: number;
  markQuoteSent?: boolean;
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function getCached<T>(cache: Map<string, CacheEntry<T>>, key: string) {
  const entry = cache.get(key);
  if (!entry) return null;
  if (entry.expiresAt <= Date.now()) {
    cache.delete(key);
    return null;
  }
  return entry.value;
}

function setCached<T>(cache: Map<string, CacheEntry<T>>, key: string, value: T) {
  cache.set(key, {
    value,
    expiresAt: Date.now() + CACHE_TTL_MS,
  });
}

function decodeJwtSubject(authHeader: string): string | null {
  try {
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    const payload = token.split(".")[1];
    if (!payload) return null;
    const normalized = payload.replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
    const claims = JSON.parse(atob(padded)) as { sub?: unknown };
    return typeof claims.sub === "string" && claims.sub.length > 0 ? claims.sub : null;
  } catch (_) {
    return null;
  }
}

function deferAfterResponse(work: Promise<unknown>) {
  const guarded = work.catch((error) => {
    console.error("❌ [WHATSAPP-SEND] Deferred housekeeping failed", error);
  });
  const runtime = (globalThis as { EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void } })
    .EdgeRuntime;
  runtime?.waitUntil?.(guarded);
}

async function cleanupStaleMessagingAttachments(
  adminClient: SupabaseClientLike,
  tenantId: string,
) {
  const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { data, error } = await adminClient
    .from("messaging_attachments")
    .select("id, storage_path, status")
    .eq("tenant_id", tenantId)
    .in("status", ["reserved", "failed", "quarantined"])
    .lt("updated_at", cutoff)
    .limit(25);
  if (error) {
    console.error("❌ [WHATSAPP-SEND] Stale attachment lookup failed", error);
    return;
  }
  for (const row of data ?? []) {
    if (row.status === "reserved") {
      await adminClient.from("messaging_attachments").update({
        status: "failed",
        failure_code: "stale_service_reservation",
        failed_at: new Date().toISOString(),
      }).eq("id", row.id).eq("status", "reserved");
    }
    const { error: removeError } = await adminClient.storage
      .from(PRIVATE_MESSAGING_BUCKET)
      .remove([String(row.storage_path)]);
    if (removeError) {
      console.error("❌ [WHATSAPP-SEND] Stale object cleanup failed", removeError);
    }
  }
}

async function resolveTenantIdForUser(
  adminClient: SupabaseClientLike,
  userId: string,
) {
  const cachedTenantId = getCached(tenantIdByUserId, userId);
  if (cachedTenantId) {
    return cachedTenantId;
  }

  const { data: profile, error: profileError } = await adminClient
    .from("user_profiles")
    .select("tenant_id")
    .eq("user_id", userId)
    .single();

  if (profileError || !profile?.tenant_id) {
    console.error("❌ [WHATSAPP-SEND] Failed to resolve tenant", profileError);
    return null;
  }

  const tenantId = String(profile.tenant_id);
  setCached(tenantIdByUserId, userId, tenantId);
  return tenantId;
}

async function resolveActiveChannel(
  adminClient: SupabaseClientLike,
  tenantId: string,
  phoneNumberId?: string,
) {
  const cacheKey = `${tenantId}:${phoneNumberId ?? "default"}`;
  const cachedChannel = getCached(activeChannelByTenantKey, cacheKey);
  if (cachedChannel) {
    return cachedChannel;
  }

  let channelQuery = adminClient
    .from("whatsapp_channels")
    .select("id, phone_number_id, display_name, display_phone_number, is_active")
    .eq("tenant_id", tenantId)
    .eq("is_active", true);

  if (phoneNumberId) {
    channelQuery = channelQuery.eq("phone_number_id", phoneNumberId);
  }

  const { data: channel, error: channelError } = await channelQuery.limit(1).maybeSingle();

  if (channelError || !channel) {
    console.error("❌ [WHATSAPP-SEND] Failed to resolve active channel", channelError);
    return null;
  }

  const resolvedChannel = channel as WhatsAppChannelRecord;
  setCached(activeChannelByTenantKey, cacheKey, resolvedChannel);
  return resolvedChannel;
}

async function resolveDirectSendPolicyBlock(params: {
  adminClient: SupabaseClientLike;
  channelId: string;
  templateName?: string;
}): Promise<DirectSendPolicyBlock | null> {
  const { data, error } = await params.adminClient
    .from("whatsapp_webhook_events")
    .select("payload, created_at")
    .eq("channel_id", params.channelId)
    .eq("event_type", "unknown")
    .order("created_at", { ascending: false })
    .limit(100);
  if (error) {
    console.error("❌ [WHATSAPP-SEND] Direct Send integrity lookup failed", error);
    return { reason: "integrity_lookup_failed", detail: error.message };
  }

  return directSendPolicyBlockFromEvents(data ?? [], params.templateName);
}

function normalizePhoneNumber(phone: string) {
  return phone.replace(/[^\d]/g, "");
}

function stringValue(value: unknown) {
  if (typeof value !== "string") {
    return undefined;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function resolveMediaFilename(request: SendRequest) {
  return request.documentFilename ??
    stringValue(request.metadata?.filename) ??
    (request.type === "image"
      ? "imagen.png"
      : request.type === "audio"
      ? "nota-de-voz.m4a"
      : "documento");
}

interface StoredMessagingAttachment {
  id: string;
  tenant_id: string;
  conversation_id: string;
  storage_bucket: string;
  storage_path: string;
  original_filename: string;
  extension: string;
  declared_mime_type: string;
  size_bytes: number;
  status: string;
  created_by?: string | null;
  message_id?: string | null;
}

interface PreparedMessagingAttachment {
  record: StoredMessagingAttachment;
  bytes: Uint8Array;
  metadata: JsonRecord;
}

async function prepareMessagingAttachment(params: {
  adminClient: SupabaseClientLike;
  request: SendRequest;
  tenantId: string;
  userId: string;
  queuedMessageId?: string;
}) {
  if (
    params.request.type !== "image" &&
    params.request.type !== "document" &&
    params.request.type !== "audio"
  ) {
    return { attachment: undefined as PreparedMessagingAttachment | undefined };
  }

  const attachmentId = attachmentStringValue(params.request.attachmentId);
  if (!attachmentId) {
    return { error: jsonResponse({ error: "attachmentId is required for media messages" }, 400) };
  }

  const { data, error } = await params.adminClient
    .from("messaging_attachments")
    .select(
      "id, tenant_id, conversation_id, storage_bucket, storage_path, original_filename, extension, declared_mime_type, size_bytes, status, created_by, message_id",
    )
    .eq("id", attachmentId)
    .eq("tenant_id", params.tenantId)
    .maybeSingle();
  if (error) {
    console.error("❌ [WHATSAPP-SEND] Attachment lookup failed", error);
    return { error: jsonResponse({ error: "Unable to validate attachment" }, 500) };
  }
  if (!data) return { error: jsonResponse({ error: "Attachment not found" }, 404) };

  const record = data as StoredMessagingAttachment;
  if (
    record.storage_bucket !== PRIVATE_MESSAGING_BUCKET ||
    !(record.status === "reserved" ||
      (record.status === "attached" && record.message_id === params.queuedMessageId)) ||
    record.created_by !== params.userId ||
    (params.request.conversationId &&
      record.conversation_id !== params.request.conversationId) ||
    !isCanonicalPrivateAttachmentPath({
      path: record.storage_path,
      tenantId: record.tenant_id,
      conversationId: record.conversation_id,
      attachmentId: record.id,
      extension: record.extension,
    })
  ) {
    return { error: jsonResponse({ error: "Attachment reservation is not sendable" }, 409) };
  }

  let contract;
  try {
    contract = validateMessagingAttachment({
      filename: record.original_filename,
      contentType: record.declared_mime_type,
      sizeBytes: Number(record.size_bytes),
    });
  } catch (error) {
    console.error("❌ [WHATSAPP-SEND] Attachment contract rejected", error);
    return { error: jsonResponse({ error: "Attachment contract is invalid" }, 415) };
  }

  const expectedType = params.request.type === "image"
    ? "image/"
    : params.request.type === "audio"
    ? "audio/"
    : undefined;
  if (expectedType && !contract.contentType.startsWith(expectedType)) {
    return {
      error: jsonResponse({
        error: params.request.type === "audio"
          ? "Attachment is not audio"
          : "Attachment is not an image",
      }, 415),
    };
  }
  if (params.request.type === "document" && contract.contentType.startsWith("image/")) {
    return { error: jsonResponse({ error: "Document attachment cannot be an image" }, 415) };
  }

  // Size/type are validated from the immutable reservation before reading the
  // object bytes. The private bucket itself enforces the same hard ceiling.
  const { data: blob, error: downloadError } = await params.adminClient.storage
    .from(PRIVATE_MESSAGING_BUCKET)
    .download(record.storage_path);
  if (downloadError || !blob) {
    console.error("❌ [WHATSAPP-SEND] Private attachment download failed", downloadError);
    return { error: jsonResponse({ error: "Unable to read private attachment" }, 500) };
  }
  if (blob.size !== Number(record.size_bytes) || blob.size > contract.maxBytes) {
    return { error: jsonResponse({ error: "Stored attachment size mismatch" }, 409) };
  }
  const bytes = new Uint8Array(await blob.arrayBuffer());
  const metadata = attachmentReference({
    attachmentId: record.id,
    storagePath: record.storage_path,
    filename: record.original_filename,
    extension: record.extension,
    contentType: record.declared_mime_type,
    sizeBytes: Number(record.size_bytes),
  });
  return { attachment: { record, bytes, metadata } };
}

async function uploadMediaToWhatsApp(
  request: SendRequest,
  phoneNumberId: string,
  attachment?: PreparedMessagingAttachment,
) {
  if (request.type !== "image" && request.type !== "document" && request.type !== "audio") {
    return { metadata: {} as JsonRecord };
  }

  if (!attachment) {
    return { error: jsonResponse({ error: "Validated attachment is required" }, 400) };
  }

  const contentType = attachment.record.declared_mime_type;
  const bytes = attachment.bytes;
  const filename = attachment.record.original_filename || resolveMediaFilename(request);
  const formData = new FormData();
  formData.append("messaging_product", "whatsapp");
  formData.append("type", contentType);
  formData.append(
    "file",
    new Blob([bytes.slice().buffer as ArrayBuffer], { type: contentType }),
    filename,
  );

  const uploadResponse = await fetch(
    `https://graph.facebook.com/${WHATSAPP_API_VERSION}/${phoneNumberId}/media`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${WHATSAPP_ACCESS_TOKEN}`,
      },
      body: formData,
      signal: AbortSignal.timeout(30_000),
    },
  );

  const uploadResult = await uploadResponse.json().catch(() => ({}));
  const mediaId = String((uploadResult as JsonRecord).id ?? "");
  if (!uploadResponse.ok || !mediaId) {
    console.error("❌ [WHATSAPP-SEND] Media upload failed", uploadResult);
    return {
      error: jsonResponse({
        error: "WhatsApp media upload failed",
        details: uploadResult,
      }, 502),
    };
  }

  return {
    mediaId,
    metadata: {
      whatsapp_media_id: mediaId,
      whatsapp_media_upload_content_type: contentType,
      whatsapp_media_upload_size: bytes.byteLength,
      ...attachment.metadata,
    } as JsonRecord,
  };
}

function actionNames(actionType: string) {
  if (actionType === "approve_quote") {
    return {
      positiveAction: "approve_quote",
      negativeAction: "reject_quote",
      positiveTitle: "Aprobar",
      negativeTitle: "Rechazar",
    };
  }
  if (actionType === "confirm_delivery") {
    return {
      positiveAction: "confirm_delivery",
      negativeAction: "cancel_delivery",
      positiveTitle: "Confirmar",
      negativeTitle: "Rechazar",
    };
  }
  if (actionType === "pay_now") {
    return {
      positiveAction: "confirm_invoice",
      negativeAction: "reject_invoice",
      positiveTitle: "Pagar",
      negativeTitle: "Rechazar",
    };
  }
  return {
    positiveAction: actionType,
    negativeAction: `reject_${actionType}`,
    positiveTitle: "Aceptar",
    negativeTitle: "Rechazar",
  };
}

function buildActionInteractivePayload(
  request: SendRequest,
  actionRevisionMs?: number,
) {
  const actionType = request.actionType;
  const actionTargetId = request.actionTargetId ?? request.jobId;
  if (!actionType || !actionTargetId) {
    return null;
  }

  const actionKind = request.actionKind ?? (actionType === "pay_now" ? "invoice" : "job");
  if (actionKind === "job" && !actionRevisionMs) return null;
  const actionId = (action: string) =>
    actionKind === "job"
      ? `job:${actionTargetId}:${action}:${actionRevisionMs}`
      : `${actionKind}:${actionTargetId}:${action}`;

  const {
    positiveAction,
    negativeAction,
    positiveTitle,
    negativeTitle,
  } = actionNames(actionType);

  return {
    type: "button",
    header: request.documentUrl
      ? {
        type: "document",
        document: {
          link: request.documentUrl,
          filename: request.documentFilename ?? "Documento.pdf",
        },
      }
      : undefined,
    body: {
      text: request.text ?? request.caption ?? "Revisa esta solicitud y responde desde WhatsApp.",
    },
    action: {
      buttons: [
        {
          type: "reply",
          reply: {
            id: actionId(negativeAction),
            title: negativeTitle,
          },
        },
        {
          type: "reply",
          reply: {
            id: actionId(positiveAction),
            title: positiveTitle,
          },
        },
      ],
    },
  };
}

function buildGraphPayload(
  request: SendRequest,
  to: string,
  mediaId?: string,
  actionRevisionMs?: number,
) {
  const payload: JsonRecord = {
    messaging_product: "whatsapp",
    recipient_type: "individual",
    to,
    type: request.type,
  };

  // Una reacción no acepta `context`: apunta a su objetivo por message_id
  // dentro del propio bloque `reaction`.
  if (request.type === "reaction") {
    payload.reaction = {
      message_id: request.reactionToExternalMessageId,
      emoji: request.reactionEmoji ?? "",
    };
    return payload;
  }

  if (request.replyToMessageId) {
    payload.context = { message_id: request.replyToMessageId };
  }

  if (request.type === "text") {
    payload.text = {
      body: request.text ?? "",
      preview_url: /https?:\/\//i.test(request.text ?? ""),
    };
    return payload;
  }

  if (request.type === "document") {
    if (!mediaId) throw new Error("validated_media_id_required");
    const document: JsonRecord = { id: mediaId };
    if (request.documentFilename) document.filename = request.documentFilename;
    if (request.caption) document.caption = request.caption;
    payload.document = document;
    return payload;
  }

  if (request.type === "image") {
    if (!mediaId) throw new Error("validated_media_id_required");
    const image: JsonRecord = { id: mediaId };
    if (request.caption) image.caption = request.caption;
    payload.image = image;
    return payload;
  }

  if (request.type === "audio") {
    // WhatsApp audio takes no caption; the recording is the message.
    if (!mediaId) throw new Error("validated_media_id_required");
    payload.audio = { id: mediaId };
    return payload;
  }

  if (request.type === "template") {
    payload.template = {
      name: request.templateName,
      language: {
        code: request.templateLanguage ?? "es",
      },
      components: request.templateComponents ?? [],
    };
    return payload;
  }

  payload.interactive = request.actionType
    ? buildActionInteractivePayload(request, actionRevisionMs)
    : request.interactive;
  return payload;
}

function getMessageContent(request: SendRequest) {
  if (request.type === "text") {
    return request.text ?? "";
  }

  if (request.type === "document") {
    return request.caption ?? request.documentFilename ?? "Documento enviado";
  }

  if (request.type === "image") {
    return request.caption ?? request.documentFilename ?? "Imagen enviada";
  }

  if (request.type === "audio") {
    return "Nota de voz";
  }

  if (request.type === "template") {
    return request.caption ?? `Template enviado: ${request.templateName ?? "sin nombre"}`;
  }

  return request.text ?? request.caption ?? "Solicitud enviada por WhatsApp";
}

async function replayStoredWhatsAppStatus(
  adminClient: SupabaseClientLike,
  externalMessageId: string,
) {
  if (!externalMessageId) {
    return;
  }

  const { error } = await adminClient.rpc("replay_whatsapp_message_status", {
    p_external_message_id: externalMessageId,
  });

  if (error) {
    console.error("❌ [WHATSAPP-SEND] Failed to replay stored status events", error);
  }
}

export async function handleWhatsAppSend(req: Request, outbox?: TrustedWhatsAppOutbox) {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  if (!SUPABASE_URL || !WHATSAPP_ACCESS_TOKEN ||
    (!outbox && (!SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY))) {
    return jsonResponse({
      error: "Missing required environment variables",
    }, 500);
  }

  const authHeader = req.headers.get("Authorization");
  if (!outbox && !authHeader) {
    return jsonResponse({ error: "Missing Authorization header" }, 401);
  }

  let requestBody: SendRequest;
  try {
    requestBody = await req.json();
  } catch (error) {
    console.error("❌ [WHATSAPP-SEND] Invalid JSON body", error);
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  if (!requestBody.phoneNumber || !requestBody.type) {
    return jsonResponse({ error: "phoneNumber and type are required" }, 400);
  }

  requestBody = normalizeWhatsAppTemplateGreeting(
    requestBody as unknown as JsonRecord,
  ) as unknown as SendRequest;
  const directSendResolution = resolveDirectSendUtility(requestBody);
  let directSendPolicyBlock: DirectSendPolicyBlock | null = null;
  if (directSendResolution.enabled && directSendResolution.body) {
    // The durable ERP copy must be the exact server-owned body sent to Meta,
    // never a caller-supplied caption that merely looks like it.
    requestBody.caption = directSendResolution.body;
  }

  const startedAt = Date.now();
  const clientMessageId = requestBody.metadata?.client_message_id ?? null;
  // Every phase is also returned to the caller: the app prints the
  // breakdown in its own log, which is the only place it can be read
  // without the dashboard.
  const timings: Array<{ phase: string; elapsed_ms: number }> = [];
  const logTiming = (phase: string, details: JsonRecord = {}) => {
    const elapsed = Date.now() - startedAt;
    timings.push({ phase, elapsed_ms: elapsed });
    console.log(
      "⏱️ [WHATSAPP-SEND] timing",
      JSON.stringify({
        phase,
        elapsed_ms: elapsed,
        type: requestBody.type,
        conversation_id: requestBody.conversationId ?? null,
        client_message_id: clientMessageId,
        ...details,
      }),
    );
  };

  logTiming("request_validated");

  if (requestBody.type === "text" && !requestBody.text) {
    return jsonResponse({ error: "text is required for text messages" }, 400);
  }

  if (requestBody.type === "document" && !requestBody.attachmentId) {
    return jsonResponse({ error: "attachmentId is required for document messages" }, 400);
  }

  if (requestBody.type === "image" && !requestBody.attachmentId) {
    return jsonResponse({ error: "attachmentId is required for image messages" }, 400);
  }

  if (requestBody.type === "audio" && !requestBody.attachmentId) {
    return jsonResponse({ error: "attachmentId is required for audio messages" }, 400);
  }

  if (
    requestBody.type === "interactive" &&
    requestBody.documentUrl &&
    !isTrustedLegacyMessagingUrl(requestBody.documentUrl, SUPABASE_URL)
  ) {
    return jsonResponse({ error: "Interactive document URL is not trusted" }, 400);
  }

  if (requestBody.type === "template" && !requestBody.templateName) {
    return jsonResponse({ error: "templateName is required for template messages" }, 400);
  }

  if (
    requestBody.type === "reaction" &&
    (!requestBody.reactionToExternalMessageId ||
      !requestBody.reactionToMessageId ||
      !requestBody.reactionConversationId)
  ) {
    return jsonResponse({
      error:
        "reactionToExternalMessageId, reactionToMessageId and reactionConversationId are required for reactions",
    }, 400);
  }

  const adminClient = outbox?.adminClient ?? createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const callerClient = outbox?.adminClient ?? createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader! } },
  });

  // Do not trust a locally decoded JWT subject. Ask Supabase Auth to verify the
  // bearer token and return the authoritative user before service-role access.
  // The tenant lookup for the subject the token *claims* starts now and
  // overlaps the auth round trip. Its result is used only if Auth confirms
  // that same user; nothing from it reaches the caller otherwise.
  const claimedUserId = outbox ? null : decodeJwtSubject(authHeader!);
  const speculativeTenant: Promise<string | null> = claimedUserId
    ? resolveTenantIdForUser(adminClient, claimedUserId).catch(() => null)
    : Promise.resolve(null);
  const { data: authData, error: authError } = outbox
    ? { data: { user: { id: outbox.userId } }, error: null }
    : await callerClient.auth.getUser();
  const userId = authData.user?.id;
  if (authError || !userId) {
    console.error("❌ [WHATSAPP-SEND] Auth verification failed", authError);
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  logTiming("auth_resolved");

  const tenantId = outbox?.tenantId ?? (claimedUserId === userId
    ? (await speculativeTenant) ?? await resolveTenantIdForUser(adminClient, userId)
    : await resolveTenantIdForUser(adminClient, userId));
  if (!tenantId) {
    return jsonResponse({ error: "Unable to resolve tenant" }, 400);
  }

  logTiming("tenant_resolved");
  // Housekeeping of yesterday's abandoned reservations has nothing to do
  // with this message: it ran serially on every send (a lookup plus up to 25
  // updates and object removals) before the send was even authorised. It now
  // runs after the response; the isolate keeps it alive through waitUntil
  // when the runtime offers it, and it is idempotent if it is cut short.
  deferAfterResponse(cleanupStaleMessagingAttachments(adminClient, tenantId));

  // The conversation, the channel and the attachment depend only on the
  // tenant: one round trip instead of three in a row.
  const conversationPromise = requestBody.conversationId
    ? callerClient
      .from("conversations")
      .select("id, tenant_id, context_type, context_id")
      .eq("id", requestBody.conversationId)
      .maybeSingle()
    : Promise.resolve({ data: null, error: null });
  const channelPromise = resolveActiveChannel(
    adminClient,
    tenantId,
    requestBody.phoneNumberId,
  );
  const preparedPromise = prepareMessagingAttachment({
    adminClient,
    request: requestBody,
    tenantId,
    userId,
    queuedMessageId: outbox?.messageId,
  });
  const [conversationLookup, channel, prepared] = await Promise.all([
    conversationPromise,
    channelPromise,
    preparedPromise,
  ]);

  let visibleConversation: JsonRecord | null = null;
  if (requestBody.conversationId) {
    const { data, error } = conversationLookup;
    if (error) {
      console.error("❌ [WHATSAPP-SEND] Conversation authorization failed", error);
      return jsonResponse({ error: "Unable to authorize conversation" }, 500);
    }
    if (!data || String(data.tenant_id) !== tenantId) {
      return jsonResponse({ error: "Conversation not found" }, 404);
    }
    visibleConversation = data as JsonRecord;
  } else if (
    requestBody.type === "image" ||
    requestBody.type === "document" ||
    requestBody.type === "audio" ||
    requestBody.type === "interactive" ||
    requestBody.markQuoteSent
  ) {
    return jsonResponse({ error: "conversationId is required for this message" }, 400);
  }

  if (prepared.error) return prepared.error;

  if (!channel) {
    return jsonResponse({ error: "No active WhatsApp channel found for tenant" }, 400);
  }

  if (directSendResolution.enabled) {
    directSendPolicyBlock = await resolveDirectSendPolicyBlock({
      adminClient,
      channelId: channel.id,
      templateName: directSendResolution.templateName,
    });
  }

  logTiming("channel_resolved", {
    channel_id: channel.id,
    phone_number_id: channel.phone_number_id,
  });

  const normalizedPhone = normalizePhoneNumber(requestBody.phoneNumber);
  const bindingContextType = requestBody.conversationId ? null : requestBody.contextType ?? null;
  const bindingContextId = requestBody.conversationId ? null : requestBody.contextId ?? null;

  // Started now, awaited as late as possible. In outbox mode the binding's
  // identity was proven by the acceptance transaction and is re-checked by
  // the send fence, so its upkeep (contact name, customer context,
  // participants: 150-350 ms in production) runs alongside the media upload
  // and the Meta call instead of ahead of them. The synchronous path still
  // waits here, because there the binding is what decides the conversation.
  const bindingPromise: Promise<{ data: unknown; error: unknown }> = (async () =>
    await adminClient.rpc(
      "ensure_whatsapp_conversation_binding",
      {
        p_tenant_id: tenantId,
        p_channel_id: channel.id,
        p_wa_id: normalizedPhone,
        p_phone_number: normalizedPhone,
        p_contact_name: requestBody.contactName ?? null,
        p_customer_id: requestBody.customerId ?? null,
        p_context_type: bindingContextType,
        p_context_id: bindingContextId,
        p_conversation_id: requestBody.conversationId ?? null,
      },
    ))();
  bindingPromise.catch(() => {});
  let bindingResult: JsonRecord | null = null;
  const resolveBinding = async (): Promise<JsonRecord | null> => {
    if (bindingResult) return bindingResult;
    const { data, error } = await bindingPromise;
    if (error || !data) {
      console.error("❌ [WHATSAPP-SEND] Failed to ensure conversation binding", error);
      return null;
    }
    bindingResult = data as JsonRecord;
    return bindingResult;
  };
  const requestedJobTarget = requestBody.actionKind === "job" || requestBody.markQuoteSent
    ? stringValue(requestBody.actionTargetId) ?? stringValue(requestBody.jobId)
    : null;
  let boundConversationId = outbox ? String(requestBody.conversationId ?? "") : "";
  let boundCustomerId: string | null = null;
  if (!outbox || requestedJobTarget) {
    const binding = await resolveBinding();
    if (!binding) {
      return jsonResponse({ error: "Unable to bind WhatsApp conversation" }, 500);
    }
    boundConversationId = String(binding.conversation_id ?? "");
    boundCustomerId = stringValue(binding.customer_id) ?? null;
  }
  if (
    !boundConversationId ||
    (visibleConversation && boundConversationId !== String(visibleConversation.id))
  ) {
    return jsonResponse({ error: "WhatsApp binding does not match conversation" }, 409);
  }
  if (
    prepared.attachment &&
    prepared.attachment.record.conversation_id !== boundConversationId
  ) {
    return jsonResponse({ error: "Attachment does not belong to this conversation" }, 409);
  }

  // The Graph context must identify a real message of this bound recipient.
  // Validate before the provider side effect, including direct (non-outbox)
  // requests; the database independently constructs the durable quote preview.
  const replyExternalId = stringValue(requestBody.replyToMessageId)?.trim();
  if (replyExternalId) {
    const { data: replyTarget, error: replyError } = await adminClient
      .from("messages")
      .select("id")
      .eq("tenant_id", tenantId)
      .eq("conversation_id", boundConversationId)
      .eq("external_provider", "whatsapp")
      .eq("external_message_id", replyExternalId)
      .maybeSingle();
    if (replyError) {
      return jsonResponse({ error: "Unable to validate reply target" }, 503);
    }
    if (!replyTarget) {
      return jsonResponse({ error: "Reply target must belong to this conversation" }, 400);
    }
    requestBody.replyToMessageId = replyExternalId;
  }

  let verifiedActionJobId: string | null = null;
  if (requestedJobTarget) {
    if (!visibleConversation || !boundCustomerId) {
      return jsonResponse({ error: "Job action requires a customer-bound conversation" }, 409);
    }
    const directContextMatches =
      String(visibleConversation.context_type ?? "").toLowerCase() === "job" &&
      String(visibleConversation.context_id ?? "") === requestedJobTarget;
    let linkedContextMatches = directContextMatches;
    if (!linkedContextMatches) {
      const { data: linkedContext, error: linkedContextError } = await adminClient
        .from("conversation_contexts")
        .select("conversation_id")
        .eq("conversation_id", boundConversationId)
        .eq("tenant_id", tenantId)
        .eq("context_type", "job")
        .eq("context_id", requestedJobTarget)
        .maybeSingle();
      if (linkedContextError) {
        console.error("❌ [WHATSAPP-SEND] Job context validation failed", linkedContextError);
        return jsonResponse({ error: "Unable to validate job context" }, 500);
      }
      linkedContextMatches = Boolean(linkedContext);
    }

    const { data: job, error: jobError } = await adminClient
      .from("mechanic_jobs")
      .select(
        "id, tenant_id, customer_id, deleted_at, quotation_status, quotation_valid_until",
      )
      .eq("id", requestedJobTarget)
      .eq("tenant_id", tenantId)
      .is("deleted_at", null)
      .maybeSingle();
    if (jobError) {
      console.error("❌ [WHATSAPP-SEND] Job target validation failed", jobError);
      return jsonResponse({ error: "Unable to validate job target" }, 500);
    }
    if (
      !linkedContextMatches ||
      !job ||
      String(job.customer_id ?? "") !== boundCustomerId
    ) {
      return jsonResponse({ error: "Job, customer and conversation do not match" }, 403);
    }
    if (
      requestBody.actionType === "approve_quote" &&
      (String(job.quotation_status ?? "pending").toLowerCase() !== "pending" ||
        (job.quotation_valid_until &&
          new Date(String(job.quotation_valid_until)).getTime() < Date.now()))
    ) {
      return jsonResponse({ error: "Quotation is not pending or has expired" }, 409);
    }
    verifiedActionJobId = String(job.id);
  }

  if (
    requestBody.markQuoteSent &&
    (requestBody.actionType !== "approve_quote" ||
      verifiedActionJobId == null)
  ) {
    return jsonResponse({ error: "Quote evidence is not linked to a verified job" }, 400);
  }

  const actionRevisionMs = verifiedActionJobId && requestBody.actionType ? Date.now() : undefined;
  const actionDescriptor = requestBody.actionType ? actionNames(requestBody.actionType) : null;
  const positiveActionToken = actionRevisionMs && verifiedActionJobId && actionDescriptor
    ? buildJobActionToken({
      jobId: verifiedActionJobId,
      action: actionDescriptor.positiveAction,
      revisionMs: actionRevisionMs,
    })
    : null;
  const negativeActionToken = actionRevisionMs && verifiedActionJobId && actionDescriptor
    ? buildJobActionToken({
      jobId: verifiedActionJobId,
      action: actionDescriptor.negativeAction,
      revisionMs: actionRevisionMs,
    })
    : null;

  const messageType = requestBody.type === "image"
    ? "image"
    : requestBody.type === "document"
    ? "file"
    : requestBody.type === "audio"
    ? "file"
    : requestBody.actionType
    ? "action_request"
    : "text";

  const directSendEnabled = directSendResolution.enabled && directSendPolicyBlock == null;
  let deliveryStrategyUsed = directSendEnabled
    ? directSendUtilityStrategy
    : directSendResolution.requested && directSendPolicyBlock != null
    ? "classic_template_policy_fallback"
    : requestBody.type === "template"
    ? "classic_template"
    : "service";
  let directSendRejection: unknown = null;

  const buildMessageMetadata = (extra: JsonRecord = {}) => ({
    ...Object.fromEntries(
      Object.entries(requestBody.metadata ?? {}).filter(([key]) =>
        ![
          "url",
          "media_url",
          "image_url",
          "file_url",
          "documentUrl",
          "document_url",
          "storage_url",
          "public_url",
          "whatsapp_media_url",
          "download_url",
          "storageBucket",
          "storage_bucket",
          "storagePath",
          "storage_path",
          "attachment_id",
          "external_status",
          "whatsapp_status",
          "meta_status",
          "external_message_id",
          "server_message_id",
          "outcome_unknown",
          "retry_disabled",
          "pending",
          "reply_to",
          "reply_to_external_message_id",
        ].includes(key)
      ),
    ),
    channel: "whatsapp",
    provider: "whatsapp",
    ...(replyExternalId ? { reply_to_external_message_id: replyExternalId } : {}),
    phone_number_id: channel.phone_number_id,
    display_phone_number: channel.display_phone_number,
    external_wa_id: normalizedPhone,
    outbound_type: requestBody.type,
    delivery_strategy_requested: directSendResolution.requested
      ? directSendUtilityStrategy
      : requestBody.type === "template"
      ? "classic_template"
      : "service",
    delivery_strategy: deliveryStrategyUsed,
    direct_send_eligible: directSendEnabled,
    direct_send_resolution: directSendPolicyBlock?.reason ?? directSendResolution.reason,
    direct_send_policy_detail: directSendPolicyBlock?.detail ?? null,
    direct_send_rejection: directSendRejection,
    ...(prepared.attachment?.metadata ?? {}),
    ...(requestBody.documentFilename
      ? {
        document_filename: requestBody.documentFilename,
        filename: requestBody.documentFilename,
      }
      : {}),
    action_type: requestBody.actionType ?? null,
    action_kind: requestBody.actionKind ??
      (requestBody.actionType ? requestBody.actionType === "pay_now" ? "invoice" : "job" : null),
    target_id: verifiedActionJobId ?? requestBody.actionTargetId ?? null,
    jobId: verifiedActionJobId,
    action_revision_ms: actionRevisionMs ?? null,
    action_token: positiveActionToken,
    action_reject_token: negativeActionToken,
    action_allowed_actions: actionDescriptor && verifiedActionJobId
      ? [actionDescriptor.positiveAction, actionDescriptor.negativeAction]
      : null,
    amount: requestBody.amount ?? null,
    status: "pending",
    ...extra,
  });

  const persistOutboundMessage = async ({
    externalMessageId,
    externalStatus,
    metadata,
    graphResult,
  }: {
    externalMessageId?: string;
    externalStatus: "accepted" | "failed" | null;
    metadata: JsonRecord;
    graphResult?: unknown;
  }) => {
    if (externalStatus === "accepted" && !externalMessageId) {
      throw new WhatsAppPersistenceError(
        "Accepted WhatsApp messages require provider evidence",
        "provider_receipt",
      );
    }

    const persistStartedAt = Date.now();
    const binding = await resolveBinding();
    if (!binding) {
      throw new WhatsAppPersistenceError(
        "Unable to bind WhatsApp conversation",
        "binding",
      );
    }
    logTiming("persist_binding_ready", {
      persist_elapsed_ms: Date.now() - persistStartedAt,
      conversation_id: binding.conversation_id,
    });

    if (outbox) {
      await outbox.persist({
        externalMessageId, externalStatus, metadata,
        content: getMessageContent(requestBody), type: messageType,
      });
    }
    const { data: insertedMessage, error: insertError } = outbox
      ? { data: { id: outbox.messageId }, error: null }
      : await adminClient
      .from("messages")
      .insert({
        conversation_id: binding.conversation_id,
        sender_id: userId,
        tenant_id: tenantId,
        content: getMessageContent(requestBody),
        type: messageType,
        metadata,
        external_provider: "whatsapp",
        external_message_id: externalMessageId || null,
        message_direction: "outbound",
        external_status: externalStatus,
      })
      .select("id")
      .single();

    if (insertError) {
      console.error("❌ [WHATSAPP-SEND] Failed to persist outbound message", insertError);
      throw new WhatsAppPersistenceError(
        "Unable to persist outbound WhatsApp message",
        "message_insert",
      );
    }
    if (!insertedMessage?.id) {
      throw new WhatsAppPersistenceError(
        "Outbound message insert returned no durable identifier",
        "message_insert_receipt",
      );
    }

    if (prepared.attachment && !outbox) {
      const attachmentUpdate = externalStatus !== "failed"
        ? {
          status: "attached",
          message_id: insertedMessage.id,
          attached_at: new Date().toISOString(),
          failed_at: null,
          failure_code: null,
        }
        : {
          status: "failed",
          message_id: insertedMessage.id,
          failed_at: new Date().toISOString(),
          failure_code: "whatsapp_send_failed",
        };
      const { data: finalizedAttachment, error: attachmentUpdateError } = await adminClient
        .from("messaging_attachments")
        .update(attachmentUpdate)
        .eq("id", prepared.attachment.record.id)
        .eq("tenant_id", tenantId)
        .eq("status", "reserved")
        .select("id, status, message_id")
        .maybeSingle();
      if (attachmentUpdateError || !finalizedAttachment) {
        console.error(
          "❌ [WHATSAPP-SEND] Failed to finalize attachment registry",
          attachmentUpdateError,
        );
        throw new WhatsAppPersistenceError(
          "Outbound message persisted but its attachment registry did not finalize",
          "attachment_finalize",
          String(insertedMessage.id),
        );
      }
      if (externalStatus === "failed") {
        const { error: cleanupError } = await adminClient.storage
          .from(PRIVATE_MESSAGING_BUCKET)
          .remove([prepared.attachment.record.storage_path]);
        if (cleanupError) {
          console.error(
            "❌ [WHATSAPP-SEND] Failed attachment cleanup failed",
            cleanupError,
          );
        }
      }
    }

    logTiming("persist_message_inserted", {
      persist_elapsed_ms: Date.now() - persistStartedAt,
    });
    // The message row is durable at this point; that is what the caller's
    // first check mark means. A status that arrived before the row and the
    // binding's last-outbound stamp are projections, so they complete after
    // the response instead of holding it.
    deferAfterResponse(
      Promise.all([
        externalMessageId
          ? replayStoredWhatsAppStatus(adminClient, externalMessageId)
          : Promise.resolve(),
        adminClient
          .from("whatsapp_conversation_bindings")
          .update({ last_outbound_at: new Date().toISOString() })
          .eq("id", binding.binding_id),
      ]),
    );

    if (
      externalStatus === "accepted" &&
      requestBody.markQuoteSent &&
      verifiedActionJobId &&
      externalMessageId
    ) {
      const { error } = await adminClient.rpc("mark_whatsapp_conversation_quote_sent", {
        p_conversation_id: boundConversationId,
        p_job_id: verifiedActionJobId,
        p_message_id: insertedMessage.id,
        p_external_message_id: externalMessageId || null,
        p_payload: graphResult ?? {},
      });

      if (error) {
        console.error("❌ [WHATSAPP-SEND] Failed to mark quote as sent", error);
        throw new WhatsAppPersistenceError(
          "WhatsApp message persisted but quote workflow evidence failed",
          "quote_evidence",
          String(insertedMessage.id),
        );
      }
    }

    logTiming("persist_done", {
      persist_elapsed_ms: Date.now() - persistStartedAt,
    });
    return { messageId: String(insertedMessage.id) };
  };

  const persistFailureResponse = async ({
    code,
    message,
    details,
    httpStatus,
    externalStatus = "failed",
    outcomeUnknown = false,
    metadata = {},
  }: {
    code: string;
    message: string;
    details?: unknown;
    httpStatus: number;
    externalStatus?: "failed" | null;
    outcomeUnknown?: boolean;
    metadata?: JsonRecord;
  }) => {
    try {
      const persisted = await persistOutboundMessage({
        externalStatus,
        metadata: buildMessageMetadata({
          ...metadata,
          status: outcomeUnknown ? "outcome_unknown" : "failed",
          whatsapp_status: outcomeUnknown ? "outcome_unknown" : "failed",
          whatsapp_status_payload: details ?? { error: message },
        }),
      });
      return jsonResponse({
        ok: false,
        accepted: false,
        queued: false,
        code,
        error: message,
        details,
        outcome_unknown: outcomeUnknown,
        evidence_persisted: true,
        message_id: persisted.messageId,
      }, httpStatus);
    } catch (error) {
      console.error("❌ [WHATSAPP-SEND] Failed to persist failure evidence", error);
      const persistenceError = error instanceof WhatsAppPersistenceError ? error : null;
      return jsonResponse({
        ok: false,
        accepted: false,
        queued: false,
        code: "outbound_failure_evidence_persistence_failed",
        error: "WhatsApp send failed and its ERP evidence is incomplete",
        original_error: code,
        outcome_unknown: outcomeUnknown,
        evidence_persisted: Boolean(persistenceError?.messageId),
        message_id: persistenceError?.messageId ?? null,
        failure_stage: persistenceError?.stage ?? "unknown",
        retry_safe: !outcomeUnknown,
      }, 500);
    }
  };

  logTiming("media_upload_start");
  let mediaUpload: Awaited<ReturnType<typeof uploadMediaToWhatsApp>>;
  try {
    mediaUpload = await uploadMediaToWhatsApp(
      requestBody,
      String(channel.phone_number_id),
      prepared.attachment,
    );
  } catch (error) {
    logTiming("media_upload_failed");
    console.error("❌ [WHATSAPP-SEND] Media upload request failed", error);
    return await persistFailureResponse({
      code: "whatsapp_media_upload_failed",
      message: "WhatsApp media upload failed",
      details: { error: String(error) },
      httpStatus: 502,
    });
  }
  if (mediaUpload.error) {
    logTiming("media_upload_failed");
    let failurePayload: unknown = { error: "WhatsApp media upload failed" };
    try {
      failurePayload = await mediaUpload.error.clone().json();
    } catch (_error) {
      // Keep the generic payload above.
    }
    return await persistFailureResponse({
      code: "whatsapp_media_upload_failed",
      message: "WhatsApp media upload failed",
      details: failurePayload,
      httpStatus: 502,
    });
  }
  logTiming("media_upload_done", {
    uploaded: Boolean(mediaUpload.mediaId),
  });

  let graphPayload: JsonRecord;
  let classicTemplatePayload: JsonRecord | null = null;
  try {
    const standardPayload = buildGraphPayload(
      requestBody,
      normalizedPhone,
      mediaUpload.mediaId,
      actionRevisionMs,
    );
    if (directSendEnabled && directSendResolution.body) {
      classicTemplatePayload = standardPayload;
      graphPayload = buildDirectSendUtilityPayload({
        to: normalizedPhone,
        body: directSendResolution.body,
      });
    } else {
      graphPayload = standardPayload;
    }
  } catch (error) {
    return await persistFailureResponse({
      code: "invalid_graph_payload",
      message: "Unable to build the WhatsApp request",
      details: { error: String(error) },
      httpStatus: 400,
    });
  }
  if (requestBody.type === "interactive" && !graphPayload.interactive) {
    return await persistFailureResponse({
      code: "interactive_payload_required",
      message: "interactive payload is required, or provide actionType/actionTargetId",
      httpStatus: 400,
    });
  }

  // Fence immediately before the first message POST, not before media upload.
  // If the lease expired, the old worker must not reach Meta.
  if (outbox && !await outbox.beforeProviderSend()) {
    return jsonResponse({ error: "Outbox send lease is no longer valid" }, 409);
  }
  logTiming("graph_request_start", {
    delivery_strategy: deliveryStrategyUsed,
  });
  let graphResponse: Response;
  try {
    graphResponse = await fetch(
      `https://graph.facebook.com/${WHATSAPP_API_VERSION}/${channel.phone_number_id}/messages`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${WHATSAPP_ACCESS_TOKEN}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(graphPayload),
        signal: AbortSignal.timeout(30_000),
      },
    );
  } catch (error) {
    logTiming("graph_request_outcome_unknown");
    console.error("❌ [WHATSAPP-SEND] Graph request outcome unknown", error);
    return await persistFailureResponse({
      code: "whatsapp_graph_outcome_unknown",
      message: "WhatsApp did not return a delivery receipt",
      details: { error: String(error) },
      httpStatus: whatsappProviderFailureHttpStatus({ outcomeUnknown: true }),
      externalStatus: null,
      outcomeUnknown: true,
      metadata: { graph_payload: graphPayload },
    });
  }

  logTiming("graph_response_headers", { status: graphResponse.status });
  let graphResult = await graphResponse.json().catch(() => ({}));
  if (!graphResponse.ok && classicTemplatePayload) {
    directSendRejection = {
      http_status: graphResponse.status,
      response: graphResult,
    };
    deliveryStrategyUsed = "classic_template_fallback";
    graphPayload = classicTemplatePayload;
    logTiming("direct_send_rejected_fallback_start", {
      status: graphResponse.status,
    });
    try {
      graphResponse = await fetch(
        `https://graph.facebook.com/${WHATSAPP_API_VERSION}/${channel.phone_number_id}/messages`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${WHATSAPP_ACCESS_TOKEN}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(graphPayload),
          signal: AbortSignal.timeout(30_000),
        },
      );
    } catch (error) {
      logTiming("direct_send_fallback_outcome_unknown");
      console.error(
        "❌ [WHATSAPP-SEND] Classic template fallback outcome unknown",
        error,
      );
      return await persistFailureResponse({
        code: "whatsapp_graph_outcome_unknown",
        message: "WhatsApp did not return a fallback delivery receipt",
        details: { error: String(error) },
        httpStatus: whatsappProviderFailureHttpStatus({ outcomeUnknown: true }),
        externalStatus: null,
        outcomeUnknown: true,
        metadata: {
          graph_payload: graphPayload,
          direct_send_rejection: directSendRejection,
        },
      });
    }
    graphResult = await graphResponse.json().catch(() => ({}));
    logTiming("direct_send_fallback_response", {
      status: graphResponse.status,
    });
  }
  if (!graphResponse.ok) {
    logTiming("graph_request_failed", { status: graphResponse.status });
    console.error("❌ [WHATSAPP-SEND] Graph API error", graphResult);
    return await persistFailureResponse({
      code: "whatsapp_graph_rejected",
      message: "WhatsApp rejected the message",
      details: graphResult,
      httpStatus: whatsappProviderFailureHttpStatus({
        providerStatus: graphResponse.status,
      }),
      metadata: {
        graph_payload: graphPayload,
        graph_response: graphResult,
        provider_http_status: graphResponse.status,
        direct_send_rejection: directSendRejection,
      },
    });
  }

  const externalMessageId = String(
    ((graphResult as JsonRecord).messages as JsonRecord[] | undefined)?.[0]?.id ?? "",
  ).trim();
  if (!externalMessageId) {
    logTiming("graph_receipt_missing");
    return await persistFailureResponse({
      code: "whatsapp_graph_receipt_missing",
      message: "WhatsApp returned no external message identifier",
      details: graphResult,
      httpStatus: whatsappProviderFailureHttpStatus({ outcomeUnknown: true }),
      externalStatus: null,
      outcomeUnknown: true,
      metadata: {
        ...(mediaUpload.metadata ?? {}),
        graph_payload: graphPayload,
        graph_response: graphResult,
      },
    });
  }

  logTiming("graph_request_done", {
    status: graphResponse.status,
    external_message_id: externalMessageId,
  });

  // Una reacción anota un mensaje que ya existe: no persiste uno nuevo. Sale
  // antes de `persistOutboundMessage` por la misma razón que el webhook la
  // saca del camino de ingreso — tratarla como mensaje es lo que ensuciaba el
  // chat y levantaba no-leídos falsos.
  if (requestBody.type === "reaction") {
    const emoji = (requestBody.reactionEmoji ?? "").trim();
    if (emoji === "") {
      await adminClient
        .from("message_reactions")
        .delete()
        .eq("message_id", requestBody.reactionToMessageId)
        .eq("reactor_user_id", userId);
    } else {
      const { error: reactionError } = await adminClient
        .from("message_reactions")
        .upsert({
          tenant_id: tenantId,
          message_id: requestBody.reactionToMessageId,
          conversation_id: requestBody.reactionConversationId,
          reactor_user_id: userId,
          emoji,
          external_provider: "whatsapp",
          external_message_id: externalMessageId,
          updated_at: new Date().toISOString(),
        }, { onConflict: "message_id, reactor_key" });
      if (reactionError) {
        console.error(
          "❌ [WHATSAPP-SEND] Reaction accepted by provider but not stored",
          reactionError,
        );
        return jsonResponse({
          ok: false,
          accepted: true,
          error: "reaction_not_persisted",
          details: reactionError.message,
          external_message_id: externalMessageId,
        }, 500);
      }
    }
    logTiming("response_returning", { reaction: true });
    return jsonResponse({
      ok: true,
      accepted: true,
      reaction: true,
      external_message_id: externalMessageId,
      graph_result: graphResult,
    });
  }

  try {
    const persisted = await persistOutboundMessage({
      externalMessageId,
      externalStatus: "accepted",
      graphResult,
      metadata: buildMessageMetadata({
        ...(mediaUpload.metadata ?? {}),
        graph_payload: graphPayload,
        graph_response: graphResult,
      }),
    });
    const receipt = durableWhatsAppSendReceipt({
      messageId: persisted.messageId,
      externalMessageId,
    });
    logTiming("response_returning", {
      queued: false,
      accepted: true,
      message_id: receipt.message_id,
      external_message_id: receipt.external_message_id,
    });
    return jsonResponse({
      ...receipt,
      delivery_strategy: deliveryStrategyUsed,
      graph_result: graphResult,
      timings,
    });
  } catch (error) {
    console.error(
      "❌ [WHATSAPP-SEND] Provider accepted but ERP finalization failed",
      error,
    );
    const persistenceError = error instanceof WhatsAppPersistenceError ? error : null;
    return jsonResponse({
      ok: false,
      accepted: false,
      provider_accepted: true,
      queued: false,
      code: "provider_accepted_erp_finalization_failed",
      error: "WhatsApp accepted the message but ERP finalization is incomplete",
      external_message_id: externalMessageId,
      message_id: persistenceError?.messageId ?? null,
      evidence_persisted: Boolean(persistenceError?.messageId),
      failure_stage: persistenceError?.stage ?? "unknown",
      outcome_unknown: false,
      retry_safe: false,
    }, 500);
  }
}

// The worker imports the same validation/template/delivery implementation.
// Importing it must not start the legacy HTTP server in the worker isolate.
if (import.meta.main) serve((req) => handleWhatsAppSend(req));
