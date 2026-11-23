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
  return { version = 1, bridge = 2, revision = revision, state = state, reason = reason, partial = partial,
    actionable = count, expiring = expiring,
    firstExpiry = expiryEnd and { spell = expirySpell, name = expiryName, endsAt = expiryEnd } or nil }
end

-- A compact, name-free display model. The addon remains the queue engine;
-- an external display only renders these fields and re-reads on the event.
local function GetDisplay()
  local colors = {
    covered = { 0.2, 0.85, 0.35 }, attention = { 1, 0.78, 0.25 },
    critical = { 1, 0.25, 0.2 }, unknown = { 0.65, 0.65, 0.75 }, unavailable = { 0.45, 0.45, 0.5 },
  }
  local marks = { covered = "+", attention = "!", critical = "!!", unknown = "?", unavailable = "-" }
  return { version = 2, revision = revision, state = state, reason = reason, partial = partial,
    actionable = count, expiring = expiring, label = S.Description(),
    text = marks[state] or "-", color = colors[state] or colors.unavailable,
    firstExpiry = expiryEnd and { spell = expirySpell, endsAt = expiryEnd } or nil }
end

-- Predefined custom-trigger import snippets. They are plain Lua strings, so
-- no serializer, compressor, library or network dependency is added.
local IMPORT_STRINGS = {
  state = [[-- BuffRadar display bridge: event BUFFRADAR_STATUS_CHANGED
function()
  local api = BuffRadarAPI
  if not api or api.version ~= 1 or not api.GetDisplay then return false end
  local display = api.GetDisplay()
  aura_env.display = display
  return display.state == "attention" or display.state == "critical"
end]],
  critical = [[-- BuffRadar display bridge: event BUFFRADAR_STATUS_CHANGED
function()
  local api = BuffRadarAPI
  if not api or api.version ~= 1 or not api.GetDisplay then return false end
  local display = api.GetDisplay()
  aura_env.display = display
  return display.state == "critical"
end]],
  count = [[-- BuffRadar display bridge: event BUFFRADAR_STATUS_CHANGED
function()
  local api = BuffRadarAPI
  if not api or api.version ~= 1 or not api.GetDisplay then return "" end
  local display = api.GetDisplay()
  aura_env.display = display
  return display.actionable > 0 and tostring(display.actionable) or display.text
end]],
}
local function CopyImportStrings()
  local out = {}
  for key, value in pairs(IMPORT_STRINGS) do out[key] = value end
  return out
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
-- version stays 1 for existing consumers; bridge=2 adds the display model.
BuffRadarAPI = { version = 1, bridge = 2, GetStatus = GetStatus, GetUnit = GetUnit,
  GetSummary = S.Summary, GetDisplay = GetDisplay, GetImportStrings = CopyImportStrings,
  GetImportString = function(kind) return IMPORT_STRINGS[kind] end }

X.ext.bridge = function(rest)
  if rest ~= "" then X.Print(L["Usage: /br bridge"]); return true end
  if X.DiagnosticsPaused and X.DiagnosticsPaused() then return true end
  local strings = CopyImportStrings()
  local lines = {}
  for _, key in ipairs({ "state", "critical", "count" }) do
    lines[#lines + 1] = "-- " .. key .. " --"
    lines[#lines + 1] = strings[key]
  end
  if #lines == 0 then X.Print(L["No display bridge snippets are available."]); return true end
  local text = table.concat(lines, "\n\n")
  if X.ShowExport then X.ShowExport(text, false, L["Copy display bridge snippets"])
  else X.Print(L["Display bridge snippets"]) end
  return true
end

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
