import { assertEquals, assertFalse } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  merchantOrderProcessingState,
  summarizeMercadoPagoApiError,
  uniqueMercadoPagoPaymentIds,
} from "./mercadopago_webhook_resources.ts";

Deno.test("Mercado Pago API errors are bounded and redact body secrets", () => {
  const summary = summarizeMercadoPagoApiError(
    {
      error: "unauthorized",
      message: "Bearer TEST-SECRET access_token=ANOTHER-SECRET for private@example.com\nraw detail",
      payer: { email: "must-not-appear@example.com" },
    },
    "payment",
    401,
  );

  assertEquals(
    summary,
    "HTTP 401 · unauthorized · Bearer [redacted] access_token=[redacted] for [redacted-email] raw detail",
  );
  assertFalse(summary.includes("TEST-SECRET"));
  assertFalse(summary.includes("ANOTHER-SECRET"));
  assertFalse(summary.includes("must-not-appear"));
});

Deno.test("merchant order uses every unique valid payment id", () => {
  assertEquals(
    uniqueMercadoPagoPaymentIds([
      { id: 1001 },
      { id: "1002" },
      { id: 1001 },
      { id: " 1003 " },
      { id: "not-a-provider-id" },
      null,
    ]),
    ["1001", "1002", "1003"],
  );
});

Deno.test("merchant order exposes action required when any payment requires it", () => {
  assertEquals(
    merchantOrderProcessingState([
      { payment_id: "1001", processing_state: "processed" },
      { payment_id: "1002", processing_state: "action_required" },
    ]),
    "action_required",
  );
  assertEquals(merchantOrderProcessingState([]), null);
});
