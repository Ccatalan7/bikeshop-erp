import requests
import json

ACCESS_TOKEN = "1000.f52c587ba2e5dd55a4d6f98044d03831.707e9e3b466055e8370f2f172f263ba1"
ORG_ID = "788658742"
API_DOMAIN = "https://www.zohoapis.com"

url = f"{API_DOMAIN}/books/v3/contacts"
headers = {"Authorization": f"Zoho-oauthtoken {ACCESS_TOKEN}"}
params = {"organization_id": ORG_ID, "per_page": 1}

response = requests.get(url, headers=headers, params=params)
data = response.json()

if data.get("contacts"):
    contact = data["contacts"][0]
    print("="*80)
    print("📋 SAMPLE ZOHO CONTACT STRUCTURE")
    print("="*80)
    print(json.dumps(contact, indent=2))
