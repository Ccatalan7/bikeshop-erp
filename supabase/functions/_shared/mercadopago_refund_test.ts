import { assertEquals, assertThrows } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildMercadoPagoRefundEvidence,
  matchesCorrection,
  parseMercadoPagoRefundRequest,
  providerHttpOutcomeIsUnknown,
} from "./mercadopago_refund.ts";

Deno.test("refund request accepts only a UUID correction identifier", () => {
  assertEquals(
    parseMercadoPagoRefundRequest({
      correction_id: "019f6e86-070c-4210-ae4a-63596a382d15",
    }).correctionId,
    "019f6e86-070c-4210-ae4a-63596a382d15",
  );
  assertThrows(() => parseMercadoPagoRefundRequest({ correction_id: "../payment" }));
});

Deno.test("ambiguous provider HTTP outcomes remain retry-safe unknowns", () => {
  assertEquals(providerHttpOutcomeIsUnknown(400), false);
  assertEquals(providerHttpOutcomeIsUnknown(404), false);
  assertEquals(providerHttpOutcomeIsUnknown(408), true);
  assertEquals(providerHttpOutcomeIsUnknown(409), true);
  assertEquals(providerHttpOutcomeIsUnknown(429), true);
  assertEquals(providerHttpOutcomeIsUnknown(503), true);
});

Deno.test("provider evidence must be approved and match payment and amount", () => {
  const evidence = buildMercadoPagoRefundEvidence({
    id: 101,
    payment_id: 202,
    status: "approved",
    amount: 24990,
    date_created: "2026-07-18T12:30:00-04:00",
    refund_mode: "standard",
    payer: { email: "must-not-be-copied@example.com" },
  });
  assertEquals(evidence, {
    id: "101",
    payment_id: "202",
    status: "approved",
    amount: 24990,
    date_created: "2026-07-18T12:30:00-04:00",
    refund_mode: "standard",
  });
  assertEquals(matchesCorrection(evidence, "202", 24990), true);
  assertEquals(matchesCorrection(evidence, "999", 24990), false);
  assertThrows(() => buildMercadoPagoRefundEvidence({ status: "pending" }));
});
