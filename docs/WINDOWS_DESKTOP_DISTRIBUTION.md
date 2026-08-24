# Windows Desktop Distribution

This project distributes the Windows desktop app through GitHub Releases.

The setup is intentionally free and low-friction:

- GitHub Actions always builds, validates, packages, and checksums the Windows
  release zip as a private workflow artifact.
- The zip becomes a public GitHub Release asset only after an explicit manual
  dispatch with `publish_release=true`.
- A SHA256 file is published next to the zip.
- An exact-SHA `windows-release-manifest.json` carries the archive identity and
  optional user-friendly release notes.
- `scripts/install_vinabike_erp.ps1` downloads the latest release, verifies the SHA256 checksum, installs into the current user's profile, and creates shortcuts.
- The Flutter app checks for a newer Windows release after staff users enter the workspace.
- When an update exists, the app prepares it in the background while the user keeps working. The in-app prompt appears only after the update has already been downloaded and staged.
- Pressing `Reiniciar` starts a separate updater bootstrap, closes the app, applies the prepared update, and relaunches Vinabike ERP.
- The normal `Vinabike ERP` shortcut opens the app immediately. It does not block startup to check for updates.

## Coworker Install

On each Windows computer, run this once in PowerShell:

```powershell
Invoke-WebRequest https://raw.githubusercontent.com/Ccatalan7/bikeshop-erp/main/scripts/install_vinabike_erp.ps1 -OutFile $env:TEMP\install_vinabike_erp.ps1
powershell -ExecutionPolicy Bypass -File $env:TEMP\install_vinabike_erp.ps1 -Launch
```

After that, users open `Vinabike ERP` from the desktop or Start Menu. Future updates are prepared silently in the background and appear inside the Flutter app only when they are ready to apply.

## Publishing An Update

Relevant pushes to `main` and default manual dispatches run the complete
artifact-only gate. They do not create a tag, GitHub Release, or coworker
update.

Validate a candidate without publishing it:

1. Open GitHub Actions.
2. Run `Build Windows Desktop Release`.
3. Leave `publish_release` disabled.
4. Wait for the workflow to finish and inspect the retained artifact, checksum,
   installer, and exact-SHA manifest.

Publish only after that evidence is accepted:

1. Run `Build Windows Desktop Release` again.
2. Explicitly enable `publish_release`.
3. Confirm the run's source SHA, then wait for both the build and guarded
   `Publish verified coworker update` job to finish.

The developer helper and VS Code publish task pass
`publish_release=true` explicitly. A forgotten input therefore fails safe as
artifact-only instead of exposing an update.

### One Windows + Android task

On a Windows development computer, the primary paired-release action is:

```text
Ctrl+Shift+B -> Publish ERP Update (Windows + Android)
```

That task deliberately has one shared preparation step followed by two
independent publishers:

1. It verifies that the current branch is allowed by the protected
   `Production` environment.
2. It fetches the live branch and applies only a safe fast-forward. Diverged
   history or a fast-forward that would disturb local work stops before
   publication.
3. It runs the pinned Flutter dependency normalization, stages the reviewed
   Source Control changes once, creates at most one new commit, and pushes that
   exact commit once.
4. It validates the latest prior successful Android
   Actions evidence artifact and combines its commit with the latest applicable
   Windows release. The older ancestor, or their one unique safe merge base,
   becomes the common `Novedades` baseline. Missing, expired, non-ancestral, or
   ambiguous evidence stops safely.
5. It resolves the exact common release-note range. Gemini Flash generates the
   bounded, user-friendly Spanish copy later inside each protected publish job.
6. It writes a short-lived, current-user-only Windows+Android handoff inside
   `.git`, separate from the macOS paired-release state, binding the branch,
   exact local and remote SHA, and release-note base. Legacy candidate fields
   remain empty for state-schema compatibility.
7. VS Code waits a bounded time for the push-triggered exact-SHA
   `ERP Integrity Gate`. If path filters created no run, it rechecks for a
   queued/in-progress run and dispatches the gate once with the exact expected
   commit. A successful live run upgrades the private handoff from schema v2
   to schema v3 with repository, workflow, run, attempt, branch, and SHA proof.
8. VS Code then launches the Windows and Android GitHub publishers in parallel
   in separate terminal panes. Each child revalidates the state and live source
   independently, and each protected workflow queries GitHub Actions to verify
   that exact successful qualification before building.

The shared task does **not** merge signing systems or credentials. Windows and
Android remain separate GitHub Actions workflows, protected publication jobs,
artifacts, manifests, signing keys, logs, and final results. If one platform
succeeds and the other fails, the successful release remains valid; rerunning
the paired task treats an already-published exact commit as success and retries
only what is missing. The preparation state keeps the exact notes baseline for
that same commit. Both the pre-qualification schema-v2 state and the same
handoff after its schema-v3 qualification upgrade preserve that binding.

A retry after an application-test failure diagnoses the completed same-SHA run
immediately instead of running the full gate again in both platform workflows.
Only cancelled, timed-out, stale, or startup-failed qualification may rerun the
same GitHub run once. `Publish Windows Update (all changes)` carries no shared
proof and therefore retains its own complete integrity fallback.

Both protected jobs run the same Gemini Flash generator over the same exact
range, so their `Novedades` describe the same committed ERP update. Each
workflow independently reconstructs and validates the committed evidence before
accepting it. If Gemini is unavailable or its output is rejected, the validated
deterministic fallback remains intact and publication can be retried safely.

The workstation never receives the private Supabase credential. It derives the
Android side of the common baseline from the bounded successful Actions evidence
artifact that was produced only after protected CI read back the exact live
Supabase manifest. Android CI independently checks that the prepared base is at
or before its current live release before publishing.

`Publish Windows Update (all changes)` remains available for a Windows-only
release and keeps its existing standalone behavior.

The workflow is pinned to the GitHub `windows-2022` runner so the Windows build uses the Visual Studio 2022 toolchain instead of whatever `windows-latest` points to that week. Release tags do not trigger this workflow; the workflow creates the release.

The newest non-prerelease GitHub Release whose
`windows-release-manifest.json`, `vinabike_erp_windows_*.zip`, matching
`.sha256`, and `install_vinabike_erp.ps1` all agree becomes the update source.
The next time users open the app, the Flutter workspace prepares the update
silently, then shows an update prompt only when the update is ready.

The protected publish job first creates deterministic Spanish fallback notes
for the exact previous-release commit range so the local intermediate file is
always valid, then prefers the Gemini API when `GEMINI_RELEASE_API_KEY` exists
in the protected `Production` environment. The default model is
`gemini-3.1-flash-lite`, with `GEMINI_RELEASE_NOTES_MODEL` available as an
optional override. If Google reports that model unavailable or rejects its
output-format contract, the generator performs one metadata-free model-list
request and retries only with an available model from its fixed Gemini
Flash/Flash-Lite allowlist. When the Gemini key is absent, the existing
deterministic fallback remains in place. The standard workflows do not call
Codex and do not receive an OpenAI credential.

Errors, exhausted quota, timeouts, or invalid output leave the validated
deterministic fallback in place and must not block publication. The generator
prints the selected provider, active Gemini model, and only a sanitized failure
category so an AI downgrade is visible without exposing Google error text or
release metadata.

Only sanitized, bounded release metadata is eligible for the provider:
fixed canonical ERP module/topic labels, status and change counts, and opaque
evidence IDs. Commit subjects, commit SHAs, raw/current/previous paths, source,
diffs, credentials, generated bundles, binary contents, customer data, and
other personal or confidential information stay local and must never be sent.
Opaque evidence IDs are mapped back to local changed paths only after the model
output passes schema and evidence validation.

Google's free/unpaid Gemini service may use submitted inputs and generated
outputs to improve its products, and human reviewers may process them; release
metadata must therefore remain within this non-sensitive boundary. See the
[Gemini API Additional Terms of Service](https://ai.google.dev/gemini-api/terms).

The CI gate deliberately does not start `vinabike_erp.exe`: application startup
initializes the production Supabase fallback and notifications before login.
Instead it verifies that the executable, Flutter DLL, ICU data and Flutter
assets exist, including the generated Univer spreadsheet engine, then packages
and checksums them without credentials or production traffic. The release job
regenerates that tracked web bundle from `package-lock.json` on its own clean
runner. Perform the functional startup check on an installed Windows canary.

## Local Test Build

On a Windows machine:

```powershell
npm ci
npm run build:spreadsheet-engine
flutter pub get
flutter build windows --release
Compress-Archive -LiteralPath build\windows\x64\runner\Release -DestinationPath build\vinabike_erp_windows_test.zip -Force
```

Do not distribute only `vinabike_erp.exe`; the app needs the DLLs and `data` folder next to it.

## User Update Flow

For coworkers, the normal flow is:

1. Open Vinabike ERP.
2. If an update exists, the app downloads and stages it in the background.
3. When available, press `Novedades` to read a short summary grouped by ERP
   module.
4. Press `Reiniciar`.
5. The app closes, applies the prepared update, and reopens Vinabike ERP.

The updater is separate from Flutter because Windows cannot safely replace the running `vinabike_erp.exe` while the app is open. If the handoff fails, check:

- `%LOCALAPPDATA%\VinabikeERP\updater-bootstrap.log`: the app-to-updater handoff log.
- `%LOCALAPPDATA%\VinabikeERP\updater.log`: the PowerShell installer log.

The updater also defends against Windows file-lock timing during restart: it retries the app-folder swap, closes stale updater `cmd` shells left by older builds, and falls back to applying the release in place if the folder itself cannot be renamed. If the install still fails, the bootstrap reopens the existing app instead of leaving the user stranded.

The app shows notes only when the selected release tag, target commit, manifest,
archive, and prepared state match. Missing or invalid notes hide `Novedades`
without affecting download, checksum verification, or restart.

## Why This Instead Of Google Drive

Google Drive is fine for a one-off zip, but it is weak for recurring app updates:

- no clean "latest release" API for the app to check
- awkward direct download URLs
- weaker release history
- no automatic build from the repo

GitHub Releases gives us stable HTTPS downloads, release history, automated builds, and checksum verification for free.

## Future Upgrade Path

The proper Windows-native installer/update model is MSIX plus App Installer. That is still the better long-term packaging format, but secure MSIX distribution should use a stable signing certificate. This workflow avoids a paid certificate for now while keeping distribution automated and verifiable.
