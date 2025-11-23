"""
Import Product Categories from Zoho Inventory to Supabase

Fetches item categories from Zoho and imports them into product_categories table.
"""

import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))

import requests
from connections.supabase_connection import SupabaseConnection

# Zoho credentials (provided by user)
REFRESH_TOKEN = "1000.891769ebb70d58d81711bd500a98a143.8ae2155bfae86e41805d983a947bd1c7"
CLIENT_ID = "1000.K45UH1SOSFKEMMQH8FUGKPA4K3PGMF"
CLIENT_SECRET = "c1959d0f2686af40ce3f3749bdae84e74bf8d58d48"

ZOHO_OAUTH_DOMAIN = "https://accounts.zoho.com"
ZOHO_API_DOMAIN = "https://www.zohoapis.com"
ZOHO_ORG_ID = "788658742"

def get_access_token():
    """Get fresh access token using refresh token"""
    print("🔑 Getting access token...")
    
    token_url = f"{ZOHO_OAUTH_DOMAIN}/oauth/v2/token"
    params = {
        'refresh_token': REFRESH_TOKEN,
        'client_id': CLIENT_ID,
        'client_secret': CLIENT_SECRET,
        'grant_type': 'refresh_token'
    }
    
    response = requests.post(token_url, params=params)
    response.raise_for_status()
    
    access_token = response.json()['access_token']
    print("   ✅ Token obtained (valid for 1 hour)")
    return access_token

def fetch_zoho_categories(access_token):
    """Fetch all unique categories from Zoho items"""
    print("\n📥 Fetching items from Zoho to extract categories...")
    
    url = f"{ZOHO_API_DOMAIN}/inventory/v1/items"
    headers = {
        'Authorization': f'Zoho-oauthtoken {access_token}',
        'Content-Type': 'application/json'
    }
    
    all_categories = set()
    page = 1
    
    while True:
        params = {
            'organization_id': ZOHO_ORG_ID,
            'page': page,
            'per_page': 200
        }
        
        response = requests.get(url, headers=headers, params=params)
        response.raise_for_status()
        
        data = response.json()
        items = data.get('items', [])
        
        if not items:
            break
        
        # Extract categories from items
        for item in items:
            category_name = item.get('category_name', '').strip()
            if category_name:
                all_categories.add(category_name)
        
        print(f"   Page {page}: {len(items)} items processed")
        page += 1
        
        if not data.get('page_context', {}).get('has_more_page'):
            break
    
    categories = [{'name': cat} for cat in sorted(all_categories)]
    print(f"   ✅ Found {len(categories)} unique categories")
    return categories

def normalize_name(name):
    """Normalize category name for comparison"""
    return name.lower().strip()

def main():
    print("\n" + "=" * 80)
    print("🔧 Import Categories from Zoho to Supabase")
    print("=" * 80)
    
    # Step 1: Get access token
    access_token = get_access_token()
    
    # Step 2: Fetch Zoho categories
    zoho_categories = fetch_zoho_categories(access_token)
    
    if not zoho_categories:
        print("❌ No categories found in Zoho")
        return
    
    # Step 3: Connect to Supabase
    supabase = SupabaseConnection()
    
    # Step 4: Fetch existing categories
    print("\n📥 Fetching existing categories from Supabase...")
    existing = supabase.fetch_all_categories()
    existing_by_name = {normalize_name(c['name']): c for c in existing}
    print(f"   ✅ Found {len(existing)} existing categories")
    
    # Step 5: Prepare import
    to_create = []
    to_skip = []
    
    for zoho_cat in zoho_categories:
        name = zoho_cat.get('name', '').strip()
        if not name:
            continue
        
        name_key = normalize_name(name)
        
        if name_key in existing_by_name:
            to_skip.append(name)
        else:
            # Build category data
            category_data = {
                'tenant_id': supabase.tenant_id,
                'name': name,
                'description': '',  # Zoho doesn't provide category descriptions
                'parent_id': None,  # Flat structure from Zoho
                'level': 0,
                'full_path': name,
                'is_active': True
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
        for cat in to_create[:10]:  # Show first 10
            print(f"   • {cat['name']}")
        if len(to_create) > 10:
            print(f"   ... and {len(to_create) - 10} more")
    
    # Step 7: Confirm
    print("\n" + "=" * 80)
    confirm = input("Proceed with import? (yes/no): ").strip().lower()
    if confirm != 'yes':
        print("❌ Cancelled")
        return
    
    # Step 8: Import
    print("\n🔄 Importing categories...")
    success = 0
    failed = 0
    
    for cat_data in to_create:
        try:
            result = supabase.client.table('product_categories').insert(cat_data).execute()
            success += 1
            print(f"   ✅ Created: {cat_data['name']}")
        except Exception as e:
            failed += 1
            print(f"   ❌ Failed: {cat_data['name']} - {str(e)}")
    
    # Step 9: Summary
    print("\n" + "=" * 80)
    print("📊 IMPORT SUMMARY")
    print("=" * 80)
    print(f"✅ Successfully created: {success}")
    print(f"❌ Failed: {failed}")
    print(f"⏭️  Skipped (already exist): {len(to_skip)}")
    print("=" * 80)
    
    if success > 0:
        print("\n🎉 Categories imported! Now you can:")
        print("   1. Refresh your Flutter app")
        print("   2. Open product form")
        print("   3. Click 'Seleccionar Categoría'")
        print("   4. See your imported categories!")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n⚠️ Cancelled by user")
    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
