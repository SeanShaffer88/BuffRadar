# Testing and verification

**Candidate:** BuffRadar 1.20.0 · WoW: Forever · Interface 16001  
**Live-client verification:** **Not performed.** No WoW: Forever client session, client build, or in-game test evidence is available for this candidate. The automated results below are offline tests and must not be read as proof of live-client combat-lockdown, taint, API, or gameplay behavior. See [`docs/FIELD_TEST.md`](docs/FIELD_TEST.md) for the step-by-step field protocol.

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

The current working tree's local gate passed all configured offline suites, including 3,271 smoke steps with zero errors across the seven configurations listed above. Its locally built Forever package also passed the package-content check. CI on the v1.20.0 release commit passed the pull-request and post-merge gates, including the Windows/POSIX package-digest comparison; that CI result does not cover later uncommitted changes in this working tree. These checks establish reproducible source and package behavior in the test harness; they do not emulate the WoW client's secure execution or prove compatibility with every live client build.

### Safety and pause coverage in the fake client

The Lua smoke suite includes regressions for combat entry/exit, secure action arming, combat visibility, death/ghost suspension and recovery, stale cast recipients, in-combat aura events, city pauses, flight-path pauses, and delayed event refreshes. The tests verify addon logic against controlled API stubs. A passing fake-client assertion is **not** a live taint or protected-action test.

### API coverage in the fake client

Tests exercise the read-only `BuffRadarAPI` status surface, including `GetSummary`, `GetStatus`, `GetUnit`, and `GetDisplay`; unavailable/stale states; independent returned snapshots; change notifications; and status changes across combat. Game API responses are supplied by test doubles. The real Forever client's unit, aura, spellbook, cooldown, and lockdown APIs have not been exercised for this candidate. In-game `/br apicheck`, `/br buffcheck`, `/br selftest`, and `/br perf` are diagnostics a field tester can use; running those commands is not a substitute for recording the scenario results below.

## Event and timer audit

A source review of `BuffRadar/BuffRadar.lua` and `BuffRadar/Intelligence.lua` found no addon-installed per-frame `OnUpdate` scan. The primary queue refresh is requested by relevant game events, including group/roster changes, zone/world transitions, player movement, `UNIT_AURA`, nameplate add/remove, spellbook changes, cooldown/range events, and cast events. Bursts are coalesced; they do not create a recurring player or aura scan.

There is one deliberate low-frequency `C_Timer.NewTicker` (1.5 seconds). It maintains presentation/expiry state and runs a cooldown-readiness sweep over the known buff spell list. If that sweep sees a readiness change, it requests a coalesced queue refresh. `C_Timer.After` is also used for one-shot event coalescing, spellbook rebuilds, and delayed life-state recovery; these callbacks are not independent periodic player scans. When the optional ticker is unavailable, the queue continues to refresh from events, but the cooldown sweep is absent.

`/br throttle` is retained as a backward-compatible command name. It adapts the low-frequency cooldown sweep cadence using movement, group size, and latency; it does **not** throttle the primary roster/aura refresh events. This distinction is now reflected in the settings label and help text. The sweep remains a polling fallback rather than claiming every observation is event-only.

## Live-client verification status

**All rows below are `NOT RUN` for this candidate.** Complete these on the exact release ZIP and record the game build and evidence before describing the release as field-verified.

| Live scenario | Status | Evidence required |
|---|---|---|
| Candidate ZIP SHA-256, client build, platform, and addon version captured | NOT RUN | Exact values and test date |
| Enter combat with a ready cast; confirm action disarms and no blocked/forbidden-action error occurs | NOT RUN | In-game observation and any error text |
| Leave combat; verify action re-arms only after lockdown ends and queue refreshes | NOT RUN | In-game observation |
| Repeat safety check while dead/ghosted and immediately after resurrection | NOT RUN | In-game observation, including delayed living-flag recovery |
| City, battleground/arena, flight-path, and group-only pause toggles | NOT RUN | Test each toggle on and off; record where the queue pauses and resumes |
| Roster, aura, nameplate, cooldown, and movement-triggered updates; compare `/br throttle` on/off | NOT RUN | Test setup, observations, and `/br perf` output |
| Core client API diagnostics and status bridge (`/br apicheck export`, `/br buffcheck`, `/br status export`, `/br bridge`) | NOT RUN | Redacted diagnostic output and observed status; confirm bridge remains read-only |

For the complete safety, cast, pause, and evidence procedure, follow [`docs/FIELD_TEST.md`](docs/FIELD_TEST.md). Record each result as `PASS`, `FAIL`, or `NOT RUN`; include the exact ZIP digest and redact player names before sharing logs. Do not convert a pending test into a pass based on the offline suite.
