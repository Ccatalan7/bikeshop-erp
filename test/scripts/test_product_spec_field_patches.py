"""The local catalogue integrator cannot turn a proposal into fill authority."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts/inventory'))
from product_spec_field_patches import apply_reviewed_field_addendum, artifact_sha
from compile_product_spec_catalog import validate_contract


class FieldPatchBoundaryTest(unittest.TestCase):
    def setUp(self):
        contract = {
            'rules_version': 2, 'roles': {'size': 'measurement'},
            'semantic_roles': {'size': 'compatibility'}, 'labels': {}, 'helpers': {},
            'allowed_when': {'size': {'kind': 'always'}},
            'required_when': {'size': {'kind': 'never'}}, 'allowed_options': {},
            'prerequisites': {}, 'evidence_requirements': {'size': False},
        }
        self.base = {
            'definitions': {'size': {'id': 'stable-definition', 'key': 'size', 'origin': 'existing',
                'label': 'Size', 'data_type': 'single_select', 'unit': None,
                'allowed_values': ['01'], 'validation_rules': {}, 'used_by': ['test']}},
            'templates': [{'key': 'test', 'id': 'stable-template', 'form_contract': contract,
                'fields': [{'key': 'size', 'section_key': 'measurement', 'sort_order': 0,
                    'is_required': False, 'visibility_rules': [], 'option_rules': [], 'constraint_rules': []}]}],
            'publication_gates': {'all_family_domain_review_complete': False,
                'all_product_assignment_review_complete': False, 'compatibility_rules_integrated': False,
                'fill_allowed': False}, 'stats': {'templates': 1, 'product_facts_changed': 0},
        }
        self.proposal = {'new_definitions': {}, 'patches': [
            {'id': 'P1', 'template': None, 'key': 'size', 'op': 'append_allowed_values',
                'before': ['01'], 'after': ['01', '1']},
        ], 'verified': True}
        self.decisions = {'approval_scope': 'field_representation',
            'base_sha256': artifact_sha(self.base), 'proposal_sha256': artifact_sha(self.proposal),
            'patch_adjudications': [{'patch_id': 'P1', 'decision': 'aceptar', 'reason': 'Separate literal tokens.'}]}

    def apply(self):
        return apply_reviewed_field_addendum(self.base, self.proposal, self.decisions, validate_contract)

    def test_literal_options_expand_without_changing_identity_or_fill_authority(self):
        result = self.apply()
        self.assertEqual(result['definitions']['size']['allowed_values'], ['01', '1'])
        self.assertEqual(result['definitions']['size']['id'], 'stable-definition')
        self.assertEqual(result['publication_gates'], self.base['publication_gates'])
        self.assertEqual(self.base['definitions']['size']['allowed_values'], ['01'])

    def test_source_file_hash_is_preserved_across_contributor_formatting(self):
        raw = json.dumps(self.proposal, indent=1).encode()
        self.decisions['proposal_sha256'] = hashlib.sha256(raw).hexdigest()
        result = apply_reviewed_field_addendum(self.base, raw, self.decisions, validate_contract)
        self.assertEqual(result['field_addenda'][0]['proposal_sha256'], hashlib.sha256(raw).hexdigest())

    def test_proposals_own_verified_flag_does_not_approve_it(self):
        self.decisions['patch_adjudications'] = []
        with self.assertRaises(ValueError): self.apply()

    def test_changed_source_or_base_cannot_reuse_a_review(self):
        self.proposal['patches'][0]['after'].append('2')
        with self.assertRaises(ValueError): self.apply()

    def test_preimage_conflict_leaves_the_original_untouched(self):
        self.proposal['patches'][0]['before'] = ['different']
        self.decisions['proposal_sha256'] = artifact_sha(self.proposal)
        before = deepcopy(self.base)
        with self.assertRaises(ValueError): self.apply()
        self.assertEqual(self.base, before)

    def test_cannot_remove_existing_token_through_append(self):
        self.proposal['patches'][0]['after'] = ['1']
        self.decisions['proposal_sha256'] = artifact_sha(self.proposal)
        with self.assertRaises(ValueError): self.apply()

    def test_rejected_patch_is_not_applied(self):
        self.decisions['patch_adjudications'][0]['decision'] = 'rechazar'
        self.assertEqual(self.apply()['definitions'], self.base['definitions'])

    def label_proposal(self):
        self.base['templates'][0]['name'] = 'Complete assembly'
        self.proposal['patches'][0].update(op='replace_template_label',
            template='test', key='name', before='Complete assembly', after='Assembly')
        self.decisions.update(base_sha256=artifact_sha(self.base),
                              proposal_sha256=artifact_sha(self.proposal))

    def test_template_label_preserves_identity_contract_and_closed_gates(self):
        self.label_proposal()
        result = self.apply()
        expected = deepcopy(self.base['templates'][0])
        expected['name'] = 'Assembly'
        self.assertEqual(result['templates'][0], expected)
        self.assertEqual(result['publication_gates'], self.base['publication_gates'])

    def test_label_operation_cannot_change_a_template_identity_or_accept_drift(self):
        for key, before, after in [('id', 'stable-template', 'other-id'),
                                   ('name', 'different', 'Assembly'),
                                   ('name', 'Complete assembly', '')]:
            with self.subTest(key=key, before=before, after=after):
                self.label_proposal()
                self.proposal['patches'][0].update(key=key, before=before, after=after)
                self.decisions['proposal_sha256'] = artifact_sha(self.proposal)
                with self.assertRaises(ValueError): self.apply()

    def test_correction_without_concrete_replacement_is_not_an_approval(self):
        self.decisions['patch_adjudications'][0]['decision'] = 'corregir'
        with self.assertRaises(ValueError): self.apply()

    def test_a_published_or_filled_catalogue_needs_a_different_workflow(self):
        self.base['publication_gates']['fill_allowed'] = True
        self.decisions['base_sha256'] = artifact_sha(self.base)
        with self.assertRaises(ValueError): self.apply()

    def test_added_contract_bucket_requires_an_explicit_present_and_value_preimage(self):
        self.proposal['patches'][0].update(op='replace_field_contract', template='test',
            before={'roles': 'measurement'}, after={'roles': 'measurement',
                'allowed_when': {'kind': 'never'}})
        self.decisions['proposal_sha256'] = artifact_sha(self.proposal)
        with self.assertRaises(ValueError): self.apply()
        self.decisions['patch_adjudications'][0]['before_extensions'] = {
            'allowed_when': {'present': True, 'value': {'kind': 'always'}}}
        self.assertEqual(self.apply()['templates'][0]['form_contract']['allowed_when']['size'], {'kind': 'never'})
        self.base['templates'][0]['form_contract']['allowed_when']['size'] = {'kind': 'never'}
        self.decisions['base_sha256'] = artifact_sha(self.base)
        with self.assertRaises(ValueError): self.apply()

    def row_proposal(self, origin='new'):
        columns = [{'key': 'model', 'label': 'Model', 'type': 'text'}]
        self.base['definitions']['size'].update(origin=origin, data_type='json',
            allowed_values=[], validation_rules={'rows_schema': {'version': 1, 'columns': columns}})
        self.proposal['patches'] = [{'id': 'P1', 'template': None, 'key': 'size',
            'op': 'append_row_columns', 'before': deepcopy(columns),
            'after': [*columns, {'key': 'minimum', 'label': 'Minimum', 'type': 'decimal'}]}]
        self.decisions.update(base_sha256=artifact_sha(self.base), proposal_sha256=artifact_sha(self.proposal))

    def test_row_extensions_preserve_the_original_schema_and_stable_id(self):
        self.row_proposal()
        result = self.apply()
        self.assertEqual(result['definitions']['size']['id'], 'stable-definition')
        self.assertEqual(len(result['definitions']['size']['validation_rules']['rows_schema']['columns']), 2)
        self.assertEqual(len(self.base['definitions']['size']['validation_rules']['rows_schema']['columns']), 1)

    def test_row_extension_cannot_modify_a_persisted_definition(self):
        self.row_proposal(origin='existing')
        with self.assertRaises(ValueError): self.apply()

    def test_row_extension_cannot_shadow_or_replace_columns(self):
        self.row_proposal()
        self.proposal['patches'][0]['after'][1]['key'] = 'model'
        self.decisions['proposal_sha256'] = artifact_sha(self.proposal)
        with self.assertRaises(ValueError): self.apply()

    def test_new_ordered_constraint_needs_existing_numeric_columns(self):
        self.row_proposal()
        self.proposal['patches'][0].update(op='set_rows_ordered_pairs', before=None,
            after=[['model', 'missing']])
        self.decisions['proposal_sha256'] = artifact_sha(self.proposal)
        with self.assertRaises(ValueError): self.apply()

    def corrected_rows_proposal(self, origin='new'):
        self.row_proposal(origin)
        schema = deepcopy(self.base['definitions']['size']['validation_rules']['rows_schema'])
        self.proposal['patches'][0].update(op='replace_unpublished_rows_schema',
            before=schema, after={**deepcopy(schema), 'unique_by': [['model']]})
        self.decisions['proposal_sha256'] = artifact_sha(self.proposal)

    def test_unpublished_schema_constraints_keep_definition_and_cell_identity(self):
        self.corrected_rows_proposal()
        result = self.apply()
        self.assertEqual(result['definitions']['size']['id'], 'stable-definition')
        self.assertEqual(result['definitions']['size']['validation_rules']['rows_schema']['unique_by'], [['model']])
        self.assertEqual(result['publication_gates'], self.base['publication_gates'])
        self.assertNotIn('unique_by', self.base['definitions']['size']['validation_rules']['rows_schema'])

    def test_schema_correction_rejects_persisted_metadata_and_stale_preimage(self):
        self.corrected_rows_proposal(origin='existing')
        with self.assertRaises(ValueError): self.apply()
        self.base['definitions']['size']['origin'] = 'new'
        self.base['definitions']['size']['validation_rules']['rows_schema']['unique_by'] = []
        self.decisions['base_sha256'] = artifact_sha(self.base)
        with self.assertRaises(ValueError): self.apply()

    def test_schema_correction_cannot_silently_reinterpret_cell_units_or_types(self):
        self.corrected_rows_proposal()
        for changes in ({'type': 'decimal'}, {'unit': 'mm'}, {'key': 'different'}):
            with self.subTest(changes=changes):
                after = deepcopy(self.proposal['patches'][0]['before'])
                after['columns'][0].update(changes)
                self.proposal['patches'][0]['after'] = after
                self.decisions['proposal_sha256'] = artifact_sha(self.proposal)
                with self.assertRaises(ValueError): self.apply()

    def test_schema_correction_cannot_smuggle_an_unrecognized_grammar(self):
        self.corrected_rows_proposal()
        self.proposal['patches'][0]['after']['allOf'] = []
        self.decisions['proposal_sha256'] = artifact_sha(self.proposal)
        with self.assertRaises(ValueError): self.apply()


class NumericPatchBoundaryTest(unittest.TestCase):
    setUp = FieldPatchBoundaryTest.setUp
    apply = FieldPatchBoundaryTest.apply

    def numeric_proposal(self):
        self.base['definitions']['size'].update(
            origin='new', data_type='number', allowed_values=[],
            unit='°', validation_rules={'positive': True})
        self.proposal['patches'] = [{'id': 'P1', 'op': 'replace_unpublished_numeric_rules',
            'template': None, 'key': 'size', 'before': {'positive': True},
            'after': {'positive': True, 'max': '90'}}]
        self.decisions['base_sha256'] = artifact_sha(self.base)
        self.decisions['proposal_sha256'] = artifact_sha(self.proposal)

    def test_angular_domain_keeps_definition_identity_and_unit(self):
        self.numeric_proposal()
        result = self.apply()
        self.assertEqual(result['definitions']['size']['validation_rules']['max'], '90')
        self.assertEqual(result['definitions']['size']['unit'], '°')
        self.assertEqual(result['definitions']['size']['id'], 'stable-definition')
        self.assertEqual(self.base['definitions']['size']['validation_rules'], {'positive': True})

    def test_numeric_correction_cannot_touch_a_persisted_definition(self):
        self.numeric_proposal()
        self.base['definitions']['size']['origin'] = 'existing'
        self.decisions['base_sha256'] = artifact_sha(self.base)
        with self.assertRaises(ValueError): self.apply()

    def test_nonexact_or_empty_numeric_domains_fail_closed(self):
        self.numeric_proposal()
        for rules in ({'max': 90}, {'max': '9_0'}, {'max': 'NaN'},
                      {'min': '91', 'max': '90'}, {'positive': True, 'max': '0'},
                      {'integer': 'true'}, {'unreviewed': True}):
            with self.subTest(rules=rules):
                self.proposal['patches'][0]['after'] = rules
                self.decisions['proposal_sha256'] = artifact_sha(self.proposal)
                with self.assertRaises(ValueError): self.apply()


if __name__ == '__main__':
    unittest.main()
