"""
Exchange grant code for refresh token - One-time use script
"""
import requests

# User provided credentials
CLIENT_ID = "1000.LKVKZREYRMW7ZXKHF8O40ZDZ9XBR0A"
CLIENT_SECRET = "cfc323be8f4cb6190356248b7a24cd12646009afe4"
GRANT_CODE = "1000.20da5bace0b2b6976c8bdb938b8d7ba6.8334698f09dcb3491c570dcd3e7d82fa"
ZOHO_ORG_ID = "788658742"

def main():
    print("\n🔑 Exchanging grant code for refresh token...")
    
    token_url = "https://accounts.zoho.com/oauth/v2/token"
    
    payload = {
        'grant_type': 'authorization_code',
        'client_id': CLIENT_ID,
        'client_secret': CLIENT_SECRET,
        'code': GRANT_CODE,
        'redirect_uri': '',
        'organization_id': ZOHO_ORG_ID
    }
    
    response = requests.post(token_url, params=payload)
    
    print(f"Status: {response.status_code}")
    print(f"Response: {response.text}")
    
    data = response.json()
    
    if 'refresh_token' in data:
        print(f"\n✅ SUCCESS!")
        print(f"Refresh Token: {data['refresh_token']}")
        print(f"Access Token: {data['access_token'][:50]}...")
        return data['refresh_token'], data['access_token']
    else:
        print(f"\n❌ ERROR: {data}")
        return None, None

if __name__ == "__main__":
    main()
