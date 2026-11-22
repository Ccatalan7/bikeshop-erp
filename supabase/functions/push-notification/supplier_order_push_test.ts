import {
  buildSupplierOrderPush,
  SUPPLIER_ORDER_ALERT_ROLES,
  supplierOrderDispatchIsNews,
} from "./supplier_order_push.ts";

function assertEquals(actual: unknown, expected: unknown, message = "") {
  const actualJson = JSON.stringify(actual);
  const expectedJson = JSON.stringify(expected);
  if (actualJson !== expectedJson) {
    throw new Error(
      `${message}: expected ${expectedJson}, received ${actualJson}`,
    );
  }
}

function assert(condition: unknown, message = "assertion failed") {
  if (!condition) throw new Error(message);
}

// The open order that leaves by itself in the morning (20261122030000): the
// phone says what the ERP notice says.
const now = new Date("2026-11-23T12:31:00Z");
const row = {
  id: "d1",
  tenant_id: "t1",
  purchase_invoice_id: "ped-1",
  state: "sent",
  updated_at: "2026-11-23T12:30:40Z",
};

Deno.test("a dispatch that just settled rings; a queued or old one does not", () => {
  assert(supplierOrderDispatchIsNews(row, now));
  for (const state of ["sent", "failed", "skipped", "unknown"]) {
    assert(supplierOrderDispatchIsNews({ ...row, state }, now), state);
  }
  assert(!supplierOrderDispatchIsNews({ ...row, state: "queued" }, now));
  assert(
    !supplierOrderDispatchIsNews(
      { ...row, updated_at: "2026-11-23T10:00:00Z" },
      now,
    ),
  );
  assert(!supplierOrderDispatchIsNews({ ...row, updated_at: null }, now));
});

Deno.test("the alert carries the notice's words and opens the order", () => {
  const push = buildSupplierOrderPush(row, {
    title: "Pedido enviado a MKR Imports",
    body:
      "PED-202611-48213 · 3 productos de 2 ventas.\nSalió solo a las 09:30 con su PDF.",
    route: "/purchases/assistant?supplier=s1&order=ped-1",
  })!;
  assertEquals(push.title, "Pedido enviado a MKR Imports");
  assertEquals(
    push.body,
    "PED-202611-48213 · 3 productos de 2 ventas. Salió solo a las 09:30 con su PDF.",
  );
  assertEquals(push.route, "/purchases/assistant?supplier=s1&order=ped-1");
  // A later alert of the same order replaces this one.
  assertEquals(push.tag, "supplier-order-ped-1");
  assertEquals(push.data.kind, "supplier_order");
  assertEquals(push.data.route, push.route);
});

Deno.test("without a title there is nothing to ring, and a foreign route is not followed", () => {
  assertEquals(buildSupplierOrderPush(row, null), null);
  assertEquals(buildSupplierOrderPush(row, { title: "  " }), null);
  const push = buildSupplierOrderPush(row, {
    title: "No salió el pedido a MKR Imports",
    route: "https://otro.invalid/x",
  })!;
  assertEquals(push.route, "/purchases/assistant");
  assertEquals(SUPPLIER_ORDER_ALERT_ROLES.includes("admin"), true);
});
