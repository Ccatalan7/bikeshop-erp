import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  inspectMercadoPagoPaymentVoucher,
  recordMercadoPagoPaymentVoucherIfAvailable,
  safeMercadoPagoPaymentVoucherUrl,
  sha256Hex,
} from "./mercadopago_payment_voucher.ts";

function approvedPayment(overrides: Record<string, unknown> = {}) {
  return {
    id: "MP-RECEIPT-001",
    status: "approved",
    status_detail: "accredited",
    transaction_amount: 24990,
    currency_id: "CLP",
    date_approved: "2026-07-18T19:00:00-04:00",
    transaction_details: {
      external_resource_url:
        "https://www.mercadopago.cl/activities/receipt?payment_id=MP-RECEIPT-001",
    },
    ...overrides,
  };
}

Deno.test("payment voucher inspection accepts only complete credential-free provider HTTPS links", () => {
  const result = inspectMercadoPagoPaymentVoucher(approvedPayment());
  assertEquals(result.observation, {
    source: "transaction_details.external_resource_url",
    availability: "available",
    fiscal_validity: "not_a_tax_document",
    url: "https://www.mercadopago.cl/activities/receipt?payment_id=MP-RECEIPT-001",
  });
  assertEquals(result.candidate?.issuedAt, "2026-07-18T23:00:00.000Z");
  assertEquals(result.candidate?.paymentId, "MP-RECEIPT-001");
});

Deno.test("payment voucher inspection records absence without inventing an artifact", () => {
  const result = inspectMercadoPagoPaymentVoucher(approvedPayment({
    transaction_details: {},
  }));
  assertEquals(result, {
    observation: {
      source: "transaction_details.external_resource_url",
      availability: "absent",
      fiscal_validity: "not_a_tax_document",
      reason: "provider_field_missing",
    },
    candidate: null,
  });
});

Deno.test("payment voucher inspection rejects credentialed, non-provider and fragment URLs", () => {
  for (
    const url of [
      "http://www.mercadopago.cl/receipt",
      "https://user:password@www.mercadopago.cl/receipt",
      "https://www.mercadopago.cl/receipt#access-token",
      "https://www.mercadopago.cl/receipt?access_token=secret",
      "https://attacker.example.test/receipt",
      "https://mercadopago.cl.attacker.example/receipt",
    ]
  ) {
    assertEquals(safeMercadoPagoPaymentVoucherUrl(url), null);
    assertEquals(
      inspectMercadoPagoPaymentVoucher(approvedPayment({
        transaction_details: { external_resource_url: url },
      })).observation.availability,
      "rejected_unsafe",
    );
  }
});

Deno.test("producer records the non-fiscal receipt through the canonical recorder exactly after paid validation", async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const result = await recordMercadoPagoPaymentVoucherIfAvailable({
    supabase: {
      rpc(name, args) {
        calls.push({ name, args });
        return Promise.resolve({
          data: "9e320000-0000-4000-8000-000000000001",
          error: null,
        });
      },
    },
    payment: approvedPayment(),
    tenantId: "9e320000-0000-4000-8000-000000000010",
    orderId: "9e320000-0000-4000-8000-000000000020",
    eventResult: { event_id: 42, outcome: "payment_validated" },
    processingResult: { processing_state: "action_required", payment_status: "paid" },
  });

  assertEquals(result, {
    recorded: true,
    availability: "available",
    documentId: "9e320000-0000-4000-8000-000000000001",
  });
  assertEquals(calls.length, 1);
  assertEquals(calls[0].name, "record_online_order_official_document");
  assertEquals(calls[0].args.p_document_kind, "mercadopago_payment_voucher");
  assertEquals(calls[0].args.p_fiscal_validity, "not_a_tax_document");
  assertEquals(calls[0].args.p_voucher_fiscal_evidence, null);
  assertEquals(
    calls[0].args.p_artifact_sha256,
    await sha256Hex(
      "https://www.mercadopago.cl/activities/receipt?payment_id=MP-RECEIPT-001",
    ),
  );
});

Deno.test("producer does not record an absent receipt or an unprocessed payment", async () => {
  let calls = 0;
  const rpcClient = {
    rpc() {
      calls += 1;
      return Promise.resolve({ data: null, error: null });
    },
  };

  const absent = await recordMercadoPagoPaymentVoucherIfAvailable({
    supabase: rpcClient,
    payment: approvedPayment({ transaction_details: {} }),
    tenantId: "tenant",
    orderId: "order",
    eventResult: { event_id: 1, outcome: "payment_validated" },
    processingResult: { processing_state: "processed", payment_status: "paid" },
  });
  const pending = await recordMercadoPagoPaymentVoucherIfAvailable({
    supabase: rpcClient,
    payment: approvedPayment(),
    tenantId: "tenant",
    orderId: "order",
    eventResult: { event_id: 2, outcome: "payment_validated" },
    processingResult: { processing_state: "action_required", payment_status: "pending" },
  });

  assertEquals(absent, { recorded: false, availability: "absent" });
  assertEquals(pending, { recorded: false, availability: "available" });
  assertEquals(calls, 0);
});

Deno.test("producer surfaces recorder failures so provider retries can recover idempotently", async () => {
  await assertRejects(
    () =>
      recordMercadoPagoPaymentVoucherIfAvailable({
        supabase: {
          rpc: () => Promise.resolve({ data: null, error: { message: "ledger unavailable" } }),
        },
        payment: approvedPayment(),
        tenantId: "tenant",
        orderId: "order",
        eventResult: { event_id: 3, outcome: "payment_validated" },
        processingResult: { processing_state: "processed" },
      }),
    Error,
    "Mercado Pago payment voucher recording failed: ledger unavailable",
  );
});
