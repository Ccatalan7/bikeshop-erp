import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildJobActionToken, parseWhatsAppActionToken } from "./whatsapp_action_tokens.ts";

const jobId = "8ee114c9-c89a-4d31-a9f4-c0dc6f665779";

Deno.test("builds and parses a nonce-bound job action token", () => {
  const token = buildJobActionToken({
    jobId,
    action: "approve_quote",
    revisionMs: 1_721_000_123_456,
  });

  assertEquals(token, `job:${jobId}:approve_quote:1721000123456`);
  assertEquals(parseWhatsAppActionToken(token), {
    kind: "job",
    targetId: jobId,
    action: "approve_quote",
    revisionMs: 1_721_000_123_456,
  });
});

Deno.test("marks legacy job and invoice actions as read-only legacy input", () => {
  assertEquals(parseWhatsAppActionToken(`job:${jobId}:approve_quote`), {
    kind: "job",
    targetId: jobId,
    action: "approve_quote",
    legacy: true,
  });
  assertEquals(parseWhatsAppActionToken(`invoice:${jobId}:confirm_payment`), {
    kind: "invoice",
    targetId: jobId,
    action: "confirm_payment",
    legacy: true,
  });
});

Deno.test("rejects malformed, forged and unsafe tokens", () => {
  assertEquals(parseWhatsAppActionToken(`job:${jobId}:approve-quote:1721000123456`), null);
  assertEquals(parseWhatsAppActionToken(`job:${jobId}:approve_quote:not-a-nonce`), null);
  assertEquals(parseWhatsAppActionToken("https://example.com/action"), null);
  assertEquals(parseWhatsAppActionToken(null), null);

  assertThrows(
    () =>
      buildJobActionToken({
        jobId: "not-a-uuid",
        action: "approve_quote",
        revisionMs: 1_721_000_123_456,
      }),
    Error,
    "invalid_job_action_target",
  );
});
