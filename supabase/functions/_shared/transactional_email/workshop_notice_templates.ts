// Avisos del taller al cliente por correo (20261105130000): recibimos tu bici,
// tu presupuesto está listo, tu bici está lista y tu comprobante de entrega.
// Mismo remitente y misma marca del tema del sitio que los correos del pedido
// y de las cotizaciones. El botón lleva a la ficha del cliente en la tienda, o
// a crear su cuenta ligada a ella: el enlace sólo abre una página, así un
// escáner de correo no liga nada.
//
// La voz es la del comprobante: tuteo, frases cortas, rótulos claros y la
// garantía al final (dueño, 2026-11-04).

import { brandFrom, escapeHtml, safeHttpsUrl } from "./templates.ts";
import { clp } from "./quote_templates.ts";
import { resolveWhatsAppTemplateGreetingName } from "../whatsapp_template_greeting.ts";

type JsonRecord = Record<string, unknown>;

export type WorkshopNoticeKind = "received" | "quote_ready" | "ready" | "delivered";

export const workshopNoticeKinds: readonly WorkshopNoticeKind[] = [
  "received",
  "quote_ready",
  "ready",
  "delivered",
];

export type RenderedWorkshopNotice = { subject: string; html: string; text: string };

export class WorkshopNoticeRenderError extends Error {}

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

/** «19 de noviembre»: el día y el mes, en la hora de la tienda. */
export function dayAndMonth(value: unknown, timezone: string): string {
  const raw = text(value);
  if (!raw) return "";
  const date = new Date(raw);
  if (Number.isNaN(date.getTime())) return "";
  return new Intl.DateTimeFormat("es-CL", { timeZone: timezone, day: "numeric", month: "long" })
    .format(date);
}

/**
 * The notice link: https, no credentials, and either the workshop page of the
 * portal or the claim page with its `#c=<code>` fragment.
 */
export function safeWorkshopLink(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const candidate = value.trim();
  if (!candidate || candidate.length > 2048) return null;
  try {
    const url = new URL(candidate);
    if (url.protocol !== "https:" || !url.hostname || url.username || url.password || url.search) {
      return null;
    }
    if (url.pathname === "/cuenta/servicios" && !url.hash) return url.toString();
    if (url.pathname === "/cuenta/vincular" && /^#c=[A-Za-z0-9_-]{40,128}$/.test(url.hash)) {
      return url.toString();
    }
    return null;
  } catch {
    return null;
  }
}

const INK = "#13212C";
const MUTED = "#5F6B75";
const LINE = "#E3E9EE";

export function renderWorkshopNotice(payload: JsonRecord): RenderedWorkshopNotice {
  const kind = text(payload.kind) as WorkshopNoticeKind;
  if (!workshopNoticeKinds.includes(kind)) {
    throw new WorkshopNoticeRenderError(`Unknown workshop notice kind: ${kind}`);
  }
  const store = record(payload.store);
  const job = record(payload.job);
  const delivery = record(payload.delivery);
  const brand = brandFrom(store);
  const storeName = text(store.name, "Nuestro taller");
  const timezone = text(store.timezone, "America/Santiago");
  const number = text(job.number);
  if (!number) throw new WorkshopNoticeRenderError("The job has no number");
  const link = safeWorkshopLink(payload.link);
  if (!link) throw new WorkshopNoticeRenderError("The notice has no valid link");
  const claim = text(payload.linkKind) === "claim";
  const preferences = !claim ? safeHttpsUrl(payload.preferencesLink) : null;
  const logo = safeHttpsUrl(store.logoUrl);

  const component = text(job.intake) === "component";
  const item = text(job.item, component ? "componente" : "bicicleta");
  // Lo que recibimos: «tu bicicleta» o, en un trabajo de componente, «tu rueda».
  const noun = component ? item : "bicicleta";
  const firstName = resolveWhatsAppTemplateGreetingName(text(job.customerName));
  const greeting = firstName ? `Hola ${firstName},` : "Hola,";
  const request = text(job.request);
  const total = num(job.total);
  const receivedOn = dayAndMonth(job.receivedAt, timezone);
  const deliveredOn = dayAndMonth(delivery.deliveredAt, timezone);
  const serviceUntil = dayAndMonth(delivery.serviceWarrantyUntil, timezone);
  const partsUntil = dayAndMonth(delivery.partsWarrantyUntil, timezone);
  const workPerformed = text(delivery.workPerformed);
  if (kind === "delivered" && !serviceUntil && !partsUntil && !workPerformed && !deliveredOn) {
    throw new WorkshopNoticeRenderError("delivered needs its delivery receipt");
  }

  const copy = {
    received: {
      subject: `Recibimos tu ${noun} · ${number}`,
      title: `Recibimos tu ${noun}`,
      lead: "Ya está en nuestro taller. Te avisaremos por este medio en cada paso.",
      button: "Ver el estado",
    },
    quote_ready: {
      subject: `Tu presupuesto está listo · ${number}`,
      title: "Tu presupuesto está listo",
      lead: "Revísalo y respóndenos para comenzar el trabajo.",
      button: "Ver el presupuesto",
    },
    ready: {
      subject: component
        ? `Tu trabajo está listo · ${number}`
        : `Tu bicicleta está lista · ${number}`,
      title: component ? "Tu trabajo está listo" : "Tu bicicleta está lista",
      lead: component
        ? "Puedes pasar a retirarlo al taller."
        : "Puedes pasar a retirarla al taller.",
      button: "Ver el detalle",
    },
    delivered: {
      subject: `Tu comprobante de entrega · ${number}`,
      title: "Tu comprobante de entrega",
      lead: deliveredOn
        ? `Entregamos tu ${noun} el ${deliveredOn}. Este es el resumen del trabajo y tu garantía.`
        : `Este es el resumen del trabajo y tu garantía.`,
      button: "Ver tu comprobante",
    },
  }[kind];

  // Primero qué y de quién; después lo hecho; al final lo que se deriva
  // (plazos): el orden del comprobante.
  const facts: Array<[string, string]> = [];
  // La bici con marca y modelo, o el elemento; sin dato, la fila sobra.
  if (item !== (component ? "componente" : "bicicleta")) {
    facts.push(
      component
        ? ["Componente", item.charAt(0).toLocaleUpperCase("es") + item.slice(1)]
        : ["Bicicleta", item],
    );
  }
  if (kind === "received" && receivedOn) facts.push(["Recibida", receivedOn]);
  if (request && kind !== "delivered") facts.push(["Servicio solicitado", request]);
  if (kind === "quote_ready" && total !== null && total > 0) {
    facts.push(["Presupuesto", clp(total)]);
  }
  if (kind === "delivered" && workPerformed) facts.push(["Trabajo realizado", workPerformed]);
  if (kind === "delivered" && serviceUntil) {
    facts.push(["Garantía del servicio", `Válida hasta el ${serviceUntil}`]);
  }
  if (kind === "delivered" && partsUntil) {
    facts.push(["Garantía de repuestos", `Válida hasta el ${partsUntil}`]);
  }
  const shownFacts = facts;

  const font = brand.bodyStack;
  const headingFont = brand.headingStack;
  const rows = shownFacts.map(([label, value]) =>
    `<tr>
<td style="padding:12px 16px 12px 0;border-top:1px solid ${LINE};font-family:${font};font-size:13px;line-height:20px;color:${MUTED};white-space:nowrap;vertical-align:top;">${
      escapeHtml(label)
    }</td>
<td style="padding:12px 0;border-top:1px solid ${LINE};font-family:${font};font-size:14px;line-height:20px;color:${INK};font-weight:600;">${
      escapeHtml(value)
    }</td>
</tr>`
  ).join("");
  const table = rows
    ? `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-top:4px;">${rows}</table>`
    : "";

  const claimNote = claim
    ? `<p style="margin:12px 0 0;font-family:${font};font-size:13px;line-height:20px;color:${MUTED};">Con tu cuenta ves el estado, el presupuesto y la garantía de cada trabajo.</p>`
    : "";
  const legal = kind === "delivered"
    ? `<p style="margin:18px 0 0;font-family:${font};font-size:12px;line-height:18px;color:${MUTED};">Sin perjuicio de la garantía legal (Ley 19.496).</p>`
    : "";
  const thanks = kind === "delivered"
    ? `<p style="margin:18px 0 0;font-family:${font};font-size:15px;line-height:23px;color:${INK};">Gracias por confiar en ${
      escapeHtml(storeName)
    }.</p>`
    : "";
  const button =
    `<table role="presentation" cellpadding="0" cellspacing="0" style="margin-top:24px;"><tr><td style="border-radius:8px;background:${brand.color};"><a href="${
      escapeHtml(link)
    }" style="display:inline-block;padding:14px 24px;font-family:${font};font-size:15px;line-height:20px;font-weight:700;color:${brand.onColor};text-decoration:none;border-radius:8px;">${
      escapeHtml(copy.button)
    }</a></td></tr></table>${claimNote}`;
  const preferencesLine = preferences
    ? `<br><a href="${
      escapeHtml(preferences)
    }" style="color:${MUTED};">Elige por dónde recibir estos avisos</a>`
    : "";

  const html = `<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${
    escapeHtml(copy.subject)
  }</title>${
    brand.fontsHref ? `<link href="${escapeHtml(brand.fontsHref)}" rel="stylesheet">` : ""
  }</head>
<body style="margin:0;padding:0;background:#EDF1F5;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#EDF1F5;"><tr><td align="center" style="padding:28px 12px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;background:#FFFFFF;border-radius:12px;overflow:hidden;">
<tr><td style="padding:22px 28px;background:${brand.color};">${
    logo
      ? `<img src="${escapeHtml(logo)}" alt="${
        escapeHtml(storeName)
      }" height="36" style="display:block;height:36px;width:auto;">`
      : `<span style="font-family:${headingFont};font-size:20px;font-weight:700;color:${brand.onColor};">${
        escapeHtml(storeName)
      }</span>`
  }</td></tr>
<tr><td style="padding:28px;">
<div style="font-family:${font};font-size:11px;line-height:14px;font-weight:700;letter-spacing:1.3px;color:${MUTED};">TRABAJO ${
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
${table}${legal}${button}${thanks}
</td></tr>
<tr><td style="padding:18px 28px;border-top:1px solid ${LINE};font-family:${font};font-size:12px;line-height:18px;color:${MUTED};">${
    escapeHtml(storeName)
  }. Responde este correo si tienes dudas.${preferencesLine}</td></tr>
</table></td></tr></table></body></html>`;

  const textLines = [
    greeting,
    "",
    copy.lead,
    "",
    ...shownFacts.map(([label, value]) => `${label}: ${value}`),
    ...(kind === "delivered" ? ["", "Sin perjuicio de la garantía legal (Ley 19.496)."] : []),
    "",
    `${copy.button}: ${link}`,
    ...(kind === "delivered" ? ["", `Gracias por confiar en ${storeName}.`] : []),
    "",
    `${storeName}. Responde este correo si tienes dudas.`,
    ...(preferences ? [`Elige por dónde recibir estos avisos: ${preferences}`] : []),
  ];

  return { subject: copy.subject, html, text: textLines.join("\n") };
}
