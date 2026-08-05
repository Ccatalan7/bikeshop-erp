import {
  type AgentGatewayRequest,
  type AgentMessage,
  isLogicalModelRole,
  type LogicalModelRole,
} from "../_shared/ai_agent/contracts.ts";
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
import { createOpenAIResponsesProvider } from "../_shared/ai_agent/providers/openai_responses.ts";
import {
  type AgentProviderId,
  AgentProviderRouter,
  ProviderError,
} from "../_shared/ai_agent/providers/provider.ts";

const DEFAULT_ALLOWED_ORIGINS = [
  "https://project-vinabike.web.app",
  "https://project-vinabike.firebaseapp.com",
  "http://localhost:54330",
  "http://127.0.0.1:54330",
] as const;

const DEFAULT_MAX_REQUEST_BYTES = 128 * 1024;
const DEFAULT_MAX_MESSAGES = 60;
const DEFAULT_MAX_TOOL_TURNS = 5;
const DEFAULT_TIMEOUT_MS = 30_000;
const DEFAULT_MAX_OUTPUT_TOKENS = 2_048;
const MAX_TEXT_CHARS = 64 * 1024;
const MAX_PROVIDER_TEXT_CHARS = 256 * 1024;

type EnvReader = (name: string) => string | undefined;

export interface AgentGatewayOptions {
  authoritySource: AgentAuthorityDataSource;
  providerRouter: AgentProviderRouter;
  toolRegistry?: AgentToolRegistry;
  allowedOrigins?: readonly string[];
  systemInstruction?: string;
  maxRequestBytes?: number;
  maxMessages?: number;
  maxTurns?: number;
  timeoutMs?: number;
  maxOutputTokens?: number;
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

export async function handler(request: Request, options: AgentGatewayOptions): Promise<Response> {
  const allowedOrigins = normalizeAllowedOrigins(options.allowedOrigins ?? DEFAULT_ALLOWED_ORIGINS);
  const origin = request.headers.get("origin");
  if (origin && !allowedOrigins.has(normalizeOrigin(origin))) {
    return json(request, allowedOrigins, 403, {
      error: "Origin not allowed",
      code: "origin_not_allowed",
    });
  }

  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(request, allowedOrigins) });
  }
  if (request.method !== "POST") {
    return json(request, allowedOrigins, 405, {
      error: "Method not allowed",
      code: "method_not_allowed",
    });
  }

  const controller = new AbortController();
  const timeoutMs = boundedInteger(options.timeoutMs, DEFAULT_TIMEOUT_MS, 1, 120_000);
  let timeoutId: ReturnType<typeof setTimeout> | undefined;
  let rejectClientAbort: ((reason: GatewayError) => void) | undefined;
  const clientAbort = new Promise<never>((_, reject) => {
    rejectClientAbort = reject;
  });
  const abortFromClient = () => {
    if (!controller.signal.aborted) controller.abort(request.signal.reason);
    rejectClientAbort?.(
      new GatewayError(499, "request_aborted", "Assistant request was cancelled"),
    );
  };
  const clientAlreadyAborted = request.signal.aborted;
  if (clientAlreadyAborted) {
    controller.abort(request.signal.reason);
  } else {
    request.signal.addEventListener("abort", abortFromClient, { once: true });
  }
  try {
    if (clientAlreadyAborted) {
      throw new GatewayError(499, "request_aborted", "Assistant request was cancelled");
    }
    const result = await Promise.race([
      completeGatewayTurn(request, options, controller.signal),
      clientAbort,
      new Promise<never>((_, reject) => {
        timeoutId = setTimeout(() => {
          controller.abort(new DOMException("AI gateway deadline exceeded", "TimeoutError"));
          reject(new GatewayError(504, "request_timeout", "Assistant request timed out"));
        }, timeoutMs);
      }),
    ]);
    return json(request, allowedOrigins, 200, result);
  } catch (error) {
    const safe = safeGatewayError(error);
    return json(request, allowedOrigins, safe.status, {
      error: safe.publicMessage,
      code: safe.code,
    });
  } finally {
    if (timeoutId !== undefined) clearTimeout(timeoutId);
    request.signal.removeEventListener("abort", abortFromClient);
    rejectClientAbort = undefined;
  }
}

async function completeGatewayTurn(
  request: Request,
  options: AgentGatewayOptions,
  signal: AbortSignal,
): Promise<Record<string, unknown>> {
  const maxRequestBytes = boundedInteger(
    options.maxRequestBytes,
    DEFAULT_MAX_REQUEST_BYTES,
    1_024,
    1024 * 1024,
  );
  const authority = await resolveAgentAuthority(request, options.authoritySource, signal);
  const body = await readBoundedJson(request, maxRequestBytes, signal);
  const parsed = parseGatewayRequest(
    body,
    boundedInteger(options.maxMessages, DEFAULT_MAX_MESSAGES, 1, 200),
    boundedInteger(options.maxTurns, DEFAULT_MAX_TOOL_TURNS, 1, 20),
  );
  const toolRegistry = options.toolRegistry ?? createDefaultAgentToolRegistry();
  const tools = toolRegistry.advertisedFor(authority);
  const provider = options.providerRouter.providerFor(parsed.modelRole);
  const turn = await provider.generate({
    modelRole: parsed.modelRole,
    systemInstruction: options.systemInstruction ?? defaultSystemInstruction(),
    messages: parsed.messages,
    tools,
    maxOutputTokens: boundedInteger(
      options.maxOutputTokens,
      DEFAULT_MAX_OUTPUT_TOKENS,
      64,
      8_192,
    ),
  }, signal);
  if (turn.text.length > MAX_PROVIDER_TEXT_CHARS) {
    throw new GatewayError(502, "provider_invalid_response", "AI provider response is invalid");
  }
  toolRegistry.validateProviderCalls(turn.toolCalls, authority);
  if (turn.toolCalls.length > 0) {
    throw new GatewayError(
      501,
      "agent_tool_loop_not_activated",
      "Server-owned AI tool execution is not activated",
    );
  }

  return {
    turn: {
      text: turn.text,
      toolCalls: turn.toolCalls,
      usage: turn.usage,
      finishReason: turn.finishReason,
    },
    modelRole: parsed.modelRole,
  };
}

export function createProductionOptions(
  getEnv: EnvReader = (name) => Deno.env.get(name),
  fetchImpl: typeof fetch = fetch,
): AgentGatewayOptions {
  const providerRoutes: Record<LogicalModelRole, { provider: AgentProviderId }> = {
    fast: { provider: configuredProvider(getEnv("AI_AGENT_FAST_PROVIDER")) },
    deep: { provider: configuredProvider(getEnv("AI_AGENT_DEEP_PROVIDER")) },
    vision: { provider: configuredProvider(getEnv("AI_AGENT_VISION_PROVIDER")) },
  };
  const selectedProviders = new Set(Object.values(providerRoutes).map((route) => route.provider));
  const providers = [];

  if (selectedProviders.has("gemini")) {
    const allowedModels = csvValues(getEnv("AI_AGENT_GEMINI_MODEL_ALLOWLIST"));
    providers.push(createGeminiAgentProvider({
      apiKey: requiredEnv(getEnv, "GEMINI_API_KEY"),
      fetchImpl,
      allowedModels: allowedModels.length > 0 ? allowedModels : undefined,
      modelByRole: {
        fast: getEnv("AI_AGENT_GEMINI_FAST_MODEL")?.trim() || "gemini-2.5-flash-lite",
        deep: getEnv("AI_AGENT_GEMINI_DEEP_MODEL")?.trim() || "gemini-2.5-flash",
        vision: getEnv("AI_AGENT_GEMINI_VISION_MODEL")?.trim() || "gemini-2.5-flash",
      },
    }));
  }
  if (selectedProviders.has("openai")) {
    const allowedModels = csvValues(getEnv("AI_AGENT_OPENAI_MODEL_ALLOWLIST"));
    providers.push(createOpenAIResponsesProvider({
      apiKey: requiredEnv(getEnv, "OPENAI_API_KEY"),
      fetchImpl,
      allowedModels: allowedModels.length > 0 ? allowedModels : undefined,
      modelByRole: {
        fast: getEnv("AI_AGENT_OPENAI_FAST_MODEL")?.trim() || "gpt-5.6-sol",
        deep: getEnv("AI_AGENT_OPENAI_DEEP_MODEL")?.trim() || "gpt-5.6-sol",
        vision: getEnv("AI_AGENT_OPENAI_VISION_MODEL")?.trim() || "gpt-5.6-sol",
      },
    }));
  }

  return {
    authoritySource: createSupabaseAuthorityDataSource({
      supabaseUrl: requiredEnv(getEnv, "SUPABASE_URL"),
      anonKey: requiredEnv(getEnv, "SUPABASE_ANON_KEY"),
      serviceRoleKey: requiredEnv(getEnv, "SUPABASE_SERVICE_ROLE_KEY"),
      fetchImpl,
    }),
    providerRouter: new AgentProviderRouter({ providers, routes: providerRoutes }),
    allowedOrigins: [
      ...DEFAULT_ALLOWED_ORIGINS,
      ...csvValues(getEnv("AI_AGENT_CORS_ALLOWED_ORIGINS")),
    ],
    toolRegistry: createDefaultAgentToolRegistry(),
    systemInstruction: getEnv("AI_AGENT_SYSTEM_INSTRUCTION")?.trim() || defaultSystemInstruction(),
    maxRequestBytes: optionalInteger(getEnv("AI_AGENT_MAX_REQUEST_BYTES")),
    maxMessages: optionalInteger(getEnv("AI_AGENT_MAX_MESSAGES")),
    maxTurns: optionalInteger(getEnv("AI_AGENT_MAX_TURNS")),
    timeoutMs: optionalInteger(getEnv("AI_AGENT_TIMEOUT_MS")),
    maxOutputTokens: optionalInteger(getEnv("AI_AGENT_MAX_OUTPUT_TOKENS")),
  };
}

export function parseGatewayRequest(
  value: unknown,
  maxMessages = DEFAULT_MAX_MESSAGES,
  maxTurns = DEFAULT_MAX_TOOL_TURNS,
): AgentGatewayRequest {
  if (!isRecord(value) || !hasExactKeys(value, ["messages", "modelRole"])) {
    throw new GatewayError(400, "invalid_request", "Invalid assistant request");
  }
  if (!isLogicalModelRole(value.modelRole) || !Array.isArray(value.messages)) {
    throw new GatewayError(400, "invalid_request", "Invalid assistant request");
  }
  if (value.messages.length < 1 || value.messages.length > maxMessages) {
    throw new GatewayError(400, "message_limit_exceeded", "Assistant message limit exceeded");
  }

  const messages = value.messages.map(parseClientMessage);
  if (messages.length > maxTurns) {
    throw new GatewayError(400, "turn_limit_exceeded", "Assistant turn limit exceeded");
  }
  const last = messages[messages.length - 1];
  if (!last || (last.role !== "user" && last.role !== "tool")) {
    throw new GatewayError(400, "invalid_request", "Assistant input must end with user data");
  }
  return { modelRole: value.modelRole, messages };
}

export function isAllowedCorsOrigin(
  origin: string,
  configured: readonly string[] = DEFAULT_ALLOWED_ORIGINS,
): boolean {
  return normalizeAllowedOrigins(configured).has(normalizeOrigin(origin));
}

function parseClientMessage(value: unknown): AgentMessage {
  if (!isRecord(value) || typeof value.role !== "string") {
    throw new GatewayError(400, "invalid_request", "Invalid assistant message");
  }
  if (value.role === "system") {
    throw new GatewayError(400, "system_prompt_forbidden", "System instructions are server-owned");
  }
  if (value.role === "user") {
    if (!hasExactKeys(value, ["role", "text"])) return invalidMessage();
    return { role: "user", text: boundedText(value.text, false) };
  }
  if (value.role === "assistant") {
    throw new GatewayError(
      400,
      "assistant_history_forbidden",
      "Assistant history is server-owned",
    );
  }
  if (value.role === "tool") {
    throw new GatewayError(
      400,
      "tool_history_forbidden",
      "Tool execution history is server-owned",
    );
  }
  return invalidMessage();
}

async function readBoundedJson(
  request: Request,
  maxBytes: number,
  signal: AbortSignal,
): Promise<unknown> {
  const contentLength = Number(request.headers.get("content-length"));
  if (Number.isFinite(contentLength) && contentLength > maxBytes) {
    throw new GatewayError(413, "request_too_large", "Assistant request is too large");
  }
  const reader = request.body?.getReader();
  if (!reader) throw new GatewayError(400, "invalid_json", "Assistant request must be valid JSON");
  const abortReader = () => {
    void reader.cancel("request_timeout").catch(() => {});
  };
  signal.addEventListener("abort", abortReader, { once: true });
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;
  try {
    while (true) {
      if (signal.aborted) {
        throw new GatewayError(504, "request_timeout", "Assistant request timed out");
      }
      const { done, value } = await reader.read();
      if (done) break;
      totalBytes += value.byteLength;
      if (totalBytes > maxBytes) {
        await reader.cancel("request_too_large");
        throw new GatewayError(413, "request_too_large", "Assistant request is too large");
      }
      chunks.push(value);
    }
  } catch (error) {
    if (error instanceof GatewayError) throw error;
    throw new GatewayError(400, "invalid_json", "Assistant request must be valid JSON");
  } finally {
    signal.removeEventListener("abort", abortReader);
    reader.releaseLock();
  }
  const bytes = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  let raw: string;
  try {
    raw = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch (_) {
    throw new GatewayError(400, "invalid_json", "Assistant request must be valid JSON");
  }
  try {
    return JSON.parse(raw);
  } catch (_) {
    throw new GatewayError(400, "invalid_json", "Assistant request must be valid JSON");
  }
}

function safeGatewayError(error: unknown): GatewayError {
  if (error instanceof GatewayError) return error;
  if (error instanceof AuthorityError) {
    return new GatewayError(error.status, error.code, error.publicMessage);
  }
  if (error instanceof ToolRegistryError) {
    return new GatewayError(error.status, error.code, error.publicMessage);
  }
  if (error instanceof ProviderError) {
    const status = error.status === 429 ? 429 : error.status === 408 ? 504 : 502;
    return new GatewayError(status, error.code, "AI provider is temporarily unavailable");
  }
  return new GatewayError(500, "assistant_unavailable", "Assistant is temporarily unavailable");
}

function json(
  request: Request,
  allowedOrigins: ReadonlySet<string>,
  status: number,
  body: Record<string, unknown>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(request, allowedOrigins),
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

function corsHeaders(request: Request, allowedOrigins: ReadonlySet<string>): HeadersInit {
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
  const origin = normalizeOrigin(request.headers.get("origin") ?? "");
  if (allowedOrigins.has(origin)) headers["Access-Control-Allow-Origin"] = origin;
  return headers;
}

function normalizeAllowedOrigins(values: readonly string[]): ReadonlySet<string> {
  const origins = new Set<string>();
  for (const value of values) {
    if (value.trim() === "*") throw new Error("Wildcard CORS origins are forbidden");
    const origin = normalizeOrigin(value);
    if (origin) origins.add(origin);
  }
  return origins;
}

function normalizeOrigin(value: string): string {
  try {
    const url = new URL(value);
    return url.origin === "null" ? "" : url.origin;
  } catch (_) {
    return "";
  }
}

function defaultSystemInstruction(): string {
  return "Eres el asistente operativo de Viñabike. Usa sólo herramientas anunciadas por el " +
    "servidor, no inventes datos del ERP y pide confirmación antes de cualquier acción sensible.";
}

function configuredProvider(value: string | undefined): AgentProviderId {
  const provider = value?.trim().toLowerCase() || "gemini";
  if (provider !== "gemini" && provider !== "openai") {
    throw new Error("AI provider route is not allowed");
  }
  return provider;
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
  if (!Number.isSafeInteger(parsed)) throw new Error("AI gateway limit is invalid");
  return parsed;
}

function boundedInteger(
  value: number | undefined,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  if (value === undefined) return fallback;
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    throw new Error("AI gateway limit is invalid");
  }
  return value;
}

function boundedText(value: unknown, allowEmpty: boolean): string {
  if (
    typeof value !== "string" || value.length > MAX_TEXT_CHARS || (!allowEmpty && !value.trim())
  ) {
    return invalidMessage();
  }
  return value;
}

function invalidMessage(): never {
  throw new GatewayError(400, "invalid_request", "Invalid assistant message");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, expected: readonly string[]): boolean {
  const actual = Object.keys(value).sort();
  return JSON.stringify(actual) === JSON.stringify([...expected].sort());
}

if (import.meta.main) {
  const options = createProductionOptions();
  Deno.serve((request) => handler(request, options));
}
