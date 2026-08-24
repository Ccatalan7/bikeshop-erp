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
5. When the signed manifest contains release notes, **Novedades** opens a short,
   non-technical summary grouped by ERP module.
6. Press **Reiniciar**. The app exits, the prepared bundle replaces the stable
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
installer hash, bundle ID, build number, visible version, and any customer-facing
release notes. Only the manual GitHub Actions job inside the protected
`Production` environment can access the private `MACOS_UPDATE_SIGNING_KEY` and
sign it. Artifact-only builds cannot use the key. The repository and every
installed updater contain only the public key.

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
- `coordination/prepared-manifest.json`: exact signed manifest verified for that
  prepared release, including optional release notes.
- `coordination/current-release.json`: installed release tag.
- `coordination/current-manifest.json`: verified manifest for the installed
  release, restored together with the previous app if startup rolls back.
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

To publish the same reviewed source to both installed platforms, use the single
top-level task:

```text
Cmd+Shift+B -> Publish ERP Update (macOS + Android)
```

On macOS this combined publisher is the workspace's default build task, so the
shortcut starts it directly instead of relying on the last task selected in
VS Code. If an agent-created branch is not authorized for `Production` but its
HEAD is exactly the live `origin/smartpegas1.0` commit, preparation switches to
that canonical branch without changing the files. Any different or divergent
history still stops before dependency resolution, staging, commit, or push.

Its preparation task checks the desktop `Production` branch boundary, safely
fast-forwards a behind local branch when Git can do so without disturbing local
work, normalizes Flutter dependencies, stages all Source Control changes, and
creates at most one new commit. It then validates the latest prior successful
Android Actions evidence artifact and combines its exact commit with the latest
applicable macOS release. The older ancestral commit, or their one unique safe
merge base, becomes the common `Novedades` baseline; an expired, missing,
non-ancestral, or ambiguous Android history fails closed. Preparation uses that
range as the shared Gemini input boundary, pushes once, and writes a short-lived
schema-v2 exact-SHA handoff inside `.git`. Legacy candidate fields remain empty.
A diverged history or
overlapping local change stops before publication.
VS Code then waits for one exact-SHA `ERP Integrity Gate`: it
reuses the push-triggered run when present, or dispatches that gate once when
path filters created no run. A successful live run upgrades the handoff to
schema v3 with its run and attempt proof. Only then does VS Code start the
macOS and protected Android GitHub publishers in parallel in separate terminal
panes. Each publisher revalidates the clean checkout, branch, exact local
commit, live remote branch, note range, and proof binding;
each protected workflow independently queries GitHub Actions before building.

The two outcomes remain independent. A successful macOS publication is not
rolled back when Android fails, and a retry recognizes an already-published
macOS manifest for the same commit instead of creating another macOS release.
The same-commit Android retry is accepted only when its published manifest uses
the exact prepared `from_commit`, so valid-looking evidence from another range
cannot hide different `Novedades`.
Android signing material and the Supabase release credential remain only in the
protected GitHub `Production` environment. The Android terminal downloads and
validates a bounded Actions evidence artifact containing the exact final
Supabase manifest; it never receives those secrets.

### El recuadro de «Novedades» se escribe antes, o se pierde (2026-08-22)

El texto que ven los compañeros viaja **dentro del manifiesto firmado**, no en
el cuerpo del release de GitHub. Editar el release después no cambia nada, y el
manifiesto no se puede tocar a mano. Una publicación que salió con el texto
determinista —«Incluye ajustes y mejoras de estabilidad en…», que no dice
nada— sólo se arregla publicando **otra** versión, porque la siguiente
actualización arranca su rango en ese commit y ya no describe estos cambios.

Desde el 2026-08-24 la preparación **no llama Codex ni acepta un candidato
local**. Sólo fija el rango exacto; el job protegido genera el texto con Gemini
Flash. La variable durable de `Production` es
`GEMINI_RELEASE_NOTES_MODEL=gemini-3.1-flash-lite`. Si ese modelo deja de estar
disponible, el generador descubre una alternativa únicamente dentro de su lista
cerrada Flash/Flash-Lite. Si Google no responde, queda el fallback determinista
y la publicación sigue siendo segura, pero quien conduce una publicación que
exige texto IA debe comprobar en el log `Release notes source: ai`.

The normal developer action is the selectable VS Code task:

```text
Cmd+Shift+B -> Publish macOS Update (all changes)
```

It runs `scripts/publish_macos_update.sh` with the same low-friction operating
model as the Windows publisher:

1. Verify that the current branch may enter the protected `Production`
   environment.
2. Stage every Source Control change and create a timestamped commit when
   needed. A clean checkout publishes the already-committed branch head.
3. Resolve the exact prior-release range that protected Gemini will summarize.
4. Push that exact commit without switching branches or creating a worktree.
5. Reuse an active publish run for the same commit, or dispatch
   `.github/workflows/macos-release.yml` once with `publish_release=true`.
6. Wait with a concise elapsed-time status. If CI fails, print the failed job,
   failed step, annotations, and failed-step log directly in the task terminal.
7. After success, require the `macos-latest` manifest, immutable versioned
   release, workflow run ID, source commit, archive, checksum, signature, and
   installer to identify the same publication.

The standalone macOS task remains available for a macOS-only release. In the
combined task, prepared mode consumes the already-resolved shared notes range.
It skips only duplicate Git stage, commit, push, and range-resolution work;
protected CI, Gemini release-note generation, validation, signing, waiting,
failure diagnostics, and exact publication verification remain unchanged.

A same-commit application-test failure is reported immediately when the task
is retried; the qualifier does not run the same known failure three times.
Cancelled, timed-out, stale, or startup-failed qualification may rerun the same
GitHub run once. The standalone macOS task supplies no shared proof and keeps
the complete integrity gate as its safe fallback.

The protected `Production` job remains the final release-note authority. It
always creates a deterministic fallback, independently resolves the previous
macOS release, reconstructs the committed change inventory and evidence
catalog, and validates Gemini's exact range, schema, size, plain-text/privacy
rules, module ownership, and evidence IDs before signing. It maps opaque IDs
back to local changed paths only after validation.

Protected CI uses the Gemini API when the `Production` environment contains
`GEMINI_RELEASE_API_KEY`. The configured model is
`gemini-3.1-flash-lite`. If Google
reports that model unavailable or rejects its output-format contract, the
generator performs one metadata-free model-list request and retries only with
an available model from its fixed Gemini Flash/Flash-Lite allowlist. There is no
Codex or OpenAI provider fallback in the standard publication workflows.

Only sanitized, bounded release metadata is eligible for those protected-CI
provider calls: fixed canonical ERP module/topic labels, status and change
counts, and opaque evidence IDs. Commit subjects, commit SHAs,
raw/current/previous paths, source, diffs, credentials, generated bundles,
binary contents, customer data, and other personal or confidential information
stay inside the protected job. A missing key, timeout, exhausted quota, API
failure, invalid response, or rejected output leaves the validated
deterministic fallback in place. Logs expose only the selected source/model and
a fixed sanitized failure category, never provider error text, prompts, source,
diffs, or generated contents.

Google's free/unpaid Gemini service may use submitted inputs and generated
outputs to improve its products, and human reviewers may process them; release
metadata must therefore remain within this non-sensitive boundary. See the
[Gemini API Additional Terms of Service](https://ai.google.dev/gemini-api/terms).
The resulting JSON is validated and merged before the manifest is signed, so
displayed macOS notes belong to the same trust boundary as the archive.

The normal publish task no longer installs Node packages, resolves Flutter,
runs analyzer/tests, or compiles web locally before commit. GitHub Actions is
one authoritative release gate for the exact commit: it regenerates the tracked spreadsheet
assets, verifies that they match the commit, runs analyzer, the complete Flutter
test suite and the ERP web build. The paired task proves that gate once and both
platform workflows verify the proof live; the standalone task runs it inside
its own workflow. After qualification, CI performs the clean native macOS build,
bundle validation, packaging, signing, and protected publication. This removes
the duplicated macOS-only local gauntlet without bypassing any condition that
guards a coworker update.

`flutter analyze` and VS Code's Problems panel do not run the full test suite,
so a zero-error Problems count still cannot guarantee that CI will accept the
commit. If CI rejects it, the source commit remains pushed, no successful
promotion is reported, and the task shows the failing GitHub job/step. Fix that
specific failure and run the same task again, exactly as with Windows.

Pushes and ordinary dispatches are artifact-only. They build and verify but
cannot publish an update. Only the separate `Production` job has write access
to GitHub Releases and refreshes the `macos-latest` metadata alias.

Both the integrity gate and the macOS runner execute `npm ci` followed by
`npm run build:spreadsheet-engine` before Flutter. The generated Univer bundles
are tracked release assets; the integrity gate requires the pinned build to
reproduce the committed copies byte-for-byte. This guarantees that a clean
release includes the reviewed spreadsheet engine instead of depending on one
Mac's uncommitted output.

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
   path, signed **Novedades** content, relaunch, installed tag, and bundle
   version.
5. Exercise a deliberately invalid local package and confirm signature/hash
   rejection and rollback without publishing it.

Only after this canary should the internal update command be handed to Chile.

The `Novedades` button can only appear before restart once the currently
installed app already contains this UI. The first update that introduces the
feature bootstraps that capability; subsequent prepared updates can show their
notes in the ready prompt.
