"""
Explore Zoho product fields to find 'código proveedor' and image fields
"""
import requests
import json

# Credentials
CLIENT_ID = "1000.LKVKZREYRMW7ZXKHF8O40ZDZ9XBR0A"
CLIENT_SECRET = "cfc323be8f4cb6190356248b7a24cd12646009afe4"
REFRESH_TOKEN = "1000.0dfaca4f7cece1a32d2e752eb855e2e5.0a5b064b44a904b0ad207c4a3edd2f06"
ZOHO_ORG_ID = "788658742"

def get_access_token():
    token_url = "https://accounts.zoho.com/oauth/v2/token"
    payload = {
        'grant_type': 'refresh_token',
        'client_id': CLIENT_ID,
        'client_secret': CLIENT_SECRET,
        'refresh_token': REFRESH_TOKEN
    }
    response = requests.post(token_url, params=payload)
    return response.json()['access_token']

def main():
    print("\n🔍 Exploring Zoho product fields...")
    
    access_token = get_access_token()
    print("✅ Got access token")
    
    headers = {
        'Authorization': f'Zoho-oauthtoken {access_token}',
        'Content-Type': 'application/json'
    }
    
    # Get a few products with ALL fields
    url = f"https://www.zohoapis.com/inventory/v1/items"
    params = {
        'organization_id': ZOHO_ORG_ID,
        'per_page': 3
    }
    
    response = requests.get(url, headers=headers, params=params)
    data = response.json()
    
    print(f"\n📦 Sample products (first 3):\n")
    
    for item in data.get('items', [])[:3]:
        print(f"=" * 80)
        print(f"Name: {item.get('name')}")
        print(f"SKU: {item.get('sku')}")
        print(f"\n🔑 ALL FIELDS:")
        for key, value in item.items():
            if value:  # Only print non-empty values
                print(f"  {key}: {value}")
        print()
    
    # Also check if there's custom_fields or cf_ prefixed fields
    first_item = data.get('items', [{}])[0] if data.get('items') else {}
    
    print("\n" + "=" * 80)
    print("🔍 LOOKING FOR SUPPLIER CODE FIELD:")
    for key, value in first_item.items():
        if 'proveedor' in key.lower() or 'supplier' in key.lower() or 'vendor' in key.lower() or 'cf_' in key.lower() or 'custom' in key.lower():
            print(f"  FOUND: {key} = {value}")
    
    print("\n🔍 LOOKING FOR IMAGE FIELDS:")
    for key, value in first_item.items():
        if 'image' in key.lower() or 'photo' in key.lower() or 'picture' in key.lower() or 'document' in key.lower():
            print(f"  FOUND: {key} = {value}")

if __name__ == "__main__":
    main()
