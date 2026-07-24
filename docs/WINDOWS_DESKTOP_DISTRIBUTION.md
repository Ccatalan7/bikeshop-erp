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

The workflow is pinned to the GitHub `windows-2022` runner so the Windows build uses the Visual Studio 2022 toolchain instead of whatever `windows-latest` points to that week. Release tags do not trigger this workflow; the workflow creates the release.

The newest non-prerelease GitHub Release whose
`windows-release-manifest.json`, `vinabike_erp_windows_*.zip`, matching
`.sha256`, and `install_vinabike_erp.ps1` all agree becomes the update source.
The next time users open the app, the Flutter workspace prepares the update
silently, then shows an update prompt only when the update is ready.

The protected publish job first creates deterministic Spanish fallback notes
for the exact previous-release commit range, then may improve them through the
OpenAI Responses API when `OPENAI_API_KEY` exists in the `Production`
environment. It sends bounded Git metadata rather than raw source. AI errors or
invalid output never block publication; the validated fallback remains in the
manifest.

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
