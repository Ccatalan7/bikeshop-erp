import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  durableMetaSendSuccess,
  metaProviderFailureDisposition,
  metaProviderFailureHttpStatus,
  replayedMetaSendResponse,
} from "./meta_send_receipts.ts";

Deno.test("durable Meta receipt distinguishes acceptance from delivery", () => {
  assertEquals(
    durableMetaSendSuccess({
      attempt_id: "attempt-1",
      state: "finalized",
      message_id: "message-1",
      external_message_id: "mid.1",
    }),
    {
      ok: true,
      accepted: true,
      provider_accepted: true,
      outcome_unknown: false,
      retry_safe: false,
      attempt_id: "attempt-1",
      message_id: "message-1",
      client_message_id: null,
      external_message_id: "mid.1",
      external_status: "accepted",
    },
  );
});

Deno.test("prepared replay fails closed against duplicate delivery", () => {
  const response = replayedMetaSendResponse({
    attempt_id: "attempt-2",
    state: "prepared",
  });
  assertEquals(response.status, 409);
  assertEquals(response.body.outcome_unknown, true);
  assertEquals(response.body.retry_safe, false);
});

Deno.test("explicit rejection permits a new idempotency key", () => {
  const response = replayedMetaSendResponse({
    attempt_id: "attempt-3",
    state: "provider_rejected",
    error_code: "provider_400",
  });
  assertEquals(response.status, 409);
  assertEquals(response.body.outcome_unknown, false);
  assertEquals(response.body.retry_safe, true);
});

Deno.test("preflight failure records that no provider request was made", () => {
  const response = replayedMetaSendResponse({
    attempt_id: "attempt-preflight",
    state: "preflight_failed",
    error_code: "credential_unavailable",
  });
  assertEquals(response.status, 409);
  assertEquals(response.body.outcome_unknown, false);
  assertEquals(response.body.retry_safe, true);
});

Deno.test("known provider acceptance is distinct from an unknown outcome", () => {
  const response = replayedMetaSendResponse({
    attempt_id: "attempt-4",
    state: "provider_accepted",
    external_message_id: "mid.4",
  });
  assertEquals(response.status, 202);
  assertEquals(response.body.accepted, true);
  assertEquals(response.body.outcome_unknown, false);
  assertEquals(response.body.persistence_pending, true);
});

Deno.test("provider failure status hides credential failures behind 502", () => {
  assertEquals(metaProviderFailureHttpStatus(400), 409);
  assertEquals(metaProviderFailureHttpStatus(401), 502);
  assertEquals(metaProviderFailureHttpStatus(429), 429);
  assertEquals(metaProviderFailureHttpStatus(503), 502);
});

Deno.test("provider 5xx is ambiguous while 4xx is an explicit rejection", () => {
  assertEquals(metaProviderFailureDisposition(400), {
    attemptState: "provider_rejected",
    outcomeUnknown: false,
    retrySafe: true,
  });
  assertEquals(metaProviderFailureDisposition(503), {
    attemptState: "outcome_unknown",
    outcomeUnknown: true,
    retrySafe: false,
  });
});
