# BuffRadar — Features (Forever edition)

The full feature list for BuffRadar 1.4.0 (Forever edition) for
WoW: Forever (Interface 16001). For the short version see
`README.md`; for store-listing copy see `DESCRIPTION.md`.

Prepared 2026-10-24 from the shipped 1.3.2 Forever README and
CHANGELOG; updated 2026-10-25 for 1.4.0. Since 1.3.2 both editions are built from one source —
the addon picks the Forever buff set when it loads on the Forever
client — and the Forever buff set itself is unchanged from 1.2.4.

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
  unverified in game, and **1.3.2 — the unified-source build — and
  1.4.0 are likewise built but UNVERIFIED in game**. The Retail
  edition (1.4.0, Interface 120105) is a separate zip from the same
  source with its own feature list.
