# Invoice Parser Service

FastAPI microservice for parsing Chilean invoices (PDFs) into structured data.

## Features

- ✅ Extracts: RUT, invoice number, date, total, supplier name
- ✅ Extracts line items: product code, description, quantity, unit price, total
- ✅ Handles MKR (Mauricio Kishinevsky) invoice format
- ✅ Supports split-line patterns (e.g., "Pedido #" on one line, "262040" on next)
- ✅ Chilean currency format support (1.234,56 → 1234.56)

## Quick Start

### Option 1: Docker (Recommended)

```bash
cd tools/invoice-parser-service
docker-compose up --build
```

Service runs at: `http://localhost:8000`

### Option 2: Local Python

```bash
cd tools/invoice-parser-service

# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Run service
python main.py
```

## Usage

### Test the API

```bash
# Health check
curl http://localhost:8000/health

# Parse invoice
curl -X POST http://localhost:8000/parse-invoice \
  -F "file=@/path/to/invoice.pdf"
```

### Response Format

```json
{
  "success": true,
  "data": {
    "rut": "77.541.999-7",
    "invoiceNumber": "262040",
    "date": "2025-10-02",
    "total": 65233.0,
    "supplier": "Mauricio Kishinevsky Rosental S.A.",
    "lineItems": [
      {
        "code": "C2725",
        "description": "Cadena KMC HV408 6V 1/2x3/32\" Caja Gris Marrón",
        "quantity": 20.0,
        "unitPrice": 2550.10,
        "total": 25501.0
      },
      {
        "code": "A2331",
        "description": "Asiento Radical Mountain Paseo N708A Con Resorte Negro",
        "quantity": 3.0,
        "unitPrice": 4890.35,
        "total": 7336.0
      },
      {
        "code": "N254",
        "description": "Neumático Vuelta USA 26x2.125\" CB-570 PAN",
        "quantity": 4.0,
        "unitPrice": 5784.35,
        "total": 21981.0
      }
    ]
  }
}
```

## Adding Support for New Suppliers

To add support for a new invoice format, edit `main.py`:

1. Add a new method in `InvoiceParser` class (e.g., `parse_supplier_xyz_invoice`)
2. Add detection logic in the main parsing flow
3. Adjust regex patterns to match the new format

## API Endpoints

- `GET /` - Service info
- `GET /health` - Health check
- `POST /parse-invoice` - Parse PDF invoice (multipart/form-data with `file` field)

## Development

### Run with hot reload

```bash
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

### Test with sample invoice

```bash
python test_parser.py
```

## Deployment

### Deploy to Render.com (Free tier)

1. Push code to GitHub
2. Create new Web Service on Render.com
3. Connect your repo
4. Build command: `pip install -r tools/invoice-parser-service/requirements.txt`
5. Start command: `uvicorn tools.invoice-parser-service.main:app --host 0.0.0.0 --port $PORT`

### Deploy to Railway.app

```bash
railway login
railway init
railway up
```

## Troubleshooting

**PDF extraction returns empty text:**
- PDF might be scanned (image-based). Add OCR support with `pytesseract`.

**Line items not extracted:**
- Check if invoice format matches MKR pattern (`[CODE] Description`)
- Add debug logging: `print(lines)` to see actual text structure
- Adjust regex patterns in `_extract_line_items_mkr()`

**Wrong supplier detected:**
- Supplier detection looks at bottom 20 lines for company patterns (S.A., Ltda., SpA)
- If supplier is elsewhere, adjust the slice in `_extract_supplier()`
