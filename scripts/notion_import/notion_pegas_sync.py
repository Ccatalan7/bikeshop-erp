#!/usr/bin/env python3
"""
Notion to Pegas (Mechanic Jobs) Sync Script

This script fetches data from a Notion database and syncs it to the mechanic_jobs table.
It intelligently matches Notion properties to database columns.
"""

import os
import sys
import requests
import time
from typing import Dict, List, Any, Optional
from datetime import datetime
from supabase import create_client, Client

# ============================================
# CONFIGURATION
# ============================================

# Notion API Configuration
NOTION_API_KEY = ""  # Set this to your Notion integration token
NOTION_DATABASE_ID = ""  # Set this to your Notion database ID (from URL)
NOTION_API_VERSION = "2022-06-28"
NOTION_BASE_URL = "https://api.notion.com/v1"

# Supabase Configuration
SUPABASE_URL = "https://wjkfhefvxucqtuxttlsz.supabase.co"
SUPABASE_SERVICE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Indqa2ZoZWZ2eHVjcXR1eHR0bHN6Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTcyNDE4MTM3NiwiZXhwIjoyMDM5NzU3Mzc2fQ.6XWO5a0bTLYE2LRB5G3AQ_c2w8mxIoTWAFGvxPPgYag"
TENANT_ID = "5443b130-cc28-45af-a420-cd500b288890"

# Column Mapping Configuration
# Maps Notion property names to mechanic_jobs columns
COLUMN_MAPPING = {
    # Format: "Notion Property Name": "database_column_name"
    "Customer": "customer_name",  # Will lookup customer_id
    "Cliente": "customer_name",
    "Bike": "bike_description",
    "Bicicleta": "bike_description",
    "Status": "status",
    "Estado": "status",
    "Description": "description",
    "Descripción": "description",
    "Labor Cost": "labor_cost",
    "Costo Mano de Obra": "labor_cost",
    "Start Date": "start_date",
    "Fecha Inicio": "start_date",
    "Completion Date": "completion_date",
    "Fecha Término": "completion_date",
    "Notes": "notes",
    "Notas": "notes",
    "Phone": "customer_phone",
    "Teléfono": "customer_phone",
    "Email": "customer_email",
}

# Status Mapping (Notion → Database)
STATUS_MAPPING = {
    "Pending": "pending",
    "Pendiente": "pending",
    "In Progress": "in_progress",
    "En Progreso": "in_progress",
    "Completed": "completed",
    "Completado": "completed",
    "Ready for Delivery": "ready_for_delivery",
    "Listo para Entrega": "ready_for_delivery",
}


class NotionPegasSync:
    def __init__(self):
        if not NOTION_API_KEY or not NOTION_DATABASE_ID:
            raise ValueError("NOTION_API_KEY and NOTION_DATABASE_ID must be set")
        
        self.notion_headers = {
            "Authorization": f"Bearer {NOTION_API_KEY}",
            "Notion-Version": NOTION_API_VERSION,
            "Content-Type": "application/json"
        }
        
        self.supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
        self.discovered_mapping = {}
        
        print(f"✅ Initialized Notion Sync")
        print(f"   Database ID: {NOTION_DATABASE_ID}")
        print(f"   Tenant: {TENANT_ID}\n")
    
    def discover_database_schema(self) -> Dict:
        """Auto-discover Notion database schema"""
        print("🔍 Auto-discovering Notion database schema...")
        
        url = f"{NOTION_BASE_URL}/databases/{NOTION_DATABASE_ID}"
        response = requests.get(url, headers=self.notion_headers)
        
        if response.status_code != 200:
            raise Exception(f"Failed to fetch database schema: {response.text}")
        
        data = response.json()
        properties = data.get("properties", {})
        
        print(f"\n📋 Found {len(properties)} properties in Notion database:\n")
        
        for prop_name, prop_data in properties.items():
            prop_type = prop_data.get("type")
            print(f"   • {prop_name} ({prop_type})")
        
        print()
        return properties
    
    def smart_map_columns(self, notion_properties: Dict) -> Dict:
        """Intelligently map Notion properties to database columns"""
        print("🧠 Smart mapping Notion properties to database columns...\n")
        
        mapping = {}
        
        # Keywords for semantic matching
        keyword_map = {
            "customer": ["customer", "cliente", "client", "name"],
            "bike": ["bike", "bicicleta", "bicycle", "modelo", "model"],
            "status": ["status", "estado", "state"],
            "description": ["description", "descripción", "desc", "details", "detalles"],
            "labor": ["labor", "mano de obra", "cost", "costo", "precio"],
            "start": ["start", "inicio", "fecha inicio", "start date"],
            "completion": ["completion", "término", "end", "fin", "fecha término"],
            "notes": ["notes", "notas", "comments", "comentarios"],
            "phone": ["phone", "teléfono", "tel", "celular"],
            "email": ["email", "correo", "mail"],
        }
        
        db_column_targets = {
            "customer": "customer_name",
            "bike": "bike_description",
            "status": "status",
            "description": "description",
            "labor": "labor_cost",
            "start": "start_date",
            "completion": "completion_date",
            "notes": "notes",
            "phone": "customer_phone",
            "email": "customer_email",
        }
        
        for prop_name in notion_properties.keys():
            prop_lower = prop_name.lower()
            
            # Try exact match first
            if prop_name in COLUMN_MAPPING:
                target = COLUMN_MAPPING[prop_name]
                mapping[prop_name] = target
                print(f"   ✅ {prop_name} → {target} (exact match)")
                continue
            
            # Try semantic matching
            matched = False
            for key, keywords in keyword_map.items():
                if any(kw in prop_lower for kw in keywords):
                    target = db_column_targets[key]
                    mapping[prop_name] = target
                    print(f"   ✅ {prop_name} → {target} (semantic match: {key})")
                    matched = True
                    break
            
            if not matched:
                print(f"   ⚠️  {prop_name} → (no mapping found, will skip)")
        
        print()
        return mapping

    def fetch_notion_database(self) -> List[Dict]:
        """Fetch all pages from Notion database with pagination"""
        print("📦 Fetching data from Notion database...")
        
        all_pages = []
        has_more = True
        start_cursor = None
        page_num = 1
        
        while has_more:
            url = f"{NOTION_BASE_URL}/databases/{NOTION_DATABASE_ID}/query"
            
            payload = {}
            if start_cursor:
                payload["start_cursor"] = start_cursor
            
            response = requests.post(url, headers=self.notion_headers, json=payload)
            
            if response.status_code != 200:
                raise Exception(f"Failed to fetch Notion data: {response.text}")
            
            data = response.json()
            pages = data.get("results", [])
            all_pages.extend(pages)
            
            has_more = data.get("has_more", False)
            start_cursor = data.get("next_cursor")
            
            print(f"   Fetched page {page_num} ({len(all_pages)} records so far)")
            page_num += 1
            
            time.sleep(0.3)  # Rate limiting
        
        print(f"✅ Total Notion records fetched: {len(all_pages)}\n")
        return all_pages

    def extract_property_value(self, prop: Dict) -> Any:
        """Extract value from Notion property based on type"""
        prop_type = prop.get("type")
        
        if prop_type == "title":
            texts = prop.get("title", [])
            return " ".join([t.get("plain_text", "") for t in texts]) if texts else None
        
        elif prop_type == "rich_text":
            texts = prop.get("rich_text", [])
            return " ".join([t.get("plain_text", "") for t in texts]) if texts else None
        
        elif prop_type == "number":
            return prop.get("number")
        
        elif prop_type == "select":
            select = prop.get("select")
            return select.get("name") if select else None
        
        elif prop_type == "multi_select":
            items = prop.get("multi_select", [])
            return [item.get("name") for item in items]
        
        elif prop_type == "date":
            date = prop.get("date")
            if date:
                start = date.get("start")
                return start if start else None
            return None
        
        elif prop_type == "people":
            people = prop.get("people", [])
            return [p.get("name", "") for p in people]
        
        elif prop_type == "checkbox":
            return prop.get("checkbox", False)
        
        elif prop_type == "url":
            return prop.get("url")
        
        elif prop_type == "email":
            return prop.get("email")
        
        elif prop_type == "phone_number":
            return prop.get("phone_number")
        
        else:
            return None

    def map_notion_to_pega(self, notion_page: Dict) -> Dict:
        """Map Notion page properties to mechanic_jobs columns"""
        properties = notion_page.get("properties", {})
        
        mapped_data = {
            "tenant_id": TENANT_ID,
            "created_at": notion_page.get("created_time"),
            "updated_at": notion_page.get("last_edited_time"),
        }
        
        # Extract Notion page ID for reference
        notion_id = notion_page.get("id", "")
        mapped_data["notion_id"] = notion_id
        
        # Map properties using discovered mapping
        for notion_prop_name, prop_data in properties.items():
            # Check if this property is mapped
            db_column = self.discovered_mapping.get(notion_prop_name)
            
            if db_column:
                value = self.extract_property_value(prop_data)
                
                # Special handling for status
                if db_column == "status" and value:
                    value = STATUS_MAPPING.get(value, value.lower().replace(" ", "_"))
                
                # Special handling for labor_cost
                if db_column == "labor_cost" and value:
                    mapped_data["labor_cost"] = float(value)
                    continue
                
                mapped_data[db_column] = value
        
        return mapped_data

    def find_or_create_customer(self, customer_name: str, phone: str = None, email: str = None) -> Optional[str]:
        """Find existing customer or create new one"""
        if not customer_name:
            return None
        
        # Search by name
        result = self.supabase.table("customers").select("id").eq(
            "tenant_id", TENANT_ID
        ).ilike("name", customer_name).execute()
        
        if result.data and len(result.data) > 0:
            return result.data[0]["id"]
        
        # Create new customer
        customer_data = {
            "tenant_id": TENANT_ID,
            "name": customer_name,
            "phone": phone,
            "email": email,
            "customer_type": "individual"
        }
        
        result = self.supabase.table("customers").insert(customer_data).execute()
        
        if result.data and len(result.data) > 0:
            print(f"   ✅ Created new customer: {customer_name}")
            return result.data[0]["id"]
        
        return None

    def sync_to_database(self, notion_pages: List[Dict]):
        """Sync Notion pages to mechanic_jobs table"""
        print("🔄 Syncing to database...\n")
        
        stats = {
            "created": 0,
            "updated": 0,
            "skipped": 0,
            "errors": 0
        }
        
        for page in notion_pages:
            try:
                mapped_data = self.map_notion_to_pega(page)
                
                # Get customer info
                customer_name = mapped_data.pop("customer_name", None)
                customer_phone = mapped_data.pop("customer_phone", None)
                customer_email = mapped_data.pop("customer_email", None)
                
                # Find or create customer
                if customer_name:
                    customer_id = self.find_or_create_customer(
                        customer_name, 
                        customer_phone, 
                        customer_email
                    )
                    if customer_id:
                        mapped_data["customer_id"] = customer_id
                
                notion_id = mapped_data.get("notion_id")
                
                # Check if already exists
                existing = self.supabase.table("mechanic_jobs").select("id").eq(
                    "tenant_id", TENANT_ID
                ).eq("notion_id", notion_id).execute()
                
                if existing.data and len(existing.data) > 0:
                    # Update existing
                    job_id = existing.data[0]["id"]
                    self.supabase.table("mechanic_jobs").update(mapped_data).eq("id", job_id).execute()
                    stats["updated"] += 1
                    print(f"✅ Updated: {mapped_data.get('bike_description', 'Unknown')}")
                else:
                    # Create new
                    self.supabase.table("mechanic_jobs").insert(mapped_data).execute()
                    stats["created"] += 1
                    print(f"✅ Created: {mapped_data.get('bike_description', 'Unknown')}")
                
            except Exception as e:
                stats["errors"] += 1
                print(f"❌ Error: {e}")
                continue
        
        # Print summary
        print("\n" + "=" * 60)
        print("📊 SYNC SUMMARY")
        print("=" * 60)
        print(f"Created:  {stats['created']}")
        print(f"Updated:  {stats['updated']}")
        print(f"Skipped:  {stats['skipped']}")
        print(f"Errors:   {stats['errors']}")
        print("=" * 60)


def main():
    print("\n🚀 Notion → Pegas Sync Script\n")
    
    if not NOTION_API_KEY:
        print("❌ Error: NOTION_API_KEY not set")
        print("\nTo get your integration token:")
        print("1. Go to https://www.notion.so/my-integrations")
        print("2. Create a new integration")
        print("3. Copy the 'Internal Integration Token'")
        print("4. Share your database with the integration")
        sys.exit(1)
    
    if not NOTION_DATABASE_ID:
        print("❌ Error: NOTION_DATABASE_ID not set")
        print("\nTo get your database ID:")
        print("1. Open your Notion database")
        print("2. Copy the URL (e.g., https://notion.so/workspace/DATABASE_ID?v=...)")
        print("3. Extract the 32-character ID before '?v='")
        sys.exit(1)
    
    try:
        syncer = NotionPegasSync()
        
        # Auto-discover schema
        notion_schema = syncer.discover_database_schema()
        
        # Smart map columns
        syncer.discovered_mapping = syncer.smart_map_columns(notion_schema)
        
        if not syncer.discovered_mapping:
            print("⚠️  No column mappings found. Check your database properties.")
            return
        
        # Fetch from Notion
        notion_pages = syncer.fetch_notion_database()
        
        if not notion_pages:
            print("⚠️  No data found in Notion database")
            return
        
        # Sync to database
        syncer.sync_to_database(notion_pages)
        
        print("\n✅ Sync complete!")
        
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
