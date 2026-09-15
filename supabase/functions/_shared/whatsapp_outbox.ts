/** A modern project secret is injected by the Edge runtime. Never add a new
 * consumer of the compromised legacy service_role JWT. */
export function runtimeSecretKey(raw: string | undefined): string {
  const keys: unknown = JSON.parse(raw ?? "{}");
  if (!keys || typeof keys !== "object" || Array.isArray(keys)) {
    throw new Error("Missing modern Edge runtime secret key");
  }
  const key = Object.values(keys).find((value) =>
    typeof value === "string" && value.startsWith("sb_secret_")
  );
  if (typeof key !== "string") throw new Error("Missing modern Edge runtime secret key");
  return key;
}

export function validOutboxDispatch(body: unknown): body is { message_id: string; token: string } {
  if (!body || typeof body !== "object") return false;
  const value = body as Record<string, unknown>;
  return typeof value.message_id === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value.message_id) &&
    typeof value.token === "string" && /^[0-9a-f]{64}$/.test(value.token);
}

/** Retry only a definite refusal. A timeout, 5xx or malformed success may have
 * reached Meta, so it cannot be treated as permission to send another copy. */
export function outboxCompletionStatus(patch: {
  externalStatus: "accepted" | "failed" | null;
  metadata: Record<string, unknown>;
}): "accepted" | "failed" | "outcome_unknown" | "retry" {
  if (patch.externalStatus === "accepted") return "accepted";
  if (patch.externalStatus === null) return "outcome_unknown";
  return patch.metadata.provider_http_status === 429 ? "retry" : "failed";
}
