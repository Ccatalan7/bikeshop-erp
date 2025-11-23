"""
Import Product Categories from Odoo to Supabase

Fetches product categories from Odoo (including hierarchy) and imports them into Supabase.
"""

import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))

from connections.odoo_connection import OdooConnection
from connections.supabase_connection import SupabaseConnection

# Odoo API key (provided by user)
ODOO_API_KEY = "aac576b5e8f222233dac50a326568030fce3c70c"

def normalize_name(name):
    """Normalize category name for comparison"""
    return name.lower().strip()

def main():
    print("\n" + "=" * 80)
    print("🔧 Import Categories from Odoo to Supabase")
    print("=" * 80)
    
    # Step 1: Connect to Odoo
    print("\n🔗 Connecting to Odoo...")
    odoo = OdooConnection(ODOO_API_KEY)
    
    # Step 2: Fetch Odoo categories
    print("\n📥 Fetching categories from Odoo...")
    
    # Search all product categories
    category_ids = odoo.search('product.category', [])
    
    if not category_ids:
        print("❌ No categories found in Odoo")
        return
    
    # Read category data with parent relationship
    categories = odoo.read('product.category', category_ids, ['name', 'parent_id', 'complete_name'])
    
    print(f"   ✅ Found {len(categories)} categories in Odoo")
    
    # Step 3: Connect to Supabase
    supabase = SupabaseConnection()
    
    # Step 4: Fetch existing categories
    print("\n📥 Fetching existing categories from Supabase...")
    existing = supabase.fetch_all_categories()
    existing_by_name = {normalize_name(c['name']): c for c in existing}
    print(f"   ✅ Found {len(existing)} existing categories")
    
    # Step 5: Build category hierarchy
    # First pass: create all categories without parent_id
    # Second pass: update parent_id references
    
    odoo_by_id = {cat['id']: cat for cat in categories}
    to_create = []
    to_skip = []
    odoo_to_supabase_id = {}  # Map Odoo ID -> Supabase ID for parent linking
    
    for odoo_cat in categories:
        name = odoo_cat.get('name', '').strip()
        if not name:
            continue
        
        name_key = normalize_name(name)
        
        if name_key in existing_by_name:
            to_skip.append(name)
            odoo_to_supabase_id[odoo_cat['id']] = existing_by_name[name_key]['id']
        else:
            # Determine level and full_path
            complete_name = odoo_cat.get('complete_name', name)
            path_parts = complete_name.split(' / ')
            level = len(path_parts) - 1
            full_path = ' > '.join(path_parts)
            
            # Build category data (parent_id will be set in second pass)
            category_data = {
                'tenant_id': supabase.tenant_id,
                'name': name,
                'description': '',
                'parent_id': None,  # Will be set later
                'level': level,
                'full_path': full_path,
                'is_active': True,
                'odoo_id': odoo_cat['id'],  # Store for parent mapping
                'odoo_parent_id': odoo_cat.get('parent_id')[0] if odoo_cat.get('parent_id') else None
            }
            to_create.append(category_data)
    
    # Step 6: Show preview
    print("\n" + "=" * 80)
    print("📋 PREVIEW OF CHANGES")
    print("=" * 80)
    print(f"✅ New categories to create: {len(to_create)}")
    print(f"⏭️  Existing categories (skip): {len(to_skip)}")
    
    if to_create:
        print("\n📝 Categories to create:")
        for cat in sorted(to_create, key=lambda x: x['full_path'])[:15]:
            indent = "  " * cat['level']
            print(f"   {indent}• {cat['name']} (level {cat['level']})")
        if len(to_create) > 15:
            print(f"   ... and {len(to_create) - 15} more")
    
    # Step 7: Confirm
    print("\n" + "=" * 80)
    confirm = input("Proceed with import? (yes/no): ").strip().lower()
    if confirm != 'yes':
        print("❌ Cancelled")
        return
    
    # Step 8: Import categories (first pass - no parent_id)
    print("\n🔄 Importing categories (pass 1: creating records)...")
    success = 0
    failed = 0
    created_categories = []
    
    # Sort by level (parents first)
    to_create_sorted = sorted(to_create, key=lambda x: x['level'])
    
    for cat_data in to_create_sorted:
        try:
            # Remove temporary fields before insert
            odoo_id = cat_data.pop('odoo_id')
            odoo_parent_id = cat_data.pop('odoo_parent_id')
            
            result = supabase.client.table('product_categories').insert(cat_data).execute()
            created_cat = result.data[0]
            
            # Store mapping
            odoo_to_supabase_id[odoo_id] = created_cat['id']
            created_categories.append({
                'supabase_id': created_cat['id'],
                'odoo_parent_id': odoo_parent_id,
                'name': cat_data['name']
            })
            
            success += 1
            print(f"   ✅ Created: {cat_data['name']}")
        except Exception as e:
            failed += 1
            print(f"   ❌ Failed: {cat_data['name']} - {str(e)}")
    
    # Step 9: Update parent_id references (second pass)
    print("\n🔄 Updating parent references (pass 2)...")
    updated = 0
    
    for cat in created_categories:
        if cat['odoo_parent_id'] and cat['odoo_parent_id'] in odoo_to_supabase_id:
            try:
                parent_supabase_id = odoo_to_supabase_id[cat['odoo_parent_id']]
                supabase.client.table('product_categories') \
                    .update({'parent_id': parent_supabase_id}) \
                    .eq('id', cat['supabase_id']) \
                    .eq('tenant_id', supabase.tenant_id) \
                    .execute()
                updated += 1
                print(f"   ✅ Updated parent: {cat['name']}")
            except Exception as e:
                print(f"   ❌ Failed to update parent for {cat['name']}: {str(e)}")
    
    # Step 10: Summary
    print("\n" + "=" * 80)
    print("📊 IMPORT SUMMARY")
    print("=" * 80)
    print(f"✅ Successfully created: {success}")
    print(f"🔗 Parent links updated: {updated}")
    print(f"❌ Failed: {failed}")
    print(f"⏭️  Skipped (already exist): {len(to_skip)}")
    print("=" * 80)
    
    if success > 0:
        print("\n🎉 Categories imported with hierarchy! Now you can:")
        print("   1. Refresh your Flutter app")
        print("   2. Open product form")
        print("   3. Click 'Seleccionar Categoría'")
        print("   4. See your Odoo categories with hierarchy!")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n⚠️ Cancelled by user")
    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
