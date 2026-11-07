// El PDF de un aviso del taller (20261107130000): el presupuesto o el
// comprobante que viaja arriba del mensaje de WhatsApp. Lo dibuja el servidor
// de la tienda con los mismos dibujos que ve el cliente en su cuenta; la base
// deja en el aviso un código de un solo uso y whatsapp-send lo canjea aquí,
// sube el PDF a Meta y lo manda por id. El código viaja en el cuerpo de la
// petición, nunca en la dirección: no queda en registros de acceso.

export const workshopNoticeDocumentPath = "/cuenta/aviso.pdf";

/// Un presupuesto o un comprobante pesa decenas de KB; Meta acepta hasta
/// 100 MB, pero nada de un aviso debería acercarse a esto.
export const workshopNoticeDocumentMaxBytes = 5 * 1024 * 1024;

const tokenPattern = /^[A-Za-z0-9_-]{43}$/;
const hostPattern = /^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/;

/// 32 bytes al azar en base64url sin relleno: 43 caracteres.
export function isWorkshopNoticeDocumentToken(value: unknown): value is string {
  return typeof value === "string" && tokenPattern.test(value);
}

/// El origen de la tienda al que se le pide el PDF: sólo https y un nombre de
/// host público (sin IP, puerto, usuario ni ruta). Sale de la configuración
/// de la tienda en el servidor, nunca de la petición de envío.
export function workshopNoticeDocumentOrigin(storeUrl: unknown): string | null {
  if (typeof storeUrl !== "string") return null;
  let url: URL;
  try {
    url = new URL(storeUrl.trim());
  } catch (_error) {
    return null;
  }
  if (url.protocol !== "https:" || url.username || url.password || url.port) {
    return null;
  }
  const host = url.hostname.toLowerCase();
  return hostPattern.test(host) ? `https://${host}` : null;
}

export interface WorkshopNoticeDocument {
  bytes: Uint8Array;
  filename: string;
}

export type WorkshopNoticeDocumentResult =
  | { document: WorkshopNoticeDocument }
  | {
    error:
      | "store_url_invalid"
      | "token_invalid"
      | "store_unreachable"
      | "store_refused"
      | "not_a_pdf"
      | "too_large";
    status?: number;
  };

/// El nombre con que lo ve el cliente, del `content-disposition` de la
/// tienda («Presupuesto PG-00671.pdf»); sin uno usable, «documento.pdf».
export function workshopNoticeDocumentFilename(disposition: string | null): string {
  const quoted = /filename="([^"]{1,120})"/i.exec(disposition ?? "")?.[1];
  const bare = /filename=([^;\s"]{1,120})/i.exec(disposition ?? "")?.[1];
  const raw = (quoted ?? bare ?? "").replace(/[\\/\u0000-\u001f]/g, "").trim();
  if (!raw || raw.startsWith(".")) return "documento.pdf";
  return /\.pdf$/i.test(raw) ? raw : `${raw}.pdf`;
}

function startsWithPdfMagic(bytes: Uint8Array): boolean {
  // «%PDF-»
  return bytes.length >= 5 && bytes[0] === 0x25 && bytes[1] === 0x50 &&
    bytes[2] === 0x44 && bytes[3] === 0x46 && bytes[4] === 0x2d;
}

/// Pide el PDF de [token] a la tienda en [storeUrl] y lo valida: respuesta
/// 200, `application/pdf`, que empiece como PDF y que no pase del tope.
export async function fetchWorkshopNoticeDocument(params: {
  storeUrl: unknown;
  token: unknown;
  fetchImpl?: typeof fetch;
  timeoutMs?: number;
}): Promise<WorkshopNoticeDocumentResult> {
  const origin = workshopNoticeDocumentOrigin(params.storeUrl);
  if (!origin) return { error: "store_url_invalid" };
  if (!isWorkshopNoticeDocumentToken(params.token)) return { error: "token_invalid" };

  let response: Response;
  try {
    response = await (params.fetchImpl ?? fetch)(`${origin}${workshopNoticeDocumentPath}`, {
      method: "POST",
      headers: { "content-type": "application/json", accept: "application/pdf" },
      body: JSON.stringify({ token: params.token }),
      redirect: "error",
      signal: AbortSignal.timeout(params.timeoutMs ?? 25_000),
    });
  } catch (_error) {
    return { error: "store_unreachable" };
  }
  if (!response.ok) {
    await response.body?.cancel().catch(() => {});
    return { error: "store_refused", status: response.status };
  }
  const contentType = (response.headers.get("content-type") ?? "").toLowerCase();
  if (!contentType.startsWith("application/pdf")) {
    await response.body?.cancel().catch(() => {});
    return { error: "not_a_pdf" };
  }
  const declared = Number(response.headers.get("content-length") ?? "0");
  if (Number.isFinite(declared) && declared > workshopNoticeDocumentMaxBytes) {
    await response.body?.cancel().catch(() => {});
    return { error: "too_large" };
  }
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.byteLength > workshopNoticeDocumentMaxBytes) return { error: "too_large" };
  if (!startsWithPdfMagic(bytes)) return { error: "not_a_pdf" };
  return {
    document: {
      bytes,
      filename: workshopNoticeDocumentFilename(response.headers.get("content-disposition")),
    },
  };
}
