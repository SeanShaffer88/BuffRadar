"""Smoke-run BuffRadar.lua under real Lua 5.1 against a fake WoW API (wowstub.lua).

Loads the TOC entries in order, fires ADDON_LOADED and PLAYER_LOGIN, runs a refresh and a set
of slash commands, opens every settings tab and fires the controls' handlers.
Reports the first Lua error of each step plus anything the addon printed as
an error. Usage: python -I smoke51.py STUB.lua ADDON.lua
"""
import sys
sys.stdout.reconfigure(encoding="utf-8")
from pathlib import Path
from lupa import lua51

stub_path, addon_path = sys.argv[1], sys.argv[2]
lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.execute(open(stub_path, encoding="utf-8").read())
audit_tests = lua.execute(Path(__file__).with_name("audit51.lua").read_text(encoding="utf-8"))
support_tests = lua.execute(Path(__file__).with_name("support51.lua").read_text(encoding="utf-8"))
audit_tests = lua.eval("function(a,b) return function(...) a(...); b(...) end end")(audit_tests, support_tests)
for module in ("core-eight51.lua", "views-supplies51.lua", "ui-eight51.lua", "five-core51.lua", "five-ui51.lua"):
    path = Path(__file__).with_name(module)
    extra = lua.execute(path.read_text(encoding="utf-8"))
    audit_tests = lua.eval("function(a,b) return function(...) a(...); b(...) end end")(audit_tests, extra)

harness = lua.eval(r"""function(sources, withTimer, noTemplates, forever, german, auditTests)
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
local castDrivers = {}
local registerStateDriver = env.RegisterStateDriver
env.RegisterStateDriver = function(target, state, condition)
  if state ~= "visibility" then
    if state == "combat" then
      assert(condition == "[@player,dead][combat] combat; nocombat", "cast driver must stop on player death or combat")
      castDrivers[target] = true
    end
    return registerStateDriver(target, state, condition)
  end
  assert(condition == "[@player,dead][combat] hide", "visibility driver must hide on death without forcing a show on recovery")
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

local NS = {}
local initialGlobals = {}
for key in pairs(env) do initialGlobals[key] = true end
local addonGlobals = {
  BuffRadarDB = true, BuffRadarAPI = true,
  BuffRadar_ToggleWindow = true, BuffRadar_ToggleSound = true,
  BuffRadar_OpenActions = true,
  SLASH_BUFFRADAR1 = true, SLASH_BUFFRADAR2 = true,
  BINDING_HEADER_BUFFRADAR = true, BINDING_CATEGORY_BUFFRADAR = true,
  BINDING_NAME_BUFFRADAR_TOGGLE = true, BINDING_NAME_BUFFRADAR_MUTE = true,
  BINDING_NAME_BUFFRADAR_ACTIONS = true,
  ["BINDING_NAME_CLICK BuffRadarNextButton:LeftButton"] = true,
  ["BINDING_NAME_CLICK BuffRadarGroupButton:LeftButton"] = true,
}
local function CheckGlobals()
  local frames = {}
  for _, f in ipairs(env.__frames) do
    local name = f:GetName()
    if name then frames[name] = f end
  end
  for key, value in pairs(env) do
    assert(initialGlobals[key] or addonGlobals[key] or frames[key] == value, "unexpected global: " .. tostring(key))
  end
end

local function LoadFile(file, client, ns)
  local chunk = assert(loadstring(file[2], "@" .. file[1]))
  setfenv(chunk, client)
  chunk("BuffRadar", ns)
end
for _, file in ipairs(sources) do
  step("load " .. file[1], function() LoadFile(file, env, NS) end)
end
step("TOC modules initialize in the private namespace", function()
  CheckGlobals()
  local X = NS.X
  assert(X and X.BUFF_DEFS and X.BLESSINGS and X.Settings and X.BuildUI and X.BuildMinimapButton,
    "data, settings, window or minimap module missing")
  assert(X.InitSync and X.OnAddonMsg and X.OnRoster and X.WizardPage and X.RefreshConfig
    and X.OpenConfig and env.SlashCmdList.BUFFRADAR and X.OnOff and X.DeathRecap and X.WipeCheck
    and X.Export and X.Import and X.ApplyPreset, "feature module did not publish its entry points")
  assert(NS.Locales and NS.Locales.deDE, "locale pack did not stay in the addon namespace")
end)
step("SavedVariables are not opened by module loading or profile validation", function()
  local X = NS.X
  assert(X.GetDB() == nil and env.BuffRadarDB == nil, "settings loaded before ADDON_LOADED")
  local first, second = X.Settings.Sanitize({}), X.Settings.Sanitize({})
  first.enabled.TEST = true
  first.bgColor[1] = 1
  assert(not second.enabled.TEST and second.bgColor[1] == 0.04, "clean settings share defaults by reference")
  assert(X.GetDB() == nil and env.BuffRadarDB == nil, "sanitizing a candidate published it")
end)

local driver
for _, f in ipairs(env.__frames) do
  -- the FIRST frame that registered ADDON_LOADED is the addon's event
  -- driver (Extras.lua adds small listener frames of its own later)
  if f.events and f.events.ADDON_LOADED then driver = f; break end
end
step("find event frame", function() assert(driver, "no frame registered ADDON_LOADED") end)
if not driver then return results, chat end
local function TestClient()
  local messages = {}
  local client = WOWSTUB(messages, withTimer, noTemplates, forever, german)
  client._G = client
  return setmetatable(client, { __index = std }), messages
end
local function LoadClient(client)
  local ns = {}
  for _, file in ipairs(sources) do LoadFile(file, client, ns) end
  for _, f in ipairs(client.__frames) do
    if f.events and f.events.PLAYER_LOGIN and f.events.ADDON_LOADED then return ns.X, f end
  end
  error("login driver did not register both events")
end
step("login fallback sanitizes without migrating and later loads replace the live save", function()
  local client = TestClient()
  local saved = { dbVersion = 9, scale = 9, castMethod = "rank", showOutOfRange = true,
                  showMinimap = false, ignored = { BeforeLogin = true }, obsolete = true }
  client.BuffRadarDB = saved
  local X, startup = LoadClient(client)
  local onEvent = startup.scripts.OnEvent
  onEvent(startup, "ADDON_LOADED", "OtherAddon")
  assert(not X.GetDB() and saved.obsolete and saved.scale == 9, "settings changed before BuffRadar loaded")
  onEvent(startup, "PLAYER_LOGIN")
  assert(not startup.events.PLAYER_LOGIN and client.BuffRadarFrame, "login fallback did not build the window once")
  assert(X.GetDB() ~= saved and saved.obsolete and saved.scale == 9, "fallback modified the input save")
  saved = X.GetDB()
  assert(saved == client.BuffRadarDB and saved.scale == 2 and not saved.obsolete, "fallback did not publish sanitized state")
  assert(saved.dbVersion == 9 and not saved.wizardSeen and saved.showOutOfRange and saved.castMethod == "rank",
    "login fallback applied normal-load migrations")
  assert(X.Ignore.Has("BeforeLogin", "BeforeLogin"), "fallback did not rebuild the ignore index")
  local minimap = client.BuffRadarMinimapButton
  assert(minimap and not minimap:IsShown(), "minimap did not receive fallback settings")

  local replacement = { dbVersion = 9, scale = 1.5, showMinimap = true }
  client.BuffRadarDB = replacement
  onEvent(startup, "ADDON_LOADED", "BuffRadar")
  assert(replacement.dbVersion == 9 and not replacement.wizardSeen, "migration edited the input table")
  assert(X.GetDB() == client.BuffRadarDB and X.GetDB().dbVersion == 25 and X.GetDB().wizardSeen,
    "normal load did not migrate and publish detached settings")
  assert(not X.Ignore.Has("BeforeLogin", "BeforeLogin"), "ignore index retained a replaced save")
  X.ApplyGeometry()
  X.RefreshMinimapButton()
  assert(client.BuffRadarFrame:GetScale() == 1.5 and minimap:IsShown(), "UI modules held onto replaced settings")
end)
local fire = function(ev, ...)
  driver.scripts.OnEvent(driver, ev, ...)
  if ev == "PLAYER_REGEN_DISABLED" or (ev == "PLAYER_DEAD" and env.__combat) then
    for target in pairs(visibilityDrivers) do target.shown = false end
    for target in pairs(castDrivers) do
      for _, attribute in ipairs({ "type", "spell", "unit", "macrotext", "shift-type1",
          "shift-spell1", "shift-unit1", "shift-macrotext1" }) do
        target.attrs[attribute] = nil
      end
    end
  end
end
step("ADDON_LOADED", function()
  fire("ADDON_LOADED", "BuffRadar")
  assert(NS.X.GetDB() == env.BuffRadarDB and env.BuffRadarDB.dbVersion == 25
    and env.BuffRadarDB.blessingComplement, "live settings or the complement default were not published")
  local pullFrame = NS.X.pullFrame
  if not NS.X.ApiCheck then return end -- not in the Retail TOC
  assert(pullFrame and pullFrame.events.ADDON_LOADED, "pull listener missing at startup")
  local before, registered = env.C_ChatInfo, {}
  env.C_ChatInfo = { RegisterAddonMessagePrefix = function(prefix) registered[#registered + 1] = prefix end }
  pullFrame.scripts.OnEvent(pullFrame, "ADDON_LOADED", "OtherAddon")
  assert(pullFrame.events.ADDON_LOADED and #registered == 0, "other addons triggered pull setup")
  pullFrame.scripts.OnEvent(pullFrame, "ADDON_LOADED", "BuffRadar")
  env.C_ChatInfo = before
  assert(not pullFrame.events.ADDON_LOADED, "pull listener stayed subscribed after setup")
  assert(#registered == 1 and registered[1] == "D5", "pull setup registered an unexpected prefix")
end)
step("PLAYER_LOGIN while dead starts with all buff surfaces hidden and disarmed", function()
  env.__over.UnitIsDeadOrGhost = function(u) return u == "player" end
  local db = env.BuffRadarDB
  local oldMinimap = db.showMinimap
  db.showMinimap = true
  fire("PLAYER_LOGIN")
  assert(not env.BuffRadarFrame:IsShown() and not env.BuffRadarPill:IsShown(), "dead login showed a buff surface")
  assert(not env.BuffRadarMinimapButton:IsShown() and db.showMinimap, "dead login changed minimap preference")
  assert(not env.BuffRadarNextButton:GetAttribute("type") and not env.BuffRadarGroupButton:GetAttribute("type"),
    "dead login armed a cast binding")
  env.__over.UnitIsDeadOrGhost = nil
  fire("PLAYER_ALIVE")
  assert(env.BuffRadarMinimapButton:IsShown(), "living player did not regain configured minimap button")
  db.showMinimap = oldMinimap
  NS.X.RefreshMinimapButton()
end)
step("startup creates only game entry points and named frames", CheckGlobals)
step("window exists", function() assert(env.BuffRadarFrame, "BuffRadarFrame not created") end)
step("minimap button exists", function() assert(env.BuffRadarMinimapButton, "no minimap button") end)
step("minimap button follows both axes after the map is resized", function()
  local map, button, db = env.Minimap, env.BuffRadarMinimapButton, env.BuffRadarDB
  local oldWidth, oldHeight, oldAngle, oldCursor = map.GetWidth, map.GetHeight, db.minimapAngle, env.GetCursorPosition
  map.GetWidth, map.GetHeight = function() return 240 end, function() return 160 end
  db.minimapAngle = 0
  NS.X.RefreshMinimapButton()
  local p = button.points[#button.points]
  local horizontal = #button.points == 1 and math.abs(p[4] - 125) < 0.01
  map.GetWidth, map.GetHeight = function() return 300 end, function() return 200 end
  local resized = map:GetScript("OnSizeChanged")
  if resized then resized(map, 300, 200) end
  p = button.points[#button.points]
  local followsSize = math.abs(p[4] - 155) < 0.01
  env.GetCursorPosition = function() return 655, 505 end
  assert(not button:GetScript("OnUpdate"), "idle minimap has a frame update")
  button:GetScript("OnDragStart")(button)
  assert(button.dragging and not button:GetScript("OnUpdate"), "minimap drag installed a frame update")
  button:GetScript("OnDragStop")(button)
  assert(not button.dragging and not button:GetScript("OnUpdate"), "minimap drag did not stop cleanly")
  button:GetScript("OnDragStart")(button)
  button:Hide()
  assert(not button.dragging and not button:GetScript("OnUpdate"), "minimap drag survived hide")
  local angle = db.minimapAngle
  map.GetWidth, map.GetHeight, db.minimapAngle, env.GetCursorPosition = oldWidth, oldHeight, oldAngle, oldCursor
  NS.X.RefreshMinimapButton()
  assert(horizontal and followsSize and math.abs(angle - 45) < 0.01, "minimap geometry ignored an axis or resize")
end)
step("friendly plate styles and restore only change verified, supported CVars", function()
  local X, db = NS.X, env.BuffRadarDB
  local style = X.friendlyPlateNamesCVar
  local vars = { nameplateShowFriendlyPlayers = "0", nameplateShowAll = "0", [style] = "0",
    nameplateShowEnemies = "1", nameplateShowSelf = "1" }
  local oldCVar, oldGet, oldBool, oldSet = env.C_CVar, env.GetCVar, env.GetCVarBool, env.SetCVar
  local oldRestore = db.plateRestore
  env.GetCVar, env.GetCVarBool, env.SetCVar = nil, function() return false end, nil
  db.plateRestore = {}
  local ok, err = pcall(function()
    local writes, refused = 0, "nameplateShowFriendlyPlayers"
    env.C_CVar = {
      GetCVar = function(key) return vars[key] end,
      SetCVar = function(key, value)
        writes = writes + 1
        if vars[key] and key ~= refused then vars[key] = value end
      end,
    }
    local slash = env.SlashCmdList.BUFFRADAR
    assert(X.FriendlyPlatesOn() == false and writes == 0, "reading nameplates changed settings")
    slash("plates")
    assert(writes == 1 and vars.nameplateShowAll == "0" and not next(db.plateRestore),
      "a refused write changed or recorded other settings")
    refused = nil
    slash("plates")
    assert(vars.nameplateShowFriendlyPlayers == "1" and vars.nameplateShowAll == "1", "enable skipped a setting")
    assert(db.plateRestore.nameplateShowFriendlyPlayers == false and db.plateRestore.nameplateShowAll == false,
      "the original off values were not saved")
    slash("plates names")
    assert(vars[style] == "1" and vars.nameplateShowFriendlyPlayers == "1", "names-only lost friendly plate discovery")
    assert(not assert(X.ProfileSnapshot()):find("plateRestore", 1, true)
      and not assert(X.Export()):find("plateRestore", 1, true), "local nameplate settings leaked into a shareable export")
    slash("plates bars")
    assert(vars[style] == "0" and db.plateRestore[style] == nil, "bars did not clear its pending change")
    slash("plates names")
    env.__combat = true
    local before = writes
    slash("plates restore")
    slash("plates off")
    assert(writes == before, "plate settings changed during combat")
    env.__combat = false
    refused = style
    slash("plates restore")
    assert(vars.nameplateShowAll == "0" and vars.nameplateShowFriendlyPlayers == "0" and vars[style] == "1"
      and db.plateRestore[style] == false, "partial restore did not preserve the refused setting for retry")
    refused = nil
    slash("plates restore")
    assert(vars[style] == "0" and not next(db.plateRestore), "restore retry did not finish")
    assert(vars.nameplateShowEnemies == "1" and vars.nameplateShowSelf == "1", "unrelated plates were changed")

    vars.nameplateShowFriendlyPlayers, vars.nameplateShowFriends, vars[style] = nil, "1", nil
    local legacy, name = X.FriendlyPlatesOn()
    assert(legacy and name == "nameplateShowFriends", "legacy nameplate CVar was not found")
    slash("plates off")
    assert(vars.nameplateShowFriends == "0" and db.plateRestore.nameplateShowFriends == true,
      "explicit off did not save the previously enabled state")
    slash("plates restore")
    assert(vars.nameplateShowFriends == "1", "restore did not reenable previously enabled nameplates")
    before = writes
    slash("plates names")
    vars.nameplateShowFriends = nil
    slash("plates off")
    assert(writes == before and X.FriendlyPlatesOn() == nil, "unsupported plate setting was written")
  end)
  env.C_CVar, env.GetCVar, env.GetCVarBool, env.SetCVar = oldCVar, oldGet, oldBool, oldSet
  db.plateRestore, env.__combat = oldRestore, false
  assert(ok, err)
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
end
step("refresh tick", timerTick)

-- Edition detection and edition-specific features.
local function chatSince(n, needle)
  for i = n + 1, #chat do if chat[i]:find(needle, 1, true) then return true end end
  return false
end
local function localizedMatch(text,key,...)
  local args={...}; for i=#args+1,12 do args[i]=987654321 end
  local rendered=string.format(NS.X.L[key],unpack(args))
  local pattern=rendered:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])","%%%1")
  pattern=pattern:gsub("987654321",".-")
  return text and text:find(pattern)~=nil
end
local function chatTemplate(n,key,...)
  for i=n+1,#chat do if localizedMatch(chat[i],key,...) then return true end end
  return false
end
step("edition detected", function()
  local n = #chat
  env.SlashCmdList.BUFFRADAR("debug")
  local want = env.__forever and "Forever" or "Retail"
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
    assert(chatSince(n, ("SHADOWGUARD  -  Shadowguard (you)  [|cff00ff00"..NS.X.L["On"].."|r]")),
      "Shadowguard missing from /br buffs or not on by default")
    assert(not chatSince(n, "SKYFURY"), "retail buff listed on Forever")
  else
    assert(chatSince(n, "SKYFURY") and chatSince(n, "SHAMAN_SHIELD"), "retail shaman buffs missing")
    assert(not chatSince(n, "INNER_FIRE") and not chatSince(n, "WATER_BREATHING")
      and not chatSince(n, "SHADOWGUARD"), "Forever buff listed on retail")
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
  for _, key in ipairs({ "look", "alerts", "buffs", "behavior", "data", "readiness" }) do
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
  assert(cfg.numTabs == 6, "PanelTemplates_SetNumTabs not called with 6")
  local keys = { "look", "alerts", "buffs", "behavior", "data", "readiness" }
  for i = 1, #keys do
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
    local isModePreference = f.preferenceKey == "simpleMode" or f.preferenceKey == "performanceMode"
    if f.scripts.OnClick and f ~= driver and not isBar and not isModePreference then
      f.scripts.OnClick(f, "LeftButton", false)
    end
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
    if f.scripts.OnClick and f.text == NS.X.L["Open BuffRadar settings"] then f.scripts.OnClick(f, "LeftButton"); opened = true end
  end
  assert(opened, "button not found")
  assert(env.BuffRadarConfig.shown, "settings window not shown")
  assert(not env.SettingsPanel.shown, "options panel still shown")
  -- clicking again must keep it open (forceShow), not toggle it closed
  for _, f in ipairs(env.__frames) do
    if f.scripts.OnClick and f.text == NS.X.L["Open BuffRadar settings"] then f.scripts.OnClick(f, "LeftButton") end
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
  if not NS.X.ApiCheck then return end -- optional Extras.lua
  local pf
  for _, f in ipairs(env.__frames) do if f.events and f.events.START_TIMER then pf = f end end
  assert(pf, "no frame registered START_TIMER")
  local firePull = function(...) pf.scripts.OnEvent(pf, ...) end
  firePull("CHAT_MSG_ADDON", "D5", "PT\t10", "RAID", "Nobody-Elsewhere")
  assert(NS.X.pullProbe.d5 == 1, "DBM PT message not counted by the probe")
  local diagnostic = NS.X.ApiCheck(false)
  assert(diagnostic:find("START_TIMER seen 0", 1, true) and diagnostic:find("DBM PT seen 1", 1, true),
    "D5-only pull activity was missing from diagnostics")
  NS.X.tally = { FORTITUDE = { total = 5, miss = 2 } }
  firePull("START_TIMER", 2, 10, 10)
  assert(NS.X.pullProbe.stSeen == 1, "START_TIMER not counted by the probe")
  assert(NS.X.pull == nil, "flash state set while pullflash is off")
  env.SlashCmdList.BUFFRADAR("pullflash on")
  firePull("START_TIMER", 2, 10, 10)
  assert(NS.X.pull ~= nil, "pull state not set with pullflash on and casts outstanding")
  local found
  for _, line in ipairs(chat) do if localizedMatch(line,"Pull in %ds (%s) -- %d casts still needed.",10,"countdown") then found = line end end
  assert(found, "no countdown line printed: " .. table.concat(chat, " | "))
  firePull("START_TIMER", 2, 0, 0)
  assert(NS.X.pull == nil, "zero timer did not cancel the pull state")
  firePull("CHAT_MSG_ADDON", "D5", "PT\t10", "RAID", "Nobody-Elsewhere")
  assert(NS.X.pullProbe.d5 == 2, "second DBM PT message not counted by the probe")
  assert(NS.X.pull == nil, "untrusted DBM pull started the flash")
  runQueued()  -- drain the pull countdown timers so later steps see a clean queue
  NS.X.tally = {}
  env.SlashCmdList.BUFFRADAR("pullflash off")
end)
step("changing a pull timer keeps its replacement until the replacement expires", function()
  if not NS.X.ApiCheck then return end -- optional Extras.lua
  if not env.__timers then return end
  runQueued()
  local X, db = NS.X, env.BuffRadarDB
  local oldTally, oldPull, oldFlash, oldTrusted = X.tally, X.pull, X.Flash, X.SenderTrusted
  local oldSender, oldRaid = X.SenderUnit, env.IsInRaid
  X.SenderUnit = function() return "player", "Leader-TestRealm" end
  local oldSetting = db.pullFlash
  local flashes = 0
  X.Flash = function() flashes = flashes + 1 end
  X.SenderTrusted = function(sender) return sender == "Leader-TestRealm" end
  X.tally, db.pullFlash = { FORTITUDE = { miss = 1 } }, true
  local pf = X.pullFrame
  pf.scripts.OnEvent(pf, "START_TIMER", 2, 8, 8)
  local timerA = X.pull
  env.IsInRaid = function() return true end  -- change scope before the new provider starts
  pf.scripts.OnEvent(pf, "CHAT_MSG_ADDON", "D5", "PT\t12", "RAID", "Leader-TestRealm")
  local timerB = X.pull
  pf.scripts.OnEvent(pf, "CANCEL_PLAYER_COUNTDOWN", "Player-Leader")
  assert(X.pull == timerB, "an older native cancellation cleared the replacement provider")
  local q = env.__timers
  env.__timers = {}
  local scheduled = timerA and timerB and timerA ~= timerB and timerB.source == "boss mod" and #q == 4
  local correct
  if scheduled then
    q[1]()
    q[2]()
    correct = X.pull == timerB and flashes == 2
    q[3]()
    correct = correct and X.pull == timerB and flashes == 3
    q[4]()
    correct = correct and X.pull == nil and flashes == 4
  end
  X.tally, X.pull, X.Flash, X.SenderTrusted, db.pullFlash = oldTally, oldPull, oldFlash, oldTrusted, oldSetting
  X.SenderUnit, env.IsInRaid = oldSender, oldRaid
  assert(scheduled and correct, "an outdated pull timer flashed or cleared the replacement")
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
  local db = env.BuffRadarDB
  local count = db.castsTotal
  row.entry = { missing = { "Power Word: Fortitude" }, guid = env.UnitGUID("player"), unit = "player" }
  row.bSpell = "Power Word: Fortitude"
  row.attrs["type"], row.attrs["spell"] = "spell", 1244
  row.attrs["shift-type1"], row.attrs["shift-spell1"] = nil, nil
  if NS.X.classic then
    row.attrs["shift-type1"], row.attrs["shift-spell1"] = "spell", 21562
    row.bGroupSpell = "Prayer of Fortitude"
  end
  env.IsShiftKeyDown = function() return true end
  local expected = NS.X.classic and 21562 or 1244
  row.scripts.PreClick(row, "LeftButton", false)
  fire("UNIT_SPELLCAST_SENT", "player", env.UnitName("player"), "cast-shift", expected)
  row.scripts.PostClick(row, "LeftButton", false)
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-shift", expected)
  local spell = NS.X.classic and "Prayer of Fortitude" or "Power Word: Fortitude"
  assert(db.castsTotal == count + 1 and db.history[#db.history].spell == spell, "wrong modifier spell credited")
  -- With no C_Timer.After the success event refreshes synchronously; rebind
  -- the test action as a fresh user click would use the newly painted row.
  row = env.BuffRadarRow1
  row.entry = { missing = { "Power Word: Fortitude" }, guid = env.UnitGUID("player"), unit = "player" }
  row.bSpell = "Power Word: Fortitude"
  row.attrs.type, row.attrs.spell = "spell", 1244
  env.IsShiftKeyDown = function() return false end
  row.scripts.PreClick(row, "LeftButton", false)
  fire("UNIT_SPELLCAST_SENT", "player", env.UnitName("player"), "cast-plain", 1244)
  row.scripts.PostClick(row, "LeftButton", false)
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-plain", 1244)
  assert(db.castsTotal == count + 2 and db.history[#db.history].spell == "Power Word: Fortitude",
    "plain click did not record the correct book spell")
  env.SlashCmdList.BUFFRADAR("modclick off")
  runQueued()
end)
step("custom group-cast pairs feed modifier clicks (1.15.0)", function()
  if not NS.X.classic then return end
  env.SlashCmdList.BUFFRADAR("modclick on")
  env.SlashCmdList.BUFFRADAR('grouppair "Thorns" "Thorns of the Grove"')
  assert(NS.X.GroupSpellFor("Thorns") == "Thorns of the Grove", "custom pair not used by GroupSpellFor")
  assert(env.BuffRadarDB.customGroup["Thorns"] == "Thorns of the Grove", "pair not saved")
  local row = env.BuffRadarRow1
  local db = env.BuffRadarDB
  local count = db.castsTotal
  row.entry = { missing = { "Thorns" }, guid = env.UnitGUID("player"), unit = "player" }
  row.bSpell = "Thorns"
  row.bGroupSpell = "Thorns of the Grove"
  row.attrs["type"], row.attrs["spell"] = "spell", 467
  row.attrs["shift-type1"], row.attrs["shift-spell1"] = "spell", 9999
  env.IsShiftKeyDown = function() return true end
  row.scripts.PreClick(row, "LeftButton", false)
  fire("UNIT_SPELLCAST_SENT", "player", env.UnitName("player"), "cast-custom", 9999)
  row.scripts.PostClick(row, "LeftButton", false)
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-custom", 9999)
  assert(db.castsTotal == count + 1 and db.history[#db.history].spell == "Thorns of the Grove",
    "shift-click ignored the custom pair")
  env.IsShiftKeyDown = function() return false end
  env.SlashCmdList.BUFFRADAR('grouppair clear "Thorns"')
  assert(NS.X.GroupSpellFor("Thorns") == nil, "cleared pair still active")
  env.SlashCmdList.BUFFRADAR("modclick off")
  runQueued()
end)
step("fast aura: unwatched payload skipped, watched payload refreshes (1.14.0)", function()
  if not env.__timers then return end
  env.SlashCmdList.BUFFRADAR("fastaura on")
  local probe = NS.X.auraProbe or {}
  local skipped0 = probe.skipped or 0
  fire("UNIT_AURA", "player", { addedAuras = { { name = "Unwatched Proc", auraInstanceID = 9002 } } })
  probe = NS.X.auraProbe
  assert(probe and (probe.skipped or 0) == skipped0 + 1,
    "unwatched payload was not skipped: fast=" .. tostring(env.BuffRadarDB.fastAura)
      .. " skipped=" .. tostring(probe and probe.skipped) .. " before=" .. tostring(skipped0)
      .. " queue=" .. tostring(#env.__timers) .. " simple=" .. tostring(env.BuffRadarDB.simpleMode)
      .. " supported=" .. tostring(NS.X.supported) .. " last=" .. tostring(chat[#chat]))
  assert(#env.__timers == 0, "skipped payload queued a refresh")
  assert(not NS.X.auraIds.player, "unwatched aura created a cache bucket")
  local watchedName = next(NS.X.watchNames or {})
  assert(watchedName, "watchNames is empty")
  fire("UNIT_AURA", "player", { addedAuras = { { name = watchedName, auraInstanceID = 9003 } } })
  assert(#env.__timers == 1, "watched payload did not queue a refresh")
  runQueued()
  local cons = env.BuffRadarDB.consumables
  env.BuffRadarDB.consumables = true
  fire("UNIT_AURA", "player", { addedAuras = { { name = "Well Fed", spellId = 19705, auraInstanceID = 9001 } } })
  assert(#env.__timers == 1, "consumable aura change (Well Fed) did not queue a refresh")
  runQueued()
  env.BuffRadarDB.consumables = cons
  fire("UNIT_AURA", "player", { removedAuraInstanceIDs = { 9002 } })
  assert(#env.__timers == 1, "unknown removed ID must refresh conservatively")
  runQueued()
  fire("UNIT_AURA", "player", { removedAuraInstanceIDs = { 9003 } })
  assert(#env.__timers == 1, "removal of a watched aura did not queue a refresh")
  runQueued()
  env.SlashCmdList.BUFFRADAR("fastaura off")
end)
step("fast aura indexes watched instances only and invalidates stale entries", function()
  local X, db = NS.X, env.BuffRadarDB
  local prev, oldAura = db.fastAura, env.C_UnitAuras
  db.fastAura, X.auraIds = true, nil
  local name = assert(next(X.watchNames))
  env.C_UnitAuras = { GetAuraDataByAuraInstanceID = function(_, id)
    if id == 37 then return { name = name } end
    if id == 38 then return { name = "Unwatched" } end
    return { name = {} }
  end }
  assert(X.AuraRelevant("player", nil, { 37 }), "resolved watched update skipped")
  assert(not X.AuraRelevant("player", nil, { 38 }), "resolved unrelated update refreshed")
  assert(X.AuraRelevant("player", nil, { 39 }), "non-string updated name skipped")
  assert(X.auraIds.player[37] == name and not X.auraIds.player[38], "unwatched update was cached")
  assert(X.AuraRelevant("player", nil, nil, { 37 }) and not X.auraIds.player, "empty bucket retained")
  X.AuraRelevant("player", { { name = name, auraInstanceID = 37 } })
  assert(X.AuraRelevant("player", { { name = "Unwatched", auraInstanceID = 37 } })
    and not X.auraIds.player, "reused ID retained its previous watched name")
  assert(X.AuraRelevant("player", { { name = name, auraInstanceID = math.huge } }), "nonfinite ID accepted")
  X.AuraRelevant("player", { { name = name, auraInstanceID = 37 } })
  db.fastAura = false
  fire("UNIT_AURA", "player", { removedAuraInstanceIDs = { 37 } })
  assert(not X.auraIds.player, "disabled filtering kept stale aura IDs")
  X.AuraRelevant("player", { { name = name, auraInstanceID = 37 } })
  env.__combat = true
  fire("UNIT_AURA", "player", { removedAuraInstanceIDs = { 37 } })
  env.__combat = false
  assert(not X.auraIds.player, "discarded combat update kept stale aura IDs")
  X.AuraRelevant("player", { { name = name, auraInstanceID = 37 } })
  fire("SPELLS_CHANGED")
  runQueued()
  local cacheCleared = not X.auraIds
  db.fastAura, env.C_UnitAuras = prev, oldAura
  timerTick()
  assert(cacheCleared, "spellbook rescan kept cached watch names")
end)
step("fast aura cache is cleared when a unit token changes", function()
  local X = NS.X
  X.auraIds = { target = { [101] = "Unwatched" }, mouseover = { [102] = "Unwatched" },
    nameplate1 = { [103] = "Unwatched" }, raid1 = { [104] = "Unwatched" } }
  fire("PLAYER_TARGET_CHANGED")
  assert(not X.auraIds.target and X.auraIds.raid1, "target token kept old aura IDs")
  fire("UPDATE_MOUSEOVER_UNIT")
  assert(not X.auraIds.mouseover, "mouseover token kept old aura IDs")
  fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
  assert(not X.auraIds.nameplate1, "removed nameplate kept old aura IDs")
  fire("GROUP_ROSTER_UPDATE")
  assert(not next(X.auraIds), "changed roster kept old aura IDs")
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
  end)
  assert(n == 0, "tick refreshed while paused (" .. n .. ")")
end)
step("leaving the city refreshes on the zone event, not on a periodic scan", function()
  env.__zone = "Elwynn Forest"
  local n1 = refreshesDuring(function() fire("ZONE_CHANGED_NEW_AREA"); timerTick() end)
  assert(n1 >= 1, "zone change didn't refresh")
  local n2 = refreshesDuring(function()
    if env.__ticker then env.__ticker() end
  end)
  assert(n2 == 0, "UI ticker performed a periodic player scan")
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
  assert(listed.nameplate2.name == "nameplate2", "restricted name did not use a readable fallback")
  -- Hovering and right-clicking those rows must not throw or save an unstable unit token.
  for i = 1, 15 do
    local row = env["BuffRadarRow" .. i]
    if row and row.entry and row.shown and plates[row.entry.unit] then
      row.scripts.OnEnter(row)
      row.scripts.OnClick(row, "RightButton", false)
    end
  end
  assert(not env.BuffRadarDB.ignored.nameplate2 and not env.BuffRadarDB.ignored.nameplate3,
    "right-click saved a unit token as a player name")
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
local function refresh() timerTick(); NS.X.Refresh(); timerTick() end

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
  assert(row:GetAttribute("type"), "a returned in-range target did not rearm the row")
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
  local originalSize = env.GetNumGroupMembers
  env.GetNumGroupMembers = function() return env.IsInGroup() and 3 or 0 end
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
    env.GetNumGroupMembers = originalSize
    env.IsSpellInRange = nil
  end
end
step("action-bar macro follows self and nearby targets without chaining macros", function()
  local cleanup = twoTanks()
  local X, O, db = NS.X, env.__over, env.BuffRadarDB
  local index = env.GetMacroIndexByName("BuffRadar")
  local savedMacro = env.__macros[index]
  local oldCVar, oldOpen, oldSpell, oldZone = env.GetCVarBool, env.Settings.OpenToCategory, env.C_Spell, env.__zone
  local oldGetTime = O.GetTime
  local oldSelf, oldMode, oldMod, oldSort, oldCity = db.includeSelf, db.castMethod, db.modClick, db.sortMode, db.pauseInCities
  local oldEdit, oldFrame, oldOffer, oldShift = env.EditMacro, env.MacroFrame, X.GroupOffer, env.IsShiftKeyDown
  local function idle(body) return body and not body:find("\n/click", 1, true) and not body:find("\n/cast", 1, true) end
  local ok, err = pcall(function()
    env.__macros[index] = nil
    fire("UPDATE_MACROS")
    X.SyncCastMacro(true)
    assert(env.GetMacroIndexByName("BuffRadar") == 0, "background sync created a macro without permission")
    env.SlashCmdList.BUFFRADAR("macro")
    index = env.GetMacroIndexByName("BuffRadar")
    assert(index > 0 and env.__pickedMacro == index, "/br macro did not create and pick up a new macro")
    env.__macros[index] = nil
    fire("UPDATE_MACROS")
    X.SyncCastMacro(true)
    -- A macro already in a user's action bar should be upgraded in its own slot.
    index = env.CreateMacro("BuffRadar", 134400, "/click BuffRadarNextButton LeftButton 1")
    fire("UPDATE_MACROS")
    env.EditMacro = function(...)
      local slot = oldEdit(...)
      fire("UPDATE_MACROS") -- this event is synchronous on the real client
      return slot
    end
    X.SyncCastMacro(true)
    assert(idle(env.GetMacroBody(index)), "old addon macro was not migrated to a harmless idle body")
    local keyDown, selfCovered, hasTarget = false, false, true
    local exists, name, guid = O.UnitExists, O.UnitName, O.UnitGUID
    local renamed, replacement
    O.UnitExists = function(unit) return unit == "target" and hasTarget or exists(unit) end
    O.UnitGUID = function(unit) if unit == "nameplate1" and replacement then return replacement end; return guid(unit) end
    O.UnitName = function(unit)
      if unit == "nameplate1" then return renamed or "Alden", env.__forever and "Ashford" or nil end
      return name(unit)
    end
    O.Aura = function(unit)
      if unit == "player" and selfCovered then return { expirationTime = env.GetTime() + 3600 } end
      return nil
    end
    env.IsSpellInRange = function() return 1 end
    env.GetCVarBool = function(key)
      if key == "ActionButtonUseKeyDown" then return keyDown end
      return oldCVar(key)
    end
    db.includeSelf, db.castMethod, db.modClick, db.sortMode = true, "target", false, "name"
    X.Refresh()
    local button = env.BuffRadarNextButton
    local selfBody = env.GetMacroBody(index)
    assert(button.entry and button.entry.isSelf and selfBody:find("\n/click BuffRadarNextButton$"),
      "self-priority or native spell action changed")
    keyDown = true
    fire("CVAR_UPDATE", "ACTION_BUTTON_USE_KEY_DOWN")
    assert(button.clickRegistration[1] == "LeftButtonDown"
      and env.GetMacroBody(index):find("BuffRadarNextButton LeftButton 1$"), "key-down phase not synced for spell casts")
    env.SlashCmdList.BUFFRADAR("macro")
    assert(env.__pickedMacro == index, "create macro did not preserve the existing action bar slot")

    selfCovered = true
    X.Refresh()
    local target = env.__forever and "Alden Ashford" or "Alden"
    local body = env.GetMacroBody(index)
    assert(button.entry and button.entry.unit == "nameplate1" and button:GetAttribute("type") == "macro",
      "next secure button did not move from self to the nearby player")
    assert(body:find("/stopmacro [combat][@player,dead]", 1, true)
      and not body:find("/click BuffRadarNextButton", 1, true)
      and body:find("\n/cleartarget\n/targetexact " .. target .. "\n/cast [help,nodead] ", 1, true)
      and body:find("\n/targetlasttarget$"), "managed macro does not execute a guarded exact-name cast at top level")
    assert(body:find(shownRows().nameplate1.row:GetAttribute("macrotext"), 1, true),
      "row and bar macro disagreed on how to reach the player")
    local writes = env.__macroWrites
    local delivery = X.CastDelivery()
    assert(delivery.directReady and delivery.macroReady and delivery.reason == "ready",
      "armed direct and synchronized bar actions were not reported ready")
    X.DeliveryLines(); X.CastDelivery()
    assert(env.__macroWrites == writes, "diagnostic reads edited macros")
    X.Refresh(); X.Refresh()
    assert(env.__macroWrites == writes, "a steady queue rewrote its macro")
    keyDown = false
    fire("CVAR_UPDATE", "ActionButtonUseKeyDown")
    assert(button.clickRegistration[1] == "LeftButtonUp" and env.GetMacroBody(index) == body,
      "changing key phase rewrote a direct bar cast or lost the up binding")

    -- Model only the relevant slash commands, including a /targetexact miss
    -- leaving its input target alone. The real secure execution needs WoW.
    local function simulate(text, previous, available, stopped)
      local current, last, cast = previous, "Old target"
      for line in text:gmatch("[^\n]+") do
        if line == "/stopmacro [combat][@player,dead]" and stopped then break end
        if line == "/cleartarget" then
          if current then last = current end
          current = nil
        elseif line:find("^/targetexact ") then
          if available then current = line:sub(14) end
        elseif line:find("/cast [help,nodead] ", 1, true) then
          cast = current
        elseif line == "/targetlasttarget" then
          current = last
        end
      end
      return cast, current
    end
    local recipient, restored = simulate(body, "Previous friend", false)
    assert(not recipient and restored == "Previous friend", "a missed exact name cast on the old target or self")
    recipient, restored = simulate(body, "Previous friend", true)
    assert(recipient == target and restored == "Previous friend", "exact cast did not hand back the prior target")
    hasTarget = false
    X.Refresh()
    body = env.GetMacroBody(index)
    recipient, restored = simulate(body, nil, true)
    assert(recipient == target and not restored, "cast with no original target reselected a stale previous one")

    -- The action marker does not cast. Only the spell event with the intended
    -- target and ID can advance the counter, whether the input was key or bar.
    local spellID = env.__forever and 1244 or 462854
    env.C_Spell = { GetSpellIDForSpellIdentifier = function() return spellID end }
    local before = db.castsTotal
    X.ResetCastTracking()
    env.__runningMacro = index + 1
    env.BuffRadarMacroButton:Click()
    fire("UNIT_SPELLCAST_SENT", "player", target, "macro-unowned", spellID)
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "macro-unowned", spellID)
    assert(db.castsTotal == before, "a different macro claimed the managed cast")
    env.__runningMacro = index
    env.BuffRadarMacroButton:Click()
    env.__runningMacro = nil
    fire("UNIT_SPELLCAST_SENT", "player", target, "managed-macro", spellID)
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "managed-macro", spellID)
    assert(db.castsTotal == before + 1 and db.history[#db.history].who == target,
      "the direct bar cast lost confirmed recipient attribution")
    local now = 1000
    O.GetTime = function() return now end
    X.ResetCastTracking()
    before = db.castsTotal
    env.__runningMacro = index
    env.BuffRadarMacroButton:Click()
    env.__runningMacro = nil
    now = now + 0.162
    env.__runningMacro = index
    env.BuffRadarMacroButton:Click()
    env.__runningMacro = nil
    fire("UNIT_SPELLCAST_SENT", "player", target, "rapid-managed-macro", spellID)
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "rapid-managed-macro", spellID)
    O.GetTime = oldGetTime
    assert(db.castsTotal == before + 1 and db.history[#db.history].who == target,
      "a rapid same-target bar retry lost its delayed cast attribution")
    X.ResetCastTracking()
    local opened
    env.Settings.OpenToCategory = function(category, section) opened = category == env.Settings.KEYBINDINGS_CATEGORY_ID and section end
    env.SlashCmdList.BUFFRADAR("gamepad")
    assert(opened == "BuffRadar" and button.entry.unit == "nameplate1", "controller setup did not open the native buff binding")

    env.__runningMacro = index
    X.SyncCastMacro(true)
    assert(env.GetMacroBody(index) == body, "an in-progress macro was rewritten")
    env.__runningMacro = nil
    fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
    assert(env.GetMacroBody(index) == body, "an unrelated nameplate disarmed the macro")
    fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    assert(idle(env.GetMacroBody(index)), "nameplate removal left the macro armed until the next scan")
    renamed, replacement = "Cedric", "Player-1-T99"
    X.Refresh()
    assert(env.GetMacroBody(index):find("/targetexact Cedric", 1, true), "recycled nameplate kept its old target")
    db.castMethod = "macro"
    X.Refresh()
    assert(button:GetAttribute("macrotext"):find("[@nameplate1,help,nodead]", 1, true)
      and env.GetMacroBody(index):find("/targetexact Cedric", 1, true), "bar macro embedded a recycled unit token")
    renamed, replacement, db.castMethod = nil, nil, "target"
    X.Refresh()

    -- The editor may have unsaved text. Background writes must not fire
    -- UPDATE_MACROS until it closes, and a hand-edit loses ownership.
    env.MacroFrame = env.CreateFrame("Frame")
    env.MacroFrame:Show()
    renamed, replacement = "Cedric", "Player-1-T99"
    X.Refresh()
    assert(env.GetMacroBody(index) == body, "macro editor did not defer automatic writes")
    local pending = X.CastDelivery()
    assert(pending.directReady and not pending.macroReady and pending.macroState == "pending"
      and pending.reason == "editor", "editor delay hid usable direct casting or reported the stale macro ready")
    env.MacroFrame:Hide()
    timerTick()
    assert(env.GetMacroBody(index):find("/targetexact Cedric", 1, true), "macro did not catch up after editing finished")
    env.MacroFrame = oldFrame

    -- Refuse a body the game would truncate, without disabling the native
    -- action (its shorter script still fits). Then verify a Shift variant.
    renamed, replacement = "A" .. string.rep("é", 77), "Player-1-T100"
    X.Refresh()
    assert(button.entry and #button:GetAttribute("macrotext") <= 255 and idle(env.GetMacroBody(index)),
      "an oversized bar macro was stored or disabled the native cast")
    local overflow = X.CastDelivery()
    assert(overflow.directReady and not overflow.macroReady and overflow.reason == "overflow"
      and overflow.macroState == "unavailable", "bar overflow incorrectly disabled direct casting or claimed pending sync")
    renamed, replacement = "Alden\n/cast Another Spell", "Player-1-T101"
    X.Refresh()
    assert(not button:GetAttribute("macrotext") and idle(env.GetMacroBody(index)),
      "an unusable exact name became macro commands")
    assert(not X.CastDelivery().directReady and X.CastDelivery().reason == "unsafe",
      "unsafe recipient was advertised as usable")
    renamed, replacement = nil, nil
    X.Refresh()
    if env.__forever then
      local base = button.bSpell
      db.modClick = true
      X.GroupOffer = function(spell, unit)
        if spell == base and unit == "nameplate1" then return "Group buff" end
        return oldOffer(spell, unit)
      end
      X.Refresh()
      local shifted = env.GetMacroBody(index)
      assert(shifted:find("/cast [mod:shift,nomod:ctrl,nomod:alt,help,nodead] Group buff; [help,nodead] ", 1, true)
        and not shifted:find("/click BuffRadarNextButton", 1, true), "bar cast lost or nested the Shift variant")
      X.ResetCastTracking()
      env.IsShiftKeyDown = function() return true end
      env.__runningMacro = index
      env.BuffRadarMacroButton:Click()
      env.__runningMacro = nil
      fire("UNIT_SPELLCAST_SENT", "player", target, "shifted-macro", spellID)
      fire("UNIT_SPELLCAST_SUCCEEDED", "player", "shifted-macro", spellID)
      assert(db.history[#db.history].spell == "Group buff", "bar macro attributed Shift to the unmodified spell")
      env.IsShiftKeyDown, db.modClick, X.GroupOffer = oldShift, false, oldOffer
      X.Refresh()
    end
    assert(env.GetMacroBody(index) == body, "restoring the original queue did not restore the original macro")
    db.pauseInCities, env.__zone = true, "Stormwind City"
    fire("ZONE_CHANGED_NEW_AREA")
    timerTick()
    assert(idle(env.GetMacroBody(index)) and not button.entry, "city pause left the macro armed")
    assert(not X.CastDelivery().directReady and not X.CastDelivery().macroReady,
      "paused actions were advertised as ready")
    db.pauseInCities, env.__zone = false, oldZone
    X.Refresh()
    assert(not idle(env.GetMacroBody(index)), "turning off city pause did not rearm the macro")

    env.__combat = true
    fire("PLAYER_REGEN_DISABLED")
    local combatWrites = env.__macroWrites
    X.SyncCastMacro(true)
    assert(env.__macroWrites == combatWrites and not simulate(body, "Previous friend", true, true),
      "combat attempted to edit the macro or left the direct cast enabled")
    assert(not X.CastDelivery().directReady and not X.CastDelivery().macroReady,
      "combat safety state was reported ready")
    env.__combat = false
    fire("PLAYER_REGEN_ENABLED")
    assert(idle(env.GetMacroBody(index)), "pre-combat macro was still armed before a safe rescan")
    X.Refresh()
    assert(not idle(env.GetMacroBody(index)), "leaving combat did not rearm the macro")
    fire("PLAYER_DEAD")
    assert(idle(env.GetMacroBody(index)), "death left the macro armed")
    assert(X.CastDelivery().directReason == "disarmed" and not X.CastDelivery().macroReady)
    fire("PLAYER_ALIVE")
    X.Refresh()
    assert(not idle(env.GetMacroBody(index)), "resurrection did not rearm the macro")
    fire("PLAYER_LEAVING_WORLD")
    X.Refresh()
    assert(idle(env.GetMacroBody(index)), "loading screen left an armed macro")
    fire("PLAYER_ENTERING_WORLD")
    X.Refresh()
    assert(not idle(env.GetMacroBody(index)), "returning to the world did not rearm the macro")

    -- A manual edit may happen before the next UPDATE_MACROS. Recheck
    -- before disarming so the write cannot hit an unrelated macro slot.
    local custom = env.GetMacroBody(index) .. "\n/say hello"
    oldEdit(index, nil, nil, custom)
    X.SyncCastMacro(true)
    fire("UPDATE_MACROS")
    X.Refresh()
    env.SlashCmdList.BUFFRADAR("macro")
    assert(env.GetMacroBody(index) == custom, "an edited BuffRadar macro was overwritten")
    assert(X.CastDelivery().reason == "custom" and not X.CastDelivery().macroReady,
      "custom macro ownership was reported synchronized")
    env.__macros[index] = nil
    fire("UPDATE_MACROS")
    X.SyncCastMacro(true)
    index = env.CreateMacro("BuffRadar", 134400, custom) -- even before it is tracked this session
    fire("UPDATE_MACROS")
    X.SyncCastMacro(true)
    assert(env.GetMacroBody(index) == custom, "a macro with an added line was reclaimed from the marker alone")
  end)
  env.__combat, env.__runningMacro, X.macroParked = false, nil, nil
  O.GetTime = oldGetTime
  env.GetCVarBool, env.Settings.OpenToCategory, env.C_Spell, env.__zone = oldCVar, oldOpen, oldSpell, oldZone
  env.EditMacro, env.MacroFrame, X.GroupOffer, env.IsShiftKeyDown = oldEdit, oldFrame, oldOffer, oldShift
  db.includeSelf, db.castMethod, db.modClick, db.sortMode, db.pauseInCities = oldSelf, oldMode, oldMod, oldSort, oldCity
  env.__macros[index] = nil
  fire("UPDATE_MACROS")
  X.SyncCastMacro(true)
  if savedMacro then env.CreateMacro(savedMacro.name, savedMacro.icon, savedMacro.body); fire("UPDATE_MACROS") end
  cleanup()
  env.IsSpellInRange = nil
  X.ResetCastTracking()
  fire("PLAYER_ALIVE")
  X.ApplyNextRegistration()
  X.Refresh()
  assert(ok, err)
end)
-- Player report (1.16.1): after a relog the bar macro stayed on its last
-- text (idle, or the self /click) until it was deleted and remade. The
-- game hands stored macro text back with a trailing line break, and the
-- exact-text ownership check refused BuffRadar's own macro.
step("bar macro stays managed when the game returns its text with line-break changes", function()
  local cleanup = twoTanks()
  local X, O, db = NS.X, env.__over, env.BuffRadarDB
  local index = env.GetMacroIndexByName("BuffRadar")
  local savedMacro = index > 0 and env.__macros[index]
  local oldEdit, oldBody = env.EditMacro, env.GetMacroBody
  local oldSelf, oldMode, oldSort = db.includeSelf, db.castMethod, db.sortMode
  local selfCovered = false
  local header = "# BuffRadar\n/stopmacro [combat][@player,dead]"
  local function relog(stored, suffix)
    if index > 0 then env.__macros[index] = nil end
    fire("UPDATE_MACROS")
    X.SyncCastMacro(true) -- forget the macro this session tracked
    env.GetMacroBody = function(i)
      local body = oldBody(i)
      return body and (body:gsub("\n", suffix == "\r\n" and "\r\n" or "\n") .. suffix)
    end
    index = env.CreateMacro("BuffRadar", 134400, stored)
    fire("UPDATE_MACROS")
  end
  local ok, err = pcall(function()
    db.includeSelf, db.castMethod, db.sortMode = true, "target", "name"
    O.Aura = function(unit)
      if unit == "player" and selfCovered then return { expirationTime = env.GetTime() + 3600 } end
    end
    env.IsSpellInRange = function() return 1 end
    env.EditMacro = function(...)
      local slot = oldEdit(...)
      fire("UPDATE_MACROS") -- synchronous on the real client
      return slot
    end
    local stored = {
      header,
      header .. "\n/click BuffRadarNextButton",
      header .. "\n/click BuffRadarNextButton LeftButton 1",
      "/click BuffRadarNextButton",
    }
    for _, suffix in ipairs({ "", "\n", "\r\n", "\n\n", " \n" }) do
      for _, text in ipairs(stored) do
        selfCovered = false
        relog(text, suffix)
        X.Refresh()
        local label = string.format("%q + %q", text, suffix)
        assert(oldBody(index):find("\n/click BuffRadarNextButton", 1, true),
          "relogged macro did not arm for the self buff: " .. label)
        selfCovered = true
        X.Refresh()
        assert(oldBody(index):find("\n/targetexact Tank1\n", 1, true),
          "relogged macro stopped following the queue to a nearby player: " .. label)
        selfCovered = false
        X.Refresh()
        assert(oldBody(index):find("\n/click BuffRadarNextButton", 1, true),
          "macro lost ownership after its own write was read back: " .. label)
      end
    end
    -- A hand-edited macro stays the player's, whatever the line endings.
    local custom = header .. "\n/say hello"
    relog(custom, "\n")
    X.Refresh()
    assert(oldBody(index) == custom, "a hand-edited macro was reclaimed after a relog")
  end)
  env.EditMacro, env.GetMacroBody = oldEdit, oldBody
  db.includeSelf, db.castMethod, db.sortMode = oldSelf, oldMode, oldSort
  if index > 0 then env.__macros[index] = nil end
  fire("UPDATE_MACROS")
  X.SyncCastMacro(true)
  if savedMacro then env.CreateMacro(savedMacro.name, savedMacro.icon, savedMacro.body); fire("UPDATE_MACROS") end
  cleanup()
  env.IsSpellInRange = nil
  X.ResetCastTracking()
  X.Refresh()
  assert(ok, err)
end)
step("cast keybinds disarm when a roster token changes after the scan", function()
  local cleanup = partyOfTwo("KEY")
  local O, X, db = env.__over, NS.X, env.BuffRadarDB
  local oldInclude, oldMethod, oldSort = db.includeSelf, db.castMethod, db.sortMode
  local ok, err = pcall(function()
    db.includeSelf, db.castMethod, db.sortMode = false, "target", "name"
    env.IsSpellInRange = function() return 1 end
    O.UnitIsPlayer = function(unit) return unit ~= "player" and O.UnitExists(unit) end
    local originalGUID = O.UnitGUID
    local replacement
    O.UnitGUID = function(unit)
      if unit == "party1" and replacement then
        if replacement == "unreadable" then return nil end
        return replacement
      end
      return originalGUID(unit)
    end
    local buttons = { env.BuffRadarNextButton, env.BuffRadarGroupButton }
    local stale = {}
    for _, button in ipairs(buttons) do
      local clickStart = assert(button:GetScript("PreClick"))
      local clickEnd = assert(button:GetScript("PostClick"))
      for _, down in ipairs({ true, false }) do
        replacement = nil
        X.Refresh()
        assert(button.entry.unit == "party1" and button:GetAttribute("type"), "fixture did not arm party1")
        clickStart(button, "LeftButton", down)
        assert(button:GetAttribute("type"), "stable recipient was disarmed")
        clickEnd(button, "LeftButton", down)
        X.ClearCastIntent()

        X.Refresh()
        replacement = down and "Player-1-Replacement" or "unreadable"
        clickStart(button, "LeftButton", down)
        local disarmed = not button:GetAttribute("type") and not button:GetAttribute("shift-type1")
          and not button:GetAttribute("macrotext") and not button.entry
        clickEnd(button, "LeftButton", down)
        if not disarmed then stale[#stale + 1] = button:GetName() .. (down and " down" or " up") end
        replacement = "Player-1-Replacement"
        X.Refresh()
        assert(button:GetAttribute("unit") == "party1" and button.entry.guid == replacement,
          "fresh scan did not bind the new recipient")
      end
    end
    assert(#stale == 0, "remained armed for a stale party1 token: " .. table.concat(stale, ", "))
  end)
  X.ClearCastIntent()
  db.includeSelf, db.castMethod, db.sortMode = oldInclude, oldMethod, oldSort
  cleanup()
  assert(ok, err)
end)
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
    "targets remained listed while the caster is in combat")
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
local function clickCast(row, castGUID, spellID, target, during, event, after)
  row.scripts.PreClick(row, "LeftButton", false)
  if not after then fire("UNIT_SPELLCAST_SENT", "player", target, castGUID, spellID) end
  if during then during() end
  row.scripts.PostClick(row, "LeftButton", false)
  if after then fire("UNIT_SPELLCAST_SENT", "player", target, castGUID, spellID) end
  if event then fire(event, "player", castGUID, spellID) end
end

step("only correlated target failures temporarily skip the target", function()
  local cleanup = partyOfTwo("L")
  local O, X = env.__over, NS.X
  O.IsSpellInRange = function() return 1 end
  refresh()
  local displayed = shownRows().party1
  assert(displayed, "Aaron's row not found")
  local row = displayed.row
  local guid = row.entry.guid
  local spellID = env.__forever and 1244 or 462854
  local spell = row.entry.missing[1]
  local original = env.C_Spell
  env.C_Spell = { GetSpellIDForSpellIdentifier = function() return spellID end,
    GetSpellName = function() return spell end }
  env.SPELL_FAILED_OUT_OF_RANGE = "That target is too distant."
  clickCast(row, "cast-range", spellID, "Aaron", function()
    fire("UI_ERROR_MESSAGE", 1, "That target is too distant.")
    fire("UNIT_SPELLCAST_FAILED", "player", "cast-range", spellID)
  end)
  assert(X.failedTargets[guid], "correlated range failure did not skip the target")
  refresh()
  assert(not shownRows().party1 and shownRows().party2, "failed target stayed listed or next target disappeared")

  X.failedTargets[guid] = nil
  refresh()
  displayed = shownRows().party1
  assert(displayed, "target did not return after its skip cleared")
  row = displayed.row
  clickCast(row, "cast-mana", spellID, "Aaron", function()
    fire("UI_ERROR_MESSAGE", 1, "Not enough mana.")
    fire("UNIT_SPELLCAST_FAILED", "player", "cast-mana", spellID)
  end)
  assert(not X.failedTargets[guid], "mana failure skipped the player")
  clickCast(row, "cast-los", spellID, "Aaron")
  fire("UI_ERROR_MESSAGE", 1, "Target is not in line of sight")
  fire("UNIT_SPELLCAST_FAILED", "player", "cast-los", spellID)
  assert(not X.failedTargets[guid], "delayed unkeyed error skipped a player")
  clickCast(row, "cast-target", spellID, "Aaron", function()
    fire("UI_ERROR_MESSAGE", 1, "Invalid target.")
    fire("UNIT_SPELLCAST_FAILED", "player", "not-our-cast", spellID)
  end)
  fire("UNIT_SPELLCAST_FAILED", "player", "cast-target", spellID)
  assert(not X.failedTargets[guid], "mismatched or delayed failure skipped a player")
  env.SPELL_FAILED_OUT_OF_RANGE = nil
  env.C_Spell = original
  cleanup()
end)

step("Forever event order correlates exact identity and consumes a GUID once", function()
  local cleanup = partyOfTwo("Attribution")
  local O, X, db = env.__over, NS.X, env.BuffRadarDB
  local original = env.C_Spell
  local spellID = env.__forever and 1244 or 462854
  env.C_Spell = { GetSpellIDForSpellIdentifier = function() return spellID end }
  O.IsSpellInRange = function() return 1 end
  local now = 1000
  O.GetTime = function() return now end
  local name = "Sample Player"
  local oldName, oldFullName = O.UnitName, O.UnitFullName
  O.UnitName = function(unit) return unit == "party1" and name or oldName(unit) end
  O.UnitFullName = function(unit) if unit == "party1" then return name, "TestRealm" end; return oldFullName(unit) end
  refresh()
  local row = shownRows().party1.row
  X.ResetCastTracking()
  local initial = db.castsTotal
  local function click(button, down)
    row.scripts.PreClick(row, button, down or false)
    row.scripts.PostClick(row, button, down or false)
  end
  local function sent(guid, id, target)
    fire("UNIT_SPELLCAST_SENT", "player", target or name, guid, id or spellID)
  end
  local function done(guid, id, terminal)
    fire(terminal or "UNIT_SPELLCAST_SUCCEEDED", "player", guid, id or spellID)
  end
  click("RightButton")
  sent("right-click"); done("right-click")
  click("LeftButton")
  done("manual-no-sent")
  sent("wrong-player", spellID, "SamplePlayer"); done("wrong-player")
  sent("after-competition"); done("after-competition")
  click("LeftButton")
  sent("wrong-rank", spellID + 1); done("wrong-rank", spellID + 1)
  click("LeftButton")
  now = now + 0.300
  sent("expired"); done("expired")
  click("LeftButton"); click("LeftButton")
  sent("overlap"); done("overlap")
  assert(db.castsTotal == initial + 1, "same-target retries lost a uniquely matched cast")
  initial = db.castsTotal
  click("LeftButton")
  local otherRow = shownRows().party2.row
  otherRow.scripts.PreClick(otherRow, "LeftButton", false)
  sent("overlap-in-new-click", spellID, env.UnitName(otherRow.entry.unit))
  otherRow.scripts.PostClick(otherRow, "LeftButton", false)
  done("overlap-in-new-click")
  assert(db.castsTotal == initial, "an overlapping different-target cast was attributed")
  click("LeftButton")
  local masked = {}
  env.issecretvalue = function(v) return v == masked end
  fire("UNIT_SPELLCAST_SENT", "player", name, masked, spellID)
  local readableFullName = O.UnitFullName
  O.UnitFullName = function(unit) if unit == "party1" then return name, masked end; return readableFullName(unit) end
  click("LeftButton")
  sent("secret-realm"); done("secret-realm")
  O.UnitFullName = readableFullName
  env.issecretvalue = nil
  sent("after-secret"); done("after-secret")
  assert(db.castsTotal == initial, "unproven spell was attributed")

  click("LeftButton")
  now = now + 0.050
  sent("confirmed")
  done("confirmed", spellID + 1)
  done("different-guid")
  assert(db.castsTotal == initial, "wrong terminal credited")
  done("confirmed"); done("confirmed")
  assert(db.castsTotal == initial + 1 and db.history[#db.history].who == name, "confirmed cast did not count once")
  click("LeftButton")
  sent("confirmed"); done("confirmed")
  assert(db.castsTotal == initial + 1, "replayed cast GUID counted again")

  click("LeftButton")
  sent("quiet-fail")
  done("quiet-fail", spellID, "UNIT_SPELLCAST_FAILED_QUIET"); done("quiet-fail")
  click("LeftButton")
  sent("interrupt")
  done("interrupt", spellID, "UNIT_SPELLCAST_INTERRUPTED"); done("interrupt")
  assert(db.castsTotal == initial + 1, "failed or interrupted cast was credited")

  row.scripts.PreClick(row, "LeftButton", false)
  done("synchronous")
  sent("synchronous")
  row.scripts.PostClick(row, "LeftButton", false)
  assert(db.castsTotal == initial + 2, "synchronous out-of-order terminal was missed")
  local prior = env.BuffRadarNextButton
  local group = env.BuffRadarGroupButton
  assert(prior.entry and group.entry, "hidden cast buttons are not armed")
  clickCast(prior, "key-next", spellID, env.UnitName(prior.entry.unit), nil, "UNIT_SPELLCAST_SUCCEEDED", true)
  local groupID = env.__forever and 21562 or spellID
  clickCast(group, "key-group", groupID, env.UnitName(group.entry.unit), nil, "UNIT_SPELLCAST_SUCCEEDED", true)
  assert(db.castsTotal == initial + 4, "hidden cast button did not record its cast")
  assert(db.history[#db.history].spell == (env.__forever and "Prayer of Fortitude" or "Skyfury"),
    "hidden group button recorded the single-target spell")
  local originalCVar = env.GetCVarBool
  env.GetCVarBool = function(key) return key == "ActionButtonUseKeyDown" or originalCVar(key) end
  fire("CVAR_UPDATE", "ActionButtonUseKeyDown")
  prior.scripts.PreClick(prior, "LeftButton", true)
  prior.scripts.PostClick(prior, "LeftButton", true)
  sent("key-down", spellID, env.UnitName(prior.entry.unit)); done("key-down")
  assert(db.castsTotal == initial + 5, "cast on configured key-down phase did not count")
  env.GetCVarBool = originalCVar
  fire("CVAR_UPDATE", "ActionButtonUseKeyDown")
  click("LeftButton")
  fire("PLAYER_REGEN_DISABLED")
  sent("after-combat"); done("after-combat")
  assert(db.castsTotal == initial + 5, "unconfirmed intent survived combat entry")
  env.__combat = false
  fire("PLAYER_REGEN_ENABLED")
  X.ResetCastTracking()
  env.C_Spell = original
  cleanup()
  runQueued()
end)

step("Forever live trace attributes full roleplay names on either mouse phase", function()
  local cleanup = partyOfTwo("LiveTrace")
  local O, X, db = env.__over, NS.X, env.BuffRadarDB
  local original, getUnitName, nameUtil = env.C_Spell, env.GetUnitName, env.NameUtil
  local spellID = env.__forever and 1244 or 462854
  env.C_Spell = { GetSpellIDForSpellIdentifier = function() return spellID end }
  O.IsSpellInRange = function() return 1 end
  local now = 1000
  O.GetTime = function() return now end
  env.GetUnitName = function(unit) return unit == "party1" and "Aaron Example" or env.UnitName(unit) end
  if env.__forever then
    local unitName = O.UnitName
    O.UnitName = function(unit)
      if unit == "party1" then return "Aaron", "Example" end
      return unitName(unit)
    end
    local function fullName(name, surname)
      return surname and (name .. " " .. surname) or name
    end
    env.NameUtil = {
      GetFullNameWithoutRealm = fullName,
      FormatUnitNameForDisplay = function(unit) return fullName(env.UnitName(unit)) end,
    }
  end
  refresh()
  local row = shownRows().party1.row
  local targetGUID = row.entry.guid
  local initial = db.castsTotal
  local function click(down)
    row.scripts.PreClick(row, "LeftButton", down)
    row.scripts.PostClick(row, "LeftButton", down)
  end
  local function sent(guid, name)
    fire("UNIT_SPELLCAST_SENT", "player", name or "Aaron Example", guid, spellID)
  end
  local function done(guid, event)
    fire(event or "UNIT_SPELLCAST_SUCCEEDED", "player", guid, spellID)
  end
  local function los()
    fire("UI_ERROR_MESSAGE", 57, "Target not in line of sight")
  end

  X.ResetCastTracking()
  click(true)
  now = now + 0.090
  sent("live-down"); done("live-down")
  now = now + 0.400
  click(false)
  sent("manual-after-release"); done("manual-after-release")
  assert(db.castsTotal == initial + 1, "down cast or release duplicate was mishandled")

  click(true)
  now = now + 0.090
  click(false)
  now = now + 0.210
  done("synthetic-quiet", "UNIT_SPELLCAST_FAILED_QUIET")
  sent("live-up"); done("live-up")
  assert(db.castsTotal == initial + 2 and db.history[#db.history].who == "Aaron Example",
    "up cast with readable roleplay name was not counted")

  click(true)
  now = now + 0.090
  sent("stale-target", "Aaron Somebody"); done("stale-target")
  click(false)
  sent("manual-after-stale"); done("manual-after-stale")
  assert(db.castsTotal == initial + 2, "competing roleplay target was credited via short name")

  click(true)
  local entry = row.entry
  row.entry = shownRows().party2.row.entry
  click(false)
  sent("rebound-row"); done("rebound-row")
  row.entry = entry
  assert(db.castsTotal == initial + 2, "changing targets during a press credited the original target")

  local oldType, oldMacro = row:GetAttribute("type"), row:GetAttribute("macrotext")
  row:SetAttribute("type", "macro")
  row:SetAttribute("macrotext", "/targetexact Aaron Armed\n/cast " .. row.entry.missing[1] .. "\n/targetlasttarget")
  click(true)
  sent("not-armed"); done("not-armed")
  click(false)
  now = now + 0.100
  click(true)
  sent("exact-armed-target", "Aaron Armed"); done("exact-armed-target")
  click(false)
  assert(db.castsTotal == initial + 3, "cast matching the exact armed macro target was not recorded")
  local secretMacro = {}
  local oldSecret = env.issecretvalue
  env.issecretvalue = function(value) return value == secretMacro end
  row:SetAttribute("macrotext", secretMacro)
  click(true); click(false)
  sent("secret-macro"); done("secret-macro")
  assert(db.castsTotal == initial + 3, "unreadable action fell back to a different target name")
  env.issecretvalue = oldSecret
  row:SetAttribute("type", oldType)
  row:SetAttribute("macrotext", oldMacro)

  click(true)
  now = now + 0.090
  sent("stale-error"); done("stale-error", "UNIT_SPELLCAST_FAILED")
  now = now + 0.010
  los()
  assert(not X.failedTargets[targetGUID], "later frame UI error skipped the target")

  click(true)
  done("unbound-failure", "UNIT_SPELLCAST_FAILED")
  los()
  assert(not X.failedTargets[targetGUID], "unbound FAILED skipped the target")

  click(true)
  sent("interrupted-order"); done("interrupted-order", "UNIT_SPELLCAST_FAILED")
  done("competing-failure", "UNIT_SPELLCAST_FAILED_QUIET")
  los()
  assert(not X.failedTargets[targetGUID], "intervening player event did not clear the failure")

  click(true)
  sent("cooldown"); done("cooldown", "UNIT_SPELLCAST_FAILED")
  fire("UI_ERROR_MESSAGE", 61, "Spell is not ready yet.")
  los()
  assert(not X.failedTargets[targetGUID], "second UI error reused a consumed failure")

  click(true)
  now = now + 0.090
  sent("live-los"); done("live-los", "UNIT_SPELLCAST_FAILED")
  los()
  assert(X.failedTargets[targetGUID] and db.castsTotal == initial + 3,
    "same-frame line-of-sight failure was not linked to the target")
  X.failedTargets[targetGUID] = nil
  X.ResetCastTracking()
  env.C_Spell, env.GetUnitName, env.NameUtil = original, getUnitName, nameUtil
  cleanup()
  runQueued()
end)

step("coverage line: progress and per-buff counts (1.4.0)", function()
  if env.__forever then return end  -- coverage math is edition-independent; retail covers it
  local cleanup = partyOfTwo()
  local O, now = env.__over, env.GetTime()
  O.Aura = function(u, name) if u == "party2" and name == "Skyfury" then return { expirationTime = now + 600 } end end
  refresh()
  local cover
  for _, fs in ipairs(env.__fontstrings) do
    if type(fs.text) == "string" and localizedMatch(fs.text,"%d/%d fully buffed") then cover = fs.text end
  end
  assert(cover, "no coverage line rendered")
  assert(localizedMatch(cover,"%d/%d fully buffed",1,3), "coverage progress wrong: " .. cover)
  assert(cover:find("Skyfury 1/3", 1, true), "per-buff coverage wrong: " .. cover)
  O.Aura = nil
  cleanup()
end)
step("rezzed party member jumps the queue (1.4.0)", function()
  if env.__forever then return end
  local cleanup = partyOfTwo("RezSymbols")
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
  local db = env.BuffRadarDB
  local oldSymbols = db.tagSymbols
  db.tagSymbols = true
  NS.X.InvalidateTags()
  refresh()
  local withSymbol = row2.tag:GetText()
  db.tagSymbols = oldSymbols
  NS.X.InvalidateTags()
  assert(withSymbol == "+ " .. NS.X.L["recently rezzed"], "rezzed tag lost its accessibility symbol")
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
  assert(env.__sent[1].msg:find(NS.X.L["BuffRadar -- missing buffs: "],1,true), "announce text: " .. env.__sent[1].msg)
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
  assert(d.dbVersion == 25, "dbVersion not migrated to 25: " .. tostring(d.dbVersion))
  assert(d.assignmentEnabled == false and next(d.buffAssignments) == nil, "migration activated assignments")
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
  assert(type(d) == "table" and d.dbVersion == 25 and d.scale == 1,
    "corrupt save not replaced with defaults")
  d.scale = 1
  -- a 1.7.0-era save (dbVersion 9): an existing user — the wizard
  -- counts as already seen, so no first-run hint nags them (1.9.0)
  env.BuffRadarDB = { dbVersion = 9 }
  fire("ADDON_LOADED", "BuffRadar")
  d = env.BuffRadarDB
  assert(d.dbVersion == 25 and d.wizardSeen == true,
    "existing user not marked wizard-seen: " .. tostring(d.wizardSeen))
  d.dbVersion, d.assignmentEnabled, d.thornsAnyClassOutdoors = 18, true, nil
  fire("ADDON_LOADED", "BuffRadar")
  d = env.BuffRadarDB
  assert(d.dbVersion == 25 and d.thornsAnyClassOutdoors == false and d.assignmentEnabled,
    "v18 settings did not gain an opt-in Thorns default while preserving assignments")
  d.dbVersion, d.autoThemePriority, d.theme = 19, nil, "ui.auto"
  fire("ADDON_LOADED", "BuffRadar")
  d = env.BuffRadarDB
  assert(d.dbVersion == 25 and d.theme == "ui.auto" and d.autoThemePriority == "",
    "v19 migration changed Auto opt-in or failed to default the priority order")
  d.dbVersion, d.blessingComplement, d.plateRestore = 24, false, nil
  fire("ADDON_LOADED", "BuffRadar")
  d = env.BuffRadarDB
  assert(d.dbVersion == 25 and d.blessingComplement == true and not next(d.plateRestore) and d.assignmentEnabled,
    "v24 migration did not enable nearby blessing complement or lost existing settings")
  d.blessingComplement = false
  fire("ADDON_LOADED", "BuffRadar")
  d = env.BuffRadarDB
  assert(d.dbVersion == 25 and not d.blessingComplement, "a current-version opt-out did not persist")
  d.blessingComplement = true
  d.plateRestore = { nameplateShowFriends = false, nameplateShowAll = true,
    [NS.X.friendlyPlateNamesCVar] = "0", nameplateShowEnemies = false }
  fire("ADDON_LOADED", "BuffRadar")
  d = env.BuffRadarDB
  assert(d.blessingComplement and d.plateRestore.nameplateShowFriends == false and d.plateRestore.nameplateShowAll == true
    and d.plateRestore[NS.X.friendlyPlateNamesCVar] == nil and d.plateRestore.nameplateShowEnemies == nil,
    "reloading lost valid options or accepted unsupported CVars")
  d.blessingComplement, d.plateRestore = false, {}
  NS.X.ApplyTheme("midnight")
  d.assignmentEnabled = false
  d.wizardSeen = false  -- leave the save as the rest of the suite expects
end)
step("ready check reports who is missing buffs (1.4.0)", function()
  if env.__forever then return end
  local cleanup = partyOfTwo()
  refresh()
  local n = #chat
  fire("READY_CHECK")
  assert(chatTemplate(n,"Ready check: %d %s missing buffs (%d buffs needed). /br announce posts the list.",3,NS.X.L["people are"]), "no ready-check summary")
  cleanup()
end)
step("local ready-check view retains independent coverage and exact responses", function()
  local cleanup = partyOfTwo("READY")
  local X, O = NS.X, env.__over
  local now = 100
  O.GetTime = function() return now end
  O.Aura = function(unit)
    if unit == "party1" then return { expirationTime = now + 15 } end
    if unit == "party2" then return end
    return nil
  end
  O.AuraList = function(unit) if unit == "party2" then error("unreadable aura") end end
  env.GetReadyCheckStatus = function(unit) return unit == "player" and "ready" or "waiting" end
  env.SlashCmdList.BUFFRADAR("ready show")
  refresh()
  local tally, armed = X.tally, shownRows().party1
  armed = armed and armed.row
  fire("READY_CHECK")
  local view = env.BuffRadarReadyCheck
  assert(view and view:IsShown() and view.summary:GetText():find(string.format(X.L["Waiting %d"], 2), 1, true))
  assert(view.rows[2].detail:GetText():find("15", 1, true), "expiry detail missing")
  assert(view.rows[3].detail:GetText():find(string.format(X.L["%s unavailable"], ""), 1, true), "unknown aura treated as missing")
  local current = shownRows().party1
  assert(X.tally == tally and (current and current.row) == armed, "ready check changed armed rows or scan tallies")
  fire("READY_CHECK_CONFIRM", "party1", false)
  assert(view.rows[2].label:GetText():find(X.L["Not ready"], 1, true), "decline lost")
  env.GetReadyCheckStatus = function() return nil end
  fire("READY_CHECK_FINISHED", false)
  assert(view:IsShown() and view.summary:GetText():find(string.format(X.L["No response %d"], 1), 1, true)
    and view.rows[2].label:GetText():find(X.L["Not ready"], 1, true), "finish cleared captured responses")
  now = now + 16
  X.ExpireReadyCheck()
  assert(not view:IsShown(), "finished ready check did not expire")
  fire("READY_CHECK")
  assert(view:IsShown(), "session opt-in lost")
  fire("READY_CHECK_FINISHED", true)
  assert(not view:IsShown(), "preempted ready check stayed visible")
  env.SlashCmdList.BUFFRADAR("ready hide")
  env.GetReadyCheckStatus = nil
  cleanup()
end)
step("group reports respect ignored players and chat refusal", function()
  local cleanup = partyOfTwo("REPORTCHAT")
  local X, O = NS.X, env.__over
  local oldChatInfo = env.C_ChatInfo
  local ok, err = pcall(function()
    env.SlashCmdList.BUFFRADAR("ignore Aaron")
    O.Aura = function() return nil end
    local sent = {}
    env.C_ChatInfo = {}
    env.C_ChatInfo.SendChatMessage = function(message, channel)
      sent[#sent + 1] = { message, channel }
    end
    X.Announce()
    assert(sent[1] and sent[1][2] == "PARTY" and not sent[1][1]:find("Aaron", 1, true),
      "modern chat failed or included ignored player")
    env.C_ChatInfo.SendChatMessage = function() error("chat denied") end
    local before, chatBefore = #env.__sent, #chat
    X.Announce()
    assert(#env.__sent == before and chatSince(chatBefore,NS.X.L["BuffRadar -- missing buffs: "]),
      "refused modern chat did not keep report local")
    assert(not X.SendGroupReport(string.rep("a", 256)), "oversized report reached chat API")
  end)
  env.C_ChatInfo = oldChatInfo
  env.SlashCmdList.BUFFRADAR("unignore Aaron")
  cleanup()
  assert(ok, err)
end)
step("coverage reports ignore cast restrictions and preserve bound rows", function()
  local cleanup = partyOfTwo("REPORT")
  local X, db, O = NS.X, env.BuffRadarDB, env.__over
  local oldRole, oldCooldown, oldRange = env.UnitGroupRolesAssigned, env.GetSpellCooldown, env.IsSpellInRange
  local oldFilter, oldCast, oldInclude, oldAssume = db.roleFilter, db.castMethod, db.includeSelf, db.assumeRange
  local ok, err = pcall(function()
    db.roleFilter, db.castMethod, db.includeSelf, db.assumeRange = "TANK", "target", false, false
    env.UnitGroupRolesAssigned = function(u) return u == "party2" and "TANK" or "DAMAGER" end
    env.IsSpellInRange = function() return 1 end
    O.Aura = function(u)
      if u == "player" then return { expirationTime = env.GetTime() + 600 } end
      return nil
    end
    refresh()
    local row = assert(shownRows().party2, "tank row not armed").row
    local original = assert(row.entry)
    local bound = row:GetAttribute("unit")
    local last = #chat
    fire("READY_CHECK")
    assert(row.entry == original and row.entry.unit == "party2" and row:GetAttribute("unit") == bound,
      "report changed live row metadata or secure unit")
    env.IsSpellInRange = function() return 0 end
    env.GetSpellCooldown = function() return env.GetTime(), 180 end
    fire("READY_CHECK")
    assert(chatTemplate(last,"Ready check: %d %s missing buffs (%d buffs needed). /br announce posts the list.",2,NS.X.L["people are"]), "cast restrictions hid known missing buffs")
    O.Aura = function(u)
      if u == "party1" then error("unreadable aura") end
      if u == "player" then return { expirationTime = env.GetTime() + 600 } end
      return nil
    end
    O.AuraList = function(u)
      if u == "party1" then error("unreadable aura list") end
    end
    last = #chat
    fire("READY_CHECK")
    assert(chatTemplate(last,"Ready check: %d %s missing buffs (%d buffs needed). /br announce posts the list.",1,NS.X.L["person is"])
      and chatTemplate(last,"Buff coverage could not be verified for %d player.",1), "ready report lost mixed known/unknown coverage")
    assert(not chatSince(last,NS.X.L["all checked buffs are present."]), "unverified player counted as buffed")
    O.Aura = function() return { expirationTime = env.GetTime() + 5 } end
    O.AuraList = nil
    last = #chat
    fire("READY_CHECK")
    assert(chatSince(last,NS.X.L["all checked buffs are present."]), "a present aura inside the rebuff window counted as missing")
  end)
  cleanup()
  db.roleFilter, db.castMethod, db.includeSelf, db.assumeRange = oldFilter, oldCast, oldInclude, oldAssume
  env.UnitGroupRolesAssigned, env.GetSpellCooldown, env.IsSpellInRange = oldRole, oldCooldown, oldRange
  assert(ok, err)
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
    assert(row.tag.text == NS.X.L["a buff just expired"], "expired tag text: " .. tostring(row.tag.text))
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
  if not NS.X.ApiCheck then return end -- optional Extras.lua
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
  if not NS.X.ApiCheck then return end -- optional Extras.lua
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
  NS.X.ShowExport(NS.X.Export(),false)
  local f = assert(env.BuffRadarExportFrame, "export frame not created")
  assert(f.shown, "export window not shown")
  local text = f.editBox.text
  assert(type(text) == "string" and text:sub(1, 3) == "BR1", "export string malformed")
  d.scale, d.sortMode, d.rebuffPer.CUSTOM_TEST = 1, "name", nil
  d.enabled.CUSTOM_TEST, d.ignored.Zed = nil, nil
  env.SlashCmdList.BUFFRADAR("import")
  f.editBox.text = text
  f.accept.scripts.OnClick(f.accept, "LeftButton")
  assert(d.scale == 1 and d.sortMode == "name" and f.apply:IsShown(), "preview applied settings")
  f.apply:Click()
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
    assert(not X.Import(input) and (not X.SettingsDiff or not X.SettingsDiff(input)), "invalid clipboard accepted: " .. i)
    assert(d.enabled.TEST and d.rebuffPer.TEST == 33 and d.ignored.Zed and d.scale == 1,
      "invalid clipboard changed settings: " .. i)
  end
  local old = empty:gsub("^BR1;complete=1;", "BR1;"):gsub(";endExport=1$", "")
  assert(X.Import(old) and not next(d.enabled) and not next(d.rebuffPer) and not next(d.ignored),
    "older complete clipboard did not clear intentionally empty tables")
  assert(X.Import(withData) and d.enabled.TEST and d.ignored.Zed, "framed clipboard round-trip failed")
  local current, currentRebuff, currentIgnore = d.enabled, d.rebuffPer, d.ignored
  -- Large but within schema limits: exercise the size cap independently of key validation.
  for i = 1, 180 do current["TEST_" .. i .. "_" .. string.rep("A", 24)] = true end
  local large = assert(X.Export(), "valid clipboard larger than named profile cap was refused")
  assert(#large > 4000 and X.Import(large), "valid large clipboard did not round-trip")
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
  assert(d.pointByChar[key] and table.concat(d.pointByChar[key], ",") == table.concat(d.point, ","),
    "stored position differs from the current point")
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
  fire("CHAT_MSG_ADDON", "BuffRadar", "CAST;SKYFURY;Player-1-P1S", "PARTY", "Zed-TestRealm")
  refresh()
  row2 = env.BuffRadarRow2
  assert(row2 and row2.entry and row2.entry.unit == "party2",
    "handled player did not sink: row2=" .. tostring(row2 and row2.entry and row2.entry.unit))
  local row3 = env.BuffRadarRow3
  assert(row3 and row3.entry and row3.entry.handled, "handled flag not set on Aaron's entry")
  if not env.__german then
    assert(row3.tag and row3.tag.shown and row3.tag.text == NS.X.L["being buffed"],
      "handled tag wrong: " .. tostring(row3.tag and row3.tag.text))
  end
  cleanup()
end)
step("group sync validates current party members and canonical realm names", function()
  local cleanup = partyOfTwo("V")
  local X, db, O = NS.X, env.BuffRadarDB, env.__over
  local sync, canAccess, assistant = db.sync, env.canaccessvalue, env.UnitIsGroupAssistant
  local leader = env.UnitIsGroupLeader
  env.UnitIsGroupLeader = function(u) return u == "party1" end
  local fullName, exists = O.UnitFullName, O.UnitExists
  db.sync = true
  O.UnitFullName = function(u)
    if u == "party1" then return "Tera", "Realm One" end
    if u == "party2" then return "Tera", "Realm Two" end
    return fullName(u)
  end
  env.UnitIsGroupAssistant = function(u) return u == "party2" end
  local key = env.__forever and "FORTITUDE" or "SKYFURY"
  local sent = #env.__addonSent
  fire("CHAT_MSG_ADDON", "BuffRadar", "HELLO;Tera", "PARTY", "Tera")
  assert(#env.__addonSent == sent, "ambiguous short name received a reply")
  fire("CHAT_MSG_ADDON", "BuffRadar", "HELLO;Tera-RealmOne", "WHISPER", "Tera-RealmOne")
  assert(#env.__addonSent == sent, "wrong transport received a reply")
  env.canaccessvalue = function(v) return v ~= "Tera-RealmOne" end
  fire("CHAT_MSG_ADDON", "BuffRadar", "HELLO;Tera", "PARTY", "Tera-RealmOne")
  assert(#env.__addonSent == sent, "unreadable sender received a reply")
  env.canaccessvalue = canAccess
  fire("CHAT_MSG_ADDON", "BuffRadar", "HERE;Tera-RealmOne", "PARTY", "Tera-RealmOne")
  fire("CHAT_MSG_ADDON", "BuffRadar", "HELLO;Tera-RealmTwo", "PARTY", "Tera-RealmTwo")
  assert(#env.__addonSent == sent + 1 and env.__addonSent[sent + 1].channel == "PARTY",
    "valid cross-realm party member did not receive a response")
  fire("CHAT_MSG_ADDON", "BuffRadar", "HELLO;Tera-RealmTwo", "PARTY", "Tera-RealmTwo")
  assert(#env.__addonSent == sent + 1, "duplicate presence ping was answered immediately")
  fire("CHAT_MSG_ADDON", "BuffRadar", "ASSIGN;" .. key .. ";Tera-RealmTwo", "PARTY", "Tera-RealmTwo")
  assert(X.assign[key] == "Tera-RealmTwo", "valid assistant assignment was ignored")
  fire("CHAT_MSG_ADDON", "BuffRadar", "COVER;Tera-RealmTwo", "PARTY", "Tera-RealmTwo")
  assert(X.cover["Tera-RealmTwo"], "cover was not stored under canonical roster name")
  fire("CHAT_MSG_ADDON", "BuffRadar", "BACK;Tera-RealmOne", "PARTY", "Tera-RealmOne")
  assert(X.cover["Tera-RealmTwo"], "return from another realm cleared the wrong cover")
  O.UnitExists = function(u) return u ~= "party2" and exists(u) end
  fire("GROUP_ROSTER_UPDATE")
  assert(not X.peers["tera-realmtwo"] and not X.cover["Tera-RealmTwo"], "departed peer was retained")
  db.sync, env.UnitIsGroupAssistant, env.UnitIsGroupLeader = sync, assistant, leader
  cleanup()
  fire("GROUP_ROSTER_UPDATE")
end)
step("group sync accepts current raid traffic and rejects unreadable authority", function()
  local X, db, O = NS.X, env.BuffRadarDB, env.__over
  local sync, raid, leader, assistant = db.sync, env.IsInRaid, env.UnitIsGroupLeader, env.UnitIsGroupAssistant
  local canAccess, roster, size = env.canaccessvalue, env.GetRaidRosterInfo, env.GetNumGroupMembers
  local exists, fullName, isUnit, guid = O.UnitExists, O.UnitFullName, O.UnitIsUnit, O.UnitGUID
  O.UnitGUID = function(u) return u == "raid1" and "Player-Me" or u == "raid2" and "Player-Lian" end
  local protected = {}
  db.sync = true
  env.IsInRaid = function() return true end
  env.GetNumGroupMembers = function() return 2 end
  O.UnitExists = function(u) return u == "player" or u == "raid1" or u == "raid2" end
  O.UnitFullName = function(u)
    if u == "player" or u == "raid1" then return "Me", "TestRealm" end
    if u == "raid2" then return "Lian", "OtherRealm" end
  end
  O.UnitIsUnit = function(a, b) return a == b or a == "raid1" and b == "player" end
  env.UnitIsGroupLeader, env.UnitIsGroupAssistant = nil, nil
  env.GetRaidRosterInfo = function() return "Lian-OtherRealm", protected end
  env.canaccessvalue = function(v) return v ~= protected end
  local key = env.__forever and "FORTITUDE" or "SKYFURY"
  fire("CHAT_MSG_ADDON", "BuffRadar", "ASSIGN;" .. key .. ";Lian", "RAID", "Lian-OtherRealm")
  assert(not X.assign[key] and not X.peers["lian-otherrealm"], "unreadable rank changed state")
  env.GetRaidRosterInfo = function(i) return i == 2 and "Lian-OtherRealm" or "Me-TestRealm", i == 1 and 2 or 1 end
  fire("CHAT_MSG_ADDON", "BuffRadar", "ASSIGN;" .. key .. ";Lian", "RAID", "Lian-OtherRealm")
  assert(X.assign[key] == "Lian" and X.peers["lian-otherrealm"], "readable raid assistant was ignored")
  X.SetLocalPlan("ASSIGN", key, nil)
  X.peers["lian-otherrealm"] = nil
  db.sync, env.IsInRaid = sync, raid
  env.UnitIsGroupLeader, env.UnitIsGroupAssistant = leader, assistant
  env.canaccessvalue, env.GetRaidRosterInfo, env.GetNumGroupMembers = canAccess, roster, size
  O.UnitExists, O.UnitFullName, O.UnitIsUnit, O.UnitGUID = exists, fullName, isUnit, guid
end)
step("caster coordination checks roster authority, drafts, acceptance and acknowledgement", function()
  if not env.__forever then return end
  local cleanup = partyOfTwo("Coord")
  local X, db, O, slash = NS.X, env.BuffRadarDB, env.__over, env.SlashCmdList.BUFFRADAR
  local sync, size, leader, assist = db.sync, env.GetNumGroupMembers, env.UnitIsGroupLeader, env.UnitIsGroupAssistant
  local send = env.SendAddonMessage
  local prior = X.assign.FORTITUDE
  local ok, err = pcall(function()
    db.sync, X.assign.FORTITUDE = true, nil
    env.GetNumGroupMembers = function() return 3 end
    env.UnitIsGroupAssistant = function() return false end
    env.UnitIsGroupLeader = function(unit) return unit == "party1" end
    local peers, nextEpoch = {}, 0
    local function scopedPayload(packet)
      return packet:match("^SYNC;3;D;[^;]+;[^;]+;%d+;(.+)$")
    end
    local function inbound(message, source, channel)
      source, channel = source or "Aaron-TestRealm", channel or "PARTY"
      -- Derive the current scope from real outbound data and act as a single mock peer.
      -- The two-client suite captures actual proof packets and tests both runtimes.
      local me = O.UnitGUID("player")
      local before = #env.__addonSent
      X.SyncSend("FORTITUDE", me)
      assert(#env.__addonSent == before + 1, "could not obtain current scope from a cast")
      local digest = table.remove(env.__addonSent).msg:match("^SYNC;3;D;([^;]+);")
      assert(digest, "outbound scope was missing")
      local peer = peers[source]
      if not peer or peer.digest ~= digest then
        nextEpoch = nextEpoch + 1
        peer = { digest = digest, epoch = string.format("%024x", nextEpoch), seq = 0 }
        peers[source] = peer
      end
      peer.seq = peer.seq + 1
      fire("CHAT_MSG_ADDON", "BuffRadar",
        string.format("SYNC;3;D;%s;%s;%d;COORD;1;%s", digest, peer.epoch, peer.seq, message), channel, source)
      local reply = env.__addonSent[before + 1]
      local challenge = reply and reply.msg:match("^SYNC;3;Q;[^;]+;[^;]+;([^;]+);")
      if challenge then
        assert(channel == "PARTY", "wrong-channel request received a scope challenge")
        table.remove(env.__addonSent, before + 1)
        fire("CHAT_MSG_ADDON", "BuffRadar",
          string.format("SYNC;3;P;%s;%s;%s;%s;%d", digest, peer.epoch, challenge, me, peer.seq), channel, source)
      end
    end
    local sent = #env.__addonSent
    inbound("REQ;1.1")
    assert(#env.__addonSent == sent, "opt-out caster sent a report")
    slash("coordinate on")
    inbound("REQ;1.1", "Zed-TestRealm")
    inbound("REQ;1.1", nil, "WHISPER")
    assert(#env.__addonSent == sent, "untrusted or wrong-channel request was answered")
    inbound("REQ;1.1")
    assert(#env.__addonSent == sent + 1 and env.__addonSent[sent + 1].msg:find("FORTITUDE", 1, true),
      "trusted request did not return learned Fortitude: " .. tostring(env.__addonSent[sent + 1] and env.__addonSent[sent + 1].msg))
    local guid = O.UnitGUID("player")
    local payload = "PLAN;1.1;10.2;" .. guid .. ";FORTITUDE"
    inbound(payload, "Zed-TestRealm")
    slash("coordinate inbox")
    slash("coordinate accept")
    assert(#env.__addonSent == sent + 1 and not X.CoordinatedHolder("FORTITUDE"), "nonleader plan was accepted")
    inbound(payload)
    local pending = X.CoordinationSnapshot()
    assert(pending.pending.name == "Aaron-TestRealm" and pending.pending.keys[1] == "FORTITUDE"
      and not pending.pending.reviewed and pending.nextRefreshAt > env.GetTime(), "recipient snapshot omitted pending details")
    slash("coordinate accept")
    assert(#env.__addonSent == sent + 1, "unreviewed plan was acknowledged")
    slash("coordinate inbox")
    slash("coordinate accept")
    assert(#env.__addonSent == sent + 2 and scopedPayload(env.__addonSent[sent + 2].msg) == "COORD;1;ACK;10.2",
      "accepted plan did not acknowledge the exact revision")
    assert(X.CoordinatedHolder("FORTITUDE") and not X.assign.FORTITUDE,
      "accepted duty did not remain isolated from manual assignments: " .. tostring(X.CoordinatedHolder("FORTITUDE") or nil)
        .. "/" .. tostring(X.assign.FORTITUDE) .. "/" .. chat[#chat])
    inbound("PLAN;1.1;9.9;" .. guid .. ";FORTITUDE")
    slash("coordinate inbox")
    slash("coordinate accept")
    assert(#env.__addonSent == sent + 2, "stale plan revision allowed another acknowledgement")
    inbound("PLAN;1.1;10.3;" .. guid .. ";-")
    slash("coordinate inbox")
    local priorClick = X.CoordinationSnapshot()
    env.SendAddonMessage = function() return false end
    slash("coordinate accept")
    assert(X.CoordinatedHolder("FORTITUDE") and #env.__addonSent == sent + 2, "failed ACK discarded accepted duties")
    env.SendAddonMessage = send
    slash("coordinate accept")
    assert(not X.CoordinatedHolder("FORTITUDE") and #env.__addonSent == sent + 3,
      "reviewed empty replacement did not clear prior duties")
    inbound("PLAN;1.1;10.4;" .. guid .. ";FORTITUDE")
    slash("coordinate inbox")
    X.Coordinate("accept", nil, priorClick.token)
    assert(#env.__addonSent == sent + 3, "old UI click accepted a newer reviewed plan")
    slash("coordinate accept")
    env.UnitIsGroupLeader = function(unit) return unit == "party2" end
    env.UnitIsGroupAssistant = function(unit) return unit == "party1" end
    fire("PARTY_LEADER_CHANGED")
    assert(not X.CoordinatedHolder("FORTITUDE") and not X.CoordinationSnapshot().active,
      "an old leader kept accepted duties after becoming assistant")
    slash("coordinate off")
    assert(not X.CoordinatedHolder("FORTITUDE"), "opt-out retained the accepted duty")

    env.UnitIsGroupLeader = function(unit) return unit == "player" end
    env.UnitIsGroupAssistant = function() return false end
    slash("coordinate on")
    slash("coordinate request")
    local request = scopedPayload(env.__addonSent[#env.__addonSent].msg):match("^COORD;1;REQ;(.+)$")
    assert(request, "leader could not request reports")
    inbound("REPORT;" .. request .. ";" .. guid .. ";ARCANE_INTELLECT")
    X.assign.FORTITUDE = "Zed-TestRealm"
    slash("coordinate need THORNS")
    slash("coordinate review")
    local reviewed = X.CoordinationSnapshot()
    assert(reviewed.active and reviewed.leader and reviewed.reportRequest and reviewed.canPublish
      and reviewed.draft and #reviewed.reports == 3, "leader snapshot omitted the reviewed draft or roster replies")
    sent = #env.__addonSent
    slash("coordinate publish")
    local plan = env.__addonSent[sent + 1]
    assert(plan and plan.msg:match(";" .. O.UnitGUID("party1"):gsub("%-", "%%-") .. ";ARCANE_INTELLECT$"),
      "reviewed plan did not route learned buff to its reporting caster")
    assert(not X.CoordinatedHolder("FORTITUDE") and X.assign.FORTITUDE == "Zed-TestRealm",
      "published plan overwrote a manual duty")
    local revision = scopedPayload(plan.msg):match("^COORD;1;PLAN;[%d.]+;([%d.]+);")
    inbound("ACK;" .. revision, "Zed-TestRealm")
    slash("coordinate status")
    assert(chat[#chat]:find(NS.X.L["Awaiting acknowledgement"], 1, true), "unassigned member forged an acknowledgement")
    inbound("ACK;" .. revision)
    local acknowledged
    for _, row in ipairs(X.CoordinationSnapshot().sent) do
      if row.name == "Aaron-TestRealm" and row.status == "acknowledged" then acknowledged = true end
    end
    assert(acknowledged, "snapshot omitted accepted acknowledgement")
    slash("coordinate status")
    assert(chat[#chat]:find(NS.X.L["Acknowledged"], 1, true), "expected caster did not acknowledge the outbox revision")

    local currentTime, deadline = O.GetTime, env.GetTime() + 181
    O.GetTime = function() return deadline end
    local expired = X.CoordinationSnapshot()
    assert(not expired.reportRequest and not expired.draft and #expired.sent == 0,
      "expired coordination data remained visible or actionable")
    O.GetTime = currentTime

    slash("coordinate review")
    local oldPublish = X.CoordinationSnapshot()
    env.UnitIsGroupLeader = function(unit) return unit == "party1" end
    env.UnitIsGroupAssistant = function(unit) return unit == "player" end
    sent = #env.__addonSent
    X.Coordinate("publish", nil, oldPublish.token)
    assert(#env.__addonSent == sent and not X.CoordinationSnapshot().draft
      and #X.CoordinationSnapshot().sent == 0, "same-roster handoff left the old publish action active")
    env.UnitIsGroupLeader = function(unit) return unit == "player" end
    env.UnitIsGroupAssistant = function() return false end
    slash("coordinate on")
    slash("coordinate request")
    slash("coordinate review")
    local oldGUID = O.UnitGUID
    O.UnitGUID = function(unit) if unit == "party1" then return "Player-1-Replaced" end return oldGUID(unit) end
    fire("GROUP_ROSTER_UPDATE")
    sent = #env.__addonSent
    slash("coordinate publish")
    assert(#env.__addonSent == sent, "replacement with a same-name member received the old plan")
  end)
  slash("coordinate off")
  env.SendAddonMessage = send
  db.sync, env.GetNumGroupMembers, env.UnitIsGroupLeader, env.UnitIsGroupAssistant = sync, size, leader, assist
  X.assign.FORTITUDE = prior
  cleanup()
  assert(ok, err)
end)
step("Forever caster coordination panel sends reviewed actions and drops obsolete controls", function()
  if not env.__forever then return end
  local X = NS.X
  local snapshot, coordinate, peerSnapshot = X.CoordinationSnapshot, X.Coordinate, X.SyncPeerSnapshot
  local model = { available = true, generation = 1, token = 11, leader = true }
  local actions = {}
  local ok, err = pcall(function()
    local readOnly
    X.CoordinationSnapshot = function(read) readOnly=read; return model end
    X.SyncPeerSnapshot = function() return { members={ {name="Aaron",status="verified"},
      {name="Bela",status="awaiting"}, {name="Cato",status="retrying"},
      {name="Dena",status="unverified"}, {name="Eryn",status="incompatible"},
      {name="Fara",status="verified"} } } end
    X.Coordinate = function(action, arg, token)
      assert(token == model.token, "panel did not forward current action token")
      actions[#actions + 1] = action
      if action == "on" then model.active, model.canRequest = true, true
      elseif action == "request" then model.reportRequest = true
      elseif action == "need" then assert(arg == "FORTITUDE", "buff key edit lost the argument")
      elseif action == "review" then
        model.draft, model.canPublish = { { key = "FORTITUDE", before = "Unassigned", after = "Aaron" } }, true
      elseif action == "publish" then
        model.draft, model.canPublish = nil, false
        model.sent = { { name = "Aaron", status = "acknowledged" } }
      elseif action == "inbox" then model.pending.reviewed = true
      elseif action == "accept" then model.pending, model.accepted = nil, { keys = { "FORTITUDE" } }
      end
    end
    X.OpenAssignments()
    env.BuffRadarAssignments.coordinationButton:Click()
    local view = env.BuffRadarCasterCoordination
    assert(view and view:IsVisible() and view.participation:GetText() == NS.X.L["Opt In"], "panel could not open while opted out")
    assert(view.tabs.peers:IsVisible(), "peer diagnostics require plan opt-in")
    view.tabs.peers:Click()
    assert(readOnly and view.rows[1].detail:GetText()==X.L["Verified"]
      and view.rows[2].detail:GetText()==X.L["Awaiting verification reply"]
      and view.rows[3].detail:GetText()==X.L["Retrying verification"]
      and view.rows[4].detail:GetText()==X.L["Not verified / no response"]
      and view.rows[5].detail:GetText()==X.L["Incompatible protocol"]
      and not view.publish:IsVisible() and #actions==0, "peer rows lost state or issued plan actions")
    view.next:Click()
    assert(view.rows[1].title:GetText()=="Fara", "peer pagination lost roster entries")
    view.tabs.inbox:Click()
    view.participation:Click()
    assert(view.participation:GetText() == NS.X.L["Opt Out"] and view.request:IsVisible(), "leader controls did not open")
    model.reports = { { name = "Aaron", keys = { "FORTITUDE" } }, { name = "Zed" } }
    view.request:Click()
    assert(view.rows[1].detail:GetText() == "FORTITUDE" and view.rows[2].detail:GetText() == NS.X.L["No response"],
      "reports did not distinguish replies")
    view.need:SetText("FORTITUDE")
    view.add:Click()
    assert(actions[#actions] == "need", "manual buff demand was not sent")
    view.review:Click()
    assert(view.publish:IsVisible() and view.publish:IsEnabled() and view.rows[1].detail:GetText():find("Aaron", 1, true),
      "review did not show the draft and publication action")
    view.publish:Click()
    view.tabs.delivery:Click()
    assert(view.rows[1].detail:GetText() == NS.X.L["Acknowledged"], "delivery did not reflect the acknowledgement")

    view.tabs.reports:Click()
    view.need:SetText("STALE")
    model = { available = true, active = true, leader = false, generation = 2, token = 22,
      pending = { name = "Aaron", keys = { "FORTITUDE" }, reviewed = false } }
    X.QueueCoordinationRefresh()
    assert(view.tabs.peers:IsVisible() and not view.tabs.draft:IsVisible() and not view.publish:IsVisible() and view.need:GetText() == "",
      "authority change left stale leader controls or input")
    assert(view.rows[1].title:GetText():find("Aaron", 1, true) and not view.accept:IsEnabled(),
      "incoming plan lacked sender or allowed unreviewed acceptance")
    view.inbox:Click()
    view.accept:Click()
    assert(actions[#actions] == "accept" and view.rows[2].title:GetText():find("FORTITUDE", 1, true),
      "reviewed plan could not be accepted")
    model = { available = false, reason = "Roster information is unavailable.", generation = 3, token = 33 }
    X.QueueCoordinationRefresh()
    assert(not view.rows[1]:IsShown() and not view.rows[2]:IsShown() and not view.accept:IsVisible() and not view.participation:IsEnabled(),
      "unavailable roster left stale plan rows or actions")
    env.__combat = true
    fire("PLAYER_REGEN_DISABLED")
    local cfg = env.BuffRadarConfig
    cfg:GetScript("OnEvent")(cfg, "PLAYER_REGEN_DISABLED")
    assert(not view:IsVisible(), "coordination panel stayed visible in combat")
  end)
  X.CoordinationSnapshot, X.Coordinate, X.SyncPeerSnapshot = snapshot, coordinate, peerSnapshot
  env.__combat = false
  env.BuffRadarConfig:Hide()
  fire("PLAYER_REGEN_ENABLED")
  assert(ok, err)
end)
step("Forever subgroup panel previews drafts, preserves modes and rejects stale overrides", function()
  if not env.__forever then return end
  local X = NS.X
  local originals = { X.InRaid, X.SubgroupDutyOptions, X.GetSubgroupDuty, X.SetSubgroupDuty, X.PreviewSubgroupDuty }
  local raid, writes = true, 0
  local saved = {}
  local ok, err = pcall(function()
    X.InRaid = function() return raid end
    X.SubgroupDutyOptions = function()
      return { { key = "FORTITUDE", name = "Power Word: Fortitude" }, { key = "THORNS", name = "Thorns" } }
    end
    local function copy(source)
      if not source then return nil end
      local result = {}
      for group in pairs(source) do result[group] = true end
      return result
    end
    X.GetSubgroupDuty = function(key) return copy(saved[key]) end
    X.SetSubgroupDuty = function(key, groups)
      saved[key], writes = copy(groups), writes + 1
      X.QueueSubgroupDutyRefresh(key)
      return true
    end
    X.PreviewSubgroupDuty = function(key, groups)
      return { members = { { name = key == "FORTITUDE" and "Aaron" or "Zed", subgroup = 2,
        status = not groups and "eligible" or groups[2] and "eligible" or "excluded",
        spell = "Power Word: Fortitude", fallback = groups and "Single-target fallback" or nil,
        group = not groups and "Prayer of Fortitude" or nil } } }
    end
    X.OpenRaidCoverage()
    env.BuffRadarRaidCoverage.subgroupButton:Click()
    local view = env.BuffRadarSubgroupResponsibilities
    assert(view and view:IsVisible() and not env.BuffRadarRaidCoverage:IsVisible(), "coverage launcher did not open the panel")
    assert(view.scope:GetText() == NS.X.L["All Groups"] and view.rows[1].detail:GetText():find("Prayer of Fortitude", 1, true),
      "unrestricted preview omitted the group option")
    view.buff:Click()
    assert(view.rows[1].title:GetText():find("Zed", 1, true), "buff selector did not change the preview")
    view.buff:Click()
    view.groups[2]:SetChecked(false)
    view.groups[2]:Click()
    assert(writes == 0 and view.scope:GetText() == NS.X.L["Selected Groups"]
      and view.rows[1].title:GetText():find(NS.X.L["Outside Selected Groups"], 1, true)
      and view.rows[1].detail:GetText():find(NS.X.L["fallback"], 1, true), "draft changed the saved duty or omitted fallback status")
    view.groups[2]:SetChecked(true)
    view.groups[2]:Click()
    assert(view.scope:GetText() == NS.X.L["Selected Groups"] and view.apply:IsEnabled(), "explicit eight became unrestricted")
    view.apply:Click()
    assert(writes == 1 and saved.FORTITUDE[2], "apply did not save the explicit group list")
    view.none:Click()
    assert(writes == 1 and view.scope:GetText() == NS.X.L["No Groups"], "No Groups did not stage an empty selection")
    view.apply:Click()
    assert(writes == 2 and saved.FORTITUDE and not next(saved.FORTITUDE), "empty restriction was not saved")
    view.all:Click()
    assert(view.scope:GetText() == NS.X.L["All Groups"] and saved.FORTITUDE, "All Groups did not stage unrestricted mode")
    saved.FORTITUDE = { [3] = true }
    view.apply:Click()
    assert(writes == 2 and saved.FORTITUDE[3] and view.notice:GetText():find("changed", 1, true),
      "Apply overwrote a newer slash edit")
    view.all:Click()
    view.apply:Click()
    assert(writes == 3 and saved.FORTITUDE == nil, "All Groups did not clear the restriction")
    view.none:Click()
    view.cancel:Click()
    assert(writes == 3 and not view:IsVisible() and env.BuffRadarRaidCoverage:IsVisible(), "Cancel wrote a draft or failed to return")
    X.OpenSubgroupResponsibilities()
    raid = false
    view.refresh:Click()
    assert(not view:IsVisible(), "draft survived leaving the raid")
  end)
  X.InRaid, X.SubgroupDutyOptions, X.GetSubgroupDuty, X.SetSubgroupDuty, X.PreviewSubgroupDuty = unpack(originals)
  if env.BuffRadarConfig then env.BuffRadarConfig:Hide() end
  assert(ok, err)
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
  env.C_Spell = { GetSpellIDForSpellIdentifier = function() return 462854 end }
  env.__addonSent = {}
  clickCast(row, "cast-sync", 462854, "Aaron", nil, "UNIT_SPELLCAST_SUCCEEDED", true)
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
    assert(row.tag and row.tag.text == NS.X.L["asked for a buff"],
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
  assert(chatTemplate(n,"%s: %d %s missing buffs (%d buffs needed).",NS.X.L["Joined a group"],3,NS.X.L["people are"]), "no join summary printed")
  local n2 = #chat
  fire("CHALLENGE_MODE_START")
  assert(chatTemplate(n2,"%s: %d %s missing buffs (%d buffs needed).",NS.X.L["Run starting"],3,NS.X.L["people are"]), "no run-start summary")
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
  if env.__ticker then timerTick() else NS.X.UpdateFade() end
  assert(env.BuffRadarFrame.alpha == 0.5, "window did not fade: " .. tostring(env.BuffRadarFrame.alpha))
  env.__mouseOver = true
  if env.__ticker then timerTick() else NS.X.UpdateFade() end
  assert(env.BuffRadarFrame.alpha == 1, "window did not unfade under the mouse")
  env.__mouseOver = false
  env.SlashCmdList.BUFFRADAR("fade 0")
  if env.__ticker then timerTick() else NS.X.UpdateFade() end
  assert(env.BuffRadarFrame.alpha == 1, "window stayed faded with fading off")
end)
step("all-buffed pill replaces the window (1.6.0)", function()
  local cleanup = partyOfTwo("P")
  local X = NS.X
  local oldSize, oldRange, oldCooldown = env.GetNumGroupMembers, env.IsSpellInRange, env.GetSpellCooldown
  local oldPlates = X.FriendlyPlatesOn
  env.GetNumGroupMembers = function() return 3 end
  X.FriendlyPlatesOn = function() return true end
  env.SlashCmdList.BUFFRADAR("pill")
  assert(env.BuffRadarDB.pill == true, "pill setting not stored")
  local function buffed() return { expirationTime = env.GetTime() + 600 } end
  env.__over.Aura = function(u) if u ~= "party1" then return buffed() end return nil end
  env.IsSpellInRange = function() return 0 end
  refresh()
  local hidNeed = env.BuffRadarPill.shown
  env.IsSpellInRange = function() return 1 end
  env.GetSpellCooldown = function() return env.GetTime(), 180 end
  refresh()
  local hidCooldown = env.BuffRadarPill.shown
  env.GetSpellCooldown = oldCooldown
  env.SlashCmdList.BUFFRADAR("find Nobody")
  refresh()
  local hidByFinder = env.BuffRadarPill.shown
  local explainedFinder = X.EmptyStatus() == X.L["The name finder hides all buff targets."]
  env.SlashCmdList.BUFFRADAR("find")
  env.__over.Aura = function(u) if u == "party1" then error("by-name restricted") end return buffed() end
  env.__over.AuraList = function(u) if u == "party1" then error("index restricted") end end
  refresh()
  local hidUnknown = env.BuffRadarPill.shown
  env.__over.Aura, env.__over.AuraList = buffed, nil
  env.GetNumGroupMembers = function() return 4 end
  refresh()
  local hidIncomplete = env.BuffRadarPill.shown
  env.GetNumGroupMembers = function() return 3 end
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
  X.FriendlyPlatesOn = oldPlates
  env.GetNumGroupMembers, env.IsSpellInRange = oldSize, oldRange
  assert(not hidNeed and not hidCooldown and not hidByFinder and not hidUnknown and not hidIncomplete,
    "all-buffed pill hid known buff needs or an incomplete reading")
  assert(explainedFinder, "an empty filtered list did not explain the name finder")
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
  local spellID = env.__forever and 1244 or 462854
  env.C_Spell = { GetSpellIDForSpellIdentifier = function() return spellID end }
  clickCast(row, "cast-queue", spellID, "Aaron", nil, "UNIT_SPELLCAST_SUCCEEDED", true)
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
    assert(tagged.tag and tagged.tag.text == NS.X.L["up next"],
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
  assert(chatSince(n, NS.X.L["Usage: /br preset raid|dungeon|solo"]), "bad preset not rejected")
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
      return { { name = "Flask of the Titans", spellId = 17626, expirationTime = env.GetTime() + 600 },
               { name = "Well Fed", spellId = 19705, expirationTime = env.GetTime() + 600 } }
    end
    return {}
  end
  refresh()
  local cover
  local labels = NS.X.L
  for _, fs in ipairs(env.__fontstrings) do
    if type(fs.text) == "string" and fs.text:find(labels["Flask"] .. " ", 1, true) then cover = fs.text end
  end
  assert(cover, "no consumables on the coverage line")
  assert(cover:find(labels["Flask"] .. " 1/3", 1, true), "flask count wrong: " .. cover)
  assert(cover:find(labels["Food"] .. " 1/3", 1, true), "food count wrong: " .. cover)
  if not env.__forever then
    assert(cover:find(env.__german and (labels["Rune"] .. " · " .. string.format(labels["%d unknown"], 3)) or "Rune 0/3", 1, true), "rune count wrong: " .. cover)
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
    assert(aRow2.tag and aRow2.tag.text == NS.X.L["assigned elsewhere"],
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
  fire("CHAT_MSG_ADDON", "BuffRadar", "HELLO;Aaron-TestRealm", "PARTY", "Aaron-TestRealm")
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
  fire("PLAYER_ALIVE")
  local releaseSent = #env.__addonSent
  for i = sent0 + 1, releaseSent do
    assert(not env.__addonSent[i].msg:find("BACK;", 1, true), "releasing sent a premature return")
  end
  fire("PLAYER_UNGHOST")
  env.__over.UnitIsDeadOrGhost = function() return false end
  timerTick()
  local backMsg
  for i = releaseSent + 1, #env.__addonSent do
    if env.__addonSent[i].msg:find("BACK;", 1, true) then backMsg = true end
  end
  assert(backMsg, "my return was not announced after the living flag recovered")
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
    if localizedMatch(env.__sent[i].msg,"BuffRadar ready check: %d %s missing buffs (%d buffs needed).%s") then posted = env.__sent[i] end
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
  fire("CHAT_MSG_ADDON", "BuffRadar", "HELLO;Aaron-TestRealm", "PARTY", "Aaron-TestRealm")
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
  env.GetInventoryItemID = function(_, slot) return slot == 16 and 12345 or 42 end
  env.GetItemInfoInstant = function(id) return id, nil, nil, id == 12345 and "INVTYPE_WEAPON" or "INVTYPE_SHIELD", nil, id == 12345 and 2 or 4 end
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
  env.GetInventoryItemID, env.GetItemInfoInstant = nil, nil
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
  assert(chatTemplate(n0,"Entered the %s with buffs missing: %d %s still need buffs (%d buffs needed).",NS.X.L["dungeon"]), "no entry reminder")
  local n1 = #chat
  fire("ZONE_CHANGED_NEW_AREA")
  assert(not chatTemplate(n1,"Entered the %s with buffs missing: %d %s still need buffs (%d buffs needed).",NS.X.L["dungeon"]), "entry reminder repeated while inside")
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
    if type(fs.text) == "string" and localizedMatch(fs.text,"%s <5m on %d/%d",nil) then line = fs.text end
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
  local main = env.__forever and "Power Word: Fortitude" or "Skyfury"
  local spellID = env.__forever and 1244 or 462854
  env.C_Spell = { GetSpellIDForSpellIdentifier = function() return spellID end }
  clickCast(row, "cast-history", spellID, "Aaron", nil, "UNIT_SPELLCAST_SUCCEEDED", true)
  env.C_Spell = nil
  assert(#db.history == 1, "cast not recorded in history")
  assert(db.history[1].spell == main, "history spell: " .. tostring(db.history[1].spell))
  assert(db.history[1].who == "Aaron", "history target: " .. tostring(db.history[1].who))
  env.SlashCmdList.BUFFRADAR("resetcount")
  assert(#db.history == 0, "history not cleared by resetcount")
  cleanup()
end)

step("adaptive cooldown-sweep throttle toggles for large groups (1.7.0)", function()
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
step("delayed event refreshes coalesce without a recurring ticker", function()
  if env.__ticker then return end
  local oldZone, oldPauseCity = env.__zone, env.BuffRadarDB.pauseInCities
  env.BuffRadarDB.pauseInCities = true
  env.__zone = "Elwynn Forest"
  timerTick()
  local before = env.__zoneCalls
  fire("UNIT_AURA", "player")
  fire("GROUP_ROSTER_UPDATE")
  fire("SPELL_UPDATE_COOLDOWN")
  assert(#env.__timers == 1, "event burst scheduled more than one delayed refresh")
  runQueued()
  assert(env.__zoneCalls > before, "coalesced event refresh did not scan")
  local stable = env.__zoneCalls
  assert(not driver.scripts.OnUpdate, "core registered a frame update")
  for _ = 1, 40 do if env.__ticker then env.__ticker() end end
  assert(env.__zoneCalls == stable, "no-ticker setup performed a periodic player scan")
  env.__zone, env.BuffRadarDB.pauseInCities = oldZone, oldPauseCity
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
  assert(chatTemplate(n,"Theme: %s","Crimson"), "no theme message")
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

step("window palette presets use their approved colors and labels", function()
  local X, db = NS.X, env.BuffRadarDB
  local slash = env.SlashCmdList.BUFFRADAR
  local palettes = {
    { "ui.elvui", "ElvUI", { 20, 20, 20 }, { 96, 96, 96 } },
    { "ui.ellesmereui", "EllesmereUI", { 21, 25, 37 }, { 220, 167, 127 } },
    { "ui.anoui", "AnoUI+", { 24, 21, 31 }, { 163, 147, 219 } },
    { "ui.wicks", "Wick's UI", { 16, 28, 35 }, { 118, 174, 194 } },
    { "ui.ultimateforever", "Ultimate Forever UI", { 35, 27, 19 }, { 177, 138, 83 } },
    { "ui.foreverforge", "ForeverForge UI", { 24, 29, 39 }, { 189, 140, 85 } },
    { "ui.daylightui", "DaylightUI", { 20, 20, 23 }, { 55, 55, 62 } },
    { "ui.meredanui", "MeredanUI", { 22, 19, 15 }, { 97, 77, 46 } },
    { "ui.nazgrelui", "NazgrelUI", { 23, 26, 33 }, { 56, 61, 74 } },
    { "ui.reforgedui", "Reforged UI", { 33, 27, 21 }, { 136, 117, 74 } },
  }
  local frame, alpha = env.BuffRadarFrame, db.bgAlpha
  local appliedBackground = nil
  local setBackdropColor = frame.SetBackdropColor
  frame.SetBackdropColor = function(self, r, g, b, a)
    appliedBackground = { r, g, b, a }
    return setBackdropColor(self, r, g, b, a)
  end
  local wasOpen = env.BuffRadarConfig and env.BuffRadarConfig:IsShown()
  X.OpenConfig(true)
  local button = assert(env.BuffRadarConfig.themeBtn)
  for _, palette in ipairs(palettes) do
    local n = #chat
    slash("theme " .. palette[1]:upper())
    assert(db.theme == palette[1] and chatTemplate(n,"Theme: %s",palette[2]), "wrong palette selection")
    for component = 1, 3 do
      assert(db.bgColor[component] == palette[3][component] / 255
          and appliedBackground[component] == db.bgColor[component]
          and frame.borderColor[component] == palette[4][component] / 255,
        "incorrect swatch for " .. palette[1])
    end
    assert(appliedBackground[4] == alpha, "theme changed background opacity")
    local restored = X.Settings.Sanitize({ theme = palette[1], bgColor = db.bgColor })
    assert(restored.theme == palette[1], "sanitizer discarded " .. palette[1])
  end
  slash("theme parchment")
  local function nextTheme()
    local before = db.theme
    button.scripts.OnClick(button)
    local preview = assert(env.BuffRadarThemePreview)
    preview.next:Click()
    assert(db.theme == before, "preview changed saved theme before Apply")
    preview.apply:Click()
  end
  for _, palette in ipairs(palettes) do
    nextTheme()
    assert(db.theme == palette[1] and button:GetText() == string.format(NS.X.L["Theme: %s"],palette[2]),
      "settings skipped or mislabeled " .. palette[1])
  end
  nextTheme()
  assert(db.theme == "ui.auto" and button:GetText() == string.format(NS.X.L["Theme: %s"],NS.X.L["Auto"]),
    "settings omitted Auto or changed its compact label")
  nextTheme()
  assert(db.theme == "custom", "settings omitted custom colors")
  nextTheme()
  assert(db.theme == "midnight", "settings omitted the original first theme on wrap")
  frame.SetBackdropColor = setBackdropColor
  if not wasOpen then env.BuffRadarConfig:Hide() end
end)

step("window palettes survive reload and profile round trips without masking saved themes", function()
  local X, db = NS.X, env.BuffRadarDB
  local slash = env.SlashCmdList.BUFFRADAR
  local savedThemes = db.customThemes
  db.customThemes = {
    { name = "UI.ELVUI", bg = { 0.1, 0.2, 0.3 }, border = { 1, 1, 1 } },
    { name = "ElvUI", bg = { 0.3, 0.2, 0.1 }, border = { 0.1, 0.2, 0.3 } },
  }
  slash("theme ui.elvui")
  fire("ADDON_LOADED", "BuffRadar")
  db = env.BuffRadarDB
  assert(env.BuffRadarDB.theme == "ui.elvui" and X.ThemeBorder()[1] == 96 / 255,
    "reload gave a reserved name to a saved theme")
  local order = X.ThemeOrder()
  assert(#order == 16 and order[5] == "ui.elvui" and order[15] == "ui.auto" and order[16] == "ElvUI",
    "cycle duplicated a reserved ID or hid the undisputed saved name")
  local caption = env.BuffRadarConfig.themeBtn.navigation.value()
  assert(caption == "ElvUI", "settings narration treated the built-in as a saved color")
  slash("theme save ui.elvui")
  assert(#db.customThemes == 2, "saved theme command used a reserved ID")
  slash("theme delete UI.ELVUI")
  assert(db.theme == "ui.elvui" and #db.customThemes == 1, "deleting a colliding save deselected the preset")
  slash("theme elvui")
  assert(db.theme == "ElvUI" and db.bgColor[1] == 0.3, "ordinary saved theme lost its ID or color")

  slash("theme ui.foreverforge")
  local exported = assert(X.Export())
  assert(exported:match("^BR1;") and X.SaveProfile("PaletteRegression"), "could not export the palette")
  local shared = assert(X.ProfileShareText("PaletteRegression", "full"))
  assert(shared:find("\nBR2;", 1, true), "the named palette profile did not use BR2")
  slash("theme midnight")
  assert(X.Import(exported) and db.theme == "ui.foreverforge"
      and math.abs(db.bgColor[1] - 24 / 255) < 1e-12, "BR1 lost the palette or its color")
  slash("theme midnight")
  X.DeleteProfile("PaletteRegression")
  assert(X.ProfileImport(shared, db.profiles.PaletteRegression) and X.LoadProfile("PaletteRegression")
      and db.theme == "ui.foreverforge" and math.abs(db.bgColor[1] - 24 / 255) < 1e-12,
    "BR2 lost the palette or its color")
  X.DeleteProfile("PaletteRegression")
  db.customThemes = savedThemes
  slash("theme midnight")
end)

step("Auto theme opts in and uses exact loaded addon folders with stable priority", function()
  local X, db = NS.X, env.BuffRadarDB
  local slash = env.SlashCmdList.BUFFRADAR
  local prevModern, prevLegacy = env.C_AddOns, env.IsAddOnLoaded
  local expected = {
    { "ElvUI", "ui.elvui" }, { "EllesmereUI", "ui.ellesmereui" }, { "AnoUI", "ui.anoui" },
    { "WicksUI", "ui.wicks" }, { "UltimateForeverUI", "ui.ultimateforever" }, { "ForeverForge_UI", "ui.foreverforge" },
    { "DaylightUI", "ui.daylightui" }, { "MeredanUI", "ui.meredanui" }, { "NazgrelUI", "ui.nazgrelui" },
    { "ReforgedUI", "ui.reforgedui" },
  }
  local ok, err = pcall(function()
    local loaded = { ElvUI = true }
    local queries = 0
    env.IsAddOnLoaded = nil
    env.C_AddOns = { IsAddOnLoaded = function(name) queries = queries + 1; return loaded[name] == true, loaded[name] == true end }
    assert(X.Settings.Sanitize({}).theme == "midnight", "Auto replaced the default")
    slash("theme midnight")
    fire("ADDON_LOADED", "ElvUI")
    assert(db.theme == "midnight" and queries == 0, "manual/default theme opted in or probed addons")
    local n = #chat
    slash("theme auto")
    assert(db.theme == "ui.auto" and chatTemplate(n,"Theme: %s",X.ThemeLabel(true)), "slash alias did not select and describe Auto")
    assert(#X.AUTO_THEME_ADDONS == #expected, "automatic addon catalog has unexpected entries")
    for i, palette in ipairs(expected) do
      local name, id = palette[1], palette[2]
      assert(X.AUTO_THEME_ADDONS[i][1] == name and X.AUTO_THEME_ADDONS[i][2] == id,
        "addon registry order or spelling is wrong at " .. i)
      loaded = { [name] = true }
      slash("theme ui.auto")
      assert(X.autoThemeResolved == id and db.theme == "ui.auto", "exact folder was not recognized: " .. name)
      local bg, border = X.ThemeBackground(), X.ThemeBorder()
      for color = 1, 3 do
        assert(bg[color] == X.THEMES[id].bg[color] and border[color] == X.THEMES[id].border[color],
          "effective colors did not match " .. name)
      end
    end
    loaded = { ReforgedUI = true, WicksUI = true, EllesmereUI = true }
    slash("theme ui.auto")
    assert(X.autoThemeResolved == "ui.ellesmereui", "loaded palette precedence depends on load order")
    loaded = { ["elvui"] = true, ["ElvUI_Options"] = true, ["Wick's UI"] = true, ["ForeverForgeUI"] = true }
    slash("theme ui.auto")
    assert(X.autoThemeResolved == "midnight", "unregistered addon aliases matched")
    for _, probe in ipairs({
      function() return true, false end,
      function() return true, nil end,
      function() return false, true end,
      function() error("fake query failure") end,
    }) do
      env.C_AddOns = { IsAddOnLoaded = probe }
      slash("theme ui.auto")
      assert(X.autoThemeResolved == "midnight", "unfinished or unreadable modern API result matched")
    end
    env.C_AddOns, env.IsAddOnLoaded = nil, nil
    slash("theme ui.auto")
    assert(X.autoThemeResolved == "midnight", "missing query APIs did not fall back")
    env.IsAddOnLoaded = function(name) return name == "MeredanUI" and 1 or nil end
    slash("theme ui.auto")
    assert(X.autoThemeResolved == "ui.meredanui", "legacy success did not select the theme")
    env.IsAddOnLoaded = function() error("fake legacy failure") end
    slash("theme ui.auto")
    assert(X.autoThemeResolved == "midnight", "legacy failure selected a palette")
  end)
  env.C_AddOns, env.IsAddOnLoaded = prevModern, prevLegacy
  slash("theme midnight")
  assert(ok, err)
end)

step("Auto theme follows startup and late addon loads while deferring window writes in combat", function()
  local X = NS.X
  local slash = env.SlashCmdList.BUFFRADAR
  local prevModern, prevLegacy = env.C_AddOns, env.IsAddOnLoaded
  local frame, prevBackdrop = env.BuffRadarFrame, env.BuffRadarFrame.SetBackdropColor
  local wasOpen = env.BuffRadarConfig:IsShown()
  local ok, err = pcall(function()
    local writes, applied = 0, nil
    frame.SetBackdropColor = function(self, r, g, b, a)
      assert(not env.__combat, "Auto attempted an appearance write during combat")
      writes = writes + 1
      applied = { r, g, b, a }
      return prevBackdrop(self, r, g, b, a)
    end
    local loaded = { WicksUI = true }
    local checked = 0
    env.C_AddOns = { IsAddOnLoaded = function(name)
      checked = checked + 1
      return loaded[name] == true, loaded[name] == true
    end }
    env.IsAddOnLoaded = nil
    assert(driver.events.ADDON_LOADED, "addon driver unsubscribed from late addon loads")
    env.BuffRadarDB.theme, env.BuffRadarDB.bgColor = "ui.auto", { 0.24, 0.25, 0.26 }
    fire("ADDON_LOADED", "BuffRadar")
    local db = env.BuffRadarDB
    assert(db.theme == "ui.auto" and X.autoThemeResolved == "ui.wicks" and db.bgColor[1] == 0.24,
      "startup did not restore Auto separately from manual colors")
    X.OpenConfig(true)
    assert(env.BuffRadarConfig.themeBtn.navigation.value() == "Auto (Wick's UI)",
      "settings narration omitted the automatic palette")
    local before = checked
    fire("ADDON_LOADED", "ElvUI_Options")
    assert(checked == before, "unrelated addon load recomputed Auto")
    loaded.ElvUI = true
    env.__combat = true
    fire("PLAYER_REGEN_DISABLED")
    before = writes
    fire("ADDON_LOADED", "ElvUI")
    assert(writes == before, "late addon load applied the theme during combat")
    env.__combat = false
    fire("PLAYER_REGEN_ENABLED")
    assert(writes > before and applied[1] == 20 / 255 and frame.borderColor[1] == 96 / 255
      and db.theme == "ui.auto" and X.autoThemeResolved == "ui.elvui",
      "leaving combat did not apply the late loaded Auto palette")
    slash("theme forest")
    loaded.EllesmereUI = true
    fire("ADDON_LOADED", "EllesmereUI")
    assert(db.theme == "forest" and X.ThemeBackground()[1] == X.THEMES.forest.bg[1],
      "late addon load overrode manual theme")
  end)
  frame.SetBackdropColor, env.__combat = prevBackdrop, false
  env.C_AddOns, env.IsAddOnLoaded = prevModern, prevLegacy
  slash("theme midnight")
  if not wasOpen then env.BuffRadarConfig:Hide() end
  assert(ok, err)
end)

step("Auto theme profile imports choose a local palette and keep historical saved Auto separate", function()
  local X, db = NS.X, env.BuffRadarDB
  local slash = env.SlashCmdList.BUFFRADAR
  local prevModern, prevLegacy, prevThemes = env.C_AddOns, env.IsAddOnLoaded, db.customThemes
  local ok, err = pcall(function()
    local loaded = "ElvUI"
    env.C_AddOns = { IsAddOnLoaded = function(name) return name == loaded, name == loaded end }
    env.IsAddOnLoaded = nil
    db.customThemes = { { name = "Auto", bg = { 0.3, 0.2, 0.1 }, border = { 0.1, 0.2, 0.3 } } }
    slash("theme auto")
    assert(db.theme == "Auto" and X.ThemeBackground()[1] == 0.3 and X.ThemeBorder()[1] == 0.1,
      "plain Auto stopped selecting a preexisting saved theme")
    slash("theme ui.auto")
    assert(db.theme == "ui.auto" and db.bgColor[1] == 0.3 and X.autoThemeResolved == "ui.elvui",
      "explicit Auto did not preserve underlying manual color")
    local br1 = assert(X.Export())
    assert(br1:match("^BR1;") and X.SaveProfile("AutoPaletteRegression"), "could not save Auto profile")
    local br2 = assert(X.ProfileShareText("AutoPaletteRegression", "full"))
    assert(br2:find("\nBR2;", 1, true), "Auto named profile did not use BR2")

    loaded = "ReforgedUI"
    slash("theme forest")
    assert(X.Import(br1) and db.theme == "ui.auto" and db.bgColor[1] == 0.3
      and X.autoThemeResolved == "ui.reforgedui" and X.ThemeBackground()[1] == 33 / 255,
      "BR1 restored the sender's displayed palette instead of local Auto")
    loaded = "DaylightUI"
    slash("theme midnight")
    X.DeleteProfile("AutoPaletteRegression")
    assert(X.ProfileImport(br2, db.profiles.AutoPaletteRegression) and X.LoadProfile("AutoPaletteRegression") and db.theme == "ui.auto"
      and db.bgColor[1] == 0.3 and X.autoThemeResolved == "ui.daylightui" and X.ThemeBorder()[1] == 55 / 255,
      "BR2 restored the sender's displayed palette instead of local Auto")
  end)
  env.C_AddOns, env.IsAddOnLoaded, db.customThemes = prevModern, prevLegacy, prevThemes
  X.DeleteProfile("AutoPaletteRegression")
  slash("theme midnight")
  assert(ok, err)
end)

step("Auto Theme Priority uses the Settings keyboard, refreshes late picks, and resets", function()
  local X, db = NS.X, env.BuffRadarDB
  local cfg, slash = env.BuffRadarConfig, env.SlashCmdList.BUFFRADAR
  local prevModern, prevLegacy, prevOrder = env.C_AddOns, env.IsAddOnLoaded, db.autoThemePriority
  local prevThemes = db.customThemes
  local input = cfg.navInput
  local function focused(widget)
    return cfg.navOutline.shown and cfg.navOutline.points[1][2] == widget
  end
  local function advanceTo(widget)
    for _ = 1, 80 do
      if focused(widget) then return end
      input.scripts.OnTabPressed(input)
    end
    error("could not focus theme priority control")
  end
  local ok, err = pcall(function()
    local loaded = { ElvUI = true }
    env.C_AddOns = { IsAddOnLoaded = function(name) return loaded[name] == true, loaded[name] == true end }
    env.IsAddOnLoaded = nil
    X.ResetAutoThemePriority()
    slash("theme crimson")
    X.OpenConfig(true)
    cfg.tabBtns.look:Click()
    slash("config find")
    local search = cfg.searchBox
    search:SetText(env.__german and "priorität" or "auto theme priority")
    search.scripts.OnTextChanged(search)
    assert(cfg.themePriorityBtn:GetAlpha() == 1 and cfg.themeBtn:GetAlpha() < 1,
      "settings search did not find the priority launcher")
    search.scripts.OnEscapePressed(search)
    slash("config navigate")
    advanceTo(cfg.themePriorityBtn)
    input.scripts.OnEnterPressed(input)
    local panel = env.BuffRadarAutoThemePriority
    assert(panel and panel:IsVisible() and #panel.rows == 10 and not cfg.searchToggle:IsShown(),
      "Window keyboard activation did not open all ten priority rows")
    assert(panel.rows[1].label:GetText() == "1. ElvUI" and not panel.rows[1].up:IsEnabled()
      and not panel.rows[10].down:IsEnabled(), "wrong default order or enabled boundary actions")
    advanceTo(panel.statusRow)
    assert(cfg.navStatus:GetText():find("Crimson", 1, true), "manual theme status was unavailable to navigation")
    advanceTo(panel.rows[2].up)
    input.scripts.OnEnterPressed(input)
    assert(panel.rows[1].label:GetText() == "1. EllesmereUI" and db.theme == "crimson"
      and db.bgColor[1] == X.THEMES.crimson.bg[1] and focused(panel.rows[1].down),
      "keyboard move did not follow the row or changed the selected manual theme")
    slash("theme ui.auto")
    assert(panel.status:GetText():find("ElvUI (ElvUI)", 1, true), "status omitted the exact detected addon")
    advanceTo(panel.statusRow)
    loaded.EllesmereUI = true
    fire("ADDON_LOADED", "EllesmereUI")
    assert(X.autoThemeAddon == "EllesmereUI" and panel.status:GetText():find("EllesmereUI (EllesmereUI)", 1, true),
      "late load did not respect saved priority or refresh open panel status")
    assert(cfg.navStatus:GetText():find("EllesmereUI (EllesmereUI)", 1, true), "resolved theme was not available to narration")
    local n = #chat
    slash("theme priority list")
    assert(chatSince(n, "ui.ellesmereui"), "slash priority list omitted the canonical palette ID")
    slash("theme priority down ui.ellesmereui")
    assert(X.autoThemeAddon == "ElvUI" and panel.rows[1].label:GetText() == "1. ElvUI",
      "slash priority move did not refresh both current theme and open panel")
    slash("theme priority up ui.ellesmereui")
    assert(X.autoThemeAddon == "EllesmereUI", "slash up did not change priority")
    panel.resetButton:Click()
    assert(db.autoThemePriority == "" and X.autoThemeAddon == "ElvUI", "Settings Reset did not restore defaults")
    loaded = {}
    slash("theme ui.auto")
    assert(panel.status:GetText():find("Midnight", 1, true), "Auto fallback was not named in the panel")
    input.scripts.OnEscapePressed(input)
    assert(not panel:IsVisible() and cfg.searchToggle:IsShown() and input:HasFocus() and focused(cfg.themePriorityBtn),
      "closing the modal by keyboard did not restore its launcher focus")
    input.scripts.OnEscapePressed(input)
    slash("theme priority")
    assert(panel:IsVisible(), "slash did not invoke the Settings overlay")
    cfg:Hide()
    X.OpenConfig(true)
    assert(not panel:IsVisible(), "theme panel remained open after Settings closed")
    slash("theme priority")
    env.__combat = true
    cfg.scripts.OnEvent(cfg, "PLAYER_REGEN_DISABLED")
    assert(not panel:IsVisible(), "theme priority remained open in combat")
    slash("theme priority")
    assert(not panel:IsVisible(), "slash opened the priority panel during combat")
    env.__combat = false
    db.customThemes = {}
    assert(X.SaveTheme("priority"), "could not create historical custom priority theme")
    slash("theme priority")
    assert(db.theme == "priority" and not panel:IsVisible(), "command masked a historical saved priority theme")
    slash("theme priority panel")
    assert(panel:IsVisible() and db.theme == "priority", "explicit panel command could not disambiguate a custom theme")
  end)
  env.C_AddOns, env.IsAddOnLoaded, db.autoThemePriority, env.__combat = prevModern, prevLegacy, prevOrder, false
  db.customThemes = prevThemes
  if input:HasFocus() then input.scripts.OnEscapePressed(input) end
  cfg.tabBtns.look:Click()
  slash("theme midnight")
  assert(ok, err)
end)

step("Auto Theme Priority repairs saved orders and round trips through old and new profiles", function()
  local X, db = NS.X, env.BuffRadarDB
  local slash = env.SlashCmdList.BUFFRADAR
  local prevModern, prevLegacy, prevOrder = env.C_AddOns, env.IsAddOnLoaded, db.autoThemePriority
  local ok, err = pcall(function()
    local repaired = X.Settings.Sanitize({
      autoThemePriority = "  UI.WICKS ,unknown,ui.elvui,ui.wicks,ui.auto",
    })
    assert(repaired.autoThemePriority:match("^ui%.wicks,ui%.elvui,ui%.ellesmereui,ui%.anoui,"),
      "partial order did not allowlist, dedupe, and append default candidates")
    for _, malformed in ipairs({ {}, 42, "unknown", string.rep("x", 513) }) do
      assert(X.Settings.Sanitize({ autoThemePriority = malformed }).autoThemePriority == "",
        "corrupt priority order did not use defaults")
    end
    env.C_AddOns = { IsAddOnLoaded = function(name)
      local loaded = name == "ElvUI" or name == "EllesmereUI"
      return loaded, loaded
    end }
    env.IsAddOnLoaded = nil
    slash("theme priority reset")
    slash("theme ui.auto")
    local defaultExport = assert(X.Export())
    slash("theme priority up ui.ellesmereui")
    local order = db.autoThemePriority
    assert(order:match("^ui%.ellesmereui,ui%.elvui,") and X.autoThemeAddon == "EllesmereUI", "could not set test priority")
    local export = assert(X.Export())
    assert(export:find(";autoThemePriority=", 1, true) and X.SaveProfile("ThemeOrderRegression"), "priority was not exportable")
    local shared = assert(X.ProfileShareText("ThemeOrderRegression", "full"))
    assert(shared:find("\nBR2;", 1, true) and shared:find(";autoThemePriority=", 1, true), "BR2 did not serialize order")
    local oldExport = export:gsub(";autoThemePriority=[^;]*", "", 1)
    local oldShared = (shared:gsub(";autoThemePriority=[^;]*", "", 1)):gsub("ThemeOrderRegression", "ThemeOrderLegacy", 1)
    assert(X.Import(oldExport) and db.autoThemePriority == order, "old BR1 changed current priority")
    assert(X.ProfileImport(oldShared) and X.LoadProfile("ThemeOrderLegacy") and db.autoThemePriority == order,
      "old BR2 changed current priority")
    local overlong = export:gsub(";autoThemePriority=[^;]*", ";autoThemePriority=" .. string.rep("a", 513), 1)
    assert(not X.Import(overlong) and db.autoThemePriority == order, "oversize import changed priority or appeared to succeed")
    assert(X.Import(defaultExport) and db.autoThemePriority == "" and X.autoThemeAddon == "ElvUI",
      "explicit empty export did not reset priority")
    assert(X.Import(export) and db.autoThemePriority == order and X.autoThemeAddon == "EllesmereUI",
      "new BR1 did not restore the order and recalculate Auto")
    slash("theme priority reset")
    assert(X.ProfileImport(shared, db.profiles.ThemeOrderRegression) and X.LoadProfile("ThemeOrderRegression")
      and db.autoThemePriority == order and X.autoThemeAddon == "EllesmereUI",
      "new BR2 did not restore the order and recalculate Auto")
  end)
  env.C_AddOns, env.IsAddOnLoaded, db.autoThemePriority = prevModern, prevLegacy, prevOrder
  X.DeleteProfile("ThemeOrderRegression")
  X.DeleteProfile("ThemeOrderLegacy")
  slash("theme midnight")
  assert(ok, err)
end)

step("Auto theme save snapshots effective colors and cancel restores the prior selection", function()
  local X, db = NS.X, env.BuffRadarDB
  local slash = env.SlashCmdList.BUFFRADAR
  local prevModern, prevPicker, prevThemes = env.C_AddOns, env.ColorPickerFrame, db.customThemes
  local wasOpen = env.BuffRadarConfig:IsShown()
  local ok, err = pcall(function()
    local loaded, picker = "AnoUI", nil
    env.C_AddOns = { IsAddOnLoaded = function(name) return name == loaded, name == loaded end }
    env.ColorPickerFrame = env.CreateFrame("Frame")
    env.ColorPickerFrame.SetupColorPickerAndShow = function(self,args) picker=args;self:Show() end
    env.ColorPickerFrame.GetColorRGB = function() return 0.7,0.6,0.5 end
    db.customThemes = {}
    slash("theme forest")
    slash("theme ui.auto")
    X.OpenConfig(true)
    local swatch = env.BuffRadarConfig.swatch
    swatch.scripts.OnClick(swatch)
    assert(picker and picker.r == 24 / 255 and picker.g == 21 / 255 and picker.b == 31 / 255,
      "color picker opened at the manual fallback instead of the displayed Auto colors")
    picker.swatchFunc()
    assert(db.theme == "custom" and db.bgColor[1] == 0.7, "manual color preview failed")
    loaded = "MeredanUI"
    fire("ADDON_LOADED", loaded)
    picker.cancelFunc()
    assert(db.theme == "ui.auto" and db.bgColor[1] == X.THEMES.forest.bg[1]
      and X.ThemeBackground()[1] == 22 / 255, "picker cancel lost Auto or stale-copied the selected palette")
    slash("theme save AutoCopy")
    assert(db.theme == "AutoCopy" and db.bgColor[1] == 22 / 255 and X.ThemeBorder()[1] == 97 / 255,
      "saving Auto used underlying settings instead of effective background and border")
    loaded = "ElvUI"
    fire("ADDON_LOADED", loaded)
    assert(db.theme == "AutoCopy" and X.ThemeBackground()[1] == 22 / 255, "saved Auto snapshot still follows addons")
  end)
  env.C_AddOns, env.ColorPickerFrame, db.customThemes = prevModern, prevPicker, prevThemes
  slash("theme midnight")
  if not wasOpen then env.BuffRadarConfig:Hide() end
  assert(ok, err)
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
step("close control follows hover without reserving titleless header space", function()
  local X, db = NS.X, env.BuffRadarDB
  local frame, close = env.BuffRadarFrame
  for _, widget in ipairs(env.__frames) do
    if widget.parent == frame and widget.template == "UIPanelCloseButton" then close = widget; break end
  end
  assert(close, "main window did not create its close button")
  local oldTitle, oldLocked, oldClick = db.showTitle, db.locked, db.clickThrough
  local oldMouse, oldCloseMouse, oldTop = env.__mouseOver, close.IsMouseOver, env.UIParent.GetTop
  local ok, err = pcall(function()
    db.showTitle, db.locked, db.clickThrough = true, false, false
    env.__mouseOver = false
    X.ApplyRowLayout()
    local titledY = env.BuffRadarRow1.points[1][5]
    frame:Show()
    X.UpdateFade()
    assert(not close:IsShown(), "close control is visible without hover")
    env.__mouseOver = true
    frame:GetScript("OnEnter")(frame)
    assert(close:IsShown() and close.hoverAnchor == "TOPRIGHT", "titled window hover did not reveal close")
    env.UIParent.GetTop = function() return 1000 end
    db.showTitle = false
    X.ApplyRowLayout()
    X.UpdateFade()
    assert(env.BuffRadarRow1.points[1][5] - titledY == 24, "titleless rows still reserve the title header")
    assert(close.hoverAnchor == "BOTTOMRIGHT", "titleless close does not float above its rows")
    env.__mouseOver = false
    close.IsMouseOver = function() return true end
    frame:GetScript("OnLeave")(frame)
    assert(close:IsShown(), "moving onto the floating button hid it")
    env.UIParent.GetTop = function() return 605 end
    X.UpdateFade()
    assert(close.hoverAnchor == "TOPRIGHT", "close went outside a window near the screen edge")
    db.locked, db.clickThrough = true, true
    X.ApplyClickThrough()
    assert(not close:IsShown(), "locked click-through window intercepted hover")
    db.locked, db.clickThrough = false, false
    env.__mouseOver = true
    X.ApplyClickThrough()
    assert(close:IsShown(), "close did not reappear when click-through ended")
    frame:Hide()
    assert(not close:IsShown(), "close remained visible on a hidden frame")
  end)
  db.showTitle, db.locked, db.clickThrough = oldTitle, oldLocked, oldClick
  env.__mouseOver, close.IsMouseOver, env.UIParent.GetTop = oldMouse, oldCloseMouse, oldTop
  X.ApplyRowLayout()
  X.ApplyClickThrough()
  timerTick()
  assert(ok, err)
end)
step("combat visibility leaves locked frames to the secure driver", function()
  local frame, pill = env.BuffRadarFrame, env.BuffRadarPill
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
step("death suspends the window, settings and casts through release and combat exit", function()
  local X, db = NS.X, env.BuffRadarDB
  local frame, pill, button = env.BuffRadarFrame, env.BuffRadarPill, env.BuffRadarMinimapButton
  local oldHidden, oldMinimap, oldDead = db.hidden, db.showMinimap, env.__over.UnitIsDeadOrGhost
  local oldHide = frame.Hide
  local tooltip, oldOwner = env.GameTooltip, env.GameTooltip.GetOwner
  local dead = true
  local ok, err = pcall(function()
    db.hidden, db.showMinimap = false, true
    X.RefreshMinimapButton()
    X.OpenConfig(true)
    local cfg = assert(env.BuffRadarConfig)
    frame:Show()
    pill:Show()
    tooltip.GetOwner = function() return frame end
    tooltip:Show()
    frame.Hide = function(self)
      assert(not env.__combat, "protected frame hidden by insecure code during combat")
      oldHide(self)
    end
    env.__over.UnitIsDeadOrGhost = function(u) return u == "player" and dead end
    env.__combat = not noTemplates
    fire("PLAYER_DEAD")
    assert(not frame:IsShown() and not pill:IsShown(), "death left a buff surface visible")
    assert(not cfg:IsShown() and not button:IsShown(), "death left an auxiliary window visible")
    assert(not tooltip:IsShown(), "death left a BuffRadar tooltip visible")
    assert(not env.BuffRadarNextButton:GetAttribute("type") and not env.BuffRadarGroupButton:GetAttribute("type"),
      "death left a cast binding armed")
    for _, command in ipairs({ "announce", "summary", "discord" }) do
      local before = #chat
      env.SlashCmdList.BUFFRADAR(command)
      assert(#chat == before, "suspended report still ran: " .. command)
    end
    env.SlashCmdList.BUFFRADAR("")
    env.BuffRadar_ToggleWindow()
    X.OpenConfig(true)
    assert(not db.hidden and db.showMinimap and not cfg:IsShown(), "dead interaction changed saved visibility or opened settings")
    fire("PLAYER_ALIVE")
    env.__combat = false
    fire("PLAYER_REGEN_ENABLED")
    timerTick()
    assert(not frame:IsShown() and not pill:IsShown() and not button:IsShown(), "ghost or combat exit restored the UI")
    fire("PLAYER_UNGHOST") -- a synchronous resurrection event may precede the unit flag
    assert(not button:IsShown(), "stale dead flag was ignored before recovery")
    dead = false
    timerTick()
    timerTick()
    assert(button:IsShown(), "late living flag did not restore configured minimap button")
    assert(not cfg:IsShown(), "recovery reopened dismissed settings")
    db.hidden, db.showMinimap = true, false
    dead = true
    tooltip.GetOwner = function() return env.UIParent end
    tooltip:Show()
    fire("PLAYER_DEAD")
    assert(tooltip:IsShown(), "death dismissed another addon's tooltip")
    dead, env.__combat = false, true
    fire("PLAYER_ALIVE") -- accepted resurrection without becoming a ghost
    timerTick()
    assert(not frame:IsShown(), "resurrection reopened the buff window during combat")
    env.__combat = false
    fire("PLAYER_REGEN_ENABLED")
    timerTick()
    assert(not frame:IsShown() and not pill:IsShown() and not button:IsShown(),
      "resurrection or combat exit ignored visibility preferences")
  end)
  env.__combat, db.hidden, db.showMinimap = false, oldHidden, oldMinimap
  frame.Hide, env.__over.UnitIsDeadOrGhost = oldHide, oldDead
  tooltip.GetOwner = oldOwner
  tooltip:Hide()
  fire("PLAYER_ALIVE")
  X.RefreshMinimapButton()
  timerTick()
  assert(ok, err)
end)
step("appearance refresh never changes the frame layer and flash restore waits for combat", function()
  local X, db = NS.X, env.BuffRadarDB
  local frame, pill = env.BuffRadarFrame, env.BuffRadarPill
  local oldFrame, oldPill = frame.SetFrameStrata, pill.SetFrameStrata
  local oldMotion, writes = db.reduceMotion, 0
  frame.SetFrameStrata = function() writes = writes + 1; error("main frame layer is fixed") end
  pill.SetFrameStrata = function() writes = writes + 1; error("pill frame layer is fixed") end
  local ok, err = pcall(function()
    db.reduceMotion = false
    X.ApplyAppearance()
    assert(writes == 0, "appearance refresh changed a frame layer")
    local restoreBorder
    X.Flash()
    assert(frame.borderColor[1] == 1 and frame.borderColor[2] == 0.35, "border pulse did not show")
    if env.C_Timer then
      restoreBorder = table.remove(env.__timers)
      assert(restoreBorder, "border pulse did not schedule a restore")
    end
    env.__combat = true
    local delayOk, delayErr = true, nil
    if restoreBorder then delayOk, delayErr = pcall(restoreBorder) end
    assert(delayOk, "border restore failed in combat: " .. tostring(delayErr))
    assert(writes == 0, "combat flash restore changed a frame layer")
    env.__combat = false
    fire("PLAYER_REGEN_ENABLED")
    local expected = X.ThemeBorder()
    assert(frame.borderColor[1] == expected[1] and frame.borderColor[2] == expected[2],
      "post-combat appearance did not restore the border colour")
    X.ApplyAppearance()
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
    X.Core.BuildBuffList()
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
  X.Core.BuildBuffList()
  assert(ok, err)
end)

step("secure rows and keys arm only after the combat driver is installed", function()
  for _, outcome in ipairs({ "snippet refused", "registration refused", "success" }) do
    local client, messages = TestClient()
    local create, registrations = client.CreateFrame, {}
    client.CreateFrame = function(kind, name, parent, template)
      local button = create(kind, name, parent, template)
      if template and template:find("SecureActionButtonTemplate", 1, true) then
        local setScript, setAttribute = button.SetScript, button.SetAttribute
        button.SetScript = function(self, event, callback)
          assert(event ~= "OnClick", name .. " replaced a secure OnClick")
          return setScript(self, event, callback)
        end
        button.SetAttribute = function(self, key, value)
          if key == "_onstate-combat" and outcome == "snippet refused" then return false end
          return setAttribute(self, key, value)
        end
      end
      return button
    end
    client.RegisterStateDriver = function(button, state)
      if state ~= "combat" then return end
      registrations[button] = (registrations[button] or 0) + 1
      if outcome == "registration refused" then return false end
    end
    local X, startup = LoadClient(client)
    startup.scripts.OnEvent(startup, "ADDON_LOADED", "BuffRadar")
    startup.scripts.OnEvent(startup, "PLAYER_LOGIN")
    X.Refresh()
    for _, message in ipairs(messages) do assert(not message:find("error", 1, true), message) end
    local row = assert(client.BuffRadarRow1)
    assert(row:IsShown() and row.entry, "no eligible row to exercise secure setup")
    for _, name in ipairs({ "BuffRadarRow1", "BuffRadarNextButton", "BuffRadarGroupButton" }) do
      local button = assert(client[name], name .. " was not built")
      local expected = outcome == "snippet refused" and 0 or 1
      assert((registrations[button] or 0) == expected, name .. " registered unexpectedly: " .. outcome)
      assert((button:GetAttribute("type") ~= nil) == (outcome == "success"), name .. " armed incorrectly: " .. outcome)
    end
  end
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
    local pack = NS.Locales and env.GetLocale and NS.Locales[env.GetLocale()]
    return (type(pack) == "table" and pack[s]) or s
  end
  local ok, err = pcall(function()
    X.tallyUnknownUnits = 0
    X.FriendlyPlatesOn = function() return true end
    X.rangeSilent = false
    assert(X.EmptyStatus() == T("No targets in the buff queue."), "an empty queue was reported as confirmed buff coverage")
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

step("unreadable outdoor target buffs are not reported as complete", function()
  local cleanup = partyOfTwo("OutsideUnknown")
  local X, O = NS.X, env.__over
  local oldPlates = X.FriendlyPlatesOn
  local ok, err = pcall(function()
    for _, key in ipairs({ "UnitExists", "UnitIsPlayer", "UnitGUID", "UnitName", "UnitFullName", "UnitClass" }) do
      local original = O[key]
      O[key] = function(unit)
        if unit == "target" then return original("party1") end
        if unit == "player" then return original(unit) end
        if key == "UnitExists" or key == "UnitIsPlayer" then return false end
      end
    end
    env.IsInGroup = function() return false end
    env.IsSpellInRange = function() return 1 end
    X.FriendlyPlatesOn = function() return true end
    O.Aura = function(unit)
      if unit == "target" then error("by-name restricted") end
      return { expirationTime = env.GetTime() + 600 }
    end
    O.AuraList = function(unit) if unit == "target" then error("index restricted") end end
    X.Refresh()
    assert(not shownRows().target and X.tallyUnknownUnits == 0,
      "unreadable solo target was listed or changed group coverage")
    assert(X.EmptyStatus() == X.L["Some buff information is unavailable."],
      "unreadable outdoor target was reported as fully buffed")
    O.Aura = function() return { expirationTime = env.GetTime() + 600 } end
    X.Refresh()
    assert(X.EmptyStatus() == X.L["No targets in the buff queue."],
      "a later readable scan did not clear aura uncertainty")
  end)
  X.FriendlyPlatesOn = oldPlates
  cleanup()
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
    if type(fs.text) == "string" and localizedMatch(fs.text,"Focus %s: needs %s","Focusdude") then found = fs.text end
  end
  assert(found, "focus line not shown for an unbuffed focus")
  env.SlashCmdList.BUFFRADAR("focus")
  refresh()
  local still
  for _, fs in ipairs(env.__fontstrings) do
    if fs.shown and type(fs.text) == "string" and localizedMatch(fs.text,"Focus %s: needs %s","Focusdude") then still = fs.text end
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
  assert(set.row.tag.text == NS.X.L["pet"] or set.row.tag.text == "Begleiter",
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
    assert(chatSince(n,"Forever"), "aura watch not refused on retail")
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
      return { { name = "Rallying Cry of the Dragonslayer", spellId = 22888, expirationTime = env.GetTime() + 7500 } }
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
  assert(chatSince(n, NS.X.L["World"] .. ": Rallying Cry of the Dragonslayer ~2h"),
    "world buff not reported by the toggle")
  refresh()
  local line
  for _, fs in ipairs(env.__fontstrings) do
    if type(fs.text) == "string" and fs.text:find(NS.X.L["World"] .. ": Rallying Cry", 1, true) then line = fs.text end
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
  O.AuraList = function(u)
    if u == "party1" then return { { spellId = 430, name = "Drink", expirationTime = env.GetTime() + 60 } } end
  end
  env.IsSpellInRange = function() return 1 end
  env.SlashCmdList.BUFFRADAR("drink")
  refresh()
  local set = shownRows().party1
  assert(set, "the drinking priest is not listed")
  assert(set.row.tag.text == NS.X.L["drinking"] or set.row.tag.text == "trinkt gerade",
    "drinking tag missing: " .. tostring(set.row.tag.text))
  local line
  for _, fs in ipairs(env.__fontstrings) do
    if type(fs.text) == "string" and fs.text:find("Healer drinking", 1, true) then line = fs.text end
  end
  assert(line, "coverage line does not count the drinking healer")
  env.SlashCmdList.BUFFRADAR("drink")
  O.UnitClass, O.AuraList = prevClass, nil
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
  assert(chatSince(n,"["..string.format(NS.X.L["%s only"],"instance").."]"), "buff list does not show the context")
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
  local dialog = env.BuffRadarExportFrame
  dialog.accept:Click()
  assert(db.autoProfile.dungeon == nil, "review changed a saved mapping")
  dialog.apply:Click()
  assert(chatSince(n, string.format(NS.X.L["Plan applied locally: %d assignments, %d blessings, %d auto profiles."], 1, 0, 1)),
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
  X.Broadcast = function(msg) messages[#messages + 1] = msg; return true end
  assert(not X.PlanImport("BRPLAN1;A;FORTITUDE;Other;P;dungeon"), "incomplete plan was accepted")
  assert(not X.PlanImport("BRPLAN1;A;FORTITUDE;Other;A;FORTITUDE;Aaron"), "duplicate plan was accepted")
  assert(not X.PlanImport("BRPLAN1;P;unknown;Original"), "unknown plan context accepted")
  assert(X.PlanImport("BRPLAN1"), "empty plan was not accepted as no-op")
  assert(X.assign.FORTITUDE == "Aaron" and db.autoProfile.dungeon == "Original" and #messages == 0,
    "invalid or empty plan changed state")
  local draft = assert(X.ParsePlanImport("BRPLAN1;A;FORTITUDE;Aaron;A;THORNS;Bela;P;raid;Future"))
  local lines, _, scope = X.ReviewPlan(draft)
  assert(scope and #lines == 3 and lines[1]:find("Future", 1, true), "review omitted missing profile or sharing")
  env.UnitIsGroupLeader = nil
  assert(not X.ApplyPlan(draft, scope) and not X.assign.THORNS and #messages == 0,
    "confirmation ignored the changed group authority")
  env.UnitIsGroupLeader = function(u) return u == "player" end
  assert(X.ApplyPlan(draft, scope))
  assert(db.autoProfile.dungeon == "Original" and db.autoProfile.raid == "Future", "plan mapping did not merge")
  assert(#messages == 1 and messages[1] == "ASSIGN;THORNS;Bela", "plan did not send only the changed record")
  assert(X.PlanImport("BRPLAN1;A;THORNS;Aaron"))
  assert(#messages == 1, "local-only plan imported with an unrequested send")
  X.assign, X.blessPlan, db.autoProfile, env.UnitIsGroupLeader, X.Broadcast = assign, bless, mapping, leader, sent
  cleanup()
end)
step("a single profile can be shared and imported (1.8.0)", function()
  local db = env.BuffRadarDB
  env.SlashCmdList.BUFFRADAR("profile save shareme")
  NS.X.ShowExport(assert(NS.X.ProfileShareText("shareme","full")),false)
  local text = env.BuffRadarExportFrame.editBox.text
  assert(type(text) == "string" and text:find("BuffRadar profile: shareme", 1, true),
    "share text has no header: " .. tostring(text))
  assert(text:find("\nBR2;", 1, true), "share text carries no versioned profile")
  env.SlashCmdList.BUFFRADAR("profile delete shareme")
  assert(db.profiles.shareme == nil, "profile not deleted before import")
  env.SlashCmdList.BUFFRADAR("profile import")
  env.BuffRadarExportFrame.editBox:SetText(text)
  local n = #chat
  local dialog = env.BuffRadarExportFrame
  dialog.accept:Click()
  assert(not db.profiles.shareme and dialog.apply:IsShown(), "profile review changed storage")
  dialog.apply:Click()
  assert(chatSince(n, string.format(NS.X.L["Profile stored: %s (not loaded)."], "shareme")), "profile import not reported")
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
  env.SlashCmdList.BUFFRADAR("offenders clear")
  NS.X.OnRoster()
  -- Isolate the saved history so the two named rows are in the top ten.
  local guidA, guidZ = env.UnitGUID("party1"), env.UnitGUID("party2")
  local function count(guid) return db.offenders[guid] and db.offenders[guid].count or 0 end
  local beforeA, beforeZ = count(guidA), count(guidZ)
  refresh()  -- Aaron and Zed are both seen unbuffed this session
  env.IsInGroup = function() return false end
  fire("GROUP_ROSTER_UPDATE")  -- the group ends: the session folds
  assert(count(guidA) == beforeA + 1 and db.offenders[guidA].name == "Aaron-TestRealm", "Aaron not counted once more")
  assert(count(guidZ) == beforeZ + 1, "Zed not counted once more")
  local n = #chat
  env.SlashCmdList.BUFFRADAR("offenders")
  assert(chatSince(n, "Aaron-TestRealm: " .. (beforeA + 1)), "offender list does not name Aaron")
  env.SlashCmdList.BUFFRADAR("offenders clear")
  assert(next(db.offenders) == nil, "offender history not cleared")
  cleanup()
end)

step("Behavior ignore-list hint clears the consumables checkbox", function()
  NS.X.OpenConfig(true)
  local cfg = env.BuffRadarConfig
  local hint
  for _, font in ipairs(env.__fontstrings) do
    if type(font.text) == "string" and font.text:find(NS.X.L["Right-click any name in the BuffRadar window to ignore that player; manage the list on the Ignore & Stats tab."],1,true) then
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
    if control.w.text == NS.X.L["Reset buff order"] then
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

step("settings search counts only visible controls and clears on close", function()
  if not (env.BuffRadarConfig and env.BuffRadarConfig.shown) then
    env.SlashCmdList.BUFFRADAR("config")
  end
  local cfg = env.BuffRadarConfig
  local sb = cfg.searchBox
  assert(sb, "no settings search box")
  cfg.tabBtns.look.scripts.OnClick()
  local oldSetFocus = sb.SetFocus
  local focused = false
  sb.SetFocus = function(self) focused = true; oldSetFocus(self) end
  cfg.displayBtn.scripts.OnClick()
  env.SlashCmdList.BUFFRADAR("config find")
  sb.SetFocus = oldSetFocus
  assert(cfg.searchFooter.shown and cfg.panels.look.shown and not cfg.displayPanel.shown and focused,
    "keyboard command did not reopen, display, and focus the settings search")
  cfg.titleCheck:SetAlpha(0.8)
  sb:SetText("opacity")
  sb.scripts.OnTextChanged(sb)
  assert(cfg.slider:GetAlpha() == 1, "the opacity slider was dimmed by its own search")
  assert(cfg.titleCheck:GetAlpha() == 0.2, "a current-tab non-match was not dimmed")
  assert(cfg.soundCheck:GetAlpha() == 1, "a different tab's control was changed")
  assert(NS.X.CfgFilter("opacity") == 1, "current-tab result count was wrong")
  if env.__german then
    sb:SetText("hintergrunddeckkraft")
    sb.scripts.OnTextChanged(sb)
    assert(cfg.searchHint:GetText() == "Treffer: 1",
      "a localized search did not match its visible label")
  end
  local opacity
  for _, entry in ipairs(NS.X.cfgReg) do
    if entry.w == cfg.slider then opacity = entry.keys; break end
  end
  assert(opacity)
  cfg.slider:Hide()
  assert(NS.X.CfgFilter(opacity) == 0, "a hidden control still counted")
  cfg.slider:Show()
  cfg.searchToggle.scripts.OnClick(cfg.searchToggle)
  assert(not cfg.searchFooter.shown and sb:GetText() == "" and cfg.titleCheck:GetAlpha() == 0.8,
    "closing Find retained the query or did not restore the original alpha")
  cfg.titleCheck:SetAlpha(1)
  cfg.searchToggle.scripts.OnClick(cfg.searchToggle)
  sb:SetText("opacity")
  sb.scripts.OnTextChanged(sb)
  sb.scripts.OnEscapePressed(sb)
  assert(not cfg.searchFooter.shown and sb:GetText() == "" and cfg.titleCheck:GetAlpha() == 1,
    "Escape did not close and clear search")
  cfg.tabBtns.alerts.scripts.OnClick()
  cfg.searchToggle.scripts.OnClick(cfg.searchToggle)
  sb:SetText("opacity")
  sb.scripts.OnTextChanged(sb)
  assert(NS.X.CfgFilter("opacity") == 0, "a match on Window leaked into Alerts")
  cfg.tabBtns.look.scripts.OnClick()
  assert(not cfg.searchFooter.shown and sb:GetText() == "" and cfg.soundCheck:GetAlpha() == 1,
    "changing tabs did not restore search appearance")
end)

step("class and role assignment table supports mouse, keyboard and settings search", function()
  local X, cfg, slash = NS.X, env.BuffRadarConfig, env.SlashCmdList.BUFFRADAR
  if not env.__forever then
    slash("buffassign")
    assert(not env.BuffRadarAssignments and not cfg.assignmentButton,
      "assignment settings appeared on the other edition")
    return
  end
  local savedEnabled, savedRule = X.AssignmentEnabled(), X.GetAssignment("DRUID", "TANK")
  local ok, err = pcall(function()
    slash("config")
    cfg.tabBtns.buffs:Click()
    cfg.assignmentButton:GetScript("OnClick")(cfg.assignmentButton, "LeftButton")
    local panel, input = env.BuffRadarAssignments, cfg.navInput
    local cell = panel.cells.DRUID.TANK
    assert(panel:IsVisible() and not cfg.searchToggle:IsShown()
      and (not panel.preview or not panel.preview:IsVisible()), "settings click did not open the assignment grid")
    assert(panel.closeButton:IsVisible(), "the grid close button did not start visible")
    assert(#X.BLESSING_CLASS_ORDER == 9 and panel.cells.WARRIOR.WORLD, "assignment table missing class or slot")
    slash("buffassign on")
    assert(X.AssignmentEnabled() and panel.enabled:GetChecked(), "slash opt-in did not update the checkbox")
    slash("config navigate")
    local function advanceTo(widget)
      for _ = 1, 50 do
        if cfg.navOutline.shown and cfg.navOutline.points[1][2] == widget then return end
        input.scripts.OnTabPressed(input)
      end
      error("could not focus the assignment control")
    end
    advanceTo(cell)
    input.scripts.OnSpacePressed(input)
    local picker = panel.picker
    assert(picker:IsShown() and picker.class == "DRUID" and picker.slot == "TANK",
      "keyboard opened the wrong cell")
    local option = picker.options[1]
    assert(option:IsVisible() and option.option, "known targeted buffs were not offered")
    assert(picker.closeButton:IsVisible() and not panel.closeButton:IsVisible(),
      "the grid close button can compete with the picker close button")
    assert(picker.backButton:IsVisible() and picker.backButton:GetText() == NS.X.L["Done"],
      "immediate picker had no Done action")
    advanceTo(option)
    input.scripts.OnEnterPressed(input)
    assert(X.GetAssignment("DRUID", "TANK")[option.option.key], "keyboard selection did not persist")
    input.scripts.OnEscapePressed(input)
    assert(not picker:IsShown() and panel:IsVisible() and panel.closeButton:IsVisible()
      and cfg.navOutline.points[1][2] == cell
      and X.GetAssignment("DRUID", "TANK")[option.option.key],
      "keyboard Escape did not restore the grid and selection")
    input.scripts.OnSpacePressed(input)
    advanceTo(option)
    input.scripts.OnEnterPressed(input)
    assert(X.GetAssignment("DRUID", "TANK") == false, "clearing a cell restored defaults instead of None")
    advanceTo(picker.defaultButton)
    input.scripts.OnEnterPressed(input)
    assert(not picker:IsShown() and X.GetAssignment("DRUID", "TANK") == nil,
      "Default did not restore inheritance and return to the table")
    input.scripts.OnEscapePressed(input)
    cell:Click()
    picker.backButton:Click()
    assert(panel:IsVisible() and not picker:IsShown(), "Done did not return to the grid")
    cell:Click()
    picker.closeButton:Click()
    assert(panel:IsVisible() and not picker:IsShown(), "the picker X closed the assignment grid")
    cell:Click()
    picker:GetScript("OnKeyDown")(picker, "ESCAPE")
    assert(panel:IsVisible() and not picker:IsShown(), "ordinary Escape closed the assignment grid")
    cell:Click()
    assert(picker:IsShown(), "mouse click did not reopen the cell editor")
    picker.noneButton:Click()
    assert(not picker:IsShown() and X.GetAssignment("DRUID", "TANK") == false,
      "None did not explicitly suppress assigned buffs")
    cell:Click()
    slash("config find")
    assert(not panel:IsShown() and not picker:IsShown() and cfg.searchBox:HasFocus(),
      "settings search did not close the assignment editor")
    cfg.searchBox.scripts.OnEscapePressed(cfg.searchBox)
    assert(cfg.searchToggle:IsShown(), "closing assignment editor did not restore settings search")
  end)
  if cfg.navInput:HasFocus() then cfg.navInput.scripts.OnEscapePressed(cfg.navInput) end
  cfg.tabBtns.look:Click()
  X.SetAssignment("DRUID", "TANK", savedRule)
  X.SetAssignmentEnabled(savedEnabled)
  X.RefreshConfig()
  X.Refresh()
  assert(ok, err)
end)

step("assignment preview opens, pages without scanning, and closes with settings", function()
  local X, cfg, slash = NS.X, env.BuffRadarConfig, env.SlashCmdList.BUFFRADAR
  if not env.__forever then
    slash("buffassign preview")
    assert(not env.BuffRadarAssignmentPreview, "assignment preview appeared on the other edition")
    return
  end
  local original = X.AssignmentPreview
  local ok, err = pcall(function()
    local scans, members = 0, {}
    for i = 1, 16 do
      members[i] = { name = "Member" .. i, rule = "Druid role", evaluated = true, buffs = { "Thorns" }, available = {} }
    end
    members[1].group = "Prayer of Fortitude is blocked by 40 group members."
    members[1].groupDetails = {}
    for i = 1, 40 do
      members[1].groupDetails[i] = "Blocker " .. i .. " · Druid tank rule excludes Fortitude"
    end
    members[2] = { name = "Member2", rule = "Rule unavailable", status = "Player details unavailable" }
    X.AssignmentPreview = function() scans = scans + 1; return members end
    slash("buffassign")
    local panel = env.BuffRadarAssignments
    panel.previewButton:Click()
    local preview = env.BuffRadarAssignmentPreview
    assert(preview:IsVisible() and scans == 1 and preview.rows[1].name == "Member1",
      "preview did not open with a roster snapshot")
    assert(preview.rows[1].description:find("Thorns", 1, true), "preview detail omitted a spell")
    assert(preview.rows[2].detail:GetText() == NS.X.L["Player details unavailable"], "unreadable row implied buff coverage")
    slash("config navigate")
    local input = cfg.navInput
    local function advanceTo(widget)
      for _ = 1, 15 do
        if cfg.navOutline.shown and cfg.navOutline.points[1][2] == widget then return end
        input.scripts.OnTabPressed(input)
      end
      error("could not focus a preview control")
    end
    advanceTo(preview.rows[1])
    input.scripts.OnEnterPressed(input)
    assert(scans == 1 and preview.rows[1].name == "Member1", "activating a member changed the snapshot")
    local blockers = assert(env.BuffRadarAssignmentBlockers)
    assert(blockers:IsVisible() and blockers.rows[1].text:GetText() == members[1].groupDetails[1],
      "opening the preview row did not show the first blocker")
    for _ = 1, 6 do blockers.next:Click() end
    assert(blockers.rows[4].text:GetText() == members[1].groupDetails[40] and not blockers.next:IsShown(),
      "paged blocker view did not reach the end of a full raid")
    blockers:Hide()
    assert(cfg.navOutline.shown and cfg.navOutline.points[1][2] == preview.rows[1],
      "closing blocker details did not restore focus to the source row")
    advanceTo(preview.next)
    input.scripts.OnEnterPressed(input)
    assert(preview.rows[1].name == "Member8" and scans == 1, "keyboard paging scanned or selected the wrong page")
    preview.scripts.OnMouseWheel(preview, -1)
    assert(preview.rows[1].name == "Member15" and not preview.rows[3]:IsShown(),
      "mouse paging did not clamp to the final members")

    members = {}
    preview.refresh:Click()
    assert(scans == 2 and not preview.rows[1]:IsShown() and not preview.next:IsShown(),
      "refresh retained departed members")
    cfg.scripts.OnEvent(cfg, "PLAYER_REGEN_DISABLED")
    assert(not preview:IsShown() and #preview.members == 0, "combat retained the preview")
    X.RefreshConfig()
    assert(scans == 2, "hidden preview scanned again")
    slash("buffassign preview")
    assert(preview:IsVisible() and scans == 3, "slash did not open a fresh preview")
    slash("config find")
    assert(not preview:IsShown() and cfg.searchBox:HasFocus(), "search did not close the preview")
  end)
  X.AssignmentPreview = original
  if cfg.navInput:HasFocus() then cfg.navInput.scripts.OnEscapePressed(cfg.navInput) end
  if cfg.searchBox:HasFocus() then cfg.searchBox.scripts.OnEscapePressed(cfg.searchBox) end
  cfg.tabBtns.look:Click()
  assert(ok, err)
end)

step("assignment preview edits session roles by identity and protects modal navigation", function()
  if not env.__forever then return end
  local X, cfg, slash = NS.X, env.BuffRadarConfig, env.SlashCmdList.BUFFRADAR
  local originalPreview, originalSet = X.AssignmentPreview, X.SetAssignmentRole
  local ok, err = pcall(function()
    local member = { name = "Mira", unit = "party1", guid = "Player-1-Mira", rule = "Druid World rule",
      evaluated = true, buffs = {}, available = {}, roleEditable = true, roleCanSet = true }
    local second = { name = "Dale", unit = "party2", guid = "Player-1-Dale", rule = "Warrior rule",
      evaluated = true, buffs = {}, available = {}, roleEditable = false }
    local writes, allow = 0, true
    X.AssignmentPreview = function() return { member, second } end
    X.SetAssignmentRole = function(unit, guid, role)
      assert(unit == member.unit and guid == member.guid, "role editor selected a different member")
      writes = writes + 1
      if not allow then return false end
      member.roleOverride = role
      return true
    end
    slash("buffassign preview")
    local preview = env.BuffRadarAssignmentPreview
    local button = preview.rows[1].roleButton
    assert(button:IsVisible() and not preview.rows[2].roleButton:IsVisible(), "role editor ignored member eligibility")
    slash("config navigate")
    local input = cfg.navInput
    local function focus(widget)
      for _ = 1, 15 do
        if cfg.navOutline.shown and cfg.navOutline.points[1][2] == widget then return end
        input.scripts.OnTabPressed(input)
      end
      error("could not focus a role control")
    end
    focus(button)
    input.scripts.OnEnterPressed(input)
    local editor = env.BuffRadarAssignmentRoleEditor
    assert(editor:IsVisible() and editor.member == member, "keyboard did not open the selected member")
    focus(editor.choices.TANK)
    input.scripts.OnEnterPressed(input)
    assert(not editor:IsShown() and member.roleOverride == "TANK" and writes == 1,
      "role did not save through keyboard activation")
    button:Click()
    assert(editor.choices.TANK.navigation.value() ~= nil, "selection is not available for narration")
    allow = false
    editor.choices.HEALER:Click()
    assert(not editor:IsShown() and member.roleOverride == "TANK" and writes == 2,
      "a rejected stale role request was presented as saved")
    allow, member.roleCanSet = true, false
    preview.refresh:Click()
    button:Click()
    assert(not editor.choices.HEALER:IsVisible() and editor.choices.GAME:IsVisible(),
      "editor allowed replacing a game role or hid the clear action")
    editor.choices.GAME:Click()
    assert(member.roleOverride == nil and writes == 3, "Use Game Role did not clear the override")
    member.roleCanSet = true
    preview.refresh:Click()
    button:Click()
    cfg.scripts.OnEvent(cfg, "PLAYER_REGEN_DISABLED")
    assert(not editor:IsShown() and not editor.member and not preview.rows[1].member and writes == 3,
      "combat retained the role editor or changed a role")
  end)
  X.AssignmentPreview, X.SetAssignmentRole = originalPreview, originalSet
  if cfg.navInput:HasFocus() then cfg.navInput.scripts.OnEscapePressed(cfg.navInput) end
  cfg.tabBtns.look:Click()
  assert(ok, err)
end)

step("blocker shortcuts stage, review, recheck and refresh the exact edit", function()
  if not env.__forever then return end
  local X, cfg, slash = NS.X, env.BuffRadarConfig, env.SlashCmdList.BUFFRADAR
  local originalPreview, originalSetter = X.AssignmentPreview, X.SetAssignment
  local originalGetException, originalSetException = X.GetBlessingExceptionForGUID, X.SetBlessingExceptionForGUID
  local originalReview, originalApply = X.ReviewBlockerEdit, X.ApplyBlockerEdit
  local ok, err = pcall(function()
    local rule = { kind = "rule", class = "DRUID", slot = "ALL", guid = "BlockerDruid" }
    local exception = { kind = "exception", guid = "BlockerPaladin", name = "Paladin" }
    local edits, remaining, left, revision, incomplete = 0, true, false, 1, false
    local function snapshot()
      local member = { name = "Warrior", identity = "PreviewWarrior", rule = "Tank", buffs = {}, available = {} }
      if remaining then
        member.groupDetails, member.groupActions = { "Druid All Roles", "Roster information unavailable", "Paladin exception" },
          { [1] = not left and rule or nil, [3] = exception }
      end
      return { member }
    end
    X.AssignmentPreview = snapshot
    X.SetAssignment = function(class, slot)
      assert(class == "DRUID" and slot == "ALL", "shortcut did not use the exact inherited rule")
      edits = edits + 1
      left = true
      return true
    end
    X.GetBlessingExceptionForGUID = function(guid)
      assert(guid == exception.guid, "shortcut opened the wrong blessing exception")
      return { name = "Paladin", key = "WISDOM", canSet = true,
        options = { { key = "KINGS", name = "Blessing of Kings" } } }
    end
    X.SetBlessingExceptionForGUID = function(guid, key)
      assert(guid == exception.guid and key == "KINGS", "editor saved the wrong blessing exception")
      remaining = false
      return "Paladin"
    end
    X.ReviewBlockerEdit = function(action, value)
      assert(action == rule or action == exception, "review used the wrong blocker action")
      if action == rule then
        assert(value == nil, "review lost the staged Default rule")
      else
        assert(value == "KINGS", "review lost the staged blessing")
      end
      local rows = { {
        name = revision == 1 and "Mira" or "Dale", gains = { "Kings" }, losses = { "Wisdom" }
      } }
      for _, name in ipairs({ "Aaron", "Bela", "Celia", "Dora", "Eliza" }) do
        rows[#rows + 1] = { name = name, gains = { "Kings" }, losses = {} }
      end
      return { revision = revision, incomplete = incomplete, rows = rows }
    end
    X.ApplyBlockerEdit = function(action, value, before)
      if left and action == rule then return false end
      if revision ~= before.revision then return false, X.ReviewBlockerEdit(action, value) end
      if action == rule then return X.SetAssignment(action.class, action.slot, value) end
      return X.SetBlessingExceptionForGUID(action.guid, value) ~= nil
    end
    slash("buffassign preview")
    local assignments, preview = env.BuffRadarAssignments, env.BuffRadarAssignmentPreview
    preview.rows[1]:Click()
    local blockers = env.BuffRadarAssignmentBlockers
    assert(blockers.rows[1].edit:IsVisible() and not blockers.rows[2].edit:IsShown(),
      "rule shortcut missing or offered for an informational blocker")
    slash("config navigate")
    local input = cfg.navInput
    local function activate(widget)
      for _ = 1, 18 do
        if cfg.navOutline.shown and cfg.navOutline.points[1][2] == widget then
          input.scripts.OnEnterPressed(input)
          return
        end
        input.scripts.OnTabPressed(input)
      end
      error("could not reach an assignment blocker control")
    end
    activate(blockers.rows[1].edit)
    local picker = assignments.picker
    assert(picker:IsVisible() and picker.backButton:IsVisible() and picker.backButton:GetText() == NS.X.L["Cancel"]
      and picker.class == "DRUID" and picker.slot == "ALL",
      "shortcut did not open the inherited All Roles picker")
    activate(picker.defaultButton)
    assert(edits == 0 and picker:IsVisible(), "staging Default saved the rule immediately")
    activate(picker.reviewButton)
    local review = env.BuffRadarBlockerReview
    assert(review:IsVisible() and review.rows[1].heading:GetText() == "Mira"
      and review.rows[1].detail:GetText() == "Gains: Kings"
      and review.rows[2].detail:GetText() == "Loses: Wisdom",
      "review omitted the named impact")
    activate(review.next)
    assert(review.rows[2].heading:GetText() == "Eliza" and not review.next:IsShown(),
      "end of the review was unreachable")
    activate(review.previous)
    activate(review.back)
    assert(not review:IsShown() and picker:IsVisible(), "Back did not return to the draft")
    activate(picker.reviewButton)
    revision = 2
    fire("GROUP_ROSTER_UPDATE")
    runQueued()
    assert(review:IsVisible(), "automatic roster refresh discarded the review")
    activate(review.apply)
    assert(edits == 0 and review:IsVisible() and review.rows[1].heading:GetText() == "Dale"
      and review.notice:GetText():find("Review again", 1, true), "roster change did not require a fresh Apply")
    activate(review.apply)
    assert(edits == 1 and not picker:IsShown() and blockers:IsVisible() and not blockers.rows[1].edit:IsShown(),
      "saving a rule did not return to the refreshed blocker list")

    left = false
    preview.refresh:Click()
    preview.rows[1]:Click()
    blockers.rows[1].edit:Click()
    picker.defaultButton:Click()
    picker.reviewButton:Click()
    left = true
    review.apply:Click()
    assert(edits == 1 and not picker:IsShown() and not review:IsShown() and not blockers.rows[1].edit:IsShown(),
      "a departed member's stale rule was still editable")

    blockers.rows[3].edit:Click()
    local editor = env.BuffRadarBlockerExceptionEditor
    assert(editor:IsVisible() and editor.choices[1]:IsVisible() and not editor.choices[2]:IsShown(),
      "local blessing options did not open")
    editor.choices[1]:Click()
    assert(editor:IsVisible() and remaining, "selecting an exception wrote immediately")
    incomplete = true
    editor.reviewButton:Click()
    assert(not review.apply:IsEnabled() and review.notice:GetText():find("could not be checked", 1, true),
      "incomplete roster did not disable Apply with an explanation")
    review.cancel:Click()
    assert(not editor:IsShown() and not review:IsShown() and remaining, "Cancel saved or left a draft open")
    incomplete = false
    blockers.rows[3].edit:Click()
    editor.choices[1]:Click()
    editor.reviewButton:Click()
    env.__combat = true
    cfg:GetScript("OnEvent")(cfg, "PLAYER_REGEN_DISABLED")
    env.__combat = false
    assert(not assignments:IsShown() and not editor:IsShown() and not review:IsShown() and remaining,
      "entering combat did not discard the draft")
    slash("buffassign preview")
    preview.rows[1]:Click()
    blockers.rows[3].edit:Click()
    assert(editor.draft == "WISDOM", "a cancelled exception draft leaked into the next edit")
    editor.choices[1]:Click()
    editor.reviewButton:Click()
    review.apply:Click()
    assert(preview:IsVisible() and not blockers:IsShown() and not editor:IsShown(),
      "resolved blocker did not return to the preview")
  end)
  X.AssignmentPreview, X.SetAssignment = originalPreview, originalSetter
  X.GetBlessingExceptionForGUID, X.SetBlessingExceptionForGUID = originalGetException, originalSetException
  X.ReviewBlockerEdit, X.ApplyBlockerEdit = originalReview, originalApply
  env.__combat = false
  cfg:Hide()
  assert(ok, err)
end)

step("visible assignment preview refreshes roster and roles without retargeting the editor", function()
  if not env.__forever then return end
  local X, cfg, slash = NS.X, env.BuffRadarConfig, env.SlashCmdList.BUFFRADAR
  local original = X.AssignmentPreview
  local function member(name, unit, editable)
    local guid = "Player-1-" .. name
    return { name = name, unit = unit, guid = guid, identity = guid, roleEditable = editable,
      roleCanSet = editable, rule = "Role rule", buffs = {}, available = {} }
  end
  local ok, err = pcall(function()
    local scans = 0
    local members = { member("Mira", "party1", true), member("Dale", "party2", true) }
    X.AssignmentPreview = function() scans = scans + 1; return members end
    slash("buffassign preview")
    local preview = env.BuffRadarAssignmentPreview
    assert(scans == 1, "initial preview count differed")
    slash("config navigate")
    local input = cfg.navInput
    local function focused(widget)
      return cfg.navOutline.shown and cfg.navOutline.points[1][2] == widget
    end
    for _ = 1, 15 do
      if focused(preview.rows[1].roleButton) then break end
      input.scripts.OnTabPressed(input)
    end
    assert(focused(preview.rows[1].roleButton), "could not focus original member")
    members = { member("Dale", "party1", true), member("Mira", "party2", true) }
    fire("GROUP_ROSTER_UPDATE")
    fire("PLAYER_ROLES_ASSIGNED")
    fire("PARTY_MEMBERS_CHANGED")
    fire("RAID_ROSTER_UPDATE")
    if env.C_Timer then assert(scans == 1, "visible event burst scanned synchronously") end
    runQueued()
    assert(scans == (env.C_Timer and 2 or 5), "incorrect event refresh count")
    assert(preview.rows[1].member.name == "Dale" and focused(preview.refresh),
      "roster refresh kept focus on a different person")

    preview.rows[2].roleButton:Click()
    local editor = env.BuffRadarAssignmentRoleEditor
    members = { member("Mira", "party1", true), member("Dale", "party2", true) }
    fire("GROUP_ROSTER_UPDATE")
    runQueued()
    assert(editor:IsVisible() and editor.member == members[1] and editor.member.unit == "party1",
      "editor did not follow only the original GUID after a roster move")
    members = { member("Mira", "party1", false), member("Dale", "party2", true) }
    fire("PLAYER_ROLES_ASSIGNED")
    runQueued()
    assert(not editor:IsShown(), "editor stayed open when member stopped being editable")

    if env.C_Timer then
      fire("GROUP_ROSTER_UPDATE")
      preview:Hide()
      slash("buffassign preview")
      local reopenedScans = scans
      runQueued()
      assert(scans == reopenedScans, "callback from the old preview refreshed a re-opened preview")
    end
    members = {}
    fire("GROUP_LEFT")
    runQueued()
    assert(not preview.rows[1]:IsShown(), "group leave retained departed members")
    preview:Hide()
    local hiddenScans = scans
    fire("GROUP_ROSTER_UPDATE")
    fire("PLAYER_ROLES_ASSIGNED")
    runQueued()
    assert(scans == hiddenScans, "hidden preview performed a roster scan")
  end)
  X.AssignmentPreview = original
  if cfg.navInput:HasFocus() then cfg.navInput.scripts.OnEscapePressed(cfg.navInput) end
  cfg.tabBtns.look:Click()
  assert(ok, err)
end)

step("keyboard settings navigation changes tabs, checkboxes, sliders, and choices", function()
  local cfg = env.BuffRadarConfig
  cfg.tabBtns.look:Click()
  env.SlashCmdList.BUFFRADAR("config navigate")
  local input = cfg.navInput
  local function focused(widget)
    return cfg.navOutline.shown and cfg.navOutline.points[1][2] == widget
  end
  local function advanceTo(widget)
    for _ = 1, 80 do
      if focused(widget) then return end
      input.scripts.OnTabPressed(input)
    end
    error("could not focus requested control")
  end
  assert(input:HasFocus() and focused(cfg.tabBtns.look), "keyboard mode did not focus the first tab")
  input.scripts.OnTabPressed(input)
  assert(focused(cfg.tabBtns.alerts), "Tab did not focus Alerts")
  input.scripts.OnEnterPressed(input)
  assert(cfg.curTab == "alerts" and focused(cfg.tabBtns.alerts), "Enter did not select Alerts")
  env.IsShiftKeyDown = function() return true end
  input.scripts.OnTabPressed(input)
  env.IsShiftKeyDown = function() return false end
  input.scripts.OnEnterPressed(input)
  assert(cfg.curTab == "look" and focused(cfg.tabBtns.look), "Shift-Tab did not return to Window")
  local check, slider, choice = cfg.titleCheck, cfg.slider, cfg.scaleDrop
  local enabled, alpha, scale = check:GetChecked(), slider:GetValue(), env.BuffRadarDB.scale
  advanceTo(check)
  input.scripts.OnSpacePressed(input)
  assert(check:GetChecked() ~= enabled, "Space did not activate checkbox")
  input.scripts.OnEnterPressed(input)
  advanceTo(slider)
  input.scripts.OnArrowPressed(input, alpha == 100 and "LEFT" or "RIGHT")
  assert(slider:GetValue() ~= alpha, "slider did not change via arrow")
  slider:SetValue(alpha)
  advanceTo(choice)
  input.scripts.OnArrowPressed(input, "RIGHT")
  assert(env.BuffRadarDB.scale ~= scale, "dropdown did not change via arrow")
  env.BuffRadarDB.scale = scale
  advanceTo(cfg.displayBtn)
  input.scripts.OnEnterPressed(input)
  assert(cfg.displayPanel:IsShown() and not cfg.searchToggle:IsShown(), "display panel did not open")
  advanceTo(cfg.barsCheck)
  local bars = cfg.barsCheck:GetChecked()
  input.scripts.OnEnterPressed(input)
  assert(cfg.barsCheck:GetChecked() ~= bars, "navigation did not activate a display option")
  input.scripts.OnEnterPressed(input)
  input.scripts.OnEscapePressed(input)
  assert(not input:HasFocus() and not cfg.navOutline.shown, "Escape did not exit navigation")
  cfg.tabBtns.look:Click()
end)

step("nested search opens persistent destinations and excludes contextual picker actions", function()
  if not env.__forever then return end
  local X, cfg = NS.X, env.BuffRadarConfig
  X.OpenRaidCoverage()
  local assignments, coverage = cfg.assignmentPanel, cfg.assignmentPanel.coverage
  assert(coverage:GetParent() == assignments and assignments:GetParent() == cfg,
    "fixture does not expose the real parent chain")
  local before = X.ProfileSnapshot()
  local nested
  for _, entry in ipairs(X.CfgSearch("")) do
    assert(entry.w ~= assignments.picker.defaultButton and entry.w ~= assignments.picker.noneButton,
      "context-dependent picker choices escaped their search boundary")
    if entry.w == coverage.refresh then nested = entry end
  end
  assert(nested and #nested.path == 2, "persistent nested control lost its opener chain")
  cfg.tabBtns.look:Click()
  assert(not coverage:IsVisible(), "test destination must start hidden")
  env.SlashCmdList.BUFFRADAR("config find")
  cfg.searchBox:SetText(X.L["Refresh Preview"])
  cfg.searchBox.scripts.OnTextChanged(cfg.searchBox)
  local found
  repeat
    for _, row in ipairs(cfg.searchRows) do
      if row.entry == nested then found = row; break end
    end
    if found or not cfg.searchNext:IsEnabled() then break end
    cfg.searchNext:Click()
  until found
  assert(found, "nested result was absent from the actual result viewport")
  found:Click()
  assert(coverage:IsVisible() and coverage.refresh:IsVisible() and cfg.navInput:HasFocus()
    and cfg.navOutline.points[1][2] == coverage.refresh,
    "nested result focused a hidden control or the wrong destination")
  assert(X.ProfileSnapshot() == before, "search navigation changed a saved setting")
  cfg.tabBtns.look:Click()
end)

step("global settings search crosses tabs, pages deterministically, and never changes a value", function()
  local X = NS.X
  local cfg = env.BuffRadarConfig
  env.SlashCmdList.BUFFRADAR("config find")
  local results = X.CfgSearch("", "settings")
  assert(#results > 5, "global registry did not include hidden-tab controls")
  local tabs, previous = {}, nil
  for _, entry in ipairs(results) do
    tabs[entry.tab] = true
    if previous then
      assert(previous.order < entry.order, "search registration order is unstable")
    end
    previous = entry
  end
  local count = 0
  for _ in pairs(tabs) do count = count + 1 end
  assert(count >= 5, "global search only indexed the current tab")
  cfg.searchBox:SetText("opacity"); cfg.searchBox.scripts.OnTextChanged(cfg.searchBox)
  local entry = assert(cfg.searchRows[1].entry)
  assert(entry.tab == "look" and entry.w == cfg.slider, "result lost its destination identity")
  local value = cfg.slider:GetValue()
  cfg.searchRows[1]:Click()
  assert(cfg.curTab == "look" and cfg.navOutline.points[1][2] == cfg.slider and cfg.slider:GetValue() == value,
    "choosing a result did not focus its exact control without mutation")
  env.SlashCmdList.BUFFRADAR("config find")
  cfg.searchBox:SetText("unlikely_search_912"); cfg.searchBox.scripts.OnTextChanged(cfg.searchBox)
  assert(#cfg.searchResults == 0 and not cfg.searchRows[1]:IsShown()
    and cfg.searchHint:GetText() == X.L["No settings or actions match this search."], "no-results state retained a stale selectable row")
  local label = cfg.tabBtns.look:GetText()
  cfg.searchBox:SetText(label); cfg.searchBox.scripts.OnTextChanged(cfg.searchBox)
  assert(#cfg.searchResults > 5 and cfg.searchPage == 1)
  local first = cfg.searchRows[1].entry
  cfg.searchNext:Click()
  assert(cfg.searchPage == 2 and cfg.searchRows[1].entry ~= first, "result paging did not advance")
  cfg.searchPrev:Click()
  assert(cfg.searchPage == 1 and cfg.searchRows[1].entry == first, "result paging was not stable")
  cfg.searchBox.scripts.OnEscapePressed(cfg.searchBox)
end)

step("keyboard settings preserve native text editing and release gameplay focus", function()
  local cfg = env.BuffRadarConfig
  cfg.tabBtns.look:Click()
  env.SlashCmdList.BUFFRADAR("config navigate")
  local input, search = cfg.navInput, cfg.searchBox
  local function advanceTo(widget)
    for _ = 1, 80 do
      if cfg.navOutline.points[1][2] == widget then return end
      input.scripts.OnTabPressed(input)
    end
    error("could not focus requested control")
  end
  advanceTo(cfg.searchToggle)
  input.scripts.OnEnterPressed(input)
  assert(search:HasFocus() and cfg.searchFooter:IsShown() and not input:HasFocus(), "Find did not enter native editing")
  search:SetText("opacity")
  search.scripts.OnTextChanged(search)
  search.scripts.OnEnterPressed(search)
  assert(input:HasFocus() and not cfg.searchFooter:IsShown() and cfg.curTab == "look"
      and cfg.navOutline.points[1][2] == cfg.slider,
    "search selection did not navigate to and focus the matching setting")
  env.SlashCmdList.BUFFRADAR("config find")
  search.scripts.OnEscapePressed(search)
  assert(not cfg.searchFooter:IsShown() and search:GetText() == "" and not search:HasFocus(),
    "search escape did not release native editing")
  env.SlashCmdList.BUFFRADAR("config navigate")
  advanceTo(cfg.searchToggle)
  input.scripts.OnEnterPressed(input)
  env.__combat = true
  cfg.scripts.OnEvent(cfg, "PLAYER_REGEN_DISABLED")
  assert(not search:HasFocus() and not input:HasFocus() and not cfg.navOutline.shown and not cfg.searchFooter:IsShown(),
    "combat did not release native editing or clean up the settings search")
  env.__combat = false
  env.SlashCmdList.BUFFRADAR("config navigate")
  cfg.titleCheck.scripts.OnMouseDown(cfg.titleCheck)
  assert(not input:HasFocus() and not cfg.navOutline.shown, "mouse takeover did not exit navigation")
  env.SlashCmdList.BUFFRADAR("config navigate")
  cfg:Hide()
  assert(not input:HasFocus(), "closing settings did not release keyboard mode")
  env.SlashCmdList.BUFFRADAR("config navigate")
  local external = env.CreateFrame("EditBox", nil, env.UIParent)
  external:SetFocus()
  assert(external:HasFocus() and not input:HasFocus() and not cfg.navOutline.shown,
    "external focus takeover revived BuffRadar keyboard mode")
  external:ClearFocus()
end)

step("settings narration uses the standard game voice and cancels stale speech", function()
  local cfg = env.BuffRadarConfig
  local spoken, scheduled = {}, {}
  local oldVoice, oldEnum, oldSpeech, oldSettings, oldTimer = env.TextToSpeech_GetSelectedVoice, env.Enum,
    env.C_VoiceChat, env.C_TTSSettings, env.C_Timer
  env.Enum = { TtsVoiceType = { Standard = 0 } }
  env.TextToSpeech_GetSelectedVoice = function(voiceType)
    assert(voiceType == 0, "narration did not select the standard voice")
    return { voiceID = 42 }
  end
  env.C_TTSSettings = { GetSpeechRate = function() return 3 end, GetSpeechVolume = function() return 70 end }
  env.C_VoiceChat = { SpeakText = function(...) spoken[#spoken + 1] = { ... } end }
  env.C_Timer = { After = function(_, f) scheduled[#scheduled + 1] = f end }
  local before = #scheduled
  env.SlashCmdList.BUFFRADAR("config narrate")
  cfg.navInput.scripts.OnTabPressed(cfg.navInput)
  for i = before + 1, #scheduled do scheduled[i]() end
  assert(#spoken == 1 and spoken[1][1] == 42 and spoken[1][3] == 3 and spoken[1][4] == 70 and spoken[1][5] == false,
    "narration did not debounce or use the selected voice settings")
  assert(spoken[1][2] == cfg.navStatus:GetText():gsub("&", " "), "spoken text and focus status diverged")
  cfg.navInput.scripts.OnTabPressed(cfg.navInput)
  cfg.navInput.scripts.OnEscapePressed(cfg.navInput)
  scheduled[#scheduled]()
  assert(#spoken == 1, "queued narration spoke after navigation exited")
  env.TextToSpeech_GetSelectedVoice, env.Enum, env.C_VoiceChat, env.C_TTSSettings, env.C_Timer =
    oldVoice, oldEnum, oldSpeech, oldSettings, oldTimer
  local count = #chat
  env.SlashCmdList.BUFFRADAR("config narrate")
  if env.__timers then env.__timers[#env.__timers]() end
  assert(cfg.navInput:HasFocus() and #chat > count + 1, "missing voice did not preserve focus and report a status")
  cfg.navInput.scripts.OnEscapePressed(cfg.navInput)
end)

step("death recap snapshots the group when you die (1.9.0)", function()
  local cleanup = partyOfTwo("DD")
  local db = env.BuffRadarDB
  env.IsSpellInRange = function() return 1 end
  refresh()
  local n = #chat
  fire("PLAYER_DEAD")
  assert(chatTemplate(n,"Death recap: %d %s missing buffs (%d buffs needed) when you died:"), "no death recap printed")
  assert(chatSince(n, "Aaron"), "death recap does not name Aaron")
  local n2 = #chat
  env.SlashCmdList.BUFFRADAR("death show")
  assert(chatSince(n2, NS.X.L["Death recap from your last death:"]), "last recap not reprinted")
  env.SlashCmdList.BUFFRADAR("death")
  assert(db.deathRecap == false, "death recap not toggled off")
  env.SlashCmdList.BUFFRADAR("death")
  assert(db.deathRecap == true, "death recap not toggled back on")
  fire("PLAYER_ALIVE")
  cleanup()
end)

step("post-wipe report fires after a real wipe (1.9.0)", function()
  local cleanup = partyOfTwo("WW")
  local db = env.BuffRadarDB
  local O, X = env.__over, NS.X
  local oldStart = X.combatStart
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
  assert(not chatTemplate(n,"Wipe report: %d of %d died. %s"), "report fired for a single death")
  -- Deaths alone are insufficient without a recorded fight.
  dead.party2 = true
  X.combatStart = nil
  local missingStart = #chat
  fire("PLAYER_REGEN_ENABLED")
  local reportedWithoutStart = chatTemplate(missingStart,"Wipe report: %d of %d died. %s")
  fire("PLAYER_REGEN_DISABLED")
  t = t + 7
  local shortFight = #chat
  fire("PLAYER_REGEN_ENABLED")
  local reportedForShortFight = chatTemplate(shortFight,"Wipe report: %d of %d died. %s")
  -- Both party members dead after a fight at the minimum duration: a wipe.
  fire("PLAYER_REGEN_DISABLED")
  t = t + 8
  local n2 = #chat
  fire("PLAYER_REGEN_ENABLED")
  assert(chatTemplate(n2,"Wipe report: %d of %d died. %s",2,3), "no wipe report after the wipe")
  assert(chatTemplate(n2,"%d %s missing buffs (%d buffs needed):",1,NS.X.L["person is"]),
    "wipe report should list the survivor's missing buffs")
  local duplicateEnd = #chat
  fire("PLAYER_REGEN_ENABLED")
  local reportedTwice = chatTemplate(duplicateEnd,"Wipe report: %d of %d died. %s")
  local n3 = #chat
  env.SlashCmdList.BUFFRADAR("wipe show")
  assert(chatSince(n3, NS.X.L["Wipe report from the last wipe:"]), "last wipe report not reprinted")
  O.GetTime = nil
  O.UnitIsDeadOrGhost = nil
  X.combatStart = oldStart
  env.SlashCmdList.BUFFRADAR("wipe")
  assert(db.wipeReport == false, "wipe report not toggled off")
  cleanup()
  assert(not reportedWithoutStart and not reportedForShortFight and not reportedTwice,
    "wipe timing was incorrect: without start=" .. tostring(reportedWithoutStart)
      .. ", short fight=" .. tostring(reportedForShortFight) .. ", duplicate end=" .. tostring(reportedTwice))
end)
step("raid wipe counts the player raid token once", function()
  local cleanup = partyOfTwo("WIPE")
  local db, O, X = env.BuffRadarDB, env.__over, NS.X
  local oldRaid, oldNum, oldWipe, oldStart = env.IsInRaid, env.GetNumGroupMembers, db.wipeReport, X.combatStart
  local ok, err = pcall(function()
    env.IsInRaid, env.GetNumGroupMembers = function() return true end, function() return 6 end
    db.wipeReport = true
    O.UnitExists = function(u) return u == "player" or u:match("^raid[1-6]$") ~= nil end
    O.UnitGUID = function(u) return (u == "player" or u == "raid1") and "Player-1-0001" or "Player-1-" .. u end
    O.UnitClass = function() return "Mage", "MAGE" end
    local dead = { player = true, raid1 = true, raid2 = true }
    O.UnitIsDeadOrGhost = function(u) return dead[u] or false end
    local last = #chat
    X.combatStart = env.GetTime() - 8
    X.WipeCheck()
    assert(not chatTemplate(last,"Wipe report: %d of %d died. %s"), "two unique raid deaths triggered a wipe")
    dead.raid3 = true
    X.combatStart = env.GetTime() - 8
    X.WipeCheck()
    assert(chatTemplate(last,"Wipe report: %d of %d died. %s",3,6), "raid wipe roster double-counted the local player")
  end)
  cleanup()
  env.IsInRaid, env.GetNumGroupMembers, db.wipeReport, X.combatStart = oldRaid, oldNum, oldWipe, oldStart
  assert(ok, err)
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
  assert(coverHas(string.format(NS.X.L["%d/%d fully buffed"],0,3)), "coverage progress not shown")
  env.SlashCmdList.BUFFRADAR("cover progress off")
  assert(db.coverParts.progress == false, "cover part not stored")
  refresh()
  assert(not coverHas(string.format(NS.X.L["%d/%d fully buffed"],0,3)), "coverage progress still shown after off")
  env.SlashCmdList.BUFFRADAR("cover progress on")
  refresh()
  assert(coverHas(string.format(NS.X.L["%d/%d fully buffed"],0,3)), "coverage progress did not come back")
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
  cleanup2()
  cleanup2 = partyOfTwo("UTF8")
  O2.UnitFullName = function(u) if u == "party1" then return "Äë哈😀z", "OtherRealm" end end
  refresh()
  arow2 = findRow()
  assert(arow2 and arow2.name.text == "Äë哈😀…",
    "shortened name split a UTF-8 character: " .. tostring(arow2 and arow2.name.text))
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
  assert(r1.entry.castGuid == env.UnitGUID(r1.entry.unit), "folded row lost the real target GUID")
  local count = db.castsTotal
  local spellID = env.__forever and 1244 or 462854
  local oldSpell = env.C_Spell
  env.C_Spell = { GetSpellIDForSpellIdentifier = function() return spellID end }
  clickCast(r1, "folded-row-cast", spellID, env.UnitName(r1.entry.unit), nil, "UNIT_SPELLCAST_SUCCEEDED", true)
  env.C_Spell = oldSpell
  assert(db.castsTotal == count + 1 and db.history[#db.history].who == env.UnitName(r1.entry.unit),
    "folded row failed to record its actual recipient")
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

step("Quick Setup stages activity and role, supports Back and cancel, and applies only on Finish", function()
  local db = env.BuffRadarDB
  assert(db.wizardSeen == false, "wizard should start unseen on a fresh save")
  local old = {}
  for _, key in ipairs({ "sortMode", "groupOnly", "groupCast", "pauseInCities", "forecastSeconds",
      "smartPriority", "scanThrottle", "visualAlerts", "statusMinimap" }) do old[key] = db[key] end
  local theme, enabled = db.theme, db.enabled
  env.SlashCmdList.BUFFRADAR("wizard")
  local w = env.BuffRadarWizard
  assert(w and w.shown and w.page == 1, "wizard did not open")
  w.choice[2]:Click()
  assert(w.page == 2 and db.sortMode == old.sortMode and db.groupOnly == old.groupOnly,
    "choosing an activity applied a preset before review")
  w.choice[3]:Click()
  assert(w.page == 3 and w.draft.role == "DAMAGER" and db.forecastSeconds == old.forecastSeconds,
    "choosing a role modified the save before review")
  w.back:Click()
  assert(w.page == 2 and w.choice[3]:GetText():find("+ ", 1, true) == 1, "Back lost the selected role")
  w.close:Click()
  assert(not w.shown and not w.draft and db.sortMode == old.sortMode, "cancel applied drafted settings")
  local shift = env.IsShiftKeyDown
  env.IsShiftKeyDown = function() return true end
  local button = env.BuffRadarMinimapButton
  button.scripts.OnClick(button, "RightButton")
  env.IsShiftKeyDown = shift
  assert(w.shown and w.page == 1 and not w.draft.activity, "shift-right-click did not start a fresh wizard")
  w.choice[3]:Click()
  w.choice[1]:Click()
  w.next:Click()
  assert(db.wizardSeen and not w.shown and db.sortMode == "role" and db.smartPriority
    and db.forecastSeconds == 60 and db.scanThrottle and db.visualAlerts and db.statusMinimap,
    "Tank + Raid did not apply the reviewed setup")
  assert(db.theme == theme and db.enabled == enabled, "Quick Setup changed the theme or selected buffs")
  for key, value in pairs(old) do db[key] = value end
  NS.X.SettingsChanged({ liteMode = true, forecastSeconds = true, statusMinimap = true, visualAlerts = true })
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

step("scrolling virtualizes secure rows without moving the cast queue", function()
  local X, db, O = NS.X, env.BuffRadarDB, env.__over
  local saved, savedOverrides = {}, {}
  local fields = { "includeSelf", "hidden", "groupOnly", "autoHide", "pauseInCities", "sortMode", "nameTrim",
    "viewMode", "twoCol", "castMethod", "modClick", "groupCast", "roleFilter", "locked", "clickThrough", "showRealm" }
  for _, field in ipairs(fields) do saved[field] = db[field] end
  for key, value in pairs(O) do savedOverrides[key] = value end
  local oldRaid, oldGroup, oldMembers = env.IsInRaid, env.IsInGroup, env.GetNumGroupMembers
  local oldMouse, oldSearch = env.__mouseButtonDown, X.search
  local frame = env.BuffRadarFrame
  local head, tail = env.BuffRadarRow1, env.BuffRadarRow15
  local nextButton, groupButton = env.BuffRadarNextButton, env.BuffRadarGroupButton
  local count, scans, changedToken = 20, 0, nil
  local function findIndex(unit)
    local i = tonumber(unit:match("^raid(%d+)$"))
    if i and i <= count then return i end
  end
  local function unitName(unit)
    local i = findIndex(unit)
    if i then return string.format("Scroll Raider %02d", i) end
    if unit == "player" then return "Scroll Tester" end
  end
  local function position(button, target)
    assert(button.entry and button.entry.unit == target,
      "expected row " .. target .. ", got " .. tostring(button.entry and button.entry.unit))
    assert(button:GetAttribute("type") == "spell" and button:GetAttribute("unit") == target,
      "secure row did not bind " .. target)
    assert(button:GetAttribute("spell") == button.entry.missing[1], "stale secure spell for " .. target)
    local groupSpell = X.GroupSpellFor(button.entry.missing[1])
    if env.__forever and groupSpell then
      assert(button:GetAttribute("shift-type1") == "spell" and button:GetAttribute("shift-unit1") == target
        and button:GetAttribute("shift-spell1") == groupSpell, "stale modifier binding for " .. target)
    end
    assert(button.name:GetText() == unitName(target), "displayed name differs from secure target")
  end
  local lockedWrites = {}
  local function guard(frameToGuard)
    local write = frameToGuard.SetAttribute
    lockedWrites[frameToGuard] = frameToGuard.SetAttribute
    frameToGuard.SetAttribute = function(self, ...)
      assert(not env.__combat, "scroll wrote a protected cast attribute during combat")
      return write(self, ...)
    end
  end
  local function scroll(widget, delta)
    local handler = assert(widget:GetScript("OnMouseWheel"), "missing registered wheel handler")
    handler(widget, delta)
  end
  local function visibleRange(first, last, total)
    local text = string.format(X.L["Rows %d–%d of %d"], first, last, total)
    for _, fs in ipairs(env.__fontstrings) do
      if fs:GetText() == text and fs:IsShown() then return true end
    end
    return false
  end
  local ok, err = pcall(function()
    env.IsInRaid, env.IsInGroup = function() return true end, function() return true end
    env.GetNumGroupMembers = function() return count + 1 end
    O.UnitExists = function(unit) return unit == "player" or findIndex(unit) ~= nil end
    O.UnitIsPlayer, O.UnitName = O.UnitExists, unitName
    O.UnitFullName = function(unit) return unitName(unit), "TestRealm" end
    O.UnitGUID = function(unit)
      if unit == "player" then return "Player-1-0001" end
      local i = findIndex(unit)
      if i then return (unit == changedToken and "Player-1-changed-" or "Player-1-scroll-") .. i end
    end
    O.UnitClass = function(unit)
      local class = unit == "player" and (env.__forever and "PRIEST" or "SHAMAN") or "WARRIOR"
      return class, class
    end
    O.Aura = function() scans = scans + 1 end
    O.IsSpellInRange = function() return 1 end
    db.includeSelf, db.hidden, db.groupOnly, db.autoHide, db.pauseInCities = false, false, false, false, false
    db.sortMode, db.viewMode, db.twoCol, db.castMethod = "name", "people", false, "target"
    db.modClick, db.groupCast, db.roleFilter = true, false, "ALL"
    db.locked, db.clickThrough, db.showRealm = false, false, false
    db.nameTrim = 0
    X.search = "scroll raider"
    X.Refresh()

    position(head, "raid1")
    position(tail, "raid15")
    assert(visibleRange(1, 15, 20), "initial viewport range is missing")
    assert(frame:IsMouseWheelEnabled() and head:IsMouseWheelEnabled(), "overflow viewport did not enable wheel input")
    assert(nextButton:GetAttribute("unit") == "raid1", "next was not armed for the queue head")
    assert(groupButton:GetAttribute("unit") == "raid1", "group cast was not armed for the queue head")
    local before = scans
    scroll(head, -1)
    position(head, "raid2")
    position(tail, "raid16")
    assert(visibleRange(2, 16, 20), "scroll did not update the viewport range")
    assert(scans == before, "wheel input performed a new aura scan")
    assert(nextButton:GetAttribute("unit") == "raid1" and groupButton:GetAttribute("unit") == "raid1",
      "scrolling moved a cast keybind away from the queue head")

    env.__mouseButtonDown = "LeftButton"
    if head:GetScript("OnMouseDown") then head:GetScript("OnMouseDown")(head, "LeftButton") end
    scroll(head, -1)
    position(head, "raid2")
    env.__mouseButtonDown = nil
    if head:GetScript("OnMouseUp") then head:GetScript("OnMouseUp")(head, "LeftButton") end

    changedToken = "raid17"
    scroll(frame, -1)
    position(head, "raid3")
    assert(not tail:GetAttribute("type") and not tail:GetAttribute("shift-type1"),
      "a recycled row stayed armed after its snapshot GUID changed")
    changedToken = nil
    refresh()
    position(tail, "raid17")
    changedToken = "raid17"
    local clickStart = assert(tail:GetScript("PreClick"), "missing secure click preparation")
    clickStart(tail, "LeftButton", false)
    assert(not tail:GetAttribute("type") and not tail:GetAttribute("shift-type1"),
      "row click could cast on a recycled unit token after scrolling")
    local clickEnd = tail:GetScript("PostClick")
    if clickEnd then clickEnd(tail, "LeftButton", false) end
    changedToken = nil
    refresh()
    position(tail, "raid17")

    env.__mouseButtonDown = "LeftButton"
    head:GetScript("OnMouseDown")(head, "LeftButton")
    env.__combat = true
    fire("PLAYER_REGEN_DISABLED")
    env.__combat = false
    fire("PLAYER_REGEN_ENABLED")
    env.__mouseButtonDown = nil
    head:GetScript("OnMouseUp")(head, "LeftButton")
    -- Simulate reusing the button between physical release and secure dispatch.
    X.Refresh()
    scroll(frame, -1)
    position(head, "raid4")
    head:GetScript("PreClick")(head, "LeftButton", false)
    assert(not head:GetAttribute("type") and not head:GetAttribute("shift-type1"),
      "mouse release after combat could cast on a different recipient than mouse down")
    head:GetScript("PostClick")(head, "LeftButton", false)
    refresh()

    for _ = 1, 25 do scroll(frame, -1) end
    position(head, "raid6")
    position(tail, "raid20")
    assert(not env.BuffRadarRow16, "scrolling expanded the secure row pool")

    db.twoCol = true
    refresh()
    position(head, "raid6")
    position(tail, "raid20")
    assert(tail.points[1][4] > head.points[1][4], "last scrolled slot did not use the second column")

    for i = 1, 15 do guard(env["BuffRadarRow" .. i]) end
    guard(nextButton)
    guard(groupButton)
    env.__combat = true
    fire("PLAYER_REGEN_DISABLED")
    assert(not head:GetAttribute("type") and not tail:GetAttribute("type")
      and not nextButton:GetAttribute("type") and not groupButton:GetAttribute("type"),
      "secure drivers left scrolled casts armed during combat")
    local lockedOffset, lockedScans = X.rowOffset, scans
    scroll(head, 1)
    scroll(frame, 1)
    assert(X.rowOffset == lockedOffset and scans == lockedScans, "wheel changed the viewport during lockdown")
    env.__combat = false
    fire("PLAYER_REGEN_ENABLED")
    refresh()
    assert(head.entry and head:GetAttribute("unit") == head.entry.unit, "combat exit did not rearm the visible target")

    db.viewMode = "buffs"
    refresh()
    assert(head.entry and head.entry.spell and head.entry.castGuid,
      "folded view did not keep a concrete recipient")
    assert(head:GetAttribute("unit") == head.entry.unit
      and head:GetAttribute("spell") == head.entry.spell, "folded row lost its secure cast target")
    assert(not frame:IsMouseWheelEnabled() and not tail:GetAttribute("type"),
      "switching to a short folded view left overflowing casts armed")
    db.viewMode = "people"
    refresh()
    position(head, "raid1")

    X.search = "scroll raider 02"
    refresh()
    position(head, "raid2")
    assert(not tail:IsShown() and not tail:GetAttribute("type") and not frame:IsMouseWheelEnabled(),
      "filter shrink left an offscreen cast or scrolling enabled")
    X.search = "scroll raider"
    count = 4
    refresh()
    position(head, "raid1")
    assert(not tail:IsShown() and not tail:GetAttribute("shift-type1"), "roster shrink left modifier casts armed")
  end)
  env.__combat, env.__mouseButtonDown = false, oldMouse
  for widget, write in pairs(lockedWrites) do widget.SetAttribute = write end
  for key in pairs(O) do O[key] = nil end
  for key, value in pairs(savedOverrides) do O[key] = value end
  for _, field in ipairs(fields) do db[field] = saved[field] end
  env.IsInRaid, env.IsInGroup, env.GetNumGroupMembers = oldRaid, oldGroup, oldMembers
  X.search = oldSearch
  refresh()
  assert(ok, err)
end)

step("coverage uptime scores the run (1.6.0)", function()
  local cleanup = partyOfTwo("V")
  env.IsSpellInRange = function() return 1 end
  env.SlashCmdList.BUFFRADAR("uptime reset")
  refresh()  -- everyone is missing buffs: the full-scan share is 0%
  local n = #chat
  env.SlashCmdList.BUFFRADAR("uptime")
  assert(chatTemplate(n,"Coverage uptime this run: %d%%",0), "uptime not 0% while buffs are missing")
  env.__over.Aura = function(u, name) return { expirationTime = env.GetTime() + 600 } end
  env.SlashCmdList.BUFFRADAR("uptime reset")
  for i = 1, 12 do refresh() end
  local cover
  for _, fs in ipairs(env.__fontstrings) do
    if type(fs.text) == "string" and localizedMatch(fs.text,"Uptime %d%%",100) then cover = fs.text end
  end
  assert(cover, "coverage line shows no 100% uptime after full scans")
  fire("CHALLENGE_MODE_START")  -- a new run resets the score
  local n2 = #chat
  env.SlashCmdList.BUFFRADAR("uptime")
  assert(chatSince(n2,NS.X.L["Coverage uptime: no grouped scans yet this run."]), "uptime not reset at run start")
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
  assert(chatTemplate(n,"Auto profile for %s: %s","dungeon","dset"), "auto profile load not announced")
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
  assert(chatTemplate(failure,"Auto profile for %s could not load '%s': %s","dungeon","Missing"), "failed auto profile did not explain the failure")
  failure = #chat
  fire("ZONE_CHANGED_NEW_AREA")
  assert(not chatTemplate(failure,"Auto profile for %s could not load '%s': %s","dungeon","Missing"), "failed auto profile repeated during same visit")
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
    X.Core.BuildBuffList()
    if env.BuffRadarBlessingPreferences then env.BuffRadarBlessingPreferences:Hide() end
    if X.RefreshConfig then X.RefreshConfig() end
  end
  local ok, err = pcall(function()
    env.IsPlayerSpell = function(id) return id == 19740 or id == 19742 or oldKnown(id) end
    db.blessingPreferences, X.blessPlan.MAGE = {}, nil
    X.Core.BuildBuffList()
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
    X.OpenConfig(true)
    X.RefreshConfig()
    assert(cfg.blessingButton.shown, "known blessings did not expose the settings button")
    cfg.blessingButton:GetScript("OnClick")(cfg.blessingButton)
    assert(env.BuffRadarBlessingPreferences.shown and #cfg.blessingSelectors == 9,
      "blessing settings did not show one control per Forever class")
    env.IsPlayerSpell = function(id) return id == 19742 or oldKnown(id) end
    X.Core.BuildBuffList()
    assert(X.BlessingForClass("MAGE").name == "Blessing of Wisdom" and db.blessingPreferences.MAGE == "MIGHT",
      "an unavailable saved preference did not fall back without clearing it")
  end)
  cleanup()
  assert(ok, err)
end)
step("Forever nearby blessing complement respects caster ownership and explicit rules", function()
  if not env.__forever then return end
  local cleanup = twoTanks()
  local X, O, db = NS.X, env.__over, env.BuffRadarDB
  local oldKnown, oldAuras, oldSecret = env.IsPlayerSpell, env.C_UnitAuras, env.issecretvalue
  local oldComplement, oldPrefs, oldRules, oldMode = db.blessingComplement, db.blessingPreferences, db.buffAssignments, db.assignmentEnabled
  local oldPlan, oldEnabled, oldContext = X.blessPlan, db.enabled.BLESSINGS, db.buffContext.BLESSINGS
  local ok, err = pcall(function()
    local kings, greater, wisdom, might = "Blessing of Kings", "Greater Blessing of Kings", "Blessing of Wisdom", "Blessing of Might"
    local unit = "nameplate1"
    local expiry, auras = env.GetTime() + 600, {}
    env.IsPlayerSpell = function(id) return id == 20217 or id == 19742 or id == 19740 or oldKnown(id) end
    db.blessingComplement, db.blessingPreferences, db.buffAssignments, db.assignmentEnabled = true, {}, {}, false
    db.enabled.BLESSINGS, db.buffContext.BLESSINGS, X.blessPlan = true, nil, {}
    env.IsSpellInRange = function() return 1 end
    O.Aura = function(u, name) if u == unit then return auras[name] end; return nil end
    X.Core.BuildBuffList()
    local function aura(owner, timer)
      return { isFromPlayerOrPlayerPet = owner, expirationTime = timer or expiry }
    end
    local scan = 0
    local function offers(expected)
      X.Refresh()
      scan = scan + 1
      local row = shownRows()[unit] or {}
      for _, name in ipairs({ kings, wisdom, might }) do
        assert((row[name] == true) == (expected == name), "scan " .. scan .. " unexpected queue spell: " .. name .. "; wanted " .. tostring(expected))
      end
    end
    offers(kings) -- Default remains Kings when no other Paladin has covered the Warrior.
    auras[kings] = aura(false)
    offers(might) -- A Warrior gets Strength instead of duplicating another Paladin's Kings.
    unit = "nameplate2"
    offers(wisdom)
    local slash, sent = env.SlashCmdList.BUFFRADAR, #env.__addonSent
    slash("bless complement off")
    assert(not db.blessingComplement and #env.__addonSent == sent, "local opt-out was broadcast")
    offers(nil)
    slash("bless complement on")
    assert(db.blessingComplement and #env.__addonSent == sent, "world blessing toggle was not local")
    offers(wisdom)
    local before = #chat
    slash("why Tank2")
    assert(chatSince(before, "complement another Paladin") and chatSince(before, wisdom),
      "why disagreed with the nearby blessing on offer")
    auras[might] = aura(true)
    offers(nil) -- Don't cycle away from your own already-active alternate.
    auras[might].expirationTime = env.GetTime() + 5
    offers(might)
    auras[might], auras[wisdom] = nil, aura(false)
    offers(might)
    auras[might], auras[kings].expirationTime = aura(false), env.GetTime() + 5
    offers(nil) -- Don't overwrite a foreign blessing when no alternative fits.
    auras = { [kings] = aura(true, env.GetTime() + 5) }
    offers(kings)
    auras = { [wisdom] = aura(false) }
    offers(kings) -- The usual preference is already complementary.
    local masked = {}
    env.issecretvalue = function(v) return v == masked end
    auras = { [kings] = aura(masked, env.GetTime() + 5) }
    offers(nil)
    env.issecretvalue = oldSecret

    local list = { { name = greater, expirationTime = expiry, sourceUnit = "nameplate1" } }
    env.C_UnitAuras = { GetBuffDataByIndex = oldAuras.GetBuffDataByIndex }
    O.AuraList = function(u) if u == unit then return list end end
    offers(wisdom) -- Greater and normal share a family, including on the index API.
    env.C_UnitAuras = nil
    offers(wisdom) -- Legacy UnitBuff's caster return carries the same meaning.
    list[1].sourceUnit = "player"
    offers(nil)
    local guid = O.UnitGUID
    list[1].sourceUnit = "target"
    O.UnitGUID = function(u) if u == "target" then return guid("player") end; return guid(u) end
    offers(nil) -- A caster token can alias the player.
    O.UnitGUID = guid
    offers(nil) -- A caster token with no readable GUID is not another Paladin.
    list[1].sourceUnit = "nameplate1"
    list[2] = { name = masked, expirationTime = expiry, sourceUnit = "player" }
    env.issecretvalue = function(v) return v == masked end
    offers(nil) -- An incomplete index read cannot prove the alternate is absent.
    env.issecretvalue, env.C_UnitAuras = oldSecret, oldAuras
    auras = { [kings] = aura(false) }
    O.AuraList = nil

    X.blessPlan.PALADIN = { mine = true, key = "KINGS" }
    offers(nil)
    X.blessPlan.PALADIN = nil
    assert(X.SetAssignmentEnabled(true) and X.SetAssignment("PALADIN", "WORLD", { BLESS_KINGS = true }))
    offers(nil)
    assert(X.SetAssignmentEnabled(false))
    offers(wisdom)
    local details, groupMissing = { cooldown = {}, cooldowns = {} }, {}
    X.Core.Missing(unit, groupMissing, true, false, "why", details)
    assert(not table.concat(groupMissing):find(wisdom, 1, true) and not details.blessing,
      "world option affected a grouped recipient")

    assert(X.SaveProfile("ComplementAudit"), "could not save complement setting")
    local shared = assert(X.ProfileShareText("ComplementAudit", "full"))
    assert(shared:find(";blessingComplement=1;", 1, true), "BR2 did not serialize complement setting")
    assert(not X.ProfileImport(shared:gsub("blessingComplement=1", "blessingComplement=maybe")),
      "BR2 accepted a malformed complement setting")
    local older = shared:gsub(";blessingComplement=1;", ";")
    assert(X.ProfileImport(older, db.profiles.ComplementAudit) and X.LoadProfile("ComplementAudit") and not db.blessingComplement,
      "a pre-v21 BR2 did not retain its legacy complement default")
    offers(nil)
    assert(X.ProfileImport(shared, db.profiles.ComplementAudit) and X.LoadProfile("ComplementAudit") and db.blessingComplement,
      "a shared profile did not restore the opt-in")
    local cfg = env.BuffRadarConfig
    X.OpenConfig(true)
    cfg.blessingButton:Click()
    local check = env.BuffRadarBlessingPreferences.complement
    assert(check:GetChecked(), "blessing panel did not reflect the setting")
    check:SetChecked(false); check:Click()
    assert(not db.blessingComplement, "the complement checkbox did not turn the option off")
  end)
  env.IsPlayerSpell, env.C_UnitAuras, env.issecretvalue = oldKnown, oldAuras, oldSecret
  db.blessingComplement, db.blessingPreferences, db.buffAssignments, db.assignmentEnabled = oldComplement, oldPrefs, oldRules, oldMode
  X.blessPlan, db.enabled.BLESSINGS, db.buffContext.BLESSINGS = oldPlan, oldEnabled, oldContext
  X.DeleteProfile("ComplementAudit")
  if env.BuffRadarBlessingPreferences then env.BuffRadarBlessingPreferences:Hide() end
  X.Core.BuildBuffList()
  cleanup()
  env.IsSpellInRange = nil
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
  assert(chatSince(n0, string.format(NS.X.L["Profile stored: %s (not loaded)."], "RaidNight")), "no save message")
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
  assert(chatTemplate(n,"%s dropped off %s.","Earth Shield","Tank1"), "no drop alert printed")
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
  assert(chatTemplate(n,"%s is on the list (row %s), missing: %s.","Aaron"), "why did not report Aaron listed")
  assert(chatTemplate(n,"%s is on the list (row %s), missing: %s.","Aaron"), "why did not name the missing buffs")
  local O = env.__over
  O.Aura = function(u, name) return { expirationTime = env.GetTime() + 600 } end
  n = #chat
  env.SlashCmdList.BUFFRADAR("why Aaron")
  assert(chatTemplate(n,"%s already has every buff you can give them.","Aaron"), "why did not report Aaron fully buffed")
  O.Aura = nil
  env.SlashCmdList.BUFFRADAR("ignore Aaron")
  n = #chat
  env.SlashCmdList.BUFFRADAR("why Aaron")
  assert(chatTemplate(n,"%s is on your ignore list, so they are never listed. /br unignore %s undoes it.","Aaron","Aaron"), "why did not report the ignore")
  env.SlashCmdList.BUFFRADAR("unignore Aaron")
  n = #chat
  env.SlashCmdList.BUFFRADAR("why Nobody")
  assert(chatTemplate(n,"Why: no readable player matches '%s'. Target or mouse over them, or enable friendly nameplates with /br plates.","Nobody"), "why did not report an unknown name")
  cleanup()
end)
step("/br why finds nearby and mouseover players and disambiguates names", function()
  local cleanup = partyOfTwo("WHY")
  local O, X = env.__over, NS.X
  local oldExists, oldClass, oldGUID, oldName = O.UnitExists, O.UnitClass, O.UnitGUID, O.UnitFullName
  local extras = { nameplate7 = { "Aaron", "OtherRealm" }, mouseover = { "Nearby", "TestRealm" } }
  O.UnitExists = function(u) return extras[u] ~= nil or oldExists(u) end
  O.UnitIsPlayer = O.UnitExists
  O.UnitFullName = function(u)
    if extras[u] then return unpack(extras[u]) end
    return oldName(u)
  end
  O.UnitGUID = function(u) return extras[u] and "Player-1-" .. u or oldGUID(u) end
  O.UnitClass = function(u) if extras[u] then return "Mage", "MAGE" end return oldClass(u) end
  O.UnitCanAssist = function(_, u) return O.UnitExists(u) end
  env.IsSpellInRange = function() return 1 end
  refresh()
  local before, tally = #chat, X.tally
  env.SlashCmdList.BUFFRADAR("why Aaron")
  assert(chatSince(before,NS.X.L["Why: more than one player matches. Use their full name, including realm."]), "ambiguous short name was chosen")
  before = #chat
  env.SlashCmdList.BUFFRADAR("why Aaron-OtherRealm")
  assert(chatTemplate(before,"%s is on the list (row %s), missing: %s.","Aaron"), "friendly nameplate was not resolved")
  before = #chat
  env.SlashCmdList.BUFFRADAR("why Nearby")
  assert(chatTemplate(before,"%s is on the list (row %s), missing: %s.","Nearby"), "mouseover did not resolve")
  assert(X.tally == tally, "listing diagnostic rebuilt live scan state")
  cleanup()
end)
step("Forever nearby diagnostics update their own panel and verify explicit nameplate changes", function()
  if not env.__forever then return end
  local cleanup = partyOfTwo("Nearby")
  local X, O, db = NS.X, env.__over, env.BuffRadarDB
  local oldCVar, oldCount, oldRestore = env.C_CVar, X.playersSeen, db.plateRestore
  db.plateRestore = {}
  local oldRole, oldAssignments, oldMode = env.UnitGroupRolesAssigned, db.buffAssignments, db.assignmentEnabled
  local oldTitle, oldLocked, oldClick = db.showTitle, db.locked, db.clickThrough
  local ok, err = pcall(function()
    local exists, guid, name, full, class = O.UnitExists, O.UnitGUID, O.UnitName, O.UnitFullName, O.UnitClass
    local target, plate = nil, false
    local function alias(unit)
      if unit == "target" then return target or "none" end
      if unit == "nameplate7" and plate then return "party1" end
      return unit
    end
    O.UnitExists = function(unit) return exists(alias(unit)) end
    O.UnitIsPlayer = O.UnitExists
    O.UnitGUID = function(unit) return guid(alias(unit)) end
    O.UnitName = function(unit) return name(alias(unit)) end
    O.UnitFullName = function(unit) return full(alias(unit)) end
    O.UnitClass = function(unit) return class(alias(unit)) end
    env.IsSpellInRange = function() return 1 end
    env.UnitGroupRolesAssigned = function(unit) return unit == "party1" and "DAMAGER" or "NONE" end
    db.buffAssignments = {}
    assert(X.SetAssignmentEnabled(true) and X.SetAssignment("MAGE", "DAMAGER", false))
    local vars = { nameplateShowFriendlyPlayers = "0", nameplateShowAll = "0", [X.friendlyPlateNamesCVar] = "0" }
    local writes, allow = 0, false
    env.C_CVar = {
      GetCVar = function(key) return vars[key] end,
      SetCVar = function(key, value)
        writes = writes + 1
        if allow then vars[key] = value end
      end,
    }
    refresh()
    assert(shownRows().party2, "the test requires a nonempty cast list")
    db.showTitle = false
    X.ApplyRowLayout()
    db.locked, db.clickThrough = true, true
    X.ApplyClickThrough()
    local help
    for _, widget in ipairs(env.__frames) do
      if widget.parent == env.BuffRadarFrame and widget:GetText() == "?" then help = widget; break end
    end
    assert(help and not help:IsShown(), "nearby help intercepted locked click-through")
    db.locked, db.clickThrough = false, false
    X.ApplyClickThrough()
    X.playersSeen = nil
    local tally, n = X.tally, #chat
    local cast = env.BuffRadarNextButton:GetAttribute("unit")
    assert(help:IsShown(), "nearby help missing from the titleless window with eligible players")
    help:Click()
    local panel = env.BuffRadarNearbyDiagnostics
    assert(panel:IsShown() and panel.togglePlates:IsShown() and panel.nameplates:GetText() == "Friendly nameplates: Off",
      "off nameplates did not offer an action in the diagnostics panel")
    assert(panel.count:GetText():find("unavailable", 1, true) and panel.details:GetText() ~= "",
      "missing scan data or target was not explained")
    assert(writes == 0 and #chat == n and X.tally == tally and env.BuffRadarNextButton:GetAttribute("unit") == cast,
      "opening nearby diagnostics changed the queue, settings, or chat")

    local event = panel:GetScript("OnEvent")
    target = "party1"
    event(panel, "PLAYER_TARGET_CHANGED")
    local reason = panel.details:GetText()
    assert(panel.targetDirty and reason:find("Aaron", 1, true) and reason:find("DPS rule", 1, true)
      and reason:find(NS.X.L["None"], 1, true) and X.tally == tally and #chat == n,
      "the read-only target diagnosis lost the matched party unit or its explicit role rule")
    panel.togglePlates:Click()
    assert(writes == 1 and panel.togglePlates:IsShown() and panel.message:GetText() ~= "",
      "a refused nameplate write was accepted")
    allow = true
    panel.togglePlates:Click()
    assert(writes == 3 and panel.togglePlates:GetText() == NS.X.L["Disable Friendly Nameplates"]
      and panel.restorePlates:IsShown() and panel.nameplates:GetText() == "Friendly nameplates: On",
      "a verified nameplate write did not update the panel")
    panel.plateStyle:Click()
    assert(vars[X.friendlyPlateNamesCVar] == "1" and panel.plateStyle:GetText() == NS.X.L["Show Friendly Health Bars"],
      "names-only control did not update the native style")
    panel.restorePlates:Click()
    assert(not panel.restorePlates:IsShown() and vars.nameplateShowAll == "0" and vars[X.friendlyPlateNamesCVar] == "0"
      and panel.togglePlates:GetText() == NS.X.L["Enable Friendly Nameplates"], "restore did not return the panel and CVars to baseline")
    assert(#chat == n and X.tally == tally, "the plate controls posted chat or rebuilt the queue synchronously")
    vars.nameplateShowFriendlyPlayers = nil
    event(panel, "CVAR_UPDATE")
    assert(panel.nameplates:GetText() == "Friendly nameplates: Unknown" and not panel.togglePlates:IsShown()
      and panel.message:GetText() == "", "unknown nameplate setting was treated as a writable off setting")

    plate = true
    refresh()
    assert(panel.count:GetText() == "Player nameplates seen on last scan: 1" and not panel.targetDirty,
      "the panel did not pick up the completed scan and resolve its pending target update")
    target = nil
    panel.refresh:Click()
    assert(not panel.details:GetText():find("Aaron", 1, true), "refresh kept a missing target's old diagnosis")

    env.__combat = true
    fire("PLAYER_REGEN_DISABLED")
    assert(not panel:IsShown() and not panel.events.PLAYER_TARGET_CHANGED,
      "combat left nearby diagnostics visible or subscribed")
    env.SlashCmdList.BUFFRADAR("nearby")
    assert(not panel:IsShown(), "the nearby command opened in combat")
    env.__combat = false
    fire("PLAYER_REGEN_ENABLED")
    env.SlashCmdList.BUFFRADAR("nearby")
    assert(panel:IsShown(), "the nearby slash command did not open the same panel")
    fire("PLAYER_DEAD")
    assert(not panel:IsShown() and not panel.events.CVAR_UPDATE, "death left nearby diagnostics open")
  end)
  X.CloseNearbyDiagnostics()
  env.C_CVar, env.__combat, X.playersSeen, db.plateRestore = oldCVar, false, oldCount, oldRestore
  env.UnitGroupRolesAssigned, db.buffAssignments, db.assignmentEnabled = oldRole, oldAssignments, oldMode
  db.showTitle, db.locked, db.clickThrough = oldTitle, oldLocked, oldClick
  cleanup()
  fire("PLAYER_ALIVE")
  X.ApplyRowLayout()
  X.ApplyClickThrough()
  assert(ok, err)
end)
step("pull countdown shows on the coverage line (1.15.0)", function()
  if not NS.X.ApiCheck then return end -- optional Extras.lua
  local cleanup = partyOfTwo()
  local pf
  for _, f in ipairs(env.__frames) do if f.events and f.events.START_TIMER then pf = f end end
  assert(pf, "no frame registered START_TIMER")
  env.SlashCmdList.BUFFRADAR("pullflash on")
  refresh()  -- a real scan, so the tally holds casts still needed
  pf.scripts.OnEvent(pf, "START_TIMER", 2, 10, 10)
  assert(NS.X.pull ~= nil, "pull state not set")
  NS.X.Refresh()  -- not refresh(): that drains queued timers, ending the pull
  local found
  for _, fs in ipairs(env.__fontstrings) do
    if type(fs.text) == "string" and localizedMatch(fs.text,"Pull in %ds") then found = fs.text end
  end
  assert(found, "no pull countdown on the coverage line")
  pf.scripts.OnEvent(pf, "START_TIMER", 2, 0, 0)  -- zero cancels
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
step("Forever uses the eligible rank and falls back from an unaffordable group cast", function()
  if not env.__forever then return end
  local cleanup = partyOfTwo("GroupReagent")
  local X, O, db = NS.X, env.__over, env.BuffRadarDB
  local oldSpell, oldCount = env.C_Spell, env.C_Item.GetItemCount
  local oldMode, oldCast, oldMinimum, oldSelf, oldMod =
    db.castMethod, db.groupCast, db.groupCastMin, db.includeSelf, db.modClick
  local oldSort = db.sortMode
  local stock, targetLevel, queries = 0, 12, 0
  local ok, err = pcall(function()
    env.C_Spell = { GetSpellLevelLearned = function(id)
      return ({ [1243] = 1, [1244] = 24, [21562] = 20, [14752] = 50 })[id]
    end }
    env.C_Item.GetItemCount = function(id, banks, charges, reagentBank, accountBank)
      assert(id == 17028 and not banks and not charges and not reagentBank and not accountBank,
        "wrong reagent or counted storage outside the bag")
      queries = queries + 1
      return stock
    end
    O.UnitLevel = function(u) return u == "party1" and targetLevel or 60 end
    O.Aura = function(u, name)
      if u == "player" and (name == "Inner Fire" or name == "Shadowguard") then
        return { expirationTime = env.GetTime() + 1000 }
      end
    end
    env.IsSpellInRange = function() return 1 end
    db.castMethod, db.groupCast, db.groupCastMin, db.includeSelf, db.modClick = "target", false, 2, false, true
    db.sortMode = "name"
    X.InvalidateReagents()
    refresh()
    local row = assert(shownRows().party1.row)
    local nextButton, group = env.BuffRadarNextButton, env.BuffRadarGroupButton
    assert(row:GetAttribute("spell") == 1243 and nextButton:GetAttribute("spell") == 1243,
      "low-level target did not receive rank 1: row=" .. tostring(row:GetAttribute("spell")) ..
      ", next=" .. tostring(nextButton:GetAttribute("spell")) .. ", unit=" ..
      tostring(nextButton.entry and nextButton.entry.unit) .. ", level=" .. tostring(env.UnitLevel("party1")))
    assert(row:GetAttribute("shift-spell1") == 1243 and group:GetAttribute("spell") == 1243,
      "reagent-free fallback did not use the same eligible single-target rank")
    assert(nextButton.bSpellText == "Power Word: Fortitude(Rank 1)", "preview spell rank differs")
    assert(queries == 1, "bags were re-read per row")
    local report = { unknown = 0, people = {
      { unit = "party1", buffs = { "Power Word: Fortitude" } },
      { unit = "party2", buffs = { "Power Word: Fortitude" } },
    } }
    assert(X.ReagentSummary(report):find("17028 0/1", 1, true), "raid-wide reagent estimate double-counted targets")
    local estimate, incomplete = X.ReagentEstimate(report)
    assert(#estimate == 1 and estimate[1].item == 17028 and estimate[1].needed == 1
      and estimate[1].carried == 0 and not incomplete, "zero stock or shared reagent scope lost in checklist")
    db.groupCast = true
    refresh()
    assert(shownRows().party1.row:GetAttribute("spell") == 1243, "automatic group offer ignored empty bags")
    stock = 2
    fire("BAG_UPDATE_DELAYED")
    refresh()
    assert(shownRows().party1.row:GetAttribute("spell") == "Prayer of Fortitude", "restocked bags did not arm a group cast")
    stock = nil
    fire("BAG_UPDATE_DELAYED")
    refresh()
    estimate = X.ReagentEstimate(report)
    assert(#estimate == 1 and estimate[1].needed == 1 and estimate[1].carried == nil
      and X.ReagentSummary(report):find("17028 ?/1", 1, true), "unreadable stock was treated as zero")
    assert(shownRows().party1.row:GetAttribute("spell") == 1243 and (group.bOfferReason or ""):find("Could not check reagent", 1, true),
      "unreadable bags armed a reagent spell or hid the reason")
    targetLevel = 30
    refresh()
    assert(shownRows().party1.row:GetAttribute("spell") == 1244, "level change left a stale cast rank")
    assert(X.DefaultRank("Divine Spirit", 12) == false, "definitively ineligible single-rank spell was admitted")
  end)
  env.C_Spell, env.C_Item.GetItemCount = oldSpell, oldCount
  db.castMethod, db.groupCast, db.groupCastMin, db.includeSelf, db.modClick =
    oldMode, oldCast, oldMinimum, oldSelf, oldMod
  db.sortMode = oldSort
  X.InvalidateReagents()
  cleanup()
  fire("SPELLS_CHANGED")
  refresh()
  assert(ok, err)
end)
step("Forever assignment rules route casts and coverage with safe group fallback", function()
  if not env.__forever then return end
  local cleanup = partyOfTwo("Assign")
  local X, db = NS.X, env.BuffRadarDB
  local oldRole, oldRules, oldMode = env.UnitGroupRolesAssigned, db.buffAssignments, db.assignmentEnabled
  local oldCount = env.C_Item.GetItemCount
  local ok, err = pcall(function()
    local roles = { party1 = "DAMAGER", party2 = "TANK" }
    env.UnitGroupRolesAssigned = function(unit)
      if roles[unit] == "THROW" then error("protected role") end
      return roles[unit]
    end
    local stock = 0
    env.C_Item.GetItemCount = function() return stock end
    X.InvalidateReagents()
    db.buffAssignments = {}
    assert(X.SetAssignment("MAGE", "ALL", { FORTITUDE = true }))
    assert(X.SetAssignment("MAGE", "DAMAGER", false))
    assert(X.SetAssignment("MAGE", "WORLD", { DIVINE_SPIRIT = true }))
    assert(X.SetAssignment("WARRIOR", "TANK", { FORTITUDE = true }))
    assert(X.SetAssignmentEnabled(false))
    refresh()
    assert(shownRows().party1, "disabled grid changed stock eligibility")
    assert(X.SetAssignmentEnabled(true))
    refresh()
    assert(not shownRows().party1 and shownRows().party2, "explicit None failed to override All")
    local report = X.GroupBuffReport(false, true)
    for _, member in ipairs(report.members) do
      if member.unit == "party1" then assert(#member.missing == 0, "coverage ignored None") end
    end
    local offer, _, stockCount, reason = X.GroupOffer("Power Word: Fortitude", "party2")
    assert(offer == nil and reason == "assignment", "empty bags masked an assignment conflict")
    roles.party1 = "THROW"
    fire("PLAYER_ROLES_ASSIGNED")
    refresh()
    local group = X.GroupBuffReport()
    local mage
    for _, member in ipairs(group.people) do if member.unit == "party1" then mage = member end end
    assert(mage and #mage.buffs == 1 and mage.buffs[1] == "Divine Spirit",
      "unreadable role did not choose World")
    assert(X.SetAssignment("MAGE", "WORLD", nil))
    refresh()
    offer, _, stockCount, reason = X.GroupOffer("Power Word: Fortitude", "party2")
    assert(offer == nil and stockCount == 0 and reason == "reagent", "compatible roster ignored empty bags")
    stock = 2
    X.InvalidateReagents()
    assert(X.GroupOffer("Power Word: Fortitude", "party2") == "Prayer of Fortitude",
      "safe group cast stayed suppressed")
    assert(not X.SetAssignment("MAGE", "ALL", { DAMPEN_MAGIC = true, AMPLIFY_MAGIC = true }))
    assert(not X.SetAssignment("MAGE", "ALL", { BLESS_KINGS = true, BLESS_MIGHT = true }))
    assert(not X.SetAssignment("MAGE", "ALL", { CUSTOM123 = true }))
    assert(X.GetAssignment("MAGE", "ALL").FORTITUDE, "invalid edits changed the saved cell")
  end)
  env.UnitGroupRolesAssigned, db.buffAssignments, db.assignmentEnabled = oldRole, oldRules, oldMode
  env.C_Item.GetItemCount = oldCount
  X.InvalidateReagents()
  cleanup()
  refresh()
  assert(ok, err)
end)
step("Forever practice review and apply are isolated from the live group", function()
  if not env.__forever then return end
  local X = NS.X
  local review, apply, undo = X.ReviewBlockerEdit, X.ApplyBlockerEdit, X.blockerUndo
  local profile = X.ProfileSnapshot()
  local config
  local ok, err = pcall(function()
    local function liveEdit() error("practice invoked a live blocker edit") end
    X.ReviewBlockerEdit, X.ApplyBlockerEdit = liveEdit, liveEdit
    env.SlashCmdList.BUFFRADAR("practice")
    config = env.BuffRadarConfig
    local practice = env.BuffRadarPractice
    assert(practice and practice:IsVisible() and not practice.edits[3], "practice allowed editing unavailable sample")
    practice.edits[1]:Click()
    assert(not practice.reviewButton:IsEnabled(), "practice reviewed an unstaged change")
    practice.choice:SetChecked(true)
    practice.choice:Click()
    practice.reviewButton:Click()
    local fakeReview = env.BuffRadarPracticeReview
    assert(fakeReview and fakeReview:IsVisible() and fakeReview.lines[1].name == "Mira", "practice did not show sample rule gains")
    fakeReview.cancel:Click()
    assert(not practice.applied[1], "cancel applied the sample change")
    practice.edits[2]:Click()
    practice.choice:SetChecked(true)
    practice.choice:Click()
    practice.reviewButton:Click()
    assert(#fakeReview.lines == 2 and fakeReview.lines[1].name == "Thoren", "practice did not show both blessing changes")
    fakeReview.apply:Click()
    assert(practice.applied[2] and not fakeReview:IsVisible(), "practice apply did not return to the sample raid")
    assert(X.ProfileSnapshot() == profile and X.blockerUndo == undo, "practice changed live settings or undo history")
  end)
  X.ReviewBlockerEdit, X.ApplyBlockerEdit = review, apply
  if config then config:Hide() end
  assert(ok, err)
end)
step("Forever blocker review compares everyone sharing a rule and rechecks state on Apply", function()
  if not env.__forever then return end
  local cleanup = partyOfTwo("RuleReview")
  local X, O, db = NS.X, env.__over, env.BuffRadarDB
  local oldSize, oldRole = env.GetNumGroupMembers, env.UnitGroupRolesAssigned
  local oldRules, oldMode = db.buffAssignments, db.assignmentEnabled
  local ok, err = pcall(function()
    local fullName, name, class, guid, exists = O.UnitFullName, O.UnitName, O.UnitClass, O.UnitGUID, O.UnitExists
    local fourthGUID = "Player-Beth"
    O.UnitExists = function(unit) return unit == "party3" or exists(unit) end
    O.UnitIsPlayer = O.UnitExists
    O.UnitGUID = function(unit) if unit == "party3" then return fourthGUID end return guid(unit) end
    O.UnitName = function(unit) if unit == "party3" then return "Beth" end return name(unit) end
    O.UnitFullName = function(unit) if unit == "party3" then return "Beth", "TestRealm" end return fullName(unit) end
    O.UnitClass = function(unit) if unit == "party3" then return "Mage", "MAGE" end return class(unit) end
    env.GetNumGroupMembers = function() return 4 end
    env.UnitGroupRolesAssigned = function() return "NONE" end
    env.IsSpellInRange = function() return 1 end
    assert(X.SetAssignmentEnabled(true))
    db.buffAssignments = {}
    assert(X.SetAssignment("MAGE", "ALL", { DIVINE_SPIRIT = true }))
    assert(X.SetAssignment("WARRIOR", "ALL", { FORTITUDE = true }))
    local function action()
      local source = X.AssignmentPreview()[3]
      for _, candidate in pairs(source.groupActions or {}) do
        if candidate.guid == guid("party1") and candidate.single == "Power Word: Fortitude" then return candidate end
      end
      error("missing Aaron's rule blocker")
    end
    local draft = { FORTITUDE = true }
    local editing = action()
    local review = assert(X.ReviewBlockerEdit(editing, draft))
    assert(not review.incomplete and #review.rows == 2 and review.rows[1].name == "Aaron-TestRealm"
      and review.rows[2].name == "Beth-TestRealm", "review omitted a second recipient on the same rule")
    for _, row in ipairs(review.rows) do
      assert(row.gains[1] == "Power Word: Fortitude" and row.losses[1] == "Divine Spirit", "wrong rule delta")
    end
    fourthGUID = "Player-NewBeth"
    local applied, fresh = X.ApplyBlockerEdit(editing, draft, review)
    assert(not applied and fresh and #fresh.rows == 2 and X.GetAssignment("MAGE", "ALL").DIVINE_SPIRIT,
      "a replacement with the same display name skipped reconfirmation")
    assert(X.SetAssignment("WARRIOR", "ALL", false))
    applied, fresh = X.ApplyBlockerEdit(editing, draft, fresh)
    assert(not applied and not fresh and X.GetAssignment("MAGE", "ALL").DIVINE_SPIRIT,
      "an origin no longer eligible for Fortitude approved the edit")
    assert(X.SetAssignment("WARRIOR", "ALL", { FORTITUDE = true }))
    editing = action()
    review = assert(X.ReviewBlockerEdit(editing, draft))
    X.ApplyProfile(assert(X.ParseProfile(X.ProfileSnapshot())))
    assert(not X.ApplyBlockerEdit(editing, draft, review) and X.GetAssignment("MAGE", "ALL").DIVINE_SPIRIT,
      "replacing the profile accepted a draft opened under the previous profile")
    editing = action()
    review = assert(X.ReviewBlockerEdit(editing, draft))
    assert(X.ApplyBlockerEdit(editing, draft, review) and X.GetAssignment("MAGE", "ALL").FORTITUDE,
      "verified shared rule failed to apply")
    assert(not next(X.AssignmentPreview()[3].groupActions or {}), "applied rule did not clear its blockers")
    assert(X.UndoBlockerEdit() and X.GetAssignment("MAGE", "ALL").DIVINE_SPIRIT,
      "undo did not restore the exact prior rule")
    assert(not X.UndoBlockerEdit(), "undo applied the same edit twice")
    assert(X.SetAssignment("MAGE", "ALL", false))
    editing = action()
    assert(X.ApplyBlockerEdit(editing, draft, assert(X.ReviewBlockerEdit(editing, draft))))
    assert(X.UndoBlockerEdit() and X.GetAssignment("MAGE", "ALL") == false,
      "undo did not preserve explicit None")
    editing = action()
    assert(X.ApplyBlockerEdit(editing, draft, assert(X.ReviewBlockerEdit(editing, draft))))
    assert(X.SetAssignment("MAGE", "ALL", nil))
    assert(not X.UndoBlockerEdit() and X.GetAssignment("MAGE", "ALL") == nil,
      "undo overwrote a later edit to the same rule")
  end)
  env.GetNumGroupMembers, env.UnitGroupRolesAssigned = oldSize, oldRole
  db.buffAssignments, db.assignmentEnabled = oldRules, oldMode
  cleanup()
  refresh()
  assert(ok, err)
end)
step("Forever assignment preview and why explain winning rules without changing secure rows", function()
  if not env.__forever then return end
  local cleanup = partyOfTwo("Preview")
  local X, O, db = NS.X, env.__over, env.BuffRadarDB
  local oldRole, oldRules, oldMode = env.UnitGroupRolesAssigned, db.buffAssignments, db.assignmentEnabled
  local oldSize = env.GetNumGroupMembers
  local oldCount, oldTip = env.C_Item.GetItemCount, env.GameTooltip
  local oldIncludeSelf, oldGroupCast, oldClickThrough = db.includeSelf, db.groupCast, db.clickThrough
  local previewAnchor
  for _, widget in ipairs(env.__frames) do
    if widget.parent == env.BuffRadarFrame and widget.kind == "Frame" and widget:GetScript("OnEnter") then
      previewAnchor = widget
      break
    end
  end
  assert(previewAnchor, "next-cast preview control not built")
  local ok, err = pcall(function()
    local role = "DAMAGER"
    env.GetNumGroupMembers = function() return 3 end
    env.UnitGroupRolesAssigned = function(unit)
      if unit == "party2" then return "TANK" end
      if role == "THROW" then error("protected role") end
      return role
    end
    env.IsSpellInRange = function() return 1 end
    env.C_Item.GetItemCount = function() return 2 end
    X.InvalidateReagents()
    O.Aura = function(unit)
      if unit == "player" then return { expirationTime = env.GetTime() + 600 } end
    end
    db.includeSelf, db.groupCast, db.clickThrough = false, false, false
    db.buffAssignments = {}
    assert(X.SetAssignmentEnabled(true))
    assert(X.SetAssignment("MAGE", "ALL", { FORTITUDE = true }))
    assert(X.SetAssignment("MAGE", "DAMAGER", false))
    assert(X.SetAssignment("MAGE", "WORLD", { DIVINE_SPIRIT = true }))
    refresh()
    local nextButton = env.BuffRadarNextButton
    local groupButton = env.BuffRadarGroupButton
    local entry, target = nextButton.entry, nextButton:GetAttribute("unit")
    local conflicts, tally = X.assignmentGroupConflicts, X.tallyUnits
    local function preview()
      local members = X.AssignmentPreview()
      assert(#members == 3, "preview did not count the party and player once: " .. #members)
      assert(members[1].rule:find("Built-in rules", 1, true), "self did not use built-in rules")
      return members[2], members[3]
    end
    local mage, warrior = preview()
    assert(mage.name == "Aaron-TestRealm" and mage.rule:find("DPS rule", 1, true)
      and mage.rule:find(NS.X.L["None"], 1, true) and #mage.buffs == 0, "preview ignored explicit None")
    local details = table.concat(warrior.groupDetails or {}, "\n")
    assert(details:find("Prayer of Fortitude would reach Aaron-TestRealm", 1, true)
      and details:find("DPS rule", 1, true) and details:find(NS.X.L["None"], 1, true),
      "preview lost the group spell, blocking member, or winning rule: " .. details)
    assert(groupButton:GetAttribute("unit") == "party2"
      and groupButton:GetAttribute("spell") == "Power Word: Fortitude", "blocked group key did not use single-target cast")
    local lines = {}
    env.GameTooltip = { SetOwner = function() end, Show = function() end, Hide = function() end,
      AddLine = function(_, line) lines[#lines + 1] = line end }
    previewAnchor:GetScript("OnEnter")(previewAnchor)
    local tooltip = table.concat(lines, "\n")
    assert(tooltip:find("Prayer of Fortitude is blocked by 1 group member.", 1, true),
      "next-cast tooltip did not count the blocker: " .. tooltip)
    assert(not tooltip:find("Aaron-TestRealm", 1, true), "tooltip displayed the full blocker list")
    env.GameTooltip = oldTip
    assert(X.assignmentGroupConflicts == conflicts, "preview changed the live group conflict cache")
    local before = #chat
    env.SlashCmdList.BUFFRADAR("why Aaron")
    assert(chatSince(before, "Applied rule for Aaron: " .. mage.rule .. "."),
      "why lost winning rule: " .. tostring(chat[before + 1]))
    role = "THROW"
    mage = preview()
    assert(mage.rule:find("World rule (role unavailable)", 1, true)
      and mage.buffs[1] == "Divine Spirit", "protected role did not fall back to World")
    assert(X.SetAssignment("MAGE", "WORLD", nil))
    mage = preview()
    assert(mage.rule:find("All Roles rule (role unavailable)", 1, true)
      and mage.available[1] == "Power Word: Fortitude", "missing World did not fall back to All Roles")
    assert(nextButton.entry == entry and nextButton:GetAttribute("unit") == target and X.tallyUnits == tally,
      "preview changed the cast queue or coverage tallies: entry=" .. tostring(nextButton.entry == entry)
      .. " target=" .. tostring(nextButton:GetAttribute("unit") == target) .. " tally=" .. tostring(X.tallyUnits == tally))
    local exists = O.UnitExists
    O.UnitExists = function(unit) if unit ~= "party1" then return exists(unit) end error("protected existence") end
    mage, warrior = preview()
    assert(mage.rule == NS.X.L["Rule unavailable"] and mage.status == NS.X.L["Player details unavailable"] and not mage.evaluated,
      "preview claimed unreadable member was evaluated")
    assert(warrior.group and warrior.group:find("roster information is unavailable", 1, true)
      and not warrior.group:find("Aaron", 1, true) and not warrior.group:find("party1", 1, true),
      "unreadable roster presented a named blocker: " .. tostring(warrior.group))
    O.UnitExists = exists
    O.Aura = function(unit)
      if unit == "player" or unit == "party1" then return { expirationTime = env.GetTime() + 600 } end
    end
    refresh()
    _, warrior = preview()
    assert(warrior.group and warrior.group:find("Group option: Prayer of Fortitude", 1, true)
      and groupButton:GetAttribute("spell") == "Prayer of Fortitude" and not groupButton.bOfferReason,
      "group cast or explanation stayed stale after the assignment changed")

    local fullName, name, class, guid = O.UnitFullName, O.UnitName, O.UnitClass, O.UnitGUID
    O.UnitExists = function(unit) return unit == "party3" or unit == "party4" or exists(unit) end
    O.UnitIsPlayer = function(unit) return unit == "party3" or exists(unit) end
    O.UnitName = function(unit) if unit == "party3" then return "Blair" end return name(unit) end
    O.UnitFullName = function(unit) if unit == "party3" then return "Blair", "TestRealm" end return fullName(unit) end
    O.UnitClass = function(unit) if unit == "party3" then return "Rogue", "ROGUE" end return class(unit) end
    O.UnitGUID = function(unit) if unit == "party3" then return "Player-1-Blocker3" end return guid(unit) end
    env.GetNumGroupMembers = function() return 5 end
    role = "DAMAGER"
    assert(X.SetAssignment("ROGUE", "DAMAGER", false))
    fire("PLAYER_ROLES_ASSIGNED")
    X.Refresh()
    warrior = X.AssignmentPreview()[3]
    details = table.concat(warrior.groupDetails or {}, "\n")
    assert(details:find("Aaron-TestRealm", 1, true) and details:find("Blair-TestRealm", 1, true)
      and details:find("incomplete", 1, true) and not details:find("party4", 1, true),
      "preview lost named blockers or roster uncertainty: " .. details)
    lines = {}
    env.GameTooltip = { SetOwner = function() end, Show = function() end, Hide = function() end,
      AddLine = function(_, line) lines[#lines + 1] = line end }
    previewAnchor:GetScript("OnEnter")(previewAnchor)
    tooltip = table.concat(lines, "\n")
    assert(tooltip:find("Prayer of Fortitude is blocked by 2 group members.", 1, true)
      and tooltip:find("incomplete", 1, true)
      and not tooltip:find("Aaron-TestRealm", 1, true) and not tooltip:find("Blair-TestRealm", 1, true),
      "compact tooltip lost the known count or partial coverage: " .. tooltip)
    assert(groupButton:GetAttribute("spell") == "Power Word: Fortitude", "multi-blocker list changed fallback cast")
  end)
  env.UnitGroupRolesAssigned, db.buffAssignments, db.assignmentEnabled = oldRole, oldRules, oldMode
  env.GetNumGroupMembers, env.C_Item.GetItemCount, env.GameTooltip = oldSize, oldCount, oldTip
  db.includeSelf, db.groupCast, db.clickThrough = oldIncludeSelf, oldGroupCast, oldClickThrough
  X.InvalidateReagents()
  cleanup()
  refresh()
  assert(ok, err)
end)
step("Forever raid coverage keeps exact, missing and unknown buffs by current subgroup", function()
  if not env.__forever then return end
  local cleanup = partyOfTwo("Coverage")
  local X, O, db = NS.X, env.__over, env.BuffRadarDB
  local oldRaid, oldSize, oldRoster = env.IsInRaid, env.GetNumGroupMembers, env.GetRaidRosterInfo
  local oldRebuff, oldEnabled, oldAssignments = db.rebuff, db.enabled, db.assignmentEnabled
  local oldRange = env.IsSpellInRange
  local oldIndexedAura = env.C_UnitAuras.GetBuffDataByIndex
  local ok, err = pcall(function()
    local moved, unknownSubgroup, offline, unknownAura, replacement = false, false, true, false, false
    local function index(unit) return tonumber(unit:match("^raid(%d+)$")) end
    env.IsInRaid = function() return true end
    env.GetNumGroupMembers = function() return 40 end
    env.GetRaidRosterInfo = function(i)
      if i == 40 and unknownSubgroup then return "Last", 0, nil end
      if i == 5 and moved then return "Moved", 0, 2 end
      return "Raid" .. i, 0, math.ceil(i / 5)
    end
    O.UnitExists = function(unit) local i = index(unit); return unit == "player" or i ~= nil and i <= 40 end
    O.UnitIsPlayer = O.UnitExists
    O.UnitGUID = function(unit)
      if unit == "player" then return "Player-self" end
      if unit == "raid5" and replacement then return "Player-replacement" end
      if index(unit) then return "Player-" .. unit end
    end
    O.UnitClass = function() return "Priest", "PRIEST" end
    O.UnitName = function(unit) return unit == "raid5" and "SameName" or unit end
    O.UnitFullName = function(unit) return O.UnitName(unit), "TestRealm" end
    O.UnitIsDeadOrGhost = function(unit) return offline and unit == "raid2" end
    O.Aura = function(unit, spell)
      if spell ~= "Power Word: Fortitude" then return nil end
      if unknownAura and unit == "raid3" then return end
      if index(unit) and not (unit == "raid1" or unit == "raid5" and replacement) then
        return { expirationTime = env.GetTime() + 1 }
      end
      return nil
    end
    env.C_UnitAuras.GetBuffDataByIndex = function(unit, i)
      if unknownAura and unit == "raid3" then return end
      return oldIndexedAura(unit, i)
    end
    db.rebuff, db.enabled, db.assignmentEnabled = 30, { FORTITUDE = true, DIVINE_SPIRIT = false }, false
    env.IsSpellInRange = function() return 0 end
    local function find(report, id)
      for _, group in ipairs(report.groups) do
        if group.id == id then
          for _, buff in ipairs(group.buffs) do if buff.name == "Power Word: Fortitude" then return buff end end
        end
      end
    end
    local beforeSync, beforeChat = #env.__addonSent, #env.__sent
    local tally = X.tallyUnits
    local report = X.RaidCoverage()
    local first = assert(find(report, 1), "Fortitude omitted from group 1")
    assert(report.raid and not report.incomplete and #report.groups == 8 and first.confirmed == 3
      and first.missing[1] == "raid1-TestRealm" and first.unknown[1] == "raid2-TestRealm",
      "coverage lost presence inside rebuff threshold, missing, or dead unknown: "
      .. tostring(report.raid) .. "/" .. tostring(report.incomplete) .. "/" .. #report.groups .. ": "
      .. first.confirmed .. "/" .. table.concat(first.missing, ",") .. "/" .. table.concat(first.unknown, ","))
    assert(find(report, 8).confirmed == 5, "coverage omitted the end of the 40-player raid")
    assert(X.tallyUnits == tally and #env.__addonSent == beforeSync and #env.__sent == beforeChat,
      "coverage changed live scan state or sent a group message")
    env.SlashCmdList.BUFFRADAR("coverage")
    local view = env.BuffRadarRaidCoverage
    local row
    for _, button in ipairs(view.rows) do
      if button.line and button.line.group == 1 and button.line.spell == "Power Word: Fortitude" then row = button; break end
    end
    assert(view:IsVisible() and row and row.counts:GetText() == "3 Confirmed · 1 Missing · 1 Unknown", "summary was not rendered")
    row:Click()
    assert(view.rows[1].heading:GetText() == "Missing: raid1-TestRealm" and view.rows[2].heading:GetText() == "Unknown: raid2-TestRealm",
      "drill-down lost missing and unknown identities")
    moved, replacement, offline, unknownAura, unknownSubgroup = true, true, false, true, true
    X.QueueAssignmentPreviewRefresh()
    runQueued()
    assert(view.report.incomplete and view.selection.group == 1 and find(view.report, 0).confirmed == 1,
      "refresh lost selection or fabricated an unreadable subgroup")
    assert(find(view.report, 2).missing[1] == "SameName-TestRealm" and find(view.report, 1).unknown[1] == "raid3-TestRealm",
      "roster move or same-name replacement inherited old coverage")
    view.back:Click()
    assert(not view.selection and view.rows[1].line.spell, "Back did not return to summary")
    env.__combat = true
    fire("PLAYER_REGEN_DISABLED")
    env.BuffRadarConfig.scripts.OnEvent(env.BuffRadarConfig, "PLAYER_REGEN_DISABLED")
    assert(not view:IsVisible() and X.RaidCoverage() == nil, "coverage stayed available in combat")
  end)
  env.__combat = false
  env.IsInRaid, env.GetNumGroupMembers, env.GetRaidRosterInfo = oldRaid, oldSize, oldRoster
  db.rebuff, db.enabled, db.assignmentEnabled = oldRebuff, oldEnabled, oldAssignments
  env.C_UnitAuras.GetBuffDataByIndex = oldIndexedAura
  env.BuffRadarConfig:Hide()
  cleanup()
  env.IsSpellInRange = oldRange
  fire("PLAYER_REGEN_ENABLED")
  assert(ok, err)
end)
step("Forever Raid Preparation checklist keeps live detail identity and pages reagents", function()
  if not env.__forever then return end
  local cleanup = partyOfTwo("PrepUI")
  local X, slash = NS.X, env.SlashCmdList.BUFFRADAR
  local snapshot = X.RaidPreparationSnapshot
  local ok, err = pcall(function()
    local model = { members = {}, reagents = {}, incomplete = false }
    local calls = 0
    for index = 1, 12 do
      model.members[index] = { guid = "Player-Prep" .. index, name = "Member" .. index,
        status = "clear", details = {} }
    end
    local selected = model.members[2]
    selected.status, selected.unknown = "attention", true
    selected.details = { "Food missing", "Flask unavailable" }
    model.reagents[1] = { name = "Candle", carried = 0, needed = 2 }
    model.reagents[2] = { name = "Powder", needed = 3 }
    for index = 3, 8 do model.reagents[index] = { name = "Reagent" .. index, carried = 4, needed = 1 } end
    X.RaidPreparationSnapshot = function(personal)
      calls = calls + 1
      if personal then return { members = {}, reagents = {}, personal = { { text = "Personal reminder" } } } end
      return model
    end
    slash("coverage")
    local coverage = assert(env.BuffRadarRaidCoverage)
    coverage.preparationButton:Click()
    local view, cfg = assert(env.BuffRadarRaidPreparation), env.BuffRadarConfig
    assert(view:IsVisible() and not coverage:IsVisible() and view.rows[2].line.guid == selected.guid,
      "Coverage did not enter the checklist")
    assert(view.rows[2].heading:GetText():find("Needs Attention · Unknown", 1, true),
      "a known issue with an unknown check looked complete")
    slash("config navigate")
    local input = cfg.navInput
    local function advanceTo(widget)
      for _ = 1, 18 do
        if cfg.navOutline.shown and cfg.navOutline.points[1][2] == widget then return end
        input.scripts.OnTabPressed(input)
      end
      error("could not focus checklist control")
    end
    advanceTo(view.rows[2])
    input.scripts.OnEnterPressed(input)
    assert(view.rows[3].heading:GetText() == "Food missing" and view.rows[4].heading:GetText() == "Flask unavailable",
      "keyboard did not expand the member's checks")
    assert(cfg.navStatus:GetText():find(NS.X.L["Collapse details"], 1, true), "expanded action was not named to keyboard users")
    table.insert(model.members, 8, table.remove(model.members, 2))
    fire("GROUP_ROSTER_UPDATE")
    if env.__timers then X.QueueAssignmentPreviewRefresh() end
    runQueued()
    assert(calls == 2 and view:IsVisible() and view.page == 2 and view.expanded == selected.guid
      and view.rows[3].heading:GetText() == "Food missing", "roster event lost the expanded member or rescanned twice")
    model.members[8] = { guid = "Player-Replacement", name = selected.name, status = "clear", details = {} }
    fire("GROUP_ROSTER_UPDATE")
    runQueued()
    assert(view.expanded == nil and view.page == 2 and not view.rows[3].line.indented,
      "same-name replacement inherited the departed player's checklist")
    view.reagents:Click()
    assert(view.rows[1].hint:GetText() == "0 carried · 2 needed · Shortfall: 2"
      and view.rows[2].hint:GetText() == "Carried quantity unknown · 3 needed",
      "unknown reagent quantity rendered as a shortfall or a known zero was dropped")
    slash("prep next")
    assert(view.page == 2 and view.rows[2].heading:GetText() == "Reagent8", "slash paging missed later reagent rows")
    slash("prep prev")
    assert(view.page == 1, "slash previous did not return to the first reagent page")
    view.back:Click()
    assert(coverage:IsVisible() and not view:IsVisible(), "Back did not restore Raid Coverage")
    slash("prep personal")
    assert(view:IsVisible() and view.tab == "personal" and view.rows[1].heading:GetText() == "Personal reminder",
      "personal mode stopped working")
    X.QueueAssignmentPreviewRefresh()
    slash("prep hide")
    local scanned = calls
    runQueued()
    assert(not view:IsVisible() and calls == scanned, "hiding the checklist left a queued scan")
    slash("prep show")
    env.IsInGroup = function() return false end
    fire("GROUP_LEFT")
    runQueued()
    assert(not view:IsVisible(), "the checklist stayed visible after leaving group")
  end)
  X.RaidPreparationSnapshot = snapshot
  if env.BuffRadarConfig then env.BuffRadarConfig:Hide() end
  cleanup()
  assert(ok, err)
end)

step("Forever subgroup duties constrain casts and preparation reports the whole raid", function()
  if not env.__forever then return end
  local cleanup = partyOfTwo("Subgroup")
  local X, O, db = NS.X, env.__over, env.BuffRadarDB
  local oldRaid, oldSize, oldRoster = env.IsInRaid, env.GetNumGroupMembers, env.GetRaidRosterInfo
  local oldConnected, oldAssignments = O.UnitIsConnected, db.assignmentEnabled
  local oldUnitInRaid = env.UnitInRaid
  local oldKnown, oldOwned = env.IsPlayerSpell, env.C_Item.GetItemCount
  local oldDuties = X.subgroupDuties
  local ok, err = pcall(function()
    local guid, name, full, class = O.UnitGUID, O.UnitName, O.UnitFullName, O.UnitClass
    local group = 2
    local function raidUnit(u) return ({raid1 = "party1", raid2 = "party2"})[u] or u end
    O.UnitExists = function(u) return u == "raid1" or u == "raid2" or u == "player" end
    O.UnitIsPlayer = O.UnitExists
    O.UnitGUID = function(u) return guid(raidUnit(u)) end
    O.UnitName = function(u) return name(raidUnit(u)) end
    O.UnitFullName = function(u) return full(raidUnit(u)) end
    O.UnitClass = function(u) return class(raidUnit(u)) end
    env.IsInRaid = function() return true end
    env.GetNumGroupMembers = function() return 2 end
    env.GetRaidRosterInfo = function(i)
      if i == 1 then return "Aaron", 0, 1 end
      if i == 2 then return "Zed", 0, group end
    end
    env.UnitInRaid = function(u) if u == "target" then return nil end if u == "mouseover" then return 2 end end
    O.UnitIsConnected = function() return true end
    env.IsSpellInRange = function() return 1 end
    env.IsPlayerSpell = function(id) return id == 21562 or oldKnown and oldKnown(id) end
    env.C_Item.GetItemCount = function() return 0 end
    db.assignmentEnabled = false
    X.subgroupDuties = nil
    local slash = env.SlashCmdList.BUFFRADAR
    slash("subgroup FORTITUDE 1")
    local draft = { [2] = true }
    local options = X.SubgroupDutyOptions()
    local option
    for _, item in ipairs(options) do if item.key == "FORTITUDE" then option = item end end
    assert(option and option.name == "Power Word: Fortitude", "known buff missing or mislabeled in selector")
    local report = X.PreviewSubgroupDuty("FORTITUDE", draft)
    assert(report and #report.members == 2 and not report.incomplete
      and report.members[1].status == "excluded" and report.members[2].status == "eligible"
      and report.members[2].name == "Zed-TestRealm", "draft preview does not follow subgroup selection")
    assert(report.members[2].spell == option.name and report.members[2].fallback
      and report.members[2].fallback:find("outside your responsibility", 1, true), "draft lacks live subgroup fallback reason")
    assert(X.GetSubgroupDuty("FORTITUDE")[1] and not X.GetSubgroupDuty("FORTITUDE")[2],
      "preview changed session duty")
    local stored = X.GetSubgroupDuty("FORTITUDE")
    stored[1] = nil
    assert(X.GetSubgroupDuty("FORTITUDE")[1], "read exposed mutable session duty")
    local none = X.PreviewSubgroupDuty("FORTITUDE", {})
    assert(none.members[1].status == "excluded" and none.members[2].status == "excluded",
      "empty selection acts as unrestricted")
    local all = X.PreviewSubgroupDuty("FORTITUDE", nil)
    assert(all.members[1].status == "eligible" and all.members[2].status == "eligible"
      and all.members[2].fallback and all.members[2].fallback:find("Missing reagent", 1, true),
      "unrestricted draft did not use normal reagent fallback")
    assert(not X.SetSubgroupDuty("FORTITUDE", { [9] = true }) and not X.SetSubgroupDuty("NOT_A_BUFF", draft),
      "invalid subgroup duty was accepted")
    assert(X.SetSubgroupDuty("FORTITUDE", draft), "could not apply valid duty")
    draft[2] = nil
    assert(X.GetSubgroupDuty("FORTITUDE")[2], "setter retained caller's draft table")
    slash("subgroup FORTITUDE 1")
    assert(X.SubgroupAllows("FORTITUDE", "raid1", true) and not X.SubgroupAllows("FORTITUDE", "raid2", true),
      "responsibility did not follow the subgroup")
    assert(not X.SubgroupAllows("FORTITUDE", "raid2", true) and X.SubgroupAllows("FORTITUDE", "target", false),
      "subgroup responsibility escaped into the world")
    assert(not X.SubgroupAllows("FORTITUDE", "mouseover", false), "unselected raid member bypassed filter by alias")
    local nameOffered, _, _, reason = X.GroupOffer("Power Word: Fortitude", "raid1")
    assert(not nameOffered and reason == "subgroup", "broad version ignored group 2")
    group = nil
    local _, _, _, unreadable = X.GroupOffer("Power Word: Fortitude", "raid1")
    assert(unreadable == "subgroup", "unreadable subgroup allowed broad cast")
    local unknown = X.PreviewSubgroupDuty("FORTITUDE", { [1] = true })
    assert(unknown.incomplete and unknown.members[2].status == "unknown" and unknown.members[2].subgroup == 0
      and unknown.members[1].fallback:find("roster information is unavailable", 1, true),
      "unknown subgroup did not explain its fallback")
    env.IsSpellInRange = function() return 0 end
    local out = X.PreviewSubgroupDuty("FORTITUDE", { [1] = true })
    assert(not out.members[1].fallback and not out.members[1].spell and out.members[1].detail == NS.X.L["Out of cast range"],
      "preview showed a cast or fallback for an out-of-range member")
    env.IsSpellInRange = function() return 1 end
    group = 2
    slash("subgroup FORTITUDE ALL")
    local _, _, _, unrestricted = X.GroupOffer("Power Word: Fortitude", "raid1")
    assert(unrestricted ~= "subgroup", "clearing the filter left broad casting blocked")
    slash("subgroup FORTITUDE 1")
    slash("prep personal")
    local prep = X.RaidPreparationSnapshot()
    assert(prep and #prep.members == 2, "preparation required a ready check or dropped a subgroup")
    assert(prep.members[2].name == "Zed-TestRealm" and prep.members[2].guid == env.UnitGUID("raid2")
      and prep.members[2].status == "attention"
      and table.concat(prep.members[2].details, ","):find("Food missing", 1, true),
      "preparation omitted the other subgroup's consumables or lost member identity")
    O.UnitIsConnected = function(unit)
      if unit == "raid2" then error("restricted") end
      return true
    end
    local partial = X.RaidPreparationSnapshot()
    local unknownMember = partial.members[2]
    assert(unknownMember.status == "unknown" and unknownMember.unknown and partial.incomplete
      and table.concat(unknownMember.details, ","):find("Food unavailable", 1, true)
      and not table.concat(unknownMember.details, ","):find("Food missing", 1, true),
      "unreadable connection was treated as known missing buffs or supplies: " ..
      tostring(unknownMember.status) .. "/" .. tostring(unknownMember.unknown) .. "/" ..
      tostring(partial.incomplete) .. "/" .. table.concat(unknownMember.details, ","))
    O.UnitIsConnected = function() return true end
    local oldPhase = env.UnitInPhase
    env.UnitInPhase = function(unit) return unit ~= "raid2" end
    local outOfPhase = X.RaidPreparationSnapshot()
    env.UnitInPhase = oldPhase
    assert(outOfPhase.members[2].status == "unknown" and outOfPhase.incomplete,
      "out-of-phase member was treated as known")
    env.GetNumGroupMembers = function() return 3 end
    assert(X.RaidPreparationSnapshot().incomplete, "preparation did not report incomplete enumeration")
    env.GetNumGroupMembers = function() return 2 end
    local reportGUID = O.UnitGUID
    O.UnitGUID = function(unit) if unit ~= "raid2" then return reportGUID(unit) end end
    local anonymous = X.RaidPreparationSnapshot()
    assert(anonymous.incomplete and #anonymous.members == 1, "unidentified roster slot was expanded under a name or token")
    O.UnitGUID = reportGUID
    local f = env.BuffRadarRaidPreparation
    assert(f and f:IsVisible(), "preparation did not open from the legacy slash mode")
    f.refresh:Click()
    assert(f:IsVisible(), "manual refresh closed preparation")
    env.__combat = true
    fire("PLAYER_REGEN_DISABLED")
    assert(not f:IsVisible() and not X.RaidPreparationSnapshot(), "preparation remained visible or scanned in combat")
    assert(not X.PreviewSubgroupDuty("FORTITUDE", {}) and not X.SetSubgroupDuty("FORTITUDE", {}),
      "subgroup duty was readable as a live preview or writable during combat")
    env.__combat = false
    env.IsInRaid = function() return false end
    fire("GROUP_LEFT")
    assert(not X.GetSubgroupDuty("FORTITUDE") and not X.SetSubgroupDuty("FORTITUDE", {}),
      "subgroup duty survived leaving the raid")
  end)
  env.__combat = false
  env.IsInRaid, env.GetNumGroupMembers, env.GetRaidRosterInfo = oldRaid, oldSize, oldRoster
  O.UnitIsConnected, db.assignmentEnabled = oldConnected, oldAssignments
  env.UnitInRaid = oldUnitInRaid
  env.IsPlayerSpell, env.C_Item.GetItemCount = oldKnown, oldOwned
  X.subgroupDuties = oldDuties
  cleanup()
  fire("PLAYER_REGEN_ENABLED")
  assert(ok, err)
end)
step("Forever session role overrides share the cast rules and retire with the roster", function()
  if not env.__forever then return end
  local cleanup = partyOfTwo("ManualRole")
  local X, O, db = NS.X, env.__over, env.BuffRadarDB
  local oldRule, oldRules, oldMode = env.UnitGroupRolesAssigned, db.buffAssignments, db.assignmentEnabled
  local oldSize, oldCount, oldOverrides = env.GetNumGroupMembers, env.C_Item.GetItemCount, X.assignmentRoleOverrides
  local ok, err = pcall(function()
    local role, size, exists, guid = nil, 3, O.UnitExists, O.UnitGUID
    local aaron = env.UnitGUID("party1")
    env.UnitGroupRolesAssigned = function(unit) if unit == "party1" then return role end end
    env.GetNumGroupMembers = function() return size end
    env.C_Item.GetItemCount = function() return 2 end
    env.IsSpellInRange = function() return 1 end
    X.InvalidateReagents()
    db.buffAssignments = {}
    assert(X.SetAssignmentEnabled(true))
    assert(X.SetAssignment("MAGE", "WORLD", { FORTITUDE = true }))
    assert(X.SetAssignment("MAGE", "TANK", false))
    assert(not X.SetAssignmentRole("party1", "stale-guid", "TANK"), "accepted stale preview identity")
    assert(not X.SetAssignmentRole("player", env.UnitGUID("player"), "TANK"), "accepted self override")
    assert(not X.SetAssignmentRole("target", aaron, "TANK"), "accepted non-roster token")
    assert(not X.SetAssignmentRole("party1", aaron, "NONE"), "accepted invalid role")
    assert(X.SetAssignmentRole("party1", aaron, "TANK"), "could not set role fallback")
    refresh()
    local row = X.AssignmentPreview()[2]
    assert(row.roleOverride == "TANK" and row.roleCanSet and row.rule:find("Manual role: Tank", 1, true)
      and row.rule:find("Tank rule", 1, true) and not shownRows().party1, "manual rule did not apply")
    local before = #chat
    env.SlashCmdList.BUFFRADAR("why Aaron")
    assert(chatSince(before, row.rule), "why omitted manual provenance")
    local offer, item, count, reason, _, detail = X.GroupOffer("Power Word: Fortitude", "party2")
    assert(not offer and reason == "assignment", "group cast ignored a manual restriction")
    local explanation = X.GroupOfferReason(item, count, reason, detail)
    assert(explanation and explanation:find("Aaron-TestRealm", 1, true)
      and explanation:find("Manual role: Tank", 1, true), "manual role omitted from blocker explanation")
    role = "DAMAGER"
    fire("PLAYER_ROLES_ASSIGNED")
    refresh()
    row = X.AssignmentPreview()[2]
    assert(row.roleEditable and not row.roleCanSet and row.rule:find("game role takes precedence", 1, true),
      "readable role did not supersede the override")
    assert(not X.SetAssignmentRole("party1", aaron, "HEALER"), "overrode a readable game role")
    assert(X.SetAssignmentRole("party1", aaron, nil), "could not clear an inactive override")
    role = nil
    env.__combat = true
    assert(not X.SetAssignmentRole("party1", aaron, "TANK"), "changed override during combat")
    env.__combat = false
    assert(X.SetAssignmentRole("party1", aaron, "TANK"))
    size = nil
    O.UnitGUID = function(unit) if unit == "party1" then error("protected GUID") end return guid(unit) end
    fire("GROUP_ROSTER_UPDATE")
    assert(X.assignmentRoleOverrides[aaron] == "TANK", "incomplete roster erased override")
    size = 2
    O.UnitExists = function(unit) return unit == "player" or unit == "party1" end
    O.UnitGUID = function(unit) if unit == "party1" then return "Player-replacement" end return guid(unit) end
    fire("GROUP_ROSTER_UPDATE")
    assert(not X.assignmentRoleOverrides[aaron], "departed member retained an override")
    assert(not X.SetAssignmentRole("party1", aaron, "TANK"), "stale roster token changed replacement")
    assert(X.SetAssignmentRole("party1", "Player-replacement", "TANK"))
    fire("GROUP_LEFT")
    assert(X.assignmentRoleOverrides["Player-replacement"], "alternate group leave wiped active group")
    size = 0
    fire("GROUP_LEFT")
    assert(not X.assignmentRoleOverrides, "group leave retained overrides")
  end)
  env.UnitGroupRolesAssigned, db.buffAssignments, db.assignmentEnabled = oldRule, oldRules, oldMode
  env.__combat = false
  env.GetNumGroupMembers, env.C_Item.GetItemCount, X.assignmentRoleOverrides = oldSize, oldCount, oldOverrides
  X.InvalidateReagents()
  cleanup()
  refresh()
  assert(ok, err)
end)
step("Forever mixed raid preserves blessing ownership and rebinds after a member changes in combat", function()
  if not env.__forever then return end
  local X, O, db = NS.X, env.__over, env.BuffRadarDB
  local fields = { "assignmentEnabled", "buffAssignments", "castMethod", "modClick", "groupCast", "sync",
    "includeSelf", "hidden", "groupOnly", "autoHide", "pauseInCities", "sortMode", "viewMode",
    "roleFilter", "pinned", "buddy", "fastAura" }
  local api = { "IsInRaid", "IsInGroup", "GetNumGroupMembers", "UnitGroupRolesAssigned",
    "GetSpellBookItemName", "GetSpellBookItemInfo", "GetSpellTabInfo", "IsPlayerSpell", "__combat", "__addonSent", "UnitIsGroupLeader" }
  local saved, savedApi, savedUnits = {}, {}, {}
  for _, key in ipairs(fields) do saved[key] = db[key] end
  for _, key in ipairs(api) do savedApi[key] = env[key] end
  for key, value in pairs(O) do savedUnits[key] = value end
  local savedPlan, savedPeers, savedExceptions, savedOverrides, savedFinder =
    X.blessPlan, X.peers, X.blessingExceptions, X.assignmentRoleOverrides, X.search
  local savedBlessing = db.enabled.BLESSINGS
  local oldCount = env.C_Item.GetItemCount
  local ok, err = pcall(function()
    local units = {
      raid1 = { "Localpal", "PALADIN", "HEALER", "Player-1-LocalPal" },
      raid2 = { "Peerpal", "PALADIN", "HEALER", "Player-1-PeerPal" },
      raid3 = { "Alpharaider", "WARRIOR", nil, "Player-1-AlphaRaider" },
      raid4 = { "Bravoraider", "WARRIOR", "DAMAGER", "Player-1-BravoRaider" },
      raid5 = { "Healerraid", "PRIEST", "HEALER", "Player-1-HealerRaid" },
    }
    local function member(unit) return units[unit == "player" and "raid1" or unit] end
    O.UnitExists = function(unit) return member(unit) ~= nil end
    O.UnitIsPlayer = O.UnitExists
    O.UnitName = function(unit) local u = member(unit); return u and u[1] end
    O.UnitFullName = function(unit) return O.UnitName(unit), "TestRealm" end
    O.UnitClass = function(unit) local u = member(unit); if u then return u[2], u[2] end end
    O.UnitGUID = function(unit) local u = member(unit); return u and u[4] end
    O.UnitIsUnit = function(a, b) return a == b or (member(a) ~= nil and member(a) == member(b)) end
    O.IsSpellInRange = function() return 1 end
    O.Aura = function(unit, spell)
      local u = member(unit)
      if u and u[2] ~= "WARRIOR" and spell == "Blessing of Kings" then return { expirationTime = env.GetTime() + 600 } end
    end
    env.IsInRaid, env.IsInGroup = function() return true end, function() return true end
    env.GetNumGroupMembers = function() return 5 end
    env.UnitIsGroupLeader = function(unit) return unit == "player" or unit == "raid1" end
    env.UnitGroupRolesAssigned = function(unit) local u = member(unit); return u and u[3] end
    env.C_Item.GetItemCount = function() return 10 end
    local book = {
      { "Blessing of Kings", 20217 }, { "Blessing of Wisdom", 19742 },
      { "Greater Blessing of Kings", 25898 }, { "Greater Blessing of Wisdom", 25894 },
    }
    env.GetSpellBookItemName = function(i) if book[i] then return book[i][1], "" end end
    env.GetSpellBookItemInfo = function(i) if book[i] then return "SPELL", book[i][2] end end
    env.GetSpellTabInfo = function() return "Holy", nil, 0, #book end
    env.IsPlayerSpell = function(id) return id == 20217 or id == 19742 or id == 25898 or id == 25894 end
    db.buffAssignments, X.blessPlan, X.peers, X.blessingExceptions, X.assignmentRoleOverrides = {}, {}, {}, {}, {}
    db.includeSelf, db.hidden, db.groupOnly, db.autoHide, db.pauseInCities = false, false, false, false, false
    db.castMethod, db.modClick, db.groupCast, db.sync, db.buddy, db.fastAura = "target", true, false, true, false, false
    db.sortMode, db.viewMode, db.roleFilter, db.pinned, X.search = "name", "people", "ALL", "", nil
    db.enabled.BLESSINGS = true
    assert(X.SetAssignmentEnabled(true))
    assert(X.SetAssignment("WARRIOR", "ALL", { BLESS_KINGS = true }))
    assert(X.SetAssignment("WARRIOR", "TANK", { BLESS_WISDOM = true }))
    assert(X.SetAssignmentRole("raid3", units.raid3[4], "TANK"))
    X.InvalidateReagents()
    fire("SPELLS_CHANGED")
    refresh()
    assert(shownRows().raid3["Blessing of Wisdom"] and shownRows().raid4["Blessing of Kings"],
      "mixed roles did not receive separate blessing assignments")

    local function assignWarriors(holder)
      fire("CHAT_MSG_ADDON", "BuffRadar", "BLESS;WARRIOR;KINGS;" .. holder .. "-TestRealm", "RAID", "Peerpal-TestRealm")
      refresh()
    end
    assignWarriors("Peerpal")
    assert(X.blessPlan.WARRIOR and not X.blessPlan.WARRIOR.mine and not shownRows().raid3 and not shownRows().raid4,
      "manual role displaced the other paladin's shared duty")
    assert(not X.SetBlessingException("alpharaider-testrealm", "WISDOM"), "exception took the other paladin's duty")
    assignWarriors("Localpal")
    local rows = shownRows()
    assert(rows.raid3["Blessing of Kings"] and rows.raid4["Blessing of Kings"], "local plan did not supersede manual role")
    assert(rows.raid4.row:GetAttribute("shift-spell1") == "Greater Blessing of Kings", "safe raid blessing was unavailable")
    assert(X.SetBlessingException("alpharaider-testrealm", "WISDOM"))
    refresh()
    rows = shownRows()
    local nextButton, groupButton = env.BuffRadarNextButton, env.BuffRadarGroupButton
    assert(nextButton:GetAttribute("unit") == "raid3" and nextButton:GetAttribute("spell") == "Blessing of Wisdom",
      "individual exception did not arm the queue head")
    assert(groupButton:GetAttribute("spell") == "Blessing of Wisdom"
      and rows.raid4.row:GetAttribute("shift-spell1") == "Blessing of Kings",
      "Greater Blessing could overwrite an individual exception")

    local alphaGUID, bravo = units.raid3[4]
    for _, row in ipairs(X.AssignmentPreview()) do
      if row.identity == units.raid4[4] then bravo = row end
    end
    assert(bravo and bravo.groupActions and bravo.groupActions[1] and bravo.groupActions[1].kind == "exception"
      and bravo.groupActions[1].guid == alphaGUID and bravo.groupDetails[1]:find("Alpharaider", 1, true),
      "the blocker shortcut did not point to the exact exception")
    local exception = assert(X.GetBlessingExceptionForGUID(alphaGUID))
    assert(exception.key == "WISDOM" and exception.canSet and #exception.options == 2,
      "the exception editor did not list learned local blessings")
    assert(not X.SetBlessingExceptionForGUID(alphaGUID, "MIGHT"), "an unlearned blessing was accepted")
    assert(X.SetBlessingExceptionForGUID(alphaGUID, "KINGS"))
    assert(X.GetBlessingExceptionForGUID(alphaGUID).key == "KINGS", "the selected blessing did not replace the exception")
    assert(X.SetBlessingExceptionForGUID(alphaGUID, "DEFAULT") and not X.GetBlessingExceptionForGUID(alphaGUID),
      "clearing an exception did not return the player to their standard assignment")
    assert(X.SetBlessingException("alpharaider-testrealm", "WISDOM"))

    env.__combat = true
    fire("PLAYER_REGEN_DISABLED")
    assert(not X.GetBlessingExceptionForGUID(alphaGUID) and not X.SetBlessingExceptionForGUID(alphaGUID, "DEFAULT"),
      "a combat exception edit was allowed")
    units.raid3 = { "CharlieRaid", "WARRIOR", "DAMAGER", "Player-1-CharlieRaid" }
    fire("GROUP_ROSTER_UPDATE")
    assert(not nextButton:GetAttribute("type") and not groupButton:GetAttribute("type"),
      "raid roster change rearmed a cast during combat")
    env.__combat = false
    fire("PLAYER_REGEN_ENABLED")
    refresh()
    assert(not X.GetBlessingExceptionForGUID(alphaGUID) and not X.SetBlessingExceptionForGUID(alphaGUID, "DEFAULT"),
      "a departed member's exception could still be edited")
    assert(nextButton:GetAttribute("unit") == "raid4" and nextButton:GetAttribute("spell") == "Blessing of Kings"
      and groupButton:GetAttribute("unit") == "raid4" and groupButton:GetAttribute("spell") == "Greater Blessing of Kings",
      "combat exit did not rebind the queue to the remaining eligible raid member")
    assert(not X.GetAssignmentRoleOverride("raid3") and shownRows().raid3["Blessing of Kings"],
      "replacement inherited the departing player's exception or role")
  end)
  for _, key in ipairs(fields) do db[key] = saved[key] end
  for _, key in ipairs(api) do env[key] = savedApi[key] end
  for key in pairs(O) do O[key] = nil end
  for key, value in pairs(savedUnits) do O[key] = value end
  X.blessPlan, X.peers, X.blessingExceptions, X.assignmentRoleOverrides, X.search =
    savedPlan, savedPeers, savedExceptions, savedOverrides, savedFinder
  db.enabled.BLESSINGS, env.C_Item.GetItemCount = savedBlessing, oldCount
  X.InvalidateReagents()
  fire("SPELLS_CHANGED")
  refresh()
  assert(ok, err)
end)
step("Forever outdoor Thorns shares cast eligibility and persists as an opt-in", function()
  if not env.__forever then return end
  local cleanup = partyOfTwo("OutdoorThorns")
  local X, O, db, slash = NS.X, env.__over, env.BuffRadarDB, env.SlashCmdList.BUFFRADAR
  local oldKnown, oldName, oldInfo, oldTab = env.IsPlayerSpell, env.GetSpellBookItemName,
    env.GetSpellBookItemInfo, env.GetSpellTabInfo
  local oldInstance, oldSecret, oldRange = env.IsInInstance, env.issecretvalue, env.IsSpellInRange
  local oldMode, oldAssignments, oldThorns, oldContext = db.assignmentEnabled, db.buffAssignments,
    db.enabled.THORNS, db.buffContext.THORNS
  local saved = db.thornsAnyClassOutdoors
  local ok, err = pcall(function()
    local book = { { "Thorns", 467 }, { "Mark of the Wild", 1126 } }
    env.IsPlayerSpell = function(id) return id == 467 or id == 1126 end
    env.GetSpellBookItemName = function(i) if book[i] then return book[i][1], "Rank 1" end end
    env.GetSpellBookItemInfo = function(i) if book[i] then return "SPELL", book[i][2] end end
    env.GetSpellTabInfo = function() return "General", nil, 0, #book end
    env.IsSpellInRange = function() return 1 end
    local instance, kind = false, "none"
    env.IsInInstance = function() return instance, kind end
    local playerClass = O.UnitClass
    O.UnitClass = function(unit)
      if unit == "player" then return "Druid", "DRUID" end
      return playerClass(unit)
    end
    db.assignmentEnabled, db.buffAssignments, db.enabled.THORNS, db.buffContext.THORNS = false, {}, true, nil
    db.thornsAnyClassOutdoors = false
    X.Core.BuildBuffList()
    X.Refresh()
    local function offered(unit, buff)
      local row = shownRows()[unit]
      return row and row[buff] == true or false
    end
    assert(offered("party2", "Thorns") and not offered("party1", "Thorns"), "opt-in altered default Thorns")
    X.OpenConfig(true)
    local cfg = env.BuffRadarConfig
    cfg.tabBtns.buffs:Click()
    assert(cfg.thornsOutdoors:IsVisible() and not cfg.thornsOutdoors:GetChecked(), "known Thorns checkbox absent or enabled")
    cfg.thornsOutdoors:SetChecked(true)
    cfg.thornsOutdoors:Click()
    assert(offered("party1", "Thorns") and offered("party1", "Mark of the Wild"),
      "checkbox did not widen Thorns or altered another buff")
    local group = X.GroupBuffReport(false, true)
    local checked
    for _, member in ipairs(group.members) do
      if member.unit == "party1" then checked = table.concat(member.missing, ","):find("Thorns", 1, true) end
    end
    assert(checked, "group report did not agree with the outdoor cast queue")
    local before = #chat
    slash("why Aaron")
    assert(chatSince(before, NS.X.L["Thorns: Any Class Outdoors"]), "why omitted the widening rule")
    cfg:Hide()

    instance, kind = true, "party"
    fire("ZONE_CHANGED_NEW_AREA")
    timerTick()
    assert(not offered("party1", "Thorns") and offered("party2", "Thorns"), "dungeon lost stock eligibility")
    for _, area in ipairs({ "raid", "pvp", "arena" }) do
      kind = area
      assert(not X.ThornsAnyClassOutdoors(), "Thorns widened inside " .. area)
    end
    instance, kind = false, "none"
    fire("PLAYER_ENTERING_WORLD")
    timerTick()
    assert(offered("party1", "Thorns"), "outdoor transition did not restore opt-in")
    assert(X.SetAssignmentEnabled(true) and X.SetAssignment("MAGE", "ALL", false))
    X.Refresh()
    assert(not offered("party1", "Thorns"), "outdoor setting overrode explicit None")
    assert(X.SetAssignment("MAGE", "ALL", nil))
    X.Refresh()
    assert(offered("party1", "Thorns"), "Default did not inherit outdoor eligibility")

    local hadUnit, guid, name, full, partyClass = O.UnitExists, O.UnitGUID, O.UnitName, O.UnitFullName, O.UnitClass
    O.UnitExists = function(u) return u == "target" or u == "player" end
    O.UnitIsPlayer = O.UnitExists
    O.UnitGUID = function(u) return guid(u == "target" and "party1" or u) end
    O.UnitName = function(u) return name(u == "target" and "party1" or u) end
    O.UnitFullName = function(u) return full(u == "target" and "party1" or u) end
    O.UnitClass = function(u) return partyClass(u == "target" and "party1" or u) end
    env.IsInGroup = function() return false end
    X.Refresh()
    assert(offered("target", "Thorns"), "Thorns did not widen for a solo target")
    db.enabled.THORNS = false
    X.Refresh()
    assert(not offered("target", "Thorns"), "Thorns ignored the spell toggle")
    db.enabled.THORNS, db.buffContext.THORNS = true, "instance"
    X.Refresh()
    assert(not offered("target", "Thorns"), "Thorns ignored its explicit context")
    db.buffContext.THORNS = nil
    O.UnitExists, O.UnitIsPlayer = hadUnit, hadUnit

    for _, bad in ipairs({ function() return nil end, function() return 0 end,
      function() error("instance API unavailable") end }) do
      env.IsInInstance = bad
      assert(not X.ThornsAnyClassOutdoors(), "unreadable or malformed world state widened Thorns")
    end
    env.IsInInstance = nil
    assert(not X.ThornsAnyClassOutdoors(), "missing instance API widened Thorns")
    env.IsInInstance = function() return false, "none" end
    env.issecretvalue = function(value) return value == false end
    assert(not X.ThornsAnyClassOutdoors(), "restricted world state widened Thorns")
    env.issecretvalue = oldSecret

    slash("profile save OutdoorThornsTest")
    local legacyExport = assert(X.Export())
    assert(not legacyExport:find("thornsAnyClassOutdoors", 1, true), "legacy settings export format changed")
    slash("thornsoutdoors off")
    local offProfile = assert(X.ProfileSnapshot())
    assert(not offProfile:find("thornsAnyClassOutdoors", 1, true), "disabled snapshot broke older profile readers")
    slash("profile load OutdoorThornsTest")
    assert(db.thornsAnyClassOutdoors, "enabled named profile did not round-trip")
    X.ApplyProfile(assert(X.ParseProfile(offProfile)))
    assert(not db.thornsAnyClassOutdoors, "older named profile failed to default outdoor Thorns off")
    assert(X.Import(legacyExport), "legacy settings export no longer imports")
  end)
  if env.BuffRadarConfig then env.BuffRadarConfig:Hide() end
  env.IsPlayerSpell, env.GetSpellBookItemName, env.GetSpellBookItemInfo, env.GetSpellTabInfo =
    oldKnown, oldName, oldInfo, oldTab
  env.IsInInstance, env.issecretvalue = oldInstance, oldSecret
  db.assignmentEnabled, db.buffAssignments, db.enabled.THORNS, db.buffContext.THORNS =
    oldMode, oldAssignments, oldThorns, oldContext
  db.thornsAnyClassOutdoors = saved
  X.DeleteProfile("OutdoorThornsTest")
  cleanup()
  env.IsSpellInRange = oldRange
  X.Core.BuildBuffList()
  refresh()
  assert(ok, err)
end)
step("Forever assignment profiles round-trip full grids, explicit None and old BR2", function()
  if not env.__forever then return end
  local X, db = NS.X, env.BuffRadarDB
  local oldRules, oldMode = db.buffAssignments, db.assignmentEnabled
  local saved = assert(X.ProfileSnapshot())
  local ok, err = pcall(function()
    db.buffAssignments = {}
    X.SetAssignmentEnabled(true)
    for _, class in ipairs(X.BLESSING_CLASS_ORDER) do
      for _, slot in ipairs(X.ASSIGNMENT_SLOTS) do
        assert(X.SetAssignment(class, slot, { ARCANE_INTELLECT = true, DAMPEN_MAGIC = true, FORTITUDE = true,
          DIVINE_SPIRIT = true, FEAR_WARD = true, SHADOW_PROT = true, MARK_OF_THE_WILD = true,
          THORNS = true, EARTH_SHIELD = true, WATER_BREATHING = true, UNENDING_BREATH = true,
          DETECT_INVIS = true, BLESS_SANCTUARY = true }))
      end
    end
    assert(X.SetAssignment("DRUID", "TANK", false))
    local profile = assert(X.ProfileSnapshot(), "full assignment grid exceeded the profile limit")
    local patch = assert(X.ParseProfile(profile))
    assert(patch.assignmentEnabled and patch.buffAssignments.DRUID.TANK == false)
    assert(patch.buffAssignments.WARRIOR.WORLD.BLESS_SANCTUARY)
    assert(not X.ParseProfile(profile .. ";a.DRUID.TANK=0"), "duplicate assignment accepted")
    assert(not X.ParseProfile(profile:gsub("a%.DRUID%.TANK=0", "a.DRUID.TANK=6")), "conflicting magic accepted")
    assert(not X.ParseProfile(profile:gsub("a%.DRUID%.TANK=0", "a.DRUID.TANK=524288")), "unknown bit accepted")
    local legacy = saved:gsub(";buffAssignments=[01]", ""):gsub(";a%.[A-Z]+%.[A-Z]+=%d+", "")
    local older = assert(X.ParseProfile(legacy))
    assert(older.assignmentEnabled == nil and older.buffAssignments == nil)
    X.SetAssignmentEnabled(false)
    X.SetAssignment("DRUID", "TANK", nil)
    X.ApplyProfile(patch)
    assert(X.AssignmentEnabled() and X.GetAssignment("DRUID", "TANK") == false)
  end)
  X.ApplyProfile(assert(X.ParseProfile(saved)))
  db.buffAssignments, db.assignmentEnabled = oldRules, oldMode
  refresh()
  assert(ok, err)
end)
step("Forever blessing exceptions follow group GUIDs and preserve class plans", function()
  if not env.__forever then return end
  local cleanup = partyOfTwo("BlessingException")
  local X, O = NS.X, env.__over
  local db = env.BuffRadarDB
  local oldSize, oldMode, oldRules = env.GetNumGroupMembers, db.assignmentEnabled, db.buffAssignments
  local oldName, oldInfo, oldTab = env.GetSpellBookItemName, env.GetSpellBookItemInfo, env.GetSpellTabInfo
  local oldPlan = X.blessPlan.MAGE
  local displaced
  local ok, err = pcall(function()
    local book = {
      { "Blessing of Kings", 20217 }, { "Blessing of Wisdom", 19742 },
      { "Greater Blessing of Kings", 25898 }, { "Greater Blessing of Wisdom", 25894 },
    }
    env.GetSpellBookItemName = function(i) if book[i] then return book[i][1], "" end end
    env.GetSpellBookItemInfo = function(i) if book[i] then return "SPELL", book[i][2] end end
    env.GetSpellTabInfo = function() return "Holy", nil, 0, #book end
    fire("SPELLS_CHANGED")
    refresh()
    local guid = O.UnitGUID
    O.UnitGUID = function(u)
      if u == "target" or u == "party1" then
        if displaced == "unknown" then error("inaccessible GUID") end
        if displaced then return "Player-New" end
        return guid("party1")
      end
      return guid(u)
    end
    X.blessPlan.MAGE = { key = "KINGS", mine = false }
    assert(not X.SetBlessingException("target", "WISDOM"), "exception stole another paladin's duty")
    X.blessPlan.MAGE.mine = true
    env.SlashCmdList.BUFFRADAR("bless player target WISDOM")
    assert(X.BlessingForClass("MAGE", "party1").name == "Blessing of Wisdom",
      "local blessing exception was not applied")
    local greater, item, count, reason, _, detail = X.GroupOffer("Blessing of Wisdom", "party1")
    assert(not greater and reason == "exception", "exception could publish a conflicting Greater cast")
    local explanation = X.GroupOfferReason(item, count, reason, detail)
    assert(explanation and explanation:find("Greater Blessing of Wisdom", 1, true)
      and explanation:find("Aaron-TestRealm", 1, true)
      and explanation:find("individual blessing exception", 1, true),
      "Greater fallback omitted the member with an individual blessing exception: " .. tostring(explanation))
    env.GetNumGroupMembers = function() return 3 end
    env.IsSpellInRange = function() return 1 end
    db.buffAssignments = {}
    assert(X.SetAssignmentEnabled(true))
    assert(X.SetAssignment("MAGE", "ALL", { BLESS_KINGS = true }))
    local source = X.AssignmentPreview()[2]
    local action
    for _, candidate in pairs(source.groupActions or {}) do
      if candidate.kind == "exception" then action = candidate; break end
    end
    assert(action, "assignment and exception overlap did not expose an exception action")
    local review = assert(X.ReviewBlockerEdit(action, "DEFAULT"))
    local row = review.rows[1]
    assert(not review.incomplete and #review.rows == 1 and row.name == "Aaron-TestRealm"
      and row.gains[1] == "Blessing of Kings" and row.losses[1] == "Blessing of Wisdom",
      "exception review did not show the switch to the group-plan blessing")
    assert(X.BlessingForClass("MAGE", "party1").name == "Blessing of Wisdom",
      "review changed the exception before Apply")
    env.GetNumGroupMembers = function() return 4 end
    local applied, incomplete = X.ApplyBlockerEdit(action, "DEFAULT", review)
    assert(not applied and incomplete and incomplete.incomplete, "unknown roster allowed exception Apply")
    env.GetNumGroupMembers = function() return 3 end
    assert(X.ApplyBlockerEdit(action, "DEFAULT", review), "verified exception could not be applied")
    assert(X.BlessingForClass("MAGE", "party1").name == "Blessing of Kings", "Apply did not clear the exception")
    assert(X.UndoBlockerEdit() and X.GetBlessingExceptionForGUID(action.guid).key == "WISDOM",
      "undo could not recreate a removed exact blessing exception")
    displaced = "unknown"
    X.PruneBlessingExceptions()
    displaced = nil
    assert(X.BlessingForClass("MAGE", "party1").name == "Blessing of Wisdom",
      "temporarily unreadable roster erased the exception")
    displaced = true
    X.PruneBlessingExceptions()
    displaced = nil
    assert(X.BlessingForClass("MAGE", "party1").name == "Blessing of Kings",
      "departed player exception was retained")
  end)
  env.GetSpellBookItemName, env.GetSpellBookItemInfo, env.GetSpellTabInfo = oldName, oldInfo, oldTab
  env.GetNumGroupMembers, db.assignmentEnabled, db.buffAssignments = oldSize, oldMode, oldRules
  X.blessPlan.MAGE = oldPlan
  cleanup()
  X.PruneBlessingExceptions()
  fire("SPELLS_CHANGED")
  refresh()
  assert(ok, err)
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
    if type(fs.text) == "string" and localizedMatch(fs.text,"%d/%d fully buffed") then cover = fs.text end
  end
  env.GetSpellCooldown = nil
  O.Aura = nil
  cleanup()
  assert(cover, "no coverage line rendered")
  -- While Skyfury is on cooldown nobody counts as missing it (it can't be
  -- cast), so the count reads complete -- with the cooldown flagged.
  assert(cover:find("Skyfury 3/3", 1, true), "coverage counts wrong: " .. cover)
  assert(localizedMatch(cover," (~%dm cd)",3), "no cooldown note on the coverage line: " .. cover)
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
    if fs.text == NS.X.L["Paused on a flight path."] or fs.text == "Auf einer Flugroute pausiert." then found = true end
  end
  assert(found, "flight-path pause message not shown")
  env.UnitOnTaxi = nil
  env.SlashCmdList.BUFFRADAR("taxi")
  refresh()
  assert(shownRows().party1, "party not listed after landing")
  cleanup()
end)
step("/br reset and resetpos clear only the current window position", function()
  local X, db = NS.X, env.BuffRadarDB
  local character = assert(X.CharKey())
  local point, byChar, charPoint = db.point, db.pointByChar, db.charPoint
  local width, casts, profiles = db.width, db.castsTotal, db.profiles
  db.charPoint, db.width, db.castsTotal = true, 275, 42
  db.profiles = { Keep = "BR1;width=250" }
  local expected = X.Export()
  local otherPoint = { "TOPLEFT", "BOTTOMLEFT", 200, 600 }
  for _, command in ipairs({ "reset", "resetpos" }) do
    db.point = { "TOPLEFT", "BOTTOMLEFT", 5000, 4000 }
    db.pointByChar = { [character] = db.point, ["Offline-Realm"] = otherPoint }
    local n = #chat
    env.SlashCmdList.BUFFRADAR(command)
    assert(X.GetDB() == db and not db.point and not db.pointByChar[character], command .. " kept the saved spot")
    assert(db.pointByChar["Offline-Realm"] == otherPoint, command .. " reset another character's spot")
    assert(X.Export() == expected and db.castsTotal == 42 and db.profiles.Keep == "BR1;width=250",
      command .. " changed unrelated settings")
    local anchor = env.BuffRadarFrame.points[1]
    assert(anchor[1] == "TOPLEFT" and anchor[3] == "LEFT" and anchor[4] == 40, command .. " did not reanchor the window")
    assert(chatSince(n,NS.X.L[command == "reset" and "Position reset." or "Window position reset to the default spot."]), "no " .. command .. " message")
  end
  db.point, db.pointByChar, db.charPoint = point, byChar, charPoint
  db.width, db.castsTotal, db.profiles = width, casts, profiles
end)
step("/br selftest prints a paste-able block (1.4.0)", function()
  local n = #chat
  env.SlashCmdList.BUFFRADAR("selftest")
  assert(chatSince(n,NS.X.L["BuffRadar self-test -- paste this whole block into a bug report:"]), "no self-test header")
  assert(chatSince(n, "dbVersion 25"), "self-test missing dbVersion")
  assert(chatTemplate(n,"  sync %s · requests %s · role filter %s · profiles %d · idle fade %s"), "self-test missing the 1.5.0 state line")
  assert(chatTemplate(n,"  pill %s · queue tag %s · consumables %s · custom spells %d · buddy split %s · uptime %s"), "self-test missing the 1.6.0 state line")
  assert(chatTemplate(n,"  readypost %s · pinned %s · weapon watch %s · entry reminder %s · throttle %s · covering %d · history %d"), "self-test missing the 1.7.0 state line")
  assert(chatTemplate(n,"  grow up %s · assume range %s · theme %s · find %s · bars %s · markers %s · focus %s · pets %s · aura %s · world %s · drink %s · offenders %d"), "self-test missing the 1.8.0 state line")
  assert(chatTemplate(n,"  two columns %s · death recap %s · wipe report %s · wizard seen %s"), "self-test missing the 1.9.0 state line")
  assert(chatTemplate(n,"  view %s · saved themes %d · row gap %d · icons %s · tooltips %s · buff order %d · click-through %s"), "self-test missing the 1.10.0 state line")
  assert(chatTemplate(n,"  buff %s: %s (spell %s, %s)","SKYFURY") or chatTemplate(n,"  buff %s: %s (spell %s, %s)","FORTITUDE"), "self-test lists no buffs")
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
  assert(gr.isSizing and not gr.scripts.OnUpdate, "right grip did not start event-only sizing")
  gr.scripts.OnMouseUp(gr)
  assert(db.scale == 1.5 and frame.scaleV == 1.5, "right grip scale " .. tostring(db.scale))
  assert(not gr.isSizing and not gr.scripts.OnUpdate, "right grip still sizing after release")
  -- A second release at an extreme cursor clamps the scale.
  gr.scripts.OnMouseDown(gr, "LeftButton")
  env.GetCursorPosition = function() return 9999, 0 end
  gr.scripts.OnMouseUp(gr)
  assert(db.scale == 2, "scale not clamped to 2: " .. tostring(db.scale))
  -- bottom-left: right edge fixed at 250 -> cursor -65 = x1.5
  db.scale = 1
  frame.scaleV = 1
  env.GetCursorPosition = function() return -65, 0 end
  gl.scripts.OnMouseDown(gl, "LeftButton")
  assert(gl.isSizing and not gl.scripts.OnUpdate, "left grip installed a frame update")
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
  if not NS.X.ApiCheck then return end -- optional Extras.lua
  local X = NS.X
  local n = #chat
  env.SlashCmdList.BUFFRADAR("apicheck")
  assert(chatSince(n, "API check"), "no apicheck header")
  assert(chatSince(n, "weapon-enchant candidates"), "no weapon-enchant discovery line")
  n = #chat
  env.SlashCmdList.BUFFRADAR("buffcheck")
  assert((chatSince(n,NS.X.L["Buff check needs C_Spell.GetSpellName or GetSpellInfo; neither exists on this client."]) or chatTemplate(n,"Buff check: all %d spell ids in the buff table exist on this client.") or chatTemplate(n,"Buff check: %d of %d spell ids are unknown here (data may still be loading -- retry in a few seconds):")), "no buffcheck result")
  n = #chat
  env.SlashCmdList.BUFFRADAR("perf")
  assert(chatSince(n,NS.X.L["Perf: CPU timing unavailable (needs debugprofilestop)."]) or chatTemplate(n,"Perf: addon memory %.0f KB") or chatTemplate(n,"Perf: %s · %d samples · CPU average %.2f ms · last %.2f ms · worst %.2f ms"), "no perf line")
  local s = X.Export()
  n = #chat
  env.SlashCmdList.BUFFRADAR("diff " .. s)
  assert(chatTemplate(n,"%s changes nothing."), "identical string reported a change")
  local changed = s:gsub("scale=[%d%.]+", "scale=1.5", 1)
  n = #chat
  env.SlashCmdList.BUFFRADAR("diff " .. changed)
  assert(chatSince(n, string.format(NS.X.L["%s: %d preference changes"],NS.X.L["That string"],1)) and chatSince(n, "scale:"), "diff missed the scale change")
  env.SlashCmdList.BUFFRADAR("profile save dtest")
  n = #chat
  env.SlashCmdList.BUFFRADAR("profile diff dtest")
  assert(chatTemplate(n,"%s changes nothing."), "profile diff of a fresh profile")
  env.SlashCmdList.BUFFRADAR("profile delete dtest")
end)
step("cast counter fits a narrow window instead of being cut off", function()
  local f
  for _, label in ipairs(env.__fontstrings) do
    local right = label.points and label.points[2]
    if right and right[1] == "RIGHT" and right[2] == env.BuffRadarFrame and right[3] == "BOTTOMRIGHT" then
      f = label
      break
    end
  end
  assert(f, "cast counter not anchored to the window footer")
  local prevW, prevSW = f.GetWidth, f.GetStringWidth

  -- Plenty of room: the full line stays.
  f.GetWidth = function() return 400 end
  f.GetStringWidth = function() return 120 end
  NS.X.UpdateCounter()
  -- Checked on the "/" that only the compact form has, so this holds in every
  -- locale: the German pack translates the words but not the separator.
  assert(not f:GetText():find("/", 1, true),
    "a wide window used the compact counter form")

  -- Too narrow for the long form: drop to the compact one. Anchored left and
  -- right with word wrap off, the alternative is a cut-off "39 all-t...".
  f.GetWidth = function() return 40 end
  f.GetStringWidth = function() return 120 end
  NS.X.UpdateCounter()
  local narrow = f:GetText()
  assert(narrow:find("/", 1, true),
    "the long counter line survived a window too narrow for it")

  f.GetWidth, f.GetStringWidth = prevW, prevSW
end)
step("apicheck readability tier tells restricted apart from absent", function()
  if not NS.X.ApiCheck then return end -- optional Extras.lua
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
  local function HasTitleMark(mark)
    for _, label in ipairs(env.__fontstrings) do
      local text = label:GetText()
      if type(text) == "string" and text:find(NS.X.L["|cff33ccffBuff|rRadar"], 1, true) == 1
          and text:find(mark, 1, true) then return true end
    end
  end
  env.__combat = true
  X.ApplyGeometry()
  local pending = HasTitleMark("(update pending)")
  env.__combat = false
  X.ApplyGeometry()
  assert(pending and not HasTitleMark("(update pending)"), "combat geometry title did not mark and clear the pending change")
  X.hid = env.GetTime()
  X.RefreshWindowHeader()
  local hidden = HasTitleMark("(data hidden)")
  X.hid = 0
  X.RefreshWindowHeader()
  assert(hidden and not HasTitleMark("(data hidden)"), "unreadable aura title did not mark and clear the data warning")
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
-- Performance budget (1.15.32, docs/DECISIONS.md): a worst-case scan -- every
-- player missing every buff -- reads at most 8 auras per player, grows
-- linearly from 20 to 40 players, and averages under 5 ms in this fake client.
step("performance budget: worst-case 40-player scan", function()
  local O, X = env.__over, NS.X
  local reads, perPlayer, ms = 0, {}, {}
  local classes = { "WARRIOR", "MAGE", "PRIEST", "DRUID", "SHAMAN", "ROGUE", "HUNTER", "WARLOCK", "PALADIN" }
  local size = 0
  O.UnitExists = function(u)
    if u == "player" then return true end
    local i = tonumber(u:match("^party(%d+)$") or u:match("^raid(%d+)$"))
    return i ~= nil and i <= size
  end
  O.UnitName = function(u) if u == "player" then return "Testshaman" end return "Raider" .. u end
  O.UnitGUID = function(u) return "Player-1-" .. u end
  O.UnitClass = function(u) local i = tonumber(u:match("%d+")) or 0; local c = classes[i % 9 + 1]; return c, c end
  O.UnitIsPlayer = function() return true end
  O.Aura = function() reads = reads + 1 end
  env.IsSpellInRange = function() return 1 end
  for _, n in ipairs({ 5, 20, 40 }) do
    size = n
    env.IsInGroup = function() return size > 1 end
    env.IsInRaid = function() return size > 5 end
    env.GetNumGroupMembers = function() return size end
    pcall(fire, "GROUP_ROSTER_UPDATE"); refresh()
    reads = 0
    local t0 = os.clock()
    for _ = 1, 50 do X.Refresh() end
    ms[n] = (os.clock() - t0) * 1000 / 50
    perPlayer[n] = reads / 50 / n
  end
  O.UnitExists, O.UnitName, O.UnitGUID, O.UnitClass, O.UnitIsPlayer, O.Aura = nil, nil, nil, nil, nil, nil
  env.IsInGroup = function() return false end
  env.IsInRaid = function() return false end
  env.GetNumGroupMembers = nil
  refresh()
  for _, n in ipairs({ 5, 20, 40 }) do
    assert(perPlayer[n] > 0 and perPlayer[n] <= 8,
      string.format("%d players: %.2f aura reads per player (budget 8)", n, perPlayer[n]))
  end
  assert(perPlayer[40] * 40 <= perPlayer[20] * 20 * 2.2,
    string.format("scan work grew faster than linear: %.0f reads at 20, %.0f at 40", perPlayer[20] * 20, perPlayer[40] * 40))
  assert(ms[40] < 5, string.format("40-player scan averaged %.2f ms (budget 5 ms)", ms[40]))
end)
step("hardening regressions: decoder types, ignore import limits, one bad unit", function()
  local X, O, db = NS.X, env.__over, env.BuffRadarDB
  -- DecodeAssignment: happy path, edge and misuse.
  assert(X.DecodeAssignment("0") == false, "zero mask is the explicit 'none' cell")
  assert(type(X.DecodeAssignment("8")) == "table", "valid mask did not decode")
  for _, bad in ipairs({ 8, true, {}, "", "08", "-1", "1e3", " 8" }) do
    assert(X.DecodeAssignment(bad) == nil, "decoder accepted " .. tostring(bad))
  end
  -- IgnoreImport: valid, oversize, escape codes, control characters.
  local before = {}
  for k, v in pairs(db.ignored) do before[k] = v end
  if X.IgnoreImport then -- optional Extras.lua
    local ok = X.IgnoreImport("BRI1;Hardenone;Hardentwo")
    assert(ok and db.ignored.Hardenone and db.ignored.Hardentwo, "valid ignore import failed")
    local okBig, msgBig = X.IgnoreImport("BRI1;" .. string.rep("Floodname;", 2000))
    assert(not okBig and msgBig:find("16 KiB", 1, true) and not db.ignored.Floodname,
      "oversize ignore import was accepted")
    assert(X.IgnoreImport("BRI1;|cffff0000Red|r;Tab\tName;Hardenthree"), "mixed ignore import refused")
    assert(not db.ignored["|cffff0000Red|r"] and not db.ignored["Tab\tName"] and db.ignored.Hardenthree,
      "escape-code or control-character name was stored")
    assert(X.IgnoreImport(("BRI1;" .. string.rep("x", 65))), "overlong name aborted the import")
    assert(not db.ignored[string.rep("x", 65)], "overlong name was stored")
  end
  env.SlashCmdList.BUFFRADAR("ignore |TInterface\\Icons\\X:0|t")
  env.SlashCmdList.BUFFRADAR("ignore Hardenfour")
  assert(not db.ignored["|TInterface\\Icons\\X:0|t"] and db.ignored.Hardenfour,
    "/br ignore stored an escape code or refused a plain name")
  assert(not X.PlanImport("BRPLAN1;A;FORTITUDE;Tab\tHolder"), "plan holder with a control character accepted")
  assert(X.PlanImport("BRPLAN1;A;FORTITUDE;Aaron") and X.PlanImport("BRPLAN1;A;FORTITUDE;none"),
    "a plain plan holder was refused")
  for k in pairs(db.ignored) do if not before[k] then db.ignored[k] = nil end end
  X.Ignore.Rebuild()
  -- One unit whose identity read raises must not hide everyone else.
  local cleanup = partyOfTwo()
  env.IsSpellInRange = function() return 1 end
  refresh()
  local baseline = shownRows()
  local okR, err, rows
  if baseline.party1 and baseline.party2 then
    local realGUID = O.UnitGUID
    O.UnitGUID = function(u)
      if u == "party2" then error("client refused") end
      return realGUID(u)
    end
    okR, err = pcall(X.Refresh)
    rows = shownRows()
  end
  cleanup()
  refresh()
  assert(baseline.party1 and baseline.party2, "both party members should be listed before the fault")
  assert(okR, "a raising UnitGUID aborted the scan: " .. tostring(err))
  assert(rows.party1 and not rows.party2, "the readable player was not listed beside the unreadable one")
end)
-- Robustness fuzz (docs/RISK_MATRIX.md): seeded, so a failure reproduces.
-- Untrusted text (imports, addon messages, whispers, slash arguments),
-- corrupted SavedVariables and failing game APIs must never raise, a
-- rejected import must leave settings untouched, an accepted one must
-- round-trip, and the sanitizer must restore every saved key's type.
step("robustness fuzz: untrusted input, corrupt saves, failing game APIs", function()
  local X, O, db = NS.X, env.__over, env.BuffRadarDB
  local function deep(v, depth)
    if type(v) ~= "table" or depth > 8 then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = deep(x, depth + 1) end
    return t
  end
  local pristine = deep(env.BuffRadarDB, 0)
  local fails, seen, stats = {}, {}, {}
  local function note(where, input, err)
    local k = where .. ":" .. tostring(err):gsub("%[string.-%]:%d+:", "")
    if seen[k] then return end
    seen[k] = true
    fails[#fails + 1] = where .. " <" .. string.format("%q", tostring(input)):sub(1, 80) .. "> " .. tostring(err):sub(1, 160)
  end
  math.randomseed(4242)
  local nasty = { "", " ", ";", ";;;", "=", "==", "\0", "\255\254", "%", "%s%s%s%d", "[", "(", "|c", "|Hitem|h", "|r",
    "\n", "\r\n", string.rep("A", 300), string.rep(";", 300), string.rep("=1;", 2000), "BR1", "BR2", "BR1;", "BR2;",
    "BRPLAN1", "BRPLAN1;", "BR1;scale=nan", "BR1;scale=inf", "BR1;scale=-inf", "BR1;scale=1e309", "BR1;scale=-0",
    "BR1;scale=0x10", "BR1;scale= 1", "BR1;__index=1", "BR1;dbVersion=999", "BR1;enabled.=1", "BR1;.=1",
    "BuffRadar profile: \nBR1", "BuffRadar profile: x\n", "BuffRadar profile: " .. string.rep("n", 500) .. "\nBR1",
    "Привет", "增益", "BRPLAN1;A;;", "BRPLAN1;P;;", "BRPLAN1;A;FORTITUDE;" .. string.rep("x", 300),
    "18446744073709551616", "-1", "1.5", "0", "00", "9" .. string.rep("9", 40) }
  local function mutate(base)
    local t = base
    for _ = 1, math.random(1, 4) do
      local op, i = math.random(6), math.random(0, #t)
      if op == 1 then t = t:sub(1, i)
      elseif op == 2 then t = t:sub(1, i) .. string.char(math.random(0, 255)) .. t:sub(i + 1)
      elseif op == 3 then t = t:sub(1, i) .. t:sub(i + 2)
      elseif op == 4 then t = t:sub(1, i) .. nasty[math.random(#nasty)] .. t:sub(i + 1)
      elseif op == 5 then t = t .. t:sub(i)
      else local j = math.random(0, #t); t = t:sub(1, math.min(i, j)) .. t:sub(math.max(i, j) + 1) end
    end
    return t
  end
  local values = { "0", "1", "2", "-1", "0.01", "0.5", "1.5", "3", "100", "1e9", "-1e9", "1e-9", "nan", "inf",
    "", "x", "name", "role", "need", "distance", "target", "macro", "rank", "raid", "instance", "0,0,0", "1,1,1",
    "2,0,0", "-1,0,0", "0.1,0.2", "ui.auto", "midnight", "nosuch", string.rep("9", 30) }
  local function fieldMutate(base)
    local parts = {}
    for part in (base .. ";"):gmatch("([^;]*);") do parts[#parts + 1] = part end
    for _ = 1, math.random(1, 2) do
      local i = math.random(2, math.max(2, #parts))
      local key = (parts[i] or ""):match("^([^=]+)=")
      if key then parts[i] = key .. "=" .. values[math.random(#values)] end
    end
    return table.concat(parts, ";")
  end
  local saved = X.Export()
  local seeds = { saved, X.PlanExport and X.PlanExport() or "BRPLAN1", "BRPLAN1;A;FORTITUDE;Aaron;P;raid;Future",
    "BuffRadar profile: Fz\n" .. saved, "BR1;scale=1.25;sortMode=name" }
  local parsers = {
    { "Import", X.Import, true }, { "SettingsDiff", X.SettingsDiff }, { "PlanImport", X.PlanImport },
    { "ProfileImport", X.ProfileImport }, { "IgnoreImport", X.IgnoreImport }, { "ParseProfile", X.ParseProfile },
    { "DecodeAssignment", X.DecodeAssignment },
  }
  for _, pz in ipairs(parsers) do
    local name, fn, mutates = pz[1], pz[2], pz[3]
    if fn then
      local inputs = {}
      for _, n in ipairs(nasty) do inputs[#inputs + 1] = n end
      for _ = 1, 400 do inputs[#inputs + 1] = mutate(seeds[math.random(#seeds)]) end
      for _ = 1, 600 do
        local seed = seeds[math.random(#seeds)]
        if name == "ProfileImport" then
          inputs[#inputs + 1] = "BuffRadar profile: Fz\n" .. fieldMutate(saved)
        else
          inputs[#inputs + 1] = fieldMutate(seed)
        end
      end
      for _, input in ipairs(inputs) do
        local before = X.Export()
        local ok, res = pcall(fn, input)
        if ok and res then stats[name] = (stats[name] or 0) + 1 end
        if not ok then note(name, input, res)
        elseif not res and X.Export() ~= before then note(name, input, "rejected input changed settings")
        elseif res and mutates then
          -- Whatever an import accepts must export, re-import and export the same.
          local okE, out = pcall(X.Export)
          if not okE or not out then note(name, input, "accepted import cannot be exported: " .. tostring(out))
          else
            local okI, again = pcall(X.Import, out)
            if not okI or not again then note(name, input, "accepted import does not round-trip: " .. tostring(again))
            elseif X.Export() ~= out then note(name, input, "round-trip changed settings")
            end
          end
          local okR, errR = pcall(refresh)
          if not okR then note(name .. "+refresh", input, errR) end
        end
        if mutates and X.Export() ~= saved then X.Import(saved) end
      end
      for _, v in ipairs({ 1, true, {}, function() end }) do
        local ok, err = pcall(fn, v)
        if not ok then note(name .. "(non-string)", type(v), err) end
      end
    end
  end
  X.Import(saved)
  O.UnitExists = function(u) return u == "player" or (u:match("^party[1-4]$") ~= nil) end
  O.UnitName = function(u) if u == "player" then return "Testshaman" end local i = u:match("^party(%d)$"); if i then return "Peer" .. i end end
  O.UnitGUID = function(u) return "Player-1-" .. u end
  O.UnitIsPlayer = function() return true end
  env.IsInGroup = function() return true end
  env.IsInRaid = function() return false end
  env.GetNumGroupMembers = function() return 5 end
  local oldSync = db.sync
  db.sync, db.requests = true, true
  refresh()
  local kinds = { "CAST", "ASSIGN", "BLESS", "COVER", "BACK", "HELLO", "HERE", "SYNC", "ZZZ", "" }
  local fields = { "FORTITUDE", "KINGS", "WARRIOR", "Peer1", "Peer2", "none", "NONE", "3", "Player-1-party1",
    "0123456789abcdef", "0123456789abcdef01234567", "B", "D", "Q", "P", "1", "999999999999", "" }
  for _ = 1, 3000 do
    local parts = { kinds[math.random(#kinds)] }
    for _ = 1, math.random(0, 6) do
      parts[#parts + 1] = math.random(5) == 1 and nasty[math.random(#nasty)] or fields[math.random(#fields)]
    end
    local msg = table.concat(parts, ";")
    if math.random(4) == 1 then msg = mutate(msg) end
    local sender = ({ "Peer1", "Peer2-TestRealm", "Testshaman", "Stranger", "", "Peer1-" .. string.rep("x", 60) })[math.random(6)]
    local ok, err = pcall(X.OnAddonMsg, "BuffRadar", msg, "PARTY", sender)
    if not ok then note("OnAddonMsg", msg, err) end
    for _, pr in pairs(X.peers or {}) do
      if pr.t ~= -1 then stats.msgAccepted = (stats.msgAccepted or 0) + 1; pr.t = -1 end
    end
    ok, err = pcall(X.OnChatAsk, math.random(2) == 1 and ("buff " .. mutate("me pls")) or mutate("buff"), sender)
    if not ok then note("OnChatAsk", sender, err) end
  end
  for _, v in ipairs({ { nil, "x" }, { 1, "x" }, { "buff", nil }, { "buff", 5 }, { {}, {} } }) do
    local ok, err = pcall(X.OnChatAsk, v[1], v[2])
    if not ok then note("OnChatAsk(types)", tostring(v[1]), err) end
    ok, err = pcall(X.OnAddonMsg, "BuffRadar", v[1], "PARTY", v[2])
    if not ok then note("OnAddonMsg(types)", tostring(v[1]), err) end
  end
  for _ in pairs(X.assign or {}) do stats.assigns = (stats.assigns or 0) + 1 end
  for _ in pairs(X.blessPlan or {}) do stats.bless = (stats.bless or 0) + 1 end
  local nPeers, nCover = 0, 0
  for _ in pairs(X.peers or {}) do nPeers = nPeers + 1 end
  for _ in pairs(X.cover or {}) do nCover = nCover + 1 end
  if nPeers > 4 then note("state", "peers", "peer table grew to " .. nPeers) end
  if nCover > 4 then note("state", "cover", "cover table grew to " .. nCover) end
  db.sync = oldSync
  O.UnitExists, O.UnitName, O.UnitGUID, O.UnitIsPlayer = nil, nil, nil, nil
  env.IsInGroup = function() return false end
  env.GetNumGroupMembers = nil
  X.assign, X.blessPlan, X.cover = {}, {}, {}
  local cmds = {}
  for w in ("nearby coordinate buffassign undo coverage show hide group cities sync requests digest sound soundfor prio view scroll clickthrough counts macro keybind clicks mode clickreg debug lock self pvp autohide rebuff groupcast sort filter strip fade mana selftest compact text charpoint export import profile plan summary discord offenders preset fastaura modclick grouppair pullflash ready prep subgroup fallsound consumables custom assign pin history throttle growup cover rowcolor tooltip rowgap iconsize twocol find findbox bars markers focus pets aura thornsoutdoors worldbuff drink context theme weapon enterflash readypost death wipe buddy bless uptime autoprofile ignore unignore ignores bg taxi watch alertsound minimap stats specscale tagsymbols motion rangewatch assumerange snap scale width buffs toggle announce signore unsignore plates why apicheck buffcheck perf diff practice config forecast smartprio status minimapstatus readiness debuff lite visual feedback"):gmatch("%S+") do
    cmds[#cmds + 1] = w
  end
  local args = { "", "on", "off", "toggle", "list", "add", "remove", "clear", "set", "save", "load", "delete", "export",
    "import", "FORTITUDE", "SHADOWGUARD", "KINGS", "raid", "instance", "always", "1", "0", "-1", "999", "0.5", "nan",
    "Aaron", "Peer1", "%s", "[", "|cffff0000", string.rep("z", 300), "Привет", "1243", "18137", "999999999" }
  local snapshot = X.Export()
  for _ = 1, 1500 do
    local line = cmds[math.random(#cmds)]
    for _ = 1, math.random(0, 3) do line = line .. " " .. args[math.random(#args)] end
    local n0 = #chat
    local ok, err = pcall(env.SlashCmdList.BUFFRADAR, line)
    if not ok then note("slash", line, err) end
    for i = n0 + 1, #chat do
      if chat[i]:find("error:", 1, true) then note("slash", line, chat[i]); break end
    end
  end
  X.Import(snapshot)
  refresh()
  -- Corrupted SavedVariables: hand edits, truncated writes, other tools.
  local function copy(v, depth)
    if type(v) ~= "table" or depth > 6 then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x, depth + 1) end
    return t
  end
  local good = copy(env.BuffRadarDB, 0)
  local keys = {}
  for k in pairs(good) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local junk = { 0, -1, 1e309, -1e309, 0 / 0, 2 ^ 53, 0.5, "", "x", "nan", string.rep("q", 5000), true, false,
    {}, { 1, 2, 3 }, { x = { y = { z = 1 } } }, { [true] = 1, [1.5] = "a" } }
  local function junkValue() local v = junk[math.random(#junk)]; return copy(v, 0) end
  local function junkKey()  -- a key a saved file can hold (never NaN or nil)
    local v = junkValue()
    if v ~= v then return "nan" end
    return v
  end
  local expected = {}
  for k, v in pairs(good) do expected[k] = type(v) end
  for round = 1, 250 do
    local d = copy(good, 0)
    for _ = 1, math.random(1, 6) do
      local k = keys[math.random(#keys)]
      if type(d[k]) == "table" and math.random(2) == 1 then
        local sub = {}
        for sk in pairs(d[k]) do sub[#sub + 1] = sk end
        if #sub > 0 then d[k][sub[math.random(#sub)]] = junkValue() else d[k][junkKey()] = junkValue() end
      elseif math.random(8) == 1 then d[k] = nil
      else d[k] = junkValue() end
    end
    if math.random(5) == 1 then d.dbVersion = junk[math.random(#junk)] end
    if math.random(10) == 1 then d[junkKey()] = junkValue() end
    env.BuffRadarDB = d
    local ok, err = pcall(fire, "ADDON_LOADED", "BuffRadar")
    if not ok then note("savedvars load", round, err)
    else
      local db2 = X.GetDB()
      if type(db2) ~= "table" then note("savedvars load", round, "save is no longer a table")
      else
        for k, ty in pairs(expected) do
          if db2[k] ~= nil and type(db2[k]) ~= ty then
            note("savedvars type", k, "kept " .. type(db2[k]) .. ", expected " .. ty)
          elseif type(db2[k]) == "number" and (db2[k] ~= db2[k] or db2[k] == 1e309 or db2[k] == -1e309) then
            note("savedvars number", k, "kept a non-finite number")
          end
        end
        local okR, errR = pcall(refresh)
        if not okR then note("savedvars refresh", round, errR) end
        local okE, errE = pcall(X.Export)
        if not okE then note("savedvars export", round, errE) end
        local okS, errS = pcall(env.SlashCmdList.BUFFRADAR, "selftest")
        if not okS then note("savedvars selftest", round, errS) end
      end
    end
  end
  env.BuffRadarDB = copy(good, 0)
  fire("ADDON_LOADED", "BuffRadar")
  refresh()
  -- Game API misbehavior during a raid scan: errors, nil, wrong types.
  local chaos = { function() error("api failure") end, function() return nil end, function() return 42 end,
    function() return "" end, function() return {} end, function() return true end }
  local function flaky(real)
    return function(...)
      if math.random(6) == 1 then return chaos[math.random(#chaos)]() end
      return real(...)
    end
  end
  local names = { "UnitExists", "UnitName", "UnitGUID", "UnitClass", "UnitIsPlayer", "UnitLevel", "Aura",
    "UnitIsDeadOrGhost", "UnitIsConnected", "UnitInRange", "UnitGroupRolesAssigned" }
  for round = 1, 200 do
    local size = math.random(1, 40)
    local real = {
      UnitExists = function(u)
        if u == "player" then return true end
        local i = tonumber(u:match("^party(%d+)$") or u:match("^raid(%d+)$"))
        return i ~= nil and i <= size
      end,
      UnitName = function(u) if u == "player" then return "Testshaman" end return "Chaos" .. u end,
      UnitGUID = function(u) return "Player-1-" .. u end,
      UnitClass = function() return "PRIEST", "PRIEST" end,
      UnitIsPlayer = function() return true end,
      UnitLevel = function() return 60 end,
      Aura = function() if math.random(3) == 1 then return { expirationTime = env.GetTime() + 100 } end end,
      UnitIsDeadOrGhost = function() return false end,
      UnitIsConnected = function() return true end,
      UnitInRange = function() return true, true end,
      UnitGroupRolesAssigned = function() return "DAMAGER" end,
    }
    for _, n in ipairs(names) do O[n] = flaky(real[n]) end
    env.IsInGroup = function() return size > 1 end
    env.IsInRaid = function() return size > 5 end
    env.GetNumGroupMembers = function() return size end
    pcall(fire, "GROUP_ROSTER_UPDATE")
    local ok, err = xpcall(X.Refresh, function(e)
      local tb = debug and debug.traceback and debug.traceback("", 2) or ""
      local at = {}
      for loc in tb:gmatch("([%w]+%.lua:%d+)") do at[#at + 1] = loc; if #at == 3 then break end end
      return tostring(e) .. " @ " .. table.concat(at, " < ")
    end)
    if not ok then note("api chaos", round, err) end
  end
  for _, only in ipairs(names) do
    for _, n in ipairs(names) do O[n] = nil end
    local size = 12
    O.UnitExists = function(u)
      if u == "player" then return true end
      local i = tonumber(u:match("^party(%d+)$") or u:match("^raid(%d+)$"))
      return i ~= nil and i <= size
    end
    O.UnitName = function(u) if u == "player" then return "Testshaman" end return "Chaos" .. u end
    O.UnitIsPlayer = function() return true end
    O[only] = function() error("raised by " .. only) end
    env.IsInGroup = function() return true end
    env.IsInRaid = function() return true end
    env.GetNumGroupMembers = function() return size end
    pcall(fire, "GROUP_ROSTER_UPDATE")
    local ok, err = xpcall(X.Refresh, function(e) return tostring(e) .. " @ " .. ((debug and debug.traceback and debug.traceback("", 2) or ""):match("BuffRadar%.lua:%d+") or "?") end)
    if not ok then note("api raises", only, err) end
  end
  for _, n in ipairs(names) do O[n] = nil end
  env.IsInGroup = function() return false end
  env.IsInRaid = function() return false end
  env.GetNumGroupMembers = nil
  refresh()
  local st = {}
  for k, v in pairs(stats) do st[#st + 1] = k .. "=" .. v end
  table.sort(st)
  for _, k in ipairs(names) do O[k] = nil end
  env.BuffRadarDB = deep(pristine, 0)
  fire("ADDON_LOADED", "BuffRadar")
  X.search = ""
  if env.BuffRadarConfig and env.BuffRadarConfig.Hide then env.BuffRadarConfig:Hide() end
  refresh()
  -- Depth floor: the field-level mutations must reach the accepting paths,
  -- or a "clean" run would only prove the frame check works.
  assert((stats.Import or 0) > 0 and (stats.ProfileImport or 0) > 0 and (stats.PlanImport or 0) > 0,
    "fuzz never reached an accepting import path [" .. table.concat(st, " ") .. "]")
  if #fails > 0 then
    error(#fails .. " finding(s) [" .. table.concat(st, " ") .. "]:\n    " .. table.concat(fails, "\n    "))
  end
end)
-- Fresh, clock-controlled clients for the intelligence and readiness features.
do
  local function FeatureClient(saved, roster, setup)
    local client, messages = TestClient()
    local O = client.__over
    local now, due = 100, {}
    O.GetTime = function() return now end
    if client.C_Timer then
      client.C_Timer.After = function(delay, callback) due[#due + 1] = { now + delay, callback } end
    end
    local units = { player = { "Me", "PRIEST" } }
    if roster then units.party1, units.party2 = { "Alia", "PALADIN" }, { "Bren", "PRIEST" } end
    O.UnitExists = function(unit) return units[unit] ~= nil end
    O.UnitIsPlayer = O.UnitExists
    O.UnitGUID = function(unit) return units[unit] and ("Player-1-" .. units[unit][1]) end
    O.UnitName = function(unit) return units[unit] and units[unit][1] end
    O.UnitFullName = function(unit) return O.UnitName(unit), "Realm" end
    O.UnitClass = function(unit) local u = units[unit]; if u then return u[2], u[2] end end
    client.IsInGroup = function() return roster == true end
    client.GetNumGroupMembers = function() return roster and 3 or 0 end
    client.IsSpellInRange = function() return 1 end
    client.UnitGroupRolesAssigned = function(unit)
      return unit == "party1" and "TANK" or unit == "party2" and "HEALER" or "NONE"
    end
    local mana = forever and "Divine Spirit" or "Arcane Intellect"
    local manaKey = forever and "DIVINE_SPIRIT" or "ARCANE_INTELLECT"
    client.IsPlayerSpell = function(id) return id == 1243 or id == (forever and 14752 or 1459) end
    if not forever then client.GetSpellBookItemName = function() end end
    saved.dbVersion, saved.wizardSeen, saved.playSound = saved.dbVersion or 22, true, false
    saved.enabled = saved.enabled or { INNER_FIRE = false, SHADOWGUARD = false }
    client.BuffRadarDB = saved
    if setup then setup(client, units) end
    local X, startup = LoadClient(client)
    local function event(name, ...)
      for i = 1, #client.__frames do
        local frame = client.__frames[i]
        local registered = frame.events and frame.events[name]
        if registered and (type(registered) ~= "table" or registered[1] == (...) or registered[2] == (...)) then
          frame.scripts.OnEvent(frame, name, ...)
        end
      end
    end
    local function advance(dt, tick)
      now = now + dt
      if client.C_Timer then
        for _ = 1, 80 do
          local index
          for i, job in ipairs(due) do
            if job[1] <= now and (not index or job[1] < due[index][1]) then index = i end
          end
          if not index then break end
          table.remove(due, index)[2]()
        end
        if tick and type(client.__ticker) == "function" then client.__ticker() end
      else
        -- With no C_Timer the addon refreshes directly from relevant events;
        -- advancing a mock clock must not synthesize a scan.
      end
    end
    event("ADDON_LOADED", "BuffRadar")
    event("PLAYER_LOGIN")
    return { client = client, X = X, api = client.BuffRadarAPI, db = X.GetDB(), event = event, advance = advance,
      O = O, units = units, mana = mana, manaKey = manaKey, slash = client.SlashCmdList.BUFFRADAR, messages = messages }
  end

  auditTests(step, FeatureClient, TestClient, LoadClient, forever)

  step("Simple Mode keeps one secure next-buff action and Performance Mode pauses diagnostics", function()
    local f = FeatureClient({ dbVersion = 24, enabled = { FORTITUDE = true } }, true)
    local c, X, db = f.client, f.X, f.db
    local main, nextButton = c.BuffRadarFrame, c.BuffRadarNextButton
    assert(main and nextButton and not db.simpleMode and not db.performanceMode, "default mode surface was not ready")
    f.slash("simple on")
    f.advance(0.11)
    assert(db.simpleMode and nextButton.alpha == 1 and nextButton.mouseEnabled and nextButton.height == 26
      and db.enabled.FORTITUDE, "Simple Mode did not preserve settings and expose its one-click action")
    X.OpenConfig(true)
    assert(c.BuffRadarConfig:IsShown() and c.BuffRadarConfig.tabBtns.look:IsShown()
      and not c.BuffRadarConfig.tabBtns.alerts:IsShown() and c.BuffRadarConfig.simpleModeBtn:IsShown(),
      "Simple Mode settings did not hide advanced tabs")
    f.slash("simple off")
    f.advance(0.11)
    assert(not db.simpleMode and nextButton.alpha == 0 and not nextButton.mouseEnabled
      and c.BuffRadarConfig.tabBtns.alerts:IsShown(), "Advanced settings did not return")
    f.slash("performance on")
    assert(db.performanceMode and X.DiagnosticsPaused(), "Performance Mode did not pause diagnostic entry points")
    f.slash("performance off")
    assert(not db.performanceMode and not X.DiagnosticsPaused(), "Performance Mode did not resume diagnostics")
  end)

  step("v23 migration keeps Simple and Performance Mode defaults explicit", function()
    local migrated = FeatureClient({ dbVersion = 23, simpleMode = true, performanceMode = true })
    assert(migrated.db.dbVersion == 25 and migrated.db.simpleMode and migrated.db.performanceMode,
      "v23 mode preferences were not preserved")
    local defaults = FeatureClient({ dbVersion = 23 })
    assert(defaults.db.dbVersion == 25 and defaults.db.simpleMode == false
      and defaults.db.performanceMode == false, "v23 did not receive safe mode defaults")
  end)

  step("v21 upgrades to validated bounded readiness settings; named profiles leave local rules alone", function()
    local f = FeatureClient({ dbVersion = 21, forecastSeconds = 900, smartPriority = "true", readinessAura = -12,
      instancePriority = { [12] = "FORTITUDE", [11] = "NOT_A_BUFF", [0] = "FORTITUDE" },
      debuffRules = { { spellID = 700, unit = "focus", encounterID = 21 },
        { spellID = 700, unit = "focus", encounterID = 99 }, { spellID = 701, unit = "target", encounterID = 0 },
        { spellID = math.huge, unit = "player", encounterID = 0 } } })
    local db, X = f.db, f.X
    assert(db.dbVersion == 25 and db.forecastSeconds == 300 and not db.smartPriority
      and db.readinessAura == 0 and db.statusMinimap, "new scalar defaults or validation were wrong")
    assert(db.instancePriority[12] == "FORTITUDE" and not db.instancePriority[0] and not db.instancePriority[11]
      and #db.debuffRules == 1 and db.debuffRules[1].encounterID == 21, "invalid or duplicate rule survived sanitation")
    for i = 1, 7 do assert(X.Debuffs.SetRule(i, "player", 0)) end
    assert(not X.Debuffs.SetRule(12, "player", 0) and #db.debuffRules == 8, "watch limit was not enforced")
    db.forecastSeconds, db.visualAlerts = 45, true
    assert(X.SaveProfile("ReadinessTest"), "could not save a profile with new controls")
    db.forecastSeconds, db.visualAlerts = 0, false
    db.debuffRules[1].encounterID, db.instancePriority[12] = 45, f.manaKey
    assert(X.LoadProfile("ReadinessTest") and db.forecastSeconds == 45 and db.visualAlerts
      and db.debuffRules[1].encounterID == 45 and db.instancePriority[12] == f.manaKey, "profile lost settings or copied local rules")
    local oldProfile = db.profiles.ReadinessTest
    for _, key in ipairs({ "forecastSeconds", "smartPriority", "statusMinimap", "visualAlerts", "liteMode" }) do
      oldProfile = oldProfile:gsub(";" .. key .. "=%d+", "")
    end
    db.forecastSeconds, db.visualAlerts, db.liteMode = 81, false, true
    X.ApplyProfile(assert(X.ParseProfile(oldProfile)))
    assert(db.forecastSeconds == 81 and not db.visualAlerts and db.liteMode, "an older BR2 profile changed new settings")
  end)

  step("Forecasts use the last covering aura, real pull timers and a local deadline without adding casts", function()
    local f = FeatureClient({ forecastSeconds = 35 }, true)
    local c, X, A = f.client, f.X, f.api
    local expiry, other, unreadable = 148, nil, {}
    c.issecretvalue = function(v) return v == unreadable end
    f.O.Aura = function(unit, spell)
      if spell == "Power Word: Fortitude" then return { expirationTime = expiry } end
      if spell == f.mana then return { expirationTime = 0 } end
      if spell == "Prayer of Fortitude" and other then return { expirationTime = other } end
      return nil
    end
    X.Refresh()
    assert(A.GetSummary().state == "covered" and A.GetSummary().expiring == 0, "an aura outside the lead time warned")
    f.slash("forecast timer 20")
    f.advance(0.11)
    local status = A.GetStatus()
    assert(status.expiring == 3 and status.firstExpiry.spell == "Power Word: Fortitude" and status.firstExpiry.endsAt == 148
      and status.actionable == 0 and not c.BuffRadarNextButton:GetAttribute("type"), "forecast changed the cast queue or missed a deadline")
    local notices = #f.messages
    X.Refresh(); X.Refresh()
    assert(#f.messages == notices, "the same forecast repeatedly alerted")
    f.slash("forecast timer off")
    f.advance(0.11)
    assert(A.GetSummary().expiring == 0, "cancelled local deadline still affected forecasts")
    if X.pullFrame then
      f.event("START_TIMER", 0, 20, 20)
      X.Refresh()
      assert(not X.pull and A.GetSummary().expiring == 0, "a PvP countdown was mistaken for a pull")
      f.event("START_TIMER", 2, unreadable, 20)
      assert(not X.pull, "unreadable countdown fell back to an unrelated total timer length")
      f.event("START_PLAYER_COUNTDOWN", "Player-1-Alia", 20, 20)
      f.advance(0.11)
      assert(X.pull and A.GetSummary().expiring == 3 and A.GetSummary().actionable == 0,
        "native pull needed missing buffs or the flash setting to forecast")
      f.event("STOP_TIMER_OF_TYPE", 1)
      assert(X.pull, "challenge countdown stop cancelled a player countdown")
      f.event("CANCEL_PLAYER_COUNTDOWN", "Player-1-Alia")
      f.advance(0.11)
      assert(not X.pull and A.GetSummary().expiring == 0, "cancelled pull stayed in the forecast")
      f.event("START_TIMER", 2, 20, 20)
      f.event("STOP_TIMER_OF_TYPE", 2)
      assert(not X.pull, "stop-by-type did not cancel the player timer")
      f.event("START_PLAYER_COUNTDOWN", "Player-1-Alia", 20, 20)
      f.event("ENCOUNTER_START", 88)
      assert(not X.pull, "encounter start left the preparation timer active")
    end
    expiry = 120
    if forever then
      other = 0
      X.Refresh()
      assert(A.GetSummary().expiring == 0, "permanent alternate coverage was ignored")
      other = unreadable
      X.Refresh()
      assert(A.GetSummary().expiring == 0 and A.GetSummary().state == "unknown",
        "a hidden alternate timer produced a false renew warning")
      other = nil
    end
    f.db.rebuff = 0
    X.Refresh()
    assert(A.GetSummary().expiring == 3 and A.GetSummary().actionable == 0, "a short known duration was not forecast without a cast")
    expiry = unreadable
    f.db.rebuff = 30
    X.Refresh()
    assert(A.GetSummary().expiring == 0 and A.GetSummary().partial, "protected timer became a known expiry")
  end)

  step("Smart priority promotes eligible role, instance and wipe-recovery buffs without rewriting manual priority", function()
    local f = FeatureClient({ includeSelf = false, wipeReport = false }, true)
    local c, X, A = f.client, f.X, f.api
    f.db.buffPrio = { f.manaKey, "FORTITUDE" }
    X.prioDirty = true
    local function first(unit)
      local row = A.GetUnit(unit)
      return row and row.missing[1]
    end
    X.Refresh()
    assert(first("party1") == f.mana and first("party2") == f.mana, "manual order was not applied")
    f.slash("smartprio on"); X.Refresh()
    assert(first("party1") == "Power Word: Fortitude" and first("party2") == f.mana, "tank/healer roles were not distinguished")
    local instance = 71
    c.GetInstanceInfo = function() return "Dungeon", "party", 1, "Normal", 5, nil, false, instance end
    f.slash("smartprio here " .. f.manaKey); X.Refresh()
    assert(f.db.instancePriority[71] == f.manaKey and first("party1") == f.mana, "configured instance did not promote its buff")
    instance = 72
    X.Refresh()
    assert(first("party1") == "Power Word: Fortitude", "a rule leaked to another instance")
    f.event("ENCOUNTER_END", 123, "Boss", 1, 3, 0)
    X.Refresh()
    assert(first("party2") == "Power Word: Fortitude", "failed encounter did not promote recovery buffs with wipe reports off")
    f.advance(91); X.Refresh()
    assert(first("party2") == f.mana, "wipe priority never expired")
    f.db.enabled.FORTITUDE = false
    X.Refresh()
    assert(first("party1") == f.mana, "smart priority bypassed a disabled buff")
    f.db.enabled.FORTITUDE = true
    c.GetSpellCooldown = function(spell)
      if spell == "Power Word: Fortitude" then return c.GetTime() - 1, 30 end
      return 0, 0
    end
    X.Refresh()
    assert(first("party1") == f.mana, "smart priority offered a buff on cooldown")
    c.GetSpellCooldown = nil
    c.IsSpellInRange = function(spell) return spell == "Power Word: Fortitude" and 0 or 1 end
    X.Refresh()
    assert(first("party1") == f.mana, "smart priority offered an out-of-range buff")
    c.IsSpellInRange = function() return 1 end
    c.UnitGroupRolesAssigned = function(unit) return unit == "party2" and "TANK" or "HEALER" end
    f.event("PLAYER_ROLES_ASSIGNED"); f.advance(0.11)
    assert(first("party1") == f.mana and first("party2") == "Power Word: Fortitude", "role change did not refresh smart order")
    f.slash("smartprio off"); X.Refresh()
    assert(first("party1") == f.mana and f.db.buffPrio[1] == f.manaKey, "turning smart priority off did not restore manual behavior")
  end)

  step("Read-only status exports queue copies, uses contextual symbols and quiet alerts, and invalidates in combat", function()
    local f = FeatureClient({ hidden = true, visualAlerts = true, rebuff = 0 }, true)
    local c, X, A = f.client, f.X, f.api
    local button, events, hasMana, duration = c.BuffRadarMinimapButton, 0, true, 0
    c.WeakAuras = { ScanEvents = function(event)
      assert(event == "BUFFRADAR_STATUS_CHANGED" and A.version == 1, "wrong integration event")
      events = events + 1
    end }
    f.O.Aura = function(unit, spell)
      if spell == "Power Word: Fortitude" then return duration and { expirationTime = duration } or nil end
      if spell == f.mana and (hasMana or unit ~= "party1") then return { expirationTime = 0 } end
      return nil
    end
    X.Refresh()
    assert(A.GetSummary().state == "covered" and button.statusMark:GetText() == "+", "covered minimap state was wrong")
    local revision, notices = A.GetSummary().revision, events
    X.Refresh()
    assert(A.GetSummary().revision == revision and events == notices, "unchanged scan emitted duplicate event")
    hasMana = false
    X.Refresh()
    assert(A.GetSummary().state == "attention" and button.statusMark:GetText() == "!", "ordinary missing buff was not yellow")
    local snapshot = A.GetStatus()
    local row = assert(A.GetUnit("party1"))
    assert(snapshot.targets[1].guid == row.guid and row.missing[1] == f.mana, "API did not return the queued buff")
    local display, bridges = A.GetDisplay(), A.GetImportStrings()
    assert(display.version == 2 and display.color and display.text and display.label
      and bridges.state:find("BUFFRADAR_STATUS_CHANGED", 1, true)
      and bridges.critical:find("GetDisplay", 1, true) and bridges.count:find("actionable", 1, true),
      "display bridge API did not return the versioned state and trigger snippets")
    assert(not bridges.state:find("UnitName", 1, true) and not bridges.state:find("CastSpell", 1, true),
      "display bridge exposed identity or a cast path")
    snapshot.targets[1].missing[1], row.name = "modified", "changed"
    f.units.nameplate1 = f.units.party1
    assert(A.GetUnit("nameplate1").missing[1] == f.mana and A.GetUnit("party1").name == "Alia",
      "integration could mutate live state or could not map a nameplate alias")
    f.units.nameplate1 = { "Different", "PALADIN" }
    assert(not A.GetUnit("nameplate1"), "reassigned token inherited someone else's queue status")
    duration = c.GetTime() + 12
    X.Refresh()
    assert(A.GetSummary().state == "critical" and button.statusMark:GetText() == "!!" and button.pulse:IsShown(),
      "important short buff did not pulse with sound off, even though it was outside the rebuff window")
    f.advance(0.7, true)
    assert(not button.pulse:IsShown(), "short minimap pulse did not clear")
    c.WeakAuras.ScanEvents = function() error("consumer failed") end
    f.db.reduceMotion = true
    duration = 0; X.Refresh(); f.advance(2.1)
    duration = nil; X.Refresh()
    assert(not button.pulse:IsShown(), "Reduced Motion did not suppress visual alerts")
    c.__combat = true
    f.event("PLAYER_REGEN_DISABLED")
    assert(A.GetSummary().reason == "combat" and #A.GetStatus().targets == 0 and not A.GetUnit("party1")
      and not button.statusMark:IsShown(), "stale status survived combat lockdown")
    c.__combat = false
    f.event("PLAYER_REGEN_ENABLED"); f.advance(0.11)
    assert(A.GetSummary().state == "critical", "completed scan did not recover after combat")
    f.slash("minimapstatus off")
    assert(not button.statusMark:IsShown() and A.GetSummary().state == "critical", "minimap preference disabled the API")
  end)

  step("Debuff strip is scoped to spell, unit and encounter; restricted or old focus auras never persist", function()
    local f = FeatureClient({ fastAura = true }, true)
    local c = f.client
    local hidden, reads = {}, 0
    local auras = { player = { spellId = 700, name = "Test Debuff", icon = 14000, applications = 3 },
      focus = { spellId = 701, name = "Boss Debuff", icon = 14001, applications = 5 } }
    f.units.focus = { "Focus", "WARRIOR" }
    c.issecretvalue = function(value) return value == hidden end
    c.C_UnitAuras.GetDebuffDataByIndex = function(unit, i)
      assert(unit == "player" or unit == "focus", "debuff scan read another unit")
      reads = reads + 1
      if i == 1 then return auras[unit] end
      return nil
    end
    f.slash("debuff add 700")
    f.slash("debuff add 701 focus 501")
    assert(not c.BuffRadarDebuffWatch, "disabled debuffs built a frame")
    f.slash("debuff on")
    local strip = assert(c.BuffRadarDebuffWatch)
    assert(strip:IsShown() and tonumber(strip.icons[1].stacks:GetText()) == 3 and not strip.icons[2],
      "encounter rule was displayed outside its encounter or player stacks were wrong")
    f.event("ENCOUNTER_START", 501)
    assert(strip.icons[2].unit == "focus" and tonumber(strip.icons[2].stacks:GetText()) == 5, "scoped focus aura was not displayed")
    c.__combat = true
    f.event("PLAYER_REGEN_DISABLED")
    local scans = c.__zoneCalls
    auras.player.applications = 4
    f.event("UNIT_AURA", "player", { addedAuras = {} })
    f.advance(0.11, true)
    assert(tonumber(strip.icons[1].stacks:GetText()) == 4 and c.__zoneCalls == scans,
      "debuff updates depended on buff refreshes or scanned the combat queue")
    auras.focus = { spellId = hidden, name = "Unreadable", applications = hidden }
    f.event("PLAYER_FOCUS_CHANGED")
    assert(not strip.icons[2]:IsShown(), "changed focus kept the previous aura or treated a secret ID as usable")
    c.C_UnitAuras.GetDebuffDataByIndex = nil
    c.UnitDebuff = function(unit, i)
      reads = reads + 1
      if unit == "focus" and i == 1 then return "Legacy", 14001, 2, nil, nil, nil, nil, nil, nil, 701 end
      return nil
    end
    f.event("PLAYER_FOCUS_CHANGED")
    assert(strip.icons[2]:IsShown() and tonumber(strip.icons[2].stacks:GetText()) == 2, "legacy harmful-aura layout did not work")
    f.event("ENCOUNTER_END", 501, "Boss", 1, 3, 1)
    assert(not strip:IsShown(), "encounter ending did not clear the scoped icon")
    c.__combat = false
    f.event("PLAYER_REGEN_ENABLED")
    f.slash("lite on")
    assert(not strip.events.UNIT_AURA and not strip:IsShown() and #f.db.debuffRules == 2, "Lite mode dropped watch settings or kept a live listener")
    local before = reads
    f.event("UNIT_AURA", "focus"); f.advance(0.11)
    assert(reads == before, "disabled watch still queried auras")
    f.slash("lite off")
    assert(strip.events.UNIT_AURA, "watch did not resume after leaving Lite mode")
    f.slash("debuff remove 701 focus")
    assert(#f.db.debuffRules == 1, "watch could not be removed")
  end)

  step("Adaptive cooldown sweep follows movement and latency without delaying queue events", function()
    local f = FeatureClient({ scanThrottle = true }, true)
    local c, X = f.client, f.X
    local speed, ping, samples = 0, 85, 0
    c.GetUnitSpeed = function() return speed end
    c.GetNetStats = function() samples = samples + 1; return 0, 0, 21, ping end
    local function group() return 30 end
    f.advance(0.11)
    assert(X.Intel.SweepTicks(group) == 3 and samples == 1, "stationary raid did not slow the cooldown sweep")
    speed = 7
    f.event("PLAYER_STARTED_MOVING")
    local before = c.__zoneCalls
    f.advance(0.11)
    assert(c.__zoneCalls == before + 1 and X.Intel.SweepTicks(group) == 1 and samples == 1, "movement event waited for a periodic player scan or resampled latency")
    ping, speed = 300, 0
    f.advance(5.1)
    assert(X.Intel.SweepTicks(group) == 4 and samples == 2, "high latency was not sampled or did not back off the cooldown sweep")
    before = c.__zoneCalls
    f.event("UNIT_AURA", "player"); f.advance(0.11)
    assert(c.__zoneCalls == before + 1, "aura event was delayed by adaptive backoff")
    c.__combat = true
    f.event("PLAYER_REGEN_DISABLED")
    before = c.__zoneCalls
    f.advance(0.41, true)
    assert(c.__zoneCalls == before, "cooldown sweep ran during combat")
    c.__combat = false
    f.event("PLAYER_REGEN_ENABLED"); f.advance(0.11)
    assert(c.__zoneCalls == before + 1 and X.Intel.SweepTicks(group) == 1, "combat exit did not refresh or restore the fast cooldown sweep cadence")
  end)

  step("Personal readiness shows bag-only stones, durability, and the configured consumable aura", function()
    if not forever then return end
    local f = FeatureClient({}, false)
    local c, X = f.client, f.X
    local equipped, healthstone, unknown, auraState = 20, 1, {}, 171
    c.issecretvalue = function(v) return v == unknown end
    c.C_Item.GetItemCount = function(id, bank, uses, reagents, account)
      assert(bank == false and uses == false and reagents == false and account == false, "healthstone lookup included bank or uses")
      return id == 19012 and healthstone or 0
    end
    c.GetInventoryItemDurability = function(slot)
      if slot == 1 then return equipped, 80 end
      if slot == 17 then return unknown, 50 end
      return nil, nil
    end
    c.GetWeaponEnchantInfo = function() return true, 15, 0, 1, false end
    c.GetInventoryItemID = function(_, slot) return slot == 16 and 15 or nil end
    f.O.AuraList = function(unit) if unit == "player" then return {
      { spellId = auraState, name = "Ready Aura", expirationTime = 0 },
    } end end
    c.GetSpellInfo = function(id) if id == 171 then return "Ready Aura" end end
    X.GroupBuffReport = function() error("personal view scanned the group") end
    f.slash("readiness aura 171")
    f.slash("readiness")
    local view = assert(c.BuffRadarRaidPreparation)
    assert(view:IsVisible() and view.tab == "personal" and not view.players:IsShown(), "solo readiness required a roster")
    assert(view.rows[3].heading:GetText():find("Ready Aura", 1, true) and view.rows[3].hint:GetText() == X.L["Present"],
      "the configured consumable aura was not identified")
    assert(view.rows[4].hint:GetText() == X.L["Present"] and view.rows[5].hint:GetText():find(X.L["Repair recommended"], 1, true)
      and view.rows[5].hint:GetText():find(X.L["Some slots unknown"], 1, true), "healthstone or durability status was wrong")
    equipped, healthstone = 0, unknown
    f.event("BAG_UPDATE_DELAYED"); f.event("UPDATE_INVENTORY_DURABILITY"); f.advance(0.11)
    assert(view.rows[4].hint:GetText() == X.L["Unknown"] and view.rows[5].hint:GetText():find("1 broken", 1, true),
      "personal panel did not refresh or treated restricted bag data as zero")
    auraState = unknown
    f.event("UNIT_AURA", "player", { addedAuras = {}, removedAuraInstanceIDs = {} }); f.advance(0.11)
    assert(view.rows[3].hint:GetText() == X.L["Unknown"], "restricted consumable was counted as absent or did not refresh")
    f.slash("lite on")
    assert(not view:IsShown() and not X.RaidPreparationSnapshot(true) and f.db.readinessAura == 171,
      "Lite mode did not close readiness or erased a configured aura")
    f.slash("lite off")
    f.slash("prep personal")
    assert(view:IsVisible(), "personal readiness did not resume")
  end)

  step("Readiness settings expose feedback, reports, and validated watch controls without sending data", function()
    local f = FeatureClient({})
    local c, X = f.client, f.X
    local reads = 0
    c.GetAddOnMemoryUsage = function(addon) assert(addon == "BuffRadar"); return 420 end
    c.UpdateAddOnMemoryUsage = function() reads = reads + 1 end
    f.slash("stats memory")
    local output = table.concat(f.messages, "\n")
    assert(reads == 1 and output:find("420 KB", 1, true) and output:find(X.L["The game does not report memory by feature."], 1, true),
      "memory report did not use addon-only data or implied per-feature estimates")
    f.slash("config")
    local cfg = assert(c.BuffRadarConfig)
    cfg.tabBtns.readiness:Click()
    local r = cfg.readiness
    r.forecast:SetText("66")
    r.forecast.scripts.OnEnterPressed(r.forecast)
    assert(f.db.forecastSeconds == 66, "readiness tab did not save forecast lead")
    r.memory:Click()
    assert(reads == 2, "memory button did not share command behavior")
    r.feedback:Click()
    local export = assert(c.BuffRadarExportFrame)
    assert(export:IsShown() and not export.accept:IsShown()
      and export.editBox:GetText():find("issues/new?template=feature_request.md", 1, true), "feedback did not open a copy-only issue link")
    f.slash("status export")
    assert(export.editBox:GetText():find("BuffRadar/issues", 1, true) == nil, "status did not get its own export")
    assert(#c.__sent == 0, "a read-only tool sent chat")
  end)
end

step("German client uses the translation", function()
  if not env.__german then return end
  local found
  for _, fs in ipairs(env.__fontstrings) do if fs.text == "Kampf" then found = true end end
  assert(found, "combat label not translated ('Kampf' not found)")
end)
step("coordination and wizard share the live settings", function()
  local X, db = NS.X, NS.X.GetDB()
  assert(db, "settings not loaded")
  local savedCtx, savedHistory, savedRaid = db.buffContext, db.history, env.IsInRaid
  db.buffContext = { SPLITTEST = "raid" }
  env.IsInRaid = function() return false end
  local outside = X.ContextOK("SPLITTEST")
  db.buffContext, env.IsInRaid = savedCtx, savedRaid
  assert(outside == false, "Coordination.lua does not read the live settings table")
  db.history = { { t = 0, who = "Splitcheck", spell = "Test" } }
  local text = X.HistoryText()
  db.history = savedHistory
  assert(type(text) == "string" and text:find("Splitcheck", 1, true), "Wizard.lua does not read the live settings table")
end)
step("row hover highlight is a faint theme-coloured wash", function()
  local X, db = NS.X, NS.X.GetDB()
  X.BuildUI()
  local row = env.BuffRadarRow1
  local hl = row and row:GetHighlightTexture()
  assert(hl, "row has no hover highlight")
  assert(hl.file == "Interface\\Buttons\\WHITE8X8" and hl.blend == "ADD", "hover highlight is not the flat wash")
  local function matches()
    local bc, c = X.ThemeBorder(), hl.vcolor
    return c and c[1] == bc[1] and c[2] == bc[2] and c[3] == bc[3] and c[4] == 0.15
  end
  assert(matches(), "hover highlight does not use the theme border colour")
  local saved = db.theme
  db.theme = (saved == "crimson") and "forest" or "crimson"
  X.ApplyAppearance()
  local followed = matches() and hl.vcolor[1] == X.THEMES[db.theme].border[1]
  db.theme = saved
  X.ApplyAppearance()
  assert(followed, "hover highlight did not follow a theme change")
end)
step("window creation is idempotent and keeps bindings on the same frames", function()
  local X = NS.X
  local count = #env.__frames
  X.BuildUI()
  assert(X.WindowReady() and #env.__frames == count, "second window build created more frames")
  assert(X.GetFrame() == env.BuffRadarFrame, "window accessor returned the wrong frame")
  local nextButton = env.BuffRadarNextButton
  assert(X.GetNextButton() == nextButton, "next-cast accessor returned the wrong frame")
  local _, installed = X.NextBindState()
  assert(installed == nextButton.combatDriver, "next-button driver state differs from diagnostics")
end)
step("right-click a row (ignore path)", function()
  local row = env.BuffRadarRow1
  row.entry = { name = "Testshaman", fullName = "Testshaman-TestRealm", missing = { "Skyfury" }, unit = "player" }
  row.scripts.OnClick(row, "RightButton", false)
  row.scripts.PostClick(row, "RightButton", false)
end)
return results, chat
end""")

addon = Path(addon_path).resolve()
root = addon.parent


def read_sources(toc):
    paths = [line.strip().replace("\\", "/") for line in toc.read_text(encoding="utf-8-sig").splitlines()
             if line.strip() and not line.lstrip().startswith("#") and line.strip().lower().endswith(".lua")]
    if len(paths) != len(set(paths)) or addon.name not in paths:
        sys.exit(f"Duplicate entries or missing core file in {toc}")
    return [(path, (root / path).read_text(encoding="utf-8-sig")) for path in paths]


retail_sources = read_sources(root / "BuffRadar.toc")
forever_sources = read_sources(root.parent / "editions" / "forever" / "BuffRadar.toc")
# Keep the older Retail+Extras coverage for optional-API paths (especially
# diagnostics with unreadable values), in addition to the real Retail TOC.
retail_extras = retail_sources + [file for file in forever_sources if file[0] == "Extras.lua"]
setups = [
    ("Retail: declared TOC (no Extras)", True, False, False, False, retail_sources),
    ("Retail + Extras: modern client (C_Timer, UI templates)", True, False, False, False, retail_extras),
    ("Retail + Extras: delayed callbacks, no ticker", False, False, False, False, retail_extras),
    ("Retail + Extras: no UI templates", True, True, False, False, retail_extras),
    ("Forever: modern client", True, False, True, False, forever_sources),
    ("Forever: delayed callbacks, no UI templates", False, True, True, False, forever_sources),
    ("Retail + Extras: German client (Locales/deDE.lua)", True, False, False, True, retail_extras),
]
failed = False
for label, with_timer, no_templates, forever, german, sources in setups:
    results, chat = harness(lua.table_from([lua.table_from(file) for file in sources]),
                            with_timer, no_templates, forever, german, audit_tests)
    bad = 0
    for i in range(1, len(results) + 1):
        name, status = results[i][1], results[i][2]
        if status != "ok":
            bad += 1
            print(f"  {name}: {status}")
    print(f"{label}: {len(results)} steps, {bad} with errors")
    failed = failed or bool(bad)
sys.exit(1 if failed else 0)
