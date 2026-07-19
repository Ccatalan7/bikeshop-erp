import {
  parseMercadoPagoExternalReference,
  paymentOrderIdentity,
} from "./mercadopago_preference.ts";

type JsonRecord = Record<string, unknown>;

export type MercadoPagoProviderPreference = {
  id: string;
  initPoint: string;
  sandboxInitPoint: string | null;
  createdAt: string | null;
  expiresAt: string;
  externalReference: string;
};

function record(value: unknown): JsonRecord {
  return value != null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : {};
}

function boundedText(value: unknown, maximum: number): string | null {
  if (typeof value !== "string" && typeof value !== "number") return null;
  const normalized = String(value).trim();
  return normalized && normalized.length <= maximum ? normalized : null;
}

function wholeClp(value: unknown): number | null {
  const amount = typeof value === "number" ? value : Number(value);
  return Number.isSafeInteger(amount) && amount >= 0 ? amount : null;
}

export function trustedMercadoPagoCheckoutUrl(value: unknown): string | null {
  const raw = boundedText(value, 2048);
  if (!raw) return null;
  try {
    const url = new URL(raw);
    if (url.protocol !== "https:" || url.username || url.password) return null;
    const host = url.hostname.toLowerCase();
    if (!/(^|\.)mercadopago\.(com(\.[a-z]{2})?|[a-z]{2})$/.test(host)) {
      return null;
    }
    return url.toString();
  } catch {
    return null;
  }
}

function providerChargeTotal(preference: JsonRecord): number | null {
  const items = Array.isArray(preference.items) ? preference.items : [];
  if (items.length === 0) return null;

  let total = 0;
  for (const rawItem of items) {
    const item = record(rawItem);
    const quantity = wholeClp(item.quantity);
    const unitPrice = wholeClp(item.unit_price);
    if (quantity == null || quantity <= 0 || unitPrice == null || unitPrice <= 0) {
      return null;
    }
    total += quantity * unitPrice;
    if (!Number.isSafeInteger(total)) return null;
  }

  const shipment = record(preference.shipments);
  const shippingCost = shipment.cost == null ? 0 : wholeClp(shipment.cost);
  return shippingCost == null ? null : total + shippingCost;
}

/**
 * Validate a provider resource before adopting it during lost-ack recovery.
 * Search results are never trusted by position: the full GET response must
 * carry the exact tenant/order/generation reference, CLP total and expiry.
 */
export function parseRecoverableMercadoPagoPreference(
  rawPreference: unknown,
  expected: {
    externalReference: string;
    amount: number;
    expiresAt: string;
  },
): MercadoPagoProviderPreference | null {
  const preference = record(rawPreference);
  const externalReference = boundedText(preference.external_reference, 150);
  if (!externalReference || externalReference !== expected.externalReference) return null;

  const expectedIdentity = parseMercadoPagoExternalReference(expected.externalReference);
  const metadata = record(preference.metadata);
  const actualIdentity = paymentOrderIdentity({
    external_reference: externalReference,
    metadata,
  });
  if (
    !expectedIdentity ||
    expectedIdentity.legacy ||
    !actualIdentity ||
    actualIdentity.tenantId !== expectedIdentity.tenantId ||
    actualIdentity.orderId !== expectedIdentity.orderId ||
    actualIdentity.generation !== expectedIdentity.generation ||
    metadata.tenant_id !== expectedIdentity.tenantId ||
    metadata.online_order_id !== expectedIdentity.orderId ||
    Number(metadata.preference_generation) !== expectedIdentity.generation
  ) {
    return null;
  }

  const id = boundedText(preference.id, 160);
  const initPoint = trustedMercadoPagoCheckoutUrl(preference.init_point);
  const sandboxInitPoint = preference.sandbox_init_point == null
    ? null
    : trustedMercadoPagoCheckoutUrl(preference.sandbox_init_point);
  const expiresAt = boundedText(preference.expiration_date_to, 64);
  if (!id || !initPoint || !expiresAt) return null;

  const providerExpiry = Date.parse(expiresAt);
  const expectedExpiry = Date.parse(expected.expiresAt);
  if (
    !Number.isFinite(providerExpiry) ||
    !Number.isFinite(expectedExpiry) ||
    Math.abs(providerExpiry - expectedExpiry) > 60_000
  ) {
    return null;
  }

  if (providerChargeTotal(preference) !== expected.amount) return null;

  return {
    id,
    initPoint,
    sandboxInitPoint,
    createdAt: boundedText(preference.date_created, 64),
    expiresAt: new Date(providerExpiry).toISOString(),
    externalReference,
  };
}

export function preferenceSearchIds(payload: unknown): string[] {
  const elements = Array.isArray(record(payload).elements)
    ? record(payload).elements as unknown[]
    : [];
  const ids = new Set<string>();
  for (const rawElement of elements) {
    const id = boundedText(record(rawElement).id, 160);
    if (id && /^[A-Za-z0-9_-]+$/.test(id)) ids.add(id);
  }
  return [...ids];
}

export function expireMercadoPagoPreferencePayload(
  now: Date,
  originalEffectiveFrom: string | null,
) {
  const nowMs = now.getTime();
  if (!Number.isFinite(nowMs)) throw new Error("Invalid preference expiration time");
  const parsedFrom = originalEffectiveFrom ? Date.parse(originalEffectiveFrom) : Number.NaN;
  const effectiveFromMs = Number.isFinite(parsedFrom) && parsedFrom < nowMs
    ? parsedFrom
    : nowMs - 60_000;

  return {
    expires: true,
    expiration_date_from: new Date(effectiveFromMs).toISOString(),
    // A very small future skew avoids provider clock-boundary rejection while
    // still making the link unusable before the worker returns it anywhere.
    expiration_date_to: new Date(nowMs + 5_000).toISOString(),
  };
}
