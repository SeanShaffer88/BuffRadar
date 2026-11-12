-- BuffRadar - Config: the settings window (widget builders, the five
-- tabs, BuildConfig, RefreshConfig, OpenConfig).
-- Loaded after BuffRadar.lua through the .toc. This is file-split
-- Slice B (1.15.0): the code below is the settings do-block that used to
-- sit at the bottom of BuffRadar.lua, moved verbatim; it reaches the
-- main file's locals through X.cfgAPI, which BuffRadar.lua fills in
-- before this file loads. Settings state (the cfg table and every
-- widget) is local to this file, exactly as it was local to the block.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, NS = ...
NS = NS or {}
local X = NS.X or {}
NS.X = X
local A = X.cfgAPI or {}

local db  -- the live settings table; read fresh at each entry point (X.GetDB)
local L = A.L
local Print, Refresh, PlayAlert = A.Print, A.Refresh, A.PlayAlert
local ApplyAppearance, ApplyGeometry = A.ApplyAppearance, A.ApplyGeometry
local BuildBuffList, InvalidateRows, UpdateCounter = A.BuildBuffList, A.InvalidateRows, A.UpdateCounter
local IsOn, Esc = A.IsOn, A.Esc
local KeybindText, OpenKeybinds, MakeMacro = A.KeybindText, A.OpenKeybinds, A.MakeMacro
local Missing = A.Missing
local RefreshMinimapButton = A.RefreshMinimapButton
local myBuffs, myBlessing = A.myBuffs, A.myBlessing
local Single, Ignore = A.Single, A.Ignore
local BLESSINGS, DEFAULTS, SCALE_PRESETS = A.BLESSINGS, A.DEFAULTS, A.SCALE_PRESETS
local CLASSIC_FEATURES = A.CLASSIC_FEATURES
local NEXT_BINDING = A.NEXT_BINDING
local pairs, ipairs, next, type, tonumber, tostring, pcall = pairs, ipairs, next, type, tonumber, tostring, pcall
local math_floor, math_min = math.floor, math.min
local table_sort = table.sort
local wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

local OpenConfig, RefreshConfig  -- assigned in the block below, published on X after it

do
local cfg

local function MakeCheck(parent, label, getter, setter)
  local cb = CreateFrame("CheckButton", nil, parent)
  cb:SetSize(24, 24)
  cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
  cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
  cb.label:SetText(label)
  cb.FitLabel = function(self)  -- the label is part of the click target, not just the box
    local w = self.label:GetStringWidth()
    if self.label.maxWidth then w = math_min(w, self.label.maxWidth) end
    self:SetHitRectInsets(0, -(w + 4), 0, 0)
  end
  cb:FitLabel()
  cb:SetScript("OnClick", function(self) setter(self:GetChecked() and true or false) end)
  cb.Update = function(self) self:SetChecked(getter() and true or false) end
  if label and label ~= "" then  -- settings search registry (1.8.0)
    X.cfgReg[#X.cfgReg + 1] = { w = cb,
      keys = (label:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")):lower() }
  end
  return cb
end

-- Settings search (1.8.0): dim every registered control that doesn't
-- match the query; returns how many match. Empty query restores all.
function X.CfgFilter(q)
  q = (q or ""):lower()
  local hits = 0
  for _, r in ipairs(X.cfgReg) do
    local on = q == "" or r.keys:find(q, 1, true) ~= nil
    if on then hits = hits + 1 end
    if r.w.SetAlpha then r.w:SetAlpha(on and 1 or 0.25) end
  end
  return hits
end

-- Hover help for a settings control: a white title line plus wrapped detail.
-- heading/text may be functions, for help that depends on the current state.
local function Tip(widget, heading, text)
  widget:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(type(heading) == "function" and heading() or heading, 1, 1, 1)
    local t = type(text) == "function" and text() or text
    if t then GameTooltip:AddLine(t, 0.85, 0.85, 0.85, true) end
    GameTooltip:Show()
  end)
  widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Seconds entry box (0-3600). Enter or clicking away saves, Esc cancels;
-- onCommit gets the number, or nil for an empty box. Shows getText() otherwise.
local function MakeSecondsBox(parent, getText, onCommit)
  local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  eb:SetSize(40, 20)
  eb:SetAutoFocus(false)
  eb:SetNumeric(true)
  eb:SetMaxLetters(4)
  eb:SetJustifyH("CENTER")
  eb.Revert = function(self) self:SetText(getText()) end
  eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnEscapePressed", function(self) self.cancel = true; self:ClearFocus() end)
  eb:SetScript("OnEditFocusLost", function(self)
    self:HighlightText(0, 0)
    if self.cancel then self.cancel = false; self:Revert(); return end
    local s = self:GetText()
    local n = tonumber(s)
    if s ~= "" and (not n or n > 3600) then
      Print("Rebuff time must be a whole number from 0 to 3600 seconds.")
    else
      onCommit(n)
    end
    self:Revert()
  end)
  return eb
end

local function MakeButton(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  if text and text ~= "" then  -- settings search registry (1.8.0)
    X.cfgReg[#X.cfgReg + 1] = { w = b, keys = text:lower() }
  end
  return b
end

local function MakeSlider(parent, x, y, width, minV, maxV, step, onChange)
  local slider = CreateFrame("Slider", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  slider:SetOrientation("HORIZONTAL")
  slider:SetSize(width, 17)
  slider:SetPoint("TOPLEFT", x, y)
  if slider.SetBackdrop then
    slider:SetBackdrop({
      bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
      edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
      tile = true, tileSize = 8, edgeSize = 8,
      insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
  end
  slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  slider:SetMinMaxValues(minV, maxV)
  slider:SetValueStep(step)
  if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
  slider:EnableMouse(true)
  slider:EnableMouseWheel(true)
  slider:SetScript("OnMouseWheel", function(self, delta)
    self:SetValue(math.max(minV, math.min(maxV, self:GetValue() + delta * step)))
  end)
  slider:SetScript("OnValueChanged", function(_, v) onChange(v) end)
  return slider
end

local function OpenColorPicker()
  local c = db.bgColor
  local prev = { c[1], c[2], c[3] }
  local function apply()
    local r, g, b = ColorPickerFrame:GetColorRGB()
    db.bgColor = { r, g, b }
    db.theme = "custom"  -- a hand-picked color leaves the theme presets (1.8.0)
    ApplyAppearance()
    RefreshConfig()
  end
  local function cancel()
    db.bgColor = { prev[1], prev[2], prev[3] }
    ApplyAppearance()
    RefreshConfig()
  end
  if ColorPickerFrame.SetupColorPickerAndShow then
    ColorPickerFrame:SetupColorPickerAndShow({
      swatchFunc = apply, cancelFunc = cancel, hasOpacity = false,
      r = c[1], g = c[2], b = c[3],
    })
  else
    ColorPickerFrame.func = apply
    ColorPickerFrame.cancelFunc = cancel
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.previousValues = { r = c[1], g = c[2], b = c[3] }
    ColorPickerFrame:SetColorRGB(c[1], c[2], c[3])
    ColorPickerFrame:Hide()
    ColorPickerFrame:Show()
  end
end

local function PercentText(v) return math_floor(v * 100 + 0.5) .. "%" end

-- Scale picker: the game's menu dropdown, with one entry per SCALE_PRESETS value.
-- A scale set by /br scale that isn't a preset shows as "Custom (n%)". Clients
-- without the dropdown template get a button that steps through the presets.
local function MakeScaleDropdown(parent, getter, setter)
  local ok, dd = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  if ok and dd and dd.SetupMenu then
    dd:SetWidth(120)
    dd:SetupMenu(function(_, root)
      for _, v in ipairs(SCALE_PRESETS) do
        root:CreateRadio(PercentText(v),
          function(x) return math.abs(getter() - x) < 0.001 end,
          function(x) setter(x) end, v)
      end
    end)
    dd.Update = function(self)
      if self.SetDefaultText then self:SetDefaultText("Custom (" .. PercentText(getter()) .. ")") end
      if self.GenerateMenu then self:GenerateMenu() end
    end
    return dd
  end
  local b = MakeButton(parent, "", 120, function(self)
    local cur, nextV = getter(), SCALE_PRESETS[1]
    for _, v in ipairs(SCALE_PRESETS) do
      if v > cur + 0.001 then nextV = v; break end
    end
    setter(nextV)
    self:Update()
  end)
  b.Update = function(self) self:SetText(PercentText(getter())) end
  return b
end

local function SelectTab(key)
  cfg.curTab = key
  if cfg.displayPanel then cfg.displayPanel:Hide() end
  for k, panel in pairs(cfg.panels) do panel:SetShown(k == key) end
  if cfg.nativeTabs then
    PanelTemplates_SetTab(cfg, cfg.tabBtns[key]:GetID())
  else
    for k, btn in pairs(cfg.tabBtns) do
      if k == key then btn:LockHighlight() else btn:UnlockHighlight() end
    end
  end
end

local function BuildConfig()
  db = X.GetDB()
  -- Blizzard's standard window (title bar, BuffRadar icon in the portrait
  -- corner, close button, inset content area) so it matches the retail UI.
  -- A client without that template gets the original hand-drawn window.
  cfg = CreateFrame("Frame", "BuffRadarConfig", UIParent, "ButtonFrameTemplate")
  local native = cfg.SetTitle and cfg.Inset and cfg.CloseButton and true or false
  if not native then
    cfg:Hide()
    cfg = CreateFrame("Frame", "BuffRadarConfig", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  end
  cfg:SetSize(600, 540)
  cfg:SetScale(db.cfgScale or 1)
  cfg:SetPoint("CENTER")
  cfg:SetFrameStrata("DIALOG")
  cfg:SetClampedToScreen(true)
  cfg:SetMovable(true)
  cfg:EnableMouse(true)
  cfg:RegisterForDrag("LeftButton")
  cfg:SetScript("OnDragStart", cfg.StartMoving)
  cfg:SetScript("OnDragStop", cfg.StopMovingOrSizing)
  if UISpecialFrames then table.insert(UISpecialFrames, "BuffRadarConfig") end -- Esc closes it

  if native then
    cfg:SetTitle("BuffRadar Settings")
    if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(cfg) end
    if cfg.SetPortraitToAsset then
      cfg:SetPortraitToAsset("Interface\\AddOns\\BuffRadar\\Media\\icon.png")
    elseif ButtonFrameTemplate_HidePortrait then
      ButtonFrameTemplate_HidePortrait(cfg)
    end
  else
    if cfg.SetBackdrop then
      cfg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
      })
      cfg:SetBackdropColor(0.05, 0.06, 0.1, 0.97)
      cfg:SetBackdropBorderColor(0.35, 0.55, 0.8, 1)
    end
    local head = cfg:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    head:SetPoint("TOP", 0, -12)
    head:SetText("|cff33ccffBuff|rRadar Settings")
    local close = CreateFrame("Button", nil, cfg, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
  end

  -- Tabs: Blizzard's bottom tabs on the standard window (named
  -- BuffRadarConfigTab1..5, as PanelTemplates expects), otherwise the
  -- original row of buttons along the top.
  cfg.panels, cfg.tabBtns = {}, {}
  cfg.nativeTabs = native and PanelTemplates_SetNumTabs and PanelTemplates_SetTab and true or false
  local tabDefs = {
    { "look", L["Window"] }, { "alerts", L["Alerts"] }, { "buffs", L["Buffs"] },
    { "behavior", L["Behavior"] }, { "data", L["Ignore & Stats"] },
  }
  local tabList, prevTab = {}, nil
  for i, td in ipairs(tabDefs) do
    local key, label = td[1], td[2]
    local function onClick() SelectTab(key); RefreshConfig() end
    local btn
    if cfg.nativeTabs then
      btn = CreateFrame("Button", "BuffRadarConfigTab" .. i, cfg, "PanelTabButtonTemplate")
      btn:SetID(i)
      btn:SetText(label)
      btn:SetScript("OnClick", onClick)
      if PanelTemplates_TabResize then PanelTemplates_TabResize(btn, 0) end
      if prevTab then
        btn:SetPoint("TOPLEFT", prevTab, "TOPRIGHT", 3, 0)
      else
        btn:SetPoint("TOPLEFT", cfg, "BOTTOMLEFT", 11, 2)
      end
      prevTab = btn
      tabList[i] = btn
    else
      btn = MakeButton(cfg, label, 106, onClick)
      btn:SetPoint("TOPLEFT", 16 + (i - 1) * 112, -40)
    end
    cfg.tabBtns[key] = btn
    local panel = CreateFrame("Frame", nil, cfg)
    if native then  -- inside the template's inset area, below the title bar
      panel:SetPoint("TOPLEFT", cfg.Inset, "TOPLEFT", 4, -4)
      panel:SetPoint("BOTTOMRIGHT", cfg.Inset, "BOTTOMRIGHT", -4, 4)
    else
      panel:SetPoint("TOPLEFT", 8, -70)
      panel:SetPoint("BOTTOMRIGHT", -8, 8)
    end
    panel:Hide()
    cfg.panels[key] = panel
  end
  if cfg.nativeTabs then
    cfg.Tabs = tabList  -- newer PanelTemplates look here; older ones use the names
    PanelTemplates_SetNumTabs(cfg, #tabList)
  end

  local function section(panel, text, x, y)
    local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
  end

  ------------------------------------------------------------------
  -- Tab: Window (look)
  ------------------------------------------------------------------
  local look = cfg.panels.look
  section(look, "Appearance", 10, -6)

  local colorLabel = look:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  colorLabel:SetPoint("TOPLEFT", 14, -34)
  colorLabel:SetText("Background color")
  local swatch = CreateFrame("Button", nil, look, BackdropTemplateMixin and "BackdropTemplate" or nil)
  swatch:SetSize(40, 18)
  swatch:SetPoint("LEFT", colorLabel, "RIGHT", 10, 0)
  if swatch.SetBackdrop then
    swatch:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                         edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    swatch:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
  end
  swatch:SetScript("OnClick", OpenColorPicker)
  cfg.swatch = swatch

  local alphaLabel = look:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  alphaLabel:SetPoint("TOPLEFT", 14, -64)
  alphaLabel:SetText("Background opacity")
  local alphaValue = look:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  alphaValue:SetPoint("LEFT", alphaLabel, "RIGHT", 8, 0)
  cfg.alphaValue = alphaValue
  cfg.slider = MakeSlider(look, 16, -84, 250, 0, 100, 5, function(v)
    v = math.floor(v + 0.5)
    db.bgAlpha = v / 100
    alphaValue:SetText(v .. "%")
    ApplyAppearance()
  end)

  cfg.titleCheck = MakeCheck(look, L["Show BuffRadar title"],
    function() return db.showTitle end,
    function(v) db.showTitle = v; ApplyAppearance() end)
  cfg.titleCheck:SetPoint("TOPLEFT", 10, -116)

  cfg.borderCheck = MakeCheck(look, L["Show border"],
    function() return db.showBorder end,
    function(v) db.showBorder = v; ApplyAppearance() end)
  cfg.borderCheck:SetPoint("TOPLEFT", 10, -142)

  cfg.compactCheck = MakeCheck(look, L["Compact rows (no portraits)"],
    function() return db.compact end,
    function(v) db.compact = v; X.ApplyRowLayout(); Refresh() end)
  cfg.compactCheck:SetPoint("TOPLEFT", 250, -124)

  cfg.charPointCheck = MakeCheck(look, L["Per-character window position"],
    function() return db.charPoint end,
    function(v)
      db.charPoint = v
      if v then
        local k = X.CharKey()
        if k and db.point then db.pointByChar[k] = db.point end
      end
    end)
  cfg.charPointCheck:SetPoint("TOPLEFT", 250, -150)

  cfg.stripCheck = MakeCheck(look, L["Buff toggle strip on the window"],
    function() return db.showStrip end,
    function(v) db.showStrip = v; X.ApplyRowLayout(); Refresh() end)
  cfg.stripCheck:SetPoint("TOPLEFT", 250, -186)

  local gapLabel = look:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  gapLabel:SetPoint("TOPLEFT", 274, -24)
  gapLabel:SetText("Row spacing")
  local gapValue = look:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gapValue:SetPoint("LEFT", gapLabel, "RIGHT", 8, 0)
  cfg.gapValue = gapValue
  cfg.gapSlider = MakeSlider(look, 276, -46, 200, 0, 8, 1, function(v)
    v = math.floor(v + 0.5)
    db.rowGap = v
    gapValue:SetText(tostring(v))
    X.ApplyRowLayout()
    Refresh()
  end)

  local iconLabel = look:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  iconLabel:SetPoint("TOPLEFT", 274, -82)
  iconLabel:SetText("Buff icon size")
  local iconValue = look:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  iconValue:SetPoint("LEFT", iconLabel, "RIGHT", 8, 0)
  cfg.iconValue = iconValue
  cfg.iconSlider = MakeSlider(look, 276, -104, 200, 0, 24, 1, function(v)
    v = math.floor(v + 0.5)
    db.iconSize = v
    iconValue:SetText(v == 0 and "auto" or tostring(v))
    X.ApplyRowLayout()
    InvalidateRows()
    Refresh()
  end)

  local fadeLabel = look:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fadeLabel:SetPoint("TOPLEFT", 304, -240)
  fadeLabel:SetText("Idle fade (mouse away)")
  local fadeValue = look:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fadeValue:SetPoint("LEFT", fadeLabel, "RIGHT", 8, 0)
  cfg.fadeValue = fadeValue
  cfg.fadeSlider = MakeSlider(look, 306, -260, 170, 0, 90, 5, function(v)
    v = math.floor(v + 0.5)
    db.idleFade = v
    fadeValue:SetText(v .. "%")
    X.curAlpha = nil
  end)

  local scaleLabel = look:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  scaleLabel:SetPoint("TOPLEFT", 14, -178)
  scaleLabel:SetText("Window scale")
  cfg.scaleDrop = MakeScaleDropdown(look,
    function() return db.scale or 1 end,
    function(v)
      if InCombatLockdown() then Print("Can't rescale the window during combat."); return end
      db.scale = v
      ApplyGeometry()
      RefreshConfig()
    end)
  cfg.scaleDrop:SetPoint("LEFT", scaleLabel, "RIGHT", 12, 0)
  local widthHint = look:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  widthHint:SetPoint("TOPLEFT", 14, -206)
  widthHint:SetText("Drag either bottom corner to scale the window. Width: /br width <180-400>.")

  local resetLook = MakeButton(look, "Reset look", 110, function()
    db.bgColor = { DEFAULTS.bgColor[1], DEFAULTS.bgColor[2], DEFAULTS.bgColor[3] }
    db.bgAlpha = DEFAULTS.bgAlpha
    db.showTitle, db.showBorder, db.scale = true, true, 1
    db.width = DEFAULTS.width
    ApplyGeometry()  -- in combat this lands when combat ends
    ApplyAppearance()
    RefreshConfig()
  end)
  resetLook:SetPoint("TOPLEFT", 14, -232)

  cfg.pillCheck = MakeCheck(look, L["Collapse to a pill while everyone is buffed"],
    function() return db.pill end,
    function(v) db.pill = v; Refresh() end)
  cfg.pillCheck:SetPoint("TOPLEFT", 10, -370)

  cfg.growCheck = MakeCheck(look, L["Grow the list upward"],
    function() return db.growUp end,
    function(v) db.growUp = v; X.ApplyAnchor(); Refresh() end)
  cfg.growCheck:SetPoint("TOPLEFT", 250, -288)

  cfg.twoColCheck = MakeCheck(look, L["Two columns when the list is long"],
    function() return db.twoCol end,
    function(v) db.twoCol = v; X.cols = nil; Refresh() end)
  cfg.twoColCheck:SetPoint("TOPLEFT", 10, -396)

  cfg.wizardBtn = MakeButton(look, "Run the setup wizard", 150, function()
    X.OpenWizard()
  end)
  cfg.wizardBtn:SetPoint("TOPLEFT", 134, -232)

  cfg.themeBtn = MakeButton(look, "Theme: Midnight", 170, function()
    local order = X.ThemeOrder()
    local cur = 1
    for i, k in ipairs(order) do if k:lower() == (db.theme or ""):lower() then cur = i end end
    X.ApplyTheme(order[cur % #order + 1])
  end)
  cfg.themeBtn:SetPoint("TOPLEFT", 250, -362)

  cfg.saveThemeBtn = MakeButton(look, "Save as theme", 150, function()
    local n = 1
    while X.SavedTheme("Custom " .. n) do n = n + 1 end
    local saved = X.SaveTheme("Custom " .. n)
    if saved then
      X.ApplyTheme(saved)
      Print("Theme saved as '" .. saved .. "'. Give it a better name any time: /br theme save <name> (saves the current look under it).")
    else
      Print("You already have 4 saved themes — /br theme delete <name> one first.")
    end
  end)
  cfg.saveThemeBtn:SetPoint("TOPLEFT", 428, -362)

  cfg.findCheck = MakeCheck(look, L["Show a name finder on the window"],
    function() return db.findBox end,
    function(v) db.findBox = v; X.ApplyRowLayout(); Refresh() end)
  cfg.findCheck:SetPoint("TOPLEFT", 250, -388)

  
  
  
  
  cfg.displayBtn = MakeButton(look, "More display options…", 170, function()
    local p = cfg.displayPanel
    if not p then return end
    if p:IsShown() then
      p:Hide()
      SelectTab(cfg.curTab or "look")
      return
    end
    for _, chk in pairs(cfg.coverChecks or {}) do chk:Update() end
    for rule, b in pairs(cfg.colorBtns or {}) do b:SetText(X.RowColorName(rule)) end
    if cfg.tooltipBtn then
      cfg.tooltipBtn:SetText(db.tooltipLevel:sub(1, 1):upper() .. db.tooltipLevel:sub(2))
    end
    if cfg.trimBtn then
      cfg.trimBtn:SetText((db.nameTrim or 0) == 0 and "full length" or ("max " .. db.nameTrim))
    if cfg.viewCheck then cfg.viewCheck:Update() end
    end
    for _, panel in pairs(cfg.panels) do panel:Hide() end
    p:Show()
  end)
  cfg.displayBtn:SetPoint("TOPLEFT", 250, -428)

  cfg.minimapCheck = MakeCheck(look, L["Minimap button (drag it around the minimap)"],
    function() return db.showMinimap end,
    function(v) db.showMinimap = v; if RefreshMinimapButton then RefreshMinimapButton() end end)
  cfg.minimapCheck:SetPoint("TOPLEFT", 10, -268)

  local cfgScaleLabel = look:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  cfgScaleLabel:SetPoint("TOPLEFT", 14, -296)
  cfgScaleLabel:SetText("Settings window scale")
  cfg.cfgScaleDrop = MakeScaleDropdown(look,
    function() return db.cfgScale or 1 end,
    function(v)
      db.cfgScale = v
      cfg:SetScale(v)
      RefreshConfig()
    end)
  cfg.cfgScaleDrop:SetPoint("LEFT", cfgScaleLabel, "RIGHT", 12, 0)

  cfg.strataBtn = MakeButton(look, "Layer: Medium", 150, function()
    local order = { "LOW", "MEDIUM", "HIGH", "DIALOG" }
    local cur = 2
    for i, k in ipairs(order) do if db.strata == k then cur = i end end
    db.strata = order[cur % #order + 1]
    ApplyAppearance()
    RefreshConfig()
  end)
  cfg.strataBtn:SetPoint("TOPLEFT", 14, -344)

  ------------------------------------------------------------------
  -- Tab: Alerts
  ------------------------------------------------------------------
  local alerts = cfg.panels.alerts
  section(alerts, "New name alert", 10, -6)

  cfg.soundCheck = MakeCheck(alerts, L["Play a sound when a name appears"],
    function() return db.playSound end,
    function(v) db.playSound = v; if v then PlayAlert() end end)
  cfg.soundCheck:SetPoint("TOPLEFT", 10, -30)

  cfg.soundBtn = MakeButton(alerts, "Sound: droplet", 150, function()
    local order = { "droplet", "system", "none" }
    local cur = 1
    for i, s in ipairs(order) do if db.alertSound == s then cur = i end end
    db.alertSound = order[cur % #order + 1]
    RefreshConfig()
    if db.playSound then PlayAlert() end
  end)
  cfg.soundBtn:SetPoint("TOPLEFT", 34, -58)

  local test = MakeButton(alerts, "Test", 60, PlayAlert)
  test:SetPoint("LEFT", cfg.soundBtn, "RIGHT", 10, 0)

  -- a sound per kind of alert (1.10.0); a kind without its own uses the
  -- main Sound choice above
  cfg.soundBtns = {}
  local kindNames = { new = "New name", drop = "Buff drop", ask = "Buff request", fall = "Buff fell off" }
  local kindY = { new = -58, drop = -84, ask = -110, fall = -136 }
  for _, kind in ipairs({ "new", "drop", "ask", "fall" }) do
    local k = kind
    local kb = MakeButton(alerts, kindNames[k] .. ": droplet", 170, function()
      local order = { "droplet", "system", "none" }
      local cur = db.alertSounds[k] or db.alertSound
      local idx = 1
      for i, sv in ipairs(order) do if cur == sv then idx = i end end
      db.alertSounds[k] = order[idx % #order + 1]
      RefreshConfig()
      PlayAlert(k)
    end)
    kb:SetPoint("TOPLEFT", 296, kindY[k])
    cfg.soundBtns[k] = kb
    Tip(kb, kindNames[k] .. " sound",
      "The sound for this kind of alert only. Click to switch between the water droplet, the game's raid warning sound and no sound. Any kind without its own uses the main Sound choice.")
  end

  cfg.muteInstCheck = MakeCheck(alerts, L["No alert sound in dungeons, raids or battlegrounds"],
    function() return db.muteInInstance end,
    function(v) db.muteInInstance = v end)
  cfg.muteInstCheck:SetPoint("TOPLEFT", 10, -92)

  section(alerts, "Buff drops", 302, -6)
  cfg.watchCheck = MakeCheck(alerts, L["Alert when a watched buff drops"],
    function() return db.watchDrop end,
    function(v) db.watchDrop = v end)
  cfg.watchCheck:SetPoint("TOPLEFT", 296, -30)

  cfg.fallCheck = MakeCheck(alerts, L["Sound when a buff falls off in combat"],
    function() return db.fallSound end,
    function(v) db.fallSound = v end)
  cfg.fallCheck:SetPoint("TOPLEFT", 296, -166)
  Tip(cfg.fallCheck, "Buff falls off in combat",
    "Play the 'Buff fell off' alert sound when a watched group buff that was up at the start of a fight is gone at the first scan after it. Single-target buffs keep their own drop alert above.")

  section(alerts, "Cast counter", 10, -136)
  cfg.counterCheck = MakeCheck(alerts, L["Show cast counter in the window"],
    function() return db.showCounter end,
    function(v) db.showCounter = v; UpdateCounter(); Refresh() end)
  cfg.counterCheck:SetPoint("TOPLEFT", 10, -160)

  local resetCount = MakeButton(alerts, "Reset counts", 110, function()
    X.sessionCasts, db.castsTotal = 0, 0
    db.history = {}
    UpdateCounter()
    Print("Cast counts reset.")
  end)
  resetCount:SetPoint("TOPLEFT", 34, -190)

  section(alerts, "Keybinds", 10, -230)
  local keyText = alerts:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  keyText:SetPoint("TOPLEFT", 14, -254)
  local keyText2 = alerts:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  keyText2:SetPoint("TOPLEFT", 14, -270)
  cfg.keyText, cfg.keyText2 = keyText, keyText2

  local setKey = MakeButton(alerts, "Set keybind", 120, OpenKeybinds)
  setKey:SetPoint("TOPLEFT", 14, -288)
  local makeMacro = MakeButton(alerts, "Create macro", 120, function() MakeMacro(false) end)
  makeMacro:SetPoint("LEFT", setKey, "RIGHT", 10, 0)

  local hint = alerts:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 14, -316)
  hint:SetWidth(420)
  hint:SetJustifyH("LEFT")
  hint:SetText("Cast next buff targets the first player in the list. Doesn't fire in combat.")

  ------------------------------------------------------------------
  -- Tab: Buffs
  ------------------------------------------------------------------
  local buffs = cfg.panels.buffs
  section(buffs, "Buffs to offer (only ones you know are listed)", 10, -6)

  -- Each buff row: checkbox + label, then a rebuff-time box. Empty box = use
  -- the all-buffs time below; a number overrides it for that buff only.
  cfg.buffChecks = {}
  local cols = { 10, 302 }
  local rebuffTip = "Offer this buff again when less than this many seconds of it remain. " ..
    "Leave empty to use the all-buffs time below. Press Enter to save, Esc to cancel."
  for i = 1, 16 do
    local cb = MakeCheck(buffs, "", function() return false end, function() end)
    local col = (i <= 8) and 1 or 2
    local row = (i - 1) % 8
    cb:SetPoint("TOPLEFT", cols[col], -34 - row * 26)
    cb.label:SetWidth(196)
    cb.label:SetJustifyH("LEFT")
    if cb.label.SetWordWrap then cb.label:SetWordWrap(false) end
    cb.label.maxWidth = 196
    Tip(cb, function() return cb.itemLabel or "" end,
      function() return "Offered to: " .. (cb.itemWho or "?") .. ". Untick to stop offering it." end)
    cb.rebuffBox = MakeSecondsBox(buffs,
      function() return (cb.itemKey and db.rebuffPer[cb.itemKey]) and tostring(db.rebuffPer[cb.itemKey]) or "" end,
      function(n)
        if not cb.itemKey then return end
        db.rebuffPer[cb.itemKey] = n  -- nil (empty box) = back to the all-buffs time
        Refresh()
      end)
    cb.rebuffBox:SetPoint("LEFT", buffs, "TOPLEFT", cols[col] + 236, -46 - row * 26)
    Tip(cb.rebuffBox, "Rebuff time (seconds)", rebuffTip)
    cb:Hide()
    cb.rebuffBox:Hide()
    cfg.buffChecks[i] = cb
  end
  local prioReset = MakeButton(buffs, "Reset buff order", 150, function()
    db.buffPrio = {}
    X.prioDirty = true
    Print("Buff order reset - your buffs are back in their normal order.")
    Refresh()
  end)
  prioReset:SetPoint("BOTTOMLEFT", buffs, "BOTTOMLEFT", 10, 10)
  Tip(prioReset, "Buff order",
    "Rows offer your buffs in the addon's normal order until you set your own: /br prio lists your buffs, /br prio <short name> <place> moves one. This button clears your order.")
  local prioHint = buffs:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  prioHint:SetPoint("LEFT", prioReset, "RIGHT", 8, 0)
  prioHint:SetText("Your own buff order: /br prio")

  cfg.rebuffHeads = {}
  for c = 1, 2 do
    local head = buffs:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    head:SetPoint("BOTTOM", buffs, "TOPLEFT", cols[c] + 256, -32)
    head:SetText("Rebuff (s)")
    head:Hide()
    cfg.rebuffHeads[c] = head
  end
  cfg.noBuffs = buffs:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  cfg.noBuffs:SetPoint("TOPLEFT", 14, -36)
  cfg.noBuffs:SetText("You don't know any supported buffs yet.")

  cfg.selfCheck = MakeCheck(buffs, L["Buff myself first (all buffs that suit me)"],
    function() return db.includeSelf end,
    function(v) db.includeSelf = v; Refresh() end)
  cfg.selfCheck:SetPoint("TOPLEFT", 10, -252)
  Tip(cfg.selfCheck, "Buff myself first",
    "Check your own character for every buff that suits your class and list yourself at the top. " ..
    "Self-only buffs (like a shaman's shield) are always checked.")

  local rebuffLabel = buffs:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  rebuffLabel:SetPoint("TOPLEFT", 14, -290)
  rebuffLabel:SetText("Offer a buff again when less than")
  cfg.rebuffDefault = MakeSecondsBox(buffs,
    function() return tostring(db.rebuff or 30) end,
    function(n)
      if not n then return end  -- the all-buffs time can't be empty
      db.rebuff = n
      Refresh()
    end)
  cfg.rebuffDefault:SetPoint("LEFT", rebuffLabel, "RIGHT", 10, 0)
  local rebuffUnit = buffs:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  rebuffUnit:SetPoint("LEFT", cfg.rebuffDefault, "RIGHT", 6, 0)
  rebuffUnit:SetText("seconds remain (all buffs)")
  Tip(cfg.rebuffDefault, "Rebuff time for all buffs (seconds)",
    "A buff that runs out sooner than this is offered again. 0 = only when it's gone. " ..
    "Per-buff boxes above override it. Same as /br rebuff <seconds>.")

  local rebuffHint = buffs:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  rebuffHint:SetPoint("TOPLEFT", 14, -314)
  rebuffHint:SetWidth(540)
  rebuffHint:SetJustifyH("LEFT")
  rebuffHint:SetText("Whole seconds, 0 to 3600. Press Enter to save, Esc to cancel.")

  ------------------------------------------------------------------
  -- Tab: Behavior
  ------------------------------------------------------------------
  local beh = cfg.panels.behavior
  section(beh, "When to show & scan", 10, -6)

  cfg.groupCheck = MakeCheck(beh, L["Only show in a party or raid"],
    function() return db.groupOnly end,
    function(v) db.groupOnly = v; Refresh() end)
  cfg.groupCheck:SetPoint("TOPLEFT", 10, -30)

  cfg.cityCheck = MakeCheck(beh, L["Pause scanning in major cities"],
    function() return db.pauseInCities end,
    function(v) db.pauseInCities = v; Refresh() end)
  cfg.cityCheck:SetPoint("TOPLEFT", 10, -56)

  cfg.bgCheck = MakeCheck(beh, L["Pause in battlegrounds and arenas"],
    function() return db.pauseInBG end,
    function(v) db.pauseInBG = v; Refresh() end)
  cfg.bgCheck:SetPoint("TOPLEFT", 10, -82)

  cfg.taxiCheck = MakeCheck(beh, L["Pause on flight paths"],
    function() return db.pauseTaxi end,
    function(v) db.pauseTaxi = v; Refresh() end)
  cfg.taxiCheck:SetPoint("TOPLEFT", 10, -108)

  cfg.consCheck = MakeCheck(beh, L["Track flasks, food and runes (coverage line)"],
    function() return db.consumables end,
    function(v) db.consumables = v; Refresh() end)
  cfg.consCheck:SetPoint("TOPLEFT", 10, -134)

  section(beh, "Casting & order", 302, -6)

  cfg.groupCastCheck = MakeCheck(beh, L["Offer group buffs in a party or raid"],
    function() return db.groupCast end,
    function(v) db.groupCast = v; Refresh() end)
  cfg.groupCastCheck:SetPoint("TOPLEFT", 296, -30)

  local gcLabel = beh:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gcLabel:SetPoint("TOPLEFT", 320, -62)
  gcLabel:SetText("...when at least this many need it:")
  local gcValue = beh:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gcValue:SetPoint("LEFT", gcLabel, "RIGHT", 6, 0)
  cfg.gcValue = gcValue
  cfg.gcSlider = MakeSlider(beh, 322, -80, 150, 2, 10, 1, function(v)
    db.groupCastMin = math.floor(v + 0.5)
    gcValue:SetText(tostring(db.groupCastMin))
    Refresh()
  end)
  -- Group-cast offers need group versions of buffs (Classic only): hide the
  -- controls here and move the rest of the column up into their space.
  local castY = 0
  if not CLASSIC_FEATURES then
    cfg.groupCastCheck:Hide()
    gcLabel:Hide()
    gcValue:Hide()
    cfg.gcSlider:Hide()
    castY = 82
  end

  cfg.sortBtn = MakeButton(beh, "Sort: name", 130, function()
    if db.sortMode == "name" then db.sortMode = "role"
    elseif db.sortMode == "role" then db.sortMode = "distance"
    elseif db.sortMode == "distance" then db.sortMode = "need"
    else db.sortMode = "name" end
    RefreshConfig()
    Refresh()
  end)
  cfg.sortBtn:SetPoint("TOPLEFT", 320, -140 + castY)
  local sortHint = beh:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  sortHint:SetPoint("LEFT", cfg.sortBtn, "RIGHT", 8, 0)
  sortHint:SetText("role = tanks & leaders · distance = nearest · need = most missing")

  section(beh, "Coordination", 302, -176 + castY)

  cfg.syncCheck = MakeCheck(beh, L["Sync casts with other BuffRadar users"],
    function() return db.sync end,
    function(v) db.sync = v end)
  cfg.syncCheck:SetPoint("TOPLEFT", 296, -200 + castY)

  cfg.requestsCheck = MakeCheck(beh, L["Mark players who ask for a buff in chat"],
    function() return db.requests end,
    function(v) db.requests = v end)
  cfg.requestsCheck:SetPoint("TOPLEFT", 296, -226 + castY)

  cfg.digestCheck = MakeCheck(beh, L["Print a summary when joining a group"],
    function() return db.joinDigest end,
    function(v) db.joinDigest = v end)
  cfg.digestCheck:SetPoint("TOPLEFT", 296, -252 + castY)

  cfg.queueCheck = MakeCheck(beh, L["Tag the next row after a cast"],
    function() return db.queueTag end,
    function(v) db.queueTag = v end)
  cfg.queueCheck:SetPoint("TOPLEFT", 296, -278 + castY)

  cfg.buddyCheck = MakeCheck(beh, L["Split the list with other BuffRadar users"],
    function() return db.buddySplit end,
    function(v) db.buddySplit = v; Refresh() end)
  cfg.buddyCheck:SetPoint("TOPLEFT", 296, -304 + castY)

  cfg.readyPostCheck = MakeCheck(beh, L["Post the ready-check summary to group chat"],
    function() return db.readyPost end,
    function(v) db.readyPost = v end)
  cfg.readyPostCheck:SetPoint("TOPLEFT", 296, -330 + castY)

  cfg.weaponCheck = MakeCheck(beh, L["Watch my weapon enchant"],
    function() return db.weaponWatch end,
    function(v) db.weaponWatch = v; Refresh() end)
  cfg.weaponCheck:SetPoint("TOPLEFT", 296, -356 + castY)

  cfg.enterCheck = MakeCheck(beh, L["Remind me when entering an instance unbuffed"],
    function() return db.enterFlash end,
    function(v) db.enterFlash = v end)
  cfg.enterCheck:SetPoint("TOPLEFT", 296, -382 + castY)

  cfg.clickThroughCheck = MakeCheck(beh, "Clicks pass through while locked",
    function() return db.clickThrough end,
    function(v) db.clickThrough = v; X.ApplyClickThrough() end)
  cfg.clickThroughCheck:SetPoint("TOPLEFT", 296, -408 + castY)
  cfg.modClickCheck = MakeCheck(beh, L["Shift-click a row casts the group version of its buff"],
    function() return db.modClick end,
    function(v) db.modClick = v; Refresh() end)
  cfg.modClickCheck:SetPoint("TOPLEFT", 296, -434 + castY)
  Tip(cfg.modClickCheck, "Modifier clicks", "Shift-click a row to cast the group version of its buff (Prayer of Fortitude, Gift of the Wild, greater blessings) instead of the single-target version. Plain clicks are unchanged. Same as /br modclick.")
  Tip(cfg.clickThroughCheck, "Click-through while locked",
    "While the window is locked, it and its rows stop catching mouse clicks, so clicks land on the game world behind them. Unlock with /br lock to move or use the window again.")

  cfg.throttleCheck = MakeCheck(beh, L["Halve the rescan rate in big groups"],
    function() return db.scanThrottle end,
    function(v) db.scanThrottle = v end)
  cfg.throttleCheck:SetPoint("TOPLEFT", 10, -215)
  cfg.fastAuraCheck = MakeCheck(beh, L["Skip rescans for aura changes that touch no watched buff"],
    function() return db.fastAura end,
    function(v) db.fastAura = v end)
  cfg.fastAuraCheck:SetPoint("TOPLEFT", 10, -240)
  cfg.pullFlashCheck = MakeCheck(beh, L["Flash when a pull timer starts"],
    function() return db.pullFlash end,
    function(v) db.pullFlash = v end)
  cfg.pullFlashCheck:SetPoint("TOPLEFT", 10, -265)

  section(beh, "More watches", 10, -298)

  cfg.petsCheck = MakeCheck(beh, L["Watch group pets"],
    function() return db.pets end,
    function(v) db.pets = v; Refresh() end)
  cfg.petsCheck:SetPoint("TOPLEFT", 10, -322)

  cfg.auraCheck = MakeCheck(beh, L["Watch my aura or aspect"],
    function() return db.auraWatch end,
    function(v) db.auraWatch = v; pcall(BuildBuffList); Refresh() end)
  cfg.auraCheck:SetPoint("TOPLEFT", 10, -348)

  cfg.worldCheck = MakeCheck(beh, L["Watch my world buffs"],
    function() return db.worldWatch end,
    function(v) db.worldWatch = v; Refresh() end)
  cfg.worldCheck:SetPoint("TOPLEFT", 10, -374)

  cfg.drinkCheck = MakeCheck(beh, L["Mark healers who are drinking"],
    function() return db.drinkWatch end,
    function(v) db.drinkWatch = v; Refresh() end)
  cfg.drinkCheck:SetPoint("TOPLEFT", 10, -400)

  cfg.deathCheck = MakeCheck(beh, L["Print a recap when I die"],
    function() return db.deathRecap end,
    function(v) db.deathRecap = v end)
  cfg.deathCheck:SetPoint("TOPLEFT", 10, -426)

  cfg.wipeCheck = MakeCheck(beh, L["Print a report after a wipe"],
    function() return db.wipeReport end,
    function(v) db.wipeReport = v end)
  cfg.wipeCheck:SetPoint("TOPLEFT", 10, -452)

  if not CLASSIC_FEATURES then
    -- Aura, world-buff and drinking watches are Forever-only concepts.
    cfg.auraCheck:Hide()
    cfg.worldCheck:Hide()
    cfg.drinkCheck:Hide()
  end

  local behHint = beh:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  behHint:SetPoint("TOPLEFT", 14, -140)
  behHint:SetWidth(270)
  behHint:SetJustifyH("LEFT")
  behHint:SetText("Right-click any name in the BuffRadar window to ignore that player; manage the list on the Ignore & Stats tab.")

  ------------------------------------------------------------------
  -- Tab: Ignore & Stats
  ------------------------------------------------------------------
  local data = cfg.panels.data
  section(data, "Ignored players", 10, -6)
  cfg.ignoreText = data:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cfg.ignoreText:SetPoint("TOPLEFT", 14, -32)
  cfg.ignoreText:SetWidth(540)
  cfg.ignoreText:SetJustifyH("LEFT")

  -- One cell per ignored name (3 columns x 4 rows), each with a remove button.
  -- RefreshConfig fills them; names past the 12th are counted in ignoreText.
  cfg.ignoreCells = {}
  for i = 1, 12 do
    local col, row = (i - 1) % 3, math_floor((i - 1) / 3)
    local cell = CreateFrame("Frame", nil, data)
    cell:SetSize(176, 20)
    cell:SetPoint("TOPLEFT", 14 + col * 182, -50 - row * 20)
    local x = CreateFrame("Button", nil, cell)
    x:SetSize(14, 14)
    x:SetPoint("LEFT", 0, 0)
    x:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    x:SetHighlightTexture("Interface\\Buttons\\UI-StopButton", "ADD")
    x:SetScript("OnClick", function()
      if not cell.ignored then return end
      local removed = Ignore.Remove(cell.ignored, true)  -- just this entry
      Print("No longer ignoring " .. table.concat(removed, ", ") .. ".")
      RefreshConfig()
      Refresh()
    end)
    x:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine("Stop ignoring " .. tostring(cell.ignored))
      if cell.ignored and not cell.ignored:find("-", 1, true) then
        GameTooltip:AddLine("(this name on every realm)", 0.6, 0.6, 0.6)
      end
      GameTooltip:Show()
    end)
    x:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cell.text = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cell.text:SetPoint("LEFT", x, "RIGHT", 4, 0)
    cell.text:SetPoint("RIGHT", cell, "RIGHT", -2, 0)
    cell.text:SetJustifyH("LEFT")
    if cell.text.SetWordWrap then cell.text:SetWordWrap(false) end
    cell:Hide()
    cfg.ignoreCells[i] = cell
  end

  local clearIgnores = MakeButton(data, "Clear ignore list", 140, function()
    wipe(db.ignored)
    wipe(Ignore.index)
    Print("Ignore list cleared.")
    RefreshConfig()
    Refresh()
  end)
  clearIgnores:SetPoint("TOPLEFT", 14, -138)

  section(data, "Casts by spell (all-time)", 10, -178)
  cfg.statsText = data:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cfg.statsText:SetPoint("TOPLEFT", 14, -204)
  cfg.statsText:SetWidth(540)
  cfg.statsText:SetJustifyH("LEFT")
  local resetStats = MakeButton(data, "Reset stats", 110, function()
    wipe(db.stats)
    Print("Cast statistics reset.")
    RefreshConfig()
  end)
  resetStats:SetPoint("TOPLEFT", 14, -290)

  section(data, "Settings profiles", 10, -330)
  local profHint = data:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  profHint:SetPoint("TOPLEFT", 14, -352)
  profHint:SetText("Save all your settings under a name; load them here or with /br profile.")
  cfg.profileBox = CreateFrame("EditBox", nil, data, "InputBoxTemplate")
  cfg.profileBox:SetSize(170, 20)
  cfg.profileBox:SetPoint("TOPLEFT", 18, -374)
  cfg.profileBox:SetAutoFocus(false)
  cfg.profileBox:SetMaxLetters(40)
  cfg.profileBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  cfg.profileBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  local function profName()
    return (cfg.profileBox:GetText() or ""):match("^%s*(.-)%s*$")
  end
  local profSave = MakeButton(data, "Save", 62, function()
    local name = profName()
    if X.SaveProfile(name) then Print("Profile saved: " .. name)
    else Print("Profile names use letters, numbers, - and _ (max 40).") end
    RefreshConfig()
  end)
  profSave:SetPoint("LEFT", cfg.profileBox, "RIGHT", 10, 0)
  local profLoad = MakeButton(data, "Load", 62, function()
    local name = profName()
    if X.LoadProfile(name) then
      Print("Profile loaded: " .. name)
      ApplyGeometry()
      ApplyAppearance()
      X.ApplyRowLayout()
      RefreshConfig()
      Refresh()
    else Print("No profile named '" .. name .. "'.") end
  end)
  profLoad:SetPoint("LEFT", profSave, "RIGHT", 6, 0)
  local profDel = MakeButton(data, "Delete", 62, function()
    local name = profName()
    if X.DeleteProfile(name) then Print("Profile deleted: " .. name)
    else Print("No profile named '" .. name .. "'.") end
    RefreshConfig()
  end)
  profDel:SetPoint("LEFT", profLoad, "RIGHT", 6, 0)
  local profShare = MakeButton(data, "Share", 62, function()
    local name = profName()
    local text = X.ProfileShareText(name)
    if text then
      X.ShowExport(text, false, "BuffRadar profile: " .. name)
    else
      Print("No profile named '" .. name .. "'.")
    end
  end)
  profShare:SetPoint("LEFT", profDel, "RIGHT", 6, 0)
  Tip(profShare, "Share this profile", "Shows the named profile as one copyable text you can send to another player; they bring it in with /br profile import. Only that one profile is shared, not your other settings.")
  cfg.profileText = data:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cfg.profileText:SetPoint("TOPLEFT", 14, -402)
  cfg.profileText:SetWidth(540)
  cfg.profileText:SetJustifyH("LEFT")

  local presetHint = data:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  presetHint:SetPoint("TOPLEFT", 14, -452)
  presetHint:SetText("Presets set window and behavior only (buff toggles are kept):")
  local presetX = 14
  for _, pname in ipairs({ "raid", "dungeon", "solo" }) do
    local pb = MakeButton(data, pname:sub(1, 1):upper() .. pname:sub(2), 76, function()
      if X.ApplyPreset(pname) then
        Print("Preset applied: " .. pname)
        ApplyGeometry()
        ApplyAppearance()
        X.ApplyRowLayout()
        RefreshConfig()
        Refresh()
      end
    end)
    pb:SetPoint("TOPLEFT", presetX, -470)
    presetX = presetX + 84
  end

  ------------------------------------------------------------------
  -- Hover help (the Buffs tab sets its own above)
  ------------------------------------------------------------------
  -- Window
  Tip(swatch, "Background color", "Click to pick the BuffRadar window's background color.")
  Tip(cfg.slider, "Background opacity", "0% = fully see-through background (text and icons stay visible). Scroll the mouse wheel to adjust in steps.")
  Tip(cfg.titleCheck, "Show BuffRadar title", "The \"BuffRadar\" name in the window's top-left corner.")
  Tip(cfg.borderCheck, "Show border", "The thin blue edge around the window.")
  Tip(cfg.compactCheck, "Compact rows", "Half-height rows without portraits, for long raid lists. The list text size is /br text <0.8-1.5>.")
  Tip(cfg.charPointCheck, "Per-character window position", "Each character keeps its own window spot. Off: one position shared by all characters.")
  Tip(cfg.scaleDrop, "Window scale", "Makes everything in the list window bigger or smaller. Can't be changed during combat. /br scale accepts any value from 0.5 to 2.")
  Tip(resetLook, "Reset look", "Restores the default color, opacity, title, border, scale and width. Your position and other settings are kept.")
  Tip(cfg.minimapCheck, "Minimap button", "Left-click it to show or hide the window, right-click for settings, drag it around the minimap. The addon compartment (minimap menu) works either way.")
  Tip(cfg.growCheck, "Grow the list upward", "The window stands on its bottom edge and the list grows upward instead of down — handy when the window sits low on the screen. The saved position remembers the form. Same as /br growup.")
  Tip(cfg.twoColCheck, "Two columns when the list is long", "With more than 8 people on the list, the rows split into two side-by-side columns and the window widens, instead of growing one tall column. Same as /br twocol.")
  Tip(cfg.themeBtn, "Color theme", "Click to cycle the window's color themes: Midnight, Crimson, Forest, Parchment — plus any themes you saved yourself. Picking a custom background color afterwards switches back to a custom theme. Same as /br theme <name>.")
  Tip(cfg.saveThemeBtn, "Save as theme", "Saves the window's current background and border colors as your own theme, so it joins the theme cycle. It is named automatically; /br theme save <name> saves under your own name, /br theme delete <name> removes one. Up to 4 saved themes.")
  Tip(cfg.strataBtn, "Window layer", "Which screen layer the window sits on: Low, Medium, High or Dialog. Raise it if other addons draw over BuffRadar; lower it if BuffRadar covers something it shouldn't. Same as /br strata <name>.")
  Tip(cfg.gapSlider, "Row spacing", "Extra empty space between the rows, 0 to 8. The window grows to fit. Same as /br rowgap <0-8>.")
  Tip(cfg.iconSlider, "Buff icon size", "How big the missing-buff icons on each row are, 10 to 24. At 0 the size is automatic (16, or 12 in compact rows). Same as /br iconsize <0|10-24>.")
  Tip(cfg.displayBtn, "More display options", "Opens a panel with the finer display choices: which parts the coverage line shows, colored edge marks on rows (your assignments, tanks, expiring soon, your buddy's rows), how much detail row tooltips carry, class-colored names, realm names and shortened names.")
  Tip(cfg.wizardBtn, "Setup wizard", "Runs the three-page first-run setup again: how you play, the window theme, and your buffs. Same as /br wizard.")
  Tip(cfg.findCheck, "Name finder", "A small Find box on the window: while it holds text, only players whose name matches are listed. Same as /br findbox; /br find <text> sets the text without the box.")
  Tip(cfg.cfgScaleDrop, "Settings window scale", "Makes this settings window bigger or smaller.")
  -- Alerts
  Tip(cfg.soundCheck, "New name alert", "Play a sound when a player appears on the list. Mute it any time with your Mute / unmute key or /br sound.")
  Tip(cfg.soundBtn, "Alert sound", "Click to switch between the water droplet, the game's raid warning sound and no sound. Plays the new choice.")
  Tip(test, "Test", "Play the alert sound now.")
  Tip(cfg.muteInstCheck, "Quiet in instances", "No alert sound in dungeons, raids, battlegrounds or arenas. The list still updates.")
  Tip(cfg.watchCheck, "Buff drop alert", "When a single-target buff of yours (like Earth Shield) disappears from the player who had it -- expired, dispelled or used up -- you get a message, the alert sound and a border flash, so you know to recast it. Moving it to another player doesn't trigger this. Same as /br watch.")
  Tip(cfg.counterCheck, "Cast counter", "Shows casts made through BuffRadar this session and all-time at the bottom of the window.")
  Tip(resetCount, "Reset counts", "Sets this session's and the all-time cast counts to zero. Per-spell stats (Ignore & Stats tab) are kept.")
  Tip(setKey, "Set keybind", "Opens Key Bindings at the BuffRadar section: Cast next buff, Show / hide window, Mute / unmute sound.")
  Tip(makeMacro, "Create macro", "Puts a BuffRadar macro on your cursor. Drop it on an action bar; pressing it casts the next buff.")
  -- Behavior
  Tip(cfg.groupCheck, "Only show in a party or raid", "Hide the window while you're solo. The Cast next buff key still works.")
  Tip(cfg.cityCheck, "Pause in major cities", "No scanning in capital cities, where crowds would fill the list. /br debug shows whether your zone counts as a city.")
  Tip(cfg.bgCheck, "Pause in battlegrounds and arenas", "No scanning in PvP instances.")
  Tip(cfg.taxiCheck, "Pause on flight paths", "While you're on a flight path you can't cast anyway, so the list pauses (like the city pause) instead of showing buffs you can't hand out. Same as /br taxi.")
  Tip(cfg.groupCastCheck, "Offer group buffs", "When enough group members need a buff, offer its group version (one cast covers the party).")
  Tip(cfg.gcSlider, "Group buff threshold", "How many group members must need the buff before the group version is offered.")
  Tip(cfg.sortBtn, "List order", "Click to switch: name = alphabetical; role = you, then tanks, then group leaders; distance = nearest first; need = whoever is missing the most castable buffs first.")
  Tip(cfg.syncCheck, "Cast sync", "When you or another BuffRadar user in your group casts a buff, everyone's list marks that player as being buffed for a few seconds, so two of you don't cast the same buff on the same player.")
  Tip(cfg.requestsCheck, "Chat buff requests", "A player on your list who whispers you (or says nearby) asking for a buff gets an 'asked for a buff' marker on their row.")
  Tip(cfg.digestCheck, "Group join summary", "One line in chat when you join a group: how many people are missing buffs and how many casts that is. Also prints when a Mythic+ run starts.")
  Tip(cfg.readyPostCheck, "Ready-check auto-post", "When a ready check runs, the summary is also posted to group chat — only when you're the leader or an assistant. Off: it only prints for you. Dead or AFK BuffRadar users hand their duties to the others automatically (cover-me, no setting).")
  Tip(cfg.weaponCheck, "Weapon enchant watch", "Your own row gets a 'weapon enchant missing' tag when an equipped weapon has no temporary enchant — a shaman imbue, a rogue poison, an oil or a sharpening stone. When your row isn't on the list, the coverage line says it instead.")
  Tip(cfg.enterCheck, "Instance-entry reminder", "One chat line when you step into a dungeon, raid or battleground while buffs are still missing: how many people still need buffs, and how many casts that is.")
  Tip(cfg.pullFlashCheck, "Pull-timer flash", "When a group pull timer starts (the game's /countdown, or a boss-mod pull timer from a trusted sender), the border flashes and chat shows the seconds and how many casts are still needed. Same as /br pullflash.")
  Tip(cfg.fastAuraCheck, "Fast aura updates", "Aura changes that touch no buff you can cast skip the rescan; the steady refresh still runs, and any doubtful payload rescans as before. Same as /br fastaura.")
  Tip(cfg.throttleCheck, "Scan throttle", "In groups of more than 20 players, the steady background rescan runs half as often. Refreshes caused by events — a buff landing, someone joining — always happen immediately. For very large raids on slower machines.")
  Tip(cfg.petsCheck, "Group pets", "Pets in your group get their own rows when they miss Fortitude, Mark of the Wild or Arcane Intellect — click the row to buff the pet. Pets never count in the coverage numbers. Same as /br pets.")
  Tip(cfg.auraCheck, "Aura / aspect watch", "Forever only: your own row flags it when no hunter aspect or paladin aura is up. Same as /br aura.")
  Tip(cfg.worldCheck, "World-buff watch", "Forever only: the coverage line lists your active world buffs (Dragonslayer, Warchief's Blessing, Songflower, ...) with the time left. Same as /br worldbuff.")
  Tip(cfg.drinkCheck, "Drinking healers", "Forever only: a player who is drinking gets a 'drinking' tag on their row, and healers who are drinking are counted on the coverage line. Same as /br drink.")
  Tip(cfg.deathCheck, "Death recap", "When you die, BuffRadar prints who in your group was missing which buffs at that moment — the rebuff list for after the rez. /br death shows the last recap again. Same as /br death.")
  Tip(cfg.wipeCheck, "Post-wipe report", "When a fight of 8 seconds or more ends with at least 3 dead (or 2 in a small party), BuffRadar prints who still needs buffs, and posts a one-line summary to group chat if you lead or assist. Same as /br wipe.")
  -- Ignore & Stats
  Tip(clearIgnores, "Clear ignore list", "Stops ignoring everyone on the list.")
  Tip(resetStats, "Reset stats", "Clears the casts-by-spell statistics. The cast counter is kept.")

  -- More display options (1.10.0): a small panel of its own — the tabs
  -- are full. Coverage-line parts, row color marks, tooltip detail and
  -- the row-name options live here.
  local dpanel = CreateFrame("Frame", nil, cfg, BackdropTemplateMixin and "BackdropTemplate" or nil)
  dpanel:SetSize(470, 484)
  dpanel:SetPoint("CENTER", cfg, "CENTER", 0, 0)
  if dpanel.SetBackdrop then
    dpanel:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 24,
      insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    local bc = X.ThemeBorder()
    dpanel:SetBackdropBorderColor(bc[1], bc[2], bc[3])
  end
  dpanel:EnableMouse(true)
  dpanel:Hide()
  cfg.displayPanel = dpanel
  local dtitle = dpanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  dtitle:SetPoint("TOPLEFT", 18, -14)
  dtitle:SetText("Display options")
  local dclose = MakeButton(dpanel, "Close", 70, function() dpanel:Hide(); SelectTab(cfg.curTab or "look") end)
  dclose:SetPoint("TOPRIGHT", -14, -10)
  section(dpanel, "Coverage line shows", 16, -44)
  cfg.coverChecks = {}
  local coverDefs = {
    { "progress", "Buffed count (15/15)" }, { "buffs", "Per-buff counts" },
    { "uptime", "Coverage uptime %" }, { "roster", "Radar roster" },
    { "expiry", "Expiry warnings" }, { "world", "World buffs" },
    { "drink", "Healers drinking" },
  }
  for i, cd in ipairs(coverDefs) do
    local part = cd[1]
    local chk = MakeCheck(dpanel, cd[2],
      function() return (db.coverParts or {})[part] ~= false end,
      function(v)
        db.coverParts = db.coverParts or {}
        if v then db.coverParts[part] = nil else db.coverParts[part] = false end
        Refresh()
      end)
    chk:SetPoint("TOPLEFT", 16 + ((i - 1) % 2) * 230, -68 - math.floor((i - 1) / 2) * 26)
    cfg.coverChecks[part] = chk
  end
  section(dpanel, "Row color marks", 16, -182)
  cfg.colorBtns = {}
  local ruleDefs = {
    { "mine", "Your assignments" }, { "tank", "Tanks" },
    { "expiring", "Expiring soon" }, { "buddy", "Buddy's rows" },
  }
  for i, rd in ipairs(ruleDefs) do
    local rule = rd[1]
    local lab = dpanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lab:SetPoint("TOPLEFT", 18, -210 - (i - 1) * 26)
    lab:SetText(rd[2])
    local btn
    btn = MakeButton(dpanel, "off", 130, function()
      local order = { "off", "gold", "sky", "red", "green", "violet" }
      local idx = 1
      for j, nm in ipairs(order) do if nm == X.RowColorName(rule) then idx = j end end
      local nxt = order[idx % #order + 1]
      if nxt == "off" then X.SetRowColor(rule, nil)
      else X.SetRowColor(rule, X.ROW_PALETTE[nxt]) end
      btn:SetText(X.RowColorName(rule))
    end)
    btn:SetPoint("TOPLEFT", 170, -208 - (i - 1) * 26)
    cfg.colorBtns[rule] = btn
  end
  cfg.classColorCheck = MakeCheck(dpanel, "Class-colored names",
    function() return db.classColors end,
    function(v) db.classColors = v; InvalidateRows(); Refresh() end)
  cfg.classColorCheck:SetPoint("TOPLEFT", 16, -424)
  cfg.realmCheck = MakeCheck(dpanel, "Show realm names",
    function() return db.showRealm end,
    function(v) db.showRealm = v; InvalidateRows(); Refresh() end)
  cfg.realmCheck:SetPoint("TOPLEFT", 246, -424)
  section(dpanel, "Row extras", 16, -318)
  cfg.barsCheck = MakeCheck(dpanel, "Duration bars on rows",
    function() return db.durationBars end,
    function(v) db.durationBars = v; InvalidateRows(); Refresh() end)
  cfg.barsCheck:SetPoint("TOPLEFT", 16, -342)
  cfg.markersCheck = MakeCheck(dpanel, "Raid markers on rows",
    function() return db.raidMarkers end,
    function(v) db.raidMarkers = v; InvalidateRows(); Refresh() end)
  cfg.markersCheck:SetPoint("TOPLEFT", 246, -342)
  cfg.focusCheck = MakeCheck(dpanel, "Focus target watch line",
    function() return db.focusWatch end,
    function(v) db.focusWatch = v; Refresh() end)
  cfg.focusCheck:SetPoint("TOPLEFT", 246, -368)

  Tip(cfg.barsCheck, "Duration bars", "A thin bar along each row's bottom edge: how much of a 30-minute span the expiring buff has left. Green over 15 minutes, yellow under it, red under 5. Same as /br bars.")
  Tip(cfg.markersCheck, "Raid markers", "Show each player's raid target icon (star, circle, ...) on their row, over the portrait. Same as /br markers.")
  Tip(cfg.focusCheck, "Focus watch", "A line above the coverage line about your focus target: what they still need, or that they're buffed. Same as /br focus.")
  cfg.viewCheck = MakeCheck(dpanel, "Group rows by buff (one row per buff still needed)",
    function() return db.viewMode == "buffs" end,
    function(v) db.viewMode = v and "buffs" or "people"; Refresh() end)
  cfg.viewCheck:SetPoint("TOPLEFT", 16, -398)
  Tip(cfg.viewCheck, "List view",
    "Unticked: one row per player, the classic list. Ticked: one row per buff still needed, showing how many players need it; click a row to cast that buff on an in-range player who needs it.")
  local tipLab = dpanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  tipLab:SetPoint("TOPLEFT", 18, -450)
  tipLab:SetText("Row tooltips")
  cfg.tooltipBtn = MakeButton(dpanel, "Standard", 120, function()
    local order = { "minimal", "standard", "full" }
    local idx = 2
    for j, nm in ipairs(order) do if nm == db.tooltipLevel then idx = j end end
    db.tooltipLevel = order[idx % #order + 1]
    cfg.tooltipBtn:SetText(db.tooltipLevel:sub(1, 1):upper() .. db.tooltipLevel:sub(2))
  end)
  cfg.tooltipBtn:SetPoint("TOPLEFT", 110, -446)
  local trimLab = dpanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  trimLab:SetPoint("TOPLEFT", 250, -450)
  trimLab:SetText("Name length")
  cfg.trimBtn = MakeButton(dpanel, "full length", 110, function()
    local order = { 0, 8, 10, 12, 14, 18 }
    local idx = 1
    for j, nm in ipairs(order) do if nm == (db.nameTrim or 0) then idx = j end end
    db.nameTrim = order[idx % #order + 1]
    cfg.trimBtn:SetText(db.nameTrim == 0 and "full length" or ("max " .. db.nameTrim))
    InvalidateRows()
    Refresh()
  end)
  cfg.trimBtn:SetPoint("TOPLEFT", 336, -446)

  -- Settings search (1.8.0): a find box along the window's bottom edge;
  -- typing dims every control that doesn't match (see X.CfgFilter).
  local searchBox = CreateFrame("EditBox", nil, cfg, "InputBoxTemplate")
  searchBox:SetSize(180, 20)
  searchBox:SetPoint("BOTTOMLEFT", cfg, "BOTTOMLEFT", 16, 10)
  searchBox:SetAutoFocus(false)
  searchBox:SetMaxLetters(30)
  local searchHint = cfg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  searchHint:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)
  searchHint:SetText("Find a setting")
  searchBox:SetScript("OnTextChanged", function(self)
    local t = self:GetText() or ""
    local n = X.CfgFilter(t)
    searchHint:SetText(t == "" and "Find a setting" or (n .. " matching"))
  end)
  searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  cfg.searchBox = searchBox
  X.cfgReg[#X.cfgReg + 1] = { w = cfg.slider, keys = "background opacity" }
  X.cfgReg[#X.cfgReg + 1] = { w = cfg.fadeSlider, keys = "idle fade" }
  X.cfgReg[#X.cfgReg + 1] = { w = cfg.gcSlider, keys = "group buff threshold" }
  X.cfgReg[#X.cfgReg + 1] = { w = cfg.scaleDrop, keys = "window scale" }
  X.cfgReg[#X.cfgReg + 1] = { w = cfg.cfgScaleDrop, keys = "settings window scale" }

  cfg:SetScript("OnShow", function()
    if cfg.searchBox then cfg.searchBox:SetText("") end  -- fresh search each open
    RefreshConfig()
  end)
  SelectTab("look")
  cfg:Hide()
end

RefreshConfig = function()
  db = X.GetDB()
  if not cfg or not cfg:IsShown() then return end
  local c = db.bgColor
  if cfg.swatch.SetBackdropColor then cfg.swatch:SetBackdropColor(c[1], c[2], c[3], 1) end
  cfg.slider:SetValue(math.floor((db.bgAlpha or 0.92) * 100 + 0.5))
  cfg.alphaValue:SetText(math.floor((db.bgAlpha or 0.92) * 100 + 0.5) .. "%")
  cfg.scaleDrop:Update()
  cfg.cfgScaleDrop:Update()
  cfg.titleCheck:Update()
  cfg.borderCheck:Update()
  if cfg.compactCheck then cfg.compactCheck:Update() end
  if cfg.charPointCheck then cfg.charPointCheck:Update() end
  if cfg.stripCheck then cfg.stripCheck:Update() end
  if cfg.clickThroughCheck then cfg.clickThroughCheck:Update() end
  for _, chk in pairs(cfg.coverChecks or {}) do chk:Update() end
  for rule, b in pairs(cfg.colorBtns or {}) do b:SetText(X.RowColorName(rule)) end
  if cfg.tooltipBtn then
    cfg.tooltipBtn:SetText(db.tooltipLevel:sub(1, 1):upper() .. db.tooltipLevel:sub(2))
  end
  if cfg.trimBtn then
    cfg.trimBtn:SetText((db.nameTrim or 0) == 0 and "full length" or ("max " .. db.nameTrim))
  end
  if cfg.gapSlider then
    cfg.gapSlider:SetValue(db.rowGap or 0)
    cfg.gapValue:SetText(tostring(db.rowGap or 0))
  end
  if cfg.iconSlider then
    cfg.iconSlider:SetValue(db.iconSize or 0)
    cfg.iconValue:SetText((db.iconSize or 0) == 0 and "auto" or tostring(db.iconSize))
  end
  if cfg.strataBtn then
    local st = db.strata or "MEDIUM"
    cfg.strataBtn:SetText("Layer: " .. st:sub(1, 1) .. st:sub(2):lower())
  end
  if cfg.fadeSlider then
    cfg.fadeSlider:SetValue(db.idleFade or 0)
    cfg.fadeValue:SetText((db.idleFade or 0) .. "%")
  end
  cfg.minimapCheck:Update()
  cfg.soundCheck:Update()
  cfg.soundBtn:SetText("Sound: " .. tostring(db.alertSound))
  for k, b in pairs(cfg.soundBtns or {}) do
    local nm = ({ new = "New name", drop = "Buff drop", ask = "Buff request", fall = "Buff fell off" })[k] or k
    b:SetText(nm .. ": " .. tostring(db.alertSounds[k] or db.alertSound))
  end
  cfg.muteInstCheck:Update()
  if cfg.watchCheck then cfg.watchCheck:Update() end
  cfg.counterCheck:Update()
  cfg.keyText:SetText("Cast next buff: " .. KeybindText(NEXT_BINDING) ..
    "    Cast next group buff: " .. KeybindText("CLICK BuffRadarGroupButton:LeftButton"))
  cfg.keyText2:SetText("Show / hide: " .. KeybindText("BUFFRADAR_TOGGLE") ..
    "    Mute: " .. KeybindText("BUFFRADAR_MUTE"))
  cfg.groupCheck:Update()
  cfg.cityCheck:Update()
  cfg.bgCheck:Update()
  if cfg.taxiCheck then cfg.taxiCheck:Update() end
  cfg.groupCastCheck:Update()
  cfg.gcSlider:SetValue(db.groupCastMin or 3)
  cfg.gcValue:SetText(tostring(db.groupCastMin or 3))
  cfg.sortBtn:SetText("Sort: " .. tostring(db.sortMode))
  if cfg.syncCheck then cfg.syncCheck:Update() end
  if cfg.requestsCheck then cfg.requestsCheck:Update() end
  if cfg.digestCheck then cfg.digestCheck:Update() end
  if cfg.pillCheck then cfg.pillCheck:Update() end
  if cfg.queueCheck then cfg.queueCheck:Update() end
  if cfg.consCheck then cfg.consCheck:Update() end
  if cfg.buddyCheck then cfg.buddyCheck:Update() end
  if cfg.readyPostCheck then cfg.readyPostCheck:Update() end
  if cfg.weaponCheck then cfg.weaponCheck:Update() end
  if cfg.enterCheck then cfg.enterCheck:Update() end
  if cfg.throttleCheck then cfg.throttleCheck:Update() end
  if cfg.growCheck then cfg.growCheck:Update() end
  if cfg.twoColCheck then cfg.twoColCheck:Update() end
  if cfg.themeBtn then
    local th = X.ThemeDef(db.theme)
    cfg.themeBtn:SetText("Theme: " .. (th and th.label or "Custom"))
  end
  if cfg.petsCheck then cfg.petsCheck:Update() end
  if cfg.auraCheck then cfg.auraCheck:Update() end
  if cfg.worldCheck then cfg.worldCheck:Update() end
  if cfg.drinkCheck then cfg.drinkCheck:Update() end
  if cfg.deathCheck then cfg.deathCheck:Update() end
  if cfg.wipeCheck then cfg.wipeCheck:Update() end
  if cfg.findCheck then cfg.findCheck:Update() end
  if cfg.barsCheck then cfg.barsCheck:Update() end
  if cfg.markersCheck then cfg.markersCheck:Update() end
  if cfg.focusCheck then cfg.focusCheck:Update() end

  -- Ignore list: one removable cell per name, the overflow counted in the summary
  local names = Ignore.Sorted()
  local cells = cfg.ignoreCells
  if #names == 0 then
    cfg.ignoreText:SetText("Nobody is ignored. Right-click a name in the window to ignore that player.")
  elseif #names > #cells then
    cfg.ignoreText:SetText(string.format("Ignored (%d) — %d more not shown; /br ignorelist lists all, /br unignore <name> removes one.",
      #names, #names - #cells))
  else
    cfg.ignoreText:SetText(string.format("Ignored (%d) — click the red button to stop ignoring a player. A name without a realm covers every realm.",
      #names))
  end
  for i, cell in ipairs(cells) do
    cell.ignored = names[i]
    if names[i] then
      cell.text:SetText(names[i])
      cell:Show()
    else
      cell:Hide()
    end
  end

  -- Stats summary: top 8 spells by count
  local statRows = {}
  for name, n in pairs(db.stats or {}) do statRows[#statRows + 1] = { name = name, n = n } end
  table.sort(statRows, function(a, b) return a.n > b.n end)
  if #statRows == 0 then
    cfg.statsText:SetText("No casts recorded yet. Statistics count casts made through BuffRadar.")
  else
    local parts = {}
    for i = 1, math.min(8, #statRows) do
      parts[#parts + 1] = string.format("%s: %d", statRows[i].name, statRows[i].n)
    end
    cfg.statsText:SetText(table.concat(parts, "   ·   "))
  end

  if cfg.profileText then
    local pnames = X.ProfileNames()
    local txt = #pnames > 0 and ("Saved profiles: " .. table.concat(pnames, ", "))
      or "No saved profiles yet."
    local autos = {}
    for ac, an in pairs(db.autoProfile) do autos[#autos + 1] = ac .. " -> " .. an end
    if #autos > 0 then
      table_sort(autos)
      txt = txt .. "\nAuto profiles: " .. table.concat(autos, ", ")
    end
    cfg.profileText:SetText(txt)
  end

  local items = {}
  for _, b in ipairs(myBuffs) do
    items[#items + 1] = { key = b.key, default = b.default, label = b.name, who = b.who }
  end
  if next(myBlessing) then
    items[#items + 1] = { key = "BLESSINGS", default = true, label = "Blessings", who = "one per class" }
  end
  for i, cb in ipairs(cfg.buffChecks) do
    local it = items[i]
    if it then
      cb.itemKey, cb.itemLabel, cb.itemWho = it.key, it.label, it.who
      cb.label:SetText(it.label .. "  |cff888888" .. (it.who or "") .. "|r")
      cb:FitLabel()
      cb:SetChecked(IsOn(it.key, it.default) and true or false)
      cb:SetScript("OnClick", function(self)
        db.enabled[it.key] = self:GetChecked() and true or false
        Refresh()
      end)
      cb:Show()
      -- Blessings have no per-buff time (Missing() uses the all-buffs one)
      local showBox = it.key ~= "BLESSINGS"
      cb.rebuffBox:SetShown(showBox)
      if showBox and not cb.rebuffBox:HasFocus() then cb.rebuffBox:Revert() end
    else
      cb.itemKey = nil
      cb:Hide()
      cb.rebuffBox:Hide()
    end
  end
  cfg.rebuffHeads[1]:SetShown(#items > 0)
  cfg.rebuffHeads[2]:SetShown(#items > 8)
  if not cfg.rebuffDefault:HasFocus() then cfg.rebuffDefault:Revert() end
  cfg.noBuffs:SetShown(#items == 0)
  cfg.selfCheck:Update()
end

-- Toggles the settings window; forceShow opens it without toggling it closed.
OpenConfig = function(forceShow)
  db = X.GetDB()
  if not cfg then BuildConfig() end
  if cfg:IsShown() and not forceShow then cfg:Hide() else cfg:Show() end
end

-- Esc > Options > AddOns > BuffRadar: a short page with a button that opens
-- the full settings window (which has more room than the options page).
if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
  local page = CreateFrame("Frame")
  local head = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  head:SetPoint("TOPLEFT", 16, -16)
  head:SetText("|cff33ccffBuff|rRadar")
  local about = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  about:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -10)
  about:SetWidth(520)
  about:SetJustifyH("LEFT")
  about:SetText("BuffRadar's settings have their own window. You can also open it with the gear " ..
    "icon in the BuffRadar window, by right-clicking the minimap button or the addon menu " ..
    "entry, or with /br config.")
  local open = MakeButton(page, "Open BuffRadar settings", 200, function()
    if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then pcall(HideUIPanel, SettingsPanel) end
    OpenConfig(true)
  end)
  open:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 0, -14)
  local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, page, "BuffRadar")
  if ok and category then pcall(Settings.RegisterAddOnCategory, category) end
end
end -- config window block
X.RefreshConfig, X.OpenConfig = RefreshConfig, OpenConfig
