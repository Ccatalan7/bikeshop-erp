"""
Quick analysis: How many Zoho products have codigo proveedor != SKU?
"""
import os
import requests

# Zoho credentials
CLIENT_ID = os.environ.get("ZOHO_CLIENT_ID", "")
CLIENT_SECRET = os.environ.get("ZOHO_CLIENT_SECRET", "")
REFRESH_TOKEN = os.environ.get("ZOHO_REFRESH_TOKEN", "")
ZOHO_ORG_ID = "788658742"

def get_zoho_access_token():
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
    print("\n📊 Analyzing Zoho products: código proveedor vs SKU")
    print("=" * 60)
    
    access_token = get_zoho_access_token()
    
    headers = {
        'Authorization': f'Zoho-oauthtoken {access_token}',
        'Content-Type': 'application/json'
    }
    
    same_as_sku = []
    different_from_sku = []
    
    page = 1
    while True:
        url = "https://www.zohoapis.com/inventory/v1/items"
        params = {
            'organization_id': ZOHO_ORG_ID,
            'page': page,
            'per_page': 200
        }
        
        response = requests.get(url, headers=headers, params=params)
        data = response.json()
        
        items = data.get('items', [])
        if not items:
            break
        
        for item in items:
            supplier_code = item.get('cf_c_digo_proveedor') or item.get('cf_c_digo_proveedor_unformatted')
            sku = item.get('sku', '')
            
            if supplier_code:
                if str(supplier_code) == str(sku):
                    same_as_sku.append({'sku': sku, 'code': supplier_code, 'name': item.get('name', '')})
                else:
                    different_from_sku.append({'sku': sku, 'code': supplier_code, 'name': item.get('name', '')})
        
        page += 1
        if not data.get('page_context', {}).get('has_more_page'):
            break
    
    total_with_code = len(same_as_sku) + len(different_from_sku)
    
    print(f"\n📦 Total products with código proveedor: {total_with_code}")
    print(f"\n   ✅ Same as SKU: {len(same_as_sku)}")
    print(f"   🔀 Different from SKU: {len(different_from_sku)}")
    
    if different_from_sku:
        print(f"\n🔀 Examples where código proveedor ≠ SKU (first 15):")
        for item in different_from_sku[:15]:
            print(f"   • SKU: {item['sku']} → Código: {item['code']} ({item['name'][:40]}...)")

if __name__ == "__main__":
    main()
