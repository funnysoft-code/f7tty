# F7TTY native workspace preview

Local development preview, not a daily-driver release. Native AppKit host with pinned GhosttyKit and real PTYs. FunnySoft's original vector logo is white on a padded, shaded black tile. The FunnySoft site and the original running scratch prototype are unchanged.

## Run

```sh
python3 build-app.py
open dist/F7TTY.app
```

Requires Apple Silicon, macOS 14+, and Xcode. No install or notarization. The built app is ad-hoc signed.

Python 3 and Git are required. The first build clones `https://github.com/briannadoubt/GhosttyKit.git`, checks out `f3756807a61a42dba3dc1d866a1fd865f1ddfe21`, and applies the two wrapper patches in `patches/`. This requires network access. Later builds validate the revision, origin and exact patch diff locally before invoking Swift. The checkout and build output are ignored by Git.

Run `python3 dependency-bootstrap.py` to prepare or validate the dependency without building the app. Existing checkouts with a different revision, origin, missing patches, staged changes, untracked files or additional tracked edits are rejected, not reset or repaired. Ignored dependency build artifacts are allowed. A failed initial clone or patch application may leave a checkout that needs manual inspection. No files from the original scratch prototype are required.

- Bottom-left plus: create a folder-backed workspace or a session.
- Command-T: create a session in the selected workspace.
- Command-D: split the focused pane right. Command-Shift-D: split below.
- Command-Shift-Return: maximize or restore the focused pane without replacing its terminal.
- Control-Tab / Control-Shift-Tab: focus the next / previous pane.
- Command-Shift-Equals: reset each split divider to its midpoint.
- Command-Option-arrow: focus a visible neighboring pane by its position without rearranging the layout.
- Command-Shift-Option-arrow: move the focused pane relative to its adjacent tree-order pane.
- Command-B: show or hide the sidebar. Command-comma: open Settings; Escape returns to the terminal.
- Command-K: search sessions, projects and available commands. Arrow keys select, Return activates and Escape dismisses without replacing the terminal.
- Command-F: search the focused terminal. Return / Shift-Return and Command-G / Command-Shift-G navigate matches. Escape closes Find.
- Command-Option-B: collapse folders without hiding the selected terminal. Hover a folder for its new-session button or a session for its remove button.
- Drag pane headers to an edge to nest a split, or the center to swap panes. Native drag cancellation leaves the model unchanged.
- Drag split dividers to resize. Header menus close individual panes or sessions.
- Sidebar: select a session; others remain alive but hidden. Right-click to rename or remove workspaces and sessions.
- Drag folders relative to folders, or sessions relative to sessions, to reorder. Cross-folder session moves preserve the session directory, pane identities and selection. The insertion line previews the destination; the saved order also determines Command-1 through Command-9.
- The toolbar bell shows recent explicit terminal bells, terminal notifications and exit events. It does not infer agent activity from output or idle shells. The in-memory history is bounded to 50 events, initially showing six with an action to browse the full scrollable history or clear it. Events whose terminals have closed remain readable but cannot be activated.
- Red close and Command-Q: confirmation, then terminate current app descendants and free terminal surfaces.
- Command-W closes only the focused terminal pane, with the same close confirmation. The Window menu also provides native minimize and zoom actions.
- Copy and Paste use the native Edit menu. Terminal-controlled clipboard access is disabled in this prototype.

Workspace names, directories and layout trees are saved atomically to `~/Library/Application Support/F7TTY/workspace-state.json`. An ordered background writer keeps one active write and the latest pending snapshot. Divider changes update the model immediately and debounce persistence for 200 ms; confirmed app termination flushes pending saves. Reopening starts fresh shells when a session is first selected. Commands, terminal transcripts and live processes are not restored. Invalid saved state is retained and blocks further saves rather than being overwritten.

This is a workspace preview, not a claim of exact Unpeel parity. The gear opens in-window Appearance settings with System, Light and Dark modes, workspace background colors, a background-opacity slider and reset. Color follows the selected workspace and is stored with its layout; Default restores the approved continuous dark sidebar treatment. Lower opacity reveals native macOS blur while terminal surfaces stay opaque and retain their dark terminal theme. Normal launches save appearance preferences; smoke tests and disposable previews do not. Full appearance options, cross-session pane transfers and agent-specific activity integration remain pending. The development app uses bundle ID `pt.funnysoft.f7tty.development` so it does not replace the original prototype.

### Separate interaction preview

```sh
python3 build-app.py --output dist/F7TTY-Polish.app
open -n dist/F7TTY-Polish.app --args --ui-preview
```

This separate bundle does not replace an already running development app. `--ui-preview` starts a disposable workspace without reading or writing saved workspace state. Normal shells still run their startup files. Do not rebuild a bundle while using it; quit only the disposable preview first.

Terminal panels use a black background with zero terminal padding and content flush to the pane edges beneath the header. Closing the last session keeps the workspace sidebar and a rounded, bordered empty panel with the F7TTY logo, session guidance and app version. Use `--empty-preview` instead of `--ui-preview` to inspect that empty state without loading saved workspaces.

The interaction pass fixes pane headers claiming clicks outside their bounds, adds 28-point button layouts with hover/pressed feedback, keeps buttons out of the terminal focus chain, updates maximize/restore labels and shortens shell titles. A 300-point sidebar and top-aligned panes follow the Unpeel reference more closely. Reparenting uses a transaction with implicit layer animation disabled; clicking the selected session does not rebuild its layout.

Peekaboo verified split creation, divider resizing, header dragging to a bottom split, maximize state feedback and sidebar hiding in the revised app. Full animation acceptance, drag cancellation, all keyboard routes and first-click behavior across inactive windows remain to be checked. A shell startup warning seen in the original preview did not reproduce in the isolated preview; no user shell configuration was changed.

Additional native checks verified directional keyboard focus, folder collapse/expansion without terminal replacement, folder-hover session creation, Find query highlights and match navigation, command-palette filtering and Settings activation, and Escape dismissal. Find restores terminal focus only while its own field still owns the keyboard, avoiding focus theft from another field or pane after a delayed close callback. Unit tests cover that ownership boundary. Peekaboo also verified session drag reordering, readable Light/Dark settings, and both populated and empty activity panels. A real shell BEL populated the inspected panel; clearing it updated the empty state and Escape dismissed it. Command-W removed the focused bottom-right test pane while both other panes and the window survived. That last test used smoke mode, which bypasses confirmation. Full-history scrolling and event selection still need native verification.

Appearance mode now propagates to existing and newly created Ghostty surfaces through the engine's color-scheme API, while F7TTY's terminal.conf remains an explicit dark terminal theme by default. Workspace app colors affect the approved native chrome without rebuilding live terminal sessions. The remaining product-level differences are intentional or require Unpeel's private agent metadata, such as live agent titles, agent activity, remote control, transcripts, worktrees and MCP screens.

## Checks

```sh
python3 dependency-bootstrap.py
swift test
swift build -c release --product F7TTY
.build/release/F7TTY --smoke-test
clang -I Sources/ProcessOwnership/include test-cleanup.c Sources/ProcessOwnership/ProcessOwnership.c -o .build/test-cleanup
.build/test-cleanup
```

The smoke test launches disposable `zsh -f` terminals, enters a command through terminal input, reads the resulting output, creates more surfaces, checks identity across zoom/move/session switching, checks nested pane dimensions and quits. It does not load or save workspace state. Optional `--capture-directory dist` captures only the test window for visual inspection. Adding `--inspect-smoke` leaves a successful smoke run open with its real activity event for native inspection; its terminals remain disposable and confirmation is bypassed. It does not prove OpenCode compatibility or battery savings.

Tests cover directional splits, removal, edge moves, center swaps, invalid drops, zoom, serialization, validation, atomic replacement, invalid-state retention and header hit-testing/button focus behavior. Escape cancellation, keyboard routing and close/reopen behavior still need an attended acceptance pass. The 2026-09-08 efficiency changes received an independent seven-lens code review with no confirmed introduced defects (review run `20260908-061648-cc75cca4`).

A narrow-pane regression test exposed Find navigation buttons compressed to half a point. Find now keeps 20-point controls, hides the secondary match count in narrow panes, and restores it when space returns. Peekaboo verified both states at 650- and 1200-point window widths with two side-by-side terminal panes.

## Prototype safety limits

Use disposable commands only. Shutdown repeatedly discovers descendants during its 350 ms grace period using libproc and verifies PID plus start time before signalling. Each newly observed descendant receives TERM, followed by KILL for surviving observed identities. A regression test covers a child forked by a TERM handler; the former single-snapshot implementation fails it. This remains best-effort: processes detached before discovery, or created and reparented between scans, can escape observation. Production requires stronger lifetime ownership before accepting the promised kill-all contract. A crash or SIGKILL bypasses app shutdown. No daemon or automatic command restoration is installed.

The host loads only bundled terminal.conf. It does not load or rewrite the user's Ghostty config. Shell startup files may still run during ordinary interactive use, as in other terminals.

## Dependency record

- GhosttyKit: `f3756807a61a42dba3dc1d866a1fd865f1ddfe21`.
- Declared upstream Ghostty: `54ac5fd21e5eeef5e910f7f646934dc58fd373f8`, 1.3.2-dev, Zig 0.15.2.
- Vendored arm64 static archive SHA-256: `3ed3fcad1aad09cd82cbb6aac305eeb9b99a18174ef495db75ba062d3f3f4371`.
- Source-linked prebuilt artifact, not independently reproduced or attested. Build from reviewed upstream source before distributing a product.
- MIT licenses remain in the dependency checkout. Audit bundled third-party notices before distribution.

Local wrapper changes isolate configuration, avoid recurring updateLayer invalidation, skip unchanged size updates, gate host drawing on visibility, resolve action targets before asynchronous dispatch, and add explicit surface cleanup. These are prototype changes, not an upstream PR or a diagnosis of Unpeel.

## Performance status

The efficiency branch adds an opaque composition path at 100% background opacity. Lower opacity attaches the native blur view; returning to 100% removes it and fills the root and window. Automatic terminal-title changes update the existing sidebar row, and sidebar toggles change constraints without rebuilding the pane hierarchy. Short Find queries debounce for 300 ms; navigation flushes the current query, and closing Find cancels pending work.

### Reproducible, disposable measurements

```sh
python3 build-app.py --output dist/F7TTY-Efficiency.app
python3 Scripts/measure-efficiency.py --app dist/F7TTY-Efficiency.app --output dist/measurements/opaque
python3 Scripts/measure-efficiency.py --app dist/F7TTY-Efficiency.app --output dist/measurements/legacy --legacy-composition
```

Each command launches a disposable `--benchmark` workspace with bundled Menlo 13 configuration and deterministic terminal output. It settles for five seconds, then samples for a full minute by default. Keep the test window visible without typing, scrolling or switching apps. Output is buffered until the capture ends. The script records raw GPU samples, process CPU-time deltas, system CPU ticks, foreground/window/display metadata, power state, terminal grid/cell dimensions, executable/resource hashes and sparse wrapper counters. It rejects captures whose sampled foreground changes or whose workload fails to start. Each output directory must be new.

Available scenarios are `--scenario animate` (20 updates/second), `idle` (static text) and `titles` (animation plus repeated title events). `--legacy-composition` restores the always-blurred, nonopaque window policy in the same build. `--square-panes` isolates rounded clipping; `--async-redraw` replaces the wrapper's explicit synchronous draw with a refresh request. These are opt-in experiments. Rounded panes and the original draw API remain the defaults. A legacy-policy comparison isolates composition; it is not a before/after comparison of the entire original app.

`F7TTY_PROFILE=1` enables fixed-key in-memory counters on the host, sessions and terminal views. There is no periodic profiling output. `profilingSnapshot()` returns lifetime counts; missing keys mean zero. The benchmark records deltas after settling. `surface_draw_calls` counts wrapper C API calls, **not** engine or GPU frame submissions. GPU readings are system-wide sampled utilization, not per-process attribution, watts or battery-runtime evidence.

The disk-backed save-scheduler regressions can also run with Command Line Tools when XCTest is unavailable:

```sh
swiftc -swift-version 5 -parse-as-library -DWORKSPACE_SAVE_STANDALONE \
  Sources/F7TTY/WorkspaceModel.swift Sources/F7TTY/WorkspaceSaveScheduler.swift \
  Tests/F7TTYTests/WorkspaceSaveSchedulerTests.swift Scripts/test-workspace-saves.swift \
  -o .build/test-workspace-saves
.build/test-workspace-saves
.build/test-workspace-saves --baseline
```

These execute the same seven checks exposed through XCTest, including ordered backpressure, final flush, write failure/recovery and retained-invalid-state protection. The synthetic 100-update divider burst performs 100 writes through the original synchronous path and one through the debounced writer. This write-count result does not establish a GPU or battery improvement.

Local validation on 2026-09-08 passed the release build, dependency patch validation, 28 native smoke checks, both process-cleanup checks and all seven standalone persistence checks. Full `swift test` remains blocked by the selected Command Line Tools installation lacking XCTest. Screen capture permission is unavailable, so visual pixel matching and real mixed-DPI/IME interaction remain attended checks. GPU comparisons are pending the owner's go-ahead.
