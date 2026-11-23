-- BuffRadar - Extras: diagnostics (/br apicheck, buffcheck, perf), settings
-- diff, and Edit Mode support. Loaded after BuffRadar.lua; talks to it only
-- through the shared X table. New code for 1.12.0 lives here so the main file
-- stops growing (see docs/DECISIONS.md).
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, NS = ...
local X = NS and NS.X
if not X then return end

local Print, L = X.Print, X.L

---------------------------------------------------------------------------
-- Nearby detection details. Reading this panel never refreshes the cast queue.
---------------------------------------------------------------------------
local nearby

local function UpdateNearbyNameplates()
  local enabled = X.FriendlyPlatesOn()
  if nearby.lastNameplates ~= enabled then nearby.message:SetText("") end
  nearby.lastNameplates = enabled
  local status = enabled == true and L["On"] or enabled == false and L["Off"] or L["Unknown"]
  nearby.nameplates:SetText(string.format(L["Friendly nameplates: %s"], status))
  nearby.togglePlates:SetText(L[enabled and "Disable Friendly Nameplates" or "Enable Friendly Nameplates"])
  nearby.togglePlates:SetShown(enabled ~= nil)
  local namesOnly = X.ReadBooleanCVar(X.friendlyPlateNamesCVar)
  nearby.plateStyle:SetText(L[namesOnly and "Show Friendly Health Bars" or "Show Friendly Names Only"])
  nearby.plateStyle:SetShown(namesOnly ~= nil)
  nearby.restorePlates:SetShown(next(X.GetDB().plateRestore) ~= nil)
end

function X.UpdateNearbyPlateControls()
  if nearby and nearby:IsShown() then UpdateNearbyNameplates() end
end

function X.UpdateNearbyScanCount()
  if not nearby or not nearby:IsShown() or nearby.lastCount == X.playersSeen then return end
  nearby.lastCount = X.playersSeen
  nearby.count:SetText(X.playersSeen == nil   and   L["Player nameplates seen on last scan: unavailable"]
      or   string.format(L["Player nameplates seen on last scan: %d"], X.playersSeen))
end

local function UpdateNearbyTarget()
  local lines = {}
  X.ExplainCurrentTarget(function(line) lines[#lines + 1] = line end)
  nearby.details:SetText(table.concat(lines, "\n"))
  nearby.scrollChild:SetHeight(math.max(1, nearby.details:GetStringHeight() or 0))
  nearby.scroll:SetVerticalScroll(0)
end

function X.UpdateNearbyTargetAfterScan()
  if not nearby or not nearby.targetDirty or not nearby:IsShown()
    or X.PlayerSuspended() or InCombatLockdown() then return end
  nearby.targetDirty = nil
  UpdateNearbyTarget()
end

local function RefreshNearby()
  nearby.message:SetText("")
  UpdateNearbyNameplates()
  X.UpdateNearbyScanCount()
  UpdateNearbyTarget()
end

local function BuildNearby()
  local f = CreateFrame("Frame", "BuffRadarNearbyDiagnostics", UIParent)
  f:SetSize(480, 298)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

  local background = f:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints(f)
  background:SetColorTexture(0.06, 0.065, 0.095, 0.98)
  local function Label(font, y)
    local label = f:CreateFontString(nil, "OVERLAY", font)
    label:SetPoint("TOPLEFT", 14, y)
    label:SetPoint("TOPRIGHT", -14, y)
    label:SetJustifyH("LEFT")
    return label
  end
  local title = Label("GameFontNormalLarge", -12)
  title:SetPoint("TOPRIGHT", -32, -12)
  title:SetText(L["Nearby Player Diagnostics"])
  local close = X.PanelWidget("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -3, -3)
  close:SetScript("OnClick", function() f:Hide() end)
  f.nameplates = Label("GameFontHighlight", -45)
  f.count = Label("GameFontHighlight", -65)
  local targetTitle = Label("GameFontNormal", -92)
  targetTitle:SetText(L["Current Target"])

  local scroll = X.PanelWidget("ScrollFrame", "BuffRadarNearbyScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -112)
  scroll:SetPoint("BOTTOMRIGHT", -30, 108)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(436, 1)
  scroll:SetScrollChild(child)
  f.scroll, f.scrollChild = scroll, child
  f.details = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.details:SetPoint("TOPLEFT", 0, 0)
  f.details:SetPoint("TOPRIGHT", 0, 0)
  f.details:SetJustifyH("LEFT")
  f.details:SetJustifyV("TOP")
  f.details:SetWordWrap(true)
  f.message = Label("GameFontHighlightSmall", -196)
  f.message:SetWordWrap(true)
  f.message:SetJustifyV("TOP")

  local function PlateButton(width, point, x, y, chooseMode)
    local btn = X.PanelWidget("Button", nil, f, "UIPanelButtonTemplate")
    btn:SetSize(width, 22)
    btn:SetPoint(point, x, y)
    btn:SetScript("OnClick", function()
      if not f:IsShown() or not btn:IsShown() or X.PlayerSuspended() or InCombatLockdown() then return end
      local mode = chooseMode()
      if not mode then return end
      local message
      X.ChangeFriendlyNameplates(mode, function(line) message = line end)
      f.message:SetText(message   or   "")
    end)
    return btn
  end
  f.togglePlates = PlateButton(266, "BOTTOMLEFT", 14, 42, function()
    local enabled = X.FriendlyPlatesOn()
    if enabled ~= nil then return enabled and "off" or "on" end
  end)
  f.plateStyle = PlateButton(266, "BOTTOMLEFT", 14, 12, function()
    local namesOnly = X.ReadBooleanCVar(X.friendlyPlateNamesCVar)
    if namesOnly ~= nil then return namesOnly and "bars" or "names" end
  end)
  f.restorePlates = PlateButton(176, "BOTTOMRIGHT", -14, 42, function() return "restore" end)
  f.restorePlates:SetText(L["Restore Nameplates"])

  local refresh = X.PanelWidget("Button", nil, f, "UIPanelButtonTemplate")
  refresh:SetSize(110, 22)
  refresh:SetPoint("BOTTOMRIGHT", -14, 12)
  refresh:SetText(L["Refresh"])
  refresh:SetScript("OnClick", function()
    if f:IsShown() and not X.PlayerSuspended() and not InCombatLockdown() then RefreshNearby() end
  end)
  f.refresh = refresh

  f:SetScript("OnShow", function(self)
    self:RegisterEvent("PLAYER_TARGET_CHANGED")
    self:RegisterEvent("CVAR_UPDATE")
  end)
  f:SetScript("OnHide", function(self)
    self.targetDirty = nil
    self:UnregisterEvent("PLAYER_TARGET_CHANGED")
    self:UnregisterEvent("CVAR_UPDATE")
  end)
  f:SetScript("OnEvent", function(self, event)
    if not self:IsShown() or X.PlayerSuspended() or InCombatLockdown() then return end
    if event == "PLAYER_TARGET_CHANGED" then
      self.targetDirty = true
      UpdateNearbyTarget()
    elseif event == "CVAR_UPDATE" then
      UpdateNearbyNameplates()
    end
  end)
  if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "BuffRadarNearbyDiagnostics" end
  f:Hide()
  return f
end

function X.OpenNearbyDiagnostics()
  if not X.classic or X.PlayerSuspended() or not X.SecureActionAllowed() then return end
  if X.DiagnosticsPaused and X.DiagnosticsPaused() then return end
  nearby = nearby or BuildNearby()
  nearby.lastCount = false  -- a new opening should render even without a completed scan
  nearby:Show()
  RefreshNearby()
end

function X.CloseNearbyDiagnostics()
  if nearby then nearby:Hide() end
end

-- Every optional API gets looked at through these, never called unguarded.
local function Has(path)
  local t = _G
  for part in path:gmatch("[^%.]+") do
    if type(t) ~= "table" then return false end
    t = t[part]
    if t == nil then return false end
  end
  return true
end

local function Yes(v) return v and "|cff00ff00yes|r" or "|cffff4040no|r" end

-- An API that exists is not the same as an API that answers. This client can
-- hand back values that cannot be read, and a presence check cannot tell the
-- difference, so each one is called and its result classified. "restricted"
-- is the case that breaks features while every presence check still says yes.
local function Answers(api, ...)
  if type(api) ~= "function" then return "absent" end
  local ok, value = pcall(api, ...)
  if not ok then return "|cffff4040errors|r" end
  if type(value) == "nil" then return "nil" end
  if X.Readable and not X.Readable(value) then return "|cffff4040restricted|r" end
  return "|cff00ff00readable|r"
end

-- The most informative unit is a player outside your group, because that is
-- the case the group-range API refuses to describe. Prefer the target, then
-- any player nameplate, and fall back to the player.
local function ProbeUnit()
  if X.UnitPresent("target") and X.ReadUnitBool(UnitIsPlayer, "target") == true
     and X.IsSelf("target") == false then return "target", "your target" end
  for i = 1, 40 do
    local u = "nameplate" .. i
    if X.UnitPresent(u) and X.ReadUnitBool(UnitIsPlayer, u) == true then
      return u, "a player nameplate"
    end
  end
  return "player", "yourself -- target a nearby player for a fuller picture"
end

-- Which rung of the range chain, if any, gives a readable answer for a unit.
local function RangeVerdict(unit, spell)
  if Answers(C_Spell and C_Spell.IsSpellInRange, spell, unit):find("readable") then
    return "spell range answers"
  end
  if Answers(IsSpellInRange, spell, unit):find("readable") then
    return "legacy spell range answers"
  end
  if type(UnitInRange) == "function" then
    local ok, inRange, checked = pcall(UnitInRange, unit)
    if ok and X.Readable and X.Readable(checked) and checked == true
       and X.Readable(inRange) then return "group range answers" end
  end
  if Answers(CheckInteractDistance, unit, 4):find("readable") then
    return "interaction distance answers"
  end
  return nil  -- nothing answered
end

---------------------------------------------------------------------------
-- /br apicheck: which client APIs BuffRadar relies on exist right now.
-- Paste the output in a bug report; it replaces guessing about a build.
---------------------------------------------------------------------------
local WANT = {
  "C_UnitAuras.GetBuffDataByIndex", "C_UnitAuras.GetAuraDataBySpellName", "C_UnitAuras.GetAuraDataByAuraInstanceID", "UnitBuff",
  "C_Spell.GetSpellName", "C_Spell.GetSpellTexture", "C_Spell.IsSpellInRange", "C_Spell.GetSpellCooldown",
  "C_SpellBook.IsSpellKnown", "IsSpellKnown", "UnitInRange", "CheckInteractDistance",
  "GetWeaponEnchantInfo", "GetInventoryItemID", "GetSpecialization", "UnitGroupRolesAssigned",
  "C_ChatInfo.SendAddonMessage", "C_Timer.After", "SetPortraitTexture",
  "issecretvalue", "canaccessvalue", "EditModeManagerFrame", "debugprofilestop",
}

function X.ApiCheck(export)
  if X.DiagnosticsPaused and X.DiagnosticsPaused() then return end
  local ver, build, _, iface = GetBuildInfo()
  local lines = {}
  local function out(text, plain)
    lines[#lines + 1] = plain or text
    if not export then Print(text) end
  end
  out(string.format("API check -- client %s build %s interface %s:", tostring(ver), tostring(build), tostring(iface)))
  local missing = 0
  for _, path in ipairs(WANT) do
    local ok = Has(path)
    if not ok then missing = missing + 1 end
    out(string.format("  %-40s %s", path, Yes(ok)), string.format("  %-40s %s", path, ok and "yes" or "NO"))
  end
  -- Weapon-enchant discovery: any API whose name suggests a temporary weapon
  -- enchant, so a replacement for GetWeaponEnchantInfo can be named from
  -- evidence instead of guessed.
  local hits = {}
  for k, v in pairs(_G) do
    if type(k) == "string" and type(v) == "function" and (k:find("WeaponEnchant", 1, true) or k:find("TempEnchant", 1, true)) then
      hits[#hits + 1] = k
    end
  end
  for _, ns in ipairs({ "C_Item", "C_TooltipInfo", "C_Container" }) do
    local t = _G[ns]
    if type(t) == "table" then
      for k, v in pairs(t) do
        if type(k) == "string" and type(v) == "function" and (k:find("Enchant", 1, true)) then hits[#hits + 1] = ns .. "." .. k end
      end
    end
  end
  table.sort(hits)
  out("  weapon-enchant candidates: " .. (#hits > 0 and table.concat(hits, ", ") or "none found"))
  out(string.format("  %d of %d listed APIs missing. A missing optional API is handled; missing ones BuffRadar needs are marked in /br debug.", missing, #WANT))
  -- Readability tier: the presence table above cannot see a restricted
  -- result, which is the failure that actually hides players from the list.
  local unit, unitWhy = ProbeUnit()
  local buffs = X.Core.Buffs
  local spell = (buffs and buffs[1] and buffs[1].name) or "Arcane Intellect"
  out(string.format("  readability on %s (%s), spell %s:", unit, unitWhy, spell))
  local PROBES = {
    { "C_Spell.IsSpellInRange", C_Spell and C_Spell.IsSpellInRange, spell, unit },
    { "IsSpellInRange", IsSpellInRange, spell, unit },
    { "CheckInteractDistance", CheckInteractDistance, unit, 4 },
    { "UnitCanAssist", UnitCanAssist, "player", unit },
    { "UnitIsPlayer", UnitIsPlayer, unit },
    { "UnitIsDeadOrGhost", UnitIsDeadOrGhost, unit },
    { "UnitIsConnected", UnitIsConnected, unit },
    { "UnitAffectingCombat", UnitAffectingCombat, unit },
    { "UnitIsCharmed", UnitIsCharmed, unit },
    { "UnitInPhase", UnitInPhase, unit },
    { "UnitIsPVP", UnitIsPVP, unit },
    { "UnitLevel", UnitLevel, unit },
    { "GetRaidTargetIndex", GetRaidTargetIndex, unit },
    { "UnitGroupRolesAssigned", UnitGroupRolesAssigned, unit },
  }
  for _, p in ipairs(PROBES) do
    local state = Answers(p[2], p[3], p[4])
    out(string.format("    %-24s %s", p[1], state),
        string.format("    %-24s %s", p[1], (state:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))))
  end
  -- UnitInRange returns two values and both have to be readable to be usable.
  if type(UnitInRange) == "function" then
    local okR, inRange, checked = pcall(UnitInRange, unit)
    local function state(v)
      if not okR then return "errors" end
      if type(v) == "nil" then return "nil" end
      return (X.Readable and not X.Readable(v)) and "restricted" or "readable"
    end
    out(string.format("    %-24s inRange %s, checked %s", "UnitInRange",
      state(inRange), state(checked)))
  else
    out(string.format("    %-24s absent", "UnitInRange"))
  end
  local verdict = RangeVerdict(unit, spell)
  if verdict then
    out("  range verdict: " .. verdict .. " for this unit.")
  else
    out("  |cffff4040range verdict: no range API answers for this unit, so it cannot be listed.|r",
        "  range verdict: no range API answers for this unit, so it cannot be listed.")
    out("    /br assumerange lists players anyway, with their range shown as estimated.")
  end
  -- UNIT_AURA payload probe (1.14.0, Brief 2): what this client actually
  -- sends, counted by the event driver since login.
  local probe = X.auraProbe
  if probe and probe.seen then
    out(string.format("  UNIT_AURA payloads seen: %d (full %d, with adds %d, with removals %d, with updates %d, skipped by fast aura %d)",
      probe.seen, probe.full or 0, probe.added or 0, probe.removed or 0, probe.updated or 0, probe.skipped or 0))
  else
    out("  UNIT_AURA payloads seen: none yet (cast or receive a buff, then run this again)")
  end
  local pp = X.pullProbe
  if pp and ((pp.stSeen or 0) > 0 or (pp.d5 or 0) > 0) then
    local types = {}
    for ty in pairs(pp.stTypes or {}) do types[#types + 1] = tostring(ty) end
    table.sort(types)
    out(string.format("  Pull timers: START_TIMER seen %d (timerTypes: %s), DBM PT seen %d",
      pp.stSeen, #types > 0 and table.concat(types, ", ") or "?", pp.d5 or 0))
  else
    out("  Pull timers: none seen yet (start a /countdown or a boss-mod /pull in a group, then run this again)")
  end
  if export then X.ShowExport(table.concat(lines, "\n"), false, L["Copy Support Report"]) end
  return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Ignore list export / import (1.13.0): one line of names, copyable, so a
-- list moves between characters or accounts. /br ignorelist export|import.
---------------------------------------------------------------------------
function X.IgnoreExport()
  return "BRI1;" .. table.concat(X.Ignore.Sorted(), ";")
end

-- Same ceiling as the settings clipboard, so a pasted or shared string can't
-- flood the saved ignore list. The whole string is checked before anything
-- is added. "|" starts a game escape code and never appears in a player name.
X.IGNORE_IMPORT_MAX_BYTES = 16384
function X.IgnoreImport(text)
  if type(text) ~= "string" then return false, "Nothing to import." end
  if #text > X.IGNORE_IMPORT_MAX_BYTES then return false, "That import exceeds 16 KiB." end
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if text:sub(1, 5) ~= "BRI1;" then return false, "Not a BuffRadar ignore-list string (should start with BRI1;)." end
  local names = {}
  for name in (text:sub(6) .. ";"):gmatch("(.-);") do
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if X.Ignore.Valid(name) then names[#names + 1] = name end
  end
  local added, err = X.Ignore.AddMany(names)
  if not added then return false, err end
  local seen = #names
  if X.Refresh then X.Refresh() end
  return true, string.format(L["Ignore list: %d added, %d already there."], added, seen - added)
end

---------------------------------------------------------------------------
-- /br buffcheck: every spell id in the buff table against the live client.
---------------------------------------------------------------------------
local function SpellKnownToClient(id)
  if Has("C_Spell.GetSpellName") then
    local ok, n = pcall(C_Spell.GetSpellName, id)
    return ok and n ~= nil
  elseif GetSpellInfo then
    local ok, n = pcall(GetSpellInfo, id)
    return ok and n ~= nil
  end
  return nil
end

function X.BuffCheck()
  if X.DiagnosticsPaused and X.DiagnosticsPaused() then return end
  local bad, total = {}, 0
  for _, d in ipairs(X.BUFF_DEFS or {}) do
    local ids = {}
    if d.id then ids[#ids + 1] = { d.id, d.name } end
    if d.choices then for _, c in ipairs(d.choices) do ids[#ids + 1] = { c[1], c[2] } end end
    for _, pair in ipairs(ids) do
      total = total + 1
      local known = SpellKnownToClient(pair[1])
      if known == nil then
        Print(L["Buff check needs C_Spell.GetSpellName or GetSpellInfo; neither exists on this client."])
        return
      end
      if not known then bad[#bad + 1] = string.format("%s (%s, id %d)", d.key, tostring(pair[2]), pair[1]) end
    end
  end
  if #bad == 0 then
    Print(string.format(L["Buff check: all %d spell ids in the buff table exist on this client."], total))
  else
    Print(string.format(L["Buff check: %d of %d spell ids are unknown here (data may still be loading -- retry in a few seconds):"], #bad, total))
    for _, line in ipairs(bad) do Print("  " .. line) end
  end
end

---------------------------------------------------------------------------
-- /br perf: scan cost and memory, so the budgets have in-game evidence.
---------------------------------------------------------------------------
function X.PerfReport()
  if X.DiagnosticsPaused and X.DiagnosticsPaused() then return end
  for _, key in ipairs({ "scan", "prepare", "import", "debuff", "combatDebuff" }) do
    local t = X.timings[key]
    if t.n > 0 then
      Print(string.format(L["Perf: %s · %d samples · CPU average %.2f ms · last %.2f ms · worst %.2f ms"],
        key, t.n, t.total / t.n, t.last, t.max))
    end
  end
  if not debugprofilestop then Print(L["Perf: CPU timing unavailable (needs debugprofilestop)."]) end
  local probe = X.auraProbe
  if probe and probe.seen then
    Print(string.format(L["Perf: UNIT_AURA payloads %d · skipped by fast aura %d"],
      probe.seen, probe.skipped or 0))
  end
  local kb = X.Intel.MemoryKB()
  if kb then Print(string.format(L["Perf: addon memory %.0f KB"], kb)) end
  Print(X.Intel.PaceText())
end

---------------------------------------------------------------------------
-- Settings diff: what applying a settings string would change.
---------------------------------------------------------------------------
function X.SettingsDiff(text, named)
  if X.DiagnosticsPaused and X.DiagnosticsPaused() then
    return nil, L["Diagnostics are paused in Performance Mode."]
  end
  if type(text) ~= "string" then return nil, L["Paste a complete, valid BuffRadar settings export."] end
  local patch
  if named or text:match("^BR2;") then patch = X.ParseProfile(text) else patch = X.ParseSettingsImport(text) end
  if not patch then return nil, L["Paste a complete, valid BuffRadar settings export."] end
  return X.ReviewSettings(patch)
end

function X.PrintDiff(text, label, named)
  local lines, err = X.SettingsDiff(text, named)
  if not lines then Print(err); return end
  if #lines == 0 then Print(string.format(L["%s changes nothing."], (label  or  L["That string"]))); return end
  Print(string.format(L["%s: %d preference changes"],label or L["That string"],#lines))
  for i = 1, math.min(#lines, 30) do Print("  " .. lines[i]) end
  if #lines > 30 then Print(string.format(L["  ... and %d more"], #lines - 30)) end
end

---------------------------------------------------------------------------
-- Edit Mode: while the game's layout editor is open, the window is shown
-- and draggable even if locked; closing it puts everything back.
---------------------------------------------------------------------------
function X.InitEditMode()
  if not (_G.EditModeManagerFrame and _G.hooksecurefunc) then return end
  local saved
  local function enter()
    local db, f = X.GetDB(), X.GetFrame()
    if not db or not f or InCombatLockdown() or X.PlayerSuspended() then return end
    saved = { locked = db.locked, shown = f:IsShown() }
    db.locked = false
    f:Show()
    X.ApplyAppearance()
  end
  local function leave(suspended)
    local db, f = X.GetDB(), X.GetFrame()
    if not db or not f or not saved then return end
    db.locked = saved.locked
    if not suspended and not InCombatLockdown() then
      if not saved.shown and X.Refresh then X.Refresh() end
      X.PositionSave()
      X.ApplyAppearance()
    end
    saved = nil
  end
  X.EndEditMode = leave
  pcall(hooksecurefunc, _G.EditModeManagerFrame, "EnterEditMode", enter)
  pcall(hooksecurefunc, _G.EditModeManagerFrame, "ExitEditMode", function() leave(false) end)
end

---------------------------------------------------------------------------
-- Pull timers (1.14.0, Brief 4 -- un-parked from the 50-item program's #8).
-- Sources, in the order they were verified from the boss mods' own code:
--   1. the native group countdown: START_TIMER (timerType, timeRemaining,
--      totalTime), started by /countdown or C_PartyInfo.DoCountdown --
--      BigWigs' own /pull rides this same path;
--   2. DBM addon comms on prefix "D5", sub-prefix "PT" (tab-separated),
--      accepted only from a trusted sender (X.SenderTrusted).
-- Which of these Forever actually delivers is PROBE evidence, not a
-- promise: every sighting is counted in X.pullProbe and /br apicheck
-- reports it. The feature itself (border flash + countdown line) is
-- display only and off until /br pullflash on.
---------------------------------------------------------------------------
X.pullProbe = { stSeen = 0, stTypes = {}, d5 = 0 }
X.pull = nil

local function PullScope()
  return X.InRaid() and "RAID" or X.InGroup() and "PARTY" or "solo"
end

local function PullOwnerPresent(owner)
  if not owner or X.UnitGUIDOf("player") == owner then return true end
  local present = false
  X.ForReportRoster(function(unit, exists)
    if exists and X.UnitGUIDOf(unit) == owner then present = true end
  end)
  return present
end

local function StopPull(source, owner, timerID)
  local active = X.pull
  if active and active.source == source and active.owner == owner and active.scope == PullScope()
    and not active.ambiguousStop and active.timerID == timerID and PullOwnerPresent(owner)
    and (source ~= "boss mod" or timerID ~= nil)
    and (owner or active.scope == "solo" or active.membership == X.GroupIdentity()) then
    X.pull = nil
    X.Core.QueueRefresh()
  end
end

local function FinishPull(pull)
  if X.pull ~= pull then return end
  X.pull = nil
  if not pull.forecastOnly and X.GetDB().pullFlash and X.Flash then X.Flash() end
  X.Core.QueueRefresh()
end

-- The existing throttled ticker owns expiry on clients without C_Timer.
function X.TickPull()
  local pull = X.pull
  if not pull or (C_Timer and C_Timer.After) then return end
  local left = pull.endsAt - GetTime()
  if left <= 0 then FinishPull(pull)
  elseif left <= 3 and not pull.warned and not pull.forecastOnly then
    pull.warned = true
    if X.GetDB().pullFlash and X.Flash then X.Flash() end
  end
end

function X.CheckPullRoster()
  local pull = X.pull
  if not pull then return end
  local trusted = not pull.sender or X.SenderTrusted(pull.sender)
  local membership = not pull.owner and X.GroupIdentity() or nil
  if pull.scope ~= PullScope() or not trusted or not PullOwnerPresent(pull.owner)
    or (not pull.owner and pull.membership ~= membership) then
    X.pull = nil
    X.Core.QueueRefresh()
  end
end

function X.PullStart(secs, source, owner, timerID, sender)
  if not X.Readable(secs) or type(secs) ~= "number" or not (secs >= 0 and secs <= 600) then return end
  if secs == 0 then StopPull(source, owner, timerID); return end
  local db = X.GetDB()
  if not db or (not db.pullFlash and not X.Intel.ForecastEnabled()) then return end
  if InCombatLockdown() or X.PlayerSuspended() or not PullOwnerPresent(owner) then return end
  local casts = 0
  if db.pullFlash then
    for _, tt in pairs(X.tally or {}) do casts = casts + (tt.miss or 0) end
  end
  local flash = casts > 0
  if not flash and not X.Intel.ForecastEnabled() then return end
  local now, scope, previous = GetTime(), PullScope(), X.pull
  local membership = not owner and X.GroupIdentity() or nil
  if not owner and scope ~= "solo" and not membership then return end
  local ends = now + secs
  local sameSource = previous and previous.source == source and previous.scope == scope and previous.endsAt > now
  if sameSource and math.abs(previous.endsAt - ends) < 0.75 and (not previous.owner or not owner or previous.owner == owner)
    and previous.timerID == timerID then
    if owner then previous.owner, previous.sender = owner, sender end
    return -- paired native notifications or repeat of an already running timer
  end
  local ambiguous = sameSource and previous.owner == owner
    and (not previous.timerID or not timerID or previous.timerID == timerID)
  local pull = { endsAt = ends, source = source, forecastOnly = not flash, owner = owner,
    timerID = timerID, sender = sender, scope = scope, ambiguousStop = ambiguous,
    membership = membership }
  X.pull = pull
  if flash then
    Print(string.format(L["Pull in %ds (%s) -- %d casts still needed."], secs, source, casts))
    if X.Flash then X.Flash() end
  end
  if X.Intel.ForecastEnabled() then X.Core.QueueRefresh() end
  if C_Timer and C_Timer.After then
    if flash and secs > 3 then
      C_Timer.After(secs - 3, function()
        if X.pull == pull and db.pullFlash and X.Flash then X.Flash() end
      end)
    end
    C_Timer.After(secs, function() FinishPull(pull) end)
  end
end

if X.supported then
  local pf = CreateFrame("Frame")
  X.pullFrame = pf
  pf:RegisterEvent("ADDON_LOADED")
  local playerCountdown = Enum and Enum.StartTimerType and Enum.StartTimerType.PlayerCountdown or 2
  for _, event in ipairs({ "START_TIMER", "START_PLAYER_COUNTDOWN", "CANCEL_PLAYER_COUNTDOWN", "STOP_TIMER_OF_TYPE" }) do
    pcall(pf.RegisterEvent, pf, event)
  end
  pf:RegisterEvent("CHAT_MSG_ADDON")
  pf:SetScript("OnEvent", function(_, ev, a1, a2, a3, a4)
    local probe = X.pullProbe
    if ev == "ADDON_LOADED" then
      if a1 == "BuffRadar" then
        pf:UnregisterEvent("ADDON_LOADED")
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
          pcall(C_ChatInfo.RegisterAddonMessagePrefix, "D5")
        end
      end
      return
    end
    if ev == "START_TIMER" then
      probe.stSeen = probe.stSeen + 1
      if X.Readable(a1) and type(a1) == "number" and a1 >= 0 and a1 <= 10 then probe.stTypes[a1] = true end
      if X.Readable(a1) and a1 == playerCountdown then X.PullStart(a2, "countdown") end
    elseif ev == "START_PLAYER_COUNTDOWN" then
      -- Native IDful stops carry the initiator's GUID, not a timer number.
      local guid = X.Core.SafeString(a1)
      if guid and guid ~= "" and #guid <= 85 then X.PullStart(a2, "countdown", guid) end
    elseif ev == "CANCEL_PLAYER_COUNTDOWN" then
      local guid = X.Core.SafeString(a1)
      if guid and guid ~= "" then StopPull("countdown", guid) end
    elseif ev == "STOP_TIMER_OF_TYPE" and X.Readable(a1) and a1 == playerCountdown then
      StopPull("countdown")
    elseif ev == "CHAT_MSG_ADDON" and X.Readable(a1) and a1 == "D5"
      and type(a2) == "string" and X.Readable(a2) and #a2 <= 255 then
      local sub, rest = a2:match("^(%u+)%s+(.+)$")
      if sub == "PT" then
        probe.d5 = probe.d5 + 1
        if not X.Readable(a3) or a3 == "solo" or a3 ~= PullScope() then return end
        local secs, map = rest:match("^(%d+)\t(%d+)$")
        secs = secs or rest:match("^(%d+)$")
        if not secs then return end
        local unit, sender = X.SenderUnit(a4)
        local owner = unit and X.SenderTrusted(a4) and X.UnitGUIDOf(unit)
        if owner then X.PullStart(tonumber(secs), "boss mod", owner, map ~= "" and map or nil, sender) end
      end
      return
    end
  end)
end

---------------------------------------------------------------------------
-- Slash registration (dispatched by Slash.lua)
---------------------------------------------------------------------------
X.ext.apicheck = function(rest) X.ApiCheck(rest == "export") end
X.ext.ignorelist = function(rest)
  if rest == "export" then X.ShowExport(X.IgnoreExport(), false, L["Ignored players"])
  elseif rest == "import" then X.ShowExport("", true, L["Ignored players"], "ignore")
  else Print(L["Usage: /br ignorelist export | import"]) end
end
X.ext.buffcheck = function() X.BuffCheck() end
X.ext.perf = function() X.PerfReport() end
X.ext.diff = function(rest)
  X.PrintDiff(rest, L["That string"])
end

if X.supported then X.InitEditMode() end
