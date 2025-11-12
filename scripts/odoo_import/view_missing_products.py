#!/usr/bin/env python3
"""
Display missing_products_zoho.csv as a formatted table
"""

import csv

# Read CSV
with open('missing_products_zoho.csv', 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    data = list(reader)

# Print header
print("\n" + "=" * 160)
print("MISSING PRODUCTS FROM ZOHO (24 products)")
print("=" * 160)

# Column widths
print(f"\n{'#':<4} {'SKU':<20} {'Product Name':<50} {'Stock':<8} {'Price':<12} {'Cost':<12} {'Category':<30}")
print("-" * 160)

# Print each row
for i, row in enumerate(data, 1):
    sku = row['SKU'][:20]
    name = row['Name'][:47] + '...' if len(row['Name']) > 50 else row['Name']
    stock = row['Stock (Zoho)']
    price = f"${float(row['Price']):,.0f}"
    cost = f"${float(row['Cost']):,.0f}"
    category = row['Category'][:27] + '...' if len(row['Category']) > 30 else row['Category']
    
    print(f"{i:<4} {sku:<20} {name:<50} {stock:<8} {price:<12} {cost:<12} {category:<30}")

# Summary
print("\n" + "=" * 160)
print(f"Total: {len(data)} products")
print(f"Total Stock: {sum(float(row['Stock (Zoho)']) for row in data):.1f} units")
print(f"Total Value (at cost): ${sum(float(row['Cost']) * float(row['Stock (Zoho)']) for row in data):,.0f} CLP")
print(f"Total Value (at price): ${sum(float(row['Price']) * float(row['Stock (Zoho)']) for row in data):,.0f} CLP")
print("=" * 160 + "\n")
