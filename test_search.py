import os
import json
import requests
from dotenv import load_dotenv

# Load env variables from .env file
def load_env():
    with open(".env", "r") as f:
        for line in f:
            if "=" in line:
                key, val = line.strip().split("=", 1)
                os.environ[key] = val

load_env()

SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")

with open("query_embedding.json", "r") as f:
    data = json.load(f)
    embedding = data["embedding"]["values"]

# Call the search_products RPC
url = f"{SUPABASE_URL}/rest/v1/rpc/search_products"
headers = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json"
}
payload = {
    "query_embedding": embedding,
    "similarity_threshold": 0.1,  # Low threshold for debugging
    "match_count": 10
}

response = requests.post(url, headers=headers, json=payload)

if response.status_code == 200:
    results = response.json()
    print(f"Found {len(results)} matches:")
    for r in results:
        print(f"- {r['name']} (Similarity: {r['similarity']:.4f})")
else:
    print(f"Error calling RPC: {response.status_code}")
    print(response.text)
