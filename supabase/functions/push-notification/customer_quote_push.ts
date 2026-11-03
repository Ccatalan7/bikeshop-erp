/**
 * The staff phone alert for a quote (plan «Cotizaciones y pedidos a pedido»:
 * every new quote rings the shop's phone, so the suppliers are asked while the
 * customer is still waiting). Pure rules, tested in
 * `customer_quote_push_test.ts`; `index.ts` reads the quote and sends it
 * through the same delivery as a web order.
 */

import { chileanPesos } from "./online_order_push.ts";

export interface CustomerQuotePushRow {
  id: string;
  tenant_id: string | null;
  quote_number?: string | null;
  customer_name?: string | null;
  status?: string | null;
  source?: string | null;
}

/**
 * `requested`: a customer sent a quote from the site; `changes_requested`:
 * the customer asked for changes to the offer. Both put the quote back in
 * the team's hands.
 */
export type CustomerQuotePushEvent = "requested" | "changes_requested";

/**
 * What the quote needs from the team now, read from the row. A request that
 * arrives late (the offer already went out, the quote was cancelled) finds
 * nothing to do and rings no phone.
 */
export function customerQuotePushEvent(
  row: CustomerQuotePushRow,
  requested: string | undefined,
): CustomerQuotePushEvent | null {
  if (row.status !== "confirming") return null;
  if (requested === "requested" || requested === "changes_requested") {
    return requested;
  }
  return null;
}

function clean(value: unknown): string {
  if (typeof value !== "string") return "";
  return value.replaceAll(/[\r\n\t]+/g, " ").trim().slice(0, 80);
}

export interface CustomerQuotePush {
  title: string;
  body: string;
  route: string;
  tag: string;
  data: Record<string, string>;
}

/**
 * Title, text and destination of the alert: the quote in the inbox. The
 * total is the reference of what was asked, when the page knew it.
 */
export function buildCustomerQuotePush(
  row: CustomerQuotePushRow,
  event: CustomerQuotePushEvent,
  facts: { lines: number; reference?: number | null },
): CustomerQuotePush {
  const reference = Number(facts.reference ?? 0);
  const baseTitle = event === "requested"
    ? "Cotización nueva"
    : "El cliente pidió cambios";
  const title = Number.isFinite(reference) && reference > 0
    ? `${baseTitle} · ${chileanPesos(reference)}`
    : baseTitle;
  const count = facts.lines === 1 ? "1 producto" : `${facts.lines} productos`;
  const parts = [
    clean(row.quote_number),
    clean(row.customer_name),
    facts.lines > 0 ? count : "",
  ].filter((part) => part.length > 0);
  const nextStep = event === "requested"
    ? "Confirma con los proveedores y envía la oferta."
    : "Revisa sus cambios y envía la oferta nueva.";
  const body = parts.length > 0
    ? `${parts.join(" · ")}. ${nextStep}`
    : nextStep;
  const route = `/sales/quotes?quote=${row.id}`;
  return {
    title,
    body,
    route,
    // A later alert of the same quote replaces the earlier one.
    tag: `customer-quote-${row.id}`,
    data: {
      kind: "customer_quote",
      event,
      quote_id: row.id,
      route,
      title,
      body,
    },
  };
}
