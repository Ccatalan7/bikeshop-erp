import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const WHATSAPP_ACCESS_TOKEN = Deno.env.get('WHATSAPP_ACCESS_TOKEN') ?? ''
const WHATSAPP_API_VERSION = Deno.env.get('WHATSAPP_API_VERSION') ?? 'v23.0'
const CACHE_TTL_MS = 5 * 60 * 1000

type JsonRecord = Record<string, unknown>

interface CacheEntry<T> {
  value: T
  expiresAt: number
}

interface WhatsAppChannelRecord {
  id: string
  phone_number_id: string
  display_name?: string | null
  display_phone_number?: string | null
  is_active: boolean
}

const tenantIdByUserId = new Map<string, CacheEntry<string>>()
const activeChannelByTenantKey = new Map<string, CacheEntry<WhatsAppChannelRecord>>()

interface SendRequest {
  conversationId?: string
  customerId?: string
  phoneNumber: string
  phoneNumberId?: string
  contactName?: string
  contextType?: string
  contextId?: string
  jobId?: string
  type: 'text' | 'image' | 'document' | 'template' | 'interactive'
  text?: string
  caption?: string
  mediaUrl?: string
  contentType?: string
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

function getCached<T>(cache: Map<string, CacheEntry<T>>, key: string) {
  const entry = cache.get(key)
  if (!entry) return null
  if (entry.expiresAt <= Date.now()) {
    cache.delete(key)
    return null
  }
  return entry.value
}

function setCached<T>(cache: Map<string, CacheEntry<T>>, key: string, value: T) {
  cache.set(key, {
    value,
    expiresAt: Date.now() + CACHE_TTL_MS,
  })
}

function decodeBase64Url(value: string) {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/')
  const padded = normalized.padEnd(
    normalized.length + ((4 - (normalized.length % 4)) % 4),
    '=',
  )
  return atob(padded)
}

function resolveUserIdFromAuthorization(authHeader: string) {
  const [scheme, token] = authHeader.split(/\s+/)
  if (scheme?.toLowerCase() !== 'bearer' || !token) {
    return null
  }

  const payloadPart = token.split('.')[1]
  if (!payloadPart) {
    return null
  }

  try {
    const payload = JSON.parse(decodeBase64Url(payloadPart)) as JsonRecord
    const subject = stringValue(payload.sub)
    return subject ?? null
  } catch (error) {
    console.error('❌ [WHATSAPP-SEND] Unable to decode JWT payload', error)
    return null
  }
}

async function resolveTenantIdForUser(
  adminClient: ReturnType<typeof createClient>,
  userId: string,
) {
  const cachedTenantId = getCached(tenantIdByUserId, userId)
  if (cachedTenantId) {
    return cachedTenantId
  }

  const { data: profile, error: profileError } = await adminClient
    .from('user_profiles')
    .select('tenant_id')
    .eq('user_id', userId)
    .single()

  if (profileError || !profile?.tenant_id) {
    console.error('❌ [WHATSAPP-SEND] Failed to resolve tenant', profileError)
    return null
  }

  const tenantId = String(profile.tenant_id)
  setCached(tenantIdByUserId, userId, tenantId)
  return tenantId
}

async function resolveActiveChannel(
  adminClient: ReturnType<typeof createClient>,
  tenantId: string,
  phoneNumberId?: string,
) {
  const cacheKey = `${tenantId}:${phoneNumberId ?? 'default'}`
  const cachedChannel = getCached(activeChannelByTenantKey, cacheKey)
  if (cachedChannel) {
    return cachedChannel
  }

  let channelQuery = adminClient
    .from('whatsapp_channels')
    .select('id, phone_number_id, display_name, display_phone_number, is_active')
    .eq('tenant_id', tenantId)
    .eq('is_active', true)

  if (phoneNumberId) {
    channelQuery = channelQuery.eq('phone_number_id', phoneNumberId)
  }

  const { data: channel, error: channelError } = await channelQuery.limit(1).maybeSingle()

  if (channelError || !channel) {
    console.error('❌ [WHATSAPP-SEND] Failed to resolve active channel', channelError)
    return null
  }

  const resolvedChannel = channel as WhatsAppChannelRecord
  setCached(activeChannelByTenantKey, cacheKey, resolvedChannel)
  return resolvedChannel
}

function normalizePhoneNumber(phone: string) {
  return phone.replace(/[^\d]/g, '')
}

function stringValue(value: unknown) {
  if (typeof value !== 'string') {
    return undefined
  }

  const trimmed = value.trim()
  return trimmed.length > 0 ? trimmed : undefined
}

function resolveMediaUrl(request: SendRequest) {
  return request.type === 'image'
    ? request.mediaUrl ?? request.documentUrl
    : request.documentUrl ?? request.mediaUrl
}

function resolveMediaFilename(request: SendRequest) {
  return request.documentFilename ??
    stringValue(request.metadata?.filename) ??
    (request.type === 'image' ? 'imagen.png' : 'documento')
}

function resolveMediaContentType(request: SendRequest, headerContentType: string | null) {
  return stringValue(headerContentType?.split(';')[0]) ??
    request.contentType ??
    stringValue(request.metadata?.contentType) ??
    stringValue(request.metadata?.content_type) ??
    (request.type === 'image' ? 'image/png' : 'application/octet-stream')
}

async function uploadMediaToWhatsApp(
  request: SendRequest,
  phoneNumberId: string,
) {
  if (request.type !== 'image' && request.type !== 'document') {
    return { metadata: {} as JsonRecord }
  }

  const mediaUrl = resolveMediaUrl(request)
  if (!mediaUrl) {
    return { metadata: {} as JsonRecord }
  }

  const mediaResponse = await fetch(mediaUrl)
  if (!mediaResponse.ok) {
    return {
      error: jsonResponse({
        error: 'Unable to fetch media before sending to WhatsApp',
        details: {
          status: mediaResponse.status,
          statusText: mediaResponse.statusText,
          mediaUrl,
        },
      }, 502),
    }
  }

  const contentType = resolveMediaContentType(
    request,
    mediaResponse.headers.get('content-type'),
  )
  const bytes = await mediaResponse.arrayBuffer()
  const filename = resolveMediaFilename(request)
  const formData = new FormData()
  formData.append('messaging_product', 'whatsapp')
  formData.append('type', contentType)
  formData.append('file', new Blob([bytes], { type: contentType }), filename)

  const uploadResponse = await fetch(
    `https://graph.facebook.com/${WHATSAPP_API_VERSION}/${phoneNumberId}/media`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${WHATSAPP_ACCESS_TOKEN}`,
      },
      body: formData,
    },
  )

  const uploadResult = await uploadResponse.json().catch(() => ({}))
  const mediaId = String((uploadResult as JsonRecord).id ?? '')
  if (!uploadResponse.ok || !mediaId) {
    console.error('❌ [WHATSAPP-SEND] Media upload failed', uploadResult)
    return {
      error: jsonResponse({
        error: 'WhatsApp media upload failed',
        details: uploadResult,
        media_url: mediaUrl,
      }, 502),
    }
  }

  return {
    mediaId,
    metadata: {
      whatsapp_media_id: mediaId,
      whatsapp_media_upload_source_url: mediaUrl,
      whatsapp_media_upload_content_type: contentType,
      whatsapp_media_upload_size: bytes.byteLength,
      whatsapp_media_upload_response: uploadResult,
    } as JsonRecord,
  }
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

function buildGraphPayload(request: SendRequest, to: string, mediaId?: string) {
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
    const document: JsonRecord = mediaId ? { id: mediaId } : { link: request.documentUrl }
    if (request.documentFilename) document.filename = request.documentFilename
    if (request.caption) document.caption = request.caption
    payload.document = document
    return payload
  }

  if (request.type === 'image') {
    const image: JsonRecord = mediaId ? { id: mediaId } : { link: request.mediaUrl ?? request.documentUrl }
    if (request.caption) image.caption = request.caption
    payload.image = image
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
    return request.documentUrl ?? request.caption ?? request.documentFilename ?? 'Documento enviado'
  }

  if (request.type === 'image') {
    return request.mediaUrl ?? request.documentUrl ?? request.caption ?? 'Imagen enviada'
  }

  if (request.type === 'template') {
    return request.caption ?? `Template enviado: ${request.templateName ?? 'sin nombre'}`
  }

  return request.text ?? request.caption ?? 'Solicitud enviada por WhatsApp'
}

async function replayStoredWhatsAppStatus(
  adminClient: ReturnType<typeof createClient>,
  externalMessageId: string,
) {
  if (!externalMessageId) {
    return
  }

  const { error } = await adminClient.rpc('replay_whatsapp_message_status', {
    p_external_message_id: externalMessageId,
  })

  if (error) {
    console.error('❌ [WHATSAPP-SEND] Failed to replay stored status events', error)
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405)
  }

  if (!SUPABASE_SERVICE_ROLE_KEY || !WHATSAPP_ACCESS_TOKEN) {
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

  const startedAt = Date.now()
  const clientMessageId = requestBody.metadata?.client_message_id ?? null
  const logTiming = (phase: string, details: JsonRecord = {}) => {
    console.log(
      '⏱️ [WHATSAPP-SEND] timing',
      JSON.stringify({
        phase,
        elapsed_ms: Date.now() - startedAt,
        type: requestBody.type,
        conversation_id: requestBody.conversationId ?? null,
        client_message_id: clientMessageId,
        ...details,
      }),
    )
  }

  logTiming('request_validated')

  if (requestBody.type === 'text' && !requestBody.text) {
    return jsonResponse({ error: 'text is required for text messages' }, 400)
  }

  if (requestBody.type === 'document' && !requestBody.documentUrl) {
    return jsonResponse({ error: 'documentUrl is required for document messages' }, 400)
  }

  if (requestBody.type === 'image' && !requestBody.mediaUrl && !requestBody.documentUrl) {
    return jsonResponse({ error: 'mediaUrl is required for image messages' }, 400)
  }

  if (requestBody.type === 'template' && !requestBody.templateName) {
    return jsonResponse({ error: 'templateName is required for template messages' }, 400)
  }

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

  const userId = resolveUserIdFromAuthorization(authHeader)
  if (!userId) {
    return jsonResponse({ error: 'Unauthorized' }, 401)
  }

  logTiming('auth_resolved')

  const tenantId = await resolveTenantIdForUser(adminClient, userId)
  if (!tenantId) {
    return jsonResponse({ error: 'Unable to resolve tenant' }, 400)
  }

  logTiming('tenant_resolved')

  const channel = await resolveActiveChannel(
    adminClient,
    tenantId,
    requestBody.phoneNumberId,
  )

  if (!channel) {
    return jsonResponse({ error: 'No active WhatsApp channel found for tenant' }, 400)
  }

  logTiming('channel_resolved', {
    channel_id: channel.id,
    phone_number_id: channel.phone_number_id,
  })

  const normalizedPhone = normalizePhoneNumber(requestBody.phoneNumber)
  const bindingContextType = requestBody.contextType ?? (requestBody.jobId ? 'job' : null)
  const bindingContextId = requestBody.contextId ?? requestBody.jobId ?? null

  // Kick off binding lookup in parallel with media upload + Graph send. The
  // binding row is only needed to know which conversation to insert the
  // persisted message into, which we do AFTER Graph success — so we don't
  // need to block the actual send on it.
  const bindingPromise = adminClient.rpc(
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

  const messageType = requestBody.type === 'image'
    ? 'image'
    : requestBody.type === 'document'
      ? 'file'
      : requestBody.actionType
        ? 'action_request'
        : 'text'

  const buildMessageMetadata = (extra: JsonRecord = {}) => ({
    ...(requestBody.metadata ?? {}),
    channel: 'whatsapp',
    provider: 'whatsapp',
    phone_number_id: channel.phone_number_id,
    display_phone_number: channel.display_phone_number,
    external_wa_id: normalizedPhone,
    outbound_type: requestBody.type,
    ...(requestBody.mediaUrl ? { media_url: requestBody.mediaUrl } : {}),
    ...(requestBody.documentUrl ? { document_url: requestBody.documentUrl } : {}),
    ...(requestBody.documentFilename
      ? {
        document_filename: requestBody.documentFilename,
        filename: requestBody.documentFilename,
      }
      : {}),
    action_type: requestBody.actionType ?? null,
    target_id: requestBody.actionTargetId ?? requestBody.jobId ?? null,
    amount: requestBody.amount ?? null,
    status: 'pending',
    ...extra,
  })

  const persistOutboundMessage = async ({
    externalMessageId,
    externalStatus,
    metadata,
    graphResult,
  }: {
    externalMessageId?: string
    externalStatus: 'accepted' | 'failed'
    metadata: JsonRecord
    graphResult?: unknown
  }) => {
    const persistStartedAt = Date.now()
    const { data: bindingResult, error: bindingError } = await bindingPromise
    if (bindingError || !bindingResult) {
      console.error('❌ [WHATSAPP-SEND] Failed to ensure conversation binding', bindingError)
      return
    }

    logTiming('persist_binding_ready', {
      persist_elapsed_ms: Date.now() - persistStartedAt,
      conversation_id: (bindingResult as JsonRecord).conversation_id,
    })

    const { error: insertError } = await adminClient
      .from('messages')
      .insert({
        conversation_id: (bindingResult as JsonRecord).conversation_id,
          sender_id: userId,
        tenant_id: tenantId,
        content: getMessageContent(requestBody),
        type: messageType,
          metadata,
        external_provider: 'whatsapp',
        external_message_id: externalMessageId || null,
        message_direction: 'outbound',
          external_status: externalStatus,
      })

    if (insertError) {
      console.error('❌ [WHATSAPP-SEND] Failed to persist outbound message', insertError)
    } else if (externalMessageId) {
      logTiming('persist_message_inserted', {
        persist_elapsed_ms: Date.now() - persistStartedAt,
      })
      await replayStoredWhatsAppStatus(adminClient, externalMessageId)
      logTiming('persist_status_replayed', {
        persist_elapsed_ms: Date.now() - persistStartedAt,
      })
    }

    await adminClient
      .from('whatsapp_conversation_bindings')
      .update({ last_outbound_at: new Date().toISOString() })
      .eq('id', (bindingResult as JsonRecord).binding_id)

    if (externalStatus === 'accepted' && requestBody.markQuoteSent && requestBody.jobId) {
      const { error } = await adminClient.rpc('mark_whatsapp_job_quote_sent', {
        p_job_id: requestBody.jobId,
        p_external_message_id: externalMessageId || null,
        p_payload: graphResult ?? {},
      })

      if (error) {
        console.error('❌ [WHATSAPP-SEND] Failed to mark quote as sent', error)
      }
    }

    logTiming('persist_done', {
      persist_elapsed_ms: Date.now() - persistStartedAt,
    })
  }

  // The HTTP response is now the Vinabike server ACK: the request is valid,
  // authenticated, tied to a tenant/channel, and accepted for delivery. The
  // actual Meta Graph send continues in the background and reconciles the
  // optimistic UI row through realtime using `client_message_id`.
  const sendPromise = (async () => {
    try {
      logTiming('media_upload_start')
      const mediaUpload = await uploadMediaToWhatsApp(
        requestBody,
        String(channel.phone_number_id),
      )
      if (mediaUpload.error) {
        logTiming('media_upload_failed')
        let failurePayload: unknown = { error: 'WhatsApp media upload failed' }
        try {
          failurePayload = await mediaUpload.error.clone().json()
        } catch (_error) {
          // Keep the generic payload above.
        }
        await persistOutboundMessage({
          externalStatus: 'failed',
          metadata: buildMessageMetadata({
            status: 'failed',
            whatsapp_status: 'failed',
            whatsapp_status_payload: failurePayload,
          }),
        })
        return
      }
      logTiming('media_upload_done', {
        uploaded: Boolean(mediaUpload.mediaId),
      })

      const graphPayload = buildGraphPayload(
        requestBody,
        normalizedPhone,
        mediaUpload.mediaId,
      )
      if (requestBody.type === 'interactive' && !graphPayload.interactive) {
        await persistOutboundMessage({
          externalStatus: 'failed',
          metadata: buildMessageMetadata({
            status: 'failed',
            whatsapp_status: 'failed',
            whatsapp_status_payload: {
              error: 'interactive payload is required, or provide actionType/actionTargetId',
            },
          }),
        })
        return
      }

      logTiming('graph_request_start')
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

      logTiming('graph_response_headers', { status: graphResponse.status })
      const graphResult = await graphResponse.json().catch(() => ({}))
      if (!graphResponse.ok) {
        logTiming('graph_request_failed', { status: graphResponse.status })
        console.error('❌ [WHATSAPP-SEND] Graph API error', graphResult)
        await persistOutboundMessage({
          externalStatus: 'failed',
          metadata: buildMessageMetadata({
            graph_payload: graphPayload,
            graph_response: graphResult,
            status: 'failed',
            whatsapp_status: 'failed',
            whatsapp_status_payload: graphResult,
          }),
        })
        return
      }

      const externalMessageId = String(
        ((graphResult as JsonRecord).messages as JsonRecord[] | undefined)?.[0]?.id ?? '',
      )
      logTiming('graph_request_done', {
        status: graphResponse.status,
        external_message_id: externalMessageId || null,
      })

      await persistOutboundMessage({
        externalMessageId,
        externalStatus: 'accepted',
        graphResult,
        metadata: buildMessageMetadata({
          ...(mediaUpload.metadata ?? {}),
          graph_payload: graphPayload,
          graph_response: graphResult,
        }),
      })
    } catch (error) {
      logTiming('background_send_failed')
      console.error('❌ [WHATSAPP-SEND] Background send failed', error)
      await persistOutboundMessage({
        externalStatus: 'failed',
        metadata: buildMessageMetadata({
          status: 'failed',
          whatsapp_status: 'failed',
          whatsapp_status_payload: { error: String(error) },
        }),
      })
    }
  })()

  // EdgeRuntime.waitUntil keeps the worker alive until the background task
  // finishes, without blocking the HTTP response.
  // deno-lint-ignore no-explicit-any
  const edgeRuntime = (globalThis as any).EdgeRuntime
  if (edgeRuntime && typeof edgeRuntime.waitUntil === 'function') {
    edgeRuntime.waitUntil(sendPromise)
  } else {
    // Local dev / non-edge runtime fallback: don't drop the promise on the floor.
    sendPromise.catch((err) =>
      console.error('❌ [WHATSAPP-SEND] Background send failed', err),
    )
  }

  logTiming('response_returning', { queued: true })

  return jsonResponse({
    ok: true,
    queued: true,
  })
})
