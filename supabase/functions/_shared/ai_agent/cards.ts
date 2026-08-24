import {
  defaultWhatsAppTemplates,
  renderWhatsAppTemplateBody,
} from "../whatsapp_templates.ts";
import {
  type AgentCardOption,
  type AgentActionCard,
  type AgentApprovalRef,
  agentApprovalStates,
  agentCardDestinations,
  type AgentEntityKind,
  type AgentInventoryAvailabilityFilter,
  agentInventoryAvailabilityFilters,
  type AgentListRef,
  type AgentSupplyNeedClarificationPrompt,
  type AgentToolResultEnvelope,
  type JsonObject,
} from "./contracts.ts";

const MAX_CARDS = 6;
const kindsByDestination: Readonly<Record<AgentActionCard["destination"], readonly string[]>> = {
  customers: ["customer"],
  suppliers: ["supplier"],
  workshop_jobs: ["job", "diagnosis_preview", "workshop_item_preview"],
  sales_invoices: ["sales_invoice"],
  purchases: ["purchase_invoice", "supply_need_draft"],
  inventory_products: ["inventory"],
  tasks: ["task", "task_preview"],
  expenses: ["expense"],
  conversations: ["conversation", "customer_contact"],
};
const entityKindByCardKind: Readonly<Record<string, AgentEntityKind | undefined>> = {
  customer: "customer",
  supplier: "supplier",
  job: "workshopJob",
  diagnosis_preview: undefined,
  workshop_item_preview: undefined,
  sales_invoice: "salesInvoice",
  purchase_invoice: "purchaseInvoice",
  supply_need_draft: undefined,
  inventory: "product",
  task: undefined,
  task_preview: undefined,
  expense: "expense",
  conversation: "conversation",
  // La tarjeta de contacto apunta al cliente: desde ahí se abre su ficha.
  customer_contact: "customer",
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
  if (toolName === "find_inventory_risks") return inventoryRiskCards(result);
  if (toolName === "analyze_cash_and_receivables") {
    return receivableCards(result.items.filter((item) => item.kind === "receivable").slice(0, 3));
  }
  if (toolName === "analyze_sales_period") return salesPeriodCards(result.items);
  if (toolName === "rank_purchase_suppliers") return supplierHistoryCards(result.items);
  if (toolName === "rank_basket_suppliers") return basketSupplierCards(result.items);
  if (toolName === "prepare_customer_contact") {
    return result.items.slice(0, 3).map((item) => {
      const open = item.windowOpen === true;
      return card({
        kind: "customer_contact",
        eyebrow: "Contactar cliente",
        title: text(item, "customerName", "Cliente"),
        subtitle: open
          ? "Ventana de 24 horas abierta"
          : "Fuera de la ventana de 24 horas",
        description: open
          ? "Puedes escribirle directamente. Revisa el texto antes de enviar."
          : "Meta sólo acepta una plantilla aprobada. Elige cuál, revisa el " +
            "texto exacto que le llegará y confirma.",
        destination: "conversations",
        chips: [
          ...(item.hasContactPhone === true ? [] : ["Sin teléfono"]),
          ...(typeof item.channel === "string" ? [item.channel] : []),
        ],
        entityRef: entityRef(item, "customer"),
        optionKind: open ? "whatsapp_freeform" : "whatsapp_template",
        // Fuera de la ventana, la tarjeta ofrece las plantillas aprobadas con
        // el texto EXACTO que recibirá el cliente. Elegir una no envía nada:
        // abre esa revisión y el operador confirma.
        options: open ? undefined : customerTemplateOptions(
          typeof item.businessName === "string" ? item.businessName : "",
        ),
      });
    });
  }
  const items = result.items.slice(0, 3);
  switch (toolName) {
    case "search_workshop_jobs":
      return items.map((item, index) =>
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
          chips: compact([
            workshopStatusLabel(optionalText(item, "status")),
            workshopPriorityLabel(optionalText(item, "priority")),
          ]),
          entityRef: entityRef(item, "workshopJob"),
          // Sobre el primer trabajo cuelgan los dos pasos que el taller da de
          // verdad después de mirar la lista: avisarle al cliente y saber qué
          // falta para cerrar. En cada fila serían un muro de botones.
          ...(index === 0
            ? {
              optionKind: "follow_up",
              options: [
                {
                  id: "workshop_blockers",
                  label: "¿Qué falta para cerrarlos?",
                  description: "Repuestos, aprobaciones y trabajos en pausa.",
                },
                {
                  id: "workshop_notify_ready",
                  label: "Avisar al cliente del primero",
                  description: "Prepara el mensaje, sin enviarlo.",
                },
              ] as readonly AgentCardOption[],
            }
            : {}),
        })
      );
    case "search_tasks":
      return items.map((item, index) =>
        card({
          kind: "task",
          eyebrow: "Tarea",
          title: text(item, "title", "Tarea"),
          subtitle: join([
            optionalText(item, "assigneeName"),
            optionalText(item, "linkedContext"),
          ]),
          destination: "tasks",
          chips: compact([
            taskStatusLabel(optionalText(item, "status")),
            taskPriorityChip(optionalText(item, "priority")),
          ]),
          ...(index === 0
            ? {
              optionKind: "follow_up",
              options: [
                {
                  id: "tasks_overdue_first",
                  label: "¿Cuáles están atrasadas?",
                  description: "Ordena por fecha de vencimiento.",
                },
              ] as readonly AgentCardOption[],
            }
            : {}),
        })
      );
    case "prepare_task":
      return items.map(preparedTaskCard);
    case "prepare_diagnosis_update":
      return items.map(preparedDiagnosisCard);
    case "prepare_workshop_item":
      return items.map(preparedWorkshopItemCard);
    case "prepare_supply_request":
      return preparedSupplyRequestCards(result.items);
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
  const operationalFilterChips = inventoryOperationalFilterChips(
    argumentsValue.operationalPredicates,
  );
  const orderChips = inventoryOrderChips(
    argumentsValue.sort,
    argumentsValue.limit,
    argumentsValue.selectionMode,
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
    !["answer", "open_list", "open_list_with_analysis"].includes(
      String(argumentsValue.presentation),
    ) ||
    technicalFilterChips === null || operationalFilterChips === null || orderChips === null ||
    category === undefined || technicalMatchSummary === null
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
  // «10+ resultados» es un número sin referente: no dice de cuántos son diez.
  // Y la lista que se abre son exactamente éstos, así que se nombran como lo
  // que son.
  //
  // **El total va en el título, no en `listRef`** (2026-08-24). El decodificador
  // del cliente exige claves EXACTAS en `listRef`, así que una clave nueva ahí
  // haría que las apps ya publicadas rechacen toda tarjeta de inventario. El
  // título es texto libre acotado a 160 bytes y llega igual a la pantalla.
  //
  // Sin el total, «Los primeros 10» de una consulta que calza con 24 esconde
  // 14 productos sin decirlo: medido con «26x2.1», donde dos de los ocultos
  // tenían stock.
  // El total sale de `matchedCount`, que viaja en cada fila y cuenta el conjunto
  // filtrado completo. **No de `totalMatches` del sobre**, que hoy devuelve el
  // tamaño de la página: medido el 2026-08-24 sobre «26x2.1», el sobre decía
  // `hasMore: true` y `totalMatches: 10` —contradictorio consigo mismo— mientras
  // `matchedCount` decía 24, que es la verdad.
  const firstMatchedCount = result.items[0]?.matchedCount;
  const totalMatches = typeof firstMatchedCount === "number" &&
      Number.isSafeInteger(firstMatchedCount) && firstMatchedCount > resultCount
    ? firstMatchedCount
    : null;
  const title = resultCount === 0
    ? "Sin resultados"
    : result.hasMore
    ? (totalMatches === null
      ? `Los primeros ${resultCount}`
      : `Los primeros ${resultCount} de ${totalMatches}`)
    : `${resultCount} ${resultCount === 1 ? "resultado" : "resultados"}`;
  const identityQuery = typeof argumentsValue.query === "string"
    ? argumentsValue.query.trim()
    : null;
  const spokenSubject = spokenListSubject(identityQuery, category);
  // El subtítulo puede mostrar las dos —«Piñones · Shimano» dice más que
  // cualquiera sola—, pero no repite la que no agrega: con «camara 29» dentro
  // de «Cámaras» la segunda sobra. La frase final, en cambio, nombra UNA cosa;
  // por eso usa `spokenSubject` y no esto.
  const identityAddsMeaning = Boolean(identityQuery) &&
    spokenSubject === identityQuery;
  const filterLabel = [
    category,
    identityAddsMeaning ? identityQuery : undefined,
  ].filter((value): value is string => Boolean(value)).join(" · ") ||
    "Inventario";
  // Dos textos porque son dos cosas. `query` es el respaldo para el buscador
  // local y `spokenSubject` es cómo se le nombra al operador lo que está
  // viendo; ahí manda la categoría resuelta cuando la hay, porque rotular la
  // lista con lo que él tipeó esconde un malentendido.
  //
  // **`query` ya no es el camino cuando el resultado se truncó.** Se creía que
  // «con el resultado truncado la frase es lo único que reencuentra esas
  // filas», y era falso: la frase sólo funciona a través de la traducción de
  // ficha que hace el servidor, y el buscador local compara texto literal.
  // Queda como respaldo para un cliente viejo que no lea `entityIds`.
  const navigationQuery = identityQuery ?? category ?? "Inventario";
  return [card({
    kind: "inventory",
    eyebrow: "Inventario",
    title,
    subtitle: technicalMatchSummary
      ? `${filterLabel} · ${technicalMatchSummary}`
      : `Coincidencias para “${filterLabel}”`,
    destination: "inventory_products",
    chips: [
      inventoryAvailabilityLabel(availability),
      ...technicalFilterChips,
      ...operationalFilterChips,
      ...orderChips,
    ],
    listRef: Object.freeze({
      kind: "inventory",
      query: navigationQuery,
      spokenSubject,
      availability,
      resultCount,
      hasMore: result.hasMore,
      // **Las ids viajan siempre, truncado o no.** Mandarlas en null cuando
      // había más resultados dejaba al cliente buscando la frase como texto, y
      // eso no encuentra nada: mientras más acertaba la búsqueda, más vacía
      // salía la lista. «cámaras 26 con válvula VA de 48mm» calzaba con 15
      // productos de la ficha y abría cero. Son las que se pudieron mostrar,
      // no la selección completa: `hasMore` lo dice y el título las nombra
      // «los primeros N».
      entityIds: Object.freeze(entityIds),
      autoOpen: argumentsValue.presentation === "open_list" ||
        argumentsValue.presentation === "open_list_with_analysis",
    }),
  })];
}

function inventoryOrderChips(
  value: unknown,
  limit: unknown,
  selectionMode: unknown,
): readonly string[] | null {
  if (
    !value || typeof value !== "object" || Array.isArray(value) ||
    Object.keys(value).length !== 2 ||
    !Object.hasOwn(value, "field") || !Object.hasOwn(value, "direction") ||
    !Number.isSafeInteger(limit) || (limit as number) < 1 || (limit as number) > 10 ||
    !["all_matches", "top_n"].includes(String(selectionMode))
  ) return null;
  const field = (value as Record<string, unknown>).field;
  const direction = (value as Record<string, unknown>).direction;
  if (
    !["relevance", "name", "stock", "minimum_stock", "price"].includes(String(field)) ||
    !["asc", "desc"].includes(String(direction)) ||
    (field === "relevance" && direction !== "desc")
  ) return null;
  const labels: Readonly<Record<string, Readonly<Record<string, string>>>> = {
    name: { asc: "Nombre A–Z", desc: "Nombre Z–A" },
    stock: { asc: "Menor stock", desc: "Mayor stock" },
    minimum_stock: { asc: "Menor stock mínimo", desc: "Mayor stock mínimo" },
    price: { asc: "Menor precio", desc: "Mayor precio" },
  };
  const orderLabel = field === "relevance" ? null : labels[String(field)]?.[String(direction)];
  if (field !== "relevance" && !orderLabel) return null;
  if (selectionMode === "top_n") {
    return Object.freeze([`Top ${limit}${orderLabel ? ` · ${orderLabel}` : ""}`]);
  }
  return Object.freeze(orderLabel ? [orderLabel] : []);
}

function inventoryOperationalFilterChips(value: unknown): readonly string[] | null {
  if (!Array.isArray(value) || value.length > 6) return null;
  const labels: Readonly<Record<string, string>> = {
    stock: "Stock",
    minimum_stock: "Stock mínimo",
    price: "Precio",
  };
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
      typeof field !== "string" || labels[field] === undefined || fields.has(field) ||
      typeof operator !== "string" ||
      !["eq", "neq", "lt", "lte", "gt", "gte", "between", "in"].includes(operator) ||
      !Array.isArray(values) || values.length < 1 || values.length > 10 ||
      values.some((filterValue) => typeof filterValue !== "number" || !Number.isFinite(filterValue))
    ) return null;
    fields.add(field);
    chips.push(`${labels[field]} ${inventoryPredicateLabel(operator, values.map(String))}`);
  }
  return Object.freeze(chips.slice(0, 3));
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
  const filter = cards[0].chips.join(" · ") || inventoryAvailabilityLabel(listRef.availability);
  const subject = listRef.spokenSubject;
  if (listRef.resultCount === 0) {
    return supportsResultLists
      ? `No encontré resultados para “${subject}” con el filtro “${filter}”. Abrí Inventario para que puedas revisarlo o ajustarlo.`
      : `No encontré resultados para “${subject}” con el filtro “${filter}”. Usa la tarjeta para revisar o ajustar la búsqueda en Inventario.`;
  }
  const count = listRef.hasMore
    ? `${listRef.resultCount} o más resultados`
    : `${listRef.resultCount} ${listRef.resultCount === 1 ? "resultado" : "resultados"}`;
  const agreement = !listRef.hasMore && listRef.resultCount === 1 ? "coincidente" : "coincidentes";
  return supportsResultLists
    ? `Abrí ${count} ${agreement} para “${subject}” en Inventario con el filtro “${filter}”.`
    : `Encontré ${count} ${agreement} para “${subject}” en Inventario con el filtro “${filter}”. Usa la tarjeta para abrirlos.`;
}

/** Keeps rolling client updates compatible with the strict v1 card decoder. */
/// `spokenSubject` es del servidor y no viaja.
///
/// Sirve para redactar la frase final, que el servidor arma antes de proyectar.
/// El cliente no lo usa para nada, y su decodificador exige claves EXACTAS en
/// `listRef`: mandarlo haría que las apps ya instaladas —macOS 1.0.3 y Android
/// 1.0.3+45, publicadas el 2026-08-22— rechazaran toda tarjeta de lista de
/// inventario. Un campo interno se queda adentro.
function withoutServerOnlyListFields(
  cards: readonly AgentActionCard[],
): readonly AgentActionCard[] {
  if (!cards.some((item) => item.listRef)) return cards;
  return Object.freeze(cards.map((item) => {
    if (!item.listRef) return item;
    const { spokenSubject: _serverOnly, ...wire } = item.listRef;
    return Object.freeze({ ...item, listRef: Object.freeze(wire) }) as AgentActionCard;
  }));
}

export function cardsForClient(
  rawCards: readonly AgentActionCard[],
  supportsResultLists: boolean,
  supportsStructuredClarifications = false,
): readonly AgentActionCard[] {
  // El embudo único hacia el cliente: aplicarlo acá cubre los diez lugares que
  // proyectan tarjetas, en vez de diez parches que se desincronizan.
  const cards = withoutServerOnlyListFields(dropSearchScaffolding(rawCards));
  if (
    (supportsResultLists || !cards.some((item) => item.listRef)) &&
    (supportsStructuredClarifications ||
      !cards.some((item) => item.supplyNeedDraft))
  ) return cards;
  return Object.freeze(cards.map((item) => {
    const withoutList = supportsResultLists || !item.listRef ? item : (() => {
      const { listRef: _unsupportedListRef, ...compatible } = item;
      return compatible;
    })();
    if (supportsStructuredClarifications || !withoutList.supplyNeedDraft) {
      return card(withoutList);
    }
    const compatible = {
      ...withoutList,
      supplyNeedDraft: Object.freeze({
        ...withoutList.supplyNeedDraft,
        lines: Object.freeze(withoutList.supplyNeedDraft.lines.map((line) => {
          const { clarificationPrompts: _unsupportedPrompts, ...compatibleLine } = line;
          return Object.freeze(compatibleLine);
        })),
      }),
    };
    // The wire shape intentionally matches the strict v1 client and therefore
    // omits a field required by the server's normalized v2 type.
    return Object.freeze(compatible) as unknown as AgentActionCard;
  }));
}

/// Cómo se le nombra al operador la lista que está viendo.
///
/// Manda su propia frase, porque ahí vive la identidad: «Shimano» no es ruido
/// y la categoría «Piñones» no lo dice. La excepción es cuando la frase no
/// agrega nada sobre la categoría resuelta —«camara 29» dentro de «Cámaras»—:
/// repetirla rotula la lista con lo que él tipeó en vez de con lo que el
/// asistente entendió, y un malentendido se esconde justo ahí.
function spokenListSubject(
  identityQuery: string | null,
  category: string | null | undefined,
): string {
  if (!identityQuery) return category ?? "Inventario";
  if (!category) return identityQuery;
  const normalizada = plainWords(category);
  const cubierta = plainWords(identityQuery)
    .split(" ")
    .filter((token) => /[a-z]/.test(token))
    .every((token) => normalizada.includes(token) || token.length < 3);
  return cubierta ? category : identityQuery;
}

function plainWords(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
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

function inventoryRiskCards(
  result: AgentToolResultEnvelope,
): readonly AgentActionCard[] {
  const items = result.items;
  if (items.length === 0) return [];
  const outOfStock = items.filter((item) => item.risk === "out_of_stock").length;
  const lowStock = items.filter((item) => item.risk === "low_stock").length;
  // El total, no la página. La tarjeta decía «10 productos detectados» cuando
  // el conjunto real eran 1.016: exacto sobre lo mostrado y falso como
  // resumen, que es justo para lo que sirve un subtítulo.
  const total = Math.max(result.totalMatches, items.length);
  const subtitle = total > items.length
    ? `${items.length} de ${total.toLocaleString("es-CL")} productos en riesgo`
    : `${total} ${total === 1 ? "producto en riesgo" : "productos en riesgo"}`;
  // La demanda es lo que convierte la lista en una decisión: sin ella el
  // operador no sabe cuáles de los 1.016 le duelen.
  const withDemand = items.filter((item) =>
    typeof item.soldRecently === "number" && item.soldRecently > 0
  ).length;
  const supplierNames = [
    ...new Set(
      items
        .map((item) => typeof item.supplierName === "string" ? item.supplierName : "")
        .filter((name) => name.length > 0),
    ),
  ];
  return [card({
    kind: "inventory",
    eyebrow: "Inventario",
    title: "Reponer lo que se está acabando",
    subtitle,
    description: total > items.length
      ? "Se muestran primero los que más se movieron en los últimos 90 días."
      : "Abre el inventario para revisar existencias y mínimos configurados.",
    destination: "inventory_products",
    chips: compact([
      outOfStock ? `${outOfStock} agotado${outOfStock === 1 ? "" : "s"}` : undefined,
      lowStock ? `${lowStock} con stock bajo` : undefined,
      withDemand ? `${withDemand} con venta reciente` : undefined,
    ]),
    // El paso siguiente vive donde termina la respuesta. El `id` viene de un
    // catálogo cerrado que el cliente conoce: el servidor elige CUÁL
    // continuación ofrecer, nunca redacta el texto que se enviará como
    // mensaje del operador.
    optionKind: "follow_up",
    options: ([
      supplierNames.length > 0
        ? {
          id: "restock_by_supplier",
          label: "Agrupar el pedido por proveedor",
          description: supplierNames.length === 1
            ? `Ordena qué pedirle a ${supplierNames[0]}.`
            : `Ordena qué pedirle a ${supplierNames.length} proveedores.`,
        }
        : undefined,
      withDemand > 0
        ? {
          id: "restock_only_moving",
          label: "Sólo lo que se vendió",
          description: "Deja fuera el catálogo que no rotó en 90 días.",
        }
        : undefined,
    ] as readonly (AgentCardOption | undefined)[]).filter(
      (option): option is AgentCardOption => option !== undefined,
    ),
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
        expenseStatusLabel(optionalText(item, "postingStatus")),
        expenseStatusLabel(optionalText(item, "paymentStatus")),
        approvalStatusLabel(optionalText(item, "approvalStatus")),
      ]),
      entityRef: entityRef(item, "expense"),
    })
  );
}

function receivableCards(items: readonly JsonObject[]): readonly AgentActionCard[] {
  return items.map((item, index) =>
    card({
      kind: "sales_invoice",
      eyebrow: "Cuenta por cobrar",
      title: text(item, "invoiceNumber", "Factura"),
      subtitle: optionalText(item, "dueDate"),
      description: money(item.balance, "Saldo"),
      destination: "sales_invoices",
      chips: compact([receivableTimingLabel(optionalText(item, "timing"))]),
      entityRef: entityRef(item, "salesInvoice"),
      // El paso siguiente sólo cuelga de la primera: repetir las mismas dos
      // opciones en cada factura convierte la respuesta en un muro de botones.
      ...(index === 0
        ? {
          optionKind: "follow_up",
          options: [
            {
              id: "collections_priority",
              label: "¿A quién le cobro primero?",
              description: "Ordena lo vencido por monto y antigüedad.",
            },
            {
              id: "collections_contact",
              label: "Contactar al que más debe",
              description: "Prepara el mensaje, sin enviarlo.",
            },
          ] as readonly AgentCardOption[],
        }
        : {}),
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
        counterpartyLabel(optionalText(item, "contextType")),
        // Una marca ISO completa no es una fecha para leer.
        dueDateLabel(optionalText(item, "lastMessageAt"))?.replace(
          "Vence ",
          "Último mensaje ",
        ),
      ]),
      description: item.needsReply === true ? "Requiere respuesta" : undefined,
      destination: "conversations",
      chips: compact([
        conversationStatusLabel(optionalText(item, "status")),
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

/// Cuando el turno terminó proponiendo una acción, las listas de búsqueda que
/// hicieron falta para llegar ahí son andamiaje, no respuesta.
///
/// Al pedir «agrega una revisión de frenos al trabajo PG-00521» el asistente
/// buscó tres veces en el catálogo hasta dar con «Regulación de frenos», y esas
/// tres búsquedas aparecían como tarjetas —«Sin resultados», «10+ resultados»,
/// «10+ resultados»— empujando la propuesta real fuera de la vista. El operador
/// no pidió buscar: pidió agregar.
function dropSearchScaffolding(
  cards: readonly AgentActionCard[],
): readonly AgentActionCard[] {
  if (!cards.some((item) => item.approvalRef)) return cards;
  const limpio = cards.filter((item) => !item.listRef || item.approvalRef);
  // Si al sacar el andamiaje no queda nada más que la propuesta, igual está
  // bien: la propuesta ES la respuesta.
  return limpio.length > 0 ? Object.freeze(limpio) : cards;
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
    : item.supplyNeedDraft
    ? `supply\u0000${item.supplyNeedDraft.lines.map((line) => line.lineRef).join("\u0000")}`
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
      "supplyNeedDraft",
      "options",
      "optionKind",
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
    const supplyNeedDraftValue = validateSupplyNeedDraft(
      item.supplyNeedDraft,
      item.kind,
      closedDestination,
      entityRefValue,
      approvalRefValue,
    );
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
      supplyNeedDraft: supplyNeedDraftValue,
      // Las opciones sobreviven al viaje por el historial: sin esto la tarjeta
      // se relee sin ellas y el operador pierde los controles al recargar.
      options: validateStoredOptions(item.options),
      optionKind: optionalBounded(item.optionKind, 40),
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

/// «A quién le compramos esto». La tarjeta responde con la participación del
/// gasto y la evidencia que la sostiene, y abre la ficha del proveedor —desde
/// ahí el operador entra a su sitio con la sesión que el ERP ya guarda—.
///
/// El porcentaje nunca viaja solo: un 100% sobre tres líneas y un 57% sobre
/// diecisiete son conclusiones distintas, y quien lee la tarjeta tiene que
/// poder distinguirlas sin abrir nada.
function supplierHistoryCards(items: readonly JsonObject[]): readonly AgentActionCard[] {
  return items.slice(0, 3).map((item) => {
    const share = typeof item.spendSharePercent === "number" ? item.spendSharePercent : null;
    const lines = typeof item.purchaseLines === "number" ? item.purchaseLines : null;
    const evidence = typeof item.evidencePurchaseLines === "number"
      ? item.evidencePurchaseLines
      : null;
    const days = typeof item.daysSinceLastPurchase === "number"
      ? item.daysSinceLastPurchase
      : null;
    const cost = typeof item.averageLandedUnitCostNet === "number"
      ? item.averageLandedUnitCostNet
      : null;
    return card({
      kind: "supplier",
      eyebrow: item.scopeRelaxed === true
        ? "Le compramos algo así"
        : "Le compramos esto",
      title: text(item, "supplierName", "Proveedor"),
      subtitle: share !== null && lines !== null && evidence !== null
        ? `${formatShare(share)} de lo comprado · ${lines} de ${evidence} líneas`
        : undefined,
      // Cuando el servidor tuvo que ensanchar la pregunta, la tarjeta lo dice.
      // Presentar como literal un resultado que se ensanchó es la forma más
      // silenciosa de mentir.
      description: join([
        cost !== null ? money(cost, "Costo unitario promedio") : undefined,
        daysSinceLabel(days),
        optionalText(item, "brands"),
        optionalText(item, "gamaMix"),
        widenedLabel(item),
      ]),
      destination: "suppliers",
      chips: compact([
        item.hasPortalAccount === true ? "Con cuenta en su portal" : undefined,
        optionalText(item, "supplierCity"),
      ]),
      entityRef: entityRef(item, "supplier"),
    });
  });
}

/// **La lista entera, y con quién se cierra.**
///
/// La pregunta del taller ante una lista no es «quién tiene rayos»: es «¿le
/// pido todo a uno, o lo reparto?». La tarjeta de rango 1 lleva esa decisión ya
/// tomada —qué cubre, qué le falta y quién completa lo que falta—, porque
/// dejársela al lector significa que la tome mal.
function basketSupplierCards(items: readonly JsonObject[]): readonly AgentActionCard[] {
  return items.slice(0, 3).map((item) => {
    const covered = typeof item.coveredNeeds === "number" ? item.coveredNeeds : null;
    const total = typeof item.totalNeeds === "number" ? item.totalNeeds : null;
    const days = typeof item.daysSinceLastPurchase === "number"
      ? item.daysSinceLastPurchase
      : null;
    const missing = optionalText(item, "missingList");
    const complement = optionalText(item, "complementSupplierName");
    return card({
      kind: "supplier",
      eyebrow: covered !== null && total !== null && covered === total
        ? "Cubre toda la lista"
        : "Cubre parte de la lista",
      title: text(item, "supplierName", "Proveedor"),
      subtitle: covered !== null && total !== null
        ? `${covered} de ${total} ${total === 1 ? "línea" : "líneas"}: ${
          text(item, "coveredList", "—")
        }`
        : undefined,
      description: join([
        // El reparto se dice completo o no se dice: «le falta X» sin decir a
        // quién pedírselo deja al operador con el problema, no con la salida.
        missing && complement
          ? `Le falta ${missing} — eso se lo compramos a ${complement}`
          : missing
          ? `Le falta ${missing}, y no hay historial de eso con nadie más`
          : undefined,
        daysSinceLabel(days),
        optionalText(item, "brands"),
      ]),
      destination: "suppliers",
      chips: compact([
        item.hasPortalAccount === true ? "Con cuenta en su portal" : undefined,
        optionalText(item, "supplierCity"),
      ]),
      entityRef: entityRef(item, "supplier"),
    });
  });
}

/// Qué se soltó para poder contestar, dicho en la tarjeta.
///
/// El servidor baja escalones cuando la frase no calza literalmente: suelta las
/// palabras que no aparecen en ningún producto, la medida que esa rama no tiene
/// poblada, o la exigencia de que estén todas las palabras. Un resultado
/// ensanchado que se presenta como literal es exacto por dentro y engañoso como
/// respuesta.
function widenedLabel(item: JsonObject): string | undefined {
  if (item.scopeRelaxed !== true) return undefined;
  const words = optionalText(item, "droppedWords");
  if (words) return `Sin «${words}»: no aparece en ningún producto`;
  const filters = optionalText(item, "droppedFilters");
  if (filters) return `Búsqueda ampliada: se soltó ${filters}`;
  return "Búsqueda ampliada";
}

/// «hace 4 meses», no «138». El operador decide con la distancia, no con el
/// entero.
function daysSinceLabel(days: number | null): string | undefined {
  if (days === null || days < 0) return undefined;
  if (days === 0) return "Última compra hoy";
  if (days === 1) return "Última compra ayer";
  if (days < 30) return `Última compra hace ${days} días`;
  const months = Math.round(days / 30);
  if (months < 12) {
    return `Última compra hace ${months} ${months === 1 ? "mes" : "meses"}`;
  }
  const years = Math.round(days / 365);
  return `Última compra hace ${years} ${years === 1 ? "año" : "años"}`;
}

function formatShare(share: number): string {
  return `${share.toFixed(share >= 10 ? 0 : 1).replace(".", ",")}%`;
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
      chips: compact([invoiceStatusLabel(optionalText(item, "status"))]),
      entityRef: entityRef(item, purchase ? "purchaseInvoice" : "salesInvoice"),
    })
  );
}

/// «Vence mañana a las 18:00» en vez de una marca de tiempo ISO. La fecha se
/// interpreta en la zona que trae la propia marca —la del taller—, nunca en
/// UTC: un desfase de cuatro horas cambia el día que lee el operador.
function dueDateLabel(value: string | undefined): string | undefined {
  if (!value) return undefined;
  const match = value.match(
    /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/u,
  );
  if (!match) return undefined;
  const [, year, month, day, hour, minute] = match;
  const fecha = `${Number(day)}-${Number(month)}-${year}`;
  return `Vence ${fecha} a las ${hour}:${minute}`;
}

function taskPriorityLabel(value: string | undefined): string | undefined {
  switch (value) {
    case "low":
    case "baja":
      return "Prioridad baja";
    case "normal":
    case "media":
      return "Prioridad normal";
    case "high":
    case "alta":
      return "Prioridad alta";
    case "urgent":
    case "urgente":
      return "Urgente";
    default:
      return undefined;
  }
}

function preparedTaskCard(item: JsonObject): AgentActionCard {
  return card({
    kind: "task_preview",
    eyebrow: "Tarea por confirmar",
    title: text(item, "title", "Tarea"),
    subtitle: join([
      optionalText(item, "assigneeName"),
      // `2026-08-23T18:00:00-04:00` es una clave, no una fecha para leer.
      dueDateLabel(optionalText(item, "dueAt")),
    ]),
    description: optionalText(item, "description"),
    destination: "tasks",
    chips: compact([
      taskPriorityLabel(optionalText(item, "priority")),
      "Requiere confirmación",
    ]),
    approvalRef: approvalRef(item),
  });
}

function preparedDiagnosisCard(item: JsonObject): AgentActionCard {
  const previousValue = optionalText(item, "previousValue");
  return card({
    kind: "diagnosis_preview",
    eyebrow: "Diagnóstico por confirmar",
    title: text(item, "fieldLabel", "Cambio de diagnóstico"),
    subtitle: join([optionalText(item, "jobNumber"), optionalText(item, "bikeLabel")]),
    description: join([
      previousValue === undefined ? "Sin valor anterior" : `Antes: ${previousValue}`,
      `Nuevo: ${text(item, "newValue", "")}`,
    ]),
    destination: "workshop_jobs",
    chips: ["Requiere confirmación"],
    approvalRef: approvalRef(item, "diagnosis_preview"),
  });
}

/// Los estados y prioridades del taller viajan en MAYÚSCULA con guiones bajos
/// porque son claves: `ESPERANDO_REPUESTOS`, `EN_CURSO`, `NORMAL`. En un chip
/// se leen como si el sistema estuviera gritando una constante interna. La
/// clave sigue siendo la clave; lo que cambia es lo que se muestra.
function workshopStatusLabel(value: string | undefined): string | undefined {
  switch (value) {
    case "PENDIENTE":
      return "Pendiente";
    case "DIAGNOSTICO":
      return "Diagnóstico";
    case "EN_CURSO":
      return "En curso";
    case "EN_PAUSA":
      return "En pausa";
    case "ESPERANDO_REPUESTOS":
      return "Esperando repuestos";
    case "FINALIZADO":
      return "Finalizado";
    case "ENTREGADO":
      return "Entregado";
    case "RETIRO_SIN_SERVICIO":
      return "Retiro sin servicio";
    case "CANCELADO":
      return "Cancelado";
    case "REPUESTOS":
      return "Esperando repuestos";
    default:
      // Un estado que este código no conoce igual deja de gritar. Enumerar
      // sirve para decirlo bien —«Esperando repuestos», no «Esperando
      // repuestos» literal de la clave—, pero el respaldo evita que una
      // constante nueva aparezca mañana como `RETIRO_SIN_SERVICIO` en un chip.
      return sentenceCaseConstant(value);
  }
}

/// `ESPERANDO_REPUESTOS` → `Esperando repuestos`. Sólo actúa sobre lo que
/// evidentemente es una clave: mayúsculas, dígitos y guiones bajos.
function sentenceCaseConstant(value: string | undefined): string | undefined {
  if (!value || !/^[A-Z][A-Z0-9_]*$/.test(value)) return value;
  const palabras = value.toLowerCase().replace(/_/g, " ");
  return palabras.charAt(0).toUpperCase() + palabras.slice(1);
}

function workshopPriorityLabel(value: string | undefined): string | undefined {
  switch (value) {
    case "NORMAL":
      // La prioridad corriente no merece un chip: ocupa lugar y no distingue
      // nada. Sólo se muestra lo que se sale de lo normal.
      return undefined;
    case "ALTA":
      return "Prioridad alta";
    case "URGENTE":
      return "Urgente";
    default:
      return sentenceCaseConstant(value);
  }
}

/// Estados de gasto y de conversación. Mismo criterio que el resto: la clave
/// se queda en la base, el chip habla castellano, y lo que este código no
/// conoce deja de gritar en vez de mostrarse crudo.
function expenseStatusLabel(value: string | undefined): string | undefined {
  switch (value) {
    case "draft":
      return "Borrador";
    case "posted":
      return "Contabilizado";
    case "void":
      return "Anulado";
    case "scheduled":
      return "Pago programado";
    case "partial":
      return "Pago parcial";
    case "paid":
      return "Pagado";
    case "approved":
      return "Aprobado";
    case "rejected":
      return "Rechazado";
    default:
      return sentenceCaseConstant(value);
  }
}

/// La aprobación tiene su propio «pending», y no es el del pago. Mezclarlos
/// ponía «Pagado» y «Pendiente de pago» en el mismo gasto: dos chips que se
/// contradicen y hacen dudar del dato correcto.
function approvalStatusLabel(value: string | undefined): string | undefined {
  switch (value) {
    case "pending":
      return "Pendiente de aprobación";
    case "approved":
      // Un gasto aprobado es lo corriente: el chip no distingue nada.
      return undefined;
    case "rejected":
      return "Aprobación rechazada";
    default:
      return sentenceCaseConstant(value);
  }
}

function counterpartyLabel(value: string | undefined): string | undefined {
  switch (value) {
    case "customer":
      return "Cliente";
    case "supplier":
      return "Proveedor";
    case "internal":
      return "Interna";
    default:
      return sentenceCaseConstant(value);
  }
}

function conversationStatusLabel(value: string | undefined): string | undefined {
  switch (value) {
    case "active":
      // Una conversación activa es lo corriente: el chip no distingue nada.
      return undefined;
    case "archived":
      return "Archivada";
    case "rejected":
      return "Rechazada";
    case "blocked":
      return "Bloqueada";
    default:
      return sentenceCaseConstant(value);
  }
}

/// Las tareas tienen su propio vocabulario, en minúscula y en inglés
/// (`pending`, `completed`, `normal`), distinto del taller
/// (`EN_CURSO`, `NORMAL`). Reusar el del taller dejaba `pending` y `normal`
/// crudos en la tarjeta.
function taskStatusLabel(value: string | undefined): string | undefined {
  switch (value) {
    case "pending":
      return "Pendiente";
    case "in_progress":
      return "En curso";
    case "completed":
      // Una tarea completada rara vez necesita el chip: si aparece en una
      // lista de pendientes, el estado ya lo dice el encabezado.
      return "Completada";
    case "cancelled":
      return "Cancelada";
    default:
      return sentenceCaseConstant(value);
  }
}

function taskPriorityChip(value: string | undefined): string | undefined {
  switch (value) {
    case "normal":
      // Lo corriente no distingue nada y ocupa lugar.
      return undefined;
    case "low":
      return "Prioridad baja";
    case "high":
      return "Prioridad alta";
    case "urgent":
      return "Urgente";
    default:
      return sentenceCaseConstant(value);
  }
}

function workshopItemTypeLabel(value: string | undefined): string | undefined {
  switch (value) {
    case "service":
    case "servicio":
      return "Servicio";
    case "product":
    case "producto":
      return "Producto";
    default:
      return undefined;
  }
}

function preparedWorkshopItemCard(item: JsonObject): AgentActionCard {
  return card({
    kind: "workshop_item_preview",
    eyebrow: "Línea por confirmar",
    title: text(item, "itemName", "Producto o servicio"),
    subtitle: join([
      optionalText(item, "jobNumber"),
      optionalText(item, "bikeLabel"),
      optionalText(item, "invoiceNumber"),
    ]),
    description: join([
      numericText(item, "quantity", "Cantidad"),
      money(item.lineTotal, "Total línea"),
    ]),
    destination: "workshop_jobs",
    chips: compact([
      workshopItemTypeLabel(optionalText(item, "itemType")),
      "Requiere confirmación",
    ]),
    approvalRef: approvalRef(item, "workshop_item_preview"),
  });
}

function preparedSupplyRequestCards(
  items: readonly JsonObject[],
): readonly AgentActionCard[] {
  if (items.length < 1 || items.length > 8) {
    throw new Error("Invalid supply request draft");
  }
  const profile = items[0].profile;
  if (
    typeof profile !== "string" ||
    !["balanced", "profitability", "urgent_local"].includes(profile) ||
    items.some((item) => item.profile !== profile)
  ) throw new Error("Invalid supply request draft");

  const lines = items.map((item) => ({
    lineRef: item.lineRef,
    description: item.description,
    productId: item.entityId,
    productName: item.productName,
    productSku: item.productSku,
    identityState: item.identityState,
    // Procedencia de categoría: la tarjeta es cerrada y viaja al cliente, que
    // la devuelve intacta al comando durable. El modelo no la ve.
    categoryId: item.categoryId ?? null,
    categoryPath: item.categoryPath ?? null,
    technicalFamily: item.technicalFamily ?? null,
    quantity: item.quantity,
    unit: item.unit,
    technicalPredicates: item.technicalPredicates,
    preference: item.preference,
    clarification: item.clarification,
    clarificationRequired: item.clarificationRequired,
    clarificationPrompts: item.clarificationPrompts ?? [],
  }));
  const confirmed = items.filter((item) => item.identityState === "confirmed").length;
  const pending = items.length - confirmed;
  const questions = items.filter((item) => item.clarificationRequired === true).length;
  const profileLabel = profile === "profitability"
    ? "Rentabilidad"
    : profile === "urgent_local"
    ? "Urgencia local"
    : "Equilibrio";
  const draft = validateSupplyNeedDraft(
    { profile, lines },
    "supply_need_draft",
    "purchases",
    undefined,
    undefined,
  );
  return [card({
    kind: "supply_need_draft",
    eyebrow: "Petición estructurada",
    title: items.length === 1
      ? "1 necesidad para revisar"
      : `${items.length} necesidades para revisar`,
    description: pending === 0
      ? "Cada línea quedó vinculada a un producto exacto. Revisa antes de guardar."
      : "Las líneas pendientes conservan el texto y no se presentan como compatibilidad confirmada.",
    destination: "purchases",
    chips: compact([
      profileLabel,
      confirmed ? `${confirmed} vinculada${confirmed === 1 ? "" : "s"}` : undefined,
      pending ? `${pending} por precisar` : undefined,
      questions ? `${questions} aclaración${questions === 1 ? "" : "es"}` : undefined,
    ]),
    supplyNeedDraft: draft,
  })];
}

export function committedTaskCard(item: JsonObject): AgentActionCard {
  return card({
    kind: "task",
    eyebrow: "Tarea creada",
    title: text(item, "title", "Tarea"),
    subtitle: join([
      optionalText(item, "assigneeName"),
      // La tarjeta de «tarea creada» mostraba la marca ISO cruda mientras la
      // propuesta —la de al lado, un segundo antes— ya decía «Vence 24-8-2026
      // a las 10:00». La misma tarea, dos formatos.
      dueDateLabel(optionalText(item, "dueAt")),
    ]),
    description: optionalText(item, "description"),
    destination: "tasks",
    chips: compact([
      taskStatusLabel(optionalText(item, "status")),
      taskPriorityChip(optionalText(item, "priority")),
    ]),
  });
}

export function committedWorkshopActionCard(
  action: "update_diagnosis" | "add_workshop_item",
  item: JsonObject,
): AgentActionCard {
  return card({
    kind: "job",
    eyebrow: action === "update_diagnosis" ? "Diagnóstico actualizado" : "Línea agregada",
    title: text(item, "jobNumber", "Trabajo"),
    subtitle: optionalText(item, "bikeLabel"),
    description: action === "update_diagnosis"
      ? join([optionalText(item, "fieldLabel"), optionalText(item, "newValue")])
      : join([optionalText(item, "itemName"), money(item.lineTotal, "Total línea")]),
    destination: "workshop_jobs",
    chips: compact([optionalText(item, "invoiceNumber")]),
    entityRef: entityRef(item, "workshopJob"),
  });
}

/// El estado de una factura no está normalizado en los datos: conviven `sent`
/// y `enviado` en la misma columna. Traducir en la tarjeta además de castellanizar
/// **unifica**, y así dos facturas en el mismo estado dejan de verse distintas.
/// Un valor que no está en esta lista se omite en vez de mostrarse crudo.
function invoiceStatusLabel(value: string | undefined): string | undefined {
  switch (value) {
    case "draft":
    case "borrador":
      return "Borrador";
    case "sent":
    case "enviado":
      return "Enviada";
    case "confirmed":
      return "Confirmada";
    case "issued":
      return "Emitida";
    case "paid":
    case "pagada":
      return "Pagada";
    case "partial":
      return "Pago parcial";
    case "overdue":
      return "Vencida";
    case "cancelled":
    case "canceled":
    case "anulada":
      return "Anulada";
    default:
      return undefined;
  }
}

/// Los estados de la base viajan en inglés porque son claves, no texto. Un
/// chip que dice «overdue» dentro de una respuesta en español se lee como una
/// falla del sistema; el taller necesita «Vencida».
function receivableTimingLabel(value: string | undefined): string | undefined {
  switch (value) {
    case "overdue":
      return "Vencida";
    case "due_today":
      return "Vence hoy";
    case "due_in_horizon":
      return "Por vencer";
    case "later":
      return "Más adelante";
    case "undated":
      return "Sin fecha de vencimiento";
    default:
      return undefined;
  }
}

function salesBasisLabel(value: string | undefined): string | undefined {
  switch (value) {
    case "issued":
      return "Por lo emitido";
    case "collected":
      return "Por lo cobrado";
    default:
      // Un criterio que este código no conoce no se traduce a la fuerza ni se
      // muestra crudo: se omite, y el resto de la tarjeta sigue siendo cierto.
      return undefined;
  }
}

function salesPeriodCards(items: readonly JsonObject[]): readonly AgentActionCard[] {
  const summary = items[0];
  if (!summary || typeof summary.highestInvoiceId !== "string") return [];
  return [card({
    kind: "sales_invoice",
    eyebrow: "Factura principal del período",
    title: text(summary, "highestInvoiceNumber", "Factura"),
    subtitle: optionalText(summary, "highestInvoiceCustomerName"),
    description: join([
      money(summary.highestInvoiceTotal, "Total factura"),
      money(summary.highestPeriodAmount, "Monto del período"),
    ]),
    destination: "sales_invoices",
    // `basis` es el criterio del período —«issued» o «collected»— y viajaba
    // crudo hasta el chip. El taller lee en castellano; una etiqueta en inglés
    // dentro de una respuesta en español se lee como un error del sistema, no
    // como información.
    chips: compact([salesBasisLabel(optionalText(summary, "basis"))]),
    entityRef: {
      kind: "salesInvoice",
      id: summary.highestInvoiceId.toLowerCase(),
    },
    optionKind: "follow_up",
    options: [
      {
        id: "sales_top_customers",
        label: "¿Quién me compró más?",
        description: "Ordena el período por cliente.",
      },
      {
        id: "sales_compare_previous",
        label: "Comparar con el período anterior",
        description: "Mismo cálculo sobre el tramo previo.",
      },
    ] as readonly AgentCardOption[],
  })];
}

function card(value: AgentActionCard): AgentActionCard {
  const eyebrow = optionalProjectedText(value.eyebrow, 80);
  const subtitle = optionalProjectedText(value.subtitle, 240);
  const description = optionalProjectedText(value.description, 500);
  const supplyNeedDraft = validateSupplyNeedDraft(
    value.supplyNeedDraft,
    value.kind,
    value.destination,
    value.entityRef,
    value.approvalRef,
  );
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
    ...(supplyNeedDraft ? { supplyNeedDraft } : {}),
    ...(value.optionKind
      ? { optionKind: projectedText(value.optionKind, 40, true) }
      : {}),
    ...(value.options && value.options.length > 0
      ? {
        options: Object.freeze(value.options.slice(0, 6).map((option) =>
          Object.freeze({
            id: projectedText(option.id, 64, true),
            label: projectedText(option.label, 80, true),
            ...(option.description
              ? { description: projectedText(option.description, 200, true) }
              : {}),
          })
        )),
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

function approvalRef(item: JsonObject, cardKind = "task_preview"): AgentApprovalRef {
  return validateApprovalRef({
    id: item.approvalId,
    action: item.action,
    state: item.state,
    expiresAt: item.expiresAt,
  }, cardKind)!;
}

function validateApprovalRef(
  value: unknown,
  cardKind: unknown,
): AgentActionCard["approvalRef"] {
  const expectedAction = cardKind === "task_preview"
    ? "create_task"
    : cardKind === "diagnosis_preview"
    ? "update_diagnosis"
    : cardKind === "workshop_item_preview"
    ? "add_workshop_item"
    : null;
  if (value === undefined) {
    if (expectedAction !== null) throw new Error("Missing approval reference");
    return undefined;
  }
  if (
    expectedAction === null || !isRecord(value) ||
    !hasExactKeys(value, ["id", "action", "state", "expiresAt"]) ||
    typeof value.id !== "string" || !validUuid(value.id) ||
    value.action !== expectedAction ||
    typeof value.state !== "string" ||
    !(agentApprovalStates as readonly string[]).includes(value.state) ||
    typeof value.expiresAt !== "string" || !isoInstant(value.expiresAt)
  ) throw new Error("Invalid approval reference");
  return Object.freeze({
    id: value.id.toLowerCase(),
    action: expectedAction,
    state: value.state as AgentApprovalRef["state"],
    expiresAt: value.expiresAt,
  });
}

function validateSupplyNeedDraft(
  value: unknown,
  cardKind: unknown,
  destination: AgentActionCard["destination"],
  entityRefValue: AgentActionCard["entityRef"],
  approvalRefValue: AgentActionCard["approvalRef"],
): AgentActionCard["supplyNeedDraft"] {
  if (value === undefined) {
    if (cardKind === "supply_need_draft") {
      throw new Error("Missing supply need draft");
    }
    return undefined;
  }
  if (
    cardKind !== "supply_need_draft" || destination !== "purchases" ||
    entityRefValue !== undefined || approvalRefValue !== undefined ||
    !isRecord(value) || !hasExactKeys(value, ["profile", "lines"]) ||
    typeof value.profile !== "string" ||
    !["balanced", "profitability", "urgent_local"].includes(value.profile) ||
    !Array.isArray(value.lines) || value.lines.length < 1 || value.lines.length > 8
  ) throw new Error("Invalid supply need draft");

  const lineReferences = new Set<string>();
  const lines = value.lines.map((line) => {
    const baseFields = [
      "lineRef",
      "description",
      "productId",
      "productName",
      "productSku",
      "identityState",
      "categoryId",
      "categoryPath",
      "technicalFamily",
      "quantity",
      "unit",
      "technicalPredicates",
      "preference",
      "clarification",
      "clarificationRequired",
    ] as const;
    if (
      !isRecord(line) ||
      (!hasExactKeys(line, baseFields) &&
        !hasExactKeys(line, [...baseFields, "clarificationPrompts"])) ||
      typeof line.lineRef !== "string" || !/^line-[1-8]$/.test(line.lineRef) ||
      lineReferences.has(line.lineRef) ||
      !(line.productId === null ||
        (typeof line.productId === "string" && validUuid(line.productId))) ||
      !(line.productName === null || typeof line.productName === "string") ||
      !(line.productSku === null || typeof line.productSku === "string") ||
      !(line.categoryId === null ||
        (typeof line.categoryId === "string" && validUuid(line.categoryId))) ||
      !(line.categoryPath === null || typeof line.categoryPath === "string") ||
      !(line.technicalFamily === null ||
        typeof line.technicalFamily === "string") ||
      // Sin categoría no hay ruta ni familia: una glosa sin identidad detrás
      // sería una afirmación que nada respalda.
      (line.categoryId === null &&
        (line.categoryPath !== null || line.technicalFamily !== null)) ||
      !["unresolved", "confirmed"].includes(String(line.identityState)) ||
      typeof line.quantity !== "number" || !Number.isFinite(line.quantity) ||
      line.quantity < 0.001 || line.quantity > 999999 ||
      typeof line.clarificationRequired !== "boolean" ||
      !Array.isArray(line.technicalPredicates) || line.technicalPredicates.length > 8 ||
      !(line.preference === null || typeof line.preference === "string") ||
      !(line.clarification === null || typeof line.clarification === "string")
    ) throw new Error("Invalid supply need draft line");

    const description = bounded(line.description, 2000, true);
    const unit = bounded(line.unit, 32, true);
    const productName = line.productName === null ? null : bounded(line.productName, 500, true);
    const productSku = line.productSku === null ? null : bounded(line.productSku, 160, true);
    const preference = line.preference === null ? null : bounded(line.preference, 240, true);
    const clarification = line.clarification === null
      ? null
      : bounded(line.clarification, 500, true);
    const clarificationPrompts = validateSupplyNeedClarificationPrompts(
      line.clarificationPrompts ?? [],
      line.clarificationRequired,
    );
    const productId = typeof line.productId === "string" ? line.productId.toLowerCase() : null;
    if (
      (productId === null &&
        (line.identityState !== "unresolved" || productName !== null || productSku !== null)) ||
      (productId !== null &&
        (line.identityState !== "confirmed" || productName === null)) ||
      (line.clarificationRequired === true &&
        (clarification === null || productId !== null))
    ) throw new Error("Invalid supply need draft identity");

    const predicateFields = new Set<string>();
    const technicalPredicates = line.technicalPredicates.map((predicate) => {
      if (
        !isRecord(predicate) ||
        !hasExactKeys(predicate, ["field", "operator", "values"]) ||
        typeof predicate.field !== "string" ||
        !/^[a-z][a-z0-9_]{1,63}$/.test(predicate.field) ||
        predicateFields.has(predicate.field) ||
        typeof predicate.operator !== "string" ||
        !["eq", "neq", "lt", "lte", "gt", "gte", "between", "in", "contains"]
          .includes(predicate.operator) ||
        !Array.isArray(predicate.values) || predicate.values.length < 1 ||
        predicate.values.length > 10 ||
        (predicate.operator === "between" && predicate.values.length !== 2) ||
        (predicate.operator !== "between" && predicate.operator !== "in" &&
          predicate.values.length !== 1)
      ) throw new Error("Invalid supply need technical predicate");
      predicateFields.add(predicate.field);
      const values = predicate.values.map((item) => {
        if (
          !["string", "number", "boolean"].includes(typeof item) ||
          (typeof item === "number" && !Number.isFinite(item)) ||
          (typeof item === "string" &&
            new TextEncoder().encode(item).byteLength > 160)
        ) throw new Error("Invalid supply need technical value");
        return item;
      });
      return Object.freeze({
        field: predicate.field,
        operator: predicate.operator as
          | "eq"
          | "neq"
          | "lt"
          | "lte"
          | "gt"
          | "gte"
          | "between"
          | "in"
          | "contains",
        values: Object.freeze(values),
      });
    });

    lineReferences.add(line.lineRef);
    return Object.freeze({
      lineRef: line.lineRef,
      description,
      productId,
      productName,
      productSku,
      identityState: line.identityState as "unresolved" | "confirmed",
      categoryId: typeof line.categoryId === "string" ? line.categoryId.toLowerCase() : null,
      categoryPath: line.categoryPath === null ? null : bounded(line.categoryPath, 240, true),
      technicalFamily: line.technicalFamily === null
        ? null
        : bounded(line.technicalFamily, 120, true),
      quantity: line.quantity,
      unit,
      technicalPredicates: Object.freeze(technicalPredicates),
      preference,
      clarification,
      clarificationRequired: line.clarificationRequired,
      clarificationPrompts,
    });
  });

  return Object.freeze({
    profile: value.profile as "balanced" | "profitability" | "urgent_local",
    lines: Object.freeze(lines),
  });
}

function validateSupplyNeedClarificationPrompts(
  value: unknown,
  clarificationRequired: boolean,
): readonly AgentSupplyNeedClarificationPrompt[] {
  if (!Array.isArray(value) || value.length > 3) {
    throw new Error("Invalid supply need clarification prompts");
  }
  if (!clarificationRequired && value.length !== 0) {
    throw new Error("Unexpected supply need clarification prompts");
  }
  // Empty remains accepted for persisted v1 cards during the negotiated
  // rollout. Newly generated tool calls enforce at least one prompt whenever
  // clarificationRequired is true.
  const ids = new Set<string>();
  const prompts = value.map((prompt) => {
    if (
      !isRecord(prompt) ||
      !hasExactKeys(prompt, [
        "id",
        "question",
        "inputKind",
        "options",
        "unit",
        "allowUnknown",
      ]) ||
      typeof prompt.id !== "string" ||
      !/^[a-z][a-z0-9_]{1,31}$/.test(prompt.id) || ids.has(prompt.id) ||
      typeof prompt.question !== "string" ||
      !["single_choice", "text", "number"].includes(String(prompt.inputKind)) ||
      !Array.isArray(prompt.options) || prompt.options.length > 5 ||
      typeof prompt.allowUnknown !== "boolean" ||
      !(prompt.unit === null || typeof prompt.unit === "string")
    ) throw new Error("Invalid supply need clarification prompt");
    ids.add(prompt.id);
    const question = bounded(prompt.question, 320, true);
    const unit = prompt.unit === null ? null : bounded(prompt.unit, 32, true);
    const options = prompt.options.map((option) => {
      if (
        !isRecord(option) || !hasExactKeys(option, ["value", "label"]) ||
        typeof option.value !== "string" ||
        !/^[a-z0-9][a-z0-9_-]{0,63}$/.test(option.value) ||
        typeof option.label !== "string"
      ) throw new Error("Invalid supply need clarification option");
      return Object.freeze({
        value: option.value,
        label: bounded(option.label, 160, true),
      });
    });
    if (
      (prompt.inputKind === "single_choice" &&
        (options.length < 2 || unit !== null ||
          new Set(options.map((option) => option.value)).size !== options.length)) ||
      (prompt.inputKind !== "single_choice" && options.length !== 0) ||
      (prompt.inputKind !== "number" && unit !== null)
    ) throw new Error("Invalid supply need clarification prompt shape");
    return Object.freeze({
      id: prompt.id,
      question,
      inputKind: prompt.inputKind as "single_choice" | "text" | "number",
      options: Object.freeze(options),
      unit,
      allowUnknown: prompt.allowUnknown,
    });
  });
  return Object.freeze(prompts);
}

const storedListRefKeys = [
  "kind",
  "query",
  "availability",
  "resultCount",
  "hasMore",
  "entityIds",
  "autoOpen",
];

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
    // `spokenSubject` es opcional en la validación: una tarjeta guardada por
    // una versión anterior no lo trae, y rechazarla borraría el historial del
    // hilo. Al proyectar, cae de vuelta a `query`.
    !(hasExactKeys(value, storedListRefKeys) ||
      hasExactKeys(value, [...storedListRefKeys, "spokenSubject"])) ||
    value.kind !== "inventory" ||
    typeof value.query !== "string" || !value.query.trim() ||
    new TextEncoder().encode(value.query.trim()).byteLength > 240 ||
    !(value.spokenSubject === undefined ||
      (typeof value.spokenSubject === "string" && value.spokenSubject.trim() &&
        new TextEncoder().encode(value.spokenSubject.trim()).byteLength <= 240)) ||
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
    // **Las ids son obligatorias, truncado o no.** Antes se exigía lo
    // contrario —`hasMore` implicaba `entityIds === null`— y eso dejaba al
    // cliente buscando la frase como texto, que no encuentra nada: mientras
    // más acertaba la búsqueda, más vacía salía la lista. Se sigue aceptando
    // `null` al LEER, porque hay tarjetas guardadas por la versión anterior y
    // rechazarlas borraría el historial del hilo.
    entityIds === null && !value.hasMore ||
    (entityIds !== null && entityIds.length !== value.resultCount) ||
    (entityIds !== null && new Set(entityIds).size !== entityIds.length)
  ) throw new Error("Invalid list reference");
  return Object.freeze({
    kind: "inventory",
    query: value.query.trim(),
    spokenSubject: typeof value.spokenSubject === "string" && value.spokenSubject.trim()
      ? value.spokenSubject.trim()
      : value.query.trim(),
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

function numericText(item: JsonObject, key: string, prefix: string): string | undefined {
  const value = item[key];
  return typeof value === "number" && Number.isFinite(value)
    ? `${prefix} ${value.toLocaleString("es-CL", { maximumFractionDigits: 2 })}`
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


/// Las plantillas de cliente aprobadas, con su cuerpo ya resuelto. El orden es
/// el del taller: primero avisar que está lista, después una actualización, y
/// al final el seguimiento de presupuesto.
function customerTemplateOptions(
  businessName: string,
): readonly { id: string; label: string; description: string }[] {
  const labels: Record<string, string> = {
    // Va primera porque es la que abre una conversación que no existe, que es
    // el caso más común cuando la ventana está cerrada.
    seguimiento_servicio_bicicleta: "Primer contacto",
    bicicleta_lista_retiro: "Lista para retiro",
    actualizacion_servicio_bicicleta: "Actualización de taller",
    seguimiento_presupuesto_bicicleta: "Seguimiento de presupuesto",
  };
  return defaultWhatsAppTemplates
    .filter((template) => template.name in labels)
    .map((template) => ({
      id: template.name,
      label: labels[template.name],
      // El cuerpo va APROBADO por Meta y con el negocio ya puesto, pero el
      // nombre del contacto se deja como `{{1}}`: quién saluda a quién lo
      // decide `resolveWhatsAppTemplateGreetingName` en el cliente, la misma
      // función que usa el envío real. Esa regla no es «la primera palabra»
      // —conserva nombres compuestos como «José Luis»— y duplicarla aquí sería
      // garantizar que un día la revisión diga algo distinto de lo que se
      // manda. Cada lado sustituye lo que le pertenece.
      description: renderWhatsAppTemplateBody(template.body, [
        "{{1}}",
        businessName,
      ]),
    }));
}


/// Las opciones guardadas se releen con la misma forma cerrada con que se
/// escribieron: id, rótulo y la revisión que se mostrará antes de confirmar.
function validateStoredOptions(value: unknown): readonly AgentCardOption[] | undefined {
  if (value === undefined || value === null) return undefined;
  if (!Array.isArray(value) || value.length > 6) {
    throw new Error("Invalid stored card options");
  }
  return Object.freeze(value.map((item) => {
    if (
      !isRecord(item) ||
      Object.keys(item).some((key) => !["id", "label", "description"].includes(key))
    ) throw new Error("Invalid stored card options");
    return Object.freeze({
      id: bounded(item.id, 64, true),
      label: bounded(item.label, 80, true),
      ...(item.description === undefined
        ? {}
        : { description: bounded(item.description, 600, true) }),
    });
  }));
}
