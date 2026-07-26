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
4. It asks the locally authenticated Codex CLI once for a bounded,
   user-friendly Spanish release-note candidate. Missing login, timeout,
   malformed output, or quota exhaustion leaves the candidate empty and does
   not block the release.
5. It writes a short-lived, current-user-only Windows+Android handoff inside
   `.git`, separate from the macOS paired-release state, binding the branch,
   exact local and remote SHA, release-note base, candidate bytes, and
   candidate SHA256.
6. VS Code then launches the Windows and Android GitHub publishers in parallel
   in separate terminal panes. Each child revalidates the state and live source
   independently before dispatching its own protected workflow.

The shared task does **not** merge signing systems or credentials. Windows and
Android remain separate GitHub Actions workflows, protected publication jobs,
artifacts, manifests, signing keys, logs, and final results. If one platform
succeeds and the other fails, the successful release remains valid; rerunning
the paired task treats an already-published exact commit as success and retries
only what is missing. The preparation state keeps and reuses the exact
SHA-bound Codex candidate for that same commit, so an ordinary partial-success
retry does not silently rewrite the user-facing summary.

The same validated Codex candidate is offered to both protected jobs, so their
`Novedades` describe the same committed ERP update. Each workflow independently
reconstructs and validates the committed evidence before accepting it. If
Codex is unavailable or the candidate is rejected, the protected release-note
generator continues through the established sanitized Gemini path and then the
deterministic fallback.

The first paired Android release uses the latest valid Windows release commit
as its shared notes baseline because the Windows computer does not receive the
private Supabase credential needed to inspect the older direct-Android channel.
That first summary can therefore cover the desktop release range; after paired
publishing begins, the Windows and Android baselines converge naturally.

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
request and retries only with an available model from its fixed free Gemini
Flash/Flash-Lite allowlist. When the Gemini key is absent, the existing
`OPENAI_API_KEY` and `OPENAI_RELEASE_NOTES_MODEL` integration remains available
as a compatibility path.

Errors, exhausted quota, timeouts, or invalid output leave the validated
deterministic fallback in place and must not block publication. The generator
prints the selected provider, active Gemini model, and only a sanitized failure
category so an AI downgrade is visible without exposing Google error text or
release metadata.

Only sanitized, bounded release metadata is eligible for either provider:
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
