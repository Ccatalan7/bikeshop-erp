import {
  type AgentFinishReason,
  type AgentMessage,
  type AgentProviderTurn,
  type AgentToolCall,
  type AgentUsage,
  emptyUsage,
  isJsonObject,
  type JsonObject,
  type LogicalModelRole,
} from "../contracts.ts";
import { type AgentModelProvider, ProviderError } from "./provider.ts";
import { discardProviderBody, readProviderJson } from "./http.ts";

const DEFAULT_OPENAI_MODEL = "gpt-5.6-sol";

export interface OpenAIResponsesProviderConfig {
  apiKey: string;
  fetchImpl?: typeof fetch;
  endpoint?: string;
  modelByRole?: Readonly<Record<LogicalModelRole, string>>;
  allowedModels?: readonly string[];
}

interface OpenAIContinuationGroup {
  readonly callIds: readonly string[];
  readonly text: string;
  readonly items: readonly JsonObject[];
}

interface OpenAIContinuationState {
  readonly version: 2;
  readonly groups: readonly OpenAIContinuationGroup[];
}

export function createOpenAIResponsesProvider(
  config: OpenAIResponsesProviderConfig,
): AgentModelProvider {
  const apiKey = requireValue(config.apiKey, "OpenAI API key");
  const fetchImpl = config.fetchImpl ?? fetch;
  const endpoint = validateEndpoint(config.endpoint ?? "https://api.openai.com/v1/responses");
  const allowedModels = new Set(config.allowedModels ?? [DEFAULT_OPENAI_MODEL]);
  const modelByRole = config.modelByRole ?? {
    fast: DEFAULT_OPENAI_MODEL,
    deep: DEFAULT_OPENAI_MODEL,
    vision: DEFAULT_OPENAI_MODEL,
  };
  assertServerModelConfiguration(modelByRole, allowedModels);

  return {
    id: "openai",
    async generate(request, signal) {
      const model = modelByRole[request.modelRole];
      const hasToolContinuation = request.messages.some((message) =>
        message.role === "assistant" && (message.toolCalls?.length ?? 0) > 0
      );
      if (hasToolContinuation && !request.continuationToken) {
        throw new ProviderError("provider_invalid_response", 502, false);
      }
      const continuation = decodeOpenAIContinuation(request.continuationToken);
      if (!hasToolContinuation && continuation.groups.length > 0) {
        throw new ProviderError("provider_invalid_response", 502, false);
      }
      const payload = {
        model,
        instructions: request.systemInstruction,
        input: openAIInputWithContinuation(request.messages, continuation.groups),
        tools: request.tools.map((tool) => ({
          type: "function",
          name: tool.name,
          description: tool.description,
          parameters: tool.parameters,
          strict: true,
        })),
        parallel_tool_calls: false,
        max_output_tokens: request.maxOutputTokens,
        include: ["reasoning.encrypted_content"],
        store: false,
      };

      let response: Response;
      try {
        response = await fetchImpl(endpoint, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${apiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(payload),
          signal,
        });
      } catch (_) {
        throw new ProviderError("provider_unavailable", 503, true);
      }

      if (!response.ok) {
        await discardProviderBody(response);
        const retryable = response.status === 408 || response.status === 429 ||
          response.status >= 500;
        throw new ProviderError(
          retryable ? "provider_unavailable" : "provider_rejected",
          response.status,
          retryable,
        );
      }

      const body = await readProviderJson(response, signal);
      return normalizeOpenAIResponse(body, continuation);
    },
  };
}

function openAIInputWithContinuation(
  messages: readonly AgentMessage[],
  continuationGroups: readonly OpenAIContinuationGroup[],
): JsonObject[] {
  const input: JsonObject[] = [];
  let continuationIndex = 0;
  for (const message of messages) {
    if (message.role === "assistant" && (message.toolCalls?.length ?? 0) > 0) {
      const continuationGroup = continuationGroups[continuationIndex++];
      const callIds = (message.toolCalls ?? []).map((call) => call.id);
      if (!continuationGroup || !sameStrings(continuationGroup.callIds, callIds)) {
        throw new ProviderError("provider_invalid_response", 502, false);
      }
      if (continuationGroup.text !== message.text.trim()) {
        throw new ProviderError("provider_invalid_response", 502, false);
      }
      // The Responses API emits one chronological output item stream. Replay
      // it exactly: reasoning may be interleaved with multiple calls, and a
      // non-reasoning model may emit function calls with no encrypted item.
      input.push(...continuationGroup.items);
      continue;
    }
    input.push(...openAIInputItems(message));
  }
  if (continuationIndex !== continuationGroups.length) {
    throw new ProviderError("provider_invalid_response", 502, false);
  }
  return input;
}

function openAIInputItems(message: AgentMessage): JsonObject[] {
  if (message.role === "tool") {
    return [{
      type: "function_call_output",
      call_id: message.toolCallId,
      output: message.text,
    }];
  }

  const output: JsonObject[] = [];
  if (message.text) output.push({ role: message.role, content: message.text });
  if (message.role === "assistant") {
    for (const call of message.toolCalls ?? []) {
      output.push({
        type: "function_call",
        call_id: call.id,
        name: call.name,
        arguments: JSON.stringify(call.arguments),
      });
    }
  }
  return output;
}

function normalizeOpenAIResponse(
  value: unknown,
  continuation: OpenAIContinuationState,
): AgentProviderTurn {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ProviderError("provider_invalid_response", 502, false);
  }
  const body = value as Record<string, unknown>;
  if (!Array.isArray(body.output)) {
    throw new ProviderError("provider_invalid_response", 502, false);
  }

  const text: string[] = [];
  const toolCalls: AgentToolCall[] = [];
  const continuationItems: JsonObject[] = [];
  for (const rawItem of body.output) {
    if (!isJsonObject(rawItem)) {
      throw new ProviderError("provider_invalid_response", 502, false);
    }
    const item = rawItem as JsonObject;
    continuationItems.push(item);
    if (item.type === "message" && Array.isArray(item.content)) {
      for (const rawContent of item.content) {
        if (!rawContent || typeof rawContent !== "object" || Array.isArray(rawContent)) continue;
        const content = rawContent as Record<string, unknown>;
        if (content.type === "output_text" && typeof content.text === "string") {
          text.push(content.text);
        }
      }
    }
    if (item.type === "function_call") {
      const call = parseOpenAIFunctionCall(item);
      if (call) toolCalls.push(call);
    }
  }

  const nextContinuation: OpenAIContinuationState = {
    version: 2,
    groups: toolCalls.length > 0
      ? [
        ...continuation.groups,
        {
          callIds: toolCalls.map((call) => call.id),
          text: text.join("").trim(),
          items: continuationItems,
        },
      ]
      : continuation.groups,
  };
  const continuationToken = toolCalls.length > 0 ? encodeContinuation(nextContinuation) : undefined;

  return {
    text: text.join("").trim(),
    toolCalls,
    usage: parseOpenAIUsage(body.usage),
    finishReason: openAIFinishReason(body, toolCalls),
    continuationToken,
  };
}

function parseOpenAIFunctionCall(item: Record<string, unknown>): AgentToolCall | null {
  if (
    typeof item.call_id !== "string" || !item.call_id ||
    typeof item.name !== "string" || !item.name ||
    typeof item.arguments !== "string"
  ) {
    throw new ProviderError("provider_invalid_response", 502, false);
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(item.arguments);
  } catch (_) {
    throw new ProviderError("provider_invalid_response", 502, false);
  }
  if (!isJsonObject(parsed)) {
    throw new ProviderError("provider_invalid_response", 502, false);
  }
  return { id: item.call_id, name: item.name, arguments: parsed };
}

function parseOpenAIUsage(value: unknown): AgentUsage {
  if (!value || typeof value !== "object" || Array.isArray(value)) return emptyUsage();
  const usage = value as Record<string, unknown>;
  const inputTokens = safeTokenCount(usage.input_tokens);
  const outputTokens = safeTokenCount(usage.output_tokens);
  return {
    inputTokens,
    outputTokens,
    totalTokens: safeTokenCount(usage.total_tokens) || inputTokens + outputTokens,
  };
}

function openAIFinishReason(
  body: Record<string, unknown>,
  calls: readonly AgentToolCall[],
): AgentFinishReason {
  if (calls.length > 0) return "tool_calls";
  if (body.status === "completed") return "stop";
  const incomplete = body.incomplete_details;
  if (incomplete && typeof incomplete === "object" && !Array.isArray(incomplete)) {
    const reason = (incomplete as Record<string, unknown>).reason;
    if (reason === "max_output_tokens") return "length";
    if (reason === "content_filter") return "blocked";
  }
  return "unknown";
}

function assertServerModelConfiguration(
  models: Readonly<Record<LogicalModelRole, string>>,
  allowlist: ReadonlySet<string>,
): void {
  for (const model of Object.values(models)) {
    if (!model || !allowlist.has(model)) {
      throw new Error("OpenAI model route is outside the server allowlist");
    }
  }
}

function validateEndpoint(value: string): string {
  const url = new URL(value);
  if (url.protocol !== "https:") throw new Error("OpenAI endpoint must use HTTPS");
  return url.toString();
}

function requireValue(value: string, label: string): string {
  if (!value.trim()) throw new Error(`${label} is not configured`);
  return value;
}

function safeTokenCount(value: unknown): number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ? value : 0;
}

function encodeContinuation(value: OpenAIContinuationState): string {
  const token = encodeBase64Url(new TextEncoder().encode(JSON.stringify(value)));
  if (token.length > 512 * 1024) {
    // Never release executable calls whose server-owned continuation state
    // already exceeds the decoder's hard limit.
    throw new ProviderError("provider_invalid_response", 502, false);
  }
  return token;
}

function decodeOpenAIContinuation(token: string | undefined): OpenAIContinuationState {
  if (!token) return { version: 2, groups: [] };
  if (token.length > 512 * 1024) {
    throw new ProviderError("provider_invalid_response", 502, false);
  }
  try {
    const decoded = new TextDecoder().decode(decodeBase64Url(token));
    const value = JSON.parse(decoded);
    if (!isOpenAIContinuationState(value)) throw new Error();
    return value;
  } catch (_) {
    throw new ProviderError("provider_invalid_response", 502, false);
  }
}

function isOpenAIContinuationState(value: unknown): value is OpenAIContinuationState {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const state = value as Record<string, unknown>;
  if (state.version !== 2 || !Array.isArray(state.groups)) return false;
  return state.groups.every((rawGroup) => {
    if (!rawGroup || typeof rawGroup !== "object" || Array.isArray(rawGroup)) return false;
    const group = rawGroup as Record<string, unknown>;
    if (
      !(Array.isArray(group.callIds) && group.callIds.length > 0 &&
        group.callIds.every((callId) => typeof callId === "string" && callId.length > 0) &&
        typeof group.text === "string" && Array.isArray(group.items) &&
        group.items.length > 0 && group.items.every(isJsonObject))
    ) {
      return false;
    }
    const callIds = group.items.flatMap((rawItem) => {
      const item = rawItem as Record<string, unknown>;
      return item.type === "function_call" && typeof item.call_id === "string"
        ? [item.call_id]
        : [];
    });
    return sameStrings(callIds, group.callIds) &&
      continuationText(group.items as readonly JsonObject[]) === group.text;
  });
}

function continuationText(items: readonly JsonObject[]): string {
  const text: string[] = [];
  for (const item of items) {
    if (item.type !== "message" || !Array.isArray(item.content)) continue;
    for (const rawContent of item.content) {
      if (!isJsonObject(rawContent)) continue;
      if (rawContent.type === "output_text" && typeof rawContent.text === "string") {
        text.push(rawContent.text);
      }
    }
  }
  return text.join("").trim();
}

function sameStrings(left: readonly string[], right: readonly string[]): boolean {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}

function encodeBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function decodeBase64Url(value: string): Uint8Array {
  const normalized = value.replaceAll("-", "+").replaceAll("_", "/");
  const padded = normalized + "=".repeat((4 - normalized.length % 4) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}
