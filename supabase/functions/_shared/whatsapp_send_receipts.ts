export interface DurableWhatsAppSendReceipt {
  ok: true;
  accepted: true;
  queued: false;
  message_id: string;
  external_message_id: string;
}

function requiredId(value: string | null | undefined, label: string) {
  const normalized = value?.trim() ?? "";
  if (!normalized) {
    throw new Error(`durable_whatsapp_send_missing_${label}`);
  }
  return normalized;
}

// A successful HTTP response is a durable receipt, not a queue acknowledgement.
// Both identifiers are required so the optimistic Flutter row can reconcile
// with a local database message and with Meta's provider lifecycle.
export function durableWhatsAppSendReceipt(params: {
  messageId?: string | null;
  externalMessageId?: string | null;
}): DurableWhatsAppSendReceipt {
  return {
    ok: true,
    accepted: true,
    queued: false,
    message_id: requiredId(params.messageId, "message_id"),
    external_message_id: requiredId(
      params.externalMessageId,
      "external_message_id",
    ),
  };
}

export function whatsappProviderFailureHttpStatus(params: {
  providerStatus?: number | null;
  outcomeUnknown?: boolean;
}) {
  if (params.outcomeUnknown || params.providerStatus === 429) {
    return 503;
  }
  return 502;
}
