import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  missingRequestedMetaOAuthScopes,
  missingRequiredMetaPageTokenScopes,
  missingRequiredMetaScopes,
  parseGrantedMetaScopes,
  REQUESTED_META_OAUTH_SCOPES,
  requiredMetaScopes,
} from "./meta_oauth_permissions.ts";

Deno.test("keeps only actual unique granted Meta permissions", () => {
  assertEquals(
    parseGrantedMetaScopes({
      data: [
        { permission: "pages_messaging", status: "granted" },
        { permission: "instagram_manage_messages", status: "declined" },
        { permission: "PAGES_MESSAGING", status: "GRANTED" },
        { permission: "invalid permission", status: "granted" },
        { permission: "pages_show_list", status: "expired" },
      ],
    }),
    ["pages_messaging"],
  );
});

Deno.test("reports provider-specific missing permissions", () => {
  const granted = [
    "business_management",
    "pages_show_list",
    "pages_messaging",
    "pages_manage_metadata",
    "pages_read_engagement",
    "pages_read_user_content",
  ];
  assertEquals(
    missingRequiredMetaScopes("facebook_messenger", granted),
    [],
  );
  assertEquals(
    missingRequiredMetaScopes("instagram", granted),
    [
      "instagram_basic",
      "instagram_manage_messages",
      "instagram_manage_comments",
    ],
  );
});

Deno.test("exposes stable required-scope contracts", () => {
  assertEquals(REQUESTED_META_OAUTH_SCOPES.length, 9);
  assertEquals(REQUESTED_META_OAUTH_SCOPES[0], "business_management");
  assertEquals(requiredMetaScopes("facebook_messenger"), [
    "business_management",
    "pages_show_list",
    "pages_messaging",
    "pages_manage_metadata",
    "pages_read_engagement",
    "pages_read_user_content",
  ]);
  assertEquals(requiredMetaScopes("instagram").length, 8);
});

Deno.test("Business Login preflight requires every configured scope", () => {
  assertEquals(
    missingRequestedMetaOAuthScopes(REQUESTED_META_OAUTH_SCOPES),
    [],
  );
  assertEquals(
    missingRequestedMetaOAuthScopes(
      REQUESTED_META_OAUTH_SCOPES.filter((scope) => scope !== "business_management"),
    ),
    ["business_management"],
  );
});

Deno.test("Page-token preflight requires the operative scopes for each channel", () => {
  const facebookPageScopes = [
    "pages_show_list",
    "pages_messaging",
    "pages_manage_metadata",
    "pages_read_engagement",
    "pages_read_user_content",
  ];
  assertEquals(
    missingRequiredMetaPageTokenScopes("facebook_messenger", facebookPageScopes),
    [],
  );
  assertEquals(
    missingRequiredMetaPageTokenScopes("instagram", facebookPageScopes),
    [
      "instagram_basic",
      "instagram_manage_messages",
      "instagram_manage_comments",
    ],
  );
  assertEquals(
    missingRequiredMetaPageTokenScopes(
      "facebook_messenger",
      facebookPageScopes.filter((scope) => scope !== "pages_messaging"),
    ),
    ["pages_messaging"],
  );
});
