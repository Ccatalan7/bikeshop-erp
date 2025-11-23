"""
Delete all product categories from Supabase

Use this to clean up before fresh import from Odoo.
"""

import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))

from connections.supabase_connection import SupabaseConnection

def main():
    print("\n" + "=" * 80)
    print("🗑️  Delete All Categories from Supabase")
    print("=" * 80)
    
    # Connect to Supabase
    supabase = SupabaseConnection()
    
    # Fetch existing categories
    print("\n📥 Fetching existing categories...")
    existing = supabase.fetch_all_categories()
    
    if not existing:
        print("✅ No categories found - nothing to delete")
        return
    
    print(f"   Found {len(existing)} categories")
    
    # Show preview
    print("\n📋 Categories to delete:")
    for cat in existing[:20]:  # Show first 20
        print(f"   • {cat['name']}")
    if len(existing) > 20:
        print(f"   ... and {len(existing) - 20} more")
    
    # Confirm
    print("\n" + "=" * 80)
    print("⚠️  WARNING: This will delete ALL categories for your tenant!")
    confirm = input("Are you sure? Type 'DELETE' to confirm: ").strip()
    if confirm != 'DELETE':
        print("❌ Cancelled")
        return
    
    # Delete all
    print("\n🗑️  Deleting categories...")
    success = 0
    failed = 0
    
    for cat in existing:
        try:
            supabase.client.table('product_categories') \
                .delete() \
                .eq('id', cat['id']) \
                .eq('tenant_id', supabase.tenant_id) \
                .execute()
            success += 1
            print(f"   ✅ Deleted: {cat['name']}")
        except Exception as e:
            failed += 1
            print(f"   ❌ Failed: {cat['name']} - {str(e)}")
    
    # Summary
    print("\n" + "=" * 80)
    print("📊 DELETION SUMMARY")
    print("=" * 80)
    print(f"✅ Successfully deleted: {success}")
    print(f"❌ Failed: {failed}")
    print("=" * 80)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n⚠️ Cancelled by user")
    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
