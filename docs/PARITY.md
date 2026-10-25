# Parity / Capability Matrix — BuffRadar

Updated: 2026-10-25 · Overall readiness: the core product is complete and
shipped at 1.6.0; the approved 50-item enhancement program stands at 10 of 50
shipped, 10 planned for 1.7.0, 3 under investigation, 26 deferred to later
batches. Every "Complete" below names its test evidence. Nothing here is
scored from in-game behaviour — both editions are **Unverified in game**
since 1.3.2 (see the Gap column and `QUALITY.md`).

| Area | Target | State | Evidence (test / corpus) | Gap |
|---|---|---|---|---|
| Core list & casting | Missing-buff list for group + nearby players; click / keybind / macro casting; you first | Complete | Trial run: list building, click-cast paths (target/id/macro/rank), BuffRadarNextButton + macro sync, in all 6 setups | In-game click-cast on both clients Unverified |
| Retail buff set | All 13 classes, patch 12.1.5 set | Complete | Edition + per-class steps in the Retail setups | Unverified in a live retail client |
| Forever buff set | Classic set incl. blessings, ranks, group variants | Complete | Forever setups incl. rank-table and Kings-first steps | Unverified in a live Forever client since 1.2.2 |
| Coordination (1.5.0–1.6.0) | Cast sync, chat requests, assignments, buddy split, blessing plan, peer hello | Complete (batch 1) | Trial steps: sync handled-marks, request tags, leader-trust assignment sink/float, buddy hash split, blessing plan set/broadcast/receive — 6 setups | #3 cover-me handoff, #7 coverage roster line → 1.7.0. All multi-user behaviour Unverified in game (needs a second BuffRadar user) |
| List & window | Sorts (name/role/distance/need), filters, strip, chips, pill, idle fade, rescue | Complete | Trial steps per feature, incl. pill show/hide/peek and off-screen rescue via `/br resetpos` | #9 search, #12 pin, #13 two-column, #14 grow-up deferred; window load-rescue branch itself is not smoke-covered (harness limit) |
| Rows & interaction | Tags (expired/rezzed/asked/handled/queued/assigned/buddy), portraits, compact rows, text scale | Complete | Tag-priority steps incl. the 1.6.0 queue tag | #20 tooltips → 1.7.0; #10 icons, #11 duration bars, #21 markers, #22 range text deferred |
| Coverage expansion | Built-in buffs + consumables + custom spells + uptime | Complete (batch 1) | Consumable tally, custom add/remove/list, uptime scoring steps | #26 weapon reminder → 1.7.0 (scoped: shaman/rogue weapon enchants); #27 pets, #29 aura/form, #30 per-buff context, #31 world buffs, #32 resistance context deferred |
| Alerts | New-name alert, drop alert, post-combat flash | Complete | Alert + flash steps | #34 instance-entry and #35 group-expiry → 1.7.0; #33, #36, #37, #38 deferred |
| Stats & reporting | Cast stats, announce, ready-check report, join digest, selftest | Complete | Announce/ready/digest/selftest steps | #5 auto-post ready report and #41 cast history → 1.7.0; #40, #42, #43, #44 deferred |
| Settings & QoL | Tabs UI, export/import, named profiles, per-spec profiles, presets, auto profiles | Complete (batch 1) | Settings-fire-every-control step, export/import round-trip, profile + preset + auto-profile steps | #46 settings search, #48 share-one-profile, #50 setup wizard deferred; #49 scan throttle → 1.7.0 |
| Settings data safety | Versioned SavedVariables, migrations, corrupt-data repair | Complete | Migration fixture: legacy v2 save → v8, corrupt save replaced, corrupt customSpells/autoProfile repaired | — |
| Localisation | deDE complete for every user-facing string | Complete | `tools/localecheck.py`: 62/62 strings; German setup runs the full trial run (175 steps) | Other locales: none planned |

## The 50-item program (SEAN approved 2026-10-25: add all 50)

- **Shipped in 1.6.0 (10):** #1 assignments, #2 buddy split, #4 blessing
  planner, #16 all-buffed pill, #24 cast queue tag, #25 consumables watch,
  #28 custom spells, #39 coverage uptime, #45 shipped presets, #47 auto
  profiles. **#23 (buff-next keybind) was a duplicate** of the long-shipped
  *Cast next buff* keybind and was replaced by #45 — recorded, not hidden.
- **Planned for 1.7.0 (10):** #3 cover-me handoff, #5 auto-post ready-check
  report, #7 coverage roster line, #12 pin a player, #20 row tooltips,
  #26 weapon buff reminder (scoped), #34 instance-entry reminder, #35 group
  expiry warning, #41 cast history log, #49 scan throttle.
- **Under investigation (3):** #8 pull-timer flash — no verified source for
  pull timers exists in the target clients' documented API; needs in-game
  research before it can be built honestly. #19 modifier clicks — Ctrl/Shift
  on a secure cast button needs an in-game prototype; a wrong guess breaks
  click-casting. #33 newly-unbuffed sound — overlaps the existing new-name
  alert; needs a sharper definition (re-entry case + distinct sound) first.
- **Deferred to later batches (26):** #6, #9, #10, #11, #13, #14, #15, #17,
  #18, #21, #22, #27, #29, #30, #31, #32, #36, #37, #38, #40, #42, #43, #44,
  #46, #48, #50.
