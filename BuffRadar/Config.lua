-- BuffRadar - settings window, controls and keyboard navigation.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local X = ns.X
local core = X.Core
X.cfgReg = {}

local db  -- the live settings table; read fresh at each entry point (X.GetDB)
local L = X.L
local Print, Refresh, PlayAlert = X.Print, X.Refresh, core.PlayAlert
local ApplyAppearance, ApplyGeometry = X.ApplyAppearance, X.ApplyGeometry
local BuildBuffList, InvalidateRows, UpdateCounter = core.BuildBuffList, X.InvalidateRows, X.UpdateCounter
local IsOn = core.IsOn
local KeybindText, OpenKeybinds, MakeMacro = core.KeybindText, core.OpenKeybinds, core.MakeMacro
local RefreshMinimapButton = X.RefreshMinimapButton
local myBuffs = core.Buffs
local Ignore = X.Ignore
local DEFAULTS = X.Settings.Defaults
local SCALE_PRESETS = { 0.5, 0.75, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2 }
local CLASSIC_FEATURES = X.classic
local NEXT_BINDING = core.NextBinding
local pairs, ipairs, type, tonumber, tostring, pcall = pairs, ipairs, type, tonumber, tostring, pcall
local math_floor, math_min = math.floor, math.min
local table_sort = table.sort
local wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

local OpenConfig, RefreshConfig  -- assigned in the block below, published on X after it

do
local cfg
local SelectTab
local CONFIG_WIDTH, CONFIG_HEIGHT = 600, 610
local NATIVE_TAB_DEPTH = 30  -- 32-unit native tabs start 2 units above the bottom edge
local K = {}  -- keyboard navigation and speech are opt-in for this settings session
local navigationHelp = L["Tab or Shift-Tab moves. Enter or Space selects. Arrows adjust. F1 toggles speech. Escape exits."]

function K.Register(widget, panel, label, role, value, adjust)
  if not cfg then return end
  local entry = { widget = widget, panel = panel, label = label, role = role, value = value, adjust = adjust }
  widget.navigation = entry
  entry.order = #cfg.navControls + 1
  cfg.navControls[entry.order] = entry
  widget:HookScript("OnMouseDown", function()
    if K.active then K.Stop() end
  end)
  return entry
end

function K.Available(entry)
  if not entry or not entry.widget:IsVisible() then return false end
  local role = entry.role
  return role == "tab" or not entry.widget.IsEnabled or entry.widget:IsEnabled()
end

function K.Modal()
  if cfg.themePriorityPanel and cfg.themePriorityPanel:IsVisible() then return cfg.themePriorityPanel end
  local assignments = cfg.assignmentPanel
  local preview = assignments and assignments.preview
  local blockers = preview and preview.blockers
  return assignments and assignments:IsShown()
    and (assignments.subgroup and assignments.subgroup:IsVisible() and assignments.subgroup
      or assignments.coordination and assignments.coordination:IsVisible() and assignments.coordination
      or assignments.preparation and assignments.preparation:IsVisible() and assignments.preparation
      or assignments.coverage and assignments.coverage:IsVisible() and assignments.coverage
      or assignments.practice and assignments.practice:IsVisible()
        and (assignments.practice.review and assignments.practice.review:IsVisible() and assignments.practice.review or assignments.practice)
      or blockers and blockers.review and blockers.review:IsVisible() and blockers.review
      or assignments.picker:IsShown() and assignments.picker
      or preview and preview:IsShown()
        and (preview.roleEditor and preview.roleEditor:IsShown() and preview.roleEditor
          or blockers and blockers:IsShown() and (blockers.exceptionEditor
            and blockers.exceptionEditor:IsShown() and blockers.exceptionEditor or blockers) or preview)
      or assignments)
    or cfg.blessingPanel and cfg.blessingPanel:IsShown() and cfg.blessingPanel
    or cfg.displayPanel and cfg.displayPanel:IsShown() and cfg.displayPanel
end

function K.InScope(entry)
  if not K.Available(entry) then return false end
  local modal = K.Modal()
  return entry.panel == (modal or cfg.panels[cfg.curTab]) or (not modal and entry.panel == cfg)
end

function K.Controls()
  if cfg.searchResultsPanel and cfg.searchResultsPanel:IsVisible() then
    local found = {}
    local function append(widget)
      if widget and K.Available(widget.navigation) then found[#found + 1] = widget.navigation end
    end
    append(cfg.searchBox)
    for _, row in ipairs(cfg.searchRows) do append(row) end
    append(cfg.searchPrev); append(cfg.searchNext); append(cfg.searchToggle)
    return found
  end
  local modal = K.Modal()
  local panel = modal or cfg.panels[cfg.curTab]
  local entries, controls = {}, {}
  for _, entry in ipairs(cfg.navControls) do
    if K.Available(entry) then
      if entry.panel == panel then
        controls[#controls + 1] = entry
      elseif not modal and entry.role == "tab" then
        entries[#entries + 1] = entry
      end
    end
  end
  -- Main tabs first, then the visible controls in row order.
  table_sort(controls, function(a, b)
    local y1, y2 = math_floor((a.widget:GetTop() or 0) / 8), math_floor((b.widget:GetTop() or 0) / 8)
    if y1 ~= y2 then return y1 > y2 end
    local x1, x2 = a.widget:GetLeft() or 0, b.widget:GetLeft() or 0
    if x1 ~= x2 then return x1 < x2 end
    return a.order < b.order
  end)
  for _, entry in ipairs(controls) do entries[#entries + 1] = entry end
  if not modal then
    for _, widget in ipairs({ cfg.searchToggle, cfg.searchBox, cfg.closeButton }) do
      if K.Available(widget.navigation) then entries[#entries + 1] = widget.navigation end
    end
  end
  return entries
end

function K.Speak(text)
  K.sequence = (K.sequence or 0) + 1
  if not K.narrate then return end
  local sequence = K.sequence
  local function speak()
    if K.sequence ~= sequence or not K.active then return end
    -- Blizzard's Windows TTS accepts XML. Speak only plain setting labels and values.
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[<>&|%c]", " ")
    local ok, available = pcall(function()
      local voice = TextToSpeech_GetSelectedVoice(Enum.TtsVoiceType.Standard)
      if voice then
        C_VoiceChat.SpeakText(voice.voiceID, text, C_TTSSettings.GetSpeechRate(), C_TTSSettings.GetSpeechVolume(), false)
        return true
      end
    end)
    if not ok or not available then
      K.narrate = false
      Print(L["Settings narration is unavailable. Check the game's Text to Speech settings."])
    end
  end
  if C_Timer and C_Timer.After then C_Timer.After(0.18, speak) else speak() end
end

function K.Focus(entry)
  K.current = entry
  if not entry then
    cfg.navOutline:Hide()
    cfg.navStatus:SetText("")
    K.sequence = (K.sequence or 0) + 1
    return
  end
  local widget = entry.widget
  local label = entry.label
  if type(label) == "function" then label = label() end
  if type(label) ~= "string" or label == "" then label = L["Setting"] end
  local value = entry.value and entry.value()
  if entry.role == "check" then value = widget:GetChecked() and L["Checked"] or L["Not checked"]
  elseif entry.role == "tab" and entry.key == cfg.curTab then value = L["Selected tab"]
  elseif entry.role == "tab" then value = L["Tab"]
  elseif entry.role == "edit" then value = value or L["Edit field"]
  elseif entry.role == "button" then value = value or L["Button"] end
  local text = value and (label .. ", " .. value) or label
  cfg.navStatus:SetText(text)
  local border = cfg.navOutline
  border:ClearAllPoints()
  border:SetPoint("TOPLEFT", widget, "TOPLEFT", -2, 2)
  if entry.role == "check" then
    border:SetPoint("BOTTOMRIGHT", widget.label, "BOTTOMRIGHT", 2, -2)
  else
    border:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", 2, -2)
  end
  border:Show()
  K.Speak(text)
end

function K.Move(delta)
  local entries = K.Controls()
  if #entries == 0 then K.Focus(nil); return end
  local at = delta > 0 and 0 or 1
  for i, entry in ipairs(entries) do
    if entry == K.current then at = i; break end
  end
  K.Focus(entries[(at - 1 + delta) % #entries + 1])
end

function K.Stop(cancel)
  if not K.active then return end
  local edit = K.edit
  K.active, K.narrate, K.current, K.edit, K.transition = nil, nil, nil, nil, nil
  K.sequence = (K.sequence or 0) + 1
  if edit and edit:HasFocus() then
    local escape = cancel and edit:GetScript("OnEscapePressed")
    if escape then escape(edit) else edit:ClearFocus() end
  end
  cfg.navInput:ClearFocus()
  cfg.navInput:Hide()
  cfg.navOutline:Hide()
  cfg.navStatus:Hide()
  cfg.navButton:SetText(L["Keyboard Navigation"])
end

function K.Edit(box)
  K.edit, K.transition = box, true
  cfg.navStatus:Hide()
  cfg.navInput:ClearFocus()
  box:SetFocus()
  K.transition = nil
  if not box:HasFocus() then K.Stop() end
end

function K.RegisterEdit(box, panel, label, value)
  K.Register(box, panel, label, "edit", value)
  box:HookScript("OnEditFocusLost", function(self)
    if K.edit == self and not K.transition then K.Stop() end
  end)
  for _, event in ipairs({ "OnEnterPressed", "OnEscapePressed", "OnTabPressed" }) do
    local original = box:GetScript(event)
    box:SetScript(event, function(self)
      if K.edit ~= self then
        if original then original(self) end
        return
      end
      K.transition = true
      if original then original(self) end
      if K.edit ~= self then return end
      if self:HasFocus() then self:ClearFocus() end
      if not K.active then return end
      K.edit = nil
      cfg.navInput:SetFocus()
      K.transition = nil
      if not cfg.navInput:HasFocus() then K.Stop(); return end
      if not cfg.searchFooter:IsShown() then cfg.navStatus:Show() end
      if event == "OnTabPressed" or not K.InScope(K.current) then
        K.Move(IsShiftKeyDown() and -1 or 1)
      else
        K.Focus(K.current)
      end
    end)
  end
end

function K.Act(delta)
  local entry = K.current
  if not K.InScope(entry) then K.Move(1); return end
  local widget = entry.widget
  if delta and entry.adjust then
    entry.adjust(delta)
  elseif delta then
    return
  elseif entry.role == "edit" then
    K.Edit(widget)
    return
  elseif entry.adjust then
    if entry.role ~= "slider" then entry.adjust(1) end
  elseif entry.role == "tab" and entry.key == cfg.curTab then
    return
  elseif entry.role == "check" then
    widget:SetChecked(not widget:GetChecked())
    widget:GetScript("OnClick")(widget)
  else
    widget:Click()
  end
  if K.active and not K.edit and not cfg.navInput:HasFocus() then K.Stop(); return end
  if K.active and not K.edit then
    if not K.InScope(K.current) then K.Move(1)
    elseif K.current == entry then K.Focus(entry) end
  end
end

function K.Start(narrate)
  if X.PlayerSuspended() or InCombatLockdown() then
    Print(L["Settings keyboard navigation is unavailable in combat or while dead."])
    return
  end
  if K.active then K.Stop() end
  K.active, K.narrate = true, narrate
  cfg.navButton:SetText(L["Exit Navigation"])
  cfg.navInput:Show()
  -- Leave a visible search query and result count intact when taking focus.
  if cfg.searchBox:HasFocus() then cfg.searchBox:ClearFocus() end
  cfg.navInput:SetFocus()
  if not cfg.navInput:HasFocus() then K.Stop(); return end
  if not cfg.searchFooter:IsShown() then cfg.navStatus:Show() end
  Print(navigationHelp)
  K.Move(1)
end

function K.Build()
  local button = X.PanelWidget("Button", nil, cfg, "UIPanelButtonTemplate")
  button:SetSize(166, 22)
  button:SetPoint("BOTTOMRIGHT", cfg, "BOTTOMRIGHT", -16, 9)
  button:SetText(L["Keyboard Navigation"])
  button:SetScript("OnClick", function()
    if K.active then K.Stop() else K.Start(false) end
  end)
  cfg.navButton = button
  local status = cfg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("BOTTOMLEFT", cfg, "BOTTOMLEFT", 16, 12)
  status:SetPoint("RIGHT", button, "LEFT", -10, 0)
  status:SetJustifyH("LEFT")
  status:SetWordWrap(false)
  status:Hide()
  cfg.navStatus = status
  local border = X.PanelWidget("Frame", nil, cfg, BackdropTemplateMixin and "BackdropTemplate" or nil)
  if border.SetBackdrop then
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    border:SetBackdropBorderColor(1, 0.82, 0.24, 1)
  end
  border:SetFrameLevel(cfg:GetFrameLevel() + 20)
  border:Hide()
  cfg.navOutline = border
  local input = CreateFrame("EditBox", nil, cfg)
  input:SetSize(1, 1)
  input:SetPoint("CENTER", button)
  input:SetAlpha(0)
  input:EnableMouse(false)
  input:SetFontObject("GameFontHighlightSmall")
  input:SetAutoFocus(false)
  input:SetAltArrowKeyMode(false)
  input:SetMaxLetters(1)
  input:SetScript("OnChar", function(self) self:SetText("") end)
  input:SetScript("OnEditFocusLost", function() if not K.transition then K.Stop() end end)
  input:SetScript("OnTabPressed", function() K.Move(IsShiftKeyDown() and -1 or 1) end)
  input:SetScript("OnEnterPressed", function() K.Act() end)
  input:SetScript("OnSpacePressed", function() K.Act() end)
  input:SetScript("OnEscapePressed", function()
    local picker = cfg.assignmentPanel and cfg.assignmentPanel.picker
    local modal = K.Modal()
    if cfg.themePriorityPanel and modal == cfg.themePriorityPanel then modal.closeButton:Click()
    elseif picker and modal == picker then picker.closeButton:Click()
    else K.Stop() end
  end)
  input:SetScript("OnArrowPressed", function(_, key)
    if key == "LEFT" or key == "DOWN" then K.Act(-1)
    elseif key == "RIGHT" or key == "UP" then K.Act(1) end
  end)
  input:SetScript("OnKeyDown", function(_, key)
    if key == "F1" then
      K.narrate = not K.narrate
      Print(K.narrate and L["Settings narration on"] or L["Settings narration off"])
      K.Focus(K.current)
    end
  end)
  input:Hide()
  cfg.navInput = input
end

local function ApplyConfigScale()
  local scale = db.cfgScale or 1
  local width, height = UIParent:GetSize()
  if width and height and width > 12 and height > 12 then
    -- Reserve room below a centered window for the tabs drawn outside it.
    local tabDepth = cfg.nativeTabs and NATIVE_TAB_DEPTH or 0
    scale = math_min(scale, (width - 12) / CONFIG_WIDTH, (height - 12) / (CONFIG_HEIGHT + 2 * tabDepth))
  end
  if cfg:GetScale() ~= scale then cfg:SetScale(scale) end
end

local function SearchKey(label)
  return (label:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")):lower()
end

local function RegisterSearch(widget, panel, label)
  local owner, guard, path, blocked = panel, 0, {}, false
  while owner and owner ~= cfg and guard < 20 do
    if owner.searchBoundary and not owner.searchOpen then blocked = true end
    if owner.searchOpen then path[#path + 1] = owner end
    if owner.searchTab then break end
    owner, guard = owner:GetParent(), guard + 1
  end
  local entry = { w = widget, panel = panel, label = label, keys = SearchKey(label),
    tab = not blocked and owner and owner.searchTab, owner = owner, path = path, order = #X.cfgReg + 1 }
  X.cfgReg[#X.cfgReg + 1] = entry
  return entry
end

local function SearchAvailable(entry)
  if not entry.tab or entry.label == "" or not entry.w:IsShown() then return false end
  for _, panel in ipairs(entry.path) do
    if panel.searchFilter and not panel.searchFilter(entry.w) then return false end
  end
  return true
end

function X.CfgSearch(query)
  local results = {}
  query = SearchKey(query or "")
  for _, entry in ipairs(X.cfgReg) do
    if SearchAvailable(entry)
        and (entry.keys .. " " .. SearchKey(cfg.tabBtns[entry.tab]:GetText())):find(query, 1, true) then
      results[#results + 1] = entry
    end
  end
  table_sort(results, function(a, b)
    local x, y = cfg.tabBtns[a.tab].navigation.order, cfg.tabBtns[b.tab].navigation.order
    if x ~= y then return x < y end
    return a.order < b.order
  end)
  return results
end

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
    local height = self.label.maxWidth and self.label:GetStringHeight() or 24
    local extra = math.max(0, (height - 24) / 2)
    self:SetHitRectInsets(0, -(w + 4), -extra, -extra)
  end
  cb:FitLabel()
  cb:SetScript("OnClick", function(self) setter(self:GetChecked() and true or false) end)
  cb.Update = function(self) self:SetChecked(getter() and true or false) end
  K.Register(cb, parent, function() return cb.label:GetText() end, "check")
  if label and label ~= "" then  -- settings search registry (1.8.0)
    RegisterSearch(cb, parent, label)
  end
  return cb
end

local function WrapCheckLabel(check)
  local label = check.label
  label.maxWidth = 250
  label:SetWidth(label.maxWidth)
  label:SetJustifyH("LEFT")
  label:SetWordWrap(true)
  check:FitLabel()
end

-- Search only the visible controls in the active tab. Preserve any
-- alpha set by the widget itself so closing search restores it.
function X.CfgFilter(q)
  q = (q or ""):lower()
  local panel = cfg and cfg.panels and cfg.panels[cfg.curTab]
  local hits = 0
  for _, r in ipairs(X.cfgReg) do
    local inTab = panel and r.panel == panel and panel:IsShown() and r.w:IsShown()
    local matches = inTab and (q == "" or r.keys:find(q, 1, true) ~= nil)
    if matches then hits = hits + 1 end
    if inTab and q ~= "" and not matches then
      if r.alpha == nil then
        r.alpha = r.w:GetAlpha()
        r.w:SetAlpha(r.alpha * 0.25)
      end
    elseif r.alpha ~= nil then
      r.w:SetAlpha(r.alpha)
      r.alpha = nil
    end
  end
  return hits
end

local function UpdateSearch()
  local query = cfg.searchBox:GetText() or ""
  X.CfgFilter(query)
  cfg.searchResults = query ~= "" and X.CfgSearch(query) or {}
  local count, pageSize = #cfg.searchResults, #cfg.searchRows
  cfg.searchPage = math_min(cfg.searchPage or 1, math.max(1, math.ceil(count / pageSize)))
  for i, row in ipairs(cfg.searchRows) do
    local entry = cfg.searchResults[(cfg.searchPage - 1) * pageSize + i]
    row.entry = entry
    if entry then
      local enabled = not entry.w.IsEnabled or entry.w:IsEnabled()
      row:SetText(cfg.tabBtns[entry.tab]:GetText() .. " > " .. entry.label
        .. (enabled and "" or (" — " .. L["Unavailable"])))
    end
    row:SetShown(entry ~= nil)
  end
  cfg.searchHint:SetText(query == "" and L["Find settings across all tabs"]
    or count == 0 and L["No settings match this search."] or string.format(L["Matches: %d"], count))
  cfg.searchResultsPanel:SetShown(query ~= "")
  if cfg.searchPage > 1 then cfg.searchPrev:Enable() else cfg.searchPrev:Disable() end
  if cfg.searchPage * pageSize < count then cfg.searchNext:Enable() else cfg.searchNext:Disable() end
end

local function CloseSearch()
  if not cfg.searchBox then return end
  cfg.searchBox:ClearFocus()
  cfg.searchBox:SetText("")
  cfg.searchPage = 1
  cfg.searchResultsPanel:Hide()
  X.CfgFilter("")
  cfg.searchHint:SetText(L["Find settings across all tabs"])
  cfg.searchFooter:Hide()
  if K.active and not K.edit then cfg.navStatus:Show() end
end

local function OpenSearch()
  cfg.searchFooter:Show()
  if K.active then
    K.Focus(cfg.searchBox.navigation)
    K.Edit(cfg.searchBox)
  else
    cfg.searchBox:SetFocus()
  end
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
  local eb = X.PanelWidget("EditBox", nil, parent, "InputBoxTemplate")
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
  local b = X.PanelWidget("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  if text and text ~= "" then  -- settings search registry (1.8.0)
    RegisterSearch(b, parent, text)
    K.Register(b, parent, function() return b:GetText() end, "button")
  end
  return b
end

local function MakeSlider(parent, x, y, width, minV, maxV, step, onChange, label, valueText)
  local slider = X.PanelWidget("Slider", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
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
  local function adjust(delta)
    slider:SetValue(math.max(minV, math.min(maxV, slider:GetValue() + delta * step)))
  end
  slider:SetScript("OnMouseWheel", function(_, delta) adjust(delta) end)
  slider:SetScript("OnValueChanged", function(_, v) onChange(v) end)
  K.Register(slider, parent, label, "slider", valueText, adjust)
  return slider
end

local function OpenColorPicker()
  K.Stop()
  local c, stored = X.ThemeBackground(), db.bgColor
  local previousTheme, previousColor = db.theme, { stored[1], stored[2], stored[3] }
  local opening = true
  local function refreshAppearance()
    if not X.ResolveAutoTheme() then
      ApplyAppearance()
      RefreshConfig()
    end
  end
  local function apply()
    if opening then return end
    local r, g, b = ColorPickerFrame:GetColorRGB()
    db.bgColor = { r, g, b }
    db.theme = "custom"  -- a hand-picked color leaves the theme presets (1.8.0)
    refreshAppearance()
  end
  local function cancel()
    db.theme, db.bgColor = previousTheme, previousColor
    refreshAppearance()
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
  opening = false
end

local function PercentText(v) return math_floor(v * 100 + 0.5) .. "%" end

-- Scale picker: the game's menu dropdown, with one entry per SCALE_PRESETS value.
-- A scale set by /br scale that isn't a preset shows as "Custom (n%)". Clients
-- without the dropdown template get a button that steps through the presets.
local function MakeScaleDropdown(parent, getter, setter, label)
  local function value()
    local current = getter()
    for _, preset in ipairs(SCALE_PRESETS) do
      if math.abs(preset - current) < 0.001 then return PercentText(preset) end
    end
    return string.format(L["Custom (%s)"], PercentText(current))
  end
  local function adjust(delta)
    local current = getter()
    local nextValue = delta > 0 and SCALE_PRESETS[1] or SCALE_PRESETS[#SCALE_PRESETS]
    if delta > 0 then
      for _, preset in ipairs(SCALE_PRESETS) do
        if preset > current + 0.001 then nextValue = preset; break end
      end
    else
      for i = #SCALE_PRESETS, 1, -1 do
        if SCALE_PRESETS[i] < current - 0.001 then nextValue = SCALE_PRESETS[i]; break end
      end
    end
    setter(nextValue)
  end
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
      if self.SetDefaultText then self:SetDefaultText(value()) end
      if self.GenerateMenu then self:GenerateMenu() end
    end
    K.Register(dd, parent, label, "choice", value, adjust)
    return dd
  end
  local b = MakeButton(parent, "", 120, function(self)
    adjust(1)
    self:Update()
  end)
  b.Update = function(self) self:SetText(PercentText(getter())) end
  K.Register(b, parent, label, "choice", value, adjust)
  return b
end

SelectTab = function(key)
  CloseSearch()
  cfg.curTab = key
  if cfg.themePriorityPanel then cfg.themePriorityPanel:Hide() end
  if cfg.displayPanel then cfg.displayPanel:Hide() end
  if cfg.blessingPanel then cfg.blessingPanel:Hide() end
  if cfg.assignmentPanel then cfg.assignmentPanel:Hide() end
  for k, panel in pairs(cfg.panels) do panel:SetShown(k == key) end
  if cfg.searchToggle and cfg.panels[key] then
    cfg.searchToggle:ClearAllPoints()
    cfg.searchToggle:SetPoint("TOPRIGHT", cfg.panels[key], "TOPRIGHT", -8, -4)
    cfg.searchToggle:Show()
  end
  if cfg.nativeTabs then
    PanelTemplates_SetTab(cfg, cfg.tabBtns[key]:GetID())
  else
    for k, btn in pairs(cfg.tabBtns) do
      if k == key then btn:LockHighlight() else btn:UnlockHighlight() end
    end
  end
end

local function BlessingOptionLabel(option)
  if option.key ~= "DEFAULT" then return option.name end
  if option.name then return string.format(L["Default (%s)"], option.name) end
  return L["Default blessing"]
end

local function MakeBlessingSelector(parent, class, label)
  local function choose(key)
    if X.SetBlessingPreference(class, key) then RefreshConfig(); Refresh() end
  end
  local function value()
    local current = X.BlessingPreference(class)
    for _, option in ipairs(X.BlessingOptions(class)) do
      if option.key == current then return BlessingOptionLabel(option) end
    end
    return L["Previously selected blessing unavailable"]
  end
  local function adjust(delta)
    local current = X.BlessingPreference(class)
    local options = X.BlessingOptions(class)
    if #options == 0 then return end
    local index = delta > 0 and 0 or 1
    for i, option in ipairs(options) do
      if option.key == current then index = i; break end
    end
    choose(options[(index - 1 + delta) % #options + 1].key)
  end
  local ok, dd = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  if ok and dd and dd.SetupMenu then
    dd:SetWidth(290)
    dd:SetupMenu(function(_, root)
      for _, option in ipairs(X.BlessingOptions(class)) do
        root:CreateRadio(BlessingOptionLabel(option),
          function(key) return X.BlessingPreference(class) == key end, choose, option.key)
      end
    end)
    dd.Update = function(self)
      if self.SetDefaultText then self:SetDefaultText(L["Previously selected blessing unavailable"]) end
      if self.GenerateMenu then self:GenerateMenu() end
    end
    K.Register(dd, parent, label, "choice", value, adjust)
    return dd
  end
  local button = MakeButton(parent, "", 290, function() adjust(1) end)
  button.Update = function(self) self:SetText(value()) end
  K.Register(button, parent, label, "choice", value, adjust)
  return button
end

local function OpenBlessingPanel()
  if not cfg.blessingPanel then
    local panel = X.PanelWidget("Frame", "BuffRadarBlessingPreferences", cfg,
                              BackdropTemplateMixin and "BackdropTemplate" or nil)
    panel.searchTab = "buffs"
    panel.searchOpen = function() panel:Show() end
    cfg.blessingPanel, cfg.blessingSelectors = panel, {}
    panel:SetPoint("CENTER", cfg, "CENTER")
    panel:SetSize(490, 392)
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel((cfg:GetFrameLevel() or 0) + 10)
    panel:EnableMouse(true)
    if panel.SetBackdrop then
      panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
      })
      panel:SetBackdropColor(0.05, 0.06, 0.1, 0.98)
    end
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -18)
    title:SetText(L["Blessings by class"])
    local close = X.PanelWidget("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() panel:Hide() end)
    K.Register(close, panel, L["Close"], "button")
    for i, class in ipairs(X.BLESSING_CLASS_ORDER) do
      local y = -52 - (i - 1) * 30
      local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      label:SetPoint("TOPLEFT", 22, y - 5)
      local classNames = _G.LOCALIZED_CLASS_NAMES_MALE
      label:SetText((classNames and classNames[class]) or class)
      local selector = MakeBlessingSelector(panel, class, label:GetText())
      selector:SetPoint("TOPLEFT", 158, y)
      cfg.blessingSelectors[i] = selector
    end
    panel.complement = MakeCheck(panel, L["Complement Nearby Blessings"],
      function() return db.blessingComplement end, X.SetBlessingComplement)
    panel.complement:SetPoint("TOPLEFT", 18, -321)
    Tip(panel.complement, L["Complement Nearby Blessings"],
      L["Offer a different known blessing outside your group if another Paladin already provides your preferred blessing. Explicit rules still take precedence."])
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 22, -355)
    hint:SetWidth(442)
    hint:SetJustifyH("LEFT")
    hint:SetText(L["An active group blessing plan takes precedence."])
    if UISpecialFrames then table.insert(UISpecialFrames, "BuffRadarBlessingPreferences") end
  end
  CloseSearch()
  cfg.blessingPanel:Show()
  RefreshConfig()
end

local AssignmentUI = {
  labels = { ALL = L["All Roles"], WORLD = L["World"], TANK = L["Tank"],
    HEALER = L["Heal"], DAMAGER = L["DPS"] },
}

function AssignmentUI.CellLabel(class, slot)
  local names = _G.LOCALIZED_CLASS_NAMES_MALE
  return (names and names[class] or class) .. ", " .. AssignmentUI.labels[slot]
end

function AssignmentUI.CellText(class, slot, options)
  local rule = X.GetAssignment(class, slot)
  if rule == nil then return L["Default"] end
  if rule == false then return L["None"] end
  local names, known = {}, {}
  local count = 0
  for _, option in ipairs(options) do
    if rule[option.key] then names[#names + 1] = option.name end
    known[option.key] = true
  end
  local unavailable = 0
  for key in pairs(rule) do
    count = count + 1
    if not known[key] then unavailable = unavailable + 1 end
  end
  if unavailable > 0 then names[#names + 1] = string.format(L["%d unavailable"], unavailable) end
  return string.format(L["%d selected"], count), table.concat(names, ", ")
end

function AssignmentUI.Update()
  local panel = cfg.assignmentPanel
  if not panel or not panel:IsShown() then return end
  panel.enabled:Update()
  local options = X.AssignmentOptions()
  for class, row in pairs(panel.cells) do
    for slot, button in pairs(row) do
      local count, descriptions = AssignmentUI.CellText(class, slot, options)
      button:SetText(count)
      button.assignmentText = descriptions or count
    end
  end
  local picker = panel.picker
  if not picker:IsShown() then return end
  local rule = picker.draft
  if not picker.action then rule = X.GetAssignment(picker.class, picker.slot) end
  picker.state:SetText(rule == nil and L["Default"] or rule == false and L["None"] or L["Custom"])
  picker.noSpells:SetShown(#options == 0)
  for index, button in ipairs(picker.options) do
    local option = options[index]
    button.option = option
    if option then
      button.label:SetText(option.name)
      button:SetChecked(type(rule) == "table" and rule[option.key] == true)
      button.icon:SetTexture(option.icon)
      button.icon:SetShown(option.icon ~= nil)
      button:FitLabel()
    end
    button:SetShown(option ~= nil)
  end
end

function AssignmentUI.Save(picker, value)
  if InCombatLockdown() or X.PlayerSuspended() then return false end
  if picker.action then
    picker.draft = value
    AssignmentUI.Update()
    return false
  end
  if X.SetAssignment(picker.class, picker.slot, value) then
    AssignmentUI.Update()
    Refresh()
    return true
  end
  AssignmentUI.Update()
  return false
end

function AssignmentUI.ToggleOption(picker, key, checked)
  local current = picker.draft
  if not picker.action then current = X.GetAssignment(picker.class, picker.slot) end
  local nextRule = {}
  if type(current) == "table" then
    for selected in pairs(current) do nextRule[selected] = true end
  end
  if checked and key:match("^BLESS_") then
    for selected in pairs(nextRule) do
      if selected:match("^BLESS_") then nextRule[selected] = nil end
    end
  elseif checked and key == "DAMPEN_MAGIC" then nextRule.AMPLIFY_MAGIC = nil
  elseif checked and key == "AMPLIFY_MAGIC" then nextRule.DAMPEN_MAGIC = nil end
  nextRule[key] = checked and true or nil
  if next(nextRule) then AssignmentUI.Save(picker, nextRule)
  else AssignmentUI.Save(picker, false) end
end

function AssignmentUI.CreatePanel(parent, name, width, height, level)
  local panel = CreateFrame("Frame", name, parent)
  -- Modal children are searchable only with an explicit, context-free opener.
  -- Drafts, member pickers and review actions must keep their selected context.
  panel.searchBoundary = true
  panel:SetSize(width, height)
  panel:SetPoint("CENTER")
  panel:SetFrameLevel(level)
  panel:EnableMouse(true)
  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(panel)
  bg:SetColorTexture(0.06, 0.065, 0.095, 1)
  panel:Hide()
  return panel
end

function AssignmentUI.CloseButton(panel, onClose)
  local close = X.PanelWidget("Button", nil, panel, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)
  close:SetScript("OnClick", onClose)
  K.Register(close, panel, L["Close"], "button")
  return close
end

function AssignmentUI.BuildPicker(panel)
  local picker = AssignmentUI.CreatePanel(panel, "BuffRadarAssignmentPicker", 574, 405, panel:GetFrameLevel() + 5)
  picker.title = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  picker.title:SetPoint("TOPLEFT", 16, -14)
  picker.title:SetPoint("TOPRIGHT", -45, -14)
  picker.title:SetJustifyH("LEFT")
  picker.closeButton = AssignmentUI.CloseButton(picker, function() AssignmentUI.CancelEdit(picker, picker.blockers) end)
  if picker.SetPropagateKeyboardInput then
    picker:EnableKeyboard(true)
    picker:HookScript("OnShow", function(self) self:SetPropagateKeyboardInput(true) end)
    picker:SetScript("OnKeyDown", function(self, key)
      if key == "ESCAPE" and not K.active and K.Modal() == self
        and not InCombatLockdown() and not X.PlayerSuspended() then
        self:SetPropagateKeyboardInput(false)
        self.closeButton:Click()
      end
    end)
  end
  picker.state = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  picker.state:SetPoint("TOPLEFT", 16, -40)
  picker.hint = picker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  picker.hint:SetPoint("TOPLEFT", 16, -63)
  picker.hint:SetPoint("TOPRIGHT", -16, -63)
  picker.hint:SetJustifyH("LEFT")
  picker.noSpells = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  picker.noSpells:SetPoint("TOPLEFT", 16, -112)
  picker.noSpells:SetText(L["No known targeted buffs."])
  picker.options = {}
  for i = 1, 18 do
    local button
    button = MakeCheck(picker, "", function() return false end, function(checked)
      if button.option then AssignmentUI.ToggleOption(picker, button.option.key, checked) end
    end)
    button:SetPoint("TOPLEFT", i % 2 == 1 and 12 or 290, -91 - math_floor((i - 1) / 2) * 27)
    button.label:SetJustifyH("LEFT")
    button.label:SetWordWrap(false)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(16, 16)
    button.icon:SetPoint("LEFT", button, "RIGHT", 4, 0)
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", button, "RIGHT", 24, 1)
    button.label.maxWidth = 220
    button.label:SetWidth(220)
    function button:FitLabel()
      self:SetHitRectInsets(0, -(24 + math_min(self.label.maxWidth, self.label:GetStringWidth())), 0, 0)
    end
    Tip(button, function() return button.label:GetText() end)
    picker.options[i] = button
  end
  picker.defaultButton = MakeButton(picker, L["Default"], 112, function()
    if AssignmentUI.Save(picker, nil) then picker:Hide() end
  end)
  picker.defaultButton:SetPoint("BOTTOMLEFT", 16, 12)
  Tip(picker.defaultButton, L["Default"], L["Inherit from All Roles or the built-in rules."])
  picker.noneButton = MakeButton(picker, L["None"], 112, function()
    if AssignmentUI.Save(picker, false) then picker:Hide() end
  end)
  picker.noneButton:SetPoint("LEFT", picker.defaultButton, "RIGHT", 8, 0)
  Tip(picker.noneButton, L["None"], L["Offer no assigned buffs for this cell."])
  picker.backButton = MakeButton(picker, L["Cancel"], 100, function()
    AssignmentUI.CancelEdit(picker, picker.blockers)
  end)
  picker.backButton:SetPoint("BOTTOMRIGHT", -16, 12)
  picker.reviewButton = MakeButton(picker, L["Review Changes"], 182, function()
    AssignmentUI.OpenReview(picker, picker.blockers)
  end)
  picker.reviewButton:SetPoint("RIGHT", picker.backButton, "LEFT", -8, 0)
  return picker
end

function AssignmentUI.OpenPicker(panel, class, slot, blockers, action)
  if InCombatLockdown() or X.PlayerSuspended() then return end
  local picker = panel.picker
  picker.class, picker.slot = class, slot
  picker.blockers, picker.action = blockers, action
  if action then picker.draft = X.GetAssignment(class, slot) end
  picker.backButton:SetText(L[blockers and "Cancel" or "Done"])
  picker.reviewButton:SetShown(blockers ~= nil)
  picker.hint:SetText(L[blockers and "Edit the draft, then review the changes before applying."
    or "Select spells for this cell. Changes apply immediately."])
  picker:SetFrameLevel(blockers and blockers:GetFrameLevel() + 5 or panel:GetFrameLevel() + 5)
  picker.closeButton:SetFrameLevel(picker:GetFrameLevel() + 1)
  panel.closeButton:Hide()
  picker.title:SetText(AssignmentUI.CellLabel(class, slot))
  picker:Show()
  AssignmentUI.Update()
  if K.active and not K.edit then K.Move(1) end
end

function AssignmentUI.UpdateBlockers(panel)
  local lines = panel.member.groupDetails
  local pages = math.max(1, math.ceil(#lines / #panel.rows))
  panel.page = math_min(pages, math.max(1, panel.page))
  local first = (panel.page - 1) * #panel.rows + 1
  panel.previous:SetShown(panel.page > 1)
  panel.next:SetShown(panel.page < pages)
  for i, row in ipairs(panel.rows) do
    local index = first + i - 1
    local line = lines[index]
    row.action = panel.member.groupActions and panel.member.groupActions[index]
    row.text:SetText(line or "")
    row.text:SetPoint("TOPRIGHT", row.action and -111 or 0, 0)
    row.edit:SetShown(row.action ~= nil)
    row:SetShown(line ~= nil)
  end
end

function AssignmentUI.FindPreviewMember(members, identity)
  if not identity then return nil end
  for _, member in ipairs(members) do
    if member.identity == identity then return member end
  end
end

function AssignmentUI.CheckBlocker(panel, action)
  if not panel or not panel:IsVisible() or not panel.member then return false end
  local member = AssignmentUI.FindPreviewMember(X.AssignmentPreview(), panel.member.identity)
  for _, candidate in pairs(member and member.groupActions or {}) do
    if candidate.kind == action.kind and candidate.guid == action.guid and candidate.class == action.class
      and candidate.slot == action.slot then return true end
  end
  Print(L["The blocker changed. Check the updated list."])
  AssignmentUI.RefreshPreview(panel.preview, panel)
  return false
end

function AssignmentUI.CancelEdit(editor, blockers)
  if not editor then return end
  editor:Hide()
  if blockers and blockers:IsVisible() then AssignmentUI.RefreshPreview(blockers.preview, blockers) end
end

function AssignmentUI.UpdateReview(panel)
  local lastPage = math.max(1, math.ceil(#panel.lines / #panel.rows))
  panel.page = math_min(lastPage, math.max(1, panel.page))
  panel.previous:SetShown(panel.page > 1)
  panel.next:SetShown(panel.page < lastPage)
  local start = (panel.page - 1) * #panel.rows
  panel.count:SetText(lastPage > 1 and string.format(L["Rows %d–%d of %d"], start + 1,
    math_min(start + #panel.rows, #panel.lines), #panel.lines) or "")
  for index, widget in ipairs(panel.rows) do
    local line = panel.lines[start + index]
    widget.heading:SetText(line and line.name or "")
    widget.detail:SetText(line and line.detail or "")
    widget:SetShown(line ~= nil)
  end
end

function AssignmentUI.ShowReview(panel, review, changed)
  panel.snapshot, panel.page, panel.lines = review, 1, {}
  local message = changed and L["The group or rules changed. Review again before applying."]
    or L["Review the changes before applying to the current group."]
  if panel.practice then message = L["Practice with sample players. Your group and settings are unaffected."] end
  if review.incomplete then message = message .. "\n" .. L["Some group members could not be checked."] end
  panel.notice:SetText(message)
  if #review.rows == 0 then
    panel.lines[1] = { name = L["No changes to group buff offers."], detail = "" }
  end
  for _, member in ipairs(review.rows) do
    local function add(names, pattern)
      -- Large edits stay readable even when translated spell names wrap.
      for index = 1, #names, 3 do
        local detail = table.concat(names, ", ", index, math_min(index + 2, #names))
        panel.lines[#panel.lines + 1] = { name = member.name, detail = string.format(pattern, detail) }
      end
    end
    add(member.gains, L["Gains: %s"])
    add(member.losses, L["Loses: %s"])
  end
  if review.incomplete then panel.apply:Disable() else panel.apply:Enable() end
  AssignmentUI.UpdateReview(panel)
  panel:Show()
  if K.active and not K.edit then K.Focus(panel.header.navigation) end
end

function AssignmentUI.BuildReview(blockers, practice)
  local name = practice and "BuffRadarPracticeReview" or "BuffRadarBlockerReview"
  local panel = AssignmentUI.CreatePanel(blockers, name, 574, 405, blockers:GetFrameLevel() + 10)
  panel.practice = practice
  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -14)
  title:SetText(L["Review Changes"])
  local function cancel()
    if practice then
      panel:Hide()
      practice.setDraft(nil)
      if K.active and not K.edit then K.Move(1) end
    else
      AssignmentUI.CancelEdit(panel.editor, blockers)
    end
  end
  AssignmentUI.CloseButton(panel, cancel)
  local header = CreateFrame("Button", nil, panel)
  panel.header = header
  header:SetSize(542, 52)
  header:SetPoint("TOPLEFT", 16, -42)
  panel.notice = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.notice:SetPoint("TOPLEFT")
  panel.notice:SetPoint("TOPRIGHT")
  panel.notice:SetJustifyH("LEFT")
  panel.notice:SetWordWrap(true)
  panel.count = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  panel.count:SetPoint("BOTTOMLEFT", 0, 3)
  K.Register(header, panel, L["Review Changes"], "detail", function()
    local count = panel.count:GetText()
    return panel.notice:GetText() .. (count and count ~= "" and ", " .. count or "")
  end)
  panel.rows = {}
  for index = 1, 5 do
    local row = CreateFrame("Button", nil, panel)
    row:SetSize(542, 49)
    row:SetPoint("TOPLEFT", 16, -96 - (index - 1) * 51)
    row.heading = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.heading:SetPoint("TOPLEFT")
    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.detail:SetPoint("TOPLEFT", 0, -17)
    row.detail:SetPoint("TOPRIGHT", 0, -17)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(true)
    K.Register(row, panel, function() return row.heading:GetText() end, "detail", function() return row.detail:GetText() end)
    panel.rows[index] = row
  end
  local function move(delta)
    panel.page = panel.page + delta
    AssignmentUI.UpdateReview(panel)
    if K.active and not K.edit then K.Focus(panel.rows[1].navigation) end
  end
  panel:EnableMouseWheel(true)
  panel:SetScript("OnMouseWheel", function(_, delta) move(delta > 0 and -1 or 1) end)
  panel.previous = MakeButton(panel, L["Previous"], 98, function() move(-1) end)
  panel.previous:SetPoint("BOTTOMLEFT", 16, 12)
  panel.next = MakeButton(panel, L["Next"], 80, function() move(1) end)
  panel.next:SetPoint("BOTTOMLEFT", 122, 12)
  panel.cancel = MakeButton(panel, L["Cancel"], 100, cancel)
  panel.cancel:SetPoint("BOTTOMRIGHT", -16, 12)
  panel.apply = MakeButton(panel, L["Apply"], 100, function()
    if not panel:IsVisible() or not panel.snapshot or panel.snapshot.incomplete
      or InCombatLockdown() or X.PlayerSuspended() then return end
    if practice then
      practice.applied[practice.draft] = true
      panel:Hide()
      practice.setDraft(nil)
      practice.notice:SetText(L["Practice changes applied to the sample raid."])
      if K.active and not K.edit then K.Move(1) end
      return
    end
    local editor = panel.editor
    if not editor then return end
    local applied, fresh = X.ApplyBlockerEdit(editor.action, editor.draft, panel.snapshot)
    if fresh then
      AssignmentUI.ShowReview(panel, fresh, true)
    else
      editor:Hide()
      if applied then
        AssignmentUI.Update()
        Refresh()
      else
        Print(L["The blocker changed. Check the updated list."])
      end
      AssignmentUI.RefreshPreview(blockers.preview, blockers)
    end
  end)
  panel.apply:SetPoint("RIGHT", panel.cancel, "LEFT", -8, 0)
  panel.back = MakeButton(panel, L["Back"], 100, function() panel:Hide() end)
  panel.back:SetPoint("RIGHT", panel.apply, "LEFT", -8, 0)
  panel:HookScript("OnHide", function()
    local editor = panel.editor
    panel.snapshot, panel.editor, panel.lines = nil, nil, nil
    if K.active and not K.edit and editor and editor:IsVisible() then K.Focus(editor.reviewButton.navigation) end
    if K.active and not K.edit and practice and practice:IsVisible() then K.Focus(practice.reviewButton.navigation) end
  end)
  if UISpecialFrames then table.insert(UISpecialFrames, name) end
  return panel
end

function AssignmentUI.BuildPractice(parent)
  local panel = AssignmentUI.CreatePanel(parent, "BuffRadarPractice", 574, 405, parent:GetFrameLevel() + 5)
  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -14)
  title:SetText(L["Practice Mode"] .. " · " .. L["Sample Raid"])
  AssignmentUI.CloseButton(panel, function() panel:Hide() end)
  panel.notice = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.notice:SetPoint("TOPLEFT", 16, -42)
  panel.notice:SetPoint("TOPRIGHT", -16, -42)
  panel.notice:SetJustifyH("LEFT")
  local samples = {
    { label = L["Mira · Inherited All Roles rule"], name = "Mira", choice = L["Offer Fortitude to the sample group"],
      gains = { L["Power Word: Fortitude"] }, losses = {} },
    { label = L["Thoren · Individual blessing exception"], name = "Thoren", choice = L["Clear Thoren's blessing exception"],
      gains = { L["Blessing of Kings"] }, losses = { L["Blessing of Wisdom"] } },
    { label = L["Arden · Buff data unavailable"] },
  }
  panel.edits = {}
  for i, sample in ipairs(samples) do
    local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", 16, -82 - (i - 1) * 44)
    label:SetText(sample.label)
    if sample.choice then
      local edit = MakeButton(panel, L["Edit Rule"], 145, function() panel.setDraft(i) end)
      edit:SetPoint("TOPRIGHT", -16, -76 - (i - 1) * 44)
      edit.navigation.value = function() return sample.label end
      panel.edits[i] = edit
    end
  end
  panel.choice = MakeCheck(panel, "", function() return panel.chosen end, function(value)
    panel.chosen = value
    if value then panel.reviewButton:Enable() else panel.reviewButton:Disable() end
  end)
  panel.choice:SetPoint("TOPLEFT", 16, -242)
  panel.reviewButton = MakeButton(panel, L["Review Changes"], 182, function()
    if InCombatLockdown() or X.PlayerSuspended() or not panel.draft or not panel.chosen then return end
    local sample = samples[panel.draft]
    local rows = {}
    if not panel.applied[panel.draft] then rows[1] = { name = sample.name, gains = sample.gains, losses = sample.losses } end
    panel.review = panel.review or AssignmentUI.BuildReview(panel, panel)
    AssignmentUI.ShowReview(panel.review, { rows = rows })
  end)
  panel.reviewButton:SetPoint("BOTTOMRIGHT", -16, 12)
  panel.setDraft = function(selected)
    panel.draft, panel.chosen = selected, false
    panel.choice:SetShown(selected ~= nil)
    panel.reviewButton:SetShown(selected ~= nil)
    panel.reviewButton:Disable()
    if selected then
      panel.choice.label:SetText(samples[selected].choice)
      panel.choice:FitLabel()
      panel.choice:SetChecked(false)
      if K.active and not K.edit then K.Focus(panel.choice.navigation) end
    end
  end
  panel:HookScript("OnHide", function()
    if panel.review then panel.review:Hide() end
    panel.draft, panel.chosen, panel.applied = nil, nil, nil
    if K.active and not K.edit and parent:IsVisible() then K.Move(1) end
  end)
  if UISpecialFrames then table.insert(UISpecialFrames, "BuffRadarPractice") end
  return panel
end

function X.OpenPractice()
  if not CLASSIC_FEATURES or X.PlayerSuspended() or InCombatLockdown() then return end
  X.OpenAssignments()
  local parent = cfg.assignmentPanel
  parent.picker:Hide()
  if parent.subgroup then parent.subgroup:Hide() end
  if parent.coordination then parent.coordination:Hide() end
  if parent.preparation then parent.preparation:Hide() end
  if parent.preview then parent.preview:Hide() end
  if parent.coverage then parent.coverage:Hide() end
  local practice = parent.practice or AssignmentUI.BuildPractice(parent)
  parent.practice = practice
  practice.applied = practice.applied or {}
  practice.notice:SetText(L["Practice with sample players. Your group and settings are unaffected."])
  practice.setDraft(nil)
  practice:Show()
  if K.active and not K.edit then K.Move(1) end
end

function X.RunBlockerUndo()
  if not CLASSIC_FEATURES or X.PlayerSuspended() or InCombatLockdown() then return end
  local applied, message = X.UndoBlockerEdit()
  if message then Print(L[message]) end
  if applied then
    AssignmentUI.Update()
    Refresh()
    local preview = cfg and cfg.assignmentPanel and cfg.assignmentPanel.preview
    if preview and preview:IsVisible() then AssignmentUI.RefreshPreview(preview, preview.blockers) end
  end
end

function AssignmentUI.OpenReview(editor, blockers)
  local action = editor.action
  if not action or not editor:IsVisible() or InCombatLockdown() or X.PlayerSuspended() then return end
  if not AssignmentUI.CheckBlocker(blockers, action) then editor:Hide(); return end
  local review = X.ReviewBlockerEdit(action, editor.draft)
  if not review then
    Print(L["The blocker changed. Check the updated list."])
    AssignmentUI.CancelEdit(editor, blockers)
    return
  end
  blockers.review = blockers.review or AssignmentUI.BuildReview(blockers)
  blockers.review.editor = editor
  AssignmentUI.ShowReview(blockers.review, review)
end

function AssignmentUI.OpenExceptionEditor(panel, action)
  local state = X.GetBlessingExceptionForGUID(action.guid)
  if not state then return end
  local editor = panel.exceptionEditor
  if not editor then
    editor = AssignmentUI.CreatePanel(panel, "BuffRadarBlockerExceptionEditor", 574, 405, panel:GetFrameLevel() + 5)
    panel.exceptionEditor = editor
    editor.title = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    editor.title:SetPoint("TOPLEFT", 16, -14)
    editor.title:SetPoint("TOPRIGHT", -45, -14)
    editor.title:SetJustifyH("LEFT")
    AssignmentUI.CloseButton(editor, function() AssignmentUI.CancelEdit(editor, panel) end)
    editor.selection = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    editor.selection:SetPoint("TOPLEFT", 16, -45)
    local function stage(key)
      if InCombatLockdown() or X.PlayerSuspended() or not editor:IsVisible() then return end
      editor.draft = key
      local name = L["Default"]
      for _, button in ipairs(editor.choices) do
        if button.option and button.option.key == key then name = button.option.name; break end
      end
      if key ~= "DEFAULT" and name == L["Default"] then name = L["Previously selected blessing unavailable"] end
      editor.selection:SetText(L["Current selection"] .. " · " .. name)
      if K.active and not K.edit then K.Focus(K.current) end
    end
    editor.stage = stage
    editor.choices = {}
    for index = 1, #X.BLESSING_KEYS do
      local button = MakeButton(editor, "", 260, function(widget)
        if widget.option then stage(widget.option.key) end
      end)
      button:SetPoint("TOPLEFT", 16, -73 - (index - 1) * 34)
      K.Register(button, editor, function() return button:GetText() end, "button", function()
        if editor.action and button.option and editor.draft == button.option.key then return L["Current selection"] end
      end)
      editor.choices[index] = button
    end
    editor.defaultButton = MakeButton(editor, L["Default"], 112, function() stage("DEFAULT") end)
    editor.defaultButton:SetPoint("BOTTOMLEFT", 16, 12)
    local cancel = MakeButton(editor, L["Cancel"], 100, function() AssignmentUI.CancelEdit(editor, panel) end)
    cancel:SetPoint("BOTTOMRIGHT", -16, 12)
    editor.reviewButton = MakeButton(editor, L["Review Changes"], 182, function() AssignmentUI.OpenReview(editor, panel) end)
    editor.reviewButton:SetPoint("RIGHT", cancel, "LEFT", -8, 0)
    editor:HookScript("OnHide", function()
      editor.action, editor.draft = nil, nil
      if panel.review then panel.review:Hide() end
      if K.active and not K.edit and panel:IsVisible() then K.Move(1) end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, "BuffRadarBlockerExceptionEditor") end
  end
  editor.title:SetText(L["Edit Blessing Exception"] .. " · " .. state.name)
  editor.action = action
  for index, button in ipairs(editor.choices) do
    local option = state.canSet and state.options[index]
    button.option = option
    if option then button:SetText(option.name) end
    button:SetShown(option and true or false)
  end
  editor:Show()
  if K.active and not K.edit then K.Move(1) end
  editor.stage(state.key or "DEFAULT")
end

function AssignmentUI.OpenBlockers(preview, member)
  if InCombatLockdown() or X.PlayerSuspended() or not member or not member.groupDetails or #member.groupDetails == 0 then return end
  local panel = preview.blockers
  if not panel then
    panel = AssignmentUI.CreatePanel(preview, "BuffRadarAssignmentBlockers", 574, 405, preview:GetFrameLevel() + 5)
    preview.blockers = panel
    panel.preview = preview
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText(L["Group Cast Blockers"])
    AssignmentUI.CloseButton(panel, function() panel:Hide() end)
    panel.rows = {}
    local function move(delta)
      panel.page = panel.page + delta
      AssignmentUI.UpdateBlockers(panel)
      if K.active and not K.edit and not K.InScope(K.current) then K.Move(1) end
    end
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta) move(delta > 0 and -1 or 1) end)
    for i = 1, 6 do
      local row = CreateFrame("Button", nil, panel)
      row:SetSize(542, 50)
      row:SetPoint("TOPLEFT", 16, -45 - (i - 1) * 53)
      row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      row.text:SetPoint("TOPLEFT")
      row.text:SetPoint("TOPRIGHT")
      row.text:SetJustifyH("LEFT")
      row.text:SetWordWrap(true)
      K.Register(row, panel, function() return row.text:GetText() end, "detail")
      row.edit = MakeButton(row, "", 105, function()
        local action = row.action
        if not action or InCombatLockdown() or X.PlayerSuspended() or not AssignmentUI.CheckBlocker(panel, action) then return end
        if action.kind == "rule" then
          AssignmentUI.OpenPicker(cfg.assignmentPanel, action.class, action.slot, panel, action)
        elseif action.kind == "exception" then
          AssignmentUI.OpenExceptionEditor(panel, action)
        end
      end)
      row.edit:SetText(L["Edit Rule"])
      row.edit:SetPoint("TOPRIGHT")
      K.Register(row.edit, panel, L["Edit Rule"], "button", function() return row.text:GetText() end)
      panel.rows[i] = row
    end
    panel.previous = MakeButton(panel, L["Previous"], 110, function() move(-1) end)
    panel.previous:SetPoint("BOTTOMLEFT", 16, 12)
    panel.next = MakeButton(panel, L["Next"], 110, function() move(1) end)
    panel.next:SetPoint("LEFT", panel.previous, "RIGHT", 8, 0)
    panel:HookScript("OnHide", function()
      local sourceRow = panel.sourceRow
      local identity = panel.member and panel.member.identity
      local picker = cfg.assignmentPanel.picker
      if picker.blockers == panel then picker:Hide() end
      if panel.exceptionEditor then panel.exceptionEditor:Hide() end
      if panel.review then panel.review:Hide() end
      panel.member, panel.sourceRow = nil, nil
      if K.active and not K.edit and preview:IsVisible() then
        local entry = sourceRow and sourceRow.member and sourceRow.member.identity == identity and sourceRow.navigation
        K.Focus(K.InScope(entry) and entry or preview.refresh.navigation)
      end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, "BuffRadarAssignmentBlockers") end
  end
  panel.member, panel.page = member, 1
  AssignmentUI.UpdateBlockers(panel)
  panel:Show()
  if K.active and not K.edit then K.Move(1) end
end

function AssignmentUI.UpdatePreview(preview, editorClosed)
  local members = preview.members
  local focusChanged = editorClosed
  local pages = math.max(1, math.ceil(#members / #preview.rows))
  preview.page = math_min(pages, math.max(1, preview.page))
  local first = (preview.page - 1) * #preview.rows + 1
  local last = math_min(#members, first + #preview.rows - 1)
  preview.count:SetText(#members == 0 and L["No group to preview."]
    or string.format(L["Members %d–%d of %d"], first, last, #members))
  preview.previous:SetShown(preview.page > 1)
  preview.next:SetShown(preview.page < pages)
  for index, row in ipairs(preview.rows) do
    local member = members[first + index - 1]
    if K.current == row.navigation or K.current == row.roleButton.navigation then
      local previous = row.member
      local identity = previous and previous.identity
      focusChanged = previous ~= member and not (identity and member and identity == member.identity)
    end
    row.member = member
    if member then
      local parts = {}
      if member.evaluated and (#member.buffs > 0 or not member.unknown) then
        parts[#parts + 1] = #member.buffs > 0
          and string.format(L["Due: %s"], table.concat(member.buffs, ", ")) or L["No buffs due"]
        parts[#parts + 1] = #member.available > 0
          and string.format(L["Available: %s"], table.concat(member.available, ", ")) or L["No buffs available"]
      end
      if member.status then parts[#parts + 1] = member.status end
      if member.group then parts[#parts + 1] = member.group end
      row.name = member.name
      row.heading:SetText(member.name .. " · " .. member.rule)
      local action = member.groupDetails and #member.groupDetails > 0
      row.description = member.rule .. "\n" .. table.concat(parts, "\n")
        .. (action and "\n" .. L["Group Cast Blockers"] or "")
      row.detail:SetText(table.concat(parts, " · "))
      if member.roleEditable then
        row.roleButton:SetText(member.roleOverride and L["Change Role"] or L["Set Role"])
      end
    end
    row.roleButton:SetShown(member ~= nil and member.roleEditable == true)
    row.heading:SetPoint("TOPRIGHT", member and member.roleEditable and -132 or -3, -3)
    row.detail:SetPoint("TOPRIGHT", member and member.roleEditable and -132 or -3, -20)
    row:SetShown(member ~= nil)
  end
  if K.active and not K.edit then
    if focusChanged then K.Focus(preview.refresh.navigation)
    elseif K.InScope(K.current) then K.Focus(K.current)
    else K.Move(1) end
  end
end

function AssignmentUI.RefreshPreview(preview, preserveBlockers, fromRoster)
  if InCombatLockdown() or X.PlayerSuspended() or not preview:IsVisible() then return end
  preview.pendingRefresh = nil
  preview.members = X.AssignmentPreview()
  local blockers = preview.blockers
  local blockMember
  local picker = cfg.assignmentPanel.picker
  local editingBlocker = blockers and (picker.blockers == blockers and picker:IsVisible()
    or blockers.exceptionEditor and blockers.exceptionEditor:IsVisible())
  if blockers and blockers:IsShown() then
    if (blockers == preserveBlockers or fromRoster and editingBlocker) and blockers.member then
      blockMember = AssignmentUI.FindPreviewMember(preview.members, blockers.member.identity)
    end
    if blockMember and blockMember.groupDetails and #blockMember.groupDetails > 0 then
      blockers.member = blockMember
      AssignmentUI.UpdateBlockers(blockers)
    elseif not (fromRoster and editingBlocker) then
      if blockMember then Print(L["No group cast blockers are currently listed."]) end
      blockers:Hide()
    end
  end
  local editor = preview.roleEditor
  local editorClosed
  if editor and editor:IsVisible() then
    local guid = editor.member and editor.member.guid
    local match
    for _, member in ipairs(preview.members) do
      if guid and member.guid == guid and member.roleEditable then match = member; break end
    end
    if match then
      AssignmentUI.OpenRoleEditor(preview, match)
    else
      editorClosed = true
      editor:Hide()
    end
  end
  AssignmentUI.UpdatePreview(preview, editorClosed)
end

function X.QueueAssignmentPreviewRefresh(preparationOnly)
  local panel = cfg and cfg.assignmentPanel
  local preview = panel and panel.preview
  local coverage = panel and panel.coverage
  local subgroup = panel and panel.subgroup
  local preparation = panel and panel.preparation
  if preparation and not preparation:IsVisible() then preparation = nil end
  if preparationOnly and not preparation then return end
  if coverage and not coverage:IsVisible() then coverage = nil end
  if preview and not preview:IsVisible() then preview = nil end
  if subgroup and not subgroup:IsVisible() then subgroup = nil end
  if not (preparation or preview or coverage or subgroup) or InCombatLockdown() or X.PlayerSuspended() then return end
  local visible = preparation or subgroup or coverage or preview
  if visible.pendingRefresh then return end
  local function refresh()
    if preparation then AssignmentUI.RefreshPreparation(preparation, true)
    elseif subgroup then AssignmentUI.RefreshSubgroup(subgroup)
    elseif coverage then AssignmentUI.RefreshCoverage(coverage)
    else AssignmentUI.RefreshPreview(preview, nil, true) end
  end
  if not C_Timer or not C_Timer.After then
    refresh()
    return
  end
  local request = {}
  visible.pendingRefresh = request
  C_Timer.After(0, function()
    if visible.pendingRefresh ~= request then return end
    visible.pendingRefresh = nil
    refresh()
  end)
end

function AssignmentUI.BuildRoleEditor(preview)
  local editor = AssignmentUI.CreatePanel(preview, "BuffRadarAssignmentRoleEditor", 574, 405,
    preview:GetFrameLevel() + 5)
  editor.title = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  editor.title:SetPoint("TOPLEFT", 16, -14)
  editor.title:SetPoint("TOPRIGHT", -45, -14)
  editor.title:SetJustifyH("LEFT")
  AssignmentUI.CloseButton(editor, function() editor:Hide() end)
  local hint = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  hint:SetPoint("TOPLEFT", 16, -62)
  hint:SetPoint("TOPRIGHT", -16, -62)
  hint:SetJustifyH("LEFT")
  hint:SetText(L["Choose a fallback when the game does not report a role."])
  editor.selection = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  editor.selection:SetPoint("TOPLEFT", 16, -91)
  local function choose(role)
    local member = editor.member
    if not editor:IsVisible() or not member or InCombatLockdown() or X.PlayerSuspended() then return end
    local changed = X.SetAssignmentRole(member.unit, member.guid, role)
    editor:Hide()
    if changed then
      Refresh()
    else
      Print(L["The member or role changed. Refresh and try again."])
    end
    AssignmentUI.RefreshPreview(preview)
  end
  editor.choices = {}
  for index, role in ipairs({ "TANK", "HEALER", "DAMAGER", "GAME" }) do
    local label = role == "GAME" and L["Use Game Role"] or AssignmentUI.labels[role]
    local button = MakeButton(editor, label, 220, function()
      if role == "GAME" then choose(nil) else choose(role) end
    end)
    button:SetPoint("TOPLEFT", 16, -119 - (index - 1) * 34)
    button.navigation.value = function()
      if editor.member and (editor.member.roleOverride or "GAME") == role then
        return L["Current selection"]
      end
    end
    editor.choices[role] = button
  end
  editor:HookScript("OnHide", function() editor.member = nil end)
  if UISpecialFrames then table.insert(UISpecialFrames, "BuffRadarAssignmentRoleEditor") end
  return editor
end

function AssignmentUI.OpenRoleEditor(preview, member)
  if not member or not member.roleEditable or InCombatLockdown() or X.PlayerSuspended() then return end
  preview.roleEditor = preview.roleEditor or AssignmentUI.BuildRoleEditor(preview)
  local editor = preview.roleEditor
  editor.member = member
  editor.title:SetText(string.format(L["Session Role for %s"], member.name))
  local label = AssignmentUI.labels[member.roleOverride] or L["Use Game Role"]
  editor.selection:SetText(L["Current selection"] .. " · " .. label)
  for role, button in pairs(editor.choices) do
    button:SetShown(role == "GAME" and member.roleOverride ~= nil or role ~= "GAME" and member.roleCanSet == true)
  end
  editor:Show()
end

function AssignmentUI.BuildPreview(panel)
  local preview = AssignmentUI.CreatePanel(panel, "BuffRadarAssignmentPreview", 574, 405, panel:GetFrameLevel() + 5)
  preview.page, preview.members, preview.rows = 1, {}, {}
  local title = preview:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -14)
  title:SetPoint("TOPRIGHT", -45, -14)
  title:SetJustifyH("LEFT")
  title:SetText(L["Preview Current Group"])
  AssignmentUI.CloseButton(preview, function() preview:Hide() end)
  preview.count = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  preview.count:SetPoint("TOPLEFT", 16, -40)
  preview.count:SetPoint("TOPRIGHT", -204, -40)
  preview.count:SetJustifyH("LEFT")

  preview.refresh = MakeButton(preview, L["Refresh Preview"], 172, function() AssignmentUI.RefreshPreview(preview) end)
  preview.refresh:SetPoint("TOPRIGHT", -16, -35)
  local function move(delta)
    if not preview:IsVisible() then return end
    preview.page = preview.page + delta
    AssignmentUI.UpdatePreview(preview)
  end
  local function onWheel(_, delta) move(delta > 0 and -1 or 1) end
  preview:EnableMouseWheel(true)
  preview:SetScript("OnMouseWheel", onWheel)

  for index = 1, 7 do
    local row = CreateFrame("Button", nil, preview)
    row:SetSize(542, 39)
    row:SetPoint("TOPLEFT", 16, -65 - (index - 1) * 42)
    row:EnableMouse(true)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", onWheel)
    row:SetScript("OnClick", function()
      AssignmentUI.OpenBlockers(preview, row.member)
      if preview.blockers and preview.blockers:IsShown() then preview.blockers.sourceRow = row end
    end)
    row.heading = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.heading:SetPoint("TOPLEFT", 3, -3)
    row.heading:SetPoint("TOPRIGHT", -3, -3)
    row.heading:SetJustifyH("LEFT")
    row.heading:SetWordWrap(false)
    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.detail:SetPoint("TOPLEFT", 3, -20)
    row.detail:SetPoint("TOPRIGHT", -3, -20)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)
    row.roleButton = MakeButton(row, "", 126, function() AssignmentUI.OpenRoleEditor(preview, row.member) end)
    row.roleButton:SetPoint("RIGHT", -1, 0)
    K.Register(row.roleButton, preview,
      function() return row.roleButton:GetText() .. " · " .. row.name end, "button",
      function() return AssignmentUI.labels[row.member.roleOverride] end)
    local function name() return row.name end
    local function description() return row.description end
    K.Register(row, preview, name, "button", description)
    Tip(row, name, description)
    preview.rows[index] = row
  end
  preview.previous = MakeButton(preview, L["Previous"], 110, function() move(-1) end)
  preview.previous:SetPoint("BOTTOMLEFT", 16, 12)
  preview.next = MakeButton(preview, L["Next"], 110, function() move(1) end)
  preview.next:SetPoint("LEFT", preview.previous, "RIGHT", 8, 0)
  preview:HookScript("OnHide", function()
    if preview.roleEditor then preview.roleEditor:Hide() end
    if preview.blockers then preview.blockers:Hide() end
    preview.pendingRefresh, preview.members = nil, {}
    for _, row in ipairs(preview.rows) do row.member = nil end
    GameTooltip:Hide()
  end)
  if UISpecialFrames then table.insert(UISpecialFrames, "BuffRadarAssignmentPreview") end
  return preview
end

function AssignmentUI.OpenPreview(panel)
  if InCombatLockdown() or X.PlayerSuspended() then return end
  panel.picker:Hide()
  if panel.subgroup then panel.subgroup:Hide() end
  if panel.coordination then panel.coordination:Hide() end
  if panel.preparation then panel.preparation:Hide() end
  if panel.coverage then panel.coverage:Hide() end
  panel.preview = panel.preview or AssignmentUI.BuildPreview(panel)
  panel.preview.page = 1
  panel.preview:Show()
  AssignmentUI.RefreshPreview(panel.preview)
end

function AssignmentUI.CoverageGroupLabel(raid, subgroup)
  if not raid then return L["Party"] end
  if not subgroup or subgroup == 0 then return L["Unknown Subgroup"] end
  return string.format(L["Raid Group %d"], subgroup)
end

function AssignmentUI.UpdateCoverage(view)
  if not view.report then return end
  local report, lines = view.report, {}
  local caption, selected
  if view.selection then
    for _, group in ipairs(report.groups) do
      if group.id == view.selection.group then
        for _, buff in ipairs(group.buffs) do
          if buff.name == view.selection.spell then selected = buff; break end
        end
        if selected then caption = AssignmentUI.CoverageGroupLabel(report.raid, group.id) .. " · " .. selected.name end
        break
      end
    end
  end
  if selected then
    for _, name in ipairs(selected.missing) do lines[#lines + 1] = { text = string.format(L["Missing: %s"], name) } end
    for _, name in ipairs(selected.unknown) do lines[#lines + 1] = { text = string.format(L["Unknown: %s"], name) } end
    if #lines == 0 then lines[1] = { text = L["All checked players have this buff."] } end
  else
    if view.selection then view.page = view.summaryPage end
    view.selection = nil
    for _, group in ipairs(report.groups) do
      local name = AssignmentUI.CoverageGroupLabel(report.raid, group.id)
      for _, buff in ipairs(group.buffs) do
        lines[#lines + 1] = { text = name .. " · " .. buff.name, group = group.id, spell = buff.name,
          counts = string.format(L["%d Confirmed · %d Missing · %d Unknown"], buff.confirmed, #buff.missing, #buff.unknown) }
      end
    end
    if #lines == 0 then
      lines[1] = { text = report.grouped and L["No applicable buffs"] or L["Join a party or raid to check buff coverage."] }
    end
  end
  view.title:SetText(caption or L["Raid Coverage"])
  view.notice:SetText(report.incomplete and L["Some roster information could not be checked."] or "")
  local pages = math.max(1, math.ceil(#lines / #view.rows))
  view.page = math.max(1, math_min(view.page, pages))
  view.previous:SetShown(view.page > 1)
  view.next:SetShown(view.page < pages)
  view.back:SetShown(selected ~= nil)
  view.subgroupButton:SetShown(selected == nil)
  view.preparationButton:SetShown(selected == nil)
  for index, row in ipairs(view.rows) do
    local line = lines[(view.page - 1) * #view.rows + index]
    row.line = line
    row.heading:SetText(line and line.text or "")
    row.counts:SetText(line and line.counts or "")
    row.navigation.role = line and line.spell and "button" or "detail"
    row:SetShown(line ~= nil)
  end
  if K.active and not K.edit and not K.InScope(K.current) then K.Move(1) end
end

function AssignmentUI.RefreshCoverage(view)
  if not view:IsVisible() or InCombatLockdown() or X.PlayerSuspended() then return end
  view.pendingRefresh = nil
  view.report = X.RaidCoverage()
  if view.report then AssignmentUI.UpdateCoverage(view) end
end

function AssignmentUI.BuildCoverage(panel)
  local view = AssignmentUI.CreatePanel(panel, "BuffRadarRaidCoverage", 574, 405, panel:GetFrameLevel() + 5)
  view.searchOpen = function() AssignmentUI.OpenCoverage(panel) end
  view.searchFilter = function(widget) return widget == view.refresh end
  view.rows = {}
  view.title = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  view.title:SetPoint("TOPLEFT", 16, -14)
  view.title:SetPoint("TOPRIGHT", -44, -14)
  view.title:SetJustifyH("LEFT")
  AssignmentUI.CloseButton(view, function() view:Hide() end)
  view.notice = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  view.notice:SetPoint("TOPLEFT", 16, -46)
  view.notice:SetPoint("TOPRIGHT", -172, -46)
  view.notice:SetJustifyH("LEFT")
  view.refresh = MakeButton(view, L["Refresh Preview"], 144, function() AssignmentUI.RefreshCoverage(view) end)
  view.refresh:SetPoint("TOPRIGHT", -16, -37)
  for index = 1, 7 do
    local row = CreateFrame("Button", nil, view)
    row:SetSize(542, 39)
    row:SetPoint("TOPLEFT", 16, -69 - (index - 1) * 42)
    row.heading = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.heading:SetPoint("TOPLEFT", 3, -3)
    row.heading:SetPoint("TOPRIGHT", -3, -3)
    row.heading:SetJustifyH("LEFT")
    row.heading:SetWordWrap(false)
    row.counts = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.counts:SetPoint("TOPLEFT", 3, -20)
    row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    row:SetScript("OnClick", function()
      if not row.line or not row.line.spell or InCombatLockdown() or X.PlayerSuspended() then return end
      view.selection = { group = row.line.group, spell = row.line.spell }
      view.summaryPage, view.page = view.page, 1
      AssignmentUI.UpdateCoverage(view)
    end)
    K.Register(row, view, function() return row.heading:GetText() end, "button", function()
      if row.line then return row.line.counts end
    end)
    view.rows[index] = row
  end
  local function move(delta)
    if not view:IsVisible() or not view.report then return end
    view.page = view.page + delta
    AssignmentUI.UpdateCoverage(view)
  end
  local function wheel(_, delta) move(delta > 0 and -1 or 1) end
  view:EnableMouseWheel(true)
  view:SetScript("OnMouseWheel", wheel)
  for _, row in ipairs(view.rows) do
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", wheel)
  end
  view.previous = MakeButton(view, L["Previous"], 86, function() move(-1) end)
  view.previous:SetPoint("BOTTOMLEFT", 16, 12)
  view.next = MakeButton(view, L["Next"], 86, function() move(1) end)
  view.next:SetPoint("LEFT", view.previous, "RIGHT", 8, 0)
  view.back = MakeButton(view, L["Back"], 110, function()
    view.selection, view.page = nil, view.summaryPage
    AssignmentUI.UpdateCoverage(view)
  end)
  view.back:SetPoint("BOTTOMRIGHT", -16, 12)
  view.subgroupButton = MakeButton(view, L["Subgroup Responsibilities"], 199, function()
    AssignmentUI.OpenSubgroup(panel, true)
  end)
  view.subgroupButton:SetPoint("BOTTOMRIGHT", -16, 12)
  view.preparationButton = MakeButton(view, L["Raid Preparation"], 150, function()
    X.RaidPreparationCommand("show")
  end)
  view.preparationButton:SetPoint("RIGHT", view.subgroupButton, "LEFT", -8, 0)
  view:HookScript("OnHide", function()
    view.pendingRefresh, view.report, view.selection = nil, nil, nil
    for _, row in ipairs(view.rows) do row.line = nil end
  end)
  if UISpecialFrames then table.insert(UISpecialFrames, "BuffRadarRaidCoverage") end
  return view
end

function AssignmentUI.OpenCoverage(panel)
  if InCombatLockdown() or X.PlayerSuspended() then return end
  panel.picker:Hide()
  if panel.subgroup then panel.subgroup:Hide() end
  if panel.coordination then panel.coordination:Hide() end
  if panel.preparation then panel.preparation:Hide() end
  if panel.preview then panel.preview:Hide() end
  if panel.practice then panel.practice:Hide() end
  panel.coverage = panel.coverage or AssignmentUI.BuildCoverage(panel)
  local view = panel.coverage
  view.selection, view.page = nil, 1
  view:Show()
  AssignmentUI.RefreshCoverage(view)
end

function X.QueuePersonalReadiness()
  local view = cfg and cfg.assignmentPanel and cfg.assignmentPanel.preparation
  if view and view.tab == "personal" then X.QueueAssignmentPreviewRefresh(true) end
end

function AssignmentUI.PreparationAvailable(tab)
  local settings = X.GetDB()
  return settings and not settings.liteMode and not InCombatLockdown() and not X.PlayerSuspended()
    and (tab == "personal" or X.InGroup())
end

function AssignmentUI.DrawPreparation(view, rosterRefresh)
  local report = view.report
  local personal = view.tab == "personal"
  local lines = personal and report.personal or {}
  local attention, unknown = 0, 0
  local oldExpandedIndex = view.expandedIndex
  local expandedIndex, expandedEnd
  local labels = { attention = L["Needs Attention"], unknown = L["Unknown"], clear = L["Checks Complete"] }
  for _, member in ipairs(report.members) do
    if member.status == "attention" then attention = attention + 1 end
    if member.unknown or member.status == "unknown" then unknown = unknown + 1 end
    if view.tab == "players" then
      local status = labels[member.status] or labels.unknown
      if member.status == "attention" and member.unknown then status = status .. " · " .. labels.unknown end
      local guid = #member.details > 0 and member.guid or nil
      local expanded = guid and view.expanded == guid
      lines[#lines + 1] = { text = member.name .. " · " .. status, guid = guid,
        hint = guid and (expanded and L["Collapse details"] or L["Expand details"]) or nil }
      if expanded then
        expandedIndex = #lines
        for _, detail in ipairs(member.details) do lines[#lines + 1] = { text = detail, indented = true } end
        expandedEnd = #lines
      end
    end
  end
  if view.tab == "reagents" then
    for _, reagent in ipairs(report.reagents) do
      local text = reagent.carried and string.format(L["%d carried · %d needed"], reagent.carried, reagent.needed)
        or string.format(L["Carried quantity unknown · %d needed"], reagent.needed)
      if reagent.carried and reagent.carried < reagent.needed then
        text = text .. " · " .. string.format(L["Shortfall: %d"], reagent.needed - reagent.carried)
      end
      lines[#lines + 1] = { text = reagent.name, hint = text }
    end
  else
    if view.expanded and not expandedIndex then view.expanded = nil end
    -- Follow the same player's block if the current page showed it before an
    -- event. Paging manually through unrelated rows is kept where possible.
    if rosterRefresh and expandedIndex and oldExpandedIndex then
      local offset = (view.page - 1) * #view.rows + 1 - oldExpandedIndex
      if offset < #view.rows and offset <= (view.expandedEnd or oldExpandedIndex) - oldExpandedIndex
        and expandedIndex ~= oldExpandedIndex then
        view.page = math.ceil(math_min(expandedEnd, expandedIndex + math.max(0, offset)) / #view.rows)
      end
    end
    view.expandedIndex, view.expandedEnd = expandedIndex, expandedEnd
  end
  if #lines == 0 then
    lines[1] = { text = view.tab == "players" and L["No eligible players to check."]
      or (report.incomplete and L["Reagent needs could not be confirmed."]
        or L["No reagents required for the current checklist."]) }
  end
  view.summary:SetText(personal and L["Your character only"]
    or string.format(L["%d Players · %d Need Attention · %d With Unknowns"], #report.members, attention, unknown))
  view.notice:SetText(personal and L["Soulwell availability cannot be checked."]
    or report.incomplete and L["Some roster information could not be checked."] or "")
  local grouped = X.InGroup()
  view.players:SetShown(grouped)
  view.reagents:SetShown(grouped)
  view.back:SetShown(grouped)
  view.personalTab:ClearAllPoints()
  if grouped then view.personalTab:SetPoint("LEFT", view.reagents, "RIGHT", 8, 0)
  else view.personalTab:SetPoint("TOPLEFT", 16, -75) end
  for _, tab in ipairs({ "players", "reagents", "personal" }) do
    local button = tab == "personal" and view.personalTab or view[tab]
    if view.tab == tab then button:Disable() else button:Enable() end
  end
  local pages = math.max(1, math.ceil(#lines / #view.rows))
  view.page = math.max(1, math_min(view.page, pages))
  view.pageLabel:SetText(string.format(L["Page %d of %d"], view.page, pages))
  view.previous:SetShown(view.page > 1)
  view.next:SetShown(view.page < pages)
  local previousFocus, focusedRow
  if K.active and not K.edit then
    for _, row in ipairs(view.rows) do
      if K.current == row.navigation then
        focusedRow, previousFocus = row, row.line and row.line.guid
        break
      end
    end
  end
  local focus
  for index, row in ipairs(view.rows) do
    local line = lines[(view.page - 1) * #view.rows + index]
    if GameTooltip.IsOwned and GameTooltip:IsOwned(row) then GameTooltip:Hide() end
    row.line = line
    row.heading:SetPoint("TOPLEFT", line and line.indented and 20 or 3, -3)
    row.heading:SetText(line and ((line.guid and (line.guid == view.expanded and "− " or "+ ") or "") .. line.text) or "")
    row.hint:SetText(line and line.hint or "")
    row.navigation.role = line and line.guid and "button" or "detail"
    row:SetShown(line ~= nil)
    if previousFocus and line and line.guid == previousFocus then focus = row.navigation end
  end
  if K.active and not K.edit then
    if focus then K.Focus(focus)
    elseif focusedRow then K.Focus(view.refresh.navigation)
    elseif not K.InScope(K.current) then K.Move(1) end
  end
end

function AssignmentUI.RefreshPreparation(view, rosterRefresh)
  if not view:IsVisible() then return end
  view.pendingRefresh = nil
  if not AssignmentUI.PreparationAvailable(view.tab) then view:Hide(); return end
  view.report = X.Measure("prepare", X.RaidPreparationSnapshot, view.tab == "personal")
  if not view.report then view:Hide(); return end
  AssignmentUI.DrawPreparation(view, rosterRefresh)
end

function X.CloseRaidPreparation(groupOnly)
  local view = cfg and cfg.assignmentPanel and cfg.assignmentPanel.preparation
  if view and (not groupOnly or view.tab ~= "personal") then view:Hide() end
end

function X.MoveRaidPreparation(delta)
  local view = cfg and cfg.assignmentPanel and cfg.assignmentPanel.preparation
  if not view or not view.report or not view:IsVisible() or not AssignmentUI.PreparationAvailable(view.tab) then return end
  view.page = view.page + delta
  AssignmentUI.DrawPreparation(view)
end

function AssignmentUI.BuildPreparation(panel)
  local view = AssignmentUI.CreatePanel(panel, "BuffRadarRaidPreparation", 574, 405, panel:GetFrameLevel() + 5)
  local function text(font, x, y, right)
    local label = view:CreateFontString(nil, "OVERLAY", font)
    label:SetPoint("TOPLEFT", x, y)
    label:SetPoint("TOPRIGHT", -right, y)
    label:SetJustifyH("LEFT")
    return label
  end
  text("GameFontNormalLarge", 16, -14, 44):SetText(L["Raid Preparation"])
  AssignmentUI.CloseButton(view, function() view:Hide() end)
  view.summary = text("GameFontHighlightSmall", 16, -44, 210)
  view.refresh = MakeButton(view, L["Refresh Preparation"], 182, function() AssignmentUI.RefreshPreparation(view, true) end)
  view.refresh:SetPoint("TOPRIGHT", -16, -37)
  view.notice = text("GameFontHighlightSmall", 16, -104, 16)
  local function selectTab(tab)
    if not view.report or view.tab == tab or not view:IsVisible() or not AssignmentUI.PreparationAvailable(tab) then return end
    local personalChanged = (view.tab == "personal") ~= (tab == "personal")
    view.tab, view.page, view.expanded, view.expandedIndex, view.expandedEnd = tab, 1, nil, nil, nil
    if personalChanged then AssignmentUI.RefreshPreparation(view) else AssignmentUI.DrawPreparation(view) end
  end
  view.players = MakeButton(view, L["Players"], 102, function() selectTab("players") end)
  view.players:SetPoint("TOPLEFT", 16, -75)
  view.reagents = MakeButton(view, L["Reagents"], 102, function() selectTab("reagents") end)
  view.reagents:SetPoint("LEFT", view.players, "RIGHT", 8, 0)
  view.personalTab = MakeButton(view, L["Personal"], 120, function() selectTab("personal") end)
  view.rows = {}
  local function wheel(_, delta) X.MoveRaidPreparation(delta > 0 and -1 or 1) end
  view:EnableMouseWheel(true)
  view:SetScript("OnMouseWheel", wheel)
  for index = 1, 6 do
    local row = CreateFrame("Button", nil, view)
    row:SetSize(542, 37)
    row:SetPoint("TOPLEFT", 16, -130 - (index - 1) * 38)
    row.heading = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.heading:SetPoint("TOPLEFT", 3, -3)
    row.heading:SetPoint("TOPRIGHT", -3, -3)
    row.heading:SetJustifyH("LEFT")
    row.hint = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.hint:SetPoint("TOPLEFT", 17, -21)
    row.hint:SetPoint("TOPRIGHT", -3, -21)
    row.hint:SetJustifyH("LEFT")
    row.hint:SetWordWrap(false)
    row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    row:SetScript("OnClick", function()
      local line = row.line
      if not line or not line.guid or not view:IsVisible() or not X.InGroup()
        or InCombatLockdown() or X.PlayerSuspended() then return end
      if view.expanded == line.guid then view.expanded = nil else view.expanded = line.guid end
      AssignmentUI.DrawPreparation(view)
    end)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", wheel)
    local function name() return row.line and row.line.text end
    local function description() return row.line and row.line.hint end
    K.Register(row, view, name, "detail", description)
    Tip(row, name, description)
    view.rows[index] = row
  end
  view.previous = MakeButton(view, L["Previous"], 110, function() X.MoveRaidPreparation(-1) end)
  view.previous:SetPoint("BOTTOMLEFT", 16, 12)
  view.next = MakeButton(view, L["Next"], 110, function() X.MoveRaidPreparation(1) end)
  view.next:SetPoint("LEFT", view.previous, "RIGHT", 8, 0)
  view.pageLabel = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  view.pageLabel:SetPoint("BOTTOM", 35, 18)
  view.back = MakeButton(view, L["Back"], 110, function() AssignmentUI.OpenCoverage(panel) end)
  view.back:SetPoint("BOTTOMRIGHT", -16, 12)
  view:HookScript("OnHide", function()
    view.pendingRefresh, view.report, view.expanded, view.expandedIndex, view.expandedEnd = nil, nil, nil, nil, nil
    for _, row in ipairs(view.rows) do row.line = nil end
    GameTooltip:Hide()
    if K.active and not K.edit and panel:IsVisible() then K.Move(1) end
  end)
  if UISpecialFrames then table.insert(UISpecialFrames, "BuffRadarRaidPreparation") end
  return view
end

function X.OpenRaidPreparation(personal)
  local tab = personal and "personal" or "players"
  if not CLASSIC_FEATURES or not AssignmentUI.PreparationAvailable(tab) then return end
  if not cfg or not cfg.assignmentPanel or not cfg.assignmentPanel:IsVisible() then X.OpenAssignments() end
  local panel = cfg.assignmentPanel
  panel.picker:Hide()
  if panel.coverage then panel.coverage:Hide() end
  if panel.coordination then panel.coordination:Hide() end
  if panel.subgroup then panel.subgroup:Hide() end
  if panel.preview then panel.preview:Hide() end
  if panel.practice then panel.practice:Hide() end
  panel.preparation = panel.preparation or AssignmentUI.BuildPreparation(panel)
  local view = panel.preparation
  view.tab, view.page = tab, 1
  view.expanded, view.expandedIndex, view.expandedEnd = nil, nil, nil
  view:Show()
  AssignmentUI.RefreshPreparation(view)
end

function AssignmentUI.SameSubgroups(left, right)
  if not left or not right then return left == right end
  for group = 1, 8 do
    if left[group] ~= right[group] then return false end
  end
  return true
end

function AssignmentUI.DrawSubgroup(view)
  local option = view.options[view.index]
  local editable = option and X.InRaid()
  local changed = editable and not AssignmentUI.SameSubgroups(view.saved, view.draft)
  local report = view.report
  local rows = report and report.members or {}
  local notice = view.warning
  if not X.InRaid() then notice = L["Join a raid to set subgroup responsibilities."]
  elseif not option then notice = L["No known targeted buffs."]
  elseif not report or report.incomplete then notice = L["Some roster information could not be checked."]
  elseif #rows == 0 then notice = L["No raid members to preview."] end
  view.notice:SetText(notice or "")
  view.buff:SetText(option and option.name or L["No known targeted buffs."])
  local scope = not view.draft and L["All Groups"] or
    (next(view.draft) and L["Selected Groups"] or L["No Groups"])
  view.scope:SetText(editable and scope or "")
  for _, button in ipairs(view.editButtons) do
    if editable then button:Enable() else button:Disable() end
  end
  if editable and not changed and #view.options > 1 then view.buff:Enable() else view.buff:Disable() end
  if changed then view.apply:Enable() else view.apply:Disable() end
  for _, check in ipairs(view.groups) do check:Update() end
  local pageCount = math.max(1, math.ceil(#rows / #view.rows))
  view.page = math.max(1, math_min(view.page, pageCount))
  view.previous:SetShown(view.page > 1)
  view.next:SetShown(view.page < pageCount)
  local status = { eligible = L["Included"], excluded = L["Outside Selected Groups"], unknown = L["Unknown"] }
  for index, row in ipairs(view.rows) do
    local member = rows[(view.page - 1) * #view.rows + index]
    row.title:SetText(member and (AssignmentUI.CoverageGroupLabel(true, member.subgroup) .. " · " .. member.name
      .. " · " .. (status[member.status] or L["Unknown"])) or "")
    local detail = member and (member.fallback or member.detail)
    if member and member.group then detail = string.format(L["Group option: %s"], member.group) end
    local text = member and member.spell
    if detail and text then text = text .. " · " .. detail
    elseif detail then text = detail end
    row.detail:SetText(text or "")
    row:SetShown(member ~= nil)
  end
  if K.active and not K.edit and not K.InScope(K.current) then K.Move(1) end
end

function AssignmentUI.RefreshSubgroup(view)
  if not view:IsVisible() or InCombatLockdown() or X.PlayerSuspended() then return end
  local inRaid = X.InRaid()
  if view.inRaid and not inRaid then view:Hide(); return end
  view.inRaid = inRaid
  local old = view.options[view.index]
  view.options, view.index = X.SubgroupDutyOptions(), 1
  if old then
    for index, option in ipairs(view.options) do
      if option.key == old.key then view.index = index; break end
    end
  end
  local option = view.options[view.index]
  local key = inRaid and option and option.key
  local saved = key and X.GetSubgroupDuty(key)
  if key ~= view.key or not AssignmentUI.SameSubgroups(view.saved, saved) then
    view.warning = key and view.key == key and L["Subgroup responsibilities changed. Review the current selection and try again."] or nil
    view.key, view.saved, view.draft, view.page = key, saved, key and X.GetSubgroupDuty(key), 1
  end
  if key then view.report = X.PreviewSubgroupDuty(key, view.draft) else view.report = nil end
  AssignmentUI.DrawSubgroup(view)
end

function X.QueueSubgroupDutyRefresh(key)
  local panel = cfg and cfg.assignmentPanel
  local view = panel and panel.subgroup
  if view and view:IsVisible() and view.key == key then AssignmentUI.RefreshSubgroup(view) end
end

function AssignmentUI.BuildSubgroup(panel)
  local view = AssignmentUI.CreatePanel(panel, "BuffRadarSubgroupResponsibilities", 574, 405, panel:GetFrameLevel() + 5)
  local title = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -14)
  title:SetText(L["Subgroup Responsibilities"])
  local function close()
    local returnToCoverage = view.returnToCoverage
    view:Hide()
    if returnToCoverage then AssignmentUI.OpenCoverage(panel) end
  end
  AssignmentUI.CloseButton(view, close)
  view.notice = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  view.notice:SetPoint("TOPLEFT", 16, -113)
  view.notice:SetPoint("TOPRIGHT", -16, -113)
  view.notice:SetJustifyH("LEFT")
  view.notice:SetWordWrap(true)
  local hint = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("BOTTOMLEFT", 16, 40)
  hint:SetText(L["Session only. Changes apply after you select Apply."])
  view.scope = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  view.scope:SetPoint("BOTTOMRIGHT", -16, 40)
  view.scope:SetJustifyH("RIGHT")
  local function canEdit()
    return view:IsVisible() and view.key and X.InRaid() and not InCombatLockdown() and not X.PlayerSuspended()
  end
  local function choose(delta)
    if not canEdit() or not AssignmentUI.SameSubgroups(view.saved, view.draft) or #view.options < 2 then return end
    view.index = ((view.index - 1 + delta) % #view.options) + 1
    AssignmentUI.RefreshSubgroup(view)
  end
  view.buff = MakeButton(view, "", 300, function() choose(1) end)
  view.buff:SetPoint("TOPLEFT", 16, -41)
  K.Register(view.buff, view, L["Buff"], "choice", function() return view.buff:GetText() end, choose)
  view.refresh = MakeButton(view, L["Refresh Preview"], 180, function() AssignmentUI.RefreshSubgroup(view) end)
  view.refresh:SetPoint("TOPRIGHT", -16, -41)
  local function setDraft(draft)
    if not canEdit() then return end
    view.draft, view.warning, view.page = draft, nil, 1
    AssignmentUI.RefreshSubgroup(view)
  end
  view.all = MakeButton(view, L["All Groups"], 130, function() setDraft(nil) end)
  view.all:SetPoint("TOPLEFT", 16, -76)
  view.none = MakeButton(view, L["No Groups"], 130, function() setDraft({}) end)
  view.none:SetPoint("LEFT", view.all, "RIGHT", 8, 0)
  view.groups, view.editButtons = {}, { view.all, view.none }
  for group = 1, 8 do
    local check = MakeCheck(view, "", function() return not view.draft or view.draft[group] end, function(checked)
      if not canEdit() then return end
      if not view.draft then
        view.draft = {}
        for index = 1, 8 do view.draft[index] = true end
      end
      view.draft[group] = checked and true or nil
      setDraft(view.draft)
    end)
    check:SetSize(20, 24)
    check.label:SetText(tostring(group))
    check:SetHitRectInsets(0, -10, 0, 0)
    check.navigation.label = function() return string.format(L["Raid Group %d"], group) end
    check:SetPoint("TOPLEFT", 301 + (group - 1) * 32, -74)
    view.groups[group] = check
    view.editButtons[#view.editButtons + 1] = check
  end
  view.rows = {}
  local function move(delta)
    if not view:IsVisible() then return end
    view.page = view.page + delta
    AssignmentUI.DrawSubgroup(view)
  end
  local function wheel(_, delta) move(delta > 0 and -1 or 1) end
  view:EnableMouseWheel(true)
  view:SetScript("OnMouseWheel", wheel)
  for index = 1, 5 do
    local row = CreateFrame("Button", nil, view)
    row:SetSize(542, 41)
    row:SetPoint("TOPLEFT", 16, -142 - (index - 1) * 42)
    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.title:SetPoint("TOPLEFT", 3, 0)
    row.title:SetPoint("TOPRIGHT", -3, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.detail:SetPoint("TOPLEFT", 3, -15)
    row.detail:SetPoint("TOPRIGHT", -3, -15)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetMaxLines(2)
    local function heading() return row.title:GetText() end
    local function detail()
      local value = row.detail:GetText()
      if value and value ~= "" then return value end
    end
    Tip(row, heading, detail)
    K.Register(row, view, heading, "detail", detail)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", wheel)
    view.rows[index] = row
  end
  view.previous = MakeButton(view, L["Previous"], 108, function() move(-1) end)
  view.previous:SetPoint("BOTTOMLEFT", 16, 12)
  view.next = MakeButton(view, L["Next"], 108, function() move(1) end)
  view.next:SetPoint("LEFT", view.previous, "RIGHT", 8, 0)
  view.cancel = MakeButton(view, L["Cancel"], 110, close)
  view.cancel:SetPoint("BOTTOMRIGHT", -16, 12)
  view.apply = MakeButton(view, L["Apply"], 110, function()
    if not canEdit() then return end
    local key, draft = view.key, view.draft
    if not AssignmentUI.SameSubgroups(view.saved, X.GetSubgroupDuty(key)) then
      AssignmentUI.RefreshSubgroup(view)
      return
    end
    if X.SetSubgroupDuty(key, draft) then
      view.saved, view.draft = X.GetSubgroupDuty(key), X.GetSubgroupDuty(key)
      view.warning = nil
    end
    AssignmentUI.RefreshSubgroup(view)
  end)
  view.apply:SetPoint("RIGHT", view.cancel, "LEFT", -8, 0)
  view:HookScript("OnHide", function()
    view.pendingRefresh, view.options, view.index = nil, {}, 1
    view.key, view.draft, view.saved, view.report, view.warning = nil, nil, nil, nil, nil
    view.inRaid, view.returnToCoverage = nil, nil
    GameTooltip:Hide()
    if K.active and not K.edit and panel:IsVisible() then K.Move(1) end
  end)
  if UISpecialFrames then table.insert(UISpecialFrames, "BuffRadarSubgroupResponsibilities") end
  return view
end

function AssignmentUI.OpenSubgroup(panel, fromCoverage)
  panel.picker:Hide()
  if panel.coordination then panel.coordination:Hide() end
  if panel.preview then panel.preview:Hide() end
  if panel.practice then panel.practice:Hide() end
  if panel.coverage then panel.coverage:Hide() end
  if panel.preparation then panel.preparation:Hide() end
  panel.subgroup = panel.subgroup or AssignmentUI.BuildSubgroup(panel)
  local view = panel.subgroup
  view:Hide()
  view.options, view.index, view.page = {}, 1, 1
  view.key, view.report, view.returnToCoverage = nil, nil, fromCoverage
  view:Show()
  AssignmentUI.RefreshSubgroup(view)
  if K.active and not K.edit then K.Move(1) end
end

function X.OpenSubgroupResponsibilities()
  if not CLASSIC_FEATURES or X.PlayerSuspended() or InCombatLockdown() then return end
  X.OpenAssignments()
  AssignmentUI.OpenSubgroup(cfg.assignmentPanel)
end

function AssignmentUI.UpdateCoordination(view)
  local model, lines = view.model, {}
  local leader = model.active == true and model.leader == true
  if view.tab ~= "inbox" and not leader then view.tab, view.page = "inbox", 1 end
  local tab = view.tab
  local pending = model.pending
  local status = model.reason and L[model.reason]
    or (model.active and L["Caster Coordination is on for this group."] or L["Caster Coordination is off."])
  view.notice:SetText(status)
  view.participation:SetText(model.active and L["Opt Out"] or L["Opt In"])
  view.tabs.inbox:SetText(pending and L["Inbox"] .. " (1)" or L["Inbox"])
  if model.active or model.available then view.participation:Enable() else view.participation:Disable() end
  for key, button in pairs(view.tabs) do
    button:SetShown(model.active == true and (key == "inbox" or leader))
    if key == tab then button:Disable() else button:Enable() end
  end
  view.request:SetShown(leader and tab == "reports")
  if model.canRequest then view.request:Enable() else view.request:Disable() end
  view.review:SetShown(leader and (tab == "reports" or tab == "draft") and model.reportRequest == true)
  view.publish:SetShown(leader and tab == "draft" and model.draft ~= nil)
  if model.canPublish then view.publish:Enable() else view.publish:Disable() end
  view.need:SetShown(leader and tab == "reports")
  view.needLabel:SetShown(leader and tab == "reports")
  view.add:SetShown(leader and tab == "reports")
  view.inbox:SetShown(tab == "inbox" and pending ~= nil)
  if pending and not pending.reviewed then view.inbox:Enable() else view.inbox:Disable() end
  view.accept:SetShown(tab == "inbox" and pending ~= nil)
  view.decline:SetShown(tab == "inbox" and pending ~= nil)
  if pending and pending.reviewed then view.accept:Enable() else view.accept:Disable() end

  if model.active and tab == "reports" then
    if model.reportRequest then
      for _, report in ipairs(model.reports or {}) do
        local keys = report.keys
        lines[#lines + 1] = { title = report.name, detail = keys and
          (#keys > 0 and table.concat(keys, ", ") or L["No learned buff capabilities have been reported."]) or L["No response"] }
      end
    else
      lines[1] = { title = L["No caster reports requested."] }
    end
  elseif model.active and tab == "draft" then
    for _, row in ipairs(model.draft or {}) do
      lines[#lines + 1] = { title = row.key, detail = row.before .. " → " .. row.after }
    end
    if #lines == 0 then
      lines[1] = { title = model.draft and L["No learned buff capabilities have been reported."] or L["No reviewed draft."] }
    end
  elseif model.active and tab == "delivery" then
    local delivery = { sent = L["Awaiting acknowledgement"], acknowledged = L["Acknowledged"],
      failed = L["Send failed"], localOnly = L["Assigned locally"] }
    for _, recipient in ipairs(model.sent or {}) do
      lines[#lines + 1] = { title = recipient.name, detail = delivery[recipient.status] }
    end
    if #lines == 0 then lines[1] = { title = L["No plan has been published."] } end
    view.notice:SetText(L["Delivery status is separate from buff coverage."])
  elseif model.active and tab == "inbox" then
    if pending then
      lines[1] = { title = string.format(L["Plan from %s"], pending.name) }
      for _, key in ipairs(pending.keys) do lines[#lines + 1] = { title = key } end
      if #pending.keys == 0 then lines[2] = { title = L["No assigned buffs"] } end
    else
      lines[1] = { title = L["No plan waiting for review."] }
    end
    if model.accepted then
      lines[#lines + 1] = { title = string.format(L["Your accepted duties: %s"], table.concat(model.accepted.keys, ", ")) }
    end
  end
  local pages = math.max(1, math.ceil(#lines / #view.rows))
  view.page = math.max(1, math_min(view.page, pages))
  view.previous:SetShown(view.page > 1)
  view.next:SetShown(view.page < pages)
  for index, row in ipairs(view.rows) do
    local line = lines[(view.page - 1) * #view.rows + index]
    local previousTitle, previousDetail = row.title:GetText(), row.detail:GetText()
    row.title:SetText(line and line.title or "")
    row.detail:SetText(line and line.detail or "")
    row:SetShown(line ~= nil)
    if line and K.active and not K.edit and K.current == row.navigation
      and (previousTitle ~= line.title or previousDetail ~= (line.detail or "")) then K.Focus(row.navigation) end
  end
  if K.active and not K.edit and not K.InScope(K.current) then K.Move(1) end
end

function AssignmentUI.RefreshCoordination(view)
  if not view:IsVisible() or InCombatLockdown() or X.PlayerSuspended() then return end
  local model = X.CoordinationSnapshot()
  local before = view.model
  if before and before.generation ~= model.generation then
    view.page = 1
    view.need:ClearFocus()
    view.need:SetText("")
  end
  view.model = model
  AssignmentUI.UpdateCoordination(view)
  local deadline = model.nextRefreshAt
  if view.deadline == deadline then return end
  view.deadline, view.refreshTicket = deadline, nil
  if deadline and C_Timer and C_Timer.After then
    local ticket = {}
    view.refreshTicket = ticket
    C_Timer.After(math.max(0.05, deadline - GetTime() + 0.05), function()
      if view.refreshTicket ~= ticket then return end
      view.deadline, view.refreshTicket = nil, nil
      AssignmentUI.RefreshCoordination(view)
    end)
  end
end

function X.QueueCoordinationRefresh()
  local panel = cfg and cfg.assignmentPanel
  local view = panel and panel.coordination
  if view then AssignmentUI.RefreshCoordination(view) end
end

function AssignmentUI.BuildCoordination(panel)
  local view = AssignmentUI.CreatePanel(panel, "BuffRadarCasterCoordination", 574, 405, panel:GetFrameLevel() + 5)
  local title = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -14)
  title:SetText(L["Caster Coordination"])
  AssignmentUI.CloseButton(view, function() view:Hide() end)
  view.notice = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  view.notice:SetPoint("TOPLEFT", 17, -44)
  view.notice:SetPoint("TOPRIGHT", -147, -44)
  view.notice:SetJustifyH("LEFT")
  view.notice:SetWordWrap(true)
  local function command(action, value, selected)
    if not view:IsVisible() or not view.model or InCombatLockdown() or X.PlayerSuspended() then return end
    if selected then view.tab, view.page = selected, 1 end
    X.Coordinate(action, value, view.model.token)
    AssignmentUI.RefreshCoordination(view)
  end
  view.participation = MakeButton(view, L["Opt In"], 124, function()
    if view.model then command(view.model.active and "off" or "on", nil, "reports") end
  end)
  view.participation:SetPoint("TOPRIGHT", -16, -39)
  view.tabs = {}
  local sections = { { "reports", L["Reports"] }, { "draft", L["Draft"] },
    { "delivery", L["Delivery"] }, { "inbox", L["Inbox"] } }
  for index, section in ipairs(sections) do
    local key = section[1]
    local tab = MakeButton(view, section[2], 124, function()
      view.tab, view.page = key, 1
      AssignmentUI.RefreshCoordination(view)
    end)
    tab:SetPoint("TOPLEFT", 16 + (index - 1) * 132, -77)
    view.tabs[key] = tab
  end
  local function move(delta)
    if not view.model then return end
    view.page = view.page + delta
    AssignmentUI.RefreshCoordination(view)
  end
  local function wheel(_, delta) move(delta > 0 and -1 or 1) end
  view:EnableMouseWheel(true)
  view:SetScript("OnMouseWheel", wheel)
  view.rows = {}
  for index = 1, 5 do
    local row = CreateFrame("Button", nil, view)
    row:SetSize(542, 40)
    row:SetPoint("TOPLEFT", 16, -109 - (index - 1) * 42)
    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.title:SetPoint("TOPLEFT", 3, -2)
    row.title:SetPoint("TOPRIGHT", -3, -2)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.detail:SetPoint("TOPLEFT", 3, -19)
    row.detail:SetPoint("TOPRIGHT", -3, -19)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", wheel)
    local function heading() return row.title:GetText() end
    local function detail()
      local value = row.detail:GetText()
      if value and value ~= "" then return value end
    end
    Tip(row, heading, detail)
    K.Register(row, view, heading, "detail", detail)
    view.rows[index] = row
  end
  view.request = MakeButton(view, L["Request Reports"], 175, function() command("request") end)
  view.request:SetPoint("BOTTOMLEFT", 16, 13)
  view.review = MakeButton(view, L["Review Caster Plan"], 192, function() command("review", nil, "draft") end)
  view.review:SetPoint("BOTTOMRIGHT", -16, 13)
  view.publish = MakeButton(view, L["Publish Plan"], 157, function() command("publish", nil, "draft") end)
  view.publish:SetPoint("BOTTOMLEFT", 16, 13)
  view.inbox = MakeButton(view, L["Review Incoming Plan"], 200, function() command("inbox") end)
  view.inbox:SetPoint("BOTTOMLEFT", 16, 13)
  view.accept = MakeButton(view, L["Accept"], 114, function() command("accept") end)
  view.accept:SetPoint("BOTTOMRIGHT", -138, 13)
  view.decline = MakeButton(view, L["Decline"], 114, function() command("decline") end)
  view.decline:SetPoint("BOTTOMRIGHT", -16, 13)
  view.previous = MakeButton(view, L["Previous"], 114, function() move(-1) end)
  view.previous:SetPoint("BOTTOMLEFT", 16, 42)
  view.next = MakeButton(view, L["Next"], 114, function() move(1) end)
  view.next:SetPoint("LEFT", view.previous, "RIGHT", 6, 0)
  view.needLabel = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  view.needLabel:SetPoint("BOTTOMLEFT", 260, 65)
  view.needLabel:SetText(L["Buff Key"])
  view.need = X.PanelWidget("EditBox", nil, view, "InputBoxTemplate")
  view.need:SetSize(122, 20)
  view.need:SetPoint("BOTTOMLEFT", 265, 42)
  view.need:SetAutoFocus(false)
  view.need:SetMaxLetters(30)
  local function add()
    local key = (view.need:GetText() or ""):match("^%s*(.-)%s*$")
    if key ~= "" then command("need", key) end
    view.need:ClearFocus()
    view.need:SetText("")
  end
  view.need:SetScript("OnEnterPressed", add)
  view.need:SetScript("OnEscapePressed", function(box) box:SetText(""); box:ClearFocus() end)
  K.RegisterEdit(view.need, view, L["Buff Key"])
  view.add = MakeButton(view, L["Add Needed Buff"], 164, add)
  view.add:SetPoint("BOTTOMRIGHT", -16, 41)
  view:HookScript("OnHide", function()
    view.need:ClearFocus()
    view.need:SetText("")
    view.model, view.deadline, view.refreshTicket = nil, nil, nil
    if K.active and not K.edit and panel:IsVisible() then K.Move(1) end
  end)
  if UISpecialFrames then table.insert(UISpecialFrames, "BuffRadarCasterCoordination") end
  return view
end

function X.OpenCoordination()
  if not CLASSIC_FEATURES or X.PlayerSuspended() or InCombatLockdown() then return end
  X.OpenAssignments()
  local panel = cfg.assignmentPanel
  panel.picker:Hide()
  if panel.subgroup then panel.subgroup:Hide() end
  if panel.preview then panel.preview:Hide() end
  if panel.coverage then panel.coverage:Hide() end
  if panel.preparation then panel.preparation:Hide() end
  if panel.practice then panel.practice:Hide() end
  panel.coordination = panel.coordination or AssignmentUI.BuildCoordination(panel)
  local view = panel.coordination
  view.tab, view.page = "reports", 1
  view:Show()
  AssignmentUI.RefreshCoordination(view)
  if view.model and view.model.pending then
    view.tab = "inbox"
    AssignmentUI.UpdateCoordination(view)
  end
  if K.active and not K.edit then K.Move(1) end
end

function AssignmentUI.Build()
  local panel = AssignmentUI.CreatePanel(cfg, "BuffRadarAssignments", 574, 405, cfg:GetFrameLevel() + 8)
  panel.searchTab = "buffs"
  panel.searchOpen = function() X.OpenAssignments() end
  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 15, -14)
  title:SetPoint("TOPRIGHT", -241, -14)
  title:SetJustifyH("LEFT")
  title:SetText(L["Class & Role Assignments"])
  panel.closeButton = AssignmentUI.CloseButton(panel, function() panel:Hide() end)
  panel.enabled = MakeCheck(panel, L["Use Class & Role Assignments"], X.AssignmentEnabled, function(value)
    if InCombatLockdown() or X.PlayerSuspended() then return end
    X.SetAssignmentEnabled(value)
    Refresh()
  end)
  panel.enabled:SetPoint("TOPLEFT", 11, -39)
  panel.previewButton = MakeButton(panel, L["Preview Current Group"], 220, function() AssignmentUI.OpenPreview(panel) end)
  panel.previewButton:SetPoint("TOPRIGHT", -16, -39)
  local practice = MakeButton(panel, L["Practice Mode"], 145, X.OpenPractice)
  practice:SetPoint("BOTTOMLEFT", 15, 11)
  local undo = MakeButton(panel, L["Undo Last Change"], 202, X.RunBlockerUndo)
  undo:SetPoint("BOTTOMRIGHT", -15, 11)
  panel.coverageButton = MakeButton(panel, L["Raid Coverage"], 172, function() AssignmentUI.OpenCoverage(panel) end)
  panel.coverageButton:SetPoint("LEFT", practice, "RIGHT", 12, 0)
  panel.coordinationButton = MakeButton(panel, L["Caster Coordination"], 190, X.OpenCoordination)
  panel.coordinationButton:SetPoint("TOPRIGHT", -45, -9)
  local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 15, -67)
  hint:SetPoint("TOPRIGHT", -15, -67)
  hint:SetJustifyH("LEFT")
  hint:SetText(L["World applies to nearby players and unknown roles. A role or World rule takes priority over All Roles. Only enabled buffs are offered."])
  panel.cells = {}
  for column, slot in ipairs(X.ASSIGNMENT_SLOTS) do
    local heading = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    heading:SetPoint("TOP", panel, "TOPLEFT", 166 + (column - 1) * 87, -110)
    heading:SetText(AssignmentUI.labels[slot])
  end
  local classNames = _G.LOCALIZED_CLASS_NAMES_MALE
  for index, class in ipairs(X.BLESSING_CLASS_ORDER) do
    local y = -130 - (index - 1) * 27
    local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", 15, y - 4)
    label:SetWidth(107)
    label:SetJustifyH("LEFT")
    label:SetText(classNames and classNames[class] or class)
    panel.cells[class] = {}
    for column, slot in ipairs(X.ASSIGNMENT_SLOTS) do
      local button = MakeButton(panel, "", 82, function()
        AssignmentUI.OpenPicker(panel, class, slot)
      end)
      button:SetPoint("TOPLEFT", 125 + (column - 1) * 87, y)
      local function labelText() return AssignmentUI.CellLabel(class, slot) end
      local function valueText() return button.assignmentText end
      K.Register(button, panel, labelText, "button", valueText)
      Tip(button, labelText, valueText)
      panel.cells[class][slot] = button
    end
  end
  panel.picker = AssignmentUI.BuildPicker(panel)
  panel:HookScript("OnHide", function()
    panel.picker:Hide()
    if panel.practice then panel.practice:Hide() end
    if panel.preview then panel.preview:Hide() end
    if panel.coverage then panel.coverage:Hide() end
    if panel.preparation then panel.preparation:Hide() end
    if panel.coordination then panel.coordination:Hide() end
    if panel.subgroup then panel.subgroup:Hide() end
    cfg.searchToggle:Show()
    GameTooltip:Hide()
  end)
  panel.picker:HookScript("OnHide", function(picker)
    local blockers = picker.blockers
    picker.blockers, picker.action, picker.draft = nil, nil, nil
    if blockers and blockers.review then blockers.review:Hide() end
    panel.closeButton:Show()
    GameTooltip:Hide()
    if K.active and not K.edit then
      local cell = panel.cells[picker.class] and panel.cells[picker.class][picker.slot]
      if not blockers and cell and K.InScope(cell.navigation) then K.Focus(cell.navigation)
      elseif blockers and blockers:IsVisible() then K.Move(1) end
    end
  end)
  if UISpecialFrames then
    table.insert(UISpecialFrames, "BuffRadarAssignments")
  end
  return panel
end

function X.OpenAssignments(preview)
  if not CLASSIC_FEATURES or X.PlayerSuspended() or InCombatLockdown() then return end
  OpenConfig(true)
  SelectTab("buffs")
  cfg.assignmentPanel = cfg.assignmentPanel or AssignmentUI.Build()
  cfg.searchToggle:Hide()
  cfg.assignmentPanel:Show()
  AssignmentUI.Update()
  if preview then
    if cfg.assignmentPanel.practice then cfg.assignmentPanel.practice:Hide() end
    AssignmentUI.OpenPreview(cfg.assignmentPanel)
  end
end

function X.OpenRaidCoverage()
  if not CLASSIC_FEATURES or X.PlayerSuspended() or InCombatLockdown() then return end
  X.OpenAssignments()
  AssignmentUI.OpenCoverage(cfg.assignmentPanel)
end

do
  function X.RefreshAutoThemePriority()
    local panel = cfg and cfg.themePriorityPanel
    if not panel or not panel:IsVisible() then return end
    local order = X.AutoThemePriority()
    for index, entry in ipairs(order) do
      local row = panel.rows[index]
      row.palette, row.name = entry[2], X.THEMES[entry[2]].label
      row.label:SetText(string.format("%d. %s", index, row.name))
      if index > 1 then row.up:Enable() else row.up:Disable() end
      if index < #order then row.down:Enable() else row.down:Disable() end
    end
    local status = X.AutoThemeStatus()
    if status ~= panel.status:GetText() then
      panel.status:SetText(status)
      if K.active and K.current == panel.statusRow.navigation then K.Focus(K.current) end
    end
  end

  local function BuildAutoThemePriority()
    local panel = AssignmentUI.CreatePanel(cfg, "BuffRadarAutoThemePriority", 540, 405, cfg:GetFrameLevel() + 8)
    panel.searchTab = "look"
    panel.searchOpen = function() X.OpenAutoThemePriority() end
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, -14)
    title:SetText(L["Auto Theme Priority"])
    local help = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 18, -42)
    help:SetText(L["Auto uses the first loaded addon in this list."])
    panel.statusRow = CreateFrame("Button", nil, panel)
    panel.statusRow:SetPoint("TOPLEFT", 18, -62)
    panel.statusRow:SetPoint("TOPRIGHT", -18, -62)
    panel.statusRow:SetHeight(22)
    panel.statusRow:EnableMouse(false)
    panel.status = panel.statusRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.status:SetAllPoints(panel.statusRow)
    panel.status:SetJustifyH("LEFT")
    K.Register(panel.statusRow, panel, L["Auto Theme Priority"], "detail",
      function() return panel.status:GetText() end)
    panel.rows = {}
    local function canEdit()
      return panel:IsVisible() and not InCombatLockdown() and not X.PlayerSuspended()
    end
    for index = 1, #X.AUTO_THEME_ADDONS do
      local row = {}
      row.label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      row.label:SetPoint("TOPLEFT", 18, -100 - (index - 1) * 25)
      local function move(offset)
        if not canEdit() or not X.MoveAutoThemePriority(row.palette, offset) then return end
        X.RefreshAutoThemePriority()
        if K.active then
          local destination = panel.rows[index + offset]
          local button = offset < 0 and destination.up or destination.down
          if not button:IsEnabled() then button = offset < 0 and destination.down or destination.up end
          K.Focus(button.navigation)
        end
      end
      row.up = MakeButton(panel, L["Move Up"], 108, function() move(-1) end)
      row.up:SetPoint("TOPRIGHT", -134, -97 - (index - 1) * 25)
      row.up.navigation.label = function() return string.format(L["Move %s Up"], row.name) end
      row.down = MakeButton(panel, L["Move Down"], 108, function() move(1) end)
      row.down:SetPoint("TOPRIGHT", -18, -97 - (index - 1) * 25)
      row.down.navigation.label = function() return string.format(L["Move %s Down"], row.name) end
      panel.rows[index] = row
    end
    panel.resetButton = MakeButton(panel, L["Reset Order"], 155, function()
      if canEdit() then
        X.ResetAutoThemePriority()
        X.RefreshAutoThemePriority()
      end
    end)
    panel.resetButton:SetPoint("BOTTOMLEFT", 18, 14)
    panel.closeButton = MakeButton(panel, L["Close"], 108, function() panel:Hide() end)
    panel.closeButton:SetPoint("BOTTOMRIGHT", -18, 14)
    panel:HookScript("OnHide", function()
      if not cfg:IsVisible() or cfg.curTab ~= "look" then return end
      cfg.searchToggle:Show()
      if K.active and K.InScope(cfg.themePriorityBtn.navigation) then K.Focus(cfg.themePriorityBtn.navigation) end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, "BuffRadarAutoThemePriority") end
    return panel
  end

  function X.OpenAutoThemePriority()
    if X.PlayerSuspended() or InCombatLockdown() then return end
    OpenConfig(true)
    SelectTab("look")
    cfg.themePriorityPanel = cfg.themePriorityPanel or BuildAutoThemePriority()
    cfg.searchToggle:Hide()
    cfg.themePriorityPanel:Show()
    X.RefreshAutoThemePriority()
    if K.active then K.Move(1) end
  end
end

function AssignmentUI.BuildReadinessSettings(panel)
  local r = { checks = {}, rules = {} }
  local I, D = X.Intel, X.Debuffs
  local function label(text, x, y, font)
    local fs = panel:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
  end
  local function section(text, x, y) return label(L[text], x, y, "GameFontNormal") end
  local function field(text, x, y, width, length, numeric, commit)
    local box = X.PanelWidget("EditBox", nil, panel, "InputBoxTemplate")
    box:SetSize(width, 20)
    box:SetPoint("TOPLEFT", x, y)
    box:SetAutoFocus(false)
    box:SetMaxLetters(length)
    if numeric then box:SetNumeric(true) end
    box:SetScript("OnEnterPressed", function(self)
      if commit then commit(self:GetText()) end
      self:ClearFocus()
      if commit then r.Update() end
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); r.Update() end)
    K.RegisterEdit(box, panel, L[text])
    RegisterSearch(box, panel, L[text])
    Tip(box, L[text], commit and L["Press Enter to save."] or nil)
    return box
  end
  local function check(key, text, x, y, tip)
    local cb = MakeCheck(panel, L[text], function() return db[key] end, function(value)
      X.SetPreference(key, value)
      RefreshConfig()
    end)
    cb:SetPoint("TOPLEFT", x, y)
    WrapCheckLabel(cb)
    if tip then Tip(cb, L[text], L[tip]) end
    r.checks[#r.checks + 1] = cb
  end

  section("Buff intelligence", 14, -10)
  label(L["Forecast seconds (0 = off)"], 15, -45)
  r.forecast = field("Forecast seconds (0 = off)", 214, -40, 50, 3, true,
    function(input) I.SetForecast(tonumber(input)) end)
  check("smartPriority", "Smart buff priority", 10, -68,
    "Promote buffs for tanks, healers, recovery and your instance rules without changing eligibility.")
  label(L["Priority buff key for this instance"], 15, -104)
  r.instance = field("Priority buff key for this instance", 18, -122, 152, 32, false)
  local instance = MakeButton(panel, L["Apply here"], 98, function()
    local key = r.instance:GetText():match("^%s*(.-)%s*$")
    I.SetInstancePriority(I.InstanceID(), key == "" and "clear" or key)
    r.instance:ClearFocus()
    r.Update()
  end)
  instance:SetPoint("TOPLEFT", 174, -121)
  Tip(instance, L["Apply here"], L["Use a key from /br buffs. Clear the field to remove the rule."])

  section("Performance & alerts", 303, -10)
  check("scanThrottle", "Adaptive scan throttle", 299, -35,
    "Slow periodic scans at rest or with high latency. Event refreshes stay responsive.")
  check("liteMode", "Lite mode", 299, -63,
    "Pause the checklist, forecasts, debuffs and optional aura watches without changing their settings.")
  check("statusMinimap", "Status on the minimap", 299, -91)
  check("visualAlerts", "Quiet visual alerts", 299, -119,
    "Briefly highlight the window or minimap without sound. Respects Reduced Motion.")

  section("Encounter debuffs", 14, -164)
  check("debuffWatch", "Show watched debuffs", 10, -184,
    "Track up to eight harmful spell IDs on you or your focus, when the client exposes them.")
  label(L["Spell ID"], 16, -220)
  label(L["Watch unit"], 111, -220)
  label(L["Encounter ID (optional)"], 252, -220)
  r.spell = field("Spell ID", 18, -238, 78, 7, true)
  r.boss = field("Encounter ID (optional)", 254, -238, 121, 7, true)
  r.unit = "player"
  r.unitButton = MakeButton(panel, L["Player"], 123, function()
    r.unit = r.unit == "player" and "focus" or "player"
    r.unitButton:SetText(L[r.unit == "player" and "Player" or "Focus"])
  end)
  r.unitButton:SetPoint("TOPLEFT", 111, -237)
  r.unitButton.navigation.label = L["Watch unit"]
  r.unitButton.navigation.value = function() return r.unitButton:GetText() end
  local add = MakeButton(panel, L["Save watch"], 151, function()
    local boss = r.boss:GetText()
    if D.SetRule(tonumber(r.spell:GetText()), r.unit, boss == "" and 0 or tonumber(boss)) then
      r.spell:SetText("")
      r.boss:SetText("")
      RefreshConfig()
    end
  end)
  add:SetPoint("TOPLEFT", 402, -237)
  r.noRules = label(L["No debuffs are being tracked."], 15, -276)
  for i = 1, X.Settings.MaxDebuffRules do
    local x, y = 16 + ((i - 1) % 2) * 278, -277 - math_floor((i - 1) / 2) * 30
    local row = { text = label("", x, y) }
    row.text:SetWidth(186)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.remove = MakeButton(panel, L["Remove"], 79, function()
      local rule = db.debuffRules[i]
      if rule then D.Remove(rule.spellID, rule.unit); RefreshConfig() end
    end)
    row.remove:SetPoint("TOPLEFT", x + 188, y + 3)
    row.remove.navigation.value = function() return row.full end
    Tip(row.remove, L["Remove"], function() return row.full end)
    r.rules[i] = row
  end

  if CLASSIC_FEATURES then
    label(L["Consumable aura ID (0 = off)"], 15, -424)
    r.aura = field("Consumable aura ID (0 = off)", 232, -420, 80, 7, true,
      function(input) X.Readiness.SetAura(tonumber(input)) end)
    local personal = MakeButton(panel, L["Open personal checks"], 214, function() X.RaidPreparationCommand("personal") end)
    personal:SetPoint("TOPLEFT", 339, -420)
  end
  r.memory = MakeButton(panel, L["Memory usage"], 152, I.MemoryReport)
  r.memory:SetPoint("TOPLEFT", 14, -444)
  local status = MakeButton(panel, L["Copy buff status"], 152, function() K.Stop(); X.ext.status("export") end)
  status:SetPoint("LEFT", r.memory, "RIGHT", 10, 0)
  r.feedback = MakeButton(panel, L["Feedback"], 152, function() K.Stop(); X.ShowFeedback() end)
  r.feedback:SetPoint("LEFT", status, "RIGHT", 10, 0)
  r.firstCast = MakeButton(panel, L["First cast guide"], 234, function() K.Stop(); X.Support.Open() end)
  r.firstCast:SetPoint("TOPLEFT", 14, -474)
  r.support = MakeButton(panel, L["Copy Support Report"], 234, function() K.Stop(); X.Support.ShowReport() end)
  r.support:SetPoint("LEFT", r.firstCast, "RIGHT", 10, 0)

  function r.Update()
    for _, cb in ipairs(r.checks) do cb:Update() end
    if not r.forecast:HasFocus() then r.forecast:SetText(tostring(db.forecastSeconds)) end
    if r.aura and not r.aura:HasFocus() then r.aura:SetText(tostring(db.readinessAura)) end
    if not r.instance:HasFocus() then
      local id = I.InstanceID()
      r.instance:SetText(id and db.instancePriority[id] or "")
    end
    r.noRules:SetShown(#db.debuffRules == 0)
    for i, row in ipairs(r.rules) do
      local rule = db.debuffRules[i]
      row.full = rule and D.RuleLabel(rule)
      row.text:SetText(row.full or "")
      row.remove:SetShown(rule ~= nil)
    end
  end
  return r
end

local function BuildConfig()
  db = X.GetDB()
  -- Blizzard's standard window (title bar, BuffRadar icon in the portrait
  -- corner, close button, inset content area) so it matches the retail UI.
  -- A client without that template gets the original hand-drawn window.
  local templateOK, built = pcall(CreateFrame, "Frame", "BuffRadarConfig", UIParent, "ButtonFrameTemplate")
  local native = templateOK and built and built.SetTitle and built.Inset and built.CloseButton
  if native then
    cfg = built
  else
    if templateOK and built then built:Hide() end
    cfg = X.PanelWidget("Frame", "BuffRadarConfig", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  end
  cfg:SetSize(CONFIG_WIDTH, CONFIG_HEIGHT)
  cfg.navControls = {}
  cfg:SetPoint("CENTER")
  cfg:SetFrameStrata("DIALOG")
  cfg:SetClampedToScreen(true)
  cfg:SetMovable(true)
  cfg:EnableMouse(true)
  cfg:HookScript("OnMouseDown", function() K.Stop() end)
  cfg:RegisterForDrag("LeftButton")
  cfg:SetScript("OnDragStart", function(self)
    K.Stop()
    self:StartMoving()
  end)
  if UISpecialFrames then table.insert(UISpecialFrames, "BuffRadarConfig") end -- Esc closes it

  if native then
    cfg.closeButton = cfg.CloseButton
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
    local close = X.PanelWidget("Button", nil, cfg, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() cfg:Hide() end)
    cfg.closeButton = close
  end
  K.Register(cfg.closeButton, cfg, L["Close settings"], "button")

  -- Tabs: Blizzard's bottom tabs on the standard window (named
  -- BuffRadarConfigTab1..6, as PanelTemplates expects), otherwise the
  -- original row of buttons along the top.
  cfg.panels, cfg.tabBtns = {}, {}
  cfg.nativeTabs = native and PanelTemplates_SetNumTabs and PanelTemplates_SetTab and true or false
  local tabDefs = {
    { "look", L["Window"], 75 }, { "alerts", L["Alerts"], 75 }, { "buffs", L["Buffs"], 70 },
    { "behavior", L["Behavior"], 98 }, { "data", L["Ignore & Stats"], 126 }, { "readiness", L["Readiness"], 106 },
  }
  local tabList, prevTab, fallbackX = {}, nil, 14
  if cfg.nativeTabs then
    for i = 1, #tabDefs do
      local ok, tab = pcall(CreateFrame, "Button", "BuffRadarConfigTab" .. i, cfg, "PanelTabButtonTemplate")
      if not ok or not tab then
        cfg.nativeTabs = false
        for _, item in ipairs(tabList) do item:Hide() end
        break
      end
      tabList[i] = tab
    end
  end
  for i, td in ipairs(tabDefs) do
    local key, label = td[1], td[2]
    local function onClick() SelectTab(key); RefreshConfig() end
    local btn
    if cfg.nativeTabs then
      btn = tabList[i]
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
    else
      btn = MakeButton(cfg, "", td[3], onClick)
      btn:SetText(label)
      btn:SetPoint("TOPLEFT", fallbackX, -40)
      fallbackX = fallbackX + td[3] + 4
    end
    K.Register(btn, cfg, label, "tab").key = key
    cfg.tabBtns[key] = btn
    local panel = CreateFrame("Frame", nil, cfg)
    panel.searchTab = key
    if cfg.nativeTabs then  -- inside the template's inset area, below the title bar
      panel:SetPoint("TOPLEFT", cfg.Inset, "TOPLEFT", 4, -4)
    else
      panel:SetPoint("TOPLEFT", 8, -70)
    end
    panel:SetPoint("BOTTOMRIGHT", cfg, "BOTTOMRIGHT", native and -10 or -8, 38)
    panel:Hide()
    cfg.panels[key] = panel
  end
  if cfg.nativeTabs then
    cfg.Tabs = tabList  -- newer PanelTemplates look here; older ones use the names
    PanelTemplates_SetNumTabs(cfg, #tabList)
    cfg:SetClampRectInsets(0, 0, 0, -NATIVE_TAB_DEPTH)
  end

  cfg.readiness = AssignmentUI.BuildReadinessSettings(cfg.panels.readiness)

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
  local swatch = X.PanelWidget("Button", nil, look, BackdropTemplateMixin and "BackdropTemplate" or nil)
  swatch:SetSize(40, 18)
  swatch:SetPoint("LEFT", colorLabel, "RIGHT", 10, 0)
  if swatch.SetBackdrop then
    swatch:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                         edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    swatch:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
  end
  swatch:SetScript("OnClick", OpenColorPicker)
  cfg.swatch = swatch
  K.Register(swatch, look, L["Background color"], "button")

  local alphaLabel = look:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  alphaLabel:SetPoint("TOPLEFT", 14, -64)
  alphaLabel:SetText(L["Background opacity"])
  local alphaValue = look:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  alphaValue:SetPoint("LEFT", alphaLabel, "RIGHT", 8, 0)
  cfg.alphaValue = alphaValue
  cfg.slider = MakeSlider(look, 16, -84, 250, 0, 100, 5, function(v)
    v = math.floor(v + 0.5)
    db.bgAlpha = v / 100
    alphaValue:SetText(v .. "%")
    ApplyAppearance()
  end, L["Background opacity"], function() return cfg.alphaValue:GetText() end)

  cfg.titleCheck = MakeCheck(look, L["Show BuffRadar title"],
    function() return db.showTitle end,
    function(v) db.showTitle = v; ApplyAppearance(); Refresh() end)
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
        if db.point then X.SaveCharacterPoint(k) end
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
  end, L["Row spacing"], function() return cfg.gapValue:GetText() end)

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
  end, L["Buff icon size"], function() return cfg.iconValue:GetText() end)

  local fadeLabel = look:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fadeLabel:SetPoint("TOPLEFT", 304, -240)
  fadeLabel:SetText(L["Idle fade (mouse away)"])
  local fadeValue = look:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fadeValue:SetPoint("LEFT", fadeLabel, "RIGHT", 8, 0)
  cfg.fadeValue = fadeValue
  cfg.fadeSlider = MakeSlider(look, 306, -260, 170, 0, 90, 5, function(v)
    v = math.floor(v + 0.5)
    db.idleFade = v
    fadeValue:SetText(v .. "%")
  end, L["Idle fade (mouse away)"], function() return cfg.fadeValue:GetText() end)

  local scaleLabel = look:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  scaleLabel:SetPoint("TOPLEFT", 14, -178)
  scaleLabel:SetText(L["Window scale"])
  cfg.scaleDrop = MakeScaleDropdown(look,
    function() return db.scale or 1 end,
    function(v)
      if InCombatLockdown() then Print("Can't rescale the window during combat."); return end
      db.scale = v
      ApplyGeometry()
      RefreshConfig()
    end, L["Window scale"])
  cfg.scaleDrop:SetPoint("LEFT", scaleLabel, "RIGHT", 12, 0)
  local widthHint = look:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  widthHint:SetPoint("TOPLEFT", 14, -206)
  widthHint:SetText("Drag either bottom corner to scale the window. Width: /br width <180-400>.")

  local resetLook = MakeButton(look, "Reset look", 110, function()
    if db.theme == X.AUTO_THEME_ID then db.theme = DEFAULTS.theme end
    db.bgColor = { DEFAULTS.bgColor[1], DEFAULTS.bgColor[2], DEFAULTS.bgColor[3] }
    db.bgAlpha = DEFAULTS.bgAlpha
    db.showTitle, db.showBorder, db.scale = true, true, 1
    db.width = DEFAULTS.width
    ApplyGeometry()  -- in combat this lands when combat ends
    if not X.ResolveAutoTheme() then
      ApplyAppearance()
      RefreshConfig()
    end
  end)
  resetLook:SetPoint("TOPLEFT", 14, -232)

  cfg.pillCheck = MakeCheck(look, L["Collapse to a pill while everyone is buffed"],
    function() return db.pill end,
    function(v) db.pill = v; Refresh() end)
  cfg.pillCheck:SetPoint("TOPLEFT", 10, -362)
  WrapCheckLabel(cfg.pillCheck)

  -- Keep long left-column checkbox labels clear of right-column controls.
  cfg.growCheck = MakeCheck(look, L["Grow the list upward"],
    function() return db.growUp end,
    function(v) db.growUp = v; X.ApplyAnchor(); Refresh() end)
  cfg.growCheck:SetPoint("TOPLEFT", 300, -296)

  cfg.twoColCheck = MakeCheck(look, L["Two columns when the list is long"],
    function() return db.twoCol end,
    function(v) db.twoCol = v; Refresh() end)
  cfg.twoColCheck:SetPoint("TOPLEFT", 10, -396)

  cfg.wizardBtn = MakeButton(look, L["Quick Setup"], 150, function()
    K.Stop()
    X.OpenWizard()
  end)
  cfg.wizardBtn:SetPoint("TOPLEFT", 134, -232)

  cfg.themeBtn = MakeButton(look, "Theme: Midnight", 170, function()
    local order = X.ThemeOrder()
    local cur = 1
    for i, k in ipairs(order) do if k:lower() == (db.theme or ""):lower() then cur = i end end
    X.ApplyTheme(order[cur % #order + 1])
  end)
  cfg.themeBtn:SetPoint("TOPLEFT", 250, -336)
  cfg.themeBtn.navigation.label = L["Theme"]
  cfg.themeBtn.navigation.value = function()
    if db.theme == X.AUTO_THEME_ID then return X.ThemeLabel(true) end
    local theme = X.ThemeDef(db.theme)
    return theme and not X.SavedTheme(db.theme) and theme.label or L["Custom theme"]
  end
  cfg.themePriorityBtn = MakeButton(look, L["Auto Theme Priority…"], 196, X.OpenAutoThemePriority)
  cfg.themePriorityBtn:SetPoint("TOPLEFT", 14, -336)

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
  cfg.saveThemeBtn:SetPoint("TOPLEFT", 428, -336)

  cfg.findCheck = MakeCheck(look, L["Show a name finder on the window"],
    function() return db.findBox end,
    function(v) db.findBox = v; X.ApplyRowLayout(); Refresh() end)
  cfg.findCheck:SetPoint("TOPLEFT", 300, -388)
  WrapCheckLabel(cfg.findCheck)

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
    CloseSearch()
    if cfg.searchToggle then cfg.searchToggle:Hide() end
    p:Show()
  end)
  cfg.displayBtn:SetPoint("TOPLEFT", 300, -428)

  cfg.panelPointCheck = MakeCheck(look, L["Remember Settings and Ready Check positions"],
    function() return db.rememberPanelPositions end,
    function(v) X.PanelPositions(v and "on" or "off") end)
  cfg.panelPointCheck:SetPoint("TOPLEFT", 10, -428)
  WrapCheckLabel(cfg.panelPointCheck)
  local resetPanels = MakeButton(look, L["Reset panel positions"], 170, function() X.PanelPositions("reset") end)
  resetPanels:SetPoint("TOPLEFT", 14, -465)

  cfg.minimapCheck = MakeCheck(look, L["Minimap button (drag it around the minimap)"],
    function() return db.showMinimap end,
    function(v) db.showMinimap = v; if RefreshMinimapButton then RefreshMinimapButton() end end)
  cfg.minimapCheck:SetPoint("TOPLEFT", 10, -268)

  local cfgScaleLabel = look:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  cfgScaleLabel:SetPoint("TOPLEFT", 14, -296)
  cfgScaleLabel:SetText(L["Settings window scale"])
  cfg.cfgScaleDrop = MakeScaleDropdown(look,
    function() return db.cfgScale or 1 end,
    function(v)
      db.cfgScale = v
      RefreshConfig()
    end, L["Settings window scale"])
  cfg.cfgScaleDrop:SetPoint("LEFT", cfgScaleLabel, "RIGHT", 12, 0)

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
  WrapCheckLabel(cfg.muteInstCheck)

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

  section(alerts, L["Keybinds"], 10, -230)
  local keyText = alerts:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  keyText:SetPoint("TOPLEFT", 14, -254)
  local keyText2 = alerts:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  keyText2:SetPoint("TOPLEFT", 14, -270)
  cfg.keyText, cfg.keyText2 = keyText, keyText2

  local setKey = MakeButton(alerts, L["Set keybind"], 120, function()
    K.Stop()
    OpenKeybinds()
  end)
  setKey:SetPoint("TOPLEFT", 14, -288)
  local makeMacro = MakeButton(alerts, L["Create macro"], 120, function() MakeMacro() end)
  makeMacro:SetPoint("LEFT", setKey, "RIGHT", 10, 0)

  local hint = alerts:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 14, -316)
  hint:SetWidth(420)
  hint:SetJustifyH("LEFT")
  hint:SetText(L["Cast next buff works with a keyboard or controller and does not fire in combat."])

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
    K.RegisterEdit(cb.rebuffBox, buffs, function()
      return string.format(L["Rebuff time for %s"], cb.itemLabel or L["Buff"])
    end, function()
      return cb.rebuffBox:GetText() ~= "" and cb.rebuffBox:GetText() or L["Use all-buff setting"]
    end)
    Tip(cb.rebuffBox, "Rebuff time (seconds)", rebuffTip)
    cb:Hide()
    cb.rebuffBox:Hide()
    cb.searchEntry = RegisterSearch(cb, buffs, "")
    cfg.buffChecks[i] = cb
  end
  local prioReset = MakeButton(buffs, "Reset buff order", 150, function()
    db.buffPrio = {}
    X.prioDirty = true
    Print("Buff order reset - your buffs are back in their normal order.")
    Refresh()
  end)
  prioReset:SetPoint("TOPLEFT", 14, -346)
  Tip(prioReset, "Buff order",
    "Rows offer your buffs in the addon's normal order until you set your own: /br prio lists your buffs, /br prio <short name> <place> moves one. This button clears your order.")
  local prioHint = buffs:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  prioHint:SetPoint("LEFT", prioReset, "RIGHT", 8, 0)
  prioHint:SetText("Your own buff order: /br prio")
  cfg.blessingButton = MakeButton(buffs, L["Blessings by class"], 190, OpenBlessingPanel)
  cfg.blessingButton:SetPoint("TOPRIGHT", -15, -346)
  if CLASSIC_FEATURES then
    cfg.assignmentButton = MakeButton(buffs, L["Class & Role Assignments"], 275, function() X.OpenAssignments() end)
    cfg.assignmentButton:SetPoint("TOPLEFT", 14, -379)
    cfg.thornsOutdoors = MakeCheck(buffs, L["Thorns: Any Class Outdoors"],
      function() return db.thornsAnyClassOutdoors end,
      X.SetThornsAnyClassOutdoors)
    cfg.thornsOutdoors:SetPoint("TOPLEFT", 310, -378)
    Tip(cfg.thornsOutdoors, L["Thorns: Any Class Outdoors"],
      L["Offer Thorns to any class in the open world. Explicit class and role assignments take precedence."])
    cfg.thornsOutdoors:Hide()
  end

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
  K.RegisterEdit(cfg.rebuffDefault, buffs, L["Rebuff time for all buffs (seconds)"],
    function() return cfg.rebuffDefault:GetText() end)
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
  WrapCheckLabel(cfg.consCheck)

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
  end, L["Group buff threshold"], function() return cfg.gcValue:GetText() end)
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
  sortHint:SetWidth(112)
  sortHint:SetJustifyH("LEFT")
  sortHint:SetText("role = tanks & leaders · distance = nearest · need = most missing")

  section(beh, "Coordination", 302, -176 + castY)

  cfg.syncCheck = MakeCheck(beh, L["Sync casts with other BuffRadar users"],
    function() return db.sync end,
    function(v) X.SetPreference("sync", v) end)
  cfg.syncCheck:SetPoint("TOPLEFT", 296, -200 + castY)
  WrapCheckLabel(cfg.syncCheck)

  cfg.requestsCheck = MakeCheck(beh, L["Mark players who ask for a buff in chat"],
    function() return db.requests end,
    function(v) db.requests = v end)
  cfg.requestsCheck:SetPoint("TOPLEFT", 296, -226 + castY)
  WrapCheckLabel(cfg.requestsCheck)

  cfg.digestCheck = MakeCheck(beh, L["Print a summary when joining a group"],
    function() return db.joinDigest end,
    function(v) db.joinDigest = v end)
  cfg.digestCheck:SetPoint("TOPLEFT", 296, -256 + castY)
  WrapCheckLabel(cfg.digestCheck)

  cfg.queueCheck = MakeCheck(beh, L["Tag the next row after a cast"],
    function() return db.queueTag end,
    function(v) db.queueTag = v end)
  cfg.queueCheck:SetPoint("TOPLEFT", 296, -282 + castY)

  cfg.buddyCheck = MakeCheck(beh, L["Split the list with other BuffRadar users"],
    function() return db.buddySplit end,
    function(v) db.buddySplit = v; Refresh() end)
  cfg.buddyCheck:SetPoint("TOPLEFT", 296, -308 + castY)
  WrapCheckLabel(cfg.buddyCheck)

  cfg.readyPostCheck = MakeCheck(beh, L["Post the ready-check summary to group chat"],
    function() return db.readyPost end,
    function(v) db.readyPost = v end)
  cfg.readyPostCheck:SetPoint("TOPLEFT", 296, -338 + castY)
  WrapCheckLabel(cfg.readyPostCheck)

  cfg.weaponCheck = MakeCheck(beh, L["Watch my weapon enchant"],
    function() return db.weaponWatch end,
    function(v) db.weaponWatch = v; Refresh() end)
  cfg.weaponCheck:SetPoint("TOPLEFT", 296, -370 + castY)

  cfg.enterCheck = MakeCheck(beh, L["Remind me when entering an instance unbuffed"],
    function() return db.enterFlash end,
    function(v) db.enterFlash = v end)
  cfg.enterCheck:SetPoint("TOPLEFT", 296, -396 + castY)
  WrapCheckLabel(cfg.enterCheck)

  cfg.clickThroughCheck = MakeCheck(beh, "Clicks pass through while locked",
    function() return db.clickThrough end,
    function(v) db.clickThrough = v; X.ApplyClickThrough() end)
  cfg.clickThroughCheck:SetPoint("TOPLEFT", 296, -428 + castY)
  cfg.modClickCheck = MakeCheck(beh, L["Shift-click a row casts the group version of its buff"],
    function() return db.modClick end,
    function(v) db.modClick = v; Refresh() end)
  cfg.modClickCheck:SetPoint("TOPLEFT", 296, -454 + castY)
  WrapCheckLabel(cfg.modClickCheck)
  Tip(cfg.modClickCheck, "Modifier clicks", "Shift-click a row to cast the group version of its buff (Prayer of Fortitude, Gift of the Wild, greater blessings) instead of the single-target version. Plain clicks are unchanged. Same as /br modclick.")
  Tip(cfg.clickThroughCheck, "Click-through while locked",
    "While the window is locked, it and its rows stop catching mouse clicks, so clicks land on the game world behind them. Unlock with /br lock to move or use the window again.")

  cfg.throttleCheck = MakeCheck(beh, L["Adaptive scan throttle"],
    function() return db.scanThrottle end,
    function(v) X.SetPreference("scanThrottle", v); RefreshConfig() end)
  cfg.throttleCheck:SetPoint("TOPLEFT", 10, -215)
  cfg.fastAuraCheck = MakeCheck(beh, L["Skip rescans for aura changes that touch no watched buff"],
    function() return db.fastAura end,
    function(v) db.fastAura = v end)
  cfg.fastAuraCheck:SetPoint("TOPLEFT", 10, -240)
  WrapCheckLabel(cfg.fastAuraCheck)
  cfg.pullFlashCheck = MakeCheck(beh, L["Flash when a pull timer starts"],
    function() return db.pullFlash end,
    function(v) X.SetPreference("pullFlash", v) end)
  cfg.pullFlashCheck:SetPoint("TOPLEFT", 10, -270)

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
  behHint:SetPoint("TOPLEFT", cfg.consCheck, "BOTTOMLEFT", 4, -8)
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
    K.Register(x, data, string.format(L["Remove ignored player %d"], i), "button")
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

  section(data, L["Settings profiles"], 10, -330)
  local profHint = data:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  profHint:SetPoint("TOPLEFT", 14, -352)
  profHint:SetText(L["Save window, alert and buff preferences to load here or with /br profile."])
  cfg.profileBox = X.PanelWidget("EditBox", nil, data, "InputBoxTemplate")
  cfg.profileBox:SetSize(170, 20)
  cfg.profileBox:SetPoint("TOPLEFT", 18, -374)
  cfg.profileBox:SetAutoFocus(false)
  cfg.profileBox:SetMaxLetters(40)
  cfg.profileBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  cfg.profileBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  K.RegisterEdit(cfg.profileBox, data, L["Profile name"])
  local function profName()
    return (cfg.profileBox:GetText() or ""):match("^%s*(.-)%s*$")
  end
  local profSave = MakeButton(data, L["Save"], 62, function()
    K.Stop()
    X.RequestProfileSave(profName())
  end)
  profSave:SetPoint("LEFT", cfg.profileBox, "RIGHT", 10, 0)
  local profLoad = MakeButton(data, L["Load"], 62, function()
    local name = profName()
    local ok, err = X.LoadProfile(name)
    if ok then
      Print("Profile loaded: " .. name)
      ApplyGeometry()
      ApplyAppearance()
      X.ApplyRowLayout()
      RefreshConfig()
      Refresh()
    else Print(err or "No profile named '" .. name .. "'.") end
  end)
  profLoad:SetPoint("LEFT", profSave, "RIGHT", 6, 0)
  local profDel = MakeButton(data, L["Delete"], 62, function()
    local name = profName()
    if X.DeleteProfile(name) then Print("Profile deleted: " .. name)
    else Print("No profile named '" .. name .. "'.") end
    RefreshConfig()
  end)
  profDel:SetPoint("LEFT", profLoad, "RIGHT", 6, 0)
  local profShare = MakeButton(data, L["Share BR2"], 86, function()
    local name = profName()
    local text = X.ProfileShareText(name)
    if text then
      K.Stop()
      X.ShowExport(text, false, "BuffRadar profile: " .. name)
    else
      Print("No profile named '" .. name .. "'.")
    end
  end)
  profShare:SetPoint("LEFT", profDel, "RIGHT", 6, 0)
  Tip(profShare, L["Share BR2"], L["Use a named BR2 profile to share newer preferences."])
  local profImport = MakeButton(data, L["Import"], 112, function()
    K.Stop()
    X.ShowExport("", true, L["Paste a shared profile, then review."], "profile")
  end)
  profImport:SetPoint("TOPRIGHT", -14, -422)
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
  Tip(cfg.themeBtn, function()
    return db.theme == X.AUTO_THEME_ID and X.ThemeLabel(true) or "Color theme"
  end, "Click to cycle the built-in and saved window color themes. Picking a custom background color afterwards switches back to a custom theme. Use /br theme to list theme names.")
  Tip(cfg.saveThemeBtn, "Save as theme", "Saves the window's current background and border colors as your own theme, so it joins the theme cycle. It is named automatically; /br theme save <name> saves under your own name, /br theme delete <name> removes one. Up to 4 saved themes.")
  Tip(cfg.gapSlider, "Row spacing", "Extra empty space between the rows, 0 to 8. The window grows to fit. Same as /br rowgap <0-8>.")
  Tip(cfg.iconSlider, "Buff icon size", "How big the missing-buff icons on each row are, 10 to 24. At 0 the size is automatic (16, or 12 in compact rows). Same as /br iconsize <0|10-24>.")
  Tip(cfg.displayBtn, "More display options", "Opens a panel with the finer display choices: which parts the coverage line shows, colored edge marks on rows (your assignments, tanks, expiring soon, your buddy's rows), how much detail row tooltips carry, class-colored names, realm names and shortened names.")
  Tip(cfg.wizardBtn, L["Quick Setup"], L["Choose your activity and role, then review the suggested settings. /br wizard"])
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
  Tip(setKey, L["Set keybind"], L["Open the BuffRadar section of the game's key bindings."])
  Tip(makeMacro, "Create macro", "Puts a BuffRadar macro on your cursor. Drop it on an action bar; pressing it casts the next buff.")
  -- Behavior
  Tip(cfg.groupCheck, "Only show in a party or raid", "Hide the window while you're solo. The Cast next buff key still works.")
  Tip(cfg.cityCheck, "Pause in major cities", "No scanning in capital cities, where crowds would fill the list. /br debug shows whether your zone counts as a city.")
  Tip(cfg.bgCheck, "Pause in battlegrounds and arenas", "No scanning in PvP instances.")
  Tip(cfg.taxiCheck, "Pause on flight paths", "While you're on a flight path you can't cast anyway, so the list pauses (like the city pause) instead of showing buffs you can't hand out. Same as /br taxi.")
  Tip(cfg.groupCastCheck, "Offer group buffs", "When enough group members need a buff, offer its group version (one cast covers the party).")
  Tip(cfg.gcSlider, L["Group buff threshold"], "How many group members must need the buff before the group version is offered.")
  Tip(cfg.sortBtn, "List order", "Click to switch: name = alphabetical; role = you, then tanks, then group leaders; distance = nearest first; need = whoever is missing the most castable buffs first.")
  Tip(cfg.syncCheck, "Cast sync", "When you or another BuffRadar user in your group casts a buff, everyone's list marks that player as being buffed for a few seconds, so two of you don't cast the same buff on the same player.")
  Tip(cfg.requestsCheck, "Chat buff requests", "A player on your list who whispers you (or says nearby) asking for a buff gets an 'asked for a buff' marker on their row.")
  Tip(cfg.digestCheck, "Group join summary", "One line in chat when you join a group: how many people are missing buffs and how many casts that is. Also prints when a Mythic+ run starts.")
  Tip(cfg.readyPostCheck, "Ready-check auto-post", "When a ready check runs, the summary is also posted to group chat — only when you're the leader or an assistant. Off: it only prints for you. Dead or AFK BuffRadar users hand their duties to the others automatically (cover-me, no setting).")
  Tip(cfg.weaponCheck, "Weapon enchant watch", "Your own row gets a 'weapon enchant missing' tag when an equipped weapon has no temporary enchant — a shaman imbue, a rogue poison, an oil or a sharpening stone. When your row isn't on the list, the coverage line says it instead.")
  Tip(cfg.enterCheck, "Instance-entry reminder", "One chat line when you step into a dungeon, raid or battleground while buffs are still missing: how many people still need buffs, and how many casts that is.")
  Tip(cfg.pullFlashCheck, "Pull-timer flash", "When a group pull timer starts (the game's /countdown, or a boss-mod pull timer from a trusted sender), the border flashes and chat shows the seconds and how many casts are still needed. Same as /br pullflash.")
  Tip(cfg.fastAuraCheck, "Fast aura updates", "Aura changes that touch no buff you can cast skip the rescan; the steady refresh still runs, and any doubtful payload rescans as before. Same as /br fastaura.")
  Tip(cfg.throttleCheck, L["Adaptive scan throttle"], L["Slow periodic scans at rest or with high latency. Event refreshes stay responsive."])
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
  local dpanel = X.PanelWidget("Frame", nil, cfg, BackdropTemplateMixin and "BackdropTemplate" or nil)
  dpanel.searchTab = "look"
  dpanel.searchOpen = function() cfg.displayBtn:Click() end
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
    btn.navigation.label = rd[2]
    btn.navigation.value = function() return btn:GetText() end
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
  cfg.tooltipBtn.navigation.label = L["Row tooltips"]
  cfg.tooltipBtn.navigation.value = function() return cfg.tooltipBtn:GetText() end
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
  cfg.trimBtn.navigation.label = L["Name length"]
  cfg.trimBtn.navigation.value = function() return cfg.trimBtn:GetText() end

  -- Keep search in a separate footer below the tab content.
  local footer = CreateFrame("Frame", nil, cfg)
  footer:SetSize(360, 20)
  footer:SetPoint("BOTTOMLEFT", cfg, "BOTTOMLEFT", 16, 10)
  cfg.searchFooter = footer
  local searchBox = X.PanelWidget("EditBox", nil, footer, "InputBoxTemplate")
  searchBox:SetSize(180, 20)
  searchBox:SetPoint("LEFT")
  searchBox:SetAutoFocus(false)
  searchBox:SetMaxLetters(30)
  local searchHint = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  searchHint:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)
  cfg.searchHint = searchHint
  searchBox:SetScript("OnTextChanged", function() cfg.searchPage = 1; UpdateSearch() end)
  searchBox:SetScript("OnEnterPressed", function()
    if cfg.searchRows[1].entry then cfg.searchRows[1]:Click() end
  end)
  searchBox:SetScript("OnTabPressed", function()
    K.Start(K.narrate)
    K.Focus(cfg.searchRows[1].entry and cfg.searchRows[1].navigation or cfg.searchBox.navigation)
  end)
  searchBox:SetScript("OnEscapePressed", CloseSearch)
  K.RegisterEdit(searchBox, cfg, L["Find settings across all tabs"], function()
    return cfg.searchHint:GetText()
  end)
  cfg.searchBox = searchBox
  local searchToggle = X.PanelWidget("Button", nil, cfg, "UIPanelButtonTemplate")
  searchToggle:SetSize(70, 22)
  searchToggle:SetText(L["Find"])
  searchToggle:SetScript("OnClick", function()
    if cfg.searchFooter:IsShown() then
      CloseSearch()
    else
      OpenSearch()
    end
  end)
  cfg.searchToggle = searchToggle
  K.Register(searchToggle, cfg, L["Find settings across all tabs"], "button")
  Tip(cfg.searchToggle, L["Find"], L["Find settings across all tabs"])
  local results = X.PanelWidget("Frame", nil, cfg, BackdropTemplateMixin and "BackdropTemplate" or nil)
  results:SetPoint("BOTTOMLEFT", cfg, "BOTTOMLEFT", 14, 38)
  results:SetSize(572, 210)
  results:SetFrameLevel(cfg:GetFrameLevel() + 25)
  if results.SetBackdrop then
    results:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    results:SetBackdropColor(0.04, 0.05, 0.08, 1)
    results:SetBackdropBorderColor(0.35, 0.55, 0.8, 1)
  end
  cfg.searchResultsPanel, cfg.searchRows = results, {}
  for i = 1, 5 do
    local row = MakeButton(results, "", 544, function()
      local entry = cfg.searchRows[i].entry
      if not entry or InCombatLockdown() or X.PlayerSuspended() then return end
      local narrate = K.narrate
      SelectTab(entry.tab)
      RefreshConfig()
      for index = #entry.path, 1, -1 do entry.path[index].searchOpen() end
      if entry.w:IsVisible() and entry.w.navigation then K.Start(narrate); K.Focus(entry.w.navigation) end
    end)
    row:SetPoint("TOPLEFT", 14, -12 - (i - 1) * 32)
    K.Register(row, cfg, function() return row:GetText() end, "button")
    row:Hide()
    cfg.searchRows[i] = row
  end
  cfg.searchPrev = MakeButton(results, L["Previous"], 100, function()
    cfg.searchPage = math.max(1, cfg.searchPage - 1); UpdateSearch()
  end)
  cfg.searchPrev:SetPoint("BOTTOMLEFT", 14, 10)
  cfg.searchPrev.navigation.panel = cfg
  cfg.searchNext = MakeButton(results, L["Next"], 100, function()
    cfg.searchPage = cfg.searchPage + 1; UpdateSearch()
  end)
  cfg.searchNext:SetPoint("BOTTOMRIGHT", -14, 10)
  cfg.searchNext.navigation.panel = cfg
  results:Hide()
  RegisterSearch(cfg.slider, look, "background opacity " .. L["Background opacity"])
  RegisterSearch(cfg.fadeSlider, look, "idle fade " .. L["Idle fade (mouse away)"])
  RegisterSearch(cfg.gcSlider, beh, "group buff threshold " .. L["Group buff threshold"])
  RegisterSearch(cfg.scaleDrop, look, "window scale " .. L["Window scale"])
  RegisterSearch(cfg.cfgScaleDrop, look, "settings window scale " .. L["Settings window scale"])

  cfg:SetScript("OnShow", function()
    CloseSearch()
    if cfg.searchToggle then cfg.searchToggle:Show() end
    RefreshConfig()
  end)
  X.BindPanelPosition(cfg, "settings", 0)
  K.Build()
  Tip(cfg.navButton, L["Keyboard Navigation"], navigationHelp)
  cfg:HookScript("OnHide", function()
    K.Stop(true)
    CloseSearch()
    if cfg.themePriorityPanel then cfg.themePriorityPanel:Hide() end
    if cfg.assignmentPanel then cfg.assignmentPanel:Hide() end
  end)
  cfg:RegisterEvent("DISPLAY_SIZE_CHANGED")
  cfg:RegisterEvent("UI_SCALE_CHANGED")
  cfg:RegisterEvent("PLAYER_REGEN_DISABLED")
  cfg:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
      K.Stop(true)
      CloseSearch()
      if cfg.themePriorityPanel then cfg.themePriorityPanel:Hide() end
      if cfg.assignmentPanel then cfg.assignmentPanel:Hide() end
    elseif cfg:IsShown() then ApplyConfigScale() end
  end)
  SelectTab("look")
  cfg:Hide()
end

RefreshConfig = function()
  db = X.GetDB()
  if not cfg or not cfg:IsShown() then return end
  ApplyConfigScale()
  local c = X.ThemeBackground()
  if cfg.swatch.SetBackdropColor then cfg.swatch:SetBackdropColor(c[1], c[2], c[3], 1) end
  cfg.slider:SetValue(math.floor((db.bgAlpha or 0.92) * 100 + 0.5))
  cfg.alphaValue:SetText(math.floor((db.bgAlpha or 0.92) * 100 + 0.5) .. "%")
  cfg.scaleDrop:Update()
  cfg.cfgScaleDrop:Update()
  cfg.titleCheck:Update()
  cfg.borderCheck:Update()
  if cfg.compactCheck then cfg.compactCheck:Update() end
  if cfg.charPointCheck then cfg.charPointCheck:Update() end
  cfg.panelPointCheck:Update()
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
  cfg.keyText:SetText(L["Cast next buff"] .. ": " .. KeybindText(NEXT_BINDING) ..
    "    " .. L["Cast next group buff"] .. ": " .. KeybindText("CLICK BuffRadarGroupButton:LeftButton"))
  cfg.keyText2:SetText(L["Show / hide window"] .. ": " .. KeybindText("BUFFRADAR_TOGGLE") ..
    "    " .. L["Mute / unmute sound"] .. ": " .. KeybindText("BUFFRADAR_MUTE"))
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
  if cfg.readiness and cfg.panels.readiness:IsShown() then cfg.readiness.Update() end
  if cfg.growCheck then cfg.growCheck:Update() end
  if cfg.twoColCheck then cfg.twoColCheck:Update() end
  if cfg.themeBtn then
    cfg.themeBtn:SetText("Theme: " .. X.ThemeLabel())
  end
  X.RefreshAutoThemePriority()
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

  local items, knowsThorns = {}, false
  for _, b in ipairs(myBuffs) do
    items[#items + 1] = { key = b.key, default = b.default, label = b.name, who = b.who }
    if b.key == "THORNS" and not b.custom then knowsThorns = true end
  end
  if cfg.thornsOutdoors then
    cfg.thornsOutdoors:SetShown(knowsThorns)
    cfg.thornsOutdoors:Update()
  end
  cfg.blessingButton:SetShown(X.HasKnownBlessings())
  if cfg.blessingPanel and cfg.blessingPanel:IsShown() then
    if X.HasKnownBlessings() then
      for _, selector in ipairs(cfg.blessingSelectors) do selector:Update() end
      cfg.blessingPanel.complement:Update()
    else
      cfg.blessingPanel:Hide()
    end
  end
  if X.HasKnownBlessings() then
    items[#items + 1] = { key = "BLESSINGS", default = true, label = "Blessings", who = "one per class" }
  end
  for i, cb in ipairs(cfg.buffChecks) do
    local it = items[i]
    if it then
      cb.itemKey, cb.itemLabel, cb.itemWho = it.key, it.label, it.who
      cb.searchEntry.keys = SearchKey(it.label .. " " .. (it.who or ""))
      cb.searchEntry.label = it.label
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
  AssignmentUI.Update()
  if cfg.searchFooter:IsShown() then UpdateSearch() end
  if K.active and not K.edit and not K.InScope(K.current) then K.Move(1) end
end

-- Toggles the settings window; forceShow opens it without toggling it closed.
OpenConfig = function(forceShow)
  if X.PlayerSuspended() then return end
  db = X.GetDB()
  if not cfg then BuildConfig() end
  if cfg:IsShown() and not forceShow then cfg:Hide() else cfg:Show() end
end

function X.OpenSettingsSearch()
  if X.PlayerSuspended() then return end
  OpenConfig(true)
  if K.Modal() then
    SelectTab(cfg.curTab or "look")
  end
  OpenSearch()
end

function X.OpenSettingsNavigation(narrate)
  if X.PlayerSuspended() or InCombatLockdown() then
    Print(L["Settings keyboard navigation is unavailable in combat or while dead."])
    return
  end
  OpenConfig(true)
  K.Start(narrate)
end

function X.HideConfig()
  if cfg and cfg:IsShown() then cfg:Hide() end
end

-- Esc > Options > AddOns > BuffRadar: a short page with a button that opens
-- the full settings window (which has more room than the options page).
if X.supported and Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
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
    if X.PlayerSuspended() then return end
    if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then pcall(HideUIPanel, SettingsPanel) end
    OpenConfig(true)
  end)
  open:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 0, -14)
  local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, page, "BuffRadar")
  if ok and category then pcall(Settings.RegisterAddOnCategory, category) end
end
end -- config window block
X.RefreshConfig, X.OpenConfig = RefreshConfig, OpenConfig
