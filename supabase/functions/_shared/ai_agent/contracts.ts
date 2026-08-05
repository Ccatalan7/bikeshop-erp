export const logicalModelRoles = ["fast", "deep", "vision"] as const;

export type LogicalModelRole = (typeof logicalModelRoles)[number];

export type JsonPrimitive = string | number | boolean | null;
export type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue };
export type JsonObject = { [key: string]: JsonValue };

export interface AgentAuthority {
  userId: string;
  tenantId: string;
  role: string;
  permissions: Readonly<Record<string, boolean>>;
}

export interface AgentToolCall {
  id: string;
  name: string;
  arguments: JsonObject;
}

export type AgentMessage =
  | {
    role: "system" | "user";
    text: string;
  }
  | {
    role: "assistant";
    text: string;
    toolCalls?: readonly AgentToolCall[];
  }
  | {
    role: "tool";
    text: string;
    toolCallId: string;
    toolName: string;
  };

export interface StrictJsonSchema {
  type: string | readonly string[];
  description?: string;
  properties?: Readonly<Record<string, StrictJsonSchema>>;
  required?: readonly string[];
  additionalProperties?: false;
  items?: StrictJsonSchema;
  enum?: readonly JsonPrimitive[];
  minLength?: number;
  maxLength?: number;
  minimum?: number;
  maximum?: number;
  minItems?: number;
  maxItems?: number;
}

export interface AgentToolDefinition {
  name: string;
  description: string;
  parameters: StrictJsonSchema;
  requiredPermissions: readonly string[];
}

export interface AgentUsage {
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
}

export type AgentFinishReason = "stop" | "tool_calls" | "length" | "blocked" | "unknown";

export interface AgentProviderRequest {
  modelRole: LogicalModelRole;
  systemInstruction: string;
  messages: readonly AgentMessage[];
  tools: readonly AgentToolDefinition[];
  maxOutputTokens: number;
  continuationToken?: string;
}

export interface AgentProviderTurn {
  text: string;
  toolCalls: readonly AgentToolCall[];
  usage: AgentUsage;
  finishReason: AgentFinishReason;
  continuationToken?: string;
}

export interface AgentGatewayRequest {
  modelRole: LogicalModelRole;
  messages: readonly AgentMessage[];
}

export function isLogicalModelRole(value: unknown): value is LogicalModelRole {
  return typeof value === "string" && (logicalModelRoles as readonly string[]).includes(value);
}

export function isJsonObject(value: unknown): value is JsonObject {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  return Object.values(value).every(isJsonValue);
}

export function isJsonValue(value: unknown): value is JsonValue {
  if (value === null) return true;
  if (["string", "number", "boolean"].includes(typeof value)) {
    return typeof value !== "number" || Number.isFinite(value);
  }
  if (Array.isArray(value)) return value.every(isJsonValue);
  return isJsonObject(value);
}

export function emptyUsage(): AgentUsage {
  return { inputTokens: 0, outputTokens: 0, totalTokens: 0 };
}
