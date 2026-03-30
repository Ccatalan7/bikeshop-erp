import re

with open('lib/modules/sales/pages/invoice_form_page.dart', 'r') as f:
    text = f.read()

# Grab _generateInvoicePDF
start = text.find('Future<pw.Document> _generateInvoicePDF(')
# we want to get the end of _buildPdfTotalRow
# Let's search for its definition: 'pw.Widget _buildPdfTotalRow('
def_idx = text.find('pw.Widget _buildPdfTotalRow(')
# find the next method or end of class
end = text.find('\n\n', def_idx)
if end == -1: end = text.find('}', def_idx) + 1

# Actually let's just grab from start to def_idx + 1000 and slice off the extra
import ast

def extract_methods(src):
    # simplest: just grab the big chunk 
    s = src.find('Future<pw.Document> _generateInvoicePDF(')
    e = src.find('  }\n}', s) + 4
    return src[s:e]

chunk = extract_methods(text)

with open('extracted_chunk.dart', 'w') as f:
    f.write(chunk)

print("Done extracting. Length:", len(chunk))
