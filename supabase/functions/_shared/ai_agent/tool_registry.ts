import type {
  AgentAuthority,
  AgentToolCall,
  AgentToolDefinition,
  JsonValue,
  StrictJsonSchema,
} from "./contracts.ts";

const operationalRead = "ai.read.operational";
const salesRead = "ai.read.sales";
const purchasesRead = "ai.read.purchases";
const publicResearchToolName = "research_public_web";

// Arbitrary text cannot be proven free of tenant data or PII by heuristics.
// Keep public research unexecutable until an isolated worker can resolve
// server-owned public identifiers without receiving ERP records.
const toolsAwaitingIsolatedExecution = new Set([publicResearchToolName]);

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

  constructor(definitions: readonly AgentToolDefinition[]) {
    const tools = new Map<string, AgentToolDefinition>();
    for (const definition of definitions) {
      if (!/^[a-z][a-z0-9_]{1,63}$/.test(definition.name)) {
        throw invalidSchema("Tool names must be stable snake_case identifiers");
      }
      if (tools.has(definition.name)) throw invalidSchema("Duplicate tool definition");
      validateStrictSchema(definition.parameters);
      tools.set(definition.name, freezeDefinition(definition));
    }
    this.#tools = tools;
  }

  advertisedFor(authority: AgentAuthority): readonly AgentToolDefinition[] {
    const capabilities = effectiveCapabilities(authority);
    return [...this.#tools.values()].filter((definition) =>
      !toolsAwaitingIsolatedExecution.has(definition.name) &&
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
      this.#validateCall(call, authority, 502);
    }
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
    if (toolsAwaitingIsolatedExecution.has(call.name)) {
      throw new ToolRegistryError(
        status,
        "tool_not_activated",
        "AI tool is not available",
      );
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
      type: ["integer", "null"],
      minimum: 1,
      maximum: 10,
      description: "Máximo de resultados; null usa el límite seguro del servidor.",
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

const publicResearchProjectionSchema: StrictJsonSchema = {
  type: "object",
  properties: {
    intent: {
      type: "string",
      enum: [
        "product_specification",
        "component_compatibility",
        "maintenance_procedure",
        "public_regulation",
      ],
      description: "Tipo público de investigación; nunca una instrucción libre.",
    },
    publicIdentifiers: {
      type: "array",
      minItems: 1,
      maxItems: 3,
      items: {
        type: "string",
        minLength: 2,
        maxLength: 64,
        description: "Identificador público normalizado de marca, modelo, componente o norma.",
      },
      description: "Referencias públicas; el servidor construye la consulta externa.",
    },
    locale: {
      type: "string",
      enum: ["es-CL", "en-US"],
      description: "Idioma público permitido para la investigación.",
    },
  },
  required: ["intent", "publicIdentifiers", "locale"],
  additionalProperties: false,
};

export function createDefaultAgentToolRegistry(): AgentToolRegistry {
  return new AgentToolRegistry([
    readTool(
      "search_inventory",
      "Busca productos, precio y stock en el inventario autorizado del taller.",
      querySchema,
      operationalRead,
    ),
    readTool(
      "list_attention_items",
      "Lista entregas y tareas que requieren atención hoy o mañana.",
      attentionItemsSchema,
      operationalRead,
    ),
    readTool(
      "search_workshop_jobs",
      "Busca trabajos autorizados por folio, cliente, bicicleta o estado.",
      boundedSearchSchema,
      operationalRead,
    ),
    readTool(
      "search_tasks",
      "Busca tareas autorizadas por texto, responsable o estado.",
      boundedSearchSchema,
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
      publicResearchToolName,
      "Propone investigación pública mediante identificadores normalizados; requiere un worker aislado.",
      publicResearchProjectionSchema,
      operationalRead,
    ),
  ]);
}

function validatePublicResearchProjection(
  argumentsValue: Readonly<Record<string, JsonValue>>,
  status: 400 | 502,
): void {
  const identifiers = argumentsValue.publicIdentifiers;
  if (!Array.isArray(identifiers)) {
    throw invalidPublicResearchArguments(status);
  }
  for (const identifier of identifiers) {
    if (typeof identifier !== "string" || !isSafePublicIdentifier(identifier)) {
      throw invalidPublicResearchArguments(status);
    }
  }
}

function isSafePublicIdentifier(value: string): boolean {
  if (!/^[A-Za-z0-9][A-Za-z0-9._+\/-]*$/.test(value)) return false;

  const normalized = value.toLowerCase();
  const sensitivePatterns = [
    /(?:^|[-_.])(?:api[-_.]?key|bearer|password|secret|token)(?:$|[-_.])/,
    /(?:^|[-_.])(?:address|cliente|correo|customer|direccion|email|factura|folio|invoice|pedido|phone|rut|telefono|whatsapp)(?:$|[-_.])/,
    /\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b/,
    /(?:^|[-_.])(?:fv|oc|ot|pg)[-_.]?[0-9]{3,}(?:$|[-_.])/,
    /(?:^|[-_.])[0-9]{1,2}[-_.]?[0-9]{3}[-_.]?[0-9]{3}[-_.]?[0-9k](?:$|[-_.])/,
    /[0-9]{7,}/,
  ];
  return !sensitivePatterns.some((pattern) => pattern.test(normalized));
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
    if (schema.minLength !== undefined && value.length < schema.minLength) return false;
    if (schema.maxLength !== undefined && value.length > schema.maxLength) return false;
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

const operationalRoles = new Set([
  "owner",
  "admin",
  "manager",
  "cashier",
  "mechanic",
  "accountant",
]);
const salesRoles = new Set(["owner", "admin", "manager", "cashier", "accountant"]);
const purchasesRoles = new Set(["owner", "admin", "manager", "accountant"]);

function effectiveCapabilities(authority: AgentAuthority): ReadonlySet<string> {
  const capabilities = new Set(
    Object.entries(authority.permissions)
      .filter((entry) => entry[1] === true)
      .map((entry) => entry[0]),
  );
  if (operationalRoles.has(authority.role)) capabilities.add(operationalRead);
  if (
    salesRoles.has(authority.role) || authority.permissions.create_invoices === true ||
    authority.permissions.access_accounting === true
  ) {
    capabilities.add(salesRead);
  }
  if (
    purchasesRoles.has(authority.role) || authority.permissions.access_accounting === true
  ) {
    capabilities.add(purchasesRead);
  }
  return capabilities;
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
