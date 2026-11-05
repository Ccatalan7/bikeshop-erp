import {
  recordTemplateReviews,
  refreshTemplateReviewsIfStale,
  templateReviewsFromMeta,
} from "./whatsapp_template_reviews.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function fakeStore(checkedAt: string | null) {
  const calls: Array<{ name: string; params: Record<string, unknown> }> = [];
  return {
    calls,
    rpc(name: string, params: Record<string, unknown>) {
      calls.push({ name, params });
      if (name === "whatsapp_template_reviews_checked_at_v1") {
        return Promise.resolve({ data: checkedAt, error: null });
      }
      return Promise.resolve({ data: 2, error: null });
    },
  };
}

Deno.test("only name, language, status, category and reason are kept", () => {
  const reviews = templateReviewsFromMeta([
    {
      id: "1",
      name: "taller_recibida_v1",
      language: "es_CL",
      status: "APPROVED",
      category: "UTILITY",
      components: [{}],
    },
    { name: "sin_estado", language: "es_CL" },
    "basura",
  ]);
  assert(reviews.length === 1, JSON.stringify(reviews));
  assert(
    JSON.stringify(reviews[0]) ===
      JSON.stringify({
        name: "taller_recibida_v1",
        language: "es_CL",
        status: "APPROVED",
        category: "UTILITY",
      }),
    JSON.stringify(reviews[0]),
  );
});

Deno.test("recording never throws", async () => {
  const failing = { rpc: () => Promise.reject(new Error("down")) };
  assert(
    await recordTemplateReviews(failing, "t", []) === false,
    "a failure is reported, not thrown",
  );
});

Deno.test("a fresh check does not ask Meta again", async () => {
  const store = fakeStore(new Date(Date.now() - 5 * 60_000).toISOString());
  let fetched = 0;
  const outcome = await refreshTemplateReviewsIfStale({
    store,
    tenantId: "t",
    accessToken: "token",
    apiVersion: "v23.0",
    businessAccountId: () => Promise.resolve("waba"),
    fetchFn: () => {
      fetched++;
      return Promise.resolve(new Response("{}"));
    },
  });
  assert(outcome === "fresh" && fetched === 0, outcome);
});

Deno.test("a stale check asks Meta and records the whole list", async () => {
  const store = fakeStore(new Date(Date.now() - 45 * 60_000).toISOString());
  const urls: string[] = [];
  const outcome = await refreshTemplateReviewsIfStale({
    store,
    tenantId: "t",
    accessToken: "token",
    apiVersion: "v23.0",
    businessAccountId: () => Promise.resolve("waba-1"),
    fetchFn: (input) => {
      urls.push(String(input));
      return Promise.resolve(
        new Response(JSON.stringify({
          data: [{ name: "taller_lista_v1", language: "es_CL", status: "PENDING" }],
        })),
      );
    },
  });
  assert(outcome === "refreshed", outcome);
  assert(urls[0].startsWith("https://graph.facebook.com/v23.0/waba-1/message_templates?"), urls[0]);
  const recorded = store.calls.find((call) => call.name === "record_whatsapp_template_reviews_v1");
  assert(
    recorded && JSON.stringify(recorded.params.p_templates) ===
        JSON.stringify([{ name: "taller_lista_v1", language: "es_CL", status: "PENDING" }]),
    JSON.stringify(recorded),
  );
});

Deno.test("without a channel, a token or an answer from Meta nothing breaks", async () => {
  const base = { tenantId: "t", apiVersion: "v23.0" };
  assert(
    await refreshTemplateReviewsIfStale({
      ...base,
      store: fakeStore(null),
      accessToken: "token",
      businessAccountId: () => Promise.resolve(null),
    }) === "no_channel",
    "no channel",
  );
  assert(
    await refreshTemplateReviewsIfStale({
      ...base,
      store: fakeStore(null),
      accessToken: "",
      businessAccountId: () => Promise.resolve("waba"),
    }) === "failed",
    "no token",
  );
  assert(
    await refreshTemplateReviewsIfStale({
      ...base,
      store: fakeStore(null),
      accessToken: "token",
      businessAccountId: () => Promise.resolve("waba"),
      fetchFn: () => Promise.resolve(new Response("{}", { status: 500 })),
    }) === "failed",
    "Meta down",
  );
});
