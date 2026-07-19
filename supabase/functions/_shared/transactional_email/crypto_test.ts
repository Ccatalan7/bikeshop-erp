import { signSvixPayload, verifyResendWebhookSignature } from "./crypto.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const secret = "whsec_" + btoa("transactional-email-test-secret-32");
const messageId = "msg_test_delivery_001";
const now = new Date("2026-07-18T18:00:00.000Z");
const timestamp = String(Math.floor(now.getTime() / 1000));
const rawBody = JSON.stringify({ type: "email.delivered", data: { email_id: "email_001" } });

Deno.test("Resend/Svix signature verification accepts valid raw payload", async () => {
  const signature = await signSvixPayload(secret, messageId, timestamp, rawBody);
  assert(
    await verifyResendWebhookSignature({
      rawBody,
      messageId,
      timestamp,
      signature: `v1,${signature}`,
      secret,
      now,
    }),
    "valid signature was rejected",
  );
});

Deno.test("Resend/Svix signature verification rejects modified body", async () => {
  const signature = await signSvixPayload(secret, messageId, timestamp, rawBody);
  assert(
    !(await verifyResendWebhookSignature({
      rawBody: `${rawBody} `,
      messageId,
      timestamp,
      signature: `v1,${signature}`,
      secret,
      now,
    })),
    "modified body was accepted",
  );
});

Deno.test("Resend/Svix signature verification rejects stale replay", async () => {
  const staleTimestamp = String(Number(timestamp) - 301);
  const signature = await signSvixPayload(secret, messageId, staleTimestamp, rawBody);
  assert(
    !(await verifyResendWebhookSignature({
      rawBody,
      messageId,
      timestamp: staleTimestamp,
      signature: `v1,${signature}`,
      secret,
      now,
    })),
    "stale webhook replay was accepted",
  );
});
