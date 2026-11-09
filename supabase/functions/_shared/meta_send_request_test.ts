import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildMetaSendRequest } from "./meta_send_request.ts";

const base = {
  recipientId: "1234567890",
  message: "Hola, sí lo tenemos.",
  graphVersion: "v25.0",
};

Deno.test("Instagram replies go through the linked Page, never the Instagram id", () => {
  const request = buildMetaSendRequest({
    ...base,
    provider: "instagram",
    accountId: "17841400000000000",
  });
  assertEquals(
    request?.url,
    "https://graph.facebook.com/v25.0/me/messages",
  );
  assertEquals(request?.url.includes("17841400000000000"), false);
  assertEquals(request?.body, {
    recipient: { id: "1234567890" },
    message: { text: "Hola, sí lo tenemos." },
  });
});

Deno.test("Messenger replies post to the Page id as a RESPONSE", () => {
  const request = buildMetaSendRequest({
    ...base,
    provider: "facebook_messenger",
    accountId: "123456789012345",
  });
  assertEquals(
    request?.url,
    "https://graph.facebook.com/v25.0/123456789012345/messages",
  );
  assertEquals(request?.body.messaging_type, "RESPONSE");
});

Deno.test("The account id cannot change the Graph path", () => {
  const request = buildMetaSendRequest({
    ...base,
    provider: "facebook_messenger",
    accountId: "123/../me",
  });
  assertEquals(
    request?.url,
    "https://graph.facebook.com/v25.0/123%2F..%2Fme/messages",
  );
});

Deno.test("An unknown provider has no send request", () => {
  assertEquals(
    buildMetaSendRequest({ ...base, provider: "whatsapp", accountId: "1" }),
    null,
  );
});
