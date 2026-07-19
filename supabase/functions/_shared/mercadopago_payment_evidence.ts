import { inspectMercadoPagoPaymentVoucher } from "./mercadopago_payment_voucher.ts";

type JsonRecord = Record<string, unknown>;

function record(value: unknown): JsonRecord {
  return value != null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : {};
}

function optionalText(value: unknown): string | null {
  if (typeof value !== "string" && typeof value !== "number") return null;
  const normalized = String(value).trim();
  return normalized.length > 0 ? normalized : null;
}

function optionalNumber(value: unknown): number | null {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

/**
 * Keep only the provider fields needed to reconcile and later prove a payment
 * voucher. Never persist payer identity, full card data, access tokens, or the
 * unbounded Mercado Pago response in the order-event ledger.
 *
 * This evidence is not, on its own, a representation of a Chilean electronic
 * payment voucher and must not be labelled "Valido como Boleta". That label
 * requires the merchant's declared SII issuance model and the actual provider
 * representation containing every field required by the SII.
 */
export function buildMercadoPagoPaymentEvidence(
  rawPayment: unknown,
): JsonRecord {
  const payment = record(rawPayment);
  const order = record(payment.order);
  const card = record(payment.card);
  const transactionDetails = record(payment.transaction_details);
  const pointOfInteraction = record(payment.point_of_interaction);
  const businessInfo = record(pointOfInteraction.business_info);
  const paymentVoucher = inspectMercadoPagoPaymentVoucher(rawPayment);

  const evidence: JsonRecord = {
    operation_number: optionalText(payment.id),
    status_detail: optionalText(payment.status_detail),
    payment_type_id: optionalText(payment.payment_type_id),
    payment_method_id: optionalText(payment.payment_method_id),
    merchant_order_id: optionalText(order.id),
    authorization_code: optionalText(payment.authorization_code),
    date_created: optionalText(payment.date_created),
    date_approved: optionalText(payment.date_approved),
    date_last_updated: optionalText(payment.date_last_updated),
    transaction_amount: optionalNumber(payment.transaction_amount),
    currency_id: optionalText(payment.currency_id),
    total_paid_amount: optionalNumber(transactionDetails.total_paid_amount),
    card_last_four_digits: optionalText(card.last_four_digits),
    processing_mode: optionalText(payment.processing_mode),
    point_of_interaction_type: optionalText(pointOfInteraction.type),
    point_of_interaction_sub_type: optionalText(pointOfInteraction.sub_type),
    point_of_interaction_unit: optionalText(businessInfo.unit),
    point_of_interaction_sub_unit: optionalText(businessInfo.sub_unit),
    // This is explicit provider-artifact availability evidence, not fiscal
    // evidence. Even an available link remains not_a_tax_document here.
    mercadopago_payment_voucher: paymentVoucher.observation,
  };

  return Object.fromEntries(
    Object.entries(evidence).filter(([, value]) => value !== null),
  );
}
