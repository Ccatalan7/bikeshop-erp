export type MetaSendAttemptState =
  | "prepared"
  | "preflight_failed"
  | "provider_accepted"
  | "finalized"
  | "provider_rejected"
  | "outcome_unknown";

export interface MetaSendAttemptReceipt {
  attempt_id: string;
  state: MetaSendAttemptState;
  message_id?: string | null;
  client_message_id?: string | null;
  external_message_id?: string | null;
  external_status?: string | null;
  error_code?: string | null;
  error_message?: string | null;
}

export function durableMetaSendSuccess(receipt: MetaSendAttemptReceipt) {
  return {
    ok: true,
    accepted: true,
    provider_accepted: true,
    outcome_unknown: false,
    retry_safe: false,
    attempt_id: receipt.attempt_id,
    message_id: receipt.message_id ?? null,
    client_message_id: receipt.client_message_id ?? null,
    external_message_id: receipt.external_message_id ?? null,
    external_status: receipt.external_status ?? "accepted",
  };
}

export function replayedMetaSendResponse(receipt: MetaSendAttemptReceipt): {
  status: number;
  body: Record<string, unknown>;
} {
  if (receipt.state === "finalized" && receipt.message_id) {
    return { status: 200, body: durableMetaSendSuccess(receipt) };
  }
  if (
    receipt.state === "preflight_failed" ||
    receipt.state === "provider_rejected"
  ) {
    return {
      status: 409,
      body: {
        ok: false,
        accepted: false,
        provider_accepted: false,
        outcome_unknown: false,
        retry_safe: true,
        attempt_id: receipt.attempt_id,
        error: {
          code: receipt.error_code ??
            (receipt.state === "preflight_failed" ? "preflight_failed" : "provider_rejected"),
          message: receipt.error_message ??
            (receipt.state === "preflight_failed"
              ? "El mensaje no se envió a Meta."
              : "Meta rechazó el mensaje."),
        },
      },
    };
  }
  if (receipt.state === "provider_accepted" && receipt.external_message_id) {
    return {
      status: 202,
      body: {
        ok: true,
        accepted: true,
        provider_accepted: true,
        outcome_unknown: false,
        retry_safe: false,
        persistence_pending: true,
        attempt_id: receipt.attempt_id,
        message_id: receipt.message_id ?? null,
        client_message_id: receipt.client_message_id ?? null,
        external_message_id: receipt.external_message_id,
        external_status: "accepted",
      },
    };
  }
  return {
    status: 409,
    body: {
      ok: false,
      accepted: false,
      provider_accepted: receipt.state === "provider_accepted",
      outcome_unknown: true,
      retry_safe: false,
      attempt_id: receipt.attempt_id,
      error: {
        code: "send_outcome_unknown",
        message: "No se reenviará automáticamente porque Meta podría haber aceptado el mensaje.",
      },
    },
  };
}

export function metaProviderFailureHttpStatus(providerStatus: number) {
  if (providerStatus === 401 || providerStatus === 403) return 502;
  if (providerStatus === 429) return 429;
  if (providerStatus >= 400 && providerStatus < 500) return 409;
  return 502;
}

export function metaProviderFailureDisposition(providerStatus: number) {
  const outcomeUnknown = providerStatus >= 500;
  return {
    attemptState: outcomeUnknown ? "outcome_unknown" : "provider_rejected",
    outcomeUnknown,
    retrySafe: !outcomeUnknown,
  } as const;
}
