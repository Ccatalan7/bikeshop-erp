import {
  autoOpenListAnswer,
  cardsForClient,
  cardsForToolResult,
  mergeCards,
  validateStoredCards,
} from "./cards.ts";
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

Deno.test("structured supply requests project one strict review card", () => {
  const draftResult: AgentToolResultEnvelope = {
    authorityTenantId: tenantId,
    asOf: "2026-08-16T18:00:00Z",
    status: "success",
    items: [{
      entityId,
      lineRef: "line-1",
      description: "Neumático 27,5 ancho mayor a 2,0",
      productName: "Kenda Kwick 27,5 × 2,10",
      productSku: "KEN-275-210",
      identityState: "confirmed",
      quantity: 2,
      unit: "unit",
      technicalPredicates: [{ field: "tire_width", operator: "gt", values: [2] }],
      preference: "gama económica",
      clarification: null,
      clarificationRequired: false,
      clarificationPrompts: [],
      profile: "balanced",
    }, {
      entityId: null,
      lineRef: "line-2",
      description: "Rayos 27,5",
      productName: null,
      productSku: null,
      identityState: "unresolved",
      quantity: 1,
      unit: "set",
      technicalPredicates: [],
      preference: null,
      clarification: "¿Medida del rayo o compatibilidad con rueda 27,5?",
      clarificationRequired: true,
      clarificationPrompts: [{
        id: "measurement_meaning",
        question: "¿La medida pertenece al producto o al contexto donde se instalará?",
        inputKind: "single_choice",
        options: [{ value: "product", label: "Al producto" }, {
          value: "fitment",
          label: "Al contexto",
        }],
        unit: null,
        allowUnknown: false,
      }],
      profile: "balanced",
    }],
    resultCount: 2,
    hasMore: false,
  };
  const cards = cardsForToolResult("prepare_supply_request", draftResult);
  assertEquals(cards.length, 1, "one request becomes one review surface");
  assertEquals(cards[0].kind, "supply_need_draft", "draft kind is closed");
  assertEquals(cards[0].destination, "purchases", "draft destination is closed");
  assertEquals(cards[0].entityRef ?? null, null, "draft never invents one selected entity");
  assertEquals(cards[0].supplyNeedDraft?.lines.length, 2, "every requested line survives");
  assertEquals(
    cards[0].supplyNeedDraft?.lines[0].productId,
    entityId,
    "only the exact server-resolved product is retained",
  );
  assertEquals(
    cards[0].supplyNeedDraft?.lines[1].clarificationRequired,
    true,
    "technical ambiguity remains explicit",
  );
  assertEquals(
    cards[0].supplyNeedDraft?.lines[1].clarificationPrompts.length,
    1,
    "the next generic question remains typed",
  );
  const legacyCard = cardsForClient(cards, true, false)[0] as unknown as {
    supplyNeedDraft: { lines: Array<Record<string, unknown>> };
  };
  assertEquals(
    "clarificationPrompts" in legacyCard.supplyNeedDraft.lines[1],
    false,
    "capability negotiation preserves the strict v1 wire shape",
  );
  assertEquals(
    cardsForClient(cards, true, true)[0].supplyNeedDraft?.lines[1]
      .clarificationPrompts.length,
    1,
    "negotiated clients receive the structured prompt",
  );
  assertNoUndefined(cards, "draft card remains canonical JSON");
  assertEquals(
    validateStoredCards(cards)[0].supplyNeedDraft,
    cards[0].supplyNeedDraft,
    "the complete typed draft survives persistence",
  );

  const invalid = structuredClone(cards[0]) as unknown as Record<string, unknown>;
  const invalidDraft = invalid.supplyNeedDraft as Record<string, unknown>;
  const invalidLines = invalidDraft.lines as Array<Record<string, unknown>>;
  invalidLines[1].productName = "Producto no probado";
  let rejected = false;
  try {
    validateStoredCards([invalid]);
  } catch (_) {
    rejected = true;
  }
  assertEquals(rejected, true, "unresolved lines cannot smuggle confirmed identity text");
});

Deno.test("inventory search projects one exact compact result set instead of arbitrary rows", () => {
  const inventoryResult: AgentToolResultEnvelope = {
    authorityTenantId: tenantId,
    asOf: "2026-08-13T12:00:00Z",
    status: "success",
    items: [
      {
        entityId,
        name: "Camara 29 A",
        stock: 7,
        technicalMatch: "product_spec",
      },
      {
        entityId: "22222222-2222-4222-8222-222222222222",
        name: "Camara 29 B",
        stock: 1,
        technicalMatch: "identity_fallback",
      },
    ],
    resultCount: 2,
    hasMore: false,
  };
  const cards = cardsForToolResult(
    "search_inventory",
    inventoryResult,
    {
      query: "camara 29",
      category: "Cámaras",
      availability: "in_stock",
      presentation: "open_list",
      sort: { field: "relevance", direction: "desc" },
      limit: 10,
      selectionMode: "all_matches",
      operationalPredicates: [],
      technicalPredicates: [{ field: "wheel_size", operator: "eq", values: ['29"'] }],
    },
  );
  assertEquals(cards.length, 1, "all rows collapse into one result-set action");
  assertEquals(cards[0].entityRef ?? null, null, "list action never picks an arbitrary product");
  assertEquals(
    cards[0].chips,
    ["En stock", '29"'],
    "the compact action exposes the database-validated technical constraint",
  );
  assertEquals(cards[0].listRef, {
    kind: "inventory",
    query: "Cámaras",
    availability: "in_stock",
    resultCount: 2,
    hasMore: false,
    entityIds: [
      entityId,
      "22222222-2222-4222-8222-222222222222",
    ],
    autoOpen: true,
  }, "the exact complete server result is retained for the product list");
  assertEquals(
    cards[0].subtitle,
    "Cámaras · 1 ficha técnica · 1 por identidad",
    "the card distinguishes canonical specs from the explicit sparse-catalog fallback",
  );
  assertEquals(
    autoOpenListAnswer(cards, true),
    'Abrí 2 resultados coincidentes para “camara 29” en Inventario con el filtro “En stock · 29"”.',
    "model prose cannot diverge from an explicit list action",
  );
  assertEquals(
    autoOpenListAnswer(cards, false),
    'Encontré 2 resultados coincidentes para “camara 29” en Inventario con el filtro “En stock · 29"”. Usa la tarjeta para abrirlos.',
    "an older client gets truthful server-owned click guidance",
  );
  validateStoredCards(cards);
  assertEquals(
    cardsForClient(cards, false)[0].listRef ?? null,
    null,
    "older strict clients receive the aggregate action without the new field",
  );
  assertEquals(
    cardsForClient(cards, true)[0].listRef,
    cards[0].listRef,
    "capable clients receive the typed result set",
  );
  validateStoredCards(cardsForClient(cards, false));
});

Deno.test("inventory cards preserve operational thresholds in the visible filter", () => {
  const cards = cardsForToolResult("search_inventory", {
    authorityTenantId: tenantId,
    asOf: "2026-08-13T12:00:00Z",
    status: "success",
    items: [{
      entityId,
      name: "Camara 29 A",
      stock: 7,
      technicalMatch: "product_spec",
    }],
    resultCount: 1,
    hasMore: false,
  }, {
    query: null,
    category: "Cámaras",
    availability: "in_stock",
    presentation: "open_list",
    sort: { field: "relevance", direction: "desc" },
    limit: 10,
    selectionMode: "all_matches",
    technicalPredicates: [{ field: "wheel_size", operator: "eq", values: ['29"'] }],
    operationalPredicates: [{ field: "stock", operator: "gt", values: [5] }],
  });
  assertEquals(
    cards[0].chips,
    ["En stock", '29"', "Stock > 5"],
    "the compact card exposes every accumulated filter",
  );
  assertEquals(
    autoOpenListAnswer(cards, true),
    'Abrí 1 resultado coincidente para “Cámaras” en Inventario con el filtro “En stock · 29" · Stock > 5”.',
    "the server-owned answer cannot hide or weaken an exact numeric threshold",
  );

  const top = cardsForToolResult("search_inventory", {
    authorityTenantId: tenantId,
    asOf: "2026-08-13T12:00:00Z",
    status: "success",
    items: [{ entityId, name: "Camara 29 A", stock: 7, technicalMatch: "product_spec" }],
    resultCount: 1,
    hasMore: false,
  }, {
    query: null,
    category: "Cámaras",
    availability: "in_stock",
    presentation: "open_list",
    sort: { field: "stock", direction: "desc" },
    limit: 1,
    selectionMode: "top_n",
    technicalPredicates: [{ field: "wheel_size", operator: "eq", values: ['29"'] }],
    operationalPredicates: [],
  });
  assertEquals(
    top[0].chips,
    ["En stock", '29"', "Top 1 · Mayor stock"],
    "top-N ordering is visible instead of being hidden in model prose",
  );

  const wholeInventoryTop = cardsForToolResult("search_inventory", {
    authorityTenantId: tenantId,
    asOf: "2026-08-13T12:00:00Z",
    status: "success",
    items: [{ entityId, name: "Producto", stock: 1, technicalMatch: "not_applicable" }],
    resultCount: 1,
    hasMore: false,
  }, {
    query: null,
    category: null,
    availability: "in_stock",
    presentation: "open_list",
    sort: { field: "stock", direction: "asc" },
    limit: 1,
    selectionMode: "top_n",
    technicalPredicates: [],
    operationalPredicates: [],
  });
  assertEquals(
    wholeInventoryTop[0].listRef?.query,
    "Inventario",
    "a bounded whole-inventory query remains navigable without fake keyword text",
  );
});

Deno.test("inventory empty and truncated result sets remain truthful", () => {
  const empty: AgentToolResultEnvelope = {
    authorityTenantId: tenantId,
    asOf: "2026-08-13T12:00:00Z",
    status: "verifiedEmpty",
    items: [],
    resultCount: 0,
    hasMore: false,
  };
  const emptyCard = cardsForToolResult("search_inventory", empty, {
    query: "camara 31",
    category: null,
    availability: "in_stock",
    presentation: "open_list",
    sort: { field: "relevance", direction: "desc" },
    limit: 10,
    selectionMode: "all_matches",
    operationalPredicates: [],
    technicalPredicates: [{ field: "wheel_size", operator: "eq", values: ['31"'] }],
  })[0];
  assertEquals(emptyCard.listRef?.entityIds, [], "verified empty is an exact empty selection");
  assertEquals(
    autoOpenListAnswer([emptyCard], true),
    'No encontré resultados para “camara 31” con el filtro “En stock · 31"”. Abrí Inventario para que puedas revisarlo o ajustarlo.',
    "empty output is not rewritten as source failure",
  );

  const truncated = cardsForToolResult("search_inventory", {
    ...result({ entityId, name: "Camara" }),
    hasMore: true,
  }, {
    query: "camara",
    category: null,
    availability: "any",
    presentation: "answer",
    sort: { field: "relevance", direction: "desc" },
    limit: 10,
    selectionMode: "all_matches",
    operationalPredicates: [],
    technicalPredicates: [],
  })[0];
  assertEquals(truncated.listRef?.entityIds, null, "a truncated page never claims exact IDs");
  assertEquals(truncated.listRef?.hasMore, true, "truncation survives persistence");
  assertEquals(
    autoOpenListAnswer([truncated], true) ?? null,
    null,
    "informational reads never auto-open",
  );
  validateStoredCards([emptyCard, truncated]);
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
        kind: "inventory",
        title: "T",
        destination: "inventory_products",
        chips: [],
        listRef: null,
      }],
      [{
        kind: "inventory",
        title: "T",
        destination: "inventory_products",
        chips: [],
        entityRef: { kind: "product", id: entityId },
        listRef: {
          kind: "inventory",
          query: "camara",
          availability: "in_stock",
          resultCount: 1,
          hasMore: false,
          entityIds: [entityId],
          autoOpen: true,
        },
      }],
      [{
        kind: "inventory",
        title: "T",
        destination: "inventory_products",
        chips: [],
        listRef: {
          kind: "inventory",
          query: "camara",
          availability: "invented",
          resultCount: 0,
          hasMore: false,
          entityIds: [],
          autoOpen: true,
        },
      }],
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

Deno.test("workshop previews keep typed approvals and sales periods route only exact invoices", () => {
  const approvalId = "99999999-9999-4999-8999-999999999999";
  const jobId = "88888888-8888-4888-8888-888888888888";
  const expiresAt = "2026-08-14T01:10:00.000000Z";
  const diagnosis = cardsForToolResult(
    "prepare_diagnosis_update",
    result({
      approvalId,
      action: "update_diagnosis",
      state: "pending",
      jobId,
      jobBikeId: entityId,
      jobNumber: "PG-00420",
      bikeLabel: "Trek Marlin 7",
      field: "drivetrain.chain_wear_percent",
      fieldLabel: "Desgaste de cadena",
      previousValue: null,
      newValue: "0.60",
      expiresAt,
    }),
  )[0];
  const item = cardsForToolResult(
    "prepare_workshop_item",
    result({
      approvalId,
      action: "add_workshop_item",
      state: "pending",
      jobId,
      jobBikeId: entityId,
      jobNumber: "PG-00420",
      bikeLabel: "Trek Marlin 7",
      catalogItemId: entityId,
      itemName: "Cambio de cadena",
      itemType: "service",
      quantity: 1,
      unitPrice: 15000,
      lineTotal: 15000,
      invoiceNumber: null,
      expiresAt,
    }),
  )[0];
  assertEquals(diagnosis.kind, "diagnosis_preview", "diagnosis preview kind");
  assertEquals(
    diagnosis.approvalRef?.action,
    "update_diagnosis",
    "diagnosis action cannot drift",
  );
  assertEquals(item.kind, "workshop_item_preview", "item preview kind");
  assertEquals(
    item.approvalRef?.action,
    "add_workshop_item",
    "item action cannot drift",
  );
  validateStoredCards([diagnosis, item]);

  let mismatchedRejected = false;
  try {
    validateStoredCards([{
      ...diagnosis,
      approvalRef: { ...diagnosis.approvalRef!, action: "add_workshop_item" },
    }]);
  } catch (_) {
    mismatchedRejected = true;
  }
  assertEquals(mismatchedRejected, true, "preview kind and action remain inseparable");

  const sales = cardsForToolResult(
    "analyze_sales_period",
    result({
      basis: "collected",
      startDate: "2026-08-03",
      endDate: "2026-08-09",
      invoiceStatus: "any",
      invoiceCount: 3,
      eventCount: 4,
      totalAmount: 175000,
      averagePerInvoice: 58333.33,
      highestInvoiceId: entityId,
      highestInvoiceNumber: "FV-00419",
      highestInvoiceCustomerName: "María Soto",
      highestInvoiceTotal: 120000,
      highestPeriodAmount: 100000,
    }),
  );
  assertEquals(sales.length, 1, "one exact highest invoice card");
  assertEquals(sales[0].entityRef?.id, entityId, "highest invoice UUID is server-owned");
  validateStoredCards(sales);
});
