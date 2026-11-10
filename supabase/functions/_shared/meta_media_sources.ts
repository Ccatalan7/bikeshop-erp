// Where the file of an Instagram or Messenger message can be fetched from.
//
// Meta names it twice: in the webhook event (`attachments[].payload.url`) and
// in the message read back by its id (`attachments.data[]`). Both are signed,
// short-lived URLs on Meta's CDN. They are used once to download the file
// and never stored, logged or handed to the app, and only Meta's own hosts
// are accepted: a URL is data from a request, not a place to fetch blindly.

type JsonRecord = Record<string, unknown>;

/** What the ERP can store as a file. A story, a reel or a view-once photo is
 * not one: it stays a text placeholder. */
export type MetaMediaKind = "image" | "video" | "audio" | "file";

export type MetaMediaSource = { kind: MetaMediaKind; url: string };

const MEDIA_KINDS: ReadonlySet<string> = new Set(["image", "video", "audio", "file"]);

// lookaside.fbsbx.com (Instagram), *.fbcdn.net and *.cdninstagram.com.
const TRUSTED_MEDIA_HOST_SUFFIXES = ["fbsbx.com", "fbcdn.net", "cdninstagram.com"];

function asRecord(value: unknown): JsonRecord | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : null;
}

export function isMetaMediaKind(value: unknown): value is MetaMediaKind {
  return typeof value === "string" && MEDIA_KINDS.has(value);
}

/** The URL when it is HTTPS on one of Meta's CDN hosts, else null. */
export function trustedMetaMediaUrl(value: unknown): string | null {
  if (typeof value !== "string" || value.length > 4_096) return null;
  try {
    const url = new URL(value.trim());
    if (url.protocol !== "https:" || url.username || url.password || url.port) {
      return null;
    }
    const host = url.hostname.toLowerCase();
    const trusted = TRUSTED_MEDIA_HOST_SUFFIXES.some((suffix) =>
      host === suffix || host.endsWith(`.${suffix}`)
    );
    return trusted ? url.toString() : null;
  } catch {
    return null;
  }
}

/** The storable files of a webhook message, in the order Meta sent them. */
export function metaMediaSourcesFromWebhook(attachments: unknown): MetaMediaSource[] {
  if (!Array.isArray(attachments)) return [];
  const sources: MetaMediaSource[] = [];
  for (const raw of attachments) {
    const attachment = asRecord(raw);
    const kind = typeof attachment?.type === "string" ? attachment.type.toLowerCase() : "";
    if (!isMetaMediaKind(kind)) continue;
    const url = trustedMetaMediaUrl(asRecord(attachment?.payload)?.url);
    if (url) sources.push({ kind, url });
  }
  return sources;
}

function kindForMimeType(value: unknown): MetaMediaKind {
  const mime = typeof value === "string" ? value.toLowerCase() : "";
  if (mime.startsWith("image/")) return "image";
  if (mime.startsWith("video/")) return "video";
  if (mime.startsWith("audio/")) return "audio";
  return "file";
}

/** The storable files of a message read back from the Graph API
 * (`GET /{message-id}?fields=attachments`). */
export function metaMediaSourcesFromGraph(message: unknown): MetaMediaSource[] {
  const data = asRecord(asRecord(message)?.attachments)?.data;
  if (!Array.isArray(data)) return [];
  const sources: MetaMediaSource[] = [];
  for (const raw of data) {
    const attachment = asRecord(raw);
    if (!attachment) continue;
    const image = trustedMetaMediaUrl(asRecord(attachment.image_data)?.url);
    const video = trustedMetaMediaUrl(asRecord(attachment.video_data)?.url);
    const file = trustedMetaMediaUrl(attachment.file_url);
    if (image) {
      sources.push({ kind: "image", url: image });
    } else if (video) {
      sources.push({ kind: "video", url: video });
    } else if (file) {
      sources.push({ kind: kindForMimeType(attachment.mime_type), url: file });
    }
  }
  return sources;
}
