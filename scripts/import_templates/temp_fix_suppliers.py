"""
Fix: Create suppliers in the suppliers table and link products via supplier_id.
The product form dropdown reads from the suppliers table + supplier_id FK.
"""
import os
from supabase import create_client, Client

SUPABASE_URL = "https://xzdvtzdqjeyqxnkqprtf.supabase.co"
SUPABASE_KEY = os.environ.get("SUPABASE_SECRET_KEY", "")
TENANT_ID = "5443b130-cc28-45af-a420-cd500b288890"

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# 1. Get all unique supplier_name values from products
print("📦 Fetching products with supplier_name...")
all_products = []
offset = 0
while True:
    resp = supabase.table('products').select('id,sku,supplier_name,supplier_id').eq('tenant_id', TENANT_ID).range(offset, offset + 999).execute()
    if not resp.data: break
    all_products.extend(resp.data)
    if len(resp.data) < 1000: break
    offset += 1000

print(f"   Total products: {len(all_products)}")

# Get unique vendor names
vendor_names = set()
for p in all_products:
    name = (p.get('supplier_name') or '').strip()
    if name:
        vendor_names.add(name)

print(f"   Unique vendors: {len(vendor_names)}")
for v in sorted(vendor_names):
    count = sum(1 for p in all_products if (p.get('supplier_name') or '').strip() == v)
    print(f"     {v}: {count} products")

# 2. Check what already exists in the suppliers table
print("\n🏭 Checking existing suppliers table...")
existing = supabase.table('suppliers').select('id,name').eq('tenant_id', TENANT_ID).execute()
existing_map = {s['name']: s['id'] for s in (existing.data or [])}
print(f"   Existing suppliers: {len(existing_map)}")

# 3. Create missing suppliers
new_suppliers = vendor_names - set(existing_map.keys())
print(f"\n🆕 Creating {len(new_suppliers)} new suppliers...")

for name in sorted(new_suppliers):
    try:
        result = supabase.table('suppliers').insert({
            'tenant_id': TENANT_ID,
            'name': name,
            'type': 'local',
            'payment_terms': 'net30',
            'is_active': True,
        }).execute()
        supplier_id = result.data[0]['id']
        existing_map[name] = supplier_id
        print(f"   ✅ Created: {name} (id: {supplier_id})")
    except Exception as e:
        print(f"   ❌ Failed: {name}: {e}")

# 4. Link products to suppliers via supplier_id
print(f"\n🔗 Linking products to suppliers...")
updated = 0
skipped = 0
failed = 0

for p in all_products:
    supplier_name = (p.get('supplier_name') or '').strip()
    if not supplier_name:
        skipped += 1
        continue
    
    # Skip if already linked
    if p.get('supplier_id'):
        skipped += 1
        continue
    
    supplier_id = existing_map.get(supplier_name)
    if not supplier_id:
        skipped += 1
        continue
    
    try:
        supabase.table('products').update({
            'supplier_id': supplier_id
        }).eq('id', p['id']).execute()
        updated += 1
    except Exception as e:
        failed += 1
        print(f"   ❌ Failed {p['sku']}: {e}")
    
    if updated % 100 == 0 and updated > 0:
        print(f"   Progress: {updated} linked...")

print(f"\n{'='*60}")
print(f"✅ Suppliers created: {len(new_suppliers)}")
print(f"✅ Products linked: {updated}")
print(f"⏭️ Skipped: {skipped}")
if failed:
    print(f"❌ Failed: {failed}")
print(f"{'='*60}")
