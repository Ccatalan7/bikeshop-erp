"""Cardinality metadata uses the same frozen negative cases as Dart and SQL."""
from copy import deepcopy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/inventory'))
from compile_product_spec_catalog import validate_contract

DOCUMENT = json.loads((ROOT / 'test/fixtures/product_spec_row_cardinality.json').read_text())


def definitions(fields):
    return {key: {'key': key, 'unit': None, 'allowed_values': [], 'data_type': f['data_type'],
                  'validation_rules': {**deepcopy(f['validation_rules']),
                                       **({'rows_schema': f.get('schema')} if f['data_type'] == 'json' else {})}}
            for key, f in fields.items()}


class RowCardinalityMetadataTest(unittest.TestCase):
    def test_valid_metadata_preserves_input(self):
        before = deepcopy(DOCUMENT)
        defs = definitions(DOCUMENT['fields'])
        validate_contract('fixture', DOCUMENT['contract'], defs, set(defs))
        self.assertEqual(before, DOCUMENT)

    def test_v1_keeps_its_existing_behavior(self):
        contract = deepcopy(DOCUMENT['contract'])
        contract['row_coherence'] = {'version': 1, 'links': []}
        defs = definitions(DOCUMENT['fields'])
        validate_contract('fixture', contract, defs, set(defs))

    def test_reverse_prerequisite_cycle(self):
        contract = deepcopy(DOCUMENT['contract'])
        contract['prerequisites']['total'] = ['items']
        defs = definitions(DOCUMENT['fields'])
        with self.assertRaises(ValueError):
            validate_contract('fixture', contract, defs, set(defs))

    def test_legacy_total_is_unavailable(self):
        contract = deepcopy(DOCUMENT['contract'])
        contract['roles']['total'] = 'legacy'
        defs = definitions(DOCUMENT['fields'])
        with self.assertRaises(ValueError):
            validate_contract('fixture', contract, defs, set(defs))


def invalid_case(case):
    def test(self):
        defs = definitions(case['fields'])
        with self.assertRaises(ValueError):
            validate_contract('fixture', case['contract'], defs, set(defs))
    return test


for case in DOCUMENT['invalid_metadata']:
    setattr(RowCardinalityMetadataTest, 'test_' + case['id'], invalid_case(case))

if __name__ == '__main__':
    unittest.main()
