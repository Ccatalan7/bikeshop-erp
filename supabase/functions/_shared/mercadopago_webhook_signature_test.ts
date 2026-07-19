import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { verifyMercadoPagoWebhookSignature } from "./mercadopago_webhook_signature.ts";

async function hmacHex(message: string, secret: string): Promise<string> {
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
    new TextEncoder().encode(message),
  );
  return Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

Deno.test("validates the Mercado Pago canonical HMAC manifest", async () => {
  const secret = "webhook-secret";
  const dataId = "Payment-ABC";
  const requestId = "request-123";
  const timestamp = "1704908010";
  const hash = await hmacHex(
    `id:${dataId.toLowerCase()};request-id:${requestId};ts:${timestamp};`,
    secret,
  );

  assertEquals(
    await verifyMercadoPagoWebhookSignature({
      signatureHeader: `ts=${timestamp},v1=${hash}`,
      requestId,
      dataId,
      secret,
    }),
    true,
  );
});

Deno.test("rejects tampering and incomplete manifests", async () => {
  const validShape = {
    signatureHeader: `ts=1704908010,v1=${"a".repeat(64)}`,
    requestId: "request-123",
    dataId: "payment-1",
    secret: "webhook-secret",
  };

  assertEquals(await verifyMercadoPagoWebhookSignature(validShape), false);
  assertEquals(
    await verifyMercadoPagoWebhookSignature({
      ...validShape,
      requestId: null,
    }),
    false,
  );
  assertEquals(
    await verifyMercadoPagoWebhookSignature({
      ...validShape,
      signatureHeader: "ts=oops,v1=abc",
    }),
    false,
  );
});
