# Windows Setup

## First setup

1. Open PowerShell 7 as the normal development user.
2. Clone the repository and enter its root.
3. Run `pwsh -File scripts/bootstrap/bootstrap_windows.ps1`.
4. Restart the terminal so the user PATH refreshes.
5. Run `pwsh -File scripts/dev/doctor.ps1`.
6. Run `just verify-fast`; run `just verify` before a pull request.

The bootstrap uses WinGet for Git, GitHub CLI, Volta, uv, just, Gitleaks, Docker Desktop, PostgreSQL, PowerShell and Android Studio. It installs the pinned Flutter SDK under the user's FVM directory and never stores repository credentials.

## Windows desktop compiler

Install Visual Studio 2022 with:

- Desktop development with C++ workload
- MSVC v143 build tools
- Windows 10 or 11 SDK
- C++ CMake tools

This workload remains an explicit Visual Studio Installer step because silently altering an existing Visual Studio installation is unsafe. `flutter doctor -v` identifies any missing component.

## Secrets and authentication

Use Windows Credential Manager or an owner-only `.env`; never put values in tracked PowerShell profiles or launch configurations. Authenticate interactively with `gh auth login`, `firebase login`, and `supabase login`.
