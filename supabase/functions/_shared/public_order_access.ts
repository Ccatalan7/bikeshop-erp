type JsonRecord = Record<string, unknown>;

export interface PublicOrderAccessRpcClient {
  rpc(
    functionName: string,
    params: JsonRecord,
  ): PromiseLike<{
    data: unknown;
    error: { message?: string } | null;
  }>;
}

export class PublicOrderAccessDeniedError extends Error {
  constructor() {
    super("Order access denied");
    this.name = "PublicOrderAccessDeniedError";
  }
}

function record(value: unknown): JsonRecord {
  return value != null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : {};
}

export function normalizePublicOrderAccessInput(value: unknown): {
  orderId: string;
  orderAccessToken: string;
} {
  const body = record(value);
  const orderId = typeof body.order_id === "string" ? body.order_id.trim().toLowerCase() : "";
  const orderAccessToken = typeof body.order_access_token === "string"
    ? body.order_access_token.trim()
    : "";

  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(
      orderId,
    ) ||
    !/^[A-Za-z0-9_-]{40,128}$/.test(orderAccessToken)
  ) {
    throw new PublicOrderAccessDeniedError();
  }

  return { orderId, orderAccessToken };
}

/**
 * Authorize the opaque checkout token before any service-role table read.
 * The returned projection intentionally contains no tenant/customer PII.
 */
export async function authorizePublicOrderAccess(
  client: PublicOrderAccessRpcClient,
  value: unknown,
): Promise<{
  orderId: string;
  orderAccessToken: string;
  projection: JsonRecord;
}> {
  const normalized = normalizePublicOrderAccessInput(value);
  const { data, error } = await client.rpc(
    "get_public_online_order_by_access_token",
    { p_token: normalized.orderAccessToken },
  );

  const projection = record(data);
  const order = record(projection.order);
  if (error != null || order.id !== normalized.orderId) {
    throw new PublicOrderAccessDeniedError();
  }

  return { ...normalized, projection };
}
