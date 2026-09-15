import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { assertAllowedZohoMailProxyRequest } from "./zoho_mail_proxy_contract.ts";

const origin = "https://mail.zoho.com";
const accountId = "2560636000000008002";

Deno.test("Zoho proxy accepts only the current account mail workflow", () => {
  const allowed: Array<[string, string, string]> = [
    ["GET", `${origin}/api/accounts/${accountId}/folders`, "read"],
    ["GET", `${origin}/api/accounts/${accountId}/messages/view?limit=50`, "read"],
    ["GET", `${origin}/api/accounts/${accountId}/messages/search?searchKey=bike`, "read"],
    ["GET", `${origin}/api/accounts/${accountId}/folders/1/messages/2/content`, "read"],
    ["GET", `${origin}/api/accounts/${accountId}/folders/1/messages/2/attachmentinfo`, "read"],
    ["GET", `${origin}/api/accounts/${accountId}/folders/1/messages/2/attachments/a-1`, "read"],
    ["POST", `${origin}/api/accounts/${accountId}/messages`, "send"],
    ["POST", `${origin}/api/accounts/${accountId}/messages/2`, "send"],
    ["PUT", `${origin}/api/accounts/${accountId}/updatemessage`, "mutation"],
    ["PUT", `${origin}/api/accounts/${accountId}/messages/2/move`, "mutation"],
  ];

  for (const [method, url, expectedKind] of allowed) {
    assertEquals(
      assertAllowedZohoMailProxyRequest(url, method, origin, accountId),
      expectedKind,
    );
  }
});

Deno.test("Zoho proxy rejects foreign accounts and broader APIs", () => {
  const blocked: Array<[string, string]> = [
    ["GET", `${origin}/api/accounts/999/messages/view`],
    ["GET", `${origin}/api/organization/1/accounts`],
    ["DELETE", `${origin}/api/accounts/${accountId}/messages/2`],
    ["PUT", `${origin}/api/accounts/${accountId}/settings`],
    ["POST", `${origin}/api/accounts/${accountId}/messages/2%2Fmove`],
    ["GET", `https://evil.example/api/accounts/${accountId}/folders`],
  ];

  for (const [method, url] of blocked) {
    assertThrows(
      () =>
        assertAllowedZohoMailProxyRequest(
          url,
          method,
          origin,
          accountId,
        ),
      Error,
      "Blocked Zoho proxy URL",
    );
  }
});
