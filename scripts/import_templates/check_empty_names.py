from config import *
from supabase import create_client

client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

result = client.from('customers').select('id, name').eq('tenant_id', TENANT_ID).execute()

empty_names = [c for c in result.data if not c.get('name') or c.get('name').strip() == '']
print(f'Customers with empty names: {len(empty_names)}')
if empty_names:
    for i, c in enumerate(empty_names[:10]):
        print(f"{i+1}. ID: {c['id']}, Name: '{c.get('name')}'")
