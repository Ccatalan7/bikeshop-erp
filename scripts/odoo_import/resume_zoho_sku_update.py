#!/usr/bin/env python3
"""
Resume updating Zoho SKUs with rate limiting
"""

import os
import xmlrpc.client
import requests
import time
from difflib import SequenceMatcher

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

def similarity_score(str1, str2):
    """Calculate similarity between two strings (0-1)"""
    return SequenceMatcher(None, str1.lower(), str2.lower()).ratio()

print("=" * 100)
print("RESUME: UPDATING ZOHO SKUS (WITH RATE LIMITING)")
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

# Fetch Zoho products (to check which already have SKUs)
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
    time.sleep(0.5)  # Rate limiting

print(f"✅ Fetched {len(zoho_products)} products from Zoho")

# Fetch Odoo products
print("\n📦 Fetching Odoo products...")
odoo_products = models.execute_kw(
    ODOO_DB, uid, ODOO_API_KEY,
    'product.product', 'search_read',
    [[]],
    {'fields': ['id', 'name', 'default_code']}
)
print(f"✅ Fetched {len(odoo_products)} products from Odoo")

# Find what still needs updating
zoho_skus = {p.get('sku'): p for p in zoho_products if p.get('sku')}
zoho_without_sku = [p for p in zoho_products if not p.get('sku')]
odoo_unmatched = [p for p in odoo_products if p.get('default_code') and p['default_code'] not in zoho_skus]

print(f"\n🔍 Still need to update: {len(zoho_without_sku)} Zoho products without SKU")
print(f"🔍 Still available: {len(odoo_unmatched)} Odoo products to match")

# Try to match by name
print("\n" + "=" * 100)
print("MATCHING REMAINING PRODUCTS BY NAME")
print("=" * 100)

matches = []

for odoo_prod in odoo_unmatched:
    odoo_name = odoo_prod.get('name', '')
    odoo_sku = odoo_prod.get('default_code', '')
    
    best_match = None
    best_score = 0
    
    for zoho_prod in zoho_without_sku:
        zoho_name = zoho_prod.get('name', '')
        score = similarity_score(odoo_name, zoho_name)
        
        if score > best_score:
            best_score = score
            best_match = zoho_prod
    
    if best_score >= 0.8:
        matches.append({
            'odoo_id': odoo_prod['id'],
            'odoo_name': odoo_name,
            'odoo_sku': odoo_sku,
            'zoho_id': best_match['item_id'],
            'zoho_name': best_match.get('name', ''),
            'similarity': best_score
        })

print(f"\n✅ Found {len(matches)} products to update")

if not matches:
    print("\n🎉 All products already updated!")
    exit(0)

# Show what will be updated
print("\n" + "=" * 100)
print("WILL UPDATE:")
print("=" * 100)
print(f"\n{'#':<5} {'Odoo SKU':<20} {'Product Name':<60}")
print("-" * 100)

for i, match in enumerate(matches[:10], 1):
    print(f"{i:<5} {match['odoo_sku']:<20} {match['odoo_name'][:60]}")

if len(matches) > 10:
    print(f"... and {len(matches) - 10} more")

# Auto-proceed (no confirmation needed)
print(f"\n⚠️  Proceeding with {len(matches)} updates...")

# Update with rate limiting
print("\n" + "=" * 100)
print("UPDATING ZOHO (WITH 3-SECOND DELAY BETWEEN REQUESTS)")
print("=" * 100)
print("\n💡 Zoho API Limits:")
print("   - 150 requests per minute")
print("   - If rate limited (429), script will wait 60 seconds and retry")
print("=" * 100)

updated_count = 0
failed_count = 0
retry_count = 0
max_retries = 3

for i, match in enumerate(matches, 1):
    zoho_id = match['zoho_id']
    odoo_sku = match['odoo_sku']
    
    print(f"\n[{i}/{len(matches)}] Updating Zoho ID {zoho_id}")
    print(f"   Adding SKU: {odoo_sku}")
    
    # Retry logic for rate limiting
    success = False
    for attempt in range(max_retries):
        try:
            url = f"https://www.zohoapis.{ZOHO_REGION}/inventory/v1/items/{zoho_id}"
            params = {"organization_id": ZOHO_ORG_ID}
            
            payload = {"sku": odoo_sku}
            
            response = requests.put(url, headers=headers, params=params, json=payload)
            
            if response.status_code == 200:
                print(f"   ✅ Updated!")
                updated_count += 1
                success = True
                break
            elif response.status_code == 429:
                # Rate limited
                if attempt < max_retries - 1:
                    wait_time = 60
                    print(f"   ⏳ Rate limited (429). Waiting {wait_time} seconds before retry...")
                    time.sleep(wait_time)
                    retry_count += 1
                else:
                    print(f"   ❌ Rate limit exceeded after {max_retries} attempts")
                    failed_count += 1
            else:
                print(f"   ❌ Failed: {response.status_code} - {response.text[:100]}")
                failed_count += 1
                break
        
        except Exception as e:
            print(f"   ❌ Error: {str(e)}")
            failed_count += 1
            break
    
    if not success and response.status_code != 429:
        failed_count += 1
    
    # CRITICAL: Wait 3 seconds between requests to avoid rate limit
    if i < len(matches):
        time.sleep(3)

# Summary
print("\n" + "=" * 100)
print("UPDATE COMPLETE")
print("=" * 100)
print(f"\n✅ Successfully updated: {updated_count}")
print(f"❌ Failed: {failed_count}")
print(f"� Retries due to rate limit: {retry_count}")
print(f"�📊 Total attempted: {len(matches)}")

if failed_count > 0:
    print("\n💡 Some updates failed. Zoho API limits:")
    print("   - Daily limit: Unknown (possibly 100-150 updates per day)")
    print("   - Per-minute limit: 150 requests")
    print("   - Try again in 24 hours if daily limit reached")
else:
    print("\n🎉 All updates completed successfully!")

print("=" * 100)
