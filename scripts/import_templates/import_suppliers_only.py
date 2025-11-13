"""
📇 IMPORT ONLY SUPPLIERS FROM ZOHO BOOKS
=========================================
"""

import time
import requests
try:
    import config
    from supabase import create_client, Client
except ImportError as e:
    print(f"❌ Missing dependency: {e}")
    exit(1)

# Config
SUPABASE_URL = config.SUPABASE_URL
SUPABASE_KEY = config.SUPABASE_SERVICE_ROLE_KEY
TENANT_ID = config.TENANT_ID
ZOHO_CLIENT_ID = config.ZOHO_CLIENT_ID
ZOHO_CLIENT_SECRET = config.ZOHO_CLIENT_SECRET
ZOHO_REFRESH_TOKEN = config.ZOHO_REFRESH_TOKEN
ZOHO_ORG_ID = config.ZOHO_ORG_ID
ZOHO_API_DOMAIN = config.ZOHO_API_DOMAIN

supabase = None
ACCESS_TOKEN = None
TOKEN_EXPIRES_AT = 0

def get_access_token() -> str:
    global ACCESS_TOKEN, TOKEN_EXPIRES_AT
    if ACCESS_TOKEN and time.time() < TOKEN_EXPIRES_AT:
        return ACCESS_TOKEN
    
    print("🔄 Refreshing token...")
    response = requests.post(
        "https://accounts.zoho.com/oauth/v2/token",
        data={
            "refresh_token": ZOHO_REFRESH_TOKEN,
            "client_id": ZOHO_CLIENT_ID,
            "client_secret": ZOHO_CLIENT_SECRET,
            "grant_type": "refresh_token",
        }
    )
    data = response.json()
    ACCESS_TOKEN = data["access_token"]
    TOKEN_EXPIRES_AT = time.time() + data["expires_in"] - 300
    print("✅ Token refreshed")
    return ACCESS_TOKEN

def fetch_vendor_contacts() -> list:
    """Fetch only vendor contacts"""
    all_vendors = []
    page = 1
    
    while True:
        print(f"  📄 Fetching page {page}...")
        token = get_access_token()
        url = f"{ZOHO_API_DOMAIN}/books/v3/contacts"
        headers = {"Authorization": f"Zoho-oauthtoken {token}"}
        params = {"organization_id": ZOHO_ORG_ID, "page": page, "per_page": 200}
        
        response = requests.get(url, headers=headers, params=params)
        data = response.json()
        contacts = data.get("contacts", [])
        
        if not contacts:
            break
        
        # Filter only vendors
        vendors = [c for c in contacts if c.get("contact_type") == "vendor"]
        all_vendors.extend(vendors)
        
        if not data.get("page_context", {}).get("has_more_page", False):
            break
        
        page += 1
    
    print(f"  ✅ Found {len(all_vendors)} vendor(s)")
    return all_vendors

def transform_to_supplier(zoho_contact: dict) -> dict:
    notes_parts = []
    if zoho_contact.get("contact_id"):
        notes_parts.append(f"Zoho ID: {zoho_contact['contact_id']}")
    if zoho_contact.get("company_name"):
        notes_parts.append(f"Company: {zoho_contact['company_name']}")
    
    payment_days = zoho_contact.get("payment_terms", 0)
    if payment_days == 0:
        payment_terms = "prepaid"
    elif payment_days <= 15:
        payment_terms = "net15"
    elif payment_days <= 30:
        payment_terms = "net30"
    else:
        payment_terms = "net60"
    
    return {
        "tenant_id": TENANT_ID,
        "name": zoho_contact.get("contact_name", ""),
        "email": zoho_contact.get("email") or None,
        "phone": zoho_contact.get("phone") or zoho_contact.get("mobile") or None,
        "rut": None,
        "address": None,
        "city": None,
        "region": None,
        "website": zoho_contact.get("website") or None,
        "payment_terms": payment_terms,
        "notes": "\n".join(notes_parts) if notes_parts else None,
        "is_active": zoho_contact.get("status") == "active",
        "default_tax_treatment": "tax_included",
    }

def main():
    global supabase
    
    print("\n" + "="*80)
    print("🏭 IMPORTING SUPPLIERS ONLY")
    print("="*80)
    
    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
    
    # Fetch vendors
    print("\n📇 Fetching vendors from Zoho...")
    vendors = fetch_vendor_contacts()
    
    # Import
    print(f"\n📥 Importing {len(vendors)} suppliers...")
    imported = 0
    skipped = 0
    errors = 0
    
    for vendor in vendors:
        try:
            name = vendor.get("contact_name", "").strip()
            if not name:
                skipped += 1
                continue
            
            # Check if exists
            existing = supabase.table("suppliers").select("id").eq("tenant_id", TENANT_ID).eq("name", name).limit(1).execute()
            
            if existing.data:
                print(f"  ⏭️  Skipped: {name}")
                skipped += 1
                continue
            
            # Insert
            supplier_data = transform_to_supplier(vendor)
            supabase.table("suppliers").insert(supplier_data).execute()
            
            print(f"  ✅ Imported: {name}")
            imported += 1
            
        except Exception as e:
            print(f"  ❌ Error importing {vendor.get('contact_name')}: {e}")
            errors += 1
    
    print("\n" + "="*80)
    print(f"✅ Imported: {imported}")
    print(f"⏭️  Skipped: {skipped}")
    print(f"❌ Errors: {errors}")
    print("="*80)

if __name__ == "__main__":
    main()
