# BuffRadar — Use-Case, Risk and Test Matrix

Started with 1.15.33 and updated for the 1.15.38 audit follow-up. Each row
ties a scenario to its mitigation and evidence. See the [audit ledger](AUDIT_1.15.38.md)
and [candidate matrix](FOREVER_1.15.38_VALIDATION.md) for new cases. Evidence names are trial-run steps in `tools/smoke51.py` unless
marked `coord:` (`tools/coordination51.py`) or `gate` (`tools/gate.sh` /
`tools/check.ps1`).

This matrix does not claim the addon is flawless. Every test runs in a fake
game client. In-game behaviour is only as verified as the maintainer's field
passes, and the last one covered releases through 1.15.33.

**Status key**
- **Covered:** mitigated, with an automated test that fails if the mitigation is removed.
- **Partial:** mitigated, but the test covers only part of the risk, or the evidence is review only.
- **Gap:** known and not mitigated. The reason is recorded.
- **Platform:** limited by what the game allows addons to do. Not fixable here.

## Assumptions

1. **Host:** the game client runs the addon in its Lua 5.1 sandbox. There is
   no file, network or process access, and no `loadstring` use. Protected
   actions (casting, targeting) need a hardware event and are blocked in
   combat.
2. **Primary target:** WoW: Forever, interface 16001. The Retail edition is
   frozen at 1.7.0 and is not field-tested.
3. **Trust levels:**
   - The local player's own typing is trusted for intent, but not for format.
   - Group members are partially trusted. Plan authority comes from the
     game-reported leader/assistant role (or Paladin for legacy blessings),
     never from the message itself.
   - Strangers nearby, whisper senders, and pasted or shared strings are
     untrusted.
   - Game API results are untrusted for type and readability: secret values,
     nil, errors.
4. **SavedVariables:** they can be hand-edited, truncated or written by
   another tool. They must never crash loading.
5. **Test client fidelity:** the fake client's stub (`tools/wowstub.lua`)
   follows documented API shapes. It does not reproduce taint, real frame
   timing, real addon-message throttling or the server's validation of
   chat traffic.
6. **Not a security boundary:** the addon protects the player's UI and saved
   data from malformed or hostile input. It does not stop a determined player
   from sending addon messages, and the protocol is not cryptographically
   authenticated.

## 1. Users and reasons for use

| ID | User | Reason / context | Risk if it goes wrong | Mitigation | Evidence | Status |
|---|---|---|---|---|---|---|
| U1 | Solo leveller (priest, mage, druid…) | Buff self and passers-by in the open world | Lists people it can't buff; clutter | Lists only players in range who can benefit from a known buff; nearby players need friendly nameplates | out-of-range players are never listed, then appear in range; empty list explains range, nameplate, and buff states | Covered |
| U2 | Dungeon healer or support | Keep 5 players buffed between pulls | Missed rebuffs; casting on the wrong target | Cast-next keybind bound to the displayed row; rows rebind after roster changes | scrolling virtualizes secure rows without moving the cast queue; 1.15.31 checklist | Covered (field-verified at 1.15.31) |
| U3 | Raid buffer (20–40 players) | Group buffs, blessings by class, assignments | Frame drops; duplicate casts between buffers | Throttled, coalesced scans; performance budget; caster coordination | performance budget: worst-case 40-player scan; scan throttle halves the big-group rescan; coord: request, report, reviewed publish… | Covered offline; in-game `/br perf` numbers not collected |
| U4 | Raid leader or assistant | Publish who buffs what | A non-leader hijacks the plan | Legacy plans require a readable current roster and leader; assignments require leader/assistant and blessings also permit Paladins | buff assignments from the leader tag and sink rows; group sync accepts current raid traffic and rejects unreadable authority | Covered |
| U5 | Paladin | Blessings per class, greater blessings | Wrong blessing per class | Kings-first priority, per-class choices, the group plan wins | per-class blessing choices persist and defer to the group plan; blessing plan: set, broadcast, receive, list | Covered |
| U6 | Priest who knows Shadowguard | Self-buff watch | Not shown, or shown when the spell is unknown | Shown only when the spell is known | edition buff set | Covered; in game Unverified |
| U7 | New user | First install | Overwhelming setup | Setup wizard; presets; a v9+ save counts as an existing user | saved settings: legacy saves migrate…; wizard steps | Covered |
| U8 | Non-English client | German, French, Spanish, Russian or Chinese UI | Untranslated or broken format strings | Locale completeness for German; placeholder parity checked for every locale | gate localecheck; German client uses the translation | Partial: non-German translations are machine-assisted |
| U9 | Player with low vision, colour-vision deficiency or motion sensitivity | Read the list comfortably | Colour-only meaning; flashing; small text | Tag symbols, reduced motion, text and icon scale, row spacing | 1.12.0 toggles: tag symbols, reduced motion…; saved themes, row spacing, icon size… | Covered |
| U10 | Keyboard-first or screen-reader-assisted player | Use settings without a mouse | Controls unreachable | Keyboard settings navigation; narration through the game's TTS voice | keyboard settings navigation changes tabs…; settings narration uses the standard game voice… | Partial: no audit with assistive-tech users |
| U11 | Multi-character or multi-account player | Move settings between characters | Lost or corrupted settings on import | Reviewed, local-by-default imports; caps and collision recheck; export round-trip | named settings profiles save, load…; clipboard settings imports require complete input and apply atomically | Covered |
| U12 | Support helper or addon author | Diagnose a bug report | Can't reproduce | `/br selftest`, `apicheck`, `buffcheck`, `perf`, `why`, nearby diagnostics | /br selftest prints a paste-able block; 1.12.0 diagnostics… | Covered |

## 2. Environments and contexts

| ID | Context | Risk | Mitigation | Evidence | Status |
|---|---|---|---|---|---|
| E1 | Combat | Protected-action error (taint); stale secure attributes | Window hidden, secure buttons disarmed, rebuilt after combat; `HookScript` only on secure buttons (project rule) | combat always hides the list and restores it afterward; combat cast driver requires both secure setup operations to accept; Lightning Shield secure actions rearm after combat… | Covered (taint itself is not reproducible offline) |
| E2 | Dead or ghost | Casting prompts while dead | All buff surfaces suspended | PLAYER_LOGIN while dead starts with all buff surfaces hidden and disarmed; death suspends the window… | Covered |
| E3 | Cities, battlegrounds, taxis, PvP flags | Spam; flagging yourself by buffing a PvP player | Pause in cities, battlegrounds and taxis; avoid-PvP option | context and pause steps; combat targets and caster are never eligible | Covered |
| E4 | 40-player raid | Frame time | Budget ≤8 aura reads per player, linear growth, <5 ms per scan in the fake client | performance budget: worst-case 40-player scan | Covered offline; in-game target Unverified |
| E5 | Client hides data (secret or restricted values) | Errors; or silently empty lists | Every unit and aura read goes through readability checks; "data hidden" badge | protected (secret) GUID / name from the game: no error; 1.12.0 badges…; apicheck readability tier… | Covered |
| E6 | Client API raises, returns nil or returns the wrong type | Scan aborts and the whole list disappears | Unit identity reads guarded (`X.UnitPresent`, `X.UnitGUIDOf`, `X.UnitClassToken`, `X.UnitNameOf`); one bad unit is skipped | hardening regressions: … one bad unit; robustness fuzz (API chaos, per-API raise) | Covered (fixed in this change) |
| E7 | Clients without `C_Timer` or UI templates | Feature breaks on older or alternative clients | Fallback `OnUpdate` timer; fallback settings look | seven trial-run setups; optional template refusal on Settings and review | Covered |
| E8 | Spell-range API silent (other realms, nameplate limits) | Lists unreachable players, or no one | Fails closed; opt-in `assumerange`; checked-distance fallback | range uses checked distance only when both spell range answers are unavailable; assumeRange lists players… | Covered |
| E9 | Other addons: UI suites, boss mods, Edit Mode | Clashing visuals; spoofed pull timers | Auto theme checks exact folders; boss-mod pulls require matching group channel and trusted sender; ambiguous stops do not cancel a replacement | Auto theme opts in…; pull timer: probe counts…; changing a pull timer keeps its replacement… | Covered |
| E10 | Reload or relog mid-session | Lost state; stale casts | Schema 23 keeps an untouched future or over-limit user save and resets session state on entering the world | migration chain steps | Covered |
| E11 | Game patch changes spell IDs or APIs | Buffs silently missing | `/br buffcheck`, `/br apicheck`; `IsPlayerSpell` gating | 1.12.0 diagnostics… | Partial: detects but can't self-repair |

## 3. Inputs and trust boundaries

| ID | Input (trust) | Risk | Mitigation | Evidence | Status |
|---|---|---|---|---|---|
| I1 | Settings import `BR1` (untrusted paste) | Crash; partial apply; injected values | 16 KiB cap; full required-field set; per-field type and range decode; atomic apply | clipboard settings imports require complete input…; robustness fuzz (1,000+ inputs, field mutations, round trip) | Covered |
| I2 | Profile string `BR2` / shared profile (untrusted) | Same as I1; oversized saved profiles | Size limits; enum checks; invalid profile preserves the existing save | profile limits and validation preserve an existing save; robustness fuzz | Covered |
| I3 | Plan string `BRPLAN1` (untrusted) | Hijacked assignments; markup in holder names | Bounded key/holder syntax; reviewed local apply; explicit share scoped to current roster and roles | plan import validates atomically…; audit plan review and authority drift | Covered offline |
| I4 | Ignore-list string `BRI1` (untrusted) | Flooding SavedVariables; markup names | 16 KiB string and 192-name saved caps checked before any additions; ≤64 bytes per name, no `\|`, `;` or control characters | hardening regressions; audit storage limits | Covered offline |
| I5 | Assignment mask (from profiles) | Crash on wrong type | String-only, canonical digits, range-checked | hardening regressions; robustness fuzz | Covered (fixed in this change) |
| I6 | Addon messages (group members) | Forged plans; replay; oversized messages; spoofed sender | Prefix, channel, sender and 255-byte checks; scoped SYNC v3 for caster coordination, roster/authority cleanup for legacy ASSIGN/BLESS | coord: (22 cases); audit remote-plan ownership; fuzz | Partial: legacy ASSIGN/BLESS has no wire generation |
| I7 | Whispers and `/say` containing "buff" (anyone nearby) | Sound spam; tagging strangers | Matches listed players only; sound ≤1 per second overall and ≤1 per 30 s per player; `/br requests off` | chat request tags the asker; robustness fuzz | Covered |
| I8 | Slash command arguments (local player) | Error output; bad stored values | Every handler runs in `pcall`; per-command validation; `/br ignore` validates names | robustness fuzz (1,500 random commands, no "error:" output) | Covered |
| I9 | SavedVariables (hand-edited or corrupt) | Crash at load; NaN or infinity propagating; wrong types | Detached finite typed validation; future/overflow preservation; migration chain v2→v23 | legacy migration, fuzz and detached-save audit fixtures | Covered |
| I10 | Game event payloads (`UNIT_AURA`, roster, nameplates) | Refresh storms | Untracked units ignored; coalesced to 0.1 s; ticker every 0.4 s | UNIT_AURA on an NPC nameplate / boss / pet: no refresh; fallback event refresh coalesces… | Covered |
| I11 | Any user or peer text reaching `find`/`match`/`gmatch`/`gsub` | Pattern injection ("malformed pattern" errors, wrong matches) | Every pattern argument is a literal or the call is a plain find; enforced by `tools/patterncheck.py`; edit boxes have max lengths | gate patterncheck (fails on a non-literal pattern) | Covered (added in this change) |

## 4. Failure modes

| ID | Failure | Effect | Mitigation | Evidence | Status |
|---|---|---|---|---|---|
| F1 | Runtime error inside a scan | List stops updating | `SafeRefresh` wraps the scan in `pcall`; the error is printed once, not per frame | robustness fuzz | Covered |
| F2 | Cast fails (line of sight, range, invalid target) | Queue stuck on one player | Target-failure messages skip that player for 30 s; other errors stay pending | range and invalid-target failures skip the current player; empty-state steps | Covered |
| F3 | Roster changes between render and key press | Buffs the wrong person | Slot occupant check clears a stale binding | 1.15.31 checklist; cast-next steps | Covered |
| F4 | Lua 5.1 local or upvalue ceilings | Addon fails to load after an edit | `tools/lualimits.py` in the gate | gate | Covered (main chunk 165/200, `HandleSlash` 58/60 upvalues) |
| F5 | Locale string with a mismatched placeholder | `string.format` error | `localecheck` checks placeholder parity | gate | Covered |
| F6 | Package missing a file or in the wrong load order | Addon broken on install | `checkpackage.py` loads the ZIP in TOC order; release assets hash-verified after upload | gate; release workflow | Covered |
| F7 | Chat send refused (throttle or channel) | Silent report failure | Refusal leaves a local report; nil or true describes submission/acceptance, not delivery; 255-byte cap | audit chat report outcomes in PARTY and RAID mocks | Partial: live chat routes and delivery pending |

## 5. Security, privacy and abuse

| ID | Abuse or exposure | Mitigation | Evidence | Status |
|---|---|---|---|---|
| S1 | A group member forges leader plans | Authority taken from the game's unit role, never from the payload | buff assignments from the leader…; coord: | Covered |
| S2 | Replay or delayed messages after a roster or leader change | SYNC v3 epoch proofs, replay floors and bounded pending queues (≤2 epochs, ≤8 packets each); legacy overlays retire on authority or membership loss | coord: roster/leader boundary cases; audit legacy overlays | Partial: legacy plan replay after a valid scope returns is not proven preventable |
| S3 | Malicious shared import string | Size caps, strict decode, atomic apply, round trip | I1–I5 | Covered |
| S4 | Markup injection (`\|c`, `\|T`, `\|H`) through names | `\|` rejected in addon-message names, plan holders and ignore entries | hardening regressions; code review of `ValidName` | Partial: free-text names from the game itself are trusted as game-sanitized |
| S5 | Unbounded saved growth | 32 profiles, 192 permanent ignores, 64 per-character anchors, 192 stat keys, 50 history slots, 50 stored offenders, 20 custom group pairs. Session offender collection limited to 128 GUIDs | bounded writer/load and overflow recovery fixtures | Covered for saved collections; a preserved legacy save is intentionally not truncated |
| S6 | Privacy: other players' names stored locally (ignore list, stats, history) | Local SavedVariables only; no network; exports are user-initiated | SECURITY.md (risk tier 0) | Covered by design |
| S7 | Privacy: names shared through Discord or stats exports | Shown in a copy box for the user to paste; nothing is sent automatically | stats export and Discord summary render | Covered by design |
| S8 | Botting or automation | Casting requires a hardware event; no auto-cast (`/br rangewatch` only notifies) | platform | Platform |
| S9 | Sound or alert harassment through `/say` | Per-second and per-player throttles; requests can be turned off | I7 | Covered |
| S10 | Supply chain (CI dependencies, release) | Pinned actions by SHA; lupa pinned; luacheck hash-pinned; release bytes re-downloaded and compared | release.yml; check.ps1 | Covered |

## 6. Self-review against this matrix (2026-11-16)

**Found and fixed by this pass:**
- `X.DecodeAssignment` raised on non-string input (I5).
- Ignore-list import had no size cap, and both ignore paths stored names
  containing `|` escape codes (I4, S4, S5).
- Plan holders accepted control characters (I3).
- Sixteen raw calls to `UnitExists`, `UnitGUID`, `UnitClass` and
  `UnitName` in `BuffRadar.lua`, plus two in the nearby diagnostics, could
  abort a whole refresh if the client raised (E6). They now go through
  guarded helpers.

**How the fixes were checked:**
- Each fix has a regression assertion. Running the new tests against the
  unfixed source fails at every fixed site.
- The fuzz runs with seed 4242 in the gate. Seeds 7, 99 and 31337 also came
  back clean in a local run.
- A depth floor fails the fuzz if mutated inputs stop reaching the
  accepting import paths.

**Coverage summary:** offline mitigations do not remove the residual risks
below. Keep the current Windows and in-game results with the tested ZIP hash.

## 7. Residual risks and limitations

- **Fake client:** taint, real frame timing, server-side addon-message
  throttling and real secret-value behaviour can't be reproduced offline. A
  passing gate is evidence, not proof.
- **In-game verification:** releases through 1.15.33 are field-verified;
  1.15.34–1.15.38 are Unverified in game. Windows package parity passed in
  CI; see the [candidate matrix](FOREVER_1.15.38_VALIDATION.md).
- **Fuzzing is sampled:** about 1,000 inputs per parser, 3,000 messages,
  1,500 commands, 250 corrupt saves and 200 API-chaos rounds per setup. It
  finds shallow-to-medium defects; it can't prove their absence. The
  settings import's strictness means most random inputs are, correctly,
  rejected early.
- **Settings import paths:** the depth floor checks that the accepting paths
  are reached, but not every field's boundary.
- **Pattern check is line-based:** `tools/patterncheck.py` reads one line at
  a time. A pattern call split across lines, or one reached through an
  alias such as `local find = string.find`, is not inspected.
- **Unauthenticated protocol:** coordination relies on game-reported roles
  and the protocol is not cryptographically authenticated. A group leader
  can always publish a bad plan. Legacy assignment/blessing and boss-mod
  traffic do not carry a unique generation. Cleanup and matching avoid
  retaining stale local state; they do not prove that all late packets are
  fresh.
- **Accessibility:** there's no external audit with screen-reader or
  switch-access users, and the in-game narration depends on the client's
  TTS voice.
- **Translations:** non-German locales are machine-assisted and not
  reviewed by native speakers.
- **Diagnostics:** `UnitClass("player")` calls in the slash and profile
  code stay unguarded. They run on the player's own command, and any error
  there is caught and printed by the slash `pcall`.
