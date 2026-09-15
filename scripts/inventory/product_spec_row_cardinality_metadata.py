"""Template-local occurrence counts, with no catalogue or product mutation."""
import math
import re

from product_spec_row_condition_metadata import _decimal_compare, decimal_literal


def _number(value):
    if isinstance(value, bool) or not isinstance(value, (str, int, float)):
        return None
    if isinstance(value, (int, float)) and (abs(value) > 9007199254740991 or not math.isfinite(value)):
        return None
    text = str(value).strip().replace(',', '.')
    return text if decimal_literal(text) else None


def row_coherence_links(contract):
    """V1 links, V2 flat counts, V3 also permits explicitly linked groups."""
    if 'row_coherence' not in contract:
        return []
    block = contract['row_coherence']
    if (not isinstance(block, dict) or isinstance(block.get('version'), bool)
            or block.get('version') != 1 and type(block.get('version')) is not int):
        raise ValueError('Invalid row coherence version')
    keys = {'version', 'links'}
    if block['version'] in (2, 3):
        keys.add('cardinalities')
        if not isinstance(block.get('cardinalities'), list):
            raise ValueError('Missing row cardinalities')
    elif block['version'] != 1:
        raise ValueError('Invalid row coherence version')
    if set(block) != keys or not isinstance(block.get('links'), list):
        raise ValueError('Invalid row coherence metadata')
    return block['links']


def validate_row_cardinalities(contract, definitions, keys, edges, ids):
    links = row_coherence_links(contract)
    collections = set()
    for item in contract.get('row_coherence', {}).get('cardinalities', []):
        grouped = isinstance(item, dict) and 'group_by' in item
        expected = {'id', 'field', 'group_by', 'total_column'} if grouped else {'id', 'field', 'total_field'}
        if (not isinstance(item, dict) or set(item) != expected
                or grouped and contract['row_coherence']['version'] != 3
                or any(not isinstance(v, str) or not re.fullmatch(r'[a-z][a-z0-9_]*', v)
                       for v in item.values())):
            raise ValueError('Invalid cardinality metadata')
        source = item['field']
        link = next((l for l in links if l['id'] == item.get('group_by')), None) if grouped else None
        if grouped and (link is None or link['field'] != source):
            raise ValueError('Grouped cardinality needs a link owned by its collection')
        total = link['target_field'] if grouped else item['total_field']
        if (source not in keys or total not in keys or item['id'] in ids or source in collections
                or any(contract['roles'].get(k) == 'legacy' for k in [source, total])
                or definitions[source]['data_type'] != 'json'
                or not isinstance(definitions[source].get('validation_rules', {}).get('rows_schema'), dict)
                or definitions[total]['data_type'] != ('json' if grouped else 'number')):
            raise ValueError('Unavailable or duplicate cardinality endpoints')
        if grouped:
            columns = definitions[total].get('validation_rules', {}).get('rows_schema', {}).get('columns', [])
            column = next((c for c in columns if c['key'] == item['total_column']), None)
            if column is None or column['type'] != 'integer':
                raise ValueError('Grouped cardinality needs an integer parent column')
            rules = {**column.get('validation', {}), 'integer': True}
        else:
            rules = definitions[total].get('validation_rules', {})
        minimum, maximum = _number(rules.get('min')), _number(rules.get('max'))
        if (rules.get('integer') is not True or minimum is None or _decimal_compare(minimum, '0') < 0
                or rules.get('max') is not None and maximum is None
                or maximum is not None and _decimal_compare(minimum, maximum) > 0):
            raise ValueError('Row total requires a nonnegative integer domain')
        collections.add(source)
        ids.add(item['id'])
        edges[source].add(total)
