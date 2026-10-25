<p align="center"><img src="BuffRadar/Media/logo.png" alt="BuffRadar logo" width="160"></p>

# BuffRadar

A click-to-buff list for World of Warcraft: a small window listing every nearby
player who is missing one of *your* buffs. Click a name, press one key or use one
macro to buff them. You always come first.

Two editions are built from the same source:

| Edition | Client | Interface |
|---|---|---|
| **Retail** | World of Warcraft (Midnight, patch 12.1.5) | 120105 |
| **Forever** | World of Warcraft Forever | 16001 |

BuffRadar picks the right buff set when it loads. The full player guide — features,
supported buffs, commands — is in [BuffRadar/README.md](BuffRadar/README.md);
what changed is in [BuffRadar/CHANGELOG.md](BuffRadar/CHANGELOG.md).

## TL;DR

BuffRadar is a World of Warcraft addon that keeps a small list on your screen
of everyone nearby who still needs one of your buffs — like a to-do list that
ticks people off as you buff them. Click a name to cast. It comes in two
editions (Retail and Forever) built from one source, it's free, and it works
entirely inside the game: no accounts, no network, nothing leaves your PC.

## Layout

| Path | What it is |
|---|---|
| `BuffRadar/` | The addon: `BuffRadar.lua`, `Locales/`, `Media/`, `Bindings.xml`, plus the Retail edition's `.toc`, README and changelog |
| `editions/forever/` | The Forever edition's `.toc`, README and changelog |
| `build.ps1` | Builds `dist/BuffRadar-<version>-Retail.zip` and `-Forever.zip` |
| `tools/` | Automated checks — see [tools/README.md](tools/README.md) |
| `.luacheckrc` | luacheck settings used by the checks |
| `AGENTS.md` | Project rule sheet (prompt in force, frozen foundation, gate) |
| `QUALITY.md` | Quality scorecard, scored from evidence |
| `docs/` | `PARITY.md` (capability matrix) and `DECISIONS.md` (decision log) |
| `SECURITY.md` | How to report a security problem, privately |

## Making a release

```powershell
.\tools\check.ps1 -Setup   # first time only
.\tools\check.ps1          # luacheck, Lua 5.1 compile and limits, translations, trial run
.\build.ps1                # both zips into dist\
```

Then test both zips in the game. Each zip holds a `BuffRadar` folder that goes in
`Interface\AddOns`.

## License

Copyright © 2026 Malikor. BuffRadar is free software under the GNU General Public
License, version 3 or (at your option) any later version — see [LICENSE](LICENSE).
