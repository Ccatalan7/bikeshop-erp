export type WhatsAppTerminalStatus = "read" | "failed";

export interface WhatsAppStatusEmailAlertConfig {
  activationId: string;
  recipientEmail: string;
  contactName: string;
  timeZone: string;
  notifyStatuses: WhatsAppTerminalStatus[];
}

export interface RenderedWhatsAppStatusEmail {
  subject: string;
  html: string;
  text: string;
}

type JsonRecord = Record<string, unknown>;

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function record(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {};
}

function textValue(value: unknown, maximumLength: number): string | null {
  if (typeof value !== "string") return null;
  // deno-lint-ignore no-control-regex -- C0 characters do not belong in mail fields.
  const cleaned = value.replaceAll(/[\x00-\x1f\x7f]+/g, " ")
    .replaceAll(/\s+/g, " ")
    .trim()
    .slice(0, maximumLength);
  return cleaned || null;
}

export function terminalWhatsAppStatus(value: unknown): WhatsAppTerminalStatus | null {
  const normalized = textValue(value, 20)?.toLowerCase();
  return normalized === "read" || normalized === "failed" ? normalized : null;
}

export function parseWhatsAppStatusEmailAlertMetadata(
  metadata: unknown,
): WhatsAppStatusEmailAlertConfig | null {
  const candidate = record(record(metadata).status_email_alert);
  if (candidate.active !== true) return null;

  const activationId = textValue(candidate.activation_id, 80);
  const recipientEmail = textValue(candidate.recipient_email, 320)?.toLowerCase() ?? null;
  const contactName = textValue(candidate.contact_name, 160);
  const timeZone = textValue(candidate.time_zone, 80) ?? "America/Los_Angeles";
  if (
    !activationId || !uuidPattern.test(activationId) ||
    !recipientEmail || !emailPattern.test(recipientEmail) ||
    !contactName
  ) {
    return null;
  }

  try {
    new Intl.DateTimeFormat("es-CL", { timeZone }).format(new Date(0));
  } catch {
    return null;
  }

  const statuses = Array.isArray(candidate.notify_statuses)
    ? candidate.notify_statuses.map(terminalWhatsAppStatus).filter(
      (status): status is WhatsAppTerminalStatus => status !== null,
    )
    : ["read" as const];
  const notifyStatuses = [...new Set(statuses)];
  if (!notifyStatuses.length) return null;

  return {
    activationId,
    recipientEmail,
    contactName,
    timeZone,
    notifyStatuses,
  };
}

export function whatsappStatusOccurredAt(
  payload: unknown,
  fallback = new Date(),
): Date {
  const timestamp = textValue(record(payload).timestamp, 32);
  if (!timestamp || !/^\d{1,16}$/.test(timestamp)) return fallback;
  const milliseconds = Number(timestamp) * 1000;
  if (!Number.isSafeInteger(milliseconds)) return fallback;
  const occurredAt = new Date(milliseconds);
  return Number.isNaN(occurredAt.getTime()) ? fallback : occurredAt;
}

function formatOccurredAt(occurredAt: Date, timeZone: string): string {
  return new Intl.DateTimeFormat("es-CL", {
    timeZone,
    dateStyle: "long",
    timeStyle: "short",
    hourCycle: "h23",
  }).format(occurredAt);
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

export function whatsappProviderErrorSummary(payload: unknown): string | null {
  const errors = record(payload).errors;
  if (!Array.isArray(errors) || !errors.length) return null;
  const first = record(errors[0]);
  const errorData = record(first.error_data);
  const parts = [
    typeof first.code === "number" && Number.isFinite(first.code)
      ? String(first.code).slice(0, 40)
      : textValue(first.code, 40),
    textValue(first.title, 180),
    textValue(first.message, 400),
    textValue(errorData.details, 500),
  ].filter((part): part is string => Boolean(part));
  return parts.length ? [...new Set(parts)].join(" · ").slice(0, 800) : null;
}

export function renderWhatsAppStatusEmail(params: {
  config: WhatsAppStatusEmailAlertConfig;
  status: WhatsAppTerminalStatus;
  occurredAt: Date;
  providerError?: string | null;
}): RenderedWhatsAppStatusEmail {
  const { config, status, occurredAt } = params;
  const localTime = formatOccurredAt(occurredAt, config.timeZone);
  const contact = config.contactName;
  const subject = status === "read"
    ? `${contact} leyó tu mensaje de WhatsApp`
    : `Falló el mensaje de WhatsApp para ${contact}`;
  const detail = status === "read"
    ? `${contact} leyó el mensaje el ${localTime} (${config.timeZone}).`
    : `WhatsApp marcó como fallido el mensaje para ${contact} el ${localTime} (${config.timeZone}).`;
  const providerLine = status === "failed" && params.providerError
    ? `\nDetalle del proveedor: ${params.providerError}`
    : "";
  const text = `${detail}${providerLine}\n\nAlerta automática de Viñabike.`;
  const htmlProvider = status === "failed" && params.providerError
    ? `<p><strong>Detalle del proveedor:</strong> ${escapeHtml(params.providerError)}</p>`
    : "";
  const html = [
    '<div style="font-family:-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif;color:#132238;line-height:1.5">',
    `<h2 style="margin:0 0 16px">${escapeHtml(subject)}</h2>`,
    `<p>${escapeHtml(detail)}</p>`,
    htmlProvider,
    '<p style="color:#607086;font-size:13px;margin-top:24px">Alerta automática de Viñabike.</p>',
    "</div>",
  ].join("");
  return { subject, html, text };
}

export function renderWhatsAppStatusAlertVerificationEmail(
  config: WhatsAppStatusEmailAlertConfig,
): RenderedWhatsAppStatusEmail {
  const subject = "Alerta de lectura de WhatsApp conectada";
  const detail =
    `Listo: la alerta para el mensaje enviado a ${config.contactName} quedó conectada. ` +
    "Cuando WhatsApp lo marque como leído, enviaremos otro correo a esta dirección. " +
    "La alerta funciona en Supabase y no depende de que el ERP ni tu Mac estén abiertos.";
  return {
    subject,
    text: `${detail}\n\nViñabike`,
    html: [
      '<div style="font-family:-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif;color:#132238;line-height:1.5">',
      `<h2 style="margin:0 0 16px">${escapeHtml(subject)}</h2>`,
      `<p>${escapeHtml(detail)}</p>`,
      '<p style="color:#607086;font-size:13px;margin-top:24px">Viñabike</p>',
      "</div>",
    ].join(""),
  };
}

export function whatsappStatusAlertIdempotencyKey(
  config: WhatsAppStatusEmailAlertConfig,
  status: WhatsAppTerminalStatus | "verification",
): string {
  return `whatsapp-status-alert/${config.activationId}/${status}`;
}
