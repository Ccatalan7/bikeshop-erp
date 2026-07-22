# macOS Desktop Distribution

Vinabike ERP distributes internal macOS builds through GitHub Releases without
requiring coworkers to install Git, Flutter, VS Code, Codex, or ChatGPT.

This is an internal trust channel, not Apple notarization. The first installer
is an explicit user opt-in. From then on, a per-user background updater accepts
only release metadata signed by Vinabike's dedicated Ed25519 key and validates
the archive and app bundle before installation.

## Coworker Experience

The stable application lives at:

```text
~/Applications/Vinabike ERP.app
```

The coworker installs it once with Terminal:

```bash
curl -fsSL \
  https://github.com/Ccatalan7/bikeshop-erp/releases/download/macos-latest/install_vinabike_erp_macos.sh \
  -o /tmp/install_vinabike_erp_macos.sh
bash /tmp/install_vinabike_erp_macos.sh
```

The installer explains that this is an internal, non-notarized channel. It does
not disable Gatekeeper and does not require `sudo`. It removes quarantine only
from the app bundle whose signed manifest, SHA-256, bundle identifier, version,
and macOS code seal were verified.

After the first install:

1. Open `Vinabike ERP` from `~/Applications` and choose **Keep in Dock**.
2. The Flutter app checks the public `macos-latest` stable manifest silently,
   without consuming GitHub's anonymous API quota.
3. A per-user LaunchAgent downloads and prepares a new version outside the app
   sandbox.
4. The in-app prompt appears only after the update is verified and ready.
5. Press **Reiniciar**. The app exits, the prepared bundle replaces the stable
   path, and Vinabike ERP reopens.

The Dock remains valid because updates replace the same stable path. Never pin
an app from `build/macos/Build/Products`.

## Security Model

Each versioned `macos-v*` release contains:

- `vinabike_erp_macos_<version>-<run>.zip`
- the archive's `.sha256`
- `macos-release-manifest.json`
- `macos-release-manifest.json.sig`
- `install_vinabike_erp_macos.sh`

The manifest binds the exact Git commit, release tag, archive URL, archive hash,
installer hash, bundle ID, build number, and visible version. Only the manual
GitHub Actions job inside the protected `Production` environment can access the
private `MACOS_UPDATE_SIGNING_KEY` and sign it. Artifact-only builds cannot use
the key. The repository and every installed updater contain only the public key.

The sandboxed app and the per-user LaunchAgent exchange only update request and
state JSON files under `~/Library/Application Support/VinabikeERP/coordination`.
The release entitlements grant the app a home-relative read/write exception for
`/Library/Application Support/VinabikeERP/` and no broader filesystem path. This
avoids asking a background LaunchAgent to mutate the app's protected sandbox
container while keeping the rest of App Sandbox enabled.

The installer rejects the release unless all of these pass:

1. SSH/Ed25519 manifest signature.
2. Expected `macos-v*` tag and GitHub repository URLs.
3. Archive SHA-256.
4. Exact bundle identifier `com.vinabike.vinabikeErp`.
5. Exact short version and monotonically generated bundle version.
6. Strict recursive `codesign` integrity verification.

The channel does **not** provide Apple's malware scan or Developer ID identity.
That is the remaining difference from a paid notarized distribution. A future
macOS security change may require revisiting this internal path. Do not broaden
the quarantine exception or disable Gatekeeper to work around such a change.

## Local State And Recovery

Updater code, downloads, logs, and rollback state live under:

```text
~/Library/Application Support/VinabikeERP
```

The app and its LaunchAgent share update coordination state under:

```text
~/Library/Application Support/VinabikeERP/coordination
```

Useful files:

- `updater.log`: verification, preparation, install, and rollback events.
- `launch-agent.log`: background process output.
- `coordination/prepared-release.json`: release waiting for the user to restart.
- `coordination/current-release.json`: installed release tag.
- `coordination/update-error.json`: user-facing preparation/apply failure.
- `rollback/Vinabike ERP.previous.app`: previous working bundle.

If the new app does not remain running after replacement, the updater restores
the previous app automatically and records the failure. It never deletes user
documents, app-container data, credentials, Git state, or database state.
Temporary downloads are deleted after every attempt, stale prepared versions
are pruned after a successful preparation, and logs rotate at 5 MB. In steady
state, disk use is bounded to the installed app, one rollback app, updater
support files, and at most one prepared update waiting for restart.

## Publishing An Update

The normal developer action is the selectable VS Code task:

```text
Cmd+Shift+B -> Publish macOS Update (all changes)
```

It runs `scripts/publish_macos_update.sh`, which stays on the current authorized
branch and stages pending Source Control changes. Before any commit or push, it
renders the staged Git tree into an isolated temporary directory and runs the
same release-integrity commands used by CI there: clean Node dependency
installation, spreadsheet-engine generation, Flutter dependency resolution,
analyzer, the complete Flutter test suite, and the ERP web release build. The
snapshot is immutable, so another agent may continue editing ordinary working
files without changing or invalidating the release under test; those later
edits remain pending for the next update. The task stops only if another process
explicitly changes the staged index during the preflight. After the exact staged
snapshot passes, the temporary directory is removed and the task commits when
needed, pushes, dispatches `.github/workflows/macos-release.yml` with
`publish_release=true`, waits for the guarded workflow, and verifies the
published assets.

If the local preflight fails, the task stops before commit, push, or workflow
dispatch. The shared machine-readable test gate prints the exact failed test,
source file, expectation, and stack location while suppressing unrelated widget
debug noise. Fix the reported failure and run the same task again; no partial
macOS update is published. `flutter analyze` and VS Code's Problems panel do not
run this suite, so a zero-error Problems count is not release-readiness proof.

This is intentionally stricter than the Windows developer helper. Windows
commits and pushes first, then runs the shared integrity gate in GitHub Actions;
macOS verifies an immutable local snapshot before creating or pushing a release
commit, and GitHub verifies it again. Agents can exercise only the local macOS
gate without mutating Git or publishing by running:

```bash
bash scripts/publish_macos_update.sh --preflight-only
```

Pushes and ordinary dispatches are artifact-only. They build and verify but
cannot publish an update. Only the separate `Production` job has write access
to GitHub Releases and refreshes the `macos-latest` metadata alias.

Both the integrity gate and the macOS runner execute `npm ci` followed by
`npm run build:spreadsheet-engine` before Flutter. The generated Univer bundles
are intentionally ignored by Git, so this step is what guarantees that a clean
release includes the new spreadsheet engine instead of depending on one Mac's
local files.

Never create a temporary branch or worktree for publication. Both `main` and
`smartpegas1.0` are explicitly authorized by the GitHub Production environment.

## First Canary

Before giving the command to coworkers, test two consecutive published versions
on one Mac:

1. Install the older release through the one-time installer.
2. Confirm it launches from `~/Applications` and remains pinned after a repo
   `build/` cleanup.
3. Publish the newer release.
4. Confirm background preparation, the in-app **Reiniciar** action, stable Dock
   path, relaunch, installed tag, and bundle version.
5. Exercise a deliberately invalid local package and confirm signature/hash
   rejection and rollback without publishing it.

Only after this canary should the internal update command be handed to Chile.
