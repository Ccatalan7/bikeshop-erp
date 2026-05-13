import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const WHATSAPP_ACCESS_TOKEN = Deno.env.get('WHATSAPP_ACCESS_TOKEN') ?? ''
const WHATSAPP_API_VERSION = Deno.env.get('WHATSAPP_API_VERSION') ?? 'v23.0'

type JsonRecord = Record<string, unknown>

interface TemplateDefinition {
  name: string
  language: string
  category: 'UTILITY' | 'MARKETING' | 'AUTHENTICATION'
  body: string
  examples: string[]
}

interface TemplateRequest {
  action?: 'list' | 'deploy_defaults'
  tenantId?: string
  channelId?: string
  businessAccountId?: string
  templates?: TemplateDefinition[]
}

const defaultTemplates: TemplateDefinition[] = [
  {
    name: 'actualizacion_servicio_bicicleta',
    language: 'es_CL',
    category: 'UTILITY',
    body:
      'Hola {{1}}, tenemos una actualizacion sobre tu bicicleta en {{2}}. Responde este mensaje para continuar la conversacion.',
    examples: ['Claudio', 'Vinabike'],
  },
  {
    name: 'bicicleta_lista_retiro',
    language: 'es_CL',
    category: 'UTILITY',
    body:
      'Hola {{1}}, tu bicicleta esta lista para retiro en {{2}}. Responde este mensaje si necesitas coordinar algo.',
    examples: ['Claudio', 'Vinabike'],
  },
  {
    name: 'seguimiento_presupuesto_bicicleta',
    language: 'es_CL',
    category: 'UTILITY',
    body:
      'Hola {{1}}, necesitamos tu respuesta sobre un presupuesto o aprobacion pendiente en {{2}}. Responde este mensaje para continuar.',
    examples: ['Claudio', 'Vinabike'],
  },
]

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  })
}

function cleanText(value: unknown) {
  if (typeof value !== 'string') return undefined
  const trimmed = value.trim()
  return trimmed.length > 0 ? trimmed : undefined
}

function isTemplateDefinition(value: unknown): value is TemplateDefinition {
  if (!value || typeof value !== 'object') return false
  const record = value as JsonRecord
  return Boolean(
    cleanText(record.name) &&
      cleanText(record.language) &&
      cleanText(record.category) &&
      cleanText(record.body) &&
      Array.isArray(record.examples),
  )
}

function buildTemplatePayload(template: TemplateDefinition) {
  return {
    name: template.name,
    language: template.language,
    category: template.category,
    allow_category_change: true,
    parameter_format: 'POSITIONAL',
    components: [
      {
        type: 'BODY',
        text: template.body,
        example: {
          body_text: [template.examples],
        },
      },
    ],
  }
}

function decodeJwtPayload(authHeader: string) {
  const token = authHeader.replace(/^Bearer\s+/i, '')
  const payload = token.split('.')[1]
  if (!payload) return null

  try {
    const normalized = payload
      .replace(/-/g, '+')
      .replace(/_/g, '/')
      .padEnd(Math.ceil(payload.length / 4) * 4, '=')
    return JSON.parse(atob(normalized)) as JsonRecord
  } catch (_error) {
    return null
  }
}

async function graphRequest(path: string, init?: RequestInit) {
  const response = await fetch(
    `https://graph.facebook.com/${WHATSAPP_API_VERSION}/${path}`,
    {
      ...init,
      headers: {
        Authorization: `Bearer ${WHATSAPP_ACCESS_TOKEN}`,
        'Content-Type': 'application/json',
        ...(init?.headers ?? {}),
      },
    },
  )

  const body = await response.json().catch(() => ({}))
  return { response, body }
}

async function listTemplates(businessAccountId: string) {
  const fields = [
    'id',
    'name',
    'language',
    'status',
    'category',
    'components',
    'rejected_reason',
  ].join(',')

  const result = await graphRequest(
    `${businessAccountId}/message_templates?fields=${encodeURIComponent(fields)}&limit=250`,
  )

  if (!result.response.ok) {
    throw result.body
  }

  return Array.isArray((result.body as JsonRecord).data)
    ? ((result.body as JsonRecord).data as JsonRecord[])
    : []
}

async function requireTenantAccess(req: Request, body: TemplateRequest) {
  const authHeader = req.headers.get('Authorization') ?? ''
  if (!authHeader) {
    return { error: jsonResponse({ error: 'Missing Authorization header' }, 401) }
  }

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
  const jwtPayload = decodeJwtPayload(authHeader)
  if (jwtPayload?.role === 'service_role') {
    const tenantId = cleanText(body.tenantId)
    if (!tenantId) {
      return { error: jsonResponse({ error: 'tenantId is required for service role calls' }, 400) }
    }
    return { adminClient, tenantId, userId: null as string | null }
  }

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  })

  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser()

  if (userError || !user) {
    return { error: jsonResponse({ error: 'Unauthorized' }, 401) }
  }

  const { data: profile, error: profileError } = await adminClient
    .from('user_profiles')
    .select('tenant_id, role')
    .eq('user_id', user.id)
    .maybeSingle()

  if (profileError || !profile?.tenant_id) {
    return { error: jsonResponse({ error: 'Unable to resolve user tenant' }, 400) }
  }

  const role = String(profile.role ?? '')
  if (!['owner', 'admin', 'manager'].includes(role)) {
    return { error: jsonResponse({ error: 'Insufficient permissions' }, 403) }
  }

  const requestedTenantId = cleanText(body.tenantId)
  const tenantId = String(profile.tenant_id)
  if (requestedTenantId && requestedTenantId !== tenantId) {
    return { error: jsonResponse({ error: 'Tenant mismatch' }, 403) }
  }

  return { adminClient, tenantId, userId: user.id }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405)
  }

  if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY || !WHATSAPP_ACCESS_TOKEN) {
    return jsonResponse({ error: 'Missing required environment variables' }, 500)
  }

  let body: TemplateRequest
  try {
    body = await req.json()
  } catch (error) {
    console.error('Invalid JSON body', error)
    return jsonResponse({ error: 'Invalid JSON body' }, 400)
  }

  const access = await requireTenantAccess(req, body)
  if ('error' in access) {
    return access.error
  }

  let channelQuery = access.adminClient
    .from('whatsapp_channels')
    .select('id, display_name, display_phone_number, phone_number_id, business_account_id, is_active')
    .eq('tenant_id', access.tenantId)

  if (body.channelId) {
    channelQuery = channelQuery.eq('id', body.channelId)
  } else {
    channelQuery = channelQuery.eq('is_active', true)
  }

  const { data: channel, error: channelError } = await channelQuery.limit(1).maybeSingle()
  if (channelError || !channel) {
    console.error('Failed to resolve WhatsApp channel', channelError)
    return jsonResponse({ error: 'No WhatsApp channel found for tenant' }, 400)
  }

  const businessAccountId = cleanText(body.businessAccountId) ??
    cleanText(channel.business_account_id)
  if (!businessAccountId) {
    return jsonResponse({ error: 'WhatsApp business account id is missing' }, 400)
  }

  const action = body.action ?? 'list'

  try {
    const existingTemplates = await listTemplates(businessAccountId)

    if (action === 'list') {
      return jsonResponse({
        ok: true,
        business_account_id: businessAccountId,
        channel,
        templates: existingTemplates,
      })
    }

    const templates = Array.isArray(body.templates) && body.templates.every(isTemplateDefinition)
      ? body.templates
      : defaultTemplates

    const created: JsonRecord[] = []
    const skipped: JsonRecord[] = []
    const failed: JsonRecord[] = []

    for (const template of templates) {
      const existing = existingTemplates.find((item) =>
        item.name === template.name && item.language === template.language
      )

      if (existing) {
        skipped.push({ template, existing })
        continue
      }

      const payload = buildTemplatePayload(template)
      const result = await graphRequest(`${businessAccountId}/message_templates`, {
        method: 'POST',
        body: JSON.stringify(payload),
      })

      if (result.response.ok) {
        created.push({ template, result: result.body })
      } else {
        failed.push({ template, error: result.body })
      }
    }

    return jsonResponse({
      ok: failed.length === 0,
      business_account_id: businessAccountId,
      channel,
      created,
      skipped,
      failed,
    }, failed.length === 0 ? 200 : 207)
  } catch (error) {
    console.error('Template manager failed', error)
    return jsonResponse({
      error: 'Meta template request failed',
      details: error,
    }, 502)
  }
})