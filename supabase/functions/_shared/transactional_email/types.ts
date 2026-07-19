export const transactionalTemplateKeys = [
  "order_received",
  "payment_confirmed",
  "processing",
  "ready_for_pickup",
  "shipped",
  "delivered",
  "cancelled",
  "refund_completed",
  "mercadopago_payment_voucher_available",
  "payment_voucher_available",
  "tax_document_issued",
] as const;

export type TransactionalTemplateKey = typeof transactionalTemplateKeys[number];

// Keep this list aligned with the production Resend webhook subscription.
// Engagement-only events (opened/clicked) do not change order-delivery truth.
export const resendOperationalEmailEvents = [
  "email.sent",
  "email.delivery_delayed",
  "email.delivered",
  "email.bounced",
  "email.complained",
  "email.failed",
  "email.suppressed",
] as const;

export type ResendOperationalEmailEvent = typeof resendOperationalEmailEvents[number];

export type JsonRecord = Record<string, unknown>;

export interface TransactionalEmailRenderRequest {
  templateKey: TransactionalTemplateKey;
  templateVersion: number;
  subject: string;
  payload: JsonRecord;
}

export interface RenderedTransactionalEmail {
  subject: string;
  html: string;
  text: string;
  templateKey: TransactionalTemplateKey;
  templateVersion: number;
}

export interface ClaimedTransactionalEmail {
  id: string;
  tenant_id: string;
  order_id: string;
  message_kind: TransactionalTemplateKey;
  template_key: TransactionalTemplateKey;
  template_version: number;
  recipient_email: string;
  recipient_name: string | null;
  sender_name: string | null;
  sender_email: string | null;
  reply_to_email: string | null;
  subject: string;
  render_payload: JsonRecord;
  attachment_manifest: unknown[];
  idempotency_key: string;
  delivery_mode: "dry_run" | "send";
  lease_token: string;
}
