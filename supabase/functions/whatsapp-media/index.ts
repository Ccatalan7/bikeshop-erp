import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  attachmentReference,
  buildPrivateMessagingAttachmentPath,
  isCanonicalPrivateAttachmentPath,
  isTrustedLegacyMessagingUrl,
  MESSAGING_ATTACHMENT_SIGNED_URL_TTL_SECONDS,
  PRIVATE_MESSAGING_BUCKET,
  stringValue,
  validateMessagingAttachment,
} from "../_shared/messaging_attachments.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const WHATSAPP_ACCESS_TOKEN = Deno.env.get("WHATSAPP_ACCESS_TOKEN") ?? "";
const WHATSAPP_API_VERSION = Deno.env.get("WHATSAPP_API_VERSION") ?? "v23.0";

type JsonRecord = Record<string, unknown>;
// deno-lint-ignore no-explicit-any
type SupabaseClientLike = ReturnType<typeof createClient<any>>;

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function mediaSourceFromMetadata(metadata: JsonRecord) {
  const rawPayload = metadata.raw_payload as JsonRecord | undefined;
  const webhookMessage = rawPayload?.message as JsonRecord | undefined;
  const rawMedia = rawPayload?.media as JsonRecord | undefined;
  const metadataMedia = metadata.media as JsonRecord | undefined;
  const messageType = stringValue(metadata.message_type) ??
    stringValue(webhookMessage?.type) ??
    "image";
  const candidates = [
    rawMedia,
    metadataMedia,
    webhookMessage?.[messageType],
    webhookMessage?.image,
    webhookMessage?.document,
    webhookMessage?.video,
    webhookMessage?.audio,
    webhookMessage?.sticker,
    metadata,
  ];

  for (const candidate of candidates) {
    if (!candidate || typeof candidate !== "object") continue;
    const record = candidate as JsonRecord;
    const mediaId = stringValue(record.id) ??
      stringValue(record.whatsapp_media_id) ??
      stringValue(record.media_id);
    if (mediaId) return { media: record, messageType, mediaId };
  }
  return null;
}

function privateReference(metadata: JsonRecord) {
  return {
    attachmentId: stringValue(metadata.attachment_id),
    bucket: stringValue(metadata.storage_bucket) ?? stringValue(metadata.storageBucket),
    path: stringValue(metadata.storage_path) ?? stringValue(metadata.storagePath),
    extension: stringValue(metadata.extension),
  };
}

function legacyUrl(metadata: JsonRecord, content: unknown) {
  const candidates = [
    metadata.url,
    metadata.media_url,
    metadata.image_url,
    metadata.file_url,
    metadata.documentUrl,
    metadata.document_url,
    content,
  ];
  return candidates.find((candidate) => isTrustedLegacyMessagingUrl(candidate, SUPABASE_URL)) as
    | string
    | undefined;
}

function sanitizedFilename(value: unknown, fallback: string) {
  const candidate = stringValue(value) ?? fallback;
  // deno-lint-ignore no-control-regex -- intentional C0 filename sanitization.
  const unsafeFilenameCharacters = /[\/\x00-\x1f\x7f]+/g;
  const sanitized = candidate
    .replaceAll(unsafeFilenameCharacters, "_")
    .trim()
    .slice(0, 200);
  return sanitized || fallback;
}

function fallbackFilename(messageType: string, contentType: string) {
  const extension = contentType === "image/png"
    ? "png"
    : contentType === "image/gif"
    ? "gif"
    : contentType === "image/webp"
    ? "webp"
    : contentType === "application/pdf"
    ? "pdf"
    : contentType === "video/mp4"
    ? "mp4"
    : contentType === "video/3gpp"
    ? "3gp"
    : contentType === "audio/mpeg"
    ? "mp3"
    : contentType === "audio/ogg"
    ? "ogg"
    : contentType === "audio/mp4"
    ? "m4a"
    : contentType === "audio/aac"
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

  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

async function signedUrl(
  adminClient: SupabaseClientLike,
  path: string,
) {
  const { data, error } = await adminClient.storage
    .from(PRIVATE_MESSAGING_BUCKET)
    .createSignedUrl(path, MESSAGING_ATTACHMENT_SIGNED_URL_TTL_SECONDS);
  if (error || !data?.signedUrl) throw error ?? new Error("signed_url_failed");
  return data.signedUrl;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
    return jsonResponse({ error: "Missing Supabase environment variables" }, 500);
  }

  const authorization = req.headers.get("Authorization");
  if (!authorization) return jsonResponse({ error: "Missing authentication" }, 401);
  const authClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: userData, error: userError } = await authClient.auth.getUser();
  if (userError || !userData.user) {
    return jsonResponse({ error: "Missing authentication" }, 401);
  }

  let body: JsonRecord;
  try {
    body = await req.json() as JsonRecord;
  } catch (_) {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }
  const messageId = stringValue(body.messageId);
  if (!messageId) return jsonResponse({ error: "messageId is required" }, 400);

  // This RLS read is the authorization boundary. The service-role client is
  // used only after the caller proves visibility of this exact message.
  const { data: visibleMessage, error: visibleError } = await authClient
    .from("messages")
    .select("id, conversation_id, tenant_id, content, type, metadata")
    .eq("id", messageId)
    .maybeSingle();
  if (visibleError) {
    console.error("❌ [WHATSAPP-MEDIA] Message visibility check failed", visibleError);
    return jsonResponse({ error: "Unable to read message" }, 500);
  }
  if (!visibleMessage) return jsonResponse({ error: "Message not found" }, 404);

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const metadata = (visibleMessage.metadata ?? {}) as JsonRecord;
  const reference = privateReference(metadata);
  if (
    reference.attachmentId &&
    reference.bucket === PRIVATE_MESSAGING_BUCKET &&
    reference.path &&
    reference.extension &&
    isCanonicalPrivateAttachmentPath({
      path: reference.path,
      tenantId: String(visibleMessage.tenant_id),
      conversationId: String(visibleMessage.conversation_id),
      attachmentId: reference.attachmentId,
      extension: reference.extension,
    })
  ) {
    const { data: attachment } = await adminClient
      .from("messaging_attachments")
      .select("id")
      .eq("id", reference.attachmentId)
      .eq("tenant_id", visibleMessage.tenant_id)
      .eq("conversation_id", visibleMessage.conversation_id)
      .eq("message_id", visibleMessage.id)
      .eq("status", "attached")
      .maybeSingle();
    if (!attachment) return jsonResponse({ error: "Attachment reference is invalid" }, 409);
    try {
      return jsonResponse({
        url: await signedUrl(adminClient, reference.path),
        metadata: {},
        already_hydrated: true,
      });
    } catch (error) {
      console.error("❌ [WHATSAPP-MEDIA] Signed URL failed", error);
      return jsonResponse({ error: "Unable to authorize attachment preview" }, 500);
    }
  }

  // Recover a partial prior hydration where the private registry/object was
  // committed but the message metadata acknowledgement was lost.
  const { data: registeredAttachment, error: registeredAttachmentError } = await adminClient
    .from("messaging_attachments")
    .select(
      "id, storage_path, original_filename, extension, declared_mime_type, size_bytes",
    )
    .eq("message_id", visibleMessage.id)
    .eq("tenant_id", visibleMessage.tenant_id)
    .eq("conversation_id", visibleMessage.conversation_id)
    .eq("status", "attached")
    .maybeSingle();
  if (registeredAttachmentError) {
    console.error(
      "❌ [WHATSAPP-MEDIA] Registered attachment lookup failed",
      registeredAttachmentError,
    );
    return jsonResponse({ error: "Unable to inspect attachment registry" }, 500);
  }
  if (registeredAttachment?.storage_path) {
    const recoveredMetadata = attachmentReference({
      attachmentId: String(registeredAttachment.id),
      storagePath: String(registeredAttachment.storage_path),
      filename: String(registeredAttachment.original_filename),
      extension: String(registeredAttachment.extension),
      contentType: String(registeredAttachment.declared_mime_type),
      sizeBytes: Number(registeredAttachment.size_bytes),
    });
    const { error: repairError } = await adminClient
      .from("messages")
      .update({ metadata: { ...metadata, ...recoveredMetadata } })
      .eq("id", visibleMessage.id)
      .eq("tenant_id", visibleMessage.tenant_id);
    if (repairError) {
      console.error("❌ [WHATSAPP-MEDIA] Attachment reference recovery failed", repairError);
      return jsonResponse({ error: "Unable to recover attachment reference" }, 500);
    }
    return jsonResponse({
      url: await signedUrl(adminClient, String(registeredAttachment.storage_path)),
      metadata: recoveredMetadata,
      already_hydrated: true,
      recovered: true,
    });
  }

  // Existing public objects remain readable during migration, but arbitrary
  // external URLs are never returned to an auto-rendering client.
  const existingLegacyUrl = legacyUrl(metadata, visibleMessage.content);
  if (existingLegacyUrl) {
    return jsonResponse({
      url: existingLegacyUrl,
      metadata: {},
      already_hydrated: true,
      legacy: true,
    });
  }

  if (!WHATSAPP_ACCESS_TOKEN) {
    return jsonResponse({ error: "WhatsApp media access is not configured" }, 500);
  }
  const source = mediaSourceFromMetadata(metadata);
  if (!source) return jsonResponse({ error: "Message has no WhatsApp media id" }, 400);

  const infoResponse = await fetch(
    `https://graph.facebook.com/${WHATSAPP_API_VERSION}/${source.mediaId}`,
    { headers: { Authorization: `Bearer ${WHATSAPP_ACCESS_TOKEN}` } },
  );
  const info = await infoResponse.json().catch(() => ({})) as JsonRecord;
  if (!infoResponse.ok) {
    console.error("❌ [WHATSAPP-MEDIA] Media metadata fetch failed", info);
    return jsonResponse({ error: "Unable to fetch WhatsApp media metadata" }, 502);
  }
  const temporaryUrl = stringValue(info.url);
  const announcedType = stringValue(info.mime_type) ?? stringValue(source.media.mime_type);
  const announcedSize = Number(info.file_size ?? source.media.file_size ?? "");
  if (!temporaryUrl || !announcedType) {
    return jsonResponse({ error: "WhatsApp media metadata is incomplete" }, 502);
  }

  const filename = sanitizedFilename(
    source.media.filename,
    fallbackFilename(source.messageType, announcedType),
  );
  let preflight;
  try {
    preflight = validateMessagingAttachment({
      filename,
      contentType: announcedType,
      sizeBytes: Number.isSafeInteger(announcedSize) && announcedSize > 0 ? announcedSize : 1,
    });
  } catch (error) {
    console.error("❌ [WHATSAPP-MEDIA] Media rejected before download", error);
    return jsonResponse({ error: "Unsupported or oversized WhatsApp media" }, 415);
  }

  const mediaResponse = await fetch(temporaryUrl, {
    headers: { Authorization: `Bearer ${WHATSAPP_ACCESS_TOKEN}` },
  });
  if (!mediaResponse.ok) {
    return jsonResponse({ error: "Unable to download WhatsApp media" }, 502);
  }
  const responseType = stringValue(mediaResponse.headers.get("content-type")) ?? announcedType;
  if (responseType.split(";")[0].trim().toLowerCase() !== preflight.contentType) {
    return jsonResponse({ error: "WhatsApp media MIME mismatch" }, 415);
  }

  let bytes: Uint8Array;
  try {
    bytes = await readBoundedBytes(mediaResponse, preflight.maxBytes);
    validateMessagingAttachment({
      filename,
      contentType: responseType,
      sizeBytes: bytes.byteLength,
    });
  } catch (error) {
    console.error("❌ [WHATSAPP-MEDIA] Media byte validation failed", error);
    return jsonResponse({ error: "Unsupported or oversized WhatsApp media" }, 415);
  }

  const attachmentId = crypto.randomUUID();
  const storagePath = buildPrivateMessagingAttachmentPath({
    tenantId: String(visibleMessage.tenant_id),
    conversationId: String(visibleMessage.conversation_id),
    attachmentId,
    extension: preflight.extension,
  });
  const { error: reservationError } = await adminClient
    .from("messaging_attachments")
    .insert({
      id: attachmentId,
      tenant_id: visibleMessage.tenant_id,
      conversation_id: visibleMessage.conversation_id,
      storage_bucket: PRIVATE_MESSAGING_BUCKET,
      storage_path: storagePath,
      original_filename: filename,
      extension: preflight.extension,
      declared_mime_type: preflight.contentType,
      size_bytes: bytes.byteLength,
      status: "reserved",
    });
  if (reservationError) {
    console.error("❌ [WHATSAPP-MEDIA] Attachment reservation failed", reservationError);
    return jsonResponse({ error: "Unable to reserve WhatsApp media" }, 500);
  }

  const { error: uploadError } = await adminClient.storage
    .from(PRIVATE_MESSAGING_BUCKET)
    .upload(
      storagePath,
      new Blob([bytes.slice().buffer as ArrayBuffer], {
        type: preflight.contentType,
      }),
      {
        contentType: preflight.contentType,
        upsert: false,
      },
    );
  if (uploadError) {
    await adminClient.from("messaging_attachments").update({
      status: "failed",
      failure_code: "private_storage_upload_failed",
      failed_at: new Date().toISOString(),
    }).eq("id", attachmentId);
    console.error("❌ [WHATSAPP-MEDIA] Private upload failed", uploadError);
    return jsonResponse({ error: "Unable to store WhatsApp media" }, 500);
  }

  const { error: registryError } = await adminClient
    .from("messaging_attachments")
    .update({
      message_id: visibleMessage.id,
      status: "attached",
      attached_at: new Date().toISOString(),
    })
    .eq("id", attachmentId)
    .eq("status", "reserved");
  if (registryError) {
    await adminClient.storage.from(PRIVATE_MESSAGING_BUCKET).remove([storagePath]);
    await adminClient.from("messaging_attachments").update({
      status: "failed",
      failure_code: "attachment_registry_finalize_race",
      failed_at: new Date().toISOString(),
    }).eq("id", attachmentId);
    const { data: existing } = await adminClient
      .from("messaging_attachments")
      .select(
        "id, storage_path, original_filename, extension, declared_mime_type, size_bytes",
      )
      .eq("message_id", visibleMessage.id)
      .eq("status", "attached")
      .maybeSingle();
    if (existing?.storage_path) {
      const recoveredMetadata = attachmentReference({
        attachmentId: String(existing.id),
        storagePath: String(existing.storage_path),
        filename: String(existing.original_filename),
        extension: String(existing.extension),
        contentType: String(existing.declared_mime_type),
        sizeBytes: Number(existing.size_bytes),
      });
      const { error: repairError } = await adminClient
        .from("messages")
        .update({ metadata: { ...metadata, ...recoveredMetadata } })
        .eq("id", visibleMessage.id)
        .eq("tenant_id", visibleMessage.tenant_id);
      if (repairError) {
        console.error("❌ [WHATSAPP-MEDIA] Existing reference repair failed", repairError);
        return jsonResponse({ error: "Unable to repair attachment reference" }, 500);
      }
      return jsonResponse({
        url: await signedUrl(adminClient, String(existing.storage_path)),
        metadata: recoveredMetadata,
        already_hydrated: true,
      });
    }
    console.error("❌ [WHATSAPP-MEDIA] Attachment registry insert failed", registryError);
    return jsonResponse({ error: "Unable to register WhatsApp media" }, 500);
  }

  const metadataUpdates = attachmentReference({
    attachmentId,
    storagePath,
    filename,
    extension: preflight.extension,
    contentType: preflight.contentType,
    sizeBytes: bytes.byteLength,
  });
  const { error: updateError } = await adminClient
    .from("messages")
    .update({ metadata: { ...metadata, ...metadataUpdates } })
    .eq("id", visibleMessage.id)
    .eq("tenant_id", visibleMessage.tenant_id);
  if (updateError) {
    console.error("❌ [WHATSAPP-MEDIA] Message reference update failed", updateError);
    // Keep the committed private registry/object. The early recovery branch
    // above repairs message metadata on the next authenticated retry.
    return jsonResponse({ error: "Unable to attach stored WhatsApp media" }, 500);
  }

  try {
    return jsonResponse({
      url: await signedUrl(adminClient, storagePath),
      metadata: metadataUpdates,
      already_hydrated: false,
    });
  } catch (error) {
    console.error("❌ [WHATSAPP-MEDIA] Signed URL failed", error);
    return jsonResponse({ error: "Unable to authorize attachment preview" }, 500);
  }
});
