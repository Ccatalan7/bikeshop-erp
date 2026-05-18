
import { createClient } from 'npm:@supabase/supabase-js@2'
import { JWT } from 'npm:google-auth-library'

interface NotificationPayload {
    type: 'INSERT'
    table: 'messages'
    record: {
        id: string
        conversation_id: string
        sender_id: string | null
        content: string | null
        type: string | null
        external_provider?: string | null
        message_direction?: string | null
        created_at: string
    }
    schema: 'public'
}

console.log("Push Notification Function Initialized")

Deno.serve(async (req) => {
    const payload: NotificationPayload = await req.json()

    // Only handle inserts
    if (payload.type !== 'INSERT') {
        return new Response(JSON.stringify({ message: 'Ignore non-insert' }), { headers: { 'Content-Type': 'application/json' } })
    }

    const supabase = createClient(
        Deno.env.get('SUPABASE_URL')!,
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    const { record } = payload

    // DEBUG: Log incoming message details
    console.log("📩 Message received:", {
        conversation_id: record.conversation_id,
        sender_id: record.sender_id,
        content_preview: record.content?.substring(0, 50)
    })

    const isExternalInbound = !record.sender_id && record.message_direction === 'inbound'

    // 1. Get recipients (other participants). External inbound messages such as
    // WhatsApp rows do not have an auth sender_id, so applying neq(null) breaks
    // the PostgREST UUID filter and prevents FCM from being sent.
    let participantsQuery = supabase
        .from('conversation_participants')
        .select('user_id')
        .eq('conversation_id', record.conversation_id)

    if (record.sender_id) {
        participantsQuery = participantsQuery.neq('user_id', record.sender_id) // Exclude internal sender
    }

    const { data: participants, error: pError } = await participantsQuery

    console.log("👥 Participants query result:", { participants, error: pError })

    if (pError || !participants || participants.length === 0) {
        console.error("No participants found or error", pError)
        return new Response(JSON.stringify({ message: 'No recipients' }), { headers: { 'Content-Type': 'application/json' } })
    }

    const recipientIds = participants.map(p => p.user_id)
    console.log("📋 Recipient IDs to notify:", recipientIds)

    // 2. Get FCM tokens for recipients
    const { data: tokens, error: tError } = await supabase
        .from('user_fcm_tokens')
        .select('fcm_token, user_id')
        .in('user_id', recipientIds)

    console.log("🔑 Token query result:", {
        tokenCount: tokens?.length || 0,
        error: tError,
        userIds: tokens?.map(t => t.user_id)
    })

    if (tError || !tokens || tokens.length === 0) {
        console.log("❌ No FCM tokens found for recipients:", recipientIds)
        return new Response(JSON.stringify({ message: 'No tokens found' }), { headers: { 'Content-Type': 'application/json' } })
    }

    // 3. Get Sender info (for notification title)
    // sender_id is the auth.users.id, not user_profiles.id
    // We need to join user_profiles → employees to get the name
    let senderName = isExternalInbound && record.external_provider === 'whatsapp'
        ? 'WhatsApp'
        : 'Usuario'

    if (record.sender_id) {
        try {
            console.log("Looking up sender for user_id:", record.sender_id)

            // First try: Get employee via user_profiles.employee_id
            const { data: userProfile, error: profileError } = await supabase
                .from('user_profiles')
                .select('employee_id')
                .eq('user_id', record.sender_id)
                .maybeSingle()

            console.log("User profile lookup:", { userProfile, error: profileError })

            if (userProfile?.employee_id) {
                // Get employee name
                const { data: employee } = await supabase
                    .from('employees')
                    .select('first_name, last_name')
                    .eq('id', userProfile.employee_id)
                    .maybeSingle()

                console.log("Employee lookup:", employee)

                if (employee) {
                    senderName = `${employee.first_name} ${employee.last_name}`.trim()
                }
            }

            // Fallback: Try auth.users metadata or email
            if (senderName === "Usuario") {
                console.log("No employee found, trying auth.users...")
                // Use Supabase Admin API to get user info
                const { data: authUser, error: authError } = await supabase.auth.admin.getUserById(record.sender_id)

                console.log("Auth user lookup:", { authUser: authUser?.user?.email, error: authError })

                if (authUser?.user) {
                    // Try metadata first (might have display_name or full_name)
                    const metadata = authUser.user.user_metadata
                    if (metadata?.full_name) {
                        senderName = metadata.full_name
                    } else if (metadata?.name) {
                        senderName = metadata.name
                    } else if (authUser.user.email) {
                        // Use email username as fallback
                        senderName = authUser.user.email.split('@')[0]
                    }
                }
            }

            if (senderName === "Usuario") {
                console.log("No name found anywhere, using fallback")
            }
        } catch (e) {
            console.error("Error fetching sender:", e)
        }
    }

    console.log("Final senderName:", senderName)

    const messageBody = record.type === 'text' ? (record.content || '') : '📷 Imagen adjunta'
    const senderIdForPayload = record.sender_id || 'external_whatsapp'
    const messageTypeForPayload = record.type || 'text'
    const contentForPayload = record.content || ''

    // 4. Send Notifications via FCM (DATA-ONLY for custom handling)
    const accessToken = await getAccessToken()

    const promises = tokens.map(async (t) => {
        try {
            const res = await fetch(`https://fcm.googleapis.com/v1/projects/${Deno.env.get('FIREBASE_PROJECT_ID')}/messages:send`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${accessToken}`,
                },
                body: JSON.stringify({
                    message: {
                        token: t.fcm_token,
                        // DATA-ONLY payload - prevents FCM auto-display, lets our code handle it
                        // This prevents duplicate notifications on web
                        data: {
                            id: record.id,
                            message_id: record.id,
                            conversation_id: record.conversation_id,
                            sender_id: senderIdForPayload,
                            sender_name: senderName,
                            title: senderName,
                            body: messageBody,
                            type: messageTypeForPayload,
                            content: contentForPayload,
                            created_at: record.created_at,
                            message_direction: record.message_direction ?? '',
                            external_provider: record.external_provider ?? '',
                            route: `/chat?conversation=${record.conversation_id}`,
                            click_action: 'FLUTTER_NOTIFICATION_CLICK',
                        },
                        // Android-specific: high priority for background wake + custom channel
                        android: {
                            priority: 'high',
                            // Include notification for Android since native app handles it
                            notification: {
                                title: senderName,
                                body: messageBody,
                                channel_id: 'chat_messages',
                                tag: record.conversation_id,
                            },
                        },
                        // iOS-specific
                        apns: {
                            payload: {
                                aps: {
                                    contentAvailable: true,
                                    mutableContent: true,
                                    alert: {
                                        title: senderName,
                                        body: messageBody
                                    },
                                    threadId: record.conversation_id,
                                }
                            }
                        },
                        // Web-specific: include notification here (not at top level) to prevent duplicate
                        webpush: {
                            headers: {
                                Urgency: 'high'
                            },
                            notification: {
                                title: senderName,
                                body: messageBody,
                                icon: '/icons/Icon-192.png',
                                badge: '/icons/Icon-192.png',
                                tag: record.conversation_id,
                                renotify: true
                            },
                            fcm_options: {
                                link: `/chat?conversation=${record.conversation_id}`
                            }
                        }
                    }
                })
            })
            const json = await res.json()
            console.log("FCM Response", json)
        } catch (e) {
            console.error("Error sending FCM", e)
        }
    })

    await Promise.all(promises)

    return new Response(JSON.stringify({ message: 'Notifications sent' }), { headers: { 'Content-Type': 'application/json' } })
})

// Helper to get Google Auth Token
async function getAccessToken() {
    const serviceAccount = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT') || '{}')
    if (!serviceAccount.private_key) {
        throw new Error("FIREBASE_SERVICE_ACCOUNT secret is missing or invalid")
    }

    const client = new JWT({
        email: serviceAccount.client_email,
        key: serviceAccount.private_key,
        scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
    })

    const res = await client.authorize()
    return res.access_token
}
