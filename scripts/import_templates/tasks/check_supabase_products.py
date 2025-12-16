"""
Check Supabase products table columns (specifically supplier_code and image_url)
"""
import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))

from connections.supabase_connection import SupabaseConnection

def main():
    print("\n🔍 Checking Supabase products table structure...")
    
    supabase = SupabaseConnection()
    
    # Fetch just a few products with all columns
    response = supabase.client.table('products') \
        .select('*') \
        .eq('tenant_id', supabase.tenant_id) \
        .limit(3) \
        .execute()
    
    print(f"\n📦 Sample products (first 3):\n")
    
    for prod in response.data:
        print(f"=" * 80)
        print(f"Name: {prod.get('name')}")
        print(f"SKU: {prod.get('sku')}")
        print(f"\n🔑 ALL COLUMNS:")
        for key, value in prod.items():
            print(f"  {key}: {value}")
        print()
    
    # Show specific fields we're interested in
    if response.data:
        first = response.data[0]
        print("\n" + "=" * 80)
        print("🎯 FIELDS WE CARE ABOUT:")
        print(f"  supplier_code: {'supplier_code' in first} (value: {first.get('supplier_code', 'N/A')})")
        print(f"  image_url: {'image_url' in first} (value: {first.get('image_url', 'N/A')})")
        print(f"  image: {'image' in first} (value: {first.get('image', 'N/A')})")

if __name__ == "__main__":
    main()
