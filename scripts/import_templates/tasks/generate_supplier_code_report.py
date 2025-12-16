"""
Generate full list of products where código proveedor ≠ SKU
"""
import requests
import csv

# Zoho credentials
CLIENT_ID = "1000.LKVKZREYRMW7ZXKHF8O40ZDZ9XBR0A"
CLIENT_SECRET = "cfc323be8f4cb6190356248b7a24cd12646009afe4"
REFRESH_TOKEN = "1000.0dfaca4f7cece1a32d2e752eb855e2e5.0a5b064b44a904b0ad207c4a3edd2f06"
ZOHO_ORG_ID = "788658742"

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

def main():
    print("Fetching products from Zoho...")
    
    access_token = get_zoho_access_token()
    
    headers = {
        'Authorization': f'Zoho-oauthtoken {access_token}',
        'Content-Type': 'application/json'
    }
    
    different_from_sku = []
    
    page = 1
    while True:
        url = "https://www.zohoapis.com/inventory/v1/items"
        params = {
            'organization_id': ZOHO_ORG_ID,
            'page': page,
            'per_page': 200
        }
        
        response = requests.get(url, headers=headers, params=params)
        data = response.json()
        
        items = data.get('items', [])
        if not items:
            break
        
        for item in items:
            supplier_code = item.get('cf_c_digo_proveedor') or item.get('cf_c_digo_proveedor_unformatted')
            sku = item.get('sku', '')
            
            if supplier_code and str(supplier_code) != str(sku):
                different_from_sku.append({
                    'name': item.get('name', ''),
                    'sku': sku,
                    'codigo_proveedor': supplier_code
                })
        
        page += 1
        if not data.get('page_context', {}).get('has_more_page'):
            break
    
    # Sort by name
    different_from_sku.sort(key=lambda x: x['name'].lower())
    
    # Write CSV
    csv_path = 'supplier_code_report.csv'
    with open(csv_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=['name', 'sku', 'codigo_proveedor'])
        writer.writeheader()
        writer.writerows(different_from_sku)
    
    print(f"\n✅ Saved to {csv_path}")
    print(f"   Total: {len(different_from_sku)} products\n")
    
    # Print markdown table
    print("| Product Name | SKU | Código Proveedor |")
    print("|--------------|-----|------------------|")
    for item in different_from_sku:
        name = item['name'][:50] + "..." if len(item['name']) > 50 else item['name']
        print(f"| {name} | {item['sku']} | {item['codigo_proveedor']} |")

if __name__ == "__main__":
    main()
