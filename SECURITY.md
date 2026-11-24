# Security and safety model

BuffRadar is a World of Warcraft addon running inside the game's addon
sandbox. It has **no network access**, reads no files, and stores data only in
the game's SavedVariables for this addon (`BuffRadarDB`): settings, ignore
list, profiles and cast statistics on this machine.

## Protected actions and combat lockdown

BuffRadar separates observation from action. Scans and status summaries read
unit, spell and aura information; casting uses Blizzard secure action buttons
and Blizzard's protected macro mechanism. A cast is never triggered by a
periodic timer or by a status integration.

- Secure cast attributes are written only while the client is outside combat
  lockdown, the player is alive, the save is in a writable schema state, and
  the selected package is supported. On a combat-edge event, BuffRadar latches
  the action gate immediately; it releases that latch only after a safe
  post-combat or resurrection event.
- Secure buttons use the secure templates' protected handlers. BuffRadar
  composes ordinary interaction with `HookScript` and `SecureHandlerWrapScript`;
  it does not replace a secure button's `OnClick` handler with `SetScript`.
- Combat state is checked before protected frame geometry, registration,
  attribute and visibility-driver changes. If combat state cannot be read,
  the protected write is refused. The game's `ADDON_ACTION_BLOCKED` and
  `ADDON_ACTION_FORBIDDEN` events are recorded as local diagnostic faults.
- Merchant purchases are opt-in, quote-bound, and require a fresh explicit
  confirmation. The quote is revalidated immediately before the protected
  purchase call. BuffRadar never automatically buys supplies.

These controls are defense in depth, not a promise that every game build or
third-party UI combination is taint-free. Taint is controlled by the game;
users should report any blocked/forbidden-action event with the self-test
output and client build. Do not use the addon to bypass combat lockdown.

## Data and in-game communication

BuffRadar does not upload telemetry, collect account credentials, or send
personal data to an external service. Integrations expose read-only status
through the versioned `BuffRadarAPI`; they cannot change settings or trigger a
cast. Optional snippets read that API and display its state only.

Communication, all inside the game:

- **Addon messages** on the `BuffRadar` prefix coordinate cast notes,
  cover-me handoff, and group plans. The receiver requires the current
  party or raid channel and an unambiguous, readable roster identity.
  Assignments require a group leader or assistant. Blessing plans also
  accept a paladin in the group.
- **Group chat posts**, only when you are the leader or an assistant and the
  matching option is on: the ready-check summary (`readyPost`, off by default)
  and the post-wipe summary (`wipeReport`, off by default).
- **Chat reading:** whispers and /say are read locally to tag a player who
  asks for a buff (`requests`, on by default). Nothing is stored or sent.

SavedVariables are schema-versioned. Newer and over-limit saves are preserved
rather than silently overwritten; see the recovery controls and
`docs/STATUS_API.md` for the public read-only interface.

## Reporting a problem

If you find a security problem — for example, a way for another player's
addon messages to change your settings or make the addon do something you
didn't ask for — please report it privately instead of opening a public
issue:

- Use GitHub's **private vulnerability reporting** on this repository
  (Security → Report a vulnerability), or
- contact the maintainer through GitHub (@SeanShaffer88).

You can expect an acknowledgement within a few days and a fix in the next
release; sooner if the problem is actively exploitable in game.

## Supported versions

Only the **latest release** receives security fixes. Older versions stay
available for rollback, as-is.
