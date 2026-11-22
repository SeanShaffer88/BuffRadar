# BuffRadar 1.19.0 Validation

Target: WoW: Forever, Interface 16001. Observed November 21, 2026
(America/Chicago). Verification used offline client adapters; no live-client
rendering, protected-action, or game-channel pass is claimed.

## Source and Behavior

Actions search adds 14 fixed destinations to the existing settings search.
All, Settings, and Actions filters retain paging, keyboard navigation and
narration. Availability is observed without running actions and rechecked when
activated. Existing editors and confirmations handle consequential operations.
The optional fifth binding opens only the menu. Gear Left/Right clicks remain
unchanged; Shift-left opens Actions. No saved-schema change or dependency was added.

Independent review corrected and regression-tested navigation restoration for
Profiles and callback failures, and live group/lightweight-mode availability for
Raid Preparation. In-memory mutations removing the Preparation guard and Profiles
navigation restoration were each rejected by the focused suite.

## Local Checks

These commands exited 0 against the final candidate:

- `pwsh -NoProfile -File tools/check.ps1 -ToolsDir ../brlua`
- `sh tools/gate.sh` with the existing brlua Python on PATH
- `python -I tools/actions51.py --addon BuffRadar/BuffRadar.lua`
- `python -I tools/package.py --tag v1.19.0` twice, with identical bytes
- `python -I tools/checkpackage.py dist/BuffRadar-1.19.0-Forever.zip .`
- DevTools `Test-WowAddon.ps1` against the expanded candidate with Interface 16001

Real Luacheck reported 0 warnings and 0 errors in 30 files. Seven smoke setups
passed 3,250 steps with no errors. The two-client coordination suite, 21 relog
scenarios, theme previews and Actions tests passed. All five locale packs contain
1,478 of 1,478 strings. Actions tests run with native and fallback timers, exercise
the actual XML binding and gear routes, and check bounded argument handling,
read-only queries, stale restrictions, navigation and narration.

The local package suite skipped its symlink fixture because Windows lacks
symlink-creation privileges (WinError 1314); the Linux CI gate provides that
coverage. Advisory upvalue estimates remain separate from compiler success.

Final local gate evidence (stdout, stderr and result.json):

- `C:/Users/Sean Shaffer/Documents/DevTools/runs/20261122T051520053Z-a87ec35b2b8945008d84923c4c728e37`
- `C:/Users/Sean Shaffer/Documents/DevTools/runs/20261122T051520045Z-2b62620786f04cf196aba544652afe8b`
- Expanded static validation: `../buffradar-1.19.0-stage/addon-validation.json`

## Candidate and Publication Gates

ZIP: `BuffRadar-1.19.0-Forever.zip`, 40 files, 30 TOC entries, five bindings.

SHA-256: `18f50b67a52df17275375dddf607c0d698677d4d1cc874690c0e68b97abf3720`

Before merging, require independent source review, passing PR CI and identical
Windows/POSIX package digests. Before tagging, compare every ZIP entry with raw
Git blobs from the approved source. The tag workflow runs the full gate, builds
the package, publishes it, re-downloads it and checks byte identity. Final
readback must match this candidate digest and the exact tagged Git source.
