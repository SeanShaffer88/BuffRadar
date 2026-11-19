-- BuffRadar - optional, event-driven harmful aura strip. It never casts.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local X = ns.X
local D, L, Print = {}, X.L, X.Print
X.Debuffs = D

local db, frame, listening, encounter
local found, pending = { player = {}, focus = {} }, {}
local fallbackIcon = "Interface\\Icons\\INV_Misc_QuestionMark"
local unitLabels = { player = "Player", focus = "Focus" }
local function Wipe(t) for k in pairs(t) do t[k] = nil end end

local function Fields(aura) return aura.spellId, aura.name, aura.icon, aura.applications end
local function Tuple(...) return select("#", ...), ... end
local function Legacy(lookup, unit, index) return Tuple(lookup(unit, index)) end

-- An explicit nil at the end of a list is different from a refused read.
local function ReadDebuff(unit, index)
  local modern = C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex
  local indexed = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  local ok, id, name, icon, stacks
  if modern or indexed then
    local aura, answered = X.QueryAura(modern or indexed, unit, index, "HARMFUL")
    if not aura then return true, answered end
    ok, id, name, icon, stacks = pcall(Fields, aura)
  else
    local legacyLookup = UnitDebuff
    if type(legacyLookup) ~= "function" then return true, false end
    local read, count, label, image, applications, _, _, _, _, _, _, spell = pcall(Legacy, legacyLookup, unit, index)
    if not read or count == 0 then return true, false end
    if type(label) == "nil" then return true, true end
    ok, id, name, icon, stacks = read, spell, label, image, applications
  end
  if not ok or not X.Readable(id) or not X.Settings.PositiveID(id) then return false end
  if not X.Readable(name) or type(name) ~= "string" then name = nil end
  if not X.Readable(icon) or (type(icon) ~= "number" and type(icon) ~= "string") then icon = fallbackIcon end
  if not X.Readable(stacks) or type(stacks) ~= "number" or not (stacks >= 0 and stacks <= 9999) then stacks = nil end
  return false, nil, id, name, icon, stacks
end

local function RuleActive(rule)
  return rule.encounterID == 0 or rule.encounterID == encounter
end

local function MakeIcon()
  local icon = CreateFrame("Frame", nil, frame)
  icon:SetSize(34, 34)
  icon:EnableMouse(true)
  icon.texture = icon:CreateTexture(nil, "ARTWORK")
  icon.texture:SetAllPoints(icon)
  icon.stacks = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  icon.stacks:SetPoint("BOTTOMRIGHT", -1, 1)
  icon.unitLabel = icon:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  icon.unitLabel:SetPoint("TOP", icon, "BOTTOM", 0, -2)
  icon:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(self.title)
    GameTooltip:AddLine(L[unitLabels[self.unit]])
    GameTooltip:Show()
  end)
  icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
  icon:SetScript("OnHide", function(self)
    if GameTooltip.GetOwner and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
  end)
  return icon
end

local function Draw()
  local n = 0
  for index, rule in ipairs(db.debuffRules) do
    local aura = found[rule.unit][index]
    if aura then
      n = n + 1
      local icon = frame.icons[n]
      if not icon then
        icon = MakeIcon()
        frame.icons[n] = icon
        icon:SetPoint("LEFT", frame, "LEFT", (n - 1) * 54, 0)
      end
      icon.title, icon.unit = aura.name, rule.unit
      icon.texture:SetTexture(aura.icon)
      icon.stacks:SetText(aura.stacks and (aura.stacks > 0 and math.floor(aura.stacks) or "") or "?")
      icon.unitLabel:SetText(L[unitLabels[rule.unit]])
      icon:Show()
    end
  end
  for i = n + 1, #frame.icons do frame.icons[i]:Hide() end
  frame:SetWidth(math.max(1, (n - 1) * 54 + 34))
  frame:SetShown(n > 0)
end

local function Watches(unit)
  for _, rule in ipairs(db.debuffRules) do
    if rule.unit == unit and RuleActive(rule) then return true end
  end
  return false
end

local function Scan(unit)
  local result = found[unit]
  Wipe(result)
  if X.PlayerSuspended() or not Watches(unit) or not X.UnitPresent(unit) then return end
  for i = 1, 40 do
    local done, _, spell, name, icon, stacks = ReadDebuff(unit, i)
    if done then break end
    if spell then
      for j, rule in ipairs(db.debuffRules) do
        if rule.unit == unit and rule.spellID == spell and RuleActive(rule)
          and (not result[j] or (stacks or 0) > (result[j].stacks or 0)) then
          result[j] = { name = name or tostring(spell), icon = icon, stacks = stacks }
        end
      end
    end
  end
end

function D.Clear()
  Wipe(pending)
  Wipe(found.player)
  Wipe(found.focus)
  if frame then
    for _, icon in ipairs(frame.icons) do icon:Hide() end
    frame:Hide()
  end
end

local function RefreshAll()
  Wipe(pending)
  Scan("player")
  Scan("focus")
  Draw()
end

function D.Refresh()
  if listening then X.Measure(InCombatLockdown() and "combatDebuff" or "debuff", RefreshAll) end
end

local function RefreshOne(unit)
  pending[unit] = nil
  Scan(unit)
  Draw()
end

local function RefreshUnit(unit)
  X.Measure(InCombatLockdown() and "combatDebuff" or "debuff", RefreshOne, unit)
end

local function OnEvent(_, event, unit)
  if not listening then return end
  if event == "PLAYER_FOCUS_CHANGED" then
    RefreshUnit("focus")  -- clear the old focus immediately
  elseif X.Readable(unit) and (unit == "player" or unit == "focus") and Watches(unit) then
    if pending[unit] then return end
    if C_Timer and C_Timer.After then
      local token = {}
      pending[unit] = token
      C_Timer.After(0.1, function()
        if pending[unit] == token then RefreshUnit(unit) end
      end)
    else
      RefreshUnit(unit)
    end
  end
end

function D.Encounter(id)
  encounter = X.Readable(id) and X.Settings.PositiveID(id) and id or nil
  D.Refresh()
end

function D.Apply()
  local enable = db and db.debuffWatch and not db.liteMode and #db.debuffRules > 0
  if enable then
    if not frame then
      frame = CreateFrame("Frame", "BuffRadarDebuffWatch", UIParent)
      frame:SetPoint("CENTER", UIParent, "CENTER", 0, -168)
      frame:SetHeight(34)
      frame:SetClampedToScreen(true)
      frame.icons = {}
      frame:SetScript("OnEvent", OnEvent)
      frame:Hide()
    end
    if not listening then
      local registered = frame.RegisterUnitEvent and pcall(frame.RegisterUnitEvent, frame, "UNIT_AURA", "player", "focus")
      if not registered then pcall(frame.RegisterEvent, frame, "UNIT_AURA") end
      pcall(frame.RegisterEvent, frame, "PLAYER_FOCUS_CHANGED")
      listening = true
    end
    D.Refresh()
  elseif listening then
    listening = false
    frame:UnregisterEvent("UNIT_AURA")
    frame:UnregisterEvent("PLAYER_FOCUS_CHANGED")
    D.Clear()
  end
end

function D.SetRule(id, unit, boss)
  if not X.Settings.ValidDebuffRule(id, unit, boss) then
    Print(L["Use a valid debuff spell ID, player or focus, and an optional encounter ID."])
    return false
  end
  for _, rule in ipairs(db.debuffRules) do
    if rule.spellID == id and rule.unit == unit then
      rule.encounterID = boss
      D.Refresh()
      return true
    end
  end
  if #db.debuffRules >= X.Settings.MaxDebuffRules then Print(L["Debuff watch limit reached."]); return false end
  db.debuffRules[#db.debuffRules + 1] = { spellID = id, unit = unit, encounterID = boss }
  D.Apply()
  return true
end

function D.Remove(id, unit)
  for i, rule in ipairs(db.debuffRules) do
    if rule.spellID == id and rule.unit == unit then
      table.remove(db.debuffRules, i)
      D.Apply()
      return true
    end
  end
  Print(L["That debuff is not on the watch list."])
  return false
end

function D.RuleLabel(rule)
  local ok, name = pcall(X.Core.SpellName, rule.spellID)
  local label = ok and X.Readable(name) and type(name) == "string" and (name .. " #" .. rule.spellID) or "#" .. rule.spellID
  return label .. " · " .. L[unitLabels[rule.unit]] .. (rule.encounterID > 0
    and (" · " .. string.format(L["Encounter %d"], rule.encounterID)) or "")
end

X.ext.debuff = function(rest)
  local action, args = rest:lower():match("^(%S*)%s*(.-)$")
  local id, unit, boss = args:match("^(%d+)%s*(%a*)%s*(%d*)$")
  unit = unit == "" and "player" or unit
  if (action == "on" or action == "off") and args == "" then
    X.SetPreference("debuffWatch", action == "on")
    Print(string.format(L["Debuff watch: %s"], L[db.debuffWatch and "On" or "Off"]))
    if db.debuffWatch and db.liteMode then Print(L["Debuff watch is paused in Lite mode."]) end
  elseif action == "add" and id then
    if D.SetRule(tonumber(id), unit, boss == "" and 0 or tonumber(boss)) then Print(L["Debuff rule saved."]) end
  elseif action == "remove" and id and boss == "" then
    D.Remove(tonumber(id), unit)
  elseif (action == "" or action == "list") and args == "" then
    if #db.debuffRules == 0 then Print(L["No debuffs are being tracked."]) end
    for _, rule in ipairs(db.debuffRules) do Print(D.RuleLabel(rule)) end
  else
    Print(L["Use /br debuff on|off|list, add <spell ID> [player|focus] [encounter ID], or remove <spell ID> [player|focus]."])
  end
  if X.RefreshConfig then X.RefreshConfig() end
  return true
end

X.OnDBLoaded(function(value)
  db, encounter = value, nil
  D.Apply()
end)
