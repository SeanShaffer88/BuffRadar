# BuffRadar Forever in-game release checklist

Run this against the exact candidate ZIP after CI passes. Record the version, client build, tester, and pass/fail for each check. Do not mark a build field-tested until the applicable checks pass.

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

- **Empty list:** with no missing buffs, confirm the fully-buffed message. Disable friendly nameplates and confirm the explicit warning. On a client that does not answer range checks, confirm the list warns that range cannot be verified instead of claiming everyone is buffed.
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
- **Scrollable rows:** with more than 15 entries, scroll over the list to the
  bottom and back. Confirm the row range updates and a click buffs the player
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
- **Pull timers:** with buffs missing and pull flash enabled, start a group
  countdown, cancel or replace it, and verify the replacement stays active
  until its own deadline. Use `/br apicheck` to check the native and supported
  boss-mod countdown diagnostics.
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
