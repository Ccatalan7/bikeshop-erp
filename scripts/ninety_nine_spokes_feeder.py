#!/usr/bin/env python3
"""
99 Spokes Bike Catalog Feeder
Fetches comprehensive bike specs from 99spokes.com API
"""

import os
import requests
from typing import Dict, List, Optional
from dotenv import load_dotenv
from supabase import create_client, Client

load_dotenv()

SUPABASE_URL = os.getenv('SUPABASE_URL')
SUPABASE_KEY = os.getenv('SUPABASE_SECRET_KEY')


class NinetyNineSpokesClient:
    """Client for 99 Spokes API"""
    
    BASE_URL = 'https://99spokes.com/api'
    
    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'BikeShopERP/1.0',
            'Accept': 'application/json'
        })
    
    def search_bikes(self, brand: str, model: str, year: int) -> List[Dict]:
        """Search for bikes by brand, model, and year"""
        try:
            # Try their search endpoint
            search_query = f"{brand} {model} {year}"
            response = self.session.get(
                f"{self.BASE_URL}/bikes",
                params={'q': search_query, 'year': year},
                timeout=10
            )
            
            if response.status_code == 200:
                return response.json().get('bikes', [])
            
            print(f"⚠️  API returned {response.status_code}")
            return []
            
        except Exception as e:
            print(f"❌ Search error: {e}")
            return []
    
    def get_bike_details(self, bike_slug: str) -> Optional[Dict]:
        """Get detailed specs for a specific bike"""
        try:
            response = self.session.get(
                f"{self.BASE_URL}/bikes/{bike_slug}",
                timeout=10
            )
            
            if response.status_code == 200:
                return response.json()
            
            return None
            
        except Exception as e:
            print(f"❌ Details error: {e}")
            return None
    
    def normalize_bike_data(self, bike_data: Dict) -> Dict:
        """Convert 99 Spokes data to our schema"""
        
        # Extract specs
        specs = bike_data.get('specs', {})
        frame = specs.get('frame', {})
        drivetrain = specs.get('drivetrain', {})
        brakes = specs.get('brakes', {})
        wheels = specs.get('wheels', {})
        
        return {
            'brand': bike_data.get('brand', {}).get('name', 'Unknown'),
            'model_name': bike_data.get('model', 'Unknown'),
            'model_year': bike_data.get('year'),
            'bike_type': bike_data.get('category', '').lower(),
            
            # Frame
            'frame_material': frame.get('material'),
            'wheel_size': frame.get('wheel_size'),
            'frame_sizes_available': bike_data.get('sizes', []),
            'weight_kg': specs.get('weight', {}).get('value'),
            'msrp_usd': bike_data.get('msrp', {}).get('usd'),
            
            # Drivetrain
            'speeds': drivetrain.get('speeds'),
            'drivetrain_config': drivetrain.get('config'),
            'cassette_range': drivetrain.get('cassette', {}).get('range'),
            'cassette_max_teeth': drivetrain.get('cassette', {}).get('max_teeth'),
            'chain_speeds': drivetrain.get('chain', {}).get('speeds'),
            'crankset_model': drivetrain.get('crankset', {}).get('model'),
            'front_derailleur_model': drivetrain.get('front_derailleur', {}).get('model'),
            'rear_derailleur_model': drivetrain.get('rear_derailleur', {}).get('model'),
            
            # Brakes
            'brake_type': brakes.get('type'),
            'brake_model': brakes.get('model'),
            'rotor_size_front_mm': brakes.get('rotor_front', {}).get('size_mm'),
            'rotor_size_rear_mm': brakes.get('rotor_rear', {}).get('size_mm'),
            
            # Wheels & Hubs
            'hub_front_model': wheels.get('hub_front', {}).get('model'),
            'hub_rear_model': wheels.get('hub_rear', {}).get('model'),
            'hub_front_spacing_mm': wheels.get('hub_front', {}).get('spacing_mm'),
            'hub_rear_spacing_mm': wheels.get('hub_rear', {}).get('spacing_mm'),
            'hub_front_axle_type': wheels.get('hub_front', {}).get('axle_type'),
            'hub_rear_axle_type': wheels.get('hub_rear', {}).get('axle_type'),
            'freehub_type': wheels.get('freehub', {}).get('type'),
            'spoke_count_front': wheels.get('spokes_front'),
            'spoke_count_rear': wheels.get('spokes_rear'),
            
            # Tires
            'tire_size_front': specs.get('tires', {}).get('front', {}).get('size'),
            'tire_size_rear': specs.get('tires', {}).get('rear', {}).get('size'),
            'tire_max_width_mm': specs.get('tires', {}).get('max_width_mm'),
            
            # Cockpit
            'handlebar_type': specs.get('cockpit', {}).get('handlebar', {}).get('model'),
            'stem_length_mm': specs.get('cockpit', {}).get('stem', {}).get('length_mm'),
            'seatpost_diameter_mm': specs.get('cockpit', {}).get('seatpost', {}).get('diameter_mm'),
            
            # Metadata
            'manufacturer_url': bike_data.get('url'),
            'image_url': bike_data.get('images', [{}])[0].get('url') if bike_data.get('images') else None,
            'full_specs_json': bike_data,
            'data_source': '99spokes',
            'data_confidence': 0.95,  # High confidence for curated data
            'external_id': bike_data.get('slug'),
        }


class NinetyNineSpokesFeeder:
    """Main feeder class using 99 Spokes API"""
    
    def __init__(self):
        self.client = NinetyNineSpokesClient()
        self.supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
    
    def fetch_and_store_bike(self, brand: str, model: str, year: int) -> Optional[Dict]:
        """Fetch bike from 99 Spokes and store in database"""
        
        print(f"🔍 Searching 99 Spokes: {brand} {model} {year}")
        
        try:
            bikes = self.client.search_bikes(brand, model, year)
            
            if not bikes:
                print(f"❌ No bikes found")
                return None
            
            # Get first result details
            bike_slug = bikes[0].get('slug')
            print(f"📥 Fetching details for: {bike_slug}")
            
            bike_data = self.client.get_bike_details(bike_slug)
            
            if not bike_data:
                print(f"❌ Could not fetch details")
                return None
            
            normalized = self.client.normalize_bike_data(bike_data)
            
            print(f"✅ Found: {normalized['brand']} {normalized['model_name']} {normalized['model_year']}")
            print(f"   Specs: {normalized['speeds']} speeds, {normalized['brake_type']} brakes, {normalized['wheel_size']} wheels")
            
            # Check if already exists
            existing = self.supabase.table('bike_catalog').select('*').eq('brand', normalized['brand']).eq('model_name', normalized['model_name']).eq('model_year', normalized['model_year']).execute()
            
            if existing.data:
                print(f"⚠️  Already exists, updating...")
                result = self.supabase.table('bike_catalog').update(normalized).eq('id', existing.data[0]['id']).execute()
                print(f"✅ Updated: {result.data[0]['id']}")
                return result.data[0]
            
            # Insert new
            result = self.supabase.table('bike_catalog').insert(normalized).execute()
            print(f"💾 Stored: {result.data[0]['id']}")
            return result.data[0]
            
        except Exception as e:
            print(f"❌ Error: {e}")
            return None
    
    def bulk_feed(self, bikes_list: List[tuple]):
        """Feed multiple bikes at once"""
        results = []
        for brand, model, year in bikes_list:
            result = self.fetch_and_store_bike(brand, model, year)
            results.append(result)
        return results


def main():
    """Demo: Feed popular bikes from 99 Spokes"""
    
    print("🚴 99 Spokes Bike Catalog Feeder\n")
    
    feeder = NinetyNineSpokesFeeder()
    
    # List of bikes to fetch
    bikes = [
        ('Trek', 'Marlin 5', 2024),
        ('Trek', 'Marlin 6', 2024),
        ('Trek', 'Marlin 7', 2024),
        ('Trek', 'FX 3', 2024),
        ('Trek', 'Domane AL 2', 2024),
        ('Specialized', 'Rockhopper', 2024),
        ('Giant', 'Escape 3', 2024),
        ('Cannondale', 'Trail 8', 2024),
    ]
    
    results = feeder.bulk_feed(bikes)
    
    success = sum(1 for r in results if r is not None)
    print(f"\n📊 Summary: {success}/{len(bikes)} bikes added/updated\n")
    print("✅ Done! Check the Bike Encyclopedia page to see detailed specs!")


if __name__ == '__main__':
    main()
