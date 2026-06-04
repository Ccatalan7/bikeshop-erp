const http = require('http');
const { URL } = require('url');

if (typeof fetch !== 'function') {
  console.error('Node 18+ is required because this relay uses native fetch().');
  process.exit(1);
}

const PORT = Number(process.env.PORT || 8787);
const SHARED_TOKEN = (process.env.DOCUMENT_RELAY_SHARED_TOKEN || '').trim();
const ALLOWED_HOSTS = new Set(
  (process.env.DOCUMENT_RELAY_ALLOWED_HOSTS || '186.67.65.199')
    .split(',')
    .map((host) => host.trim().toLowerCase())
    .filter(Boolean),
);
const MAX_BYTES = Number(process.env.DOCUMENT_RELAY_MAX_BYTES || 25 * 1024 * 1024);
const FETCH_TIMEOUT_MS = Number(process.env.DOCUMENT_RELAY_FETCH_TIMEOUT_MS || 60000);
const MAX_REDIRECTS = 5;

function withCors(headers = {}) {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    'Access-Control-Allow-Headers':
      'Authorization,Content-Type,X-Vinabike-Relay-Token',
    ...headers,
  };
}

function sendJson(res, statusCode, payload) {
  res.writeHead(
    statusCode,
    withCors({
      'Content-Type': 'application/json; charset=utf-8',
    }),
  );
  res.end(JSON.stringify(payload));
}

function isAuthorized(req) {
  if (!SHARED_TOKEN) return true;

  const relayToken = String(req.headers['x-vinabike-relay-token'] || '').trim();
  const bearer = String(req.headers.authorization || '')
    .replace(/^Bearer\s+/i, '')
    .trim();

  return relayToken === SHARED_TOKEN || bearer === SHARED_TOKEN;
}

function parseAllowedUrl(rawUrl) {
  let parsed;
  try {
    parsed = new URL(rawUrl);
  } catch (_) {
    throw new Error('URL invalida.');
  }

  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    throw new Error('Solo se permiten URLs http o https.');
  }

  if (!ALLOWED_HOSTS.has(parsed.hostname.toLowerCase())) {
    throw new Error(`Host no permitido: ${parsed.hostname}`);
  }

  return parsed;
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;

    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > 32 * 1024) {
        reject(new Error('Body demasiado grande.'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });

    req.on('end', () => {
      try {
        const text = Buffer.concat(chunks).toString('utf8');
        resolve(text ? JSON.parse(text) : {});
      } catch (_) {
        reject(new Error('JSON invalido.'));
      }
    });

    req.on('error', reject);
  });
}

async function fetchWithRedirects(initialUrl) {
  let currentUrl = initialUrl;

  for (let redirectCount = 0; redirectCount <= MAX_REDIRECTS; redirectCount += 1) {
    const parsed = parseAllowedUrl(currentUrl);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);

    let response;
    try {
      response = await fetch(parsed.toString(), {
        redirect: 'manual',
        signal: controller.signal,
        headers: {
          'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ' +
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15',
          Accept: 'application/pdf,application/octet-stream,*/*',
        },
      });
    } finally {
      clearTimeout(timeout);
    }

    if (
      response.status >= 300 &&
      response.status < 400 &&
      response.headers.get('location')
    ) {
      currentUrl = new URL(response.headers.get('location'), parsed).toString();
      continue;
    }

    return { response, finalUrl: parsed.toString() };
  }

  throw new Error('Demasiados redirects.');
}

async function responseToBuffer(response) {
  const declaredLength = Number(response.headers.get('content-length') || 0);
  if (declaredLength > MAX_BYTES) {
    throw new Error('Documento demasiado grande.');
  }

  const arrayBuffer = await response.arrayBuffer();
  const buffer = Buffer.from(arrayBuffer);
  if (buffer.length > MAX_BYTES) {
    throw new Error('Documento demasiado grande.');
  }

  return buffer;
}

function cleanMimeType(value) {
  if (!value) return null;
  return String(value).split(';')[0].trim().toLowerCase() || null;
}

function fileNameFromDisposition(value) {
  if (!value) return null;

  const utfMatch = String(value).match(/filename\*=UTF-8''([^;]+)/i);
  if (utfMatch) {
    return decodeURIComponent(utfMatch[1].replace(/"/g, '').trim());
  }

  const match = String(value).match(/filename="?([^";]+)"?/i);
  return match ? match[1].trim() : null;
}

function safeFileName(value, fallback = 'documento.pdf') {
  const raw = value && String(value).trim() ? String(value).trim() : fallback;
  const clean = raw
    .split(/[\\/]/)
    .pop()
    .replace(/[^A-Za-z0-9._ -]+/g, '_')
    .replace(/_+/g, '_')
    .trim();

  const name = clean || fallback;
  return name.toLowerCase().endsWith('.pdf') ? name : `${name}.pdf`;
}

function fallbackFileName(sourceUrl) {
  const parsed = new URL(sourceUrl);
  const segment = parsed.pathname.split('/').filter(Boolean).pop();
  if (segment && segment.toLowerCase() !== 'getpdf.php') {
    return safeFileName(segment);
  }
  return `documento_${parsed.hostname.replace(/[^A-Za-z0-9]+/g, '_')}.pdf`;
}

async function handleFetchDocument(req, res) {
  if (!isAuthorized(req)) {
    sendJson(res, 401, { error: 'Token de relay invalido.' });
    return;
  }

  const body = await readJsonBody(req);
  const sourceUrl = String(body.url || '').trim();
  const parsedSource = parseAllowedUrl(sourceUrl);

  const { response, finalUrl } = await fetchWithRedirects(parsedSource.toString());
  if (response.status < 200 || response.status >= 300) {
    sendJson(res, 502, {
      error: `Servidor remoto respondio HTTP ${response.status}.`,
      remoteStatusCode: response.status,
    });
    return;
  }

  const bytes = await responseToBuffer(response);
  const mimeType = cleanMimeType(response.headers.get('content-type')) || 'application/pdf';
  const fileName = safeFileName(
    fileNameFromDisposition(response.headers.get('content-disposition')),
    fallbackFileName(finalUrl),
  );

  res.writeHead(
    200,
    withCors({
      'Content-Type': mimeType,
      'Content-Length': String(bytes.length),
      'Content-Disposition': `inline; filename="${fileName}"`,
      'X-Vinabike-Relay': 'chile-document-relay',
      'X-Vinabike-Remote-Status': String(response.status),
    }),
  );
  res.end(bytes);
}

const server = http.createServer(async (req, res) => {
  try {
    if (req.method === 'OPTIONS') {
      res.writeHead(204, withCors());
      res.end();
      return;
    }

    if (req.method === 'GET' && req.url === '/health') {
      sendJson(res, 200, {
        ok: true,
        service: 'vinabike-chile-document-relay',
        allowedHosts: Array.from(ALLOWED_HOSTS),
      });
      return;
    }

    if (req.method === 'POST' && req.url === '/fetch-document') {
      await handleFetchDocument(req, res);
      return;
    }

    sendJson(res, 404, { error: 'Ruta no encontrada.' });
  } catch (error) {
    sendJson(res, 500, {
      error: error && error.message ? error.message : 'Error inesperado.',
    });
  }
});

server.listen(PORT, () => {
  console.log(
    `Vinabike Chile document relay listening on :${PORT}; allowed hosts: ${
      Array.from(ALLOWED_HOSTS).join(', ') || '(none)'
    }`,
  );
});
