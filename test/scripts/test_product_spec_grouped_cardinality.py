import json
import sys
import unittest
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/inventory'))
from compile_product_spec_catalog import validate_contract
from compile_product_spec_grouped_cardinality import compile_sql

DOCUMENT = json.loads((ROOT / 'test/fixtures/product_spec_grouped_cardinality.json').read_text())


def validate(document):
    fields = {k: {'key': k, 'unit': None, 'allowed_values': [],
                  'data_type': v['data_type'], 'validation_rules': v['validation_rules']}
              for k, v in document['fields'].items()}
    validate_contract('grouped_fixture', document['contract'], fields, set(fields))


class GroupedCardinalityTest(unittest.TestCase):
    def test_closed_contract_keeps_source_unchanged(self):
        before = deepcopy(DOCUMENT)
        validate(DOCUMENT)
        self.assertEqual(before, DOCUMENT)

    def test_dependency_cycle_through_group_link(self):
        document = deepcopy(DOCUMENT)
        document['contract']['prerequisites']['assemblies'] = ['members']
        with self.assertRaises(ValueError):
            validate(document)

    def test_legacy_parent_is_not_available(self):
        document = deepcopy(DOCUMENT)
        document['contract']['roles']['assemblies'] = 'legacy'
        with self.assertRaises(ValueError):
            validate(document)

    def test_v3_still_accepts_an_explicit_flat_count(self):
        document = deepcopy(DOCUMENT)
        document['contract']['row_coherence']['cardinalities'] = [
            {'id': 'flat', 'field': 'members', 'total_field': 'total'}]
        validate(document)

    def test_candidate_matches_immutable_predecessor_compilation(self):
        self.assertEqual(compile_sql(), (ROOT / 'scripts/inventory/sql/product_spec_grouped_cardinality_candidate.sql').read_text())


for case in DOCUMENT['invalid_metadata']:
    def check(self, case=case):
        with self.assertRaises(ValueError):
            validate(case)
    setattr(GroupedCardinalityTest, 'test_' + case['id'], check)


if __name__ == '__main__':
    unittest.main()
