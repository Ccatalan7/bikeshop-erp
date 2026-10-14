// Pure pieces of the web presence collector (web-presence-collect): what a
// sitemap lists, what the site wiki says we changed, and how Google's rows
// become ours. Kept apart so they are tested without network.

export type SitemapRead = { urls: string[]; sitemaps: string[] };

/** The <loc> entries of a sitemap or of a sitemap index. */
export function parseSitemap(xml: string): SitemapRead {
  const isIndex = /<sitemapindex[\s>]/i.test(xml);
  const locs = [...xml.matchAll(/<loc>\s*([^<\s]+)\s*<\/loc>/gi)].map((m) => decodeXml(m[1]));
  return isIndex ? { urls: [], sitemaps: locs } : { urls: locs, sitemaps: [] };
}

function decodeXml(value: string): string {
  return value
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'");
}

export type ChangeNote = {
  day: string;
  kind: "cambio" | "analisis";
  operation: string;
  title: string;
  body: string;
  sourceKey: string;
};

/**
 * Entries of docs/wiki/sitio-web/log.md: «- 2026-10-11 — corrección — text»,
 * possibly over several lines. A «corrección» or «ingesta» is something we
 * changed; a «consulta archivada» is an analysis; a «revisión» (lint) is
 * neither and is left out.
 */
export async function parseWikiLog(markdown: string): Promise<ChangeNote[]> {
  const entries: { day: string; operation: string; text: string }[] = [];
  let current: { day: string; operation: string; text: string } | null = null;
  for (const line of markdown.split("\n")) {
    const start = line.match(/^- (\d{4}-\d{2}-\d{2}) — ([^—]+?) — (.*)$/);
    if (start) {
      if (current) entries.push(current);
      current = { day: start[1], operation: start[2].trim().toLowerCase(), text: start[3] };
      continue;
    }
    if (current && /^\s{2,}\S/.test(line)) {
      current.text += " " + line.trim();
    } else if (current) {
      entries.push(current);
      current = null;
    }
  }
  if (current) entries.push(current);

  const notes: ChangeNote[] = [];
  for (const entry of entries) {
    const kind = entry.operation.startsWith("corrección") || entry.operation.startsWith("ingesta")
      ? "cambio"
      : entry.operation.startsWith("consulta")
      ? "analisis"
      : null;
    if (!kind) continue;
    const body = stripMarkdown(entry.text);
    notes.push({
      day: entry.day,
      kind,
      operation: entry.operation,
      title: firstSentence(body),
      body,
      sourceKey: `wiki:${entry.day}:${await sha1Hex(body)}`,
    });
  }
  return notes;
}

export function stripMarkdown(text: string): string {
  return text
    .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/\*\*([^*]+)\*\*/g, "$1")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * A short title: the text after the page links («catalogo y datos: …»), up
 * to the first sentence end, at most 140 characters.
 */
export function firstSentence(body: string): string {
  const afterLinks = body.includes(": ") ? body.slice(body.indexOf(": ") + 2) : body;
  const sentence = afterLinks.split(/(?<=[.;])\s/)[0] ?? afterLinks;
  const clean = sentence.replace(/[.;]$/, "").trim();
  const capitalized = clean.charAt(0).toUpperCase() + clean.slice(1);
  return capitalized.length > 140 ? capitalized.slice(0, 139).trimEnd() + "…" : capitalized;
}

async function sha1Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-1", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("").slice(
    0,
    16,
  );
}

/** «https://www.vinabike.cl/» → «vinabike.cl». */
export function storeHost(storeUrl: string): string | null {
  try {
    return new URL(storeUrl).hostname.replace(/^www\./, "").toLowerCase() || null;
  } catch {
    return null;
  }
}

export function isoDay(date: Date): string {
  return date.toISOString().slice(0, 10);
}

export function addDays(day: string, days: number): string {
  const date = new Date(`${day}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return isoDay(date);
}

/** Consecutive windows of at most `size` days from `start` to `end`. */
export function dayWindows(start: string, end: string, size: number): [string, string][] {
  const windows: [string, string][] = [];
  let from = start;
  while (from <= end) {
    const to = addDays(from, size - 1) < end ? addDays(from, size - 1) : end;
    windows.push([from, to]);
    from = addDays(to, 1);
  }
  return windows;
}

/** GA4 «20261011» → «2026-10-11». */
export function ga4Day(value: string): string {
  return `${value.slice(0, 4)}-${value.slice(4, 6)}-${value.slice(6, 8)}`;
}

/** The sitemap's state of indexation from the per-URL inspections. */
export function indexSummary(
  rows: { verdict: string | null; coverage_state: string | null; inspected_at: string | null }[],
): { sitemapUrls: number; inspected: number; indexed: number; byState: Record<string, number> } {
  const byState: Record<string, number> = {};
  let inspected = 0;
  let indexed = 0;
  for (const row of rows) {
    if (!row.inspected_at) continue;
    inspected++;
    if (row.verdict === "PASS") indexed++;
    const state = row.coverage_state || "Sin dato";
    byState[state] = (byState[state] ?? 0) + 1;
  }
  return { sitemapUrls: rows.length, inspected, indexed, byState };
}
