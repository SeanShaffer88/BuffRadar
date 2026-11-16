# BuffRadar — Quality Scorecard

Scored under the Elite Software Master Prompt v1.1 (§17), from evidence only.
Updated: 2026-10-25, at the adoption of the prompt and the close of 1.6.0.
Re-checked at the close of 1.7.0 (same day): **scores unchanged** — the new
code is Unverified in game like everything since 1.3.2, so no dimension may
honestly move yet; what grew is the evidence base (corpus 174→184 steps,
185 German) and the shipped share of the enhancement program (10→20 of 50).
Re-checked again at the close of 1.8.0 (same day): **scores unchanged** for
the same reason; the evidence base grew to 237 steps (238 German), the
program stands at 40 of 50, and the product is Forever-only from 1.8.0.
Re-checked at the close of 1.9.0 (same day): **scores unchanged** for the
same reason; the evidence base grew to 241 steps (242 German), and the
50-item program is **complete** — 44 shipped, 3 duplicates resolved,
3 parked under investigation with their reasons recorded.
Re-checked at the close of 1.10.0 (same day): **scores unchanged** for
the same reason; the evidence base grew to 245 steps (246 German), and
a SEAN-requested 10-item customization batch shipped (saved themes,
row spacing + icon size, coverage part toggles, per-kind alert sounds,
tooltip detail levels, row color marks, group-by-buff view, buff
priority order, window strata + click-through, name formats).
Re-checked at the close of 1.13.0 (2026-11-11): **scores unchanged** —
the evidence picture changed, the score does not move on one field run.
1.12.0 was verified in game by SEAN on Forever 1.60.1.70862, which
retires the "Unverified since 1.3.2" basis for the core through 1.12.0;
the 1.13.0 additions (apicheck export, ignore-list export/import,
`/br summary`, CI + packaging) are Unverified in game, and the
multi-user coordination behaviour still has no second-user field
evidence. The 1.12.0 GitHub Release originally shipped with no assets;
assets were backfilled and 1.13.0 was published through the tag
workflow on 2026-11-11 (see docs/DECISIONS.md).
Re-checked at the close of 1.14.0 (2026-11-11): **scores unchanged** —
the release adds three off-by-default options (fast aura, modifier
clicks, pull-timer flash), the Data.lua split, and the release
pipeline repair; all of it is Unverified in game, and the two
un-parked items (#8, #19) stay Unverified until SEAN's field pass.
The trial-run corpus grew with steps for each new behaviour.
Re-checked at the close of 1.15.0 (2026-11-11): **scores unchanged** —
the release builds #33 (the last parked item), the coverage-line pull
countdown, custom group-cast pairs, a group-cast keybind, and finishes
the file split (Config.lua, Slash.lua); all of it is Unverified in
game. The trial-run corpus grew with steps for each new behaviour.
Re-checked at the close of 1.15.1 (2026-11-11): **scores unchanged** —
a layout-only fix release driven by SEAN's first 1.15.0 captures (the
first in-game evidence for the settings window since 1.12.0); the main
window and list are now field-verified at 1.15.0, and 1.15.1's own
layout is Unverified until his re-check.
Re-checked on 2026-11-16 after SEAN reported that every release through
1.15.31 passed in game: the UX field-test waiver is **closed**. UX moves
2→4 and Correctness 4→5, as this scorecard set out; **total 69→74**.
Multi-user coordination is covered by that report. 1.15.32
(Shadowguard watch) and 1.15.33 (input hardening) passed their checklist
steps in game later the same day (SEAN); no score changes.
Re-scored the same day against the current tree (1.15.32): stale rows that
still described the single-file layout, the parked items and the 1.10.0
corpus were brought up to date. Feature completeness 3→4 (program done,
nothing parked), Performance 3→4 (budget defined and gate-enforced; the
performance waiver is **closed**), Diagnostics 3→4 (the diagnostics pass
shipped). Maintainability stays 3: the main file is back near 9,700 lines.
**Total 74→78.**
Scores are 0–5 per dimension (3 = meets the bar with evidence); the weighted
total uses the §17 weights. A release under this regime requires: total ≥85,
no dimension below 3, and no Fail. **The current total is 78** — the blockers
are named below as waivers with owners and follow-ups, not hidden.

| Dimension (weight) | Score | Verdict | Evidence |
|---|---|---|---|
| Correctness (14) | 5 | Pass | Full gate green (Lua 5.1 compile, luacheck 0/0, locale, trial run × 6 fake-client setups, 0 errors) and every release through 1.15.31 passed in game (SEAN, 2026-11-16). |
| Security & privacy (12) | 4 | Pass | Risk Tier 0: no network, no credentials, no data leaves the client; SavedVariables are local settings/stats only. Addon comms ride the game's group channel on one prefix; assignment/blessing-plan messages are trust-gated (leader/assistant; paladin for blessings). `SECURITY.md` present. |
| Robustness (11) | 4 | Pass | SavedVariables migration chain v2→v20 smoke-tested, including corrupt-save replacement and repair of corrupt custom-spell / auto-profile entries; a strict sanitizer rebuilds settings on load; handlers are pcall-wrapped so one bad event can't kill the addon. |
| Feature completeness (9) | 4 | Pass | Core purpose complete. The approved 50-item program is **complete** with **nothing parked**: 44 shipped by 1.9.0, three duplicates replaced in-batch (#23, #10, #15), and the three parked items built later (#8 and #19 in 1.14.0, #33 in 1.15.0). Three further suggestion lists are done except one platform limit recorded in `docs/SUGGESTIONS.md` (#13: the game does not let addons auto-cast, so out-of-range players get a notice instead). Not 5: that limit. |
| Performance (8) | 4 | Pass (waiver closed 2026-11-16) | Budget defined 2026-11-16 (`docs/DECISIONS.md`) and enforced by the trial run on every push: a worst-case scan (every player missing every buff) reads ≤8 auras per player, grows linearly from 20 to 40 players, and averages <5 ms in the fake client (measured: ~5.75 reads per player, ~0.7 ms for 40 players). Scans are event-driven, coalesced to one per 0.1 s and ticked every 0.4 s; rows are pooled. Not 5: the in-game target (`/br perf` average ≤2 ms, worst ≤8 ms in a 40-player raid) has no field numbers yet. |
| Maintainability (7) | 3 | **Waiver** (minor) | The source is split across ten files (Data, BuffRadar, Coordination, Wizard, Window, Config, Slash, Extras, Recaps, Profiles; 17.4k lines). Slices E, F and G (2026-11-16) moved coordination, the wizard/diagnostics tools and the window builder with its cast buttons out, so `BuffRadar.lua` dropped from ~9,700 to ~7,200 lines, but it is still above the prompt's file-length target and Config.lua is ~4,100. Lua 5.1 limits are tool-enforced on every file: main chunk 165/200 locals, `HandleSlash` 58/60 upvalues, `Refresh` 49/60. The score stays 3 until the split passes a field test and the scan core (who is around, rank selection, Refresh) is the only large block left. Slice G touches the secure cast path, so it needs its own field test. |
| Modularity (6) | 3 | Pass | Seven load-ordered files; sections stay one-way (data → scan → render → UI → commands), shared state lives in one `X` registry table, and the split files reach main state only through bridge tables (`X.cfgAPI`, `X.slashAPI`). Every capability is a named slash operation before it is a settings control. Not 4: the bridge tables are a wide coupling surface, checked by review only. |
| UX & accessibility (6) | 4 | Pass (waiver closed 2026-11-16) | The UI is complete in code and smoke, and SEAN's in-game field test passed for every release through 1.15.31 on Forever (reported 2026-11-16). Not 5: no accessibility audit beyond the tag-symbol, reduced-motion and text-scale options. |
| Scalability (5) | 3 | Pass | Host caps group size (40); scan cost is linear in roster size and throttled; the row pool is capped at 15 with overflow counted on the coverage line. 10x/100x testing is not applicable to a host-capped addon; the cap behaviour is smoke-tested. |
| Idiomatic quality (5) | 4 | Pass | luacheck 1.2.0 at strict settings: 0 warnings / 0 errors; project checkers (compile, limits, locale) green; consistent style across the file. |
| Test & corpus evidence (5) | 4 | Pass | Corpus = the trial run: 350/350 steps in five setups, 351/351 in the German setup at 1.15.32, plus the two-client coordination run, the package check, migration fixtures from real legacy save shapes, corrupt-data fixtures, a randomized roster/combat step and the performance-budget step. The corpus only grows. Line-coverage percentage is not measurable for this stack, so the corpus fraction is the recorded evidence. |
| Self-documentation (4) | 3 | Pass | Section banners and why-comments throughout; architecture and rules in `AGENTS.md`; module map in the root README's Layout table. No generated API reference — not applicable to an addon with no public API. |
| Documentation (4) | 4 | Pass | Four-doc set per edition (README / FEATURES / DESCRIPTION / CHANGELOG) plus `tools/README.md`, in-game help covering every command, `SECURITY.md`, and `## TL;DR` openings on all three READMEs (added at adoption). Checked against the code at every release. |
| Diagnostics & supportability (4) | 4 | Pass | `/br selftest` (versioned paste-able block), `/br debug`, `/br apicheck [export]` (client API probe), `/br buffcheck` (spell table vs live client), `/br perf` (scan ms, memory), `/br why <name>` (the deciding listing check) and the Nearby Player Diagnostics panel. Local only; nothing is sent anywhere. Not 5: no stable error IDs — the game's error frame carries those. |

**Total: 78 / 100.** No dimension is Fail and none is below 3. Both major
waivers SEAN approved on 2026-10-25 are now closed: the UX field test
(passed through 1.15.31) and the performance budget (defined and
gate-enforced, 2026-11-16). One minor waiver remains (Maintainability: the
main file's length). The ≥85 release bar is not met; releases continue
under SEAN's standing approval. The honest path upward is real work:
shrinking `BuffRadar.lua` (maintainability 3→4, ≈+1.4), narrowing the
bridge tables (modularity 3→4, ≈+1.2), in-game `/br perf` numbers from a
40-player raid (performance 4→5, ≈+1.6), and the remaining 3-scored
dimensions (scalability, self-documentation) each earning a 4.
