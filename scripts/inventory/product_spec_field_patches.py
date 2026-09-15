"""Apply individually adjudicated field proposals to an unpublished catalogue.

This pure transformation cannot change product facts or open publication gates.
Input hashes, stable identities and each changed value are checked before a new
artifact is returned. A source URL or the proposal's own verified flag is never
an integration decision.
"""
from copy import deepcopy
from decimal import Decimal, InvalidOperation
import hashlib
import json
import re
import uuid


CONTRACT_BUCKETS = {
    'roles', 'semantic_roles', 'allowed_when', 'required_when',
    'allowed_options', 'prerequisites', 'evidence_requirements', 'labels', 'helpers',
}
FIELD_KEYS = {
    'key', 'section_key', 'sort_order', 'is_required', 'visibility_rules',
    'option_rules', 'constraint_rules',
}


def artifact_sha(value):
    return hashlib.sha256((json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode()).hexdigest()


def apply_reviewed_field_addendum(base, proposal, decisions, validate_contract):
    """Return a new local catalogue; fail before producing a partial artifact."""
    # Preserve the exact reviewed file hash even when a contributor uses a
    # different JSON indent. Dict input is for canonically generated fixtures.
    if isinstance(proposal, bytes):
        proposal_sha = hashlib.sha256(proposal).hexdigest()
        proposal = json.loads(proposal)
    else:
        proposal_sha = artifact_sha(proposal)
    if decisions.get('approval_scope') != 'field_representation':
        raise ValueError('An explicit field-representation adjudication is required')
    if decisions.get('base_sha256') != artifact_sha(base):
        raise ValueError('Adjudicated catalogue base has drifted')
    if decisions.get('proposal_sha256') != proposal_sha:
        raise ValueError('Adjudicated proposal has drifted')
    if not base.get('publication_gates') or any(base['publication_gates'].values()):
        raise ValueError('Field proposals only apply before publication and fill')
    decision_rows = decisions.get('patch_adjudications', [])
    verdicts = {v['patch_id']: v for v in decision_rows}
    patches = proposal['patches']
    patch_ids = {p['id'] for p in patches}
    if (len(verdicts) != len(decision_rows) or len(patch_ids) != len(patches)
            or set(verdicts) != patch_ids):
        raise ValueError('Every proposal needs exactly one explicit decision')
    if any(v.get('decision') not in ('aceptar', 'corregir', 'rechazar') for v in verdicts.values()):
        raise ValueError('Unknown field decision')
    result = deepcopy(base)
    definitions = result['definitions']
    templates = {t['key']: t for t in result['templates']}
    supplied = deepcopy(proposal['new_definitions'])
    for key, replacement in decisions.get('definition_overrides', {}).items():
        if key not in supplied or replacement.get('key') != key:
            raise ValueError('A definition correction must target a proposed new field')
        supplied[key] = deepcopy(replacement)
    applied, rejected = [], []

    for patch in patches:
        key, op = patch['key'], patch['op']
        verdict = verdicts[patch['id']]
        if not verdict.get('reason'):
            raise ValueError('A field decision must explain its scope')
        if verdict['decision'] == 'rechazar':
            rejected.append(patch['id'])
            continue
        after = deepcopy(verdict.get('after_override', patch['after']))
        if (verdict['decision'] == 'corregir' and 'after_override' not in verdict
                and key not in decisions.get('definition_overrides', {})):
            raise ValueError('A correction must supply its concrete replacement')
        if op == 'replace_template_label':
            template = templates.get(patch['template'])
            if (template is None or key != 'name'
                    or not isinstance(patch['before'], str)
                    or template.get('name') != patch['before']
                    or not isinstance(after, str) or not after.strip()):
                raise ValueError('Template label requires its exact non-empty name preimage')
            template['name'] = after
        elif op == 'replace_template_coherence':
            if patch['template'] not in templates or key not in ('row_coherence', 'scalar_ordered_pairs', 'row_conditions'):
                raise ValueError('Only executable template coherence blocks can be replaced')
            contract = templates[patch['template']]['form_contract']
            if patch['before'] != {'present': key in contract, 'value': contract.get(key)}:
                raise ValueError('Template coherence preimage drift')
            contract[key] = after
        elif op in ('replace_definition_label', 'append_allowed_values', 'replace_unpublished_options'):
            if patch['template'] is not None or key not in definitions:
                raise ValueError('Definition patch targets an unavailable identity')
            attr = 'label' if op == 'replace_definition_label' else 'allowed_values'
            if definitions[key][attr] != patch['before']:
                raise ValueError(f'Definition preimage drift: {key}/{attr}')
            if attr == 'label':
                if not isinstance(after, str) or not after.strip():
                    raise ValueError('Definition label is empty')
            elif (not isinstance(after, list) or any(not isinstance(v, str) for v in after)
                  or len(after) != len(set(after))
                  or (op == 'append_allowed_values' and after[:len(patch['before'])] != patch['before'])):
                raise ValueError('Append must preserve the existing option identities and order')
            if op == 'replace_unpublished_options' and definitions[key]['origin'] != 'new':
                raise ValueError('Only unpublished option identities can be replaced')
            definitions[key][attr] = after
        elif op == 'replace_unpublished_numeric_rules':
            definition = definitions.get(key, {})
            if (patch['template'] is not None or definition.get('origin') != 'new'
                    or definition.get('data_type') != 'number'):
                raise ValueError('Numeric correction requires an unpublished new number')
            if definition.get('validation_rules') != patch['before']:
                raise ValueError('Full numeric-rule preimage drift')
            if (not isinstance(after, dict) or set(after) - {'min', 'max', 'positive', 'integer'}
                    or any(type(after[k]) is not bool for k in ('positive', 'integer') if k in after)):
                raise ValueError('Unsupported numeric-rule correction')
            bounds = {}
            for bound in ('min', 'max'):
                if bound not in after:
                    continue
                try:
                    if (not isinstance(after[bound], str) or not re.fullmatch(
                            r'[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?', after[bound])):
                        raise ValueError('Numeric bounds require exact decimal text')
                    value = Decimal(after[bound])
                    if not value.is_finite():
                        raise ValueError('Non-finite numeric bound')
                    bounds[bound] = value
                except InvalidOperation:
                    raise ValueError('Invalid decimal bound') from None
            if ('min' in bounds and 'max' in bounds and bounds['min'] > bounds['max']
                    or after.get('positive') and 'max' in bounds and bounds['max'] <= 0):
                raise ValueError('Empty numeric domain')
            definition['validation_rules'] = after
        elif op == 'replace_unpublished_rows_schema':
            definition = definitions.get(key, {})
            if (patch['template'] is not None or definition.get('origin') != 'new'
                    or definition.get('data_type') != 'json'):
                raise ValueError('Row-schema correction requires an unpublished new definition')
            schema = definition.get('validation_rules', {}).get('rows_schema')
            if schema != patch['before']:
                raise ValueError(f'Full row-schema preimage drift: {key}')
            if (not isinstance(schema, dict) or schema.get('version') != 1
                    or not isinstance(after, dict) or after.get('version') != 1
                    or set(after) - {'version', 'columns', 'ordered_pairs', 'unique_by'}
                    or not isinstance(after.get('columns'), list) or not after['columns']):
                raise ValueError('Unsupported row-schema correction')
            columns = after['columns']
            if (any(not isinstance(c, dict) or not isinstance(c.get('key'), str) for c in columns)
                    or len({c['key'] for c in columns}) != len(columns)):
                raise ValueError('Row-schema correction duplicates or loses column identity')
            # Even unpublished corrections retain existing cell meaning.
            # Enum choices, labels and constraints may change after review;
            # a type/unit/key change needs a separate explicit transformation.
            if (len(columns) < len(schema['columns']) or any(
                    any(old.get(attr) != new.get(attr) for attr in ('key', 'type', 'unit'))
                    for old, new in zip(schema['columns'], columns))):
                raise ValueError('Row-schema correction cannot change column identity/type/unit')
            definition['validation_rules']['rows_schema'] = after
        elif op in ('append_row_columns', 'set_rows_ordered_pairs'):
            # These proposals extend unpublished, newly allocated schemas.
            # Changing a persisted row schema needs a database version/migration.
            definition = definitions.get(key, {})
            if (patch['template'] is not None or definition.get('origin') != 'new'
                    or definition.get('data_type') != 'json'):
                raise ValueError('Row extension must target an unpublished new definition')
            schema = definition.get('validation_rules', {}).get('rows_schema')
            if not isinstance(schema, dict) or schema.get('version') != 1:
                raise ValueError('Row extension needs the reviewed schema version')
            attr = 'columns' if op == 'append_row_columns' else 'ordered_pairs'
            before = schema.get(attr)
            if before != patch['before']:
                raise ValueError(f'Row schema preimage drift: {key}/{attr}')
            if (not isinstance(after, list)
                    or after[:len(before or [])] != (before or [])):
                raise ValueError('Row extension cannot replace existing columns or constraints')
            if attr == 'columns':
                if any(not isinstance(c, dict) or not isinstance(c.get('key'), str) for c in after):
                    raise ValueError('Invalid row column extension')
                if len({c['key'] for c in after}) != len(after):
                    raise ValueError('Row extension shadows an existing column')
            else:
                types = {c['key']: c['type'] for c in schema['columns']}
                if any(not isinstance(pair, list) or len(pair) != 2 or pair[0] == pair[1]
                       or any(types.get(c) not in ('decimal', 'integer') for c in pair)
                       for pair in after):
                    raise ValueError('Ordered pairs need distinct numeric columns')
            schema[attr] = after
        elif op in ('add_field', 'replace_field_contract'):
            name = patch['template']
            if name not in templates:
                raise ValueError('Field patch targets an unavailable template')
            template = templates[name]
            found = [f for f in template['fields'] if f['key'] == key]
            contract = template['form_contract']
            if op == 'add_field':
                if patch['before'] is not None or found:
                    raise ValueError(f'Field already exists: {name}/{key}')
                if key not in definitions:
                    if key not in supplied:
                        raise ValueError(f'Missing definition: {key}')
                    definition = deepcopy(supplied[key])
                    if (definition.get('origin') != 'new' or definition.get('id') is not None
                            or definition.get('key') != key):
                        raise ValueError('A new definition cannot replace a database identity')
                    definition['id'] = str(uuid.uuid5(uuid.NAMESPACE_URL, 'vinabike:spec-definition:' + key))
                    definitions[key] = definition
                entry = after.get('field_entry')
                if (not isinstance(entry, dict) or set(entry) != FIELD_KEYS
                        or entry['key'] != key or after.get('definition_used_by_append') != name):
                    raise ValueError('Invalid new field entry')
                if set(after) - CONTRACT_BUCKETS - {'field_entry', 'definition_used_by_append'}:
                    raise ValueError('Unexpected new-field mutation')
                template['fields'].append(deepcopy(entry))
            else:
                if len(found) != 1 or not isinstance(patch['before'], dict):
                    raise ValueError('Field replacement must resolve one existing field')
                extensions = verdict.get('before_extensions', {})
                if (set(extensions) != set(after) - set(patch['before'])
                        or set(after) != set(patch['before']) | set(extensions)
                        or set(after) - CONTRACT_BUCKETS):
                    raise ValueError('Field replacement exceeds its adjudicated preimage')
                for bucket, expected in extensions.items():
                    actual = {'present': key in contract[bucket],
                              'value': contract[bucket].get(key)}
                    if expected != actual:
                        raise ValueError(f'Extended field preimage drift: {name}/{key}/{bucket}')
                for bucket, before in patch['before'].items():
                    if contract[bucket].get(key) != before:
                        raise ValueError(f'Field preimage drift: {name}/{key}/{bucket}')
            for bucket, value in after.items():
                if bucket in CONTRACT_BUCKETS:
                    contract[bucket][key] = deepcopy(value)
        else:
            raise ValueError('Unexpected field proposal operation')
        applied.append(patch['id'])

    for definition in definitions.values():
        definition['used_by'] = []
    for template in result['templates']:
        keys = {f['key'] for f in template['fields']}
        if len(keys) != len(template['fields']):
            raise ValueError('Duplicate field after integration')
        for field in template['fields']:
            definitions[field['key']]['used_by'].append(template['key'])
            field['section_key'] = template['form_contract']['roles'][field['key']]
        validate_contract(template['key'], template['form_contract'], definitions, keys)
    for key, before in base['definitions'].items():
        if any(definitions[key][attr] != before[attr] for attr in ('id', 'key', 'data_type', 'unit')):
            raise ValueError('Field integration cannot change a stable definition identity/type/unit')
    if result['publication_gates'] != base['publication_gates']:
        raise ValueError('A field proposal cannot open a publication or fill gate')
    result['field_addenda'] = [*result.get('field_addenda', []), {
        'base_sha256': artifact_sha(base), 'proposal_sha256': proposal_sha,
        'decisions_sha256': artifact_sha(decisions), 'applied': applied, 'rejected': rejected,
        'scope': 'field_representation',
    }]
    result['stats'].update(
        definitions=len(definitions), new_definitions=sum(d['origin'] == 'new' for d in definitions.values()),
        structured_fields=sum(d['data_type'] == 'json' for d in definitions.values()),
        fields=sum(len(t['fields']) for t in result['templates']), product_facts_changed=0,
    )
    return result
