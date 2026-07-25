"""
Supabase/Flutter Connection Module

Provides authenticated Supabase client and helper methods.
Non-secret tenant settings come from config.py. The exact URL and privileged
key must be injected through the protected process environment.
"""

import os
import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))

import config
from supabase import create_client, Client
from typing import List, Dict, Optional


class SupabaseConnection:
    """
    Handle all Supabase/Flutter database interactions.
    Uses the tenant ID from config.py and exact SUPABASE_URL plus
    SUPABASE_SECRET_KEY from the process environment.
    
    Usage:
        supabase = SupabaseConnection()
        products = supabase.fetch_all_products()
        customers = supabase.fetch_all_customers()
    """
    
    def __init__(self):
        """Initialize with protected process credentials."""
        self.url = os.environ.get("SUPABASE_URL", "").strip()
        self.key = os.environ.get("SUPABASE_SECRET_KEY", "").strip()
        self.tenant_id = config.TENANT_ID
        approved_production_url = "https://xzdvtzdqjeyqxnkqprtf.supabase.co"
        if (
            self.url != approved_production_url
            and not self.url.startswith(("http://127.0.0.1:", "http://localhost:"))
        ):
            raise RuntimeError(
                "Missing or invalid SUPABASE_URL. Set the approved production "
                "URL or an explicit loopback URL in the protected process environment."
            )
        if not self.key:
            raise RuntimeError(
                "Missing SUPABASE_SECRET_KEY in the process environment. "
                "Inject it from the documented OS credential store."
            )
        
        # Initialize client
        print("🔑 Connecting to Supabase...")
        self.client: Client = create_client(self.url, self.key)
        print("   ✅ Connected")
    
    def fetch_all_products(self) -> List[Dict]:
        """
        Fetch all products from Supabase with pagination
        
        Returns:
            List of product dictionaries with keys: id, name, sku, price, cost, stock_quantity
        """
        print("\n📥 Fetching products from Flutter/Supabase...")
        
        all_products = []
        page_size = 1000
        offset = 0
        
        while True:
            response = self.client.table('products') \
                .select('id,name,sku,price,cost,stock_quantity,tenant_id') \
                .eq('tenant_id', self.tenant_id) \
                .range(offset, offset + page_size - 1) \
                .execute()
            
            if not response.data:
                break
            
            for p in response.data:
                all_products.append({
                    'id': p.get('id'),
                    'name': p.get('name', ''),
                    'sku': p.get('sku', ''),
                    'price': float(p.get('price', 0)),
                    'cost': float(p.get('cost', 0)),
                    'stock': int(p.get('stock_quantity', 0))
                })
            
            print(f"   Page {offset // page_size + 1}: {len(response.data)} products")
            
            if len(response.data) < page_size:
                break
            
            offset += page_size
        
        print(f"   ✅ Total: {len(all_products)} products")
        return all_products
    
    def fetch_all_customers(self) -> List[Dict]:
        """
        Fetch all customers from Supabase with pagination
        
        Returns:
            List of customer dictionaries
        """
        print("\n📥 Fetching customers from Flutter/Supabase...")
        
        all_customers = []
        page_size = 1000
        offset = 0
        
        while True:
            response = self.client.table('customers') \
                .select('*') \
                .eq('tenant_id', self.tenant_id) \
                .range(offset, offset + page_size - 1) \
                .execute()
            
            if not response.data:
                break
            
            all_customers.extend(response.data)
            print(f"   Page {offset // page_size + 1}: {len(response.data)} customers")
            
            if len(response.data) < page_size:
                break
            
            offset += page_size
        
        print(f"   ✅ Total: {len(all_customers)} customers")
        return all_customers
    
    def fetch_all_suppliers(self) -> List[Dict]:
        """
        Fetch all suppliers from Supabase with pagination
        
        Returns:
            List of supplier dictionaries
        """
        print("\n📥 Fetching suppliers from Flutter/Supabase...")
        
        all_suppliers = []
        page_size = 1000
        offset = 0
        
        while True:
            response = self.client.table('suppliers') \
                .select('*') \
                .eq('tenant_id', self.tenant_id) \
                .range(offset, offset + page_size - 1) \
                .execute()
            
            if not response.data:
                break
            
            all_suppliers.extend(response.data)
            print(f"   Page {offset // page_size + 1}: {len(response.data)} suppliers")
            
            if len(response.data) < page_size:
                break
            
            offset += page_size
        
        print(f"   ✅ Total: {len(all_suppliers)} suppliers")
        return all_suppliers
    
    def update_product(self, product_id: str, updates: Dict) -> bool:
        """
        Update a product in Supabase
        
        Args:
            product_id: Product UUID
            updates: Dictionary with fields to update (e.g., {'price': 10000, 'cost': 5000})
        
        Returns:
            True if successful
        """
        try:
            self.client.table('products') \
                .update(updates) \
                .eq('id', product_id) \
                .eq('tenant_id', self.tenant_id) \
                .execute()
            return True
        except Exception as e:
            print(f"      ❌ Failed: {e.args[0] if e.args else str(e)}")
            return False
    
    def insert_customer(self, customer_data: Dict) -> bool:
        """
        Insert a new customer in Supabase
        
        Args:
            customer_data: Customer fields (name, email, phone, rut, etc.)
                          tenant_id is automatically added
        
        Returns:
            True if successful
        """
        try:
            customer_data['tenant_id'] = self.tenant_id
            self.client.table('customers').insert(customer_data).execute()
            return True
        except Exception as e:
            print(f"      ❌ Failed: {e.args[0] if e.args else str(e)}")
            return False
    
    def insert_supplier(self, supplier_data: Dict) -> bool:
        """
        Insert a new supplier in Supabase
        
        Args:
            supplier_data: Supplier fields (name, email, phone, rut, etc.)
                          tenant_id is automatically added
        
        Returns:
            True if successful
        """
        try:
            supplier_data['tenant_id'] = self.tenant_id
            self.client.table('suppliers').insert(supplier_data).execute()
            return True
        except Exception as e:
            print(f"      ❌ Failed: {e.args[0] if e.args else str(e)}")
            return False
    
    def upsert_product(self, product_data: Dict, conflict_column: str = 'sku') -> bool:
        """
        Insert or update product (based on SKU or other unique field)
        
        Args:
            product_data: Product fields including SKU
            conflict_column: Column to use for conflict detection (default: 'sku')
        
        Returns:
            True if successful
        """
        try:
            product_data['tenant_id'] = self.tenant_id
            self.client.table('products').upsert(
                product_data,
                on_conflict=conflict_column
            ).execute()
            return True
        except Exception as e:
            print(f"      ❌ Failed: {e.args[0] if e.args else str(e)}")
            return False
