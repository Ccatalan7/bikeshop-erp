import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  PUSH_NOTIFICATION_WEBHOOK_HEADER,
  pushWebhookAuthorized,
} from "./push_notification_auth.ts";

const configuredSecret = "push-webhook-fixture-32-bytes-long";

Deno.test("push webhook accepts only the exact dedicated secret", () => {
  const headers = new Headers({
    [PUSH_NOTIFICATION_WEBHOOK_HEADER]: configuredSecret,
  });
  assertEquals(pushWebhookAuthorized(headers, configuredSecret), true);
  assertEquals(
    pushWebhookAuthorized(
      new Headers({
        [PUSH_NOTIFICATION_WEBHOOK_HEADER]: "push-webhook-fixture-32-bytes-wrong",
      }),
      configuredSecret,
    ),
    false,
  );
});

Deno.test("push webhook fails closed when either side is missing", () => {
  assertEquals(pushWebhookAuthorized(new Headers(), configuredSecret), false);
  assertEquals(
    pushWebhookAuthorized(
      new Headers({ [PUSH_NOTIFICATION_WEBHOOK_HEADER]: configuredSecret }),
      "",
    ),
    false,
  );
  assertEquals(
    pushWebhookAuthorized(
      new Headers({ [PUSH_NOTIFICATION_WEBHOOK_HEADER]: configuredSecret }),
      undefined,
    ),
    false,
  );
});

Deno.test("push webhook is case-sensitive and does not accept bearer fallback", () => {
  assertEquals(
    pushWebhookAuthorized(
      new Headers({ [PUSH_NOTIFICATION_WEBHOOK_HEADER]: configuredSecret.toUpperCase() }),
      configuredSecret,
    ),
    false,
  );
  assertEquals(
    pushWebhookAuthorized(
      new Headers({ authorization: `Bearer ${configuredSecret}` }),
      configuredSecret,
    ),
    false,
  );
});
