<p align="center"><img src="BuffRadar/Media/logo.png" alt="BuffRadar logo" width="160"></p>

# BuffRadar

[![CI](https://github.com/SeanShaffer88/BuffRadar/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/SeanShaffer88/BuffRadar/actions/workflows/ci.yml)

BuffRadar shows which players need a buff you can cast in **WoW: Forever**
(Interface 16001). Click a name, press your **Cast next buff** key, or use a
macro to work through the list. Your character goes first by default.

## Download and Install

1. Download the Forever ZIP from the [latest GitHub release](https://github.com/SeanShaffer88/BuffRadar/releases/latest)
   or the [CurseForge project](https://www.curseforge.com/wow/addons/buffradar).
2. Extract the `BuffRadar` folder into your Forever client's `Interface/AddOns`
   folder. The installed TOC should be at `Interface/AddOns/BuffRadar/BuffRadar.toc`.
3. Enable BuffRadar in the game's AddOns list.

## Quick Start

- Run `/br plates` to enable friendly nameplates for nearby players outside
  your group. BuffRadar also checks your group, target, and mouseover. Use
  `/br plates names` to keep detection without friendly health bars, or
  `/br plates restore` to undo recorded nameplate changes.
- Click a row to buff its player. Use `/br key` to set keybinds or run
  `/br macro` outside combat to create a cast-next macro for your action bar.
  On a controller, use `/br gamepad` to bind **Cast next buff** directly or
  activate the macro from your action bar.
- Open settings with `/br config`. Run `/br wizard` or Shift-right-click
  the minimap button to choose your activity and role and review a starting
  setup. Use `/br why <name>` for a player's eligibility and assignment.
- Click **?** on the buff window or run `/br nearby` to check friendly
  nameplates, the last scan count, and your current target's eligibility.

## Features

[Live Buff Queue](#live-buff-queue) · [Casting](#casting) ·
[Supported Buffs](#supported-buffs) · [Assignments](#assignments) ·
[Raid Tools and Reports](#raid-tools-and-reports) ·
[Group Coordination](#group-coordination) ·
[Display and Accessibility](#display-and-accessibility) ·
[Profiles and Diagnostics](#profiles-and-diagnostics)

### Live Buff Queue

| Feature | Controls and behavior |
|---|---|
| Discovery and eligibility | Checks group members, target, mouseover, and readable friendly nameplates for buffs you know that fit the recipient. Uses spell range where available and proximity where needed. `/br assumerange` lets you opt into listing players with unknown range. `/br rangewatch` can alert when someone who needs a buff enters range. |
| Safety and pauses | Combat hides and disarms cast rows and excludes targets in combat. Death and ghost state suspend the addon UI. Choose group-only visibility, major-city pauses, battleground and arena pauses, flight-path pauses, PvP skips, and a low-mana threshold with `/br group`, `/br cities`, `/br bg`, `/br taxi`, `/br pvp`, and `/br mana`. |
| Queue order | Check yourself first, prioritize recently resurrected players, and pin one player. Sort by name, tanks and leaders, distance, or most buffs needed. Filter by name or by group role when the client supplies roles. Use `/br self`, `/br pin`, `/br sort`, `/br find`, and `/br filter`. |
| List views | Use `/br view people\|buffs` for a row per player or per needed buff. The buff view shows how many players need each buff. Scroll long lists with the wheel or `/br scroll up\|down`. The cast-next key still uses the head of the full queue. |
| Ignore lists | Right-click a row to save an ignore or Shift-right-click to ignore for this session. Manage entries under **Ignore & Stats** or with `/br ignore`, `/br unignore`, `/br signore`, and `/br unsignore`. Export or import the list with `/br ignorelist export` or `/br ignorelist import`. |
| Scan options | `/br throttle on` adjusts periodic scans to movement, group size, and latency without delaying event refreshes. `/br fastaura` skips rescans when a readable aura change can be identified as unrelated to watched buffs. |

### Casting

- **Four keybinds.** Cast next buff, cast next group buff, show or hide the
  window, and mute or unmute alerts. Open them with `/br key`.
- **Buff and rank selection.** Enable buffs individually, set priority with
  `/br prio`, and set a shared or per-buff rebuff threshold with `/br rebuff`.
  Group equivalents satisfy the same underlying buff. `/br smartprio on`
  can promote eligible buffs for tank or healer roles, wipe recovery, and
  saved instance rules. Manual priority breaks ties. BuffRadar skips spells
  on cooldown and can pick a recipient-eligible rank when the data is available.
- **Cast preview.** Hover a row or the window footer to see the planned cast.
  The next-cast tooltip can show the target, spell rank, fallback reason,
  and known group-blocker count.
- **Group versions.** Set the minimum need for automatic group-cast offers
  with `/br groupcast`. Enable Shift-click with `/br modclick` and register
  your own spells with `/br grouppair "Single" "Group"`. BuffRadar falls
  back to a single-target cast when group eligibility or known reagent
  availability blocks the group cast.
- **Cast controls.** `/br mode` selects target, spell ID, macro, or ranked
  macro mode. `/br clickreg` chooses when clicks fire. If BuffRadar can tie
  a line-of-sight failure to its cast, it skips that target temporarily so
  the next cast can move on.

### Supported Buffs

The Buffs tab shows spells your character knows. These are the built-in
families. Use `/br buffs` for buff keys, `/br toggle <key>` to change a
toggle, and `/br context` to restrict a buff to raids or instances. Use
`/br custom add <spell ID>`, `/br custom remove <spell ID>`, and
`/br custom list` to manage custom watched buffs for the current character.

| Class | Enabled by Default | Optional |
|---|---|---|
| Druid | Mark of the Wild / Gift of the Wild, Thorns for melee classes | **Thorns: Any Class Outdoors** extends Thorns to all classes in the open world. Explicit assignments take precedence. |
| Priest | Power Word: Fortitude / Prayer of Fortitude, Divine Spirit / Prayer of Spirit for mana users, Fear Ward for warriors, Inner Fire, Shadowguard | Shadow Protection / Prayer of Shadow Protection |
| Mage | Arcane Intellect / Arcane Brilliance for mana users, Molten / Mage / Ice / Frost Armor | Dampen Magic, Amplify Magic |
| Paladin | One blessing per class. Kings when known, with Might for warriors and rogues and Wisdom for other classes as defaults when Kings is unavailable. | Aura watch |
| Shaman | Water Shield or Lightning Shield | Earth Shield for warriors, Water Breathing |
| Warlock | Fel Armor, Demon Armor, or Demon Skin | Unending Breath, Detect Invisibility and its Greater and Lesser variants |
| Hunter | | Aspect watch |

The Paladin planner supports Might, Wisdom, Kings, Salvation, Light, and
Sanctuary, including their learned Greater versions. Enable the Paladin
aura and Hunter aspect reminders with `/br aura`.

### Assignments

- **Blessings by Class.** Set your preferences with
  `/br bless prefer <class> <blessing|DEFAULT>`. An active group plan takes
  precedence over personal class preferences. Use
  `/br bless player <target|name> <blessing|DEFAULT>` for a normal blessing
  exception in your current group, subject to the plan's caster ownership.
  Enable **Complement Nearby Blessings** with `/br bless complement on` to
  offer a different known blessing outside your group when another Paladin
  already provides your preferred one. Explicit rules take precedence.
- **Class & Role Assignments.** Enable the table in **Settings → Buffs** or
  with `/br buffassign on`. It uses the class and known group role, or
  the class's **World** cell when the role is unavailable or the player is
  outside your group. Unset cells fall back to **All**, then the normal
  rules. Choose **None** to skip managed targeted buffs or **Default** to
  restore inheritance. Named profiles can save and share the table.
- **Preview Current Group.** Use `/br buffassign preview` to see each
  member's effective rule, available casts, and group blockers. Set a
  session role override when the game has supplied no role. The override
  clears when the player leaves or the UI reloads. `/br why <name>` shows
  the deciding rule and any role override.
- **Review blocker edits.** See which players and rules block a group cast,
  with incomplete roster information flagged. **Edit Rule** opens the
  exact assignment cell or blessing exception. **Review Changes** shows
  who would gain or lose buff offers, and **Apply** rechecks the roster
  and refreshes the blockers. `/br practice` uses a sample roster.
  `/br undo` reverses the last eligible blocker edit in the same session.

### Raid Tools and Reports

| Feature | Controls and behavior |
|---|---|
| Raid Coverage | `/br coverage` opens a read-only report of confirmed, missing, and unknown buffs by subgroup. Select a buff to drill down to the affected players. |
| Raid Preparation | Open the read-only checklist from **Raid Coverage** or use `/br prep`. Expand a player for missing and expiring buffs, consumable checks, and unknown readings. **Reagents** compares carried quantities with estimated needs and flags shortfalls. Roster changes refresh the open checklist and preserve expansion for a player still present. Open **Personal** with `/br readiness`, even solo, for food, flask, an optional consumable aura, carried Healthstones, durability, and applicable weapon and pet checks. |
| Subgroup Responsibilities | Open from **Raid Coverage** or `/br subgroup panel`. Restrict a buff to selected raid groups, preview the affected roster, and see why a group cast may fall back to a single-target cast. For example, `/br subgroup FORTITUDE 1,2` assigns groups 1 and 2. Set **All** or **None** as needed. Rules clear when you leave the raid or reload. |
| Ready Checks | `/br ready show` lists player responses, missing and expiring buffs, unknowns, and estimated group reagents. `/br readypost` lets leaders and assistants enable automatic group-chat summaries. |
| Recaps and sharing | Get a death recap or post-wipe rebuff report and reprint them with `/br death show` and `/br wipe show`. Use `/br summary` for needs by buff, `/br announce` for party or raid chat, and `/br discord` for copyable Markdown. |
| Coverage line | Pick visible parts with `/br cover` including progress, buffs and cooldowns, the active or away BuffRadar roster, group expiry, world buffs, drinking healers, and session uptime. `/br uptime` reports the share of grouped scans that found every checked player buffed. |
| Encounter debuffs | In Settings → **Readiness**, or with `/br debuff add <spell ID> [player\|focus] [encounter ID]` and `/br debuff on`, show readable auras and their stacks in a separate strip. An encounter ID restricts a rule to that fight. |
| Extras to watch | Read flask and food counts for Forever, see your temporary weapon enchant, and track your focus target's buff needs, world buff timers, or drinking healers. Watch group pets for Fortitude, Mark of the Wild, and Arcane Intellect. Use `/br consumables`, `/br weapon`, `/br focus`, `/br worldbuff`, `/br drink`, or `/br pets`. |

### Group Coordination

- **Caster Coordination.** Open from **Class & Role Assignments** or with
  `/br coordinate panel`, enable cast sync, and opt in for the group.
  Leaders and assistants can request reports of known spells, build and
  review a draft, publish duties, and track acknowledgements. Casters can
  review, accept, or decline an incoming plan. Acknowledgements are shown
  separately from buff coverage. Plans clear when the roster or leadership
  changes. Run `/br coordinate` for the available commands.
- **Cast sync and handoff.** `/br sync` shares successful cast status with
  other BuffRadar users in the group. `/br assign` lets leaders and
  assistants assign casters to buffs. Leaders, assistants, and Paladins can use
  `/br bless <class> <blessing> [caster]` to share a class blessing plan
  with optional ownership. `/br buddy` splits
  queues between active casters. Cover-me handoff redistributes duties
  when a participating caster dies or goes AFK.
- **Requests and reminders.** Tag eligible players who ask for buffs in
  nearby chat or whispers, print a joining-group digest, tag the next row
  after a cast, and remind yourself when you enter an instance unbuffed.
  Use `/br requests`, `/br digest`, and `/br enterflash` or open
  **Settings → Behavior**.
- **Alerts.** Choose droplet, system sound, or silence for new names,
  single-target buff drops, requests, and post-combat alerts for buffs that
  fell off during the fight.
  Test and silence alerts in instances from the **Alerts** tab. The
  window can flash after combat or for a supported pull countdown.
  See `/br soundfor`, `/br watch`, `/br fallsound`, and `/br pullflash`.
- **Expiry forecasts.** `/br forecast 60` warns about confirmed expirations
  within 60 seconds. A supported pull timer extends the window to include the
  countdown plus the lead time; `/br forecast timer 30` sets a local deadline.
  Use `/br forecast off` to disable notices. Forecasts do not infer boss
  mechanics or arm casts earlier than `/br rebuff` allows.

### Display and Accessibility

- **Window layout.** Drag, lock, resize from the bottom corners, reset
  position or appearance, and set width, list scale, or settings scale
  independently. Save position per character and scale per specialization.
  Move the window through the game's Edit Mode when the client exposes it.
  Hold Shift to snap while resizing when enabled. Click-through while
  locked, idle fade, an all-buffed pill with click-to-peek, and empty-list
  hiding are optional. Hover to show the close button. Hiding the title
  frees the header space.
- **Rows and styling.** Choose compact rows, two columns, upward growth,
  text size, row spacing, and icon size. Customize background color,
  opacity, border, and themes. Choose a built-in palette or save up to four
  custom themes. Select **Auto** to match a loaded UI addon, then open
  **Auto Theme Priority** on the Window tab to reorder matches and see the
  selected addon. Show class colors, realm names,
  raid markers, duration bars, or colored marks for tanks, assignments,
  expiry, and the buddy split. Trim long names and select minimal,
  standard, or full tooltips with buff durations where available.
- **Quick controls.** Toggle known buffs from the icon strip, add a name
  finder to the list, and show or hide the cast counter. Open settings
  from the gear icon, the movable minimap button, the add-on menu
  where available, or `/br config`. The minimap marks confirmed coverage
  green (`+`), ordinary needs yellow (`!`), critical needs red (`!!`), and
  unknown coverage gray (`?`). A paused scan has no mark. `/br visual on`
  adds quiet highlights independently of sound and respects Reduced Motion.
- **Accessible settings.** Search the active tab with `/br config find`. Use
  `/br config navigate` for keyboard controls or `/br config narrate`
  for the game's configured text-to-speech voice. Tab or Shift+Tab moves,
  Enter or Space activates, arrow keys adjust, F1 toggles speech, and
  Escape exits navigation. The color picker, keybind prompt, setup wizard,
  and profile share dialogs have their own controls. Enable status symbols
  with `/br tagsymbols` and reduced motion with `/br motion`.
- **Languages.** English and German text are bundled, along with partial
  French, Spanish, Russian, and Simplified Chinese translations.

### Profiles and Diagnostics

| Feature | Controls and behavior |
|---|---|
| Presets and specialization | Quick Setup drafts a preset and alert preferences based on your activity and role. It applies them only on confirmation. Standalone presets are available through `/br preset`. Buff toggles and rebuff overrides can follow the active specialization when the client identifies it. |
| Named profiles | Save, load, list, delete, and share profiles from **Ignore & Stats** or `/br profile`. Preview a saved profile's differences with `/br profile diff <name>`. `/br autoprofile` can switch profiles for raids, dungeons, battlegrounds, grouped world play, or solo play. |
| Import and export | Use `/br export` and `/br import` for settings strings and `/br diff <string>` to preview them. Share the Class & Role Assignments table with `/br profile share` and `/br profile import`. A shared profile can replace a saved profile of the same name and is applied when loaded. Use `/br plan export` and `/br plan import` to transfer and merge group buff assignments, the blessing plan, and auto-profile mappings. |
| Casts and history | Show session and all-time totals, reset counters, see per-spell stats or export them, and review the last 50 tracked casts. See `/br count`, `/br resetcount`, `/br stats`, and `/br history`. `/br offenders` tracks players seen unbuffed across group sessions. |
| Troubleshooting | `/br why <name>` explains how a player is handled. `/br debug` reports client and window state, `/br clicks` logs cast attempts, `/br selftest` prints a report for bug reports, `/br apicheck export` produces a copyable API report, `/br buffcheck` checks spell IDs, and `/br perf` reports scan timings when available. `/br stats memory` reports the game's addon total, not per-feature estimates. `/br lite on` pauses forecasts, readiness, debuffs, and optional watches without changing their saved settings. |
| UI integration and feedback | Use the [read-only status API](docs/STATUS_API.md) or `/br status export`. Get a copyable feature-request link with `/br feedback` or see the [roadmap](docs/ROADMAP.md). |

## Player Guides

Find supported buffs, settings, and commands in the
[Forever Player Guide](editions/forever/README.md). Review release details in
the [Changelog](editions/forever/CHANGELOG.md).

BuffRadar has targeted Forever since 1.8.0. The last Retail release was
1.7.0. See the [Retail Guide](BuffRadar/README.md) and
[Support Decision](docs/DECISIONS.md#2026-10-25--retail-support-dropped-forever-only-from-180-sean).

## Screenshots

**BuffRadar list**

![BuffRadar list showing nearby players who need buffs.](editions/forever/screenshots/buffradar-forever-list.png)

**BuffRadar settings**

![BuffRadar settings window with appearance and behavior options.](editions/forever/screenshots/buffradar-forever-settings.png)

## Source and Contributions

The [Forever TOC](editions/forever/BuffRadar.toc) and the historical
[Retail TOC](BuffRadar/BuffRadar.toc) load a shared Lua 5.1 implementation:

- [Data](BuffRadar/Data.lua) initializes the addon namespace. [SavedVariables](BuffRadar/SavedVariables.lua)
  validates and migrates `BuffRadarDB` on load; [Profiles](BuffRadar/Profiles.lua)
  handles settings and plan imports and exports.
- [Core](BuffRadar/BuffRadar.lua) scans and builds the cast queue.
  [Intelligence](BuffRadar/Intelligence.lua) owns scan cadence, forecasts and
  contextual priority. [Status](BuffRadar/Status.lua) publishes copies;
  [Debuffs](BuffRadar/Debuffs.lua) and [Readiness](BuffRadar/Readiness.lua)
  own optional aura and inventory checks.
  [Coordination](BuffRadar/Coordination.lua) handles group messages and plans.
- [Window](BuffRadar/Window.lua) owns the main window and secure buttons.
  [Minimap](BuffRadar/Minimap.lua) owns the minimap and addon menu.
  [Config](BuffRadar/Config.lua), [Wizard](BuffRadar/Wizard.lua), and
  [Slash](BuffRadar/Slash.lua) handle settings, setup, and commands.

- [Report a bug or request a feature](https://github.com/SeanShaffer88/BuffRadar/issues/new/choose).
  Use the [security policy](SECURITY.md) for private reports.
- [Contributing](CONTRIBUTING.md) and [local checks](tools/README.md).

## Repository Layout

| Path | What it is |
|---|---|
| `BuffRadar/` | Shared addon source, translations, art, bindings, and historical Retail files |
| `editions/forever/` | The Forever edition's `.toc`, README and changelog |
| `build.ps1` | Packages the supported Forever edition and SHA-256 checksum with PowerShell 7 |
| `tools/` | Automated checks — see [tools/README.md](tools/README.md) |
| `.luacheckrc` | luacheck settings used by the checks |
| `AGENTS.md` | Project rule sheet (prompt in force, frozen foundation, gate) |
| `QUALITY.md` | Quality scorecard, scored from evidence |
| `docs/` | Capability matrix, decision log, status API, and roadmap |
| `SECURITY.md` | How to report a security problem, privately |

## Making a Release

```powershell
.\tools\check.ps1 -Setup   # first time only
.\tools\check.ps1          # luacheck, Lua 5.1 compile and limits, translations, trial run
.\build.ps1                # Forever ZIP and SHA256SUMS.txt in dist\
```

Then test the Forever zip in the game. The zip holds a `BuffRadar` folder that goes in
`Interface\AddOns`.

## License

Copyright © 2026 Malikor. BuffRadar is free software under the GNU General Public
License, version 3 or (at your option) any later version — see [LICENSE](LICENSE).
