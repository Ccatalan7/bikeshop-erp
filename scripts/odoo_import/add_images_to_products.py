#!/usr/bin/env python3
"""
Add images to the 24 products we just created (IDs: 14003-14026)
"""

import os
import xmlrpc.client
import requests
import base64
from typing import Optional

# Zoho credentials
ZOHO_ORG_ID = "788658742"
ZOHO_REFRESH_TOKEN = os.environ.get("ZOHO_REFRESH_TOKEN", "")
ZOHO_CLIENT_ID = os.environ.get("ZOHO_CLIENT_ID", "")
ZOHO_CLIENT_SECRET = os.environ.get("ZOHO_CLIENT_SECRET", "")
ZOHO_REGION = "com"

# Odoo credentials
ODOO_URL = "https://vinabike.odoo.com"
ODOO_DB = "vinabike"
ODOO_USERNAME = "vinabikechile@gmail.com"
ODOO_API_KEY = os.environ.get("ODOO_API_KEY", "")

zoho_access_token = None


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
    zoho_access_token = response.json()["access_token"]
    print(f"✅ Got access token")
    return zoho_access_token


def download_zoho_image(image_document_id: str) -> Optional[bytes]:
    """Download product image from Zoho using correct endpoint."""
    if not image_document_id:
        return None
    
    try:
        # CORRECT endpoint: /documents/ (not /items/.../image)
        url = f"https://www.zohoapis.{ZOHO_REGION}/inventory/v1/documents/{image_document_id}"
        headers = {
            "Authorization": f"Zoho-oauthtoken {zoho_access_token}",
        }
        params = {"organization_id": ZOHO_ORG_ID}
        
        response = requests.get(url, headers=headers, params=params, timeout=30, allow_redirects=True)
        
        if response.status_code == 200:
            return response.content
        else:
            return None
    except Exception as e:
        print(f"      Error: {e}")
        return None


def main():
    print("=" * 80)
    print("Add Images to 24 Created Products")
    print("=" * 80)
    
    # Get Zoho token
    get_zoho_access_token()
    
    # Connect to Odoo
    print("\n🔑 Connecting to Odoo...")
    common = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/common')
    uid = common.authenticate(ODOO_DB, ODOO_USERNAME, ODOO_API_KEY, {})
    models = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/object')
    print(f"✅ Connected (User ID: {uid})")
    
    # Read the CSV to get Zoho data
    import csv
    products_to_update = []
    
    with open('missing_products_zoho.csv', 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            products_to_update.append(row)
    
    # Fetch Zoho products to get image_document_id
    print(f"\n📦 Fetching Zoho products...")
    headers = {"Authorization": f"Zoho-oauthtoken {zoho_access_token}"}
    
    all_zoho_products = []
    page = 1
    while True:
        url = f"https://www.zohoapis.{ZOHO_REGION}/inventory/v1/items"
        params = {"organization_id": ZOHO_ORG_ID, "page": page, "per_page": 200}
        response = requests.get(url, headers=headers, params=params)
        data = response.json()
        items = data.get("items", [])
        if not items:
            break
        all_zoho_products.extend(items)
        page += 1
    
    zoho_by_sku = {p.get('sku'): p for p in all_zoho_products if p.get('sku')}
    
    # Get the 24 products from Odoo
    print(f"\n📦 Fetching created products from Odoo (IDs 14003-14026)...")
    odoo_products = models.execute_kw(
        ODOO_DB, uid, ODOO_API_KEY,
        'product.product', 'search_read',
        [[['id', '>=', 14003], ['id', '<=', 14026]]],
        {'fields': ['id', 'name', 'default_code']}
    )
    
    print(f"✅ Found {len(odoo_products)} products to update")
    
    # Update each product with image
    updated = 0
    skipped = 0
    
    print(f"\n📷 Downloading and uploading images...")
    print("=" * 80)
    
    for odoo_product in odoo_products:
        sku = odoo_product['default_code']
        name = odoo_product['name']
        odoo_id = odoo_product['id']
        
        print(f"\n[{odoo_id}] {name}")
        print(f"   SKU: {sku}")
        
        # Get Zoho product
        zoho_product = zoho_by_sku.get(sku)
        if not zoho_product:
            print(f"   ⚠️  Not found in Zoho")
            skipped += 1
            continue
        
        # Get image document ID
        image_document_id = zoho_product.get('image_document_id')
        if not image_document_id:
            print(f"   ⚠️  No image in Zoho")
            skipped += 1
            continue
        
        # Download image
        print(f"   📥 Downloading image (doc: {image_document_id})...")
        image_bytes = download_zoho_image(image_document_id)
        
        if not image_bytes:
            print(f"   ❌ Failed to download")
            skipped += 1
            continue
        
        print(f"   ✅ Downloaded ({len(image_bytes)} bytes)")
        
        # Upload to Odoo
        print(f"   📤 Uploading to Odoo...")
        try:
            image_base64 = base64.b64encode(image_bytes).decode('utf-8')
            
            models.execute_kw(
                ODOO_DB, uid, ODOO_API_KEY,
                'product.product', 'write',
                [[odoo_id], {'image_1920': image_base64}]
            )
            
            print(f"   ✅ Image uploaded!")
            updated += 1
        except Exception as e:
            print(f"   ❌ Upload failed: {e}")
            skipped += 1
    
    # Summary
    print("\n" + "=" * 80)
    print("✅ Image Update Complete!")
    print("=" * 80)
    print(f"Images uploaded: {updated}")
    print(f"Skipped: {skipped}")
    print(f"Total: {len(odoo_products)}")


if __name__ == "__main__":
    main()
