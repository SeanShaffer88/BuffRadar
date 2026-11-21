-- BuffRadar - last completed scan, shared by the minimap and read-only API.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local X = ns.X
local L, I = X.L, X.Intel
local S = {}
X.Status = S

local rows, count, revision = {}, 0, 0
local state, reason, partial = "unavailable", "inactive", false
local expiring, expirySpell, expiryName, expiryEnd = 0, nil, nil, nil
local lastAttemptAt, lastCompletedAt, completedGeneration, badClock = nil, nil, 0, false
local labels = { covered = "Checked buffs are covered", attention = "Buffs need attention",
  critical = "Important buff missing or expiring", unknown = "Buff coverage could not be verified" }
local reasons = { combat = "Buff scan paused in combat", dead = "Buff scan paused while dead",
  paused = "Buff scan paused", updating = "Waiting for a fresh buff scan", inactive = "No applicable buffs to check" }

local function ObserverRefresh()
  if X.Daily then pcall(X.Daily.Refresh) end
  if X.Views then pcall(X.Views.Refresh) end
end
local function Now(value)
  local n=value
  if n==nil then n=X.ReadUnitNumber(GetTime) end
  return X.Readable(n) and type(n)=="number" and n==n and n>=0 and n<math.huge and n or nil
end
function S.Attempt()
  local now=Now()
  if not now or (lastAttemptAt and now<lastAttemptAt) then badClock=true;return end
  lastAttemptAt=now
end
function S.Freshness(now)
  now=Now(now)
  local age=now and lastCompletedAt and now-lastCompletedAt or nil
  local current,why="never",reason
  if not now or badClock or (age and age<0) then current,why,age="unavailable","clock",nil
  elseif state=="unavailable" and (reason=="paused" or reason=="combat" or reason=="dead") then current="paused"
  elseif state=="unavailable" and lastCompletedAt then current="unavailable"
  elseif lastCompletedAt then
    local interval=X.Intel.EffectiveInterval()
    current=age>math.max(10,3*interval) and "stale" or "current"
  end
  return {lastAttemptAt=lastAttemptAt,lastCompletedAt=lastCompletedAt,age=age,state=current,reason=why,generation=completedGeneration}
end

local function Notify()
  revision = revision + 1
  ObserverRefresh()
  if X.SupportChanged then pcall(X.SupportChanged) end
  if X.UpdateMinimapStatus then X.UpdateMinimapStatus() end
  -- Consumers can re-read after the queue has been committed. No dependency
  -- or load-order requirement, and a consumer exception cannot break casting.
  local bridge = _G.WeakAuras
  if type(bridge) == "table" and type(bridge.ScanEvents) == "function" then
    pcall(bridge.ScanEvents, "BUFFRADAR_STATUS_CHANGED")
  end
end

local function ClearRow(row)
  row.unit, row.guid, row.name = nil, nil, nil
  for i = #row.missing, 1, -1 do row.missing[i] = nil end
end

function S.Unavailable(why)
  I.ForgetAlerts()
  if why == "updating" then
    if X.PlayerSuspended() then why = "dead"
    elseif InCombatLockdown() then why = "combat" end
  end
  if state == "unavailable" and reason == why then return end
  for i = 1, count do ClearRow(rows[i]) end
  count, state, reason, partial = 0, "unavailable", why, false
  expiring, expirySpell, expiryName, expiryEnd = 0, nil, nil, nil
  Notify()
end

function S.Publish(entries, n)
  local critical, pending, spell, name, ends, pulse = I.ScanResult()
  local tracked = next(X.tally) ~= nil
  local expected = X.ReadUnitNumber(GetNumGroupMembers)
  local grouped = (expected and expected > 1) or X.ReadUnitBool(IsInGroup) == true
    or X.ReadUnitBool(IsInRaid) == true or (expected == nil and X.InGroup())
  local incomplete = X.scanHasUnknownBuffs or X.scanNameFiltered or X.tallyUnknownUnits > 0
    or (grouped and (not expected or expected < 2 or X.tallyUnits ~= expected)) or false
  local current = critical and "critical" or (n > 0 or X.scanHasMissingBuffs or pending > 0) and "attention"
    or incomplete and "unknown" or tracked and "covered" or "unavailable"
  local why = current == "unavailable" and "inactive" or nil
  local changed = current ~= state or why ~= reason or incomplete ~= partial or n ~= count
    or pending ~= expiring or spell ~= expirySpell or name ~= expiryName or ends ~= expiryEnd
  for i = 1, n do
    local entry, row = entries[i], rows[i]
    if not row then row = { missing = {} }; rows[i] = row end
    if row.unit ~= entry.unit or row.guid ~= entry.guid or row.name ~= entry.name then changed = true end
    row.unit, row.guid, row.name = entry.unit, entry.guid, entry.name
    local missing = row.missing
    if #missing ~= #entry.missing then changed = true end
    for j = 1, #entry.missing do
      if missing[j] ~= entry.missing[j] then changed = true; missing[j] = entry.missing[j] end
    end
    for j = #missing, #entry.missing + 1, -1 do missing[j] = nil end
  end
  for i = n + 1, count do ClearRow(rows[i]) end
  count, state, reason, partial = n, current, why, incomplete
  expiring, expirySpell, expiryName, expiryEnd = pending, spell, name, ends
  local now=Now()
  completedGeneration=completedGeneration+1
  if now and (not lastCompletedAt or now>=lastCompletedAt) then lastCompletedAt,badClock=now,false else badClock=true end
  if X.CommitCoverageEvidence then X.CommitCoverageEvidence(completedGeneration,now) end
  if changed then Notify() else ObserverRefresh() end
  if pulse and X.VisualBuffAlert then X.VisualBuffAlert() end
end

function S.State() return state end
function S.Count() return count end

-- Typed internal aggregates: intentionally excludes expiry recipients and rows.
function S.Diagnostics()
  return { revision = revision, state = state, reason = reason, partial = partial,
    actionable = count, expiring = expiring }
end

function S.Description()
  return L[labels[state] or reasons[reason]]
end

function S.Summary()
  return { version = 1, revision = revision, state = state, reason = reason, partial = partial,
    actionable = count, expiring = expiring,
    firstExpiry = expiryEnd and { spell = expirySpell, name = expiryName, endsAt = expiryEnd } or nil }
end

local function CopyRow(row)
  local missing = {}
  for i, spell in ipairs(row.missing) do missing[i] = spell end
  return { unit = row.unit, guid = row.guid, name = row.name, missing = missing }
end

local function GetStatus()
  local snapshot = S.Summary()
  local targets = {}
  for i = 1, count do targets[i] = CopyRow(rows[i]) end
  snapshot.targets = targets
  return snapshot
end

local function GetUnit(unit)
  if count == 0 or not X.Readable(unit) or type(unit) ~= "string" or #unit > 40 then return end
  local guid = X.UnitGUIDOf(unit)
  if not guid then return end
  for i = 1, count do
    if rows[i].guid == guid then return CopyRow(rows[i]) end
  end
end

-- Public, versioned integration only. Addon modules use the private namespace.
BuffRadarAPI = { version = 1, GetStatus = GetStatus, GetUnit = GetUnit, GetSummary = S.Summary }

X.ext.status = function(rest)
  if rest ~= "" and rest:lower() ~= "export" then X.Print("/br status [export]"); return true end
  local line = S.Description() .. " · " .. string.format(L["%d cast targets · %d forecast buffs"], count, expiring)
  if rest == "" then
    X.Print(line)
  else
    local lines = { line }
    if X.DeliveryLines then
      local direct, bar = X.DeliveryLines()
      lines[#lines + 1] = L["Cast delivery"]
      lines[#lines + 1] = direct
      lines[#lines + 1] = bar
    end
    if expiryEnd and expiryEnd > GetTime() then lines[#lines + 1] = I.ForecastText(expirySpell, expiryName, expiryEnd) end
    for i = 1, count do
      local row = rows[i]
      lines[#lines + 1] = row.name .. ": " .. table.concat(row.missing, ", ")
    end
    X.ShowExport(table.concat(lines, "\n"), false, L["Copy the current buff status"])
  end
  return true
end
