import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  dayWindows,
  firstSentence,
  ga4Day,
  indexSummary,
  parseSitemap,
  parseWikiLog,
  storeHost,
} from "./web_presence.ts";

Deno.test("a sitemap lists its pages and an index its sitemaps", () => {
  assertEquals(
    parseSitemap(
      `<?xml version="1.0"?><urlset><url><loc>https://vinabike.cl/</loc></url>` +
        `<url><loc> https://vinabike.cl/productos?a=1&amp;b=2 </loc></url></urlset>`,
    ),
    { urls: ["https://vinabike.cl/", "https://vinabike.cl/productos?a=1&b=2"], sitemaps: [] },
  );
  assertEquals(
    parseSitemap(`<sitemapindex><sitemap><loc>https://vinabike.cl/s1.xml</loc></sitemap></sitemapindex>`),
    { urls: [], sitemaps: ["https://vinabike.cl/s1.xml"] },
  );
});

Deno.test("the site wiki log becomes changes and analyses", async () => {
  const notes = await parseWikiLog(`# Registro

- 2026-10-11 — consulta archivada — [datos](paginas/datos.md) y
  [catalogo](paginas/catalogo.md): aviso de Search Console «No global
  identifier» en 7 fichas.
- 2026-10-10 — corrección — [catalogo](paginas/catalogo-y-fichas.md): un
  destacado nuevo pasa por la regla de venta; antes se guardaba otro.
- 2026-10-09 — revisión — lint sin errores.
`);
  assertEquals(notes.length, 2);
  assertEquals(notes[0].kind, "analisis");
  assertEquals(notes[0].day, "2026-10-11");
  assertEquals(notes[0].title, "Aviso de Search Console «No global identifier» en 7 fichas");
  assertEquals(notes[1].kind, "cambio");
  assertEquals(notes[1].title, "Un destacado nuevo pasa por la regla de venta");
  assertEquals(notes[1].body.includes("](paginas"), false);
  assertEquals(notes[1].sourceKey.startsWith("wiki:2026-10-10:"), true);
  // The same text gives the same key: a re-run does not duplicate it.
  assertEquals((await parseWikiLog(`- 2026-10-10 — corrección — [catalogo](x.md): un
  destacado nuevo pasa por la regla de venta; antes se guardaba otro.`))[0].sourceKey, notes[1].sourceKey);
});

Deno.test("a long title is cut at 140 characters", () => {
  assertEquals(firstSentence("x".repeat(200)).length, 140);
});

Deno.test("dates, hosts and windows", () => {
  assertEquals(storeHost("https://www.vinabike.cl/"), "vinabike.cl");
  assertEquals(storeHost("no es url"), null);
  assertEquals(ga4Day("20261011"), "2026-10-11");
  assertEquals(dayWindows("2026-01-01", "2026-03-05", 30), [
    ["2026-01-01", "2026-01-30"],
    ["2026-01-31", "2026-03-01"],
    ["2026-03-02", "2026-03-05"],
  ]);
});

Deno.test("indexation counts only what Google inspected", () => {
  assertEquals(
    indexSummary([
      { verdict: "PASS", coverage_state: "Submitted and indexed", inspected_at: "2026-10-14" },
      { verdict: "NEUTRAL", coverage_state: "Discovered - currently not indexed", inspected_at: "2026-10-14" },
      { verdict: null, coverage_state: null, inspected_at: null },
    ]),
    {
      sitemapUrls: 3,
      inspected: 2,
      indexed: 1,
      byState: { "Submitted and indexed": 1, "Discovered - currently not indexed": 1 },
    },
  );
});
