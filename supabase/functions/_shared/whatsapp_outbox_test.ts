import { assertEquals, assertThrows } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { outboxCompletionStatus, runtimeSecretKey, validOutboxDispatch } from "./whatsapp_outbox.ts";

Deno.test("worker requires a modern injected key and never falls back to a JWT", () => {
  assertEquals(runtimeSecretKey('{"default":"sb_secret_test"}'), "sb_secret_test");
  assertThrows(() => runtimeSecretKey(undefined));
  assertThrows(() => runtimeSecretKey('{"default":"eyJlegacy"}'));
});
Deno.test("dispatch capabilities must have their exact bounded shape", () => {
  assertEquals(validOutboxDispatch({ message_id: "9f032200-0000-4000-8000-000000000001", token: "a".repeat(64) }), true);
  assertEquals(validOutboxDispatch({ message_id: "anything", token: "a".repeat(64) }), false);
  assertEquals(validOutboxDispatch({ message_id: "9f032200-0000-4000-8000-000000000001", token: "short" }), false);
});
Deno.test("only a definite rate-limit refusal allows another provider attempt", () => {
  assertEquals(outboxCompletionStatus({ externalStatus: "failed", metadata: { provider_http_status: 429 } }), "retry");
  assertEquals(outboxCompletionStatus({ externalStatus: "failed", metadata: { provider_http_status: 500 } }), "failed");
  assertEquals(outboxCompletionStatus({ externalStatus: null, metadata: {} }), "outcome_unknown");
  assertEquals(outboxCompletionStatus({ externalStatus: "accepted", metadata: {} }), "accepted");
});
