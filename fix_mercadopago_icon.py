import xml.etree.ElementTree as ET
import os

ET.register_namespace('', 'http://www.w3.org/2000/svg')
ns = {'svg': 'http://www.w3.org/2000/svg'}

os.chdir('/tmp/payment-icons')

try:
    tree = ET.parse('mercadopago_fresh.svg')
    root = tree.getroot()
    
    # We identified the structure:
    # Indices 0-5: Icon parts (Blue Oval, Hands, etc). DO NOT TOUCH.
    # Index 6: <g> containing "mercado" paths. COLOR WHITE.
    # Indices 7-10: <path> containing "pago". COLOR WHITE.
    
    # Collect all children first to access by index reliably
    children = list(root)
    
    for i, child in enumerate(children):
        if i < 6:
            continue # Skip icon parts
        
        if child.tag == '{http://www.w3.org/2000/svg}g':
            # This is "mercado" group
            for subchild in child:
                subchild.set('fill', '#FFFFFF')
                if 'class' in subchild.attrib:
                    del subchild.attrib['class']
        elif child.tag == '{http://www.w3.org/2000/svg}path':
            # This is "pago" letters
            child.set('fill', '#FFFFFF')
            if 'class' in child.attrib:
                del child.attrib['class']

    tree.write('mercadopago_final.svg', encoding='utf-8', xml_declaration=False)
    print("Successfully created mercadopago_final.svg")

except Exception as e:
    print(f"Error: {e}")
