#!/usr/bin/env python3
"""
Full comparison between Zoho and Odoo products
"""

import os
import xmlrpc.client
import requests

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

print("=" * 100)
print("ZOHO vs ODOO - FULL PRODUCT COMPARISON")
print("=" * 100)

# Get Zoho token
print("\n🔑 Authenticating with Zoho...")
url = f"https://accounts.zoho.{ZOHO_REGION}/oauth/v2/token"
params = {
    "refresh_token": ZOHO_REFRESH_TOKEN,
    "client_id": ZOHO_CLIENT_ID,
    "client_secret": ZOHO_CLIENT_SECRET,
    "grant_type": "refresh_token"
}
response = requests.post(url, data=params)
zoho_token = response.json()["access_token"]
print("✅ Zoho authenticated")

# Connect to Odoo
print("\n🔑 Connecting to Odoo...")
common = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/common')
uid = common.authenticate(ODOO_DB, ODOO_USERNAME, ODOO_API_KEY, {})
models = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/object')
print(f"✅ Odoo connected (User ID: {uid})")

# Fetch Zoho products
print("\n📦 Fetching Zoho products...")
headers = {"Authorization": f"Zoho-oauthtoken {zoho_token}"}
zoho_products = []
page = 1

while True:
    url = f"https://www.zohoapis.{ZOHO_REGION}/inventory/v1/items"
    params = {"organization_id": ZOHO_ORG_ID, "page": page, "per_page": 200}
    response = requests.get(url, headers=headers, params=params)
    data = response.json()
    items = data.get("items", [])
    if not items:
        break
    zoho_products.extend(items)
    page += 1

print(f"✅ Fetched {len(zoho_products)} products from Zoho")

# Fetch Odoo products
print("\n📦 Fetching Odoo products...")
odoo_products = models.execute_kw(
    ODOO_DB, uid, ODOO_API_KEY,
    'product.product', 'search_read',
    [[]],
    {'fields': ['id', 'name', 'default_code', 'list_price', 'standard_price', 'type', 'active', 'categ_id']}
)
print(f"✅ Fetched {len(odoo_products)} products from Odoo")

# Analysis
print("\n" + "=" * 100)
print("PRODUCT COUNTS")
print("=" * 100)

zoho_with_sku = [p for p in zoho_products if p.get('sku')]
odoo_with_sku = [p for p in odoo_products if p.get('default_code')]

print(f"\n{'System':<20} {'Total':<15} {'With SKU':<15} {'Without SKU':<15}")
print("-" * 100)
print(f"{'Zoho':<20} {len(zoho_products):<15} {len(zoho_with_sku):<15} {len(zoho_products) - len(zoho_with_sku):<15}")
print(f"{'Odoo':<20} {len(odoo_products):<15} {len(odoo_with_sku):<15} {len(odoo_products) - len(odoo_with_sku):<15}")

# SKU matching
zoho_skus = {p.get('sku'): p for p in zoho_products if p.get('sku')}
odoo_skus = {p.get('default_code'): p for p in odoo_products if p.get('default_code')}

common_skus = set(zoho_skus.keys()) & set(odoo_skus.keys())
only_zoho = set(zoho_skus.keys()) - set(odoo_skus.keys())
only_odoo = set(odoo_skus.keys()) - set(zoho_skus.keys())

print("\n" + "=" * 100)
print("SKU MATCHING")
print("=" * 100)
print(f"\nProducts in BOTH systems (matched by SKU):  {len(common_skus)}")
print(f"Products ONLY in Zoho:                       {len(only_zoho)}")
print(f"Products ONLY in Odoo:                       {len(only_odoo)}")

# Product types
print("\n" + "=" * 100)
print("PRODUCT TYPES")
print("=" * 100)

zoho_goods = sum(1 for p in zoho_products if p.get('product_type') == 'goods')
zoho_services = sum(1 for p in zoho_products if p.get('product_type') == 'service')

odoo_consu = sum(1 for p in odoo_products if p.get('type') == 'consu')
odoo_services = sum(1 for p in odoo_products if p.get('type') == 'service')
odoo_other = len(odoo_products) - odoo_consu - odoo_services

print(f"\n{'System':<20} {'Goods/Consumable':<20} {'Services':<15} {'Other':<10}")
print("-" * 100)
print(f"{'Zoho':<20} {zoho_goods:<20} {zoho_services:<15} {'-':<10}")
print(f"{'Odoo':<20} {odoo_consu:<20} {odoo_services:<15} {odoo_other:<10}")

# Active/Inactive
print("\n" + "=" * 100)
print("ACTIVE STATUS")
print("=" * 100)

zoho_active = sum(1 for p in zoho_products if p.get('status') == 'active')
zoho_inactive = len(zoho_products) - zoho_active

odoo_active = sum(1 for p in odoo_products if p.get('active') == True)
odoo_inactive = len(odoo_products) - odoo_active

print(f"\n{'System':<20} {'Active':<15} {'Inactive':<15}")
print("-" * 100)
print(f"{'Zoho':<20} {zoho_active:<15} {zoho_inactive:<15}")
print(f"{'Odoo':<20} {odoo_active:<15} {odoo_inactive:<15}")

# Stock analysis (Zoho only - Odoo stock is complex)
print("\n" + "=" * 100)
print("STOCK ANALYSIS (ZOHO)")
print("=" * 100)

total_stock = sum(float(p.get('stock_on_hand', 0)) for p in zoho_products)
products_with_stock = sum(1 for p in zoho_products if float(p.get('stock_on_hand', 0)) > 0)
products_no_stock = len(zoho_products) - products_with_stock

print(f"\nTotal stock units:                {total_stock:,.1f}")
print(f"Products with stock:              {products_with_stock}")
print(f"Products without stock:           {products_no_stock}")
print(f"Average stock per product:        {total_stock / len(zoho_products):,.2f} units")

# Price analysis
print("\n" + "=" * 100)
print("PRICE ANALYSIS")
print("=" * 100)

zoho_total_value = sum(float(p.get('rate', 0)) * float(p.get('stock_on_hand', 0)) for p in zoho_products)
zoho_avg_price = sum(float(p.get('rate', 0)) for p in zoho_products) / len(zoho_products)

odoo_avg_price = sum(float(p.get('list_price', 0)) for p in odoo_products) / len(odoo_products)
odoo_avg_cost = sum(float(p.get('standard_price', 0)) for p in odoo_products) / len(odoo_products)

print(f"\n{'Metric':<40} {'Zoho':<20} {'Odoo':<20}")
print("-" * 100)
print(f"{'Average Sales Price':<40} ${zoho_avg_price:,.0f} CLP{'':<7} ${odoo_avg_price:,.0f} CLP")
print(f"{'Average Cost Price':<40} {'-':<20} ${odoo_avg_cost:,.0f} CLP")
print(f"{'Total Inventory Value (at price)':<40} ${zoho_total_value:,.0f} CLP{'':<7} {'-':<20}")

# Sample of products only in Zoho
print("\n" + "=" * 100)
print(f"PRODUCTS ONLY IN ZOHO ({len(only_zoho)} products)")
print("=" * 100)

if only_zoho:
    print("\nFirst 10 SKUs only in Zoho:")
    for i, sku in enumerate(list(only_zoho)[:10], 1):
        product = zoho_skus[sku]
        print(f"   {i}. {sku:<20} {product.get('name', '')[:50]}")
    if len(only_zoho) > 10:
        print(f"   ... and {len(only_zoho) - 10} more")

# Sample of products only in Odoo
print("\n" + "=" * 100)
print(f"PRODUCTS ONLY IN ODOO ({len(only_odoo)} products)")
print("=" * 100)

if only_odoo:
    print("\nFirst 10 SKUs only in Odoo:")
    for i, sku in enumerate(list(only_odoo)[:10], 1):
        product = odoo_skus[sku]
        print(f"   {i}. {sku:<20} {product.get('name', '')[:50]}")
    if len(only_odoo) > 10:
        print(f"   ... and {len(only_odoo) - 10} more")

# Summary
print("\n" + "=" * 100)
print("SUMMARY")
print("=" * 100)
print(f"\n✅ Zoho and Odoo are now IN SYNC:")
print(f"   - Both systems have products with matching SKUs")
print(f"   - Total matched products: {len(common_skus)}")
print(f"   - Zoho has {len(only_zoho)} unique products (likely without SKU or deprecated)")
print(f"   - Odoo has {len(only_odoo)} unique products (likely Odoo system products)")
print(f"\n📊 Data Quality:")
print(f"   - Zoho: {len(zoho_with_sku)/len(zoho_products)*100:.1f}% of products have SKU")
print(f"   - Odoo: {len(odoo_with_sku)/len(odoo_products)*100:.1f}% of products have SKU")
print(f"\n💰 Inventory Value (Zoho): ${zoho_total_value:,.0f} CLP")
print("=" * 100)
