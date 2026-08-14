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
const workshopWrite = "ai.write.workshop";
const publicResearchToolName = "research_public_web";
const prepareTaskToolName = "prepare_task";
const prepareDiagnosisUpdateToolName = "prepare_diagnosis_update";
const prepareWorkshopItemToolName = "prepare_workshop_item";
const inventorySchemaToolName = "inspect_inventory_schema";
const capabilityGapToolName = "report_capability_gap";

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
    if (call.name === prepareDiagnosisUpdateToolName) {
      validatePrepareDiagnosisUpdateProjection(call.arguments, status);
    }
    if (call.name === prepareWorkshopItemToolName) {
      validatePrepareWorkshopItemProjection(call.arguments, status);
    }
    if (call.name === "get_workshop_job_context") {
      validateWorkshopJobContextProjection(call.arguments, status);
    }
    if (call.name === "analyze_sales_period") {
      validateSalesPeriodProjection(call.arguments, status);
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

const inventorySearchSchema: StrictJsonSchema = {
  type: "object",
  properties: {
    query: {
      type: ["string", "null"],
      minLength: 1,
      maxLength: 240,
      description:
        "Identidad o contexto textual opcional del producto: nombre, marca, modelo, SKU o código. Usa null cuando categoría y predicados técnicos expresen completamente la búsqueda.",
    },
    category: {
      type: ["string", "null"],
      minLength: 1,
      maxLength: 160,
      description:
        'Categoría canónica del catálogo, por ejemplo "Cámaras". El backend la resuelve contra product_categories y expande sólo su category_tech_mappings. Usa null para una identidad concreta o una consulta acotada sobre todo el inventario, como un top-N o un resumen general.',
    },
    availability: enumProperty(
      ["any", "in_stock", "low_stock", "out_of_stock"],
      "Filtro de disponibilidad pedido: in_stock incluye stock bajo; any sólo cuando el operador no condicionó disponibilidad.",
    ),
    presentation: enumProperty(
      ["answer", "open_list"],
      "Usa open_list sólo cuando abrir el listado filtrado completa una petición explícita de buscar, mostrar, listar o abrir productos. Usa answer para preguntas, conteos, comparaciones o resúmenes.",
    ),
    sort: {
      type: "object",
      description:
        "Orden server-owned de la selección. relevance conserva el ranking de identidad; los demás campos permiten ordenar de forma exacta sin pedir al modelo que reordene texto.",
      properties: {
        field: {
          type: "string",
          enum: ["relevance", "name", "stock", "minimum_stock", "price"],
          description: "Campo cerrado por el cual ordenar los productos filtrados.",
        },
        direction: {
          type: "string",
          enum: ["asc", "desc"],
          description:
            "Dirección exacta. relevance sólo admite desc; conserva asc/desc literalmente para cantidades, precios y nombre.",
        },
      },
      required: ["field", "direction"],
      additionalProperties: false,
    },
    limit: {
      type: "integer",
      minimum: 1,
      maximum: 10,
      description:
        "Cantidad máxima de filas. Usa 10 salvo que el operador pida explícitamente una cantidad menor.",
    },
    selectionMode: enumProperty(
      ["all_matches", "top_n"],
      "Usa top_n sólo cuando el operador pide explícitamente los N mayores/menores o una cantidad cerrada; all_matches mantiene hasMore si el límite trunca coincidencias.",
    ),
    technicalPredicates: {
      type: "array",
      minItems: 0,
      maxItems: 8,
      description:
        "Predicados técnicos explícitos obtenidos de inspect_inventory_schema. No inventes claves, operadores ni valores. Usa [] cuando no exista una restricción técnica.",
      items: {
        type: "object",
        properties: {
          field: {
            type: "string",
            minLength: 2,
            maxLength: 64,
            description: "Clave snake_case exacta de spec_definitions.key.",
          },
          operator: {
            type: "string",
            enum: ["eq", "neq", "lt", "lte", "gt", "gte", "between", "in", "contains"],
            description: "Operador anunciado por inspect_inventory_schema para el campo exacto.",
          },
          values: {
            type: "array",
            minItems: 1,
            maxItems: 10,
            items: { type: ["string", "number", "boolean"] },
            description:
              "Uno o más valores tipados. between usa exactamente dos; los operadores escalares usan uno.",
          },
        },
        required: ["field", "operator", "values"],
        additionalProperties: false,
      },
    },
    operationalPredicates: {
      type: "array",
      minItems: 0,
      maxItems: 6,
      description:
        "Comparaciones exactas sobre campos operativos autorizados del inventario. No sustituyas un umbral numérico por availability: stock es la existencia disponible efectiva, minimum_stock es el mínimo configurado y price es el precio de venta. Usa [] cuando no exista una restricción operativa.",
      items: {
        type: "object",
        properties: {
          field: {
            type: "string",
            enum: ["stock", "minimum_stock", "price"],
            description: "Campo operativo exacto anunciado por inspect_inventory_schema.",
          },
          operator: {
            type: "string",
            enum: ["eq", "neq", "lt", "lte", "gt", "gte", "between", "in"],
            description:
              "Comparador numérico exacto; conserva estrictamente mayor/menor versus mayor/menor o igual.",
          },
          values: {
            type: "array",
            minItems: 1,
            maxItems: 10,
            items: { type: "number" },
            description:
              "Umbral numérico: between usa exactamente dos valores, in admite varios y el resto exactamente uno.",
          },
        },
        required: ["field", "operator", "values"],
        additionalProperties: false,
      },
    },
  },
  required: [
    "query",
    "category",
    "availability",
    "presentation",
    "sort",
    "limit",
    "selectionMode",
    "technicalPredicates",
    "operationalPredicates",
  ],
  additionalProperties: false,
};

const inventorySchemaInspectionSchema: StrictJsonSchema = {
  type: "object",
  properties: {
    query: {
      type: "string",
      minLength: 1,
      maxLength: 240,
      description:
        "Petición técnica breve del operador. Se usa sólo para descubrir categorías y campos autorizados; no ejecuta la búsqueda.",
    },
    category: {
      type: ["string", "null"],
      minLength: 1,
      maxLength: 160,
      description:
        "Categoría que crees pertinente, o null para que el servidor proponga candidatos desde el árbol real.",
    },
  },
  required: ["query", "category"],
  additionalProperties: false,
};

const capabilityGapSchema: StrictJsonSchema = {
  type: "object",
  properties: {
    domain: {
      type: "string",
      enum: [
        "inventory",
        "workshop",
        "sales",
        "purchases",
        "accounting",
        "customers",
        "suppliers",
        "tasks",
        "communications",
        "files",
        "public_web",
        "other",
      ],
      description: "Dominio principal que la petición necesita.",
    },
    operation: {
      type: "string",
      enum: [
        "read",
        "filter",
        "compare",
        "aggregate",
        "draft",
        "mutate",
        "navigate",
        "research",
        "other",
      ],
      description: "Tipo de operación que no se pudo completar con precisión.",
    },
    reason: {
      type: "string",
      enum: [
        "missing_tool",
        "unsupported_filter",
        "missing_structured_data",
        "permission_required",
        "ambiguous_request",
        "source_unavailable",
      ],
      description:
        "Motivo exacto. No uses source_unavailable para un argumento inválido ni missing_tool si una herramienta anunciada sí cubre la petición.",
    },
    alternative: {
      type: "string",
      enum: [
        "none",
        "broader_search",
        "exact_match",
        "ask_clarification",
        "public_research",
      ],
      description: "Alternativa segura que el operador puede intentar, si existe.",
    },
    field: {
      type: ["string", "null"],
      minLength: 2,
      maxLength: 64,
      description:
        "Clave exacta devuelta por inspect_inventory_schema cuando reason es missing_structured_data; null para cualquier otra causa.",
    },
  },
  required: ["domain", "operation", "reason", "alternative", "field"],
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

const salesPeriodSchema: StrictJsonSchema = {
  type: "object",
  properties: {
    basis: enumProperty(
      ["issued", "collected"],
      "issued agrupa facturas por fecha de emisión; collected agrupa pagos efectivos no eliminados por fecha de cobro.",
    ),
    rangeMode: enumProperty(
      ["relative", "absolute"],
      "relative deja que el servidor resuelva límites desde la fecha local del negocio; absolute usa las dos fechas explícitas.",
    ),
    relativePeriod: {
      type: ["string", "null"],
      enum: [
        "today",
        "yesterday",
        "this_week",
        "last_week",
        "last_7_days",
        "this_month",
        "last_month",
        "this_year",
        "last_year",
        null,
      ],
      description: "Período relativo server-owned, o null cuando rangeMode es absolute.",
    },
    startDate: {
      type: ["string", "null"],
      minLength: 10,
      maxLength: 10,
      description:
        "Primer día inclusivo YYYY-MM-DD sólo para rangeMode absolute; null para relative.",
    },
    endDate: {
      type: ["string", "null"],
      minLength: 10,
      maxLength: 10,
      description:
        "Último día inclusivo YYYY-MM-DD sólo para rangeMode absolute; null para relative.",
    },
    invoiceStatus: enumProperty(
      ["any", "open", "paid", "cancelled"],
      "Estado comercial opcional aplicado a las facturas; any conserva todos los documentos válidos para la base elegida.",
    ),
  },
  required: [
    "basis",
    "rangeMode",
    "relativePeriod",
    "startDate",
    "endDate",
    "invoiceStatus",
  ],
  additionalProperties: false,
};

const workshopJobContextSchema: StrictJsonSchema = {
  type: "object",
  properties: {
    jobRef: {
      type: "string",
      minLength: 36,
      maxLength: 36,
      description:
        "Referencia opaca jobRef devuelta por search_workshop_jobs; nunca un UUID, nombre o folio inventado.",
    },
  },
  required: ["jobRef"],
  additionalProperties: false,
};

const diagnosisSchemaInspectionSchema: StrictJsonSchema = {
  type: "object",
  properties: {
    section: enumProperty(
      [
        "any",
        "suspension",
        "drivetrain",
        "front_brake",
        "rear_brake",
        "front_wheel",
        "rear_wheel",
        "bottom_bracket",
        "cockpit",
      ],
      "Sección estructurada del diagnóstico que se desea inspeccionar.",
    ),
  },
  required: ["section"],
  additionalProperties: false,
};

const prepareDiagnosisUpdateSchema: StrictJsonSchema = {
  type: "object",
  properties: {
    jobRef: {
      type: "string",
      minLength: 36,
      maxLength: 36,
      description:
        "Referencia opaca jobRef del trabajo obtenida desde search_workshop_jobs/get_workshop_job_context.",
    },
    jobBikeId: {
      type: "string",
      minLength: 36,
      maxLength: 36,
      description:
        "UUID exacto de la bicicleta dentro del trabajo obtenido desde get_workshop_job_context.",
    },
    field: {
      type: "string",
      minLength: 3,
      maxLength: 80,
      description: "Ruta exacta section.field devuelta por inspect_diagnosis_schema.",
    },
    numberValue: {
      type: ["number", "null"],
      description: "Valor numérico exacto, o null cuando el campo inspeccionado es textual.",
    },
    textValue: {
      type: ["string", "null"],
      minLength: 1,
      maxLength: 1000,
      description:
        "Clave canónica o nota exacta, o null cuando el campo inspeccionado es numérico.",
    },
    unit: enumProperty(
      ["none", "display_fraction", "percent", "millimeter"],
      "Unidad exacta anunciada por inspect_diagnosis_schema. display_fraction representa lecturas de calibre 0..1 y el servidor las normaliza al almacenamiento porcentual 0..100.",
    ),
    expectedUpdatedAt: {
      type: ["string", "null"],
      minLength: 20,
      maxLength: 40,
      description:
        "Revisión exacta diagnosisUpdatedAt devuelta por get_workshop_job_context; null sólo si esa revisión era null.",
    },
  },
  required: [
    "jobRef",
    "jobBikeId",
    "field",
    "numberValue",
    "textValue",
    "unit",
    "expectedUpdatedAt",
  ],
  additionalProperties: false,
};

const prepareWorkshopItemSchema: StrictJsonSchema = {
  type: "object",
  properties: {
    jobRef: {
      type: "string",
      minLength: 36,
      maxLength: 36,
      description:
        "Referencia opaca jobRef del trabajo obtenida desde search_workshop_jobs/get_workshop_job_context.",
    },
    jobBikeId: {
      type: ["string", "null"],
      minLength: 36,
      maxLength: 36,
      description:
        "Bicicleta exacta del trabajo, o null sólo cuando la línea es general para todo el trabajo.",
    },
    catalogItemRef: {
      type: "string",
      minLength: 36,
      maxLength: 36,
      description:
        "Referencia opaca catalogItemRef devuelta por search_inventory. El servidor conserva el UUID, nombre, tipo y precio.",
    },
    quantity: {
      type: "number",
      minimum: 0.01,
      maximum: 999,
      description: "Cantidad u horas exactas que se propondrán.",
    },
    notes: {
      type: ["string", "null"],
      minLength: 1,
      maxLength: 500,
      description: "Detalle opcional de la línea; null si el catálogo basta.",
    },
    expectedJobUpdatedAt: {
      type: "string",
      minLength: 20,
      maxLength: 40,
      description:
        "Revisión exacta jobUpdatedAt devuelta por get_workshop_job_context para evitar sobrescribir cambios concurrentes.",
    },
  },
  required: [
    "jobRef",
    "jobBikeId",
    "catalogItemRef",
    "quantity",
    "notes",
    "expectedJobUpdatedAt",
  ],
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
      inventorySchemaToolName,
      "Descubre el árbol real de categorías, familias técnicas y campos operativos/técnicos filtrables, con tipos, unidades, operadores y cobertura de datos. No adivines claves desde la frase del operador: llama primero a esta herramienta y usa exactamente su contrato.",
      inventorySchemaInspectionSchema,
      operationalRead,
    ),
    readTool(
      "search_inventory",
      "Consulta productos, precio y stock en el inventario autorizado. Separa categoría, identidad, especificaciones y magnitudes operativas: category se valida contra el árbol real y sus descendientes; query queda sólo para identidad/contexto; restricciones de ficha van en technicalPredicates y comparaciones de stock, stock mínimo o precio van en operationalPredicates. availability expresa estados, nunca reemplaza un umbral numérico. La base aplica todos los predicados antes de ordenar y limitar; cada fila incluye métricas verificadas del conjunto completo filtrado para responder conteos, stock total, valor de inventario y mínimos/máximos/promedio de precio sin sumar una página truncada. Usa sort y selectionMode para top-N. Separa una respuesta informativa de una petición explícita de abrir el listado y nunca enumeres un conjunto distinto del devuelto por la herramienta.",
      inventorySearchSchema,
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
      "Consulta trabajos autorizados combinando texto opcional, horizonte, estado y prioridad. La identidad relacional incluye cliente, todas las bicicletas y la factura vinculada; úsala para resolver primero el trabajo exacto antes de cualquier acción.",
      workshopQuerySchema,
      operationalRead,
    ),
    readTool(
      "get_workshop_job_context",
      "Lee el contexto exacto de un trabajo ya resuelto: sus bicicletas internas, factura vinculada, revisión concurrente y si cada acción puede prepararse. No acepta nombres ni hace coincidencias aproximadas.",
      workshopJobContextSchema,
      operationalRead,
    ),
    readTool(
      "inspect_diagnosis_schema",
      "Descubre los campos escalares reales del diagnóstico de bicicleta, sus tipos, unidades y valores canónicos. Debes llamarla antes de preparar una actualización de diagnóstico y reutilizar exactamente field y unit.",
      diagnosisSchemaInspectionSchema,
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
      "analyze_sales_period",
      "Calcula sobre un intervalo inclusivo de fechas del negocio cuántas facturas se emitieron o recibieron cobros, el monto total y la factura de mayor monto. collected usa eventos reales de sales_payments y cuenta facturas distintas; no infiere cobro desde el estado de la factura.",
      salesPeriodSchema,
      salesRead,
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
      prepareDiagnosisUpdateToolName,
      "Prepara un cambio tipado sobre un campo real del diagnóstico de una bicicleta ya resuelta. Nunca modifica el trabajo durante el turno del modelo: congela valor anterior, valor nuevo y revisión; sólo la confirmación explícita ejecuta y verifica el cambio.",
      prepareDiagnosisUpdateSchema,
      workshopWrite,
    ),
    readTool(
      prepareWorkshopItemToolName,
      "Prepara agregar un producto o servicio de catálogo a un trabajo exacto y, cuando corresponde, a su factura vinculada. El servidor toma nombre, tipo y precio del catálogo, revalida bloqueos financieros y sólo escribe tras confirmación explícita.",
      prepareWorkshopItemSchema,
      workshopWrite,
    ),
    localTool(
      capabilityGapToolName,
      "Termina de forma honesta una petición que ninguna herramienta o dato autorizado puede resolver con precisión. Úsala sólo después de comparar la intención con las herramientas anunciadas o después de que una lectura demuestre la carencia; la respuesta final la redacta el servidor y nunca debe inventar ejecución ni disponibilidad.",
      capabilityGapSchema,
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

function validatePrepareDiagnosisUpdateProjection(
  argumentsValue: Readonly<Record<string, JsonValue>>,
  status: 400 | 502,
): void {
  const numberValue = argumentsValue.numberValue;
  const textValue = argumentsValue.textValue;
  const expectedUpdatedAt = argumentsValue.expectedUpdatedAt;
  if (
    (typeof numberValue === "number") === (typeof textValue === "string") ||
    !isUuid(argumentsValue.jobRef) ||
    !isUuid(argumentsValue.jobBikeId) ||
    (typeof expectedUpdatedAt === "string" && !isIsoInstant(expectedUpdatedAt))
  ) {
    throw new ToolRegistryError(
      status,
      "invalid_tool_arguments",
      "AI tool arguments are invalid",
    );
  }
}

function validatePrepareWorkshopItemProjection(
  argumentsValue: Readonly<Record<string, JsonValue>>,
  status: 400 | 502,
): void {
  if (
    !isUuid(argumentsValue.jobRef) ||
    !(argumentsValue.jobBikeId === null || isUuid(argumentsValue.jobBikeId)) ||
    !isUuid(argumentsValue.catalogItemRef) ||
    typeof argumentsValue.expectedJobUpdatedAt !== "string" ||
    !isIsoInstant(argumentsValue.expectedJobUpdatedAt)
  ) {
    throw new ToolRegistryError(
      status,
      "invalid_tool_arguments",
      "AI tool arguments are invalid",
    );
  }
}

function validateWorkshopJobContextProjection(
  argumentsValue: Readonly<Record<string, JsonValue>>,
  status: 400 | 502,
): void {
  if (!isUuid(argumentsValue.jobRef)) {
    throw new ToolRegistryError(
      status,
      "invalid_tool_arguments",
      "AI tool arguments are invalid",
    );
  }
}

function validateSalesPeriodProjection(
  argumentsValue: Readonly<Record<string, JsonValue>>,
  status: 400 | 502,
): void {
  const start = argumentsValue.startDate;
  const end = argumentsValue.endDate;
  const mode = argumentsValue.rangeMode;
  const relative = argumentsValue.relativePeriod;
  const relativePeriods = [
    "today",
    "yesterday",
    "this_week",
    "last_week",
    "last_7_days",
    "this_month",
    "last_month",
    "this_year",
    "last_year",
  ];
  if (
    !["relative", "absolute"].includes(String(mode)) ||
    (mode === "relative" &&
      (!relativePeriods.includes(String(relative)) || start !== null || end !== null)) ||
    (mode === "absolute" &&
      (relative !== null || typeof start !== "string" || typeof end !== "string" ||
        !isIsoDate(start) || !isIsoDate(end) || start > end ||
        (Date.parse(`${end}T00:00:00Z`) - Date.parse(`${start}T00:00:00Z`)) /
              86_400_000 > 366))
  ) {
    throw new ToolRegistryError(
      status,
      "invalid_tool_arguments",
      "AI tool arguments are invalid",
    );
  }
}

function isUuid(value: JsonValue | undefined): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

function isIsoInstant(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/.test(value) &&
    Number.isFinite(Date.parse(value));
}

function isIsoDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00Z`);
  return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
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

function localTool(
  name: string,
  description: string,
  parameters: StrictJsonSchema,
): AgentToolDefinition {
  return {
    name,
    description,
    parameters,
    requiredPermissions: [],
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
