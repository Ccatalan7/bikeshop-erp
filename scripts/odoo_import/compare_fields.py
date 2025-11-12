#!/usr/bin/env python3
"""
Compare product fields between Zoho and Odoo to create proper field mapping.
"""

import xmlrpc.client
import requests
import json

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
ODOO_API_KEY = "b9b8a246da7deeea272a4679e24baa68ebfb7e7e"

print("=" * 80)
print("Field Comparison: Zoho vs Odoo")
print("=" * 80)

# Get Zoho access token
print("\n🔑 Getting Zoho access token...")
url = f"https://accounts.zoho.{ZOHO_REGION}/oauth/v2/token"
params = {
    "refresh_token": ZOHO_REFRESH_TOKEN,
    "client_id": ZOHO_CLIENT_ID,
    "client_secret": ZOHO_CLIENT_SECRET,
    "grant_type": "refresh_token"
}
response = requests.post(url, data=params)
zoho_access_token = response.json()["access_token"]

# Fetch one sample product from Zoho
print("\n📦 Fetching sample product from Zoho...")
headers = {
    "Authorization": f"Zoho-oauthtoken {zoho_access_token}",
    "Content-Type": "application/json"
}
url = f"https://www.zohoapis.{ZOHO_REGION}/inventory/v1/items"
params = {"organization_id": ZOHO_ORG_ID, "per_page": 1}
response = requests.get(url, headers=headers, params=params)
zoho_products = response.json().get("items", [])

if zoho_products:
    zoho_product = zoho_products[0]
    print(f"✅ Sample product: {zoho_product.get('name')}")
    print(f"\n📋 Zoho Product Fields ({len(zoho_product)} fields):")
    for key in sorted(zoho_product.keys()):
        value = zoho_product[key]
        value_type = type(value).__name__
        # Truncate long values
        display_value = str(value)[:50] + "..." if len(str(value)) > 50 else str(value)
        print(f"   {key:30s} ({value_type:10s}): {display_value}")

# Connect to Odoo
print("\n" + "=" * 80)
print("\n🔑 Connecting to Odoo...")
common = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/common')
uid = common.authenticate(ODOO_DB, ODOO_USERNAME, ODOO_API_KEY, {})
models = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/object')

# Get Odoo product fields
print("\n📦 Fetching Odoo product.product fields...")
fields_info = models.execute_kw(
    ODOO_DB, uid, ODOO_API_KEY,
    'product.product', 'fields_get',
    [], {'attributes': ['string', 'type', 'help']}
)

print(f"\n📋 Odoo product.product Fields ({len(fields_info)} fields):")
print("\n   Key fields for product sync:")
important_fields = [
    'name', 'default_code', 'barcode', 'list_price', 'standard_price',
    'type', 'categ_id', 'qty_available', 'weight', 'volume',
    'description', 'description_sale', 'active', 'sale_ok', 'purchase_ok',
    'uom_id', 'uom_po_id', 'image_1920'
]

for field in important_fields:
    if field in fields_info:
        info = fields_info[field]
        field_type = info.get('type', 'unknown')
        field_label = info.get('string', field)
        print(f"   {field:30s} ({field_type:15s}): {field_label}")

# Create mapping suggestion
print("\n" + "=" * 80)
print("Suggested Field Mapping (Zoho → Odoo)")
print("=" * 80)

if zoho_products:
    mapping = {
        'name': 'name',  # Product name
        'sku': 'default_code',  # SKU/Internal Reference
        'rate': 'list_price',  # Sales price
        'purchase_rate': 'standard_price',  # Cost
        'stock_on_hand': 'qty_available',  # Stock (READ-ONLY in Odoo)
        'product_type': 'type',  # goods→consu, service→service
        'status': 'active',  # active→True, inactive→False
        'brand': None,  # Not in base Odoo (might need custom field)
        'reorder_level': None,  # Not in base Odoo
        'image_document_id': 'image_1920',  # Product image
        'description': 'description',  # Internal description
        'created_time': 'create_date',  # Created date (READ-ONLY)
        'last_modified_time': 'write_date',  # Updated date (READ-ONLY)
    }
    
    print("\nZoho Field              → Odoo Field              Notes")
    print("-" * 80)
    for zoho_field, odoo_field in mapping.items():
        if zoho_field in zoho_product:
            zoho_value = zoho_product[zoho_field]
            if odoo_field:
                notes = ""
                if zoho_field in ['stock_on_hand', 'created_time', 'last_modified_time']:
                    notes = "(READ-ONLY in Odoo)"
                elif zoho_field == 'product_type':
                    notes = "(goods→consu, service→service)"
                elif zoho_field == 'status':
                    notes = "(active→True)"
                print(f"{zoho_field:24s} → {odoo_field:24s} {notes}")
            else:
                print(f"{zoho_field:24s} → (NO MAPPING)            Not in base Odoo")

print("\n" + "=" * 80)
print("✅ Field analysis complete!")
print("=" * 80)
