/**
 * What the buyer paid for the order: the products (`transaction_amount`) plus
 * the delivery Mercado Pago charged (`shipping_amount`, the preference's
 * `shipments.cost`). Mercado Pago keeps that delivery out of
 * `transaction_amount`; until 2026-10-13 the webhook compared the products
 * alone with the order total and rejected WEB-26-00021, paid in full ($11.000
 * + $6.990). Interest a buyer pays for installments (the rest of
 * `transaction_details.total_paid_amount`) is Mercado Pago's, never the
 * order's, so it is not added.
 *
 * NaN when an amount is missing or unusable.
 */
export function mercadoPagoOrderPaidAmount(rawPayment: unknown): number {
  const payment = rawPayment != null && typeof rawPayment === "object" &&
      !Array.isArray(rawPayment)
    ? rawPayment as Record<string, unknown>
    : {};
  const products = amountOf(payment.transaction_amount);
  if (products === null) return Number.NaN;
  const shipping = payment.shipping_amount == null
    ? 0
    : amountOf(payment.shipping_amount);
  if (shipping === null || shipping < 0) return Number.NaN;
  return products + shipping;
}

function amountOf(value: unknown): number | null {
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}
