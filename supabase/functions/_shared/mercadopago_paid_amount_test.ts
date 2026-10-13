import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { mercadoPagoOrderPaidAmount } from "./mercadopago_paid_amount.ts";
import { buildMercadoPagoPaymentEvidence } from "./mercadopago_payment_evidence.ts";

// WEB-26-00021, as Mercado Pago's Payments API returns it (2026-10-13): the
// products in transaction_amount, the delivery apart, $17.990 paid in full.
const paidWithDelivery = {
  id: 182785051395,
  status: "approved",
  transaction_amount: 11000,
  shipping_amount: 6990,
  currency_id: "CLP",
  installments: 1,
  transaction_details: {
    total_paid_amount: 17990,
    net_received_amount: 17306,
  },
};

Deno.test("an order paid with delivery is the products plus the delivery", () => {
  assertEquals(mercadoPagoOrderPaidAmount(paidWithDelivery), 17990);
});

Deno.test("an order without delivery is the products", () => {
  assertEquals(
    mercadoPagoOrderPaidAmount({ transaction_amount: 11000, shipping_amount: 0 }),
    11000,
  );
  assertEquals(mercadoPagoOrderPaidAmount({ transaction_amount: 11000 }), 11000);
});

Deno.test("installment interest the buyer pays is never the order's", () => {
  assertEquals(
    mercadoPagoOrderPaidAmount({
      transaction_amount: 120000,
      shipping_amount: 0,
      transaction_details: { total_paid_amount: 131400 },
    }),
    120000,
  );
});

Deno.test("an unusable amount is NaN, so the observation is refused", () => {
  assert(Number.isNaN(mercadoPagoOrderPaidAmount({})));
  assert(Number.isNaN(mercadoPagoOrderPaidAmount({ transaction_amount: null })));
  assert(Number.isNaN(mercadoPagoOrderPaidAmount({ transaction_amount: "" })));
  assert(
    Number.isNaN(
      mercadoPagoOrderPaidAmount({ transaction_amount: 100, shipping_amount: -1 }),
    ),
  );
  assert(
    Number.isNaN(
      mercadoPagoOrderPaidAmount({ transaction_amount: 100, shipping_amount: "x" }),
    ),
  );
  assert(Number.isNaN(mercadoPagoOrderPaidAmount(null)));
});

Deno.test("the stored evidence keeps the delivery that proves the total", () => {
  const evidence = buildMercadoPagoPaymentEvidence(paidWithDelivery);
  assertEquals(evidence.transaction_amount, 11000);
  assertEquals(evidence.shipping_amount, 6990);
  assertEquals(evidence.total_paid_amount, 17990);
});
