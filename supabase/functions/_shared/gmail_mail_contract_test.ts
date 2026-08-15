import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  assertAllowedGmailProxyRequest,
  buildGmailMessageDetailUrl,
  buildKnownGmailInboxMarkers,
  gmailRateLimitRetryAt,
  parseKnownGmailIds,
  selectUnknownGmailInboxDetailIds,
} from "./gmail_mail_contract.ts";

Deno.test("known Gmail messages still fetch authoritative labels", () => {
  const known = buildGmailMessageDetailUrl("message-1", true);
  assertEquals(known.searchParams.get("format"), "minimal");
  assertEquals(known.searchParams.get("fields"), "id,labelIds");

  const unknown = buildGmailMessageDetailUrl("message-2", false);
  assertEquals(unknown.searchParams.get("format"), "full");
  assertEquals(unknown.searchParams.get("fields")?.includes("payload("), true);
});

Deno.test("known ID cache hints are bounded to the local cache capacity", () => {
  const ids = Array.from({ length: 550 }, (_, index) => `message-${index}`);
  assertEquals(parseKnownGmailIds(ids).size, 500);
  assertEquals(parseKnownGmailIds([" ", null, "message-1"]).has("message-1"), true);
});

Deno.test("known Inbox snapshot reconciles all cached read states without per-message gets", () => {
  const markers = buildKnownGmailInboxMarkers(
    ["message-3", "message-2", "message-1", "message-2"],
    new Set(["message-3", "message-1"]),
    new Set(["message-1", "message-2", "message-3", "archived-message"]),
  );

  assertEquals(markers, [
    {
      id: "message-3",
      known: true,
      labelIds: ["INBOX", "UNREAD"],
    },
    { id: "message-2", known: true, labelIds: ["INBOX"] },
    {
      id: "message-1",
      known: true,
      labelIds: ["INBOX", "UNREAD"],
    },
  ]);
  assertEquals(
    markers.some((message) => message.id === "archived-message"),
    false,
  );
});

Deno.test("Gmail rate-limit cooldown honors provider time and has a bounded fallback", () => {
  const now = Date.parse("2026-08-15T19:00:00.000Z");
  assertEquals(
    gmailRateLimitRetryAt({
      error: {
        message: "User-rate limit exceeded. Retry after 2026-08-15T19:15:00.000Z",
      },
    }, now),
    "2026-08-15T19:15:00.000Z",
  );
  assertEquals(
    gmailRateLimitRetryAt({ error: { message: "rateLimitExceeded" } }, now),
    "2026-08-15T19:05:00.000Z",
  );
});

Deno.test("Gmail snapshot fetches visible newcomers and only enough older rows to fill holes", () => {
  assertEquals(
    selectUnknownGmailInboxDetailIds(
      ["new", "known-1", "known-2", "replacement"],
      ["new", "known-1"],
      new Set(["known-1", "known-2", "archived"]),
      50,
    ),
    ["new"],
  );
  assertEquals(
    selectUnknownGmailInboxDetailIds(
      ["known-1", "known-2", "replacement"],
      ["known-1", "known-2"],
      new Set(["known-1", "known-2", "archived"]),
      50,
    ),
    ["replacement"],
  );
  assertEquals(
    selectUnknownGmailInboxDetailIds(
      ["known-1", "known-2", "older-1", "older-2"],
      ["known-1", "known-2"],
      new Set(["known-1", "known-2"]),
      50,
    ),
    [],
  );
});

Deno.test("Gmail proxy accepts only the operations used by the client", () => {
  const allowed: Array<[string, string]> = [
    ["GET", "https://www.googleapis.com/gmail/v1/users/me/messages/m-1?format=full"],
    ["GET", "https://www.googleapis.com/gmail/v1/users/me/messages/m-1/attachments/a-1"],
    ["POST", "https://www.googleapis.com/gmail/v1/users/me/watch"],
    ["POST", "https://www.googleapis.com/gmail/v1/users/me/stop"],
    ["POST", "https://www.googleapis.com/gmail/v1/users/me/messages/send"],
    ["POST", "https://www.googleapis.com/gmail/v1/users/me/messages/m-1/modify"],
    ["POST", "https://www.googleapis.com/gmail/v1/users/me/messages/m-1/trash"],
    ["POST", "https://www.googleapis.com/gmail/v1/users/me/messages/m-1/untrash"],
  ];

  for (const [method, url] of allowed) {
    assertAllowedGmailProxyRequest(url, method);
  }
});

Deno.test("Gmail proxy rejects broader mailbox and encoded-path access", () => {
  const blocked: Array<[string, string]> = [
    ["GET", "https://evil.example/gmail/v1/users/me/messages/m-1"],
    ["GET", "https://www.googleapis.com/gmail/v1/users/me/settings/filters"],
    ["DELETE", "https://www.googleapis.com/gmail/v1/users/me/messages/m-1"],
    ["POST", "https://www.googleapis.com/gmail/v1/users/me/messages/batchDelete"],
    ["GET", "https://www.googleapis.com/gmail/v1/users/me/messages/m-1%2Fattachments%2Fa-1"],
  ];

  for (const [method, url] of blocked) {
    assertThrows(
      () => assertAllowedGmailProxyRequest(url, method),
      Error,
      "Blocked Gmail proxy URL",
    );
  }
});
