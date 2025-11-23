"""
Test Odoo Authentication

Quick script to verify Odoo credentials work.
"""

import xmlrpc.client

URL = "https://vinabike.odoo.com"
DB = "vinabike"
USERNAME = "vinabikechile@gmail.com"
API_KEY = "aac576b5e8f222233dac50a326568030fce3c70c"

print(f"Testing Odoo connection...")
print(f"  URL: {URL}")
print(f"  Database: {DB}")
print(f"  Username: {USERNAME}")
print(f"  API Key: {API_KEY[:20]}...")

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    print("\n✅ Connected to Odoo XML-RPC endpoint")
    
    print("\n🔑 Testing authentication...")
    uid = common.authenticate(DB, USERNAME, API_KEY, {})
    
    if uid:
        print(f"✅ Authentication successful! UID: {uid}")
    else:
        print("❌ Authentication failed - returned False/0")
        print("\nPossible reasons:")
        print("  - Wrong database name")
        print("  - Wrong username")  
        print("  - Wrong/expired API key")
        print("\n💡 Get a fresh API key from:")
        print("  Odoo → Settings → Users → Your User → API Key tab → Generate")
        
except Exception as e:
    print(f"❌ Error: {type(e).__name__}: {str(e)}")
    import traceback
    traceback.print_exc()
