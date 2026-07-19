export type MercadoPagoRefundRequest = {
  correctionId: string;
};

export type MercadoPagoRefundEvidence = {
  id: string;
  payment_id: string;
  status: string;
  amount: number;
  date_created: string;
  refund_mode: string | null;
};

export function parseMercadoPagoRefundRequest(
  value: unknown,
): MercadoPagoRefundRequest {
  if (!value || typeof value !== "object") {
    throw new Error("Invalid refund request");
  }
  const correctionId = (value as Record<string, unknown>).correction_id;
  if (
    typeof correctionId !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(correctionId.trim())
  ) {
    throw new Error("Invalid correction identifier");
  }
  return { correctionId: correctionId.trim() };
}

export function buildMercadoPagoRefundEvidence(
  value: unknown,
): MercadoPagoRefundEvidence {
  if (!value || typeof value !== "object") {
    throw new Error("Mercado Pago returned invalid refund evidence");
  }
  const refund = value as Record<string, unknown>;
  const id = refund.id?.toString().trim() ?? "";
  const paymentId = refund.payment_id?.toString().trim() ?? "";
  const status = refund.status?.toString().trim().toLowerCase() ?? "";
  const amount = Number(refund.amount);
  const dateCreated = refund.date_created?.toString().trim() ?? "";
  if (
    !id || !paymentId || status !== "approved" ||
    !Number.isFinite(amount) || amount <= 0 || !dateCreated ||
    Number.isNaN(Date.parse(dateCreated))
  ) {
    throw new Error("Mercado Pago refund evidence is incomplete");
  }
  return {
    id,
    payment_id: paymentId,
    status,
    amount,
    date_created: dateCreated,
    refund_mode: refund.refund_mode?.toString() ?? null,
  };
}

export function matchesCorrection(
  evidence: MercadoPagoRefundEvidence,
  expectedPaymentId: string,
  expectedAmount: number,
): boolean {
  return evidence.payment_id === expectedPaymentId &&
    evidence.amount === expectedAmount;
}

export function providerHttpOutcomeIsUnknown(status: number): boolean {
  return status === 408 || status === 409 || status === 425 || status === 429 ||
    status >= 500;
}
