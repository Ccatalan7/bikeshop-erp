export type MercadoPagoProcessingResult = {
  payment_id: string;
  processing_state: string | null;
};

function boundedText(value: unknown, maxLength: number): string | null {
  if (typeof value !== "string") return null;

  const redacted = value
    .replace(/[\r\n\t]+/g, " ")
    .replace(/bearer\s+[^\s,;]+/gi, "Bearer [redacted]")
    .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, "[redacted-email]")
    .replace(
      /\b(access[_ -]?token|authorization|client[_ -]?secret)\b\s*[:=]\s*[^\s,;]+/gi,
      "$1=[redacted]",
    )
    .replace(/\s+/g, " ")
    .trim();

  return redacted ? redacted.slice(0, maxLength) : null;
}

function boundedCode(value: unknown): string | null {
  const code = boundedText(value, 80);
  if (!code) return null;
  return /^[a-z0-9_.:-]+$/i.test(code) ? code : null;
}

/**
 * Reduces an untrusted Mercado Pago error body to a bounded operational
 * summary. The raw response is never returned or logged.
 */
export function summarizeMercadoPagoApiError(
  payload: unknown,
  label: string,
  status: number,
): string {
  const object = payload && typeof payload === "object" && !Array.isArray(payload)
    ? payload as Record<string, unknown>
    : null;
  const code = boundedCode(object?.error) ?? boundedCode(object?.code);
  const message = boundedText(object?.message, 160) ??
    `Mercado Pago ${boundedText(label, 40) ?? "resource"} request failed`;

  return [`HTTP ${status}`, code, message].filter(Boolean).join(" · ");
}

/** Merchant-order notifications can contain several attempts. Process every
 * unique numeric payment id instead of trusting array position zero. */
export function uniqueMercadoPagoPaymentIds(payments: unknown): string[] {
  if (!Array.isArray(payments)) return [];

  const unique = new Set<string>();
  for (const candidate of payments) {
    if (!candidate || typeof candidate !== "object") continue;
    const rawId = (candidate as Record<string, unknown>).id;
    const id = typeof rawId === "number" && Number.isSafeInteger(rawId)
      ? String(rawId)
      : typeof rawId === "string"
      ? rawId.trim()
      : "";
    if (/^[0-9]{1,64}$/.test(id)) unique.add(id);
  }
  return [...unique];
}

export function merchantOrderProcessingState(
  results: MercadoPagoProcessingResult[],
): string | null {
  if (results.some((result) => result.processing_state === "action_required")) {
    return "action_required";
  }
  if (results.some((result) => result.processing_state === "pending")) {
    return "pending";
  }
  return results.length > 0 ? "processed" : null;
}
