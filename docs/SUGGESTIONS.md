# BuffRadar — 20 suggestions (2026-11-08)

Basis: read of `BuffRadar.lua` (8.1k lines, one file), tooling, docs and the 1.10.0 state. Build checked: Forever 1.60.1.70862 (interface 16001).

## Reliability / compatibility
1. **`/br apicheck`** — print which client APIs exist and are readable (`C_UnitAuras.*`, `GetWeaponEnchantInfo`, `C_Spell.*`, secret-value helpers). Turns "Unverified" into pasteable evidence from one in-game command.
2. **Weapon-enchant API for Forever** — other Forever addons report a newer temporary-enchant API; verify on 70862 and add it ahead of `GetWeaponEnchantInfo`.
3. **`/br buffcheck`** — validate every spell id/name in the buff table against the live client at load and list unknowns; catches Forever data changes without a release.
4. **Secret-data indicator** — when aura/range reads return secret values in combat, show a small "data hidden" mark instead of silently stale rows.
5. **Incremental aura updates** — use `UNIT_AURA` update info (added/removed auras) instead of full rescans; fits the 12.1 aura changes shared with Forever.
6. **Edit Mode registration** — Forever shares Mainline Edit Mode; let the window be placed/scaled from it.

## Window / UX
7. **Snap points on the scale grips** — hold Shift to snap to 75/100/125/150%.
8. **Edge width handle** — restore live width dragging on the right edge now that corners scale.
9. **Scale per spec/profile** — scale already saves in profiles; add an explicit per-spec toggle with a visible tag.
10. **Update-pending badge** — show when a size/scale change waits for combat to end.
11. **Colorblind-safe tag palette + text-only tags** — no color-only meaning.
12. **Reduced-motion switch** — disable fade and flash animations in one option.

## Features
13. **Auto-queue out-of-range casts** — cast when the player walks into range.
14. **Profile diff before import** — show what an import string changes.
15. **Talent-aware buff set** — use Forever talents to hide buffs the player can no longer cast.
16. **More locales** — frFR/esES/ruRU/zhCN via the existing `L[...]` + `localecheck.py` flow.

## Engineering
17. **Split the 8.1k-line file** into several `.lua` files sharing the `X` table; removes the 194/200 local pressure and the 59/60 upvalue peak in `Refresh()`.
18. **Local pre-push hook** running the full gate (no CI, per project decision).
19. **`/br perf`** — scan ms, memory, ticker rate, so budgets get in-game evidence.
20. **Fuzz trials** — random roster sizes 1–40, secret-value injection and mid-combat transitions in `smoke51.py`.

## Status (1.13.0)

| # | Status | Notes |
|---|---|---|
| 1 | Done | `/br apicheck` |
| 2 | Done | `GetWeaponEnchantInfo` stays (pcall-guarded); in-game verification of 1.12.0 passed, so no replacement is needed. `/br apicheck` still lists candidates. |
| 3 | Done | `/br buffcheck` |
| 4 | Done | "(data hidden)" title badge |
| 5 | Done | empty incremental `UNIT_AURA` payloads are dropped; real changes still rescan |
| 6 | Done | hooks `EditModeManagerFrame` Enter/Exit when it exists |
| 7 | Done | Shift-snap, `/br snap` |
| 8 | Done | right-edge width handle |
| 9 | Done | `/br specscale`; tooltip shows the saved spec |
| 10 | Done | "(update pending)" title badge |
| 11 | Done | `/br tagsymbols` |
| 12 | Done | `/br motion` |
| 13 | Partial | `/br rangewatch` notifies; the game does not allow addons to cast for you, so there is no auto-cast |
| 14 | Done | `/br diff`, `/br profile diff`, diff printed before every import |
| 15 | Already true | only spellbook spells are offered; talent/spell events rescan. Not changed. |
| 16 | Done | frFR, esES, ruRU, zhCN (81/81 each); machine-assisted translation, community review welcome |
| 17 | Partial | new code is in `Extras.lua`; the existing 8k-line file stays whole: Lua locals cannot cross files and it shares ~190 of them |
| 18 | Done | `tools/gate.sh`, `tools/install-hooks.sh` |
| 19 | Done | `/br perf` |
| 20 | Done | randomized roster/combat step in `smoke51.py` |

## Second list (2026-11-08, after in-game verification)

| Item | Status | Notes |
|---|---|---|
| In-game verification | Done | 1.12.0 verified live by SEAN on Forever 1.60.1.70862 |
| Release | Done | cut by SEAN |
| Real luacheck in CI | Skipped | SEAN: skip for now |
| `apicheck` export | Done | `/br apicheck export` |
| CI release workflow | Done | `.github/workflows/{ci,release}.yml`, `tools/package.sh` |
| Weapon-enchant API | Done | no change needed (see #2) |
| Consumable reminders | Already true | `/br consumables` (1.6.0) |
| Per-class presets | Already true | `/br preset`, per-spec profiles |
| Out-of-range hint | Already true | range words, out-of-range marker, `/br rangewatch` |
| Raid-wide summary | Done | `/br summary` (join digest and `/br discord` already existed) |
| Sound per buff type | Already true | `/br soundfor` (1.10.0) |
| Ignore-list import/export | Done | `/br ignorelist export | import` |
| Dual-spec test coverage | Done | smoke step for per-spec scale |

## Third list (2026-11-11, shipped as 1.15.0)

Seven suggestions SEAN approved the day 1.14.0 shipped; all seven are
built, gated and in 1.15.0 (Unverified in game, like 1.13.0/1.14.0).

| # | Item | Status |
|---|---|---|
| 1 | File split Slices B + C (settings -> Config.lua, slash -> Slash.lua) | Done — split complete; main file ~8.4k -> ~6.0k lines |
| 2 | Pull countdown in the coverage line | Done — coverage line counts down from X.pull while a timer runs |
| 3 | Un-park #33 with a definition (buff fell off mid-fight) | Done — /br fallsound, "fall" alert kind, off by default; no parked items remain |
| 4 | /br why <name> — explain why a player is/isn't listed | Done — runs the scan's own checks in order and reports the deciding one |
| 5 | Custom group-cast pairs for modifier clicks | Done — /br grouppair, consulted by GroupSpellFor |
| 6 | Group-cast keybind | Done — BuffRadarGroupButton, falls back to the plain cast |
| 7 | Workflow upkeep (actions off the deprecated Node 20 runtime) | Done — checkout v5, setup-python v6 in both workflows |
