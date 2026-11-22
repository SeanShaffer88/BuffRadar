# Local Offline Candidate

Historical evidence for the local candidate before 1.19.0. The 1.19.0 release
adds Actions search and a fifth binding; its verification is recorded separately.

Base: `018ee2c` (1.18.0). Branch: `test/forever-offline-relog`.
This candidate has no new release version, tag, or published assets.

## Changes

- Restart harness recreates Lua state and copies only durable settings, macro
  slots, native bindings, and action-bar references.
- Existing local Support report adds typed error counts, peer totals, and
  allowlisted theme diagnostics. Raw errors and player text stay excluded.
- Caster Coordination adds a read-only Peers tab, separate from plan acceptance.
- Theme Preview supports transient palette selection, Apply, Cancel, keyboard
  navigation and narration. Auto diagnostics retain the committed selection.

## Verification

All final commands below exited 0 on 2026-11-21 (America/Chicago).

| Command | Evidence |
|---|---|
| `pwsh -NoProfile -File tools/check.ps1 -ToolsDir ../brlua` | Real Luacheck: 0 warnings, 0 errors in 30 files. Compiler, seven smoke configurations (3,250 steps), coordination, 21 relog scenarios, theme previews, localization and package checks passed. |
| `sh tools/gate.sh` with the existing brlua Python first on PATH | Full POSIX gate passed using the same installed Lua 5.1 adapter. |
| `python -I tools/package.py` twice | Identical ZIP digests. |
| `python -I tools/checkpackage.py dist/BuffRadar-1.18.0-Forever.zip .` | 40 files, 30 TOC load entries, four XML bindings; exact source/package match. |
| DevTools `Test-WowAddon.ps1` against expanded ZIP, `-InterfaceVersion 16001` | Valid, 30 load entries, no findings; static metadata/reference checks only. |

All five locale packs contain 1,450 of 1,450 strings. Independent review found
and verified the correction for committed Auto diagnostics showing a transient
preview label. The reviewer independently ran relog, coordination, and theme
checks. A source-string mutation removing macro newline normalization was
rejected by the restart harness.

The package suite skipped its symbolic-link fixture because this Windows
account lacks symbolic-link creation privileges (WinError 1314). Other package
fixtures passed. Advisory upvalue estimates warn at 56 of 60; actual Lua 5.1
compilation passed. No in-game execution was requested or performed; mocks do
not establish real rendering, channel delivery or protected-action behavior.

Final logs (stdout, stderr and result.json under each directory):

- `C:/Users/Sean Shaffer/Documents/DevTools/runs/20261122T045211231Z-e19bfc68b8cc43bd8949cdb56050f5ee`
- `C:/Users/Sean Shaffer/Documents/DevTools/runs/20261122T045221442Z-ab868eb00fe94b4c8937c98b00b70cbd`
- Expanded artifact validation: `../buffradar-offline-stage-20261121T225240/addon-validation.json`

Local artifact: `dist/BuffRadar-1.18.0-Forever.zip`

SHA-256: `7ef1599bd0539155dca20809029a775d2d2324059fd64eac72fcb13a2147ddc9`

## Workflow

The [Git workflow skill](<C:/Users/Sean Shaffer/.agents/skills/git-workflow-and-versioning/SKILL.md>)
requires changes to flow through Git; work stayed on a dedicated local branch.
The [code review skill](<C:/Users/Sean Shaffer/.agents/skills/code-review-and-quality/SKILL.md>)
requires review after feature implementation; an independent auditor reviewed
the final changes and verification evidence. Repository AGENTS.md supplied the
TOC-driven compiler, locale, smoke, coordination and packaging gates.
