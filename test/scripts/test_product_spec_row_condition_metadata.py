"""The compiler rejects the same malformed metadata as SQL and Dart fixtures."""
from copy import deepcopy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/inventory'))
from product_spec_row_condition_metadata import validate_row_conditions

DOCUMENT = json.loads((ROOT / 'test/fixtures/product_spec_row_conditions.json').read_text())
DEFINITIONS = {key: {'data_type': field['data_type'], 'validation_rules': {'rows_schema': field['schema']}}
               for key, field in DOCUMENT['fields'].items()}


class RowConditionMetadataTest(unittest.TestCase):
    def test_shared_valid_metadata_is_not_mutated(self):
        before = deepcopy(DOCUMENT)
        validate_row_conditions(DOCUMENT['contract'], DEFINITIONS, set(DEFINITIONS))
        self.assertEqual(DOCUMENT, before)

    def test_legacy_target_is_not_active_just_because_its_schema_exists(self):
        contract = deepcopy(DOCUMENT['contract'])
        contract['roles'] = {'configurations': 'legacy'}
        with self.assertRaises(ValueError):
            validate_row_conditions(contract, DEFINITIONS, set(DEFINITIONS))

    def test_boolean_does_not_impersonate_schema_version_one(self):
        contract = deepcopy(DOCUMENT['contract'])
        contract['row_conditions']['version'] = True
        with self.assertRaises(ValueError):
            validate_row_conditions(contract, DEFINITIONS, set(DEFINITIONS))


def invalid_case(case):
    def test(self):
        with self.assertRaises(ValueError):
            validate_row_conditions(case['contract'], DEFINITIONS, set(DEFINITIONS))
    return test


for case in DOCUMENT['invalid_metadata']:
    setattr(RowConditionMetadataTest, 'test_' + case['id'], invalid_case(case))


if __name__ == '__main__':
    unittest.main()
