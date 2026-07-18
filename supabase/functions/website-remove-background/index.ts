import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function cleanText(value: unknown) {
  return typeof value === 'string' ? value.trim() : ''
}

function safeStorageSource(rawUrl: string, supabaseUrl: string) {
  try {
    const source = new URL(rawUrl)
    const project = new URL(supabaseUrl)
    return source.protocol === 'https:' &&
      source.host === project.host &&
      source.pathname.startsWith(
        '/storage/v1/object/public/vinabike-assets/website-images/',
      )
  } catch (_) {
    return false
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405)
  }

  const authHeader = req.headers.get('Authorization') ?? ''
  if (!authHeader) {
    return jsonResponse({ error: 'Unauthorized' }, 401)
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const removeBgApiKey = Deno.env.get('REMOVE_BG_API_KEY') ?? ''
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return jsonResponse({ error: 'Server configuration is incomplete' }, 500)
  }
  if (!removeBgApiKey) {
    return jsonResponse(
      {
        code: 'provider_not_configured',
        error: 'Smart background removal is not configured',
      },
      503,
    )
  }

  try {
    const body = await req.json() as { imageUrl?: string; tenantId?: string }
    const imageUrl = cleanText(body.imageUrl)
    if (!safeStorageSource(imageUrl, supabaseUrl)) {
      return jsonResponse(
        { error: 'Only Website Builder media can be processed' },
        400,
      )
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    })
    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser()
    if (userError || !user) {
      return jsonResponse({ error: 'Unauthorized' }, 401)
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey)
    const { data: profile, error: profileError } = await adminClient
      .from('user_profiles')
      .select('tenant_id, role')
      .eq('user_id', user.id)
      .maybeSingle()
    if (profileError || !profile?.tenant_id) {
      return jsonResponse({ error: 'Unable to resolve user tenant' }, 400)
    }
    const role = cleanText(profile.role)
    if (!['owner', 'admin', 'manager'].includes(role)) {
      return jsonResponse({ error: 'Insufficient permissions' }, 403)
    }
    const tenantId = String(profile.tenant_id)
    if (body.tenantId && cleanText(body.tenantId) !== tenantId) {
      return jsonResponse({ error: 'Tenant mismatch' }, 403)
    }

    const providerBody = new FormData()
    providerBody.append('image_url', imageUrl)
    providerBody.append('size', 'auto')
    providerBody.append('type', 'product')
    providerBody.append('format', 'png')

    const providerResponse = await fetch(
      'https://api.remove.bg/v1.0/removebg',
      {
        method: 'POST',
        headers: { 'X-Api-Key': removeBgApiKey },
        body: providerBody,
      },
    )
    if (!providerResponse.ok) {
      const providerStatus = providerResponse.status
      console.error(
        '[website-remove-background] provider failed status=' +
          String(providerStatus),
      )
      if (providerStatus === 402) {
        return jsonResponse(
          {
            code: 'provider_credits_exhausted',
            error: 'Background-removal credits are exhausted',
          },
          402,
        )
      }
      if (providerStatus === 429) {
        return jsonResponse({ error: 'Provider rate limit reached' }, 429)
      }
      return jsonResponse({ error: 'Background-removal provider failed' }, 502)
    }

    const resultBytes = new Uint8Array(await providerResponse.arrayBuffer())
    if (resultBytes.length === 0 || resultBytes.length > 25 * 1024 * 1024) {
      return jsonResponse({ error: 'Provider returned an invalid image' }, 502)
    }

    const objectPath =
      'website-images/background-removed/' +
      tenantId +
      '/smart_' +
      crypto.randomUUID() +
      '.png'
    const { error: uploadError } = await adminClient.storage
      .from('vinabike-assets')
      .upload(objectPath, resultBytes, {
        contentType: 'image/png',
        cacheControl: '31536000',
        upsert: false,
      })
    if (uploadError) {
      console.error('[website-remove-background] upload failed', uploadError)
      return jsonResponse({ error: 'Unable to store processed image' }, 500)
    }

    const { data: publicData } = adminClient.storage
      .from('vinabike-assets')
      .getPublicUrl(objectPath)
    return jsonResponse({
      imageUrl: publicData.publicUrl,
      method: 'remove-bg',
    })
  } catch (error) {
    console.error('[website-remove-background] unexpected error', error)
    return jsonResponse({ error: 'Unable to remove image background' }, 400)
  }
})
