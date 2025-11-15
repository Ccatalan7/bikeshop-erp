"""
Zoho Inventory/Books Connection Module

Provides OAuth authentication and API methods for Zoho.
This is a TEMPLATE - never hardcode user credentials here.
Credentials are passed as parameters and managed at runtime.
"""

import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))

import config
import requests
from typing import Dict, List, Optional


class ZohoConnection:
    """
    Handle all Zoho API interactions with automatic OAuth token refresh.
    
    Usage:
        # Ask user for credentials (they can expire)
        client_id = input("Zoho Client ID: ").strip()
        client_secret = input("Zoho Client Secret: ").strip()
        refresh_token = input("Zoho Refresh Token: ").strip()
        
        zoho = ZohoConnection(client_id, client_secret, refresh_token)
        products = zoho.fetch_all_products()
    """
    
    def __init__(self, client_id: str, client_secret: str, refresh_token: str):
        """
        Initialize Zoho connection with user-provided credentials.
        
        Args:
            client_id: Zoho OAuth Client ID (can rotate)
            client_secret: Zoho OAuth Client Secret (can rotate)
            refresh_token: Zoho Refresh Token (expires after months)
        """
        self.client_id = client_id
        self.client_secret = client_secret
        self.refresh_token = refresh_token
        
        # Load permanent values from config
        self.api_domain = config.ZOHO_API_DOMAIN
        self.oauth_domain = config.ZOHO_OAUTH_DOMAIN
        self.org_id = config.ZOHO_ORG_ID
        
        # Access token (1-hour expiry, managed internally)
        self.access_token = None
        
        # Get initial access token
        self._refresh_access_token()
    
    def _refresh_access_token(self) -> str:
        """
        Get fresh access token using refresh token.
        Access tokens expire after 1 hour - this is called automatically.
        """
        print("🔑 Getting Zoho access token...")
        
        token_url = f"{self.oauth_domain}/oauth/v2/token"
        token_params = {
            'refresh_token': self.refresh_token,
            'client_id': self.client_id,
            'client_secret': self.client_secret,
            'grant_type': 'refresh_token'
        }
        
        response = requests.post(token_url, params=token_params)
        response.raise_for_status()
        
        self.access_token = response.json()['access_token']
        print("   ✅ Token obtained (valid for 1 hour)")
        return self.access_token
    
    def _get_headers(self) -> Dict:
        """Get headers with current access token"""
        return {
            'Authorization': f'Zoho-oauthtoken {self.access_token}',
            'Content-Type': 'application/json'
        }
    
    def get(self, endpoint: str, params: Optional[Dict] = None) -> Dict:
        """
        Generic GET request to Zoho API
        
        Args:
            endpoint: API endpoint (e.g., '/items', '/contacts')
            params: Query parameters
        
        Returns:
            Response JSON
        """
        url = f"{self.api_domain}/inventory/v1{endpoint}"
        
        if params is None:
            params = {}
        params['organization_id'] = self.org_id
        
        response = requests.get(url, headers=self._get_headers(), params=params)
        response.raise_for_status()
        return response.json()
    
    def post(self, endpoint: str, data: Dict) -> Dict:
        """Generic POST request to Zoho API"""
        url = f"{self.api_domain}/inventory/v1{endpoint}"
        params = {'organization_id': self.org_id}
        
        response = requests.post(url, headers=self._get_headers(), params=params, json=data)
        response.raise_for_status()
        return response.json()
    
    def put(self, endpoint: str, data: Dict) -> Dict:
        """Generic PUT request to Zoho API"""
        url = f"{self.api_domain}/inventory/v1{endpoint}"
        params = {'organization_id': self.org_id}
        
        response = requests.put(url, headers=self._get_headers(), params=params, json=data)
        response.raise_for_status()
        return response.json()
    
    def fetch_all_products(self) -> List[Dict]:
        """
        Fetch all products from Zoho with pagination
        
        Returns:
            List of product dictionaries with keys: name, sku, price, cost, stock
        """
        print("\n📥 Fetching products from Zoho...")
        
        all_items = []
        page = 1
        
        while True:
            params = {'page': page, 'per_page': 200}
            data = self.get('/items', params)
            items = data.get('items', [])
            
            if not items:
                break
            
            for item in items:
                all_items.append({
                    'item_id': item.get('item_id'),
                    'name': item.get('name', ''),
                    'sku': item.get('sku', ''),
                    'price': float(item.get('rate', 0)),
                    'cost': float(item.get('purchase_rate', 0)),
                    'stock': int(item.get('stock_on_hand', 0))
                })
            
            print(f"   Page {page}: {len(items)} items")
            page += 1
            
            if not data.get('page_context', {}).get('has_more_page'):
                break
        
        print(f"   ✅ Total: {len(all_items)} products")
        return all_items
    
    def fetch_all_contacts(self) -> List[Dict]:
        """
        Fetch all contacts from Zoho with pagination
        
        Returns:
            List of contact dictionaries
        """
        print("\n📥 Fetching contacts from Zoho...")
        
        all_contacts = []
        page = 1
        
        while True:
            params = {'page': page, 'per_page': 200}
            data = self.get('/contacts', params)
            contacts = data.get('contacts', [])
            
            if not contacts:
                break
            
            all_contacts.extend(contacts)
            print(f"   Page {page}: {len(contacts)} contacts")
            page += 1
            
            if not data.get('page_context', {}).get('has_more_page'):
                break
        
        print(f"   ✅ Total: {len(all_contacts)} contacts")
        return all_contacts
    
    def update_product(self, item_id: str, updates: Dict) -> bool:
        """
        Update a product in Zoho
        
        Args:
            item_id: Zoho item ID
            updates: Dictionary with fields to update (e.g., {'sku': 'NEW-SKU', 'rate': 10000})
        
        Returns:
            True if successful
        """
        try:
            self.put(f'/items/{item_id}', updates)
            return True
        except Exception as e:
            print(f"      ❌ Failed: {e}")
            return False
    
    def update_contact(self, contact_id: str, updates: Dict) -> bool:
        """Update a contact in Zoho"""
        try:
            self.put(f'/contacts/{contact_id}', updates)
            return True
        except Exception as e:
            print(f"      ❌ Failed: {e}")
            return False
