# BuffRadar 1.15.38 — candidate verification

- **Artifact:** `BuffRadar-1.15.38-Forever.zip` · 1,280,404 bytes
- **SHA-256:** `73c0c7389e5cfa96401c4e641e886263afdf8dcd5175d44927981af1949e8112`
- **Target:** WoW: Forever, Interface 16001 · SavedVariables schema 23

This is an **unpublished candidate** built from the audit follow-up worktree,
not the published 1.15.37 package. The local handoff copies of the ZIP and
`SHA256SUMS.txt` are in `release-candidates/1.15.38/` outside Git. Rebuild with
`sh tools/package.sh` or PowerShell 7 `./build.ps1` from the same source.
If the ZIP hash changes, use a new matrix for the changed artifact.

## Offline gate and release bytes

| Check | Result | Evidence |
|---|---|---|
| Lua 5.1 compile, advisory limits, locales and patterns | **Pass** | `sh tools/gate.sh` compiled all 22 Lua files. Compiler self-tests reject 201 locals and 61 upvalues. German key and format checks and the literal-pattern check passed. |
| Declared Retail TOC (regression fixture) | **Pass** | 398 steps, zero errors. |
| Retail + Extras: modern, timer fallback, no UI templates, German | **Pass** | 399 steps each, zero errors. |
| Forever: modern, and fallback timer without UI templates | **Pass** | 404 steps each, zero errors. |
| Scoped two-client coordination | **Pass** | 22 cases, including roster and leader changes, replay floors, and proof retry/fallback. |
| Real Luacheck 1.2.0 on POSIX | **Pass** | Lua 5.1.5, 22 addon and locale files, zero warnings/errors. Separate from the compile check. |
| Package regressions | **Pass** | Seven tests including repeatability with changed source mtimes, invalid metadata and tags, links, path aliases, source drift, checksums and binding verification. |
| Candidate repeat build and checksum | **Pass** | Two clean POSIX output runs (one with `--tag v1.15.38`), byte-identical ZIPs and checksum files, then `sha256sum -c SHA256SUMS.txt`. No tag was created. |
| Package contents and startup | **Pass** | Source-aware `tools/checkpackage.py` verified all 32 files, loaded 22 Forever TOC entries in Lua 5.1, checked all four stable bindings, and read version 1.15.38 and Interface 16001 via `/br selftest`. |
| Patch whitespace and release notes | **Pass** | `git diff --check`; the first Forever changelog section matches the candidate TOC. |
| Windows `build.ps1` and package parity | **Pass in CI** | [PR #57 CI run](https://github.com/SeanShaffer88/BuffRadar/actions/runs/44429425381) built and verified the Windows ZIP with PowerShell and compared its SHA-256 with the POSIX build. The candidate was also reproduced byte-for-byte from the tested commit. |
| Full native Windows `tools/check.ps1` gate | **Not run** | The Windows CI job checks packaging; it does not run the full local Windows checker. |
| Hosted ZIP and checksum readback | **Not run** | No 1.15.38 GitHub release or other publication. After approved publication verify both downloaded files against the candidate bytes. |

Detailed scope: [32-item audit ledger](AUDIT_1.15.38.md).

## Windows parity handoff

On a clean checkout of the candidate source, use PowerShell 7 and Python
3.10 or newer. Set up the local tooling with `./tools/check.ps1 -Setup` if
needed. Build and run the full checker (including the ZIP):

```powershell
./build.ps1 --tag v1.15.38
./tools/check.ps1
Get-FileHash -Algorithm SHA256 dist/BuffRadar-1.15.38-Forever.zip
Get-Content dist/SHA256SUMS.txt
```

Record the Windows/PowerShell/Python versions, gate exit status, and digest.
The file hash and checksum line must match the header above. The CI parity
result is recorded separately from the full local Windows check.

## Forever field pass — pending

Install the **exact ZIP above** into a clean `Interface/AddOns/BuffRadar`
folder; do not test loose source files. Back up `WTF` before migration or
recovery checks. Record tester/date, client build/interface and language,
party or raid size, UI scale/resolution, and the ZIP digest. Attach relevant
screenshots, client error/taint excerpts, or copied diagnostic output.

| ID | Scenario | What to verify and record | Result |
|---|---|---|---|
| F1 | Install, upgrade, reload | `/br selftest` reports 1.15.38, Forever, Interface 16001 and schema 23. Upgrade a copied v22 save; keep profiles, saved class and role rules, keybinds and applicable preferences. With disposable future or over-limit saves, verify the warning and original save preservation; test explicit overflow recovery only after backing up. | Pending |
| F2 | Review and share | Try cancel/edit/apply with BR1; rename and replace a BR2 collision with an auto-profile mapping without loading it. Review a plan locally with no sends, then share with a second user; change membership or leadership during review and check that sharing refuses. Record what the receiver actually sees. | Pending |
| F3 | Protected casting and macro safety | Use a row, Cast Next Buff, Cast Next Group Buff, Shift-click and the action-bar macro. Include nearby exact-name, party, raid, self, group pet, and controller if available. Verify correct recipients and rank; check no stale or blocked actions on combat entry/exit, death/release/resurrection, token reuse, or after closing a macro editor. A user-owned same-name macro stays unchanged. | Pending |
| F4 | Group fallbacks and observations | Use a Fortitude/Prayer tier against low-level and eligible recipients. Change range, reagents, cooldown and subgroup rules; verify fallback and that pets don't count toward group need. Distinguish present/missing/unknown food, flask, drinking, world buffs and custom aura IDs, and test shield, empty hand, and coatable weapons in Personal readiness. Include restricted auras and combat debuff stacks. | Pending |
| F5 | Viewport, focus and panel positions | Test a short viewport, large UI scale, two columns and a long roster. Scroll in people/buff views; check the visible row casts on its own player, Cast Next Buff stays on the first eligible player, and the footer/buttons stay reachable. Test drag/save/reopen/reload/reset for Settings and Ready Check, combat/death closure, and review focus/scrolling without overlapping controls. | Pending |
| F6 | Nearby and locales | In English and German, compare nameplates on/off, estimated vs explicitly failed range, target changes, close/reopen and confirmed vs unknown texts. Opening Nearby or toggling its visibility does not itself change CVars. Check translated dialog buttons, markers and actual ID-based observations on a German client. | Pending |
| F7 | Countdown and roster transitions | Test native and available boss-mod countdowns in a party/raid. Cancel with the original sender, replace an active countdown, try an unrelated stop, and leave/rejoin. Confirm forecasts remain scoped; an ambiguous stop can wait for expiry. Record the `/br apicheck` timer observations and check no old join digest fires. | Pending |
| F8 | Reports and chat routes | Try `/br announce` and opt-in ready-check chat in normal party and raid and, if available, instanced group contexts. Test refusal or throttling and retain the local report. Compare the caster's send result with another player's received messages; API acceptance or no return value is not delivery. | Pending |
| F9 | Timings and memory | Collect `/br perf` in solo, 5-player, 25-player and up-to-40-player groups, including raids and combat debuff updates. Record scan average/worst against the 2 ms/8 ms targets, preparation/import/debuff samples when present, and addon total memory before/after roster churn and Lite mode. Record client latency and panel visibility; fake-client or CPU timings aren't end-to-end latency. | Pending |

Also run the applicable [general and readiness checks](FOREVER_RELEASE_CHECKLIST.md).
A skipped game scenario remains unverified; don't carry a result forward from
another build, language or changed artifact.
