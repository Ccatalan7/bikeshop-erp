export type ZohoMailProxyKind = "read" | "send" | "mutation";

export function assertAllowedZohoMailProxyRequest(
  value: string,
  method: string,
  expectedOrigin: string,
  expectedAccountId: string,
): ZohoMailProxyKind {
  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch (_) {
    throw new Error("Blocked Zoho proxy URL");
  }

  if (
    parsed.origin !== expectedOrigin ||
    parsed.username ||
    parsed.password ||
    parsed.hash ||
    /%2f|%5c/i.test(parsed.pathname)
  ) {
    throw new Error("Blocked Zoho proxy URL");
  }

  let pathname: string;
  try {
    pathname = decodeURIComponent(parsed.pathname).replace(/\/$/, "");
  } catch (_) {
    throw new Error("Blocked Zoho proxy URL");
  }

  const normalizedMethod = method.trim().toUpperCase();
  const accountBase = `/api/accounts/${expectedAccountId}`;
  const id = "[A-Za-z0-9._~-]+";
  const readPaths = [
    new RegExp(`^${accountBase}/folders$`),
    new RegExp(`^${accountBase}/messages/(?:view|search)$`),
    new RegExp(
      `^${accountBase}/folders/${id}/messages/${id}/(?:content|attachmentinfo)$`,
    ),
    new RegExp(
      `^${accountBase}/folders/${id}/messages/${id}/attachments/${id}$`,
    ),
  ];
  if (
    normalizedMethod === "GET" &&
    readPaths.some((pattern) => pattern.test(pathname))
  ) {
    return "read";
  }

  if (
    normalizedMethod === "POST" &&
    (pathname === `${accountBase}/messages` ||
      new RegExp(`^${accountBase}/messages/${id}$`).test(pathname))
  ) {
    return "send";
  }

  if (
    normalizedMethod === "PUT" &&
    (pathname === `${accountBase}/updatemessage` ||
      new RegExp(`^${accountBase}/messages/${id}/move$`).test(pathname))
  ) {
    return "mutation";
  }

  throw new Error("Blocked Zoho proxy URL");
}
