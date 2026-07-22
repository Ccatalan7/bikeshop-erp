type JsonRecord = Record<string, unknown>;

export type MetaWebhookProvider = "facebook_messenger" | "instagram";
export type MetaWebhookMessageType =
  | "text"
  | "image"
  | "video"
  | "audio"
  | "file"
  | "sticker"
  | "media"
  | "unsupported";

interface MetaWebhookEventBase {
  provider: MetaWebhookProvider;
  accountId: string;
  eventKey: string;
  occurredAt: string | null;
  payload: JsonRecord;
}

export interface MetaInboundMessageEvent extends MetaWebhookEventBase {
  kind: "message";
  direction: "inbound";
  senderId: string;
  recipientId: string;
  externalUserId: string;
  externalMessageId: string;
  messageType: MetaWebhookMessageType;
  text: string;
}

export interface MetaEchoMessageEvent extends MetaWebhookEventBase {
  kind: "echo";
  direction: "outbound";
  senderId: string;
  recipientId: string;
  externalUserId: string;
  externalMessageId: string;
  messageType: MetaWebhookMessageType;
  text: string;
}

export interface MetaDeliveryEvent extends MetaWebhookEventBase {
  kind: "delivery";
  senderId: string;
  recipientId: string;
  externalUserId: string;
  externalMessageIds: string[];
  watermark: string | null;
}

export interface MetaReadEvent extends MetaWebhookEventBase {
  kind: "read";
  senderId: string;
  recipientId: string;
  externalUserId: string;
  externalMessageId: string | null;
  watermark: string | null;
}

export interface MetaInteractionEvent extends MetaWebhookEventBase {
  kind: "interaction";
  interactionType: "comment" | "mention";
  field: string;
  verb: string | null;
  externalObjectId: string;
  parentObjectId: string | null;
  actorId: string | null;
  actorName: string | null;
  text: string | null;
  permalink: string | null;
}

export type MetaWebhookEvent =
  | MetaInboundMessageEvent
  | MetaEchoMessageEvent
  | MetaDeliveryEvent
  | MetaReadEvent
  | MetaInteractionEvent;

function asRecord(value: unknown): JsonRecord | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : null;
}

function safeText(value: unknown, maxLength = 4_000): string | null {
  if (typeof value !== "string" && typeof value !== "number") return null;
  // deno-lint-ignore no-control-regex -- webhook text must not retain C0 bytes.
  const unsafeControlCharacters = /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g;
  const normalized = String(value)
    .replaceAll("\r\n", "\n")
    .replaceAll("\r", "\n")
    .replace(unsafeControlCharacters, "")
    .trim()
    .slice(0, maxLength);
  return normalized || null;
}

function safeId(value: unknown): string | null {
  return safeText(value, 512);
}

function safePermalink(
  value: unknown,
  provider: MetaWebhookProvider,
): string | null {
  const candidate = safeText(value, 2_048);
  if (!candidate) return null;
  try {
    const url = new URL(candidate);
    if (url.protocol !== "https:") return null;
    const hostname = url.hostname.toLowerCase();
    const trustedHost = provider === "instagram"
      ? hostname === "instagram.com" || hostname === "www.instagram.com"
      : hostname === "facebook.com" || hostname === "www.facebook.com" ||
        hostname === "m.facebook.com";
    if (!trustedHost || url.port) return null;
    url.username = "";
    url.password = "";
    url.hash = "";
    for (const key of [...url.searchParams.keys()]) {
      if (/token|secret|signature|password/i.test(key)) {
        url.searchParams.delete(key);
      }
    }
    return url.toString().slice(0, 2_048);
  } catch {
    return null;
  }
}

function timestampText(value: unknown): string | null {
  if (typeof value === "number" && Number.isFinite(value) && value > 0) {
    const milliseconds = value >= 10_000_000_000 ? value : value * 1_000;
    const result = new Date(milliseconds);
    return Number.isNaN(result.valueOf()) ? null : result.toISOString();
  }
  const candidate = safeText(value, 100);
  if (!candidate) return null;
  if (/^\d+(?:\.\d+)?$/.test(candidate)) {
    return timestampText(Number(candidate));
  }
  const result = new Date(candidate);
  return Number.isNaN(result.valueOf()) ? null : result.toISOString();
}

function keyPart(value: string | null): string {
  return encodeURIComponent(value ?? "none");
}

function eventKey(...parts: Array<string | null>): string {
  return ["meta", ...parts].map(keyPart).join(":");
}

function uniqueIds(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map(safeId).filter((item): item is string => !!item))]
    .sort();
}

function messageTypeForAttachment(type: string | null): MetaWebhookMessageType {
  switch (type?.toLowerCase()) {
    case "image":
    case "video":
    case "audio":
    case "file":
    case "sticker":
      return type.toLowerCase() as MetaWebhookMessageType;
    case "media":
      return "media";
    default:
      return "unsupported";
  }
}

function mediaPlaceholder(type: MetaWebhookMessageType): string {
  switch (type) {
    case "image":
      return "Imagen recibida";
    case "video":
      return "Video recibido";
    case "audio":
      return "Audio recibido";
    case "file":
      return "Archivo recibido";
    case "sticker":
      return "Sticker recibido";
    case "media":
      return "Contenido multimedia recibido";
    default:
      return "Contenido adjunto recibido";
  }
}

function sanitizedAttachments(value: unknown): {
  attachmentTypes: string[];
  attachmentIds: string[];
  messageType: MetaWebhookMessageType | null;
} {
  if (!Array.isArray(value) || value.length === 0) {
    return { attachmentTypes: [], attachmentIds: [], messageType: null };
  }
  const attachmentTypes = new Set<string>();
  const attachmentIds = new Set<string>();
  let messageType: MetaWebhookMessageType | null = null;
  for (const rawAttachment of value) {
    const attachment = asRecord(rawAttachment);
    if (!attachment) continue;
    const type = safeText(attachment.type, 64)?.toLowerCase() ?? "unsupported";
    attachmentTypes.add(type);
    messageType ??= messageTypeForAttachment(type);

    const payload = asRecord(attachment.payload);
    for (
      const candidate of [
        attachment.id,
        payload?.id,
        payload?.attachment_id,
        payload?.media_id,
        payload?.sticker_id,
      ]
    ) {
      const id = safeId(candidate);
      if (id) attachmentIds.add(id);
    }
  }
  return {
    attachmentTypes: [...attachmentTypes].sort(),
    attachmentIds: [...attachmentIds].sort(),
    messageType,
  };
}

function parseMessagingItem(params: {
  value: JsonRecord;
  entryAccountId: string;
  entryTime: unknown;
  provider: MetaWebhookProvider;
}): MetaWebhookEvent[] {
  const { value, entryAccountId, entryTime, provider } = params;
  const senderId = safeId(asRecord(value.sender)?.id);
  const recipientId = safeId(asRecord(value.recipient)?.id);
  if (!senderId || !recipientId) return [];
  const accountId = entryAccountId || recipientId;
  const occurredAt = timestampText(value.timestamp) ?? timestampText(entryTime);
  const result: MetaWebhookEvent[] = [];

  const message = asRecord(value.message);
  const externalMessageId = safeId(message?.mid);
  if (
    message && externalMessageId && message.is_deleted !== true &&
    message.is_self !== true
  ) {
    const attachments = sanitizedAttachments(message.attachments);
    const directText = safeText(message.text);
    const messageType = attachments.messageType ?? "text";
    const text = directText ?? mediaPlaceholder(messageType);
    const isEcho = message.is_echo === true;
    const externalUserId = isEcho ? recipientId : senderId;
    const normalizedMessage = {
      provider,
      accountId,
      senderId,
      recipientId,
      externalUserId,
      externalMessageId,
      messageType,
      text,
      occurredAt,
      payload: {
        message_id: externalMessageId,
        message_type: messageType,
        text,
        ...(attachments.attachmentTypes.length > 0
          ? { attachment_types: attachments.attachmentTypes }
          : {}),
        ...(attachments.attachmentIds.length > 0
          ? { attachment_ids: attachments.attachmentIds }
          : {}),
      },
    };
    if (isEcho) {
      result.push({
        ...normalizedMessage,
        kind: "echo",
        direction: "outbound",
        eventKey: eventKey(
          provider,
          "echo",
          accountId,
          externalMessageId,
        ),
      });
    } else {
      result.push({
        ...normalizedMessage,
        kind: "message",
        direction: "inbound",
        eventKey: eventKey(
          provider,
          "message",
          accountId,
          externalMessageId,
        ),
      });
    }
  }

  const delivery = asRecord(value.delivery);
  if (delivery) {
    const externalMessageIds = uniqueIds(delivery.mids);
    const watermark = safeId(delivery.watermark);
    if (externalMessageIds.length > 0 || watermark) {
      result.push({
        kind: "delivery",
        provider,
        accountId,
        senderId,
        recipientId,
        externalUserId: senderId,
        externalMessageIds,
        watermark,
        occurredAt,
        eventKey: eventKey(
          provider,
          "delivery",
          accountId,
          senderId,
          externalMessageIds.join(",") || null,
          watermark,
        ),
        payload: {
          message_ids: externalMessageIds,
          ...(watermark ? { watermark } : {}),
        },
      });
    }
  }

  const read = asRecord(value.read);
  if (read) {
    const readMessageId = safeId(read.mid) ?? safeId(read.message_id);
    const watermark = safeId(read.watermark);
    if (readMessageId || watermark) {
      result.push({
        kind: "read",
        provider,
        accountId,
        senderId,
        recipientId,
        externalUserId: senderId,
        externalMessageId: readMessageId,
        watermark,
        occurredAt,
        eventKey: eventKey(
          provider,
          "read",
          accountId,
          senderId,
          readMessageId,
          watermark,
        ),
        payload: {
          ...(readMessageId ? { message_id: readMessageId } : {}),
          ...(watermark ? { watermark } : {}),
        },
      });
    }
  }

  return result;
}

function interactionTypeForChange(
  field: string,
  value: JsonRecord,
): "comment" | "mention" | null {
  const item = safeText(value.item, 64)?.toLowerCase() ?? "";
  if (field.includes("mention") || item.includes("mention")) return "mention";
  if (
    field === "comments" || field === "live_comments" ||
    item === "comment" || (field === "feed" && !!safeId(value.comment_id))
  ) return "comment";
  return null;
}

function parseChange(params: {
  change: JsonRecord;
  accountId: string;
  entryTime: unknown;
  provider: MetaWebhookProvider;
}): MetaInteractionEvent | null {
  const { change, accountId, entryTime, provider } = params;
  const field = safeText(change.field, 128)?.toLowerCase();
  const value = asRecord(change.value);
  if (!field || !value) return null;
  const interactionType = interactionTypeForChange(field, value);
  if (!interactionType) return null;

  const externalObjectId = interactionType === "mention"
    ? safeId(value.mention_id) ?? safeId(value.comment_id) ??
      safeId(value.media_id) ?? safeId(value.id)
    : safeId(value.comment_id) ?? safeId(value.id);
  if (!externalObjectId) return null;
  const media = asRecord(value.media);
  const parentObjectId = safeId(value.post_id) ?? safeId(value.media_id) ??
    safeId(value.parent_id) ?? safeId(media?.id);
  const actor = asRecord(value.from) ?? asRecord(value.sender) ??
    asRecord(value.user);
  const actorId = safeId(actor?.id);
  const actorName = safeText(actor?.name, 256) ??
    safeText(actor?.username, 256);
  const text = safeText(value.message) ?? safeText(value.text);
  const permalink = safePermalink(value.permalink_url, provider) ??
    safePermalink(value.permalink, provider) ??
    safePermalink(media?.permalink, provider);
  const verb = safeText(value.verb, 64)?.toLowerCase() ?? null;
  const occurredAt = timestampText(value.created_time) ??
    timestampText(value.timestamp) ?? timestampText(value.time) ??
    timestampText(entryTime);

  return {
    kind: "interaction",
    provider,
    accountId,
    interactionType,
    field,
    verb,
    externalObjectId,
    parentObjectId,
    actorId,
    actorName,
    text,
    permalink,
    occurredAt,
    eventKey: eventKey(
      provider,
      interactionType,
      accountId,
      externalObjectId,
      verb,
      occurredAt,
    ),
    payload: {
      interaction_type: interactionType,
      field,
      object_id: externalObjectId,
      ...(parentObjectId ? { parent_object_id: parentObjectId } : {}),
      ...(actorId ? { actor_id: actorId } : {}),
      ...(actorName ? { actor_name: actorName } : {}),
      ...(verb ? { verb } : {}),
      ...(text ? { text } : {}),
      ...(permalink ? { permalink } : {}),
    },
  };
}

export function parseMetaWebhookEvents(input: unknown): MetaWebhookEvent[] {
  const root = asRecord(input);
  if (!root) throw new Error("invalid_meta_webhook_payload");
  const object = safeText(root.object, 64)?.toLowerCase();
  if (object !== "page" && object !== "instagram") {
    throw new Error("unsupported_meta_webhook_object");
  }
  if (!Array.isArray(root.entry)) {
    throw new Error("invalid_meta_webhook_entries");
  }
  const provider: MetaWebhookProvider = object === "page" ? "facebook_messenger" : "instagram";
  const events: MetaWebhookEvent[] = [];

  for (const rawEntry of root.entry) {
    const entry = asRecord(rawEntry);
    if (!entry) continue;
    const entryAccountId = safeId(entry.id) ?? "";
    if (Array.isArray(entry.messaging)) {
      for (const rawItem of entry.messaging) {
        const value = asRecord(rawItem);
        if (!value) continue;
        events.push(...parseMessagingItem({
          value,
          entryAccountId,
          entryTime: entry.time,
          provider,
        }));
      }
    }
    if (entryAccountId) {
      const changes: unknown[] = Array.isArray(entry.changes) ? [...entry.changes] : [];
      const directField = safeText(entry.field, 128);
      const directValue = asRecord(entry.value);
      if (directField && directValue) {
        changes.push({ field: directField, value: directValue });
      }
      for (const rawChange of changes) {
        const change = asRecord(rawChange);
        if (!change) continue;
        const event = parseChange({
          change,
          accountId: entryAccountId,
          entryTime: entry.time,
          provider,
        });
        if (event) events.push(event);
      }
    }
  }

  const unique = new Map<string, MetaWebhookEvent>();
  for (const event of events) unique.set(event.eventKey, event);
  return [...unique.values()];
}
