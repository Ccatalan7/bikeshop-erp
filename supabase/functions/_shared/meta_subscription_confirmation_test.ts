import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  confirmMetaPageSubscription,
  hasSubscribedMetaApp,
  META_INSTAGRAM_APP_WEBHOOK_FIELDS,
  META_PAGE_SUBSCRIPTION_FIELDS,
  type MetaGraphFetcher,
} from "./meta_subscription_confirmation.ts";

function subscriptionInput(fetcher: MetaGraphFetcher) {
  return {
    pageId: "page-1",
    token: "page-token",
    fields: ["messages", "feed"],
    appId: "app-123",
    graphVersion: "v25.0",
    fetcher,
  };
}

Deno.test("confirms a Page subscription only after exact mutation success and app read-back", async () => {
  const requests: Array<{ url: URL; init?: RequestInit }> = [];
  const fetcher: MetaGraphFetcher = (input, init) => {
    requests.push({ url: new URL(String(input)), init });
    return Promise.resolve(
      requests.length === 1 ? Response.json({ success: true }) : Response.json({
        data: [
          { id: "other-app", subscribed_fields: ["messages", "feed"] },
          {
            id: "app-123",
            subscribed_fields: ["feed", "messages", "message_echoes"],
          },
        ],
      }),
    );
  };

  assertEquals(
    await confirmMetaPageSubscription(subscriptionInput(fetcher)),
    true,
  );
  assertEquals(requests.length, 2);
  assertEquals(requests[0].url.origin, "https://graph.facebook.com");
  assertEquals(requests[0].url.pathname, "/v25.0/page-1/subscribed_apps");
  assertEquals(requests[0].init?.method, "POST");
  assertEquals(String(requests[0].init?.body), "subscribed_fields=messages%2Cfeed");
  assertEquals(requests[0].url.search, "");
  assertEquals(requests[1].init?.method, "GET");
  assertEquals(
    requests[1].url.searchParams.get("fields"),
    "id,subscribed_fields",
  );
  assertEquals(requests[1].url.searchParams.get("limit"), "100");
  assertEquals(requests[1].url.toString().includes("page-token"), false);
});

Deno.test("rejects non-2xx or non-boolean mutation confirmations without read-back", async () => {
  for (
    const response of [
      new Response(JSON.stringify({ success: true }), { status: 400 }),
      Response.json({ success: "true" }),
      Response.json({ success: 1 }),
      Response.json({ success: false }),
      new Response("not-json"),
    ]
  ) {
    let calls = 0;
    const fetcher: MetaGraphFetcher = () => {
      calls += 1;
      return Promise.resolve(response.clone());
    };
    assertEquals(
      await confirmMetaPageSubscription(subscriptionInput(fetcher)),
      false,
    );
    assertEquals(calls, 1);
  }
});

Deno.test("fails closed when subscribed_apps read-back does not contain this app", async () => {
  for (
    const readBackResponse of [
      Response.json({
        data: [{ id: "other-app", subscribed_fields: ["messages", "feed"] }],
      }),
      Response.json({
        data: [{ id: 123, subscribed_fields: ["messages", "feed"] }],
      }),
      Response.json({ data: [] }),
      Response.json(
        { data: [{ id: "app-123", subscribed_fields: ["messages", "feed"] }] },
        { status: 503 },
      ),
      new Response("not-json"),
    ]
  ) {
    let calls = 0;
    const fetcher: MetaGraphFetcher = () => {
      calls += 1;
      return Promise.resolve(
        calls === 1 ? Response.json({ success: true }) : readBackResponse.clone(),
      );
    };
    assertEquals(
      await confirmMetaPageSubscription(subscriptionInput(fetcher)),
      false,
    );
    assertEquals(calls, 2);
  }
});

Deno.test("requires every requested field while tolerating extra subscribed fields", () => {
  assertEquals(
    hasSubscribedMetaApp(
      {
        data: [{
          id: "app-123",
          subscribed_fields: ["feed", "message_echoes", "messages"],
        }],
      },
      "app-123",
      ["messages", "feed"],
    ),
    true,
  );
  assertEquals(
    hasSubscribedMetaApp(
      {
        data: [{
          id: "app-123",
          subscribed_fields: ["messages", "message_echoes"],
        }],
      },
      "app-123",
      ["messages", "feed"],
    ),
    false,
  );
});

Deno.test("fails closed on malformed subscribed_fields evidence", () => {
  for (
    const payload of [
      { data: [{ id: "app-123" }] },
      { data: [{ id: "app-123", subscribed_fields: "messages,feed" }] },
      { data: [{ id: "app-123", subscribed_fields: ["messages", 123, "feed"] }] },
      { data: [{ id: "app-123", subscribed_fields: ["messages", ""] }] },
      { data: { id: "app-123", subscribed_fields: ["messages", "feed"] } },
    ]
  ) {
    assertEquals(
      hasSubscribedMetaApp(payload, "app-123", ["messages", "feed"]),
      false,
    );
  }

  assertEquals(
    hasSubscribedMetaApp(
      {
        data: [{ id: "app-123", subscribed_fields: ["messages", "feed"] }],
      },
      "app-123",
      [],
    ),
    false,
  );
});

Deno.test("uses the exact Graph v25 Page webhook field names", () => {
  assertEquals(META_PAGE_SUBSCRIPTION_FIELDS, [
    "messages",
    "messaging_postbacks",
    "message_deliveries",
    "message_reads",
    "message_echoes",
    "feed",
  ]);
});

Deno.test("documents the app-level Instagram webhook fields for Facebook Login", () => {
  assertEquals(META_INSTAGRAM_APP_WEBHOOK_FIELDS, [
    "comments",
    "live_comments",
    "messages",
    "messaging_seen",
  ]);
});

Deno.test("fails closed on provider transport errors", async () => {
  const fetcher: MetaGraphFetcher = () => Promise.reject(new Error("network"));
  assertEquals(
    await confirmMetaPageSubscription(subscriptionInput(fetcher)),
    false,
  );
});
