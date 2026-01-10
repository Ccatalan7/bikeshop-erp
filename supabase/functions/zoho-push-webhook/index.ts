import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

/**
 * Zoho Mail Push Webhook
 * 
 * Receives outgoing webhooks from Zoho Mail when new emails arrive.
 * Configure in Zoho Mail > Settings > Integrations > Outgoing Webhooks.
 */
serve(async (req) => {
    console.log('📧 [ZOHO-PUSH] ========== WEBHOOK RECEIVED ==========')
    console.log('📧 [ZOHO-PUSH] Method:', req.method)
    console.log('📧 [ZOHO-PUSH] Time:', new Date().toISOString())

    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        // Create Supabase client with service role
        const supabase = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        // Parse body
        let body
        try {
            body = await req.json()
        } catch (e) {
            console.log('📧 [ZOHO-PUSH] No JSON body or parse error')
            // Some verification requests might be empty or URL params
            return new Response(JSON.stringify({ status: 'ok' }), { headers: corsHeaders })
        }

        console.log('📧 [ZOHO-PUSH] Body:', JSON.stringify(body, null, 2))

        // Zoho payload usually contains info about the email
        // Example: { "summary": "...", "sender": "user@example.com", ... }
        // We need to identify WHICH user this webhook belongs to.
        // Option 1: The user configures the webhook with a query param ?userId=... (Secure)
        // Option 2: We look up by the 'to' address if available in the payload.

        const url = new URL(req.url)
        let userId = url.searchParams.get('userId')
        const emailAddress = body.toAddress || body.to || body.recipient

        if (!userId && emailAddress) {
            // Look up by email if userId not provided in URL
            console.log('📧 [ZOHO-PUSH] No userId in URL, looking up by email:', emailAddress)
            const { data: subs } = await supabase
                .from('email_push_subscriptions')
                .select('user_id')
                .eq('provider', 'zoho')
                .eq('email_address', emailAddress)
                .limit(1)

            if (subs && subs.length > 0) {
                userId = subs[0].user_id
            }
        }

        if (!userId) {
            console.error('📧 [ZOHO-PUSH] Could not identify user (userId param missing and no matching email found)')
            return new Response(JSON.stringify({ error: 'User identification failed' }), {
                status: 200, // Return 200 to Zoho so it doesn't retry endlessly
                headers: corsHeaders
            })
        }

        console.log('📧 [ZOHO-PUSH] Identified User:', userId)

        // Trigger notification
        const { error: notifyError } = await supabase.rpc('notify_new_email', {
            p_user_id: userId,
            p_provider: 'zoho',
            p_history_id: null, // Zoho doesn't use historyId
            p_notification_data: {
                ...body,
                timestamp: new Date().toISOString()
            }
        })

        if (notifyError) {
            console.error('📧 [ZOHO-PUSH] Notify error:', notifyError)
        } else {
            console.log('📧 [ZOHO-PUSH] ✅ Notification sent to app!')
        }

        console.log('📧 [ZOHO-PUSH] ========== COMPLETE ==========')
        return new Response(JSON.stringify({ status: 'success' }), {
            status: 200,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })

    } catch (error) {
        console.error('📧 [ZOHO-PUSH] ❌ Error:', error)
        return new Response(JSON.stringify({ status: 'error', message: error.message }), {
            status: 200,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
    }
})
