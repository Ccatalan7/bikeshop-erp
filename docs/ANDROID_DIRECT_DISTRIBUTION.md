# Android direct distribution

Vinabike ERP uses a private, no-monthly-fee Android channel for a very small
employee pilot.

## User experience

1. Open `https://vinabike.cl/cuenta/descargas/android`.
2. Sign in with an active ERP staff account.
3. Download and install the APK. Android asks once whether the browser may
   install applications from this source.
4. Later releases are detected inside the installed ERP. `Actualizar`
   downloads the exact private APK, verifies its size and SHA-256, and opens
   Android's system installer.

Android always owns the final confirmation on an unmanaged phone. The ERP does
not attempt a silent installation.

The pilot build targets ARM64 (`arm64-v8a`), used by current Android phones. A
different CPU architecture needs its own release variant.

## Trust boundary

- Package: `com.vinabike.erp`.
- Every APK is signed by the same durable Viñabike release key.
- Permanent signing certificate SHA-256:
  `7e651eb2989b22a9d9262f91f0657e3a512134ac7675715fed144273ad2a897c`.
- The keystore is outside Git. The authorized Mac keeps its local copy and
  password in macOS Keychain. Cross-platform publication exposes its encrypted
  copy and passwords only inside the protected GitHub `Production` environment.
- Losing the keystore prevents seamless updates. Back it up before the first
  phone install.
- Release artifacts live in the private `erp-mobile-releases` Supabase Storage
  bucket below the tenant UUID. The ARM64 APK is split into ordered 40 MB
  objects to stay inside the no-cost project's per-object limit.
- Storage RLS allows reads only to active ERP staff in that tenant. Client
  uploads, replacements, and deletions are not allowed.
- The versioned APK and manifest are uploaded first. `latest.json` is replaced
  last, so clients never see a release before its immutable artifact exists.
- The app validates manifest schema, package, tenant path, size, version code,
  and SHA-256 before invoking Android. Android independently verifies the APK
  signature before replacing an installed application.

## Signing setup

On the authorized release Mac:

```bash
bash scripts/android/create_release_signing_key.sh --create
bash scripts/android/create_release_signing_key.sh --check
```

The default durable path is:

```text
~/Library/Application Support/Vinabike ERP/signing/android-release.jks
```

Never commit the keystore, its password, `android/key.properties`, or a
base64-encoded copy. The base64 transport belongs only in
`ANDROID_RELEASE_KEYSTORE_BASE64` in the protected GitHub environment. Put an
independent encrypted backup under an owner-controlled recovery process.

## Publication

The package version comes from `pubspec.yaml` and its build number must increase
for every release.

The normal cross-platform developer action on macOS is:

```text
Cmd+Shift+B -> Publish ERP Update (macOS + Android)
```

On Windows, the equivalent single action is:

```text
Ctrl+Shift+B -> Publish ERP Update (Windows + Android)
```

Each task safely fast-forwards a behind branch when it does not overlap local
work, runs the pinned Flutter dependency resolution, creates at most one shared
commit, asks local Codex at most once for one bounded shared note candidate,
pushes once, then starts the selected desktop publisher and Android publisher
in parallel in separate VS Code terminal panes. The Android child consumes a
short-lived schema-v2 exact-SHA state file inside `.git`; it never creates
another commit or push. Before dispatch, it requires the local branch, clean
worktree, `HEAD`, live remote branch, release-note base, and candidate checksum
to match that shared state.

The protected cross-platform path dispatches the already-registered
`.github/workflows/macos-release.yml` entrypoint with
`release_target=android`. That neutral router calls
`.github/workflows/android-release.yml` at the exact shared commit. This is
required until the new Android workflow is also registered on the repository
default branch. Android's build, signing, secrets, evidence, serialization, and
retry boundary remain independent from macOS. GitHub serializes Android
publications, runs the application integrity gate, rebuilds
packaged assets, derives a version code greater than the private live manifest,
builds and verifies the signed APK, and publishes it to the same private
Supabase bucket. The committed version name remains authoritative; CI selects
`max(committed build code, latest live code + 1)` so a Windows workstation does
not need the Supabase credential or Android signing material.

The workflow accepts only a size-bounded, checksummed local Codex candidate and
an exact release-note base commit. Protected CI independently reconstructs the
committed range and validates the candidate. Invalid or unavailable AI output
falls back to deterministic Spanish notes without blocking the update. The
structured `release_notes` object is bound to the Android manifest commit so the
installed app can show the same user-friendly `Novedades` content as desktop
releases.

Every successful publication or exact-commit retry retains one bounded
`vinabike-erp-android-release-evidence` Actions artifact containing the exact
final Supabase readback as `android-release-manifest.json`. A workflow success
without that matching manifest is not publication evidence.

If the same Android version and commit are already live, a retry reports success
without rebuilding or replacing the release. If macOS succeeds while Android
fails, macOS stays published and the Android terminal retains the exact failure;
the platforms do not share or weaken signing credentials.

Protected CI retries are also idempotent. If `latest.json` already names the
requested commit, the workflow verifies and returns that exact manifest.
Otherwise it reuses only byte-identical immutable APK parts and versioned
metadata left by a partial attempt; conflicting existing content fails closed.

The standalone Android commands remain available for an Android-only
maintenance release.

Preflight:

```bash
bash scripts/android/publish_direct_release.sh --check
```

Exact publication:

```bash
VINABIKE_ANDROID_RELEASE_CONFIRM=publish-1.0.2+4 \
  bash scripts/android/publish_direct_release.sh
```

Publication refuses an uncommitted worktree. It builds the ARM64 release APK,
verifies its Android signature and permanent certificate fingerprint, hashes
the whole APK and every ordered part, uploads each part through Supabase's 6 MB
resumable-upload protocol, writes the immutable versioned manifest, advances the
private latest manifest, and reads back the complete package, version, source
commit, object path, byte count, hashes, and ordered parts.

## Rollback

Android rejects a lower version code. Rollback is a forward-fix build containing
the previous known-good code with a new, higher build number. Do not remove the
current private artifact during an incident; publish the forward fix and keep
the release ledger intact.

The APK updater does not roll back Supabase migrations or backend changes.
Mobile-visible backend evolution must remain compatible with the currently
installed release.
