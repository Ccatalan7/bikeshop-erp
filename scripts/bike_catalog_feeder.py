#!/usr/bin/env python3
"""
Bike Catalog Feeder - Fetch bike specs from external APIs
Supports: Bike Index API (public, free)
Future: BikeBook.io when available
"""

import requests
import json
from typing import Dict, List, Optional
from supabase import create_client, Client
import os
from dotenv import load_dotenv

load_dotenv()

SUPABASE_URL = os.getenv('SUPABASE_URL', 'https://your-project.supabase.co')
SUPABASE_KEY = os.getenv('SUPABASE_SERVICE_ROLE_KEY', '')

class BikeIndexClient:
    """Client for Bike Index API V3"""
    
    BASE_URL = "https://bikeindex.org/api/v3"
    
    def search_bikes(self, manufacturer: str, model: str, year: Optional[int] = None) -> List[Dict]:
        """Search bikes by manufacturer and model"""
        params = {
            'manufacturer': manufacturer,
            'query': model,
        }
        
        response = requests.get(f"{self.BASE_URL}/search", params=params)
        response.raise_for_status()
        
        data = response.json()
        bikes = data.get('bikes', [])
        
        # Filter by year if specified
        if year:
            bikes = [b for b in bikes if b.get('year') == year]
        
        return bikes
    
    def normalize_bike_data(self, bike_data: Dict) -> Dict:
        """Convert Bike Index data to our schema"""
        
        # Extract specs from description (free text parsing)
        description = bike_data.get('description', '')
        
        return {
            'brand': bike_data.get('manufacturer_name', 'Unknown'),
            'model_name': bike_data.get('frame_model', 'Unknown'),
            'model_year': bike_data.get('year'),
            'bike_type': self._infer_bike_type(bike_data.get('frame_model', '')),
            'frame_material': self._extract_frame_material(description),
            'wheel_size': self._extract_wheel_size(description),
            'image_url': bike_data.get('large_img') or bike_data.get('thumb'),
            'full_specs_json': bike_data,
            'data_source': 'bike_index',
            'data_confidence': 0.6,  # Lower confidence for user-submitted data
            'external_id': str(bike_data.get('id')),
        }
    
    def _infer_bike_type(self, model: str) -> str:
        """Infer bike type from model name"""
        model_lower = model.lower()
        if any(x in model_lower for x in ['marlin', 'x-caliber', 'roscoe', 'fuel']):
            return 'mountain'
        elif any(x in model_lower for x in ['domane', 'émonda', 'madone', 'checkpoint']):
            return 'road'
        elif any(x in model_lower for x in ['fx', 'dual sport', 'verve']):
            return 'hybrid'
        elif 'gravel' in model_lower:
            return 'gravel'
        return None
    
    def _extract_frame_material(self, description: str) -> Optional[str]:
        """Try to extract frame material from description"""
        desc_lower = description.lower()
        if 'carbon' in desc_lower:
            return 'carbon'
        elif 'aluminum' in desc_lower or 'aluminium' in desc_lower:
            return 'aluminum'
        elif 'steel' in desc_lower:
            return 'steel'
        elif 'titanium' in desc_lower:
            return 'titanium'
        return None
    
    def _extract_wheel_size(self, description: str) -> Optional[str]:
        """Try to extract wheel size from description"""
        desc_lower = description.lower()
        if '29' in desc_lower or '29"' in desc_lower:
            return '29"'
        elif '27.5' in desc_lower:
            return '27.5"'
        elif '26' in desc_lower or '26"' in desc_lower:
            return '26"'
        elif '700c' in desc_lower:
            return '700c'
        return None


class BikeCatalogFeeder:
    """Main feeder class to populate bike_catalog table"""
    
    def __init__(self):
        self.bike_index = BikeIndexClient()
        self.supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
    
    def fetch_and_store_bike(self, brand: str, model: str, year: int) -> Optional[Dict]:
        """Fetch bike from API and store in database"""
        
        print(f"🔍 Searching for: {brand} {model} {year}")
        
        # Search Bike Index
        try:
            bikes = self.bike_index.search_bikes(brand, model, year)
            
            if not bikes:
                print(f"❌ No bikes found for {brand} {model} {year}")
                return None
            
            # Take first result
            bike_data = bikes[0]
            normalized = self.bike_index.normalize_bike_data(bike_data)
            
            print(f"✅ Found: {normalized['brand']} {normalized['model_name']} {normalized['model_year']}")
            
            # Check if already exists
            existing = self.supabase.table('bike_catalog').select('*').eq('brand', normalized['brand']).eq('model_name', normalized['model_name']).eq('model_year', normalized['model_year']).execute()
            
            if existing.data:
                print(f"⚠️  Bike already exists in catalog (ID: {existing.data[0]['id']})")
                return existing.data[0]
            
            # Insert into database
            result = self.supabase.table('bike_catalog').insert(normalized).execute()
            
            print(f"💾 Stored in database: {result.data[0]['id']}")
            return result.data[0]
            
        except Exception as e:
            print(f"❌ Error: {e}")
            return None
    
    def bulk_feed(self, bikes_list: List[tuple]):
        """Feed multiple bikes at once"""
        results = []
        for brand, model, year in bikes_list:
            result = self.fetch_and_store_bike(brand, model, year)
            if result:
                results.append(result)
        
        print(f"\n📊 Summary: {len(results)}/{len(bikes_list)} bikes added to catalog")
        return results


def main():
    """Demo: Feed some popular bikes"""
    
    print("🚴 Bike Catalog Feeder - Demo\n")
    
    feeder = BikeCatalogFeeder()
    
    # Popular bikes to feed (brand, model, year)
    demo_bikes = [
        ('Trek', 'Marlin 5', 2024),
        ('Trek', 'Marlin 6', 2024),
        ('Trek', 'Marlin 7', 2024),
        ('Trek', 'FX 3', 2024),
        ('Trek', 'Domane AL 2', 2024),
        ('Specialized', 'Rockhopper', 2024),
        ('Giant', 'Escape 3', 2024),
        ('Cannondale', 'Trail 8', 2024),
    ]
    
    results = feeder.bulk_feed(demo_bikes)
    
    print("\n✅ Demo complete!")
    print(f"   You can now view these bikes in the Bike Encyclopedia page in your app.")


if __name__ == '__main__':
    main()
