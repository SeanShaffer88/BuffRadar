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

---------------------------------------------------------------------------
-- /br apicheck: which client APIs BuffRadar relies on exist right now.
-- Paste the output in a bug report; it replaces guessing about a build.
---------------------------------------------------------------------------
local WANT = {
  "C_UnitAuras.GetBuffDataByIndex", "C_UnitAuras.GetAuraDataBySpellName", "UnitBuff",
  "C_Spell.GetSpellName", "C_Spell.GetSpellTexture", "C_Spell.IsSpellInRange", "C_Spell.GetSpellCooldown",
  "C_SpellBook.IsSpellKnown", "IsSpellKnown", "UnitInRange", "CheckInteractDistance",
  "GetWeaponEnchantInfo", "GetInventoryItemID", "GetSpecialization", "UnitGroupRolesAssigned",
  "C_ChatInfo.SendAddonMessage", "C_Timer.After", "SetPortraitTexture",
  "issecretvalue", "canaccessvalue", "EditModeManagerFrame", "debugprofilestop",
}

function X.ApiCheck()
  local ver, build, _, iface = GetBuildInfo()
  Print(string.format("API check -- client %s build %s interface %s:", tostring(ver), tostring(build), tostring(iface)))
  local missing = 0
  for _, path in ipairs(WANT) do
    local ok = Has(path)
    if not ok then missing = missing + 1 end
    Print(string.format("  %-40s %s", path, Yes(ok)))
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
  Print("  weapon-enchant candidates: " .. (#hits > 0 and table.concat(hits, ", ") or "none found"))
  Print(string.format("  %d of %d listed APIs missing. A missing optional API is handled; missing ones BuffRadar needs are marked in /br debug.", missing, #WANT))
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

function X.SettingsDiff(text)
  if type(text) ~= "string" or text:sub(1, 3) ~= "BR1" then return nil, "Not a BuffRadar settings string." end
  local want, have = Parse(text), Parse(X.Export())
  local lines = {}
  local keys = {}
  for k in pairs(want) do keys[k] = true end
  for k in pairs(have) do keys[k] = true end
  local names = {}
  for k in pairs(keys) do names[#names + 1] = k end
  table.sort(names)
  for _, k in ipairs(names) do
    if k:find("^ignored%.") or k:find("^enabled%.") or k:find("^rebuffPer%.") or not k:find("%.") then
      local a, b = have[k], want[k]
      if a ~= b and (b ~= nil) then
        lines[#lines + 1] = string.format("%s: %s -> %s", k, tostring(a), tostring(b))
      end
    end
  end
  return lines
end

function X.PrintDiff(text, label)
  local lines, err = X.SettingsDiff(text)
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
    if not db or not f or InCombatLockdown() then return end
    saved = { locked = db.locked, shown = f:IsShown() }
    db.locked = false
    f:Show()
    X.ApplyAppearance()
  end
  local function leave()
    local db, f = X.GetDB(), X.GetFrame()
    if not db or not f or not saved or InCombatLockdown() then return end
    db.locked = saved.locked
    if not saved.shown and X.Refresh then X.Refresh() end
    X.PositionSave()
    X.ApplyAppearance()
    saved = nil
  end
  pcall(hooksecurefunc, _G.EditModeManagerFrame, "EnterEditMode", enter)
  pcall(hooksecurefunc, _G.EditModeManagerFrame, "ExitEditMode", leave)
end

---------------------------------------------------------------------------
-- Slash registration (dispatched from BuffRadar.lua's HandleSlash)
---------------------------------------------------------------------------
X.ext.apicheck = function() X.ApiCheck() end
X.ext.buffcheck = function() X.BuffCheck() end
X.ext.perf = function() X.PerfReport() end
X.ext.diff = function(rest)
  X.PrintDiff(rest, "That string")
end

X.InitEditMode()
