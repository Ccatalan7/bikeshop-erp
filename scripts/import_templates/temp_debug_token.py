import requests
from sync_zoho_to_flutter import ZOHO_CLIENT_ID, ZOHO_CLIENT_SECRET, ZOHO_REFRESH_TOKEN, ZOHO_OAUTH_DOMAIN

token_url = f"{ZOHO_OAUTH_DOMAIN}/oauth/v2/token"
params = {
    'refresh_token': ZOHO_REFRESH_TOKEN,
    'client_id': ZOHO_CLIENT_ID,
    'client_secret': ZOHO_CLIENT_SECRET,
    'grant_type': 'refresh_token'
}
response = requests.post(token_url, params=params)
print("STATUS CODE:", response.status_code)
print("RESPONSE:", response.text)
