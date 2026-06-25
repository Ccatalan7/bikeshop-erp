# Windows Desktop Distribution

This project distributes the Windows desktop app through GitHub Releases.

The setup is intentionally free and low-friction:

- GitHub Actions builds the Windows release zip.
- The release zip is published as a GitHub Release asset.
- A SHA256 file is published next to the zip.
- `scripts/install_vinabike_erp.ps1` downloads the latest release, verifies the SHA256 checksum, installs into the current user's profile, and creates shortcuts.
- The Flutter app checks for a newer Windows release after staff users enter the workspace.
- When an update exists, the app shows an in-app update prompt. Pressing `Actualizar` starts the external updater, closes the app, replaces the app folder, and relaunches Vinabike ERP.
- The normal `Vinabike ERP` shortcut also runs a launcher script that checks for updates before opening the app. This is a fallback for users who ignore the in-app prompt.

## Coworker Install

On each Windows computer, run this once in PowerShell:

```powershell
Invoke-WebRequest https://raw.githubusercontent.com/Ccatalan7/bikeshop-erp/main/scripts/install_vinabike_erp.ps1 -OutFile $env:TEMP\install_vinabike_erp.ps1
powershell -ExecutionPolicy Bypass -File $env:TEMP\install_vinabike_erp.ps1 -Launch
```

After that, users open `Vinabike ERP` from the desktop or Start Menu. Future updates appear inside the Flutter app as an update prompt.

## Publishing An Update

Updates publish automatically when relevant app files are pushed to `main`.

You can also publish manually:

1. Open GitHub Actions.
2. Run `Build Windows Desktop Release`.
3. Wait for the workflow to finish.

The newest non-prerelease GitHub Release that contains `vinabike_erp_windows_*.zip` and its `.sha256` file becomes the update source. The next time users open the app, the Flutter workspace shows an update prompt. The launcher shortcut also checks for updates before starting the app.

## Local Test Build

On a Windows machine:

```powershell
flutter pub get
flutter build windows --release
Compress-Archive -LiteralPath build\windows\x64\runner\Release -DestinationPath build\vinabike_erp_windows_test.zip -Force
```

Do not distribute only `vinabike_erp.exe`; the app needs the DLLs and `data` folder next to it.

## User Update Flow

For coworkers, the normal flow is:

1. Open Vinabike ERP.
2. If an update is available, press `Actualizar`.
3. The app closes.
4. The updater installs the new build and reopens Vinabike ERP.

The updater is separate from Flutter because Windows cannot safely replace the running `vinabike_erp.exe` while the app is open.

## Why This Instead Of Google Drive

Google Drive is fine for a one-off zip, but it is weak for recurring app updates:

- no clean "latest release" API for the app to check
- awkward direct download URLs
- weaker release history
- no automatic build from the repo

GitHub Releases gives us stable HTTPS downloads, release history, automated builds, and checksum verification for free.

## Future Upgrade Path

The proper Windows-native installer/update model is MSIX plus App Installer. That is still the better long-term packaging format, but secure MSIX distribution should use a stable signing certificate. This workflow avoids a paid certificate for now while keeping distribution automated and verifiable.
