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
const WHATSAPP_MEDIA_BUCKET = Deno.env.get('WHATSAPP_MEDIA_BUCKET') ?? 'vinabike-assets'

type JsonRecord = Record<string, unknown>

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  })
}

function stringValue(value: unknown) {
  if (typeof value !== 'string') return undefined
  const trimmed = value.trim()
  return trimmed.length > 0 ? trimmed : undefined
}

function urlFromMetadata(metadata: JsonRecord) {
  const rawPayload = metadata.raw_payload as JsonRecord | undefined
  const rawMedia = rawPayload?.media as JsonRecord | undefined
  const media = metadata.media as JsonRecord | undefined
  const candidates = [
    metadata.url,
    metadata.media_url,
    metadata.image_url,
    metadata.file_url,
    metadata.documentUrl,
    metadata.document_url,
    media?.url,
    media?.media_url,
    rawMedia?.url,
    rawMedia?.media_url,
  ]

  for (const candidate of candidates) {
    const value = stringValue(candidate)
    if (value?.startsWith('http')) return value
  }

  return undefined
}

function safeStoragePart(value: string) {
  const cleaned = value
    .trim()
    .replaceAll(/[^A-Za-z0-9._-]+/g, '_')
    .replaceAll(/_+/g, '_')
    .replaceAll(/^[._-]+|[._-]+$/g, '')
  return cleaned || 'media'
}

function extensionForContentType(contentType: string, fallback = 'bin') {
  const normalized = contentType.toLowerCase().split(';')[0].trim()
  switch (normalized) {
    case 'image/jpeg':
      return 'jpg'
    case 'image/png':
      return 'png'
    case 'image/gif':
      return 'gif'
    case 'image/webp':
      return 'webp'
    case 'video/mp4':
      return 'mp4'
    case 'audio/mpeg':
      return 'mp3'
    case 'audio/ogg':
      return 'ogg'
    case 'application/pdf':
      return 'pdf'
    default:
      return fallback
  }
}

function mediaSourceFromMetadata(metadata: JsonRecord) {
  const rawPayload = metadata.raw_payload as JsonRecord | undefined
  const webhookMessage = rawPayload?.message as JsonRecord | undefined
  const rawMedia = rawPayload?.media as JsonRecord | undefined
  const metadataMedia = metadata.media as JsonRecord | undefined
  const messageType = stringValue(metadata.message_type) ??
    stringValue(webhookMessage?.type) ??
    'image'

  const candidates = [
    rawMedia,
    metadataMedia,
    webhookMessage?.[messageType],
    webhookMessage?.image,
    webhookMessage?.document,
    webhookMessage?.video,
    webhookMessage?.audio,
    webhookMessage?.sticker,
    metadata,
  ]

  for (const candidate of candidates) {
    if (!candidate || typeof candidate !== 'object') continue
    const record = candidate as JsonRecord
    const mediaId = stringValue(record.id) ??
      stringValue(record.whatsapp_media_id) ??
      stringValue(record.media_id)
    if (mediaId) {
      return {
        media: record,
        messageType,
        mediaId,
      }
    }
  }

  return null
}

function filenameForMedia(
  messageType: string,
  media: JsonRecord,
  messageId: string,
  contentType: string,
) {
  const explicit = stringValue(media.filename) ??
    stringValue(media.document_filename) ??
    stringValue(media.originalFilename)
  if (explicit) return explicit

  const fallbackExtension = extensionForContentType(
    contentType,
    messageType === 'image' || messageType === 'sticker' ? 'jpg' : 'bin',
  )
  const label = messageType === 'document'
    ? 'documento'
    : messageType === 'video'
    ? 'video'
    : messageType === 'audio'
    ? 'audio'
    : 'imagen'
  return `${label}_${safeStoragePart(messageId)}.${fallbackExtension}`
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405)
  }

  if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
    return jsonResponse({ error: 'Missing Supabase environment variables' }, 500)
  }

  const authorization = req.headers.get('Authorization')
  if (!authorization) {
    return jsonResponse({ error: 'Missing authentication' }, 401)
  }

  const authClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: {
      headers: { Authorization: authorization },
    },
  })
  const { data: userData, error: userError } = await authClient.auth.getUser()
  if (userError || !userData.user) {
    return jsonResponse({ error: 'Missing authentication' }, 401)
  }

  let body: JsonRecord
  try {
    body = await req.json() as JsonRecord
  } catch (_) {
    return jsonResponse({ error: 'Invalid JSON body' }, 400)
  }

  const messageId = stringValue(body.messageId)
  if (!messageId) {
    return jsonResponse({ error: 'messageId is required' }, 400)
  }

  const { data: visibleMessage, error: visibleError } = await authClient
    .from('messages')
    .select('id, conversation_id, tenant_id, content, type, metadata')
    .eq('id', messageId)
    .maybeSingle()

  if (visibleError) {
    console.error('❌ [WHATSAPP-MEDIA] Message visibility check failed', visibleError)
    return jsonResponse({ error: 'Unable to read message' }, 500)
  }

  if (!visibleMessage) {
    return jsonResponse({ error: 'Message not found' }, 404)
  }

  const metadata = (visibleMessage.metadata ?? {}) as JsonRecord
  const existingUrl = urlFromMetadata(metadata)
  if (existingUrl) {
    return jsonResponse({
      url: existingUrl,
      metadata,
      already_hydrated: true,
    })
  }

  if (!WHATSAPP_ACCESS_TOKEN) {
    return jsonResponse({ error: 'WhatsApp media access is not configured' }, 500)
  }

  const source = mediaSourceFromMetadata(metadata)
  if (!source) {
    return jsonResponse({ error: 'Message has no WhatsApp media id' }, 400)
  }

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

  const infoResponse = await fetch(
    `https://graph.facebook.com/${WHATSAPP_API_VERSION}/${source.mediaId}`,
    {
      headers: {
        Authorization: `Bearer ${WHATSAPP_ACCESS_TOKEN}`,
      },
    },
  )
  const info = await infoResponse.json().catch(() => ({})) as JsonRecord
  if (!infoResponse.ok) {
    console.error('❌ [WHATSAPP-MEDIA] Media metadata fetch failed', info)
    return jsonResponse({ error: 'Unable to fetch WhatsApp media metadata', details: info }, 502)
  }

  const temporaryUrl = stringValue(info.url)
  if (!temporaryUrl) {
    return jsonResponse({ error: 'WhatsApp media metadata did not include a URL' }, 502)
  }

  const mediaResponse = await fetch(temporaryUrl, {
    headers: {
      Authorization: `Bearer ${WHATSAPP_ACCESS_TOKEN}`,
    },
  })

  if (!mediaResponse.ok) {
    return jsonResponse({
      error: 'Unable to download WhatsApp media',
      details: {
        status: mediaResponse.status,
        statusText: mediaResponse.statusText,
      },
    }, 502)
  }

  const contentType = stringValue(mediaResponse.headers.get('content-type')) ??
    stringValue(info.mime_type) ??
    stringValue(source.media.mime_type) ??
    (source.messageType === 'image' || source.messageType === 'sticker'
      ? 'image/jpeg'
      : 'application/octet-stream')
  const bytes = new Uint8Array(await mediaResponse.arrayBuffer())
  const filename = filenameForMedia(source.messageType, source.media, messageId, contentType)
  const extension = extensionForContentType(
    contentType,
    filename.includes('.') ? filename.split('.').pop() ?? 'bin' : 'bin',
  )
  const storagePath = [
    'whatsapp-media',
    safeStoragePart(String(visibleMessage.tenant_id ?? 'tenant')),
    safeStoragePart(String(visibleMessage.conversation_id ?? 'conversation')),
    `${safeStoragePart(messageId)}.${extension}`,
  ].join('/')

  const { error: uploadError } = await adminClient.storage
    .from(WHATSAPP_MEDIA_BUCKET)
    .upload(storagePath, new Blob([bytes], { type: contentType }), {
      contentType,
      upsert: true,
    })

  if (uploadError) {
    console.error('❌ [WHATSAPP-MEDIA] Storage upload failed', uploadError)
    return jsonResponse({ error: 'Unable to store WhatsApp media' }, 500)
  }

  const { data: publicUrlData } = adminClient.storage
    .from(WHATSAPP_MEDIA_BUCKET)
    .getPublicUrl(storagePath)
  const publicUrl = publicUrlData.publicUrl
  const isImageLike = source.messageType === 'image' || source.messageType === 'sticker'
  const metadataUpdates: JsonRecord = {
    whatsapp_media_id: source.mediaId,
    media_id: source.mediaId,
    media_source: 'whatsapp_cloud_api',
    url: publicUrl,
    ...(isImageLike ? { media_url: publicUrl } : {
      document_url: publicUrl,
      documentUrl: publicUrl,
    }),
    filename,
    originalFilename: filename,
    extension,
    contentType,
    content_type: contentType,
    sizeBytes: bytes.byteLength,
    size_bytes: bytes.byteLength,
    storageBucket: WHATSAPP_MEDIA_BUCKET,
    storage_bucket: WHATSAPP_MEDIA_BUCKET,
    storagePath: storagePath,
    storage_path: storagePath,
    whatsapp_media_info: info,
  }
  const nextMetadata = {
    ...metadata,
    ...metadataUpdates,
  }

  const { error: updateError } = await adminClient
    .from('messages')
    .update({ metadata: nextMetadata })
    .eq('id', messageId)

  if (updateError) {
    console.error('❌ [WHATSAPP-MEDIA] Message metadata update failed', updateError)
    return jsonResponse({ error: 'Unable to update message media metadata' }, 500)
  }

  return jsonResponse({
    url: publicUrl,
    metadata: metadataUpdates,
    already_hydrated: false,
  })
})
