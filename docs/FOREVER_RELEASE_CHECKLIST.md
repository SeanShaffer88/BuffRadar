# BuffRadar Forever in-game release checklist

Run this against the exact candidate ZIP after CI passes. Record the version, client build, tester, and pass/fail for each check. Do not mark a build field-tested until the applicable checks pass.

- **Empty list:** with no missing buffs, confirm the fully-buffed message. Disable friendly nameplates and confirm the explicit warning. On a client that does not answer range checks, confirm the list warns that range cannot be verified instead of claiming everyone is buffed.
- **Eligibility:** confirm a player appears only when a known buff benefits them and they are in spell range, alive, and out of combat. Toggle include-self and verify the character can buff itself.
- **Failure recovery:** test a line-of-sight block, an out-of-range cast, and an invalid target. Each failed target should be temporarily skipped; the next keybind press should advance to another eligible player.
- **Combat:** enter combat with buffs missing. Confirm no protected cast starts; after combat, verify the list resumes and catches up.
- **Settings and safety:** switch settings tabs and confirm search closes; check for overlapping controls and ADDON_ACTION_BLOCKED errors.
