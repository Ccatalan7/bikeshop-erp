#!/usr/bin/env python3
"""Read/hash the explicitly inventoried public objects for C3 review.

No credentials, Storage writes, copies, reference edits or deletion. Private
outputs contain customer/job identifiers and PDF text; do not publish them.
Run with the bundled Python/pypdf runtime after the guarded review manifest.
"""
import argparse
import concurrent.futures
import hashlib
import io
import json
import os
from pathlib import Path
import urllib.parse
import urllib.request

from pypdf import PdfReader

ORIGIN = "https://xzdvtzdqjeyqxnkqprtf.supabase.co"
PREFIX = "/storage/v1/object/public/vinabike-assets/"
MAX_TOTAL_BYTES = 32 * 1024 * 1024
MAX_OBJECT_BYTES = 20 * 1024 * 1024


def audit_object(item, output):
    path = item["source_path"]
    if path.split("/", 1)[0] not in ("mechanic_jobs", "presupuestos"):
        raise ValueError("Object is outside the exact review scope")
    if item["bucket_id"] != "vinabike-assets" or ".." in path.split("/"):
        raise ValueError("Invalid source path")
    request_url = ORIGIN + PREFIX + urllib.parse.quote(path, safe="/")
    with urllib.request.urlopen(request_url, timeout=30) as response:
        received_url = urllib.parse.urlsplit(response.geturl())
        if (response.status != 200 or received_url.scheme != "https"
                or received_url.netloc != urllib.parse.urlsplit(ORIGIN).netloc
                or urllib.parse.unquote(received_url.path) != PREFIX + path):
            raise ValueError("Source did not return its expected public object")
        data = response.read(MAX_OBJECT_BYTES + 1)
        if len(data) > MAX_OBJECT_BYTES:
            raise ValueError("Object exceeds the reviewed byte cap")
        if len(data) != item["declared_bytes"]:
            raise ValueError("Object changed size; refresh the inventory")
        content_type = response.headers.get_content_type()
        etag = response.headers.get("ETag")
    digest = hashlib.sha256(data).hexdigest()
    exact_refs = []
    for ref in item["exact_job_references"]:
        uri = urllib.parse.urlsplit(ref["reference"])
        if (uri.scheme != "https" or uri.netloc != urllib.parse.urlsplit(ORIGIN).netloc
                or urllib.parse.unquote(uri.path) != PREFIX + path):
            raise ValueError("Business reference is not the exact source object")
        customer = item["path_customer"]
        if (customer is None or customer["customer_id"] != ref["customer_id"]
                or customer["tenant_id"] != ref["tenant_id"]):
            raise ValueError("Path owner differs from the referenced job owner")
        exact_refs.append({k: ref[k] for k in ("job_id", "tenant_id", "customer_id")})
    receipt = {
        "object_id": item["object_id"], "source_bucket": item["bucket_id"],
        "source_path": path, "source_updated_at": item["updated_at"],
        "observed_bytes": len(data), "sha256": digest,
        "content_type": content_type, "etag": etag,
        "exact_job_references": exact_refs,
        "copy_verified": False, "references_changed": False, "public_retired": False,
    }
    if item["content_type"] == "application/pdf":
        reader = PdfReader(io.BytesIO(data))
        if len(reader.pages) > 20:
            raise ValueError("PDF exceeds the review page cap")
        text = "\n\n".join(page.extract_text() or "" for page in reader.pages)
        leaf = output / (digest + ".pdf")
        leaf.write_bytes(data)
        leaf.chmod(0o600)
        text_path = output / (digest + ".txt")
        text_path.write_text(text)
        text_path.chmod(0o600)
        receipt.update({"pdf_pages": len(reader.pages), "pdf_text_file": str(text_path.resolve()),
                        "pdf_file": str(leaf.resolve())})
    return receipt


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    manifest = json.loads(args.manifest.read_text())
    if not manifest or len(manifest) > 16:
        raise ValueError("Refresh/review the inventory instead of broadening its scope")
    if sum(item["declared_bytes"] for item in manifest) > MAX_TOTAL_BYTES:
        raise ValueError("Review scope exceeds the total byte cap")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    args.output_dir.chmod(0o700)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        receipts = list(executor.map(lambda item: audit_object(item, args.output_dir), manifest))
    result = args.output_dir / "source-byte-receipts.json"
    result.write_text(json.dumps(receipts, indent=2) + "\n")
    result.chmod(0o600)
    print(json.dumps({
        "objects_read": len(receipts),
        "objects_with_exact_job_owner": sum(bool(r["exact_job_references"]) for r in receipts),
        "pdf_objects": sum("pdf_pages" in r for r in receipts),
        "distinct_pdf_bytes": len({r["sha256"] for r in receipts if "pdf_pages" in r}),
        "total_bytes": sum(r["observed_bytes"] for r in receipts),
        "storage_writes": 0, "reference_writes": 0, "deletions": 0,
    }))


if __name__ == "__main__":
    main()
