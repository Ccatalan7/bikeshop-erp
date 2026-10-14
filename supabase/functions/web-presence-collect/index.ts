// Presencia en internet: lee Search Console y Google Analytics con la cuenta
// de servicio de Viñabike y guarda las cifras por día (20261014150000).
//
// Acciones:
//   collect — búsquedas por día, consultas y páginas, sitemap, un lote de
//             inspecciones, Analytics y los cambios del wiki. pg_cron, cada día.
//   inspect — sólo un lote de inspecciones de direcciones del sitemap.
//             pg_cron, cada dos horas (bajo el tope de 2.000 al día).
// La llama pg_cron con su secreto (x-web-presence-secret) para todas las
// tiendas, o un editor del ERP («Actualizar») para la suya.

// @ts-ignore - Deno imports
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
// @ts-ignore - Deno imports
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { serviceAccountAccessToken } from "../_shared/google_service_account.ts";
import {
  addDays,
  dayWindows,
  ga4Day,
  indexSummary,
  isoDay,
  parseSitemap,
  parseWikiLog,
  storeHost,
} from "../_shared/web_presence.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

type Tenant = {
  tenantId: string;
  host: string;
  gscSite: string;
  sitemapUrl: string;
  ga4PropertyId: string | null;
};

type Detail = Record<string, unknown> & { errors: string[] };

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-web-presence-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const scopes = [
  "https://www.googleapis.com/auth/webmasters.readonly",
  "https://www.googleapis.com/auth/analytics.readonly",
];

// Search Console guarda 16 meses; Analytics, lo que tenga la propiedad.
const searchHistoryDays = 480;
const trafficHistoryDays = 400;
// Google corrige los últimos días: se vuelven a pedir.
const refetchDays = 4;
const budgetMs = 120_000;
const changelogUrl =
  "https://raw.githubusercontent.com/Ccatalan7/bikeshop-erp/main/docs/wiki/sitio-web/log.md";
const changelogHost = "vinabike.cl";

// @ts-ignore - Deno serve
serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);

  const startedAt = Date.now();
  const db = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
  const body = await req.json().catch(() => ({}));
  const action = body?.action === "inspect" ? "inspect" : "collect";

  let tenantIds: string[] | null;
  try {
    tenantIds = await authorize(req, db, body?.tenantId);
  } catch (error) {
    return json({ error: (error as Error).message }, 403);
  }

  const email = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_EMAIL") ?? "";
  const privateKey = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY") ?? "";
  if (!email || !privateKey) return json({ error: "Falta la cuenta de servicio de Google" }, 500);

  let token: string;
  try {
    token = await serviceAccountAccessToken({ email, privateKey, scopes });
  } catch (error) {
    return json({ error: (error as Error).message }, 502);
  }

  const tenants = await loadTenants(db, tenantIds);
  const work = async () => {
    for (const tenant of tenants) await runTenant(db, token, tenant, action, startedAt);
  };
  // pg_net corta a los 5 s y la pantalla no espera dos minutos: se responde
  // al tiro y cada recolección deja su fila en web_presence_runs.
  const runtime = (globalThis as { EdgeRuntime?: { waitUntil: (work: Promise<unknown>) => void } })
    .EdgeRuntime;
  if (runtime) {
    runtime.waitUntil(work());
    return json({ accepted: true, action, tenants: tenants.map((t) => t.host) }, 202);
  }
  await work();
  return json({ accepted: true, action, tenants: tenants.map((t) => t.host) });
});

async function authorize(req: Request, db: Db, tenantId?: string): Promise<string[] | null> {
  const secret = Deno.env.get("WEB_PRESENCE_COLLECT_SECRET") ?? "";
  const given = req.headers.get("x-web-presence-secret") ?? "";
  if (secret && given && timingSafeEqual(secret, given)) return null; // todas las tiendas

  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) throw new Error("No autorizado");
  const { data: userData, error: userError } = await db.auth.getUser(jwt);
  if (userError || !userData?.user) throw new Error("Sesión no válida");

  const userClient = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: `Bearer ${jwt}` } } },
  );
  const { data: ownTenant } = await userClient.rpc("user_tenant_id");
  const target = typeof tenantId === "string" && tenantId ? tenantId : ownTenant;
  const { error } = await userClient.rpc("catalog_assert_editor_v1", { p_tenant_id: target });
  if (error) throw new Error("Tu cuenta no puede actualizar estas cifras");
  return [String(target)];
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function loadTenants(db: Db, only: string[] | null): Promise<Tenant[]> {
  let query = db.from("website_settings").select("tenant_id, value").eq("key", "store_url");
  if (only) query = query.in("tenant_id", only);
  const { data: urls } = await query;
  const { data: settings } = await db.from("web_presence_settings").select("*");
  const byTenant = new Map((settings ?? []).map((s: Record<string, unknown>) => [s.tenant_id, s]));

  const tenants: Tenant[] = [];
  for (const row of urls ?? []) {
    const host = storeHost(String(row.value ?? ""));
    if (!host) continue;
    const s = byTenant.get(row.tenant_id) as Record<string, string | boolean> | undefined;
    if (s && s.enabled === false) continue;
    tenants.push({
      tenantId: row.tenant_id,
      host,
      gscSite: (s?.gsc_site as string) || `sc-domain:${host}`,
      sitemapUrl: (s?.sitemap_url as string) || `https://${host}/sitemap.xml`,
      ga4PropertyId: (s?.ga4_property_id as string) || null,
    });
  }
  return tenants;
}

async function runTenant(db: Db, token: string, tenant: Tenant, action: string, startedAt: number) {
  const { data: run } = await db.from("web_presence_runs")
    .insert({ tenant_id: tenant.tenantId, task: action })
    .select("id")
    .single();
  const detail: Detail = { errors: [] };
  const left = () => budgetMs - (Date.now() - startedAt);

  const step = async (name: string, fn: () => Promise<unknown>, minLeft = 8_000) => {
    if (left() < minLeft) {
      detail.errors.push(`${name}: sin tiempo, sigue en la próxima`);
      return;
    }
    try {
      detail[name] = await fn();
    } catch (error) {
      detail.errors.push(`${name}: ${(error as Error).message}`.slice(0, 300));
    }
  };

  if (action === "collect") {
    await step("search_daily", () => collectSearchDaily(db, token, tenant));
    await step("search_terms", () => collectSearchTerms(db, token, tenant, left));
    await step("sitemap", () => refreshSitemap(db, token, tenant));
    await step("traffic", () => collectTraffic(db, token, tenant));
    await step("notes", () => collectNotes(db, tenant));
  }
  await step("inspect", () => inspectBatch(db, token, tenant, action === "inspect" ? 80 : 20, left));
  // La foto de indexación es lo que la pantalla muestra: siempre se guarda.
  await step("index", () => snapshotIndex(db, tenant), 2_000);

  const status = detail.errors.length === 0
    ? "ok"
    : Object.keys(detail).length > 1
    ? "partial"
    : "error";
  if (run?.id) {
    await db.from("web_presence_runs")
      .update({ finished_at: new Date().toISOString(), status, detail })
      .eq("id", run.id);
  }
  return { tenant: tenant.host, status, detail };
}

async function google(token: string, url: string, init?: RequestInit) {
  const response = await fetch(url, {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      ...(init?.headers ?? {}),
    },
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message = payload?.error?.message ?? response.statusText;
    const error = new Error(`${response.status} ${String(message).slice(0, 200)}`);
    (error as Error & { status?: number }).status = response.status;
    throw error;
  }
  return payload;
}

function searchUrl(site: string) {
  return `https://searchconsole.googleapis.com/webmasters/v3/sites/${
    encodeURIComponent(site)
  }/searchAnalytics/query`;
}

async function lastDay(db: Db, table: string, tenantId: string, filter?: [string, string]) {
  let query = db.from(table).select("day").eq("tenant_id", tenantId);
  if (filter) query = query.eq(filter[0], filter[1]);
  const { data } = await query.order("day", { ascending: false }).limit(1);
  return data?.[0]?.day as string | undefined;
}

async function upsertChunks(db: Db, table: string, rows: unknown[], onConflict: string) {
  for (let i = 0; i < rows.length; i += 1000) {
    const { error } = await db.from(table).upsert(rows.slice(i, i + 1000), { onConflict });
    if (error) throw new Error(`${table}: ${error.message}`);
  }
}

async function collectSearchDaily(db: Db, token: string, tenant: Tenant) {
  const today = isoDay(new Date());
  const last = await lastDay(db, "web_presence_search_daily", tenant.tenantId);
  const start = last ? addDays(last, -refetchDays) : addDays(today, -searchHistoryDays);
  const payload = await google(token, searchUrl(tenant.gscSite), {
    method: "POST",
    body: JSON.stringify({
      startDate: start,
      endDate: today,
      dimensions: ["date"],
      type: "web",
      dataState: "all",
      rowLimit: 25000,
    }),
  });
  const rows = (payload.rows ?? []).map((r: Record<string, unknown>) => ({
    tenant_id: tenant.tenantId,
    day: (r.keys as string[])[0],
    clicks: Math.round(Number(r.clicks ?? 0)),
    impressions: Math.round(Number(r.impressions ?? 0)),
    position: Number(r.position ?? 0) || null,
  }));
  await upsertChunks(db, "web_presence_search_daily", rows, "tenant_id,day");
  return { from: start, days: rows.length };
}

async function collectSearchTerms(db: Db, token: string, tenant: Tenant, left: () => number) {
  const today = isoDay(new Date());
  const result: Record<string, unknown> = {};
  for (const kind of ["query", "page"] as const) {
    const last = await lastDay(db, "web_presence_search_terms", tenant.tenantId, ["kind", kind]);
    const start = last ? addDays(last, -refetchDays) : addDays(today, -searchHistoryDays);
    let saved = 0;
    let reached = start;
    for (const [from, to] of dayWindows(start, today, 60)) {
      if (left() < 15_000) break;
      let startRow = 0;
      for (;;) {
        const payload = await google(token, searchUrl(tenant.gscSite), {
          method: "POST",
          body: JSON.stringify({
            startDate: from,
            endDate: to,
            dimensions: ["date", kind],
            type: "web",
            dataState: "all",
            rowLimit: 25000,
            startRow,
          }),
        });
        const rows = (payload.rows ?? []).map((r: Record<string, unknown>) => ({
          tenant_id: tenant.tenantId,
          day: (r.keys as string[])[0],
          kind,
          term: String((r.keys as string[])[1]).slice(0, 500),
          clicks: Math.round(Number(r.clicks ?? 0)),
          impressions: Math.round(Number(r.impressions ?? 0)),
          position: Number(r.position ?? 0) || null,
        }));
        await upsertChunks(db, "web_presence_search_terms", rows, "tenant_id,kind,day,term");
        saved += rows.length;
        if (rows.length < 25000) break;
        startRow += 25000;
      }
      reached = to;
    }
    result[kind] = { from: start, until: reached, rows: saved };
  }
  return result;
}

async function refreshSitemap(db: Db, token: string, tenant: Tenant) {
  const seenAt = new Date().toISOString();
  const urls = new Set<string>();
  const pending = [tenant.sitemapUrl];
  for (let read = 0; pending.length && read < 20; read++) {
    const response = await fetch(pending.shift()!, { headers: { "User-Agent": "VinabikePresencia/1" } });
    if (!response.ok) throw new Error(`sitemap ${response.status}`);
    const parsed = parseSitemap(await response.text());
    parsed.urls.forEach((u) => urls.add(u));
    pending.push(...parsed.sitemaps);
  }
  await upsertChunks(
    db,
    "web_presence_urls",
    [...urls].map((url) => ({
      tenant_id: tenant.tenantId,
      url,
      in_sitemap: true,
      last_seen_at: seenAt,
    })),
    "tenant_id,url",
  );
  await db.from("web_presence_urls")
    .update({ in_sitemap: false })
    .eq("tenant_id", tenant.tenantId)
    .eq("in_sitemap", true)
    .lt("last_seen_at", seenAt);

  // Lo que dice Search Console del sitemap enviado.
  let submitted: number | null = null;
  let lastRead: string | null = null;
  try {
    const sitemaps = await google(
      token,
      `https://searchconsole.googleapis.com/webmasters/v3/sites/${
        encodeURIComponent(tenant.gscSite)
      }/sitemaps`,
    );
    const ours = (sitemaps.sitemap ?? []).find((s: Record<string, unknown>) =>
      s.path === tenant.sitemapUrl
    );
    if (ours) {
      lastRead = ours.lastDownloaded ?? null;
      // Sólo páginas: el sitemap también declara las imágenes de cada ficha.
      submitted = (ours.contents ?? [])
        .filter((c: Record<string, unknown>) => c.type === "web")
        .reduce((sum: number, c: Record<string, unknown>) => sum + Number(c.submitted ?? 0), 0);
    }
  } catch (_) {
    // El sitemap propio ya quedó leído; esto es complemento.
  }
  await db.from("web_presence_index_daily").upsert({
    tenant_id: tenant.tenantId,
    day: isoDay(new Date()),
    sitemap_urls: urls.size,
    sitemap_submitted: submitted,
    sitemap_last_read: lastRead,
  }, { onConflict: "tenant_id,day" });
  return { urls: urls.size, submitted, lastRead };
}

async function inspectBatch(db: Db, token: string, tenant: Tenant, size: number, left: () => number) {
  const { data: due } = await db.from("web_presence_urls")
    .select("url")
    .eq("tenant_id", tenant.tenantId)
    .eq("in_sitemap", true)
    .order("inspected_at", { ascending: true, nullsFirst: true })
    .limit(size);
  let inspected = 0;
  let quota = false;
  const queue = [...(due ?? [])];
  const worker = async () => {
    // Una inspección tarda ~7 s: se deja tiempo para la foto del final.
    while (queue.length && !quota && left() > 25_000) {
      const { url } = queue.shift()!;
      try {
        const payload = await google(
          token,
          "https://searchconsole.googleapis.com/v1/urlInspection/index:inspect",
          {
            method: "POST",
            body: JSON.stringify({ inspectionUrl: url, siteUrl: tenant.gscSite, languageCode: "en-US" }),
          },
        );
        const s = payload?.inspectionResult?.indexStatusResult ?? {};
        await db.from("web_presence_urls").update({
          inspected_at: new Date().toISOString(),
          verdict: s.verdict ?? null,
          coverage_state: s.coverageState ?? null,
          indexing_state: s.indexingState ?? null,
          page_fetch_state: s.pageFetchState ?? null,
          robots_state: s.robotsTxtState ?? null,
          last_crawl_at: s.lastCrawlTime ?? null,
          google_canonical: s.googleCanonical ?? null,
          user_canonical: s.userCanonical ?? null,
          inspect_error: null,
        }).eq("tenant_id", tenant.tenantId).eq("url", url);
        inspected++;
      } catch (error) {
        const status = (error as Error & { status?: number }).status;
        if (status === 429) {
          quota = true;
          return;
        }
        await db.from("web_presence_urls").update({
          inspected_at: new Date().toISOString(),
          inspect_error: (error as Error).message.slice(0, 200),
        }).eq("tenant_id", tenant.tenantId).eq("url", url);
      }
    }
  };
  await Promise.all(Array.from({ length: 6 }, worker));
  return { inspected, quotaReached: quota };
}

async function snapshotIndex(db: Db, tenant: Tenant) {
  const rows: { verdict: string | null; coverage_state: string | null; inspected_at: string | null }[] =
    [];
  for (let from = 0;; from += 1000) {
    const { data } = await db.from("web_presence_urls")
      .select("verdict, coverage_state, inspected_at")
      .eq("tenant_id", tenant.tenantId)
      .eq("in_sitemap", true)
      .range(from, from + 999);
    rows.push(...(data ?? []));
    if (!data || data.length < 1000) break;
  }
  const summary = indexSummary(rows);
  await db.from("web_presence_index_daily").upsert({
    tenant_id: tenant.tenantId,
    day: isoDay(new Date()),
    sitemap_urls: summary.sitemapUrls,
    inspected: summary.inspected,
    indexed: summary.indexed,
    by_state: summary.byState,
  }, { onConflict: "tenant_id,day" });
  return summary;
}

async function collectTraffic(db: Db, token: string, tenant: Tenant) {
  if (!tenant.ga4PropertyId) return { skipped: "sin propiedad de Analytics configurada" };
  const today = isoDay(new Date());
  const last = await lastDay(db, "web_presence_traffic_daily", tenant.tenantId);
  const start = last ? addDays(last, -3) : addDays(today, -trafficHistoryDays);
  const report = (body: unknown) =>
    google(
      token,
      `https://analyticsdata.googleapis.com/v1beta/properties/${tenant.ga4PropertyId}:runReport`,
      { method: "POST", body: JSON.stringify(body) },
    );
  const hostFilter = {
    filter: {
      fieldName: "hostName",
      inListFilter: { values: [tenant.host, `www.${tenant.host}`] },
    },
  };
  const chileFilter = {
    filter: { fieldName: "country", stringFilter: { matchType: "EXACT", value: "Chile" } },
  };
  const events = [
    "view_item_list",
    "view_item",
    "add_to_cart",
    "begin_checkout",
    "purchase",
    "contact",
  ];
  const out: Record<string, number> = {};
  for (const scope of ["sitio", "chile"] as const) {
    const dimensionFilter = scope === "sitio"
      ? hostFilter
      : { andGroup: { expressions: [hostFilter, chileFilter] } };
    let traffic;
    try {
      traffic = await report({
        dateRanges: [{ startDate: start, endDate: today }],
        dimensions: [{ name: "date" }, { name: "sessionDefaultChannelGroup" }],
        metrics: [
          { name: "sessions" },
          { name: "engagedSessions" },
          { name: "totalUsers" },
          { name: "keyEvents" },
        ],
        dimensionFilter,
        limit: 100000,
      });
    } catch (error) {
      // La cuenta de servicio entra a Analytics sólo si el dueño la agrega
      // como lector de la propiedad; mientras no, la pantalla lo dice.
      if ((error as Error & { status?: number }).status === 403) {
        return {
          noAccess: true,
          property: tenant.ga4PropertyId,
          account: Deno.env.get("GOOGLE_SERVICE_ACCOUNT_EMAIL") ?? null,
        };
      }
      throw error;
    }
    const trafficRows = (traffic.rows ?? []).map((r: Record<string, Record<string, string>[]>) => ({
      tenant_id: tenant.tenantId,
      day: ga4Day(r.dimensionValues[0].value),
      scope,
      channel: r.dimensionValues[1].value || "(sin canal)",
      sessions: Number(r.metricValues[0].value),
      engaged_sessions: Number(r.metricValues[1].value),
      users: Number(r.metricValues[2].value),
      key_events: Number(r.metricValues[3].value),
    }));
    await upsertChunks(db, "web_presence_traffic_daily", trafficRows, "tenant_id,scope,day,channel");

    const eventReport = await report({
      dateRanges: [{ startDate: start, endDate: today }],
      dimensions: [{ name: "date" }, { name: "eventName" }],
      metrics: [{ name: "eventCount" }],
      dimensionFilter: {
        andGroup: {
          expressions: [
            ...(scope === "sitio" ? [hostFilter] : [hostFilter, chileFilter]),
            { filter: { fieldName: "eventName", inListFilter: { values: events } } },
          ],
        },
      },
      limit: 100000,
    });
    const eventRows = (eventReport.rows ?? []).map((r: Record<string, Record<string, string>[]>) => ({
      tenant_id: tenant.tenantId,
      day: ga4Day(r.dimensionValues[0].value),
      scope,
      event_name: r.dimensionValues[1].value,
      event_count: Number(r.metricValues[0].value),
    }));
    await upsertChunks(db, "web_presence_events_daily", eventRows, "tenant_id,scope,day,event_name");
    out[scope] = trafficRows.length;
  }
  return { from: start, rows: out };
}

async function collectNotes(db: Db, tenant: Tenant) {
  if (tenant.host !== changelogHost) return { skipped: "sin registro de cambios" };
  const response = await fetch(changelogUrl);
  if (!response.ok) throw new Error(`registro del wiki ${response.status}`);
  const notes = await parseWikiLog(await response.text());
  await upsertChunks(
    db,
    "web_presence_notes",
    notes.map((n) => ({
      tenant_id: tenant.tenantId,
      kind: n.kind,
      day: n.day,
      title: n.title,
      body: n.body,
      source: "wiki",
      source_key: n.sourceKey,
    })),
    "tenant_id,source_key",
  );
  return { notes: notes.length };
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
