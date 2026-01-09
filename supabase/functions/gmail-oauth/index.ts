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
    // Redirects from Google -> Edge Function -> Frontend
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
                return Response.redirect(`${mobileDeepLink}?provider=gmail&error=${error}`, 302)
            }
            return Response.redirect(`${frontendBase}?gmail_error=${error}#/mail`, 302)
        }

        if (code) {
            if (isMobile) {
                // Redirect to mobile app via deep link
                console.log('[Gmail OAuth] Redirecting to mobile app')
                return Response.redirect(`${mobileDeepLink}?provider=gmail&code=${code}`, 302)
            }
            // Redirect with query param BEFORE hash for reliable Uri.base parsing
            return Response.redirect(`${frontendBase}?gmail_code=${code}#/mail`, 302)
        }

        return new Response('Method not allowed', { status: 405 })
    }

    try {
        const reqBody = await req.json()

        // Get secrets
        const clientId = Deno.env.get('GMAIL_CLIENT_ID')
        const clientSecret = Deno.env.get('GMAIL_CLIENT_SECRET')

        if (!clientId || !clientSecret) {
            throw new Error('Missing Gmail credentials')
        }

        // CASE 2: Token Exchange
        if (reqBody.grant_type) {
            const { code, redirect_uri, refresh_token, grant_type } = reqBody

            const params: Record<string, string> = {
                client_id: clientId,
                client_secret: clientSecret,
            }

            if (grant_type === 'refresh_token') {
                if (!refresh_token) throw new Error('Missing refresh_token')
                params.grant_type = 'refresh_token'
                params.refresh_token = refresh_token
            } else {
                if (!code || !redirect_uri) throw new Error('Missing code or redirect_uri')
                params.grant_type = 'authorization_code'
                params.code = code
                params.redirect_uri = redirect_uri
            }

            console.log(`[Gmail Token Exchange] ${grant_type}`)

            const response = await fetch('https://oauth2.googleapis.com/token', {
                method: 'POST',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: new URLSearchParams(params),
            })

            const data = await response.json()

            if (data.error) throw new Error(data.error_description || data.error)

            // Fetch user email/profile if new access token
            let userInfo = {}
            const accessToken = data.access_token

            if (accessToken) {
                try {
                    const profileRes = await fetch('https://www.googleapis.com/gmail/v1/users/me/profile', {
                        headers: { 'Authorization': `Bearer ${accessToken}` }
                    })
                    if (profileRes.ok) {
                        userInfo = await profileRes.json()
                    }
                } catch (e) {
                    console.error('Profile fetch error', e)
                }
            }

            return new Response(JSON.stringify({ ...data, user_info: userInfo }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            })
        }

        // CASE 3: API Proxy
        if (reqBody.proxy_url) {
            const { proxy_url, method, body, gmail_token } = reqBody

            if (!gmail_token) throw new Error('Missing gmail_token')

            console.log(`[Gmail Proxy] ${method || 'GET'} ${proxy_url}`)

            const fetchOptions: RequestInit = {
                method: method || 'GET',
                headers: {
                    'Authorization': `Bearer ${gmail_token}`,
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
        console.error('Gmail Edge Function Error:', error)
        return new Response(JSON.stringify({ error: error.message }), {
            status: 400,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
    }
})
