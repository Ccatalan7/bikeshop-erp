import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { constantTimeEqual } from "../_shared/transactional_email/crypto.ts";
import { sendWithResend } from "../_shared/transactional_email/resend_client.ts";
import {
  attachmentReference,
  buildPrivateMessagingAttachmentPath,
  PRIVATE_MESSAGING_BUCKET,
  stringValue,
  validateMessagingAttachment,
} from "../_shared/messaging_attachments.ts";
import {
  parseWhatsAppActionToken,
  type WhatsAppActionTarget,
} from "../_shared/whatsapp_action_tokens.ts";
import {
  parseWhatsAppStatusEmailAlertMetadata,
  renderWhatsAppStatusAlertVerificationEmail,
  renderWhatsAppStatusEmail,
  terminalWhatsAppStatus,
  whatsappProviderErrorSummary,
  whatsappStatusAlertIdempotencyKey,
  type WhatsAppStatusEmailAlertConfig,
  whatsappStatusOccurredAt,
  type WhatsAppTerminalStatus,
} from "../_shared/whatsapp_status_email_alert.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-hub-signature-256",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const WHATSAPP_VERIFY_TOKEN = Deno.env.get("WHATSAPP_VERIFY_TOKEN") ?? "";
const WHATSAPP_ACCESS_TOKEN = Deno.env.get("WHATSAPP_ACCESS_TOKEN") ?? "";
const WHATSAPP_API_VERSION = Deno.env.get("WHATSAPP_API_VERSION") ?? "v23.0";
const META_APP_SECRET = Deno.env.get("META_APP_SECRET") ?? "";
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const WHATSAPP_STATUS_ALERT_TEST_SECRET = Deno.env.get("WHATSAPP_STATUS_ALERT_TEST_SECRET") ?? "";
const STATUS_ALERT_SENDER = "Ventas Viñabike <ventas@vinabike.cl>";
const STATUS_ALERT_REPLY_TO = "ventas@vinabike.cl";

type JsonRecord = Record<string, unknown>;
// deno-lint-ignore no-explicit-any
type SupabaseClientLike = ReturnType<typeof createClient<any>>;

interface PersistedInboundMessage {
  id: string;
  tenant_id: string;
  conversation_id: string;
  metadata: JsonRecord;
}

interface StatusAlertMessage {
  id: string;
  tenantId: string;
  conversationId: string | null;
  externalMessageId: string;
  externalStatus: string | null;
  config: WhatsAppStatusEmailAlertConfig;
}

interface StatusAlertLedger {
  id: string;
  data: JsonRecord;
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function recordValue(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {};
}

function statusAlertNotificationType(status: WhatsAppTerminalStatus | "verification") {
  return status === "verification"
    ? "whatsapp_status_email_alert_connected"
    : `whatsapp_message_${status}_email_alert`;
}

async function resolveStatusAlertMessage(params: {
  supabase: SupabaseClientLike;
  messageId?: string | null;
  externalMessageId?: string | null;
}): Promise<StatusAlertMessage | null> {
  let query = params.supabase
    .from("messages")
    .select("id, tenant_id, conversation_id, external_message_id, external_status, metadata");
  query = params.messageId
    ? query.eq("id", params.messageId)
    : query.eq("external_provider", "whatsapp")
      .eq("external_message_id", params.externalMessageId ?? "");
  const { data, error } = await query.maybeSingle();
  if (error) throw error;
  if (!data) return null;
  const config = parseWhatsAppStatusEmailAlertMetadata(data.metadata);
  if (!config) return null;
  return {
    id: String(data.id),
    tenantId: String(data.tenant_id),
    conversationId: stringValue(data.conversation_id) ?? null,
    externalMessageId: String(data.external_message_id ?? ""),
    externalStatus: stringValue(data.external_status) ?? null,
    config,
  };
}

async function ensureStatusAlertLedger(params: {
  supabase: SupabaseClientLike;
  message: StatusAlertMessage;
  status: WhatsAppTerminalStatus | "verification";
  occurredAt: Date;
  title: string;
  body: string;
  readAt?: string | null;
}): Promise<StatusAlertLedger> {
  const type = statusAlertNotificationType(params.status);
  const baseData: JsonRecord = {
    activation_id: params.message.config.activationId,
    message_id: params.message.id,
    conversation_id: params.message.conversationId,
    external_message_id: params.message.externalMessageId,
    whatsapp_status: params.status,
    recipient_email: params.message.config.recipientEmail,
    contact_name: params.message.config.contactName,
    email_delivery_status: "pending",
    event_at: params.occurredAt.toISOString(),
  };
  const { error: upsertError } = await params.supabase
    .from("erp_notifications")
    .upsert({
      tenant_id: params.message.tenantId,
      type,
      title: params.title,
      body: params.body,
      route: null,
      entity_type: "message",
      entity_id: params.message.id,
      severity: params.status === "failed" ? "critical" : "success",
      data: baseData,
      occurred_at: params.occurredAt.toISOString(),
      read_at: params.readAt ?? null,
    }, {
      onConflict: "tenant_id,type,entity_type,entity_id",
      ignoreDuplicates: true,
    });
  if (upsertError) throw upsertError;

  const { data, error } = await params.supabase
    .from("erp_notifications")
    .select("id, data")
    .eq("tenant_id", params.message.tenantId)
    .eq("type", type)
    .eq("entity_type", "message")
    .eq("entity_id", params.message.id)
    .maybeSingle();
  if (error) throw error;
  if (!data) throw new Error("status_alert_ledger_not_found");

  const existingData = recordValue(data.data);
  if (existingData.activation_id !== params.message.config.activationId) {
    const { error: resetError } = await params.supabase
      .from("erp_notifications")
      .update({
        title: params.title,
        body: params.body,
        severity: params.status === "failed" ? "critical" : "success",
        data: baseData,
        occurred_at: params.occurredAt.toISOString(),
        read_at: params.readAt ?? null,
      })
      .eq("id", data.id);
    if (resetError) throw resetError;
    return { id: String(data.id), data: baseData };
  }
  return { id: String(data.id), data: existingData };
}

async function updateStatusAlertLedger(params: {
  supabase: SupabaseClientLike;
  ledger: StatusAlertLedger;
  updates: JsonRecord;
}) {
  const nextData = { ...params.ledger.data, ...params.updates };
  const { error } = await params.supabase
    .from("erp_notifications")
    .update({ data: nextData })
    .eq("id", params.ledger.id);
  if (error) throw error;
  params.ledger.data = nextData;
}

async function submitStatusAlertEmail(params: {
  supabase: SupabaseClientLike;
  message: StatusAlertMessage;
  ledger: StatusAlertLedger;
  status: WhatsAppTerminalStatus | "verification";
  subject: string;
  html: string;
  text: string;
}) {
  if (params.ledger.data.email_delivery_status === "submitted") {
    return { outcome: "already_submitted" as const };
  }
  if (!RESEND_API_KEY) throw new Error("status_alert_resend_not_configured");

  const outcome = await sendWithResend({
    apiKey: RESEND_API_KEY,
    idempotencyKey: whatsappStatusAlertIdempotencyKey(
      params.message.config,
      params.status,
    ),
    from: STATUS_ALERT_SENDER,
    to: params.message.config.recipientEmail,
    replyTo: STATUS_ALERT_REPLY_TO,
    subject: params.subject,
    html: params.html,
    text: params.text,
    tags: [
      { name: "alert", value: "whatsapp_status" },
      { name: "message_id", value: params.message.id },
      { name: "status", value: params.status },
    ],
  });

  if (outcome.kind === "submitted") {
    await updateStatusAlertLedger({
      supabase: params.supabase,
      ledger: params.ledger,
      updates: {
        email_delivery_status: "submitted",
        email_provider: "resend",
        email_provider_message_id: outcome.providerMessageId,
        email_submitted_at: new Date().toISOString(),
        email_error_class: null,
        email_error_message: null,
      },
    });
    return { outcome: "submitted" as const, providerMessageId: outcome.providerMessageId };
  }

  await updateStatusAlertLedger({
    supabase: params.supabase,
    ledger: params.ledger,
    updates: {
      email_delivery_status: outcome.kind === "retry" ? "retry" : "permanent_failure",
      email_error_class: outcome.errorClass,
      email_error_message: outcome.message.slice(0, 500),
      email_last_attempt_at: new Date().toISOString(),
    },
  });
  throw new Error(`status_alert_email_${outcome.errorClass}`);
}

async function deliverConfiguredStatusAlert(params: {
  supabase: SupabaseClientLike;
  messageId?: string | null;
  externalMessageId: string;
  statusValue: unknown;
  statusPayload: JsonRecord;
}) {
  const status = terminalWhatsAppStatus(params.statusValue);
  if (!status) return { outcome: "not_terminal" as const };
  const message = await resolveStatusAlertMessage({
    supabase: params.supabase,
    messageId: params.messageId,
    externalMessageId: params.externalMessageId,
  });
  if (!message) return { outcome: "not_configured" as const };
  if (message.externalMessageId !== params.externalMessageId) {
    throw new Error("status_alert_external_message_mismatch");
  }
  if (!message.config.notifyStatuses.includes(status)) {
    return { outcome: "status_not_configured" as const };
  }

  const occurredAt = whatsappStatusOccurredAt(params.statusPayload);
  const rendered = renderWhatsAppStatusEmail({
    config: message.config,
    status,
    occurredAt,
    providerError: whatsappProviderErrorSummary(params.statusPayload),
  });
  const ledger = await ensureStatusAlertLedger({
    supabase: params.supabase,
    message,
    status,
    occurredAt,
    title: rendered.subject,
    body: rendered.text.split("\n")[0],
  });
  return await submitStatusAlertEmail({
    supabase: params.supabase,
    message,
    ledger,
    status,
    ...rendered,
  });
}

async function handleStatusAlertOperatorRequest(
  req: Request,
  supabase: SupabaseClientLike,
) {
  const suppliedSecret = req.headers.get("x-whatsapp-status-alert-secret") ?? "";
  if (
    !WHATSAPP_STATUS_ALERT_TEST_SECRET ||
    !constantTimeEqual(suppliedSecret, WHATSAPP_STATUS_ALERT_TEST_SECRET)
  ) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }
  const declaredLength = Number(req.headers.get("content-length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > 16 * 1024) {
    return jsonResponse({ error: "Request too large" }, 413);
  }
  let body: JsonRecord;
  try {
    body = recordValue(await req.json());
  } catch {
    return jsonResponse({ error: "Invalid JSON" }, 400);
  }
  const action = stringValue(body.action);
  const messageId = stringValue(body.message_id);
  if (!messageId || (action !== "verify" && action !== "reconcile")) {
    return jsonResponse({ error: "Invalid operator action" }, 400);
  }

  const message = await resolveStatusAlertMessage({ supabase, messageId });
  if (!message) return jsonResponse({ error: "Configured alert not found" }, 404);
  if (action === "reconcile") {
    const currentStatus = terminalWhatsAppStatus(message.externalStatus);
    if (!currentStatus) {
      return jsonResponse({ reconciled: true, outcome: "not_terminal" });
    }
    const { data, error } = await supabase
      .from("whatsapp_webhook_events")
      .select("payload, created_at")
      .eq("event_type", "status")
      .like("event_key", `status:${message.externalMessageId}:${currentStatus}:%`)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (error) throw error;
    const payload = recordValue(data?.payload);
    const outcome = await deliverConfiguredStatusAlert({
      supabase,
      messageId: message.id,
      externalMessageId: message.externalMessageId,
      statusValue: currentStatus,
      statusPayload: Object.keys(payload).length
        ? payload
        : { status: currentStatus, timestamp: Math.floor(Date.now() / 1000).toString() },
    });
    return jsonResponse({ reconciled: true, outcome });
  }

  const rendered = renderWhatsAppStatusAlertVerificationEmail(message.config);
  const occurredAt = new Date();
  const ledger = await ensureStatusAlertLedger({
    supabase,
    message,
    status: "verification",
    occurredAt,
    title: rendered.subject,
    body: rendered.text.split("\n")[0],
    readAt: occurredAt.toISOString(),
  });
  const outcome = await submitStatusAlertEmail({
    supabase,
    message,
    ledger,
    status: "verification",
    ...rendered,
  });
  return jsonResponse({ verified: true, outcome });
}

async function createHmacSha256Hex(secret: string, payload: string) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(payload),
  );
  return Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function verifyMetaSignature(req: Request, rawBody: string) {
  if (!META_APP_SECRET) {
    console.error("❌ [WHATSAPP-WEBHOOK] META_APP_SECRET is not configured");
    return false;
  }
  const header = req.headers.get("x-hub-signature-256");
  if (!header?.startsWith("sha256=")) return false;
  const expected = header.slice("sha256=".length);
  const actual = await createHmacSha256Hex(META_APP_SECRET, rawBody);
  if (expected.length !== actual.length) return false;
  let difference = 0;
  for (let index = 0; index < expected.length; index += 1) {
    difference |= expected.charCodeAt(index) ^ actual.charCodeAt(index);
  }
  return difference === 0;
}

function getMessageType(message: JsonRecord) {
  return String(message.type ?? "text");
}

function getMessageBody(message: JsonRecord) {
  const type = getMessageType(message);
  if (type === "text") return String((message.text as JsonRecord | undefined)?.body ?? "");
  if (type === "interactive") {
    const interactive = message.interactive as JsonRecord | undefined;
    const buttonReply = interactive?.button_reply as JsonRecord | undefined;
    const listReply = interactive?.list_reply as JsonRecord | undefined;
    return String(buttonReply?.title ?? listReply?.title ?? buttonReply?.id ?? listReply?.id ?? "");
  }
  if (type === "button") return String((message.button as JsonRecord | undefined)?.text ?? "");
  if (type === "image") {
    return String((message.image as JsonRecord | undefined)?.caption ?? "Imagen recibida");
  }
  if (type === "document") {
    const document = message.document as JsonRecord | undefined;
    return String(document?.caption ?? document?.filename ?? "Documento recibido");
  }
  if (type === "audio") return "Audio recibido";
  if (type === "video") {
    return String((message.video as JsonRecord | undefined)?.caption ?? "Video recibido");
  }
  if (type === "location") return "Ubicación compartida";
  return type;
}

function mediaRecordForMessage(message: JsonRecord) {
  const messageType = getMessageType(message);
  const candidates = [
    message[messageType],
    message.image,
    message.document,
    message.video,
    message.audio,
    message.sticker,
  ];
  for (const candidate of candidates) {
    if (!candidate || typeof candidate !== "object") continue;
    const media = candidate as JsonRecord;
    const mediaId = stringValue(media.id);
    if (mediaId) return { media, messageType, mediaId };
  }
  return null;
}

function sanitizedFilename(value: unknown, fallback: string) {
  const source = stringValue(value) ?? fallback;
  // deno-lint-ignore no-control-regex -- intentional C0 filename sanitization.
  const unsafeFilenameCharacters = /[\/\x00-\x1f\x7f]+/g;
  const result = source
    .replaceAll(unsafeFilenameCharacters, "_")
    .trim()
    .slice(0, 200);
  return result || fallback;
}

function fallbackFilename(messageType: string, contentType: string) {
  const normalized = contentType.split(";")[0].trim().toLowerCase();
  const extension = normalized === "image/png"
    ? "png"
    : normalized === "image/gif"
    ? "gif"
    : normalized === "image/webp"
    ? "webp"
    : normalized === "application/pdf"
    ? "pdf"
    : normalized === "video/mp4"
    ? "mp4"
    : normalized === "video/3gpp"
    ? "3gp"
    : normalized === "audio/mpeg"
    ? "mp3"
    : normalized === "audio/ogg"
    ? "ogg"
    : normalized === "audio/mp4"
    ? "m4a"
    : normalized === "audio/aac"
    ? "aac"
    : "jpg";
  const label = messageType === "document"
    ? "documento"
    : messageType === "audio"
    ? "audio"
    : messageType === "video"
    ? "video"
    : "imagen";
  return `${label}.${extension}`;
}

async function readBoundedBytes(response: Response, maxBytes: number) {
  const length = Number(response.headers.get("content-length") ?? "");
  if (Number.isFinite(length) && length > maxBytes) {
    throw new Error("attachment_too_large");
  }
  if (!response.body) return new Uint8Array();
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maxBytes) throw new Error("attachment_too_large");
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const result = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return result;
}

async function mergeMessageMetadata(
  supabase: SupabaseClientLike,
  message: PersistedInboundMessage,
  metadataUpdates: JsonRecord,
) {
  if (!Object.keys(metadataUpdates).length) return;
  const { error } = await supabase
    .from("messages")
    .update({ metadata: { ...message.metadata, ...metadataUpdates } })
    .eq("id", message.id)
    .eq("tenant_id", message.tenant_id);
  if (error) throw error;
  message.metadata = { ...message.metadata, ...metadataUpdates };
}

async function resolvePersistedInboundMessage(params: {
  supabase: SupabaseClientLike;
  ingestResult: JsonRecord | null;
  externalMessageId: string;
}) {
  let query = params.supabase
    .from("messages")
    .select("id, tenant_id, conversation_id, metadata");
  const messageId = stringValue(params.ingestResult?.message_id);
  query = messageId ? query.eq("id", messageId) : query
    .eq("external_provider", "whatsapp")
    .eq("external_message_id", params.externalMessageId);
  const { data, error } = await query.maybeSingle();
  if (error) throw error;
  if (!data) throw new Error("persisted_inbound_message_not_found");
  return {
    id: String(data.id),
    tenant_id: String(data.tenant_id),
    conversation_id: String(data.conversation_id),
    metadata: (data.metadata ?? {}) as JsonRecord,
  } as PersistedInboundMessage;
}

async function existingAttachmentReference(
  supabase: SupabaseClientLike,
  message: PersistedInboundMessage,
) {
  const { data, error } = await supabase
    .from("messaging_attachments")
    .select("id, storage_path, original_filename, extension, declared_mime_type, size_bytes")
    .eq("message_id", message.id)
    .eq("tenant_id", message.tenant_id)
    .eq("conversation_id", message.conversation_id)
    .eq("status", "attached")
    .maybeSingle();
  if (error) throw error;
  if (!data) return null;
  return attachmentReference({
    attachmentId: String(data.id),
    storagePath: String(data.storage_path),
    filename: String(data.original_filename),
    extension: String(data.extension),
    contentType: String(data.declared_mime_type),
    sizeBytes: Number(data.size_bytes),
  });
}

async function hydrateInboundMedia(params: {
  supabase: SupabaseClientLike;
  message: JsonRecord;
  persisted: PersistedInboundMessage;
}) {
  const mediaSource = mediaRecordForMessage(params.message);
  if (!mediaSource) return { result: "not_media" as const };

  if (stringValue(params.persisted.metadata.attachment_id)) {
    return { result: "already_attached" as const };
  }
  const existingReference = await existingAttachmentReference(
    params.supabase,
    params.persisted,
  );
  if (existingReference) {
    await mergeMessageMetadata(params.supabase, params.persisted, existingReference);
    return { result: "repaired_reference" as const };
  }

  const providerMetadata: JsonRecord = {
    whatsapp_media_id: mediaSource.mediaId,
    media_id: mediaSource.mediaId,
    media_source: "whatsapp_cloud_api",
  };
  if (!WHATSAPP_ACCESS_TOKEN) throw new Error("missing_whatsapp_access_token");

  const infoResponse = await fetch(
    `https://graph.facebook.com/${WHATSAPP_API_VERSION}/${mediaSource.mediaId}`,
    { headers: { Authorization: `Bearer ${WHATSAPP_ACCESS_TOKEN}` } },
  );
  const info = await infoResponse.json().catch(() => ({})) as JsonRecord;
  if (!infoResponse.ok) throw new Error(`media_metadata_fetch_${infoResponse.status}`);
  const temporaryUrl = stringValue(info.url);
  const announcedType = stringValue(info.mime_type) ?? stringValue(mediaSource.media.mime_type);
  const announcedSize = Number(info.file_size ?? mediaSource.media.file_size ?? "");
  if (!temporaryUrl || !announcedType) throw new Error("media_metadata_incomplete");

  const filename = sanitizedFilename(
    mediaSource.media.filename,
    fallbackFilename(mediaSource.messageType, announcedType),
  );
  let contract;
  try {
    contract = validateMessagingAttachment({
      filename,
      contentType: announcedType,
      sizeBytes: Number.isSafeInteger(announcedSize) && announcedSize > 0 ? announcedSize : 1,
    });
  } catch (error) {
    await mergeMessageMetadata(params.supabase, params.persisted, {
      ...providerMetadata,
      media_unavailable_reason: String(error),
    });
    return { result: "rejected" as const, reason: String(error) };
  }

  const mediaResponse = await fetch(temporaryUrl, {
    headers: { Authorization: `Bearer ${WHATSAPP_ACCESS_TOKEN}` },
  });
  if (!mediaResponse.ok) throw new Error(`media_download_${mediaResponse.status}`);
  const responseType = stringValue(mediaResponse.headers.get("content-type")) ?? announcedType;
  if (responseType.split(";")[0].trim().toLowerCase() !== contract.contentType) {
    await mergeMessageMetadata(params.supabase, params.persisted, {
      ...providerMetadata,
      media_unavailable_reason: "media_mime_mismatch",
    });
    return { result: "rejected" as const, reason: "media_mime_mismatch" };
  }

  let bytes: Uint8Array;
  try {
    bytes = await readBoundedBytes(mediaResponse, contract.maxBytes);
    validateMessagingAttachment({
      filename,
      contentType: responseType,
      sizeBytes: bytes.byteLength,
    });
  } catch (error) {
    await mergeMessageMetadata(params.supabase, params.persisted, {
      ...providerMetadata,
      media_unavailable_reason: String(error),
    });
    return { result: "rejected" as const, reason: String(error) };
  }

  const attachmentId = crypto.randomUUID();
  const storagePath = buildPrivateMessagingAttachmentPath({
    tenantId: params.persisted.tenant_id,
    conversationId: params.persisted.conversation_id,
    attachmentId,
    extension: contract.extension,
  });
  const { error: reservationError } = await params.supabase
    .from("messaging_attachments")
    .insert({
      id: attachmentId,
      tenant_id: params.persisted.tenant_id,
      conversation_id: params.persisted.conversation_id,
      storage_bucket: PRIVATE_MESSAGING_BUCKET,
      storage_path: storagePath,
      original_filename: filename,
      extension: contract.extension,
      declared_mime_type: contract.contentType,
      size_bytes: bytes.byteLength,
      status: "reserved",
    });
  if (reservationError) {
    const racedReference = await existingAttachmentReference(
      params.supabase,
      params.persisted,
    );
    if (!racedReference) throw reservationError;
    await mergeMessageMetadata(params.supabase, params.persisted, racedReference);
    return { result: "repaired_race" as const };
  }

  const { error: uploadError } = await params.supabase.storage
    .from(PRIVATE_MESSAGING_BUCKET)
    .upload(
      storagePath,
      new Blob([bytes.slice().buffer as ArrayBuffer], {
        type: contract.contentType,
      }),
      {
        contentType: contract.contentType,
        upsert: false,
      },
    );
  if (uploadError) {
    await params.supabase.from("messaging_attachments").update({
      status: "failed",
      failure_code: "private_storage_upload_failed",
      failed_at: new Date().toISOString(),
    }).eq("id", attachmentId);
    throw uploadError;
  }

  const { error: registryError } = await params.supabase
    .from("messaging_attachments")
    .update({
      message_id: params.persisted.id,
      status: "attached",
      attached_at: new Date().toISOString(),
    })
    .eq("id", attachmentId)
    .eq("status", "reserved");
  if (registryError) {
    await params.supabase.storage.from(PRIVATE_MESSAGING_BUCKET).remove([storagePath]);
    await params.supabase.from("messaging_attachments").update({
      status: "failed",
      failure_code: "attachment_registry_finalize_failed",
      failed_at: new Date().toISOString(),
    }).eq("id", attachmentId);
    throw registryError;
  }

  const reference = {
    ...providerMetadata,
    ...attachmentReference({
      attachmentId,
      storagePath,
      filename,
      extension: contract.extension,
      contentType: contract.contentType,
      sizeBytes: bytes.byteLength,
    }),
  };
  // If this write fails, the next Meta retry finds the registry row above and
  // repairs the message without downloading/uploading the media a second time.
  await mergeMessageMetadata(params.supabase, params.persisted, reference);
  return { result: "attached" as const };
}

function parseActionTarget(message: JsonRecord): WhatsAppActionTarget | null {
  const interactive = message.interactive as JsonRecord | undefined;
  const buttonReply = interactive?.button_reply as JsonRecord | undefined;
  const listReply = interactive?.list_reply as JsonRecord | undefined;
  const button = message.button as JsonRecord | undefined;
  return parseWhatsAppActionToken(
    buttonReply?.id ?? listReply?.id ?? button?.payload,
  );
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method === "GET") {
    const url = new URL(req.url);
    const accepted = url.searchParams.get("hub.mode") === "subscribe" &&
      url.searchParams.get("hub.verify_token") === WHATSAPP_VERIFY_TOKEN &&
      Boolean(url.searchParams.get("hub.challenge"));
    return accepted
      ? new Response(url.searchParams.get("hub.challenge"), { status: 200 })
      : new Response("Forbidden", { status: 403 });
  }
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    return jsonResponse({ error: "Missing Supabase environment variables" }, 500);
  }

  const requestUrl = new URL(req.url);
  if (requestUrl.pathname.endsWith("/verify-status-email-alert")) {
    const operatorClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    try {
      return await handleStatusAlertOperatorRequest(req, operatorClient);
    } catch (error) {
      console.error("❌ [WHATSAPP-WEBHOOK] Status email alert operator error", error);
      return jsonResponse({ error: "Status email alert operation failed" }, 500);
    }
  }

  const rawBody = await req.text();
  if (!await verifyMetaSignature(req, rawBody)) {
    return jsonResponse({ error: "Invalid Meta signature" }, 401);
  }
  let payload: JsonRecord;
  try {
    payload = JSON.parse(rawBody) as JsonRecord;
  } catch (_) {
    return jsonResponse({ error: "Invalid JSON payload" }, 400);
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const processedMessages: unknown[] = [];
  const processedStatuses: unknown[] = [];
  const automationResults: unknown[] = [];
  const deterministicRejections: unknown[] = [];
  const operationalErrors: string[] = [];
  const entries = Array.isArray(payload.entry) ? payload.entry : [];

  for (const entry of entries) {
    const changes = Array.isArray((entry as JsonRecord).changes)
      ? (entry as JsonRecord).changes as JsonRecord[]
      : [];
    for (const change of changes) {
      const value = (change.value ?? {}) as JsonRecord;
      const providerMetadata = (value.metadata ?? {}) as JsonRecord;
      const phoneNumberId = String(providerMetadata.phone_number_id ?? "");
      const contacts = Array.isArray(value.contacts) ? value.contacts as JsonRecord[] : [];
      const messages = Array.isArray(value.messages) ? value.messages as JsonRecord[] : [];
      const statuses = Array.isArray(value.statuses) ? value.statuses as JsonRecord[] : [];

      for (const status of statuses) {
        const externalMessageId = String(status.id ?? "");
        const statusValue = String(status.status ?? "");
        if (!phoneNumberId || !externalMessageId || !statusValue) continue;
        try {
          const { data, error } = await supabase.rpc("record_whatsapp_message_status", {
            p_phone_number_id: phoneNumberId,
            p_external_message_id: externalMessageId,
            p_status: statusValue,
            p_payload: status,
          });
          if (error) throw error;
          processedStatuses.push(data);
          const recordedStatus = recordValue(data);
          const alertResult = await deliverConfiguredStatusAlert({
            supabase,
            messageId: stringValue(recordedStatus.message_id),
            externalMessageId,
            statusValue,
            statusPayload: status,
          });
          if (
            alertResult.outcome !== "not_terminal" &&
            alertResult.outcome !== "not_configured" &&
            alertResult.outcome !== "status_not_configured"
          ) {
            automationResults.push({
              kind: "whatsapp_status_email_alert",
              external_message_id: externalMessageId,
              status: statusValue,
              outcome: alertResult.outcome,
            });
          }
        } catch (error) {
          console.error("❌ [WHATSAPP-WEBHOOK] Status processing error", error);
          operationalErrors.push(`status:${externalMessageId}:${String(error)}`);
        }
      }

      for (const message of messages) {
        const waId = String(message.from ?? contacts[0]?.wa_id ?? "");
        const externalMessageId = String(message.id ?? "");
        if (!phoneNumberId || !waId || !externalMessageId) {
          deterministicRejections.push({ reason: "missing_message_identity" });
          continue;
        }

        const inboundPayload = {
          message,
          contact: contacts[0] ?? null,
          metadata: providerMetadata,
        };
        try {
          // Ingest and idempotency receipt happen before any provider download.
          const { data, error } = await supabase.rpc(
            "ingest_whatsapp_inbound_message",
            {
              p_phone_number_id: phoneNumberId,
              p_external_message_id: externalMessageId,
              p_wa_id: waId,
              p_phone_number: waId,
              p_contact_name: String(
                ((contacts[0]?.profile as JsonRecord | undefined)?.name) ?? "",
              ),
              p_message_type: getMessageType(message),
              p_message_body: getMessageBody(message),
              p_payload: inboundPayload,
              p_context_type: null,
              p_context_id: null,
            },
          );
          if (error) throw error;
          const ingestResult = (data ?? null) as JsonRecord | null;
          processedMessages.push(ingestResult);
          if (ingestResult?.ignored) continue;

          const persisted = await resolvePersistedInboundMessage({
            supabase,
            ingestResult,
            externalMessageId,
          });
          const mediaResult = await hydrateInboundMedia({
            supabase,
            message,
            persisted,
          });
          if (mediaResult.result === "rejected") {
            deterministicRejections.push({
              external_message_id: externalMessageId,
              reason: mediaResult.reason,
            });
          }

          const actionTarget = parseActionTarget(message);
          if (actionTarget?.kind === "job") {
            const replyContext = message.context as JsonRecord | undefined;
            const replyToExternalMessageId = stringValue(replyContext?.id);
            if (
              actionTarget.legacy ||
              !actionTarget.revisionMs ||
              !replyToExternalMessageId
            ) {
              await mergeMessageMetadata(supabase, persisted, {
                action_rejected: true,
                action_rejection_reason: "legacy_or_unbound_job_action",
              });
              deterministicRejections.push({
                external_message_id: externalMessageId,
                reason: "legacy_or_unbound_job_action",
              });
              continue;
            }
            // Deliberately runs for duplicate deliveries too. The SQL command
            // is idempotent by external_message_id and repairs partial retries.
            const { data: actionData, error: actionError } = await supabase.rpc(
              "apply_whatsapp_job_action",
              {
                p_job_id: actionTarget.targetId,
                p_action: actionTarget.action,
                p_external_message_id: externalMessageId,
                p_reply_to_external_message_id: replyToExternalMessageId,
                p_action_revision_ms: actionTarget.revisionMs,
                p_payload: inboundPayload,
              },
            );
            if (actionError) throw actionError;
            automationResults.push(actionData);
          } else if (actionTarget?.kind === "invoice") {
            // Payment/receipt state is provider-driven. A chat reply is kept as
            // read-only evidence and must never confirm a fiscal object.
            await mergeMessageMetadata(supabase, persisted, {
              action_rejected: true,
              action_rejection_reason: "invoice_actions_are_read_only",
            });
            deterministicRejections.push({
              external_message_id: externalMessageId,
              reason: "invoice_actions_are_read_only",
            });
          }
        } catch (error) {
          console.error("❌ [WHATSAPP-WEBHOOK] Message processing error", error);
          operationalErrors.push(`message:${externalMessageId}:${String(error)}`);
        }
      }
    }
  }

  const hasOperationalFailure = operationalErrors.length > 0;
  return jsonResponse({
    ok: !hasOperationalFailure,
    retryable: hasOperationalFailure,
    processed_messages: processedMessages.length,
    processed_statuses: processedStatuses.length,
    automations: automationResults.length,
    deterministic_rejections: deterministicRejections,
    errors: operationalErrors,
  }, hasOperationalFailure ? 500 : 200);
});
