# BuffRadar Forever in-game release checklist

Run this against the exact candidate ZIP after CI passes. Record the version, client build, tester, and pass/fail for each check. Do not mark a build field-tested until the applicable checks pass.

## Macro after relog

- Put the BuffRadar macro on an action bar, log out fully, and log back in.
  Without remaking it, check that pressing it buffs the next player in the
  list, including a nearby player shown only by nameplate, not just you.
- Open the macro editor and check that the text follows the next player as
  the list changes. A macro you edited by hand must stay as you wrote it.

## 1.16.0 Audit Follow-up

Use the [1.16.0 verification matrix](FOREVER_1.16.0_VALIDATION.md) to identify
and check the ZIP. Run its field scenarios plus the applicable readiness and
general checks below. Use a backed-up
SavedVariables file and disposable test settings for downgrade and cap checks.
An offline pass does not verify rendering, protected actions, or delivery.

## 1.16.1 Rapid macro retries

Result: **Unverified in game**. Use the exact 1.16.1 Forever ZIP.

- Enable `/br clicks`. Cast through the managed action-bar macro, then retry
  the same target and spell quickly enough for Forever to report `SENT` after
  the click. A successful cast should update the counter and history once.
- Repeat with a different target before the first cast is correlated. The
  ambiguous cast must not be credited to the wrong player.
- Press again while the spell is not ready. Confirm the game may show its
  cooldown message and BuffRadar keeps the target queued until a cast succeeds.

## 1.15.37 Readiness

Result: **Unverified in game**. Use the 1.15.37 Forever ZIP.

- Open Quick Setup with `/br wizard` and Shift-right-click on the minimap.
  Select Raid and Tank. Go Back or close without applying; reopen and finish.
  Only Apply should change settings, and buff toggles and bindings must survive.
- Set a forecast lead longer than the rebuff window. Watch a readable timed
  buff with no cast offer. Start, replace and cancel a native pull countdown
  while coverage is still active; test a longer equivalent aura and a local
  timer. No forecast should create a cast or persist into combat as current.
- Enable smart priority with assigned tank/healer roles. Try a real wipe and an
  instance rule in two different zones. Confirm priorities respect assignments,
  range, spell knowledge and cooldowns and that off restores manual behavior.
- Watch a known player/focus debuff. Test stacks, focus replacement, scoped
  encounters, unreadable combat auras, death, and Lite mode. Check that the
  separate strip never interrupts Cast Next Buff.
- Open `/br readiness` solo and in a group. Move a Healthstone in or out of
  bags; try damaged equipment, a temporary coating and a configured consumable
  aura. Confirm event updates, unknown labels, and the existing group and
  reagent tabs. Enable Lite and turn it back off without losing settings.
- Verify minimap symbols, a pulse with sound muted, and suppression with Reduced
  Motion. Verify Readiness keyboard navigation and German labels. Copy Feedback;
  it must not open a browser or submit data by itself.
- Read status from an integration after a scan, entering combat, and changing
  a nameplate token's target. Record `/br perf` and `/br stats memory` at rest
  and moving in a raid; an aura event must still refresh promptly.

## 1.15.35 Nearby casting, controller input, blessings, and nameplates

Result: **Unverified in game**. Run against the candidate ZIP, not a loose copy.

- **Save and window compatibility:** Upgrade with an existing `BuffRadarDB`, a
  saved profile, and per-character positions. Reload and check that the profile,
  window position, minimap button, and settings persist. `/br reset` and
  `/br resetpos` should reset only the current window position. On leaving
  combat, check that deferred scale and theme changes apply, the border flash
  returns to the normal colour, and the rows and both cast bindings rearm.
- **Existing and new macros:** Upgrade with the old BuffRadar-generated macro
  already on a bar; it should update in place. Try both key-down and key-up
  settings. With your own buff missing and an ungrouped player on the list,
  the macro should buff you once and then the other player, including a
  player with a surname. Test `/br macro` on a fresh install too.
- **Target safety:** Test with a friendly target selected, and again with no
  target. After buffing a nearby player your previous target state should
  return. If the exact player has left, the cast must not land on the old
  target or yourself. Try a party member, combat, death, and a loading
  screen. The macro must never cast during combat. Inspect `/br history` and
  the counter after successful and failed attempts.
- **Controller:** On the standard gamepad, bind **Cast next buff** via
  `/br gamepad` and press it without pointing to a row. Repeat using the
  managed action-bar macro. Check one cast per press and that toggling the
  game's key-down setting doesn't break the native binding.
- **Blessings:** On a Paladin who knows Kings and a class-appropriate
  alternate, test on a nearby player outside your group who has another
  Paladin's Kings (then Greater Kings). With the option off, no alternate
  should appear. With it on, cast the alternate and check that the queue
  does not cycle to a third blessing. Repeat using your own Kings, then with
  a group plan or explicit World assignment; the opt-in must not override them.
- **Nameplates:** Note your game settings before using `/br plates` and
  `/br plates names`. Make sure the friendly health bar disappears but the
  nearby player remains discoverable. Turn plates off, then target or mouse
  over the same player; these sources should still work. Change settings
  again, reload, and use **Restore Nameplates** or `/br plates restore` to
  confirm the recorded values (including Always Show, if changed) return.
  Check that enemy and personal nameplate preferences stay untouched.

## 1.15.34 File split (Slices E, F and G) and row hover highlight

Code moved into `Coordination.lua`, `Wizard.lua` and `Window.lua`; nothing should look or
behave differently. Check that both files load (no Lua error at login, and
`/br selftest` runs) and then:

- **Coordination.lua:** with a second BuffRadar user in the group and cast
  sync on, buff a player and check that their row clears on the other
  client. Whisper yourself "buff" from a listed player and check that the row
  is marked and the alert sound plays once. Join a group with buffs missing
  and check the join digest line. Open Caster Coordination and request reports.
- **Wizard.lua:** run `/br wizard` through all three pages. Save, apply and
  delete a theme. Run `/br why <name>` on a nearby player and open the
  Nearby Player panel with **?**. Check `/br history`, `/br stats` and an
  export dialog. With alerts on, check that the window border flashes.
- **Window.lua (secure cast path, test this first):** with `/br clicks` on,
  buff from a row click, the Cast Next Buff key and Shift-click / the group
  key. Check each cast lands on the displayed player and the counter moves
  once. Enter and leave combat: rows and both buttons disarm and rebind.
  Toggle a buff on the strip, use a role chip, let the window idle-fade,
  drag the scale grips and edges, and close the window with its button (it
  stays hidden until reopened). Run `/reload` and check the window returns
  where it was.
- **Row hover highlight:** move the mouse over names in the list. Each row
  should light with a faint wash in the theme's border colour (no yellow
  glow), and only while the mouse is on it. Switch theme, including Auto
  with a UI suite loaded, and check the wash follows. With click-through
  on and the window locked, rows should not highlight.

## 1.15.33 Input hardening

Result: **passed** — SEAN, reported 2026-11-16 (client build not recorded).

- Run `/br ignore |cffff0000Red|r` and check that it is refused. Run
  `/br ignore` with a plain name and check that it is added.
- Import an ignore-list string over 16 KiB and check that it is refused with
  nothing added. Import a normal `BRI1;` string and check that it works.
- In a 5-player group and a raid, check that the list still fills and
  updates as normal while you buff, including pets and the tooltip.
- With friendly nameplates on, stand near an ungrouped player who already
  has one of your buffs and run `/br why <name>`. The buff must read as
  present or unverified, never as missing (a restricted aura read must not
  pass as a definitive "absent").

## 1.15.32 Shadowguard watch

Result: **passed** — SEAN, reported 2026-11-16 (client build not recorded).

- On a priest who knows Shadowguard, run `/br buffs` and check that
  `SHADOWGUARD` is listed and on. Let Shadowguard expire and verify you are
  listed as missing it; cast it and verify the row clears.
- Run `/br toggle SHADOWGUARD` and check that the buff stops being watched.
- On a priest who does not know Shadowguard, check that it is not listed.

## 1.15.31 Cast Queue and Wipe Reports

Result: **passed** — SEAN, reported 2026-11-16 (all releases through
1.15.31 pass in game; client build not recorded).

- With both cast-next keybinds configured, test each while replacing a party
  member. Verify the next press after the list refreshes targets the
  displayed player. Try the same with cast-on-key-down and cast-on-key-up.
- Use the name finder to hide a player who needs a buff, then clear it.
  Verify the empty state leaves the buff status undetermined and the
  all-buffed pill stays hidden while known needs remain.
- Enable wipe reports and test a qualifying fight, then `/br wipe show`.
  Verify one automatic recap and a successful manual reprint. A fight
  shorter than eight seconds should generate no automatic recap.

## 1.15.30 Nearby Player Diagnostics

- Turn off friendly nameplates and target a friendly player. Open the panel
  with **?** while a buff row is visible. Check that it reports nameplates
  off, displays the last scan count, and explains the current target.
- Select **Enable Friendly Nameplates**, then confirm the panel reports the
  new setting. Verify that the count reflects the next scan, or select
  **Refresh** to reread the result.
- Switch between a friendly player, an enemy, and no target. Confirm the
  previous target's explanation clears. With the title hidden and the buff
  window narrow, check that the launcher and cast counter remain usable.
- Open with `/br nearby` while the buff window is hidden. Enter combat or die
  with diagnostics open and verify that it closes.

## 1.15.29 Assignment Navigation and Outdoor Thorns

- Open **Settings → Buffs → Class & Role Assignments**. Check that it opens
  the grid and that **Preview Current Group** still opens the preview.
- Edit a cell and close it with **Done**, the top-right close button, and
  Escape outside keyboard-navigation mode. Confirm the grid remains open
  and keeps the saved selections. Cancel a draft opened from a blocker and
  confirm it returns to the blocker list with the original rule.
- On a Druid with Thorns, enable **Thorns: Any Class Outdoors** on the
  Buffs tab. Confirm a nearby Mage who lacks Thorns can be offered it, first
  ungrouped and then in your party. Enter a dungeon with the setting still
  enabled and confirm the default class rules apply. Outside again, set an
  explicit **None** assignment for the Mage and confirm it takes precedence.

## 1.15.28 Raid Preparation

- Open Raid Preparation from Raid Coverage and with `/br prep`. Expand and
  collapse a player, then use the Back button to return to Raid Coverage.
  With keyboard navigation enabled, check that narration reads the row status
  and expanded details.
- Expand a player, then add or remove another member or move someone to a
  different raid subgroup. The checklist should stay open and keep the
  same player's details expanded. Remove the expanded member and check
  that the old details disappear.
- In a group that needs a learned group buff, view Reagents with insufficient
  stock, then replenish stock and use Refresh Preparation. Check that the
  carried count and shortfall update. Try `/br prep personal` and check the
  optional personal reminders. Enter combat or leave the group while the
  checklist is open to verify it closes.

## 1.15.27 Subgroup Responsibilities

- Open the panel with `/br subgroup panel` and from Raid Coverage. Select
  Fortitude and one subgroup. Check the roster preview, then cancel or close
  and confirm `/br subgroup` still shows the previous rule.
- Apply a selection in a raid with someone needing the buff in a selected
  subgroup. Check the displayed fallback reason when the group cast could
  reach an unselected subgroup. Repeat with **All** and **None**.
- Move a member between groups, then confirm the preview follows that player.
  Check that an edit made through the slash command appears in the panel.
- Enter combat and leave the raid with the panel open. Verify the draft
  closes and the applied rule clears on raid exit or UI reload.

## 1.15.26 Caster Coordination Panel

- In a group with cast sync on, open Caster Coordination from Class & Role
  Assignments, then verify `/br coordinate panel` opens the same view.
- Have a leader and caster opt in. Request reports, review a draft, and
  publish it. Verify the caster sees the sender and duties before accepting.
  Check that acknowledgement appears separately from actual buff coverage.
- Replace a group member with a draft or inbox open. Repeat with an unchanged
  roster while the current leader promotes someone else and keeps assistant
  permissions. Confirm the old plan disappears and its controls cannot act.
- Check keyboard navigation and narration in the panel. Enter combat with
  the panel open and verify the panel closes.

## 1.15.24 Review Blocker Edits

- From a blocker, edit an All Roles cell affecting multiple members with
  different roles. Change multiple buff selections in that cell, then
  verify Review Changes lists the affected players and their gained or
  lost buff offers.
- Change a member's role or replace a roster member before Apply. Confirm
  BuffRadar shows the updated impact and requires review again. If the
  original cast target leaves or its rule no longer offers the spell,
  confirm the stale edit is discarded.
- Cancel a draft, then apply an edit and compare the refreshed blocker list
  with the next-cast tooltip. Repeat for a local blessing exception and
  confirm the review works with mouse and keyboard.

## 1.15.23 Edit Blocker Rules

- Open a blocked cast in `/br buffassign preview` and choose **Edit Rule**.
  Verify a role-specific rule opens its cell and an inherited All Roles
  rule opens All Roles. After an edit, confirm the refreshed list and
  next-cast tooltip agree about the remaining blockers.
- Edit or clear a local Paladin blessing exception. Check that unavailable
  roster information and another Paladin's shared duty have no edit action.
- Try the shortcut with keyboard navigation, change the roster while the
  editor is open, and enter combat. Confirm stale actions cannot change
  a replacement player's rule and casting remains disarmed in combat.

## 1.15.22 Group-Cast Blocker Lists

- With reagents available, configure two group members to exclude the same
  group spell. Use `/br buffassign preview` to read both players and their
  rules, then hover the main window footer and confirm the count is two.
- Remove one conflict, then the other. Confirm the count drops and the
  group cast returns after the final conflict clears.
- Repeat with a class-wide Greater Blessing and individual exceptions.
  Verify the same player counts once. When roster details are unavailable,
  verify the UI distinguishes known blockers from incomplete information.

## 1.15.21 Group-Cast Explanations

- With a group buff and its reagent available, make one group member's
  assignment exclude the spell. Run `/br buffassign preview` and hover
  the main window footer. Confirm both identify the blocking player and
  rule, and the prepared cast stays single-target. Change the rule and
  verify the group option returns.
- Repeat with a Paladin's individual blessing exception and a class-wide
  Greater Blessing. Check the explanation identifies the exception.
- If roster data is unavailable, check the explanation describes the
  uncertainty without naming a player the client could not identify.

## 1.15.20 Group Preview Refresh

- Open the group preview on page two or later in a raid. Change an assigned
  role and have someone leave and rejoin if possible. Confirm rows update
  without clicking Refresh Preview and the page stays in bounds.
- Open the role editor and change another member's role. Confirm it still
  refers to the selected player. Have the selected player leave and
  confirm the editor closes instead of pointing to their replacement.
- With two Paladins, verify class-plan ownership, individual exceptions,
  and group-cast fallback. Enter combat during a roster change and
  confirm the preview closes and the cast inputs remain disarmed.

## 1.15.19 Session Role Overrides

- Open `/br buffassign preview` with an unassigned group member. Set Tank,
  Heal, or DPS from their row and compare the effective rule, cast queue,
  and `/br why <name>`. Clear it and verify fallback to World or All Roles.
- Have Forever report a role for that member. Confirm the game role takes
  precedence and that the preview explains the change.
- Have a member leave and another take their roster slot. Confirm the new
  member gets no override and the first member returns without one. Reload
  the UI and confirm any remaining overrides clear.
- Check mouse and keyboard controls. With group reagents available, change
  an override to a role whose rule excludes the spell and verify the
  group action falls back safely. Check Paladin class plans and individual
  exceptions, then confirm combat closes the panel and disarms casting.

## 1.15.18 Assignment Preview

- With a party or raid, open `/br buffassign preview`. Compare each row's
  resolved assignment with `/br why <name>`. Include a known group role,
  an unavailable role, an All fallback, an explicit None and a default.
- With two paladins, compare the preview after setting a class assignment,
  then a normal blessing exception. Check a missing reagent and a group
  cast blocked by another member's rule.
- Change a role, buff or roster member and refresh the preview. Check the
  full roster using keyboard navigation and mouse paging. Confirm the
  preview closes during combat and leaves the cast queue intact.

## 1.15.17 Assignment Table

- Upgrade from 1.15.16. Confirm the table is off and the same eligible players
  and buffs appear. Open Buffs → Class & Role Assignments and enable it.
- Choose different targeted buffs for All, World, and a group role in the
  same class. Verify a known role uses its cell, World handles a nearby
  stranger or unavailable role, and an unset cell uses All before falling
  back to the standard rules. Change a live group role between fights.
- Verify None skips managed targeted buffs and Default restores inheritance.
  Test a Paladin blessing exception and a synced class plan in the same group.
  As a Mage, confirm the picker prevents selecting both magic variants.
- With reagents in bags, make one potential recipient ineligible for the
  group buff. Confirm the row, Shift-click, and group keybind do not broaden
  the cast to override the table. Repeat after entering and leaving combat.
- Save a named profile, reload, and switch settings before restoring it.
  Check search, Tab, activation, narration and Escape on the table and picker,
  including smaller settings scales and German labels if available.

## General Release Checks

- **Empty list:** verify that confirmed coverage, no eligible cast target,
  disabled friendly nameplates and unreadable range or auras are distinct
  states. Unknown coverage must not be reported as fully buffed.
- **Eligibility:** confirm a player appears only when a known buff benefits them and they are in spell range, alive, and out of combat. Toggle include-self and verify the character can buff itself.
- **Cast attribution:** outside combat, use `/br clicks` to turn on diagnostics.
  Start with a buff that appears in the list and note the cast counter. Click its
  row, wait for the global cooldown, then use the Cast Next Buff keybind on
  another eligible target. Cast the same spell from the action bar after the
  cooldown. The counter and cast history should advance once for each BuffRadar
  cast and stay unchanged for the action-bar cast. If available, also test
  self-buffing, the group buff keybind, and Shift-clicking a row for a group buff.
  Capture all `BuffRadar:` diagnostic lines from the click through completion
  or failure using chat screenshots. Include the client build and indicate which
  action produced each sequence. Run `/br clicks` again to stop tracing.
- **Failure recovery:** test line of sight, range and an invalid target while
  tracing. Verify that a failed cast never advances the counter and that an
  unrelated error never skips the target. For line of sight, look for
  `SENT` and `FAILED` with the same spell ID and cast GUID, then the
  line-of-sight message in the same frame. Check that this sequence advances
  the queue. Retry during the global cooldown and confirm the cooldown error
  leaves the target in the queue.
- **Combat:** enter combat with buffs missing. Confirm no protected cast starts; after combat, verify the list resumes and catches up.
- **Death and resurrection:** die in and out of combat. Check that BuffRadar's window, pill, minimap button, and open settings close, and that its cast bindings stay disarmed. Reload while dead and test release to ghost form, combat ending while dead, resurrection after releasing, and resurrection without releasing. Confirm the normal window and minimap preferences resume after resurrection and combat, including a window you hid manually before death. The game's AddOns and minimap-compartment entries can stay listed, but their BuffRadar controls should not open the addon while dead.
- **Hover close:** with the title on and off, hover the list, then move onto and off the close button. Confirm it stays under the cursor, remains reachable near the screen edge, and leaves no header gap with the title off. Confirm locked click-through and the existing show/hide binding still work.
- **Scrollable rows:** test with more than 15 entries, then with a short
  viewport or higher UI scale so fewer rows fit. Scroll to the bottom and
  back. Confirm the footer's row span updates and a click buffs the player
  shown on that row. Verify the Cast Next Buff key still uses the first eligible
  player in the full list. Test wheel input while holding a mouse button over a
  row and after combat begins. Confirm the secure rows disarm in combat and
  rebind correctly afterward. Repeat with two columns, a name filter, and a
  list that shrinks below 15 entries.
- **Settings and safety:** switch settings tabs and confirm search closes; check for overlapping controls and ADDON_ACTION_BLOCKED errors.
- **Settings search:** use `/br config find` to focus Find. Search the active tab,
  close with Escape, and confirm the query clears and control contrast returns.
- **Settings keyboard navigation:** run `/br config navigate`. Move forward and
  back with Tab and Shift+Tab, activate tabs and controls with the displayed
  activation key, and use the arrow keys where the footer indicates. Include
  a checkbox, a slider, a dropdown, a native text field, and a secondary settings
  panel. Confirm focus stays visible and skips hidden or disabled controls.
- **Settings narration:** run `/br config narrate` and listen for the focus label
  and current value. Check rapid navigation and text-field editing, then confirm
  Escape, closing settings, and starting combat return control to the game.
- **Scan performance:** enable fast aura updates with `/br fastaura on`. Add
  and remove a watched buff, then change target or leave the group. Verify the
  list reflects the new unit and its buffs. Run `/br perf` out of combat and
  record scan counts and timings while solo and in a raid, if available.
  Record preparation, import and combat-debuff samples separately. Compare
  the raid scan average and worst case with the 2 ms / 8 ms field targets;
  don't infer these from fake-client timings.
- **Pull timers:** with buffs missing and pull flash enabled, start a group
  countdown and cancel it. Replace a countdown while it is still active:
  unrelated or ambiguous cancellations must not remove the replacement, which
  still has its own expiry. Use `/br apicheck` to record which payloads the
  client emits. Do not assume a boss-mod map field is a unique timer ID.
- **Ready check and wipe:** confirm missing buffs are reported for a group member
  beyond cast range. Check that unreadable aura data is marked unverified and
  a ready check leaves the visible cast target unchanged. In a raid, confirm
  the wipe report counts the player once.

## 1.15.16 field checks

- **Nearby-player diagnostics:** With friendly nameplates on, use
  `/br why <name>` for an ungrouped player without targeting them. Turn
  nameplates off and repeat with the same player under the mouse. Move the
  mouse away and verify the message offers a way to diagnose discovery.
- **Group reagents:** With group casting enabled and enough unbuffed members
  in range, spend the last reagent. Confirm the next action updates to a
  single-target cast. Try the row, Shift-click, and Cast Next Group Buff with
  empty bags, then restock and confirm the group action is available again.
  Verify the pre-pull estimate distinguishes bags from needed casts.
- **Recipient rank and identity:** Test a low-level party member and then an
  ungrouped low-level player. Check the next-cast preview, cast once with
  `/br clicks` on and confirm the recipient receives the displayed rank. Verify
  the original target is preserved. Repeat after scrolling, a roster change,
  and combat. Turn tracing off with `/br clicks`.
- **Blessing exception:** With two Paladin buff recipients of the same class,
  give one a different normal blessing. Confirm a group cast does not replace
  that exception, the other player still follows the class choice, and a
  departed player does not carry the session exception back on rejoin.
- **Ready-check detail:** Enable the ready-check view and have group members
  answer Ready, decline, and leave one response pending. Include missing and
  soon-expiring buffs. Check the retained results after completion, then leave
  the group and verify the results clear. Confirm the cast queue stays usable.
