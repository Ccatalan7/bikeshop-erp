import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  BODY_TEXT_LIMIT,
  bytesToBase64,
  decodeEntitiesDeep,
  decodeMimeWords,
  gmailIgnored,
  gmailMessageToRecord,
  gmailPartData,
  htmlToText,
  parseAddress,
  parseAddressList,
  parseRawHeaders,
  zohoAttachments,
  zohoMessageToRecord,
} from "./mail_sync_parse.ts";

function b64url(
  text: string,
  encoder: (text: string) => Uint8Array = (t) => new TextEncoder().encode(t),
) {
  return bytesToBase64(encoder(text)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function latin1(text: string): Uint8Array {
  return new Uint8Array([...text].map((ch) => ch.charCodeAt(0) & 0xff));
}

Deno.test("addresses keep the person and fold the address", () => {
  assertEquals(parseAddress('"Comercial Ejemplo SpA" <Ventas@Ejemplo.invalid>'), {
    name: "Comercial Ejemplo SpA",
    address: "ventas@ejemplo.invalid",
  });
  assertEquals(parseAddress("solo@ejemplo.invalid"), {
    name: null,
    address: "solo@ejemplo.invalid",
  });
  assertEquals(
    parseAddressList('"Pérez, Ana" <ana@ejemplo.invalid>, b@ejemplo.invalid; Not Provided'),
    ["ana@ejemplo.invalid", "b@ejemplo.invalid"],
  );
  assertEquals(
    parseAddressList("&lt;contacto@tienda.invalid&gt;"),
    ["contacto@tienda.invalid"],
    "Zoho escapes the angle brackets",
  );
});

Deno.test("encoded words in names and subjects are decoded", () => {
  assertEquals(decodeMimeWords("=?ISO-8859-1?Q?Mu=F1oz?="), "Muñoz");
  assertEquals(decodeMimeWords("=?UTF-8?B?wr9QYXJhIGN1w6FuZG8/?="), "¿Para cuándo?");
  assertEquals(decodeMimeWords("Hola =?UTF-8?Q?mec=C3=A1nico?= y más"), "Hola mecánico y más");
});

Deno.test("html becomes readable text without styles or scripts", () => {
  const text = htmlToText(
    "<html><head><style>p{color:red}</style></head><body><p>Monto:&nbsp;$45.990</p>" +
      "<script>alert(1)</script><div>Nombre del originante: Ana&#32;P&eacute;rez</div><br>Fin</body></html>",
  );
  assertEquals(text, "Monto: $45.990\nNombre del originante: Ana Pérez\n\nFin");
});

Deno.test("a Gmail message keeps headers, latin-1 text, attachments and labels", () => {
  const message = {
    id: "m1",
    threadId: "t1",
    labelIds: ["INBOX", "UNREAD", "CATEGORY_UPDATES"],
    snippet: "Le informamos que &#39;se realizó&#39;",
    internalDate: String(Date.parse("2026-10-20T13:14:16Z")),
    payload: {
      mimeType: "multipart/mixed",
      headers: [
        { name: "From", value: "Banco Ejemplo <avisos@banco.invalid>" },
        { name: "To", value: "Tienda <contacto@tienda.invalid>" },
        { name: "Subject", value: "Aviso de transferencia de fondos" },
        { name: "Message-ID", value: "<abc123@banco.invalid>" },
        { name: "In-Reply-To", value: "<prev@tienda.invalid>" },
        { name: "References", value: "<root@tienda.invalid> <prev@tienda.invalid>" },
      ],
      parts: [
        {
          partId: "0",
          mimeType: "text/plain",
          headers: [{ name: "Content-Type", value: "text/plain; charset=ISO-8859-1" }],
          body: { data: b64url("Monto: $45.990\nNombre del originante: Ana Pérez", latin1) },
        },
        {
          partId: "1",
          mimeType: "application/xml",
          filename: "DTE_123.xml",
          headers: [{ name: "Content-Disposition", value: 'attachment; filename="DTE_123.xml"' }],
          body: { size: 2048, attachmentId: "att-1" },
        },
        {
          partId: "2",
          mimeType: "image/png",
          filename: "logo.png",
          headers: [{ name: "Content-ID", value: "<logo>" }],
          body: { size: 300, data: b64url("png") },
        },
      ],
    },
  };
  const record = gmailMessageToRecord(message);
  assert(record);
  assertEquals(record.from_address, "avisos@banco.invalid");
  assertEquals(record.from_name, "Banco Ejemplo");
  assertEquals(record.to_addresses, ["contacto@tienda.invalid"]);
  assertEquals(record.body_text, "Monto: $45.990\nNombre del originante: Ana Pérez");
  assertEquals(record.snippet, "Le informamos que 'se realizó'");
  assertEquals(record.rfc_message_id, "abc123@banco.invalid");
  assertEquals(record.in_reply_to, "prev@tienda.invalid");
  assertEquals(record.reference_ids, ["root@tienda.invalid", "prev@tienda.invalid"]);
  assertEquals(record.direction, "in");
  assertEquals(record.provider_read, false);
  assertEquals(record.in_inbox, true);
  assertEquals(record.is_bulk, false);
  assertEquals(record.has_attachments, true, "the XML counts, the inline logo does not");
  assertEquals(
    record.attachments.map((a) => [a.filename, a.inline, a.attachment_id ?? a.part_id]),
    [
      ["DTE_123.xml", false, "att-1"],
      ["logo.png", true, "2"],
    ],
  );
  assertEquals(record.received_at, "2026-10-20T13:14:16.000Z");
  assertEquals(gmailPartData(message, "2"), b64url("png"));
});

Deno.test("entities encoded twice still read as letters", () => {
  assertEquals(decodeEntitiesDeep("Ver la p&amp;aacute;gina"), "Ver la página");
  assertEquals(htmlToText("<p>Ver la p&amp;aacute;gina</p>"), "Ver la página");
  assertEquals(decodeEntitiesDeep("Tom &amp; Jerry"), "Tom & Jerry");
});

Deno.test("a bank text part with glued cells gives way to its html", () => {
  const plain = "Aviso de transferencia\nNombreAna PérezCuenta de origenCuenta CorrienteCuenta de destinoCuenta VistaMonto$45.990";
  const html = "<p>Aviso de transferencia</p><table><tr><td>Nombre</td><td>Ana Pérez</td></tr>" +
    "<tr><td>Cuenta de origen</td><td>Cuenta Corriente</td></tr>" +
    "<tr><td>Cuenta de destino</td><td>Cuenta Vista</td></tr><tr><td>Monto</td><td>$45.990</td></tr></table>";
  const record = gmailMessageToRecord({
    id: "m-banco",
    labelIds: ["INBOX"],
    internalDate: "1760000000000",
    payload: {
      mimeType: "multipart/alternative",
      headers: [{ name: "From", value: "aviso@banco.invalid" }, { name: "Subject", value: "Transferencia" }],
      parts: [
        { mimeType: "text/plain", body: { data: b64url(plain) } },
        { mimeType: "text/html", body: { data: b64url(html) } },
      ],
    },
  });
  assert(record);
  assert(record.body_text?.includes("Cuenta de destino Cuenta Vista"), record.body_text ?? "");
});

Deno.test("a text part with css gives way to its html", () => {
  const plain = "Se ha creado una solicitud de envio\n@media screen and (max-width: 450px) {\nbody {\ndisplay: flex;\n}\n}\n.header {\nmargin-bottom: 20px;\n}\nTu orden de flete es 123";
  const html = "<html><head><style>.header{margin-bottom:20px}</style></head><body><p>Se ha creado una solicitud de envio</p><p>Tu orden de flete es 123</p></body></html>";
  const record = gmailMessageToRecord({
    id: "m-css",
    labelIds: ["INBOX"],
    internalDate: "1760000000000",
    payload: {
      mimeType: "multipart/alternative",
      headers: [{ name: "From", value: "aviso@courier.invalid" }, { name: "Subject", value: "Despacho" }],
      parts: [
        { mimeType: "text/plain", body: { data: b64url(plain) } },
        { mimeType: "text/html", body: { data: b64url(html) } },
      ],
    },
  });
  assert(record);
  assertEquals(record.body_text, "Se ha creado una solicitud de envio\nTu orden de flete es 123");
});

Deno.test("a good text part is kept over its html", () => {
  const record = gmailMessageToRecord({
    id: "m-texto",
    labelIds: ["INBOX"],
    internalDate: "1760000000000",
    payload: {
      mimeType: "multipart/alternative",
      headers: [{ name: "From", value: "cliente@correo.invalid" }, { name: "Subject", value: "Consulta" }],
      parts: [
        { mimeType: "text/plain", body: { data: b64url("Hola, ¿tienen la cadena de 12 velocidades en WhatsApp?") } },
        { mimeType: "text/html", body: { data: b64url("<div>Hola, ¿tienen la cadena de 12 velocidades en WhatsApp?</div><div>firma</div>") } },
      ],
    },
  });
  assert(record);
  assertEquals(record.body_text, "Hola, ¿tienen la cadena de 12 velocidades en WhatsApp?");
});

Deno.test("an html-only Gmail newsletter is bulk and readable", () => {
  const record = gmailMessageToRecord({
    id: "m2",
    labelIds: ["INBOX", "CATEGORY_PROMOTIONS"],
    internalDate: "1760000000000",
    payload: {
      mimeType: "text/html",
      headers: [
        { name: "From", value: "ofertas@marca.invalid" },
        { name: "Subject", value: "=?UTF-8?Q?Hasta_70=25_de_descuento?=" },
        { name: "List-Unsubscribe", value: "<mailto:baja@marca.invalid>" },
      ],
      body: { data: b64url("<p>Ofertas de <b>temporada</b></p>") },
    },
  });
  assert(record);
  assertEquals(record.subject, "Hasta 70% de descuento");
  assertEquals(record.body_text, "Ofertas de temporada");
  assertEquals(record.is_bulk, true);
  assertEquals(record.provider_read, true);
});

Deno.test("sent mail goes out and drafts or spam are never kept", () => {
  const record = gmailMessageToRecord({
    id: "m3",
    labelIds: ["SENT"],
    internalDate: "1760000000000",
    payload: {
      mimeType: "text/plain",
      headers: [{ name: "From", value: "contacto@tienda.invalid" }],
    },
  });
  assertEquals(record?.direction, "out");
  assertEquals(record?.in_inbox, false);
  assertEquals(gmailIgnored(["DRAFT"]), true);
  assertEquals(gmailIgnored(["SPAM", "UNREAD"]), true);
  assertEquals(gmailIgnored(["INBOX"]), false);
});

Deno.test("a long body is cut to what the store keeps", () => {
  const record = gmailMessageToRecord({
    id: "m4",
    labelIds: ["INBOX"],
    internalDate: "1760000000000",
    payload: { mimeType: "text/plain", body: { data: b64url("x".repeat(BODY_TEXT_LIMIT + 50)) } },
  });
  assertEquals(record?.body_text?.length, BODY_TEXT_LIMIT);
});

Deno.test("a Zoho message keeps folder, headers and attachments", () => {
  const headers = parseRawHeaders(
    "Message-ID: <z1@proveedor.invalid>\r\nIn-Reply-To: <x@tienda.invalid>\r\nReferences: <a@tienda.invalid>\r\n <x@tienda.invalid>\r\nList-Unsubscribe: <https://baja.invalid>\r\n",
  );
  assertEquals(headers.get("references"), "<a@tienda.invalid> <x@tienda.invalid>");
  const attachments = zohoAttachments({
    data: {
      attachments: [{ attachmentId: "9", attachmentName: "factura.pdf", attachmentSize: "1200" }],
    },
  });
  const record = zohoMessageToRecord(
    {
      messageId: "1700",
      folderId: "11",
      threadId: "55",
      subject: "Pedido 32913 confirmado",
      summary: "Gracias por su compra &amp; preferencia",
      sender: "Proveedor Ejemplo",
      fromAddress: "ventas@proveedor.invalid",
      toAddress: "&quot;Tienda&quot; &lt;contacto@tienda.invalid&gt;",
      ccAddress: "Not Provided",
      receivedTime: "1760000000000",
      status: "0",
      hasAttachment: "1",
    },
    { id: "11", kind: "inbox" },
    {
      html: "<div>Pedido <b>32913</b></div>",
      rawHeaders: "Message-ID: <z1@proveedor.invalid>\nIn-Reply-To: <x@tienda.invalid>\n",
      attachments,
    },
  );
  assert(record);
  assertEquals(record.from_address, "ventas@proveedor.invalid");
  assertEquals(record.from_name, "Proveedor Ejemplo");
  assertEquals(record.to_addresses, ["contacto@tienda.invalid"]);
  assertEquals(record.cc_addresses, []);
  assertEquals(record.snippet, "Gracias por su compra & preferencia");
  assertEquals(record.body_text, "Pedido 32913");
  assertEquals(record.rfc_message_id, "z1@proveedor.invalid");
  assertEquals(record.in_reply_to, "x@tienda.invalid");
  assertEquals(record.provider_folder_id, "11");
  assertEquals(record.provider_thread_id, "55");
  assertEquals(record.provider_read, false);
  assertEquals(record.has_attachments, true);
  assertEquals(record.attachments[0].attachment_id, "9");
  assertEquals(record.labels, ["INBOX"]);
});
