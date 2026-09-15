#!/usr/bin/env python3
"""Audit every product and every template without changing or filling the ERP.

Structural observations deliberately do not mark mechanical semantics reviewed.
Both assigned and missing fichas stay in the independent domain-review queue.
"""
import argparse
import collections
import datetime as dt
import hashlib
import json
from pathlib import Path


def rule_fields(value):
    if isinstance(value, dict):
        if isinstance(value.get("field"), str):
            yield value["field"]
        for child in value.values():
            yield from rule_fields(child)
    elif isinstance(value, list):
        for child in value:
            yield from rule_fields(child)


def audit(snapshot, server_rows):
    tables = snapshot["tables"]
    products = tables["products"]
    categories = {r["id"]: r for r in tables["product_categories"]}
    definitions = {r["id"]: r for r in tables["spec_definitions"]}
    templates = {r["id"]: r for r in tables["spec_templates"]}
    mappings = {r["category_id"]: r for r in tables["category_tech_mappings"]
                if r["status"] == "active"}
    fields = collections.defaultdict(list)
    facts = collections.defaultdict(list)
    for field in tables["spec_template_fields"]:
        fields[field["template_id"]].append(field)
    for fact in tables["spec_facts"]:
        facts[fact["subject_id"]].append(fact)
    server = {row["id"]: row for row in server_rows}
    if len(server) != len(server_rows):
        raise ValueError("Duplicate product in server evaluation")
    rows = []
    expected_server_ids = set()
    for product in products:
        mapping = mappings.get(product["category_id"], {})
        template = templates.get(product.get("spec_template_id") or mapping.get("template_id"), {})
        if not template.get("is_active"):
            template = {}
        if template:
            expected_server_ids.add(product["id"])
        own_facts = facts[product["id"]]
        main_facts = [f for f in own_facts if f["subject_scope"] is None]
        field_ids = {f["spec_definition_id"] for f in fields[template.get("id")]}
        stored_ids = {f["spec_definition_id"] for f in main_facts}
        current = server.get(product["id"])
        # PostgreSQL JSON timestamps can differ only in the UTC spelling.
        timestamp = lambda s: dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
        stale = bool(current and (
            current["spec_revision"] != product["spec_revision"]
            or timestamp(current["updated_at"]) != timestamp(product["updated_at"])
            or current["contract_version"] != template.get("contract_version")
            or current["template_id"] != template.get("id")))
        pending = ["identity_and_family_semantic_review"]
        if product["product_type"] == "service":
            pending = ["service_classification_review"]
        elif not template:
            pending.append("assign_correct_technical_template")
        else:
            pending.append("family_fields_and_compatibility_review")
        if stale:
            pending.append("snapshot_changed_requery_required")
        orphan_keys = sorted(definitions[i]["key"] for i in stored_ids - field_ids)
        if orphan_keys:
            pending.append("preserve_and_review_facts_outside_current_template")
        rows.append({
            "id": product["id"], "name": product["name"], "sku": product["sku"],
            "brand": product["brand"], "model": product["model"],
            "product_type": product["product_type"], "active": product["is_active"],
            "category_id": product["category_id"],
            "category_path": categories.get(product["category_id"], {}).get("full_path"),
            "template_id": template.get("id"), "family": template.get("technical_family"),
            "explicit_template_id": product.get("spec_template_id"),
            "binding_source": ("explicit" if template else "explicit_unavailable") if product.get("spec_template_id") else ("category" if template else "none"),
            "contract_version": template.get("contract_version"),
            "spec_revision": product["spec_revision"], "updated_at": product["updated_at"],
            "facts_count": len(own_facts), "main_facts_count": len(main_facts),
            "scoped_facts_count": len(own_facts)-len(main_facts),
            "fact_keys": sorted(definitions[i]["key"] for i in stored_ids),
            "facts_outside_template": orphan_keys,
            "legacy_specifications_present": bool(product.get("specifications")),
            "missing_required_fields": sorted(definitions[f["spec_definition_id"]]["key"]
                for f in fields[template.get("id")]
                if f["is_required"] and f["spec_definition_id"] not in stored_ids),
            "server_issues": current["issues"] if current else None,
            "server_evaluation_stale": stale,
            "pending": pending, "semantic_review": "pending", "fill_ready": False,
        })
    if expected_server_ids != set(server):
        raise ValueError("Server evaluation must cover exactly every mapped product")
    template_rows = []
    for template in sorted(templates.values(), key=lambda t:(t["technical_family"],t["key"])):
        own_fields = fields[template["id"]]
        own_keys = {definitions[f["spec_definition_id"]]["key"] for f in own_fields}
        contract = template.get("form_contract") or {}
        dependencies = set(rule_fields([f["visibility_rules"] for f in own_fields]))
        for key, requirements in contract.get("prerequisites", {}).items():
            dependencies.update(requirements)
        family_products = [p for p in rows if p["template_id"] == template["id"]]
        template_rows.append({
            "id": template["id"], "key": template["key"],
            "family": template["technical_family"], "active": template["is_active"],
            "contract_version": template["contract_version"],
            "products": len(family_products), "products_with_facts": sum(bool(p["facts_count"]) for p in family_products),
            "field_count": len(own_fields),
            "fields": [{"key": definitions[f["spec_definition_id"]]["key"],
                        "role": contract.get("roles", {}).get(definitions[f["spec_definition_id"]]["key"]),
                        "type": definitions[f["spec_definition_id"]]["data_type"],
                        "validation": definitions[f["spec_definition_id"]]["validation_rules"],
                        "visibility": f["visibility_rules"],
                        "advisory_options": f["option_rules"],
                        "enforced_constraints": f["constraint_rules"]} for f in own_fields],
            "dependency_keys_outside_template": sorted(dependencies-own_keys),
            "has_source_scoped_constraints": any(f["constraint_rules"] for f in own_fields),
            "semantic_review": "partial_chain_pilot" if template["technical_family"] in ("chain","chain_link") else "pending",
            "whole_family_completed": False,
        })
    physical = [p for p in rows if p["product_type"] != "service"]
    summary = {
        "all_products_audited": len(rows), "physical_products": len(physical),
        "services": len(rows)-len(physical),
        "physical_with_template": sum(bool(p["template_id"]) for p in physical),
        "physical_without_template": sum(not p["template_id"] for p in physical),
        "physical_with_facts": sum(bool(p["facts_count"]) for p in physical),
        "physical_with_template_without_facts": sum(bool(p["template_id"]) and not p["facts_count"] for p in physical),
        "physical_without_category": sum(not p["category_id"] for p in physical),
        "products_with_facts_outside_template": sum(bool(p["facts_outside_template"]) for p in rows),
        "products_with_legacy_specifications": sum(p["legacy_specifications_present"] for p in rows),
        "products_with_server_issues": sum(bool(p["server_issues"]) for p in rows),
        "products_with_blocking_server_issues": sum(any(i.get("blocking",True) for i in p["server_issues"] or []) for p in rows),
        "stale_server_evaluations": sum(p["server_evaluation_stale"] for p in rows),
        "active_templates": sum(t["active"] for t in template_rows),
        "active_template_families": len({t["family"] for t in template_rows if t["active"]}),
        "semantically_complete_families": None,
        "semantic_completion_measurement": "not_assessed_by_structural_audit",
        "bulk_fill_enabled": False,
    }
    unmapped = collections.defaultdict(list)
    for product in physical:
        if not product["template_id"]:
            unmapped[product["category_id"]].append(product)
    return {"format_version": 1, "scope": "all_products_and_all_templates",
            "snapshot_at": snapshot["captured_at"], "summary": summary,
            "products": rows, "templates": template_rows,
            "unmapped_categories": [{"category_id": key,
                "path": categories.get(key, {}).get("full_path"),
                "products": len(items), "product_ids": [p["id"] for p in items],
                "classification_review": "pending"}
                for key,items in sorted(unmapped.items(), key=lambda x:(-len(x[1]),str(x[0])))]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", type=Path, required=True)
    parser.add_argument("--server-evaluation", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = audit(json.loads(args.snapshot.read_bytes()), json.loads(args.server_evaluation.read_bytes()))
    result["snapshot_sha256"] = hashlib.sha256(args.snapshot.read_bytes()).hexdigest()
    result["server_evaluation_sha256"] = hashlib.sha256(args.server_evaluation.read_bytes()).hexdigest()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2)+"\n")
    print(json.dumps(result["summary"], indent=2))


if __name__ == "__main__":
    main()
