# BuffRadar status API (version 1)

`BuffRadarAPI` is a local, read-only integration point. It does not scan auras on
request, change settings, cast, or send messages. The table is available once
BuffRadar's Lua files are loaded; before the first completed scan its state is
`unavailable`. All returned tables, including nested `missing` lists, are
independent copies.

## Read the current state

```lua
local api = BuffRadarAPI
if api and api.version == 1 then
  local summary = api.GetSummary()
  local unit = api.GetUnit("nameplate1")
  -- summary.state is suitable for an icon or label.
  -- If unit exists, unit.missing[1] is the first offered spell for that unit.
end
```

| Call | Returns |
| --- | --- |
| `GetSummary()` | `version`, `revision`, `state`, `partial`, `actionable` (number of cast targets), `expiring` (number of confirmed buff forecasts), optional `firstExpiry = { spell, name, endsAt }`, and `reason` when unavailable. `endsAt` uses the game's `GetTime()` clock, rounded to seconds. |
| `GetStatus()` | The summary plus `targets`, an ordered array of `{ unit, guid, name, missing }`. `missing` lists the localized spell names offered by the queue, including a group version when one is offered. |
| `GetUnit(unitToken)` | A target record for the token's current readable GUID, or `nil`. This also works for a nameplate token representing a queued party or raid member. A stale or reassigned token does not inherit a former unit's status. |

`state` is one of `covered`, `attention`, `critical`, `unknown`, or `unavailable`.
`attention` can mean an ordinary missing buff, an out-of-range need, or a
confirmed expiry forecast; it does not guarantee a cast target. `critical`
means a checked defensive buff (or a smart-priority instance buff) is
confirmed missing or has at most 15 seconds left. `partial` can be true even
when one need is known. `covered` applies only to the buffs BuffRadar was able
to check, not every buff in the game. `unavailable` has a `reason` of `inactive`,
`updating`, `paused`, `combat`, or `dead`. In these states the API does not
return old targets as current. In 1.15.38 an incompatible install stays
`inactive`; a failed refresh or cached row paint invalidates the snapshot
instead of republishing an old queue. This does not change the API version.

## React to changes

Compatible custom trigger hosts receive `BUFFRADAR_STATUS_CHANGED` when a
completed snapshot changes or is invalidated. Read the API on that event and on
initialization; the event carries no arguments. Other consumers can poll the
lightweight summary or `GetUnit(unitToken)` on their own normal update path.
Use `revision` to skip re-rendering unchanged data. For a custom trigger,
register `BUFFRADAR_STATUS_CHANGED` and use the same condition on initialization:

```lua
function()
  local api = BuffRadarAPI
  if not api or api.version ~= 1 then return false end
  local state = api.GetSummary().state
  return state == "attention" or state == "critical"
end
```

For per-nameplate text, pass that plate's current unit token to `GetUnit`.
Use its `missing` array to build the label and clear it when `GetUnit`
returns `nil`; do not hold on to a result across nameplate reuse.

For troubleshooting without a script, use `/br status` or `/br status export`.
The export is a local copy dialog; review names before posting it publicly.
