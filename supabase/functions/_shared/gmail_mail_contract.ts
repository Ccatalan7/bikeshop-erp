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
