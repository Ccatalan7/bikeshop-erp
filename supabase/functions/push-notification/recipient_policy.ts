export interface PushMessageRecord {
  id: string;
  conversation_id: string;
  tenant_id?: string | null;
  sender_id: string | null;
  content: string | null;
  type: string | null;
  metadata?: Record<string, unknown> | null;
  external_provider?: string | null;
  message_direction?: string | null;
  created_at: string;
}

export interface PushConversation {
  id: string;
  tenant_id: string;
  type: "internal" | "support";
  channel: string;
}

export interface PushParticipant {
  user_id: string;
  tenant_id: string;
}

export interface RecipientPolicyInput {
  record: PushMessageRecord;
  conversation: PushConversation;
  participants: PushParticipant[];
  activeStaffUserIds: string[];
  activeCustomerUserIds: string[];
}

function normalized(value: unknown) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

function metadataRecord(value: unknown): Record<string, unknown> {
  return value != null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function isTrue(value: unknown) {
  return value === true || normalized(value) === "true";
}

/**
 * System messages and Meta's unsupported companion events are inbox evidence,
 * not human-authored messages. They must never generate a user notification.
 */
export function isSilentMessagingRow(record: PushMessageRecord) {
  const messageType = normalized(record.type);
  if (messageType === "system" || messageType === "unsupported") return true;

  const metadata = metadataRecord(record.metadata);
  if (
    isTrue(metadata.suppress_notification) ||
    isTrue(metadata.notification_silent) ||
    isTrue(metadata.is_companion) ||
    isTrue(metadata.companion)
  ) {
    return true;
  }

  if (
    normalized(metadata.message_type) === "unsupported" ||
    normalized(metadata.provider_message_type) === "unsupported"
  ) {
    return true;
  }

  const rawPayload = metadataRecord(metadata.raw_payload);
  const rawMessage = metadataRecord(rawPayload.message);
  return normalized(rawMessage.type) === "unsupported";
}

/**
 * Resolve recipients from canonical tenant membership instead of trusting the
 * webhook row. Support inbound messages fan out to every active staff member
 * in the conversation tenant; internal and support-outbound messages remain
 * participant-only. The sender is excluded in every case.
 */
export function resolveMessagingRecipientIds(input: RecipientPolicyInput) {
  const { record, conversation } = input;
  if (
    !record.id ||
    !record.conversation_id ||
    record.conversation_id !== conversation.id ||
    !conversation.tenant_id ||
    (record.tenant_id != null && record.tenant_id !== conversation.tenant_id) ||
    isSilentMessagingRow(record)
  ) {
    return [];
  }

  const staff = new Set(input.activeStaffUserIds.filter(Boolean));
  const customers = new Set(input.activeCustomerUserIds.filter(Boolean));
  const tenantMembers = new Set([...staff, ...customers]);
  const senderId = record.sender_id?.trim() || null;

  const participantIds = new Set(
    input.participants
      .filter((participant) =>
        participant.tenant_id === conversation.tenant_id &&
        tenantMembers.has(participant.user_id)
      )
      .map((participant) => participant.user_id),
  );

  let recipients: Set<string>;
  if (conversation.type === "internal") {
    recipients = new Set(
      [...participantIds].filter((userId) => staff.has(userId)),
    );
  } else if (conversation.type === "support") {
    const direction = normalized(record.message_direction);
    const isInbound = direction === "inbound" ||
      (direction !== "outbound" && (senderId == null || !staff.has(senderId)));
    recipients = isInbound ? new Set(staff) : participantIds;
  } else {
    return [];
  }

  if (senderId != null) recipients.delete(senderId);
  return [...recipients].sort();
}

export function buildMessagingPushData(
  record: PushMessageRecord,
  senderName: string,
  body: string,
) {
  return {
    id: record.id,
    message_id: record.id,
    conversation_id: record.conversation_id,
    sender_id: record.sender_id || "external_whatsapp",
    sender_name: senderName,
    title: senderName,
    body,
    type: record.type || "text",
    content: record.content || "",
    created_at: record.created_at,
    message_direction: record.message_direction ?? "",
    external_provider: record.external_provider ?? "",
    route: `/chat?conversation=${record.conversation_id}`,
    click_action: "FLUTTER_NOTIFICATION_CLICK",
  };
}
