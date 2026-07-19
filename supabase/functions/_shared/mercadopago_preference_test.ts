import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildMercadoPagoCharge,
  buildMercadoPagoExternalReference,
  mercadoPagoPaymentMethodPolicy,
  mercadoPagoPreferenceWindow,
  normalizeMercadoPagoPreferenceTtl,
  parseMercadoPagoExternalReference,
  paymentOrderIdentity,
  preferenceBelongsToOrder,
} from "./mercadopago_preference.ts";

const tenantId = "5443b130-cc28-45af-a420-cd500b288890";
const orderId = "e3161092-23f1-48ad-be8d-f83a110e5e79";

const baseItems = [
  {
    product_id: "product-a",
    product_name: "Bicicleta urbana",
    product_sku: "BIKE-A",
    quantity: 2,
    unit_price: 10_000,
    subtotal: 20_000,
  },
  {
    product_id: "product-b",
    product_name: "Casco",
    product_sku: "HELMET-B",
    quantity: 1,
    unit_price: 5_000,
    subtotal: 5_000,
  },
];

Deno.test("preference request excludes offline ticket payment methods", () => {
  assertEquals(mercadoPagoPaymentMethodPolicy(), {
    excluded_payment_types: [{ id: "ticket" }],
  });
});

Deno.test("preference charge preserves server item quantities without discount", () => {
  const result = buildMercadoPagoCharge(
    {
      total: 27_000,
      shipping_cost: 2_000,
      discount_amount: 0,
      delivery_type: "shipping",
    },
    baseItems,
  );

  assertEquals(result.itemGrossTotal, 25_000);
  assertEquals(result.shippingCost, 2_000);
  assertEquals(result.chargeTotal, 27_000);
  assertEquals(result.items, [
    {
      id: "BIKE-A",
      title: "Bicicleta urbana",
      quantity: 2,
      unit_price: 10_000,
      currency_id: "CLP",
    },
    {
      id: "HELMET-B",
      title: "Casco",
      quantity: 1,
      unit_price: 5_000,
      currency_id: "CLP",
    },
  ]);
});

Deno.test("preference charge allocates discounts and still equals the order total", () => {
  const result = buildMercadoPagoCharge(
    {
      total: 25_999,
      shipping_cost: 2_000,
      discount_amount: 1_001,
      delivery_type: "shipping",
    },
    baseItems,
  );

  assertEquals(result.discountAmount, 1_001);
  assertEquals(result.items, [
    {
      id: "BIKE-A",
      title: "Bicicleta urbana × 2",
      quantity: 1,
      unit_price: 19_199,
      currency_id: "CLP",
    },
    {
      id: "HELMET-B",
      title: "Casco",
      quantity: 1,
      unit_price: 4_800,
      currency_id: "CLP",
    },
  ]);
  assertEquals(
    result.items.reduce((sum, item) => sum + item.quantity * item.unit_price, 0) +
      result.shippingCost,
    25_999,
  );
});

Deno.test("preference charge rejects an order-level reconciliation mismatch", () => {
  assertThrows(
    () =>
      buildMercadoPagoCharge(
        {
          total: 25_001,
          shipping_cost: 2_000,
          discount_amount: 1_000,
          delivery_type: "shipping",
        },
        baseItems,
      ),
    Error,
    "items + shipping - discount != total",
  );
});

Deno.test("preference charge rejects a client-corrupt line subtotal", () => {
  assertThrows(
    () =>
      buildMercadoPagoCharge(
        {
          total: 27_000,
          shipping_cost: 2_000,
          discount_amount: 0,
          delivery_type: "shipping",
        },
        [{ ...baseItems[0], subtotal: 19_999 }, baseItems[1]],
      ),
    Error,
    "subtotal does not match quantity and price",
  );
});

Deno.test("preference charge fails closed on fractional CLP amounts", () => {
  assertThrows(
    () =>
      buildMercadoPagoCharge(
        {
          total: 27_000.5,
          shipping_cost: 2_000,
          discount_amount: 0,
          delivery_type: "shipping",
        },
        baseItems,
      ),
    Error,
    "whole CLP",
  );
});

Deno.test("preference charge rejects shipping on a pickup order", () => {
  assertThrows(
    () =>
      buildMercadoPagoCharge(
        {
          total: 27_000,
          shipping_cost: 2_000,
          discount_amount: 0,
          delivery_type: "pickup",
        },
        baseItems,
      ),
    Error,
    "Pickup orders cannot include a shipping charge",
  );
});

Deno.test("preference external reference binds tenant order and generation", () => {
  const reference = buildMercadoPagoExternalReference(tenantId, orderId, 7);

  assertEquals(
    reference,
    `vb1:${tenantId}:${orderId}:7`,
  );
  assertEquals(parseMercadoPagoExternalReference(reference), {
    tenantId,
    orderId,
    generation: 7,
    legacy: false,
  });
  assertEquals(preferenceBelongsToOrder(reference, tenantId, orderId), true);
  assertEquals(
    preferenceBelongsToOrder(
      reference,
      "97000000-0000-4000-8000-000000000002",
      orderId,
    ),
    false,
  );
});

Deno.test("legacy UUID references remain readable but malformed references fail closed", () => {
  assertEquals(parseMercadoPagoExternalReference(orderId), {
    tenantId: null,
    orderId,
    generation: null,
    legacy: true,
  });
  assertEquals(parseMercadoPagoExternalReference(`vb1:${tenantId}:${orderId}:0`), null);
  assertEquals(parseMercadoPagoExternalReference(`vb1:${tenantId}:not-an-order:1`), null);
});

Deno.test("payment identity rejects conflicting provider metadata", () => {
  const externalReference = buildMercadoPagoExternalReference(tenantId, orderId, 1);
  assertEquals(
    paymentOrderIdentity({
      external_reference: externalReference,
      metadata: {
        tenant_id: tenantId,
        online_order_id: orderId,
        preference_generation: 1,
      },
    }),
    { tenantId, orderId, generation: 1, legacy: false },
  );
  assertEquals(
    paymentOrderIdentity({
      external_reference: externalReference,
      metadata: {
        tenant_id: "97000000-0000-4000-8000-000000000002",
        online_order_id: orderId,
      },
    }),
    null,
  );
  assertEquals(
    paymentOrderIdentity({
      external_reference: externalReference,
      metadata: {
        tenant_id: tenantId,
        online_order_id: orderId,
        preference_generation: 2,
      },
    }),
    null,
  );
});

Deno.test("preference term is capped by the inventory reservation", () => {
  const now = new Date("2026-07-19T03:00:00.000Z");
  const window = mercadoPagoPreferenceWindow({
    now,
    ttlMinutes: 45,
    reservationExpiresAt: new Date("2026-07-19T03:12:00.000Z"),
  });

  assertEquals(window, {
    effectiveFrom: "2026-07-19T03:00:00.000Z",
    expiresAt: "2026-07-19T03:12:00.000Z",
    ttlMinutes: 45,
  });
});

Deno.test("preference TTL is tenant-configurable inside safe limits", () => {
  assertEquals(normalizeMercadoPagoPreferenceTtl(undefined), 30);
  assertEquals(normalizeMercadoPagoPreferenceTtl("2"), 5);
  assertEquals(normalizeMercadoPagoPreferenceTtl("45"), 45);
  assertEquals(normalizeMercadoPagoPreferenceTtl("999"), 60);
});

Deno.test("preference creation refuses a reservation too close to expiry", () => {
  assertThrows(
    () =>
      mercadoPagoPreferenceWindow({
        now: new Date("2026-07-19T03:00:00.000Z"),
        ttlMinutes: 30,
        reservationExpiresAt: new Date("2026-07-19T03:01:00.000Z"),
      }),
    Error,
    "too close to expiry",
  );
});
