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
Scores are 0–5 per dimension (3 = meets the bar with evidence); the weighted
total uses the §17 weights. A release under this regime requires: total ≥85,
no dimension below 3, and no Fail. **The current total is 69** — the blockers
are named below as waivers with owners and follow-ups, not hidden.

| Dimension (weight) | Score | Verdict | Evidence |
|---|---|---|---|
| Correctness (14) | 4 | Pass | Full gate green on the integrated 1.10.0 tree: Lua 5.1 compile, luacheck 0/0, locale 81/81, trial run 245 steps (246 German) × 6 fake-client setups, 0 errors. Not 5: in-game runtime is Unverified (see UX waiver). |
| Security & privacy (12) | 4 | Pass | Risk Tier 0: no network, no credentials, no data leaves the client; SavedVariables are local settings/stats only. Addon comms ride the game's group channel on one prefix; assignment/blessing-plan messages are trust-gated (leader/assistant; paladin for blessings). `SECURITY.md` present. |
| Robustness (11) | 4 | Pass | SavedVariables migration chain v2→v12 smoke-tested, including corrupt-save replacement and repair of corrupt custom-spell / auto-profile entries; a strict sanitizer rebuilds settings on load; handlers are pcall-wrapped so one bad event can't kill the addon. |
| Feature completeness (9) | 3 | Pass | Core purpose complete. The approved 50-item enhancement program is **complete**: 44 shipped across 1.6.0 + 1.7.0 + 1.8.0 + 1.9.0 (three listed items proved duplicates — #23, #10, #15 — each replaced in-batch; #20 was completed rather than duplicated), 3 parked under investigation (#8, #19, #33 — see `docs/PARITY.md`). A further SEAN-requested customization batch (10 items) shipped in 1.10.0. |
| Performance (8) | 3 | **Waiver** (major — **approved by SEAN 2026-10-25**) | No numeric frame-time budget exists for this product class; the mitigation is structural: event-driven scanning plus a throttled ticker, no per-frame work, bounded row pool (15). Follow-up: scan throttle (#49) **shipped in 1.7.0**; if SEAN ever sees frame drops in 40-man raids, a measured budget gets defined then. |
| Maintainability (7) | 3 | **Waiver** (minor) | One ~8,100-line Lua file exceeds the prompt's default file-length target. Reason: the WoW addon loader and Lua 5.1's 200-local ceiling make the single-file layout the pragmatic architecture today; the file is sectioned, and the locals budget (194/200) is tool-enforced. Follow-up: re-evaluate a split (the `.toc` can list several files) if locals pressure grows. Decision log started 2026-10-25 (`docs/DECISIONS.md`). |
| Modularity (6) | 3 | Pass | Single file, but internal sections are one-way (data → scan → render → UI → commands), all shared state lives in one `X` registry table, and every capability is a named slash-command operation before it is a settings control. Checked manually in review (no mechanical boundary tool exists for this stack). |
| UX & accessibility (6) | 2 | **Waiver** (major — **approved by SEAN 2026-10-25**; the field test itself remains his action) | The UI is complete in code and smoke (all states exercised in the fake client), but the in-game field test — the fresh-user gate for this product — has been outstanding since 1.3.2; 1.3.2–1.10.0 are all Unverified in game. Only SEAN can run it (Forever only, since 1.8.0). Follow-up: Forever field test, priorities recorded in `docs/PARITY.md`. |
| Scalability (5) | 3 | Pass | Host caps group size (40); scan cost is linear in roster size and throttled; the row pool is capped at 15 with overflow counted on the coverage line. 10x/100x testing is not applicable to a host-capped addon; the cap behaviour is smoke-tested. |
| Idiomatic quality (5) | 4 | Pass | luacheck 1.2.0 at strict settings: 0 warnings / 0 errors; project checkers (compile, limits, locale) green; consistent style across the file. |
| Test & corpus evidence (5) | 4 | Pass | Corpus = the trial run: 245/245 steps in five setups, 246/246 in the German setup at 1.10.0, including migration fixtures from real legacy save shapes and corrupt-data fixtures. The corpus only grows; every slice adds steps (1.7.0's steps also caught a real 1.6.0 bug — short-name assignment identity). Line-coverage percentage is not measurable for this stack, so the corpus fraction is the recorded evidence. |
| Self-documentation (4) | 3 | Pass | Section banners and why-comments throughout; architecture and rules in `AGENTS.md`; module map in the root README's Layout table. No generated API reference — not applicable to an addon with no public API. |
| Documentation (4) | 4 | Pass | Four-doc set per edition (README / FEATURES / DESCRIPTION / CHANGELOG) plus `tools/README.md`, in-game help covering every command, `SECURITY.md`, and `## TL;DR` openings on all three READMEs (added at adoption). Checked against the code at every release. |
| Diagnostics & supportability (4) | 3 | Pass | `/br selftest` prints a versioned, paste-able diagnostics block (version, edition, settings state, feature state, last error); `/br debug` prints client/zone/nameplate diagnostics. Local only; nothing is sent anywhere. No stable error IDs — the game's error frame carries those. |

**Total: 69 / 100.** No dimension is Fail. Two major waivers (Performance
budget, UX field test) are the owner's to approve or close; both predate this
scorecard and are recorded here so 1.7.0 is developed against them openly.
The honest path upward is evidence, not score-shopping: the field test alone
moves UX (2→4) and lets Correctness claim 5 — together +26 weighted points
(≈74 total). Completing the 50-item program (completeness 3→4) and defining a
measured frame budget (performance 3→4) reach ≈79. Beyond that, the
remaining 3-scored dimensions (maintainability, modularity, scalability,
self-documentation, diagnostics) must each earn a 4 on real work — a file
split, a diagnostics pass — before ≥85 is in reach. **SEAN approved both
major waivers on 2026-10-25** (performance budget; releases proceeding while
the field test is outstanding), so releases proceed under that approval —
recorded here, with the follow-ups still open above — until the evidence
closes them.
