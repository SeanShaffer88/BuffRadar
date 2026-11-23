-- BuffRadar - minimap button and addon compartment.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local X = ns.X
local L = X.L
local db
X.OnDBLoaded(function(value) db = value end)

local minimapBtn, pulseEnd, lastPulse
local badgeColors = {
  covered = { 0.25, 1, 0.45, "+" }, attention = { 1, 0.82, 0.22, "!" },
  critical = { 1, 0.32, 0.28, "!!" }, unknown = { 0.72, 0.76, 0.8, "?" },
}

function X.UpdateMinimapStatus()
  if not minimapBtn then return end
  local badge = minimapBtn.statusMark
  local state = db and db.statusMinimap and X.Status.State()
  if badge.state == state then return end
  badge.state = state
  local style = badgeColors[state]
  if style then
    badge:SetText(style[4])
    badge:SetTextColor(style[1], style[2], style[3])
  end
  badge:SetShown(style ~= nil)
end

local function AddStatusTooltip()
  if not db or not db.statusMinimap then return end
  local summary = X.Status.Summary()
  GameTooltip:AddLine(X.Status.Description(), 1, 1, 1)
  if summary.partial and summary.state ~= "unknown" then
    GameTooltip:AddLine(L["Some buff coverage could not be verified"], 0.75, 0.75, 0.75)
  end
  local expiry = summary.firstExpiry
  if expiry and expiry.endsAt > GetTime() then
    GameTooltip:AddLine(X.Intel.ForecastText(expiry.spell, expiry.name, expiry.endsAt), 1, 0.82, 0.35, true)
  end
end

function X.TickMinimapPulse()
  if pulseEnd and (GetTime() >= pulseEnd or db.reduceMotion or not db.visualAlerts or InCombatLockdown()) then
    pulseEnd = nil
    minimapBtn.pulse:Hide()
  end
end

function X.VisualBuffAlert()
  if not db.visualAlerts or db.reduceMotion or InCombatLockdown() or X.PlayerSuspended() then return end
  local now = GetTime()
  if lastPulse and now - lastPulse < 2 then return end
  if db.showBorder and X.Flash(true) then
    lastPulse = now
  elseif minimapBtn and minimapBtn:IsVisible() then
    lastPulse, pulseEnd = now, now + 0.65
    minimapBtn.pulse:Show()
    if C_Timer and C_Timer.After then C_Timer.After(0.65, X.TickMinimapPulse) end
  end
end

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

local function UpdateAngleFromCursor(self)
  if X.PlayerSuspended() or not db then return end
  local mx, my = Minimap:GetCenter()
  if not mx or not my then return end
  local cx, cy = GetCursorPosition()
  local scale = (Minimap.GetEffectiveScale and Minimap:GetEffectiveScale()) or 1
  cx, cy = cx / scale, cy / scale
  local rx, ry = MinimapRadii()
  local atan2 = math.atan2 or math.atan
  db.minimapAngle = math.deg(atan2((cy - my) / ry, (cx - mx) / rx)) % 360
  PositionMinimapButton()
end

local function StopMinimapDrag(self)
  if self and self.dragging then
    self.dragging = nil
    UpdateAngleFromCursor(self)
  end
end

local function RefreshMinimapButton()
  if not minimapBtn then return end
  if db and db.showMinimap and not X.PlayerSuspended() then
    minimapBtn:Show()
    PositionMinimapButton()
    X.UpdateMinimapStatus()
  else
    pulseEnd = nil
    minimapBtn.pulse:Hide()
    StopMinimapDrag(minimapBtn)
    minimapBtn:Hide()
  end
end

local function OnClick(_, button)
  if button == "RightButton" then
    if X.ReadUnitBool(IsShiftKeyDown) then X.OpenWizard()
    elseif X.OpenConfig then X.OpenConfig() end
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
  b.pulse = b:CreateTexture(nil, "ARTWORK")
  b.pulse:SetAllPoints(icon)
  b.pulse:SetColorTexture(1, 0.76, 0.28, 0.45)
  b.pulse:Hide()
  b.statusMark = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.statusMark:SetPoint("TOPRIGHT", 0, 0)
  b.statusMark:Hide()
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff33ccffBuff|rRadar")
    AddStatusTooltip()
    GameTooltip:AddLine(L["Left-click: show / hide the window"], 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L["Right-click: settings"], 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L["Shift-right-click: Quick Setup"], 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L["Drag: move around the minimap"], 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- A Button only receives left clicks unless told otherwise; without this the
  -- right-click-for-settings in the tooltip never fired.
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", OnClick)
  -- Drag is event-only: the final cursor position is read on DragStop/Hide,
  -- not by a per-frame loop. The angle lands when the mouse is released.
  b:SetScript("OnDragStart", function(self)
    if db and not X.PlayerSuspended() and self:IsVisible() then self.dragging = true end
  end)
  b:SetScript("OnDragStop", StopMinimapDrag)
  b:SetScript("OnHide", StopMinimapDrag)
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
        AddStatusTooltip()
        GameTooltip:AddLine(L["Left-click: show / hide the window"], 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["Right-click: settings"], 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["Shift-right-click: Quick Setup"], 0.8, 0.8, 0.8)
        GameTooltip:Show()
      end,
      funcOnLeave = function() GameTooltip:Hide() end,
    })
  end
end

X.BuildMinimapButton = BuildMinimapButton
X.RefreshMinimapButton = RefreshMinimapButton
