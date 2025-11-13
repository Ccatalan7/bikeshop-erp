from supabase import create_client
import config

supabase = create_client(config.SUPABASE_URL, config.SUPABASE_SERVICE_ROLE_KEY)

print("="*80)
print("📋 CHECKING ACTUAL DATABASE SCHEMA")
print("="*80)

# Check customers table columns
print("\n👥 CUSTOMERS TABLE COLUMNS:")
try:
    result = supabase.table("customers").select("*").limit(1).execute()
    if result.data:
        print(f"   Columns: {', '.join(result.data[0].keys())}")
    else:
        # Try inserting a dummy record to see what columns exist
        print("   No existing records, checking schema...")
        result = supabase.rpc("exec", {"query": "SELECT column_name FROM information_schema.columns WHERE table_name = 'customers' AND table_schema = 'public' ORDER BY ordinal_position"}).execute()
        print(f"   Result: {result}")
except Exception as e:
    print(f"   Error: {e}")

# Check suppliers table columns
print("\n🏭 SUPPLIERS TABLE COLUMNS:")
try:
    result = supabase.table("suppliers").select("*").limit(1).execute()
    if result.data:
        print(f"   Columns: {', '.join(result.data[0].keys())}")
    else:
        print("   No existing records")
except Exception as e:
    print(f"   Error: {e}")

print("\n" + "="*80)
