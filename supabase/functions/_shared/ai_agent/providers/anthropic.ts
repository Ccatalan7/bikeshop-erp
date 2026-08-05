import {
  type AgentFinishReason,
  type AgentMessage,
  type AgentProviderTurn,
  type AgentToolCall,
  type AgentToolDefinition,
  type AgentUsage,
  emptyUsage,
  isJsonObject,
  type JsonObject,
  type JsonValue,
  type LogicalModelRole,
  logicalModelRoles,
  type StrictJsonSchema,
} from "../contracts.ts";
import { type AgentModelProvider, ProviderError } from "./provider.ts";
import { discardProviderBody, readProviderJson } from "./http.ts";

const DEFAULT_ANTHROPIC_ENDPOINT = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_API_VERSION = "2023-06-01";
const MAX_CONTINUATION_TOKEN_LENGTH = 512 * 1024;
const TOOL_NAME_PATTERN = /^[a-zA-Z0-9_-]{1,64}$/;

const defaultModels: Readonly<Record<LogicalModelRole, string>> = {
  fast: "claude-sonnet-5",
  deep: "claude-opus-5",
  vision: "claude-sonnet-5",
};

export type AnthropicEffort = "low" | "medium" | "high" | "xhigh" | "max";

const defaultEffort: Readonly<Record<LogicalModelRole, AnthropicEffort>> = {
  fast: "low",
  deep: "high",
  vision: "medium",
};

export interface AnthropicMessagesProviderConfig {
  apiKey: string;
  fetchImpl?: typeof fetch;
  endpoint?: string;
  modelByRole?: Readonly<Record<LogicalModelRole, string>>;
  allowedModels?: readonly string[];
  effortByRole?: Readonly<Record<LogicalModelRole, AnthropicEffort>>;
}

interface AnthropicContinuationGroup {
  readonly callIds: readonly string[];
  readonly callNames: readonly string[];
  readonly text: string;
  readonly blocks: readonly JsonObject[];
}

interface AnthropicContinuationState {
  readonly version: 1;
  readonly model: string;
  readonly groups: readonly AnthropicContinuationGroup[];
}

export function createAnthropicMessagesProvider(
  config: AnthropicMessagesProviderConfig,
): AgentModelProvider {
  const apiKey = requireValue(config.apiKey, "Anthropic API key");
  const fetchImpl = config.fetchImpl ?? fetch;
  const endpoint = validateEndpoint(config.endpoint ?? DEFAULT_ANTHROPIC_ENDPOINT);
  const modelByRole = Object.freeze({
    ...(config.modelByRole ?? defaultModels),
  });
  const allowedModels = new Set(
    config.allowedModels ?? ["claude-sonnet-5", "claude-opus-5"],
  );
  const effortByRole = Object.freeze({
    ...(config.effortByRole ?? defaultEffort),
  });
  assertServerModelConfiguration(modelByRole, allowedModels);
  assertServerEffortConfiguration(effortByRole);

  return {
    id: "anthropic",
    async generate(request, signal) {
      if (signal.aborted) {
        throw new ProviderError("provider_unavailable", 503, true);
      }
      const model = modelByRole[request.modelRole];
      const continuation = decodeAnthropicContinuation(
        request.continuationToken,
        model,
      );
      const hasToolContinuation = request.messages.some((message) =>
        message.role === "assistant" && (message.toolCalls?.length ?? 0) > 0
      );
      if (hasToolContinuation !== (continuation.groups.length > 0)) {
        throw invalidProviderResponse();
      }
      const tools = anthropicTools(request.tools);
      const toolNames = new Set(request.tools.map((tool) => tool.name));
      const payload = {
        model,
        max_tokens: request.maxOutputTokens,
        system: request.systemInstruction,
        messages: anthropicMessages(
          request.messages,
          continuation.groups,
          toolNames,
        ),
        tools: tools.length > 0 ? tools : undefined,
        thinking: { type: "adaptive", display: "omitted" },
        output_config: { effort: effortByRole[request.modelRole] },
      };

      let response: Response;
      try {
        response = await fetchImpl(endpoint, {
          method: "POST",
          headers: {
            "anthropic-version": ANTHROPIC_API_VERSION,
            "Content-Type": "application/json",
            "x-api-key": apiKey,
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
      return normalizeAnthropicResponse(body, continuation, model, toolNames);
    },
  };
}

function anthropicTools(tools: readonly AgentToolDefinition[]): JsonObject[] {
  const names = new Set<string>();
  return tools.map((tool) => {
    if (
      !TOOL_NAME_PATTERN.test(tool.name) || names.has(tool.name) ||
      !tool.description.trim() || !isClosedObjectSchema(tool.parameters)
    ) {
      throw invalidProviderResponse();
    }
    names.add(tool.name);
    return {
      name: tool.name,
      description: tool.description,
      input_schema: tool.parameters as unknown as JsonObject,
      strict: true,
    };
  });
}

function isClosedObjectSchema(schema: StrictJsonSchema): boolean {
  if (schema.type !== "object" || schema.additionalProperties !== false) return false;
  const properties = schema.properties ?? {};
  if (
    schema.required?.some((name, index, required) =>
      !Object.hasOwn(properties, name) || required.indexOf(name) !== index
    )
  ) {
    return false;
  }
  return Object.values(properties).every(isClosedNestedSchema);
}

function isClosedNestedSchema(schema: StrictJsonSchema): boolean {
  const types = Array.isArray(schema.type) ? schema.type : [schema.type];
  if (types.includes("object")) {
    if (schema.additionalProperties !== false) return false;
    const properties = schema.properties ?? {};
    if (
      schema.required?.some((name, index, required) =>
        !Object.hasOwn(properties, name) || required.indexOf(name) !== index
      )
    ) {
      return false;
    }
    if (!Object.values(properties).every(isClosedNestedSchema)) return false;
  }
  if (types.includes("array") && (!schema.items || !isClosedNestedSchema(schema.items))) {
    return false;
  }
  return true;
}

function anthropicMessages(
  messages: readonly AgentMessage[],
  continuationGroups: readonly AnthropicContinuationGroup[],
  availableToolNames: ReadonlySet<string>,
): JsonObject[] {
  const output: JsonObject[] = [];
  let continuationIndex = 0;
  let index = 0;
  while (index < messages.length) {
    const message = messages[index];
    if (message.role === "tool") {
      throw invalidProviderResponse();
    }

    if (message.role === "assistant" && (message.toolCalls?.length ?? 0) > 0) {
      const calls = message.toolCalls ?? [];
      if (calls.some((call) => !availableToolNames.has(call.name))) {
        throw invalidProviderResponse();
      }
      const continuation = continuationGroups[continuationIndex++];
      const continuationCalls = continuation?.blocks.filter((block) => block.type === "tool_use") ??
        [];
      if (
        !continuation || continuation.text !== message.text.trim() ||
        !sameStrings(continuation.callIds, calls.map((call) => call.id)) ||
        !sameStrings(continuation.callNames, calls.map((call) => call.name)) ||
        !calls.every((call, callIndex) =>
          sameJsonValue(call.arguments, continuationCalls[callIndex]?.input)
        )
      ) {
        throw invalidProviderResponse();
      }
      output.push({ role: "assistant", content: [...continuation.blocks] });
      const toolResults: JsonObject[] = [];
      for (let callIndex = 0; callIndex < calls.length; callIndex++) {
        const result = messages[++index];
        if (
          !result || result.role !== "tool" ||
          result.toolCallId !== calls[callIndex].id ||
          result.toolName !== calls[callIndex].name
        ) {
          throw invalidProviderResponse();
        }
        toolResults.push({
          type: "tool_result",
          tool_use_id: result.toolCallId,
          content: result.text,
        });
      }
      output.push({ role: "user", content: toolResults });
      index++;
      continue;
    }

    const content: JsonObject[] = message.text ? [{ type: "text", text: message.text }] : [];
    output.push({
      role: message.role === "assistant" ? "assistant" : "user",
      content,
    });
    index++;
  }

  if (continuationIndex !== continuationGroups.length) {
    throw invalidProviderResponse();
  }
  if (output.at(-1)?.role === "assistant") {
    // Current server-owned routes do not support assistant prefills.
    throw invalidProviderResponse();
  }
  return output;
}

function normalizeAnthropicResponse(
  value: unknown,
  continuation: AnthropicContinuationState,
  expectedModel: string,
  availableToolNames: ReadonlySet<string>,
): AgentProviderTurn {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw invalidProviderResponse();
  }
  const body = value as Record<string, unknown>;
  if (
    body.type !== "message" || body.role !== "assistant" ||
    body.model !== expectedModel || !Array.isArray(body.content)
  ) {
    throw invalidProviderResponse();
  }

  const text: string[] = [];
  const toolCalls: AgentToolCall[] = [];
  const continuationBlocks: JsonObject[] = [];
  for (const rawBlock of body.content) {
    if (!isJsonObject(rawBlock)) throw invalidProviderResponse();
    const block = rawBlock as JsonObject;
    assertValidAnthropicBlock(block);
    continuationBlocks.push(block);
    if (block.type === "text") text.push(block.text as string);
    if (block.type === "tool_use") {
      if (!availableToolNames.has(block.name as string)) {
        throw invalidProviderResponse();
      }
      toolCalls.push({
        id: block.id as string,
        name: block.name as string,
        arguments: block.input as JsonObject,
      });
    }
  }

  if (body.stop_reason === "tool_use" && toolCalls.length === 0) {
    throw invalidProviderResponse();
  }
  if (body.stop_reason !== "tool_use" && toolCalls.length > 0) {
    throw invalidProviderResponse();
  }
  const priorCallIds = new Set(
    continuation.groups.flatMap((group) => group.callIds),
  );
  if (
    new Set(toolCalls.map((call) => call.id)).size !== toolCalls.length ||
    toolCalls.some((call) => priorCallIds.has(call.id))
  ) {
    throw invalidProviderResponse();
  }
  const normalizedText = text.join("").trim();
  const nextContinuation: AnthropicContinuationState = {
    version: 1,
    model: expectedModel,
    groups: toolCalls.length > 0
      ? [
        ...continuation.groups,
        {
          callIds: toolCalls.map((call) => call.id),
          callNames: toolCalls.map((call) => call.name),
          text: normalizedText,
          blocks: continuationBlocks,
        },
      ]
      : continuation.groups,
  };
  const continuationToken = toolCalls.length > 0 ? encodeContinuation(nextContinuation) : undefined;

  return {
    text: normalizedText,
    toolCalls,
    usage: parseAnthropicUsage(body.usage),
    finishReason: anthropicFinishReason(body.stop_reason, toolCalls),
    continuationToken,
  };
}

function assertValidAnthropicBlock(block: JsonObject): void {
  switch (block.type) {
    case "text":
      if (typeof block.text !== "string") throw invalidProviderResponse();
      return;
    case "thinking":
      if (
        typeof block.thinking !== "string" ||
        typeof block.signature !== "string" || !block.signature
      ) {
        throw invalidProviderResponse();
      }
      return;
    case "redacted_thinking":
      if (typeof block.data !== "string" || !block.data) {
        throw invalidProviderResponse();
      }
      return;
    case "tool_use":
      if (
        typeof block.id !== "string" || !block.id ||
        typeof block.name !== "string" || !block.name ||
        !isJsonObject(block.input)
      ) {
        throw invalidProviderResponse();
      }
      return;
    default:
      throw invalidProviderResponse();
  }
}

function parseAnthropicUsage(value: unknown): AgentUsage {
  if (!value || typeof value !== "object" || Array.isArray(value)) return emptyUsage();
  const usage = value as Record<string, unknown>;
  const inputTokens = safeTokenCount(usage.input_tokens) +
    safeTokenCount(usage.cache_creation_input_tokens) +
    safeTokenCount(usage.cache_read_input_tokens);
  const outputTokens = safeTokenCount(usage.output_tokens);
  return { inputTokens, outputTokens, totalTokens: inputTokens + outputTokens };
}

function anthropicFinishReason(
  value: unknown,
  calls: readonly AgentToolCall[],
): AgentFinishReason {
  if (calls.length > 0) return "tool_calls";
  switch (value) {
    case "end_turn":
    case "stop_sequence":
      return "stop";
    case "max_tokens":
    case "model_context_window_exceeded":
      return "length";
    case "refusal":
      return "blocked";
    default:
      return "unknown";
  }
}

function encodeContinuation(value: AnthropicContinuationState): string {
  const token = encodeBase64Url(new TextEncoder().encode(JSON.stringify(value)));
  if (token.length > MAX_CONTINUATION_TOKEN_LENGTH) {
    // The caller must never execute calls whose exact thinking/tool stream can
    // no longer be replayed under the decoder's hard limit.
    throw invalidProviderResponse();
  }
  return token;
}

function decodeAnthropicContinuation(
  token: string | undefined,
  expectedModel: string,
): AnthropicContinuationState {
  if (!token) return { version: 1, model: expectedModel, groups: [] };
  if (token.length > MAX_CONTINUATION_TOKEN_LENGTH) {
    throw invalidProviderResponse();
  }
  try {
    const decoded = new TextDecoder("utf-8", { fatal: true }).decode(decodeBase64Url(token));
    const value = JSON.parse(decoded);
    if (!isAnthropicContinuationState(value, expectedModel)) throw new Error();
    return value;
  } catch (_) {
    throw invalidProviderResponse();
  }
}

function isAnthropicContinuationState(
  value: unknown,
  expectedModel: string,
): value is AnthropicContinuationState {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const state = value as Record<string, unknown>;
  if (state.version !== 1 || state.model !== expectedModel || !Array.isArray(state.groups)) {
    return false;
  }
  const seenCallIds = new Set<string>();
  return state.groups.every((rawGroup) => {
    if (!rawGroup || typeof rawGroup !== "object" || Array.isArray(rawGroup)) return false;
    const group = rawGroup as Record<string, unknown>;
    if (
      !Array.isArray(group.callIds) || group.callIds.length === 0 ||
      !group.callIds.every((id) => typeof id === "string" && id.length > 0) ||
      new Set(group.callIds).size !== group.callIds.length ||
      group.callIds.some((id) => seenCallIds.has(id as string)) ||
      !Array.isArray(group.callNames) ||
      !group.callNames.every((name) => typeof name === "string" && name.length > 0) ||
      group.callNames.length !== group.callIds.length || typeof group.text !== "string" ||
      !Array.isArray(group.blocks) || group.blocks.length === 0 ||
      !group.blocks.every(isJsonObject)
    ) {
      return false;
    }
    const blocks = group.blocks as JsonObject[];
    try {
      blocks.forEach(assertValidAnthropicBlock);
    } catch (_) {
      return false;
    }
    const calls = blocks.flatMap((block) =>
      block.type === "tool_use" ? [{ id: block.id as string, name: block.name as string }] : []
    );
    const text = blocks
      .filter((block) => block.type === "text")
      .map((block) => block.text as string)
      .join("")
      .trim();
    const valid = text === group.text &&
      sameStrings(calls.map((call) => call.id), group.callIds as string[]) &&
      sameStrings(calls.map((call) => call.name), group.callNames as string[]);
    if (valid) {
      for (const callId of group.callIds as string[]) seenCallIds.add(callId);
    }
    return valid;
  });
}

function assertServerModelConfiguration(
  models: Readonly<Record<LogicalModelRole, string>>,
  allowlist: ReadonlySet<string>,
): void {
  for (const role of logicalModelRoles) {
    const model = models[role];
    if (!model || !allowlist.has(model)) {
      throw new Error("Anthropic model route is outside the server allowlist");
    }
  }
}

function assertServerEffortConfiguration(
  efforts: Readonly<Record<LogicalModelRole, AnthropicEffort>>,
): void {
  const allowed = new Set<AnthropicEffort>(["low", "medium", "high", "xhigh", "max"]);
  for (const role of logicalModelRoles) {
    if (!allowed.has(efforts[role])) {
      throw new Error("Anthropic effort route is outside the server allowlist");
    }
  }
}

function validateEndpoint(value: string): string {
  const url = new URL(value);
  if (url.protocol !== "https:" || url.username || url.password || url.hash) {
    throw new Error("Anthropic endpoint must use credential-free HTTPS");
  }
  return url.toString();
}

function requireValue(value: string, label: string): string {
  if (!value.trim()) throw new Error(`${label} is not configured`);
  return value.trim();
}

function safeTokenCount(value: unknown): number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ? value : 0;
}

function sameStrings(left: readonly string[], right: readonly string[]): boolean {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}

function sameJsonValue(left: JsonValue, right: JsonValue | undefined): boolean {
  if (left === null || right === null || typeof left !== "object" || typeof right !== "object") {
    return left === right;
  }
  if (Array.isArray(left) || Array.isArray(right)) {
    return Array.isArray(left) && Array.isArray(right) && left.length === right.length &&
      left.every((value, index) => sameJsonValue(value, right[index]));
  }
  const leftKeys = Object.keys(left).sort();
  const rightKeys = Object.keys(right).sort();
  return sameStrings(leftKeys, rightKeys) &&
    leftKeys.every((key) => sameJsonValue(left[key], right[key]));
}

function invalidProviderResponse(): ProviderError {
  return new ProviderError("provider_invalid_response", 502, false);
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
