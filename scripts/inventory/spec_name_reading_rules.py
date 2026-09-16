#!/usr/bin/env python3
"""Deterministic name readings for the technical fill.

The sanctioned path for a fact that only the product name supports is the
server RPC `record_product_spec_reading_v1`: it takes a field of the active
template, a value and a literal quote, checks the quote against the product
text and the value against the field (label stems for a single select, an
exact number token, the field vocabulary for a boolean), refuses a field that
already holds a fact of another source, and writes an unconfirmed
`name_reading` fact with its reading receipt.

This module does the reading side offline: per family, a small set of regular
expressions that recognise trade notation in Chilean supplier names
(`36H`, `135x10mm`, `SGS`, `V/FRANCESA`, `9/16`, `160mm`, `14-28T`) and turn
it into (field, value, quote) candidates, then a faithful replica of the RPC
checks that predicts the verdict before any call is made. The replica is a
filter, not the gate: the RPC re-validates every candidate live.

Rules are conservative on purpose. A value is only proposed when the quote
names it in the field's own vocabulary; a family/field with two different
readings on the same product is dropped as ambiguous; nothing is inferred
across fields, and no unit is converted.

Usage:
  spec_name_reading_rules.py --catalog field-catalog.csv --bindings bindings.csv \
      --output candidates.json [--families hub,rim] [--report report.md]
"""
import argparse
import collections
import csv
import json
import re
import unicodedata
from pathlib import Path

csv.field_size_limit(1 << 30)


# --- replica of the SQL checks ---------------------------------------------

def normalize(text):
    """assistant_normalize_query_internal_v1: unaccent, lower, [^a-z0-9]+ -> ' '."""
    stripped = ''.join(c for c in unicodedata.normalize('NFKD', text or '')
                       if not unicodedata.combining(c))
    return re.sub(r'[^a-z0-9]+', ' ', stripped.lower().strip()).strip()


def common_prefix(a, b):
    n = 0
    for x, y in zip(a, b):
        if x != y:
            break
        n += 1
    return n


def shares_stem(quote_word, label_word):
    if len(label_word) < 4 or len(quote_word) < 4:
        return quote_word == label_word
    import math
    return common_prefix(quote_word, label_word) >= max(
        4, math.ceil(0.75 * min(len(quote_word), len(label_word))))


def label_score(quote_norm, label_norm):
    words = [w for w in label_norm.split(' ') if len(w) >= 2]
    quote_words = quote_norm.split(' ')
    covered = sum(1 for w in words if any(shares_stem(q, w) for q in quote_words))
    if not words or not covered:
        return (0.0, 0)
    return (round(covered / len(words), 6), covered)


NUMBER_TOKEN_GUARD_BEFORE = r'(^|[^0-9.,eE+-])'
NUMBER_TOKEN_GUARD_AFTER = r'($|[^0-9.,eE])'


def number_in_quote(value, quote):
    text = str(value)
    if '.' in text:
        text = text.rstrip('0').rstrip('.') if text.rstrip('0').rstrip('.') else '0'
    wanted = text.replace('.', '[.]') + ('0*' if '.' in text else '([.]0+)?')
    if float(value) >= 0:
        wanted = '[+]?' + wanted
    return re.search(NUMBER_TOKEN_GUARD_BEFORE + wanted + NUMBER_TOKEN_GUARD_AFTER,
                     quote.replace('−', '-')) is not None


AUXILIARIES = {'trae', 'tiene', 'incluye', 'indica', 'si', 'el', 'la', 'los', 'las', 'de', 'del',
               'con', 'sin', 'por', 'para', 'y', 'o', 'un', 'una', 'es', 'viene', 'declarado', 'esta'}


def boolean_vocabulary(label, description):
    phrases = [label]
    if description and ':' in description and description.index(':') > 0:
        head = description[:description.index(':')]
        if not normalize(head).startswith('indica'):
            phrases += re.split(r'\s+o\s+|,', head)
    terms = []
    for phrase in phrases:
        if not phrase or not phrase.strip():
            continue
        words = [w for w in normalize(phrase).split(' ') if w and w not in AUXILIARIES]
        if not words or (len(words) == 1 and len(words[0]) < 6):
            continue
        terms.append(' '.join(words))
        terms += [w for w in words if len(w) >= 6]
    return sorted(set(terms))


def boolean_from_vocabulary(text, label, description):
    terms = boolean_vocabulary(label, description)
    tokens = normalize(text).split(' ')
    if not terms or not tokens or tokens == ['']:
        return None
    seen = []
    for term in terms:
        parts = term.split(' ')
        for i in range(0, len(tokens) - len(parts) + 1):
            if tokens[i:i + len(parts)] != parts:
                continue
            negated = any(tokens[i - back] in ('sin', 'no', 'nunca')
                          for back in (1, 2) if i - back >= 0)
            seen.append(not negated)
    if not seen or len(set(seen)) != 1:
        return None
    return seen[0]


def predict(field, value, quote, product_text):
    """Return None when the RPC would record, else the rejection reason."""
    if not quote or not quote.strip():
        return 'la cita viene vacía'
    if len(quote) > 200:
        return 'la cita es demasiado larga'
    if normalize(quote) not in normalize(product_text):
        return 'la cita no está en el texto del producto'
    kind = field['data_type']
    quote_norm = normalize(quote)
    if kind == 'single_select':
        wanted = normalize(str(value))
        labels = {normalize(l): l for l in field['value_labels']}
        if wanted not in labels:
            return 'el valor no está en la lista del campo'
        chosen = label_score(quote_norm, wanted)
        if chosen[1] == 0:
            return 'la cita no dice ese valor'
        siblings = [label_score(quote_norm, l) for l in labels if l != wanted]
        best = max(siblings) if siblings else None
        if best is not None and best > chosen:
            return 'la cita describe mejor otro valor del campo'
        if best is not None and best == chosen:
            return 'la cita no distingue entre dos valores del campo'
        return None
    if kind == 'boolean':
        if not isinstance(value, bool):
            return 'el valor no es un sí o un no'
        read = boolean_from_vocabulary(quote, field['label'], field['description'])
        if read is None:
            return 'la cita no dice lo que el campo nombra'
        if read != value:
            return 'la cita dice lo contrario'
        return None
    if kind == 'number':
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return 'el valor no es un número'
        if not number_in_quote(value, quote):
            return 'la cita no trae ese número'
        return None
    if kind == 'multi_select':
        return 'el servidor todavía no sabe leer una lista de valores'
    return 'el servidor no sabe comprobar este tipo de campo'


# --- extraction rules --------------------------------------------------------

def words(*patterns):
    """A single-select reader: each (label, regex) yields that label with the match as quote."""
    compiled = [(label, re.compile(pattern, re.IGNORECASE)) for label, pattern in patterns]

    def reader(text):
        found = []
        for label, regex in compiled:
            m = regex.search(text)
            if m:
                found.append((label, m.group(0)))
        return found
    return reader


def number(pattern, group=1, allowed=None, cast=int, quote_group=0):
    regex = re.compile(pattern, re.IGNORECASE)

    def reader(text):
        found = []
        for m in regex.finditer(text):
            raw = m.group(group)
            try:
                value = cast(raw.replace(',', '.'))
            except ValueError:
                continue
            if allowed is not None and value not in allowed:
                continue
            found.append((value, m.group(quote_group)))
        return found
    return reader


def flag(pattern, value=True):
    regex = re.compile(pattern, re.IGNORECASE)

    def reader(text):
        m = regex.search(text)
        return [(value, m.group(0))] if m else []
    return reader


def either(*readers):
    def reader(text):
        found = []
        for r in readers:
            found += r(text)
        return found
    return reader


def unless(reader, pattern):
    """Suppress a reader when the text matches a pattern (pairs, ranges, sets)."""
    regex = re.compile(pattern, re.IGNORECASE)

    def guarded(text):
        return [] if regex.search(text) else reader(text)
    return guarded


def first(*readers):
    """The first reader that finds something wins (a set word beats a side word)."""
    def reader(text):
        for r in readers:
            found = r(text)
            if found:
                return found
        return []
    return reader


NB = r'(?<![0-9.,])'  # not preceded by a digit or decimal mark
SIDE_WORDS = r'\b(?:DELANTER[AO]|TRASER[AO]|IZQUIERD[AO]|DERECH[AO]|TRAS|IZQ|DER)\b'
PAIR_WORDS = r'\bPAR\b|\bJUEGO\b|\bJGO\b|\bSET\b'

SPOKE_HOLES = number(NB + r'(28|32|36|40|48)\s?(?:H\b|H\.|HOYOS?\b|AGUJEROS\b|RAYOS\b|HOLES?\b)',
                     allowed={28, 32, 36, 40, 48})
POSITION_F = words(('Delantera', r'\bDELANTER[AO]\b'), ('Trasera', r'\bTRASER[AO]\b'))
POSITION_OR_SET = first(words(('Juego (delantera y trasera)', r'\bJUEGO\b')), POSITION_F)
SPEEDS = (NB + r'(?<![xX/])([5-9]|1[0-3])\s?(?:V\b|V\.|VEL\b|VEL\.|VELOC\b|VELOCIDADES\b|S\b|SPEED\b|-SPEED\b|SI\b)')
COG_RANGE = re.compile(NB + r'(?<!-)(1[0-6])\s?[-/]\s?(\d{2})(\s?T)?\b(?!\s?[-/]\s?\d)')


def cog_reader(which):
    def reader(text):
        found = []
        for m in COG_RANGE.finditer(text):
            small, large = int(m.group(1)), int(m.group(2))
            if not (8 <= small <= 16 and 18 <= large <= 52 and large > small):
                continue
            if which == 'small':
                found.append((small, m.group(0)))
            else:
                # The quote starts at the largest cog so the number token is not
                # preceded by the range dash, which the server reads as a sign.
                found.append((large, text[m.start(2):m.end(0)]))
        return found
    return reader


MATERIAL_ALU = ('Aluminio', r'\bALUM(?:INIO)?(?:CNC)?\b')
MATERIAL_ACERO = ('Acero', r'\bACERO\b(?!\s+INOX)')
MATERIAL_CARBONO = ('Carbono', r'\bCARBONO\b')

RULES = {
    'hub': {
        # A hub set describes its pieces in rows; the single spoke count is not
        # applicable there and the coherence guard refuses the pair.
        'spoke_hole_count': unless(SPOKE_HOLES, PAIR_WORDS + r'|^\s*MAZAS\b'),
        'hub_package_position': POSITION_OR_SET,
        'bearing_system': unless(words(('Sellados', r'\bSELLAD[AO]S?\b')), PAIR_WORDS + r'|^\s*MAZAS\b'),
        'hub_old_mm': either(
            number(NB + r'(100|110|130|135|141|142|148|150|157)\s?[xX]\s?(?:9|10|12|15|20)\s?MM\b',
                   allowed={100, 110, 130, 135, 141, 142, 148, 150, 157}),
            number(NB + r'(?:9|10|12|15|20)\s?MM\s?[xX]\s?(100|110|130|135|141|142|148|150|157)\s?MM\b',
                   allowed={100, 110, 130, 135, 141, 142, 148, 150, 157}),
            number(NB + r'(?<![xX])(100|110|130|135|142|148)\s?MM\b(?!\s?[xX])'),
            number(NB + r'(130|135)\s+OLD\b'),
            number(r'\bBOOST\s+(110|148)\b')),
        'hub_axle_diameter_mm': either(
            number(NB + r'(?:100|110|130|135|141|142|148|150|157)\s?[xX]\s?(9|10|12|15|20)\s?MM\b'),
            number(NB + r'(9|10|12|15|20)\s?MM\s?[xX]\s?(?:100|110|130|135|141|142|148|150|157)\s?MM\b'),
            number(r'\bEJE\s+(12|15|20)\s?MM\b')),
        'hub_drive_receiver_kind': words(('Núcleo de cassette', r'\bN[UÚ]CLEO\b')),
    },
    'rim': {
        'spoke_hole_count': SPOKE_HOLES,
        'rim_wall_type': words(('Doble pared', r'\bDOBLE(?:\s+PARED)?\b'), ('Pared simple', r'\bPARED\s+SIMPLE\b')),
        'rim_material': words(MATERIAL_ALU),
        'bead_seat_diameter_mm': number(NB + r'(622|559|584|507|406|451|540|590|630|635|305|355|349)\s?[xX]\s?\d{2}\s?MM\b'),
    },
    'rear_derailleur': {
        'derailleur_cage_length': words(('Larga (SGS)', r'\bSGS\b|\bLARGA\b'), ('Media (GS)', r'\bGS\b'),
                                        ('Corta (SS)', r'\bSS\b')),
    },
    'shifter': {
        'shifter_position': either(
            words(('Derecho / trasero', r'\bDERECH[OA]\b|\bTRASER[OA]\b|\bTRAS\b'),
                  ('Izquierdo / delantero', r'\bIZQUIERD[OA]\b|\bDELANTER[OA]\b')),
            unless(words(('Par', r'\bPAR\b')), SIDE_WORDS)),
        'shifter_indexed_positions': unless(
            unless(number(SPEEDS, allowed=set(range(3, 14))), r'\d\s?[xX]\s?\d|\d[vV]?\s?/\s?\d{1,2}[vV]'),
            r'(?:' + PAIR_WORDS + r')(?![\s\S]*' + SIDE_WORDS + ')'),
        'shifter_actuation_mode': words(('Indexado', r'\bINDEX\b'), ('Fricción', r'\bFRICCI[OÓ]N\b')),
    },
    'chain': {
        'link_count': number(NB + r'(1[0-3]\d)\s?(?:E\b|L\b|LINKS?\b|ESLABONES\b)', allowed=set(range(100, 141))),
        'chain_width_family': words(('3/32', r'3/32'), ('11/128', r'11/128')),
    },
    'pedal': {
        'pedal_thread_standard': words(('9/16" x 20 TPI', r'9/16')),
        'body_material': words(('Aluminio', r'\bALUMINIO(?:CNC)?\b'), ('Plástico / nylon', r'\bPL[AÁ]ST(?:ICO)?\b\.?')),
        'pedal_type': words(('Plataforma', r'\bPLATAFORMA\b')),
        'sold_as': words(('Par', r'\(PAR\)')),
    },
    'crankset': {
        'crank_arm_length_mm': either(
            number(NB + r'(160|165|170|172\.5|175)\s?MM\b', cast=float, allowed={160, 165, 170, 172.5, 175}),
            number(r'\bBIELA\s+(165|170|175)\b')),
        'crankset_construction': words(('Una pieza (americana)', r'\bAMERICANA\b')),
    },
    'chainring': {
        'teeth_count': unless(number(NB + r'(?<![-/])([2-5]\d)\s?(?:T\b|DTS\b|DIENTES\b)', allowed=set(range(20, 61))),
                              r'\d{2}\s?[-/]\s?\d{2}'),
        'chainring_bcd_mm': number(NB + r'(64|94|96|100|104|110|130)\s?BCD\b'),
        'chainring_package_kind': words(('Juego de platos', r'\bJUEGO\b')),
        'narrow_wide': flag(r'\bNARROW\b'),
    },
    'front_derailleur': {
        # `t/abajo/arriba` names both pulls: it is a dual-pull unit, not a down pull.
        'front_derailleur_cable_pull': words(
            ('Doble tiro (dual pull)', r'\bDUAL\b|\bDOBLE\s+TIR[OÓ]N?\b|\bABAJO\s*/\s*ARRIBA\b|\bARRIBA\s*/\s*ABAJO\b'),
            ('Tiro arriba (top pull)', r'(?<![/A-Z])T/?\s?ARRIBA\b(?!\s*/\s*ABAJO)|\bTIRO\s+ARRIBA\b'),
            ('Tiro abajo (down pull)', r'(?<![/A-Z])T/?\s?ABAJO\b(?!\s*/\s*ARRIBA)|\bTIRO\s+ABAJO\b')),
        'front_derailleur_mount_type': words(('Abrazadera', r'\bABRAZADERA\b')),
    },
    'rotor': {
        'rotor_diameter_mm_value': either(
            number(NB + r'(140|160|180|200|203|220)\s?MM\b'),
            number(NB + r'(140|160|180|200|203|220)[xX]2\.\d\s?MM\b')),
        'rotor_nominal_thickness_mm': number(r'[xX](1\.8|2\.0|2\.3)\s?MM\b', cast=float),
        'rotor_material': words(('Acero Inoxidable', r'\bACERO\s+INOXIDABLE\b')),
        'rotor_floating': flag(r'\bFLOTANTE\b'),
    },
    'freewheel': {
        'sprocket_count': number(SPEEDS, allowed=set(range(5, 13))),
        'smallest_cog_teeth': cog_reader('small'),
        'largest_cog_teeth': cog_reader('large'),
    },
    'cassette': {
        'sprocket_count': number(SPEEDS, allowed=set(range(7, 14))),
        'smallest_cog_teeth': cog_reader('small'),
        'largest_cog_teeth': cog_reader('large'),
    },
    'brake_pad': {
        'braking_surface': words(('Disco', r'\bDISCO\b')),
        'compound_type': words(('Metálico', r'(?<!SEMI )(?<!SEMI-)\bMET[AÁ]LIC[AO]S?\b'),
                               ('Semi-Metálico', r'\bSEMI[\s-]?MET[AÁ]L(?:IC[AO]S?)?\b|\bSEMIMET[AÁ]LIC[AO]S?\b'),
                               ('Cerámico', r'\bCER[AÁ]MIC[AO]S?\b'),
                               ('Orgánico (resina)', r'\bORG[AÁ]N(?:IC[AO]S?)?\b|\bRESINA\b')),
        'rim_pad_length_mm': unless(number(NB + r'(50|55|60|65|70|72)\s?MM\b'), r'\bDISCO\b|\bPASTILLA'),
    },
    'tube': {
        'valve_standard': words(('Auto (Schrader / americana)', r'\bSCHRADER\b|\bAMERICANA\b|\bAUTO\b'),
                                ('Francesa (Presta)', r'\bPRESTA\b|\bFRANCESA\b')),
        'valve_length_mm_value': number(NB + r'(33|35|40|42|48|52|60|80)\s?MM\b', allowed={33, 35, 40, 42, 48, 52, 60, 80}),
    },
    'spoke': {
        'spoke_length_mm': either(
            number(NB + r'(1[7-9]\d|2\d\d|30\d)\s?(?:MM\b|MM\.|\[MM\]|\(MM\))'),
            number(r'\bRAYOS?\s+(1[7-9]\d|2\d\d|30\d)\b(?!\s?[.,]\d)'),
            number(NB + r'(1[7-9]\d|2\d\d|30\d)\s?[xX×]\s?14G\b')),
        'spoke_head_interface': words(('Straight Pull', r'\bSTRAIGHT\s+PULL\b'), ('J-Bend', r'\bJ-BEND\b')),
        'pack_quantity': number(r'\b(36|72|144)\s?(?:UNIDADES\b|U\b)'),
    },
    'bottom_bracket': {
        'spindle_length_mm': either(
            number(NB + r'(1[0-4]\d(?:\.5)?)\s?(?:MM\b|M\b)', cast=float),
            number(r'\b(?:68|73)\s?[xX]\s?(1[0-4]\d(?:\.5)?)\b(?![.,]\d)', cast=float)),
        # spindle_interface only applies when the unit includes a spindle; an
        # integrated (Hollowtech) unit has none, so the guard refuses it.
    },
    'hub_axle': {
        'wheel_position': POSITION_F,
        'axle_length_mm': number(NB + r'(1[3-9]\d)\s?MM\b'),
    },
    'brake_lever': {
        'lever_side': words(('Izquierda', r'\bIZQUIERD[AO]\b'), ('Derecha', r'\bDERECH[AO]\b')),
        'brake_actuation': words(('Hidráulico', r'\bHIDR[AÁ]ULIC[AO]S?\b'), ('Mecánico (cable)', r'\bMEC[AÁ]NIC[AO]S?\b')),
    },
    'light': {
        'light_position': POSITION_OR_SET,
    },
    'lock': {
        'lock_kind': words(('U-lock', r'\bU-LOCK\b'), ('Cadena', r'\bCADENA\b'), ('Cable / espiral', r'\bCABLE\b|\bESPIRAL\b'),
                           ('Plegable', r'\bPLEGABLE\b')),
        'locking_mechanism': words(('Llave', r'\bLLAVES?\b'), ('Clave (combinación)', r'\bCOMBINACI[OÓ]N\b|\bCLAVE\b')),
    },
    'pump': {
        'pump_kind': words(('De pie', r'\bPIE\b'), ('De mano / mini', r'\bMANO\b|\bMINI\b'), ('Inflador CO2', r'\bINFLADOR\b|\bCO2\b')),
    },
    'helmet': {
        'helmet_kind': words(('Urbano', r'\bURBANO\b'), ('Ruta', r'\bRUTA\b'), ('MTB / trail', r'\bMTB\b|\bTRAIL\b'), ('Enduro', r'\bENDURO\b')),
        'intended_audience': words(('Niño / juvenil', r'\bNI[NÑ][OA]S?\b|\bJUVENIL\b'), ('Adulto', r'\bADULTOS?\b')),
    },
    'seatpost': {
        'seatpost_diameter_mm': number(NB + r'(25\.4|27\.2|28\.6|30\.9|31\.6|31\.8|33\.9|34\.9)(?:\s?MM)?\b', cast=float),
        'seatpost_length_mm': number(NB + r'(2[5-9]\d|3\d\d|4[0-5]\d)\s?MM\b'),
        'material': words(MATERIAL_ALU, MATERIAL_ACERO, MATERIAL_CARBONO),
    },
    'stem': {
        'stem_length_mm': unless(number(NB + r'(4\d|5\d|[6-9]\d|1[0-3]\d)\s?MM\b'), r'\bADAPTADOR\b'),
        'bar_clamp_diameter_mm': unless(number(NB + r'(25\.4|31\.8)(?:\s?MM)?\b', cast=float), r'\bADAPTADOR\b'),
        'stem_kind': first(words(('Adaptador quill → ahead', r'\bADAPTADOR\b')), words(('Tee de espiga (quill)', r'\bQUILL\b'))),
        'material': words(MATERIAL_ALU, MATERIAL_ACERO, MATERIAL_CARBONO),
    },
    'handlebar': {
        'bar_width_mm': number(NB + r'(5[8-9]\d|[67]\d\d|800)\s?MM\b'),
        'bar_clamp_diameter_mm': number(NB + r'(25\.4|31\.8)(?:\s?MM)?\b', cast=float),
        'bar_style': words(('Riser', r'\bRISER\b'), ('Recto (plano)', r'\bRECTO\b|\bPLANO\b'), ('Ruta (drop)', r'\bRUTA\b|\bDROP\b')),
        'material': words(MATERIAL_ALU, MATERIAL_ACERO, MATERIAL_CARBONO),
    },
    'saddle': {
        'saddle_intended_use': words(('MTB', r'\bMTB\b'), ('Ruta', r'\bRUTA\b'), ('Niño', r'\bNI[NÑ][OA]S?\b'),
                                     ('Gel / confort', r'\bGEL\b')),
    },
    'grip': {
        'sold_as': words(('Par', r'\bPAR\b')),
    },
    'brake_caliper': {
        'brake_position': words(('Delantero', r'\bDELANTER[OA]\b'), ('Trasero', r'\bTRASER[OA]\b')),
        'brake_actuation': words(('Mecánico (cable)', r'\bMEC[AÁ]NIC[AO]S?\b'), ('Hidráulico', r'\bHIDR[AÁ]ULIC[AO]S?\b')),
    },
    'fork': {
        # An axle spacing reads as `9x100mm`: the travel is the millimetre figure
        # that no `x` precedes, so a fork with both keeps only its travel.
        'travel_mm': number(r'(?<![0-9.,xX])(80|100|120|130|140|150|160|170)\s?MM\b'),
        'hub_old_mm': number(r'(?<![0-9.,])(?:9|15|20)\s?[xX]\s?(100|110)\s?MM\b'),
        'lockout': flag(r'\bBLOQUEO\b'),
        'material': words(MATERIAL_ALU, MATERIAL_ACERO, MATERIAL_CARBONO),
    },
    'wheel_retention': {
        'material': words(MATERIAL_ALU, MATERIAL_ACERO),
    },
    'tire': {
        'tire_bead_type': words(('Alambre', r'\bALAMBRE\b'), ('Plegable (kevlar)', r'\bPLEGABLE\b|\bKEVLAR\b')),
        'tire_use': words(('MTB', r'\bMTB\b'), ('Ruta', r'\bRUTA\b'), ('BMX', r'\bBMX\b')),
        'tire_tpi': number(NB + r'(\d{2,3})\s?TPI\b'),
        'tire_width_mm': number(r'\b700\s?[xX]\s?(\d{2})\s?[cC]\b'),
    },
}


# --- driver ------------------------------------------------------------------

def load_catalog(path):
    catalog = {}
    for row in csv.DictReader(open(path, encoding='utf-8')):
        if row['role'] == 'legacy':
            continue
        catalog[(row['template_key'], row['field_key'])] = {
            'data_type': row['data_type'], 'unit': row['unit'], 'label': row['label'],
            'description': row['description'],
            'value_labels': [v for v in row['value_labels'].split('||') if v],
        }
    return catalog


def load_bindings(path):
    products = []
    for row in csv.DictReader(open(path, encoding='utf-8')):
        facts = {}
        for item in row['facts'].split('|'):
            if item:
                key, _, source = item.rpartition(':')
                facts[key] = source
        products.append({'product_id': row['product_id'], 'name': row['name'],
                         'description': row['description'], 'family': row['template_key'],
                         'facts': facts})
    return products


def build(catalog, products, families=None):
    candidates, dropped = [], []
    for product in products:
        family = product['family']
        if family not in RULES or (families and family not in families):
            continue
        text = ' '.join(x for x in (product['name'], product['description']) if x)
        for field_key, reader in RULES[family].items():
            field = catalog.get((family, field_key))
            if field is None:
                dropped.append({**product_ref(product), 'field_key': field_key, 'why': 'field not filterable/active in live template'})
                continue
            found = reader(text)
            if not found:
                continue
            values = {json.dumps(v, ensure_ascii=False) for v, _ in found}
            if len(values) > 1:
                dropped.append({**product_ref(product), 'field_key': field_key, 'why': 'ambiguous',
                                'readings': [[v, q] for v, q in found]})
                continue
            value, quote = found[0]
            existing = product['facts'].get(field_key)
            if existing and existing != 'name_reading':
                dropped.append({**product_ref(product), 'field_key': field_key, 'why': 'kept_existing:' + existing,
                                'value': value, 'quote': quote})
                continue
            reason = predict(field, value, quote, text)
            entry = {**product_ref(product), 'field_key': field_key, 'data_type': field['data_type'],
                     'value': value, 'quote': quote, 'predicted': reason or 'recorded'}
            (candidates if reason is None else dropped).append(entry if reason is None else {**entry, 'why': reason})
    return candidates, dropped


def product_ref(product):
    return {'product_id': product['product_id'], 'family': product['family'], 'name': product['name']}


def report(candidates, dropped):
    lines = ['# Lecturas de nombre: candidatos', '']
    per = collections.Counter((c['family'], c['field_key']) for c in candidates)
    products = collections.defaultdict(set)
    for c in candidates:
        products[c['family']].add(c['product_id'])
    lines.append(f'Candidatos que el réplica predice como `recorded`: {len(candidates)} lecturas en '
                 f'{sum(len(v) for v in products.values())} productos.')
    lines.append('')
    lines.append('| Familia | Campo | Lecturas |')
    lines.append('|---|---|---:|')
    for (family, field), n in sorted(per.items()):
        lines.append(f'| {family} | {field} | {n} |')
    lines.append('')
    why = collections.Counter(d['why'].split(':')[0] for d in dropped)
    lines.append('Descartados antes de llamar: ' + ', '.join(f'{k} {v}' for k, v in why.most_common()))
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--catalog', required=True)
    parser.add_argument('--bindings', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--families', default='')
    parser.add_argument('--report')
    args = parser.parse_args()
    families = {f for f in args.families.split(',') if f}
    catalog = load_catalog(args.catalog)
    products = load_bindings(args.bindings)
    candidates, dropped = build(catalog, products, families or None)
    Path(args.output).write_text(json.dumps({'candidates': candidates, 'dropped': dropped},
                                            ensure_ascii=False, indent=1) + '\n')
    text = report(candidates, dropped)
    if args.report:
        Path(args.report).write_text(text)
    print(text)


if __name__ == '__main__':
    main()
