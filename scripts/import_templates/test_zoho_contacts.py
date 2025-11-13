import requests

ACCESS_TOKEN = "1000.f52c587ba2e5dd55a4d6f98044d03831.707e9e3b466055e8370f2f172f263ba1"
ORG_ID = "788658742"
API_DOMAIN = "https://www.zohoapis.com"

print("="*80)
print("📇 TESTING ZOHO BOOKS CONTACTS API")
print("="*80)

# Test contacts endpoint
url = f"{API_DOMAIN}/books/v3/contacts"
headers = {"Authorization": f"Zoho-oauthtoken {ACCESS_TOKEN}"}
params = {"organization_id": ORG_ID, "per_page": 200}

response = requests.get(url, headers=headers, params=params)
print(f"Status: {response.status_code}")

if response.status_code == 200:
    data = response.json()
    contacts = data.get('contacts', [])
    
    print(f"✅ Found {len(contacts)} contacts")
    print(f"   Total contacts: {data.get('page_context', {}).get('total', 'unknown')}")
    
    if contacts:
        print(f"\n📋 SAMPLE CONTACTS (first 5):")
        for i, contact in enumerate(contacts[:5], 1):
            print(f"\n   {i}. {contact.get('contact_name')}")
            print(f"      Type: {contact.get('contact_type')} (customer={contact.get('is_customer')}, vendor={contact.get('is_vendor')})")
            print(f"      Email: {contact.get('email')}")
            print(f"      Phone: {contact.get('phone')}")
            print(f"      Company: {contact.get('company_name', 'N/A')}")
            print(f"      Balance: ${contact.get('outstanding_receivable_amount', 0)}")
else:
    print(f"❌ Error: {response.status_code}")
    print(response.text)

print("\n" + "="*80)
