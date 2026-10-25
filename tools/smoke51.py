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
  "taxi", "taxi", "watch", "watch", "profile", "profile list", "profile save", "resetpos" }
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
  assert(d.dbVersion == 8, "dbVersion not migrated to 8: " .. tostring(d.dbVersion))
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
  assert(type(d) == "table" and d.dbVersion == 8 and d.scale == 1,
    "corrupt save not replaced with defaults")
  d.scale = 1
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
  assert(chatSince(n, "dbVersion 8"), "self-test missing dbVersion")
  assert(chatSince(n, "role filter"), "self-test missing the 1.5.0 state line")
  assert(chatSince(n, "custom spells"), "self-test missing the 1.6.0 state line")
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
