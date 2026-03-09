import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent))

from connections.supabase_connection import SupabaseConnection

supabase = SupabaseConnection()
response = supabase.client.table('products').select('*').limit(1).execute()
print("Product Schema:")
if response.data:
    for key, value in response.data[0].items():
        print(f" - {key}: {type(value).__name__}")
else:
    print("No products found")
