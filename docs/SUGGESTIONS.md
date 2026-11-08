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
