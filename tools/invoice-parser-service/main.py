"""
FastAPI Invoice Parser Service
Extracts structured data from Chilean invoices (PDFs)
"""
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import pdfplumber
import re
import io
from datetime import datetime
from typing import Optional, List, Dict, Any

app = FastAPI(title="Invoice Parser API", version="1.0.0")

# CORS for Flutter web client
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, restrict to your domain
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class InvoiceParser:
    """Parse Chilean invoices from PDF text"""
    
    def parse_mkr_invoice(self, text: str) -> Dict[str, Any]:
        """Parse MKR (Mauricio Kishinevsky) invoice format"""
        lines = [l.strip() for l in text.split('\n') if l.strip()]
        
        result = {
            "rut": self._extract_rut(lines),
            "invoiceNumber": self._extract_invoice_number(lines),
            "date": self._extract_date(lines),
            "total": self._extract_total(lines),
            "supplier": self._extract_supplier(lines),
            "lineItems": self._extract_line_items_mkr(lines),
        }
        
        return result
    
    def _extract_rut(self, lines: List[str]) -> Optional[str]:
        """Extract supplier RUT (NOT recipient RUT)
        For MKR invoices: Skip first few lines (recipient info), look for supplier RUT"""
        found_ruts = []
        
        for i, line in enumerate(lines):
            match = re.search(r'(\d{1,2}\.?\d{3}\.?\d{3}-[\dkK])', line)
            if match:
                rut = match.group(1)
                # Format with dots if missing
                if '.' not in rut:
                    rut = re.sub(r'(\d{1,2})(\d{3})(\d{3})(-.+)', r'\1.\2.\3\4', rut)
                found_ruts.append((i, rut))
        
        # Strategy: For MKR invoices, the FIRST RUT is usually the recipient (skip it)
        # Look for a different RUT later in the document (supplier)
        if len(found_ruts) >= 2:
            # Return the second RUT found (likely the supplier)
            return found_ruts[1][1]
        elif len(found_ruts) == 1:
            # Only one RUT found, use it
            return found_ruts[0][1]
        
        return None
    
    def _extract_invoice_number(self, lines: List[str]) -> Optional[str]:
        """Extract invoice/pedido number (handles split lines)"""
        # Pattern 1: Same line
        for line in lines[:30]:
            match = re.search(r'(?:Pedido|PEDIDO|Factura|FACTURA|Folio|FOLIO)\s*#?\s*(\d+)', line, re.IGNORECASE)
            if match:
                return match.group(1)
        
        # Pattern 2: Label on one line, number on next
        for i in range(len(lines) - 1):
            if re.match(r'^(?:Pedido|Factura|Folio)\s*#?\s*$', lines[i], re.IGNORECASE):
                if re.match(r'^\d+$', lines[i + 1]):
                    return lines[i + 1]
        
        return None
    
    def _extract_date(self, lines: List[str]) -> Optional[str]:
        """Extract date in DD/MM/YYYY format"""
        for line in lines[:30]:
            match = re.search(r'(\d{2})/(\d{2})/(\d{4})', line)
            if match:
                day, month, year = match.groups()
                try:
                    date = datetime(int(year), int(month), int(day))
                    return date.strftime('%Y-%m-%d')
                except ValueError:
                    continue
        return None
    
    def _extract_total(self, lines: List[str]) -> Optional[float]:
        """Extract total amount (handles split lines)"""
        # Strategy 1: "Total" on one line, amount on next
        for i in range(len(lines) - 1):
            if lines[i].upper().strip() == 'TOTAL' or lines[i].upper().startswith('TOTAL '):
                next_line = lines[i + 1]
                match = re.search(r'\$\s*([\d.,]+)', next_line)
                if match:
                    amount = self._parse_amount(match.group(1))
                    if amount and 0 < amount < 1_000_000_000:
                        return amount
        
        # Strategy 2: "Total $ 65.233" on same line
        for line in lines:
            match = re.search(r'(?:TOTAL|Total|total)\s*\$?\s*([\d.,]+)', line, re.IGNORECASE)
            if match:
                amount = self._parse_amount(match.group(1))
                if amount and 0 < amount < 1_000_000_000:
                    return amount
        
        return None
    
    def _extract_supplier(self, lines: List[str]) -> Optional[str]:
        """Extract supplier name (sender, usually at bottom for MKR)"""
        # Check bottom 20 lines for company patterns
        for line in reversed(lines[-20:]):
            if re.search(r'\b(S\.A\.|Ltda\.|SpA|SPA)\b', line, re.IGNORECASE):
                # Clean up company name
                company = re.sub(r'(Importaciones|Exportación|Casa Matriz|Fonos).*', '', line, flags=re.IGNORECASE).strip()
                if len(company) > 3:
                    return company
            
            # Check for MKR brand
            if 'MKR' in line.upper() and len(line) < 50:
                return line.strip()
        
        return None
    
    def _extract_line_items_mkr(self, lines: List[str]) -> List[Dict[str, Any]]:
        """Extract line items from MKR invoice format"""
        items = []
        
        # Find table start (IMPORTE header)
        start_idx = None
        for i, line in enumerate(lines):
            if line.upper().strip() == 'IMPORTE':
                start_idx = i + 1
                break
        
        if start_idx is None:
            return items
        
        # Find table end (Total neto)
        end_idx = len(lines)
        for i in range(start_idx, len(lines)):
            if 'TOTAL NETO' in lines[i].upper() or ('TOTAL' in lines[i].upper() and i > start_idx + 10):
                end_idx = i
                break
        
        # Parse products (each starts with [CODE] pattern)
        i = start_idx
        while i < end_idx and len(items) < 50:  # Max 50 items
            line = lines[i].strip()
            
            # Check for product code: [C2725] Product Name
            match = re.match(r'^\[([A-Z0-9]+)\]\s+(.+)$', line)
            if match:
                code = match.group(1)
                description = match.group(2)
                
                # Collect description lines (until barcode or UNIDADES)
                i += 1
                desc_lines = 0
                while i < end_idx and desc_lines < 5:
                    if 'UNIDADES' in lines[i].upper() or re.match(r'^\d{13,}$', lines[i].strip()):
                        break
                    if lines[i].strip() and not re.match(r'^[\d,\.]+$', lines[i].strip()) and lines[i].strip() not in ['IVA 19%', 'Vta', '$']:
                        description += ' ' + lines[i].strip()
                    i += 1
                    desc_lines += 1
                
                # Extract quantity and price from next 10 lines
                quantity = None
                unit_price = None
                line_total = None
                
                for j in range(i, min(i + 10, end_idx)):
                    test_line = lines[j].strip()
                    
                    # Quantity: format "20,00" before UNIDADES
                    if quantity is None and re.match(r'^\d{1,4},\d{2}$', test_line):
                        quantity = self._parse_amount(test_line)
                    
                    # Unit price: format "2.550,10" after UNIDADES
                    if unit_price is None and re.match(r'^\d{1,3}\.\d{3},\d{2}$', test_line):
                        unit_price = self._parse_amount(test_line)
                    
                    # Line total: after "$" symbol
                    if j > 0 and lines[j - 1].strip() == '$':
                        total_match = re.match(r'^([\d.,]+)$', test_line)
                        if total_match:
                            line_total = self._parse_amount(total_match.group(1))
                            break
                
                # Add item if we have minimum data
                if description:
                    items.append({
                        "code": code,
                        "description": description.strip(),
                        "quantity": quantity,
                        "unitPrice": unit_price,
                        "total": line_total,
                    })
                
                i += 10  # Skip ahead past this product
            else:
                i += 1
        
        return items
    
    def _parse_amount(self, amount_str: str) -> Optional[float]:
        """Parse Chilean currency format to float"""
        try:
            # Remove $ and spaces
            amount_str = amount_str.replace('$', '').replace(' ', '').strip()
            
            # Chilean format: 1.234,56 → 1234.56 OR 20,00 → 20.0
            if ',' in amount_str and '.' in amount_str:
                # Has both: dots are thousands, comma is decimal
                amount_str = amount_str.replace('.', '').replace(',', '.')
            elif ',' in amount_str:
                # Only comma: it's decimal separator
                amount_str = amount_str.replace(',', '.')
            # If only dots, they're thousands separators (remove them)
            elif amount_str.count('.') > 1:
                amount_str = amount_str.replace('.', '')
            
            return float(amount_str)
        except (ValueError, AttributeError):
            return None


parser = InvoiceParser()


@app.get("/")
def root():
    return {"status": "ok", "service": "Invoice Parser API", "version": "1.0.0"}


@app.get("/health")
def health():
    return {"status": "healthy"}


@app.post("/parse-invoice")
async def parse_invoice(file: UploadFile = File(...)):
    """
    Parse invoice PDF and return structured data
    
    Returns:
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
                    "description": "Cadena KMC HV408...",
                    "quantity": 20.0,
                    "unitPrice": 2550.10,
                    "total": 25501.0
                }
            ]
        }
    }
    """
    if not file.filename.lower().endswith('.pdf'):
        raise HTTPException(status_code=400, detail="Only PDF files are supported")
    
    try:
        # Read PDF bytes
        pdf_bytes = await file.read()
        pdf_file = io.BytesIO(pdf_bytes)
        
        # Extract text using pdfplumber
        text = ""
        with pdfplumber.open(pdf_file) as pdf:
            for page in pdf.pages:
                text += page.extract_text() or ""
        
        if not text.strip():
            raise HTTPException(status_code=400, detail="Could not extract text from PDF")
        
        # Parse invoice
        result = parser.parse_mkr_invoice(text)
        
        return JSONResponse({
            "success": True,
            "data": result,
            "rawText": text[:500] + "..." if len(text) > 500 else text  # First 500 chars for debugging
        })
        
    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "error": str(e),
                "detail": "Failed to parse invoice"
            }
        )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
