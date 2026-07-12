import os
import sys
import time
import requests
from typing import List, Dict
from supabase import create_client, Client

# ============================================================================
# CONFIGURATION
# ============================================================================
# Zoho
ZOHO_CLIENT_ID = os.environ.get("ZOHO_CLIENT_ID", "")
ZOHO_CLIENT_SECRET = os.environ.get("ZOHO_CLIENT_SECRET", "")
ZOHO_REFRESH_TOKEN = os.environ.get("ZOHO_REFRESH_TOKEN", "")
ZOHO_ORG_ID = "788658742"
ZOHO_API_DOMAIN = "https://www.zohoapis.com"
ZOHO_OAUTH_DOMAIN = "https://accounts.zoho.com"

# Supabase
SUPABASE_URL = "https://xzdvtzdqjeyqxnkqprtf.supabase.co"
SUPABASE_KEY = os.environ.get("SUPABASE_SECRET_KEY", "")
TENANT_ID = "5443b130-cc28-45af-a420-cd500b288890"

RATE_LIMIT_DELAY = 0.5 

def get_zoho_token() -> str:
    token_url = f"{ZOHO_OAUTH_DOMAIN}/oauth/v2/token"
    params = {
        'refresh_token': ZOHO_REFRESH_TOKEN,
        'client_id': ZOHO_CLIENT_ID,
        'client_secret': ZOHO_CLIENT_SECRET,
        'grant_type': 'refresh_token'
    }
    response = requests.post(token_url, params=params)
    response.raise_for_status()
    return response.json()['access_token']

def fetch_zoho_products(access_token: str) -> List[Dict]:
    url = f"{ZOHO_API_DOMAIN}/inventory/v1/items"
    headers = {'Authorization': f'Zoho-oauthtoken {access_token}'}
    all_items = []
    page = 1
    while True:
        params = {'organization_id': ZOHO_ORG_ID, 'page': page, 'per_page': 200}
        response = requests.get(url, headers=headers, params=params)
        response.raise_for_status()
        data = response.json()
        items = data.get('items', [])
        if not items:
            break
        all_items.extend(items)
        page += 1
        time.sleep(RATE_LIMIT_DELAY)
        if not data.get('page_context', {}).get('has_more_page'):
            break
    return all_items

def fetch_flutter_products(supabase: Client) -> List[Dict]:
    all_products = []
    page_size = 1000
    offset = 0
    while True:
        response = supabase.table('products') \
            .select('id,name,sku,price,cost,brand,supplier_id,tenant_id,image_url') \
            .eq('tenant_id', TENANT_ID) \
            .range(offset, offset + page_size - 1) \
            .execute()
        if not response.data:
            break
        all_products.extend(response.data)
        if len(response.data) < page_size:
            break
        offset += page_size
    return all_products


def main():
    print("Fetching data for summary...")
    access_token = get_zoho_token()
    supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
    
    zoho_products = fetch_zoho_products(access_token)
    flutter_products = fetch_flutter_products(supabase)
    
    zoho_map = {p.get('sku'): p for p in zoho_products if p.get('sku')}
    
    missing_data_items = []
    
    for flutter_prod in flutter_products:
        sku = flutter_prod.get('sku')
        if not sku:
            continue
            
        zoho_prod = zoho_map.get(sku)
        if not zoho_prod:
            continue
            
        # Check if flutter product is missing brand or supplier
        has_brand = bool(flutter_prod.get('brand')) and flutter_prod.get('brand') != 'N/A'
        has_supplier = bool(flutter_prod.get('supplier_id'))  # if we can map it? Actually Zoho has vendor_name.
        
        # If it's missing in flutter
        brand_in_flutter = flutter_prod.get('brand', '') or ''
        
        brand_in_zoho = zoho_prod.get('brand', '') or ''
        supplier_in_zoho = zoho_prod.get('vendor_name', '') or ''
        
        needs_update = False
        reasons = []
        
        if not brand_in_flutter and brand_in_zoho:
            needs_update = True
            reasons.append(f"Missing Brand (Zoho has: {brand_in_zoho})")
            
        # Flutter's brand doesn't match Zoho's brand
        if brand_in_flutter and brand_in_zoho and brand_in_flutter.lower() != brand_in_zoho.lower():
             needs_update = True
             reasons.append(f"Brand Mismatch (Flutter: {brand_in_flutter} -> Zoho: {brand_in_zoho})")
            
        # We will update brand for all these.
        if needs_update:
            missing_data_items.append({
                'sku': sku,
                'name': flutter_prod.get('name', ''),
                'reasons': reasons
            })
            
    # New items from zoho not in flutter
    flutter_skus = {p.get('sku') for p in flutter_products if p.get('sku')}
    new_in_zoho = []
    for zh in zoho_products:
        sku = zh.get('sku')
        if sku and sku not in flutter_skus:
            new_in_zoho.append({
                'sku': sku,
                'name': zh.get('name', ''),
                'brand': zh.get('brand', ''),
                'supplier': zh.get('vendor_name', '')
            })

    print("\\n" + "=" * 80)
    print("SUMMARY")
    print("=" * 80)
    print("MAPPING LOGIC:")
    print("Both Flutter and Zoho have a 'SKU' column. We map exactly 1:1 on the SKU string.")
    
    print(f"\\n1. Existing products in flutter that need Brand/Supplier updates: {len(missing_data_items)}")
    for item in missing_data_items[:10]:
        print(f"   - {item['sku']} ({item['name']}): {', '.join(item['reasons'])}")
    if len(missing_data_items) > 10:
        print(f"   ... and {len(missing_data_items) - 10} more.")
        
    print(f"\\n2. New products entirely missing from Flutter (found in Zoho): {len(new_in_zoho)}")
    for item in new_in_zoho[:5]:
        print(f"   - {item['sku']} ({item['name']}) [Brand: {item['brand']}, Supplier: {item['supplier']}]")
    if len(new_in_zoho) > 5:
        print(f"   ... and {len(new_in_zoho) - 5} more.")

if __name__ == '__main__':
    main()
