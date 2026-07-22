import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { verifyMetaWebhookSignature } from "./meta_webhook_signature.ts";

async function hmacHex(payload: Uint8Array, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, Uint8Array.from(payload)),
  );
  return Array.from(signature)
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

Deno.test("validates Meta HMAC over the exact raw body", async () => {
  const secret = "meta-app-secret";
  const rawBody = '{"object":"instagram","entry":[]}\n';
  const hash = await hmacHex(new TextEncoder().encode(rawBody), secret);

  assertEquals(
    await verifyMetaWebhookSignature({
      signatureHeader: `sha256=${hash}`,
      rawBody,
      appSecret: secret,
    }),
    true,
  );
  assertEquals(
    await verifyMetaWebhookSignature({
      signatureHeader: `sha256=${hash}`,
      rawBody: rawBody.trimEnd(),
      appSecret: secret,
    }),
    false,
  );
});

Deno.test("accepts raw bytes without decoding or rewriting them", async () => {
  const secret = "meta-app-secret";
  const rawBody = new Uint8Array([0, 13, 10, 255, 42]);
  const hash = await hmacHex(rawBody, secret);

  assertEquals(
    await verifyMetaWebhookSignature({
      signatureHeader: `sha256=${hash.toUpperCase()}`,
      rawBody,
      appSecret: secret,
    }),
    true,
  );
});

Deno.test("rejects malformed, tampered, or incomplete Meta signatures", async () => {
  const validInput = {
    signatureHeader: `sha256=${"a".repeat(64)}`,
    rawBody: "{}",
    appSecret: "meta-app-secret",
  };

  assertEquals(await verifyMetaWebhookSignature(validInput), false);
  assertEquals(
    await verifyMetaWebhookSignature({
      ...validInput,
      signatureHeader: `sha1=${"a".repeat(40)}`,
    }),
    false,
  );
  assertEquals(
    await verifyMetaWebhookSignature({
      ...validInput,
      signatureHeader: "sha256=not-hex",
    }),
    false,
  );
  assertEquals(
    await verifyMetaWebhookSignature({ ...validInput, appSecret: null }),
    false,
  );
  assertEquals(
    await verifyMetaWebhookSignature({
      ...validInput,
      signatureHeader: null,
    }),
    false,
  );
});
