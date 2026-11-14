# Contributing to BuffRadar

BuffRadar targets World of Warcraft: Forever, Interface 16001. Read the
[player guide](editions/forever/README.md) for how the addon works and
[AGENTS.md](AGENTS.md) for project rules.

## Report an issue

Open a [bug report or feature request](https://github.com/SeanShaffer88/BuffRadar/issues/new/choose).
For a bug, include the addon version, WoW build, reproduction steps, and the
first Lua error if one appeared. Remove character names and chat details you
prefer to keep private. Follow the [security policy](SECURITY.md) for security reports.

## Propose a change

1. Fork the repo and branch from `main`. Keep each pull request focused on one behavior.
2. Use Lua 5.1 and the existing addon namespace. Keep cast actions on the secure,
   user-triggered path. Check client-returned data before using it in Lua
   comparisons, arithmetic, or table keys.
3. Add a regression step for the changed behavior. For persistence changes,
   include a fixture from a previous version. Update the Forever TOC when its
   metadata or load order needs to change.
4. Run the [local checks](tools/README.md) and include their results in the PR.
   State which behaviors you verified in Forever and which you exercised in mocks.
5. Open a pull request with the reproduction, proposed change, and compatibility
   tradeoffs. Maintainers review the change and the CI result.

Run the [Forever checklist](docs/FOREVER_RELEASE_CHECKLIST.md) when the change
affects combat, bindings, restricted client data, or visible settings layout.
