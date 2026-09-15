"""Adversarial preparation tests; no credentials, SQL or actual product claims."""
from copy import deepcopy
import importlib.util
from pathlib import Path
import sys
import unittest
import io
import urllib.error

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/inventory'))
import prepare_product_spec_application as app
import simulate_product_spec_research as sim
import prepare_product_spec_registration as registration
import apply_product_spec_research as apply_client
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('research_fixture', Path(__file__).with_name('test_product_spec_research_simulator.py'))
fixture_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture_module)


class ApplicationPreparationTest(unittest.TestCase):
    def setUp(self):
        fixture = fixture_module.ResearchSimulationTest()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        self.proposal, self.snapshot, self.archive = fixture.proposal, fixture.snapshot, fixture.archive
        for index, field in enumerate(self.snapshot['editor']['template']['fields']):
            field['spec_definitions']['id'] = f'f1112300-0000-4000-8000-{index + 51:012}'
        self.simulation = self.make_simulation()

    def make_simulation(self):
        check = sim.inspect_proposal(self.proposal, self.snapshot, self.archive)
        request = check.pop('request')
        values = {**deepcopy(self.snapshot['editor']['values']), **deepcopy(request['p_values_patch'])}
        preview = {'mode': 'simulation', 'product_id': self.proposal['product_id'],
                   'actor_id': self.snapshot['actor_id'], 'tenant_id': self.snapshot['tenant_id'],
                   'snapshot_sha256': self.snapshot['snapshot_sha256'], 'mechanical_approval': False,
                   'apply_authorized': False, 'valid_draft': True, 'issues': [], 'values': values,
                   'identity': {**self.snapshot['product'], **request['p_identity_patch']},
                   'reference_id': self.snapshot['product']['spec_reference_id'], 'derived_keys': []}
        return {**check, 'mode': 'authenticated_simulation', 'project': 'abcdefghijklmnopqrst',
                'actor_id': self.snapshot['actor_id'],
                'tenant_id': self.snapshot['tenant_id'], 'before_snapshot': deepcopy(self.snapshot),
                'server_preview': preview}

    def prepare(self):
        return app.prepare(self.proposal, self.simulation, self.archive)

    def test_seals_exact_command_backup_and_review_without_apply_authority(self):
        original = deepcopy((self.proposal, self.simulation))
        bundle = self.prepare()
        self.assertEqual(original, (self.proposal, self.simulation))
        self.assertEqual(app.verify_bundle(bundle), bundle['command'])
        self.assertFalse(bundle['apply_authorized'])
        self.assertEqual(bundle['writes'], 0)
        self.assertEqual(bundle['before_snapshot']['observations'], self.snapshot['observations'])
        self.assertEqual(bundle['command']['expected_values']['amount'], '9007199254740993.125')
        self.assertIs(bundle['command']['expected_values']['flag'], False)
        self.assertEqual(bundle['operation_id'], self.prepare()['operation_id'])

    def test_offline_preflight_is_not_an_authenticated_simulation(self):
        self.simulation['mode'] = 'offline_preflight'
        with self.assertRaises(ValueError): self.prepare()

    def test_whole_postimage_rejects_unmentioned_changed_or_removed_fact(self):
        for value in ({'amount': '9007199254740993.125', 'flag': True},
                      {'amount': '9007199254740993.125'},
                      {'amount': '9007199254740993.125', 'flag': False, 'extra': 'new'}):
            self.simulation['server_preview']['values'] = value
            with self.assertRaises(ValueError): self.prepare()

    def test_preview_cannot_change_commercial_identity_or_sku(self):
        self.simulation['server_preview']['identity']['sku'] = 'unreviewed'
        with self.assertRaises(ValueError): self.prepare()

    def test_actor_tenant_and_proposal_preimages_must_match(self):
        for key in ('actor_id', 'tenant_id', 'proposal_sha256', 'snapshot_sha256', 'product_id'):
            original = self.simulation[key]
            self.simulation[key] = 'changed'
            with self.assertRaises(ValueError): self.prepare()
            self.simulation[key] = original

    def test_valid_boolean_is_strict_and_unknown_issue_is_blocking(self):
        for key, value in [('valid_draft', 1), ('apply_authorized', True),
                           ('mechanical_approval', True), ('issues', [{'code': 'unknown'}])]:
            original = self.simulation['server_preview'][key]
            self.simulation['server_preview'][key] = value
            with self.assertRaises(ValueError): self.prepare()
            self.simulation['server_preview'][key] = original

    def test_missing_evidence_cannot_be_excused_as_global_readiness(self):
        (self.archive / 'evidence.txt').unlink()
        with self.assertRaises(ValueError): self.prepare()

    def test_self_review_and_changed_proposal_require_independent_review(self):
        self.proposal['review']['by'] = 'codex'
        with self.assertRaises(ValueError): self.prepare()

    def test_canonical_brand_resolution_is_explicit(self):
        self.proposal['identity'][0].update(field='brand', current='Synthetic', proposed='Other')
        self.proposal['review']['reviewed_proposal_sha256'] = sim.proposal_hash(self.proposal)
        self.simulation = self.make_simulation()
        with self.assertRaisesRegex(ValueError, 'canonical brand'): self.prepare()

    def test_reference_cannot_add_unreviewed_effect(self):
        self.simulation['server_preview'].update(reference_id='surprise', derived_keys=['extra'])
        with self.assertRaises(ValueError): self.prepare()

    def test_new_required_pending_field_is_not_a_false_mechanical_approval(self):
        self.simulation['server_preview']['issues'] = [{'code': 'required', 'field': 'missing', 'blocking': False}]
        bundle = self.prepare()
        self.assertFalse(bundle['server_preview']['mechanical_approval'])
        self.assertEqual(bundle['server_preview']['issues'][0]['field'], 'missing')

    def test_undefined_canonical_definition_id_is_rejected(self):
        self.simulation['before_snapshot']['editor']['template']['fields'][0]['spec_definitions'].pop('id')
        with self.assertRaises(ValueError): self.prepare()

    def test_sealed_backup_and_command_cannot_be_changed_in_place(self):
        original = self.prepare()
        for edit in (lambda b: b['command']['values_patch'].update(amount='9'),
                     lambda b: b['before_snapshot']['observations'].clear(),
                     lambda b: b.update(apply_authorized=True)):
            bundle = deepcopy(original)
            edit(bundle)
            with self.assertRaises(ValueError): app.verify_bundle(bundle)

    def test_confirmed_measurement_needs_resolved_conflict_even_after_review(self):
        fact = self.snapshot['observations'][0]
        change = self.proposal['facts'][0]
        change.update(key='flag', proposed=True, unit=None, current={
            'value': False, 'source': 'mechanic', 'confirmed': True,
            'fact_id': fact['fact']['id'], 'fact_sha256': fact['fact_sha256']})
        self.proposal['review']['reviewed_proposal_sha256'] = sim.proposal_hash(self.proposal)
        self.simulation = self.make_simulation()
        with self.assertRaisesRegex(ValueError, 'confirmed observation'): self.prepare()
        self.proposal['conflicts'] = [{'field': 'flag', 'description': 'Synthetic source disagreement',
                                      'evidence': ['oem'], 'resolution': 'Synthetic explicit resolution'}]
        self.proposal['review']['reviewed_proposal_sha256'] = sim.proposal_hash(self.proposal)
        self.simulation = self.make_simulation()
        self.assertTrue(self.prepare()['command']['expected_values']['flag'])

    def test_missing_or_invalid_project_cannot_prepare_an_application(self):
        for project in (None, '', 'https://example.test', 'short', 1):
            self.simulation['project'] = project
            with self.assertRaises(ValueError): self.prepare()

    def test_same_command_in_other_project_gets_a_different_operation(self):
        before = self.prepare()
        self.simulation['project'] = 'zzzzzzzzzzzzzzzzzzzz'
        after = self.prepare()
        self.assertEqual(before['command_sha256'], after['command_sha256'])
        self.assertNotEqual(before['operation_id'], after['operation_id'])

    def readiness(self):
        return {'schema_version': 1, 'project': self.simulation['project'],
                'tenant_id': self.snapshot['tenant_id'], 'id': 'f1112300-0000-4000-8000-000000000081',
                'audit_sha256': 'a' * 64, 'review_sha256': 'b' * 64,
                'closed_at': '2026-09-07T10:00:00+00:00', 'enabled': True}

    def test_registration_requires_fresh_evidence_and_preserves_exact_approval(self):
        bundle = self.prepare()
        sql = registration.registration_sql(bundle, self.readiness(), self.simulation, self.archive)
        self.assertIn(registration.sql_text(sim.canonical(bundle['command']).decode()), sql)
        self.assertNotIn('set enabled=true', sql)
        (self.archive / 'evidence.txt').write_text('Changed document')
        with self.assertRaises(ValueError):
            registration.registration_sql(bundle, self.readiness(), self.simulation, self.archive)

    def test_registration_cannot_change_readiness_actor_or_review(self):
        bundle = self.prepare()
        for field, value in (('enabled', False), ('tenant_id', self.snapshot['actor_id']),
                             ('project', 'zzzzzzzzzzzzzzzzzzzz'), ('closed_at', '2026-09-07T10:00:00')):
            gate = self.readiness()
            gate[field] = value
            with self.assertRaises(ValueError):
                registration.registration_sql(bundle, gate, self.simulation, self.archive)
        changed = deepcopy(self.simulation)
        changed['actor_id'] = 'foreign'
        with self.assertRaises(ValueError):
            registration.registration_sql(bundle, self.readiness(), changed, self.archive)
        bundle['proposal']['review']['notes'] = 'Changed approval'
        bundle['bundle_sha256'] = app.digest({k: v for k, v in bundle.items() if k != 'bundle_sha256'})
        # Re-hashing can preserve integrity; it is not permission to reuse the
        # old server registration, which is checked by apply_or_recover.
        client = Mock(actor_id=bundle['command']['actor_id'], project=bundle['project'])
        client.application.return_value = {'bundle_sha256': 'old registration'}
        with self.assertRaises(ValueError): apply_client.apply_or_recover(bundle, client, self.archive)
        self.assertEqual([c.args[0] for c in client.application.call_args_list], [apply_client.STATUS])

    def test_client_rejects_other_project_before_any_operation_request(self):
        bundle = self.prepare()
        client = Mock(actor_id=bundle['command']['actor_id'], project='zzzzzzzzzzzzzzzzzzzz')
        with self.assertRaises(ValueError): apply_client.apply_or_recover(bundle, client, self.archive)
        client.application.assert_not_called()

    def test_uncertain_apply_is_never_automatically_retried(self):
        bundle = self.prepare()
        command = bundle['command']
        status = {'application_id': bundle['operation_id'], 'actor_id': command['actor_id'],
                  'tenant_id': command['tenant_id'], 'command_sha256': bundle['command_sha256'],
                  'bundle_sha256': bundle['bundle_sha256'], 'applied': False,
                  'readiness_enabled': True, 'revoked': False}
        client = Mock(actor_id=command['actor_id'], project=bundle['project'])
        client.application.side_effect = [status, apply_client.SessionUnavailable('uncertain response')]
        with patch.object(apply_client, 'simulate', return_value=self.simulation):
            with self.assertRaises(apply_client.SessionUnavailable):
                apply_client.apply_or_recover(bundle, client, self.archive)
        self.assertEqual([c.args[0] for c in client.application.call_args_list],
                         [apply_client.STATUS, apply_client.APPLY])

    def test_recovery_only_does_not_apply_an_unapplied_command(self):
        bundle = self.prepare()
        command = bundle['command']
        client = Mock(actor_id=command['actor_id'], project=bundle['project'])
        client.application.return_value = {'application_id': bundle['operation_id'],
            'actor_id': command['actor_id'], 'tenant_id': command['tenant_id'],
            'command_sha256': bundle['command_sha256'], 'bundle_sha256': bundle['bundle_sha256'],
            'applied': False}
        with self.assertRaises(ValueError):
            apply_client.apply_or_recover(bundle, client, self.archive, recover_only=True)
        self.assertEqual([c.args[0] for c in client.application.call_args_list], [apply_client.STATUS])

    def test_apply_response_owns_replay_after_status_race(self):
        bundle = self.prepare()
        command = bundle['command']
        status = {'application_id': bundle['operation_id'], 'actor_id': command['actor_id'],
                  'tenant_id': command['tenant_id'], 'command_sha256': bundle['command_sha256'],
                  'bundle_sha256': bundle['bundle_sha256'], 'applied': False,
                  'readiness_enabled': True, 'revoked': False}
        # Receipt integrity is exercised against actual SQL in the roundtrip.
        # This probe isolates dispatch/replay attribution at the status race.
        for replayed in (True, False):
            client = Mock(actor_id=command['actor_id'], project=bundle['project'])
            client.application.side_effect = [status, {'replayed': replayed}, {'after_snapshot': {}}]
            client.read.return_value = {}
            with patch.object(apply_client, 'simulate', return_value=self.simulation), \
                 patch.object(apply_client, 'verify_receipt', return_value={'replayed': False}):
                outcome = apply_client.apply_or_recover(bundle, client, self.archive)
            self.assertIs(outcome['recovered_existing_receipt'], replayed)
            self.assertEqual([c.args[0] for c in client.application.call_args_list],
                             [apply_client.STATUS, apply_client.APPLY, apply_client.RECEIPT])

    def test_malformed_apply_result_does_not_guess_ownership_or_retry(self):
        bundle = self.prepare()
        command = bundle['command']
        status = {'application_id': bundle['operation_id'], 'actor_id': command['actor_id'],
                  'tenant_id': command['tenant_id'], 'command_sha256': bundle['command_sha256'],
                  'bundle_sha256': bundle['bundle_sha256'], 'applied': False,
                  'readiness_enabled': True, 'revoked': False}
        for response in ({}, {'replayed': 'false'}, None):
            client = Mock(actor_id=command['actor_id'], project=bundle['project'])
            client.application.side_effect = [status, response]
            with patch.object(apply_client, 'simulate', return_value=self.simulation):
                with self.assertRaises(apply_client.SessionUnavailable):
                    apply_client.apply_or_recover(bundle, client, self.archive)
            self.assertEqual([c.args[0] for c in client.application.call_args_list],
                             [apply_client.STATUS, apply_client.APPLY])


class ApplicationTransportTest(unittest.TestCase):
    def setUp(self):
        # Constructor/session verification has its own real routing contract.
        # These fake values exercise only the separate fixed RPC capability.
        self.client = object.__new__(apply_client.ApplicationSession)
        self.client._origin = 'https://abcdefghijklmnopqrst.supabase.co'
        self.client._api_key = 'synthetic-public-key'
        self.client._token = 'synthetic-private-token'
        self.client._opener = Mock()
        self.operation = 'f1112300-0000-4000-8000-000000000081'

    def test_transport_can_only_post_one_exact_registered_uuid(self):
        self.client._opener.open.return_value = io.BytesIO(b'{"applied":true}')
        self.assertTrue(self.client.application(apply_client.STATUS, self.operation)['applied'])
        request = self.client._opener.open.call_args.args[0]
        self.assertEqual(request.method, 'POST')
        self.assertEqual(request.full_url, self.client._origin + '/rest/v1/rpc/' + apply_client.STATUS)
        self.assertEqual(request.data, sim.canonical({'p_application_id': self.operation}))
        self.assertEqual(request.get_header('Authorization'), 'Bearer synthetic-private-token')
        self.assertEqual(self.client._opener.open.call_count, 1)

    def test_arbitrary_rpc_and_noncanonical_id_never_reach_transport(self):
        for command, operation in [('save_product_with_specs_v1', self.operation),
                                   (apply_client.APPLY, self.operation.upper()),
                                   (apply_client.APPLY, self.operation + '/?delete=true')]:
            with self.assertRaises(ValueError): self.client.application(command, operation)
        self.client._opener.open.assert_not_called()

    def test_timeout_has_no_retry_or_credential_output(self):
        self.client._opener.open.side_effect = urllib.error.URLError('synthetic-private-token')
        with self.assertRaises(apply_client.SessionUnavailable) as raised:
            self.client.application(apply_client.APPLY, self.operation)
        self.assertNotIn('synthetic-private-token', str(raised.exception))
        self.assertEqual(self.client._opener.open.call_count, 1)

    def test_http_rejection_is_distinct_and_does_not_echo_untrusted_body(self):
        for status in (400, 401, 403, 404, 409, 422):
            self.client._opener.open.reset_mock()
            self.client._opener.open.side_effect = urllib.error.HTTPError(
                'https://example.invalid', status, 'synthetic-private-token', {},
                io.BytesIO(b'{"code":"42501","message":"synthetic-private-token"}'))
            with self.assertRaises(apply_client.ApplicationRejected) as raised:
                self.client.application(apply_client.APPLY, self.operation)
            self.assertIn(f'HTTP {status}; code 42501', str(raised.exception))
            self.assertNotIn('synthetic-private-token', str(raised.exception))
            self.assertNotIn('recover', str(raised.exception))
            self.assertEqual(self.client._opener.open.call_count, 1)

    def test_known_application_reason_is_preserved(self):
        self.client._opener.open.side_effect = urllib.error.HTTPError(
            'https://example.invalid', 403, '', {}, io.BytesIO(sim.canonical(
                {'code': '42501', 'message': 'El saneamiento global todavía no habilita el llenado'})))
        with self.assertRaisesRegex(apply_client.ApplicationRejected, 'todavía no habilita'):
            self.client.application(apply_client.APPLY, self.operation)

    def test_unreadable_rejection_is_still_a_rejection(self):
        for body in (b'gateway html synthetic-private-token', b'{"message":[]}', b'[]'):
            self.client._opener.open.side_effect = urllib.error.HTTPError(
                'https://example.invalid', 403, '', {}, io.BytesIO(body))
            with self.assertRaisesRegex(apply_client.ApplicationRejected, 'HTTP 403'):
                self.client.application(apply_client.APPLY, self.operation)

    def test_timeout_rate_limit_and_server_failures_keep_same_id_recovery(self):
        for status in (408, 429, 500, 502, 503):
            self.client._opener.open.reset_mock()
            self.client._opener.open.side_effect = urllib.error.HTTPError(
                'https://example.invalid', status, 'synthetic-private-token', {}, io.BytesIO(b''))
            with self.assertRaisesRegex(apply_client.SessionUnavailable, 'same operation ID'):
                self.client.application(apply_client.APPLY, self.operation)
            self.assertEqual(self.client._opener.open.call_count, 1)

    def test_failed_read_does_not_claim_a_write_was_attempted(self):
        self.client._opener.open.side_effect = urllib.error.URLError('failed read')
        with self.assertRaisesRegex(apply_client.SessionUnavailable, 'read unavailable; retry this read'):
            self.client.application(apply_client.STATUS, self.operation)

    def test_mid_response_socket_failure_keeps_the_same_id(self):
        for error in (ConnectionResetError('synthetic-private-token'),
                      apply_client.http.client.IncompleteRead(b'synthetic-private-token')):
            self.client._opener.open.reset_mock()
            self.client._opener.open.side_effect = error
            with self.assertRaises(apply_client.SessionUnavailable) as raised:
                self.client.application(apply_client.APPLY, self.operation)
            self.assertIn('same operation ID', str(raised.exception))
            self.assertNotIn('synthetic-private-token', str(raised.exception))
            self.assertEqual(self.client._opener.open.call_count, 1)


if __name__ == '__main__': unittest.main()
