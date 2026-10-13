# Avocado Pomodoro — native desktop shell

Offline AppKit + WKWebView app, transparent floating borderless window with a 380 × 580 base size. The timer is fixed at 65% (247 × 377); legacy size preferences are ignored. Settings and checklist windows keep independent readable sizes. The avocado body posts a native drag action; standard Edit shortcuts remain available in text fields. No npm or network dependency.

## Build/install (does not launch)

```sh
cd /Users/shenlan/Avocado-Pomodoro
./build.sh
```

Build requires the macOS Swift compiler, Python 3, Apple command-line tools (`sips`, `iconutil`), and the locally installed offline `rsvg-convert` renderer. Native tests compile `Main.swift` with `VisibleWindow.swift`, `LogStore.swift`, `TaskStore.swift`, and the selected test entry point; omitting those dependencies will not link. Tests compile and run first unless `POMODORO_SKIP_TESTS=1 ./build.sh` is used. The script builds, bundles `index.html`, `core.js`, and a generated triple-beep WAV, then ad-hoc signs and verifies `/Users/shenlan/Applications/Avocado Pomodoro.app`. If frontend files are missing, the native binary still builds and reports the missing files; rerun after frontend generation. `POMODORO_APP_PATH` can override the install destination. Installing does not restart an already-running instance; that process keeps its old native code until the user chooses to quit and reopen it.

## Obsidian checklist

Right-click the timer and choose **Checklist**. The separate 460 × 640 paper-style pixel window stays readable independently of timer scaling. It reads `/Users/shenlan/shenlan-lib`, groups Markdown tasks by source note and heading, and defaults to today's daily note when present. The note selector and All/Open/Done filter expose other tasks. Empty checkbox placeholders, templates, code fences and Pomodoro event logs are excluded.

Nested checkbox tasks retain their indentation, including when filtering hides their parent. Markdown HTTP/HTTPS links show their title and open in the default browser without changing the checkbox. Checking or unchecking requests a native write to the original note. UI state changes only after disk confirmation; conflicts show an error instead of silently overwriting a stale task. The view refreshes every three seconds while visible. This is local vault synchronization; Obsidian's own sync service controls propagation to other devices. The minus tab closes only the checklist panel. Drag the title to move it.

`node e2e-checklist.cjs` exercises the right-click entry, rendering, filters and check/uncheck bridge. `--qa-checklist` exercises real native check and uncheck on a scratch-only vault; it never modifies the user's tasks.

## Single-focus cycle and completion notes

Click the session-name input to choose a searchable vault task or enter a custom name. Task selection only copies the name; it never checks off or modifies the task. The picker has a separate search field and supports Arrow keys, Enter and Escape.

Choose **Minutes** before **Start Focus**: default **25**, whole minutes **1–180**. Invalid input cannot start a session. The chosen duration is captured at Start; later setup edits do not alter a running session or its completion note.

The flow is **manual Start Focus → choose Rest / Keep Going → manual next**. There are no groups, focus counts or long rests. Rest is fixed at **5 minutes**; no rest-duration input or modification API is provided. Previous preferences are ignored for new rests. A rest already in progress retains its saved deadline across reload. Natural focus expiry shows **Rest / Keep Going**. Rest starts a five-minute break. Keep Going continues the same focus with an overtime count until **End**, retaining pause/resume and the actual active duration in its log. Rest expiry shows **REST COMPLETE** and does not start another focus. Click **Next** to return to setup, then **Start Focus** to begin manually. Each phase start/completion reveals the timer, even when muted.

Deadlines use wall-clock time. A delayed tick or reload shows the pending choice without starting rest; it never manufactures extra focus cycles. Older saved groups restore their current phase and pending notes without resuming group automation. Old rest-duration and group preferences are discarded.

Completed-focus notes are optional and appear inside the dial while rest continues independently. **Timer** returns to live controls; **Notes (N)** reopens pending notes. **Save** logs the oldest completed focus; **Skip** discards only that note. Notes retain their captured name, event ID, timestamps, duration and draft across reloads and later manually started focuses. Nothing writes automatically. Saving or skipping a note cannot restart a finished rest or alter a live phase. Rest phases are never logged.

**End** stops a phase early. Ending a focus records actual active time excluding pauses and opens its optional note; saving/skipping retains the manual **Start Rest / Next** choice. Ending a rest shows **REST COMPLETE**. Pause/resume remains available.

`node --test *.test.cjs` covers the single-cycle transitions, custom plans, legacy migration, delayed ticks, pause accounting and persistence. `node e2e-cycle.cjs` covers automatic rest, stopped rest, manual next, retained notes and removed group settings. The `e2e-sequence-queue.cjs`, `e2e-sequence-reload.cjs` and `e2e-sequence-settings.cjs` filenames remain as regression entry points for notes, legacy migration and skin/sound settings; they no longer exercise groups. Browser saves are intercepted and native QA writes only in scratch.

### Pause notes

Pausing a focus session shows an optional textarea inside the dial. **Save Note** writes a pause event without completing or resuming the timer. **Resume** without saving writes nothing. Each pause has a durable event ID; retrying a failed save cannot duplicate the event. The draft and saved state survive app restart. Rest pauses do not create focus logs.

Pause entries use `[ ]` and `paused`; completion entries use `[x]` and `completed`. Both use the same concise layout: timestamp, planned and active duration, session name, status, and indented note lines. Active duration excludes paused time. Event and session IDs remain internal to prevent duplicates; they are not printed in Markdown.

Run `node e2e-pause.cjs` for inline notes, optional save, persisted state and retry checks. `--qa-pause` runs the real WKWebView → Swift → Markdown pause-save and later completion flow against the scratch log.

## Icons

`Assets/status-icon.svg` is an exact copy of the supplied `30-颜色-番茄红.svg`. Build renders its original black silhouette at 18/36 pixels; AppKit displays the 2× raster as an 18-point template, adapting to light/dark menu bars without recoloring the source. `Assets/app-icon.png` is the exact supplied 1024-pixel tomato artwork. Build uses `sips` and `iconutil` to create `AppIcon.icns` at the standard 16–1024 pixel sizes in scratch; the plist declares it as the app icon. Original assets are also bundled. No network or image-generation dependency is used.

`node --test icons.test.cjs` checks metadata, template setup and byte-for-byte source preservation. `--qa-visibility` also verifies the installed native menu image is present, templated and 18 × 18 points. Finder may retain an icon cache until the next launch; building does not relaunch the normal app.

## Skins

Right-click the character and choose **Settings…** to open a separate, fixed-size 330 × 530 pixel-style settings window. Its 14px controls do not scale with the timer. The **Language** selector in Settings switches between **English** (default) and **简体中文**. Changes apply immediately to the timer, task picker, settings, checklist, accessibility labels, and native menus. The choice persists across app restarts. Switching languages preserves running deadlines, task names, note drafts, and existing log contents. Native error details remain in their original language. Skin and completion sound are saved automatically. **Focus prompts** accepts one candidate per line and saves automatically. Focusing the name input before Start shows one random candidate in a pixel dialogue; the same candidate remains for that setup and disappears on Start. Each new focus setup picks again. Empty candidates use a default encouragement. The widget has no toolbar or close button. Double-click the character or a noninteractive area of the dial to hide only the timer window; its countdown continues. Inputs, note fields and buttons retain their normal double-click behavior. Dragging never docks or half-conceals it, and no idle timer moves it. Dragging beyond a screen boundary clamps the entire widget into the nearest visible screen. The macOS menu-bar **◷ → Show Timer** brings the timer forward without changing its size or state. Completion reveals the window even when sound is disabled. The menu-bar menu also offers settings and quit.

Skins keep the dial geometry and controls unchanged. Kirby uses the broad-bodied coarse-pixel SVG artwork with visible hands and a separate decorative tongue behind the dial controls.

### Visibility and panel controls

Double-click hides the floating timer without pausing, resetting or quitting. The menu-bar **Show Timer** restores it manually. There are no docking or idle-hiding controls. Settings retains its Done control and checklist its minus tab; each closes only its respective panel. Phase starts/completions still bring the timer forward, including with sound off.

Run `node e2e-english-settings.cjs` and `node e2e-visibility.cjs` for English settings and double-click hide/reveal regressions. `--qa-settings` verifies fixed-size native settings and the live preference bridge; `--qa-visibility` verifies double-click hiding, muted focus/rest expiry automatically revealing the native window, unchanged frame, boundary clamping and no movement after eleven seconds idle. `--qa-ui` checks context-menu controls and completion reveal.

Run `node e2e-language.cjs` to verify live switching, preference messages, reload persistence, timer/draft preservation, translated completion feedback, picker/checklist copy and settings bounds. `build.sh` also runs isolated native language preference and menu translation tests and bundles `i18n.js`.

## Native bridge

`window.webkit.messageHandlers.native.postMessage({action, ...payload})`

- `drag`: AppKit window drag, using the current mouse-down event or a synthesized event.
- `alarm`: three beeps, repeated every two seconds for at most fifteen seconds.
- `silence`: stops sound immediately. System output volume and mute remain unchanged.
- `hide`: hides only the timer window; accepts messages from the timer webview and leaves the timer running.
- `reveal`: restores and brings the timer forward on every phase start/completion, including when muted.
- `save`: fields `id`, `name`, `note`, `startedAt`, `completedAt` (timestamps are JS epoch milliseconds), optionally `plannedSeconds` (whole-minute seconds, 60–10800; omitted means legacy 1500), `elapsedSeconds` (integer) and `endedEarly` (Boolean). Completion and pause saves send their own captured plan, never the current setup value or another live phase's duration. Early finishes require both `endedEarly:true` and an explicit active duration.
- `close`: persists the frontend timer, fires lifecycle events, and terminates.

Save calls `window.nativeResult({ok:true,id})` or `{ok:false,id,error}` through JSON serialization, never string interpolation of raw user input. Top-level local-file messages only; navigation stays within bundled resources.

## Log semantics

Normal default target:

`/Users/shenlan/shenlan-lib/Pomodoro/pomodoro-log.md`

Append logs directly to this Markdown file. Normal launches can override the file with `POMODORO_LOG_PATH`; QA always ignores that override.

```markdown
- [x] YYYY-MM-DD HH:mm — 25 min planned, 25:00 elapsed — "name" — completed
  - Optional note line
  - Another note line
```

Timestamp is the completion time in the local timezone. Requires a nonempty ID/name and finite, nonnegative, ordered timestamps within the supported calendar range. Plans must be whole minutes from 1 to 180. Normal completions require at least the planned wall time and record the actual active duration, including overtime; an explicit shorter active duration requires `endedEarly:true`. Legacy payloads omitting the plan default to 1500 seconds (25 minutes). Early finishes can have shorter (including zero) wall time and record the provided active duration as `mm:ss`. Every explicit duration must be nonnegative and no more than wall time plus a one-second rounding tolerance. Both pause and completion headings show the captured planned minutes. Pauses can extend wall time without increasing active duration. Breaks are not logged. Titles flatten newlines and escape quotes/backslashes. Existing bytes are preserved; a newline is inserted only when needed before appending.

Adjacent `.state.json` and `.lock` sidecars provide durable ID deduplication, crash-recoverable write transactions, and exclusive locks across app instances. Do not delete sidecars while a save is in flight. A journal conflict or unreadable/corrupt sidecar fails safely instead of rewriting the user's log. External editors do not participate in the lock, so avoid concurrent external edits during a save.

All standalone log tests inject unique scratch-directory targets, remove them afterward, and never write to the user's log.

To run native scale/QA-script tests plus all log tests without building, installing, or launching the app:

```sh
TEST_BINARY="$(mktemp "$TMPDIR/avocado-shell-tests.XXXXXX")"
swiftc -D NATIVE_SHELL_TESTS -parse-as-library Main.swift VisibleWindow.swift LogStore.swift TaskStore.swift LogStoreTests.swift -framework AppKit -framework WebKit -o "$TEST_BINARY"
"$TEST_BINARY"
rm -f "$TEST_BINARY"
```

Scale tests use a unique UserDefaults suite, not the app's preferences. `build.sh` continues to run the standalone LogStore suite.

## Explicit native QA mode

After permission to launch:

```sh
open -n '/Users/shenlan/Applications/Avocado Pomodoro.app' --args --qa
# Two-minute early finish through the same real bridge:
open -n '/Users/shenlan/Applications/Avocado Pomodoro.app' --args --qa --qa-early
```

`--qa` enables accelerated normal-completion testing; `--qa-early` also enables isolated QA even when used alone. Early QA starts a named focus block two minutes in the past and calls `timer.finish(now)` rather than the normal full-duration tick. QA uses a nonpersistent WKWebView data store, does not read/write the user's saved scale or window frame, and starts at 0.65. After web load it applies the fixed 0.65 scale, captures DOM widget bounds and native content dimensions, then restores 0.65 before injecting the timer. It renders/flashes the dial, starts native sound, sets a two-line note, and clicks the real inline log button after 2.2 seconds. It tests the real WKWebView → Swift → Markdown → JS callback path. It does **not** terminate automatically, so the UI can be inspected.

QA writes only beneath:

`/Users/shenlan/.hermes/cache/scratch/pomodoro-native-qa/`

- `pomodoro-log.md` plus journal/lock sidecars
- `result.json`: callback status/ID, exact log target, read-back Markdown, sound playback acceptance, JavaScript errors, resolved frontend state/feedback, `endedEarly`, and `scaleChecks`. Each scale check contains `level`, `nativeWidth`, `nativeHeight`, measured `widget` bounds/viewport/selection, `ok`, and `error`. Verify every reported scale check is `ok:true` (the fixed-size QA reports the 0.65 level); callback success alone only proves the log save.

`--qa-visibility` verifies double-clicking hides the native window without moving it, hidden focus/rest timers automatically reveal on expiry even when muted, screen-boundary placement stays fully visible, and eleven seconds idle does not move or hide it. `--qa-cycle` verifies fixed five-minute rest without an editing API, verifies focus expiry starts rest and rest expiry stops, saves the captured focus note without restarting the timer, then checks only a manual Start begins the next focus. Both report `ok:true` in the scratch `result.json` on success.

`node e2e-custom-focus.cjs` covers setup default/range validation, compact bounds in both skins, custom focus persistence, snapshot saves and pause payloads. `node e2e-name-picker.cjs` covers read-only options, provenance, safe rendering, searching, keyboard selection, custom names and viewport bounds. `node e2e-picker-source.cjs` covers a saved custom name, a separate search field, focus opening, explicit load errors versus empty state, read-only selection and viewport bounds. `node e2e-visibility.cjs` covers double-click hiding, preserved control interactions and focus/rest completion reveal with sound on/off. These browser tests require Node.js and Playwright at `/Users/shenlan/.hermes/cache/scratch/pomodoro-qa/node_modules/playwright`; the installed app itself has no npm dependency.

`--qa-cycle` chooses 42 through the real setup and Start button, changes the setup to 7 without altering the active focus, verifies the captured `42 min planned, 42:00 elapsed` native note, and confirms rest never starts another focus automatically. Accelerated expiry uses the same `tickTimer()` transition path as normal operation. `--qa-picker` loads both the checklist and timer picker from the same scratch-only `picker-vault`, containing open and done tasks. It verifies the picker identities equal all checklist open-task identities, a prefilled custom name does not filter them, selection starts the captured 42-minute focus, and the fixture bytes remain unchanged. Normal launches use the actual `/Users/shenlan/shenlan-lib` TaskStore shared with the checklist; QA fixture paths are never used in normal mode.

The report is also printed with `NATIVE_QA_RESULT` to stdout when launching the executable directly. `soundPlaybackAccepted` means NSSound accepted playback, not proof that a human heard it. Quit only the QA instance; do not interrupt an already-running normal app. Repeated QA runs append fresh IDs; no normal localStorage or user log is touched.

The app has not been launched by the build script. Native QA requires an explicit launch by the parent/user; compiler and log tests alone do not verify window dragging, audible output, or the live WKWebView bridge.
