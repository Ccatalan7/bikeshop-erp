"""Research preimages, independent review and preservation before any writer exists."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts/inventory'))
import simulate_product_spec_research as sim


class ResearchSimulationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.archive = Path(self.temp.name)
        content = b'Synthetic fixture evidence; no actual product claim.'
        (self.archive / 'evidence.txt').write_bytes(content)
        self.product = 'f1112300-0000-4000-8000-000000000020'
        self.tenant = 'f1112300-0000-4000-8000-000000000001'
        self.actor = 'f1112300-0000-4000-8000-000000000091'
        self.template = 'f1112300-0000-4000-8000-000000000050'
        product = {'id': self.product, 'tenant_id': self.tenant, 'brand': 'Synthetic', 'model': None,
                   'category_id': None, 'spec_reference_id': None, 'spec_revision': 7,
                   'updated_at': '2026-09-07T10:00:00+00:00', 'product_type': 'product'}
        definitions = [{'key': 'amount', 'data_type': 'number', 'unit': 'mm', 'validation_rules': {}},
                       {'key': 'flag', 'data_type': 'boolean', 'unit': None, 'validation_rules': {}},
                       {'key': 'rows', 'data_type': 'json', 'unit': None,
                        'validation_rules': {'rows_schema': {'version': 1, 'columns': []}}}]
        self.snapshot = {
            'read_schema_version': 1, 'actor_id': self.actor, 'tenant_id': self.tenant,
            'product': product, 'snapshot_sha256': 'a' * 64,
            'fingerprints': {k: 'b' * 64 for k in ('product_sha256', 'facts_sha256', 'template_sha256', 'references_sha256')},
            'editor': {'read_schema_version': 2, 'product_id': self.product, 'draft_category_id': None,
                       'revision': 7, 'template_id': self.template, 'contract_version': 9,
                       'values': {'flag': False}, 'template': {'id': self.template, 'contract_version': 9,
                           'form_contract': {}, 'fields': [{'spec_definitions': d} for d in definitions]}},
            'references': [], 'observations': [{
                'fact': {'id': 'f1112300-0000-4000-8000-000000000071', 'tenant_id': self.tenant,
                         'subject_id': self.product, 'subject_type': 'product', 'subject_scope': None,
                         'source': 'mechanic', 'confirmed': True, 'value_boolean': False},
                'definition': {'key': 'flag'}, 'fact_sha256': 'c' * 64,
                'options': [], 'readings': [{'quote': 'Synthetic historical evidence'}]}],
        }
        self.proposal = {
            'schema_version': 2, 'product_id': self.product, 'researcher': 'codex', 'status': 'reviewed',
            'based_on': {'snapshot_sha256': self.snapshot['snapshot_sha256'], 'tenant_id': self.tenant,
                         'fingerprints': deepcopy(self.snapshot['fingerprints']), 'spec_revision': 7,
                         'updated_at': product['updated_at'], 'template_id': self.template, 'contract_version': 9},
            'identity': [{'field': 'model', 'current': None, 'proposed': 'Exact', 'evidence': ['oem'], 'reason': 'Synthetic identity'}],
            'reference': None,
            'facts': [{'key': 'amount', 'current': {'value': None, 'source': None, 'confirmed': None,
                                                  'fact_id': None, 'fact_sha256': None},
                       'proposed': '9007199254740993.125', 'unit': 'mm', 'method': 'Synthetic documentary reading',
                       'origin': 'research', 'evidence': ['oem'], 'scope': 'Synthetic model only', 'reason': 'Synthetic proposal'}],
            'evidence': [{'id': 'oem', 'kind': 'oem_page', 'source': 'https://example.test/synthetic',
                          'locator': 'Fixture', 'consulted_on': '2026-09-07', 'scope': 'Synthetic',
                          'finding': 'No actual product claim', 'sha256': hashlib.sha256(content).hexdigest(),
                          'artifact_path': 'evidence.txt'}],
            'conflicts': [], 'review': {'by': 'claude', 'verdict': 'accepted', 'date': '2026-09-07',
                                       'reviewed_proposal_sha256': None, 'notes': 'Synthetic review record'},
        }
        self.sign_record()

    def sign_record(self):
        self.proposal['review']['reviewed_proposal_sha256'] = sim.proposal_hash(self.proposal)

    def inspect(self):
        return sim.inspect_proposal(self.proposal, self.snapshot, self.archive)

    def codes(self, kind='issues'):
        return {i['code'] for i in self.inspect()[kind]}

    def test_preserves_all_inputs_and_unmentioned_observations(self):
        before = deepcopy((self.proposal, self.snapshot))
        result = self.inspect()
        self.assertEqual(result['issues'], [])
        self.assertEqual((self.proposal, self.snapshot), before)
        self.assertEqual(result['request']['p_values_patch'], {'amount': '9007199254740993.125'})
        self.assertTrue(result['review_record_consistent'])
        self.assertFalse(result['can_apply'])
        self.assertEqual(result['writes'], 0)

    def test_v1_review_is_never_auto_upgraded(self):
        self.proposal['schema_version'] = 1
        with self.assertRaises(ValueError):
            self.inspect()

    def test_decimal_json_number_rejected_before_network(self):
        for number in (1, 1.25, 9007199254740993):
            self.proposal['facts'][0]['proposed'] = number
            with self.assertRaises(ValueError):
                self.inspect()

    def test_row_decimal_must_also_be_text(self):
        self.proposal['facts'][0].update(key='rows', unit=None,
            proposed={'schema_version': 1, 'rows': [{'id': 'row-a', 'values': {'length': '0.000000000000000001'}, 'sources': []}]})
        self.assertFalse(self.inspect()['issues'])
        self.proposal['facts'][0]['proposed']['rows'][0]['values']['length'] = 0.1
        with self.assertRaises(ValueError):
            self.inspect()

    def test_evidence_kind_must_satisfy_the_contract(self):
        contract = self.snapshot['editor']['template']['form_contract']
        contract['evidence_requirements'] = {'amount': 'oem_spec'}
        self.assertFalse(self.inspect()['issues'])
        self.proposal['evidence'][0]['kind'] = 'distributor'
        self.sign_record()
        self.assertIn({'code': 'evidence_kind_insufficient', 'field': 'amount'}, self.inspect()['issues'])
        contract['evidence_requirements'] = {'amount': 'oem_or_package'}
        self.proposal['evidence'][0]['kind'] = 'packaging_photo'
        self.sign_record()
        self.assertFalse(self.inspect()['issues'])
        self.proposal['evidence'][0]['kind'] = 'name_quote'
        self.sign_record()
        self.assertIn({'code': 'evidence_kind_insufficient', 'field': 'amount'}, self.inspect()['issues'])
        contract['evidence_requirements'] = {'amount': 'name_reading_hint_only'}
        self.assertFalse(self.inspect()['issues'])

    def test_row_schema_version_follows_the_definition(self):
        # front_derailleur_clamp_options moved to rows_schema version 2 (strict
        # ordered pairs); the engine refuses a version-1 payload for it, so the
        # proposal must carry the definition's version, and only that one.
        definition = self.snapshot['editor']['template']['fields'][2]['spec_definitions']
        definition['validation_rules']['rows_schema']['version'] = 2
        self.proposal['facts'][0].update(key='rows', unit=None,
            proposed={'schema_version': 2, 'rows': [{'id': 'row-a', 'values': {'length': '1'}, 'sources': []}]})
        self.assertFalse(self.inspect()['issues'])
        self.proposal['facts'][0]['proposed']['schema_version'] = 1
        self.assertIn({'code': 'row_schema_version', 'field': 'rows'}, self.inspect()['issues'])
        self.proposal['facts'][0]['proposed']['schema_version'] = 0
        with self.assertRaises(ValueError):
            self.inspect()

    def test_row_delta_never_migrates_an_observation_of_another_version(self):
        before = {'schema_version': 1, 'rows': [{'id': 'one', 'values': {'length': '1'}, 'sources': []}]}
        delta = {'schema_version': 2, 'rows': [{'id': 'two', 'values': {'length': '2'}, 'sources': []}]}
        with self.assertRaises(ValueError):
            sim.merge_row_delta(before, delta)
        self.assertEqual(sim.merge_row_delta(None, delta)['schema_version'], 2)

    def test_row_delta_preserves_omitted_rows_cells_and_sources(self):
        before = {'schema_version': 1, 'rows': [
            {'id': 'one', 'values': {'length': '1', 'note': 'Existing evidence'}, 'sources': ['first']},
            {'id': 'two', 'values': {'length': '2'}, 'sources': ['second']}]}
        delta = {'schema_version': 1, 'rows': [
            {'id': 'one', 'values': {'length': '10'}, 'sources': ['first', 'new']},
            {'id': 'three', 'values': {'length': '3'}, 'sources': []}]}
        original = deepcopy((before, delta))
        result = sim.merge_row_delta(before, delta)
        self.assertEqual((before, delta), original)
        self.assertEqual([r['id'] for r in result['rows']], ['one', 'two', 'three'])
        self.assertEqual(result['rows'][0]['values'], {'length': '10', 'note': 'Existing evidence'})
        self.assertEqual(result['rows'][0]['sources'], ['first', 'new'])
        self.assertEqual(result['rows'][1], before['rows'][1])

    def test_changed_template_product_revision_and_evidence_preimages(self):
        for key, value in [('spec_revision', 8), ('updated_at', '2026-09-07T11:00:00+00:00'),
                           ('contract_version', 10), ('snapshot_sha256', 'd' * 64)]:
            original = self.proposal['based_on'][key]
            self.proposal['based_on'][key] = value
            self.assertIn('stale_preimage', self.codes())
            self.proposal['based_on'][key] = original
        self.proposal['based_on']['fingerprints']['facts_sha256'] = 'd' * 64
        self.assertIn('stale_preimage', self.codes())

    def test_foreign_product_or_observation_cannot_be_silently_dropped(self):
        self.snapshot['observations'][0]['fact']['tenant_id'] = 'foreign'
        with self.assertRaises(ValueError):
            self.inspect()

    def test_scope_is_preserved_and_cannot_satisfy_unscoped_preimage(self):
        self.snapshot['observations'][0]['fact']['subject_scope'] = 'front'
        change = self.proposal['facts'][0]
        change.update(key='flag', proposed=True, unit=None)
        change['current']['value'] = False
        self.assertFalse(self.inspect()['issues'])
        self.assertIsNotNone(self.snapshot['observations'][0]['fact']['subject_scope'])

    def test_false_and_zero_are_distinct_preimages(self):
        self.proposal['identity'][0]['current'] = 0
        self.snapshot['product']['model'] = False
        self.assertIn('identity_preimage', self.codes())
        self.assertFalse(sim.same(False, 0))

    def test_fact_provenance_hash_is_required_for_replacement(self):
        change = self.proposal['facts'][0]
        change.update(key='flag', proposed=True, unit=None)
        change['current']['value'] = False
        self.assertIn('fact_preimage', self.codes())
        fact = self.snapshot['observations'][0]
        change['current'].update(fact_id=fact['fact']['id'], fact_sha256=fact['fact_sha256'],
                                 source='mechanic', confirmed=True)
        self.assertNotIn('fact_preimage', self.codes())
        change['current']['confirmed'] = False
        self.assertIn('fact_preimage', self.codes())

    def test_legacy_fields_are_not_writable_candidates(self):
        self.snapshot['editor']['template']['form_contract']['roles'] = {'amount': 'legacy'}
        self.assertIn('field_unavailable', self.codes())

    def test_no_implicit_unit_conversion(self):
        self.proposal['facts'][0]['unit'] = 'cm'
        self.assertIn('unit_mismatch', self.codes())

    def test_boolean_type_cannot_fill_numeric_field(self):
        self.proposal['facts'][0]['proposed'] = False
        self.assertIn('typed_value_required', self.codes())

    def test_missing_source_and_tampered_archive_are_distinct(self):
        self.proposal['facts'][0]['evidence'] = ['absent']
        self.assertIn('unknown_evidence', self.codes())
        (self.archive / 'evidence.txt').write_text('Changed bytes')
        self.assertIn('evidence_hash_mismatch', self.codes())

    def test_unarchived_evidence_stays_pending(self):
        self.proposal['evidence'][0]['artifact_path'] = None
        self.assertIn('evidence_artifact_unavailable', self.codes('pending'))

    def test_path_traversal_and_symlinks_cannot_read_unrelated_files(self):
        for path in ('../outside.txt', '/etc/passwd'):
            self.proposal['evidence'][0]['artifact_path'] = path
            self.assertIn('evidence_path_outside_archive', self.codes())
        (self.archive / 'link').symlink_to('/etc/passwd')
        self.proposal['evidence'][0]['artifact_path'] = 'link'
        self.assertIn('evidence_path_outside_archive', self.codes())

    def test_duplicate_research_identities_are_rejected(self):
        for collection in ('facts', 'identity', 'evidence'):
            item = deepcopy(self.proposal[collection][0])
            self.proposal[collection].append(item)
            with self.assertRaises(ValueError):
                self.inspect()
            self.proposal[collection].pop()

    def test_review_cannot_survive_changed_value_or_self_review(self):
        self.proposal['facts'][0]['proposed'] = '10'
        self.assertIn('independent_review_required', self.codes('pending'))
        self.sign_record()
        self.assertNotIn('independent_review_required', self.codes('pending'))
        self.proposal['review']['by'] = 'codex'
        self.assertIn('independent_review_required', self.codes('pending'))

    def test_conflict_is_not_resolved_by_latest_date(self):
        self.proposal['conflicts'] = [{'field': 'amount', 'description': 'Competing variants',
                                       'evidence': ['oem'], 'resolution': None}]
        self.assertIn('unresolved_conflict', self.codes())

    def test_reference_effects_are_exhaustive_and_not_sent_as_manual_fact(self):
        self.proposal['reference'] = {'id': 'synthetic-ref', 'binding_level': 'model',
                                      'evidence': ['oem'], 'reason': 'Synthetic reference'}
        self.proposal['facts'][0]['origin'] = 'reference'
        self.snapshot['references'] = [{'id': 'synthetic-ref', 'facts': {'amount': '9007199254740993.125'}}]
        self.assertFalse(self.inspect()['issues'])
        self.assertEqual(self.inspect()['request']['p_values_patch'], {})
        self.snapshot['references'][0]['facts']['flag'] = True
        self.assertIn('reference_effects_not_fully_reviewed', self.codes())

    def test_reference_numeric_mismatch_is_not_coerced(self):
        self.proposal['facts'][0]['origin'] = 'reference'
        self.snapshot['product']['spec_reference_id'] = 'synthetic-ref'
        self.snapshot['references'] = [{'id': 'synthetic-ref', 'facts': {'amount': '9007199254740993.124'}}]
        self.assertIn('reference_fact_mismatch', self.codes())

    def test_duplicate_json_and_nonfinite_literals_fail_before_decoding(self):
        path = self.archive / 'input.json'
        for text in ('{"id":1,"id":2}', '{"value":NaN}', '{"value":Infinity}'):
            path.write_text(text)
            with self.assertRaises(ValueError):
                sim.load_json(path)

    def test_schema_formats_are_enforced(self):
        self.proposal['evidence'][0]['consulted_on'] = '2026-02-30'
        with self.assertRaises(ValueError):
            self.inspect()

    def test_output_never_overwrites_a_prior_receipt(self):
        path = self.archive / 'result.json'
        sim.write_new(path, {'writes': 0})
        with self.assertRaises(FileExistsError):
            sim.write_new(path, {'writes': 1})
        self.assertEqual(json.loads(path.read_text()), {'writes': 0})

    def test_fresh_simulation_uses_two_read_commands_and_no_writer(self):
        calls = []
        snapshot = self.snapshot
        def read(command, params):
            calls.append(command)
            if command == 'get_product_spec_research_snapshot_v1':
                return deepcopy(snapshot)
            self.assertEqual(command, 'preview_product_spec_research_v1')
            return {'snapshot_sha256': snapshot['snapshot_sha256'], 'actor_id': self.actor,
                    'tenant_id': self.tenant, 'product_id': self.product, 'mode': 'simulation',
                    'apply_authorized': False, 'mechanical_approval': False,
                    'values': {'flag': False, 'amount': params['p_values_patch']['amount']}, 'issues': []}
        client = type('ReadOnlyClient', (), {'actor_id': self.actor, 'project': 'abcdefghijklmnopqrst',
                                          'read': staticmethod(read)})()
        result = sim.simulate(self.proposal, client, self.archive)
        self.assertEqual(len(calls), 2)
        self.assertFalse(result['can_apply'])
        self.assertFalse(result['issues'])

    def test_stale_proposal_never_reaches_preview(self):
        self.proposal['based_on']['spec_revision'] = 6
        calls = []
        def read(command, params):
            calls.append(command)
            return self.snapshot
        client = type('ReadOnlyClient', (), {'actor_id': self.actor, 'project': 'abcdefghijklmnopqrst',
                                          'read': staticmethod(read)})()
        result = sim.simulate(self.proposal, client, self.archive)
        self.assertEqual(calls, ['get_product_spec_research_snapshot_v1'])
        self.assertTrue(result['issues'])


if __name__ == '__main__':
    unittest.main()
