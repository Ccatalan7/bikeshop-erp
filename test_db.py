import os
import requests
import json

with open('.env', 'r') as f:
    for line in f:
        if "=" in line:
            key, val = line.strip().split("=", 1)
            os.environ[key] = val

url = f"{os.environ['SUPABASE_URL']}/rest/v1/"
headers = {
    "apikey": os.environ["SUPABASE_SERVICE_ROLE_KEY"],
    "Authorization": f"Bearer {os.environ['SUPABASE_SERVICE_ROLE_KEY']}"
}

print("Running NOTIFY pgrst to reload schema cache...")
response = requests.post(
    f"{url}rpc/reload_schema_cache",
    headers=headers,
    json={}
)
if response.status_code != 200:
    print(f"Failed to call reload_schema_cache directly: {response.text}")
    print("Trying SQL directly via Supabase API...")
    
    # We can use the postgresql REST API for running arbitrary SQL on Supabase
    query_url = f"{url}?query=NOTIFY%20pgrst%2C%20'reload%20schema'"
    print(f"Please use Supabase Studio to run: NOTIFY pgrst, 'reload schema'")

print("Getting Purchase Payments schema...")
response = requests.get(f"{url}purchase_payments?limit=1", headers=headers)
print(response.status_code)
print(response.text)
