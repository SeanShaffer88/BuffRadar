# BuffRadar — Project Rules

Prompt in force: The Elite Software Master Prompt v1.1 · Annexes: A5 (games, mods
and addons), B (orchestration, adapted — Storytold Tier 2 WoW Lua), C (SEAN annex),
D (no AI features)

Purpose in one line: a click-to-buff list addon for World of Warcraft — it shows
every nearby player who is missing one of your buffs; click a name (or press one
key) to buff them.

Frozen foundation: both editions share the Lua source under `BuffRadar/`.
Their `.toc` files declare load order; do not use `require` or add globals for
module communication. `Data.lua` initializes the addon namespace, `SavedVariables.lua`
owns the schema and publishes the live DB, `BuffRadar.lua` owns scanning and
cast decisions, and `Window.lua` and `Minimap.lua` own their frames and caches.
Keep implementation state local and share entry points through the addon table.
Every feature is reachable through `/br` as well as through its settings control
where it has one. SavedVariables are versioned (`dbVersion`, currently 21) with
migration smoke fixtures; keep those fixtures in sync with format changes.

Build: none (interpreted Lua 5.1).
Full gate (all of it, every time, output read): `sh tools/gate.sh` runs the Lua
5.1 compiler, advisory limit estimates, locale and pattern checks, seven
fake-client smoke setups using the two TOCs, and two-client coordination.
`sh tools/install-hooks.sh` installs the pre-push gate. Also run real luacheck
1.2.0 on all addon Lua files (0 warnings / 0 errors); `tools/check.ps1` runs the
checks on Windows. Add trial steps for every feature in the setups it applies to.

Budgets: scanning is event-driven plus a throttled ticker; no per-frame
polling. The Lua 5.1 compiler enforces 200 active locals per function or chunk
and 60 upvalues per function. Check headroom with `tools/lualimits.py` when
adding file-scope state; keep state in its owning module rather than moving it
into the shared `X` table to work around the limits.

Coverage floors: every user-visible capability has smoke evidence before it is
called done; in-game behaviour is labelled **Unverified** until SEAN's field test
proves it (evidence labels: Verified / Partially Verified / Unverified).

Special rules for this project:
- Manual Forever release validation: run docs/FOREVER_RELEASE_CHECKLIST.md on the exact candidate build before marking in-game behavior verified.
- Secure action buttons: `HookScript` / `WrapScript` only — **never**
  `SetScript("OnClick")` on a secure button.
- **CI runs the gate** (`.github/workflows/ci.yml`, added in 1.13.0): static checks + trial run + a packaging dry run on every push/PR. Real luacheck 1.2.0 stays a local Windows step (`tools/check.ps1`) — SEAN skipped it in CI on 2026-11-08. `release.yml` publishes on a `v*` tag that must equal the Forever .toc version.
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
