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
- The keystore is outside Git and its password is stored in macOS Keychain.
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
base64-encoded copy. Put an encrypted backup under an owner-controlled recovery
process before distributing the first APK.

## Publication

The package version comes from `pubspec.yaml` and its build number must increase
for every release.

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
private latest manifest, and reads that manifest back.

## Rollback

Android rejects a lower version code. Rollback is a forward-fix build containing
the previous known-good code with a new, higher build number. Do not remove the
current private artifact during an incident; publish the forward fix and keep
the release ledger intact.

The APK updater does not roll back Supabase migrations or backend changes.
Mobile-visible backend evolution must remain compatible with the currently
installed release.
