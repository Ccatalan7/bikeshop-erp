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
$ErrorActionPreference = 'Stop'
Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/Ccatalan7/bikeshop-erp/main/scripts/install_vinabike_erp.ps1 -OutFile "$env:TEMP\install_vinabike_erp.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\install_vinabike_erp.ps1" -Launch
```

After that, users open `Vinabike ERP` from the desktop or Start Menu. Future updates are prepared silently in the background and appear inside the Flutter app only when they are ready to apply.

2026-08-31 correction: a source branch is not an installed release. Publishing
macOS and Android does not publish Windows. Before handing over an installer,
compare the live Windows manifest commit with the requested branch head; when
they differ, describe the Windows version as older instead of implying parity.
Published release notes use that release's immutable installer URL. The
bootstrap above reads the maintained installer from the canonical branch, but
still installs only a published, checksummed Windows artifact.

The installer and Flutter updater scan at most ten pages of 100 releases.
macOS entries can fill an entire first page; absence there is not proof that no
Windows release exists. Both readers stop at the first matching candidate or
the end of the feed and preserve network/manifest failures. The PowerShell
discovery regression executes the real function with fixtures, without running
the installer entry point, and is also run on Windows PowerShell in CI.
Assign the REST response before normalizing it with an array expression:
wrapping the invocation directly nests the JSON array as one pipeline object,
so a real 100-release page falsely looks like a one-item terminal page. The
fixtures preserve that actual PowerShell transport behavior.

Windows release builds must explicitly enable the production AI gateway and
receive the public Supabase publishable key, just like macOS/Android. Missing
build configuration fails before packaging; a newer Git SHA alone does not
activate a compile-time-disabled runtime.

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
5. It resolves the exact common release-note range. Protected CI assembles
   committed reviewed changes verbatim for the actual platform and Release scope.
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

Both protected jobs assemble reviewed changes over the same exact range and
select the actual platform. Their shared user-facing changes have identical
text. Each workflow reconstructs and validates committed source hashes and
coverage independently. Missing or stale review blocks publication; filenames
and green tests do not establish a user benefit. Preparation advances the
visible version for new source while preserving same-commit retries and
monotonic native build counters.

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

The protected publish job assembles the implementation agent's reviewed
records under `docs/releases/changes/`, selecting Windows and Release scope.
It validates the exact range, source hashes, coverage, module ownership and
plain-text limits before binding the notes to the archive. No provider call,
credentials or speculative fallback is used. Logs identify
`source: ai; provider: reviewed-change-records`; installed clients retain their
existing manifest format. Debug/internal records do not advertise benefits.
A new commit with an already-published visible version is rejected.
See [RELEASES.md](development/RELEASES.md#versiones-y-novedades-verificadas-corregido-el-2026-10-01)
for the record format, author review and automatic visible version progression.

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
