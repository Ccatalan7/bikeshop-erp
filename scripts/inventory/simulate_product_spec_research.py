#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["jsonschema[format-nongpl]==4.26.0"]
# ///
"""Validate a v2 research proposal and simulate it through authenticated reads.

No writer, SQL, refresh token, retry, or apply switch is available. An offline
snapshot checks preparation only; only a fresh authenticated server simulation
evaluates the current persisted template. Neither mode authorizes catalogue fill.
"""
import argparse
from copy import deepcopy
import hashlib
import json
import os
from pathlib import Path
import sys

from jsonschema import Draft202012Validator, FormatChecker

from product_spec_session import ProductSpecSession, SessionUnavailable

ROOT = Path(__file__).resolve().parents[2]
RESEARCH = ROOT / 'docs/development/product-specs-research-2026-09-05'
SCHEMA = RESEARCH / 'catalog-fill-proposal-v2.schema.json'


# Who may research and who may review. A reviewer must differ from the
# researcher. claude-peer is a separate Claude session with fresh context
# (2026-09-16); owner is the shop owner reviewing by hand.
REVIEWERS = ('codex', 'claude', 'claude-peer', 'owner')
# What each contract evidence requirement accepts, by archived evidence kind.
# A saved name (name_quote) or an existing measurement never stands in for a
# manufacturer's sheet or the package; a distributor listing is not the OEM.
EVIDENCE_REQUIREMENT_KINDS = {
    'oem_spec': {'oem_page', 'oem_catalogue'},
    'oem_or_package': {'oem_page', 'oem_catalogue', 'packaging_photo'},
    'package_or_label': {'oem_page', 'oem_catalogue', 'packaging_photo', 'erp_image'},
    'name_reading_hint_only': None,
}


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(',', ':'), allow_nan=False).encode()


def proposal_hash(proposal):
    return hashlib.sha256(canonical({k: v for k, v in proposal.items() if k != 'review'})).hexdigest()


def same(left, right):
    # Python equality would conflate false with 0 and true with 1.
    return canonical(left) == canonical(right)


def merge_row_delta(current, patch):
    """Preview upserts retain omitted rows, cells, source order and stable IDs."""
    # The rows carry the version their definition's rows_schema declares (the
    # engine rejects any other); a delta never migrates an observation written
    # under an older version, that is sanitation work.
    version = patch.get('schema_version')
    if type(version) is not int or version < 1:
        raise ValueError('Row version must be an integer')
    base = deepcopy(current if current is not None else {'schema_version': version, 'rows': []})
    if (not isinstance(base, dict) or base.get('schema_version') != version
            or not isinstance(base.get('rows'), list)):
        raise ValueError('Existing row observations require sanitation')
    originals = unique(base['rows'], 'id')
    changes = unique(patch['rows'], 'id')
    for row_id, change in changes.items():
        if row_id not in originals:
            base['rows'].append(deepcopy(change))
            continue
        row = originals[row_id]
        row['values'].update(change['values'])
        row['sources'] = list(dict.fromkeys([*row['sources'], *change['sources']]))
    return base


def load_json(path):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError('Duplicate JSON member')
            result[key] = value
        return result

    def constant(_value):
        raise ValueError('Non-finite JSON number')

    if path.stat().st_size > 16 * 1024 * 1024:
        raise ValueError('Research artifact exceeds the per-product limit')
    raw = path.read_bytes()
    return json.loads(raw, object_pairs_hook=pairs, parse_constant=constant)


def unique(rows, field):
    result = {row[field]: row for row in rows}
    if len(result) != len(rows):
        raise ValueError('Duplicate research identity: ' + field)
    return result


def check_schema(proposal):
    schema = load_json(SCHEMA)
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    errors = sorted(validator.iter_errors(proposal), key=lambda e: str(list(e.absolute_path)))
    if errors:
        # Paths and validator names are useful without echoing arbitrary inputs.
        raise ValueError('Invalid v2 proposal: ' + '; '.join(
            '/'.join(map(str, e.absolute_path)) + ' (' + e.validator + ')' for e in errors[:12]))
    if type(proposal['schema_version']) is not int:
        raise ValueError('Proposal version must be an integer')
    for fact in proposal['facts']:
        if isinstance(fact['proposed'], dict) and type(fact['proposed']['schema_version']) is not int:
            raise ValueError('Row version must be an integer')


def inspect_proposal(proposal, snapshot, evidence_root=RESEARCH):
    """Return findings and a read-only preview request; never mutate inputs."""
    check_schema(proposal)
    facts = unique(proposal['facts'], 'key')
    identities = unique(proposal['identity'], 'field')
    evidence = unique(proposal['evidence'], 'id')
    if (snapshot.get('read_schema_version') != 1 or not isinstance(snapshot.get('product'), dict)
            or not isinstance(snapshot.get('editor'), dict)
            or not isinstance(snapshot.get('observations'), list)
            or not isinstance(snapshot.get('references'), list)):
        raise ValueError('A complete research snapshot is required')
    product, editor = snapshot['product'], snapshot['editor']
    if (snapshot.get('tenant_id') != product.get('tenant_id')
            or product.get('id') != proposal['product_id']
            or editor.get('product_id') != product.get('id')
            or editor.get('revision') != product.get('spec_revision')
            or editor.get('draft_category_id') != product.get('category_id')
            or editor.get('read_schema_version') != 2):
        raise ValueError('Research snapshot identities disagree')
    issues, pending = [], []

    def issue(code, field=''):
        issues.append({'code': code, 'field': field})

    basis = proposal['based_on']
    expected = {
        'tenant_id': snapshot['tenant_id'], 'snapshot_sha256': snapshot['snapshot_sha256'],
        'fingerprints': snapshot['fingerprints'], 'spec_revision': product['spec_revision'],
        'updated_at': product['updated_at'], 'template_id': editor['template_id'],
        'contract_version': editor['contract_version'],
    }
    for key, value in expected.items():
        if not same(basis[key], value):
            issue('stale_preimage', key)
    if product.get('product_type') == 'service':
        issue('service_workflow')
    template = editor.get('template')
    if (not isinstance(template, dict) or template.get('id') != editor.get('template_id')
            or template.get('contract_version') != editor.get('contract_version')):
        issue('template_unavailable')
        fields = {}
    else:
        fields = unique([field['spec_definitions'] for field in template['fields']], 'key')
    observations = {}
    for observation in snapshot['observations']:
        fact = observation['fact']
        if (fact['tenant_id'] != snapshot['tenant_id'] or fact['subject_id'] != product['id']
                or fact['subject_type'] != 'product'):
            raise ValueError('Foreign observation in research snapshot')
        if fact.get('subject_scope') is not None:
            continue  # Kept intact; this proposal targets only unscoped facts.
        key = observation['definition']['key']
        if key in observations:
            raise ValueError('Ambiguous unscoped observation identity')
        observations[key] = observation
    for field, change in identities.items():
        if not same(change['current'], product.get(field)):
            issue('identity_preimage', field)
    for key, change in facts.items():
        definition = fields.get(key)
        if definition is None or template['form_contract'].get('roles', {}).get(key) == 'legacy':
            issue('field_unavailable', key)
            continue
        observation = observations.get(key)
        before = {
            'value': editor['values'].get(key),
            'fact_id': observation['fact']['id'] if observation else None,
            'fact_sha256': observation['fact_sha256'] if observation else None,
            'source': observation['fact']['source'] if observation else None,
            'confirmed': observation['fact']['confirmed'] if observation else None,
        }
        if not same(change['current'], before):
            issue('fact_preimage', key)
        if not same(change['unit'], definition.get('unit')):
            issue('unit_mismatch', key)
        value, kind = change['proposed'], definition['data_type']
        valid_type = (
            (kind in ('number', 'text', 'single_select') and isinstance(value, str)) or
            (kind == 'boolean' and type(value) is bool) or
            (kind == 'multi_select' and isinstance(value, list)) or
            (kind == 'json' and isinstance(value, dict) and
             'rows_schema' in definition['validation_rules'])
        )
        if not valid_type:
            issue('typed_value_required', key)
        elif kind == 'json' and value.get('schema_version') != definition['validation_rules']['rows_schema'].get('version'):
            issue('row_schema_version', key)
        # Research provenance is written by the published applier
        # (20260916140000); only a name reading still needs its own receipt.
        if change['origin'] == 'existing_name':
            pending.append({'code': 'canonical_name_receipt_required', 'field': key})
    for change in [*facts.values(), *identities.values(), *proposal['conflicts'],
                   *([proposal['reference']] if proposal['reference'] else [])]:
        for source in change['evidence']:
            if source not in evidence:
                issue('unknown_evidence', source)
    # The contract says what kind of evidence each field needs; a fact whose
    # archived evidence is all weaker than that is blocked here, not by the
    # reviewer's eye.
    requirements = (template or {}).get('form_contract', {}).get('evidence_requirements', {}) if fields else {}
    for key, change in facts.items():
        accepted = EVIDENCE_REQUIREMENT_KINDS.get(requirements.get(key))
        if accepted is None:
            continue
        kinds = {evidence[source]['kind'] for source in change['evidence'] if source in evidence}
        if not kinds & accepted:
            issue('evidence_kind_insufficient', key)
    evidence_root = evidence_root.resolve()
    for source in evidence.values():
        artifact = source['artifact_path']
        if artifact is None:
            pending.append({'code': 'evidence_artifact_unavailable', 'field': source['id']})
            continue
        relative = Path(artifact)
        resolved = (evidence_root / relative).resolve()
        if relative.is_absolute() or '..' in relative.parts or not resolved.is_relative_to(evidence_root):
            issue('evidence_path_outside_archive', source['id'])
        elif not resolved.is_file() or source['sha256'] is None:
            issue('evidence_artifact_missing', source['id'])
        elif hashlib.sha256(resolved.read_bytes()).hexdigest() != source['sha256']:
            issue('evidence_hash_mismatch', source['id'])
    references = unique(snapshot['references'], 'id')
    reference_id = proposal['reference']['id'] if proposal['reference'] else product.get('spec_reference_id')
    reference = references.get(reference_id)
    reference_changes = {k: f for k, f in facts.items() if f['origin'] == 'reference'}
    if reference_changes or proposal['reference']:
        if reference is None:
            issue('reference_unavailable')
        else:
            if set(reference_changes) != set(reference['facts']):
                issue('reference_effects_not_fully_reviewed')
            for key, change in reference_changes.items():
                if key not in reference['facts'] or not same(change['proposed'], reference['facts'][key]):
                    issue('reference_fact_mismatch', key)
    for conflict in proposal['conflicts']:
        if not conflict['resolution']:
            issue('unresolved_conflict', conflict['field'])
    review = proposal['review']
    review_consistent = (proposal['status'] == 'reviewed' and review['verdict'] == 'accepted'
                         and review['by'] in REVIEWERS and review['by'] != proposal['researcher']
                         and review['reviewed_proposal_sha256'] == proposal_hash(proposal)
                         and review['date'] is not None)
    if not review_consistent:
        pending.append({'code': 'independent_review_required', 'field': ''})
    # The applier is published; the readiness closure is the gate that remains.
    pending.append({'code': 'global_sanitation_open', 'field': ''})
    request = {
        'p_product_id': proposal['product_id'],
        'p_expected_snapshot_sha256': snapshot['snapshot_sha256'],
        'p_identity_patch': {key: item['proposed'] for key, item in identities.items()},
        'p_values_patch': {key: item['proposed'] for key, item in facts.items() if item['origin'] != 'reference'},
        'p_reference_id': proposal['reference']['id'] if proposal['reference'] else None,
    }
    return {'schema_version': 1, 'mode': 'preflight', 'product_id': proposal['product_id'],
            'proposal_sha256': proposal_hash(proposal), 'snapshot_sha256': snapshot['snapshot_sha256'],
            'issues': issues, 'pending': pending, 'review_record_consistent': review_consistent,
            'can_apply': False, 'writes': 0, 'request': request}


def simulate(proposal, client, evidence_root=RESEARCH):
    snapshot = client.read('get_product_spec_research_snapshot_v1', {'p_product_id': proposal['product_id']})
    if snapshot.get('actor_id') != client.actor_id:
        raise ValueError('The server snapshot belongs to a different actor')
    result = inspect_proposal(proposal, snapshot, evidence_root)
    result.update(mode='authenticated_simulation', project=client.project,
                  actor_id=client.actor_id, tenant_id=snapshot['tenant_id'],
                  before_snapshot=snapshot)
    if not result['issues']:
        preview = client.read('preview_product_spec_research_v1', result['request'])
        if (preview.get('snapshot_sha256') != snapshot['snapshot_sha256']
                or preview.get('actor_id') != client.actor_id or preview.get('tenant_id') != snapshot['tenant_id']
                or preview.get('product_id') != proposal['product_id'] or preview.get('mode') != 'simulation'
                or preview.get('apply_authorized') is not False or preview.get('mechanical_approval') is not False):
            raise ValueError('Server preview identity or authority boundary disagrees')
        result['server_preview'] = preview
        for change in proposal['facts']:
            expected = change['proposed']
            if isinstance(expected, dict) and change['origin'] != 'reference':
                expected = merge_row_delta(snapshot['editor']['values'].get(change['key']), expected)
            if not same(preview['values'].get(change['key']), expected):
                result['issues'].append({'code': 'proposed_effect_mismatch', 'field': change['key']})
        result['issues'].extend(i for i in preview['issues'] if i.get('blocking', True))
    result.pop('request')
    return result


def write_new(path, value):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as output:
        json.dump(value, output, ensure_ascii=False, indent=2, allow_nan=False)
        output.write('\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--proposal', type=Path, required=True)
    parser.add_argument('--snapshot', type=Path, help='Offline preflight only; no server validation')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    proposal = load_json(args.proposal)
    check_schema(proposal)  # Reject malformed input before accessing credentials.
    if args.snapshot:
        result = inspect_proposal(proposal, load_json(args.snapshot))
        result.pop('request')
        result['mode'] = 'offline_preflight'
    else:
        result = simulate(proposal, ProductSpecSession(ROOT))
    write_new(args.output, result)
    print(json.dumps({'mode': result['mode'], 'issues': len(result['issues']),
                      'pending': len(result['pending']), 'writes': 0, 'output': str(args.output)}))
    return 2 if result['issues'] else 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, TypeError, KeyError, OSError, SessionUnavailable) as error:
        if isinstance(error, (ValueError, SessionUnavailable)):
            print(str(error), file=sys.stderr)
        else:
            print('Research input/session/output could not be processed', file=sys.stderr)
        sys.exit(1)
