import type { AgentAuthority, JsonObject } from "./contracts.ts";
import { createSupabaseAgentRunStore, RunBeginError } from "./run_store.ts";
import { type AgentRpcClient, SupabaseUserDataError } from "./supabase_user_data.ts";

const userId = "11111111-1111-4111-8111-111111111111";
const tenantId = "22222222-2222-4222-8222-222222222222";
const threadId = "33333333-3333-4333-8333-333333333333";
const runId = "44444444-4444-4444-8444-444444444444";
const requestId = "55555555-5555-4555-8555-555555555555";
const leaseToken = "66666666-6666-4666-8666-666666666666";
const fingerprint = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

const authority: AgentAuthority = {
  userId,
  tenantId,
  role: "admin",
  permissions: {},
  capabilities: [
    "ai.read.operational",
    "ai.read.sales",
    "ai.read.purchases",
    "ai.read.accounting",
  ],
  authorityFingerprint: fingerprint,
};

function assertEquals(actual: unknown, expected: unknown, message: string): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${message}: ${JSON.stringify(actual)} != ${JSON.stringify(expected)}`);
  }
}

function beginEnvelope(extra: Record<string, unknown> = {}) {
  return {
    authorityTenantId: tenantId,
    actorUserId: userId,
    authorityFingerprint: fingerprint,
    threadId,
    runId,
    runNo: 1,
    runStatus: "running",
    runDisposition: "claimed",
    replayed: false,
    leaseToken,
    fenceToken: 1,
    leaseExpiresAt: "2026-08-11T12:01:50Z",
    canonicalSummary: null,
    canonicalMessages: [{
      messageId: requestId,
      sequenceNo: 1,
      role: "user",
      content: "Organiza el día",
      cards: [],
      createdAt: "2026-08-11T12:00:00Z",
    }],
    response: null,
    terminalErrorCode: null,
    nextProviderAttemptNo: 1,
    nextToolOrdinal: 1,
    ...extra,
  };
}

Deno.test("run store begins through caller authority with a 110 second lease", async () => {
  let captured: { name: string; parameters: JsonObject } | null = null;
  const callerClient: AgentRpcClient = {
    rpc(name, parameters) {
      captured = { name, parameters };
      return Promise.resolve(beginEnvelope());
    },
  };
  let runtimeCalls = 0;
  const runtimeClient: AgentRpcClient = {
    rpc: () => {
      runtimeCalls++;
      return Promise.reject(new Error("unexpected runtime mutation"));
    },
  };
  const lease = await createSupabaseAgentRunStore(callerClient, runtimeClient).begin({
    authority,
    clientRequestId: requestId,
    requestHash: "request-hmac",
    userContent: "Organiza el día",
    modelRole: "fast",
    threadId: null,
    maxOutputTokens: 2048,
  }, new AbortController().signal);
  const beginCall = captured as { name: string; parameters: JsonObject } | null;
  if (!beginCall) throw new Error("begin RPC was not called");
  assertEquals(beginCall.name, "assistant_begin_run_v1", "fixed begin RPC");
  assertEquals("p_tenant_id" in beginCall.parameters, false, "tenant derives from caller JWT");
  assertEquals("p_actor_user_id" in beginCall.parameters, false, "actor derives from caller JWT");
  assertEquals(
    "p_authority_fingerprint" in beginCall.parameters,
    false,
    "authority derives from caller JWT",
  );
  assertEquals(beginCall.parameters.p_lease_ttl_seconds, 110, "lease spans request deadline");
  assertEquals(beginCall.parameters.p_max_output_tokens, 2048, "DB and provider budget agree");
  assertEquals(lease.runDisposition, "claimed", "claimed snapshot parsed");
  assertEquals(runtimeCalls, 0, "attested runtime transport is not used for admission");
});

Deno.test("run store forwards authority binding and exact cost on every attempt", async () => {
  const calls: Array<{ name: string; parameters: JsonObject }> = [];
  const callerClient: AgentRpcClient = {
    rpc(name, parameters) {
      calls.push({ name, parameters });
      return Promise.resolve(beginEnvelope());
    },
  };
  const runtimeClient: AgentRpcClient = {
    rpc(name, parameters) {
      calls.push({ name, parameters });
      return Promise.resolve({ authorityTenantId: tenantId, runId });
    },
  };
  const store = createSupabaseAgentRunStore(callerClient, runtimeClient);
  const lease = await store.begin({
    authority,
    clientRequestId: requestId,
    requestHash: "request-hmac",
    userContent: "Organiza el día",
    modelRole: "fast",
    threadId: null,
    maxOutputTokens: 2048,
  }, new AbortController().signal);
  await store.recordProviderAttempt({
    lease,
    attemptNo: 1,
    provider: "openai",
    model: "gpt-exact",
    modelRole: "fast",
    status: "succeeded",
    usage: { inputTokens: 5, outputTokens: 3, totalTokens: 8 },
    estimatedCostMicrousd: 11,
    startedAt: "2026-08-11T12:00:00Z",
    completedAt: "2026-08-11T12:00:01Z",
  }, new AbortController().signal);
  const attempt = calls[1];
  assertEquals(attempt.name, "assistant_record_provider_attempt_v2", "fixed attested attempt RPC");
  assertEquals(attempt.parameters.p_tenant_id, tenantId, "attempt tenant bound");
  assertEquals(attempt.parameters.p_actor_user_id, userId, "attempt actor bound");
  assertEquals(
    attempt.parameters.p_authority_fingerprint,
    fingerprint,
    "attempt fingerprint bound",
  );
  assertEquals(attempt.parameters.p_estimated_cost_microusd, 11, "real estimate persisted");
  assertEquals(attempt.parameters.p_model, "gpt-exact", "exact routed model persisted");

  await store.recordToolReceipt({
    lease,
    ordinal: 1,
    providerAttemptNo: 1,
    providerCallHash: "call-hmac",
    toolName: "research_public_web",
    risk: "public_research",
    status: "succeeded",
    argumentsHash: "arguments-hmac",
    outputHash: "output-hmac",
    resultCount: 1,
    outputBytes: 256,
    externalAccounting: {
      provider: "gemini",
      model: "gemini-3.6-flash",
      state: "configured_estimate",
      inputTokens: 120,
      outputTokens: 40,
      meter: "google_search_query",
      meterUnits: 3,
      costMicrousd: 12_345,
    },
    startedAt: "2026-08-11T12:00:01Z",
    completedAt: "2026-08-11T12:00:02Z",
  }, new AbortController().signal);
  assertEquals(
    calls[2].parameters.p_risk,
    "public_research",
    "public egress is explicit in ledger",
  );
  assertEquals(
    calls[2].name,
    "assistant_record_tool_receipt_v2",
    "tool receipt uses the fixed attested RPC",
  );
  assertEquals(calls[2].parameters.p_external_provider, "gemini", "external provider forwarded");
  assertEquals(
    calls[2].parameters.p_external_model,
    "gemini-3.6-flash",
    "external model forwarded",
  );
  assertEquals(
    calls[2].parameters.p_external_usage_state,
    "configured_estimate",
    "external usage state forwarded",
  );
  assertEquals(calls[2].parameters.p_external_input_tokens, 120, "external input forwarded");
  assertEquals(calls[2].parameters.p_external_output_tokens, 40, "external output forwarded");
  assertEquals(
    calls[2].parameters.p_external_meter,
    "google_search_query",
    "external meter forwarded",
  );
  assertEquals(calls[2].parameters.p_external_meter_units, 3, "external meter units forwarded");
  assertEquals(calls[2].parameters.p_external_cost_microusd, 12_345, "external cost forwarded");

  await store.recordToolReceipt({
    lease,
    ordinal: 2,
    providerAttemptNo: 1,
    providerCallHash: "draft-call-hmac",
    toolName: "prepare_task",
    risk: "draft",
    policyDecision: "approval_required",
    approvalUsed: false,
    status: "succeeded",
    argumentsHash: "draft-arguments-hmac",
    outputHash: "draft-output-hmac",
    resultCount: 1,
    outputBytes: 128,
    startedAt: "2026-08-11T12:00:02Z",
    completedAt: "2026-08-11T12:00:03Z",
  }, new AbortController().signal);
  assertEquals(calls[3].parameters.p_risk, "draft", "task preparation is a draft");
  assertEquals(
    calls[3].parameters.p_policy_decision,
    "approval_required",
    "task preparation remains approval-gated",
  );
  assertEquals(calls[3].parameters.p_approval_used, false, "draft does not consume approval");
  assertEquals(
    calls[3].parameters.p_external_provider,
    null,
    "ordinary tools have no egress provider",
  );
  assertEquals(
    calls[3].parameters.p_external_cost_microusd,
    0,
    "ordinary tools have no egress cost",
  );
});

Deno.test("run store validates terminal replay disposition without requiring a lease", async () => {
  const store = createSupabaseAgentRunStore(
    {
      rpc: () =>
        Promise.resolve(beginEnvelope({
          runStatus: "succeeded",
          runDisposition: "terminal",
          replayed: true,
          leaseToken: null,
          fenceToken: null,
          response: {
            content: "Respuesta previa",
            cards: [],
            createdAt: "2026-08-11T12:00:02Z",
          },
        })),
    },
    { rpc: () => Promise.reject(new Error("unexpected runtime mutation")) },
  );
  const replay = await store.begin({
    authority,
    clientRequestId: requestId,
    requestHash: "request-hmac",
    userContent: "Organiza el día",
    modelRole: "fast",
    threadId: null,
    maxOutputTokens: 2048,
  }, new AbortController().signal);
  assertEquals(replay.leaseToken, null, "terminal replay has no lease");
  assertEquals(replay.terminalResponse?.content, "Respuesta previa", "stored response returned");
});

Deno.test("run store scopes SQLSTATE outcomes to caller-owned admission only", async () => {
  const beginStore = createSupabaseAgentRunStore(
    {
      rpc: () =>
        Promise.reject(
          new SupabaseUserDataError("rpc_invalid_response", false, "idempotency_conflict"),
        ),
    },
    { rpc: () => Promise.reject(new Error("unexpected runtime mutation")) },
  );
  try {
    await beginStore.begin({
      authority,
      clientRequestId: requestId,
      requestHash: "request-hmac",
      userContent: "Organiza el día",
      modelRole: "fast",
      threadId: null,
      maxOutputTokens: 2048,
    }, new AbortController().signal);
  } catch (error) {
    assertEquals(error instanceof RunBeginError, true, "begin receives the typed outcome");
    if (!(error instanceof RunBeginError)) throw error;
    assertEquals(error.outcome, "idempotency_conflict", "begin preserves only closed outcome");
  }

  const store = createSupabaseAgentRunStore(
    { rpc: () => Promise.resolve(beginEnvelope()) },
    {
      rpc: () =>
        Promise.reject(
          new SupabaseUserDataError("rpc_invalid_response", false, "idempotency_conflict"),
        ),
    },
  );
  const activeLease = await store.begin({
    authority,
    clientRequestId: requestId,
    requestHash: "request-hmac",
    userContent: "Organiza el día",
    modelRole: "fast",
    threadId: null,
    maxOutputTokens: 2048,
  }, new AbortController().signal);
  try {
    await store.heartbeat(activeLease, new AbortController().signal);
  } catch (error) {
    assertEquals(
      error instanceof RunBeginError,
      false,
      "mutator 22023 cannot masquerade as an idempotency conflict",
    );
    assertEquals(error instanceof SupabaseUserDataError, true, "mutator failure stays generic");
    return;
  }
  throw new Error("mutator error unexpectedly succeeded");
});

Deno.test("run store accepts a valid 64 KiB canonical message for total-history bounding", async () => {
  const content = "á".repeat(32 * 1024);
  const store = createSupabaseAgentRunStore(
    {
      rpc: () =>
        Promise.resolve(beginEnvelope({
          canonicalMessages: [{ role: "user", content }],
        })),
    },
    { rpc: () => Promise.reject(new Error("unexpected runtime mutation")) },
  );
  const activeLease = await store.begin({
    authority,
    clientRequestId: requestId,
    requestHash: "request-hmac",
    userContent: "Organiza el día",
    modelRole: "fast",
    threadId: null,
    maxOutputTokens: 2048,
  }, new AbortController().signal);
  assertEquals(activeLease.canonicalMessages[0].content, content, "64 KiB row remains valid");
});

Deno.test("run store preserves a DB-coerced cancelled completion snapshot", async () => {
  const store = createSupabaseAgentRunStore(
    { rpc: () => Promise.resolve(beginEnvelope()) },
    {
      rpc: () =>
        Promise.resolve({
          authorityTenantId: tenantId,
          actorUserId: userId,
          authorityFingerprint: fingerprint,
          threadId,
          runId,
          runStatus: "cancelled",
          runDisposition: "terminal",
          terminalErrorCode: "run_cancelled",
          response: null,
        }),
    },
  );
  const activeLease = await store.begin({
    authority,
    clientRequestId: requestId,
    requestHash: "request-hmac",
    userContent: "Organiza el día",
    modelRole: "fast",
    threadId: null,
    maxOutputTokens: 2048,
  }, new AbortController().signal);
  const completion = await store.complete({
    lease: activeLease,
    status: "succeeded",
    content: "Lista",
    cards: [],
  }, new AbortController().signal);
  assertEquals(completion.runStatus, "cancelled", "durable status overrides requested success");
  assertEquals(completion.terminalErrorCode, "run_cancelled", "durable code is retained");
  assertEquals(completion.response, null, "cancelled run has no assistant response");
});
