import {
  type AgentActionCard,
  type AgentApprovalRef,
  agentApprovalStates,
  agentCardDestinations,
  type AgentEntityKind,
  type AgentInventoryAvailabilityFilter,
  agentInventoryAvailabilityFilters,
  type AgentListRef,
  type AgentToolResultEnvelope,
  type JsonObject,
} from "./contracts.ts";

const MAX_CARDS = 6;
const kindsByDestination: Readonly<Record<AgentActionCard["destination"], readonly string[]>> = {
  customers: ["customer"],
  suppliers: ["supplier"],
  workshop_jobs: ["job"],
  sales_invoices: ["sales_invoice"],
  purchases: ["purchase_invoice"],
  inventory_products: ["inventory"],
  tasks: ["task", "task_preview"],
  expenses: ["expense"],
  conversations: ["conversation"],
};
const entityKindByCardKind: Readonly<Record<string, AgentEntityKind | undefined>> = {
  customer: "customer",
  supplier: "supplier",
  job: "workshopJob",
  sales_invoice: "salesInvoice",
  purchase_invoice: "purchaseInvoice",
  inventory: "product",
  task: undefined,
  task_preview: undefined,
  expense: "expense",
  conversation: "conversation",
};

export function cardsForToolResult(
  toolName: string,
  result: AgentToolResultEnvelope,
  argumentsValue: JsonObject = {},
): readonly AgentActionCard[] {
  if (toolName === "search_inventory") {
    return inventorySearchCards(result, argumentsValue);
  }
  if (result.status !== "success" && result.status !== "partial") return [];
  if (toolName === "list_attention_items") return attentionCards(result.items);
  if (toolName === "find_inventory_risks") return inventoryRiskCards(result.items);
  if (toolName === "analyze_cash_and_receivables") {
    return receivableCards(result.items.filter((item) => item.kind === "receivable").slice(0, 3));
  }
  const items = result.items.slice(0, 3);
  switch (toolName) {
    case "search_workshop_jobs":
      return items.map((item) =>
        card({
          kind: "job",
          eyebrow: "Trabajo",
          title: text(item, "jobNumber", "Trabajo"),
          subtitle: join([
            optionalText(item, "customerName"),
            optionalText(item, "assignedTechnicianName"),
          ]),
          description: optionalText(item, "clientRequest"),
          destination: "workshop_jobs",
          chips: compact([optionalText(item, "status"), optionalText(item, "priority")]),
          entityRef: entityRef(item, "workshopJob"),
        })
      );
    case "search_tasks":
      return items.map((item) =>
        card({
          kind: "task",
          eyebrow: "Tarea",
          title: text(item, "title", "Tarea"),
          subtitle: join([optionalText(item, "assigneeName"), optionalText(item, "linkedContext")]),
          destination: "tasks",
          chips: compact([optionalText(item, "status"), optionalText(item, "priority")]),
        })
      );
    case "prepare_task":
      return items.map(preparedTaskCard);
    case "search_customers":
      return entityCards(items, "customer", "Cliente", "customers");
    case "search_suppliers":
      return entityCards(items, "supplier", "Proveedor", "suppliers");
    case "search_sales_invoices":
      return invoiceCards(items, false);
    case "search_purchase_invoices":
      return invoiceCards(items, true);
    case "list_recent_expenses":
      return expenseCards(items);
    case "search_conversations":
      return conversationCards(items);
    default:
      return [];
  }
}

function inventorySearchCards(
  result: AgentToolResultEnvelope,
  argumentsValue: JsonObject,
): readonly AgentActionCard[] {
  const technicalFilterChips = inventoryTechnicalFilterChips(
    argumentsValue.technicalPredicates,
  );
  const category = argumentsValue.category === null
    ? null
    : typeof argumentsValue.category === "string" && argumentsValue.category.trim() &&
        new TextEncoder().encode(argumentsValue.category.trim()).length <= 160
    ? argumentsValue.category.trim()
    : undefined;
  const technicalMatchSummary = inventoryTechnicalMatchSummary(
    result,
    technicalFilterChips,
  );
  if (
    !["success", "partial", "verifiedEmpty"].includes(result.status) ||
    !(argumentsValue.query === null ||
      (typeof argumentsValue.query === "string" && argumentsValue.query.trim())) ||
    !agentInventoryAvailabilityFilters.includes(
      argumentsValue.availability as AgentInventoryAvailabilityFilter,
    ) ||
    !["answer", "open_list"].includes(String(argumentsValue.presentation)) ||
    technicalFilterChips === null || category === undefined ||
    technicalMatchSummary === null
  ) return [];
  const entityIds = result.items.map((item) => {
    if (typeof item.entityId !== "string" || !validUuid(item.entityId)) {
      throw new Error("Invalid inventory list entity id");
    }
    return item.entityId.toLowerCase();
  });
  if (new Set(entityIds).size !== entityIds.length) {
    throw new Error("Duplicate inventory list entity id");
  }
  const availability = argumentsValue.availability as AgentInventoryAvailabilityFilter;
  const resultCount = result.resultCount;
  const title = resultCount === 0
    ? "Sin resultados"
    : `${resultCount}${result.hasMore ? "+" : ""} ${
      resultCount === 1 ? "resultado" : "resultados"
    }`;
  const filterLabel = category ??
    (typeof argumentsValue.query === "string" ? argumentsValue.query.trim() : null);
  if (!filterLabel) return [];
  return [card({
    kind: "inventory",
    eyebrow: "Inventario",
    title,
    subtitle: technicalMatchSummary
      ? `${filterLabel} · ${technicalMatchSummary}`
      : `Coincidencias para “${filterLabel}”`,
    destination: "inventory_products",
    chips: [inventoryAvailabilityLabel(availability), ...technicalFilterChips],
    listRef: Object.freeze({
      kind: "inventory",
      query: filterLabel,
      availability,
      resultCount,
      hasMore: result.hasMore,
      entityIds: result.hasMore ? null : Object.freeze(entityIds),
      autoOpen: argumentsValue.presentation === "open_list",
    }),
  })];
}

function inventoryTechnicalMatchSummary(
  result: AgentToolResultEnvelope,
  technicalFilterChips: readonly string[] | null,
): string | null {
  if (technicalFilterChips === null) return null;
  if (technicalFilterChips.length === 0 || result.items.length === 0) return "";
  let productSpec = 0;
  let identityFallback = 0;
  for (const item of result.items) {
    if (item.technicalMatch === "product_spec") productSpec++;
    else if (item.technicalMatch === "identity_fallback") identityFallback++;
    else return null;
  }
  return [
    productSpec > 0
      ? `${productSpec} ${productSpec === 1 ? "ficha técnica" : "fichas técnicas"}`
      : null,
    identityFallback > 0 ? `${identityFallback} por identidad` : null,
  ].filter((value): value is string => value !== null).join(" · ");
}

function inventoryTechnicalFilterChips(value: unknown): readonly string[] | null {
  if (!Array.isArray(value) || value.length > 8) return null;
  const fields = new Set<string>();
  const chips: string[] = [];
  for (const item of value) {
    if (!item || typeof item !== "object" || Array.isArray(item)) return null;
    const entries = Object.entries(item);
    if (
      entries.length !== 3 ||
      !entries.every(([key]) => key === "field" || key === "operator" || key === "values")
    ) return null;
    const field = (item as Record<string, unknown>).field;
    const operator = (item as Record<string, unknown>).operator;
    const values = (item as Record<string, unknown>).values;
    if (
      typeof field !== "string" || !/^[a-z][a-z0-9_]{1,63}$/.test(field) ||
      fields.has(field) || typeof operator !== "string" ||
      !["eq", "neq", "lt", "lte", "gt", "gte", "between", "in", "contains"]
        .includes(operator) ||
      !Array.isArray(values) || values.length < 1 || values.length > 10 ||
      values.some((filterValue) =>
        !["string", "number", "boolean"].includes(typeof filterValue) ||
        (typeof filterValue === "string" &&
          (!filterValue.trim() ||
            new TextEncoder().encode(filterValue.trim()).length > 120))
      )
    ) return null;
    fields.add(field);
    const renderedValues = values.map((filterValue) =>
      typeof filterValue === "string" ? filterValue.trim() : String(filterValue)
    );
    chips.push(inventoryPredicateLabel(operator, renderedValues));
  }
  return Object.freeze(chips.slice(0, 3));
}

function inventoryPredicateLabel(operator: string, values: readonly string[]): string {
  switch (operator) {
    case "eq":
      return values[0];
    case "neq":
      return `≠ ${values[0]}`;
    case "lt":
      return `< ${values[0]}`;
    case "lte":
      return `≤ ${values[0]}`;
    case "gt":
      return `> ${values[0]}`;
    case "gte":
      return `≥ ${values[0]}`;
    case "between":
      return `${values[0]}–${values[1]}`;
    case "in":
      return values.join(" / ");
    case "contains":
      return `contiene ${values[0]}`;
    default:
      return values[0] ?? "";
  }
}

export function autoOpenListAnswer(
  cards: readonly AgentActionCard[],
  supportsResultLists: boolean,
): string | undefined {
  if (cards.length !== 1) return undefined;
  const listRef = cards[0].listRef;
  if (!listRef?.autoOpen || listRef.kind !== "inventory") return undefined;
  const filter = inventoryAvailabilityLabel(listRef.availability);
  if (listRef.resultCount === 0) {
    return supportsResultLists
      ? `No encontré resultados con el filtro “${filter}”. Abrí Inventario para que puedas revisarlo o ajustarlo.`
      : `No encontré resultados con el filtro “${filter}”. Usa la tarjeta para revisar o ajustar la búsqueda en Inventario.`;
  }
  const count = listRef.hasMore
    ? `${listRef.resultCount} o más resultados`
    : `${listRef.resultCount} ${listRef.resultCount === 1 ? "resultado" : "resultados"}`;
  return supportsResultLists
    ? `Abrí ${count} coincidentes en Inventario con el filtro “${filter}”.`
    : `Encontré ${count} coincidentes en Inventario con el filtro “${filter}”. Usa la tarjeta para abrirlos.`;
}

/** Keeps rolling client updates compatible with the strict v1 card decoder. */
export function cardsForClient(
  cards: readonly AgentActionCard[],
  supportsResultLists: boolean,
): readonly AgentActionCard[] {
  if (supportsResultLists || !cards.some((item) => item.listRef)) return cards;
  return Object.freeze(cards.map((item) => {
    if (!item.listRef) return item;
    const { listRef: _unsupportedListRef, ...compatible } = item;
    return card(compatible);
  }));
}

function inventoryAvailabilityLabel(value: AgentInventoryAvailabilityFilter): string {
  switch (value) {
    case "any":
      return "Todos";
    case "in_stock":
      return "En stock";
    case "low_stock":
      return "Stock bajo";
    case "out_of_stock":
      return "Agotados";
  }
}

function inventoryRiskCards(items: readonly JsonObject[]): readonly AgentActionCard[] {
  if (items.length === 0) return [];
  const outOfStock = items.filter((item) => item.risk === "out_of_stock").length;
  const lowStock = items.filter((item) => item.risk === "low_stock").length;
  return [card({
    kind: "inventory",
    eyebrow: "Inventario",
    title: "Revisar riesgos de inventario",
    subtitle: `${items.length} ${
      items.length === 1 ? "producto detectado" : "productos detectados"
    }`,
    description: "Abre el inventario para revisar existencias y mínimos configurados.",
    destination: "inventory_products",
    chips: compact([
      outOfStock ? `${outOfStock} agotado${outOfStock === 1 ? "" : "s"}` : undefined,
      lowStock ? `${lowStock} con stock bajo` : undefined,
    ]),
  })];
}

function expenseCards(items: readonly JsonObject[]): readonly AgentActionCard[] {
  return items.map((item) =>
    card({
      kind: "expense",
      eyebrow: "Gasto",
      title: text(item, "expenseNumber", "Gasto"),
      subtitle: join([optionalText(item, "category"), optionalText(item, "issueDate")]),
      description: join([
        currencyAmount(item.totalAmount, item.currency, "Total"),
        currencyAmount(item.balance, item.currency, "Saldo"),
      ]),
      destination: "expenses",
      chips: compact([
        optionalText(item, "postingStatus"),
        optionalText(item, "paymentStatus"),
        optionalText(item, "approvalStatus"),
      ]),
      entityRef: entityRef(item, "expense"),
    })
  );
}

function receivableCards(items: readonly JsonObject[]): readonly AgentActionCard[] {
  return items.map((item) =>
    card({
      kind: "sales_invoice",
      eyebrow: "Cuenta por cobrar",
      title: text(item, "invoiceNumber", "Factura"),
      subtitle: optionalText(item, "dueDate"),
      description: money(item.balance, "Saldo"),
      destination: "sales_invoices",
      chips: compact([optionalText(item, "timing")]),
      entityRef: entityRef(item, "salesInvoice"),
    })
  );
}

function conversationCards(items: readonly JsonObject[]): readonly AgentActionCard[] {
  return items.map((item) =>
    card({
      kind: "conversation",
      eyebrow: "Conversación",
      title: channelTitle(item.channel),
      subtitle: join([
        optionalText(item, "contextLabel"),
        optionalText(item, "contextType"),
        optionalText(item, "lastMessageAt"),
      ]),
      description: item.needsReply === true ? "Requiere respuesta" : undefined,
      destination: "conversations",
      chips: compact([
        optionalText(item, "status"),
        typeof item.unreadCount === "number" && item.unreadCount > 0
          ? `${item.unreadCount} sin leer`
          : undefined,
      ]),
      entityRef: entityRef(item, "conversation"),
    })
  );
}

function channelTitle(value: unknown): string {
  switch (value) {
    case "website_portal":
      return "Conversación del portal web";
    case "facebook_messenger":
      return "Conversación de Messenger";
    case "whatsapp":
      return "Conversación de WhatsApp";
    case "instagram":
      return "Conversación de Instagram";
    case "internal":
      return "Conversación interna";
    default:
      return "Conversación";
  }
}

export function mergeCards(
  existing: readonly AgentActionCard[],
  additions: readonly AgentActionCard[],
): readonly AgentActionCard[] {
  const result = [...existing];
  const seen = new Set(result.map(cardIdentity));
  for (const item of additions) {
    const key = cardIdentity(item);
    if (!seen.has(key)) {
      seen.add(key);
      result.push(item);
    }
    if (result.length >= MAX_CARDS) break;
  }
  return Object.freeze(result);
}

function cardIdentity(item: AgentActionCard): string {
  return item.approvalRef
    ? `approval\u0000${item.approvalRef.id}`
    : item.entityRef
    ? `entity\u0000${item.entityRef.kind}\u0000${item.entityRef.id}`
    : item.listRef
    ? `list\u0000${item.listRef.kind}\u0000${item.listRef.query}\u0000${item.listRef.availability}`
    : `aggregate\u0000${item.destination}\u0000${item.kind}\u0000${item.title}`;
}

export function validateStoredCards(value: unknown): readonly AgentActionCard[] {
  if (!Array.isArray(value) || value.length > MAX_CARDS) throw new Error("Invalid stored cards");
  return Object.freeze(value.map((item) => {
    if (!isRecord(item)) throw new Error("Invalid stored card");
    const requiredKeys = new Set(["kind", "title", "destination", "chips"]);
    const optionalKeys = new Set([
      "eyebrow",
      "subtitle",
      "description",
      "entityRef",
      "approvalRef",
      "listRef",
    ]);
    if (Object.keys(item).some((key) => !requiredKeys.has(key) && !optionalKeys.has(key))) {
      throw new Error("Invalid stored card");
    }
    const destination = item.destination;
    if (
      typeof destination !== "string" ||
      !(agentCardDestinations as readonly string[]).includes(destination)
    ) throw new Error("Invalid stored card destination");
    const closedDestination = destination as AgentActionCard["destination"];
    if (!kindsByDestination[closedDestination].includes(String(item.kind))) {
      throw new Error("Invalid stored card kind");
    }
    if (!Array.isArray(item.chips) || item.chips.length > 4) throw new Error("Invalid card chips");
    const entityRefValue = validateEntityRef(item.entityRef, item.kind);
    const approvalRefValue = validateApprovalRef(item.approvalRef, item.kind);
    const listRefValue = validateListRef(
      item.listRef,
      item.kind,
      closedDestination,
      entityRefValue,
      approvalRefValue,
    );
    return card({
      kind: bounded(item.kind, 32, true),
      title: bounded(item.title, 160, true),
      destination: closedDestination,
      eyebrow: optionalBounded(item.eyebrow, 80),
      subtitle: optionalBounded(item.subtitle, 240),
      description: optionalBounded(item.description, 500),
      chips: item.chips.map((chip) => bounded(chip, 64, true)),
      entityRef: entityRefValue,
      approvalRef: approvalRefValue,
      listRef: listRefValue,
    });
  }));
}

function attentionCards(items: readonly JsonObject[]): readonly AgentActionCard[] {
  const sources = new Set(items.map((item) => optionalText(item, "source")));
  return [
    ...(sources.has("workshop")
      ? [card({
        kind: "job",
        eyebrow: "Taller",
        title: "Revisar trabajos que requieren atención",
        destination: "workshop_jobs",
        chips: [],
      })]
      : []),
    ...(sources.has("task")
      ? [card({
        kind: "task",
        eyebrow: "Tareas",
        title: "Revisar tareas que requieren atención",
        destination: "tasks",
        chips: [],
      })]
      : []),
  ];
}

function entityCards(
  items: readonly JsonObject[],
  kind: string,
  label: string,
  destination: "customers" | "suppliers",
): readonly AgentActionCard[] {
  return items.map((item) =>
    card({
      kind,
      eyebrow: label,
      title: text(item, "name", label),
      destination,
      chips: [item.isActive === true ? "Activo" : "Inactivo"],
      entityRef: entityRef(item, kind === "customer" ? "customer" : "supplier"),
    })
  );
}

function invoiceCards(items: readonly JsonObject[], purchase: boolean): readonly AgentActionCard[] {
  return items.map((item) =>
    card({
      kind: purchase ? "purchase_invoice" : "sales_invoice",
      eyebrow: purchase ? "Factura de compra" : "Factura de venta",
      title: text(item, "invoiceNumber", "Factura"),
      subtitle: optionalText(item, purchase ? "supplierName" : "customerName"),
      description: join([money(item.total, "Total"), money(item.balance, "Saldo")]),
      destination: purchase ? "purchases" : "sales_invoices",
      chips: compact([optionalText(item, "status")]),
      entityRef: entityRef(item, purchase ? "purchaseInvoice" : "salesInvoice"),
    })
  );
}

function preparedTaskCard(item: JsonObject): AgentActionCard {
  return card({
    kind: "task_preview",
    eyebrow: "Tarea por confirmar",
    title: text(item, "title", "Tarea"),
    subtitle: join([optionalText(item, "assigneeName"), optionalText(item, "dueAt")]),
    description: optionalText(item, "description"),
    destination: "tasks",
    chips: compact([optionalText(item, "priority"), "Requiere confirmación"]),
    approvalRef: approvalRef(item),
  });
}

export function committedTaskCard(item: JsonObject): AgentActionCard {
  return card({
    kind: "task",
    eyebrow: "Tarea creada",
    title: text(item, "title", "Tarea"),
    subtitle: join([optionalText(item, "assigneeName"), optionalText(item, "dueAt")]),
    description: optionalText(item, "description"),
    destination: "tasks",
    chips: compact([optionalText(item, "status"), optionalText(item, "priority")]),
  });
}

function card(value: AgentActionCard): AgentActionCard {
  const eyebrow = optionalProjectedText(value.eyebrow, 80);
  const subtitle = optionalProjectedText(value.subtitle, 240);
  const description = optionalProjectedText(value.description, 500);
  return Object.freeze({
    kind: projectedText(value.kind, 32, true),
    title: projectedText(value.title, 160, true),
    destination: value.destination,
    chips: Object.freeze(
      value.chips.slice(0, 4).map((chip) => projectedText(chip, 64, true)),
    ),
    ...(eyebrow ? { eyebrow } : {}),
    ...(subtitle ? { subtitle } : {}),
    ...(description ? { description } : {}),
    ...(value.entityRef ? { entityRef: Object.freeze({ ...value.entityRef }) } : {}),
    ...(value.approvalRef ? { approvalRef: Object.freeze({ ...value.approvalRef }) } : {}),
    ...(value.listRef
      ? {
        listRef: Object.freeze({
          ...value.listRef,
          entityIds: value.listRef.entityIds === null
            ? null
            : Object.freeze([...value.listRef.entityIds]),
        }),
      }
      : {}),
  });
}

function entityRef(item: JsonObject, kind: AgentEntityKind): AgentActionCard["entityRef"] {
  const id = item.entityId;
  if (typeof id !== "string") return undefined;
  if (!validUuid(id)) throw new Error("Invalid entity id");
  return Object.freeze({ kind, id: id.toLowerCase() });
}

function validateEntityRef(value: unknown, cardKind: unknown): AgentActionCard["entityRef"] {
  if (value === undefined) return undefined;
  if (
    !isRecord(value) || Object.keys(value).length !== 2 || !("kind" in value) || !("id" in value)
  ) {
    throw new Error("Invalid entity reference");
  }
  const expected = typeof cardKind === "string" ? entityKindByCardKind[cardKind] : undefined;
  if (
    !expected || value.kind !== expected || typeof value.id !== "string" || !validUuid(value.id)
  ) {
    throw new Error("Invalid entity reference");
  }
  return Object.freeze({ kind: expected, id: value.id.toLowerCase() });
}

function approvalRef(item: JsonObject): AgentApprovalRef {
  return validateApprovalRef({
    id: item.approvalId,
    action: item.action,
    state: item.state,
    expiresAt: item.expiresAt,
  }, "task_preview")!;
}

function validateApprovalRef(
  value: unknown,
  cardKind: unknown,
): AgentActionCard["approvalRef"] {
  if (value === undefined) {
    if (cardKind === "task_preview") throw new Error("Missing approval reference");
    return undefined;
  }
  if (
    cardKind !== "task_preview" || !isRecord(value) ||
    !hasExactKeys(value, ["id", "action", "state", "expiresAt"]) ||
    typeof value.id !== "string" || !validUuid(value.id) ||
    value.action !== "create_task" ||
    typeof value.state !== "string" ||
    !(agentApprovalStates as readonly string[]).includes(value.state) ||
    typeof value.expiresAt !== "string" || !isoInstant(value.expiresAt)
  ) throw new Error("Invalid approval reference");
  return Object.freeze({
    id: value.id.toLowerCase(),
    action: "create_task",
    state: value.state as AgentApprovalRef["state"],
    expiresAt: value.expiresAt,
  });
}

function validateListRef(
  value: unknown,
  cardKind: unknown,
  destination: AgentActionCard["destination"],
  entityRefValue: AgentActionCard["entityRef"],
  approvalRefValue: AgentActionCard["approvalRef"],
): AgentListRef | undefined {
  if (value === undefined) return undefined;
  if (
    cardKind !== "inventory" || destination !== "inventory_products" ||
    entityRefValue !== undefined || approvalRefValue !== undefined ||
    !isRecord(value) ||
    !hasExactKeys(value, [
      "kind",
      "query",
      "availability",
      "resultCount",
      "hasMore",
      "entityIds",
      "autoOpen",
    ]) ||
    value.kind !== "inventory" ||
    typeof value.query !== "string" || !value.query.trim() ||
    new TextEncoder().encode(value.query.trim()).byteLength > 240 ||
    typeof value.availability !== "string" ||
    !(agentInventoryAvailabilityFilters as readonly string[]).includes(value.availability) ||
    !Number.isSafeInteger(value.resultCount) ||
    (value.resultCount as number) < 0 || (value.resultCount as number) > 10 ||
    typeof value.hasMore !== "boolean" || typeof value.autoOpen !== "boolean" ||
    !(value.entityIds === null || Array.isArray(value.entityIds))
  ) throw new Error("Invalid list reference");
  const entityIds = value.entityIds === null ? null : value.entityIds.map((id) => {
    if (typeof id !== "string" || !validUuid(id)) {
      throw new Error("Invalid list reference");
    }
    return id.toLowerCase();
  });
  if (
    (value.hasMore ? entityIds !== null : entityIds === null) ||
    (entityIds !== null && entityIds.length !== value.resultCount) ||
    (entityIds !== null && new Set(entityIds).size !== entityIds.length)
  ) throw new Error("Invalid list reference");
  return Object.freeze({
    kind: "inventory",
    query: value.query.trim(),
    availability: value.availability as AgentInventoryAvailabilityFilter,
    resultCount: value.resultCount as number,
    hasMore: value.hasMore,
    entityIds: entityIds === null ? null : Object.freeze(entityIds),
    autoOpen: value.autoOpen,
  });
}

function validUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

function isoInstant(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/.test(value) &&
    Number.isFinite(Date.parse(value));
}

function text(item: JsonObject, key: string, fallback: string): string {
  return optionalText(item, key) ?? fallback;
}

function optionalText(item: JsonObject, key: string): string | undefined {
  const value = item[key];
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function money(value: unknown, prefix: string): string | undefined {
  return typeof value === "number" && Number.isFinite(value)
    ? `${prefix} $${Math.round(value).toLocaleString("es-CL")}`
    : undefined;
}

function currencyAmount(value: unknown, currency: unknown, prefix: string): string | undefined {
  if (typeof value !== "number" || !Number.isFinite(value)) return undefined;
  const code = typeof currency === "string" && currency.trim() ? currency.trim() : "CLP";
  return `${prefix} ${code} ${value.toLocaleString("es-CL", { maximumFractionDigits: 6 })}`;
}

function join(values: readonly (string | undefined)[]): string | undefined {
  const parts = compact(values);
  return parts.length ? parts.join(" • ") : undefined;
}

function compact(values: readonly (string | undefined)[]): string[] {
  return values.filter((value): value is string => Boolean(value?.trim()));
}

function bounded(value: unknown, max: number, required: boolean): string {
  if (
    typeof value !== "string" || new TextEncoder().encode(value).byteLength > max ||
    (required && !value.trim())
  ) {
    throw new Error("Invalid card text");
  }
  return value.trim();
}

function optionalBounded(value: unknown, max: number): string | undefined {
  if (value === undefined || value === null || value === "") return undefined;
  return bounded(value, max, true);
}

function projectedText(value: unknown, max: number, required: boolean): string {
  if (typeof value !== "string" || (required && !value.trim())) {
    throw new Error("Invalid card text");
  }
  const normalized = value.trim();
  if (new TextEncoder().encode(normalized).byteLength <= max) return normalized;
  let result = "";
  let bytes = 0;
  for (const scalar of normalized) {
    const next = new TextEncoder().encode(scalar).byteLength;
    if (bytes + next > max) break;
    result += scalar;
    bytes += next;
  }
  if (required && !result) throw new Error("Invalid card text");
  return result;
}

function optionalProjectedText(value: unknown, max: number): string | undefined {
  if (value === undefined || value === null || value === "") return undefined;
  return projectedText(value, max, true);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, expected: readonly string[]): boolean {
  return JSON.stringify(Object.keys(value).sort()) === JSON.stringify([...expected].sort());
}
