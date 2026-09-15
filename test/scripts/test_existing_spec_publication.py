#!/usr/bin/env python3
"""Boundary tests for existing-template forward publication, not bike claims."""
from copy import deepcopy
from pathlib import Path
import sys
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/inventory'))
from compile_existing_spec_publication import compile_packet, generate_migration
from compile_non_drivetrain_publication import TENANT, metadata_records


def fixture():
    uid = lambda key: str(uuid.uuid5(uuid.NAMESPACE_URL, 'vinabike:forward-test:' + key))
    family, old_key, new_key = ('forward_publication_probe',
                                'forward_original_observation', 'forward_scoped_option')
    contract = {'rules_version': 2, 'roles': {old_key: 'primary'},
                'semantic_roles': {old_key: 'measurement'}, 'labels': {},
                'allowed_when': {old_key: {'kind': 'always'}},
                'required_when': {old_key: {'kind': 'never'}},
                'allowed_options': {}, 'prerequisites': {}, 'helpers': {},
                'evidence_requirements': {}}
    definitions = {old_key: {
        'id': uid(old_key), 'key': old_key, 'origin': 'existing',
        'label': 'Original fixture observation', 'data_type': 'number',
        'unit': 'mm', 'allowed_values': [], 'validation_rules': {'positive': True}}}
    template = {'id': uid(family), 'key': family, 'name': 'Forward fixture',
                'technical_family': 'bearing', 'origin': 'existing',
                'form_contract': contract, 'fields': [{
                    'key': old_key, 'section_key': 'primary', 'sort_order': 0,
                    'is_required': False, 'visibility_rules': [],
                    'option_rules': [], 'constraint_rules': []}]}
    records = metadata_records([template], definitions, set())
    moment = '2026-09-01T00:00:00+00:00'
    for table in records.values():
        for row in table:
            row.update(created_at=moment, updated_at=moment)
    records['spec_templates'][0]['contract_version'] = 2
    before = {'tenant_id': TENANT, 'templates': records['spec_templates'],
              'fields': records['spec_template_fields'],
              'existing_definitions': [{**records['spec_definitions'][0], 'options': []}]}
    target = deepcopy(template)
    target['form_contract']['roles'][old_key] = 'legacy'
    target['form_contract']['semantic_roles'][old_key] = 'legacy'
    target['form_contract']['allowed_when'][old_key] = {'kind': 'never'}
    target['fields'][0]['section_key'] = 'legacy'
    definitions[new_key] = {
        'id': uid(new_key), 'key': new_key, 'origin': 'new',
        'label': 'Synthetic scoped choice', 'data_type': 'single_select',
        'unit': None, 'allowed_values': ['A', 'B'], 'validation_rules': {}}
    target['fields'].append({
        'key': new_key, 'section_key': 'declaration', 'sort_order': 10,
        'is_required': False, 'visibility_rules': [], 'option_rules': [],
        'constraint_rules': []})
    target['form_contract']['roles'][new_key] = 'declaration'
    target['form_contract']['semantic_roles'][new_key] = 'declaration'
    target['form_contract']['allowed_when'][new_key] = {'kind': 'always'}
    target['form_contract']['required_when'][new_key] = {'kind': 'never'}
    hashes = {'catalog_sha256': 'a' * 64, 'cases_sha256': 'b' * 64,
              'preimage_sha256': 'c' * 64}
    cases = {'catalogue_sha256': hashes['catalog_sha256'], 'cases': [{
        'id': 'forward_synthetic_option', 'template': family,
        'values': {new_key: 'A'}, 'expected_blocking': []}]}
    return {'catalog': {'templates': [target], 'definitions': definitions},
            'cases': cases, 'before': before, 'families': [family],
            'hashes': hashes, 'adjudication': {'fixture': 'Not a mechanical assertion'}}


class ForwardPublication(unittest.TestCase):
    def test_preserves_ids_and_bumps_only_actual_changes(self):
        data = fixture()
        packet = compile_packet(**data)
        self.assertEqual(packet['records']['spec_templates'][0]['contract_version'], 5)
        self.assertEqual(packet['records']['spec_template_fields'][0]['id'],
                         data['before']['fields'][0]['id'])
        self.assertEqual(len(packet['patches']), 2)
        self.assertFalse(packet['product_writes'])
        self.assertNotIn('update public.products', generate_migration(packet, source_sha='a'*64))

    def test_shared_change_rejected(self):
        data = fixture()
        next(iter(data['catalog']['definitions'].values()))['unit'] = 'in'
        with self.assertRaisesRegex(ValueError, 'Shared definition'):
            compile_packet(**data)

    def test_existing_field_cannot_disappear(self):
        data = fixture()
        data['catalog']['templates'][0]['fields'].pop(0)
        with self.assertRaises(ValueError):
            compile_packet(**data)

    def test_template_cannot_change_family(self):
        data = fixture()
        data['catalog']['templates'][0]['technical_family'] = 'chain'
        with self.assertRaisesRegex(ValueError, 'identity, family'):
            compile_packet(**data)

    def test_template_changes_cannot_be_silently_discarded(self):
        for attribute, value in (
                ('name', 'Changed name'), ('description', 'Changed description'),
                ('default_tags', ['new']), ('is_active', False),
                ('tenant_id', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
                ('contract_version', 99), ('created_at', '2020-01-01'),
                ('updated_at', '2020-01-01')):
            with self.subTest(attribute=attribute):
                data = fixture()
                data['catalog']['templates'][0][attribute] = value
                with self.assertRaisesRegex(ValueError, 'Unsupported template metadata change'):
                    compile_packet(**data)

    def test_default_and_helper_changes_keep_original_field_identity(self):
        data = fixture()
        data['before']['fields'][0].update(default_value_json='7', helper_text='Before')
        packet = compile_packet(**data)
        old = packet['before']['spec_template_fields'][0]
        after = packet['records']['spec_template_fields'][0]
        self.assertEqual(old['id'], after['id'])
        self.assertEqual(old['default_value_json'], '7')
        self.assertIsNone(after['default_value_json'])

    def test_explicit_field_presentation_survives_a_contract_only_update(self):
        data = fixture()
        old = data['before']['fields'][0]
        old.update(default_value_json={'number': '7.10'}, helper_text='Documented dimension')
        target = data['catalog']['templates'][0]
        target['fields'][0].update(
            default_value_json=deepcopy(old['default_value_json']),
            helper_text=old['helper_text'], section_key=old['section_key'])
        packet = compile_packet(**data)
        after = packet['records']['spec_template_fields'][0]
        self.assertEqual(after['default_value_json'], old['default_value_json'])
        self.assertEqual(after['helper_text'], old['helper_text'])
        self.assertFalse(any(p['table'] == 'spec_template_fields' and
                            p['before']['id'] == old['id'] for p in packet['patches']))

    def test_explicit_helper_changes_are_never_discarded(self):
        data = fixture()
        target = data['catalog']['templates'][0]['fields'][0]
        target['helper_text'] = 'Reviewed replacement helper'
        target['default_value_json'] = '8.25'
        after = compile_packet(**data)['records']['spec_template_fields'][0]
        self.assertEqual(after['helper_text'], 'Reviewed replacement helper')
        self.assertEqual(after['default_value_json'], '8.25')

    def test_unreviewed_extra_definition_rejected(self):
        data = fixture()
        data['catalog']['definitions']['unrelated'] = {'id': 'irrelevant'}
        with self.assertRaisesRegex(ValueError, 'Only definitions used'):
            compile_packet(**data)

    def test_metadata_noop_does_not_bump_revision(self):
        data = fixture()
        # Feed the target back as a captured preimage after its first update.
        first = compile_packet(**data)
        before = data['before']
        before['templates'] = deepcopy(first['records']['spec_templates'])
        before['fields'] = deepcopy(first['records']['spec_template_fields'])
        for table in ('templates', 'fields'):
            for row in before[table]:
                row.update(created_at='2026-09-01T00:00:00+00:00',
                           updated_at='2026-09-01T00:00:00+00:00')
        for d in first['records']['spec_definitions']:
            before['existing_definitions'].append({**d, 'options': [
                o for o in first['records']['spec_definition_values']
                if o['spec_definition_id'] == d['id']]})
        replay = compile_packet(**data)
        self.assertEqual(replay['patches'], [])
        self.assertEqual(replay['records']['spec_templates'][0]['contract_version'], 5)


if __name__ == '__main__':
    unittest.main()
