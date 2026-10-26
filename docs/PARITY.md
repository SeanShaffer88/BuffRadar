# Parity / Capability Matrix — BuffRadar

Updated: 2026-10-25 · Overall readiness: the core product is complete and
shipped at 1.10.0 — **Forever-only since 1.8.0** (Retail support dropped
by SEAN 2026-10-25; Retail ended at 1.7.0). The approved 50-item
enhancement program is **complete**: 44 of 50 shipped (1.6.0 + 1.7.0 +
1.8.0 + 1.9.0), 3 resolved as duplicates (each replaced in-batch), and
3 parked under investigation with their reasons recorded below. A
further SEAN-requested customization batch (10 items) shipped in
1.10.0, listed after the program below. Every
"Complete" below names its test
evidence. Nothing here is scored from in-game behaviour — the addon is
**Unverified in game** since 1.3.2 (see the Gap column and `QUALITY.md`).

| Area | Target | State | Evidence (test / corpus) | Gap |
|---|---|---|---|---|
| Core list & casting | Missing-buff list for group + nearby players; click / keybind / macro casting; you first | Complete | Trial run: list building, click-cast paths (target/id/macro/rank), BuffRadarNextButton + macro sync, in all 6 setups | In-game click-cast on both clients Unverified |
| Retail buff set | All 13 classes, patch 12.1.5 set | Complete | Edition + per-class steps in the Retail setups | Unverified in a live retail client |
| Forever buff set | Classic set incl. blessings, ranks, group variants | Complete | Forever setups incl. rank-table and Kings-first steps | Unverified in a live Forever client since 1.2.2 |
| Coordination (1.5.0–1.8.0) | Cast sync, chat requests, assignments, buddy split, blessing plan, peer hello, cover-me handoff, coverage roster, plan strings | Complete (batches 1–3) | Trial steps: sync handled-marks, request tags, leader-trust assignment sink/float, buddy hash split, blessing plan set/broadcast/receive, cover handoff + return, roster line, plan export/import round-trip — 6 setups | All multi-user behaviour Unverified in game (needs a second BuffRadar user) |
| List & window | Sorts (name/role/distance/need), filters, strip, chips, pill, idle fade, rescue, pin, name finder, grow-up anchor, combat hide, color themes, two-column layout, saved custom themes, row spacing + icon size, window strata, click-through while locked, group-by-buff view | Complete (batches 1–4 + 1.10.0) | Trial steps per feature, incl. pill show/hide/peek, off-screen rescue via `/br resetpos`, pin order under name sort, find filter, grow-up anchor, combat hide/show, theme cycle, two-column split + widen/narrow (harness records anchors + width); 1.10.0 steps: theme save/apply/delete + sanitizer round-trip, row-pitch + icon-size deltas, frame strata, click-through mouse flags locked/unlocked, buff-view fold + cast target | Window load-rescue branch itself is not smoke-covered (harness limit) |
| Rows & interaction | Tags (expired/rezzed/asked/handled/queued/assigned/buddy/pinned/weapon/drinking/pet), portraits, compact rows, text scale, tooltips (3 detail levels), duration bars, raid markers, range text, focus line, coverage-line part toggles, row color marks, name formats (class colors / realm / trim), buff priority order | Complete (batches 1–3 + 1.10.0) | Tag-priority steps incl. queue + pinned + weapon + drinking tags; tooltip step (recorder GameTooltip: missing + remaining-time lines); bars/markers/range/focus steps; 1.10.0 display step (coverage part off/on, tooltip minimal/full lines, tank color mark, realm + trimmed names, plain name color); priority step (offer order flips + resets) | The aura/aspect note in the row below applies as before |
| Coverage expansion | Built-in buffs + consumables + custom spells + uptime + weapon watch + pets + aura/aspect watch + per-buff context + world-buff watch + healer drinking | Complete (batches 1–3) | Consumable tally, custom add/remove/list, uptime scoring, weapon flag on/off steps; pet rows + report exclusion, context gating (incl. the SHADOW_PROT instance default), world-buff line, drinking tag + coverage count steps | Weapon watch reads temporary weapon enchants only (GetWeaponEnchantInfo); solo with no other row, the reminder waits for a row or a group. The aura/aspect watch's positive path (a hunter/paladin who knows an aspect/aura spell) is not smoke-covered — the harness spellbook is a priest's/shaman's; toggle + edition gating are covered |
| Alerts | New-name alert, drop alert, post-combat flash, instance-entry reminder, group expiry warning, a sound per alert kind | Complete | Alert + flash steps; entry reminder fires-once step; expiry tally step (3 holders < 5 min); 1.10.0 per-kind sound step (save/change/master via `/br soundfor`) | #33 under investigation (overlaps new-name alert) |
| Stats & reporting | Cast stats + export, cast history, announce, ready-check report + auto-post, join digest, selftest, repeat offenders, Discord summary, death recap, post-wipe report | Complete (batches 1–4) | Announce/ready/digest/selftest steps; auto-post step (leader posts to PARTY); history record + resetcount-clear step; offenders fold-on-group-end step; stats export + Discord render steps; death-recap step (PLAYER_DEAD print + reprint); wipe step (controllable clock: single death = no report, 2-of-3 dead after 20 s = report) | — |
| Settings & QoL | Tabs UI, export/import, named profiles + share-one-profile, per-spec profiles, presets, auto profiles, scan throttle, settings search, setup wizard | Complete (batches 1–4) | Settings-fire-every-control step, export/import round-trip, profile + preset + auto-profile steps, throttle toggle + 25-player tick step, profile share/import round-trip, settings-search dim step, wizard step (preset pick applies + advances, theme cycles, Finish marks seen) | — |
| Settings data safety | Versioned SavedVariables, migrations, corrupt-data repair | Complete | Migration fixture: legacy v2 save → v12, corrupt save replaced, corrupt customSpells/autoProfile repaired; v9 save marks the setup wizard as seen (existing users are not nagged) | — |
| Localisation | deDE complete for every user-facing string | Complete | `tools/localecheck.py`: 81/81 strings; German setup runs the full trial run (246 steps) | Other locales: none planned |

## The 50-item program (SEAN approved 2026-10-25: add all 50)

- **Shipped in 1.6.0 (10):** #1 assignments, #2 buddy split, #4 blessing
  planner, #16 all-buffed pill, #24 cast queue tag, #25 consumables watch,
  #28 custom spells, #39 coverage uptime, #45 shipped presets, #47 auto
  profiles. **#23 (buff-next keybind) was a duplicate** of the long-shipped
  *Cast next buff* keybind and was replaced by #45 — recorded, not hidden.
- **Shipped in 1.7.0 (10):** #3 cover-me handoff, #5 auto-post ready-check
  report, #7 coverage roster line, #12 pin a player, #20 row tooltips
  (**completed, not duplicated** — rows already had tooltips; 1.7.0 added
  the remaining-times half), #26 weapon buff reminder (temporary weapon
  enchants), #34 instance-entry reminder, #35 group expiry warning,
  #41 cast history log, #49 scan throttle. 1.7.0 also fixed a 1.6.0 bug
  its new tests exposed: assignments/plans set by short name sank on the
  named player's own list (identity now goes through `X.SameUser`).
- **Shipped in 1.8.0 (20):** #6 plan strings, #9 name finder, #11 duration
  bars, #14 grow-up anchor, #17 hide in combat, #18 color themes,
  #21 raid markers, #22 range text, #27 group pets, #29 aura/aspect watch,
  #30 per-buff context, #31 world-buff watch, #32 resistance context
  (SHADOW_PROT defaults to instance context on Forever), #36 healer
  drinking, #40 repeat offenders, #42 stats export, #46 settings search,
  #48 share one profile — plus two in-batch replacements for items that
  proved to be duplicates: **#10 (missing-buff icons) already shipped**
  (rows have always shown the missing buffs' icons) → replaced by
  **#43 Discord summary**; **#15 (opacity slider) already shipped** (the
  Window tab's background-opacity slider) → replaced by **#37 focus
  watch**. Both replacements are marked † in the Forever changelog.
  1.8.0 is also the first **Forever-only** release (see DECISIONS).
- **Shipped in 1.9.0 (4):** #13 two-column layout, #38 death recap,
  #44 post-wipe report, #50 setup wizard. **The program is complete**:
  every item that can be built and verified from here has shipped.
- **Customization batch in 1.10.0 (10, SEAN-requested):** saved themes,
  row spacing + icon size, coverage-line part toggles, per-kind alert
  sounds, tooltip detail levels, row color marks, group-by-buff view,
  buff priority order, window strata + click-through, name formats.
  Each is a slash operation as well as a settings control. All ten are
  Unverified in game, like everything since 1.3.2.
- **Parked under investigation (3):** #8 pull-timer flash — no verified
  source for pull timers exists in the target clients' documented API;
  needs in-game research before it can be built honestly. #19 modifier
  clicks — Ctrl/Shift on a secure cast button needs an in-game
  prototype; a wrong guess breaks click-casting. #33 newly-unbuffed
  sound — overlaps the existing new-name alert; needs a sharper
  definition (re-entry case + distinct sound) first. These three stay
  parked until there is evidence, not guesses.
