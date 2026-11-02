import { clp, QuoteEmailRenderError, renderQuoteEmail } from "./quote_templates.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const offerPayload = {
  kind: "offer",
  link: "https://vinabike.cl/cotizacion#t=AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-abcd",
  store: { name: "Viñabike", storeUrl: "https://vinabike.cl", brandColor: "#0D3B66" },
  quote: { number: "COT-26-00001", customerName: "Ana Pérez" },
  prepayPercent: 100,
  offer: {
    total: 148000,
    subtotal: 124370,
    taxAmount: 23630,
    validUntil: "2026-11-05T15:00:00Z",
    lines: [
      { name: "Neumático 29 x 2.25", availability: "in_stock", quantity: 3, quantityRequested: 3, unitPrice: 30000, lineTotal: 90000 },
      { name: "Cámara 29 <b>", availability: "on_order", quantity: 2, quantityRequested: 4, unitPrice: 6500, lineTotal: 13000, leadDaysMin: 2, leadDaysMax: 4, note: "El proveedor tiene 2" },
      { name: "Válvula", availability: "unavailable", quantity: 0, quantityRequested: 1 },
    ],
  },
};

Deno.test("the offer email lists each line with its availability, total and the link", () => {
  const email = renderQuoteEmail(offerPayload);
  assert(email.subject === "Tu cotización COT-26-00001 está lista", email.subject);
  assert(email.html.includes("Hola Ana,"), "greets by first name");
  assert(email.html.includes("A pedido · 2 de 4 · llega en 2 a 4 días hábiles"), "partial on-order line");
  assert(email.html.includes("No disponible"), "unavailable line");
  assert(email.html.includes("$148.000"), "total");
  assert(email.html.includes("Cámara 29 &lt;b&gt;"), "names are escaped");
  assert(email.html.includes("se paga por adelantado"), "on-order prepayment note");
  assert(email.html.includes('href="https://vinabike.cl/cotizacion#t='), "link button");
  assert(email.html.includes("aceptarla, pedir cambios o rechazarla"), "says what the link allows");
  assert(email.text.includes("Ver y responder la oferta: https://vinabike.cl/cotizacion#t="), "text part");
});

Deno.test("the acknowledgement lists what was asked and needs no offer", () => {
  const email = renderQuoteEmail({
    kind: "received",
    link: "https://vinabike.cl/cotizacion#t=x".padEnd(80, "y"),
    store: { name: "Viñabike" },
    quote: { number: "COT-26-00002", customerName: "Beto" },
    requested: [{ name: "Neumático Maxxis Minion DHF 29 x 2.5", quantity: 2 }],
  });
  assert(email.subject === "Recibimos tu cotización COT-26-00002", email.subject);
  assert(email.html.includes("Minion DHF"), "requested line");
  assert(!email.html.includes("Total"), "no totals before the offer");
});

Deno.test("an offer email without a sent offer is refused", () => {
  let refused = false;
  try {
    renderQuoteEmail({ ...offerPayload, offer: null });
  } catch (error) {
    refused = error instanceof QuoteEmailRenderError;
  }
  assert(refused, "must refuse");
});

Deno.test("pesos are written the Chilean way", () => {
  assert(clp(148000) === "$148.000", clp(148000));
  assert(clp(0) === "$0", clp(0));
});
