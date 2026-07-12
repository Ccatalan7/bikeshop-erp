"""
Retry failed image imports with sanitized filenames
These 11 images failed due to special characters: ñ, ~, [], etc.
"""

import os
import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))

import requests
import re
import unicodedata
from connections.supabase_connection import SupabaseConnection

# Zoho credentials
CLIENT_ID = os.environ.get("ZOHO_CLIENT_ID", "")
CLIENT_SECRET = os.environ.get("ZOHO_CLIENT_SECRET", "")
REFRESH_TOKEN = os.environ.get("ZOHO_REFRESH_TOKEN", "")
ZOHO_ORG_ID = "788658742"

BUCKET_NAME = "vinabike-assets"

# These SKUs failed
FAILED_SKUS = [
    "NNV63",  # Horquilla_Suntour_29[P]_Xcm_Rl_Negra_Mate_Disco.jpg
    "NNV56",  # Freno_Hidráulico_Delantero_Tanke_4_Pistones_Morado_Metálico_.jpg
    "9274",   # e4d616_33fa13ea3d1e47cd8912be5c26b19dd9~mv2.jpeg
    "AE0218", # Puños_Goma_con_Bloqueo_en_un_solo_lado_.jpg
    "M004",   # Logo_Viñabike.jpg
    "M003",   # Logo_Viñabike.jpg
    "AE0208", # Válvula_Francesa_Tubular_Deemount_40_mm_Roja.jpg
    "7683",   # e4d616_0051ff1deec94dd2bd0761109bfe85b4~mv2.jpg
    "23140",  # Piñón_Radius_FW-8SI-GT_8_Vel_Atornillado_14-34T.png
    "AE0226", # Puños_Enlee_Morados_.jpg
    "AE0211", # Tija_Sillín_Carbono_27.2_-_400mm_Toseek.jpg
]


def sanitize_filename(filename):
    """Remove/replace special characters that Supabase doesn't like"""
    # Normalize unicode (ñ → n, á → a, etc.)
    filename = unicodedata.normalize('NFKD', filename)
    filename = filename.encode('ascii', 'ignore').decode('ascii')
    
    # Remove brackets, tildes, and other problematic chars
    filename = re.sub(r'[\[\]~]', '', filename)
    
    # Replace multiple underscores with single
    filename = re.sub(r'_+', '_', filename)
    
    # Remove leading/trailing underscores
    filename = filename.strip('_')
    
    return filename


def get_zoho_access_token():
    token_url = "https://accounts.zoho.com/oauth/v2/token"
    payload = {
        'grant_type': 'refresh_token',
        'client_id': CLIENT_ID,
        'client_secret': CLIENT_SECRET,
        'refresh_token': REFRESH_TOKEN
    }
    response = requests.post(token_url, params=payload)
    return response.json()['access_token']


def download_image_from_zoho(access_token, item_id):
    headers = {'Authorization': f'Zoho-oauthtoken {access_token}'}
    url = f"https://www.zohoapis.com/inventory/v1/items/{item_id}/image"
    params = {'organization_id': ZOHO_ORG_ID}
    
    response = requests.get(url, headers=headers, params=params)
    if response.status_code == 200:
        return response.content
    return None


def main():
    print("\n" + "=" * 80)
    print("🔄 RETRY FAILED IMAGE IMPORTS (with sanitized filenames)")
    print("=" * 80)
    
    access_token = get_zoho_access_token()
    print("✅ Got Zoho access token")
    
    # Get Zoho products for failed SKUs
    headers = {
        'Authorization': f'Zoho-oauthtoken {access_token}',
        'Content-Type': 'application/json'
    }
    
    # Fetch all Zoho products to find the failed ones
    print("\n📥 Fetching product info from Zoho...")
    zoho_products = {}
    page = 1
    while True:
        url = "https://www.zohoapis.com/inventory/v1/items"
        params = {'organization_id': ZOHO_ORG_ID, 'page': page, 'per_page': 200}
        response = requests.get(url, headers=headers, params=params)
        data = response.json()
        
        items = data.get('items', [])
        if not items:
            break
        
        for item in items:
            sku = item.get('sku', '')
            if sku in FAILED_SKUS and item.get('image_document_id'):
                zoho_products[sku] = {
                    'item_id': item['item_id'],
                    'image_name': item.get('image_name', 'image.jpg'),
                    'image_type': item.get('image_type', 'jpg')
                }
        
        page += 1
        if not data.get('page_context', {}).get('has_more_page'):
            break
    
    print(f"   Found {len(zoho_products)} products to retry\n")
    
    # Connect to Supabase
    supabase = SupabaseConnection()
    tenant_id = supabase.tenant_id
    
    # Get Supabase product IDs
    supabase_products = {}
    for sku in FAILED_SKUS:
        response = supabase.client.table('products') \
            .select('id') \
            .eq('sku', sku) \
            .eq('tenant_id', tenant_id) \
            .execute()
        if response.data:
            supabase_products[sku] = response.data[0]['id']
    
    # Process each failed product
    success = 0
    failed = 0
    
    for sku in FAILED_SKUS:
        if sku not in zoho_products or sku not in supabase_products:
            print(f"  ⚠️ {sku}: Not found in both systems")
            continue
        
        zoho_item = zoho_products[sku]
        supabase_id = supabase_products[sku]
        
        print(f"  [{sku}]...", end=" ", flush=True)
        
        try:
            # Download from Zoho
            image_data = download_image_from_zoho(access_token, zoho_item['item_id'])
            if not image_data:
                print("❌ Download failed")
                failed += 1
                continue
            
            # Sanitize filename
            ext = zoho_item['image_type'] if zoho_item['image_type'] else 'jpg'
            original_name = zoho_item['image_name']
            sanitized_name = sanitize_filename(original_name)
            
            # Ensure it has extension
            if not sanitized_name.lower().endswith(('.jpg', '.jpeg', '.png', '.gif', '.webp')):
                sanitized_name = f"{sanitized_name}.{ext}"
            
            print(f"({original_name} → {sanitized_name})", end=" ", flush=True)
            
            # Storage path
            storage_path = f"{tenant_id}/{sku}/{sanitized_name}"
            content_type = f"image/{ext}"
            
            # Upload
            try:
                supabase.client.storage.from_(BUCKET_NAME).upload(
                    path=storage_path,
                    file=image_data,
                    file_options={"content-type": content_type, "upsert": "true"}
                )
            except Exception as e:
                if "Duplicate" in str(e) or "already exists" in str(e):
                    supabase.client.storage.from_(BUCKET_NAME).remove([storage_path])
                    supabase.client.storage.from_(BUCKET_NAME).upload(
                        path=storage_path,
                        file=image_data,
                        file_options={"content-type": content_type}
                    )
                else:
                    raise e
            
            # Build URL and update product
            public_url = f"https://xzdvtzdqjeyqxnkqprtf.supabase.co/storage/v1/object/public/{BUCKET_NAME}/{storage_path}"
            
            supabase.client.table('products') \
                .update({'image_url': public_url}) \
                .eq('id', supabase_id) \
                .eq('tenant_id', tenant_id) \
                .execute()
            
            print("✅")
            success += 1
            
        except Exception as e:
            print(f"❌ {e}")
            failed += 1
    
    print("\n" + "=" * 80)
    print(f"✅ Imported: {success}")
    print(f"❌ Failed: {failed}")
    print("=" * 80)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n⚠️ Cancelled")
    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
