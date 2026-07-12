#!/usr/bin/env python3
"""
Test connection to Odoo and explore available data.
"""

import os
import xmlrpc.client

# Odoo credentials
ODOO_URL = "https://vinabike.odoo.com"
ODOO_DB = "vinabike"
ODOO_USERNAME = "vinabikechile@gmail.com"
ODOO_API_KEY = os.environ.get("ODOO_API_KEY", "")

print("=" * 80)
print("Testing Odoo Connection")
print("=" * 80)

try:
    # Step 1: Authenticate
    print(f"\n1️⃣ Connecting to: {ODOO_URL}")
    print(f"   Database: {ODOO_DB}")
    print(f"   Username: {ODOO_USERNAME}")
    
    common = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/common')
    
    print("\n2️⃣ Authenticating...")
    uid = common.authenticate(ODOO_DB, ODOO_USERNAME, ODOO_API_KEY, {})
    
    if not uid:
        print("❌ Authentication failed! Check your credentials.")
        exit(1)
    
    print(f"✅ Authenticated! User ID: {uid}")
    
    # Step 2: Get Odoo version
    version_info = common.version()
    print(f"\n📦 Odoo Version: {version_info.get('server_version', 'Unknown')}")
    
    # Step 3: Connect to object endpoint
    models = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/object')
    
    # Step 4: Test access - Get product count
    print("\n3️⃣ Checking access to models...")
    
    # Products (product.product)
    product_count = models.execute_kw(
        ODOO_DB, uid, ODOO_API_KEY,
        'product.product', 'search_count', [[]]
    )
    print(f"   📦 Products: {product_count}")
    
    # Categories (product.category)
    category_count = models.execute_kw(
        ODOO_DB, uid, ODOO_API_KEY,
        'product.category', 'search_count', [[]]
    )
    print(f"   📁 Categories: {category_count}")
    
    # Partners/Customers (res.partner)
    partner_count = models.execute_kw(
        ODOO_DB, uid, ODOO_API_KEY,
        'res.partner', 'search_count', [[['customer_rank', '>', 0]]]
    )
    print(f"   👥 Customers: {partner_count}")
    
    # Step 5: Fetch sample product
    print("\n4️⃣ Fetching sample product...")
    products = models.execute_kw(
        ODOO_DB, uid, ODOO_API_KEY,
        'product.product', 'search_read',
        [[]],
        {'fields': ['name', 'default_code', 'list_price', 'standard_price', 'qty_available', 'categ_id'], 'limit': 1}
    )
    
    if products:
        product = products[0]
        print(f"   Name: {product.get('name')}")
        print(f"   SKU: {product.get('default_code')}")
        print(f"   Price: {product.get('list_price')}")
        print(f"   Cost: {product.get('standard_price')}")
        print(f"   Stock: {product.get('qty_available')}")
        print(f"   Category: {product.get('categ_id')}")
    
    # Step 6: Check available fields for product.product
    print("\n5️⃣ Available fields in product.product model:")
    fields_info = models.execute_kw(
        ODOO_DB, uid, ODOO_API_KEY,
        'product.product', 'fields_get',
        [], {'attributes': ['string', 'type']}
    )
    
    # Show important fields
    important_fields = [
        'name', 'default_code', 'list_price', 'standard_price', 'qty_available',
        'categ_id', 'type', 'sale_ok', 'purchase_ok', 'active', 'barcode',
        'weight', 'volume', 'description', 'description_sale', 'image_1920'
    ]
    
    print("\n   Key fields available:")
    for field in important_fields:
        if field in fields_info:
            field_type = fields_info[field].get('type', 'unknown')
            field_label = fields_info[field].get('string', field)
            print(f"      - {field}: {field_label} ({field_type})")
    
    print("\n" + "=" * 80)
    print("✅ Connection successful! Ready to import data.")
    print("=" * 80)
    
except Exception as e:
    print(f"\n❌ Error: {e}")
    import traceback
    traceback.print_exc()
