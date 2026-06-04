import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-vinabike-relay-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const defaultAllowedHosts = "186.67.65.199";
const maxRedirects = 5;

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function parseAllowedUrl(rawUrl: string): URL {
  let parsed: URL;
  try {
    parsed = new URL(rawUrl);
  } catch (_) {
    throw new Error("URL invalida.");
  }

  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    throw new Error("Solo se permiten URLs http o https.");
  }

  const allowedHosts = new Set(
    (Deno.env.get("DOCUMENT_RELAY_ALLOWED_HOSTS") ?? defaultAllowedHosts)
      .split(",")
      .map((host) => host.trim().toLowerCase())
      .filter(Boolean),
  );

  if (!allowedHosts.has(parsed.hostname.toLowerCase())) {
    throw new Error(`Host no permitido: ${parsed.hostname}`);
  }

  return parsed;
}

function isAuthorized(req: Request): boolean {
  const expected = (Deno.env.get("DOCUMENT_RELAY_SHARED_TOKEN") ?? "").trim();
  if (!expected) return false;

  const relayToken = (req.headers.get("X-Vinabike-Relay-Token") ?? "").trim();
  const bearer = (req.headers.get("Authorization") ?? "")
    .replace(/^Bearer\s+/i, "")
    .trim();

  return relayToken === expected || bearer === expected;
}

async function fetchWithRedirects(
  initialUrl: string,
): Promise<{ response: Response; finalUrl: string }> {
  let currentUrl = initialUrl;
  const timeoutMs = Number(
    Deno.env.get("DOCUMENT_RELAY_FETCH_TIMEOUT_MS") ?? "60000",
  );

  for (let redirectCount = 0; redirectCount <= maxRedirects; redirectCount++) {
    const parsed = parseAllowedUrl(currentUrl);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);

    let response: Response;
    try {
      response = await fetch(parsed.toString(), {
        redirect: "manual",
        signal: controller.signal,
        headers: {
          "User-Agent":
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
          "Accept": "application/pdf,application/octet-stream,*/*",
        },
      });
    } finally {
      clearTimeout(timeout);
    }

    const location = response.headers.get("Location");
    if (response.status >= 300 && response.status < 400 && location) {
      currentUrl = new URL(location, parsed).toString();
      continue;
    }

    return { response, finalUrl: parsed.toString() };
  }

  throw new Error("Demasiados redirects.");
}

async function responseBytes(response: Response): Promise<Uint8Array> {
  const maxBytes = Number(
    Deno.env.get("DOCUMENT_RELAY_MAX_BYTES") ?? String(25 * 1024 * 1024),
  );
  const declaredLength = Number(response.headers.get("Content-Length") ?? "0");
  if (declaredLength > maxBytes) {
    throw new Error("Documento demasiado grande.");
  }

  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.length > maxBytes) {
    throw new Error("Documento demasiado grande.");
  }
  return bytes;
}

function cleanMimeType(value: string | null): string {
  const cleaned = value?.split(";")[0]?.trim().toLowerCase();
  return cleaned && cleaned.includes("/") ? cleaned : "application/pdf";
}

function fileNameFromContentDisposition(value: string | null): string | null {
  if (!value) return null;

  const utfMatch = value.match(/filename\*=UTF-8''([^;]+)/i);
  if (utfMatch?.[1]) {
    return decodeURIComponent(utfMatch[1].replaceAll('"', "").trim());
  }

  const match = value.match(/filename="?([^";]+)"?/i);
  return match?.[1]?.trim() ?? null;
}

function safeFileName(value: string | null, fallback: string): string {
  const raw = value?.trim() || fallback;
  const clean = raw
    .split(/[\\/]/)
    .pop()!
    .replaceAll(/[^A-Za-z0-9._ -]+/g, "_")
    .replaceAll(/_+/g, "_")
    .trim();

  const name = clean || fallback;
  return name.toLowerCase().endsWith(".pdf") ? name : `${name}.pdf`;
}

function fallbackFileName(sourceUrl: string): string {
  const parsed = new URL(sourceUrl);
  const segment = parsed.pathname.split("/").filter(Boolean).pop();
  if (segment && segment.toLowerCase() !== "getpdf.php") {
    return safeFileName(segment, "documento.pdf");
  }
  return `documento_${parsed.hostname.replaceAll(/[^A-Za-z0-9]+/g, "_")}.pdf`;
}

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return jsonResponse({ error: "Method not allowed" }, 405);
    }

    if (!isAuthorized(req)) {
      return jsonResponse({ error: "Token de relay invalido." }, 401);
    }

    const body = await req.json() as { url?: string; tenantId?: string };
    const sourceUrl = body.url?.trim() ?? "";
    if (!sourceUrl) {
      return jsonResponse({ error: "Falta URL del documento." }, 400);
    }

    const parsedSource = parseAllowedUrl(sourceUrl);
    const { response, finalUrl } = await fetchWithRedirects(
      parsedSource.toString(),
    );

    if (response.status < 200 || response.status >= 300) {
      return jsonResponse(
        {
          error: `Servidor remoto respondio HTTP ${response.status}.`,
          remoteStatusCode: response.status,
        },
        502,
      );
    }

    const bytes = await responseBytes(response);
    const mimeType = cleanMimeType(response.headers.get("Content-Type"));
    const fileName = safeFileName(
      fileNameFromContentDisposition(
        response.headers.get("Content-Disposition"),
      ),
      fallbackFileName(finalUrl),
    );

    return new Response(bytes, {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": mimeType,
        "Content-Length": String(bytes.length),
        "Content-Disposition": `inline; filename="${fileName}"`,
        "X-Vinabike-Relay": "supabase-edge-document-relay",
        "X-Vinabike-Remote-Status": String(response.status),
      },
    });
  } catch (error) {
    console.error("[chile-document-relay]", error);
    return jsonResponse(
      {
        error: error instanceof Error ? error.message : String(error),
      },
      500,
    );
  }
});
