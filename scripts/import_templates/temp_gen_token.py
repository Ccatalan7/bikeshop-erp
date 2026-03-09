import requests

client_id = "1000.HEUWHSDCUE4GAN7CL3P045ICRU5V5B"
client_secret = "ffd0bc79a8e2456cef492010e34c3653a55d82be43"
grant_token = "1000.7e2b6bce0a3dec51b9324e1c6269b5e9.595e1c25a197a9edaca22b3bbf96b470"
org_id = "788658742"

token_url = "https://accounts.zoho.com/oauth/v2/token"
payload = {
    'grant_type': 'authorization_code',
    'client_id': client_id,
    'client_secret': client_secret,
    'code': grant_token,
    'redirect_uri': 'https://localhost:8000',
    'organization_id': org_id
}

import json
response = requests.post(token_url, params=payload)

with open('temp_token_out.json', 'w') as f:
    json.dump(response.json(), f)
    
print("Saved to temp_token_out.json")
