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
local math_min, math_max, math_floor = math.min, math.max, math.floor
local string_format = string.format
local table_sort = table.sort
local wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
local GetTime, InCombatLockdown = GetTime, InCombatLockdown
local UnitExists, UnitGUID, UnitClass = UnitExists, UnitGUID, UnitClass
local UnitIsPlayer, UnitCanAssist = UnitIsPlayer, UnitCanAssist

---------------------------------------------------------------------------
-- Setup wizard (1.9.0): a three-page first-run walkthrough — play
-- style (a shipped preset), window look, and your buff list — so a
-- new user lands on sane settings without facing the full settings
-- window cold. /br wizard runs it again at any time. Defined here:
-- it needs ApplyGeometry / ApplyAppearance, which exist from here on.
---------------------------------------------------------------------------
function X.WizardPage(n)
  local w = X.wizardFrame
  if not w then return end
  w.page = n
  for i = 1, 3 do w.choice[i]:Hide() end
  w.back:SetShown(n > 1)
  if n == 1 then
    w.title:SetText("BuffRadar setup — step 1 of 3")
    w.body:SetText("How do you mostly play? Each answer applies a starting preset; every setting can be changed later in Settings.")
    local styles = {
      { "Mostly solo", "solo" }, { "In a party", "dungeon" }, { "In raids", "raid" },
    }
    for i, s in ipairs(styles) do
      local b = w.choice[i]
      b:SetText(s[1])
      b:SetScript("OnClick", function()
        if X.ApplyPreset(s[2]) then
          ApplyGeometry()
          ApplyAppearance()
          X.ApplyRowLayout()
          if X.RefreshConfig then X.RefreshConfig() end
          if QueueRefresh then QueueRefresh() end
          Print("Setup wizard: the " .. s[2] .. " preset is applied.")
        end
        X.WizardPage(2)
      end)
      b:Show()
    end
    w.next:Hide()
  elseif n == 2 then
    w.title:SetText("BuffRadar setup — step 2 of 3")
    w.body:SetText("The window's look. Click the theme button to cycle the color schemes; scale, width and more live in Settings > Window.")
    local b = w.choice[1]
    local function themeLabel()
      return "Theme: " .. X.ThemeLabel(true)
    end
    b:SetText(themeLabel())
    b:SetScript("OnClick", function()
      local order = X.ThemeOrder()
      local cur = 1
      for i, k in ipairs(order) do if k:lower() == (db.theme or ""):lower() then cur = i end end
      X.ApplyTheme(order[cur % #order + 1])
      if X.RefreshConfig then X.RefreshConfig() end
      b:SetText(themeLabel())
    end)
    b:Show()
    w.next:SetText("Next")
    w.next:Show()
  else
    w.title:SetText("BuffRadar setup — step 3 of 3")
    local names = {}
    for _, bf in ipairs(myBuffs) do names[#names + 1] = bf.name end
    w.body:SetText(#names > 0
      and ("You can cast: " .. table.concat(names, ", ")
        .. ". Toggle any of them in Settings > Buffs, or with /br toggle <KEY>."
        .. " Press Finish — then just click a name on the list to buff them.")
      or "You don't know any buffs BuffRadar handles yet; the list appears once you learn one. Press Finish to close.")
    local b = w.choice[1]
    b:SetText("Open settings")
    b:SetScript("OnClick", function() X.OpenConfig() end)
    b:Show()
    w.next:SetText("Finish")
    w.next:Show()
  end
  w.pageText:SetText("Step " .. n .. " of 3")
end

function X.OpenWizard()
  if not db or X.PlayerSuspended() then return end
  if InCombatLockdown() then
    Print("The setup wizard can't open during combat — try again when it ends.")
    return
  end
  local w = X.wizardFrame
  if not w then
    w = CreateFrame("Frame", "BuffRadarWizard", UIParent, "BackdropTemplate")
    X.wizardFrame = w
    w:SetSize(370, 260)
    w:SetPoint("CENTER")
    w:SetFrameStrata("DIALOG")
    if w.SetBackdrop then
      w:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 8, right = 8, top = 8, bottom = 8 } })
    end
    if w.SetBackdropColor then w:SetBackdropColor(0, 0, 0, 0.9) end
    w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    w.title:SetPoint("TOP", 0, -16)
    w.body = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    w.body:SetPoint("TOPLEFT", 20, -48)
    w.body:SetPoint("TOPRIGHT", -20, -48)
    w.body:SetJustifyH("LEFT")
    w.body:SetWordWrap(true)
    w.pageText = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w.pageText:SetPoint("BOTTOM", 0, 16)
    w.choice = {}
    for i = 1, 3 do
      local b = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
      b:SetSize(210, 24)
      b:SetPoint("TOP", w, "TOP", 0, -104 - (i - 1) * 32)
      w.choice[i] = b
    end
    w.back = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    w.back:SetSize(90, 22)
    w.back:SetPoint("BOTTOMLEFT", 16, 12)
    w.back:SetText("Back")
    w.back:SetScript("OnClick", function() X.WizardPage(math_max(1, (w.page or 1) - 1)) end)
    w.next = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    w.next:SetSize(110, 22)
    w.next:SetPoint("BOTTOMRIGHT", -16, 12)
    w.next:SetScript("OnClick", function()
      if (w.page or 1) >= 3 then
        db.wizardSeen = true
        w:Hide()
        Print("Setup done — /br wizard runs it again, /br config opens all settings.")
      else
        X.WizardPage((w.page or 1) + 1)
      end
    end)
    local close = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    close:SetSize(24, 24)
    close:SetText("X")
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetScript("OnClick", function()
      db.wizardSeen = true
      w:Hide()
    end)
  end
  X.WizardPage(1)
  w:Show()
end

-- Apply a color theme (1.8.0). Defined here because it needs
-- ApplyAppearance, which only exists from this point on.
function X.ApplyTheme(name)
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
    if g and X.farPrev[g] and not e.outOfRange and not e.pet then
      local name = X.farPrev[g] == true and e.name or X.farPrev[g]
      Print(string_format("%s is in range now and still needs a buff.", name))
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
    Print("Why: more than one player matches. Use their full name, including realm.")
    return
  end
  if not selected then
    Print("Why: no readable player matches '" .. name .. "'. Target or mouse over them, or enable friendly nameplates with /br plates.")
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
    emit(disp .. " is on your ignore list, so they are never listed. /br unignore " .. disp .. " undoes it.")
    return
  end
  if X.SessionHas(full, short) then
    printInactiveRule()
    emit(disp .. " is ignored for this session only (Shift+right-click on a row). It clears when you reload.")
    return
  end
  local valid, isSelf = Valid(unit)
  if not valid then
    printInactiveRule()
    emit(disp .. " can't be buffed right now (dead, offline, in combat, charmed or in another phase), so they are not listed.")
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
      emit(disp .. ": buff information is unavailable.")
    elseif #detail.cooldown > 0 then
      emit(disp .. " needs " .. table.concat(detail.cooldown, ", ") .. ", but those spells are on cooldown.")
    elseif not checked then
      emit(disp .. (detail.assignment and ": no enabled buffs apply under the selected class or role assignment."
        or ": no enabled buffs apply to this player."))
    else
      emit(disp .. " already has every buff you can give them.")
    end
    return
  end
  local inRange, _, rangeUnknown, rankLimited = X.FilterInRange(unit, allMiss, miss, isSelf, true)
  if showUnknown then
    if unknown then emit(L["Some buff information is unavailable."]) end
    if rangeUnknown and (inRange > 0 or rankLimited) then emit(L["Range could not be confirmed; the list may be incomplete."]) end
  end
  if inRange == 0 then
    emit(disp .. " needs " .. table.concat(allMiss, ", ") .. (rankLimited
      and ", but no learned rank fits their level, or another needed spell is out of range."
      or rangeUnknown
      and ", but the game could not confirm cast range. Move closer and check again."
      or " but none are in cast range; move closer before buffing."))
    return
  end
  if guid and X.failedTargets[guid] and X.failedTargets[guid] > GetTime() then
    local failure = X.lastTargetCastProblem
    emit(disp .. " was temporarily skipped after a failed cast."
      .. (failure and failure.guid == guid and " " .. failure.message or "") .. " Try again in a few seconds.")
    return
  end
  for i = 1, core.EntryCount() do
    if guid and entries[i].guid == guid then
      local visibility = X.QueueVisibility(entries, i)
      if visibility == "visible" then
        emit(disp .. " is on the list (row " .. i .. "), missing: " .. table.concat(miss, ", ") .. ".")
      elseif visibility == "overflow" then
        emit(disp .. " is outside the visible rows. " .. L["Use the mouse wheel to see more rows."])
      else
        emit(disp .. " needs " .. table.concat(miss, ", ") .. " and is collected, but the row is not shown -- the role filter under the title is the usual reason.")
      end
      return
    end
  end
  if X.search and X.search ~= "" and not (disp:lower():find(X.search, 1, true)) then
    emit(disp .. " needs " .. table.concat(miss, ", ") .. ", but the name finder ('" .. X.search .. "') hides them. Clear the finder text to see everyone.")
    return
  end
  if not guid then
    emit(disp .. ": the game did not expose a readable player identity. Target them and check again.")
    return
  end
  emit(disp .. " is not on the list right now; they need: " .. table.concat(miss, ", ") .. ".")
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
          Print(string_format("%s dropped off %s.", Single.spell[key] or key, prev.name))
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
    return "No casts recorded yet. Buffs you cast through BuffRadar will be listed here."
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
  lines[#lines + 1] = string_format("Casts: %d this session, %d all-time",
    X.sessionCasts, db.castsTotal or 0)
  if X.upTotal > 0 then
    lines[#lines + 1] = string_format("Coverage uptime this run: %d%% (%d of %d scans fully buffed)",
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
    lines[#lines + 1] = string_format("Coverage uptime this run: %d%%",
      math_floor(100 * X.upFull / X.upTotal + 0.5))
  end
  return table.concat(lines, "\n")
end

function X.ShowExport(text, forImport, titleText, mode)
  if X.PlayerSuspended() then return end
  if InCombatLockdown() then Print("Can't open that during combat."); return end
  local f = X.exportFrame
  if not f then
    f = CreateFrame("Frame", "BuffRadarExportFrame", UIParent,
                    BackdropTemplateMixin and "BackdropTemplate" or nil)
    X.exportFrame = f
    f:SetSize(440, 150)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    if f.SetBackdrop then
      f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
      })
      f:SetBackdropColor(0.04, 0.05, 0.09, 0.97)
      f:SetBackdropBorderColor(0.35, 0.55, 0.8, 1)
    end
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 12, -10)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() f:Hide() end)
    local eb = CreateFrame("EditBox", nil, f)
    eb:SetPoint("TOPLEFT", 12, -34)
    eb:SetPoint("BOTTOMRIGHT", -12, 36)
    eb:SetMultiLine(true)
    if eb.SetAutoFocus then eb:SetAutoFocus(false) end
    if eb.SetFontObject and ChatFontNormal then eb:SetFontObject(ChatFontNormal) end
    eb:SetScript("OnEscapePressed", function(self) if self.ClearFocus then self:ClearFocus() end end)
    f.editBox = eb
    local acc = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    acc:SetSize(110, 22)
    acc:SetPoint("BOTTOMRIGHT", -12, 8)
    acc:SetText("Import")
    acc:SetScript("OnClick", function()
      local ok, msg
      if f.importMode == "plan" then
        ok, msg = X.PlanImport(f.editBox:GetText())
      elseif f.importMode == "profile" then
        ok, msg = X.ProfileImport(f.editBox:GetText())
      elseif f.importMode == "ignore" then
        ok, msg = X.IgnoreImport(f.editBox:GetText())
      else
        local txt = f.editBox:GetText()
        if X.PrintDiff then X.PrintDiff(txt, "This import") end  -- what it changes, before it does (1.12.0)
        ok, msg = X.Import(txt)
      end
      Print(msg)
      if ok then
        f:Hide()
        ApplyGeometry()
        ApplyAppearance()
        if X.RefreshConfig then X.RefreshConfig() end
        if QueueRefresh then QueueRefresh() end
      end
    end)
    f.accept = acc
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "BuffRadarExportFrame" end
    f:Hide()
  end
  f.title:SetText(titleText or (forImport and "BuffRadar -- paste a settings string, then Import"
                             or "BuffRadar -- your settings string (select all, copy)"))
  f.importMode = mode or "settings"  -- what the Import button applies (1.8.0)
  f.editBox:SetText(text or "")
  f.accept:SetShown(forImport and true or false)
  f:Show()
  if f.editBox.SetFocus then f.editBox:SetFocus() end
  if f.editBox.HighlightText then f.editBox:HighlightText() end
end
