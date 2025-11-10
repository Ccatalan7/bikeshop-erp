#!/usr/bin/env python3
"""
Seed bikes and wheel building data directly into Supabase
Run: python3 seed_bikes_wheels.py
"""

from supabase import create_client
import os

# Supabase credentials
SUPABASE_URL = "https://xzdvtzdqjeyqxnkqprtf.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh6ZHZ0emRxamV5cXhua3FwcnRmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MjcyODY1NDksImV4cCI6MjA0Mjg2MjU0OX0.z1fZMoSzPL8Dt03d7i-xC4JFBxgIvXXBrYzpH9M3afo"

EMAIL = "vinabikechile@gmail.com"
PASSWORD = "000000"

def main():
    print("🚀 Starting comprehensive bike & wheel seed...")
    
    # Initialize Supabase client
    client = create_client(SUPABASE_URL, SUPABASE_KEY)
    
    # Sign in
    print(f"🔐 Signing in as {EMAIL}...")
    auth_response = client.auth.sign_in_with_password(
        credentials={"email": EMAIL, "password": PASSWORD}
    )
    
    print("✅ Logged in successfully")
    
    # Get tenant_id
    print("📋 Fetching tenant_id...")
    user_id = client.auth.get_user().user.id
    user_profile = client.table('user_profiles').select('tenant_id').eq('user_id', user_id).execute()
    tenant_id = user_profile.data[0]['tenant_id']
    print(f"✅ Found tenant_id: {tenant_id}")
    
    # Cleanup
    print("\n🧹 Cleaning up existing data...")
    client.table('wheel_builds').delete().eq('tenant_id', tenant_id).execute()
    client.table('wheel_spokes').delete().eq('tenant_id', tenant_id).execute()
    client.table('wheel_rims').delete().eq('tenant_id', tenant_id).execute()
    client.table('wheel_hubs').delete().eq('tenant_id', tenant_id).execute()
    # Don't delete all bikes, just note how many exist
    existing_bikes = client.table('bikes').select('*', count='exact').eq('tenant_id', tenant_id).execute()
    print(f"ℹ️  Keeping {existing_bikes.count} existing bikes")
    print("✅ Cleanup complete")
    
    # Add more diverse bikes
    print("\n🚴 Adding bikes...")
    bikes = [
        {
            'tenant_id': tenant_id,
            'brand': 'Trek',
            'model': 'X-Caliber 8',
            'year': 2024,
            'serial_number': 'TRK29001',
            'frame_number': 'WTU29XC8001',
            'wheel_size': '29"',
            'frame_size': 'L',
            'color': 'Matte Black',
            'bike_type': 'Mountain',
            'status': 'available',
            'purchase_price': 650000,
            'sale_price': 890000,
            'notes': 'Cross-country hardtail, 29" wheels with 32H hubs',
        },
        {
            'tenant_id': tenant_id,
            'brand': 'Specialized',
            'model': 'Rockhopper Comp 29',
            'year': 2024,
            'serial_number': 'SPZ29002',
            'frame_number': 'WSBC29RH002',
            'wheel_size': '29"',
            'frame_size': 'M',
            'color': 'Gloss Red',
            'bike_type': 'Mountain',
            'status': 'available',
            'purchase_price': 580000,
            'sale_price': 780000,
        },
        {
            'tenant_id': tenant_id,
            'brand': 'Scott',
            'model': 'Scale 970',
            'year': 2024,
            'serial_number': 'SCT275004',
            'frame_number': 'SCT275SC004',
            'wheel_size': '27.5"',
            'frame_size': 'M',
            'color': 'Green/Black',
            'bike_type': 'Mountain',
            'status': 'available',
            'purchase_price': 720000,
            'sale_price': 950000,
        },
        {
            'tenant_id': tenant_id,
            'brand': 'Cervélo',
            'model': 'R3 Ultegra',
            'year': 2024,
            'serial_number': 'CRV700007',
            'frame_number': 'CVL700R3007',
            'wheel_size': '700c',
            'frame_size': '54cm',
            'color': 'Matte Carbon',
            'bike_type': 'Road',
            'status': 'available',
            'purchase_price': 2800000,
            'sale_price': 3500000,
        },
        {
            'tenant_id': tenant_id,
            'brand': 'Specialized',
            'model': 'Diverge E5 Comp',
            'year': 2024,
            'serial_number': 'SPZ700010',
            'frame_number': 'SBC700DV010',
            'wheel_size': '700c',
            'frame_size': '54cm',
            'color': 'Forest Green',
            'bike_type': 'Gravel',
            'status': 'available',
            'purchase_price': 1350000,
            'sale_price': 1750000,
        },
    ]
    
    result = client.table('bikes').insert(bikes).execute()
    print(f"✅ Added {len(result.data)} bikes")
    
    # Add hubs
    print("\n📦 Adding hubs...")
    hubs = [
        # 32H hubs
        {
            'tenant_id': tenant_id,
            'name': 'Shimano Deore M6010 Front 32H',
            'brand': 'Shimano',
            'spoke_holes': 32,
            'hub_type': 'front',
            'left_flange_diameter_mm': 50.0,
            'right_flange_diameter_mm': 50.0,
            'left_center_to_flange_mm': 28.0,
            'right_center_to_flange_mm': 20.0,
            'axle_standard': '15x110mm Boost',
            'brake_type': 'Disc',
            'price': 45000,
        },
        {
            'tenant_id': tenant_id,
            'name': 'Shimano Deore M6010 Rear 32H',
            'brand': 'Shimano',
            'spoke_holes': 32,
            'hub_type': 'rear',
            'left_flange_diameter_mm': 53.0,
            'right_flange_diameter_mm': 53.0,
            'left_center_to_flange_mm': 30.0,
            'right_center_to_flange_mm': 18.0,
            'axle_standard': '12x148mm Boost',
            'brake_type': 'Disc',
            'freehub_type': 'Shimano HG',
            'price': 65000,
        },
        # 28H hubs
        {
            'tenant_id': tenant_id,
            'name': 'Shimano Ultegra R8170 Front 28H',
            'brand': 'Shimano',
            'spoke_holes': 28,
            'hub_type': 'front',
            'left_flange_diameter_mm': 45.0,
            'right_flange_diameter_mm': 45.0,
            'left_center_to_flange_mm': 26.0,
            'right_center_to_flange_mm': 19.0,
            'axle_standard': '12x100mm',
            'brake_type': 'Disc',
            'price': 85000,
        },
    ]
    
    result = client.table('wheel_hubs').insert(hubs).execute()
    print(f"✅ Added {len(result.data)} hubs")
    
    # Add rims
    print("\n📦 Adding rims...")
    rims = [
        # 29" rims
        {
            'tenant_id': tenant_id,
            'name': 'DT Swiss XM421 29" (ERD 602mm) 32H',
            'brand': 'DT Swiss',
            'wheel_size': '29"',
            'erd_mm': 602.0,
            'spoke_holes': 32,
            'internal_width_mm': 25.0,
            'external_width_mm': 30.0,
            'rim_type': 'tubeless',
            'material': 'aluminum',
            'price': 85000,
        },
        {
            'tenant_id': tenant_id,
            'name': 'Stan\'s NoTubes Arch MK4 29" (ERD 605mm) 32H',
            'brand': 'Stan\'s NoTubes',
            'wheel_size': '29"',
            'erd_mm': 605.0,
            'spoke_holes': 32,
            'internal_width_mm': 26.0,
            'external_width_mm': 30.0,
            'rim_type': 'tubeless',
            'material': 'aluminum',
            'price': 95000,
        },
        # 27.5" rims
        {
            'tenant_id': tenant_id,
            'name': 'DT Swiss EX511 27.5" (ERD 559mm) 32H',
            'brand': 'DT Swiss',
            'wheel_size': '27.5"',
            'erd_mm': 559.0,
            'spoke_holes': 32,
            'internal_width_mm': 30.0,
            'external_width_mm': 35.0,
            'rim_type': 'tubeless',
            'material': 'aluminum',
            'price': 98000,
        },
        # 700c rims
        {
            'tenant_id': tenant_id,
            'name': 'Mavic Open Pro 700c (ERD 622mm) 28H',
            'brand': 'Mavic',
            'wheel_size': '700c',
            'erd_mm': 622.0,
            'spoke_holes': 28,
            'internal_width_mm': 17.0,
            'external_width_mm': 23.0,
            'rim_type': 'clincher',
            'material': 'aluminum',
            'price': 65000,
        },
        {
            'tenant_id': tenant_id,
            'name': 'HED Belgium Plus 700c (ERD 622mm) 32H',
            'brand': 'HED',
            'wheel_size': '700c',
            'erd_mm': 622.0,
            'spoke_holes': 32,
            'internal_width_mm': 21.0,
            'external_width_mm': 25.0,
            'rim_type': 'tubeless',
            'material': 'aluminum',
            'price': 125000,
        },
    ]
    
    result = client.table('wheel_rims').insert(rims).execute()
    print(f"✅ Added {len(result.data)} rims")
    
    # Add spokes
    print("\n📦 Adding spokes...")
    spokes = [
        {
            'tenant_id': tenant_id,
            'name': 'DT Swiss Competition 290mm Black',
            'brand': 'DT Swiss',
            'length_mm': 290,
            'gauge': '2.0/1.8mm',
            'material': 'Stainless Steel',
            'color': 'Black',
            'head_type': 'J-bend',
            'price': 650,
            'stock_quantity': 100,
        },
        {
            'tenant_id': tenant_id,
            'name': 'DT Swiss Competition 292mm Black',
            'brand': 'DT Swiss',
            'length_mm': 292,
            'gauge': '2.0/1.8mm',
            'material': 'Stainless Steel',
            'color': 'Black',
            'head_type': 'J-bend',
            'price': 650,
            'stock_quantity': 100,
        },
        {
            'tenant_id': tenant_id,
            'name': 'Sapim Race 294mm Silver',
            'brand': 'Sapim',
            'length_mm': 294,
            'gauge': '2.0/1.8mm',
            'material': 'Stainless Steel',
            'color': 'Silver',
            'head_type': 'J-bend',
            'price': 580,
            'stock_quantity': 100,
        },
    ]
    
    result = client.table('wheel_spokes').insert(spokes).execute()
    print(f"✅ Added {len(result.data)} spokes")
    
    # Summary
    print("\n✨ Seed complete! Summary:")
    print(f"  🚴 Bikes: {len(bikes)} new + {existing_bikes.count} existing")
    print(f"  📦 Hubs: {len(hubs)}")
    print(f"  📦 Rims: {len(rims)}")
    print(f"  📦 Spokes: {len(spokes)}")
    print("\n🎯 Ready to test the Smart Wizard!")
    print("   Navigate to Taller → Wheel Builder Wizard")

if __name__ == "__main__":
    main()
