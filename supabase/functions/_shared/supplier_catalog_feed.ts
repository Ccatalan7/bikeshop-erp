// Reading a supplier's catalogue feed.
//
// MKR Imports gave Viñabike an endpoint on 2026-11-17: one file with every
// product of the brands the shop asked for, its exact stock, net prices,
// description and photos, refreshed every 30 minutes. The portal only showed
// one product at a time and cut the stock at «50+».
//
// The database starts a reading on a schedule
// (`dispatch_supplier_catalog_feed_syncs`) and is the only one that can. The
// function that serves it is open to the internet, so the single-use ticket
// the database minted for that reading is the only authority: a request
// without it is refused before the supplier is asked. The address and its
// token arrive from the database when the ticket is redeemed and go nowhere
// else: not into an answer, not into a log.
//
// The database decides what changed. Stock and prices of every row go first;
// it answers which codes need their content, and only those descriptions and
// photos are sent. An unchanged catalogue costs the database three reads.

type JsonRecord = Record<string, unknown>;

export type SupplierFeedClient = {
  rpc: (
    name: string,
    args: JsonRecord,
  ) => PromiseLike<{ data: unknown; error: { message?: string; code?: string } | null }>;
};

export type SupplierFeedFetch = (
  url: string,
  init: { signal: AbortSignal; redirect: "error"; headers: Record<string, string> },
) => Promise<Response>;

export type SupplierFeedRow = {
  sku: string;
  productCode: string | null;
  barcode: string | null;
  stock: number;
  price: string | null;
  priceBefore: string | null;
  priceOffer: string | null;
  suggestedRetail: string | null;
  name: string;
  brand: string;
  description: string | null;
  photos: string[];
  contentHash: string;
};

export type SupplierFeedParse =
  | { ok: true; rows: SupplierFeedRow[]; skipped: number }
  | { ok: false; error: string };

export type SupplierFeedAnswer = {
  status: number;
  body: JsonRecord;
};

const RUN_ID = /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const RUN_TICKET = /^[0-9a-f]{64}$/;
const DECIMAL = /^\d{1,11}(\.\d{1,4})?$/;
const BARCODE = /^[0-9A-Za-z-]{4,32}$/;

/** The only host each format may be read from. */
const FORMAT_HOSTS: Record<string, string> = {
  mkr_csv_v1: "mkr.cl",
};

/** Rows of stock and prices per call: about 300 KB of JSON. */
export const ROWS_PER_CALL = 3000;
/** Content per call: descriptions are HTML of up to 20 KB each. */
export const CONTENT_ROWS_PER_CALL = 400;
export const CONTENT_CHARS_PER_CALL = 700_000;
/** The file is 18 MB today. Past this it is not the catalogue. */
export const MAX_FEED_CHARS = 80_000_000;
export const FETCH_TIMEOUT_MS = 90_000;

/** Splits delimited text into records. Fields may be quoted, hold the
 * delimiter and line breaks, and double a quote to escape it. */
export function parseDelimited(text: string, delimiter = ";"): string[][] {
  const records: string[][] = [];
  const separator = delimiter.charCodeAt(0);
  const length = text.length;
  let index = text.charCodeAt(0) === 0xfeff ? 1 : 0;
  let record: string[] = [];
  while (index < length) {
    let field: string;
    if (text.charCodeAt(index) === 34) {
      index += 1;
      let start = index;
      let parts: string[] | null = null;
      for (;;) {
        const quote = text.indexOf('"', index);
        if (quote === -1) {
          field = (parts ? parts.join("") : "") + text.slice(start);
          index = length;
          break;
        }
        if (text.charCodeAt(quote + 1) === 34) {
          (parts ??= []).push(text.slice(start, quote + 1));
          index = quote + 2;
          start = index;
          continue;
        }
        field = parts ? parts.join("") + text.slice(start, quote) : text.slice(start, quote);
        index = quote + 1;
        break;
      }
      // Anything between the closing quote and the next separator is noise.
      while (index < length) {
        const code = text.charCodeAt(index);
        if (code === separator || code === 10 || code === 13) break;
        index += 1;
      }
    } else {
      let end = index;
      while (end < length) {
        const code = text.charCodeAt(end);
        if (code === separator || code === 10 || code === 13) break;
        end += 1;
      }
      field = text.slice(index, end);
      index = end;
    }
    record.push(field);
    if (index >= length) break;
    const code = text.charCodeAt(index);
    if (code === separator) {
      index += 1;
      if (index >= length) record.push("");
      continue;
    }
    index += code === 13 && text.charCodeAt(index + 1) === 10 ? 2 : 1;
    records.push(record);
    record = [];
  }
  if (record.length > 0) records.push(record);
  return records.filter((fields) => fields.length > 1 || fields[0] !== "");
}

function headerKey(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function decimal(value: string | undefined): string | null {
  const trimmed = (value ?? "").trim();
  return DECIMAL.test(trimmed) ? trimmed : null;
}

/** A fingerprint of what describes a product. 53 bits (cyrb53): enough to
 * tell a changed description among ten thousand, and cheap over 16 MB. */
export function contentFingerprint(
  name: string,
  brand: string,
  description: string | null,
  photos: string[],
): string {
  const text = `${name}\u0001${brand}\u0001${description ?? ""}\u0001${photos.join("\u0002")}`;
  let h1 = 0xdeadbeef;
  let h2 = 0x41c6ce57;
  for (let index = 0; index < text.length; index += 1) {
    const code = text.charCodeAt(index);
    h1 = Math.imul(h1 ^ code, 2654435761);
    h2 = Math.imul(h2 ^ code, 1597334677);
  }
  h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909);
  h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^ Math.imul(h1 ^ (h1 >>> 13), 3266489909);
  const high = (h2 >>> 0).toString(16).padStart(8, "0");
  const low = (h1 >>> 0).toString(16).padStart(8, "0");
  return `v1:${high}${low}:${text.length}`;
}

/** MKR's file: `;` separated, one header line, prices net of tax.
 * SKU;Código Producto;cod barra;stock;Precio_mkr;EsOferta;Precio_mkr_antes;
 * Precio_mkr_oferta;Precio Sugerido ( L2 );Nombre;Marca;Grupo;Sub Grupo;
 * Descripcion;Foto;Foto2…Foto6 */
export function parseMkrCsvV1(text: string): SupplierFeedParse {
  const records = parseDelimited(text, ";");
  if (records.length < 2) return { ok: false, error: "empty_file" };
  const columns = new Map<string, number>();
  records[0].forEach((name, position) => {
    const key = headerKey(name);
    if (key && !columns.has(key)) columns.set(key, position);
  });
  const required = ["sku", "stock", "precio_mkr", "nombre", "marca"];
  if (required.some((key) => !columns.has(key))) {
    return { ok: false, error: "unexpected_header" };
  }
  const at = (key: string) => columns.get(key) ?? -1;
  const sku = at("sku");
  const productCode = at("codigo_producto");
  const barcode = at("cod_barra");
  const stock = at("stock");
  const price = at("precio_mkr");
  const priceBefore = at("precio_mkr_antes");
  const priceOffer = at("precio_mkr_oferta");
  const suggested = at("precio_sugerido_l2");
  const name = at("nombre");
  const brand = at("marca");
  const description = at("descripcion");
  const photoColumns = ["foto", "foto2", "foto3", "foto4", "foto5", "foto6"]
    .map(at)
    .filter((position) => position >= 0);

  // The last line of a code wins, as in the database.
  const rows = new Map<string, SupplierFeedRow>();
  let skipped = 0;
  for (let line = 1; line < records.length; line += 1) {
    const fields = records[line];
    const code = (fields[sku] ?? "").trim();
    if (!code || code.length > 64) {
      skipped += 1;
      continue;
    }
    const quantity = Number((fields[stock] ?? "").trim());
    const rowName = (fields[name] ?? "").trim();
    const rowBrand = (fields[brand] ?? "").trim();
    const rowDescription = description >= 0 ? (fields[description] ?? "").trim() : "";
    const photos: string[] = [];
    for (const position of photoColumns) {
      const url = (fields[position] ?? "").trim();
      if (url.startsWith("https://") && !/\s/.test(url) && !photos.includes(url)) {
        photos.push(url);
      }
    }
    const rawBarcode = barcode >= 0 ? (fields[barcode] ?? "").trim() : "";
    const rawProductCode = productCode >= 0 ? (fields[productCode] ?? "").trim() : "";
    rows.set(code, {
      sku: code,
      productCode: rawProductCode ? rawProductCode.slice(0, 64) : null,
      barcode: BARCODE.test(rawBarcode) && !/^0+$/.test(rawBarcode) ? rawBarcode : null,
      stock: Number.isFinite(quantity) ? Math.trunc(quantity) : 0,
      price: decimal(fields[price]),
      priceBefore: priceBefore >= 0 ? decimal(fields[priceBefore]) : null,
      priceOffer: priceOffer >= 0 ? decimal(fields[priceOffer]) : null,
      suggestedRetail: suggested >= 0 ? decimal(fields[suggested]) : null,
      name: rowName,
      brand: rowBrand,
      description: rowDescription || null,
      photos,
      contentHash: contentFingerprint(rowName, rowBrand, rowDescription || null, photos),
    });
  }
  if (rows.size === 0) return { ok: false, error: "empty_file" };
  return { ok: true, rows: [...rows.values()], skipped };
}

/** The address a reading goes to, or null when it is not the supplier's. */
export function supplierFeedUrl(
  format: string,
  endpointTemplate: string,
  token: string,
): string | null {
  const host = FORMAT_HOSTS[format];
  if (!host || !token || !endpointTemplate.includes("{token}")) return null;
  let url: URL;
  try {
    url = new URL(endpointTemplate.replace("{token}", encodeURIComponent(token)));
  } catch (_) {
    return null;
  }
  if (url.protocol !== "https:" || url.hostname !== host || url.port || url.username) {
    return null;
  }
  return url.toString();
}

/** The seconds a `Retry-After` header asks for, whether it is a number or a
 * date. Null when it says nothing usable; never more than a day. */
export function retryAfterSeconds(header: string | null, nowMs: number): number | null {
  const value = (header ?? "").trim();
  if (!value) return null;
  let seconds: number;
  if (/^\d{1,9}$/.test(value)) {
    seconds = Number(value);
  } else {
    const date = Date.parse(value);
    if (!Number.isFinite(date)) return null;
    seconds = Math.ceil((date - nowMs) / 1000);
  }
  if (!Number.isFinite(seconds) || seconds <= 0) return null;
  return Math.min(seconds, 86_400);
}

function parseFeed(format: string, text: string): SupplierFeedParse {
  if (format === "mkr_csv_v1") return parseMkrCsvV1(text);
  return { ok: false, error: "unknown_format" };
}

function count(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

/** Runs the reading a ticket opens. The answer carries counts and codes,
 * never the address, the token or a product. */
export async function runSupplierFeedSync(params: {
  client: SupplierFeedClient;
  payload: unknown;
  fetchFn: SupplierFeedFetch;
  now?: () => number;
}): Promise<SupplierFeedAnswer> {
  const { client, payload, fetchFn } = params;
  const now = params.now ?? (() => Date.now());
  const started = now();
  const record = (payload && typeof payload === "object" ? payload : {}) as JsonRecord;
  const runId = typeof record.run_id === "string" ? record.run_id : "";
  const ticket = typeof record.token === "string" ? record.token : "";
  if (!RUN_ID.test(runId) || !RUN_TICKET.test(ticket)) {
    return { status: 400, body: { ok: false, error: "invalid_ticket" } };
  }

  const redeemed = await client.rpc("redeem_supplier_catalog_feed_sync", {
    p_run_id: runId,
    p_token: ticket,
  });
  if (redeemed.error) {
    return { status: 503, body: { ok: false, error: "redeem_failed" } };
  }
  const feed = (redeemed.data && typeof redeemed.data === "object" ? redeemed.data : null) as
    | JsonRecord
    | null;
  if (!feed) {
    return { status: 409, body: { ok: false, error: "ticket_refused" } };
  }

  const fail = async (code: string, httpStatus: number | null = null) => {
    await client.rpc("fail_supplier_catalog_feed_run_v1", {
      p_run_id: runId,
      p_error_code: code,
      p_http_status: httpStatus,
    });
    return { status: 200, body: { ok: false, error: code } } as SupplierFeedAnswer;
  };

  try {
    const format = typeof feed.format === "string" ? feed.format : "";
    const url = supplierFeedUrl(
      format,
      typeof feed.endpoint_template === "string" ? feed.endpoint_template : "",
      typeof feed.token === "string" ? feed.token : "",
    );
    if (!url) return await fail("address_not_allowed");

    const abort = new AbortController();
    const timer = setTimeout(() => abort.abort(), FETCH_TIMEOUT_MS);
    let response: Response;
    let text: string;
    try {
      response = await fetchFn(url, {
        signal: abort.signal,
        redirect: "error",
        headers: { Accept: "text/csv, text/plain;q=0.9, */*;q=0.1" },
      });
      if (!response.ok) {
        const wait = retryAfterSeconds(response.headers.get("retry-after"), now());
        await response.body?.cancel();
        // The supplier refuses a second download too soon after the first
        // (MKR, 2026-11-19: 429 a minute later). How long it asks to wait is
        // the only thing worth keeping from that answer.
        const code = wait === null
          ? `http_${response.status}`
          : `http_${response.status}_retry_${wait}`;
        return await fail(code, response.status);
      }
      text = await response.text();
    } catch (_) {
      return await fail(abort.signal.aborted ? "fetch_timeout" : "fetch_failed");
    } finally {
      clearTimeout(timer);
    }
    if (text.length > MAX_FEED_CHARS) return await fail("too_large", response.status);

    const parsed = parseFeed(format, text);
    if (!parsed.ok) return await fail(parsed.error, response.status);
    const rows = parsed.rows;
    const bytes = Number(response.headers.get("content-length")) || text.length;

    const needContent = new Set<string>();
    const totals = { new: 0, stock_changes: 0, price_changes: 0 };
    for (let offset = 0; offset < rows.length; offset += ROWS_PER_CALL) {
      const applied = await client.rpc("apply_supplier_catalog_feed_rows_v1", {
        p_run_id: runId,
        p_rows: rows.slice(offset, offset + ROWS_PER_CALL).map((row) => [
          row.sku,
          row.productCode,
          row.barcode,
          row.stock,
          row.price,
          row.priceBefore,
          row.priceOffer,
          row.suggestedRetail,
          row.contentHash,
        ]),
      });
      if (applied.error) return await fail("apply_rows_failed", response.status);
      const answer = (applied.data ?? {}) as JsonRecord;
      totals.new += count(answer.new);
      totals.stock_changes += count(answer.stock_changes);
      totals.price_changes += count(answer.price_changes);
      if (Array.isArray(answer.need_content)) {
        for (const code of answer.need_content) {
          if (typeof code === "string") needContent.add(code);
        }
      }
    }

    let contentChanges = 0;
    let batch: unknown[][] = [];
    let batchChars = 0;
    const flush = async (): Promise<boolean> => {
      if (batch.length === 0) return true;
      const applied = await client.rpc("apply_supplier_catalog_feed_content_v1", {
        p_run_id: runId,
        p_rows: batch,
      });
      batch = [];
      batchChars = 0;
      if (applied.error) return false;
      contentChanges += count(applied.data);
      return true;
    };
    for (const row of rows) {
      if (!needContent.has(row.sku)) continue;
      const size = row.name.length + (row.description?.length ?? 0) + 400;
      if (
        batch.length >= CONTENT_ROWS_PER_CALL ||
        (batch.length > 0 && batchChars + size > CONTENT_CHARS_PER_CALL)
      ) {
        if (!(await flush())) return await fail("apply_content_failed", response.status);
      }
      batch.push([row.sku, row.name, row.brand, row.description, row.photos, row.contentHash]);
      batchChars += size;
    }
    if (!(await flush())) return await fail("apply_content_failed", response.status);

    const finished = await client.rpc("finish_supplier_catalog_feed_run_v1", {
      p_run_id: runId,
      p_skus: rows.map((row) => row.sku),
      p_stats: {
        http_status: response.status,
        bytes,
        duration_ms: Math.max(0, Math.round(now() - started)),
      },
    });
    if (finished.error) return await fail("finish_failed", response.status);
    const closing = (finished.data ?? {}) as JsonRecord;
    return {
      status: 200,
      body: {
        ok: closing.status === "ok",
        status: typeof closing.status === "string" ? closing.status : "unknown",
        rows: rows.length,
        skipped: parsed.skipped,
        new: totals.new,
        stock_changes: totals.stock_changes,
        price_changes: totals.price_changes,
        content_changes: contentChanges,
        delisted: count(closing.delisted),
        in_stock: count(closing.in_stock),
      },
    };
  } catch (_) {
    return await fail("reader_error");
  }
}
