import { assertEquals, assertFalse } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildMercadoPagoPaymentEvidence } from "./mercadopago_payment_evidence.ts";

Deno.test("Mercado Pago evidence keeps reconciliation fields and removes PII/card data", () => {
  const evidence = buildMercadoPagoPaymentEvidence({
    id: 123456,
    status: "approved",
    status_detail: "accredited",
    payment_type_id: "credit_card",
    payment_method_id: "visa",
    authorization_code: "AUTH-42",
    date_created: "2026-07-18T10:00:00Z",
    date_approved: "2026-07-18T10:00:04Z",
    date_last_updated: "2026-07-18T10:00:04Z",
    transaction_amount: 12990,
    currency_id: "CLP",
    order: { id: "merchant-77" },
    transaction_details: {
      total_paid_amount: 12990,
      net_received_amount: 12100,
      // When returned on a fully approved payment, this public provider link
      // is retained only as a non-fiscal payment-receipt reference.
      external_resource_url: "https://mercadopago.cl/ticket/payment-flow",
    },
    card: {
      first_six_digits: "411111",
      last_four_digits: "1111",
      cardholder: { name: "Persona privada" },
    },
    payer: { email: "private@example.com", identification: { number: "1-9" } },
    point_of_interaction: {
      type: "CHECKOUT",
      business_info: { unit: "online_payments", sub_unit: "checkout_pro" },
      transaction_data: {
        // QR/ticket continuation URLs are also payment-flow resources.
        ticket_url: "https://mercadopago.cl/qr/payment-flow",
      },
    },
    three_ds_info: {
      external_resource_url: "https://issuer.example.test/3ds-challenge",
      creq: "never-store-this-either",
    },
    official_document: {
      artifact_url: "https://attacker.example.test/not-a-voucher.pdf",
      fiscal_validity: "voucher_valid_as_boleta",
    },
    processing_mode: "aggregator",
    access_token: "never-store-this",
  });

  assertEquals(evidence, {
    operation_number: "123456",
    status_detail: "accredited",
    payment_type_id: "credit_card",
    payment_method_id: "visa",
    merchant_order_id: "merchant-77",
    authorization_code: "AUTH-42",
    date_created: "2026-07-18T10:00:00Z",
    date_approved: "2026-07-18T10:00:04Z",
    date_last_updated: "2026-07-18T10:00:04Z",
    transaction_amount: 12990,
    currency_id: "CLP",
    total_paid_amount: 12990,
    card_last_four_digits: "1111",
    processing_mode: "aggregator",
    point_of_interaction_type: "CHECKOUT",
    point_of_interaction_unit: "online_payments",
    point_of_interaction_sub_unit: "checkout_pro",
    mercadopago_payment_voucher: {
      source: "transaction_details.external_resource_url",
      availability: "available",
      fiscal_validity: "not_a_tax_document",
      url: "https://mercadopago.cl/ticket/payment-flow",
    },
  });
  assertFalse("payer" in evidence);
  assertFalse("first_six_digits" in evidence);
  assertFalse("access_token" in evidence);
  assertFalse("external_resource_url" in evidence);
  assertFalse("ticket_url" in evidence);
  assertFalse("three_ds_info" in evidence);
  assertFalse("official_document" in evidence);
});

Deno.test("Mercado Pago evidence drops empty and invalid optional values", () => {
  assertEquals(
    buildMercadoPagoPaymentEvidence({
      id: "  payment-1  ",
      transaction_amount: "not-a-number",
      currency_id: " ",
    }),
    {
      operation_number: "payment-1",
      mercadopago_payment_voucher: {
        source: "transaction_details.external_resource_url",
        availability: "not_applicable",
        fiscal_validity: "not_a_tax_document",
        reason: "payment_not_approved",
      },
    },
  );
});
