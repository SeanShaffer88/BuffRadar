# Changelog

All notable changes to BuffRadar are listed here. Newest first.

## 1.10.0 — 2026-10-25 — Forever edition

A customization release: ten player-requested options — five
improvements to things already there, five new additions — all about
making the window look, sound and behave the way you want. Every one
is a `/br` command as well as a settings control where it has one.

Improvements:

- **Your own themes** (`/br theme save <name>`, `/br theme delete
  <name>`, Settings > Window): save the window colors you have set as
  a named theme — up to four — and switch between them like the
  built-in themes.
- **Row spacing and icon size** (`/br rowgap <0-8>`, `/br iconsize
  <0|10-24>`, Settings > Window): pad the rows out vertically, and
  make the missing-buff icons bigger — or leave the size automatic.
- **Coverage line, your pick** (`/br cover <part> on|off`, Settings >
  Window > More display options): each of the line's seven parts —
  progress, your buffs, uptime, group, expiry, world buffs, healer
  drinking — can be switched off on its own.
- **A sound per alert** (`/br soundfor`, Settings > Alerts): the
  new-name, buff-drop and buff-request alerts each get their own
  sound choice; any kind without one uses the main sound.
- **Tooltip detail levels** (`/br tooltip`, Settings > Window > More
  display options): minimal (the cast line only), standard, or full —
  full adds where the player is and who else could cast the buff.

Additions:

- **Row color marks** (`/br rowcolor`, Settings > Window > More
  display options): a thin color bar on the left edge of rows that
  are your assignments, tanks, about to expire, or your buddy's half
  of a split list — pick a color per kind, or turn each off.
- **Group-by-buff view** (`/br view buffs`, Settings > Window > More
  display options): one row per buff still needed, with the number
  of players who need it; click a row to cast that buff on an
  in-range player who needs it.
- **Your buff order** (`/br prio`, Settings > Buffs): rows offer
  your buffs in the order you choose — the first one is the click
  target and first icon — and "need" sorting prefers rows whose top
  buff sits highest in your order.
- **Window layer and click-through** (`/br strata`, `/br
  clickthrough`, Settings > Window / Behavior): put the window on a
  higher or lower layer, and — while it is locked — let clicks pass
  through it to the game world behind.
- **Name formats** (Settings > Window > More display options):
  class-colored names on or off, realm names shown or hidden, and a
  longest-name length after which names shorten with dots.

Also fixed: a settings layout overlap on the Window tab — the
two-column and duration-bars checkboxes, and the setup-wizard
button and the range-words checkbox, could sit on top of each other.

## 1.9.0 — 2026-10-25 — Forever edition

The final batch of the 50-item enhancement program: the last four
buildable items. With this release the program is complete — 44 of
50 shipped, 3 duplicates resolved along the way, and 3 items parked
under investigation (#8 pull-timer flash, #19 modifier clicks,
#33 newly-unbuffed sound; each needs in-game evidence or a sharper
definition — see `../../docs/PARITY.md`).

- **Two-column layout** (`/br twocol`, Settings > Window): with more
  than 8 people on the list, the rows split into two side-by-side
  columns and the window widens — each column keeps your chosen width
  — instead of growing one tall column.
- **Death recap** (`/br death`, Settings > Behavior): the moment you
  die, BuffRadar prints who in your group was missing which buffs —
  the rebuff list for after the rez. `/br death show` reprints the
  last recap. On by default.
- **Post-wipe report** (`/br wipe`, Settings > Behavior): when a
  fight of 8 seconds or more ends with at least 3 group members dead
  (2 in a small party), BuffRadar prints who still needs buffs; if
  you lead or assist, a one-line summary also goes to group chat.
  `/br wipe show` reprints the last report. Off by default.
- **Setup wizard** (`/br wizard`, Settings > Window): a three-page
  walkthrough for new users — how you play (applies the matching
  preset), the window theme, and your buff list. First-time users
  get a one-line hint about it at login; players upgrading from an
  older version are marked as already set up and never see the hint.

Settings storage moves to version 11; older saves upgrade themselves
on load, as always.

## 1.8.0 — 2026-10-25 — Forever edition

**BuffRadar is Forever-only from this release.** Retail support was
dropped by SEAN on 2026-10-25: releases from 1.8.0 ship only the
Forever zip. Retail 1.7.0 remains available as the last Retail
release, and the Retail docs in this repo stay frozen at 1.7.0. The
shared source still carries the Retail spell tables, untouched.

Twenty more items from the 50-item enhancement program. Two items on
the original list turned out to be already shipped and are marked † —
each was replaced in the same batch, not silently dropped.

- **Buff plan strings** (`/br plan export|import`): the whole group
  plan — assignments, the blessing plan and your auto-profile map —
  as one copyable string you can hand to another BuffRadar user.
  Importing applies it locally and shares it onward.
- **Name finder** (`/br find <text>`, `/br findbox`, Settings >
  Window): a search box on the window filters the list to matching
  names; reports and announcements are never filtered.
- **Duration bars** (`/br bars`, Settings > Window): a thin bar
  under each row shows the shortest time left on that player's
  buffs from your set — green, yellow under 15 minutes, red under 5.
- **Grow upward** (`/br growup`, Settings > Window): the list can
  grow up from a bottom anchor instead of down.
- **Hide in combat** (`/br combat`, Settings > Window): the window
  and the all-buffed pill hide while you're in combat and return
  when it ends.
- **Color themes** (`/br theme`, Settings > Window): Midnight,
  Crimson, Forest and Parchment window color schemes; picking a
  custom background color switches the theme to Custom.
- **Raid target markers** (`/br markers`, Settings > Window): a row
  shows the raid marker (skull, cross, …) currently on that player.
- **Range in words** (`/br range`, Settings > Window): rows that
  are only just out of range say *near* instead of out of range.
- **Group pets** (`/br pets`, Settings > Behavior): party and raid
  pets get their own rows when they're missing Fortitude, Mark of
  the Wild or Arcane Intellect. Pets never appear in reports,
  announcements or offender counts.
- **Aura / aspect watch** (`/br aura`, Settings > Behavior):
  hunters are reminded to keep an aspect up, paladins an aura.
- **Per-buff context** (`/br context KEY raid|instance|always`): a
  buff can matter only in raids, only in instances (dungeons and
  battlegrounds count), or always. Bare `/br context` lists them.
- **World-buff watch** (`/br worldbuff`, Settings > Behavior): the
  coverage line lists the world buffs on you with time left —
  Rallying Cry of the Dragonslayer, Warchief's Blessing,
  Songflower Serenade, Spirit of Zandalar and friends.
- **Resistance context**: on Forever, Shadow Protection now starts
  in *instance* context — it's a pre-pull buff, not an always-on
  need. Change it any time with `/br context SHADOW_PROT always`.
- **Healer drinking** (`/br drink`, Settings > Behavior): healers
  sitting down to drink are tagged *drinking*, and the coverage
  line counts them, so pulls can wait for mana.
- **Focus watch** † (`/br focus`, Settings > Window): your focus
  target's missing buffs show as one line above the coverage line.
  († replaces #15 "opacity slider" — the background-opacity slider
  already shipped in the Window tab long ago.)
- **Repeat offenders** (`/br offenders`): when a group session
  ends, everyone seen unbuffed during it gains a count; the command
  lists the worst repeat offenders across sessions.
- **Stats export** (`/br stats export`): the cast statistics as
  copyable text.
- **Discord summary** † (`/br discord`): the group's buff state as
  a small markdown block, ready to paste into Discord.
  († replaces #10 "missing-buff icons" — rows have always shown
  icons of exactly what each player is missing.)
- **Settings search** (Settings window, bottom left): type to dim
  every setting that doesn't match, with a match count.
- **Share one profile** (`/br profile share <name>`,
  `/br profile import`, and a Share button on the Data tab): send a
  single named profile to another player as one text; importing
  stores it under its name, unapplied.

Settings format is now dbVersion 10; older saves migrate
automatically, as before. German translation covers all 78 strings;
`/br selftest` also reports the 1.8.0 state (grow up, combat hide,
theme, find, bars, markers, focus, pets, aura, world, drink,
offender count).

## 1.7.0 — 2026-10-25 — Forever edition

The same ten enhancements as retail 1.7.0, from the shared source.
(One item on the list, row tooltips, was half-built already — rows
had tooltips without remaining times — so this release completes
them; see the retail changelog. The short-name fix below matters
doubly here, where the blessing planner rides on the same names.)

- **Cover-me handoff.** When a BuffRadar user in your group dies or
  goes AFK, their buff duties pass to the rest of you automatically:
  their buddy-split share is redistributed, and any buff assigned to
  them counts as yours until they're back. Travels over the sync
  channel (`/br sync`); no setting.
- **Ready-check auto-post** (`/br readypost`, Settings > Behavior):
  as leader or assistant, the ready-check summary is also posted to
  group chat.
- **Coverage roster line.** The coverage line now shows which
  BuffRadar users are on duty, how many assignments each holds, and
  who is away (dead/AFK) — e.g. `Radar: Me (1), Aaron, Zed (away)`.
- **Pin a player** (`/br pin <name>`, `/br pin none`): one player's
  row stays at the top of the list, tagged *pinned*, whatever the
  sort says.
- **Row tooltips, completed.** Hovering a row now also lists the
  buffs that player HAS from your set, with the time left on each,
  soonest first.
- **Weapon enchant watch** (`/br weapon`, Settings > Behavior):
  your own row gets a *weapon enchant missing* tag when an equipped
  weapon has no temporary enchant — imbue, poison, oil or stone. If
  your row isn't on the list, the coverage line says it instead.
- **Instance-entry reminder** (`/br enterflash`, on by default):
  one chat line when you step into a dungeon, raid or battleground
  with buffs still missing — how many people, and how many casts.
- **Group expiry warning.** The coverage line warns when a group
  buff is inside its last five minutes on at least half its
  holders: `Blessings <5m on 18/30`.
- **Cast history** (`/br history`): the last 50 buffs you cast
  through BuffRadar — spell, target, time — in a copyable window.
  Cleared by `/br resetcount`.
- **Scan throttle** (`/br throttle`, Settings > Behavior): in
  groups over 20, the steady rescan runs half as often;
  event-driven refreshes stay instant.

**Fixed (from 1.6.0):** an assignment or blessing plan set with a
player's short name now floats correctly on that player's own list
— it sank as "someone else's" before. Name matching now treats a
bare name and the same name with a realm as the same person, unless
the realms actually differ.

Settings format is now dbVersion 9; older saves migrate
automatically, as before. German translation covers all 68 strings;
`/br selftest` also reports the 1.7.0 state (ready-post, pin,
weapon watch, entry reminder, throttle, cover count, history).

## 1.6.0 — 2026-10-25 — Forever edition

The same ten enhancements as retail 1.6.0, from the shared source —
plus the blessing planner, which belongs to this edition. (One item
on the original list, a buff-next keybind, duplicated the existing
*Cast next buff* keybind and was replaced by the shipped presets;
see the retail changelog.)

- **Blessing planner** (`/br bless <CLASS> <BLESSING> [name]`): the
  leader, an assistant or any paladin can plan which blessing each
  class gets — e.g. Kings for warriors, Wisdom for priests. Your own
  casts follow the plan automatically; other paladins running
  BuffRadar see the planned blessing on their rows for that class,
  and a named paladin can be given a class personally. The plan
  travels over the cast-sync channel (`/br sync`) and lasts for the
  group session.
- **Buff assignments** (`/br assign <BUFF> <name|none>`): the leader
  or an assistant assigns a buff to one player; their rows for it
  float tagged *your assignment*, everyone else's sink tagged
  *assigned elsewhere*.
- **Buddy split** (`/br buddy`): two or more BuffRadar users split
  the list between them by a stable hash; your share floats, the
  rest sink tagged *buddy's watch*.
- **All-buffed pill** (`/br pill`): the window collapses to a small
  pill showing the coverage count while everyone is fully buffed;
  click it to peek for five seconds.
- **Cast queue tag:** the next row is tagged *up next* for a few
  seconds after one of your casts lands.
- **Consumables watch** (`/br consumables`): the coverage line also
  counts flask and food buffs across the group. (No Augment Rune
  count on this edition — the item doesn't exist here.)
- **Custom watched spells** (`/br custom add|remove|list <spell ID>`):
  watch any buff spell you know. Per character; not carried by
  settings export or named profiles.
- **Coverage uptime** (`/br uptime`): the share of grouped scans this
  session that found nobody missing anything; resets when the group
  ends.
- **Shipped presets** (`/br preset raid|dungeon|solo`) and
  **auto-switch profiles** (`/br autoprofile <context> <profile>`),
  as on retail.
- Internals: `/br selftest` reports the 1.6.0 state; SavedVariables
  dbVersion is now 8 (old saves migrate automatically); the German
  translation covers all 62 strings. The trial run covers all of the
  above — 174 steps (175 on the German setup) in each of six
  fake-client setups.
- **Not yet verified in game.** 1.6.0 has passed the full offline
  check suite only; the in-game check is still owed.

## 1.5.0 — 2026-10-25 — Forever edition

The same fourteen enhancements as retail 1.5.0, from the shared
source (four items on the original list duplicated 1.4.0 features and
were replaced — see the retail changelog):

- **Cast sync between BuffRadar users** (`/br sync`): a cast by any
  BuffRadar user in your group marks that player *being buffed* on
  everyone's list for a few seconds, so nobody double-casts.
- **Chat buff requests** (`/br requests`): a listed player who
  whispers or says they need a buff gets an *asked for a buff* marker.
- **Join digest** (`/br digest`): one line when you join a group —
  how many people are missing buffs, and how many casts that is.
- **Buff toggle strip** (`/br strip`): icons for your buffs under the
  title; click to toggle one without opening settings. The role
  filter chips beside them need assigned group roles, which this
  client doesn't expose, so the chips have no effect here.
- **Need sort** (`/br sort need`): most missing buffs first.
- **Idle fade** (`/br fade <0-90>`): the window fades while your
  mouse is elsewhere.
- **Named settings profiles** (`/br profile save|load|delete|list`).
- **Drop alert** (`/br watch`): a message, sound and border flash
  when your single-target buff drops off its holder.
- **Coverage cooldown note:** a buff on cooldown is flagged on the
  coverage line, e.g. *Fortitude 15/15 (~3m cd)*, since it can't be
  counted as missing while it cools down.
- **Flight-path pause** (optional, `/br taxi`) and an **off-screen
  window rescue** plus `/br resetpos`.
- Internals: SavedVariables dbVersion is now 7 (old saves migrate
  automatically); the German translation covers all 53 strings; the
  trial run covers all of the above (164 steps per fake-client
  setup).
- **Not yet verified in game.** 1.5.0 has passed the full offline
  check suite only; 1.2.2 remains the last version confirmed live on
  this client (beta build 1.60.1.70450).

## 1.4.0 — 2026-10-25 — Forever edition

The same twenty enhancements as retail 1.4.0, from the shared
source:

- **Rezzed players jump the queue.** Someone who just came back from the
  dead has lost every buff; their row moves to the top (below yours) with
  a *recently rezzed* marker for a minute.
- **Coverage line.** While grouped, a line under the list shows how many
  members are fully buffed plus per-buff coverage ("12/15 fully buffed ·
  Fortitude 14/15 ...") — it doubles as progress while you work a fresh group.
- **Expired-buff marker and time left.** A buff that disappears outright
  (expired, dispelled, death) flags its row *a buff just expired* for a
  few seconds; a buff inside its rebuff window shows *~4m left* /
  *~20s left* on the row.
- **Session-only ignore.** Shift-right-click a row (or `/br signore
  <name>`) to ignore someone until you log out; nothing is saved.
  `/br unsignore <name>` undoes it.
- **`/br announce`** posts the group's missing buffs to party/raid chat,
  and a ready check now prints a local summary of who is missing what.
- **Low-mana pause** (`/br mana <0-100>`): above 0, listing pauses with
  a *Low mana* status while your mana is under that percentage.
- **Distance sort** (`/br sort distance`, also the Settings sort
  button): nearest first — in cast range, then in group range, then
  everyone else.
- **Per-spec profiles** (uses the client's specialization API where it has one; clients without it are unaffected): buff toggles and rebuff timings are
  remembered per specialization and swap automatically on a spec change.
- **Settings export / import** (`/br export`, `/br import`): copy nearly
  all settings between characters as one string.
- **Compact rows** (Settings > Window, or `/br compact`): half-height
  rows without portraits. List text size is separate from window scale
  (`/br text <0.8-1.5>`).
- **Per-character window position** (Settings > Window, or
  `/br charpoint`).
- **Post-combat flash:** when combat ends with buffs still missing, the
  window border pulses once.
- **`/br selftest`** prints one paste-able block for bug reports.
- **Settings-window translation:** tab titles and the main checkboxes
  now use the translation table; German covers all 44 strings.
- Internals: scattered state consolidated into one table (the file sits
  at 184 of Lua 5.1's 200 top-level locals, peak function 45 of 60
  upvalues), SavedVariables migration from every old layout is now
  covered by the trial run, and the trial run checks all of the above
  (128–129 steps in each of six fake-client setups). Settings dbVersion
  is now 6; old saves migrate automatically.
- **Not yet verified in game.** 1.4.0 has passed the full offline check
  suite only; the in-game check is still owed.

## 1.3.2 — 2026-10-23 — Forever edition

Built from the same source as retail 1.3.2: BuffRadar now picks the
Forever buff set (unchanged from 1.2.4) when it loads on the Forever
client. Everything below also applies to the retail edition.

- **Resizable window** (drag the bottom-right corner) and **scale
  dropdowns** for the list window and the settings window.
- **Settings window in the standard game style,** with tabs along the
  bottom; a client without those parts keeps the previous look.
- **Rebuff timing** in the settings window (Buffs tab), **hover help** on
  every setting, and checkbox labels that can be clicked.
- **Ignore list:** realm-aware, any capitalization, remove names one by
  one on the Ignore & Stats tab. Names ignored before keep working.
- **Buffing group members no longer changes your target.**
- **Addon menu entry:** left-click shows or hides the window, right-click
  opens settings. Where the client lists addon options, BuffRadar appears
  under Esc > Options > AddOns.
- **Fixes:** right-clicking a row no longer casts; right-clicking the
  minimap button opens settings as its tooltip says.
- **Out-of-range rows are marked,** with *out of range* under the greyed
  name, so the state doesn't rely on color alone. Fixed alongside: a
  player who came back into range kept the grey name.
- **German translation** of the main window, its tooltips and the minimap
  tooltips (`Locales\deDE.lua`), which is also the template for other
  languages.
- **Less work in busy places,** sturdier handling of protected game values,
  and more of the window's text can be translated.

## 1.2.4 — 2026-10-22

- **Fix: the window no longer moves as names are added and removed.** The
  list's height changes with every name, but the window was anchored by
  its left edge (or by whatever point a drag left it on), so growing and
  shrinking happened around that anchor and the whole window — top edge
  included — jumped up and down. The window is now anchored by its
  top-left corner only: the top edge stays exactly where you put it and
  the list grows and shrinks downward. Positions saved by older versions
  are converted automatically on first load; a position saved mid-drag
  by an older version may shift slightly that one time, because the old
  save didn't record the window's height.

## 1.2.3 — 2026-10-22

- **Fix (paladin): Blessing of Kings is now cast when known.** Kings sat
  second in each class's blessing priority, behind Might or Wisdom — but
  Kings is learned after both, so any paladin who knew Kings already knew
  the first-choice blessing too and Kings was never selected. Kings now
  leads every class list; Might (warriors, rogues) and Wisdom (everyone
  else) remain the fallbacks for paladins who don't know Kings yet.
- **Fix (nearby players): BuffRadar no longer stays silent when it can't
  see anyone.** Non-group players can only be discovered through friendly
  nameplates, your target, or your mouseover — there is no API that lists
  nearby players. With friendly nameplates off, the window previously read
  "Everyone nearby is buffed." even though nobody outside the group could
  be seen at all. Now: the window says "Friendly nameplates are off.",
  BuffRadar warns once in chat at login, mouseover is checked as an extra
  discovery source, and `/br debug` reports the nameplate setting plus
  how many nameplate units (and players) the game is currently showing,
  so "it only works when I target people" can be told apart from a
  scanning problem at a glance.

## 1.2.2 — 2026-10-20

- **Fix:** clicking a name in the window did not cast. The right-click
  ignore handler (added in 1.2.0) was installed with `SetScript("OnClick")`,
  which *replaces* the SecureActionButtonTemplate's own OnClick — the
  handler that actually performs the cast — so every click ran only the
  ignore logic and no spell was ever cast. The handler is now installed
  with `HookScript`, so the secure cast fires first. The ignore toggle
  also now triggers on exactly one click phase (with the default
  press+release registration it previously would have toggled twice).

## 1.2.1 — 2026-10-20

- **Fix:** the window failed to build with "attempt to call a nil value"
  (BuffRadar.lua:1240) because the minimap-button builder was declared
  after the UI builder that calls it, and Lua locals only exist from their
  declaration point. It is now forward-declared like the other cross-section
  helpers. Reported from a live beta session — thank you.

## 1.2.0 — 2026-10-20

Feature release, and the settings window is redesigned into tabs
(Window / Alerts / Buffs / Behavior / Ignore & Stats) to hold it all.
Includes everything from the 1.1.2 compatibility pass below.

- **Group-cast offers:** in a party or raid, when enough group members need
  the same buff, the first matching row offers the group version instead
  (Arcane Brilliance, Prayer of Fortitude, Prayer of Spirit, Prayer of
  Shadow Protection, Gift of the Wild). On/off and threshold (default 3) in
  Settings > Behavior, or `/br groupcast [on|off|<n>]`.
- **Out-of-range players** can stay listed, greyed and unclickable, instead
  of disappearing (Settings > Behavior, off by default). They sort last and
  never trigger the alert sound.
- **Ignore list:** right-click any row to ignore that player (for example
  someone AFK); right-click again to undo. Manage with `/br ignore`,
  `/br unignore`, `/br ignorelist`, or the Ignore & Stats settings tab.
- **Role ordering:** optional sort putting you, then raid tanks
  (MAINTANK/MAINASSIST flags), then group leaders first
  (`/br sort name|role`, or Settings > Behavior).
- **Per-buff rebuff timing:** `/br rebuff KEY <seconds>` (for example
  `/br rebuff THORNS 60`) overrides the global rebuff threshold per buff.
- **Alert choices:** the new-name alert can be the droplet, a system raid
  warning, or silent (`/br alertsound`), and can stay quiet inside
  dungeons, raids and battlegrounds (Settings > Alerts).
- **Minimap button** (draggable, left-click toggles the window, right-click
  opens settings) plus an addon-compartment entry. `/br minimap` toggles it.
- **Battleground pause:** optional pause in battlegrounds and arenas
  (`/br bg`), like the major-city pause.
- **Cast statistics:** all-time casts per spell, shown with `/br stats` and
  on the Ignore & Stats settings tab.
- **Localization scaffolding:** window status lines go through a locale
  table (`BuffRadarLocales`), so translation files can override them.
- Settings that used to be slash-only (window scale, cast counter) now have
  controls in the new tabbed settings window.

## 1.1.2 — 2026-10-20

Compatibility update for the final beta builds. No new options.

- **Verified against Forever beta build 1.60.1.70450** (October 18; interface
  16001, unchanged from 1.1.1's 70374 target). All APIs BuffRadar uses were
  re-audited against the current build.
- **Build 70425 spell removals need no action:** Blessing of Salvation and
  Greater Blessing of Salvation were removed from the game, and BuffRadar
  only ever offers spells found in your spellbook, so they drop out on their
  own. (They were never in the per-class blessing priority lists.)
- `/br debug` now prints the full client version and build number, so bug
  reports name the exact build.
- Portrait rendering is guarded like the rest of the addon: if a future
  build renames or restricts the portrait call, rows still render.

## 1.1.1 — 2026-10-15

Performance and robustness pass. No new options.

- **Much lighter in raids:** refreshes no longer create garbage (about 317 KB per refresh
  before, near zero now with 25 raid members and 40 nameplates in view), and CPU time per
  refresh is lower.
- **No redundant redraws:** portraits, icons, text and click bindings are only updated
  when something actually changed.
- **Bursts of events are batched:** a flood of buff changes in a raid now triggers about
  ten refreshes a second instead of one per event. Spellbook changes are batched too.
- **Faster buff checks** on clients that support looking up a buff by name.
- **Non-English clients:** if spell names aren't loaded yet at login, BuffRadar requests
  them and switches to the correct localized names when they arrive.
- **Damaged settings are repaired** automatically instead of causing errors.
- A window drag still in progress when combat starts is finished cleanly.
- `/br plates` no longer tries to change nameplate settings during combat.

## 1.1.0 — 2026-10-14

- **Party/raid only:** new option to show the window only while you're in a party or
  raid (`/br group`, or Settings > When to show). The *Cast next buff* key keeps
  working while the window is hidden.
- **Show / hide keybind:** bind it under BuffRadar in Key Bindings. Pressed during
  combat, the change applies when combat ends.
- **Mute keybind:** turns the water droplet sound off and on.
- **No scanning in major cities:** BuffRadar pauses in capital cities and shows
  "Paused in a major city." On by default; turn it off with `/br cities` or in Settings.
- Settings window lists all three keybinds. `/br debug` now shows your zone, map ID
  and whether it counts as a major city.

## 1.0.1 — 2026-10-14

- Updated for Forever beta build 1.60.1.70374 (interface 16001, unchanged).
- Buff checks no longer stop working if the game hides a buff's details from addons;
  that one buff is skipped and the rest of the list still works.
- The *Cast next buff* keybind and macro no longer depend on secure snippets. If the game
  rejects them, the window still loads and the key still clears after each press and
  when combat starts. `/br debug` shows which method is in use.

## 1.0.0 — 2026-10-13

First release.

- **Buff list:** a small window listing every nearby player who is missing one of your
  buffs, with portrait, class-colored name and icons of the buffs they still need.
- **You first:** your own character is always checked first and sits at the top of the
  list whenever you're missing a buff.
- **Class-aware:** each buff only goes to classes it helps (Arcane Intellect to mana
  users, Thorns to melee, Fear Ward to warriors, one fitting blessing per class).
- **Buffs covered:** Druid, Priest, Mage, Paladin, Warlock and Shaman buffs, including
  self-buffs such as armors, Inner Fire and Shaman shields. Situational buffs are off
  by default and can be switched on.
- **Smart checks:** group versions count as already buffed, nearly expired buffs are
  offered again, spells on cooldown are skipped, and your highest rank is always cast.
- **Click, keybind or macro:** click a name, bind *Cast next buff*, or use `/br macro`
  for a ready-made macro. The keybind and macro never fire in combat.
- **Water droplet alert** when someone new appears (optional).
- **Cast counter** for this session and all-time.
- **Settings window** (`/br config`): background color, opacity, title, border, alerts,
  counter, keybind, macro and per-buff on/off switches.
