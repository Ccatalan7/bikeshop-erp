# Vinabike Edge Cache - Cloudflare Worker

This Cloudflare Worker caches Supabase RPC responses at edge locations worldwide,
reducing latency from ~700ms to ~50ms for most visitors.

## Setup Instructions

### 1. Install Wrangler CLI (if not already installed)

```bash
npm install -g wrangler
```

### 2. Login to Cloudflare

```bash
wrangler login
```

This will open a browser window to authenticate with your Cloudflare account.

### 3. Install dependencies

```bash
cd cloudflare-worker
npm install
```

### 4. Deploy the Worker

```bash
npm run deploy
```

After deployment, you'll get a URL like:
```
https://vinabike-edge-cache.YOUR_SUBDOMAIN.workers.dev
```

### 5. Test the Worker

```bash
# Test health endpoint
curl https://vinabike-edge-cache.YOUR_SUBDOMAIN.workers.dev/health

# Test cache endpoint
curl -X POST https://vinabike-edge-cache.YOUR_SUBDOMAIN.workers.dev/cache/public-store-data \
  -H "Content-Type: application/json" \
  -d '{"p_tenant_id": "5443b130-cc28-45af-a420-cd500b288890"}'
```

### 6. Update Flutter App

After deployment, update the Flutter app to use the cached endpoint.
The WebsiteService will need to call the worker URL instead of Supabase directly.

## How it Works

1. First request hits Cloudflare edge in user's region (e.g., Santiago, Chile)
2. Edge checks cache - if MISS, fetches from Supabase (~700ms)
3. Response is cached at edge for 5 minutes
4. Subsequent requests from ANY user in that region get cached response (~50ms)

## Response Headers

- `X-Cache: HIT` or `X-Cache: MISS` - indicates cache status
- `X-Edge-Location: SCL` - Cloudflare edge location code (e.g., SCL = Santiago)

## Cache Invalidation

Cache expires after 5 minutes (CACHE_TTL_SECONDS).
To manually invalidate, you can:
1. Redeploy the worker
2. Change the cache key logic
3. Use Cloudflare's Cache Purge API
