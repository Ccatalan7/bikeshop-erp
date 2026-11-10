import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { runScheduledMetaChannelSweep } from "./meta_channel_sweep.ts";

type Call = { name: string; args: Record<string, unknown> };

function fakeClient(responses: Record<string, unknown>, failing: string[] = []) {
  const calls: Call[] = [];
  const stored: string[] = [];
  return {
    calls,
    stored,
    client: {
      rpc(name: string, args: Record<string, unknown>) {
        calls.push({ name, args });
        return Promise.resolve(
          failing.includes(name)
            ? { data: null, error: { code: "P0002" } }
            : { data: name in responses ? responses[name] : {}, error: null },
        );
      },
      storage: {
        from(_bucket: string) {
          return {
            upload(path: string, _body: Blob, _options: { contentType: string; upsert: boolean }) {
              stored.push(path);
              return Promise.resolve({ error: null });
            },
            remove(_paths: string[]) {
              return Promise.resolve({ error: null });
            },
          };
        },
      },
    },
  };
}

function noNetwork() {
  const requests: string[] = [];
  return {
    requests,
    fetchImpl: (url: string) => {
      requests.push(url);
      return Promise.resolve(new Response("{}", { status: 404 }));
    },
  };
}

const CHANNEL = "c0a75eeb-0001-4000-8000-000000000001";
const TICKET = "ab".repeat(32);

// The function that serves the sweep is open to the internet: the ticket the
// database issued is the only thing that opens it.
Deno.test("a sweep without a well-formed ticket touches nothing", async () => {
  for (
    const payload of [
      null,
      "text",
      {},
      { channel_id: CHANNEL },
      { token: TICKET },
      { channel_id: "not-a-channel", token: TICKET },
      { channel_id: CHANNEL, token: "short" },
      { channel_id: CHANNEL, token: `${TICKET}00` },
      { channel_id: CHANNEL, token: TICKET.toUpperCase() },
      { channel_id: 7, token: 7 },
    ]
  ) {
    const { client, calls } = fakeClient({});
    const { requests, fetchImpl } = noNetwork();
    const answer = await runScheduledMetaChannelSweep({ client, payload, fetchImpl });
    assertEquals(answer, { status: 403, body: { ok: false, error: "forbidden" } });
    assertEquals(calls.length, 0, JSON.stringify(payload));
    assertEquals(requests.length, 0);
  }
});

Deno.test("a ticket the database does not honour claims nothing and asks nothing", async () => {
  const { client, calls } = fakeClient({ redeem_meta_channel_sweep_ticket: null });
  const { requests, fetchImpl } = noNetwork();
  const answer = await runScheduledMetaChannelSweep({
    client,
    payload: { channel_id: CHANNEL, token: TICKET },
    fetchImpl,
  });
  assertEquals(answer, { status: 403, body: { ok: false, error: "forbidden" } });
  assertEquals(calls, [{
    name: "redeem_meta_channel_sweep_ticket",
    args: { p_channel_id: CHANNEL, p_token: TICKET },
  }]);
  assertEquals(requests.length, 0);
});

Deno.test("a ticket that cannot be checked is an error, not a pass", async () => {
  const { client, calls } = fakeClient({}, ["redeem_meta_channel_sweep_ticket"]);
  const answer = await runScheduledMetaChannelSweep({
    client,
    payload: { channel_id: CHANNEL, token: TICKET },
  });
  assertEquals(answer, { status: 500, body: { ok: false, error: "redeem_P0002" } });
  assertEquals(calls.length, 1);

  const { client: reachable } = fakeClient({});
  const unreachable = await runScheduledMetaChannelSweep({
    client: {
      ...reachable,
      rpc() {
        throw new Error("database unreachable");
      },
    },
    payload: { channel_id: CHANNEL, token: TICKET },
  });
  assertEquals(unreachable, { status: 500, body: { ok: false, error: "redeem_failed" } });
});

Deno.test("a redeemed ticket names the contacts and fetches the files of its account", async () => {
  const { client, calls, stored } = fakeClient({
    redeem_meta_channel_sweep_ticket: {
      provider: "instagram",
      external_account_id: "ig-account",
    },
    claim_meta_contact_profiles_due: {
      channel_id: "channel-1",
      provider: "instagram",
      contacts: [
        { binding_id: "binding-1", external_user_id: "igsid-1" },
        { binding_id: "binding-2", external_user_id: "igsid-2" },
      ],
    },
    claim_meta_message_media_due: {
      channel_id: "channel-1",
      provider: "instagram",
      messages: [{
        message_id: "11111111-1111-4111-8111-111111111111",
        tenant_id: "22222222-2222-4222-8222-222222222222",
        conversation_id: "33333333-3333-4333-8333-333333333333",
        external_message_id: "mid-photo",
        media_type: "image",
      }],
    },
    get_meta_channel_access_token: { access_token: "page-token" },
    attach_meta_message_media: { attached: true },
  });
  const photoUrl = "https://lookaside.fbsbx.com/ig_messaging_cdn/?asset_id=1&signature=s";
  const requests: string[] = [];
  const fetchImpl = (url: string) => {
    requests.push(url);
    if (url.includes("/igsid-1?")) {
      return Promise.resolve(Response.json({ username: "solo.usuario" }));
    }
    if (url.includes("/igsid-2?")) {
      return Promise.resolve(
        Response.json({ error: { code: 100, error_subcode: 2018218 } }, { status: 400 }),
      );
    }
    if (url.includes("/mid-photo?")) {
      return Promise.resolve(
        Response.json({ attachments: { data: [{ image_data: { url: photoUrl } }] } }),
      );
    }
    if (url === photoUrl) {
      return Promise.resolve(
        new Response(new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]), {
          headers: { "content-type": "image/jpeg" },
        }),
      );
    }
    return Promise.resolve(new Response("{}", { status: 404 }));
  };
  const answer = await runScheduledMetaChannelSweep({
    client,
    payload: { channel_id: CHANNEL, token: TICKET },
    graphVersion: "v25.0",
    fetchImpl,
  });
  assertEquals(answer, {
    status: 200,
    body: {
      ok: true,
      provider: "instagram",
      profiles: { claimed: 2, resolved: 1, errors: ["graph_100_2018218"] },
      media: { claimed: 1, attached: 1, errors: [] },
    },
  });
  // The ticket is redeemed before anything is claimed, and the claims are the
  // wide ones: a sweep has no event to keep waiting.
  assertEquals(calls[0], {
    name: "redeem_meta_channel_sweep_ticket",
    args: { p_channel_id: CHANNEL, p_token: TICKET },
  });
  assertEquals(
    calls.filter((call) => call.name.startsWith("claim_")),
    [
      {
        name: "claim_meta_contact_profiles_due",
        args: { p_provider: "instagram", p_external_account_id: "ig-account", p_limit: 10 },
      },
      {
        name: "claim_meta_message_media_due",
        args: { p_provider: "instagram", p_external_account_id: "ig-account", p_limit: 5 },
      },
    ],
  );
  assertEquals(stored.length, 1);
  // Nothing of a person leaves in the answer.
  const serialized = JSON.stringify(answer.body);
  for (
    const secret of [
      "igsid",
      "solo.usuario",
      "binding-",
      "page-token",
      TICKET,
      "mid-photo",
      "fbsbx",
    ]
  ) {
    assertEquals(serialized.includes(secret), false, secret);
  }
});
