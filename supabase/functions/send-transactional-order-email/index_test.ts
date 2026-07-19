import { handleTransactionalEmailWorker } from "./index.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const workerSecret = "transactional-worker-test-secret";
const tenantId = "5443b130-cc28-45af-a420-cd500b288890";

async function withWorkerEnvironment(
  mode: "dry_run" | "send",
  callback: () => Promise<void>,
) {
  const previousSecret = Deno.env.get("TRANSACTIONAL_EMAIL_WORKER_SECRET");
  const previousMode = Deno.env.get("TRANSACTIONAL_EMAIL_MODE");
  Deno.env.set("TRANSACTIONAL_EMAIL_WORKER_SECRET", workerSecret);
  Deno.env.set("TRANSACTIONAL_EMAIL_MODE", mode);
  try {
    await callback();
  } finally {
    if (previousSecret == null) Deno.env.delete("TRANSACTIONAL_EMAIL_WORKER_SECRET");
    else Deno.env.set("TRANSACTIONAL_EMAIL_WORKER_SECRET", previousSecret);
    if (previousMode == null) Deno.env.delete("TRANSACTIONAL_EMAIL_MODE");
    else Deno.env.set("TRANSACTIONAL_EMAIL_MODE", previousMode);
  }
}

Deno.test("worker rejects requests without its dedicated secret", async () => {
  await withWorkerEnvironment("dry_run", async () => {
    const response = await handleTransactionalEmailWorker(
      new Request("https://example.invalid/send-transactional-order-email", {
        method: "POST",
        body: JSON.stringify({ action: "render" }),
      }),
    );
    assert(response.status === 401, "unauthorized worker request was accepted");
  });
});

Deno.test("dry-run runtime refuses an explicit send request before claiming outbox", async () => {
  await withWorkerEnvironment("dry_run", async () => {
    const response = await handleTransactionalEmailWorker(
      new Request("https://example.invalid/send-transactional-order-email", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-transactional-email-worker-secret": workerSecret,
        },
        body: JSON.stringify({ action: "process", tenant_id: tenantId, mode: "send" }),
      }),
    );
    assert(response.status === 409, "dry-run runtime allowed send mode");
  });
});

Deno.test("process path requires an explicit tenant before database access", async () => {
  await withWorkerEnvironment("dry_run", async () => {
    const response = await handleTransactionalEmailWorker(
      new Request("https://example.invalid/send-transactional-order-email", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-transactional-email-worker-secret": workerSecret,
        },
        body: JSON.stringify({ action: "process", mode: "dry_run" }),
      }),
    );
    assert(response.status === 400, "worker accepted a process request without tenant_id");
    const body = await response.json();
    assert(String(body.error).includes("tenant_id"), "tenant error was not explicit");
  });
});

Deno.test("process path rejects an ambiguous mode instead of silently dry-running", async () => {
  await withWorkerEnvironment("send", async () => {
    const response = await handleTransactionalEmailWorker(
      new Request("https://example.invalid/send-transactional-order-email", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-transactional-email-worker-secret": workerSecret,
        },
        body: JSON.stringify({ action: "process", tenant_id: tenantId, mode: "SEND" }),
      }),
    );
    assert(response.status === 400, "ambiguous process mode silently changed behavior");
  });
});

Deno.test("authorized render acceptance path never requires provider credentials", async () => {
  await withWorkerEnvironment("dry_run", async () => {
    const response = await handleTransactionalEmailWorker(
      new Request("https://example.invalid/send-transactional-order-email", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${workerSecret}`,
        },
        body: JSON.stringify({
          action: "render",
          templateKey: "order_received",
          templateVersion: 1,
          subject: "Pedido recibido",
          payload: {
            schemaVersion: 1,
            store: { name: "Viñabike", storeUrl: "https://vinabike.cl", currency: "CLP" },
            customer: { name: "Cliente de prueba" },
            order: { number: "WEB-TEST-001", total: 24990 },
            items: [{ name: "Producto de prueba", quantity: 1, subtotal: 24990 }],
            document: {
              kind: "order_receipt",
              taxStatus: "not_a_tax_document",
              label: "Comprobante de pedido · No constituye documento tributario",
            },
          },
        }),
      }),
    );
    const body = await response.json();
    assert(response.status === 200, `render path failed with ${response.status}`);
    assert(body.templateKey === "order_received", "wrong template rendered");
    assert(String(body.html).includes("Viñabike"), "sender branding is missing");
    assert(
      String(body.text).includes("No constituye documento tributario"),
      "tax disclaimer is missing",
    );
  });
});
