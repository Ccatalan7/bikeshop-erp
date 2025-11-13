import requests

ACCESS_TOKEN = "1000.f52c587ba2e5dd55a4d6f98044d03831.707e9e3b466055e8370f2f172f263ba1"
ORG_ID = "788658742"
API_DOMAIN = "https://www.zohoapis.com"

print("="*80)
print("📊 COUNTING ZOHO BOOKS CONTACTS")
print("="*80)

# Fetch all contacts with pagination
all_contacts = []
page = 1
total_pages = 0

while True:
    print(f"📄 Fetching page {page}...")
    url = f"{API_DOMAIN}/books/v3/contacts"
    headers = {"Authorization": f"Zoho-oauthtoken {ACCESS_TOKEN}"}
    params = {"organization_id": ORG_ID, "per_page": 200, "page": page}
    
    response = requests.get(url, headers=headers, params=params)
    
    if response.status_code != 200:
        print(f"❌ Error: {response.status_code}")
        break
    
    data = response.json()
    contacts = data.get('contacts', [])
    
    if not contacts:
        break
    
    all_contacts.extend(contacts)
    
    page_context = data.get('page_context', {})
    has_more = page_context.get('has_more_page', False)
    
    if not has_more:
        break
    
    page += 1

total_pages = page

# Count by type
customers = [c for c in all_contacts if c.get('contact_type') == 'customer']
vendors = [c for c in all_contacts if c.get('contact_type') == 'vendor']
both = [c for c in all_contacts if c.get('contact_type') not in ['customer', 'vendor']]

print("\n" + "="*80)
print("📊 CONTACT SUMMARY")
print("="*80)
print(f"📇 Total Contacts: {len(all_contacts)}")
print(f"📄 Total Pages: {total_pages}")
print(f"\n👥 Customers: {len(customers)}")
print(f"🏭 Vendors: {len(vendors)}")
print(f"❓ Other/Both: {len(both)}")
print("="*80)
