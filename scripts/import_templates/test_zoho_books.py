import requests
import time

# Using the access token we just got
ACCESS_TOKEN = "1000.3e8e594b099c3f3480087133f908c1f2.5dda97244ca7bff688ee1c5b24a49f60"
ORG_ID = "788658742"
API_DOMAIN = "https://www.zohoapis.com"

def test_endpoint(endpoint_name, endpoint_path):
    print(f"\n{'='*80}")
    print(f"�� Testing: {endpoint_name}")
    print(f"{'='*80}")
    
    url = f"{API_DOMAIN}/books/v3/{endpoint_path}"
    headers = {
        "Authorization": f"Zoho-oauthtoken {ACCESS_TOKEN}",
    }
    params = {"organization_id": ORG_ID}
    
    try:
        response = requests.get(url, headers=headers, params=params)
        print(f"Status: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Success!")
            
            # Print summary based on endpoint
            if 'invoices' in data:
                print(f"   📄 Found {len(data['invoices'])} invoices")
                if data['invoices']:
                    inv = data['invoices'][0]
                    print(f"   Sample: {inv.get('invoice_number')} - ${inv.get('total')} - {inv.get('customer_name')}")
            elif 'bills' in data:
                print(f"   📄 Found {len(data['bills'])} bills")
                if data['bills']:
                    bill = data['bills'][0]
                    print(f"   Sample: {bill.get('bill_number')} - ${bill.get('total')} - {bill.get('vendor_name')}")
            elif 'journalentries' in data:
                print(f"   📄 Found {len(data['journalentries'])} journal entries")
                if data['journalentries']:
                    je = data['journalentries'][0]
                    print(f"   Sample: {je.get('entry_number')} - ${je.get('total')} - {je.get('reference_number')}")
            elif 'expenses' in data:
                print(f"   📄 Found {len(data['expenses'])} expenses")
                if data['expenses']:
                    exp = data['expenses'][0]
                    print(f"   Sample: ${exp.get('total')} - {exp.get('account_name')}")
            else:
                print(f"   Response keys: {list(data.keys())}")
                
        else:
            print(f"❌ Error: {response.status_code}")
            print(f"   {response.text}")
            
    except Exception as e:
        print(f"❌ Exception: {e}")

# Test all endpoints
print("\n" + "="*80)
print("🧾 TESTING ZOHO BOOKS API ACCESS")
print("="*80)
print(f"Organization ID: {ORG_ID}")
print(f"API Domain: {API_DOMAIN}")

test_endpoint("Sales Invoices", "invoices")
test_endpoint("Purchase Bills", "bills")
test_endpoint("Journal Entries", "journalentries")
test_endpoint("Expenses", "expenses")

print("\n" + "="*80)
print("✅ TESTING COMPLETE")
print("="*80)
