import { handlePreview, PreviewRpc } from "./index.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

// Invented data (2026-10-13 shipping receipt preview).
const preview = {
  templateKey: "shipped",
  templateVersion: 1,
  recipient: "cliente@example.invalid",
  recipientName: "Cliente Prueba",
  senderName: "Ventas Tienda",
  senderEmail: "ventas@example.invalid",
  deliveryMode: "send",
  suppressed: null,
  subject: "Tu pedido WEB-TEST-001 ya fue enviado",
  payload: {
    schemaVersion: 1,
    store: { name: "Tienda Prueba", currency: "CLP", timezone: "America/Santiago" },
    customer: { name: "Cliente Prueba" },
    order: {
      number: "WEB-TEST-001",
      status: "shipped",
      paymentStatus: "paid",
      deliveryType: "shipping",
      total: 17990,
      shippingCost: 6990,
    },
    items: [{ name: "Producto de prueba", quantity: 1, subtotal: 11000 }],
    shipment: {
      carrier: "Correos de Chile",
      service: "Paquete Express AM",
      trackingNumber: "770000000001",
      trackingUrl: "https://www.correos.cl/web/guest/seguimiento-en-linea",
    },
    delivery: { name: "Cliente Prueba", addressLine1: "Calle Inventada 123", city: "Comuna" },
  },
};

const orderId = "9e800000-0000-4000-8000-000000000031";

function request(body: unknown, auth = "Bearer token-de-prueba"): Request {
  return new Request("http://localhost/preview", {
    method: "POST",
    headers: { Authorization: auth, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

Deno.test("the preview is the shipped email drawn with the worker's template", async () => {
  let seen: { auth: string; orderId: string; shipment: unknown } | null = null;
  const rpc: PreviewRpc = (auth, id, shipment) => {
    seen = { auth, orderId: id, shipment };
    return Promise.resolve({ data: preview, error: null });
  };
  const response = await handlePreview(
    request({
      orderId,
      shipment: { carrier: "Correos de Chile", tracking_number: "770000000001" },
    }),
    rpc,
  );
  assert(response.status === 200, `status ${response.status}`);
  const body = await response.json();
  assert(body.recipient === "cliente@example.invalid", "recipient is missing");
  assert(body.subject === "Tu pedido WEB-TEST-001 ya fue enviado", "subject changed");
  assert(body.deliveryMode === "send", "delivery mode is missing");
  assert(String(body.html).includes("770000000001"), "the tracking code is not in the email");
  assert(String(body.html).includes("Calle Inventada 123"), "the address is not in the email");
  assert(seen!.auth === "Bearer token-de-prueba", "the caller's session was not used");
  assert(seen!.orderId === orderId, "wrong order");
});

Deno.test("the database's refusal reaches the person", async () => {
  const rpc: PreviewRpc = () =>
    Promise.resolve({
      data: null,
      error: { code: "23514", message: "El pedido ya no espera despacho (está shipped)." },
    });
  const response = await handlePreview(
    request({ orderId, shipment: { carrier: "Starken", tracking_number: "123456" } }),
    rpc,
  );
  assert(response.status === 400, `status ${response.status}`);
  const body = await response.json();
  assert(String(body.error).includes("ya no espera despacho"), "the reason was lost");
});

Deno.test("no session, no preview; bad input never reaches the database", async () => {
  let called = false;
  const rpc: PreviewRpc = () => {
    called = true;
    return Promise.resolve({ data: preview, error: null });
  };
  assert((await handlePreview(request({ orderId, shipment: {} }, ""), rpc)).status === 401, "401");
  assert(
    (await handlePreview(request({ orderId: "x", shipment: { a: 1 } }), rpc)).status === 400,
    "bad id",
  );
  assert(
    (await handlePreview(request({ orderId, shipment: {} }), rpc)).status === 400,
    "empty draft",
  );
  assert(
    (await handlePreview(new Request("http://localhost/preview", { method: "GET" }), rpc))
      .status ===
      405,
    "GET",
  );
  assert(!called, "the database was called for an invalid request");
});
