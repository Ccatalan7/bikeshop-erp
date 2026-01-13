import xml.etree.ElementTree as ET
import os

ET.register_namespace('', 'http://www.w3.org/2000/svg')
ns = {'svg': 'http://www.w3.org/2000/svg'}

os.chdir('/tmp/payment-icons')

# 1. MercadoPago
try:
    tree = ET.parse('mercadopago.svg')
    root = tree.getroot()
    # Logic: Paths directly under root are text. Paths under first <g> are icon.
    for child in root:
        if child.tag == '{http://www.w3.org/2000/svg}path':
            child.set('fill', '#FFFFFF')
            if 'class' in child.attrib:
                del child.attrib['class']
    tree.write('mercadopago_white.svg', encoding='utf-8', xml_declaration=False)
except Exception as e:
    print(f"Error processing mercadopago: {e}")

# 2. Visa
try:
    tree = ET.parse('visa.svg')
    root = tree.getroot()
    for elem in root.iter():
        style = elem.get('style', '')
        if '#00579f' in style:
            elem.set('style', style.replace('#00579f', '#FFFFFF'))
    tree.write('visa_white.svg', encoding='utf-8', xml_declaration=False)
except Exception as e:
    print(f"Error processing visa: {e}")

# 3. Mastercard
try:
    tree = ET.parse('mastercard.svg')
    root = tree.getroot()
    # Use findall for direct children to avoid deep recursion if not needed, but text is confirmed as direct child path
    for child in root:
        if child.tag == '{http://www.w3.org/2000/svg}path':
            child.set('fill', '#FFFFFF')
    tree.write('mastercard_white.svg', encoding='utf-8', xml_declaration=False)
except Exception as e:
    print(f"Error processing mastercard: {e}")
