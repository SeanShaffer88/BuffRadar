# Actions Search Design

Approved before UI implementation. Reuse the current settings search and its
five-row pagination, keyboard controller, narration and literal text matching.

```text
+ BuffRadar Settings -------------------------------+
| [Find Settings and Actions.....................]   |
| [All] [Settings] [Actions]                         |
| Inspect > Raid Preparation                        |
|   /br prep show -- Open checklist                  |
| Manage > Subgroup Responsibilities                |
|   /br subgroup panel -- Open responsibilities      |
| Troubleshoot > Copy Support Report                |
|   /br support -- Local technical report            |
| [Previous] Matches: 14                   [Next]     |
+---------------------------------------------------+

+ Why This Buff? -----------------------------------+
| Player name [____________________________]         |
|                              [Explain] [Cancel]    |
+---------------------------------------------------+
```

Actions appear alongside settings and can be browsed using the Actions filter.
Each fixed internal action has a category, localized label, slash equivalent,
availability check and direct callback to an existing screen or operation.
There is no arbitrary command interpreter. Argument-taking operations open the
existing editor or reviewed workflow. The bounded player-name form calls the
existing read-only explanation function.

Availability checks are read-only. Activation rechecks the current client state.
Unavailable rows remain focusable so their reasons can be read and narrated.
Opening a group screen does not require leadership; the existing screen enforces
permissions on consequential operations. No launcher action casts a spell.

The Settings Actions button, optional keybind, `/br actions`, and Shift-left-click
on the gear open the same search. Existing gear Left/Right clicks and slash
commands remain available. No persistent action history or saved schema changes.
