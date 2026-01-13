import xml.etree.ElementTree as ET
import os

ET.register_namespace('', 'http://www.w3.org/2000/svg')
ns = {'svg': 'http://www.w3.org/2000/svg'}

os.chdir('/tmp/payment-icons')

try:
    tree = ET.parse('mercadopago_fresh.svg')
    root = tree.getroot()
    
    print(f"Root tag: {root.tag}")
    print(f"ViewBox: {root.get('viewBox')}")
    
    for i, child in enumerate(root):
        print(f"Child {i}: {child.tag} {child.attrib.get('class', '')} {child.attrib.get('id', '')}")
        if child.tag == '{http://www.w3.org/2000/svg}g':
            for j, subchild in enumerate(child):
                 print(f"  Grandchild {j}: {subchild.tag} d_len={len(subchild.get('d', ''))} start={subchild.get('d', '')[:20]}")
        elif child.tag == '{http://www.w3.org/2000/svg}path':
             print(f"  Path d_len={len(child.get('d', ''))} start={child.get('d', '')[:20]}")

except Exception as e:
    print(f"Error: {e}")
