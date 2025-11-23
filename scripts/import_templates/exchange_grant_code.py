"""
Exchange Zoho Grant Code for Refresh Token

Run this ONCE when you get a new grant code from Zoho OAuth.
The refresh token will be permanent (valid for months/years).
"""

import requests

def exchange_grant_code():
    print("\n" + "=" * 80)
    print("🔑 EXCHANGE ZOHO GRANT CODE FOR REFRESH TOKEN")
    print("=" * 80)
    
    print("\nYou need these 3 values from Zoho:")
    print("1. Grant Code (one-time code from OAuth authorization)")
    print("2. Client ID")
    print("3. Client Secret")
    print("4. Redirect URI (must match what you used in OAuth)")
    
    grant_code = input("\nGrant Code: ").strip()
    client_id = input("Client ID: ").strip()
    client_secret = input("Client Secret: ").strip()
    redirect_uri = input("Redirect URI (or press Enter for default): ").strip()
    
    if not redirect_uri:
        redirect_uri = "https://www.zoho.com/oauth/callback"
    
    print("\n🔄 Exchanging grant code for refresh token...")
    
    token_url = "https://accounts.zoho.com/oauth/v2/token"
    token_params = {
        'grant_type': 'authorization_code',
        'client_id': client_id,
        'client_secret': client_secret,
        'redirect_uri': redirect_uri,
        'code': grant_code
    }
    
    try:
        response = requests.post(token_url, params=token_params)
        response.raise_for_status()
        
        data = response.json()
        
        if 'refresh_token' in data:
            print("\n" + "=" * 80)
            print("✅ SUCCESS! Here's your refresh token:")
            print("=" * 80)
            print(f"\nREFRESH TOKEN: {data['refresh_token']}")
            print(f"\nAccess Token (expires in 1 hour): {data.get('access_token', 'N/A')}")
            print("\n⚠️  SAVE THE REFRESH TOKEN - You'll use it for all future imports!")
            print("=" * 80)
            
            return data['refresh_token']
        else:
            print("\n❌ ERROR: No refresh token in response")
            print(f"Response: {data}")
            return None
            
    except requests.exceptions.HTTPError as e:
        print(f"\n❌ HTTP ERROR: {e}")
        print(f"Response: {e.response.text}")
        return None
    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        return None

if __name__ == "__main__":
    try:
        exchange_grant_code()
    except KeyboardInterrupt:
        print("\n⚠️  Cancelled by user")
    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
