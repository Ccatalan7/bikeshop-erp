#!/usr/bin/env python3
"""Copy only inventoried photos with an exact live workshop owner.

The source reference stays stable. No public object is deleted, no job URL is
rewritten, and objects without an exact job owner are never assigned here.
Credentials stay in memory; receipts are private and contain no credentials.
All SQL goes through the repository's guarded query wrapper.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[2]
PRODUCTION_ORIGIN = "https://xzdvtzdqjeyqxnkqprtf.supabase.co"
BUCKET = "workshop-legacy-private"
PUBLIC_PREFIX = "/storage/v1/object/public/vinabike-assets/"
MAX_BYTES = 20 * 1024 * 1024
MAX_TOTAL = 32 * 1024 * 1024


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise RuntimeError("Storage redirigió la solicitud; se detuvo la copia.")


def sql_value(value):
    return "'" + str(value).replace("'", "''") + "'"


def canonical_id(value):
    return str(uuid.UUID(value))


def query(environment, sql, write=False):
    folder = ROOT / ".tmp/db"
    folder.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", suffix=".sql", dir=folder,
                                     prefix="c3-copy-", delete=False) as source:
        path = Path(source.name)
        os.chmod(path, 0o600)
        source.write(sql)
    try:
        command = [str(ROOT / "scripts/db/query.sh"), environment,
                   "--file", str(path)]
        if write:
            command.append("--write")
        else:
            command += ["--format", "json"]
        process = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        if process.returncode:
            raise RuntimeError("El wrapper rechazó el alcance o recibo de copia.")
        if write:
            return None
        start = re.search(r"(?m)^\[", process.stdout)
        if start is None:
            raise RuntimeError("El wrapper no devolvió el readback JSON esperado.")
        result, _ = json.JSONDecoder().raw_decode(process.stdout[start.start():])
        return result
    finally:
        path.unlink(missing_ok=True)


def plan(manifest, receipts, origin):
    by_path = {item["source_path"]: item for item in manifest}
    result = []
    for receipt in receipts:
        references = receipt["exact_job_references"]
        if not references:
            continue
        if len(references) != 1:
            raise ValueError("Una foto tiene más de un dueño; requiere revisión.")
        source_path = receipt["source_path"]
        item = by_path[source_path]
        exact = item["exact_job_references"]
        if len(exact) != 1:
            raise ValueError("El manifiesto y el recibo no concuerdan.")
        owner = references[0]
        for key in ("tenant_id", "job_id", "customer_id"):
            if canonical_id(owner[key]) != canonical_id(exact[0][key]):
                raise ValueError("El dueño cambió entre manifiesto y recibo.")
        reference = exact[0]["reference"]
        uri = urllib.parse.urlsplit(reference)
        expected = urllib.parse.urlsplit(origin)
        if (uri.scheme != expected.scheme or uri.netloc != expected.netloc
                or uri.query or uri.fragment
                or urllib.parse.unquote(uri.path) != PUBLIC_PREFIX + source_path):
            raise ValueError("La referencia sale del proyecto y objeto revisados.")
        name = source_path.split("/")[-1]
        if (source_path != "mechanic_jobs/" + owner["customer_id"] + "/" + name
                or not re.fullmatch(r"[A-Za-z0-9_.-]+\.(?:jpg|jpeg|png)", name, re.I)):
            raise ValueError("El objeto no es una foto revisada con dueño exacto.")
        if (receipt["source_bucket"] != "vinabike-assets"
                or not 0 < receipt["observed_bytes"] <= MAX_BYTES
                or not re.fullmatch(r"[0-9a-f]{64}", receipt["sha256"])):
            raise ValueError("El recibo de bytes no permite copiar el objeto.")
        copy_id = str(uuid.uuid5(uuid.NAMESPACE_URL, reference + "#" + owner["job_id"]))
        result.append({
            "id": copy_id, **owner, "source_reference": reference,
            "source_path": source_path, "file_name": name,
            "storage_path": "/".join((owner["tenant_id"], owner["job_id"], copy_id, name)),
            "size_bytes": receipt["observed_bytes"], "sha256": receipt["sha256"],
            "mime_type": receipt["content_type"],
            "source_updated_at": item["updated_at"],
        })
    if not result or len(result) > 6 or sum(row["size_bytes"] for row in result) > MAX_TOTAL:
        raise ValueError("El alcance debe ser las seis fotos ya revisadas o un subconjunto.")
    return sorted(result, key=lambda row: row["source_path"])


def current_scope(environment, row):
    selected = query(environment, f"""
      select object.id::text as object_id
      from public.mechanic_jobs job
      join public.customers customer on customer.id = job.customer_id
        and customer.tenant_id = job.tenant_id
      join storage.objects object on object.bucket_id = 'vinabike-assets'
        and object.name = {sql_value(row['source_path'])}
      where job.id = {sql_value(row['job_id'])}::uuid
        and job.tenant_id = {sql_value(row['tenant_id'])}::uuid
        and customer.id = {sql_value(row['customer_id'])}::uuid
        and {sql_value(row['source_reference'])} = any(coalesce(job.image_urls, '{{}}'::text[]))
        and object.updated_at = {sql_value(row['source_updated_at'])}::timestamptz
        and (object.metadata->>'size')::bigint = {row['size_bytes']}
    """)
    if len(selected) != 1:
        raise RuntimeError("El archivo, vínculo o dueño cambió; la copia se detuvo.")


def credentials(environment, origin):
    if environment == "production":
        key = os.environ.get("SUPABASE_SECRET_KEY")
        if not key:
            found = subprocess.run(
                ["security", "find-generic-password", "-s",
                 "Vinabike ERP Supabase secret key", "-a", "supabase", "-w"],
                capture_output=True, text=True)
            key = found.stdout.strip() if found.returncode == 0 else None
    else:
        status = subprocess.run([str(ROOT / "scripts/supabase_cli.sh"), "status", "-o", "env"],
                                cwd=ROOT, capture_output=True, text=True)
        if status.returncode:
            raise RuntimeError("El stack local no está disponible.")
        values = dict(re.findall(r'^([A-Z_]+)="?([^"\n]+)"?$', status.stdout, re.M))
        if values.get("API_URL", "").rstrip("/") != origin:
            raise RuntimeError("La API local no corresponde al origen revisado.")
        key = values.get("SERVICE_ROLE_KEY") or values.get("SECRET_KEY")
    if not key:
        raise RuntimeError("No está disponible la credencial de Storage.")
    return key


def request(origin, path, key=None, data=None, mime=None, allow_conflict=False):
    headers = {}
    if key:
        headers = {"apikey": key, "Authorization": "Bearer " + key}
    if data is not None:
        headers.update({"Content-Type": mime, "x-upsert": "false"})
    req = urllib.request.Request(origin + path, headers=headers, data=data,
                                 method="POST" if data is not None else "GET")
    try:
        with urllib.request.build_opener(NoRedirect()).open(req, timeout=30) as response:
            if response.status not in (200, 201):
                raise RuntimeError("Storage no confirmó el objeto esperado.")
            body = response.read(MAX_BYTES + 1)
            if len(body) > MAX_BYTES:
                raise RuntimeError("El objeto superó el límite revisado.")
            return body
    except urllib.error.HTTPError as error:
        # A retry may find the exact deterministic path. Its bytes are always
        # re-read and compared; conflict is never an authorization to replace.
        if allow_conflict and error.code in (400, 409):
            return None
        raise RuntimeError(f"Storage rechazó la solicitud (HTTP {error.code}).") from None


def check_bytes(data, row):
    if (len(data) != row["size_bytes"]
            or hashlib.sha256(data).hexdigest() != row["sha256"]):
        raise RuntimeError("Los bytes difieren del recibo revisado; no se registra la copia.")


def register(environment, row, copied_at, verified_at):
    fields = {
        key: row[key] for key in ("id", "tenant_id", "customer_id", "job_id",
                                  "source_path", "source_reference", "storage_path",
                                  "file_name", "mime_type")
    }
    fields.update({
        "source_bucket": "vinabike-assets",
        "source_size_bytes": row["size_bytes"], "private_size_bytes": row["size_bytes"],
        "source_sha256": row["sha256"], "private_sha256": row["sha256"],
        "copied_at": copied_at, "verified_at": verified_at,
    })
    payload = sql_value(json.dumps(fields))
    query(environment, f"""
      begin;
      select 1 from public.mechanic_jobs where id = {sql_value(row['job_id'])}::uuid
        for update;
      insert into public.workshop_legacy_asset_copies
      select (jsonb_populate_record(null::public.workshop_legacy_asset_copies,
        {payload}::jsonb)).*
      on conflict (id) do nothing;
      select 1 / (case when exists (
        select 1 from public.workshop_legacy_asset_copies
        where id = {sql_value(row['id'])}::uuid
          and source_reference = {sql_value(row['source_reference'])}
          and storage_path = {sql_value(row['storage_path'])}
          and job_id = {sql_value(row['job_id'])}::uuid
          and tenant_id = {sql_value(row['tenant_id'])}::uuid
          and customer_id = {sql_value(row['customer_id'])}::uuid
          and private_sha256 = {sql_value(row['sha256'])}
          and private_size_bytes = {row['size_bytes']}
      ) then 1 else 0 end) as recibo_exacto;
      commit;
    """, write=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--environment", choices=("local", "production"), required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--receipts", type=Path, required=True)
    parser.add_argument("--origin", default=PRODUCTION_ORIGIN)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--expected-plan-sha256")
    args = parser.parse_args()
    os.umask(0o077)
    origin = args.origin.rstrip("/")
    uri = urllib.parse.urlsplit(origin)
    if ((args.environment == "production" and origin != PRODUCTION_ORIGIN)
            or (args.environment == "local"
                and (uri.scheme != "http" or uri.hostname not in ("localhost", "127.0.0.1")
                     or uri.path or uri.query or uri.fragment))):
        raise ValueError("El destino no es el proyecto o stack local autorizado.")
    rows = plan(json.loads(args.manifest.read_text()), json.loads(args.receipts.read_text()), origin)
    fingerprint = hashlib.sha256(json.dumps(rows, sort_keys=True).encode()).hexdigest()
    for row in rows:
        current_scope(args.environment, row)
    def save_receipt():
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps({
            "environment": args.environment, "plan_sha256": fingerprint,
            "copies_verified": sum(bool(row.get("copy_verified")) for row in rows),
            "reference_writes": 0, "public_deletions": 0, "objects": rows,
        }, indent=2) + "\n")
        args.output.chmod(0o600)
    save_receipt()
    if args.execute:
        if (args.expected_plan_sha256 != fingerprint
                or os.environ.get("VINABIKE_STORAGE_COPY_CONFIRM") != args.environment
                or (args.environment == "production"
                    and os.environ.get("VINABIKE_DB_WRITE_CONFIRM") != "production")):
            raise RuntimeError("Falta el alcance revisado o el marcador de copia exacta.")
        key = credentials(args.environment, origin)
        for row in rows:
            public_path = PUBLIC_PREFIX + urllib.parse.quote(row["source_path"], safe="/")
            original = request(origin, public_path)
            check_bytes(original, row)
            copied_at = datetime.datetime.now(datetime.timezone.utc).isoformat()
            private_path = "/storage/v1/object/" + BUCKET + "/" + urllib.parse.quote(
                row["storage_path"], safe="/")
            request(origin, private_path, key, original, row["mime_type"], allow_conflict=True)
            copied = request(origin, private_path, key)
            check_bytes(copied, row)
            # Re-check the public bytes and current owner after copying.
            check_bytes(request(origin, public_path), row)
            current_scope(args.environment, row)
            register(args.environment, row, copied_at,
                     datetime.datetime.now(datetime.timezone.utc).isoformat())
            row["copy_verified"] = True
            save_receipt()
    print(json.dumps({"environment": args.environment, "objects": len(rows),
                      "plan_sha256": fingerprint, "executed": args.execute,
                      "reference_writes": 0, "public_deletions": 0}))


if __name__ == "__main__":
    main()
