-- BuffRadar - optional personal checks for the Raid Preparation panel.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local X = ns.X
local R, L, Print = {}, X.L, X.Print
X.Readiness = R

-- Ranked classic stones, including the Improved Healthstone variants.
local stones = { 5512, 19004, 19005, 5511, 19006, 19007, 5509, 19008, 19009,
  5510, 19010, 19011, 9421, 19012, 19013 }
local gearSlots = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }

local function Healthstone()
  local modern = C_Item and C_Item.GetItemCount
  local read = modern or GetItemCount
  local incomplete = false
  for _, id in ipairs(stones) do
    local count
    if modern then count = X.ReadUnitNumber(read, id, false, false, false, false)
    else count = X.ReadUnitNumber(read, id, false, false) end
    if count and count > 0 then return true end
    if not count or count < 0 then incomplete = true end
  end
  if not incomplete then return false end
end

local function Tuple(...) return select("#", ...), ... end
local function Durability(slot) return Tuple(GetInventoryItemDurability(slot)) end

local function Repairs()
  if type(GetInventoryItemDurability) ~= "function" then return L["Unknown"] end
  local lowest, broken, incomplete = nil, 0, false
  for _, slot in ipairs(gearSlots) do
    local ok, n, current, maximum = pcall(Durability, slot)
    if not ok or n == 0 then
      incomplete = true
    elseif type(current) ~= "nil" or type(maximum) ~= "nil" then
      if X.Readable(current) and X.Readable(maximum) and type(current) == "number" and type(maximum) == "number"
        and maximum > 0 and maximum < math.huge and current >= 0 and current <= maximum then
        local percent = math.floor(current / maximum * 100)
        lowest = math.min(lowest or 100, percent)
        if current == 0 then broken = broken + 1 end
      else
        incomplete = true
      end
    end
  end
  if not lowest then return L[incomplete and "Unknown" or "No durable equipment"] end
  local reading = broken > 0 and string.format(L["%d broken · Lowest %d%%"], broken, lowest)
    or string.format(L["Lowest %d%%"], lowest)
  if lowest <= 30 then reading = reading .. " · " .. L["Repair recommended"] end
  return incomplete and (reading .. " · " .. L["Some slots unknown"]) or reading
end

local function HasAuraID(id)
  local complete = true
  for i = 1, 40 do
    local done, answered, spell = X.Debuffs.ReadAura("player", i, false)
    if done then
      if answered and complete then return false end
      return nil
    end
    if spell == id then return true end
    if not spell then complete = false end
  end
end

local function Presence(value)
  if value == nil then return L["Unknown"] end
  return L[value and "Present" or "Missing"]
end

function R.Personal()
  local db = X.GetDB()
  if not X.classic or not db or db.liteMode or X.PlayerSuspended() or InCombatLockdown() then return end
  local lines = {}
  for _, def in ipairs(X.CONS_DEFS) do
    lines[#lines + 1] = { text = L[def.label], hint = Presence(X.ConsHas("player", def)) }
  end
  if db.readinessAura > 0 then
    local ok, name = pcall(X.Core.SpellName, db.readinessAura)
    local label = ok and X.Readable(name) and type(name) == "string" and name or "#" .. db.readinessAura
    lines[#lines + 1] = { text = L["Optional consumable"] .. " · " .. label, hint = Presence(HasAuraID(db.readinessAura)) }
  else
    lines[#lines + 1] = { text = L["Optional consumable"], hint = L["No aura configured"] }
  end
  lines[#lines + 1] = { text = L["Healthstone in bags"], hint = Presence(Healthstone()) }
  lines[#lines + 1] = { text = L["Equipment durability"], hint = Repairs() }
  local missing = X.WeaponEnchantMissing(true)
  lines[#lines + 1] = { text = L["Temporary weapon coating"], hint = missing == nil and L["Unknown"]
    or L[missing and "Missing" or "No missing coating"] }
  local class = X.UnitClassToken("player")
  if class == "HUNTER" or class == "WARLOCK" then
    lines[#lines + 1] = { text = L["Active pet"], hint = Presence(X.ReadUnitBool(UnitExists, "pet")) }
  end
  return { members = {}, reagents = {}, personal = lines }
end

function R.SetAura(id)
  if id ~= 0 and not X.Settings.PositiveID(id) then
    Print(L["Enter a consumable aura spell ID, or 0 to clear it."])
    return false
  end
  X.GetDB().readinessAura = id
  if X.QueuePersonalReadiness then X.QueuePersonalReadiness() end
  return true
end

function X.ShowFeedback()
  X.ShowExport("https://github.com/SeanShaffer88/BuffRadar/issues/new?template=feature_request.md", false,
    L["Copy the feedback link and open it in your browser."])
end

X.ext.feedback = function() X.ShowFeedback(); return true end
X.ext.readiness = function(rest)
  if not X.classic then X.RaidPreparationCommand("personal"); return true end
  local input = rest:lower()
  local id = input:match("^aura%s+(%S+)$")
  if id then
    if R.SetAura(id == "off" and 0 or tonumber(id)) then
      Print(string.format(L["Personal consumable aura ID: %d (0 = off)."], X.GetDB().readinessAura))
      if X.RefreshConfig then X.RefreshConfig() end
    end
  elseif input == "" or input == "personal" then
    X.RaidPreparationCommand("personal")
  elseif input == "show" or input == "hide" or input == "next" or input == "prev" then
    X.RaidPreparationCommand(input)
  else
    Print(L["Use /br readiness [personal|show|hide|next|prev] or aura <spell ID|off>."])
  end
  return true
end
