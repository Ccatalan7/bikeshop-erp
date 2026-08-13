import { cardsForToolResult, mergeCards, validateStoredCards } from "./cards.ts";
import type { AgentActionCard, AgentToolResultEnvelope, JsonObject } from "./contracts.ts";

const tenantId = "22222222-2222-4222-8222-222222222222";
const entityId = "11111111-1111-4111-8111-111111111111";

function result(item: JsonObject): AgentToolResultEnvelope {
  return {
    authorityTenantId: tenantId,
    asOf: "2026-08-11T12:00:00Z",
    status: "success",
    items: [item],
    resultCount: 1,
    hasMore: false,
  };
}

function assertEquals(actual: unknown, expected: unknown, message: string): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${message}: ${JSON.stringify(actual)} != ${JSON.stringify(expected)}`);
  }
}

function assertNoUndefined(value: unknown, message: string): void {
  if (value === undefined) throw new Error(message);
  if (Array.isArray(value)) {
    for (const item of value) assertNoUndefined(item, message);
    return;
  }
  if (value && typeof value === "object") {
    for (const item of Object.values(value)) assertNoUndefined(item, message);
  }
}

Deno.test("server cards match every closed Flutter destination-kind pair", () => {
  const cases: Array<[string, JsonObject, string, string, string | null]> = [
    [
      "search_customers",
      { entityId, name: "Ana", isActive: true },
      "customers",
      "customer",
      "customer",
    ],
    [
      "search_suppliers",
      { entityId, name: "Shimano", isActive: true },
      "suppliers",
      "supplier",
      "supplier",
    ],
    [
      "search_workshop_jobs",
      { entityId, jobNumber: "PG-1" },
      "workshop_jobs",
      "job",
      "workshopJob",
    ],
    [
      "search_sales_invoices",
      { entityId, invoiceNumber: "FV-1" },
      "sales_invoices",
      "sales_invoice",
      "salesInvoice",
    ],
    [
      "search_purchase_invoices",
      { entityId, invoiceNumber: "FC-1" },
      "purchases",
      "purchase_invoice",
      "purchaseInvoice",
    ],
    [
      "search_inventory",
      { entityId, name: "Cadena" },
      "inventory_products",
      "inventory",
      "product",
    ],
    ["search_tasks", { entityId, title: "Llamar" }, "tasks", "task", null],
    [
      "list_recent_expenses",
      { entityId, expenseNumber: "GG-1", currency: "CLP" },
      "expenses",
      "expense",
      "expense",
    ],
    [
      "analyze_cash_and_receivables",
      { kind: "receivable", entityId, invoiceNumber: "FV-2", balance: 1000 },
      "sales_invoices",
      "sales_invoice",
      "salesInvoice",
    ],
    [
      "search_conversations",
      {
        entityId,
        channel: "whatsapp",
        status: "active",
        unreadCount: 1,
        contextLabel: "PG-0042",
      },
      "conversations",
      "conversation",
      "conversation",
    ],
  ];
  for (const [tool, item, destination, kind, entityKind] of cases) {
    const card = cardsForToolResult(tool, result(item))[0];
    assertEquals(card.destination, destination, `${tool} destination`);
    assertEquals(card.kind, kind, `${tool} kind`);
    const decoded = validateStoredCards([card])[0];
    assertEquals(decoded.destination, destination, `${tool} survives strict destination decode`);
    assertEquals(decoded.kind, kind, `${tool} survives strict kind decode`);
    assertEquals(card.entityRef?.kind ?? null, entityKind, `${tool} exact entity route kind`);
    assertEquals(card.entityRef?.id ?? null, entityKind ? entityId : null, `${tool} server ID`);
  }
});

Deno.test("inventory risks use one aggregate card and cash summary creates no route", () => {
  const riskResult: AgentToolResultEnvelope = {
    authorityTenantId: tenantId,
    asOf: "2026-08-11T12:00:00Z",
    status: "success",
    items: [
      { entityId, name: "Cadena", risk: "out_of_stock" },
      {
        entityId: "22222222-2222-4222-8222-222222222222",
        name: "Pastillas",
        risk: "low_stock",
      },
    ],
    resultCount: 2,
    hasMore: false,
  };
  const cards = cardsForToolResult("find_inventory_risks", riskResult);
  assertEquals(cards.length, 1, "risk rows collapse into one quiet card");
  assertEquals(cards[0].destination, "inventory_products", "aggregate opens inventory");
  assertEquals(cards[0].entityRef ?? null, null, "aggregate never routes to one product");
  validateStoredCards(cards);

  assertEquals(
    cardsForToolResult("analyze_cash_and_receivables", result({ kind: "summary" })).length,
    0,
    "cash summary has no misleading aggregate route",
  );
});

Deno.test("server cards omit absent optional fields before runtime attestation", () => {
  const cards = cardsForToolResult("list_attention_items", {
    authorityTenantId: tenantId,
    asOf: "2026-08-11T12:00:00Z",
    status: "success",
    items: [{ source: "workshop" }, { source: "task" }],
    resultCount: 2,
    hasMore: false,
  });

  assertEquals(cards.length, 2, "attention sources create two aggregate cards");
  assertNoUndefined(cards, "attested card payload cannot contain undefined");
  assertEquals(
    JSON.parse(JSON.stringify(cards)),
    cards,
    "card JSON shape is stable without implicit key dropping",
  );
});

Deno.test("cards deduplicate and remain bounded to six", () => {
  const cards: AgentActionCard[] = Array.from({ length: 8 }, (_, index) => ({
    kind: "task",
    title: `Tarea ${index}`,
    destination: "tasks",
    chips: [],
  }));
  const merged = mergeCards([cards[0]], [cards[0], ...cards.slice(1)]);
  assertEquals(merged.length, 6, "card array bound");
  assertEquals(merged.filter((card) => card.title === "Tarea 0").length, 1, "duplicate removed");

  const sameTitleDifferentRecords = mergeCards([], [
    {
      kind: "customer",
      title: "Juan Pérez",
      destination: "customers",
      chips: [],
      entityRef: { kind: "customer", id: entityId },
    },
    {
      kind: "customer",
      title: "Juan Pérez",
      destination: "customers",
      chips: [],
      entityRef: { kind: "customer", id: "22222222-2222-4222-8222-222222222222" },
    },
  ]);
  assertEquals(sameTitleDifferentRecords.length, 2, "server identities prevent title collisions");
});

Deno.test("stored cards reject oversize or non-closed payloads", () => {
  for (
    const invalid of [
      [{ kind: "task", title: "x".repeat(161), destination: "tasks", chips: [] }],
      [{ kind: "task", title: "😀".repeat(41), destination: "tasks", chips: [] }],
      [{ kind: "task", title: "T", destination: "unknown", chips: [] }],
      [{ kind: "customer", title: "T", destination: "tasks", chips: [] }],
      [{ kind: "task", title: "T", destination: "tasks", chips: Array(5).fill("x") }],
      [{ kind: "task", title: "T", destination: "tasks", chips: [], route: "/evil" }],
      [{ kind: "task", title: "T", destination: "tasks", chips: [], entityRef: null }],
      [{
        kind: "expense",
        title: "Gasto",
        destination: "expenses",
        chips: [],
        entityRef: { kind: "conversation", id: entityId },
      }],
      [{
        kind: "conversation",
        title: "Chat",
        destination: "conversations",
        chips: [],
        entityRef: { kind: "expense", id: entityId },
      }],
      [{
        kind: "job",
        title: "T",
        destination: "workshop_jobs",
        chips: [],
        entityRef: { kind: "customer", id: entityId },
      }],
      [{
        kind: "customer",
        title: "T",
        destination: "customers",
        chips: [],
        entityRef: { kind: "customer", id: "not-a-uuid" },
      }],
      [{
        kind: "task",
        title: "T",
        destination: "tasks",
        chips: [],
        entityRef: { kind: "product", id: entityId },
      }],
    ]
  ) {
    let rejected = false;
    try {
      validateStoredCards(invalid);
    } catch (_) {
      rejected = true;
    }
    assertEquals(rejected, true, "invalid stored card rejected");
  }
});

Deno.test("valid ERP rows project long chip values without failing the run", () => {
  const asciiStatus = "s".repeat(100);
  const asciiCard = cardsForToolResult(
    "search_tasks",
    result({ title: "Tarea válida", status: asciiStatus }),
  )[0];
  assertEquals(
    new TextEncoder().encode(asciiCard.chips[0]).byteLength,
    64,
    "100-byte DB status is projected to the card bound",
  );

  const emojiStatus = "😀".repeat(25);
  const emojiCard = cardsForToolResult(
    "search_workshop_jobs",
    result({ jobNumber: "PG-1", status: emojiStatus }),
  )[0];
  assertEquals(
    new TextEncoder().encode(emojiCard.chips[0]).byteLength,
    64,
    "multibyte projection ends on a Unicode scalar boundary",
  );
  assertEquals(emojiCard.chips[0], "😀".repeat(16), "projection never splits an emoji");
  validateStoredCards([asciiCard, emojiCard]);
});

Deno.test("task preparation card carries one closed durable approval reference", () => {
  const approvalId = "99999999-9999-4999-8999-999999999999";
  const expiresAt = "2026-08-12T12:10:00.000000Z";
  const preview = cardsForToolResult(
    "prepare_task",
    result({
      approvalId,
      action: "create_task",
      state: "pending",
      title: "Llamar al cliente",
      description: "Confirmar retiro",
      priority: "high",
      dueAt: "2026-08-13T16:00:00Z",
      assigneeMode: "me",
      assigneeName: "Tú",
      expiresAt,
    }),
  )[0];
  assertEquals(preview.kind, "task_preview", "draft kind");
  assertEquals(preview.destination, "tasks", "closed destination");
  assertEquals(preview.entityRef ?? null, null, "draft is not yet a task entity");
  assertEquals(preview.approvalRef, {
    id: approvalId,
    action: "create_task",
    state: "pending",
    expiresAt,
  }, "exact approval wire");
  const decoded = validateStoredCards([preview])[0];
  assertEquals(decoded.kind, preview.kind, "approval survives ledger kind validation");
  assertEquals(decoded.approvalRef, preview.approvalRef, "approval survives ledger validation");

  for (
    const invalid of [
      { ...preview, approvalRef: undefined },
      { ...preview, approvalRef: { ...preview.approvalRef!, action: "delete_everything" } },
      { ...preview, approvalRef: { ...preview.approvalRef!, state: "executing" } },
      { ...preview, approvalRef: { ...preview.approvalRef!, expiresAt: "tomorrow" } },
      {
        kind: "task",
        title: "Tarea",
        destination: "tasks",
        chips: [],
        approvalRef: preview.approvalRef,
      },
    ]
  ) {
    let rejected = false;
    try {
      validateStoredCards([invalid]);
    } catch (_) {
      rejected = true;
    }
    assertEquals(rejected, true, "approval shape fails closed");
  }
});
