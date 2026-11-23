# Live-client validation checklist

Offline Lua 5.1 smoke tests do not emulate WoW: Forever's secure execution,
combat lockdown, taint rules, nameplates, merchant UI, or actual spell casts.
The checklist below is mandatory before calling a release field-validated.
No live-client result has been recorded for this candidate yet.

## Record the exact candidate

Before installing, record:

- the Forever ZIP filename and SHA-256 digest;
- the displayed addon version and TOC interface value;
- the WoW: Forever client build/version, realm, operating system, and character
  class/level;
- date/time and tester; and
- whether another UI addon was enabled (record the list, do not infer a cause).

Do not edit the ZIP after calculating its digest. Attach the game's local
`/br selftest` output and `Interface/AddOns/BuffRadar/BuffRadar.lua` report
lines only if relevant. Redact character names and realm before sharing.

## Smoke and combat safety

1. Install the candidate in a test profile with a backup of `BuffRadarDB`.
   Log in alive and out of combat; confirm the queue window and settings open.
2. Enable Simple Mode. Confirm the minimal queue remains readable, **Cast next
   buff** works for the expected recipient, settings/advanced actions are
   hidden, and `/br simple off` restores them without changing saved choices.
3. Enable Performance Mode. Confirm diagnostics and merchant previews are
   paused; turn it off and verify both return.
4. Enter combat while the queue has a ready action. Confirm no button or macro
   attempts to change protected attributes, the queue cannot cast, and no
   `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN` event is emitted.
   Leave combat; confirm the queue refreshes and secure actions resume only
   after the player is alive and the game reports combat lockdown ended.
5. Repeat while dead/ghosted, during a loading screen, and immediately after
   resurrection. Verify no stale action is left armed.
6. Open, resize, move, and close settings and the main window both in and out
   of combat. Confirm no protected-operation errors or taint dialogs.

## Gameplay and merchant checks

1. With a party/raid test group, verify self, party, raid, nameplate, range,
   aura-expiration, and spell-cooldown events update the queue without waiting
   for a periodic player scan.
2. Verify each cast by mouse, configured click phase, keybind, and managed
   macro. Change a recipient's identity between scan and click; confirm the
   stale action disarms rather than targeting the replacement.
3. Test death, resurrection, zoning/loading, city pause, and group roster
   changes. Confirm the queue and read-only status report appropriate states.
4. At a supported merchant, enable restock previews, inspect the exact item,
   stack, quantity, cost, cap, and free-slot quote; change one input and confirm
   approval is invalidated. Confirm only an explicit fresh approval purchases
   the revalidated quote. Do not test with valuable currency or an untrusted
   merchant.
5. Confirm `/br bridge` snippets report the public display state and never
   alter the queue, settings, or casting state.

## Evidence and result

For each item record `PASS`, `FAIL`, or `NOT RUN`, the exact observation, and
any error text. A failed or unrun step is not a pass. Attach the exact ZIP
SHA-256, build information, test date, platform, anonymized self-test output,
and screenshots/logs for any taint, combat, cast-target, or purchase issue.

| Area | Result | Evidence / notes |
|---|---|---|
| Candidate digest and game build captured | NOT RUN | No candidate package or client session recorded. |
| Simple Mode and Performance Mode | NOT RUN | |
| Combat lockdown, taint, death and resurrection | NOT RUN | |
| Mouse, keybind, macro and stale-recipient casts | NOT RUN | |
| Event-driven queue updates | NOT RUN | |
| Merchant quote invalidation and explicit purchase | NOT RUN | |
| Status API/display bridge | NOT RUN | |

Do not mark the release field-validated until every required row is either
passed with evidence or explicitly excluded by the release owner.
