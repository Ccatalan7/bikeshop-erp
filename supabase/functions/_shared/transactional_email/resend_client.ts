export type ResendSendOutcome =
  | { kind: "submitted"; providerMessageId: string }
  | { kind: "retry"; errorClass: string; message: string; retryAfterSeconds?: number }
  | { kind: "permanent_failure"; errorClass: string; message: string };

export interface ResendMessage {
  apiKey: string;
  idempotencyKey: string;
  from: string;
  to: string;
  replyTo?: string;
  subject: string;
  html: string;
  text: string;
  tags: Array<{ name: string; value: string }>;
}

function retryAfterSeconds(response: Response): number | undefined {
  const value = response.headers.get("retry-after");
  if (!value) return undefined;
  const seconds = Number(value);
  if (Number.isFinite(seconds)) return Math.max(1, Math.round(seconds));
  const date = Date.parse(value);
  if (!Number.isFinite(date)) return undefined;
  return Math.max(1, Math.ceil((date - Date.now()) / 1000));
}

type ResendResponseDetail = {
  id?: string;
  errorCode?: string;
  message: string;
};

async function responseMessage(response: Response): Promise<ResendResponseDetail> {
  const raw = await response.text();
  if (!raw) return { message: `Resend returned HTTP ${response.status}` };
  try {
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    return {
      id: typeof parsed.id === "string" ? parsed.id : undefined,
      errorCode: typeof parsed.name === "string"
        ? parsed.name
        : typeof parsed.code === "string"
        ? parsed.code
        : undefined,
      message: typeof parsed.message === "string"
        ? parsed.message
        : `Resend returned HTTP ${response.status}`,
    };
  } catch {
    return { message: `Resend returned HTTP ${response.status}` };
  }
}

export async function sendWithResend(
  message: ResendMessage,
  fetchImpl: typeof fetch = fetch,
): Promise<ResendSendOutcome> {
  try {
    const response = await fetchImpl("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${message.apiKey}`,
        "Content-Type": "application/json",
        "Idempotency-Key": message.idempotencyKey,
      },
      body: JSON.stringify({
        from: message.from,
        to: [message.to],
        reply_to: message.replyTo,
        subject: message.subject,
        html: message.html,
        text: message.text,
        tags: message.tags,
      }),
      signal: AbortSignal.timeout(15_000),
    });
    const detail = await responseMessage(response);

    if ((response.ok || response.status === 409) && detail.id) {
      return { kind: "submitted", providerMessageId: detail.id };
    }

    // Resend has two distinct 409 contracts. A concurrent request with the
    // same idempotency key is safe to retry; a reused key with a different
    // payload is permanently invalid. Do not collapse both into one outcome.
    if (
      response.status === 409 &&
      detail.errorCode === "concurrent_idempotent_requests"
    ) {
      return {
        kind: "retry",
        errorClass: "resend_concurrent_idempotent_request",
        message: detail.message,
        retryAfterSeconds: retryAfterSeconds(response) ?? 2,
      };
    }

    if (
      response.status === 408 || response.status === 425 || response.status === 429 ||
      response.status >= 500
    ) {
      return {
        kind: "retry",
        errorClass: `resend_http_${response.status}`,
        message: detail.message,
        retryAfterSeconds: retryAfterSeconds(response),
      };
    }

    return {
      kind: "permanent_failure",
      errorClass: `resend_http_${response.status}`,
      message: detail.message,
    };
  } catch (error) {
    const messageText = error instanceof Error ? error.message : "Unknown network error";
    return {
      kind: "retry",
      errorClass: error instanceof DOMException && error.name === "TimeoutError"
        ? "resend_timeout"
        : "resend_network_error",
      message: messageText,
    };
  }
}
