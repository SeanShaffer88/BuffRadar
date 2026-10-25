# BuffRadar checks

Automated checks to run before building a release. They don't replace testing
in the game, but they catch the mistakes that are easiest to ship by accident —
including the one where WoW silently refuses to load the whole addon.

## Run them

From the project folder (the one holding `BuffRadar\` and `build.ps1`):

```powershell
.\tools\check.ps1
```

It prints each check's result and ends with **All checks passed.** or
**FAILED:** followed by what failed (exit code 1). Then build with `.\build.ps1`.

## First time (or if the tools went missing)

```powershell
.\tools\check.ps1 -Setup
```

This creates a private tools folder at `%LOCALAPPDATA%\Temp\brlua` (pass
`-ToolsDir <folder>` to use another place): a Python environment with
[lupa](https://pypi.org/project/lupa/), which bundles real Lua 5.1, and
[luacheck](https://github.com/lunarmodules/luacheck) 1.2.0 from its official
release, checked against a known SHA-256. Nothing else on the machine changes;
deleting that folder removes it all. Windows may clean `Temp` folders now and
then — just run `-Setup` again.

## What each check does

| Check | Catches |
|---|---|
| **luacheck** | Accidental globals, unused or shadowed variables, unreachable code. Settings in `..\.luacheckrc`: reading the game's API is allowed, creating globals is reported unless listed there. |
| **Lua 5.1 compile** (`luacheck51.py`) | Anything WoW's Lua would refuse to compile. A compile error means the game skips the whole file: no window, no `/br`, no minimap button. |
| **Lua 5.1 limits** (`lualimits.py`) | Lua 5.1 allows at most 200 local variables in scope at the top of a file and 60 upvalues per function. 1.3.2's first test build broke the first limit. Warns from 195 locals / 55 upvalues. |
| **Trial run** (`smoke51.py` + `wowstub.lua`) | Errors while running: loads the addon into a fake game client, logs in, fires game events, runs every `/br` command, clicks every settings control, and checks the behavior added in 1.3.2, 1.4.0, 1.5.0, 1.6.0 and 1.7.0 (coverage, rezzed priority, session ignore, announce, ready check, expiry flag, low-mana pause, distance sort, spec profiles, export/import, compact rows, per-character position, post-combat flash, SavedVariables migration, cast sync, chat requests, join digest, role filter, toggle strip, need sort, phase skip, idle fade, named profiles, drop alert, coverage cooldown note, flight-path pause, resetpos, all-buffed pill, cast queue tag, shipped presets, consumables watch, custom watched spells, buff assignments, buddy split, blessing planner, coverage uptime, auto profiles, cover-me handoff, ready-check auto-post, coverage roster line, pin a player, tooltip remaining times, weapon enchant watch, instance-entry reminder, group expiry warning, cast history, scan throttle). Runs six setups: retail (modern client, older timer, no UI templates, German client) and Forever (two). |
| **Translations** (`localecheck.py`) | Each `Locales\*.lua` against BuffRadar's English text: keys BuffRadar doesn't use (typos, outdated text) and `%d` / `%s` / color codes that differ — both fail the check. Untranslated lines are only listed. |
| **Built zips** | Whether the zips in `dist\` still contain the current `BuffRadar.lua` (only if `build.ps1` has been run). |

## Limits of the fake game client

`wowstub.lua` imitates only the parts of the game BuffRadar uses, closely
enough to run every code path. It doesn't model layout, secure-button rules,
real casting, group play or combat restrictions, so a clean run still needs a
test in the game. When you add a feature, add a step for it in `smoke51.py`.
