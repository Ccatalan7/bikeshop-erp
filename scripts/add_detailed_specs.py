#!/usr/bin/env python3
"""
Add detailed specs to existing bikes in catalog
This populates the technical fields that Bike Index doesn't provide
"""

import os
from dotenv import load_dotenv
from supabase import create_client, Client

load_dotenv()

SUPABASE_URL = os.getenv('SUPABASE_URL')
SUPABASE_KEY = os.getenv('SUPABASE_SERVICE_ROLE_KEY')

# Detailed specs for each bike
BIKE_SPECS = {
    'Marlin': {
        'frame_material': 'Alpha Silver Aluminum',
        'wheel_size': '29"',
        'frame_size_range': ['XS', 'S', 'M', 'L', 'XL', 'XXL'],
        'weight_kg': 14.5,
        'msrp_usd': 629.99,
        
        # Drivetrain
        'drivetrain_speeds': 21,
        'drivetrain_config': '3x7',
        'cassette_range': '14-34T',
        'cassette_max_teeth': 34,
        'chain_speeds': 7,
        'crankset_model': 'ProWheel, 48/38/28',
        'front_derailleur_model': 'Shimano Tourney TY710',
        'rear_derailleur_model': 'Shimano Tourney TY300',
        
        # Brakes
        'brake_type': 'hydraulic_disc',
        'brake_model': 'Tektro HD-M276',
        'brake_rotor_size_front_mm': 160,
        'brake_rotor_size_rear_mm': 160,
        
        # Wheels & Hubs
        'front_hub_model': 'Formula DC-20',
        'rear_hub_model': 'Formula DC-22',
        'front_hub_spacing_mm': 100,
        'rear_hub_spacing_mm': 142,
        'front_axle_type': 'QR',
        'rear_axle_type': 'QR',
        'freehub_type': 'shimano_hg',
        'spoke_count': 32,
        
        # Tires
        'tire_size_front': '29x2.2"',
        'tire_size_rear': '29x2.2"',
        'max_tire_width_mm': 57,
        
        # Cockpit
        'handlebar_type': 'flat',
        'stem_length_mm': 90,
        'seatpost_diameter_mm': 31.6,
    },
    
    'Domane': {
        'frame_material': 'Alpha Aluminum',
        'wheel_size': '700c',
        'frame_size_range': ['47cm', '50cm', '52cm', '54cm', '56cm', '58cm', '60cm', '62cm'],
        'weight_kg': 10.2,
        'msrp_usd': 1099.99,
        
        # Drivetrain
        'drivetrain_speeds': 16,
        'drivetrain_config': '2x8',
        'cassette_range': '11-32T',
        'cassette_max_teeth': 32,
        'chain_speeds': 8,
        'crankset_model': 'Shimano Claris, 50/34',
        'front_derailleur_model': 'Shimano Claris',
        'rear_derailleur_model': 'Shimano Claris',
        
        # Brakes
        'brake_type': 'rim',
        'brake_model': 'Tektro rim brakes',
        
        # Wheels & Hubs
        'front_hub_model': 'Formula RB-51',
        'rear_hub_model': 'Formula RB-52',
        'front_hub_spacing_mm': 100,
        'rear_hub_spacing_mm': 130,
        'front_axle_type': 'QR',
        'rear_axle_type': 'QR',
        'freehub_type': 'shimano_hg',
        'spoke_count': 28,
        
        # Tires
        'tire_size_front': '700x28c',
        'tire_size_rear': '700x28c',
        'max_tire_width_mm': 32,
        
        # Cockpit
        'handlebar_type': 'drop',
        'stem_length_mm': 100,
        'seatpost_diameter_mm': 27.2,
    },
    
    'Rockhopper': {
        'frame_material': 'M4 Aluminum',
        'wheel_size': '27.5"',
        'frame_size_range': ['XS', 'S', 'M', 'L', 'XL'],
        'weight_kg': 13.8,
        'msrp_usd': 750.00,
        
        # Drivetrain
        'drivetrain_speeds': 18,
        'drivetrain_config': '2x9',
        'cassette_range': '11-36T',
        'cassette_max_teeth': 36,
        'chain_speeds': 9,
        'crankset_model': 'Shimano Alivio, 36/22',
        'front_derailleur_model': 'Shimano Alivio',
        'rear_derailleur_model': 'Shimano Alivio',
        
        # Brakes
        'brake_type': 'hydraulic_disc',
        'brake_model': 'Tektro HD-M275',
        'brake_rotor_size_front_mm': 180,
        'brake_rotor_size_rear_mm': 160,
        
        # Wheels & Hubs
        'front_hub_model': 'Specialized Hi Lo disc',
        'rear_hub_model': 'Specialized Hi Lo disc',
        'front_hub_spacing_mm': 100,
        'rear_hub_spacing_mm': 142,
        'front_axle_type': 'QR',
        'rear_axle_type': 'thru_12mm',
        'freehub_type': 'shimano_hg',
        'spoke_count': 32,
        
        # Tires
        'tire_size_front': '27.5x2.3"',
        'tire_size_rear': '27.5x2.3"',
        'max_tire_width_mm': 65,
        
        # Cockpit
        'handlebar_type': 'riser',
        'stem_length_mm': 80,
        'seatpost_diameter_mm': 30.9,
    },
    
    'Escape': {
        'frame_material': 'ALUXX-Grade Aluminum',
        'wheel_size': '700c',
        'frame_size_range': ['XS', 'S', 'M', 'L', 'XL'],
        'weight_kg': 12.5,
        'msrp_usd': 630.00,
        
        # Drivetrain
        'drivetrain_speeds': 21,
        'drivetrain_config': '3x7',
        'cassette_range': '12-32T',
        'cassette_max_teeth': 32,
        'chain_speeds': 7,
        'crankset_model': 'ProWheel, 48/38/28',
        'front_derailleur_model': 'Shimano Tourney',
        'rear_derailleur_model': 'Shimano Tourney',
        
        # Brakes
        'brake_type': 'rim',
        'brake_model': 'Tektro V-brake',
        
        # Wheels & Hubs
        'front_hub_model': 'Giant GX03V',
        'rear_hub_model': 'Giant GX03V',
        'front_hub_spacing_mm': 100,
        'rear_hub_spacing_mm': 135,
        'front_axle_type': 'QR',
        'rear_axle_type': 'QR',
        'freehub_type': 'shimano_hg',
        'spoke_count': 32,
        
        # Tires
        'tire_size_front': '700x35c',
        'tire_size_rear': '700x35c',
        'max_tire_width_mm': 42,
        
        # Cockpit
        'handlebar_type': 'flat',
        'stem_length_mm': 90,
        'seatpost_diameter_mm': 30.9,
    },
}


def update_bike_specs():
    """Update bikes with detailed specs"""
    supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
    
    print("🔧 Adding detailed specs to bikes...\n")
    
    # Get all bikes
    bikes = supabase.table('bike_catalog').select('*').execute()
    
    updated = 0
    for bike in bikes.data:
        # Find matching spec template
        model_name = bike['model_name']
        specs = None
        
        for key in BIKE_SPECS:
            if key.lower() in model_name.lower():
                specs = BIKE_SPECS[key]
                break
        
        if not specs:
            print(f"⚠️  No spec template for: {model_name}")
            continue
        
        print(f"🔧 Updating: {model_name}")
        
        # Update with detailed specs
        result = supabase.table('bike_catalog').update(specs).eq('id', bike['id']).execute()
        
        if result.data:
            print(f"✅ Updated {len(specs)} fields")
            updated += 1
        else:
            print(f"❌ Failed to update")
    
    print(f"\n📊 Summary: {updated}/{len(bikes.data)} bikes updated with detailed specs")
    print("\n✅ Done! Now you can see full specs in the Bike Encyclopedia page!")


if __name__ == '__main__':
    update_bike_specs()
