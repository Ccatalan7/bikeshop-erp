type JsonRecord = Record<string, unknown>;

export type MercadoPagoPaymentVoucherAvailability =
  | "available"
  | "absent"
  | "rejected_unsafe"
  | "incomplete"
  | "not_applicable";

export type MercadoPagoPaymentVoucherObservation = {
  source: "transaction_details.external_resource_url";
  availability: MercadoPagoPaymentVoucherAvailability;
  fiscal_validity: "not_a_tax_document";
  reason?: string;
  url?: string;
};

export type MercadoPagoPaymentVoucherCandidate = {
  paymentId: string;
  amount: number;
  currency: string;
  issuedAt: string;
  url: string;
  statusDetail: string | null;
  observation: MercadoPagoPaymentVoucherObservation;
};

export type MercadoPagoPaymentVoucherInspection = {
  observation: MercadoPagoPaymentVoucherObservation;
  candidate: MercadoPagoPaymentVoucherCandidate | null;
};

type RpcResult = {
  data: unknown;
  error: { message?: string } | null;
};

export type MercadoPagoVoucherRpcClient = {
  rpc: (name: string, args: JsonRecord) => PromiseLike<RpcResult>;
};

const source = "transaction_details.external_resource_url" as const;
const nonTaxValidity = "not_a_tax_document" as const;
const supportedHost = /(^|\.)(mercadopago|mercadolibre)\.(cl|com(?:\.[a-z]{2})?)$/i;
const credentialQueryName =
  /(^|[_-])(access[_-]?token|token|api[_-]?key|secret|signature|sig|authorization|auth|password|credential)([_-]|$)/i;

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

function unavailable(
  availability: Exclude<MercadoPagoPaymentVoucherAvailability, "available">,
  reason: string,
): MercadoPagoPaymentVoucherInspection {
  return {
    observation: {
      source,
      availability,
      fiscal_validity: nonTaxValidity,
      reason,
    },
    candidate: null,
  };
}

/**
 * Accept only a credential-free public Mercado Pago/Mercado Libre HTTPS link.
 * The provider response is trusted for payment truth, but never as authority
 * to make an arbitrary host fetchable or customer-clickable.
 */
export function safeMercadoPagoPaymentVoucherUrl(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const candidate = value.trim();
  if (!candidate || candidate.length > 2048) return null;

  try {
    const url = new URL(candidate);
    if (
      url.protocol !== "https:" || !url.hostname || url.port || url.username ||
      url.password || url.hash || !supportedHost.test(url.hostname)
    ) {
      return null;
    }
    for (const key of url.searchParams.keys()) {
      if (credentialQueryName.test(key)) return null;
    }
    return url.toString();
  } catch {
    return null;
  }
}

/**
 * Classify the provider field without ever claiming Chilean fiscal validity.
 * A safe, complete link is a Mercado Pago payment receipt only. It is not a
 * boleta or DTE unless the independent verified SII flow records that artifact.
 */
export function inspectMercadoPagoPaymentVoucher(
  rawPayment: unknown,
): MercadoPagoPaymentVoucherInspection {
  const payment = record(rawPayment);
  const status = optionalText(payment.status)?.toLowerCase() ?? "";
  const transactionDetails = record(payment.transaction_details);
  const rawUrl = optionalText(transactionDetails.external_resource_url);

  if (status !== "approved") {
    return unavailable("not_applicable", "payment_not_approved");
  }
  if (!rawUrl) {
    return unavailable("absent", "provider_field_missing");
  }

  const url = safeMercadoPagoPaymentVoucherUrl(rawUrl);
  if (!url) {
    return unavailable("rejected_unsafe", "unsafe_or_credentialed_url");
  }

  const paymentId = optionalText(payment.id);
  const amount = typeof payment.transaction_amount === "number"
    ? payment.transaction_amount
    : Number(payment.transaction_amount);
  const currency = optionalText(payment.currency_id)?.toUpperCase() ?? "";
  const approvedAt = optionalText(payment.date_approved);
  if (
    !paymentId || paymentId.length > 160 || !Number.isFinite(amount) ||
    amount <= 0 || !/^[A-Z]{3}$/.test(currency) || !approvedAt ||
    Number.isNaN(Date.parse(approvedAt))
  ) {
    return unavailable("incomplete", "approved_payment_fields_incomplete");
  }

  const observation: MercadoPagoPaymentVoucherObservation = {
    source,
    availability: "available",
    fiscal_validity: nonTaxValidity,
    url,
  };

  return {
    observation,
    candidate: {
      paymentId,
      amount,
      currency,
      issuedAt: new Date(approvedAt).toISOString(),
      url,
      statusDetail: optionalText(payment.status_detail),
      observation,
    },
  };
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * Append the provider-hosted non-fiscal receipt only after the durable payment
 * observation and sale processor agree that this validated payment is paid.
 * The canonical ledger trigger owns email enqueueing; this helper never writes
 * the transactional outbox directly.
 */
export async function recordMercadoPagoPaymentVoucherIfAvailable(args: {
  supabase: MercadoPagoVoucherRpcClient;
  payment: unknown;
  tenantId: string;
  orderId: string;
  eventResult: unknown;
  processingResult: unknown;
}): Promise<{
  recorded: boolean;
  availability: MercadoPagoPaymentVoucherAvailability;
  documentId?: string;
}> {
  const inspection = inspectMercadoPagoPaymentVoucher(args.payment);
  const eventResult = record(args.eventResult);
  const processingResult = record(args.processingResult);
  const eventOutcome = optionalText(eventResult.outcome) ?? "";
  const processingState = optionalText(processingResult.processing_state) ?? "";
  const paymentStatus = optionalText(processingResult.payment_status) ?? "";
  const validated = ["payment_validated", "applied"].includes(eventOutcome);
  const safelyPaid = paymentStatus === "paid" ||
    (processingState === "processed" && validated);

  if (!inspection.candidate || !validated || !safelyPaid) {
    return {
      recorded: false,
      availability: inspection.observation.availability,
    };
  }

  const voucher = inspection.candidate;
  const referenceSha256 = await sha256Hex(voucher.url);
  const { data, error } = await args.supabase.rpc(
    "record_online_order_official_document",
    {
      p_tenant_id: args.tenantId,
      p_order_id: args.orderId,
      p_document_kind: "mercadopago_payment_voucher",
      p_provider: "mercadopago",
      p_provider_document_id: `payment:${voucher.paymentId}`,
      p_fiscal_validity: nonTaxValidity,
      p_amount: voucher.amount,
      p_currency: voucher.currency,
      p_issued_at: voucher.issuedAt,
      p_artifact_url: voucher.url,
      // This hashes the immutable reference, not the remote bytes. The schema
      // records artifact_hash_scope=reference_url for this document kind.
      p_artifact_sha256: referenceSha256,
      p_status: "approved",
      p_source_event_key: `mercadopago_payment_voucher:${voucher.paymentId}`,
      p_payment_operation_id: voucher.paymentId,
      p_document_type: null,
      p_folio: null,
      p_metadata: {
        source,
        provider_event_id: optionalText(eventResult.event_id),
        provider_status_detail: voucher.statusDetail,
        provider_created_at: voucher.issuedAt,
      },
      p_voucher_fiscal_evidence: null,
    },
  );

  if (error) {
    throw new Error(
      `Mercado Pago payment voucher recording failed: ${error.message ?? "unknown error"}`,
    );
  }

  return {
    recorded: true,
    availability: "available",
    documentId: typeof data === "string" ? data : undefined,
  };
}
