"""
Import Product Images from Zoho to Supabase Storage

Downloads actual image files from Zoho using image_document_id
Uploads to Supabase Storage bucket 'vinabike-assets'  
Updates product image_url field
Only imports if: SKU matches AND product doesn't already have an image_url
"""

import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))

import requests
import tempfile
import os
from connections.supabase_connection import SupabaseConnection

# Zoho credentials
CLIENT_ID = "1000.LKVKZREYRMW7ZXKHF8O40ZDZ9XBR0A"
CLIENT_SECRET = "cfc323be8f4cb6190356248b7a24cd12646009afe4"
REFRESH_TOKEN = "1000.0dfaca4f7cece1a32d2e752eb855e2e5.0a5b064b44a904b0ad207c4a3edd2f06"
ZOHO_ORG_ID = "788658742"

# Supabase Storage
BUCKET_NAME = "vinabike-assets"


def get_zoho_access_token():
    """Get Zoho access token using refresh token"""
    print("🔑 Getting Zoho access token...")
    token_url = "https://accounts.zoho.com/oauth/v2/token"
    payload = {
        'grant_type': 'refresh_token',
        'client_id': CLIENT_ID,
        'client_secret': CLIENT_SECRET,
        'refresh_token': REFRESH_TOKEN
    }
    response = requests.post(token_url, params=payload)
    response.raise_for_status()
    print("   ✅ Token obtained")
    return response.json()['access_token']


def fetch_all_zoho_products_with_images(access_token):
    """Fetch all products from Zoho that have images"""
    print("\n📥 Fetching products from Zoho (with images)...")
    
    headers = {
        'Authorization': f'Zoho-oauthtoken {access_token}',
        'Content-Type': 'application/json'
    }
    
    all_items = []
    page = 1
    
    while True:
        url = "https://www.zohoapis.com/inventory/v1/items"
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
        
        for item in items:
            image_doc_id = item.get('image_document_id')
            if image_doc_id:  # Only products with images
                all_items.append({
                    'item_id': item.get('item_id'),
                    'sku': item.get('sku', ''),
                    'name': item.get('name', ''),
                    'image_document_id': image_doc_id,
                    'image_name': item.get('image_name', ''),
                    'image_type': item.get('image_type', 'jpg')
                })
        
        print(f"   Page {page}: {len(items)} items")
        page += 1
        
        if not data.get('page_context', {}).get('has_more_page'):
            break
    
    print(f"   ✅ Total with images: {len(all_items)} products")
    return all_items


def download_image_from_zoho(access_token, item_id, image_name):
    """Download image from Zoho"""
    headers = {
        'Authorization': f'Zoho-oauthtoken {access_token}'
    }
    
    # Zoho item image endpoint
    url = f"https://www.zohoapis.com/inventory/v1/items/{item_id}/image"
    params = {'organization_id': ZOHO_ORG_ID}
    
    response = requests.get(url, headers=headers, params=params)
    
    if response.status_code == 200:
        return response.content
    else:
        return None


def main():
    print("\n" + "=" * 80)
    print("🖼️  IMPORT PRODUCT IMAGES FROM ZOHO TO SUPABASE STORAGE")
    print("=" * 80)
    
    # Get Zoho access token
    access_token = get_zoho_access_token()
    
    # Fetch Zoho products with images
    zoho_products = fetch_all_zoho_products_with_images(access_token)
    
    # Build lookup by SKU
    zoho_by_sku = {}
    for p in zoho_products:
        if p['sku']:
            zoho_by_sku[p['sku']] = p
    
    print(f"\n📊 Zoho products with images: {len(zoho_by_sku)}")
    
    # Connect to Supabase
    supabase = SupabaseConnection()
    tenant_id = supabase.tenant_id
    
    # Fetch all Supabase products WITHOUT images
    print("\n📥 Fetching Supabase products without images...")
    products_without_images = []
    page_size = 1000
    offset = 0
    
    while True:
        response = supabase.client.table('products') \
            .select('id, sku, image_url, name') \
            .eq('tenant_id', tenant_id) \
            .range(offset, offset + page_size - 1) \
            .execute()
        
        if not response.data:
            break
        
        for prod in response.data:
            # Only include products WITHOUT image_url
            if not prod.get('image_url'):
                products_without_images.append(prod)
        
        print(f"   Page {offset // page_size + 1}: {len(response.data)} products")
        
        if len(response.data) < page_size:
            break
        
        offset += page_size
    
    print(f"   ✅ Products without images: {len(products_without_images)}")
    
    # Find matches (Supabase products without image that have Zoho image)
    imports_needed = []
    
    for prod in products_without_images:
        sku = prod.get('sku', '')
        if sku and sku in zoho_by_sku:
            zoho_item = zoho_by_sku[sku]
            imports_needed.append({
                'supabase_id': prod['id'],
                'sku': sku,
                'name': prod.get('name', ''),
                'zoho_item_id': zoho_item['item_id'],
                'image_name': zoho_item['image_name'],
                'image_type': zoho_item['image_type']
            })
    
    print(f"\n📋 PREVIEW: {len(imports_needed)} images to import")
    
    if not imports_needed:
        print("\n✅ All matchable products already have images!")
        return
    
    # Show first 10 as preview
    print("\nFirst 10 imports:")
    for imp in imports_needed[:10]:
        print(f"  • {imp['sku']}: {imp['image_name']}")
    
    if len(imports_needed) > 10:
        print(f"  ... and {len(imports_needed) - 10} more")
    
    # Ask for confirmation
    confirm = input(f"\n🔄 Proceed with {len(imports_needed)} image imports? (yes/no): ").strip().lower()
    
    if confirm != 'yes':
        print("❌ Cancelled")
        return
    
    # Process imports
    print("\n🔄 Downloading from Zoho and uploading to Supabase Storage...")
    success = 0
    failed = 0
    
    for i, imp in enumerate(imports_needed, 1):
        try:
            print(f"  [{i}/{len(imports_needed)}] {imp['sku']}...", end=" ", flush=True)
            
            # Download from Zoho
            image_data = download_image_from_zoho(
                access_token, 
                imp['zoho_item_id'],
                imp['image_name']
            )
            
            if not image_data:
                print("❌ Download failed")
                failed += 1
                continue
            
            # Determine file extension
            ext = imp['image_type'] if imp['image_type'] else 'jpg'
            if ext.lower() == 'jpeg':
                ext = 'jpg'
            
            # Storage path: {tenant_id}/{sku}/{filename}
            safe_image_name = imp['image_name'].replace(' ', '_') if imp['image_name'] else f"image.{ext}"
            storage_path = f"{tenant_id}/{imp['sku']}/{safe_image_name}"
            
            # Upload to Supabase Storage
            content_type = f"image/{ext}"
            
            # Try to upload (upsert mode - will overwrite if exists)
            try:
                supabase.client.storage.from_(BUCKET_NAME).upload(
                    path=storage_path,
                    file=image_data,
                    file_options={"content-type": content_type, "upsert": "true"}
                )
            except Exception as upload_error:
                # If file exists error, try to remove and re-upload
                if "Duplicate" in str(upload_error) or "already exists" in str(upload_error):
                    supabase.client.storage.from_(BUCKET_NAME).remove([storage_path])
                    supabase.client.storage.from_(BUCKET_NAME).upload(
                        path=storage_path,
                        file=image_data,
                        file_options={"content-type": content_type}
                    )
                else:
                    raise upload_error
            
            # Build public URL
            public_url = f"https://xzdvtzdqjeyqxnkqprtf.supabase.co/storage/v1/object/public/{BUCKET_NAME}/{storage_path}"
            
            # Update product with image_url
            supabase.client.table('products') \
                .update({'image_url': public_url}) \
                .eq('id', imp['supabase_id']) \
                .eq('tenant_id', tenant_id) \
                .execute()
            
            print("✅")
            success += 1
            
        except Exception as e:
            print(f"❌ {e}")
            failed += 1
    
    # Summary
    print("\n" + "=" * 80)
    print(f"✅ Imported: {success}")
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
