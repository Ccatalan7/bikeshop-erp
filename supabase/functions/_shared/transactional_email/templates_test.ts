import { renderTransactionalEmail, TemplateRenderError } from "./templates.ts";
import { transactionalTemplateKeys } from "./types.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function basePayload() {
  return {
    schemaVersion: 1,
    store: {
      name: "Viña Bike",
      storeUrl: "https://vinabike.cl",
      logoUrl: "https://vinabike.cl/logo.png",
      currency: "CLP",
      timezone: "America/Santiago",
    },
    customer: { name: "Cliente Prueba" },
    order: {
      id: "9e000000-0000-4000-8000-000000000001",
      number: "WEB-TEST-001",
      status: "processing",
      paymentStatus: "paid",
      total: 24990,
      trackingCarrier: "Starken",
      trackingNumber: "TRACK-001",
      trackingUrl: "https://www.starken.cl/seguimiento/TRACK-001",
      refundedAmount: 24990,
    },
    items: [{ name: "Producto de prueba", quantity: 1, subtotal: 24990 }],
    document: {
      kind: "order_receipt",
      taxStatus: "not_a_tax_document",
      label: "Comprobante de pedido · No constituye documento tributario",
    },
  };
}

Deno.test("all transactional templates render professional HTML and plain text", () => {
  for (const key of transactionalTemplateKeys) {
    const payload = basePayload() as Record<string, unknown>;
    if (key === "tax_document_issued") {
      payload.officialTaxDocument = {
        status: "accepted",
        documentType: "Boleta electrónica",
        folio: "12345",
        downloadUrl: "https://documentos.vinabike.cl/dte/secure-token",
      };
    }
    if (key === "payment_voucher_available") {
      payload.officialPaymentVoucher = {
        provider: "Mercado Pago",
        status: "approved",
        operationId: "MP-OP-001",
        issuedAt: "2026-07-18T18:00:00.000Z",
        amount: 24990,
        currency: "CLP",
        fiscalValidity: "voucher_valid_as_boleta",
        downloadUrl: "https://documentos.vinabike.cl/vouchers/secure-token",
      };
    }
    if (key === "mercadopago_payment_voucher_available") {
      payload.document = {
        kind: "mercadopago_payment_voucher",
        taxStatus: "not_a_tax_document",
        label: "Comprobante de pago de Mercado Pago · No constituye boleta ni factura",
      };
      payload.mercadoPagoPaymentVoucher = {
        provider: "Mercado Pago",
        providerDocumentId: "payment:MP-OP-001",
        status: "approved",
        operationId: "MP-OP-001",
        issuedAt: "2026-07-18T18:00:00.000Z",
        amount: 24990,
        currency: "CLP",
        fiscalValidity: "not_a_tax_document",
        downloadUrl: "https://www.mercadopago.cl/activities/receipt?payment_id=MP-OP-001",
      };
    }

    const rendered = renderTransactionalEmail({
      templateKey: key,
      templateVersion: 1,
      subject: `Asunto ${key}`,
      payload,
    });
    assert(rendered.html.includes("<!doctype html>"), `${key} has no HTML document`);
    assert(rendered.html.includes("Viña Bike"), `${key} has no store identity`);
    assert(rendered.text.length > 80, `${key} has no useful plain-text fallback`);
    assert(rendered.subject === `Asunto ${key}`, `${key} changed immutable subject`);
    if (key === "payment_voucher_available") {
      assert(
        rendered.html.includes("Ver boleta (voucher)"),
        "verified Mercado Pago voucher action is not identified as the boleta",
      );
    }
    if (key === "mercadopago_payment_voucher_available") {
      assert(
        rendered.html.includes("Ver comprobante de pago"),
        "Mercado Pago receipt action is missing",
      );
      assert(
        rendered.html.includes("No constituye boleta ni factura"),
        "non-fiscal Mercado Pago receipt is not explicitly labelled",
      );
      assert(
        !rendered.html.includes("Válido como boleta"),
        "non-fiscal Mercado Pago receipt was mislabeled as a boleta",
      );
    }
  }
});

Deno.test("order receipt is clearly labelled as non-tax", () => {
  const rendered = renderTransactionalEmail({
    templateKey: "order_received",
    templateVersion: 1,
    subject: "Pedido recibido",
    payload: basePayload(),
  });
  assert(
    rendered.html.includes("No constituye documento tributario"),
    "HTML must label the order receipt as non-tax",
  );
  assert(
    rendered.text.includes("No constituye documento tributario"),
    "plain text must label the order receipt as non-tax",
  );
});

Deno.test("customer-controlled values are HTML escaped", () => {
  const payload = basePayload();
  payload.customer.name = '<img src=x onerror="alert(1)">';
  payload.items[0].name = "<script>alert(1)</script>";
  const rendered = renderTransactionalEmail({
    templateKey: "order_received",
    templateVersion: 1,
    subject: "Pedido recibido",
    payload,
  });
  assert(!rendered.html.includes("<script>"), "script tag was not escaped");
  assert(!rendered.html.includes("<img src=x"), "customer HTML was not escaped");
  assert(rendered.html.includes("&lt;script&gt;"), "escaped product value is missing");
});

Deno.test("unsafe tracking links are never rendered as actions", () => {
  const payload = basePayload();
  for (
    const unsafeUrl of [
      "javascript:alert(1)",
      "https://usuario:secreto@tracking.example.com/pedido",
      "https://tracking.example.com/pedido#token-secreto",
    ]
  ) {
    payload.store.storeUrl = unsafeUrl;
    payload.order.trackingUrl = unsafeUrl;
    const rendered = renderTransactionalEmail({
      templateKey: "shipped",
      templateVersion: 1,
      subject: "Enviado",
      payload,
    });
    assert(!rendered.html.includes(unsafeUrl), "unsafe URL reached the HTML");
    assert(!rendered.text.includes(unsafeUrl), "unsafe URL reached plain text");
  }
});

Deno.test("tax document email rejects internal invoice data", () => {
  let rejected = false;
  try {
    renderTransactionalEmail({
      templateKey: "tax_document_issued",
      templateVersion: 1,
      subject: "Factura",
      payload: {
        ...basePayload(),
        officialTaxDocument: { status: "internal", documentType: "Factura", folio: "FV-001" },
      },
    });
  } catch (error) {
    rejected = error instanceof TemplateRenderError;
  }
  assert(rejected, "internal invoices must not render as an official tax document email");
});

Deno.test("payment voucher email rejects an ordinary Mercado Pago status", () => {
  let rejected = false;
  try {
    renderTransactionalEmail({
      templateKey: "payment_voucher_available",
      templateVersion: 1,
      subject: "Comprobante",
      payload: {
        ...basePayload(),
        officialPaymentVoucher: {
          provider: "Mercado Pago",
          status: "approved",
          operationId: "MP-OP-001",
          amount: 24990,
          currency: "CLP",
        },
      },
    });
  } catch (error) {
    rejected = error instanceof TemplateRenderError;
  }
  assert(rejected, "a payment status alone must not render as a fiscal voucher");
});

Deno.test("non-fiscal Mercado Pago receipt rejects fiscal labels and unsafe links", () => {
  for (
    const voucher of [
      {
        provider: "Mercado Pago",
        status: "approved",
        operationId: "MP-OP-001",
        issuedAt: "2026-07-18T18:00:00.000Z",
        amount: 24990,
        currency: "CLP",
        fiscalValidity: "voucher_valid_as_boleta",
        downloadUrl: "https://www.mercadopago.cl/receipt",
      },
      {
        provider: "Mercado Pago",
        status: "approved",
        operationId: "MP-OP-001",
        issuedAt: "2026-07-18T18:00:00.000Z",
        amount: 24990,
        currency: "CLP",
        fiscalValidity: "not_a_tax_document",
        downloadUrl: "https://user:secret@www.mercadopago.cl/receipt",
      },
    ]
  ) {
    let rejected = false;
    try {
      renderTransactionalEmail({
        templateKey: "mercadopago_payment_voucher_available",
        templateVersion: 1,
        subject: "Comprobante",
        payload: {
          ...basePayload(),
          mercadoPagoPaymentVoucher: voucher,
        },
      });
    } catch (error) {
      rejected = error instanceof TemplateRenderError;
    }
    assert(rejected, "unsafe or fiscalized payment receipt must not render");
  }
});

Deno.test("templates ignore internal notes and unsupported payload fields", () => {
  const payload = { ...basePayload(), internalNotes: "NO EXPONER ESTO" };
  const rendered = renderTransactionalEmail({
    templateKey: "processing",
    templateVersion: 1,
    subject: "Preparando",
    payload,
  });
  assert(!rendered.html.includes("NO EXPONER ESTO"), "internal notes leaked into HTML");
  assert(!rendered.text.includes("NO EXPONER ESTO"), "internal notes leaked into text");
});
