"""Recovery integrity and local viewer safety; no database or Keychain calls."""
import copy
import importlib.util
from pathlib import Path
import unittest

MODULE = Path(__file__).resolve().parents[2] / "scripts/inventory/product_spec_legacy.py"
spec = importlib.util.spec_from_file_location("legacy", MODULE)
legacy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(legacy)

PROFILE = "10000000-0000-4000-8000-000000000001"
ARCHIVED = "10000000-0000-4000-8000-000000000002"


def fixture():
    tables = {name: [] for name in legacy.DATA_TABLES}
    tables.update({
        "products": [{"id": "p1", "tenant_id": "tenant1", "name": "<script>evil()</script>",
                      "sku": "legacy", "category_id": "c1"}],
        "product_categories": [{"id": "c1", "tenant_id": "tenant1", "full_path": "Test"}],
        "spec_templates": [{"id": "t1", "tenant_id": None}],
        "spec_definitions": [{"id": "d1", "tenant_id": None, "key": "reusable", "label": "Reutilizable"}],
        "spec_facts": [{"id": "f1", "tenant_id": "tenant1", "subject_id": "p1",
                        "spec_definition_id": "d1", "value_boolean": False,
                        "source": "supplier_text", "confirmed": False}],
    })
    return {"format_version": 1, "scope": "vinabike_product_specs_pre_fill",
            "tenant": {"id": "tenant1", "subdomain": "vinabike"},
            "captured_at": "2026-09-06", "tables": tables,
            "operational_fingerprint": {"products": 1}}


def profile(identifier, row_id, archived_at=None, **extra):
    # Synthetic component profile in the shape the server emits (to_jsonb of
    # the row, generated columns included). No product or OEM data.
    row = {"id": identifier, "tenant_id": "tenant1", "product_id": "p1",
           "collection_definition_id": "d2", "member_row_id": row_id,
           "member_identity": {"family": "part_test", "identity_brand": "<b>Fixture</b>",
                               "identity_model": "Model A"},
           "identity_sources": ["https://example.test/pack"], "manufacturer_sku": None,
           "template_id": "t2", "saved_contract_version": 5, "reference_id": None,
           "created_at": "2026-09-14T20:00:00+00:00", "updated_at": "2026-09-14T20:00:00+00:00",
           "archived_at": archived_at, "scope": "member:" + identifier,
           "active_template_guard": None if archived_at else True}
    row.update(extra)
    return row


def member_fixture():
    sample = fixture()
    sample["format_version"] = 2
    sample["operational_fingerprint"]["member_profiles"] = 2
    tables = sample["tables"]
    tables["spec_templates"].append({"id": "t2", "tenant_id": None, "key": "part_test"})
    tables["spec_definitions"] += [
        {"id": "d2", "tenant_id": None, "key": "included_parts", "label": "Piezas incluidas"},
        {"id": "d3", "tenant_id": None, "key": "member_length", "label": "Largo", "unit": "mm"}]
    tables["spec_facts"] += [
        {"id": "f2", "tenant_id": "tenant1", "subject_id": "p1", "subject_scope": "member:" + PROFILE,
         "spec_definition_id": "d3", "value_number": "9007199254740993.2",
         "source": "mechanic", "confirmed": False},
        {"id": "f3", "tenant_id": "tenant1", "subject_id": "p1", "subject_scope": "member:" + ARCHIVED,
         "spec_definition_id": "d3", "value_number": "7.1", "source": "catalog", "confirmed": False}]
    tables["spec_fact_readings"].append(
        {"fact_id": "f2", "tenant_id": "tenant1", "definition_id": "d3", "quote": "cita exacta",
         "model": "fixture", "read_at": "2026-09-14T20:05:00+00:00", "source_digest": "digest",
         "source_text": "texto largo del producto", "vocabulary_digest": "v"})
    tables["product_spec_member_profiles"] = [
        profile(PROFILE, "r1"),
        profile(ARCHIVED, "r1", archived_at="2026-09-14T21:00:00+00:00",
                member_identity={"family": "part_test", "identity_brand": "Fixture"})]
    tables["product_spec_member_profile_events"] = [
        {"id": "e1", "profile_id": ARCHIVED, "tenant_id": "tenant1", "product_id": "p1",
         "actor_id": "u1", "occurred_at": "2026-09-14T21:00:00+00:00",
         "before_state": {"member_row_id": "r1", "archived_at": None},
         "after_state": {"member_row_id": "r1", "archived_at": "2026-09-14T21:00:00+00:00"}}]
    return sample


def member_tables(sample):
    return sample["tables"]["product_spec_member_profiles"]


class LegacyIntegrityTest(unittest.TestCase):
    def test_foreign_tenant_rejected(self):
        sample = fixture()
        sample["tables"]["products"][0]["tenant_id"] = "another"
        with self.assertRaisesRegex(ValueError, "Foreign tenant"):
            legacy.validate_snapshot(sample)

    def test_missing_table_rejected(self):
        sample = fixture()
        del sample["tables"]["spec_fact_readings"]
        with self.assertRaisesRegex(ValueError, "incomplete"):
            legacy.validate_snapshot(sample)

    def test_orphan_enum_selection_rejected(self):
        sample = fixture()
        sample["tables"]["spec_fact_values"].append({"fact_id": "f1", "value_id": "missing"})
        with self.assertRaisesRegex(ValueError, "Broken reference"):
            legacy.validate_snapshot(sample)

    def test_duplicate_product_rejected(self):
        sample = fixture()
        sample["tables"]["products"] *= 2
        with self.assertRaisesRegex(ValueError, "Duplicate IDs"):
            legacy.validate_snapshot(sample)

    def test_false_and_provenance_survive_roundtrip(self):
        sample = fixture()
        before = copy.deepcopy(sample)
        self.assertEqual(legacy.validate_snapshot(sample)["spec_facts"], 1)
        page = legacy.render_view(sample)
        self.assertIn("false", page)
        self.assertIn("supplier_text", page)
        self.assertEqual(sample, before)

    def test_product_text_cannot_inject_markup(self):
        page = legacy.render_view(fixture())
        self.assertNotIn("<script>evil()", page)
        self.assertIn("&lt;script&gt;evil()&lt;/script&gt;", page)
        self.assertIn("default-src 'none'", page)


class MemberProfileFormatTest(unittest.TestCase):
    def test_format_1_still_validates_without_member_tables(self):
        counts = legacy.validate_snapshot(fixture())
        self.assertEqual(set(counts), set(legacy.DATA_TABLES))
        legacy.validate_manifest({"format_version": 1, "row_counts": counts}, fixture(), counts)

    def test_format_1_cannot_carry_member_facts(self):
        sample = fixture()
        sample["tables"]["spec_facts"][0]["subject_scope"] = "member:" + PROFILE
        with self.assertRaisesRegex(ValueError, "Format 1 cannot carry member facts"):
            legacy.validate_snapshot(sample)

    def test_format_2_counts_and_manifest(self):
        sample = member_fixture()
        before = copy.deepcopy(sample)
        counts = legacy.validate_snapshot(sample)
        self.assertEqual(set(counts), set(legacy.DATA_TABLES + legacy.MEMBER_TABLES))
        self.assertEqual(counts["product_spec_member_profiles"], 2)
        self.assertEqual(counts["product_spec_member_profile_events"], 1)
        self.assertEqual(counts["spec_facts"], 3)
        self.assertEqual(sample, before)
        legacy.validate_manifest({"format_version": 2, "row_counts": counts}, sample, counts)
        with self.assertRaisesRegex(ValueError, "Manifest format mismatch"):
            legacy.validate_manifest({"format_version": 1, "row_counts": counts}, sample, counts)

    def test_format_2_requires_both_member_tables(self):
        sample = member_fixture()
        del sample["tables"]["product_spec_member_profile_events"]
        with self.assertRaisesRegex(ValueError, "incomplete"):
            legacy.validate_snapshot(sample)

    def test_member_fact_needs_its_owner_profile(self):
        sample = member_fixture()
        sample["tables"]["spec_facts"][1]["subject_scope"] = "member:10000000-0000-4000-8000-000000000009"
        with self.assertRaisesRegex(ValueError, "Member fact without owner profile"):
            legacy.validate_snapshot(sample)
        sample = member_fixture()
        sample["tables"]["products"].append({"id": "p2", "tenant_id": "tenant1", "name": "Other",
                                             "sku": "other", "category_id": "c1"})
        sample["operational_fingerprint"]["products"] = 2
        sample["tables"]["spec_facts"][1]["subject_id"] = "p2"
        with self.assertRaisesRegex(ValueError, "Member fact without owner profile"):
            legacy.validate_snapshot(sample)

    def test_profile_identity_and_archive_state_are_checked(self):
        sample = member_fixture()
        member_tables(sample)[0]["scope"] = "member:" + ARCHIVED
        with self.assertRaisesRegex(ValueError, "Profile scope mismatch"):
            legacy.validate_snapshot(sample)
        sample = member_fixture()
        member_tables(sample)[1]["active_template_guard"] = True
        with self.assertRaisesRegex(ValueError, "Archived state mismatch"):
            legacy.validate_snapshot(sample)
        sample = member_fixture()
        member_tables(sample)[0]["member_identity"] = "Fixture"
        with self.assertRaisesRegex(ValueError, "identity"):
            legacy.validate_snapshot(sample)

    def test_second_active_profile_on_a_row_rejected(self):
        sample = member_fixture()
        member_tables(sample)[1]["archived_at"] = None
        member_tables(sample)[1]["active_template_guard"] = True
        with self.assertRaisesRegex(ValueError, "Duplicate active profile row"):
            legacy.validate_snapshot(sample)

    def test_profile_references_are_checked(self):
        for field, message in (("product_id", "products"), ("template_id", "spec_templates"),
                               ("reference_id", "product_spec_references")):
            sample = member_fixture()
            member_tables(sample)[0][field] = "missing"
            with self.assertRaisesRegex(ValueError, "Broken reference.*" + message):
                legacy.validate_snapshot(sample)
        sample = member_fixture()
        sample["tables"]["product_spec_member_profile_events"][0]["profile_id"] = "missing"
        with self.assertRaisesRegex(ValueError, "Broken reference"):
            legacy.validate_snapshot(sample)
        sample = member_fixture()
        sample["tables"]["product_spec_member_profile_events"][0]["after_state"] = None
        with self.assertRaisesRegex(ValueError, "row images"):
            legacy.validate_snapshot(sample)

    def test_member_count_is_cross_checked(self):
        sample = member_fixture()
        sample["operational_fingerprint"]["member_profiles"] = 1
        with self.assertRaisesRegex(ValueError, "Member profile count"):
            legacy.validate_snapshot(sample)

    def test_view_groups_each_piece_with_identity_archive_and_evidence(self):
        sample = member_fixture()
        page = legacy.render_view(sample)
        head, _, tail = page.partition("&quot;piezas&quot;")
        # The root block lists only the root fact; the member measures live
        # under the pieces, each with its identity, archive state and evidence.
        self.assertIn("1 hechos · 2 piezas (1 archivadas)", page)
        self.assertIn("supplier_text", head)
        self.assertNotIn("9007199254740993.2", head)
        self.assertNotIn("member_length", head)
        self.assertIn("9007199254740993.2", tail)
        self.assertIn("&quot;7.1&quot;", tail)
        self.assertIn("2026-09-14T21:00:00+00:00", tail)
        self.assertIn("cita exacta", tail)
        self.assertIn("https://example.test/pack", tail)
        self.assertIn("part_test", tail)
        self.assertIn("&quot;actor&quot;: &quot;u1&quot;", tail)
        self.assertNotIn("texto largo del producto", page)
        self.assertNotIn("<b>Fixture</b>", page)
        self.assertIn("&lt;b&gt;Fixture&lt;/b&gt;", tail)
        self.assertNotIn("hechos_sin_dueno", page)

    def test_view_never_merges_an_unowned_scope_into_the_product(self):
        sample = member_fixture()
        sample["tables"]["spec_facts"][1]["subject_scope"] = "member:10000000-0000-4000-8000-000000000009"
        page = legacy.render_view(sample)
        head = page.partition("&quot;hechos_sin_dueno&quot;")[0]
        self.assertNotIn("9007199254740993.2", head)
        self.assertIn("hechos_sin_dueno", page)


if __name__ == "__main__":
    unittest.main()
