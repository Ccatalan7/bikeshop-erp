// Correos de una cotización de cliente (20261102063700): recibida, oferta
// lista, recordatorio y aceptada. Mismo remitente y misma marca del tema del
// sitio que los correos del pedido (`templates.ts`). El botón lleva al
// enlace de la cotización, que sólo lee: aceptar, pedir cambios o rechazar
// es siempre un clic en la página, así un escáner de correo no responde nada.

import { brandFrom, escapeHtml, safeHttpsUrl } from "./templates.ts";

type JsonRecord = Record<string, unknown>;

export type QuoteEmailKind = "received" | "offer" | "reminder" | "accepted";

export const quoteEmailKinds: readonly QuoteEmailKind[] = [
  "received",
  "offer",
  "reminder",
  "accepted",
];

export type RenderedQuoteEmail = { subject: string; html: string; text: string };

export class QuoteEmailRenderError extends Error {}

function record(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {};
}

function text(value: unknown, fallback = ""): string {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
}

function num(value: unknown): number | null {
  const n = typeof value === "number" ? value : Number(value);
  return Number.isFinite(n) ? n : null;
}

/** «$30.000»: pesos sin decimales y punto de miles. */
export function clp(value: unknown): string {
  const n = Math.round(num(value) ?? 0);
  return `${n < 0 ? "-" : ""}$${String(Math.abs(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ".")}`;
}

function when(value: unknown, timezone: string): string {
  const raw = text(value);
  if (!raw) return "";
  const date = new Date(raw);
  if (Number.isNaN(date.getTime())) return "";
  return new Intl.DateTimeFormat("es-CL", {
    timeZone: timezone,
    weekday: "long",
    day: "numeric",
    month: "long",
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

const availabilityLabel: Record<string, string> = {
  in_stock: "En stock",
  on_order: "A pedido",
  unavailable: "No disponible",
};

function lineLabel(line: JsonRecord): string {
  const availability = text(line.availability);
  let label = availabilityLabel[availability] ?? "";
  const quantity = num(line.quantity) ?? 0;
  const requested = num(line.quantityRequested) ?? 0;
  if (quantity > 0 && quantity < requested) label += ` · ${quantity} de ${requested}`;
  const min = num(line.leadDaysMin);
  const max = num(line.leadDaysMax);
  if (availability === "on_order" && min !== null) {
    label += ` · llega en ${max === null || max === min ? min : `${min} a ${max}`} días hábiles`;
  }
  return label;
}

/**
 * The quote link: https, no credentials, and only the `#t=<link>` fragment
 * the quote page reads (the order emails' [safeHttpsUrl] refuses fragments).
 */
export function safeQuoteLink(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const candidate = value.trim();
  if (!candidate || candidate.length > 2048) return null;
  try {
    const url = new URL(candidate);
    if (
      url.protocol !== "https:" || !url.hostname || url.username || url.password ||
      !/^#t=[A-Za-z0-9_-]{40,128}$/.test(url.hash)
    ) {
      return null;
    }
    return url.toString();
  } catch {
    return null;
  }
}

const INK = "#13212C";
const MUTED = "#5F6B75";
const LINE = "#E3E9EE";

export function renderQuoteEmail(payload: JsonRecord): RenderedQuoteEmail {
  const kind = text(payload.kind) as QuoteEmailKind;
  if (!quoteEmailKinds.includes(kind)) {
    throw new QuoteEmailRenderError(`Unknown quote email kind: ${kind}`);
  }
  const store = record(payload.store);
  const quote = record(payload.quote);
  const offer = record(payload.offer);
  const brand = brandFrom(store);
  const storeName = text(store.name, "Nuestra tienda");
  const timezone = text(store.timezone, "America/Santiago");
  const number = text(quote.number);
  const firstName = text(quote.customerName).split(/\s+/)[0] ?? "";
  const link = safeQuoteLink(payload.link);
  const logo = safeHttpsUrl(store.logoUrl);
  if ((kind === "offer" || kind === "reminder" || kind === "accepted") && !offer.total) {
    throw new QuoteEmailRenderError(`${kind} needs a sent offer`);
  }
  if (!number) throw new QuoteEmailRenderError("The quote has no number");

  const lines = Array.isArray(offer.lines) ? offer.lines.map(record) : [];
  const requested = Array.isArray(payload.requested) ? payload.requested.map(record) : [];
  const validUntil = when(offer.validUntil, timezone);
  const prepay = num(payload.prepayPercent) ?? 100;
  const hasOnOrder = lines.some((line) =>
    text(line.availability) === "on_order" && (num(line.quantity) ?? 0) > 0
  );

  const copy = {
    received: {
      subject: `Recibimos tu cotización ${number}`,
      title: "Recibimos tu cotización",
      lead:
        "Estamos confirmando la disponibilidad, el precio y el plazo de cada producto. Te enviamos la oferta por este mismo medio.",
      button: "Ver tu cotización",
    },
    offer: {
      subject: `Tu cotización ${number} está lista`,
      title: "Tu oferta está lista",
      lead: validUntil
        ? `Esta es nuestra oferta para tu cotización. Vale hasta el ${validUntil}.`
        : "Esta es nuestra oferta para tu cotización.",
      button: "Ver y responder la oferta",
    },
    reminder: {
      subject: `Tu oferta ${number} vence pronto`,
      title: "Tu oferta vence pronto",
      lead: validUntil
        ? `La oferta de tu cotización vale hasta el ${validUntil}. Si quieres los productos, acéptala desde el enlace.`
        : "La oferta de tu cotización vence pronto. Si quieres los productos, acéptala desde el enlace.",
      button: "Ver y responder la oferta",
    },
    accepted: {
      subject: `Aceptaste la oferta ${number}`,
      title: "Recibimos tu aceptación",
      lead: `Gracias. Aceptaste la oferta por ${
        clp(offer.total)
      }. Te escribimos para coordinar el pago y la entrega.`,
      button: "Ver tu cotización",
    },
  }[kind];

  const greeting = firstName ? `Hola ${firstName},` : "Hola,";
  const font = brand.bodyStack;
  const headingFont = brand.headingStack;

  const offerRows = lines.map((line) => {
    const total = num(line.lineTotal);
    const note = text(line.note);
    return `<tr>
<td style="padding:14px 0;border-top:1px solid ${LINE};font-family:${font};font-size:14px;line-height:20px;color:${INK};">
<strong>${escapeHtml(text(line.name))}</strong><br>
<span style="font-size:12px;line-height:18px;color:${MUTED};">${escapeHtml(lineLabel(line))}</span>${
      note
        ? `<br><span style="font-size:12px;line-height:18px;color:${MUTED};font-style:italic;">${
          escapeHtml(note)
        }</span>`
        : ""
    }</td>
<td align="right" style="padding:14px 0 14px 12px;border-top:1px solid ${LINE};font-family:${font};font-size:14px;line-height:20px;color:${INK};white-space:nowrap;">${
      (num(line.quantity) ?? 0) > 0 ? `${num(line.quantity)} × ${clp(line.unitPrice)}` : "—"
    }<br><strong>${total === null ? "" : clp(total)}</strong></td>
</tr>`;
  }).join("");

  const requestedRows = requested.map((line) =>
    `<tr><td style="padding:10px 0;border-top:1px solid ${LINE};font-family:${font};font-size:14px;line-height:20px;color:${INK};">${
      escapeHtml(text(line.name))
    }</td><td align="right" style="padding:10px 0 10px 12px;border-top:1px solid ${LINE};font-family:${font};font-size:14px;color:${INK};">${
      num(line.quantity) ?? ""
    }</td></tr>`
  ).join("");

  const totals = offer.total
    ? `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-top:8px;">
<tr><td style="font-family:${font};font-size:13px;line-height:22px;color:${MUTED};">Neto</td><td align="right" style="font-family:${font};font-size:13px;color:${MUTED};">${
      clp(offer.subtotal)
    }</td></tr>
<tr><td style="font-family:${font};font-size:13px;line-height:22px;color:${MUTED};">IVA</td><td align="right" style="font-family:${font};font-size:13px;color:${MUTED};">${
      clp(offer.taxAmount)
    }</td></tr>
<tr><td style="padding-top:8px;border-top:1px solid ${LINE};font-family:${font};font-size:18px;line-height:26px;font-weight:700;color:${INK};">Total</td><td align="right" style="padding-top:8px;border-top:1px solid ${LINE};font-family:${font};font-size:18px;font-weight:700;color:${INK};">${
      clp(offer.total)
    }</td></tr></table>`
    : "";

  const table = kind === "received"
    ? `<table role="presentation" width="100%" cellpadding="0" cellspacing="0">${requestedRows}</table>`
    : `<table role="presentation" width="100%" cellpadding="0" cellspacing="0">${offerRows}</table>${totals}`;

  const notes = text(offer.notes) && kind === "offer"
    ? `<p style="margin:16px 0 0;font-family:${font};font-size:14px;line-height:21px;color:${INK};">${
      escapeHtml(text(offer.notes))
    }</p>`
    : "";
  const prepayNote = hasOnOrder && (kind === "offer" || kind === "reminder") && prepay > 0
    ? `<p style="margin:16px 0 0;font-family:${font};font-size:13px;line-height:20px;color:${MUTED};">Lo que es a pedido se paga ${
      prepay >= 100 ? "por adelantado" : `con un abono del ${prepay} %`
    } antes de pedirlo.</p>`
    : "";
  const answerNote = kind === "offer" || kind === "reminder"
    ? `<p style="margin:12px 0 0;font-family:${font};font-size:13px;line-height:20px;color:${MUTED};">Desde el enlace puedes aceptarla, pedir cambios o rechazarla.</p>`
    : "";
  const button = link
    ? `<table role="presentation" cellpadding="0" cellspacing="0" style="margin-top:24px;"><tr><td style="border-radius:8px;background:${brand.color};"><a href="${
      escapeHtml(link)
    }" style="display:inline-block;padding:14px 24px;font-family:${font};font-size:15px;line-height:20px;font-weight:700;color:${brand.onColor};text-decoration:none;border-radius:8px;">${
      escapeHtml(copy.button)
    }</a></td></tr></table>${answerNote}`
    : "";

  const html = `<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${
    escapeHtml(copy.subject)
  }</title>${brand.fontsHref ? `<link href="${escapeHtml(brand.fontsHref)}" rel="stylesheet">` : ""}</head>
<body style="margin:0;padding:0;background:#EDF1F5;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#EDF1F5;"><tr><td align="center" style="padding:28px 12px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;background:#FFFFFF;border-radius:12px;overflow:hidden;">
<tr><td style="padding:22px 28px;background:${brand.color};">${
    logo
      ? `<img src="${escapeHtml(logo)}" alt="${escapeHtml(storeName)}" height="36" style="display:block;height:36px;width:auto;">`
      : `<span style="font-family:${headingFont};font-size:20px;font-weight:700;color:${brand.onColor};">${
        escapeHtml(storeName)
      }</span>`
  }</td></tr>
<tr><td style="padding:28px;">
<div style="font-family:${font};font-size:11px;line-height:14px;font-weight:700;letter-spacing:1.3px;color:${MUTED};">COTIZACIÓN ${
    escapeHtml(number)
  }</div>
<h1 style="margin:10px 0 0;font-family:${headingFont};font-size:28px;line-height:34px;font-weight:700;color:${INK};">${
    escapeHtml(copy.title)
  }</h1>
<p style="margin:16px 0 0;font-family:${font};font-size:15px;line-height:23px;color:${INK};">${
    escapeHtml(greeting)
  }</p>
<p style="margin:8px 0 20px;font-family:${font};font-size:15px;line-height:23px;color:${INK};">${
    escapeHtml(copy.lead)
  }</p>
${table}${notes}${prepayNote}${button}
</td></tr>
<tr><td style="padding:18px 28px;border-top:1px solid ${LINE};font-family:${font};font-size:12px;line-height:18px;color:${MUTED};">${
    escapeHtml(storeName)
  }. Responde este correo si tienes dudas.</td></tr>
</table></td></tr></table></body></html>`;

  const textLines = [
    greeting,
    "",
    copy.lead,
    "",
    ...(kind === "received"
      ? requested.map((line) => `- ${num(line.quantity) ?? ""} × ${text(line.name)}`)
      : lines.map((line) =>
        `- ${text(line.name)} (${lineLabel(line)}): ${
          (num(line.quantity) ?? 0) > 0 ? `${num(line.quantity)} × ${clp(line.unitPrice)}` : "—"
        }`
      )),
    ...(offer.total ? ["", `Total: ${clp(offer.total)}`] : []),
    ...(link ? ["", `${copy.button}: ${link}`] : []),
    "",
    storeName,
  ];

  return { subject: copy.subject, html, text: textLines.join("\n") };
}
