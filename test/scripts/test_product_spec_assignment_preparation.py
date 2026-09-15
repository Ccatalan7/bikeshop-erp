import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts/inventory'))
from prepare_product_spec_assignments import commands, TENANT


class AssignmentPreparationTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / 'snapshot.json'
        self.actor = '11111111-1111-4111-8111-111111111111'
        self.product_id = '22222222-2222-4222-8222-222222222222'
        product = {'id': self.product_id, 'tenant_id': TENANT, 'name': 'Synthetic lock',
                   'sku': 'SYNTHETIC', 'category_id': None, 'spec_revision': 0,
                   'updated_at': '2026-09-14T00:00:00+00:00', 'product_type': 'product'}
        self.state = {'read_schema_version': 2, 'actor_id': self.actor,
            'tenant_id': TENANT, 'product': product, 'observations': [],
            'member_profiles': {'profiles': [], 'archived_profiles': []},
            'member_profile_events': [], 'editor': {'template_id': None},
            'snapshot_sha256': 'a' * 64}
        self.decision = {**{k: product[k] for k in
            ('name', 'sku', 'category_id', 'spec_revision', 'updated_at')},
            'product_id': self.product_id,
            'target_template_id': '33333333-3333-4333-8333-333333333333',
            'target_template_key': 'lock', 'reviewed_target_contract_version': 1,
            'before_file': str(self.path), 'before_snapshot_sha256': 'a' * 64,
            'review_reason': 'Synthetic object-class review', 'facts_patch': {},
            'identity_patch': {}}
        self.write_state()
        self.proposal = {'actor_id': self.actor, 'status': 'assignment_only_review_pending',
                         'decisions': [self.decision]}

    def write_state(self):
        self.path.write_text(json.dumps(self.state))
        self.decision['before_file_sha256'] = hashlib.sha256(self.path.read_bytes()).hexdigest()

    def run_commands(self):
        return commands(self.proposal, 'b' * 64)

    def test_operation_key_is_stable_and_actor_scoped(self):
        actor, first = self.run_commands()
        self.assertEqual(actor, self.actor)
        self.assertEqual(first, self.run_commands()[1])
        self.assertEqual(first[0]['product_id'], self.product_id)
        self.proposal['actor_id'] = '55555555-5555-4555-8555-555555555555'
        self.state['actor_id'] = self.proposal['actor_id']
        self.write_state()
        self.assertNotEqual(first[0]['operation_key'], self.run_commands()[1][0]['operation_key'])

    def test_replaced_snapshot_bytes_are_rejected(self):
        self.path.write_text(self.path.read_text() + ' ')
        with self.assertRaisesRegex(ValueError, 'snapshot file changed'):
            self.run_commands()

    def test_foreign_actor_is_rejected_even_with_a_new_file_hash(self):
        self.state['actor_id'] = '44444444-4444-4444-8444-444444444444'
        self.write_state()
        with self.assertRaises(ValueError):
            self.run_commands()

    def test_duplicate_product_is_rejected(self):
        self.proposal['decisions'].append(copy.deepcopy(self.decision))
        with self.assertRaisesRegex(ValueError, 'Duplicate product'):
            self.run_commands()

    def test_technical_and_identity_changes_are_rejected(self):
        for key in ('facts_patch', 'identity_patch'):
            with self.subTest(key=key):
                self.decision[key] = {'model': 'invented'}
                with self.assertRaisesRegex(ValueError, 'cannot include'):
                    self.run_commands()
                self.decision[key] = {}

    def test_existing_scoped_observations_are_not_reclassified(self):
        self.state['member_profiles']['profiles'] = [{'id': 'existing-piece'}]
        self.write_state()
        with self.assertRaises(ValueError):
            self.run_commands()

    def test_boolean_revision_does_not_equal_zero(self):
        self.state['product']['spec_revision'] = False
        self.write_state()
        with self.assertRaisesRegex(ValueError, 'exact revision'):
            self.run_commands()

    def test_service_and_stock_set_are_outside_this_slice(self):
        for flag in ('is_service', 'is_set'):
            with self.subTest(flag=flag):
                self.state['product'][flag] = True
                self.write_state()
                with self.assertRaisesRegex(ValueError, 'ordinary physical product'):
                    self.run_commands()
                self.state['product'].pop(flag)


if __name__ == '__main__':
    unittest.main()
