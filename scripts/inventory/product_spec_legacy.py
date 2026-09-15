#!/usr/bin/env python3
"""Encrypted, read-only recovery copies of the product-specification domain.

Database access is exclusively the repository's guarded query wrapper. This
tool cannot apply a production restore, clear facts, or roll back a database.
Use the bundled workspace Python (cryptography) reported in the recovery guide.

Format 1 copies hold the root product facts. Format 2 adds the component
profiles (identity, binding, archived state) and their event history, owning
the facts stored under `member:<profile id>` in the same snapshot. Both are
read, verified, exported and viewed by this same tool.
"""

import argparse
import datetime as dt
import getpass
import hashlib
import html
import io
import json
import os
from pathlib import Path
import secrets
import shlex
import subprocess
import sys
import tarfile
import tempfile
import webbrowser
import zipfile

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

ROOT = Path(__file__).resolve().parents[2]
PROJECT = "xzdvtzdqjeyqxnkqprtf"
MAGIC = b"VBSPEC01"
KEY_SERVICE = "Vinabike ERP product specs legacy backup v1"
SCOPE = "vinabike_product_specs_pre_fill"
SQL = ROOT / "scripts/inventory/product_spec_legacy_export.sql"
DEFAULT_DESTINATION = Path.home() / "Vinabike Backups" / "Product Specs Legacy"
DATA_TABLES = (
    "products", "product_categories", "category_tech_mappings",
    "spec_definitions", "spec_definition_values", "spec_templates",
    "spec_template_fields", "spec_facts", "spec_fact_values", "spec_fact_readings",
    "product_spec_values", "product_set_components", "product_spec_references",
    "product_spec_save_receipts",
)
MEMBER_TABLES = ("product_spec_member_profiles", "product_spec_member_profile_events")
# The internal concurrency epoch (spec_member_graph_revisions) is coordination
# state, not recoverable data, and is deliberately not captured.
FORMAT_TABLES = {1: DATA_TABLES, 2: DATA_TABLES + MEMBER_TABLES}
MEMBER_SCOPE = "member:"


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":")).encode()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def command(args, **kwargs):
    # Errors deliberately omit stdout/stderr: neither credentials nor private
    # catalogue content belong in the terminal transcript.
    result = subprocess.run(args, cwd=ROOT, capture_output=True, **kwargs)
    if result.returncode:
        raise RuntimeError(f"{Path(args[0]).name} failed (exit {result.returncode})")
    return result.stdout


def private_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with path.open("xb") as handle:
        os.chmod(path, 0o600)
        handle.write(data)


def key(create=False):
    account = getpass.getuser()
    args = ["/usr/bin/security", "find-generic-password", "-s", KEY_SERVICE,
            "-a", account, "-w"]
    result = subprocess.run(args, capture_output=True)
    if result.returncode == 44 and create:
        candidate = secrets.token_hex(32)
        # security's interactive input keeps the key out of process argv and
        # tool logs. No -U: an existing key is never overwritten or rotated.
        request = "add-generic-password -s {} -a {} -w {}\n".format(
            shlex.quote(KEY_SERVICE), shlex.quote(account), candidate)
        command(["/usr/bin/security", "-i"], input=request.encode())
        result = subprocess.run(args, capture_output=True)
    if result.returncode:
        raise RuntimeError("Backup key is unavailable in the macOS Keychain")
    try:
        value = bytes.fromhex(result.stdout.decode().strip())
        if len(value) != 32:
            raise ValueError()
        return value
    except ValueError as error:
        raise RuntimeError("Backup key has an unexpected format") from error


def validate_member_graph(tables, tenant_id):
    """Every component profile owns its scope, and every scoped fact has an
    owner. Archived profiles keep their facts; nothing here re-derives them."""
    profiles = {}
    for row in tables["product_spec_member_profiles"]:
        if row.get("tenant_id") != tenant_id:
            raise ValueError("Foreign tenant in product_spec_member_profiles")
        if row.get("scope") != MEMBER_SCOPE + str(row["id"]):
            raise ValueError("Profile scope mismatch")
        archived = row.get("archived_at") is not None
        if archived == (row.get("active_template_guard") is True):
            raise ValueError("Archived state mismatch")
        if not isinstance(row.get("member_identity"), dict) or \
                not isinstance(row.get("identity_sources"), list):
            raise ValueError("Profile identity is not an object with sources")
        profiles[row["id"]] = row
    active_rows = set()
    for row in profiles.values():
        if row.get("archived_at") is not None:
            continue
        binding = (row["product_id"], row["collection_definition_id"], row["member_row_id"])
        if binding in active_rows:
            raise ValueError("Duplicate active profile row")
        active_rows.add(binding)
    for row in tables["product_spec_member_profile_events"]:
        owner = profiles.get(row.get("profile_id"))
        if owner is None or row.get("product_id") != owner["product_id"] or \
                row.get("tenant_id") != owner["tenant_id"]:
            raise ValueError("Broken reference: product_spec_member_profile_events.profile_id -> product_spec_member_profiles")
        if not isinstance(row.get("after_state"), dict) or \
                not isinstance(row.get("before_state"), (dict, type(None))):
            raise ValueError("Profile event without row images")
    for fact in tables["spec_facts"]:
        scope = fact.get("subject_scope")
        if scope is None:
            continue
        owner = profiles.get(scope[len(MEMBER_SCOPE):]) if scope.startswith(MEMBER_SCOPE) else None
        if owner is None or owner["product_id"] != fact["subject_id"] or \
                owner["tenant_id"] != fact.get("tenant_id"):
            raise ValueError("Member fact without owner profile")


def validate_snapshot(snapshot):
    version = snapshot.get("format_version")
    if version not in FORMAT_TABLES or snapshot.get("scope") != SCOPE:
        raise ValueError("Unsupported snapshot format or scope")
    tenant = snapshot.get("tenant") or {}
    if tenant.get("subdomain") != "vinabike" or not tenant.get("id"):
        raise ValueError("Missing or unexpected tenant")
    tables = snapshot["tables"]
    if set(tables) != set(FORMAT_TABLES[version]):
        raise ValueError("Recovery table set is incomplete")
    for name, rows in tables.items():
        if not isinstance(rows, list):
            raise ValueError(f"Invalid rows: {name}")
        ids = [row["id"] for row in rows if "id" in row]
        if len(ids) != len(set(ids)):
            raise ValueError(f"Duplicate IDs: {name}")
        if any(row.get("tenant_id") not in (None, tenant["id"]) for row in rows):
            raise ValueError(f"Foreign tenant in {name}")
    indexed = {name: {row["id"]: row for row in rows if "id" in row}
               for name, rows in tables.items()}
    relations = [
        ("spec_facts", "subject_id", "products"),
        ("spec_facts", "spec_definition_id", "spec_definitions"),
        ("spec_fact_values", "fact_id", "spec_facts"),
        ("spec_fact_values", "value_id", "spec_definition_values"),
        ("spec_fact_readings", "fact_id", "spec_facts"),
        ("spec_definition_values", "spec_definition_id", "spec_definitions"),
        ("spec_template_fields", "template_id", "spec_templates"),
        ("spec_template_fields", "spec_definition_id", "spec_definitions"),
        ("category_tech_mappings", "category_id", "product_categories"),
        ("category_tech_mappings", "template_id", "spec_templates"),
        ("product_spec_values", "product_id", "products"),
        ("product_spec_values", "spec_definition_id", "spec_definitions"),
        ("products", "category_id", "product_categories"),
        ("products", "spec_reference_id", "product_spec_references"),
        ("products", "spec_template_id", "spec_templates"),
        ("product_set_components", "set_product_id", "products"),
        ("product_set_components", "component_product_id", "products"),
    ]
    if version == 2:
        relations += [
            ("product_spec_member_profiles", "product_id", "products"),
            ("product_spec_member_profiles", "collection_definition_id", "spec_definitions"),
            ("product_spec_member_profiles", "template_id", "spec_templates"),
            ("product_spec_member_profiles", "reference_id", "product_spec_references"),
            ("product_spec_member_profile_events", "profile_id", "product_spec_member_profiles"),
            ("product_spec_member_profile_events", "product_id", "products"),
        ]
    for table, field, target in relations:
        if any(row.get(field) is not None and row[field] not in indexed[target]
               for row in tables[table]):
            raise ValueError(f"Broken reference: {table}.{field} -> {target}")
    if not tables["products"] or not tables["spec_templates"]:
        raise ValueError("Empty product or template baseline")
    if len(tables["products"]) != snapshot["operational_fingerprint"]["products"]:
        raise ValueError("Product count does not match independent snapshot count")
    if version == 2:
        validate_member_graph(tables, tenant["id"])
        if len(tables["product_spec_member_profiles"]) != \
                snapshot["operational_fingerprint"]["member_profiles"]:
            raise ValueError("Member profile count does not match independent snapshot count")
    elif any(row.get("subject_scope") is not None for row in tables["spec_facts"]):
        # A format 1 copy has no owner for a component fact: it must not be
        # read as if the fact belonged to the root product.
        raise ValueError("Format 1 cannot carry member facts; use format 2")
    return {name: len(rows) for name, rows in tables.items()}


def validate_manifest(meta, snapshot, counts):
    if meta.get("format_version") != snapshot["format_version"]:
        raise ValueError("Manifest format mismatch")
    if counts != meta["row_counts"]:
        raise ValueError("Manifest count mismatch")


def collect_workspace():
    # Preserve the exact committed baseline plus all current tracked changes
    # and untracked, non-ignored files. Ignored .env/cache/build files stay out.
    base = command(["git", "archive", "--format=tar.gz", "HEAD"])
    changed = command(["git", "diff", "HEAD", "--name-only", "-z"]).split(b"\0")
    untracked = command(["git", "ls-files", "--others", "--exclude-standard", "-z"]).split(b"\0")
    paths = sorted(set(os.fsdecode(p) for p in changed + untracked if p))
    overlay = io.BytesIO()
    deleted, hashes = [], {}
    with tarfile.open(fileobj=overlay, mode="w:gz") as archive:
        for relative in paths:
            path = ROOT / relative
            if not path.exists() and not path.is_symlink():
                deleted.append(relative)
                continue
            if path.is_file() or path.is_symlink():
                info = archive.gettarinfo(str(path), arcname=relative)
                if path.is_symlink():
                    archive.addfile(info)
                    hashes[relative] = sha(os.readlink(path).encode())
                else:
                    data = path.read_bytes()
                    info.size = len(data)
                    archive.addfile(info, io.BytesIO(data))
                    hashes[relative] = sha(data)
    return base, overlay.getvalue(), deleted, hashes


def read_bundle(folder):
    meta = json.loads((folder / "manifest.json").read_text())
    encrypted = (folder / "product-specs.vbspec").read_bytes()
    if sha(encrypted) != meta["encrypted_sha256"] or not encrypted.startswith(MAGIC):
        raise ValueError("Encrypted archive checksum/format mismatch")
    plaintext = AESGCM(key()).decrypt(encrypted[8:20], encrypted[20:], MAGIC)
    if sha(plaintext) != meta["archive_sha256"]:
        raise ValueError("Archive checksum mismatch")
    with zipfile.ZipFile(io.BytesIO(plaintext)) as archive:
        bad = archive.testzip()
        if bad:
            raise ValueError("Corrupt archive member")
        snapshot_bytes = archive.read("snapshot.json")
        if sha(snapshot_bytes) != meta["snapshot_sha256"]:
            raise ValueError("Snapshot checksum mismatch")
        snapshot = json.loads(snapshot_bytes)
        validate_manifest(meta, snapshot, validate_snapshot(snapshot))
        for name, expected in meta["members"].items():
            if sha(archive.read(name)) != expected:
                raise ValueError(f"Archive member checksum mismatch: {name}")
    return meta, snapshot, plaintext


def verify(folder):
    meta, snapshot, _ = read_bundle(folder)
    # Recover every row to a new disposable local directory, then reread and
    # compare every field. This proves data recovery, not a PostgreSQL rollback.
    with tempfile.TemporaryDirectory(prefix="spec-recovery-") as temporary:
        os.chmod(temporary, 0o700)
        for table, rows in snapshot["tables"].items():
            path = Path(temporary) / f"{table}.json"
            private_write(path, canonical(rows))
            if canonical(json.loads(path.read_bytes())) != canonical(rows):
                raise ValueError(f"Recovery roundtrip failed: {table}")
    return {"verified_at": dt.datetime.now(dt.timezone.utc).isoformat(),
            "format_version": snapshot["format_version"],
            "encrypted_sha256": meta["encrypted_sha256"],
            "authenticated_decryption": True, "all_members_sha256": True,
            "row_and_field_roundtrip": True, "references_intact": True,
            "member_scopes_owned": snapshot["format_version"] == 2,
            "production_restore_executed": False, "row_counts": meta["row_counts"]}


def create(destination):
    project = (ROOT / "supabase/.temp/project-ref").read_text().strip()
    if project != PROJECT:
        raise ValueError("Repository is not linked to the approved production project")
    print(f"Read-only backup: production {project}, tenant vinabike", flush=True)
    backup_key = key(create=True)
    raw = command([str(ROOT / "scripts/db/query.sh"), "production", "--file",
                   str(SQL), "--format", "json"])
    records = json.loads(raw)
    if len(records) != 1:
        raise ValueError("Expected exactly one transactional snapshot")
    snapshot = records[0]["snapshot"]
    counts = validate_snapshot(snapshot)
    snapshot_bytes = canonical(snapshot)
    base, overlay, deleted, hashes = collect_workspace()
    source_manifest = {"head": command(["git", "rev-parse", "HEAD"]).decode().strip(),
        "branch": command(["git", "branch", "--show-current"]).decode().strip(),
        "deleted_tracked_paths": deleted, "workspace_overlay_sha256": hashes,
        "scope": "committed repository plus tracked changes and non-ignored untracked files",
        "excluded": ["ignored files", "credentials", "running app state", "provider storage objects"]}
    buffer = io.BytesIO()
    members = {"snapshot.json": snapshot_bytes, "source/HEAD.tar.gz": base,
        "source/workspace-overlay.tar.gz": overlay,
        "source/manifest.json": canonical(source_manifest),
        "recovery-export.sql": SQL.read_bytes(),
        "recovery-tool.py": Path(__file__).read_bytes()}
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in members.items():
            archive.writestr(name, data)
    nonce = secrets.token_bytes(12)
    archive_bytes = buffer.getvalue()
    encrypted = MAGIC + nonce + AESGCM(backup_key).encrypt(nonce, archive_bytes, MAGIC)
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    folder = destination / (stamp + "-pre-fill")
    if ROOT == folder.resolve() or ROOT in folder.resolve().parents:
        raise ValueError("Backups must live outside the repository")
    folder.mkdir(parents=True, mode=0o700)
    os.chmod(destination, 0o700)
    manifest = {"format_version": snapshot["format_version"], "project_ref": project,
        "scope": snapshot["scope"], "captured_at": snapshot["captured_at"],
        "tenant_id": snapshot["tenant"]["id"], "row_counts": counts,
        "physical_products": snapshot["operational_fingerprint"]["physical_products"],
        "member_profiles": snapshot["operational_fingerprint"]["member_profiles"],
        "head": source_manifest["head"], "branch": source_manifest["branch"],
        "snapshot_sha256": sha(snapshot_bytes), "archive_sha256": sha(archive_bytes),
        "encrypted_sha256": sha(encrypted),
        "members": {name: sha(data) for name, data in members.items()},
        "encryption": "AES-256-GCM", "keychain_service": KEY_SERVICE,
        "retention": "Keep until the owner explicitly retires this legacy baseline",
        "recovery_limit": "Product-specification domain only; no sales, stock, accounting, auth or storage rollback"}
    private_write(folder / "product-specs.vbspec", encrypted)
    private_write(folder / "manifest.json", json.dumps(manifest, indent=2).encode())
    receipt = verify(folder)
    private_write(folder / "verification.json", json.dumps(receipt, indent=2).encode())
    private_write(folder / "recovery-tool.py", Path(__file__).read_bytes())
    launcher = "#!/bin/zsh\nset -eu\nexec {} {} view {}\n".format(
        shlex.quote(sys.executable), shlex.quote(str(folder / "recovery-tool.py")),
        shlex.quote(str(folder)))
    private_write(folder / "Abrir estado legacy.command", launcher.encode())
    os.chmod(folder / "Abrir estado legacy.command", 0o700)
    note = ("# Estado legacy de fichas\n\nCopia anterior al llenado masivo, posterior a las dos migraciones de fichas del 6 de septiembre.\n\n"
        "Abre `Abrir estado legacy.command` para consultar productos y hechos guardados en este Mac. "
        "La clave reside en el Llavero de macOS; conserva ese llavero junto con esta carpeta al cambiar de equipo.\n\n"
        "El archivo cifrado incluye datos normalizados, lecturas y procedencia, espejo legacy, plantillas, opciones, "
        "mapeos, referencias, composición de sets y código (HEAD más cambios locales). "
        "Los catálogos SQL son evidencia de la versión, no un script de restauración.\n\n"
        "Formato 2: incluye además las fichas de piezas incluidas en un producto (identidad confirmada, fila, "
        "plantilla, referencia, estado de archivo) con su historial de cambios, y conserva las observaciones de cada "
        "pieza bajo su propia ficha. El visor las muestra agrupadas por pieza, nunca mezcladas con la ficha del producto.\n\n"
        "No restaura ventas, compras, stock, cuentas, usuarios ni archivos de Storage. "
        "Una reversa en producción debe prepararse como cambio selectivo, comparar revisiones actuales, "
        "preservar cambios posteriores y verificar todos los campos restaurados.\n\n"
        "Verificación realizada: descifrado autenticado, hashes, referencias y recuperación campo por campo en carpeta temporal. "
        "No se ejecutó restauración contra PostgreSQL ni producción.\n")
    private_write(folder / "LEEME.md", note.encode())
    print(json.dumps({"folder": str(folder), "format_version": snapshot["format_version"],
                      "encrypted_sha256": sha(encrypted), "verified": True,
                      "row_counts": counts}, indent=2))


def render_view(snapshot):
    tables = snapshot["tables"]
    definitions = {row["id"]: row for row in tables["spec_definitions"]}
    options = {row["id"]: row for row in tables["spec_definition_values"]}
    categories = {row["id"]: row for row in tables["product_categories"]}
    templates = {row["id"]: row for row in tables["spec_templates"]}
    option_values = {}
    for row in tables["spec_fact_values"]:
        option_values.setdefault(row["fact_id"], []).append(row)
    readings = {}
    for row in tables["spec_fact_readings"]:
        readings.setdefault(row["fact_id"], []).append({
            "cita": row.get("quote"), "modelo": row.get("model"),
            "leido": row.get("read_at"), "huella": row.get("source_digest")})
    # Root observations by product; component observations by their scope.
    # A member fact is never listed under the root product.
    root_facts, member_facts = {}, {}
    for row in tables["spec_facts"]:
        value = next((row.get(key) for key in ("value_number", "value_boolean", "value_text", "value_json")
                      if row.get(key) is not None), None)
        selected = option_values.get(row["id"], [])
        if selected:
            value = [options[v["value_id"]]["label"] for v in sorted(selected,
                key=lambda x:(x.get("position") or 0, x["value_id"]))]
        definition = definitions[row["spec_definition_id"]]
        fact = {"campo": definition["label"], "clave": definition["key"], "valor": value,
                "unidad": definition.get("unit"), "fuente": row["source"],
                "confirmado": row["confirmed"], "lecturas": readings.get(row["id"], [])}
        scope = row.get("subject_scope")
        if scope is None:
            root_facts.setdefault(row["subject_id"], []).append(fact)
        else:
            member_facts.setdefault((row["subject_id"], scope), []).append(fact)
    events = {}
    for row in tables.get("product_spec_member_profile_events", []):
        image = lambda state: None if state is None else {
            key: state.get(key) for key in ("member_row_id", "member_identity",
            "manufacturer_sku", "reference_id", "archived_at")}
        events.setdefault(row["profile_id"], []).append({
            "cuando": row.get("occurred_at"), "actor": row.get("actor_id"),
            "antes": image(row.get("before_state")), "despues": image(row.get("after_state"))})
    pieces = {}
    for row in sorted(tables.get("product_spec_member_profiles", []),
                      key=lambda p:(p.get("created_at") or "", p["id"])):
        collection = definitions.get(row.get("collection_definition_id"), {})
        pieces.setdefault(row["product_id"], []).append({
            "ficha": row["id"], "coleccion": collection.get("label") or row.get("collection_definition_id"),
            "fila": row.get("member_row_id"), "identidad": row.get("member_identity"),
            "fuentes": row.get("identity_sources"), "mpn": row.get("manufacturer_sku"),
            "plantilla": templates.get(row.get("template_id"), {}).get("key") or row.get("template_id"),
            "version_guardada": row.get("saved_contract_version"),
            "referencia": row.get("reference_id"), "archivada": row.get("archived_at"),
            "hechos": member_facts.pop((row["product_id"], row.get("scope")), []),
            "historial": events.get(row["id"], [])})
    esc = lambda value: html.escape(str(value if value is not None else ""), quote=True)
    blocks = []
    for product in sorted(tables["products"], key=lambda p:(p["name"],p["id"])):
        category = categories.get(product.get("category_id"), {}).get("full_path") or "Sin categoría"
        values = root_facts.get(product["id"], [])
        product_pieces = pieces.get(product["id"], [])
        # Only a snapshot that failed validation could leave owned scopes here;
        # they are shown apart rather than merged into the product.
        unowned = [{"alcance": scope, "hechos": facts} for (subject, scope), facts
                   in sorted(member_facts.items()) if subject == product["id"]]
        archived = sum(1 for piece in product_pieces if piece["archivada"] is not None)
        summary = "{} · {} · {} hechos".format(esc(product["name"]), esc(product["sku"]), len(values))
        if product_pieces:
            summary += " · {} piezas ({} archivadas)".format(len(product_pieces), archived)
        body = {"identidad": product, "hechos": values}
        if product_pieces:
            body["piezas"] = product_pieces
        if unowned:
            body["hechos_sin_dueno"] = unowned
        blocks.append("<details><summary>{}</summary><p>{}</p><pre>{}</pre></details>".format(
            summary, esc(category), esc(json.dumps(body, ensure_ascii=False, indent=2))))
    return ("<!doctype html><html lang='es'><meta charset='utf-8'><meta name='viewport' content='width=device-width'>"
        "<meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'\">"
        "<title>Fichas · Estado legacy</title><style>body{font:16px system-ui;max-width:1100px;margin:40px auto;padding:0 24px}"
        "input{font:inherit;width:95%;padding:12px}details{padding:12px;border-bottom:1px solid #aaa}summary{cursor:pointer}"
        "pre{white-space:pre-wrap;overflow-wrap:anywhere;font-size:13px}</style>"
        f"<h1>Estado legacy de fichas</h1><p>{esc(snapshot['captured_at'])} · formato {esc(snapshot['format_version'])} · {len(tables['products'])} productos · Sólo lectura, copia local.</p>"
        "<p>Esta copia es posterior al rediseño de cadenas y anterior al llenado. No muestra cambios posteriores. "
        "Las piezas incluidas en un producto se listan bajo <code>piezas</code>, cada una con su identidad, estado de archivo, fuentes y observaciones.</p>"
        "<label>Buscar producto, SKU o campo <input type='search' id='search'></label>" + "".join(blocks) +
        "<script>document.getElementById('search').addEventListener('input',e=>{let q=e.target.value.toLocaleLowerCase();"
        "document.querySelectorAll('details').forEach(d=>d.hidden=!d.textContent.toLocaleLowerCase().includes(q))})</script></html>")


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    make = commands.add_parser("create")
    make.add_argument("--destination", type=Path, default=DEFAULT_DESTINATION)
    for name in ("verify", "view", "export-local"):
        sub = commands.add_parser(name)
        sub.add_argument("folder", type=Path)
        if name == "export-local":
            sub.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.action == "create":
        create(args.destination)
    elif args.action == "verify":
        print(json.dumps(verify(args.folder), indent=2))
    elif args.action == "view":
        _, snapshot, _ = read_bundle(args.folder)
        # The viewer is intentionally local and private. No remote resources,
        # auth tokens, write actions, or connection to the live ERP.
        viewer = args.folder / ("consulta-" + secrets.token_hex(4) + ".html")
        private_write(viewer, render_view(snapshot).encode())
        webbrowser.open(viewer.as_uri())
        print(f"Local read-only viewer: {viewer}")
    else:
        if args.output.exists():
            raise ValueError("Recovery output must be a new directory")
        _, snapshot, archive_bytes = read_bundle(args.folder)
        args.output.mkdir(parents=True, mode=0o700)
        private_write(args.output / "snapshot.json", canonical(snapshot))
        with zipfile.ZipFile(io.BytesIO(archive_bytes)) as archive:
            for name in ("HEAD.tar.gz", "workspace-overlay.tar.gz", "manifest.json"):
                private_write(args.output / "source" / name, archive.read("source/" + name))
        print(f"Local data recovery only: {args.output}; no database writes")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Values from a failed parse, query or decrypt are never printed.
        print(f"Recovery tool stopped: {type(error).__name__}: {error}", file=sys.stderr)
        sys.exit(1)
