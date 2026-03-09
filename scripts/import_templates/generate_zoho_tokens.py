"""
🔑 Generate Zoho Refresh Token from Grant Token

This script exchanges a Zoho Grant Token for a Refresh Token.

Flow:
1. User authorizes app in Zoho → Gets a GRANT TOKEN (one-time use)
2. This script exchanges grant token for REFRESH TOKEN (long-lived)
3. Refresh token is stored and reused for all future API calls

Usage:
    python generate_zoho_tokens.py
"""

import requests

ZOHO_OAUTH_DOMAIN = "https://accounts.zoho.com"
ZOHO_ORG_ID = "788658742"


def generate_refresh_token(client_id: str, client_secret: str, grant_token: str) -> dict:
    """
    Exchange Zoho grant token for refresh token.
    
    Args:
        client_id: Zoho OAuth Client ID
        client_secret: Zoho OAuth Client Secret
        grant_token: One-time authorization code from Zoho OAuth flow
    
    Returns:
        Dict with 'refresh_token' and 'access_token'
    
    Example:
        This is what happens after user authorizes your app:
        1. Zoho redirects with: ?code=1000.xxxxxxxx...
        2. You call this function with that code as grant_token
        3. You get back a refresh_token to store for later
    """
    print("\n" + "=" * 80)
    print("🔑 Zoho Token Generation")
    print("=" * 80)
    
    token_url = f"{ZOHO_OAUTH_DOMAIN}/oauth/v2/token"
    
    payload = {
        'grant_type': 'authorization_code',  # ← GRANT TOKEN exchange (one-time use, ~10 min)
        'client_id': client_id,
        'client_secret': client_secret,
        'code': grant_token,  # ← One-time authorization code
        'redirect_uri': 'https://localhost:8000',  # 🔑 CRITICAL: Must exactly match the URL used to generate
        'organization_id': ZOHO_ORG_ID  # 🔑 CRITICAL: Org ID REQUIRED!
    }
    
    print(f"\n📡 Exchanging grant token for refresh token...")
    print(f"   URL: {token_url}")
    print(f"   Organization ID: {ZOHO_ORG_ID}")
    
    try:
        response = requests.post(token_url, params=payload)
        response.raise_for_status()
        
        data = response.json()
        
        if 'access_token' not in data or 'refresh_token' not in data:
            print(f"\n❌ ERROR: Unexpected response from Zoho:")
            print(f"   {data}")
            print(f"\n💡 Common issues:")
            print(f"   1. Grant token already used (one-time only)")
            print(f"   2. Grant token expired (valid for ~10 minutes)")
            print(f"   3. Redirect URI doesn't match your OAuth app settings")
            return None
        
        print(f"\n✅ Token generation successful!")
        print(f"\n📋 Token Lifetimes:")
        print(f"   • Access Token: {data['access_token'][:20]}... (expires in 1 hour, auto-refreshes)")
        print(f"   • Refresh Token: {data['refresh_token'][:20]}... (valid for MONTHS)")
        print(f"\n💾 🔑 STORE YOUR REFRESH TOKEN - You'll use it for all future imports:")
        print(f"   {data['refresh_token']}")
        
        return {
            'access_token': data['access_token'],
            'refresh_token': data['refresh_token'],
            'expires_in': data.get('expires_in', 3600)
        }
    
    except requests.exceptions.RequestException as e:
        print(f"\n❌ ERROR: {e}")
        print(f"\nResponse: {e.response.text if hasattr(e, 'response') else 'N/A'}")
        return None


def main():
    print("\n" + "=" * 80)
    print("🔐 Zoho OAuth Token Generator")
    print("=" * 80)
    
    print("\n📖 How this works:")
    print("   1. You authorize the app in Zoho (one-time)")
    print("   2. Zoho gives you a GRANT TOKEN (one-time use, ~10 min expiry)")
    print("   3. This script exchanges it for a REFRESH TOKEN (months-long validity)")
    print("   4. You store the REFRESH TOKEN for all future API calls")
    
    print("\n🔑 Get your grant token:")
    print("   1. Visit: https://accounts.zoho.com/oauth/v2/auth?response_type=code&client_id={CLIENT_ID}&scope=ZohoInventory.items.CREATE,ZohoInventory.items.READ,ZohoInventory.items.UPDATE&redirect_uri=https://localhost:8000")
    print("   2. Authorize access")
    print("   3. You'll be redirected to localhost with: ?code=1000.xxxxxxxx...")
    print("   4. Copy the code parameter value (that's your grant token)")
    
    print("\n" + "=" * 80)
    print("Enter your credentials:")
    print("=" * 80)
    
    client_id = input("\n🔑 Client ID: ").strip()
    client_secret = input("🔑 Client Secret: ").strip()
    grant_token = input("🔑 Grant Token (authorization code): ").strip()
    
    if not all([client_id, client_secret, grant_token]):
        print("\n❌ All fields required!")
        return
    
    # Generate tokens
    result = generate_refresh_token(client_id, client_secret, grant_token)
    
    if result:
        print("\n" + "=" * 80)
        print("✅ NEXT STEP: Use this refresh token in import scripts")
        print("=" * 80)
        print(f"\nFor import scripts, provide:")
        print(f"  - Client ID: {client_id}")
        print(f"  - Client Secret: {client_secret}")
        print(f"  - Refresh Token: {result['refresh_token']}")
        print("\nThe script will automatically get access tokens when needed.")


if __name__ == "__main__":
    main()
