-- BuffRadar - prediction, contextual priority and periodic scan policy.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local X = ns.X
local I, L, Print = {}, X.L, X.Print
X.Intel = I

local db
local wipeUntil, fastUntil, manualDeadline = 0, 0, nil
local nextLatencySample, latency, lastTicks = 0, nil, 1
local scanAt, lead, horizon, instanceKey, grouped, recovering
local expiring, firstEnd, firstSpell, firstUnit, critical
local forecastWasCritical, noticedSpell, noticedEnd, notifyAfter
local CRITICAL_SECONDS = 15
local defensive = { FORTITUDE = true, MARK_OF_THE_WILD = true, BLESS_KINGS = true, BLESS_SANCTUARY = true }
local mana = { ARCANE_INTELLECT = true, DIVINE_SPIRIT = true, BLESS_WISDOM = true }

local function Deadline(now)
  local ends = X.pull and X.pull.endsAt
  if not ends or ends <= now then ends = 0 end
  if manualDeadline and manualDeadline > now then ends = math.max(ends, manualDeadline) end
  return ends > now and ends or nil
end

function I.ForecastEnabled()
  return db and not db.liteMode and db.forecastSeconds > 0
end

function I.InstanceID()
  if type(GetInstanceInfo) ~= "function" then return end
  local ok, _, kind, _, _, _, _, _, id = pcall(GetInstanceInfo)
  if ok and X.Readable(kind) and (kind == "raid" or kind == "party")
    and X.Readable(id) and X.Settings.PositiveID(id) then return id end
end

function I.BeginScan()
  scanAt = GetTime()
  lead = I.ForecastEnabled() and db.forecastSeconds or 0
  local deadline = lead > 0 and Deadline(scanAt)
  horizon = deadline and (deadline - scanAt + lead) or lead
  local id = db.smartPriority and next(db.instancePriority) and I.InstanceID()
  instanceKey = id and db.instancePriority[id] or nil
  grouped = db.smartPriority and X.InGroup()
  recovering = grouped and scanAt < wipeUntil
  expiring, firstEnd, firstSpell, firstUnit, critical = 0, nil, nil, nil, false
  -- The coverage line already watches the last five minutes. Reuse the same
  -- family lookup and only extend it when a real preparation timer needs it.
  return math.max(300, horizon)
end

local function MatchesInstance(key, blessing)
  return instanceKey and (instanceKey == key or instanceKey == blessing)
end

function I.Observe(unit, key, spell, seconds, blessing)
  if seconds == nil then return end
  local important = defensive[blessing or key] or (db.smartPriority and MatchesInstance(key, blessing))
  if important and seconds <= CRITICAL_SECONDS then critical = true end
  if seconds <= 0 or seconds > horizon then return end
  local ends = scanAt + seconds
  expiring = expiring + 1
  if not firstEnd or ends < firstEnd then firstEnd, firstSpell, firstUnit = ends, spell, unit end
end

function I.ForecastText(spell, name, endsAt)
  return string.format(L["Forecast: %s on %s expires in %ds."], spell, name,
    math.max(1, math.ceil(endsAt - GetTime())))
end

function I.ScanResult()
  local name = firstUnit and (X.UnitNameOf(firstUnit) or firstUnit)
  -- Treat nearly simultaneous expiry of the same buff as one notice. Keep
  -- the cooldown across roster refreshes; a different expiry can still warn
  -- even if the forecast never became completely empty.
  local notice = firstEnd and scanAt >= notifyAfter
    and (not noticedEnd or firstSpell ~= noticedSpell or math.abs(firstEnd - noticedEnd) > 1)
  if notice then
    noticedSpell, noticedEnd, notifyAfter = firstSpell, firstEnd, scanAt + 5
    Print(I.ForecastText(firstSpell, name, firstEnd))
  end
  local pulse = notice or (critical and not forecastWasCritical)
  forecastWasCritical = critical
  -- Round only the exported timestamp to avoid publishing tiny timer jitter.
  return critical, expiring, firstSpell, name, firstEnd and math.ceil(firstEnd), pulse
end

function I.ForgetAlerts()
  forecastWasCritical = false
end

-- Lower tiers win. The saved manual order breaks ties within a tier;
-- contextual promotion never writes to it or makes a new spell eligible.
function I.Tier(entry, key, blessing)
  if not grouped or not entry.group or entry.pet then return 3 end
  if MatchesInstance(key, blessing) then return 0 end
  local family = blessing or key
  if (recovering or entry.rezzed) and defensive[family] then return 1 end
  if entry.groupRole == "TANK" and (defensive[family] or family == "FEAR_WARD" or family == "THORNS") then return 2 end
  if entry.groupRole == "HEALER" and mana[family] then return 2 end
  return 3
end

function I.MarkWipe()
  if db and db.smartPriority and X.InGroup() then wipeUntil = GetTime() + 90 end
end

function I.ClearPreparation()
  manualDeadline, X.pull = nil, nil
end

function I.ResetContext()
  wipeUntil, noticedSpell, noticedEnd, notifyAfter = 0, nil, nil, 0
  I.ClearPreparation()
  I.ForgetAlerts()
end

function I.WakeAfterCombat()
  fastUntil = GetTime() + 3
end

function I.ScanTicks(groupSize)
  if not db or not db.scanThrottle then lastTicks = 1; return 1 end
  local now = GetTime()
  local deadline = Deadline(now)
  if now < fastUntil or (deadline and deadline - now <= 10) then lastTicks = 1; return 1 end
  if now >= nextLatencySample then
    nextLatencySample = now + 5
    latency = nil
    if type(GetNetStats) == "function" then
      local ok, _, _, home, world = pcall(GetNetStats)
      if ok then
        for i = 1, 2 do
          local v = i == 1 and home or world
          if X.Readable(v) and type(v) == "number" and v >= 0 and v < math.huge then
            latency = math.max(v, latency or 0)
          end
        end
      end
    end
  end
  local speed = X.ReadUnitNumber(GetUnitSpeed, "player")
  if latency and latency >= 250 then
    lastTicks = speed == 0 and 4 or 3
  elseif speed and speed > 0 then
    lastTicks = 1
  else
    local large = groupSize() > 20
    lastTicks = speed == 0 and (large and 3 or 2) or (large and 2 or 1)
  end
  return lastTicks
end

function I.EffectiveInterval()
  return (db and db.scanThrottle and lastTicks or 1) * X.Core.UpdateInterval
end

function I.PaceText()
  return string.format(L["Periodic scan: %.1fs · Latency: %s"], (db.scanThrottle and lastTicks or 1) * X.Core.UpdateInterval,
    latency and string.format(L["%d ms"], math.floor(latency)) or L["Unknown"])
end

function I.MemoryKB()
  local update = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or _G.UpdateAddOnMemoryUsage
  local read = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or _G.GetAddOnMemoryUsage
  if type(read) ~= "function" then return end
  if type(update) == "function" then pcall(update) end
  local kb = X.ReadUnitNumber(read, "BuffRadar")
  if kb and kb >= 0 then return kb end
end

function I.MemoryReport()
  local kb = I.MemoryKB()
  Print(kb and string.format(L["BuffRadar memory: %.0f KB (game-reported total)."], kb)
    or L["BuffRadar memory: unavailable on this client."])
  Print(L["The game does not report memory by feature."])
  Print(string.format(L["Queue rows: %d · Saved casts: %d · Debuff rules: %d"],
    X.Status.Count(), #db.history, #db.debuffRules))
  Print(string.format(L["Lite mode: %s"], L[db.liteMode and "On" or "Off"]))
  Print(I.PaceText())
end

function X.SettingsChanged(changed)
  local lite = changed.liteMode
  if X.Views and (changed.matrixView or changed.selfStatusStrip or changed.profile) then pcall(X.Views.Refresh) end
  if changed.forecastSeconds or lite then
    I.ForgetAlerts()
    if not I.ForecastEnabled() then
      manualDeadline, noticedSpell, noticedEnd, notifyAfter = nil, nil, nil, 0
    end
  end
  if X.pull and (changed.pullFlash or changed.forecastSeconds or lite) and not I.ForecastEnabled()
    and (not db.pullFlash or X.pull.forecastOnly) then X.pull = nil end
  if changed.smartPriority and not db.smartPriority then wipeUntil = 0 end
  if lite and db.liteMode and X.CloseRaidPreparation then X.CloseRaidPreparation() end
  if lite or changed.debuffWatch or changed.debuffRules then X.Debuffs.Apply() end
  if (lite or changed.statusMinimap) and X.UpdateMinimapStatus then X.UpdateMinimapStatus() end
  if (lite or changed.visualAlerts) and X.TickMinimapPulse then X.TickMinimapPulse() end
  if changed.readinessAura and X.QueuePersonalReadiness then X.QueuePersonalReadiness() end
  if changed.sync then
    X.CheckLegacyAuthority(not db.sync)
    if not db.sync then X.StopCoordination() end
  end
  if changed.forecastSeconds or changed.pullFlash or lite or changed.smartPriority or changed.scanThrottle
    or changed.profile or changed.matrixView or changed.selfStatusStrip then X.Core.QueueRefresh() end
end

function X.SetPreference(key, value)
  if X.Preferences then return X.Preferences.Set(key,value,"other") end
  if db[key] == value then return true end
  if X.Settings.SaveState()=="future" then return false,"future" end
  db[key] = value
  X.SettingsChanged({ [key] = true })
  return true
end

function I.SetForecast(seconds)
  if type(seconds) ~= "number" or seconds ~= math.floor(seconds) or seconds < 0 or seconds > 300 then
    Print(L["Enter a forecast time from 0 to 300 seconds (0 turns it off)."])
    return false
  end
  X.SetPreference("forecastSeconds", seconds)
  return true
end

function I.SetInstancePriority(id, key)
  if not X.Settings.PositiveID(id) then Print(L["An instance ID is required."]); return false end
  if type(key) == "string" and key:lower() == "clear" then
    db.instancePriority[id] = nil
  else
    key = type(key) == "string" and key:upper() or ""
    if not X.Settings.PriorityKey(key) then Print(L["Use a buff key from /br buffs."]); return false end
    if not db.instancePriority[id] then
      local count = 0
      for _ in pairs(db.instancePriority) do count = count + 1 end
      if count >= X.Settings.MaxInstanceRules then Print(L["Instance rule limit reached."]); return false end
    end
    db.instancePriority[id] = key
  end
  X.Core.QueueRefresh()
  return true
end

local function ShowForecast()
  Print(string.format(L["Forecast lead: %ds (0 = off)."], db.forecastSeconds))
  if db.liteMode then Print(L["Forecasts are paused in Lite mode."]); return end
  local status = X.Status.Summary()
  if status.firstExpiry and status.firstExpiry.endsAt > GetTime() then
    local entry = status.firstExpiry
    Print(I.ForecastText(entry.spell, entry.name, entry.endsAt))
  end
end

X.ext.forecast = function(rest)
  local input = rest:lower()
  local timer = input:match("^timer%s+(%S+)$")
  if input == "" then ShowForecast()
  elseif timer then
    local seconds = tonumber(timer)
    if timer == "off" or seconds == 0 then manualDeadline = nil
    elseif not I.ForecastEnabled() then Print(L["Enable forecasts before setting a timer."]); return true
    elseif not seconds or seconds ~= math.floor(seconds) or seconds < 1 or seconds > 600 then
      Print(L["Use /br forecast timer <1-600|off>."]); return true
    elseif InCombatLockdown() or X.PlayerSuspended() then return true
    else
      manualDeadline = GetTime() + seconds
      Print(string.format(L["Local preparation timer: %ds."], seconds))
    end
    X.Core.QueueRefresh()
  elseif I.SetForecast(input == "off" and 0 or tonumber(input)) then
    Print(string.format(L["Forecast lead: %ds (0 = off)."], db.forecastSeconds))
  end
  if X.RefreshConfig then X.RefreshConfig() end
  return true
end

X.ext.smartprio = function(rest)
  local input = rest:lower()
  local here = input:match("^here%s+(%S+)$")
  local id, key = input:match("^instance%s+(%d+)%s+(%S+)$")
  if input == "" or input == "on" or input == "off" then
    X.SetPreference("smartPriority", input == "on" or (input == "" and not db.smartPriority))
    Print(string.format(L["Smart priority: %s"], L[db.smartPriority and "On" or "Off"]))
  elseif here or id then
    local instance = here and I.InstanceID() or tonumber(id)
    if I.SetInstancePriority(instance, here or key) then
      Print(string.format(L["Instance %d: %s"], instance, db.instancePriority[instance] or L["Default"]))
    end
  elseif input == "list" then
    local ids = {}
    for instance in pairs(db.instancePriority) do ids[#ids + 1] = instance end
    table.sort(ids)
    if #ids == 0 then Print(L["No instance priority rules saved."]) end
    for _, instance in ipairs(ids) do Print(string.format(L["Instance %d: %s"], instance, db.instancePriority[instance])) end
  else
    Print(L["Use /br smartprio [on|off|list], here <KEY|clear>, or instance <ID> <KEY|clear>."])
  end
  if X.RefreshConfig then X.RefreshConfig() end
  return true
end

local function Toggle(setting, label, usage)
  return function(rest)
    local value = rest:lower()
    if value ~= "" and value ~= "on" and value ~= "off" then Print(usage); return true end
    X.SetPreference(setting, value == "on" or (value == "" and not db[setting]))
    Print(string.format(label, L[db[setting] and "On" or "Off"]))
    if X.RefreshConfig then X.RefreshConfig() end
    return true
  end
end
X.ext.lite = Toggle("liteMode", L["Lite mode: %s"], "/br lite [on|off]")
X.ext.minimapstatus = Toggle("statusMinimap", L["Minimap status: %s"], "/br minimapstatus [on|off]")
X.ext.visual = Toggle("visualAlerts", L["Visual alerts: %s"], "/br visual [on|off]")

X.OnDBLoaded(function(value)
  db = value
  fastUntil = 0
  nextLatencySample, latency, lastTicks = 0, nil, 1
  I.ResetContext()
end)
