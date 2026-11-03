import {
  buildCustomerQuotePush,
  customerQuotePushEvent,
} from "./customer_quote_push.ts";
import type { CustomerQuotePushRow } from "./customer_quote_push.ts";

function assertEquals(actual: unknown, expected: unknown, message: string) {
  const actualJson = JSON.stringify(actual);
  const expectedJson = JSON.stringify(expected);
  if (actualJson !== expectedJson) {
    throw new Error(
      `${message}: expected ${expectedJson}, received ${actualJson}`,
    );
  }
}

function quote(
  overrides: Partial<CustomerQuotePushRow> = {},
): CustomerQuotePushRow {
  return {
    id: "quote-001",
    tenant_id: "tenant-a",
    quote_number: "COT-26-00012",
    customer_name: "Camila Rojas",
    status: "confirming",
    source: "web",
    ...overrides,
  };
}

Deno.test("a quote waiting for the team rings for what was asked", () => {
  assertEquals(
    customerQuotePushEvent(quote(), "requested"),
    "requested",
    "new quote",
  );
  assertEquals(
    customerQuotePushEvent(quote(), "changes_requested"),
    "changes_requested",
    "changes",
  );
  assertEquals(
    customerQuotePushEvent(quote(), "accepted"),
    null,
    "acceptance rings as a web order, not here",
  );
});

Deno.test("a late request finds nothing to do", () => {
  for (const status of ["offered", "accepted", "rejected", "cancelled"]) {
    assertEquals(
      customerQuotePushEvent(quote({ status }), "requested"),
      null,
      status,
    );
  }
});

Deno.test("the alert names the quote and the next step, and opens it", () => {
  const push = buildCustomerQuotePush(quote(), "requested", {
    lines: 3,
    reference: 106970,
  });
  assertEquals(push.title, "Cotización nueva · $106.970", "title");
  assertEquals(
    push.body,
    "COT-26-00012 · Camila Rojas · 3 productos. Confirma con los proveedores y envía la oferta.",
    "body",
  );
  assertEquals(push.route, "/sales/quotes?quote=quote-001", "route");
  assertEquals(push.tag, "customer-quote-quote-001", "tag");
  assertEquals(push.data.kind, "customer_quote", "kind");
});

Deno.test("changes ask for the new offer; one line reads singular", () => {
  const push = buildCustomerQuotePush(
    quote({ customer_name: "  Ana\nPérez " }),
    "changes_requested",
    { lines: 1 },
  );
  assertEquals(push.title, "El cliente pidió cambios", "no total, no amount");
  assertEquals(
    push.body,
    "COT-26-00012 · Ana Pérez · 1 producto. Revisa sus cambios y envía la oferta nueva.",
    "body",
  );
});
