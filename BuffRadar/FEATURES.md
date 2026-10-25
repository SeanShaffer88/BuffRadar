# BuffRadar — Features (Retail edition)

The full feature list for BuffRadar 1.6.0 for WoW Retail
(patch 12.1.5, Interface 120105). For the short version see
`README.md`; for store-listing copy see `DESCRIPTION.md`.

Prepared 2026-10-24 from the shipped 1.3.2 README and CHANGELOG;
updated 2026-10-25 for 1.6.0.
Since 1.3.2 the Retail and Forever editions are built from one
source — the addon picks its buff set when it loads — so fixes and
features land in both at once; differences from the Forever edition
are called out below.

## New in 1.6.0

- **Buff assignments** (`/br assign <BUFF> <name|none>`): the group
  leader or an assistant assigns a buff to one player. On their list
  the rows float, tagged *your assignment*; on everyone else's they
  sink, tagged *assigned elsewhere*. Session-only; travels over the
  cast-sync channel (`/br sync`).
- **Buddy split** (`/br buddy`): with sync on, two or more BuffRadar
  users split the list by a stable hash of each player's GUID. Your
  share floats; the rest sink, tagged *buddy's watch*. A sort, not a
  filter — nobody disappears.
- **Blessing planner** (Forever edition only, `/br bless`): plan a
  blessing per class, optionally for one named paladin.
- **All-buffed pill** (`/br pill`): while everyone in the group is
  fully buffed the window collapses to a small pill showing the
  coverage count; click it to peek at the window for five seconds.
- **Cast queue tag:** after one of your casts lands, the next row is
  tagged *up next* for a few seconds.
- **Consumables watch** (`/br consumables`): flask, food and Augment
  Rune counts join the coverage line. Read-only: consumables never
  create rows.
- **Custom watched spells** (`/br custom add|remove|list <spell ID>`):
  watch any buff spell you know, offered to everyone it suits.
  Stored per character; not carried by settings export or named
  profiles.
- **Coverage uptime** (`/br uptime`): the share of grouped scans
  this run that found nobody missing anything, on the coverage line
  from ten scans up. Resets when a Mythic+ run starts and when the
  group ends.
- **Shipped presets** (`/br preset raid|dungeon|solo`, buttons on
  the Ignore & Stats tab): one-click starting points for raid,
  dungeon and solo play.
- **Auto-switch profiles** (`/br autoprofile <context> <profile>`):
  raid, dungeon, pvp, world (grouped) and solo contexts each load a
  mapped named profile on entry.
- German translation covers all 62 strings; `/br selftest` also
  reports the 1.6.0 state (pill, queue tag, consumables, customs,
  buddy split, uptime, assignments, plan, auto profiles, peers).

## New in 1.5.0

- **Cast sync between BuffRadar users** (`/br sync`): casts by any
  BuffRadar user in the group mark the target *being buffed* on every
  user's list for a few seconds and sink their row.
- **Chat buff requests** (`/br requests`): a whisper or nearby say
  asking for a buff tags the asker's row *asked for a buff*.
- **Join digest** (`/br digest`): one summary line when joining a
  group, and again when a Mythic+ run starts.
- **Buff toggle strip** (`/br strip`): one icon per castable buff
  under the title; click to toggle. Beside it, **role filter chips**
  (All / Tank / Heal / DPS, `/br filter`) narrow the window list to
  one role — reports still cover everyone.
- **Need sort** (`/br sort need`): most missing buffs first.
- **Phase-aware scanning:** group members in another phase are not
  listed.
- **Idle fade** (`/br fade <0-90>`): the window fades while the
  mouse is elsewhere.
- **Named settings profiles** (`/br profile save|load|delete|list`,
  or the Ignore & Stats tab): complete settings sets under a name.
- **Drop alert** (`/br watch`): message, sound and border flash when
  your single-target buff (Earth Shield) drops off its holder.
- **Coverage cooldown note:** a buff on a real cooldown is flagged
  on the coverage line, e.g. *Skyfury 15/15 (~3m cd)*.
- **Flight-path pause** (`/br taxi`, optional) and an **off-screen
  window rescue** with `/br resetpos`.
- German translation now covers all 53 strings; `/br selftest` also
  reports the 1.5.0 state (sync, requests, filter, profiles, fade).

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
  profiles** for toggles and rebuff timings.
- **Settings export/import** as one string, **compact rows**, separate
  **list text size**, **per-character window position**, a **post-combat
  border flash**, and **`/br selftest`** for bug reports.
- Settings-window tabs and main checkboxes are translatable now;
  German covers all 44 strings.

## The list

- **Live list of who needs what.** Every nearby player missing one
  of your buffs is listed with portrait, class-colored name and the
  icons of what they still need. Players drop off once buffed.
- **You first.** Your own character is always checked first and sits
  at the top of the list whenever you're missing something.
- **The list grows downward.** The window is anchored by its
  top-left corner only, so its top edge stays where you put it as
  names come and go.

## Buffing

- **Click-to-buff.** Click a name to buff that player; hovering a
  name shows exactly what will be cast and what they still need.
  Buffing a group member no longer changes your target; for a
  player outside your group, BuffRadar targets them by name, casts,
  then switches back to your previous target.
- **One-key buffing.** Bind *Cast next buff*, or use the BuffRadar
  macro (`/br macro`), to work through the list without clicking.
- **One cast covers the group.** Retail raid buffs apply to your
  whole party or raid when cast on a group member, so one click
  usually clears several rows at once.
- **Class-aware.** Arcane Intellect only goes to mana users, Earth
  Shield to tanks (by the group role they picked; by class for
  anyone without one), and so on.
- **Smart checks.** Buffs about to expire are offered again. Spells
  on cooldown (Blessing of the Bronze, Battle Shout) are skipped
  while they cool down — both also only reach you and your group,
  so they are offered only to you and group members, never to
  strangers.
- **Earth Shield goes to one tank at a time.** It can sit on only
  one other player, so while yours is on a tank, nobody else is
  offered it; when it's about to run out, that same tank is.

## Supported buffs (Retail)

These are Blizzard's player-cast long-term raid buffs for patch
12.1.5, rebuilt for 1.3.0 from Blizzard's raid-buff list:

| Class   | On by default | Off by default (situational) |
|---------|---------------|------------------------------|
| Mage    | Arcane Intellect (mana users) | — |
| Warrior | Battle Shout (you & your group) | — |
| Priest  | Power Word: Fortitude (everyone) | — |
| Druid   | Mark of the Wild (everyone) | Thorns (melee, PvP talent) |
| Shaman  | Skyfury (everyone), Water or Lightning Shield (you) | Earth Shield (tanks, one at a time) |
| Evoker  | Blessing of the Bronze (you & your group) | — |
| Warlock | — | Unending Breath |

Deliberately excluded: an evoker's *Source of Magic* and a druid's
*Symbiotic Relationship* can each sit on only one player per caster,
so a list like this can't represent them — everyone else would show
as missing forever. Paladins, death knights, rogues, hunters, monks
and demon hunters have no castable long-term buff for others on
retail (their raid contributions are auras or enemy debuffs), so the
window stays hidden on those characters.

Three spell IDs in the 1.3.0 table (Battle Shout, Skyfury, Blessing
of the Bronze) were flagged for `/br debug` confirmation in a retail
client.

## Seeing nearby players, alerts, settings

Same as the Forever edition: discovery is group units + target +
mouseover + friendly nameplates only (nameplates required for
strangers, with the login warning and `/br debug` reporting when
they're off); water-droplet alert with mute/system/none choices;
out-of-range rows greyed **and marked *out of range* in text**, so
the state doesn't rely on color alone; role ordering (you, tanks by
group role, and leaders first); city/battleground pauses (Dornogal
is in the retail city list); party/raid-only mode; autohide; minimap
button and addon-compartment entry; tabbed settings window (Window /
Alerts / Buffs / Behavior / Ignore & Stats); session and all-time
cast counters with per-spell statistics; three keybinds (Cast next
buff, Show / hide window, Mute / unmute sound).

Retail settings details: the ignore list is realm-aware and ignores
capitalization, and names can be removed one by one on the Ignore &
Stats tab. The window resizes by dragging its bottom-right corner,
and scale dropdowns (50%–200%) cover both the list window and the
settings window. Settings open from the gear icon, by right-clicking
the minimap button or the addon menu entry, via Esc > Options >
AddOns, or with `/br config`; every setting has hover help, and the
Buffs tab carries a per-buff rebuff-timing box. The main window, its
tooltips and the minimap tooltips are translated into German on
German clients; the settings window is English for now.

Retail differences: there is no group-cast offer (retail raid buffs
already apply group-wide) and no highest-rank logic (buffs are not
ranked on retail).

## Not in this version

- No buffing during combat, no line-of-sight check, and no discovery
  beyond group, target, mouseover and friendly nameplates — the
  same platform limits as the Forever edition.
- No support for single-target-per-caster buffs (Source of Magic,
  Symbiotic Relationship) — see above.

## Verification status

- **1.6.0 is built but UNVERIFIED in a retail client** (1.5.0, 1.4.0
  and 1.3.2 were never verified either). Midnight
  removed the "load out-of-date addons" option, so this edition
  loads only while its interface version matches the live patch
  (120105 = 12.1.5); a new retail patch needs a new build with the
  updated number, and the TOC must match exactly.
