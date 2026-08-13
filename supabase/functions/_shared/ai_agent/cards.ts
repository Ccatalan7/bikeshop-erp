import {
  type AgentActionCard,
  type AgentApprovalRef,
  agentApprovalStates,
  agentCardDestinations,
  type AgentEntityKind,
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
): readonly AgentActionCard[] {
  if (result.status !== "success" && result.status !== "partial") return [];
  if (toolName === "list_attention_items") return attentionCards(result.items);
  if (toolName === "find_inventory_risks") return inventoryRiskCards(result.items);
  if (toolName === "analyze_cash_and_receivables") {
    return receivableCards(result.items.filter((item) => item.kind === "receivable").slice(0, 3));
  }
  const items = result.items.slice(0, 3);
  switch (toolName) {
    case "search_inventory":
      return items.map((item) =>
        card({
          kind: "inventory",
          eyebrow: "Inventario",
          title: text(item, "name", "Producto"),
          subtitle: join([optionalText(item, "sku"), optionalText(item, "brand")]),
          description: join([money(item.price, "Precio"), number(item.stock, "Stock")]),
          destination: "inventory_products",
          chips: optionalText(item, "category") ? [text(item, "category", "")] : [],
          entityRef: entityRef(item, "product"),
        })
      );
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

function number(value: unknown, prefix: string): string | undefined {
  return typeof value === "number" && Number.isFinite(value) ? `${prefix} ${value}` : undefined;
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
