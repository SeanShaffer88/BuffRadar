# BuffRadar 1.19.1 Validation

Target: WoW: Forever, Interface 16001. Observed November 22, 2026
(America/Chicago). Verification uses offline client adapters. No live-client
rendering, protected-action or battleground pass is claimed.

## Scope

Support and Why explain battleground pauses, combat and PvP safety, detected
blessings, preferences, assignments, plans and complement decisions. Reports
use bounded fixed fields; failures and unreadable client data stay unknown.
Diagnostic reads restore private scan state on success and error. No saved
schema, dependency or gameplay selection policy changes. Pinned Actions remain
separate and are not part of this release.

## Offline Evidence

The POSIX and Windows gates cover actual Lua 5.1 compilation, seven client
smoke configurations, two-client coordination, 21 relog scenarios, theme
previews, Actions, Support privacy and packaging. Real Luacheck checks all
30 addon files. All five locales contain 1,524 of 1,524 strings.

Focused diagnostics exercise BG and arena pauses, strict unknown flags,
partial and empty spellbooks, observed ranks, plans and assignments, ownership,
complement suppression, recipient explanations and restoration after errors.
Independent comparisons found identical results in 625 combat/PvP validity
cases and 1,890 blessing-selection cases, including the existing second return.
Mutations removing partial-book readiness or read-only rank protection fail.

Final gate logs (stdout, stderr and result.json):

- POSIX: `C:/Users/Sean Shaffer/Documents/DevTools/runs/20261122T162244185Z-905542c97daf414f89e82bda3937a9a5`
- Windows: `C:/Users/Sean Shaffer/Documents/DevTools/runs/20261122T162355480Z-63dd1f226dac44a6a9b9b35a0e65a818`
- Packaging: `C:/Users/Sean Shaffer/Documents/DevTools/runs/20261122T162344263Z-8dc38e3447054c279b26b27905117ae0`
- Expanded static validation: `../buffradar-1.19.1-stage/addon-validation.json`

Windows skips the symlink fixture because creation privileges are absent
(WinError 1314). Require that fixture to pass on Linux CI. Limit estimates
remain advisory; actual Lua compilation is the syntax gate.

## Artifact and Publication Gates

`BuffRadar-1.19.1-Forever.zip`: 2,257,491 bytes; 40 files; 30 TOC entries;
five bindings. Repeated builds produce identical bytes. Expanded DevTools
validation exited 0 with Interface 16001 and no findings.

SHA-256: `76e2093fb9dfdf30a2ed00ec1b4025d54072b00d17b285234d7d363bfe0ef0e3`

Require independent review, raw Git-blob parity for every ZIP member, passing
PR CI and equal Windows/POSIX digests before merging. Tag only that source.
The release workflow reruns the gate and verifies downloaded assets. Final
readback must match this candidate and the exact tagged Git blobs.
