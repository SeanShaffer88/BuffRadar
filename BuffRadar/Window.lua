-- BuffRadar - main window, rows, layout and secure click surfaces.
-- Consumes the core's scan results; this file owns the frames and their caches.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, addon = ...
local X = addon.X
local core = X.Core
local db
X.OnDBLoaded(function(value) db = value end)

local L, Print, IsOn, QueueRefresh = X.L, X.Print, core.IsOn, core.QueueRefresh
local Bind, SpellIcon, SpellName = core.Bind, core.SpellIcon, core.SpellName
local Readable, SafeString, Ignore = X.Readable, core.SafeString, X.Ignore
local myBuffs, myBlessing = core.Buffs, core.BlessingsByClass
local ALL, BUFF_DEFS, CLASSIC_FEATURES = X.ALL, X.BUFF_DEFS, X.classic
local math_floor, math_min, math_max, math_ceil, math_huge = math.floor, math.min, math.max, math.ceil, math.huge
local string_format, table_sort = string.format, table.sort
local wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
local GetTime, InCombatLockdown, UnitLevel = GetTime, InCombatLockdown, UnitLevel

local MAX_ROWS  = 15
local ROW_H     = 24
local WIDTH     = X.Settings.Defaults.width
local MIN_WIDTH, MAX_WIDTH = X.Settings.MinWidth, X.Settings.MaxWidth
local HEADER_H  = 24
local MAX_ICONS = 5
local FOOTER_H  = 16

local frame, title, countText, emptyText, overflowText, combatText, nextBtn, coverText
local footerText, focusText, gear, closeButton, nextPreview, nearbyButton
local bar, stripButtons, chipButtons, stripState, findBar, findEdit
local grip, leftGrip, widthHandle, groupBtn, pill
local rows, built = {}, false
local rowMouseButtons, rowLeftPress = {}, nil
local viewport, viewportCount, rowOffset
local visibleLimit = MAX_ROWS
local viewportMode, viewportSearch, viewportRole, viewportTwoCol, rowWheelEnabled
local columns, rowsPerColumn, previousRowsTall = 1, MAX_ROWS, nil
local rowHeight, topHeight = ROW_H, HEADER_H
local titleLayoutState, titleKey, geometryPending, appearancePending, flashPending
local currentAlpha, pillPeek, groupWrapped
local lastCounterSession, lastCounterTotal, lastCounterRoom
local themePreview

local function OwnsThemePreview(owner)
  return owner and owner == themePreview and db == owner.db
    and X.Preferences.Generation() == owner.generation
    and not InCombatLockdown() and not X.PlayerSuspended() and X.Settings.SaveState() ~= "future"
    and db.theme == owner.theme and db.autoThemePriority == owner.priority
    and db.bgColor[1] == owner.color[1] and db.bgColor[2] == owner.color[2] and db.bgColor[3] == owner.color[3]
end

-- Widget writes only when the value actually changes (no redundant redraws).
local function SetTextIfChanged(fs, text)
  if fs.cText ~= text then fs.cText = text; fs:SetText(text) end
end
local function SetShownIfChanged(w, show)
  if (w:IsShown() and true or false) ~= show then
    if show then w:Show() else w:Hide() end
  end
end
-- Height changes are safe to make freely: the frame is anchored by its
-- TOPLEFT corner only (see SavePosition/RestorePosition), so growing or
-- shrinking the height moves only the bottom edge -- the list grows
-- downward and the top of the window never moves.
local function SetHeightIfChanged(f, h)
  if f.cHeight ~= h then f.cHeight = h; f:SetHeight(h) end
end

---------------------------------------------------------------------------
-- Toggle strip, filter chips and idle fade (1.5.0). The bar under the
-- title carries one icon button per buff you can cast (click toggles it,
-- like the Buffs tab) and the role filter chips on the right.
---------------------------------------------------------------------------
local function BarHeight()
  return (db and db.showStrip and core.HasAnyBuff()) and 18 or 0
end

local function RefreshStrip()
  if not stripButtons or not db then return end
  local parts = {}
  for _, b in ipairs(myBuffs) do parts[#parts + 1] = b.key .. (IsOn(b.key, b.default) and "1" or "0") end
  if next(myBlessing) then parts[#parts + 1] = "BLESSINGS" .. (IsOn("BLESSINGS", true) and "1" or "0") end
  local sig = table.concat(parts, ",") .. "|" .. core.BookCount()
  if sig == stripState then return end
  stripState = sig
  local i = 0
  local function place(key, name, default)
    i = i + 1
    local b = stripButtons[i]
    if not b then return end
    b.buffKey, b.buffName, b.buffDefault = key, name, default
    local on = IsOn(key, default)
    b.tex:SetTexture(SpellIcon(name))
    b.tex:SetAlpha(on and 1 or 0.3)
    if b.tex.SetDesaturated then b.tex:SetDesaturated(not on) end
    b:Show()
  end
  for _, b in ipairs(myBuffs) do place(b.key, b.name, b.default) end
  if next(myBlessing) then
    local _, anyB = next(myBlessing)
    if anyB then place("BLESSINGS", anyB.name, true) end
  end
  for j = i + 1, #stripButtons do stripButtons[j]:Hide() end
end

function X.RefreshChips()
  if not chipButtons or not db then return end
  for _, b in ipairs(chipButtons) do
    if b.roleKey == db.roleFilter then b.fs:SetTextColor(1, 0.85, 0.3)
    else b.fs:SetTextColor(0.55, 0.55, 0.55) end
  end
end

-- Idle fade: while the mouse is elsewhere the whole window goes partly
-- see-through; moving the mouse over it brings it back. Polled from the
-- refresh ticker (no per-frame work).
function X.UpdateFade()
  if not frame or not db then return end
  local close = closeButton
  local over = (frame.IsMouseOver and frame:IsMouseOver())
    or (close and close:IsShown() and close.IsMouseOver and close:IsMouseOver())
  if close and not InCombatLockdown() then
    local visible = frame:IsShown() and over and not (db.clickThrough and db.locked)
      and not X.PlayerSuspended()
    if visible then
      -- Above a titleless window where space permits; otherwise only the
      -- hovered button overlays its corner.
      local above = false
      if not db.showTitle then
        local ceiling, top = UIParent:GetTop(), frame:GetTop()
        above = ceiling and top
          and ceiling * UIParent:GetEffectiveScale() - top * frame:GetEffectiveScale()
            >= 22 * close:GetEffectiveScale()
      end
      local anchor = above and "BOTTOMRIGHT" or "TOPRIGHT"
      if close.hoverAnchor ~= anchor then
        close.hoverAnchor = anchor
        close:ClearAllPoints()
        close:SetPoint(anchor, frame, "TOPRIGHT", 0, 0)
      end
    end
    if close:IsShown() ~= (visible and true or false) then close:SetShown(visible and true or false) end
  end
  local target = 1
  if db.idleFade and db.idleFade > 0 and not db.reduceMotion and not frame.isMoving and not (grip and grip.isSizing)
     and not (leftGrip and leftGrip.isSizing) and not (widthHandle and widthHandle.isSizing) then
    if not over then target = 1 - db.idleFade / 100 end
  end
  if currentAlpha ~= target then
    currentAlpha = target
    frame:SetAlpha(target)
  end
end

-- Anchor at the growing edge's opposite corner so row count changes never
-- move the saved position. Legacy anchors are converted when restored.
local function SavePosition()
  if db.growUp then
    -- Grow-up form: the bottom-left corner is the anchor (see X.ApplyAnchor).
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if left and bottom then
      frame:ClearAllPoints()
      frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
      db.point = { "BOTTOMLEFT", "BOTTOMLEFT", left, bottom }
      if db.charPoint then
        local k = X.CharKey()
        X.SaveCharacterPoint(k)
      end
      return
    end
  end
  local left, top = frame:GetLeft(), frame:GetTop()
  if left and top then
    -- Store the top-left corner in screen coordinates (origin bottom-left;
    -- GetLeft/GetTop and SetPoint offsets use the same coordinate system
    -- for this frame). Re-anchor in that form right away, too:
    -- StopMovingOrSizing can leave the frame anchored by whatever point
    -- the drag used, which would bring the jumping back until next reload.
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    db.point = { "TOPLEFT", "BOTTOMLEFT", left, top }
  else
    -- Position not measurable yet (frame never laid out): keep whatever
    -- anchor the drag left rather than saving nothing. RestorePosition
    -- converts a non-TOPLEFT anchor like this one on the next load.
    local p, _, rp, x, y = frame:GetPoint()
    if p then db.point = { p, rp, x, y } end
  end
  if db.charPoint then
    local k = X.CharKey()
    if db.point then X.SaveCharacterPoint(k) end
  end
end

-- Where a named anchor point sits inside a frame, as fractions of its
-- width (from the left edge) and height (from the bottom edge).
local POINT_FRACTION = {
  TOPLEFT = { 0, 1 },     TOP = { 0.5, 1 },   TOPRIGHT = { 1, 1 },
  LEFT = { 0, 0.5 },      CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
  BOTTOMLEFT = { 0, 0 },  BOTTOM = { 0.5, 0 },   BOTTOMRIGHT = { 1, 0 },
}

local function UsablePoint(point, widget)
  if not X.Settings.CopyPoint(point) then return false end
  local to, from = POINT_FRACTION[point[1]], POINT_FRACTION[point[2]]
  local width = X.ReadUnitNumber(UIParent.GetWidth, UIParent)
  local height = X.ReadUnitNumber(UIParent.GetHeight, UIParent)
  if not width or width <= 0 or not height or height <= 0 then return true end
  local scale = X.ReadUnitNumber(widget.GetScale, widget) or 1
  local w, h = X.ReadUnitNumber(widget.GetWidth, widget), X.ReadUnitNumber(widget.GetHeight, widget)
  if not w or not h or w <= 0 or h <= 0 then return true end
  local left = from[1] * width + (point[3] - to[1] * w) * scale
  local bottom = from[2] * height + (point[4] - to[2] * h) * scale
  return left < width and bottom < height and left + w * scale > 0 and bottom + h * scale > 0
end

-- Forget the saved window spot (shared and per-character), so the next
-- RestorePosition lands on the default anchor.
local function ClearSavedPoint()
  db.point = nil
  if db.charPoint then
    local k = X.CharKey()
    if k then db.pointByChar[k] = nil end
  end
end

local function PlaceSavedPosition()
  if db.charPoint then
    local k = X.CharKey()
    if k and db.pointByChar[k] then db.point = db.pointByChar[k] end
  end
  frame:ClearAllPoints()
  if db.point and not UsablePoint(db.point, frame) then ClearSavedPoint() end
  if db.growUp and db.point and db.point[1] == "BOTTOMLEFT" then
    -- Grow-up form (1.8.0): restore the bottom anchor as saved.
    frame:SetPoint("BOTTOMLEFT", UIParent, db.point[2], db.point[3], db.point[4])
    return
  end
  if not db.point then
    -- Default spot, in top-left form: the pre-1.3.1 default anchored the
    -- frame's LEFT point at (40, 80) from the screen's left edge; at the
    -- height the frame is built with, that puts the top-left corner half
    -- a build-height above it.
    frame:SetPoint("TOPLEFT", UIParent, "LEFT", 40, 80 + (HEADER_H + 30) / 2)
    return
  end
  local p, rp, x, y = db.point[1], db.point[2], db.point[3], db.point[4]
  local f = POINT_FRACTION[p]
  if p == "TOPLEFT" or not f then
    frame:SetPoint(p, UIParent, rp, x, y)
    return
  end
  -- Legacy save (1.3.0 and earlier stored the drag anchor verbatim, e.g.
  -- LEFT or CENTER): convert it to a TOPLEFT anchor against the same
  -- point of UIParent. The top-left corner sits (-fx * W, (1 - fy) * H)
  -- from the old anchor point, so with the frame's current size the
  -- window does not move at all in this conversion -- it just stops
  -- moving afterwards, when its height starts changing. The height at
  -- drag time was never saved, so this preserves the position as
  -- restored now, not necessarily the exact top edge seen while dragging.
  local w, h = frame:GetWidth(), frame:GetHeight()
  db.point = { "TOPLEFT", rp, x - f[1] * w, y + (1 - f[2]) * h }
  frame:SetPoint("TOPLEFT", UIParent, rp, db.point[3], db.point[4])
end

local function RestorePosition()
  if InCombatLockdown() then return end
  if not pcall(PlaceSavedPosition) then
    ClearSavedPoint()
    PlaceSavedPosition()
  end
end

function X.SaveCharacterPoint(key)
  if key and X.Settings.PlainString(key, 128) and X.Settings.CanAdd(db.pointByChar, "pointByChar", key) then
    db.pointByChar[key] = X.Settings.CopyPoint(db.point)
  end
end

function X.ResetWindowPosition()
  if InCombatLockdown() then return false end
  ClearSavedPoint()
  if frame then RestorePosition() end
  return true
end

local function InstallCombatDriver(button, snippet)
  if not RegisterStateDriver then return false end
  local ok, accepted = pcall(button.SetAttribute, button, "_onstate-combat", snippet)
  if not ok or accepted == false then return false end
  ok, accepted = pcall(RegisterStateDriver, button, "combat", "[@player,dead][combat] combat; nocombat")
  return ok and accepted ~= false
end

-- The keybind / macro button. Like the rows, it's set up between clicks (never during one).
-- It casts on press when "ActionButtonUseKeyDown" is on and on release otherwise, so one
-- key press = one cast. It clears itself after each use and whenever combat starts.
local function ApplyNextRegistration()
  if not nextBtn or InCombatLockdown() then return end
  if GetCVarBool and GetCVarBool("ActionButtonUseKeyDown") then
    nextBtn:RegisterForClicks("LeftButtonDown")
  else
    nextBtn:RegisterForClicks("LeftButtonUp")
  end
  if groupBtn then
    if GetCVarBool and GetCVarBool("ActionButtonUseKeyDown") then
      groupBtn:RegisterForClicks("LeftButtonDown")
    else
      groupBtn:RegisterForClicks("LeftButtonUp")
    end
  end
end

local nextWrapped, nextCombatDriver = false, false

local function ClearNext()
  if not nextBtn or InCombatLockdown() then return end
  nextBtn.entry = nil
  if nextBtn.isClear then return end  -- already disarmed: skip protected writes
  nextBtn:SetAttribute("type", nil)
  nextBtn:SetAttribute("spell", nil)
  nextBtn:SetAttribute("unit", nil)
  nextBtn:SetAttribute("macrotext", nil)
  nextBtn:SetAttribute("shift-type1", nil)
  nextBtn:SetAttribute("shift-spell1", nil)
  nextBtn:SetAttribute("shift-unit1", nil)
  nextBtn:SetAttribute("shift-macrotext1", nil)
  nextBtn.isClear = true
  nextBtn.bGuid = nil
end

local function ClearGroup()
  if not groupBtn or InCombatLockdown() then return end
  groupBtn.entry = nil
  if groupBtn.isClear then return end  -- already disarmed: skip the protected writes
  groupBtn:SetAttribute("type", nil)
  groupBtn:SetAttribute("spell", nil)
  groupBtn:SetAttribute("unit", nil)
  groupBtn:SetAttribute("macrotext", nil)
  groupBtn.isClear = true
  groupBtn.bGuid = nil
end

local function DisarmStaleKeybind(button, mouseButton, clear)
  if mouseButton == "LeftButton" and not InCombatLockdown() and button:GetAttribute("type")
      and not X.RowTargetMatches(button.entry) then
    clear()
    if QueueRefresh then QueueRefresh() end
  end
end

-- Group-cast keybind (1.15.0): the group button's plain attribute family
-- carries the GROUP version of the head row's buff, so one key press
-- casts it. When the buff has no group version the button falls back to
-- the plain cast -- the key is never dead, same as the next-buff key.
local function BindGroupCached(btn, unit, spell, guid)
  if not btn.combatDriver then return false end
  local isSelf = X.IsSelf(unit)
  if isSelf == nil then ClearGroup(); return false end
  local offer, item, count, reason, _, blocker = X.GroupOffer(spell, unit)
  local gspell = offer or spell
  local method = db.castMethod
  local lvl = X.ReadUnitNumber(UnitLevel, unit) or 0
  local pick = X.BindingRank(gspell, unit, lvl, method)
  if pick == false then ClearGroup(); return false end
  local id = pick and pick.id
  local hadTarget = X.NeedsExactTarget(unit, isSelf, method) and X.UnitPresent("target")
  btn.bOfferReason = X.GroupOfferReason(item, count, reason, blocker)
  btn.bOfferSummary = blocker and X.GroupOfferReason(item, count, reason, blocker, true) or btn.bOfferReason
  if btn.bGuid == guid and btn.bUnit == unit and btn.bSpell == gspell
     and btn.bMethod == method and btn.bLevel == lvl and btn.bSelf == isSelf and btn.bRankID == id
     and btn.bHadTarget == hadTarget then
    return btn:GetAttribute("type") ~= nil
  end
  Bind(btn, unit, gspell, isSelf, pick, nil, nil, hadTarget)
  btn.bGuid, btn.bUnit, btn.bSpell, btn.bMethod, btn.bLevel = guid, unit, gspell, method, lvl
  btn.bSelf, btn.bHadTarget = isSelf, hadTarget
  btn.bRankID, btn.bActionID, btn.bSpellText = id, id, X.CastText(gspell, pick)
  if method == "macro" then btn.bActionID, btn.bSpellText = nil, gspell end
  btn.isClear = false
  return btn:GetAttribute("type") ~= nil
end

local function ClearRowCast(btn)
  if InCombatLockdown() then return end
  btn:SetAttribute("type", nil)
  btn:SetAttribute("spell", nil)
  btn:SetAttribute("unit", nil)
  btn:SetAttribute("macrotext", nil)
  btn:SetAttribute("shift-type1", nil)
  btn:SetAttribute("shift-spell1", nil)
  btn:SetAttribute("shift-unit1", nil)
  btn:SetAttribute("shift-macrotext1", nil)
  btn.bGuid = nil
end

-- Secure attribute writes only when what the button should cast actually changed.
local function BindCached(btn, unit, spell, guid)
  if not btn.combatDriver then return false end
  local isSelf = X.IsSelf(unit)
  if isSelf == nil then
    if btn.bGuid ~= nil then ClearRowCast(btn) end
    return false
  end
  local method = db.castMethod
  local lvl = X.ReadUnitNumber(UnitLevel, unit) or 0
  local pick = X.BindingRank(spell, unit, lvl, method)
  if pick == false then ClearRowCast(btn); return false end
  local gspell, item, count, reason, blocker
  if db.modClick then
    local _
    gspell, item, count, reason, _, blocker = X.GroupOffer(spell, unit)
  end
  if reason then gspell = spell end -- explicit Shift fallback mirrors the primary binding
  local gpick = gspell and X.BindingRank(gspell, unit, lvl, method)
  local id, gid = pick and pick.id, gpick and gpick.id
  local hadTarget = X.NeedsExactTarget(unit, isSelf, method) and X.UnitPresent("target")
  btn.bOfferReason = X.GroupOfferReason(item, count, reason, blocker)
  if btn.bGuid == guid and btn.bUnit == unit and btn.bSpell == spell
     and btn.bMethod == method and btn.bLevel == lvl and btn.bSelf == isSelf
     and btn.bRankID == id and btn.bGroupSpell == gspell and btn.bGroupRankID == gid
     and btn.bHadTarget == hadTarget then
    return btn:GetAttribute("type") ~= nil
  end
  Bind(btn, unit, spell, isSelf, pick, gspell, gpick, hadTarget)
  btn.bGuid, btn.bUnit, btn.bSpell, btn.bMethod, btn.bLevel = guid, unit, spell, method, lvl
  btn.bSelf, btn.bHadTarget = isSelf, hadTarget
  btn.bRankID, btn.bGroupRankID, btn.bGroupSpell = id, gid, gspell
  btn.bActionID, btn.bGroupID, btn.bSpellText = id, gid, X.CastText(spell, pick)
  btn.bGroupText = gspell and X.CastText(gspell, gpick)
  if method == "macro" then
    btn.bActionID, btn.bGroupID, btn.bSpellText, btn.bGroupText = nil, nil, spell, gspell
  end
  btn.isClear = false
  return btn:GetAttribute("type") ~= nil
end

-- The group key uses the same head as the next-buff key.
local function ArmGroupButton(first)
  if not groupBtn then return end
  groupBtn.entry = BindGroupCached(groupBtn, first.unit, first.missing[1], first.guid) and first or nil
end

local function NoCastReason(entry)
  local group = groupBtn
  if not entry then return X.groupFallback or (group and group.entry and group.bOfferReason) end
  if group and group.entry == entry and group.bOfferReason then
    return group.bOfferSummary
  end
  if X.groupFallbackEntry == entry then return X.groupFallbackSummary end
end

local function ShowNextPreview(owner)
  if InCombatLockdown() or X.PlayerSuspended() or (db.locked and db.clickThrough) then return end
  local entry = nextBtn and nextBtn.entry
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  if entry then
    GameTooltip:AddLine(string_format(L["Next buff: %s — %s"], entry.fullName or entry.name,
      nextBtn.bSpellText or entry.missing[1]), 1, 1, 1, true)
  end
  if X.DeliveryLines then
    local direct, macroLine = X.DeliveryLines()
    GameTooltip:AddLine(direct, 0.8, 0.9, 1, true)
    GameTooltip:AddLine(macroLine, 0.8, 0.9, 1, true)
  end
  local group = groupBtn
  if group and group.entry == entry and group.bSpellText then
    GameTooltip:AddLine(string_format(L["Group buff key: %s"], group.bSpellText), 0.8, 0.9, 1, true)
  end
  local reason = NoCastReason(entry)
  if reason then GameTooltip:AddLine(reason, 1, 0.7, 0.3, true) end
  GameTooltip:Show()
end

function X.RefreshNextPreview()
  if nextPreview and GameTooltip.IsShown and GameTooltip:IsShown()
      and GameTooltip.GetOwner and GameTooltip:GetOwner() == nextPreview then
    GameTooltip:ClearLines()
    ShowNextPreview(nextPreview)
  end
end

local function BuildNextButton()
  nextBtn = CreateFrame("Button", "BuffRadarNextButton", UIParent,
                        "SecureActionButtonTemplate,SecureHandlerStateTemplate")
  nextBtn:SetSize(1, 1)
  nextBtn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
  nextBtn:SetAlpha(0)
  nextBtn:EnableMouse(false)
  nextBtn:Show()
  ApplyNextRegistration()
  -- Secure snippets clear the button the instant combat starts and right after each use.
  -- Leave casting disarmed if the client cannot install combat clearing.
  nextCombatDriver = InstallCombatDriver(nextBtn, [[
    if newstate == "combat" then
      self:SetAttribute("type", nil)
      self:SetAttribute("spell", nil)
      self:SetAttribute("unit", nil)
      self:SetAttribute("macrotext", nil)
      self:SetAttribute("shift-type1", nil)
      self:SetAttribute("shift-spell1", nil)
      self:SetAttribute("shift-unit1", nil)
      self:SetAttribute("shift-macrotext1", nil)
    end
  ]])
  nextBtn.combatDriver = nextCombatDriver
  if SecureHandlerWrapScript then
    nextWrapped = pcall(SecureHandlerWrapScript, nextBtn, "OnClick", nextBtn, [[ return nil, true ]], [[
      self:SetAttribute("type", nil)
      self:SetAttribute("spell", nil)
      self:SetAttribute("unit", nil)
      self:SetAttribute("macrotext", nil)
      self:SetAttribute("shift-type1", nil)
      self:SetAttribute("shift-spell1", nil)
      self:SetAttribute("shift-unit1", nil)
      self:SetAttribute("shift-macrotext1", nil)
    ]])
  end
  nextBtn:HookScript("PreClick", function(self, button, down)
    DisarmStaleKeybind(self, button, ClearNext)
    X.BeginCastClick(self, button, down, "next-buff key")
  end)
  nextBtn:HookScript("PostClick", function(self, button, down)
    X.EndCastClick(self, button, down, "next-buff key")
    self.bGuid, self.isClear = nil, false  -- attributes changed outside our cache
    if not nextWrapped then ClearNext() end  -- one press = one cast
  end)
end

-- The group-cast keybind button (1.15.0): same hidden secure pattern as
-- the next-buff button -- combat driver clears it, the wrap clears it
-- after each use, PostClick books the cast that actually happened (the
-- group version when there is one).
local function BuildGroupButton()
  local btn = CreateFrame("Button", "BuffRadarGroupButton", UIParent,
                         "SecureActionButtonTemplate,SecureHandlerStateTemplate")
  groupBtn = btn
  btn:SetSize(1, 1)
  btn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
  btn:SetAlpha(0)
  btn:EnableMouse(false)
  btn:Show()
  ApplyNextRegistration()
  btn.combatDriver = InstallCombatDriver(btn, [[
    if newstate == "combat" then
      self:SetAttribute("type", nil)
      self:SetAttribute("spell", nil)
      self:SetAttribute("unit", nil)
      self:SetAttribute("macrotext", nil)
    end
  ]])
  if SecureHandlerWrapScript then
    groupWrapped = pcall(SecureHandlerWrapScript, btn, "OnClick", btn, [[ return nil, true ]], [[
      self:SetAttribute("type", nil)
      self:SetAttribute("spell", nil)
      self:SetAttribute("unit", nil)
      self:SetAttribute("macrotext", nil)
    ]])
  end
  btn:HookScript("PreClick", function(self, button, down)
    DisarmStaleKeybind(self, button, ClearGroup)
    X.BeginCastClick(self, button, down, "group-buff key")
  end)
  btn:HookScript("PostClick", function(self, button, down)
    X.EndCastClick(self, button, down, "group-buff key")
    self.bGuid, self.isClear = nil, false  -- attributes changed outside our cache
    if not groupWrapped then ClearGroup() end  -- one press = one cast
  end)
end

function X.SetNextCast(entry)
  if nextBtn then nextBtn.deliveryEntry = entry end
  if nextBtn and entry then
    nextBtn.entry = BindCached(nextBtn, entry.unit, entry.missing[1], entry.guid) and entry or nil
    ArmGroupButton(entry)
  else
    ClearNext()
    ClearGroup()
  end
end

function X.ClearKeybindCasts()
  if nextBtn then nextBtn.deliveryEntry = nil end
  ClearNext()
  ClearGroup()
end

local function ClassColor(class)
  local c = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class])
         or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
  if c then return c.r, c.g, c.b end
  return 1, 1, 1
end

local function Row_OnEnter(self)
  if not self.entry then return end
  local e = self.entry
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  if X.UnitPresent(e.unit) and X.UnitGUIDOf(e.unit) == e.guid then
    GameTooltip:SetUnit(e.unit)
  else
    GameTooltip:AddLine(e.name)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(string_format(L["Click to cast: %s"], "|cff00ff00" .. (self.bSpellText or e.missing[1]) .. "|r"))
  if db.modClick and CLASSIC_FEATURES then
    local gs = self.bGroupText or self.bGroupSpell
    if gs then
      GameTooltip:AddLine(string_format(L["Shift-click to cast: %s"], "|cff00ff00" .. gs .. "|r"))
    end
    if self.bOfferReason then GameTooltip:AddLine(self.bOfferReason, 1, 0.7, 0.3, true) end
  end
  if e.groupCast then
    GameTooltip:AddLine(L["Group version — one cast buffs the whole party."], 0.4, 0.8, 1)
  end
  -- Tooltip detail (1.10.0): minimal stops at the cast line.
  if db.tooltipLevel == "minimal" then GameTooltip:Show() return end
  GameTooltip:AddLine(L["Right-click to ignore this player."], 0.6, 0.6, 0.6)
  GameTooltip:AddLine(L["Shift-right-click to ignore for this session only."], 0.6, 0.6, 0.6)
  if #e.missing > 1 then
    local rest = {}
    for i = 2, #e.missing do rest[#rest + 1] = e.missing[i] end
    GameTooltip:AddLine(string_format(L["Still needs: %s"], table.concat(rest, ", ")), 0.8, 0.8, 0.8, true)
  end
  -- The full picture (1.7.0): buffs this player HAS from your set, with
  -- the time left on each, soonest first — so a hover answers "what do
  -- they still need, and what's about to run out?" in one look.
  if X.UnitPresent(e.unit) then
    local missSet = {}
    for _, m in ipairs(e.missing) do missSet[m] = true end
    local have, seenHave = {}, {}
    for _, def in ipairs(myBuffs) do
      local nm = def.name
      if nm and not seenHave[nm] and not missSet[nm] then
        seenHave[nm] = true
        local left = X.Remaining(e.unit, nm)
        if left and left < math_huge and left > 0 then
          have[#have + 1] = { name = nm, left = left }
        end
      end
    end
    table_sort(have, function(x, y) return x.left < y.left end)
    for i = 1, math_min(6, #have) do
      local h = have[i]
      local t = h.left >= 90 and string_format(L["~%dm left"], math_floor(h.left / 60))
        or string_format(L["~%ds left"], math_floor(h.left))
      GameTooltip:AddLine(h.name .. " — " .. t, 0.55, 0.85, 0.55)
    end
  end
  -- Full tooltips (1.10.0) add the context lines: class and group, the
  -- range in words, and which other classes could cast the first buff.
  if db.tooltipLevel == "full" then
    local bits = {}
    if e.class then bits[#bits + 1] = e.class:sub(1, 1) .. e.class:sub(2):lower() end
    bits[#bits + 1] = e.group and "In your group" or "Nearby, not in your group"
    bits[#bits + 1] = e.approximateRange and L["Estimated range"] or "in cast range"
    GameTooltip:AddLine(table.concat(bits, " · "), 0.7, 0.7, 0.7)
    -- Which other classes could cast the first missing buff: scanned
    -- from the definitions on the spot (a hover is rare; no state kept).
    local _, myClass = UnitClass("player")
    local names, seenCls = {}, {}
    for _, d in ipairs(BUFF_DEFS) do
      local dn
      if d.choices then dn = SpellName(d.choices[1][1], d.choices[1][2])
      else dn = SpellName(d.id, d.name) end
      if dn == e.missing[1] then
        for c in pairs(d.classes or ALL) do
          if c ~= myClass and not seenCls[c] then
            seenCls[c] = true
            names[#names + 1] = c:sub(1, 1) .. c:sub(2):lower()
          end
        end
      end
    end
    table_sort(names)
    if #names > 0 then
      GameTooltip:AddLine(string.format(L["Also castable by: %s"], table.concat(names, ", ")), 0.7, 0.7, 0.7, true)
    end
  end
  GameTooltip:Show()
end

-- The name field stops this far short of the row's right edge to leave
-- room for the buff icons; it follows the icon size (1.10.0).
local function IconInset()
  local isz = (db.iconSize or 0) > 0 and db.iconSize or (db.compact and 12 or 16)
  return MAX_ICONS * (isz + 2) + 4
end

local function RowMouseHeld()
  for button, expires in pairs(rowMouseButtons) do
    local down = X.ReadUnitBool(_G.IsMouseButtonDown, button)
    if down == false or (down == nil and GetTime() >= expires) then
      rowMouseButtons[button] = nil
    end
  end
  return next(rowMouseButtons) ~= nil
end
local function RowWheel(_, delta)
  if delta ~= 0 then X.ScrollRows(delta < 0 and 1 or -1) end
end

-- Row hover highlight (1.15.34): a faint wash in the theme's border colour
-- instead of the bright quest-title glow. The engine shows a button's
-- highlight texture only while the mouse is over it, so no script is
-- needed; ApplyAppearance re-tints every row when the theme changes.
local ROW_HOVER_ALPHA = 0.15
local function TintRowHover(b)
  local hl = b and b.GetHighlightTexture and b:GetHighlightTexture()
  if not hl or not hl.SetVertexColor then return end
  local bc = X.ThemeBorder()
  hl:SetVertexColor(bc[1], bc[2], bc[3], ROW_HOVER_ALPHA)
end

local function RegisterRowClicks(b)
  if db.clickReg == "down" then
    b:RegisterForClicks("AnyDown")
  elseif db.clickReg == "up" then
    b:RegisterForClicks("AnyUp")
  else
    b:RegisterForClicks("AnyUp", "AnyDown")
  end
end

local function IgnoreRowPlayer(self, button, down)
  if button ~= "RightButton" or InCombatLockdown() then return end
  -- With AnyUp+AnyDown registered, OnClick fires twice per physical click;
  -- toggle on exactly one phase (release, unless casts trigger on press).
  if down ~= (db.clickReg == "down") then return end
  local e = self.entry
  if not e or not db or e.spell then return end
  local short = e.pet and SafeString(e.name) or e.sortName
  if short == "" then short = nil end
  local who = e.fullName or short   -- Name-Realm: ignores this one player only
  if not who then return end
  if _G.IsShiftKeyDown and _G.IsShiftKeyDown() then
    local k = Ignore.Key(who)
    if X.session[k] then
      X.session[k] = nil
      Print(string.format(L["No longer ignoring %s for this session."], who))
    else
      X.session[k] = true
      Print(string.format(L["Ignoring %s for this session only (not saved)."], who))
    end
    if QueueRefresh then QueueRefresh() end
    return
  end
  if Ignore.Has(e.fullName, short) then
    -- (a row still showing an ignored player: it drops off on the next refresh)
    local removed = Ignore.Remove(who)
    if #removed == 0 and short then removed = Ignore.Remove(short) end
    Print(string.format(L["No longer ignoring %s."], table.concat(removed, ", ")))
  else
    local ok, err = Ignore.Add(who)
    if ok then Print(string.format(L["Ignoring %s. Undo with /br unignore %s or on the Ignore & Stats tab."], who, who))
    elseif err then Print(err) end
  end
  if QueueRefresh then QueueRefresh() end
end

local function ValidateRowClick(self, button, down)
  if button == "LeftButton" and not InCombatLockdown() and self:GetAttribute("type") then
    local press = not down and rowLeftPress
    local changed = press and (press.row ~= self or press.guid ~= self.bGuid
      or press.unit ~= self.bUnit or press.spell ~= self.bSpell)
    if changed or not X.RowTargetMatches(self.entry) then
      ClearRowCast(self)
      self.entry, self.guid = nil, nil
      if QueueRefresh then QueueRefresh() end
      return
    end
  end
  X.BeginCastClick(self, button, down, "click")
end

local function TrackRowCast(self, button, down)
  X.EndCastClick(self, button, down, "click")
  if button == "LeftButton" and not down then rowLeftPress = nil end
end

local function RememberRowPress(self, button)
  if button == "LeftButton" or button == "RightButton" then rowMouseButtons[button] = GetTime() + 1 end
  if button == "LeftButton" then
    -- The mouse-up notification may precede the up-phase secure click.
    -- Keep the presented binding through dispatch, independently of that notification.
    rowLeftPress = { row = self, guid = self.bGuid, unit = self.bUnit, spell = self.bSpell }
  end
end

local function EndRowMouseHold(_, button)
  rowMouseButtons[button] = nil
end

local function BuildRowVisuals(b)
  b.portrait = b:CreateTexture(nil, "ARTWORK")
  b.portrait:SetSize(ROW_H - 2, ROW_H - 2)
  b.portrait:SetPoint("LEFT", 1, 0)
  if b.CreateMaskTexture and b.portrait.AddMaskTexture then
    local m = b:CreateMaskTexture()
    m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
                 "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(b.portrait)
    b.portrait:AddMaskTexture(m)
  end

  b.cMissing = {}  -- render cache: icons currently drawn
  b.icons = {}
  for j = 1, MAX_ICONS do
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetSize(16, 16)
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if j == 1 then
      t:SetPoint("RIGHT", b, "RIGHT", -2, 0)
    else
      t:SetPoint("RIGHT", b.icons[j - 1], "LEFT", -2, 0)
    end
    b.icons[j] = t
  end

  b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.name:SetPoint("LEFT", b.portrait, "RIGHT", 6, 0)
  b.name:SetPoint("RIGHT", b, "RIGHT", -(IconInset()), 0)
  b.name:SetJustifyH("LEFT")
  if b.name.SetWordWrap then b.name:SetWordWrap(false) end
  -- "out of range" under the name of a greyed row, so the state doesn't rest
  -- on color alone (RenderRow moves the name up to make room).
  -- Duration bar (1.8.0): a thin bar along the row's bottom edge showing
  -- how much of a 30-minute span the expiring buff has left.
  b.tint = b:CreateTexture(nil, "OVERLAY")
  b.tint:SetTexture("Interface\\Buttons\\WHITE8X8")
  b.tint:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -1)
  b.tint:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 1)
  b.tint:SetWidth(3)
  b.tint:Hide()
  b.bar = b:CreateTexture(nil, "ARTWORK")
  b.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
  b.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, 1)
  b.bar:SetHeight(3)
  b.bar:SetWidth(10)
  b.bar:Hide()
  -- Raid marker badge (1.8.0): the player's raid target icon, drawn over
  -- the portrait's top-left corner.
  b.marker = b:CreateTexture(nil, "OVERLAY")
  b.marker:SetSize(12, 12)
  b.marker:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  b.marker:Hide()

  -- Short status tag under the name ("recently rezzed"); shares the slot
  -- with the out-of-range label, which wins when both would apply.
  b.tag = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.tag:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -1)
  b.tag:SetTextColor(1, 0.85, 0.4)
  b.tag:Hide()
end

local function CreateRow(i)
  local b = CreateFrame("Button", "BuffRadarRow" .. i, frame,
                        "SecureActionButtonTemplate,SecureHandlerStateTemplate")
  -- Anchored on both sides, so rows follow the window's width when it's resized.
  b:SetHeight(ROW_H)
  b:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -HEADER_H - (i - 1) * ROW_H)
  b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -HEADER_H - (i - 1) * ROW_H)
  RegisterRowClicks(b)
  b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "ADD")
  TintRowHover(b)
  -- Right-click only ignores (see the OnClick hook below). Bind() sets the plain
  -- "type" attribute, which the secure template uses for EVERY mouse button
  -- unless a button-specific one exists; this "type2" override is a made-up
  -- action the template doesn't know, so a right-click casts nothing.
  -- Bind() never touches "type2", so this holds for the row's lifetime.
  b:SetAttribute("type2", "buffradarignore")
  b.combatDriver = InstallCombatDriver(b, [[
    if newstate == "combat" then
      self:SetAttribute("type", nil)
      self:SetAttribute("spell", nil)
      self:SetAttribute("unit", nil)
      self:SetAttribute("macrotext", nil)
      self:SetAttribute("shift-type1", nil)
      self:SetAttribute("shift-spell1", nil)
      self:SetAttribute("shift-unit1", nil)
      self:SetAttribute("shift-macrotext1", nil)
    end
  ]])

  BuildRowVisuals(b)

  -- HookScript, never SetScript: SetScript would REPLACE the
  -- SecureActionButtonTemplate's own OnClick (SecureActionButton_OnClick),
  -- which is what actually performs the cast -- with it replaced, clicks run
  -- only this handler and nothing is ever cast (the 1.2.0/1.2.1 bug).
  b:HookScript("OnClick", IgnoreRowPlayer)
  b:HookScript("PreClick", ValidateRowClick)
  b:HookScript("PostClick", TrackRowCast)
  b:SetScript("OnEnter", Row_OnEnter)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:HookScript("OnMouseDown", RememberRowPress)
  b:HookScript("OnMouseUp", EndRowMouseHold)
  b:SetScript("OnMouseWheel", RowWheel)
  b:EnableMouseWheel(false)
  b:Hide()
  rows[i] = b
end

-- Color themes (1.8.0): a theme is a background color + border color pair.
-- Picking one sets both; picking a custom background color afterwards
-- switches the theme back to "custom" (border returns to the default).

-- Saved themes (1.10.0): your own background + border pairs, kept in
-- db.customThemes, usable anywhere a built-in theme is.
function X.SavedTheme(name)
  if not db or not name then return nil end
  local id = name:lower()
  if X.THEMES[id] or id == "custom" then return nil end
  for _, t in ipairs(db.customThemes or {}) do
    if t.name:lower() == id then
      return { label = t.name, bg = t.bg, border = t.border }
    end
  end
  return nil
end

function X.ThemeDef(name)
  if not name then return nil end
  return X.THEMES[name:lower()] or X.SavedTheme(name)
end

-- The cycle order: built-in themes followed by your saved themes.
function X.ThemeOrder()
  local order = {}
  for _, k in ipairs(X.THEME_ORDER) do order[#order + 1] = k end
  if db then
    for _, t in ipairs(db.customThemes or {}) do
      local id = t.name:lower()
      if not X.THEMES[id] and id ~= "custom" then order[#order + 1] = t.name end
    end
  end
  return order
end

function X.EffectiveTheme()
  if OwnsThemePreview(themePreview) then return X.ThemeCandidate(themePreview.selected) end
  if db and db.theme == X.AUTO_THEME_ID then
    return X.THEMES[X.autoThemeResolved or "midnight"]
  end
  return db and X.ThemeDef(db.theme)
end

function X.ThemeBorder()
  local t = X.EffectiveTheme()
  if t then return t.border end
  return { 0.35, 0.55, 0.8 }
end

function X.ThemeBackground()
  local candidate = OwnsThemePreview(themePreview) and X.ThemeCandidate(themePreview.selected)
  if candidate then return candidate.bg end
  if db and db.theme == X.AUTO_THEME_ID then
    return X.EffectiveTheme().bg
  end
  return db and db.bgColor or X.Settings.Defaults.bgColor
end

function X.ThemeLabel(detail)
  if db and db.theme == X.AUTO_THEME_ID then
    if detail then
      return string_format(L["Auto (%s)"], X.THEMES[X.autoThemeResolved or "midnight"].label)
    end
    return L["Auto"]
  end
  local t = db and X.ThemeDef(db.theme)
  return t and t.label or "Custom"
end

function X.AutoThemePriority()
  return X.Settings.AutoThemeOrder(db and db.autoThemePriority)
end

function X.MoveAutoThemePriority(palette, offset)
  if not db or (offset ~= -1 and offset ~= 1) then return false end
  local order = X.AutoThemePriority()
  for i, entry in ipairs(order) do
    if entry[2] == palette then
      local nextIndex = i + offset
      if not order[nextIndex] then return false end
      order[i], order[nextIndex] = order[nextIndex], entry
      db.autoThemePriority = X.Settings.EncodeAutoThemeOrder(order)
      X.ResolveAutoTheme()
      return true
    end
  end
  return false
end

function X.ResetAutoThemePriority()
  if not db then return false end
  local changed = db.autoThemePriority ~= ""
  db.autoThemePriority = ""
  X.ResolveAutoTheme()
  return changed
end

function X.AutoThemeStatus()
  if not db or db.theme ~= X.AUTO_THEME_ID then
    return string_format(L["Auto is off. Current theme: %s."], X.ThemeLabel())
  end
  if not X.autoThemeAddon then return L["No supported UI addon is loaded. Using Midnight."] end
  return string_format(L["Selected: %s (%s)"], X.THEMES[X.autoThemeResolved or "midnight"].label, X.autoThemeAddon)
end

-- Grow-up (1.8.0): normally the window hangs from its top-left corner and
-- the list grows downward. With grow-up on, the window stands on its
-- bottom-left corner instead, so the list grows upward and the bottom
-- edge never moves. The saved point records which form it holds.
function X.ApplyAnchor()
  if not frame then return end
  local left = frame:GetLeft()
  if not left then return end
  if db.growUp then
    local bottom = frame:GetBottom()
    if not bottom then return end
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    db.point = { "BOTTOMLEFT", "BOTTOMLEFT", left, bottom }
  else
    local top = frame:GetTop()
    if not top then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    db.point = { "TOPLEFT", "BOTTOMLEFT", left, top }
  end
  if db.charPoint then
    local k = X.CharKey()
    X.SaveCharacterPoint(k)
  end
end

-- Title suffix (1.12.0): "(update pending)" while a size/scale change waits
-- for combat to end; "(data hidden)" while the game is withholding aura
-- data from addons (secret values), so a stale-looking list has a reason.
local function UpdateTitleMarks()
  if not title then return end
  local hid = X.hid > 0 and (GetTime() - X.hid) < 10
  local key = (geometryPending and "p" or "") .. (hid and "h" or "")
  if titleKey == key then return end
  titleKey = key
  local txt = "|cff33ccffBuff|rRadar"
  if geometryPending then txt = txt .. " |cffffa040(update pending)|r" end
  if hid then txt = txt .. " |cffffa040(data hidden)|r" end
  title:SetText(txt)
end

-- Width and scale. The window holds secure row buttons, so its size can't
-- change in combat; callers retry after combat (PLAYER_REGEN_ENABLED).
function X.PanelWidget(kind, name, parent, template)
  local ok, widget = pcall(CreateFrame, kind, name, parent, template)
  if ok and widget then return widget end
  widget = CreateFrame(kind, name, parent)
  if kind == "Button" then
    widget:SetNormalFontObject(GameFontNormal)
    widget:SetHighlightFontObject(GameFontHighlight)
    local texture = widget:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    texture:SetColorTexture(0.12, 0.16, 0.21, 0.95)
    if template == "UIPanelCloseButton" then widget:SetSize(22, 22); widget:SetText("×") end
  elseif kind == "EditBox" then
    widget:SetFontObject(GameFontHighlight)
  elseif template == "BackdropTemplate" and kind == "Frame" and not widget.SetBackdrop then
    local texture = widget:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    texture:SetColorTexture(0.04, 0.06, 0.10, 0.95)
  end
  return widget
end

do
  local panels = {}
  local function RestorePanel(widget, key, offset)
    local point = db.rememberPanelPositions and db.panelPoints[key]
    widget:ClearAllPoints()
    if point and UsablePoint(point, widget) and pcall(widget.SetPoint, widget, point[1], UIParent, point[2], point[3], point[4]) then return end
    db.panelPoints[key] = nil
    widget:SetPoint("CENTER", UIParent, "CENTER", 0, offset)
  end

  function X.BindPanelPosition(widget, key, offset)
    panels[key] = { frame = widget, offset = offset }
    RestorePanel(widget, key, offset)
    widget:HookScript("OnShow", function(self) RestorePanel(self, key, offset) end)
    widget:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      if db.rememberPanelPositions then
        local p, relative, rp, x, y = self:GetPoint(1)
        if relative == UIParent then db.panelPoints[key] = X.Settings.CopyPoint({ p, rp, x, y }) end
      end
    end)
  end

  function X.PanelPositions(mode)
    if mode == "on" then db.rememberPanelPositions = true
    elseif mode == "off" or mode == "reset" then
      if mode == "off" then db.rememberPanelPositions = false end
      wipe(db.panelPoints)
      for key, info in pairs(panels) do RestorePanel(info.frame, key, info.offset) end
    else return false end
    return true
  end
end

local function ApplyGeometry()
  if not frame then return end
  if InCombatLockdown() then
    geometryPending = true  -- lands at PLAYER_REGEN_ENABLED; the title says so meanwhile (1.12.0)
    UpdateTitleMarks()
    return
  end
  geometryPending = nil
  -- Two-column layout (1.9.0): each column keeps the chosen width, with
  -- a small gap between the columns.
  local cols = columns
  frame:SetWidth((db.width or WIDTH) * cols + (cols - 1) * 6)
  frame:SetScale(db.scale or 1)
  UpdateTitleMarks()
end

local function ApplyAppearance()
  if not frame then return end
  if InCombatLockdown() then
    appearancePending = true
    return
  end
  appearancePending = nil
  flashPending = nil
  local c = X.ThemeBackground()
  local bc = X.ThemeBorder()
  if frame.SetBackdropColor then
    frame:SetBackdropColor(c[1], c[2], c[3], db.bgAlpha or 0.92)
    frame:SetBackdropBorderColor(bc[1], bc[2], bc[3], db.showBorder and 1 or 0)
  end
  for i = 1, #rows do TintRowHover(rows[i]) end
  if pill and pill.SetBackdropColor then
    pill:SetBackdropColor(c[1], c[2], c[3], db.bgAlpha or 0.92)
    pill:SetBackdropBorderColor(bc[1], bc[2], bc[3], db.showBorder and 1 or 0)
  end
  if grip then grip:SetShown(not db.locked) end
  if leftGrip then leftGrip:SetShown(not db.locked) end
  if widthHandle then widthHandle:SetShown(not db.locked) end
  title:SetShown(db.showTitle and true or false)
  if titleLayoutState ~= db.showTitle then X.ApplyRowLayout() end
  combatText:ClearAllPoints()
  if db.showTitle then
    combatText:SetPoint("LEFT", title, "RIGHT", 6, 0)
  else
    combatText:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -8)
  end
end

-- Briefly highlight the window when a pull ends or a countdown starts.
function X.Flash(soft)
  if not frame or not frame.SetBackdropBorderColor or InCombatLockdown() or db.reduceMotion then return end
  if soft and not frame:IsVisible() then return end
  if soft then frame:SetBackdropBorderColor(1, 0.7, 0.28, 0.58)
  else frame:SetBackdropBorderColor(1, 0.35, 0.35, 1) end
  if C_Timer and C_Timer.After then
    C_Timer.After(0.7, ApplyAppearance)
  else
    flashPending = true  -- no timer API: Refresh() restores it next pass
  end
  return true
end

do
  local function LoadFinished(ok, loaded, ...)
    if not ok or not Readable(loaded) then return false end
    -- The two-result API can report loaded while the addon's load is
    -- still in progress. A legacy one-result API has no separate flag.
    if select("#", ...) == 0 then return loaded == true or loaded == 1 end
    local finished = ...
    return loaded == true and Readable(finished) and finished == true
  end

  function X.ThemeCandidate(name)
    if name == "custom" and db then return { label = L["Custom theme"], bg = db.bgColor, border = { 0.35, 0.55, 0.8 } } end
    if name ~= X.AUTO_THEME_ID then return X.ThemeDef(name) end
    local resolved, selectedAddon
    if db then
      resolved = "midnight"
      local isLoaded = _G.C_AddOns and _G.C_AddOns.IsAddOnLoaded
      if type(isLoaded) ~= "function" then isLoaded = _G.IsAddOnLoaded end
      if type(isLoaded) == "function" then
        for _, entry in ipairs(X.AutoThemePriority()) do
          if LoadFinished(pcall(isLoaded, entry[1])) then
            resolved, selectedAddon = entry[2], entry[1]
            break
          end
        end
      end
    end
    return X.THEMES[resolved or "midnight"], selectedAddon
  end

  function X.ResolveAutoTheme()
    local resolved, selectedAddon
    if db and db.theme == X.AUTO_THEME_ID then
      local candidate
      candidate, selectedAddon = X.ThemeCandidate(X.AUTO_THEME_ID)
      for id, definition in pairs(X.THEMES) do if definition == candidate then resolved = id; break end end
    end
    if X.autoThemeResolved == resolved and X.autoThemeAddon == selectedAddon then
      if X.RefreshAutoThemePriority then X.RefreshAutoThemePriority() end
      if themePreview then
        ApplyAppearance()
        if X.RefreshThemePreview then X.RefreshThemePreview() end
      end
      return false
    end
    X.autoThemeResolved, X.autoThemeAddon = resolved, selectedAddon
    ApplyAppearance()
    if X.RefreshConfig then X.RefreshConfig() end
    return true
  end

  function X.CancelThemePreview(owner)
    if not themePreview or (owner and owner ~= themePreview) then return false end
    themePreview = nil
    ApplyAppearance()
    return true
  end

  function X.BeginThemePreview()
    X.CancelThemePreview()
    if not db or InCombatLockdown() or X.PlayerSuspended() or X.Settings.SaveState() == "future" then return end
    themePreview = { db = db, generation = X.Preferences.Generation(), theme = db.theme,
      priority = db.autoThemePriority, color = { db.bgColor[1], db.bgColor[2], db.bgColor[3] }, selected = db.theme }
    return themePreview
  end

  function X.ThemePreviewState(owner)
    owner = owner or themePreview
    if not OwnsThemePreview(owner) then X.CancelThemePreview(owner); return end
    local candidate, selectedAddon = X.ThemeCandidate(owner.selected)
    if not candidate then X.CancelThemePreview(owner); return end
    return { id = owner.selected, label = candidate.label, bg = candidate.bg, border = candidate.border, addon = selectedAddon }
  end

  function X.PreviewTheme(owner, name)
    if not OwnsThemePreview(owner) or type(name) ~= "string" or not X.ThemeCandidate(name) then return false end
    owner.selected = name
    ApplyAppearance()
    return true
  end

  function X.ApplyThemePreview(owner)
    if not owner then return false end
    local candidate = X.ThemePreviewState(owner)
    if not candidate then return false end
    local changes = { theme = candidate.id }
    if candidate.id ~= X.AUTO_THEME_ID then changes.bgColor = { candidate.bg[1], candidate.bg[2], candidate.bg[3] } end
    themePreview = nil
    local ok = X.Preferences.Transaction(changes, "ui")
    X.ResolveAutoTheme()
    ApplyAppearance()
    if X.RefreshConfig then X.RefreshConfig() end
    return ok
  end

  X.OnDBLoaded(function() X.CancelThemePreview() end)
end

local function ApplyRowWheel()
  if not frame or InCombatLockdown() then return end
  local enabled = (viewportCount or 0) > visibleLimit and not (db.clickThrough and db.locked)
  if rowWheelEnabled == enabled then return end
  rowWheelEnabled = enabled
  frame:EnableMouseWheel(enabled)
  for _, row in ipairs(rows) do row:EnableMouseWheel(enabled) end
end

local function ClearRowViewport()
  viewport, rowOffset, viewportCount = nil, nil, nil
  if frame and not InCombatLockdown() then
    ApplyRowWheel()
    SetShownIfChanged(overflowText, false)
  end
end

-- Click-through (1.10.0): while the window is locked AND the player
-- asked for it, the window and its rows stop eating mouse clicks, so
-- clicks land on the game world behind them. Never changed in combat
-- (secure buttons refuse it there); re-applied when combat ends and
-- whenever the lock or the setting changes.
function X.ApplyClickThrough()
  if not frame or not db then return end
  if InCombatLockdown and InCombatLockdown() then return end
  local mouse = not (db.clickThrough and db.locked)
  if frame.EnableMouse then frame:EnableMouse(mouse) end
  for i = 1, MAX_ROWS do
    local row = rows[i]
    if row and row.EnableMouse then row:EnableMouse(mouse) end
  end
  if nextBtn and nextBtn.EnableMouse then nextBtn:EnableMouse(mouse) end
  if nextPreview then nextPreview:EnableMouse(mouse) end
  if nearbyButton then nearbyButton:SetShown(mouse) end
  ApplyRowWheel()
  if X.UpdateFade then X.UpdateFade() end
end

-- Compact rows, text scale and column layout. Re-anchoring secure rows
-- must wait until combat ends.
function X.ApplyRowLayout()
  if not frame or InCombatLockdown() then return end
  titleLayoutState = db.showTitle
  local h = db.compact and 16 or ROW_H
  local header = db.showTitle and HEADER_H or 0
  local barHeight = BarHeight()
  rowHeight = h
  if findBar then
    findBar:SetShown(db.findBox and true or false)
    findBar:ClearAllPoints()
    findBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -header - barHeight)
    findBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -header - barHeight)
  end
  local top = header + barHeight + (db.findBox and 16 or 0)
  topHeight = top
  if bar then
    bar:SetShown(barHeight > 0)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -header)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -header)
  end
  if widthHandle then
    widthHandle:ClearAllPoints()
    widthHandle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -header)
    widthHandle:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 18)
  end
  emptyText:ClearAllPoints()
  emptyText:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -top - 3)
  countText:ClearAllPoints()
  if db.showTitle then
    countText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -6)
  else
    countText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 6)
  end
  if footerText then
    footerText:ClearAllPoints()
    footerText:SetPoint("LEFT", nearbyButton or gear, "RIGHT", 5, 0)
    footerText:SetPoint("RIGHT", frame, "BOTTOMRIGHT", db.showTitle and -16 or -48, 13)
  end
  -- Two-column layout (1.9.0): rows fill the first column top to
  -- bottom, then the second. PaintRowViewport selects the column count.
  local per = rowsPerColumn
  local cols = columns
  local cellW = (db.width or WIDTH) + 6  -- column width + the gap
  local isz = (db.iconSize or 0) > 0 and db.iconSize or (db.compact and 12 or 16)
  local ts = db.textScale or 1
  for i, row in ipairs(rows) do
    local col = math_floor((i - 1) / per)
    local idx = (i - 1) % per
    row:SetHeight(h)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 6 + col * cellW, -top - idx * (h + (db.rowGap or 0)))
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(6 + (cols - 1 - col) * cellW), -top - idx * (h + (db.rowGap or 0)))
    if row.portrait then row.portrait:SetShown(not db.compact) end
    for j = 1, MAX_ICONS do if row.icons[j] then row.icons[j]:SetSize(isz, isz) end end
    if row.name then row.name:SetScale(ts) end
    if row.tag then row.tag:SetScale(ts) end
  end
end

local function UpdateCounter()
  if not footerText then return end
  SetShownIfChanged(footerText, db.showCounter == true)
  local total = db.castsTotal or 0
  -- The counter shares its row with the settings gear and stops short of the
  -- resize grip, so a narrow window used to cut it to "39 all-t...". Width is
  -- part of the cache key so a resize re-fits the line, not just a new cast.
  local room = footerText:GetWidth() or 0
  if X.sessionCasts ~= lastCounterSession or total ~= lastCounterTotal
     or room ~= lastCounterRoom then
    lastCounterSession, lastCounterTotal, lastCounterRoom = X.sessionCasts, total, room
    footerText:SetText(string_format(L["Casts: |cffffffff%d|r this session  ·  |cffffffff%d|r all-time"],
      X.sessionCasts, total))
    if room > 0 and footerText:GetStringWidth() > room then
      footerText:SetText(string_format(L["Casts: |cffffffff%d|r / |cffffffff%d|r"],
        X.sessionCasts, total))
    end
  end
end

local function ClearRow(row)
  row.entry, row.guid = nil, nil
  if row.bGuid ~= nil then ClearRowCast(row) end
  if row:IsShown() then row:Hide() end
end

local function InvalidateRows()
  for i = 1, #rows do
    local row = rows[i]
    row.cGuid, row.cUnit, row.cTag = nil, nil, nil
    -- false means rebuild (or clear if this row is retired), not disarmed.
    if row.bGuid ~= nil then row.bGuid = false end
    row.cBar, row.cMarker = nil, nil
    row.cTint = nil
    wipe(row.cMissing)
  end
  if nextBtn then nextBtn.bGuid, nextBtn.isClear = nil, false end
end

-- The name shown on a row (1.10.0): optionally with the realm, and
-- optionally shortened.
local function DispName(e)
  local nm = (db.showRealm and e.fullName) or e.name or ""
  local trim = db.nameTrim or 0
  if trim > 0 and Readable(nm) and type(nm) == "string" and #nm > trim then
    local count = 0
    -- Skip UTF-8 continuation bytes when looking for the first character
    -- beyond the display limit. Keep the engine's original text if unreadable.
    for offset in nm:gmatch("()[^\128-\191]") do
      if count == trim then return nm:sub(1, offset - 1) .. "…" end
      count = count + 1
    end
  end
  return nm
end

-- Tag symbols (1.12.0): with tagSymbols on, a status tag also carries a
-- symbol, so its meaning never rests on color alone.
function X.InvalidateTags()
  for i = 1, #rows do rows[i].cTag = false end
  QueueRefresh()
end

-- Label and symbol are keyed by the same status, not translated text.
-- Earlier entries win when more than one status applies.
local ROW_TAGS = {
  { "expired", "a buff just expired", "!" },
  { "rezzed", "recently rezzed", "+" },
  { "queued", "up next", ">" },
  { "handled", "being buffed", "~" },
  { "mine", "your assignment", "#" },
  { "theirs", "assigned elsewhere", "x" },
  { "buddy", "buddy's watch", "&" },
  { "pinned", "pinned", "^" },
  { "weapon", "weapon enchant missing", "/" },
  { "drinking", "drinking", "o" },
  { "asked", "asked for a buff", "?" },
  { "pet", "pet", "p" },
}

local function RowTag(entry, symbols)
  for _, tag in ipairs(ROW_TAGS) do
    if entry[tag[1]] then return symbols and (tag[3] .. " " .. L[tag[2]]) or L[tag[2]] end
  end
  local left = entry.remain1
  if left then
    return left >= 90 and string_format(L["~%dm left"], math_floor(left / 60))
      or string_format(L["~%ds left"], math_floor(left))
  end
end

local function SetNameOffset(row, y)
  row.name:ClearAllPoints()
  row.name:SetPoint("LEFT", row.portrait, "RIGHT", 6, y)
  row.name:SetPoint("RIGHT", row, "RIGHT", -IconInset(), y)
end

local function RenderRowName(row, e)
  if row.cGuid == e.guid and row.cUnit == e.unit then return end
  if SetPortraitTexture then pcall(SetPortraitTexture, row.portrait, e.unit) end
  row.name:SetText(DispName(e))
  row.cGuid, row.cUnit = e.guid, e.unit
  if db.classColors then row.name:SetTextColor(ClassColor(e.class))
  else row.name:SetTextColor(0.92, 0.92, 0.92) end
end

local function RenderRowTag(row, entry)
  local tag = RowTag(entry, db.tagSymbols)
  if row.cTag == tag then return end
  row.cTag = tag
  if tag then
    row.tag:SetText(tag)
    SetNameOffset(row, 5)
    row.tag:Show()
  else
    row.tag:Hide()
    SetNameOffset(row, 0)
  end
end

local function RenderDurationBar(row, e)
  -- Duration bar (1.8.0): the expiring buff's remaining time as a share
  -- of 30 minutes; the color band shifts green -> yellow -> red.
  local barKey
  if db.durationBars and e.remain1 and e.remain1 < math_huge then
    local frac = math_min(1, e.remain1 / 1800)
    local band = e.remain1 < 300 and 1 or (e.remain1 < 900 and 2 or 3)
    barKey = math_floor(frac * 40) .. ":" .. band
    if row.cBar ~= barKey then
      row.cBar = barKey
      row.bar:SetWidth(math_max(2, (row:GetWidth() - 4) * frac))
      if band == 1 then row.bar:SetVertexColor(1, 0.3, 0.3)
      elseif band == 2 then row.bar:SetVertexColor(1, 0.85, 0.4)
      else row.bar:SetVertexColor(0.4, 0.9, 0.4) end
      row.bar:Show()
    end
  end
  if not barKey then
    -- Unconditional: InvalidateRows clears the cache without touching
    -- the texture, so the hide can't ride on the cache alone.
    row.cBar = nil
    row.bar:Hide()
  end
end

local function RenderRaidMarker(row, e)
  -- Raid marker badge (1.8.0).
  local mk = (db.raidMarkers and e.marker) or nil
  if row.cMarker ~= mk then
    row.cMarker = mk
    if mk then
      row.marker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. mk)
      row.marker:Show()
    else
      row.marker:Hide()
    end
  end
  if not mk then row.marker:Hide() end
end

local function RenderRowTint(row, e)
  -- Row color mark (1.10.0): a colored strip on the row's left edge for
  -- the first matching rule you switched on — yours, tanks, expiring
  -- soon, your split partner's half.
  local tint
  local rc = db.rowColors
  if rc then
    if rc.mine and e.mine then tint = rc.mine
    elseif rc.tank and e.role == 1 then tint = rc.tank
    elseif rc.expiring and (e.expired or (e.remain1 and e.remain1 < 300)) then tint = rc.expiring
    elseif rc.buddy and e.buddy then tint = rc.buddy end
  end
  if row.cTint ~= tint then
    row.cTint = tint
    if tint then
      row.tint:SetVertexColor(tint[1], tint[2], tint[3])
      row.tint:Show()
    else
      row.tint:Hide()
    end
  end
  if not tint then row.tint:Hide() end
end

local function RenderRowIcons(row, m)
  local cm, changed = row.cMissing, false
  for j = 1, MAX_ICONS do
    if cm[j] ~= m[j] then changed = true; break end
  end
  if changed then
    for j = 1, MAX_ICONS do
      local t, spell = row.icons[j], m[j]
      if spell then
        t:SetTexture(SpellIcon(spell))
        t:SetAlpha(j == 1 and 1 or 0.5)
        t:Show()
      else
        t:Hide()
      end
      cm[j] = spell
    end
  end
end

local function RenderRow(row, e, cached)
  row.entry, row.guid = e, e.guid
  RenderRowName(row, e)
  RenderRowTag(row, e)
  RenderDurationBar(row, e)
  RenderRaidMarker(row, e)
  RenderRowTint(row, e)
  local m = e.missing
  RenderRowIcons(row, m)
  if cached and not X.RowTargetMatches(e) then
    -- A cached entry whose unit token was recycled is display-only.
    row:SetAlpha(0.6)
    if row.bGuid ~= nil then ClearRowCast(row) end
  else
    row:SetAlpha(1)
    BindCached(row, e.unit, m[1], e.castGuid or e.guid)
  end
  if not row:IsShown() then row:Show() end
end

-- Row color marks (1.10.0): named colors for the row edge strip.
X.ROW_PALETTE = {
  gold = { 1, 0.8, 0.2 }, sky = { 0.4, 0.7, 1 }, red = { 1, 0.35, 0.35 },
  green = { 0.45, 0.95, 0.45 }, violet = { 0.75, 0.5, 1 },
}
X.ROW_PALETTE_ORDER = { "gold", "sky", "red", "green", "violet" }

function X.RowColorName(rule)
  local c = db.rowColors and db.rowColors[rule]
  if not c then return "off" end
  for name, rgb in pairs(X.ROW_PALETTE) do
    if rgb[1] == c[1] and rgb[2] == c[2] and rgb[3] == c[3] then return name end
  end
  return "custom"
end

function X.SetRowColor(rule, c)
  db.rowColors = db.rowColors or {}
  db.rowColors[rule] = c and { c[1], c[2], c[3] } or nil
  InvalidateRows()
  QueueRefresh()
end

function X.AbortWindowScan()
  viewport, viewportCount, rowOffset = nil, nil, nil
  if nextBtn then nextBtn.entry, nextBtn.isClear = nil, false end
  if groupBtn then groupBtn.entry, groupBtn.isClear = nil, false end
  for _, row in ipairs(rows) do row.entry, row.guid = nil, nil end
  rowLeftPress = nil
  wipe(rowMouseButtons)
  if InCombatLockdown() then return end -- secure combat drivers own clearing here
  pcall(ClearNext)
  pcall(ClearGroup)
  for _, row in ipairs(rows) do
    pcall(ClearRowCast, row)
    pcall(row.Hide, row)
  end
  pcall(X.ShowWindowStatus, not db.hidden and L["Buff scan interrupted. Waiting for a fresh scan."])
end

-- Drop paused or hidden rows without changing the independent keybind queue.
-- A pause whose status is suppressed leaves an already-collapsed pill alone.
function X.ShowWindowStatus(text, keepPill)
  ClearRowViewport()
  for _, row in ipairs(rows) do ClearRow(row) end
  if pill and not keepPill then SetShownIfChanged(pill, false) end
  if not text then
    SetShownIfChanged(frame, false)
    return
  end
  if focusText then SetShownIfChanged(focusText, false) end
  SetShownIfChanged(coverText, false)
  SetTextIfChanged(countText, "")
  SetShownIfChanged(overflowText, false)
  SetTextIfChanged(emptyText, text)
  SetShownIfChanged(emptyText, true)
  UpdateCounter()
  SetHeightIfChanged(frame, topHeight + 26 + FOOTER_H)
  SetShownIfChanged(frame, true)
end

-- Pick an honest explanation for an empty list when the client cannot verify range.
function X.EmptyStatus()
  if X.scanHasUnknownBuffs or (X.tallyUnknownUnits or 0) > 0 then
    return L["Some buff information is unavailable."]
  end
  if X.FriendlyPlatesOn() == false then
    return L["Friendly nameplates are off."]
  end
  if X.rangeSilent then
    return L["Range could not be confirmed; the list may be incomplete."]
  end
  if X.scanNameFiltered then return L["The name finder hides all buff targets."] end
  if (X.lastTargetCastProblem and GetTime() < X.lastTargetCastProblem.expires)
     or NoCastReason() then return L["No cast target is available."] end
  return L["No targets in the buff queue."]
end

local function EmptyStatusHint()
  if X.FriendlyPlatesOn() == false then return L["Use /br plates to see nearby players."] end
  if X.rangeSilent then return L["Move closer or use /br why <name>."] end
  if X.lastTargetCastProblem and GetTime() < X.lastTargetCastProblem.expires then
    return X.lastTargetCastProblem.message
  end
  return NoCastReason()
end

-- Coverage-line parts (1.10.0): the line is assembled from parts, each
-- with its own switch in db.coverParts; absent means on.
local function CoverOn(part)
  local cp = db and db.coverParts
  return not cp or cp[part] ~= false
end

-- Group-by-buff view (1.10.0): fold the people entries into one row
-- per buff still needed. Each folded row stands for the buff itself:
-- its name carries the count, and it borrows an in-range holder (if
-- any) as its cast target, so clicking the row buffs that player with
-- exactly that spell. Only the render stage uses the folded list --
-- coverage, sounds and reports keep working on people.
local function BuildBuffView(list, n)
  local bySpell, order = {}, {}
  for i = 1, n do
    local e = list[i]
    if not e.header then
      for j = 1, #(e.missing or {}) do
        local spell = e.missing[j]
        local g = bySpell[spell]
        if not g then
          g = { spell = spell, count = 0, missing = { spell }, group = true }
          bySpell[spell] = g
          order[#order + 1] = g
        end
        g.count = g.count + 1
        if g.unit == nil then
          g.unit, g.class, g.castGuid, g.pet = e.unit, e.class, e.guid, e.pet
          g.approximateRange = e.approximateRange
        end
      end
    end
  end
  table_sort(order, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.spell < b.spell
  end)
  for i = 1, #order do
    local g = order[i]
    g.name = g.count > 1 and (g.spell .. " x" .. g.count) or g.spell
    g.sortName = g.spell
    g.guid = "buff:" .. g.spell .. "#" .. g.count
  end
  return order, #order
end

local function FitRows(n, extraHeight)
  local height = X.ReadUnitNumber(UIParent.GetHeight, UIParent)
  local width = X.ReadUnitNumber(UIParent.GetWidth, UIParent)
  local scale = db.scale or 1 -- frame is a direct child of UIParent
  height = height and height > 0 and height / scale - 12 or math.huge
  width = width and width > 0 and width / scale - 12 or math.huge
  local gap = db.rowGap or 0
  local budget = height - topHeight - FOOTER_H - 8 - extraHeight + gap
  local pitch = rowHeight + gap
  local single = math_max(1, math_floor(budget / pitch))
  local cols = db.twoCol and width >= (db.width or WIDTH) * 2 + 6 and (n > 8 or n > single) and 2 or 1
  if n > math_min(MAX_ROWS, single * cols) then
    single = math_max(1, math_floor((budget - 14) / pitch))
  end
  return math_min(MAX_ROWS, single * cols), cols
end

local function PaintRowViewport(cached, extraHeight)
  local view, n = viewport, viewportCount
  local wantCols = columns
  if not cached then visibleLimit, wantCols = FitRows(n, extraHeight) end
  rowOffset = math_min(rowOffset or 0, math_max(0, n - visibleLimit))
  local shown = math_min(n, visibleLimit)
  local rowsTall = wantCols == 2 and math_floor((shown + 1) / 2) or shown
  if wantCols ~= columns or rowsTall ~= (previousRowsTall or shown) then
    columns, previousRowsTall = wantCols, rowsTall
    rowsPerColumn = wantCols == 2 and rowsTall or MAX_ROWS
    X.ApplyRowLayout()
    ApplyGeometry()
  end
  for i = 1, MAX_ROWS do
    if i <= shown then RenderRow(rows[i], view[rowOffset + i], cached) else ClearRow(rows[i]) end
  end
  local overflow = n > visibleLimit
  if overflow then
    local y = -topHeight - rowsTall * rowHeight
      - math_max(0, rowsTall - 1) * (db.rowGap or 0) - 2
    if overflowText.cY ~= y then
      overflowText.cY = y
      overflowText:ClearAllPoints()
      overflowText:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, y)
    end
    SetTextIfChanged(overflowText, string_format(L["Rows %d–%d of %d"], rowOffset + 1, rowOffset + shown, n))
  end
  SetShownIfChanged(overflowText, overflow)
  ApplyRowWheel()
  return shown, rowsTall
end

function X.ScrollRows(step)
  if not viewport or viewportCount <= visibleLimit or db.hidden
      or not frame:IsShown() or InCombatLockdown() or X.PlayerSuspended()
      or (db.clickThrough and db.locked) or RowMouseHeld()
      or X.ReadUnitBool(_G.IsMouseButtonDown, "LeftButton") == true
      or X.ReadUnitBool(_G.IsMouseButtonDown, "RightButton") == true then return false end
  if viewportMode ~= db.viewMode or viewportSearch ~= X.search
      or viewportRole ~= db.roleFilter or viewportTwoCol ~= db.twoCol then return false end
  local offset = math_max(0, math_min(rowOffset + step, viewportCount - visibleLimit))
  if offset == rowOffset then return false end
  local owner = GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner()
  if owner == frame or (owner and owner.GetParent and owner:GetParent() == frame) then GameTooltip:Hide() end
  rowOffset = offset
  local ok, err = pcall(PaintRowViewport, true)
  if not ok then X.RefreshFault(err) end
  return ok
end

local function AppendBuffCoverage(parts)
  for _, b in ipairs(myBuffs) do
    local t = not b.self and X.tally[b.key] or nil
    if t and t.total > 0 then
      local nm = b.key:lower():gsub("_", " ")
      local seg = string_format("%s %d/%d", nm:sub(1, 1):upper() .. nm:sub(2),
        t.total - t.miss, t.total)
      -- A buff on a real cooldown is never counted as missing (you can't
      -- cast it anyway), so its count can look complete while people
      -- still need it -- flag the cooldown so the number isn't trusted
      -- blindly.
      local left = core.CooldownLeft(b.name)
      if left > 5 then
        seg = seg .. (left >= 60 and string_format(L[" (~%dm cd)"], math_floor(left / 60 + 0.5))
                      or string_format(L[" (~%ds cd)"], math_floor(left + 0.5)))
      end
      parts[#parts + 1] = seg
    end
  end
  local tb = X.tally.BLESSINGS
  if tb and tb.total > 0 then
    parts[#parts + 1] = string_format(L["Blessings %d/%d"], tb.total - tb.miss, tb.total)
  end
end

local function CoverageRoster()
  local nowC = GetTime()
  -- Assignment counts keyed by short name: holders are recorded as
  -- typed (often short), users are known by full name.
  local held = {}
  for _, who in pairs(X.assign) do
    local wk = Ignore.Key(who:match("^[^%-]+") or who)
    held[wk] = (held[wk] or 0) + 1
  end
  local duty = {}
  local meF = Ignore.UnitNames("player")
  if meF then
    local mk = Ignore.Key(meF:match("^[^%-]+") or meF)
    duty[#duty + 1] = (meF:match("^[^%-]+") or meF)
      .. (held[mk] and (" (" .. held[mk] .. ")") or "")
  end
  local peerNames = {}
  for k, p in pairs(X.peers) do
    if nowC - p.t < 90 then peerNames[#peerNames + 1] = k end
  end
  table_sort(peerNames)
  for _, k in ipairs(peerNames) do
    local p = X.peers[k]
    local short = (p.name:match("^[^%-]+") or p.name)
    for cname, exp in pairs(X.cover) do
      if exp > nowC and X.SameUser(p.name, cname) then
        short = short .. " (" .. L["Away"] .. ")" break
      end
    end
    local hk = Ignore.Key(p.name:match("^[^%-]+") or p.name)
    if held[hk] then short = short .. " (" .. held[hk] .. ")" end
    duty[#duty + 1] = short
  end
  if #duty > 1 then return "Radar: " .. table.concat(duty, ", ") end
end

local function ExpiringGroupBuffs()
  local worstKey, worstSoon, worstTotal = nil, 0, 0
  for key, soon in pairs(X.expiryTally) do
    local t = X.tally[key]
    if t and soon >= 3 and soon * 2 >= t.total and soon > worstSoon then
      worstKey, worstSoon, worstTotal = key, soon, t.total
    end
  end
  if worstKey then
    local nm = worstKey == "BLESSINGS" and "Blessings" or worstKey
    if worstKey ~= "BLESSINGS" then
      for _, def in ipairs(myBuffs) do
        if def.key == worstKey then nm = def.name break end
      end
    end
    return string_format(L["%s <5m on %d/%d"], nm, worstSoon, worstTotal)
  end
end

local function RenderCoverage(entries, n)
  if X.tallyUnits <= 1 and (X.tallyUnits == 0 or X.tallyUnknownUnits == 0) then
    SetShownIfChanged(coverText, false)
    return false
  end
  local parts = {}
  if CoverOn("progress") then
    parts[#parts + 1] = string_format(L["%d/%d fully buffed"], X.tallyUnits - X.tallyMissingUnits, X.tallyUnits)
  end
  if CoverOn("buffs") then AppendBuffCoverage(parts) end
  if db.consumables then
    for _, cd in ipairs(X.CONS_DEFS) do
      local t = X.consTally[cd.key]
      if t then
        local text = t.total > 0 and string_format("%s %d/%d", L[cd.label], t.total - t.miss, t.total) or L[cd.label]
        parts[#parts + 1] = text .. (t.unknown > 0 and (" · " .. string_format(L["%d unknown"], t.unknown)) or "")
      end
    end
  end
  -- Coverage uptime (1.6.0): the share of grouped scans this run that
  -- found nobody missing anything. A scan-based score, reset when a
  -- Mythic+ run starts and when the group ends.
  if X.tallyUnknownUnits == 0 then
    X.upTotal = X.upTotal + 1
    if X.tallyMissingUnits == 0 then X.upFull = X.upFull + 1 end
  end
  if X.upTotal >= 10 and CoverOn("uptime") then
    parts[#parts + 1] = string_format(L["Uptime %d%%"],
      math_floor(100 * X.upFull / X.upTotal + 0.5))
  end
  if db.sync and CoverOn("roster") then parts[#parts + 1] = CoverageRoster() end
  if CoverOn("expiry") then parts[#parts + 1] = ExpiringGroupBuffs() end
  -- Weapon watch (1.7.0): when your own row isn't on the list to
  -- carry the tag, the coverage line carries the reminder instead.
  if db.weaponWatch and not db.liteMode and X.WeaponEnchantMissing() then
    local selfListed = false
    for i = 1, n do
      if entries[i].isSelf then selfListed = true break end
    end
    if not selfListed then
      parts[#parts + 1] = "your weapon has no enchant"
    end
  end
  -- World-buff watch (1.8.0): your active world buffs, with time left.
  if db.worldWatch and not db.liteMode and CoverOn("world") then
    local wb = X.WorldBuffsText()
    if wb then parts[#parts + 1] = wb end
  end
  -- Healer drinking (1.8.0): healers sitting down to drink between
  -- pulls — the group waits for them, not the other way round.
  if db.drinkWatch and not db.liteMode and CoverOn("drink") and (X.drinkHealers or 0) > 0 then
    parts[#parts + 1] = X.drinkHealers == 1 and "Healer drinking"
      or string_format(L["%d healers drinking"], X.drinkHealers)
  end
  -- Pull countdown (1.15.0): while a pull timer runs (Extras tracks it
  -- in X.pull), the coverage line itself counts down -- the part of the
  -- pull-timer feature 1.14.0 trimmed. The steady ticker rebuilds this
  -- line every 0.4s while the list is live, and Extras refreshes again
  -- the moment the timer ends, so the number never goes stale.
  if X.pull and X.pull.endsAt then
    local left = math_ceil(X.pull.endsAt - GetTime())
    if left > 0 then parts[#parts + 1] = string_format(L["Pull in %ds"], left) end
  end
  SetTextIfChanged(coverText, table.concat(parts, "  ·  "))
  SetShownIfChanged(coverText, #parts > 0)
  return #parts > 0
end

function X.RenderQueue(entries, n, sessionShow, wasAfterCombat)
  -- group-by-buff view folds the render list; everything above this
  -- point (coverage, sounds, counts) still works on people
  local viewEntries, viewN = entries, n
  if db.viewMode == "buffs" then viewEntries, viewN = BuildBuffView(entries, n) end
  if viewportMode ~= db.viewMode or viewportSearch ~= X.search or viewportRole ~= db.roleFilter then
    rowOffset = nil
  end
  viewportMode, viewportSearch, viewportRole = db.viewMode, X.search, db.roleFilter
  viewportTwoCol = db.twoCol
  viewport, viewportCount = viewEntries, viewN
  -- Post-combat catch-up: one border pulse when the frozen list thaws with
  -- work waiting, so a pull's-end rebuff round doesn't go unnoticed.
  if wasAfterCombat and n > 0 and X.Flash then X.Flash() end

  SetTextIfChanged(countText, n > 0 and n or "")
  local hint
  if n == 0 then
    hint = EmptyStatusHint()
    SetTextIfChanged(emptyText, X.EmptyStatus() .. (hint and "\n" .. hint or ""))
  end
  SetShownIfChanged(emptyText, n == 0)

  local coverShown = RenderCoverage(entries, n)
  local focusLine = db.focusWatch and not db.liteMode and focusText and core.FocusLine()
  if focusText then
    if focusLine then SetTextIfChanged(focusText, focusLine) end
    SetShownIfChanged(focusText, focusLine and true or false)
  end

  local extras = (coverShown and 13 or 0) + (focusLine and 13 or 0)
  local shown, rowsTall = PaintRowViewport(false, extras)
  if X.UpdateNearbyTargetAfterScan then X.UpdateNearbyTargetAfterScan() end
  local h = topHeight + (shown > 0 and rowsTall * rowHeight + math_max(0, rowsTall - 1) * (db.rowGap or 0) or 18) + 8
  if hint then h = h + 13 end
  if coverShown then h = h + 13 end
  if focusLine then h = h + 13 end
  if viewN > visibleLimit then h = h + 14 end
  h = h + FOOTER_H  -- bottom row: settings gear + cast counter
  UpdateCounter()
  SetHeightIfChanged(frame, h)

  -- All-buffed pill (1.6.0): in a group with nobody missing anything, the
  -- window can collapse to the pill until someone needs a buff again (or
  -- the pill is clicked for a peek).
  local pillMode = db.pill and n == 0 and X.InGroup() and not db.hidden
    and core.ScanConfirmsGroupBuffed() and GetTime() > (pillPeek or 0)
  if pillMode and pill then
    SetTextIfChanged(pill.text, "|cff33ccffBuff|rRadar · "
      .. string_format("%d/%d ", X.tallyUnits - X.tallyMissingUnits, X.tallyUnits) .. L["All buffed"])
    SetShownIfChanged(frame, false)
    SetShownIfChanged(pill, true)
  else
    if pill then SetShownIfChanged(pill, false) end
    SetShownIfChanged(frame, not (db.autoHide and n == 0 and not sessionShow))
  end
end

-- Scale drag (1.11.0). Cursor-driven; the OnUpdate runs only while a grip is
-- held. Scale = the cursor's horizontal distance from the fixed bottom
-- corner divided by the window's unscaled width.
local SNAPS = { 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2 }

local function ScaleFromCursor(g)
  local cx = GetCursorPosition() / UIParent:GetEffectiveScale()
  local w = g.baseW
  if not w or w <= 0 then return db.scale or 1 end
  local ns = (g.side == "RIGHT") and (cx - g.fixedX) / w or (g.fixedX - cx) / w
  if db.gripSnap ~= false and IsShiftKeyDown and IsShiftKeyDown() then
    local best, bd = ns, 0.06  -- Shift: snap to a preset within 6%
    for _, p in ipairs(SNAPS) do
      local d = math.abs(ns - p)
      if d < bd then best, bd = p, d end
    end
    ns = best
  end
  if ns < 0.5 then ns = 0.5 elseif ns > 2 then ns = 2 end  -- same bounds as RANGES.scale
  return ns
end

local function PlaceScaled(g, ns)
  local left = (g.side == "RIGHT") and g.fixedX or (g.fixedX - g.baseW * ns)
  frame:SetScale(ns)
  frame:ClearAllPoints()
  if db.growUp then
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left / ns, g.fixedY / ns)
  else
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / ns, g.fixedY / ns)
  end
end

local function EndEdgeDrag(e)
  if not e or not e.isSizing or InCombatLockdown() then return end
  e.isSizing = false
  frame:StopMovingOrSizing()
  local cols = columns
  local w = (frame:GetWidth() - (cols - 1) * 6) / cols
  db.width = math.max(MIN_WIDTH, math.min(MAX_WIDTH, math_floor(w + 0.5)))
  ApplyGeometry()
  SavePosition()
end

local EndScaleDrag
local function BeginScaleDrag(g)
  local s = frame:GetScale() or 1
  local l, r = frame:GetLeft(), frame:GetRight()
  local y = db.growUp and frame:GetBottom() or frame:GetTop()
  if not (l and r and y) then return end
  g.baseW = frame:GetWidth()
  g.fixedX = (g.side == "RIGHT") and l * s or r * s
  g.fixedY = y * s
  g.isSizing = true
  g:SetScript("OnUpdate", function(self)
    if InCombatLockdown() then EndScaleDrag(self); return end
    local ns = ScaleFromCursor(self)
    db.scale = ns
    PlaceScaled(self, ns)
  end)
end

EndScaleDrag = function(g)
  if not g or not g.isSizing then return end
  g:SetScript("OnUpdate", nil)
  if InCombatLockdown() then return end
  g.isSizing = false
  local ns = math_floor((db.scale or 1) * 100 + 0.5) / 100
  db.scale = ns
  PlaceScaled(g, ns)
  SavePosition()
  if X.RefreshConfig then X.RefreshConfig() end
end

local function EndWindowDrags()
  if InCombatLockdown() then return end
  if frame and frame.isMoving then
    frame:StopMovingOrSizing()
    frame.isMoving = false
    SavePosition()
  end
  EndScaleDrag(grip)
  EndScaleDrag(leftGrip)
  EndEdgeDrag(widthHandle)
end

local function HideOwnedTooltip()
  if not GameTooltip or not GameTooltip.GetOwner then return end
  local owner = GameTooltip:GetOwner()
  if not owner then return end
  local config = _G.BuffRadarConfig
  while owner do
    if owner == frame or owner == config or owner == _G.BuffRadarMinimapButton
       or owner == pill or owner == X.wizardFrame or owner == X.exportFrame then
      GameTooltip:Hide()
      return
    end
    if not owner.GetParent then return end
    owner = owner:GetParent()
  end
end

function X.SuspendWindow()
  ClearRowViewport()
  wipe(rowMouseButtons)
  rowLeftPress = nil
  pillPeek = nil
  HideOwnedTooltip()
  if X.HideConfig then X.HideConfig() end
  if X.CloseRaidPreparation then X.CloseRaidPreparation() end
  if X.CloseNearbyDiagnostics then X.CloseNearbyDiagnostics() end
  if X.wizardFrame and X.wizardFrame:IsShown() then X.wizardFrame:Hide() end
  if X.exportFrame and X.exportFrame:IsShown() then X.exportFrame:Hide() end
  if X.EndEditMode then X.EndEditMode(true) end
  X.RefreshMinimapButton()

  -- The state drivers hide and disarm protected frames during lockdown.
  -- Clear the Lua-side click bookkeeping immediately in either case.
  local locked = InCombatLockdown()
  if nextBtn then nextBtn.entry = nil end
  if groupBtn then groupBtn.entry = nil end
  for i = 1, #rows do
    rows[i].entry, rows[i].guid = nil, nil
    if not locked then
      ClearRowCast(rows[i])
      ClearRow(rows[i])
    end
  end
  if locked then return end
  EndWindowDrags()
  ClearNext()
  ClearGroup()
  if frame then SetShownIfChanged(frame, false) end
  if pill then SetShownIfChanged(pill, false) end
end

local function BuildWindowFrame()
  frame = X.PanelWidget("Frame", "BuffRadarFrame", UIParent,
                      BackdropTemplateMixin and "BackdropTemplate" or nil)
  if X.PlayerSuspended() then frame:Hide() end
  frame:SetSize(db.width or WIDTH, HEADER_H + 30)
  -- Keep the client's default MEDIUM layer. Changing strata on the live
  -- frame can be blocked by some Forever clients and is not needed for casts.
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:SetResizable(true)
  -- Only the width is user-sized (StartSizing("RIGHT")); the height bounds are
  -- wide open because Refresh() sets the height to fit the list.
  if frame.SetResizeBounds then
    frame:SetResizeBounds(MIN_WIDTH, 1, MAX_WIDTH, 4000)
  elseif frame.SetMinResize then
    frame:SetMinResize(MIN_WIDTH, 1)
    frame:SetMaxResize(MAX_WIDTH, 4000)
  end
  frame:EnableMouse(true)
  frame:SetScript("OnMouseWheel", RowWheel)
  frame:EnableMouseWheel(false)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    if not db.locked and not InCombatLockdown() then
      self:StartMoving()
      self.isMoving = true
    end
  end)
  frame:SetScript("OnDragStop", function(self)
    if not self.isMoving or InCombatLockdown() then return end
    self:StopMovingOrSizing()
    self.isMoving = false
    SavePosition()
  end)
  if frame.SetBackdrop then
    frame:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.04, 0.05, 0.09, 0.92)
    frame:SetBackdropBorderColor(0.35, 0.55, 0.8, 1)
  end
end

local function BuildCloseControl()
  title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 9, -7)
  title:SetText(L["|cff33ccffBuff|rRadar"])

  local close = X.PanelWidget("Button", nil, frame, "UIPanelCloseButton")
  closeButton = close
  close:SetSize(22, 22)
  close:SetPoint("TOPRIGHT", 0, 0)
  close.hoverAnchor = "TOPRIGHT"
  close:SetFrameLevel((frame:GetFrameLevel() or 0) + 10)
  close:Hide()
  close:SetScript("OnClick", function()
    if X.PlayerSuspended() or InCombatLockdown() or (db.clickThrough and db.locked) then return end
    db.hidden = true; core.SetSessionShow(false)
    frame:Hide()
    Print(L["Hidden. Type /br to show it again."])
  end)
  frame:HookScript("OnEnter", X.UpdateFade)
  frame:HookScript("OnLeave", X.UpdateFade)
  frame:HookScript("OnShow", X.UpdateFade)
  frame:HookScript("OnHide", function()
    if not InCombatLockdown() then
      close:Hide()
      if db.hidden then
        wipe(rowMouseButtons)
        rowLeftPress = nil
        ClearRowViewport()
      end
    end
  end)
  close:HookScript("OnLeave", X.UpdateFade)
end

local function BuildStatusLabels()
  countText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

  combatText = frame:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
  combatText:SetPoint("LEFT", title, "RIGHT", 6, 0)
  combatText:SetText(L["combat"])
  combatText:Hide()

  emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  emptyText:SetPoint("TOPLEFT", 10, -HEADER_H - 3)
  emptyText:SetText(L["No targets in the buff queue."])

  overflowText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  overflowText:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -HEADER_H)

  -- Coverage line (1.4.0): "12/15 fully buffed · Fortitude 13/15 · ...",
  -- directly above the footer; Refresh() grows the window when it's shown.
  coverText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  coverText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 9, FOOTER_H + 3)
  coverText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, FOOTER_H + 3)
  coverText:SetJustifyH("LEFT")
  if coverText.SetWordWrap then coverText:SetWordWrap(false) end
  coverText:Hide()

  -- Focus watch line (1.8.0): one line about your focus target's buffs,
  -- directly above the coverage line. Refresh fills and shows it.
  focusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  focusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 9, FOOTER_H + 17)
  focusText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, FOOTER_H + 17)
  focusText:SetJustifyH("LEFT")
  if focusText.SetWordWrap then focusText:SetWordWrap(false) end
  focusText:Hide()
end

local function BuildFooter()
  gear = CreateFrame("Button", nil, frame)
  gear:SetSize(14, 14)
  gear:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 6)
  gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
  gear:SetHighlightTexture("Interface\\Buttons\\UI-OptionsButton", "ADD")
  gear:RegisterForClicks("LeftButtonUp","RightButtonUp")
  gear:SetScript("OnClick", function(_,button)
    if button=="LeftButton" and IsShiftKeyDown and IsShiftKeyDown() and X.OpenActions then X.OpenActions()
    elseif button=="RightButton" and X.Daily then X.Daily.Open()
    elseif X.OpenConfig then X.OpenConfig() end
  end)
  gear:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["BuffRadar settings"])
    GameTooltip:AddLine(L["Right-click: Daily Tasks"])
    GameTooltip:AddLine(L["Shift-left-click: Actions"])
    GameTooltip:Show()
  end)
  gear:SetScript("OnLeave", function() GameTooltip:Hide() end)

  if CLASSIC_FEATURES then
    local help = CreateFrame("Button", nil, frame)
    nearbyButton = help
    help:SetSize(14, 14)
    help:SetPoint("LEFT", gear, "RIGHT", 4, 0)
    help:SetNormalFontObject("GameFontNormal")
    help:SetHighlightFontObject("GameFontHighlight")
    help:SetText("?")
    help:SetShown(not (db.clickThrough and db.locked))
    help:SetScript("OnClick", function()
      if X.OpenNearbyDiagnostics then X.OpenNearbyDiagnostics() end
    end)
    help:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(L["Why Is Someone Missing?"])
      GameTooltip:Show()
    end)
    help:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end

  footerText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footerText:SetPoint("LEFT", nearbyButton or gear, "RIGHT", 5, 0)
  footerText:SetPoint("RIGHT", frame, "BOTTOMRIGHT", -16, 13)  -- clear of the resize grip
  footerText:SetJustifyH("LEFT")
  if footerText.SetWordWrap then footerText:SetWordWrap(false) end
  if CLASSIC_FEATURES then
    local preview = CreateFrame("Frame", nil, frame)
    preview:SetPoint("TOPLEFT", footerText, "TOPLEFT", 0, 0)
    preview:SetPoint("BOTTOMRIGHT", footerText, "BOTTOMRIGHT", 0, 0)
    preview:EnableMouse(true)
    preview:SetScript("OnEnter", ShowNextPreview)
    preview:SetScript("OnLeave", function() GameTooltip:Hide() end)
    nextPreview = preview
  end
end

local function BuildPill()
  -- All-buffed pill (1.6.0): with /br pill on, the full window collapses to
  -- this small button while the group is fully buffed. It sits where the
  -- window's top-left corner is; clicking it peeks at the full window.
  pill = X.PanelWidget("Button", "BuffRadarPill", UIParent,
                           BackdropTemplateMixin and "BackdropTemplate" or nil)
  if X.PlayerSuspended() then pill:Hide() end
  pill:SetSize(150, 22)
  pill:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  if pill.SetBackdrop then
    pill:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    pill:SetBackdropColor(0.04, 0.05, 0.09, 0.92)
    pill:SetBackdropBorderColor(0.35, 0.55, 0.8, 1)
  end
  pill.text = pill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  pill.text:SetPoint("CENTER", 0, 0)
  pill.text:SetText(L["All buffed"])
  pill:SetScript("OnClick", function(self)
    pillPeek = GetTime() + 5
    self:Hide()
    if frame then frame:Show() end
  end)
  pill:Hide()
end

local function BuildToggleBar()
  -- Toggle strip + role filter bar (1.5.0), directly under the title:
  -- your buff icons on the left (click one to toggle that buff), the role
  -- filter chips on the right. ApplyRowLayout shows/hides the bar and
  -- moves the rows below it.
  bar = CreateFrame("Frame", nil, frame)
  bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -HEADER_H)
  bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -HEADER_H)
  bar:SetHeight(18)
  stripButtons = {}
  for i = 1, 10 do
    local b = CreateFrame("Button", "BuffRadarStrip" .. i, bar)
    b:SetSize(16, 16)
    b:SetPoint("LEFT", bar, "LEFT", (i - 1) * 17, 0)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints(b)
    b:SetScript("OnClick", function(self)
      if InCombatLockdown() or not self.buffKey then return end
      db.enabled[self.buffKey] = not IsOn(self.buffKey, self.buffDefault)
      stripState = nil
      if QueueRefresh then QueueRefresh() end
    end)
    b:SetScript("OnEnter", function(self)
      if not self.buffKey then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(self.buffName   or   self.buffKey)
      GameTooltip:AddLine(IsOn(self.buffKey, self.buffDefault)   and   L["On -- click to turn off"]
          or   L["Off -- click to turn on"], 0.7, 0.7, 0.7)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    stripButtons[i] = b
  end
  chipButtons = {}
  local chipDefs = {
    { "ALL", "All", 26, -98 }, { "TANK", "Tank", 32, -64 },
    { "HEALER", "Heal", 32, -30 }, { "DAMAGER", "DPS", 28, 0 },
  }
  for _, cd in ipairs(chipDefs) do
    local b = CreateFrame("Button", "BuffRadarChip" .. cd[1], bar)
    b:SetSize(cd[3], 16)
    b:SetPoint("RIGHT", bar, "RIGHT", cd[4], 0)
    b.roleKey = cd[1]
    b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.fs:SetAllPoints(b)
    b.fs:SetJustifyH("CENTER")
    b.fs:SetText(L[cd[2]])
    b.fs:SetWordWrap(false)
    b.fs:SetWidth(cd[3])
    b:SetScript("OnClick", function(self)
      if not X.SetPreference("roleFilter",self.roleKey,"ui") then return end
      X.RefreshChips()
      if QueueRefresh then QueueRefresh() end
    end)
    chipButtons[#chipButtons + 1] = b
  end
  X.RefreshChips()
end

local function BuildResizeControls()
  -- Scale grips (1.11.0): drag either bottom corner to rescale the whole
  -- window (frame, rows, icons and text) together. The opposite bottom
  -- corner stays put on screen; the top edge (or bottom edge when the list
  -- grows up) stays put vertically. Width is set with /br width.
  local function MakeScaleGrip(side)
    local g = CreateFrame("Button", nil, frame)
    g:SetSize(12, 12)
    g.side = side
    local right = side == "RIGHT"
    g:SetPoint(right and "BOTTOMRIGHT" or "BOTTOMLEFT", frame, right and "BOTTOMRIGHT" or "BOTTOMLEFT",
               right and -3 or 3, 3)
    g:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    g:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    g:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight", "ADD")
    if not right then  -- mirror the right-corner art for the left corner
      local texs = { g:GetNormalTexture(), g:GetPushedTexture(), g:GetHighlightTexture() }
      for i = 1, 3 do
        if texs[i] and texs[i].SetTexCoord then texs[i]:SetTexCoord(1, 0, 0, 1) end
      end
    end
    g:SetScript("OnMouseDown", function(self, button)
      if button ~= "LeftButton" or db.locked or InCombatLockdown() then return end
      BeginScaleDrag(self)
    end)
    g:SetScript("OnMouseUp", function(self) EndScaleDrag(self) end)
    g:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, right and "ANCHOR_RIGHT" or "ANCHOR_LEFT")
      GameTooltip:AddLine(L["Drag to resize the window"])
      GameTooltip:AddLine(string.format("%d%%%s", math_floor((db.scale or 1) * 100 + 0.5),
        db.scalePerSpec and (X.spec and string.format(L["  (scale saved for %s)"],X.spec) or L["  (per-spec scale on)"]) or ""),
        0.8, 0.8, 0.8)
      if db.gripSnap ~= false then GameTooltip:AddLine(L["Hold Shift to snap to 75 / 100 / 125 / 150%"], 0.6, 0.6, 0.6) end
      GameTooltip:Show()
    end)
    g:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return g
  end
  grip = MakeScaleGrip("RIGHT")
  leftGrip = MakeScaleGrip("LEFT")

  -- Width handle (1.12.0): drag the right edge to change the list width,
  -- the job the old corner grip did. Kept clear of the corner grip.
  local edge = CreateFrame("Button", nil, frame)
  edge:SetWidth(5)
  edge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -HEADER_H)
  edge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 18)
  edge:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" or db.locked or InCombatLockdown() then return end
    frame:StartSizing("RIGHT")
    self.isSizing = true
  end)
  edge:SetScript("OnMouseUp", function(self) EndEdgeDrag(self) end)
  edge:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:AddLine(L["Drag to change the width"])
    GameTooltip:Show()
  end)
  edge:SetScript("OnLeave", function() GameTooltip:Hide() end)
  widthHandle = edge
end

local function BuildFinder()
  -- Name finder (1.8.0): a slim bar under the toggle strip holding one
  -- edit box; while it has text, the list shows only matching names.
  -- ApplyRowLayout positions and shows/hides it.
  findBar = CreateFrame("Frame", nil, frame)
  findBar:SetHeight(16)
  local findLabel = findBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  findLabel:SetPoint("LEFT", 2, 0)
  findLabel:SetText(L["Find:"])
  findEdit = X.PanelWidget("EditBox", nil, findBar, "InputBoxTemplate")
  findEdit:SetSize(130, 16)
  findEdit:SetPoint("LEFT", findLabel, "RIGHT", 6, 0)
  findEdit:SetAutoFocus(false)
  findEdit:SetMaxLetters(24)
  findEdit:SetScript("OnTextChanged", function(self)
    X.search = (self:GetText() or ""):lower()
    if QueueRefresh then QueueRefresh() end
  end)
  findEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  findEdit:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
  end)
  findBar:Hide()
end

local function BuildCastControls()
  -- Hide securely during death or combat. Refresh owns the visible state.
  if RegisterStateDriver then
    local ok, accepted = pcall(RegisterStateDriver, frame, "visibility", "[@player,dead][combat] hide")
    frame.visibilityDriver = ok and accepted ~= false
    ok, accepted = pcall(RegisterStateDriver, pill, "visibility", "[@player,dead][combat] hide")
    pill.visibilityDriver = ok and accepted ~= false
  end

  -- Plain button: the action-bar macro uses this only to observe the press.
  local macroNote = CreateFrame("Button", "BuffRadarMacroButton", UIParent)
  macroNote:SetSize(1, 1)
  macroNote:SetPoint("BOTTOMLEFT")
  macroNote:SetAlpha(0)
  macroNote:EnableMouse(false)
  macroNote:RegisterForClicks("LeftButtonUp")
  macroNote:SetScript("OnClick", X.RecordBarMacroClick)
  local okNext, errNext = pcall(BuildNextButton)
  pcall(BuildGroupButton)
  if not okNext then Print(string.format(L["|cffff4040keybind button unavailable:|r %s"], tostring(errNext))) end
end

local function BuildUI()
  if built or InCombatLockdown() then return end
  BuildWindowFrame()
  BuildCloseControl()
  BuildStatusLabels()
  BuildFooter()
  BuildPill()
  BuildToggleBar()
  BuildResizeControls()
  BuildFinder()
  for i = 1, MAX_ROWS do CreateRow(i) end
  BuildCastControls()

  ApplyGeometry()
  RestorePosition()
  ApplyAppearance()
  X.ApplyRowLayout()
  UpdateCounter()
  X.BuildMinimapButton()
  built = true
end

function X.BeginWindowCombat()
  wipe(rowMouseButtons)
  if X.ReadUnitBool(_G.IsMouseButtonDown, "LeftButton") == false then rowLeftPress = nil end
  if combatText then combatText:Show() end
  -- Drivers clear cast attributes in combat; protected drag and visibility
  -- work can run here only if the client has not started lockdown.
  if not InCombatLockdown() then
    EndWindowDrags()
    if frame and not frame.visibilityDriver then frame:Hide() end
    if pill and not pill.visibilityDriver then pill:Hide() end
  end
end

function X.EndWindowCombat()
  EndWindowDrags()
  if combatText then combatText:Hide() end
  BuildUI()
  if X.PlayerSuspended() then return false end
  -- Secure snippets cleared the attributes behind the display cache.
  for i = 1, #rows do rows[i].bGuid = nil end
  if nextBtn then nextBtn.bGuid, nextBtn.isClear = nil, false end
  if groupBtn then groupBtn.bGuid, groupBtn.isClear = nil, false end
  ApplyGeometry()  -- a scale/width change made during combat lands now
  if appearancePending or flashPending then ApplyAppearance() end
  X.ApplyRowLayout()
  X.ApplyClickThrough()
  ApplyNextRegistration()
  return true
end

function X.PrepareWindowScan()
  -- The next scan reuses entry tables. Do not scroll the previous view while it runs.
  viewport = nil
  if flashPending then ApplyAppearance() end
end

function X.RefreshWindowHeader()
  UpdateTitleMarks()
  RefreshStrip()
  X.RefreshChips()
end

function X.SetFinderText(text)
  X.search = text:lower()
  if findEdit then findEdit:SetText(text) end
end

function X.HasHeldRow()
  return (viewportCount or 0) > visibleLimit and RowMouseHeld()
end

function X.QueueVisibility(entries, index)
  for _, row in ipairs(rows) do
    if row.entry == entries[index] then return "visible" end
  end
  if db.viewMode == "people" and viewport == entries
      and (index <= (rowOffset or 0) or index > (rowOffset or 0) + visibleLimit) then
    return "overflow"
  end
end

function X.ApplyRowClickRegistration()
  if InCombatLockdown() then return end
  for _, row in ipairs(rows) do RegisterRowClicks(row) end
end

function X.InvalidatePortrait(unit)
  for _, row in ipairs(rows) do
    if row.cUnit == unit then row.cGuid = nil end
  end
end

local function ToggleWindow()
  if not db or X.PlayerSuspended() then return end
  db.hidden = not db.hidden
  core.SetSessionShow(not db.hidden)
  if InCombatLockdown() then
    Print(db.hidden   and   L["Window will hide when combat ends."]   or   L["Window will show when combat ends."])
    return
  end
  if not db.hidden and db.groupOnly and not X.InGroup() then
    Print(L["Window is set to show only in a party or raid."])
  end
  X.Refresh()
end

X.ToggleWindow = ToggleWindow
BuffRadar_ToggleWindow = ToggleWindow  -- Bindings.xml

-- Private entry points used by the core and other UI modules.
X.BuildUI = BuildUI
X.WindowReady = function() return built end
X.GetFrame = function() return frame end
X.GetNextButton = function() return nextBtn end
X.NextBindState = function() return nextWrapped, nextCombatDriver end
X.ApplyNextRegistration = ApplyNextRegistration
X.InvalidateRows = InvalidateRows
X.ApplyGeometry = ApplyGeometry
X.ApplyAppearance = ApplyAppearance
X.UpdateCounter = UpdateCounter
X.PositionSave = SavePosition
