# BuffRadar — Project Rules

Prompt in force: The Elite Software Master Prompt v1.1 · Annexes: A5 (games, mods
and addons), B (orchestration, adapted — Storytold Tier 2 WoW Lua), C (SEAN annex),
D (no AI features)

Purpose in one line: a click-to-buff list addon for World of Warcraft — it shows
every nearby player who is missing one of your buffs; click a name (or press one
key) to buff them.

Frozen foundation: one shared Lua source (`BuffRadar/BuffRadar.lua`) builds both
editions; editions differ only in their `.toc` and bundled docs
(`BuffRadar/` = Retail docs, `editions/forever/` = Forever docs). Every feature
is reachable as a `/br` slash command — the slash surface is the operation
registry — as well as through its settings control where it has one.
SavedVariables are versioned (`dbVersion`, currently 12) with a tested migration
chain; adding or changing a setting is a format change and updates the migration
smoke fixtures in the same change.

Build: none (interpreted Lua 5.1).
Full gate (all of it, every time, output read):
`python3 tools/luacheck51.py BuffRadar/BuffRadar.lua BuffRadar/Locales/deDE.lua` ·
`python3 tools/lualimits.py BuffRadar/BuffRadar.lua` ·
`python3 tools/localecheck.py BuffRadar/BuffRadar.lua BuffRadar/Locales` ·
real luacheck 1.2.0 over both Lua files (0 warnings / 0 errors) ·
`python3 tools/smoke51.py tools/wowstub.lua BuffRadar/BuffRadar.lua`
(six fake-client setups, 0 errors required).
Test corpus: the trial run in `tools/smoke51.py` — it only grows; every feature
lands with steps in every setup it applies to.

Budgets: the host's per-frame budget governs — scanning is event-driven plus a
throttled ticker; no per-frame polling. Lua 5.1 hard limits enforced by
`tools/lualimits.py`: ≤200 top-level locals (currently 194), ≤60 upvalues per
function (currently 59 peak). New state goes in the `X` table or methods, never
new file-scope locals, unless the budget is re-checked in the same change.

Coverage floors: every user-visible capability has smoke evidence before it is
called done; in-game behaviour is labelled **Unverified** until SEAN's field test
proves it (evidence labels: Verified / Partially Verified / Unverified).

Special rules for this project:
- Secure action buttons: `HookScript` / `WrapScript` only — **never**
  `SetScript("OnClick")` on a secure button.
- **No CI in this repo** (SEAN's decision, 2026-10-25) — the gate runs locally.
- Publishing: one `push_files` snapshot via the GitHub connector (the Contents
  API's per-call size cap cannot carry `BuffRadar.lua`), then blob-verify every
  published file against the local tree. **Forever-only from 1.8.0** (SEAN
  dropped Retail support 2026-10-25; Retail docs stay frozen at 1.7.0):
  releases attach the Forever zip plus `SHA256SUMS.txt`, and are not shipped
  until the assets are re-downloaded and hash-verified.
- The German locale stays complete — `tools/localecheck.py` enforces it; new
  user-facing list tags need an `L[...]` entry and a deDE translation.
- Licence is GPLv3 (upstream author Malikor). The SEAN-annex MIT default does
  not override a fork's licence.
- Repo About description and topics are refreshed after every release.
- Public documentation never names or compares other addons.

Known limitations live in each edition's `FEATURES.md` (Verification status) and
`docs/PARITY.md` (Gap column). Decision log: `docs/DECISIONS.md`.
Quality scorecard: `QUALITY.md`.
