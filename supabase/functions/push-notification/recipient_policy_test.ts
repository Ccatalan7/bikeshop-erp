import {
  buildConversationReadPushData,
  buildMessagingPushData,
  isSilentMessagingRow,
  messagePushBody,
  readSignalIsStale,
  resolveMessagingRecipientIds,
} from "./recipient_policy.ts";
import type {
  PushConversation,
  PushMessageRecord,
} from "./recipient_policy.ts";

function assertEquals(actual: unknown, expected: unknown, message: string) {
  const actualJson = JSON.stringify(actual);
  const expectedJson = JSON.stringify(expected);
  if (actualJson !== expectedJson) {
    throw new Error(
      `${message}: expected ${expectedJson}, received ${actualJson}`,
    );
  }
}

const tenantA = "tenant-a";
const tenantB = "tenant-b";
const staffA = "staff-a";
const staffB = "staff-b";
const customerA = "customer-a";

function message(
  overrides: Partial<PushMessageRecord> = {},
): PushMessageRecord {
  return {
    id: "message-001",
    conversation_id: "conversation-001",
    tenant_id: tenantA,
    sender_id: customerA,
    content: "Hola",
    type: "text",
    metadata: {},
    external_provider: null,
    message_direction: null,
    created_at: "2026-07-19T12:00:00.000Z",
    ...overrides,
  };
}

function conversation(type: "internal" | "support"): PushConversation {
  return {
    id: "conversation-001",
    tenant_id: tenantA,
    type,
    channel: type === "internal" ? "internal" : "website_portal",
  };
}

Deno.test("external support inbound notifies every active staff member in the tenant", () => {
  const recipients = resolveMessagingRecipientIds({
    record: message({
      sender_id: null,
      external_provider: "whatsapp",
      message_direction: "inbound",
    }),
    conversation: { ...conversation("support"), channel: "whatsapp" },
    participants: [],
    activeStaffUserIds: [staffB, staffA],
    activeCustomerUserIds: [customerA],
  });

  assertEquals(
    recipients,
    [staffA, staffB],
    "support fan-out must not require staff participants",
  );
});

Deno.test("customer portal messages without provider direction are inbound support", () => {
  const recipients = resolveMessagingRecipientIds({
    record: message(),
    conversation: conversation("support"),
    participants: [{ user_id: customerA, tenant_id: tenantA }],
    activeStaffUserIds: [staffA, staffB],
    activeCustomerUserIds: [customerA],
  });

  assertEquals(
    recipients,
    [staffA, staffB],
    "customer-authored support must notify active staff",
  );
});

Deno.test("support outbound reaches only the customer, never the team", () => {
  const recipients = resolveMessagingRecipientIds({
    record: message({ sender_id: staffA, message_direction: "outbound" }),
    conversation: conversation("support"),
    participants: [
      { user_id: staffA, tenant_id: tenantA },
      { user_id: staffB, tenant_id: tenantA },
      { user_id: customerA, tenant_id: tenantA },
      { user_id: "foreign-customer", tenant_id: tenantB },
    ],
    activeStaffUserIds: [staffA, staffB],
    activeCustomerUserIds: [customerA],
  });

  assertEquals(
    recipients,
    [customerA],
    "a teammate's reply to a customer is Viñabike speaking, not news to staff",
  );
});

Deno.test("internal messages reach only active staff participants in the same tenant", () => {
  const recipients = resolveMessagingRecipientIds({
    record: message({ sender_id: staffA }),
    conversation: conversation("internal"),
    participants: [
      { user_id: staffA, tenant_id: tenantA },
      { user_id: staffB, tenant_id: tenantA },
      { user_id: "staff-not-active", tenant_id: tenantA },
      { user_id: "foreign-staff", tenant_id: tenantB },
      { user_id: customerA, tenant_id: tenantA },
    ],
    activeStaffUserIds: [staffA, staffB, "foreign-staff"],
    activeCustomerUserIds: [customerA],
  });

  assertEquals(
    recipients,
    [staffB],
    "internal chat must not fan out beyond active staff participants",
  );
});

Deno.test("tenant mismatch fails closed before recipient selection", () => {
  const recipients = resolveMessagingRecipientIds({
    record: message({
      tenant_id: tenantB,
      sender_id: null,
      message_direction: "inbound",
    }),
    conversation: conversation("support"),
    participants: [],
    activeStaffUserIds: [staffA],
    activeCustomerUserIds: [],
  });

  assertEquals(
    recipients,
    [],
    "payload tenant must never override the parent conversation",
  );
});

Deno.test("system and WhatsApp companion rows are silent", () => {
  assertEquals(
    isSilentMessagingRow(message({ type: "system" })),
    true,
    "system row",
  );
  assertEquals(
    isSilentMessagingRow(
      message({ metadata: { message_type: "unsupported" } }),
    ),
    true,
    "unsupported provider row",
  );
  assertEquals(
    isSilentMessagingRow(message({
      metadata: { raw_payload: { message: { type: "unsupported" } } },
    })),
    true,
    "raw Meta companion row",
  );
});

Deno.test("FCM data retains stable database message and conversation ids", () => {
  const record = message();
  const data = buildMessagingPushData(record, "Cliente", "Hola");

  assertEquals(
    data.id,
    record.id,
    "legacy id must use the database message id",
  );
  assertEquals(
    data.message_id,
    record.id,
    "dedupe id must use the database message id",
  );
  assertEquals(
    data.conversation_id,
    record.conversation_id,
    "deep link must retain conversation id",
  );
  assertEquals(
    data.route,
    `/chat?conversation=${record.conversation_id}`,
    "route must open canonical chat",
  );
});

Deno.test("Meta push data uses a provider-specific external sender id", () => {
  const record = message({
    sender_id: null,
    external_provider: "instagram",
    message_direction: "inbound",
  });
  const data = buildMessagingPushData(record, "Instagram • A1B2C3", "Hola");
  assertEquals(
    data.sender_id,
    "external_instagram",
    "Meta sender fallback must not be mislabeled as WhatsApp",
  );
});

Deno.test("a photo with a caption says the caption, not «Imagen adjunta»", () => {
  assertEquals(
    messagePushBody(message({
      type: "image",
      content: "confirmame si es eso entonces",
      metadata: {},
    })),
    "📷 confirmame si es eso entonces",
    "the caption travels in content for WhatsApp images",
  );
  assertEquals(
    messagePushBody(message({ type: "image", content: "Imagen enviada" })),
    "📷 Foto",
    "a generic media label is not news",
  );
  assertEquals(
    messagePushBody(message({
      type: "file",
      content: "Pedido.pdf",
      metadata: { filename: "Pedido - 298454.pdf" },
    })),
    "📄 Pedido - 298454.pdf",
    "a document says its name",
  );
  assertEquals(
    messagePushBody(message({
      type: "file",
      metadata: { content_type: "audio/ogg" },
    })),
    "🎤 Audio",
    "a voice note says it is audio",
  );
});

Deno.test("the read signal is data-only and names the conversation", () => {
  assertEquals(
    buildConversationReadPushData("conversation-001", 42),
    {
      kind: "conversation_read",
      read_conversation_id: "conversation-001",
      read_through_sequence: "42",
    },
    "FCM data values are strings",
  );
  assertEquals(
    "conversation_id" in buildConversationReadPushData("conversation-001", 42),
    false,
    "the published app would announce it as a new message",
  );
});

Deno.test("chat pushes say which inbox the app opens before its list loads", () => {
  const data = buildMessagingPushData(
    message({ sender_id: null, message_direction: "inbound" }),
    "Diego Muñoz",
    "Hola",
    "supplier",
  );
  assertEquals(data.counterparty_type, "supplier", "supplier inbox hint");
});

Deno.test("a message push carries its sequence for the read signal", () => {
  const data = buildMessagingPushData(
    message({ message_sequence: 11, message_direction: "inbound" }),
    "Diego Muñoz",
    "Hola",
  );
  assertEquals(data.message_sequence, "11", "FCM data values are strings");
});

Deno.test("a read overtaken by a customer message keeps its alert", () => {
  const staff = new Set([staffA, staffB]);
  assertEquals(
    readSignalIsStale(
      [{ sender_id: null, message_direction: "inbound", type: "image" }],
      staff,
    ),
    true,
    "the supplier wrote after the read: its alert stays",
  );
  assertEquals(
    readSignalIsStale(
      [{ sender_id: staffB, message_direction: "outbound", type: "text" }],
      staff,
    ),
    false,
    "a teammate's reply does not make the chat unread",
  );
  assertEquals(
    readSignalIsStale(
      [{ sender_id: null, message_direction: "inbound", type: "system" }],
      staff,
    ),
    false,
    "a silent row never alerted anyone",
  );
  assertEquals(readSignalIsStale([], staff), false, "nothing after the read");
});
