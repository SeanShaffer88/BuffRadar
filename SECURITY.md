# Security

BuffRadar is a World of Warcraft addon. It runs inside the game's addon
sandbox: it has **no network access**, reads no files, and stores data only in
the game's own SavedVariables for this addon (`BuffRadarDB` — your settings,
ignore list, profiles and cast statistics, all on your own machine).

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
