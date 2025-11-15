"""
🔄 ZOHO ↔ ODOO SYNC
===================

WHAT THIS DOES:
- Compares products between Zoho and Odoo
- Finds missing products in either system
- Syncs SKU, name, price, cost, stock
- Optionally creates missing products

WHEN TO USE:
- Reconciling two separate systems
- Migrating from one system to another
- Keeping both systems in sync

SYNC STRATEGIES:
1. One-way: Zoho → Odoo (Zoho is source of truth)
2. One-way: Odoo → Zoho (Odoo is source of truth)
3. Two-way: Sync both directions (complex, use carefully)

REQUIREMENTS:
- Both Zoho and Odoo credentials
- Decision on which system is source of truth
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
import xmlrpc.client
from typing import Dict, List, Tuple
import time

# ============================================================================
# CONFIGURATION
# ============================================================================

ZOHO_CLIENT_ID = config.ZOHO_CLIENT_ID
ZOHO_CLIENT_SECRET = config.ZOHO_CLIENT_SECRET
ZOHO_REFRESH_TOKEN = config.ZOHO_REFRESH_TOKEN
ZOHO_ORG_ID = config.ZOHO_ORG_ID
ZOHO_API_DOMAIN = config.ZOHO_API_DOMAIN
ZOHO_OAUTH_DOMAIN = getattr(config, 'ZOHO_OAUTH_DOMAIN', 'https://accounts.zoho.com')

ODOO_URL = config.ODOO_URL
ODOO_DB = config.ODOO_DB
ODOO_USERNAME = config.ODOO_USERNAME
ODOO_API_KEY = config.ODOO_API_KEY

RATE_LIMIT_DELAY = config.RATE_LIMIT_DELAY

# ============================================================================
# FETCH DATA FROM BOTH SYSTEMS
# ============================================================================

def fetch_zoho_products() -> List[Dict]:
    """Fetch all products from Zoho"""
    print("\n📥 Fetching products from Zoho...")
    
    # Get access token
    token_url = f"{ZOHO_OAUTH_DOMAIN}/oauth/v2/token"
    token_params = {
        'refresh_token': ZOHO_REFRESH_TOKEN,
        'client_id': ZOHO_CLIENT_ID,
        'client_secret': ZOHO_CLIENT_SECRET,
        'grant_type': 'refresh_token'
    }
    
    response = requests.post(token_url, params=token_params)
    response.raise_for_status()
    access_token = response.json()['access_token']
    
    # Fetch items
    url = f"{ZOHO_API_DOMAIN}/inventory/v1/items"
    headers = {'Authorization': f'Zoho-oauthtoken {access_token}'}
    params = {'organization_id': ZOHO_ORG_ID, 'per_page': 200}
    
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
        page += 1
        time.sleep(RATE_LIMIT_DELAY)
    
    print(f"   ✅ Found {len(all_items)} products")
    return all_items


def fetch_odoo_products() -> List[Dict]:
    """Fetch all products from Odoo"""
    print("\n📥 Fetching products from Odoo...")
    
    common = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/common')
    uid = common.authenticate(ODOO_DB, ODOO_USERNAME, ODOO_API_KEY, {})
    
    if not uid:
        raise Exception("Failed to authenticate with Odoo")
    
    models = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/object')
    
    products = models.execute_kw(
        ODOO_DB, uid, ODOO_API_KEY,
        'product.product', 'search_read',
        [[]],
        {'fields': ['default_code', 'name', 'list_price', 'standard_price', 'qty_available']}
    )
    
    print(f"   ✅ Found {len(products)} products")
    return products, uid, models


# ============================================================================
# COMPARISON LOGIC
# ============================================================================

def compare_products(zoho_products: List[Dict], odoo_products: List[Dict]) -> Tuple:
    """
    Compare products between Zoho and Odoo
    
    Returns:
        Tuple of (in_both, only_zoho, only_odoo, differences)
    """
    print("\n" + "=" * 80)
    print("🔍 COMPARING PRODUCTS")
    print("=" * 80)
    
    # Build SKU maps
    zoho_map = {p['sku']: p for p in zoho_products if p.get('sku')}
    odoo_map = {p['default_code']: p for p in odoo_products if p.get('default_code')}
    
    zoho_skus = set(zoho_map.keys())
    odoo_skus = set(odoo_map.keys())
    
    # Find matches and differences
    in_both = zoho_skus & odoo_skus
    only_zoho = zoho_skus - odoo_skus
    only_odoo = odoo_skus - zoho_skus
    
    print(f"\n📊 Comparison Results:")
    print(f"   ✅ In both systems: {len(in_both)}")
    print(f"   📗 Only in Zoho: {len(only_zoho)}")
    print(f"   📘 Only in Odoo: {len(only_odoo)}")
    
    # Check for differences in common products
    differences = []
    for sku in in_both:
        zoho_prod = zoho_map[sku]
        odoo_prod = odoo_map[sku]
        
        diffs = []
        
        # Compare name
        if zoho_prod.get('item_name', '').lower() != odoo_prod.get('name', '').lower():
            diffs.append('name')
        
        # Compare price (rough comparison, allow 1% difference)
        zoho_price = float(zoho_prod.get('rate', 0))
        odoo_price = float(odoo_prod.get('list_price', 0))
        if abs(zoho_price - odoo_price) / max(zoho_price, odoo_price, 1) > 0.01:
            diffs.append('price')
        
        # Compare stock
        zoho_stock = int(zoho_prod.get('stock_on_hand', 0))
        odoo_stock = int(odoo_prod.get('qty_available', 0))
        if abs(zoho_stock - odoo_stock) > 0:
            diffs.append('stock')
        
        if diffs:
            differences.append({
                'sku': sku,
                'fields': diffs,
                'zoho': zoho_prod,
                'odoo': odoo_prod
            })
    
    print(f"   ⚠️  Products with differences: {len(differences)}")
    
    return in_both, only_zoho, only_odoo, differences


# ============================================================================
# SYNC OPERATIONS
# ============================================================================

def sync_zoho_to_odoo(only_zoho: set, zoho_map: Dict, uid: int, models):
    """Create missing products in Odoo from Zoho"""
    print("\n" + "=" * 80)
    print("📤 SYNCING ZOHO → ODOO")
    print("=" * 80)
    
    if not only_zoho:
        print("   ✅ No products to sync")
        return
    
    print(f"\n   Creating {len(only_zoho)} products in Odoo...")
    
    created = 0
    errors = []
    
    for sku in only_zoho:
        zoho_prod = zoho_map[sku]
        
        try:
            product_data = {
                'name': zoho_prod.get('item_name', 'Unknown'),
                'default_code': sku,
                'list_price': float(zoho_prod.get('rate', 0)),
                'standard_price': float(zoho_prod.get('purchase_rate', 0)),
                'type': 'product',
            }
            
            models.execute_kw(
                ODOO_DB, uid, ODOO_API_KEY,
                'product.product', 'create',
                [product_data]
            )
            
            created += 1
            
        except Exception as e:
            errors.append(f"SKU {sku}: {str(e)}")
        
        time.sleep(RATE_LIMIT_DELAY)
    
    print(f"\n   ✅ Created: {created}")
    print(f"   ❌ Errors: {len(errors)}")
    
    if errors:
        print("\n   First 5 errors:")
        for error in errors[:5]:
            print(f"      {error}")


def sync_odoo_to_zoho(only_odoo: set, odoo_map: Dict, access_token: str):
    """Create missing products in Zoho from Odoo"""
    print("\n" + "=" * 80)
    print("📤 SYNCING ODOO → ZOHO")
    print("=" * 80)
    
    if not only_odoo:
        print("   ✅ No products to sync")
        return
    
    print(f"\n   Creating {len(only_odoo)} products in Zoho...")
    
    url = f"{ZOHO_API_DOMAIN}/inventory/v1/items"
    headers = {'Authorization': f'Zoho-oauthtoken {access_token}'}
    
    created = 0
    errors = []
    
    for sku in only_odoo:
        odoo_prod = odoo_map[sku]
        
        try:
            item_data = {
                'name': odoo_prod.get('name', 'Unknown'),
                'sku': sku,
                'rate': float(odoo_prod.get('list_price', 0)),
                'purchase_rate': float(odoo_prod.get('standard_price', 0)),
                'organization_id': ZOHO_ORG_ID,
            }
            
            response = requests.post(url, headers=headers, json=item_data)
            response.raise_for_status()
            
            created += 1
            
        except Exception as e:
            errors.append(f"SKU {sku}: {str(e)}")
        
        time.sleep(RATE_LIMIT_DELAY)
    
    print(f"\n   ✅ Created: {created}")
    print(f"   ❌ Errors: {len(errors)}")
    
    if errors:
        print("\n   First 5 errors:")
        for error in errors[:5]:
            print(f"      {error}")


# ============================================================================
# MAIN
# ============================================================================

def main():
    """Main sync function"""
    print("\n" + "=" * 80)
    print("🔄 ZOHO ↔ ODOO SYNC")
    print("=" * 80)
    
    # Fetch from both systems
    zoho_products = fetch_zoho_products()
    odoo_products, uid, models = fetch_odoo_products()
    
    # Build maps
    zoho_map = {p['sku']: p for p in zoho_products if p.get('sku')}
    odoo_map = {p['default_code']: p for p in odoo_products if p.get('default_code')}
    
    # Compare
    in_both, only_zoho, only_odoo, differences = compare_products(zoho_products, odoo_products)
    
    # Show sample differences
    if differences:
        print("\n📋 Sample Differences (first 10):")
        print("=" * 80)
        for i, diff in enumerate(differences[:10], 1):
            print(f"\n{i}. SKU: {diff['sku']}")
            print(f"   Fields: {', '.join(diff['fields'])}")
            
            if 'name' in diff['fields']:
                print(f"   Zoho name: {diff['zoho'].get('item_name', '')}")
                print(f"   Odoo name: {diff['odoo'].get('name', '')}")
            
            if 'price' in diff['fields']:
                print(f"   Zoho price: {diff['zoho'].get('rate', 0)}")
                print(f"   Odoo price: {diff['odoo'].get('list_price', 0)}")
            
            if 'stock' in diff['fields']:
                print(f"   Zoho stock: {diff['zoho'].get('stock_on_hand', 0)}")
                print(f"   Odoo stock: {diff['odoo'].get('qty_available', 0)}")
    
    # Ask user what to do
    print("\n" + "=" * 80)
    print("🤔 SYNC OPTIONS")
    print("=" * 80)
    print("\n1. Create missing products in Odoo from Zoho")
    print("2. Create missing products in Zoho from Odoo")
    print("3. Both (create in both systems)")
    print("4. Skip (just show comparison)")
    
    choice = input("\nYour choice (1-4): ").strip()
    
    if choice == '1':
        sync_zoho_to_odoo(only_zoho, zoho_map, uid, models)
    elif choice == '2':
        # Get fresh Zoho token
        token_url = f"{ZOHO_API_DOMAIN}/oauth/v2/token"
        token_params = {
            'refresh_token': ZOHO_REFRESH_TOKEN,
            'client_id': ZOHO_CLIENT_ID,
            'client_secret': ZOHO_CLIENT_SECRET,
            'grant_type': 'refresh_token'
        }
        response = requests.post(token_url, params=token_params)
        access_token = response.json()['access_token']
        
        sync_odoo_to_zoho(only_odoo, odoo_map, access_token)
    elif choice == '3':
        sync_zoho_to_odoo(only_zoho, zoho_map, uid, models)
        
        # Get fresh Zoho token
        token_url = f"{ZOHO_API_DOMAIN}/oauth/v2/token"
        token_params = {
            'refresh_token': ZOHO_REFRESH_TOKEN,
            'client_id': ZOHO_CLIENT_ID,
            'client_secret': ZOHO_CLIENT_SECRET,
            'grant_type': 'refresh_token'
        }
        response = requests.post(token_url, params=token_params)
        access_token = response.json()['access_token']
        
        sync_odoo_to_zoho(only_odoo, odoo_map, access_token)
    else:
        print("\n   ⏭️  Skipping sync")
    
    print("\n" + "=" * 80)
    print("✅ COMPLETE!")
    print("=" * 80)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n⚠️  Sync cancelled by user")
    except Exception as e:
        print(f"\n\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
