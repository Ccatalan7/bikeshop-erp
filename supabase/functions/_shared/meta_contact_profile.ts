// The name behind an Instagram or Messenger conversation.
//
// Meta's messaging webhook carries only the sender's scoped id (IGSID or
// PSID). The name and the username come from a separate Graph request, the
// User Profile API. Until 2026-11-09 nothing made that request, so every
// conversation was titled «Instagram • 1B5849» (owner: «por qué se ven con ese
// código raro y no con el nombre del cliente?»).
//
// The webhook calls `resolveDueMetaContactProfiles` after it has stored its
// events. The database decides who is due (`claim_meta_contact_profiles_due`:
// no name yet, and not asked in the last day) and where the answer goes
// (`record_meta_contact_profile`: the service-only binding and the
// conversation title). Message metadata keeps its pseudonymous label.
//
// A refusal is expected, not exceptional. Meta answers only for people who
// wrote to the business, and under Standard Access it may answer only for
// people with a role on the app. A refused contact keeps its code and is asked
// again a day later, which names it once the app review is approved.

type JsonRecord = Record<string, unknown>;

export type MetaContactProfile =
  | { ok: true; name: string | null; username: string | null }
  | { ok: false; error: string; retrySoon: boolean };

type RpcClient = {
  rpc(
    name: string,
    args: JsonRecord,
  ): PromiseLike<{ data: unknown; error: { code?: string } | null }>;
};

type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;

// Instagram contacts have a username and often no display name. Messenger
// contacts have a name only.
const PROFILE_FIELDS: Record<string, string> = {
  instagram: "name,username",
  facebook_messenger: "name",
};

// Graph codes that mean «try again shortly»: unknown error and service
// unavailable. Rate limits (4, 17, 32, 613) wait a day like any refusal.
const TRANSIENT_GRAPH_CODES = new Set([1, 2]);

export function metaContactProfileUrl(
  graphVersion: string,
  provider: string,
  externalUserId: string,
): string | null {
  const fields = PROFILE_FIELDS[provider];
  if (!fields || !externalUserId) return null;
  return `https://graph.facebook.com/${graphVersion}/${
    encodeURIComponent(externalUserId)
  }?fields=${fields}`;
}

function text(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed ? trimmed.slice(0, 200) : null;
}

/** Reads a Graph answer. The stored error is a code, never Meta's message. */
export function interpretMetaContactProfile(
  status: number,
  body: unknown,
): MetaContactProfile {
  const record = body && typeof body === "object" ? body as JsonRecord : {};
  if (status >= 200 && status < 300) {
    const name = text(record.name);
    const username = text(record.username);
    if (name || username) return { ok: true, name, username };
    return { ok: false, error: "empty_profile", retrySoon: false };
  }
  const graphError = record.error && typeof record.error === "object"
    ? record.error as JsonRecord
    : null;
  const code = Number(graphError?.code);
  if (graphError && Number.isFinite(code)) {
    const subcode = Number(graphError.error_subcode);
    return {
      ok: false,
      error: Number.isFinite(subcode) && subcode > 0 ? `graph_${code}_${subcode}` : `graph_${code}`,
      retrySoon: TRANSIENT_GRAPH_CODES.has(code),
    };
  }
  return { ok: false, error: `http_${status}`, retrySoon: status >= 500 };
}

export async function fetchMetaContactProfile(params: {
  graphVersion: string;
  provider: string;
  externalUserId: string;
  accessToken: string;
  fetchImpl?: FetchLike;
}): Promise<MetaContactProfile> {
  const url = metaContactProfileUrl(
    params.graphVersion,
    params.provider,
    params.externalUserId,
  );
  if (!url) return { ok: false, error: "unsupported_provider", retrySoon: false };
  try {
    const response = await (params.fetchImpl ?? fetch)(url, {
      headers: { Authorization: `Bearer ${params.accessToken}` },
    });
    const body = await response.json().catch(() => ({}));
    return interpretMetaContactProfile(response.status, body);
  } catch (_) {
    return { ok: false, error: "network", retrySoon: true };
  }
}

export type MetaContactProfileSweep = {
  claimed: number;
  resolved: number;
  /** One short code per contact that got no name. */
  errors: string[];
};

/** Names the contacts of one Meta account that are due. Never throws: the
 * webhook that calls it has already stored its events. */
export async function resolveDueMetaContactProfiles(params: {
  client: RpcClient;
  provider: string;
  accountId: string;
  graphVersion: string;
  limit?: number;
  fetchImpl?: FetchLike;
}): Promise<MetaContactProfileSweep> {
  const sweep: MetaContactProfileSweep = { claimed: 0, resolved: 0, errors: [] };
  try {
    const { data: claimData, error: claimError } = await params.client.rpc(
      "claim_meta_contact_profiles_due",
      {
        p_provider: params.provider,
        p_external_account_id: params.accountId,
        p_limit: params.limit ?? 3,
      },
    );
    if (claimError) {
      sweep.errors.push(`claim_${claimError.code ?? "rpc_error"}`);
      return sweep;
    }
    const claim = (claimData ?? {}) as JsonRecord;
    const channelId = text(claim.channel_id);
    const contacts = Array.isArray(claim.contacts) ? claim.contacts as JsonRecord[] : [];
    sweep.claimed = contacts.length;
    if (!channelId || contacts.length === 0) return sweep;

    const record = async (
      bindingId: string,
      profile: MetaContactProfile,
    ) => {
      const { error } = await params.client.rpc("record_meta_contact_profile", {
        p_binding_id: bindingId,
        p_contact_name: profile.ok ? profile.name : null,
        p_username: profile.ok ? profile.username : null,
        p_error: profile.ok ? null : profile.error,
        p_retry_soon: profile.ok ? false : profile.retrySoon,
      });
      if (error) {
        sweep.errors.push(`record_${error.code ?? "rpc_error"}`);
      } else if (profile.ok) {
        sweep.resolved += 1;
      } else {
        sweep.errors.push(profile.error);
      }
    };

    const { data: credentialData, error: credentialError } = await params.client.rpc(
      "get_meta_channel_access_token",
      { p_channel_id: channelId },
    );
    const rawToken = ((credentialData ?? {}) as JsonRecord).access_token;
    const accessToken = typeof rawToken === "string" && rawToken ? rawToken : null;
    for (const contact of contacts) {
      const bindingId = text(contact.binding_id);
      const externalUserId = text(contact.external_user_id);
      if (!bindingId || !externalUserId) continue;
      if (credentialError || !accessToken) {
        // Without the channel's token nobody can be asked. It waits a day
        // like a refusal, so a broken channel does not retry on every event.
        await record(bindingId, {
          ok: false,
          error: "credential_unavailable",
          retrySoon: false,
        });
        continue;
      }
      await record(
        bindingId,
        await fetchMetaContactProfile({
          graphVersion: params.graphVersion,
          provider: params.provider,
          externalUserId,
          accessToken,
          fetchImpl: params.fetchImpl,
        }),
      );
    }
  } catch (_) {
    sweep.errors.push("sweep_failed");
  }
  return sweep;
}
