"""
FINAL Sync: CSV (Zoho Export) -> Supabase (Flutter)
- Uses the Zoho CSV export for supplier/vendor data (no API calls needed!)
- Also fetches brand data from the Zoho LIST API (which DOES return brand)  
- Maps by SKU
- Upserts brand + supplier_name
- NEVER touches stock_quantity or image_url
"""
import os
import csv
import time
import json
import requests
from typing import List, Dict
from supabase import create_client, Client

# ============================================================================
# CONFIGURATION
# ============================================================================
CSV_PATH = r"c:\dev\VINABIKE\bikeshop-erp\.github\Artículo - Item.csv"

ZOHO_CLIENT_ID = os.environ.get("ZOHO_CLIENT_ID", "")
ZOHO_CLIENT_SECRET = os.environ.get("ZOHO_CLIENT_SECRET", "")
ZOHO_REFRESH_TOKEN = os.environ.get("ZOHO_REFRESH_TOKEN", "")
ZOHO_ORG_ID = "788658742"
ZOHO_API_DOMAIN = "https://www.zohoapis.com"
ZOHO_OAUTH_DOMAIN = "https://accounts.zoho.com"

SUPABASE_URL = "https://xzdvtzdqjeyqxnkqprtf.supabase.co"
SUPABASE_KEY = os.environ.get("SUPABASE_SECRET_KEY", "")
TENANT_ID = "5443b130-cc28-45af-a420-cd500b288890"

# ============================================================================
# DATA LOADING
# ============================================================================
def load_csv_vendors() -> Dict[str, str]:
    """Load SKU -> Vendor mapping from the Zoho CSV export"""
    print("📄 Loading vendor data from CSV export...")
    sku_to_vendor = {}
    with open(CSV_PATH, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            sku = (row.get('SKU', '') or '').strip()
            vendor = (row.get('Vendor', '') or '').strip()
            if sku:
                sku_to_vendor[sku] = vendor
    print(f"   ✅ Loaded {len(sku_to_vendor)} SKUs from CSV")
    vendors_with_data = sum(1 for v in sku_to_vendor.values() if v)
    print(f"   📊 {vendors_with_data} items have a vendor assigned")
    return sku_to_vendor

def fetch_zoho_brands() -> Dict[str, str]:
    """Fetch SKU -> Brand mapping from Zoho LIST API (brand IS available there)"""
    print("\n🔑 Getting Zoho access token...")
    params = {'refresh_token': ZOHO_REFRESH_TOKEN, 'client_id': ZOHO_CLIENT_ID,
              'client_secret': ZOHO_CLIENT_SECRET, 'grant_type': 'refresh_token'}
    resp = requests.post(f"{ZOHO_OAUTH_DOMAIN}/oauth/v2/token", params=params)
    data = resp.json()
    if 'access_token' not in data:
        print(f"   ❌ Token error: {data}")
        return {}
    access_token = data['access_token']
    print("   ✅ Token obtained")
    
    print("\n📥 Fetching brand data from Zoho LIST API...")
    url = f"{ZOHO_API_DOMAIN}/inventory/v1/items"
    headers = {'Authorization': f'Zoho-oauthtoken {access_token}'}
    sku_to_brand = {}
    sku_to_price = {}
    page = 1
    while True:
        params = {'organization_id': ZOHO_ORG_ID, 'page': page, 'per_page': 200}
        data = requests.get(url, headers=headers, params=params).json()
        items = data.get('items', [])
        if not items: break
        for item in items:
            sku = (item.get('sku', '') or '').strip()
            brand = (item.get('brand', '') or '').strip()
            if sku:
                sku_to_brand[sku] = brand
                sku_to_price[sku] = {
                    'name': item.get('name', ''),
                    'price': float(item.get('rate', 0)),
                    'cost': float(item.get('purchase_rate', 0)),
                }
        print(f"   Page {page}: {len(items)} items")
        page += 1
        time.sleep(0.5)
        if not data.get('page_context', {}).get('has_more_page'): break
    
    brands_with_data = sum(1 for b in sku_to_brand.values() if b)
    print(f"   ✅ Loaded {len(sku_to_brand)} SKUs, {brands_with_data} have brand data")
    return sku_to_brand, sku_to_price

def fetch_flutter_products(supabase: Client) -> List[Dict]:
    print("\n📥 Fetching ALL products from Flutter/Supabase...")
    all_products = []
    offset = 0
    while True:
        resp = supabase.table('products') \
            .select('id,name,sku,price,cost,brand,brand_id,supplier_id,supplier_name,image_url,tenant_id') \
            .eq('tenant_id', TENANT_ID) \
            .range(offset, offset + 999) \
            .execute()
        if not resp.data: break
        all_products.extend(resp.data)
        if len(resp.data) < 1000: break
        offset += 1000
    print(f"   ✅ Total: {len(all_products)} products")
    return all_products

# ============================================================================
# MAIN
# ============================================================================
def main():
    print("\n" + "=" * 80)
    print("🚀 ZOHO → FLUTTER SYNC (CSV + API, BRAND + SUPPLIER)")
    print("=" * 80)
    print("RULES:")
    print(" ✅ Upsert (insert new, update existing)")
    print(" ✅ Sync Brand (from Zoho API)")
    print(" ✅ Sync Supplier Name (from CSV Vendor column)")
    print(" ❌ Skip stock_quantity")
    print(" ❌ Skip image_url")
    print(" 🔗 Match by SKU")
    
    # 1. Load data from all sources
    csv_vendors = load_csv_vendors()
    zoho_brands, zoho_prices = fetch_zoho_brands()
    
    supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
    flutter_products = fetch_flutter_products(supabase)
    flutter_map = {p.get('sku'): p for p in flutter_products if p.get('sku')}
    
    # Get all Zoho SKUs (union of CSV and API)
    all_zoho_skus = set(csv_vendors.keys()) | set(zoho_brands.keys())
    
    # 2. Build upsert payloads
    print("\n📋 Analyzing differences...")
    upserts = []
    summary = {'brand_updates': 0, 'supplier_updates': 0, 'new_products': 0}
    
    for sku in all_zoho_skus:
        if not sku:
            continue
        
        zoho_brand = (zoho_brands.get(sku, '') or '').strip()
        zoho_vendor = (csv_vendors.get(sku, '') or '').strip()
        zoho_info = zoho_prices.get(sku, {})
        zoho_name = zoho_info.get('name', '')
        zoho_price = zoho_info.get('price', 0)
        zoho_cost = zoho_info.get('cost', 0)
        
        fp = flutter_map.get(sku)
        
        if fp:
            # EXISTING product - only check brand and supplier
            flutter_brand = (fp.get('brand', '') or '').strip()
            flutter_supplier = (fp.get('supplier_name', '') or '').strip()
            
            changes = {}
            reasons = []
            
            # Brand: update if flutter is empty and zoho has data
            if zoho_brand and not flutter_brand:
                changes['brand'] = zoho_brand
                reasons.append(f"Brand: '' -> '{zoho_brand}'")
                summary['brand_updates'] += 1
            
            # Supplier: update if flutter is empty and zoho CSV has data
            if zoho_vendor and not flutter_supplier:
                changes['supplier_name'] = zoho_vendor
                reasons.append(f"Supplier: '' -> '{zoho_vendor}'")
                summary['supplier_updates'] += 1
            
            if changes:
                payload = {'id': fp['id'], 'sku': sku, 'tenant_id': TENANT_ID}
                payload.update(changes)
                # Preserve existing image_url
                if fp.get('image_url'):
                    payload['image_url'] = fp['image_url']
                upserts.append({'payload': payload, 'reasons': reasons, 'type': 'UPDATE', 'name': fp.get('name', zoho_name)})
        else:
            # NEW product - insert
            if not zoho_name:
                continue  # skip if we don't even have a name
            payload = {
                'tenant_id': TENANT_ID,
                'sku': sku,
                'name': zoho_name,
                'price': zoho_price,
                'cost': zoho_cost,
            }
            if zoho_brand:
                payload['brand'] = zoho_brand
            if zoho_vendor:
                payload['supplier_name'] = zoho_vendor
            
            upserts.append({'payload': payload, 'reasons': ['New product'], 'type': 'INSERT', 'name': zoho_name})
            summary['new_products'] += 1
    
    # 3. Show summary
    print(f"\n{'='*80}")
    print(f"📊 SYNC SUMMARY")
    print(f"{'='*80}")
    print(f"Zoho total SKUs: {len(all_zoho_skus)}")
    print(f"Flutter total products: {len(flutter_products)}")
    print(f"\nChanges to apply:")
    print(f"  🏷️  Brand updates: {summary['brand_updates']}")
    print(f"  🏭 Supplier updates: {summary['supplier_updates']}")
    print(f"  🆕 New products: {summary['new_products']}")
    print(f"  📦 Total upserts: {len(upserts)}")
    
    # Group supplier updates by vendor
    supplier_groups = {}
    for u in upserts:
        if 'supplier_name' in u['payload']:
            vendor = u['payload']['supplier_name']
            supplier_groups.setdefault(vendor, []).append(u)
    
    if supplier_groups:
        print(f"\n  Supplier updates by vendor:")
        for vendor, items in sorted(supplier_groups.items(), key=lambda x: -len(x[1])):
            print(f"    {vendor}: {len(items)} products")
    
    # Preview
    print(f"\n🧐 Preview (first 15):")
    for u in upserts[:15]:
        print(f"  [{u['type']}] {u['payload']['sku']} ({u['name']})")
        for r in u['reasons']:
            print(f"         {r}")
    if len(upserts) > 15:
        print(f"  ... and {len(upserts) - 15} more")
    
    if not upserts:
        print("\n✅ Everything is up to date!")
        return
    
    # Save full report
    with open('temp_sync_report.json', 'w', encoding='utf-8') as f:
        json.dump({
            'summary': summary,
            'supplier_groups': {k: len(v) for k, v in supplier_groups.items()},
            'upserts': [{'sku': u['payload']['sku'], 'name': u['name'], 'type': u['type'], 'reasons': u['reasons']} for u in upserts]
        }, f, ensure_ascii=False, indent=2)
    print("\n📄 Full report saved to temp_sync_report.json")
    
    confirm = input("\nProceed with Upsert? (yes/no): ").strip().lower()
    if confirm != 'yes':
        print("❌ Cancelled")
        return
    
    # 4. Execute updates and inserts separately
    print("\n🔄 Applying changes to Supabase...")
    
    # Split into updates (have id) and inserts (no id)
    update_items = [u for u in upserts if u['type'] == 'UPDATE']
    insert_items = [u for u in upserts if u['type'] == 'INSERT']
    
    success = 0
    failed = 0
    errors = []
    
    # UPDATES: use .update().eq('id', id) for each product
    if update_items:
        print(f"\n   📝 Updating {len(update_items)} existing products...")
        for i, u in enumerate(update_items):
            payload = u['payload']
            product_id = payload.pop('id')  # Remove id from payload, use as filter
            payload.pop('sku', None)  # Don't update SKU
            payload.pop('tenant_id', None)  # Don't update tenant_id
            payload.pop('image_url', None)  # Don't touch image_url
            
            try:
                supabase.table('products').update(payload).eq('id', product_id).execute()
                success += 1
            except Exception as e:
                failed += 1
                errors.append(f"{u['payload'].get('sku', '?')}: {e}")
            
            if (i + 1) % 100 == 0:
                print(f"      Progress: {i+1}/{len(update_items)} ({success} ok, {failed} failed)")
        
        print(f"      ✅ Updates done: {success} ok, {failed} failed")
    
    # INSERTS: use insert for new products
    if insert_items:
        print(f"\n   🆕 Inserting {len(insert_items)} new products...")
        for ins in insert_items:
            payload = ins['payload']
            if not payload.get('name'):
                failed += 1
                continue
            try:
                supabase.table('products').insert(payload).execute()
                success += 1
                print(f"      ✅ Inserted: {payload['sku']} ({payload['name']})")
            except Exception as e:
                failed += 1
                errors.append(f"INSERT {payload['sku']}: {e}")
                print(f"      ❌ Failed {payload['sku']}: {e}")
    
    print(f"\n{'='*80}")
    print(f"✅ Successfully applied: {success}")
    if failed:
        print(f"❌ Failed: {failed}")
        if errors[:5]:
            print("First 5 errors:")
            for e in errors[:5]:
                print(f"   {e}")
    print(f"{'='*80}")


if __name__ == "__main__":
    main()
