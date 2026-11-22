# Local support and theme changes

Design sketch approved before implementation. No saved schema changes.

```text
Caster Coordination
[Reports] [Draft] [Delivery] [Inbox] [Peers]
Peer verification is separate from plan delivery and buff coverage.
Alyx  - Verified
Bela  - Awaiting reply
Cato  - Retrying verification
Dena  - No response
Eryn  - Incompatible protocol
[Previous] [Next]

+ Theme Preview -------------------------------- [X] +
| Preview changes the window; settings stay unchanged. |
| [Previous]          Auto               [Next]        |
| Selected: matching palette (loaded UI addon)         |
| +---- BuffRadar sample in candidate colours ------+ |
| | Missing buff                      [sample icon] | |
| +------------------------------------------------+ |
|                         [Apply] [Cancel]             |
+----------------------------------------------------+
```

Peers are available to group members without opting into caster plans. Reading
status does not send a message. Silence means unverified, never incompatible.
Roster and leader changes invalidate old verification observations.

The existing Support report remains the single local copy/export flow. Add
allowlisted settings, aggregate peer counts, theme selection and finite error
counts without names, chat, custom labels, or raw error messages.

Theme previews are transient. Apply commits one preferences transaction. Cancel,
closing the panel, combat, or a conflicting preferences change discards the
preview. Auto identifies its current candidate separately from the saved choice.
