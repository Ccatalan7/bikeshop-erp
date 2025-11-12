"""
🔄 ODOO → FLUTTER (SUPABASE) SYNC
==================================

WHAT THIS DOES:
- Syncs products from Odoo to Flutter app database (Supabase)
- Syncs categories with hierarchical structure (Parent / Child / Grandchild)
- Matches products by SKU (default_code in Odoo)
- Creates missing categories automatically
- Updates product categories

WHEN TO USE:
- Initial product import from Odoo
- Periodic sync to keep Flutter app updated with Odoo changes
- After adding new products/categories in Odoo

REQUIREMENTS:
- Odoo API credentials (username, password/API key, database name)
- Supabase credentials (URL, service role key)
- Tenant ID (from Supabase tenants table)
"""

import sys
from pathlib import Path

# Add scripts directory to path
sys.path.append(str(Path(__file__).parent))

try:
    import config
except ImportError:
    print("\n❌ ERROR: config.py not found!")
    print("\n📝 SETUP INSTRUCTIONS:")
    print("1. Copy config.template.py to config.py")
    print("2. Edit config.py with your credentials")
    print("3. Run this script again\n")
    sys.exit(1)

# Validate configuration
if not config.validate_config():
    sys.exit(1)

from supabase import create_client
import xmlrpc.client
from typing import Dict, List, Set
import time

# ============================================================================
# CONFIGURATION
# ============================================================================

SUPABASE_URL = config.SUPABASE_URL
SUPABASE_KEY = config.SUPABASE_SERVICE_ROLE_KEY
TENANT_ID = config.TENANT_ID

ODOO_URL = config.ODOO_URL
ODOO_DB = config.ODOO_DB
ODOO_USERNAME = config.ODOO_USERNAME
ODOO_API_KEY = config.ODOO_API_KEY

BATCH_SIZE = config.BATCH_SIZE

# ============================================================================
# MAIN SYNC LOGIC
# ============================================================================

def sync_categories(client, odoo_uid, odoo_models) -> Dict[int, str]:
    """
    Sync all categories from Odoo to Supabase
    
    Returns:
        Dict mapping Odoo category ID to Supabase category ID
    """
    print("\n" + "=" * 80)
    print("📁 SYNCING CATEGORIES")
    print("=" * 80)
    
    # Fetch all categories from Odoo
    print("\n1️⃣ Fetching categories from Odoo...")
    categories = odoo_models.execute_kw(
        ODOO_DB, odoo_uid, ODOO_API_KEY,
        'product.category', 'search_read',
        [[]],
        {'fields': ['id', 'name', 'complete_name', 'parent_id']}
    )
    print(f"   ✅ Found {len(categories)} categories")
    
    # Fetch existing categories from Supabase
    print("\n2️⃣ Checking existing categories in Supabase...")
    existing = client.table("product_categories")\
        .select("full_path, id")\
        .eq("tenant_id", TENANT_ID)\
        .execute()
    
    existing_paths = {cat['full_path']: cat['id'] for cat in existing.data}
    print(f"   ✅ Found {len(existing_paths)} existing categories")
    
    # Create missing categories
    print("\n3️⃣ Creating missing categories...")
    category_cache = existing_paths.copy()
    
    def get_or_create_category(complete_name: str) -> str:
        """Recursively create category hierarchy"""
        if complete_name in category_cache:
            return category_cache[complete_name]
        
        parts = complete_name.split(' / ')
        parent_id = None
        current_path = []
        
        for i, part in enumerate(parts):
            current_path.append(part)
            full_path = ' / '.join(current_path)
            level = i
            
            if full_path in category_cache:
                parent_id = category_cache[full_path]
                continue
            
            # Check if exists in database
            response = client.table("product_categories").select("id")\
                .eq("tenant_id", TENANT_ID)\
                .eq("full_path", full_path)\
                .execute()
            
            if response.data:
                category_id = response.data[0]['id']
            else:
                # Create new category
                insert_data = {
                    'tenant_id': TENANT_ID,
                    'name': part,
                    'full_path': full_path,
                    'parent_id': parent_id,
                    'level': level,
                    'is_active': True
                }
                response = client.table("product_categories").insert(insert_data).execute()
                category_id = response.data[0]['id']
                print(f"   ➕ Created: {full_path}")
            
            category_cache[full_path] = category_id
            parent_id = category_id
        
        return parent_id
    
    # Process all categories
    odoo_to_supabase = {}
    created_count = 0
    
    for cat in categories:
        supabase_id = get_or_create_category(cat['complete_name'])
        odoo_to_supabase[cat['id']] = supabase_id
        if cat['complete_name'] not in existing_paths:
            created_count += 1
    
    print(f"\n   ✅ Created {created_count} new categories")
    print(f"   ✅ Total categories: {len(category_cache)}")
    
    return odoo_to_supabase


def sync_products(client, odoo_uid, odoo_models, category_map: Dict[int, str]):
    """
    Sync products from Odoo to Supabase
    
    Args:
        client: Supabase client
        odoo_uid: Odoo user ID
        odoo_models: Odoo models proxy
        category_map: Mapping from Odoo category ID to Supabase category ID
    """
    print("\n" + "=" * 80)
    print("📦 SYNCING PRODUCTS")
    print("=" * 80)
    
    # Fetch all products from Supabase
    print("\n1️⃣ Fetching products from Supabase...")
    all_products = []
    offset = 0
    
    while True:
        response = client.table("products")\
            .select("id, sku, category_id")\
            .eq("tenant_id", TENANT_ID)\
            .range(offset, offset + BATCH_SIZE - 1)\
            .execute()
        
        all_products.extend(response.data)
        
        if len(response.data) < BATCH_SIZE:
            break
        offset += BATCH_SIZE
    
    print(f"   ✅ Found {len(all_products)} products")
    
    # Fetch products from Odoo
    print("\n2️⃣ Fetching products from Odoo...")
    odoo_products = odoo_models.execute_kw(
        ODOO_DB, odoo_uid, ODOO_API_KEY,
        'product.product', 'search_read',
        [[]],
        {'fields': ['default_code', 'categ_id', 'name', 'list_price']}
    )
    print(f"   ✅ Found {len(odoo_products)} products")
    
    # Build SKU to category mapping
    print("\n3️⃣ Building SKU to category mapping...")
    sku_to_category = {}
    for product in odoo_products:
        sku = product.get('default_code')
        if sku and product.get('categ_id'):
            odoo_cat_id = product['categ_id'][0]
            if odoo_cat_id in category_map:
                sku_to_category[sku] = category_map[odoo_cat_id]
    
    print(f"   ✅ Mapped {len(sku_to_category)} SKUs to categories")
    
    # Update products
    print("\n4️⃣ Updating product categories...")
    updated = 0
    skipped = 0
    not_found = 0
    
    for product in all_products:
        sku = product['sku']
        
        if sku in sku_to_category:
            # Update category
            client.table("products")\
                .update({'category_id': sku_to_category[sku]})\
                .eq('id', product['id'])\
                .execute()
            updated += 1
        elif product.get('category_id'):
            skipped += 1  # Already has category
        else:
            not_found += 1  # SKU not found in Odoo
    
    print(f"\n   ✅ Updated: {updated}")
    print(f"   ⏭️  Skipped (already set): {skipped}")
    print(f"   ⚠️  Not found in Odoo: {not_found}")


def main():
    """Main sync function"""
    print("\n" + "=" * 80)
    print("🔄 ODOO → FLUTTER SYNC")
    print("=" * 80)
    print(f"\n📊 Configuration:")
    print(f"   Odoo: {ODOO_URL}")
    print(f"   Database: {ODOO_DB}")
    print(f"   Supabase: {SUPABASE_URL}")
    print(f"   Tenant: {TENANT_ID}")
    
    # Initialize connections
    print("\n🔗 Connecting to services...")
    
    # Supabase
    client = create_client(SUPABASE_URL, SUPABASE_KEY)
    print("   ✅ Supabase connected")
    
    # Odoo
    common = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/common')
    uid = common.authenticate(ODOO_DB, ODOO_USERNAME, ODOO_API_KEY, {})
    
    if not uid:
        print("   ❌ Failed to authenticate with Odoo")
        return
    
    models = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/object')
    print(f"   ✅ Odoo connected (User ID: {uid})")
    
    # Sync categories first
    category_map = sync_categories(client, uid, models)
    
    # Sync products
    sync_products(client, uid, models, category_map)
    
    # Summary
    print("\n" + "=" * 80)
    print("✅ SYNC COMPLETE!")
    print("=" * 80)
    
    # Final stats
    total_products = client.table("products")\
        .select("id", count="exact")\
        .eq("tenant_id", TENANT_ID)\
        .execute()
    
    with_categories = client.table("products")\
        .select("id", count="exact")\
        .eq("tenant_id", TENANT_ID)\
        .not_.is_("category_id", "null")\
        .execute()
    
    total_categories = client.table("product_categories")\
        .select("id", count="exact")\
        .eq("tenant_id", TENANT_ID)\
        .execute()
    
    print(f"\n📊 Final Stats:")
    print(f"   Categories: {total_categories.count}")
    print(f"   Products: {total_products.count}")
    print(f"   With categories: {with_categories.count} ({with_categories.count/total_products.count*100:.1f}%)")
    print(f"   Without categories: {total_products.count - with_categories.count}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n⚠️  Sync cancelled by user")
    except Exception as e:
        print(f"\n\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
