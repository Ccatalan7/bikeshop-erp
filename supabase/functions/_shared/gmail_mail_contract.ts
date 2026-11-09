import { mailProviderRateLimitRetryAt } from "./mail_provider_rate_limit.ts";

export const GMAIL_API_ORIGIN = "https://www.googleapis.com";

const gmailMessageFields = [
  "id",
  "threadId",
  "labelIds",
  "snippet",
  "internalDate",
  "payload(headers(name,value),filename,mimeType,body(attachmentId,size),parts(filename,mimeType,headers(name,value),body(attachmentId,size),parts(filename,mimeType,headers(name,value),body(attachmentId,size),parts(filename,mimeType,headers(name,value),body(attachmentId,size)))))",
].join(",");

export function parseKnownGmailIds(value: unknown): Set<string> {
  if (!Array.isArray(value)) return new Set();
  return new Set(
    value
      .map((item) => String(item ?? "").trim())
      .filter((item) => item.length > 0)
      .slice(0, 500),
  );
}

/**
 * Reconciles provider-owned Inbox membership and read state without issuing a
 * `messages.get` request for every cached row. Gmail's list endpoint can return
 * the newest 500 Inbox IDs and the newest 500 unread Inbox IDs for five quota
 * units each; every unread message inside the newest 500 Inbox rows is
 * necessarily present in that unread window.
 *
 * IDs absent from [currentInboxIds] are intentionally omitted. The caller can
 * therefore treat this as an authoritative snapshot for the same bounded
 * cache window and remove messages that were archived, trashed, or displaced
 * beyond it.
 */
export function buildKnownGmailInboxMarkers(
  currentInboxIds: readonly string[],
  unreadInboxIds: ReadonlySet<string>,
  knownIds: ReadonlySet<string>,
): Array<Record<string, unknown>> {
  const emitted = new Set<string>();
  const markers: Array<Record<string, unknown>> = [];

  for (const rawId of currentInboxIds) {
    const id = String(rawId ?? "").trim();
    if (!id || emitted.has(id) || !knownIds.has(id)) continue;
    emitted.add(id);
    markers.push({
      id,
      known: true,
      labelIds: unreadInboxIds.has(id) ? ["INBOX", "UNREAD"] : ["INBOX"],
    });
  }

  return markers;
}

/**
 * Chooses the bounded set of unknown messages that needs full metadata.
 * Visible new messages are always included. If cached rows left Inbox, older
 * unknown rows are added only far enough to fill those holes; a routine
 * refresh must not silently preload the rest of the 500-row snapshot.
 */
export function selectUnknownGmailInboxDetailIds(
  currentInboxIds: readonly string[],
  visibleInboxIds: readonly string[],
  knownIds: ReadonlySet<string>,
  maxDetails: number,
): string[] {
  const current = Array.from(
    new Set(currentInboxIds.map((id) => String(id ?? "").trim()).filter(Boolean)),
  );
  const visible = Array.from(
    new Set(visibleInboxIds.map((id) => String(id ?? "").trim()).filter(Boolean)),
  );
  const selected = visible.filter((id) => !knownIds.has(id));
  const selectedSet = new Set(selected);
  const presentKnownCount = current.reduce(
    (count, id) => count + (knownIds.has(id) ? 1 : 0),
    0,
  );
  let replacementsNeeded = Math.max(
    0,
    knownIds.size - presentKnownCount - selected.length,
  );

  for (const id of current) {
    if (selected.length >= maxDetails || replacementsNeeded <= 0) break;
    if (knownIds.has(id) || selectedSet.has(id)) continue;
    selected.push(id);
    selectedSet.add(id);
    replacementsNeeded -= 1;
  }

  return selected.slice(0, Math.max(maxDetails, 0));
}

/**
 * Extracts Gmail's provider-owned Retry-After timestamp from an error payload.
 * The API currently returns it inside `error.message`, not as a response
 * header through the Supabase client. A bounded fallback prevents an older
 * polling client from immediately hammering the same exhausted mailbox.
 */
export function gmailRateLimitRetryAt(
  payload: unknown,
  nowMs = Date.now(),
  retryAfterHeader?: string | null,
): string {
  return mailProviderRateLimitRetryAt(payload, {
    nowMs,
    retryAfterHeader,
  });
}

/**
 * Known messages still need a minimal metadata read. Returning only a local
 * cache marker freezes Gmail's UNREAD label and hides changes from other
 * clients indefinitely.
 */
export function buildGmailMessageDetailUrl(
  messageId: string,
  known: boolean,
): URL {
  const url = new URL(
    `${GMAIL_API_ORIGIN}/gmail/v1/users/me/messages/${encodeURIComponent(messageId)}`,
  );
  url.searchParams.set("format", known ? "minimal" : "full");
  url.searchParams.set("fields", known ? "id,labelIds" : gmailMessageFields);
  return url;
}

/**
 * The OAuth function owns a high-value Gmail token, so its generic proxy is
 * deliberately narrower than the upstream API. Only operations used by the
 * mail client are reachable.
 */
export function assertAllowedGmailProxyRequest(
  value: string,
  method: string,
): void {
  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch (_) {
    throw new Error("Blocked Gmail proxy URL");
  }

  const normalizedMethod = method.trim().toUpperCase();
  if (/%2f|%5c/i.test(parsed.pathname)) {
    throw new Error("Blocked Gmail proxy URL");
  }
  let pathname: string;
  try {
    pathname = decodeURIComponent(parsed.pathname);
  } catch (_) {
    throw new Error("Blocked Gmail proxy URL");
  }

  if (
    parsed.origin !== GMAIL_API_ORIGIN ||
    parsed.username ||
    parsed.password ||
    parsed.hash
  ) {
    throw new Error("Blocked Gmail proxy URL");
  }

  const messagePath = /^\/gmail\/v1\/users\/me\/messages\/[^/]+$/;
  const attachmentPath = /^\/gmail\/v1\/users\/me\/messages\/[^/]+\/attachments\/[^/]+$/;
  const messageActionPath = /^\/gmail\/v1\/users\/me\/messages\/[^/]+\/(trash|untrash|modify)$/;

  const allowed = normalizedMethod === "GET"
    ? messagePath.test(pathname) || attachmentPath.test(pathname)
    : normalizedMethod === "POST" && (
      pathname === "/gmail/v1/users/me/watch" ||
      pathname === "/gmail/v1/users/me/stop" ||
      pathname === "/gmail/v1/users/me/messages/send" ||
      messageActionPath.test(pathname)
    );

  if (!allowed) throw new Error("Blocked Gmail proxy URL");
}

/**
 * Labels de sistema que el ERP lista como carpeta. Las categorías llegan con
 * el nombre que Gmail usa en español; las etiquetas del usuario, con el suyo.
 */
export const GMAIL_FOLDER_SYSTEM_LABELS = new Set([
  "INBOX",
  "SENT",
  "DRAFT",
  "SPAM",
  "TRASH",
  "STARRED",
  "IMPORTANT",
  "CATEGORY_PERSONAL",
  "CATEGORY_UPDATES",
  "CATEGORY_PROMOTIONS",
  "CATEGORY_SOCIAL",
  "CATEGORY_FORUMS",
]);

/**
 * El label que pide el cliente para listar una carpeta. Antes sólo pasaban
 * los cinco de sistema y todo lo demás caía en INBOX: las categorías y las
 * etiquetas del usuario no se podían abrir (2026-11-08). Ahora pasa un label
 * de sistema conocido o un id de etiqueta del usuario (`Label_<n>`, que es
 * sensible a mayúsculas); cualquier otra cosa sigue siendo INBOX.
 */
export function resolveGmailListLabel(value: unknown): string {
  const raw = typeof value === "string" ? value.trim() : "";
  if (!raw) return "INBOX";
  if (/^Label_[0-9]{1,24}$/.test(raw)) return raw;
  const upper = raw.toUpperCase();
  return GMAIL_FOLDER_SYSTEM_LABELS.has(upper) ? upper : "INBOX";
}

export type GmailFolderLabel = {
  id: string;
  name: string;
  type: "system" | "user";
};

/** Las carpetas que el ERP ofrece de una lista de `users.labels`. */
export function gmailFolderLabels(payload: unknown): GmailFolderLabel[] {
  const root = payload && typeof payload === "object" ? payload as Record<string, unknown> : {};
  const labels = Array.isArray(root.labels) ? root.labels : [];
  const folders: GmailFolderLabel[] = [];
  for (const raw of labels) {
    if (!raw || typeof raw !== "object") continue;
    const label = raw as Record<string, unknown>;
    const id = typeof label.id === "string" ? label.id.trim() : "";
    const name = typeof label.name === "string" ? label.name.trim() : "";
    const type = String(label.type ?? "").toLowerCase() === "user" ? "user" : "system";
    if (!id) continue;
    if (type === "system" && !GMAIL_FOLDER_SYSTEM_LABELS.has(id)) continue;
    if (type === "user" && !/^Label_[0-9]{1,24}$/.test(id)) continue;
    folders.push({ id, name: name || id, type });
  }
  return folders;
}
