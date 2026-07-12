"""
Deep analysis: Check supplier mapping between Zoho and Flutter
"""
import os
from supabase import create_client, Client

SUPABASE_URL = "https://xzdvtzdqjeyqxnkqprtf.supabase.co"
SUPABASE_KEY = os.environ.get("SUPABASE_SECRET_KEY", "")
TENANT_ID = "5443b130-cc28-45af-a420-cd500b288890"

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# 1. Check if there's a suppliers table
print("=" * 80)
print("STEP 1: Get all suppliers from Supabase")
print("=" * 80)
try:
    resp = supabase.table('suppliers').select('*').eq('tenant_id', TENANT_ID).execute()
    print(f"Found {len(resp.data)} suppliers")
    for s in resp.data:
        print(f"  ID: {s.get('id')} | Name: {s.get('name', s.get('company_name', 'N/A'))}")
except Exception as e:
    print(f"suppliers table error: {e}")

# 2. Get the full products schema (all columns)
print("\n" + "=" * 80)
print("STEP 2: Get product schema (all columns)")
print("=" * 80)
resp = supabase.table('products').select('*').eq('tenant_id', TENANT_ID).limit(1).execute()
if resp.data:
    for key, val in resp.data[0].items():
        print(f"  {key}: {type(val).__name__} = {repr(val)[:80]}")

# 3. How many products have supplier_id set vs not 
print("\n" + "=" * 80)
print("STEP 3: Products with/without supplier_id")
print("=" * 80)
all_products = []
offset = 0
while True:
    resp = supabase.table('products').select('id,sku,name,supplier_id,brand').eq('tenant_id', TENANT_ID).range(offset, offset + 999).execute()
    if not resp.data:
        break
    all_products.extend(resp.data)
    if len(resp.data) < 1000:
        break
    offset += 1000

has_supplier = [p for p in all_products if p.get('supplier_id')]
no_supplier = [p for p in all_products if not p.get('supplier_id')]
has_brand = [p for p in all_products if p.get('brand')]
no_brand = [p for p in all_products if not p.get('brand')]

print(f"Total products: {len(all_products)}")
print(f"With supplier_id: {len(has_supplier)}")
print(f"Without supplier_id: {len(no_supplier)}")
print(f"With brand: {len(has_brand)}")
print(f"Without brand: {len(no_brand)}")
