import xml.etree.ElementTree as ET
import os

ET.register_namespace('', 'http://www.w3.org/2000/svg')
ns = {'svg': 'http://www.w3.org/2000/svg'}

os.chdir('/tmp/payment-icons')

try:
    tree = ET.parse('mercadopago_fresh.svg')
    root = tree.getroot()
    
    children = list(root)
    
    # Original Colors from Style Block:
    DARK_BLUE = '#0a0080'  # cls-1
    LIGHT_BLUE = '#00bcff' # cls-3
    WHITE = '#ffffff'      # cls-2
    
    # Target Colors:
    # Icon (0-5): Keep Original Brand Colors
    # Text (6+): Force White
    
    for i, child in enumerate(children):
        # Remove class attribute to ensure fill takes precedence
        if 'class' in child.attrib:
            del child.attrib['class']
            
        if i == 0: # defs
            continue
            
        elif i == 1: # cls-3 (Light Blue Oval Top)
            child.set('fill', LIGHT_BLUE)
            
        elif i in [2, 3, 4]: # cls-2 (White Hands)
            child.set('fill', WHITE)
            
        elif i == 5: # cls-1 (Dark Blue Oval Shadow/Bottom)
            child.set('fill', DARK_BLUE)
            
        else: # i >= 6 (Text - originally cls-1)
            # Force Text to be White for Dark Mode
            if child.tag == '{http://www.w3.org/2000/svg}g':
                for sub in child:
                    sub.set('fill', WHITE)
                    if 'class' in sub.attrib: del sub.attrib['class']
            else:
                child.set('fill', WHITE)

    tree.write('mercadopago_polished.svg', encoding='utf-8', xml_declaration=False)
    print("Successfully created mercadopago_polished.svg")

except Exception as e:
    print(f"Error: {e}")
