<p align="center"><img src="Media/logo.png" alt="BuffRadar logo" width="160"></p>

# BuffRadar

**A click-to-buff list for World of Warcraft — Retail edition.**

BuffRadar shows a small window listing every nearby player who is missing one of *your*
buffs — with their portrait, class-colored name and icons of what they still need.
Click a name to buff them. Press one key (or one macro) to buff the next person.
You always come first.

Version 1.3.2 (Retail edition) · Interface 120105 · For retail patch 12.1.5 (Midnight) · License: GPLv3

This is the retail edition of BuffRadar. A Forever edition (interface 16001) exists
for that client; both are built from the same source and share the same settings
layout — only the `.toc` differs, and BuffRadar picks the right buff set when it loads.

---

## Features

- **Live list of who needs what.** Players stay listed until every buff you can cast
  that suits their class has been applied, then drop off.
- **The list grows downward.** The window is anchored by its top-left corner, so
  its top edge stays exactly where you put it as names come and go — only the
  bottom edge moves.
- **You first.** Your own character is always checked first and sits at the top of the
  list whenever you're missing something.
- **Class-aware.** Arcane Intellect only goes to mana users, Earth Shield to tanks
  (by the role they picked in your group; by class for anyone without one),
  and so on.
- **One-key buffing.** Bind *Cast next buff* or use the BuffRadar macro to work through
  the list without clicking.
- **One cast covers the group.** Retail raid buffs apply to your whole party or raid
  when cast on a group member, so one click usually clears several rows at once.
- **Smart checks.** Buffs about to expire are offered again. Spells on cooldown
  (Blessing of the Bronze, Battle Shout) are skipped while they cool down.
- **Water droplet alert** when someone new appears (optional, with a mute keybind;
  a system sound or silence can be chosen instead, and alerts can stay quiet in
  instances).
- **Out-of-range players** can stay listed, greyed and marked *out of range*, so you
  see who's coming into range. **Right-click a row** to ignore a player who doesn't
  want buffs.
- **Role ordering** option: you, tanks (by group role) and leaders first.
- **Stays out of the way:** pauses in major cities (and, optionally, in
  battlegrounds), can show only while you're in a party or raid, and has a
  show/hide keybind, a minimap button and an addon-compartment entry.
- **Cast counter** for this session and all-time, plus per-spell cast statistics.
- **Customizable look:** background color, opacity, title, border, width and scale —
  in the tabbed settings window (Window / Alerts / Buffs / Behavior / Ignore & Stats).
  Drag the window's bottom-right corner to make it wider or narrower; pick a scale
  (50%–200%) for the list window and for the settings window from their dropdowns.

## Supported buffs

| Class   | On by default | Off by default (situational) |
|---------|---------------|------------------------------|
| Mage    | Arcane Intellect (mana users) | — |
| Warrior | Battle Shout (you & your group) | — |
| Priest  | Power Word: Fortitude (everyone) | — |
| Druid   | Mark of the Wild (everyone) | Thorns (melee, PvP talent) |
| Shaman  | Skyfury (everyone), Water or Lightning Shield (you) | Earth Shield (one tank at a time) |
| Evoker  | Blessing of the Bronze (you & your group) | — |
| Warlock | — | Unending Breath |

These are Blizzard's player-cast long-term raid buffs, minus two: an evoker's
*Source of Magic* and a druid's *Symbiotic Relationship* can each sit on only one
player per caster, so a list like this can't represent them — everyone else would
show as missing forever. Paladins, death knights, rogues, hunters, monks and demon
hunters have no castable long-term buff for others on retail (their raid
contributions are auras or enemy debuffs), so the window stays hidden on those
characters.

## Installation

1. Download and unzip.
2. Move the `BuffRadar` folder into your retail `Interface\AddOns` folder, so the path
   is `Interface\AddOns\BuffRadar\BuffRadar.toc`.
3. Restart the game (a `/reload` is not enough the first time).
4. **Turn on friendly nameplates** (Shift+V, or `/br plates`). The game only lets addons
   see nearby players outside your group through their nameplates.

## Using it

| Action | How |
|---|---|
| Buff someone | Click their name in the window |
| Buff the next person | Your *Cast next buff* key, or the BuffRadar macro |
| Settings | Gear icon in the bottom-left corner, right-click the minimap button or the addon menu entry, Esc > Options > AddOns > BuffRadar, or `/br config` — hover any setting for a short explanation |
| Show / hide from the minimap | Left-click the minimap button or BuffRadar in the minimap's addon menu |
| Rebuff timing | Settings > Buffs: a seconds box per buff (empty = the all-buffs time) and one for all buffs |
| Move the window | Drag it (lock it with `/br lock`) |
| Resize the window | Drag its bottom-right corner (width), or pick a scale in Settings > Window |
| Hide or show the window | Your *Show / hide window* key, or `/br` |
| Mute the sound | Your *Mute / unmute sound* key, or `/br sound` |

Hover over a name to see exactly what will be cast and what they still need.

### Keybind and macro

- **Keybinds:** Settings > *Set keybind* opens Key Bindings at the BuffRadar section,
  which has three: **Cast next buff**, **Show / hide window** and **Mute / unmute sound**.
- **Macro:** Settings > *Create macro* (or `/br macro`) puts a ready-made macro on your
  cursor. Drop it on an action bar. You can also add this line to any macro:

  ```
  /click BuffRadarNextButton LeftButton 1
  ```

  Use `/click BuffRadarNextButton` instead if you've turned off *Cast action keybinds on
  key down* in the game options. The BuffRadar macro updates itself if you change that.

## Commands

| Command | What it does |
|---|---|
| `/br` | Show or hide the window |
| `/br config` | Open the settings window |
| `/br key` | Open Key Bindings at the BuffRadar section |
| `/br macro` | Create the BuffRadar macro |
| `/br buffs` | List the buffs you can cast and whether each is on |
| `/br toggle KEY` | Turn one buff on or off (keys come from `/br buffs`) |
| `/br self` | Turn checking yourself first on or off |
| `/br sound` | Turn the water droplet alert on or off |
| `/br group` | Only show the window in a party or raid (off by default) |
| `/br cities` | Pause scanning in major cities (on by default) |
| `/br count` · `/br resetcount` | Show or reset the cast counter |
| `/br rebuff <seconds>` · `/br rebuff KEY <seconds>` | Re-offer a buff when less than this much time is left (default 30; per-buff override by key; also on Settings > Buffs) |
| `/br sort name\|role` | List order: name, or tanks & leaders first |
| `/br ignore <name>` · `/br unignore <name>` · `/br ignorelist` | Manage the ignore list (or right-click a row; remove names on the Ignore & Stats tab). Capitals don't matter; `Name-Realm` means that one player, a plain `Name` means that name on every realm |
| `/br alertsound droplet\|system\|none` | Choose the new-name alert sound |
| `/br bg` · `/br minimap` · `/br stats` | Pause in battlegrounds · toggle minimap button · casts by spell |
| `/br pvp` | Include or skip PvP-flagged players when you aren't flagged (skipped by default) |
| `/br lock` · `/br scale <n>` · `/br reset` | Lock (moving and resizing), set any scale from 0.5 to 2, or reset the window's position |
| `/br autohide` | Hide the window when nobody needs anything |
| `/br plates` | Turn on friendly nameplates |
| `/br clicks` · `/br debug` | Troubleshooting output |

## Good to know

- **Combat:** the game doesn't let addons change click-to-cast buttons during combat,
  so the list freezes until combat ends. The keybind and macro do nothing in combat.
- **Line of sight:** addons can't check line of sight in advance. If a cast fails with
  *"Target not in line of sight"*, move and try again.
- **Targeting:** party and raid members are buffed directly, without touching your
  target. To buff a player outside your group, BuffRadar targets them by name,
  casts, then switches back to your previous target.
- **Seeing strangers:** the game gives addons no list of nearby players. BuffRadar
  finds people through your group, your target, your mouseover, and friendly
  nameplates — so with friendly nameplates off, only grouped, targeted or hovered
  players can appear. When nameplates are off the window says so instead of
  claiming everyone is buffed, and BuffRadar warns once at login. `/br debug`
  shows whether nameplates are on and how many the game is currently showing.
- **Major cities:** Stormwind, Ironforge, Darnassus, Orgrimmar, Thunder Bluff, Undercity,
  The Exodar, Silvermoon, Shattrath and Dornogal. If a city isn't detected, `/br debug`
  shows the zone and map ID BuffRadar sees.
- **Retail raid buffs spread on their own:** casting one on a group member applies it
  to the whole party or raid in range, so rows clear in bunches. **Battle Shout** and
  **Blessing of the Bronze** are group-only casts by the game's rules — they can't be
  given to strangers, so BuffRadar only lists you and your group for them. Both
  have a short cooldown BuffRadar waits out.
- **Patch days:** Midnight removed the "load out-of-date addons" option, so this
  edition loads only while its interface version matches the live patch (120105 =
  12.1.5). A new retail patch needs a new BuffRadar build with the updated number.
- **Show / hide in combat:** the game doesn't allow it, so the keybind applies the
  change as soon as combat ends.
- **Cast counter:** the session count resets on login or `/reload`. The all-time count
  is shared by all your characters.
- **Earth Shield** can sit on only one other player at a time, so while yours is on a
  tank, BuffRadar doesn't offer it to anyone else — until it's about to run out, when
  it's offered to that same tank again.
- **Languages:** the main window, its tooltips and the minimap tooltips are in German
  on German clients (`Locales\deDE.lua`); the settings window is English for now.
  To add a language, copy that file — it explains how at the top.

## Credits

Casting approach and buff coverage were informed by
[BuffYou](https://www.curseforge.com/wow/addons/buffyou) by datdata (MIT license).
The water droplet sound and the logo were made for BuffRadar.

## License

Copyright © 2026 Malikor.

BuffRadar is free software: you can redistribute it and/or modify it under the terms of
the GNU General Public License as published by the Free Software Foundation, either
version 3 of the License, or (at your option) any later version. See [LICENSE](LICENSE)
for the full text.
