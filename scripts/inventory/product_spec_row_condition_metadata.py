"""Reject malformed row-condition metadata before local catalogue trials.

This validates the representation only. SQL/Dart parity and independent domain
review remain mandatory before publication; no rule here certifies a fitment.
"""
import re

NUMBER = re.compile(r'^[+-]?([0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE]([+-]?[0-9]+))?$')
TYPES = {'boolean': {'boolean'}, 'decimal': {'decimal', 'integer'}, 'token': {'token', 'text'}}
OPERATORS = {'eq', 'in', 'lt', 'lte', 'gt', 'gte'}


def decimal_literal(value):
    if not isinstance(value, str):
        return False
    match = NUMBER.fullmatch(value)
    if not match:
        return False
    try:
        raw_exponent = int(match[2] or '0')
    except ValueError:
        return False
    # PostgreSQL's numeric input rejects larger raw exponents even for zero.
    # Match SpecRuleDecimal and the server before any scale arithmetic.
    if raw_exponent < -16383 or raw_exponent > 1073741823:
        return False
    mantissa = match[1]
    scale = len(mantissa) - mantissa.index('.') - 1 if '.' in mantissa else 0
    exponent = raw_exponent - scale
    if exponent < -16383:
        return False
    digits = mantissa.replace('.', '').lstrip('0')
    return not digits or len(digits) + exponent <= 131072


def condition_inputs(expression, columns):
    if not isinstance(expression, dict) or expression.get('kind') not in ('always', 'never', 'when'):
        raise ValueError('Invalid row condition expression')
    if expression['kind'] != 'when':
        if set(expression) != {'kind'}:
            raise ValueError('A constant condition cannot contain alternatives')
        return set()
    if set(expression) != {'kind', 'rows'} or not isinstance(expression['rows'], list) or not expression['rows']:
        raise ValueError('Missing condition alternatives')
    dependencies = set()
    for row in expression['rows']:
        if not isinstance(row, list) or not row:
            raise ValueError('Empty condition alternative')
        for predicate in row:
            if not isinstance(predicate, dict) or set(predicate) != {'field', 'operator', 'value_type', 'value'}:
                raise ValueError('Invalid row predicate')
            key, kind, operator = predicate['field'], predicate['value_type'], predicate['operator']
            if (not isinstance(key, str) or key not in columns or not isinstance(kind, str)
                    or kind not in TYPES or columns[key]['type'] not in TYPES[kind]
                    or not isinstance(operator, str) or operator not in OPERATORS
                    or operator in {'lt', 'lte', 'gt', 'gte'} and kind != 'decimal'):
                raise ValueError('Foreign or mistyped row prerequisite')
            choices = predicate['value'] if operator == 'in' else [predicate['value']]
            if not isinstance(choices, list) or not choices:
                raise ValueError('A row predicate needs a value')
            for value in choices:
                if (kind == 'boolean' and type(value) is not bool
                        or kind != 'boolean' and (not isinstance(value, str) or not value)
                        or kind == 'decimal' and not decimal_literal(value)):
                    raise ValueError('Invalid typed row prerequisite literal')
                allowed = columns[key].get('allowed_values', [])
                if allowed and value not in allowed:
                    raise ValueError('Prerequisite uses an unavailable token')
            dependencies.add(key)
    return dependencies


def _decimal_parts(value):
    """Exact comparison without a Decimal context or allocating exponent zeros."""
    if not decimal_literal(value):
        raise ValueError('Invalid exact expected decimal')
    match = NUMBER.fullmatch(value)
    mantissa = match[1]
    scale = len(mantissa) - mantissa.index('.') - 1 if '.' in mantissa else 0
    digits = mantissa.replace('.', '').lstrip('0')
    if not digits:
        return 0, '', 0
    trimmed = digits.rstrip('0')
    exponent = int(match[2] or '0') - scale + len(digits) - len(trimmed)
    return -1 if value.startswith('-') else 1, trimmed, exponent


def _decimal_compare(left, right):
    a, b = _decimal_parts(left), _decimal_parts(right)
    if a[0] != b[0]:
        return (a[0] > b[0]) - (a[0] < b[0])
    if not a[0]:
        return 0
    order_a, order_b = len(a[1]) + a[2], len(b[1]) + b[2]
    if order_a != order_b:
        return a[0] * ((order_a > order_b) - (order_a < order_b))
    width = max(len(a[1]), len(b[1]))
    digits_a, digits_b = a[1].ljust(width, '0'), b[1].ljust(width, '0')
    return a[0] * ((digits_a > digits_b) - (digits_a < digits_b))


def value_rule_inputs(rule, target, columns, scoped_options):
    if scoped_options is not None and not isinstance(scoped_options, list):
        raise ValueError('Row options must be a list')
    if (not isinstance(rule, dict) or set(rule) != {'when', 'expected'}
            or not isinstance(rule['expected'], dict)
            or set(rule['expected']) != {'value_type', 'value'}):
        raise ValueError('Invalid conditional row value rule')
    expected = rule['expected']
    kind, value = expected['value_type'], expected['value']
    target_type = target['type']
    if kind == 'boolean':
        if target_type != 'boolean' or type(value) is not bool:
            raise ValueError('Conditional value must be a JSON boolean')
    elif kind == 'token':
        if (target_type != 'token' or not isinstance(value, str) or not value.strip()
                or value.strip().lower() in {'unknown', 'desconocido / sin confirmar'}
                or target.get('allowed_values') and value not in target['allowed_values']
                or scoped_options is not None and value not in scoped_options):
            raise ValueError('Conditional token exceeds the column domain')
    elif kind == 'decimal':
        if target_type not in {'decimal', 'integer'}:
            raise ValueError('Conditional decimal needs a numeric column')
        parts = _decimal_parts(value)
        validation = target.get('validation', {})
        if (target_type == 'integer' and parts[2] < 0
                or validation.get('positive') is True and parts[0] <= 0
                or 'min' in validation and _decimal_compare(value, validation['min']) < 0
                or 'max' in validation and _decimal_compare(value, validation['max']) > 0):
            raise ValueError('Conditional decimal exceeds the column domain')
    else:
        raise ValueError('Conditional value type must be explicit')
    return condition_inputs(rule['when'], columns)


def validate_row_conditions(contract, definitions, keys):
    if 'row_conditions' not in contract:
        return
    block = contract['row_conditions']
    if (type(contract.get('rules_version')) is not int or contract['rules_version'] != 2
            or not isinstance(block, dict) or set(block) != {'version', 'fields'}
            or type(block['version']) is not int or block['version'] != 1
            or not isinstance(block['fields'], dict)):
        raise ValueError('Invalid row conditions version or shape')
    for key, rules in block['fields'].items():
        definition = definitions.get(key, {})
        schema = definition.get('validation_rules', {}).get('rows_schema')
        if (key not in keys or contract.get('roles', {}).get(key) == 'legacy'
                or definition.get('data_type') != 'json' or not isinstance(schema, dict)
                or not isinstance(rules, dict) or not rules
                or set(rules) - {'allowed_when', 'required_when', 'allowed_options', 'value_when'}):
            raise ValueError('Row conditions need an active structured field')
        columns = {column['key']: column for column in schema['columns']}
        edges = {column: set() for column in columns}
        for bucket, entries in rules.items():
            if not isinstance(entries, dict):
                raise ValueError('Row condition bucket must be a map')
            for column, expression in entries.items():
                if column not in columns:
                    raise ValueError('Row condition target does not exist')
                target = columns[column]
                if bucket == 'allowed_options':
                    if (target['type'] != 'token' or not isinstance(expression, list)
                            or any(not isinstance(token, str) or not token for token in expression)
                            or len(expression) != len(set(expression))
                            or target.get('allowed_values') and not set(expression) <= set(target['allowed_values'])):
                        raise ValueError('Row options exceed the schema domain')
                    continue
                if bucket == 'value_when':
                    if not isinstance(expression, list) or not expression:
                        raise ValueError('Conditional row values need a nonempty rule list')
                    scoped = rules.get('allowed_options', {})
                    if not isinstance(scoped, dict):
                        raise ValueError('Row condition bucket must be a map')
                    for rule in expression:
                        edges[column].update(value_rule_inputs(rule, target, columns, scoped.get(column)))
                    continue
                edges[column].update(condition_inputs(expression, columns))
                if bucket == 'allowed_when' and target.get('required') is True and expression['kind'] != 'always':
                    raise ValueError('Static required columns cannot be conditional')
        visited, visiting = set(), set()

        def visit(column):
            if column in visiting:
                raise ValueError('Row prerequisites form a cycle')
            if column in visited:
                return
            visiting.add(column)
            for dependency in edges[column]:
                visit(dependency)
            visiting.remove(column)
            visited.add(column)

        for column in columns:
            visit(column)
