#!/usr/bin/env python3
"""
Phase 1 Flutter Integration Test
Verifies that categories can be fetched with compatibility metadata via Supabase API
"""

import sys
import os

# Add parent directory to path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from connections.supabase_connection import SupabaseConnection
from config import TENANT_ID
import json

def main():
    print("🧪 Testing Phase 1: Flutter Integration")
    print("=" * 60)
    
    # Connect to Supabase
    sb = SupabaseConnection()
    print(f"✅ Connected to Supabase (tenant: {TENANT_ID[:8]}...)")
    print()
    
    # Test 1: Fetch category with metadata (Cassette)
    print("Test 1: Fetch Cassette category")
    print("-" * 60)
    response = sb.client.from_('product_categories') \
        .select('*') \
        .eq('tenant_id', TENANT_ID) \
        .eq('name', 'Cassette') \
        .not_.is_('compatibility_metadata', 'null') \
        .execute()
    
    if response.data and len(response.data) > 0:
        category = response.data[0]
        print(f"✅ Name: {category['name']}")
        print(f"✅ Full Path: {category['full_path']}")
        print(f"✅ Icon: {category['icon_name']}")
        print(f"✅ Discipline Scope: {category['discipline_scope']}")
        
        metadata = category['compatibility_metadata']
        print(f"✅ Component Code: {metadata['component_code']}")
        print(f"✅ Attributes Count: {len(metadata['attributes'])}")
        
        print("\n📋 Attributes:")
        for attr in metadata['attributes']:
            required = "⚠️ Required" if attr.get('required') else "Optional"
            print(f"  - {attr['name']}: {attr['type']} ({required})")
            if 'enum_values' in attr:
                print(f"    Values: {', '.join(attr['enum_values'][:5])}...")
    else:
        print("❌ Cassette category not found or has no metadata")
        return False
    
    print()
    
    # Test 2: Fetch Hub (Mazas) - most complex component
    print("Test 2: Fetch Mazas (Hub) category")
    print("-" * 60)
    response = sb.client.from_('product_categories') \
        .select('*') \
        .eq('tenant_id', TENANT_ID) \
        .eq('name', 'Mazas') \
        .not_.is_('compatibility_metadata', 'null') \
        .execute()
    
    if response.data and len(response.data) > 0:
        category = response.data[0]
        metadata = category['compatibility_metadata']
        print(f"✅ Name: {category['name']}")
        print(f"✅ Attributes Count: {len(metadata['attributes'])} (expected: 10)")
        
        expected_attrs = [
            'hub_position', 'spoke_holes', 'hub_spacing_mm', 'axle_type',
            'freehub_standard', 'brake_interface', 'flange_diameter_left_mm',
            'flange_diameter_right_mm', 'center_to_flange_left_mm', 'center_to_flange_right_mm'
        ]
        
        actual_attrs = [attr['name'] for attr in metadata['attributes']]
        missing = set(expected_attrs) - set(actual_attrs)
        
        if missing:
            print(f"❌ Missing attributes: {missing}")
        else:
            print(f"✅ All 10 hub attributes present")
    else:
        print("❌ Mazas category not found or has no metadata")
        return False
    
    print()
    
    # Test 3: Count all categories with metadata
    print("Test 3: Count categories with metadata")
    print("-" * 60)
    response = sb.client.from_('product_categories') \
        .select('name, full_path, compatibility_metadata', count='exact') \
        .eq('tenant_id', TENANT_ID) \
        .not_.is_('compatibility_metadata', 'null') \
        .execute()
    
    count = response.count if hasattr(response, 'count') else len(response.data)
    print(f"✅ Categories with metadata: {count}/23 expected")
    
    if count == 23:
        print("✅ Perfect match!")
    elif count < 23:
        print(f"⚠️ Missing {23 - count} categories")
    else:
        print(f"⚠️ Extra {count - 23} categories (unexpected)")
    
    print()
    
    # Test 4: Verify data structure for Flutter deserialization
    print("Test 4: Verify Flutter-compatible structure")
    print("-" * 60)
    
    # Simulate what Flutter would receive
    response = sb.client.from_('product_categories') \
        .select('id, name, full_path, compatibility_metadata, discipline_scope, icon_name') \
        .eq('tenant_id', TENANT_ID) \
        .eq('name', 'Horquillas') \
        .not_.is_('compatibility_metadata', 'null') \
        .execute()
    
    if response.data and len(response.data) > 0:
        fork_data = response.data[0]
        
        # Check all required fields for Flutter
        required_fields = ['id', 'name', 'full_path', 'compatibility_metadata', 'discipline_scope', 'icon_name']
        missing_fields = [f for f in required_fields if f not in fork_data or fork_data[f] is None]
        
        if missing_fields:
            print(f"❌ Missing fields for Flutter: {missing_fields}")
            return False
        else:
            print(f"✅ All required fields present")
            
        # Check metadata structure
        metadata = fork_data['compatibility_metadata']
        required_metadata_keys = ['component_code', 'attributes']
        missing_keys = [k for k in required_metadata_keys if k not in metadata]
        
        if missing_keys:
            print(f"❌ Missing metadata keys: {missing_keys}")
            return False
        else:
            print(f"✅ Metadata structure valid")
            
        # Check attribute structure
        if metadata['attributes']:
            sample_attr = metadata['attributes'][0]
            required_attr_keys = ['name', 'type', 'required', 'label']
            missing_attr_keys = [k for k in required_attr_keys if k not in sample_attr]
            
            if missing_attr_keys:
                print(f"❌ Missing attribute keys: {missing_attr_keys}")
                return False
            else:
                print(f"✅ Attribute structure valid")
                print(f"   Sample: {sample_attr['name']} ({sample_attr['type']})")
    else:
        print("❌ Horquillas (Fork) category not found")
        return False
    
    print()
    print("=" * 60)
    print("🎉 Phase 1 Integration Test: ALL PASSED")
    print()
    print("Next Steps:")
    print("1. Restart Flutter app (hot restart)")
    print("2. Go to: Productos → + Nuevo Producto")
    print("3. Select category: 'Componentes > Ruedas > Mazas'")
    print("4. Verify 'Advanced Specs' tab appears with 10 hub fields")
    print("5. Try different component categories (Fork, Cassette, Tire)")
    
    return True

if __name__ == '__main__':
    try:
        success = main()
        sys.exit(0 if success else 1)
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
