# BuffRadar checks

Automated checks to run before building a release. They don't replace testing
in the game, but they catch the mistakes that are easiest to ship by accident —
including the one where WoW silently refuses to load the whole addon.

## Run them

On Windows, open **PowerShell 7** in the project folder (the one holding
`BuffRadar\` and `build.ps1`). In File Explorer, open that folder and type
`pwsh` into the address bar. Install Python 3 first if `py -3 --version`
doesn't find it. Follow the one-time setup below, then run:

```powershell
.\tools\check.ps1
```

If you already have a BuffRadar tools folder, pass it with
`-ToolsDir 'C:\path\to\brlua'`. From a Unix shell with Python 3 and Lupa
available, use `sh tools/gate.sh` to run the same gate used by GitHub CI.

The checker prints each result and ends with **All checks passed.** or
**FAILED:** followed by what failed (exit code 1). Then build with `.\build.ps1`.

To run only the two-client Caster Coordination harness with the checker’s
Python environment, use:

```powershell
& 'C:\path\to\brlua\Scripts\python.exe' -I tools/coordination51.py tools/wowstub.lua BuffRadar/BuffRadar.lua
```

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
| **Lua 5.1 compile** (`luacheck51.py`) | Compiles every Lua file listed in the Forever TOC. A nonzero compiler exit stops the checker before the trial run. |
| **Lua 5.1 limits** (`lualimits.py`) | Estimates headroom against Lua 5.1's limits of 200 active locals and 60 upvalues per function. The checker warns from 195 locals or 55 upvalues. The estimates are advisory. |
| **Trial run** (`smoke51.py` + `wowstub.lua`) | Errors while running: loads the addon into a fake game client, logs in, fires game events, runs every `/br` command, clicks every settings control, and checks the behavior added in 1.3.2, 1.4.0, 1.5.0, 1.6.0 and 1.7.0 (coverage, rezzed priority, session ignore, announce, ready check, expiry flag, low-mana pause, distance sort, spec profiles, export/import, compact rows, per-character position, post-combat flash, SavedVariables migration, cast sync, chat requests, join digest, role filter, toggle strip, need sort, phase skip, idle fade, named profiles, drop alert, coverage cooldown note, flight-path pause, resetpos, all-buffed pill, cast queue tag, shipped presets, consumables watch, custom watched spells, buff assignments, buddy split, blessing planner, coverage uptime, auto profiles, cover-me handoff, ready-check auto-post, coverage roster line, pin a player, tooltip remaining times, weapon enchant watch, instance-entry reminder, group expiry warning, cast history, scan throttle). Runs six setups: retail (modern client, older timer, no UI templates, German client) and Forever (two). |
| **Translations** (`localecheck.py`) | Each `Locales\*.lua` against BuffRadar's English text: keys BuffRadar doesn't use (typos, outdated text) and `%d` / `%s` / color codes that differ — both fail the check. Untranslated lines are only listed. |
| **Lua pattern arguments** (`patterncheck.py`) | Every `find` / `match` / `gmatch` / `gsub` pattern must be a string literal, or the call must be a plain find (`:find(x, 1, true)`), so player names, chat and imports can never be read as patterns. One line at a time; a non-literal pattern fails the check. |
| **Forever package** | If a ZIP for the current version exists in `dist\`, checks its bytes against the current source, TOC metadata, declared Lua load order, and XML bindings in a Forever mock. CI builds and checks the archive on every PR. |
| **Two-client coordination** (`coordination51.py`) | Loads two independent Forever mock clients. Relays their real plan, cast, and session-proof packets. Checks plan acceptance, bidirectional cast sync, and replay rejection across roster and leadership changes. |

## Limits of the fake game client

`wowstub.lua` imitates only the parts of the game BuffRadar uses, closely
enough to run every code path. It doesn't model layout, secure-button rules,
real casting, group play or combat restrictions, so a clean run still needs a
test in the game. When you add a feature, add a step for it in `smoke51.py`.

The two-client harness controls message order and duplicates in memory.
Its assertions cover the addon’s handling of those messages. The harness
does not exercise the game’s channel delivery or protected casting.

The regular gate replays old requests and plans together after re-opt-in. It
also replays cast packets and session proofs with the original caster and
target still in the group. It tests a roster change seen only by the receiving
client, delayed and duplicate proofs, a fresh cast arriving before its proof,
and a timed retry with no new application traffic.

Forever caster plans and cast sync require both clients to use scoped protocol
version 3. When a roster and its leadership return to a previous state, the
client broadcasts a challenge. Each sender's proof establishes the sequence
cutoff. A first fresh cast or plan request sent after that proof can sync
without another round trip. If peers remain unverified after three seconds,
the client broadcasts one more challenge with a new nonce. Either proof can
verify a pending peer during the second window. Further proofs leave that
peer's cutoff intact. If both attempts expire, the next packet uses a targeted
challenge and may itself be dropped. BuffRadar only retries the challenge.
