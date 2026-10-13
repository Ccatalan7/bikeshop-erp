import {
  JsonRecord,
  RenderedTransactionalEmail,
  TransactionalEmailRenderRequest,
  TransactionalTemplateKey,
  transactionalTemplateKeys,
} from "./types.ts";
import { safeMercadoPagoPaymentVoucherUrl } from "../mercadopago_payment_voucher.ts";

export class TemplateRenderError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "TemplateRenderError";
  }
}

type Copy = {
  eyebrow: string;
  heading: string;
  body: string;
};

const copyByTemplate: Record<TransactionalTemplateKey, Copy> = {
  order_received: {
    eyebrow: "PEDIDO RECIBIDO",
    heading: "Gracias, recibimos tu pedido",
    body: "Ya tenemos los detalles de tu compra. Te avisaremos por este mismo medio cuando avance.",
  },
  payment_confirmed: {
    eyebrow: "PAGO CONFIRMADO",
    heading: "Tu pago quedó confirmado",
    body: "El pago fue validado y tu pedido puede continuar con su preparación.",
  },
  processing: {
    eyebrow: "EN PREPARACIÓN",
    heading: "Estamos preparando tu pedido",
    body: "Nuestro equipo ya está revisando y preparando los productos de tu compra.",
  },
  ready_for_pickup: {
    eyebrow: "LISTO PARA RETIRO",
    heading: "Tu pedido ya está listo",
    body: "Puedes retirarlo en la tienda. Si necesitas coordinar algo, responde este correo.",
  },
  shipped: {
    eyebrow: "PEDIDO ENVIADO",
    heading: "Tu pedido va en camino",
    body:
      "Ya lo entregamos al transportista. Con el número de seguimiento puedes ver dónde va en todo momento.",
  },
  delivered: {
    eyebrow: "PEDIDO ENTREGADO",
    heading: "Tu pedido fue entregado",
    body: "Esperamos que disfrutes tu compra. Si necesitas ayuda, puedes responder este correo.",
  },
  cancelled: {
    eyebrow: "PEDIDO CANCELADO",
    heading: "Tu pedido fue cancelado",
    body: "Registramos la cancelación. Si no reconoces este cambio o necesitas ayuda, contáctanos.",
  },
  refund_completed: {
    eyebrow: "REEMBOLSO COMPLETADO",
    heading: "Procesamos tu reembolso",
    body:
      "El reembolso quedó registrado. El abono puede tardar según los plazos de tu medio de pago.",
  },
  mercadopago_payment_voucher_available: {
    eyebrow: "COMPROBANTE DE PAGO",
    heading: "Tu comprobante de Mercado Pago está disponible",
    body:
      "Mercado Pago confirmó la operación y publicó su comprobante. Este documento acredita el pago, pero no reemplaza una boleta o factura emitida conforme al modelo tributario de la tienda.",
  },
  payment_voucher_available: {
    eyebrow: "VOUCHER VÁLIDO COMO BOLETA",
    heading: "Tu comprobante tributario está disponible",
    body:
      "Mercado Pago emitió el voucher de tu compra. De acuerdo con el modelo de emisión declarado por la tienda, este comprobante es válido como boleta.",
  },
  tax_document_issued: {
    eyebrow: "DOCUMENTO TRIBUTARIO EMITIDO",
    heading: "Tu documento tributario está disponible",
    body: "El documento oficial de tu compra fue emitido y está disponible de forma segura.",
  },
};

function record(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {};
}

function text(value: unknown, fallback = ""): string {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
}

function numberValue(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim() && Number.isFinite(Number(value))) {
    return Number(value);
  }
  return 0;
}

export function escapeHtml(value: unknown): string {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

export function safeHttpsUrl(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const candidate = value.trim();
  if (!candidate || candidate.length > 2048) return null;
  try {
    const url = new URL(candidate);
    if (
      url.protocol !== "https:" || !url.hostname || url.username ||
      url.password || url.hash
    ) {
      return null;
    }
    return url.toString();
  } catch {
    return null;
  }
}

function formatMoney(value: unknown, currency: string): string {
  const amount = numberValue(value);
  try {
    return new Intl.NumberFormat("es-CL", {
      style: "currency",
      currency: currency || "CLP",
      maximumFractionDigits: currency === "CLP" ? 0 : 2,
    }).format(amount);
  } catch {
    return `${Math.round(amount).toLocaleString("es-CL")} ${currency || "CLP"}`;
  }
}

function requireTemplateKey(value: string): asserts value is TransactionalTemplateKey {
  if (!(transactionalTemplateKeys as readonly string[]).includes(value)) {
    throw new TemplateRenderError(`Unsupported transactional template: ${value}`);
  }
}

function officialTaxDocument(payload: JsonRecord): JsonRecord | null {
  const document = record(payload.officialTaxDocument);
  const status = text(document.status).toLowerCase();
  const documentType = text(document.documentType);
  const folio = text(document.folio);
  if (!["issued", "accepted"].includes(status) || !documentType || !folio) return null;
  return document;
}

function officialPaymentVoucher(payload: JsonRecord): JsonRecord | null {
  const voucher = record(payload.officialPaymentVoucher);
  const provider = text(voucher.provider);
  const status = text(voucher.status).toLowerCase();
  const operationId = text(voucher.operationId) || text(voucher.paymentId);
  const issuedAt = text(voucher.issuedAt);
  const currency = text(voucher.currency);
  const amount = numberValue(voucher.amount);
  const fiscalValidity = text(voucher.fiscalValidity);
  if (
    !provider || status !== "approved" || !operationId ||
    !issuedAt || Number.isNaN(Date.parse(issuedAt)) || amount <= 0 || !currency ||
    fiscalValidity !== "voucher_valid_as_boleta"
  ) {
    return null;
  }
  return voucher;
}

function mercadoPagoPaymentVoucher(payload: JsonRecord): JsonRecord | null {
  const voucher = record(payload.mercadoPagoPaymentVoucher);
  const provider = text(voucher.provider);
  const status = text(voucher.status).toLowerCase();
  const operationId = text(voucher.operationId) || text(voucher.paymentId);
  const issuedAt = text(voucher.issuedAt);
  const currency = text(voucher.currency);
  const amount = numberValue(voucher.amount);
  const fiscalValidity = text(voucher.fiscalValidity);
  const downloadUrl = safeMercadoPagoPaymentVoucherUrl(voucher.downloadUrl);
  if (
    provider.toLowerCase() !== "mercado pago" || status !== "approved" ||
    !operationId || !issuedAt || Number.isNaN(Date.parse(issuedAt)) ||
    amount <= 0 || !currency || fiscalValidity !== "not_a_tax_document" ||
    !downloadUrl
  ) {
    return null;
  }
  return voucher;
}

// ---------------------------------------------------------------------------
// The look. The email is the store's face to the customer (owner, 2026-10-13),
// so it wears the site's brand: color and fonts come from the site theme the
// queue copies into `store.brandColor`, `store.headingFont` and
// `store.bodyFont`, never from constants here.
// ---------------------------------------------------------------------------

const INK = "#13212C";
const BODY = "#3B4A55";
const MUTED = "#66757F";
const HAIRLINE = "#E3E9EE";
const SOFT = "#F4F7FA";
const PAGE = "#EDF1F5";
const FALLBACK_BRAND = "#1D3A52";

type Brand = {
  color: string;
  onColor: string;
  onColorSoft: string;
  onColorPending: string;
  pill: string;
  track: string;
  tint: string;
  tintBorder: string;
  headingStack: string;
  bodyStack: string;
  fontsHref: string | null;
};

function hexColor(value: unknown): string | null {
  const candidate = text(value);
  return /^#[0-9a-f]{6}$/i.test(candidate) ? candidate.toUpperCase() : null;
}

function rgb(hex: string): number[] {
  return [1, 3, 5].map((index) => parseInt(hex.slice(index, index + 2), 16));
}

function mix(hex: string, other: string, amount: number): string {
  const from = rgb(hex);
  const to = rgb(other);
  return "#" +
    from.map((channel, index) =>
      Math.round(channel + (to[index] - channel) * amount).toString(16).padStart(2, "0")
    ).join("").toUpperCase();
}

function luminance(hex: string): number {
  const [r, g, b] = rgb(hex).map((channel) => {
    const value = channel / 255;
    return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function fontName(value: unknown): string | null {
  const candidate = text(value);
  return /^[A-Za-z0-9 ]{1,40}$/.test(candidate) ? candidate : null;
}

/** The site's brand, with the text color that stays readable on it. */
export function brandFrom(store: JsonRecord): Brand {
  const color = hexColor(store.brandColor) ?? FALLBACK_BRAND;
  const onColor = luminance(color) > 0.4 ? INK : "#FFFFFF";
  const heading = fontName(store.headingFont);
  const body = fontName(store.bodyFont);
  const families = [...new Set([heading, body].filter((name): name is string => !!name))];
  return {
    color,
    onColor,
    onColorSoft: mix(onColor, color, 0.12),
    onColorPending: mix(onColor, color, 0.36),
    pill: mix(color, onColor, 0.16),
    track: mix(color, onColor, 0.26),
    tint: mix(color, "#FFFFFF", 0.94),
    tintBorder: mix(color, "#FFFFFF", 0.62),
    headingStack: `${heading ? `'${heading}',` : ""}'Oswald','Arial Narrow',Arial,sans-serif`,
    bodyStack: `${body ? `'${body}',` : ""}'Helvetica Neue',Helvetica,Arial,sans-serif`,
    fontsHref: families.length === 0
      ? null
      : `https://fonts.googleapis.com/css2?${
        families.map((name) => `family=${name.replaceAll(" ", "+")}:wght@400;500;600;700`).join("&")
      }&display=swap`,
  };
}

function caption(label: string, brand: Brand): string {
  return `<div style="font-family:${brand.bodyStack};font-size:11px;line-height:14px;font-weight:700;letter-spacing:1.3px;color:${MUTED};">${
    escapeHtml(label.toUpperCase())
  }</div>`;
}

function button(label: string, url: string, brand: Brand, fullWidth: boolean): string {
  return `<table role="presentation" ${
    fullWidth ? 'width="100%" ' : ""
  }cellspacing="0" cellpadding="0" style="border-collapse:separate;"><tr><td align="center" bgcolor="${brand.color}" style="border-radius:10px;background:${brand.color};"><a href="${
    escapeHtml(url)
  }" target="_blank" style="display:block;padding:14px 24px;font-family:${brand.bodyStack};font-size:15px;line-height:20px;font-weight:700;color:${brand.onColor};text-decoration:none;border-radius:10px;">${
    escapeHtml(label)
  } &rarr;</a></td></tr></table>`;
}

function formatDateTime(value: string | null, timezone: string): string | null {
  if (!value) return null;
  const time = Date.parse(value);
  if (Number.isNaN(time)) return null;
  const at = new Date(time);
  for (const timeZone of [timezone, "America/Santiago"]) {
    try {
      const day = new Intl.DateTimeFormat("es-CL", {
        timeZone,
        weekday: "long",
        day: "numeric",
        month: "long",
      }).format(at);
      const clock = new Intl.DateTimeFormat("es-CL", {
        timeZone,
        hour: "2-digit",
        minute: "2-digit",
        hour12: false,
      }).format(at);
      return `${day} a las ${clock}`;
    } catch {
      // An unknown store timezone falls back to Chile.
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Where the order is: the same steps the customer sees on the site.
// ---------------------------------------------------------------------------

const progressStep: Partial<Record<TransactionalTemplateKey, number>> = {
  order_received: 0,
  payment_confirmed: 1,
  processing: 2,
  shipped: 3,
  ready_for_pickup: 3,
  delivered: 4,
};

function progress(
  templateKey: TransactionalTemplateKey,
  order: JsonRecord,
): { steps: string[]; current: number } | null {
  const step = progressStep[templateKey];
  if (step === undefined) return null;
  const current = templateKey === "order_received" &&
      text(order.paymentStatus).toLowerCase() === "paid"
    ? 1
    : step;
  const pickup = templateKey === "ready_for_pickup" || text(order.deliveryType) === "pickup";
  return {
    steps: pickup
      ? ["Recibido", "Pagado", "Preparado", "Listo para retiro", "Retirado"]
      : ["Recibido", "Pagado", "Preparado", "En camino", "Entregado"],
    current,
  };
}

function progressHtml(state: { steps: string[]; current: number }, brand: Brand): string {
  const width = `${Math.floor(100 / state.steps.length)}%`;
  const bars = state.steps.map((_, index) =>
    `<td width="${width}" style="padding:0 3px;"><table role="presentation" width="100%" cellspacing="0" cellpadding="0"><tr><td height="6" style="height:6px;font-size:0;line-height:0;border-radius:3px;background:${
      index <= state.current ? brand.onColor : brand.track
    };">&nbsp;</td></tr></table></td>`
  ).join("");
  const labels = state.steps.map((step, index) => {
    const tone = index === state.current
      ? `color:${brand.onColor};font-weight:700;`
      : index < state.current
      ? `color:${brand.onColorSoft};font-weight:500;`
      : `color:${brand.onColorPending};font-weight:500;`;
    return `<td width="${width}" valign="top" style="padding:9px 3px 0;font-family:${brand.bodyStack};font-size:12px;line-height:15px;${tone}">${
      index < state.current ? "&#10003;&nbsp;" : ""
    }${escapeHtml(step)}</td>`;
  }).join("");
  return `<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin-top:30px;border-collapse:collapse;"><tr>${bars}</tr><tr>${labels}</tr></table>`;
}

// ---------------------------------------------------------------------------
// The shipment: carrier, service, the code and how to follow it.
// ---------------------------------------------------------------------------

type ShipmentView = {
  carrier: string;
  service: string;
  trackingNumber: string;
  trackingUrl: string | null;
  admittedAt: string | null;
};

function shipmentView(payload: JsonRecord): ShipmentView | null {
  const shipment = record(payload.shipment);
  const order = record(payload.order);
  const carrier = text(shipment.carrier) || text(order.trackingCarrier);
  const trackingNumber = text(shipment.trackingNumber) || text(order.trackingNumber);
  if (!carrier && !trackingNumber) return null;
  return {
    carrier,
    service: text(shipment.service),
    trackingNumber,
    trackingUrl: safeHttpsUrl(shipment.trackingUrl) ?? safeHttpsUrl(order.trackingUrl),
    admittedAt: text(shipment.admittedAt) || null,
  };
}

function shipmentCard(
  view: ShipmentView,
  brand: Brand,
  timezone: string,
): { html: string; text: string } {
  const carrierLabel = view.carrier || "el transportista";
  // The carriers' public pages take the code in a form, not in the link.
  const deepLink = !!view.trackingUrl && !!view.trackingNumber &&
    view.trackingUrl.includes(view.trackingNumber);
  const hint = view.trackingNumber && !deepLink
    ? `Copia el número y pégalo en la página de seguimiento de ${carrierLabel}.`
    : "";
  const admitted = formatDateTime(view.admittedAt, timezone);
  const admittedLine = admitted ? `Lo entregamos a ${carrierLabel} el ${admitted}.` : "";

  const html = `
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:separate;border:1px solid ${HAIRLINE};border-radius:14px;">
      <tr><td style="padding:22px 24px 0;">
        ${caption("Tu envío", brand)}
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin-top:6px;border-collapse:collapse;"><tr>
          <td valign="middle" style="font-family:${brand.headingStack};font-size:22px;line-height:28px;font-weight:600;color:${INK};">${
    escapeHtml(view.carrier || "Transportista")
  }</td>
          ${
    view.service
      ? `<td align="right" valign="middle"><span style="display:inline-block;padding:5px 11px;border-radius:999px;background:${SOFT};border:1px solid ${HAIRLINE};font-family:${brand.bodyStack};font-size:12px;line-height:16px;font-weight:600;color:${BODY};white-space:nowrap;">${
        escapeHtml(view.service)
      }</span></td>`
      : ""
  }
        </tr></table>
      </td></tr>
      ${
    view.trackingNumber
      ? `<tr><td style="padding:18px 24px 0;">
        ${caption("Número de seguimiento", brand)}
        <div class="code" style="margin-top:8px;padding:16px 12px;border-radius:10px;border:1.5px dashed ${brand.tintBorder};background:${brand.tint};text-align:center;font-family:${brand.bodyStack};font-size:30px;line-height:36px;font-weight:700;letter-spacing:2.5px;color:${brand.color};word-break:break-all;">${
        escapeHtml(view.trackingNumber)
      }</div>
      </td></tr>`
      : ""
  }
      ${
    view.trackingUrl
      ? `<tr><td style="padding:16px 24px 0;">${
        button("Seguir mi envío", view.trackingUrl, brand, true)
      }</td></tr>`
      : ""
  }
      ${
    hint
      ? `<tr><td style="padding:10px 24px 0;font-family:${brand.bodyStack};font-size:13px;line-height:19px;color:${MUTED};text-align:center;">${
        escapeHtml(hint)
      }</td></tr>`
      : ""
  }
      <tr><td style="padding:${admittedLine ? "16px 24px 20px" : "0 24px 22px"};">${
    admittedLine
      ? `<div style="padding-top:14px;border-top:1px solid ${HAIRLINE};font-family:${brand.bodyStack};font-size:14px;line-height:20px;color:${BODY};"><span style="color:${brand.color};">&#9679;</span>&nbsp; ${
        escapeHtml(admittedLine)
      }</div>`
      : ""
  }</td></tr>
    </table>`;

  const textLines = [
    "",
    `Transportista: ${view.carrier || "Transportista"}${view.service ? ` · ${view.service}` : ""}`,
    view.trackingNumber ? `Número de seguimiento: ${view.trackingNumber}` : "",
    view.trackingUrl ? `Seguir el envío: ${view.trackingUrl}` : "",
    hint,
    admittedLine,
  ].filter((line, index) => index === 0 || line);
  return { html, text: textLines.join("\n") };
}

function deliveryBlock(payload: JsonRecord, brand: Brand): { html: string; text: string } {
  const delivery = record(payload.delivery);
  if (!text(delivery.addressLine1)) return { html: "", text: "" };
  const place = [text(delivery.city), text(delivery.state)].filter(Boolean).join(", ");
  const lines = [text(delivery.addressLine1), text(delivery.addressLine2), place].filter(Boolean);
  const name = text(delivery.name);
  return {
    html: `
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin-top:16px;border-collapse:separate;background:${SOFT};border-radius:14px;">
      <tr><td style="padding:18px 24px;">
        ${caption("Se entrega en", brand)}
        ${
      name
        ? `<div style="margin-top:6px;font-family:${brand.bodyStack};font-size:15px;line-height:21px;font-weight:700;color:${INK};">${
          escapeHtml(name)
        }</div>`
        : ""
    }
        <div style="margin-top:${
      name ? 2 : 6
    }px;font-family:${brand.bodyStack};font-size:15px;line-height:22px;color:${BODY};">${
      lines.map(escapeHtml).join("<br>")
    }</div>
      </td></tr>
    </table>`,
    text: ["", "Se entrega en:", name, ...lines].filter((line, index) => index === 0 || line)
      .join("\n"),
  };
}

// ---------------------------------------------------------------------------
// What was bought.
// ---------------------------------------------------------------------------

function itemsTable(
  items: unknown[],
  currency: string,
  brand: Brand,
  afterContent: boolean,
): { html: string; text: string } {
  if (items.length === 0) return { html: "", text: "" };

  const htmlRows = items.map((rawItem) => {
    const item = record(rawItem);
    const name = text(item.name, "Producto");
    const quantity = Math.max(1, Math.round(numberValue(item.quantity)));
    return `
      <tr>
        <td style="padding:12px 0;border-bottom:1px solid ${HAIRLINE};font-family:${brand.bodyStack};color:${INK};font-size:15px;line-height:21px;font-weight:600;">
          ${escapeHtml(name)}
          <span style="display:block;color:${MUTED};font-size:13px;font-weight:400;">Cantidad: ${quantity}</span>
        </td>
        <td align="right" valign="top" style="padding:12px 0 12px 16px;border-bottom:1px solid ${HAIRLINE};font-family:${brand.bodyStack};color:${INK};font-size:15px;line-height:21px;font-weight:600;white-space:nowrap;">
          ${escapeHtml(formatMoney(item.subtotal, currency))}
        </td>
      </tr>`;
  }).join("");

  const textRows = items.map((rawItem) => {
    const item = record(rawItem);
    return `- ${text(item.name, "Producto")} × ${
      Math.max(1, Math.round(numberValue(item.quantity)))
    }: ${formatMoney(item.subtotal, currency)}`;
  }).join("\n");

  return {
    html: `
      <div style="margin-top:${afterContent ? 28 : 0}px;">${caption("Tu compra", brand)}</div>
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:collapse;margin-top:4px;">
        ${htmlRows}
      </table>`,
    text: `\nDetalle\n${textRows}`,
  };
}

const amountTemplates: readonly TransactionalTemplateKey[] = [
  "order_received",
  "payment_confirmed",
  "shipped",
];

/**
 * What the total is made of, then the total, so a customer never sees a
 * total the listed products do not explain. WEB-26-00021 (2026-10-12) got
 * «$11.000» for the bike part and «Total $17.990» with the $6.990 delivery
 * nowhere in the email.
 */
function amountSummary(
  templateKey: TransactionalTemplateKey,
  order: JsonRecord,
  currency: string,
  brand: Brand,
): { html: string; text: string } {
  if (!amountTemplates.includes(templateKey)) return { html: "", text: "" };

  const total = numberValue(order.total);
  const shipping = numberValue(order.shippingCost);
  const deliveryType = text(order.deliveryType);
  const rows: Array<[string, string]> = [];
  if (deliveryType === "shipping" && shipping > 0) {
    rows.push(["Productos", formatMoney(total - shipping, currency)]);
    rows.push(["Despacho a domicilio", formatMoney(shipping, currency)]);
  } else if (deliveryType === "pickup") {
    rows.push(["Retiro en tienda", "Sin costo"]);
  }
  const paid = templateKey === "payment_confirmed" || templateKey === "shipped" ||
    text(order.paymentStatus).toLowerCase() === "paid";
  const totalLabel = paid ? "Total pagado" : "Total a pagar";

  const rowHtml = rows.map(([label, value]) =>
    `<tr>
        <td style="padding-top:8px;font-family:${brand.bodyStack};color:${MUTED};font-size:14px;line-height:20px;">${
      escapeHtml(label)
    }</td>
        <td align="right" style="padding-top:8px;font-family:${brand.bodyStack};color:${BODY};font-size:14px;line-height:20px;">${
      escapeHtml(value)
    }</td>
      </tr>`
  ).join("");

  return {
    html:
      `<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin-top:6px;border-collapse:collapse;">${rowHtml}<tr>
        <td style="padding-top:12px;font-family:${brand.bodyStack};color:${INK};font-size:15px;line-height:22px;font-weight:700;">${
        escapeHtml(totalLabel)
      }</td>
        <td align="right" style="padding-top:12px;font-family:${brand.headingStack};color:${INK};font-size:22px;line-height:26px;font-weight:600;">${
        escapeHtml(formatMoney(total, currency))
      }</td>
      </tr></table>`,
    text: [
      "",
      ...rows.map(([label, value]) => `${label}: ${value}`),
      `${totalLabel}: ${formatMoney(total, currency)}`,
    ].join("\n"),
  };
}

function primaryAction(
  templateKey: TransactionalTemplateKey,
  payload: JsonRecord,
): { label: string; url: string } | null {
  const order = record(payload.order);
  const store = record(payload.store);

  if (templateKey === "shipped") {
    const trackingUrl = safeHttpsUrl(order.trackingUrl);
    if (trackingUrl) return { label: "Seguir envío", url: trackingUrl };
  }

  if (templateKey === "tax_document_issued") {
    const document = officialTaxDocument(payload);
    const documentUrl = document ? safeHttpsUrl(document.downloadUrl) : null;
    if (documentUrl) return { label: "Ver documento", url: documentUrl };
  }

  if (templateKey === "payment_voucher_available") {
    const voucher = officialPaymentVoucher(payload);
    const voucherUrl = voucher ? safeHttpsUrl(voucher.downloadUrl) : null;
    if (voucherUrl) return { label: "Ver boleta (voucher)", url: voucherUrl };
  }

  if (templateKey === "mercadopago_payment_voucher_available") {
    const voucher = mercadoPagoPaymentVoucher(payload);
    const voucherUrl = voucher ? safeMercadoPagoPaymentVoucherUrl(voucher.downloadUrl) : null;
    if (voucherUrl) return { label: "Ver comprobante de pago", url: voucherUrl };
  }

  const storeUrl = safeHttpsUrl(store.storeUrl);
  return storeUrl ? { label: "Visitar la tienda", url: storeUrl } : null;
}

export function renderTransactionalEmail(
  request: TransactionalEmailRenderRequest,
): RenderedTransactionalEmail {
  requireTemplateKey(request.templateKey);
  if (request.templateVersion !== 1) {
    throw new TemplateRenderError(
      `Unsupported ${request.templateKey} template version: ${request.templateVersion}`,
    );
  }

  const payload = record(request.payload);
  if (request.templateKey === "tax_document_issued" && !officialTaxDocument(payload)) {
    throw new TemplateRenderError(
      "tax_document_issued requires an official DTE with issued or accepted status, type and folio",
    );
  }
  if (
    request.templateKey === "payment_voucher_available" &&
    !officialPaymentVoucher(payload)
  ) {
    throw new TemplateRenderError(
      "payment_voucher_available requires an approved official provider voucher with operation id, issue time, amount, currency and explicit fiscal validity",
    );
  }
  if (
    request.templateKey === "mercadopago_payment_voucher_available" &&
    !mercadoPagoPaymentVoucher(payload)
  ) {
    throw new TemplateRenderError(
      "mercadopago_payment_voucher_available requires an approved, credential-free Mercado Pago receipt explicitly marked not_a_tax_document",
    );
  }

  const store = record(payload.store);
  const customer = record(payload.customer);
  const order = record(payload.order);
  const document = record(payload.document);
  const officialDocument = officialTaxDocument(payload);
  const paymentVoucher = officialPaymentVoucher(payload);
  const mercadoPagoVoucher = mercadoPagoPaymentVoucher(payload);
  const items = Array.isArray(payload.items) ? payload.items : [];
  const storeName = text(store.name, "Nuestra tienda");
  const storeUrl = safeHttpsUrl(store.storeUrl);
  const timezone = text(store.timezone, "America/Santiago");
  const customerName = text(customer.name, "");
  const orderNumber = text(order.number, "");
  const currency = text(store.currency, "CLP").toUpperCase();
  const copy = copyByTemplate[request.templateKey];
  const brand = brandFrom(store);
  const logoUrl = safeHttpsUrl(store.logoUrl);
  const greeting = customerName ? `Hola ${customerName},` : "Hola,";
  const nonTaxLabel = request.templateKey === "order_received"
    ? text(document.label, "Comprobante de pedido · No constituye documento tributario")
    : request.templateKey === "mercadopago_payment_voucher_available"
    ? text(
      document.label,
      "Comprobante de pago de Mercado Pago · No constituye boleta ni factura",
    )
    : "";

  const shipment = request.templateKey === "shipped" ? shipmentView(payload) : null;
  const shipmentContent = shipment
    ? shipmentCard(shipment, brand, timezone)
    : { html: "", text: "" };
  const deliveryContent = request.templateKey === "shipped"
    ? deliveryBlock(payload, brand)
    : { html: "", text: "" };
  // The shipment card carries its own button; the store link sits in the help row.
  const action = shipment ? null : primaryAction(request.templateKey, payload);

  const statusRows: Array<[string, string]> = [];
  if (request.templateKey === "order_received") {
    statusRows.push([
      "Pago",
      text(order.paymentStatus).toLowerCase() === "paid"
        ? "Confirmado"
        : "Pendiente de confirmación",
    ]);
  }
  if (request.templateKey === "refund_completed") {
    statusRows.push(["Monto reembolsado", formatMoney(order.refundedAmount, currency)]);
  }
  if (officialDocument) {
    statusRows.push(["Documento", text(officialDocument.documentType)]);
    statusRows.push(["Folio", text(officialDocument.folio)]);
  }
  if (paymentVoucher) {
    statusRows.push(["Operador", text(paymentVoucher.provider)]);
    statusRows.push([
      "Operación",
      text(paymentVoucher.operationId) || text(paymentVoucher.paymentId),
    ]);
    statusRows.push([
      "Monto",
      formatMoney(paymentVoucher.amount, text(paymentVoucher.currency, currency)),
    ]);
    statusRows.push(["Validez", "Válido como boleta"]);
  }
  if (mercadoPagoVoucher) {
    statusRows.push(["Operador", "Mercado Pago"]);
    statusRows.push([
      "Operación",
      text(mercadoPagoVoucher.operationId) || text(mercadoPagoVoucher.paymentId),
    ]);
    statusRows.push([
      "Monto",
      formatMoney(
        mercadoPagoVoucher.amount,
        text(mercadoPagoVoucher.currency, currency),
      ),
    ]);
    statusRows.push(["Validez", "Comprobante de pago · no es documento tributario"]);
  }

  const metadataHtml = statusRows.length === 0
    ? ""
    : `<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:separate;background:${SOFT};border-radius:14px;">
      ${
      statusRows.map(([label, value], index) =>
        `<tr>
        <td style="padding:${index === 0 ? 16 : 10}px 20px ${
          index === statusRows.length - 1 ? 16 : 0
        }px;font-family:${brand.bodyStack};color:${MUTED};font-size:13px;line-height:19px;width:38%;">${
          escapeHtml(label)
        }</td>
        <td style="padding:${index === 0 ? 16 : 10}px 20px ${
          index === statusRows.length - 1 ? 16 : 0
        }px 0;font-family:${brand.bodyStack};color:${INK};font-size:14px;line-height:19px;font-weight:700;">${
          escapeHtml(value)
        }</td>
      </tr>`
      ).join("")
    }
    </table>`;

  const metadataText = [
    orderNumber ? `Pedido: ${orderNumber}` : "",
    ...statusRows.map(([label, value]) => `${label}: ${value}`),
  ].filter(Boolean).join("\n");
  const actionHtml = action
    ? `<div style="margin-top:28px;">${button(action.label, action.url, brand, false)}</div>`
    : "";

  const itemContent = itemsTable(
    items,
    currency,
    brand,
    !!(shipmentContent.html || deliveryContent.html || metadataHtml),
  );
  const amounts = amountSummary(request.templateKey, order, currency, brand);
  const state = progress(request.templateKey, order);

  const preheader = shipment && shipment.trackingNumber
    ? `Va por ${shipment.carrier || "transportista"} · seguimiento ${shipment.trackingNumber}`
    : `${copy.heading}${orderNumber ? ` · ${orderNumber}` : ""}`;

  const header = `
        <tr><td class="px" style="padding:22px 40px;background:#FFFFFF;border-radius:16px 16px 0 0;">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:collapse;"><tr>
            <td valign="middle">${
    logoUrl
      ? `<img src="${escapeHtml(logoUrl)}" alt="${
        escapeHtml(storeName)
      }" height="40" style="display:block;height:40px;width:auto;max-width:180px;border:0;">`
      : `<div style="font-family:${brand.headingStack};font-size:22px;line-height:28px;font-weight:600;color:${INK};">${
        escapeHtml(storeName)
      }</div>`
  }</td>
            ${
    orderNumber
      ? `<td align="right" valign="middle" style="font-family:${brand.bodyStack};font-size:11px;line-height:14px;font-weight:700;letter-spacing:1.3px;color:${MUTED};">PEDIDO<div style="margin-top:3px;font-size:15px;line-height:20px;letter-spacing:.3px;color:${INK};">${
        escapeHtml(orderNumber)
      }</div></td>`
      : ""
  }
          </tr></table>
        </td></tr>`;

  const hero = `
        <tr><td class="px" style="padding:36px 40px 34px;background:${brand.color};">
          <span style="display:inline-block;padding:6px 12px;border-radius:999px;background:${brand.pill};font-family:${brand.bodyStack};font-size:11px;line-height:14px;font-weight:700;letter-spacing:1.4px;color:${brand.onColor};">${
    escapeHtml(copy.eyebrow)
  }</span>
          <h1 class="h1" style="margin:16px 0 0;font-family:${brand.headingStack};font-size:34px;line-height:41px;font-weight:600;letter-spacing:.2px;color:${brand.onColor};">${
    escapeHtml(copy.heading)
  }</h1>
          <p style="margin:14px 0 0;font-family:${brand.bodyStack};font-size:16px;line-height:25px;color:${brand.onColorSoft};"><strong style="color:${brand.onColor};">${
    escapeHtml(greeting)
  }</strong><br>${escapeHtml(copy.body)}</p>
          ${state ? progressHtml(state, brand) : ""}
        </td></tr>`;

  const help = `
        <tr><td class="px" style="padding:22px 40px;background:${SOFT};border-radius:0 0 16px 16px;font-family:${brand.bodyStack};font-size:14px;line-height:21px;color:${BODY};">
          <strong style="color:${INK};">¿Alguna duda?</strong> Responde este correo y te ayudamos.${
    storeUrl
      ? `<br><a href="${
        escapeHtml(storeUrl)
      }" target="_blank" style="color:${brand.color};font-weight:700;text-decoration:none;">${
        escapeHtml(new URL(storeUrl).host)
      }</a>`
      : ""
  }
        </td></tr>`;

  const html = `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light only">
<meta name="supported-color-schemes" content="light">
${brand.fontsHref ? `<link href="${escapeHtml(brand.fontsHref)}" rel="stylesheet">` : ""}
<style>
  @media only screen and (max-width:620px) {
    .outer { padding:12px 8px 24px !important; }
    .px { padding-left:22px !important; padding-right:22px !important; }
    .h1 { font-size:28px !important; line-height:34px !important; }
    .code { font-size:24px !important; letter-spacing:1.5px !important; }
  }
</style>
</head>
<body style="margin:0;padding:0;background:${PAGE};-webkit-text-size-adjust:100%;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">${
    escapeHtml(preheader)
  }</div>
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:${PAGE};border-collapse:collapse;">
    <tr><td class="outer" align="center" style="padding:32px 12px 40px;">
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:600px;border-collapse:separate;background:#FFFFFF;border-radius:16px;">
        ${header}
        ${hero}
        <tr><td class="px" style="padding:32px 40px 34px;background:#FFFFFF;font-family:${brand.bodyStack};color:${BODY};">
          ${shipmentContent.html}
          ${deliveryContent.html}
          ${metadataHtml}
          ${itemContent.html}
          ${amounts.html}
          ${actionHtml}
          ${
    nonTaxLabel
      ? `<p style="margin:24px 0 0;padding-top:16px;border-top:1px solid ${HAIRLINE};font-family:${brand.bodyStack};color:${MUTED};font-size:12px;line-height:18px;">${
        escapeHtml(nonTaxLabel)
      }</p>`
      : ""
  }
        </td></tr>
        ${help}
      </table>
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:600px;border-collapse:collapse;">
        <tr><td align="center" style="padding:18px 24px 0;font-family:${brand.bodyStack};font-size:12px;line-height:18px;color:${MUTED};">
          Mensaje operacional de <strong style="color:${BODY};">${
    escapeHtml(storeName)
  }</strong> sobre tu pedido${
    orderNumber ? ` <span style="white-space:nowrap;">${escapeHtml(orderNumber)}</span>` : ""
  }.
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;

  const textBody = [
    copy.eyebrow,
    copy.heading,
    "",
    greeting,
    copy.body,
    metadataText ? `\n${metadataText}` : "",
    shipmentContent.text,
    deliveryContent.text,
    itemContent.text,
    amounts.text,
    action ? `\n${action.label}: ${action.url}` : "",
    nonTaxLabel ? `\n${nonTaxLabel}` : "",
    `\n¿Alguna duda? Responde este correo y te ayudamos.${storeUrl ? ` ${storeUrl}` : ""}`,
    `Mensaje operacional de ${storeName}.`,
  ].filter(Boolean).join("\n");

  return {
    subject: request.subject,
    html,
    text: textBody,
    templateKey: request.templateKey,
    templateVersion: request.templateVersion,
  };
}
