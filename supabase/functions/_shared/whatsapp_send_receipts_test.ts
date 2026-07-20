import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  durableWhatsAppSendReceipt,
  whatsappProviderFailureHttpStatus,
} from "./whatsapp_send_receipts.ts";

Deno.test("success requires both durable ERP and Meta identifiers", () => {
  assertThrows(
    () => durableWhatsAppSendReceipt({ externalMessageId: "wamid.1" }),
    Error,
    "durable_whatsapp_send_missing_message_id",
  );
  assertThrows(
    () => durableWhatsAppSendReceipt({ messageId: "message-1" }),
    Error,
    "durable_whatsapp_send_missing_external_message_id",
  );

  assertEquals(
    durableWhatsAppSendReceipt({
      messageId: "message-1",
      externalMessageId: "wamid.1",
    }),
    {
      ok: true,
      accepted: true,
      queued: false,
      message_id: "message-1",
      external_message_id: "wamid.1",
    },
  );
});

Deno.test("retryable and ambiguous provider failures use 503", () => {
  assertEquals(whatsappProviderFailureHttpStatus({ providerStatus: 400 }), 502);
  assertEquals(whatsappProviderFailureHttpStatus({ providerStatus: 429 }), 503);
  assertEquals(whatsappProviderFailureHttpStatus({ outcomeUnknown: true }), 503);
});
