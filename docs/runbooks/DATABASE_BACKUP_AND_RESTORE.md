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
