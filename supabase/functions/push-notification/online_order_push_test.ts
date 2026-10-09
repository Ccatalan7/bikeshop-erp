import {
  buildOnlineOrderPush,
  chileanPesos,
  onlineOrderPushEvent,
} from "./online_order_push.ts";
import type { OnlineOrderPushRow } from "./online_order_push.ts";

function assertEquals(actual: unknown, expected: unknown, message: string) {
  const actualJson = JSON.stringify(actual);
  const expectedJson = JSON.stringify(expected);
  if (actualJson !== expectedJson) {
    throw new Error(
      `${message}: expected ${expectedJson}, received ${actualJson}`,
    );
  }
}

function order(
  overrides: Partial<OnlineOrderPushRow> = {},
): OnlineOrderPushRow {
  return {
    id: "order-001",
    tenant_id: "tenant-a",
    order_number: "VB-0123",
    customer_name: "Camila Rojas",
    total: 45990,
    payment_method: "transfer",
    payment_status: "pending",
    delivery_type: "pickup",
    status: "confirmed",
    ...overrides,
  };
}

Deno.test("a pending transfer asks the team to confirm it", () => {
  assertEquals(
    onlineOrderPushEvent(order()),
    "awaiting_payment",
    "transfer waiting for the bank",
  );
});

Deno.test("a confirmed transfer rings nobody: the team did it", () => {
  assertEquals(
    onlineOrderPushEvent(order({ payment_status: "paid" })),
    null,
    "transfer already confirmed",
  );
});

Deno.test("Mercado Pago rings only once paid", () => {
  assertEquals(
    onlineOrderPushEvent(order({ payment_method: "mercadopago" })),
    null,
    "checkout still open",
  );
  assertEquals(
    onlineOrderPushEvent(
      order({ payment_method: "mercadopago", payment_status: "failed" }),
    ),
    null,
    "failed payment",
  );
  assertEquals(
    onlineOrderPushEvent(
      order({ payment_method: "mercadopago", payment_status: "paid" }),
    ),
    "paid",
    "paid order to prepare",
  );
});

Deno.test("cancelled and smoke-test orders ring nobody", () => {
  assertEquals(
    onlineOrderPushEvent(order({ status: "cancelled" })),
    null,
    "cancelled",
  );
  assertEquals(
    onlineOrderPushEvent(order({ payment_method: "smoke_test" })),
    null,
    "smoke test",
  );
});

Deno.test("cash on delivery and unknown methods still ring", () => {
  assertEquals(
    onlineOrderPushEvent(order({ payment_method: "cash_on_delivery" })),
    "awaiting_payment",
    "cash on delivery",
  );
  assertEquals(
    onlineOrderPushEvent(order({ payment_method: null })),
    "awaiting_payment",
    "no method recorded",
  );
});

Deno.test("prices read the Chilean way", () => {
  assertEquals(chileanPesos(45990), "$45.990", "five digits");
  assertEquals(chileanPesos(1234567), "$1.234.567", "seven digits");
  assertEquals(chileanPesos(990), "$990", "three digits");
  assertEquals(chileanPesos(45990.4), "$45.990", "rounded");
});

Deno.test("transfer alert says what to do and opens the order", () => {
  const push = buildOnlineOrderPush(order(), "awaiting_payment");
  assertEquals(
    push.title,
    "Pedido web por transferencia · $45.990",
    "title",
  );
  assertEquals(
    push.body,
    "VB-0123 · Camila Rojas · Retiro en tienda. Revisa la cartola y confirma la transferencia.",
    "body",
  );
  assertEquals(push.route, "/website/orders?order=order-001", "route");
  assertEquals(push.tag, "online-order-order-001", "tag");
  assertEquals(push.data.kind, "online_order", "kind");
  assertEquals(push.data.route, push.route, "data route");
  assertEquals(
    Object.keys(push.data).includes("conversation_id"),
    false,
    "no chat identity, so open apps leave it to the in-app alert",
  );
  assertEquals(
    Object.values(push.data).every((value) => typeof value === "string"),
    true,
    "FCM data values are strings",
  );
});

Deno.test("paid alert reads as a sale to prepare", () => {
  const push = buildOnlineOrderPush(
    order({
      payment_method: "mercadopago",
      payment_status: "paid",
      delivery_type: "shipping",
      total: "129990",
    }),
    "paid",
  );
  assertEquals(push.title, "Venta web pagada · $129.990", "title");
  assertEquals(
    push.body,
    "VB-0123 · Camila Rojas · Despacho. Hay que prepararlo.",
    "body",
  );
});

Deno.test("missing facts leave no dangling separators", () => {
  const push = buildOnlineOrderPush(
    order({
      order_number: null,
      customer_name: "  ",
      delivery_type: null,
      total: 0,
    }),
    "awaiting_payment",
  );
  assertEquals(push.title, "Pedido web por transferencia", "title");
  assertEquals(
    push.body,
    "Revisa la cartola y confirma la transferencia.",
    "body",
  );
});
