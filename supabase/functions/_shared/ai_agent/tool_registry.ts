import type {
  AgentAuthority,
  AgentToolCall,
  AgentToolDefinition,
  JsonValue,
  StrictJsonSchema,
} from "./contracts.ts";
import { validatePublicResearchArguments } from "./public_research.ts";

const operationalRead = "ai.read.operational";
const salesRead = "ai.read.sales";
const purchasesRead = "ai.read.purchases";
const accountingRead = "ai.read.accounting";
const publicResearchToolName = "research_public_web";
const prepareTaskToolName = "prepare_task";

export class ToolRegistryError extends Error {
  constructor(
    readonly status: 400 | 403 | 502,
    readonly code:
      | "unknown_tool"
      | "unauthorized_tool"
      | "invalid_tool_arguments"
      | "invalid_tool_schema"
      | "tool_not_activated",
    readonly publicMessage: string,
  ) {
    super(publicMessage);
    this.name = "ToolRegistryError";
  }
}

export class AgentToolRegistry {
  readonly #tools: ReadonlyMap<string, AgentToolDefinition>;

  constructor(
    definitions: readonly AgentToolDefinition[],
    options: { activatedTools?: readonly string[] } = {},
  ) {
    const activatedTools = new Set(options.activatedTools ?? []);
    const tools = new Map<string, AgentToolDefinition>();
    for (const definition of definitions) {
      if (!/^[a-z][a-z0-9_]{1,63}$/.test(definition.name)) {
        throw invalidSchema("Tool names must be stable snake_case identifiers");
      }
      if (tools.has(definition.name)) throw invalidSchema("Duplicate tool definition");
      validateStrictSchema(definition.parameters);
      if (definition.name === publicResearchToolName && !activatedTools.has(definition.name)) {
        continue;
      }
      tools.set(definition.name, freezeDefinition(definition));
    }
    this.#tools = tools;
  }

  advertisedFor(authority: AgentAuthority): readonly AgentToolDefinition[] {
    const capabilities = effectiveCapabilities(authority);
    return [...this.#tools.values()].filter((definition) =>
      definition.requiredPermissions.every((permission) => capabilities.has(permission))
    );
  }

  validateProviderCalls(
    calls: readonly AgentToolCall[],
    authority: AgentAuthority,
  ): void {
    if (calls.length > 8) {
      throw new ToolRegistryError(502, "invalid_tool_arguments", "AI tool fan-out is invalid");
    }
    const ids = new Set<string>();
    for (const call of calls) {
      if (!call.id || call.id.length > 256 || ids.has(call.id)) {
        throw new ToolRegistryError(502, "invalid_tool_arguments", "AI tool call is invalid");
      }
      ids.add(call.id);
      this.validateProviderCall(call, authority);
    }
  }

  validateProviderCall(call: AgentToolCall, authority: AgentAuthority): void {
    if (!call.id || call.id.length > 256) {
      throw new ToolRegistryError(502, "invalid_tool_arguments", "AI tool call is invalid");
    }
    this.#validateCall(call, authority, 502);
  }

  #validateCall(call: AgentToolCall, authority: AgentAuthority, status: 400 | 502): void {
    const definition = this.#requireAllowed(call.name, authority, status);
    if (!matchesSchema(call.arguments, definition.parameters)) {
      throw new ToolRegistryError(
        status,
        "invalid_tool_arguments",
        "AI tool arguments are invalid",
      );
    }
    if (call.name === publicResearchToolName) {
      validatePublicResearchProjection(call.arguments, status);
    }
    if (call.name === prepareTaskToolName) {
      validatePrepareTaskProjection(call.arguments, status);
    }
  }

  #requireAllowed(
    name: string,
    authority: AgentAuthority,
    status: 400 | 502,
  ): AgentToolDefinition {
    const definition = this.#tools.get(name);
    if (!definition) {
      throw new ToolRegistryError(status, "unknown_tool", "AI tool is not available");
    }
    const capabilities = effectiveCapabilities(authority);
    const allowed = definition.requiredPermissions.every((permission) =>
      capabilities.has(permission)
    );
    if (!allowed) {
      throw new ToolRegistryError(
        status === 400 ? 403 : 502,
        "unauthorized_tool",
        "AI tool is not available",
      );
    }
    return definition;
  }
}

const querySchema: StrictJsonSchema = {
  type: "object",
  properties: {
    query: {
      type: "string",
      minLength: 1,
      maxLength: 240,
      description: "Texto breve y específico para filtrar datos autorizados.",
    },
  },
  required: ["query"],
  additionalProperties: false,
};

const boundedSearchSchema: StrictJsonSchema = {
  type: "object",
  properties: {
    query: {
      type: "string",
      minLength: 1,
      maxLength: 240,
      description: "Texto breve y específico para filtrar datos autorizados.",
    },
    limit: {
      type: "integer",
      minimum: 1,
      maximum: 10,
      description: "Máximo seguro de resultados.",
    },
  },
  required: ["query", "limit"],
  additionalProperties: false,
};

const attentionItemsSchema: StrictJsonSchema = {
  type: "object",
  properties: {
    horizon: {
      type: "string",
      enum: ["today", "tomorrow"],
      description: "Día operacional chileno que se debe revisar.",
    },
  },
  required: ["horizon"],
  additionalProperties: false,
};

const businessSnapshotSchema: StrictJsonSchema = {
  type: "object",
  properties: {
    horizon: {
      type: "string",
      enum: ["today", "tomorrow", "next_7_days"],
      description: "Horizonte operacional cerrado para resumir taller, tareas e inventario.",
    },
  },
  required: ["horizon"],
  additionalProperties: false,
};

const inventoryRisksSchema: StrictJsonSchema = closedSearchSchema({
  risk: ["any", "low_stock", "out_of_stock"],
});

const recentExpensesSchema: StrictJsonSchema = {
  type: "object",
  properties: {
    query: optionalQueryProperty(),
    days: integerProperty(1, 365, "Ventana histórica en días."),
    postingStatus: enumProperty(["any", "draft", "posted", "void"], "Estado contable."),
    paymentStatus: enumProperty(
      ["any", "pending", "scheduled", "partial", "paid", "void"],
      "Estado de pago.",
    ),
    approvalStatus: enumProperty(
      ["any", "pending", "approved", "rejected"],
      "Estado de aprobación.",
    ),
    limit: integerProperty(1, 10, "Máximo seguro de resultados."),
  },
  required: [
    "query",
    "days",
    "postingStatus",
    "paymentStatus",
    "approvalStatus",
    "limit",
  ],
  additionalProperties: false,
};

const cashAndReceivablesSchema: StrictJsonSchema = {
  type: "object",
  properties: {
    horizon: enumProperty(
      ["today", "next_7_days", "next_30_days"],
      "Horizonte para cuentas por cobrar.",
    ),
    limit: integerProperty(1, 8, "Máximo de facturas por cobrar."),
  },
  required: ["horizon", "limit"],
  additionalProperties: false,
};

const conversationsSchema: StrictJsonSchema = {
  type: "object",
  properties: {
    query: optionalQueryProperty(),
    channel: enumProperty(
      ["any", "internal", "website_portal", "whatsapp", "instagram", "facebook_messenger"],
      "Canal cerrado de conversación.",
    ),
    status: enumProperty(
      ["any", "pending", "active", "resolved", "rejected"],
      "Estado de la conversación.",
    ),
    contextType: enumProperty(
      [
        "any",
        "job",
        "invoice",
        "order",
        "purchase_invoice",
        "supplier",
        "customer",
        "product",
        "bike",
      ],
      "Tipo de registro relacionado.",
    ),
    unreadOnly: { type: "boolean", description: "Limita a conversaciones no leídas." },
    needsReplyOnly: {
      type: "boolean",
      description: "Limita a conversaciones que requieren respuesta.",
    },
    days: integerProperty(1, 365, "Ventana histórica en días."),
    limit: integerProperty(1, 10, "Máximo seguro de resultados."),
  },
  required: [
    "query",
    "channel",
    "status",
    "contextType",
    "unreadOnly",
    "needsReplyOnly",
    "days",
    "limit",
  ],
  additionalProperties: false,
};

const workshopQuerySchema: StrictJsonSchema = filteredSearchSchema({
  status: ["any", "open", "completed", "delivered", "cancelled"],
  includeAssignee: false,
});

const taskQuerySchema: StrictJsonSchema = filteredSearchSchema({
  status: ["any", "pending", "in_progress", "completed", "cancelled"],
  includeAssignee: true,
});

const publicResearchProjectionSchema: StrictJsonSchema = {
  type: "object",
  properties: {},
  required: [],
  additionalProperties: false,
};

const prepareTaskSchema: StrictJsonSchema = {
  type: "object",
  properties: {
    title: {
      type: "string",
      minLength: 1,
      maxLength: 160,
      description: "Título concreto de la tarea que el operador podrá confirmar.",
    },
    description: {
      type: ["string", "null"],
      minLength: 1,
      maxLength: 2000,
      description: "Detalle opcional de la tarea; null cuando no hace falta.",
    },
    priority: {
      type: "string",
      enum: ["low", "normal", "high", "urgent"],
      description: "Prioridad operacional cerrada.",
    },
    dueAt: {
      type: ["string", "null"],
      minLength: 20,
      maxLength: 40,
      description: "Fecha y hora ISO 8601 con zona, o null si no hay vencimiento.",
    },
    assigneeMode: {
      type: "string",
      enum: ["me", "unassigned", "name"],
      description: "Asignación a quien opera, sin asignar o por nombre autorizado.",
    },
    assigneeName: {
      type: ["string", "null"],
      minLength: 1,
      maxLength: 160,
      description: "Nombre exacto sólo cuando assigneeMode es name; en otro caso null.",
    },
  },
  required: [
    "title",
    "description",
    "priority",
    "dueAt",
    "assigneeMode",
    "assigneeName",
  ],
  additionalProperties: false,
};

export function createDefaultAgentToolRegistry(options: { publicResearch?: boolean } = {}) {
  return new AgentToolRegistry([
    readTool(
      "search_inventory",
      "Busca productos, precio y stock en el inventario autorizado del taller.",
      querySchema,
      operationalRead,
    ),
    readTool(
      "find_inventory_risks",
      "Detecta productos con stock bajo o agotado usando filtros autorizados de inventario.",
      inventoryRisksSchema,
      operationalRead,
    ),
    readTool(
      "list_attention_items",
      "Lista entregas y tareas que requieren atención hoy o mañana.",
      attentionItemsSchema,
      operationalRead,
    ),
    readTool(
      "get_business_snapshot",
      "Resume métricas operacionales de taller, tareas e inventario para hoy, mañana o los próximos siete días.",
      businessSnapshotSchema,
      operationalRead,
    ),
    readTool(
      "search_workshop_jobs",
      "Consulta trabajos autorizados combinando texto opcional, horizonte, estado y prioridad.",
      workshopQuerySchema,
      operationalRead,
    ),
    readTool(
      "search_tasks",
      "Consulta tareas autorizadas combinando texto opcional, horizonte, estado, prioridad y asignación.",
      taskQuerySchema,
      operationalRead,
    ),
    readTool(
      "search_customers",
      "Busca clientes autorizados por nombre o identificador.",
      boundedSearchSchema,
      operationalRead,
    ),
    readTool(
      "search_suppliers",
      "Busca proveedores autorizados por nombre o identificador.",
      boundedSearchSchema,
      purchasesRead,
    ),
    readTool(
      "search_sales_invoices",
      "Busca facturas de venta autorizadas por folio, cliente o estado.",
      boundedSearchSchema,
      salesRead,
    ),
    readTool(
      "search_purchase_invoices",
      "Busca facturas de compra autorizadas por folio, proveedor o estado.",
      boundedSearchSchema,
      purchasesRead,
    ),
    readTool(
      "list_recent_expenses",
      "Consulta gastos recientes por estado contable, de pago y aprobación, sin exponer proveedores ni contactos.",
      recentExpensesSchema,
      accountingRead,
    ),
    readTool(
      "analyze_cash_and_receivables",
      "Analiza el saldo contable de cuentas configuradas y facturas por cobrar en un horizonte cerrado; no representa saldo bancario, conciliado ni disponible.",
      cashAndReceivablesSchema,
      accountingRead,
    ),
    readTool(
      "search_conversations",
      "Busca conversaciones autorizadas por canal, estado y contexto sin leer contenido, nombres ni contactos.",
      conversationsSchema,
      operationalRead,
    ),
    readTool(
      prepareTaskToolName,
      "Prepara una tarea exacta y durable para revisión. Nunca la crea: la escritura sólo ocurre después de una confirmación explícita en la tarjeta.",
      prepareTaskSchema,
      operationalRead,
    ),
    readTool(
      publicResearchToolName,
      "Investiga el mensaje actual del operador en la web pública, incluidos sitios o foros nombrados, mediante un adaptador aislado y fuentes HTTPS citadas. No acepta texto ni destinos: el servidor deriva la tarea sólo del mensaje actual.",
      publicResearchProjectionSchema,
      operationalRead,
    ),
  ], {
    activatedTools: options.publicResearch ? [publicResearchToolName] : [],
  });
}

function optionalQueryProperty(): StrictJsonSchema {
  return {
    type: ["string", "null"],
    minLength: 1,
    maxLength: 240,
    description: "Texto opcional; null permite usar sólo filtros estructurados.",
  };
}

function enumProperty(values: readonly string[], description: string): StrictJsonSchema {
  return { type: "string", enum: values, description };
}

function integerProperty(minimum: number, maximum: number, description: string): StrictJsonSchema {
  return { type: "integer", minimum, maximum, description };
}

function closedSearchSchema(extra: Readonly<Record<string, readonly string[]>>): StrictJsonSchema {
  const properties: Record<string, StrictJsonSchema> = { query: optionalQueryProperty() };
  for (const [name, values] of Object.entries(extra)) {
    properties[name] = enumProperty(values, `Filtro cerrado ${name}.`);
  }
  properties.limit = integerProperty(1, 10, "Máximo seguro de resultados.");
  return {
    type: "object",
    properties,
    required: Object.keys(properties),
    additionalProperties: false,
  };
}

function filteredSearchSchema(options: {
  status: readonly string[];
  includeAssignee: boolean;
}): StrictJsonSchema {
  const properties: Record<string, StrictJsonSchema> = {
    query: {
      type: ["string", "null"],
      minLength: 1,
      maxLength: 240,
      description: "Texto opcional; null permite filtrar sólo por campos estructurados.",
    },
    horizon: {
      type: "string",
      enum: ["any", "today", "tomorrow", "week", "overdue"],
      description: "Horizonte temporal cerrado.",
    },
    status: {
      type: "string",
      enum: options.status,
      description: "Estado cerrado del registro.",
    },
    priority: {
      type: "string",
      enum: ["any", "urgent", "high", "normal", "low"],
      description: "Prioridad cerrada del registro.",
    },
    limit: {
      type: "integer",
      minimum: 1,
      maximum: 10,
      description: "Máximo seguro de resultados.",
    },
  };
  if (options.includeAssignee) {
    properties.assignee = {
      type: "string",
      enum: ["any", "me", "unassigned"],
      description: "Asignación cerrada de tareas.",
    };
  }
  return {
    type: "object",
    properties,
    required: Object.keys(properties),
    additionalProperties: false,
  };
}

function validatePublicResearchProjection(
  argumentsValue: Readonly<Record<string, JsonValue>>,
  status: 400 | 502,
): void {
  try {
    validatePublicResearchArguments(argumentsValue);
  } catch (_) {
    throw invalidPublicResearchArguments(status);
  }
}

function validatePrepareTaskProjection(
  argumentsValue: Readonly<Record<string, JsonValue>>,
  status: 400 | 502,
): void {
  const mode = argumentsValue.assigneeMode;
  const name = argumentsValue.assigneeName;
  const dueAt = argumentsValue.dueAt;
  if (
    (mode === "name") !== (typeof name === "string") ||
    (typeof dueAt === "string" && !isIsoInstant(dueAt))
  ) {
    throw new ToolRegistryError(
      status,
      "invalid_tool_arguments",
      "AI tool arguments are invalid",
    );
  }
}

function isIsoInstant(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/.test(value) &&
    Number.isFinite(Date.parse(value));
}

function invalidPublicResearchArguments(status: 400 | 502): ToolRegistryError {
  return new ToolRegistryError(
    status,
    "invalid_tool_arguments",
    "AI tool arguments are invalid",
  );
}

export function validateStrictSchema(schema: StrictJsonSchema): void {
  const types = Array.isArray(schema.type) ? schema.type : [schema.type];
  if (types.length === 0 || types.some((type) => !validSchemaTypes.has(type))) {
    throw invalidSchema("Tool schema contains an unsupported type");
  }
  if (types.includes("object")) {
    if (!schema.properties || schema.additionalProperties !== false) {
      throw invalidSchema("Object tool schemas must be closed");
    }
    const propertyNames = Object.keys(schema.properties).sort();
    const required = [...(schema.required ?? [])].sort();
    if (JSON.stringify(propertyNames) !== JSON.stringify(required)) {
      throw invalidSchema("Every object property must be required");
    }
    for (const property of Object.values(schema.properties)) validateStrictSchema(property);
  }
  if (types.includes("array")) {
    if (!schema.items) throw invalidSchema("Array tool schemas require an item schema");
    validateStrictSchema(schema.items);
  }
}

export function matchesSchema(value: JsonValue, schema: StrictJsonSchema): boolean {
  const types = Array.isArray(schema.type) ? schema.type : [schema.type];
  if (!types.some((type) => matchesType(value, type))) return false;
  if (schema.enum && !schema.enum.some((candidate) => candidate === value)) return false;

  if (typeof value === "string") {
    const byteLength = new TextEncoder().encode(value).byteLength;
    if (schema.minLength !== undefined && byteLength < schema.minLength) return false;
    if (schema.maxLength !== undefined && byteLength > schema.maxLength) return false;
  }
  if (typeof value === "number") {
    if (schema.minimum !== undefined && value < schema.minimum) return false;
    if (schema.maximum !== undefined && value > schema.maximum) return false;
  }
  if (Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) return false;
    if (schema.maxItems !== undefined && value.length > schema.maxItems) return false;
    if (schema.items && !value.every((item) => matchesSchema(item, schema.items!))) return false;
  }
  if (value && typeof value === "object" && !Array.isArray(value)) {
    const properties = schema.properties;
    if (!properties) return false;
    const keys = Object.keys(value);
    if ((schema.required ?? []).some((key) => !keys.includes(key))) return false;
    if (schema.additionalProperties === false && keys.some((key) => !(key in properties))) {
      return false;
    }
    for (const [key, propertyValue] of Object.entries(value)) {
      const propertySchema = properties[key];
      if (propertySchema && !matchesSchema(propertyValue, propertySchema)) return false;
    }
  }
  return true;
}

const validSchemaTypes = new Set([
  "object",
  "array",
  "string",
  "number",
  "integer",
  "boolean",
  "null",
]);

function matchesType(value: JsonValue, type: string): boolean {
  switch (type) {
    case "null":
      return value === null;
    case "array":
      return Array.isArray(value);
    case "object":
      return value !== null && typeof value === "object" && !Array.isArray(value);
    case "string":
      return typeof value === "string";
    case "number":
      return typeof value === "number" && Number.isFinite(value);
    case "integer":
      return typeof value === "number" && Number.isInteger(value);
    case "boolean":
      return typeof value === "boolean";
    default:
      return false;
  }
}

function readTool(
  name: string,
  description: string,
  parameters: StrictJsonSchema,
  requiredCapability: string,
): AgentToolDefinition {
  return {
    name,
    description,
    parameters,
    requiredPermissions: [requiredCapability],
  };
}

function effectiveCapabilities(authority: AgentAuthority): ReadonlySet<string> {
  return new Set(authority.capabilities);
}

function invalidSchema(message: string): ToolRegistryError {
  return new ToolRegistryError(502, "invalid_tool_schema", message);
}

function freezeDefinition(definition: AgentToolDefinition): AgentToolDefinition {
  return Object.freeze({
    ...definition,
    requiredPermissions: Object.freeze([...definition.requiredPermissions]),
  });
}
