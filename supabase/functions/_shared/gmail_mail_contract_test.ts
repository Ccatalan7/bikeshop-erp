import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  assertAllowedGmailProxyRequest,
  buildGmailMessageDetailUrl,
  parseKnownGmailIds,
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
