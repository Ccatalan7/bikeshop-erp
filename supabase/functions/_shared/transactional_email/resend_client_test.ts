import { sendWithResend } from "./resend_client.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function message() {
  return {
    apiKey: "test-key-never-sent",
    idempotencyKey: "txn-email:test:001",
    from: "Viña Bike <pedidos@example.invalid>",
    to: "customer@example.invalid",
    subject: "Pedido recibido",
    html: "<p>Pedido</p>",
    text: "Pedido",
    tags: [{ name: "outbox_id", value: "outbox-test" }],
  };
}

Deno.test("Resend client records provider acknowledgement", async () => {
  let idempotencyHeader = "";
  const fetchMock = ((_input: string | URL | Request, init?: RequestInit) => {
    idempotencyHeader = new Headers(init?.headers).get("idempotency-key") ?? "";
    return Promise.resolve(
      new Response(JSON.stringify({ id: "email_provider_001" }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
  }) as typeof fetch;
  const result = await sendWithResend(message(), fetchMock);
  assert(result.kind === "submitted", "provider acknowledgement was not accepted");
  assert(idempotencyHeader === "txn-email:test:001", "idempotency key was not forwarded");
});

Deno.test("Resend client treats 429 as retryable and honors Retry-After", async () => {
  const fetchMock = (() =>
    Promise.resolve(
      new Response(
        JSON.stringify({ message: "Rate limited" }),
        { status: 429, headers: { "retry-after": "45" } },
      ),
    )) as typeof fetch;
  const result = await sendWithResend(message(), fetchMock);
  assert(result.kind === "retry", "429 must be retryable");
  assert(result.kind === "retry" && result.retryAfterSeconds === 45, "Retry-After was ignored");
});

Deno.test("Resend client retries a concurrent idempotent request", async () => {
  const fetchMock = (() =>
    Promise.resolve(
      new Response(
        JSON.stringify({
          name: "concurrent_idempotent_requests",
          message: "A matching request is still in progress",
        }),
        { status: 409 },
      ),
    )) as typeof fetch;
  const result = await sendWithResend(message(), fetchMock);
  assert(result.kind === "retry", "concurrent idempotent request must be retried");
  assert(
    result.kind === "retry" && result.retryAfterSeconds === 2,
    "concurrent idempotent retry did not receive a bounded delay",
  );
});

Deno.test("Resend client permanently rejects an idempotency payload conflict", async () => {
  const fetchMock = (() =>
    Promise.resolve(
      new Response(
        JSON.stringify({
          name: "invalid_idempotent_request",
          message: "The idempotency key was used with another payload",
        }),
        { status: 409 },
      ),
    )) as typeof fetch;
  const result = await sendWithResend(message(), fetchMock);
  assert(
    result.kind === "permanent_failure",
    "an idempotency payload conflict must never retry indefinitely",
  );
});

Deno.test("Resend client classifies validation failure as permanent", async () => {
  const fetchMock = (() =>
    Promise.resolve(
      new Response(
        JSON.stringify({ message: "Invalid from address" }),
        { status: 422 },
      ),
    )) as typeof fetch;
  const result = await sendWithResend(message(), fetchMock);
  assert(result.kind === "permanent_failure", "422 must not be retried indefinitely");
});

Deno.test("Resend client retries a lost acknowledgement without sending in test", async () => {
  const fetchMock =
    (() => Promise.reject(new TypeError("simulated connection reset"))) as typeof fetch;
  const result = await sendWithResend(message(), fetchMock);
  assert(result.kind === "retry", "network errors must remain retryable");
});
