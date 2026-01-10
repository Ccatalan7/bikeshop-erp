import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

/**
 * Gmail Push Webhook
 * 
 * Receives push notifications from Google Cloud Pub/Sub when new emails arrive.
 * The Pub/Sub subscription should be configured to push to this endpoint.
 * 
 * Flow:
 * 1. New email arrives in Gmail
 * 2. Gmail API sends notification to Pub/Sub topic
 * 3. Pub/Sub pushes to this webhook
 * 4. We decode the message and update `email_push_subscriptions` table
 * 5. Supabase Realtime notifies the Flutter app
 * 6. App fetches new emails from Gmail
 */
serve(async (req) => {
    console.log('📧 [GMAIL-PUSH] ========== WEBHOOK RECEIVED ==========')
    console.log('📧 [GMAIL-PUSH] Method:', req.method)
    console.log('📧 [GMAIL-PUSH] Time:', new Date().toISOString())

    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        // Create Supabase client with service role (to update any user's subscription)
        const supabase = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        // Parse Pub/Sub message
        const body = await req.json()
        console.log('📧 [GMAIL-PUSH] Pub/Sub body:', JSON.stringify(body, null, 2))

        // Pub/Sub sends messages in this format:
        // {
        //   "message": {
        //     "data": "<base64 encoded>",
        //     "messageId": "...",
        //     "publishTime": "..."
        //   },
        //   "subscription": "projects/.../subscriptions/..."
        // }

        const message = body.message
        if (!message?.data) {
            console.log('📧 [GMAIL-PUSH] No message data - might be a test ping')
            return new Response(JSON.stringify({ status: 'ok', message: 'No data' }), {
                status: 200,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' }
            })
        }

        // Decode base64 message data
        const decodedData = atob(message.data)
        console.log('📧 [GMAIL-PUSH] Decoded message:', decodedData)

        // Gmail sends: {"emailAddress":"user@gmail.com","historyId":"12345"}
        const notification = JSON.parse(decodedData)
        const { emailAddress, historyId } = notification

        console.log('📧 [GMAIL-PUSH] Email:', emailAddress)
        console.log('📧 [GMAIL-PUSH] History ID:', historyId)

        if (!emailAddress) {
            console.error('📧 [GMAIL-PUSH] No emailAddress in notification')
            return new Response(JSON.stringify({ error: 'No emailAddress' }), {
                status: 400,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' }
            })
        }

        // Find the user by their Gmail address
        // We look up in email_push_subscriptions where we stored the email_address
        const { data: subs, error: subError } = await supabase
            .from('email_push_subscriptions')
            .select('user_id')
            .eq('provider', 'gmail')
            .eq('email_address', emailAddress)
            .limit(1)

        if (subError) {
            console.error('📧 [GMAIL-PUSH] specific lookup error:', subError)
            return new Response(JSON.stringify({ status: 'ok', warning: 'User lookup error' }), {
                status: 200,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' }
            })
        }

        if (!subs || subs.length === 0) {
            console.log('📧 [GMAIL-PUSH] No user found for email:', emailAddress)
            // Try fallback to zoho_tokens just in case (legacy)
            const { data: tokens } = await supabase
                .from('zoho_tokens')
                .select('user_id')
                .eq('provider', 'gmail')
                .eq('email', emailAddress)
                .limit(1)

            if (!tokens || tokens.length === 0) {
                return new Response(JSON.stringify({ status: 'ok', warning: 'User not found' }), {
                    status: 200,
                    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
                })
            }
            console.log('📧 [GMAIL-PUSH] Found user via legacy tokens:', tokens[0].user_id)
            var userId = tokens[0].user_id
        } else {
            var userId = subs[0].user_id
        }

        console.log('📧 [GMAIL-PUSH] Found user:', userId)

        // Trigger notification to the app via the notify_new_email function
        const { error: notifyError } = await supabase.rpc('notify_new_email', {
            p_user_id: userId,
            p_provider: 'gmail',
            p_history_id: historyId,
            p_notification_data: { emailAddress, historyId, timestamp: new Date().toISOString() }
        })

        if (notifyError) {
            console.error('📧 [GMAIL-PUSH] Notify error:', notifyError)
            // Still return 200 to avoid retries
        } else {
            console.log('📧 [GMAIL-PUSH] ✅ Notification sent to app!')
        }

        console.log('📧 [GMAIL-PUSH] ========== COMPLETE ==========')
        return new Response(JSON.stringify({ status: 'ok' }), {
            status: 200,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })

    } catch (error) {
        console.error('📧 [GMAIL-PUSH] ❌ Error:', error)
        // Always return 200 to prevent Pub/Sub retries flooding us
        return new Response(JSON.stringify({ status: 'ok', error: error.message }), {
            status: 200,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
    }
})
