-- Minimal fake WoW client for a smoke run of BuffRadar.lua under Lua 5.1.
-- Not a game emulator: just enough API for the addon to load, handle
-- ADDON_LOADED / PLAYER_LOGIN, build its window and run slash commands, so
-- load-time and command-time runtime errors surface.
-- Usage (from the runner): local env = WOWSTUB(); run chunk with setfenv(chunk, env).

function WOWSTUB(chat, withTimer, noTemplates, forever, german)
  local env = { __noTemplates = noTemplates, __forever = forever, __german = german, __fontstrings = {} }
  -- noTemplates: a client without ButtonFrameTemplate / PanelTemplates, so
  -- frames lack the template's members and the addon's fallback UI is used.
  local templateOnly = { SetTitle = true, Inset = true, CloseButton = true, SetPortraitToAsset = true }
  if withTimer then  -- modern client: C_Timer; callbacks queue until the test runs them
    env.__timers = {}
    env.C_Timer = {
      After = function(_, f) env.__timers[#env.__timers + 1] = f end,
      NewTicker = function(_, f) env.__ticker = f; return {} end,
    }
  end
  local noop = function() end

  local function newObject(kind, name)
    local o = { kind = kind, name = name, scripts = {}, attrs = {}, shown = true, text = "" }
    local methods = {}
    function methods.SetScript(self, ev, fn) self.scripts[ev] = fn end
    function methods.GetScript(self, ev) return self.scripts[ev] end
    function methods.HookScript(self, ev, fn)
      local old = self.scripts[ev]
      self.scripts[ev] = old and function(...) old(...); fn(...) end or fn
    end
    function methods.Show(self) local was = self.shown; self.shown = true
      if not was and self.scripts.OnShow then self.scripts.OnShow(self) end end
    function methods.Hide(self) self.shown = false end
    function methods.SetShown(self, v) if v then self:Show() else self:Hide() end end
    function methods.IsShown(self) return self.shown end
    function methods.IsVisible(self) return self.shown end
    function methods.SetAttribute(self, k, v) self.attrs[k] = v end
    function methods.GetAttribute(self, k) return self.attrs[k] end
    function methods.SetText(self, t) self.text = t end
    function methods.GetText(self) return self.text end
    function methods.SetAlpha(self, a) self.alpha = a end
    function methods.GetAlpha(self) return self.alpha or 1 end
    function methods.IsMouseOver(self) return env.__mouseOver or false end
    function methods.GetStringWidth() return 120 end
    function methods.GetWidth() return 210 end
    function methods.GetHeight() return 120 end
    function methods.GetLeft() return 40 end
    function methods.GetTop() return 600 end
    function methods.GetBottom() return 480 end
    function methods.GetCenter() return 500, 400 end
    function methods.GetEffectiveScale() return 1 end
    function methods.GetPoint() return "TOPLEFT", env.UIParent, "BOTTOMLEFT", 40, 600 end
    function methods.GetChecked(self) return self.checked or false end
    function methods.SetChecked(self, v) self.checked = v end
    function methods.GetValue(self) return self.value or 0 end
    function methods.SetValue(self, v) self.value = v
      if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end end
    function methods.HasFocus() return false end
    function methods.GetName(self) return self.name end
    function methods.SetID(self, id) self.id = id end
    function methods.GetID(self) return self.id or 0 end
    function methods.CreateTexture() return newObject("Texture") end
    function methods.CreateMaskTexture() return newObject("MaskTexture") end
    function methods.CreateFontString()
      local fs = newObject("FontString")
      env.__fontstrings[#env.__fontstrings + 1] = fs
      return fs
    end
    function methods.SetPoint(self, ...)
      self.points = self.points or {}
      self.points[#self.points + 1] = { ... }
    end
    function methods.ClearAllPoints(self) self.points = {} end
    function methods.SetWidth(self, w) self.width = w end
    function methods.SetTextColor(self, r, g, b) self.color = { r, g, b } end
    function methods.SetBackdropBorderColor(self, r, g, b, a) self.borderColor = { r, g, b, a } end
    function methods.RegisterEvent(self, ev) self.events[ev] = true end
    function methods.UnregisterEvent(self, ev) self.events[ev] = nil end
    -- DropdownButton (modern menu) API
    function methods.SetupMenu(self, gen) self.menuGen = gen end
    function methods.GenerateMenu(self)
      if self.menuGen then
        local root = { CreateRadio = function(_, text, isSel, setSel, data) isSel(data); return {} end }
        self.menuGen(self, root)
      end
    end
    o.events = {}
    -- Capitalized names are widget methods (any unknown one is a no-op);
    -- lowercase names are the addon's own data fields, nil until it sets them.
    return setmetatable(o, { __index = function(_, k)
      if noTemplates and templateOnly[k] then return nil end
      if type(k) == "string" and k:match("^%u") then return methods[k] or noop end
      return nil
    end })
  end
  env.__newObject = newObject

  local frames = {}
  function env.CreateFrame(kind, name, parent, template)
    local f = newObject(kind, name)
    f.template = template
    if name then env[name] = f end
    frames[#frames + 1] = f
    return f
  end
  env.__frames = frames
  env.UIParent = newObject("Frame", "UIParent")
  env.Minimap = newObject("Frame", "Minimap")
  env.GameTooltip = newObject("GameTooltip", "GameTooltip")
  env.ColorPickerFrame = newObject("Frame", "ColorPickerFrame")
  env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) chat[#chat + 1] = msg end }
  env.SlashCmdList = {}
  env.UISpecialFrames = {}
  env.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
  env.BackdropTemplateMixin = {}

  -- World / unit API: a level-80 shaman, solo, out of combat, outside cities.
  env.GetLocale = function() return german and "deDE" or "enUS" end
  -- Aura lookups go through env.__over.Aura(unit, name, filter); default: no auras.
  env.C_UnitAuras = {
    GetAuraDataBySpellName = function(unit, name, filter)
      local f = env.__over.Aura
      if f then return f(unit, name, filter) end
      return nil
    end,
    -- Index-based reading, fed by env.__over.AuraList(unit) returning an
    -- array of { name = ..., expirationTime = ... }; default: no auras.
    GetBuffDataByIndex = function(unit, i)
      local f = env.__over.AuraList
      local list = f and f(unit)
      if list then return list[i] end
      return nil
    end,
  }
  env.UnitBuff = function(unit, i)
    local f = env.__over.AuraList
    local list = f and f(unit)
    local a = list and list[i]
    if a then return a.name, "", 0, 0, 0, 0, a.expirationTime end
    return nil
  end
  env.GetBuildInfo = function() return "12.1.5", "99999", "Oct 2026", 120105 end
  env.GetTime = function()
    local f = env.__over and env.__over.GetTime
    if f then return f() end
    return os.clock()
  end
  env.__combat = false
  env.InCombatLockdown = function() return env.__combat end
  -- The addon caches these functions at load, so tests change unit data
  -- through env.__over.<FunctionName> instead of replacing the functions.
  env.__over = {}
  local function over(name, default)
    return function(u, ...)
      local f = env.__over[name]
      if f then return f(u, ...) end
      return default(u, ...)
    end
  end
  env.UnitExists = over("UnitExists", function(u) return u == "player" end)
  env.UnitGUID = over("UnitGUID", function(u) return u == "player" and "Player-1-0001" or nil end)
  env.UnitIsUnit = function(a, b) return a == b end
  env.UnitClass = over("UnitClass", function(u) if u == "player" then return "Shaman", "SHAMAN" end end)
  env.UnitName = over("UnitName", function(u) if u == "player" then return "Testshaman" end end)
  env.UnitFullName = over("UnitFullName", function(u) if u == "player" then return "Testshaman", "TestRealm" end end)
  env.GetNormalizedRealmName = function() return "TestRealm" end
  env.UnitLevel = function() return 80 end
  env.UnitIsPlayer = over("UnitIsPlayer", function(u) return u == "player" end)
  env.UnitIsDeadOrGhost = over("UnitIsDeadOrGhost", function() return false end)
  env.__sent = {}
  env.SendChatMessage = function(msg, chattype) env.__sent[#env.__sent + 1] = { msg = msg, chattype = chattype } end
  env.__addonSent = {}
  env.SendAddonMessage = function(prefix, msg, channel)
    env.__addonSent[#env.__addonSent + 1] = { prefix = prefix, msg = msg, channel = channel }
  end
  env.UnitIsConnected = function() return true end
  env.UnitCanAssist = function() return true end
  env.UnitIsPVP = function() return false end
  env.UnitGroupRolesAssigned = function() return "NONE" end
  env.IsInGroup = function() return false end
  env.IsInRaid = function() return false end
  env.IsInInstance = function() return false, "none" end
  -- Refresh() checks the zone once per run, so zone calls count refreshes.
  env.__zone, env.__zoneCalls = "Elwynn Forest", 0
  env.GetRealZoneText = function() env.__zoneCalls = env.__zoneCalls + 1; return env.__zone end
  env.GetCVarBool = function(k) return k == "nameplateShowFriends" end
  env.GetCVar = function() return "1" end
  env.SetCVar = noop
  env.IsPlayerSpell = function(id) return id == 462854 or id == 52127 or id == 974 end -- Skyfury, Water Shield, Earth Shield
  env.GetSpellBookItemName = function(i, bank) if i == 1 then return "Skyfury", "" end end
  env.GetNumSpellTabs = function() return 1 end
  env.GetSpellTabInfo = function() return "General", nil, 0, 3 end
  env.GetSpellTexture = function() return 136000 end
  env.PlaySound = noop
  env.PlaySoundFile = noop
  env.GetBindingKey = function() return nil end
  env.GetBindingText = function(k) return k end
  env.GetMacroIndexByName = function() return 0 end
  env.GetNumMacros = function() return 3, 0 end
  env.CreateMacro = function() return 4 end
  env.EditMacro = noop
  env.PickupMacro = noop
  env.GetCursorPosition = function() return 0, 0 end
  env.SetPortraitTexture = noop
  env.RegisterStateDriver = noop
  env.SecureHandlerWrapScript = noop
  env.hooksecurefunc = noop
  env.SOUNDKIT = { RAID_WARNING = 8959 }
  -- Options menu (Settings) and the minimap's addon compartment
  env.__settings = {}
  env.Settings = {
    RegisterCanvasLayoutCategory = function(frame, name)
      local c = { frame = frame, name = name, GetID = function() return 1 end }
      env.__settings.canvas = c
      return c
    end,
    RegisterAddOnCategory = function(c) env.__settings.registered = c end,
    OpenToCategory = noop,
    KEYBINDINGS_CATEGORY_ID = 2,
  }
  env.SettingsPanel = newObject("Frame", "SettingsPanel")
  env.HideUIPanel = function(f) f:Hide() end
  env.AddonCompartmentFrame = { RegisterAddon = function(_, info) env.__compartment = info end }
  -- Forever client: interface 16001, a level-60 priest with ranked spells.
  if forever then
    env.GetBuildInfo = function() return "1.60.1", "70450", "Oct 2026", 16001 end
    local book = {  -- name, rank text, spell id
      { "Power Word: Fortitude", "Rank 1", 1243 }, { "Power Word: Fortitude", "Rank 2", 1244 },
      { "Prayer of Fortitude", "Rank 1", 21562 }, { "Inner Fire", "Rank 1", 588 },
      { "Divine Spirit", "Rank 1", 14752 },
    }
    local knownIds = {}
    for _, b in ipairs(book) do knownIds[b[3]] = true end
    env.IsPlayerSpell = function(id) return knownIds[id] or false end
    env.GetSpellBookItemName = function(i) local b = book[i]; if b then return b[1], b[2] end end
    env.GetSpellBookItemInfo = function(i) local b = book[i]; if b then return "SPELL", b[3] end end
    env.GetSpellTabInfo = function() return "Holy", nil, 0, #book end
    env.__over.UnitClass = function(u) if u == "player" then return "Priest", "PRIEST" end end
    env.UnitLevel = function() return 60 end
  end
  if noTemplates then return env end
  -- Bottom tabs (PanelTabButtonTemplate helpers)
  env.PanelTemplates_SetNumTabs = function(f, n) f.numTabs = n end
  env.PanelTemplates_SetTab = function(f, id)
    assert(type(id) == "number" and id >= 1 and id <= (f.numTabs or 0), "PanelTemplates_SetTab: bad tab id " .. tostring(id))
    f.selectedTab = id
  end
  env.PanelTemplates_TabResize = noop
  env.ButtonFrameTemplate_HideButtonBar = noop
  env.ButtonFrameTemplate_HidePortrait = noop
  return env
end
