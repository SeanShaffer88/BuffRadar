# BuffRadar — Features (Forever edition)

The feature list for BuffRadar (Forever edition) for
WoW: Forever (Interface 16001). For the short version see
`README.md`; for store-listing copy see `DESCRIPTION.md`.

The shipping Forever TOC requires Interface 16001. The historical Retail
TOC remains a test fixture; 1.7.0 was the last Retail release.

## Unreleased: rank caps

- `/br rank <BUFF_KEY> <1-20>` keeps one buff at or below a chosen rank, to save
  mana while levelling (for example Arcane Intellect rank 2). Target, ID, rank
  and macro cast modes all honour it; the target-level rank fallback still
  applies below the cap. `/br rank <BUFF_KEY> max` clears it and `/br rank`
  lists the caps. `/br buffs` shows the buff keys.

**Verification:** automated checks; live behavior remains **Unverified**.

## 1.20.1: Verification and Refresh Clarity

- Document the distinction between event-driven player/roster/aura refreshes and
  the remaining low-frequency cooldown-readiness sweep.
- Correct `/br throttle` wording and publish automated test evidence separately
  from the live-client checklist; no live test is claimed.

## 1.20.0: Event-Driven Refresh and Safer Integration

- Use event-driven refreshes instead of unnecessary recurring scans, while
  retaining compatibility with clients that lack optional timers.
- Expose a read-only status bridge for display integrations and diagnostics.
- Harden combat and player-life transitions, including delayed updates to the
  client's living flag and protected UI behavior.
- Add Auto Theme Priority controls and keep settings modal panels open through
  live refreshes.

## 1.19.1: Battleground and Blessing Diagnostics

- `/br support` adds fixed instance, pause-preference, combat/PvP and cached
  blessing-knowledge fields to the private technical report.
- `/br why NAME` separates global pause/safety state from player buff needs and
  explains preferred/effective blessings, precedence and complement decisions.
- Unknown evidence remains unknown. Diagnostic aura reads are isolated from
  normal scan state. No player/caster names or raw errors enter Support exports.

## 1.19.0: Current Workflow

- **Searchable Actions:** `/br actions` and the Settings Actions button expose
  inspection, management and troubleshooting alongside settings search. Filters,
  slash equivalents and live availability reasons retain keyboard navigation and
  narration. Argument-based actions open existing forms and reviewed editors.
  Shift-left-click on the gear and an optional Actions keybind open the same UI.

- **Reviewed assignment copying:** copy a configured cell or row to a chosen
  destination, review rule changes and current-group offers, then apply locally.
  Default, None and custom values retain their distinct meanings.
- **Section-only imports:** Whole Profile keeps complete import behavior;
  Selected Sections applies Appearance, Alerts and/or Buff Rules while preserving
  identities, connections, supplies and unselected settings. The whole input
  validates before any selected fields are applied.
- **Local preference recovery:** `/br recovery` reviews one bounded previous-settings
  or pre-upgrade snapshot. Restore is explicit and leaves identities, profiles,
  cast history and purchase authorization outside the snapshot.
- **Three-item update notice:** dismiss the account-wide notice, open its Daily
  Tasks link, or reopen it with `/br whatsnew`. Settings includes both links.
- **Retained picker navigation:** normal assignment-picker edits are immediate;
  Done, X and Escape preserve the selection and return to the grid. Blocker-draft
  Cancel, X and Escape discard staged edits; review Back retains the draft.


- **Optional coverage views:** `/br matrix` presents bounded player/buff pages
  from committed scan evidence; `/br selfstrip` reports personal aura status in
  fixed slots. Symbols and text distinguish confirmed, missing, unknown and
  not-applicable results. Neither view casts or changes the tracking toggles.
- **Confirmed reagent restocking:** `/br supplies` offers opt-in, supported-item
  targets and per-confirmation copper/unit caps. Review a merchant quote and
  explicitly confirm its next row. Quote changes cancel consent. Only gold
  prices and safely bounded quantities are supported; bag estimates use empty
  general slots. A request is not treated as confirmed inventory delivery.

**Verification:** original Lua 5.1 offline regressions cover read-only models,
quote mutation/staleness, bundles, caps, unknown data and no-purchase paths.
Actual merchant behavior and native rendering remain **Unverified**.

- **Setup and discovery:** `/br wizard` reviews a starting configuration;
  `/br plates` enables friendly nameplate discovery and `/br nearby` diagnoses it.
- **Casting:** click a row, bind **Cast next buff** with `/br key`, or create
  the managed action-bar macro with `/br macro`. The footer distinguishes
  direct-binding readiness from macro readiness, including parked and pending
  states. Use the stated reason; a queue alone does not prove either path ready.
- **Settings:** `/br config find` searches all six tabs with `Tab > Setting`
  results, Previous/Next paging and exact-control focus. Selecting a result
  leaves its value unchanged. Escape closes search; keyboard navigation and
  narration remain available.
- **Assignments and preparation:** `/br why <name>`, `/br coverage` and
  `/br prep` explain rules and distinguish missing buffs from unknown readings.
  Missing role data falls back to the class's World assignment cell.
- **Profiles and troubleshooting:** `/br profile` manages named profiles;
  imports are previewed before applying. `/br status export` includes separate
  **Cast delivery** diagnostics. See the [player guide](README.md) for the
  everyday workflow and [changelog](CHANGELOG.md) for release history.

<details>
<summary>Historical Release Highlights (version-specific counts and behavior)</summary>

## 1.16.3: shared-scanner maintenance

- Preserve ownership of single-recipient buffs when their holder is ignored or
  filtered. Regression checks exercise the historical Retail Earth Shield
  definition; Forever's current definitions do not use this mode.

**Verification:** automated checks; live behavior remains **Unverified**.

## 1.16.2: macro after relog

- The BuffRadar action-bar macro stays managed after you log in again. The
  game returns saved macro text with a trailing line break, which BuffRadar
  no longer mistakes for a hand-edited macro. Macros you edited yourself are
  still left alone.

**Verification:** automated checks; live behavior remains **Unverified**.

## 1.16.1: accurate cast history

- Preserve cast counts and history when Forever reports a successful cast
  after rapid retries on the same target and spell. Different-target overlaps
  remain uncredited if their origin is unclear.

**Verification:** automated checks; live behavior remains **Unverified**.

## 1.16.0: safer casts, saves and sharing

- A scan or viewport paint failure clears cast actions until a successful
  refresh. The viewport scrolls when fewer rows fit your screen.
- Group casts use the same eligibility checks for automatic offers,
  Shift-click, and the group key. Missing prerequisites fall back to the
  single cast. Pet rows bind their pet unit, not a player's name.
- Food, flask, drinking and world-buff checks use recognised aura IDs and
  client spell names. An unreadable observation is not a confirmed absence.
  Personal readiness checks temporary coatings only on eligible weapons.
- Schema 23 preserves newer saves and deliberate profile/ignore overflow.
  Review pasted settings before applying. Named profiles show collisions
  and may be stored under another name without loading them.
- Plan imports are local by default. Sharing requires an explicit choice,
  current group membership and permission to send. Auto-profile mappings
  stay local. A send result doesn't confirm that another player received it.
- `/br positions on` remembers Settings and Ready Check positions (off by
  default). `/br perf` reports available CPU timing samples by type.

## 1.15.37: Readiness

- Forecast confirmed expiry using real aura durations and a supported pull or
  local preparation timer, without changing cast eligibility.
- Reorder already eligible buffs with smart priority for tanks, healers, wipe
  recovery and instance rules. The saved manual order still breaks ties.
- Keep player/focus debuff icons and stack counts separate from the cast queue.
  An optional encounter ID restricts a watch to that boss fight.
- Open personal raid preparation even solo. See Healthstones in bags, gear
  durability and an optional consumable aura alongside food, flask and weapon
  checks. The client does not report placed Soulwell availability.
- Choose role and activity in Quick Setup. Enable contextual minimap symbols
  and quiet visuals, with Reduced Motion support.
- Read or export buff status, adjust the adaptive cooldown sweep, report total
  memory and pause optional work with Lite mode. Queue refreshes remain event-driven.

**Verification:** fake-client Lua 5.1 and package checks. Live behavior remains
**Unverified** pending the Forever release checklist.

## 1.15.16

- Diagnose why nearby players are absent from the buff list.
- Preview the next target and selected spell rank.
- Fall back to a single-target buff when a group reagent is missing.
- Set a normal blessing exception for a member of the current group.
- Review ready-check responses, buff status, and estimated reagent needs.

See `CHANGELOG.md` and the in-game release checklist for verification status.

## New in 1.10.0

A customization batch (all ten also exist as `/br` commands):

- **Saved themes** — name and keep up to four of your own color
  themes (`/br theme save <name>`), alongside the built-ins.
- **Row spacing + icon size** — vertical padding between rows, and
  missing-buff icons at a size you pick (`/br rowgap`, `/br iconsize`).
- **Coverage-line part toggles** — each of the line's seven parts
  (progress, your buffs, uptime, group, expiry, world buffs, healer
  drinking) can be hidden on its own (`/br cover`).
- **A sound per alert kind** — new-name, buff-drop and buff-request
  alerts each pick their own sound (`/br soundfor`).
- **Tooltip detail levels** — minimal, standard, or full tooltips;
  full adds the player's situation and who else could cast the buff
  (`/br tooltip`).
- **Row color marks** — a thin color bar marks rows that are your
  assignments, tanks, expiring soon, or your buddy's half (`/br
  rowcolor`).
- **Group-by-buff view** — one row per buff still needed, with a
  count; clicking casts that buff on an in-range player who needs
  it (`/br view buffs`).
- **Your buff order** — rows offer your buffs in your order; the
  first is the click target (`/br prio`).
- **Click-through** — clicks pass through the window while it is locked
  (`/br clickthrough`). The window stays on the client's standard layer
  to avoid a blocked frame action.
- **Name formats** — class-colored names on/off, realm names
  shown/hidden, and a longest-name length.

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
  string. Import opens a review; **Apply locally** is the default. If
  authorised, **Apply and share** sends changed assignments and blessings,
  not auto-profile mappings.
- **Name finder** (`/br find`, `/br findbox`): a search box on the
  window filters the list by name; reports stay unfiltered.
- **Duration bars** (`/br bars`): a thin bar under each row shows
  the shortest time left on that player's buffs from your set
  (green / yellow under 15m / red under 5m).
- **Grow upward** (`/br growup`): the list can grow up from a
  bottom anchor instead of down.
- **Combat safety:** the window and pill hide during combat, buff buttons
  are disabled, and targets in combat never appear.
- **Color themes** (`/br theme`): choose a built-in window palette, save your
  own, or select Auto to match a loaded UI addon. **Auto Theme Priority**
  (`/br theme priority panel`) sets the order and shows the selected addon. A
  hand-picked background color selects Custom. The Theme button or
  `/br theme preview` previews a palette without changing saved settings;
  Apply saves it and Cancel restores the previous appearance.
- **Raid target markers** (`/br markers`): rows show the raid
  marker currently on that player.
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
  coverage line) flags an applicable melee weapon with no temporary
  coating (such as an imbue, poison, oil or stone). Empty slots, shields, and
  ranged weapons don't count as missing.
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

</details>

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
  name lights its row with a faint wash in the theme's border colour
  and shows exactly what will be cast and what they still need.
  Since 1.3.2, buffing a group member no longer changes your
  target; for anyone else, BuffRadar targets them by name, casts,
  then switches back to your previous target.
- **One-key buffing.** Bind *Cast next buff* to a keyboard or controller
  button (`/br key` or `/br gamepad`), or put the managed BuffRadar macro
  (`/br macro`) on an action bar. A hand-written `/click` macro can't
  chain another macro to reach an ungrouped target.
- **Recipient rank.** Supported cast modes choose a recipient-eligible
  learned rank when the client supplies rank and level information.
  Plain-name macro mode leaves the choice to the game. Missing information
  can leave the highest learned rank as the fallback. The footer previews
  the prepared cast.
- **Class-aware.** Arcane Intellect only goes to mana users, Thorns
  to melee classes, Fear Ward to warriors, and so on. Paladins give
  each class one fitting blessing: **Blessing of Kings leads every
  class list since 1.2.3** (it is learned after Might/Wisdom, so it
  was previously unreachable); Might (warriors, rogues) and Wisdom
  (everyone else) are the fallbacks. **Complement Nearby Blessings** is
  on by default: when a player outside your group already has another
  Paladin's copy of your preferred blessing, BuffRadar offers an available
  class-appropriate alternative. Use `/br bless complement off` to disable it.
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
| Priest  | Power Word: Fortitude (everyone), Divine Spirit (mana users), Fear Ward (warriors), Inner Fire (you), Shadowguard (you) | Shadow Protection |
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
  `/br plates` turns friendly nameplates on. Use `/br plates off` to turn
  them off, `/br plates names` to keep discovery without health bars on
  supported clients, or `/br plates restore` to undo recorded changes.
  These controls are also in Nearby Player Diagnostics (`/br nearby`).
- **Range can be unanswerable.** This client may accept a range query and
  return a value no addon is allowed to read. `C_Spell.IsSpellInRange` behaves
  that way, `UnitInRange` reports nothing usable for anyone outside your group,
  and `CheckInteractDistance` can be restricted too. When no check answers, a
  player is treated as out of range and the window can stay empty. `/br
  apicheck` names which check answers on your client, and `/br assumerange`
  (off by default) lists those players with their range shown as estimated.

## Alerts, ordering and staying out of the way

- **Water droplet alert** when someone new appears (optional, with a
  mute keybind; a system sound or silence can be chosen instead, and
  alerts can stay quiet in instances).
- **Explicitly out-of-range players are not cast rows.** Range Watch
  (`/br rangewatch`) can alert when a player enters range. Assumed range is
  an opt-in for unanswered checks and is marked estimated. **Right-click a
  row** or use `/br ignore` to add to the realm-aware permanent ignore list
  (up to 192 names); remove names on the Ignore & Stats tab or with
  `/br unignore`.
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

- Six-tab settings window (Window / Alerts / Buffs / Behavior /
  Ignore & Stats / Readiness) in the standard game style with
  tabs along the bottom where the client provides it: background
  color, opacity, title, border, width and scale; per-buff on/off
  (`/br buffs`, `/br toggle KEY`); per-buff rebuff timing on the
  Buffs tab; hover help on every setting; clickable checkbox
  labels. Dragging either bottom corner scales the whole window
  (width: `/br width`), and scale dropdowns (50%–200%) cover the list window and the
  settings window. Settings open from the gear icon, by
  right-clicking the minimap button or the addon menu entry, via
  Esc > Options > AddOns (on clients that list addon options), or
  with `/br config`. `/br config find` searches across the tabs and focuses
  the selected setting without changing it.
- **Languages:** English and complete German, French, Spanish, Russian and
  Simplified Chinese packs cover all current settings, list and tooltip keys.
  Strict offline checks validate formatting, literal commands and locale-first
  flows; native-speaker certification and actual client rendering are unverified.
- **First cast guide:** `/br firstcast` explains discovery and delivery readiness,
  then confirms a user-triggered cast only through the normal attributed success
  path. Closing/reopening starts a fresh attempt; combat pauses guidance.
- **Private support report:** `/br support` opens a local copy dialog containing
  a bounded typed technical report with delivery state, relevant settings,
  error counts, peer verification counts, and the selected theme.
  Names, profile labels, macro bodies, history
  and raw errors are excluded. Nothing is sent or copied to the clipboard
  automatically. Both actions are also in **Readiness** settings.
- **Cast counter** for this session and all-time, plus per-spell cast
  statistics (`/br count`, `/br resetcount`, `/br stats`). The
  session count resets on login or `/reload`; the all-time count is
  shared by all your characters.
- Four keybinds: **Cast next buff**, **Cast next group buff**,
  **Show / hide window**, and **Mute / unmute sound** (`/br key`).

## Not in this version

- No buffing during combat: the window is hidden, secure buff buttons
  are disabled, and players in combat are excluded.
- No pre-cast line-of-sight check. A line-of-sight error can advance the
  queue when BuffRadar can link it to the attempted cast.
- No discovery beyond group, target, mouseover and friendly
  nameplates — there is no API for a general nearby-player list.

## Verification status

**1.16.0:** Lua 5.1 fake-client, coordination, lint, and package checks cover
this release. CI compares Windows and POSIX build digests. Live Forever
behavior is **Unverified**. Fake clients do not reproduce taint, chat
delivery, real viewport rendering, or
restricted aura/range behavior on a live build. Known spell IDs are not a
complete catalogue of all Forever consumables or world buffs.

**1.15.35:** Macro migration, nearby cast targeting, blessing
selection, and reversible nameplate controls pass the Lua smoke tests.
Live casting, controller bindings, and nameplate appearance are **Unverified**.

**Field test through 1.15.33:** on 2026-11-16 the maintainer reported that
every release up to and including 1.15.31 passed in-game testing in WoW:
Forever, and later that day that 1.15.32 (Shadowguard watch) and 1.15.33
(input hardening) passed their checklist steps too. 1.15.34 (source
file split and the row hover highlight) is not yet verified in game.

**1.15.16:** The maintainer confirmed live verification
in WoW: Forever on 2026-11-14 using field-test build `d05115bdb03d`.

The maintainer verified scrollable rows for 1.15.11 using field-test build
`650f5c603781` in WoW: Forever on 2026-11-14.

The maintainer also verified the 1.15.10 field-test build `274b0298d250` in
WoW: Forever on 2026-11-14.

- 1.2.2 and earlier were confirmed working live by SEAN on
  2026-10-20. **1.12.0 was verified in game by SEAN on Forever
  1.60.1.70862** (2026-11-08) — that run covers the cumulative
  1.3.2–1.12.0 feature set on the Forever client. 1.13.0 through
  1.15.33 were verified in game by the maintainer (reported
  2026-11-16). A first in-game look at 1.15.0 (2026-11-11) found
  settings-window layout faults, fixed in 1.15.1. The Retail edition ended at 1.7.0
  (Interface 120105), a separate zip from the same source with its
  own feature list.

<details>
<summary>Earlier Fixes and Additions</summary>

## Fixed in 1.15.2

- List only players currently in cast range who can benefit from a known
  buff and are out of combat; targets in combat are excluded.
- Hide and disarm buff buttons during combat.
- Detect the game's line-of-sight failure message and temporarily skip
  that target so the next keybind press can move on.
- Remove the range-display and combat-hide toggles, which no longer
  match the safe eligibility rules.

## Fixed in 1.15.1

- Window tab re-spaced in a taller settings window; the Display options panel now replaces the tab instead of drawing over it; duration bars, raid markers, range words and the focus watch line moved into that panel ("Row extras").

## Added in 1.15.0

- `/br fallsound` - a distinct sound when a watched group buff falls off during a fight (off by default; #33).
- Pull countdown on the coverage line while a pull timer runs (with `/br pullflash` on).
- `/br grouppair "Single" "Group"` - your own Shift-click group-cast pairs.
- "Cast next group buff" key binding - casts the group version of the first row's buff.
- `/br why <name>` - the deciding reason a player is or is not on the list.
- Settings window and slash commands moved to their own files (internal; no behaviour change).

## Added in 1.14.0

- `/br fastaura` - skip rescans when readable aura changes can be identified as
  unrelated to watched buffs (off by default). The cache retains watched
  instances. An unrecognized removal triggers a rescan.
- `/br modclick` - Shift-click a row casts the group version of its buff (off by default).
- `/br pullflash` - border flash and a countdown line when a group pull timer starts (off by default).
- Buff tables, presets and themes moved to `Data.lua` (internal; no behaviour change).

## Added in 1.13.0

- `/br apicheck export` - API report in a copy window.
- `/br ignorelist export | import` - move the ignore list between characters.
- `/br summary` - casts still needed per buff, biggest first.

</details>
