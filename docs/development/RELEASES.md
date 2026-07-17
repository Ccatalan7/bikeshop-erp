# Releases

The canonical promotion path is:

```text
feature/current line → pull request to protected main → integrity + preview
→ intentional merge → Production environment → post-deploy smoke
```

- `main` is protected and rejects force-pushes/deletion.
- Firebase ERP/store and Windows release workflows consume the merged commit.
- Production jobs use the `Production` GitHub Environment; pull-request previews use `staging`.
- A workflow dispatch is diagnostic or exceptional and must still run its integrity dependency.
- Never deploy a dirty working tree or run direct production upload helpers as a normal release path.
- Record commit SHA, actor, environment, timestamps, checks and rollback reference.
- Web builds publish `release.json` and retained SHA-256 evidence. Promotion is
  successful only when the live Firebase target reports the exact merged commit.
- The ERP production job then runs the read-only inventory/payment/journal/trace
  invariant dashboard. A critical violation fails the release record without
  attempting an automatic data repair.

Firebase rollback uses the previous Hosting release. Windows rollback uses the previous signed/checksummed artifact. macOS internal rollback restores the previous verified bundle retained under the per-user updater support directory. Database rollback follows the database backup/restore runbook and must not improvise destructive reverse SQL.

For a Firebase rollback, select the last release whose retained evidence and
post-deploy checks passed, restore it through Firebase Hosting release history,
then verify its `release.json` commit and rerun `just db-health production`.
