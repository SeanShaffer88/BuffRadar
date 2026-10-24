# Changelog

All notable changes to BuffRadar are listed here. Newest first.

## 1.3.2 — 2026-10-23 — Retail edition

- **Earth Shield is offered to one tank at a time.** It can sit on only one
  other player, so with two tanks around, one always showed as missing it.
  While yours is on a tank, no one else is offered it; when it's about to
  run out, only that tank is. (Skyfury was checked too: it can be given to
  players outside your group, so it stays as it is.)
- **Out-of-range rows are marked,** with *out of range* under the greyed
  name, so the state doesn't rely on color alone. Fixed alongside: a
  player who came back into range kept the grey name.
- **German translation** of the main window, its tooltips and the minimap
  tooltips (`Locales\deDE.lua`), which is also the template for other
  languages.
- **One source for both editions.** The retail and Forever editions are now
  built from the same `BuffRadar.lua`, which picks its buff set and class
  tables when it loads (from the client's interface version). Fixes and
  features land in both at once; each zip differs only in its `.toc` and docs.

- **Fix: Battle Shout and Blessing of the Bronze no longer list strangers.**
  Both only reach you and your party or raid, but players outside the group
  (seen through nameplates, target or mouseover) were still listed as
  needing them — forever, since casting could never reach them. After the
  group was buffed, the *Cast next buff* key stayed stuck on a stranger and
  recast the buff every time its cooldown ended. These two buffs are now
  offered only to you and your group members; the settings window labels
  them "you & your group".
- **Tanks are recognised by their group role.** Earth Shield's "tanks" and
  the *role* sort order used to go by class, so every death knight, monk
  and demon hunter counted as a tank — damage dealers included. Group
  members now count as tanks by the role they picked (role check or
  dungeon finder); a raid's main-tank/main-assist flag still counts for
  sorting too. Players with no assigned role (strangers, or groups without
  a role check) fall back to the old class rule for Earth Shield.
- **Buffing group members no longer changes your target.** Every cast on
  another player used to target them by name, cast, then switch back to
  your previous target — a visible target flicker that also disturbed
  target history. Party and raid members are now cast on directly; the
  target-swap remains only for players outside your group.
- **Rebuff timing in the settings window.** The Buffs tab has a seconds
  box next to each buff (empty = use the all-buffs time) and one for the
  all-buffs time, so `/br rebuff` is no longer the only way to set them.
  Checkbox labels are now clickable, not just the box.
- **Sturdier with protected game values.** When the game hands BuffRadar
  a protected ("secret") player name, ID, class or level, it no longer
  risks an error: such a name is still shown but not used for sorting,
  a player whose ID is protected is skipped, and the cast counter and
  `/br clicks` output ignore protected values. Before, one protected name
  could break the list ("attempt to compare").
- **More of the window can be translated.** The window's combat label,
  "+N more", cast counter, row tooltips and the gear, resize-grip,
  minimap-button and addon-menu tooltips now go through the translation
  table too; anything a translation leaves out stays in English.
- **Settings window in the standard game style.** It now uses the game's
  own window frame — title bar, close button, the BuffRadar icon in the
  corner — with the five sections as tabs along the bottom edge, like the
  character window. A client without those parts gets the previous look.
- **Less work in busy places.** Aura changes on units BuffRadar never
  lists (enemy and NPC nameplates, pets, bosses, arena opponents) no
  longer trigger a list update, and nothing is rescanned during combat,
  when the list is frozen anyway — it catches up as combat ends. The
  steady 0.4-second rescan rests while scanning is paused (major city,
  battleground) or you know no supported buffs; zone changes, learning a
  spell and settings changes still update right away. The spell-rank
  table, which only the Forever edition uses, is no longer built.
- **BuffRadar in the game's options.** Esc > Options > AddOns now lists
  BuffRadar, with a button that opens its settings window.
- **Addon menu entry works like the minimap button.** In the minimap's
  addon menu, left-click BuffRadar to show or hide the window and
  right-click it for settings (it used to open settings on any click);
  hovering it shows a tooltip.
- **Fix: right-clicking the minimap button opens settings,** as its
  tooltip always said. The button only listened to left clicks.
- **Hover help on every setting.** Each checkbox, button, slider and
  dropdown in the settings window shows a short explanation when you
  hover it.
- **Fix: right-clicking a row no longer casts.** A row's cast applied to
  every mouse button, so right-clicking someone to ignore them also buffed
  them (and counted the cast). Right-click now only ignores.
- **Ignore list: realm-aware, any capitalization, removable one by one.**
  Right-clicking a row now ignores that player as *Name-Realm*, so a
  player with the same name on another realm is no longer hidden too.
  `/br ignore` and `/br unignore` no longer care about capitals or spaces
  (`/br ignore bob` matches Bob); a plain name ignores it on every realm,
  and `/br unignore <name>` clears that name on every realm. The Ignore &
  Stats tab lists ignored players with a remove button next to each (up
  to 12 shown; `/br ignorelist` lists all). Names ignored by older
  versions keep working as "every realm" entries, and duplicates that
  differ only in capitals are merged; the saved format is unchanged.
- **Settings that did nothing on retail are gone.** The Behavior tab's
  "Offer group buffs" option and its threshold slider are hidden (retail
  has no group versions of buffs; one cast already covers the group), and
  the rest of that column moves up. `/br groupcast` explains this instead
  of changing a setting that had no effect, `/br mode` offers only
  `target` and `macro` (the `id` and `rank` modes pick spell ranks, which
  retail doesn't have), and the `BLESSINGS` key is no longer accepted by
  `/br toggle` or `/br rebuff`. A saved `id`/`rank` mode switches back to
  the default `target`. The Forever-only code stays in place, switched
  off, so the two editions remain one codebase apart.
- **Resizable window.** Drag the list window's bottom-right corner to make
  it wider (up to 400) or narrower (down to 180), so long names stop being
  cut off. The height still follows the list, and the top edge stays put.
  The grip hides while the window is locked (`/br lock`) and does nothing
  in combat, when the game doesn't allow resizing. Reset look restores the
  default width.
- **Scale dropdowns.** The list window's scale slider is now a dropdown of
  presets (50%–200%), and the settings window has its own scale dropdown,
  both on the Window tab. `/br scale` still takes any value from 0.5 to 2
  (shown as "Custom" in the dropdown). Changing the list window's scale in
  combat is now refused with a message instead of being blocked by the game.

## 1.3.1 — 2026-10-22 — Retail edition

- **Fix: the window no longer moves as names are added and removed** (the
  same fix as Forever edition 1.2.4). The list's height changes with every
  name, but the window was anchored by its left edge (or by whatever
  point a drag left it on), so growing and shrinking happened around that
  anchor and the whole window — top edge included — jumped up and down.
  The window is now anchored by its top-left corner only: the top edge
  stays exactly where you put it and the list grows and shrinks downward.
  Positions saved by older versions are converted automatically on first
  load; a position saved mid-drag by an older version may shift slightly
  that one time, because the old save didn't record the window's height.

## 1.3.0 — 2026-10-22 — Retail edition

First retail release, ported from the Forever edition (which continues as
1.2.3, interface 16001). Targets retail patch 12.1.5, interface 120105 —
Midnight no longer offers "load out-of-date addons", so the number must
match the live patch exactly.

- **Buff set rebuilt for retail,** following Blizzard's own list of
  player-cast long-term raid buffs: Arcane Intellect, Power Word:
  Fortitude and Mark of the Wild carry over; **Battle Shout** (warrior),
  **Skyfury** (shaman) and **Blessing of the Bronze** (evoker) are new —
  on Forever those classes had nothing to give. Retail raid buffs apply
  to the whole group when cast on one member, so rows clear in bunches.
  Source of Magic and Symbiotic Relationship are excluded on purpose:
  each can sit on only one player per caster, so everyone else would
  list as missing forever. Everything retail removed (paladin blessings,
  mage armors, Divine Spirit, Fear Ward, Inner Fire, group-cast versions
  like Prayer of Fortitude) is out of the table.
- **All thirteen classes recognised.** The Forever edition knew nine;
  death knights, monks, demon hunters and evokers would never have been
  listed as needing buffs. Arcane Intellect's "mana users" list is
  retail-correct too: hunters (focus) drop off, evokers and monks join.
- **Retail spell IDs** where they differ (Water Shield 52127), and
  Dornogal joins the major-city pause list alongside Silvermoon.
- Includes the 1.2.3 fixes below (Kings priority; nameplates-off login
  warning, honest empty state and `/br debug` nameplate diagnostics;
  mouseover discovery). The blessing tables remain in the code,
  inert on retail, so the two editions stay one codebase apart.

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
