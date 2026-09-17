#!/usr/bin/env python3
"""Deterministic name readings for the technical fill.

The sanctioned path for a fact that only the product name supports is the
server RPC `record_product_spec_reading_v1`: it takes a field of the active
template, a value and a literal quote, checks the quote against the product
text and the value against the field (label stems or the option's reading
terms for a single select, an exact number token, the field vocabulary plus
its reading terms for a boolean), refuses a field that already holds a fact of
another source, and writes an unconfirmed `name_reading` fact with its
reading receipt.

This module does the reading side offline: per family, a small set of regular
expressions that recognise trade notation in Chilean supplier names
(`36H`, `135x10mm`, `SGS`, `F/V`, `9/16`, `160mm`, `14-28T`, `QR`, `c/bloqueo`,
`(CL)`, `W/O CG`) and turn it into (field, value, quote) candidates, then a
faithful replica of the RPC checks that predicts the verdict before any call
is made. The replica is a filter, not the gate: the RPC re-validates every
candidate live, and only the RPC sees the product coherence guard (a hub set
refuses the single-hub fields, a gated field needs its prerequisite first).

Rules are conservative on purpose. A value is only proposed when the quote
names it in the field's own vocabulary (label stems or reading terms); a
family/field with two different readings on the same product is dropped as
ambiguous; nothing is inferred across fields, and no unit is converted. The
order of the rules inside a family matters: a prerequisite (position, the
"present" flags) is read before the field it gates.

Usage:
  spec_name_reading_rules.py --catalog field-catalog.csv --bindings bindings.csv \
      --output candidates.json [--families hub,rim] [--report report.md]

The catalog CSV comes from the live definitions and carries, per field, the
option labels, the option reading terms (`label>>t1;t2||…`) and the boolean
reading terms (`reading_terms`, `reading_terms_false`).
"""
import argparse
import collections
import csv
import json
import math
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
    return common_prefix(quote_word, label_word) >= max(
        4, math.ceil(0.75 * min(len(quote_word), len(label_word))))


def label_score(quote_norm, label_norm):
    words = [w for w in label_norm.split(' ') if len(w) >= 2]
    quote_words = quote_norm.split(' ')
    covered = sum(1 for w in words if any(shares_stem(q, w) for q in quote_words))
    if not words or not covered:
        return (0.0, 0)
    return (round(covered / len(words), 6), covered)


def terms_best_length(quote_norm, terms):
    """spec_terms_best_length_internal_v1: the longest whole normalized phrase inside the quote, 0 if none."""
    padded = ' ' + (quote_norm or '') + ' '
    best = 0
    for term in terms or ():
        term_norm = normalize(term)
        if term_norm and (' ' + term_norm + ' ') in padded:
            best = max(best, len(term_norm))
    return best


def terms_hit(quote_norm, terms):
    return terms_best_length(quote_norm, terms) > 0


def option_score(quote_norm, label, terms):
    """A term hit beats any partial label coverage; between terms the longer phrase wins."""
    best = terms_best_length(quote_norm, terms)
    return (1.0, 1000 + best) if best else label_score(quote_norm, normalize(label))


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


def boolean_from_terms(text, terms):
    """spec_boolean_from_terms_internal_v1: every term present votes yes unless
    «sin», «no» or «nunca» sits up to two tokens before it; a split vote or no
    vote reads nothing."""
    tokens = normalize(text).split(' ')
    if not terms or not tokens or tokens == ['']:
        return None
    seen = []
    for term in terms:
        parts = normalize(term).split(' ')
        if not parts or parts == ['']:
            continue
        for i in range(0, len(tokens) - len(parts) + 1):
            if tokens[i:i + len(parts)] != parts:
                continue
            negated = any(tokens[i - back] in ('sin', 'no', 'nunca')
                          for back in (1, 2) if i - back >= 0)
            seen.append(not negated)
    if not seen or len(set(seen)) != 1:
        return None
    return seen[0]


def boolean_from_vocabulary(text, label, description):
    return boolean_from_terms(text, boolean_vocabulary(label, description))


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
        value_terms = field.get('value_terms', {})
        chosen = option_score(quote_norm, labels[wanted], value_terms.get(wanted, []))
        if chosen[1] == 0:
            return 'la cita no dice ese valor'
        siblings = [option_score(quote_norm, labels[l], value_terms.get(l, []))
                    for l in labels if l != wanted]
        best = max(siblings) if siblings else None
        if best is not None and best > chosen:
            return 'la cita describe mejor otro valor del campo'
        if best is not None and best == chosen:
            return 'la cita no distingue entre dos valores del campo'
        return None
    if kind == 'boolean':
        if not isinstance(value, bool):
            return 'el valor no es un sí o un no'
        read = boolean_from_terms(
            quote, boolean_vocabulary(field['label'], field['description']) + field.get('reading_terms', []))
        negative = boolean_from_terms(quote, field.get('reading_terms_false', []))
        if negative is True:
            read = None if read is True else False
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
            if raw is None:
                continue
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


def only_if(reader, pattern):
    """Run a reader only when the text matches a pattern (a washer, a coil lock)."""
    regex = re.compile(pattern, re.IGNORECASE)

    def guarded(text):
        return reader(text) if regex.search(text) else []
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
HUB_SET = PAIR_WORDS + r'|^\s*MAZAS\b'
FRACTION_BEFORE = r'(?<![\d/-])(?<!\d )'   # `1-1/8` and `1 1/8` are steerer sizes, not `1/8`
FRACTION_AFTER = r'(?![\d/])'

SPOKE_HOLES = either(
    number(NB + r'(28|32|36|40|48)\s?(?:H\b|H\.|HOYOS?\b|AGUJEROS\b|RAYOS\b|HOLES?\b)',
           allowed={28, 32, 36, 40, 48}),
    number(NB + r'(28|32|36)/(?:DISCO|SELLAD)', allowed={28, 32, 36}))
POSITION_F = words(('Delantera', r'\bDELANTER[AO]\b'), ('Trasera', r'\bTRASER[AO]\b'))
POSITION_OR_SET = first(words(('Juego (delantera y trasera)', r'\bJUEGO\b|\bJGO\b|\(PAR\)|^\s*MAZAS\b')), POSITION_F)
SPEEDS = (NB + r'(?<![xX/])([5-9]|1[0-3])\s?(?:V\b|V\.|VEL\b|VEL\.|VELOC\b|VELOCIDADES\b|S\b|SPEED\b|-SPEED\b|SI\b)')
COG_RANGE = re.compile(NB + r'(?<!-)(1[0-6])\s?[-/]\s?(\d{2})(\s?T)?\b(?!\s?[-/]\s?\d)')
SINGLE_COG = number(NB + r'(1[2-9]|2[0-4])\s?(?:T\b|DTS\b|DTES\b|DIENTES\b)', allowed=set(range(12, 25)))


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


def single_cog(which):
    """A one-cog freewheel names its only sprocket: smallest and largest are the same."""
    return unless(unless(SINGLE_COG, COG_RANGE.pattern), SPEEDS)


MATERIAL_ALU = ('Aluminio', r'\bALUM(?:INIO)?(?:CNC)?\b|\bALUMIN\b|\bALLOY\b')
MATERIAL_ACERO = ('Acero', r'\bACERO\b(?!\s+INOX)|\bSTEEL\b')
MATERIAL_INOX = ('Acero inoxidable', r'\bACERO\s+INOX(?:IDABLE)?\b|\bINOX(?:IDABLE)?\b|\bSTAINLESS\b')
MATERIAL_CARBONO = ('Carbono', r'\bCARBONO?\b')
MATERIAL_PLASTICO = ('Plástico', r'\bPL[AÁ]STIC[OA]\b|\bPLASTIC\b')
MATERIAL_TITANIO = ('Titanio', r'\bTITANIO\b|\bTITANIUM\b')
VALVE_STANDARD = words(
    ('Francesa (Presta)', r'\bF/V\b|\bFV\b|\bV/F\b|\bPRESTA\b|\bFRANCESA\b'),
    ('Auto (Schrader / americana)', r'\bA/V\b|\bAV\b|\bV/A\b|\bSCHRADER\b|\bAUTO\b|\bAMERICANA\b'))
BRAKE_POSITION = words(('Delantero', r'\bDELANTER[OA]\b'), ('Trasero', r'\bTRASER[OA]\b'))
M_THREADS = words(*[(f'M{n}', rf'\bM{n}(?![0-9.])') for n in (3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 15, 18, 19, 20, 22)])
PACK_UNITS = number(r'(?<!MINIMO )(?<!MIN\.)(?<!MIN )(?<!MIN\. )' + NB
                    + r'(\d{1,3})\s?(?:UNID(?:ADES)?\b\.?|PCS\b|PZS\b|PC\b|UN\b\.?|U\b)')
MM_VOLUME = number(NB + r'(\d{2,4})\s?(?:ML\b|CC\b)')
NINO = r'\bNI[NÑ][OA]S?\b|\bKIDS\b|\bJUNIOR\b|\bINFANTIL\b'


RULES = {
    'hub': {
        'hub_package_position': POSITION_OR_SET,
        # The flags gate the kinds: a rotor mount before its interface, a drive
        # receiver before its kind. A set describes its pieces in rows.
        'hub_rotor_mount_present': unless(flag(r'\bDISCO\b|\bDISC\b|\(CL\)|\bCL\b|\bCENTER\s?LOCK\b'), HUB_SET),
        'hub_drive_receiver_present': unless(
            flag(r'\bTRASER[AO]\b|\bN[UÚ]CLEO\b|\bMICRO\s?SPLINE\b|\bCASSETTE\b|\bFREE\s?WHEEL\b'
                 r'|\bRUEDA LIBRE\b|PI[NÑ][OÓ]N CON HILO|\bFIXI\b|\bFLIP FLOP\b'), HUB_SET),
        'hub_axle_mount_kind': unless(words(
            ('Cierre rápido', r'\bQR\b|\bC/BLOQ(?:UEO)?\b\.?|\bCON BLOQ(?:UEO)?\b\.?|\bBLOQUEO\b|\bQUICK RELEASE\b'),
            ('Eje pasante', r'\bEJE PASANTE\b|\bTHRU AXLE\b'),
            ('Eje con tuercas', r'\bC/TUERCAS?\b|\bCON TUERCAS?\b|\bEJE 3/8\b|(?<![\d/])3/8"')), HUB_SET),
        'rotor_mount_type': unless(words(('Centerlock', r'\(CL\)|\bCL\b|\bCENTER\s?LOCK\b'),
                                         ('6 pernos', r'\b6 (?:PERNOS|BOLTS?|TORNILLOS)\b')), HUB_SET),
        'hub_drive_receiver_kind': unless(words(
            ('Núcleo de cassette', r'\bN[UÚ]CLEO\b|\bMICRO\s?SPLINE\b|\bCASSETTE\b'),
            ('Rosca para piñón (rueda libre)', r'\bFREE\s?WHEEL\b|PI[NÑ][OÓ]N CON HILO|\bRUEDA LIBRE\b'),
            ('Rosca para piñón fijo', r'\bFIXI\b|\bFIXED\b'),
            ('Driver BMX', r'\b9T\b|\bDRIVER\b')), HUB_SET),
        'spoke_hole_count': unless(SPOKE_HOLES, HUB_SET),
        'bearing_system': unless(words(('Sellados', r'\bSELLAD[AO]S?\b|\bSEALED\b'),
                                       ('Bolas sueltas', r'\bBOLITAS\b|\bBOLAS\b')), HUB_SET),
        'hub_old_mm': either(
            number(NB + r'(100|110|130|135|141|142|148|150|157)\s?[xX]\s?(?:9|10|12|15|20)\s?MM\b',
                   allowed={100, 110, 130, 135, 141, 142, 148, 150, 157}),
            number(NB + r'(?:9|10|12|15|20)\s?MM\s?[xX]\s?(100|110|130|135|141|142|148|150|157)\s?MM\b',
                   allowed={100, 110, 130, 135, 141, 142, 148, 150, 157}),
            number(NB + r'(?<![xX])(100|110|130|135|142|148)\s?MM\b(?!\s?[xX])'),
            number(NB + r'(130|135)\s+OLD\b'),
            number(r'\bBOOST\s+(110|148)\b'),
            number(NB + r'(?:12|15|20)\s?[xX]\s?(100|110|142|148|157)\b(?![\d.,])')),
        'hub_axle_diameter_mm': either(
            number(NB + r'(?:100|110|130|135|141|142|148|150|157)\s?[xX]\s?(9|10|12|15|20)\s?MM\b'),
            number(NB + r'(9|10|12|15|20)\s?MM\s?[xX]\s?(?:100|110|130|135|141|142|148|150|157)\s?MM\b'),
            number(r'\bEJE\s+(12|15|20)\s?MM\b'),
            number(NB + r'(12|15|20)\s?[xX]\s?(?:100|110|142|148|157)\b(?![\d.,])'),
            number(r'\b(14)\s?MM\b(?=\s+\d{1,2}T\b)')),
    },
    'hub_axle': {
        'wheel_position': POSITION_F,
        'axle_length_mm': number(NB + r'(1[3-9]\d)\s?MM\b'),
        'axle_hollow': either(flag(r'\bPERFORAD[AO]\b|\bHUECO\b|\bPARA BLOQUEO\b|\bBLOQUEO\b|\bQUICK RELEASE\b|\bQR\b'),
                              flag(r'\bMACIZO\b', False)),
        'cones_and_locknuts_included': flag(r'\bCOMPLET[AO]\b|\bCON CONOS\b|\bC/CONOS\b'),
    },
    'rim': {
        'spoke_hole_count': SPOKE_HOLES,
        'rim_wall_type': words(('Doble pared', r'\bDOBLE(?:\s+PARED)?\b|\bD/PARED\b'), ('Pared simple', r'\bPARED\s+SIMPLE\b')),
        'rim_material': words(MATERIAL_ALU),
        'rim_tubeless_ready': flag(r'\bTLR\b|\bTUBELESS\b|\bTL\b(?=\s)'),
        'bead_seat_diameter_mm': number(NB + r'(622|559|584|507|406|451|540|590|630|635|305|355|349)\s?[xX]\s?\d{2}\s?MM\b'),
    },
    'rear_derailleur': {
        'derailleur_cage_length': words(('Larga (SGS)', r'\bSGS\b|\bLARGA\b'), ('Media (GS)', r'\bGS\b'),
                                        ('Corta (SS)', r'\bSS\b')),
        'rear_derailleur_mount_type': words(
            ('Con uña / claw', r'\bAPERNAR\b|\bAPERNADO\b|\bCON PATA\b|\bC/PATA\b|\bW/RIVETED ADAPTER\b|\bCLAW\b'),
            ('Pata/postiza estándar', r'\bDIRECT ATTACHMENT\b|\bDIRECTO\b|\bS/PATA\b')),
        'rear_derailleur_supplied_mount_adapter': flag(r'\bW/RIVETED ADAPTER\b|\bCON PATA\b|\bC/PATA\b'),
    },
    'shifter': {
        'shifter_position': either(
            words(('Derecho (trasero)', r'\bDERECH[OA]\b|\bTRASER[OA]\b|\bTRAS\b|\bDER\b|\bRIGHT\b'),
                  ('Izquierdo (delantero)', r'\bIZQUIERD[OA]\b|\bDELANTER[OA]\b|\bIZQ\b|\bLEFT\b')),
            unless(words(('Par', r'\bPAR\b|\bJUEGO\b|"JUEGO"')), SIDE_WORDS)),
        'shifter_indexed_positions': unless(
            unless(number(SPEEDS, allowed=set(range(3, 14))), r'\d\s?[xX]\s?\d|\d[vV]?\s?/\s?\d{1,2}[vV]'),
            r'(?:' + PAIR_WORDS + r')(?![\s\S]*' + SIDE_WORDS + ')'),
        'shifter_actuation_mode': unless(words(('Indexado', r'\bINDEX\b|\bSINCRONIZAD[OA]\b|\bSIS\b'),
                                               ('Fricción', r'\bFRICCI[OÓ]N\b|\bFRICTION\b')),
                                         r'(?:' + PAIR_WORDS + r'|"JUEGO")(?![\s\S]*' + SIDE_WORDS + ')'),
        'shifter_control_style': unless(words(
            ('Giro (twist)', r'\bGIRO\b|\bTWIST\b|\bREVO\s?SHIFT\b|\bGRIP\s?SHIFT\b'),
            ('Gatillo (trigger)', r'\bGATILLO\b|\bTRIGGER\b|\bRAPID\s?FIRE\b'),
            ('Palanca de pulgar', r'\bTHUMB\s?SHIFTER\b|\bPULGAR\b'),
            ('Integrado con la maneta de freno', r'\bCAMBIO\s*/?\s*FRENO\b|\bCAMBIO Y FRENO\b|\bEZ-?FIRE\b|\bINTEGRAD[OA]\b')),
                                        r'(?:' + PAIR_WORDS + r'|"JUEGO")(?![\s\S]*' + SIDE_WORDS + ')'),
    },
    'chain': {
        'link_count': number(NB + r'(1[0-3]\d)\s?(?:E\b|L\b|LINKS?\b|ESLABONES\b)', allowed=set(range(100, 141))),
        'chain_width_family': words(('3/32', r'3/32'), ('11/128', r'11/128'), ('1/8', FRACTION_BEFORE + r'1/8' + FRACTION_AFTER)),
        'drivetrain_mode': words(
            ('Single speed / BMX / IGH', r'\bBMX\b|\bSINGLE\s?SPEED\b|\b1 VEL\b\.?|\bFIXIE\b'),
            ('Derailleur', r'(?<![\d/xX])(?:[6-9]|1[0-2])\s?(?:VEL\b\.?|V\b\.?|VELOCIDADES\b|-?SPEED\b|S\b)(?!\s?/)')),
        'quick_link_included': flag(r'\bW/QUICK-?LINK\b|\bQUICK-?LINK\b|\bMISSING\s?LINK\b|\bCON CONECTOR\b|\bC/CONECTOR\b'),
    },
    'chain_link': {
        'chain_connector_type': words(('Missing link', r'\bMISSING\s?LINK\b')),
        'chain_link_pack_qty': either(number(r'\((\d)\s?PIEZAS\)'), number(r'\b(\d)\s?PCS\b'), number(r'\b(\d)P\b')),
    },
    'pedal': {
        'pedal_thread_standard': words(('9/16" x 20 TPI', r'9/16'), ('1/2" x 20 TPI', FRACTION_BEFORE + r'1/2' + FRACTION_AFTER)),
        'body_material': words(('Aluminio', r'\bALUMINIO(?:CNC)?\b|\bALUM\b'),
                               ('Plástico / nylon', r'\bPL[AÁ]ST(?:ICO)?\b\.?|\bRESINA\b|\bTERMOPL[AÁ]STIC[AO]\b|\bPLASTIC\b'),
                               ('Magnesio', r'\bMAGNESIO\b')),
        'pedal_type': words(('Plataforma', r'\bPLATAFORMA\b|\bPLAN[OA]\b|\bFLAT\b'),
                            ('Automático (clipless)', r'\bCALAS?\b|\bCLIPLESS\b|\bSPD\b')),
        'sold_as': words(('Par', r'\((?:PAR|JUEGO)\)|\bPAR\b')),
        'reflectors_included': flag(r'\bC/REF(?:LECTOR)?\b\.?|\bCON REFLECTOR(?:ES)?\b'),
        'replaceable_pins': flag(r'\bC/PINES\b|\bPINES\b|\bC/PINCHOS\b|\bPINCHOS\b|\bPINS\b'),
    },
    'crank_arm': {
        'crank_side': words(('Izquierda', r'\bIZQU(?:I)?ERDA\b|\bIZQ\b'), ('Derecha', r'\bDERECHA\b|\bDER\b')),
        'crank_arm_carries_chainring_mount': either(flag(r'\bIZQU(?:I)?ERDA\b|\bIZQ\b', False),
                                                    flag(r'\bDERECHA\b|\bDER\b', True)),
        'crank_arm_length_mm': number(NB + r'(160|165|170|172\.5|175)\s?M{1,2}\b', cast=float, allowed={160, 165, 170, 172.5, 175}),
        'crank_arm_system_construction': words(
            ('Tres piezas (eje independiente)', r'\bPARA EJE\b(?!\s+DE MOTOR INTEGRADO)|\bP/EJE\b'),
            ('Dos piezas (eje solidario al brazo derecho)', r'\bMOTOR INTEGRADO\b|\bINTEGRAD[AO]\b')),
        'pedal_thread': words(('9/16', r'9/16'), ('1/2', FRACTION_BEFORE + r'1/2' + FRACTION_AFTER)),
    },
    'crankset': {
        'crank_arm_length_mm': either(
            number(NB + r'(160|165|170|172\.5|175)\s?MM\b', cast=float, allowed={160, 165, 170, 172.5, 175}),
            number(r'\bBIELA\s+(165|170|175)\b')),
        'crankset_construction': words(
            ('Una pieza (americana)', r'\bAMERICANA\b'),
            ('Dos piezas (integrado)', r'\bINTEGRAD[AO]\b|\bHOLLOWTECH\b'),
            ('Tres piezas (motor aparte)', r'\bP/EJE\b|\bPARA EJE\b|\bPTA\.? CUAD(?:RADA)?\b|\bPUNTA CUADRADA\b')),
        'crankset_chain_guard_included': either(
            flag(r'\bC/\s?CUBRE\b|\bCON CUBRE\b|\bCUBRE\s?CADENA\b|\bC/CUB\b\.?|\bW/CG\b|\bCHAIN CASE\b'),
            flag(r'\bW/O CG\b|\bS/CUBRE\b|\bSIN CUBRE\b', False)),
        'bottom_bracket_included': either(
            flag(r'\+\s?MOTOR BSA\b|\bMOTOR BSA\b|\bCON MOTOR\b|\bC/MOTOR\b|\bMOTOR INCLUIDO\b'),
            flag(r'\bSIN MOTOR\b|\bS/MOTOR\b', False)),
        'chainring_mounting': words(('Platos desmontables por pernos', r'\(DESMONTABLE\)|\bDESMONTABLES?\b')),
    },
    'chainring': {
        'chainring_package_kind': words(('Juego de platos', r'\bJUEGO\b')),
        'chainring_position': words(('Único', r'\bMONOPLATO\b|\bMONO PLATO\b')),
        'teeth_count': unless(number(NB + r'(?<![-/])([2-5]\d)\s?(?:T\b|DTS\b|DIENTES\b)', allowed=set(range(20, 61))),
                              r'\d{2}\s?[-/]\s?\d{2}'),
        'chainring_bcd_mm': number(NB + r'(64|94|96|100|104|110|130)\s?BCD\b'),
        'narrow_wide': flag(r'\bNARROW\b'),
    },
    'front_derailleur': {
        # `t/abajo/arriba` names both pulls: it is a dual-pull unit, not a down pull.
        'front_derailleur_cable_pull': words(
            ('Doble tiro (dual pull)', r'\bDUAL\b|\bDOBLE\s+TIR[OÓ]N?\b|\bABAJO\s*/\s*ARRIBA\b|\bARRIBA\s*/\s*ABAJO\b'),
            ('Tiro arriba (top pull)', r'(?<![/A-Z])T/?\s?ARRIBA\b(?!\s*/\s*ABAJO)|\bTIRO\s+ARRIBA\b'),
            ('Tiro abajo (down pull)', r'(?<![/A-Z])T/?\s?ABAJO\b(?!\s*/\s*ARRIBA)|\bTIRO\s+ABAJO\b')),
        'front_derailleur_mount_type': words(('Abrazadera', r'\bABRAZADERA\b'), ('Braze-on', r'\bBRAZE-?ON\b')),
        'front_derailleur_swing': words(('Tradicional (top swing)', r'\bTOP[- ]?SWING\b'),
                                        ('Down swing', r'\bDOWN[- ]?SWING\b'), ('Side swing', r'\bSIDE[- ]?SWING\b')),
    },
    'rotor': {
        'rotor_diameter_mm_value': either(
            number(NB + r'(140|160|180|200|203|220)\s?MM\b'),
            number(NB + r'(140|160|180|200|203|220)[xX]2\.\d\s?MM\b')),
        'rotor_nominal_thickness_mm': number(r'[xX](1\.8|2\.0|2\.3)\s?MM\b', cast=float),
        'rotor_material': words(('Acero Inoxidable', r'\bACERO\s+INOXIDABLE\b|\bINOX\b'), ('Acero', r'\bACERO\b(?!\s+INOX)')),
        'rotor_floating': flag(r'\bFLOTANTE\b|\bFLOATING\b'),
        'rotor_mount_type': words(('Centerlock', r'\bCENTER\s?LOCK\b|\(CL\)|\bCL\b'),
                                  ('6 pernos', r'\b6 (?:PERNOS|TORNILLOS|BOLTS?)\b|\bCON TORNILLOS\b')),
    },
    'freewheel': {
        'sprocket_count': number(SPEEDS, allowed=set(range(5, 13))),
        'smallest_cog_teeth': either(cog_reader('small'), single_cog('small')),
        'largest_cog_teeth': either(cog_reader('large'), single_cog('large')),
    },
    'cassette': {
        'sprocket_count': number(SPEEDS, allowed=set(range(7, 14))),
        'smallest_cog_teeth': cog_reader('small'),
        'largest_cog_teeth': cog_reader('large'),
        'cassette_spline_standard': words(('Shimano MICRO SPLINE (MTB 12v)', r'\bMICRO\s?SPLINE\b'), ('SRAM XD', r'\bXD\b(?!R)')),
        'shift_technology': words(('SRAM Eagle', r'\bEAGLE\b'), ('LINKGLIDE', r'\bLINK\s?GLIDE\b')),
    },
    'brake_pad': {
        'braking_surface': words(('Disco', r'\bDISCO\b'),
                                 ('Llanta', r'\bV-?BRAKE\b|\bPAT[IÍ]N(?:ES)?\b(?!\s+EL[EÉ]CTRICO)|\bTIRO LATERAL\b|1/2 PISTA')),
        'compound_type': words(('Metálico', r'(?<!SEMI )(?<!SEMI-)\bMET[AÁ]LIC[AO]S?\b'),
                               ('Semi-Metálico', r'\bSEMI[\s-]?MET[AÁ]L(?:IC[AO]S?)?\b|\bSEMIMET[AÁ]LIC[AO]S?\b'),
                               ('Cerámico', r'\bCER[AÁ]MIC[AO]S?\b'),
                               ('Orgánico (resina)', r'\bORG[AÁ]N(?:IC[AO]S?)?\b|\bRESINA\b')),
        'pad_spring_included': flag(r'\bW/\s?SPRING\b|\bCON RESORTE\b|\bSPRING\b'),
        'rim_pad_stud_type': words(('Espárrago roscado', r'\bCON TUERCAS?\b|\bC/TUERCA\b|\bTUERCA(?: ALLEN)?\b'),
                                   ('Poste liso', r'\bCON V[AÁ]STAGO\b|\bC/V[AÁ]STAGO\b|\bV[AÁ]STAGO\b')),
        'rim_pad_length_mm': unless(number(NB + r'(50|55|60|65|70|72)\s?MM\b'), r'\bDISCO\b|\bPASTILLA'),
        'pack_quantity': number(r'\b([24])\s?U\b(?!\S)'),
    },
    'tube': {
        'valve_standard': VALVE_STANDARD,
        'valve_length_mm_value': number(NB + r'(33|35|40|42|44|48|50|52|60|80)\s?MM\b', allowed={33, 35, 40, 42, 44, 48, 50, 52, 60, 80}),
    },
    'tubeless_valve': {
        'valve_standard': VALVE_STANDARD,
        'valve_length_mm_value': number(NB + r'(33|35|40|42|44|48|50|52|60|80)\s?MM\b', allowed={33, 35, 40, 42, 44, 48, 50, 52, 60, 80}),
        'pack_quantity': unless(number(NB + r'(\d{1,2})\s?UN\b\.?'), r'\bOB[UÚ]S\b|\bN[UÚ]CLEO\b'),
    },
    'spoke': {
        'spoke_length_mm': either(
            number(NB + r'(1[7-9]\d|2\d\d|30\d)\s?(?:MM\b|MM\.|\[MM\]|\(MM\))'),
            number(r'\bRAYOS?\s+(1[7-9]\d|2\d\d|30\d)\b(?!\s?[.,]\d)'),
            number(NB + r'(1[7-9]\d|2\d\d|30\d)\s?[xX×]\s?14G\b')),
        'spoke_head_interface': words(('Straight Pull', r'\bSTRAIGHT\s+PULL\b'), ('J-Bend', r'\bJ-BEND\b')),
        'pack_quantity': number(r'\b(36|72|144)\s?(?:UNIDADES\b|U\b)'),
        'nipples_included': flag(r'\bC/\s?NIP(?:P)?LES\b|\bCON NIP(?:P)?LES\b|\bNIP(?:P)?LES?\b'),
    },
    'bottom_bracket': {
        'spindle_length_mm': either(
            number(NB + r'(1[0-4]\d(?:\.5)?)\s?(?:MM\b|M\b)', cast=float),
            number(r'\b(?:68|73)\s?[xX]\s?(1[0-4]\d(?:\.5)?)\b(?![.,]\d)', cast=float)),
        # spindle_interface only applies when the unit includes a spindle; an
        # integrated (Hollowtech) unit has none, so the guard refuses it.
        'includes_spindle': either(flag(r'\bEJE DE MOTOR\b|\bEJE MOTOR\b|\bEJE SELLADO\b|\bCON EJE\b'),
                                   flag(r'\bHOLLOWTECH\b|\bINTEGRADO\b|\bPRESS-?FIT\b', False)),
    },
    'brake_lever': {
        'lever_side': words(('Izquierda', r'\bIZQUIERD[AO]\b|\bIZQ\b'), ('Derecha', r'\bDERECH[AO]\b|\bDER\b')),
        'brake_actuation': words(('Hidráulico', r'\bHIDR[AÁ]ULIC[AO]S?\b'), ('Mecánico (cable)', r'\bMEC[AÁ]NIC[AO]S?\b')),
        'lever_cable_pull': words(('Tiro largo (V-brake / disco mecánico tiro largo)', r'\bV-?BRAKE\b|\bTIRO LARGO\b'),
                                  ('Tiro corto (ruta / cantilever / caliper)', r'\bRUTA\b|\bTIRO CORTO\b')),
    },
    'brake_caliper': {
        'brake_position': BRAKE_POSITION,
        'brake_actuation': words(('Mecánico (cable)', r'\bMEC[AÁ]NIC[AO]S?\b'), ('Hidráulico', r'\bHIDR[AÁ]ULIC[AO]S?\b')),
        'braking_surface': words(('Disco', r'\bDISCO\b|\bDISC\b'), ('Llanta', r'\bV-?BRAKE\b')),
        'caliper_mount_interface': words(('Post Mount', r'\bPM\b|\bPOST MOUNT\b'), ('Flat Mount', r'\bFM\b|\bFLAT MOUNT\b')),
        'piston_count_value': number(r'\b([24])\s?PISTONES\b'),
    },
    'rim_brake': {
        'brake_presentation': unless(words(('Par de mecanismos',
                                            r'\bDEL/TRAS?\b|\bDELANTERO Y TRASERO\b|\[JUEGO\]|\(JUEGO\)|\bJUEGO\b|\bJGO\b|\bSET\b|\bPAR\b')),
                                     r'^\s*RESORTE\b|\bCOMPLETO\b|\bMANETAS?\b|\bMANILLAS?\b|-\s*(?:DELANTERO|TRASERO)\b'),
    },
    'hydraulic_disc_brake': {
        'brake_presentation': words(('Par delantero y trasero', r'^\s*JUEGO DE FRENOS\b|\bDEL/TRAS?\b|\bDELANTERO Y TRASERO\b')),
    },
    'light': {
        'light_position': POSITION_OR_SET,
        'lumens_claimed': number(NB + r'(\d{2,4})\s?(?:LM\b|L\b|LUMENS?\b|LUMEN(?:ES)?\b)'),
    },
    'lock': {
        'lock_kind': words(('U-lock', r'\bU-?LOCK\b'), ('Cadena', r'\bCADENA\b'), ('Cable / espiral', r'\bCABLE\b|\bESPIRAL\b'),
                           ('Plegable', r'\bPLEGABLE\b')),
        'locking_mechanism': words(('Llave', r'\bLLAVES?\b'), ('Clave (combinación)', r'\bCOMBINACI[OÓ]N\b|\bCLAVE\b')),
        'cable_diameter_mm': only_if(number(r'\b1[58]0\s?(?:CM)?\s?[xX]\s?(8|10|12)\s?M{0,2}\b'), r'\bESPIRAL\b'),
    },
    'pump': {
        'pump_kind': words(('De pie', r'\bPIE\b|\bPISO\b|\bFLOOR\b'), ('De mano / mini', r'\bMANO\b|\bMINI\b'),
                           ('Inflador CO2', r'\bINFLADOR\b|\bCO2\b'), ('Bomba de suspensión', r'\bSHOCK\b|\bSUSPENSI[OÓ]N\b')),
        'gauge': flag(r'\bC/\s?MAN[OÓ]METRO\b|\bCON MAN[OÓ]METRO\b|\bMAN[OÓ]METRO\b'),
        'barrel_material': words(('Plástico / resina', r'\bRESINA\b|\bPL[AÁ]STICO\b|\bPLASTIC\b'), ('Acero', r'\bACERO\b')),
    },
    'helmet': {
        'helmet_kind': words(('Urbano', r'\bURBANO\b'), ('Ruta', r'\bRUTA\b'), ('MTB / trail', r'\bMTB\b|\bTRAIL\b'), ('Enduro', r'\bENDURO\b')),
        'intended_audience': words(('Niño / juvenil', NINO + r'|\bJUVENIL\b'), ('Adulto', r'\bADULTOS?\b')),
        'adjustable_fit': flag(r'\bAJUSTABLE\b|\bREGULABLE\b|\bCON REGULADOR\b'),
    },
    'seatpost': {
        'seatpost_diameter_mm': number(NB + r'(22\.2|25\.4|26\.4|26\.8|27\.0|27\.2|28\.6|30\.9|31\.6|31\.8|33\.9|34\.9)(?:\s?MM)?\b', cast=float),
        'seatpost_length_mm': either(number(NB + r'(2[5-9]\d|3\d\d|4[0-5]\d)\s?MM\b'),
                                     number(r'[xX]\s?(300|350|400|450)\b(?!\s?[.,]\d)')),
        'seatpost_kind': words(('Rígida', r'\bR[IÍ]GIDA\b'), ('Con suspensión', r'\bSUSPENSI[OÓ]N\b|\bCON RESORTE\b'),
                               ('Telescópica (dropper)', r'\bDROPPER\b|\bTELESC[OÓ]PICA\b')),
        'material': words(MATERIAL_ALU, MATERIAL_ACERO, MATERIAL_CARBONO),
    },
    'stem': {
        'stem_kind': first(words(('Adaptador (quill a ahead)', r'\bADAPTADOR\b')),
                           words(('Ahead (sin rosca)', r'\bA-?HEAD\b'), ('De espiga (quill)', r'\bQUILL\b|\bESPIGA\b'))),
        'stem_length_mm': unless(either(number(NB + r'(4\d|5\d|[6-9]\d|1[0-3]\d)\s?MM\b'),
                                        number(r'[xX]\s?(4\d|5\d|[6-9]\d|1[0-3]\d)\b(?![.,]\d)(?!\s?[.,]\d)')), r'\bADAPTADOR\b'),
        'bar_clamp_diameter_mm': unless(number(NB + r'(25\.4|31\.8)(?:\s?MM)?\b', cast=float), r'\bADAPTADOR\b'),
        'stem_angle_deg': number(NB + r'(\d{1,2})\s?(?:GRADOS\b|°|º)'),
        'quill_diameter_mm': either(number(r'\bADAPTADOR TEE (22\.2|25\.4)/', cast=float),
                                    number(r'\b(22\.2)\s?[xX]\s?25\.4\b', cast=float)),
        'quill_adapter_output_diameter_mm': only_if(number(r'(?:22\.2|25\.4)/(28\.6)\b', cast=float), r'\bADAPTADOR\b'),
        'material': words(MATERIAL_ALU, MATERIAL_ACERO, MATERIAL_CARBONO),
    },
    'handlebar': {
        'bar_width_mm': either(number(NB + r'(5[4-9]\d|[67]\d\d|8[0-2]\d)\s?MM\b'),
                               number(NB + r'(5[4-9]\d|[67]\d\d|8[0-2]\d)\s?[xX]\s?\d{1,2}°'),
                               number(r'\bW:(5[4-9]\d|[67]\d\d|8[0-2]\d)X'),
                               number(r'[xX]\s?(5[4-9]\d|[67]\d\d|8[0-2]\d)\b(?!\s?MM)(?![.,]\d)')),
        'bar_clamp_diameter_mm': number(NB + r'(25\.4|31\.8)(?:\s?MM)?\b', cast=float),
        'bar_rise_mm': either(number(r'\bRISE\s?((\d{2})\s?MM)\b', group=2, quote_group=1), number(r'\b(\d{2})\s?RISE\b')),
        'bar_style': words(('Riser', r'\bRISER\b'), ('Recto (plano)', r'\bRECTO\b|\bPLANO\b'), ('Ruta (drop)', r'\bRUTA\b|\bDROP\b'),
                           ('BMX', r'\bBMX\b'), ('Urbano / paseo', r'\bPLAYERA\b|\bBEACH\b|\bPASEO\b|\bCITY\b')),
        'material': words(MATERIAL_ALU, MATERIAL_ACERO, MATERIAL_CARBONO),
    },
    'saddle': {
        'saddle_intended_use': words(('MTB', r'\bMTB\b'), ('Ruta', r'\bRUTA\b'), ('Niño', NINO),
                                     ('Gel / confort', r'\bGEL\b'), ('Urbano / confort', r'\bPASEO\b|\bURBAN[OA]\b|\bCITY\b')),
        'saddle_cutout': flag(r'\bPROST[AÁ]TIC[OA]\b|\bPERFORAD[OA]\b|\bCON CANAL\b|\bVENTANA\b'),
        'saddle_length_mm': number(r'\b(2[2-9]\d)\s?[xX]\s?1[0-9]\d\s?MM\b'),
        'saddle_width_mm': number(r'\b2[2-9]\d\s?[xX]\s?(1[0-9]\d)\s?MM\b'),
    },
    'grip': {
        'sold_as': words(('Par', r'\(PAR\)|\bPAR\b')),
        'grip_attachment': words(('Lock-on (doble abrazadera)', r'\b2 LOCK\b|\bDOBLE LOCK\b|\bDUAL LOCK\b'),
                                 ('Lock-on (una abrazadera)', r'\b1 LOCK\b|\bEN UN SOLO LADO\b'),
                                 ('Deslizante', r'\bSLIDE ON\b|\bSIN LOCK\b')),
        'grip_length_mm': unless(number(NB + r'(9\d|1[0-4]\d)\s?MM\b', allowed=set(range(90, 150))), PAIR_WORDS + r'|\(PAR\)'),
        'intended_rider': words(('Niño', NINO), ('Adulto', r'\bADULTOS?\b')),
    },
    'seat_clamp': {
        'clamp_kind': words(('Collarín con cierre rápido', r'\bCIERRA? R[AÁ]PIDO\b|\bBLOQUEO\b|\bQR\b'),
                            ('Aguja / palanca de repuesto', r'\bAGUJA\b'),
                            ('Collarín con perno', r'\bCON PERNO\b|\bALLEN\b')),
        'seat_tube_outer_diameter_mm': number(NB + r'(28\.6|30\.0|31\.8|34\.9|35|36\.4)(?:\s?MM)?\b(?![.,]\d)', cast=float),
        'material': words(MATERIAL_ALU, MATERIAL_ACERO, MATERIAL_CARBONO),
    },
    'fastener': {
        'fastener_kind': first(words(('Golilla / espaciador', r'\bGOLILLAS?\b')),
                               words(('Perno', r'\bPERNOS?\b'), ('Tornillo', r'\bTORNILLOS?\b'), ('Tuerca', r'\bTUERCAS?\b'))),
        'declared_purpose': words(('Perno de biela (cuadrado)', r'\bEJE CUADRADO\b|\bPARA CUADRADA\b|\bCUADRAD[AO]\b'),
                                  ('Perno de plato', r'\bCORONAS?\b'),
                                  ('Perno de rotor', r'\bFRENO DISCO\b|\bDISCO FRENO\b|\bROTOR\b'),
                                  ('Perno de portacaramagiola', r'\bPORTA\s?CARAMA[YG]I?OLAS?\b'),
                                  ('Perno de patilla', r'\bPOSTIZA\b')),
        'head_drive': words(('Torx', r'\bTORQ\b|\bTORX\b|\bT25\b'), ('Hexagonal interior (Allen)', r'\bALLEN\b')),
        'thread': unless(either(M_THREADS, words(('3/8"', FRACTION_BEFORE + r'3/8' + FRACTION_AFTER))), r'\bGOLILLA\b'),
        'length_mm': unless(number(r'\bM\d{1,2}\s?[xX ]\s?(\d{1,2}(?:\.\d)?)\s?MM\b', cast=float), r'\bGOLILLA\b'),
        'washer_thickness_mm': only_if(number(r'\bM\d{1,2}\s+(\d(?:\.\d)?)\s?MM\b', cast=float), r'\bGOLILLA\b'),
        'pack_quantity': PACK_UNITS,
        'material': words(MATERIAL_ACERO, MATERIAL_INOX, MATERIAL_ALU, MATERIAL_TITANIO),
    },
    'bearing': {
        'ball_diameter_in': words(('1/8', FRACTION_BEFORE + r'1/8' + FRACTION_AFTER), ('5/32', r'5/32'), ('3/16', r'3/16'),
                                  ('7/32', r'7/32'), ('1/4', FRACTION_BEFORE + r'1/4' + FRACTION_AFTER)),
        'bearing_application': words(('Maza', r'\bMAZA\b|\bRUEDA\b|\bEJE TRASERO\b|\bEJE DELANTERO\b'),
                                     ('Dirección', r'\bDIRECCI[OÓ]N\b'), ('Pedalier', r'\bTHOMPSON\b|\bMOTOR\b')),
        'bearing_supply_form': words(('Canastillo con bolas', r'\bCANASTILLO\b|\bENJAULAD[AO]\b'),
                                     ('Bolas sueltas', r'\bEN BOLSA\b|\bBOLSA\b|\bGRUESA\b')),
    },
    'hub_small_part': {
        'hub_part_kind': words(('Cono', r'\bCONOS?\b'), ('Contratuerca', r'\bCONTRATUERCA\b'), ('Adaptador de eje', r'\bADAPTADOR DE EJE\b')),
        'wheel_position': POSITION_F,
        'dust_cap_included': flag(r'\bCON CUBRE\s?POLVO\b|\bCUBRE\s?POLVO\b|\bGUARDAPOLVO\b'),
        'pack_quantity': PACK_UNITS,
    },
    'control_cable': {
        'pack_quantity': number(r'(?<!MIN\.)(?<!MIN )\b(\d{2,3})\s?PCS\b'),
        'material': words(MATERIAL_INOX),
    },
    'workshop_tool': {
        'tool_kind': unless(words(
            ('Corta cadena', r'\bCORTA\s?CADENAS?\b'),
            ('Desmontador de neumático', r'\bDESMONTADOR(?:ES)?\b'),
            ('Extractor de biela', r'\bEXTRACTOR (?:DE )?BIELAS?\b|\bEXTRACTOR PERNO BIELA\b|\bEXTRACTOR (?:DE )?VOLANTE\b'),
            ('Extractor de cassette / rueda libre', r'\bEXTRACTOR (?:DE )?(?:CASSETTE|PI[NÑ][OÓ]N)\b'),
            ('Llave de pedalier', r'\bEXTRACTOR (?:DE )?MOTOR\b|\bMOTOR SELLADO\b'),
            ('Llave de rayos', r'\bTIRA\s?RAYOS\b'),
            ('Llave de pedales', r'\bLLAVE (?:DE )?PEDAL(?:ES)?\b|\bLLAVE SHIMANO PEDAL\b'),
            ('Multiherramienta', r'\bHERRAMIENTA MULTIFUNCIONAL\b|\bMULTI\s?TOOL\b|\b\d{1,2} EN 1\b|\b\d{1,2}\s?X\s?1\b'),
            ('Herramienta de purga', r'\bPURGA\b'),
            ('Cepillo / limpieza', r'\bLIMPIADOR\b|\bESCOBILLA\b|\bCEPILLO\b'),
            ('Alicate / prensa', r'\bALICATE\b|\bPINZAS?\b'),
            ('Extractor de obús', r'\bEXTRACTOR DE OB[UÚ]S\b|\bOB[UÚ]S\b'),
            ('Juego de llaves Allen', r'\bLLAVERO ALLEN\b|\bLLAVES? ALLEN\b'),
            ('Botella aplicadora', r'\bBOTELLA APLICADORA\b'),
            ('Regla / medidor', r'\bREGLA\b'),
            ('Cincel / otro manual', r'\bCINCEL\b'),
            ('Guía de cableado interno', r'\bGU[IÍ]A CABLEADO INTERNO\b'),
            ('Extractor de cono de dirección', r'\bEXTRACTOR CONO\b.*\bDIRECCION\b'),
            ('EPP (guantes de taller)', r'\bGUANTES? DE NITRILO\b')),
            r'^\s*TORNILLO\b|\bREPUESTO\b'),
        'pack_quantity': PACK_UNITS,
        'volume_ml': MM_VOLUME,
    },
    'workshop_chemical': {
        'chemical_kind': words(('Lubricante de cadena (seco)', r'\bSECO\b|\bDRY\b'),
                               ('Lubricante de cadena (húmedo)', r'\bH[UÚ]MEDO\b|\bWET\b'),
                               ('Lubricante de cadena (cera)', r'\bCERA\b|\bWAX\b'),
                               ('Desengrasante', r'\bDESENGRASANTE\b|\bDEGREASER\b'),
                               ('Limpiador', r'\bLIMPIADOR\b|\bCLEANER\b'),
                               ('Grasa', r'\bGRASA\b|\bGREASE\b'),
                               ('Abrillantador / protector', r'\bABRILLANTADOR\b'),
                               ('Silicona', r'\bSILICONA\b')),
        'container': words(('Aerosol', r'\bAEROSOL\b|\bSPRAY\b'), ('Gotero', r'\bGOTERO\b')),
        'volume_ml': MM_VOLUME,
        'weight_g': number(NB + r'(\d{2,4})\s?(?:GRS?\b|GRAMOS\b|G\b)'),
    },
    'tube_repair': {
        'repair_kind': first(words(('Kit parches + solución', r'\bSET (?:DE )?PARCHES\b(?=.*\+\s?SOLUC)')),
                             words(('Pegamento / solución', r'\bPEGAMENTO\b|\bSOLUCI[OÓ]N\b'),
                                   ('Parche autoadhesivo', r'\bGLUELESS\b|\bAUTOADHESIVO\b'))),
        'patch_count': unless(number(NB + r'(\d{1,3})\s?(?:UND\b\.?|UNIDADES\b|U\b|PARCHES\b|P\b)'), r'^\s*PEGAMENTO\b|^\s*SOLUCION\b'),
        'glue_volume_ml': number(NB + r'(\d{1,3})\s?(?:ML\b|CC\b)'),
    },
    'headset': {
        'headset_part_scope': words(('Completa', r'\bJUEGO (?:DE )?DIRECCI[OÓ]N\b')),
    },
    'kickstand': {
        'kickstand_mount_kind': words(('Abrazadera a vaina', r'\bABRAZADERA\b')),
        'adjustable_length': flag(r'\bAJUSTABLE\b|\bREGULABLE\b'),
    },
    'bottle': {
        'volume_ml': number(NB + r'(\d{3,4})\s?ML\b'),
    },
    'bottle_cage': {
        'material': words(MATERIAL_ALU, MATERIAL_ACERO),
    },
    'fork': {
        # An axle spacing reads as `9x100mm`: the travel is the millimetre figure
        # that no `x` precedes, so a fork with both keeps only its travel.
        'travel_mm': number(r'(?<![0-9.,xX])(80|100|120|130|140|150|160|170)\s?MM\b'),
        'hub_old_mm': number(r'(?<![0-9.,])(?:9|15|20)\s?[xX]\s?(100|110)\s?MM\b'),
        'lockout': either(flag(r'\bBLOQUEO\b|\bLOCKOUT\b'), flag(r'\bSIN BLOQUEO\b', False)),
        'fork_kind': words(('Rígida', r'\bR[IÍ]GIDA\b'), ('Suspensión (aire)', r'\bAIRE\b|\bAIR\b'),
                           ('Suspensión (muelle)', r'\bCOIL\b|\bMUELLE\b|\bRESORTE\b')),
        'steerer_threaded': either(flag(r'\bCON HILO\b|\bC/HILO\b'), flag(r'\bSIN HILO\b|\bA-?HEAD\b', False)),
        'steerer_fit': unless(words(('1 1/8" (28.6 mm)', r'\b1[- ]1/8\b'), ('1" (25.4 mm)', r'\b1"(?![\d/])'),
                                    ('Tapered 1 1/8" – 1.5"', r'\bTAPERED\b|\bC[OÓ]NIC[AO]\b')), r'1[.,]5"?\s*$|1-1/8\s*[-–/]\s*1[.,]5'),
        'brake_mount': words(('Postes cantilever / V-brake', r'\bV-?BRAKE\b')),
        'material': words(MATERIAL_ALU, MATERIAL_ACERO, MATERIAL_CARBONO),
    },
    'wheel_retention': {
        'material': words(MATERIAL_ALU, MATERIAL_ACERO),
    },
    'tire': {
        'tire_bead_type': words(('Alambre', r'\bALAMBRE\b|\bWIRE\b'), ('Plegable (kevlar)', r'\bPLEGABLE\b|\bKEVLAR\b|\bFOLDING\b')),
        'tire_use': words(('MTB', r'\bMTB\b'), ('Ruta', r'\bRUTA\b'), ('BMX', r'\bBMX\b'),
                          ('Urbano / híbrido', r'\bURBAN[OA]\b|\bCITY\b|\bH[IÍ]BRID[OA]\b|\bTREKKING\b|\bPASEO\b'),
                          ('Niño', NINO), ('Scooter', r'\bSCOOTER\b|\bPAT[IÍ]N EL[EÉ]CTRICO\b')),
        'tire_tubeless_ready': flag(r'\bTLR\b|\bTUBELESS\b|\bTL READY\b'),
        'tire_tpi': number(NB + r'(\d{2,3})\s?TPI\b'),
        'tire_width_mm': number(r'\b700\s?[xX]\s?(\d{2})\s?[cC]\b'),
    },
    'bike_bag': {
        'bag_position': words(('Triángulo del cuadro', r'\bTRIANGUL(?:O|AR)\b'), ('Bajo sillín', r'\bBAJO (?:SILL[IÍ]N|ASIENTO)\b'),
                              ('Manubrio', r'\bMANUBRIO\b|\bMANILLAR\b'), ('Alforja', r'\bALFORJAS?\b')),
        'waterproof_claim': flag(r'\bIMPERMEABLE\b|\bWATERPROOF\b'),
    },
    'rider_bag': {
        'bag_kind': first(words(('Cubre-mochila', r'\bPROTECTOR (?:IMPERMEABLE )?DE MOCHILA\b|\bCUBRE\s?MOCHILA\b'),
                                ('Mochila de hidratación', r'\bCAMELBAK\b|\bHIDRATACI[OÓ]N\b'),
                                ('Riñonera / bolso de cintura', r'\bRI[NÑ]ONERA\b')),
                          words(('Mochila', r'^\s*MOCHILA\b'))),
        'volume_l': unless(number(NB + r'(\d{1,2})\s?(?:L\b|LITROS?\b|LT\b)'), r'\d{2}-\d{2}\s?L\b'),
        'fits_volume_min_l': number(r'\b(\d{2})-\d{2}\s?L\b'),
        'fits_volume_max_l': number(r'\b\d{2}-(\d{2}\s?L)\b', group=1, quote_group=1, cast=lambda s: int(re.sub(r'\D', '', s))),
        'waterproof_claim': flag(r'\bIMPERMEABLE\b|\bWATERPROOF\b'),
    },
    'accessory_mount': {
        'accessory_mount_kind': words(('Soporte de teléfono', r'\bSOPORTE (?:PL[AÁ]STICO )?(?:CELULAR|TEL[EÉ]FONO)\b'),
                                      ('Gancho de pared / almacenamiento', r'\bGANCHO\b')),
        'material': words(MATERIAL_ALU, MATERIAL_PLASTICO),
        'rotation_360': flag(r'\b360\s?°?'),
        'device_width_min_mm': number(r'\b(\d{2})-\d{2,3}\s?MM\b'),
        'device_width_max_mm': number(r'\b\d{2}-(\d{2,3}\s?MM)\b', group=1, quote_group=1, cast=lambda s: int(re.sub(r'\D', '', s))),
    },
    'fender': {
        'fender_position': words(('Juego', r'\bSET\b|\(JUEGO\)|\bJUEGO\b|\bDELANTERO Y TRASERO\b'),
                                 ('Delantero', r'\bDELANTERO\b(?!\s+Y\s+TRASERO)'), ('Trasero', r'(?<!Y\s)\bTRASERO\b')),
    },
    'audible_signal': {
        'signal_kind': words(('Campanilla', r'\bCAMPANILLA\b'), ('Bocina electrónica', r'\bBOCINA ELECTR[OÓ]NICA\b')),
        'loudness_db_claim': number(NB + r'(\d{2,3})\s?DB\b'),
        'power_source': words(('Recargable USB', r'\bRECARGABLE\b')),
    },
    'derailleur_pulley': {
        'pulley_package_kind': words(('Par de roldanas en el mismo envase', r'\bPAR\b')),
        'pulley_teeth': unless(number(NB + r'(1[0-6])\s?T\b'), r'\bPAR\b'),
    },
    'spacer': {
        'material': words(MATERIAL_ALU, ('Carbono', r'\bCARBON\b'), ('Policarbonato / plástico', r'\bPOLY?CARBONATO\b')),
    },
    'tubeless_tape': {
        'tape_width_mm': number(NB + r'(\d{2})\s?MM\b', allowed=set(range(18, 46))),
        'roll_length_m': number(NB + r'(\d{1,2})\s?MTS?\b'),
    },
    'rim_strip': {
        'strip_material': words(('Goma', r'\bGOMA\b')),
    },
    'rider_glove': {
        'finger_length': words(('Corto (medio dedo)', r'\bCORTO\b|\bMEDIO DEDO\b'), ('Largo (dedo completo)', r'\bDEDO COMPLETO\b|\bLARGO\b')),
        'glove_intended_use': words(('Ciclismo', r'\bCICLISMO\b'), ('Moto', r'\bMOTO\b')),
        'padding': words(('Gel', r'\bGEL\b')),
    },
    'rider_apparel': {
        'garment_kind': words(('Jersey', r'\bJERSEY\b'), ('Polera', r'\bPOLERA\b'), ('Buff / cuello', r'\bBUFF\b'),
                              ('Máscara / pasamontañas', r'\bM[AÁ]SCARA\b'), ('Short', r'\bSHORT\b'), ('Chaqueta', r'\bCHAQUETA\b')),
    },
    'souvenir': {
        'souvenir_kind': words(('Sticker / pegatina', r'\bSTICKERS?\b|\bPEGATINAS?\b'), ('Modelo a escala', r'\bA ESCALA\b')),
    },
    'headset_small_part': {
        'headset_part_kind': words(('Araña (star nut)', r'\bARA[NÑ]A\b')),
    },
    'control_small_part': {
        'control_part_kind': words(('Terminal de piola (crimp)', r'\bTERMINAL (?:DE )?(?:PIOLA|CABLE|PUNTA PIOLA)\b'),
                                   ('Tope / terminal de funda', r'\bTERMINAL DE FUNDA\b'),
                                   ('Capuchón', r'\bCAPUCH[OÓ]N\b'),
                                   ('Guía de cable', r'\bGU[IÍ]A CABLE\b|\bHEBILLA\b'),
                                   ('Regulador de tensión (barril)', r'\bREGULADOR\b'),
                                   ('Noodle V-brake', r'\bNOODLE\b|\bGU[IÍ]A \(PASADOR\) FRENO V-BRAKE\b|\bGU[IÍ]A FRENO CURVA\b'),
                                   ('Fuelle / goma protectora', r'\bGOM(?:A|ITA)\b')),
        'pack_quantity': PACK_UNITS,
    },
    'pedal_peg': {
        'peg_axle_fit': words(('Eje 3/8" (10 mm)', FRACTION_BEFORE + r'3/8' + FRACTION_AFTER), ('Eje 14 mm', r'\b14\s?MM\b')),
        'peg_length_mm': number(r'[xX]\s?(1[0-2]\d)\s?MM\b'),
        'material': words(MATERIAL_ACERO, MATERIAL_ALU),
        'pack_quantity': PACK_UNITS,
    },
    'rack_basket': {
        'carrier_kind': words(('Correa / pulpo de carga', r'\bCUERDA BUNGEE\b|\bPULPO\b')),
        'material': words(MATERIAL_ACERO),
    },
    'handlebar_covering': {
        'covering_kind': words(('Cinta de manillar', r'\bCINTA\b'), ('Funda / espuma tubular', r'\bCUBRE MANUBRIO\b')),
        'material': words(('EVA', r'\bEVA\b')),
    },
    'seatpost_shim': {
        'shim_inner_diameter_mm': number(r'\b\d{2}(?:\.\d)?-((27\.2)\s?MM)\b', group=2, quote_group=1, cast=float),
    },
    'bottom_bracket_bearing': {
        'bearing_supply_form': words(('Canastillo con bolas', r'\bCANASTILLO\b|\bENJAULAD[AO]\b'), ('Cartucho', r'\bSELLADO\b|\b2RS\b')),
        'bb_ball_size_in': words(('1/4', FRACTION_BEFORE + r'1/4' + FRACTION_AFTER)),
    },
    'rear_shock': {
        'spring_kind': words(('Aire', r'\bAIR\b|\bAIRE\b|\bTRIAIR\b'), ('Muelle', r'\bCOIL\b|\bMUELLE\b')),
    },
    'tubeless_consumable': {
        'consumable_kind': words(('Sellante', r'\bSELLADOR\b|\bSELLANTE\b|\bL[IÍ]QUIDO ANTIPINCHAZOS\b|\bSEAL\b')),
        'sealant_volume_ml': number(NB + r'(\d{3,4})\s?(?:ML\b|CC\b)'),
    },
    'consumer_electronics': {
        'device_kind': words(('Cable de datos/carga', r'\bCABLE\b'), ('Cargador', r'\bCARGADOR\b'), ('Audífonos', r'\bAUD[IÍ]FONOS?\b'),
                             ('Tarjeta de memoria', r'\bMEMORIA SD\b|\bTARJETA\b')),
        'rated_power_w': only_if(number(NB + r'(\d{2,3})\s?W\b'), r'\bCARGADOR\b'),
        'storage_capacity_gb': number(NB + r'(\d{2,4})\s?GB\b'),
        'wireless': flag(r'\bINAL[AÁ]MBRIC[OA]\b'),
    },
    'cycle_computer': {
        'functions_count': number(NB + r'(\d{1,2})\s?FUNCIONES\b'),
        'speed_source': words(('Sensor de rueda (imán / cable)', r'\bCON CABLE\b')),
    },
}


# --- driver ------------------------------------------------------------------

def parse_terms(cell):
    return [t for t in (cell or '').split(';') if t]


def parse_value_terms(cell):
    """`label>>t1;t2||label2>>…` → {normalized label: [terms]}."""
    result = {}
    for item in (cell or '').split('||'):
        if '>>' not in item:
            continue
        label, _, terms = item.partition('>>')
        result[normalize(label)] = parse_terms(terms)
    return result


def load_catalog(path):
    catalog = {}
    for row in csv.DictReader(open(path, encoding='utf-8')):
        if row['role'] == 'legacy':
            continue
        catalog[(row['template_key'], row['field_key'])] = {
            'data_type': row['data_type'], 'unit': row['unit'], 'label': row['label'],
            'description': row['description'],
            'value_labels': [v for v in row['value_labels'].split('||') if v],
            'value_terms': parse_value_terms(row.get('value_terms', '')),
            'reading_terms': parse_terms(row.get('reading_terms', '')),
            'reading_terms_false': parse_terms(row.get('reading_terms_false', '')),
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
