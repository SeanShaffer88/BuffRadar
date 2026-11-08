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

## Status (1.12.0)

| # | Status | Notes |
|---|---|---|
| 1 | Done | `/br apicheck` |
| 2 | Partial | `/br apicheck` lists weapon-enchant API candidates on the live client; the replacement name could not be verified from here, so `GetWeaponEnchantInfo` stays (pcall-guarded). Needs one in-game run. |
| 3 | Done | `/br buffcheck` |
| 4 | Done | "(data hidden)" title badge |
| 5 | Done | empty incremental `UNIT_AURA` payloads are dropped; real changes still rescan |
| 6 | Done (Unverified) | hooks `EditModeManagerFrame` Enter/Exit when it exists |
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
