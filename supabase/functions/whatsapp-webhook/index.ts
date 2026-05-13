import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-hub-signature-256',
}

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const WHATSAPP_VERIFY_TOKEN = Deno.env.get('WHATSAPP_VERIFY_TOKEN') ?? ''
const META_APP_SECRET = Deno.env.get('META_APP_SECRET') ?? ''

type JsonRecord = Record<string, unknown>

interface ActionTarget {
  kind: 'job' | 'invoice'
  targetId: string
  action: string
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

async function createHmacSha256Hex(secret: string, payload: string) {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )

  const signature = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(payload),
  )

  return Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('')
}

async function verifyMetaSignature(req: Request, rawBody: string) {
  if (!META_APP_SECRET) {
    console.error('❌ [WHATSAPP-WEBHOOK] META_APP_SECRET is not configured')
    return false
  }

  const header = req.headers.get('x-hub-signature-256')
  if (!header?.startsWith('sha256=')) {
    console.error('❌ [WHATSAPP-WEBHOOK] Missing x-hub-signature-256 header')
    return false
  }

  const expected = header.replace('sha256=', '')
  const actual = await createHmacSha256Hex(META_APP_SECRET, rawBody)
  return expected === actual
}

function getMessageType(message: JsonRecord) {
  return String(message.type ?? 'text')
}

function getMessageBody(message: JsonRecord) {
  const type = getMessageType(message)

  if (type === 'text') {
    return String((message.text as JsonRecord | undefined)?.body ?? '')
  }

  if (type === 'interactive') {
    const interactive = message.interactive as JsonRecord | undefined
    const buttonReply = interactive?.button_reply as JsonRecord | undefined
    const listReply = interactive?.list_reply as JsonRecord | undefined
    return String(buttonReply?.title ?? listReply?.title ?? buttonReply?.id ?? listReply?.id ?? '')
  }

  if (type === 'button') {
    return String((message.button as JsonRecord | undefined)?.text ?? '')
  }

  if (type === 'image') {
    return String((message.image as JsonRecord | undefined)?.caption ?? 'Imagen recibida')
  }

  if (type === 'document') {
    const document = message.document as JsonRecord | undefined
    return String(document?.caption ?? document?.filename ?? 'Documento recibido')
  }

  if (type === 'audio') {
    return 'Audio recibido'
  }

  if (type === 'video') {
    return String((message.video as JsonRecord | undefined)?.caption ?? 'Video recibido')
  }

  if (type === 'location') {
    return 'Ubicación compartida'
  }

  return type
}

function parseActionTarget(message: JsonRecord): ActionTarget | null {
  const interactive = message.interactive as JsonRecord | undefined
  const buttonReply = interactive?.button_reply as JsonRecord | undefined
  const listReply = interactive?.list_reply as JsonRecord | undefined
  const button = message.button as JsonRecord | undefined

  const rawId = String(
    buttonReply?.id ?? listReply?.id ?? button?.payload ?? '',
  )

  if (!rawId) {
    return null
  }

  const match = /^(job|invoice):([0-9a-fA-F-]{36}):([a-z_]+)$/.exec(rawId)
  if (!match) {
    return null
  }

  return {
    kind: match[1] as 'job' | 'invoice',
    targetId: match[2],
    action: match[3],
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method === 'GET') {
    const url = new URL(req.url)
    const mode = url.searchParams.get('hub.mode')
    const verifyToken = url.searchParams.get('hub.verify_token')
    const challenge = url.searchParams.get('hub.challenge')

    if (mode === 'subscribe' && verifyToken === WHATSAPP_VERIFY_TOKEN && challenge) {
      console.log('✅ [WHATSAPP-WEBHOOK] Verification challenge accepted')
      return new Response(challenge, { status: 200 })
    }

    console.error('❌ [WHATSAPP-WEBHOOK] Verification failed')
    return new Response('Forbidden', { status: 403 })
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405)
  }

  const rawBody = await req.text()
  const isValidSignature = await verifyMetaSignature(req, rawBody)

  if (!isValidSignature) {
    return jsonResponse({ error: 'Invalid Meta signature' }, 401)
  }

  let payload: JsonRecord
  try {
    payload = JSON.parse(rawBody) as JsonRecord
  } catch (error) {
    console.error('❌ [WHATSAPP-WEBHOOK] Invalid JSON payload', error)
    return jsonResponse({ error: 'Invalid JSON payload' }, 400)
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
  const processedMessages: unknown[] = []
  const processedStatuses: unknown[] = []
  const automationResults: unknown[] = []
  const errors: string[] = []

  const entries = Array.isArray(payload.entry) ? payload.entry : []

  for (const entry of entries) {
    const changes = Array.isArray((entry as JsonRecord).changes)
      ? ((entry as JsonRecord).changes as JsonRecord[])
      : []

    for (const change of changes) {
      const value = ((change.value ?? {}) as JsonRecord)
      const metadata = ((value.metadata ?? {}) as JsonRecord)
      const phoneNumberId = String(metadata.phone_number_id ?? '')

      const contacts = Array.isArray(value.contacts)
        ? (value.contacts as JsonRecord[])
        : []
      const messages = Array.isArray(value.messages)
        ? (value.messages as JsonRecord[])
        : []
      const statuses = Array.isArray(value.statuses)
        ? (value.statuses as JsonRecord[])
        : []

      for (const status of statuses) {
        try {
          const externalMessageId = String(status.id ?? '')
          const statusValue = String(status.status ?? '')
          if (!phoneNumberId || !externalMessageId || !statusValue) {
            continue
          }

          const { data, error } = await supabase.rpc('record_whatsapp_message_status', {
            p_phone_number_id: phoneNumberId,
            p_external_message_id: externalMessageId,
            p_status: statusValue,
            p_payload: status,
          })

          if (error) {
            throw error
          }

          console.log(
            '🔎 [WHATSAPP-WEBHOOK] status_callback',
            JSON.stringify({
              status: statusValue,
              external_message_id: externalMessageId,
              phone_number_id: phoneNumberId,
              applied: (data as JsonRecord | null)?.applied,
              applied_status: (data as JsonRecord | null)?.status,
              message_id: (data as JsonRecord | null)?.message_id,
              conversation_id: (data as JsonRecord | null)?.conversation_id,
            }),
          )

          processedStatuses.push(data)
        } catch (error) {
          console.error('❌ [WHATSAPP-WEBHOOK] Status processing error', error)
          errors.push(`status:${String(error)}`)
        }
      }

      for (const message of messages) {
        try {
          const waId = String(message.from ?? contacts[0]?.wa_id ?? '')
          const externalMessageId = String(message.id ?? '')
          const messageType = getMessageType(message)
          const messageBody = getMessageBody(message)
          const contactName = String(
            ((contacts[0]?.profile as JsonRecord | undefined)?.name) ?? '',
          )

          if (!phoneNumberId || !waId || !externalMessageId) {
            continue
          }

          const inboundPayload = {
            message,
            contact: contacts[0] ?? null,
            metadata,
          }

          const { data: ingestResult, error: ingestError } = await supabase.rpc(
            'ingest_whatsapp_inbound_message',
            {
              p_phone_number_id: phoneNumberId,
              p_external_message_id: externalMessageId,
              p_wa_id: waId,
              p_phone_number: waId,
              p_contact_name: contactName,
              p_message_type: messageType,
              p_message_body: messageBody,
              p_payload: inboundPayload,
              p_context_type: null,
              p_context_id: null,
            },
          )

          if (ingestError) {
            throw ingestError
          }

          processedMessages.push(ingestResult)

          const actionTarget = parseActionTarget(message)
          const isDuplicate = Boolean((ingestResult as JsonRecord | null)?.duplicate)

          if (!isDuplicate && actionTarget) {
            if (actionTarget.kind === 'job') {
              const { data, error } = await supabase.rpc('apply_whatsapp_job_action', {
                p_job_id: actionTarget.targetId,
                p_action: actionTarget.action,
                p_external_message_id: externalMessageId,
                p_payload: inboundPayload,
              })

              if (error) {
                throw error
              }

              automationResults.push(data)
            }

            if (
              actionTarget.kind === 'invoice' &&
              ['approve_invoice', 'confirm_invoice', 'approve_quote'].includes(actionTarget.action)
            ) {
              const { error } = await supabase.rpc('confirm_invoice_approval', {
                p_invoice_id: actionTarget.targetId,
              })

              if (error) {
                throw error
              }

              automationResults.push({
                invoice_id: actionTarget.targetId,
                action: actionTarget.action,
                result: 'approved',
              })
            }
          }
        } catch (error) {
          console.error('❌ [WHATSAPP-WEBHOOK] Message processing error', error)
          errors.push(`message:${String(error)}`)
        }
      }
    }
  }

  return jsonResponse({
    ok: true,
    processed_messages: processedMessages.length,
    processed_statuses: processedStatuses.length,
    automations: automationResults.length,
    errors,
  })
})