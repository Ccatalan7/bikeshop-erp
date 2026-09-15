#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["jsonschema[format-nongpl]==4.26.0"]
# ///
"""Apply or recover ONE previously registered spec-only research command.

The server controls global readiness and exact command registration. There is
no arbitrary RPC, SQL, refresh-token use, batch loop or automatic write retry.
No production application is registered during development of this candidate.
"""
import argparse
import hashlib
import http.client
import json
import re
from pathlib import Path
import sys
import urllib.error
import urllib.request
from uuid import UUID

from prepare_product_spec_application import prepare, verify_bundle
from product_spec_session import ProductSpecSession, SessionUnavailable
from simulate_product_spec_research import ROOT, RESEARCH, canonical, load_json, same, simulate, write_new

STATUS = 'get_product_spec_research_application_status_v1'
RECEIPT = 'get_product_spec_research_receipt_v1'
APPLY = 'apply_product_spec_research_v1'


class ApplicationRejected(ValueError):
    """The current HTTP request was rejected; this is not a timeout receipt."""


# Only these fixed application messages are safe to show verbatim. A gateway
# error body, proxy page or reflected request is not trusted to exclude tokens
# or product data merely because it arrived in a PostgREST-shaped response.
PUBLIC_REJECTIONS = {
    'Authenticated tenant required', 'Aplicación no disponible',
    'Recibo no disponible', 'Comando de ficha inválido',
    'El saneamiento global todavía no habilita el llenado',
    'La preimagen cambió; hay que investigar y revisar de nuevo',
    'El efecto actual no corresponde a la propuesta revisada',
    'La revisión no corresponde a este comando',
    'Una observación confirmada requiere un conflicto resuelto explícitamente',
}


class ApplicationSession(ProductSpecSession):
    """Separate capability: the existing ProductSpecSession stays read-only."""
    def application(self, command, operation_id):
        if command not in (STATUS, RECEIPT, APPLY) or str(UUID(operation_id)) != operation_id:
            raise ValueError('Only an exact registered application UUID is accepted')
        request = urllib.request.Request(self._origin + '/rest/v1/rpc/' + command,
            data=canonical({'p_application_id': operation_id}), method='POST',
            headers={'apikey': self._api_key, 'Authorization': 'Bearer ' + self._token,
                     'Content-Type': 'application/json'})
        try:
            with self._opener.open(request, timeout=45) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if 400 <= error.code < 500 and error.code not in (408, 429):
                code, message = '', ''
                try:
                    body = json.loads(error.read(8192))
                    if isinstance(body, dict):
                        candidate = body.get('code')
                        if isinstance(candidate, str) and re.fullmatch(r'(?:[A-Z0-9]{5}|PGRST[0-9]{3})', candidate):
                            code = '; code ' + candidate
                        if body.get('message') in PUBLIC_REJECTIONS:
                            message = ': ' + body['message']
                except (ValueError, TypeError, OSError):
                    pass
                finally:
                    error.close()
                # No statement about earlier attempts: a prior receipt may
                # still exist even if this attempt now lacks authorization.
                raise ApplicationRejected(f'Application request rejected (HTTP {error.code}{code}){message}') from None
            error.close()
            raise SessionUnavailable(self._unavailable(command)) from None
        except (urllib.error.URLError, OSError, http.client.HTTPException, ValueError):
            # A transport error does not prove a transaction failed. The only
            # recovery is the SAME operation's status/receipt, never a new key.
            raise SessionUnavailable(self._unavailable(command)) from None

    @staticmethod
    def _unavailable(command):
        return ('Application response unavailable; recover the same operation ID' if command == APPLY
                else 'Application read unavailable; retry this read with the same operation ID')


def verify_receipt(bundle, receipt):
    command = verify_bundle(bundle)
    for key, wanted in {'application_id': bundle['operation_id'], 'actor_id': command['actor_id'],
                        'tenant_id': command['tenant_id'], 'product_id': command['product_id'],
                        'command_sha256': bundle['command_sha256']}.items():
        if receipt.get(key) != wanted or receipt.get('result', {}).get(key) != wanted:
            raise ValueError('Receipt identity or command hash disagrees')
    if not same(receipt.get('before_snapshot'), bundle['before_snapshot']):
        raise ValueError('Receipt does not preserve the reviewed full preimage')
    before, after = receipt['before_snapshot'], receipt.get('after_snapshot', {})
    if (after.get('actor_id') != command['actor_id'] or after.get('tenant_id') != command['tenant_id']
            or after.get('product', {}).get('id') != command['product_id']
            or not same(after.get('editor', {}).get('values'), command['expected_values'])
            or after['product'].get('spec_reference_id') != command['reference_id']):
        raise ValueError('Receipt does not contain the reviewed complete postimage')
    expected_product = {**command['expected_identity'], 'spec_reference_id': command['reference_id']}
    mutable_audit = {'updated_at', 'spec_revision'}
    if (not same({k: v for k, v in after['product'].items() if k not in mutable_audit},
                 {k: v for k, v in expected_product.items() if k not in mutable_audit})
            or receipt['result'].get('revision') != after['product'].get('spec_revision')):
        raise ValueError('Receipt identity projection differs from the reviewed complete product')
    for side, snapshot in (('before', before), ('after', after)):
        text = receipt.get(side + '_product_text')
        if (not isinstance(text, str) or hashlib.sha256(text.encode()).hexdigest()
                != snapshot.get('fingerprints', {}).get('product_sha256')):
            raise ValueError('Full product backup hash disagrees with the server snapshot')
    # Preserve JSON numeric tokens and types without routing through binary
    # floats (or confusing a number with an identically written text value).
    def exact_product(text):
        return json.loads(text, parse_int=lambda n: ('integer', n),
                          parse_float=lambda n: ('decimal', n))
    old_product = exact_product(receipt['before_product_text'])
    new_product = exact_product(receipt['after_product_text'])
    exceptions = {'updated_at', 'spec_revision', *command['identity_patch']}
    if old_product.get('spec_reference_id') != command['reference_id']:
        exceptions.add('spec_reference_id')
    if ({k: v for k, v in old_product.items() if k not in exceptions}
            != {k: v for k, v in new_product.items() if k not in exceptions}):
        raise ValueError('Receipt changed unrelated product columns')
    for key, wanted in command['identity_patch'].items():
        if not same(after['product'].get(key), wanted):
            raise ValueError('Applied identity differs from the reviewed delta')
    changed = receipt.get('changed_fact_ids')
    if (not isinstance(changed, list) or len(set(changed)) != len(changed)
            or receipt['result'].get('changed_fact_ids') != changed):
        raise ValueError('Receipt effect identifiers disagree')
    old = {o['fact']['id']: o for o in before['observations']}
    new = {o['fact']['id']: o for o in after['observations']}
    if (len(old) != len(before['observations']) or len(new) != len(after['observations'])
            or set(old) - set(new) or set(changed) - set(new)):
        raise ValueError('Receipt lost or duplicated observation identities')
    approved = {c['definition_id']: c for c in command['changes']}
    for fact_id, observation in new.items():
        if fact_id not in changed:
            if not same(old.get(fact_id), observation):
                raise ValueError('Receipt altered an unmentioned observation')
            continue
        fact = observation['fact']
        effect = approved.get(fact['spec_definition_id'])
        if (effect is None or fact.get('subject_scope') is not None
                or fact.get('subject_type') != 'product' or fact.get('subject_id') != command['product_id']
                or fact.get('tenant_id') != command['tenant_id']
                or fact['source'] != ('catalog' if effect['origin'] == 'reference' else 'research')
                or fact['confirmed'] is not False or observation.get('readings') != []):
            raise ValueError('Applied observation has unreviewed provenance')
    if (receipt['result'].get('before_snapshot_sha256') != before['snapshot_sha256']
            or receipt['result'].get('after_snapshot_sha256') != after['snapshot_sha256']):
        raise ValueError('Receipt snapshot fingerprints disagree')
    return receipt['result']


def apply_or_recover(bundle, client, evidence_root=RESEARCH, *, recover_only=False):
    command = verify_bundle(bundle)
    if client.actor_id != command['actor_id'] or client.project != bundle['project']:
        raise ValueError('The session actor or project is not the reviewed application target')
    status = client.application(STATUS, bundle['operation_id'])
    expected = {'application_id': bundle['operation_id'], 'actor_id': client.actor_id,
                'tenant_id': command['tenant_id'], 'command_sha256': bundle['command_sha256'],
                'bundle_sha256': bundle['bundle_sha256']}
    if (not isinstance(status, dict) or any(status.get(k) != v for k, v in expected.items())
            or type(status.get('applied')) is not bool):
        raise ValueError('Server registration does not match this exact prepared bundle')
    recovered = status['applied']
    application_result = None
    if not recovered:
        if recover_only:
            raise ValueError('This operation has no applied receipt')
        if status.get('readiness_enabled') is not True or status.get('revoked') is not False:
            raise ValueError('Global readiness or application permission is closed')
        fresh = prepare(bundle['proposal'], simulate(bundle['proposal'], client, evidence_root), evidence_root)
        if fresh['command_sha256'] != bundle['command_sha256'] or fresh['backup_sha256'] != bundle['backup_sha256']:
            raise ValueError('Research changed; do not apply or silently refresh this approval')
        application_result = client.application(APPLY, bundle['operation_id'])  # Exactly one attempt.
        if not isinstance(application_result, dict) or type(application_result.get('replayed')) is not bool:
            raise SessionUnavailable('Application result cannot identify replay; recover the same operation ID')
        recovered = application_result['replayed']
    receipt = client.application(RECEIPT, bundle['operation_id'])
    verified_result = verify_receipt(bundle, receipt)
    if application_result is not None and not same(
            {k: v for k, v in application_result.items() if k != 'replayed'},
            {k: v for k, v in verified_result.items() if k != 'replayed'}):
        raise SessionUnavailable('Application result differs from its receipt; recover the same operation ID')
    current = client.read('get_product_spec_research_snapshot_v1', {'p_product_id': command['product_id']})
    # A later authorized edit is not an excuse to replay/undo this application.
    current_matches = same(current, receipt['after_snapshot'])
    return {'schema_version': 1, 'mode': 'application_receipt_verified',
            'application_id': bundle['operation_id'], 'receipt': receipt,
            'current_snapshot': current, 'current_matches_receipt': current_matches,
            'recovered_existing_receipt': recovered}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--recover-only', action='store_true')
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError('Receipt output already exists; it will not be overwritten')
    bundle = load_json(args.bundle)
    verify_bundle(bundle)  # Invalid input never reaches credentials or network.
    outcome = apply_or_recover(bundle, ApplicationSession(ROOT), recover_only=args.recover_only)
    write_new(args.output, outcome)
    print(canonical({'application_id': outcome['application_id'],
                     'current_matches_receipt': outcome['current_matches_receipt'],
                     'recovered_existing_receipt': outcome['recovered_existing_receipt'],
                     'output': str(args.output)}).decode())


if __name__ == '__main__':
    try:
        main()
    except (ValueError, SessionUnavailable) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
