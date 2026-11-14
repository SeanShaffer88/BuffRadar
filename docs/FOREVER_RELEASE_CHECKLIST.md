# BuffRadar Forever in-game release checklist

Run this against the exact candidate ZIP after CI passes. Record the version, client build, tester, and pass/fail for each check. Do not mark a build field-tested until the applicable checks pass.

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
  unrelated error never skips the target. Capture whether a failed cast reports
  a cast GUID and whether it advances the queue, so the failure path can be
  verified against the actual client.
- **Combat:** enter combat with buffs missing. Confirm no protected cast starts; after combat, verify the list resumes and catches up.
- **Death and resurrection:** die in and out of combat. Check that BuffRadar's window, pill, minimap button, and open settings close, and that its cast bindings stay disarmed. Reload while dead and test release to ghost form, combat ending while dead, resurrection after releasing, and resurrection without releasing. Confirm the normal window and minimap preferences resume after resurrection and combat, including a window you hid manually before death. The game's AddOns and minimap-compartment entries can stay listed, but their BuffRadar controls should not open the addon while dead.
- **Hover close:** with the title on and off, hover the list, then move onto and off the close button. Confirm it stays under the cursor, remains reachable near the screen edge, and leaves no header gap with the title off. Confirm locked click-through and the existing show/hide binding still work.
- **Settings and safety:** switch settings tabs and confirm search closes; check for overlapping controls and ADDON_ACTION_BLOCKED errors.
- **Settings search:** use `/br config find` to focus Find. Search the active tab,
  close with Escape, and confirm the query clears and control contrast returns.
- **Ready check and wipe:** confirm missing buffs are reported for a group member
  beyond cast range. Check that unreadable aura data is marked unverified and
  a ready check leaves the visible cast target unchanged. In a raid, confirm
  the wipe report counts the player once.
