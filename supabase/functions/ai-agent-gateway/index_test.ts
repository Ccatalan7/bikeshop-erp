import type {
  AgentAuthority,
  AgentProviderRequest,
  AgentProviderTurn,
} from "../_shared/ai_agent/contracts.ts";
import type { AgentAuthorityDataSource } from "../_shared/ai_agent/authority.ts";
import {
  AgentApprovalActionError,
  type AgentApprovalActionExecutor,
} from "../_shared/ai_agent/action_endpoint.ts";
import { createDefaultAgentToolRegistry } from "../_shared/ai_agent/tool_registry.ts";
import type { AgentModelProvider } from "../_shared/ai_agent/providers/provider.ts";
import { AgentProviderRouter, ProviderError } from "../_shared/ai_agent/providers/provider.ts";
import {
  type AgentRunLease,
  type AgentRunStore,
  RunBeginError,
} from "../_shared/ai_agent/run_store.ts";
import type { AgentToolExecutor } from "../_shared/ai_agent/tool_executor.ts";
import {
  createProductionOptions,
  handler,
  isAllowedCorsOrigin,
  parseGatewayRequest,
  resolveSupabasePublishableKey,
} from "./index.ts";
import { AgentPricingCatalog } from "../_shared/ai_agent/pricing.ts";

const endpoint = "https://project.supabase.co/functions/v1/ai-agent-gateway";
const origin = "https://erp.example.test";
const userId = "11111111-1111-4111-8111-111111111111";
const tenantId = "22222222-2222-4222-8222-222222222222";
const threadId = "33333333-3333-4333-8333-333333333333";
const runId = "44444444-4444-4444-8444-444444444444";
const requestId = "55555555-5555-4555-8555-555555555555";
const leaseToken = "66666666-6666-4666-8666-666666666666";
const hmacKey = "unit-test-hmac-key-".repeat(2);
const authorityFingerprint = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const pricingCatalog = AgentPricingCatalog.parse(JSON.stringify({
  "test-model": {
    inputMicrousdPerMillionTokens: 1_000_000,
    outputMicrousdPerMillionTokens: 2_000_000,
  },
}));

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}
function assertEquals(actual: unknown, expected: unknown, message: string): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${message}: ${JSON.stringify(actual)} != ${JSON.stringify(expected)}`);
  }
}
function body(extra: Record<string, unknown> = {}) {
  return {
    version: 1,
    clientRequestId: requestId,
    threadId: null,
    modelRole: "fast",
    message: "¿Qué debo priorizar hoy?",
    viewContext: { kind: "none", jobIds: [], truncated: false },
    ...extra,
  };
}
function httpRequest(
  value: unknown,
  options: { origin?: string; raw?: string; signal?: AbortSignal } = {},
) {
  return new Request(endpoint, {
    method: "POST",
    headers: {
      origin: options.origin ?? origin,
      authorization: "Bearer opaque-jwt",
      "content-type": "application/json",
    },
    body: options.raw ?? JSON.stringify(value),
    signal: options.signal,
  });
}

class MemoryRunStore implements AgentRunStore {
  lease: AgentRunLease = {
    authorityTenantId: tenantId,
    actorUserId: userId,
    authorityFingerprint,
    threadId,
    runId,
    runStatus: "running",
    runDisposition: "claimed",
    terminalErrorCode: null,
    replayed: false,
    leaseToken,
    fenceToken: 1,
    canonicalSummary: null,
    canonicalMessages: [{ role: "user", content: "¿Qué debo priorizar hoy?" }],
    terminalResponse: null,
    nextProviderAttemptNo: 1,
    nextToolOrdinal: 1,
  };
  beginCalls = 0;
  beginError: Error | null = null;
  completionBlock: Promise<void> | null = null;
  completionStarted: (() => void) | null = null;
  completionStatus: "succeeded" | "failed" | "cancelled" | "timed_out" | null = null;
  begin(): Promise<AgentRunLease> {
    this.beginCalls++;
    if (this.beginError) return Promise.reject(this.beginError);
    return Promise.resolve(this.lease);
  }
  heartbeat() {
    return Promise.resolve({ cancelRequested: false });
  }
  recordProviderAttempt() {
    return Promise.resolve();
  }
  recordToolReceipt() {
    return Promise.resolve();
  }
  async complete(input: Parameters<AgentRunStore["complete"]>[0]) {
    this.completionStarted?.();
    if (this.completionBlock) await this.completionBlock;
    const status = this.completionStatus ?? input.status;
    return Promise.resolve({
      threadId,
      runId,
      runStatus: status,
      terminalErrorCode: status === "succeeded"
        ? null
        : this.completionStatus === "cancelled"
        ? "run_cancelled"
        : input.errorCode ?? "assistant_unavailable",
      response: status === "succeeded"
        ? { content: input.content!, cards: input.cards ?? [] }
        : null,
    });
  }
}

function options(turn: AgentProviderTurn = {
  text: "Respuesta verificada",
  toolCalls: [],
  usage: { inputTokens: 3, outputTokens: 2, totalTokens: 5 },
  finishReason: "stop",
}) {
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
    authorityFingerprint,
  };
  const source: AgentAuthorityDataSource = { resolve: () => Promise.resolve(authority) };
  const store = new MemoryRunStore();
  const executor: AgentToolExecutor = {
    execute: () => Promise.reject(new Error("unexpected tool")),
    workshopViewContext: () => Promise.reject(new Error("unexpected view context")),
  };
  const provider: AgentModelProvider = {
    id: "openai",
    modelFor: () => "test-model",
    generate: () => Promise.resolve(turn),
  };
  return {
    value: {
      providerRouter: new AgentProviderRouter({
        providers: [provider],
        routes: {
          fast: { provider: "openai" },
          deep: { provider: "openai" },
          vision: { provider: "openai" },
        },
      }),
      requestServices: (_request: Request) => ({
        authoritySource: source,
        runStore: store,
        toolExecutor: executor,
      }),
      toolRegistry: createDefaultAgentToolRegistry(),
      allowedOrigins: [origin],
      auditHmacKey: hmacKey,
      pricingCatalog,
    },
    store,
  };
}

Deno.test("missing bearer is rejected before production transports are constructed", async () => {
  const setup = options();
  setup.value.requestServices = () => {
    throw new Error("request-scoped transport must not be constructed");
  };
  const request = new Request(endpoint, {
    method: "POST",
    headers: { origin, "content-type": "application/json" },
    body: JSON.stringify(body()),
  });
  const response = await handler(request, setup.value);
  assertEquals(response.status, 401, "missing bearer keeps the session boundary");
  assertEquals((await response.json()).code, "invalid_session", "missing bearer is sanitized");
});

Deno.test("CORS preflight permits the result-list rollout capability header", async () => {
  const setup = options();
  const response = await handler(
    new Request(endpoint, {
      method: "OPTIONS",
      headers: { origin },
    }),
    setup.value,
  );
  assertEquals(response.status, 204, "preflight succeeds");
  assert(
    response.headers.get("access-control-allow-headers")?.includes(
      "x-vinabike-ai-result-lists",
    ),
    "web clients may negotiate typed result lists",
  );
});

Deno.test("v1 request parser accepts only the closed client contract", () => {
  const parsed = parseGatewayRequest(body());
  assertEquals(parsed.version, 1, "version remains fixed");
  assertEquals(parsed.threadId, null, "nullable thread is normalized");
});

Deno.test("v1 request parser rejects provider, tenant, tools and history", () => {
  for (const key of ["provider", "tenantId", "tools", "messages", "permissions"]) {
    let rejected = false;
    try {
      parseGatewayRequest(body({ [key]: "attacker" }));
    } catch (_) {
      rejected = true;
    }
    assert(rejected, `${key} must be forbidden`);
  }
});

Deno.test("v1 request parser accepts fast/deep but never client-selected vision", () => {
  assertEquals(parseGatewayRequest(body({ modelRole: "deep" })).modelRole, "deep", "deep allowed");
  let rejected = false;
  try {
    parseGatewayRequest(body({ modelRole: "vision" }));
  } catch (_) {
    rejected = true;
  }
  assert(rejected, "vision is server-owned in v1");
});

Deno.test("message limit is measured as UTF-8 bytes", () => {
  const accepted = "á".repeat(4_096);
  assertEquals(
    parseGatewayRequest(body({ message: accepted })).message,
    accepted,
    "8192 bytes accepted",
  );
  let rejected = false;
  try {
    parseGatewayRequest(body({ message: `${accepted}á` }));
  } catch (_) {
    rejected = true;
  }
  assert(rejected, "8194 byte message rejected");
  assertEquals(
    parseGatewayRequest(body({ message: "  hola  " })).message,
    "hola",
    "message canonicalized",
  );
});

Deno.test("view context is closed, UUID-only and bounded", () => {
  const parsed = parseGatewayRequest(body({
    viewContext: { kind: "workshop_jobs", jobIds: [runId], truncated: true },
  }));
  assertEquals(parsed.viewContext.kind, "workshop_jobs", "trusted kind accepted");
  for (
    const invalid of [
      { kind: "workshop_jobs", jobIds: ["folio-visible"], truncated: false },
      { kind: "none", jobIds: [runId], truncated: false },
      { kind: "rejected", jobIds: [], truncated: true },
    ]
  ) {
    let rejected = false;
    try {
      parseGatewayRequest(body({ viewContext: invalid }));
    } catch (_) {
      rejected = true;
    }
    assert(rejected, "invalid visible context is rejected");
  }
});

Deno.test("approval action dispatches without provider, run store or tool execution", async () => {
  const setup = options();
  let applyCalls = 0;
  const approvalExecutor: AgentApprovalActionExecutor = {
    apply: (request, authority) => {
      applyCalls++;
      assertEquals(authority.tenantId, tenantId, "action retains resolved authority");
      return Promise.resolve({
        version: 1,
        operation: "approval_action",
        approvalId: request.approvalId,
        clientActionId: request.clientActionId,
        approvalState: "discarded",
        text: "No se creó la tarea.",
        cards: [],
        status: "completed",
      });
    },
  };
  const originalServices = setup.value.requestServices;
  setup.value.requestServices = (request: Request) => ({
    ...originalServices(request),
    approvalActionExecutor: approvalExecutor,
  });
  let providerCalls = 0;
  setup.value.providerRouter = new AgentProviderRouter({
    providers: [{
      id: "openai",
      modelFor: () => "test-model",
      generate: () => {
        providerCalls++;
        throw new Error("provider must not run for approval action");
      },
    }],
    routes: {
      fast: { provider: "openai" },
      deep: { provider: "openai" },
      vision: { provider: "openai" },
    },
  });
  const action = {
    version: 1,
    operation: "approval_action",
    approvalId: "77777777-7777-4777-8777-777777777777",
    approvalAction: "discard",
    clientActionId: "88888888-8888-4888-8888-888888888888",
  };
  const response = await handler(httpRequest(action), setup.value);
  assertEquals(response.status, 200, "approval action completes");
  assertEquals(applyCalls, 1, "only the action executor runs");
  assertEquals(setup.store.beginCalls, 0, "action allocates no assistant run");
  assertEquals(providerCalls, 0, "action performs no model request");
});

Deno.test("approval action keeps exact parsing, executor and authority failures closed", async () => {
  const action = {
    version: 1,
    operation: "approval_action",
    approvalId: "77777777-7777-4777-8777-777777777777",
    approvalAction: "approve",
    clientActionId: "88888888-8888-4888-8888-888888888888",
  };
  const invalid = options();
  const invalidResponse = await handler(
    httpRequest({ ...action, tenantId }),
    invalid.value,
  );
  assertEquals(invalidResponse.status, 400, "extra action key is rejected");
  assertEquals((await invalidResponse.json()).code, "approval_invalid", "parse code is closed");

  const missing = options();
  const missingResponse = await handler(httpRequest(action), missing.value);
  assertEquals(missingResponse.status, 503, "missing action executor fails closed");
  assertEquals((await missingResponse.json()).code, "approval_unavailable", "missing code fixed");

  const deniedAuthority = options();
  deniedAuthority.value.requestServices = () => ({
    authoritySource: { resolve: () => Promise.reject(new Error("private")) },
    runStore: deniedAuthority.store,
    toolExecutor: {
      execute: () => Promise.reject(new Error("unexpected")),
      workshopViewContext: () => Promise.reject(new Error("unexpected")),
    },
  });
  const authorityResponse = await handler(httpRequest(action), deniedAuthority.value);
  assertEquals(authorityResponse.status, 503, "authority resolves before action dispatch");
  assertEquals(
    (await authorityResponse.json()).code,
    "authorization_unavailable",
    "authority error remains generic",
  );

  for (
    const [status, code] of [[403, "approval_forbidden"], [
      409,
      "approval_idempotency_conflict",
    ]] as const
  ) {
    const mapped = options();
    const originalServices = mapped.value.requestServices;
    mapped.value.requestServices = (request: Request) => ({
      ...originalServices(request),
      approvalActionExecutor: {
        apply: () =>
          Promise.reject(
            new AgentApprovalActionError(
              status,
              code,
              status === 403 ? "Approval is unavailable" : "Approval was already used differently",
            ),
          ),
      },
    });
    const response = await handler(httpRequest(action), mapped.value);
    assertEquals(response.status, status, `${code} status is stable`);
    assertEquals((await response.json()).code, code, `${code} maps without upstream details`);
  }
});

Deno.test("gateway returns exact v1 response and no provider internals", async () => {
  const setup = options();
  const response = await handler(httpRequest(body()), setup.value);
  const raw = await response.text();
  assertEquals(response.status, 200, "request completes");
  assertEquals(JSON.parse(raw), {
    version: 1,
    threadId,
    runId,
    text: "Respuesta verificada",
    cards: [],
    status: "completed",
  }, "response is closed");
  assert(!raw.includes("openai"), "provider id is private");
  assert(!raw.includes("toolCalls"), "tool calls are private");
});

Deno.test("gateway returns terminal replay without provider execution", async () => {
  let providerCalls = 0;
  const setup = options();
  setup.store.lease = {
    ...setup.store.lease,
    runDisposition: "terminal",
    replayed: true,
    leaseToken: null,
    fenceToken: null,
    terminalResponse: { content: "Respuesta previa", cards: [] },
  };
  setup.value.providerRouter = new AgentProviderRouter({
    providers: [{
      id: "openai",
      modelFor: () => "test-model",
      generate: () => {
        providerCalls++;
        throw new Error();
      },
    }],
    routes: {
      fast: { provider: "openai" },
      deep: { provider: "openai" },
      vision: { provider: "openai" },
    },
  });
  const response = await handler(httpRequest(body()), setup.value);
  assertEquals(response.status, 200, "terminal replay succeeds");
  assertEquals(providerCalls, 0, "replay consumes no model resources");
});

Deno.test("active duplicate request is a stable conflict", async () => {
  const setup = options();
  setup.store.lease = {
    ...setup.store.lease,
    runDisposition: "in_progress",
    replayed: true,
    leaseToken: null,
    fenceToken: null,
  };
  const response = await handler(httpRequest(body()), setup.value);
  assertEquals(response.status, 409, "active duplicate conflicts");
  assertEquals((await response.json()).code, "run_in_progress", "machine code is fixed");
});

Deno.test("caller-owned admission outcomes keep exact sanitized HTTP mappings", async () => {
  const cases = [
    ["idempotency_conflict", 409, "idempotency_conflict"],
    ["forbidden", 403, "assistant_forbidden"],
    ["quota_exceeded", 429, "assistant_quota_exceeded"],
  ] as const;
  for (const [outcome, status, code] of cases) {
    const setup = options();
    setup.store.beginError = new RunBeginError(outcome);
    const response = await handler(httpRequest(body()), setup.value);
    assertEquals(response.status, status, `${outcome} status is stable`);
    assertEquals((await response.json()).code, code, `${outcome} code is closed`);
  }
});

Deno.test("failed, cancelled and timed-out terminal replays keep typed outcomes", async () => {
  const cases = [
    ["failed", "provider_unavailable", 502, "provider_unavailable"],
    ["cancelled", "run_cancelled", 409, "run_cancelled"],
    ["timed_out", "request_timeout", 504, "request_timeout"],
  ] as const;
  for (const [runStatus, terminalErrorCode, status, code] of cases) {
    const setup = options();
    setup.store.lease = {
      ...setup.store.lease,
      runStatus,
      runDisposition: "terminal",
      replayed: true,
      leaseToken: null,
      fenceToken: null,
      terminalErrorCode,
    };
    const response = await handler(httpRequest(body()), setup.value);
    assertEquals(response.status, status, `${runStatus} HTTP status`);
    assertEquals((await response.json()).code, code, `${runStatus} stable code`);
  }
});

Deno.test("CORS rejects arbitrary origins before runtime work", async () => {
  const setup = options();
  const response = await handler(
    httpRequest(body(), { origin: "https://attacker.test" }),
    setup.value,
  );
  assertEquals(response.status, 403, "origin denied");
  assertEquals(setup.store.beginCalls, 0, "no run allocated");
  assert(isAllowedCorsOrigin(origin, [origin]), "exact origin allowed");
  assert(!isAllowedCorsOrigin("https://sub.erp.example.test", [origin]), "subdomain denied");
});

Deno.test("malformed and oversized bodies never allocate runs", async () => {
  const setup = options();
  const malformed = await handler(httpRequest({}, { raw: "{" }), setup.value);
  assertEquals(malformed.status, 400, "bad JSON rejected");
  const oversized = await handler(httpRequest(body({ message: "x".repeat(40_000) })), {
    ...setup.value,
    maxRequestBytes: 1024,
  });
  assertEquals(oversized.status, 413, "oversized request rejected");
  assertEquals(setup.store.beginCalls, 0, "no run allocation");
});

Deno.test("provider errors are fixed and sanitized", async () => {
  const setup = options();
  setup.value.providerRouter = new AgentProviderRouter({
    providers: [{
      id: "openai",
      modelFor: () => "test-model",
      generate: () => Promise.reject(new ProviderError("provider_rejected", 401, false)),
    }],
    routes: {
      fast: { provider: "openai" },
      deep: { provider: "openai" },
      vision: { provider: "openai" },
    },
  });
  const response = await handler(httpRequest(body()), setup.value);
  const raw = await response.text();
  assertEquals(response.status, 502, "provider failure contained");
  assert(raw.includes("provider_rejected"), "fixed code returned");
  assert(!raw.includes("401"), "upstream detail hidden");
});

Deno.test("client abort is relayed and does not become a provider retry", async () => {
  const client = new AbortController();
  let calls = 0;
  let markStarted!: () => void;
  const started = new Promise<void>((resolve) => markStarted = resolve);
  const setup = options();
  setup.value.providerRouter = new AgentProviderRouter({
    providers: [{
      id: "openai",
      modelFor: () => "test-model",
      generate: (_request: AgentProviderRequest, signal: AbortSignal) => {
        calls++;
        markStarted();
        return new Promise((_resolve, reject) => {
          signal.addEventListener(
            "abort",
            () => reject(new ProviderError("provider_unavailable", 503, true)),
            { once: true },
          );
        });
      },
    }],
    routes: {
      fast: { provider: "openai" },
      deep: { provider: "openai" },
      vision: { provider: "openai" },
    },
  });
  const pending = handler(httpRequest(body(), { signal: client.signal }), setup.value);
  await started;
  client.abort();
  const response = await pending;
  assertEquals(response.status, 499, "abort is explicit");
  assertEquals(calls, 1, "aborted provider is never retried");
});

Deno.test("client abort waits for durable cleanup before handler completion", async () => {
  const client = new AbortController();
  let providerCalls = 0;
  let markProviderStarted!: () => void;
  const providerStarted = new Promise<void>((resolve) => markProviderStarted = resolve);
  let releaseCompletion!: () => void;
  const completionBlock = new Promise<void>((resolve) => releaseCompletion = resolve);
  let markCompletionStarted!: () => void;
  const completionStarted = new Promise<void>((resolve) => markCompletionStarted = resolve);
  const setup = options();
  setup.store.completionBlock = completionBlock;
  setup.store.completionStarted = markCompletionStarted;
  setup.value.providerRouter = new AgentProviderRouter({
    providers: [{
      id: "openai",
      modelFor: () => "test-model",
      generate: (_request: AgentProviderRequest, signal: AbortSignal) => {
        providerCalls++;
        markProviderStarted();
        return new Promise((_resolve, reject) => {
          signal.addEventListener(
            "abort",
            () => reject(new ProviderError("provider_unavailable", 503, false)),
            { once: true },
          );
        });
      },
    }],
    routes: {
      fast: { provider: "openai" },
      deep: { provider: "openai" },
      vision: { provider: "openai" },
    },
  });
  let settled = false;
  const pending = handler(httpRequest(body(), { signal: client.signal }), setup.value)
    .finally(() => settled = true);
  await providerStarted;
  client.abort();
  await completionStarted;
  await Promise.resolve();
  assertEquals(settled, false, "HTTP response waits for the durable terminal write");
  assertEquals(providerCalls, 1, "abort starts no later provider call");
  releaseCompletion();
  const response = await pending;
  assertEquals(response.status, 499, "cleanup preserves the typed abort response");
  assertEquals(settled, true, "handler settles only after cleanup returns");
});

Deno.test("production wiring isolates caller data and assistant_runtime ledger transports", async () => {
  const requests: Array<{ path: string; headers: Headers }> = [];
  const env: Record<string, string> = {
    AI_AGENT_FAST_PROVIDER: "gemini",
    AI_AGENT_DEEP_PROVIDER: "gemini",
    AI_AGENT_VISION_PROVIDER: "gemini",
    GEMINI_API_KEY: "provider-key",
    SUPABASE_URL: "https://project.supabase.co",
    SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({
      default: "sb_publishable_hosted_test",
    }),
    AI_AGENT_RUNTIME_ATTESTATION_KID: "runtime-test",
    AI_AGENT_RUNTIME_ATTESTATION_KEY_HEX: "11".repeat(32),
    AI_AGENT_RUNTIME_ATTESTATION_AUDIENCE: "supabase:projectref:assistant-runtime",
    AI_AGENT_AUDIT_HMAC_KEY: hmacKey,
    AI_AGENT_GEMINI_SEARCH_MICROUSD_PER_QUERY: "14000",
    AI_AGENT_MODEL_PRICING_JSON: JSON.stringify({
      "gemini-3.6-flash": {
        inputMicrousdPerMillionTokens: 1,
        outputMicrousdPerMillionTokens: 2,
      },
      "gemini-3.1-pro-preview": {
        inputMicrousdPerMillionTokens: 3,
        outputMicrousdPerMillionTokens: 4,
      },
    }),
  };
  const fetchImpl: typeof fetch = (input, init) => {
    const url = new URL(input instanceof Request ? input.url : input.toString());
    requests.push({ path: url.pathname, headers: new Headers(init?.headers) });
    const rpc = url.pathname.split("/").at(-1);
    if (rpc === "assistant_get_authority_v1") {
      return Promise.resolve(
        new Response(JSON.stringify({
          authorityTenantId: tenantId,
          actorUserId: userId,
          role: "admin",
          permissions: {},
          capabilities: [
            "ai.read.operational",
            "ai.read.sales",
            "ai.read.purchases",
            "ai.read.accounting",
          ],
          authorityFingerprint,
          asOf: "2026-08-11T12:00:00Z",
        })),
      );
    }
    if (rpc === "assistant_search_inventory_v5") {
      return Promise.resolve(
        new Response(JSON.stringify({
          authorityTenantId: tenantId,
          asOf: "2026-08-11T12:00:00Z",
          status: "verifiedEmpty",
          items: [],
          resultCount: 0,
          hasMore: false,
        })),
      );
    }
    if (rpc === "assistant_begin_run_v1") {
      return Promise.resolve(
        new Response(JSON.stringify({
          authorityTenantId: tenantId,
          actorUserId: userId,
          authorityFingerprint,
          threadId,
          runId,
          runStatus: "running",
          runDisposition: "claimed",
          replayed: false,
          leaseToken,
          fenceToken: 1,
          canonicalSummary: null,
          canonicalMessages: [{ role: "user", content: "Hola" }],
          response: null,
          terminalErrorCode: null,
          nextProviderAttemptNo: 1,
          nextToolOrdinal: 1,
        })),
      );
    }
    if (rpc === "assistant_heartbeat_run_v2") {
      return Promise.resolve(
        new Response(JSON.stringify({
          authorityTenantId: tenantId,
          runId,
          cancelRequested: false,
        })),
      );
    }
    return Promise.reject(new Error(`unexpected RPC ${rpc}`));
  };
  const production = createProductionOptions((name) => env[name], fetchImpl);
  const services = production.requestServices(
    new Request(endpoint, {
      headers: { authorization: "Bearer caller.jwt.value" },
    }),
  );
  const signal = new AbortController().signal;
  const resolved = await services.authoritySource.resolve(signal);
  await services.toolExecutor.execute(
    {
      id: "call-1",
      name: "search_inventory",
      arguments: {
        query: "cadena",
        category: null,
        availability: "any",
        presentation: "answer",
        technicalPredicates: [],
      },
    },
    resolved,
    signal,
  );
  const runLease = await services.runStore.begin({
    authority: resolved,
    clientRequestId: requestId,
    requestHash: "request-hmac",
    userContent: "Hola",
    modelRole: "fast",
    threadId: null,
    maxOutputTokens: 2048,
  }, signal);
  await services.runStore.heartbeat(runLease, signal);

  assertEquals(requests.map((entry) => entry.path), [
    "/rest/v1/rpc/assistant_get_authority_v1",
    "/rest/v1/rpc/assistant_search_inventory_v5",
    "/rest/v1/rpc/assistant_begin_run_v1",
    "/rest/v1/rpc/assistant_heartbeat_run_v2",
  ], "only fixed transports are reached");
  for (const entry of requests.slice(0, 3)) {
    assertEquals(
      entry.headers.get("apikey"),
      "sb_publishable_hosted_test",
      "caller apikey comes from hosted JSON map",
    );
    assertEquals(
      entry.headers.get("authorization"),
      "Bearer caller.jwt.value",
      "caller JWT retained",
    );
    assertEquals(entry.headers.get("content-profile"), null, "caller remains in public schema");
  }
  const runtime = requests[3].headers;
  assertEquals(
    runtime.get("apikey"),
    "sb_publishable_hosted_test",
    "runtime reuses the selected hosted publishable key",
  );
  assertEquals(
    runtime.get("authorization"),
    "Bearer caller.jwt.value",
    "runtime mutation retains caller JWT",
  );
  assertEquals(runtime.get("content-profile"), "assistant_runtime", "runtime schema is isolated");
  assertEquals(
    runtime.get("accept-profile"),
    "assistant_runtime",
    "runtime response schema isolated",
  );
});

Deno.test("production public research stays on forced Gemini even if a Browser Use key exists", () => {
  const env: Record<string, string> = {
    AI_AGENT_FAST_PROVIDER: "gemini",
    AI_AGENT_DEEP_PROVIDER: "gemini",
    AI_AGENT_VISION_PROVIDER: "gemini",
    GEMINI_API_KEY: "provider-key",
    SUPABASE_URL: "https://project.supabase.co",
    SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ default: "sb_publishable_hosted_test" }),
    AI_AGENT_RUNTIME_ATTESTATION_KID: "runtime-test",
    AI_AGENT_RUNTIME_ATTESTATION_KEY_HEX: "11".repeat(32),
    AI_AGENT_RUNTIME_ATTESTATION_AUDIENCE: "supabase:projectref:assistant-runtime",
    AI_AGENT_AUDIT_HMAC_KEY: hmacKey,
    AI_AGENT_GEMINI_SEARCH_MICROUSD_PER_QUERY: "14000",
    AI_AGENT_MODEL_PRICING_JSON: JSON.stringify({
      "gemini-3.6-flash": {
        inputMicrousdPerMillionTokens: 1,
        outputMicrousdPerMillionTokens: 2,
      },
      "gemini-3.1-pro-preview": {
        inputMicrousdPerMillionTokens: 3,
        outputMicrousdPerMillionTokens: 4,
      },
    }),
    BROWSER_USE_API_KEY: "browser-use-dedicated-key",
  };
  const production = createProductionOptions((name) => env[name], fetch);
  assertEquals(
    production.toolRegistry?.advertisedFor({
      userId,
      tenantId,
      role: "admin",
      permissions: {},
      capabilities: ["ai.read.operational"],
      authorityFingerprint,
    }).some((tool) => tool.name === "research_public_web"),
    true,
    "configured Gemini activates forced public research",
  );
  delete env.GEMINI_API_KEY;
  env.AI_AGENT_FAST_PROVIDER = "openai";
  env.AI_AGENT_DEEP_PROVIDER = "openai";
  env.AI_AGENT_VISION_PROVIDER = "openai";
  env.OPENAI_API_KEY = "provider-key";
  env.AI_AGENT_MODEL_PRICING_JSON = JSON.stringify({
    "gpt-5.6-sol": { inputMicrousdPerMillionTokens: 1, outputMicrousdPerMillionTokens: 2 },
  });
  const disabled = createProductionOptions((name) => env[name], fetch);
  assertEquals(
    disabled.toolRegistry?.advertisedFor({
      userId,
      tenantId,
      role: "admin",
      permissions: {},
      capabilities: ["ai.read.operational"],
      authorityFingerprint,
    }).some((tool) => tool.name === "research_public_web"),
    false,
    "a Browser key alone cannot activate an unattested remote browser",
  );
});

Deno.test("production provider effort remains a closed server-owned route", async () => {
  const baseEnv: Record<string, string> = {
    SUPABASE_URL: "https://project.supabase.co",
    SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ default: "sb_publishable_hosted_test" }),
    AI_AGENT_RUNTIME_ATTESTATION_KID: "runtime-test",
    AI_AGENT_RUNTIME_ATTESTATION_KEY_HEX: "11".repeat(32),
    AI_AGENT_RUNTIME_ATTESTATION_AUDIENCE: "supabase:projectref:assistant-runtime",
    AI_AGENT_AUDIT_HMAC_KEY: hmacKey,
  };
  for (const providerId of ["openai", "anthropic"] as const) {
    const bodies: Array<Record<string, unknown>> = [];
    const env: Record<string, string> = {
      ...baseEnv,
      AI_AGENT_FAST_PROVIDER: providerId,
      AI_AGENT_DEEP_PROVIDER: providerId,
      AI_AGENT_VISION_PROVIDER: providerId,
      AI_AGENT_MODEL_PRICING_JSON: providerId === "openai"
        ? JSON.stringify({
          "gpt-5.6-sol": { inputMicrousdPerMillionTokens: 1, outputMicrousdPerMillionTokens: 2 },
        })
        : JSON.stringify({
          "claude-sonnet-5": {
            inputMicrousdPerMillionTokens: 1,
            outputMicrousdPerMillionTokens: 2,
          },
          "claude-opus-5": { inputMicrousdPerMillionTokens: 3, outputMicrousdPerMillionTokens: 4 },
        }),
      ...(providerId === "openai"
        ? { OPENAI_API_KEY: "provider-key", AI_AGENT_OPENAI_DEEP_EFFORT: "max" }
        : { ANTHROPIC_API_KEY: "provider-key", AI_AGENT_ANTHROPIC_DEEP_EFFORT: "max" }),
    };
    const fetchImpl: typeof fetch = (_input, init = {}) => {
      bodies.push(JSON.parse(String(init.body)));
      return Promise.resolve(
        new Response(JSON.stringify(
          providerId === "openai"
            ? {
              status: "completed",
              output: [{ type: "message", content: [{ type: "output_text", text: "Listo." }] }],
              usage: { input_tokens: 1, output_tokens: 1, total_tokens: 2 },
            }
            : {
              type: "message",
              role: "assistant",
              model: "claude-opus-5",
              content: [{ type: "text", text: "Listo." }],
              stop_reason: "end_turn",
              usage: { input_tokens: 1, output_tokens: 1 },
            },
        )),
      );
    };
    const production = createProductionOptions((name) => env[name], fetchImpl);
    await production.providerRouter.providerFor("deep").generate({
      modelRole: "deep",
      systemInstruction: "Server policy",
      messages: [{ role: "user", text: "Analiza" }],
      tools: [],
      maxOutputTokens: 256,
    }, new AbortController().signal);
    assertEquals(
      providerId === "openai" ? bodies[0].reasoning : bodies[0].output_config,
      { effort: "max" },
      `${providerId} deep effort is selected only from server configuration`,
    );
  }
});

Deno.test("hosted publishable JSON map supports an explicit safe key name", () => {
  const env: Record<string, string> = {
    SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({
      default: "sb_publishable_default_test",
      ai_agent: "sb_publishable_agent_test",
    }),
    AI_AGENT_SUPABASE_PUBLISHABLE_KEY_NAME: "ai_agent",
  };
  assertEquals(
    resolveSupabasePublishableKey((name) => env[name], "https://project.supabase.co"),
    "sb_publishable_agent_test",
    "configured hosted key is selected from the map",
  );
});

Deno.test("local Supabase alone may use the singular compatibility fallback", () => {
  const env: Record<string, string> = {
    SUPABASE_PUBLISHABLE_KEY: "sb_publishable_local_test",
  };
  assertEquals(
    resolveSupabasePublishableKey((name) => env[name], "http://127.0.0.1:54321"),
    "sb_publishable_local_test",
    "local fallback remains available",
  );
});

Deno.test("publishable key resolution fails closed for hosted fallback and invalid maps", () => {
  const cases: Array<[Record<string, string>, string]> = [
    [{ SUPABASE_PUBLISHABLE_KEY: "sb_publishable_legacy_test" }, "https://project.supabase.co"],
    [{
      SUPABASE_PUBLISHABLE_KEYS: "{",
      SUPABASE_PUBLISHABLE_KEY: "sb_publishable_local_test",
    }, "http://127.0.0.1:54321"],
    [{
      SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ default: "not-a-publishable-key" }),
    }, "https://project.supabase.co"],
    [{
      SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ named: "sb_publishable_named_test" }),
    }, "https://project.supabase.co"],
  ];
  for (const [env, url] of cases) {
    let rejected = false;
    try {
      resolveSupabasePublishableKey((name) => env[name], url);
    } catch (_) {
      rejected = true;
    }
    assert(rejected, "invalid or unavailable hosted key configuration is rejected");
  }
});

Deno.test("gateway timeout cannot outlive its 110 second durable lease", () => {
  let rejected = false;
  try {
    const env: Record<string, string> = {
      AI_AGENT_FAST_PROVIDER: "gemini",
      AI_AGENT_DEEP_PROVIDER: "gemini",
      AI_AGENT_VISION_PROVIDER: "gemini",
      GEMINI_API_KEY: "provider-key",
      SUPABASE_URL: "https://project.supabase.co",
      SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({
        default: "sb_publishable_hosted_test",
      }),
      AI_AGENT_RUNTIME_ATTESTATION_KID: "runtime-test",
      AI_AGENT_RUNTIME_ATTESTATION_KEY_HEX: "11".repeat(32),
      AI_AGENT_RUNTIME_ATTESTATION_AUDIENCE: "supabase:projectref:assistant-runtime",
      AI_AGENT_AUDIT_HMAC_KEY: hmacKey,
      AI_AGENT_MODEL_PRICING_JSON: JSON.stringify({
        "gemini-3.6-flash": {
          inputMicrousdPerMillionTokens: 1,
          outputMicrousdPerMillionTokens: 2,
        },
        "gemini-3.1-pro-preview": {
          inputMicrousdPerMillionTokens: 3,
          outputMicrousdPerMillionTokens: 4,
        },
      }),
      AI_AGENT_TIMEOUT_MS: "90001",
    };
    createProductionOptions((name) => env[name], fetch);
  } catch (_) {
    rejected = true;
  }
  assert(rejected, "timeout above the 90 second pilot ceiling fails at startup");
});

Deno.test("Gemini research timeout cannot exceed the 70 second egress ceiling", () => {
  const env: Record<string, string> = {
    AI_AGENT_FAST_PROVIDER: "gemini",
    AI_AGENT_DEEP_PROVIDER: "gemini",
    AI_AGENT_VISION_PROVIDER: "gemini",
    GEMINI_API_KEY: "provider-key",
    SUPABASE_URL: "https://project.supabase.co",
    SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ default: "sb_publishable_hosted_test" }),
    AI_AGENT_RUNTIME_ATTESTATION_KID: "runtime-test",
    AI_AGENT_RUNTIME_ATTESTATION_KEY_HEX: "11".repeat(32),
    AI_AGENT_RUNTIME_ATTESTATION_AUDIENCE: "supabase:projectref:assistant-runtime",
    AI_AGENT_AUDIT_HMAC_KEY: hmacKey,
    AI_AGENT_GEMINI_SEARCH_MICROUSD_PER_QUERY: "14000",
    AI_AGENT_MODEL_PRICING_JSON: JSON.stringify({
      "gemini-3.6-flash": { inputMicrousdPerMillionTokens: 1, outputMicrousdPerMillionTokens: 2 },
      "gemini-3.1-pro-preview": {
        inputMicrousdPerMillionTokens: 3,
        outputMicrousdPerMillionTokens: 4,
      },
    }),
    AI_AGENT_GEMINI_RESEARCH_TIMEOUT_MS: "70001",
  };
  let rejected = false;
  try {
    createProductionOptions((name) => env[name], fetch);
  } catch (_) {
    rejected = true;
  }
  assert(rejected, "public research cannot consume the entire gateway deadline");
});

Deno.test("production output budget accepts 8192 and rejects 8193 at startup", () => {
  const env: Record<string, string> = {
    AI_AGENT_FAST_PROVIDER: "gemini",
    AI_AGENT_DEEP_PROVIDER: "gemini",
    AI_AGENT_VISION_PROVIDER: "gemini",
    GEMINI_API_KEY: "provider-key",
    SUPABASE_URL: "https://project.supabase.co",
    SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({
      default: "sb_publishable_hosted_test",
    }),
    AI_AGENT_RUNTIME_ATTESTATION_KID: "runtime-test",
    AI_AGENT_RUNTIME_ATTESTATION_KEY_HEX: "11".repeat(32),
    AI_AGENT_RUNTIME_ATTESTATION_AUDIENCE: "supabase:projectref:assistant-runtime",
    AI_AGENT_AUDIT_HMAC_KEY: hmacKey,
    AI_AGENT_GEMINI_SEARCH_MICROUSD_PER_QUERY: "14000",
    AI_AGENT_MODEL_PRICING_JSON: JSON.stringify({
      "gemini-3.6-flash": {
        inputMicrousdPerMillionTokens: 1,
        outputMicrousdPerMillionTokens: 2,
      },
      "gemini-3.1-pro-preview": {
        inputMicrousdPerMillionTokens: 3,
        outputMicrousdPerMillionTokens: 4,
      },
    }),
    AI_AGENT_MAX_OUTPUT_TOKENS: "8192",
  };
  const accepted = createProductionOptions((name) => env[name], fetch);
  assertEquals(accepted.maxOutputTokens, 8192, "8192 remains the exact shared ceiling");
  env.AI_AGENT_MAX_OUTPUT_TOKENS = "8193";
  let rejected = false;
  try {
    createProductionOptions((name) => env[name], fetch);
  } catch (_) {
    rejected = true;
  }
  assert(rejected, "8193 fails before serving requests");
});
