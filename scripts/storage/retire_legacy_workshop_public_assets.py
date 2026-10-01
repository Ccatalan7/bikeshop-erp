#!/usr/bin/env python3
"""Close the public exposure of the legacy workshop photos and quote PDFs.

Scope is fixed: the objects under `vinabike-assets/mechanic_jobs/` and
`vinabike-assets/presupuestos/` (8 + 8 at the 2026-09-30 inventory). Nothing is
lost: before any public deletion every object has a byte-identical private
copy that is re-read and compared.

- A photo with an exact job owner already has its private copy and receipt
  (`copy_legacy_workshop_assets.py`, table `workshop_legacy_asset_copies`);
  the ERP, portal and PDF read it from there. Its reference is not rewritten.
- An object without an attributed owner (two HEIC photos and the eight chat-era
  quote PDFs) goes to the existing service-only quarantine of unreferenced
  legacy bytes: `messaging-attachment-quarantine/legacy-orphans/<sha256>` with
  its receipt in `messaging_legacy_orphan_quarantine_receipts`, the same path
  the messaging migrator uses. Owner decision, 2026-09-30: quarantine and
  retire, do not keep customer documents public while the owner is unknown.

Then the public objects are deleted through the Storage API and the result is
read back (catalog, public URL, private bytes, receipts). Credentials stay in
memory; the receipt file holds no credentials. All SQL goes through
`scripts/db/query.sh`. Without --execute it only plans and writes the receipt.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import sys
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.dont_write_bytecode = True

import copy_legacy_workshop_assets as copier  # noqa: E402

PUBLIC_BUCKET = "vinabike-assets"
COPY_BUCKET = copier.BUCKET
QUARANTINE_BUCKET = "messaging-attachment-quarantine"
PREFIXES = ("mechanic_jobs", "presupuestos")
EXPECTED = {"mechanic_jobs": 8, "presupuestos": 8}
EXPECTED_ATTRIBUTED = 6
MAX_BYTES = 20 * 1024 * 1024
PATH_HASH_PREFIX = "vinabike-public-orphan-path-v1:"


def inventory(environment):
    return copier.query(environment, f"""
      select o.name as source_path,
        (o.metadata->>'size')::bigint as size_bytes,
        coalesce(nullif(o.metadata->>'mimetype', ''), 'application/octet-stream') as mime_type,
        o.created_at::text as created_at, o.updated_at::text as updated_at,
        c.storage_path as copy_path, c.private_sha256 as copy_sha256,
        c.private_size_bytes as copy_size_bytes, p.id is not null as copy_present
      from storage.objects o
      left join public.workshop_legacy_asset_copies c
        on c.source_bucket = {copier.sql_value(PUBLIC_BUCKET)} and c.source_path = o.name
        and c.verified_at is not null and c.private_sha256 = c.source_sha256
      left join storage.objects p
        on p.bucket_id = {copier.sql_value(COPY_BUCKET)} and p.name = c.storage_path
      where o.bucket_id = {copier.sql_value(PUBLIC_BUCKET)}
        and split_part(o.name, '/', 1) in ('mechanic_jobs', 'presupuestos')
      order by o.name
    """)


def plan(rows):
    counts = {prefix: 0 for prefix in PREFIXES}
    result = []
    for row in rows:
        counts[row["source_path"].split("/")[0]] += 1
        if not 0 < int(row["size_bytes"]) <= MAX_BYTES:
            raise ValueError("Un objeto está vacío o supera el límite revisado.")
        attributed = row["copy_path"] is not None
        if attributed and not (row["copy_present"]
                               and int(row["copy_size_bytes"]) == int(row["size_bytes"])):
            raise ValueError("Una foto atribuida no tiene su copia privada presente.")
        result.append({
            "source_path": row["source_path"],
            "size_bytes": int(row["size_bytes"]),
            "mime_type": row["mime_type"],
            "created_at": row["created_at"],
            "updated_at": row["updated_at"],
            "destination": "copia_privada" if attributed else "cuarentena",
            "copy_path": row["copy_path"],
            "copy_sha256": row["copy_sha256"],
            "source_path_sha256": hashlib.sha256(
                (PATH_HASH_PREFIX + row["source_path"]).encode()).hexdigest(),
        })
    attributed = sum(row["destination"] == "copia_privada" for row in result)
    if counts != EXPECTED or attributed != EXPECTED_ATTRIBUTED:
        raise ValueError("El inventario cambió desde la revisión; no se retira nada.")
    return result


def storage_url(origin, bucket, path, authenticated=True):
    quoted = urllib.parse.quote(path, safe="/")
    kind = "authenticated" if authenticated else "public"
    return f"{origin}/storage/v1/object/{kind}/{bucket}/{quoted}"


def download(origin, key, bucket, path):
    req = urllib.request.Request(storage_url(origin, bucket, path),
                                 headers={"apikey": key, "Authorization": "Bearer " + key})
    try:
        with urllib.request.build_opener(copier.NoRedirect()).open(req, timeout=60) as response:
            body = response.read(MAX_BYTES + 1)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"Storage no entregó el objeto (HTTP {error.code}).") from None
    if len(body) > MAX_BYTES:
        raise RuntimeError("El objeto superó el límite revisado.")
    return body


def public_status(origin, path):
    req = urllib.request.Request(storage_url(origin, PUBLIC_BUCKET, path, authenticated=False))
    try:
        with urllib.request.build_opener(copier.NoRedirect()).open(req, timeout=30) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code


def upload_quarantine(origin, key, path, data, mime):
    req = urllib.request.Request(
        f"{origin}/storage/v1/object/{QUARANTINE_BUCKET}/{urllib.parse.quote(path, safe='/')}",
        data=data, method="POST",
        headers={"apikey": key, "Authorization": "Bearer " + key,
                 "Content-Type": mime, "x-upsert": "false"})
    try:
        with urllib.request.build_opener(copier.NoRedirect()).open(req, timeout=60):
            return "subido"
    except urllib.error.HTTPError as error:
        # The hash-addressed object may already exist from a retry: its bytes
        # are re-read and compared by the caller, never replaced.
        if error.code in (400, 409):
            return "ya_presente"
        raise RuntimeError(f"Storage rechazó la cuarentena (HTTP {error.code}).") from None


def delete_public(origin, key, paths):
    req = urllib.request.Request(
        f"{origin}/storage/v1/object/{PUBLIC_BUCKET}", method="DELETE",
        data=json.dumps({"prefixes": paths}).encode(),
        headers={"apikey": key, "Authorization": "Bearer " + key,
                 "Content-Type": "application/json"})
    try:
        with urllib.request.build_opener(copier.NoRedirect()).open(req, timeout=60) as response:
            return len(json.loads(response.read() or b"[]"))
    except urllib.error.HTTPError:
        # A delete may commit and lose its acknowledgement; the catalog
        # readback below decides.
        return None


def same(data, size, sha):
    return len(data) == size and hashlib.sha256(data).hexdigest() == sha


def finalize_quarantine(environment, row):
    copier.query(environment, f"""
      begin;
      select public.finalize_legacy_messaging_orphan_quarantine(
        {copier.sql_value(row['source_path_sha256'])},
        {copier.sql_value(row['sha256'])},
        {row['size_bytes']},
        {copier.sql_value(row['created_at'])}::timestamptz);
      commit;
    """, write=True)


def mark_deleted(environment, row):
    copier.query(environment, f"""
      begin;
      select public.mark_legacy_messaging_orphan_public_deleted(
        {copier.sql_value(row['source_path_sha256'])},
        {copier.sql_value(row['sha256'])});
      commit;
    """, write=True)


def readback(environment, rows):
    names = ", ".join(copier.sql_value(row["source_path"]) for row in rows)
    hashes = ", ".join(copier.sql_value(row["source_path_sha256"]) for row in rows
                       if row["destination"] == "cuarentena")
    return copier.query(environment, f"""
      select
        (select count(*) from storage.objects
          where bucket_id = {copier.sql_value(PUBLIC_BUCKET)} and name in ({names}))
          as publicos_restantes,
        (select count(*) from public.workshop_legacy_asset_copies c
          join storage.objects p on p.bucket_id = {copier.sql_value(COPY_BUCKET)}
            and p.name = c.storage_path
          where c.source_path in ({names}) and c.verified_at is not null)
          as copias_privadas_presentes,
        (select count(*) from public.messaging_legacy_orphan_quarantine_receipts r
          join storage.objects q on q.bucket_id = r.quarantine_bucket
            and q.name = r.quarantine_path
            and (q.metadata->>'size')::bigint = r.size_bytes
          where r.source_path_sha256 in ({hashes}))
          as cuarentenas_presentes,
        (select count(*) from public.messaging_legacy_orphan_quarantine_receipts r
          where r.source_path_sha256 in ({hashes})
            and r.deleted_from_public_at is not null)
          as cuarentenas_marcadas_retiradas
    """)[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--environment", choices=("production",), required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--expected-plan-sha256")
    args = parser.parse_args()
    os.umask(0o077)
    origin = copier.PRODUCTION_ORIGIN
    rows = plan(inventory(args.environment))
    fingerprint = hashlib.sha256(json.dumps(rows, sort_keys=True).encode()).hexdigest()
    summary = {"environment": args.environment, "plan_sha256": fingerprint,
               "executed": args.execute, "objects": len(rows),
               "copia_privada": sum(r["destination"] == "copia_privada" for r in rows),
               "cuarentena": sum(r["destination"] == "cuarentena" for r in rows)}

    def save(extra=None):
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps({**summary, **(extra or {}), "rows": rows},
                                          indent=2) + "\n")
        args.output.chmod(0o600)

    save()
    if not args.execute:
        print(json.dumps(summary))
        return
    if (args.expected_plan_sha256 != fingerprint
            or os.environ.get("VINABIKE_STORAGE_COPY_CONFIRM") != args.environment
            or os.environ.get("VINABIKE_DB_WRITE_CONFIRM") != "production"):
        raise RuntimeError("Falta el plan revisado o el marcador de escritura productiva.")
    key = copier.credentials(args.environment, origin)

    # 1. Every object gets a verified private twin before anything is deleted.
    for row in rows:
        data = download(origin, key, PUBLIC_BUCKET, row["source_path"])
        if len(data) != row["size_bytes"]:
            raise RuntimeError("El tamaño público difiere del catálogo; no se retira nada.")
        row["sha256"] = hashlib.sha256(data).hexdigest()
        if row["destination"] == "copia_privada":
            if row["sha256"] != row["copy_sha256"]:
                raise RuntimeError("El original difiere de su copia privada registrada.")
            if not same(download(origin, key, COPY_BUCKET, row["copy_path"]),
                        row["size_bytes"], row["sha256"]):
                raise RuntimeError("La copia privada no coincide byte a byte.")
        else:
            row["quarantine_path"] = "legacy-orphans/" + row["sha256"]
            row["quarantine_upload"] = upload_quarantine(
                origin, key, row["quarantine_path"], data, row["mime_type"])
            if not same(download(origin, key, QUARANTINE_BUCKET, row["quarantine_path"]),
                        row["size_bytes"], row["sha256"]):
                raise RuntimeError("La cuarentena no coincide byte a byte.")
            finalize_quarantine(args.environment, row)
        row["private_twin_verified"] = True
        save()

    # 2. Bytes may not change between the twin check and the delete.
    for row in rows:
        if not same(download(origin, key, PUBLIC_BUCKET, row["source_path"]),
                    row["size_bytes"], row["sha256"]):
            raise RuntimeError("Un original cambió antes del retiro; no se retira nada.")
    acknowledged = delete_public(origin, key, [row["source_path"] for row in rows])

    # 3. Read back: catalog, receipts, private bytes and the public URL. A
    # quarantine receipt is marked retired only once the catalog says so.
    names = ", ".join(copier.sql_value(row["source_path"]) for row in rows)
    remaining = {item["name"] for item in copier.query(args.environment, f"""
      select name from storage.objects
      where bucket_id = {copier.sql_value(PUBLIC_BUCKET)} and name in ({names})
    """)}
    for row in rows:
        if row["destination"] == "cuarentena" and row["source_path"] not in remaining:
            mark_deleted(args.environment, row)
    result = readback(args.environment, rows)
    statuses = [public_status(origin, row["source_path"]) for row in rows]
    for row, status in zip(rows, statuses):
        row["public_http_after"] = status
    final = {
        "delete_acknowledged": acknowledged,
        "retired_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        **{k: int(v) for k, v in result.items()},
        "public_url_still_200": sum(status == 200 for status in statuses),
    }
    save(final)
    print(json.dumps({**summary, **final}))
    if (final["publicos_restantes"] != 0
            or final["copias_privadas_presentes"] != EXPECTED_ATTRIBUTED
            or final["cuarentenas_presentes"] != len(rows) - EXPECTED_ATTRIBUTED
            or final["cuarentenas_marcadas_retiradas"] != len(rows) - EXPECTED_ATTRIBUTED):
        raise SystemExit("El readback del retiro no cuadra.")


if __name__ == "__main__":
    main()
