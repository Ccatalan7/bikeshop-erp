# Driving the app and reading Design from an agent session

Everything an agent needs to verify UI work on this repository **without**
10-minute rebuilds, without asking the owner to click, and without
re-discovering the same five traps. Read this before touching UI.

Verified working on 2026-07-30 (macOS 25.5, Flutter 3.38.5 via FVM).

> **El procedimiento vive en
> [`AGENT_VISUAL_WORKFLOW.md`](AGENT_VISUAL_WORKFLOW.md).** Este archivo
> es la referencia de cada herramienta y de las trampas que encierra.
> Si vienes a probar la app o a compararla con un frame, empieza por allá.

## The three surfaces, and when to use each

| Surface | Loop | Use it for |
|---|---|---|
| **macOS debug session** (`scripts/dev/native_session.sh`) | hot reload 2–5 s | Default for every desktop/tablet UI round. Real data, real services. |
| **iOS Simulator** (`mcp__Claude_Code_iOS_Simulator__control`) | build once, then tap/screenshot | Phone layouts, touch targets, safe areas, keyboard insets. |
| **Web preview** (`scripts/dev/web_preview.sh`, see `WEB_PREVIEW.md`) | release build ~10 min | Only when the browser is the point. Not an iteration loop. |

## 1. macOS debug session — the main loop

```bash
scripts/dev/native_session.sh start      # ~1-2 min the first time
scripts/dev/native_session.sh reload     # after edits · ~2-5 s
scripts/dev/native_session.sh restart    # state reset · ~3-5 s
scripts/dev/native_session.sh errors     # compile errors / exceptions
scripts/dev/native_session.sh status
scripts/dev/native_session.sh stop
```

The session lives in a detached `screen` named `payroll`. The owner can take
it over at any time with **`screen -x payroll`** (`Ctrl+A`, then `D` to
detach). Both sides share the same terminal, so nobody has to hand over.

Four traps this encodes, each of which cost a full round when hit:

1. **Never pipe `flutter run` to `tee`.** Losing the TTY silently disables the
   single-key commands: `r` does nothing, forever. Logging goes through
   screen's own `logfile` directive (macOS ships screen 4.x, which has no
   `-Logfile` flag — it must come from a `screenrc`).
2. **Keys need `-p 0`:** `screen -S payroll -p 0 -X stuff 'r'`. Without the
   window selector the keystroke is swallowed.
3. **One session at a time.** If VS Code is running its own debug session,
   stop it first (⏹). `start` refuses instead of creating a second one.
4. **A hot reload rebuilds the routed page**, so the module returns to its
   default scope. Re-navigate before judging what you see.
5. **A wedged incremental compiler looks like a dead session, and isn't**
   (2026-07-31). Symptom: `reload` times out, the log freezes mid
   `Performing hot reload... ⣷⣯`, and **the app keeps running and answering
   screenshots** — so every capture shows the OLD code and nothing you write
   ever appears. `flutter run` never reports it. More reloads do nothing.

   Run **`native_session.sh doctor`**, which names the cause instead of
   guessing: it checks whether the log is still growing, asks the VM service
   for a real `reloadSources`, and prints `COMPILADOR TRABADO — Error while
   starting Kernel isolate task` when the kernel task is stuck. The only fix
   is restarting the process: `native_session.sh stop && native_session.sh start`.

   Do **not** blame `screen -ls` saying `(Attached)`. An attached owner does
   NOT block reloads — that misreading cost a full round on 2026-07-31, and
   `doctor` now prints the attach as informational precisely so nobody
   confuses it with the cause again.

### Verifying dark and compact without leaving a trace

Both are required before a surface is declared done, and both are reachable
from the same session:

- **Dark**: Configuración → Apariencia → `Oscuro`. It writes the owner's
  persisted preference, so **put it back on `Claro` when you finish** — the
  app is theirs, not a test rig.
- **Compact (390)**: resize the window instead of booting the Simulator when
  you only need the composition:

  ```bash
  osascript -e 'tell application "System Events" to tell (first process whose unix id is <PID>) to set size of front window to {430, 928}'
  ```

  `app_control.sh geometry` prints the pid and confirms the new size, and the
  compact shell (drawer + pills) engages exactly as on a phone. Restore
  `{1672, 928}` afterwards. Use the Simulator when what you need is touch
  behaviour or the real safe areas, not just the breakpoint.

## 2. Eyes and hands on the running app

```bash
scripts/dev/app_control.sh shot out.png      # the app's own rendered frame
scripts/dev/app_control.sh geometry          # pid · window · frame size
scripts/dev/app_control.sh click X Y         # current `shot` only; never reuse
scripts/dev/app_control.sh scroll X Y -5
scripts/dev/app_control.sh drag X Y X2 Y2
scripts/dev/app_control.sh type "texto"
scripts/dev/app_control.sh key 36            # 36 return · 53 esc · 48 tab
```

### Tap by identity; pixels are a one-frame fallback (2026-07-31)

```bash
scripts/dev/app_control.sh find --label "Confirmar semana"
scripts/dev/app_control.sh find --key payroll-confirm-week
scripts/dev/app_control.sh tap  --key payroll-confirm-week
```

**Why a reused `click X Y` keeps missing.** `shot` returns physical pixels —
1360×757 on one run, 3024×1632 on a Retina display, 2312×1410 after a resize —
while Flutter hit testing uses logical coordinates. The script bridges those
spaces for the **current** frame: the normal app backend queries the live DPR
and divides the physical frame coordinates before creating `PointerEvent`s;
the OS backend maps the same physical pixels into the current window and title
bar. That translation does not make a saved coordinate durable. Navigation,
layout, resize, display/DPR changes or an app restart can move the target, so a
coordinate read from an earlier capture is stale. On an app running against
**production**, reusing one caused the 2026-07-30 navigation tap to land on
`Quitar de la semana` and write for real.

`find` resolves the target from the live element tree by `ValueKey<String>` or
by semantic/`Text` label, and prints its real rectangle in logical coordinates.
`tap` locates and taps in one step, and **prints what it hit** — so you keep
awareness of where the event landed instead of inferring it.

Three properties that matter:

- **Ambiguity is an error, not a coin flip.** With more than one candidate
  `tap` refuses and lists them. `--index N` is a zero-based integer into that
  list; a missing index for multiple matches, non-integer, negative, or
  out-of-range value is rejected before any pointer event is sent.
- **The target must be live and usable now.** Its chosen point must be inside
  the current logical viewport and its branch must win the live hit test.
  Offstage, ignored, absorbed, semantics-disabled, disabled-button, covered,
  off-viewport, detached, and zero-size candidates are not returned.
- **Coordinates expire.** If an identity does not exist, take a fresh `shot`
  and use its point immediately. Never carry a coordinate across navigation,
  layout changes, resize, display/DPR changes, reload, or restart.

Keep `click X Y` for what has no identity — a canvas, a chart, a spot inside an
image — and for testing the OS event path itself. For anything with a key or a
label, use `tap`; never reuse a coordinate from an earlier frame.

### Two ways of seeing, and they answer different questions

```bash
scripts/dev/app_control.sh shot out.png          # cómo se VE
scripts/dev/app_control.sh read                  # qué ESTÁ
scripts/dev/app_control.sh read --filter pagar
```

`shot` returns the exact rendered frame through the VM service — real pixels,
not a photo of a screen. It is the only way to judge design fidelity, and it
stays mandatory for that: comparing a frame against the app is what this whole
contract is built on.

But a picture does not say what *is*. Whether a button is disabled, a row
selected, a field focused, a disclosure open — reading those off colour is
inference, and inference is how an agent ends up asserting something false.

`read` walks the **semantics tree**, the same structure Flutter hands to
VoiceOver, so it reflects the app as a person who is not looking at it receives
it. It prints label, value, state flags and size, indented by hierarchy, and
costs text instead of an image. `--filter` narrows it to one region.

Use both: **structure from `read`, appearance from `shot`.** When they
disagree, the semantics tree is what a screen reader will announce — that
disagreement is itself the bug.

### Two input backends — the default does not touch the owner's cursor

`click`, `scroll` and `drag` are delivered **inside the app** by default, through
the debug service extensions in `lib/dev/agent_input.dart`. They hand synthetic
`PointerEvent`s to `GestureBinding`, the same way widget tests do.

| | default (`app`) | `APP_CONTROL_BACKEND=os` |
|---|---|---|
| Owner's cursor | untouched | **moves — you fight over one mouse** |
| Window focus | not required | required, and stolen |
| Installed build stealing clicks | impossible | a real trap |
| Proves the OS event path | no | yes |

The default exists because the agent and the owner previously shared one
physical pointer: either could land a click in the middle of the other's
gesture. Now the owner keeps using the Mac while the agent drives the app, even
with the window in the background.

Use `APP_CONTROL_BACKEND=os` only to test the OS path itself — a window that
receives no events at all is invisible to synthetic pointers, by construction.

The channel is registered from `main.dart` behind `kDebugMode`, so no release
build exposes it. A build that predates it simply lacks the extension and the
script falls back to CGEvents on its own.

How the CGEvent backend works, and why it is not obvious:

- **`shot` goes through the Dart VM service** (`_flutter.screenshot`), so it
  returns exactly what the engine painted. No Screen Recording permission, no
  other window can cover it, and it works while the app is in the background.
  `window` uses `screencapture -R` instead when you need to see native chrome.
- **Clicks are CGEvents.** AppleScript's `click at` is accepted and then
  ignored by the Flutter window — it looks like nothing happened. The Swift
  driver in `scripts/dev/mouse_events.swift` posts real HID events; the script
  compiles it on demand into `.tmp/dev-tools/mouse`.
- **Coordinates begin as physical frame pixels** — the same numbers read from
  the current `shot`. The default app backend queries the live DPR and converts
  them to Flutter logical coordinates. The CGEvent backend independently maps
  them into current window points and offsets Y for the title bar. Neither
  mapping permits coordinate reuse after the rendered state or geometry moves.
- **Always target the debug app by executable path**, never by process name.
  An installed build (`~/Applications/Vinabike`) shares the name
  `vinabike_erp`; targeting by name silently drives the old app and every
  observation is wrong. If two windows appear, check
  `pgrep -f build/macos/Build/Products/Debug`.

### macOS permissions (one time, by the owner)

`System Settings → Privacy & Security → Accessibility` must list **both**
Claude entries:

- `Claude` — the desktop app.
- `claude` (lowercase) — the Claude Code helper at
  `~/Library/Application Support/Claude/claude-code/<version>/claude.app`.
  **This is the one that actually runs the agent's shell**; with only the
  uppercase entry enabled every call fails with
  `osascript is not allowed assistive access (-1719)`.

Screen Recording is only needed for `app_control.sh window` and for reading
the Design window.

## 3. Looking at Claude Design — never for values

> **Values come from `DesignSync`, not from this window.** Colour, radius,
> shadow, border, spacing, font and height are read out of the Design file with
> `DesignSync get_file`, which returns them literally. Reading them off a
> capture, or estimating them, is prohibited — see
> [`DESIGN_HANDOFF_SYNC_CONTRACT.md`](DESIGN_HANDOFF_SYNC_CONTRACT.md), which is
> the norm this section is subordinate to.

This window is for exactly two jobs:

1. **Seeing what the file API truncates.** A canvas page is capped at 256 KiB;
   sections past the cut exist only here. Anything taken this way is marked
   unsourced in the code until it can be read from a file.
2. **Confirming a built result** against the design, the same way app
   screenshots confirm a change.

```bash
scripts/dev/design_window.sh shot
scripts/dev/design_window.sh scroll -8
scripts/dev/design_window.sh pages       # page selector, then Esc to close
```

Design is a **window of the Claude app**, so it is raised by window name and
captured by frame. Two absolutes:

- **Never capture the full screen.** The desktop holds unrelated private
  windows (mail, chats). Capture the Design window's frame only.
- **Read-only.** Typing into Design's composer or sending a message is acting
  on the owner's behalf and needs explicit permission each time.

**The trap this section exists to prevent** (2026-07-30): an agent walked this
window with `shot`/`scroll` to "see" a popover, then wrote a surface out of its
own head — wrong shadow, wrong radius, and a shadow nested inside a clipping
`Material` so it never painted at all. One `get_file` on the component guide
returned the real ladder in seconds:
`popover 0 6px 22px rgba(12,37,55,.13)`. Scrolling to look is slower *and*
wrong.

### Sending a prompt to Design (only with per-message permission)

When the owner explicitly asks for a prompt to be typed and sent, paste it —
never `osascript … keystroke` the body, which mangles anything non-ASCII.

```bash
printf '%s' "$(cat prompt.txt)" | \
  __CF_USER_TEXT_ENCODING=0x1F6:0x8000100:0x8000100 pbcopy
osascript -e 'tell application "System Events" to keystroke "v" using command down'
```

**The accent trap, with its real cause.** This account's
`__CF_USER_TEXT_ENCODING` is `0x1F6:0x0:0x0` — the trailing `0x0` is
**MacRoman**. `pbcopy` puts the correct UTF-8 bytes on the pasteboard but
*declares* them MacRoman, so Design renders `CORRECCIÓN` as `CORRECCI√ìN` and
`además` as `adem√°s`. `pbpaste` round-trips fine and hides the bug — the
bytes were never wrong, only the declared flavour. Override the variable on
the `pbcopy` call itself (`0x8000100` = UTF-8); exporting it later is too
late. This cost a full round on 2026-07-30 and again on the T8 prompt.

Two more things worth knowing: a long paste lands as a **"Pasted text"
attachment chip**, not inline text — that is normal and Design reads it; and
if a bad paste is already attached, remove it with the chip's `✕` before
pasting again or the message goes out twice.

## 4. iOS Simulator — phone verification

Use the `mcp__Claude_Code_iOS_Simulator__control` tool. Order matters:

1. `attach` **first** — it opens the live panel instantly on a booted device
   and surfaces the one-time device-access prompt while the owner is present.
   On a cold machine it returns a clear error; boot or build, then retry.
2. `build` (`mcp__Claude_Code_iOS_Simulator__build`) or the repo's own build
   command produces the `.app`.
3. `launch` with the built `.app` path.
4. `screenshot`, `tap`, `swipe`, `text`, `touch_path` to drive and verify —
   these are headless and do not need the panel.

Notes that save time: coordinates are **device points**, origin top-left, and
`launch` reports the device's point size. A `swipe` starting within 4 pt of an
edge performs the OS gesture (back, notification shade, Control Center), not a
drag — start further in when scrolling content near a bezel. The Simulator
cannot be replaced by resizing the macOS window when what you are checking is
touch targets, safe areas or the software keyboard.

This tool drives **simulators only**. "On my iPhone" means building for the
device with the normal toolchain; say so instead of silently using a simulator.

## 5. Cost discipline

The mechanism is cheap; **looking** is what costs. A screenshot is ~2 k
tokens of context, a hot reload is a few hundred bytes of log.

- Verify by text first: `flutter analyze`, the focused suites, and
  `native_session.sh errors`. Hundreds of these fit in one screenshot's budget.
- Capture only when the judgement is visual: layout, hierarchy, colour,
  density, overflow.
- Navigate blind, capture at the end. Do not screenshot after every click "to
  see if it worked" — the next capture already proves it.

## 6. What still needs the owner

- Granting the two Accessibility entries (once).
- Stopping their own VS Code debug session before the agent starts one.
- Any real financial mutation, deploy, commit or push.
- Anything typed into Design, or any message sent on their behalf.
