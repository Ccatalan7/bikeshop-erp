#!/usr/bin/env python3
"""C3 real: copy one synthetic photo, read it as staff/customer, deny outsiders.

Uses existing local Auth/PostgREST/Storage services. Never starts/replaces them
and refuses hosted origins. --hold keeps the exact fixture for app verification;
--release retires only the IDs/paths recorded by this run.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "c3copy", ROOT / "scripts/storage/copy_legacy_workshop_assets.py")
c3 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c3)


def api(origin, path, key, data=None, method=None, bearer=None, raw=False):
    headers = {"apikey": key}
    if bearer:
        headers["Authorization"] = "Bearer " + bearer
    payload = data
    if data is not None and not isinstance(data, bytes):
        payload = json.dumps(data).encode()
        headers["Content-Type"] = "application/json"
    elif isinstance(data, bytes):
        headers["Content-Type"] = "image/png"
        headers["x-upsert"] = "false"
    request = urllib.request.Request(origin + path, data=payload, headers=headers,
                                    method=method or ("POST" if data is not None else "GET"))
    try:
        with urllib.request.build_opener(c3.NoRedirect()).open(request, timeout=30) as response:
            body = response.read(c3.MAX_BYTES + 1)
            return response.status, body if raw else (json.loads(body) if body else {})
    except urllib.error.HTTPError as error:
        body = error.read()
        if raw:
            return error.code, body
        try:
            return error.code, json.loads(body)
        except (ValueError, UnicodeDecodeError):
            return error.code, {}


def status():
    process = subprocess.run([str(ROOT / "scripts/supabase_cli.sh"), "status", "-o", "env"],
                             cwd=ROOT, capture_output=True, text=True)
    if process.returncode:
        raise RuntimeError("El stack local no responde; no se reinicia desde este gate.")
    import re
    values = dict(re.findall(r'^([A-Z_]+)="?([^"\n]+)"?$', process.stdout, re.M))
    origin = values.get("API_URL", "").rstrip("/")
    from urllib.parse import urlsplit
    if urlsplit(origin).hostname not in ("localhost", "127.0.0.1"):
        raise RuntimeError("El destino no es local.")
    return origin, values.get("ANON_KEY") or values["PUBLISHABLE_KEY"], (
        values.get("SERVICE_ROLE_KEY") or values["SECRET_KEY"])


def setup_sql(state):
    ident = state["ids"]
    quote = c3.sql_value
    accounts = state["accounts"]
    return f"""
      begin;
      set local session_replication_role = replica;
      insert into public.tenants(id,shop_name,is_active,subdomain) values
        ({quote(ident['tenant'])}, 'C3 Taller privado', true, 'c3-privado'),
        ({quote(ident['foreign_tenant'])}, 'C3 Taller ajeno', true, 'c3-ajeno');
      insert into public.user_profiles(user_id,tenant_id,role) values
        ({quote(accounts[0]['id'])}, {quote(ident['tenant'])}, 'mechanic'),
        ({quote(accounts[2]['id'])}, {quote(ident['foreign_tenant'])}, 'mechanic');
      insert into public.customers(id,tenant_id,name,email,auth_user_id,is_active) values
        ({quote(ident['customer'])}, {quote(ident['tenant'])}, 'Cliente C3 privado',
         {quote(accounts[1]['email'])}, {quote(accounts[1]['id'])}, true);
      insert into public.bikes(id,tenant_id,customer_id,brand,model) values
        ({quote(ident['bike'])}, {quote(ident['tenant'])}, {quote(ident['customer'])},
         'C3', 'Rueda con copia privada');
      insert into public.mechanic_jobs(id,tenant_id,customer_id,bike_id,job_number,
        client_request,status) values
        ({quote(ident['job'])}, {quote(ident['tenant'])}, {quote(ident['customer'])},
         {quote(ident['bike'])}, {quote('C3-' + ident['job'][:8])},
         'Abrir la foto privada de la rueda', 'PENDIENTE');
      commit;
    """


def cleanup(state, origin, admin):
    quote = c3.sql_value
    for bucket, path in (
        ("workshop-legacy-private", state.get("private_path")),
        ("vinabike-assets", state.get("source_path")),
    ):
        if not path:
            continue
        code, _ = api(origin, "/storage/v1/object/" + bucket, admin,
                      {"prefixes": [path]}, method="DELETE", bearer=admin)
        if code not in (200, 404):
            raise RuntimeError("No se pudieron retirar los bytes sintéticos.")
    ids = state["ids"]
    # All identifiers originate in this disposable run. Replica mode prevents
    # teardown itself from firing business events; it never escapes the txn.
    c3.query("local", f"""
      begin;
      set local session_replication_role = replica;
      delete from public.database_backups where tenant_id = {quote(ids['tenant'])};
      delete from public.workshop_legacy_asset_copies where job_id = {quote(ids['job'])};
      delete from public.mechanic_jobs where id = {quote(ids['job'])};
      delete from public.bikes where id = {quote(ids['bike'])};
      delete from public.customers where id = {quote(ids['customer'])};
      delete from public.user_profiles where tenant_id in (
        {quote(ids['tenant'])}, {quote(ids['foreign_tenant'])});
      delete from public.tenants where id in (
        {quote(ids['tenant'])}, {quote(ids['foreign_tenant'])});
      commit;
    """, write=True)
    for account in state["accounts"]:
        code, _ = api(origin, "/auth/v1/admin/users/" + account["id"], admin,
                      method="DELETE", bearer=admin)
        if code not in (200, 204, 404):
            raise RuntimeError("No se pudieron retirar las cuentas sintéticas.")
    rows = c3.query("local", f"""
      select (
        (select count(*) from public.tenants where id in (
          {quote(ids['tenant'])}, {quote(ids['foreign_tenant'])})) +
        (select count(*) from public.mechanic_jobs where id = {quote(ids['job'])}) +
        (select count(*) from storage.objects where (
          bucket_id = 'vinabike-assets' and name = {quote(state.get('source_path',''))})
          or (bucket_id = 'workshop-legacy-private'
            and name = {quote(state.get('private_path',''))}))
      )::int as residues
    """)
    if rows[0]["residues"] != 0:
        raise RuntimeError("El readback de retirada detectó residuos.")
    if state.get("legacy_bucket_created"):
        code, _ = api(origin, "/storage/v1/bucket/vinabike-assets", admin,
                      method="DELETE", bearer=admin)
        if code not in (200, 204, 404):
            raise RuntimeError("El bucket sintético no quedó vacío para retirarlo.")


def recover_receipt(state, origin, anon, admin, state_path):
    """Recover this held run's job and copy through real authenticated RPCs.

    The original synthetic object is removed through Storage, while its
    verified private bytes remain. No hosted destination is accepted.
    """
    quote = c3.sql_value
    ids = state["ids"]
    reference = origin + c3.PUBLIC_PREFIX + state["source_path"]
    c3.query("local", "update public.user_profiles set role = 'admin' where user_id = "
             + quote(state["accounts"][0]["id"]), write=True)
    code, session = api(origin, "/auth/v1/token?grant_type=password", anon, {
        "email": state["accounts"][0]["email"], "password": state["password"],
    })
    if code != 200:
        raise RuntimeError("Auth no confirmó al administrador sintético.")
    token = session["access_token"]
    code, backup = api(origin, "/rest/v1/rpc/create_backup", anon, {
        "p_tenant_id": ids["tenant"], "p_backup_name": "C3 copia y recuperación integrada",
        "p_backup_type": "manual", "p_notes": None,
    }, bearer=token)
    if code != 200 or not backup.get("success"):
        raise RuntimeError("El respaldo real no capturó la fixture.")
    backup_id = backup["backup_id"]
    state["backup_id"] = backup_id
    state_path.write_text(json.dumps(state, indent=2) + "\n")
    state_path.chmod(0o600)
    snapshot = c3.query("local", "select backup_data from public.database_backups where id = "
                        + quote(backup_id))[0]["backup_data"]
    jobs = [row for row in snapshot["mechanic_jobs"] if row["id"] == ids["job"]]
    copies = snapshot.get("workshop_legacy_asset_copies") or []
    if len(jobs) != 1 or len(copies) != 1 or copies[0]["job_id"] != ids["job"]:
        raise RuntimeError("La captura no conservó el trabajo y su recibo exacto.")
    code, _ = api(origin, "/storage/v1/object/vinabike-assets", admin,
                  {"prefixes": [state["source_path"]]}, method="DELETE", bearer=admin)
    if code != 200:
        raise RuntimeError("No se retiró el original sintético del gate local.")
    code, _ = api(origin, c3.PUBLIC_PREFIX + state["source_path"], anon, raw=True)
    if code == 200:
        raise RuntimeError("El original sintético aún está disponible.")
    c3.query("local", f"""
      begin;
      set local session_replication_role = replica;
      delete from public.workshop_legacy_asset_copies where job_id = {quote(ids['job'])};
      delete from public.mechanic_jobs where id = {quote(ids['job'])};
      commit;
    """, write=True)
    arguments = {"p_backup_id": backup_id, "p_tenant_id": ids["tenant"]}
    code, review = api(origin, "/rest/v1/rpc/restore_backup_merge_preflight", anon,
                       arguments, bearer=token)
    if code != 200 or not review.get("can_restore"):
        raise RuntimeError("La revisión real no aceptó recuperar el trabajo y su copia: "
                           + str(review.get("message", "sin informe")))
    missing = c3.query("local", "select count(*) as rows from public.mechanic_jobs where id = "
                       + quote(ids["job"]))[0]["rows"]
    if missing:
        raise RuntimeError("El preflight dejó el trabajo escrito.")
    code, restored = api(origin, "/rest/v1/rpc/restore_backup_merge", anon,
                         arguments, bearer=token)
    if code != 200 or not restored.get("success"):
        raise RuntimeError("La recuperación real no terminó: "
                           + str(restored.get("message", "sin informe")))
    readback = c3.query("local", f"""
      select (select to_jsonb(job) from public.mechanic_jobs job
        where id = {quote(ids['job'])}) as job,
        (select to_jsonb(copy) from public.workshop_legacy_asset_copies copy
          where job_id = {quote(ids['job'])}) as copy,
        (select count(*) from public.workshop_restore_invocations) +
        (select count(*) from public.workshop_restore_effect_packets) as packets
    """)[0]
    if readback["job"] != jobs[0] or readback["copy"] != copies[0] or readback["packets"]:
        raise RuntimeError("La recuperación cambió el trabajo, recibo o dejó paquetes abiertos.")
    for account in state["accounts"][:2]:
        code, actor = api(origin, "/auth/v1/token?grant_type=password", anon, {
            "email": account["email"], "password": state["password"],
        })
        if code != 200:
            raise RuntimeError("Auth no confirmó al lector después de recuperar.")
        code, resolved = api(origin, "/rest/v1/rpc/workshop_legacy_asset_read_v1", anon,
                             {"p_reference": reference}, bearer=actor["access_token"])
        if code != 200 or resolved.get("mode") != "private":
            raise RuntimeError("El trabajo recuperado no abre su foto privada.")
        code, signed = api(origin, "/storage/v1/object/sign/workshop-legacy-private/" +
                           state["private_path"], anon, {"expiresIn": 300},
                           bearer=actor["access_token"])
        if code != 200:
            raise RuntimeError("Storage no autorizó la foto recuperada.")
        code, data = api(origin, "/storage/v1" + signed["signedURL"], anon, raw=True)
        if code != 200 or hashlib.sha256(data).hexdigest() != copies[0]["private_sha256"]:
            raise RuntimeError("Los bytes recuperados no coinciden con el recibo.")
    evidence = {"receipt_captured": 1, "preflight_rollback": 1, "recovery_readback": 1,
                "exact_rows": 2, "public_original_unavailable": 1,
                "staff_and_customer_private_read": 1, "open_packets": 0}
    (state_path.parent / "recovery-readback.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps(evidence))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hold", action="store_true")
    parser.add_argument("--release", type=Path)
    parser.add_argument("--recover", type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    origin, anon, admin = status()
    ready = c3.query("local", "select to_regprocedure("
                    "'public.workshop_legacy_asset_read_v1(text)') is not null as ready")
    if not ready[0]["ready"]:
        raise RuntimeError("El forward C3 debe estar instalado antes del recorrido.")
    if args.release:
        state = json.loads(args.release.read_text())
        if state["origin"] != origin:
            raise RuntimeError("La fixture no pertenece a este stack local.")
        cleanup(state, origin, admin)
        print(json.dumps({"retirada_completa": 1}))
        return
    if args.recover:
        state = json.loads(args.recover.read_text())
        if state["origin"] != origin:
            raise RuntimeError("La fixture no pertenece a este stack local.")
        recover_receipt(state, origin, anon, admin, args.recover)
        return
    folder = ROOT / ".tmp/e2e" / ("workshop-private-files-" +
                                 datetime.now().strftime("%Y%m%d-%H%M%S"))
    folder.mkdir(parents=True, mode=0o700)
    state = {
        "origin": origin, "password": "C3-" + secrets.token_hex(16),
        "ids": {name: str(uuid.uuid4()) for name in
                ("tenant", "foreign_tenant", "customer", "bike", "job")},
        "accounts": [],
    }
    state_path = folder / "local-fixture-private.json"
    def save():
        state_path.write_text(json.dumps(state, indent=2) + "\n")
        state_path.chmod(0o600)
    save()
    passed = False
    try:
        for label in ("staff", "customer", "foreign"):
            email = "c3-" + label + "-" + state["ids"]["tenant"][:8] + "@vinabike.invalid"
            code, account = api(origin, "/auth/v1/admin/users", admin, {
                "email": email, "password": state["password"], "email_confirm": True,
            }, bearer=admin)
            if code not in (200, 201) or "id" not in account:
                raise RuntimeError("Auth no pudo crear la cuenta sintética.")
            state["accounts"].append({"id": account["id"], "email": email})
            save()
        c3.query("local", setup_sql(state), write=True)
        code, bucket_status = api(origin, "/storage/v1/bucket/vinabike-assets", admin,
                      bearer=admin)
        if code == 404 or (code == 400 and
                          str(bucket_status.get("statusCode")) == "404"):
            code, _ = api(origin, "/storage/v1/bucket", admin, {
                "id": "vinabike-assets", "name": "vinabike-assets",
                "public": True, "file_size_limit": c3.MAX_BYTES,
            }, bearer=admin)
            if code not in (200, 201):
                raise RuntimeError(f"Storage no creó el bucket local (HTTP {code}).")
            state["legacy_bucket_created"] = True
            save()
        elif code != 200:
            raise RuntimeError(f"Storage no respondió sobre el bucket (HTTP {code}).")
        data = (ROOT / "assets/images/rear_wheel_exploded.png").read_bytes()
        source_path = "mechanic_jobs/" + state["ids"]["customer"] + "/rueda-trasera.png"
        state["source_path"] = source_path
        reference = origin + c3.PUBLIC_PREFIX + source_path
        save()
        code, _ = api(origin, "/storage/v1/object/vinabike-assets/" + source_path,
                      admin, data, bearer=admin)
        if code not in (200, 201):
            raise RuntimeError(f"Storage no pudo subir la foto sintética (HTTP {code}).")
        c3.query("local", f"update public.mechanic_jobs set image_urls = array["
                 + c3.sql_value(reference) + "] where id = "
                 + c3.sql_value(state["ids"]["job"]), write=True)
        metadata = c3.query("local", "select id::text as object_id, updated_at::text as updated_at"
                           " from storage.objects where bucket_id = 'vinabike-assets' and name = "
                           + c3.sql_value(source_path))[0]
        owner = {key: state["ids"][short] for key, short in
                 (("tenant_id","tenant"), ("customer_id","customer"), ("job_id","job"))}
        manifest = [{
            **metadata, "source_path": source_path,
            "exact_job_references": [{**owner, "reference": reference}],
        }]
        receipts = [{
            "source_path": source_path, "source_bucket": "vinabike-assets",
            "exact_job_references": [owner], "observed_bytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest(), "content_type": "image/png",
        }]
        rows = c3.plan(manifest, receipts, origin)
        row = rows[0]
        state["private_path"] = row["storage_path"]
        save()
        c3.current_scope("local", row)
        c3.check_bytes(c3.request(origin, c3.PUBLIC_PREFIX + source_path), row)
        c3.request(origin, "/storage/v1/object/workshop-legacy-private/" +
                   row["storage_path"], admin, data, "image/png")
        c3.check_bytes(c3.request(origin, "/storage/v1/object/workshop-legacy-private/" +
                                 row["storage_path"], admin), row)
        moment = datetime.now(timezone.utc).isoformat()
        c3.register("local", row, moment, moment)
        for index, expected in ((0, "private"), (1, "private"), (2, "denied")):
            code, session = api(origin, "/auth/v1/token?grant_type=password", anon, {
                "email": state["accounts"][index]["email"], "password": state["password"],
            })
            if code != 200:
                raise RuntimeError("Auth no confirmó el acceso sintético.")
            token = session["access_token"]
            code, result = api(origin, "/rest/v1/rpc/workshop_legacy_asset_read_v1",
                               anon, {"p_reference": reference}, bearer=token)
            if expected == "denied":
                if code not in (401, 403):
                    raise RuntimeError("Un taller ajeno obtuvo la copia.")
                continue
            if code != 200 or result.get("mode") != expected:
                raise RuntimeError("El dueño no pudo resolver su copia privada.")
            code, signed = api(origin, "/storage/v1/object/sign/workshop-legacy-private/" +
                               row["storage_path"], anon, {"expiresIn": 300}, bearer=token)
            if code != 200:
                raise RuntimeError("Storage no autorizó la lectura privada del dueño.")
            signed_path = "/storage/v1" + signed["signedURL"]
            code, opened = api(origin, signed_path, anon, raw=True)
            if code != 200:
                raise RuntimeError("La URL temporal no abrió la copia privada.")
            c3.check_bytes(opened, row)
            if index == 0:
                # Exercise the provider's DELETE API, which enables its own
                # metadata delete guard. The employee must still be fenced
                # out; reading the exact bytes proves nothing was removed.
                code, _ = api(origin, "/storage/v1/object/workshop-legacy-private",
                              anon, {"prefixes": [row["storage_path"]]},
                              method="DELETE", bearer=token)
                c3.check_bytes(c3.request(origin,
                    "/storage/v1/object/workshop-legacy-private/" +
                    row["storage_path"], admin), row)
        code, _ = api(origin, "/storage/v1/object/public/workshop-legacy-private/" +
                      row["storage_path"], anon, raw=True)
        if code == 200:
            raise RuntimeError("Un anónimo pudo leer la copia por URL pública.")
        passed = True
        evidence = {"readback": 1, "staff_private_read": 1, "customer_private_read": 1,
                    "foreign_denied": 1, "anonymous_public_denied": 1,
                    "staff_private_delete_denied": 1,
                    "bytes_sha256": row["sha256"], "bytes": len(data)}
        (folder / "readback.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print(json.dumps(evidence))
        if args.hold:
            print("Fixture local conservada para app: " + str(state_path))
    finally:
        if not (passed and args.hold):
            cleanup(state, origin, admin)
            print(json.dumps({"retirada_completa": 1}))


if __name__ == "__main__":
    main()
