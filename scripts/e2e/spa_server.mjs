import {createReadStream, existsSync, statSync} from 'node:fs';
import {createServer} from 'node:http';
import {extname, join, normalize, resolve} from 'node:path';

const root = resolve(process.argv[2] ?? 'build/web_erp');
const port = Number(process.env.PORT ?? 4173);
const mimeTypes = {
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.ico': 'image/x-icon',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.wasm': 'application/wasm',
  '.webp': 'image/webp',
};

if (!existsSync(join(root, 'index.html'))) {
  throw new Error(`Missing Flutter web build at ${root}`);
}

createServer((request, response) => {
  const pathname = decodeURIComponent(new URL(request.url ?? '/', 'http://localhost').pathname);
  const requested = resolve(root, `.${normalize(pathname)}`);
  const safeFile = requested.startsWith(`${root}/`) && existsSync(requested) && statSync(requested).isFile();
  const file = safeFile ? requested : join(root, 'index.html');

  response.writeHead(200, {
    'cache-control': 'no-store',
    'content-type': mimeTypes[extname(file)] ?? 'application/octet-stream',
  });
  createReadStream(file).pipe(response);
}).listen(port, '127.0.0.1', () => {
  console.log(`ERP E2E server listening on http://127.0.0.1:${port}`);
});
