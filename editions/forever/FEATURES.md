# BuffRadar — Features (Forever edition)

The full feature list for BuffRadar 1.9.0 (Forever edition) for
WoW: Forever (Interface 16001). For the short version see
`README.md`; for store-listing copy see `DESCRIPTION.md`.

Prepared 2026-10-24 from the shipped 1.3.2 Forever README and
CHANGELOG; updated 2026-10-25 for 1.9.0. Since 1.3.2 both editions are built from one source —
the addon picks the Forever buff set when it loads on the Forever
client — and the Forever buff set itself is unchanged from 1.2.4.
**From 1.8.0 BuffRadar is Forever-only**: Retail support was dropped
2026-10-25, and 1.7.0 is the last Retail release.

## New in 1.9.0

- **Two-column layout** (`/br twocol`, Settings > Window): past 8
  rows, the list splits into two side-by-side columns and the window
  widens, instead of growing one tall column.
- **Death recap** (`/br death`, `/br death show`, Settings >
  Behavior): when you die, BuffRadar prints who in your group was
  missing which buffs at that moment — the rebuff list for after the
  rez. On by default; the last recap can be reprinted any time.
- **Post-wipe report** (`/br wipe`, `/br wipe show`, Settings >
  Behavior): when a fight of 8 seconds or more ends with at least 3
  group members dead (2 in a small party), BuffRadar prints who still
  needs buffs, and — if you lead or assist — posts a one-line summary
  to group chat. Off by default.
- **Setup wizard** (`/br wizard`, Settings > Window): a three-page
  first-run walkthrough — how you play (applies a preset), the window
  theme, and your buff list. New users get a one-line hint pointing
  at it on their first login; existing users are never nagged.

These four finish the 50-item enhancement program: 44 items shipped,
3 duplicates resolved in-batch, and 3 parked under investigation
(#8 pull-timer flash, #19 modifier clicks, #33 newly-unbuffed sound —
each needs in-game evidence or a sharper definition, recorded in
`../../docs/PARITY.md`).

## New in 1.8.0

- **Buff plan strings** (`/br plan export|import`): assignments,
  the blessing plan and the auto-profile map as one copyable
  string; importing applies it and shares it onward.
- **Name finder** (`/br find`, `/br findbox`): a search box on the
  window filters the list by name; reports stay unfiltered.
- **Duration bars** (`/br bars`): a thin bar under each row shows
  the shortest time left on that player's buffs from your set
  (green / yellow under 15m / red under 5m).
- **Grow upward** (`/br growup`): the list can grow up from a
  bottom anchor instead of down.
- **Hide in combat** (`/br combat`): window and pill hide during
  combat and return when it ends.
- **Color themes** (`/br theme`): Midnight, Crimson, Forest and
  Parchment window schemes; a custom color makes the theme Custom.
- **Raid target markers** (`/br markers`): rows show the raid
  marker currently on that player.
- **Range in words** (`/br range`): rows just out of range say
  *near* instead of out of range.
- **Group pets** (`/br pets`): party/raid pets get rows when
  missing Fortitude, Mark of the Wild or Arcane Intellect; pets
  stay out of every report and announcement.
- **Aura / aspect watch** (`/br aura`): hunters keep an aspect up,
  paladins an aura — your own row reminds you.
- **Per-buff context** (`/br context KEY raid|instance|always`):
  a buff can matter only in raids or only in instances. Shadow
  Protection starts in *instance* context on this edition.
- **World-buff watch** (`/br worldbuff`): the coverage line lists
  your world buffs with time left (Dragonslayer, Warchief's,
  Songflower, Zandalar, Darkmoon fortunes, Dire Maul tributes,
  Silithid traces).
- **Healer drinking** (`/br drink`): drinking healers are tagged
  *drinking* and counted on the coverage line.
- **Focus watch** (`/br focus`): your focus target's missing
  buffs as one line above the coverage line.
- **Repeat offenders** (`/br offenders`): per-session counts of
  who was seen unbuffed, kept across sessions (worst 50).
- **Stats export** (`/br stats export`) and **Discord summary**
  (`/br discord`): cast statistics, and the group's buff state as
  a markdown block, both as copyable text.
- **Settings search**: a find box in the settings window dims
  every setting that doesn't match the text.
- **Share one profile** (`/br profile share|import`, Data tab
  Share button): one named profile as a copyable text.
- Two listed items († in the changelog) were already shipped —
  missing-buff icons and the opacity slider — and were replaced
  in-batch by the Discord summary and the focus watch.
- German translation covers all 78 strings; `/br selftest` also
  reports the 1.8.0 state. Settings format is now dbVersion 10.

## New in 1.7.0

- **Cover-me handoff:** a BuffRadar user who dies or goes AFK hands
  their duties to the other users automatically — their buddy-split
  share is redistributed and buffs assigned to them count as yours
  until they're back. Rides the sync channel; no setting.
- **Ready-check auto-post** (`/br readypost`): as leader or
  assistant, the ready-check summary is also posted to group chat.
- **Coverage roster line:** the coverage line lists the BuffRadar
  users on duty, the assignments each holds, and who is away.
- **Pin a player** (`/br pin <name|none>`): one row glued to the
  top of the list, tagged *pinned*, under every sort.
- **Row tooltips, completed:** hover a row to see the buffs the
  player has from your set, with the time left on each.
- **Weapon enchant watch** (`/br weapon`): your row (or the
  coverage line) flags an equipped weapon with no temporary
  enchant — imbue, poison, oil or stone.
- **Instance-entry reminder** (`/br enterflash`, on by default):
  one line on entering a dungeon, raid or battleground unbuffed.
- **Group expiry warning:** the coverage line names a group buff
  inside its last five minutes on at least half its holders.
- **Cast history** (`/br history`): the last 50 casts through
  BuffRadar — spell, target, time — in a copyable window.
- **Scan throttle** (`/br throttle`): groups over 20 rescan at
  half rate; event-driven refreshes stay instant.
- **Fixed:** assignments and blessing plans set by short name now
  float on the named player's own list (1.6.0 sank them) — this
  matters doubly here, where the planner rides on those names.
- German translation covers all 68 strings; `/br selftest` also
  reports the 1.7.0 state (ready-post, pin, weapon watch, entry
  reminder, throttle, cover count, history).

## New in 1.6.0

- **Blessing planner** (`/br bless <CLASS> <BLESSING> [name]`): the
  leader, an assistant or any paladin plans which blessing each
  class receives. Your casts follow the plan; other paladins running
  BuffRadar see the planned blessing on their rows for that class,
  and one named paladin can own a class. Session-only; travels over
  the cast-sync channel (`/br sync`).
- **Buff assignments** (`/br assign <BUFF> <name|none>`): the leader
  or an assistant assigns a buff to one player; their rows float
  (*your assignment*), everyone else's sink (*assigned elsewhere*).
- **Buddy split** (`/br buddy`): with sync on, BuffRadar users split
  the list by a stable hash — your share floats, the rest sink
  tagged *buddy's watch*.
- **All-buffed pill** (`/br pill`): the window collapses to a small
  pill with the coverage count while everyone is fully buffed;
  click to peek for five seconds.
- **Cast queue tag:** the next row is tagged *up next* briefly after
  one of your casts lands.
- **Consumables watch** (`/br consumables`): flask and food counts
  on the coverage line (no Augment Rune on this client).
- **Custom watched spells** (`/br custom add|remove|list <spell ID>`):
  watch any buff spell you know. Per character; not carried by
  settings export or named profiles.
- **Coverage uptime** (`/br uptime`): the share of grouped scans this
  session that found nobody missing anything; resets when the group
  ends.
- **Shipped presets** (`/br preset raid|dungeon|solo`) and
  **auto-switch profiles** (`/br autoprofile <context> <profile>`),
  as on retail.
- German translation covers all 62 strings; `/br selftest` also
  reports the 1.6.0 state.

## New in 1.5.0

- **Cast sync between BuffRadar users** (`/br sync`): casts by any
  BuffRadar user in the group mark the target *being buffed* on every
  user's list for a few seconds and sink their row.
- **Chat buff requests** (`/br requests`): a whisper or nearby say
  asking for a buff tags the asker's row *asked for a buff*.
- **Join digest** (`/br digest`): one summary line when joining a
  group.
- **Buff toggle strip** (`/br strip`): one icon per castable buff
  under the title; click to toggle. The **role filter chips** beside
  it need assigned group roles, which this client doesn't expose, so
  they have no effect here.
- **Need sort** (`/br sort need`): most missing buffs first.
- **Idle fade** (`/br fade <0-90>`): the window fades while the
  mouse is elsewhere.
- **Named settings profiles** (`/br profile save|load|delete|list`,
  or the Ignore & Stats tab): complete settings sets under a name.
- **Drop alert** (`/br watch`): message, sound and border flash when
  your single-target buff drops off its holder.
- **Coverage cooldown note:** a buff on a real cooldown is flagged
  on the coverage line, e.g. *Fortitude 15/15 (~3m cd)*.
- **Flight-path pause** (`/br taxi`, optional) and an **off-screen
  window rescue** with `/br resetpos`.
- German translation now covers all 53 strings; `/br selftest` also
  reports the 1.5.0 state (sync, requests, filter, profiles, fade).
  (Phase-aware scanning is in the shared source too, but this client
  has no phasing, so it changes nothing here.)

## New in 1.4.0

- **Rezzed players jump the queue** (below you) with a *recently rezzed*
  marker — they have lost every buff.
- **Coverage line** while grouped: members fully buffed plus per-buff
  coverage; doubles as buffing progress.
- **Row markers:** *a buff just expired* for buffs that vanish outright,
  *~4m left* / *~20s left* inside the rebuff window.
- **Session-only ignore** (Shift-right-click or `/br signore`), **`/br
  announce`** to party/raid chat, and a local ready-check summary.
- **Low-mana pause** (`/br mana <0-100>`), **distance sort**, **per-spec
  profiles** for toggles and rebuff timings (where the client exposes specializations).
- **Settings export/import** as one string, **compact rows**, separate
  **list text size**, **per-character window position**, a **post-combat
  border flash**, and **`/br selftest`** for bug reports.
- Settings-window tabs and main checkboxes are translatable now;
  German covers all 44 strings.

## The list

- **Live list of who needs what.** Every nearby player missing one
  of your buffs is listed with portrait, class-colored name and the
  icons of what they still need. Players drop off once every buff
  you can cast that suits their class has been applied.
- **You first.** Your own character is always checked first and sits
  at the top of the list whenever you're missing something
  (`/br self` toggles this).
- **The list grows downward.** Since 1.2.4 the window is anchored by
  its top-left corner only, so its top edge stays exactly where you
  put it as names come and go — only the bottom edge moves.
  Positions saved by older versions are converted automatically on
  first load.

## Buffing

- **Click-to-buff.** Click a name to buff that player; hovering a
  name shows exactly what will be cast and what they still need.
  Since 1.3.2, buffing a group member no longer changes your
  target; for anyone else, BuffRadar targets them by name, casts,
  then switches back to your previous target.
- **One-key buffing.** Bind *Cast next buff*, or use the BuffRadar
  macro (`/br macro`, or `/click BuffRadarNextButton LeftButton 1`
  in any macro), to work through the list without clicking.
- **Highest rank.** Buffs are cast by name, so your highest known
  rank is always used.
- **Class-aware.** Arcane Intellect only goes to mana users, Thorns
  to melee classes, Fear Ward to warriors, and so on. Paladins give
  each class one fitting blessing: **Blessing of Kings leads every
  class list since 1.2.3** (it is learned after Might/Wisdom, so it
  was previously unreachable); Might (warriors, rogues) and Wisdom
  (everyone else) are the fallbacks.
- **Group-cast offers.** When enough of your party or raid needs the
  same buff, BuffRadar offers the group version (Prayer of
  Fortitude, Gift of the Wild, Greater Blessings…) instead — one
  cast for everyone (`/br groupcast`).
- **Smart checks.** Group versions (Arcane Brilliance, Prayer of
  Fortitude, Gift of the Wild, Greater Blessings) count as "already
  buffed". Buffs about to expire are offered again (default: under
  30 seconds left, per-buff override via `/br rebuff` or the Buffs
  settings tab). Spells on cooldown are skipped.

## Supported buffs (Forever)

| Class   | On by default | Off by default (situational) |
|---------|---------------|------------------------------|
| Druid   | Mark of the Wild (everyone), Thorns (melee) | — |
| Priest  | Power Word: Fortitude (everyone), Divine Spirit (mana users), Fear Ward (warriors), Inner Fire (you) | Shadow Protection |
| Mage    | Arcane Intellect (mana users), Molten / Mage / Ice / Frost Armor (you) | Dampen Magic, Amplify Magic |
| Paladin | One blessing per class: Kings for everyone if you know it; otherwise Might for warriors and rogues, Wisdom for everyone else | — |
| Warlock | Fel / Demon Armor or Demon Skin (you) | Unending Breath, Detect Invisibility |
| Shaman  | Water or Lightning Shield (you) | Earth Shield, Water Breathing |

Warriors, rogues and hunters have no buffs for others, so the window
stays hidden on those characters.

## Seeing nearby players

- Discovery is group units + target + mouseover + friendly
  nameplates (`nameplate1..40`) only — the game gives addons no list
  of nearby players.
- **Friendly nameplates are required** for strangers. Since 1.2.3,
  with nameplates off the window says "Friendly nameplates are off"
  instead of claiming everyone is buffed, BuffRadar warns once in
  chat at login, and `/br debug` reports the nameplate setting plus
  how many nameplate units/players the game is currently showing.
  `/br plates` turns friendly nameplates on.

## Alerts, ordering and staying out of the way

- **Water droplet alert** when someone new appears (optional, with a
  mute keybind; a system sound or silence can be chosen instead, and
  alerts can stay quiet in instances).
- **Out-of-range players** can stay listed, greyed **and marked
  *out of range* in text** (since 1.3.2 — the state doesn't rely on
  color alone), so you see who's coming into range. **Right-click a
  row** to ignore a player who doesn't want buffs
  (`/br ignore` / `/br unignore` / `/br ignorelist`); since 1.3.2
  the ignore list is realm-aware, ignores capitalization, and names
  can be removed one by one on the Ignore & Stats tab.
- **Role ordering** option: you, tanks (by the group role they
  picked) and leaders first (`/br sort name|role`).
- Pauses in major cities (and, optionally, in battlegrounds), can
  show only while you're in a party or raid, autohide when nobody
  needs anything, and has a show/hide keybind, a minimap button and
  an addon-compartment entry (left-click shows or hides the window,
  right-click opens settings).
- PvP-flagged players are skipped when you aren't flagged
  (`/br pvp`).

## Settings and statistics

- Tabbed settings window (Window / Alerts / Buffs / Behavior /
  Ignore & Stats) — since 1.3.2 in the standard game style with
  tabs along the bottom where the client provides it: background
  color, opacity, title, border, width and scale; per-buff on/off
  (`/br buffs`, `/br toggle KEY`); per-buff rebuff timing on the
  Buffs tab; hover help on every setting; clickable checkbox
  labels. The window resizes by dragging its bottom-right corner,
  and scale dropdowns (50%–200%) cover the list window and the
  settings window. Settings open from the gear icon, by
  right-clicking the minimap button or the addon menu entry, via
  Esc > Options > AddOns (on clients that list addon options), or
  with `/br config`.
- **Languages:** the main window, its tooltips and the minimap
  tooltips are in German on German clients (`Locales\deDE.lua`,
  which is also the template for other languages); the settings
  window is English for now.
- **Cast counter** for this session and all-time, plus per-spell cast
  statistics (`/br count`, `/br resetcount`, `/br stats`). The
  session count resets on login or `/reload`; the all-time count is
  shared by all your characters.
- Three keybinds: **Cast next buff**, **Show / hide window** and
  **Mute / unmute sound** (`/br key`).

## Not in this version

- No buffing during combat: the game doesn't let addons change
  click-to-cast buttons in combat, so the list freezes until combat
  ends and the keybind/macro do nothing in combat. Show/hide changes
  made in combat apply when combat ends.
- No line-of-sight check: addons can't check it in advance; a failed
  cast reports the game's own "Target not in line of sight" error.
- No discovery beyond group, target, mouseover and friendly
  nameplates — there is no API for a general nearby-player list.

## Verification status

- 1.2.2 and earlier were confirmed working live by SEAN on
  2026-10-20. 1.2.4 (the TOPLEFT anchoring fix) was built but
  unverified in game, and **1.3.2 — the unified-source build — 1.4.0,
  1.5.0, 1.6.0, 1.7.0 and 1.8.0 are likewise built but UNVERIFIED in
  game**. The Retail edition ended at 1.7.0 (Interface 120105), a
  separate zip from the same source with its own feature list.
