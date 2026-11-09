export type MetaSendProvider = "instagram" | "facebook_messenger";

export interface MetaSendRequestInput {
  provider: string;
  /** `meta_channels.external_account_id`: the Page id or the Instagram id. */
  accountId: string;
  /** Page-scoped (PSID) or Instagram-scoped (IGSID) id of the person. */
  recipientId: string;
  message: string;
  graphVersion: string;
}

export interface MetaSendRequest {
  url: string;
  body: Record<string, unknown>;
}

/**
 * Graph request that sends one text reply on a Meta channel.
 *
 * Both channels authenticate with the Page access token stored when the
 * channel was connected through Facebook Login for Business, so both send
 * from the Facebook Page:
 *
 * - Messenger posts to `/{page-id}/messages`, the account id itself.
 * - Instagram posts to `/me/messages`, which the Page token resolves to the
 *   Page linked to the professional account. It never posts to
 *   `/{instagram-id}/messages`: with this login Graph answers (#100) subcode
 *   33, «Object with ID … does not support this operation» (the only reply
 *   ever attempted, 2026-10-16). That node belongs to the Instagram Login API
 *   on graph.instagram.com with an Instagram user token, which this
 *   integration does not hold.
 *
 * Returns null for a provider this integration does not send on.
 */
export function buildMetaSendRequest(
  input: MetaSendRequestInput,
): MetaSendRequest | null {
  const node = input.provider === "instagram"
    ? "me"
    : input.provider === "facebook_messenger"
    ? encodeURIComponent(input.accountId)
    : null;
  if (!node) return null;
  return {
    url: `https://graph.facebook.com/${input.graphVersion}/${node}/messages`,
    body: {
      recipient: { id: input.recipientId },
      message: { text: input.message },
      ...(input.provider === "facebook_messenger"
        ? { messaging_type: "RESPONSE" }
        : {}),
    },
  };
}
