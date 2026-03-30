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

interface SendRequest {
  conversationId?: string
  customerId?: string
  phoneNumber: string
  phoneNumberId?: string
  contactName?: string
  contextType?: string
  contextId?: string
  jobId?: string
  type: 'text' | 'document' | 'template' | 'interactive'
  text?: string
  caption?: string
  documentUrl?: string
  documentFilename?: string
  templateName?: string
  templateLanguage?: string
  templateComponents?: unknown[]
  interactive?: JsonRecord
  replyToMessageId?: string
  metadata?: JsonRecord
  actionType?: string
  actionTargetId?: string
  actionKind?: 'job' | 'invoice'
  amount?: number
  markQuoteSent?: boolean
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  })
}

function normalizePhoneNumber(phone: string) {
  return phone.replace(/[^\d]/g, '')
}

function buildActionInteractivePayload(request: SendRequest) {
  const actionType = request.actionType
  const actionTargetId = request.actionTargetId ?? request.jobId
  if (!actionType || !actionTargetId) {
    return null
  }

  const actionKind = request.actionKind ?? (actionType === 'pay_now' ? 'invoice' : 'job')

  let positiveAction = actionType
  let negativeAction = `reject_${actionType}`
  let positiveTitle = 'Aceptar'
  let negativeTitle = 'Rechazar'

  if (actionType === 'approve_quote') {
    positiveAction = 'approve_quote'
    negativeAction = 'reject_quote'
    positiveTitle = 'Aprobar'
  }

  if (actionType === 'confirm_delivery') {
    positiveAction = 'confirm_delivery'
    negativeAction = 'cancel_delivery'
    positiveTitle = 'Confirmar'
  }

  if (actionType === 'pay_now') {
    positiveAction = 'confirm_invoice'
    negativeAction = 'reject_invoice'
    positiveTitle = 'Pagar'
  }

  return {
    type: 'button',
    header: request.documentUrl ? {
      type: 'document',
      document: {
        link: request.documentUrl,
        filename: request.documentFilename ?? 'Documento.pdf'
      }
    } : undefined,
    body: {
      text: request.text ?? request.caption ?? 'Revisa esta solicitud y responde desde WhatsApp.',
    },
    action: {
      buttons: [
        {
          type: 'reply',
          reply: {
            id: `${actionKind}:${actionTargetId}:${negativeAction}`,
            title: negativeTitle,
          },
        },
        {
          type: 'reply',
          reply: {
            id: `${actionKind}:${actionTargetId}:${positiveAction}`,
            title: positiveTitle,
          },
        },
      ],
    },
  }
}

function buildGraphPayload(request: SendRequest, to: string) {
  const payload: JsonRecord = {
    messaging_product: 'whatsapp',
    recipient_type: 'individual',
    to,
    type: request.type,
  }

  if (request.replyToMessageId) {
    payload.context = { message_id: request.replyToMessageId }
  }

  if (request.type === 'text') {
    payload.text = {
      body: request.text ?? '',
      preview_url: false,
    }
    return payload
  }

  if (request.type === 'document') {
    payload.document = {
      link: request.documentUrl,
      filename: request.documentFilename,
      caption: request.caption,
    }
    return payload
  }

  if (request.type === 'template') {
    payload.template = {
      name: request.templateName,
      language: {
        code: request.templateLanguage ?? 'es',
      },
      components: request.templateComponents ?? [],
    }
    return payload
  }

  payload.interactive = request.interactive ?? buildActionInteractivePayload(request)
  return payload
}

function getMessageContent(request: SendRequest) {
  if (request.type === 'text') {
    return request.text ?? ''
  }

  if (request.type === 'document') {
    return request.caption ?? request.documentFilename ?? 'Documento enviado'
  }

  if (request.type === 'template') {
    return request.caption ?? `Template enviado: ${request.templateName ?? 'sin nombre'}`
  }

  return request.text ?? request.caption ?? 'Solicitud enviada por WhatsApp'
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405)
  }

  if (!SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY || !WHATSAPP_ACCESS_TOKEN) {
    return jsonResponse({
      error: 'Missing required environment variables',
    }, 500)
  }

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) {
    return jsonResponse({ error: 'Missing Authorization header' }, 401)
  }

  let requestBody: SendRequest
  try {
    requestBody = await req.json()
  } catch (error) {
    console.error('❌ [WHATSAPP-SEND] Invalid JSON body', error)
    return jsonResponse({ error: 'Invalid JSON body' }, 400)
  }

  if (!requestBody.phoneNumber || !requestBody.type) {
    return jsonResponse({ error: 'phoneNumber and type are required' }, 400)
  }

  if (requestBody.type === 'text' && !requestBody.text) {
    return jsonResponse({ error: 'text is required for text messages' }, 400)
  }

  if (requestBody.type === 'document' && !requestBody.documentUrl) {
    return jsonResponse({ error: 'documentUrl is required for document messages' }, 400)
  }

  if (requestBody.type === 'template' && !requestBody.templateName) {
    return jsonResponse({ error: 'templateName is required for template messages' }, 400)
  }

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: {
      headers: { Authorization: authHeader },
    },
  })
  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser()

  if (userError || !user) {
    return jsonResponse({ error: 'Unauthorized' }, 401)
  }

  const { data: profile, error: profileError } = await adminClient
    .from('user_profiles')
    .select('tenant_id')
    .eq('user_id', user.id)
    .single()

  if (profileError || !profile?.tenant_id) {
    console.error('❌ [WHATSAPP-SEND] Failed to resolve tenant', profileError)
    return jsonResponse({ error: 'Unable to resolve tenant' }, 400)
  }

  const tenantId = String(profile.tenant_id)
  let channelQuery = adminClient
    .from('whatsapp_channels')
    .select('id, phone_number_id, display_name, display_phone_number, is_active')
    .eq('tenant_id', tenantId)
    .eq('is_active', true)

  if (requestBody.phoneNumberId) {
    channelQuery = channelQuery.eq('phone_number_id', requestBody.phoneNumberId)
  }

  const { data: channel, error: channelError } = await channelQuery.limit(1).maybeSingle()

  if (channelError || !channel) {
    console.error('❌ [WHATSAPP-SEND] Failed to resolve active channel', channelError)
    return jsonResponse({ error: 'No active WhatsApp channel found for tenant' }, 400)
  }

  const normalizedPhone = normalizePhoneNumber(requestBody.phoneNumber)
  const bindingContextType = requestBody.contextType ?? (requestBody.jobId ? 'job' : null)
  const bindingContextId = requestBody.contextId ?? requestBody.jobId ?? null

  const { data: bindingResult, error: bindingError } = await adminClient.rpc(
    'ensure_whatsapp_conversation_binding',
    {
      p_tenant_id: tenantId,
      p_channel_id: channel.id,
      p_wa_id: normalizedPhone,
      p_phone_number: normalizedPhone,
      p_contact_name: requestBody.contactName ?? null,
      p_customer_id: requestBody.customerId ?? null,
      p_context_type: bindingContextType,
      p_context_id: bindingContextId,
      p_conversation_id: requestBody.conversationId ?? null,
    },
  )

  if (bindingError || !bindingResult) {
    console.error('❌ [WHATSAPP-SEND] Failed to ensure conversation binding', bindingError)
    return jsonResponse({ error: 'Unable to ensure WhatsApp conversation binding' }, 400)
  }

  const graphPayload = buildGraphPayload(requestBody, normalizedPhone)
  if (requestBody.type === 'interactive' && !graphPayload.interactive) {
    return jsonResponse({
      error: 'interactive payload is required, or provide actionType/actionTargetId',
    }, 400)
  }

  const graphResponse = await fetch(
    `https://graph.facebook.com/${WHATSAPP_API_VERSION}/${channel.phone_number_id}/messages`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${WHATSAPP_ACCESS_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(graphPayload),
    },
  )

  const graphResult = await graphResponse.json().catch(() => ({}))
  if (!graphResponse.ok) {
    console.error('❌ [WHATSAPP-SEND] Graph API error', graphResult)
    return jsonResponse({
      error: 'Graph API request failed',
      details: graphResult,
    }, 502)
  }

  const externalMessageId = String(
    ((graphResult as JsonRecord).messages as JsonRecord[] | undefined)?.[0]?.id ?? '',
  )

  const messageType = requestBody.type === 'document'
    ? 'file'
    : requestBody.actionType
      ? 'action_request'
      : 'text'

  const messageMetadata: JsonRecord = {
    ...(requestBody.metadata ?? {}),
    channel: 'whatsapp',
    provider: 'whatsapp',
    phone_number_id: channel.phone_number_id,
    display_phone_number: channel.display_phone_number,
    external_wa_id: normalizedPhone,
    outbound_type: requestBody.type,
    graph_payload: graphPayload,
    graph_response: graphResult,
    action_type: requestBody.actionType ?? null,
    target_id: requestBody.actionTargetId ?? requestBody.jobId ?? null,
    amount: requestBody.amount ?? null,
    status: 'pending',
  }

  const { data: insertedMessage, error: insertError } = await adminClient
    .from('messages')
    .insert({
      conversation_id: (bindingResult as JsonRecord).conversation_id,
      sender_id: user.id,
      tenant_id: tenantId,
      content: getMessageContent(requestBody),
      type: messageType,
      metadata: messageMetadata,
      external_provider: 'whatsapp',
      external_message_id: externalMessageId || null,
      message_direction: 'outbound',
      external_status: 'accepted',
    })
    .select('id, conversation_id, content, type, metadata, created_at')
    .single()

  if (insertError) {
    console.error('❌ [WHATSAPP-SEND] Failed to persist outbound message', insertError)
    return jsonResponse({
      error: 'WhatsApp message sent but persistence failed',
      details: insertError.message,
      graph_result: graphResult,
    }, 500)
  }

  await adminClient
    .from('whatsapp_conversation_bindings')
    .update({ last_outbound_at: new Date().toISOString() })
    .eq('id', (bindingResult as JsonRecord).binding_id)

  if (requestBody.markQuoteSent && requestBody.jobId) {
    const { error } = await adminClient.rpc('mark_whatsapp_job_quote_sent', {
      p_job_id: requestBody.jobId,
      p_external_message_id: externalMessageId || null,
      p_payload: graphResult,
    })

    if (error) {
      console.error('❌ [WHATSAPP-SEND] Failed to mark quote as sent', error)
    }
  }

  return jsonResponse({
    ok: true,
    conversation_id: (bindingResult as JsonRecord).conversation_id,
    binding_id: (bindingResult as JsonRecord).binding_id,
    external_message_id: externalMessageId,
    message: insertedMessage,
    graph_result: graphResult,
  })
})