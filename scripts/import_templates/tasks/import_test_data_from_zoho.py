"""
Task: Import 20 random products (with categories), 20 suppliers, and 20 customers from Zoho to Supabase staging
Purpose: Testing data for staging environment
"""

import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))

import random
from connections.zoho_connection import ZohoConnection
from connections.supabase_connection import SupabaseConnection

def normalize_name(name: str) -> str:
    """Normalize names for comparison"""
    return name.lower().strip()

def import_categories(zoho, supabase, product_categories):
    """Import unique categories from products"""
    print("\n📁 Importing product categories...")
    
    # Get unique categories
    unique_categories = {}
    for cat_name in product_categories:
        if cat_name and cat_name.strip():
            normalized = normalize_name(cat_name)
            if normalized not in unique_categories:
                unique_categories[normalized] = cat_name
    
    print(f"   Found {len(unique_categories)} unique categories")
    
    # Check existing categories
    existing = supabase.client.table('product_categories').select('name').execute()
    existing_names = {normalize_name(c['name']) for c in existing.data}
    
    imported = 0
    for normalized, original_name in unique_categories.items():
        if normalized not in existing_names:
            try:
                supabase.client.table('product_categories').insert({
                    'name': original_name,
                    'tenant_id': supabase.tenant_id
                }).execute()
                imported += 1
                print(f"   ✅ Imported: {original_name}")
            except Exception as e:
                print(f"   ⚠️  Failed: {original_name} - {e}")
        else:
            print(f"   ⏭️  Skipped (exists): {original_name}")
    
    return imported

def import_products(zoho, supabase, count=20):
    """Import random products from Zoho"""
    print(f"\n📦 Importing {count} random products...")
    
    # Fetch all products from Zoho
    print("   Fetching products from Zoho...")
    zoho_products = zoho.fetch_all_products()
    print(f"   Found {len(zoho_products)} total products in Zoho")
    
    # Select random products
    if len(zoho_products) > count:
        selected_products = random.sample(zoho_products, count)
    else:
        selected_products = zoho_products
        print(f"   ⚠️  Only {len(zoho_products)} products available")
    
    # Collect categories for later import
    categories = set()
    for prod in selected_products:
        if prod.get('category_name'):
            categories.add(prod['category_name'])
    
    # Get existing SKUs to avoid duplicates
    existing = supabase.client.table('products').select('sku').execute()
    existing_skus = {p['sku'] for p in existing.data if p.get('sku')}
    
    imported = 0
    skipped = 0
    failed = 0
    
    for prod in selected_products:
        sku = prod.get('sku', '')
        name = prod.get('name', 'Unnamed Product')
        
        if sku in existing_skus:
            print(f"   ⏭️  Skipped (exists): {name} ({sku})")
            skipped += 1
            continue
        
        try:
            product_data = {
                'tenant_id': supabase.tenant_id,
                'name': name,
                'sku': sku or None,
                'price': float(prod.get('rate', 0)),
                'cost': float(prod.get('purchase_rate', 0)),
                'inventory_qty': int(prod.get('stock_on_hand', 0)),
                'stock_quantity': int(prod.get('stock_on_hand', 0)),
                'barcode': prod.get('upc') or prod.get('ean') or None
            }
            
            supabase.client.table('products').insert(product_data).execute()
            imported += 1
            print(f"   ✅ Imported: {name} ({sku})")
            
        except Exception as e:
            failed += 1
            print(f"   ❌ Failed: {name} - {e}")
    
    return imported, skipped, failed, list(categories)

def import_suppliers(zoho, supabase, count=20):
    """Import random suppliers (vendors) from Zoho"""
    print(f"\n🏭 Importing {count} random suppliers...")
    
    # Fetch all contacts from Zoho
    print("   Fetching contacts from Zoho...")
    zoho_contacts = zoho.fetch_all_contacts()
    
    # Filter vendors only
    vendors = [c for c in zoho_contacts if c.get('contact_type') == 'vendor']
    print(f"   Found {len(vendors)} vendors in Zoho")
    
    # Select random vendors
    if len(vendors) > count:
        selected_vendors = random.sample(vendors, count)
    else:
        selected_vendors = vendors
        print(f"   ⚠️  Only {len(vendors)} vendors available")
    
    # Get existing suppliers to avoid duplicates
    existing = supabase.client.table('suppliers').select('name').execute()
    existing_names = {normalize_name(s['name']) for s in existing.data}
    
    imported = 0
    skipped = 0
    failed = 0
    
    for vendor in selected_vendors:
        name = vendor.get('contact_name', 'Unnamed Supplier')
        normalized = normalize_name(name)
        
        if normalized in existing_names:
            print(f"   ⏭️  Skipped (exists): {name}")
            skipped += 1
            continue
        
        try:
            supplier_data = {
                'tenant_id': supabase.tenant_id,
                'name': name,
                'email': vendor.get('email') or None,
                'phone': vendor.get('phone') or None,
                'address': vendor.get('billing_address', {}).get('address') or None,
                'rut': vendor.get('custom_field_hash', {}).get('cf_rut') or None
            }
            
            supabase.client.table('suppliers').insert(supplier_data).execute()
            imported += 1
            print(f"   ✅ Imported: {name}")
            
        except Exception as e:
            failed += 1
            print(f"   ❌ Failed: {name} - {e}")
    
    return imported, skipped, failed

def import_customers(zoho, supabase, count=20):
    """Import random customers from Zoho"""
    print(f"\n👥 Importing {count} random customers...")
    
    # Fetch all contacts from Zoho
    print("   Fetching contacts from Zoho...")
    zoho_contacts = zoho.fetch_all_contacts()
    
    # Filter customers only
    customers = [c for c in zoho_contacts if c.get('contact_type') == 'customer']
    print(f"   Found {len(customers)} customers in Zoho")
    
    # Select random customers
    if len(customers) > count:
        selected_customers = random.sample(customers, count)
    else:
        selected_customers = customers
        print(f"   ⚠️  Only {len(customers)} customers available")
    
    # Get existing customers to avoid duplicates
    existing = supabase.client.table('customers').select('name, email').execute()
    existing_names = {normalize_name(c['name']) for c in existing.data}
    existing_emails = {c['email'].lower() for c in existing.data if c.get('email')}
    
    imported = 0
    skipped = 0
    failed = 0
    
    for customer in selected_customers:
        name = customer.get('contact_name', 'Unnamed Customer')
        email = customer.get('email', '').lower() if customer.get('email') else None
        normalized_name = normalize_name(name)
        
        # Skip if name or email already exists
        if normalized_name in existing_names or (email and email in existing_emails):
            print(f"   ⏭️  Skipped (exists): {name}")
            skipped += 1
            continue
        
        try:
            customer_data = {
                'tenant_id': supabase.tenant_id,
                'name': name,
                'email': email
            }
            
            supabase.client.table('customers').insert(customer_data).execute()
            imported += 1
            print(f"   ✅ Imported: {name}")
            
        except Exception as e:
            failed += 1
            print(f"   ❌ Failed: {name} - {e}")
    
    return imported, skipped, failed

def main():
    print("\n" + "=" * 80)
    print("🧪 IMPORT TEST DATA FROM ZOHO TO STAGING")
    print("=" * 80)
    print("\n⚠️  Target: STAGING environment (kyvgmapifacpzuyreasy)")
    print("📊 Will import:")
    print("   - 20 random products (with their categories)")
    print("   - 20 random suppliers")
    print("   - 20 random customers")
    
    print("\n🔑 Zoho credentials needed (I'll reuse them for this session)")
    print("   Get these from Zoho Developer Console\n")
    zoho_client_id = input("Zoho Client ID: ").strip()
    zoho_client_secret = input("Zoho Client Secret: ").strip()
    zoho_refresh_token = input("Zoho Refresh Token: ").strip()
    
    # Initialize connections (Zoho credentials are hardcoded in config.py for this test)
    print("\n🔌 Connecting to Zoho and Supabase...")
    zoho = ZohoConnection(zoho_client_id, zoho_client_secret, zoho_refresh_token)
    supabase = SupabaseConnection()  # Uses staging config
    
    print(f"   ✅ Connected to Supabase staging (tenant: {supabase.tenant_id[:8]}...)")
    print(f"   ✅ Connected to Zoho (org: {zoho.org_id})")
    
    # Confirm before proceeding
    confirm = input("\n⚠️  This will import data to STAGING. Proceed? (yes/no): ").strip().lower()
    if confirm != 'yes':
        print("❌ Cancelled by user")
        return
    
    # Track totals
    total_imported = 0
    total_skipped = 0
    total_failed = 0
    
    try:
        # Import products ONLY (suppliers and customers already imported)
        prod_imported, prod_skipped, prod_failed, categories = import_products(zoho, supabase, count=20)
        total_imported += prod_imported
        total_skipped += prod_skipped
        total_failed += prod_failed
        
        # Skip categories (not needed)
        cat_imported = 0
        
        # Skip suppliers (already imported)
        supp_imported = 0
        supp_skipped = 0
        supp_failed = 0
        
        # Skip customers (already imported)
        cust_imported = 0
        cust_skipped = 0
        cust_failed = 0
        
        # Final summary
        print("\n" + "=" * 80)
        print("📊 IMPORT SUMMARY")
        print("=" * 80)
        print(f"✅ Total imported:  {total_imported}")
        print(f"⏭️  Total skipped:   {total_skipped} (already existed)")
        print(f"❌ Total failed:    {total_failed}")
        print("=" * 80)
        print("\n🎉 Import completed!")
        
    except Exception as e:
        print(f"\n❌ FATAL ERROR: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n⚠️  Cancelled by user (Ctrl+C)")
    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
