// The scheduled sweep of a Meta channel (Instagram or Messenger).
//
// The webhook names a contact and fetches a file when the message arrives.
// The sweep does the same for what no event comes for: the conversations and
// photos that already existed when each job was built, what Meta refused the
// day before, what failed. Without it the owner saw codes instead of names
// and «Imagen recibida» instead of photos until somebody wrote again
// (2026-11-10).
//
// The database starts it on a schedule (`dispatch_meta_channel_sweeps`) and
// is the only one that can. The function that serves it is open to the
// internet, so the single-use ticket the database minted for that channel is
// the only authority: a request without it is refused before anybody is
// claimed and before Meta is asked.

import {
  type MetaContactProfileSweep,
  type MetaFetch,
  resolveDueMetaContactProfiles,
} from "./meta_contact_profile.ts";
import {
  type MetaMediaClient,
  type MetaMessageMediaSweep,
  resolveDueMetaMessageMedia,
} from "./meta_message_media.ts";

type JsonRecord = Record<string, unknown>;

const SWEEP_CHANNEL_ID = /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const SWEEP_TICKET = /^[0-9a-f]{64}$/;

/** A scheduled sweep asks for as many contacts as one claim allows. */
export const SCHEDULED_PROFILE_LIMIT = 10;
/** Files are downloads of up to 16 MB each: fewer per run. */
export const SCHEDULED_MEDIA_LIMIT = 5;

export type MetaChannelSweepAnswer = {
  status: number;
  body:
    | { ok: false; error: string }
    | {
      ok: true;
      provider: string;
      profiles: MetaContactProfileSweep;
      media: MetaMessageMediaSweep;
    };
};

function text(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed ? trimmed.slice(0, 200) : null;
}

/** Runs the sweep a ticket opens. The answer carries counts and codes, never
 * a name, an id or a URL. */
export async function runScheduledMetaChannelSweep(params: {
  client: MetaMediaClient;
  payload: unknown;
  graphVersion?: string;
  fetchImpl?: MetaFetch;
}): Promise<MetaChannelSweepAnswer> {
  const refused: MetaChannelSweepAnswer = {
    status: 403,
    body: { ok: false, error: "forbidden" },
  };
  const payload = params.payload && typeof params.payload === "object"
    ? params.payload as JsonRecord
    : {};
  const channelId = typeof payload.channel_id === "string" ? payload.channel_id : "";
  const ticket = typeof payload.token === "string" ? payload.token : "";
  if (!SWEEP_CHANNEL_ID.test(channelId) || !SWEEP_TICKET.test(ticket)) return refused;

  let account: JsonRecord | null;
  try {
    const { data, error } = await params.client.rpc(
      "redeem_meta_channel_sweep_ticket",
      { p_channel_id: channelId, p_token: ticket },
    );
    if (error) {
      return {
        status: 500,
        body: { ok: false, error: `redeem_${error.code ?? "rpc_error"}` },
      };
    }
    account = data && typeof data === "object" ? data as JsonRecord : null;
  } catch (_) {
    return { status: 500, body: { ok: false, error: "redeem_failed" } };
  }
  const provider = text(account?.provider);
  const accountId = text(account?.external_account_id);
  if (!provider || !accountId) return refused;

  const profiles = await resolveDueMetaContactProfiles({
    client: params.client,
    provider,
    accountId,
    graphVersion: params.graphVersion,
    limit: SCHEDULED_PROFILE_LIMIT,
    fetchImpl: params.fetchImpl,
  });
  const media = await resolveDueMetaMessageMedia({
    client: params.client,
    provider,
    accountId,
    graphVersion: params.graphVersion,
    limit: SCHEDULED_MEDIA_LIMIT,
    fetchImpl: params.fetchImpl,
  });
  return { status: 200, body: { ok: true, provider, profiles, media } };
}
