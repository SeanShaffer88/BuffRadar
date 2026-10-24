# BuffRadar — Features (Retail edition)

The full feature list for BuffRadar 1.3.2 for WoW Retail
(patch 12.1.5, Interface 120105). For the short version see
`README.md`; for store-listing copy see `DESCRIPTION.md`.

Prepared 2026-10-24 from the shipped 1.3.2 README and CHANGELOG.
Since 1.3.2 the Retail and Forever editions are built from one
source — the addon picks its buff set when it loads — so fixes and
features land in both at once; differences from the Forever edition
are called out below.

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

- **1.3.2 is built but UNVERIFIED in a retail client.** Midnight
  removed the "load out-of-date addons" option, so this edition
  loads only while its interface version matches the live patch
  (120105 = 12.1.5); a new retail patch needs a new build with the
  updated number, and the TOC must match exactly.
