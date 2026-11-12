-- BuffRadar - Slash: every /br command (HandleSlash and its helpers:
-- OnOff, ListBuffs, X.Context, X.AutoProfileCheck, X.SelfTest).
-- Loaded after BuffRadar.lua and Config.lua through the .toc. This is
-- file-split Slice C (1.15.0): the code below is the slash do-block that
-- used to sit at the bottom of BuffRadar.lua, moved verbatim; it reaches
-- the main file's locals through X.slashAPI, which BuffRadar.lua fills
-- in before this file loads. State the main file owns and reassigns
-- (the window, its grip, build/session flags) is re-read through
-- syncState() at each command, so nothing here can go stale.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, NS = ...
NS = NS or {}
local X = NS.X or {}
NS.X = X
local A = X.slashAPI or {}

local db  -- the live settings table; read fresh by syncState (X.GetDB)
local Print, Refresh, PlayAlert = A.Print, A.Refresh, A.PlayAlert
local RefreshConfig, OpenConfig = A.RefreshConfig, A.OpenConfig
local ApplyAppearance, ApplyGeometry = A.ApplyAppearance, A.ApplyGeometry
local BuildBuffList, BuildUI, InvalidateRows = A.BuildBuffList, A.BuildUI, A.InvalidateRows
local IsOn, FriendlyPlatesOn = A.IsOn, A.FriendlyPlatesOn
local InGroup, InInstanceNow, InMajorCity = A.InGroup, A.InInstanceNow, A.InMajorCity
local MakeMacro, OpenKeybinds = A.MakeMacro, A.OpenKeybinds
local RefreshMinimapButton, RestorePosition = A.RefreshMinimapButton, A.RestorePosition
local SpellName, UpdateCounter, QueueRefresh = A.SpellName, A.UpdateCounter, A.QueueRefresh
local myBuffs, myBlessing = A.myBuffs, A.myBlessing
local Single, Ignore = A.Single, A.Ignore
local ALL, BLESSINGS, BUFF_DEFS = A.ALL, A.BLESSINGS, A.BUFF_DEFS
local entries, seen, known, ranks, rows = A.entries, A.seen, A.known, A.ranks, A.rows
local CLASSIC_FEATURES = A.CLASSIC_FEATURES
local MAX_WIDTH, MIN_WIDTH = A.MAX_WIDTH, A.MIN_WIDTH
local pairs, ipairs, next, type, tonumber, tostring, pcall = pairs, ipairs, next, type, tonumber, tostring, pcall
local math_floor, math_min = math.floor, math.min
local string_format = string.format
local table_sort = table.sort
local wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

-- State owned by BuffRadar.lua; refreshed at every command entry.
local frame, grip, built, hasAnyBuff, sessionShow
local lastError, bookCount, nextWrapped, nextCombatDriver
local function syncState()
  db = X.GetDB()
  local s = A.getState()
  frame, grip, built, hasAnyBuff, sessionShow = s.frame, s.grip, s.built, s.hasAnyBuff, s.sessionShow
  lastError, bookCount, nextWrapped, nextCombatDriver = s.lastError, s.bookCount, s.nextWrapped, s.nextCombatDriver
end

local function OnOff(v) return v and "|cff00ff00on|r" or "|cffff4040off|r" end

local function ListBuffs()
  Print("Buffs you can cast (toggle with /br toggle KEY):")
  local any = false
  for _, b in ipairs(myBuffs) do
    any = true
    local ctx = db.buffContext[b.key]
    Print(string.format("  %s  -  %s (%s)  [%s]%s", b.key, b.name, b.who or "",
      OnOff(IsOn(b.key, b.default)), ctx and ("  [" .. ctx .. " only]") or ""))
  end
  if next(myBlessing) then
    any = true
    local ctx = db.buffContext.BLESSINGS
    Print(string.format("  BLESSINGS  -  paladin blessings by class  [%s]%s",
      OnOff(IsOn("BLESSINGS", true)), ctx and ("  [" .. ctx .. " only]") or ""))
  end
  if not any then Print("  (none known)") end
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

-- Load the profile mapped to the current context, if any. Only fires on
-- a context change, and only once per context+profile pair, so standing
-- in a dungeon never reloads over your manual changes.
function X.AutoProfileCheck()
  db = X.GetDB()
  if not db or not next(db.autoProfile) then return end
  local ctx = X.Context()
  if X.autoCtx == ctx then return end
  X.autoCtx = ctx
  local name = db.autoProfile[ctx]
  if name and db.profiles[name] and X.lastAutoProfile ~= ctx .. ":" .. name then
    X.lastAutoProfile = ctx .. ":" .. name
    if X.LoadProfile(name) then
      Print("Auto profile for " .. ctx .. ": " .. name)
      ApplyGeometry()
      ApplyAppearance()
      X.ApplyRowLayout()
      if RefreshConfig then RefreshConfig() end
      Refresh()
    end
  end
end

function X.SelfTest()
  local ver, build, _, iface = GetBuildInfo()
  Print("BuffRadar self-test -- paste this whole block into a bug report:")
  Print(string.format("  version %s · %s edition · interface %s · client %s build %s",
    "1.13.0", CLASSIC_FEATURES and "Forever" or "Retail", tostring(iface), tostring(ver), tostring(build)))
  Print(string.format("  settings dbVersion %s · sort %s · cast mode %s · scale %s",
    tostring(db.dbVersion), tostring(db.sortMode), tostring(db.castMethod), tostring(db.scale)))
  Print(string.format("  sync %s · requests %s · role filter %s · profiles %d · idle fade %s",
    OnOff(db.sync), OnOff(db.requests), tostring(db.roleFilter),
    #X.ProfileNames(), tostring(db.idleFade or 0)))
  Print(string.format("  pill %s · queue tag %s · consumables %s · custom spells %d · buddy split %s · uptime %s",
    OnOff(db.pill), OnOff(db.queueTag), OnOff(db.consumables), #(db.customSpells or {}),
    OnOff(db.buddySplit),
    X.upTotal > 0 and string.format("%d%%", math.floor(100 * X.upFull / X.upTotal + 0.5)) or "n/a"))
  local acount, bcount, apcount, pcount = 0, 0, 0, 0
  for _ in pairs(X.assign) do acount = acount + 1 end
  for _ in pairs(X.blessPlan) do bcount = bcount + 1 end
  for _ in pairs(db.autoProfile) do apcount = apcount + 1 end
  for _ in pairs(X.peers) do pcount = pcount + 1 end
  Print(string.format("  assignments %d · blessing plan %d · auto profiles %d · peers %d",
    acount, bcount, apcount, pcount))
  local ccount = 0
  for _ in pairs(X.cover) do ccount = ccount + 1 end
  Print(string.format("  readypost %s · pinned %s · weapon watch %s · entry reminder %s · throttle %s · covering %d · history %d",
    OnOff(db.readyPost), (db.pinned ~= "" and db.pinned) or "none",
    OnOff(db.weaponWatch), OnOff(db.enterFlash), OnOff(db.scanThrottle),
    ccount, #(db.history or {})))
  local ocount = 0
  for _ in pairs(db.offenders) do ocount = ocount + 1 end
  Print(string.format("  grow up %s · combat hide %s · theme %s · find %s · bars %s · markers %s · focus %s · pets %s · aura %s · world %s · drink %s · offenders %d",
    OnOff(db.growUp), OnOff(db.hideInCombat), tostring(db.theme), OnOff(db.findBox),
    OnOff(db.durationBars), OnOff(db.raidMarkers), OnOff(db.focusWatch), OnOff(db.pets),
    OnOff(db.auraWatch), OnOff(db.worldWatch), OnOff(db.drinkWatch), ocount))
  Print(string.format("  two columns %s · death recap %s · wipe report %s · wizard seen %s",
    OnOff(db.twoCol), OnOff(db.deathRecap), OnOff(db.wipeReport), OnOff(db.wizardSeen)))
  Print(string.format("  view %s · saved themes %d · row gap %d · icons %s · layer %s · tooltips %s · buff order %d · click-through %s",
    tostring(db.viewMode), #(db.customThemes or {}), db.rowGap or 0,
    (db.iconSize or 0) > 0 and tostring(db.iconSize) or "auto", tostring(db.strata),
    tostring(db.tooltipLevel), #(db.buffPrio or {}), OnOff(db.clickThrough)))
  if #myBuffs == 0 then Print("  buffs found: none") end
  for _, b in ipairs(myBuffs) do
    local id
    for _, d in ipairs(BUFF_DEFS) do if d.key == b.key then id = d.id break end end
    id = id or b.custom
    Print(string.format("  buff %s: %s (spell %s, %s)", b.key, b.name,
      tostring(id), IsOn(b.key, b.default) and "on" or "off"))
  end
  local plates = FriendlyPlatesOn()
  Print(string.format("  friendly nameplates: %s · plates seen %d (%d players) · in group %s",
    plates == nil and "unknown" or (plates and "on" or "off"),
    X.platesSeen or 0, X.playersSeen or 0, tostring(InGroup())))
  Print(string.format("  window built %s · spec profile %s · last problem: %s",
    tostring(built), tostring(X.spec or "none"), tostring(lastError or "none")))
end

local function HandleSlash(msg)
  syncState()
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  if not db then Print("Settings not loaded yet."); return end
  if not built and not InCombatLockdown() then
    local ok, err = pcall(BuildUI)
    if not ok then Print("|cffff4040error building window:|r " .. tostring(err)) end
  end

  local needsOOC = { [""]=true, show=true, hide=true, reset=true, resetpos=true, scale=true, width=true, specscale=true, macro=true }
  if needsOOC[cmd] and InCombatLockdown() then
    Print("Can't do that during combat.")
    return
  end

  if cmd == "" then
    if frame and frame:IsShown() then
      db.hidden, sessionShow = true, false
    A.setSessionShow(sessionShow)
      A.setSessionShow(sessionShow)
      frame:Hide()
      Print("Hidden.")
    else
      db.hidden, sessionShow = false, true
    A.setSessionShow(sessionShow)
      A.setSessionShow(sessionShow)
      Print("Shown." .. (hasAnyBuff and "" or " (No supported buffs found; try /br debug)"))
    end
  elseif cmd == "show" then
    db.hidden, sessionShow = false, true
  elseif cmd == "hide" then
    db.hidden, sessionShow = true, false
  elseif cmd == "config" or cmd == "options" or cmd == "settings" then
    OpenConfig()
  elseif cmd == "group" then
    db.groupOnly = not db.groupOnly
    Print("Show only in a party or raid " .. OnOff(db.groupOnly))
  elseif cmd == "cities" then
    db.pauseInCities = not db.pauseInCities
    Print("Pause in major cities " .. OnOff(db.pauseInCities))
  elseif cmd == "sync" then
    db.sync = not db.sync
    Print("BuffRadar cast sync " .. OnOff(db.sync))
  elseif cmd == "requests" then
    db.requests = not db.requests
    Print("Chat buff requests " .. OnOff(db.requests))
  elseif cmd == "digest" then
    db.joinDigest = not db.joinDigest
    Print("Group join summary " .. OnOff(db.joinDigest))
  elseif cmd == "sound" then
    db.playSound = not db.playSound
    Print("Droplet sound " .. OnOff(db.playSound))
    if db.playSound then PlayAlert() end
  elseif cmd == "soundfor" then
    local kind, choice = rest:match("^(%S+)%s*(%S*)$")
    local choices = { droplet = true, system = true, none = true }
    if kind == "master" and choices[choice] then
      db.alertSound = choice
      Print("Alert sound (used for every alert without its own): " .. choice)
      if db.playSound then PlayAlert() end
    elseif (kind == "new" or kind == "drop" or kind == "ask" or kind == "fall") and choices[choice] then
      db.alertSounds[kind] = choice
      Print("Sound for " .. kind .. " alerts: " .. choice)
      PlayAlert(kind)
    else
      Print("Alert sound (default): " .. db.alertSound
        .. " - new name: " .. (db.alertSounds.new or db.alertSound)
        .. " - buff drop: " .. (db.alertSounds.drop or db.alertSound)
        .. " - buff request: " .. (db.alertSounds.ask or db.alertSound)
        .. " - buff fell off: " .. (db.alertSounds.fall or db.alertSound))
      Print("Change one: /br soundfor master|new|drop|ask|fall droplet|system|none")
    end
  elseif cmd == "prio" then
    if rest == "reset" then
      db.buffPrio = {}
      X.prioDirty = true
      Print("Buff order reset - your buffs are back in their normal order.")
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
      if key then
        key = key:upper()
        local at
        for i, k in ipairs(order) do if k == key then at = i; break end end
        if not at then
          Print("You don't have a buff with the short name " .. key .. " - /br prio lists them.")
        else
          table.remove(order, at)
          local pos = tonumber(posText) or 1
          if pos < 1 then pos = 1 end
          if pos > #order + 1 then pos = #order + 1 end
          table.insert(order, pos, key)
          db.buffPrio = order
          X.prioDirty = true
          Print("Buff order: " .. (byKey[key] or key) .. " is now offered number " .. pos .. ".")
          Refresh()
        end
      else
        Print("Your buffs, first offered first (move one with /br prio <short name> <place>):")
        for i, k in ipairs(order) do
          Print("  " .. i .. ". " .. (byKey[k] or k) .. " (" .. k .. ")")
        end
      end
    end
  elseif cmd == "view" then
    if rest == "people" or rest == "buffs" then
      db.viewMode = rest
      Print("List view: " .. (rest == "buffs"
        and "one row per buff still needed (click a row to cast it on someone who needs it)"
        or "one row per player"))
      Refresh()
    else
      Print("List view is " .. db.viewMode .. " - change it with /br view people|buffs")
    end
  elseif cmd == "clickthrough" then
    db.clickThrough = not db.clickThrough
    X.ApplyClickThrough()
    Print("Click-through while the window is locked " .. OnOff(db.clickThrough))
  elseif cmd == "count" or cmd == "counts" then
    Print(string.format("Casts through BuffRadar: %d this session, %d all-time.", X.sessionCasts, db.castsTotal or 0))
  elseif cmd == "resetcount" then
    X.sessionCasts, db.castsTotal = 0, 0
    db.history = {}
    UpdateCounter()
    Print("Cast counts reset.")
  elseif cmd == "macro" then
    MakeMacro(false)
  elseif cmd == "key" or cmd == "keybind" then
    OpenKeybinds()
  elseif cmd == "clicks" then
    db.clickDebug = not db.clickDebug
    Print("Click diagnostics " .. OnOff(db.clickDebug))
  elseif cmd == "mode" then
    local m = rest:lower()
    -- "id" and "rank" pick a spell rank, which only the Forever edition has.
    if m == "target" or m == "macro" or (CLASSIC_FEATURES and (m == "id" or m == "rank")) then
      if InCombatLockdown() then Print("Can't change mode during combat."); return end
      db.castMethod = m
      Print("Cast mode: " .. m)
    elseif CLASSIC_FEATURES then
      Print("Usage: /br mode target|id|macro|rank   (currently " .. tostring(db.castMethod) .. ")")
      Print("  target = target the player, cast, restore your target (default)")
      Print("  id = cast the chosen rank by spell ID")
      Print("  macro = /cast by plain name (game picks highest rank)")
      Print("  rank = /cast Name(Rank N)")
    else
      Print("Usage: /br mode target|macro   (currently " .. tostring(db.castMethod) .. ")")
      Print("  target = group members directly; others: target, cast, restore your target (default)")
      Print("  macro = /cast [@unit] by spell name")
    end
  elseif cmd == "clickreg" then
    local m = rest:lower()
    if m == "both" or m == "down" or m == "up" then
      if InCombatLockdown() then Print("Can't change this during combat."); return end
      db.clickReg = m
      for _, row in ipairs(rows) do
        if m == "down" then row:RegisterForClicks("AnyDown")
        elseif m == "up" then row:RegisterForClicks("AnyUp")
        else row:RegisterForClicks("AnyUp", "AnyDown") end
      end
      Print("Clicks trigger on: " .. m)
    else
      Print("Usage: /br clickreg both|down|up   (currently " .. tostring(db.clickReg) .. ")")
    end
  elseif cmd == "debug" then
    local ver, build, _, iface = GetBuildInfo()
    local _, myClass = UnitClass("player")
    Print(string.format("client %s build %s (interface %s, %s edition), class %s, spellbook entries %d, window built %s",
      tostring(ver), tostring(build), tostring(iface), CLASSIC_FEATURES and "Forever" or "Retail",
      tostring(myClass), bookCount, tostring(built)))
    local names = {}
    for _, b in ipairs(myBuffs) do names[#names + 1] = b.name end
    for class, b in pairs(myBlessing) do names[#names + 1] = class .. "=" .. b.name end
    Print("buffs found: " .. (#names > 0 and table.concat(names, ", ") or "none"))
    for _, b in ipairs(CLASSIC_FEATURES and myBuffs or {}) do  -- rank details: Forever only
      local list = ranks[b.name]
      if list and #list > 0 then
        local top = list[#list]
        Print(string.format("  %s: %d rank(s) known, top = %s, spell ID %s", b.name, #list,
          tostring(top.sub), tostring(top.id)))
      end
    end
    local isCity, mapID, zone = InMajorCity()
    Print(string.format("zone: %s (map %s), major city: %s, in group: %s", tostring(zone),
      tostring(mapID), tostring(isCity), tostring(InGroup())))
    local platesOn = FriendlyPlatesOn()
    Print(string.format("friendly nameplates: %s, nameplate units seen: %d (%d players)",
      platesOn == nil and "unknown" or (platesOn and "on" or "off"),
      X.platesSeen, X.playersSeen))
    Print("keybind safety: combat driver " .. (nextCombatDriver and "secure" or "fallback") ..
      ", click reset " .. (nextWrapped and "secure" or "fallback"))
    Print("cast mode: " .. tostring(db.castMethod) .. ", clickreg: " .. tostring(db.clickReg) ..
      ", ActionButtonUseKeyDown=" ..
      tostring(GetCVar and GetCVar("ActionButtonUseKeyDown")))
    if frame then
      local p, _, rp, x, y = frame:GetPoint()
      Print(string.format("window shown %s, at %s %s %d %d", tostring(frame:IsShown()),
        tostring(p), tostring(rp), x or 0, y or 0))
    end
    if lastError then Print("last error: " .. tostring(lastError)) end
  elseif cmd == "lock" then
    db.locked = not db.locked
    ApplyAppearance()  -- the resize grip hides while locked
    X.ApplyClickThrough()
    Print("Window lock (moving and resizing) " .. OnOff(db.locked))
  elseif cmd == "self" then
    db.includeSelf = not db.includeSelf
    Print("Check yourself first (all buffs that suit you) " .. OnOff(db.includeSelf))
  elseif cmd == "pvp" then
    db.avoidPvP = not db.avoidPvP
    Print("Skip PvP-flagged players " .. OnOff(db.avoidPvP))
  elseif cmd == "autohide" then
    db.autoHide = not db.autoHide
    Print("Hide when empty " .. OnOff(db.autoHide))
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
        Print(string.format("%s re-buffs when less than %d seconds remain.", key, v))
      else
        Print("Unknown buff key. Use /br buffs to see keys.")
      end
    else
      local n = tonumber(rest)
      if n and n >= 0 then
        db.rebuff = n
        Print(string.format("Re-buff (all buffs) when less than %d seconds remain.", n))
      else
        Print("Usage: /br rebuff <seconds>  |  /br rebuff KEY <seconds>   (all-buffs default " .. db.rebuff .. ")")
      end
    end
    Refresh()
  elseif cmd == "groupcast" and not CLASSIC_FEATURES then
    Print("Group-cast offers aren't needed here: on retail, one cast of a raid buff covers the whole group.")
  elseif cmd == "groupcast" then
    local m = rest:lower()
    local n = tonumber(m)
    if n then
      db.groupCastMin = math.max(2, math.min(40, math.floor(n)))
      Print("Group buffs offered when " .. db.groupCastMin .. "+ group members need the buff.")
    elseif m == "on" then
      db.groupCast = true
      Print("Group-cast offers on.")
    elseif m == "off" then
      db.groupCast = false
      Print("Group-cast offers off.")
    else
      db.groupCast = not db.groupCast
      Print("Group-cast offers " .. OnOff(db.groupCast) ..
        " (threshold " .. db.groupCastMin .. "; set with /br groupcast <n>)")
    end
    Refresh()
  elseif cmd == "sort" then
    local m = rest:lower()
    if m == "name" or m == "role" or m == "distance" or m == "need" then db.sortMode = m
    elseif db.sortMode == "name" then db.sortMode = "role"
    elseif db.sortMode == "role" then db.sortMode = "distance"
    elseif db.sortMode == "distance" then db.sortMode = "need"
    else db.sortMode = "name" end
    Print("List order: " .. db.sortMode ..
      (db.sortMode == "role" and " (tanks & leaders first)" or
       db.sortMode == "distance" and " (nearest first)" or
       db.sortMode == "need" and " (most missing first)" or ""))
    Refresh()
  elseif cmd == "filter" then
    local m = rest:upper()
    if m == "ALL" or m == "TANK" or m == "HEALER" or m == "DAMAGER" or m == "DPS" then
      db.roleFilter = (m == "DPS") and "DAMAGER" or m
      X.RefreshChips()
      Print("Role filter: " .. db.roleFilter .. " (window list only)")
    else
      Print("Usage: /br filter all|tank|healer|dps   (currently " .. tostring(db.roleFilter or "ALL") .. ")")
    end
    Refresh()
  elseif cmd == "strip" then
    db.showStrip = not db.showStrip
    X.ApplyRowLayout()
    Print("Buff toggle strip " .. OnOff(db.showStrip))
    Refresh()
  elseif cmd == "fade" then
    local n = tonumber(rest)
    if n and n >= 0 and n <= 90 then
      db.idleFade = math_floor(n)
      X.curAlpha = nil
      Print(string.format("Idle fade: %d%% while the mouse is away (0 = off).", db.idleFade))
    else
      Print("Usage: /br fade <0-90>   (currently " .. tostring(db.idleFade or 0) .. ")")
    end
  elseif cmd == "mana" then
    local n = tonumber(rest)
    if n and n >= 0 and n <= 100 then
      db.lowMana = math_floor(n)
      Print(db.lowMana > 0 and
        string.format("Buffing pauses below %d%% mana.", db.lowMana) or "Low-mana pause off.")
    else
      Print(string.format("Usage: /br mana <0-100> (0 = off; currently %s)",
        tostring(db.lowMana or 0)))
    end
    Refresh()
  elseif cmd == "selftest" then
    X.SelfTest()
  elseif cmd == "compact" then
    db.compact = not db.compact
    X.ApplyRowLayout()
    Print("Compact rows " .. OnOff(db.compact))
    Refresh()
  elseif cmd == "text" then
    local n = tonumber(rest)
    if n and n >= 0.8 and n <= 1.5 then
      db.textScale = n
      X.ApplyRowLayout()
      Print(string.format("List text scale: %s", tostring(n)))
    else
      Print("Usage: /br text <0.8 - 1.5>   (currently " .. tostring(db.textScale or 1) .. ")")
    end
    Refresh()
  elseif cmd == "charpoint" then
    db.charPoint = not db.charPoint
    if db.charPoint then
      local k = X.CharKey()
      if k and db.point then db.pointByChar[k] = db.point end
    end
    Print("Per-character window position " .. OnOff(db.charPoint))
  elseif cmd == "export" then
    X.ShowExport(X.Export(), false)
    Print("Settings string shown -- copy it, then use /br import on the other character.")
  elseif cmd == "import" then
    X.ShowExport("", true)
  elseif cmd == "profile" then
    local sub, pname = rest:match("^(%S*)%s*(.-)%s*$")
    sub = (sub or ""):lower()
    if sub == "save" then
      if X.SaveProfile(pname) then Print("Profile saved: " .. pname)
      else Print("Usage: /br profile save <name> (letters, numbers, - and _, max 40 characters)") end
      if RefreshConfig then RefreshConfig() end
    elseif sub == "load" then
      if X.LoadProfile(pname) then
        Print("Profile loaded: " .. pname)
        ApplyGeometry()
        ApplyAppearance()
        X.ApplyRowLayout()
        if RefreshConfig then RefreshConfig() end
        Refresh()
      else Print("No profile named '" .. pname .. "'. /br profile list shows them.") end
    elseif sub == "delete" or sub == "del" then
      if X.DeleteProfile(pname) then Print("Profile deleted: " .. pname)
      else Print("No profile named '" .. pname .. "'.") end
      if RefreshConfig then RefreshConfig() end
    elseif sub == "share" then
      local text = X.ProfileShareText(pname)
      if text then
        X.ShowExport(text, false, "BuffRadar profile: " .. pname)
        Print("Profile '" .. pname .. "' shown as one text — copy it and send it.")
      else
        Print("No profile named '" .. pname .. "'. /br profile list shows them.")
      end
    elseif sub == "import" then
      X.ShowExport("", true, "BuffRadar — paste a shared profile, then Import", "profile")
    elseif sub == "diff" then
      local str = db.profiles[pname]
      if type(str) ~= "string" then Print("No profile named '" .. pname .. "'. /br profile list shows them.")
      elseif X.PrintDiff then X.PrintDiff(str, "Profile '" .. pname .. "'")
      else Print("Diff needs Extras.lua.") end
    elseif sub == "list" or sub == "" then
      local names = X.ProfileNames()
      Print(#names > 0 and ("Profiles: " .. table.concat(names, ", "))
        or "No saved profiles yet. /br profile save <name> makes one.")
    else
      Print("Usage: /br profile save|load|delete|list|share|import <name>")
    end
  elseif cmd == "plan" then
    local sub = (rest:match("^(%S*)") or ""):lower()
    if sub == "export" then
      X.ShowExport(X.PlanExport(), false, "BuffRadar — your group buff plan (copy it)")
      Print("Plan string shown — it carries assignments, the blessing plan and auto profiles, not your settings.")
    elseif sub == "import" then
      X.ShowExport("", true, "BuffRadar — paste a plan string, then Import", "plan")
    else
      local acount, bcount = 0, 0
      for _ in pairs(X.assign) do acount = acount + 1 end
      for _ in pairs(X.blessPlan) do bcount = bcount + 1 end
      Print(string.format("Current plan: %d assignments, %d blessings. /br plan export shares it as one string.", acount, bcount))
    end
  elseif cmd == "summary" then
    local rows, people = X.SummaryLines()
    if #rows == 0 then Print("Nobody in your group is missing a buff you can cast.")
    else
      Print(string_format("Group needs (%d %s):", people, people == 1 and "person" or "people"))
      for i = 1, math_min(#rows, 12) do Print(string_format("  %s: %d", rows[i].n, rows[i].c)) end
    end
  elseif cmd == "discord" then
    X.ShowExport(X.DiscordText(), false, "BuffRadar — copy into Discord")
    Print("Discord summary shown — copy it into your Discord message.")
  elseif cmd == "offenders" then
    if rest:lower() == "clear" then
      wipe(db.offenders)
      Print("Repeat-offender history cleared.")
    else
      local orows = {}
      for nm, c in pairs(db.offenders) do orows[#orows + 1] = { nm = nm, c = c } end
      table_sort(orows, function(a, b) return a.c > b.c end)
      if #orows == 0 then
        Print("No repeat offenders yet — a player lands here after a group session where they were seen unbuffed.")
      else
        Print("Repeat offenders (group sessions seen unbuffed):")
        for i = 1, math_min(10, #orows) do
          Print(string.format("  %s: %d", orows[i].nm, orows[i].c))
        end
      end
    end
  elseif cmd == "preset" then
    local name = rest:lower()
    if X.ApplyPreset(name) then
      Print("Preset applied: " .. name .. " (window and behavior only; buff toggles kept).")
      ApplyGeometry()
      ApplyAppearance()
      X.ApplyRowLayout()
      if RefreshConfig then RefreshConfig() end
      Refresh()
    else
      Print("Usage: /br preset raid|dungeon|solo")
    end
  elseif cmd == "wizard" then
    X.OpenWizard()
  elseif cmd == "pill" then
    db.pill = not db.pill
    Print("All-buffed pill " .. OnOff(db.pill))
    Refresh()
  elseif cmd == "fastaura" then
    local m = rest:lower()
    if m == "on" then db.fastAura = true
    elseif m == "off" then db.fastAura = false
    else db.fastAura = not db.fastAura end
    Print("Fast aura updates " .. OnOff(db.fastAura) ..
      " -- aura changes that touch no watched buff skip the rescan (the steady refresh still runs).")
  elseif cmd == "modclick" then
    local m = rest:lower()
    if m == "on" then db.modClick = true
    elseif m == "off" then db.modClick = false
    else db.modClick = not db.modClick end
    Print("Modifier clicks " .. OnOff(db.modClick) ..
      " -- Shift-click a row to cast the group version of its buff (Forever only).")
    Refresh()
  elseif cmd == "grouppair" then
    local cg = db.customGroup
    local single, group = rest:match('^"([^"]+)"%s*"([^"]+)"$')
    if single then
      cg[single] = group
      Print("Group-cast pair set: Shift-click " .. single .. " casts " .. group .. " (needs /br modclick on).")
    elseif rest:lower():sub(1, 6) == "clear " then
      local name = rest:sub(7):gsub('^"', ""):gsub('"$', "")
      if cg[name] then cg[name] = nil; Print("Group-cast pair removed for " .. name .. ".")
      else Print("No custom group-cast pair for " .. name .. ".") end
    elseif rest == "" then
      local any = false
      for s, g in pairs(cg) do Print("  " .. s .. " -> " .. g); any = true end
      if not any then Print('No custom group-cast pairs. Add one: /br grouppair "Single Buff" "Group Buff"') end
    else
      Print('Usage: /br grouppair "Single Buff" "Group Buff"  |  /br grouppair clear "Single Buff"  |  /br grouppair (list)')
    end
    Refresh()
  elseif cmd == "pullflash" then
    local m = rest:lower()
    if m == "on" then db.pullFlash = true
    elseif m == "off" then db.pullFlash = false
    else db.pullFlash = not db.pullFlash end
    Print("Pull-timer flash " .. OnOff(db.pullFlash) ..
      " -- border flash and a countdown line when a group pull timer starts (the game's /countdown or a boss-mod pull).")
  elseif cmd == "why" then
    local nm = rest:match("^%s*(.-)%s*$")
    if nm == "" then
      Print("Usage: /br why <name> - say why a player is or is not on the list")
    else
      X.Why(nm)
      Refresh()  -- rebuild the tallies Why's scan touched
    end
  elseif cmd == "fallsound" then
    local m = rest:lower()
    if m == "on" then db.fallSound = true
    elseif m == "off" then db.fallSound = false
    else db.fallSound = not db.fallSound end
    Print("Buff-fell-off sound " .. OnOff(db.fallSound) ..
      " -- a distinct alert when a watched group buff falls off during a fight.")
  elseif cmd == "consumables" then
    db.consumables = not db.consumables
    Print("Consumables on the coverage line " .. OnOff(db.consumables))
    Refresh()
  elseif cmd == "custom" then
    local sub, arg = rest:match("^(%S*)%s*(.-)%s*$")
    sub = (sub or ""):lower()
    local id = tonumber(arg)
    if sub == "add" and id then
      id = math.floor(id)
      local have = false
      for _, x in ipairs(db.customSpells) do if x == id then have = true break end end
      if have then Print("That spell is already on the custom list.")
      elseif #db.customSpells >= 20 then Print("The custom list is full (20 spells).")
      else
        db.customSpells[#db.customSpells + 1] = id
        pcall(BuildBuffList)
        Print("Custom spell added: " .. tostring(SpellName(id, id))
          .. " -- watched from now on if you know it.")
        Refresh()
      end
    elseif sub == "remove" and id then
      local gone = false
      for i = #db.customSpells, 1, -1 do
        if db.customSpells[i] == id then table.remove(db.customSpells, i); gone = true end
      end
      if gone then
        pcall(BuildBuffList)
        Print("Custom spell removed.")
        Refresh()
      else Print("That spell is not on the custom list.") end
    elseif sub == "list" or sub == "" then
      if #db.customSpells == 0 then
        Print("No custom spells. /br custom add <spell ID> watches one.")
      else
        local parts = {}
        for _, x in ipairs(db.customSpells) do
          parts[#parts + 1] = tostring(SpellName(x, x)) .. " (" .. x .. ")"
        end
        Print("Custom spells: " .. table.concat(parts, ", "))
      end
    else
      Print("Usage: /br custom add|remove|list <spell ID>")
    end
  elseif cmd == "assign" then
    local akey, aname = rest:match("^(%S*)%s*(.-)%s*$")
    akey = (akey or ""):upper()
    if akey == "" then
      local parts = {}
      for k, v in pairs(X.assign) do parts[#parts + 1] = k .. " -> " .. v end
      table_sort(parts)
      Print(#parts > 0 and ("Assignments: " .. table.concat(parts, ", "))
        or "No buff assignments. /br assign <BUFF> <name> sets one (leader or assistant).")
    elseif akey == "CLEAR" then
      wipe(X.assign)
      Print("Assignments cleared.")
      Refresh()
    elseif not InGroup() then
      Print("Assignments need a group.")
    elseif not X.AmLead() then
      Print("Only the group leader or an assistant can set assignments.")
    elseif aname == "" then
      Print("Usage: /br assign <BUFF> <name>, or /br assign <BUFF> none to clear one.")
    else
      if aname:lower() == "none" then X.assign[akey] = nil else X.assign[akey] = aname end
      X.Broadcast("ASSIGN;" .. akey .. ";" .. aname)
      Print("Assignment: " .. akey .. " -> " .. aname)
      Refresh()
    end
  elseif cmd == "pin" then
    if rest == "" then
      Print(db.pinned ~= "" and ("Pinned: " .. db.pinned .. "  (/br pin none clears it)")
        or "No one is pinned. /br pin <name> keeps a player at the top of the list.")
    elseif rest:lower() == "none" then
      db.pinned = ""
      Print("Pin cleared.")
      Refresh()
    else
      db.pinned = rest
      Print("Pinned " .. rest .. " — their row stays at the top while they need a buff.")
      Refresh()
    end
  elseif cmd == "history" then
    if #(db.history or {}) == 0 then
      Print("No casts recorded yet — buffs you cast through BuffRadar will be listed here.")
    else
      X.ShowExport(X.HistoryText(), false, "BuffRadar -- your recent casts (newest first)")
    end
  elseif cmd == "throttle" then
    db.scanThrottle = not db.scanThrottle
    Print("Scan throttle " .. OnOff(db.scanThrottle)
      .. " — in groups over 20, the steady rescan runs half as often (event refreshes stay instant).")
  elseif cmd == "growup" then
    db.growUp = not db.growUp
    X.ApplyAnchor()
    Print("Grow the list upward " .. OnOff(db.growUp)
      .. " — on: the window's bottom edge stays put and the list grows up.")
    Refresh()
  elseif cmd == "cover" then
    local parts = { "progress", "buffs", "uptime", "roster", "expiry", "world", "drink" }
    local valid = {}
    for _, k in ipairs(parts) do valid[k] = true end
    local part, mode = rest:match("^(%S+)%s*(%S*)$")
    if part and valid[part] and (mode == "on" or mode == "off") then
      if mode == "off" then db.coverParts[part] = false else db.coverParts[part] = nil end
      Print("Coverage line part '" .. part .. "' " .. mode .. ".")
      Refresh()
    elseif part then
      Print("Usage: /br cover <part> on|off — parts: " .. table.concat(parts, ", ") .. ".")
    else
      local states = {}
      for _, k in ipairs(parts) do
        states[#states + 1] = k .. ((db.coverParts or {})[k] == false and " off" or " on")
      end
      Print("Coverage line parts: " .. table.concat(states, ", ") .. ".")
    end
  elseif cmd == "rowcolor" then
    local rules = { "mine", "tank", "expiring", "buddy" }
    local isRule = { mine = true, tank = true, expiring = true, buddy = true }
    local rule, val = rest:match("^(%S+)%s*(%S*)$")
    if rule and isRule[rule] then
      val = (val or ""):lower()
      if val == "" then
        Print("Row color for '" .. rule .. "': " .. X.RowColorName(rule)
          .. ". /br rowcolor " .. rule .. " <color|off> — colors: gold, sky, red, green, violet, or #rrggbb.")
      elseif val == "off" then
        X.SetRowColor(rule, nil)
        Print("Row color for '" .. rule .. "' off.")
      elseif X.ROW_PALETTE[val] then
        X.SetRowColor(rule, X.ROW_PALETTE[val])
        Print("Row color for '" .. rule .. "': " .. val .. ".")
      else
        local hex = val:gsub("^#", "")
        local r, g, b = hex:match("^(%x%x)(%x%x)(%x%x)$")
        if r then
          X.SetRowColor(rule, { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 })
          Print("Row color for '" .. rule .. "' set to #" .. hex .. ".")
        else
          Print("Unknown color '" .. val .. "'. Use gold, sky, red, green, violet, #rrggbb — or off.")
        end
      end
    elseif rule then
      Print("Usage: /br rowcolor <rule> <color|off> — rules: " .. table.concat(rules, ", ") .. ".")
    else
      local states = {}
      for _, r in ipairs(rules) do states[#states + 1] = r .. " " .. X.RowColorName(r) end
      Print("Row colors: " .. table.concat(states, ", ") .. ". /br rowcolor <rule> <color|off> changes one.")
    end
  elseif cmd == "tooltip" then
    local m = rest:lower()
    if m == "minimal" or m == "standard" or m == "full" then
      db.tooltipLevel = m
      Print("Row tooltips: " .. m .. ".")
      if RefreshConfig then RefreshConfig() end
    else
      Print("Usage: /br tooltip minimal|standard|full (now " .. (db.tooltipLevel or "standard") .. ").")
    end
  elseif cmd == "rowgap" then
    local v = tonumber(rest)
    if v and v >= 0 and v <= 8 then
      db.rowGap = math.floor(v + 0.5)
      X.ApplyRowLayout()
      Print("Row spacing set to " .. db.rowGap .. ".")
      Refresh()
      if RefreshConfig then RefreshConfig() end
    else
      Print("Usage: /br rowgap <0-8> — extra space between the rows (now " .. (db.rowGap or 0) .. ").")
    end
  elseif cmd == "iconsize" then
    local v = tonumber(rest)
    if v and (v == 0 or (v >= 10 and v <= 24)) then
      db.iconSize = math.floor(v + 0.5)
      X.ApplyRowLayout()
      InvalidateRows()
      Print(db.iconSize == 0 and "Buff icon size: automatic." or ("Buff icon size set to " .. db.iconSize .. "."))
      Refresh()
      if RefreshConfig then RefreshConfig() end
    else
      Print("Usage: /br iconsize <0|10-24> — 0 is automatic (now " .. (db.iconSize or 0) .. ").")
    end
  elseif cmd == "strata" then
    local m = rest:upper()
    if m == "LOW" or m == "MEDIUM" or m == "HIGH" or m == "DIALOG" then
      db.strata = m
      ApplyAppearance()
      Print("Window layer set to " .. m .. ".")
      if RefreshConfig then RefreshConfig() end
    else
      Print("Usage: /br strata low|medium|high|dialog (now " .. (db.strata or "MEDIUM") .. ").")
    end
  elseif cmd == "twocol" then
    db.twoCol = not db.twoCol
    X.cols = nil  -- force the column split to re-decide on the next refresh
    Print("Two columns when the list is long " .. OnOff(db.twoCol)
      .. " — on: past 8 rows the list splits into two columns.")
    Refresh()
  elseif cmd == "find" then
    if rest == "" or rest:lower() == "off" then
      X.search = ""
      if X.findEdit then X.findEdit:SetText("") end
      Print("Name finder cleared — everyone is listed again.")
    else
      X.search = rest:lower()
      if X.findEdit then X.findEdit:SetText(rest) end
      Print("Name finder: only names matching '" .. rest .. "' are listed. /br find off clears it.")
    end
    Refresh()
  elseif cmd == "findbox" then
    db.findBox = not db.findBox
    X.ApplyRowLayout()
    Print("Name finder box on the window " .. OnOff(db.findBox))
    Refresh()
  elseif cmd == "bars" then
    db.durationBars = not db.durationBars
    InvalidateRows()
    Print("Duration bars on rows " .. OnOff(db.durationBars)
      .. " — the bar shows the expiring buff's time left, as a share of 30 minutes.")
    Refresh()
  elseif cmd == "markers" then
    db.raidMarkers = not db.raidMarkers
    InvalidateRows()
    Print("Raid markers on rows " .. OnOff(db.raidMarkers))
    Refresh()
  elseif cmd == "focus" then
    db.focusWatch = not db.focusWatch
    Print("Focus target watch line " .. OnOff(db.focusWatch))
    Refresh()
  elseif cmd == "pets" then
    db.pets = not db.pets
    Print("Group pets on the list " .. OnOff(db.pets)
      .. " — pets get rows for Fortitude, Mark of the Wild and Arcane Intellect.")
    Refresh()
  elseif cmd == "aura" then
    if not CLASSIC_FEATURES then
      Print("The aura / aspect watch belongs to the Forever edition.")
    else
      db.auraWatch = not db.auraWatch
      pcall(BuildBuffList)
      Print("Aura / aspect watch " .. OnOff(db.auraWatch)
        .. " — your own row flags a missing hunter aspect or paladin aura.")
      Refresh()
    end
  elseif cmd == "worldbuff" then
    if not CLASSIC_FEATURES then
      Print("The world-buff watch belongs to the Forever edition.")
    else
      db.worldWatch = not db.worldWatch
      Print("World-buff watch " .. OnOff(db.worldWatch))
      if db.worldWatch then
        Print(X.WorldBuffsText() or "No world buffs on you right now.")
      end
      Refresh()
    end
  elseif cmd == "drink" then
    if not CLASSIC_FEATURES then
      Print("The drinking watch belongs to the Forever edition.")
    else
      db.drinkWatch = not db.drinkWatch
      Print("Healer drinking watch " .. OnOff(db.drinkWatch)
        .. " — drinking players are tagged; healers also reach the coverage line.")
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
      Print(#parts > 0 and ("Buff contexts: " .. table.concat(parts, ", "))
        or "No buff contexts set. /br context KEY raid|instance|always limits a buff.")
    elseif not found then
      Print("Unknown buff key. Use /br buffs to see keys.")
    elseif mode == "raid" or mode == "instance" then
      db.buffContext[key] = mode
      Print(key .. " is now offered in " .. (mode == "raid" and "raids" or "instances") .. " only.")
      Refresh()
    elseif mode == "always" or mode == "clear" then
      db.buffContext[key] = nil
      Print(key .. " is offered everywhere again.")
      Refresh()
    else
      Print("Usage: /br context KEY raid|instance|always")
    end
  elseif cmd == "theme" then
    local m = rest:lower()
    if m == "" or m == "list" then
      local parts = {}
      for _, k in ipairs(X.ThemeOrder()) do
        parts[#parts + 1] = k
          .. ((db.theme or ""):lower() == k:lower() and " (current)" or "")
      end
      Print("Themes: " .. table.concat(parts, ", ")
        .. ". /br theme <name> applies one; /br theme save <name> saves your current look (up to 4).")
    elseif m:sub(1, 5) == "save " then
      local saved, why = X.SaveTheme(rest:sub(6))
      if saved then
        X.ApplyTheme(saved)
        Print("Theme saved as '" .. saved .. "' — it's in the theme cycle now. /br theme delete " .. saved .. " removes it.")
      elseif why == "full" then
        Print("You already have 4 saved themes — /br theme delete <name> one first.")
      elseif why == "taken" then
        Print("That name is taken by a built-in theme. Pick another.")
      else
        Print("Theme names are one word (letters, numbers, dashes), up to 24 characters.")
      end
    elseif m:sub(1, 7) == "delete " then
      local name = rest:sub(8)
      if X.DeleteTheme(name) then
        Print("Saved theme '" .. name .. "' deleted.")
      else
        Print("No saved theme named '" .. name .. "'.")
      end
    elseif X.ApplyTheme(m) then
      Print("Theme: " .. X.ThemeDef(m).label)
    else
      Print("Unknown theme '" .. m .. "'. /br theme lists them.")
    end
  elseif cmd == "weapon" then
    db.weaponWatch = not db.weaponWatch
    Print("Weapon enchant watch " .. OnOff(db.weaponWatch)
      .. " — your row (or the coverage line) will flag a weapon with no imbue, poison or oil.")
    Refresh()
  elseif cmd == "enterflash" then
    db.enterFlash = not db.enterFlash
    Print("Instance-entry buff reminder " .. OnOff(db.enterFlash))
  elseif cmd == "readypost" then
    db.readyPost = not db.readyPost
    Print("Ready-check summary also posted to group chat (leader/assistant) " .. OnOff(db.readyPost))
  elseif cmd == "death" then
    if rest:lower() == "show" then
      if X.lastDeath then
        Print("Death recap from your last death:")
        for i = 1, math_min(#X.lastDeath, 12) do Print(X.lastDeath[i]) end
        if #X.lastDeath > 12 then Print(string.format("  +%d more", #X.lastDeath - 12)) end
      else
        Print("No death recap yet — one is recorded when you die.")
      end
    else
      db.deathRecap = not db.deathRecap
      Print("Death recap " .. OnOff(db.deathRecap)
        .. " — on: dying prints who was missing buffs. /br death show reprints the last one.")
    end
  elseif cmd == "wipe" then
    if rest:lower() == "show" then
      if X.lastWipe then
        Print("Wipe report from the last wipe:")
        for i = 1, math_min(#X.lastWipe, 12) do Print(X.lastWipe[i]) end
        if #X.lastWipe > 12 then Print(string.format("  +%d more", #X.lastWipe - 12)) end
      else
        Print("No wipe report yet — one is recorded when a fight ends as a wipe.")
      end
    else
      db.wipeReport = not db.wipeReport
      Print("Post-wipe report " .. OnOff(db.wipeReport)
        .. " — on: a fight ending with several dead prints the rebuff list. /br wipe show reprints the last one.")
    end
  elseif cmd == "buddy" then
    db.buddySplit = not db.buddySplit
    Print("Buddy list splitting " .. OnOff(db.buddySplit)
      .. " (needs cast sync on, and another BuffRadar user in the group)")
    Refresh()
  elseif cmd == "bless" then
    if not CLASSIC_FEATURES then
      Print("The blessing planner belongs to the Forever edition -- Retail has no blessings.")
    else
      local cls, bkey, bname = rest:match("^(%S*)%s*(%S*)%s*(.-)%s*$")
      cls = (cls or ""):upper()
      bkey = (bkey or ""):upper()
      if cls == "" then
        local parts = {}
        for c, p in pairs(X.blessPlan) do
          parts[#parts + 1] = c .. ": " .. p.key .. " (" .. p.name .. ")"
        end
        table_sort(parts)
        Print(#parts > 0 and ("Blessing plan: " .. table.concat(parts, ", "))
          or "No blessing plan. /br bless <CLASS> <BLESSING> [name] sets one.")
      elseif bkey == "" then
        Print("Usage: /br bless <CLASS> <BLESSING> [name], or /br bless <CLASS> none to clear.")
      else
        local _, myClass = UnitClass("player")
        if not X.AmLead() and myClass ~= "PALADIN" then
          Print("Only the group leader, an assistant or a paladin can set the blessing plan.")
        elseif bkey == "NONE" then
          X.blessPlan[cls] = nil
          X.Broadcast("BLESS;" .. cls .. ";NONE;none")
          Print("Blessing plan cleared for " .. cls .. ".")
          Refresh()
        elseif not BLESSINGS[bkey] then
          local bkeys = {}
          for k in pairs(BLESSINGS) do bkeys[#bkeys + 1] = k end
          table_sort(bkeys)
          Print("Unknown blessing '" .. bkey .. "'. Known: " .. table.concat(bkeys, ", ") .. ".")
        else
          local holder = (bname ~= "") and bname or (Ignore.UnitNames("player") or "me")
          local me = Ignore.UnitNames("player")
          X.blessPlan[cls] = { key = bkey, name = holder,
                               mine = me ~= nil and Ignore.Key(holder) == Ignore.Key(me) }
          X.Broadcast("BLESS;" .. cls .. ";" .. bkey .. ";" .. holder)
          Print("Blessing plan: " .. cls .. " gets " .. bkey .. " from " .. holder .. ".")
          Refresh()
        end
      end
    end
  elseif cmd == "uptime" then
    if rest:lower() == "reset" then
      X.upTotal, X.upFull = 0, 0
      Print("Coverage uptime reset.")
    elseif X.upTotal == 0 then
      Print("Coverage uptime: no grouped scans yet this run.")
    else
      Print(string.format("Coverage uptime this run: %d%% (%d of %d scans fully buffed).",
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
      Print(#parts > 0 and ("Auto profiles: " .. table.concat(parts, ", "))
        or "No auto profiles. /br autoprofile <raid|dungeon|pvp|world|solo> <profile> sets one.")
    elseif not CTX[ctx] then
      Print("Contexts: raid, dungeon, pvp, world (grouped, no instance), solo.")
    elseif pname == "" then
      Print("Usage: /br autoprofile " .. ctx .. " <profile name>, or 'clear'.")
    elseif pname:lower() == "clear" then
      db.autoProfile[ctx] = nil
      X.autoCtx, X.lastAutoProfile = nil, nil
      Print("Auto profile for " .. ctx .. " cleared.")
      if RefreshConfig then RefreshConfig() end
    elseif not db.profiles[pname] then
      Print("No profile named '" .. pname .. "'. /br profile list shows them.")
    else
      db.autoProfile[ctx] = pname
      X.autoCtx, X.lastAutoProfile = nil, nil
      Print("Auto profile: " .. ctx .. " loads '" .. pname .. "'.")
      if RefreshConfig then RefreshConfig() end
      X.AutoProfileCheck()
    end
  elseif cmd == "ignore" then
    if rest == "" then Print("Usage: /br ignore <name> or <name-realm>  (or right-click a row)"); return end
    if Ignore.Add(rest) then
      Print("Ignoring " .. rest .. (rest:find("-", 1, true) and "." or " on every realm."))
    else
      Print(rest .. " is already ignored.")
    end
    if RefreshConfig then RefreshConfig() end
  elseif cmd == "unignore" then
    if rest == "" then Print("Usage: /br unignore <name> (every realm) or <name-realm>"); return end
    local removed = Ignore.Remove(rest)
    if #removed == 0 then
      Print(rest .. " isn't on the ignore list. See /br ignorelist.")
    else
      Print("No longer ignoring " .. table.concat(removed, ", ") .. ".")
    end
    if RefreshConfig then RefreshConfig() end
  elseif cmd == "ignorelist" or cmd == "ignores" then
    if (rest == "export" or rest == "import") and X.ext.ignorelist then X.ext.ignorelist(rest); return end
    local names = Ignore.Sorted()
    Print(#names == 0 and "Ignore list is empty." or ("Ignored: " .. table.concat(names, ", ")))
    local sess = {}
    for k in pairs(X.session) do sess[#sess + 1] = k end
    if #sess > 0 then
      table_sort(sess)
      Print("Session-only: " .. table.concat(sess, ", "))
    end
  elseif cmd == "bg" then
    db.pauseInBG = not db.pauseInBG
    Print("Pause in battlegrounds " .. OnOff(db.pauseInBG))
    Refresh()
  elseif cmd == "taxi" then
    db.pauseTaxi = not db.pauseTaxi
    Print("Pause on flight paths " .. OnOff(db.pauseTaxi))
    Refresh()
  elseif cmd == "watch" then
    db.watchDrop = not db.watchDrop
    Print("Single-target drop alert " .. OnOff(db.watchDrop))
    Refresh()
  elseif cmd == "alertsound" then
    local m = rest:lower()
    if m == "droplet" or m == "system" or m == "none" then
      db.alertSound = m
      Print("Alert sound: " .. m)
      if db.playSound then PlayAlert() end
    else
      Print("Usage: /br alertsound droplet|system|none   (currently " .. tostring(db.alertSound) .. ")")
    end
  elseif cmd == "minimap" then
    db.showMinimap = not db.showMinimap
    RefreshMinimapButton()
    Print("Minimap button " .. OnOff(db.showMinimap))
  elseif cmd == "stats" then
    if rest:lower() == "export" then
      X.ShowExport(X.StatsText(), false, "BuffRadar — cast statistics")
      return
    end
    local srows = {}
    for k, n in pairs(db.stats or {}) do srows[#srows + 1] = { k = k, n = n } end
    table.sort(srows, function(a, b) return a.n > b.n end)
    if #srows == 0 then
      Print("No casts recorded yet.")
    else
      Print("Casts by spell (all-time):")
      for i = 1, math.min(10, #srows) do
        Print(string.format("  %s: %d", srows[i].k, srows[i].n))
      end
    end
  elseif cmd == "specscale" then
    local v = rest:lower()
    if v == "on" then db.scalePerSpec = true elseif v == "off" then db.scalePerSpec = false
    else db.scalePerSpec = not db.scalePerSpec end
    if db.scalePerSpec and X.spec then db.specScales[X.spec] = db.scale end
    Print("Scale per specialization " .. OnOff(db.scalePerSpec) .. (X.spec and (" (this spec: " .. X.spec .. ")") or ""))
  elseif cmd == "tagsymbols" then
    db.tagSymbols = not db.tagSymbols
    X.InvalidateTags()
    Print("Row tag symbols " .. OnOff(db.tagSymbols))
  elseif cmd == "motion" then
    db.reduceMotion = not db.reduceMotion
    Print("Reduced motion " .. OnOff(db.reduceMotion) .. " (no idle fade, no border flash)")
  elseif cmd == "rangewatch" then
    db.rangeWatch = not db.rangeWatch
    Print("Range watch " .. OnOff(db.rangeWatch))
  elseif cmd == "snap" then
    db.gripSnap = not db.gripSnap
    Print("Shift-snap on the scale grips " .. OnOff(db.gripSnap))
  elseif cmd == "scale" then
    local n = tonumber(rest)
    if n and n >= 0.5 and n <= 2 then
      db.scale = n
      ApplyGeometry()
      if RefreshConfig then RefreshConfig() end
    else
      Print("Usage: /br scale <0.5 - 2>")
    end
  elseif cmd == "width" then
    local n = tonumber(rest)
    if n and n >= MIN_WIDTH and n <= MAX_WIDTH then
      db.width = math_floor(n + 0.5)
      ApplyGeometry()
      if QueueRefresh then QueueRefresh() end
    else
      Print(string.format("Usage: /br width <%d - %d>", MIN_WIDTH, MAX_WIDTH))
    end
  elseif cmd == "reset" then
    X.ClearSavedPoint()
    if frame then RestorePosition() end
    Print("Position reset.")
  elseif cmd == "resetpos" then
    X.ClearSavedPoint()
    if frame then RestorePosition() end
    Print("Window position reset to the default spot.")
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
      Print("Unknown key. Use /br buffs to see keys.")
      return
    end
    db.enabled[key] = not IsOn(key, default)
    Print(key .. " " .. OnOff(db.enabled[key]))
  elseif cmd == "announce" then
    X.Announce()
  elseif cmd == "signore" then
    if rest == "" then Print("Usage: /br signore <name> (ignore for this session only)"); return end
    local k = Ignore.Key(rest)
    if X.session[k] then
      Print(rest .. " is already ignored for this session.")
    else
      X.session[k] = true
      Print("Ignoring " .. rest .. " for this session only (not saved).")
    end
  elseif cmd == "unsignore" then
    if rest == "" then Print("Usage: /br unsignore <name>"); return end
    local k = Ignore.Key(rest)
    if X.session[k] then
      X.session[k] = nil
      Print("No longer ignoring " .. rest .. " for this session.")
    else
      Print(rest .. " isn't ignored for this session.")
    end
  elseif cmd == "plates" then
    if SetCVar then
      if InCombatLockdown() then Print("Can't change nameplate settings during combat."); return end
      SetCVar("nameplateShowFriends", 1)
      Print("Friendly nameplates turned on, so nearby non-group players can be listed.")
    end
  elseif X.ext[cmd] then
    X.ext[cmd](rest)
  else
    Print("Commands:")
    Print("  /br  - show/hide the window   (/br debug if it won't appear)")
    Print("  /br config  - settings window (color, opacity, title, keybind)")
    Print("  /br macro  - create a 'BuffRadar' macro that casts the next buff")
    Print("  /br key  - open Key Bindings to bind 'Cast next buff'")
    Print("  /br sound  - toggle the water droplet alert")
    Print("  /br group  - only show the window in a party or raid")
    Print("  /br cities  - pause scanning in major cities")
    Print("  /br count | resetcount  - show / reset cast counts")
    Print("  /br lock | self (check yourself first, on by default) | pvp | autohide")
    Print("  /br rebuff <sec> | scale <n> | reset")
    Print("  /br buffs | toggle <KEY>")
    Print("  /br clicks  - print what each click tries to cast")
    Print("  /br mode " .. (CLASSIC_FEATURES and "target|id|macro|rank" or "target|macro") ..
      "  - how clicks cast (default target)")
    Print("  /br clickreg both|down|up  - which half of the click casts")
    Print("  /br plates  - turn on friendly nameplates (needed for non-group players)")
    if CLASSIC_FEATURES then
      Print("  /br groupcast [on|off|<n>]  - offer group buffs when n+ players need one")
    end
    Print("  /br sort name|role|distance  - list order (role = tanks & leaders first)")
    Print("  /br mana <0-100>  - pause buffing below this mana % (0 = off)")
    Print("  /br export | import  - copy settings between characters as one string")
    Print("  /br compact  - half-height rows   /br text <0.8-1.5>  - list text size")
    Print("  /br charpoint  - per-character window position   /br selftest  - bug-report block")
    Print("  /br ignore <name> | unignore <name> | ignorelist [export|import]   /br summary  - what the group still needs")
    Print("  /br rebuff KEY <sec>  - per-buff rebuff timing (see /br buffs for keys)")
    Print("  /br alertsound droplet|system|none  - new-name alert sound")
    Print("  /br fallsound on|off  - distinct sound when a buff falls off in combat (#33)")
    Print("  /br grouppair \"Single\" \"Group\"  - your own Shift-click group-cast pair")
    Print("  /br why <name>  - why a player is or is not on the list")
    Print("  /br announce  - post missing buffs to party/raid chat")
    Print("  /br signore <name> | unsignore <name>  - ignore for this session only")
    Print("  /br bg  - pause in battlegrounds   /br minimap  - toggle minimap button")
    Print("  /br stats  - casts by spell (all-time)")
    Print("  /br sync | requests | digest  - cast sync, chat-request markers, join summary")
    Print("  /br filter all|tank|healer|dps  - role filter   /br strip  - buff toggle strip")
    Print("  /br fade <0-90>  - idle fade   /br watch  - drop alert   /br taxi  - flight-path pause")
    Print("  /br profile save|load|delete|list <name>  - named settings profiles")
    Print("  /br profile share <name> | profile import  - share ONE profile as a text")
    Print("  /br plan export|import  - share the group buff plan as one string")
    Print("  /br stats export  - cast statistics as text   /br discord  - summary for Discord")
    Print("  /br offenders  - repeat offenders across sessions   /br context KEY raid|instance|always")
    Print("  /br assign <BUFF> <name>  - leader assigns a buff   /br buddy  - split the list")
    Print("  /br readypost  - also post the ready-check summary to group chat")
    Print("  /br death [show]  - recap of who was missing buffs when you died")
    Print("  /br wipe [show]  - rebuff report after a wipe")
    Print("  /br pin <name>  - keep a player at the top   /br pin none  - clear the pin")
    Print("  /br weapon  - watch your weapon enchant   /br enterflash  - instance-entry reminder")
    Print("  /br history  - your recent casts   /br throttle  - halve the rescan rate in big groups")
    Print("  /br growup  - list grows upward   /br theme <name>  - color theme")
    Print("  Combat safety: the list hides and buff buttons are disabled until combat ends.")
    Print("  /br find <text> | findbox  - name finder   /br bars  - duration bars   /br markers  - raid markers")
    Print("  /br focus  - focus target watch line")
    Print("  /br pets  - list group pets   /br context KEY raid|instance|always  - limit a buff")
    if CLASSIC_FEATURES then
      Print("  /br aura  - aura/aspect watch   /br worldbuff  - world-buff watch   /br drink  - drinking healers")
    end
    Print("  /br pill  - all-buffed pill   /br consumables  - flask/food counts")
    Print("  /br custom add|remove|list <id>  - watch any buff spell you know")
    Print("  /br uptime  - coverage uptime %   /br preset raid|dungeon|solo")
    Print("  /br wizard  - run the one-minute setup wizard")
    Print("  /br theme save <name>  - save your current colors as a theme")
    Print("  /br rowgap <0-8> | iconsize <0|10-24> | strata <layer>")
    Print("  /br cover <part> on|off  - pick what the coverage line shows")
    Print("  /br rowcolor <rule> <color|off>  - colored marks on rows")
    Print("  /br tooltip minimal|standard|full  - row tooltip detail")
    Print("  /br autoprofile <context> <profile>  - load a profile by context")
    if CLASSIC_FEATURES then
      Print("  /br bless <CLASS> <BLESSING> [name]  - blessing planner")
    end
    Print("  /br specscale  - remember the scale per specialization   /br snap  - Shift-snap the scale grips")
    Print("  /br tagsymbols | motion | rangewatch  - tag symbols, reduced motion, tell me when someone walks into range")
    Print("  /br apicheck [export] | buffcheck | perf  - diagnostics   /br profile diff <name>  - what a profile would change")
    Print("  /br width <180-400>  - list width")
    Print("  /br resetpos  - reset the window position")
  end
  Refresh()
end

X.HandleSlash = HandleSlash
X.OnOff = OnOff
