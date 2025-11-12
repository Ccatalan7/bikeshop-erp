"""
Test script for invoice parser service
"""
import requests
import sys

def test_service():
    """Test the invoice parser service"""
    base_url = "http://localhost:8000"
    
    # Test health endpoint
    print("🔍 Testing health endpoint...")
    response = requests.get(f"{base_url}/health")
    if response.status_code == 200:
        print("✅ Health check passed")
    else:
        print(f"❌ Health check failed: {response.status_code}")
        return False
    
    # Test parse endpoint with a PDF
    if len(sys.argv) > 1:
        pdf_path = sys.argv[1]
        print(f"\n🔍 Testing parse endpoint with: {pdf_path}")
        
        with open(pdf_path, 'rb') as f:
            files = {'file': ('invoice.pdf', f, 'application/pdf')}
            response = requests.post(f"{base_url}/parse-invoice", files=files)
        
        if response.status_code == 200:
            data = response.json()
            print("✅ Parse successful!")
            print(f"\n📋 Parsed data:")
            print(f"  RUT: {data['data'].get('rut')}")
            print(f"  Invoice #: {data['data'].get('invoiceNumber')}")
            print(f"  Date: {data['data'].get('date')}")
            print(f"  Total: ${data['data'].get('total'):,.0f}")
            print(f"  Supplier: {data['data'].get('supplier')}")
            print(f"\n  Line items ({len(data['data'].get('lineItems', []))}):")
            for item in data['data'].get('lineItems', []):
                print(f"    [{item['code']}] {item['description'][:50]}...")
                print(f"      Qty: {item['quantity']}, Price: ${item['unitPrice']:,.2f}, Total: ${item['total']:,.0f}")
        else:
            print(f"❌ Parse failed: {response.status_code}")
            print(response.text)
            return False
    else:
        print("\n💡 To test with a PDF: python test_parser.py /path/to/invoice.pdf")
    
    return True

if __name__ == "__main__":
    success = test_service()
    sys.exit(0 if success else 1)
