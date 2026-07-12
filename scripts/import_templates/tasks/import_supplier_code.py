"""
Import Supplier Code (código proveedor) from Zoho to Supabase

Maps Zoho field 'cf_c_digo_proveedor' → Supabase column 'supplier_code'
Matches products by SKU
"""

import os
import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))

import requests
from connections.supabase_connection import SupabaseConnection

# Zoho credentials
CLIENT_ID = os.environ.get("ZOHO_CLIENT_ID", "")
CLIENT_SECRET = os.environ.get("ZOHO_CLIENT_SECRET", "")
REFRESH_TOKEN = os.environ.get("ZOHO_REFRESH_TOKEN", "")
ZOHO_ORG_ID = "788658742"


def get_zoho_access_token():
    """Get Zoho access token using refresh token"""
    print("🔑 Getting Zoho access token...")
    token_url = "https://accounts.zoho.com/oauth/v2/token"
    payload = {
        'grant_type': 'refresh_token',
        'client_id': CLIENT_ID,
        'client_secret': CLIENT_SECRET,
        'refresh_token': REFRESH_TOKEN
    }
    response = requests.post(token_url, params=payload)
    response.raise_for_status()
    print("   ✅ Token obtained")
    return response.json()['access_token']


def fetch_all_zoho_products(access_token):
    """Fetch all products from Zoho with supplier code field"""
    print("\n📥 Fetching products from Zoho...")
    
    headers = {
        'Authorization': f'Zoho-oauthtoken {access_token}',
        'Content-Type': 'application/json'
    }
    
    all_items = []
    page = 1
    
    while True:
        url = "https://www.zohoapis.com/inventory/v1/items"
        params = {
            'organization_id': ZOHO_ORG_ID,
            'page': page,
            'per_page': 200
        }
        
        response = requests.get(url, headers=headers, params=params)
        response.raise_for_status()
        data = response.json()
        
        items = data.get('items', [])
        if not items:
            break
        
        for item in items:
            supplier_code = item.get('cf_c_digo_proveedor') or item.get('cf_c_digo_proveedor_unformatted')
            all_items.append({
                'sku': item.get('sku', ''),
                'name': item.get('name', ''),
                'supplier_code': supplier_code
            })
        
        print(f"   Page {page}: {len(items)} items")
        page += 1
        
        if not data.get('page_context', {}).get('has_more_page'):
            break
    
    print(f"   ✅ Total: {len(all_items)} products")
    return all_items


def main():
    print("\n" + "=" * 80)
    print("📦 IMPORT SUPPLIER CODE (código proveedor) FROM ZOHO TO SUPABASE")
    print("=" * 80)
    
    # Get Zoho access token
    access_token = get_zoho_access_token()
    
    # Fetch Zoho products
    zoho_products = fetch_all_zoho_products(access_token)
    
    # Build lookup by SKU
    zoho_by_sku = {}
    for p in zoho_products:
        if p['sku'] and p['supplier_code']:
            zoho_by_sku[p['sku']] = p['supplier_code']
    
    print(f"\n📊 Zoho products with supplier code: {len(zoho_by_sku)}")
    
    # Connect to Supabase
    supabase = SupabaseConnection()
    
    # Fetch all Supabase products
    print("\n📥 Fetching products from Supabase...")
    all_supabase_products = []
    page_size = 1000
    offset = 0
    
    while True:
        response = supabase.client.table('products') \
            .select('id, sku, supplier_code, name') \
            .eq('tenant_id', supabase.tenant_id) \
            .range(offset, offset + page_size - 1) \
            .execute()
        
        if not response.data:
            break
        
        all_supabase_products.extend(response.data)
        print(f"   Page {offset // page_size + 1}: {len(response.data)} products")
        
        if len(response.data) < page_size:
            break
        
        offset += page_size
    
    print(f"   ✅ Total: {len(all_supabase_products)} products")
    
    # Find matches - FORCE UPDATE ALL products where Zoho has supplier code
    updates_needed = []
    
    for prod in all_supabase_products:
        sku = prod.get('sku', '')
        if sku and sku in zoho_by_sku:
            zoho_supplier_code = str(zoho_by_sku[sku])
            current_supplier_code = prod.get('supplier_code') or ''
            
            # Force update ALL - overwrite regardless of current value
            updates_needed.append({
                'id': prod['id'],
                'sku': sku,
                'name': prod.get('name', ''),
                'current': current_supplier_code,
                'new': zoho_supplier_code
            })
    
    print(f"\n📋 PREVIEW: {len(updates_needed)} products to update")
    
    if not updates_needed:
        print("\n✅ All products already have correct supplier codes!")
        return
    
    # Show first 10 as preview
    print("\nFirst 10 updates:")
    for u in updates_needed[:10]:
        print(f"  • {u['sku']}: '{u['current']}' → '{u['new']}'")
    
    if len(updates_needed) > 10:
        print(f"  ... and {len(updates_needed) - 10} more")
    
    # Ask for confirmation
    confirm = input(f"\n🔄 Proceed with {len(updates_needed)} updates? (yes/no): ").strip().lower()
    
    if confirm != 'yes':
        print("❌ Cancelled")
        return
    
    # Apply updates
    print("\n🔄 Applying updates...")
    success = 0
    failed = 0
    
    for u in updates_needed:
        try:
            supabase.client.table('products') \
                .update({'supplier_code': u['new']}) \
                .eq('id', u['id']) \
                .eq('tenant_id', supabase.tenant_id) \
                .execute()
            success += 1
            print(f"  ✅ {u['sku']}")
        except Exception as e:
            failed += 1
            print(f"  ❌ {u['sku']}: {e}")
    
    # Summary
    print("\n" + "=" * 80)
    print(f"✅ Updated: {success}")
    print(f"❌ Failed: {failed}")
    print("=" * 80)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n⚠️ Cancelled by user")
    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
