// mail-sync: trae el correo de las casillas de la empresa al servidor.
//
// Entradas:
// - El despacho de pg_cron (`dispatch_mail_sync_v1`): `{run_id, token}` con un
//   token de un solo uso que sólo `claim_mail_sync_run_v1` acepta. Sin JWT.
// - Una persona del equipo con su JWT: `sync` (traer ahora), `prepare`
//   (casillas conectadas y directorio), `body` (el original para leerlo) y
//   `attachment` (un adjunto).
//
// Sólo lee las casillas encendidas (`mail_mailboxes.is_active`). Nunca guarda
// ni devuelve llaves, y nunca registra el contenido de un correo en los logs.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  base64UrlToBase64,
  bytesToBase64,
  gmailAttachments,
  gmailBodies,
  gmailIgnored,
  type GmailMessage,
  gmailMessageToRecord,
  gmailPartData,
  htmlToText,
  type MailAttachment,
  type MailRecord,
  parseZohoRead,
  zohoAttachments,
  zohoFolderLabels,
  zohoHasAttachment,
  type ZohoListItem,
  zohoMessageToRecord,
  type ZohoSyncFolder,
  zohoSyncFolders,
} from "../_shared/mail_sync_parse.ts";

declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void } | undefined;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const GMAIL_API = "https://gmail.googleapis.com/gmail/v1/users/me";
const zohoAccountsOrigin = Deno.env.get("ZOHO_ACCOUNTS_ORIGIN") ?? "https://accounts.zoho.com";
const zohoMailOrigin = Deno.env.get("ZOHO_MAIL_ORIGIN") ?? "https://mail.zoho.com";

/** Cuánto correo hacia atrás entra la primera vez. */
const BACKFILL_DAYS = 120;
/** Una corrida del despacho deja margen bajo el límite de 150 s de la función. */
const RUN_BUDGET_MS = 110_000;
const USER_SYNC_BUDGET_MS = 40_000;
const USER_SYNC_MIN_GAP_MS = 20_000;
const PREPARE_EVERY_MS = 60 * 60 * 1000;
const UPSERT_CHUNK = 20;
const GMAIL_CONCURRENCY = 4;
const ZOHO_CONCURRENCY = 2;
const ZOHO_PAGE = 100;
const ZOHO_NEW_PAGE = 50;
const MAX_ATTACHMENT_BYTES = 15 * 1024 * 1024;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type Admin = ReturnType<typeof adminClient>;
type Json = Record<string, unknown>;

type Mailbox = {
  id: string;
  tenant_id: string;
  provider: "gmail" | "zoho";
  address: string;
  is_active: boolean;
  sync_state: Json | null;
  last_synced_at: string | null;
  backfilled_at: string | null;
  last_sync_error?: string | null;
};

type EmailAccount = {
  id: string;
  tenant_id: string;
  provider: string;
  account_email: string;
  provider_account_id?: string | null;
  access_token?: string | null;
  refresh_token?: string | null;
  token_type?: string | null;
  scope?: string | null;
  token_expires_at?: string | null;
};

type AuthContext = { userId: string; tenantId: string; role: string };
type Stats = { new: number; updated: number };

class HttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

class ProviderError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
  }
}

class Deadline {
  constructor(readonly at: number) {}
  passed(marginMs = 0) {
    return Date.now() + marginMs >= this.at;
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const raw = await req.text();
  if (raw.length > 4096) return json({ error: "Invalid request" }, 400);
  let body: Json;
  try {
    const parsed = raw ? JSON.parse(raw) : {};
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("bad");
    body = parsed as Json;
  } catch (_) {
    return json({ error: "Invalid request" }, 400);
  }

  const admin = adminClient();
  if (isDispatch(body)) return await handleDispatch(admin, body);

  let auth: AuthContext;
  try {
    auth = await requireStaff(req, admin);
  } catch (_) {
    return json({ error: "Unauthorized" }, 401);
  }

  try {
    switch (body.action) {
      case "sync":
        return json(
          await syncMailboxes(
            admin,
            auth.tenantId,
            new Deadline(Date.now() + USER_SYNC_BUDGET_MS),
            USER_SYNC_MIN_GAP_MS,
          ),
        );
      case "prepare":
        return json(await handlePrepare(admin, auth));
      case "body":
        return json(await handleBody(admin, auth, body));
      case "attachment":
        return json(await handleAttachment(admin, auth, body));
      default:
        return json({ error: "Unknown action" }, 400);
    }
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    console.error("[mail-sync] action failed", body.action, safeMessage(error));
    return json({ error: safeMessage(error) }, status);
  }
});

// ---------------------------------------------------------------------------
// Despacho de pg_cron
// ---------------------------------------------------------------------------

function isDispatch(body: Json): body is { run_id: string; token: string } {
  return typeof body.run_id === "string" && UUID.test(body.run_id) &&
    typeof body.token === "string" && /^[0-9a-f]{64}$/.test(body.token);
}

async function handleDispatch(admin: Admin, body: { run_id: string; token: string }) {
  const { data: claimed, error } = await admin.rpc("claim_mail_sync_run_v1", {
    p_run_id: body.run_id,
    p_token: body.token,
  });
  if (error) return json({ error: "Unable to claim dispatch" }, 503);
  if (claimed !== true) return json({ error: "Invalid or consumed dispatch" }, 403);

  const work = (async () => {
    let result: unknown = null;
    let failure: string | null = null;
    try {
      result = await syncMailboxes(admin, null, new Deadline(Date.now() + RUN_BUDGET_MS));
    } catch (error) {
      failure = safeMessage(error);
    }
    const finished = await admin.rpc("finish_mail_sync_run_v1", {
      p_run_id: body.run_id,
      p_result: result,
      p_error: failure,
    });
    if (finished.error) console.error("[mail-sync] finish failed", finished.error.message);
  })();

  if (typeof EdgeRuntime !== "undefined" && EdgeRuntime?.waitUntil) {
    EdgeRuntime.waitUntil(work);
    return json({ accepted: true }, 202);
  }
  await work;
  return json({ ok: true });
}

// ---------------------------------------------------------------------------
// Sincronización
// ---------------------------------------------------------------------------

async function syncMailboxes(
  admin: Admin,
  tenantId: string | null,
  deadline: Deadline,
  minGapMs = 0,
) {
  let query = admin
    .from("mail_mailboxes")
    .select(
      "id, tenant_id, provider, address, is_active, sync_state, last_synced_at, backfilled_at",
    )
    .eq("is_active", true)
    .order("last_synced_at", { ascending: true, nullsFirst: true });
  if (tenantId) query = query.eq("tenant_id", tenantId);
  const { data, error } = await query;
  if (error) throw error;
  const mailboxes = (data ?? []) as Mailbox[];
  await prepareTenantsIfStale(admin, mailboxes);

  const report: Json[] = [];
  for (const mailbox of mailboxes) {
    if (deadline.passed(10_000)) {
      report.push({ mailbox: mailbox.id, skipped: "deadline" });
      continue;
    }
    if (
      minGapMs && mailbox.last_synced_at &&
      Date.now() - Date.parse(mailbox.last_synced_at) < minGapMs
    ) {
      report.push({ mailbox: mailbox.id, skipped: "recent" });
      continue;
    }
    try {
      const account = await loadAccountFor(admin, mailbox);
      if (!account) {
        await updateMailbox(admin, mailbox, {
          last_sync_error: "Nadie del equipo tiene esta casilla conectada en el ERP.",
        });
        report.push({ mailbox: mailbox.id, error: "no_connection" });
        continue;
      }
      const stats = mailbox.provider === "gmail"
        ? await syncGmail(admin, mailbox, account, deadline)
        : await syncZoho(admin, mailbox, account, deadline);
      report.push({ mailbox: mailbox.id, provider: mailbox.provider, ...stats });
    } catch (error) {
      const message = safeMessage(error);
      console.error("[mail-sync] mailbox failed", mailbox.provider, message);
      await updateMailbox(admin, mailbox, { last_sync_error: message.slice(0, 500) }).catch(
        () => {},
      );
      report.push({ mailbox: mailbox.id, error: message.slice(0, 200) });
    }
  }
  return { mailboxes: report };
}

/** Casillas recién conectadas y directorio de remitentes, como mucho una vez por hora. */
async function prepareTenantsIfStale(admin: Admin, mailboxes: Mailbox[]) {
  const byTenant = new Map<string, Mailbox[]>();
  for (const mailbox of mailboxes) {
    byTenant.set(mailbox.tenant_id, [...(byTenant.get(mailbox.tenant_id) ?? []), mailbox]);
  }
  for (const [tenant, list] of byTenant) {
    const oldest = Math.min(
      ...list.map((m) => Date.parse(String(m.sync_state?.prepared_at ?? "")) || 0),
    );
    if (Date.now() - oldest < PREPARE_EVERY_MS) continue;
    const { error } = await admin.rpc("mail_prepare_tenant_v1", { p_tenant_id: tenant });
    if (error) {
      console.error("[mail-sync] prepare failed", error.message);
      continue;
    }
    const preparedAt = new Date().toISOString();
    for (const mailbox of list) {
      await saveState(admin, mailbox, { ...(mailbox.sync_state ?? {}), prepared_at: preparedAt });
    }
  }
}

async function loadAccountFor(admin: Admin, mailbox: Mailbox): Promise<EmailAccount | null> {
  const { data, error } = await admin
    .from("email_accounts")
    .select(
      "id, tenant_id, provider, account_email, provider_account_id, access_token, refresh_token, token_type, scope, token_expires_at",
    )
    .eq("tenant_id", mailbox.tenant_id)
    .eq("provider", mailbox.provider)
    .eq("is_active", true);
  if (error) throw error;
  const candidates = ((data ?? []) as EmailAccount[]).filter((account) =>
    (account.account_email ?? "").trim().toLowerCase() === mailbox.address &&
    (account.refresh_token ?? "").trim() !== ""
  );
  candidates.sort((a, b) =>
    (Date.parse(b.token_expires_at ?? "") || 0) - (Date.parse(a.token_expires_at ?? "") || 0)
  );
  return candidates[0] ?? null;
}

async function saveState(admin: Admin, mailbox: Mailbox, state: Json, extra: Json = {}) {
  mailbox.sync_state = state;
  await updateMailbox(admin, mailbox, { sync_state: state, ...extra });
}

async function updateMailbox(admin: Admin, mailbox: Mailbox, patch: Json) {
  const { error } = await admin
    .from("mail_mailboxes")
    .update(patch)
    .eq("id", mailbox.id)
    .eq("tenant_id", mailbox.tenant_id);
  if (error) throw error;
}

/** Ids del proveedor que ya están guardados, con su estado de leído. */
async function knownMessages(admin: Admin, mailboxId: string, ids: string[]) {
  const known = new Map<string, { read: boolean; labels: string[] }>();
  const unique = [...new Set(ids.filter(Boolean))];
  for (let i = 0; i < unique.length; i += 100) {
    const { data, error } = await admin
      .from("mail_messages")
      .select("provider_message_id, provider_read, labels")
      .eq("mailbox_id", mailboxId)
      .in("provider_message_id", unique.slice(i, i + 100));
    if (error) throw error;
    for (const row of data ?? []) {
      known.set(String(row.provider_message_id), {
        read: row.provider_read === true,
        labels: Array.isArray(row.labels) ? row.labels.map(String) : [],
      });
    }
  }
  return known;
}

async function upsert(admin: Admin, mailboxId: string, records: MailRecord[], stats: Stats) {
  for (let i = 0; i < records.length; i += UPSERT_CHUNK) {
    const chunk = records.slice(i, i + UPSERT_CHUNK);
    if (!chunk.length) continue;
    const { data, error } = await admin.rpc("mail_upsert_messages_v1", {
      p_mailbox_id: mailboxId,
      p_messages: chunk,
    });
    if (error) throw error;
    const result = (data ?? {}) as Json;
    stats.new += Number(result.new ?? 0);
    stats.updated += Number(result.updated ?? 0);
  }
}

// ---------------------------------------------------------------------------
// Gmail
// ---------------------------------------------------------------------------

async function syncGmail(
  admin: Admin,
  mailbox: Mailbox,
  account: EmailAccount,
  deadline: Deadline,
) {
  const token = await accessTokenFor(admin, account);
  const state: Json = { ...(mailbox.sync_state ?? {}) };
  const stats: Stats = { new: 0, updated: 0 };

  if (typeof state.history_id !== "string" || !state.history_id) {
    // Primera vez: desde aquí lo nuevo llega por el historial; lo de antes, por
    // el relleno de abajo.
    const profile = await gmailJson(token, "/profile");
    state.history_id = String(profile.historyId ?? "");
    state.backfill_page_token = null;
    await saveState(admin, mailbox, state);
  } else {
    const changes = await gmailHistory(token, String(state.history_id), deadline);
    if (changes.expired) {
      const profile = await gmailJson(token, "/profile");
      state.history_id = String(profile.historyId ?? "");
      const recent = await gmailListIds(token, "newer_than:3d -in:chats -in:drafts", null, 500);
      await gmailStore(admin, mailbox, token, recent.ids, stats, deadline);
    } else {
      await gmailStore(admin, mailbox, token, changes.added, stats, deadline);
      await gmailRelabel(admin, mailbox, token, changes.relabeled, stats, deadline);
      if (changes.historyId) state.history_id = changes.historyId;
    }
    await saveState(admin, mailbox, state);
  }

  let backfilled = Boolean(mailbox.backfilled_at);
  while (!backfilled && !deadline.passed(15_000)) {
    const pageToken = typeof state.backfill_page_token === "string"
      ? state.backfill_page_token
      : null;
    const page = await gmailListIds(
      token,
      `newer_than:${BACKFILL_DAYS}d -in:chats -in:drafts`,
      pageToken,
      100,
    );
    const complete = await gmailStore(admin, mailbox, token, page.ids, stats, deadline);
    if (!complete) break; // se repite la misma página la próxima vez
    state.backfill_page_token = page.nextPageToken;
    backfilled = !page.nextPageToken;
    await saveState(
      admin,
      mailbox,
      state,
      backfilled ? { backfilled_at: new Date().toISOString() } : {},
    );
  }

  await updateMailbox(admin, mailbox, {
    last_synced_at: new Date().toISOString(),
    last_sync_error: null,
  });
  return { ...stats, backfilled };
}

async function gmailHistory(token: string, startHistoryId: string, deadline: Deadline) {
  const added = new Set<string>();
  const relabeled = new Map<string, string[]>();
  let pageToken: string | null = null;
  let historyId: string | null = null;
  do {
    const params = new URLSearchParams({ startHistoryId, maxResults: "500" });
    for (const type of ["messageAdded", "labelAdded", "labelRemoved"]) {
      params.append("historyTypes", type);
    }
    if (pageToken) params.set("pageToken", pageToken);
    const response = await gmailFetch(token, `/history?${params}`);
    if (response.status === 404) {
      await response.body?.cancel();
      return { expired: true, added: [] as string[], relabeled, historyId: null };
    }
    const payload = await response.json().catch(() => ({})) as Json;
    if (!response.ok) {
      throw new ProviderError(
        `Gmail ${response.status}: ${providerMessage(payload)}`,
        response.status,
      );
    }
    for (const entry of (payload.history ?? []) as Json[]) {
      for (const item of (entry.messagesAdded ?? []) as Json[]) {
        const message = (item.message ?? {}) as GmailMessage;
        if (message.id && !gmailIgnored(message.labelIds)) added.add(message.id);
      }
      for (
        const item of [
          ...((entry.labelsAdded ?? []) as Json[]),
          ...((entry.labelsRemoved ?? []) as Json[]),
        ]
      ) {
        const message = (item.message ?? {}) as GmailMessage;
        if (message.id) relabeled.set(message.id, message.labelIds ?? []);
      }
    }
    if (payload.historyId) historyId = String(payload.historyId);
    pageToken = typeof payload.nextPageToken === "string" ? payload.nextPageToken : null;
  } while (pageToken && !deadline.passed(20_000));
  // Si quedó una página sin leer, el historial se retoma desde el mismo punto.
  return { expired: false, added: [...added], relabeled, historyId: pageToken ? null : historyId };
}

async function gmailListIds(token: string, q: string, pageToken: string | null, max: number) {
  const params = new URLSearchParams({ q, maxResults: String(max) });
  if (pageToken) params.set("pageToken", pageToken);
  const payload = await gmailJson(token, `/messages?${params}`);
  const ids = ((payload.messages ?? []) as Json[]).map((m) => String(m.id ?? "")).filter(Boolean);
  return {
    ids,
    nextPageToken: typeof payload.nextPageToken === "string" ? payload.nextPageToken : null,
  };
}

/** Guarda los mensajes que faltan. Devuelve false si se acabó el tiempo a mitad. */
async function gmailStore(
  admin: Admin,
  mailbox: Mailbox,
  token: string,
  ids: string[],
  stats: Stats,
  deadline: Deadline,
): Promise<boolean> {
  const known = await knownMessages(admin, mailbox.id, ids);
  const missing = [...new Set(ids)].filter((id) => !known.has(id));
  for (let i = 0; i < missing.length; i += UPSERT_CHUNK) {
    if (deadline.passed(8_000)) return false;
    const messages = await mapLimit(
      missing.slice(i, i + UPSERT_CHUNK),
      GMAIL_CONCURRENCY,
      (id) => gmailMessage(token, id),
    );
    const records = messages
      .filter((message): message is GmailMessage =>
        message !== null && !gmailIgnored(message.labelIds)
      )
      .map(gmailMessageToRecord)
      .filter((record): record is MailRecord => record !== null);
    await upsert(admin, mailbox.id, records, stats);
  }
  return true;
}

/** Cambios de etiquetas (leído, archivado en Gmail): sólo se tocan los que cambiaron. */
async function gmailRelabel(
  admin: Admin,
  mailbox: Mailbox,
  token: string,
  relabeled: Map<string, string[]>,
  stats: Stats,
  deadline: Deadline,
) {
  if (!relabeled.size) return;
  const known = await knownMessages(admin, mailbox.id, [...relabeled.keys()]);
  const unknown: string[] = [];
  const updates: MailRecord[] = [];
  for (const [id, labels] of relabeled) {
    const stored = known.get(id);
    if (!stored) {
      if (!gmailIgnored(labels)) unknown.push(id);
      continue;
    }
    const same = stored.labels.length === labels.length &&
      stored.labels.every((label) => labels.includes(label));
    if (same) continue;
    updates.push(minimalRecord(id, labels, !labels.includes("UNREAD"), labels.includes("INBOX")));
  }
  await upsert(admin, mailbox.id, updates, stats);
  if (unknown.length) await gmailStore(admin, mailbox, token, unknown, stats, deadline);
}

function minimalRecord(id: string, labels: string[], read: boolean, inInbox: boolean): MailRecord {
  return {
    provider_message_id: id,
    provider_thread_id: null,
    provider_folder_id: null,
    rfc_message_id: null,
    in_reply_to: null,
    reference_ids: [],
    direction: labels.includes("SENT") ? "out" : "in",
    from_address: "",
    from_name: null,
    to_addresses: [],
    cc_addresses: [],
    subject: "",
    snippet: null,
    body_text: null,
    has_attachments: false,
    attachments: [],
    labels,
    provider_read: read,
    in_inbox: inInbox,
    is_bulk: false,
    received_at: new Date().toISOString(),
  };
}

async function gmailMessage(token: string, id: string): Promise<GmailMessage | null> {
  const response = await gmailFetch(token, `/messages/${encodeURIComponent(id)}?format=full`);
  if (response.status === 404) {
    await response.body?.cancel();
    return null;
  }
  const payload = await response.json().catch(() => ({})) as Json;
  if (!response.ok) {
    throw new ProviderError(
      `Gmail ${response.status}: ${providerMessage(payload)}`,
      response.status,
    );
  }
  return payload as GmailMessage;
}

async function gmailFetch(token: string, path: string): Promise<Response> {
  for (let attempt = 0;; attempt++) {
    const response = await fetch(`${GMAIL_API}${path}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (response.status === 429 || response.status >= 500) {
      const wait = retryAfterMs(response) ?? (attempt + 1) * 1500;
      await response.body?.cancel();
      if (attempt < 2 && wait <= 10_000) {
        await sleep(wait);
        continue;
      }
      throw new ProviderError(`Gmail ${response.status}`, response.status);
    }
    return response;
  }
}

async function gmailJson(token: string, path: string): Promise<Json> {
  const response = await gmailFetch(token, path);
  const payload = await response.json().catch(() => ({})) as Json;
  if (!response.ok) {
    throw new ProviderError(
      `Gmail ${response.status}: ${providerMessage(payload)}`,
      response.status,
    );
  }
  return payload;
}

// ---------------------------------------------------------------------------
// Zoho
// ---------------------------------------------------------------------------

type ZohoFolder = ZohoSyncFolder;

/** Cada cuánto se vuelve a pedir la lista de carpetas (el usuario crea nuevas). */
const ZOHO_FOLDERS_TTL_MS = 6 * 60 * 60 * 1000;

async function syncZoho(admin: Admin, mailbox: Mailbox, account: EmailAccount, deadline: Deadline) {
  const token = await accessTokenFor(admin, account);
  const accountId = (account.provider_account_id ?? "").trim();
  if (!accountId) throw new Error("La conexión de Zoho no tiene el id de su cuenta.");
  const base = `${zohoMailOrigin}/api/accounts/${encodeURIComponent(accountId)}`;
  const state: Json = { ...(mailbox.sync_state ?? {}) };
  const stats: Stats = { new: 0, updated: 0 };

  const folders = await zohoFoldersFor(token, base, state);
  await saveState(admin, mailbox, state);

  const horizon = Date.now() - BACKFILL_DAYS * 24 * 60 * 60 * 1000;
  const backfill = {
    ...((state.backfill ?? {}) as Record<string, { start: number; done: boolean }>),
  };

  for (const folder of folders) {
    if (deadline.passed(15_000)) break;
    const key = zohoBackfillKey(folder);

    // Lo nuevo: desde arriba mientras aparezcan correos que no tenemos.
    for (
      let page = 0, start = 1;
      page < 3 && !deadline.passed(15_000);
      page++, start += ZOHO_NEW_PAGE
    ) {
      const items = await zohoList(token, base, folder.id, start, ZOHO_NEW_PAGE);
      const result = await zohoStore(
        admin,
        mailbox,
        token,
        base,
        items,
        folder,
        stats,
        deadline,
        page === 0,
      );
      if (!result.complete || result.unknown === 0 || items.length < ZOHO_NEW_PAGE) break;
    }

    // Lo de antes: se retoma donde quedó, hasta el horizonte.
    const progress = backfill[key] ?? { start: 1, done: false };
    while (!progress.done && !deadline.passed(15_000)) {
      const items = await zohoList(token, base, folder.id, progress.start, ZOHO_PAGE);
      const inHorizon = items.filter((item) => Number(item.receivedTime ?? 0) >= horizon);
      const result = await zohoStore(
        admin,
        mailbox,
        token,
        base,
        inHorizon,
        folder,
        stats,
        deadline,
        false,
      );
      if (!result.complete) break;
      progress.start += items.length;
      if (items.length < ZOHO_PAGE || inHorizon.length < items.length) progress.done = true;
      backfill[key] = progress;
      state.backfill = backfill;
      await saveState(admin, mailbox, state);
    }
  }

  const done = folders.every((folder) => backfill[zohoBackfillKey(folder)]?.done === true);
  const now = new Date().toISOString();
  await updateMailbox(admin, mailbox, {
    last_synced_at: now,
    last_sync_error: null,
    ...(done && !mailbox.backfilled_at ? { backfilled_at: now } : {}),
  });
  return { ...stats, backfilled: done };
}

/** Entrada y Enviados conservan su clave de relleno de antes; las demás, su id. */
function zohoBackfillKey(folder: ZohoFolder): string {
  return folder.kind === "inbox" || folder.kind === "sent" ? folder.kind : folder.id;
}

/**
 * Las carpetas que se sincronizan. Antes eran sólo Entrada y Enviados, y lo
 * que el filtro inteligente de Zoho archiva en Notification o Newsletter —un
 * código de verificación de Meta, por ejemplo— nunca llegaba al ERP
 * (2026-11-08). La lista se guarda en el estado y se renueva cada 6 horas.
 */
async function zohoFoldersFor(token: string, base: string, state: Json): Promise<ZohoFolder[]> {
  const checkedAt = Date.parse(String(state.folders_checked_at ?? ""));
  const cached = Array.isArray(state.folder_list) ? state.folder_list as ZohoFolder[] : null;
  if (
    cached && cached.length > 0 && Number.isFinite(checkedAt) &&
    Date.now() - checkedAt < ZOHO_FOLDERS_TTL_MS
  ) {
    return cached;
  }
  const payload = await zohoJson(token, `${base}/folders`);
  const folders = zohoSyncFolders(
    (Array.isArray(payload.data) ? payload.data : []) as Json[],
  );
  if (!folders.some((folder) => folder.kind === "inbox")) {
    throw new Error("Zoho no devolvió la bandeja de entrada.");
  }
  state.folder_list = folders;
  state.folders_checked_at = new Date().toISOString();
  state.folders = {
    inbox: folders.find((folder) => folder.kind === "inbox")?.id,
    sent: folders.find((folder) => folder.kind === "sent")?.id,
  };
  return folders;
}

async function zohoList(
  token: string,
  base: string,
  folderId: string,
  start: number,
  limit: number,
) {
  const payload = await zohoJson(
    token,
    `${base}/messages/view?folderId=${encodeURIComponent(folderId)}&start=${start}&limit=${limit}`,
  );
  const root = payload.data;
  if (Array.isArray(root)) return root as ZohoListItem[];
  if (root && typeof root === "object") {
    for (const key of ["messages", "messageList"]) {
      const value = (root as Json)[key];
      if (Array.isArray(value)) return value as ZohoListItem[];
    }
  }
  return [];
}

async function zohoStore(
  admin: Admin,
  mailbox: Mailbox,
  token: string,
  base: string,
  items: ZohoListItem[],
  folder: ZohoFolder,
  stats: Stats,
  deadline: Deadline,
  refreshKnown: boolean,
): Promise<{ complete: boolean; unknown: number }> {
  const known = await knownMessages(
    admin,
    mailbox.id,
    items.map((item) => String(item.messageId ?? "")),
  );
  const unknown = items.filter((item) => item.messageId && !known.has(String(item.messageId)));

  if (refreshKnown) {
    // Leído en Zoho, o movido de carpeta (archivado, sacado de Notification):
    // sólo se escriben los que cambiaron.
    const folderLabels = zohoFolderLabels(folder.kind).join("|");
    const changed = items
      .filter((item) => {
        const stored = known.get(String(item.messageId ?? ""));
        return stored !== undefined && (
          stored.read !== parseZohoRead(item.isRead ?? item.status) ||
          stored.labels.join("|") !== folderLabels
        );
      })
      .map((item) => zohoMessageToRecord(item, folder))
      .filter((record): record is MailRecord => record !== null);
    await upsert(admin, mailbox.id, changed, stats);
  }

  for (let i = 0; i < unknown.length; i += 10) {
    if (deadline.passed(8_000)) return { complete: false, unknown: unknown.length };
    const records = await mapLimit(
      unknown.slice(i, i + 10),
      ZOHO_CONCURRENCY,
      (item) => zohoDetails(token, base, item, folder),
    );
    await upsert(
      admin,
      mailbox.id,
      records.filter((record): record is MailRecord => record !== null),
      stats,
    );
  }
  return { complete: true, unknown: unknown.length };
}

async function zohoDetails(
  token: string,
  base: string,
  item: ZohoListItem,
  folder: ZohoFolder,
): Promise<MailRecord | null> {
  const messageId = String(item.messageId ?? "").trim();
  if (!messageId) return null;
  const folderId = String(item.folderId ?? folder.id);
  const path = `${base}/folders/${encodeURIComponent(folderId)}/messages/${
    encodeURIComponent(messageId)
  }`;

  const content = await zohoOptional(token, `${path}/content`);
  const html = typeof (content?.data as Json | undefined)?.content === "string"
    ? String((content?.data as Json).content)
    : null;
  let rawHeaders: string | null = null;
  if (folder.kind !== "sent") {
    const header = await zohoOptional(token, `${path}/header`);
    const value = (header?.data as Json | undefined)?.headerContent;
    rawHeaders = typeof value === "string" ? value : null;
  }
  let attachments: MailAttachment[] = [];
  if (zohoHasAttachment(item)) {
    const info = await zohoOptional(token, `${path}/attachmentinfo?includeInline=false`);
    attachments = info ? zohoAttachments(info) : [];
  }
  return zohoMessageToRecord(item, { id: folderId, kind: folder.kind }, {
    html,
    rawHeaders,
    attachments,
  });
}

/** Un detalle que puede faltar (borrado, sin permiso): null. Un límite de uso corta la corrida. */
async function zohoOptional(token: string, url: string): Promise<Json | null> {
  try {
    return await zohoJson(token, url);
  } catch (error) {
    if (error instanceof ProviderError && (error.status === 400 || error.status === 404)) {
      return null;
    }
    throw error;
  }
}

async function zohoFetch(
  token: string,
  url: string,
  accept = "application/json",
): Promise<Response> {
  for (let attempt = 0;; attempt++) {
    const response = await fetch(url, {
      headers: { Authorization: `Zoho-oauthtoken ${token}`, Accept: accept },
    });
    if (response.status === 429 || response.status >= 500) {
      const wait = retryAfterMs(response) ?? (attempt + 1) * 2000;
      await response.body?.cancel();
      if (attempt < 2 && wait <= 10_000) {
        await sleep(wait);
        continue;
      }
      throw new ProviderError(`Zoho ${response.status}`, response.status);
    }
    return response;
  }
}

async function zohoJson(token: string, url: string): Promise<Json> {
  const response = await zohoFetch(token, url);
  const payload = await response.json().catch(() => ({})) as Json;
  if (!response.ok) {
    throw new ProviderError(
      `Zoho ${response.status}: ${providerMessage(payload)}`,
      response.status,
    );
  }
  return payload;
}

// ---------------------------------------------------------------------------
// Acciones de la app
// ---------------------------------------------------------------------------

async function handlePrepare(admin: Admin, auth: AuthContext) {
  const { error } = await admin.rpc("mail_prepare_tenant_v1", { p_tenant_id: auth.tenantId });
  if (error) throw error;
  const { data, error: listError } = await admin
    .from("mail_mailboxes")
    .select("id, provider, address, is_active, last_synced_at, last_sync_error, backfilled_at")
    .eq("tenant_id", auth.tenantId)
    .order("address");
  if (listError) throw listError;
  return { mailboxes: data ?? [] };
}

async function loadMessageForStaff(admin: Admin, auth: AuthContext, messageId: unknown) {
  if (typeof messageId !== "string" || !UUID.test(messageId)) {
    throw new HttpError(400, "Correo inválido");
  }
  const { data, error } = await admin
    .from("mail_messages")
    .select("id, tenant_id, mailbox_id, provider_message_id, provider_folder_id, attachments")
    .eq("id", messageId)
    .eq("tenant_id", auth.tenantId)
    .maybeSingle();
  if (error) throw error;
  if (!data) throw new HttpError(404, "Correo no encontrado");
  const { data: mailbox, error: mailboxError } = await admin
    .from("mail_mailboxes")
    .select(
      "id, tenant_id, provider, address, is_active, sync_state, last_synced_at, backfilled_at",
    )
    .eq("id", data.mailbox_id)
    .eq("tenant_id", auth.tenantId)
    .maybeSingle();
  if (mailboxError) throw mailboxError;
  if (!mailbox) throw new HttpError(404, "Casilla no encontrada");
  // El correo de una casilla apagada no se le muestra al equipo
  // (20261106240000): tampoco su original ni sus adjuntos.
  if (!(mailbox as Mailbox).is_active) throw new HttpError(404, "Correo no encontrado");
  const account = await loadAccountFor(admin, mailbox as Mailbox);
  if (!account) {
    throw new HttpError(409, "Nadie del equipo tiene esta casilla conectada en el ERP.");
  }
  return {
    message: data as {
      id: string;
      provider_message_id: string;
      provider_folder_id: string | null;
      attachments: MailAttachment[] | null;
    },
    mailbox: mailbox as Mailbox,
    account,
  };
}

async function handleBody(admin: Admin, auth: AuthContext, body: Json) {
  const { message, mailbox, account } = await loadMessageForStaff(admin, auth, body.message_id);
  const token = await accessTokenFor(admin, account);
  if (mailbox.provider === "gmail") {
    const full = await gmailMessage(token, message.provider_message_id);
    if (!full) throw new HttpError(404, "El correo ya no está en Gmail.");
    const { text, html } = gmailBodies(full);
    return { html, text };
  }
  const base = zohoBase(account);
  const folderId = message.provider_folder_id ?? "";
  const content = await zohoOptional(
    token,
    `${base}/folders/${encodeURIComponent(folderId)}/messages/${
      encodeURIComponent(message.provider_message_id)
    }/content`,
  );
  const html = typeof (content?.data as Json | undefined)?.content === "string"
    ? String((content?.data as Json).content)
    : null;
  if (html === null) throw new HttpError(404, "El correo ya no está en Zoho.");
  return { html, text: htmlToText(html) };
}

async function handleAttachment(admin: Admin, auth: AuthContext, body: Json) {
  const { message, mailbox, account } = await loadMessageForStaff(admin, auth, body.message_id);
  const wanted = String(body.attachment_id ?? body.part_id ?? "").trim();
  const attachments = Array.isArray(message.attachments) ? message.attachments : [];
  const attachment = attachments.find((item) =>
    item.attachment_id === wanted || item.part_id === wanted
  );
  if (!wanted || !attachment) throw new HttpError(404, "Adjunto no encontrado");
  if (attachment.size > MAX_ATTACHMENT_BYTES) {
    throw new HttpError(413, "El adjunto es demasiado grande para abrirlo aquí.");
  }
  const token = await accessTokenFor(admin, account);

  let base64: string | null = null;
  if (mailbox.provider === "gmail") {
    base64 = await gmailAttachmentData(token, message.provider_message_id, attachment);
  } else {
    const base = zohoBase(account);
    const url = `${base}/folders/${encodeURIComponent(message.provider_folder_id ?? "")}/messages/${
      encodeURIComponent(message.provider_message_id)
    }/attachments/${encodeURIComponent(attachment.attachment_id ?? "")}`;
    const response = await zohoFetch(token, url, "*/*");
    if (!response.ok) {
      await response.body?.cancel();
      throw new HttpError(response.status === 404 ? 404 : 502, "Zoho no entregó el adjunto.");
    }
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.length > MAX_ATTACHMENT_BYTES) {
      throw new HttpError(413, "El adjunto es demasiado grande para abrirlo aquí.");
    }
    base64 = bytesToBase64(bytes);
  }
  if (base64 === null) throw new HttpError(404, "Adjunto no encontrado");
  return {
    filename: attachment.filename,
    mime_type: attachment.mime_type,
    size: attachment.size,
    data_base64: base64,
  };
}

async function gmailAttachmentData(
  token: string,
  messageId: string,
  attachment: MailAttachment,
): Promise<string | null> {
  const byId = async (attachmentId: string) => {
    const response = await gmailFetch(
      token,
      `/messages/${encodeURIComponent(messageId)}/attachments/${encodeURIComponent(attachmentId)}`,
    );
    if (!response.ok) {
      await response.body?.cancel();
      return null;
    }
    const payload = await response.json().catch(() => ({})) as Json;
    return typeof payload.data === "string" ? base64UrlToBase64(payload.data) : null;
  };
  if (attachment.attachment_id) {
    const data = await byId(attachment.attachment_id);
    if (data !== null) return data;
  }
  // Gmail puede renovar el id del adjunto: se busca la parte de nuevo.
  const full = await gmailMessage(token, messageId);
  if (!full) return null;
  if (attachment.part_id) {
    const inline = gmailPartData(full, attachment.part_id);
    if (inline) return base64UrlToBase64(inline);
    const fresh = gmailAttachments(full).find((item) => item.part_id === attachment.part_id);
    if (fresh?.attachment_id) return await byId(fresh.attachment_id);
  }
  return null;
}

function zohoBase(account: EmailAccount) {
  const accountId = (account.provider_account_id ?? "").trim();
  if (!accountId) throw new HttpError(409, "La conexión de Zoho no tiene el id de su cuenta.");
  return `${zohoMailOrigin}/api/accounts/${encodeURIComponent(accountId)}`;
}

// ---------------------------------------------------------------------------
// Llaves de acceso (se guardan donde ya vivían: email_accounts)
// ---------------------------------------------------------------------------

async function accessTokenFor(admin: Admin, account: EmailAccount): Promise<string> {
  const current = (account.access_token ?? "").trim();
  const expiresAt = account.token_expires_at ? Date.parse(account.token_expires_at) : 0;
  if (current && expiresAt > Date.now() + 5 * 60 * 1000) return current;

  const refreshToken = (account.refresh_token ?? "").trim();
  if (!refreshToken) {
    throw new Error("La conexión no tiene cómo renovarse; hay que conectarla de nuevo.");
  }
  const isGmail = account.provider === "gmail";
  const response = await fetch(
    isGmail ? "https://oauth2.googleapis.com/token" : `${zohoAccountsOrigin}/oauth/v2/token`,
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: env(isGmail ? "GMAIL_CLIENT_ID" : "ZOHO_CLIENT_ID"),
        client_secret: env(isGmail ? "GMAIL_CLIENT_SECRET" : "ZOHO_CLIENT_SECRET"),
        refresh_token: refreshToken,
        grant_type: "refresh_token",
      }),
    },
  );
  const payload = await response.json().catch(() => ({})) as Json;
  const accessToken = String(payload.access_token ?? "").trim();
  if (!response.ok || payload.error || !accessToken) {
    throw new Error(
      `No se pudo renovar la conexión de ${isGmail ? "Gmail" : "Zoho"}: ${
        String(payload.error ?? response.status)
      }`,
    );
  }
  const expires = new Date(Date.now() + Number(payload.expires_in || 3600) * 1000).toISOString();
  const now = new Date().toISOString();
  const { error } = await admin
    .from("email_accounts")
    .update({
      access_token: accessToken,
      token_type: String(payload.token_type ?? "") || account.token_type,
      scope: String(payload.scope ?? "") || account.scope,
      token_expires_at: expires,
      last_token_refresh_at: now,
      last_error: null,
      updated_at: now,
    })
    .eq("id", account.id)
    .eq("tenant_id", account.tenant_id);
  if (error) throw error;
  account.access_token = accessToken;
  account.token_expires_at = expires;
  return accessToken;
}

// ---------------------------------------------------------------------------
// Utilidades
// ---------------------------------------------------------------------------

async function requireStaff(req: Request, admin: Admin): Promise<AuthContext> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) throw new Error("Unauthorized");
  const userClient = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await userClient.auth.getUser();
  if (error || !data.user) throw new Error("Unauthorized");
  const { data: profile, error: profileError } = await admin
    .from("user_profiles")
    .select("tenant_id, role, is_active")
    .eq("user_id", data.user.id)
    .maybeSingle();
  if (profileError || !profile?.tenant_id || profile.is_active === false) {
    throw new Error("Unauthorized");
  }
  return {
    userId: data.user.id,
    tenantId: String(profile.tenant_id),
    role: String(profile.role ?? ""),
  };
}

async function mapLimit<T, R>(
  items: T[],
  limit: number,
  task: (item: T) => Promise<R>,
): Promise<R[]> {
  const results = new Array<R>(items.length);
  let next = 0;
  const worker = async () => {
    while (next < items.length) {
      const index = next++;
      results[index] = await task(items[index]);
    }
  };
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return results;
}

function retryAfterMs(response: Response): number | null {
  const header = response.headers.get("Retry-After");
  if (!header) return null;
  const seconds = Number(header);
  if (Number.isFinite(seconds)) return Math.max(0, seconds * 1000);
  const at = Date.parse(header);
  return Number.isFinite(at) ? Math.max(0, at - Date.now()) : null;
}

function providerMessage(payload: Json): string {
  const error = payload.error;
  if (error && typeof error === "object") {
    return String((error as Json).message ?? "").slice(0, 200);
  }
  const data = payload.data;
  if (data && typeof data === "object") {
    return String((data as Json).moreInfo ?? (data as Json).errorCode ?? "").slice(0, 200);
  }
  return String(error ?? "").slice(0, 200);
}

function safeMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (error && typeof error === "object" && "message" in error) {
    return String((error as Json).message);
  }
  return String(error);
}

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function env(name: string): string {
  const value = Deno.env.get(name) ?? "";
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

function adminClient() {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
