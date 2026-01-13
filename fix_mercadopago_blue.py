import xml.etree.ElementTree as ET
import os

ET.register_namespace('', 'http://www.w3.org/2000/svg')
ns = {'svg': 'http://www.w3.org/2000/svg'}

os.chdir('/tmp/payment-icons')

try:
    tree = ET.parse('mercadopago_fresh.svg')
    root = tree.getroot()
    
    children = list(root)
    
    # Logic:
    # 0: defs
    # 1: cls-3 (Detail) -> White
    # 2,3,4: cls-2 (Hands) -> White
    # 5: cls-1 (Oval) -> Blue
    # 6: Group (Mercado) -> Contains cls-1 paths -> White
    # 7-10: Paths (Pago) -> cls-1 -> White
    
    BLUE = '#009EE3'
    WHITE = '#FFFFFF'
    
    for i, child in enumerate(children):
        # Determine color based on index (Role) and Class
        
        # Helper to process an element
        def process_element(elem, explicit_color=None):
            cls = elem.get('class')
            color = explicit_color
            
            if not color:
                if cls == 'cls-1': color = BLUE # Default for cls-1
                elif cls == 'cls-2': color = WHITE
                elif cls == 'cls-3': color = WHITE # Assuming detail is white
            
            if color:
                elem.set('fill', color)
            
            if 'class' in elem.attrib:
                del elem.attrib['class']

        if i < 6:
            # Icon Parts
            # Index 5 is the Oval (cls-1). Needs to be BLUE.
            # Indices 1-4 are Hands/Details. Need to be WHITE.
            if i == 5:
                process_element(child, BLUE)
            elif i > 0: # 1,2,3,4
                process_element(child, WHITE)
                
        else:
            # Text Parts (Group or Paths)
            # Need to be WHITE regardless of original class (which was Blue/cls-1)
            if child.tag == '{http://www.w3.org/2000/svg}g':
                for sub in child:
                    process_element(sub, WHITE)
            else:
                process_element(child, WHITE)

    tree.write('mercadopago_fixed_colors.svg', encoding='utf-8', xml_declaration=False)
    print("Successfully created mercadopago_fixed_colors.svg")

except Exception as e:
    print(f"Error: {e}")
