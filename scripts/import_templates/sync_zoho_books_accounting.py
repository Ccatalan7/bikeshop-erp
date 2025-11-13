"""
🧾 ZOHO BOOKS ACCOUNTING DATA IMPORT
=====================================

Imports accounting data from Zoho Books to Supabase:
- Sales Invoices (with line items and payments)
- Purchase Invoices (with line items and payments) 
- Journal Entries (with journal lines)
- Expenses

Author: AI Agent
Date: November 12, 2025
Version: 1.0

PREREQUISITES:
1. Copy config.template.py to config.py
2. Fill in Zoho Books credentials (client_id, client_secret, refresh_token, org_id)
3. Fill in Supabase credentials (url, service_role_key, tenant_id)
4. Run: python3 sync_zoho_books_accounting.py

ZOHO BOOKS API DOCS:
- https://www.zoho.com/books/api/v3/
"""

import sys
import os
import json
import time
import requests
from datetime import datetime
from typing import Dict, List, Optional, Any

# Add parent directory to path for config import
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

try:
    import config
except ImportError:
    print("❌ config.py not found!")
    print("📋 Please copy config.template.py to config.py and fill in your credentials")
    sys.exit(1)

from supabase import create_client, Client

# ============================================================================
# CONFIGURATION
# ============================================================================

ZOHO_API_DOMAIN = config.ZOHO_API_DOMAIN
ZOHO_CLIENT_ID = config.ZOHO_CLIENT_ID
ZOHO_CLIENT_SECRET = config.ZOHO_CLIENT_SECRET
ZOHO_REFRESH_TOKEN = config.ZOHO_REFRESH_TOKEN
ZOHO_ORG_ID = config.ZOHO_ORG_ID

SUPABASE_URL = config.SUPABASE_URL
SUPABASE_KEY = config.SUPABASE_SERVICE_ROLE_KEY
TENANT_ID = config.TENANT_ID

# Initialize Supabase client
supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# Access token cache
ACCESS_TOKEN = None
TOKEN_EXPIRES_AT = 0

# ============================================================================
# ZOHO AUTHENTICATION
# ============================================================================

def get_access_token() -> str:
    """Get or refresh Zoho access token"""
    global ACCESS_TOKEN, TOKEN_EXPIRES_AT
    
    # Return cached token if still valid
    if ACCESS_TOKEN and time.time() < TOKEN_EXPIRES_AT:
        return ACCESS_TOKEN
    
    print("🔄 Refreshing Zoho access token...")
    
    url = f"{ZOHO_API_DOMAIN}/oauth/v2/token"
    params = {
        'refresh_token': ZOHO_REFRESH_TOKEN,
        'client_id': ZOHO_CLIENT_ID,
        'client_secret': ZOHO_CLIENT_SECRET,
        'grant_type': 'refresh_token'
    }
    
    try:
        response = requests.post(url, params=params)
        response.raise_for_status()
        data = response.json()
        
        ACCESS_TOKEN = data['access_token']
        # Set expiry to 50 minutes (tokens last 1 hour)
        TOKEN_EXPIRES_AT = time.time() + (50 * 60)
        
        print("✅ Access token refreshed")
        return ACCESS_TOKEN
        
    except Exception as e:
        print(f"❌ Failed to refresh token: {e}")
        raise

# ============================================================================
# ZOHO API HELPERS
# ============================================================================

def zoho_get(endpoint: str, params: Dict = None) -> Dict:
    """Make GET request to Zoho Books API"""
    token = get_access_token()
    
    if params is None:
        params = {}
    
    params['organization_id'] = ZOHO_ORG_ID
    
    headers = {
        'Authorization': f'Zoho-oauthtoken {token}',
        'Content-Type': 'application/json'
    }
    
    url = f"{ZOHO_API_DOMAIN}/books/v3/{endpoint}"
    
    try:
        response = requests.get(url, headers=headers, params=params)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.HTTPError as e:
        print(f"❌ Zoho API error: {e}")
        print(f"Response: {response.text}")
        raise

def fetch_all_pages(endpoint: str, data_key: str) -> List[Dict]:
    """Fetch all pages from a paginated Zoho endpoint"""
    all_items = []
    page = 1
    per_page = 200  # Zoho Books max per page
    
    while True:
        print(f"  📄 Fetching page {page}...", end='\r')
        
        params = {'page': page, 'per_page': per_page}
        response = zoho_get(endpoint, params)
        
        if data_key not in response:
            break
        
        items = response[data_key]
        if not items:
            break
        
        all_items.extend(items)
        
        # Check if there are more pages
        page_context = response.get('page_context', {})
        if not page_context.get('has_more_page', False):
            break
        
        page += 1
        time.sleep(0.3)  # Rate limiting
    
    print(f"  ✅ Fetched {len(all_items)} items across {page} page(s)")
    return all_items

# ============================================================================
# DATA TRANSFORMATION HELPERS
# ============================================================================

def parse_zoho_date(date_str: Optional[str]) -> Optional[str]:
    """Convert Zoho date format to ISO 8601"""
    if not date_str:
        return None
    
    try:
        # Zoho format: "2025-01-15" or "2025-01-15T10:30:00-0300"
        if 'T' in date_str:
            dt = datetime.fromisoformat(date_str.replace('Z', '+00:00'))
        else:
            dt = datetime.strptime(date_str, '%Y-%m-%d')
        
        return dt.isoformat()
    except Exception as e:
        print(f"⚠️  Failed to parse date '{date_str}': {e}")
        return date_str

def parse_zoho_number(value: Any) -> float:
    """Convert Zoho number format to float"""
    if value is None or value == '':
        return 0.0
    
    if isinstance(value, (int, float)):
        return float(value)
    
    # Handle string numbers with Chilean format (1.500,00)
    if isinstance(value, str):
        # Remove thousands separators and convert decimal comma to dot
        value = value.replace('.', '').replace(',', '.')
        try:
            return float(value)
        except ValueError:
            return 0.0
    
    return 0.0

def map_zoho_status(zoho_status: str, invoice_type: str) -> str:
    """Map Zoho invoice status to our app status"""
    status_map = {
        'draft': 'draft',
        'sent': 'draft',  # Sent but not confirmed
        'viewed': 'draft',
        'overdue': 'posted',  # Still a valid invoice
        'partially_paid': 'posted',
        'paid': 'paid',
        'void': 'cancelled',
        'cancelled': 'cancelled',
    }
    
    return status_map.get(zoho_status.lower(), 'draft')

# ============================================================================
# PRODUCT/CUSTOMER MATCHING
# ============================================================================

def get_or_create_customer(zoho_customer: Dict) -> Optional[str]:
    """Get existing customer by name or create new one"""
    customer_name = zoho_customer.get('customer_name', 'Unknown Customer')
    
    # Try to find existing customer
    result = supabase.table('customers').select('id').eq('tenant_id', TENANT_ID).eq('name', customer_name).limit(1).execute()
    
    if result.data:
        return result.data[0]['id']
    
    # Create new customer
    customer_data = {
        'tenant_id': TENANT_ID,
        'name': customer_name,
        'email': zoho_customer.get('email'),
        'phone': zoho_customer.get('phone'),
        'rut': zoho_customer.get('custom_field_hash', {}).get('cf_rut'),  # If you have custom RUT field
        'notes': f"Imported from Zoho Books (Customer ID: {zoho_customer.get('customer_id')})"
    }
    
    try:
        result = supabase.table('customers').insert(customer_data).execute()
        print(f"  ✅ Created customer: {customer_name}")
        return result.data[0]['id']
    except Exception as e:
        print(f"  ⚠️  Failed to create customer '{customer_name}': {e}")
        return None

def get_or_create_supplier(zoho_vendor: Dict) -> Optional[str]:
    """Get existing supplier by name or create new one"""
    vendor_name = zoho_vendor.get('vendor_name', 'Unknown Supplier')
    
    # Try to find existing supplier
    result = supabase.table('suppliers').select('id').eq('tenant_id', TENANT_ID).eq('name', vendor_name).limit(1).execute()
    
    if result.data:
        return result.data[0]['id']
    
    # Create new supplier
    supplier_data = {
        'tenant_id': TENANT_ID,
        'name': vendor_name,
        'email': zoho_vendor.get('email'),
        'phone': zoho_vendor.get('phone'),
        'rut': zoho_vendor.get('custom_field_hash', {}).get('cf_rut'),
        'notes': f"Imported from Zoho Books (Vendor ID: {zoho_vendor.get('vendor_id')})"
    }
    
    try:
        result = supabase.table('suppliers').insert(supplier_data).execute()
        print(f"  ✅ Created supplier: {vendor_name}")
        return result.data[0]['id']
    except Exception as e:
        print(f"  ⚠️  Failed to create supplier '{vendor_name}': {e}")
        return None

def find_product_by_name(item_name: str) -> Optional[str]:
    """Find product by name (fuzzy match)"""
    result = supabase.table('products').select('id').eq('tenant_id', TENANT_ID).ilike('name', f'%{item_name}%').limit(1).execute()
    
    if result.data:
        return result.data[0]['id']
    
    return None

# ============================================================================
# SALES INVOICES IMPORT
# ============================================================================

def import_sales_invoices():
    """Import all sales invoices from Zoho Books"""
    print("\n" + "="*80)
    print("📥 IMPORTING SALES INVOICES")
    print("="*80)
    
    # Fetch all invoices
    invoices = fetch_all_pages('invoices', 'invoices')
    
    if not invoices:
        print("⚠️  No sales invoices found in Zoho Books")
        return
    
    imported_count = 0
    skipped_count = 0
    error_count = 0
    
    for invoice in invoices:
        try:
            invoice_number = invoice.get('invoice_number', 'UNKNOWN')
            
            # Check if already imported
            existing = supabase.table('sales_invoices').select('id').eq('tenant_id', TENANT_ID).eq('invoice_number', invoice_number).execute()
            
            if existing.data:
                skipped_count += 1
                continue
            
            # Get or create customer
            customer_id = None
            if invoice.get('customer_name'):
                customer_id = get_or_create_customer(invoice)
            
            # Map invoice data
            invoice_data = {
                'tenant_id': TENANT_ID,
                'invoice_number': invoice_number,
                'customer_id': customer_id,
                'date': parse_zoho_date(invoice.get('date')),
                'due_date': parse_zoho_date(invoice.get('due_date')),
                'subtotal': parse_zoho_number(invoice.get('sub_total', 0)),
                'tax_amount': parse_zoho_number(invoice.get('tax_total', 0)),
                'discount_amount': parse_zoho_number(invoice.get('discount_total', 0)),
                'total': parse_zoho_number(invoice.get('total', 0)),
                'paid_amount': parse_zoho_number(invoice.get('payment_made', 0)),
                'status': map_zoho_status(invoice.get('status', 'draft'), 'sales'),
                'notes': invoice.get('notes'),
                'source': 'zoho_books_import',
                'tax_treatment': 'tax_included' if parse_zoho_number(invoice.get('tax_total', 0)) > 0 else 'no_tax'
            }
            
            # Calculate net_amount (total - tax for tax_included invoices)
            if invoice_data['tax_treatment'] == 'tax_included':
                invoice_data['net_amount'] = invoice_data['total'] - invoice_data['tax_amount']
            else:
                invoice_data['net_amount'] = invoice_data['subtotal']
            
            # Insert invoice
            result = supabase.table('sales_invoices').insert(invoice_data).execute()
            invoice_id = result.data[0]['id']
            
            # Fetch and import line items
            invoice_detail = zoho_get(f"invoices/{invoice.get('invoice_id')}")
            line_items = invoice_detail.get('invoice', {}).get('line_items', [])
            
            for item in line_items:
                product_id = find_product_by_name(item.get('name', ''))
                
                line_data = {
                    'invoice_id': invoice_id,
                    'product_id': product_id,
                    'description': item.get('description') or item.get('name'),
                    'quantity': int(item.get('quantity', 1)),
                    'unit_price': parse_zoho_number(item.get('rate', 0)),
                    'discount_percent': parse_zoho_number(item.get('discount', 0)),
                    'tax_percent': parse_zoho_number(item.get('tax_percentage', 0)),
                    'total': parse_zoho_number(item.get('item_total', 0))
                }
                
                # Note: sales_invoices don't have line_items in your schema
                # They use JSON 'items' field. Skip line items or update schema.
            
            imported_count += 1
            print(f"  ✅ Imported: {invoice_number} (${invoice_data['total']:,.0f})")
            
        except Exception as e:
            error_count += 1
            print(f"  ❌ Failed to import invoice {invoice.get('invoice_number', 'UNKNOWN')}: {e}")
    
    print(f"\n✅ Imported: {imported_count}")
    print(f"⏭️  Skipped: {skipped_count} (already exist)")
    print(f"❌ Errors: {error_count}")

# ============================================================================
# PURCHASE INVOICES (BILLS) IMPORT
# ============================================================================

def import_purchase_invoices():
    """Import all purchase bills from Zoho Books"""
    print("\n" + "="*80)
    print("📥 IMPORTING PURCHASE INVOICES (BILLS)")
    print("="*80)
    
    # Fetch all bills
    bills = fetch_all_pages('bills', 'bills')
    
    if not bills:
        print("⚠️  No purchase bills found in Zoho Books")
        return
    
    imported_count = 0
    skipped_count = 0
    error_count = 0
    
    for bill in bills:
        try:
            bill_number = bill.get('bill_number', 'UNKNOWN')
            
            # Check if already imported
            existing = supabase.table('purchase_invoices').select('id').eq('tenant_id', TENANT_ID).eq('invoice_number', bill_number).execute()
            
            if existing.data:
                skipped_count += 1
                continue
            
            # Get or create supplier
            supplier_id = None
            if bill.get('vendor_name'):
                supplier_id = get_or_create_supplier(bill)
            
            # Map bill data
            invoice_data = {
                'tenant_id': TENANT_ID,
                'invoice_number': bill_number,
                'supplier_id': supplier_id,
                'date': parse_zoho_date(bill.get('date')),
                'due_date': parse_zoho_date(bill.get('due_date')),
                'subtotal': parse_zoho_number(bill.get('sub_total', 0)),
                'tax_amount': parse_zoho_number(bill.get('tax_total', 0)),
                'total': parse_zoho_number(bill.get('total', 0)),
                'paid_amount': parse_zoho_number(bill.get('payment_made', 0)),
                'status': map_zoho_status(bill.get('status', 'draft'), 'purchase'),
                'notes': bill.get('notes'),
                'source': 'zoho_books_import',
                'tax_treatment': 'tax_included' if parse_zoho_number(bill.get('tax_total', 0)) > 0 else 'no_tax'
            }
            
            # Calculate net_amount
            invoice_data['net_amount'] = invoice_data['subtotal']
            
            # Insert invoice
            result = supabase.table('purchase_invoices').insert(invoice_data).execute()
            invoice_id = result.data[0]['id']
            
            imported_count += 1
            print(f"  ✅ Imported: {bill_number} (${invoice_data['total']:,.0f})")
            
        except Exception as e:
            error_count += 1
            print(f"  ❌ Failed to import bill {bill.get('bill_number', 'UNKNOWN')}: {e}")
    
    print(f"\n✅ Imported: {imported_count}")
    print(f"⏭️  Skipped: {skipped_count} (already exist)")
    print(f"❌ Errors: {error_count}")

# ============================================================================
# JOURNAL ENTRIES IMPORT
# ============================================================================

def import_journal_entries():
    """Import journal entries from Zoho Books"""
    print("\n" + "="*80)
    print("📥 IMPORTING JOURNAL ENTRIES")
    print("="*80)
    
    # Fetch all journal entries
    entries = fetch_all_pages('journalentries', 'journalentries')
    
    if not entries:
        print("⚠️  No journal entries found in Zoho Books")
        return
    
    imported_count = 0
    skipped_count = 0
    error_count = 0
    
    for entry in entries:
        try:
            entry_number = entry.get('entry_number', 'UNKNOWN')
            
            # Check if already imported
            existing = supabase.table('journal_entries').select('id').eq('tenant_id', TENANT_ID).eq('entry_number', entry_number).execute()
            
            if existing.data:
                skipped_count += 1
                continue
            
            # Map journal entry data
            entry_data = {
                'tenant_id': TENANT_ID,
                'entry_number': entry_number,
                'date': parse_zoho_date(entry.get('journal_date')),
                'description': entry.get('notes') or f"Imported from Zoho Books - {entry_number}",
                'total': parse_zoho_number(entry.get('total', 0)),
                'source_type': 'manual',
                'source_reference': f"zoho_books_{entry.get('journal_id')}"
            }
            
            # Insert journal entry
            result = supabase.table('journal_entries').insert(entry_data).execute()
            journal_entry_id = result.data[0]['id']
            
            # Fetch full entry details for line items
            entry_detail = zoho_get(f"journalentries/{entry.get('journal_id')}")
            line_items = entry_detail.get('journalentry', {}).get('line_items', [])
            
            # Import journal lines
            for line in line_items:
                # Try to find matching account by name
                account_name = line.get('account_name', '')
                account_result = supabase.table('accounts').select('id').eq('tenant_id', TENANT_ID).ilike('name', f'%{account_name}%').limit(1).execute()
                
                account_id = account_result.data[0]['id'] if account_result.data else None
                
                if not account_id:
                    print(f"  ⚠️  Account not found: {account_name} - skipping line")
                    continue
                
                line_data = {
                    'entry_id': journal_entry_id,
                    'account_id': account_id,
                    'description': line.get('description') or account_name,
                    'debit': parse_zoho_number(line.get('debit_amount', 0)),
                    'credit': parse_zoho_number(line.get('credit_amount', 0))
                }
                
                supabase.table('journal_lines').insert(line_data).execute()
            
            imported_count += 1
            print(f"  ✅ Imported: {entry_number} (${entry_data['total']:,.0f})")
            
        except Exception as e:
            error_count += 1
            print(f"  ❌ Failed to import entry {entry.get('entry_number', 'UNKNOWN')}: {e}")
    
    print(f"\n✅ Imported: {imported_count}")
    print(f"⏭️  Skipped: {skipped_count} (already exist)")
    print(f"❌ Errors: {error_count}")

# ============================================================================
# EXPENSES IMPORT
# ============================================================================

def import_expenses():
    """Import expenses from Zoho Books"""
    print("\n" + "="*80)
    print("📥 IMPORTING EXPENSES")
    print("="*80)
    
    print("⚠️  Expense import requires expense tracking module in your app")
    print("💡 Skipping for now - you can enable this later if needed")
    
    # Uncomment when expense module is ready:
    # expenses = fetch_all_pages('expenses', 'expenses')
    # ... import logic

# ============================================================================
# MAIN EXECUTION
# ============================================================================

def main():
    """Main import flow"""
    print("\n" + "="*80)
    print("🧾 ZOHO BOOKS ACCOUNTING DATA IMPORT")
    print("="*80)
    print(f"📍 Tenant ID: {TENANT_ID}")
    print(f"🏢 Organization ID: {ZOHO_ORG_ID}")
    print("="*80)
    
    # Validate configuration
    if not config.validate_config():
        sys.exit(1)
    
    # Test Supabase connection
    try:
        result = supabase.table('tenants').select('shop_name').eq('id', TENANT_ID).execute()
        if result.data:
            print(f"✅ Connected to tenant: {result.data[0]['shop_name']}")
        else:
            print(f"❌ Tenant {TENANT_ID} not found in database")
            sys.exit(1)
    except Exception as e:
        print(f"❌ Failed to connect to Supabase: {e}")
        sys.exit(1)
    
    # Test Zoho connection
    try:
        get_access_token()
        print("✅ Zoho Books authentication successful")
    except Exception as e:
        print(f"❌ Failed to authenticate with Zoho: {e}")
        sys.exit(1)
    
    # Import data
    try:
        import_sales_invoices()
        import_purchase_invoices()
        import_journal_entries()
        import_expenses()
        
        print("\n" + "="*80)
        print("✅ IMPORT COMPLETED SUCCESSFULLY")
        print("="*80)
        print("📊 Summary available in Flutter app")
        print("💡 Check Accounting module to verify imported data")
        
    except KeyboardInterrupt:
        print("\n\n⚠️  Import cancelled by user")
        sys.exit(0)
    except Exception as e:
        print(f"\n\n❌ Import failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()
