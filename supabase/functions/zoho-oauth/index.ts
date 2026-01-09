import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
    const url = new URL(req.url)

    // Handle CORS preflight requests
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    // CASE 1: OAuth Callback Redirect (GET)
    // Redirects from Zoho -> Edge Function -> Frontend (with param renaming to avoid Supabase conflict)
    if (req.method === 'GET') {
        const code = url.searchParams.get('code')
        const error = url.searchParams.get('error')
        const state = url.searchParams.get('state') // Contains platform info

        // Check if this is a mobile OAuth callback
        const isMobile = state === 'mobile'

        // Frontend URL (Base)
        const frontendBase = 'https://project-vinabike.web.app'
        // Mobile deep link base
        const mobileDeepLink = 'vinabike://mail/oauth'

        if (error) {
            if (isMobile) {
                return Response.redirect(`${mobileDeepLink}?provider=zoho&error=${error}`, 302)
            }
            return Response.redirect(`${frontendBase}?error=${error}#/mail`, 302)
        }

        if (code) {
            if (isMobile) {
                // Redirect to mobile app via deep link
                console.log('[Zoho OAuth] Redirecting to mobile app')
                return Response.redirect(`${mobileDeepLink}?provider=zoho&code=${code}`, 302)
            }
            // Redirect with query param BEFORE hash for reliable Uri.base parsing
            // Structure: https://host/?zoho_code=...#/mail
            return Response.redirect(`${frontendBase}?zoho_code=${code}#/mail`, 302)
        }

        return new Response('Method not allowed', { status: 405 })
    }

    try {
        const reqBody = await req.json()

        // Get secrets
        const clientId = Deno.env.get('ZOHO_CLIENT_ID')
        const clientSecret = Deno.env.get('ZOHO_CLIENT_SECRET')

        if (!clientId || !clientSecret) {
            throw new Error('Missing Zoho credentials')
        }

        // CASE 2: Token Exchange
        if (reqBody.grant_type) {
            const { code, redirect_uri, refresh_token, grant_type } = reqBody
            const params = new URLSearchParams()
            params.append('client_id', clientId)
            params.append('client_secret', clientSecret)

            if (grant_type === 'refresh_token') {
                if (!refresh_token) throw new Error('Missing refresh_token')
                params.append('grant_type', 'refresh_token')
                params.append('refresh_token', refresh_token)
            } else {
                if (!code || !redirect_uri) throw new Error('Missing code or redirect_uri')
                params.append('grant_type', 'authorization_code')
                params.append('code', code)
                params.append('redirect_uri', redirect_uri)
            }

            console.log(`[Token Exchange] Calling Zoho token endpoint: ${grant_type}`)

            const response = await fetch('https://accounts.zoho.com/oauth/v2/token', {
                method: 'POST',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: params,
            })

            const data = await response.json()

            if (data.error) throw new Error(data.error)

            // Fetch Account ID if new access token
            let accountInfo = {}
            const accessToken = data.access_token

            if (accessToken) {
                try {
                    const accRes = await fetch('https://mail.zoho.com/api/accounts', {
                        headers: { 'Authorization': `Zoho-oauthtoken ${accessToken}` }
                    })
                    if (accRes.ok) {
                        const accData = await accRes.json()
                        if (accData.data && accData.data.length > 0) {
                            accountInfo = accData.data[0]
                        }
                    }
                } catch (e) {
                    console.error('Account fetch error', e)
                }
            }

            return new Response(JSON.stringify({ ...data, account_info: accountInfo }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            })
        }

        // CASE 3: API Proxy
        if (reqBody.proxy_url) {
            const { proxy_url, method, body, zoho_token } = reqBody

            if (!zoho_token) throw new Error('Missing zoho_token')

            console.log(`[Proxy] ${method || 'GET'} ${proxy_url}`)

            const fetchOptions: any = {
                method: method || 'GET',
                headers: {
                    'Authorization': `Zoho-oauthtoken ${zoho_token}`,
                    'Content-Type': 'application/json'
                }
            }

            if (body) fetchOptions.body = JSON.stringify(body)

            const response = await fetch(proxy_url, fetchOptions)
            const responseText = await response.text()

            let responseData
            try {
                responseData = JSON.parse(responseText)
            } catch (e) {
                responseData = { text: responseText }
            }

            return new Response(JSON.stringify(responseData), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: response.status
            })
        }

        throw new Error('Invalid request')

    } catch (error) {
        console.error('Edge Function Error:', error)
        return new Response(JSON.stringify({ error: error.message }), {
            status: 400,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
    }
})
