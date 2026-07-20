import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  attachmentReference,
  buildPrivateMessagingAttachmentPath,
  isTrustedLegacyMessagingUrl,
  validateMessagingAttachment,
} from "./messaging_attachments.ts";

const tenantId = "11111111-1111-4111-8111-111111111111";
const conversationId = "22222222-2222-4222-8222-222222222222";
const attachmentId = "33333333-3333-4333-8333-333333333333";

Deno.test("validates the extension, MIME and size before a read/upload", () => {
  assertEquals(
    validateMessagingAttachment({
      filename: "cotizacion.PDF",
      contentType: "application/pdf",
      sizeBytes: 1200,
    }),
    {
      extension: "pdf",
      contentType: "application/pdf",
      maxBytes: 20 * 1024 * 1024,
    },
  );

  assertThrows(
    () =>
      validateMessagingAttachment({
        filename: "foto.jpg",
        contentType: "text/html",
        sizeBytes: 1200,
      }),
    Error,
    "unsupported_attachment_type",
  );

  assertThrows(
    () =>
      validateMessagingAttachment({
        filename: "foto.jpg",
        contentType: "image/jpeg",
        sizeBytes: 5 * 1024 * 1024 + 1,
      }),
    Error,
    "attachment_too_large",
  );
});

Deno.test("builds a PII-free canonical private path and reference", () => {
  const storagePath = buildPrivateMessagingAttachmentPath({
    tenantId,
    conversationId,
    attachmentId,
    extension: "pdf",
  });
  assertEquals(
    storagePath,
    `${tenantId}/${conversationId}/${attachmentId}.pdf`,
  );
  assertEquals(
    attachmentReference({
      attachmentId,
      storagePath,
      filename: "orden.pdf",
      extension: "pdf",
      contentType: "application/pdf",
      sizeBytes: 100,
    }).storage_bucket,
    "chat-attachments",
  );
});

Deno.test("legacy dual-read trusts only the exact old Supabase paths", () => {
  const supabaseUrl = "https://project.supabase.co";
  assertEquals(
    isTrustedLegacyMessagingUrl(
      "https://project.supabase.co/storage/v1/object/public/vinabike-assets/chat/a.png",
      supabaseUrl,
    ),
    true,
  );
  assertEquals(
    isTrustedLegacyMessagingUrl(
      "https://project.supabase.co/storage/v1/object/public/vinabike-assets/whatsapp-media/a.pdf",
      supabaseUrl,
    ),
    true,
  );
  assertEquals(
    isTrustedLegacyMessagingUrl(
      "https://tracker.example/pixel.png",
      supabaseUrl,
    ),
    false,
  );
  assertEquals(
    isTrustedLegacyMessagingUrl(
      "https://project.supabase.co/storage/v1/object/public/other/a.png",
      supabaseUrl,
    ),
    false,
  );
});
