import assert from "node:assert/strict";
import { createServer } from "node:http";
import test from "node:test";
import { readFileSync } from "node:fs";

import {
  exactServerRoutes,
  serverRouteSources,
  checkStorefrontHtmlRoutes,
  selectStorefrontHtmlChecks,
  tagAttributes,
} from "./check_storefront_html_routes.mjs";

const store = "https://taller-norte.example";
const uuid = "46a51a87-aa3a-430c-a6e1-af48c8d74541";
const sitemapXml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>${store}</loc></url>
  <url><loc>${store}/productos</loc></url>
  <url><loc>${store}/productos/categoria/frenos</loc></url>
  <url><loc>${store}/productos/pastillas-shimano/1161022</loc></url>
  <url><loc>${store}/productos/rueda-27-5/RDM41%20LD</loc></url>
  <url><loc>${store}/servicios</loc></url>
</urlset>`;
const redirectManifest = {
  generatedAt: "2026-10-05T00:00:00Z",
  redirects: [
    { source: "/productos/viejo-nombre/1161022", destination: "/productos/pastillas-shimano/1161022", type: 301 },
    { source: `/productos/${uuid}`, destination: "/productos/pastillas-shimano/1161022", type: 301 },
  ],
};
const source = "core-aaaaaaaaaaaa.server-bbbbbbbbbbbb";

// The order Jaspr writes them: `href` before `rel`, `name` before `content`.
function page(path, { robots = "index,follow" } = {}) {
  return `<!doctype html><html><head><link href="${store}${path}" rel="canonical"/>` +
    `<meta name="robots" content="${robots}"/></head><body><main><h1>x</h1></main></body></html>`;
}

async function withServer(answer, run) {
  const server = createServer((request, response) => answer(request, response));
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  try {
    return await run(origin);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

function liveServer({ servedSource = source, noindexOn = null } = {}) {
  return (request, response) => {
    const path = decodeURI(new URL(request.url, "http://x").pathname);
    const headers = { "content-type": "text/html; charset=utf-8", "x-storefront-source": servedSource };
    if (path === `/productos/${uuid}` || path === `/producto/${uuid}`) {
      response.writeHead(301, { ...headers, location: "/productos/pastillas-shimano/1161022" });
      return response.end();
    }
    const known = ["/productos", "/productos/categoria/frenos", "/productos/pastillas-shimano/1161022", "/productos/rueda-27-5/RDM41 LD"];
    if (!known.includes(path)) {
      response.writeHead(404, headers);
      return response.end("<html></html>");
    }
    const canonicalPath = path.replace("RDM41 LD", "RDM41%20LD");
    response.writeHead(200, headers);
    response.end(page(canonicalPath, { robots: path === noindexOn ? "noindex,follow" : "index,follow" }));
  };
}

const checks = selectStorefrontHtmlChecks({ sitemapXml, redirectManifest, storeOrigin: store });
const fast = { attempts: 1, timeoutMs: 5000 };

test("picks the catalog, every category, products and the old UUID links", () => {
  assert.deepEqual(
    checks.pages.map((entry) => entry.path),
    ["/productos", "/productos/categoria/frenos", "/productos/pastillas-shimano/1161022", "/productos/rueda-27-5/RDM41%20LD"],
  );
  assert.deepEqual(checks.redirects, [
    { path: `/productos/${uuid}`, location: "/productos/pastillas-shimano/1161022" },
    { path: `/producto/${uuid}`, location: "/productos/pastillas-shimano/1161022" },
  ]);
});

test("reads attributes in any order", () => {
  const html = '<link rel="canonical" href="https://a.example/x?y=1&amp;z=2">' +
    '<link href="https://a.example/x.css" rel="stylesheet"/>' +
    '<meta content="noindex" name="robots">';
  assert.equal(
    tagAttributes(html, "link").find((link) => link.rel === "canonical").href,
    "https://a.example/x?y=1&z=2",
  );
  assert.equal(tagAttributes(html, "meta")[0].name, "robots");
});

test("a sitemap without the catalog has nothing to check and says so", () => {
  assert.throws(
    () => selectStorefrontHtmlChecks({ sitemapXml: "<urlset></urlset>", redirectManifest, storeOrigin: store }),
    /no trae \/productos/,
  );
});

test("passes when the server answers every route with this source", async () => {
  const failures = await withServer(liveServer(), (origin) =>
    checkStorefrontHtmlRoutes({ origins: [origin], checks, expectedSource: source, log: () => {}, requestOptions: fast }),
  );
  assert.deepEqual(failures, []);
});

test("fails on a server published from another source", async () => {
  const failures = await withServer(liveServer({ servedSource: "core-old.server-old" }), (origin) =>
    checkStorefrontHtmlRoutes({ origins: [origin], checks, expectedSource: source, log: () => {}, requestOptions: fast }),
  );
  assert.ok(failures.length >= 4);
  assert.match(failures[0], /deploy_cloud_run\.sh/);
});

test("fails on a noindex page and on a route Hosting answers itself", async () => {
  const failures = await withServer(
    (request, response) => {
      // Hosting's fallback: index.html with 200 for an unknown route.
      if (request.url.includes("no-existe")) {
        response.writeHead(200, { "content-type": "text/html" });
        return response.end(page("/"));
      }
      return liveServer({ noindexOn: "/productos/categoria/frenos" })(request, response);
    },
    (origin) => checkStorefrontHtmlRoutes({ origins: [origin], checks, expectedSource: source, log: () => {}, requestOptions: fast }),
  );
  assert.equal(failures.length, 2);
  assert.match(failures[0], /categoria\/frenos: robots/);
  assert.match(failures[1], /esperaba el 404 del servidor HTML, llegó 200/);
});

test("checks every exact server route the sitemap publishes, from firebase.json", () => {
  const routes = exactServerRoutes(JSON.parse(readFileSync("firebase.json", "utf8")));
  for (const path of ["/", "/productos", "/servicios", "/nosotros", "/envios", "/devoluciones", "/terminos", "/privacidad", "/contacto", "/carrito"]) {
    assert.ok(routes.includes(path), path);
  }
  const withPolicies = sitemapXml.replace(
    "</urlset>",
    `<url><loc>${store}</loc></url>` +
      `<url><loc>${store}/nosotros</loc></url><url><loc>${store}/envios</loc></url></urlset>`,
  );
  const pages = selectStorefrontHtmlChecks({
    sitemapXml: withPolicies,
    redirectManifest,
    storeOrigin: store,
    exactRoutes: routes,
  }).pages;
  const selected = pages.map((entry) => entry.path);
  // The services catalog, published information pages and the home are
  // checked; one not in the sitemap is not. The home's canonical is the bare
  // origin.
  assert.deepEqual(selected.slice(0, 5), ["/productos", "/servicios", "/nosotros", "/envios", "/"]);
  assert.equal(pages[4].canonical, store);
  assert.ok(!selected.includes("/terminos"));
});

test("a private route must be the server's, never indexed", async () => {
  const withCart = { ...checks, private: ["/carrito"] };
  const answer = (robots, servedSource = source) => (request, response) => {
    if (new URL(request.url, "http://x").pathname === "/carrito") {
      response.writeHead(200, { "content-type": "text/html", "x-storefront-source": servedSource });
      return response.end(page("/carrito", { robots }));
    }
    return liveServer()(request, response);
  };
  const run = (handler) => withServer(handler, (origin) =>
    checkStorefrontHtmlRoutes({ origins: [origin], checks: withCart, expectedSource: source, log: () => {}, requestOptions: fast }),
  );
  assert.deepEqual(await run(answer("noindex,follow")), []);
  const indexed = await run(answer("index,follow"));
  assert.equal(indexed.length, 1);
  assert.match(indexed[0], /carrito: robots «index,follow», esperaba noindex/);
  const fromFlutter = await run((request, response) => {
    if (new URL(request.url, "http://x").pathname === "/carrito") {
      response.writeHead(200, { "content-type": "text/html" });
      return response.end(page("/carrito", { robots: "noindex" }));
    }
    return liveServer()(request, response);
  });
  assert.equal(fromFlutter.length, 1);
  assert.match(fromFlutter[0], /sin x-storefront-source/);
});

test("an order page and the portal are checked as private server routes", () => {
  const firebaseConfig = JSON.parse(readFileSync("firebase.json", "utf8"));
  const checks = selectStorefrontHtmlChecks({
    sitemapXml,
    redirectManifest,
    storeOrigin: store,
    exactRoutes: exactServerRoutes(firebaseConfig),
    serverSources: serverRouteSources(firebaseConfig),
  });
  // The portal's content endpoints answer POST only: never asked for.
  assert.deepEqual(checks.private, [
    "/carrito",
    "/checkout",
    "/cuenta",
    "/cuenta/pedidos",
    "/cuenta/servicios",
    "/cuenta/bicicletas",
    "/cuenta/perfil",
    "/cuenta/direcciones",
    "/pedido/00000000-0000-4000-8000-000000000000",
  ]);
});
