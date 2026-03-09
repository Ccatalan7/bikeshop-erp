"""
Check what fields Zoho actually returns for items, including vendor/supplier info.
Fetch 1 item from the LIST api and 1 from the DETAIL api to compare.
"""
import requests
import json

ZOHO_CLIENT_ID = "1000.HEUWHSDCUE4GAN7CL3P045ICRU5V5B"
ZOHO_CLIENT_SECRET = "ffd0bc79a8e2456cef492010e34c3653a55d82be43"
ZOHO_REFRESH_TOKEN = "1000.1018c69651f1ca381b062c385a218e1d.72eb1094dbf04d5f018adee06494e3d1"
ZOHO_ORG_ID = "788658742"
ZOHO_API_DOMAIN = "https://www.zohoapis.com"
ZOHO_OAUTH_DOMAIN = "https://accounts.zoho.com"

# Get token
token_url = f"{ZOHO_OAUTH_DOMAIN}/oauth/v2/token"
params = {'refresh_token': ZOHO_REFRESH_TOKEN, 'client_id': ZOHO_CLIENT_ID, 'client_secret': ZOHO_CLIENT_SECRET, 'grant_type': 'refresh_token'}
access_token = requests.post(token_url, params=params).json()['access_token']
headers = {'Authorization': f'Zoho-oauthtoken {access_token}'}

# 1. Fetch first page of items from LIST endpoint
print("=" * 80)
print("LIST API - First 2 items (all fields)")
print("=" * 80)
resp = requests.get(f"{ZOHO_API_DOMAIN}/inventory/v1/items", headers=headers, params={'organization_id': ZOHO_ORG_ID, 'per_page': 2}).json()
items = resp.get('items', [])
for item in items[:2]:
    print(f"\nItem: {item.get('name')} (SKU: {item.get('sku')})")
    print(f"All keys: {list(item.keys())}")
    # Print vendor-related fields
    for k, v in item.items():
        if 'vendor' in k.lower() or 'supplier' in k.lower() or 'brand' in k.lower() or 'contact' in k.lower():
            print(f"  ** {k}: {v}")

# 2. Fetch one item from DETAIL endpoint
if items:
    item_id = items[0].get('item_id')
    print(f"\n{'='*80}")
    print(f"DETAIL API - Item {item_id}")
    print(f"{'='*80}")
    detail = requests.get(f"{ZOHO_API_DOMAIN}/inventory/v1/items/{item_id}", headers=headers, params={'organization_id': ZOHO_ORG_ID}).json()
    item_detail = detail.get('item', {})
    print(f"All keys: {list(item_detail.keys())}")
    for k, v in item_detail.items():
        if 'vendor' in k.lower() or 'supplier' in k.lower() or 'brand' in k.lower() or 'contact' in k.lower() or 'purchase' in k.lower():
            print(f"  ** {k}: {json.dumps(v, ensure_ascii=False)[:200]}")
