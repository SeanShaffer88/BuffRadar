-- BuffRadar - minimap button and addon compartment.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local X = ns.X
local L = X.L
local db
X.OnDBLoaded(function(value) db = value end)

local minimapBtn

local function MinimapRadii()
  local w = Minimap.GetWidth and Minimap:GetWidth()
  local h = Minimap.GetHeight and Minimap:GetHeight()
  return w and w > 0 and w / 2 + 5 or 80, h and h > 0 and h / 2 + 5 or 80
end

local function PositionMinimapButton()
  if not minimapBtn then return end
  local angle = math.rad((db and db.minimapAngle) or 215)
  local rx, ry = MinimapRadii()
  minimapBtn:ClearAllPoints()
  minimapBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * rx, math.sin(angle) * ry)
end

local function RefreshMinimapButton()
  if not minimapBtn then return end
  if db and db.showMinimap and not X.PlayerSuspended() then
    minimapBtn:Show()
    PositionMinimapButton()
  else
    minimapBtn.dragging = false
    minimapBtn:Hide()
  end
end

local function OnClick(_, button)
  if button == "RightButton" then
    if X.OpenConfig then X.OpenConfig() end
  else
    X.ToggleWindow()
  end
end

local function BuildMinimapButton()
  if minimapBtn or not Minimap then return end
  local b = CreateFrame("Button", "BuffRadarMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", 0, 1)
  icon:SetTexture("Interface\\AddOns\\BuffRadar\\Media\\icon.png")
  local border = b:CreateTexture(nil, "ARTWORK")
  border:SetSize(52, 52)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff33ccffBuff|rRadar")
    GameTooltip:AddLine(L["Left-click: show / hide the window"], 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L["Right-click: settings"], 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L["Drag: move around the minimap"], 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- A Button only receives left clicks unless told otherwise; without this the
  -- right-click-for-settings in the tooltip never fired.
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", OnClick)
  b:SetScript("OnDragStart", function(self) self.dragging = true end)
  b:SetScript("OnDragStop", function(self) self.dragging = false end)
  b:SetScript("OnUpdate", function(self)
    if not self.dragging or not db then return end
    local mx, my = Minimap:GetCenter()
    if not mx or not my then return end
    local cx, cy = GetCursorPosition()
    local scale = (Minimap.GetEffectiveScale and Minimap:GetEffectiveScale()) or 1
    cx, cy = cx / scale, cy / scale
    local rx, ry = MinimapRadii()
    local atan2 = math.atan2 or math.atan
    db.minimapAngle = math.deg(atan2((cy - my) / ry, (cx - mx) / rx)) % 360
    PositionMinimapButton()
  end)
  minimapBtn = b
  if Minimap.HookScript then Minimap:HookScript("OnSizeChanged", PositionMinimapButton) end
  RefreshMinimapButton()

  -- Addon compartment (the minimap's addon menu): same clicks as the minimap
  -- button. The click callback's arguments differ between client versions:
  -- newer menus pass a table with .buttonName, older dropdowns pass the mouse
  -- button as the 5th argument; anything else counts as a left click.
  if AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
    pcall(AddonCompartmentFrame.RegisterAddon, AddonCompartmentFrame, {
      text = "BuffRadar",
      icon = "Interface\\AddOns\\BuffRadar\\Media\\icon.png",
      notCheckable = true,
      registerForAnyClick = true,
      func = function(...)
        local a2, a5 = select(2, ...), select(5, ...)
        OnClick(nil, (type(a2) == "table" and a2.buttonName) or a5)
      end,
      funcOnEnter = function(button)
        if type(button) ~= "table" or X.PlayerSuspended() then return end
        GameTooltip:SetOwner(button, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff33ccffBuff|rRadar")
        GameTooltip:AddLine(L["Left-click: show / hide the window"], 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["Right-click: settings"], 0.8, 0.8, 0.8)
        GameTooltip:Show()
      end,
      funcOnLeave = function() GameTooltip:Hide() end,
    })
  end
end

X.BuildMinimapButton = BuildMinimapButton
X.RefreshMinimapButton = RefreshMinimapButton
