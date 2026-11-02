import { processQuoteMessages } from "./index.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const offer = {
  messageId: "11111111-1111-4111-8111-111111111111",
  kind: "offer",
  recipient: "ana@example.invalid",
  link: "https://vinabike.cl/cotizacion#t=" + "a".repeat(43),
  sender: { enabled: true, name: "Ventas Viñabike", email: "ventas@vinabike.cl", replyTo: "ventas@vinabike.cl" },
  store: { name: "Viñabike" },
  quote: { number: "COT-26-00001", customerName: "Ana" },
  offer: { total: 30000, subtotal: 25210, taxAmount: 4790, lines: [] },
};

function fakeClient(claimed: unknown[]) {
  const completions: Array<Record<string, unknown>> = [];
  return {
    completions,
    rpc(name: string, params: Record<string, unknown>) {
      if (name === "claim_customer_quote_messages_v1") return Promise.resolve({ data: claimed, error: null });
      completions.push({ name, ...params });
      return Promise.resolve({ data: "sent", error: null });
    },
  };
}

Deno.test("a claimed quote email is sent once with its own idempotency key and marked sent", async () => {
  const client = fakeClient([offer]);
  const sent: Array<Record<string, unknown>> = [];
  const results = await processQuoteMessages(client, "t", "w", "key", (message) => {
    sent.push(message as unknown as Record<string, unknown>);
    return Promise.resolve({ kind: "submitted", providerMessageId: "re_1" });
  });
  assert(sent.length === 1, "one send");
  assert(sent[0].idempotencyKey === `customer-quote-message:${offer.messageId}`, "stable key");
  assert(sent[0].to === "ana@example.invalid", "recipient");
  assert(results[0].outcome === "submitted", JSON.stringify(results));
  assert(client.completions[0].p_outcome === "sent" && client.completions[0].p_provider_message_id === "re_1", "completed sent");
});

Deno.test("a store without the transactional sender skips, and a broken payload fails without retrying", async () => {
  const client = fakeClient([
    { ...offer, sender: { enabled: false } },
    { ...offer, messageId: "22222222-2222-4222-8222-222222222222", offer: null },
  ]);
  let sends = 0;
  await processQuoteMessages(client, "t", "w", "key", () => {
    sends++;
    return Promise.resolve({ kind: "submitted", providerMessageId: "re_2" });
  });
  assert(sends === 0, "nothing sent");
  assert(client.completions[0].p_outcome === "skipped", "skipped");
  assert(client.completions[1].p_outcome === "failed", "render error fails");
});
