/**
 * Cloudflare Worker: Supabase Edge Cache
 * 
 * This worker caches Supabase RPC responses at Cloudflare's edge,
 * reducing latency from ~700ms to ~50ms for most visitors.
 * 
 * Deploy: npx wrangler deploy
 */

// Cache TTL: Balance between performance and freshness
// - 300s (5 min) = good cache hit ratio, 90% of visitors get fast response
// - 60s = updates visible within 1 minute, but more cache misses
const CACHE_TTL_SECONDS = 300; // 5 minutes

// Allowed tenant IDs (security - only cache for known tenants)
const ALLOWED_TENANTS = [
    '5443b130-cc28-45af-a420-cd500b288890', // vinabike
];

export function isTenantOwnedStoreData(data, expectedTenantId) {
    return Boolean(
        data
        && typeof data === 'object'
        && !Array.isArray(data)
        && typeof expectedTenantId === 'string'
        && expectedTenantId.length > 0
        && data.tenant_id === expectedTenantId
    );
}

export default {
    async fetch(request, env, ctx) {
        // Only handle POST requests to our cache endpoint
        const url = new URL(request.url);

        // CORS preflight
        if (request.method === 'OPTIONS') {
            return handleCORS();
        }

        // Main endpoint: /cache/public-store-data
        if (url.pathname === '/cache/public-store-data' && request.method === 'POST') {
            return handlePublicStoreData(request, env, ctx);
        }

        // Cache purge endpoint: /cache/purge
        // Call this after updating website content to clear the cache
        if (url.pathname === '/cache/purge' && request.method === 'POST') {
            return handleCachePurge(request);
        }

        // Health check
        if (url.pathname === '/health') {
            return new Response(JSON.stringify({
                status: 'ok',
                edge: request.cf?.colo,
                cache_ttl: CACHE_TTL_SECONDS
            }), {
                headers: { 'Content-Type': 'application/json' }
            });
        }

        return new Response('Not Found', { status: 404 });
    },

    // Cron trigger: Keep Supabase warm every 4 minutes
    async scheduled(event, env, ctx) {
        console.log('🔥 Warm-up cron triggered');
        const { supabaseUrl, supabaseAnonKey } = getSupabaseConfig(env);

        // Ping Supabase RPC for each allowed tenant to keep the function warm
        for (const tenantId of ALLOWED_TENANTS) {
            try {
                const response = await fetch(`${supabaseUrl}/rest/v1/rpc/get_public_store_data`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'apikey': supabaseAnonKey,
                        'Authorization': `Bearer ${supabaseAnonKey}`
                    },
                    body: JSON.stringify({ p_tenant_id: tenantId })
                });

                console.log(`🔥 Warm-up for tenant ${tenantId}: ${response.status}`);
            } catch (error) {
                console.error(`❌ Warm-up failed for tenant ${tenantId}:`, error.message);
            }
        }
    }
};

async function handlePublicStoreData(request, env, ctx) {
    try {
        const { supabaseUrl, supabaseAnonKey } = getSupabaseConfig(env);
        const body = await request.json();
        const tenantId = body.p_tenant_id;

        // Security: Only allow known tenants
        if (!ALLOWED_TENANTS.includes(tenantId)) {
            return new Response(JSON.stringify({ error: 'Invalid tenant' }), {
                status: 403,
                headers: corsHeaders()
            });
        }

        // Create cache key
        const cacheKey = new Request(`https://cache.vinabike.cl/public-store-data/${tenantId}`, {
            method: 'GET'
        });

        // Check cache first
        const cache = caches.default;
        const response = await cache.match(cacheKey);

        if (response) {
            let cachedData = null;
            try {
                // Clone before reading so we don't consume the cached body stream.
                cachedData = await response.clone().json();
            } catch (_) {
                // A malformed legacy entry is untrusted and repaired below.
            }

            if (isTenantOwnedStoreData(cachedData, tenantId)) {
                console.log(`Cache HIT for tenant ${tenantId}`);
                return new Response(JSON.stringify({
                    ...cachedData,
                    _cache: 'HIT',
                    _edge: request.cf?.colo || 'unknown'
                }), {
                    headers: {
                        ...corsHeaders(),
                        'Content-Type': 'application/json',
                        'X-Cache': 'HIT',
                        'X-Edge-Location': request.cf?.colo || 'unknown',
                        'X-Tenant-ID': tenantId
                    }
                });
            }

            console.warn(`Discarding tenant-mismatched cache entry for ${tenantId}`);
            await cache.delete(cacheKey);
        }

        // Cache MISS - fetch from Supabase
        console.log(`Cache MISS for tenant ${tenantId}, fetching from Supabase`);

        const supabaseResponse = await fetch(`${supabaseUrl}/rest/v1/rpc/get_public_store_data`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'apikey': supabaseAnonKey,
                'Authorization': `Bearer ${supabaseAnonKey}`
            },
            body: JSON.stringify({ p_tenant_id: tenantId })
        });

        if (!supabaseResponse.ok) {
            const error = await supabaseResponse.text();
            console.error('Supabase error:', error);
            return new Response(JSON.stringify({ error: 'Supabase error', details: error }), {
                status: supabaseResponse.status,
                headers: corsHeaders()
            });
        }

        const data = await supabaseResponse.json();
        if (!isTenantOwnedStoreData(data, tenantId)) {
            console.error(`Supabase returned data without the requested tenant identity for ${tenantId}`);
            return new Response(JSON.stringify({ error: 'Tenant identity mismatch' }), {
                status: 502,
                headers: corsHeaders()
            });
        }

        // Prepare response for caching
        const responseToCache = new Response(JSON.stringify(data), {
            headers: {
                'Content-Type': 'application/json',
                'Cache-Control': `public, max-age=${CACHE_TTL_SECONDS}`
            }
        });

        // Store in cache (background - don't block response)
        ctx.waitUntil(cache.put(cacheKey, responseToCache.clone()));

        // Return response with cache miss indicator
        return new Response(JSON.stringify({
            ...data,
            _cache: 'MISS',
            _edge: request.cf?.colo || 'unknown'
        }), {
            headers: {
                ...corsHeaders(),
                'Content-Type': 'application/json',
                'X-Cache': 'MISS',
                'X-Edge-Location': request.cf?.colo || 'unknown',
                'X-Tenant-ID': tenantId
            }
        });

    } catch (error) {
        console.error('Worker error:', error);
        return new Response(JSON.stringify({ error: error.message }), {
            status: 500,
            headers: corsHeaders()
        });
    }
}

function getSupabaseConfig(env) {
    const supabaseUrl = env.SUPABASE_URL;
    const supabaseAnonKey = env.SUPABASE_ANON_KEY;

    if (!supabaseUrl || !supabaseAnonKey) {
        throw new Error('Missing SUPABASE_URL or SUPABASE_ANON_KEY worker binding');
    }

    return { supabaseUrl, supabaseAnonKey };
}

function corsHeaders() {
    return {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        'Access-Control-Expose-Headers': 'X-Cache, X-Edge-Location, X-Tenant-ID',
        'Content-Type': 'application/json'
    };
}

function handleCORS() {
    return new Response(null, {
        status: 204,
        headers: corsHeaders()
    });
}

// Purge cache for a specific tenant
// Usage: POST /cache/purge with body {"p_tenant_id": "..."}
async function handleCachePurge(request) {
    try {
        const body = await request.json();
        const tenantId = body.p_tenant_id;

        if (!ALLOWED_TENANTS.includes(tenantId)) {
            return new Response(JSON.stringify({ error: 'Invalid tenant' }), {
                status: 403,
                headers: corsHeaders()
            });
        }

        // Delete from cache
        const cacheKey = new Request(`https://cache.vinabike.cl/public-store-data/${tenantId}`, {
            method: 'GET'
        });

        const cache = caches.default;
        const deleted = await cache.delete(cacheKey);

        return new Response(JSON.stringify({
            success: true,
            purged: deleted,
            tenant_id: tenantId,
            message: deleted ? 'Cache cleared' : 'Cache was already empty'
        }), {
            headers: corsHeaders()
        });
    } catch (error) {
        return new Response(JSON.stringify({ error: error.message }), {
            status: 500,
            headers: corsHeaders()
        });
    }
}
