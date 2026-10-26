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

harness = lua.eval(r"""function(addonSrc, withTimer, noTemplates, forever, german, localeSrc)
local chat = {}
local env = WOWSTUB(chat, withTimer, noTemplates, forever, german)
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
step("load file (main chunk)", function() chunk("BuffRadar", {}) end)

local driver
for _, f in ipairs(env.__frames) do
  if f.events and f.events.ADDON_LOADED then driver = f end
end
step("find event frame", function() assert(driver, "no frame registered ADDON_LOADED") end)
if not driver then return results, chat end
local fire = function(ev, ...) driver.scripts.OnEvent(driver, ev, ...) end
step("ADDON_LOADED", function() fire("ADDON_LOADED", "BuffRadar") end)
step("PLAYER_LOGIN", function() fire("PLAYER_LOGIN") end)
step("window exists", function() assert(env.BuffRadarFrame, "BuffRadarFrame not created") end)
step("minimap button exists", function() assert(env.BuffRadarMinimapButton, "no minimap button") end)
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
step("out-of-range rows: marker shown, and class color back when in range", function()
  local cleanup = twoTanks()
  refresh()
  local r = shownRows()
  local row = assert(r.nameplate1, "tank 1 not listed").row
  assert(row.far and row.far.shown, "no 'out of range' marker on a greyed row")
  assert(row.name.color and row.name.color[1] < 0.6, "out-of-range name not greyed")
  env.IsSpellInRange = function() return 1 end   -- now in range
  refresh()
  row = assert(shownRows().nameplate1, "tank 1 not listed in range").row
  assert(not row.far.shown, "'out of range' marker still shown in range")
  assert(row.name.color and row.name.color[1] > 0.9, "name still grey after coming into range")
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
  assert(d.dbVersion == 11, "dbVersion not migrated to 11: " .. tostring(d.dbVersion))
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
  assert(type(d) == "table" and d.dbVersion == 11 and d.scale == 1,
    "corrupt save not replaced with defaults")
  d.scale = 1
  -- a 1.7.0-era save (dbVersion 9): an existing user — the wizard
  -- counts as already seen, so no first-run hint nags them (1.9.0)
  env.BuffRadarDB = { dbVersion = 9 }
  fire("ADDON_LOADED", "BuffRadar")
  d = env.BuffRadarDB
  assert(d.dbVersion == 11 and d.wizardSeen == true,
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
  assert(db.sortMode == "role" and db.groupCast == true and db.showOutOfRange == true,
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

step("hide in combat steps aside for the fight (1.8.0)", function()
  local db = env.BuffRadarDB
  env.SlashCmdList.BUFFRADAR("combat")
  assert(db.hideInCombat == true, "hideInCombat setting not stored")
  local frame = env.BuffRadarFrame
  frame:Show()
  fire("PLAYER_REGEN_DISABLED")
  assert(not frame:IsShown(), "window still shown after combat started")
  fire("PLAYER_REGEN_ENABLED")
  timerTick()
  env.SlashCmdList.BUFFRADAR("combat")
  assert(db.hideInCombat == false, "hideInCombat not toggled off")
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
  local O = env.__over
  env.IsSpellInRange = function() return 1 end
  env.GetRaidTargetIndex = function(u) if u == "party1" then return 3 end end
  env.SlashCmdList.BUFFRADAR("markers")
  refresh()
  local row = shownRows().party1 and shownRows().party1.row
  assert(row, "Aaron not listed")
  assert(row.marker and row.marker.shown, "raid marker badge not shown")
  env.SlashCmdList.BUFFRADAR("markers")
  refresh()
  assert(not row.marker.shown, "raid marker stayed after the setting went off")
  env.GetRaidTargetIndex = nil
  cleanup()
end)

step("range band text calls a near player near (1.8.0)", function()
  local cleanup = partyOfTwo("R")
  local O = env.__over
  env.IsSpellInRange = function(_, u) if u == "party2" then return 0 end return 1 end
  env.UnitInRange = function(u) if u == "party2" then return true, true end end
  env.SlashCmdList.BUFFRADAR("range")
  refresh()
  local row = shownRows().party2 and shownRows().party2.row
  assert(row, "Zed not listed as a greyed row")
  assert(row.far.text == "near" or row.far.text == "in der Nähe",
    "greyed row does not read 'near': " .. tostring(row.far.text))
  env.SlashCmdList.BUFFRADAR("range")
  refresh()
  assert(row.far.text == "out of range" or row.far.text == "außer Reichweite",
    "greyed row label not restored: " .. tostring(row.far.text))
  env.UnitInRange = nil
  cleanup()
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
  env.SlashCmdList.BUFFRADAR("pets")
  refresh()
  assert(not shownRows().partypet1, "pet stayed after the setting went off")
  cleanup()
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

step("a single profile can be shared and imported (1.8.0)", function()
  local db = env.BuffRadarDB
  env.SlashCmdList.BUFFRADAR("profile save shareme")
  env.SlashCmdList.BUFFRADAR("profile share shareme")
  local text = env.BuffRadarExportFrame.editBox.text
  assert(type(text) == "string" and text:find("BuffRadar profile: shareme", 1, true),
    "share text has no header: " .. tostring(text))
  assert(text:find("\nBR1;", 1, true), "share text carries no settings string")
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
  env.SlashCmdList.BUFFRADAR("autoprofile dungeon clear")
  assert(db.autoProfile.dungeon == nil, "auto profile not cleared")
  env.SlashCmdList.BUFFRADAR("profile delete dset")
  env.SlashCmdList.BUFFRADAR("scale 1")
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
  assert(chatSince(n, "dbVersion 11"), "self-test missing dbVersion")
  assert(chatSince(n, "role filter"), "self-test missing the 1.5.0 state line")
  assert(chatSince(n, "custom spells"), "self-test missing the 1.6.0 state line")
  assert(chatSince(n, "weapon watch"), "self-test missing the 1.7.0 state line")
  assert(chatSince(n, "grow up"), "self-test missing the 1.8.0 state line")
  assert(chatSince(n, "two columns"), "self-test missing the 1.9.0 state line")
  assert(chatSince(n, "buff SKYFURY") or chatSince(n, "buff FORTITUDE"), "self-test lists no buffs")
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
    results, chat = harness(src, with_timer, no_templates, forever, german, de_src if german else None)
    bad = 0
    for i in range(1, len(results) + 1):
        name, status = results[i][1], results[i][2]
        if status != "ok":
            bad += 1
            print(f"  {name}: {status}")
    print(f"{label}: {len(results)} steps, {bad} with errors")
