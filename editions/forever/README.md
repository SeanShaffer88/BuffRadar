<p align="center"><img src="Media/logo.png" alt="BuffRadar logo" width="160"></p>

# BuffRadar

**A click-to-buff list for World of Warcraft Forever.**

BuffRadar shows a small window listing every nearby player who is missing one of *your*
buffs — with their portrait, class-colored name and icons of what they still need.
Click a name to buff them. Press one key (or one macro) to buff the next person.
You always come first.

Version 1.4.0 · Interface 16001 · License: GPLv3 (1.2.4 was last verified on Forever beta build 1.60.1.70450)

The Forever and retail editions are built from the same source; this zip's `.toc`
targets the Forever client, and BuffRadar picks the Forever buff set when it loads.

---

**Docs:** [Features](FEATURES.md) · [Description](DESCRIPTION.md) · [Changelog](CHANGELOG.md)

## Features

- **Live list of who needs what.** Players stay listed until every buff you can cast
  that suits their class has been applied, then drop off.
- **The list grows downward.** The window is anchored by its top-left corner, so
  its top edge stays exactly where you put it as names come and go — only the
  bottom edge moves.
- **You first.** Your own character is always checked first and sits at the top of the
  list whenever you're missing something.
- **Class-aware.** Arcane Intellect only goes to mana users, Thorns to melee classes,
  Fear Ward to warriors, and so on. Paladins give each class one fitting blessing.
- **One-key buffing.** Bind *Cast next buff* or use the BuffRadar macro to work through
  the list without clicking.
- **Highest rank.** Buffs are cast by name, so your highest known rank is always used.
- **Smart checks.** Group versions (Arcane Brilliance, Prayer of Fortitude, Gift of the
  Wild, Greater Blessings) count as "already buffed". Buffs about to expire are offered
  again. Spells on cooldown are skipped.
- **Water droplet alert** when someone new appears (optional, with a mute keybind;
  a system sound or silence can be chosen instead, and alerts can stay quiet in
  instances).
- **Group-cast offers:** when enough of your party or raid needs the same buff,
  BuffRadar offers the group version (Prayer of Fortitude, Gift of the Wild…)
  instead — one cast for everyone.
- **Out-of-range players** can stay listed, greyed and marked *out of range*, so you
  see who's coming into range. **Right-click a row** to ignore a player who doesn't
  want buffs.
- **Role ordering** option: you, tanks and leaders first.
- **Rezzed players first** (after you): someone who just came back from the dead
  has lost every buff, so their row jumps up with a *recently rezzed* marker.
- **Row markers:** *a buff just expired* when a buff vanishes outright, and
  *~4m left* on a buff inside its rebuff window.
- **Coverage line** while grouped: how many members are fully buffed, and
  per-buff coverage — also your progress while buffing a fresh group.
- **Session-only ignore:** Shift-right-click a row to ignore someone until
  you log out (nothing saved).
- **`/br announce`** posts the group's missing buffs to party/raid chat, and
  a ready check prints you a local summary.
- **Low-mana pause** (optional): listing pauses while your mana is under a
  percentage you set.
- **Distance ordering** option: nearest first.
- **Settings export/import:** copy nearly all settings between characters
  as one string (`/br export`, `/br import`).
- **Compact rows** without portraits, a separate list text size, and a
  per-character window position option.
- **Post-combat flash:** the border pulses once when combat ends with
  buffs still missing.
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
| Druid   | Mark of the Wild (everyone), Thorns (melee) | — |
| Priest  | Power Word: Fortitude (everyone), Divine Spirit (mana users), Fear Ward (warriors), Inner Fire (you) | Shadow Protection |
| Mage    | Arcane Intellect (mana users), Molten / Mage / Ice / Frost Armor (you) | Dampen Magic, Amplify Magic |
| Paladin | One blessing per class: Kings for everyone if you know it; otherwise Might for warriors and rogues, Wisdom for everyone else | — |
| Warlock | Fel / Demon Armor or Demon Skin (you) | Unending Breath, Detect Invisibility |
| Shaman  | Water or Lightning Shield (you) | Earth Shield, Water Breathing |

Warriors, rogues and hunters have no buffs for others, so the window stays hidden on
those characters.

## Installation

1. Download and unzip.
2. Move the `BuffRadar` folder into your Forever `Interface\AddOns` folder, so the path
   is `Interface\AddOns\BuffRadar\BuffRadar.toc`.
3. Restart the game (a `/reload` is not enough the first time).
4. **Turn on friendly nameplates** (Shift+V, or `/br plates`). The game only lets addons
   see nearby players outside your group through their nameplates.

## Using it

| Action | How |
|---|---|
| Buff someone | Click their name in the window |
| Buff the next person | Your *Cast next buff* key, or the BuffRadar macro |
| Settings | Gear icon in the bottom-left corner, right-click the minimap button or the addon menu entry, Esc > Options > AddOns > BuffRadar (on clients that list addon options), or `/br config` — hover any setting for a short explanation |
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
| `/br groupcast [on\|off\|<n>]` | Offer group buff versions when n+ group members need the same buff |
| `/br sort name\|role\|distance` | List order: name, tanks & leaders first, or nearest first |
| `/br ignore <name>` · `/br unignore <name>` · `/br ignorelist` | Manage the ignore list (or right-click a row; remove names on the Ignore & Stats tab). Capitals don't matter; `Name-Realm` means that one player, a plain `Name` means that name on every realm |
| `/br alertsound droplet\|system\|none` | Choose the new-name alert sound |
| `/br announce` | Post the group's missing buffs to party/raid chat |
| `/br signore <name>` · `/br unsignore <name>` | Ignore a player for this session only (or Shift-right-click a row) |
| `/br mana <0-100>` | Pause listing below this mana % (0 = off) |
| `/br export` · `/br import` | Copy settings between characters as one string |
| `/br compact` · `/br text <0.8-1.5>` · `/br charpoint` | Half-height rows · list text size · per-character window position |
| `/br selftest` | Print a paste-able block for bug reports |
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
  The Exodar, Silvermoon and Shattrath. If a city isn't detected, `/br debug` shows the
  zone and map ID BuffRadar sees.
- **Show / hide in combat:** the game doesn't allow it, so the keybind applies the
  change as soon as combat ends.
- **Cast counter:** the session count resets on login or `/reload`. The all-time count
  is shared by all your characters.
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
