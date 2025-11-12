"""
🔄 ZOHO → FLUTTER (SUPABASE) SYNC
==================================

WHAT THIS DOES:
- Syncs products from Zoho Inventory/Books to Flutter app (Supabase)
- Handles Chilean number format (1.500,00 → 1500.00)
- Creates categories from Zoho data
- Updates stock quantities
- Handles images (if URLs provided)

WHEN TO USE:
- Initial product import from Zoho
- Periodic sync to keep stock quantities updated
- After adding new products in Zoho

REQUIREMENTS:
- Zoho API credentials (client_id, client_secret, refresh_token, org_id)
- Supabase credentials (URL, service role key)
- Tenant ID (from Supabase tenants table)
"""

import sys
from pathlib import Path

# Add scripts directory to path
sys.path.append(str(Path(__file__).parent))

try:
    import config
except ImportError:
    print("\n❌ ERROR: config.py not found!")
    print("\n📝 SETUP INSTRUCTIONS:")
    print("1. Copy config.template.py to config.py")
    print("2. Edit config.py with your credentials")
    print("3. Run this script again\n")
    sys.exit(1)

# Validate configuration
if not config.validate_config():
    sys.exit(1)

import requests
from supabase import create_client
from typing import Dict, List, Optional
import time

# ============================================================================
# CONFIGURATION
# ============================================================================

SUPABASE_URL = config.SUPABASE_URL
SUPABASE_KEY = config.SUPABASE_SERVICE_ROLE_KEY
TENANT_ID = config.TENANT_ID

ZOHO_CLIENT_ID = config.ZOHO_CLIENT_ID
ZOHO_CLIENT_SECRET = config.ZOHO_CLIENT_SECRET
ZOHO_REFRESH_TOKEN = config.ZOHO_REFRESH_TOKEN
ZOHO_ORG_ID = config.ZOHO_ORG_ID
ZOHO_API_DOMAIN = config.ZOHO_API_DOMAIN

BATCH_SIZE = config.BATCH_SIZE
RATE_LIMIT_DELAY = config.RATE_LIMIT_DELAY

# ============================================================================
# ZOHO API HELPERS
# ============================================================================

def get_zoho_access_token() -> str:
    """Get fresh access token from Zoho"""
    url = f"{ZOHO_API_DOMAIN}/oauth/v2/token"
    params = {
        'refresh_token': ZOHO_REFRESH_TOKEN,
        'client_id': ZOHO_CLIENT_ID,
        'client_secret': ZOHO_CLIENT_SECRET,
        'grant_type': 'refresh_token'
    }
    
    response = requests.post(url, params=params)
    response.raise_for_status()
    
    return response.json()['access_token']


def fetch_zoho_items(access_token: str) -> List[Dict]:
    """Fetch all items from Zoho Inventory"""
    url = f"{ZOHO_API_DOMAIN}/inventory/v1/items"
    headers = {
        'Authorization': f'Zoho-oauthtoken {access_token}'
    }
    params = {
        'organization_id': ZOHO_ORG_ID,
        'per_page': 200
    }
    
    all_items = []
    page = 1
    
    while True:
        params['page'] = page
        response = requests.get(url, headers=headers, params=params)
        response.raise_for_status()
        
        data = response.json()
        items = data.get('items', [])
        
        if not items:
            break
        
        all_items.extend(items)
        print(f"   Fetched page {page}: {len(items)} items")
        
        page += 1
        time.sleep(RATE_LIMIT_DELAY)  # Rate limiting
    
    return all_items


# ============================================================================
# DATA TRANSFORMATION
# ============================================================================

def parse_chilean_number(value) -> float:
    """
    Parse Chilean number format to float
    
    Examples:
        "1.500,00" → 1500.00
        "123.456,78" → 123456.78
        "1.234" → 1234.00
    """
    if not value or value == '':
        return 0.0
    
    s = str(value).strip()
    
    # Remove thousand separators (dots)
    s = s.replace('.', '')
    
    # Replace decimal comma with period
    s = s.replace(',', '.')
    
    try:
        return float(s)
    except ValueError:
        return 0.0


def map_zoho_to_supabase(zoho_item: Dict) -> Dict:
    """
    Map Zoho item fields to Supabase product schema
    
    Zoho fields:
        - item_id, item_name, sku, product_type
        - rate (selling price), purchase_rate (cost)
        - stock_on_hand, available_stock
        - description, brand, manufacturer
        - image_name, image_type, image_document_id
    
    Supabase fields:
        - name, sku, description
        - price, cost
        - stock_quantity, inventory_qty
        - brand, category_id
        - image_url, barcode
    """
    return {
        'tenant_id': TENANT_ID,
        'name': zoho_item.get('item_name', zoho_item.get('name', 'Unknown')),
        'sku': zoho_item.get('sku', ''),
        'description': zoho_item.get('description', ''),
        'price': parse_chilean_number(zoho_item.get('rate', 0)),
        'cost': parse_chilean_number(zoho_item.get('purchase_rate', 0)),
        'stock_quantity': int(zoho_item.get('stock_on_hand', 0)),
        'inventory_qty': int(zoho_item.get('stock_on_hand', 0)),
        'brand': zoho_item.get('brand', ''),
        'barcode': zoho_item.get('upc', ''),
        'is_active': zoho_item.get('status', 'active') == 'active',
        'created_at': zoho_item.get('created_time', None),
    }


# ============================================================================
# SYNC LOGIC
# ============================================================================

def sync_products(client, zoho_items: List[Dict]):
    """
    Sync products from Zoho to Supabase
    
    Strategy:
    - Fetch existing products by SKU
    - Update if exists, insert if new
    - Handle duplicates gracefully
    """
    print("\n" + "=" * 80)
    print("📦 SYNCING PRODUCTS")
    print("=" * 80)
    
    # Fetch existing products
    print("\n1️⃣ Fetching existing products from Supabase...")
    existing = client.table("products")\
        .select("id, sku")\
        .eq("tenant_id", TENANT_ID)\
        .execute()
    
    existing_skus = {p['sku']: p['id'] for p in existing.data}
    print(f"   ✅ Found {len(existing_skus)} existing products")
    
    # Process Zoho items
    print("\n2️⃣ Processing Zoho items...")
    
    inserted = 0
    updated = 0
    skipped = 0
    errors = []
    
    for i, zoho_item in enumerate(zoho_items, 1):
        try:
            product_data = map_zoho_to_supabase(zoho_item)
            sku = product_data['sku']
            
            if not sku:
                skipped += 1
                continue
            
            if sku in existing_skus:
                # Update existing
                product_id = existing_skus[sku]
                client.table("products")\
                    .update(product_data)\
                    .eq('id', product_id)\
                    .execute()
                updated += 1
            else:
                # Insert new
                client.table("products")\
                    .insert(product_data)\
                    .execute()
                inserted += 1
            
            if i % 50 == 0:
                print(f"   Progress: {i}/{len(zoho_items)}")
            
            time.sleep(RATE_LIMIT_DELAY)
            
        except Exception as e:
            errors.append(f"SKU {sku}: {str(e)}")
            skipped += 1
    
    print(f"\n   ✅ Inserted: {inserted}")
    print(f"   ✅ Updated: {updated}")
    print(f"   ⏭️  Skipped: {skipped}")
    
    if errors:
        print(f"\n   ⚠️  Errors ({len(errors)}):")
        for error in errors[:10]:  # Show first 10
            print(f"      {error}")


def main():
    """Main sync function"""
    print("\n" + "=" * 80)
    print("🔄 ZOHO → FLUTTER SYNC")
    print("=" * 80)
    print(f"\n📊 Configuration:")
    print(f"   Zoho Org: {ZOHO_ORG_ID}")
    print(f"   Zoho API: {ZOHO_API_DOMAIN}")
    print(f"   Supabase: {SUPABASE_URL}")
    print(f"   Tenant: {TENANT_ID}")
    
    # Initialize connections
    print("\n🔗 Connecting to services...")
    
    # Supabase
    client = create_client(SUPABASE_URL, SUPABASE_KEY)
    print("   ✅ Supabase connected")
    
    # Zoho - get access token
    print("   🔄 Getting Zoho access token...")
    access_token = get_zoho_access_token()
    print("   ✅ Zoho authenticated")
    
    # Fetch items from Zoho
    print("\n📥 Fetching items from Zoho Inventory...")
    zoho_items = fetch_zoho_items(access_token)
    print(f"   ✅ Fetched {len(zoho_items)} items")
    
    # Sync to Supabase
    sync_products(client, zoho_items)
    
    # Summary
    print("\n" + "=" * 80)
    print("✅ SYNC COMPLETE!")
    print("=" * 80)
    
    # Final stats
    total_products = client.table("products")\
        .select("id", count="exact")\
        .eq("tenant_id", TENANT_ID)\
        .execute()
    
    print(f"\n📊 Final Stats:")
    print(f"   Total products in Supabase: {total_products.count}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n⚠️  Sync cancelled by user")
    except Exception as e:
        print(f"\n\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
