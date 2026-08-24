export const logicalModelRoles = ["fast", "deep", "vision"] as const;

export type LogicalModelRole = (typeof logicalModelRoles)[number];

export type JsonPrimitive = string | number | boolean | null;
export type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue };
export type JsonObject = { [key: string]: JsonValue };

export const agentCapabilities = [
  "ai.read.operational",
  "ai.read.sales",
  "ai.read.purchases",
  "ai.read.accounting",
  "ai.write.workshop",
] as const;

export type AgentCapability = (typeof agentCapabilities)[number];

export interface AgentAuthority {
  userId: string;
  tenantId: string;
  role: string;
  permissions: Readonly<Record<string, boolean>>;
  capabilities: readonly AgentCapability[];
  authorityFingerprint: string;
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
  /// Parte de `inputTokens` que el proveedor sirvió desde su caché.
  cachedInputTokens?: number;
}

/// `malformed_tool_call` es el modelo intentando llamar una herramienta y
/// produciendo JSON inválido —el `MALFORMED_FUNCTION_CALL` de Gemini—. No es un
/// proveedor caído ni una respuesta prohibida: es un fallo de formato, y por
/// eso tiene su propio nombre. Confundirlo con `unknown` mataba la corrida
/// entera cuando bastaba con volver a preguntar.
export type AgentFinishReason =
  | "stop"
  | "tool_calls"
  | "length"
  | "blocked"
  | "malformed_tool_call"
  | "unknown";

export interface AgentProviderRequest {
  modelRole: LogicalModelRole;
  systemInstruction: string;
  messages: readonly AgentMessage[];
  tools: readonly AgentToolDefinition[];
  requiredToolName?: string;
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
  version: 1;
  clientRequestId: string;
  threadId: string | null;
  modelRole: LogicalModelRole;
  message: string;
  viewContext: AgentViewContext;
}

export type AgentViewContext =
  | {
    kind: "none" | "rejected" | "intelligent_purchasing";
    jobIds: readonly [];
    truncated: false;
  }
  | { kind: "workshop_jobs"; jobIds: readonly string[]; truncated: boolean };

export const agentCardDestinations = [
  "customers",
  "suppliers",
  "workshop_jobs",
  "sales_invoices",
  "purchases",
  "inventory_products",
  "tasks",
  "expenses",
  "conversations",
] as const;

export type AgentCardDestination = (typeof agentCardDestinations)[number];

export type AgentEntityKind =
  | "workshopJob"
  | "customer"
  | "salesInvoice"
  | "supplier"
  | "purchaseInvoice"
  | "product"
  | "expense"
  | "conversation";

export interface AgentEntityRef {
  kind: AgentEntityKind;
  id: string;
}

export const agentInventoryAvailabilityFilters = [
  "any",
  "in_stock",
  "low_stock",
  "out_of_stock",
] as const;

export type AgentInventoryAvailabilityFilter = (typeof agentInventoryAvailabilityFilters)[number];

/**
 * A server-projected result set that the client can reopen without asking the
 * model to invent a route or independently reconstruct the selected rows.
 * `kind` is a discriminator so other ERP lists can join this closed union.
 */
export interface AgentInventoryListRef {
  kind: "inventory";
  /// Texto para el buscador local del cliente. Con el resultado completo la
  /// lista navega por ids y esto es sólo un rótulo; con el resultado truncado
  /// es lo que permite reencontrar las filas.
  query: string;
  /// Cómo se le nombra al operador lo que está viendo. Es distinto de `query`
  /// a propósito: la frase que él tipeó («camara 29») y lo que el asistente
  /// entendió («Cámaras») no son la misma cosa, y una sola cadena obligaba a
  /// elegir entre rotular mal la lista o hablarle con palabras ajenas.
  spokenSubject: string;
  availability: AgentInventoryAvailabilityFilter;
  resultCount: number;
  hasMore: boolean;
  entityIds: readonly string[] | null;
  autoOpen: boolean;
}

export type AgentListRef = AgentInventoryListRef;

export interface AgentSupplyNeedTechnicalPredicate {
  field: string;
  operator: "eq" | "neq" | "lt" | "lte" | "gt" | "gte" | "between" | "in" | "contains";
  values: readonly (string | number | boolean)[];
}

export interface AgentSupplyNeedClarificationOption {
  value: string;
  label: string;
}

export interface AgentSupplyNeedClarificationPrompt {
  id: string;
  question: string;
  inputKind: "single_choice" | "text" | "number";
  options: readonly AgentSupplyNeedClarificationOption[];
  unit: string | null;
  allowUnknown: boolean;
}

export interface AgentSupplyNeedDraftLine {
  lineRef: string;
  description: string;
  productId: string | null;
  productName: string | null;
  productSku: string | null;
  identityState: "unresolved" | "confirmed";
  /// Procedencia de categoría resuelta por el servidor. Sobrevive al turno
  /// dentro de la tarjeta cerrada y vuelve intacta al comando durable; la
  /// familia técnica se deriva en cada lectura y no se guarda.
  categoryId: string | null;
  categoryPath: string | null;
  technicalFamily: string | null;
  quantity: number;
  unit: string;
  technicalPredicates: readonly AgentSupplyNeedTechnicalPredicate[];
  preference: string | null;
  clarification: string | null;
  clarificationRequired: boolean;
  clarificationPrompts: readonly AgentSupplyNeedClarificationPrompt[];
}

export interface AgentSupplyNeedDraft {
  profile: "balanced" | "profitability" | "urgent_local";
  lines: readonly AgentSupplyNeedDraftLine[];
}

/// Una opción que el operador puede elegir en la tarjeta. Elegir NO ejecuta:
/// abre la revisión de lo que se hará —el texto exacto de un mensaje, la línea
/// que se agregará— y recién ahí se confirma. El servidor sólo describe las
/// opciones; quién las ejecuta y cómo es del cliente autorizado.
export interface AgentCardOption {
  id: string;
  label: string;
  description?: string;
}

export interface AgentActionCard {
  kind: string;
  title: string;
  destination: AgentCardDestination;
  eyebrow?: string;
  subtitle?: string;
  description?: string;
  chips: readonly string[];
  entityRef?: AgentEntityRef;
  approvalRef?: AgentApprovalRef;
  listRef?: AgentListRef;
  supplyNeedDraft?: AgentSupplyNeedDraft;
  /// Opciones excluyentes. El cliente las muestra como controles y, al elegir
  /// una, abre la previsualización antes de cualquier efecto.
  options?: readonly AgentCardOption[];
  /// Qué família de acción representan las opciones, para que el cliente sepa
  /// qué previsualización abrir (`whatsapp_template`, por ejemplo).
  optionKind?: string;
}

export const agentApprovalStates = [
  "pending",
  "approved",
  "discarded",
  "expired",
] as const;

export type AgentApprovalState = (typeof agentApprovalStates)[number];

export interface AgentApprovalRef {
  id: string;
  action: "create_task" | "update_diagnosis" | "add_workshop_item";
  state: AgentApprovalState;
  expiresAt: string;
}

export interface AgentApprovalActionRequest {
  version: 1;
  operation: "approval_action";
  approvalId: string;
  approvalAction: "approve" | "discard";
  clientActionId: string;
}

export interface AgentApprovalActionResponse {
  version: 1;
  operation: "approval_action";
  approvalId: string;
  clientActionId: string;
  approvalState: Exclude<AgentApprovalState, "pending">;
  text: string;
  cards: readonly AgentActionCard[];
  status: "completed";
}

export interface AgentGatewayResponse {
  version: 1;
  threadId: string;
  runId: string;
  text: string;
  cards: readonly AgentActionCard[];
  status: "completed";
}

export type AgentToolResultStatus = "success" | "verifiedEmpty" | "partial" | "unavailable";

export interface AgentToolResultEnvelope {
  authorityTenantId: string;
  asOf: string;
  status: AgentToolResultStatus;
  items: readonly JsonObject[];
  resultCount: number;
  hasMore: boolean;
  /// Cuántas coincidencias hay en total, no cuántas cupieron en el tope.
  totalMatches: number;
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
