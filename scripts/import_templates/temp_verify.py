"""Verify the sync results"""
import os
from supabase import create_client, Client

SUPABASE_URL = "https://xzdvtzdqjeyqxnkqprtf.supabase.co"
SUPABASE_KEY = os.environ.get("SUPABASE_SECRET_KEY", "")
TENANT_ID = "5443b130-cc28-45af-a420-cd500b288890"

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

all_products = []
offset = 0
while True:
    resp = supabase.table('products').select('id,sku,brand,supplier_name').eq('tenant_id', TENANT_ID).range(offset, offset + 999).execute()
    if not resp.data: break
    all_products.extend(resp.data)
    if len(resp.data) < 1000: break
    offset += 1000

total = len(all_products)
has_brand = sum(1 for p in all_products if p.get('brand'))
has_supplier = sum(1 for p in all_products if p.get('supplier_name'))
no_brand = sum(1 for p in all_products if not p.get('brand'))
no_supplier = sum(1 for p in all_products if not p.get('supplier_name'))

print("=" * 60)
print("POST-SYNC VERIFICATION")
print("=" * 60)
print(f"Total products: {total}")
print(f"With brand:     {has_brand} ({has_brand*100//total}%)")
print(f"Without brand:  {no_brand}")
print(f"With supplier:  {has_supplier} ({has_supplier*100//total}%)")
print(f"Without supplier: {no_supplier}")
