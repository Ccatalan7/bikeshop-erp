export type MetaSendProvider = "instagram" | "facebook_messenger";

export interface MetaSendRequestInput {
  provider: string;
  /** `meta_channels.external_account_id`: the Page id or the Instagram id. */
  accountId: string;
  /** Page-scoped (PSID) or Instagram-scoped (IGSID) id of the person. */
  recipientId: string;
  /** The text of a text reply. Exactly one of `message` and `imageUrl`. */
  message?: string;
  /**
   * A short-lived signed link to a photo in the private attachment registry.
   * Meta fetches it while it accepts the send, so the link never needs to
   * outlive the request.
   */
  imageUrl?: string;
  graphVersion: string;
}

export interface MetaSendRequest {
  url: string;
  body: Record<string, unknown>;
}

/**
 * Graph request that sends one reply on a Meta channel: a text or a photo.
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
 * A photo goes as an `image` attachment whose payload is the URL Meta
 * downloads; neither channel takes a caption with it (2026-11-26).
 *
 * Returns null for a provider this integration does not send on, or when the
 * input is not exactly one text or one photo.
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
  const text = input.message?.trim() ?? "";
  const imageUrl = input.imageUrl?.trim() ?? "";
  if ((text === "") === (imageUrl === "")) return null;
  if (imageUrl !== "" && !imageUrl.startsWith("https://")) return null;
  return {
    url: `https://graph.facebook.com/${input.graphVersion}/${node}/messages`,
    body: {
      recipient: { id: input.recipientId },
      message: imageUrl !== ""
        ? { attachment: { type: "image", payload: { url: imageUrl } } }
        : { text: input.message },
      ...(input.provider === "facebook_messenger"
        ? { messaging_type: "RESPONSE" }
        : {}),
    },
  };
}
