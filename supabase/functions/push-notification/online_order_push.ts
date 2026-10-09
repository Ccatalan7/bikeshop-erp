/**
 * The staff phone alert for a web order (owner, 2026-10-09: the shop learns
 * at once, so no customer is left waiting). Pure rules, tested in
 * `online_order_push_test.ts`; `index.ts` reads the order and sends.
 */

export interface OnlineOrderPushRow {
  id: string;
  tenant_id: string | null;
  order_number?: string | null;
  customer_name?: string | null;
  total?: number | string | null;
  payment_method?: string | null;
  payment_status?: string | null;
  delivery_type?: string | null;
  status?: string | null;
}

/** `awaiting_payment`: confirm the transfer; `paid`: prepare the order. */
export type OnlineOrderPushEvent = "awaiting_payment" | "paid";

/**
 * What the order needs from the team right now, read from the row itself.
 * A request that arrives late (the transfer already confirmed, the order
 * cancelled) finds nothing to do and rings no phone.
 */
export function onlineOrderPushEvent(
  row: OnlineOrderPushRow,
): OnlineOrderPushEvent | null {
  if (row.status === "cancelled") return null;
  const method = row.payment_method ?? "";
  if (method === "smoke_test") return null;
  const paid = row.payment_status === "paid";
  if (method === "mercadopago") return paid ? "paid" : null;
  // A transfer the team confirmed was their own doing.
  return paid ? null : "awaiting_payment";
}

/** `45990` → `$45.990`, the way prices read in Chile. */
export function chileanPesos(value: number): string {
  const rounded = Math.round(Math.abs(value));
  const digits = String(rounded).replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  return `${value < 0 ? "-" : ""}$${digits}`;
}

function clean(value: unknown): string {
  if (typeof value !== "string") return "";
  return value.replaceAll(/[\r\n\t]+/g, " ").trim().slice(0, 80);
}

function titleFor(row: OnlineOrderPushRow, event: OnlineOrderPushEvent) {
  if (event === "paid") return "Venta web pagada";
  switch (row.payment_method) {
    case "transfer":
      return "Pedido web por transferencia";
    case "cash_on_delivery":
      return "Pedido web contra entrega";
    default:
      return "Pedido web nuevo";
  }
}

function nextStepFor(row: OnlineOrderPushRow, event: OnlineOrderPushEvent) {
  if (event === "paid") return "Hay que prepararlo.";
  switch (row.payment_method) {
    case "transfer":
      return "Revisa la cartola y confirma la transferencia.";
    case "cash_on_delivery":
      return "Se paga al recibirlo.";
    default:
      return "Revísalo en Pedidos web.";
  }
}

function deliveryLabel(value: string | null | undefined) {
  switch (value) {
    case "pickup":
      return "Retiro en tienda";
    case "shipping":
      return "Despacho";
    default:
      return "";
  }
}

export interface OnlineOrderPush {
  title: string;
  body: string;
  route: string;
  tag: string;
  data: Record<string, string>;
}

/**
 * Title, text and destination of the alert. The data carries no
 * `conversation_id`: with the app open the chat handlers ignore it and the
 * in-app order alert, which already exists, is the one that shows.
 */
export function buildOnlineOrderPush(
  row: OnlineOrderPushRow,
  event: OnlineOrderPushEvent,
): OnlineOrderPush {
  const total = Number(row.total ?? 0);
  const amount = Number.isFinite(total) && total > 0 ? chileanPesos(total) : "";
  const baseTitle = titleFor(row, event);
  const title = amount ? `${baseTitle} · ${amount}` : baseTitle;
  const facts = [
    clean(row.order_number),
    clean(row.customer_name),
    deliveryLabel(row.delivery_type),
  ].filter((part) => part.length > 0);
  const nextStep = nextStepFor(row, event);
  const body = facts.length > 0
    ? `${facts.join(" · ")}. ${nextStep}`
    : nextStep;
  const route = `/website/orders?order=${row.id}`;
  return {
    title,
    body,
    route,
    // The paid alert of the same order replaces the earlier one.
    tag: `online-order-${row.id}`,
    data: {
      kind: "online_order",
      event,
      order_id: row.id,
      route,
      title,
      body,
    },
  };
}
