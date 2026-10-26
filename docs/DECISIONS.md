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
