#!/usr/bin/env python3
"""
Check what values Odoo accepts for product.template.type field
"""

import os
import xmlrpc.client

# Odoo credentials
ODOO_URL = "https://vinabike.odoo.com"
ODOO_DB = "vinabike"
ODOO_USERNAME = "vinabikechile@gmail.com"
ODOO_API_KEY = os.environ.get("ODOO_API_KEY", "")

print("Connecting to Odoo...")
common = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/common')
uid = common.authenticate(ODOO_DB, ODOO_USERNAME, ODOO_API_KEY, {})
models = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/object')

print("\nChecking product.product 'type' field options...")
fields_info = models.execute_kw(
    ODOO_DB, uid, ODOO_API_KEY,
    'product.product', 'fields_get',
    ['type'], {'attributes': ['type', 'selection', 'string', 'help']}
)

if 'type' in fields_info:
    field = fields_info['type']
    print(f"\nField: {field.get('string', 'type')}")
    print(f"Type: {field.get('type')}")
    print(f"Help: {field.get('help', 'N/A')}")
    print(f"\nAllowed values (selection):")
    for value, label in field.get('selection', []):
        print(f"  - '{value}': {label}")
else:
    print("Type field not found!")

print("\n" + "="*80)
print("Checking product.template 'type' field options...")
fields_info = models.execute_kw(
    ODOO_DB, uid, ODOO_API_KEY,
    'product.template', 'fields_get',
    ['type'], {'attributes': ['type', 'selection', 'string', 'help']}
)

if 'type' in fields_info:
    field = fields_info['type']
    print(f"\nField: {field.get('string', 'type')}")
    print(f"Type: {field.get('type')}")
    print(f"Help: {field.get('help', 'N/A')}")
    print(f"\nAllowed values (selection):")
    for value, label in field.get('selection', []):
        print(f"  - '{value}': {label}")
else:
    print("Type field not found!")
