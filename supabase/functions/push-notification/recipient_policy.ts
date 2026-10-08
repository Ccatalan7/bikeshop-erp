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
  /** Global, monotonic: the same space as the team read cursor. */
  message_sequence?: number | string | null;
  created_at: string;
}

export interface PushConversation {
  id: string;
  tenant_id: string;
  type: "internal" | "support";
  channel: string;
  counterparty_type?: string | null;
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
 * in the conversation tenant; internal messages remain participant-only. A
 * support message written by Viñabike reaches only the customer side: with a
 * customer or a supplier the whole team is one sender, so a teammate's reply
 * is not news to the rest of the team (owner, 2026-10-08: «genera como una
 * dinámica de grupo, no debería ser así»). The sender is excluded in every
 * case.
 */
/**
 * A support row written by the customer or supplier side: the explicit
 * direction wins; without one, anyone who is not active staff.
 */
export function isCustomerSideSupportRow(
  record: Pick<PushMessageRecord, "sender_id" | "message_direction">,
  staff: Set<string>,
) {
  const direction = normalized(record.message_direction);
  const senderId = record.sender_id?.trim() || null;
  return direction === "inbound" ||
    (direction !== "outbound" && (senderId == null || !staff.has(senderId)));
}

/**
 * Whether a team read must NOT clear the chat's alerts: a customer-side
 * message arrived after the read, so its alert is still unread.
 *
 * El 2026-10-08 la revisión cruzada encontró la carrera: la lectura hasta 10
 * se encola, entra el 11 y su aviso se muestra, y la señal —que llega
 * después— borraba todo lo del chat, también el 11.
 */
export function readSignalIsStale(
  laterRows: Array<
    Pick<
      PushMessageRecord,
      "sender_id" | "message_direction" | "type" | "metadata"
    >
  >,
  staff: Set<string>,
) {
  return laterRows.some((row) =>
    !isSilentMessagingRow(row as PushMessageRecord) &&
    isCustomerSideSupportRow(row, staff)
  );
}

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
    const isInbound = isCustomerSideSupportRow(record, staff);
    recipients = isInbound ? new Set(staff) : new Set(
      [...participantIds].filter((userId) => !staff.has(userId)),
    );
  } else {
    return [];
  }

  if (senderId != null) recipients.delete(senderId);
  return [...recipients].sort();
}

function cleanLine(value: unknown) {
  return typeof value === "string"
    ? value.replaceAll(/[\r\n\t]+/g, " ").replaceAll(/\s+/g, " ").trim()
    : "";
}

const genericMediaTexts = new Set([
  "Imagen enviada",
  "Imagen adjunta",
  "Archivo adjunto",
  "Archivo enviado",
]);

/**
 * What the notification says about a message. A photo with a caption showed
 * only «Imagen adjunta» and hid what the supplier wrote (2026-10-08).
 */
export function messagePushBody(record: PushMessageRecord) {
  const metadata = metadataRecord(record.metadata);
  const content = cleanLine(record.content);
  const caption = cleanLine(metadata.caption);
  const filename = cleanLine(metadata.filename ?? metadata.file_name);
  const contentType = cleanLine(metadata.content_type ?? metadata.mime_type);
  const generic = content === "" || genericMediaTexts.has(content);
  const clip = (text: string) => text.slice(0, 120);
  if (record.type === "image") {
    const text = caption || (generic ? "" : content);
    return clip(text ? `📷 ${text}` : "📷 Foto");
  }
  if (record.type === "file") {
    if (contentType.startsWith("audio/")) return "🎤 Audio";
    const text = caption || filename || (generic ? "Archivo" : content);
    return clip(`📄 ${text}`);
  }
  return clip(content || "Nuevo mensaje");
}

/**
 * Data-only signal that someone at Viñabike read a conversation: every staff
 * device drops that chat's notification, like WhatsApp does across linked
 * devices.
 *
 * The chat travels as `read_conversation_id`, never `conversation_id`: the
 * app published before 2026-10-08 treats any data push with
 * `conversation_id` as a new message and showed «Nuevo mensaje recibido» on
 * every open phone each time someone read a chat. Without that key the old
 * app only refreshes its inbox.
 */
export function buildConversationReadPushData(
  conversationId: string,
  readThroughSequence: number | null,
) {
  return {
    kind: "conversation_read",
    read_conversation_id: conversationId,
    read_through_sequence: readThroughSequence == null
      ? ""
      : String(readThroughSequence),
  };
}

export function buildMessagingPushData(
  record: PushMessageRecord,
  senderName: string,
  body: string,
  counterpartyType: string | null = null,
) {
  return {
    id: record.id,
    message_id: record.id,
    conversation_id: record.conversation_id,
    sender_id: record.sender_id ||
      (record.external_provider
        ? `external_${record.external_provider}`
        : "external_support"),
    sender_name: senderName,
    title: senderName,
    body,
    type: record.type || "text",
    content: record.content || "",
    created_at: record.created_at,
    message_direction: record.message_direction ?? "",
    external_provider: record.external_provider ?? "",
    // A later read signal only drops this alert if it reads through it.
    message_sequence: record.message_sequence == null
      ? ""
      : String(record.message_sequence),
    route: `/chat?conversation=${record.conversation_id}`,
    // Which inbox the app opens before its list has loaded.
    counterparty_type: counterpartyType ?? "",
    click_action: "FLUTTER_NOTIFICATION_CLICK",
  };
}
