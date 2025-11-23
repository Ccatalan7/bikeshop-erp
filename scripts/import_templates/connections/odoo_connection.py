"""
Odoo ERP Connection Module

Provides XML-RPC authentication and API methods for Odoo.
This is a TEMPLATE - API key can expire, ask user each time.
"""

import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))

import config
import xmlrpc.client
from typing import List, Dict, Any


class OdooConnection:
    """
    Handle all Odoo API interactions via XML-RPC.
    
    Usage:
        # Ask user for API key (can expire)
        api_key = input("Odoo API Key: ").strip()
        
        odoo = OdooConnection(api_key)
        products = odoo.fetch_all_products()
        partners = odoo.fetch_all_partners()
    """
    
    def __init__(self, api_key: str):
        """
        Initialize with user-provided API key.
        
        Args:
            api_key: Odoo API Key (can expire/rotate)
        """
        # Load permanent values from config
        self.url = config.ODOO_URL
        self.db = config.ODOO_DB
        self.username = config.ODOO_USERNAME
        
        # User-provided (can expire)
        self.api_key = api_key
        
        # Initialize XML-RPC clients
        self.common = xmlrpc.client.ServerProxy(f'{self.url}/xmlrpc/2/common')
        self.models = xmlrpc.client.ServerProxy(f'{self.url}/xmlrpc/2/object')
        
        # Authenticate
        print("🔑 Authenticating with Odoo...")
        try:
            self.uid = self.common.authenticate(self.db, self.username, self.api_key, {})
            if not self.uid:
                raise Exception(f"Odoo authentication failed - check API key, username ({self.username}), and database ({self.db})")
            print(f"   ✅ Authenticated (UID: {self.uid})")
        except Exception as e:
            print(f"   ❌ Authentication error: {str(e)}")
            raise
    
    def search(self, model: str, domain: List = None) -> List[int]:
        """
        Search for record IDs in Odoo
        
        Args:
            model: Odoo model name (e.g., 'product.product', 'res.partner')
            domain: Search domain (e.g., [('default_code', '=', 'SKU123')])
        
        Returns:
            List of record IDs
        """
        if domain is None:
            domain = []
        
        return self.models.execute_kw(
            self.db, self.uid, self.api_key,
            model, 'search', [domain]
        )
    
    def read(self, model: str, ids: List[int], fields: List[str] = None) -> List[Dict]:
        """
        Read records from Odoo
        
        Args:
            model: Odoo model name
            ids: List of record IDs
            fields: List of field names to fetch (None = all fields)
        
        Returns:
            List of record dictionaries
        """
        if fields is None:
            fields = []
        
        return self.models.execute_kw(
            self.db, self.uid, self.api_key,
            model, 'read', [ids], {'fields': fields}
        )
    
    def search_read(self, model: str, domain: List = None, fields: List[str] = None, limit: int = None) -> List[Dict]:
        """
        Search and read in one call
        
        Args:
            model: Odoo model name
            domain: Search domain
            fields: Fields to fetch
            limit: Maximum records to return
        
        Returns:
            List of record dictionaries
        """
        if domain is None:
            domain = []
        if fields is None:
            fields = []
        
        kwargs = {'fields': fields}
        if limit:
            kwargs['limit'] = limit
        
        return self.models.execute_kw(
            self.db, self.uid, self.api_key,
            model, 'search_read', [domain], kwargs
        )
    
    def create(self, model: str, values: Dict) -> int:
        """
        Create a new record in Odoo
        
        Args:
            model: Odoo model name
            values: Dictionary of field values
        
        Returns:
            New record ID
        """
        return self.models.execute_kw(
            self.db, self.uid, self.api_key,
            model, 'create', [values]
        )
    
    def write(self, model: str, ids: List[int], values: Dict) -> bool:
        """
        Update records in Odoo
        
        Args:
            model: Odoo model name
            ids: List of record IDs to update
            values: Dictionary of field values to update
        
        Returns:
            True if successful
        """
        return self.models.execute_kw(
            self.db, self.uid, self.api_key,
            model, 'write', [ids, values]
        )
    
    def fetch_all_products(self) -> List[Dict]:
        """
        Fetch all products from Odoo
        
        Returns:
            List of product dictionaries with keys: id, name, default_code (SKU), list_price, standard_price
        """
        print("\n📥 Fetching products from Odoo...")
        
        products = self.search_read(
            'product.product',
            domain=[],
            fields=['name', 'default_code', 'list_price', 'standard_price', 'qty_available']
        )
        
        # Transform to standard format
        result = []
        for p in products:
            result.append({
                'id': p['id'],
                'name': p.get('name', ''),
                'sku': p.get('default_code', ''),
                'price': float(p.get('list_price', 0)),
                'cost': float(p.get('standard_price', 0)),
                'stock': int(p.get('qty_available', 0))
            })
        
        print(f"   ✅ Total: {len(result)} products")
        return result
    
    def fetch_all_partners(self, is_customer: bool = None, is_supplier: bool = None) -> List[Dict]:
        """
        Fetch partners (customers/suppliers) from Odoo
        
        Args:
            is_customer: Filter customers only
            is_supplier: Filter suppliers only
        
        Returns:
            List of partner dictionaries
        """
        print("\n📥 Fetching partners from Odoo...")
        
        domain = []
        if is_customer is not None:
            domain.append(('customer_rank', '>', 0))
        if is_supplier is not None:
            domain.append(('supplier_rank', '>', 0))
        
        partners = self.search_read(
            'res.partner',
            domain=domain,
            fields=['name', 'email', 'phone', 'vat', 'street', 'city', 'country_id']
        )
        
        print(f"   ✅ Total: {len(partners)} partners")
        return partners
    
    def update_product_sku(self, product_id: int, new_sku: str) -> bool:
        """
        Update product SKU in Odoo
        
        Args:
            product_id: Odoo product ID
            new_sku: New SKU value
        
        Returns:
            True if successful
        """
        try:
            self.write('product.product', [product_id], {'default_code': new_sku})
            return True
        except Exception as e:
            print(f"      ❌ Failed: {e}")
            return False
