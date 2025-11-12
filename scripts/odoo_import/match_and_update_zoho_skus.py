#!/usr/bin/env python3
"""
Match 183 Odoo-only products by name and update Zoho with Odoo SKUs
"""

import xmlrpc.client
import requests
from difflib import SequenceMatcher

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

def similarity_score(str1, str2):
    """Calculate similarity between two strings (0-1)"""
    return SequenceMatcher(None, str1.lower(), str2.lower()).ratio()

def normalize_name(name):
    """Normalize product name for better matching"""
    import re
    # Remove extra spaces, convert to lowercase
    name = re.sub(r'\s+', ' ', name.strip().lower())
    # Remove common words that might differ
    stopwords = ['el', 'la', 'los', 'las', 'de', 'del', 'y', '&']
    words = [w for w in name.split() if w not in stopwords]
    return ' '.join(words)

print("=" * 100)
print("MATCHING ODOO PRODUCTS TO ZOHO BY NAME")
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
headers = {"Authorization": f"Zoho-oauthtoken {zoho_token}"}
print("✅ Zoho authenticated")

# Connect to Odoo
print("\n🔑 Connecting to Odoo...")
common = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/common')
uid = common.authenticate(ODOO_DB, ODOO_USERNAME, ODOO_API_KEY, {})
models = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/object')
print(f"✅ Odoo connected (User ID: {uid})")

# Fetch Zoho products
print("\n📦 Fetching Zoho products...")
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
    {'fields': ['id', 'name', 'default_code', 'list_price', 'type', 'active']}
)
print(f"✅ Fetched {len(odoo_products)} products from Odoo")

# Find Odoo products without SKU match in Zoho
zoho_skus = {p.get('sku'): p for p in zoho_products if p.get('sku')}
zoho_without_sku = [p for p in zoho_products if not p.get('sku')]
odoo_unmatched = [p for p in odoo_products if p.get('default_code') and p['default_code'] not in zoho_skus]

print(f"\n🔍 Found {len(odoo_unmatched)} Odoo products without SKU match in Zoho")
print(f"🔍 Found {len(zoho_without_sku)} Zoho products without SKU")

# Try to match by name
print("\n" + "=" * 100)
print("MATCHING BY NAME")
print("=" * 100)

matches = []
unmatched_odoo = []

for odoo_prod in odoo_unmatched:
    odoo_name = odoo_prod.get('name', '')
    odoo_sku = odoo_prod.get('default_code', '')
    
    # Try to find best match in Zoho products without SKU
    best_match = None
    best_score = 0
    
    for zoho_prod in zoho_without_sku:
        zoho_name = zoho_prod.get('name', '')
        
        # Calculate similarity
        score = similarity_score(odoo_name, zoho_name)
        
        if score > best_score:
            best_score = score
            best_match = zoho_prod
    
    # Consider it a match if similarity > 0.8 (80%)
    if best_score >= 0.8:
        matches.append({
            'odoo_id': odoo_prod['id'],
            'odoo_name': odoo_name,
            'odoo_sku': odoo_sku,
            'zoho_id': best_match['item_id'],
            'zoho_name': best_match.get('name', ''),
            'similarity': best_score
        })
    else:
        unmatched_odoo.append({
            'odoo_id': odoo_prod['id'],
            'odoo_name': odoo_name,
            'odoo_sku': odoo_sku,
            'best_match_name': best_match.get('name', '') if best_match else '',
            'best_score': best_score
        })

print(f"\n✅ Found {len(matches)} strong matches (similarity >= 80%)")
print(f"⚠️  Found {len(unmatched_odoo)} products that couldn't be matched")

# Show matches
if matches:
    print("\n" + "=" * 100)
    print("MATCHED PRODUCTS (will update Zoho with Odoo SKU)")
    print("=" * 100)
    print(f"\n{'#':<5} {'Odoo SKU':<20} {'Similarity':<12} {'Product Name':<60}")
    print("-" * 100)
    
    for i, match in enumerate(matches[:20], 1):
        print(f"{i:<5} {match['odoo_sku']:<20} {match['similarity']*100:>6.1f}%     {match['odoo_name'][:60]}")
    
    if len(matches) > 20:
        print(f"... and {len(matches) - 20} more matches")

# Show unmatched
if unmatched_odoo:
    print("\n" + "=" * 100)
    print("UNMATCHED PRODUCTS (low similarity)")
    print("=" * 100)
    print(f"\n{'#':<5} {'Odoo SKU':<20} {'Best %':<12} {'Odoo Name':<60}")
    print("-" * 100)
    
    for i, item in enumerate(unmatched_odoo[:20], 1):
        print(f"{i:<5} {item['odoo_sku']:<20} {item['best_score']*100:>6.1f}%     {item['odoo_name'][:60]}")
    
    if len(unmatched_odoo) > 20:
        print(f"... and {len(unmatched_odoo) - 20} more unmatched")

# Ask for confirmation
print("\n" + "=" * 100)
print("READY TO UPDATE ZOHO")
print("=" * 100)
print(f"\nThis will update {len(matches)} products in Zoho:")
print(f"  - Add SKU from Odoo (e.g., 'NNV154', 'NNV31', etc.)")
print(f"  - Products will then be matched in future syncs")

response = input("\n⚠️  Proceed with updating Zoho SKUs? (yes/no): ")

if response.lower() != 'yes':
    print("❌ Cancelled. No changes made.")
    exit(0)

# Update Zoho products with Odoo SKUs
print("\n" + "=" * 100)
print("UPDATING ZOHO")
print("=" * 100)

updated_count = 0
failed_count = 0

for i, match in enumerate(matches, 1):
    zoho_id = match['zoho_id']
    odoo_sku = match['odoo_sku']
    
    print(f"\n[{i}/{len(matches)}] Updating Zoho ID {zoho_id}")
    print(f"   Adding SKU: {odoo_sku}")
    
    try:
        # Update Zoho product with SKU
        url = f"https://www.zohoapis.{ZOHO_REGION}/inventory/v1/items/{zoho_id}"
        params = {"organization_id": ZOHO_ORG_ID}
        
        payload = {
            "sku": odoo_sku
        }
        
        response = requests.put(url, headers=headers, params=params, json=payload)
        
        if response.status_code == 200:
            print(f"   ✅ Updated!")
            updated_count += 1
        else:
            print(f"   ❌ Failed: {response.status_code} - {response.text[:100]}")
            failed_count += 1
    
    except Exception as e:
        print(f"   ❌ Error: {str(e)}")
        failed_count += 1

# Summary
print("\n" + "=" * 100)
print("UPDATE COMPLETE")
print("=" * 100)
print(f"\n✅ Successfully updated: {updated_count}")
print(f"❌ Failed: {failed_count}")
print(f"📊 Total attempted: {len(matches)}")
print(f"⚠️  Still unmatched: {len(unmatched_odoo)}")

# Export unmatched to CSV for manual review
if unmatched_odoo:
    import csv
    
    filename = "unmatched_products_by_name.csv"
    with open(filename, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=['odoo_sku', 'odoo_name', 'best_match_name', 'similarity_%'])
        writer.writeheader()
        
        for item in unmatched_odoo:
            writer.writerow({
                'odoo_sku': item['odoo_sku'],
                'odoo_name': item['odoo_name'],
                'best_match_name': item['best_match_name'],
                'similarity_%': f"{item['best_score']*100:.1f}"
            })
    
    print(f"\n📄 Exported unmatched products to: {filename}")

print("\n" + "=" * 100)
