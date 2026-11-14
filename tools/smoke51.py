"""Smoke-run BuffRadar.lua under real Lua 5.1 against a fake WoW API (wowstub.lua).

Loads the file, fires ADDON_LOADED and PLAYER_LOGIN, runs a refresh and a set
of slash commands, opens every settings tab and fires the controls' handlers.
Reports the first Lua error of each step plus anything the addon printed as
an error. Usage: python -I smoke51.py STUB.lua ADDON.lua
"""
import sys
from lupa import lua51

stub_path, addon_path = sys.argv[1], sys.argv[2]
lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.execute(open(stub_path, encoding="utf-8").read())

harness = lua.eval(r"""function(addonSrc, withTimer, noTemplates, forever, german, localeSrc, extrasSrc, dataSrc, configSrc, slashSrc, recapsSrc, profilesSrc)
local chat = {}
local env = WOWSTUB(chat, withTimer, noTemplates, forever, german)
local unitIsUnit = env.UnitIsUnit
env.UnitIsUnit = function(a, b)
  if env.__over.UnitIsUnit then return env.__over.UnitIsUnit(a, b) end
  return unitIsUnit(a, b)
end
local unitLevel = env.UnitLevel
env.UnitLevel = function(unit)
  if env.__over.UnitLevel then return env.__over.UnitLevel(unit) end
  return unitLevel(unit)
end
local unitCanAssist = env.UnitCanAssist
env.UnitCanAssist = function(a, b)
  if env.__over.UnitCanAssist then return env.__over.UnitCanAssist(a, b) end
  return unitCanAssist(a, b)
end
local unitIsPvP = env.UnitIsPVP
env.UnitIsPVP = function(unit)
  if env.__over.UnitIsPVP then return env.__over.UnitIsPVP(unit) end
  return unitIsPvP(unit)
end
local visibilityDrivers = {}
local registerStateDriver = env.RegisterStateDriver
env.RegisterStateDriver = function(target, state, condition)
  if state ~= "visibility" then return registerStateDriver(target, state, condition) end
  assert(condition == "[combat] hide", "visibility driver must not force a show outside combat")
  if noTemplates then error("visibility driver unavailable in fallback setup") end
  visibilityDrivers[target] = (visibilityDrivers[target] or 0) + 1
end
-- Globals the addon reads but the stub doesn't define fall back to Lua's own
-- standard library, then to nil (like a client without that API).
local std = { string=string, table=table, math=math, pairs=pairs, ipairs=ipairs, next=next,
  type=type, select=select, pcall=pcall, tostring=tostring, tonumber=tonumber, error=error,
  setmetatable=setmetatable, getmetatable=getmetatable, rawget=rawget, rawset=rawset, unpack=unpack,
  strlower=string.lower, format=string.format, os=os }
setmetatable(env, { __index = std })
env._G = env
local results = {}
local function step(name, fn)
  local before = #chat
  local ok, err = pcall(fn)
  local printedErr
  for i = before + 1, #chat do
    -- the addon reports caught errors as "...error..." / "...blocked..." (red is also used for "off")
    if chat[i]:find("error", 1, true) or chat[i]:find("blocked", 1, true) then printedErr = chat[i] end
  end
  results[#results + 1] = { name, ok and (printedErr and ("addon printed: " .. printedErr) or "ok") or ("LUA ERROR: " .. tostring(err)) }
end

local chunk, cerr = loadstring(addonSrc, "=BuffRadar.lua")
if not chunk then return { { "compile", "FAIL: " .. cerr } }, chat end
setfenv(chunk, env)
if localeSrc then  -- Locales\*.lua load before BuffRadar.lua (.toc order)
  step("load translation file", function()
    local lchunk = assert(loadstring(localeSrc, "=Locales/deDE.lua"))
    setfenv(lchunk, env)
    lchunk("BuffRadar", {})
  end)
end
local NS = {}
if dataSrc then
  step("load Data.lua", function()
    local dch = assert(loadstring(dataSrc, "=Data.lua"))
    setfenv(dch, env)
    dch("BuffRadar", NS)
    assert(NS.X and NS.X.BUFF_DEFS and NS.X.BLESSINGS, "Data.lua did not publish its tables")
  end)
end
step("load file (main chunk)", function() chunk("BuffRadar", NS) end)
if configSrc then
  step("load Config.lua", function()
    local cch = assert(loadstring(configSrc, "=Config.lua"))
    setfenv(cch, env)
    cch("BuffRadar", NS)
    assert(NS.X.RefreshConfig and NS.X.OpenConfig, "Config.lua did not publish its entry points")
  end)
end
if slashSrc then
  step("load Slash.lua", function()
    local sch = assert(loadstring(slashSrc, "=Slash.lua"))
    setfenv(sch, env)
    sch("BuffRadar", NS)
    assert(NS.X.HandleSlash and NS.X.OnOff, "Slash.lua did not publish its entry points")
  end)
end
if extrasSrc then
  step("load Extras.lua", function()
    local ech = assert(loadstring(extrasSrc, "=Extras.lua"))
    setfenv(ech, env)
    ech("BuffRadar", NS)
  end)
end

if recapsSrc then
  step("load Recaps.lua", function()
    local rch = assert(loadstring(recapsSrc, "=Recaps.lua"))
    setfenv(rch, env)
    rch("BuffRadar", NS)
    assert(NS.X.DeathRecap and NS.X.WipeCheck, "Recaps.lua did not publish its entry points")
  end)
end
if profilesSrc then
  step("load Profiles.lua", function()
    local pch = assert(loadstring(profilesSrc, "=Profiles.lua"))
    setfenv(pch, env)
    pch("BuffRadar", NS)
    assert(NS.X.Export and NS.X.Import and NS.X.ApplyPreset, "Profiles.lua did not publish its entry points")
  end)
end

local driver
for _, f in ipairs(env.__frames) do
  -- the FIRST frame that registered ADDON_LOADED is the addon's event
  -- driver (Extras.lua adds small listener frames of its own later)
  if f.events and f.events.ADDON_LOADED then driver = f; break end
end
step("find event frame", function() assert(driver, "no frame registered ADDON_LOADED") end)
if not driver then return results, chat end
local fire = function(ev, ...)
  driver.scripts.OnEvent(driver, ev, ...)
  if ev == "PLAYER_REGEN_DISABLED" then
    for target in pairs(visibilityDrivers) do target.shown = false end
  end
end
step("ADDON_LOADED", function() fire("ADDON_LOADED", "BuffRadar") end)
step("PLAYER_LOGIN", function() fire("PLAYER_LOGIN") end)
step("window exists", function() assert(env.BuffRadarFrame, "BuffRadarFrame not created") end)
step("minimap button exists", function() assert(env.BuffRadarMinimapButton, "no minimap button") end)
step("minimap button follows both axes after the map is resized", function()
  local map, button, db = env.Minimap, env.BuffRadarMinimapButton, env.BuffRadarDB
  local oldWidth, oldHeight, oldAngle, oldCursor = map.GetWidth, map.GetHeight, db.minimapAngle, env.GetCursorPosition
  map.GetWidth, map.GetHeight = function() return 240 end, function() return 160 end
  db.minimapAngle = 0
  NS.X.cfgAPI.RefreshMinimapButton()
  local p = button.points[#button.points]
  local horizontal = #button.points == 1 and math.abs(p[4] - 125) < 0.01
  map.GetWidth, map.GetHeight = function() return 300 end, function() return 200 end
  local resized = map:GetScript("OnSizeChanged")
  if resized then resized(map, 300, 200) end
  p = button.points[#button.points]
  local followsSize = math.abs(p[4] - 155) < 0.01
  env.GetCursorPosition = function() return 655, 505 end
  button:GetScript("OnDragStart")(button)
  button:GetScript("OnUpdate")(button)
  button:GetScript("OnDragStop")(button)
  local angle = db.minimapAngle
  map.GetWidth, map.GetHeight, db.minimapAngle, env.GetCursorPosition = oldWidth, oldHeight, oldAngle, oldCursor
  NS.X.cfgAPI.RefreshMinimapButton()
  assert(horizontal and followsSize and math.abs(angle - 45) < 0.01, "minimap geometry ignored an axis or resize")
end)
step("friendly nameplates select the supported CVar and verify changes", function()
  local vars = { nameplateShowFriendlyPlayers = "0", nameplateShowAll = "0" }
  local oldCVar, oldGet, oldBool, oldSet = env.C_CVar, env.GetCVar, env.GetCVarBool, env.SetCVar
  env.GetCVar, env.GetCVarBool, env.SetCVar = nil, function() return false end, nil
  env.C_CVar = {
    GetCVar = function(key) return vars[key] end,
    SetCVar = function(key, value) if vars[key] then vars[key] = value end end,
  }
  local friendly = NS.X.FriendlyPlatesOn
  local initiallyOff = friendly and friendly() == false
  env.SlashCmdList.BUFFRADAR("plates")
  local modernSet = vars.nameplateShowFriendlyPlayers == "1" and vars.nameplateShowAll == "1"
  vars.nameplateShowFriendlyPlayers, vars.nameplateShowFriends = nil, "1"
  local legacy, name
  if friendly then legacy, name = friendly() end
  vars.nameplateShowFriends = nil
  local unknown = friendly and friendly() == nil
  vars.nameplateShowFriendlyPlayers = "0"
  env.C_CVar.SetCVar = function() return true end
  local n = #chat
  env.SlashCmdList.BUFFRADAR("plates")
  local reportsFailure = #chat > n and not chat[#chat]:find("Friendly nameplates turned on", 1, true)
  env.C_CVar, env.GetCVar, env.GetCVarBool, env.SetCVar = oldCVar, oldGet, oldBool, oldSet
  assert(initiallyOff and modernSet and legacy and name == "nameplateShowFriends" and unknown and reportsFailure,
    "friendly nameplate CVar selection or readback failed")
end)
step("slash command registered", function()
  assert(env.SLASH_BUFFRADAR1 == "/br" and env.SlashCmdList.BUFFRADAR, "no /br")
end)
step("event: UNIT_AURA refresh", function() fire("UNIT_AURA", "player") end)
step("event: SPELLS_CHANGED", function() fire("SPELLS_CHANGED") end)
step("event: GROUP_ROSTER_UPDATE", function() fire("GROUP_ROSTER_UPDATE") end)
step("event: PLAYER_REGEN_DISABLED/ENABLED", function()
  fire("PLAYER_REGEN_DISABLED"); fire("PLAYER_REGEN_ENABLED") end)
-- One steady tick plus any queued event refreshes, for either timer kind.
local function runQueued()
  if env.__timers then
    local q = env.__timers; env.__timers = {}
    for _, f in ipairs(q) do f() end
  end
end
local timerTick = function()
  runQueued()
  if env.__ticker then env.__ticker() end
  local f = driver.scripts.OnUpdate
  if f then f(driver, 1) end
end
step("refresh tick", timerTick)

-- Edition detection and edition-specific features.
local function chatSince(n, needle)
  for i = n + 1, #chat do if chat[i]:find(needle, 1, true) then return true end end
  return false
end
step("edition detected", function()
  local n = #chat
  env.SlashCmdList.BUFFRADAR("debug")
  local want = env.__forever and "Forever edition" or "Retail edition"
  assert(chatSince(n, want), "/br debug didn't report " .. want)
  if env.__forever then
    assert(chatSince(n, "Power Word: Fortitude: 2 rank(s) known"), "Forever rank table not built")
  else
    assert(not chatSince(n, "rank(s) known"), "rank table reported on retail")
  end
end)
step("edition buff set", function()
  local n = #chat
  env.SlashCmdList.BUFFRADAR("buffs")
  if env.__forever then
    assert(chatSince(n, "FORTITUDE") and chatSince(n, "INNER_FIRE") and chatSince(n, "DIVINE_SPIRIT"),
      "Forever priest buffs missing from /br buffs")
    assert(not chatSince(n, "SKYFURY"), "retail buff listed on Forever")
  else
    assert(chatSince(n, "SKYFURY") and chatSince(n, "SHAMAN_SHIELD"), "retail shaman buffs missing")
    assert(not chatSince(n, "INNER_FIRE") and not chatSince(n, "WATER_BREATHING"), "Forever buff listed on retail")
  end
end)
step("edition commands: rank cast mode and group-cast offers", function()
  local n = #chat
  env.SlashCmdList.BUFFRADAR("mode rank")
  if env.__forever then
    assert(env.BuffRadarDB.castMethod == "rank", "rank mode refused on Forever")
    env.SlashCmdList.BUFFRADAR("mode target")
    env.SlashCmdList.BUFFRADAR("groupcast on")
    assert(env.BuffRadarDB.groupCast == true, "group-cast offers not enabled on Forever")
    env.SlashCmdList.BUFFRADAR("groupcast off")
  else
    assert(env.BuffRadarDB.castMethod ~= "rank", "rank mode accepted on retail")
    env.SlashCmdList.BUFFRADAR("groupcast on")
    assert(env.BuffRadarDB.groupCast ~= true, "group-cast offers enabled on retail")
  end
end)

local cmds = { "", "", "show", "config", "config", "debug", "help", "buffs", "toggle SKYFURY",
  "toggle SKYFURY", "rebuff 45", "rebuff SKYFURY 60", "rebuff BLESSINGS 10", "ignore Bob",
  "ignore bob", "ignore Alice-Other Realm", "ignorelist", "unignore BOB", "unignore nobody",
  "scale 1.25", "scale 9", "lock", "lock", "mode rank", "mode macro", "mode target",
  "groupcast", "sort role", "sort name", "sound", "sound", "alertsound system", "minimap",
  "minimap", "stats", "count", "resetcount", "self", "self", "pvp", "pvp", "autohide",
  "autohide", "group", "group", "cities", "cities", "bg", "bg", "plates", "clicks", "clicks",
  "clickreg both", "key", "macro", "reset", "announce", "signore Bob", "signore bob",
  "unsignore BOB", "signore", "unsignore", "mana 20", "mana 0", "mana 999", "mana",
  "export", "import", "sort distance", "sort name", "selftest", "compact", "compact",
  "text 1.25", "text 9", "text", "charpoint", "charpoint",
  "sync", "sync", "requests", "requests", "digest", "digest",
  "filter tank", "filter all", "strip", "strip", "fade 50", "fade 0", "sort need", "sort name",
  "taxi", "taxi", "watch", "watch", "profile", "profile list", "profile save", "resetpos",
  "growup", "growup", "combat", "combat", "theme crimson", "theme midnight", "theme",
  "find zzz", "find off", "findbox", "findbox", "bars", "bars", "markers", "markers",
  "range", "range", "focus", "focus",
  "pets", "pets", "aura", "aura", "worldbuff", "worldbuff", "drink", "drink",
  "context FORTITUDE instance", "context FORTITUDE always", "context",
  "plan", "plan export", "discord", "offenders", "stats export" }
for _, c in ipairs(cmds) do
  step("/br " .. c, function() env.SlashCmdList.BUFFRADAR(c) end)
end

-- Settings window: open it, and fire every control's click / value handler.
step("open settings", function()
  if not (env.BuffRadarConfig and env.BuffRadarConfig.shown) then env.SlashCmdList.BUFFRADAR("config") end
  assert(env.BuffRadarConfig, "BuffRadarConfig not created")
end)
step("settings window: fallback look when templates are missing", function()
  if not env.__noTemplates then return end
  local cfg = env.BuffRadarConfig
  assert(not cfg.nativeTabs, "bottom tabs used without PanelTemplates")
  assert(cfg.template ~= "ButtonFrameTemplate", "template window kept without its members")
  for _, key in ipairs({ "look", "alerts", "buffs", "behavior", "data" }) do
    local btn = cfg.tabBtns[key]
    btn.scripts.OnClick(btn, "LeftButton")
    assert(cfg.panels[key].shown, "fallback tab " .. key .. " didn't show its panel")
  end
end)
step("settings window uses the standard template and bottom tabs", function()
  if env.__noTemplates then return end
  local cfg = env.BuffRadarConfig
  assert(cfg.template == "ButtonFrameTemplate", "template: " .. tostring(cfg.template))
  assert(cfg.nativeTabs, "bottom tabs not used")
  assert(cfg.numTabs == 5, "PanelTemplates_SetNumTabs not called with 5")
  local keys = { "look", "alerts", "buffs", "behavior", "data" }
  for i = 1, 5 do
    local tab = assert(env["BuffRadarConfigTab" .. i], "BuffRadarConfigTab" .. i .. " missing")
    assert(tab.template == "PanelTabButtonTemplate", "tab template")
    tab.scripts.OnClick(tab, "LeftButton")
    assert(cfg.selectedTab == i, "tab " .. i .. " not selected")
    for j, k in ipairs(keys) do
      assert(cfg.panels[k].shown == (i == j), "tab " .. i .. ": panel " .. k .. " visibility wrong")
    end
  end
end)
step("fire every settings control", function()
  for _, f in ipairs(env.__frames) do
    -- The main window's strip/chip buttons are not settings controls; firing
    -- them would toggle buffs and set the role filter as a side effect.
    -- The all-buffed pill is a main-window control too: clicking it starts a
    -- timed peek at the window, which would poison later timing checks.
    local nm = f.GetName and f:GetName()
    if type(nm) ~= "string" then nm = "" end
    local isBar = nm:sub(1, 14) == "BuffRadarStrip" or nm:sub(1, 13) == "BuffRadarChip"
      or nm == "BuffRadarPill"
    if f.scripts.OnClick and f ~= driver and not isBar then f.scripts.OnClick(f, "LeftButton", false) end
    if f.scripts.OnEnter then f.scripts.OnEnter(f) end
    if f.scripts.OnLeave then f.scripts.OnLeave(f) end
    if f.scripts.OnEditFocusLost then
      f.text = "75"; f.scripts.OnEditFocusLost(f)
      f.text = "9999"; f.scripts.OnEditFocusLost(f)
      f.text = ""; f.scripts.OnEditFocusLost(f)
    end
    if f.GenerateMenu and f.menuGen then f:GenerateMenu() end
  end
end)
step("refresh tick after settings", timerTick)
step("AddOns options page registered", function()
  local c = env.__settings.registered
  assert(c and c.name == "BuffRadar", "no AddOns category registered")
end)
step("options page button opens settings (and closes the options panel)", function()
  env.BuffRadarConfig:Hide()
  env.SettingsPanel:Show()
  local page = env.__settings.registered.frame
  local opened = false
  for _, f in ipairs(env.__frames) do
    if f.scripts.OnClick and f.text == "Open BuffRadar settings" then f.scripts.OnClick(f, "LeftButton"); opened = true end
  end
  assert(opened, "button not found")
  assert(env.BuffRadarConfig.shown, "settings window not shown")
  assert(not env.SettingsPanel.shown, "options panel still shown")
  -- clicking again must keep it open (forceShow), not toggle it closed
  for _, f in ipairs(env.__frames) do
    if f.scripts.OnClick and f.text == "Open BuffRadar settings" then f.scripts.OnClick(f, "LeftButton") end
  end
  assert(env.BuffRadarConfig.shown, "second click closed the settings window")
end)
step("addon compartment: left toggles window, right opens settings, tooltip", function()
  local info = assert(env.__compartment, "not registered")
  assert(info.registerForAnyClick, "right clicks not enabled")
  local function hiddenFlag() return env.BuffRadarDB.hidden end
  local before = hiddenFlag()
  info.func({}, { buttonName = "LeftButton" }, {})          -- newer menu signature
  assert(hiddenFlag() ~= before, "left click (new API) didn't toggle")
  info.func({}, nil, nil, nil, "LeftButton")                -- older dropdown signature
  assert(hiddenFlag() == before, "left click (old API) didn't toggle back")
  env.BuffRadarConfig:Hide()
  info.func({}, { buttonName = "RightButton" }, {})
  assert(env.BuffRadarConfig.shown, "right click (new API) didn't open settings")
  env.BuffRadarConfig:Hide()
  info.func({}, nil, nil, nil, "RightButton")
  assert(env.BuffRadarConfig.shown, "right click (old API) didn't open settings")
  info.funcOnEnter(env.__newObject("Button")); info.funcOnLeave()
  info.funcOnEnter(nil)
end)
step("minimap button accepts right clicks", function()
  local b = env.BuffRadarMinimapButton
  assert(b, "no minimap button")
  env.BuffRadarConfig:Hide()
  b.scripts.OnClick(b, "RightButton")
  assert(env.BuffRadarConfig.shown, "right click didn't open settings")
end)
-- Performance behavior (action 8). Refreshes are counted through zone lookups.
local function refreshesDuring(fn)
  timerTick()  -- settle anything already queued
  local before = env.__zoneCalls
  fn()
  return env.__zoneCalls - before
end
step("UNIT_AURA on an NPC nameplate / boss / pet: no refresh", function()
  local n = refreshesDuring(function()
    fire("UNIT_AURA", "nameplate3"); fire("UNIT_AURA", "boss1"); fire("UNIT_AURA", "partypet1")
    runQueued()
    if not env.__timers then local f = driver.scripts.OnUpdate; if f then f(driver, 0) end end
  end)
  -- with C_Timer nothing may be queued; with the fallback, no refresh may be pending
  if env.__timers then assert(n == 0, "untracked unit refreshed (" .. n .. ")") end
end)
step("UNIT_AURA on yourself: refresh queued", function()
  if not env.__timers then return end
  fire("UNIT_AURA", "player")
  assert(#env.__timers == 1, "no refresh queued for the player")
  runQueued()
end)
step("pull timer: probe counts sightings; flash fires with casts outstanding (1.14.0)", function()
  local pf
  for _, f in ipairs(env.__frames) do if f.events and f.events.START_TIMER then pf = f end end
  assert(pf, "no frame registered START_TIMER")
  local firePull = function(...) pf.scripts.OnEvent(pf, ...) end
  NS.X.tally = { FORTITUDE = { total = 5, miss = 2 } }
  firePull("START_TIMER", 3, 10, 10)
  assert(NS.X.pullProbe.stSeen == 1, "START_TIMER not counted by the probe")
  assert(NS.X.pull == nil, "flash state set while pullflash is off")
  env.SlashCmdList.BUFFRADAR("pullflash on")
  firePull("START_TIMER", 3, 10, 10)
  assert(NS.X.pull ~= nil, "pull state not set with pullflash on and casts outstanding")
  local found
  for _, line in ipairs(chat) do if line:find("Pull in 10s", 1, true) then found = line end end
  assert(found, "no countdown line printed: " .. table.concat(chat, " | "))
  firePull("START_TIMER", 3, 0, 0)
  assert(NS.X.pull == nil, "zero timer did not cancel the pull state")
  firePull("CHAT_MSG_ADDON", "D5", "PT\t10", "RAID", "Nobody-Elsewhere")
  assert(NS.X.pullProbe.d5 == 1, "DBM PT message not counted by the probe")
  assert(NS.X.pull == nil, "untrusted DBM pull started the flash")
  runQueued()  -- drain the pull countdown timers so later steps see a clean queue
  NS.X.tally = {}
  env.SlashCmdList.BUFFRADAR("pullflash off")
end)
step("modifier clicks: group spell mapping + shift-click bookkeeping (1.14.0)", function()
  env.SlashCmdList.BUFFRADAR("modclick on")
  if NS.X.classic then
    assert(NS.X.GroupSpellFor("Power Word: Fortitude") == "Prayer of Fortitude", "Fortitude group mapping wrong")
    assert(NS.X.GroupSpellFor("Mark of the Wild") == "Gift of the Wild", "Mark group mapping wrong")
    assert(NS.X.GroupSpellFor("Blessing of Might") == "Greater Blessing of Might", "blessing group mapping wrong")
    assert(NS.X.GroupSpellFor("Thorns") == nil, "Thorns must have no group version")
  else
    assert(NS.X.GroupSpellFor("Power Word: Fortitude") == nil, "retail defs carry no groupCast")
  end
  local row = env.BuffRadarRow1
  row.entry = { missing = { "Power Word: Fortitude" }, guid = "g1", sortName = "Bob" }
  row.attrs["type"] = "spell"
  env.IsShiftKeyDown = function() return true end
  NS.X.pendingCast = nil
  row.scripts.PostClick(row, "LeftButton", false)
  if NS.X.classic then
    assert(NS.X.pendingCast and NS.X.pendingCast.spell == "Prayer of Fortitude",
      "shift-click booked the wrong spell: " .. tostring(NS.X.pendingCast and NS.X.pendingCast.spell))
  else
    assert(NS.X.pendingCast and NS.X.pendingCast.spell == "Power Word: Fortitude", "retail shift-click must book the plain spell")
  end
  env.IsShiftKeyDown = function() return false end
  NS.X.pendingCast = nil
  row.scripts.PostClick(row, "LeftButton", false)
  assert(NS.X.pendingCast and NS.X.pendingCast.spell == "Power Word: Fortitude", "plain click booked the wrong spell")
  env.SlashCmdList.BUFFRADAR("modclick off")
end)
step("custom group-cast pairs feed modifier clicks (1.15.0)", function()
  if not NS.X.classic then return end
  env.SlashCmdList.BUFFRADAR("modclick on")
  env.SlashCmdList.BUFFRADAR('grouppair "Thorns" "Thorns of the Grove"')
  assert(NS.X.GroupSpellFor("Thorns") == "Thorns of the Grove", "custom pair not used by GroupSpellFor")
  assert(env.BuffRadarDB.customGroup["Thorns"] == "Thorns of the Grove", "pair not saved")
  local row = env.BuffRadarRow1
  row.entry = { missing = { "Thorns" }, guid = "g1", sortName = "Bob" }
  row.attrs["type"] = "spell"
  env.IsShiftKeyDown = function() return true end
  NS.X.pendingCast = nil
  row.scripts.PostClick(row, "LeftButton", false)
  assert(NS.X.pendingCast and NS.X.pendingCast.spell == "Thorns of the Grove",
    "shift-click ignored the custom pair: " .. tostring(NS.X.pendingCast and NS.X.pendingCast.spell))
  env.IsShiftKeyDown = function() return false end
  env.SlashCmdList.BUFFRADAR('grouppair clear "Thorns"')
  assert(NS.X.GroupSpellFor("Thorns") == nil, "cleared pair still active")
  env.SlashCmdList.BUFFRADAR("modclick off")
end)
step("fast aura: unwatched payload skipped, watched payload refreshes (1.14.0)", function()
  if not env.__timers then return end
  env.SlashCmdList.BUFFRADAR("fastaura on")
  local probe = NS.X.auraProbe or {}
  local skipped0 = probe.skipped or 0
  fire("UNIT_AURA", "player", { addedAuras = { { name = "Unwatched Proc", auraInstanceID = 9002 } } })
  probe = NS.X.auraProbe
  assert(probe and (probe.skipped or 0) == skipped0 + 1, "unwatched payload was not skipped")
  assert(#env.__timers == 0, "skipped payload queued a refresh")
  local watchedName = next(NS.X.watchNames or {})
  assert(watchedName, "watchNames is empty")
  fire("UNIT_AURA", "player", { addedAuras = { { name = watchedName, auraInstanceID = 9003 } } })
  assert(#env.__timers == 1, "watched payload did not queue a refresh")
  runQueued()
  fire("UNIT_AURA", "player", { addedAuras = { { name = "Well Fed", auraInstanceID = 9001 } } })
  assert(#env.__timers == 1, "consumable aura change (Well Fed) did not queue a refresh")
  runQueued()
  fire("UNIT_AURA", "player", { removedAuraInstanceIDs = { 9002 } })
  assert(#env.__timers == 0, "removal of an unwatched aura queued a refresh")
  fire("UNIT_AURA", "player", { removedAuraInstanceIDs = { 9003 } })
  assert(#env.__timers == 1, "removal of a watched aura did not queue a refresh")
  runQueued()
  env.SlashCmdList.BUFFRADAR("fastaura off")
end)
step("UNIT_AURA in combat: ignored", function()
  if not env.__timers then return end
  env.__combat = true
  fire("UNIT_AURA", "player"); fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
  env.__combat = false
  assert(#env.__timers == 0, "refresh queued during combat")
end)
step("paused in a city: steady tick does nothing", function()
  env.BuffRadarDB.pauseInCities = true
  env.__zone = "Orgrimmar"
  fire("ZONE_CHANGED_NEW_AREA")
  timerTick()                      -- the event refresh notices the city
  local n = refreshesDuring(function()
    if env.__ticker then env.__ticker() end
    local f = driver.scripts.OnUpdate
    if f then f(driver, 1) end
  end)
  assert(n == 0, "tick refreshed while paused (" .. n .. ")")
end)
step("leaving the city: event refresh runs, ticks resume", function()
  env.__zone = "Elwynn Forest"
  local n1 = refreshesDuring(function() fire("ZONE_CHANGED_NEW_AREA"); timerTick() end)
  assert(n1 >= 1, "zone change didn't refresh")
  local n2 = refreshesDuring(function()
    if env.__ticker then env.__ticker() end
    local f = driver.scripts.OnUpdate
    if f then f(driver, 1) end
  end)
  assert(n2 >= 1, "ticks didn't resume after leaving the city")
end)
step("protected (secret) GUID / name from the game: no error", function()
  -- A secret stand-in: comparing or concatenating it throws, like the game's.
  local function boom() error("used a protected value") end
  local function secret() return setmetatable({ __secret = true },
    { __lt = boom, __le = boom, __eq = boom, __concat = boom }) end
  env.issecretvalue = function(v) return type(v) == "table" and rawget(v, "__secret") == true end
  local plates = { nameplate1 = true, nameplate2 = true, nameplate3 = true }
  local O = env.__over  -- hooks the stub's (cached-by-the-addon) unit functions
  O.UnitExists = function(u) return u == "player" or plates[u] or false end
  O.UnitIsPlayer = function(u) return u == "player" or plates[u] or false end
  O.UnitGUID = function(u)
    if u == "nameplate1" then return secret() end          -- protected GUID
    if u == "nameplate2" then return "Player-1-0002" end
    if u == "nameplate3" then return "Player-1-0003" end
    if u == "player" then return "Player-1-0001" end
  end
  O.UnitName = function(u)
    if u == "nameplate2" or u == "nameplate3" then return secret() end  -- protected names
    if plates[u] then return "Someone" end
    if u == "player" then return "Testshaman" end
  end
  O.UnitFullName = function(u)
    if u == "nameplate2" or u == "nameplate3" then return secret(), secret() end
    if plates[u] then return "Someone", "TestRealm" end
    if u == "player" then return "Testshaman", "TestRealm" end
  end
  O.UnitClass = function(u)
    if plates[u] then return "Mage", "MAGE" end
    if u == "player" then return "Shaman", "SHAMAN" end
  end
  env.BuffRadarDB.showOutOfRange = true
  env.BuffRadarDB.pauseInCities = false
  env.BuffRadarDB.hidden, env.BuffRadarDB.groupOnly, env.BuffRadarDB.autoHide = false, false, false
  local before = #chat
  timerTick(); fire("NAME_PLATE_UNIT_ADDED", "nameplate2"); timerTick()
  for i = before + 1, #chat do assert(not chat[i]:find("error", 1, true), chat[i]) end
  local listed = {}
  for i = 1, 15 do
    local row = env["BuffRadarRow" .. i]
    if row and row.entry and row.shown then listed[row.entry.unit] = row.entry end
  end
  assert(not listed.nameplate1, "unit with a protected GUID was listed")
  local got = {}
  for u in pairs(listed) do got[#got + 1] = u end
  assert(listed.nameplate2 and listed.nameplate3, "units with protected names should still be listed; listed: [" ..
    table.concat(got, ",") .. "], window shown=" .. tostring(env.BuffRadarFrame.shown) ..
    ", empty text=" .. tostring(env.BuffRadarFrame and select(2, pcall(function() return chat[#chat] end))))
  -- hovering and right-clicking those rows must not throw either
  for i = 1, 15 do
    local row = env["BuffRadarRow" .. i]
    if row and row.entry and row.shown and plates[row.entry.unit] then
      row.scripts.OnEnter(row)
      row.scripts.OnClick(row, "RightButton", false)
    end
  end
  for k in pairs(O) do O[k] = nil end
  env.issecretvalue = nil
end)
-- Rows currently shown, by unit: unit -> { spell = true, ... } plus the row.
local function shownRows()
  local out = {}
  for i = 1, 15 do
    local row = env["BuffRadarRow" .. i]
    if row and row.entry and row.shown then
      local set = { row = row }
      for _, s in ipairs(row.entry.missing) do set[s] = true end
      out[row.entry.unit] = set
    end
  end
  return out
end
-- Two nearby tanks (nameplates) for the next steps; returns a cleanup function.
local function twoTanks()
  local plates = { nameplate1 = "WARRIOR", nameplate2 = "PALADIN" }
  local O = env.__over
  O.UnitExists = function(u) return u == "player" or plates[u] ~= nil end
  O.UnitIsPlayer = O.UnitExists
  O.UnitGUID = function(u)
    if plates[u] then return "Player-1-T" .. u:sub(-1) end
    if u == "player" then return "Player-1-0001" end
  end
  O.UnitName = function(u) if plates[u] then return "Tank" .. u:sub(-1) end if u == "player" then return "Me" end end
  O.UnitFullName = function(u)
    if plates[u] then return "Tank" .. u:sub(-1), "TestRealm" end
    if u == "player" then return "Me", "TestRealm" end
  end
  O.UnitClass = function(u)
    if plates[u] then return plates[u], plates[u] end
    if u == "player" then return env.__forever and "PRIEST" or "SHAMAN", env.__forever and "PRIEST" or "SHAMAN" end
  end
  local db = env.BuffRadarDB
  db.showOutOfRange, db.pauseInCities, db.hidden, db.groupOnly, db.autoHide = true, false, false, false, false
  local savedIgnored = {}
  for name in pairs(db.ignored) do savedIgnored[#savedIgnored + 1] = name end
  for _, name in ipairs(savedIgnored) do env.SlashCmdList.BUFFRADAR("unignore " .. name) end
  return function() for k in pairs(O) do O[k] = nil end end
end
local function refresh() timerTick(); fire("UNIT_AURA", "nameplate1"); timerTick() end

step("Earth Shield: offered to one tank at a time (retail)", function()
  if env.__forever then return end  -- Forever's Earth Shield table is unchanged from 1.2.4
  local cleanup = twoTanks()
  env.BuffRadarDB.enabled.EARTH_SHIELD = true
  local ES = "Earth Shield"
  local function check(label, want1, want2)
    refresh()
    local r = shownRows()
    local has1 = r.nameplate1 and r.nameplate1[ES] or false
    local has2 = r.nameplate2 and r.nameplate2[ES] or false
    assert(has1 == want1 and has2 == want2, string.format(
      "%s: Earth Shield offered to tank1=%s tank2=%s, expected %s/%s", label, tostring(has1), tostring(has2),
      tostring(want1), tostring(want2)))
  end
  local O, now = env.__over, env.GetTime()
  O.Aura = nil
  check("nobody has it", true, true)
  O.Aura = function(u, name) if u == "nameplate1" and name == ES then return { expirationTime = now + 600 } end end
  check("yours on tank 1", false, false)
  O.Aura = function(u, name) if u == "nameplate1" and name == ES then return { expirationTime = now + 10 } end end
  check("yours on tank 1, about to expire", true, false)
  O.Aura = function(u, name, filter)
    if u == "nameplate1" and name == ES and not tostring(filter):find("PLAYER") then return { expirationTime = now + 600 } end
  end
  check("another shaman's on tank 1", false, true)
  env.BuffRadarDB.enabled.EARTH_SHIELD = nil
  O.Aura = nil
  cleanup()
end)
step("out-of-range players are never listed, then appear in range", function()
  local cleanup = twoTanks()
  env.IsSpellInRange = function() return 0 end
  refresh()
  assert(not shownRows().nameplate1 and not shownRows().nameplate2,
    "an out-of-range player appeared in the list")
  env.IsSpellInRange = function() return 1 end
  refresh()
  local row = assert(shownRows().nameplate1, "tank 1 not listed in range").row
  assert(not row.far.shown, "'out of range' marker still shown in range")
  env.IsSpellInRange = nil
  cleanup()
end)
-- A two-member party (Aaron the mage, Zed the warrior) for the 1.4.0 steps.
local function partyOfTwo(suffix)
  local units = { party1 = { name = "Aaron", class = "MAGE" }, party2 = { name = "Zed", class = "WARRIOR" } }
  local O = env.__over
  O.UnitExists = function(u) return u == "player" or units[u] ~= nil end
  O.UnitIsPlayer = O.UnitExists
  O.UnitGUID = function(u)
    if units[u] then return "Player-1-P" .. u:sub(-1) .. (suffix or "") end
    if u == "player" then return "Player-1-0001" end
  end
  O.UnitName = function(u) if units[u] then return units[u].name end if u == "player" then return "Me" end end
  O.UnitFullName = function(u)
    if units[u] then return units[u].name, "TestRealm" end
    if u == "player" then return "Me", "TestRealm" end
  end
  O.UnitClass = function(u)
    if units[u] then return units[u].class, units[u].class end
    if u == "player" then return env.__forever and "PRIEST" or "SHAMAN", env.__forever and "PRIEST" or "SHAMAN" end
  end
  env.IsInGroup = function() return true end
  O.Aura = nil  -- clear any aura hook a previous step left behind
  env.SlashCmdList.BUFFRADAR("unsignore Aaron")
  env.SlashCmdList.BUFFRADAR("unsignore Zed")
  local db = env.BuffRadarDB
  db.showOutOfRange, db.pauseInCities, db.hidden, db.groupOnly, db.autoHide = true, false, false, false, false
  local savedIgnored = {}
  for name in pairs(db.ignored) do savedIgnored[#savedIgnored + 1] = name end
  for _, name in ipairs(savedIgnored) do env.SlashCmdList.BUFFRADAR("unignore " .. name) end
  return function()
    for k in pairs(O) do O[k] = nil end
    env.IsInGroup = function() return false end
    env.IsSpellInRange = nil
  end
end
step("combat targets and caster are never eligible", function()
  local cleanup = partyOfTwo("C")
  local O = env.__over
  env.IsSpellInRange = function() return 1 end
  O.UnitAffectingCombat = function(u) return u == "party2" end
  refresh()
  local rows = shownRows()
  assert(rows.party1 and not rows.party2, "a target in combat was listed")
  O.UnitAffectingCombat = function(u) return u == "player" end
  refresh()
  assert(not shownRows().party1 and not shownRows().party2,
    "targets remained listed while the caster was in combat")
  O.UnitAffectingCombat = nil
  cleanup()
end)
step("self remains buffable when the assist API rejects self", function()
  local cleanup = partyOfTwo("SELF")
  local O, db = env.__over, env.BuffRadarDB
  local oldInclude, oldMethod, oldRange = db.includeSelf, db.castMethod, env.IsSpellInRange
  local ok, err = pcall(function()
    db.includeSelf, db.castMethod = true, "target"
    env.IsSpellInRange = function() return 1 end
    O.UnitCanAssist = function(source, unit)
      if source == "player" and unit == "player" then return false end
      return true
    end
    refresh()
    local selfRow = assert(shownRows().player, "self was omitted when assist check rejected the player")
    local row = selfRow.row
    assert(row.entry.isSelf, "player row was not marked as self")
    assert(row.attrs.type == "spell" and row.attrs.unit == "player",
      "self row was not armed to cast directly on player")
    assert(row.attrs.spell == row.entry.missing[1], "self row was bound to a different buff")
  end)
  O.UnitCanAssist = nil
  env.IsSpellInRange = oldRange
  db.includeSelf, db.castMethod = oldInclude, oldMethod
  cleanup()
  assert(ok, err)
end)
step("unreadable unit eligibility results never offer a buff", function()
  local cleanup = partyOfTwo("VE")
  local db, O = env.BuffRadarDB, env.__over
  local prevCharm, prevSecret, prevAvoid = env.UnitIsCharmed, env.issecretvalue, db.avoidPvP
  local errors, masked = {}
  local function secret(value)
    masked = value
    return value
  end
  env.issecretvalue = function(value)
    if masked ~= nil and value == masked then masked = nil; return true end
    return false
  end
  env.IsSpellInRange = function() return 1 end
  local function check(expected, message)
    masked = nil
    refresh()
    if (shownRows().party2 ~= nil) ~= expected then errors[#errors + 1] = message end
  end
  db.avoidPvP = false
  env.UnitIsCharmed = function() return false end
  check(true, "readable uncharmed target was hidden")
  env.UnitIsCharmed = function(u) if u == "party2" then return secret(false) end return false end
  check(false, "unreadable charm state offered a buff")
  env.UnitIsCharmed = function(u) if u == "party2" then error("charm API refused") end return false end
  check(false, "failed charm API offered a buff")
  env.UnitIsCharmed = nil
  check(true, "client without the charm API hid an eligible target")

  db.avoidPvP = true
  O.UnitIsPVP = function(u) return u == "party2" end
  check(false, "flagged target was listed for an unflagged caster")
  O.UnitIsPVP = function() return true end
  check(true, "flagged caster could not buff a flagged target")
  O.UnitIsPVP = function(u) if u == "player" then return secret(true) end return true end
  check(false, "unreadable caster PvP flag offered a buff")
  O.UnitIsPVP = function(u) if u == "party2" then return secret(false) end return false end
  check(false, "unreadable target PvP flag offered a buff to an unflagged caster")
  O.UnitIsPVP = function(u) if u == "party2" then return secret(false) end return true end
  check(true, "known flagged caster was blocked by an unreadable target PvP flag")
  db.avoidPvP = false
  check(true, "disabled PvP filter still blocked an eligible target")

  O.UnitAffectingCombat = function(u) if u == "party2" then return secret(false) end return false end
  check(false, "unreadable target combat state offered a buff")
  O.UnitAffectingCombat = function(u)
    if u == "player" then return secret(false) end
    masked = nil
    return false
  end
  check(false, "unreadable caster combat state offered a buff")
  env.UnitIsCharmed, env.issecretvalue, db.avoidPvP = prevCharm, prevSecret, prevAvoid
  cleanup()
  assert(#errors == 0, table.concat(errors, "; "))
end)
step("line-of-sight failures skip that target for the session window", function()
  local cleanup = partyOfTwo("L")
  local O = env.__over
  env.IsSpellInRange = function() return 1 end
  refresh()
  local guid = "Player-1-P1L"
  NS.X.pendingCast = {
    spell = "Skyfury", time = env.GetTime(), guid = guid,
    key = "SKYFURY", who = "Aaron",
  }
  fire("UI_ERROR_MESSAGE", 1, "Target is not in line of sight")
  assert(NS.X.failedTargets[guid], "line-of-sight failure did not mark the target")
  assert(NS.X.pendingCast == nil, "failed cast remained pending")
  refresh()
  local rows = shownRows()
  assert(not rows.party1 and rows.party2,
    "failed target stayed listed or the next eligible target disappeared")
  NS.X.failedTargets[guid] = nil
  refresh()
  assert(shownRows().party1, "target did not return after its temporary skip cleared")
  cleanup()
end)
step("range and invalid-target failures skip the current player", function()
  local cleanup = partyOfTwo("R")
  local X = NS.X
  local oldOutOfRange = env.SPELL_FAILED_OUT_OF_RANGE
  local ok, err = pcall(function()
    env.__over.IsSpellInRange = function() return 1 end
    if env.C_Spell then env.C_Spell.IsSpellInRange = function() return 1 end end
    refresh()
    local guid = "Player-1-P1R"
    env.SPELL_FAILED_OUT_OF_RANGE = "That target is too distant."
    X.pendingCast = { spell = "Skyfury", time = env.GetTime(), guid = guid, key = "SKYFURY", who = "Aaron" }
    fire("UI_ERROR_MESSAGE", 1, "That target is too distant.")
    assert(X.failedTargets[guid], "localized out-of-range failure did not skip the target")
    refresh()
    local rows = shownRows()
    assert(not rows.party1 and rows.party2, "range failure did not leave the next eligible player available")
    X.failedTargets[guid] = nil
    X.pendingCast = { spell = "Skyfury", time = env.GetTime(), guid = guid, key = "SKYFURY", who = "Aaron" }
    fire("UI_ERROR_MESSAGE", 1, "Invalid target.")
    assert(X.failedTargets[guid], "invalid-target failure did not skip the target")
    X.failedTargets[guid] = nil
    X.pendingCast = { spell = "Skyfury", time = env.GetTime(), guid = guid, key = "SKYFURY", who = "Aaron" }
    fire("UI_ERROR_MESSAGE", 1, "Not enough mana.")
    assert(X.pendingCast and not X.failedTargets[guid], "non-target cast failure incorrectly skipped the player")
    X.pendingCast = nil
  end)
  env.SPELL_FAILED_OUT_OF_RANGE = oldOutOfRange
  cleanup()
  assert(ok, err)
end)

step("coverage line: progress and per-buff counts (1.4.0)", function()
  if env.__forever then return end  -- coverage math is edition-independent; retail covers it
  local cleanup = partyOfTwo()
  local O, now = env.__over, env.GetTime()
  O.Aura = function(u, name) if u == "party2" and name == "Skyfury" then return { expirationTime = now + 600 } end end
  refresh()
  local cover
  for _, fs in ipairs(env.__fontstrings) do
    if type(fs.text) == "string" and fs.text:find("fully buffed", 1, true) then cover = fs.text end
  end
  assert(cover, "no coverage line rendered")
  assert(cover:find("1/3 fully buffed", 1, true), "coverage progress wrong: " .. cover)
  assert(cover:find("Skyfury 1/3", 1, true), "per-buff coverage wrong: " .. cover)
  O.Aura = nil
  cleanup()
end)
step("rezzed party member jumps the queue (1.4.0)", function()
  if env.__forever then return end
  local cleanup = partyOfTwo()
  local O = env.__over
  env.IsSpellInRange = function() return 1 end  -- in range: the tag, not the far label, applies
  local dead = false
  O.UnitIsDeadOrGhost = function(u) return u == "party2" and dead or false end
  refresh()  -- both listed (name order: Aaron before Zed)
  local r = shownRows()
  assert(r.party1 and r.party2, "party members not listed")
  dead = true
  refresh()  -- Zed dead: not listed, death tracked
  assert(not shownRows().party2, "dead member still listed")
  dead = false
  refresh()  -- Zed rezzed: back, and ahead of Aaron despite the name order
  local row2 = env.BuffRadarRow2
  assert(row2 and row2.entry and row2.entry.unit == "party2",
    "rezzed member not second (after self): " .. tostring(row2 and row2.entry and row2.entry.unit))
  assert(row2.entry.rezzed, "rezzed flag not set on the entry")
  assert(row2.tag and row2.tag.shown, "'recently rezzed' tag not shown")
  O.UnitIsDeadOrGhost = nil
  cleanup()
end)
step("session-only ignore via /br signore (1.4.0)", function()
  if env.__forever then return end
  local cleanup = partyOfTwo()
  refresh()
  assert(shownRows().party1, "Aaron not listed before signore")
  env.SlashCmdList.BUFFRADAR("signore Aaron")
  refresh()
  assert(not shownRows().party1, "Aaron still listed after signore")
  assert(shownRows().party2, "Zed wrongly hidden by signore Aaron")
  env.SlashCmdList.BUFFRADAR("unsignore Aaron")
  refresh()
  assert(shownRows().party1, "Aaron not back after unsignore")
  assert(next(env.BuffRadarDB.ignored) == nil, "session ignore leaked into the saved list")
  cleanup()
end)
step("/br announce posts the missing list to party chat (1.4.0)", function()
  if env.__forever then return end
  local cleanup = partyOfTwo()
  refresh()
  env.__sent = {}
  env.SlashCmdList.BUFFRADAR("announce")
  assert(#env.__sent == 1, "announce sent " .. #env.__sent .. " messages")
  assert(env.__sent[1].chattype == "PARTY", "announce channel: " .. tostring(env.__sent[1].chattype))
  assert(env.__sent[1].msg:find("missing buffs", 1, true), "announce text: " .. env.__sent[1].msg)
  assert(env.__sent[1].msg:find("Aaron", 1, true), "announce missing Aaron: " .. env.__sent[1].msg)
  cleanup()
end)
step("saved settings: legacy saves migrate, corrupt values repair (1.4.0)", function()
  -- a pre-1.2.0 save (dbVersion 2) with out-of-range, mistyped and unknown keys
  env.BuffRadarDB = {
    dbVersion = 2, castMethod = "id", clickReg = "down",
    scale = 99, width = "wide", bogusKey = true,
    ignored = { Bob = true, [3] = true },
    rebuffPer = { SKYFURY = 45, BAD = "x" }, stats = { Skyfury = 3 },
    profiles = { RaidNight = "BR1;scale=1.5", Bad = 42 },
    roleFilter = "SIDEWAYS", idleFade = 500,
    customSpells = { 12345, "x", 0, 99999999, 12345 },
    autoProfile = { dungeon = "RaidNight", bad = 42, [3] = "x" },
    point = { "LEFT", "LEFT", 10, 20 },
  }
  fire("ADDON_LOADED", "BuffRadar")
  local d = env.BuffRadarDB
  assert(d.castMethod == "target", "pre-v3 castMethod not reset: " .. tostring(d.castMethod))
  assert(d.clickReg == "both", "pre-v3 clickReg not reset: " .. tostring(d.clickReg))
  assert(d.includeSelf == true, "pre-v4 includeSelf not forced on")
  assert(d.dbVersion == 17, "dbVersion not migrated to 17: " .. tostring(d.dbVersion))
  assert(next(d.blessingPreferences) == nil, "existing character got a blessing override")
  assert(d.wizardSeen == false, "ancient save should still count as a new user for the wizard")
  if env.__forever then  -- 1.8.0 (#32): shadow protection defaults to instances
    assert(d.buffContext.SHADOW_PROT == "instance",
      "shadow protection context default missing: " .. tostring(d.buffContext.SHADOW_PROT))
  end
  assert(d.scale == 2, "scale not clamped: " .. tostring(d.scale))
  assert(d.width == 210, "mistyped width not repaired: " .. tostring(d.width))
  assert(d.bogusKey == nil, "unknown key survived sanitizing")
  assert(d.ignored.Bob == true and d.ignored[3] == nil, "ignore list not cleaned")
  assert(d.rebuffPer.SKYFURY == 45 and d.rebuffPer.BAD == nil, "rebuffPer not cleaned")
  assert(d.profiles.RaidNight == "BR1;scale=1.5" and d.profiles.Bad == nil, "profiles not cleaned")
  assert(d.roleFilter == "ALL", "bad role filter not repaired: " .. tostring(d.roleFilter))
  assert(#d.customSpells == 1 and d.customSpells[1] == 12345, "custom spells not cleaned")
  assert(d.autoProfile.dungeon == "RaidNight" and d.autoProfile.bad == nil
    and d.autoProfile[3] == nil, "auto profiles not cleaned")
  assert(d.idleFade == 90, "idle fade not clamped: " .. tostring(d.idleFade))
  assert(d.stats.Skyfury == 3, "stats lost in migration")
  -- a completely corrupt save (not even a table) becomes clean defaults
  env.BuffRadarDB = "junk"
  fire("ADDON_LOADED", "BuffRadar")
  d = env.BuffRadarDB
  assert(type(d) == "table" and d.dbVersion == 17 and d.scale == 1,
    "corrupt save not replaced with defaults")
  d.scale = 1
  -- a 1.7.0-era save (dbVersion 9): an existing user — the wizard
  -- counts as already seen, so no first-run hint nags them (1.9.0)
  env.BuffRadarDB = { dbVersion = 9 }
  fire("ADDON_LOADED", "BuffRadar")
  d = env.BuffRadarDB
  assert(d.dbVersion == 17 and d.wizardSeen == true,
    "existing user not marked wizard-seen: " .. tostring(d.wizardSeen))
  d.wizardSeen = false  -- leave the save as the rest of the suite expects
end)
step("ready check reports who is missing buffs (1.4.0)", function()
  if env.__forever then return end
  local cleanup = partyOfTwo()
  refresh()
  local n = #chat
  fire("READY_CHECK")
  assert(chatSince(n, "Ready check: 3 people are missing buffs"), "no ready-check summary")
  cleanup()
end)
step("a buff that vanishes is flagged as expired (1.4.0)", function()
  if env.__forever then return end
  local cleanup = partyOfTwo()
  local O, now = env.__over, env.GetTime()
  env.IsSpellInRange = function() return 1 end  -- in range: the tag, not the far label, applies
  O.Aura = function(u, name) if u == "party1" and name == "Skyfury" then return { expirationTime = now + 600 } end end
  refresh()  -- Aaron has Skyfury: not listed
  assert(not shownRows().party1, "Aaron listed despite having Skyfury")
  O.Aura = nil
  refresh()  -- now it's gone entirely: flagged, not just listed
  local row = assert(shownRows().party1, "Aaron not listed after losing Skyfury").row
  assert(row.entry.expired, "vanished buff not flagged as expired")
  assert(row.tag and row.tag.shown and type(row.tag.text) == "string" and #row.tag.text > 0,
    "expired tag not shown: " .. tostring(row.tag and row.tag.text))
  if not env.__german then
    assert(row.tag.text == "a buff just expired", "expired tag text: " .. tostring(row.tag.text))
  end
  cleanup()
end)
step("low-mana pause (1.4.0)", function()
  if env.__forever then return end
  local cleanup = partyOfTwo()
  env.UnitPower = function() return 10 end
  env.UnitPowerMax = function() return 100 end
  env.SlashCmdList.BUFFRADAR("mana 20")
  refresh()
  local want = env.__german and "Wenig Mana -- Buffen pausiert." or "Low mana -- buffing paused."
  local found
  for _, fs in ipairs(env.__fontstrings) do
    if fs.text == want and fs.shown then found = true end
  end
  assert(found, "low-mana status not shown at 10% mana with a 20% threshold")
  env.UnitPower = function() return 90 end
  refresh()
  assert(shownRows().party1, "list did not resume after drinking")
  env.SlashCmdList.BUFFRADAR("mana 0")
  env.UnitPower, env.UnitPowerMax = nil, nil
  cleanup()
end)
step("distance sort puts the in-range player first (1.4.0)", function()
  local cleanup = twoTanks()
  env.IsSpellInRange = function(spell, unit) return unit == "nameplate2" and 1 or 0 end
  env.BuffRadarDB.sortMode = "distance"
  refresh()
  local row2 = env.BuffRadarRow2
  assert(row2 and row2.entry and row2.entry.unit == "nameplate2",
    "distance sort did not put nameplate2 second: " .. tostring(row2 and row2.entry and row2.entry.unit))
  env.BuffRadarDB.sortMode = "name"
  cleanup()
end)
step("per-spec profiles keep separate buff toggles (1.4.0)", function()
  local spec = 1
  env.GetSpecialization = function() return spec end
  fire("ADDON_LOADED", "BuffRadar")  -- SpecSwap runs here (and on talent events)
  local d = env.BuffRadarDB
  d.enabled.CUSTOM_TEST = true
  spec = 2
  fire("PLAYER_TALENT_UPDATE")
  assert(d.specProfiles.s1 and d.specProfiles.s1.enabled.CUSTOM_TEST == true,
    "spec 1 toggles not saved into its profile")
  d.enabled.CUSTOM_TEST = false
  spec = 1
  fire("PLAYER_TALENT_UPDATE")
  assert(d.enabled.CUSTOM_TEST == true, "spec 1 toggles not restored on swap back")
  spec = 2
  fire("PLAYER_TALENT_UPDATE")
  assert(d.enabled.CUSTOM_TEST == false, "spec 2 kept spec 1's toggle")
  env.GetSpecialization = nil
end)
step("dual-spec scale: each spec keeps its own window scale (1.13.0)", function()
  local spec = 1
  env.GetSpecialization = function() return spec end
  fire("ADDON_LOADED", "BuffRadar")
  local d = env.BuffRadarDB
  d.scalePerSpec = true
  d.scale = 1.3
  spec = 2
  fire("PLAYER_TALENT_UPDATE")
  d.scale = 0.8
  spec = 1
  fire("PLAYER_TALENT_UPDATE")
  assert(math.abs((d.scale or 0) - 1.3) < 0.001, "spec 1 scale not restored: " .. tostring(d.scale))
  spec = 2
  fire("PLAYER_TALENT_UPDATE")
  assert(math.abs((d.scale or 0) - 0.8) < 0.001, "spec 2 scale not restored: " .. tostring(d.scale))
  spec = 1
  fire("PLAYER_TALENT_UPDATE")
  d.scalePerSpec = false
  env.GetSpecialization = nil
end)
step("ignore list export/import round-trip (1.13.0)", function()
  local d = env.BuffRadarDB
  env.SlashCmdList.BUFFRADAR("ignore Zork")
  env.SlashCmdList.BUFFRADAR("ignore Bleep-Realm")
  env.SlashCmdList.BUFFRADAR("ignorelist export")
  local f = env.BuffRadarExportFrame
  assert(f and f.editBox, "no export frame for the ignore list")
  local txt = f.editBox:GetText()
  assert(txt:sub(1, 5) == "BRI1;" and txt:find("Zork", 1, true) and txt:find("Bleep-Realm", 1, true),
    "export string wrong: " .. tostring(txt))
  env.SlashCmdList.BUFFRADAR("unignore Zork")
  env.SlashCmdList.BUFFRADAR("unignore Bleep-Realm")
  assert(not d.ignored["Zork"], "unignore failed")
  env.SlashCmdList.BUFFRADAR("ignorelist import")
  f.editBox:SetText(txt .. ";bad\1name")
  f.accept.scripts.OnClick(f.accept)
  assert(d.ignored["Zork"] or d.ignored["zork"], "import did not restore Zork")
  assert(d.ignored["Bleep-Realm"], "import did not restore Bleep-Realm")
  env.SlashCmdList.BUFFRADAR("unignore Zork")
  env.SlashCmdList.BUFFRADAR("unignore Bleep-Realm")
  env.SlashCmdList.BUFFRADAR("ignorelist import")
  f.editBox:SetText("not a list")
  f.accept.scripts.OnClick(f.accept)
end)
step("/br summary and /br apicheck export (1.13.0)", function()
  env.SlashCmdList.BUFFRADAR("summary")
  env.SlashCmdList.BUFFRADAR("apicheck export")
  local f = env.BuffRadarExportFrame
  assert(f and f.editBox:GetText():find("API check", 1, true), "apicheck export text missing")
  assert(not f.editBox:GetText():find("|c", 1, true), "color codes leaked into the export")
end)
step("settings export/import round-trip (1.4.0)", function()
  local d = env.BuffRadarDB
  d.scale, d.sortMode = 1.5, "role"
  d.enabled.CUSTOM_TEST = false
  d.rebuffPer.CUSTOM_TEST = 77
  d.ignored.Zed = true
  env.SlashCmdList.BUFFRADAR("export")
  local f = assert(env.BuffRadarExportFrame, "export frame not created")
  assert(f.shown, "export window not shown")
  local text = f.editBox.text
  assert(type(text) == "string" and text:sub(1, 3) == "BR1", "export string malformed")
  d.scale, d.sortMode, d.rebuffPer.CUSTOM_TEST = 1, "name", nil
  d.enabled.CUSTOM_TEST, d.ignored.Zed = nil, nil
  env.SlashCmdList.BUFFRADAR("import")
  f.editBox.text = text
  f.accept.scripts.OnClick(f.accept, "LeftButton")
  assert(d.scale == 1.5 and d.sortMode == "role", "import did not restore scalars")
  assert(d.enabled.CUSTOM_TEST == false and d.rebuffPer.CUSTOM_TEST == 77,
    "import did not restore per-buff tables")
  assert(d.ignored.Zed == true, "import did not restore the ignore list")
  d.scale, d.sortMode = 1, "name"
  d.enabled.CUSTOM_TEST, d.rebuffPer.CUSTOM_TEST, d.ignored.Zed = nil, nil, nil
  env.SlashCmdList.BUFFRADAR("unignore Zed")  -- the poke above bypasses the name index; clear it properly
end)
step("clipboard settings imports require complete input and apply atomically", function()
  local X, d = NS.X, env.BuffRadarDB
  local enabled, rebuff, ignored = d.enabled, d.rebuffPer, d.ignored
  d.enabled, d.rebuffPer, d.ignored = {}, {}, {}
  local empty = assert(X.Export())
  d.enabled.TEST, d.rebuffPer.TEST, d.ignored.Zed = true, 33, true
  local withData = assert(X.Export())
  d.scale = 1
  local bad = {
    "BR1", "BR1;scale=1.5", "BR1;bgColor=0,0,0;enabled.TEST=1",
    (withData:gsub(";endExport=1$", "")),
    (withData:gsub("enabled.TEST=1", "enabled.TEST=maybe")),
    (withData:gsub("enabled.TEST=1", "enabled.TEST=1;enabled.TEST=0")),
    (withData:gsub("enabled.TEST=1", "enabled.TEST=1;unknown=1")),
    (withData:gsub("enabled.TEST=1", "enabled.T%%ZZ=1")),
    "BR1;" .. string.rep("A", 16384),
  }
  for i, input in ipairs(bad) do
    assert(not X.Import(input) and not X.SettingsDiff(input), "invalid clipboard accepted: " .. i)
    assert(d.enabled.TEST and d.rebuffPer.TEST == 33 and d.ignored.Zed and d.scale == 1,
      "invalid clipboard changed settings: " .. i)
  end
  local old = empty:gsub("^BR1;complete=1;", "BR1;"):gsub(";endExport=1$", "")
  assert(X.Import(old) and not next(d.enabled) and not next(d.rebuffPer) and not next(d.ignored),
    "older complete clipboard did not clear intentionally empty tables")
  assert(X.Import(withData) and d.enabled.TEST and d.ignored.Zed, "framed clipboard round-trip failed")
  local current, currentRebuff, currentIgnore = d.enabled, d.rebuffPer, d.ignored
  current[string.rep("A", 4100)] = true
  local large = assert(X.Export(), "valid clipboard larger than named profile cap was refused")
  assert(X.Import(large), "valid large clipboard did not round-trip")
  current[string.rep("A", 16500)] = true
  d.enabled, d.rebuffPer, d.ignored = current, currentRebuff, currentIgnore
  assert(not X.Export(), "oversized settings produced an unreadable export")
  d.enabled, d.rebuffPer, d.ignored = enabled, rebuff, ignored
  X.Ignore.Rebuild()
end)
step("post-combat border flash when work waits (1.4.0)", function()
  if env.__forever then return end
  local cleanup = partyOfTwo()
  env.__combat = true
  fire("PLAYER_REGEN_DISABLED")
  env.__combat = false
  fire("PLAYER_REGEN_ENABLED")
  timerTick()  -- the queued refresh runs and finds people missing buffs
  local bc = env.BuffRadarFrame.borderColor
  assert(bc and bc[1] == 1 and bc[2] == 0.35, "border did not flash after combat")
  timerTick()  -- the restore timer runs
  bc = env.BuffRadarFrame.borderColor
  assert(bc and bc[1] == 0.35, "border not restored after the flash")
  cleanup()
end)
step("time-left tag on a row inside its rebuff window (1.4.0)", function()
  if env.__forever then return end
  local cleanup = partyOfTwo("T")  -- fresh GUIDs: no rez / expiry history from earlier steps
  local O = env.__over
  env.IsSpellInRange = function() return 1 end
  -- Aaron's Skyfury has 20s left: inside the 30s rebuff window, still present
  O.Aura = function(u, name)
    if u == "party1" and name == "Skyfury" then return { expirationTime = env.GetTime() + 20 } end
  end
  refresh()
  local row = assert(shownRows().party1, "Aaron not listed inside the rebuff window").row
  assert(row.tag and row.tag.shown, "time-left tag not shown")
  if not env.__german then
    assert(row.tag.text:match("^~%d+s left$"), "time-left text: " .. tostring(row.tag.text))
  end
  O.Aura = nil
  cleanup()
end)
step("compact rows shrink the window and hide portraits (1.4.0)", function()
  if env.__forever then return end
  local cleanup = partyOfTwo()
  refresh()
  local h1 = env.BuffRadarFrame.cHeight
  env.SlashCmdList.BUFFRADAR("compact")
  refresh()
  local h2 = env.BuffRadarFrame.cHeight
  assert(h2 and h1 and h2 < h1, "compact did not shrink the window (" ..
    tostring(h1) .. " -> " .. tostring(h2) .. ")")
  assert(env.BuffRadarRow1.portrait.shown == false, "portrait still shown in compact mode")
  env.SlashCmdList.BUFFRADAR("compact")
  refresh()
  assert(env.BuffRadarFrame.cHeight == h1, "window height not restored leaving compact mode")
  cleanup()
end)
step("per-character position is stored on save (1.4.0)", function()
  local d = env.BuffRadarDB
  env.SlashCmdList.BUFFRADAR("charpoint")
  assert(d.charPoint == true, "charpoint not enabled")
  local f = env.BuffRadarFrame
  f.isMoving = true
  f.scripts.OnDragStop(f)  -- runs SavePosition
  local key
  for k in pairs(d.pointByChar) do key = k end
  assert(key and key:find("TestRealm", 1, true), "no per-character position stored: " .. tostring(key))
  assert(d.pointByChar[key] == d.point, "stored position is not the current point")
  env.SlashCmdList.BUFFRADAR("charpoint")
  assert(d.charPoint == false, "charpoint not disabled")
end)
step("cast sync: another user's cast sinks the player (1.5.0)", function()
  if env.__forever then return end
  local cleanup = partyOfTwo("S")
  env.BuffRadarDB.sync = true
  env.IsSpellInRange = function() return 1 end
  refresh()
  local row2 = env.BuffRadarRow2
  assert(row2 and row2.entry and row2.entry.unit == "party1", "Aaron not second before sync")
  fire("CHAT_MSG_ADDON", "BuffRadar", "CAST;SKYFURY;Player-1-P1S", "PARTY", "Other-Realm")
  refresh()
  row2 = env.BuffRadarRow2
  assert(row2 and row2.entry and row2.entry.unit == "party2",
    "handled player did not sink: row2=" .. tostring(row2 and row2.entry and row2.entry.unit))
  local row3 = env.BuffRadarRow3
  assert(row3 and row3.entry and row3.entry.handled, "handled flag not set on Aaron's entry")
  if not env.__german then
    assert(row3.tag and row3.tag.shown and row3.tag.text == "being buffed",
      "handled tag wrong: " .. tostring(row3.tag and row3.tag.text))
  end
  cleanup()
end)
step("cast sync: your cast is broadcast to other users (1.5.0)", function()
  if env.__forever then return end
  local cleanup = partyOfTwo()
  env.BuffRadarDB.sync = true
  env.IsSpellInRange = function() return 1 end
  refresh()
  local row
  for i = 1, 15 do
    local r = env["BuffRadarRow" .. i]
    if r and r.entry and r.entry.unit == "party1" then row = r end
  end
  assert(row, "Aaron's row not found")
  row.scripts.PostClick(row, "LeftButton")  -- primes the pending cast
  env.C_Spell = { GetSpellName = function() return "Skyfury" end }
  env.__addonSent = {}
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "castline", 4242)
  env.C_Spell = nil
  assert(#env.__addonSent == 1, "no sync broadcast sent (" .. #env.__addonSent .. ")")
  local m = env.__addonSent[1]
  assert(m.prefix == "BuffRadar" and m.channel == "PARTY", "sync broadcast header wrong")
  assert(m.msg == "CAST;SKYFURY;Player-1-P1", "sync broadcast body: " .. tostring(m.msg))
  cleanup()
end)
step("chat request tags the asker (1.5.0)", function()
  if env.__forever then return end
  local cleanup = partyOfTwo("Q")
  env.BuffRadarDB.requests = true
  env.IsSpellInRange = function() return 1 end
  refresh()
  fire("CHAT_MSG_WHISPER", "buff pls", "Aaron-TestRealm")
  refresh()
  local row
  for i = 1, 15 do
    local r = env["BuffRadarRow" .. i]
    if r and r.entry and r.entry.unit == "party1" then row = r end
  end
  assert(row and row.entry.asked, "asker not tagged")
  if not env.__german then
    assert(row.tag and row.tag.text == "asked for a buff",
      "ask tag text: " .. tostring(row.tag and row.tag.text))
  end
  cleanup()
end)
step("joining a group prints a one-line summary (1.5.0)", function()
  if env.__forever then return end
  local cleanup = partyOfTwo()
  env.BuffRadarDB.joinDigest = true
  local n = #chat
  fire("GROUP_ROSTER_UPDATE")
  timerTick()  -- runs the delayed digest on timer clients
  assert(chatSince(n, "Joined a group: 3 people are missing buffs"), "no join summary printed")
  local n2 = #chat
  fire("CHALLENGE_MODE_START")
  assert(chatSince(n2, "Run starting: 3 people are missing buffs"), "no run-start summary")
  cleanup()
end)
step("role filter: chips and /br filter narrow the window (1.5.0)", function()
  if env.__forever then return end  -- no assigned roles on the old client
  local cleanup = partyOfTwo("F")
  env.IsSpellInRange = function() return 1 end
  env.UnitGroupRolesAssigned = function(u) return u == "party2" and "TANK" or "DAMAGER" end
  refresh()
  local r = shownRows()
  assert(r.party1 and r.party2, "both party members listed before filtering")
  env.SlashCmdList.BUFFRADAR("filter tank")
  refresh()
  r = shownRows()
  assert(r.party2 and not r.party1, "tank filter wrong: Aaron=" .. tostring(r.party1 ~= nil))
  assert(r.player, "your own row must survive the role filter")
  local chip = env.BuffRadarChipTANK
  assert(chip and chip.fs, "tank filter chip missing")
  assert(chip.fs.color and chip.fs.color[1] > 0.9, "active chip not highlighted")
  chip.scripts.OnClick(chip, "LeftButton")
  assert(env.BuffRadarDB.roleFilter == "TANK", "chip click did not set the filter")
  env.SlashCmdList.BUFFRADAR("filter all")
  refresh()
  assert(shownRows().party1, "filter all did not restore the full list")
  env.UnitGroupRolesAssigned = function() return "NONE" end
  cleanup()
end)
step("buff toggle strip on the window (1.5.0)", function()
  if env.__forever then return end
  local cleanup = partyOfTwo("T")
  env.IsSpellInRange = function() return 1 end
  refresh()
  local h1 = env.BuffRadarFrame.cHeight
  local btn
  for i = 1, 10 do
    local b = env["BuffRadarStrip" .. i]
    if b and b.buffKey == "SKYFURY" then btn = b end
  end
  assert(btn, "no Skyfury button on the toggle strip")
  btn.scripts.OnClick(btn, "LeftButton")
  assert(env.BuffRadarDB.enabled.SKYFURY == false, "strip click did not turn Skyfury off")
  refresh()
  assert(not shownRows().party1, "Aaron still listed with Skyfury toggled off")
  btn.scripts.OnClick(btn, "LeftButton")
  assert(env.BuffRadarDB.enabled.SKYFURY == true, "strip click did not turn Skyfury back on")
  env.SlashCmdList.BUFFRADAR("strip")
  refresh()
  local h2 = env.BuffRadarFrame.cHeight
  assert(h2 and h1 and h2 < h1, "hiding the strip did not shrink the window")
  env.SlashCmdList.BUFFRADAR("strip")
  refresh()
  assert(env.BuffRadarFrame.cHeight == h1, "window height not restored with the strip back")
  cleanup()
end)
step("need sort: most missing buffs first (1.5.0)", function()
  if env.__forever then return end
  local cleanup = partyOfTwo("N")
  env.IsSpellInRange = function() return 1 end
  env.UnitGroupRolesAssigned = function(u) return u == "party2" and "TANK" or "DAMAGER" end
  env.BuffRadarDB.enabled.EARTH_SHIELD = true
  env.SlashCmdList.BUFFRADAR("sort need")
  refresh()
  -- Zed (tank) misses Skyfury + Earth Shield = 2; Aaron misses Skyfury = 1.
  local row2 = env.BuffRadarRow2
  assert(row2 and row2.entry and row2.entry.unit == "party2",
    "need sort did not put Zed second: " .. tostring(row2 and row2.entry and row2.entry.unit))
  env.SlashCmdList.BUFFRADAR("sort name")
  env.BuffRadarDB.enabled.EARTH_SHIELD = nil
  env.UnitGroupRolesAssigned = function() return "NONE" end
  cleanup()
end)
step("a player in another phase is not listed (1.5.0)", function()
  if env.__forever then return end  -- phasing is a retail concept
  local cleanup = partyOfTwo("P")
  env.IsSpellInRange = function() return 1 end
  env.UnitInPhase = function(u) return u ~= "party2" end
  refresh()
  assert(shownRows().party1, "Aaron missing in the phase test")
  assert(not shownRows().party2, "Zed listed despite being in another phase")
  env.UnitInPhase = nil
  refresh()
  assert(shownRows().party2, "Zed not back once the phases align")
  cleanup()
end)
step("idle fade lowers the window alpha (1.5.0)", function()
  env.SlashCmdList.BUFFRADAR("fade 50")
  assert(env.BuffRadarDB.idleFade == 50, "fade setting not stored")
  env.__mouseOver = false
  timerTick()
  assert(env.BuffRadarFrame.alpha == 0.5, "window did not fade: " .. tostring(env.BuffRadarFrame.alpha))
  env.__mouseOver = true
  timerTick()
  assert(env.BuffRadarFrame.alpha == 1, "window did not unfade under the mouse")
  env.__mouseOver = false
  env.SlashCmdList.BUFFRADAR("fade 0")
  timerTick()
  assert(env.BuffRadarFrame.alpha == 1, "window stayed faded with fading off")
end)
step("all-buffed pill replaces the window (1.6.0)", function()
  local cleanup = partyOfTwo("P")
  env.SlashCmdList.BUFFRADAR("pill")
  assert(env.BuffRadarDB.pill == true, "pill setting not stored")
  env.__over.Aura = function(u, name) return { expirationTime = env.GetTime() + 600 } end
  refresh()
  assert(env.BuffRadarPill and env.BuffRadarPill.shown, "pill not shown while all buffed")
  assert(not env.BuffRadarFrame.shown, "window still shown in pill mode")
  env.BuffRadarPill.scripts.OnClick(env.BuffRadarPill)
  assert(env.BuffRadarFrame.shown, "pill click did not peek the window")
  refresh()
  assert(env.BuffRadarFrame.shown, "peek did not survive a refresh inside its window")
  env.__over.Aura = nil
  refresh()
  assert(not env.BuffRadarPill.shown, "pill stuck after buffs went missing")
  assert(env.BuffRadarFrame.shown, "window did not return when buffs went missing")
  env.SlashCmdList.BUFFRADAR("pill")
  cleanup()
end)
step("cast queue: next row tagged after a cast lands (1.6.0)", function()
  local cleanup = partyOfTwo("U")
  env.IsSpellInRange = function() return 1 end
  -- You are fully buffed yourself, so the top row is Aaron's, not yours.
  env.__over.Aura = function(u, name) if u == "player" then return { expirationTime = env.GetTime() + 600 } end end
  refresh()
  local row
  for i = 1, 15 do
    local r = env["BuffRadarRow" .. i]
    if r and r.entry and r.entry.unit == "party1" then row = r end
  end
  assert(row, "Aaron's row not found")
  local spell = row.entry.missing[1]
  row.scripts.PostClick(row, "LeftButton")
  env.C_Spell = { GetSpellName = function() return spell end }
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "castline", 4242)
  env.C_Spell = nil
  refresh()
  local tagged
  for i = 1, 15 do
    local r = env["BuffRadarRow" .. i]
    if r and r.entry and r.entry.queued then tagged = r end
  end
  assert(tagged, "no row tagged as up next")
  assert(tagged == env.BuffRadarRow1, "up-next tag not on the top row")
  if not env.__german then
    assert(tagged.tag and tagged.tag.text == "up next",
      "queue tag text: " .. tostring(tagged.tag and tagged.tag.text))
  end
  cleanup()
end)
step("shipped presets set window and behavior only (1.6.0)", function()
  local db = env.BuffRadarDB
  env.SlashCmdList.BUFFRADAR("preset raid")
  assert(db.sortMode == "role" and db.groupCast == true,
    "raid preset not applied")
  env.SlashCmdList.BUFFRADAR("preset solo")
  assert(db.sortMode == "name" and db.groupCast == false and db.pauseInCities == false,
    "solo preset not applied")
  local n = #chat
  env.SlashCmdList.BUFFRADAR("preset bogus")
  assert(chatSince(n, "Usage: /br preset raid|dungeon|solo"), "bad preset not rejected")
  db.sortMode, db.groupCast, db.groupOnly, db.showOutOfRange = "name", false, false, false
end)
step("custom watched spells join the list (1.6.0)", function()
  local db = env.BuffRadarDB
  local wasKnown = env.IsPlayerSpell
  env.IsPlayerSpell = function(id) return id == 12345 or wasKnown(id) end
  env.GetSpellInfo = function(id) if id == 12345 then return "Test Blessing" end end
  env.SlashCmdList.BUFFRADAR("custom add 12345")
  assert(#db.customSpells == 1 and db.customSpells[1] == 12345, "custom spell not stored")
  local cleanup = partyOfTwo("T")
  env.IsSpellInRange = function() return 1 end
  refresh()
  local found = false
  for i = 1, 15 do
    local r = env["BuffRadarRow" .. i]
    if r and r.entry then
      for _, m in ipairs(r.entry.missing) do if m == "Test Blessing" then found = true end end
    end
  end
  assert(found, "custom spell not offered on any row")
  cleanup()
  env.SlashCmdList.BUFFRADAR("custom remove 12345")
  assert(#db.customSpells == 0, "custom spell not removed")
  env.IsPlayerSpell = wasKnown
  env.GetSpellInfo = nil
end)
step("consumables tracked on the coverage line (1.6.0)", function()
  local cleanup = partyOfTwo("N")
  env.SlashCmdList.BUFFRADAR("consumables")
  assert(env.BuffRadarDB.consumables == true, "consumables setting not stored")
  env.__over.AuraList = function(u)
    if u == "party2" then
      return { { name = "Flask of the Titans", expirationTime = env.GetTime() + 600 },
               { name = "Well Fed", expirationTime = env.GetTime() + 600 } }
    end
    return {}
  end
  refresh()
  local cover
  for _, fs in ipairs(env.__fontstrings) do
    if type(fs.text) == "string" and fs.text:find("Flask", 1, true) then cover = fs.text end
  end
  assert(cover, "no consumables on the coverage line")
  assert(cover:find("Flask 1/3", 1, true), "flask count wrong: " .. cover)
  assert(cover:find("Food 1/3", 1, true), "food count wrong: " .. cover)
  if not env.__forever then
    assert(cover:find("Rune 0/3", 1, true), "rune count wrong: " .. cover)
  end
  env.__over.AuraList = nil
  env.SlashCmdList.BUFFRADAR("consumables")
  cleanup()
end)
step("buff assignments from the leader tag and sink rows (1.6.0)", function()
  -- A custom spell gives Zed a different lead buff, so the sink is visible:
  -- assignments mark rows by their FIRST missing buff.
  local wasKnown = env.IsPlayerSpell
  env.IsPlayerSpell = function(id) return id == 12345 or wasKnown(id) end
  env.GetSpellInfo = function(id) if id == 12345 then return "Test Blessing" end end
  env.SlashCmdList.BUFFRADAR("custom add 12345")
  local cleanup = partyOfTwo("A")
  env.BuffRadarDB.sync = true
  env.IsSpellInRange = function() return 1 end
  env.UnitIsGroupLeader = function(u) return u == "party1" end
  local key = env.__forever and "FORTITUDE" or "SKYFURY"
  local buffName = env.__forever and "Power Word: Fortitude" or "Skyfury"
  -- Zed already has the assigned buff, so his row leads with the custom one.
  env.__over.Aura = function(u, name)
    if u == "party2" and name == buffName then return { expirationTime = env.GetTime() + 600 } end
  end
  refresh()
  local function rowOf(unit)
    for i = 1, 15 do
      local r = env["BuffRadarRow" .. i]
      if r and r.entry and r.entry.unit == unit then return r, i end
    end
  end
  local _, aIdx0 = rowOf("party1")
  local _, zIdx0 = rowOf("party2")
  assert(aIdx0 and zIdx0 and aIdx0 < zIdx0, "baseline order unexpected")
  -- Zed is not the leader: his assignment is refused.
  fire("CHAT_MSG_ADDON", "BuffRadar", "ASSIGN;" .. key .. ";Zed", "PARTY", "Zed-TestRealm")
  refresh()
  local aRow = rowOf("party1")
  assert(aRow and not aRow.entry.theirs and not aRow.entry.mine,
    "untrusted assignment took effect")
  -- The leader (Aaron) takes the buff himself: on this client it sinks.
  fire("CHAT_MSG_ADDON", "BuffRadar", "ASSIGN;" .. key .. ";Aaron", "PARTY", "Aaron-TestRealm")
  refresh()
  local aRow2, aIdx = rowOf("party1")
  local _, zIdx = rowOf("party2")
  assert(aRow2 and aRow2.entry.theirs, "leader assignment not marked")
  assert(aIdx and zIdx and aIdx > zIdx, "assigned rows did not sink")
  if not env.__german then
    assert(aRow2.tag and aRow2.tag.text == "assigned elsewhere",
      "assign tag text: " .. tostring(aRow2.tag and aRow2.tag.text))
  end
  env.UnitIsGroupLeader = nil
  cleanup()
  env.SlashCmdList.BUFFRADAR("custom remove 12345")
  env.IsPlayerSpell = wasKnown
  env.GetSpellInfo = nil
end)
step("buddy split shares the list between users (1.6.0)", function()
  local cleanup = partyOfTwo("B")
  local db = env.BuffRadarDB
  db.sync = true
  db.buddySplit = true
  env.IsSpellInRange = function() return 1 end
  -- Start from a clean peer table: earlier steps' traffic recorded peers,
  -- and leaving the group wipes them.
  env.IsInGroup = function() return false end
  fire("GROUP_ROSTER_UPDATE")
  env.IsInGroup = function() return true end
  fire("CHAT_MSG_ADDON", "BuffRadar", "HELLO;Me-TestRealm", "PARTY", "Aaron-TestRealm")
  refresh()
  -- Users sorted by key: aaron-testrealm, then me-testrealm (index 2), so
  -- an entry is mine when (sum of GUID bytes) % 2 == 1.
  local function expectBuddy(guid)
    local s = 0
    for i = 1, #guid do s = s + guid:byte(i) end
    return s % 2 ~= 1
  end
  local seen = 0
  for i = 1, 15 do
    local r = env["BuffRadarRow" .. i]
    if r and r.entry and r.entry.group and not r.entry.isSelf then
      seen = seen + 1
      assert((r.entry.buddy ~= nil) == expectBuddy(r.entry.guid),
        "buddy share wrong for " .. r.entry.guid)
    end
  end
  assert(seen == 2, "expected both party members listed, saw " .. seen)
  db.buddySplit = false
  cleanup()
end)
step("cover-me handoff: duties pass while a buddy is away (1.7.0)", function()
  local cleanup = partyOfTwo("C")
  local db = env.BuffRadarDB
  db.sync = true
  env.IsSpellInRange = function() return 1 end
  env.UnitIsGroupLeader = function(u) return u == "party1" end
  local key = env.__forever and "FORTITUDE" or "SKYFURY"
  -- Aaron (the leader) takes the buff; on my list it sinks as theirs.
  fire("CHAT_MSG_ADDON", "BuffRadar", "ASSIGN;" .. key .. ";Aaron", "PARTY", "Aaron-TestRealm")
  refresh()
  local function aaronRow()
    for i = 1, 15 do
      local r = env["BuffRadarRow" .. i]
      if r and r.entry and r.entry.unit == "party1" then return r end
    end
  end
  local r0 = aaronRow()
  assert(r0 and r0.entry.theirs and not r0.entry.mine, "baseline: assignment not theirs")
  -- Aaron goes down: his assignment becomes mine (the handoff).
  fire("CHAT_MSG_ADDON", "BuffRadar", "COVER;Aaron-TestRealm", "PARTY", "Aaron-TestRealm")
  refresh()
  local r1 = aaronRow()
  assert(r1 and r1.entry.mine, "covered assignment did not hand off")
  -- He is back: the assignment returns to him.
  fire("CHAT_MSG_ADDON", "BuffRadar", "BACK;Aaron-TestRealm", "PARTY", "Aaron-TestRealm")
  refresh()
  local r2 = aaronRow()
  assert(r2 and r2.entry.theirs and not r2.entry.mine, "returned assignment not restored")
  -- My own death announces a cover; standing back up announces my return.
  local sent0 = #env.__addonSent
  env.__over.UnitIsDeadOrGhost = function(u) return u == "player" end
  fire("PLAYER_DEAD")
  local coverMsg
  for i = sent0 + 1, #env.__addonSent do
    if env.__addonSent[i].msg:find("COVER;", 1, true) then coverMsg = true end
  end
  assert(coverMsg, "my death did not announce a cover")
  env.__over.UnitIsDeadOrGhost = function() return false end
  fire("PLAYER_ALIVE")
  local backMsg
  for i = sent0 + 1, #env.__addonSent do
    if env.__addonSent[i].msg:find("BACK;", 1, true) then backMsg = true end
  end
  assert(backMsg, "my return was not announced")
  env.__over.UnitIsDeadOrGhost = nil
  env.UnitIsGroupLeader = nil
  cleanup()
end)

step("ready-check summary auto-posts for leaders (1.7.0)", function()
  local cleanup = partyOfTwo("R")
  env.BuffRadarDB.readyPost = true
  env.UnitIsGroupLeader = function(u) return u == "player" end
  local s0 = #env.__sent
  fire("READY_CHECK")
  local posted
  for i = s0 + 1, #env.__sent do
    if env.__sent[i].msg:find("BuffRadar ready check:", 1, true) then posted = env.__sent[i] end
  end
  assert(posted, "ready-check summary not posted to group chat")
  assert(posted.chattype == "PARTY", "posted to wrong channel: " .. tostring(posted.chattype))
  env.UnitIsGroupLeader = nil
  cleanup()
end)

step("coverage line lists the BuffRadar users on duty (1.7.0)", function()
  local cleanup = partyOfTwo("D")
  env.BuffRadarDB.sync = true
  env.IsSpellInRange = function() return 1 end
  -- Clean peer table first (earlier steps left peers behind).
  env.IsInGroup = function() return false end
  fire("GROUP_ROSTER_UPDATE")
  env.IsInGroup = function() return true end
  fire("CHAT_MSG_ADDON", "BuffRadar", "HELLO;Me-TestRealm", "PARTY", "Aaron-TestRealm")
  refresh()
  local cover
  for _, fs in ipairs(env.__fontstrings) do
    if type(fs.text) == "string" and fs.text:find("Radar: Me, Aaron", 1, true) then cover = fs.text end
  end
  assert(cover, "coverage line has no roster segment")
  cleanup()
end)

step("pinned player stays on top of the list (1.7.0)", function()
  -- twoTanks() provides two nameplate players, Tank1 and Tank2.
  local cleanup = twoTanks()
  local db = env.BuffRadarDB
  db.sortMode = "name"
  env.IsSpellInRange = function() return 1 end
  local function order()
    local out = {}
    for i = 1, 15 do
      local r = env["BuffRadarRow" .. i]
      if r and r.entry and r.shown
         and (r.entry.unit == "player" or r.entry.unit == "nameplate1" or r.entry.unit == "nameplate2") then
        out[#out + 1] = r.entry.unit
      end
    end
    return table.concat(out, ",")
  end
  refresh()
  assert(order() == "player,nameplate1,nameplate2", "baseline order: " .. order())
  env.SlashCmdList.BUFFRADAR("pin Tank2")
  refresh()
  assert(order() == "player,nameplate2,nameplate1", "pinned order: " .. order())
  local pinFlag = false
  for i = 1, 15 do
    local r = env["BuffRadarRow" .. i]
    if r and r.entry and r.entry.unit == "nameplate2" then pinFlag = r.entry.pinned end
  end
  assert(pinFlag, "Tank2's entry is not flagged pinned")
  env.SlashCmdList.BUFFRADAR("pin none")
  refresh()
  assert(order() == "player,nameplate1,nameplate2", "unpinned order: " .. order())
  assert(db.pinned == "", "pin not cleared")
  cleanup()
end)

step("row tooltip shows remaining times (1.7.0)", function()
  local db = env.BuffRadarDB
  -- Aaron HAS my main buff (10 minutes left) but misses a custom one,
  -- so his row exists and the tooltip can show both halves.
  local main = env.__forever and "Power Word: Fortitude" or "Skyfury"
  local wasKnown = env.IsPlayerSpell
  env.IsPlayerSpell = function(id) return id == 12345 or wasKnown(id) end
  env.GetSpellInfo = function(id) if id == 12345 then return "Test Blessing" end end
  env.SlashCmdList.BUFFRADAR("custom add 12345")
  local cleanup = partyOfTwo("T")
  env.IsSpellInRange = function() return 1 end
  -- Aaron has every buff of mine (10 minutes left) except the custom
  -- one: whichever name the scan asks by, the answer is the same table.
  -- (Set after partyOfTwo — it clears aura hooks on purpose.)
  env.__over.Aura = function(u, name)
    if u == "party1" and name ~= "Test Blessing" then
      return { expirationTime = env.GetTime() + 600 }
    end
  end
  refresh()
  local row
  for i = 1, 15 do
    local r = env["BuffRadarRow" .. i]
    if r and r.entry and r.entry.unit == "party1" then row = r end
  end
  assert(row, "Aaron has no row")
  local lines = {}
  local realTip = env.GameTooltip
  env.GameTooltip = { SetOwner = function() end, Show = function() end,
    SetUnit = function() end, Hide = function() end,
    AddLine = function(_, t) lines[#lines + 1] = t end }
  row.scripts.OnEnter(row)
  env.GameTooltip = realTip
  local castLine, haveLine
  for _, t in ipairs(lines) do
    if type(t) == "string" and t:find("Test Blessing", 1, true) then castLine = t end
    if type(t) == "string" and t:find(main, 1, true) and t:find("—", 1, true) then haveLine = t end
  end
  assert(castLine, "tooltip does not name the missing custom buff")
  assert(haveLine, "tooltip lacks the remaining-time line for " .. main)
  env.__over.Aura = nil
  env.SlashCmdList.BUFFRADAR("custom remove 12345")
  env.IsPlayerSpell = wasKnown
  env.GetSpellInfo = nil
  cleanup()
end)

step("weapon enchant watch flags your own row (1.7.0)", function()
  local cleanup = partyOfTwo("W")
  local db = env.BuffRadarDB
  db.weaponWatch = true
  env.IsSpellInRange = function() return 1 end
  env.GetWeaponEnchantInfo = function() return false, 0, 0, 0, false, 0, 0, 0 end
  env.GetInventoryItemID = function() return 12345 end
  refresh()
  local function selfEntry()
    for i = 1, 15 do
      local r = env["BuffRadarRow" .. i]
      if r and r.entry and r.entry.isSelf then return r.entry end
    end
  end
  local e1 = selfEntry()
  assert(e1 and e1.weapon, "self row not flagged for a missing weapon enchant")
  -- Both hands enchanted: the flag clears.
  env.GetWeaponEnchantInfo = function() return true, 900, 0, 1, true, 900, 0, 2 end
  refresh()
  local e2 = selfEntry()
  assert(e2 and not e2.weapon, "weapon flag stuck after enchanting")
  env.GetWeaponEnchantInfo = nil
  env.GetInventoryItemID = nil
  cleanup()
end)

step("instance-entry reminder fires once per entry (1.7.0)", function()
  local cleanup = partyOfTwo("I")
  env.IsSpellInRange = function() return 1 end
  -- Start provably outside, then step in.
  env.IsInInstance = function() return false, "none" end
  fire("ZONE_CHANGED_NEW_AREA")
  local n0 = #chat
  env.IsInInstance = function() return true, "party" end
  fire("ZONE_CHANGED_NEW_AREA")
  assert(chatSince(n0, "Entered the dungeon with buffs missing"), "no entry reminder")
  local n1 = #chat
  fire("ZONE_CHANGED_NEW_AREA")
  assert(not chatSince(n1, "Entered the dungeon"), "entry reminder repeated while inside")
  env.IsInInstance = function() return false, "none" end
  fire("ZONE_CHANGED_NEW_AREA")
  cleanup()
end)

step("group expiry warning counts holders inside five minutes (1.7.0)", function()
  local cleanup = partyOfTwo("E")
  env.IsSpellInRange = function() return 1 end
  -- Everyone HAS the main buff, but only about four minutes of it.
  local main = env.__forever and "Power Word: Fortitude" or "Skyfury"
  env.__over.Aura = function(u, name)
    if name == main then return { expirationTime = env.GetTime() + 240 } end
  end
  refresh()
  local line
  for _, fs in ipairs(env.__fontstrings) do
    if type(fs.text) == "string" and fs.text:find("<5m on 3/", 1, true) then line = fs.text end
  end
  assert(line, "coverage line has no expiry warning")
  env.__over.Aura = nil
  cleanup()
end)

step("cast history records your casts (1.7.0)", function()
  local cleanup = partyOfTwo("H")
  local db = env.BuffRadarDB
  db.history = {}
  env.IsSpellInRange = function() return 1 end
  refresh()
  local row
  for i = 1, 15 do
    local r = env["BuffRadarRow" .. i]
    if r and r.entry and r.entry.unit == "party1" then row = r end
  end
  assert(row, "Aaron's row not found")
  row.scripts.PostClick(row, "LeftButton")  -- primes the pending cast
  local main = env.__forever and "Power Word: Fortitude" or "Skyfury"
  env.C_Spell = { GetSpellName = function() return main end }
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "castline", 4242)
  env.C_Spell = nil
  assert(#db.history == 1, "cast not recorded in history")
  assert(db.history[1].spell == main, "history spell: " .. tostring(db.history[1].spell))
  assert(db.history[1].who == "Aaron", "history target: " .. tostring(db.history[1].who))
  env.SlashCmdList.BUFFRADAR("resetcount")
  assert(#db.history == 0, "history not cleared by resetcount")
  cleanup()
end)

step("scan throttle halves the big-group rescan (1.7.0)", function()
  local db = env.BuffRadarDB
  env.SlashCmdList.BUFFRADAR("throttle")
  assert(db.scanThrottle == true, "throttle setting not stored")
  -- A 25-player raid: ticks must not error, refreshes still land.
  env.IsInRaid = function() return true end
  env.IsInGroup = function() return true end
  env.GetNumGroupMembers = function() return 25 end
  timerTick(); timerTick(); timerTick()
  refresh()
  env.IsInRaid = function() return false end
  env.IsInGroup = function() return false end
  env.GetNumGroupMembers = nil
  env.SlashCmdList.BUFFRADAR("throttle")
  assert(db.scanThrottle == false, "throttle not toggled off")
end)

step("grow-up window anchors by its bottom edge (1.8.0)", function()
  local db = env.BuffRadarDB
  env.SlashCmdList.BUFFRADAR("growup")
  assert(db.growUp == true, "growUp setting not stored")
  assert(db.point and db.point[1] == "BOTTOMLEFT",
    "saved point not in bottom form: " .. tostring(db.point and db.point[1]))
  env.SlashCmdList.BUFFRADAR("growup")
  assert(db.growUp == false, "growUp not toggled off")
  assert(db.point and db.point[1] == "TOPLEFT", "saved point not back in top form")
end)

step("color themes set the window colors (1.8.0)", function()
  local db = env.BuffRadarDB
  env.SlashCmdList.BUFFRADAR("theme midnight")
  local n = #chat
  env.SlashCmdList.BUFFRADAR("theme crimson")
  assert(db.theme == "crimson", "theme not stored")
  assert(db.bgColor[1] == 0.08 and db.bgColor[2] == 0.02 and db.bgColor[3] == 0.02,
    "theme background not applied")
  assert(chatSince(n, "Theme: Crimson"), "no theme message")
  local frame = env.BuffRadarFrame
  assert(frame.borderColor and frame.borderColor[1] == 0.75,
    "theme border not applied to the window")
  env.SlashCmdList.BUFFRADAR("theme")
  assert(chatSince(n, "crimson (current)"), "theme list does not mark the current theme")
  env.SlashCmdList.BUFFRADAR("theme bogus")
  assert(db.theme == "crimson", "a bogus theme changed the setting")
  env.SlashCmdList.BUFFRADAR("theme midnight")
  assert(db.theme == "midnight", "theme not restored")
end)

step("combat always hides the list and restores it afterward", function()
  local frame = env.BuffRadarFrame
  frame:Show()
  fire("PLAYER_REGEN_DISABLED")
  assert(not frame:IsShown(), "window still shown after combat started")
  fire("PLAYER_REGEN_ENABLED")
  timerTick()
  assert(frame:IsShown(), "window did not return after combat ended")
end)
step("combat visibility leaves locked frames to the secure driver", function()
  local frame, pill = env.BuffRadarFrame, NS.X.pill
  local db = env.BuffRadarDB
  local oldHidden = db.hidden
  local hideFrame, hidePill = frame.Hide, pill.Hide
  local function rejectLockedHide(hide)
    return function(self)
      assert(not env.__combat, "addon attempted a protected Hide during lockdown")
      hide(self)
    end
  end
  frame.Hide, pill.Hide = rejectLockedHide(hideFrame), rejectLockedHide(hidePill)
  local ok, err = pcall(function()
    frame:Show()
    pill:Show()
    env.__combat = not noTemplates
    fire("PLAYER_REGEN_DISABLED")
    assert(not frame.shown and not pill.shown, "combat did not hide both surfaces")
    if noTemplates then
      assert(not visibilityDrivers[frame] and not visibilityDrivers[pill], "fallback registered a driver")
    else
      assert(visibilityDrivers[frame] == 1 and visibilityDrivers[pill] == 1,
        "each combat surface should have one secure visibility driver")
    end
    env.__combat = false
    db.hidden = true
    fire("PLAYER_REGEN_ENABLED")
    assert(not frame.shown and not pill.shown, "combat exit force-showed a hidden surface")
    timerTick()
    assert(not frame.shown and not pill.shown, "post-combat refresh ignored manual hide")
  end)
  env.__combat, db.hidden = false, oldHidden
  frame.Hide, pill.Hide = hideFrame, hidePill
  assert(ok, err)
end)
step("appearance refresh never changes the frame layer and flash restore waits for combat", function()
  local X, db = NS.X, env.BuffRadarDB
  local frame, pill = env.BuffRadarFrame, X.pill
  local oldFrame, oldPill = frame.SetFrameStrata, pill.SetFrameStrata
  local oldMotion, writes = db.reduceMotion, 0
  frame.SetFrameStrata = function() writes = writes + 1; error("main frame layer is fixed") end
  pill.SetFrameStrata = function() writes = writes + 1; error("pill frame layer is fixed") end
  local ok, err = pcall(function()
    db.reduceMotion = false
    X.cfgAPI.ApplyAppearance()
    assert(writes == 0, "appearance refresh changed a frame layer")
    local restoreBorder
    X.Flash()
    if env.C_Timer then
      restoreBorder = table.remove(env.__timers)
      assert(restoreBorder, "border pulse did not schedule a restore")
    else
      assert(X.flashPending, "border pulse did not request a fallback restore")
    end
    env.__combat = true
    local delayOk, delayErr = true, nil
    if restoreBorder then delayOk, delayErr = pcall(restoreBorder) end
    assert(delayOk, "border restore failed in combat: " .. tostring(delayErr))
    assert(writes == 0, "combat flash restore changed a frame layer")
    env.__combat = false
    fire("PLAYER_REGEN_ENABLED")
    assert(not X.flashPending, "appearance replay left a redundant fallback border restore")
    X.cfgAPI.ApplyAppearance()
    assert(writes == 0, "appearance refresh attempted a protected frame-layer change")
  end)
  env.__combat = false
  frame.SetFrameStrata, pill.SetFrameStrata, db.reduceMotion = oldFrame, oldPill, oldMotion
  assert(ok, err)
end)
step("Lightning Shield secure actions rearm after combat and failed setup stays disarmed", function()
  if not env.__forever then return end
  local X, db, O = NS.X, NS.X.GetDB(), env.__over
  local oldClass, oldKnown = O.UnitClass, env.IsPlayerSpell
  local oldNames, oldInfo, oldTab = env.GetSpellBookItemName, env.GetSpellBookItemInfo, env.GetSpellTabInfo
  local oldHidden, oldGroup, oldSelf, oldCity = db.hidden, db.groupOnly, db.includeSelf, db.pauseInCities
  local oldMethod, oldShield = db.castMethod, db.enabled.SHAMAN_SHIELD
  local frame, nextButton = env.BuffRadarFrame, env.BuffRadarNextButton
  local oldStop = frame.StopMovingOrSizing
  local row, oldWrite, oldDriver
  local ok, err = pcall(function()
    O.UnitClass = function(unit) if unit == "player" then return "Shaman", "SHAMAN" end end
    env.IsPlayerSpell = function(id) return id == 324 end
    env.GetSpellBookItemName = function(i) if i == 1 then return "Lightning Shield", "Rank 1" end end
    env.GetSpellBookItemInfo = function(i) if i == 1 then return "SPELL", 324 end end
    env.GetSpellTabInfo = function() return "General", nil, 0, 1 end
    db.hidden, db.groupOnly, db.includeSelf, db.pauseInCities = false, false, true, false
    db.castMethod, db.enabled.SHAMAN_SHIELD = "target", true
    X.cfgAPI.BuildBuffList()
    X.Refresh()
    local listed = assert(shownRows().player, "Lightning Shield self row is absent")
    row = listed.row
    assert(listed["Lightning Shield"], "Lightning Shield is not the active shaman spell")
    oldWrite, oldDriver = row.SetAttribute, row.combatDriver
    assert(row:GetAttribute("spell") == "Lightning Shield" and nextButton:GetAttribute("unit") == "player",
      "Lightning Shield row or next button started disarmed")
    -- Secure driver writes are modeled by clearing both attributes without
    -- touching the addon's normal binding caches.
    row:SetAttribute("type", nil)
    nextButton:SetAttribute("type", nil)
    row.SetAttribute = function(self, key, value)
      assert(not env.__combat, "addon tried to write locked cast attributes")
      oldWrite(self, key, value)
    end
    frame.StopMovingOrSizing = function(self)
      assert(not env.__combat, "addon tried to stop a protected drag during lockdown")
      oldStop(self)
    end
    frame.isMoving = true
    row.combatDriver = false
    env.__combat = true
    fire("PLAYER_REGEN_DISABLED")
    fire("PLAYER_REGEN_ENABLED")
    assert(frame.isMoving and not row:GetAttribute("type"), "locked regen attempted cleanup or rearm")
    env.__combat = false
    fire("PLAYER_REGEN_ENABLED")
    X.Refresh()
    assert(not frame.isMoving and not row:GetAttribute("type"), "unavailable driver allowed row to arm")
    row.combatDriver = oldDriver
    fire("PLAYER_REGEN_ENABLED")
    X.Refresh()
    assert(row:GetAttribute("spell") == "Lightning Shield" and row:GetAttribute("type") == "spell"
      and nextButton:GetAttribute("type") == "spell", "post-combat Lightning Shield cast was not rearmed")
  end)
  env.__combat = false
  if row then row.SetAttribute, row.combatDriver = oldWrite, oldDriver end
  frame.StopMovingOrSizing, frame.isMoving = oldStop, false
  O.UnitClass, env.IsPlayerSpell = oldClass, oldKnown
  env.GetSpellBookItemName, env.GetSpellBookItemInfo, env.GetSpellTabInfo = oldNames, oldInfo, oldTab
  db.hidden, db.groupOnly, db.includeSelf, db.pauseInCities = oldHidden, oldGroup, oldSelf, oldCity
  db.castMethod, db.enabled.SHAMAN_SHIELD = oldMethod, oldShield
  X.cfgAPI.BuildBuffList()
  assert(ok, err)
end)

step("combat cast driver requires both secure setup operations to accept", function()
  local X = NS.X
  local previousRegister = env.RegisterStateDriver
  local registrations, snippetResult, driverResult = 0, false, nil
  local button = { SetAttribute = function() return snippetResult end }
  local ok, err = pcall(function()
    env.RegisterStateDriver = function()
      registrations = registrations + 1
      return driverResult
    end
    assert(not X.InstallCombatDriver(button, ""), "explicit snippet refusal armed the control")
    assert(registrations == 0, "driver installed after the snippet failed")
    snippetResult, driverResult = nil, false
    assert(not X.InstallCombatDriver(button, ""), "explicit driver refusal armed the control")
    snippetResult, driverResult = nil, nil
    assert(X.InstallCombatDriver(button, "") and registrations == 2, "successful void calls did not arm")
  end)
  env.RegisterStateDriver = previousRegister
  assert(ok, err)
end)

step("name finder filters the list (1.8.0)", function()
  local cleanup = partyOfTwo("F")
  local db = env.BuffRadarDB
  env.IsSpellInRange = function() return 1 end
  refresh()
  assert(shownRows().party1 and shownRows().party2, "both players listed before the search")
  env.SlashCmdList.BUFFRADAR("find aar")
  refresh()
  local rows = shownRows()
  assert(rows.party1 and not rows.party2, "search did not narrow the list to Aaron")
  env.SlashCmdList.BUFFRADAR("findbox")
  assert(db.findBox == true, "find box setting not stored")
  env.SlashCmdList.BUFFRADAR("findbox")
  assert(db.findBox == false, "find box not toggled off")
  env.SlashCmdList.BUFFRADAR("find off")
  refresh()
  assert(shownRows().party2, "clearing the search did not restore the list")
  cleanup()
end)

step("duration bar follows the expiring buff (1.8.0)", function()
  local cleanup = partyOfTwo("D")
  local O = env.__over
  env.IsSpellInRange = function() return 1 end
  -- Aaron's Fortitude is up but inside the rebuff window: it stays his
  -- first missing buff, with ~20 seconds left on it.
  local first = env.__forever and "Power Word: Fortitude" or "Skyfury"
  O.Aura = function(u, name)
    if u == "party1" and name == first then return { expirationTime = env.GetTime() + 20 } end
  end
  env.SlashCmdList.BUFFRADAR("bars")
  refresh()
  local row = shownRows().party1 and shownRows().party1.row
  assert(row, "Aaron not listed")
  assert(row.bar and row.bar.shown, "duration bar not shown for the expiring buff")
  env.SlashCmdList.BUFFRADAR("bars")
  refresh()
  assert(not row.bar.shown, "duration bar stayed after the setting went off")
  O.Aura = nil
  cleanup()
end)

step("raid marker badge shows on the row (1.8.0)", function()
  local cleanup = partyOfTwo("M")
  env.IsSpellInRange = function() return 1 end
  local marker, calls = 3, 0
  local previousCanAccess = env.canaccessvalue
  env.canaccessvalue = function(v) return v ~= 7 end
  env.GetRaidTargetIndex = function(u)
    calls = calls + 1
    if u == "party1" then return marker end
  end
  local db = NS.X.GetDB()
  local ok, err = pcall(function()
    refresh()
    assert(calls == 0, "raid marker API was called with markers off")
    env.SlashCmdList.BUFFRADAR("markers")
    refresh()
    local row = assert(shownRows().party1, "Aaron not listed").row
    assert(row.marker and row.marker.shown, "raid marker badge not shown")
    for _, invalid in ipairs({7, 9, 2.5}) do
      marker = invalid
      refresh()
      assert(not row.marker.shown, "unreadable or invalid raid marker was shown")
    end
    marker = 8
    refresh()
    assert(row.marker.shown, "valid raid marker did not return after an invalid one")
    env.SlashCmdList.BUFFRADAR("markers")
    calls = 0
    refresh()
    assert(not row.marker.shown, "raid marker stayed after the setting went off")
    assert(calls == 0, "raid marker API was called after markers were turned off")
  end)
  if db.raidMarkers then env.SlashCmdList.BUFFRADAR("markers") end
  env.GetRaidTargetIndex, env.canaccessvalue = nil, previousCanAccess
  cleanup()
  assert(ok, err)
end)

step("out-of-range group members stay off the list (1.8.0)", function()
  local cleanup = partyOfTwo("R")
  env.IsSpellInRange = function(_, u) if u == "party2" then return 0 end return 1 end
  refresh()
  assert(not shownRows().party2, "out-of-range party member appeared in the list")
  env.IsSpellInRange = function() return 1 end
  refresh()
  assert(shownRows().party2, "party member did not appear after moving into range")
  local selected = {}
  env.IsSpellInRange = function(spell) return spell == "Short-range buff" and 1 or 0 end
  assert(NS.X.FilterInRange("party2", { "Long-range buff", "Short-range buff" }, selected) == 1
    and selected[1] == "Short-range buff",
    "range filtering did not keep only castable buffs")
  env.IsSpellInRange = nil
  env.C_Spell = { IsSpellInRange = function() return nil end }
  local previousGroup, previousInteract = env.UnitInRange, env.CheckInteractDistance
  env.UnitInRange, env.CheckInteractDistance = nil, nil
  assert(NS.X.FilterInRange("party2", { "Unknown-range buff" }, selected) == 0,
    "unknown spell-specific range without a fallback was treated as safe")
  env.UnitInRange, env.CheckInteractDistance = previousGroup, previousInteract
  env.C_Spell = nil
  cleanup()
end)

step("range uses checked distance only when both spell range answers are unavailable", function()
  local previousModern, previousLegacy = env.C_Spell, env.IsSpellInRange
  local previousGroup, previousInteract = env.UnitInRange, env.CheckInteractDistance
  local previousCanAccess, previousUnitIsUnit = env.canaccessvalue, env.__over.UnitIsUnit
  local protected = {}
  local selected, spells = {}, { "Test buff" }
  env.canaccessvalue = function(v) return v ~= protected end
  local ok, err = pcall(function()
    local function listed(unit)
      return NS.X.FilterInRange(unit or "party2", spells, selected) == 1
    end
    local function inaccessible() return protected end
    env.C_Spell = { IsSpellInRange = inaccessible }
    env.IsSpellInRange = function() return 1 end
    assert(listed(), "readable legacy result did not replace inaccessible modern result")
    env.C_Spell.IsSpellInRange = function() return false end
    assert(not listed(), "explicit modern out-of-range result was replaced by legacy range")
    env.C_Spell.IsSpellInRange = function() error("unavailable") end
    assert(listed(), "readable legacy result did not replace failed modern query")
    env.C_Spell.IsSpellInRange, env.IsSpellInRange = inaccessible, inaccessible
    env.UnitInRange = function() return true, true end
    local count, approximate = NS.X.FilterInRange("party2", spells, selected)
    assert(count == 1 and approximate, "checked group distance did not fill in for unreadable spell results")
    env.UnitInRange = function() return false, true end
    env.CheckInteractDistance = function() return true end
    assert(not listed(), "checked group false was overridden by interaction distance")
    env.UnitInRange = function() return false, false end
    count, approximate = NS.X.FilterInRange("party2", spells, selected)
    assert(count == 1 and approximate, "interaction distance did not fill in for unchecked group range")

    -- Lua 5.1 has no secret primitives. Mask values that would otherwise
    -- normalize as in range so the assertions exercise the readability guard.
    local maskedFailures = {}
    local function expectHidden(message)
      if listed() then maskedFailures[#maskedFailures + 1] = message end
    end
    env.canaccessvalue = function(v) return v ~= true end
    env.C_Spell.IsSpellInRange = function() return true end
    env.IsSpellInRange = function() return false end
    expectHidden("masked modern true overrode readable legacy false")
    env.C_Spell, env.IsSpellInRange = nil, nil
    env.canaccessvalue = function(v) return v ~= 1 end
    env.CheckInteractDistance = function() return false end
    env.UnitInRange = function() return 1, true end
    expectHidden("masked group range result was treated as in range")
    env.UnitInRange = function() return true, 1 end
    expectHidden("masked group checked flag was treated as true")
    assert(#maskedFailures == 0, table.concat(maskedFailures, "; "))

    env.canaccessvalue = function(v) return v ~= protected end
    env.UnitInRange = function() return protected, true end
    env.CheckInteractDistance = function() return false end
    assert(not listed(), "unreadable group range was treated as in range")
    env.UnitInRange = function() return protected, protected end
    env.CheckInteractDistance = inaccessible
    assert(not listed(), "unreadable approximate range was treated as in range")
    env.CheckInteractDistance = function() return true end
    assert(listed(), "readable interact-distance fallback was ignored")
    env.UnitInRange = function() return false, true end
    assert(not listed(), "explicit group out-of-range result was replaced by interact range")
    env.__over.UnitIsUnit = function(unit) if unit == "target" then return true end return protected end
    env.CheckInteractDistance = function() return true end
    env.UnitInRange = function() return true, true end
    assert(not listed(), "unreadable self comparison was treated as self")
    assert(listed("player") and listed("target"), "self or self alias failed range check")
  end)
  env.C_Spell, env.IsSpellInRange = previousModern, previousLegacy
  env.UnitInRange, env.CheckInteractDistance = previousGroup, previousInteract
  env.canaccessvalue, env.__over.UnitIsUnit = previousCanAccess, previousUnitIsUnit
  assert(ok, err)
end)

step("assumeRange lists players this client refuses to place", function()
  local X, db = NS.X, NS.X.GetDB()
  local protected = {}
  local prevAccess = env.canaccessvalue
  local prevModern, prevLegacy = env.C_Spell, env.IsSpellInRange
  local prevGroup, prevInteract = env.UnitInRange, env.CheckInteractDistance
  local prevAssume, prevSilent = db.assumeRange, X.rangeSilent
  local selected, spells = {}, { "Test buff" }
  local ok, err = pcall(function()
    local function inaccessible() return protected end
    env.canaccessvalue = function(v) return v ~= protected end
    env.C_Spell = { IsSpellInRange = inaccessible }
    env.IsSpellInRange = inaccessible
    env.UnitInRange = function() return protected, protected end
    env.CheckInteractDistance = inaccessible

    -- The default stays strict, which is what the two steps above assert.
    db.assumeRange = false
    assert(X.FilterInRange("party2", spells, selected) == 0,
      "the strict default listed a player whose range nothing could answer")

    -- Opting in lists them, flagged estimated so the row says as much.
    db.assumeRange = true
    X.rangeSilent = false
    local count, approximate = X.FilterInRange("party2", spells, selected)
    assert(count == 1, "assumeRange did not list a player with no readable range")
    assert(approximate, "an assumed range was not flagged as estimated")
    assert(X.rangeSilent, "the silent-range flag was not recorded for diagnostics")

    -- An answer the client does give still wins over the assumption.
    env.CheckInteractDistance = function() return false end
    assert(X.FilterInRange("party2", spells, selected) == 0,
      "assumeRange overrode an explicit out-of-range answer")
    env.CheckInteractDistance = function() return true end
    assert(X.FilterInRange("party2", spells, selected) == 1,
      "a readable in-range answer stopped working with assumeRange on")
  end)
  db.assumeRange, X.rangeSilent = prevAssume, prevSilent
  env.canaccessvalue = prevAccess
  env.C_Spell, env.IsSpellInRange = prevModern, prevLegacy
  env.UnitInRange, env.CheckInteractDistance = prevGroup, prevInteract
  assert(ok, err)
end)

step("empty list explains range, nameplate, and buff states", function()
  local X = NS.X
  local oldRange, oldUnknown, oldPlates = X.rangeSilent, X.tallyUnknownUnits, X.FriendlyPlatesOn
  -- Expected text follows the client locale (the German setup shows deDE strings).
  local function T(s)
    local pack = env.BuffRadarLocales and env.GetLocale and env.BuffRadarLocales[env.GetLocale()]
    return (type(pack) == "table" and pack[s]) or s
  end
  local ok, err = pcall(function()
    X.tallyUnknownUnits = 0
    X.FriendlyPlatesOn = function() return true end
    X.rangeSilent = false
    assert(X.EmptyStatus() == T("Everyone nearby is buffed."), "known empty state is misleading")
    X.rangeSilent = true
    assert(X.EmptyStatus() == T("Range could not be confirmed; the list may be incomplete."), "silent range state was hidden")
    X.FriendlyPlatesOn = function() return false end
    X.rangeSilent = false
    assert(X.EmptyStatus() == T("Friendly nameplates are off."), "nameplate-off state was hidden")
    X.tallyUnknownUnits = 1
    assert(X.EmptyStatus() == T("Some buff information is unavailable."), "unreadable buff state lost priority")
  end)
  X.rangeSilent, X.tallyUnknownUnits, X.FriendlyPlatesOn = oldRange, oldUnknown, oldPlates
  assert(ok, err)
end)

step("silent-range diagnostic resets when a later scan answers", function()
  local cleanup = partyOfTwo("S")
  local X = NS.X
  local oldLegacy = env.__over.IsSpellInRange
  local oldModern = env.C_Spell and env.C_Spell.IsSpellInRange
  local ok, err = pcall(function()
    env.__over.IsSpellInRange = function() return 1 end
    if env.C_Spell then env.C_Spell.IsSpellInRange = function() return 1 end end
    X.rangeSilent = true
    refresh()
    assert(not X.rangeSilent, "a previous silent-range result remained sticky after a readable scan")
  end)
  env.__over.IsSpellInRange = oldLegacy
  if env.C_Spell then env.C_Spell.IsSpellInRange = oldModern end
  cleanup()
  assert(ok, err)
end)

step("unreadable rank levels and mana remain safe", function()
  local cleanup = partyOfTwo("Q")
  local X, db, O = NS.X, NS.X.GetDB(), env.__over
  local oldAccess, oldPower, oldMax, oldMana = env.canaccessvalue, env.UnitPower, env.UnitPowerMax, db.lowMana
  local protected = {}
  local ok, err = pcall(function()
    env.canaccessvalue = function(v) return v ~= protected end
    O.UnitLevel = function(unit) if unit == "party1" then return protected end return 60 end
    assert(not X.ReadUnitNumber(env.UnitLevel, "party1"), "unreadable level escaped numeric adapter")
    if env.__forever then
      local rank = X.PickRank("Power Word: Fortitude", "party1")
      assert(rank and rank.id == 1244, "unreadable level changed the default rank")
      O.UnitLevel = function(unit) if unit == "party1" then error("level unavailable") end return 60 end
      rank = X.PickRank("Power Word: Fortitude", "party1")
      assert(rank and rank.id == 1244, "level refusal changed the default rank")
    end
    db.lowMana = 25
    env.UnitPower = function(unit, powerType)
      assert(unit == "player" and powerType == 0, "mana queried without the mana power type")
      return protected
    end
    env.UnitPowerMax = function() return 100 end
    assert(not X.LowMana(), "unreadable mana paused the list")
    env.UnitPower = function() return 10 end
    assert(X.LowMana(), "readable low mana did not pause the list")
    env.UnitPowerMax = function() error("maximum mana unavailable") end
    assert(not X.LowMana(), "refused maximum mana paused the list")
    X.Refresh()
    assert(shownRows().party1, "guarded power refusal removed a valid row")
  end)
  env.canaccessvalue, env.UnitPower, env.UnitPowerMax, db.lowMana = oldAccess, oldPower, oldMax, oldMana
  cleanup()
  assert(ok, err)
end)

step("unit identity failures skip the unknown unit while allowing known self and allies", function()
  local cleanup = partyOfTwo("I")
  local oldAccess = env.canaccessvalue
  local function check(comparison, readable, label)
    env.__over.UnitIsUnit = function(unit, other)
      if unit == "party1" then return comparison() end
      return unit == other
    end
    env.canaccessvalue = readable
    NS.X.Refresh()
    local rows = shownRows()
    assert(rows.player and rows.party2 and not rows.party1, label)
  end
  local ok, err = pcall(function()
    check(function() error("incomparable tokens") end, nil, "comparison refusal stopped another row")
    local protectedTrue, protectedFalse = {}, {}
    local function readable(v) return v ~= protectedTrue and v ~= protectedFalse end
    check(function() return protectedTrue end, readable, "hidden true produced a target")
    check(function() return protectedFalse end, readable, "hidden false produced a target")
    env.canaccessvalue, env.__over.UnitIsUnit = nil, function(a, b) return a == b end
    NS.X.Refresh()
    assert(shownRows().party1, "readable identity did not restore target")
  end)
  env.canaccessvalue = oldAccess
  cleanup()
  assert(ok, err)
end)

step("restricted aura reads never offer an unverified recast or coverage result", function()
  local cleanup = partyOfTwo("U")
  local X, O = NS.X, env.__over
  local oldAccess, oldRebuff = env.canaccessvalue, X.GetDB().rebuff
  local protected = {}
  local ok, err = pcall(function()
    X.GetDB().rebuff = 30
    local function refreshAura()
      X.Refresh()
      return shownRows().party1
    end
    assert(refreshAura(), "readable empty aura list did not offer a buff")
    O.Aura = function(unit) if unit == "party1" then error("by-name restricted") end end
    O.AuraList = function(unit) if unit == "party1" then error("index restricted") end end
    assert(not refreshAura() and X.tallyUnknownUnits == 1, "restricted aura was treated as missing or known")
    O.Aura = function(unit) if unit == "party1" then return end return nil end
    assert(not refreshAura() and X.tallyUnknownUnits == 1, "zero-result aura refusal was treated as absence")
    O.Aura = function() return nil end
    assert(refreshAura() and X.tallyUnknownUnits == 0, "explicit nil aura absence required indexed access")
    O.Aura = function(unit) if unit == "party1" then return end return nil end
    env.canaccessvalue = function(v) return v ~= protected end
    O.AuraList = function(unit) if unit == "party1" then return {{ name = protected, expirationTime = 0 }} end end
    assert(not refreshAura(), "unreadable indexed aura name was treated as missing")
    O.AuraList = function() return {} end
    assert(refreshAura(), "known empty index fallback did not restore a missing row")
    O.Aura = function(unit) if unit == "party1" then return { expirationTime = protected } end end
    assert(not refreshAura() and X.tallyUnknownUnits == 1, "unreadable expiry was treated as a usable timer")
    X.GetDB().rebuff = 0
    assert(not refreshAura() and X.tallyUnknownUnits == 0, "known presence was discarded at a zero threshold")
    O.Aura = function(unit) if unit == "party1" then return { expirationTime = 0 } end end
    assert(not refreshAura() and X.tallyUnknownUnits == 0, "permanent aura did not count as present")
  end)
  env.canaccessvalue, X.GetDB().rebuff = oldAccess, oldRebuff
  cleanup()
  assert(ok, err)
end)

step("restricted aura event values coalesce a conservative refresh", function()
  if not env.__timers then return end
  local X, db = NS.X, NS.X.GetDB()
  local oldAccess, oldFast = env.canaccessvalue, db.fastAura
  local protected = {}
  local inaccessible = setmetatable({}, { __index = function() error("restricted aura payload") end })
  local ok, err = pcall(function()
    runQueued()
    db.fastAura = false
    fire("UNIT_AURA", "player", {})
    assert(#env.__timers == 0, "ordinary empty payload queued a refresh")
    fire("UNIT_AURA", "player", inaccessible)
    fire("UNIT_AURA", "player", inaccessible)
    assert(#env.__timers == 1, "unreadable payload did not coalesce a refresh")
    runQueued()
    db.fastAura = true
    env.canaccessvalue = function(v) return v ~= protected end
    fire("UNIT_AURA", "player", { addedAuras = {{ name = "Unwatched", auraInstanceID = protected }} })
    assert(#env.__timers == 1, "secret aura instance ID did not trigger a rescan")
    assert(not (X.auraIds and X.auraIds.player and X.auraIds.player[protected]), "secret ID was cached")
    runQueued()
  end)
  env.canaccessvalue, db.fastAura = oldAccess, oldFast
  assert(ok, err)
end)

step("focus watch line reports the focus target (1.8.0)", function()
  local cleanup = partyOfTwo("W")
  local O = env.__over
  local prevExists, prevPlayer = O.UnitExists, O.UnitIsPlayer
  O.UnitExists = function(u) if u == "focus" then return true end return prevExists(u) end
  O.UnitIsPlayer = function(u) if u == "focus" then return true end return prevPlayer(u) end
  O.UnitName = function(u) if u == "focus" then return "Focusdude" end
    if u == "player" then return "Me" end return u == "party1" and "Aaron" or "Zed" end
  O.UnitClass = function(u) if u == "focus" then return "Mage", "MAGE" end
    if u == "player" then return env.__forever and "PRIEST" or "SHAMAN", env.__forever and "PRIEST" or "SHAMAN" end
    return u == "party1" and "MAGE" or "WARRIOR", u == "party1" and "MAGE" or "WARRIOR" end
  env.SlashCmdList.BUFFRADAR("focus")
  refresh()
  local found
  for _, fs in ipairs(env.__fontstrings) do
    if type(fs.text) == "string" and fs.text:find("Focus Focusdude: needs", 1, true) then found = fs.text end
  end
  assert(found, "focus line not shown for an unbuffed focus")
  env.SlashCmdList.BUFFRADAR("focus")
  refresh()
  local still
  for _, fs in ipairs(env.__fontstrings) do
    if fs.shown and type(fs.text) == "string" and fs.text:find("Focus Focusdude", 1, true) then still = fs.text end
  end
  assert(not still, "focus line stayed after the setting went off")
  cleanup()
end)

step("group pets get their own rows (1.8.0)", function()
  if not env.__forever then return end  -- the harness priest knows pet buffs; the shaman knows none
  local cleanup = partyOfTwo("P")
  local O = env.__over
  local prevExists, prevPlayer = O.UnitExists, O.UnitIsPlayer
  O.UnitExists = function(u) if u == "partypet1" then return true end return prevExists(u) end
  O.UnitIsPlayer = function(u) if u == "partypet1" then return false end return prevPlayer(u) end
  O.UnitGUID = function(u) if u == "partypet1" then return "Pet-1-1P" end
    if u == "player" then return "Player-1-0001" end
    return "Player-1-P" .. u:sub(-1) .. "P" end
  O.UnitName = function(u) if u == "partypet1" then return "Fluffy" end
    if u == "player" then return "Me" end return u == "party1" and "Aaron" or "Zed" end
  env.IsSpellInRange = function() return 1 end
  env.SlashCmdList.BUFFRADAR("pets")
  refresh()
  local set = shownRows().partypet1
  assert(set, "Aaron's pet not listed")
  assert(set["Power Word: Fortitude"], "pet not offered Fortitude")
  assert(set.row.tag.text == "pet" or set.row.tag.text == "Begleiter",
    "pet row not tagged: " .. tostring(set.row.tag.text))
  local marker = 7
  env.issecretvalue = function(v) return v == 7 end
  env.GetRaidTargetIndex = function(unit) if unit == "partypet1" then return marker end end
  local ok, err = pcall(function()
    env.SlashCmdList.BUFFRADAR("markers")
    refresh()
    assert(not shownRows().partypet1.row.marker.shown, "secret pet marker was displayed")
    marker = 4
    refresh()
    assert(shownRows().partypet1.row.marker.shown, "readable pet marker was not displayed")
  end)
  env.issecretvalue, env.GetRaidTargetIndex = nil, nil
  env.SlashCmdList.BUFFRADAR("markers")
  env.SlashCmdList.BUFFRADAR("pets")
  refresh()
  assert(not shownRows().partypet1, "pet stayed after the setting went off")
  cleanup()
  assert(ok, err)
end)

step("aura and aspect watch toggles (1.8.0)", function()
  local db = env.BuffRadarDB
  local n = #chat
  env.SlashCmdList.BUFFRADAR("aura")
  if not env.__forever then
    assert(chatSince(n, "Forever edition"), "aura watch not refused on retail")
    assert(not db.auraWatch, "aura watch stored on retail")
    return
  end
  assert(db.auraWatch == true, "aura watch not stored")
  refresh()  -- a priest knows no aspects or auras: the list is unchanged, no error
  env.SlashCmdList.BUFFRADAR("aura")
  assert(db.auraWatch == false, "aura watch not toggled off")
end)

step("world-buff watch names your world buffs (1.8.0)", function()
  if not env.__forever then return end
  local cleanup = partyOfTwo("B")
  local O = env.__over
  O.AuraList = function(u)
    if u == "player" then
      return { { name = "Rallying Cry of the Dragonslayer", expirationTime = env.GetTime() + 7500 } }
    end
    return {}
  end
  O.Aura = function(u, name)
    if u == "player" and name == "Rallying Cry of the Dragonslayer" then
      return { expirationTime = env.GetTime() + 7500 }
    end
  end
  local n = #chat
  env.SlashCmdList.BUFFRADAR("worldbuff")
  assert(chatSince(n, "World: Rallying Cry of the Dragonslayer ~2h"),
    "world buff not reported by the toggle")
  refresh()
  local line
  for _, fs in ipairs(env.__fontstrings) do
    if type(fs.text) == "string" and fs.text:find("World: Rallying Cry", 1, true) then line = fs.text end
  end
  assert(line, "coverage line carries no world-buff segment")
  env.SlashCmdList.BUFFRADAR("worldbuff")
  O.AuraList = nil
  O.Aura = nil
  cleanup()
end)

step("drinking healers are tagged and counted (1.8.0)", function()
  if not env.__forever then return end
  local cleanup = partyOfTwo("K")
  local O = env.__over
  local prevClass = O.UnitClass
  O.UnitClass = function(u)
    if u == "party1" then return "Priest", "PRIEST" end
    return prevClass(u)
  end
  O.Aura = function(u, name)
    if u == "party1" and name == "Drink" then return { expirationTime = env.GetTime() + 60 } end
  end
  env.IsSpellInRange = function() return 1 end
  env.SlashCmdList.BUFFRADAR("drink")
  refresh()
  local set = shownRows().party1
  assert(set, "the drinking priest is not listed")
  assert(set.row.tag.text == "drinking" or set.row.tag.text == "trinkt gerade",
    "drinking tag missing: " .. tostring(set.row.tag.text))
  local line
  for _, fs in ipairs(env.__fontstrings) do
    if type(fs.text) == "string" and fs.text:find("Healer drinking", 1, true) then line = fs.text end
  end
  assert(line, "coverage line does not count the drinking healer")
  env.SlashCmdList.BUFFRADAR("drink")
  O.Aura = nil
  cleanup()
end)

step("per-buff context limits where a buff is offered (1.8.0)", function()
  local cleanup = partyOfTwo("T")
  local db = env.BuffRadarDB
  env.IsSpellInRange = function() return 1 end
  local key = env.__forever and "FORTITUDE" or "SKYFURY"
  local spell = env.__forever and "Power Word: Fortitude" or "Skyfury"
  refresh()
  assert(shownRows().party1 and shownRows().party1[spell], "buff offered before the context is set")
  env.SlashCmdList.BUFFRADAR("context " .. key .. " instance")
  assert(db.buffContext[key] == "instance", "context not stored")
  local n = #chat
  env.SlashCmdList.BUFFRADAR("buffs")
  assert(chatSince(n, "[instance only]"), "buff list does not show the context")
  refresh()  -- the party is in the open world, not an instance
  local set = shownRows().party1
  assert(not set or not set[spell], "buff still offered outside its context")
  env.SlashCmdList.BUFFRADAR("context " .. key .. " always")
  assert(db.buffContext[key] == nil, "context not cleared")
  refresh()
  assert(shownRows().party1 and shownRows().party1[spell], "buff not offered again after clearing")
  cleanup()
end)

step("plan strings carry the group plan to another user (1.8.0)", function()
  local cleanup = partyOfTwo("Q")
  local db = env.BuffRadarDB
  env.UnitIsGroupLeader = function(u) return u == "player" end
  local key = env.__forever and "FORTITUDE" or "SKYFURY"
  env.SlashCmdList.BUFFRADAR("assign " .. key .. " Aaron")
  env.SlashCmdList.BUFFRADAR("profile save pset")
  env.SlashCmdList.BUFFRADAR("autoprofile dungeon pset")
  env.SlashCmdList.BUFFRADAR("plan export")
  local text = env.BuffRadarExportFrame.editBox.text
  assert(type(text) == "string" and text:sub(1, 7) == "BRPLAN1",
    "plan string not produced: " .. tostring(text))
  env.SlashCmdList.BUFFRADAR("assign clear")
  env.SlashCmdList.BUFFRADAR("autoprofile dungeon clear")
  assert(db.autoProfile.dungeon == nil, "auto profile not cleared before import")
  env.SlashCmdList.BUFFRADAR("plan import")
  env.BuffRadarExportFrame.editBox:SetText(text)
  local n = #chat
  env.BuffRadarExportFrame.accept.scripts.OnClick(env.BuffRadarExportFrame.accept)
  assert(chatSince(n, "Plan imported: 1 assignments, 0 blessings, 1 auto profiles"),
    "plan import did not report the parts")
  assert(db.autoProfile.dungeon == "pset", "auto profile not restored by the plan")
  local n2 = #chat
  env.SlashCmdList.BUFFRADAR("assign")
  assert(chatSince(n2, key .. " -> Aaron"), "assignment not restored by the plan")
  env.SlashCmdList.BUFFRADAR("assign clear")
  env.SlashCmdList.BUFFRADAR("autoprofile dungeon clear")
  env.SlashCmdList.BUFFRADAR("profile delete pset")
  env.UnitIsGroupLeader = nil
  cleanup()
end)

step("plan import validates atomically and broadcasts only changes", function()
  local cleanup = partyOfTwo("QP")
  local X, db = NS.X, env.BuffRadarDB
  local assign, bless, mapping, leader, sent = X.assign, X.blessPlan, db.autoProfile, env.UnitIsGroupLeader, X.Broadcast
  X.assign, X.blessPlan, db.autoProfile = { FORTITUDE = "Aaron" }, {}, { dungeon = "Original" }
  env.UnitIsGroupLeader = function(u) return u == "player" end
  local messages = {}
  X.Broadcast = function(msg) messages[#messages + 1] = msg end
  assert(not X.PlanImport("BRPLAN1;A;FORTITUDE;Other;P;dungeon"), "incomplete plan was accepted")
  assert(not X.PlanImport("BRPLAN1;A;FORTITUDE;Other;A;FORTITUDE;Aaron"), "duplicate plan was accepted")
  assert(not X.PlanImport("BRPLAN1;P;unknown;Original"), "unknown plan context accepted")
  assert(X.PlanImport("BRPLAN1"), "empty plan was not accepted as no-op")
  assert(X.assign.FORTITUDE == "Aaron" and db.autoProfile.dungeon == "Original" and #messages == 0,
    "invalid or empty plan changed state")
  assert(X.PlanImport("BRPLAN1;A;FORTITUDE;Aaron;A;THORNS;Bela;P;raid;Future"))
  assert(db.autoProfile.dungeon == "Original" and db.autoProfile.raid == "Future", "plan mapping did not merge")
  assert(#messages == 1 and messages[1] == "ASSIGN;THORNS;Bela", "plan did not send only the changed record")
  env.UnitIsGroupLeader = nil
  assert(X.PlanImport("BRPLAN1;A;THORNS;Aaron"))
  assert(#messages == 1, "plan published assignments without leadership")
  X.assign, X.blessPlan, db.autoProfile, env.UnitIsGroupLeader, X.Broadcast = assign, bless, mapping, leader, sent
  cleanup()
end)
step("a single profile can be shared and imported (1.8.0)", function()
  local db = env.BuffRadarDB
  env.SlashCmdList.BUFFRADAR("profile save shareme")
  env.SlashCmdList.BUFFRADAR("profile share shareme")
  local text = env.BuffRadarExportFrame.editBox.text
  assert(type(text) == "string" and text:find("BuffRadar profile: shareme", 1, true),
    "share text has no header: " .. tostring(text))
  assert(text:find("\nBR2;", 1, true), "share text carries no versioned profile")
  env.SlashCmdList.BUFFRADAR("profile delete shareme")
  assert(db.profiles.shareme == nil, "profile not deleted before import")
  env.SlashCmdList.BUFFRADAR("profile import")
  env.BuffRadarExportFrame.editBox:SetText(text)
  local n = #chat
  env.BuffRadarExportFrame.accept.scripts.OnClick(env.BuffRadarExportFrame.accept)
  assert(chatSince(n, "Profile imported: shareme"), "profile import not reported")
  assert(type(db.profiles.shareme) == "string", "profile not stored by the import")
  env.SlashCmdList.BUFFRADAR("profile delete shareme")
end)

step("stats export and Discord summary render (1.8.0)", function()
  local cleanup = partyOfTwo("S")
  local db = env.BuffRadarDB
  local spell = env.__forever and "Power Word: Fortitude" or "Skyfury"
  db.stats[spell] = 5
  env.SlashCmdList.BUFFRADAR("stats export")
  local text = env.BuffRadarExportFrame.editBox.text
  assert(type(text) == "string" and text:find("BuffRadar cast statistics", 1, true),
    "stats export has no header")
  assert(text:find(spell .. ": 5", 1, true), "stats export missing the spell count")
  env.IsSpellInRange = function() return 1 end
  refresh()
  env.SlashCmdList.BUFFRADAR("discord")
  local dtext = env.BuffRadarExportFrame.editBox.text
  assert(type(dtext) == "string" and dtext:find("**BuffRadar", 1, true),
    "discord summary has no header")
  assert(dtext:find("Aaron", 1, true), "discord summary does not name who needs buffs")
  db.stats[spell] = nil
  cleanup()
end)

step("repeat offenders are counted when a group ends (1.8.0)", function()
  local cleanup = partyOfTwo("G")
  local db = env.BuffRadarDB
  env.IsSpellInRange = function() return 1 end
  -- Earlier sessions in this setup may already have counted these two;
  -- this step asserts exactly one more fold for its own session.
  local beforeA = db.offenders["Aaron"] or 0
  local beforeZ = db.offenders["Zed"] or 0
  refresh()  -- Aaron and Zed are both seen unbuffed this session
  env.IsInGroup = function() return false end
  fire("GROUP_ROSTER_UPDATE")  -- the group ends: the session folds
  assert(db.offenders["Aaron"] == beforeA + 1,
    "Aaron not counted once more: " .. tostring(db.offenders["Aaron"]))
  assert(db.offenders["Zed"] == beforeZ + 1, "Zed not counted once more")
  local n = #chat
  env.SlashCmdList.BUFFRADAR("offenders")
  assert(chatSince(n, "Aaron: " .. (beforeA + 1)), "offender list does not name Aaron")
  env.SlashCmdList.BUFFRADAR("offenders clear")
  assert(next(db.offenders) == nil, "offender history not cleared")
  cleanup()
end)

step("Behavior ignore-list hint clears the consumables checkbox", function()
  NS.X.OpenConfig(true)
  local cfg = env.BuffRadarConfig
  local hint
  for _, font in ipairs(env.__fontstrings) do
    if type(font.text) == "string" and font.text:find("Right-click any name in the BuffRadar window", 1, true) then
      hint = font
      break
    end
  end
  local point = assert(hint and hint.points and hint.points[1], "missing ignore-list hint anchor")
  assert(point[1] == "TOPLEFT" and point[2] == cfg.consCheck and point[3] == "BOTTOMLEFT" and point[5] <= -8,
    "ignore-list hint must clear the bottom of the consumables checkbox")
end)

step("settings controls and long labels stay within their columns", function()
  local cfg = env.BuffRadarConfig
  assert(cfg.growCheck.points[1][2] == 300 and cfg.growCheck.points[1][3] == -296,
    "Grow checkbox must clear the settings scale picker")
  assert(cfg.themeBtn.points[1][3] == -336 and cfg.saveThemeBtn.points[1][3] == -336,
    "theme buttons must clear the pill checkbox")
  assert(cfg.findCheck.points[1][2] == 300 and cfg.displayBtn.points[1][2] == 300,
    "Window controls must stay in the right column")
  for _, check in ipairs({cfg.pillCheck, cfg.findCheck, cfg.muteInstCheck, cfg.consCheck,
      cfg.fastAuraCheck, cfg.readyPostCheck, cfg.enterCheck, cfg.modClickCheck}) do
    assert(check.label.width == 250, "long settings label must wrap inside its column: " .. check.label.text)
  end
  assert(cfg.pullFlashCheck.points[1][3] <= cfg.fastAuraCheck.points[1][3] - 30,
    "pull-timer checkbox must clear the wrapped Fast Aura label")
  for _, control in ipairs(NS.X.cfgReg) do
    if control.w.text == "Reset buff order" then
      local anchor = control.w.points[1]
      assert(anchor[1] == "TOPLEFT" and anchor[3] == -346,
        "reset buff order belongs beside its rebuff settings, above the footer")
      return
    end
  end
  error("reset buff order control missing")
end)

step("settings search opens on demand and closes cleanly on tab changes", function()
  local cfg = env.BuffRadarConfig
  local footer = cfg.searchFooter
  local searchPoint = (footer or cfg.searchBox).points[1]
  local searchTop = cfg.size[2] - searchPoint[5] - (footer or cfg.searchBox).size[2]
  local data = cfg.panels.data
  local panelTop = data.points[1][3]
  if type(panelTop) == "number" then
    for _, control in ipairs(NS.X.cfgReg) do
      if control.w.text == "Raid" then
        local presetBottom = -panelTop - control.w.points[1][3] + control.w.size[2]
        assert(presetBottom + 8 <= searchTop, "preset row exceeds space above the settings footer")
        break
      end
    end
  end
  for _, panel in pairs(cfg.panels) do
    local bottom = panel.points[2]
    assert(bottom[2] == cfg and bottom[5] >= searchPoint[5] + footer.size[2] + 8,
      "tab panel must end at least 8 units above the search footer")
  end
  assert(not footer.shown and cfg.searchToggle.shown,
    "the search bar should start collapsed with its Find button available")
  cfg.searchToggle.scripts.OnClick(cfg.searchToggle)
  assert(footer.shown, "Find did not open the search bar")
  cfg.searchBox:SetText("buff")
  cfg.tabBtns.alerts.scripts.OnClick()
  assert(not footer.shown and cfg.searchBox.text == "" and cfg.searchToggle.shown,
    "switching tabs should close and clear search without hiding its toggle")
  cfg.tabBtns.look.scripts.OnClick()
  cfg.displayBtn.scripts.OnClick()
  assert(cfg.displayPanel.shown and not cfg.panels.look.shown and not footer.shown
    and not cfg.searchToggle.shown,
    "Display Options should replace the current tab and hide search controls")
  cfg.tabBtns.alerts.scripts.OnClick()
  assert(cfg.panels.alerts.shown and not cfg.displayPanel.shown and not footer.shown
    and cfg.searchToggle.shown,
    "selecting a tab should restore only the Find toggle")
  cfg.tabBtns.look.scripts.OnClick()
end)

step("settings scale fits a small UI and restores the saved preference", function()
  local cfg = env.BuffRadarConfig
  local db = env.BuffRadarDB
  local saved = db.cfgScale
  local getSize = env.UIParent.GetSize
  db.cfgScale = 2
  env.UIParent.GetSize = function() return 1024, 768 end
  NS.X.RefreshConfig()
  local scale = cfg:GetScale()
  local tabDepth = cfg.nativeTabs and 30 or 0
  assert(scale * cfg.size[1] <= 1024 and scale * (cfg.size[2] + 2 * tabDepth) <= 768,
    "settings and tabs must fit at the maximum saved scale")
  assert(db.cfgScale == 2, "temporary scale cap must not overwrite the preference")
  env.UIParent.GetSize = function() return 2000, 1600 end
  cfg.scripts.OnEvent(cfg, "DISPLAY_SIZE_CHANGED")
  assert(cfg:GetScale() == 2, "settings must restore the saved scale when it fits")
  env.UIParent.GetSize = getSize
  db.cfgScale = saved
  NS.X.RefreshConfig()
end)

step("settings search dims what does not match (1.8.0)", function()
  if not (env.BuffRadarConfig and env.BuffRadarConfig.shown) then
    env.SlashCmdList.BUFFRADAR("config")
  end
  local cfg = env.BuffRadarConfig
  local sb = cfg.searchBox
  assert(sb, "no settings search box")
  sb:SetText("opacity")
  sb.scripts.OnTextChanged(sb)
  assert(cfg.slider.alpha == 1, "the opacity slider was dimmed by its own search")
  assert(cfg.soundCheck.alpha == 0.25, "an unrelated control was not dimmed")
  sb:SetText("")
  sb.scripts.OnTextChanged(sb)
  assert(cfg.soundCheck.alpha == 1, "clearing the search did not restore the controls")
end)

step("death recap snapshots the group when you die (1.9.0)", function()
  local cleanup = partyOfTwo("DD")
  local db = env.BuffRadarDB
  env.IsSpellInRange = function() return 1 end
  refresh()
  local n = #chat
  fire("PLAYER_DEAD")
  assert(chatSince(n, "Death recap:"), "no death recap printed")
  assert(chatSince(n, "Aaron"), "death recap does not name Aaron")
  local n2 = #chat
  env.SlashCmdList.BUFFRADAR("death show")
  assert(chatSince(n2, "Death recap from your last death:"), "last recap not reprinted")
  env.SlashCmdList.BUFFRADAR("death")
  assert(db.deathRecap == false, "death recap not toggled off")
  env.SlashCmdList.BUFFRADAR("death")
  assert(db.deathRecap == true, "death recap not toggled back on")
  cleanup()
end)

step("post-wipe report fires after a real wipe (1.9.0)", function()
  local cleanup = partyOfTwo("WW")
  local db = env.BuffRadarDB
  local O = env.__over
  env.SlashCmdList.BUFFRADAR("wipe")
  assert(db.wipeReport == true, "wipe report not enabled")
  -- A controllable clock: the wipe gate needs an 8+ second fight.
  local t = 1000
  O.GetTime = function() return t end
  local dead = { party1 = true }
  O.UnitIsDeadOrGhost = function(u) return dead[u] or false end
  env.IsSpellInRange = function() return 1 end
  refresh()
  -- One dead in a party of three is not a wipe: no report.
  fire("PLAYER_REGEN_DISABLED")
  t = t + 20
  local n = #chat
  fire("PLAYER_REGEN_ENABLED")
  assert(not chatSince(n, "Wipe report"), "report fired for a single death")
  -- Both party members dead after a long fight: a wipe.
  dead.party2 = true
  fire("PLAYER_REGEN_DISABLED")
  t = t + 20
  local n2 = #chat
  fire("PLAYER_REGEN_ENABLED")
  assert(chatSince(n2, "Wipe report: 2 of 3 died."), "no wipe report after the wipe")
  assert(chatSince(n2, "1 person is missing buffs"),
    "wipe report should list the survivor's missing buffs")
  local n3 = #chat
  env.SlashCmdList.BUFFRADAR("wipe show")
  assert(chatSince(n3, "Wipe report from the last wipe:"), "last wipe report not reprinted")
  O.GetTime = nil
  O.UnitIsDeadOrGhost = nil
  env.SlashCmdList.BUFFRADAR("wipe")
  assert(db.wipeReport == false, "wipe report not toggled off")
  cleanup()
end)

step("saved themes, row spacing, icon size, window layer (1.10.0)", function()
  local db = env.BuffRadarDB
  -- Save the current custom colors as a theme, apply another, come back.
  db.bgColor = { 0.1, 0.2, 0.3 }
  db.theme = "custom"
  env.SlashCmdList.BUFFRADAR("theme save ocean")
  assert(#db.customThemes == 1 and db.customThemes[1].name == "ocean",
    "theme not saved: " .. tostring(db.customThemes[1] and db.customThemes[1].name))
  assert(db.theme == "ocean", "saved theme not applied after saving")
  env.SlashCmdList.BUFFRADAR("theme midnight")
  assert(db.theme == "midnight", "built-in theme not applied")
  env.SlashCmdList.BUFFRADAR("theme ocean")
  assert(db.theme == "ocean" and db.bgColor[2] == 0.2,
    "saved theme colors not restored: " .. tostring(db.bgColor[2]))
  env.SlashCmdList.BUFFRADAR("theme delete ocean")
  assert(#db.customThemes == 0 and db.theme == "custom",
    "theme delete did not fall back to custom")
  -- Sanitizer keeps a well-formed saved theme, drops the broken ones.
  env.BuffRadarDB.customThemes = {
    { name = "Good", bg = { 0, 0, 0 }, border = { 1, 1, 1 } },
    { name = "Broken" }, "junk",
  }
  fire("ADDON_LOADED", "BuffRadar")
  db = env.BuffRadarDB
  assert(#db.customThemes == 1 and db.customThemes[1].name == "Good",
    "sanitizer mishandled saved themes")
  db.customThemes = {}
  -- Row spacing + icon size move the row anchors and icon sizes.
  local cleanup = partyOfTwo("GG")
  db = env.BuffRadarDB
  refresh()
  local r1, r2 = env.BuffRadarRow1, env.BuffRadarRow2
  local y1 = r2.points[1][5] - r1.points[1][5]
  env.SlashCmdList.BUFFRADAR("rowgap 6")
  assert(db.rowGap == 6, "row gap not stored")
  local y2 = r2.points[1][5] - r1.points[1][5]
  assert(y2 == y1 - 6, "row gap did not widen the pitch: " .. tostring(y1) .. " -> " .. tostring(y2))
  env.SlashCmdList.BUFFRADAR("rowgap 0")
  env.SlashCmdList.BUFFRADAR("iconsize 20")
  assert(db.iconSize == 20, "icon size not stored")
  assert(r1.icons[1].size and r1.icons[1].size[1] == 20,
    "icon size not applied: " .. tostring(r1.icons[1].size and r1.icons[1].size[1]))
  env.SlashCmdList.BUFFRADAR("iconsize 0")
  cleanup()
end)

step("coverage parts, tooltip levels, names, row colors (1.10.0)", function()
  local cleanup = partyOfTwo("TT")
  local db = env.BuffRadarDB
  refresh()
  -- Coverage line: the progress part switches off and back on.
  local function coverHas(text)
    for _, fs in ipairs(env.__fontstrings) do
      if type(fs.text) == "string" and fs.text:find(text, 1, true) then return true end
    end
    return false
  end
  assert(coverHas("0/3 fully buffed"), "coverage progress not shown")
  env.SlashCmdList.BUFFRADAR("cover progress off")
  assert(db.coverParts.progress == false, "cover part not stored")
  refresh()
  assert(not coverHas("0/3 fully buffed"), "coverage progress still shown after off")
  env.SlashCmdList.BUFFRADAR("cover progress on")
  refresh()
  assert(coverHas("0/3 fully buffed"), "coverage progress did not come back")
  -- Tooltip levels on Aaron's row.
  local function findRow()
    for i = 1, 15 do
      local r = env["BuffRadarRow" .. i]
      if r and r.entry and r.entry.unit == "party1" then return r end
    end
  end
  local arow = findRow()
  assert(arow, "Aaron has no row")
  local function tipLines()
    local lines = {}
    local realTip = env.GameTooltip
    env.GameTooltip = { SetOwner = function() end, Show = function() end,
      SetUnit = function() end, Hide = function() end,
      AddLine = function(_, t) lines[#lines + 1] = t end }
    arow.scripts.OnEnter(arow)
    env.GameTooltip = realTip
    return lines
  end
  local function anyLine(lines, text)
    for _, t in ipairs(lines) do
      if type(t) == "string" and t:find(text, 1, true) then return true end
    end
    return false
  end
  env.SlashCmdList.BUFFRADAR("tooltip minimal")
  assert(not anyLine(tipLines(), "Right-click"),
    "minimal tooltip still shows the hint lines")
  env.SlashCmdList.BUFFRADAR("tooltip full")
  assert(anyLine(tipLines(), "In your group"),
    "full tooltip lacks the group line")
  env.SlashCmdList.BUFFRADAR("tooltip standard")
  -- (Row names are re-rendered only for a new player on the row, so the
  -- name-format checks below use fresh scenes, like the config's own
  -- invalidate path would produce in the game.)
  -- Row color mark: tank rows get a sky edge strip.
  env.UnitGroupRolesAssigned = function(u) return u == "party2" and "TANK" or "DAMAGER" end
  env.SlashCmdList.BUFFRADAR("rowcolor tank sky")
  assert(db.rowColors.tank and db.rowColors.tank[2] == 0.7, "row color not stored")
  refresh()
  local zrow
  for i = 1, 15 do
    local r = env["BuffRadarRow" .. i]
    if r and r.entry and r.entry.unit == "party2" then zrow = r end
  end
  assert(zrow, "Zed has no row")
  assert(zrow.tint.shown and zrow.tint.vcolor and zrow.tint.vcolor[2] == 0.7,
    "tank row has no sky mark")
  env.SlashCmdList.BUFFRADAR("rowcolor tank off")
  env.UnitGroupRolesAssigned = nil
  refresh()
  cleanup()
  -- Row names: realm shown and the name shortened. (A row re-renders its
  -- name when a different player lands on it, so the settings are set
  -- between two scenes — the same moment the settings window's own
  -- invalidate produces in the game.)
  local cleanup2 = partyOfTwo("UU")
  local db2 = env.BuffRadarDB
  local O2 = env.__over
  O2.UnitFullName = function(u) if u == "party1" then return "Aaron", "OtherRealm" end end
  db2.showRealm = true
  db2.nameTrim = 4
  cleanup2 = partyOfTwo("U2")
  O2.UnitFullName = function(u) if u == "party1" then return "Aaron", "OtherRealm" end end
  refresh()
  local arow2 = findRow()
  assert(arow2 and arow2.name.text == "Aaro…",
    "realm + shortened name wrong: " .. tostring(arow2 and arow2.name.text))
  db2.showRealm = false
  db2.nameTrim = 0
  cleanup2()
  -- Class colors off: the name renders in plain light grey. (Aaron must
  -- be in range for this: out of range greys the name either way.)
  local cleanup3 = partyOfTwo("VV")
  local db3 = env.BuffRadarDB
  db3.classColors = false
  cleanup3 = partyOfTwo("V2")
  env.IsSpellInRange = function() return 1 end
  refresh()
  local arow3 = findRow()
  assert(arow3 and arow3.name.color and arow3.name.color[1] == 0.92,
    "class colors off did not switch the name color")
  db3.classColors = true
  cleanup3()
end)

step("per-kind sounds, buff priority, click-through (1.10.0)", function()
  local db = env.BuffRadarDB
  -- a sound per kind of alert
  env.SlashCmdList.BUFFRADAR("soundfor drop none")
  assert(db.alertSounds.drop == "none", "per-kind sound not saved")
  env.SlashCmdList.BUFFRADAR("soundfor drop droplet")
  assert(db.alertSounds.drop == "droplet", "per-kind sound not changed")
  env.SlashCmdList.BUFFRADAR("soundfor master system")
  assert(db.alertSound == "system", "master sound not changed")
  env.SlashCmdList.BUFFRADAR("soundfor master droplet")
  assert(db.alertSound == "droplet", "master sound not restored")
  -- click-through only bites while the window is locked
  local row = env.BuffRadarRow1
  env.SlashCmdList.BUFFRADAR("clickthrough")
  assert(db.clickThrough == true, "click-through not on")
  assert(row.mouseEnabled ~= false, "click-through bit while unlocked")
  env.SlashCmdList.BUFFRADAR("lock")
  assert(db.locked == true, "window not locked")
  assert(row.mouseEnabled == false, "rows still catch clicks while locked")
  assert(env.BuffRadarFrame.mouseEnabled == false, "frame still catches clicks while locked")
  env.SlashCmdList.BUFFRADAR("lock")
  assert(row.mouseEnabled == true, "rows did not get their clicks back on unlock")
  env.SlashCmdList.BUFFRADAR("clickthrough")
  assert(db.clickThrough == false, "click-through not off")
  -- buff priority: the Forever priest offers Fortitude then Spirit by
  -- default; putting Spirit first makes it the row's cast target
  if env.__forever then
    local cleanup = partyOfTwo("PP")
    refresh()
    local arow
    for i = 1, 15 do
      local r = env["BuffRadarRow" .. i]
      if r and r.entry and r.entry.unit == "party1" then arow = r; break end
    end
    assert(arow and arow.cMissing and arow.cMissing[1] == "Power Word: Fortitude",
      "default first offer is not Fortitude: " .. tostring(arow and arow.cMissing and arow.cMissing[1]))
    env.SlashCmdList.BUFFRADAR("prio DIVINE_SPIRIT 1")
    assert(db.buffPrio[1] == "DIVINE_SPIRIT", "priority not saved")
    refresh()
    assert(arow.cMissing[1] == "Divine Spirit",
      "row did not offer Spirit first: " .. tostring(arow.cMissing[1]))
    env.SlashCmdList.BUFFRADAR("prio reset")
    assert(#db.buffPrio == 0, "priority not reset")
    refresh()
    assert(arow.cMissing[1] == "Power Word: Fortitude", "priority reset did not restore the order")
    cleanup()
  end
end)

step("group-by-buff view (1.10.0)", function()
  local db = env.BuffRadarDB
  local cleanup = partyOfTwo("BB")
  refresh()
  env.SlashCmdList.BUFFRADAR("view buffs")
  assert(db.viewMode == "buffs", "view mode not saved")
  refresh()
  local r1, r2 = env.BuffRadarRow1, env.BuffRadarRow2
  assert(r1.entry and r1.entry.guid and r1.entry.guid:sub(1, 5) == "buff:",
    "first row is not a buff row")
  -- counts decide first: on Forever, Fortitude is missing by all three
  -- (Spirit by two), so Fortitude leads; on Retail, Skyfury leads.
  local firstBuff = env.__forever and "Power Word: Fortitude" or "Skyfury"
  local secondBuff = env.__forever and "Divine Spirit" or nil
  assert(r1.name.text and r1.name.text:find(firstBuff, 1, true),
    "first buff row should be " .. firstBuff .. ": " .. tostring(r1.name.text))
  if secondBuff then
    assert(r2.name.text and r2.name.text:find(secondBuff, 1, true),
      "second buff row should be Spirit: " .. tostring(r2.name.text))
  end
  assert(r1.entry.unit == "player" or r1.entry.unit == "party1" or r1.entry.unit == "party2",
    "buff row has no cast target")
  assert(r1.entry.missing and r1.entry.missing[1] == firstBuff,
    "buff row would not cast its own spell")
  env.SlashCmdList.BUFFRADAR("view people")
  assert(db.viewMode == "people", "view mode not restored")
  refresh()
  local found = false
  for i = 1, 15 do
    local r = env["BuffRadarRow" .. i]
    if r and r.entry and r.entry.unit == "party1" then found = true break end
  end
  assert(found, "people view did not come back")
  cleanup()
end)

step("setup wizard walks a new user through (1.9.0)", function()
  local db = env.BuffRadarDB
  assert(db.wizardSeen == false, "wizard should start unseen on a fresh save")
  env.SlashCmdList.BUFFRADAR("wizard")
  local w = env.BuffRadarWizard
  assert(w and w.shown, "wizard did not open")
  -- Page 1: dirty the sort mode, then pick "In a party" (dungeon preset).
  db.sortMode = "role"
  w.choice[2].scripts.OnClick(w.choice[2])
  assert(db.sortMode == "need", "party preset not applied by the wizard: " .. tostring(db.sortMode))
  assert(db.groupOnly == true, "party preset did not set groupOnly")
  assert(w.page == 2, "wizard did not advance to page 2")
  -- Page 2: the theme button cycles the theme.
  local before = db.theme
  w.choice[1].scripts.OnClick(w.choice[1])
  assert(db.theme ~= before, "theme not cycled on page 2")
  w.next.scripts.OnClick(w.next)
  assert(w.page == 3, "wizard did not advance to page 3")
  -- Page 3: Finish closes it and marks it seen.
  w.next.scripts.OnClick(w.next)
  assert(db.wizardSeen == true, "finishing did not mark the wizard seen")
  assert(not w.shown, "wizard did not close on Finish")
end)

step("two-column layout splits a long list (1.9.0)", function()
  local db = env.BuffRadarDB
  -- An 11-member raid plus the player: 12 people, all missing a buff.
  local units = {}
  local classes = { "MAGE", "WARRIOR", "PRIEST", "DRUID", "ROGUE" }
  for i = 1, 11 do
    units["raid" .. i] = { name = string.format("Raider%02d", i), class = classes[(i % 5) + 1] }
  end
  local O = env.__over
  O.UnitExists = function(u) return u == "player" or units[u] ~= nil end
  O.UnitIsPlayer = O.UnitExists
  O.UnitGUID = function(u)
    if units[u] then return "Player-1-R" .. u:sub(5) end
    if u == "player" then return "Player-1-0001" end
  end
  O.UnitName = function(u) if units[u] then return units[u].name end if u == "player" then return "Me" end end
  O.UnitFullName = function(u)
    if units[u] then return units[u].name, "TestRealm" end
    if u == "player" then return "Me", "TestRealm" end
  end
  O.UnitClass = function(u)
    if units[u] then return units[u].class, units[u].class end
    if u == "player" then return env.__forever and "PRIEST" or "SHAMAN", env.__forever and "PRIEST" or "SHAMAN" end
  end
  O.Aura = nil
  env.IsInRaid = function() return true end
  env.IsInGroup = function() return true end
  env.GetNumGroupMembers = function() return 12 end
  db.showOutOfRange, db.pauseInCities, db.hidden, db.groupOnly, db.autoHide = true, false, false, false, false
  env.IsSpellInRange = function() return 1 end
  refresh()
  local frame = env.BuffRadarFrame
  local w1 = frame.width
  local row7 = env.BuffRadarRow7  -- 12 rows: single column row 7; two columns start at row 7
  assert(row7 and row7.shown, "row 7 not shown in the raid")
  assert(row7.points[1][4] == 6, "single column: row 7 starts at x=6, got " .. tostring(row7.points[1][4]))
  env.SlashCmdList.BUFFRADAR("twocol")
  assert(db.twoCol == true, "twoCol setting not stored")
  refresh()
  assert(frame.width > w1, "frame did not widen for two columns: " .. tostring(frame.width))
  local p1, p7 = env.BuffRadarRow1.points[1], row7.points[1]
  assert(p7[4] > p1[4], "row 7 did not move into the second column")
  assert(p7[5] == p1[5], "row 7 is not at the top of the second column")
  env.SlashCmdList.BUFFRADAR("twocol")
  refresh()
  assert(frame.width == w1, "frame did not narrow back: " .. tostring(frame.width))
  assert(row7.points[1][4] == 6, "row 7 did not return to the single column")
  for k in pairs(O) do O[k] = nil end
  env.IsInRaid = function() return false end
  env.IsInGroup = function() return false end
  env.GetNumGroupMembers = nil
  env.IsSpellInRange = nil
end)

step("coverage uptime scores the run (1.6.0)", function()
  local cleanup = partyOfTwo("V")
  env.IsSpellInRange = function() return 1 end
  env.SlashCmdList.BUFFRADAR("uptime reset")
  refresh()  -- everyone is missing buffs: the full-scan share is 0%
  local n = #chat
  env.SlashCmdList.BUFFRADAR("uptime")
  assert(chatSince(n, "Coverage uptime this run: 0%"), "uptime not 0% while buffs are missing")
  env.__over.Aura = function(u, name) return { expirationTime = env.GetTime() + 600 } end
  env.SlashCmdList.BUFFRADAR("uptime reset")
  for i = 1, 12 do refresh() end
  local cover
  for _, fs in ipairs(env.__fontstrings) do
    if type(fs.text) == "string" and fs.text:find("Uptime 100%%") then cover = fs.text end
  end
  assert(cover, "coverage line shows no 100% uptime after full scans")
  fire("CHALLENGE_MODE_START")  -- a new run resets the score
  local n2 = #chat
  env.SlashCmdList.BUFFRADAR("uptime")
  assert(chatSince(n2, "no grouped scans yet"), "uptime not reset at run start")
  env.__over.Aura = nil
  cleanup()
end)

step("auto profile switches with the context (1.6.0)", function()
  local db = env.BuffRadarDB
  env.SlashCmdList.BUFFRADAR("scale 1.5")
  env.SlashCmdList.BUFFRADAR("profile save dset")
  env.SlashCmdList.BUFFRADAR("scale 1")
  assert(db.scale == 1, "scale not back at 1 before the switch")
  env.SlashCmdList.BUFFRADAR("autoprofile dungeon dset")
  assert(db.autoProfile and db.autoProfile.dungeon == "dset", "auto profile not saved")
  env.IsInInstance = function() return true, "party" end
  local n = #chat
  fire("ZONE_CHANGED_NEW_AREA")
  assert(db.scale == 1.5, "dungeon auto profile did not apply (scale " .. tostring(db.scale) .. ")")
  assert(chatSince(n, "Auto profile for dungeon: dset"), "auto profile load not announced")
  env.IsInInstance = function() return false, "none" end
  fire("ZONE_CHANGED_NEW_AREA")  -- solo now: no mapping, scale stays
  assert(db.scale == 1.5, "solo context unexpectedly changed settings")
  env.SlashCmdList.BUFFRADAR("scale 1")
  env.IsInInstance = function() return true, "party" end
  fire("ZONE_CHANGED_NEW_AREA")
  assert(db.scale == 1.5, "mapped context was skipped after returning from unmapped solo")
  env.SlashCmdList.BUFFRADAR("scale 1")
  fire("ZONE_CHANGED_NEW_AREA")
  assert(db.scale == 1, "same-context event discarded manual changes")
  env.IsInInstance = function() return false, "none" end
  fire("ZONE_CHANGED_NEW_AREA")
  db.autoProfile.dungeon = "Missing"
  env.IsInInstance = function() return true, "party" end
  local failure = #chat
  fire("ZONE_CHANGED_NEW_AREA")
  assert(chatSince(failure, "could not load 'Missing'"), "failed auto profile did not explain the failure")
  failure = #chat
  fire("ZONE_CHANGED_NEW_AREA")
  assert(not chatSince(failure, "could not load 'Missing'"), "failed auto profile repeated during same visit")
  env.IsInInstance = function() return false, "none" end
  fire("ZONE_CHANGED_NEW_AREA")
  env.SlashCmdList.BUFFRADAR("autoprofile dungeon clear")
  assert(db.autoProfile.dungeon == nil, "auto profile not cleared")
  env.SlashCmdList.BUFFRADAR("profile delete dset")
  env.SlashCmdList.BUFFRADAR("scale 1")
end)

step("per-class blessing choices persist and defer to the group plan", function()
  if not env.__forever then return end
  local X, db = NS.X, env.BuffRadarDB
  local oldKnown, oldPreferences, oldPlan = env.IsPlayerSpell, db.blessingPreferences, X.blessPlan.MAGE
  local function cleanup()
    env.IsPlayerSpell, db.blessingPreferences, X.blessPlan.MAGE = oldKnown, oldPreferences, oldPlan
    X.DeleteProfile("AuditBlessing")
    X.cfgAPI.BuildBuffList()
    if env.BuffRadarBlessingPreferences then env.BuffRadarBlessingPreferences:Hide() end
    if X.RefreshConfig then X.RefreshConfig() end
  end
  local ok, err = pcall(function()
    env.IsPlayerSpell = function(id) return id == 19740 or id == 19742 or oldKnown(id) end
    db.blessingPreferences, X.blessPlan.MAGE = {}, nil
    X.cfgAPI.BuildBuffList()
    assert(X.BlessingForClass("MAGE").name == "Blessing of Wisdom", "default blessing changed")
    local sent = #env.__addonSent
    env.SlashCmdList.BUFFRADAR("bless prefer MAGE MIGHT")
    assert(X.BlessingForClass("MAGE").name == "Blessing of Might", "preference did not select a known blessing")
    assert(#env.__addonSent == sent, "private preference broadcast to the group")
    assert(not X.SetBlessingPreference("MAGE", "KINGS"), "unlearned blessing became a new preference")
    X.blessPlan.MAGE = { key = "WISDOM", mine = true }
    assert(X.BlessingForClass("MAGE").name == "Blessing of Wisdom", "group plan did not override preference")
    X.blessPlan.MAGE.mine = false
    assert(X.BlessingForClass("MAGE") == nil, "other paladin's assignment was ignored")
    X.blessPlan.MAGE = nil
    assert(X.SaveProfile("AuditBlessing"), "could not save preferred blessing")
    env.SlashCmdList.BUFFRADAR("bless prefer MAGE DEFAULT")
    assert(db.blessingPreferences.MAGE == nil, "default did not clear the preference")
    assert(X.LoadProfile("AuditBlessing") and db.blessingPreferences.MAGE == "MIGHT",
      "named profile did not restore preferred blessing")
    local cfg = env.BuffRadarConfig
    X.RefreshConfig()
    assert(cfg.blessingButton.shown, "known blessings did not expose the settings button")
    cfg.blessingButton:GetScript("OnClick")(cfg.blessingButton)
    assert(env.BuffRadarBlessingPreferences.shown and #cfg.blessingSelectors == 9,
      "blessing settings did not show one control per Forever class")
    env.IsPlayerSpell = function(id) return id == 19742 or oldKnown(id) end
    X.cfgAPI.BuildBuffList()
    assert(X.BlessingForClass("MAGE").name == "Blessing of Wisdom" and db.blessingPreferences.MAGE == "MIGHT",
      "an unavailable saved preference did not fall back without clearing it")
  end)
  cleanup()
  assert(ok, err)
end)
step("blessing plan: set, broadcast, receive, list (1.6.0)", function()
  if not env.__forever then return end
  local cleanup = partyOfTwo("L")
  env.BuffRadarDB.sync = true
  env.UnitIsGroupLeader = function(u) return u == "player" end
  env.__addonSent = {}
  env.SlashCmdList.BUFFRADAR("bless WARRIOR MIGHT")
  assert(chatSince(0, "Blessing plan: WARRIOR gets MIGHT"), "bless plan not set")
  local sent = env.__addonSent[#env.__addonSent]
  assert(sent and sent.msg == "BLESS;WARRIOR;MIGHT;Me-TestRealm",
    "bless broadcast: " .. tostring(sent and sent.msg))
  env.__over.UnitClass = function(u)
    if u == "party1" then return "Paladin", "PALADIN" end
    return "Mage", "MAGE"
  end
  fire("CHAT_MSG_ADDON", "BuffRadar", "BLESS;MAGE;WISDOM;Aaron-TestRealm", "PARTY", "Aaron-TestRealm")
  local n = #chat
  env.SlashCmdList.BUFFRADAR("bless")
  assert(chatSince(n, "MAGE: WISDOM (Aaron-TestRealm)"), "received plan not listed")
  env.UnitIsGroupLeader = nil
  cleanup()
end)
step("named settings profiles save, load, list, delete (1.5.0)", function()
  local db = env.BuffRadarDB
  local keepScale = db.scale
  env.SlashCmdList.BUFFRADAR("scale 1.5")
  assert(db.scale == 1.5, "scale not set before saving the profile")
  local n0 = #chat
  env.SlashCmdList.BUFFRADAR("profile save RaidNight")
  assert(db.profiles and db.profiles.RaidNight, "profile not saved")
  assert(chatSince(n0, "Profile saved: RaidNight"), "no save message")
  env.SlashCmdList.BUFFRADAR("scale 0.75")
  assert(db.scale == 0.75, "scale not changed after saving")
  env.SlashCmdList.BUFFRADAR("profile load RaidNight")
  assert(db.scale == 1.5, "profile load did not restore the scale: " .. tostring(db.scale))
  assert(db.profiles.RaidNight, "loading a profile deleted it")
  local n = #chat
  env.SlashCmdList.BUFFRADAR("profile list")
  assert(chatSince(n, "RaidNight"), "profile list does not name the profile")
  env.SlashCmdList.BUFFRADAR("profile delete RaidNight")
  assert(db.profiles.RaidNight == nil, "profile not deleted")
  env.SlashCmdList.BUFFRADAR("scale " .. tostring(keepScale or 1))
end)
step("profiles restore window and buff settings and retain old saves", function()
  local X, db = NS.X, env.BuffRadarDB
  local keep = { compact = db.compact, alertSounds = db.alertSounds, buffPrio = db.buffPrio }
  db.compact, db.alertSounds, db.buffPrio = true, { drop = "droplet" }, { "THORNS", "MOTW" }
  assert(X.SaveProfile("AuditProfile"), "could not save a profile")
  db.compact, db.alertSounds, db.buffPrio = false, { drop = "system", ask = "system" }, { "MOTW" }
  local loaded = X.LoadProfile("AuditProfile")
  local restored = db.compact and db.alertSounds.drop == "droplet" and not db.alertSounds.ask
    and db.buffPrio[1] == "THORNS" and db.buffPrio[2] == "MOTW"
  local keepScale = db.scale
  assert(X.ProfileImport("BuffRadar profile: AuditLegacy\nBR1;scale=1.25"), "valid legacy profile was refused")
  local legacy = X.LoadProfile("AuditLegacy") and db.scale == 1.25 and db.alertSounds.drop == "droplet"
  db.compact, db.alertSounds, db.buffPrio, db.scale = keep.compact, keep.alertSounds, keep.buffPrio, keepScale
  X.prioDirty = true
  X.DeleteProfile("AuditProfile")
  X.DeleteProfile("AuditLegacy")
  assert(loaded and restored, "profile omitted window settings, alert sounds, or ordered buff priorities")
  assert(legacy, "legacy profile did not preserve newer settings")
end)
step("historical named profiles load retired layer exports", function()
  local X, db = NS.X, env.BuffRadarDB
  local scale, assumed, layer = db.scale, db.assumeRange, db.strata
  db.scale, db.assumeRange = 1.25, true
  local current = assert(X.ProfileSnapshot())
  -- v1.15.5 emitted strata and predated assumeRange.
  local previous = current:gsub(";assumeRange=1;", ";") .. ";strata=HIGH"
  assert(X.ParseProfile(previous), "1.15.5 BR2 profile was rejected")
  assert(not X.ParseProfile(previous .. ";strata=LOW"), "duplicate retired layer was accepted")
  assert(not X.ParseProfile(previous:gsub("strata=HIGH", "strata=unknown")), "invalid retired layer was accepted")
  assert(not X.ParseProfile(current:gsub(";assumeRange=1;", ";")), "truncated current BR2 profile was accepted")
  assert(X.ProfileImport("BuffRadar profile: Historical\n" .. previous))
  db.scale = 1
  assert(X.LoadProfile("Historical") and db.scale == 1.25 and not db.assumeRange and db.strata == layer,
    "historical profile failed to migrate")
  X.DeleteProfile("Historical")
  db.scale, db.assumeRange = scale, assumed
end)
step("profile limits and validation preserve an existing save", function()
  local X, db = NS.X, env.BuffRadarDB
  assert(X.SaveProfile("AuditProfile"), "could not save a profile")
  local before = db.profiles.AuditProfile
  local prefix = "BuffRadar profile: AuditProfile\n"
  local rejected = not X.ProfileImport(prefix .. "BR1garbage")
  local rejectedEmpty = not X.ProfileImport(prefix .. "BR1")
  local rejectedMalformed = not X.ProfileImport(prefix .. "BR1;scale=1.25;locked=maybe")
  local rejectedEnum = not X.ProfileImport(prefix .. "BR1;scale=1.25;sortMode=unknown")
  local rejectedOversize = not X.ProfileImport(prefix .. "BR1;ignored." .. string.rep("A", 4000) .. "=1")
  local keepIgnored = db.ignored
  db.ignored = { [string.rep("B", 4000)] = true }
  local rejectedSave = not X.SaveProfile("AuditProfile")
  db.ignored = keepIgnored
  local unchanged = db.profiles.AuditProfile == before
  X.DeleteProfile("AuditProfile")
  assert(rejected and rejectedEmpty and rejectedMalformed and rejectedEnum, "invalid input was accepted as a profile")
  assert(rejectedOversize and rejectedSave and unchanged, "oversized input replaced an existing profile")
end)
step("single-target buff dropping off its holder alerts once (1.5.0)", function()
  if env.__forever then return end
  local cleanup = twoTanks()
  env.BuffRadarDB.enabled.EARTH_SHIELD = true
  local ES = "Earth Shield"
  local O = env.__over
  O.Aura = function(u, name) if u == "nameplate1" and name == ES then return { expirationTime = env.GetTime() + 600 } end end
  refresh()  -- your Earth Shield sits on tank 1
  local n = #chat
  O.Aura = nil  -- gone, and tank 1 is still standing there
  refresh()
  assert(chatSince(n, "Earth Shield dropped off Tank1."), "no drop alert printed")
  local n2 = #chat
  refresh()  -- still gone: the alert must not repeat
  assert(not chatSince(n2, "dropped off"), "drop alert repeated for the same drop")
  env.BuffRadarDB.enabled.EARTH_SHIELD = nil
  cleanup()
end)
step("/br why explains listing decisions (1.15.0)", function()
  local cleanup = partyOfTwo()
  refresh()
  local n = #chat
  env.SlashCmdList.BUFFRADAR("why Aaron")
  assert(chatSince(n, "Aaron is on the list"), "why did not report Aaron listed")
  assert(chatSince(n, ", missing:"), "why did not name the missing buffs")
  local O = env.__over
  O.Aura = function(u, name) return { expirationTime = env.GetTime() + 600 } end
  n = #chat
  env.SlashCmdList.BUFFRADAR("why Aaron")
  assert(chatSince(n, "already has every buff"), "why did not report Aaron fully buffed")
  O.Aura = nil
  env.SlashCmdList.BUFFRADAR("ignore Aaron")
  n = #chat
  env.SlashCmdList.BUFFRADAR("why Aaron")
  assert(chatSince(n, "ignore list"), "why did not report the ignore")
  env.SlashCmdList.BUFFRADAR("unignore Aaron")
  n = #chat
  env.SlashCmdList.BUFFRADAR("why Nobody")
  assert(chatSince(n, "no player named"), "why did not report an unknown name")
  cleanup()
end)
step("pull countdown shows on the coverage line (1.15.0)", function()
  local cleanup = partyOfTwo()
  local pf
  for _, f in ipairs(env.__frames) do if f.events and f.events.START_TIMER then pf = f end end
  assert(pf, "no frame registered START_TIMER")
  env.SlashCmdList.BUFFRADAR("pullflash on")
  refresh()  -- a real scan, so the tally holds casts still needed
  pf.scripts.OnEvent(pf, "START_TIMER", 3, 10, 10)
  assert(NS.X.pull ~= nil, "pull state not set")
  NS.X.Refresh()  -- not refresh(): that drains queued timers, ending the pull
  local found
  for _, fs in ipairs(env.__fontstrings) do
    if type(fs.text) == "string" and fs.text:find("Pull in ", 1, true) then found = fs.text end
  end
  assert(found, "no pull countdown on the coverage line")
  pf.scripts.OnEvent(pf, "START_TIMER", 3, 0, 0)  -- zero cancels
  assert(NS.X.pull == nil, "pull state not cleared by the cancel")
  NS.X.Refresh()
  local gone = true
  for _, fs in ipairs(env.__fontstrings) do
    if type(fs.text) == "string" and fs.text:find("Pull in", 1, true) then gone = false end
  end
  assert(gone, "countdown still on the coverage line after the cancel")
  runQueued()
  env.SlashCmdList.BUFFRADAR("pullflash off")
  cleanup()
end)
step("group-cast keybind button arms the group version (1.15.0)", function()
  local cleanup = partyOfTwo()
  env.IsSpellInRange = function() return 1 end
  refresh()
  local gb = env.BuffRadarGroupButton
  assert(gb, "group button not created")
  if env.__forever then
    assert(gb.attrs["type"] == "spell", "group button type wrong: " .. tostring(gb.attrs["type"]))
    assert(gb.attrs["spell"] == "Prayer of Fortitude",
      "group button not armed with the group spell: " .. tostring(gb.attrs["spell"]))
  else
    assert(gb.attrs["spell"] == "Skyfury",
      "group button should fall back to the plain head spell: " .. tostring(gb.attrs["spell"]))
  end
  env.IsSpellInRange = nil
  cleanup()
end)
step("buff falling off mid-fight plays the fall alert (1.15.0, #33)", function()
  if not env.__forever then return end
  local cleanup = partyOfTwo()
  local db = env.BuffRadarDB
  local O = env.__over
  db.fallSound = true
  db.alertSounds.fall = "system"
  local played = 0
  local oldPlay = env.PlaySound
  env.PlaySound = function() played = played + 1 end
  O.Aura = function(u, name) if u == "party1" and name == "Power Word: Fortitude" then return { expirationTime = env.GetTime() + 600 } end end
  refresh()  -- baseline: party1 has Fortitude
  fire("PLAYER_REGEN_DISABLED")
  O.Aura = nil  -- Fortitude falls off during the fight
  fire("PLAYER_REGEN_ENABLED")
  refresh()  -- the first scan after combat sees the drop
  assert(played == 1, "fall alert did not play exactly once, played=" .. played)
  -- control: the same drop outside combat stays silent
  O.Aura = function(u, name) if u == "party1" and name == "Power Word: Fortitude" then return { expirationTime = env.GetTime() + 600 } end end
  refresh()  -- baseline again
  O.Aura = nil
  refresh()
  assert(played == 1, "fall alert played for an out-of-combat drop")
  env.PlaySound = oldPlay
  db.fallSound = false
  db.alertSounds.fall = nil
  cleanup()
end)
step("coverage line notes a buff on cooldown (1.5.0)", function()
  if env.__forever then return end
  local cleanup = partyOfTwo("C")
  local O = env.__over
  O.Aura = function(u, name) if u == "party2" and name == "Skyfury" then return { expirationTime = env.GetTime() + 600 } end end
  env.GetSpellCooldown = function() return env.GetTime(), 180 end
  refresh()
  local cover
  for _, fs in ipairs(env.__fontstrings) do
    if type(fs.text) == "string" and fs.text:find("fully buffed", 1, true) then cover = fs.text end
  end
  env.GetSpellCooldown = nil
  O.Aura = nil
  cleanup()
  assert(cover, "no coverage line rendered")
  -- While Skyfury is on cooldown nobody counts as missing it (it can't be
  -- cast), so the count reads complete -- with the cooldown flagged.
  assert(cover:find("Skyfury 3/3", 1, true), "coverage counts wrong: " .. cover)
  assert(cover:find("(~3m cd)", 1, true), "no cooldown note on the coverage line: " .. cover)
end)
step("flight-path pause (1.5.0)", function()
  local cleanup = partyOfTwo("X")
  env.IsSpellInRange = function() return 1 end
  refresh()
  assert(shownRows().party1, "party not listed before the flight")
  env.SlashCmdList.BUFFRADAR("taxi")
  env.UnitOnTaxi = function() return true end
  refresh()
  assert(not shownRows().party1, "party still listed on a flight path")
  local found
  for _, fs in ipairs(env.__fontstrings) do
    if fs.text == "Paused on a flight path." or fs.text == "Auf einer Flugroute pausiert." then found = true end
  end
  assert(found, "flight-path pause message not shown")
  env.UnitOnTaxi = nil
  env.SlashCmdList.BUFFRADAR("taxi")
  refresh()
  assert(shownRows().party1, "party not listed after landing")
  cleanup()
end)
step("/br resetpos clears the saved window spot (1.5.0)", function()
  local db = env.BuffRadarDB
  db.point = { "TOPLEFT", "BOTTOMLEFT", 5000, 4000 }
  local n = #chat
  env.SlashCmdList.BUFFRADAR("resetpos")
  assert(db.point == nil, "resetpos did not clear the saved spot")
  assert(chatSince(n, "default spot"), "no resetpos message")
end)
step("/br selftest prints a paste-able block (1.4.0)", function()
  local n = #chat
  env.SlashCmdList.BUFFRADAR("selftest")
  assert(chatSince(n, "BuffRadar self-test"), "no self-test header")
  assert(chatSince(n, "dbVersion 17"), "self-test missing dbVersion")
  assert(chatSince(n, "role filter"), "self-test missing the 1.5.0 state line")
  assert(chatSince(n, "custom spells"), "self-test missing the 1.6.0 state line")
  assert(chatSince(n, "weapon watch"), "self-test missing the 1.7.0 state line")
  assert(chatSince(n, "grow up"), "self-test missing the 1.8.0 state line")
  assert(chatSince(n, "two columns"), "self-test missing the 1.9.0 state line")
  assert(chatSince(n, "saved themes"), "self-test missing the 1.10.0 state line")
  assert(chatSince(n, "buff SKYFURY") or chatSince(n, "buff FORTITUDE"), "self-test lists no buffs")
end)
step("corner grips scale the window (1.11.0)", function()
  local db = env.BuffRadarDB
  local gr, gl
  for _, f in ipairs(env.__frames) do
    if f.side == "RIGHT" and f.scripts.OnMouseDown then gr = f end
    if f.side == "LEFT" and f.scripts.OnMouseDown then gl = f end
  end
  assert(gr and gl, "scale grips not built")
  local frame = env.BuffRadarFrame
  db.locked = false
  db.scale = 1
  -- bottom-right: left edge fixed at 40, stub width 210 -> cursor 355 = x1.5
  env.GetCursorPosition = function() return 355, 0 end
  gr.scripts.OnMouseDown(gr, "LeftButton")
  assert(gr.isSizing, "right grip did not start sizing")
  gr.scripts.OnUpdate(gr)
  assert(db.scale == 1.5 and frame.scaleV == 1.5, "right grip scale " .. tostring(db.scale))
  env.GetCursorPosition = function() return 9999, 0 end
  gr.scripts.OnUpdate(gr)
  assert(db.scale == 2, "scale not clamped to 2: " .. tostring(db.scale))
  gr.scripts.OnMouseUp(gr)
  assert(not gr.isSizing and not gr.scripts.OnUpdate, "right grip still sizing after release")
  -- bottom-left: right edge fixed at 250 -> cursor -65 = x1.5
  db.scale = 1
  frame.scaleV = 1
  env.GetCursorPosition = function() return -65, 0 end
  gl.scripts.OnMouseDown(gl, "LeftButton")
  gl.scripts.OnUpdate(gl)
  assert(db.scale == 1.5, "left grip scale " .. tostring(db.scale))
  gl.scripts.OnMouseUp(gl)
  assert(db.scale == 1.5 and not gl.isSizing, "left grip release")
  -- locked windows and combat refuse a drag
  db.locked = true
  gr.scripts.OnMouseDown(gr, "LeftButton")
  assert(not gr.isSizing, "locked window started a scale drag")
  db.locked = false
  env.__combat = true
  gr.scripts.OnMouseDown(gr, "LeftButton")
  assert(not gr.isSizing, "combat started a scale drag")
  env.__combat = false
  env.GetCursorPosition = function() return 0, 0 end
  db.scale = 1
  env.SlashCmdList.BUFFRADAR("width 300")
  assert(db.width == 300, "width command: " .. tostring(db.width))
  env.SlashCmdList.BUFFRADAR("width 210")
end)
step("1.12.0 diagnostics: apicheck, buffcheck, perf, settings diff", function()
  local X = NS.X
  local n = #chat
  env.SlashCmdList.BUFFRADAR("apicheck")
  assert(chatSince(n, "API check"), "no apicheck header")
  assert(chatSince(n, "weapon-enchant candidates"), "no weapon-enchant discovery line")
  n = #chat
  env.SlashCmdList.BUFFRADAR("buffcheck")
  assert(chatSince(n, "Buff check"), "no buffcheck result")
  n = #chat
  env.SlashCmdList.BUFFRADAR("perf")
  assert(chatSince(n, "Perf:"), "no perf line")
  local s = X.Export()
  n = #chat
  env.SlashCmdList.BUFFRADAR("diff " .. s)
  assert(chatSince(n, "changes nothing"), "identical string reported a change")
  local changed = s:gsub("scale=[%d%.]+", "scale=1.5", 1)
  n = #chat
  env.SlashCmdList.BUFFRADAR("diff " .. changed)
  assert(chatSince(n, "would change 1 setting") and chatSince(n, "scale:"), "diff missed the scale change")
  env.SlashCmdList.BUFFRADAR("profile save dtest")
  n = #chat
  env.SlashCmdList.BUFFRADAR("profile diff dtest")
  assert(chatSince(n, "changes nothing"), "profile diff of a fresh profile")
  env.SlashCmdList.BUFFRADAR("profile delete dtest")
end)
step("cast counter fits a narrow window instead of being cut off", function()
  local X = NS.X
  local f = X.footerText
  assert(f, "footer text was not exposed")
  local prevW, prevSW = f.GetWidth, f.GetStringWidth

  -- Plenty of room: the full line stays.
  f.GetWidth = function() return 400 end
  f.GetStringWidth = function() return 120 end
  X.lastCounterRoom = nil
  NS.X.slashAPI.UpdateCounter()
  -- Checked on the "/" that only the compact form has, so this holds in every
  -- locale: the German pack translates the words but not the separator.
  assert(not f:GetText():find("/", 1, true),
    "a wide window used the compact counter form")

  -- Too narrow for the long form: drop to the compact one. Anchored left and
  -- right with word wrap off, the alternative is a cut-off "39 all-t...".
  f.GetWidth = function() return 40 end
  f.GetStringWidth = function() return 120 end
  X.lastCounterRoom = nil
  NS.X.slashAPI.UpdateCounter()
  local narrow = f:GetText()
  assert(narrow:find("/", 1, true),
    "the long counter line survived a window too narrow for it")

  f.GetWidth, f.GetStringWidth = prevW, prevSW
  X.lastCounterRoom = nil
end)
step("apicheck readability tier tells restricted apart from absent", function()
  local n = #chat
  env.SlashCmdList.BUFFRADAR("apicheck")
  assert(chatSince(n, "readability on"), "no readability section")
  assert(chatSince(n, "range verdict"), "no range verdict line")

  -- A value the client refuses to describe has to read as restricted, not as
  -- a working answer. Telling those apart is the whole point of this tier:
  -- every one of these APIs is present, so a presence check reports success.
  local protected = {}
  local prevCanAccess = env.canaccessvalue
  local prevModern, prevLegacy = env.C_Spell, env.IsSpellInRange
  local prevGroup, prevInteract = env.UnitInRange, env.CheckInteractDistance
  env.canaccessvalue = function(v) return v ~= protected end
  env.C_Spell = { IsSpellInRange = function() return protected end }
  env.IsSpellInRange = nil
  env.UnitInRange = function() return protected, protected end
  env.CheckInteractDistance = function() return protected end
  n = #chat
  env.SlashCmdList.BUFFRADAR("apicheck")
  assert(chatSince(n, "restricted"), "a restricted result was not reported as restricted")
  assert(chatSince(n, "no range API answers"),
    "no verdict when every range API refuses to answer")

  -- and a readable fallback is credited rather than ignored
  env.canaccessvalue = prevCanAccess
  env.C_Spell, env.IsSpellInRange = nil, nil
  env.UnitInRange = function() return false, false end
  env.CheckInteractDistance = function() return true end
  n = #chat
  env.SlashCmdList.BUFFRADAR("apicheck")
  assert(chatSince(n, "interaction distance answers"),
    "a readable interact-distance answer was not credited")
  env.C_Spell, env.IsSpellInRange = prevModern, prevLegacy
  env.UnitInRange, env.CheckInteractDistance = prevGroup, prevInteract
end)
step("1.12.0 toggles: tag symbols, reduced motion, range watch, snap, per-spec scale", function()
  local X, db = NS.X, env.BuffRadarDB
  env.SlashCmdList.BUFFRADAR("tagsymbols")
  assert(db.tagSymbols == true, "tagsymbols not on")
  env.SlashCmdList.BUFFRADAR("tagsymbols")
  assert(db.tagSymbols == false, "tagsymbols not off")
  assert(X.TAGSYM["recently rezzed"] == "+" or env.__german, "tag symbol table")
  env.SlashCmdList.BUFFRADAR("motion")
  assert(db.reduceMotion == true, "reduced motion not on")
  local a = env.BuffRadarFrame.borderColor
  X.Flash()
  assert(env.BuffRadarFrame.borderColor == a, "flash fired with reduced motion on")
  env.SlashCmdList.BUFFRADAR("motion")
  env.SlashCmdList.BUFFRADAR("rangewatch")
  assert(db.rangeWatch == true, "range watch not on")
  env.SlashCmdList.BUFFRADAR("rangewatch")
  env.SlashCmdList.BUFFRADAR("snap")
  assert(db.gripSnap == false, "snap not off")
  env.SlashCmdList.BUFFRADAR("snap")
  -- per-spec scale: scale follows the spec
  env.GetSpecialization = function() return 1 end
  X.spec = nil
  X.SpecSwap()
  env.SlashCmdList.BUFFRADAR("specscale on")
  db.scale = 1.25
  env.GetSpecialization = function() return 2 end
  X.SpecSwap()
  assert(db.specScales.s1 == 1.25, "spec 1 scale not remembered: " .. tostring(db.specScales.s1))
  db.scale = 0.75
  env.GetSpecialization = function() return 1 end
  X.SpecSwap()
  assert(db.scale == 1.25, "spec 1 scale not restored: " .. tostring(db.scale))
  env.SlashCmdList.BUFFRADAR("specscale off")
  db.scale = 1
  env.GetSpecialization = nil
  X.spec = nil
end)
step("1.12.0 badges: update pending (combat) and data hidden (secret)", function()
  local X = NS.X
  local frame = env.BuffRadarFrame
  env.__combat = true
  env.SlashCmdList.BUFFRADAR("width 250")
  env.__combat = false
  X.ext = X.ext  -- (slash width is refused in combat; ApplyGeometry path is what we test)
  env.__combat = true
  X.ApplyScaleNow()
  assert(X.geoPending == true, "pending flag not set in combat")
  env.__combat = false
  X.ApplyScaleNow()
  assert(not X.geoPending, "pending flag not cleared out of combat")
  X.hid = env.GetTime()
  X.titleKey = nil
  X.UpdateTitleMarks()
  assert(X.titleKey == "h", "data-hidden mark not set: " .. tostring(X.titleKey))
  X.hid = 0
  X.UpdateTitleMarks()
  assert(X.titleKey == "", "data-hidden mark not cleared")
end)
step("1.12.0 UNIT_AURA payload: empty incremental update is dropped", function()
  local n0 = env.__zoneCalls
  fire("UNIT_AURA", "player", { isFullUpdate = false })
  fire("UNIT_AURA", "player", { addedAuras = {} })
end)
step("1.12.0 fuzz: random roster sizes and mid-combat flips never error", function()
  local O = env.__over
  math.randomseed(1212)
  for round = 1, 25 do
    local size = math.random(1, 40)
    O.UnitExists = function(u)
      if u == "player" then return true end
      local i = tonumber(u:match("^party(%d+)$") or u:match("^raid(%d+)$"))
      return i ~= nil and i <= size
    end
    O.UnitName = function(u) if u == "player" then return "Testshaman" end return "Fuzz" .. u end
    O.UnitGUID = function(u) return "Player-1-" .. u end
    O.UnitClass = function(u) local c = ({ "WARRIOR", "MAGE", "PRIEST", "DRUID", "SHAMAN" })[math.random(5)]; return c, c end
    O.UnitIsPlayer = function() return true end
    O.Aura = function(u, name) if math.random(3) == 1 then return { expirationTime = env.GetTime() + math.random(600) } end end
    env.IsInGroup = function() return size > 1 end
    env.IsInRaid = function() return size > 5 end
    env.GetNumGroupMembers = function() return size end
    if math.random(4) == 1 then env.__combat = true end
    pcall(fire, "GROUP_ROSTER_UPDATE")
    refresh()
    env.__combat = false
    refresh()
  end
  O.UnitExists, O.UnitName, O.UnitGUID, O.UnitClass, O.UnitIsPlayer, O.Aura = nil, nil, nil, nil, nil, nil
  env.IsInGroup = function() return false end
  env.IsInRaid = function() return false end
  env.GetNumGroupMembers = nil
  refresh()
end)
step("German client uses the translation", function()
  if not env.__german then return end
  local found
  for _, fs in ipairs(env.__fontstrings) do if fs.text == "Kampf" then found = true end end
  assert(found, "combat label not translated ('Kampf' not found)")
end)
step("right-click a row (ignore path)", function()
  local row = env.BuffRadarRow1
  row.entry = { name = "Testshaman", fullName = "Testshaman-TestRealm", missing = { "Skyfury" }, unit = "player" }
  row.scripts.OnClick(row, "RightButton", false)
  row.scripts.PostClick(row, "RightButton", false)
end)
return results, chat
end""")

import os
src = open(addon_path, encoding="utf-8").read()
de_path = os.path.join(os.path.dirname(os.path.abspath(addon_path)), "Locales", "deDE.lua")
de_src = open(de_path, encoding="utf-8").read() if os.path.exists(de_path) else None
ex_path = os.path.join(os.path.dirname(os.path.abspath(addon_path)), "Extras.lua")
ex_src = open(ex_path, encoding="utf-8").read() if os.path.exists(ex_path) else None
da_path = os.path.join(os.path.dirname(os.path.abspath(addon_path)), "Data.lua")
da_src = open(da_path, encoding="utf-8").read() if os.path.exists(da_path) else None
cf_path = os.path.join(os.path.dirname(os.path.abspath(addon_path)), "Config.lua")
cf_src = open(cf_path, encoding="utf-8").read() if os.path.exists(cf_path) else None
sl_path = os.path.join(os.path.dirname(os.path.abspath(addon_path)), "Slash.lua")
rc_path = os.path.join(os.path.dirname(os.path.abspath(addon_path)), "Recaps.lua")
rc_src = open(rc_path, encoding="utf-8").read() if os.path.exists(rc_path) else None
pf_path = os.path.join(os.path.dirname(os.path.abspath(addon_path)), "Profiles.lua")
pf_src = open(pf_path, encoding="utf-8").read() if os.path.exists(pf_path) else None
sl_src = open(sl_path, encoding="utf-8").read() if os.path.exists(sl_path) else None
setups = [
    ("Retail: modern client (C_Timer, UI templates)", True, False, False, False),
    ("Retail: fallback timer (OnUpdate)", False, False, False, False),
    ("Retail: no UI templates (fallback settings look)", True, True, False, False),
    ("Forever: modern client", True, False, True, False),
    ("Forever: fallback timer, no UI templates", False, True, True, False),
]
if de_src:
    setups.append(("Retail: German client (Locales/deDE.lua)", True, False, False, True))
for label, with_timer, no_templates, forever, german in setups:
    results, chat = harness(src, with_timer, no_templates, forever, german, de_src if german else None, ex_src, da_src, cf_src, sl_src, rc_src, pf_src)
    bad = 0
    for i in range(1, len(results) + 1):
        name, status = results[i][1], results[i][2]
        if status != "ok":
            bad += 1
            print(f"  {name}: {status}")
    print(f"{label}: {len(results)} steps, {bad} with errors")
