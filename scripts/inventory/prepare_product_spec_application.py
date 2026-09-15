#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["jsonschema[format-nongpl]==4.26.0"]
# ///
"""Seal an independently reviewed research delta and its authenticated backup.

This prepares a spec-only application; it cannot grant permission, stage SQL or
write an ERP record. A future authenticated writer must consume the exact sealed
command from its server-controlled registry after global sanitation is closed.
"""
import argparse
from copy import deepcopy
import hashlib
from pathlib import Path
import re
import sys
import uuid

from product_spec_session import ProductSpecSession, SessionUnavailable
from simulate_product_spec_research import (
    ROOT, RESEARCH, canonical, inspect_proposal, load_json, merge_row_delta,
    proposal_hash, same, simulate, unique, write_new,
)

NAMESPACE = uuid.UUID('208ecdb4-880a-4e5d-a5b8-e8e2777e444e')
PREPARATION_GATES = {'global_sanitation_open', 'authenticated_spec_only_applicator_pending',
                     'research_provenance_writer_pending'}


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def prepare(proposal, simulation, evidence_root=RESEARCH):
    """Validate every effect, including values omitted by the proposal.

    Authenticated simulation is an input provenance requirement, not a bearer
    capability. Its actor, preimage and entire postimage are independently
    compared here; the writer must repeat the live checks under its locks.
    """
    if (simulation.get('mode') != 'authenticated_simulation'
            or not isinstance(simulation.get('project'), str)
            or not re.fullmatch(r'[a-z]{20}', simulation['project'])
            or simulation.get('can_apply') is not False
            or type(simulation.get('writes')) is not int or simulation['writes'] != 0):
        raise ValueError('A read-only authenticated simulation is required')
    before = simulation.get('before_snapshot')
    checked = inspect_proposal(proposal, before, evidence_root)
    if checked['issues'] or simulation.get('issues'):
        raise ValueError('Research has unresolved findings')
    if not checked['review_record_consistent']:
        raise ValueError('The other researcher must review this exact proposal')
    pending = checked['pending'] + simulation.get('pending', [])
    if any(item['code'] not in PREPARATION_GATES for item in pending):
        raise ValueError('Research evidence or canonical identity prerequisites remain open')
    if (simulation.get('proposal_sha256') != proposal_hash(proposal)
            or simulation.get('snapshot_sha256') != before['snapshot_sha256']
            or simulation.get('actor_id') != before['actor_id']
            or simulation.get('tenant_id') != before['tenant_id']
            or simulation.get('product_id') != proposal['product_id']):
        raise ValueError('Simulation identities or proposal hash disagree')

    request = checked['request']
    preview = simulation.get('server_preview')
    if (not isinstance(preview, dict) or preview.get('mode') != 'simulation'
            or preview.get('mechanical_approval') is not False
            or preview.get('apply_authorized') is not False
            or preview.get('valid_draft') is not True
            or not isinstance(preview.get('issues'), list)
            or any(i.get('blocking', True) for i in preview['issues'])
            or any(preview.get(k) != simulation[k] for k in (
                'actor_id', 'tenant_id', 'product_id', 'snapshot_sha256'))):
        raise ValueError('A matching valid server preview is required')
    # A brand label alone cannot update the canonical brand relationship.
    # Keep this explicit gate until the identity owner supplies its receipt.
    if 'brand' in request['p_identity_patch']:
        raise ValueError('Brand changes require the canonical brand identity command')

    product, editor = before['product'], before['editor']
    expected_identity = {**product, **request['p_identity_patch']}
    if not same(preview.get('identity'), expected_identity):
        raise ValueError('Preview changes unreviewed product identity')
    expected_values = deepcopy(editor['values'])
    for key, value in request['p_values_patch'].items():
        expected_values[key] = (merge_row_delta(expected_values.get(key), value)
                                if isinstance(value, dict) else deepcopy(value))
    reference_id = request['p_reference_id'] or product.get('spec_reference_id')
    references = unique(before['references'], 'id')
    derived_keys = []
    if reference_id:
        if reference_id not in references:
            raise ValueError('The selected reference is not in the reviewed snapshot')
        for key, value in references[reference_id]['facts'].items():
            if key not in expected_values:
                expected_values[key] = deepcopy(value)
                derived_keys.append(key)
    if (not same(preview.get('values'), expected_values)
            or preview.get('reference_id') != reference_id
            or sorted(preview.get('derived_keys', [])) != sorted(derived_keys)):
        raise ValueError('Preview changes facts outside the reviewed delta')

    fields = unique([f['spec_definitions'] for f in editor['template']['fields']], 'key')
    changes = []
    for change in proposal['facts']:
        key = change['key']
        final_value = (merge_row_delta(editor['values'].get(key), change['proposed'])
                       if isinstance(change['proposed'], dict) and change['origin'] != 'reference'
                       else change['proposed'])
        if not same(expected_values.get(key), final_value):
            raise ValueError('A reviewed fact disagrees with its complete postimage')
        if (change['current']['confirmed'] is True
                and not same(change['current']['value'], final_value)
                and not any(c['field'] == key and isinstance(c['resolution'], str)
                            and c['resolution'].strip() for c in proposal['conflicts'])):
            raise ValueError('Replacing a physically confirmed observation requires a resolved conflict')
        definition_id = fields[key].get('id')
        if not isinstance(definition_id, str) or str(uuid.UUID(definition_id)) != definition_id:
            raise ValueError('Every effect needs its exact canonical definition UUID')
        changes.append({'key': key, 'definition_id': definition_id,
                        'current': deepcopy(change['current']),
                        'final_value': deepcopy(final_value), 'origin': change['origin'],
                        'evidence': deepcopy(change['evidence'])})
    reviewed_keys = {item['key'] for item in changes}
    if set(derived_keys) - reviewed_keys:
        raise ValueError('Every automatic reference effect needs independent review')
    if not changes and not request['p_identity_patch'] and reference_id == product.get('spec_reference_id'):
        raise ValueError('The application contains no reviewed effects')
    command = {
        'schema_version': 1, 'product_id': proposal['product_id'],
        'tenant_id': before['tenant_id'], 'actor_id': before['actor_id'],
        'based_on': deepcopy(proposal['based_on']), 'proposal_sha256': proposal_hash(proposal),
        'identity_patch': deepcopy(request['p_identity_patch']),
        'values_patch': deepcopy(request['p_values_patch']), 'reference_id': reference_id,
        'expected_values': expected_values, 'expected_identity': expected_identity,
        'changes': changes,
    }
    command_sha = digest(command)
    project = simulation['project']
    operation_id = str(uuid.uuid5(NAMESPACE, project + ':' + before['tenant_id'] + ':' + command_sha))
    body = {'schema_version': 1, 'mode': 'prepared_spec_only_application',
            'project': project,
            'operation_id': operation_id, 'command_sha256': command_sha, 'command': command,
            'proposal': deepcopy(proposal), 'before_snapshot': deepcopy(before),
            'server_preview': deepcopy(preview),
            'backup_sha256': digest(before), 'apply_authorized': False,
            'pending': sorted(PREPARATION_GATES), 'writes': 0}
    return {**body, 'bundle_sha256': digest(body)}


def verify_bundle(bundle):
    """Reject a changed backup or command before any future server registration."""
    if (bundle.get('schema_version') != 1
            or not isinstance(bundle.get('project'), str)
            or not re.fullmatch(r'[a-z]{20}', bundle['project'])
            or bundle.get('mode') != 'prepared_spec_only_application'
            or bundle.get('apply_authorized') is not False
            or type(bundle.get('writes')) is not int or bundle['writes'] != 0
            or bundle.get('bundle_sha256') != digest({k: v for k, v in bundle.items() if k != 'bundle_sha256'})
            or bundle.get('command_sha256') != digest(bundle.get('command'))
            or bundle.get('backup_sha256') != digest(bundle.get('before_snapshot'))):
        raise ValueError('The application bundle or backup has changed')
    operation_id = str(uuid.uuid5(NAMESPACE, bundle['project'] + ':'
                                  + bundle['command']['tenant_id'] + ':' + bundle['command_sha256']))
    if bundle.get('operation_id') != operation_id:
        raise ValueError('The operation identity does not belong to this project and command')
    return deepcopy(bundle['command'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--proposal', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    proposal = load_json(args.proposal)
    simulation = simulate(proposal, ProductSpecSession(ROOT))
    bundle = prepare(proposal, simulation)
    write_new(args.output, bundle)
    print(canonical({'operation_id': bundle['operation_id'],
                     'command_sha256': bundle['command_sha256'],
                     'backup_sha256': bundle['backup_sha256'],
                     'apply_authorized': False, 'writes': 0,
                     'output': str(args.output)}).decode())


if __name__ == '__main__':
    try:
        main()
    except (ValueError, SessionUnavailable) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
