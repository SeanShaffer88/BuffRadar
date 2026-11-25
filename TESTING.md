# Testing and verification

**Candidate:** BuffRadar 1.20.2 · WoW: Forever · Interface 16001

**Live-client verification:** **PASS (maintainer-reported).** On 2026-11-25, the maintainer reported all field checks passed using BuffRadar 1.20.2 on WoW Forever 1.60.1.71037, Windows 11 x64. Exact candidate ZIP: `BuffRadar-1.20.2-Forever.zip`; SHA-256: `403987d4da0e759f3e165ffc4b95f69e9719d6c0854800c2d3ae6abc1dd386e2`. No screenshots or diagnostic logs were attached, so the in-game results have not been independently observed here. See [`docs/FIELD_TEST.md`](docs/FIELD_TEST.md) for the field protocol.

## Automated verification

Run the repository gate with Python 3.10 or newer and `lupa==2.8` installed:

```sh
python3 -m pip install --only-binary=:all: lupa==2.8
sh tools/gate.sh
```

The gate runs static Lua, limits, localization, locale-flow and pattern checks; fake-client smoke suites; coordination, relog, theme, Actions, diagnostics, and package regression tests. Its fake clients exercise these configurations:

- Retail declared-TOC files without Extras;
- modern timer and UI-template support;
- delayed callbacks without a recurring ticker;
- missing UI templates;
- Forever modern-client and delayed/no-template variants; and
- German localization.

The v1.20.2 release-prep tree passed the local gate, including 3,271 smoke steps with zero errors across the seven configurations listed above. The built Forever ZIP passed package verification (40 files, 30 TOC entries, five bindings) with SHA-256 `403987d4da0e759f3e165ffc4b95f69e9719d6c0854800c2d3ae6abc1dd386e2`. [PR CI](https://github.com/SeanShaffer88/BuffRadar/actions/runs/45661223715) and [post-merge CI](https://github.com/SeanShaffer88/BuffRadar/actions/runs/45661724840) passed, including the Windows/POSIX package-digest comparison. Automated checks exercise controlled test clients; they do not independently verify live-client behavior.

The separate real luacheck 1.2.0 run was not performed in this Linux workspace; the repository's `tools/check.ps1` wrapper requires Windows. The Lua 5.1 static/compiler checks in the gate passed.

### Safety and pause coverage in the fake client

The Lua smoke suite includes regressions for combat entry/exit, secure action arming, combat visibility, death/ghost suspension and recovery, stale cast recipients, in-combat aura events, city pauses, flight-path pauses, and delayed event refreshes. The tests verify addon logic against controlled API stubs. A passing fake-client assertion is **not** a live taint or protected-action test.

### API coverage in the fake client

Tests exercise the read-only `BuffRadarAPI` status surface, including `GetSummary`, `GetStatus`, `GetUnit`, and `GetDisplay`; unavailable/stale states; independent returned snapshots; change notifications; and status changes across combat. Game API responses in the automated suite are supplied by test doubles. The maintainer reported that the real Forever client's scenarios and diagnostics passed on the build above; no raw diagnostic output was attached.

## Event and timer audit

A source review of `BuffRadar/BuffRadar.lua` and `BuffRadar/Intelligence.lua` found no addon-installed per-frame `OnUpdate` scan. The primary queue refresh is requested by relevant game events, including group/roster changes, zone/world transitions, player movement, `UNIT_AURA`, nameplate add/remove, spellbook changes, cooldown/range events, and cast events. Bursts are coalesced; they do not create a recurring player or aura scan.

There is one deliberate low-frequency `C_Timer.NewTicker` (1.5 seconds). It maintains presentation/expiry state and runs a cooldown-readiness sweep over the known buff spell list. If that sweep sees a readiness change, it requests a coalesced queue refresh. `C_Timer.After` is also used for one-shot event coalescing, spellbook rebuilds, and delayed life-state recovery; these callbacks are not independent periodic player scans. When the optional ticker is unavailable, the queue continues to refresh from events, but the cooldown sweep is absent.

`/br throttle` is retained as a backward-compatible command name. It adapts the low-frequency cooldown sweep cadence using movement, group size, and latency; it does **not** throttle the primary roster/aura refresh events. This distinction is now reflected in the settings label and help text. The sweep remains a polling fallback rather than claiming every observation is event-only.

## Live-client verification status

**All rows below are `PASS (maintainer-reported)` for the exact candidate ZIP above.** No screenshots or diagnostic logs were attached.

| Live scenario | Status | Evidence |
|---|---|---|
| Candidate ZIP SHA-256, client build, platform, and addon version captured | PASS (reported) | ZIP digest, WoW Forever 1.60.1.71037, Windows 11 x64, BuffRadar 1.20.2; 2026-11-25 |
| Enter combat with a ready cast; confirm action disarms and no blocked/forbidden-action error occurs | PASS (reported) | Maintainer report; no log attached |
| Leave combat; verify action re-arms only after lockdown ends and queue refreshes | PASS (reported) | Maintainer report; no log attached |
| Repeat safety check while dead/ghosted and immediately after resurrection | PASS (reported) | Maintainer report; no log attached |
| City, battleground/arena, flight-path, and group-only pause toggles | PASS (reported) | Maintainer report; no log attached |
| Roster, aura, nameplate, cooldown, and movement-triggered updates; compare `/br throttle` on/off | PASS (reported) | Maintainer report; no log attached |
| Blessing complement against another Paladin's Kings; check class alternate and assignment precedence | PASS (reported) | Maintainer report; no log attached |
| Core client API diagnostics and status bridge (`/br apicheck export`, `/br buffcheck`, `/br status export`, `/br bridge`) | PASS (reported) | Maintainer report; no log attached |

For the complete safety, cast, pause, and evidence procedure, follow [`docs/FIELD_TEST.md`](docs/FIELD_TEST.md). Record each result as `PASS`, `FAIL`, or `NOT RUN`; include the exact ZIP digest and redact player names before sharing logs. Do not convert a pending test into a pass based on the offline suite.
