-- BuffRadar - setup wizard, themes, and nearby / cast diagnostics.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local X = ns.X
local core = X.Core

local db
X.OnDBLoaded(function(value) db = value end)

local L, Print, PlayAlert, QueueRefresh = X.L, X.Print, core.PlayAlert, core.QueueRefresh
local ApplyAppearance, ApplyGeometry = X.ApplyAppearance, X.ApplyGeometry
local Ignore, Readable, SafeString = X.Ignore, X.Readable, core.SafeString
local Single, Missing, Valid = core.Single, core.Missing, core.Valid
local InGroup, InRaid = X.InGroup, X.InRaid
local RAID, PARTY, PLATES = core.RAID, core.PARTY, core.PLATES
local myBuffs, entries = core.Buffs, core.Entries
local CLASSIC_FEATURES = X.classic
local pairs, ipairs, type, pcall = pairs, ipairs, type, pcall
local math_min, math_floor = math.min, math.floor
local string_format = string.format
local table_sort = table.sort
local wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
local GetTime, InCombatLockdown = GetTime, InCombatLockdown
local UnitExists, UnitGUID, UnitClass = UnitExists, UnitGUID, UnitClass
local UnitIsPlayer, UnitCanAssist = UnitIsPlayer, UnitCanAssist

---------------------------------------------------------------------------
-- Quick Setup: stage both answers; only Finish changes live settings.
---------------------------------------------------------------------------
local activities = { { "solo", "Solo play" }, { "dungeon", "Dungeons / Mythic+" }, { "raid", "Raids" } }
local roles = { { "TANK", "Tank" }, { "HEALER", "Heal" }, { "DAMAGER", "DPS" } }

local function DraftSettings(draft)
  local group = draft.activity ~= "solo"
  local support = draft.role ~= "DAMAGER"
  return group and (support and "role" or "need") or "name", group and (support and 60 or 45) or 0, group
end

function X.WizardPage(n)
  local w = X.wizardFrame
  if not w or not w.draft then return end
  w.page = n
  w.title:SetText(string.format(L["Quick Setup · Step %d of 3"], n))
  w.back:SetShown(n > 1)
  w.next:SetShown(n == 3)
  for i = 1, 3 do w.choice[i]:Hide() end
  if n < 3 then
    w.body:SetText(L[n == 1 and "What do you play most often?" or "What is your primary role?"])
    local field = n == 1 and "activity" or "role"
    for i, option in ipairs(n == 1 and activities or roles) do
      local button, id, label = w.choice[i], option[1], option[2]
      button:SetText((w.draft[field] == id   and   "+ "   or   "") .. L[label])
      button:SetScript("OnClick", function()
        w.draft[field], w.draft[field .. "Label"] = id, label
        X.WizardPage(n + 1)
      end)
      button:Show()
    end
  else
    local sort, lead, group = DraftSettings(w.draft)
    local preset = X.PRESETS[w.draft.activity]
    local names = {}
    for i = 1, math_min(3, #myBuffs) do names[#names + 1] = myBuffs[i].name end
    if X.HasKnownBlessings() then names[#names + 1] = L["Blessings"] end
    if #myBuffs > 3 then names[#names + 1] = "…" end
    local sortLabels = { role = "Tanks first", need = "Most buffs needed", name = "Name" }
    local lines = { L[w.draft.activityLabel] .. " · " .. L[w.draft.roleLabel],
      string.format(L["Order: %s · Forecast: %ds (0 = off)"], L[sortLabels[sort]], lead),
      string.format(L["Smart priority: %s"], L[group and "On" or "Off"]) .. " · "
        .. string.format(L["Adaptive scan throttle: %s"], L[w.draft.activity == "raid" and "On" or "Off"]),
      string.format(L["Group only: %s · Group casts: %s · Pause in cities: %s"],
        L[preset.groupOnly and "On" or "Off"], L[CLASSIC_FEATURES and preset.groupCast and "On" or "Off"],
        L[preset.pauseInCities and "On" or "Off"]),
      L["Quiet alerts and the minimap status are enabled. Buff selections and keybinds are kept."],
      #names > 0 and string.format(L["Your supported buffs: %s"], table.concat(names, ", "))
        or L["No supported buffs in your spellbook."],
    }
    if db.liteMode and lead > 0 then lines[#lines + 1] = L["Forecasts are paused in Lite mode."] end
    w.body:SetText(table.concat(lines, "\n\n"))
  end
end

local function FinishSetup(w)
  if InCombatLockdown() or X.PlayerSuspended() or not w.draft or w.page ~= 3 then return end
  X.ApplyPreset(w.draft.activity)
  if not CLASSIC_FEATURES then db.groupCast = false end
  db.sortMode, db.forecastSeconds, db.smartPriority = DraftSettings(w.draft)
  db.scanThrottle = w.draft.activity == "raid"
  db.visualAlerts, db.statusMinimap, db.wizardSeen = true, true, true
  w:Hide()
  ApplyGeometry()
  ApplyAppearance()
  X.ApplyRowLayout()
  X.SettingsChanged({ forecastSeconds = true, smartPriority = true, visualAlerts = true,
    statusMinimap = true, profile = true })
  if X.RefreshConfig then X.RefreshConfig() end
  Print(L["Quick Setup complete. Run /br wizard to make new choices."])
  Print(L["Quick Setup is complete. Use /br firstcast for a guided first cast."])
end

function X.OpenWizard()
  if not db or X.PlayerSuspended() then return end
  if InCombatLockdown() then
    Print(L["Quick Setup is unavailable in combat."])
    return
  end
  local w = X.wizardFrame
  if not w then
    w = X.PanelWidget("Frame", "BuffRadarWizard", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    X.wizardFrame = w
    w:SetSize(422, 334)
    w:SetPoint("CENTER")
    w:SetClampedToScreen(true)
    w:SetFrameStrata("DIALOG")
    w:EnableMouse(true)
    if w.SetBackdrop then
      w:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 8, right = 8, top = 8, bottom = 8 } })
    end
    if w.SetBackdropColor then w:SetBackdropColor(0, 0, 0, 0.92) end
    w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    w.title:SetPoint("TOP", 0, -17)
    w.body = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    w.body:SetPoint("TOPLEFT", 20, -54)
    w.body:SetPoint("TOPRIGHT", -20, -54)
    w.body:SetJustifyH("LEFT")
    w.body:SetWordWrap(true)
    w.choice = {}
    for i = 1, 3 do
      local b = X.PanelWidget("Button", nil, w, "UIPanelButtonTemplate")
      b:SetSize(252, 28)
      b:SetPoint("TOP", w, "TOP", 0, -100 - (i - 1) * 38)
      w.choice[i] = b
    end
    w.back = X.PanelWidget("Button", nil, w, "UIPanelButtonTemplate")
    w.back:SetSize(94, 24)
    w.back:SetPoint("BOTTOMLEFT", 16, 14)
    w.back:SetText(L["Back"])
    w.back:SetScript("OnClick", function() X.WizardPage(w.page - 1) end)
    w.next = X.PanelWidget("Button", nil, w, "UIPanelButtonTemplate")
    w.next:SetSize(112, 24)
    w.next:SetPoint("BOTTOMRIGHT", -16, 14)
    w.next:SetText(L["Apply"])
    w.next:SetScript("OnClick", function() FinishSetup(w) end)
    local close = X.PanelWidget("Button", nil, w, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() w:Hide() end)
    w.close = close
    w:SetScript("OnHide", function() w.draft = nil end)
    if UISpecialFrames then table.insert(UISpecialFrames, "BuffRadarWizard") end
  end
  w.draft = {}
  X.WizardPage(1)
  w:Show()
end

-- Apply a color theme (1.8.0). Defined here because it needs
-- ApplyAppearance, which only exists from this point on.
function X.ApplyTheme(name)
  if X.CancelThemePreview then X.CancelThemePreview() end
  if name and name:lower() == "auto" and not X.SavedTheme(name) then name = X.AUTO_THEME_ID end
  local t = X.ThemeDef(name)
  if not t then return false end
  local id = name:lower()
  db.theme = X.THEMES[id] and id or t.label
  if id ~= X.AUTO_THEME_ID then db.bgColor = { t.bg[1], t.bg[2], t.bg[3] } end
  if not X.ResolveAutoTheme() then
    ApplyAppearance()
    if X.RefreshConfig then X.RefreshConfig() end
  end
  return true
end

-- Save the current look (background + the border now in effect) as one
-- of your themes (1.10.0). Returns the name, or nil plus a reason.
function X.SaveTheme(name)
  if X.CancelThemePreview then X.CancelThemePreview() end
  name = (name or ""):match("^%s*(.-)%s*$")
  if X.THEMES[name:lower()] or name:lower() == "custom" then return nil, "taken" end
  if not name:match("^[%w%-]+$") or #name > 24 then return nil, "name" end
  local c, b = X.ThemeBackground(), X.ThemeBorder()
  local entry = { name = name,
    bg = { c[1], c[2], c[3] },
    border = { b[1], b[2], b[3] } }
  db.customThemes = db.customThemes or {}
  for i, t in ipairs(db.customThemes) do
    if t.name:lower() == name:lower() then
      db.customThemes[i] = entry
      return name
    end
  end
  if #db.customThemes >= 4 then return nil, "full" end
  db.customThemes[#db.customThemes + 1] = entry
  return name
end

function X.DeleteTheme(name)
  if X.CancelThemePreview then X.CancelThemePreview() end
  if not db or not name then return false end
  for i, t in ipairs(db.customThemes or {}) do
    if t.name:lower() == name:lower() then
      table.remove(db.customThemes, i)
      if not X.THEMES[name:lower()] and (db.theme or ""):lower() == name:lower() then
        db.theme = "custom"
        ApplyAppearance()
        if X.RefreshConfig then X.RefreshConfig() end
      end
      return true
    end
  end
  return false
end

-- Watched-buff drop alert (1.5.0): your single-target buff (Earth Shield)
-- was on someone at the last scan and is gone now, while that player is
-- still around -- say so instead of silently re-offering it. The alert
-- fires once per drop: prevHolder only refills when the buff is seen on
-- someone again. A holder change (you recast it on someone else) is a
-- move, not a drop. Runs after each CollectEntries in Refresh.
-- Range watch (1.12.0): a player who needed a buff and was out of range
-- last scan, and is in range now, still needs it -> one chat line + the
-- alert sound. The game does not allow casting automatically, so this
-- only tells you; the click is yours.
function X.CheckRange()
  if not db.rangeWatch then
    wipe(X.farPrev); wipe(X.farNow); return
  end
  for i = 1, core.EntryCount() do
    local e = entries[i]
    local g = e.guid
    if g and X.farPrev[g] and not e.pet then
      local name = X.farPrev[g] == true and e.name or X.farPrev[g]
      Print(string_format(L["%s is in range now and still needs a buff."], name))
      PlayAlert("new")
    end
  end
  X.farPrev, X.farNow = X.farNow, X.farPrev
  wipe(X.farNow)
end

-- Buff-fell-off alert (1.15.0, #33): Consider's expiry tracking spots a
-- watched group buff that was up when a fight started and is gone at the
-- first scan after it; this plays the "fall" alert kind once for that
-- scan, telling a mid-fight drop apart from a fresh arrival (the
-- new-name alert cannot). Detection lands after combat because the list
-- is frozen during it -- which is also when rebuffing becomes possible.
function X.CheckFalls()
  if X.fallPending then
    X.fallPending = nil
    if db and db.fallSound then PlayAlert("fall") end
  end
end

-- /br why <name> (1.15.0): explain, in plain words, why a player is or
-- is not on the list. Reuse cast eligibility rules without updating coverage tallies.
function X.Why(name)
  if not db then return end
  local want = (name or ""):lower()
  if want == "" then return end
  local selected, best, ambiguous
  local function try(u, grp)
    if X.ReadUnitBool(UnitExists, u) ~= true or X.ReadUnitBool(UnitIsPlayer, u) ~= true
      or X.ReadUnitBool(UnitCanAssist, "player", u) == false and u ~= "player" then return end
    local f, s = Ignore.UnitNames(u)
    if not f then return end
    local fl, sl = f:lower(), (s or ""):lower()
    local score = fl == want and 3 or sl == want and 2 or fl:find(want, 1, true) and 1 or 0
    if score == 0 or best and score < best then return end
    local ok, raw = pcall(UnitGUID, u)
    local guid = ok and SafeString(raw) or nil
    if not best or score > best then
      selected, best, ambiguous = { unit = u, full = f, short = s, group = grp, guid = guid }, score, false
    elseif (guid and selected.guid and guid ~= selected.guid) or selected.full:lower() ~= fl then
      ambiguous = true
    end
  end
  local list = InRaid() and RAID or PARTY
  try("player", true)
  for i = 1, #list do try(list[i], true) end
  try("target", false)
  try("mouseover", false)
  for i = 1, #PLATES do try(PLATES[i], false) end
  if ambiguous then
    Print(L["Why: more than one player matches. Use their full name, including realm."])
    return
  end
  if not selected then
    Print(string.format(L["Why: no readable player matches '%s'. Target or mouse over them, or enable friendly nameplates with /br plates."], name))
    return
  end
  X.ExplainPlayer(selected, Print)
end

function X.ExplainPlayer(selected, emit, showUnknown)
  local unit, full, short, isGroup, guid = selected.unit, selected.full, selected.short, selected.group, selected.guid
  local disp = short or full
  local function printRule(detail)
    if CLASSIC_FEATURES then
      local rule = detail.rule or L["Rule unavailable"]
      if detail.blessing then rule = rule .. " · " .. detail.blessing end
      emit(string_format(L["Applied rule for %s: %s."], disp, rule))
    end
  end
  local function printInactiveRule()
    local ok, _, class = pcall(UnitClass, unit)
    class = ok and SafeString(class) or nil
    local assignment, source, role, _, manual = X.AssignmentForUnit(class, unit, isGroup, X.IsSelf(unit))
    printRule({ rule = X.AssignmentRuleText(class, role, source, assignment, isGroup, manual) })
  end
  if Ignore.Has(full, short) then
    printInactiveRule()
    emit(string.format(L["%s is on your ignore list, so they are never listed. /br unignore %s undoes it."], disp, disp))
    return
  end
  if X.SessionHas(full, short) then
    printInactiveRule()
    emit(string.format(L["%s is ignored for this session only (Shift+right-click on a row). It clears when you reload."], disp))
    return
  end
  local valid, isSelf = Valid(unit)
  if not valid then
    printInactiveRule()
    emit(string.format(L["%s can't be buffed right now (dead, offline, in combat, charmed or in another phase), so they are not listed."], disp))
    return
  end
  local allMiss, miss = {}, {}
  local detail = { cooldown = {}, cooldowns = {} }
  local n, unknown, checked = Missing(unit, allMiss, isGroup, isSelf, "why", detail)
  printRule(detail)
  -- The fallback aura index is rebuilt on demand after a diagnostic scan.
  X.scanUnit = nil
  if n == 0 then
    if unknown then
      emit(string.format(L["%s: buff information is unavailable."], disp))
    elseif #detail.cooldown > 0 then
      emit(string.format(L["%s needs %s, but those spells are on cooldown."], disp, table.concat(detail.cooldown, ", ")))
    elseif not checked then
      emit(disp .. (detail.assignment   and   L[": no enabled buffs apply under the selected class or role assignment."]
          or   L[": no enabled buffs apply to this player."]))
    else
      emit(string.format(L["%s already has every buff you can give them."], disp))
    end
    return
  end
  local inRange, _, rangeUnknown, rankLimited = X.FilterInRange(unit, allMiss, miss, isSelf, true)
  if showUnknown then
    if unknown then emit(L["Some buff information is unavailable."]) end
    if rangeUnknown and (inRange > 0 or rankLimited) then emit(L["Range could not be confirmed; the list may be incomplete."]) end
  end
  if inRange == 0 then
    emit(string.format(L["%s needs %s%s"], disp, table.concat(allMiss, ", "), (rankLimited
       and  L[", but no learned rank fits their level, or another needed spell is out of range."]
       or  rangeUnknown
       and  L[", but the game could not confirm cast range. Move closer and check again."]
       or  L[" but none are in cast range; move closer before buffing."])))
    return
  end
  if guid and X.failedTargets[guid] and X.failedTargets[guid] > GetTime() then
    local failure = X.lastTargetCastProblem
    emit(string.format(L["%s was temporarily skipped after a failed cast.%s Try again in a few seconds."], disp, (failure  and  failure.guid == guid  and  " " .. failure.message  or  "")))
    return
  end
  for i = 1, core.EntryCount() do
    if guid and entries[i].guid == guid then
      local visibility = X.QueueVisibility(entries, i)
      if visibility == "visible" then
        emit(string.format(L["%s is on the list (row %s), missing: %s."], disp, i, table.concat(miss, ", ")))
      elseif visibility == "overflow" then
        emit(string.format(L["%s is outside the visible rows. %s"], disp, L["Use the mouse wheel to see more rows."]))
      else
        emit(string.format(L["%s needs %s and is collected, but the row is not shown -- the role filter under the title is the usual reason."], disp, table.concat(miss, ", ")))
      end
      return
    end
  end
  if X.search and X.search ~= "" and not (disp:lower():find(X.search, 1, true)) then
    emit(string.format(L["%s needs %s, but the name finder ('%s') hides them. Clear the finder text to see everyone."], disp, table.concat(miss, ", "), X.search))
    return
  end
  if not guid then
    emit(string.format(L["%s: the game did not expose a readable player identity. Target them and check again."], disp))
    return
  end
  emit(string.format(L["%s is not on the list right now; they need: %s."], disp, table.concat(miss, ", ")))
end

function X.ExplainCurrentTarget(emit)
  local exists = X.ReadUnitBool(UnitExists, "target")
  if exists ~= true then
    emit(L[exists == false and "Select a friendly player to check." or "Current target information is unavailable."])
    return
  end
  local player = X.ReadUnitBool(UnitIsPlayer, "target")
  local self = X.IsSelf("target")
  local assist = self or X.ReadUnitBool(UnitCanAssist, "player", "target")
  if player == false or assist == false then
    emit(L["Select a friendly player to check."])
    return
  end
  local function readGUID(unit)
    local ok, guid = pcall(UnitGUID, unit)
    if ok and type(guid) == "string" and Readable(guid) and guid ~= "" then return guid end
  end
  local full, short = Ignore.UnitNames("target")
  local guid = readGUID("target")
  if player == nil or assist == nil or not full or not guid then
    emit(L["Current target information is unavailable."])
    return
  end
  local unit = "target"
  if self then
    unit = "player"
  elseif InGroup() then
    local roster = InRaid() and RAID or PARTY
    for _, member in ipairs(roster) do
      if readGUID(member) == guid then unit = member; break end
    end
  end
  X.ExplainPlayer({ unit = unit, full = full, short = short, group = unit ~= "target", guid = guid }, emit, true)
end

-- These are game settings, not frame overrides. Remember only values we
-- changed and verified, and never save them in a shareable profile.
local function WritePlateSetting(name, value, remember)
  local before = X.ReadBooleanCVar(name)
  if before == nil then return false end
  if before ~= value then
    local setter = (C_CVar and C_CVar.SetCVar) or SetCVar
    if not setter then return false end
    pcall(setter, name, value and "1" or "0")
    if X.ReadBooleanCVar(name) ~= value then return false end
    if remember and db.plateRestore[name] == nil then db.plateRestore[name] = before end
  end
  if db.plateRestore[name] == value then db.plateRestore[name] = nil end
  return true
end

function X.ChangeFriendlyNameplates(mode, emit)
  if InCombatLockdown() then emit(L["Can't change nameplate settings during combat."]); return end
  if X.PlayerSuspended() then emit(L["Nameplate settings are unavailable while dead."]); return end
  if mode == "restore" then
    if not next(db.plateRestore) then emit(L["No nameplate changes to restore."]); return end
    for name, value in pairs(db.plateRestore) do WritePlateSetting(name, value, false) end
    emit(L[next(db.plateRestore) and "Some nameplate settings could not be restored. Try again or check the game's options."
      or "Restored your previous nameplate settings."])
  elseif mode == "names" or mode == "bars" then
    local namesOnly = mode == "names"
    if not WritePlateSetting(X.friendlyPlateNamesCVar, namesOnly, true) then
      emit(L["Couldn't change friendly nameplate style. Check the game's nameplate settings."])
      return
    end
    emit(L[namesOnly and "Friendly nameplates now show names only." or "Friendly nameplates can show health bars again."])
  elseif mode == "on" or mode == "off" then
    local _, name = X.FriendlyPlatesOn()
    if not name then
      emit(L["Couldn't find a supported friendly nameplate setting on this client."])
      return
    end
    local enable = mode == "on"
    if not WritePlateSetting(name, enable, true) then
      emit(L[enable and "Couldn't turn on friendly nameplates. Check the game's nameplate settings."
        or "Couldn't turn off friendly nameplates. Check the game's nameplate settings."])
      return
    end
    if not enable then
      emit(L["Friendly nameplates turned off. Your group, target, and mouseover are still checked."])
    elseif X.ReadBooleanCVar("nameplateShowAll") == false and not WritePlateSetting("nameplateShowAll", true, true) then
      emit(L["Friendly nameplates are enabled. The game may still hide them outside combat."])
    else
      emit(L["Friendly nameplates turned on, so nearby non-group players can be listed."])
    end
  else
    emit(L["Usage: /br plates on|off|names|bars|restore"])
    return
  end
  if X.UpdateNearbyPlateControls then X.UpdateNearbyPlateControls() end
  QueueRefresh()
end

function X.CheckDrops()
  local lookup = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
  local uncertain = {}
  if db.watchDrop then
    for key, prev in pairs(X.prevHolder) do
      if not Single.holder[key] and prev.unit and X.UnitPresent(prev.unit) and lookup then
        local aura, definitive = X.QueryNamedAura(lookup, prev.unit, Single.spell[key] or key, "HELPFUL|PLAYER")
        if definitive and not aura then
          Print(string_format(L["%s dropped off %s."], Single.spell[key] or key, prev.name))
          PlayAlert("drop")
          X.Flash()
        else
          uncertain[key] = prev
        end
      end
    end
  end
  X.prevHolder = uncertain
  for key, unit in pairs(Single.holder) do
    X.prevHolder[key] = { unit = unit, name = X.UnitNameOf(unit) or unit }
  end
end

-- Copyable settings string window for /br export and /br import.
-- The recent-casts list for /br history, newest first (1.7.0).
function X.HistoryText()
  local h = db.history or {}
  if #h == 0 then
    return L["No casts recorded yet — buffs you cast through BuffRadar will be listed here."]
  end
  local lines = {}
  for i = #h, 1, -1 do
    local e = h[i]
    local when = ""
    if e.t and e.t > 0 and date then
      local okd, s = pcall(date, "%H:%M", e.t)
      if okd and s then when = s .. "  " end
    end
    lines[#lines + 1] = when .. (e.spell or "?") .. "  ->  " .. (e.who or "?")
  end
  return table.concat(lines, "\n")
end

-- Stats export (1.8.0): the cast statistics as copyable text.
function X.StatsText()
  local lines = { "BuffRadar cast statistics" }
  lines[#lines + 1] = string_format(L["Casts: %d this session, %d all-time"],
    X.sessionCasts, db.castsTotal or 0)
  if X.upTotal > 0 then
    lines[#lines + 1] = string_format(L["Coverage uptime this run: %d%% (%d of %d scans fully buffed)"],
      math_floor(100 * X.upFull / X.upTotal + 0.5), X.upFull, X.upTotal)
  end
  local srows = {}
  for k, n in pairs(db.stats or {}) do srows[#srows + 1] = { k = k, n = n } end
  table.sort(srows, function(a, b) return a.n > b.n end)
  if #srows > 0 then
    lines[#lines + 1] = "By spell:"
    for i = 1, math_min(10, #srows) do
      lines[#lines + 1] = string_format("  %s: %d", srows[i].k, srows[i].n)
    end
  end
  return table.concat(lines, "\n")
end

-- Per-buff summary (1.13.0): how many casts of each buff the group
-- still needs, biggest first. Counts everyone, ignoring the role filter.
function X.SummaryLines()
  local report = X.GroupBuffReport()
  local per = {}
  for _, person in ipairs(report.people) do
    for _, name in ipairs(person.buffs) do
      per[name] = (per[name] or 0) + 1
    end
  end
  local counts = {}
  for n, c in pairs(per) do counts[#counts + 1] = { n = n, c = c } end
  table_sort(counts, function(a, b) if a.c ~= b.c then return a.c > b.c end return a.n < b.n end)
  return counts, #report.people, X.GroupCoverageNote(report)
end

-- Discord summary (1.8.0): the group's buff state as a small markdown
-- block, ready to paste into a Discord message.
function X.DiscordText()
  local report = X.GroupBuffReport()
  local note = X.GroupCoverageNote(report)
  local lines = { "**BuffRadar — group buff check**" }
  if #report.people == 0 and not note then
    lines[#lines + 1] = "All checked buffs are present."
  elseif #report.people > 0 then
    lines[#lines + 1] = "Still needs buffs:"
    for _, person in ipairs(report.people) do
      lines[#lines + 1] = "- " .. person.name .. " — " .. table.concat(person.buffs, ", ")
    end
  end
  if note then lines[#lines + 1] = note end
  if X.upTotal >= 10 then
    lines[#lines + 1] = string_format(L["Coverage uptime this run: %d%%"],
      math_floor(100 * X.upFull / X.upTotal + 0.5))
  end
  return table.concat(lines, "\n")
end

local function ReviewText(f, lines)
  f.reviewText:SetText(table.concat(lines, "\n"))
  f.reviewChild:SetHeight(math.max(1, f.reviewText:GetStringHeight() or 1))
  f.review:SetVerticalScroll(0)
end

local function ReviewNamedProfile(f)
  local name = f.nameBox:GetText():match("^%s*(.-)%s*$")
  local valid = X.Settings.IsProfileName(name)
  local prior = valid and db.profiles[name] or nil
  local used = valid and table.concat(X.ProfileMappings(name), ", ") or ""
  local lines = { valid and string_format(L["Store as %s without loading its settings."], name)
    or L["Profile names use letters, numbers, - and _ (max 40)."] }
  if prior then lines[#lines + 1] = string_format(L["Existing profile: %s. Enter a different name to keep it."], name) end
  if used ~= "" then lines[#lines + 1] = string_format(L["Auto-profile mappings using this name: %s"], used) end
  f.reviewName, f.reviewPrior, f.reviewMappings = name, prior, used
  f.apply:SetText(L[prior and "Replace profile" or "Save profile"])
  f.apply:SetEnabled(valid and true or false)
  lines[#lines + 1] = L["Compared with your current settings (not applied):"]
  for _, line in ipairs(f.profileLines) do lines[#lines + 1] = line end
  if #f.profileLines == 0 then lines[#lines + 1] = L["No settings or plan values would change."] end
  ReviewText(f, lines)
end

local ConfigureSections
local function ReviewImport(f)
  return X.Measure("import", function()
    local parse = f.importMode == "plan" and X.ParsePlanImport
      or f.importMode == "profile" and X.ParseSharedProfile or X.ParseSettingsImport
    local draft, err = parse(f.editBox:GetText())
    if not draft then Print(err); return end
    f.draft, f.reviewDB, f.reviewSignature, f.shareScope = draft, db, nil, nil
    f.title:SetText(L["Review before applying"])
    f.editBox:ClearFocus()
    f.editBox:Hide()
    f.accept:Hide()
    f.back:Show()
    f.review:Show()
    f.apply:SetEnabled(true)
    f.apply:Show()
    if f.importMode == "profile" then
      f.profileLines = X.ReviewSettings(draft.patch)
      f.nameBox:Show()
      f.nameBox:SetText(draft.name)
      ReviewNamedProfile(f)
      ConfigureSections(f)
      return
    end
    f.apply:SetText(L["Apply locally"])
    local lines, _, scope
    if f.importMode == "plan" then lines, _, scope = X.ReviewPlan(draft)
    else lines = X.ReviewSettings(draft) end
    f.reviewSignature, f.shareScope = table.concat(lines, "\n"), scope or nil
    f.share:SetShown(f.shareScope ~= nil)
    if #lines == 0 then lines[1] = L["No settings or plan values would change."] end
    if f.importMode == "plan" then
      lines[#lines + 1] = L["Auto-profile mappings stay local, even when sharing."]
      if scope then
        local channel = scope:match("^(%u+):")
        lines[#lines + 1] = string_format(L["Apply and share sends changed assignments and blessings to %s."],
          L[channel == "RAID" and "the raid" or "the party"])
      else lines[#lines + 1] = L["Group sharing is unavailable for this review."] end
    end
    ReviewText(f, lines)
    ConfigureSections(f)
  end)
end

local function ApplyImport(f, share)
  if not f.draft or f.reviewDB ~= db or InCombatLockdown() or X.PlayerSuspended() then return end
  local ok, msg = X.Measure("import", function()
    if f.importMode == "profile" then
      local name = f.nameBox:GetText():match("^%s*(.-)%s*$")
      local lines = X.ReviewSettings(f.draft.patch)
      if name ~= f.reviewName or db.profiles[name] ~= f.reviewPrior
        or table.concat(X.ProfileMappings(name), ", ") ~= f.reviewMappings
        or table.concat(lines, "\n") ~= table.concat(f.profileLines, "\n") then
        f.profileLines = lines
        ReviewNamedProfile(f)
        return false, L["The current values changed. Review again before applying."]
      end
      return X.StoreProfile(name, f.draft.body, f.reviewPrior)
    end
    local plan = f.importMode == "plan"
    local lines = plan and X.ReviewPlan(f.draft) or X.ReviewSettings(f.draft)
    if f.reviewSignature ~= table.concat(lines, "\n") then
      ReviewImport(f)
      return false, L["The current values changed. Review again before applying."]
    end
    if plan then
      if share and not f.shareScope then return false, L["Group sharing is unavailable for this review."] end
      return X.ApplyPlan(f.draft, share and f.shareScope or nil)
    end
    X.ApplyProfile(f.draft)
    return true, L["Settings applied locally."]
  end)
  Print(msg)
  if not ok then return end
  f.completed = true
  f:Hide()
  ApplyGeometry()
  ApplyAppearance()
  X.ApplyRowLayout()
  if X.RefreshConfig then X.RefreshConfig() end
  QueueRefresh()
end

ConfigureSections=function(f)
  if f.importMode=="plan" then if f.sectionsPanel then f.sectionsPanel:Hide() end;return end
  if not f.sectionsPanel then
    local panel=CreateFrame("Frame",nil,f);panel:SetPoint("TOPLEFT",12,-35);panel:SetSize(520,105)
    f.sectionsPanel=panel
    local mode=X.PanelWidget("Button",nil,panel,"UIPanelButtonTemplate")
    mode:SetSize(250,24);mode:SetPoint("TOPLEFT",0,0)
    mode:SetScript("OnClick",function()
      if not f:IsShown() or not f.draft or InCombatLockdown() or X.PlayerSuspended() then return end
      f.sectionWhole=not f.sectionWhole;ReviewImport(f)
    end)
    f.sectionMode=mode;f.sectionChecks={}
    for index,entry in ipairs({{"appearance","Appearance"},{"alerts","Alerts"},{"buffrules","Buff Rules"}}) do
      local key,label=entry[1],entry[2]
      local check=X.PanelWidget("CheckButton",nil,panel,"UICheckButtonTemplate")
      check:SetSize(24,24);check:SetPoint("TOPLEFT",(index-1)*172,-30)
      check.label=check:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
      check.label:SetPoint("LEFT",check,"RIGHT",2,0);check.label:SetWidth(140);check.label:SetJustifyH("LEFT");check.label:SetText(L[label])
      check:SetScript("OnClick",function(self)
        if not f:IsShown() or not f.draft or f.sectionWhole or InCombatLockdown() or X.PlayerSuspended() then return end
        f.sectionSelection[key]=self:GetChecked()==true;ConfigureSections(f)
      end)
      check.dailyActivate=function()
        check:SetChecked(not check:GetChecked());check:GetScript("OnClick")(check)
      end
      f.sectionChecks[key]=check
    end
    f.sectionHint=panel:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    f.sectionHint:SetPoint("TOPLEFT",0,-60);f.sectionHint:SetWidth(520);f.sectionHint:SetHeight(42)
    f.sectionHint:SetJustifyH("LEFT");f.sectionHint:SetJustifyV("TOP");f.sectionHint:SetWordWrap(true)
  end
  f.dailyKeyboardPolicy=function(self)
    return self.review:IsShown() and not self.editBox:IsShown() and self.sectionsPanel:IsShown()
  end
  X.DailyAPI.RegisterPanel(f)
  f.buttons={f.sectionMode,f.sectionChecks.appearance,f.sectionChecks.alerts,f.sectionChecks.buffrules,
    f.apply,f.back,f.cancel,f.closeButton}
  f.sectionEpoch=(f.sectionEpoch or 0)+1
  local epoch=f.sectionEpoch
  f:SetSize(550,400);f.sectionsPanel:Show()
  X.DailyAPI.Capture(f,true)
  f.review:ClearAllPoints();f.review:SetPoint("TOPLEFT",12,-147);f.review:SetPoint("BOTTOMRIGHT",-12,65)
  f.sectionMode:SetText(L[f.sectionWhole and "Whole Profile" or "Selected Sections"])
  for key,check in pairs(f.sectionChecks) do check:SetChecked(f.sectionSelection[key]);check:SetEnabled(not f.sectionWhole) end
  f.sectionHint:SetText(L["Whole Profile keeps the complete import. Selected Sections leave identities, connections and supplies unchanged."])
  if f.sectionWhole then
    f.sectionDraft=nil
    local draft=f.draft
    f.apply:SetScript("OnClick",function(self,...)
      if f:IsShown() and f.sectionEpoch==epoch and f.draft==draft then f.wholeApply(self,...) end
    end)
    return
  end
  local selected={appearance=f.sectionSelection.appearance,alerts=f.sectionSelection.alerts,buffrules=f.sectionSelection.buffrules}
  local model=X.ProfileSections.Stage(f.editBox:GetText(),selected)
  f.sectionDraft=model;f.nameBox:Hide();f.share:Hide()
  f.apply:SetText(L["Apply Selected Sections"]);f.apply:SetEnabled(model~=nil)
  local lines=model and model.lines or {L["No sections selected."]}
  if #lines==0 then lines={L["No settings or plan values would change."]} end
  ReviewText(f,lines)
  f.apply:SetScript("OnClick",function()
    if not f:IsShown() or not f.apply:IsShown() or InCombatLockdown() or X.PlayerSuspended()
      or f.sectionEpoch~=epoch or f.sectionDraft~=model or not model then return end
    local ok=X.ProfileSections.Apply(model)
    if ok then f.completed=true;f:Hide();QueueRefresh()
    else f.sectionDraft=nil;f.apply:Disable();Print(L["The current values changed. Review again before applying."]) end
  end)
end

local function ShowPaste(f, importing)
  if f.wholeApply then f.apply:SetScript("OnClick",f.wholeApply) end
  if X.DailyAPI then X.DailyAPI.Capture(f,false) end
  if f.sectionsPanel then f.sectionsPanel:Hide() end
  f:SetSize(550,275);f.sectionDraft=nil;f.sectionEpoch=(f.sectionEpoch or 0)+1
  f.draft, f.reviewDB, f.reviewPrior, f.profileLines = nil, nil, nil, nil
  f.title:SetText(f.pasteTitle)
  f.review:Hide()
  f.nameBox:Hide()
  f.apply:Hide()
  f.share:Hide()
  f.back:Hide()
  f.accept:SetShown(importing)
  f.editBox:Show()
  f.editBox:SetFocus()
  f.editBox:HighlightText()
end

function X.ShowExport(text, forImport, titleText, mode)
  if X.PlayerSuspended() then return end
  if InCombatLockdown() then Print(L["Can't open that during combat."]); return end
  local f = X.exportFrame
  local inputParent=X.DailyAPI and X.DailyAPI.Modal()
  if not inputParent and X.WorkflowParent then inputParent=X.WorkflowParent() end
  if not inputParent and X.Daily then local host=X.Daily.Frame();if host and host:IsVisible() then inputParent=host end end
  if not f then
    f = X.PanelWidget("Frame", "BuffRadarExportFrame", UIParent,
                    BackdropTemplateMixin and "BackdropTemplate" or nil)
    X.exportFrame = f
    f:SetSize(550, 275)
    f:SetPoint("CENTER")
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    if f.SetBackdrop then
      f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      f:SetBackdropColor(0.04, 0.05, 0.09, 0.97)
      f:SetBackdropBorderColor(0.35, 0.55, 0.8, 1)
    end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 12, -10)
    local close = X.PanelWidget("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() f:Hide() end)
    f.closeButton=close
    local eb = CreateFrame("EditBox", nil, f)
    eb:SetPoint("TOPLEFT", 12, -38)
    eb:SetPoint("BOTTOMRIGHT", -12, 38)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    if eb.SetFontObject and ChatFontNormal then eb:SetFontObject(ChatFontNormal) end
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    f.editBox = eb
    f.review = CreateFrame("ScrollFrame", nil, f)
    f.review:SetPoint("TOPLEFT", 12, -36)
    f.review:SetPoint("BOTTOMRIGHT", -12, 65)
    f.review:EnableMouseWheel(true)
    f.review:SetScript("OnMouseWheel", function(self, delta)
      local scroll = math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 48))
      self:SetVerticalScroll(scroll)
    end)
    f.reviewChild = CreateFrame("Frame", nil, f.review)
    f.reviewChild:SetSize(520, 1)
    f.review:SetScrollChild(f.reviewChild)
    f.reviewText = f.reviewChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.reviewText:SetPoint("TOPLEFT")
    f.reviewText:SetWidth(520)
    f.reviewText:SetJustifyH("LEFT")
    f.nameBox = X.PanelWidget("EditBox", nil, f, "InputBoxTemplate")
    f.nameBox:SetSize(208, 22)
    f.nameBox:SetPoint("BOTTOMLEFT", 17, 38)
    f.nameBox:SetAutoFocus(false)
    f.nameBox:SetMaxLetters(40)
    f.nameBox:SetScript("OnTextChanged", function() if f.profileLines then ReviewNamedProfile(f) end end)
    f.nameBox:SetScript("OnEscapePressed", function() f:Hide() end)
    local function button(label, w, anchor, offset, action, y)
      local b = X.PanelWidget("Button", nil, f, "UIPanelButtonTemplate")
      b:SetSize(w, 22)
      b:SetPoint(anchor, offset, y or 8)
      b:SetText(L[label])
      b:SetScript("OnClick", function()
        if f:IsShown() and b:IsShown() and not InCombatLockdown() and not X.PlayerSuspended() then action() end
      end)
      return b
    end
    f.back = button("Edit paste", 135, "BOTTOMLEFT", 12, function() ShowPaste(f, true) end)
    f.share = button("Apply and share", 170, "BOTTOMRIGHT", -98, function() ApplyImport(f, true) end, 37)
    f.apply = button("Apply locally", 170, "BOTTOMRIGHT", -98, function() ApplyImport(f) end)
    f.wholeApply=f.apply:GetScript("OnClick")
    f.cancel = button("Cancel", 80, "BOTTOMRIGHT", -12, function() f:Hide() end)
    f.accept = button("Review import", 145, "BOTTOMRIGHT", -98, function()
      if f.importMode ~= "ignore" then ReviewImport(f); return end
      local ok, msg = X.IgnoreImport(f.editBox:GetText())
      Print(L[msg])
      if ok then f.completed = true; f:Hide() end
    end)
    f:SetScript("OnHide", function()
      if f.importing and not f.completed then Print(L["Import canceled."]) end
      f.sectionDraft=nil;f.sectionEpoch=(f.sectionEpoch or 0)+1
      f.draft, f.reviewDB, f.reviewPrior, f.importing, f.profileLines = nil, nil, nil, nil, nil
      f.editBox:ClearFocus()
      f.nameBox:ClearFocus()
    end)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "BuffRadarExportFrame" end
    f:Hide()
  end
  f.sectionWhole=true;f.sectionSelection={appearance=true,alerts=true,buffrules=true}
  f.sectionDraft=nil;f.sectionEpoch=(f.sectionEpoch or 0)+1
  f.dailyInputContentGeneration=(f.dailyInputContentGeneration or 0)+1
  f.importMode, f.importing, f.completed = mode or "settings", forImport, nil
  f.pasteTitle = titleText or L[forImport and "Paste a legacy BR1 settings copy, then review."
    or "Legacy BR1 settings copy (select all, copy)"]
  f.editBox:SetText(text   or   "")
  f.accept:SetText(L[f.importMode == "ignore" and "Import" or "Review import"])
  f:Show()
  ShowPaste(f, forImport and true or false)
  if X.DailyAPI and inputParent and inputParent~=f and inputParent:IsVisible() then
    f:SetFrameLevel(inputParent:GetFrameLevel()+10)
    if not (X.HostWorkflow and X.HostWorkflow(inputParent,f)) then X.DailyAPI.Suspend(inputParent,f) end
    X.DailyAPI.SetModal(f)
  end
end

function X.ShowSaveState(state)
  if state == "future" then Print(L["A newer BuffRadar save was preserved. Changes are for this session only."])
  elseif state == "overflow" then
    Print(L["Too many profiles or ignores. The original save was preserved; changes are temporary."])
    Print(L["Use /br storage delete profile <name> or /br storage delete ignore <name>, then reload."])
  end
end

function X.RequestProfileSave(name)
  if not X.Settings.IsProfileName(name) then
    Print(L["Profile names use letters, numbers, - and _ (max 40)."])
    return
  end
  local prior = db.profiles[name]
  if not prior then
    local _, msg = X.SaveProfile(name)
    Print(msg)
    if X.RefreshConfig then X.RefreshConfig() end
    return
  end
  local body = X.ProfileSnapshot()
  if not body then Print(L["These settings are too large to save as a profile."]); return end
  X.ShowExport("BuffRadar profile: " .. name .. "\n" .. body, true, L["Review before applying"], "profile")
  if X.exportFrame and X.exportFrame:IsShown() and not InCombatLockdown() then ReviewImport(X.exportFrame) end
end
