"""
🔐 CONFIGURATION TEMPLATE FOR IMPORT/SYNC SCRIPTS
==================================================

INSTRUCTIONS FOR AI AGENTS:
1. Copy this file to `config.py` in the same directory
2. Ask user for the required credentials
3. Fill in the values below
4. Never commit config.py to git (it's in .gitignore)

INSTRUCTIONS FOR USERS:
1. Copy this file: `cp config.template.py config.py`
2. Fill in your API keys and credentials
3. Keep config.py private (never share or commit it)
"""

# ============================================================================
# SUPABASE CONFIGURATION
# ============================================================================
# Get from: https://supabase.com/dashboard/project/YOUR_PROJECT/settings/api
SUPABASE_URL = "https://YOUR_PROJECT.supabase.co"
SUPABASE_SERVICE_ROLE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.YOUR_KEY_HERE"

# Get from Supabase: SELECT id, shop_name FROM tenants;
# Or from Flutter app user_profiles table
TENANT_ID = "00000000-0000-0000-0000-000000000000"

# ============================================================================
# ZOHO CONFIGURATION
# ============================================================================
# Get from: https://api-console.zoho.com/
# 1. Create Server-based Application
# 2. Generate self-authorized grant token
# 3. Exchange for refresh token

ZOHO_CLIENT_ID = "1000.XXXXXXXXXXXXXXXXXXXXXXXXXXXX"
ZOHO_CLIENT_SECRET = "your_client_secret_here"
ZOHO_REFRESH_TOKEN = "1000.xxxxxxxxxxxxxxxxxxxxxxxxxxxx.yyyyyyyyyyyyyyyyyyyyyyyyyyyy"

# Get from: Zoho Books Settings > Organization > Organization ID
ZOHO_ORG_ID = "123456789"

# Regional API domains:
# - US: https://www.zohoapis.com
# - EU: https://www.zohoapis.eu
# - IN: https://www.zohoapis.in
# - AU: https://www.zohoapis.com.au
# - CN: https://www.zohoapis.com.cn
ZOHO_API_DOMAIN = "https://www.zohoapis.com"

# ============================================================================
# ODOO CONFIGURATION
# ============================================================================
# Get from: Odoo Settings > Users & Companies > Your User > Account Security > API Keys
# 1. Click "New API Key"
# 2. Name it (e.g., "Python Import Script")
# 3. Copy the generated key

ODOO_URL = "https://your-company.odoo.com"  # Your Odoo instance URL
ODOO_DB = "your-database-name"  # Database name (usually company name)
ODOO_USERNAME = "user@example.com"  # Your Odoo login email
ODOO_API_KEY = "your_api_key_here"  # API key from above

# ============================================================================
# IMPORT SETTINGS
# ============================================================================

# Batch size for bulk operations (adjust based on API rate limits)
BATCH_SIZE = 100

# Rate limiting (seconds to wait between API calls)
RATE_LIMIT_DELAY = 0.5

# Retry settings
MAX_RETRIES = 3
RETRY_DELAY = 2  # seconds

# Logging
ENABLE_VERBOSE_LOGGING = True
LOG_FILE = "import_log.txt"

# ============================================================================
# VALIDATION
# ============================================================================

def validate_config():
    """Validate that all required fields are filled"""
    errors = []
    
    if "YOUR_PROJECT" in SUPABASE_URL:
        errors.append("❌ SUPABASE_URL not configured")
    
    if "YOUR_KEY_HERE" in SUPABASE_SERVICE_ROLE_KEY:
        errors.append("❌ SUPABASE_SERVICE_ROLE_KEY not configured")
    
    if TENANT_ID == "00000000-0000-0000-0000-000000000000":
        errors.append("❌ TENANT_ID not configured")
    
    if "XXXXXXXXXXXXXXXXXXXXXXXXXXXX" in ZOHO_CLIENT_ID:
        errors.append("⚠️  ZOHO_CLIENT_ID not configured (optional if not using Zoho)")
    
    if "your-company" in ODOO_URL:
        errors.append("⚠️  ODOO_URL not configured (optional if not using Odoo)")
    
    if errors:
        print("\n" + "=" * 80)
        print("🔴 CONFIGURATION ERRORS")
        print("=" * 80)
        for error in errors:
            print(error)
        print("\nPlease edit config.py and fill in your credentials.")
        print("=" * 80 + "\n")
        return False
    
    print("✅ Configuration validated successfully!")
    return True

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def get_supabase_client():
    """Initialize and return Supabase client"""
    from supabase import create_client
    return create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

def get_odoo_connection():
    """Initialize and return Odoo XML-RPC connection"""
    import xmlrpc.client
    
    common = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/common')
    uid = common.authenticate(ODOO_DB, ODOO_USERNAME, ODOO_API_KEY, {})
    
    if not uid:
        raise Exception("Failed to authenticate with Odoo")
    
    models = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/object')
    return uid, models

def get_zoho_access_token():
    """Get fresh Zoho access token using refresh token"""
    import requests
    
    url = f"{ZOHO_API_DOMAIN}/oauth/v2/token"
    params = {
        'refresh_token': ZOHO_REFRESH_TOKEN,
        'client_id': ZOHO_CLIENT_ID,
        'client_secret': ZOHO_CLIENT_SECRET,
        'grant_type': 'refresh_token'
    }
    
    response = requests.post(url, params=params)
    response.raise_for_status()
    
    return response.json()['access_token']
