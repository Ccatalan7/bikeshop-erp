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
  accent: string;
};

const copyByTemplate: Record<TransactionalTemplateKey, Copy> = {
  order_received: {
    eyebrow: "PEDIDO RECIBIDO",
    heading: "Gracias, recibimos tu pedido",
    body: "Ya tenemos los detalles de tu compra. Te avisaremos por este mismo medio cuando avance.",
    accent: "#1677A8",
  },
  payment_confirmed: {
    eyebrow: "PAGO CONFIRMADO",
    heading: "Tu pago quedó confirmado",
    body: "El pago fue validado y tu pedido puede continuar con su preparación.",
    accent: "#287A55",
  },
  processing: {
    eyebrow: "EN PREPARACIÓN",
    heading: "Estamos preparando tu pedido",
    body: "Nuestro equipo ya está revisando y preparando los productos de tu compra.",
    accent: "#7C5A27",
  },
  ready_for_pickup: {
    eyebrow: "LISTO PARA RETIRO",
    heading: "Tu pedido ya está listo",
    body: "Puedes retirarlo en la tienda. Si necesitas coordinar algo, responde este correo.",
    accent: "#287A55",
  },
  shipped: {
    eyebrow: "PEDIDO ENVIADO",
    heading: "Tu pedido va en camino",
    body: "El despacho ya fue entregado al transportista. Abajo encontrarás sus datos.",
    accent: "#476A93",
  },
  delivered: {
    eyebrow: "PEDIDO ENTREGADO",
    heading: "Tu pedido fue entregado",
    body: "Esperamos que disfrutes tu compra. Si necesitas ayuda, puedes responder este correo.",
    accent: "#287A55",
  },
  cancelled: {
    eyebrow: "PEDIDO CANCELADO",
    heading: "Tu pedido fue cancelado",
    body: "Registramos la cancelación. Si no reconoces este cambio o necesitas ayuda, contáctanos.",
    accent: "#8A4545",
  },
  refund_completed: {
    eyebrow: "REEMBOLSO COMPLETADO",
    heading: "Procesamos tu reembolso",
    body:
      "El reembolso quedó registrado. El abono puede tardar según los plazos de tu medio de pago.",
    accent: "#5D598A",
  },
  mercadopago_payment_voucher_available: {
    eyebrow: "COMPROBANTE DE PAGO",
    heading: "Tu comprobante de Mercado Pago está disponible",
    body:
      "Mercado Pago confirmó la operación y publicó su comprobante. Este documento acredita el pago, pero no reemplaza una boleta o factura emitida conforme al modelo tributario de la tienda.",
    accent: "#315C76",
  },
  payment_voucher_available: {
    eyebrow: "VOUCHER VÁLIDO COMO BOLETA",
    heading: "Tu comprobante tributario está disponible",
    body:
      "Mercado Pago emitió el voucher de tu compra. De acuerdo con el modelo de emisión declarado por la tienda, este comprobante es válido como boleta.",
    accent: "#315C76",
  },
  tax_document_issued: {
    eyebrow: "DOCUMENTO TRIBUTARIO EMITIDO",
    heading: "Tu documento tributario está disponible",
    body: "El documento oficial de tu compra fue emitido y está disponible de forma segura.",
    accent: "#315C76",
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

function itemsTable(items: unknown[], currency: string): { html: string; text: string } {
  if (items.length === 0) return { html: "", text: "" };

  const htmlRows = items.map((rawItem) => {
    const item = record(rawItem);
    const name = text(item.name, "Producto");
    const quantity = Math.max(1, Math.round(numberValue(item.quantity)));
    return `
      <tr>
        <td style="padding:12px 0;border-bottom:1px solid #E7ECEF;color:#23313A;font-size:14px;line-height:20px;">
          ${escapeHtml(name)}
          <span style="display:block;color:#73808A;font-size:12px;">Cantidad: ${quantity}</span>
        </td>
        <td align="right" style="padding:12px 0;border-bottom:1px solid #E7ECEF;color:#23313A;font-size:14px;font-weight:600;white-space:nowrap;">
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
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:collapse;margin-top:20px;">
        <tr><td colspan="2" style="padding-bottom:4px;color:#73808A;font-size:11px;font-weight:700;letter-spacing:1px;">DETALLE</td></tr>
        ${htmlRows}
      </table>`,
    text: `\nDetalle\n${textRows}`,
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
  const customerName = text(customer.name, "");
  const orderNumber = text(order.number, "");
  const currency = text(store.currency, "CLP").toUpperCase();
  const copy = copyByTemplate[request.templateKey];
  const logoUrl = safeHttpsUrl(store.logoUrl);
  const action = primaryAction(request.templateKey, payload);
  const itemContent = itemsTable(items, currency);
  const trackingCarrier = text(order.trackingCarrier);
  const trackingNumber = text(order.trackingNumber);
  const greeting = customerName ? `Hola ${customerName},` : "Hola,";
  const nonTaxLabel = request.templateKey === "order_received"
    ? text(document.label, "Comprobante de pedido · No constituye documento tributario")
    : request.templateKey === "mercadopago_payment_voucher_available"
    ? text(
      document.label,
      "Comprobante de pago de Mercado Pago · No constituye boleta ni factura",
    )
    : "";

  const statusRows: Array<[string, string]> = [];
  if (orderNumber) statusRows.push(["Pedido", orderNumber]);
  if (request.templateKey === "shipped" && trackingCarrier) {
    statusRows.push(["Transportista", trackingCarrier]);
  }
  if (request.templateKey === "shipped" && trackingNumber) {
    statusRows.push(["Seguimiento", trackingNumber]);
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
    : `<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:collapse;margin:22px 0 0;background:#F6F8F9;border-left:3px solid ${copy.accent};">
      ${
      statusRows.map(([label, value]) =>
        `<tr>
        <td style="padding:9px 12px;color:#73808A;font-size:12px;width:34%;">${
          escapeHtml(label)
        }</td>
        <td style="padding:9px 12px;color:#23313A;font-size:13px;font-weight:650;">${
          escapeHtml(value)
        }</td>
      </tr>`
      ).join("")
    }
    </table>`;

  const metadataText = statusRows.map(([label, value]) => `${label}: ${value}`).join("\n");
  const actionHtml = action
    ? `<table role="presentation" cellspacing="0" cellpadding="0" style="margin:26px 0 4px;"><tr><td bgcolor="${copy.accent}" style="border-radius:4px;"><a href="${
      escapeHtml(action.url)
    }" style="display:inline-block;padding:12px 20px;color:#FFFFFF;text-decoration:none;font-size:14px;font-weight:700;">${
      escapeHtml(action.label)
    }</a></td></tr></table>`
    : "";

  const totalHtml = ["order_received", "payment_confirmed"].includes(request.templateKey)
    ? `<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin-top:14px;border-collapse:collapse;"><tr>
        <td style="padding-top:8px;color:#23313A;font-size:15px;font-weight:700;">Total</td>
        <td align="right" style="padding-top:8px;color:#23313A;font-size:18px;font-weight:750;">${
      escapeHtml(formatMoney(order.total, currency))
    }</td>
      </tr></table>`
    : "";

  const totalText = ["order_received", "payment_confirmed"].includes(request.templateKey)
    ? `\nTotal: ${formatMoney(order.total, currency)}`
    : "";

  const preheader = `${copy.heading}${orderNumber ? ` · ${orderNumber}` : ""}`;
  const html = `<!doctype html>
<html lang="es">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#EEF2F4;font-family:Arial,'Helvetica Neue',sans-serif;color:#23313A;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">${
    escapeHtml(preheader)
  }</div>
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#EEF2F4;border-collapse:collapse;">
    <tr><td align="center" style="padding:28px 12px;">
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:620px;background:#FFFFFF;border-collapse:collapse;border-top:4px solid ${copy.accent};">
        <tr><td style="padding:24px 34px 18px;border-bottom:1px solid #E7ECEF;">
          ${
    logoUrl
      ? `<img src="${escapeHtml(logoUrl)}" alt="${
        escapeHtml(storeName)
      }" width="150" style="display:block;max-width:150px;height:auto;border:0;">`
      : `<div style="font-size:20px;font-weight:800;letter-spacing:.2px;color:#173A4E;">${
        escapeHtml(storeName)
      }</div>`
  }
        </td></tr>
        <tr><td style="padding:34px;">
          <div style="color:${copy.accent};font-size:11px;font-weight:800;letter-spacing:1.2px;margin-bottom:10px;">${copy.eyebrow}</div>
          <h1 style="margin:0 0 18px;color:#17242C;font-size:27px;line-height:34px;font-weight:750;">${
    escapeHtml(copy.heading)
  }</h1>
          <p style="margin:0 0 12px;color:#394850;font-size:15px;line-height:24px;">${
    escapeHtml(greeting)
  }</p>
          <p style="margin:0;color:#394850;font-size:15px;line-height:24px;">${
    escapeHtml(copy.body)
  }</p>
          ${metadataHtml}
          ${itemContent.html}
          ${totalHtml}
          ${actionHtml}
          ${
    nonTaxLabel
      ? `<p style="margin:24px 0 0;padding-top:16px;border-top:1px solid #E7ECEF;color:#73808A;font-size:11px;line-height:17px;">${
        escapeHtml(nonTaxLabel)
      }</p>`
      : ""
  }
        </td></tr>
        <tr><td style="padding:20px 34px;background:#F6F8F9;color:#73808A;font-size:11px;line-height:17px;">
          Este es un mensaje operacional de ${
    escapeHtml(storeName)
  }. Puedes responder este correo si necesitas ayuda.
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
    itemContent.text,
    totalText,
    action ? `\n${action.label}: ${action.url}` : "",
    nonTaxLabel ? `\n${nonTaxLabel}` : "",
    `\nEste es un mensaje operacional de ${storeName}. Puedes responder este correo si necesitas ayuda.`,
  ].filter(Boolean).join("\n");

  return {
    subject: request.subject,
    html,
    text: textBody,
    templateKey: request.templateKey,
    templateVersion: request.templateVersion,
  };
}
