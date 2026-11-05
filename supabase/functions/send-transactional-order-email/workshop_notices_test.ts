import { processWorkshopNotices } from "./index.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const received = {
  noticeId: "33333333-3333-4333-8333-333333333333",
  kind: "received",
  recipient: "maria@example.invalid",
  link: "https://vinabike.cl/cuenta/vincular#c=" + "a".repeat(43),
  linkKind: "claim",
  sender: {
    enabled: true,
    name: "Taller Viñabike",
    email: "taller@vinabike.cl",
    replyTo: "hola@vinabike.cl",
  },
  store: { name: "Viñabike", timezone: "America/Santiago" },
  job: {
    number: "PG-00333",
    customerName: "María José Rojas",
    item: "Trek Marlin 7",
    intake: "bike",
  },
};

function fakeClient(claimed: unknown[], claimError = false) {
  const completions: Array<Record<string, unknown>> = [];
  return {
    completions,
    rpc(name: string, params: Record<string, unknown>) {
      if (name === "claim_workshop_customer_notices_v1") {
        return Promise.resolve(
          claimError ? { data: null, error: { message: "boom" } } : { data: claimed, error: null },
        );
      }
      completions.push({ name, ...params });
      return Promise.resolve({ data: "sent", error: null });
    },
  };
}

Deno.test("a claimed workshop notice is sent once with its own key and closed as sent", async () => {
  const client = fakeClient([received]);
  const sent: Array<Record<string, unknown>> = [];
  const results = await processWorkshopNotices(client, "t", "w", "key", (message) => {
    sent.push(message as unknown as Record<string, unknown>);
    return Promise.resolve({ kind: "submitted", providerMessageId: "re_9" });
  });
  assert(sent.length === 1, "one send");
  assert(sent[0].idempotencyKey === `workshop-notice:${received.noticeId}`, "stable key");
  assert(sent[0].to === "maria@example.invalid", "recipient");
  assert(sent[0].from === "Taller Viñabike <taller@vinabike.cl>", "sender");
  assert(sent[0].subject === "Recibimos tu bicicleta · PG-00333", String(sent[0].subject));
  assert(results[0].outcome === "submitted", JSON.stringify(results));
  assert(
    client.completions[0].name === "complete_workshop_customer_notice_v1" &&
      client.completions[0].p_outcome === "sent" &&
      client.completions[0].p_provider_message_id === "re_9",
    "completed sent",
  );
});

Deno.test("a shop without its sender skips, a broken notice fails and a provider hiccup retries", async () => {
  const client = fakeClient([
    { ...received, sender: { enabled: false } },
    {
      ...received,
      noticeId: "44444444-4444-4444-8444-444444444444",
      link: "https://evil.example/x",
    },
    { ...received, noticeId: "55555555-5555-4555-8555-555555555555" },
  ]);
  let sends = 0;
  await processWorkshopNotices(client, "t", "w", "key", () => {
    sends++;
    return Promise.resolve({ kind: "retry", errorClass: "provider_unavailable", message: "503" });
  });
  assert(sends === 1, "only the healthy notice reaches the provider");
  assert(client.completions[0].p_outcome === "skipped", "skipped without a sender");
  assert(client.completions[1].p_outcome === "failed", "an unsafe link fails without retrying");
  assert(client.completions[2].p_outcome === "retry", "a transient failure retries");
});

Deno.test("a failed claim never throws into the order e-mails", async () => {
  const results = await processWorkshopNotices(fakeClient([], true), "t", "w", "key");
  assert(results.length === 1 && results[0].outcome === "claim_failed", JSON.stringify(results));
});
