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

## 2026-10-25 — Elite Software Master Prompt adopted (v1.1)
Artefacts created: this log, `QUALITY.md`, `docs/PARITY.md`, `SECURITY.md`,
and the rule sheet in `AGENTS.md`. BuffRadar scores **69/100** at adoption,
with two major waivers recorded in `QUALITY.md` (no numeric performance
budget for this product class; the in-game field test outstanding since
1.3.2 — the owner's own action). Releases below the §17 bar proceed only
under the owner's standing waiver, recorded in `QUALITY.md`. Annex D does
not apply (no AI features); Annex B applies in its Storytold Tier 2 adapted
form (single integrator, slash-command registry, corpus-scored parity).
