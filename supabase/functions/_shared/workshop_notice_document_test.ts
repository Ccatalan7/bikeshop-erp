import {
  fetchWorkshopNoticeDocument,
  isWorkshopNoticeDocumentToken,
  workshopNoticeDocumentFilename,
  workshopNoticeDocumentMaxBytes,
  workshopNoticeDocumentOrigin,
} from "./workshop_notice_document.ts";

function assertEquals(actual: unknown, expected: unknown, message = "") {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${message} expected ${e}, received ${a}`);
}

const token = "Zq81TfY0LwmR4pXc".padEnd(43, "x");
const pdf = new TextEncoder().encode("%PDF-1.4\n%fake\n");

function store(response: Response, seen: Request[] = []): typeof fetch {
  return ((input: Request | URL | string, init?: RequestInit) => {
    seen.push(new Request(input, init));
    return Promise.resolve(response.clone());
  }) as typeof fetch;
}

Deno.test("only the store's own https host is asked", () => {
  assertEquals(workshopNoticeDocumentOrigin("https://vinabike.cl/"), "https://vinabike.cl");
  assertEquals(workshopNoticeDocumentOrigin(" https://www.vinabike.cl "), "https://www.vinabike.cl");
  for (const value of [
    "http://vinabike.cl",
    "https://127.0.0.1",
    "https://localhost",
    "https://vinabike.cl:8443",
    "https://user:pass@vinabike.cl",
    "ftp://vinabike.cl",
    "",
    null,
  ]) {
    assertEquals(workshopNoticeDocumentOrigin(value), null, String(value));
  }
});

Deno.test("the token is the 43-character base64url code the database mints", () => {
  assertEquals(isWorkshopNoticeDocumentToken(token), true);
  assertEquals(isWorkshopNoticeDocumentToken(token.slice(1)), false);
  assertEquals(isWorkshopNoticeDocumentToken(`${token.slice(1)}/`), false);
  assertEquals(isWorkshopNoticeDocumentToken(undefined), false);
});

Deno.test("the customer sees the store's file name, always a PDF", () => {
  assertEquals(
    workshopNoticeDocumentFilename('attachment; filename="Presupuesto PG-00671.pdf"'),
    "Presupuesto PG-00671.pdf",
  );
  assertEquals(workshopNoticeDocumentFilename("attachment; filename=comprobante"), "comprobante.pdf");
  assertEquals(workshopNoticeDocumentFilename('attachment; filename="../x.pdf"'), "documento.pdf");
  assertEquals(workshopNoticeDocumentFilename(null), "documento.pdf");
});

Deno.test("the PDF is asked with the code in the body, never in the address", async () => {
  const seen: Request[] = [];
  const result = await fetchWorkshopNoticeDocument({
    storeUrl: "https://vinabike.cl",
    token,
    fetchImpl: store(
      new Response(pdf, {
        headers: {
          "content-type": "application/pdf",
          "content-disposition": 'attachment; filename="Comprobante PG-00671.pdf"',
        },
      }),
      seen,
    ),
  });
  assertEquals("document" in result ? result.document.filename : result, "Comprobante PG-00671.pdf");
  assertEquals(seen[0].url, "https://vinabike.cl/cuenta/aviso.pdf");
  assertEquals(seen[0].method, "POST");
  assertEquals(await seen[0].json(), { token });
});

Deno.test("anything that is not a small real PDF is refused", async () => {
  const cases: [Response, string][] = [
    [new Response("no", { status: 404 }), "store_refused"],
    [new Response(pdf, { headers: { "content-type": "text/html" } }), "not_a_pdf"],
    [new Response("<html>", { headers: { "content-type": "application/pdf" } }), "not_a_pdf"],
    [
      new Response(new Uint8Array(workshopNoticeDocumentMaxBytes + 1), {
        headers: { "content-type": "application/pdf" },
      }),
      "too_large",
    ],
  ];
  for (const [response, expected] of cases) {
    const result = await fetchWorkshopNoticeDocument({
      storeUrl: "https://vinabike.cl",
      token,
      fetchImpl: store(response),
    });
    assertEquals("error" in result ? result.error : "document", expected, expected);
  }
  const unreachable = await fetchWorkshopNoticeDocument({
    storeUrl: "https://vinabike.cl",
    token,
    fetchImpl: (() => Promise.reject(new Error("down"))) as typeof fetch,
  });
  assertEquals("error" in unreachable ? unreachable.error : "document", "store_unreachable");
  const forged = await fetchWorkshopNoticeDocument({ storeUrl: "https://vinabike.cl", token: "x" });
  assertEquals("error" in forged ? forged.error : "document", "token_invalid");
});
