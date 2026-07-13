# macOS Setup

## First setup

1. Install Xcode from Apple and open it once to accept its license.
2. Clone the repository and enter its root.
3. Run `bash scripts/bootstrap/bootstrap_macos.sh`.
4. Run `just doctor`.
5. Copy `.env.example` to `.env` only when local runtime credentials are required; obtain values from the approved password store, never chat or Git.
6. Run `just verify-fast`. Run `just verify` before a pull request.

The bootstrap installs missing packages from `Brewfile` without broadly upgrading installed packages. It configures pinned Node/npm through Volta, pinned Flutter through FVM, the Python parser through uv, and a Colima Docker runtime when no runtime is active.

If VS Code reports that the project's `.fvm/...` path is not a valid SDK immediately
after a pull, run the lightweight repair instead of the full bootstrap:

```bash
bash scripts/bootstrap/ensure_flutter_sdk_macos.sh
```

Then reload the VS Code window. This activates the version from `.fvmrc` and
runs `flutter pub get`; it does not change application or business data.

## Authentication

Use interactive provider logins and the macOS Keychain:

```text
gh auth login
firebase login
supabase login
```

The doctor checks authentication state without printing tokens. Provider and database secrets must remain in Keychain or owner-only `.env` files.

## Platform checks

- macOS builds require Xcode and CocoaPods.
- Android builds require Android Studio SDK components and accepted licenses.
- Local Supabase tests require Docker/Colima and PostgreSQL client tools.
- Browser E2E installs its browser once with `npx playwright install chromium`.
