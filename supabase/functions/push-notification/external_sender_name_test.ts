import { externalSenderName } from "./external_sender_name.ts";

function assertEquals(actual: unknown, expected: unknown) {
  if (actual !== expected) {
    throw new Error(
      `expected ${JSON.stringify(expected)}, received ${
        JSON.stringify(actual)
      }`,
    );
  }
}

Deno.test("an Instagram push is announced by the conversation's name", () => {
  assertEquals(
    externalSenderName({
      provider: "instagram",
      metadata: { contact_label: "Instagram • 1B5849" },
      conversationTitle: "Camila Rojas",
    }),
    "Camila Rojas",
  );
});

Deno.test("a contact Meta has not named is announced by its code", () => {
  assertEquals(
    externalSenderName({
      provider: "instagram",
      metadata: { contact_label: "Instagram • 1B5849" },
      conversationTitle: "Instagram • 1B5849",
    }),
    "Instagram • 1B5849",
  );
  assertEquals(
    externalSenderName({
      provider: "instagram",
      metadata: { contact_label: "Instagram • 1B5849" },
      conversationTitle: "  ",
    }),
    "Instagram • 1B5849",
  );
  assertEquals(
    externalSenderName({
      provider: "instagram",
      metadata: {},
      conversationTitle: null,
    }),
    "Instagram",
  );
});

Deno.test("Messenger follows the same rule", () => {
  assertEquals(
    externalSenderName({
      provider: "facebook_messenger",
      metadata: { contact_label: "Messenger • A02339" },
      conversationTitle: "Pedro Soto",
    }),
    "Pedro Soto",
  );
  assertEquals(
    externalSenderName({
      provider: "facebook_messenger",
      metadata: {},
      conversationTitle: undefined,
    }),
    "Messenger",
  );
});

// A WhatsApp conversation's title can be a job or a group; the sender's own
// profile name stays the announcement.
Deno.test("WhatsApp keeps its sender's profile name", () => {
  assertEquals(
    externalSenderName({
      provider: "whatsapp",
      metadata: { contact_name: "María José" },
      conversationTitle: "PG-00673",
    }),
    "María José",
  );
  assertEquals(
    externalSenderName({
      provider: "whatsapp",
      metadata: {},
      conversationTitle: "PG-00673",
    }),
    "WhatsApp",
  );
});

Deno.test("other external messages are a customer, and line breaks never reach the title", () => {
  assertEquals(
    externalSenderName({
      provider: null,
      metadata: {},
      conversationTitle: "Soporte",
    }),
    "Cliente",
  );
  assertEquals(
    externalSenderName({
      provider: "instagram",
      metadata: {},
      conversationTitle: "Camila\nRojas",
    }),
    "Camila Rojas",
  );
});
