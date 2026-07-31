import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const tenantA = '5443b130-cc28-45af-a420-cd500b288890';
const tenantB = '72000000-0000-4000-8000-000000000002';

const workerSource = await readFile(
  new URL('../src/index.js', import.meta.url),
  'utf8',
);
const workerModule = await import(
  `data:text/javascript;base64,${Buffer.from(workerSource).toString('base64')}`
);
const worker = workerModule.default;

function requestFor(tenantId) {
  return new Request(
    'https://vinabike-edge-cache.test/cache/public-store-data',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_tenant_id: tenantId }),
    },
  );
}

function context() {
  const pending = [];
  return {
    pending,
    waitUntil(promise) {
      pending.push(promise);
    },
  };
}

function environment() {
  return {
    SUPABASE_URL: 'https://supabase.test',
    SUPABASE_ANON_KEY: 'publishable-test-key',
  };
}

test('tenant identity validator requires an exact flat ownership match', () => {
  assert.equal(
    workerModule.isTenantOwnedStoreData({ tenant_id: tenantA }, tenantA),
    true,
  );
  assert.equal(
    workerModule.isTenantOwnedStoreData({ tenant_id: tenantB }, tenantA),
    false,
  );
  assert.equal(workerModule.isTenantOwnedStoreData({}, tenantA), false);
  assert.equal(workerModule.isTenantOwnedStoreData([], tenantA), false);
});

test('cache miss preserves verified origin identity in body, header, and cache',
  async (t) => {
    let cachedResponse;
    const cache = {
      async match() {
        return undefined;
      },
      async put(_key, response) {
        cachedResponse = response;
      },
      async delete() {
        return false;
      },
    };
    Object.defineProperty(globalThis, 'caches', {
      configurable: true,
      value: { default: cache },
    });

    const originalFetch = globalThis.fetch;
    t.after(() => {
      globalThis.fetch = originalFetch;
      delete globalThis.caches;
    });
    globalThis.fetch = async () => Response.json({
      tenant_id: tenantA,
      settings: { store_name: 'Tienda A' },
      blocks: [],
      home_page_id: null,
    });

    const ctx = context();
    const response = await worker.fetch(
      requestFor(tenantA),
      environment(),
      ctx,
    );
    const body = await response.json();

    assert.equal(response.status, 200);
    assert.equal(response.headers.get('X-Tenant-ID'), tenantA);
    assert.equal(body.tenant_id, tenantA);
    assert.equal(body._cache, 'MISS');
    assert.equal(body.settings.store_name, 'Tienda A');

    await Promise.all(ctx.pending);
    const cachedBody = await cachedResponse.json();
    assert.equal(cachedBody.tenant_id, tenantA);
    assert.equal('_cache' in cachedBody, false);
  });

test('a mismatched cached tenant is evicted and cannot reach the caller',
  async (t) => {
    let deleted = false;
    const cache = {
      async match() {
        return Response.json({
          tenant_id: tenantB,
          settings: { store_name: 'Tienda B contaminada' },
        });
      },
      async put() {},
      async delete() {
        deleted = true;
        return true;
      },
    };
    Object.defineProperty(globalThis, 'caches', {
      configurable: true,
      value: { default: cache },
    });

    const originalFetch = globalThis.fetch;
    t.after(() => {
      globalThis.fetch = originalFetch;
      delete globalThis.caches;
    });
    globalThis.fetch = async () => Response.json({
      tenant_id: tenantA,
      settings: { store_name: 'Tienda A fresca' },
      blocks: [],
      home_page_id: null,
    });

    const ctx = context();
    const response = await worker.fetch(
      requestFor(tenantA),
      environment(),
      ctx,
    );
    const body = await response.json();

    assert.equal(deleted, true);
    assert.equal(body.tenant_id, tenantA);
    assert.equal(body.settings.store_name, 'Tienda A fresca');
    assert.equal(body._cache, 'MISS');
    await Promise.all(ctx.pending);
  });

test('a mismatched origin identity fails closed and is never cached',
  async (t) => {
    let putCount = 0;
    const cache = {
      async match() {
        return undefined;
      },
      async put() {
        putCount += 1;
      },
      async delete() {
        return false;
      },
    };
    Object.defineProperty(globalThis, 'caches', {
      configurable: true,
      value: { default: cache },
    });

    const originalFetch = globalThis.fetch;
    t.after(() => {
      globalThis.fetch = originalFetch;
      delete globalThis.caches;
    });
    globalThis.fetch = async () => Response.json({
      tenant_id: tenantB,
      settings: { store_name: 'Tienda B' },
      blocks: [],
      home_page_id: null,
    });

    const ctx = context();
    const response = await worker.fetch(
      requestFor(tenantA),
      environment(),
      ctx,
    );

    assert.equal(response.status, 502);
    assert.deepEqual(await response.json(), {
      error: 'Tenant identity mismatch',
    });
    assert.equal(putCount, 0);
    assert.equal(ctx.pending.length, 0);
  });
