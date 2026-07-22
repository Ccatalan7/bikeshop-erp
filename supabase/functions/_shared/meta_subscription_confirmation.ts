type JsonRecord = Record<string, unknown>;

export type MetaGraphFetcher = (
  input: string | URL | Request,
  init?: RequestInit,
) => Promise<Response>;

export interface ConfirmMetaPageSubscriptionInput {
  pageId: string;
  token: string;
  fields: readonly string[];
  appId: string;
  graphVersion: string;
  fetcher?: MetaGraphFetcher;
}

export const META_PAGE_SUBSCRIPTION_FIELDS = [
  "messages",
  "messaging_postbacks",
  "message_deliveries",
  "message_reads",
  "message_echoes",
  "feed",
] as const;

// Facebook Login for Business configures these Instagram webhook fields at the
// app level in Meta App Dashboard. They must not be sent to an Instagram
// account's /subscribed_apps edge with the Page access token.
export const META_INSTAGRAM_APP_WEBHOOK_FIELDS = [
  "comments",
  "live_comments",
  "messages",
  "messaging_seen",
] as const;

function asRecord(value: unknown): JsonRecord | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : null;
}

async function responseJson(response: Response): Promise<unknown> {
  try {
    return await response.json();
  } catch {
    return null;
  }
}

export function isMetaSubscriptionMutationConfirmed(payload: unknown): boolean {
  return asRecord(payload)?.success === true;
}

export function hasSubscribedMetaApp(
  payload: unknown,
  appId: string,
  requiredFields: readonly string[],
): boolean {
  const data = asRecord(payload)?.data;
  if (
    !appId || !Array.isArray(data) || requiredFields.length === 0 ||
    requiredFields.some((field) =>
      typeof field !== "string" || field.length === 0 || field.trim() !== field
    )
  ) {
    return false;
  }

  return data.some((rawApp) => {
    const app = asRecord(rawApp);
    if (app?.id !== appId || !Array.isArray(app.subscribed_fields)) {
      return false;
    }
    if (
      app.subscribed_fields.some((field) => typeof field !== "string" || field.length === 0)
    ) {
      return false;
    }
    const subscribedFields = new Set(app.subscribed_fields as string[]);
    return requiredFields.every((field) => subscribedFields.has(field));
  });
}

// Installs the app on one Facebook Page and confirms the Page-level fields.
// Linked Instagram channels share this Page installation; their object fields
// are configured separately at the app level in Meta App Dashboard.
export async function confirmMetaPageSubscription(
  input: ConfirmMetaPageSubscriptionInput,
): Promise<boolean> {
  const fetcher = input.fetcher ?? fetch;
  const subscribedAppsUrl = new URL(
    `https://graph.facebook.com/${input.graphVersion}/${
      encodeURIComponent(input.pageId)
    }/subscribed_apps`,
  );

  try {
    const subscriptionResponse = await fetcher(subscribedAppsUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${input.token}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        subscribed_fields: input.fields.join(","),
      }),
      signal: AbortSignal.timeout(20_000),
    });
    if (!subscriptionResponse.ok) return false;
    const subscriptionPayload = await responseJson(subscriptionResponse);
    if (!isMetaSubscriptionMutationConfirmed(subscriptionPayload)) return false;

    const readBackUrl = new URL(subscribedAppsUrl);
    readBackUrl.searchParams.set("fields", "id,subscribed_fields");
    readBackUrl.searchParams.set("limit", "100");
    const readBackResponse = await fetcher(readBackUrl, {
      method: "GET",
      headers: { Authorization: `Bearer ${input.token}` },
      signal: AbortSignal.timeout(20_000),
    });
    if (!readBackResponse.ok) return false;
    return hasSubscribedMetaApp(
      await responseJson(readBackResponse),
      input.appId,
      input.fields,
    );
  } catch {
    return false;
  }
}
