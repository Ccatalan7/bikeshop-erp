"""Typed expectation metadata uses the shared SQL/Dart boundary fixtures."""
from copy import deepcopy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/inventory'))
from product_spec_row_condition_metadata import validate_row_conditions

DOCUMENT = json.loads((ROOT / 'test/fixtures/product_spec_row_value_conditions.json').read_text())
DEFINITIONS = {key: {'data_type': value['data_type'], 'validation_rules': {'rows_schema': value['schema']}}
               for key, value in DOCUMENT['fields'].items()}


class RowValueMetadataTest(unittest.TestCase):
    def test_legacy_contract_without_extension_is_unchanged(self):
        validate_row_conditions({}, DEFINITIONS, set(DEFINITIONS))


def valid_case(case):
    def test(self):
        before = deepcopy(case)
        validate_row_conditions(case['contract'], DEFINITIONS, set(DEFINITIONS))
        self.assertEqual(case, before)
    return test


def invalid_case(case):
    def test(self):
        with self.assertRaises(ValueError):
            validate_row_conditions(case['contract'], DEFINITIONS, set(DEFINITIONS))
    return test


for case in DOCUMENT['cases'] + DOCUMENT['valid_metadata']:
    setattr(RowValueMetadataTest, 'test_valid_' + case['id'], valid_case(case))
for case in DOCUMENT['invalid_metadata']:
    setattr(RowValueMetadataTest, 'test_invalid_' + case['id'], invalid_case(case))


if __name__ == '__main__':
    unittest.main()
