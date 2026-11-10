// Photos, videos, voice messages and files that arrive by Instagram or
// Messenger.
//
// Until 2026-11-10 the integration kept only the words «Imagen recibida»
// (owner: «la imagen no llegó»). Now the file is downloaded on the server
// into the private attachment registry, like a WhatsApp file, and the
// database turns the message into the bubble every app version already draws
// (`attach_meta_message_media`).
//
// Two ways to the file, one way to store it:
// - the webhook has the URL Meta sends with the event
//   (`hydrateFreshMetaMessageMedia`);
// - the scheduled sweep asks Meta for the message by its id
//   (`resolveDueMetaMessageMedia`): what the webhook missed and what arrived
//   before this existed. Meta answers only for the 20 newest messages of a
//   conversation, and may refuse people without a role on the app until the
//   app review is approved.
// The database decides who is due and stamps every attempt
// (`claim_meta_message_media`, `claim_meta_message_media_due`), so the two
// never fetch the same file. Failures are codes on the service-only event
// row; a message that gets no file keeps its placeholder.

import {
  buildPrivateMessagingAttachmentPath,
  maxBytesForContentType,
  MESSAGING_ATTACHMENT_MIME_BY_EXTENSION,
  normalizedContentType,
  PRIVATE_MESSAGING_BUCKET,
  validateMessagingAttachment,
} from "./messaging_attachments.ts";
import {
  interpretMetaGraphFailure,
  type MetaFetch,
  metaGraphVersion,
  type MetaRpcClient,
} from "./meta_contact_profile.ts";
import {
  type MetaMediaKind,
  type MetaMediaSource,
  metaMediaSourcesFromGraph,
  trustedMetaMediaUrl,
} from "./meta_media_sources.ts";
import { storeVoiceNotePlaybackTwin } from "./voice_note_twin.ts";

type JsonRecord = Record<string, unknown>;

export type MetaMediaClient = MetaRpcClient & {
  storage: {
    from(bucket: string): {
      upload(
        path: string,
        body: Blob,
        options: { contentType: string; upsert: boolean },
      ): Promise<{ error: unknown }>;
      remove(paths: string[]): Promise<{ error: unknown }>;
    };
  };
};

/** The message that will own the file, as a claim names it. */
export type ClaimedMetaMediaMessage = {
  messageId: string;
  tenantId: string;
  conversationId: string;
  externalMessageId: string;
  mediaType: string;
};

export type MetaMediaOutcome =
  | { ok: true }
  | { ok: false; error: string; retrySoon: boolean };

export type MetaMessageMediaSweep = {
  claimed: number;
  attached: number;
  /** One short code per message that got no file. */
  errors: string[];
};

const GRAPH_REQUEST_TIMEOUT_MS = 8_000;
const DOWNLOAD_TIMEOUT_MS = 30_000;
const MAX_REDIRECTS = 3;
// Same cap as the WhatsApp webhook: the decoder runs inside the request's CPU
// budget. A longer note gets its twin when it is first played.
const VOICE_NOTE_TWIN_MAX_BYTES = 256 * 1024;

// The first extension listed for a type is the one a stored file gets.
const EXTENSION_BY_CONTENT_TYPE: Readonly<Record<string, string>> = (() => {
  const map: Record<string, string> = {};
  for (const [extension, type] of Object.entries(MESSAGING_ATTACHMENT_MIME_BY_EXTENSION)) {
    map[type] ??= extension;
  }
  return map;
})();

const FILENAME_BY_KIND: Readonly<Record<MetaMediaKind, string>> = {
  image: "imagen",
  video: "video",
  audio: "audio",
  file: "documento",
};

// What to allow while reading, before the bytes say what the file is: the
// largest file of that kind the registry accepts.
const READ_CAP_TYPE_BY_KIND: Readonly<Record<MetaMediaKind, string>> = {
  image: "image/jpeg",
  video: "video/mp4",
  audio: "audio/mp4",
  file: "application/pdf",
};

function text(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function startsWith(bytes: Uint8Array, signature: number[], offset = 0): boolean {
  if (bytes.byteLength < offset + signature.length) return false;
  return signature.every((byte, index) => bytes[offset + index] === byte);
}

/** What the bytes are, by their first bytes. Null when they do not say. */
export function sniffContentType(bytes: Uint8Array): string | null {
  if (startsWith(bytes, [0xff, 0xd8, 0xff])) return "image/jpeg";
  if (startsWith(bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return "image/png";
  if (startsWith(bytes, [0x47, 0x49, 0x46, 0x38])) return "image/gif";
  if (
    startsWith(bytes, [0x52, 0x49, 0x46, 0x46]) && startsWith(bytes, [0x57, 0x45, 0x42, 0x50], 8)
  ) {
    return "image/webp";
  }
  if (startsWith(bytes, [0x25, 0x50, 0x44, 0x46])) return "application/pdf";
  if (startsWith(bytes, [0x4f, 0x67, 0x67, 0x53])) return "audio/ogg";
  if (startsWith(bytes, [0x49, 0x44, 0x33])) return "audio/mpeg";
  // ISO media (`....ftyp`): MP4, M4A and 3GP share the container.
  if (startsWith(bytes, [0x66, 0x74, 0x79, 0x70], 4)) return "video/mp4";
  return null;
}

/** The type a file is stored under. The bytes win over the header Meta's CDN
 * sends; inside the MP4 container, where the bytes cannot tell sound from
 * video, the header and what Meta called the attachment decide. */
export function storedContentType(
  kind: MetaMediaKind,
  headerType: string | null,
  bytes: Uint8Array,
): string {
  const header = normalizedContentType(headerType ?? "");
  const sniffed = sniffContentType(bytes);
  if (sniffed === "video/mp4") {
    if (header === "video/3gpp") return header;
    if (header === "audio/mp4" || kind === "audio") return "audio/mp4";
    return "video/mp4";
  }
  return sniffed ?? header;
}

async function readBoundedBytes(response: Response, maxBytes: number): Promise<Uint8Array> {
  const length = Number(response.headers.get("content-length") ?? "");
  if (Number.isFinite(length) && length > maxBytes) {
    await response.body?.cancel().catch(() => {});
    throw new Error("attachment_too_large");
  }
  if (!response.body) return new Uint8Array();
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maxBytes) {
        await reader.cancel().catch(() => {});
        throw new Error("attachment_too_large");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const result = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return result;
}

/** Downloads from Meta's CDN and nowhere else: a redirect is followed only to
 * another of Meta's hosts. The Page token is never sent to the CDN. */
async function downloadFromMeta(
  source: MetaMediaSource,
  fetchImpl: MetaFetch,
): Promise<{ response: Response } | { ok: false; error: string; retrySoon: boolean }> {
  let current: string | null = trustedMetaMediaUrl(source.url);
  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    if (!current) return { ok: false, error: "untrusted_media_host", retrySoon: false };
    let response: Response;
    try {
      response = await fetchImpl(current, {
        redirect: "manual",
        signal: AbortSignal.timeout(DOWNLOAD_TIMEOUT_MS),
      });
    } catch (_) {
      return { ok: false, error: "download_network", retrySoon: true };
    }
    if (response.status >= 300 && response.status < 400) {
      const location = response.headers.get("location");
      await response.body?.cancel().catch(() => {});
      if (!location) {
        return { ok: false, error: "download_redirect_without_target", retrySoon: false };
      }
      try {
        current = trustedMetaMediaUrl(new URL(location, current).toString());
      } catch {
        current = null;
      }
      continue;
    }
    if (!response.ok) {
      await response.body?.cancel().catch(() => {});
      return {
        ok: false,
        error: `download_${response.status}`,
        retrySoon: response.status >= 500 || response.status === 429,
      };
    }
    return { response };
  }
  return { ok: false, error: "download_too_many_redirects", retrySoon: false };
}

/** Downloads one file and attaches it to its message. Never throws. */
export async function storeMetaMessageMedia(params: {
  client: MetaMediaClient;
  message: ClaimedMetaMediaMessage;
  source: MetaMediaSource;
  /** Other storable files Meta sent in the same message. */
  moreFiles?: number;
  fetchImpl?: MetaFetch;
}): Promise<MetaMediaOutcome> {
  const { client, message, source } = params;
  try {
    const download = await downloadFromMeta(source, params.fetchImpl ?? fetch);
    if (!("response" in download)) return download;

    const headerType = download.response.headers.get("content-type");
    const readCap = maxBytesForContentType(READ_CAP_TYPE_BY_KIND[source.kind]);
    let bytes: Uint8Array;
    try {
      bytes = await readBoundedBytes(download.response, readCap);
    } catch (error) {
      const tooLarge = error instanceof Error && error.message === "attachment_too_large";
      return {
        ok: false,
        error: tooLarge ? "attachment_too_large" : "download_interrupted",
        retrySoon: !tooLarge,
      };
    }

    const contentType = storedContentType(source.kind, headerType, bytes);
    const extension = EXTENSION_BY_CONTENT_TYPE[contentType];
    if (!extension) return { ok: false, error: "unsupported_attachment_type", retrySoon: false };
    const filename = `${FILENAME_BY_KIND[source.kind]}.${extension}`;
    try {
      validateMessagingAttachment({ filename, contentType, sizeBytes: bytes.byteLength });
    } catch (error) {
      return {
        ok: false,
        error: error instanceof Error ? error.message : "invalid_attachment",
        retrySoon: false,
      };
    }

    const attachmentId = crypto.randomUUID();
    const storagePath = buildPrivateMessagingAttachmentPath({
      tenantId: message.tenantId,
      conversationId: message.conversationId,
      attachmentId,
      extension,
    });
    const bucket = client.storage.from(PRIVATE_MESSAGING_BUCKET);
    const { error: uploadError } = await bucket.upload(
      storagePath,
      new Blob([bytes.slice().buffer as ArrayBuffer], { type: contentType }),
      { contentType, upsert: false },
    );
    if (uploadError) return { ok: false, error: "storage_upload_failed", retrySoon: true };

    // A voice note in Ogg/Opus also gets the WAV twin Apple's players need.
    const playbackTwin = await storeVoiceNotePlaybackTwin({
      storage: client.storage,
      bucket: PRIVATE_MESSAGING_BUCKET,
      storagePath,
      contentType,
      bytes,
      maxBytes: VOICE_NOTE_TWIN_MAX_BYTES,
    });
    const discard = async () => {
      const paths = playbackTwin
        ? [storagePath, playbackTwin.playback_storage_path]
        : [storagePath];
      await bucket.remove(paths).catch(() => {});
    };

    let attached: JsonRecord | null = null;
    let attachError: { code?: string } | null = null;
    try {
      const { data, error } = await client.rpc("attach_meta_message_media", {
        p_message_id: message.messageId,
        p_attachment_id: attachmentId,
        p_original_filename: filename,
        p_extension: extension,
        p_declared_mime_type: contentType,
        p_size_bytes: bytes.byteLength,
        p_has_playback_twin: playbackTwin !== null,
        p_more_files: Math.max(0, params.moreFiles ?? 0),
      });
      attached = data && typeof data === "object" ? data as JsonRecord : null;
      attachError = error;
    } catch (_) {
      attachError = { code: "unreachable" };
    }
    if (attachError) {
      await discard();
      return {
        ok: false,
        error: `attach_${attachError.code ?? "rpc_error"}`,
        retrySoon: attachError.code === "unreachable",
      };
    }
    if (attached?.attached !== true) {
      // Another run attached its copy first: this one is not needed.
      await discard();
    }
    return { ok: true };
  } catch (_) {
    return { ok: false, error: "media_failed", retrySoon: false };
  }
}

function claimedMessage(value: unknown): ClaimedMetaMediaMessage | null {
  const item = value && typeof value === "object" ? value as JsonRecord : null;
  const messageId = text(item?.message_id);
  const tenantId = text(item?.tenant_id);
  const conversationId = text(item?.conversation_id);
  const externalMessageId = text(item?.external_message_id);
  if (!messageId || !tenantId || !conversationId || !externalMessageId) return null;
  return {
    messageId,
    tenantId,
    conversationId,
    externalMessageId,
    mediaType: text(item?.media_type) ?? "file",
  };
}

async function recordFailure(
  client: MetaRpcClient,
  messageId: string,
  failure: { error: string; retrySoon: boolean },
): Promise<void> {
  try {
    await client.rpc("fail_meta_message_media", {
      p_message_id: messageId,
      p_error: failure.error,
      p_retry_soon: failure.retrySoon,
    });
  } catch (_) {
    // The claim already stamped the attempt: the message waits its day.
  }
}

/** The file of a message the webhook just stored, from the URL Meta sent with
 * it. Returns what happened as a code; never throws. */
export async function hydrateFreshMetaMessageMedia(params: {
  client: MetaMediaClient;
  messageId: string;
  sources: readonly MetaMediaSource[];
  fetchImpl?: MetaFetch;
}): Promise<string> {
  // Without a usable URL nobody is claimed: the sweep asks Meta for it.
  if (params.sources.length === 0) return "no_source";
  try {
    const { data, error } = await params.client.rpc("claim_meta_message_media", {
      p_message_id: params.messageId,
    });
    if (error) return `claim_${error.code ?? "rpc_error"}`;
    const message = claimedMessage(data);
    if (!message) return "not_due";
    const outcome = await storeMetaMessageMedia({
      client: params.client,
      message,
      source: params.sources[0],
      moreFiles: params.sources.length - 1,
      fetchImpl: params.fetchImpl,
    });
    if (outcome.ok) return "attached";
    // When the URL of the event is what failed, the sweep asks Meta for a new
    // one on its next run instead of waiting a day. A file that is too large
    // or of a type the ERP does not keep would fail the same way: it waits.
    await recordFailure(params.client, message.messageId, {
      error: outcome.error,
      retrySoon: outcome.retrySoon || outcome.error.startsWith("download_") ||
        outcome.error === "untrusted_media_host",
    });
    return outcome.error;
  } catch (_) {
    return "media_failed";
  }
}

export function metaMessageMediaUrl(graphVersion: string, externalMessageId: string): string {
  return `https://graph.facebook.com/${graphVersion}/${
    encodeURIComponent(externalMessageId)
  }?fields=attachments`;
}

/** Asks Meta where the files of a stored message are. */
export async function fetchMetaMessageMediaSources(params: {
  graphVersion: string;
  externalMessageId: string;
  accessToken: string;
  fetchImpl?: MetaFetch;
}): Promise<
  | { ok: true; sources: MetaMediaSource[] }
  | { ok: false; error: string; retrySoon: boolean }
> {
  try {
    const response = await (params.fetchImpl ?? fetch)(
      metaMessageMediaUrl(params.graphVersion, params.externalMessageId),
      {
        headers: { Authorization: `Bearer ${params.accessToken}` },
        signal: AbortSignal.timeout(GRAPH_REQUEST_TIMEOUT_MS),
      },
    );
    const body = await response.json().catch(() => ({}));
    if (!response.ok) return interpretMetaGraphFailure(response.status, body);
    const sources = metaMediaSourcesFromGraph(body);
    if (sources.length === 0) return { ok: false, error: "no_media_in_message", retrySoon: false };
    return { ok: true, sources };
  } catch (_) {
    return { ok: false, error: "network", retrySoon: true };
  }
}

/** Fetches the files that are due for one Meta account. Never throws. */
export async function resolveDueMetaMessageMedia(params: {
  client: MetaMediaClient;
  provider: string;
  accountId: string;
  /** Defaults to `metaGraphVersion()`. */
  graphVersion?: string;
  limit?: number;
  fetchImpl?: MetaFetch;
}): Promise<MetaMessageMediaSweep> {
  const sweep: MetaMessageMediaSweep = { claimed: 0, attached: 0, errors: [] };
  try {
    const graphVersion = params.graphVersion ?? metaGraphVersion();
    const { data: claimData, error: claimError } = await params.client.rpc(
      "claim_meta_message_media_due",
      {
        p_provider: params.provider,
        p_external_account_id: params.accountId,
        p_limit: params.limit ?? 3,
      },
    );
    if (claimError) {
      sweep.errors.push(`claim_${claimError.code ?? "rpc_error"}`);
      return sweep;
    }
    const claim = (claimData ?? {}) as JsonRecord;
    const channelId = text(claim.channel_id);
    const messages = (Array.isArray(claim.messages) ? claim.messages : [])
      .map(claimedMessage)
      .filter((message): message is ClaimedMetaMediaMessage => message !== null);
    sweep.claimed = messages.length;
    if (!channelId || messages.length === 0) return sweep;

    const { data: credentialData, error: credentialError } = await params.client.rpc(
      "get_meta_channel_access_token",
      { p_channel_id: channelId },
    );
    const rawToken = ((credentialData ?? {}) as JsonRecord).access_token;
    const accessToken = typeof rawToken === "string" && rawToken ? rawToken : null;

    for (const message of messages) {
      let failure: { error: string; retrySoon: boolean } | null = null;
      if (credentialError || !accessToken) {
        // Without the channel's token nobody can be asked: it waits a day,
        // so a broken channel does not retry on every run.
        failure = { error: "credential_unavailable", retrySoon: false };
      } else {
        const found = await fetchMetaMessageMediaSources({
          graphVersion,
          externalMessageId: message.externalMessageId,
          accessToken,
          fetchImpl: params.fetchImpl,
        });
        if (!found.ok) {
          failure = found;
        } else {
          const outcome = await storeMetaMessageMedia({
            client: params.client,
            message,
            source: found.sources[0],
            moreFiles: found.sources.length - 1,
            fetchImpl: params.fetchImpl,
          });
          if (!outcome.ok) failure = outcome;
        }
      }
      if (failure) {
        await recordFailure(params.client, message.messageId, failure);
        sweep.errors.push(failure.error);
      } else {
        sweep.attached += 1;
      }
    }
  } catch (_) {
    sweep.errors.push("sweep_failed");
  }
  return sweep;
}
