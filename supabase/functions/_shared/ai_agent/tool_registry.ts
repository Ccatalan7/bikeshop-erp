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
const purchaseRankingToolName = "rank_purchase_candidates";
const purchaseScenarioToolName = "build_purchase_scenarios";
const prepareSupplyRequestToolName = "prepare_supply_request";
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
    if (call.name === purchaseRankingToolName) {
      validatePurchaseRankingProjection(call.arguments, status);
    }
    if (call.name === purchaseScenarioToolName) {
      validatePurchaseScenarioProjection(call.arguments, status);
    }
    if (call.name === prepareSupplyRequestToolName) {
      validatePrepareSupplyRequestProjection(call.arguments, status);
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
      ["answer", "open_list", "open_list_with_analysis"],
      "Usa open_list cuando abrir el listado filtrado completa por sí solo una petición explícita de buscar, mostrar, listar o abrir productos. Usa open_list_with_analysis cuando el operador además pide explicar, comparar, priorizar o recomendar sobre esa misma selección; el servidor confirma la apertura y conserva tu análisis grounded. Usa answer cuando no debe abrirse la lista, por ejemplo para conteos o resúmenes.",
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
        "Predicados sobre claves y operadores que anunció inspect_inventory_schema. No inventes claves ni operadores; los valores sí van como los dijo el operador. Usa [] cuando no haya restricción técnica.",
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
            description: "Operador anunciado para ese campo. En listas, eq/in comparan el vocabulario ya traducido; contains busca por fragmento.",
          },
          values: {
            type: "array",
            minItems: 1,
            maxItems: 10,
            items: { type: ["string", "number", "boolean"] },
            description:
              "Uno o más valores; between usa dos y los escalares uno. En campos de lista manda las palabras del operador —«caja inglesa», «sellado»— y el servidor las resuelve; un valor que no resuelve descarta sólo ese predicado, así que intentar siempre supera a no filtrar.",
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

const purchaseRankingSchema: StrictJsonSchema = {
  type: "object",
  properties: {
    catalogItemRef: {
      type: ["string", "null"],
      minLength: 36,
      maxLength: 36,
      description:
        "Referencia opaca exacta devuelta por search_inventory. Úsala cuando ya se resolvió un producto del catálogo; nunca copies ni inventes un UUID interno.",
    },
    query: {
      type: ["string", "null"],
      minLength: 1,
      maxLength: 240,
      description:
        "Identidad breve ya descompuesta del producto cuando todavía no existe una referencia exacta. Omite palabras de intención como necesito, comprar o buscar. Debe ser null cuando catalogItemRef está presente.",
    },
    profile: enumProperty(
      ["balanced", "profitability", "urgent_local"],
      "Perfil explícito del ranking: equilibrio general, mayor rentabilidad o rescate local urgente.",
    ),
    limit: integerProperty(1, 10, "Máximo seguro de alternativas históricas."),
  },
  required: ["catalogItemRef", "query", "profile", "limit"],
  additionalProperties: false,
};

const purchaseScenarioSchema: StrictJsonSchema = {
  type: "object",
  properties: {
    items: {
      type: "array",
      minItems: 2,
      maxItems: 8,
      description:
        "Productos exactos ya resueltos para la canasta, en el mismo orden de la petición. No agregues ni combines líneas que el operador no pidió.",
      items: {
        type: "object",
        properties: {
          catalogItemRef: {
            type: "string",
            minLength: 36,
            maxLength: 36,
            description:
              "Referencia opaca exacta publicada por search_inventory; nunca copies ni inventes un UUID interno.",
          },
          quantity: {
            type: "number",
            minimum: 0.001,
            maximum: 999999,
            description: "Cantidad positiva pedida para esta línea.",
          },
          externalOnly: {
            type: "boolean",
            description:
              "Usa true sólo si el operador descartó expresamente el stock interno para esta línea; en todo otro caso usa false.",
          },
        },
        required: ["catalogItemRef", "quantity", "externalOnly"],
        additionalProperties: false,
      },
    },
    profile: enumProperty(
      ["balanced", "profitability", "urgent_local"],
      "Objetivo comercial explícito aplicado a todas las líneas.",
    ),
    maxSuppliers: integerProperty(
      1,
      3,
      "Máximo de proveedores permitido en cada escenario externo.",
    ),
    limit: integerProperty(1, 3, "Máximo de escenarios materialmente distintos."),
  },
  required: ["items", "profile", "maxSuppliers", "limit"],
  additionalProperties: false,
};

const prepareSupplyRequestSchema: StrictJsonSchema = {
  type: "object",
  properties: {
    items: {
      type: "array",
      minItems: 1,
      maxItems: 8,
      description:
        "Una línea por producto solicitado, en el orden del operador. No combines categorías distintas en una sola línea ni inventes una línea que no fue pedida.",
      items: {
        type: "object",
        properties: {
          catalogItemRef: {
            type: ["string", "null"],
            minLength: 36,
            maxLength: 36,
            description:
              "Referencia opaca exacta de search_inventory, o null si hay varias alternativas, falta precisión técnica o el producto aún no existe. Nunca inventes un UUID.",
          },
          categoryRef: {
            type: ["string", "null"],
            minLength: 36,
            maxLength: 36,
            description:
              "Referencia opaca de la categoría devuelta por inspect_inventory_schema. Úsala cuando la línea no tenga producto exacto pero sí una categoría resuelta, para que la revisión conserve de qué familia se trata. Con catalogItemRef presente el servidor deriva la categoría de la ficha y esta debe ser null. Nunca inventes ni copies un UUID.",
          },
          commercialTarget: {
            // Obligatoria y anulable, como `categoryRef`. El validador del
            // registro exige que toda propiedad declarada esté en `required`
            // (`Every object property must be required`), así que «opcional»
            // no existe acá: lo que se declara, se emite, aunque sea null.
            type: ["object", "null"],
            description:
              "Objetivo comercial que el operador expresó para ESTA línea. Usa null cuando no fijó ninguno. Nunca inventes un techo de costo ni un piso de margen, no conviertas monedas y no repitas aquí el perfil general.",
            properties: {
              gama: {
                type: ["string", "null"],
                enum: ["economica", "media", "alta", null],
                description:
                  "Gama pedida explícitamente: economica, media o alta. null si el operador no la dijo.",
              },
              maxLandedUnitCostNet: {
                type: ["number", "null"],
                minimum: 0,
                maximum: 999999999,
                description:
                  "Techo de costo aterrizado neto por unidad, en la moneda del taller. La moneda es del servidor: no la escribas ni la conviertas. null si no hay techo.",
              },
              minGrossMarginRatio: {
                type: ["number", "null"],
                minimum: 0,
                maximum: 1,
                description:
                  "Piso de margen bruto como fracción entre 0 y 1: 0.35 es 35 por ciento. null si el operador no fijó un piso.",
              },
            },
            required: ["gama", "maxLandedUnitCostNet", "minGrossMarginRatio"],
            additionalProperties: false,
          },
          description: {
            type: "string",
            minLength: 1,
            maxLength: 2000,
            description:
              "Descripción breve que conserva literalmente medidas, marca, gama, preferencias y relaciones expresadas. No agregues 'para' una rueda, bicicleta o sistema si el operador sólo dio una medida ambigua; elimina únicamente palabras de conversación.",
          },
          quantity: {
            type: "number",
            minimum: 0.001,
            maximum: 999999,
            description:
              "Cantidad explícita. Usa 1 sólo cuando el operador realmente no indicó otra cantidad.",
          },
          unit: {
            type: "string",
            minLength: 1,
            maxLength: 32,
            description:
              "Unidad operacional corta en español, por ejemplo unidad, par, juego o metro. Conserva una unidad explícita; no conviertas medidas técnicas en cantidad.",
          },
          technicalPredicates: {
            type: "array",
            minItems: 0,
            maxItems: 8,
            description:
              "Restricciones técnicas explícitas con las claves y operadores exactos descubiertos por inspect_inventory_schema. Usa [] si la ficha no permite estructurarlas; la descripción conserva el texto.",
            items: {
              type: "object",
              properties: {
                field: {
                  type: "string",
                  minLength: 2,
                  maxLength: 64,
                  description: "Clave exacta de spec_definitions.key.",
                },
                operator: {
                  type: "string",
                  enum: ["eq", "neq", "lt", "lte", "gt", "gte", "between", "in", "contains"],
                  description: "Operador autorizado para el campo.",
                },
                values: {
                  type: "array",
                  minItems: 1,
                  maxItems: 10,
                  items: { type: ["string", "number", "boolean"] },
                  description: "Valores tipados exactos de la restricción.",
                },
              },
              required: ["field", "operator", "values"],
              additionalProperties: false,
            },
          },
          preference: {
            type: ["string", "null"],
            minLength: 1,
            maxLength: 240,
            description:
              "Preferencia comercial breve no representada por la identidad técnica, como gama económica, marca preferida o margen; null si no existe.",
          },
          clarification: {
            type: ["string", "null"],
            minLength: 1,
            maxLength: 500,
            description:
              "Resumen concreto de la duda del operador cuando clarificationRequired=true, o advertencia de evidencia/datos del sistema cuando es false; null si no hace falta. Nunca presentes una carencia del catálogo como si al operador le faltara responder.",
          },
          clarificationRequired: {
            type: "boolean",
            description:
              "true sólo cuando falta una decisión o dato material que el operador no entregó. Debe ser false si la petición es inequívoca y la única carencia pertenece a las fichas o evidencia del ERP.",
          },
          clarificationPrompts: {
            type: "array",
            minItems: 0,
            maxItems: 3,
            description:
              "Preguntas tipadas y category-agnostic que el operador puede responder ahora. Prefiere sólo la próxima pregunta decisiva. Debe ser [] salvo cuando clarificationRequired=true.",
            items: {
              type: "object",
              properties: {
                id: {
                  type: "string",
                  minLength: 2,
                  maxLength: 32,
                  description:
                    "Identificador semántico estable snake_case dentro de la línea; no contiene nombres de tabla ni UUID.",
                },
                question: {
                  type: "string",
                  minLength: 1,
                  maxLength: 320,
                  description:
                    "Una sola pregunta clara sobre el próximo dato material. No combines varias decisiones en una pregunta.",
                },
                inputKind: {
                  type: "string",
                  enum: ["single_choice", "text", "number"],
                  description:
                    "single_choice para lecturas cerradas, number para una magnitud y text para una respuesta libre breve.",
                },
                options: {
                  type: "array",
                  minItems: 0,
                  maxItems: 5,
                  description:
                    "Entre 2 y 5 alternativas sólo para single_choice; [] para text y number.",
                  items: {
                    type: "object",
                    properties: {
                      value: {
                        type: "string",
                        minLength: 1,
                        maxLength: 64,
                      },
                      label: {
                        type: "string",
                        minLength: 1,
                        maxLength: 160,
                      },
                    },
                    required: ["value", "label"],
                    additionalProperties: false,
                  },
                },
                unit: {
                  type: ["string", "null"],
                  minLength: 1,
                  maxLength: 32,
                  description: "Unidad visible sólo para number; null en los demás tipos.",
                },
                allowUnknown: {
                  type: "boolean",
                  description:
                    "true cuando el flujo puede avanzar con «No lo sé» y buscar otra forma de resolver; no implica inventar un valor.",
                },
              },
              required: [
                "id",
                "question",
                "inputKind",
                "options",
                "unit",
                "allowUnknown",
              ],
              additionalProperties: false,
            },
          },
        },
        required: [
          "catalogItemRef",
          "categoryRef",
          "commercialTarget",
          "description",
          "quantity",
          "unit",
          "technicalPredicates",
          "preference",
          "clarification",
          "clarificationRequired",
          "clarificationPrompts",
        ],
        additionalProperties: false,
      },
    },
    profile: enumProperty(
      ["balanced", "profitability", "urgent_local"],
      "Objetivo comercial que mejor refleja la petición completa.",
    ),
  },
  required: ["items", "profile"],
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

const customerContactSchema: StrictJsonSchema = {
  type: "object",
  properties: {
    query: {
      type: "string",
      minLength: 1,
      maxLength: 240,
      description: "Nombre del cliente a contactar.",
    },
    limit: {
      type: "integer",
      minimum: 1,
      maximum: 5,
      description: "Máximo de clientes candidatos.",
    },
  },
  required: ["query", "limit"],
  additionalProperties: false,
};

const boundedSearchSchema: StrictJsonSchema = {
  type: "object",
  properties: {
    query: {
      // Nullable a propósito: sin esto, «qué proveedores tengo» era
      // inexpresable —el listado completo no tiene término de búsqueda— y el
      // modelo respondía que no tenía herramienta, teniéndola.
      type: ["string", "null"],
      minLength: 1,
      maxLength: 240,
      description:
        "Texto breve y específico para filtrar. Usa null para pedir el listado " +
        "sin filtrar, ordenado por lo más reciente: «qué proveedores tengo», " +
        "«muéstrame mis clientes». Nunca declares que falta una herramienta " +
        "por no tener un término de búsqueda.",
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
const purchaseInvoiceSearchSchema: StrictJsonSchema = {
  type: "object",
  properties: {
    query: {
      type: ["string", "null"],
      minLength: 1,
      maxLength: 240,
      description:
        "Texto para filtrar por folio, proveedor o estado. null para no filtrar por texto.",
    },
    relativePeriod: enumProperty(
      [
        "any",
        "today",
        "yesterday",
        "this_week",
        "last_week",
        "last_7_days",
        "this_month",
        "last_month",
        "this_year",
        "last_year",
      ],
      "Período del negocio resuelto por el servidor. Úsalo para «qué compré " +
        "este mes», «cuánto le compré a mis proveedores la semana pasada» o " +
        "cualquier pregunta de compras acotada en el tiempo: cada fila trae " +
        "matchedCount, matchedTotal y matchedBalance del conjunto COMPLETO del " +
        "período, no de la página. Con eso respondes totales sin sumar a mano " +
        "y sin declarar que falta una herramienta. any no acota el tiempo.",
    ),
    limit: {
      type: "integer",
      minimum: 1,
      maximum: 10,
      description: "Máximo seguro de resultados.",
    },
  },
  required: ["query", "relativePeriod", "limit"],
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

const inventoryRisksSchema: StrictJsonSchema = {
  type: "object",
  properties: {
    query: optionalQueryProperty(),
    risk: enumProperty(
      ["any", "low_stock", "out_of_stock"],
      "Qué se considera en riesgo. `any` = todo lo que está POR DEBAJO de su " +
        "mínimo, incluido lo que está en cero: ésta es la respuesta a «qué me " +
        "falta», «bajo stock mínimo» o «qué tengo que reponer», porque un " +
        "producto en cero está más bajo su mínimo que uno que aún tiene " +
        "unidades. `low_stock` = todavía queda stock pero está en o bajo el " +
        "mínimo; sirve sólo cuando el operador excluye explícitamente lo " +
        "agotado. `out_of_stock` = exactamente cero.",
    ),
    limit: integerProperty(1, 10, "Máximo seguro de resultados."),
  },
  required: ["query", "risk", "limit"],
  additionalProperties: false,
};

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
      "Consulta productos, precio, stock y ficha técnica del inventario autorizado. Hay dos caminos y NO se mezclan. (1) Sin predicados, el que debes preferir: manda en query la frase del operador tal como la dijo y technicalPredicates en []; el servidor la traduce contra el vocabulario real de fichas y las medidas del catálogo, y basta una llamada sin inspección previa. (2) Con predicados: inspecciona antes el esquema en una ronda aparte y usa su categoría y campos exactos; mandarlos sin esa inspección hace que el servidor rechace la llamada. Cada fila trae technicalSpecs con la ficha resuelta del producto: úsala para responder qué medidas o qué características tiene, y nunca deduzcas una especificación del nombre ni la busques en la web. Trae además métricas verificadas del conjunto completo filtrado —conteo, stock total, valor, mínimo, máximo y promedio de precio— para responder totales sin sumar una página truncada. availability expresa estados, no reemplaza un umbral. Usa sort y selectionMode para top-N, y nunca enumeres un conjunto distinto del que devolvió la herramienta.",
      inventorySearchSchema,
      operationalRead,
    ),
    readTool(
      purchaseRankingToolName,
      "Compara proveedores históricos para un producto exacto o una identidad breve. El servidor calcula costo aterrizado, margen, frecuencia, recencia, estabilidad y calidad de evidencia con una fórmula versionada. La disponibilidad del proveedor siempre queda como no verificada; usa esta herramienta sólo después de revisar primero el stock interno cuando la intención es abastecer.",
      purchaseRankingSchema,
      purchasesRead,
    ),
    {
      name: purchaseScenarioToolName,
      description:
        "Construye escenarios acotados para una canasta de productos exactos. Consulta ATP, mantiene stock interno primero, limita proveedores, conserva faltantes y compara costo aterrizado histórico sin inventar ahorro de flete ni disponibilidad vigente. Úsala después de resolver cada producto con search_inventory.",
      parameters: purchaseScenarioSchema,
      requiredPermissions: [operationalRead, purchasesRead],
    },
    {
      name: prepareSupplyRequestToolName,
      description:
        "Estructura una petición real de abastecimiento en una a ocho líneas revisables. Úsala en el Asistente de compras después de descomponer la frase, inspeccionar fichas cuando haya especificaciones y consultar stock para cada identidad. Vincula catalogItemRef sólo ante una coincidencia exacta; conserva dudas como aclaraciones y termina siempre con esta herramienta cuando el operador quiere encontrar, abastecer o comprar productos. No crea necesidades, reservas, compras ni documentos: el usuario revisa y confirma el borrador en la interfaz.",
      parameters: prepareSupplyRequestSchema,
      requiredPermissions: [operationalRead, purchasesRead],
    },
    readTool(
      "find_inventory_risks",
      "Detecta productos en riesgo de quiebre. Para «qué me falta», «bajo stock mínimo» o «qué hay que reponer» usa risk=any: lo agotado también está bajo el mínimo y es lo más urgente, así que dejarlo fuera responde de menos. Al contar «bajo su mínimo» considera sólo los items cuyo minimumStock sea mayor que cero —un producto en cero SIN mínimo configurado está agotado, pero no está bajo un mínimo que nadie definió— y dilo por separado si el operador pregunta por agotados. Reserva low_stock para cuando pide explícitamente lo que todavía tiene unidades, y out_of_stock para lo que está en cero.",
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
      "Busca facturas de compra autorizadas por folio, proveedor o estado, y responde totales por período. Con relativePeriod cada fila trae matchedCount, matchedTotal y matchedBalance del conjunto completo del período —no de la página—, así que «qué le compré a mis proveedores este mes» o «cuánto gasté en compras la semana pasada» se contestan con esta misma herramienta, sin sumar a mano y sin declarar que falta una capacidad.",
      purchaseInvoiceSearchSchema,
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
      "Calcula sobre un intervalo inclusivo de fechas del negocio cuántas facturas se emitieron o recibieron cobros, el monto total, la factura de mayor monto Y el desglose por cliente del período: cuántos clientes distintos, quién encabeza con su monto y número de facturas, y el top 5 en topCustomers. Con eso responde también «quién me compró más», «mi mejor cliente del mes» o cualquier ranking por cliente: no hace falta ninguna otra herramienta ni declarar que falta una. collected usa eventos reales de sales_payments y cuenta facturas distintas; no infiere cobro desde el estado de la factura.",
      salesPeriodSchema,
      salesRead,
    ),
    readTool(
      "prepare_customer_contact",
      "Prepara el contacto por WhatsApp con un cliente. Resuelve si la ventana de 24 horas está abierta y ofrece las plantillas aprobadas con su texto exacto. No envía nada: el operador confirma en la tarjeta.",
      customerContactSchema,
      operationalRead,
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
      "Termina de forma honesta una petición que ninguna herramienta autorizada puede resolver. Sólo después de que una EJECUCIÓN real lo demuestre: inspeccionar un esquema no demuestra nada, y sin ejecutar no sabes si hay datos. Nunca la uses sobre un campo que la inspección devolvió y no intentaste buscar, ni para un ranking por cliente (lo trae analyze_sales_period), ni para contactar a un cliente (prepare_customer_contact). source_unavailable es sólo para una herramienta que falló al ejecutarse. La respuesta final la redacta el servidor.",
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

function validatePurchaseRankingProjection(
  argumentsValue: Readonly<Record<string, JsonValue>>,
  status: 400 | 502,
): void {
  const hasCatalogReference = typeof argumentsValue.catalogItemRef === "string";
  const hasQuery = typeof argumentsValue.query === "string" &&
    argumentsValue.query.trim().length > 0;
  if (hasCatalogReference === hasQuery) {
    throw new ToolRegistryError(
      status,
      "invalid_tool_arguments",
      "AI tool arguments are invalid",
    );
  }
}

function validatePurchaseScenarioProjection(
  argumentsValue: Readonly<Record<string, JsonValue>>,
  status: 400 | 502,
): void {
  if (!Array.isArray(argumentsValue.items)) {
    throw new ToolRegistryError(
      status,
      "invalid_tool_arguments",
      "AI tool arguments are invalid",
    );
  }
  const references = new Set<string>();
  for (const item of argumentsValue.items) {
    if (!item || typeof item !== "object" || Array.isArray(item)) continue;
    const reference = "catalogItemRef" in item ? item.catalogItemRef : null;
    if (typeof reference !== "string" || references.has(reference)) {
      throw new ToolRegistryError(
        status,
        "invalid_tool_arguments",
        "AI tool arguments are invalid",
      );
    }
    references.add(reference);
  }
}

function validatePrepareSupplyRequestProjection(
  argumentsValue: Readonly<Record<string, JsonValue>>,
  status: 400 | 502,
): void {
  if (!Array.isArray(argumentsValue.items)) {
    throw new ToolRegistryError(
      status,
      "invalid_tool_arguments",
      "AI tool arguments are invalid",
    );
  }
  for (const item of argumentsValue.items) {
    if (!item || typeof item !== "object" || Array.isArray(item)) continue;
    const clarification = "clarification" in item ? item.clarification : null;
    const required = "clarificationRequired" in item ? item.clarificationRequired : false;
    const prompts = "clarificationPrompts" in item ? item.clarificationPrompts : null;
    const catalogItemRef = "catalogItemRef" in item ? item.catalogItemRef : null;
    const categoryRef = "categoryRef" in item ? item.categoryRef : null;
    if (
      (required === true && typeof clarification !== "string") ||
      (required === true && typeof catalogItemRef === "string") ||
      // La ficha exacta manda sobre la categoría: si la línea trae producto,
      // el servidor deriva su categoría y una enviada por el modelo sólo
      // podría contradecirla.
      (typeof catalogItemRef === "string" && typeof categoryRef === "string") ||
      !validSupplyClarificationPrompts(prompts, required === true)
    ) {
      throw new ToolRegistryError(
        status,
        "invalid_tool_arguments",
        "AI tool arguments are invalid",
      );
    }
  }
}

function validSupplyClarificationPrompts(
  value: unknown,
  required: boolean,
): boolean {
  if (!Array.isArray(value) || value.length > 3) return false;
  if (!required) return value.length === 0;
  if (value.length < 1) return false;
  const ids = new Set<string>();
  for (const prompt of value) {
    if (!prompt || typeof prompt !== "object" || Array.isArray(prompt)) return false;
    const item = prompt as Record<string, unknown>;
    if (
      !hasExactKeys(item, [
        "id",
        "question",
        "inputKind",
        "options",
        "unit",
        "allowUnknown",
      ]) ||
      typeof item.id !== "string" || !/^[a-z][a-z0-9_]{1,31}$/.test(item.id) ||
      ids.has(item.id) || typeof item.question !== "string" ||
      !item.question.trim() || utf8Bytes(item.question.trim()) > 320 ||
      !["single_choice", "text", "number"].includes(String(item.inputKind)) ||
      !Array.isArray(item.options) || item.options.length > 5 ||
      typeof item.allowUnknown !== "boolean" ||
      !(item.unit === null ||
        (typeof item.unit === "string" && item.unit.trim() &&
          utf8Bytes(item.unit.trim()) <= 32))
    ) return false;
    ids.add(item.id);
    if (item.inputKind === "single_choice") {
      if (item.options.length < 2 || item.unit !== null) return false;
      const optionValues = new Set<string>();
      for (const option of item.options) {
        if (!option || typeof option !== "object" || Array.isArray(option)) return false;
        const candidate = option as Record<string, unknown>;
        if (
          !hasExactKeys(candidate, ["value", "label"]) ||
          typeof candidate.value !== "string" ||
          !/^[a-z0-9][a-z0-9_-]{0,63}$/.test(candidate.value) ||
          optionValues.has(candidate.value) || typeof candidate.label !== "string" ||
          !candidate.label.trim() || utf8Bytes(candidate.label.trim()) > 160
        ) return false;
        optionValues.add(candidate.value);
      }
    } else if (item.options.length !== 0) {
      return false;
    } else if (item.inputKind !== "number" && item.unit !== null) {
      return false;
    }
  }
  return true;
}

function hasExactKeys(
  value: Record<string, unknown>,
  keys: readonly string[],
): boolean {
  const actual = Object.keys(value);
  return actual.length === keys.length && keys.every((key) => key in value);
}

function utf8Bytes(value: string): number {
  return new TextEncoder().encode(value).byteLength;
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
