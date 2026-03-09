"""
Full analysis: Compare brand AND supplier between Zoho and Flutter
"""
import time
import json
import requests
from supabase import create_client, Client

ZOHO_CLIENT_ID = "1000.HEUWHSDCUE4GAN7CL3P045ICRU5V5B"
ZOHO_CLIENT_SECRET = "ffd0bc79a8e2456cef492010e34c3653a55d82be43"
ZOHO_REFRESH_TOKEN = "1000.1018c69651f1ca381b062c385a218e1d.72eb1094dbf04d5f018adee06494e3d1"
ZOHO_ORG_ID = "788658742"
ZOHO_API_DOMAIN = "https://www.zohoapis.com"
ZOHO_OAUTH_DOMAIN = "https://accounts.zoho.com"

SUPABASE_URL = "https://xzdvtzdqjeyqxnkqprtf.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh6ZHZ0emRxamV5cXhua3FwcnRmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjAwNjQyMzUsImV4cCI6MjA3NTY0MDIzNX0.q5OswWMx6C00dbSHlFSOKlv6BA6GKx36VtVSy8ohxAM"
TENANT_ID = "5443b130-cc28-45af-a420-cd500b288890"

def get_zoho_token():
    token_url = f"{ZOHO_OAUTH_DOMAIN}/oauth/v2/token"
    params = {'refresh_token': ZOHO_REFRESH_TOKEN, 'client_id': ZOHO_CLIENT_ID, 'client_secret': ZOHO_CLIENT_SECRET, 'grant_type': 'refresh_token'}
    return requests.post(token_url, params=params).json()['access_token']

def fetch_zoho_products(access_token):
    url = f"{ZOHO_API_DOMAIN}/inventory/v1/items"
    headers = {'Authorization': f'Zoho-oauthtoken {access_token}'}
    all_items = []
    page = 1
    while True:
        params = {'organization_id': ZOHO_ORG_ID, 'page': page, 'per_page': 200}
        data = requests.get(url, headers=headers, params=params).json()
        items = data.get('items', [])
        if not items: break
        all_items.extend(items)
        page += 1
        time.sleep(0.5)
        if not data.get('page_context', {}).get('has_more_page'): break
    return all_items

def fetch_flutter_products(supabase):
    all_products = []
    offset = 0
    while True:
        resp = supabase.table('products').select('id,name,sku,price,cost,brand,brand_id,supplier_id,supplier_name').eq('tenant_id', TENANT_ID).range(offset, offset + 999).execute()
        if not resp.data: break
        all_products.extend(resp.data)
        if len(resp.data) < 1000: break
        offset += 1000
    return all_products

def main():
    access_token = get_zoho_token()
    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
    
    zoho_products = fetch_zoho_products(access_token)
    flutter_products = fetch_flutter_products(supabase)
    
    zoho_map = {p.get('sku'): p for p in zoho_products if p.get('sku')}
    flutter_map = {p.get('sku'): p for p in flutter_products if p.get('sku')}
    
    # Collect all unique Zoho vendor names
    zoho_vendors = set()
    for zh in zoho_products:
        v = zh.get('vendor_name', '')
        if v: zoho_vendors.add(v)
    
    results = {
        'missing_brand': [],
        'missing_supplier': [],
        'brand_mismatch': [],
        'new_products': [],
    }
    
    # Check existing flutter products against zoho
    for fp in flutter_products:
        sku = fp.get('sku')
        if not sku or sku not in zoho_map:
            continue
        zh = zoho_map[sku]
        
        zoho_brand = zh.get('brand', '') or ''
        zoho_supplier = zh.get('vendor_name', '') or ''
        flutter_brand = fp.get('brand', '') or ''
        flutter_supplier = fp.get('supplier_name', '') or ''
        
        if not flutter_brand and zoho_brand:
            results['missing_brand'].append({'sku': sku, 'name': fp.get('name',''), 'zoho_brand': zoho_brand})
        elif flutter_brand and zoho_brand and flutter_brand.strip().lower() != zoho_brand.strip().lower():
            results['brand_mismatch'].append({'sku': sku, 'name': fp.get('name',''), 'flutter_brand': flutter_brand, 'zoho_brand': zoho_brand})
            
        if not flutter_supplier and zoho_supplier:
            results['missing_supplier'].append({'sku': sku, 'name': fp.get('name',''), 'zoho_supplier': zoho_supplier})
    
    # New products
    flutter_skus = set(flutter_map.keys())
    for zh in zoho_products:
        sku = zh.get('sku')
        if sku and sku not in flutter_skus:
            results['new_products'].append({'sku': sku, 'name': zh.get('name',''), 'brand': zh.get('brand',''), 'supplier': zh.get('vendor_name','')})
    
    # Write full results to JSON
    with open('temp_full_analysis.json', 'w', encoding='utf-8') as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    
    # Print summary
    print("=" * 80)
    print("FULL ANALYSIS: BRAND + SUPPLIER GAPS")
    print("=" * 80)
    print(f"\nZoho products: {len(zoho_products)}")
    print(f"Flutter products: {len(flutter_products)}")
    print(f"Unique Zoho suppliers: {len(zoho_vendors)}")
    for v in sorted(zoho_vendors):
        count = sum(1 for zh in zoho_products if (zh.get('vendor_name','') or '') == v)
        print(f"  - {v}: {count} products")
    
    print(f"\n--- MISSING BRAND (Flutter has NO brand, Zoho HAS brand): {len(results['missing_brand'])}")
    for i in results['missing_brand'][:5]:
        print(f"   {i['sku']} ({i['name']}) -> Zoho brand: {i['zoho_brand']}")
    if len(results['missing_brand']) > 5:
        print(f"   ... and {len(results['missing_brand']) - 5} more")
    
    print(f"\n--- BRAND MISMATCH: {len(results['brand_mismatch'])}")
    for i in results['brand_mismatch'][:5]:
        print(f"   {i['sku']} ({i['name']}) Flutter: {i['flutter_brand']} -> Zoho: {i['zoho_brand']}")
    if len(results['brand_mismatch']) > 5:
        print(f"   ... and {len(results['brand_mismatch']) - 5} more")
    
    print(f"\n--- MISSING SUPPLIER (Flutter has NO supplier_name, Zoho HAS vendor): {len(results['missing_supplier'])}")
    # Group by supplier
    by_supplier = {}
    for i in results['missing_supplier']:
        s = i['zoho_supplier']
        by_supplier.setdefault(s, []).append(i)
    for supplier, items in sorted(by_supplier.items(), key=lambda x: -len(x[1])):
        print(f"   {supplier}: {len(items)} products missing")
        for item in items[:3]:
            print(f"      - {item['sku']} ({item['name']})")
        if len(items) > 3:
            print(f"      ... and {len(items) - 3} more")
    
    print(f"\n--- NEW PRODUCTS (in Zoho, not in Flutter): {len(results['new_products'])}")
    for i in results['new_products'][:5]:
        print(f"   {i['sku']} ({i['name']}) [Brand: {i['brand']}, Supplier: {i['supplier']}]")
    if len(results['new_products']) > 5:
        print(f"   ... and {len(results['new_products']) - 5} more")

    print(f"\nTOTAL PRODUCTS THAT NEED UPDATING: {len(results['missing_brand']) + len(results['brand_mismatch']) + len(results['missing_supplier']) + len(results['new_products'])}")
    print("(Some products may appear in multiple categories)")


if __name__ == '__main__':
    main()
