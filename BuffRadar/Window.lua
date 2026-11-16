-- BuffRadar - Window: the main window's builder (BuildUI), the toggle
-- strip, filter chips and idle fade (1.5.0), the Cast Next / group cast
-- buttons and their secure bindings, and the scale / edge drag helpers.
-- Loaded after BuffRadar.lua through the .toc. This is file-split Slice G
-- (1.15.34): the code below moved verbatim from BuffRadar.lua and reaches
-- that file's locals through X.winAPI, which BuffRadar.lua fills in
-- before this file loads. BuildUI creates the window handles here and
-- hands them back with PublishUI() before any main-file code reads them;
-- the settings table arrives through X.dbSinks.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, NS = ...
local X = NS and NS.X
if not X or not X.winAPI then return end
local A = X.winAPI

local db = X.GetDB and X.GetDB()  -- nil until ADDON_LOADED; X.dbSinks updates it
X.dbSinks = X.dbSinks or {}
X.dbSinks[#X.dbSinks + 1] = function(value) db = value end

local L, Print, IsOn, QueueRefresh = A.L, A.Print, A.IsOn, A.QueueRefresh
local OpenConfig, RefreshConfig = A.OpenConfig, A.RefreshConfig
local ApplyAppearance, ApplyGeometry = A.ApplyAppearance, A.ApplyGeometry
local RestorePosition, SavePosition, UpdateCounter = A.RestorePosition, A.SavePosition, A.UpdateCounter
local Bind, CreateRow, BuildMinimapButton = A.Bind, A.CreateRow, A.BuildMinimapButton
local SafeString, SpellIcon = A.SafeString, A.SpellIcon
local myBuffs, myBlessing = A.myBuffs, A.myBlessing
local CLASSIC_FEATURES, MAX_ROWS, WIDTH = A.CLASSIC_FEATURES, A.MAX_ROWS, A.WIDTH
local HEADER_H, FOOTER_H, MIN_WIDTH, MAX_WIDTH = A.HEADER_H, A.FOOTER_H, A.MIN_WIDTH, A.MAX_WIDTH
local pairs, ipairs, pcall = pairs, ipairs, pcall
local math_floor = math.floor
local string_format = string.format
local wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
local GetTime, InCombatLockdown = GetTime, InCombatLockdown
local UnitName, UnitLevel = UnitName, UnitLevel

-- Window handles BuildUI creates. BuffRadar.lua keeps its own copies for
-- the scan and refresh; PublishUI() hands these over as soon as they exist.
local frame, title, countText, emptyText, overflowText, combatText, nextBtn, coverText
local footerText, grip
local built = false
local function PublishUI()
  A.setUI(frame, title, countText, emptyText, overflowText, combatText,
          nextBtn, coverText, footerText, grip, built)
end

---------------------------------------------------------------------------
-- Toggle strip, filter chips and idle fade (1.5.0). The bar under the
-- title carries one icon button per buff you can cast (click toggles it,
-- like the Buffs tab) and the role filter chips on the right.
---------------------------------------------------------------------------
function X.BarHeight()
  return (db and db.showStrip and A.hasAnyBuff()) and 18 or 0
end

function X.RefreshStrip()
  if not X.stripBtns or not db then return end
  local parts = {}
  for _, b in ipairs(myBuffs) do parts[#parts + 1] = b.key .. (IsOn(b.key, b.default) and "1" or "0") end
  if next(myBlessing) then parts[#parts + 1] = "BLESSINGS" .. (IsOn("BLESSINGS", true) and "1" or "0") end
  local sig = table.concat(parts, ",") .. "|" .. A.bookCount()
  if sig == X.stripSig then return end
  X.stripSig = sig
  local i = 0
  local function place(key, name, default)
    i = i + 1
    local b = X.stripBtns[i]
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
  for j = i + 1, #X.stripBtns do X.stripBtns[j]:Hide() end
end

function X.RefreshChips()
  if not X.chipBtns or not db then return end
  for _, b in ipairs(X.chipBtns) do
    if b.roleKey == db.roleFilter then b.fs:SetTextColor(1, 0.85, 0.3)
    else b.fs:SetTextColor(0.55, 0.55, 0.55) end
  end
end

-- Idle fade: while the mouse is elsewhere the whole window goes partly
-- see-through; moving the mouse over it brings it back. Polled from the
-- refresh ticker (no per-frame work).
function X.UpdateFade()
  if not frame or not db then return end
  local close = X.closeButton
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
     and not (X.gripL and X.gripL.isSizing) and not (X.edge and X.edge.isSizing) then
    if not over then target = 1 - db.idleFade / 100 end
  end
  if X.curAlpha ~= target then
    X.curAlpha = target
    frame:SetAlpha(target)
  end
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
  if X.groupBtn then
    if GetCVarBool and GetCVarBool("ActionButtonUseKeyDown") then
      X.groupBtn:RegisterForClicks("LeftButtonDown")
    else
      X.groupBtn:RegisterForClicks("LeftButtonUp")
    end
  end
end

local nextWrapped, nextCombatDriver = false, false

local function ClearNext()
  if not nextBtn or InCombatLockdown() then return end
  nextBtn.entry = nil
  if nextBtn.isClear then return end  -- already disarmed: skip four protected writes
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
  if not X.groupBtn or InCombatLockdown() then return end
  X.groupBtn.entry = nil
  if X.groupBtn.isClear then return end  -- already disarmed: skip the protected writes
  X.groupBtn:SetAttribute("type", nil)
  X.groupBtn:SetAttribute("spell", nil)
  X.groupBtn:SetAttribute("unit", nil)
  X.groupBtn:SetAttribute("macrotext", nil)
  X.groupBtn.isClear = true
  X.groupBtn.bGuid = nil
end
X.ClearGroup = ClearGroup

function X.DisarmStaleKeybind(button, mouseButton, clear)
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
-- Mirrors Bind's cast-method branches for the single spell it writes;
-- Bind itself is untouched (rows and the next-buff button keep their
-- proven path).
local function BindGroup(btn, unit, gspell, isSelf, pick)
  local method = db.castMethod
  if method == "target" then
    btn:SetAttribute("type", nil)
    btn:SetAttribute("unit", nil)
    btn:SetAttribute("spell", nil)
    btn:SetAttribute("macrotext", nil)
    if isSelf then
      btn:SetAttribute("type", "spell")
      btn:SetAttribute("spell", (pick and pick.id) or gspell)
      btn:SetAttribute("unit", "player")
      return
    end
    if unit:match("^party%d+$") or unit:match("^raid%d+$") then
      btn:SetAttribute("type", "spell")
      btn:SetAttribute("spell", (pick and pick.id) or gspell)
      btn:SetAttribute("unit", unit)
      return
    end
    local ok, name = pcall(GetUnitName or UnitName, unit, true)
    name = ok and SafeString(name) or nil  -- a protected name can't build a macro: no cast
    if name and name ~= "" then
      btn:SetAttribute("type", "macro")
      btn:SetAttribute("macrotext", "/targetexact " .. name .. "\n/cast " .. X.CastText(gspell, pick) .. "\n/targetlasttarget")
    end
  elseif method == "id" and pick and pick.id then
    btn:SetAttribute("type", "spell")
    btn:SetAttribute("unit", unit)
    btn:SetAttribute("spell", pick.id)
    btn:SetAttribute("macrotext", nil)
  else
    local text = (method == "rank") and X.CastText(gspell, pick) or gspell
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("unit", nil)
    btn:SetAttribute("spell", nil)
    btn:SetAttribute("macrotext", "/cast [@" .. unit .. ",help,nodead] " .. text)
  end
end

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
  btn.bOfferReason = X.GroupOfferReason(item, count, reason, blocker)
  btn.bOfferSummary = blocker and X.GroupOfferReason(item, count, reason, blocker, true) or btn.bOfferReason
  if btn.bGuid == guid and btn.bUnit == unit and btn.bSpell == gspell
     and btn.bMethod == method and btn.bLevel == lvl and btn.bSelf == isSelf and btn.bRankID == id then
    return btn:GetAttribute("type") ~= nil
  end
  BindGroup(btn, unit, gspell, isSelf, pick)
  btn.bGuid, btn.bUnit, btn.bSpell, btn.bMethod, btn.bLevel = guid, unit, gspell, method, lvl
  btn.bSelf = isSelf
  btn.bRankID, btn.bActionID, btn.bSpellText = id, id, X.CastText(gspell, pick)
  if method == "macro" then btn.bActionID, btn.bSpellText = nil, gspell end
  btn.isClear = false
  return btn:GetAttribute("type") ~= nil
end

function X.ClearRowCast(btn)
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
    if btn.bGuid ~= nil then X.ClearRowCast(btn) end
    return false
  end
  local method = db.castMethod
  local lvl = X.ReadUnitNumber(UnitLevel, unit) or 0
  local pick = X.BindingRank(spell, unit, lvl, method)
  if pick == false then X.ClearRowCast(btn); return false end
  local gspell, item, count, reason, blocker
  if db.modClick then
    local _
    gspell, item, count, reason, _, blocker = X.GroupOffer(spell, unit)
  end
  if reason then gspell = spell end -- explicit Shift fallback mirrors the primary binding
  local gpick = gspell and X.BindingRank(gspell, unit, lvl, method)
  local id, gid = pick and pick.id, gpick and gpick.id
  btn.bOfferReason = X.GroupOfferReason(item, count, reason, blocker)
  if btn.bGuid == guid and btn.bUnit == unit and btn.bSpell == spell
     and btn.bMethod == method and btn.bLevel == lvl and btn.bSelf == isSelf
     and btn.bRankID == id and btn.bGroupSpell == gspell and btn.bGroupRankID == gid then
    return btn:GetAttribute("type") ~= nil
  end
  Bind(btn, unit, spell, isSelf, pick, gspell, gpick)
  btn.bGuid, btn.bUnit, btn.bSpell, btn.bMethod, btn.bLevel = guid, unit, spell, method, lvl
  btn.bSelf = isSelf
  btn.bRankID, btn.bGroupRankID, btn.bGroupSpell = id, gid, gspell
  btn.bActionID, btn.bGroupID, btn.bSpellText = id, gid, X.CastText(spell, pick)
  btn.bGroupText = gspell and X.CastText(gspell, gpick)
  if method == "macro" then
    btn.bActionID, btn.bGroupID, btn.bSpellText, btn.bGroupText = nil, nil, spell, gspell
  end
  btn.isClear = false
  return btn:GetAttribute("type") ~= nil
end

-- Arm the group button with the head row (called from Refresh, which is
-- at its upvalue ceiling and reaches the button only through X).
function X.ArmGroupBtn(first)
  if not X.groupBtn then return end
  X.groupBtn.entry = BindGroupCached(X.groupBtn, first.unit, first.missing[1], first.guid) and first or nil
end

function X.NoCastReason(entry)
  local group = X.groupBtn
  if not entry then return X.groupFallback or (group and group.entry and group.bOfferReason) end
  if group and group.entry == entry and group.bOfferReason then
    return group.bOfferSummary
  end
  if X.groupFallbackEntry == entry then return X.groupFallbackSummary end
end

function X.ShowNextPreview(owner)
  if InCombatLockdown() or X.PlayerSuspended() or (db.locked and db.clickThrough) then return end
  local entry = nextBtn and nextBtn.entry
  if not entry or not nextBtn:GetAttribute("type") then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:AddLine(string_format(L["Next buff: %s — %s"], entry.fullName or entry.name,
    nextBtn.bSpellText or entry.missing[1]), 1, 1, 1, true)
  local group = X.groupBtn
  if group and group.entry == entry and group.bSpellText then
    GameTooltip:AddLine(string_format(L["Group buff key: %s"], group.bSpellText), 0.8, 0.9, 1, true)
  end
  local reason = X.NoCastReason(entry)
  if reason then GameTooltip:AddLine(reason, 1, 0.7, 0.3, true) end
  GameTooltip:Show()
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
  nextCombatDriver = X.InstallCombatDriver(nextBtn, [[
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
    X.DisarmStaleKeybind(self, button, ClearNext)
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
  X.groupBtn = btn
  btn:SetSize(1, 1)
  btn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
  btn:SetAlpha(0)
  btn:EnableMouse(false)
  btn:Show()
  ApplyNextRegistration()
  X.groupCombatDriver = X.InstallCombatDriver(btn, [[
    if newstate == "combat" then
      self:SetAttribute("type", nil)
      self:SetAttribute("spell", nil)
      self:SetAttribute("unit", nil)
      self:SetAttribute("macrotext", nil)
    end
  ]])
  btn.combatDriver = X.groupCombatDriver
  if SecureHandlerWrapScript then
    X.groupWrapped = pcall(SecureHandlerWrapScript, btn, "OnClick", btn, [[ return nil, true ]], [[
      self:SetAttribute("type", nil)
      self:SetAttribute("spell", nil)
      self:SetAttribute("unit", nil)
      self:SetAttribute("macrotext", nil)
    ]])
  end
  btn:HookScript("PreClick", function(self, button, down)
    X.DisarmStaleKeybind(self, button, ClearGroup)
    X.BeginCastClick(self, button, down, "group-buff key")
  end)
  btn:HookScript("PostClick", function(self, button, down)
    X.EndCastClick(self, button, down, "group-buff key")
    self.bGuid, self.isClear = nil, false  -- attributes changed outside our cache
    if not X.groupWrapped then ClearGroup() end  -- one press = one cast
  end)
end

-- Scale drag (1.11.0). Cursor-driven; the OnUpdate runs only while a grip is
-- held. Scale = the cursor's horizontal distance from the fixed bottom
-- corner divided by the window's unscaled width.
X.SNAPS = { 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2 }

function X.ScaleFromCursor(g)
  local cx = GetCursorPosition() / UIParent:GetEffectiveScale()
  local w = g.baseW
  if not w or w <= 0 then return db.scale or 1 end
  local ns = (g.side == "RIGHT") and (cx - g.fixedX) / w or (g.fixedX - cx) / w
  if db.gripSnap ~= false and IsShiftKeyDown and IsShiftKeyDown() then
    local best, bd = ns, 0.06  -- Shift: snap to a preset within 6%
    for _, p in ipairs(X.SNAPS) do
      local d = math.abs(ns - p)
      if d < bd then best, bd = p, d end
    end
    ns = best
  end
  if ns < 0.5 then ns = 0.5 elseif ns > 2 then ns = 2 end  -- same bounds as RANGES.scale
  return ns
end

function X.PlaceScaled(g, ns)
  local left = (g.side == "RIGHT") and g.fixedX or (g.fixedX - g.baseW * ns)
  frame:SetScale(ns)
  frame:ClearAllPoints()
  if db.growUp then
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left / ns, g.fixedY / ns)
  else
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / ns, g.fixedY / ns)
  end
end

function X.EndEdgeDrag(e)
  if not e or not e.isSizing or InCombatLockdown() then return end
  e.isSizing = false
  frame:StopMovingOrSizing()
  local cols = X.cols or 1
  local w = (frame:GetWidth() - (cols - 1) * 6) / cols
  db.width = math.max(MIN_WIDTH, math.min(MAX_WIDTH, math_floor(w + 0.5)))
  ApplyGeometry()
  SavePosition()
end

function X.BeginScaleDrag(g)
  local s = frame:GetScale() or 1
  local l, r = frame:GetLeft(), frame:GetRight()
  local y = db.growUp and frame:GetBottom() or frame:GetTop()
  if not (l and r and y) then return end
  g.baseW = frame:GetWidth()
  g.fixedX = (g.side == "RIGHT") and l * s or r * s
  g.fixedY = y * s
  g.isSizing = true
  g:SetScript("OnUpdate", function(self)
    if InCombatLockdown() then X.EndScaleDrag(self); return end
    local ns = X.ScaleFromCursor(self)
    db.scale = ns
    X.PlaceScaled(self, ns)
  end)
end

function X.EndScaleDrag(g)
  if not g or not g.isSizing then return end
  g:SetScript("OnUpdate", nil)
  if InCombatLockdown() then return end
  g.isSizing = false
  local ns = math_floor((db.scale or 1) * 100 + 0.5) / 100
  db.scale = ns
  X.PlaceScaled(g, ns)
  SavePosition()
  if RefreshConfig then RefreshConfig() end
end

function X.EndWindowDrags()
  if InCombatLockdown() then return end
  if frame and frame.isMoving then
    frame:StopMovingOrSizing()
    frame.isMoving = false
    SavePosition()
  end
  X.EndScaleDrag(grip)
  X.EndScaleDrag(X.gripL)
  X.EndEdgeDrag(X.edge)
end

local function BuildUI()
  if built or InCombatLockdown() then return end

  frame = CreateFrame("Frame", "BuffRadarFrame", UIParent,
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
  frame:SetScript("OnMouseWheel", X.RowWheel)
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

  title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 9, -7)
  title:SetText("|cff33ccffBuff|rRadar")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  X.closeButton = close
  close:SetSize(22, 22)
  close:SetPoint("TOPRIGHT", 0, 0)
  close.hoverAnchor = "TOPRIGHT"
  close:SetFrameLevel((frame:GetFrameLevel() or 0) + 10)
  close:Hide()
  close:SetScript("OnClick", function()
    if X.PlayerSuspended() or InCombatLockdown() or (db.clickThrough and db.locked) then return end
    db.hidden = true; A.setSessionShow(false)
    frame:Hide()
    Print("Hidden. Type /br to show it again.")
  end)
  frame:HookScript("OnEnter", X.UpdateFade)
  frame:HookScript("OnLeave", X.UpdateFade)
  frame:HookScript("OnShow", X.UpdateFade)
  frame:HookScript("OnHide", function()
    if not InCombatLockdown() then
      close:Hide()
      if db.hidden then
        wipe(X.rowMouseButtons)
        X.rowLeftPress = nil
        X.ClearRowViewport()
      end
    end
  end)
  close:HookScript("OnLeave", X.UpdateFade)

  local gear = CreateFrame("Button", nil, frame)
  X.gear = gear
  gear:SetSize(14, 14)
  gear:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 6)
  gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
  gear:SetHighlightTexture("Interface\\Buttons\\UI-OptionsButton", "ADD")
  gear:SetScript("OnClick", function() OpenConfig() end)
  gear:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["BuffRadar settings"])
    GameTooltip:Show()
  end)
  gear:SetScript("OnLeave", function() GameTooltip:Hide() end)

  if CLASSIC_FEATURES then
    local help = CreateFrame("Button", nil, frame)
    X.nearbyButton = help
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

  footerText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footerText:SetPoint("LEFT", X.nearbyButton or gear, "RIGHT", 5, 0)
  footerText:SetPoint("RIGHT", frame, "BOTTOMRIGHT", -16, 13)  -- clear of the resize grip
  footerText:SetJustifyH("LEFT")
  if footerText.SetWordWrap then footerText:SetWordWrap(false) end
  X.footerText = footerText
  if CLASSIC_FEATURES then
    local preview = CreateFrame("Frame", nil, frame)
    preview:SetPoint("TOPLEFT", footerText, "TOPLEFT", 0, 0)
    preview:SetPoint("BOTTOMRIGHT", footerText, "BOTTOMRIGHT", 0, 0)
    preview:EnableMouse(true)
    preview:SetScript("OnEnter", X.ShowNextPreview)
    preview:SetScript("OnLeave", function() GameTooltip:Hide() end)
    X.nextPreview = preview
  end

  -- Coverage line (1.4.0): "12/15 fully buffed · Fortitude 13/15 · ...",
  -- directly above the footer; Refresh() grows the window when it's shown.
  coverText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  coverText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 9, FOOTER_H + 3)
  coverText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, FOOTER_H + 3)
  coverText:SetJustifyH("LEFT")
  if coverText.SetWordWrap then coverText:SetWordWrap(false) end
  coverText:Hide()

  -- All-buffed pill (1.6.0): with /br pill on, the full window collapses to
  -- this small button while the group is fully buffed. It sits where the
  -- window's top-left corner is; clicking it peeks at the full window.
  local pill = CreateFrame("Button", "BuffRadarPill", UIParent,
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
    X.pillPeek = GetTime() + 5
    self:Hide()
    if frame then frame:Show() end
  end)
  pill:Hide()
  X.pill = pill

  -- Toggle strip + role filter bar (1.5.0), directly under the title:
  -- your buff icons on the left (click one to toggle that buff), the role
  -- filter chips on the right. ApplyRowLayout shows/hides the bar and
  -- moves the rows below it.
  local bar = CreateFrame("Frame", nil, frame)
  bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -HEADER_H)
  bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -HEADER_H)
  bar:SetHeight(18)
  X.bar = bar
  X.stripBtns = {}
  for i = 1, 10 do
    local b = CreateFrame("Button", "BuffRadarStrip" .. i, bar)
    b:SetSize(16, 16)
    b:SetPoint("LEFT", bar, "LEFT", (i - 1) * 17, 0)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints(b)
    b:SetScript("OnClick", function(self)
      if InCombatLockdown() or not self.buffKey then return end
      db.enabled[self.buffKey] = not IsOn(self.buffKey, self.buffDefault)
      X.stripSig = nil
      if QueueRefresh then QueueRefresh() end
    end)
    b:SetScript("OnEnter", function(self)
      if not self.buffKey then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(self.buffName or self.buffKey)
      GameTooltip:AddLine(IsOn(self.buffKey, self.buffDefault) and "On -- click to turn off"
        or "Off -- click to turn on", 0.7, 0.7, 0.7)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    X.stripBtns[i] = b
  end
  X.chipBtns = {}
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
    b.fs:SetText(cd[2])
    b:SetScript("OnClick", function(self)
      db.roleFilter = self.roleKey
      X.RefreshChips()
      if QueueRefresh then QueueRefresh() end
    end)
    X.chipBtns[#X.chipBtns + 1] = b
  end
  X.RefreshChips()

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
      X.BeginScaleDrag(self)
    end)
    g:SetScript("OnMouseUp", function(self) X.EndScaleDrag(self) end)
    g:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, right and "ANCHOR_RIGHT" or "ANCHOR_LEFT")
      GameTooltip:AddLine(L["Drag to resize the window"])
      GameTooltip:AddLine(string.format("%d%%%s", math_floor((db.scale or 1) * 100 + 0.5),
        db.scalePerSpec and (X.spec and ("  (scale saved for " .. X.spec .. ")") or "  (per-spec scale on)") or ""),
        0.8, 0.8, 0.8)
      if db.gripSnap ~= false then GameTooltip:AddLine("Hold Shift to snap to 75 / 100 / 125 / 150%", 0.6, 0.6, 0.6) end
      GameTooltip:Show()
    end)
    g:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return g
  end
  grip = MakeScaleGrip("RIGHT")
  X.gripL = MakeScaleGrip("LEFT")

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
  edge:SetScript("OnMouseUp", function(self) X.EndEdgeDrag(self) end)
  edge:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:AddLine("Drag to change the width")
    GameTooltip:Show()
  end)
  edge:SetScript("OnLeave", function() GameTooltip:Hide() end)
  X.edge = edge

  -- Name finder (1.8.0): a slim bar under the toggle strip holding one
  -- edit box; while it has text, the list shows only matching names.
  -- ApplyRowLayout positions and shows/hides it.
  local findBar = CreateFrame("Frame", nil, frame)
  findBar:SetHeight(16)
  local findLabel = findBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  findLabel:SetPoint("LEFT", 2, 0)
  findLabel:SetText("Find:")
  local findEdit = CreateFrame("EditBox", nil, findBar, "InputBoxTemplate")
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
  X.findBar, X.findEdit = findBar, findEdit

  -- Focus watch line (1.8.0): one line about your focus target's buffs,
  -- directly above the coverage line. Refresh fills and shows it.
  local focusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  focusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 9, FOOTER_H + 17)
  focusText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, FOOTER_H + 17)
  focusText:SetJustifyH("LEFT")
  if focusText.SetWordWrap then focusText:SetWordWrap(false) end
  focusText:Hide()
  X.focusText = focusText

  PublishUI()  -- CreateRow and the calls below read the main file's copies
  for i = 1, MAX_ROWS do CreateRow(i) end

  -- Hide securely during death or combat. Refresh owns the visible state.
  if RegisterStateDriver then
    local ok, accepted = pcall(RegisterStateDriver, frame, "visibility", "[@player,dead][combat] hide")
    frame.visibilityDriver = ok and accepted ~= false
    ok, accepted = pcall(RegisterStateDriver, pill, "visibility", "[@player,dead][combat] hide")
    pill.visibilityDriver = ok and accepted ~= false
  end

  local okNext, errNext = pcall(BuildNextButton)
  pcall(BuildGroupButton)
  PublishUI()  -- nextBtn now exists
  if not okNext then Print("|cffff4040keybind button unavailable:|r " .. tostring(errNext)) end

  ApplyGeometry()
  RestorePosition()
  ApplyAppearance()
  X.ApplyRowLayout()
  UpdateCounter()
  BuildMinimapButton()
  built = true
  PublishUI()
end

-- Entry points BuffRadar.lua and Slash.lua call.
X.BuildUI, X.ApplyNextRegistration, X.ClearNext, X.BindCached =
  BuildUI, ApplyNextRegistration, ClearNext, BindCached
X.NextBindState = function() return nextWrapped, nextCombatDriver end
