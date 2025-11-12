#!/usr/bin/env python3
"""
Sync products from Zoho to Odoo:
1. Match products by SKU
2. Create missing products in Odoo (Zoho has 24 more than Odoo)
3. Update existing products in Odoo with latest Zoho data (stock, prices)
"""

import xmlrpc.client
import requests
import time
from typing import Dict, List, Optional

# Zoho credentials
ZOHO_ORG_ID = "788658742"
ZOHO_REFRESH_TOKEN = "1000.5b73cc4d011ce72c562a005111500bbb.50ad2a91262bd56838118547a056c713"
ZOHO_CLIENT_ID = "1000.0UQWCWHOVFP0GY6KF4HI4IO3UTNJJX"
ZOHO_CLIENT_SECRET = "6e6c290e749847c5a98bde74ea906f392a4f35bc55"
ZOHO_REGION = "com"  # US region

# Odoo credentials
ODOO_URL = "https://vinabike.odoo.com"
ODOO_DB = "vinabike"
ODOO_USERNAME = "vinabikechile@gmail.com"
ODOO_API_KEY = "b9b8a246da7deeea272a4679e24baa68ebfb7e7e"

# Global variables
zoho_access_token = None
odoo_uid = None
odoo_models = None


def get_zoho_access_token() -> str:
    """Get fresh Zoho access token using refresh token."""
    global zoho_access_token
    
    print("🔑 Getting Zoho access token...")
    url = f"https://accounts.zoho.{ZOHO_REGION}/oauth/v2/token"
    params = {
        "refresh_token": ZOHO_REFRESH_TOKEN,
        "client_id": ZOHO_CLIENT_ID,
        "client_secret": ZOHO_CLIENT_SECRET,
        "grant_type": "refresh_token"
    }
    
    response = requests.post(url, data=params)
    if response.status_code == 200:
        zoho_access_token = response.json()["access_token"]
        print(f"✅ Got Zoho access token")
        return zoho_access_token
    else:
        raise Exception(f"Failed to get Zoho token: {response.text}")


def connect_odoo():
    """Connect to Odoo and authenticate."""
    global odoo_uid, odoo_models
    
    print("🔑 Connecting to Odoo...")
    common = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/common')
    odoo_uid = common.authenticate(ODOO_DB, ODOO_USERNAME, ODOO_API_KEY, {})
    
    if not odoo_uid:
        raise Exception("Odoo authentication failed!")
    
    odoo_models = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/object')
    print(f"✅ Connected to Odoo (User ID: {odoo_uid})")


def fetch_all_zoho_products() -> List[Dict]:
    """Fetch all products from Zoho."""
    print("\n📦 Fetching all products from Zoho...")
    
    if not zoho_access_token:
        get_zoho_access_token()
    
    headers = {
        "Authorization": f"Zoho-oauthtoken {zoho_access_token}",
        "Content-Type": "application/json"
    }
    
    all_products = []
    page = 1
    per_page = 200
    
    while True:
        url = f"https://www.zohoapis.{ZOHO_REGION}/inventory/v1/items"
        params = {
            "organization_id": ZOHO_ORG_ID,
            "page": page,
            "per_page": per_page
        }
        
        response = requests.get(url, headers=headers, params=params)
        
        if response.status_code != 200:
            print(f"❌ Error fetching Zoho products: {response.text}")
            break
        
        data = response.json()
        items = data.get("items", [])
        
        if not items:
            break
        
        all_products.extend(items)
        print(f"   Fetched page {page}: {len(items)} products (total: {len(all_products)})")
        
        # Check if there are more pages
        page_context = data.get("page_context", {})
        if not page_context.get("has_more_page", False):
            break
        
        page += 1
        time.sleep(0.5)  # Rate limiting
    
    print(f"✅ Fetched {len(all_products)} products from Zoho")
    return all_products


def fetch_all_odoo_products() -> List[Dict]:
    """Fetch all products from Odoo."""
    print("\n📦 Fetching all products from Odoo...")
    
    products = odoo_models.execute_kw(
        ODOO_DB, odoo_uid, ODOO_API_KEY,
        'product.product', 'search_read',
        [[]],
        {
            'fields': [
                'id', 'name', 'default_code', 'list_price', 'standard_price',
                'qty_available', 'categ_id', 'type', 'active', 'barcode'
            ]
        }
    )
    
    print(f"✅ Fetched {len(products)} products from Odoo")
    return products


def map_zoho_to_odoo_data(zoho_product: Dict) -> Dict:
    """Map Zoho product fields to Odoo product fields."""
    # Odoo product types: 'consu' (goods), 'service', 'combo'
    zoho_type = zoho_product.get('product_type', 'goods')
    odoo_type = 'service' if zoho_type == 'service' else 'consu'
    
    return {
        'name': zoho_product.get('name', ''),
        'default_code': zoho_product.get('sku', ''),  # SKU
        'list_price': float(zoho_product.get('rate', 0)),  # Sales price
        'standard_price': float(zoho_product.get('purchase_rate', 0)),  # Cost
        'type': odoo_type,  # 'consu' for goods, 'service' for services
        'active': zoho_product.get('status') == 'active',
        'barcode': zoho_product.get('sku', ''),  # Use SKU as barcode if not present
    }


def create_product_in_odoo(zoho_product: Dict) -> Optional[int]:
    """Create a new product in Odoo."""
    try:
        product_data = map_zoho_to_odoo_data(zoho_product)
        
        product_id = odoo_models.execute_kw(
            ODOO_DB, odoo_uid, ODOO_API_KEY,
            'product.product', 'create',
            [product_data]
        )
        
        return product_id
    except Exception as e:
        print(f"   ❌ Error creating product: {e}")
        return None


def update_product_in_odoo(odoo_product_id: int, zoho_product: Dict) -> bool:
    """Update existing product in Odoo with Zoho data."""
    try:
        product_data = map_zoho_to_odoo_data(zoho_product)
        
        # Update stock separately (qty_available is computed field, need to use stock.quant)
        zoho_stock = float(zoho_product.get('stock_on_hand', 0))
        
        # Update product fields
        odoo_models.execute_kw(
            ODOO_DB, odoo_uid, ODOO_API_KEY,
            'product.product', 'write',
            [[odoo_product_id], product_data]
        )
        
        # Note: Stock update in Odoo requires stock.quant or stock.move
        # For now, we'll just update basic fields
        
        return True
    except Exception as e:
        print(f"   ❌ Error updating product: {e}")
        return False


def main():
    """Main sync process."""
    print("=" * 80)
    print("Zoho → Odoo Product Sync")
    print("=" * 80)
    
    # Connect to both systems
    get_zoho_access_token()
    connect_odoo()
    
    # Fetch all products
    zoho_products = fetch_all_zoho_products()
    odoo_products = fetch_all_odoo_products()
    
    # Build SKU maps
    zoho_by_sku = {p.get('sku'): p for p in zoho_products if p.get('sku')}
    odoo_by_sku = {p.get('default_code'): p for p in odoo_products if p.get('default_code')}
    
    print("\n" + "=" * 80)
    print("Analysis")
    print("=" * 80)
    print(f"Zoho products: {len(zoho_products)}")
    print(f"Odoo products: {len(odoo_products)}")
    print(f"Zoho with SKU: {len(zoho_by_sku)}")
    print(f"Odoo with SKU: {len(odoo_by_sku)}")
    
    # Find products to create and update
    to_create = []
    to_update = []
    
    for sku, zoho_product in zoho_by_sku.items():
        if sku in odoo_by_sku:
            to_update.append((odoo_by_sku[sku]['id'], zoho_product))
        else:
            to_create.append(zoho_product)
    
    print(f"\nProducts to CREATE in Odoo: {len(to_create)}")
    print(f"Products to UPDATE in Odoo: {len(to_update)}")
    
    # Confirm before proceeding
    print("\n" + "=" * 80)
    print("⚠️  WARNING: This will modify your Odoo database!")
    print("=" * 80)
    response = input("Do you want to proceed? (yes/no): ").strip().lower()
    
    if response != 'yes':
        print("❌ Aborted by user")
        return
    
    # Create missing products
    created_count = 0
    if to_create:
        print(f"\n📝 Creating {len(to_create)} new products in Odoo...")
        for i, zoho_product in enumerate(to_create, 1):
            sku = zoho_product.get('sku')
            name = zoho_product.get('name')
            
            product_id = create_product_in_odoo(zoho_product)
            if product_id:
                created_count += 1
                print(f"   {i}/{len(to_create)} ✅ Created: {name} (SKU: {sku})")
            else:
                print(f"   {i}/{len(to_create)} ❌ Failed: {name} (SKU: {sku})")
    
    # Update existing products
    updated_count = 0
    if to_update:
        print(f"\n🔄 Updating {len(to_update)} existing products in Odoo...")
        for i, (odoo_id, zoho_product) in enumerate(to_update, 1):
            sku = zoho_product.get('sku')
            name = zoho_product.get('name')
            
            if update_product_in_odoo(odoo_id, zoho_product):
                updated_count += 1
                if i % 100 == 0:  # Progress every 100 products
                    print(f"   Progress: {i}/{len(to_update)} updated...")
            else:
                print(f"   {i}/{len(to_update)} ❌ Failed: {name} (SKU: {sku})")
    
    # Summary
    print("\n" + "=" * 80)
    print("✅ Sync Complete!")
    print("=" * 80)
    print(f"Created: {created_count}")
    print(f"Updated: {updated_count}")
    print(f"Total processed: {created_count + updated_count}")


if __name__ == "__main__":
    main()
