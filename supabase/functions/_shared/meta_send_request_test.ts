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

Deno.test("A photo goes to Instagram as an image attachment fetched from its link", () => {
  const request = buildMetaSendRequest({
    provider: "instagram",
    accountId: "17841400000000000",
    recipientId: "1234567890",
    imageUrl: "https://project.supabase.co/storage/v1/object/sign/chat-attachments/a.jpg?token=t",
    graphVersion: "v25.0",
  });
  assertEquals(request?.url, "https://graph.facebook.com/v25.0/me/messages");
  assertEquals(request?.body, {
    recipient: { id: "1234567890" },
    message: {
      attachment: {
        type: "image",
        payload: {
          url: "https://project.supabase.co/storage/v1/object/sign/chat-attachments/a.jpg?token=t",
        },
      },
    },
  });
});

Deno.test("A Messenger photo is still a RESPONSE from the Page", () => {
  const request = buildMetaSendRequest({
    provider: "facebook_messenger",
    accountId: "123456789012345",
    recipientId: "1234567890",
    imageUrl: "https://project.supabase.co/storage/v1/object/sign/chat-attachments/a.png?token=t",
    graphVersion: "v25.0",
  });
  assertEquals(request?.body.messaging_type, "RESPONSE");
  assertEquals(
    (request?.body.message as Record<string, unknown>).text,
    undefined,
  );
});

Deno.test("A send is exactly one text or one photo, and a photo link is https", () => {
  const common = {
    provider: "instagram",
    accountId: "1",
    recipientId: "2",
    graphVersion: "v25.0",
  };
  assertEquals(buildMetaSendRequest({ ...common }), null);
  assertEquals(
    buildMetaSendRequest({
      ...common,
      message: "Hola",
      imageUrl: "https://example.invalid/a.jpg",
    }),
    null,
  );
  assertEquals(
    buildMetaSendRequest({ ...common, imageUrl: "http://example.invalid/a.jpg" }),
    null,
  );
});
