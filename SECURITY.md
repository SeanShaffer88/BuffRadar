# Security

BuffRadar is a World of Warcraft addon. It runs inside the game's addon
sandbox: it has **no network access**, reads no files, and stores data only in
the game's own SavedVariables for this addon (`BuffRadarDB` — your settings,
ignore list, profiles and cast statistics, all on your own machine). Its only
communication is the game's addon-message channel, on its own prefix, inside
your current group, and group-plan messages (assignments, blessing plan) are
only accepted from the group leader, an assistant, or — for the blessing
plan — a paladin.

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
