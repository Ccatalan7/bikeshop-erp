import { signSvixPayload } from "../_shared/transactional_email/crypto.ts";
import { handleResendTransactionalWebhook } from "./index.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const now = new Date("2026-07-18T20:00:00.000Z");
const timestamp = String(Math.floor(now.getTime() / 1000));
const webhookSecret = "whsec_" + btoa("transactional-webhook-test-secret");

async function signedRequest(event: Record<string, unknown>, messageId: string) {
  const rawBody = JSON.stringify(event);
  const signature = await signSvixPayload(webhookSecret, messageId, timestamp, rawBody);
  return new Request("https://example.invalid/resend-transactional-webhook", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "svix-id": messageId,
      "svix-timestamp": timestamp,
      "svix-signature": `v1,${signature}`,
    },
    body: rawBody,
  });
}

function dependencies(rpcCalls: Array<Record<string, unknown>>) {
  return {
    env(name: string) {
      return {
        RESEND_WEBHOOK_SECRET: webhookSecret,
        SUPABASE_URL: "https://project.example.invalid",
        SUPABASE_SERVICE_ROLE_KEY: "service-role-test-value",
      }[name] ?? "";
    },
    now: () => now,
    createRpcClient: () => ({
      rpc(name: string, params: Record<string, unknown>) {
        rpcCalls.push({ name, params });
        return Promise.resolve({ data: { matched: true }, error: null });
      },
    }),
  };
}

Deno.test("signed operational Resend event records only sanitized delivery evidence", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const request = await signedRequest({
    type: "email.bounced",
    created_at: now.toISOString(),
    data: {
      email_id: "email_delivery_001",
      from: "Ventas Viñabike <ventas@vinabike.cl>",
      to: ["customer-private@example.invalid"],
      subject: "Private order subject",
      bounce: {
        type: "Permanent",
        subType: "Suppressed",
        message: "Mailbox customer-private@example.invalid rejected Bearer secret-token-value",
      },
      tags: { outbox_id: "9e000000-0000-4000-8000-000000000001" },
    },
  }, "msg_delivery_001");

  const response = await handleResendTransactionalWebhook(request, dependencies(calls));
  assert(response.status === 200, `unexpected status ${response.status}`);
  assert(calls.length === 1, "provider event RPC was not called exactly once");

  const call = calls[0];
  assert(call.name === "record_transactional_email_provider_event", "wrong RPC called");
  const params = call.params as Record<string, unknown>;
  assert(params.p_event_type === "email.bounced", "event type was not preserved");
  assert(params.p_is_permanent === true, "permanent bounce was not classified");
  const sanitized = JSON.stringify(params.p_sanitized_payload);
  assert(!sanitized.includes("customer-private"), "recipient PII leaked into evidence");
  assert(!sanitized.includes("secret-token-value"), "credential-like detail leaked into evidence");
  assert(!sanitized.includes("Private order subject"), "subject leaked into evidence");
  assert(!sanitized.includes("service-role-test-value"), "service role leaked into evidence");
});

Deno.test("every signed Resend bounce is permanent even without an optional subtype", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const request = await signedRequest({
    type: "email.bounced",
    created_at: now.toISOString(),
    data: {
      email_id: "email_delivery_without_bounce_type",
      tags: { outbox_id: "9e000000-0000-4000-8000-000000000001" },
    },
  }, "msg_delivery_without_bounce_type");

  const response = await handleResendTransactionalWebhook(request, dependencies(calls));
  assert(response.status === 200, `unexpected status ${response.status}`);
  const params = calls[0]?.params as Record<string, unknown> | undefined;
  assert(params?.p_is_permanent === true, "permanent bounce was not suppressed");
});

Deno.test("signed operational event with an invalid occurrence time is rejected", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const request = await signedRequest({
    type: "email.delivered",
    created_at: "not-a-provider-time",
    data: { email_id: "email_invalid_time" },
  }, "msg_invalid_time");

  const response = await handleResendTransactionalWebhook(request, dependencies(calls));
  assert(response.status === 400, "invalid provider occurrence time was fabricated locally");
  assert(calls.length === 0, "invalid provider time reached the evidence ledger");
});

Deno.test("signed engagement event is acknowledged without persistence or retries", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const request = await signedRequest({
    type: "email.opened",
    created_at: now.toISOString(),
    data: { email_id: "email_opened_001" },
  }, "msg_opened_001");

  const response = await handleResendTransactionalWebhook(request, dependencies(calls));
  const body = await response.json();
  assert(response.status === 200, "ignored signed event must be acknowledged");
  assert(body.ignored === true, "engagement event was not explicitly ignored");
  assert(calls.length === 0, "engagement event was persisted");
});

Deno.test("unsigned webhook is rejected before any database call", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const response = await handleResendTransactionalWebhook(
    new Request("https://example.invalid/resend-transactional-webhook", {
      method: "POST",
      body: JSON.stringify({ type: "email.delivered" }),
    }),
    dependencies(calls),
  );
  assert(response.status === 401, "unsigned webhook was accepted");
  assert(calls.length === 0, "unsigned webhook reached the database");
});
