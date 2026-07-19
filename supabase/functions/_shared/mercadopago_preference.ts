export type MercadoPagoOrderChargeSnapshot = {
  total: unknown;
  shipping_cost: unknown;
  discount_amount: unknown;
  delivery_type?: unknown;
};

export type MercadoPagoOrderItemSnapshot = {
  product_id: unknown;
  product_name: unknown;
  product_sku: unknown;
  quantity: unknown;
  unit_price: unknown;
  subtotal: unknown;
};

export type MercadoPagoPreferenceItem = {
  id: string;
  title: string;
  quantity: number;
  unit_price: number;
  currency_id: "CLP";
};

export type MercadoPagoChargeReconciliation = {
  items: MercadoPagoPreferenceItem[];
  itemGrossTotal: number;
  shippingCost: number;
  discountAmount: number;
  chargeTotal: number;
};

export type MercadoPagoPaymentMethodPolicy = {
  excluded_payment_types: Array<{ id: "ticket" }>;
};

export type MercadoPagoPreferenceIdentity = {
  tenantId: string | null;
  orderId: string;
  generation: number | null;
  legacy: boolean;
};

export type MercadoPagoPreferenceWindow = {
  effectiveFrom: string;
  expiresAt: string;
  ttlMinutes: number;
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export const mercadoPagoPreferenceTtl = {
  defaultMinutes: 30,
  minimumMinutes: 5,
  maximumMinutes: 60,
  minimumRemainingSeconds: 90,
} as const;

export function normalizeMercadoPagoPreferenceTtl(value: unknown): number {
  const parsed = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(parsed)) return mercadoPagoPreferenceTtl.defaultMinutes;
  return Math.min(
    mercadoPagoPreferenceTtl.maximumMinutes,
    Math.max(mercadoPagoPreferenceTtl.minimumMinutes, Math.trunc(parsed)),
  );
}

/**
 * Provider references carry tenant + order + generation so a global webhook
 * secret never has to infer tenant ownership from a client-supplied UUID.
 * Raw UUID references remain readable for payments created before this format.
 */
export function buildMercadoPagoExternalReference(
  tenantId: string,
  orderId: string,
  generation: number,
): string {
  if (!uuidPattern.test(tenantId) || !uuidPattern.test(orderId)) {
    throw new Error("Mercado Pago reference requires valid tenant and order identifiers");
  }
  if (!Number.isSafeInteger(generation) || generation <= 0 || generation > 999_999) {
    throw new Error("Mercado Pago reference generation is invalid");
  }
  return `vb1:${tenantId.toLowerCase()}:${orderId.toLowerCase()}:${generation}`;
}

export function parseMercadoPagoExternalReference(
  value: unknown,
): MercadoPagoPreferenceIdentity | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim();

  if (uuidPattern.test(normalized)) {
    return {
      tenantId: null,
      orderId: normalized.toLowerCase(),
      generation: null,
      legacy: true,
    };
  }

  const parts = normalized.split(":");
  if (
    parts.length !== 4 ||
    parts[0] !== "vb1" ||
    !uuidPattern.test(parts[1]) ||
    !uuidPattern.test(parts[2]) ||
    !/^[1-9][0-9]{0,5}$/.test(parts[3])
  ) {
    return null;
  }

  return {
    tenantId: parts[1].toLowerCase(),
    orderId: parts[2].toLowerCase(),
    generation: Number(parts[3]),
    legacy: false,
  };
}

export function mercadoPagoPreferenceWindow(params: {
  now: Date;
  ttlMinutes: unknown;
  reservationExpiresAt: Date;
}): MercadoPagoPreferenceWindow {
  const nowMs = params.now.getTime();
  const reservationMs = params.reservationExpiresAt.getTime();
  if (!Number.isFinite(nowMs) || !Number.isFinite(reservationMs)) {
    throw new Error("Mercado Pago preference dates are invalid");
  }

  const ttlMinutes = normalizeMercadoPagoPreferenceTtl(params.ttlMinutes);
  const requestedExpiryMs = nowMs + ttlMinutes * 60_000;
  const expiresMs = Math.min(requestedExpiryMs, reservationMs);
  if (
    expiresMs - nowMs < mercadoPagoPreferenceTtl.minimumRemainingSeconds * 1000
  ) {
    throw new Error("The inventory reservation is too close to expiry");
  }

  return {
    effectiveFrom: new Date(nowMs).toISOString(),
    expiresAt: new Date(expiresMs).toISOString(),
    ttlMinutes,
  };
}

export function preferenceBelongsToOrder(
  externalReference: unknown,
  tenantId: string,
  orderId: string,
): boolean {
  const identity = parseMercadoPagoExternalReference(externalReference);
  if (!identity || identity.orderId !== orderId.toLowerCase()) return false;
  return identity.legacy || identity.tenantId === tenantId.toLowerCase();
}

function record(value: unknown): Record<string, unknown> {
  return value != null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

/** Resolve the server identity carried by a provider payment and reject
 * conflicting metadata instead of silently preferring one attacker-controlled
 * field over another. */
export function paymentOrderIdentity(
  rawPayment: unknown,
): MercadoPagoPreferenceIdentity | null {
  const payment = record(rawPayment);
  const identity = parseMercadoPagoExternalReference(payment.external_reference);
  if (!identity) return null;

  const metadata = record(payment.metadata);
  const metadataTenant = typeof metadata.tenant_id === "string"
    ? metadata.tenant_id.trim().toLowerCase()
    : "";
  const metadataOrder = typeof metadata.online_order_id === "string"
    ? metadata.online_order_id.trim().toLowerCase()
    : "";
  const metadataGeneration = metadata.preference_generation == null
    ? null
    : Number(metadata.preference_generation);

  if (metadataOrder && metadataOrder !== identity.orderId) return null;
  if (
    identity.tenantId &&
    metadataTenant &&
    metadataTenant !== identity.tenantId
  ) {
    return null;
  }
  if (
    metadataGeneration != null &&
    identity.generation != null &&
    (!Number.isSafeInteger(metadataGeneration) ||
      metadataGeneration !== identity.generation)
  ) {
    return null;
  }

  return {
    ...identity,
    tenantId: identity.tenantId || (uuidPattern.test(metadataTenant) ? metadataTenant : null),
  };
}

/**
 * Checkout Pro enables every payment type by default. Viñabike accepts the
 * online card/account-balance rails here; cash/offline ticket methods are
 * deliberately excluded so payment confirmation stays webhook-verifiable.
 */
export function mercadoPagoPaymentMethodPolicy(): MercadoPagoPaymentMethodPolicy {
  return {
    excluded_payment_types: [{ id: "ticket" }],
  };
}

function clpAmount(value: unknown, field: string, options: {
  positive?: boolean;
  nonNegative?: boolean;
} = {}): number {
  const amount = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(amount) || !Number.isSafeInteger(amount)) {
    throw new Error(`${field} must be a whole CLP amount`);
  }
  if (options.positive && amount <= 0) {
    throw new Error(`${field} must be positive`);
  }
  if (options.nonNegative && amount < 0) {
    throw new Error(`${field} cannot be negative`);
  }
  return amount;
}

function positiveInteger(value: unknown, field: string): number {
  const quantity = typeof value === "number" ? value : Number(value);
  if (!Number.isSafeInteger(quantity) || quantity <= 0) {
    throw new Error(`${field} must be a positive whole number`);
  }
  return quantity;
}

/**
 * Builds the server-owned Mercado Pago charge and proves that it reconciles to
 * the immutable order snapshot. When a discount exists it is allocated over
 * the gross item lines and each discounted line is sent as one summarized MP
 * item. This avoids relying on an undocumented negative-price item while still
 * charging exactly `items + shipping - discount`.
 */
export function buildMercadoPagoCharge(
  order: MercadoPagoOrderChargeSnapshot,
  rawItems: MercadoPagoOrderItemSnapshot[],
): MercadoPagoChargeReconciliation {
  if (!Array.isArray(rawItems) || rawItems.length === 0) {
    throw new Error("Order has no items");
  }

  const total = clpAmount(order.total, "Order total", { positive: true });
  const shippingCost = clpAmount(order.shipping_cost ?? 0, "Shipping cost", {
    nonNegative: true,
  });
  const discountAmount = clpAmount(
    order.discount_amount ?? 0,
    "Discount amount",
    { nonNegative: true },
  );
  const deliveryType = typeof order.delivery_type === "string"
    ? order.delivery_type.trim().toLowerCase()
    : "";
  if (shippingCost > 0 && deliveryType !== "shipping") {
    throw new Error("Pickup orders cannot include a shipping charge");
  }

  const normalized = rawItems.map((item, index) => {
    const quantity = positiveInteger(item.quantity, `Item ${index + 1} quantity`);
    const unitPrice = clpAmount(item.unit_price, `Item ${index + 1} unit price`, {
      positive: true,
    });
    const subtotal = clpAmount(item.subtotal, `Item ${index + 1} subtotal`, {
      positive: true,
    });
    if (unitPrice * quantity !== subtotal) {
      throw new Error(`Item ${index + 1} subtotal does not match quantity and price`);
    }

    const productId = typeof item.product_id === "string" ? item.product_id.trim() : "";
    const sku = typeof item.product_sku === "string" ? item.product_sku.trim() : "";
    const name = typeof item.product_name === "string" ? item.product_name.trim() : "";
    if (!productId || !name) {
      throw new Error(`Item ${index + 1} is missing its server-owned identity`);
    }

    return {
      id: sku || productId,
      name,
      quantity,
      unitPrice,
      subtotal,
      index,
    };
  });

  const itemGrossTotal = normalized.reduce((sum, item) => sum + item.subtotal, 0);
  if (!Number.isSafeInteger(itemGrossTotal) || itemGrossTotal <= 0) {
    throw new Error("Order item total is invalid");
  }
  if (discountAmount >= itemGrossTotal) {
    throw new Error("Discount must be lower than the gross item total");
  }

  const expectedTotal = itemGrossTotal + shippingCost - discountAmount;
  if (!Number.isSafeInteger(expectedTotal) || expectedTotal !== total) {
    throw new Error("Order charges do not reconcile: items + shipping - discount != total");
  }

  if (discountAmount === 0) {
    return {
      items: normalized.map((item) => ({
        id: item.id,
        title: item.name,
        quantity: item.quantity,
        unit_price: item.unitPrice,
        currency_id: "CLP",
      })),
      itemGrossTotal,
      shippingCost,
      discountAmount,
      chargeTotal: expectedTotal,
    };
  }

  // Largest-remainder allocation keeps every amount in whole CLP and makes
  // the allocation deterministic even when the proportional shares tie.
  const allocations = normalized.map((item) => {
    const exactNumerator = BigInt(discountAmount) * BigInt(item.subtotal);
    const grossDenominator = BigInt(itemGrossTotal);
    const base = Number(exactNumerator / grossDenominator);
    return {
      index: item.index,
      base,
      remainder: exactNumerator % grossDenominator,
    };
  });
  let remainder = discountAmount - allocations.reduce((sum, entry) => sum + entry.base, 0);
  const remainderOrder = [...allocations].sort((left, right) => {
    if (left.remainder === right.remainder) return left.index - right.index;
    return left.remainder > right.remainder ? -1 : 1;
  });
  for (const entry of remainderOrder) {
    if (remainder <= 0) break;
    entry.base += 1;
    remainder -= 1;
  }
  if (remainder !== 0) {
    throw new Error("Discount allocation could not be reconciled");
  }

  const discountByIndex = new Map(allocations.map((entry) => [entry.index, entry.base]));
  const items = normalized.map((item) => {
    const discountedLineTotal = item.subtotal - (discountByIndex.get(item.index) ?? 0);
    if (discountedLineTotal <= 0) {
      throw new Error("Discount allocation produced a non-positive Mercado Pago item");
    }
    return {
      id: item.id,
      title: item.quantity === 1 ? item.name : `${item.name} × ${item.quantity}`,
      quantity: 1,
      unit_price: discountedLineTotal,
      currency_id: "CLP" as const,
    };
  });

  const providerItemTotal = items.reduce(
    (sum, item) => sum + item.quantity * item.unit_price,
    0,
  );
  if (providerItemTotal + shippingCost !== total) {
    throw new Error("Mercado Pago preference amount does not reconcile to order total");
  }

  return {
    items,
    itemGrossTotal,
    shippingCost,
    discountAmount,
    chargeTotal: expectedTotal,
  };
}
