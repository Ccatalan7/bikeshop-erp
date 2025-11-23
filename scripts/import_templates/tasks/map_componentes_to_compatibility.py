"""
Map Componentes Categories to Compatibility Metadata

Fetches all categories under "Componentes" parent and adds compatibility_metadata
following the Master Plan Section 4.2 field dictionary.
"""

import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))

from connections.supabase_connection import SupabaseConnection

# Component type mapping (Odoo category name → compatibility metadata)
COMPONENT_METADATA = {
    # TRANSMISIÓN (Drivetrain)
    'Cassette': {
        'component_code': 'cassette',
        'discipline_scope': ['mtb', 'road', 'gravel'],
        'icon_name': 'cassette',
        'attributes': [
            {'name': 'cassette_speeds', 'type': 'enum', 'required': True, 'label': 'Velocidades', 
             'enum_values': ['5', '6', '7', '8', '9', '10', '11', '12', '13']},
            {'name': 'cassette_range_min', 'type': 'number', 'required': True, 'label': 'Piñón menor (dientes)', 'unit': 'teeth'},
            {'name': 'cassette_range_max', 'type': 'number', 'required': True, 'label': 'Piñón mayor (dientes)', 'unit': 'teeth'},
            {'name': 'freehub_standard', 'type': 'enum', 'required': True, 'label': 'Estándar cuerpo',
             'enum_values': ['shimano_hg', 'microspline', 'sram_xd', 'sram_xdr', 'campagnolo', 't_type', 'hg_5s_vintage']},
        ]
    },
    'Freewheel': {
        'component_code': 'freewheel',
        'discipline_scope': ['vintage', 'city'],
        'icon_name': 'freewheel',
        'attributes': [
            {'name': 'freewheel_speeds', 'type': 'enum', 'required': True, 'label': 'Velocidades',
             'enum_values': ['5', '6', '7', '8']},
            {'name': 'freewheel_range_min', 'type': 'number', 'required': True, 'label': 'Piñón menor', 'unit': 'teeth'},
            {'name': 'freewheel_range_max', 'type': 'number', 'required': True, 'label': 'Piñón mayor', 'unit': 'teeth'},
            {'name': 'thread_type', 'type': 'enum', 'required': True, 'label': 'Tipo rosca',
             'enum_values': ['standard_1.375x24', 'french_35mm', 'italian']},
        ]
    },
    'Cadenas': {
        'component_code': 'chain',
        'discipline_scope': ['mtb', 'road', 'gravel', 'city'],
        'icon_name': 'chain',
        'attributes': [
            {'name': 'chain_speeds', 'type': 'enum', 'required': True, 'label': 'Velocidades',
             'enum_values': ['5', '6', '7', '8', '9', '10', '11', '12', '13']},
            {'name': 'chain_type', 'type': 'enum', 'required': True, 'label': 'Tipo cadena',
             'enum_values': ['hg', 'hg_plus', 'eagle', 't_type', 'road11s', 'campagnolo']},
            {'name': 'chain_width_mm', 'type': 'number', 'required': False, 'label': 'Ancho interno', 'unit': 'mm'},
        ]
    },
    'Piñones': {
        'component_code': 'cog',
        'discipline_scope': ['fixie', 'single_speed'],
        'icon_name': 'cog',
        'attributes': [
            {'name': 'teeth_count', 'type': 'number', 'required': True, 'label': 'Número de dientes'},
            {'name': 'thread_type', 'type': 'enum', 'required': True, 'label': 'Tipo rosca',
             'enum_values': ['standard_1.375x24', 'track_italian']},
        ]
    },
    'Desviador Trasero': {
        'component_code': 'rear_derailleur',
        'discipline_scope': ['mtb', 'road', 'gravel'],
        'icon_name': 'derailleur',
        'attributes': [
            {'name': 'derailleur_speeds', 'type': 'enum', 'required': True, 'label': 'Velocidades',
             'enum_values': ['7', '8', '9', '10', '11', '12', '13']},
            {'name': 'derailleur_max_teeth', 'type': 'number', 'required': True, 'label': 'Máx dientes piñón', 'unit': 'teeth'},
            {'name': 'cage_length', 'type': 'enum', 'required': True, 'label': 'Largo jaula',
             'enum_values': ['short', 'medium', 'long']},
            {'name': 'clutch', 'type': 'boolean', 'required': False, 'label': 'Clutch'},
            {'name': 'mount_type', 'type': 'enum', 'required': True, 'label': 'Montaje',
             'enum_values': ['standard_hanger', 'direct_mount', 'udh']},
        ]
    },
    'Desviadores delanteros': {
        'component_code': 'front_derailleur',
        'discipline_scope': ['mtb', 'road', 'gravel'],
        'icon_name': 'front-derailleur',
        'attributes': [
            {'name': 'derailleur_speeds', 'type': 'enum', 'required': True, 'label': 'Velocidades',
             'enum_values': ['8', '9', '10', '11', '12']},
            {'name': 'mount_type', 'type': 'enum', 'required': True, 'label': 'Montaje',
             'enum_values': ['clamp_31.8', 'clamp_34.9', 'braze_on', 'direct_mount']},
            {'name': 'chainrings', 'type': 'enum', 'required': True, 'label': 'Platos',
             'enum_values': ['double', 'triple']},
        ]
    },
    'Biela Americana': {
        'component_code': 'crankset',
        'discipline_scope': ['mtb', 'road', 'gravel'],
        'icon_name': 'crankset',
        'attributes': [
            {'name': 'crank_arm_length_mm', 'type': 'enum', 'required': True, 'label': 'Largo bielas',
             'enum_values': ['165', '170', '172.5', '175', '177.5', '180']},
            {'name': 'chainline_mm', 'type': 'number', 'required': True, 'label': 'Chainline', 'unit': 'mm'},
            {'name': 'q_factor_mm', 'type': 'number', 'required': False, 'label': 'Q-factor', 'unit': 'mm'},
            {'name': 'spindle_type', 'type': 'enum', 'required': True, 'label': 'Tipo eje',
             'enum_values': ['square_taper', 'octalink', 'isis', 'gxp', 'bb30', 'pf30', 'dub', 't47']},
            {'name': 'chainring_mount', 'type': 'enum', 'required': True, 'label': 'Montaje plato',
             'enum_values': ['bcd_104', 'bcd_110', 'bcd_130', 'direct_mount_sram', 'direct_mount_shimano']},
        ]
    },
    'Catalina': {
        'component_code': 'chainring',
        'discipline_scope': ['mtb', 'road', 'gravel'],
        'icon_name': 'chainring',
        'attributes': [
            {'name': 'teeth_count', 'type': 'number', 'required': True, 'label': 'Dientes'},
            {'name': 'bcd_mm', 'type': 'enum', 'required': True, 'label': 'BCD',
             'enum_values': ['104', '110', '130', '144', 'direct_mount']},
            {'name': 'offset_mm', 'type': 'number', 'required': False, 'label': 'Offset', 'unit': 'mm'},
            {'name': 'wide_narrow', 'type': 'boolean', 'required': False, 'label': 'Narrow-wide'},
        ]
    },
    'Cubetas': {
        'component_code': 'bottom_bracket',
        'discipline_scope': ['mtb', 'road', 'gravel'],
        'icon_name': 'bb',
        'attributes': [
            {'name': 'bb_type', 'type': 'enum', 'required': True, 'label': 'Tipo caja',
             'enum_values': ['bsa_68', 'bsa_73', 'ita', 'pf30', 'bb86', 'bb92', 'bb30', 't47', 'bmx']},
            {'name': 'bb_width_mm', 'type': 'number', 'required': True, 'label': 'Ancho', 'unit': 'mm'},
            {'name': 'spindle_compatibility', 'type': 'enum', 'required': True, 'label': 'Compatible con',
             'enum_values': ['square_taper', 'octalink', 'gxp', 'bb30', 'dub', 't47']},
        ]
    },
    
    # RUEDAS (Wheels)
    'Mazas': {
        'component_code': 'hub',
        'discipline_scope': ['mtb', 'road', 'gravel'],
        'icon_name': 'hub',
        'attributes': [
            {'name': 'hub_position', 'type': 'enum', 'required': True, 'label': 'Posición',
             'enum_values': ['front', 'rear']},
            {'name': 'spoke_holes', 'type': 'enum', 'required': True, 'label': 'Número rayos',
             'enum_values': ['12', '16', '20', '24', '28', '32', '36', '48']},
            {'name': 'hub_spacing_mm', 'type': 'enum', 'required': True, 'label': 'OLD (espaciado)', 'unit': 'mm',
             'enum_values': ['100', '110', '135', '142', '148', '150', '157']},
            {'name': 'axle_type', 'type': 'enum', 'required': True, 'label': 'Tipo eje',
             'enum_values': ['qr_9x100', 'qr_10x135', 'thru_12x100', 'thru_12x142', 'thru_15x100', 'thru_15x110', 'thru_20x110', 'bolt_on']},
            {'name': 'freehub_standard', 'type': 'enum', 'required': False, 'label': 'Cuerpo (solo trasera)',
             'enum_values': ['shimano_hg', 'microspline', 'sram_xd', 'sram_xdr', 'campagnolo', 't_type']},
            {'name': 'brake_interface', 'type': 'enum', 'required': True, 'label': 'Interfaz freno',
             'enum_values': ['6_bolt', 'centerlock', 'rim_brake']},
            {'name': 'flange_diameter_left_mm', 'type': 'number', 'required': False, 'label': 'Diámetro brida izq', 'unit': 'mm'},
            {'name': 'flange_diameter_right_mm', 'type': 'number', 'required': False, 'label': 'Diámetro brida der', 'unit': 'mm'},
            {'name': 'center_to_flange_left_mm', 'type': 'number', 'required': False, 'label': 'Centro a brida izq', 'unit': 'mm'},
            {'name': 'center_to_flange_right_mm', 'type': 'number', 'required': False, 'label': 'Centro a brida der', 'unit': 'mm'},
        ]
    },
    'Llantas': {
        'component_code': 'rim',
        'discipline_scope': ['mtb', 'road', 'gravel'],
        'icon_name': 'rim',
        'attributes': [
            {'name': 'spoke_holes', 'type': 'enum', 'required': True, 'label': 'Número rayos',
             'enum_values': ['12', '16', '20', '24', '28', '32', '36', '48']},
            {'name': 'rim_internal_width_mm', 'type': 'number', 'required': True, 'label': 'Ancho interno', 'unit': 'mm'},
            {'name': 'rim_external_width_mm', 'type': 'number', 'required': False, 'label': 'Ancho externo', 'unit': 'mm'},
            {'name': 'erd_mm', 'type': 'number', 'required': True, 'label': 'ERD (diámetro efectivo)', 'unit': 'mm'},
            {'name': 'tubeless_ready', 'type': 'boolean', 'required': True, 'label': 'Tubeless ready'},
            {'name': 'wheel_size', 'type': 'enum', 'required': True, 'label': 'Tamaño rueda',
             'enum_values': ['700c', '650b_27_5', '29er', '26in', '24in', '20in', '18in', '16in']},
            {'name': 'brake_interface', 'type': 'enum', 'required': True, 'label': 'Interfaz freno',
             'enum_values': ['disc_only', 'rim_brake', 'both']},
        ]
    },
    'Neumáticos': {
        'component_code': 'tire',
        'discipline_scope': ['mtb', 'road', 'gravel'],
        'icon_name': 'tire',
        'attributes': [
            {'name': 'bsd_diameter_mm', 'type': 'enum', 'required': True, 'label': 'Diámetro BSD',
             'enum_values': ['406', '451', '507', '559', '571', '584', '622']},
            {'name': 'tire_width_mm', 'type': 'number', 'required': True, 'label': 'Ancho', 'unit': 'mm'},
            {'name': 'casing', 'type': 'enum', 'required': True, 'label': 'Carcasa',
             'enum_values': ['folding', 'wire']},
            {'name': 'tubeless_ready', 'type': 'boolean', 'required': True, 'label': 'Tubeless ready'},
            {'name': 'tpi', 'type': 'number', 'required': False, 'label': 'TPI (hilos por pulgada)'},
        ]
    },
    'Cámaras': {
        'component_code': 'tube',
        'discipline_scope': ['mtb', 'road', 'gravel'],
        'icon_name': 'tube',
        'attributes': [
            {'name': 'bsd_diameter_mm', 'type': 'enum', 'required': True, 'label': 'Diámetro BSD',
             'enum_values': ['406', '451', '507', '559', '571', '584', '622']},
            {'name': 'tube_width_min_mm', 'type': 'number', 'required': True, 'label': 'Ancho mínimo', 'unit': 'mm'},
            {'name': 'tube_width_max_mm', 'type': 'number', 'required': True, 'label': 'Ancho máximo', 'unit': 'mm'},
            {'name': 'valve_type', 'type': 'enum', 'required': True, 'label': 'Tipo válvula',
             'enum_values': ['presta', 'schrader', 'dunlop']},
            {'name': 'valve_length_mm', 'type': 'enum', 'required': True, 'label': 'Largo válvula',
             'enum_values': ['40', '48', '60', '80']},
        ]
    },
    'Rayos': {
        'component_code': 'spoke',
        'discipline_scope': ['mtb', 'road', 'gravel'],
        'icon_name': 'spoke',
        'attributes': [
            {'name': 'spoke_length_mm', 'type': 'number', 'required': True, 'label': 'Largo', 'unit': 'mm'},
            {'name': 'spoke_gauge', 'type': 'enum', 'required': True, 'label': 'Calibre',
             'enum_values': ['14g', '15g', '2.0mm', '1.8mm', '2.0-1.8-2.0']},
            {'name': 'spoke_head_type', 'type': 'enum', 'required': True, 'label': 'Tipo cabeza',
             'enum_values': ['j_bend', 'straight_pull']},
        ]
    },
    'Niples': {
        'component_code': 'nipple',
        'discipline_scope': ['mtb', 'road', 'gravel'],
        'icon_name': 'nipple',
        'attributes': [
            {'name': 'nipple_size', 'type': 'enum', 'required': True, 'label': 'Tamaño',
             'enum_values': ['12mm', '14mm', '16mm']},
            {'name': 'material', 'type': 'enum', 'required': True, 'label': 'Material',
             'enum_values': ['brass', 'aluminum', 'alloy']},
        ]
    },
    'Rotores': {
        'component_code': 'rotor',
        'discipline_scope': ['mtb', 'road', 'gravel'],
        'icon_name': 'rotor',
        'attributes': [
            {'name': 'rotor_size_mm', 'type': 'enum', 'required': True, 'label': 'Tamaño', 'unit': 'mm',
             'enum_values': ['140', '160', '180', '203', '220']},
            {'name': 'rotor_mount', 'type': 'enum', 'required': True, 'label': 'Montaje',
             'enum_values': ['6_bolt', 'centerlock']},
        ]
    },
    
    # DIRECCIÓN (Steering/Cockpit)
    'Horquillas': {
        'component_code': 'fork',
        'discipline_scope': ['mtb', 'gravel'],
        'icon_name': 'fork',
        'attributes': [
            {'name': 'travel_mm', 'type': 'number', 'required': True, 'label': 'Recorrido suspensión', 'unit': 'mm'},
            {'name': 'offset_mm', 'type': 'number', 'required': True, 'label': 'Offset (rake)', 'unit': 'mm'},
            {'name': 'axle_type', 'type': 'enum', 'required': True, 'label': 'Tipo eje',
             'enum_values': ['qr_9x100', 'thru_12x100', 'thru_15x100', 'thru_15x110', 'thru_20x110']},
            {'name': 'hub_spacing_mm', 'type': 'enum', 'required': True, 'label': 'Espaciado', 'unit': 'mm',
             'enum_values': ['100', '110', '115']},
            {'name': 'brake_mount', 'type': 'enum', 'required': True, 'label': 'Montaje freno',
             'enum_values': ['post', 'flat', 'IS', 'none']},
            {'name': 'steerer_type', 'type': 'enum', 'required': True, 'label': 'Tipo dirección',
             'enum_values': ['threaded', 'threadless']},
            {'name': 'steerer_diameter_mm', 'type': 'enum', 'required': True, 'label': 'Diámetro dirección',
             'enum_values': ['1', '1.125', '1.5']},
            {'name': 'max_tire_width_mm', 'type': 'number', 'required': False, 'label': 'Ancho máx neumático', 'unit': 'mm'},
        ]
    },
    'Manubrios': {
        'component_code': 'handlebar',
        'discipline_scope': ['mtb', 'road', 'gravel'],
        'icon_name': 'handlebar',
        'attributes': [
            {'name': 'clamp_diameter_mm', 'type': 'enum', 'required': True, 'label': 'Diámetro abrazadera',
             'enum_values': ['25.4', '31.8', '35']},
            {'name': 'width_mm', 'type': 'number', 'required': True, 'label': 'Ancho', 'unit': 'mm'},
            {'name': 'rise_mm', 'type': 'number', 'required': False, 'label': 'Rise', 'unit': 'mm'},
            {'name': 'sweep_deg', 'type': 'number', 'required': False, 'label': 'Sweep', 'unit': 'degrees'},
        ]
    },
    'Tee': {
        'component_code': 'stem',
        'discipline_scope': ['mtb', 'road', 'gravel'],
        'icon_name': 'stem',
        'attributes': [
            {'name': 'clamp_diameter_mm', 'type': 'enum', 'required': True, 'label': 'Diámetro abrazadera',
             'enum_values': ['25.4', '31.8', '35']},
            {'name': 'steerer_diameter_mm', 'type': 'enum', 'required': True, 'label': 'Diámetro dirección',
             'enum_values': ['1', '1.125', '1.5']},
            {'name': 'length_mm', 'type': 'enum', 'required': True, 'label': 'Largo', 'unit': 'mm',
             'enum_values': ['30', '35', '40', '45', '50', '60', '70', '80', '90', '100', '110', '120', '130']},
            {'name': 'angle_deg', 'type': 'enum', 'required': True, 'label': 'Ángulo',
             'enum_values': ['-17', '-10', '-6', '0', '6', '10', '17']},
        ]
    },
    'Juego de dirección': {
        'component_code': 'headset',
        'discipline_scope': ['mtb', 'road', 'gravel'],
        'icon_name': 'headset',
        'attributes': [
            {'name': 'headset_standard', 'type': 'enum', 'required': True, 'label': 'Estándar',
             'enum_values': ['zs44_zs56', 'is41_is52', 'ec34_ec37', 'threaded_1_1_8', 'bmx_internal']},
            {'name': 'steerer_diameter_mm', 'type': 'enum', 'required': True, 'label': 'Diámetro dirección',
             'enum_values': ['1', '1.125', '1.5']},
        ]
    },
    
    # FRENOS (Brakes)
    'Calipers': {
        'component_code': 'brake_caliper',
        'discipline_scope': ['mtb', 'road', 'gravel'],
        'icon_name': 'brake',
        'attributes': [
            {'name': 'brake_type', 'type': 'enum', 'required': True, 'label': 'Tipo',
             'enum_values': ['mechanical', 'hydraulic']},
            {'name': 'caliper_mount', 'type': 'enum', 'required': True, 'label': 'Montaje',
             'enum_values': ['post', 'flat', 'IS']},
            {'name': 'compatible_rotor_sizes_mm', 'type': 'array', 'required': True, 'label': 'Tamaños rotor compatibles',
             'array_type': 'enum', 'enum_values': ['140', '160', '180', '203', '220']},
        ]
    },
    'Manillas': {
        'component_code': 'brake_lever',
        'discipline_scope': ['mtb', 'road', 'gravel'],
        'icon_name': 'lever',
        'attributes': [
            {'name': 'brake_type', 'type': 'enum', 'required': True, 'label': 'Tipo',
             'enum_values': ['mechanical', 'hydraulic']},
            {'name': 'lever_pull_ratio', 'type': 'enum', 'required': False, 'label': 'Ratio',
             'enum_values': ['short_pull', 'long_pull']},
            {'name': 'hose_type', 'type': 'enum', 'required': False, 'label': 'Tipo manguera',
             'enum_values': ['dot', 'mineral_oil']},
        ]
    },
    'Pastillas': {
        'component_code': 'brake_pad',
        'discipline_scope': ['mtb', 'road', 'gravel'],
        'icon_name': 'pad',
        'attributes': [
            {'name': 'pad_compound', 'type': 'enum', 'required': True, 'label': 'Compuesto',
             'enum_values': ['organic', 'semi_metallic', 'metallic']},
            {'name': 'pad_shape', 'type': 'text', 'required': True, 'label': 'Forma/modelo compatible'},
        ]
    },
    
    # ASIENTOS (Saddle/Seatpost)
    'Tija': {
        'component_code': 'seatpost',
        'discipline_scope': ['mtb', 'road', 'gravel'],
        'icon_name': 'seatpost',
        'attributes': [
            {'name': 'seatpost_diameter_mm', 'type': 'enum', 'required': True, 'label': 'Diámetro', 'unit': 'mm',
             'enum_values': ['25.4', '27.2', '30.9', '31.6', '34.9']},
            {'name': 'seatpost_length_mm', 'type': 'number', 'required': True, 'label': 'Largo', 'unit': 'mm'},
            {'name': 'seatpost_type', 'type': 'enum', 'required': True, 'label': 'Tipo',
             'enum_values': ['rigid', 'dropper']},
            {'name': 'dropper_travel_mm', 'type': 'number', 'required': False, 'label': 'Recorrido dropper', 'unit': 'mm'},
        ]
    },
    'Asiento': {
        'component_code': 'saddle',
        'discipline_scope': ['mtb', 'road', 'gravel'],
        'icon_name': 'saddle',
        'attributes': [
            {'name': 'rail_type', 'type': 'enum', 'required': True, 'label': 'Tipo rieles',
             'enum_values': ['7mm_round', 'carbon_oval', '7x10mm_oval']},
            {'name': 'width_mm', 'type': 'number', 'required': False, 'label': 'Ancho', 'unit': 'mm'},
        ]
    },
    
    # PEDALES
    'Pedales': {
        'component_code': 'pedal',
        'discipline_scope': ['mtb', 'road', 'bmx'],
        'icon_name': 'pedal',
        'attributes': [
            {'name': 'pedal_thread', 'type': 'enum', 'required': True, 'label': 'Rosca',
             'enum_values': ['9_16', '1_2']},
            {'name': 'pedal_type', 'type': 'enum', 'required': True, 'label': 'Tipo',
             'enum_values': ['platform', 'clipless', 'combo']},
            {'name': 'cleat_system', 'type': 'enum', 'required': False, 'label': 'Sistema calas',
             'enum_values': ['spd', 'spd_sl', 'look_keo', 'time', 'speedplay']},
        ]
    },
}

def main():
    print("\n" + "=" * 80)
    print("🔧 Map Componentes Categories to Compatibility Metadata")
    print("=" * 80)
    
    # Connect to Supabase
    supabase = SupabaseConnection()
    
    # Fetch all categories
    print("\n📥 Fetching categories from Supabase...")
    all_categories = supabase.fetch_all_categories()
    
    # Find "Componentes" parent
    componentes_parent = next((cat for cat in all_categories if cat['name'] == 'Componentes' and cat['level'] == 0), None)
    
    if not componentes_parent:
        print("❌ Parent category 'Componentes' not found")
        return
    
    print(f"   ✅ Found 'Componentes' parent (ID: {componentes_parent['id']})")
    
    # Get all children of Componentes (level 1 and deeper)
    componentes_children = [cat for cat in all_categories if 'Componentes' in cat['full_path']]
    print(f"   ✅ Found {len(componentes_children)} categories under 'Componentes'")
    
    # Show categories to map
    print("\n📋 Categories to map:")
    to_update = []
    not_mapped = []
    
    for cat in componentes_children:
        cat_name = cat['name']
        if cat_name in COMPONENT_METADATA:
            metadata = COMPONENT_METADATA[cat_name]
            to_update.append({
                'id': cat['id'],
                'name': cat_name,
                'full_path': cat['full_path'],
                'metadata': metadata
            })
            print(f"   ✅ {cat['full_path']} → {metadata['component_code']}")
        else:
            not_mapped.append(cat['full_path'])
    
    if not_mapped:
        print(f"\n⚠️  {len(not_mapped)} categories NOT mapped (will skip):")
        for path in not_mapped[:10]:
            print(f"   • {path}")
        if len(not_mapped) > 10:
            print(f"   ... and {len(not_mapped) - 10} more")
    
    # Confirm
    print("\n" + "=" * 80)
    print(f"📊 SUMMARY")
    print("=" * 80)
    print(f"✅ Categories to update: {len(to_update)}")
    print(f"⏭️  Categories to skip: {len(not_mapped)}")
    print("=" * 80)
    
    confirm = input("\nProceed with metadata update? (yes/no): ").strip().lower()
    if confirm != 'yes':
        print("❌ Cancelled")
        return
    
    # Update categories
    print("\n🔄 Updating categories with compatibility metadata...")
    success = 0
    failed = 0
    
    for item in to_update:
        try:
            update_data = {
                'compatibility_metadata': item['metadata'],
                'discipline_scope': item['metadata'].get('discipline_scope', []),
                'icon_name': item['metadata'].get('icon_name', '')
            }
            
            supabase.client.table('product_categories') \
                .update(update_data) \
                .eq('id', item['id']) \
                .eq('tenant_id', supabase.tenant_id) \
                .execute()
            
            success += 1
            print(f"   ✅ Updated: {item['name']} ({item['metadata']['component_code']})")
        except Exception as e:
            failed += 1
            print(f"   ❌ Failed: {item['name']} - {str(e)}")
    
    # Summary
    print("\n" + "=" * 80)
    print("📊 UPDATE SUMMARY")
    print("=" * 80)
    print(f"✅ Successfully updated: {success}")
    print(f"❌ Failed: {failed}")
    print("=" * 80)
    
    if success > 0:
        print("\n🎉 Compatibility metadata added! Now:")
        print("   1. Refresh your Flutter app")
        print("   2. Open product form → select a Componentes category")
        print("   3. See the Advanced Specs tab auto-populate!")
        print("   4. Phase 1 (Metadata Expansion) is COMPLETE! ✅")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n⚠️ Cancelled by user")
    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
