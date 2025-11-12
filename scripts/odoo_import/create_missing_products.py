#!/usr/bin/env python3
"""
Create 24 missing products from Zoho to Odoo.
- Match products by SKU
- Create only products that don't exist in Odoo
- Map categories by name
- Download and upload product images
"""

import xmlrpc.client
import requests
import time
import base64
from typing import Dict, List, Optional

# Zoho credentials
ZOHO_ORG_ID = "788658742"
ZOHO_REFRESH_TOKEN = "1000.5b73cc4d011ce72c562a005111500bbb.50ad2a91262bd56838118547a056c713"
ZOHO_CLIENT_ID = "1000.0UQWCWHOVFP0GY6KF4HI4IO3UTNJJX"
ZOHO_CLIENT_SECRET = "6e6c290e749847c5a98bde74ea906f392a4f35bc55"
ZOHO_REGION = "com"

# Odoo credentials
ODOO_URL = "https://vinabike.odoo.com"
ODOO_DB = "vinabike"
ODOO_USERNAME = "vinabikechile@gmail.com"
ODOO_API_KEY = "821be81bf75abeaf8508279b62e87f0fbab57b55"

# Global variables
zoho_access_token = None
odoo_uid = None
odoo_models = None
odoo_categories_cache = {}  # category_name -> category_id


def get_zoho_access_token() -> str:
    """Get fresh Zoho access token."""
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
    """Connect to Odoo."""
    global odoo_uid, odoo_models
    
    print("🔑 Connecting to Odoo...")
    common = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/common')
    
    try:
        odoo_uid = common.authenticate(ODOO_DB, ODOO_USERNAME, ODOO_API_KEY, {})
    except Exception as e:
        print(f"❌ Error during authentication: {e}")
        raise
    
    if not odoo_uid:
        print(f"❌ Authentication failed!")
        print(f"   URL: {ODOO_URL}")
        print(f"   DB: {ODOO_DB}")
        print(f"   User: {ODOO_USERNAME}")
        print(f"   API Key: {ODOO_API_KEY[:20]}...")
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
        print(f"   Page {page}: {len(items)} products (total: {len(all_products)})")
        
        page_context = data.get("page_context", {})
        if not page_context.get("has_more_page", False):
            break
        
        page += 1
        time.sleep(0.5)
    
    print(f"✅ Fetched {len(all_products)} products from Zoho")
    return all_products


def fetch_all_odoo_products() -> List[Dict]:
    """Fetch all products from Odoo."""
    print("\n📦 Fetching all products from Odoo...")
    
    products = odoo_models.execute_kw(
        ODOO_DB, odoo_uid, ODOO_API_KEY,
        'product.product', 'search_read',
        [[]],
        {'fields': ['id', 'name', 'default_code']}
    )
    
    print(f"✅ Fetched {len(products)} products from Odoo")
    return products


def load_odoo_categories():
    """Load all Odoo categories into cache."""
    global odoo_categories_cache
    
    print("\n📁 Loading Odoo categories...")
    
    categories = odoo_models.execute_kw(
        ODOO_DB, odoo_uid, ODOO_API_KEY,
        'product.category', 'search_read',
        [[]],
        {'fields': ['id', 'name', 'complete_name']}
    )
    
    # Cache by complete_name (full path)
    for cat in categories:
        complete_name = cat.get('complete_name', cat.get('name', ''))
        odoo_categories_cache[complete_name] = cat['id']
    
    print(f"✅ Loaded {len(odoo_categories_cache)} categories")


def find_category_id(category_name: str) -> Optional[int]:
    """Find Odoo category ID by name (exact match or fuzzy)."""
    if not category_name:
        return None
    
    # Exact match
    if category_name in odoo_categories_cache:
        return odoo_categories_cache[category_name]
    
    # Try to find partial match (last segment)
    category_name_lower = category_name.lower()
    for odoo_cat_name, cat_id in odoo_categories_cache.items():
        if category_name_lower in odoo_cat_name.lower():
            return cat_id
    
    return None


def download_zoho_image(image_document_id: str) -> Optional[bytes]:
    """Download product image from Zoho."""
    if not image_document_id:
        return None
    
    try:
        # Correct Zoho documents endpoint
        url = f"https://www.zohoapis.{ZOHO_REGION}/inventory/v1/documents/{image_document_id}"
        headers = {
            "Authorization": f"Zoho-oauthtoken {zoho_access_token}",
        }
        params = {"organization_id": ZOHO_ORG_ID}
        
        response = requests.get(url, headers=headers, params=params, timeout=30, allow_redirects=True)
        
        if response.status_code == 200:
            return response.content
        else:
            print(f"   ⚠️  Failed to download image: {response.status_code}")
            return None
    except Exception as e:
        print(f"   ⚠️  Error downloading image: {e}")
        return None


def create_product_in_odoo(zoho_product: Dict) -> Optional[int]:
    """Create a new product in Odoo with image."""
    try:
        name = zoho_product.get('name', '')
        sku = zoho_product.get('sku', '')
        
        # Map product type
        zoho_type = zoho_product.get('product_type', 'goods')
        odoo_type = 'service' if zoho_type == 'service' else 'consu'
        
        # Map category
        category_name = zoho_product.get('category_name', '')
        category_id = find_category_id(category_name)
        
        # Basic product data
        product_data = {
            'name': name,
            'default_code': sku,
            'list_price': float(zoho_product.get('rate', 0)),
            'standard_price': float(zoho_product.get('purchase_rate', 0)),
            'type': odoo_type,
            'active': zoho_product.get('status') == 'active',
        }
        
        # Add category if found
        if category_id:
            product_data['categ_id'] = category_id
        
        # Download and add image
        image_document_id = zoho_product.get('image_document_id')
        if image_document_id:
            print(f"   📷 Downloading image...")
            image_bytes = download_zoho_image(image_document_id)
            if image_bytes:
                # Encode to base64 for Odoo
                image_base64 = base64.b64encode(image_bytes).decode('utf-8')
                product_data['image_1920'] = image_base64
                print(f"   ✅ Image downloaded ({len(image_bytes)} bytes)")
        
        # Create product
        product_id = odoo_models.execute_kw(
            ODOO_DB, odoo_uid, ODOO_API_KEY,
            'product.product', 'create',
            [product_data]
        )
        
        return product_id
    except Exception as e:
        print(f"   ❌ Error creating product: {e}")
        return None


def main():
    """Main process."""
    print("=" * 80)
    print("Create Missing Products: Zoho → Odoo")
    print("=" * 80)
    
    # Connect to both systems
    get_zoho_access_token()
    connect_odoo()
    load_odoo_categories()
    
    # Fetch all products
    zoho_products = fetch_all_zoho_products()
    odoo_products = fetch_all_odoo_products()
    
    # Build SKU sets
    zoho_skus = {p.get('sku'): p for p in zoho_products if p.get('sku')}
    odoo_skus = {p.get('default_code') for p in odoo_products if p.get('default_code')}
    
    print("\n" + "=" * 80)
    print("Analysis")
    print("=" * 80)
    print(f"Zoho products with SKU: {len(zoho_skus)}")
    print(f"Odoo products with SKU: {len(odoo_skus)}")
    
    # Find products to create
    to_create = []
    for sku, zoho_product in zoho_skus.items():
        if sku not in odoo_skus:
            to_create.append(zoho_product)
    
    print(f"\n📝 Products to CREATE in Odoo: {len(to_create)}")
    
    if not to_create:
        print("\n✅ All Zoho products already exist in Odoo!")
        return
    
    # Export list to CSV
    import csv
    csv_filename = 'missing_products_zoho.csv'
    with open(csv_filename, 'w', newline='', encoding='utf-8') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(['SKU', 'Name', 'Stock (Zoho)', 'Price', 'Cost', 'Category', 'Type'])
        
        for product in to_create:
            writer.writerow([
                product.get('sku', ''),
                product.get('name', ''),
                product.get('stock_on_hand', 0),
                product.get('rate', 0),
                product.get('purchase_rate', 0),
                product.get('category_name', ''),
                product.get('product_type', 'goods')
            ])
    
    print(f"\n✅ Exported product list to: {csv_filename}")
    
    # Show sample of products to create
    print("\nSample products to create:")
    for i, product in enumerate(to_create[:5], 1):
        stock = product.get('stock_on_hand', 0)
        print(f"   {i}. {product.get('name')} (SKU: {product.get('sku')}, Stock: {stock})")
    if len(to_create) > 5:
        print(f"   ... and {len(to_create) - 5} more")
    
    # Confirm
    print("\n" + "=" * 80)
    response = input(f"Create {len(to_create)} products in Odoo? (yes/no): ").strip().lower()
    
    if response != 'yes':
        print("❌ Aborted by user")
        return
    
    # Create products
    created_count = 0
    failed_count = 0
    
    print(f"\n📝 Creating {len(to_create)} products...")
    print("=" * 80)
    
    for i, zoho_product in enumerate(to_create, 1):
        sku = zoho_product.get('sku')
        name = zoho_product.get('name')
        category_name = zoho_product.get('category_name', 'N/A')
        
        print(f"\n[{i}/{len(to_create)}] Creating: {name}")
        print(f"   SKU: {sku}")
        print(f"   Category: {category_name}")
        
        product_id = create_product_in_odoo(zoho_product)
        
        if product_id:
            created_count += 1
            print(f"   ✅ Created (ID: {product_id})")
        else:
            failed_count += 1
            print(f"   ❌ Failed to create")
    
    # Summary
    print("\n" + "=" * 80)
    print("✅ Import Complete!")
    print("=" * 80)
    print(f"Successfully created: {created_count}")
    print(f"Failed: {failed_count}")
    print(f"Total: {len(to_create)}")


if __name__ == "__main__":
    main()
