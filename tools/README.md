# BuffRadar checks

Automated checks to run before building a release. They don't replace testing
in the game, but they catch the mistakes that are easiest to ship by accident —
including the one where WoW silently refuses to load the whole addon.

## Run them

On Windows, open **PowerShell 7** in the project folder (the one holding
`BuffRadar\` and `build.ps1`). In File Explorer, open that folder and type
`pwsh` into the address bar. Install Python 3.10 or newer first if `py -3 --version`
doesn't find it. Follow the one-time setup below, then run:

```powershell
.\tools\check.ps1
```

If you already have a BuffRadar tools folder, pass it with
`-ToolsDir 'C:\path\to\brlua'`. From a Unix shell with Python 3 and Lupa
available, use `sh tools/gate.sh` to run the same gate used by GitHub CI.

The checker exits nonzero on failure. A compiler failure stops the run before
smoke. Run Luacheck 1.2.0 separately from the POSIX gate.

## Build and verify the ZIP

Use `.\build.ps1` from PowerShell or `sh tools/package.sh` from POSIX. Both
call `tools/package.py`, write a deterministic ZIP and checksum to `dist/`,
and accept `--tag vX.Y.Z` to require an exact TOC match. Build before running
`check.ps1` again to include the current ZIP in its checks, or verify directly
with the Python environment that has Lupa installed:

```sh
python -I tools/checkpackage.py dist/BuffRadar-X.Y.Z-Forever.zip .
```

Replace `X.Y.Z` with the TOC version. The final `.` checks ZIP inventory and
bytes against the current source, including the adjacent `SHA256SUMS.txt`.
CI builds on Windows and POSIX and compares SHA-256 digests. Build twice
before freezing a candidate, and use that exact ZIP for the field checklist.

To run only the two-client Caster Coordination harness with the checker’s
Python environment, use:

```powershell
& 'C:\path\to\brlua\Scripts\python.exe' -I tools/coordination51.py tools/wowstub.lua BuffRadar/BuffRadar.lua
```

Run only the offline relog checks with the same Python environment:

```powershell
& 'C:\path\to\brlua\Scripts\python.exe' -I tools/relog51.py tools/wowstub.lua BuffRadar/BuffRadar.lua
```

This starts separate Lua clients. Only plain saved settings, native macro slots,
bindings, and action-bar references cross the restart boundary. Frames, queues,
timers, and addon closures are recreated. The checks cover graceful logout and
abrupt restart, macro newline handling, changed recipients, bindings, empty
queues, and Auto theme resolution against the new client's loaded addons.

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
| **Lua 5.1 compile** (`luacheck51.py`) | Compiles all shared Lua and locale files in PowerShell and POSIX. A compiler failure stops the gate before the trial run. |
| **Lua 5.1 limits** (`lualimits.py`) | Estimates headroom against Lua 5.1's limits of 200 active locals and 60 upvalues per function. The checker warns from 195 locals or 55 upvalues. The estimates are advisory. |
| **Trial run** (`smoke51.py` + `wowstub.lua`) | Loads each edition in its TOC order. Checks startup and save migrations, cast attributes and event bookkeeping, window layout and controls, profile round trips, slash commands, and scan performance. `audit51.lua` contains isolated hardening regressions. Runs seven setups: both declared TOCs, plus variations for Extras on Retail, timers, UI templates, and German. |
| **Translations** (`localecheck.py`) | Each `Locales\*.lua` against BuffRadar's English text: keys BuffRadar doesn't use (typos, outdated text) and `%d` / `%s` / color codes that differ — both fail the check. Missing German keys fail; untranslated keys in partial locales are reported. |
| **Lua pattern arguments** (`patterncheck.py`) | Every `find` / `match` / `gmatch` / `gsub` pattern must be a string literal, or the call must be a plain find (`:find(x, 1, true)`), so player names, chat and imports can never be read as patterns. One line at a time; a non-literal pattern fails the check. |
| **Packaging regressions** (`test_package.py`) | Rebuilds from independent source trees and checks repeat bytes, version/tag rejection, link and path refusal, source drift, archive metadata, checksums and exact bindings. |
| **Forever package** | If a ZIP for the current version exists in `dist\`, checks its bytes against the current source, TOC metadata, declared Lua load order, and XML bindings in a Forever mock, including `/br selftest` version readback. CI builds and checks the archive on every PR. |
| **Two-client coordination** (`coordination51.py`) | Loads two independent Forever mock clients. Relays their real plan, cast, and session-proof packets. Checks plan acceptance, bidirectional cast sync, and replay rejection across roster and leadership changes. |
| **Offline relog** (`relog51.py`) | Restarts into a separate Lua runtime using copied durable game data. Checks settings, managed macros, bindings, rebuilt queue targets, and Auto themes without carrying transient addon state across clients. |
| **Theme preview** (`theme_preview51.py`) | Checks transient rendering, Apply and Cancel, Auto candidate resolution, conflicting edits, combat invalidation, and the keyboard-accessible preview panel. |
| **Actions search** (`actions51.py`) | Checks action categories, settings filters, paged results, read-only availability, activation guards, command equivalents, argument forms, keyboard navigation, narration and the optional Actions binding. |
| **Battleground and blessing diagnostics** (`diagnostics51.py`) | Checks pause explanations, exact combat/PvP flags, cached blessing knowledge, selection precedence and complement reasons, unknown API values, report privacy, and isolated reads on success and error. |

## Limits of the fake game client

`wowstub.lua` imitates only the parts of the game BuffRadar uses, closely
enough to exercise the addon's logic and record widget writes. It is not a
renderer or a secure execution environment. A clean run still needs an in-game
test of real casting, controller input, combat lockdown, and visual layout. When you add a feature, add a step for it in `smoke51.py`.

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
