// Turns a Gmail or Zoho message into the row `mail_upsert_messages_v1` stores.
// Pure functions only: no network, no secrets, so they are tested on their own
// (`mail_sync_parse_test.ts`).

export type MailAttachment = {
  filename: string;
  mime_type: string;
  size: number;
  inline: boolean;
  attachment_id?: string;
  part_id?: string;
};

export type MailRecord = {
  provider_message_id: string;
  provider_thread_id: string | null;
  provider_folder_id: string | null;
  rfc_message_id: string | null;
  in_reply_to: string | null;
  reference_ids: string[];
  direction: "in" | "out";
  from_address: string;
  from_name: string | null;
  to_addresses: string[];
  cc_addresses: string[];
  subject: string;
  snippet: string | null;
  body_text: string | null;
  has_attachments: boolean;
  attachments: MailAttachment[];
  labels: string[];
  provider_read: boolean;
  in_inbox: boolean;
  is_bulk: boolean;
  received_at: string;
};

/** What the server keeps of a body: enough to read it, search it and link it. */
export const BODY_TEXT_LIMIT = 20000;

// ---------------------------------------------------------------------------
// Text
// ---------------------------------------------------------------------------

const NAMED_ENTITIES: Record<string, string> = {
  nbsp: " ",
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
  aacute: "á",
  eacute: "é",
  iacute: "í",
  oacute: "ó",
  uacute: "ú",
  Aacute: "Á",
  Eacute: "É",
  Iacute: "Í",
  Oacute: "Ó",
  Uacute: "Ú",
  ntilde: "ñ",
  Ntilde: "Ñ",
  uuml: "ü",
  Uuml: "Ü",
  agrave: "à",
  egrave: "è",
  iexcl: "¡",
  iquest: "¿",
  deg: "°",
  ordm: "º",
  ordf: "ª",
  euro: "€",
  copy: "©",
  reg: "®",
  trade: "™",
  laquo: "«",
  raquo: "»",
  mdash: "—",
  ndash: "–",
  hellip: "…",
  bull: "•",
  middot: "·",
  lsquo: "‘",
  rsquo: "’",
  ldquo: "“",
  rdquo: "”",
  times: "×",
  shy: "",
  zwnj: "",
  zwj: "",
};

export function decodeEntities(text: string): string {
  return text.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (match, code: string) => {
    if (code[0] === "#") {
      const value = code[1] === "x" || code[1] === "X"
        ? parseInt(code.slice(2), 16)
        : parseInt(code.slice(1), 10);
      if (!Number.isFinite(value) || value <= 0 || value > 0x10ffff) return match;
      try {
        return String.fromCodePoint(value);
      } catch (_) {
        return match;
      }
    }
    return NAMED_ENTITIES[code] ?? NAMED_ENTITIES[code.toLowerCase()] ?? match;
  });
}

/**
 * Como [decodeEntities], pero también lo codificado dos veces: hay remitentes
 * que mandan «p&amp;aacute;gina», que tras una pasada sigue diciendo
 * «p&aacute;gina».
 */
export function decodeEntitiesDeep(text: string): string {
  let out = decodeEntities(text);
  for (let pass = 0; pass < 2 && /&(#x[0-9a-f]+|#\d+|[a-z]+);/i.test(out); pass++) {
    const next = decodeEntities(out);
    if (next === out) break;
    out = next;
  }
  return out;
}

/**
 * Palabras pegadas («destinoCuenta»): una minúscula seguida de una mayúscula.
 * El texto plano que algunos bancos generan de su HTML pierde los espacios
 * entre celdas; si el HTML trae claramente menos, se lee el HTML.
 */
export function gluedWords(text: string): number {
  return (text.match(/[a-záéíóúñ][A-ZÁÉÍÓÚÑ]/g) ?? []).length;
}

/**
 * Reglas de CSS escritas en el texto plano («.header { margin: 0; }»): hay
 * remitentes que generan su versión en texto quitando las etiquetas pero no
 * los estilos. Con dos o más, se lee el HTML.
 */
export function cssRules(text: string): number {
  return (text.match(/[^{}\n]{0,160}\{\s*(?:[-a-zA-Z]+\s*:[^;{}]*;?\s*)+\}/g) ?? []).length;
}

export function htmlToText(html: string): string {
  let text = html
    .replace(/<!--[\s\S]*?-->/g, " ")
    .replace(/<(head|style|script|title)\b[\s\S]*?<\/\1\s*>/gi, " ")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/(p|div|tr|li|h[1-6]|table|blockquote|section|article)\s*>/gi, "\n")
    .replace(/<li\b[^>]*>/gi, "\n• ")
    .replace(/<\/t[dh]\s*>/gi, " ")
    .replace(/<[^>]+>/g, " ");
  text = decodeEntitiesDeep(text);
  return tidyText(text);
}

export function tidyText(text: string): string {
  return text
    .replace(/\r\n?/g, "\n")
    .replace(/[ \t\f\v ]+/g, " ")
    .split("\n")
    .map((line) => line.trim())
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

export function limitText(text: string | null | undefined, limit = BODY_TEXT_LIMIT): string | null {
  const value = (text ?? "").trim();
  if (!value) return null;
  return value.length > limit ? value.slice(0, limit) : value;
}

export function decodeBase64Url(data: string): Uint8Array {
  const normalized = data.replace(/-/g, "+").replace(/_/g, "/").replace(/\s+/g, "");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export function base64UrlToBase64(data: string): string {
  const normalized = data.replace(/-/g, "+").replace(/_/g, "/").replace(/\s+/g, "");
  return normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
}

export function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

export function decodeBytes(bytes: Uint8Array, charset: string | null | undefined): string {
  const label = (charset ?? "").trim().replace(/^["']|["']$/g, "").toLowerCase() || "utf-8";
  try {
    return new TextDecoder(label).decode(bytes);
  } catch (_) {
    return new TextDecoder("utf-8").decode(bytes);
  }
}

/** RFC 2047 encoded words (`=?ISO-8859-1?Q?Mu=F1oz?=`), as some senders still use. */
export function decodeMimeWords(value: string): string {
  return value
    .replace(/(=\?[^?]+\?[bq]\?[^?]*\?=)\s+(?==\?)/gi, "$1")
    .replace(
      /=\?([^?]+)\?([bq])\?([^?]*)\?=/gi,
      (match, charset: string, encoding: string, text: string) => {
        try {
          let bytes: Uint8Array;
          if (encoding.toLowerCase() === "b") {
            bytes = decodeBase64Url(text);
          } else {
            const raw = text.replace(/_/g, " ");
            const out: number[] = [];
            for (let i = 0; i < raw.length; i++) {
              if (raw[i] === "=" && /^[0-9a-f]{2}$/i.test(raw.slice(i + 1, i + 3))) {
                out.push(parseInt(raw.slice(i + 1, i + 3), 16));
                i += 2;
              } else {
                out.push(raw.charCodeAt(i) & 0xff);
              }
            }
            bytes = new Uint8Array(out);
          }
          return decodeBytes(bytes, charset.split("*")[0]);
        } catch (_) {
          return match;
        }
      },
    );
}

// ---------------------------------------------------------------------------
// Addresses and headers
// ---------------------------------------------------------------------------

/** Splits `"Doe, Ana" <ana@x.cl>, b@y.cl` on the commas that separate people. */
function splitAddressList(value: string): string[] {
  const parts: string[] = [];
  let current = "";
  let quoted = false;
  let angled = false;
  for (const ch of value) {
    if (ch === '"') quoted = !quoted;
    else if (ch === "<") angled = true;
    else if (ch === ">") angled = false;
    if ((ch === "," || ch === ";") && !quoted && !angled) {
      parts.push(current);
      current = "";
    } else {
      current += ch;
    }
  }
  parts.push(current);
  return parts.map((part) => part.trim()).filter(Boolean);
}

export function parseAddress(
  value: string | null | undefined,
): { name: string | null; address: string } {
  const text = decodeMimeWords(decodeEntities(value ?? "")).trim();
  const angled = text.match(/<\s*([^<>\s]+@[^<>\s]+)\s*>/);
  if (angled) {
    const name = text.slice(0, angled.index).trim().replace(/^"+|"+$/g, "").trim();
    const address = angled[1].toLowerCase();
    return { name: name && name.toLowerCase() !== address ? name : null, address };
  }
  const bare = text.match(/[^\s<>"',;]+@[^\s<>"',;]+/);
  return { name: null, address: bare ? bare[0].toLowerCase() : "" };
}

export function parseAddressList(value: string | null | undefined): string[] {
  const text = decodeEntities(value ?? "");
  const seen = new Set<string>();
  for (const part of splitAddressList(text)) {
    const { address } = parseAddress(part);
    if (address.includes("@")) seen.add(address);
  }
  return [...seen];
}

function stripAngles(value: string): string {
  return value.trim().replace(/^<+|>+$/g, "").trim();
}

export function messageIdValue(value: string | null | undefined): string | null {
  const first = (value ?? "").match(/<[^<>]+>/)?.[0] ?? (value ?? "").trim().split(/\s+/)[0] ?? "";
  const id = stripAngles(first);
  return id || null;
}

export function referenceIds(value: string | null | undefined): string[] {
  const ids = (value ?? "").match(/<[^<>]+>/g) ?? [];
  return [...new Set(ids.map(stripAngles).filter(Boolean))].slice(-20);
}

/** Raw header block (Zoho `headerContent`) → lower-cased name → first value. */
export function parseRawHeaders(raw: string): Map<string, string> {
  const headers = new Map<string, string>();
  const unfolded = raw.replace(/\r\n?/g, "\n").replace(/\n[ \t]+/g, " ");
  for (const line of unfolded.split("\n")) {
    const index = line.indexOf(":");
    if (index <= 0) continue;
    const name = line.slice(0, index).trim().toLowerCase();
    if (!name || headers.has(name)) continue;
    headers.set(name, line.slice(index + 1).trim());
  }
  return headers;
}

/** A mass mailing: an unsubscribe link, a bulk precedence or Gmail's Promotions tab. */
export function looksBulk(headers: Map<string, string>, labels: string[] = []): boolean {
  if (labels.includes("CATEGORY_PROMOTIONS")) return true;
  if (headers.has("list-unsubscribe")) return true;
  const precedence = (headers.get("precedence") ?? "").toLowerCase();
  return precedence === "bulk" || precedence === "list" || precedence === "junk";
}

// ---------------------------------------------------------------------------
// Gmail
// ---------------------------------------------------------------------------

type GmailHeader = { name?: string; value?: string };
type GmailPart = {
  partId?: string;
  mimeType?: string;
  filename?: string;
  headers?: GmailHeader[];
  body?: { size?: number; data?: string; attachmentId?: string };
  parts?: GmailPart[];
};
export type GmailMessage = {
  id?: string;
  threadId?: string;
  labelIds?: string[];
  snippet?: string;
  internalDate?: string;
  payload?: GmailPart;
};

function gmailHeaders(part: GmailPart | undefined): Map<string, string> {
  const headers = new Map<string, string>();
  for (const header of part?.headers ?? []) {
    const name = (header.name ?? "").toLowerCase();
    if (name && !headers.has(name)) headers.set(name, header.value ?? "");
  }
  return headers;
}

function partCharset(part: GmailPart): string | null {
  const contentType = gmailHeaders(part).get("content-type") ?? "";
  return contentType.match(/charset\s*=\s*"?([^";\s]+)/i)?.[1] ?? null;
}

function walkParts(part: GmailPart | undefined, visit: (part: GmailPart) => void) {
  if (!part) return;
  visit(part);
  for (const child of part.parts ?? []) walkParts(child, visit);
}

/** The readable body of a Gmail message: its plain text, or its HTML as text. */
export function gmailBodies(message: GmailMessage): { text: string | null; html: string | null } {
  let plain: string | null = null;
  let html: string | null = null;
  walkParts(message.payload, (part) => {
    if (part.filename) return;
    const disposition = (gmailHeaders(part).get("content-disposition") ?? "").toLowerCase();
    if (disposition.startsWith("attachment")) return;
    const data = part.body?.data;
    if (!data) return;
    const mime = (part.mimeType ?? "").toLowerCase();
    if (mime === "text/plain" && plain === null) {
      plain = decodeBytes(decodeBase64Url(data), partCharset(part));
    } else if (mime === "text/html" && html === null) {
      html = decodeBytes(decodeBase64Url(data), partCharset(part));
    }
  });
  const plainText = plain !== null ? tidyText(decodeEntitiesDeep(plain)) : null;
  const htmlText = html !== null ? htmlToText(html) : null;
  let text: string | null;
  if (plainText !== null && plainText.length >= 20) {
    const worse = htmlText !== null && (
      gluedWords(plainText) >= gluedWords(htmlText) + 3 ||
      cssRules(plainText) >= 2 + cssRules(htmlText)
    );
    text = worse ? htmlText : plainText;
  } else {
    text = htmlText ?? plainText;
  }
  return { text, html };
}

export function gmailAttachments(message: GmailMessage): MailAttachment[] {
  const attachments: MailAttachment[] = [];
  walkParts(message.payload, (part) => {
    const filename = decodeMimeWords(part.filename ?? "").trim();
    if (!filename) return;
    const headers = gmailHeaders(part);
    const disposition = (headers.get("content-disposition") ?? "").toLowerCase();
    const mime = (part.mimeType ?? "application/octet-stream").toLowerCase();
    const inline = disposition.startsWith("inline") ||
      (!disposition && headers.has("content-id") && mime.startsWith("image/"));
    attachments.push({
      filename,
      mime_type: mime,
      size: Number(part.body?.size ?? 0) || 0,
      inline,
      ...(part.body?.attachmentId ? { attachment_id: part.body.attachmentId } : {}),
      ...(part.partId ? { part_id: part.partId } : {}),
    });
  });
  return attachments;
}

/** Finds a part by id (an attachment small enough to travel inside the message). */
export function gmailPartData(message: GmailMessage, partId: string): string | null {
  let found: string | null = null;
  walkParts(message.payload, (part) => {
    if (found === null && part.partId === partId && part.body?.data) found = part.body.data;
  });
  return found;
}

export function gmailMessageToRecord(message: GmailMessage): MailRecord | null {
  const id = (message.id ?? "").trim();
  if (!id) return null;
  const labels = message.labelIds ?? [];
  const headers = gmailHeaders(message.payload);
  const from = parseAddress(headers.get("from"));
  const { text } = gmailBodies(message);
  const attachments = gmailAttachments(message);
  const internal = Number(message.internalDate ?? 0);
  const dateHeader = Date.parse(headers.get("date") ?? "");
  const receivedMs = internal > 0
    ? internal
    : Number.isFinite(dateHeader)
    ? dateHeader
    : Date.now();
  return {
    provider_message_id: id,
    provider_thread_id: message.threadId ?? null,
    provider_folder_id: null,
    rfc_message_id: messageIdValue(headers.get("message-id")),
    in_reply_to: messageIdValue(headers.get("in-reply-to")),
    reference_ids: referenceIds(headers.get("references")),
    direction: labels.includes("SENT") ? "out" : "in",
    from_address: from.address,
    from_name: from.name,
    to_addresses: parseAddressList(headers.get("to")),
    cc_addresses: parseAddressList(headers.get("cc")),
    subject: decodeMimeWords(headers.get("subject") ?? "").trim(),
    snippet: limitText(decodeEntities(message.snippet ?? ""), 600),
    body_text: limitText(text),
    has_attachments: attachments.some((attachment) => !attachment.inline),
    attachments,
    labels,
    provider_read: !labels.includes("UNREAD"),
    in_inbox: labels.includes("INBOX"),
    is_bulk: looksBulk(headers, labels),
    received_at: new Date(receivedMs).toISOString(),
  };
}

/** Gmail messages the store never keeps: drafts, spam, trash and chats. */
export function gmailIgnored(labels: string[] | undefined): boolean {
  const set = new Set(labels ?? []);
  return set.has("DRAFT") || set.has("SPAM") || set.has("TRASH") || set.has("CHAT");
}

// ---------------------------------------------------------------------------
// Zoho
// ---------------------------------------------------------------------------

export function parseZohoRead(value: unknown): boolean {
  if (typeof value === "boolean") return value;
  if (typeof value === "number") return value !== 0;
  const normalized = String(value ?? "").trim().toUpperCase();
  if (["0", "UNREAD", "UNREADMESSAGE", "FALSE"].includes(normalized)) return false;
  return true;
}

function zohoFlag(value: unknown): boolean {
  const normalized = String(value ?? "").trim().toLowerCase();
  return normalized === "1" || normalized === "true" || normalized === "yes";
}

export type ZohoListItem = Record<string, unknown>;

export function zohoHasAttachment(item: ZohoListItem): boolean {
  return zohoFlag(item.hasAttachment) || zohoFlag(item.attachment) ||
    zohoFlag(item.isAttachmentAvailable) || Number(item.attachmentCount ?? 0) > 0;
}

export function zohoAttachments(payload: unknown): MailAttachment[] {
  const root = payload && typeof payload === "object" ? (payload as Record<string, unknown>) : {};
  const data = root.data && typeof root.data === "object"
    ? (root.data as Record<string, unknown>)
    : root;
  const lists = [data.attachments, data.attachmentInfo, data.attachmentList]
    .filter(Array.isArray) as unknown[][];
  const attachments: MailAttachment[] = [];
  for (const list of lists) {
    for (const raw of list) {
      if (!raw || typeof raw !== "object") continue;
      const item = raw as Record<string, unknown>;
      const filename = String(item.attachmentName ?? item.fileName ?? item.name ?? "").trim();
      const id = String(item.attachmentId ?? item.id ?? "").trim();
      if (!filename || !id) continue;
      attachments.push({
        filename,
        mime_type: String(item.contentType ?? item.mimeType ?? "application/octet-stream")
          .toLowerCase(),
        size: Number(item.attachmentSize ?? item.size ?? 0) || 0,
        inline: false,
        attachment_id: id,
      });
    }
  }
  return attachments;
}

/**
 * Qué es una carpeta de Zoho para el store. Zoho saca solo de la bandeja de
 * entrada lo que su filtro inteligente clasifica: Notification y Newsletter
 * son, en Gmail, las categorías Notificaciones y Promociones de la misma
 * bandeja. Archive, Snoozed y las del usuario son correo archivado.
 */
export type ZohoFolderKind =
  | "inbox"
  | "sent"
  | "notification"
  | "newsletter"
  | "archive"
  | "snoozed"
  | "custom";

export type ZohoSyncFolder = { id: string; kind: ZohoFolderKind; name?: string };

/** Labels con el vocabulario de Gmail, para que ambas cuentas se lean igual. */
export function zohoFolderLabels(kind: ZohoFolderKind): string[] {
  switch (kind) {
    case "inbox":
      return ["INBOX"];
    case "sent":
      return ["SENT"];
    case "notification":
      return ["INBOX", "CATEGORY_UPDATES"];
    case "newsletter":
      return ["INBOX", "CATEGORY_PROMOTIONS"];
    case "snoozed":
      return ["SNOOZED"];
    default:
      return [];
  }
}

type ZohoRawFolder = Record<string, unknown>;

function zohoText(value: unknown): string {
  return String(value ?? "").trim();
}

/**
 * Las carpetas de Zoho que guardan correo para leer, con su tipo.
 *
 * Zoho entrega con `folderType` «Inbox» la entrada, Notification, Newsletter y
 * las carpetas del usuario: la entrada es la de ruta `/Inbox` (o nombre
 * «Inbox»), y si ninguna viene así, la primera de ese tipo. Borradores,
 * plantillas, la bandeja de salida, spam y papelera no se guardan — igual que
 * en Gmail (`gmailIgnored`).
 */
export function zohoSyncFolders(rawFolders: ZohoRawFolder[]): ZohoSyncFolder[] {
  const usable = rawFolders.filter((raw) => zohoText(raw.folderId));
  const typed = (raw: ZohoRawFolder) => zohoText(raw.folderType).toLowerCase();
  const named = (raw: ZohoRawFolder) => zohoText(raw.folderName).toLowerCase();
  const inboxCandidates = usable.filter((raw) =>
    typed(raw) === "inbox" || (!typed(raw) && ["inbox", "bandeja de entrada"].includes(named(raw)))
  );
  const inbox = inboxCandidates.find((raw) =>
    zohoText(raw.path).toLowerCase() === "/inbox" ||
    ["inbox", "bandeja de entrada"].includes(named(raw))
  ) ?? inboxCandidates[0];

  const skipped = new Set(["drafts", "templates", "outbox", "spam", "junk", "trash"]);
  const skippedNames = new Set([
    "drafts",
    "borradores",
    "templates",
    "plantillas",
    "outbox",
    "bandeja de salida",
    "spam",
    "junk",
    "correo no deseado",
    "trash",
    "papelera",
  ]);
  const folders: ZohoSyncFolder[] = [];
  let sentSeen = false;
  for (const raw of usable) {
    const id = zohoText(raw.folderId);
    const type = typed(raw);
    const name = named(raw);
    let kind: ZohoFolderKind;
    if (raw === inbox) {
      kind = "inbox";
    } else if (skipped.has(type) || (!type && skippedNames.has(name))) {
      continue;
    } else if (
      !sentSeen &&
      (type === "sent" || type === "sent items" || ["sent", "enviados", "enviado"].includes(name))
    ) {
      kind = "sent";
      sentSeen = true;
    } else if (name === "notification" || name === "notificaciones") {
      kind = "notification";
    } else if (name === "newsletter" || name === "newsletters") {
      kind = "newsletter";
    } else if (type === "archive" || name === "archive" || name === "archivar") {
      kind = "archive";
    } else if (type === "snoozed" || name === "snoozed" || name === "pospuesto") {
      kind = "snoozed";
    } else if (type === "sent" || type === "sent items") {
      continue;
    } else {
      kind = "custom";
    }
    folders.push({ id, kind, name: zohoText(raw.folderName) || undefined });
  }
  return inbox ? folders : [];
}

export function zohoMessageToRecord(
  item: ZohoListItem,
  folder: { id: string; kind: ZohoFolderKind },
  extra: { html?: string | null; rawHeaders?: string | null; attachments?: MailAttachment[] } = {},
): MailRecord | null {
  const id = String(item.messageId ?? "").trim();
  if (!id) return null;
  const headers = parseRawHeaders(extra.rawHeaders ?? "");
  const from = parseAddress(String(item.fromAddress ?? item.sender ?? ""));
  const senderName = decodeEntities(String(item.sender ?? "")).trim();
  const fromName = from.name ?? (senderName && !senderName.includes("@") ? senderName : null);
  const received = Number(item.receivedTime ?? item.sentDateInGMT ?? 0);
  const attachments = extra.attachments ?? [];
  const body = extra.html ? htmlToText(extra.html) : null;
  return {
    provider_message_id: id,
    provider_thread_id: item.threadId ? String(item.threadId) : null,
    provider_folder_id: folder.id,
    rfc_message_id: messageIdValue(headers.get("message-id")),
    in_reply_to: messageIdValue(headers.get("in-reply-to")),
    reference_ids: referenceIds(headers.get("references")),
    direction: folder.kind === "sent" ? "out" : "in",
    from_address: from.address,
    from_name: fromName,
    to_addresses: parseAddressList(String(item.toAddress ?? "")),
    cc_addresses: parseAddressList(String(item.ccAddress ?? "")),
    subject: decodeEntities(String(item.subject ?? "")).trim(),
    snippet: limitText(decodeEntities(String(item.summary ?? "")), 600),
    body_text: limitText(body),
    has_attachments: attachments.length > 0 || zohoHasAttachment(item),
    attachments,
    labels: zohoFolderLabels(folder.kind),
    provider_read: parseZohoRead(item.isRead ?? item.status),
    in_inbox: zohoFolderLabels(folder.kind).includes("INBOX"),
    is_bulk: looksBulk(headers, zohoFolderLabels(folder.kind)),
    received_at: new Date(received > 0 ? received : Date.now()).toISOString(),
  };
}
