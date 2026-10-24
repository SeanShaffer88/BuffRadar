# Changelog

All notable changes to BuffRadar are listed here. Newest first.

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
