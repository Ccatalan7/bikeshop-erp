/**
 * The phone alert for a supplier's open order that leaves by itself in the
 * morning (20261122030000): it left with its PDF, it did not, or WhatsApp did
 * not say. The words are the database's — the ERP notice of the same
 * dispatch (`supplier_order_dispatch_notify_internal`) — so the phone and the
 * bell never tell two stories. Pure rules, tested in
 * `supplier_order_push_test.ts`; `index.ts` reads the dispatch and its notice
 * and sends them through the same delivery as a web order.
 */

export interface SupplierOrderDispatchPushRow {
  id: string;
  tenant_id: string | null;
  purchase_invoice_id?: string | null;
  state?: string | null;
  updated_at?: string | null;
}

export interface SupplierOrderNoticeRow {
  title?: string | null;
  body?: string | null;
  route?: string | null;
}

export interface SupplierOrderPush {
  title: string;
  body: string;
  route: string;
  tag: string;
  data: Record<string, string>;
}

/**
 * A dispatch settled longer ago than this is not news: a restored backup
 * reinserts old rows with the triggers alive, and a late or replayed request
 * finds the same row.
 */
export const SUPPLIER_ORDER_ALERT_FRESH_MS = 60 * 60 * 1000;

/** Who buys from the suppliers: the roles that manage purchases. */
export const SUPPLIER_ORDER_ALERT_ROLES = ["admin", "manager"];

const SETTLED_STATES = new Set(["sent", "failed", "skipped", "unknown"]);

/** Whether [row] settled just now: sent, not sent, or unknown. */
export function supplierOrderDispatchIsNews(
  row: SupplierOrderDispatchPushRow,
  now: Date,
): boolean {
  if (!row.state || !SETTLED_STATES.has(row.state)) return false;
  const at = Date.parse(row.updated_at ?? "");
  if (!Number.isFinite(at)) return false;
  const age = now.getTime() - at;
  // A clock a little ahead of this one is still now.
  return age < SUPPLIER_ORDER_ALERT_FRESH_MS && age > -5 * 60 * 1000;
}

function clean(value: unknown, max: number): string {
  if (typeof value !== "string") return "";
  return value.replaceAll(/[\r\n\t]+/g, " ").trim().slice(0, max);
}

/**
 * The alert of [row] with the words of its ERP [notice]; null without a
 * title. It opens the purchasing assistant on the order, and a later alert
 * of the same order (it left, then WhatsApp failed it) replaces this one.
 */
export function buildSupplierOrderPush(
  row: SupplierOrderDispatchPushRow,
  notice: SupplierOrderNoticeRow | null,
): SupplierOrderPush | null {
  const title = clean(notice?.title, 120);
  if (!title) return null;
  const body = clean(notice?.body, 240);
  const rawRoute = clean(notice?.route, 300);
  const route = rawRoute.startsWith("/purchases/")
    ? rawRoute
    : "/purchases/assistant";
  return {
    title,
    body,
    route,
    tag: `supplier-order-${row.purchase_invoice_id ?? row.id}`,
    data: {
      kind: "supplier_order",
      dispatch_id: row.id,
      route,
      title,
      body,
    },
  };
}
