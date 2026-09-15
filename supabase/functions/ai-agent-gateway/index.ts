import type { AgentGatewayRequest, LogicalModelRole } from "../_shared/ai_agent/contracts.ts";
import {
  type AgentAuthorityDataSource,
  AuthorityError,
  createSupabaseAuthorityDataSource,
  resolveAgentAuthority,
} from "../_shared/ai_agent/authority.ts";
import {
  AgentToolRegistry,
  createDefaultAgentToolRegistry,
  ToolRegistryError,
} from "../_shared/ai_agent/tool_registry.ts";
import { createGeminiAgentProvider } from "../_shared/ai_agent/providers/gemini.ts";
import {
  AgentApprovalActionError,
  type AgentApprovalActionExecutor,
  createSupabaseAgentApprovalActionExecutor,
  parseApprovalActionRequest,
} from "../_shared/ai_agent/action_endpoint.ts";
import { createOpenAIResponsesProvider } from "../_shared/ai_agent/providers/openai_responses.ts";
import { createAnthropicMessagesProvider } from "../_shared/ai_agent/providers/anthropic.ts";
import {
  type AgentProviderId,
  AgentProviderRouter,
  ProviderError,
} from "../_shared/ai_agent/providers/provider.ts";
import { AgentRuntimeError, executeAgentRun } from "../_shared/ai_agent/runtime.ts";
import { type AgentRunStore, createSupabaseAgentRunStore } from "../_shared/ai_agent/run_store.ts";
import {
  type AgentToolExecutor,
  createSupabaseAgentToolExecutor,
} from "../_shared/ai_agent/tool_executor.ts";
import {
  createSupabaseRuntimeStoreClient,
  createSupabaseUserDataClient,
} from "../_shared/ai_agent/supabase_user_data.ts";
import { AgentPricingCatalog } from "../_shared/ai_agent/pricing.ts";
import { createGeminiGoogleSearchPublicResearchClient } from "../_shared/ai_agent/public_research.ts";

const DEFAULT_ALLOWED_ORIGINS = [
  "https://project-vinabike.web.app",
  "https://project-vinabike.firebaseapp.com",
  "http://localhost:54330",
  "http://127.0.0.1:54330",
] as const;
const DEFAULT_MAX_REQUEST_BYTES = 32 * 1024;
const DEFAULT_TIMEOUT_MS = 90_000;
const RESULT_LISTS_CAPABILITY_HEADER = "x-vinabike-ai-result-lists";
const STRUCTURED_CLARIFICATIONS_CAPABILITY_HEADER = "x-vinabike-ai-structured-clarifications";

type EnvReader = (name: string) => string | undefined;

export interface AgentRequestServices {
  authoritySource: AgentAuthorityDataSource;
  runStore: AgentRunStore;
  toolExecutor: AgentToolExecutor;
  approvalActionExecutor?: AgentApprovalActionExecutor;
}

export interface AgentGatewayOptions {
  providerRouter: AgentProviderRouter;
  requestServices(request: Request): AgentRequestServices;
  toolRegistry?: AgentToolRegistry;
  allowedOrigins?: readonly string[];
  systemInstruction?: string;
  auditHmacKey: string;
  maxRequestBytes?: number;
  timeoutMs?: number;
  maxOutputTokens?: number;
  pricingCatalog: AgentPricingCatalog;
}

class GatewayError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    readonly publicMessage: string,
  ) {
    super(publicMessage);
    this.name = "GatewayError";
  }
}

export async function handler(
  request: Request,
  options: AgentGatewayOptions,
): Promise<Response> {
  const allowedOrigins = normalizeAllowedOrigins(
    options.allowedOrigins ?? DEFAULT_ALLOWED_ORIGINS,
  );
  const origin = request.headers.get("origin");
  if (origin && !allowedOrigins.has(normalizeOrigin(origin))) {
    return json(request, allowedOrigins, 403, {
      error: "Origin not allowed",
      code: "origin_not_allowed",
    });
  }
  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: corsHeaders(request, allowedOrigins),
    });
  }
  if (request.method !== "POST") {
    return json(request, allowedOrigins, 405, {
      error: "Method not allowed",
      code: "method_not_allowed",
    });
  }

  const controller = new AbortController();
  const timeoutMs = boundedInteger(
    options.timeoutMs,
    DEFAULT_TIMEOUT_MS,
    1,
    90_000,
  );
  let timeoutId: ReturnType<typeof setTimeout> | undefined;
  const abortFromClient = () => {
    if (!controller.signal.aborted) controller.abort(request.signal.reason);
  };
  if (request.signal.aborted) controller.abort(request.signal.reason);
  else {request.signal.addEventListener("abort", abortFromClient, {
      once: true,
    });}

  try {
    if (request.signal.aborted) {
      throw new GatewayError(
        499,
        "request_aborted",
        "Assistant request was cancelled",
      );
    }
    timeoutId = setTimeout(() => {
      controller.abort(
        new DOMException("AI gateway deadline exceeded", "TimeoutError"),
      );
    }, timeoutMs);
    const result = await completeGatewayTurn(
      request,
      options,
      controller.signal,
    );
    return json(
      request,
      allowedOrigins,
      200,
      result as unknown as Record<string, unknown>,
    );
  } catch (error) {
    const safe = safeGatewayError(error);
    return json(request, allowedOrigins, safe.status, {
      error: safe.publicMessage,
      code: safe.code,
    });
  } finally {
    if (timeoutId !== undefined) clearTimeout(timeoutId);
    request.signal.removeEventListener("abort", abortFromClient);
  }
}

async function completeGatewayTurn(
  request: Request,
  options: AgentGatewayOptions,
  signal: AbortSignal,
) {
  // Validate the caller session before constructing any request-scoped
  // transport. The production transport intentionally rejects a missing
  // bearer header at construction time; doing this first preserves the public
  // 401 contract instead of collapsing that safe rejection into a generic 500.
  const authorization = request.headers.get("authorization") ?? "";
  const bearer = /^Bearer\s+(\S+)$/i.exec(authorization);
  if (!bearer || bearer[1].length > 8_192) {
    throw new AuthorityError(401, "invalid_session", "Authentication required");
  }
  const services = options.requestServices(request);
  const authority = await resolveAgentAuthority(
    request,
    services.authoritySource,
    signal,
  );
  const body = await readBoundedJson(
    request,
    boundedInteger(
      options.maxRequestBytes,
      DEFAULT_MAX_REQUEST_BYTES,
      1024,
      128 * 1024,
    ),
    signal,
  );
  if (isRecord(body) && body.operation === "approval_action") {
    const action = parseApprovalActionRequest(body);
    if (!services.approvalActionExecutor) {
      throw new GatewayError(
        503,
        "approval_unavailable",
        "Approval could not be completed",
      );
    }
    return await services.approvalActionExecutor.apply(
      action,
      authority,
      signal,
    );
  }
  const parsed = parseGatewayRequest(body);
  return await executeAgentRun(parsed, authority, {
    providerRouter: options.providerRouter,
    toolRegistry: options.toolRegistry ?? createDefaultAgentToolRegistry(),
    toolExecutor: services.toolExecutor,
    runStore: services.runStore,
    auditHmacKey: options.auditHmacKey,
    systemInstruction: options.systemInstruction,
    maxOutputTokens: options.maxOutputTokens,
    pricingCatalog: options.pricingCatalog,
    supportsResultLists: request.headers.get(RESULT_LISTS_CAPABILITY_HEADER) === "1",
    supportsStructuredClarifications:
      request.headers.get(STRUCTURED_CLARIFICATIONS_CAPABILITY_HEADER) === "1",
  }, signal);
}

export function createProductionOptions(
  getEnv: EnvReader = (name) => Deno.env.get(name),
  fetchImpl: typeof fetch = fetch,
): AgentGatewayOptions {
  const providerRoutes: Record<
    LogicalModelRole,
    { provider: AgentProviderId }
  > = {
    fast: { provider: configuredProvider(getEnv("AI_AGENT_FAST_PROVIDER")) },
    deep: { provider: configuredProvider(getEnv("AI_AGENT_DEEP_PROVIDER")) },
    vision: {
      provider: configuredProvider(getEnv("AI_AGENT_VISION_PROVIDER")),
    },
  };
  const selectedProviders = new Set(
    Object.values(providerRoutes).map((route) => route.provider),
  );
  const providers = [];
  if (selectedProviders.has("gemini")) {
    const allowedModels = csvValues(getEnv("AI_AGENT_GEMINI_MODEL_ALLOWLIST"));
    providers.push(createGeminiAgentProvider({
      apiKey: requiredEnv(getEnv, "GEMINI_API_KEY"),
      fetchImpl,
      allowedModels: allowedModels.length ? allowedModels : undefined,
      modelByRole: {
        fast: getEnv("AI_AGENT_GEMINI_FAST_MODEL")?.trim() ||
          "gemini-3.6-flash",
        // El rol profundo dejó de apuntar a un *preview*: el 2026-08-21
        // `gemini-3.1-pro-preview` rechazaba por cuota 12 de cada 12 llamadas.
        deep: getEnv("AI_AGENT_GEMINI_DEEP_MODEL")?.trim() ||
          "gemini-3.7-flash",
        vision: getEnv("AI_AGENT_GEMINI_VISION_MODEL")?.trim() ||
          "gemini-3.6-flash",
      },
    }));
  }
  if (selectedProviders.has("openai")) {
    const allowedModels = csvValues(getEnv("AI_AGENT_OPENAI_MODEL_ALLOWLIST"));
    providers.push(createOpenAIResponsesProvider({
      apiKey: requiredEnv(getEnv, "OPENAI_API_KEY"),
      fetchImpl,
      allowedModels: allowedModels.length ? allowedModels : undefined,
      modelByRole: {
        fast: getEnv("AI_AGENT_OPENAI_FAST_MODEL")?.trim() || "gpt-5.6-sol",
        deep: getEnv("AI_AGENT_OPENAI_DEEP_MODEL")?.trim() || "gpt-5.6-sol",
        vision: getEnv("AI_AGENT_OPENAI_VISION_MODEL")?.trim() || "gpt-5.6-sol",
      },
      reasoningEffortByRole: {
        fast: configuredOpenAIEffort(
          getEnv("AI_AGENT_OPENAI_FAST_EFFORT"),
          "medium",
        ),
        deep: configuredOpenAIEffort(
          getEnv("AI_AGENT_OPENAI_DEEP_EFFORT"),
          "high",
        ),
        vision: configuredOpenAIEffort(
          getEnv("AI_AGENT_OPENAI_VISION_EFFORT"),
          "medium",
        ),
      },
    }));
  }
  if (selectedProviders.has("anthropic")) {
    const allowedModels = csvValues(
      getEnv("AI_AGENT_ANTHROPIC_MODEL_ALLOWLIST"),
    );
    providers.push(createAnthropicMessagesProvider({
      apiKey: requiredEnv(getEnv, "ANTHROPIC_API_KEY"),
      fetchImpl,
      allowedModels: allowedModels.length ? allowedModels : undefined,
      modelByRole: {
        fast: getEnv("AI_AGENT_ANTHROPIC_FAST_MODEL")?.trim() ||
          "claude-sonnet-5",
        deep: getEnv("AI_AGENT_ANTHROPIC_DEEP_MODEL")?.trim() ||
          "claude-opus-5",
        vision: getEnv("AI_AGENT_ANTHROPIC_VISION_MODEL")?.trim() ||
          "claude-sonnet-5",
      },
      effortByRole: {
        fast: configuredProviderEffort(
          getEnv("AI_AGENT_ANTHROPIC_FAST_EFFORT"),
          "low",
        ),
        deep: configuredProviderEffort(
          getEnv("AI_AGENT_ANTHROPIC_DEEP_EFFORT"),
          "high",
        ),
        vision: configuredProviderEffort(
          getEnv("AI_AGENT_ANTHROPIC_VISION_EFFORT"),
          "medium",
        ),
      },
    }));
  }
  const supabaseUrl = requiredEnv(getEnv, "SUPABASE_URL");
  const publishableKey = resolveSupabasePublishableKey(getEnv, supabaseUrl);
  const runtimeAttestationKeyId = requiredEnv(
    getEnv,
    "AI_AGENT_RUNTIME_ATTESTATION_KID",
  );
  const runtimeAttestationKeyHex = requiredEnv(
    getEnv,
    "AI_AGENT_RUNTIME_ATTESTATION_KEY_HEX",
  );
  const runtimeAttestationAudience = requiredEnv(
    getEnv,
    "AI_AGENT_RUNTIME_ATTESTATION_AUDIENCE",
  );
  const timeoutMs = optionalInteger(getEnv("AI_AGENT_TIMEOUT_MS"));
  if (timeoutMs !== undefined) {
    boundedInteger(timeoutMs, DEFAULT_TIMEOUT_MS, 1, 90_000);
  }
  const maxOutputTokens = optionalInteger(getEnv("AI_AGENT_MAX_OUTPUT_TOKENS"));
  if (maxOutputTokens !== undefined) boundedOutputTokens(maxOutputTokens);
  const geminiResearchApiKey = getEnv("GEMINI_API_KEY")?.trim();
  const pricingCatalog = AgentPricingCatalog.parse(
    requiredEnv(getEnv, "AI_AGENT_MODEL_PRICING_JSON"),
  );
  // Public research uses the provider-native, forced Google Search contract.
  // Browser Use remains implemented but deliberately dormant: its current API
  // cannot prove a provider-side read-only action policy or attest every
  // visited URL, so merely adding a key must never silently widen authority.
  const publicResearch = geminiResearchApiKey
    ? createGeminiGoogleSearchPublicResearchClient({
      apiKey: geminiResearchApiKey,
      fetchImpl,
      model: getEnv("AI_AGENT_GEMINI_RESEARCH_MODEL")?.trim() ||
        "gemini-3.6-flash",
      timeoutMs: optionalInteger(getEnv("AI_AGENT_GEMINI_RESEARCH_TIMEOUT_MS")),
      pricingCatalog,
      searchMicrousdPerQuery: requiredInteger(
        getEnv,
        "AI_AGENT_GEMINI_SEARCH_MICROUSD_PER_QUERY",
      ),
      // Search establishes publisher evidence. URL Context then reads only the
      // validated direct publisher URLs to fill unresolved subfacts; any
      // enrichment failure preserves the proven Search result as partial.
      enrichWithUrlContext: true,
      // Technical facts are finally re-read from the exact selected publisher
      // pages. Only deterministic page text can authorize field-level quotes;
      // Gemini's grounded prose remains useful context but not a specification.
      enrichWithPublisherContent: true,
      resolvePublisherDns: (hostname, recordType) => Deno.resolveDns(hostname, recordType),
    })
    : undefined;
  return {
    providerRouter: new AgentProviderRouter({
      providers,
      routes: providerRoutes,
    }),
    requestServices(request) {
      const authorization = request.headers.get("authorization") ?? "";
      const client = createSupabaseUserDataClient({
        supabaseUrl,
        publishableKey,
        authorization,
        fetchImpl,
      });
      const runtimeClient = createSupabaseRuntimeStoreClient({
        supabaseUrl,
        publishableKey,
        authorization,
        attestationKeyId: runtimeAttestationKeyId,
        attestationKeyHex: runtimeAttestationKeyHex,
        attestationAudience: runtimeAttestationAudience,
        fetchImpl,
      });
      return {
        authoritySource: createSupabaseAuthorityDataSource(client),
        runStore: createSupabaseAgentRunStore(client, runtimeClient),
        toolExecutor: createSupabaseAgentToolExecutor(client, {
          publicResearch,
        }),
        approvalActionExecutor: createSupabaseAgentApprovalActionExecutor(
          client,
        ),
      };
    },
    toolRegistry: createDefaultAgentToolRegistry({
      publicResearch: Boolean(publicResearch),
    }),
    allowedOrigins: [
      ...DEFAULT_ALLOWED_ORIGINS,
      ...csvValues(getEnv("AI_AGENT_CORS_ALLOWED_ORIGINS")),
    ],
    systemInstruction: getEnv("AI_AGENT_SYSTEM_INSTRUCTION")?.trim(),
    auditHmacKey: requiredEnv(getEnv, "AI_AGENT_AUDIT_HMAC_KEY"),
    pricingCatalog,
    maxRequestBytes: optionalInteger(getEnv("AI_AGENT_MAX_REQUEST_BYTES")),
    timeoutMs,
    maxOutputTokens,
  };
}

export function parseGatewayRequest(value: unknown): AgentGatewayRequest {
  if (!isRecord(value)) return invalidRequest();
  const allowedKeys = value.threadId === undefined
    ? ["version", "clientRequestId", "modelRole", "message", "viewContext"]
    : [
      "version",
      "clientRequestId",
      "threadId",
      "modelRole",
      "message",
      "viewContext",
    ];
  if (!hasExactKeys(value, allowedKeys) || value.version !== 1) {
    return invalidRequest();
  }
  if (
    !validUuid(value.clientRequestId) ||
    (value.threadId !== undefined && value.threadId !== null &&
      !validUuid(value.threadId))
  ) {
    return invalidRequest();
  }
  if (value.modelRole !== "fast" && value.modelRole !== "deep") {
    return invalidRequest();
  }
  if (typeof value.message !== "string") return invalidRequest();
  const message = value.message.trim();
  if (!message || new TextEncoder().encode(message).byteLength > 8192) {
    return invalidRequest();
  }
  const viewContext = parseViewContext(value.viewContext);
  return {
    version: 1,
    clientRequestId: value.clientRequestId,
    threadId: value.threadId ?? null,
    modelRole: value.modelRole,
    message,
    viewContext,
  };
}

function parseViewContext(value: unknown): AgentGatewayRequest["viewContext"] {
  if (
    !isRecord(value) || !hasExactKeys(value, ["kind", "jobIds", "truncated"])
  ) {
    return invalidRequest();
  }
  if (!Array.isArray(value.jobIds) || typeof value.truncated !== "boolean") {
    return invalidRequest();
  }
  if (
    value.kind === "none" || value.kind === "rejected" ||
    value.kind === "intelligent_purchasing"
  ) {
    if (value.jobIds.length || value.truncated) return invalidRequest();
    return { kind: value.kind, jobIds: [], truncated: false };
  }
  if (
    value.kind !== "workshop_jobs" || value.jobIds.length > 20 ||
    value.jobIds.length < 1
  ) {
    return invalidRequest();
  }
  if (
    !value.jobIds.every(validUuid) ||
    new Set(value.jobIds).size !== value.jobIds.length
  ) {
    return invalidRequest();
  }
  return {
    kind: "workshop_jobs",
    jobIds: value.jobIds,
    truncated: value.truncated,
  };
}

export function isAllowedCorsOrigin(
  origin: string,
  configured: readonly string[] = DEFAULT_ALLOWED_ORIGINS,
): boolean {
  return normalizeAllowedOrigins(configured).has(normalizeOrigin(origin));
}

async function readBoundedJson(
  request: Request,
  maxBytes: number,
  signal: AbortSignal,
): Promise<unknown> {
  const contentLength = Number(request.headers.get("content-length"));
  if (Number.isFinite(contentLength) && contentLength > maxBytes) {
    throw new GatewayError(
      413,
      "request_too_large",
      "Assistant request is too large",
    );
  }
  const reader = request.body?.getReader();
  if (!reader) {
    throw new GatewayError(
      400,
      "invalid_json",
      "Assistant request must be valid JSON",
    );
  }
  const abortReader = () => void reader.cancel("request_aborted").catch(() => {});
  signal.addEventListener("abort", abortReader, { once: true });
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      if (signal.aborted) {
        throw new GatewayError(
          504,
          "request_timeout",
          "Assistant request timed out",
        );
      }
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maxBytes) {
        await reader.cancel("request_too_large");
        throw new GatewayError(
          413,
          "request_too_large",
          "Assistant request is too large",
        );
      }
      chunks.push(value);
    }
  } catch (error) {
    if (error instanceof GatewayError) throw error;
    throw new GatewayError(
      400,
      "invalid_json",
      "Assistant request must be valid JSON",
    );
  } finally {
    signal.removeEventListener("abort", abortReader);
    reader.releaseLock();
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch (_) {
    throw new GatewayError(
      400,
      "invalid_json",
      "Assistant request must be valid JSON",
    );
  }
}

function safeGatewayError(error: unknown): GatewayError {
  if (error instanceof GatewayError) return error;
  if (error instanceof AgentApprovalActionError) {
    return new GatewayError(error.status, error.code, error.publicMessage);
  }
  if (
    error instanceof AuthorityError || error instanceof ToolRegistryError ||
    error instanceof AgentRuntimeError
  ) {
    return new GatewayError(error.status, error.code, error.publicMessage);
  }
  if (error instanceof ProviderError) {
    return new GatewayError(
      502,
      error.code,
      "AI provider is temporarily unavailable",
    );
  }
  return new GatewayError(
    500,
    "assistant_unavailable",
    "Assistant is temporarily unavailable",
  );
}

function json(
  request: Request,
  origins: ReadonlySet<string>,
  status: number,
  body: Record<string, unknown>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(request, origins),
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

function corsHeaders(
  request: Request,
  origins: ReadonlySet<string>,
): HeadersInit {
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers":
      `authorization, x-client-info, apikey, content-type, ${RESULT_LISTS_CAPABILITY_HEADER}, ${STRUCTURED_CLARIFICATIONS_CAPABILITY_HEADER}`,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
  const origin = normalizeOrigin(request.headers.get("origin") ?? "");
  if (origins.has(origin)) headers["Access-Control-Allow-Origin"] = origin;
  return headers;
}

function normalizeAllowedOrigins(
  values: readonly string[],
): ReadonlySet<string> {
  const result = new Set<string>();
  for (const value of values) {
    if (value.trim() === "*") {
      throw new Error("Wildcard CORS origins are forbidden");
    }
    const origin = normalizeOrigin(value);
    if (origin) result.add(origin);
  }
  return result;
}

function normalizeOrigin(value: string): string {
  try {
    const url = new URL(value);
    return url.origin === "null" ? "" : url.origin;
  } catch (_) {
    return "";
  }
}

function configuredProvider(value: string | undefined): AgentProviderId {
  const provider = value?.trim().toLowerCase() || "gemini";
  if (
    provider !== "gemini" && provider !== "openai" && provider !== "anthropic"
  ) {
    throw new Error("AI provider route is not allowed");
  }
  return provider;
}

function configuredOpenAIEffort(
  value: string | undefined,
  fallback: "medium" | "high",
): "low" | "medium" | "high" | "xhigh" | "max" {
  return configuredProviderEffort(value, fallback);
}

function configuredProviderEffort(
  value: string | undefined,
  fallback: "low" | "medium" | "high",
): "low" | "medium" | "high" | "xhigh" | "max" {
  const effort = value?.trim().toLowerCase() || fallback;
  if (
    effort !== "low" && effort !== "medium" && effort !== "high" &&
    effort !== "xhigh" &&
    effort !== "max"
  ) {
    throw new Error("AI reasoning effort is not allowed");
  }
  return effort;
}

export function resolveSupabasePublishableKey(
  getEnv: EnvReader,
  supabaseUrl: string,
): string {
  const rawMap = getEnv("SUPABASE_PUBLISHABLE_KEYS")?.trim();
  if (rawMap) {
    let parsed: unknown;
    try {
      parsed = JSON.parse(rawMap);
    } catch (_) {
      throw new Error("Supabase publishable key map is invalid");
    }
    if (!isRecord(parsed) || Object.keys(parsed).length === 0) {
      throw new Error("Supabase publishable key map is invalid");
    }
    const validated = new Map<string, string>();
    for (const [name, value] of Object.entries(parsed)) {
      if (!validPublishableKeyName(name) || !validPublishableKey(value)) {
        throw new Error("Supabase publishable key map is invalid");
      }
      validated.set(name, value);
    }
    const selectedName = getEnv("AI_AGENT_SUPABASE_PUBLISHABLE_KEY_NAME")?.trim() || "default";
    if (!validPublishableKeyName(selectedName)) {
      throw new Error("Supabase publishable key name is invalid");
    }
    const selected = validated.get(selectedName);
    if (!selected) {
      throw new Error("Supabase publishable key is not configured");
    }
    return selected;
  }

  if (isLocalSupabaseUrl(supabaseUrl)) {
    const fallback = getEnv("SUPABASE_PUBLISHABLE_KEY")?.trim();
    if (validPublishableKey(fallback)) return fallback;
  }
  throw new Error("Supabase publishable key is not configured");
}

function validPublishableKeyName(value: string): boolean {
  return /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(value);
}

function validPublishableKey(value: unknown): value is string {
  return typeof value === "string" &&
    /^sb_publishable_[A-Za-z0-9_-]{4,512}$/.test(value);
}

function isLocalSupabaseUrl(value: string): boolean {
  try {
    return ["localhost", "127.0.0.1", "::1"].includes(new URL(value).hostname);
  } catch (_) {
    return false;
  }
}

function requiredEnv(getEnv: EnvReader, name: string): string {
  const value = getEnv(name)?.trim();
  if (!value) throw new Error(`${name} is not configured`);
  return value;
}
function csvValues(value: string | undefined): string[] {
  return (value ?? "").split(",").map((item) => item.trim()).filter(Boolean);
}
function optionalInteger(value: string | undefined): number | undefined {
  if (!value?.trim()) return undefined;
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed)) {
    throw new Error("AI gateway limit is invalid");
  }
  return parsed;
}
function requiredInteger(getEnv: EnvReader, name: string): number {
  const value = optionalInteger(requiredEnv(getEnv, name));
  if (value === undefined) throw new Error(`${name} is not configured`);
  return value;
}
function boundedOutputTokens(value: number): number {
  if (value < 64 || value > 8192) {
    throw new Error("AI gateway output limit is invalid");
  }
  return value;
}
function boundedInteger(
  value: number | undefined,
  fallback: number,
  min: number,
  max: number,
): number {
  const result = value ?? fallback;
  if (!Number.isSafeInteger(result) || result < min || result > max) {
    throw new Error("AI gateway limit is invalid");
  }
  return result;
}
function invalidRequest(): never {
  throw new GatewayError(400, "invalid_request", "Invalid assistant request");
}
function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}
function hasExactKeys(
  value: Record<string, unknown>,
  expected: readonly string[],
): boolean {
  return JSON.stringify(Object.keys(value).sort()) ===
    JSON.stringify([...expected].sort());
}
function validUuid(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

if (import.meta.main) {
  const options = createProductionOptions();
  Deno.serve((request) => handler(request, options));
}
