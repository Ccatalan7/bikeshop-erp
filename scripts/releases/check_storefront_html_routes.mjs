#!/usr/bin/env node
// Checks, after a store publication, the routes `firebase.json` hands to the
// HTML server (Cloud Run `storefront-html`) on both live origins.
//
// Hosting publishes the sitemap and drops the snapshots of those routes, but
// the pages come from a service published on its own
// (services/storefront_html/deploy_cloud_run.sh). `release.json` matching
// says nothing about them, so this asks the live origins for `/productos` and
// the other exact routes the sitemap publishes (the information pages),
// every category and a sample of products from the sitemap just built, two old
// UUID links and an unknown category, and fails when:
//   - a page is not a 200 with its sitemap URL as canonical and indexable;
//   - an old link does not 301 to the product's canonical path;
//   - an unknown category is not a real 404 from the server;
//   - a private route (`/carrito`, `/checkout`, an order page) is not a 200
//     from the server with noindex;
//   - Cloud Run answers with another source than this commit's
//     (`x-storefront-source`, services/storefront_html/tool/source_id.sh): the
//     shared core changed and the server was not published with it.
//
// Usage (repository root, after the generator):
//   EXPECTED_STORE_ORIGIN=https://vinabike.cl \
//   EXPECTED_FIREBASE_ORIGIN=https://vinabike-store.web.app \
//   node scripts/releases/check_storefront_html_routes.mjs
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const uuidPath = /^\/productos\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

function unescapeXml(value) {
  return value
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&quot;", '"')
    .replaceAll("&apos;", "'")
    .replaceAll("&amp;", "&");
}

// Which pages and links to ask for, from the sitemap and the redirect
// manifest of this build.
// The exact sources (`/productos`, `/nosotros`…) the store target of
// `firebase.json` rewrites to the HTML server.
export function exactServerRoutes(firebaseConfig) {
  const store = (firebaseConfig?.hosting ?? []).find((entry) => entry.target === "store");
  return (store?.rewrites ?? [])
    .filter((rewrite) => rewrite.run?.serviceId === "storefront-html" &&
      typeof rewrite.source === "string" && !rewrite.source.includes("*"))
    .map((rewrite) => rewrite.source);
}

// Every source, exact or `/**`, the store target rewrites to the HTML server.
export function serverRouteSources(firebaseConfig) {
  const store = (firebaseConfig?.hosting ?? []).find((entry) => entry.target === "store");
  return (store?.rewrites ?? [])
    .filter((rewrite) => rewrite.run?.serviceId === "storefront-html" &&
      typeof rewrite.source === "string")
    .map((rewrite) => rewrite.source);
}

// Server routes that are never indexed, so the sitemap does not list them:
// they must still be a 200 from the server, with `noindex`.
export const privateServerRoutes = ["/carrito", "/checkout"];

// A path under a private `/**` source, to ask for it: the order page answers
// its frame for any order id (the order itself is read in the browser).
export const privateServerSamples = {
  "/pedido/**": "/pedido/00000000-0000-4000-8000-000000000000",
};

export function selectStorefrontHtmlChecks({
  sitemapXml,
  redirectManifest,
  storeOrigin,
  exactRoutes = ["/productos"],
  serverSources = exactRoutes,
  productSample = 6,
  legacySample = 2,
}) {
  const base = storeOrigin.replace(/\/+$/, "");
  const urls = [...sitemapXml.matchAll(/<loc>(.*?)<\/loc>/g)].map((match) =>
    unescapeXml(match[1].trim()),
  );
  // The home is the bare origin in the sitemap and in its canonical.
  const paths = urls
    .filter((url) => url === base || url.startsWith(`${base}/`))
    .map((url) => (url === base ? "/" : url.slice(base.length)));
  const categories = paths.filter((path) =>
    path.startsWith("/productos/categoria/"),
  );
  const products = paths.filter(
    (path) => /^\/productos\/[^/]+\/[^/]+$/.test(path) &&
      !path.startsWith("/productos/categoria/"),
  );
  const sampled = [];
  if (products.length > 0) {
    const step = Math.max(1, Math.floor(products.length / productSample));
    for (let i = 0; i < products.length && sampled.length < productSample; i += step) {
      sampled.push(products[i]);
    }
  }
  const legacy = (redirectManifest?.redirects ?? [])
    .filter((redirect) => uuidPath.test(redirect.source))
    .slice(0, legacySample);
  if (!paths.includes("/productos")) {
    throw new Error("sitemap.xml no trae /productos: no hay nada que revisar.");
  }
  if (sampled.length === 0) {
    throw new Error("sitemap.xml no trae fichas de producto.");
  }
  // Every other exact route the sitemap publishes (the information pages);
  // an unpublished one is not in the sitemap and answers 404 by design.
  const exact = exactRoutes.filter(
    (path) => path !== "/productos" && paths.includes(path),
  );
  return {
    pages: ["/productos", ...exact, ...categories, ...sampled].map((path) => ({
      path,
      canonical: path === "/" ? base : `${base}${path}`,
    })),
    redirects: legacy.flatMap((redirect) => [
      // Hosting's exact rule, and the server's answer for the singular route.
      { path: redirect.source, location: redirect.destination },
      {
        path: redirect.source.replace(/^\/productos\//, "/producto/"),
        location: redirect.destination,
      },
    ]),
    missing: "/productos/categoria/no-existe-revision-de-publicacion",
    private: [
      ...exactRoutes.filter((path) => privateServerRoutes.includes(path)),
      ...serverSources
        .filter((source) => source in privateServerSamples)
        .map((source) => privateServerSamples[source]),
    ],
  };
}

// The attributes of each `<tag …>` in a page, whatever their order: Jaspr
// writes `href` before `rel` (a search that assumed the other order failed
// the first live check, 2026-10-05).
export function tagAttributes(html, tag) {
  return [...html.matchAll(new RegExp(`<${tag}\\b([^>]*)>`, "gi"))].map(
    (match) =>
      Object.fromEntries(
        [...match[1].matchAll(/([a-zA-Z:-]+)\s*=\s*"([^"]*)"/g)].map((attr) => [
          attr[1].toLowerCase(),
          unescapeXml(attr[2]),
        ]),
      ),
  );
}

async function request(origin, path, { attempts = 3, timeoutMs = 30000 } = {}) {
  let lastError;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      const response = await fetch(`${origin}${path}`, {
        redirect: "manual",
        signal: AbortSignal.timeout(timeoutMs),
        headers: { "user-agent": "vinabike-publication-check" },
      });
      const body = await response.text();
      // A cold start or a read that failed (503) is retried; the rest counts.
      if (response.status < 500 || attempt === attempts) {
        return { status: response.status, headers: response.headers, body };
      }
      lastError = new Error(`HTTP ${response.status}`);
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 2000 * attempt));
  }
  throw new Error(`${origin}${path}: ${lastError?.message ?? lastError}`);
}

function sourceProblem(origin, path, headers, expectedSource) {
  const served = headers.get("x-storefront-source");
  if (served === expectedSource) return null;
  return (
    `${origin}${path} viene de la fuente ${served ?? "(sin x-storefront-source)"} ` +
    `y este commit es ${expectedSource}: publica el servidor con ` +
    "services/storefront_html/deploy_cloud_run.sh"
  );
}

export async function checkStorefrontHtmlRoutes({
  origins,
  checks,
  expectedSource,
  log = console.log,
  requestOptions,
}) {
  const failures = [];
  for (const origin of origins.map((value) => value.replace(/\/+$/, ""))) {
    for (const page of checks.pages) {
      const response = await request(origin, page.path, requestOptions);
      const problems = [];
      if (response.status !== 200) problems.push(`HTTP ${response.status}`);
      const canonical = tagAttributes(response.body, "link").find(
        (link) => link.rel?.toLowerCase() === "canonical",
      )?.href;
      if (canonical !== page.canonical) {
        problems.push(`canonical ${canonical ?? "(ninguna)"}`);
      }
      const robots = [
        response.headers.get("x-robots-tag") ?? "",
        tagAttributes(response.body, "meta").find(
          (meta) => meta.name?.toLowerCase() === "robots",
        )?.content ?? "",
      ].join(" ");
      if (/noindex/i.test(robots)) problems.push(`robots «${robots.trim()}»`);
      const source = sourceProblem(origin, page.path, response.headers, expectedSource);
      if (source) problems.push(source);
      if (problems.length > 0) {
        failures.push(`${origin}${page.path}: ${problems.join("; ")}`);
      } else {
        log(`ok ${origin}${page.path}`);
      }
    }
    for (const redirect of checks.redirects) {
      const response = await request(origin, redirect.path, requestOptions);
      const location = response.headers.get("location");
      const target = location ? new URL(location, origin).pathname : null;
      if (
        response.status !== 301 ||
        target === null ||
        decodeURIComponent(target) !== decodeURIComponent(redirect.location)
      ) {
        failures.push(
          `${origin}${redirect.path}: esperaba 301 a ${redirect.location}, ` +
            `llegó ${response.status} ${location ?? ""}`.trim(),
        );
      } else {
        log(`ok ${origin}${redirect.path} → ${target}`);
      }
    }
    for (const path of checks.private ?? []) {
      const response = await request(origin, path, requestOptions);
      const problems = [];
      if (response.status !== 200) problems.push(`HTTP ${response.status}`);
      const robots = tagAttributes(response.body, "meta").find(
        (meta) => meta.name?.toLowerCase() === "robots",
      )?.content ?? "";
      if (!/noindex/i.test(robots)) problems.push(`robots «${robots}», esperaba noindex`);
      const source = sourceProblem(origin, path, response.headers, expectedSource);
      if (source) problems.push(source);
      if (problems.length > 0) {
        failures.push(`${origin}${path}: ${problems.join("; ")}`);
      } else {
        log(`ok ${origin}${path} (noindex)`);
      }
    }
    const missing = await request(origin, checks.missing, requestOptions);
    const source = sourceProblem(origin, checks.missing, missing.headers, expectedSource);
    if (missing.status !== 404 || source) {
      failures.push(
        `${origin}${checks.missing}: esperaba el 404 del servidor HTML, ` +
          `llegó ${missing.status}${source ? `; ${source}` : ""}`,
      );
    } else {
      log(`ok ${origin}${checks.missing} → 404`);
    }
  }
  return failures;
}

async function main() {
  const origins = [
    process.env.EXPECTED_STORE_ORIGIN,
    process.env.EXPECTED_FIREBASE_ORIGIN,
  ].filter((value) => value && value.trim());
  if (origins.length === 0) {
    throw new Error("Faltan EXPECTED_STORE_ORIGIN y EXPECTED_FIREBASE_ORIGIN.");
  }
  const firebaseConfig = JSON.parse(
    readFileSync(process.env.FIREBASE_CONFIG ?? "firebase.json", "utf8"),
  );
  const checks = selectStorefrontHtmlChecks({
    sitemapXml: readFileSync(
      process.env.SITEMAP_FILE ?? "build/web_store/sitemap.xml",
      "utf8",
    ),
    redirectManifest: JSON.parse(
      readFileSync(
        process.env.REDIRECT_MANIFEST ?? "scripts/generated_product_redirects.json",
        "utf8",
      ),
    ),
    storeOrigin: process.env.CANONICAL_STORE_ORIGIN ?? "https://vinabike.cl",
    exactRoutes: exactServerRoutes(firebaseConfig),
    serverSources: serverRouteSources(firebaseConfig),
  });
  const expectedSource = execFileSync(
    "bash",
    ["services/storefront_html/tool/source_id.sh"],
    { encoding: "utf8" },
  ).trim();
  const failures = await checkStorefrontHtmlRoutes({
    origins,
    checks,
    expectedSource,
  });
  if (failures.length > 0) {
    console.error(
      `Las rutas del servidor HTML fallaron en ${failures.length} revisiones:\n` +
        failures.map((failure) => `- ${failure}`).join("\n"),
    );
    process.exit(1);
  }
  console.log(
    `Servidor HTML verificado (${expectedSource}) en ${origins.join(" y ")}.`,
  );
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main().catch((error) => {
    console.error(error.message ?? error);
    process.exit(1);
  });
}
