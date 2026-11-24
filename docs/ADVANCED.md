# Advanced controls

BuffRadar's Advanced surface is optional. **Simple Mode** is the default for
new/older saves: the window keeps the next missing buff visible and offers a
single secure **Cast next buff** button. It does not change buff preferences,
profiles, assignments, or scan eligibility. Use `/br simple off` or **Show
all settings** to return to the full controls. `/br simple on` restores the
minimal surface.

## Performance Mode

`/br performance on` pauses diagnostic reports and restock previews, and
closes their open panels. It does not change saved buff choices or cast rules.
`/br performance off` restores normal behavior. The **Performance Mode**
checkbox is under Readiness → Performance & alerts. This is separate from
`/br throttle`, a legacy command name for adapting the low-frequency cooldown
sweep. It does not schedule or throttle the event-driven player/roster/aura
refreshes.

## Slash command reference

Run `/br help` with Simple Mode off for the complete in-client command list.
The principal advanced commands are:

| Area | Commands | Purpose |
|---|---|---|
| Window | `/br config`, `/br show`, `/br hide`, `/br toggle` | Open settings or control the queue window. |
| Queue and eligibility | `/br why [name]`, `/br nearby`, `/br filter [role]`, `/br ignore [name]`, `/br signore [name]` | Explain a queue decision, inspect nearby candidates, or manage local/session filters. |
| Preferences | `/br simple [on|off]`, `/br performance [on|off]`, `/br throttle [on|off]`, `/br lite [on|off]`, `/br minimapstatus [on|off]`, `/br visual [on|off]` | Choose the presentation and non-critical update policy. |
| Assignments | `/br assign`, `/br coordinate`, `/br coverage`, `/br prep` | Open group planning and readiness panels. These features require the Forever package and appropriate group permissions. |
| Diagnostics | `/br apicheck`, `/br buffcheck`, `/br perf`, `/br diff`, `/br selftest`, `/br support` | Review local capability, settings, performance and support data. Diagnostic commands are paused in Performance Mode. |
| Supplies | `/br supplies` | Preview a merchant quote; any purchase still needs a fresh explicit confirmation. Previews are paused in Performance Mode. |
| Status integration | `/br status [export]`, `/br bridge` | Read the status interface or show optional display-only Lua snippets. Neither path can cast or modify settings. |

Commands and available panels vary by package. The in-game help is the source
of truth for the installed edition. Commands hidden by Simple Mode remain
available after switching back to Advanced.

## Status bridge snippets

`/br bridge` presents three display-only snippets: attention/critical state,
critical-only state, and actionable count. They subscribe to
`BUFFRADAR_STATUS_CHANGED` and read `BuffRadarAPI.GetDisplay()`. Copy a
snippet into a compatible custom-trigger display; it is Lua source, not a
serialized import package. BuffRadar does not install, configure, or activate
an external display. The public API and trigger example are documented in
[`STATUS_API.md`](STATUS_API.md).
