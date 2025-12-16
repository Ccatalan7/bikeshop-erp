
import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))
from connections.zoho_connection import ZohoConnection
from connections.supabase_connection import SupabaseConnection
import requests

def download_and_upload_image(image_url, sku, supabase, zoho_token):
    """Download image from Zoho and upload to Supabase Storage"""
    try:
        headers = {'Authorization': f'Zoho-oauthtoken {zoho_token}'}
        resp = requests.get(image_url, headers=headers, timeout=30, allow_redirects=True)
        if resp.status_code != 200:
            return None
        content_type = resp.headers.get('content-type', 'image/jpeg')
        if 'png' in content_type:
            ext = 'png'
        elif 'webp' in content_type:
            ext = 'webp'
        else:
            ext = 'jpg'
        storage_path = f"{supabase.tenant_id}/{sku}/main.{ext}"
        file_options = {'content_type': content_type, 'upsert': True}
        bucket = supabase.client.storage.from('products')
        bucket.upload(path=storage_path, file=resp.content, file_options=file_options)
        public_url = bucket.get_public_url(storage_path)
        return public_url
    except Exception as e:
        print(f"      ❌ Download/upload error: {str(e)[:80]}")
        return None

def main():
    print('Supplier codes import script ready')

if __name__ == '__main__':
    main()
