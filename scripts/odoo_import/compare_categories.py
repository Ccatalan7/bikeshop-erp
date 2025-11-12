#!/usr/bin/env python3
"""
Compare categories between Odoo and Supabase to understand the discrepancy.
Odoo: 144 categories
Supabase: 170 categories (claimed)
"""

import xmlrpc.client
from supabase import create_client, Client

# Odoo credentials
ODOO_URL = "https://vinabike.odoo.com"
ODOO_DB = "vinabike"
ODOO_USERNAME = "vinabikechile@gmail.com"
ODOO_API_KEY = "b9b8a246da7deeea272a4679e24baa68ebfb7e7e"

# Supabase credentials
SUPABASE_URL = "https://xzdvtzdqjeyqxnkqprtf.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh6ZHZ0emRxamV5cXhua3FwcnRmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2MDA2NDIzNSwiZXhwIjoyMDc1NjQwMjM1fQ.SJowIXSQY4n1TMQysRojCTZKZILJ5x8Mr2XAN7HBMBo"
TENANT_ID = "5443b130-cc28-45af-a420-cd500b288890"

print("=" * 80)
print("Comparing Categories: Odoo vs Supabase")
print("=" * 80)

# Connect to Odoo
print("\n📦 Fetching categories from Odoo...")
common = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/common')
uid = common.authenticate(ODOO_DB, ODOO_USERNAME, ODOO_API_KEY, {})
models = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/object')

# Fetch all Odoo categories with full path
odoo_categories = models.execute_kw(
    ODOO_DB, uid, ODOO_API_KEY,
    'product.category', 'search_read',
    [[]],
    {'fields': ['name', 'complete_name', 'parent_id']}
)

print(f"✅ Found {len(odoo_categories)} categories in Odoo")

# Connect to Supabase
print("\n📦 Fetching categories from Supabase...")
supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

supabase_result = supabase.table('product_categories').select('id, name, full_path, level').eq('tenant_id', TENANT_ID).execute()
supabase_categories = supabase_result.data

print(f"✅ Found {len(supabase_categories)} categories in Supabase")

# Analyze the difference
print("\n" + "=" * 80)
print("Analysis")
print("=" * 80)

# Extract full paths
odoo_paths = set()
for cat in odoo_categories:
    # Odoo uses 'complete_name' for full path (e.g., "Parent / Child")
    full_path = cat.get('complete_name', cat.get('name', ''))
    odoo_paths.add(full_path)

supabase_paths = set()
for cat in supabase_categories:
    supabase_paths.add(cat['full_path'])

# Categories in Supabase but not in Odoo
extra_in_supabase = supabase_paths - odoo_paths
print(f"\n📊 Categories in Supabase but NOT in Odoo: {len(extra_in_supabase)}")
if extra_in_supabase:
    print("\nSample of extra categories:")
    for i, path in enumerate(sorted(extra_in_supabase)[:10]):
        print(f"   {i+1}. {path}")
    if len(extra_in_supabase) > 10:
        print(f"   ... and {len(extra_in_supabase) - 10} more")

# Categories in Odoo but not in Supabase
missing_in_supabase = odoo_paths - supabase_paths
print(f"\n📊 Categories in Odoo but NOT in Supabase: {len(missing_in_supabase)}")
if missing_in_supabase:
    print("\nSample of missing categories:")
    for i, path in enumerate(sorted(missing_in_supabase)[:10]):
        print(f"   {i+1}. {path}")
    if len(missing_in_supabase) > 10:
        print(f"   ... and {len(missing_in_supabase) - 10} more")

# Categories in both
common_categories = odoo_paths & supabase_paths
print(f"\n📊 Categories in BOTH systems: {len(common_categories)}")

# Summary
print("\n" + "=" * 80)
print("Summary")
print("=" * 80)
print(f"Odoo total: {len(odoo_categories)}")
print(f"Supabase total: {len(supabase_categories)}")
print(f"Common: {len(common_categories)}")
print(f"Extra in Supabase: {len(extra_in_supabase)}")
print(f"Missing in Supabase: {len(missing_in_supabase)}")

# Show a few sample Odoo categories for reference
print("\n" + "=" * 80)
print("Sample Odoo Categories (first 10)")
print("=" * 80)
for i, cat in enumerate(odoo_categories[:10]):
    print(f"{i+1}. {cat.get('complete_name', cat.get('name'))}")
