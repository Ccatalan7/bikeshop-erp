import { assertEquals, assertNotEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  expireMercadoPagoPreferencePayload,
  parseRecoverableMercadoPagoPreference,
  preferenceSearchIds,
  trustedMercadoPagoCheckoutUrl,
} from "./mercadopago_preference_lifecycle.ts";

const tenantId = "5443b130-cc28-45af-a420-cd500b288890";
const orderId = "e3161092-23f1-48ad-be8d-f83a110e5e79";
const externalReference = `vb1:${tenantId}:${orderId}:1`;

Deno.test("lost-ack recovery adopts only an exact provider preference", () => {
  const recovered = parseRecoverableMercadoPagoPreference({
    id: "collector-preference-1",
    external_reference: externalReference,
    metadata: {
      tenant_id: tenantId,
      online_order_id: orderId,
      preference_generation: 1,
    },
    init_point: "https://www.mercadopago.cl/checkout/v1/redirect?pref_id=one",
    sandbox_init_point: "https://sandbox.mercadopago.com/checkout/pay?pref_id=one",
    date_created: "2026-07-19T03:00:00.000Z",
    expiration_date_to: "2026-07-19T03:30:00.000Z",
    items: [{ quantity: 1, unit_price: 43_000 }],
    shipments: { cost: 2_000 },
  }, {
    externalReference,
    amount: 45_000,
    expiresAt: "2026-07-19T03:30:00.000Z",
  });

  assertNotEquals(recovered, null);
  assertEquals(recovered?.id, "collector-preference-1");
});

Deno.test("lost-ack recovery rejects amount tenant and expiry mismatches", () => {
  const base = {
    id: "collector-preference-1",
    external_reference: externalReference,
    metadata: {
      tenant_id: tenantId,
      online_order_id: orderId,
      preference_generation: 1,
    },
    init_point: "https://www.mercadopago.cl/checkout/v1/redirect?pref_id=one",
    expiration_date_to: "2026-07-19T03:30:00.000Z",
    items: [{ quantity: 1, unit_price: 45_000 }],
  };
  const expected = {
    externalReference,
    amount: 45_000,
    expiresAt: "2026-07-19T03:30:00.000Z",
  };

  assertEquals(
    parseRecoverableMercadoPagoPreference(
      { ...base, items: [{ quantity: 1, unit_price: 44_999 }] },
      expected,
    ),
    null,
  );
  assertEquals(
    parseRecoverableMercadoPagoPreference({
      ...base,
      metadata: {
        tenant_id: "97000000-0000-4000-8000-000000000002",
        online_order_id: orderId,
        preference_generation: 1,
      },
    }, expected),
    null,
  );
  assertEquals(
    parseRecoverableMercadoPagoPreference({
      ...base,
      metadata: {
        tenant_id: tenantId,
        online_order_id: orderId,
        preference_generation: 2,
      },
    }, expected),
    null,
  );
  assertEquals(
    parseRecoverableMercadoPagoPreference({
      ...base,
      expiration_date_to: "2026-07-19T04:30:00.000Z",
    }, expected),
    null,
  );
});

Deno.test("checkout URLs are restricted to HTTPS Mercado Pago origins", () => {
  assertEquals(
    trustedMercadoPagoCheckoutUrl("https://www.mercadopago.cl/checkout/start"),
    "https://www.mercadopago.cl/checkout/start",
  );
  assertEquals(trustedMercadoPagoCheckoutUrl("http://www.mercadopago.cl/checkout"), null);
  assertEquals(trustedMercadoPagoCheckoutUrl("https://mercadopago.cl.evil.test/checkout"), null);
});

Deno.test("preference search IDs are bounded unique provider identifiers", () => {
  assertEquals(
    preferenceSearchIds({
      elements: [
        { id: "pref-1" },
        { id: "pref-1" },
        { id: "pref_2" },
        { id: "pref/unsafe" },
      ],
    }),
    ["pref-1", "pref_2"],
  );
});

Deno.test("preference closure moves provider expiry to the immediate safe boundary", () => {
  assertEquals(
    expireMercadoPagoPreferencePayload(
      new Date("2026-07-19T03:30:00.000Z"),
      "2026-07-19T03:00:00.000Z",
    ),
    {
      expires: true,
      expiration_date_from: "2026-07-19T03:00:00.000Z",
      expiration_date_to: "2026-07-19T03:30:05.000Z",
    },
  );
});
