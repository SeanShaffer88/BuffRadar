-- BuffRadar - /br command parsing and dispatch.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local X = ns.X
local core = X.Core
local L = X.L

local db  -- the live settings table; read fresh by syncState (X.GetDB)
local Print, Refresh, PlayAlert = X.Print, X.Refresh, core.PlayAlert
local RefreshConfig, OpenConfig = X.RefreshConfig, X.OpenConfig
local ApplyAppearance, ApplyGeometry = X.ApplyAppearance, X.ApplyGeometry
local BuildBuffList, BuildUI, InvalidateRows = core.BuildBuffList, X.BuildUI, X.InvalidateRows
local IsOn, FriendlyPlatesOn = core.IsOn, X.FriendlyPlatesOn
local InGroup, InInstanceNow, InMajorCity = X.InGroup, core.InInstance, core.InMajorCity
local MakeMacro, OpenKeybinds = core.MakeMacro, core.OpenKeybinds
local RefreshMinimapButton = X.RefreshMinimapButton
local SpellName, UpdateCounter, QueueRefresh = core.SpellName, X.UpdateCounter, core.QueueRefresh
local myBuffs, myBlessing = core.Buffs, core.BlessingsByClass
local Ignore = X.Ignore
local BLESSINGS, BUFF_DEFS = X.BLESSINGS, X.BUFF_DEFS
local ranks = core.Ranks
local CLASSIC_FEATURES = X.classic
local MIN_WIDTH, MAX_WIDTH = X.Settings.MinWidth, X.Settings.MaxWidth
-- Simple Mode exposes only one-click buffing and the mode switches. Advanced
-- commands remain implemented and documented, but hidden from that surface.
local simpleAllowed = {
  [""]=true, show=true, hide=true, config=true, help=true, simple=true, performance=true,
  status=true, sound=true, mute=true, minimap=true, minimapstatus=true, visual=true,
  lite=true, macro=true, key=true, gamepad=true,
}
local diagnosticCommands = {
  why=true, nearby=true, apicheck=true, buffcheck=true, perf=true, diff=true, debug=true,
  support=true, selftest=true, prep=true, coverage=true, coordinate=true, buffassign=true,
  practice=true, undo=true, subgroup=true, death=true, wipe=true, ready=true,
  readypost=true, stats=true, memory=true, supplies=true, bridge=true, firstcast=true,
}
local pairs, ipairs, next, type, tonumber, tostring, pcall = pairs, ipairs, next, type, tonumber, tostring, pcall
local math_floor, math_min = math.floor, math.min
local string_format = string.format
local table_sort = table.sort
local wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

-- Read the current settings, scan and window state at command entry.
local frame, built, hasAnyBuff, sessionShow
local lastError, bookCount, nextWrapped, nextCombatDriver
local function syncState()
  db = X.GetDB()
  frame, built = X.GetFrame(), X.WindowReady()
  hasAnyBuff, sessionShow = core.HasAnyBuff(), core.SessionShow()
  lastError, bookCount = core.LastError(), core.BookCount()
  nextWrapped, nextCombatDriver = X.NextBindState()
end

local function OnOff(v) return v and ("|cff00ff00"..L["On"].."|r") or ("|cffff4040"..L["Off"].."|r") end

local function ListBuffs()
  Print(L["Buffs you can cast (toggle with /br toggle KEY):"])
  local any = false
  for _, b in ipairs(myBuffs) do
    any = true
    local ctx = db.buffContext[b.key]
    Print(string.format("  %s  -  %s (%s)  [%s]%s", b.key, b.name, b.who or "",
      OnOff(IsOn(b.key, b.default)), ctx and ("  [" .. string.format(L["%s only"],ctx) .. "]") or ""))
  end
  if next(myBlessing) then
    any = true
    local ctx = db.buffContext.BLESSINGS
    Print(string.format(L["  BLESSINGS  -  paladin blessings by class  [%s]%s"],
      OnOff(IsOn("BLESSINGS", true)), ctx and ("  [" .. string.format(L["%s only"],ctx) .. "]") or ""))
  end
  if not any then Print(L["  (none known)"]) end
end

SLASH_BUFFRADAR1 = "/br"
SLASH_BUFFRADAR2 = "/buffradar"
-- /br selftest: one paste-able block for bug reports.
-- Auto profiles (1.6.0): the context your character is in right now.
-- Instance types come from the client; "world" is grouped open world.
function X.Context()
  local t = InInstanceNow()
  if t == "raid" then return "raid" end
  if t == "party" then return "dungeon" end
  if t == "pvp" or t == "arena" then return "pvp" end
  if InGroup() then return "world" end
  return "solo"
end

-- Apply the mapped profile once per context visit so manual changes stick.
function X.AutoProfileCheck()
  db = X.GetDB()
  if not db then return end
  local ctx = X.Context()
  if X.autoCtx == ctx then return end
  X.autoCtx = ctx
  local name = db.autoProfile[ctx]
  if name then
    local ok, err = X.LoadProfile(name)
    if ok then
      Print(string.format(L["Auto profile for %s: %s"], ctx, name))
      ApplyGeometry()
      ApplyAppearance()
      X.ApplyRowLayout()
      if RefreshConfig then RefreshConfig() end
      Refresh()
    else
      Print(string.format(L["Auto profile for %s could not load '%s': %s"], ctx, name, (err  or  L["profile not found."])))
    end
  end
end

function X.SelfTest()
  if X.DiagnosticsPaused and X.DiagnosticsPaused() then return end
  local ver, build, _, iface = GetBuildInfo()
  local metadata = (_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
  local ok, version = pcall(metadata, "BuffRadar", "Version")
  version = ok and X.Readable(version) and type(version) == "string" and version or "unknown"
  Print(L["BuffRadar self-test -- paste this whole block into a bug report:"])
  Print(string.format(L["  version %s · %s edition · interface %s · client %s build %s"],
    version, CLASSIC_FEATURES and "Forever" or "Retail", tostring(iface), tostring(ver), tostring(build)))
  Print(string.format(L["  settings dbVersion %s · sort %s · cast mode %s · scale %s"],
    tostring(db.dbVersion), tostring(db.sortMode), tostring(db.castMethod), tostring(db.scale)))
  Print(string.format(L["  sync %s · requests %s · role filter %s · profiles %d · idle fade %s"],
    OnOff(db.sync), OnOff(db.requests), tostring(db.roleFilter),
    #X.ProfileNames(), tostring(db.idleFade or 0)))
  Print(string.format(L["  pill %s · queue tag %s · consumables %s · custom spells %d · buddy split %s · uptime %s"],
    OnOff(db.pill), OnOff(db.queueTag), OnOff(db.consumables), #(db.customSpells or {}),
    OnOff(db.buddySplit),
    X.upTotal > 0 and string.format("%d%%", math.floor(100 * X.upFull / X.upTotal + 0.5)) or "n/a"))
  local acount, bcount, apcount, pcount = 0, 0, 0, 0
  for _ in pairs(X.assign) do acount = acount + 1 end
  for _ in pairs(X.blessPlan) do bcount = bcount + 1 end
  for _ in pairs(db.autoProfile) do apcount = apcount + 1 end
  for _ in pairs(X.peers) do pcount = pcount + 1 end
  Print(string.format(L["  assignments %d · blessing plan %d · auto profiles %d · peers %d"],
    acount, bcount, apcount, pcount))
  local ccount = 0
  for _ in pairs(X.cover) do ccount = ccount + 1 end
  Print(string.format(L["  readypost %s · pinned %s · weapon watch %s · entry reminder %s · throttle %s · covering %d · history %d"],
    OnOff(db.readyPost), (db.pinned ~= "" and db.pinned) or "none",
    OnOff(db.weaponWatch), OnOff(db.enterFlash), OnOff(db.scanThrottle),
    ccount, #(db.history or {})))
  local ocount = 0
  for _ in pairs(db.offenders) do ocount = ocount + 1 end
  Print(string.format(L["  grow up %s · assume range %s · theme %s · find %s · bars %s · markers %s · focus %s · pets %s · aura %s · world %s · drink %s · offenders %d"],
    OnOff(db.growUp), OnOff(db.assumeRange), tostring(db.theme), OnOff(db.findBox),
    OnOff(db.durationBars), OnOff(db.raidMarkers), OnOff(db.focusWatch), OnOff(db.pets),
    OnOff(db.auraWatch), OnOff(db.worldWatch), OnOff(db.drinkWatch), ocount))
  Print(string.format(L["  two columns %s · death recap %s · wipe report %s · wizard seen %s"],
    OnOff(db.twoCol), OnOff(db.deathRecap), OnOff(db.wipeReport), OnOff(db.wizardSeen)))
  Print(string.format(L["  view %s · saved themes %d · row gap %d · icons %s · tooltips %s · buff order %d · click-through %s"],
    tostring(db.viewMode), #(db.customThemes or {}), db.rowGap or 0,
    (db.iconSize or 0) > 0 and tostring(db.iconSize) or "auto",
    tostring(db.tooltipLevel), #(db.buffPrio or {}), OnOff(db.clickThrough)))
  if #myBuffs == 0 then Print(L["  buffs found: none"]) end
  for _, b in ipairs(myBuffs) do
    local id
    for _, d in ipairs(BUFF_DEFS) do if d.key == b.key then id = d.id break end end
    id = id or b.custom
    Print(string.format(L["  buff %s: %s (spell %s, %s)"], b.key, b.name,
      tostring(id), IsOn(b.key, b.default) and "on" or "off"))
  end
  local plates = FriendlyPlatesOn()
  Print(string.format(L["  friendly nameplates: %s · plates seen %d (%d players) · in group %s"],
    plates == nil and "unknown" or (plates and "on" or "off"),
    X.platesSeen or 0, X.playersSeen or 0, tostring(InGroup())))
  Print(string.format(L["  window built %s · spec profile %s · last problem: %s"],
    tostring(built), tostring(X.spec or "none"), tostring(lastError or "none")))
end

local function ThemePriority(command)
  if command == "" or command == "panel" then
    X.OpenAutoThemePriority()
  elseif command == "list" then
    local parts = {}
    for i, entry in ipairs(X.AutoThemePriority()) do
      local palette = entry[2]
      parts[i] = string.format("%d. %s (%s)", i, X.ThemeDef(palette).label, palette)
    end
    Print(L["Auto Theme Priority"] .. ": " .. table.concat(parts, ", "))
    Print(X.AutoThemeStatus())
  elseif command == "reset" then
    X.ResetAutoThemePriority()
    Print(L["Auto Theme Priority reset."])
  else
    local action, palette = command:match("^(%a+)%s+([%w%.%-]+)$")
    if action == "up" or action == "down" then
      local moved = X.MoveAutoThemePriority(palette, action == "up" and -1 or 1)
      Print(moved   and   L["Auto Theme Priority updated."]   or   L["Could not move that Auto theme."])
    else
      Print(L["Usage: /br theme priority [panel|list|up <id>|down <id>|reset]"])
    end
  end
end

local function HandleSlash(msg)
  syncState()
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  if cmd == "actions" then X.OpenActions(); return end
  if cmd=="daily" or cmd=="prefs" then if X.ext[cmd] then X.ext[cmd](rest) end; return end
  if cmd=="matrix" then if X.Views then X.Views.ToggleMatrix() end; return end
  if cmd=="selfstrip" then if X.Views then X.Views.ToggleSelf() end; return end
  if cmd=="supplies" then
    if not X.Supplies then return end
    local action,a,b=rest:match("^(%S*)%s*(%S*)%s*(%S*)$")
    if action=="on" or action=="off" then X.Supplies.SetEnabled(action=="on")
    elseif action=="target" then X.Supplies.SetTarget(tonumber(a),tonumber(b))
    elseif action=="limits" then X.Supplies.SetLimits(tonumber(a),tonumber(b)) end
    X.Supplies.Show(); return
  end
  if cmd=="export" then X.Daily.Share(rest=="full" and "full" or "preferences"); return end
  if cmd=="profile" then
    local shared=rest:match("^share%s+(.+)$")
    if shared then X.Daily.Share("preferences",shared); return end
  end
  if (cmd == "firstcast" or cmd == "support") and X.ext[cmd] then X.ext[cmd](rest); return end
  if not X.supported then Print(L["BuffRadar requires the Forever package on Interface 16001. Casting is disabled."]); return end
  if not db then Print(L["Settings not loaded yet."]); return end
  if X.SimpleMode and X.SimpleMode() and not simpleAllowed[cmd] and X.AdvancedHidden() then return end
  if diagnosticCommands[cmd] and X.DiagnosticsPaused and X.DiagnosticsPaused() then return end
  if X.PerformanceMode and X.PerformanceMode() and cmd == "status" and rest:lower() == "export" then
    Print(L["Diagnostics are paused in Performance Mode."]); return
  end
  if (cmd == "" or cmd == "show" or cmd == "hide" or cmd == "announce"
      or cmd == "summary" or cmd == "discord") and X.PlayerSuspended() then
    return
  end
  -- Read-only diagnostics use the current queue and must not rebuild it.
  if cmd == "why" then
    if rest == "" then
      Print(L["Usage: /br why <name> - say why a player is or is not on the list"])
    else
      X.Why(rest)
    end
    return
  elseif cmd == "nearby" then
    if X.OpenNearbyDiagnostics then X.OpenNearbyDiagnostics() end
    return
  elseif cmd == "coordinate" then
    local action, argument = rest:lower():match("^(%S*)%s*(.-)$")
    if action == "panel" then
      if not CLASSIC_FEATURES then
        Print(L["Caster Coordination is available in WoW: Forever."])
      elseif InCombatLockdown() then
        Print(L["Can't do that during combat."])
      elseif not X.PlayerSuspended() then
        X.OpenCoordination()
      end
    else
      X.Coordinate(action, argument)
    end
    return
  elseif cmd == "buffassign" and rest:lower() == "preview" then
    if InCombatLockdown() then
      Print(L["Can't do that during combat."])
    elseif not CLASSIC_FEATURES then
      Print(L["Class & Role Assignments are available in WoW: Forever."])
    else
      X.OpenAssignments(true)
    end
    return
  elseif cmd == "practice" or cmd == "undo" then
    if InCombatLockdown() then
      Print(L["Can't do that during combat."])
    elseif not CLASSIC_FEATURES then
      Print(L["Class & Role Assignments are available in WoW: Forever."])
    elseif cmd == "practice" then
      X.OpenPractice()
    else
      X.RunBlockerUndo()
    end
    return
  elseif cmd == "coverage" then
    if InCombatLockdown() then
      Print(L["Can't do that during combat."])
    elseif not CLASSIC_FEATURES then
      Print(L["Coverage is available in WoW: Forever."])
    else
      X.OpenRaidCoverage()
    end
    return
  end
  if not built and not InCombatLockdown() then
    local ok, err = pcall(BuildUI)
    if not ok then Print(string.format(L["|cffff4040error building window:|r %s"], tostring(err))) end
  end

  local needsOOC = { [""]=true, show=true, hide=true, simple=true, reset=true, resetpos=true, scale=true, width=true, specscale=true, macro=true, buffassign=true }
  if needsOOC[cmd] and InCombatLockdown() then
    Print(L["Can't do that during combat."])
    return
  end

  if cmd == "" then
    if frame and frame:IsShown() then
      db.hidden, sessionShow = true, false
      core.SetSessionShow(sessionShow)
      frame:Hide()
      Print(L["Hidden."])
    else
      db.hidden, sessionShow = false, true
      core.SetSessionShow(sessionShow)
      Print(string.format(L["Shown.%s"], (hasAnyBuff  and  ""  or  L[" (No supported buffs found; try /br debug)"])))
    end
  elseif cmd == "show" then
    db.hidden, sessionShow = false, true
  elseif cmd == "hide" then
    db.hidden, sessionShow = true, false
  elseif cmd == "simple" or cmd == "performance" then
    local key, label = cmd == "simple" and "simpleMode" or "performanceMode",
      cmd == "simple" and L["Simple Mode"] or L["Performance Mode"]
    local action = rest:lower()
    if action == "on" or action == "off" then
      local enabled = action == "on"
      if X.SetPreference(key, enabled) then
        Print(string.format(L[cmd == "simple" and "Simple Mode: %s" or "Performance Mode: %s"], OnOff(enabled)))
      end
    elseif action == "" then
      Print(string.format(L[cmd == "simple" and "Simple Mode: %s" or "Performance Mode: %s"], OnOff(db[key])))
    else
      Print(L["  /br simple [on|off] · /br performance [on|off] · /br bridge - display snippets"])
    end
  elseif cmd == "config" or cmd == "options" or cmd == "settings" then
    local subcommand = rest:lower()
    if subcommand == "find" and X.OpenSettingsSearch then
      X.OpenSettingsSearch()
    elseif (subcommand == "navigate" or subcommand == "narrate") and X.OpenSettingsNavigation then
      X.OpenSettingsNavigation(subcommand == "narrate")
    else
      OpenConfig()
    end
  elseif cmd == "buffassign" then
    if not CLASSIC_FEATURES then
      Print(L["Class & Role Assignments are available in WoW: Forever."])
    elseif not X.PlayerSuspended() then
      local action = rest:lower()
      if action == "on" or action == "off" then
        X.SetAssignmentEnabled(action == "on")
        X.RefreshConfig()
        Refresh()
        Print(X.AssignmentEnabled()   and   L["Class & Role Assignments enabled."]   or   L["Class & Role Assignments disabled."])
      else
        X.OpenAssignments()
      end
    end
  elseif cmd == "group" then
    db.groupOnly = not db.groupOnly
    Print(string.format(L["Show only in a party or raid %s"], OnOff(db.groupOnly)))
  elseif cmd == "cities" then
    db.pauseInCities = not db.pauseInCities
    Print(string.format(L["Pause in major cities %s"], OnOff(db.pauseInCities)))
  elseif cmd == "sync" then
    X.SetPreference("sync", not db.sync)
    Print(string.format(L["BuffRadar cast sync %s"], OnOff(db.sync)))
  elseif cmd == "requests" then
    db.requests = not db.requests
    Print(string.format(L["Chat buff requests %s"], OnOff(db.requests)))
  elseif cmd == "digest" then
    db.joinDigest = not db.joinDigest
    Print(string.format(L["Group join summary %s"], OnOff(db.joinDigest)))
  elseif cmd == "sound" then
    db.playSound = not db.playSound
    Print(string.format(L["Droplet sound %s"], OnOff(db.playSound)))
    if db.playSound then PlayAlert() end
  elseif cmd == "soundfor" then
    local kind, choice = rest:match("^(%S+)%s*(%S*)$")
    local choices = { droplet = true, system = true, none = true }
    if kind == "master" and choices[choice] then
      db.alertSound = choice
      Print(string.format(L["Alert sound (used for every alert without its own): %s"], choice))
      if db.playSound then PlayAlert() end
    elseif (kind == "new" or kind == "drop" or kind == "ask" or kind == "fall") and choices[choice] then
      db.alertSounds[kind] = choice
      Print(string.format(L["Sound for %s alerts: %s"], kind, choice))
      PlayAlert(kind)
    else
      Print(string.format(L["Alert sound (default): %s - new name: %s - buff drop: %s - buff request: %s - buff fell off: %s"], db.alertSound, (db.alertSounds.new  or  db.alertSound), (db.alertSounds.drop  or  db.alertSound), (db.alertSounds.ask  or  db.alertSound), (db.alertSounds.fall  or  db.alertSound)))
      Print(L["Change one: /br soundfor master|new|drop|ask|fall droplet|system|none"])
    end
  elseif cmd == "prio" then
    if rest == "reset" then
      db.buffPrio = {}
      X.prioDirty = true
      Print(L["Buff order reset - your buffs are back in their normal order."])
      Refresh()
    else
      local key, posText = rest:match("^(%S+)%s+(%d+)$")
      -- the full current order: your saved order first, then the rest
      -- of your buffs in their normal order
      local order, seenK, byKey = {}, {}, {}
      for _, k in ipairs(db.buffPrio) do order[#order + 1] = k; seenK[k] = true end
      for _, b in ipairs(myBuffs) do
        byKey[b.key] = b.name
        if not seenK[b.key] then order[#order + 1] = b.key; seenK[b.key] = true end
      end
      if X.HasKnownBlessings() then
        byKey.BLESSINGS = L["Blessings"]
        if not seenK.BLESSINGS then order[#order + 1] = "BLESSINGS" end
      end
      if key then
        key = key:upper()
        local at
        for i, k in ipairs(order) do if k == key then at = i; break end end
        if not at then
          Print(string.format(L["You don't have a buff with the short name %s - /br prio lists them."], key))
        else
          table.remove(order, at)
          local pos = tonumber(posText) or 1
          if pos < 1 then pos = 1 end
          if pos > #order + 1 then pos = #order + 1 end
          table.insert(order, pos, key)
          db.buffPrio = order
          X.prioDirty = true
          Print(string.format(L["Buff order: %s is now offered number %s."], (byKey[key]  or  key), pos))
          Refresh()
        end
      else
        Print(L["Your buffs, first offered first (move one with /br prio <short name> <place>):"])
        for i, k in ipairs(order) do
          Print("  " .. i .. ". " .. (byKey[k]   or   k) .. " (" .. k .. ")")
        end
      end
    end
  elseif cmd == "view" then
    if rest == "people" or rest == "buffs" then
      db.viewMode = rest
      Print(string.format(L["List view: %s"], (rest == "buffs"
         and  L["one row per buff still needed (click a row to cast it on someone who needs it)"]
         or  L["one row per player"])))
      Refresh()
    else
      Print(string.format(L["List view is %s - change it with /br view people|buffs"], db.viewMode))
    end
  elseif cmd == "scroll" then
    if rest == "up" or rest == "down" then
      X.ScrollRows(rest == "down" and 1 or -1)
    else
      Print(L["Usage: /br scroll up|down"])
    end
  elseif cmd == "clickthrough" then
    db.clickThrough = not db.clickThrough
    X.ApplyClickThrough()
    Print(string.format(L["Click-through while the window is locked %s"], OnOff(db.clickThrough)))
  elseif cmd == "count" or cmd == "counts" then
    Print(string.format(L["Casts through BuffRadar: %d this session, %d all-time."], X.sessionCasts, db.castsTotal or 0))
  elseif cmd == "resetcount" then
    X.sessionCasts, db.castsTotal = 0, 0
    db.history = {}
    UpdateCounter()
    Print(L["Cast counts reset."])
  elseif cmd == "macro" then
    MakeMacro()
  elseif cmd == "key" or cmd == "keybind" or cmd == "gamepad" then
    OpenKeybinds()
    if cmd == "gamepad" and not InCombatLockdown() and not X.PlayerSuspended() then
      Print(L["Bind a controller button to BuffRadar's Cast next buff, or put /br macro on an action bar."])
    end
  elseif cmd == "clicks" then
    db.clickDebug = not db.clickDebug
    Print(string.format(L["Click diagnostics %s"], OnOff(db.clickDebug)))
  elseif cmd == "mode" then
    local m = rest:lower()
    -- "id" and "rank" pick a spell rank, which only the Forever edition has.
    if m == "target" or m == "macro" or (CLASSIC_FEATURES and (m == "id" or m == "rank")) then
      if InCombatLockdown() then Print(L["Can't change mode during combat."]); return end
      db.castMethod = m
      Print(string.format(L["Cast mode: %s"], m))
    elseif CLASSIC_FEATURES then
      Print(string.format(L["Usage: /br mode target|id|macro|rank   (currently %s)"], tostring(db.castMethod)))
      Print(L["  target = target the player, cast, restore your target (default)"])
      Print(L["  id = cast the chosen rank by spell ID"])
      Print(L["  macro = /cast by plain name (game picks highest rank)"])
      Print(L["  rank = /cast Name(Rank N)"])
    else
      Print(string.format(L["Usage: /br mode target|macro   (currently %s)"], tostring(db.castMethod)))
      Print(L["  target = group members directly; others: target, cast, restore your target (default)"])
      Print(L["  macro = /cast [@unit] by spell name"])
    end
  elseif cmd == "clickreg" then
    local m = rest:lower()
    if m == "both" or m == "down" or m == "up" then
      if InCombatLockdown() then Print(L["Can't change this during combat."]); return end
      db.clickReg = m
      X.ApplyRowClickRegistration()
      Print(string.format(L["Clicks trigger on: %s"], m))
    else
      Print(string.format(L["Usage: /br clickreg both|down|up   (currently %s)"], tostring(db.clickReg)))
    end
  elseif cmd == "debug" then
    local ver, build, _, iface = GetBuildInfo()
    local _, myClass = UnitClass("player")
    Print(string.format(L["client %s build %s (interface %s, %s edition), class %s, spellbook entries %d, window built %s"],
      tostring(ver), tostring(build), tostring(iface), CLASSIC_FEATURES and "Forever" or "Retail",
      tostring(myClass), bookCount, tostring(built)))
    local names = {}
    for _, b in ipairs(myBuffs) do names[#names + 1] = b.name end
    for class, b in pairs(myBlessing) do names[#names + 1] = class .. "=" .. b.name end
    Print(string.format(L["Buffs and class-default blessings: %s"], (#names > 0 and table.concat(names, ", ") or L["none"])))
    for _, b in ipairs(CLASSIC_FEATURES and myBuffs or {}) do  -- rank details: Forever only
      local list = ranks[b.name]
      if list and #list > 0 then
        local top = list[#list]
        Print(string.format(L["  %s: %d rank(s) known, top = %s, spell ID %s"], b.name, #list,
          tostring(top.sub), tostring(top.id)))
      end
    end
    local isCity, mapID, zone = InMajorCity()
    Print(string.format(L["zone: %s (map %s), major city: %s, in group: %s"], tostring(zone),
      tostring(mapID), tostring(isCity), tostring(InGroup())))
    local platesOn = FriendlyPlatesOn()
    Print(string.format(L["friendly nameplates: %s, nameplate units seen: %d (%d players)"],
      platesOn == nil and "unknown" or (platesOn and "on" or "off"),
      tonumber(X.platesSeen) or 0, tonumber(X.playersSeen) or 0))
    Print(string.format(L["keybind safety: combat driver %s, click reset %s"], (nextCombatDriver  and  L["secure"]  or  L["fallback"]), (nextWrapped  and  L["secure"]  or  L["fallback"])))
    Print(string.format(L["cast mode: %s, clickreg: %s, ActionButtonUseKeyDown=%s"], tostring(db.castMethod), tostring(db.clickReg), tostring(GetCVar and GetCVar("ActionButtonUseKeyDown"))))
    if frame then
      local p, _, rp, x, y = frame:GetPoint()
      Print(string.format(L["window shown %s, at %s %s %d %d"], tostring(frame:IsShown()),
        tostring(p), tostring(rp), x or 0, y or 0))
    end
    if lastError then Print(string.format(L["last error: %s"], tostring(lastError))) end
  elseif cmd == "lock" then
    db.locked = not db.locked
    ApplyAppearance()  -- the resize grip hides while locked
    X.ApplyClickThrough()
    Print(string.format(L["Window lock (moving and resizing) %s"], OnOff(db.locked)))
  elseif cmd == "self" then
    db.includeSelf = not db.includeSelf
    Print(string.format(L["Check yourself first (all buffs that suit you) %s"], OnOff(db.includeSelf)))
  elseif cmd == "pvp" then
    db.avoidPvP = not db.avoidPvP
    Print(string.format(L["Skip PvP-flagged players %s"], OnOff(db.avoidPvP)))
  elseif cmd == "autohide" then
    db.autoHide = not db.autoHide
    Print(string.format(L["Hide when empty %s"], OnOff(db.autoHide)))
  elseif cmd == "rebuff" then
    local key, secs = rest:match("^(%S+)%s+(%d+)$")
    if key and secs then
      key = key:upper()
      local found = CLASSIC_FEATURES and key == "BLESSINGS"
      if not found then
        for _, d in ipairs(BUFF_DEFS) do if d.key == key then found = true break end end
      end
      if found then
        local v = tonumber(secs)
        db.rebuffPer[key] = v
        Print(string.format(L["%s re-buffs when less than %d seconds remain."], key, v))
      else
        Print(L["Unknown buff key. Use /br buffs to see keys."])
      end
    else
      local n = tonumber(rest)
      if n and n >= 0 then
        db.rebuff = n
        Print(string.format(L["Re-buff (all buffs) when less than %d seconds remain."], n))
      else
        Print(string.format(L["Usage: /br rebuff <seconds>  |  /br rebuff KEY <seconds>   (all-buffs default %s)"], db.rebuff))
      end
    end
    Refresh()
  elseif cmd == "groupcast" and not CLASSIC_FEATURES then
    Print(L["Group-cast offers aren't needed here: on retail, one cast of a raid buff covers the whole group."])
  elseif cmd == "groupcast" then
    local m = rest:lower()
    local n = tonumber(m)
    if n then
      db.groupCastMin = math.max(2, math.min(40, math.floor(n)))
      Print(string.format(L["Group buffs offered when %s+ group members need the buff."], db.groupCastMin))
    elseif m == "on" then
      db.groupCast = true
      Print(L["Group-cast offers on."])
    elseif m == "off" then
      db.groupCast = false
      Print(L["Group-cast offers off."])
    else
      db.groupCast = not db.groupCast
      Print(string.format(L["Group-cast offers %s (threshold %s; set with /br groupcast <n>)"], OnOff(db.groupCast), db.groupCastMin))
    end
    Refresh()
  elseif cmd == "sort" then
    local m = rest:lower()
    if m == "name" or m == "role" or m == "distance" or m == "need" then db.sortMode = m
    elseif db.sortMode == "name" then db.sortMode = "role"
    elseif db.sortMode == "role" then db.sortMode = "distance"
    elseif db.sortMode == "distance" then db.sortMode = "need"
    else db.sortMode = "name" end
    Print(string.format(L["List order: %s%s"], db.sortMode, (db.sortMode == "role"  and  L[" (tanks & leaders first)"]  or
       db.sortMode == "distance"  and  L[" (nearest first)"]  or
       db.sortMode == "need"  and  L[" (most missing first)"]  or  "")))
    Refresh()
  elseif cmd == "filter" then
    local m = rest:upper()
    if m == "ALL" or m == "TANK" or m == "HEALER" or m == "DAMAGER" or m == "DPS" then
      db.roleFilter = (m == "DPS") and "DAMAGER" or m
      X.RefreshChips()
      Print(string.format(L["Role filter: %s (window list only)"], db.roleFilter))
    else
      Print(string.format(L["Usage: /br filter all|tank|healer|dps   (currently %s)"], tostring(db.roleFilter or "ALL")))
    end
    Refresh()
  elseif cmd == "strip" then
    db.showStrip = not db.showStrip
    X.ApplyRowLayout()
    Print(string.format(L["Buff toggle strip %s"], OnOff(db.showStrip)))
    Refresh()
  elseif cmd == "fade" then
    local n = tonumber(rest)
    if n and n >= 0 and n <= 90 then
      db.idleFade = math_floor(n)
      Print(string.format(L["Idle fade: %d%% while the mouse is away (0 = off)."], db.idleFade))
    else
      Print(string.format(L["Usage: /br fade <0-90>   (currently %s)"], tostring(db.idleFade or 0)))
    end
  elseif cmd == "mana" then
    local n = tonumber(rest)
    if n and n >= 0 and n <= 100 then
      db.lowMana = math_floor(n)
      Print(db.lowMana > 0   and
        string.format(L["Buffing pauses below %d%% mana."], db.lowMana)   or   L["Low-mana pause off."])
    else
      Print(string.format(L["Usage: /br mana <0-100> (0 = off; currently %s)"],
        tostring(db.lowMana or 0)))
    end
    Refresh()
  elseif cmd == "selftest" then
    X.SelfTest()
  elseif cmd == "compact" then
    db.compact = not db.compact
    X.ApplyRowLayout()
    Print(string.format(L["Compact rows %s"], OnOff(db.compact)))
    Refresh()
  elseif cmd == "text" then
    local n = tonumber(rest)
    if n and n >= 0.8 and n <= 1.5 then
      db.textScale = n
      X.ApplyRowLayout()
      Print(string.format(L["List text scale: %s"], tostring(n)))
    else
      Print(string.format(L["Usage: /br text <0.8 - 1.5>   (currently %s)"], tostring(db.textScale or 1)))
    end
    Refresh()
  elseif cmd == "charpoint" then
    db.charPoint = not db.charPoint
    if db.charPoint then
      local k = X.CharKey()
      if db.point then X.SaveCharacterPoint(k) end
    end
    Print(string.format(L["Per-character window position %s"], OnOff(db.charPoint)))
  elseif cmd == "export" then
    local text, err = X.Export()
    if not text then Print(err); return end
    X.ShowExport(text, false)
    Print(L["Use a named BR2 profile to share newer preferences."])
  elseif cmd == "import" then
    X.ShowExport("", true)
  elseif cmd == "profile" then
    local sub, pname = rest:match("^(%S*)%s*(.-)%s*$")
    sub = (sub or ""):lower()
    if sub == "save" then
      X.RequestProfileSave(pname)
    elseif sub == "load" then
      local ok, err = X.LoadProfile(pname)
      if ok then
        Print(string.format(L["Profile loaded: %s"], pname))
        ApplyGeometry()
        ApplyAppearance()
        X.ApplyRowLayout()
        if RefreshConfig then RefreshConfig() end
        Refresh()
      else Print(err   or   string.format(L["No profile named '%s'. /br profile list shows them."], pname)) end
    elseif sub == "delete" or sub == "del" then
      if X.DeleteProfile(pname) then Print(string.format(L["Profile deleted: %s"], pname))
      else Print(string.format(L["No profile named '%s'."], pname)) end
      if RefreshConfig then RefreshConfig() end
    elseif sub == "share" then
      local text = X.ProfileShareText(pname)
      if text then
        X.ShowExport(text, false, string.format(L["Profiles: %s"],pname))
        Print(string.format(L["Profile '%s' shown as one text — copy it and send it."], pname))
      else
        Print(string.format(L["No profile named '%s'. /br profile list shows them."], pname))
      end
    elseif sub == "import" then
      X.ShowExport("", true, L["Paste a shared profile, then review."], "profile")
    elseif sub == "diff" then
      local str = db.profiles[pname]
      if type(str) ~= "string" then Print(string.format(L["No profile named '%s'. /br profile list shows them."], pname))
      elseif X.PrintDiff then X.PrintDiff(str, string.format(L["Profiles: %s"],pname), true)
      else Print(L["Diff needs Extras.lua."]) end
    elseif sub == "list" or sub == "" then
      local names = X.ProfileNames()
      Print(#names > 0   and   (string.format(L["Profiles: %s"], table.concat(names, ", ")))
          or   L["No saved profiles yet. /br profile save <name> makes one."])
    else
      Print(L["Usage: /br profile save|load|delete|list|share|import <name>"])
    end
  elseif cmd == "plan" then
    local sub = (rest:match("^(%S*)") or ""):lower()
    if sub == "export" then
      local text, err = X.PlanExport()
      if not text then Print(err); return end
      X.ShowExport(text, false, L["Group plan copy (select all, copy)"])
      Print(L["Plan string shown — it carries assignments, the blessing plan and auto profiles, not your settings."])
    elseif sub == "import" then
      X.ShowExport("", true, L["Paste a group plan, then review."], "plan")
    else
      local acount, bcount = 0, 0
      for _ in pairs(X.assign) do acount = acount + 1 end
      for _ in pairs(X.blessPlan) do bcount = bcount + 1 end
      Print(string.format(L["Current plan: %d assignments, %d blessings. /br plan export shares it as one string."], acount, bcount))
    end
  elseif cmd == "summary" then
    local summary, people, note = X.SummaryLines()
    if #summary == 0 then Print(note   or   L["All checked buffs are present."])
    else
      Print(string_format(L["Group needs (%d %s):"], people, L[people == 1 and "person" or "people"]))
      for i = 1, math_min(#summary, 12) do Print(string_format("  %s: %d", summary[i].n, summary[i].c)) end
      if note then Print(note) end
    end
  elseif cmd == "discord" then
    X.ShowExport(X.DiscordText(), false, "BuffRadar — Discord — "..L["Copy"])
    Print(L["Discord summary shown — copy it into your Discord message."])
  elseif cmd == "storage" then
    local kind, name = rest:match("^delete%s+(%a+)%s+(.+)$")
    if kind == "profile" or kind == "ignore" then
      if X.Settings.RemovePreservedEntry(kind == "profile" and "profiles" or "ignored", name) then
        Print(L["Removed from the preserved save. Reload to try normal saving again."])
      else Print(L["No matching entry in an oversized save."]) end
    else
      X.ShowSaveState(X.Settings.SaveState())
      Print(string.format(L["Profiles: %d/%d · Ignores: %d/%d"], X.Settings.Count(db.profiles), X.Settings.Limits.profiles,
        X.Settings.Count(db.ignored), X.Settings.Limits.ignored))
    end
  elseif cmd == "offenders" then
    if rest:lower() == "clear" then
      wipe(db.offenders)
      Print(L["Repeat-offender history cleared."])
    else
      local orows = {}
      for guid, item in pairs(db.offenders) do orows[#orows + 1] = { nm = item.name, c = item.count, guid = guid } end
      table_sort(orows, function(a, b) return a.c > b.c or (a.c == b.c and a.guid < b.guid) end)
      if #orows == 0 then
        Print(L["No repeat offenders yet — a player lands here after a group session where they were seen unbuffed."])
      else
        Print(L["Repeat offenders (group sessions seen unbuffed):"])
        for i = 1, math_min(10, #orows) do
          Print(string.format("  %s: %d", orows[i].nm, orows[i].c))
        end
      end
    end
  elseif cmd == "preset" then
    local name = rest:lower()
    if X.ApplyPreset(name) then
      Print(string.format(L["Preset applied: %s (window and behavior only; buff toggles kept)."], name))
      ApplyGeometry()
      ApplyAppearance()
      X.ApplyRowLayout()
      if RefreshConfig then RefreshConfig() end
      Refresh()
    else
      Print(L["Usage: /br preset raid|dungeon|solo"])
    end
  elseif cmd == "wizard" or cmd == "quicksetup" then
    X.OpenWizard()
    return
  elseif cmd == "pill" then
    db.pill = not db.pill
    Print(string.format(L["All-buffed pill %s"], OnOff(db.pill)))
    Refresh()
  elseif cmd == "fastaura" then
    local m = rest:lower()
    if m == "on" then db.fastAura = true
    elseif m == "off" then db.fastAura = false
    else db.fastAura = not db.fastAura end
    Print(string.format(L["Fast aura updates %s -- aura changes that touch no watched buff skip the rescan (the steady refresh still runs)."], OnOff(db.fastAura)))
  elseif cmd == "modclick" then
    local m = rest:lower()
    if m == "on" then db.modClick = true
    elseif m == "off" then db.modClick = false
    else db.modClick = not db.modClick end
    Print(string.format(L["Modifier clicks %s -- Shift-click a row to cast the group version of its buff (Forever only)."], OnOff(db.modClick)))
    Refresh()
  elseif cmd == "grouppair" then
    local cg = db.customGroup
    local single, group = rest:match('^"([^"]+)"%s+"([^"]+)"$')
    if single then
      if not X.Settings.ValidGroupPair(single, group) then Print(L["Invalid group-cast pair; nothing changed."]); return end
      local count = 0
      for _ in pairs(cg) do count = count + 1 end
      if not cg[single] and count >= X.Settings.MaxGroupPairs then
        Print(L["Group-cast pair limit reached. Remove a pair first."])
        return
      end
      cg[single] = group
      Print(string.format(L["Group-cast pair set: Shift-click %s casts %s (needs /br modclick on)."], single, group))
    elseif rest:lower():sub(1, 6) == "clear " then
      local name = rest:sub(7):gsub('^"', ""):gsub('"$', "")
      if cg[name] then cg[name] = nil; Print(string.format(L["Group-cast pair removed for %s."], name))
      else Print(string.format(L["No custom group-cast pair for %s."], name)) end
    elseif rest == "" then
      local any = false
      for s, g in pairs(cg) do Print("  " .. s .. " -> " .. g); any = true end
      if not any then Print(L["No custom group-cast pairs. Add one: /br grouppair \"Single Buff\" \"Group Buff\""]) end
    else
      Print(L["Usage: /br grouppair \"Single Buff\" \"Group Buff\"  |  /br grouppair clear \"Single Buff\"  |  /br grouppair (list)"])
    end
    Refresh()
  elseif cmd == "pullflash" then
    local m = rest:lower()
    X.SetPreference("pullFlash", m == "on" or (m ~= "off" and not db.pullFlash))
    Print(string.format(L["Pull-timer flash %s -- border flash and a countdown line when a group pull timer starts (the game's /countdown or a boss-mod pull)."], OnOff(db.pullFlash)))
  elseif cmd == "ready" then
    X.ReadyViewCommand(rest:match("^%s*(.-)%s*$"):lower())
  elseif cmd == "prep" then
    X.RaidPreparationCommand(rest:lower())
    return
  elseif cmd == "subgroup" then
    if rest:match("^%s*(.-)%s*$"):lower() == "panel" and CLASSIC_FEATURES then
      X.OpenSubgroupResponsibilities()
    else
      X.SubgroupDutyCommand(rest)
    end
  elseif cmd == "fallsound" then
    local m = rest:lower()
    if m == "on" then db.fallSound = true
    elseif m == "off" then db.fallSound = false
    else db.fallSound = not db.fallSound end
    Print(string.format(L["Buff-fell-off sound %s -- a distinct alert when a watched group buff falls off during a fight."], OnOff(db.fallSound)))
  elseif cmd == "consumables" then
    db.consumables = not db.consumables
    Print(string.format(L["Consumables on the coverage line %s"], OnOff(db.consumables)))
    Refresh()
  elseif cmd == "custom" then
    local sub, arg = rest:match("^(%S*)%s*(.-)%s*$")
    sub = (sub or ""):lower()
    local id = tonumber(arg)
    if sub == "add" and X.Settings.PositiveID(id) then
      local have = false
      for _, x in ipairs(db.customSpells) do if x == id then have = true break end end
      if have then Print(L["That spell is already on the custom list."])
      elseif #db.customSpells >= 20 then Print(L["The custom list is full (20 spells)."])
      else
        db.customSpells[#db.customSpells + 1] = id
        pcall(BuildBuffList)
        Print(string.format(L["Custom spell added: %s -- watched from now on if you know it."], tostring(SpellName(id, id))))
        Refresh()
      end
    elseif sub == "remove" and id then
      local gone = false
      for i = #db.customSpells, 1, -1 do
        if db.customSpells[i] == id then table.remove(db.customSpells, i); gone = true end
      end
      if gone then
        local key = "CUSTOM" .. id
        db.enabled[key], db.rebuffPer[key] = nil, nil
        pcall(BuildBuffList)
        Print(L["Custom spell removed."])
        Refresh()
      else Print(L["That spell is not on the custom list."]) end
    elseif sub == "list" or sub == "" then
      if #db.customSpells == 0 then
        Print(L["No custom spells. /br custom add <spell ID> watches one."])
      else
        local parts = {}
        for _, x in ipairs(db.customSpells) do
          parts[#parts + 1] = tostring(SpellName(x, x)) .. " (" .. x .. ")"
        end
        Print(string.format(L["Custom spells: %s"], table.concat(parts, ", ")))
      end
    else
      Print(L["Usage: /br custom add|remove|list <spell ID>"])
    end
  elseif cmd == "assign" then
    local akey, aname = rest:match("^(%S*)%s*(.-)%s*$")
    akey = (akey or ""):upper()
    if akey == "" then
      local parts = {}
      for k, v in pairs(X.assign) do parts[#parts + 1] = k .. " -> " .. v end
      table_sort(parts)
      Print(#parts > 0   and   (string.format(L["Assignments: %s"], table.concat(parts, ", ")))
          or   L["No buff assignments. /br assign <BUFF> <name> sets one (leader or assistant)."])
    elseif akey == "CLEAR" then
      X.ClearLocalPlans("ASSIGN")
      Print(L["Assignments cleared."])
      Refresh()
    elseif not InGroup() then
      Print(L["Assignments need a group."])
    elseif not X.AmLead() then
      Print(L["Only the group leader or an assistant can set assignments."])
    elseif aname == "" then
      Print(L["Usage: /br assign <BUFF> <name>, or /br assign <BUFF> none to clear one."])
    else
      X.SetLocalPlan("ASSIGN", akey, aname:lower() ~= "none" and aname or nil)
      X.Broadcast("ASSIGN;" .. akey .. ";" .. aname)
      Print(string.format(L["Assignment: %s -> %s"], akey, aname))
      Refresh()
    end
  elseif cmd == "pin" then
    if rest == "" then
      Print(db.pinned ~= ""   and   (string.format(L["Pinned: %s  (/br pin none clears it)"], db.pinned))
          or   L["No one is pinned. /br pin <name> keeps a player at the top of the list."])
    elseif rest:lower() == "none" then
      db.pinned = ""
      Print(L["Pin cleared."])
      Refresh()
    else
      db.pinned = rest
      Print(string.format(L["Pinned %s — their row stays at the top while they need a buff."], rest))
      Refresh()
    end
  elseif cmd == "history" then
    if #(db.history or {}) == 0 then
      Print(L["No casts recorded yet — buffs you cast through BuffRadar will be listed here."])
    else
      X.ShowExport(X.HistoryText(), false, "BuffRadar — /br history — "..L["Copy"])
    end
  elseif cmd == "throttle" then
    local mode = rest:lower()
    if mode ~= "" and mode ~= "on" and mode ~= "off" then Print("/br throttle [on|off]"); return end
    X.SetPreference("scanThrottle", mode == "on" or (mode == "" and not db.scanThrottle))
    Print(string.format(L["Adaptive scan throttle: %s"], L[db.scanThrottle and "On" or "Off"]))
    if RefreshConfig then RefreshConfig() end
    return
  elseif cmd == "growup" then
    db.growUp = not db.growUp
    X.ApplyAnchor()
    Print(string.format(L["Grow the list upward %s — on: the window's bottom edge stays put and the list grows up."], OnOff(db.growUp)))
    Refresh()
  elseif cmd == "cover" then
    local parts = { "progress", "buffs", "uptime", "roster", "expiry", "world", "drink" }
    local valid = {}
    for _, k in ipairs(parts) do valid[k] = true end
    local part, mode = rest:match("^(%S+)%s*(%S*)$")
    if part and valid[part] and (mode == "on" or mode == "off") then
      if mode == "off" then db.coverParts[part] = false else db.coverParts[part] = nil end
      Print(string.format(L["Coverage line part '%s' %s."], part, mode))
      Refresh()
    elseif part then
      Print(string.format(L["Usage: /br cover <part> on|off — parts: %s."], table.concat(parts, ", ")))
    else
      local states = {}
      for _, k in ipairs(parts) do
        states[#states + 1] = k .. ((db.coverParts or {})[k] == false and " off" or " on")
      end
      Print(string.format(L["Coverage line parts: %s."], table.concat(states, ", ")))
    end
  elseif cmd == "rowcolor" then
    local rules = { "mine", "tank", "expiring", "buddy" }
    local isRule = { mine = true, tank = true, expiring = true, buddy = true }
    local rule, val = rest:match("^(%S+)%s*(%S*)$")
    if rule and isRule[rule] then
      val = (val or ""):lower()
      if val == "" then
        Print(string.format(L["Row color for '%s': %s. /br rowcolor %s <color|off> — colors: gold, sky, red, green, violet, or #rrggbb."], rule, X.RowColorName(rule), rule))
      elseif val == "off" then
        X.SetRowColor(rule, nil)
        Print(string.format(L["Row color for '%s' off."], rule))
      elseif X.ROW_PALETTE[val] then
        X.SetRowColor(rule, X.ROW_PALETTE[val])
        Print(string.format(L["Row color for '%s': %s."], rule, val))
      else
        local hex = val:gsub("^#", "")
        local r, g, b = hex:match("^(%x%x)(%x%x)(%x%x)$")
        if r then
          X.SetRowColor(rule, { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 })
          Print(string.format(L["Row color for '%s' set to #%s."], rule, hex))
        else
          Print(string.format(L["Unknown color '%s'. Use gold, sky, red, green, violet, #rrggbb — or off."], val))
        end
      end
    elseif rule then
      Print(string.format(L["Usage: /br rowcolor <rule> <color|off> — rules: %s."], table.concat(rules, ", ")))
    else
      local states = {}
      for _, r in ipairs(rules) do states[#states + 1] = r .. " " .. X.RowColorName(r) end
      Print(string.format(L["Row colors: %s. /br rowcolor <rule> <color|off> changes one."], table.concat(states, ", ")))
    end
  elseif cmd == "tooltip" then
    local m = rest:lower()
    if m == "minimal" or m == "standard" or m == "full" then
      db.tooltipLevel = m
      Print(string.format(L["Row tooltips: %s."], m))
      if RefreshConfig then RefreshConfig() end
    else
      Print(string.format(L["Usage: /br tooltip minimal|standard|full (now %s)."], (db.tooltipLevel  or  L["standard"])))
    end
  elseif cmd == "rowgap" then
    local v = tonumber(rest)
    if v and v >= 0 and v <= 8 then
      db.rowGap = math.floor(v + 0.5)
      X.ApplyRowLayout()
      Print(string.format(L["Row spacing set to %s."], db.rowGap))
      Refresh()
      if RefreshConfig then RefreshConfig() end
    else
      Print(string.format(L["Usage: /br rowgap <0-8> — extra space between the rows (now %s)."], (db.rowGap  or  0)))
    end
  elseif cmd == "iconsize" then
    local v = tonumber(rest)
    if v and (v == 0 or (v >= 10 and v <= 24)) then
      db.iconSize = math.floor(v + 0.5)
      X.ApplyRowLayout()
      InvalidateRows()
      Print(db.iconSize == 0   and   L["Buff icon size: automatic."]   or   (string.format(L["Buff icon size set to %s."], db.iconSize)))
      Refresh()
      if RefreshConfig then RefreshConfig() end
    else
      Print(string.format(L["Usage: /br iconsize <0|10-24> — 0 is automatic (now %s)."], (db.iconSize  or  0)))
    end
  elseif cmd == "twocol" then
    db.twoCol = not db.twoCol
    Print(string.format(L["Two columns when the list is long %s — on: past 8 rows the list splits into two columns."], OnOff(db.twoCol)))
    Refresh()
  elseif cmd == "find" then
    if rest == "" or rest:lower() == "off" then
      X.SetFinderText("")
      Print(L["Name finder cleared — everyone is listed again."])
    else
      X.SetFinderText(rest)
      Print(string.format(L["Name finder: only names matching '%s' are listed. /br find off clears it."], rest))
    end
    Refresh()
  elseif cmd == "findbox" then
    db.findBox = not db.findBox
    X.ApplyRowLayout()
    Print(string.format(L["Name finder box on the window %s"], OnOff(db.findBox)))
    Refresh()
  elseif cmd == "bars" then
    db.durationBars = not db.durationBars
    InvalidateRows()
    Print(string.format(L["Duration bars on rows %s — the bar shows the expiring buff's time left, as a share of 30 minutes."], OnOff(db.durationBars)))
    Refresh()
  elseif cmd == "markers" then
    db.raidMarkers = not db.raidMarkers
    InvalidateRows()
    Print(string.format(L["Raid markers on rows %s"], OnOff(db.raidMarkers)))
    Refresh()
  elseif cmd == "focus" then
    db.focusWatch = not db.focusWatch
    Print(string.format(L["Focus target watch line %s"], OnOff(db.focusWatch)))
    Refresh()
  elseif cmd == "pets" then
    db.pets = not db.pets
    Print(string.format(L["Group pets on the list %s — pets get rows for Fortitude, Mark of the Wild and Arcane Intellect."], OnOff(db.pets)))
    Refresh()
  elseif cmd == "aura" then
    if not CLASSIC_FEATURES then
      Print(L["The aura / aspect watch belongs to the Forever edition."])
    else
      db.auraWatch = not db.auraWatch
      pcall(BuildBuffList)
      Print(string.format(L["Aura / aspect watch %s — your own row flags a missing hunter aspect or paladin aura."], OnOff(db.auraWatch)))
      Refresh()
    end
  elseif cmd == "thornsoutdoors" then
    if not CLASSIC_FEATURES then return end
    local value = rest:lower()
    if value == "on" or value == "off" then
      X.SetThornsAnyClassOutdoors(value == "on")
    elseif value ~= "" then
      Print(L["Usage: /br thornsoutdoors [on|off]"])
      return
    end
    Print(L["Thorns: Any Class Outdoors"] .. " " .. OnOff(db.thornsAnyClassOutdoors))
  elseif cmd == "worldbuff" then
    if not CLASSIC_FEATURES then
      Print(L["The world-buff watch belongs to the Forever edition."])
    else
      db.worldWatch = not db.worldWatch
      Print(string.format(L["World-buff watch %s"], OnOff(db.worldWatch)))
      if db.worldWatch then
        Print(X.WorldBuffsText()   or   L["No world buffs on you right now."])
      end
      Refresh()
    end
  elseif cmd == "drink" then
    if not CLASSIC_FEATURES then
      Print(L["The drinking watch belongs to the Forever edition."])
    else
      db.drinkWatch = not db.drinkWatch
      Print(string.format(L["Healer drinking watch %s — drinking players are tagged; healers also reach the coverage line."], OnOff(db.drinkWatch)))
      Refresh()
    end
  elseif cmd == "context" then
    local key, mode = rest:match("^(%S+)%s+(%S+)$")
    key = key and key:upper()
    mode = mode and mode:lower()
    local found = key == "BLESSINGS"
    if key and not found then
      for _, d in ipairs(BUFF_DEFS) do if d.key == key then found = true break end end
    end
    if not key then
      local parts = {}
      for k, v in pairs(db.buffContext) do parts[#parts + 1] = k .. "=" .. v end
      table_sort(parts)
      Print(#parts > 0   and   (string.format(L["Buff contexts: %s"], table.concat(parts, ", ")))
          or   L["No buff contexts set. /br context KEY raid|instance|always limits a buff."])
    elseif not found then
      Print(L["Unknown buff key. Use /br buffs to see keys."])
    elseif mode == "raid" or mode == "instance" then
      db.buffContext[key] = mode
      Print(string.format(L["%s is now offered in %s only."], key, (mode == "raid"  and  L["raids"]  or  L["instances"])))
      Refresh()
    elseif mode == "always" or mode == "clear" then
      db.buffContext[key] = nil
      Print(string.format(L["%s is offered everywhere again."], key))
      Refresh()
    else
      Print(L["Usage: /br context KEY raid|instance|always"])
    end
  elseif cmd == "theme" then
    local m = rest:lower()
    if m == "preview" then
      X.OpenThemePreview()
    elseif m == "" or m == "list" then
      local parts = {}
      for _, k in ipairs(X.ThemeOrder()) do
        local current = (db.theme or ""):lower() == k:lower()
        local label = k == X.AUTO_THEME_ID and X.ThemeLabel(true) or nil
        parts[#parts + 1] = k .. (current and (label and " (" .. label .. ")" or " (current)") or "")
      end
      Print(string.format(L["Themes: %s. /br theme <name> applies one; /br theme save <name> saves your current look (up to 4)."], table.concat(parts, ", ")))
    elseif (m == "priority" and not X.SavedTheme(m)) or m:match("^priority%s") then
      ThemePriority(m:match("^priority%s+(.*)$") or "")
    elseif m:sub(1, 5) == "save " then
      local saved, why = X.SaveTheme(rest:sub(6))
      if saved then
        X.ApplyTheme(saved)
        Print(string.format(L["Theme saved as '%s' — it's in the theme cycle now. /br theme delete %s removes it."], saved, saved))
      elseif why == "full" then
        Print(L["You already have 4 saved themes — /br theme delete <name> one first."])
      elseif why == "taken" then
        Print(L["That name is taken by a built-in theme. Pick another."])
      else
        Print(L["Theme names are one word (letters, numbers, dashes), up to 24 characters."])
      end
    elseif m:sub(1, 7) == "delete " then
      local name = rest:sub(8)
      if X.DeleteTheme(name) then
        Print(string.format(L["Saved theme '%s' deleted."], name))
      else
        Print(string.format(L["No saved theme named '%s'."], name))
      end
    elseif X.ApplyTheme(m) then
      Print(string.format(L["Theme: %s"], X.ThemeLabel(true)))
    else
      Print(string.format(L["Unknown theme '%s'. /br theme lists them."], m))
    end
  elseif cmd == "weapon" then
    db.weaponWatch = not db.weaponWatch
    Print(string.format(L["Weapon enchant watch %s — your row (or the coverage line) will flag a weapon with no imbue, poison or oil."], OnOff(db.weaponWatch)))
    Refresh()
  elseif cmd == "enterflash" then
    db.enterFlash = not db.enterFlash
    Print(string.format(L["Instance-entry buff reminder %s"], OnOff(db.enterFlash)))
  elseif cmd == "readypost" then
    db.readyPost = not db.readyPost
    Print(string.format(L["Ready-check summary also posted to group chat (leader/assistant) %s"], OnOff(db.readyPost)))
  elseif cmd == "death" then
    if rest:lower() == "show" then
      if X.lastDeath then
        Print(L["Death recap from your last death:"])
        for i = 1, math_min(#X.lastDeath, 12) do Print(X.lastDeath[i]) end
        if #X.lastDeath > 12 then Print(string.format(L["  +%d more"], #X.lastDeath - 12)) end
      else
        Print(L["No death recap yet — one is recorded when you die."])
      end
    else
      db.deathRecap = not db.deathRecap
      Print(string.format(L["Death recap %s — on: dying prints who was missing buffs. /br death show reprints the last one."], OnOff(db.deathRecap)))
    end
  elseif cmd == "wipe" then
    if rest:lower() == "show" then
      if X.lastWipe then
        Print(L["Wipe report from the last wipe:"])
        for i = 1, math_min(#X.lastWipe, 12) do Print(X.lastWipe[i]) end
        if #X.lastWipe > 12 then Print(string.format(L["  +%d more"], #X.lastWipe - 12)) end
      else
        Print(L["No wipe report yet — one is recorded when a fight ends as a wipe."])
      end
    else
      db.wipeReport = not db.wipeReport
      Print(string.format(L["Post-wipe report %s — on: a fight ending with several dead prints the rebuff list. /br wipe show reprints the last one."], OnOff(db.wipeReport)))
    end
  elseif cmd == "buddy" then
    db.buddySplit = not db.buddySplit
    Print(string.format(L["Buddy list splitting %s (needs cast sync on, and another BuffRadar user in the group)"], OnOff(db.buddySplit)))
    Refresh()
  elseif cmd == "bless" then
    if not CLASSIC_FEATURES then
      Print(L["The blessing planner belongs to the Forever edition -- Retail has no blessings."])
    else
      local cls, bkey, bname = rest:match("^(%S*)%s*(%S*)%s*(.-)%s*$")
      cls = (cls or ""):upper()
      bkey = (bkey or ""):upper()
      if cls == "COMPLEMENT" then
        if bname ~= "" or (bkey ~= "" and bkey ~= "ON" and bkey ~= "OFF") then
          Print(L["Usage: /br bless complement on|off"])
        elseif bkey ~= "" and not X.SetBlessingComplement(bkey == "ON") then
          Print(L["Learn a blessing before changing this setting."])
        else
          Print(string.format(L["Complement Nearby Blessings: %s"], db.blessingComplement and L["On"] or L["Off"]))
        end
        return
      elseif cls == "PLAYER" then
        local name, key = rest:match("^%S+%s+(.+)%s+(%S+)%s*$")
        if not name then
          Print(L["Usage: /br bless player <player name> <BLESSING|DEFAULT>."])
        else
          local who, reason = X.SetBlessingException(name:match("^%s*(.-)%s*$"):lower(), key:upper())
          if who then
            Print(string.format(L["Group blessing exception: %s = %s."], who, key:upper()))
            Refresh()
          else
            Print(L[reason])
          end
        end
      elseif cls == "PREFER" then
        local key = bname:upper()
        if bkey == "" or key == "" then
          Print(L["Usage: /br bless prefer <CLASS> <BLESSING|DEFAULT>."])
        elseif X.SetBlessingPreference(bkey, key) then
          Print(string.format(L["Blessing preference: %s = %s."], bkey, key))
          if RefreshConfig then RefreshConfig() end
          Refresh()
        else
          Print(L["Choose a Forever class and a blessing you know, or DEFAULT."])
        end
      elseif cls == "" then
        local parts = {}
        for c, p in pairs(X.blessPlan) do
          parts[#parts + 1] = c .. ": " .. p.key .. " (" .. p.name .. ")"
        end
        table_sort(parts)
        Print(#parts > 0   and   (string.format(L["Blessing plan: %s"], table.concat(parts, ", ")))
            or   L["No blessing plan. /br bless <CLASS> <BLESSING> [name] sets one."])
      elseif bkey == "" then
        Print(L["Usage: /br bless <CLASS> <BLESSING> [name], or /br bless <CLASS> none to clear."])
      else
        local _, myClass = UnitClass("player")
        if not X.AmLead() and myClass ~= "PALADIN" then
          Print(L["Only the group leader, an assistant or a paladin can set the blessing plan."])
        elseif bkey == "NONE" then
          X.SetLocalPlan("BLESS", cls, nil)
          X.Broadcast("BLESS;" .. cls .. ";NONE;none")
          Print(string.format(L["Blessing plan cleared for %s."], cls))
          Refresh()
        elseif not BLESSINGS[bkey] then
          local bkeys = {}
          for k in pairs(BLESSINGS) do bkeys[#bkeys + 1] = k end
          table_sort(bkeys)
          Print(string.format(L["Unknown blessing '%s'. Known: %s."], bkey, table.concat(bkeys, ", ")))
        else
          local holder = (bname ~= "") and bname or (Ignore.UnitNames("player") or "me")
          local me = Ignore.UnitNames("player")
          X.SetLocalPlan("BLESS", cls, { key = bkey, name = holder,
            mine = me ~= nil and Ignore.Key(holder) == Ignore.Key(me) })
          X.Broadcast("BLESS;" .. cls .. ";" .. bkey .. ";" .. holder)
          Print(string.format(L["Blessing plan: %s gets %s from %s."], cls, bkey, holder))
          Refresh()
        end
      end
    end
  elseif cmd == "uptime" then
    if rest:lower() == "reset" then
      X.upTotal, X.upFull = 0, 0
      Print(L["Coverage uptime reset."])
    elseif X.upTotal == 0 then
      Print(L["Coverage uptime: no grouped scans yet this run."])
    else
      Print(string.format(L["Coverage uptime this run: %d%% (%d of %d scans fully buffed)."],
        math.floor(100 * X.upFull / X.upTotal + 0.5), X.upFull, X.upTotal))
    end
  elseif cmd == "autoprofile" then
    local ctx, pname = rest:match("^(%S*)%s*(.-)%s*$")
    ctx = (ctx or ""):lower()
    local CTX = { raid = true, dungeon = true, pvp = true, world = true, solo = true }
    if ctx == "" then
      local parts = {}
      for c in pairs(CTX) do
        if db.autoProfile[c] then parts[#parts + 1] = c .. " -> " .. db.autoProfile[c] end
      end
      table_sort(parts)
      Print(#parts > 0   and   (string.format(L["Auto profiles: %s"], table.concat(parts, ", ")))
          or   L["No auto profiles. /br autoprofile <raid|dungeon|pvp|world|solo> <profile> sets one."])
    elseif not CTX[ctx] then
      Print(L["Contexts: raid, dungeon, pvp, world (grouped, no instance), solo."])
    elseif pname == "" then
      Print(string.format(L["Usage: /br autoprofile %s <profile name>, or 'clear'."], ctx))
    elseif pname:lower() == "clear" then
      db.autoProfile[ctx] = nil
      if X.autoCtx == ctx then X.autoCtx = nil end
      Print(string.format(L["Auto profile for %s cleared."], ctx))
      if RefreshConfig then RefreshConfig() end
    elseif not db.profiles[pname] then
      Print(string.format(L["No profile named '%s'. /br profile list shows them."], pname))
    else
      db.autoProfile[ctx] = pname
      if X.autoCtx == ctx then X.autoCtx = nil end
      Print(string.format(L["Auto profile: %s loads '%s'."], ctx, pname))
      if RefreshConfig then RefreshConfig() end
      X.AutoProfileCheck()
    end
  elseif cmd == "ignore" then
    if rest == "" then Print(L["Usage: /br ignore <name> or <name-realm>  (or right-click a row)"]); return end
    if not Ignore.Valid(rest) then Print(L["That is not a player name (64 characters at most, no | or ;)."]); return end
    local added, err = Ignore.Add(rest)
    if err then Print(err); return end
    if added then
      Print(string.format(L["Ignoring %s%s"], rest, (rest:find("-", 1, true)  and  "."  or  L[" on every realm."])))
    else
      Print(string.format(L["%s is already ignored."], rest))
    end
    if RefreshConfig then RefreshConfig() end
  elseif cmd == "unignore" then
    if rest == "" then Print(L["Usage: /br unignore <name> (every realm) or <name-realm>"]); return end
    local removed = Ignore.Remove(rest)
    if #removed == 0 then
      Print(string.format(L["%s isn't on the ignore list. See /br ignorelist."], rest))
    else
      Print(string.format(L["No longer ignoring %s."], table.concat(removed, ", ")))
    end
    if RefreshConfig then RefreshConfig() end
  elseif cmd == "ignorelist" or cmd == "ignores" then
    if (rest == "export" or rest == "import") and X.ext.ignorelist then X.ext.ignorelist(rest); return end
    local names = Ignore.Sorted()
    Print(#names == 0   and   L["Ignore list is empty."]   or   (string.format(L["Ignored: %s"], table.concat(names, ", "))))
    local sess = {}
    for k in pairs(X.session) do sess[#sess + 1] = k end
    if #sess > 0 then
      table_sort(sess)
      Print(string.format(L["Session-only: %s"], table.concat(sess, ", ")))
    end
  elseif cmd == "bg" then
    db.pauseInBG = not db.pauseInBG
    Print(string.format(L["Pause in battlegrounds %s"], OnOff(db.pauseInBG)))
    Refresh()
  elseif cmd == "taxi" then
    db.pauseTaxi = not db.pauseTaxi
    Print(string.format(L["Pause on flight paths %s"], OnOff(db.pauseTaxi)))
    Refresh()
  elseif cmd == "watch" then
    db.watchDrop = not db.watchDrop
    Print(string.format(L["Single-target drop alert %s"], OnOff(db.watchDrop)))
    Refresh()
  elseif cmd == "alertsound" then
    local m = rest:lower()
    if m == "droplet" or m == "system" or m == "none" then
      db.alertSound = m
      Print(string.format(L["Alert sound: %s"], m))
      if db.playSound then PlayAlert() end
    else
      Print(string.format(L["Usage: /br alertsound droplet|system|none   (currently %s)"], tostring(db.alertSound)))
    end
  elseif cmd == "minimap" then
    db.showMinimap = not db.showMinimap
    RefreshMinimapButton()
    Print(string.format(L["Minimap button %s"], OnOff(db.showMinimap)))
  elseif cmd == "stats" then
    if rest:lower() == "memory" then X.Intel.MemoryReport(); return end
    if rest:lower() == "export" then
      X.ShowExport(X.StatsText(), false, L["Casts by spell (all-time)"])
      return
    end
    local srows = {}
    for k, n in pairs(db.stats or {}) do srows[#srows + 1] = { k = k, n = n } end
    table.sort(srows, function(a, b) return a.n > b.n end)
    if #srows == 0 then
      Print(L["No casts recorded yet."])
    else
      Print(L["Casts by spell (all-time):"])
      for i = 1, math.min(10, #srows) do
        Print(string.format("  %s: %d", srows[i].k, srows[i].n))
      end
    end
  elseif cmd == "specscale" then
    local v = rest:lower()
    if v == "on" then db.scalePerSpec = true elseif v == "off" then db.scalePerSpec = false
    else db.scalePerSpec = not db.scalePerSpec end
    if db.scalePerSpec and X.spec then db.specScales[X.spec] = db.scale end
    Print(string.format(L["Scale per specialization %s%s"], OnOff(db.scalePerSpec), (X.spec  and  (string.format(L[" (this spec: %s)"], X.spec))  or  "")))
  elseif cmd == "tagsymbols" then
    db.tagSymbols = not db.tagSymbols
    X.InvalidateTags()
    Print(string.format(L["Row tag symbols %s"], OnOff(db.tagSymbols)))
  elseif cmd == "motion" then
    db.reduceMotion = not db.reduceMotion
    Print(string.format(L["Reduced motion %s (no idle fade, no border flash)"], OnOff(db.reduceMotion)))
  elseif cmd == "rangewatch" then
    db.rangeWatch = not db.rangeWatch
    Print(string.format(L["Range watch %s"], OnOff(db.rangeWatch)))
  elseif cmd == "assumerange" then
    db.assumeRange = not db.assumeRange
    Print(string.format(L["Listing players the client will not place %s (their range shows as estimated)"], OnOff(db.assumeRange)))
    QueueRefresh()
  elseif cmd == "snap" then
    db.gripSnap = not db.gripSnap
    Print(string.format(L["Shift-snap on the scale grips %s"], OnOff(db.gripSnap)))
  elseif cmd == "scale" then
    local n = tonumber(rest)
    if n and n >= 0.5 and n <= 2 then
      db.scale = n
      ApplyGeometry()
      if RefreshConfig then RefreshConfig() end
    else
      Print(L["Usage: /br scale <0.5 - 2>"])
    end
  elseif cmd == "width" then
    local n = tonumber(rest)
    if n and n >= MIN_WIDTH and n <= MAX_WIDTH then
      db.width = math_floor(n + 0.5)
      ApplyGeometry()
      if QueueRefresh then QueueRefresh() end
    else
      Print(string.format(L["Usage: /br width <%d - %d>"], MIN_WIDTH, MAX_WIDTH))
    end
  elseif cmd == "positions" then
    if not X.PanelPositions(rest:lower()) then Print(L["Use /br positions on|off|reset."]); return end
    Print(string.format(L["Remember panel positions: %s"], L[db.rememberPanelPositions and "On" or "Off"]))
    if RefreshConfig then RefreshConfig() end
    return
  elseif cmd == "reset" or cmd == "resetpos" then
    if X.ResetWindowPosition() then
      Print(cmd == "reset"   and   L["Position reset."]   or   L["Window position reset to the default spot."])
    else
      Print(L["Can't move the buff window during combat."])
    end
  elseif cmd == "buffs" then
    ListBuffs()
  elseif cmd == "toggle" then
    local key = rest:upper()
    local found = CLASSIC_FEATURES and key == "BLESSINGS"
    local default = true
    for _, d in ipairs(BUFF_DEFS) do
      if d.key == key then found = true; default = d.on end
    end
    if not found then
      Print(L["Unknown key. Use /br buffs to see keys."])
      return
    end
    db.enabled[key] = not IsOn(key, default)
    Print(key .. " " .. OnOff(db.enabled[key]))
  elseif cmd == "announce" then
    X.Announce()
  elseif cmd == "signore" then
    if rest == "" then Print(L["Usage: /br signore <name> (ignore for this session only)"]); return end
    local k = Ignore.Key(rest)
    if X.session[k] then
      Print(string.format(L["%s is already ignored for this session."], rest))
    else
      X.session[k] = true
      Print(string.format(L["Ignoring %s for this session only (not saved)."], rest))
    end
  elseif cmd == "unsignore" then
    if rest == "" then Print(L["Usage: /br unsignore <name>"]); return end
    local k = Ignore.Key(rest)
    if X.session[k] then
      X.session[k] = nil
      Print(string.format(L["No longer ignoring %s for this session."], rest))
    else
      Print(string.format(L["%s isn't ignored for this session."], rest))
    end
  elseif cmd == "plates" then
    X.ChangeFriendlyNameplates(rest == "" and "on" or rest:lower(), Print)
    return
  elseif X.ext[cmd] then
    if X.ext[cmd](rest) then return end
  else
    if X.SimpleMode and X.SimpleMode() then
      Print(L["Simple Mode: click a row or use /br show. Use /br simple off for advanced commands."])
      return
    end
    Print(L["Commands:"])
    Print(L["  /br  - show/hide the window   (/br debug if it won't appear)"])
    Print(L["  /br config  - settings window   /br config find - search settings"])
    Print(L["  /br actions - browse searchable actions"])
    Print(L["  /br config navigate - keyboard navigation   /br config narrate - keyboard navigation with speech"])
    Print(L["  /br macro  - create a 'BuffRadar' macro that casts the next buff"])
    Print(L["  /br key  - open Key Bindings to bind 'Cast next buff'"])
    Print(L["/br gamepad - set up controller buffing"])
    Print(L["  /br sound  - toggle the water droplet alert"])
    Print(L["  /br group  - only show the window in a party or raid"])
    Print(L["  /br cities  - pause scanning in major cities"])
    Print(L["  /br count | resetcount  - show / reset cast counts"])
    Print(L["  /br lock | self (check yourself first, on by default) | pvp | autohide"])
    Print("  /br rebuff <sec> | scale <n> | reset")
    Print("  /br buffs | toggle <KEY>")
    Print(L["  /br clicks  - print what each click tries to cast"])
    Print(string.format(L["  /br mode %s  - how clicks cast (default target)"], (CLASSIC_FEATURES  and  L["target|id|macro|rank"]  or  L["target|macro"])))
    Print(L["  /br clickreg both|down|up  - which half of the click casts"])
    Print(L["Usage: /br plates on|off|names|bars|restore"])
    if CLASSIC_FEATURES then Print(L["  /br nearby  - diagnose nearby players and your current target"]) end
    if CLASSIC_FEATURES then
      Print(L["  /br groupcast [on|off|<n>]  - offer group buffs when n+ players need one"])
    end
    Print(L["  /br sort name|role|distance  - list order (role = tanks & leaders first)"])
    Print(L["  /br mana <0-100>  - pause buffing below this mana % (0 = off)"])
    Print(L["  /br export | import  - copy settings between characters as one string"])
    Print(L["  /br compact  - half-height rows   /br text <0.8-1.5>  - list text size"])
    Print(L["  /br charpoint  - per-character window position   /br selftest  - bug-report block"])
    Print(L["  /br ignore <name> | unignore <name> | ignorelist [export|import]   /br summary  - what the group still needs"])
    Print(L["  /br rebuff KEY <sec>  - per-buff rebuff timing (see /br buffs for keys)"])
    Print(L["  /br alertsound droplet|system|none  - new-name alert sound"])
    Print(L["  /br fallsound on|off  - distinct sound when a buff falls off in combat (#33)"])
    Print(L["  /br grouppair \"Single\" \"Group\"  - your own Shift-click group-cast pair"])
    Print(L["  /br why <name>  - why a player is or is not on the list"])
    Print(L["  /br announce  - post missing buffs to party/raid chat"])
    Print(L["  /br signore <name> | unsignore <name>  - ignore for this session only"])
    Print(L["  /br bg  - pause in battlegrounds   /br minimap  - toggle minimap button"])
    Print(L["  /br stats  - casts by spell (all-time)"])
    Print(L["  /br sync | requests | digest  - cast sync, chat-request markers, join summary"])
    Print(L["  /br filter all|tank|healer|dps  - role filter   /br strip  - buff toggle strip"])
    Print(L["  /br fade <0-90>  - idle fade   /br watch  - drop alert   /br taxi  - flight-path pause"])
    Print(L["  /br profile save|load|delete|list <name>  - named settings profiles"])
    Print(L["  /br profile share <name> | profile import  - share ONE profile as a text"])
    Print(L["  /br plan export|import  - share the group buff plan as one string"])
    Print(L["  /br stats export  - cast statistics as text   /br discord  - summary for Discord"])
    Print(L["  /br offenders  - repeat offenders across sessions   /br context KEY raid|instance|always"])
    Print(L["  /br assign <BUFF> <name>  - leader assigns a buff   /br buddy  - split the list"])
    if CLASSIC_FEATURES then Print(L["Use /br coordinate panel|on|off|request|need|review|publish|status|inbox|accept|decline."]) end
    Print(L["  /br readypost  - also post the ready-check summary to group chat"])
    Print(L["  /br ready show|hide|next|prev  - local ready-check details"])
    Print(L["  /br prep [personal]  - raid preparation and optional personal reminders"])
    Print(L["  /br subgroup [panel|BUFF 1,2|ALL|NONE]  - local raid subgroup responsibilities"])
    Print(L["  /br death [show]  - recap of who was missing buffs when you died"])
    Print(L["  /br wipe [show]  - rebuff report after a wipe"])
    Print(L["  /br pin <name>  - keep a player at the top   /br pin none  - clear the pin"])
    Print(L["  /br weapon  - watch your weapon enchant   /br enterflash  - instance-entry reminder"])
    Print(L["  /br history  - your recent casts   /br throttle [on|off]  - adaptive UI sweep"])
    Print(L["  /br forecast [seconds|off|timer] · /br smartprio · /br debuff · /br readiness"])
    Print(L["  /br minimapstatus · /br visual · /br lite · /br stats memory · /br status [export] · /br feedback"])
    Print(L["  /br simple [on|off] · /br performance [on|off] · /br bridge - display snippets"])
    Print(L["  /br growup  - list grows upward   /br theme <name>  - color theme"])
    Print(L["  Combat safety: the list hides and buff buttons are disabled until combat ends."])
    Print(L["  /br find <text> | findbox  - name finder   /br bars  - duration bars   /br markers  - raid markers"])
    Print(L["  /br scroll up|down  - move through a long buff list"])
    Print(L["  /br focus  - focus target watch line"])
    Print(L["  /br pets  - list group pets   /br context KEY raid|instance|always  - limit a buff"])
    if CLASSIC_FEATURES then
      Print(L["  /br aura  - aura/aspect watch   /br worldbuff  - world-buff watch   /br drink  - drinking healers"])
      Print(L["  /br thornsoutdoors [on|off]  - offer Thorns to any class in the open world"])
    end
    Print(L["  /br pill  - all-buffed pill   /br consumables  - flask/food counts"])
    Print(L["  /br custom add|remove|list <id>  - watch any buff spell you know"])
    Print(L["  /br uptime  - coverage uptime %   /br preset raid|dungeon|solo"])
    Print(L["  /br wizard (or /br quicksetup) - choose an activity and role"])
    Print(L["  /br theme save <name>  - save your current colors as a theme"])
    Print(L["Usage: /br theme priority [panel|list|up <id>|down <id>|reset]"])
    Print("  /br rowgap <0-8> | iconsize <0|10-24>")
    Print(L["  /br cover <part> on|off  - pick what the coverage line shows"])
    Print(L["  /br rowcolor <rule> <color|off>  - colored marks on rows"])
    Print(L["  /br tooltip minimal|standard|full  - row tooltip detail"])
    Print(L["  /br autoprofile <context> <profile>  - load a profile by context"])
    if CLASSIC_FEATURES then
      Print(L["  /br bless <CLASS> <BLESSING> [name]  - blessing planner"])
      Print(L["Usage: /br bless complement on|off"])
      Print(L["  /br buffassign [on|off|preview]  - class and role buff assignments"])
      Print(L["  /br practice · /br undo  - practice blocker edits or undo the last one"])
      Print(L["  /br coverage  - read-only buff coverage by raid subgroup"])
    end
    Print(L["  /br specscale  - remember the scale per specialization   /br snap  - Shift-snap the scale grips"])
    Print(L["  /br tagsymbols | motion | rangewatch  - tag symbols, reduced motion, tell me when someone walks into range"])
    Print(L["  /br assumerange  - list players when this client refuses to report range (see /br apicheck)"])
    Print(L["  /br apicheck [export] | buffcheck | perf  - diagnostics   /br profile diff <name>  - what a profile would change"])
    Print(L["  /br width <180-400>  - list width"])
    Print(L["  /br resetpos  - reset the window position"])
  end
  Refresh()
end

X.OnOff = OnOff
SlashCmdList.BUFFRADAR = function(msg)
  local ordinary={self=true,group=true,cities=true,pvp=true,autohide=true,scale=true,width=true,
    mode=true,rebuff=true,sort=true,sound=true,strip=true,compact=true,text=true,fade=true,
    rowgap=true,iconsize=true,tooltip=true,bars=true,markers=true,toggle=true,theme=true}
  local cmd=(msg or ""):match("^%s*(%S+)") or ""
  local function dispatch()
    if ordinary[cmd:lower()] and X.Preferences then
      X.Preferences.Capture(function() HandleSlash(msg) end,"slash")
    else HandleSlash(msg) end
  end
  local ok, err = pcall(dispatch)
  if not ok then Print(string.format(L["|cffff4040error:|r %s"], tostring(err))) end
end
