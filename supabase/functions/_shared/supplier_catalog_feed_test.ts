import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  contentFingerprint,
  parseDelimited,
  parseMkrCsvV1,
  ROWS_PER_CALL,
  runSupplierFeedSync,
  type SupplierFeedFetch,
  supplierFeedUrl,
} from "./supplier_catalog_feed.ts";

const HEADER =
  'SKU;"Código Producto";"cod barra";stock;Precio_mkr;EsOferta;Precio_mkr_antes;Precio_mkr_oferta;"Precio Sugerido ( L2 )";Nombre;Marca;Grupo;"Sub Grupo";Descripcion;Foto;Foto2;Foto3;Foto4;Foto5;Foto6';

const RUN_ID = "0b9f4c1e-2a52-4a0b-9d0e-6f7d0c5a1b11";
const TICKET = "ab".repeat(32);
const TOKEN = "tok_sintetico-123";

function line(fields: string[]): string {
  return fields.join(";");
}

function file(lines: string[]): string {
  return `﻿${[HEADER, ...lines].join("\n")}\n`;
}

Deno.test("a quoted field keeps its separators, line breaks and doubled quotes", () => {
  const records = parseDelimited(
    '﻿a;"b;1";c\r\nd;"dice ""hola""\nen dos líneas";\n\ne;f;g',
  );
  assertEquals(records, [
    ["a", "b;1", "c"],
    ["d", 'dice "hola"\nen dos líneas', ""],
    ["e", "f", "g"],
  ]);
});

Deno.test("an unterminated quote takes the rest instead of looping", () => {
  assertEquals(parseDelimited('a;"sin cerrar;b\nc'), [["a", "sin cerrar;b\nc"]]);
});

Deno.test("MKR's file becomes rows with exact stock, net prices and photos", () => {
  const parsed = parseMkrCsvV1(file([
    line([
      "A317",
      "0000107000003",
      "4717954187799",
      "7",
      "8489.69",
      "1",
      "8489.69",
      "4244.84",
      "13017.00",
      "Adaptador de disco a2z 160/165 - 203",
      "A2Z Components",
      "",
      "",
      '"<p>Para discos de 203 mm; ""post mount"".</p>\n<p>Aluminio.</p>"',
      "https://cdn.exz.cl/product/A/A317/original/A317-1.jpg",
      "https://cdn.exz.cl/product/A/A317/original/A317-2.jpg",
      "",
      "",
      "",
      "",
    ]),
    line([
      "A055",
      "",
      "0",
      "-2",
      "9989.83",
      "",
      "",
      "",
      "14277.31",
      "Adaptador A2Z Single Speed",
      "A2Z Components",
      "",
      "",
      "",
      "http://sin-https.example/a.jpg",
      "",
      "",
      "",
      "",
      "",
    ]),
  ]));
  if (!parsed.ok) throw new Error(parsed.error);
  assertEquals(parsed.rows.length, 2);
  const first = parsed.rows[0];
  assertEquals(first.sku, "A317");
  assertEquals(first.productCode, "0000107000003");
  assertEquals(first.barcode, "4717954187799");
  assertEquals(first.stock, 7);
  assertEquals(first.price, "8489.69");
  assertEquals(first.priceBefore, "8489.69");
  assertEquals(first.priceOffer, "4244.84");
  assertEquals(first.suggestedRetail, "13017.00");
  assertEquals(first.name, "Adaptador de disco a2z 160/165 - 203");
  assertEquals(first.brand, "A2Z Components");
  assertEquals(
    first.description,
    '<p>Para discos de 203 mm; "post mount".</p>\n<p>Aluminio.</p>',
  );
  assertEquals(first.photos, [
    "https://cdn.exz.cl/product/A/A317/original/A317-1.jpg",
    "https://cdn.exz.cl/product/A/A317/original/A317-2.jpg",
  ]);
  const second = parsed.rows[1];
  // A barcode of zeros is a placeholder, a negative stock is what MKR says,
  // an empty price is no price, and a photo that is not https is not stored.
  assertEquals(second.barcode, null);
  assertEquals(second.productCode, null);
  assertEquals(second.stock, -2);
  assertEquals(second.priceBefore, null);
  assertEquals(second.priceOffer, null);
  assertEquals(second.description, null);
  assertEquals(second.photos, []);
});

Deno.test("columns are found by name, the last line of a code wins and bad lines are counted", () => {
  const parsed = parseMkrCsvV1(
    [
      "Marca;Nombre;stock;SKU;Precio_mkr",
      "KMC;Cadena Z8.3;3;C883;7990.00",
      "KMC;Cadena Z8.3;12;C883;7990.00",
      "KMC;Sin código;4;;100.00",
      "KMC;Stock raro;muchos;C999;no-es-precio",
    ].join("\n"),
  );
  if (!parsed.ok) throw new Error(parsed.error);
  assertEquals(parsed.skipped, 1);
  assertEquals(
    parsed.rows.map((row) => [row.sku, row.stock, row.price]),
    [["C883", 12, "7990.00"], ["C999", 0, null]],
  );
});

Deno.test("a file that is not MKR's is refused by its header", () => {
  assertEquals(parseMkrCsvV1("<html><body>Acceso denegado</body></html>\n"), {
    ok: false,
    error: "empty_file",
  });
  assertEquals(parseMkrCsvV1("codigo;cantidad\nA1;3\n"), {
    ok: false,
    error: "unexpected_header",
  });
});

Deno.test("the fingerprint changes with any part of the content", () => {
  const base = contentFingerprint("Cadena", "KMC", "<p>8 v</p>", ["https://a/1.jpg"]);
  assertEquals(base, contentFingerprint("Cadena", "KMC", "<p>8 v</p>", ["https://a/1.jpg"]));
  const others = [
    contentFingerprint("Cadena.", "KMC", "<p>8 v</p>", ["https://a/1.jpg"]),
    contentFingerprint("Cadena", "KMC ", "<p>8 v</p>", ["https://a/1.jpg"]),
    contentFingerprint("Cadena", "KMC", "<p>9 v</p>", ["https://a/1.jpg"]),
    contentFingerprint("Cadena", "KMC", "<p>8 v</p>", ["https://a/2.jpg"]),
    contentFingerprint("Cadena", "KMC", "<p>8 v</p>", []),
    contentFingerprint("Cadena", "KMC", null, ["https://a/1.jpg"]),
  ];
  assertEquals(new Set([base, ...others]).size, others.length + 1);
});

Deno.test("a reading only goes to the supplier's own host", () => {
  assertEquals(
    supplierFeedUrl("mkr_csv_v1", "https://mkr.cl/api/endpoint?token={token}", "a b/c"),
    "https://mkr.cl/api/endpoint?token=a%20b%2Fc",
  );
  assertEquals(
    supplierFeedUrl("mkr_csv_v1", "https://mkr.cl.example.org/api?token={token}", TOKEN),
    null,
  );
  assertEquals(supplierFeedUrl("mkr_csv_v1", "http://mkr.cl/api?token={token}", TOKEN), null);
  assertEquals(supplierFeedUrl("mkr_csv_v1", "https://mkr.cl:8443/api?token={token}", TOKEN), null);
  assertEquals(supplierFeedUrl("mkr_csv_v1", "https://mkr.cl/api?token=fijo", TOKEN), null);
  assertEquals(supplierFeedUrl("otro_formato", "https://mkr.cl/api?token={token}", TOKEN), null);
  assertEquals(supplierFeedUrl("mkr_csv_v1", "https://mkr.cl/api?token={token}", ""), null);
});

type Call = { name: string; args: Record<string, unknown> };

function fakeClient(responses: Record<string, unknown[]>, failing: string[] = []) {
  const calls: Call[] = [];
  return {
    calls,
    client: {
      rpc(name: string, args: Record<string, unknown>) {
        calls.push({ name, args });
        if (failing.includes(name)) {
          return Promise.resolve({ data: null, error: { message: "boom" } });
        }
        const queue = responses[name] ?? [];
        const data = queue.length > 1 ? queue.shift() : queue[0];
        return Promise.resolve({ data: data ?? null, error: null });
      },
    },
  };
}

function fakeFetch(body: string, status = 200) {
  const urls: string[] = [];
  const fetchFn: SupplierFeedFetch = (url) => {
    urls.push(url);
    return Promise.resolve(new Response(body, { status }));
  };
  return { urls, fetchFn };
}

const REDEEMED = {
  run_id: RUN_ID,
  format: "mkr_csv_v1",
  endpoint_template: "https://mkr.cl/api/endpoint?token={token}",
  token: TOKEN,
};

function twoProducts(): string {
  return file([
    line([
      "C883",
      "",
      "",
      "50",
      "7990.00",
      "",
      "",
      "",
      "11591.00",
      "Cadena KMC Z8.3",
      "KMC",
      "",
      "",
      "<p>8 velocidades</p>",
      "https://cdn.exz.cl/c883.jpg",
      "",
      "",
      "",
      "",
      "",
    ]),
    line([
      "L100",
      "",
      "",
      "0",
      "40000.00",
      "",
      "",
      "",
      "59900.00",
      "Candado OnGuard",
      "On Guard",
      "",
      "",
      "<p>U-Lock</p>",
      "",
      "",
      "",
      "",
      "",
      "",
    ]),
  ]);
}

Deno.test("a request without a well-formed ticket never reaches the database or the supplier", async () => {
  const { client, calls } = fakeClient({});
  const { urls, fetchFn } = fakeFetch(twoProducts());
  for (
    const payload of [null, {}, { run_id: RUN_ID }, { run_id: "x", token: TICKET }, {
      run_id: RUN_ID,
      token: "corto",
    }]
  ) {
    const answer = await runSupplierFeedSync({ client, payload, fetchFn });
    assertEquals(answer, { status: 400, body: { ok: false, error: "invalid_ticket" } });
  }
  assertEquals(calls.length, 0);
  assertEquals(urls.length, 0);
});

Deno.test("a ticket the database refuses never reaches the supplier", async () => {
  const { client, calls } = fakeClient({ redeem_supplier_catalog_feed_sync: [null] });
  const { urls, fetchFn } = fakeFetch(twoProducts());
  const answer = await runSupplierFeedSync({
    client,
    payload: { run_id: RUN_ID, token: TICKET },
    fetchFn,
  });
  assertEquals(answer, { status: 409, body: { ok: false, error: "ticket_refused" } });
  assertEquals(calls.map((call) => call.name), ["redeem_supplier_catalog_feed_sync"]);
  assertEquals(urls.length, 0);
});

Deno.test("a reading stores every row, sends only the content asked for and closes with all codes", async () => {
  const { client, calls } = fakeClient({
    redeem_supplier_catalog_feed_sync: [REDEEMED],
    apply_supplier_catalog_feed_rows_v1: [{
      rows: 2,
      new: 1,
      stock_changes: 1,
      price_changes: 0,
      need_content: ["L100"],
    }],
    apply_supplier_catalog_feed_content_v1: [1],
    finish_supplier_catalog_feed_run_v1: [{
      status: "ok",
      rows: 2,
      listed: 2,
      in_stock: 1,
      delisted: 3,
    }],
  });
  const { urls, fetchFn } = fakeFetch(twoProducts());
  let clock = 1000;
  const answer = await runSupplierFeedSync({
    client,
    payload: { run_id: RUN_ID, token: TICKET },
    fetchFn,
    now: () => (clock += 250),
  });
  assertEquals(urls, [`https://mkr.cl/api/endpoint?token=${TOKEN}`]);
  assertEquals(calls.map((call) => call.name), [
    "redeem_supplier_catalog_feed_sync",
    "apply_supplier_catalog_feed_rows_v1",
    "apply_supplier_catalog_feed_content_v1",
    "finish_supplier_catalog_feed_run_v1",
  ]);
  const rows = calls[1].args.p_rows as unknown[][];
  assertEquals(rows.map((row) => row.slice(0, 8)), [
    ["C883", null, null, 50, "7990.00", null, null, "11591.00"],
    ["L100", null, null, 0, "40000.00", null, null, "59900.00"],
  ]);
  const content = calls[2].args.p_rows as unknown[][];
  assertEquals(content.map((row) => row.slice(0, 5)), [
    ["L100", "Candado OnGuard", "On Guard", "<p>U-Lock</p>", []],
  ]);
  assertEquals(content[0][5], rows[1][8]);
  assertEquals(calls[3].args.p_skus, ["C883", "L100"]);
  assertEquals((calls[3].args.p_stats as Record<string, unknown>).http_status, 200);
  assertEquals(answer, {
    status: 200,
    body: {
      ok: true,
      status: "ok",
      rows: 2,
      skipped: 0,
      new: 1,
      stock_changes: 1,
      price_changes: 0,
      content_changes: 1,
      delisted: 3,
      in_stock: 1,
    },
  });
  // Neither the address nor the token leaves in the answer.
  assertEquals(JSON.stringify(answer).includes(TOKEN), false);
  assertEquals(JSON.stringify(answer).includes("mkr.cl"), false);
});

Deno.test("an unchanged catalogue sends no content", async () => {
  const { client, calls } = fakeClient({
    redeem_supplier_catalog_feed_sync: [REDEEMED],
    apply_supplier_catalog_feed_rows_v1: [{ rows: 2, new: 0, need_content: [] }],
    finish_supplier_catalog_feed_run_v1: [{ status: "ok", delisted: 0, in_stock: 1 }],
  });
  const { fetchFn } = fakeFetch(twoProducts());
  const answer = await runSupplierFeedSync({
    client,
    payload: { run_id: RUN_ID, token: TICKET },
    fetchFn,
  });
  assertEquals(calls.map((call) => call.name), [
    "redeem_supplier_catalog_feed_sync",
    "apply_supplier_catalog_feed_rows_v1",
    "finish_supplier_catalog_feed_run_v1",
  ]);
  assertEquals(answer.body.content_changes, 0);
});

Deno.test("a large catalogue goes in several calls", async () => {
  const lines: string[] = [];
  for (let index = 0; index < ROWS_PER_CALL + 5; index += 1) {
    lines.push(line([
      `S${index}`,
      "",
      "",
      "1",
      "100.00",
      "",
      "",
      "",
      "150.00",
      `Producto ${index}`,
      "SRAM",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
    ]));
  }
  const { client, calls } = fakeClient({
    redeem_supplier_catalog_feed_sync: [REDEEMED],
    apply_supplier_catalog_feed_rows_v1: [{ need_content: [] }],
    finish_supplier_catalog_feed_run_v1: [{ status: "ok" }],
  });
  const { fetchFn } = fakeFetch(file(lines));
  await runSupplierFeedSync({ client, payload: { run_id: RUN_ID, token: TICKET }, fetchFn });
  const applied = calls.filter((call) => call.name === "apply_supplier_catalog_feed_rows_v1");
  assertEquals(applied.map((call) => (call.args.p_rows as unknown[]).length), [ROWS_PER_CALL, 5]);
  const finish = calls[calls.length - 1];
  assertEquals((finish.args.p_skus as string[]).length, ROWS_PER_CALL + 5);
});

Deno.test("what the supplier refuses, or answers wrong, closes the reading as failed with a code", async () => {
  const cases: Array<[string, number, string, number | null]> = [
    ["Token inválido", 401, "http_401", 401],
    ["<html>mantenimiento</html>", 200, "empty_file", 200],
    ["codigo;cantidad\nA1;3\n", 200, "unexpected_header", 200],
  ];
  for (const [body, status, code, httpStatus] of cases) {
    const { client, calls } = fakeClient({ redeem_supplier_catalog_feed_sync: [REDEEMED] });
    const { fetchFn } = fakeFetch(body, status);
    const answer = await runSupplierFeedSync({
      client,
      payload: { run_id: RUN_ID, token: TICKET },
      fetchFn,
    });
    assertEquals(answer, { status: 200, body: { ok: false, error: code } });
    assertEquals(calls[calls.length - 1], {
      name: "fail_supplier_catalog_feed_run_v1",
      args: { p_run_id: RUN_ID, p_error_code: code, p_http_status: httpStatus },
    });
    assertEquals(
      calls.some((call) => call.name === "apply_supplier_catalog_feed_rows_v1"),
      false,
    );
  }
});

Deno.test("an address that is not the supplier's is never fetched", async () => {
  const { client, calls } = fakeClient({
    redeem_supplier_catalog_feed_sync: [{
      ...REDEEMED,
      endpoint_template: "https://otro.example/api?token={token}",
    }],
  });
  const { urls, fetchFn } = fakeFetch(twoProducts());
  const answer = await runSupplierFeedSync({
    client,
    payload: { run_id: RUN_ID, token: TICKET },
    fetchFn,
  });
  assertEquals(urls.length, 0);
  assertEquals(answer.body.error, "address_not_allowed");
  assertEquals(calls[calls.length - 1].name, "fail_supplier_catalog_feed_run_v1");
});

Deno.test("a database error mid-reading closes it as failed and never finishes it", async () => {
  const { client, calls } = fakeClient(
    { redeem_supplier_catalog_feed_sync: [REDEEMED] },
    ["apply_supplier_catalog_feed_rows_v1"],
  );
  const { fetchFn } = fakeFetch(twoProducts());
  const answer = await runSupplierFeedSync({
    client,
    payload: { run_id: RUN_ID, token: TICKET },
    fetchFn,
  });
  assertEquals(answer.body, { ok: false, error: "apply_rows_failed" });
  assertEquals(
    calls.some((call) => call.name === "finish_supplier_catalog_feed_run_v1"),
    false,
  );
});

Deno.test("a fetch that throws closes the reading as failed", async () => {
  const { client, calls } = fakeClient({ redeem_supplier_catalog_feed_sync: [REDEEMED] });
  const answer = await runSupplierFeedSync({
    client,
    payload: { run_id: RUN_ID, token: TICKET },
    fetchFn: () => Promise.reject(new Error("dns")),
  });
  assertEquals(answer.body, { ok: false, error: "fetch_failed" });
  assertEquals(calls[calls.length - 1].args.p_error_code, "fetch_failed");
});
