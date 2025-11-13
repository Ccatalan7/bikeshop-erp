"""
📇 IMPORT ZOHO BOOKS CONTACTS TO SUPABASE
==========================================
Imports customers and vendors from Zoho Books contacts API
"""

import time
import requests
from typing import Optional
try:
    import config
    from supabase import create_client, Client
except ImportError as e:
    print(f"❌ Missing dependency: {e}")
    print("Install: pip3 install supabase requests python-dateutil")
    exit(1)

# ============================================================================
# CONFIGURATION
# ============================================================================
SUPABASE_URL = config.SUPABASE_URL
SUPABASE_KEY = config.SUPABASE_SERVICE_ROLE_KEY
TENANT_ID = config.TENANT_ID

ZOHO_CLIENT_ID = config.ZOHO_CLIENT_ID
ZOHO_CLIENT_SECRET = config.ZOHO_CLIENT_SECRET
ZOHO_REFRESH_TOKEN = config.ZOHO_REFRESH_TOKEN
ZOHO_ORG_ID = config.ZOHO_ORG_ID
ZOHO_API_DOMAIN = config.ZOHO_API_DOMAIN

# Global Supabase client
supabase: Optional[Client] = None

# OAuth token cache
ACCESS_TOKEN = None
TOKEN_EXPIRES_AT = 0

# ============================================================================
# ZOHO OAUTH & API HELPERS
# ============================================================================

def get_access_token() -> str:
    """Get or refresh Zoho access token"""
    global ACCESS_TOKEN, TOKEN_EXPIRES_AT
    
    if ACCESS_TOKEN and time.time() < TOKEN_EXPIRES_AT:
        return ACCESS_TOKEN
    
    print("🔄 Refreshing Zoho access token...")
    
    response = requests.post(
        "https://accounts.zoho.com/oauth/v2/token",
        data={
            "refresh_token": ZOHO_REFRESH_TOKEN,
            "client_id": ZOHO_CLIENT_ID,
            "client_secret": ZOHO_CLIENT_SECRET,
            "grant_type": "refresh_token",
        }
    )
    
    if response.status_code != 200:
        raise Exception(f"Failed to refresh token: {response.text}")
    
    data = response.json()
    ACCESS_TOKEN = data["access_token"]
    TOKEN_EXPIRES_AT = time.time() + data["expires_in"] - 300  # 5min buffer
    
    print("✅ Token refreshed")
    return ACCESS_TOKEN

def zoho_get(endpoint: str, params: dict = None) -> dict:
    """Make authenticated GET request to Zoho Books API"""
    token = get_access_token()
    url = f"{ZOHO_API_DOMAIN}/books/v3/{endpoint}"
    
    headers = {"Authorization": f"Zoho-oauthtoken {token}"}
    params = params or {}
    params["organization_id"] = ZOHO_ORG_ID
    
    response = requests.get(url, headers=headers, params=params)
    
    if response.status_code != 200:
        raise Exception(f"Zoho API error: {response.status_code} - {response.text}")
    
    return response.json()

def fetch_all_contacts() -> list:
    """Fetch all contacts with pagination"""
    all_contacts = []
    page = 1
    
    while True:
        print(f"  📄 Fetching page {page}...")
        response = zoho_get("contacts", {"page": page, "per_page": 200})
        
        contacts = response.get("contacts", [])
        if not contacts:
            break
        
        all_contacts.extend(contacts)
        
        page_context = response.get("page_context", {})
        if not page_context.get("has_more_page", False):
            break
        
        page += 1
    
    print(f"  ✅ Fetched {len(all_contacts)} contact(s) across {page} page(s)")
    return all_contacts

# ============================================================================
# DATA TRANSFORMATION
# ============================================================================

def transform_contact_to_customer(zoho_contact: dict) -> dict:
    """Transform Zoho contact to Supabase customer format
    
    Supabase customers columns: id, name, rut, email, phone, address, city, 
    notes, created_at, region, is_active, image_url, updated_at, auth_user_id, tenant_id
    
    Zoho contact fields: contact_name, email, phone, mobile, company_name, etc.
    """
    # Zoho doesn't provide address/city in the list view, only in detail view
    # We'll populate what we can from the list data
    notes_parts = []
    if zoho_contact.get("contact_id"):
        notes_parts.append(f"Zoho ID: {zoho_contact['contact_id']}")
    if zoho_contact.get("company_name"):
        notes_parts.append(f"Company: {zoho_contact['company_name']}")
    
    return {
        "tenant_id": TENANT_ID,
        "name": zoho_contact.get("contact_name", ""),
        "email": zoho_contact.get("email") or None,
        "phone": zoho_contact.get("phone") or zoho_contact.get("mobile") or None,
        "rut": None,  # Zoho doesn't have tax_id in list view
        "address": None,  # Not in list view
        "city": None,  # Not in list view
        "region": None,  # Not in list view
        "notes": "\n".join(notes_parts) if notes_parts else None,
        "is_active": zoho_contact.get("status") == "active",
    }

def transform_contact_to_supplier(zoho_contact: dict) -> dict:
    """Transform Zoho contact to Supabase supplier format
    
    Supabase suppliers columns: id, name, rut, email, phone, address, created_at, 
    city, region, comuna, contact_person, website, payment_terms, notes, is_active, 
    updated_at, bank_details, type, tenant_id, default_tax_treatment
    
    Zoho contact fields: contact_name, email, phone, mobile, website, company_name, etc.
    """
    notes_parts = []
    if zoho_contact.get("contact_id"):
        notes_parts.append(f"Zoho ID: {zoho_contact['contact_id']}")
    if zoho_contact.get("company_name"):
        notes_parts.append(f"Company: {zoho_contact['company_name']}")
    
    # Map payment terms (Zoho uses days, we use text labels)
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
        "rut": None,  # Not in list view
        "address": None,  # Not in list view
        "city": None,  # Not in list view
        "region": None,  # Not in list view
        "website": zoho_contact.get("website") or None,
        "payment_terms": payment_terms,
        "notes": "\n".join(notes_parts) if notes_parts else None,
        "is_active": zoho_contact.get("status") == "active",
        "default_tax_treatment": "tax_included",  # ✅ Fixed: use 'tax_included' not 'taxIncluded'
    }

# ============================================================================
# IMPORT FUNCTIONS
# ============================================================================

def import_customers(contacts: list):
    """Import contacts marked as customers"""
    print("\n" + "="*80)
    print("📥 IMPORTING CUSTOMERS")
    print("="*80)
    
    # Filter customer contacts
    customer_contacts = [c for c in contacts if c.get("contact_type") == "customer"]
    print(f"  📊 Found {len(customer_contacts)} customer contacts")
    
    imported = 0
    skipped = 0
    errors = 0
    
    for contact in customer_contacts:
        try:
            name = contact.get("contact_name", "").strip()
            if not name:
                skipped += 1
                continue
            
            # Check if customer already exists
            existing = supabase.table("customers").select("id").eq("tenant_id", TENANT_ID).eq("name", name).limit(1).execute()
            
            if existing.data:
                print(f"  ⏭️  Skipped: {name} (already exists)")
                skipped += 1
                continue
            
            # Transform and insert
            customer_data = transform_contact_to_customer(contact)
            supabase.table("customers").insert(customer_data).execute()
            
            print(f"  ✅ Imported: {name}")
            imported += 1
            
        except Exception as e:
            print(f"  ❌ Error importing {contact.get('contact_name')}: {e}")
            errors += 1
    
    print(f"\n✅ Imported: {imported}")
    print(f"⏭️  Skipped: {skipped} (already exist)")
    print(f"❌ Errors: {errors}")

def import_suppliers(contacts: list):
    """Import contacts marked as vendors"""
    print("\n" + "="*80)
    print("📥 IMPORTING SUPPLIERS")
    print("="*80)
    
    # Filter vendor contacts
    vendor_contacts = [c for c in contacts if c.get("contact_type") == "vendor"]
    print(f"  📊 Found {len(vendor_contacts)} vendor contacts")
    
    imported = 0
    skipped = 0
    errors = 0
    
    for contact in vendor_contacts:
        try:
            name = contact.get("contact_name", "").strip()
            if not name:
                skipped += 1
                continue
            
            # Check if supplier already exists
            existing = supabase.table("suppliers").select("id").eq("tenant_id", TENANT_ID).eq("name", name).limit(1).execute()
            
            if existing.data:
                print(f"  ⏭️  Skipped: {name} (already exists)")
                skipped += 1
                continue
            
            # Transform and insert
            supplier_data = transform_contact_to_supplier(contact)
            supabase.table("suppliers").insert(supplier_data).execute()
            
            print(f"  ✅ Imported: {name}")
            imported += 1
            
        except Exception as e:
            print(f"  ❌ Error importing {contact.get('contact_name')}: {e}")
            errors += 1
    
    print(f"\n✅ Imported: {imported}")
    print(f"⏭️  Skipped: {skipped} (already exist)")
    print(f"❌ Errors: {errors}")

# ============================================================================
# MAIN
# ============================================================================

def main():
    global supabase
    
    print("\n" + "="*80)
    print("📇 ZOHO BOOKS CONTACTS IMPORT")
    print("="*80)
    print(f"📍 Tenant ID: {TENANT_ID[:8]}...")
    print(f"🏢 Organization ID: {ZOHO_ORG_ID}")
    print("="*80)
    
    # Initialize Supabase
    try:
        supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
        
        # Verify tenant exists
        tenant_result = supabase.table("tenants").select("shop_name").eq("id", TENANT_ID).single().execute()
        print(f"✅ Connected to tenant: {tenant_result.data['shop_name']}")
    except Exception as e:
        print(f"❌ Supabase connection failed: {e}")
        return
    
    # Test Zoho authentication
    try:
        get_access_token()
        print("✅ Zoho Books authentication successful")
    except Exception as e:
        print(f"❌ Zoho authentication failed: {e}")
        return
    
    # Fetch all contacts
    print("\n" + "="*80)
    print("📇 FETCHING CONTACTS FROM ZOHO BOOKS")
    print("="*80)
    
    try:
        contacts = fetch_all_contacts()
    except Exception as e:
        print(f"❌ Failed to fetch contacts: {e}")
        return
    
    # Import customers
    import_customers(contacts)
    
    # Import suppliers
    import_suppliers(contacts)
    
    print("\n" + "="*80)
    print("✅ IMPORT COMPLETED SUCCESSFULLY")
    print("="*80)
    print("💡 Check your Flutter app to verify imported contacts")

if __name__ == "__main__":
    main()
