-- BuffRadar - Extras: diagnostics (/br apicheck, buffcheck, perf), settings
-- diff, and Edit Mode support. Loaded after BuffRadar.lua; talks to it only
-- through the shared X table. New code for 1.12.0 lives here so the main file
-- stops growing (see docs/DECISIONS.md).
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, NS = ...
local X = NS and NS.X
if not X then return end

local Print = X.Print

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
  if UnitExists("target") and X.ReadUnitBool(UnitIsPlayer, "target") == true
     and X.IsSelf("target") == false then return "target", "your target" end
  for i = 1, 40 do
    local u = "nameplate" .. i
    if UnitExists(u) and X.ReadUnitBool(UnitIsPlayer, u) == true then
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
  local buffs = X.slashAPI and X.slashAPI.myBuffs
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
  if pp and (pp.stSeen or 0) > 0 then
    local types = {}
    for ty in pairs(pp.stTypes or {}) do types[#types + 1] = tostring(ty) end
    table.sort(types)
    out(string.format("  Pull timers: START_TIMER seen %d (timerTypes: %s), DBM PT seen %d",
      pp.stSeen, #types > 0 and table.concat(types, ", ") or "?", pp.d5 or 0))
  else
    out("  Pull timers: none seen yet (start a /countdown or a boss-mod /pull in a group, then run this again)")
  end
  if export then X.ShowExport(table.concat(lines, "\n"), false, "BuffRadar API check -- select all, copy") end
  return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Ignore list export / import (1.13.0): one line of names, copyable, so a
-- list moves between characters or accounts. /br ignorelist export|import.
---------------------------------------------------------------------------
function X.IgnoreExport()
  return "BRI1;" .. table.concat(X.Ignore.Sorted(), ";")
end

function X.IgnoreImport(text)
  if type(text) ~= "string" then return false, "Nothing to import." end
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if text:sub(1, 5) ~= "BRI1;" then return false, "Not a BuffRadar ignore-list string (should start with BRI1;)." end
  local added, seen = 0, 0
  for name in (text:sub(6) .. ";"):gmatch("(.-);") do
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name ~= "" and #name <= 64 and not name:find("[%c]") then
      seen = seen + 1
      if X.Ignore.Add(name) then added = added + 1 end
    end
  end
  if X.Refresh then X.Refresh() end
  return true, string.format("Ignore list: %d added, %d already there.", added, seen - added)
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
  local bad, total = {}, 0
  for _, d in ipairs(X.BUFF_DEFS or {}) do
    local ids = {}
    if d.id then ids[#ids + 1] = { d.id, d.name } end
    if d.choices then for _, c in ipairs(d.choices) do ids[#ids + 1] = { c[1], c[2] } end end
    for _, pair in ipairs(ids) do
      total = total + 1
      local known = SpellKnownToClient(pair[1])
      if known == nil then
        Print("Buff check needs C_Spell.GetSpellName or GetSpellInfo; neither exists on this client.")
        return
      end
      if not known then bad[#bad + 1] = string.format("%s (%s, id %d)", d.key, tostring(pair[2]), pair[1]) end
    end
  end
  if #bad == 0 then
    Print(string.format("Buff check: all %d spell ids in the buff table exist on this client.", total))
  else
    Print(string.format("Buff check: %d of %d spell ids are unknown here (data may still be loading -- retry in a few seconds):", #bad, total))
    for _, line in ipairs(bad) do Print("  " .. line) end
  end
end

---------------------------------------------------------------------------
-- /br perf: scan cost and memory, so the budgets have in-game evidence.
---------------------------------------------------------------------------
function X.PerfReport()
  local pf = X.perf
  if not pf or pf.n == 0 then Print("Perf: no scans timed yet (needs debugprofilestop)."); return end
  Print(string.format("Perf: %d scans · average %.2f ms · last %.2f ms · worst %.2f ms",
    pf.n, pf.total / pf.n, pf.last, pf.max))
  local probe = X.auraProbe
  if probe and probe.seen then
    Print(string.format("Perf: UNIT_AURA payloads %d · skipped by fast aura %d",
      probe.seen, probe.skipped or 0))
  end
  local getMem = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or _G.GetAddOnMemoryUsage
  local upd = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or _G.UpdateAddOnMemoryUsage
  if getMem then
    if upd then pcall(upd) end
    local ok, kb = pcall(getMem, "BuffRadar")
    if ok and type(kb) == "number" then Print(string.format("Perf: addon memory %.0f KB", kb)) end
  end
end

---------------------------------------------------------------------------
-- Settings diff: what applying a settings string would change.
---------------------------------------------------------------------------
local function Parse(text)
  local out = {}
  if type(text) ~= "string" then return out end
  for part in (text .. ";"):gmatch("(.-);") do
    local k, v = part:match("^(.-)=(.*)$")
    if k then out[k] = v end
  end
  return out
end

function X.SettingsDiff(text, named)
  if type(text) ~= "string" then return nil, "Not a BuffRadar settings string." end
  local profile = text:match("^BR2;") ~= nil
  local patch, body
  if profile or named then
    patch, body = X.ParseProfile(text), text
  else
    patch, body = X.ParseSettingsImport(text)
  end
  if not patch then return nil, "Not a complete, valid BuffRadar settings string." end
  local current, err
  if profile then
    current = X.ProfileSnapshot()
    if not current then return nil, "Current settings exceed the profile size limit." end
  else
    current, err = X.Export()
    if not current then return nil, err end
  end
  local want, have = Parse(body), Parse(current)
  if patch.assumeRange == false and want.assumeRange == nil then want.assumeRange = "0" end
  local lines = {}
  local keys = {}
  for k in pairs(want) do keys[k] = true end
  for k in pairs(have) do keys[k] = true end
  local names = {}
  for k in pairs(keys) do names[#names + 1] = k end
  table.sort(names)
  for _, k in ipairs(names) do
    local map = k:match("^(%a+)%.")
    if (map and patch[map] ~= nil) or patch[k] ~= nil then
      local a, b = have[k], want[k]
      if a ~= b then
        lines[#lines + 1] = string.format("%s: %s -> %s", k, tostring(a), tostring(b))
      end
    end
  end
  return lines
end

function X.PrintDiff(text, label, named)
  local lines, err = X.SettingsDiff(text, named)
  if not lines then Print(err); return end
  if #lines == 0 then Print((label or "That string") .. " changes nothing."); return end
  Print(string.format("%s would change %d setting%s:", label or "That string", #lines, #lines == 1 and "" or "s"))
  for i = 1, math.min(#lines, 30) do Print("  " .. lines[i]) end
  if #lines > 30 then Print(string.format("  ... and %d more", #lines - 30)) end
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

function X.PullStart(secs, source)
  local probe = X.pullProbe
  probe.lastSource, probe.lastSecs = source, secs
  if secs <= 0 then X.pull = nil; return end  -- a zero timer is a cancel
  local db = X.GetDB and X.GetDB()
  if not db or not db.pullFlash then return end
  if InCombatLockdown and InCombatLockdown() then return end
  local casts = 0
  for _, tt in pairs(X.tally or {}) do casts = casts + (tt.miss or 0) end
  if casts <= 0 then return end
  X.pull = { endsAt = GetTime() + secs, source = source }
  Print(string.format("Pull in %ds (%s) -- %d casts still needed.", secs, source, casts))
  if X.Flash then X.Flash() end
  if C_Timer and C_Timer.After then
    if secs > 3 then
      C_Timer.After(secs - 3, function() if X.pull then if X.Flash then X.Flash() end end end)
    end
    C_Timer.After(secs, function()
      if X.pull then
        X.pull = nil
        if X.Flash then X.Flash() end
        if X.Refresh then X.Refresh() end
      end
    end)
  end
end

do
  local pf = CreateFrame("Frame")
  X.pullFrame = pf
  pf:RegisterEvent("ADDON_LOADED")
  pf:RegisterEvent("START_TIMER")
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
      if a1 ~= nil then probe.stTypes[a1] = true end
      local secs = (type(a2) == "number" and a2) or (type(a3) == "number" and a3) or 0
      X.PullStart(secs, "countdown")
      return
    end
    if ev == "CHAT_MSG_ADDON" and X.Readable(a1) and a1 == "D5"
      and type(a2) == "string" and X.Readable(a2) then
      local sub, rest = a2:match("^(%u+)%s+(.+)$")
      if sub == "PT" then
        probe.d5 = probe.d5 + 1
        probe.d5last = a2:sub(1, 24)
        local secs = tonumber((rest or ""):match("(%d+)"))
        if secs and X.SenderTrusted and X.SenderTrusted(a4) then
          X.PullStart(secs, "boss mod")
        end
      end
      return
    end
  end)
end

---------------------------------------------------------------------------
-- Slash registration (dispatched from BuffRadar.lua's HandleSlash)
---------------------------------------------------------------------------
X.ext.apicheck = function(rest) X.ApiCheck(rest == "export") end
X.ext.ignorelist = function(rest)
  if rest == "export" then X.ShowExport(X.IgnoreExport(), false, "BuffRadar ignore list -- select all, copy")
  elseif rest == "import" then X.ShowExport("", true, "BuffRadar -- paste an ignore-list string, then Import", "ignore")
  else Print("Usage: /br ignorelist export | import") end
end
X.ext.buffcheck = function() X.BuffCheck() end
X.ext.perf = function() X.PerfReport() end
X.ext.diff = function(rest)
  X.PrintDiff(rest, "That string")
end

X.InitEditMode()
