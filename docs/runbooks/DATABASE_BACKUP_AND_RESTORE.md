# Database Backup and Restore

## Backup

1. Confirm the project reference and environment aloud in the terminal output; never infer it from a stale link.
2. Record schema version/commit and before invariants.
3. Create an encrypted logical dump with the owner-only database credential from the platform credential store.
4. Store the dump outside the repository with SHA-256, timestamp, project ref and retention metadata.
5. Verify the dump is readable without printing data or credentials.

## Restore drill

1. Create an isolated disposable project/database.
2. Refuse the production project ref in the restore command.
3. Restore roles/schema/data in the documented order.
4. Run schema fingerprint, tenant counts, ledger continuity, journal balance and critical pgTAP checks.
5. Delete the disposable environment only after recording the result.

Production restoration requires an incident record, confirmed backup, explicit before/after invariants and a second human confirmation. Never test restoration against production.

## Product-specification legacy baseline (2026-09-06)

A product-ficha rollback must not rewind later sales, purchases, prices, stock,
accounting or user accounts. Keep a **domain-scoped** encrypted recovery bundle
in addition to provider backups. This is not a replacement for the full ERP
backup procedure above.

`scripts/inventory/product_spec_legacy.py create` reads one MVCC snapshot through
`scripts/db/query.sh production`, using its project check, read-only transaction
and Keychain database credential. It captures all tenant product identities,
normalized facts/option links/readings, the legacy mirror, category mappings,
templates/definitions/vocabulary, references, set composition and receipts.
Products are an explicit projection; commercial and stock fields are only an
irreversible comparison fingerprint, never a restore payload. Schema catalogs
record the version but are **not an executable PostgreSQL restore script**.

The same encrypted archive includes the Git HEAD archive and an overlay of
tracked changes plus non-ignored untracked files. Ignored credentials, build
outputs and the running app's unsaved drafts are excluded. Shared checkout
changes are copied, never stashed, cleaned, staged or committed.

Use the workspace Python with `cryptography`, discovered from the bundled
runtime. On the verified Mac:

```bash
/Users/Claudio/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 scripts/inventory/product_spec_legacy.py create
```

The output directory is outside the repository, under
`~/Vinabike Backups/Product Specs Legacy/`. Its timestamped `manifest.json`
records scope, counts, SHA-256, project ref, retention and key location.
AES-256-GCM authenticates the encrypted archive; the key is stored in the macOS
Keychain, service `Vinabike ERP product specs legacy backup v1`, account of the
current OS user. The tool never overwrites an existing key. Preserve the keychain
when migrating the backup to another machine; copying the ciphertext alone does
not transfer the key.

Each copy contains `Abrir estado legacy.command`, `LEEME.md` and an independent
copy of the reader. The launcher opens a private local, read-only product viewer.
It does not connect to the ERP. The HTML view is a decrypted local consultation
copy with owner-only permissions; the authoritative archive remains encrypted.
`verify <folder>` checks authenticated decryption, member hashes, counts,
references and a row/field recovery roundtrip into a disposable private folder.
`export-local <folder> --output <new-folder>` recovers the snapshot and code
archives locally without a database write or overwriting an existing directory.
This verification proves archive/data recovery, **not** a successful PostgreSQL
restore; that stronger claim requires the separate restore drill above.

Before any selective production reversal, prepare a reviewed compensating
command with explicit before/after images and operation receipts. Revert only
fields whose current value, provenance and readings still match the operation's
after-image. A later edit is a conflict to reconcile. Never delete facts based
on `created_at`, decrement `spec_revision`, restore an old `updated_at` over
later activity, replace complete product rows, or restore old idempotency
receipts. Restore to a synthetic local tenant and test the actual compensating
command before requesting production restoration. The backup tool intentionally
does not implement a production apply command.
