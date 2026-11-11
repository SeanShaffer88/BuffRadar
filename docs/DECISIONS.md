# BuffRadar — Decision Log

Newest last. Each entry: the decision, why, the alternatives considered, and
the consequences. Started 2026-10-25 at the adoption of the Elite Software
Master Prompt; earlier entries are reconstructed from the changelogs and are
dated by when the decision took effect.

## 2026-10-20 — HookScript/WrapScript only on secure buttons
Row click-casting broke in 1.2.0 because a secure action button's `OnClick`
was replaced with `SetScript`. Rule ever since: secure buttons are only ever
hooked or wrapped, never re-scripted. Consequence: any new row interaction
must fit the hook/wrap pattern or be investigated first (see #19 in
`docs/PARITY.md`).

## 2026-10-23 — One source for both editions
Retail and Forever are built from a single `BuffRadar.lua`; the addon picks
its buff set at load from the client it runs on, and editions differ only in
`.toc` + docs. Alternative (two maintained trees) was rejected: every fix had
to be ported by hand and the trees had already drifted once. Consequence:
edition-specific behaviour is always a runtime branch, never a fork.

## 2026-10-24 — Four-doc set per edition
Every edition ships README / FEATURES / DESCRIPTION / CHANGELOG. Consequence:
a release is not done until all eight docs (plus the root README and
`tools/README.md`) agree with the code.

## 2026-10-25 — No CI for addon repos (SEAN)
Checks run locally via the tools/ gate instead. Alternative (GitHub Actions)
was tried for one day and removed at SEAN's direction: CI is not needed for
WoW addons. Consequence: the gate is a manual, full, read-the-output run
before every publish — there is no server-side safety net.

## 2026-10-25 — Publish via one push_files snapshot, then blob-verify
The Contents API passes file content as a single argument and cannot carry
`BuffRadar.lua` (~233 KB), so publishing is one `push_files` snapshot commit
through the GitHub connector, followed by a blob-SHA comparison of every
published file against the local tree. Consequence: local git history is
finer-grained than the remote's; the sync record
(`repo.muse-github-snapshot-sync.json`, kept with the working clone) maps
the two.

## 2026-10-25 — Assignments are per-buff, not per-player
`/br assign FORTITUDE Anna` marks every row whose *first* missing buff is
Fortitude. Alternative (a player owns a person, not a buff) was rejected:
buffs, not people, are what a group runs out of. Consequence: documented in
the changelog so the sink/float behaviour isn't a surprise.

## 2026-10-25 — Consumables are read-only; custom spells stay out of profiles
Consumables (flasks/food/runes) appear only as coverage counts, never as
rows — you cannot cast them on anyone. Custom watched spells are stored per
character and are deliberately not carried by settings export or named
profiles: a profile must never imply a spell another character doesn't know.
Both are documented in the user docs, not just here.

## 2026-10-25 — Identity matching goes through X.SameUser (bug fix)
The 1.7.0 cover-me tests exposed a latent 1.6.0 defect: assignments and
blessing plans carry the holder's name **as typed** (often the bare short
name), while identity checks compared full `Name-Realm` keys — so on the
assignee's own client their assignment sank as "someone else's". Rule now:
all holder/peer identity comparisons go through `X.SameUser` (full match,
or short-name match with no conflicting realm — the ignore list's
longstanding rule). Fixed in 1.7.0 and noted in both changelogs.

## 2026-10-25 — #20 (row tooltips) completed, not rebuilt
Rows already had tooltips (missing buff, cast line, ignore hints); the
listed item's missing half was remaining times for buffs the player HAS.
1.7.0 added exactly that half. Recorded here and in the changelogs so
the item is not later "re-shipped" as new.

## 2026-10-25 — Elite Software Master Prompt adopted (v1.1)
Artefacts created: this log, `QUALITY.md`, `docs/PARITY.md`, `SECURITY.md`,
and the rule sheet in `AGENTS.md`. BuffRadar scores **69/100** at adoption,
with two major waivers recorded in `QUALITY.md` (no numeric performance
budget for this product class; the in-game field test outstanding since
1.3.2 — the owner's own action). Releases below the §17 bar proceed only
under the owner's standing waiver, recorded in `QUALITY.md`. **SEAN
approved both major waivers on 2026-10-25**, and 1.7.0 (batch 2 of the
50-item program) was built and shipped under that approval the same day;
QUALITY.md was re-checked at its close with scores unchanged (the new
code is Unverified in game, so no dimension may honestly move). Annex D does
not apply (no AI features); Annex B applies in its Storytold Tier 2 adapted
form (single integrator, slash-command registry, corpus-scored parity).

## 2026-10-25 — Retail support dropped; Forever-only from 1.8.0 (SEAN)
SEAN directed: "addon is Forever-only i'm dropping retail support."
Consequences: releases from 1.8.0 attach only the Forever zip plus
`SHA256SUMS.txt`; the Retail docs in this repo (everything under
`BuffRadar/` except the shared source files) stay frozen at 1.7.0; past
Retail releases remain available as history. The shared source keeps its
Retail-gated spell tables untouched — removing them was not asked for,
and the smoke corpus keeps exercising both editions' code paths. The
field test is now Forever-only.

## 2026-10-25 — #10 and #15 were duplicates; replaced in-batch (1.8.0)
Implementation study for the 1.8.0 batch found two listed items already
shipped: #10 (missing-buff icons — rows have shown the missing buffs'
icons since the earliest versions) and #15 (opacity slider — the Window
tab's background-opacity slider). Following the #23 → #45 precedent,
each was replaced inside the same batch rather than silently dropped or
re-shipped: #10 → #43 (Discord summary), #15 → #37 (focus watch). Both
are marked † in the Forever changelog and recorded in `docs/PARITY.md`.

## 2026-10-25 — Final batch shipped as 1.9.0; the 50-item program is complete
SEAN directed "Build the final 4 as 1.9.0". Shipped: #13 two-column
layout (the list splits into two columns past 8 rows and the window
widens per column), #38 death recap (dying prints who was missing
what; `/br death show` reprints), #44 post-wipe report (a fight of
8+ seconds ending with 3+ dead — or 2 in a small party — prints the
rebuff list and, as leader/assistant, posts a one-line summary),
#50 setup wizard (three pages: preset, theme, your buffs; a first-run
hint points new users at it, and the dbVersion 11 migration marks
existing users as already seen). With this batch the program stands
at 44 of 50 shipped and 3 duplicates resolved; the last 3 items
(#8 pull-timer flash, #19 modifier clicks, #33 newly-unbuffed sound)
stay parked under investigation for the reasons in `docs/PARITY.md`
— they need in-game evidence or a sharper definition, not guesses.
Building further is closed off; the outstanding action is SEAN's
Forever field test (everything since 1.3.2 is Unverified in game).

## 2026-11-08 — All 20 suggestions applied as 1.12.0
SEAN: "Apply all suggestions". Notes: (a) the main file stays one chunk
at the 200-local limit, so the state table `X` moved to the top and the
new feature code went into `Extras.lua`, loaded second through the shared
addon namespace; a full split of the 8k-line file is NOT done because Lua
locals cannot cross files and the existing code shares ~190 of them
(recorded in docs/SUGGESTIONS.md). (b) The weapon-enchant replacement API
for Forever could not be named from evidence (the lookup was not
approved), so `/br apicheck` now lists candidates and `GetWeaponEnchantInfo`
stays. (c) "Auto-queue out-of-range casts" became Range watch: the game
forbids addons casting for you. (d) Talent-aware buff set was already
true (only spells in the spellbook are offered; talent and spell changes
rescan) and is covered by `/br apicheck`/`buffcheck`.

## 2026-11-08 — Scale grips replace the width grip (1.11.0)
SEAN asked for drag-to-resize anchors in the bottom corners that scale
the window and everything in it. Both bottom corners now scale; the old
width-only grip is gone and width moved to `/br width`. Scale math is
cursor distance from the fixed bottom corner over the unscaled window
width, clamped 0.5-2. Helpers live on `X` (the file-scope local budget
is 194/200; two extra locals broke compile and the trial step caught a
second bug, a scoped `RANGES` reference). Compatibility with build
1.60.1.70862 is a code audit only — Unverified in game.

## 2026-10-25 — Customization batch shipped as 1.10.0
SEAN asked for 5 enhancements and 5 additions that give players more
customization, then directed "Build all 10 as 1.10.0". Shipped:
saved themes, row spacing + icon size sliders, coverage-line part
toggles, a sound per alert kind, tooltip detail levels (enhancements);
row color marks, group-by-buff view, buff priority order, window
strata + click-through, name formats (additions). Two build notes
worth keeping: the shared registry table `X` is declared partway
through the main file, so code above it must never reference it — a
stored cross-reference table for the full tooltip died on exactly
that and was replaced by an on-hover scan; and the settings
"fire every control" trial step flips toggle-style controls for the
rest of a test run, so the group-by-buff switch is a checkbox, not a
cycle button. The batch also fixed a real Window-tab layout overlap
found while adding the new controls (the two-column and
duration-bars checkboxes, and the wizard button and range-words
checkbox, overlapped). Everything remains Unverified in game;
SEAN's Forever field test is still the outstanding action.

## 2026-11-08 — 1.13.0 after in-game verification

SEAN verified 1.12.0 in game and cut the release. Most of the second
suggestion list already existed (presets, consumables, range cues,
per-alert sounds), so only the gaps were built: apicheck export, ignore
list export/import, `/br summary`, packaging and CI. Real luacheck 1.2.0
in CI was skipped at SEAN's request; the in-repo static checks stay the
gate. `dbVersion` stays 13 (no new saved keys).

## 2026-11-11 — Release pipeline repaired; docs synced to 1.13.0

SEAN directed "do all of them" on the five improvement briefs drafted
2026-11-11 (release pipeline, unit-scoped refresh, modifier clicks,
pull-timer flash, file split) — BuffRadar resumed for this scope only.
Findings while repairing Brief 1: the 1.12.0 GitHub Release had no
assets, 1.11.0 and 1.13.0 had no release or tag, and the stray
`1.12.0` tag (no `v` prefix) could never fire `release.yml`, which
requires `v*` tags equal to the Forever .toc version. Fixes: the
release workflow now verifies its own assets landed; QUALITY.md,
docs/PARITY.md and the Forever FEATURES.md were synced from their
stale 1.10.0 state to the verified record (1.12.0 verified in game on
1.60.1.70862; 1.13.0 Unverified); AGENTS.md's "no CI" line was
corrected (CI exists since 1.13.0; real luacheck stays local per
SEAN's 2026-11-08 call). Tag rule going forward: `v<version>` only.

## 2026-11-11 — 1.14.0: Briefs 2–4 built (default off); file split Slice A only

Scope set by SEAN the same day: Brief 1, then Slice A of the file
split, then Briefs 2, 3, 4 — nothing else built; file-split Slices B
(settings) and C (slash) were NOT built and stay as briefs.
- Brief 2 (fast aura): the brief's per-unit entry cache was trimmed to
  a relevance skip — CollectEntries' global passes (tallies, single-
  target holders, drop checks) make per-unit caching a rewrite of the
  scan core, while the payload itself proves most incremental updates
  touch no watched buff. Any doubt falls back to today's full refresh.
  The probe ships unconditionally so Forever's real payload shapes are
  evidence before the default can change.
- Brief 3 (#19): mapping A chosen (Shift+left-click = group version),
  attributes only, no script-handler changes; combat snippets and
  every clear path clear the shift family alongside the plain one.
  The prototype gate became the 1.14.0 field pass because the option
  is off by default and plain casting is untouched.
- Brief 4 (#8): display = border flash + a chat countdown line. The
  brief's coverage-line countdown was dropped: the coverage line is
  rebuilt by every refresh, so a ticking countdown there needs a
  main-side hook — noted as a follow-up if the field pass wants it.
  Sources are counted by a probe before the feature trusts them;
  boss-mod comms require X.SenderTrusted.
- dbVersion 14 for the three new options (all default off), with the
  migration ladder and smoke fixtures updated in the same change, per
  the rule that adding a setting is a format change.
- Settings window: the Behavior tab gained two rows (fast aura,
  pull flash) and the right column one (modifier clicks); the tab's
  lower rows shifted down — the in-game settings pass for 1.14.0 must
  confirm nothing clips at the tab's bottom edge.

## 2026-11-11 — 1.15.0: all seven suggestions built

- Scope: SEAN approved all seven suggestions the day 1.14.0 shipped —
  file split Slices B+C, coverage-line countdown, #33 un-parked,
  `/br why`, custom group pairs, group-cast keybind, workflow upkeep.
- #33's definition (from its own investigation note): the re-entry
  case — a watched group buff up at a fight's start and gone at the
  first scan after it. Detection rides Consider's existing expiry
  snapshots; the scan cannot run in combat, so the alert fires at
  combat end, which is also when rebuffing becomes possible. Its own
  "fall" alert kind and `fallSound` option, off by default.
- Coverage countdown reads the pull state Extras already keeps; the
  refresh ticker keeps it current. Closes Brief 4's recorded follow-up.
- `/br why` runs the scan's own checks in order (ignore, session
  ignore, validity, missing, listed, finder, range) and reports the
  deciding one, then refreshes to rebuild the tallies its probe scan
  touched.
- Custom pairs (`db.customGroup`, capped, per-character like custom
  spells — deliberately not in profile exports) are consulted after
  the built-in group map, so a built-in pair always wins.
- The group keybind mirrors the cast-setup branches rather than
  touching the field-proven next-buff binding path; with no group
  version it arms the plain cast, so the key is never dead. The 60-
  upvalue ceiling on Refresh and the 200-local ceiling on the main
  chunk were both hit during this batch: group-button state lives on
  X, and the split files declare their own locals.
- File split complete: Config.lua (settings) and Slash.lua (slash
  commands) moved verbatim; main keeps thin delegating locals and two
  bridge tables (X.cfgAPI, X.slashAPI) for the locals they consume;
  Slash re-reads reassigned main state through getState() at command
  entry. BuffRadar.lua: 8,455 lines at 1.14.0 -> about 6,000.
- Workflows: checkout v5 / setup-python v6 — the first majors on the
  Node 24 runtime runners are moving to.
- dbVersion 15 (fallSound, customGroup), migration + fixtures in the
  same change. All of 1.15.0 is Unverified in game.

## 2026-11-11 — 1.15.1: settings layout fixes from the field pass

- SEAN's first 1.15.0 captures: the main window and list render
  correctly in game; the settings Window tab did not — three proven
  collisions (idle-fade vs the width hint, the long minimap label vs
  Grow-up, combat-hide vs the Layer button), bottom rows spilling
  below the frame, and the Display options panel drawing over the
  tab (its backdrop does not hide the tab on this client).
- Fixes: settings window 470 -> 540 tall; the tab's lower half
  re-spaced row by row; four fine-display checks (bars, markers,
  range words, focus line) moved into the Display panel as "Row
  extras" (same fields/callbacks; the panel grew to fit); opening
  the panel now hides the tab panels and closing it (or clicking a
  tab) restores the current tab via SelectTab/cfg.curTab — no
  reliance on backdrop opacity. No db change (dbVersion stays 15).
- 1.15.1 is Unverified in game until SEAN's re-check captures.

