import {
  buildMessagingPushData,
  isSilentMessagingRow,
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

Deno.test("support outbound stays participant-only and never notifies the sender", () => {
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
    [customerA, staffB],
    "outbound support recipients must be scoped participants",
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
