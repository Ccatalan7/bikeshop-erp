import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  fetchMetaContactProfile,
  interpretMetaContactProfile,
  metaContactProfileUrl,
  metaGraphVersion,
  resolveDueMetaContactProfiles,
} from "./meta_contact_profile.ts";

type Call = { name: string; args: Record<string, unknown> };

function fakeClient(responses: Record<string, unknown>, failing: string[] = []) {
  const calls: Call[] = [];
  return {
    calls,
    client: {
      rpc(name: string, args: Record<string, unknown>) {
        calls.push({ name, args });
        return Promise.resolve(
          failing.includes(name)
            ? { data: null, error: { code: "P0002" } }
            : { data: name in responses ? responses[name] : {}, error: null },
        );
      },
    },
  };
}

function graph(answers: Record<string, { status: number; body: unknown }>) {
  const requests: { url: string; authorization: string | null; bounded: boolean }[] = [];
  const fetchImpl = (url: string, init?: RequestInit) => {
    requests.push({
      url,
      authorization: new Headers(init?.headers).get("authorization"),
      bounded: init?.signal instanceof AbortSignal,
    });
    const id = Object.keys(answers).find((key) => url.includes(`/${key}?`));
    const answer = id ? answers[id] : { status: 404, body: {} };
    return Promise.resolve(
      new Response(JSON.stringify(answer.body), { status: answer.status }),
    );
  };
  return { requests, fetchImpl };
}

Deno.test("the profile request asks only for the name and the username", () => {
  assertEquals(
    metaContactProfileUrl("v25.0", "instagram", "178/41"),
    "https://graph.facebook.com/v25.0/178%2F41?fields=name,username",
  );
  assertEquals(
    metaContactProfileUrl("v25.0", "facebook_messenger", "555"),
    "https://graph.facebook.com/v25.0/555?fields=name",
  );
  assertEquals(metaContactProfileUrl("v25.0", "whatsapp", "555"), null);
});

Deno.test("a profile is a name, a username or both", () => {
  assertEquals(
    interpretMetaContactProfile(200, { name: " Camila Rojas ", username: "camila.rojas" }),
    { ok: true, name: "Camila Rojas", username: "camila.rojas" },
  );
  // Many Instagram accounts have no display name.
  assertEquals(
    interpretMetaContactProfile(200, { username: "solo.usuario", id: "1" }),
    { ok: true, name: null, username: "solo.usuario" },
  );
  assertEquals(
    interpretMetaContactProfile(200, { id: "1" }),
    { ok: false, error: "empty_profile", retrySoon: false },
  );
});

Deno.test("a refusal is a code, and only an outage is retried soon", () => {
  // Permission or consent: wait a day; the app review may change the answer.
  assertEquals(
    interpretMetaContactProfile(400, {
      error: { message: "(#10) no permission", code: 10 },
    }),
    { ok: false, error: "graph_10", retrySoon: false },
  );
  assertEquals(
    interpretMetaContactProfile(400, {
      error: { message: "consent", code: 100, error_subcode: 2018218 },
    }),
    { ok: false, error: "graph_100_2018218", retrySoon: false },
  );
  // A rate limit also waits.
  assertEquals(
    interpretMetaContactProfile(400, { error: { code: 4 } }),
    { ok: false, error: "graph_4", retrySoon: false },
  );
  assertEquals(
    interpretMetaContactProfile(500, { error: { code: 2 } }),
    { ok: false, error: "graph_2", retrySoon: true },
  );
  assertEquals(
    interpretMetaContactProfile(502, "<html>"),
    { ok: false, error: "http_502", retrySoon: true },
  );
});

Deno.test("the token travels in the header, never in the URL", async () => {
  const { requests, fetchImpl } = graph({
    "igsid-1": { status: 200, body: { name: "Camila Rojas" } },
  });
  const profile = await fetchMetaContactProfile({
    graphVersion: "v25.0",
    provider: "instagram",
    externalUserId: "igsid-1",
    accessToken: "page-token",
    fetchImpl,
  });
  assertEquals(profile, { ok: true, name: "Camila Rojas", username: null });
  assertEquals(requests[0].authorization, "Bearer page-token");
  assertEquals(requests[0].url.includes("page-token"), false);
  // A sweep asks one contact after another: a request that never answers
  // must not hold the rest.
  assertEquals(requests[0].bounded, true);
});

Deno.test("the Graph version is the configured one only when it is a version", () => {
  assertEquals(metaGraphVersion("v26.0"), "v26.0");
  assertEquals(metaGraphVersion("latest"), "v25.0");
  assertEquals(metaGraphVersion("v26.0/../x"), "v25.0");
  assertEquals(metaGraphVersion(""), "v25.0");
  assertEquals(metaGraphVersion(null), "v25.0");
});

Deno.test("a network failure is retried soon", async () => {
  const profile = await fetchMetaContactProfile({
    graphVersion: "v25.0",
    provider: "instagram",
    externalUserId: "igsid-1",
    accessToken: "page-token",
    fetchImpl: () => Promise.reject(new Error("offline")),
  });
  assertEquals(profile, { ok: false, error: "network", retrySoon: true });
});

Deno.test("the sweep names who Meta answers for and records why not for the rest", async () => {
  const { client, calls } = fakeClient({
    claim_meta_contact_profiles_due: {
      channel_id: "channel-1",
      provider: "instagram",
      contacts: [
        { binding_id: "binding-1", external_user_id: "igsid-1" },
        { binding_id: "binding-2", external_user_id: "igsid-2" },
      ],
    },
    get_meta_channel_access_token: { access_token: "page-token" },
  });
  const { fetchImpl } = graph({
    "igsid-1": { status: 200, body: { name: "Camila Rojas", username: "camila.rojas" } },
    "igsid-2": { status: 400, body: { error: { code: 10 } } },
  });
  const sweep = await resolveDueMetaContactProfiles({
    client,
    provider: "instagram",
    accountId: "ig-account",
    graphVersion: "v25.0",
    fetchImpl,
  });
  assertEquals(sweep, { claimed: 2, resolved: 1, errors: ["graph_10"] });
  assertEquals(calls[0], {
    name: "claim_meta_contact_profiles_due",
    args: { p_provider: "instagram", p_external_account_id: "ig-account", p_limit: 3 },
  });
  assertEquals(
    calls.filter((call) => call.name === "record_meta_contact_profile").map((call) => call.args),
    [
      {
        p_binding_id: "binding-1",
        p_contact_name: "Camila Rojas",
        p_username: "camila.rojas",
        p_error: null,
        p_retry_soon: false,
      },
      {
        p_binding_id: "binding-2",
        p_contact_name: null,
        p_username: null,
        p_error: "graph_10",
        p_retry_soon: false,
      },
    ],
  );
});

Deno.test("nobody due means no token is read and Meta is not called", async () => {
  const { client, calls } = fakeClient({
    claim_meta_contact_profiles_due: { channel_id: "channel-1", contacts: [] },
  });
  const { requests, fetchImpl } = graph({});
  const sweep = await resolveDueMetaContactProfiles({
    client,
    provider: "instagram",
    accountId: "ig-account",
    graphVersion: "v25.0",
    fetchImpl,
  });
  assertEquals(sweep, { claimed: 0, resolved: 0, errors: [] });
  assertEquals(calls.map((call) => call.name), ["claim_meta_contact_profiles_due"]);
  assertEquals(requests.length, 0);
});

Deno.test("without the channel token the contacts wait and Meta is not called", async () => {
  const { client, calls } = fakeClient(
    {
      claim_meta_contact_profiles_due: {
        channel_id: "channel-1",
        contacts: [{ binding_id: "binding-1", external_user_id: "igsid-1" }],
      },
    },
    ["get_meta_channel_access_token"],
  );
  const { requests, fetchImpl } = graph({});
  const sweep = await resolveDueMetaContactProfiles({
    client,
    provider: "instagram",
    accountId: "ig-account",
    graphVersion: "v25.0",
    fetchImpl,
  });
  assertEquals(sweep, { claimed: 1, resolved: 0, errors: ["credential_unavailable"] });
  assertEquals(requests.length, 0);
  assertEquals(calls.at(-1)?.args.p_retry_soon, false);
});

Deno.test("the sweep never throws into the webhook", async () => {
  const sweep = await resolveDueMetaContactProfiles({
    client: {
      rpc() {
        throw new Error("database unreachable");
      },
    },
    provider: "instagram",
    accountId: "ig-account",
    graphVersion: "v25.0",
  });
  assertEquals(sweep, { claimed: 0, resolved: 0, errors: ["sweep_failed"] });
});
