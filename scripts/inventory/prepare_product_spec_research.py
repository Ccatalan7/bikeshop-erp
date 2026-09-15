#!/usr/bin/env python3
"""Prepare bounded research batches from the guarded catalogue manifest.

This tool has no database connection and emits no apply commands. Product text
and images are discovery leads; every proposal still needs source review.
"""

import argparse
import collections
import datetime
import hashlib
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--references", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--batch-size", type=int, default=20)
    args = parser.parse_args()
    if not 1 <= args.batch_size <= 50:
        parser.error("batch-size must be between 1 and 50")
    rows = json.loads(args.manifest.read_text())
    if not isinstance(rows, list) or not all(isinstance(row, dict) for row in rows):
        parser.error("manifest must contain a JSON array of product records")
    ids = [row.get("id") for row in rows]
    if not all(ids) or len(set(ids)) != len(ids):
        parser.error("manifest must contain each product ID exactly once")
    references = json.loads(args.references.read_text())
    if not isinstance(references, list) or not all(
        isinstance(reference, dict) and reference.get("id") for reference in references
    ):
        parser.error("references must contain a JSON array of identified editions")
    if len({reference["id"] for reference in references}) != len(references):
        parser.error("reference IDs must be unique")
    groups = collections.defaultdict(list)
    for row in rows:
        if row.get("spec_revision") is None or not row.get("updated_at"):
            parser.error(f"Missing concurrency snapshot for {row['id']}")
        if not isinstance(row.get("current_values"), dict):
            parser.error(f"Missing current fact values for {row['id']}")
        family = row.get("technical_family")
        # Unmapped categories remain distinct research queues, not a fake family.
        group = family or "unmapped:" + (row.get("category") or "uncategorized")
        groups[(not row["is_active"], group)].append(row)
    batches = []
    priority = {"chain_link": 0, "chain": 1, "cassette": 2,
                "rear_derailleur": 3, "shifter": 4, "brake_pad": 5}
    for (inactive, group), products in sorted(
        groups.items(), key=lambda pair: (pair[0][0],
                                         priority.get(pair[0][1], 10), pair[0][1])
    ):
        products.sort(key=lambda row: (row.get("brand") or "", row["name"], row["id"]))
        for start in range(0, len(products), args.batch_size):
            batch = products[start:start + args.batch_size]
            batches.append({
                "batch_id": f"research-{len(batches) + 1:03d}",
                "group": group,
                "active": not inactive,
                "status": "research_required",
                "products": [{
                    **row,
                    "pending": [
                        *(["family_mapping"] if not row.get("template_id") else []),
                        *(["model_identity"] if not row.get("model") else []),
                        "variant_and_packaging", "manufacturer_evidence",
                        "field_proposals", "independent_review",
                    ],
                    "proposals": [],
                    "reference_candidate": None,
                    "reference_candidates": [reference["id"] for reference in references
                        if reference["technical_family"] == row.get("technical_family")
                        and reference["brand"].strip().casefold()
                        == (row.get("brand") or "").strip().casefold()],
                } for row in batch],
            })
    result = {
        "schema_version": 1,
        "prepared_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "purpose": "research_only",
        "product_count": len(rows),
        "batch_count": len(batches),
        "source_manifest": str(args.manifest),
        "snapshot_sha256": hashlib.sha256(args.manifest.read_bytes()).hexdigest(),
        "references_sha256": hashlib.sha256(args.references.read_bytes()).hexdigest(),
        "reference_library": references,
        "batches": batches,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(f"Prepared {len(rows)} products in {len(batches)} research batches: {args.output}")


if __name__ == "__main__":
    main()
