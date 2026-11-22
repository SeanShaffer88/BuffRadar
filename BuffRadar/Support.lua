-- BuffRadar - session-local first-cast guidance and typed local support reports.
-- Copyright (C) 2026 Malikor. GPLv3 or later.
local _, ns = ...
local X, L = ns.X, ns.X.L
local G = {}
X.Support = G
local active, generation, baseline, confirmed = false, 0, 0, false
local state, reason, frame = "inactive", "inactive", nil
local controls, focus = {}, 0
local awaiting, inputPaused = false, false
local ownedModal
local faultCounts = { blocked=0, forbidden=0 }

function G.RecordFault(kind)
  if faultCounts[kind] then faultCounts[kind] = math.min(1000000, faultCounts[kind] + 1) end
end

local function Readable(value) return X.Readable(value) end
local function Number(value)
  if not Readable(value) or type(value) ~= "number" or value ~= value
      or value < 0 or value > 1000000000000 or value == math.huge then return nil end
  return value
end
local function Enum(value, choices)
  return Readable(value) and type(value) == "string" and choices[value] and value or "unknown"
end
local function Bool(value)
  if Readable(value) and type(value) == "boolean" then return value end
end
local function Data(fn)
  if type(fn) ~= "function" then return {} end
  local ok, value = pcall(fn)
  return ok and Readable(value) and type(value) == "table" and not getmetatable(value) and value or {}
end
local function Field(data, key) return rawget(data, key) end
local function BuffCount()
  local count = #X.Core.Buffs
  if X.HasKnownBlessings and X.HasKnownBlessings() then count = count + 1 end
  return count
end
local deliveryReasons = { ready = true, no_target = true, disarmed = true, recipient = true,
  unsafe = true, overflow = true, api = true, missing = true, unreadable = true,
  custom = true, combat = true, editor = true, running = true, sync = true }
local discoveryStates = { unavailable = true, attention = true, critical = true, covered = true, unknown = true }
local guideLabels = {
  discovering = "Waiting for discovery.", unsupported = "This client or edition is unsupported.",
  no_buffs = "No supported buffs are learned.", inactive = "Discovery is paused or disabled.",
  covered = "No missing buffs are queued. Covered players need no cast.",
  no_target = "No targets in the buff queue.", plates_off = "Friendly nameplates are off.",
  unknown = "Discovery is incomplete or filtered.",
  ready = "Ready: activate an existing BuffRadar row, binding or managed macro yourself.",
  awaiting_user_cast = "Waiting for your cast.", confirmed = "Confirmed: BuffRadar credited your cast.",
  paused = "Guidance is paused during combat or while the player is unavailable.",
}

function G.Snapshot()
  return { version = 1, generation = generation, active = active, state = state, reason = reason,
    successSerial = X.CastSuccessSerial() }
end

local function Focus(index)
  if controls[focus] then controls[focus]:UnlockHighlight() end
  focus = index
  if controls[focus] then controls[focus]:LockHighlight() end
end
local function Keyboard()
  if not frame then return end
  -- Propagation is nocombat even on an unprotected frame. Never flip it in combat.
  if InCombatLockdown() then frame:EnableKeyboard(false); Focus(0)
  else frame:SetPropagateKeyboardInput(true); frame:EnableKeyboard(active and frame:IsShown() and not inputPaused) end
end

local function ResumeAfter(dialog)
  if not dialog or not dialog:IsShown() then inputPaused = false; Keyboard(); return end
  ownedModal = dialog
  dialog.supportGuideGeneration = generation
  if dialog.supportGuideHook then return end
  dialog.supportGuideHook = true
  dialog:HookScript("OnHide", function(self)
    if ownedModal ~= self then return end
    ownedModal = nil
    if active and frame:IsShown() and self.supportGuideGeneration == generation then
      inputPaused = false
      Keyboard()
    end
  end)
end

function G.Refresh()
  if not active then return end
  local status, delivery = Data(X.Status.Diagnostics), Data(X.CastDelivery)
  local discovery = Enum(Field(status, "state"), discoveryStates)
  local scanReason = Enum(Field(status, "reason"), { updating=true, inactive=true, paused=true, dead=true, combat=true })
  if InCombatLockdown() or X.PlayerSuspended() then state, reason = "paused", "paused"
  elseif confirmed then state, reason = "confirmed", "confirmed"
  elseif not Bool(X.supported) then state, reason = "blocked", "unsupported"
  elseif BuffCount() == 0 then state, reason = "blocked", "no_buffs"
  elseif Bool(Field(delivery, "directReady")) or Bool(Field(delivery, "macroReady")) then
    state = awaiting and "awaiting_user_cast" or "ready"; reason = state
  elseif discovery == "covered" then state, reason = "blocked", "covered"
  elseif discovery == "unknown" or Bool(Field(status, "partial")) then state, reason = "blocked", "unknown"
  elseif scanReason == "updating" then state, reason = "discovering", "discovering"
  elseif scanReason == "paused" then state, reason = "blocked", "inactive"
  elseif not X.InGroup() and X.FriendlyPlatesOn() == false then state, reason = "blocked", "plates_off"
  else state, reason = "blocked", "no_target" end
  if frame then
    frame.body:SetText(L[guideLabels[reason] or guideLabels.unknown])
    local ok, direct, macroLine = pcall(X.DeliveryLines)
    if not ok or not Readable(direct) or not Readable(macroLine)
        or type(direct) ~= "string" or type(macroLine) ~= "string" then
      direct, macroLine = L["Unavailable"], L["Unavailable"]
    end
    frame.delivery:SetText(direct .. "\n" .. macroLine)
    Keyboard()
  end
end
X.SupportChanged = G.Refresh

function G.Close()
  active, confirmed, awaiting = false, false, false
  ownedModal = nil
  generation, state, reason = generation + 1, "inactive", "inactive"
  X.ObserveCastSuccess(nil)
  if frame then frame:Hide(); frame:EnableKeyboard(false); Focus(0) end
end

local function Success(serial)
  if not active or confirmed or not Number(serial) or serial <= baseline
      or (state ~= "ready" and state ~= "awaiting_user_cast")
      or InCombatLockdown() or X.PlayerSuspended() then return end
  -- The serial arrives only after the canonical attributed success path.
  confirmed, baseline = true, serial
  G.Refresh()
end

local function Create()
  frame = X.PanelWidget("Frame", "BuffRadarFirstCast", UIParent,
    BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(410, 420); frame:SetPoint("CENTER"); frame:SetClampedToScreen(true)
  frame:SetFrameStrata("DIALOG"); frame:EnableMouse(true)
  if frame.SetBackdrop then
    frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(0.04, 0.05, 0.09, 0.97)
  end
  local function text(font, y, height)
    local fs = frame:CreateFontString(nil, "OVERLAY", font)
    fs:SetPoint("TOPLEFT", 18, y); fs:SetWidth(374); fs:SetHeight(height)
    fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP"); fs:SetWordWrap(true)
    return fs
  end
  frame.title = text("GameFontNormalLarge", -18, 28); frame.title:SetText(L["First cast guide"])
  frame.body = text("GameFontHighlight", -58, 88)
  frame.delivery = text("GameFontHighlightSmall", -150, 94)
  local function button(label, y, action)
    local b = X.PanelWidget("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(374, 27); b:SetPoint("TOPLEFT", 18, y); b:SetText(L[label])
    b:SetScript("OnClick", action); controls[#controls + 1] = b
    return b
  end
  frame.setup = button("Open Quick Setup", -252, function()
    if not InCombatLockdown() then
      inputPaused = true; Keyboard(); X.OpenWizard(); ResumeAfter(X.wizardFrame)
    end
  end)
  button("Open Buff List", -282, function()
    if InCombatLockdown() or X.PlayerSuspended() then return end
    awaiting, inputPaused = true, true
    local window = X.GetFrame()
    if window and not window:IsShown() then X.ToggleWindow() end
    G.Refresh()
  end)
  if X.classic and X.OpenNearbyDiagnostics then
    frame.nearby = button("Nearby Player Diagnostics", -312, function()
      if InCombatLockdown() or X.PlayerSuspended() then return end
      inputPaused = true; Keyboard(); X.OpenNearbyDiagnostics(); ResumeAfter(_G.BuffRadarNearbyDiagnostics)
    end)
  end
  frame.report = button("Copy Support Report", -342, function() G.ShowReport() end)
  button("Close", -372, G.Close)
  frame:SetScript("OnHide", function() if active then G.Close() end end)
  frame:SetScript("OnMouseDown", function() inputPaused = false; Keyboard() end)
  frame:SetScript("OnKeyDown", function(self, key)
    if InCombatLockdown() then return end
    if key == "TAB" then
      local delta = IsShiftKeyDown and IsShiftKeyDown() and -1 or 1
      Focus(focus == 0 and (delta > 0 and 1 or #controls) or (focus - 1 + delta) % #controls + 1)
    elseif key == "ESCAPE" then G.Close()
    elseif key == "ENTER" or key == "SPACE" then
      if controls[focus] then controls[focus]:Click() end
    else self:SetPropagateKeyboardInput(true); return end
    self:SetPropagateKeyboardInput(false)
  end)
  frame:RegisterEvent("PLAYER_REGEN_DISABLED"); frame:RegisterEvent("PLAYER_REGEN_ENABLED")
  frame:RegisterEvent("PLAYER_DEAD"); frame:RegisterEvent("PLAYER_ALIVE"); frame:RegisterEvent("PLAYER_ENTERING_WORLD")
  frame:SetScript("OnEvent", function() if active then G.Refresh() end end)
  if UISpecialFrames then table.insert(UISpecialFrames, "BuffRadarFirstCast") end
end

function G.Open()
  G.Close()
  if not frame then Create() end
  generation, active, state, reason = generation + 1, true, "discovering", "discovering"
  inputPaused = false
  baseline = X.ObserveCastSuccess(Success)
  frame:Show(); G.Refresh()
end
function G.Frame() return frame end

-- Every serialized field is a fresh primitive validated against this schema.
-- Never traverse saves/profiles/rows/history or inspect raw errors to redact them.
function G.Report()
  local fields, truncated = {}, false
  local function put(key, value)
    if type(value) == "boolean" then value = value and "true" or "false"
    elseif type(value) == "number" then value = Number(value) and string.format("%.6g", value) or "unknown"
    elseif type(value) ~= "string" then value = "unknown" end
    fields[#fields + 1] = key .. "=" .. value
  end
  local function version(value, build)
    if not Readable(value) then return "unknown" end
    if build and Number(value) then value = string.format("%.0f", value) end
    if type(value) ~= "string" or #value > 24 then return "unknown" end
    return (build and value:match("^%d+$") or not build and value:match("^%d+%.%d+%.%d+$")) and value or "unknown"
  end
  local ok, clientVersion, build, _, interface = pcall(function() return GetBuildInfo() end)
  put("client.version", ok and version(clientVersion) or "unknown")
  put("client.build", ok and version(build, true) or "unknown")
  put("client.interface", ok and Number(interface) or nil)
  local localeOK, locale = pcall(function() return GetLocale() end)
  put("client.locale", localeOK and Enum(locale, { enUS=true, enGB=true, deDE=true, frFR=true, esES=true, ruRU=true, zhCN=true }) or "unknown")
  local metadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  local metaOK, addonVersion = pcall(function() return metadata("BuffRadar", "Version") end)
  put("addon.version", metaOK and version(addonVersion) or "unknown")
  put("addon.edition", X.classic and "Forever" or "Retail")
  put("addon.supported", Bool(X.supported))
  local db = Data(X.GetDB)
  put("settings.schema", Number(Field(db, "dbVersion")))
  for _, key in ipairs({ "includeSelf", "groupOnly", "hidden", "groupCast", "modClick", "assignmentEnabled", "sync" }) do
    local value = Field(db, key)
    put("settings." .. key, Bool(value))
  end
  put("settings.castMethod", Enum(Field(db, "castMethod"), { target=true, rank=true, id=true, macro=true }))
  put("settings.sortMode", Enum(Field(db, "sortMode"), { name=true, need=true, role=true, distance=true }))
  put("settings.roleFilter", Enum(Field(db, "roleFilter"), { ALL=true, TANK=true, HEALER=true, DAMAGER=true }))
  local countOK, profileCount = pcall(function() return X.ProfileCount() end)
  put("profiles.count", countOK and Number(profileCount) or nil)
  local contextOK, context = pcall(function() return X.Context() end)
  put("profiles.context", contextOK and Enum(context, { solo=true, world=true, dungeon=true, raid=true, pvp=true }) or "unknown")
  put("buffs.supported", BuffCount())
  local status, delivery = Data(X.Status.Diagnostics), Data(X.CastDelivery)
  put("discovery.state", Enum(Field(status, "state"), discoveryStates))
  put("discovery.actionable", Number(Field(status, "actionable")))
  put("discovery.expiring", Number(Field(status, "expiring")))
  put("discovery.partial", Bool(Field(status, "partial")))
  put("delivery.direct", Enum(Field(delivery, "directReason"), deliveryReasons))
  put("delivery.macro", Enum(Field(delivery, "reason"), deliveryReasons))
  put("guide.state", Enum(state, { inactive=true, discovering=true, blocked=true, ready=true, awaiting_user_cast=true, confirmed=true, paused=true }))
  put("cast.successSerial", X.CastSuccessSerial())
  put("errors.unclassified", Number(X.ScanFaultCount()))
  put("errors.scan", Number(X.ScanFaultCount()))
  put("errors.blocked", faultCounts.blocked)
  put("errors.forbidden", faultCounts.forbidden)
  local peers = Data(X.SyncPeerSnapshot)
  local peerCounts = Data(function() return Field(peers, "counts") end)
  put("sync.available", Bool(Field(peers, "available")))
  for _, key in ipairs({ "verified", "awaiting", "retrying", "unverified", "incompatible" }) do
    put("sync." .. key, Number(Field(peerCounts, key)))
  end
  local themes, addons = { custom=true }, {}
  for _, id in ipairs(X.THEME_ORDER) do themes[id] = true end
  for _, entry in ipairs(X.AUTO_THEME_ADDONS) do addons[entry[1]] = true end
  put("theme.selected", Enum(Field(db, "theme"), themes))
  put("theme.resolved", Enum(X.autoThemeResolved, themes))
  put("theme.addon", Enum(X.autoThemeAddon, addons))
  local timing = X.timings and Data(function() return rawget(X.timings, "scan") end) or {}
  local samples = Number(Field(timing, "n"))
  put("timing.scan.samples", samples)
  put("timing.scan.lastMs", samples and samples > 0 and Number(Field(timing, "last")) or nil)
  local lines, bytes = { "BuffRadarSupport/1" }, 64
  for _, line in ipairs(fields) do
    if bytes + #line + 1 > 16384 then truncated = true; break end
    lines[#lines + 1], bytes = line, bytes + #line + 1
  end
  table.insert(lines, 2, "report.truncated=" .. (truncated and "true" or "false"))
  return table.concat(lines, "\n")
end

function G.ShowReport()
  if active then inputPaused = true; Keyboard() end
  X.ShowExport(L["Technical details only. No player names or user text are included. Review and copy locally."]
    .. "\n\n" .. G.Report(), false, L["Support report"])
  if active then ResumeAfter(X.exportFrame) end
end
X.ext.firstcast = function() G.Open(); return true end
X.ext.support = function() G.ShowReport(); return true end
