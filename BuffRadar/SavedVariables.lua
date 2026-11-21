-- BuffRadar - SavedVariables schema, validation and load lifecycle.
-- WoW supplies BuffRadarDB before ADDON_LOADED; never read it at file load.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local X = ns.X
local DB_VERSION = 23
local PROFILE_MAX_BYTES = 4000
local MIN_WIDTH, MAX_WIDTH = 180, 400

local LIMITS = { profiles = 32, ignored = 192, pointByChar = 64, stats = 192, specProfiles = 4,
  specScales = 4, enabled = 256, rebuffPer = 256, coverParts = 16, buffContext = 256, offenders = 50 }

local function Count(map)
  local n = 0
  for _ in pairs(map) do n = n + 1 end
  return n
end

local function KeepKeys(source, limit, valid, compare)
  local keys = {}
  local function Trim()
    table.sort(keys, compare)
    for i = #keys, limit + 1, -1 do keys[i] = nil end
  end
  for key, value in pairs(source) do
    if valid(key, value) then
      keys[#keys + 1] = key
      if #keys >= limit * 2 then Trim() end
    end
  end
  Trim()
  return keys
end

local DEFAULTS = {
  locked = false,
  hidden = false,
  includeSelf = true,  -- your own character gets every buff that suits your class (top of the list)
  avoidPvP = true,     -- don't list PvP-flagged players unless you're flagged too
  autoHide = false,    -- hide the window when nobody needs anything
  rebuff = 30,         -- re-list a player when your buff has less than this many seconds left
  scale = 1,
  width = 210,         -- list window width (corner grip); height always follows the list
  cfgScale = 1,        -- settings window scale
  enabled = {},
  point = nil,
  castMethod = "target", -- "target" (target player, cast, restore target), "id", "macro", "rank"
  clickDebug = false,
  clickReg = "both",   -- which mouse half triggers the cast: "both", "down" or "up"
  bgColor = { 0.04, 0.05, 0.09 },
  bgAlpha = 0.92,
  showTitle = true,
  showBorder = true,
  playSound = true,    -- water droplet when a new name shows up
  showCounter = true,  -- cast counter at the bottom of the window
  castsTotal = 0,      -- all-time casts made through BuffRadar
  groupOnly = false,   -- only show the window while in a party or raid
  pauseInCities = true, -- stop scanning in major cities
  groupCast = false,   -- offer the group version (Prayer of Fortitude etc.) when enough group members need a buff
  groupCastMin = 3,    -- how many group members must need the buff first
  showOutOfRange = false, -- the list only includes targets in cast range
  sortMode = "name",   -- list order: "name" or "role" (tanks and leaders first)
  ignored = {},        -- player names BuffRadar never lists (right-click a row)
  rebuffPer = {},      -- per-buff rebuff thresholds in seconds: buff key -> seconds
  alertSound = "droplet", -- alert sound: "droplet", "system" or "none"
  alertSounds = {},     -- per-alert-kind sound: new/drop/ask/fall -> a sound name (empty = use alertSound)
  buffPrio = {},        -- your buff order: buff keys, first offered first (empty = normal order)
  blessingPreferences = {}, -- class token -> preferred blessing key
  blessingComplement = false, -- offer a different blessing to ungrouped players with another Paladin's copy
  plateRestore = {},    -- original values of supported game CVars changed by /br plates
  assignmentEnabled = false,
  thornsAnyClassOutdoors = false,
  buffAssignments = {},
  clickThrough = false, -- while locked, let clicks pass through the window to the game
  muteInInstance = false, -- no alert sound while in a dungeon, raid or battleground
  showMinimap = true,  -- minimap button (the addon compartment works regardless)
  minimapAngle = 215,  -- minimap button position, degrees
  pauseInBG = false,   -- pause listing in battlegrounds and arenas
  pauseTaxi = false,   -- pause listing while on a flight path (1.5.0)
  watchDrop = true,    -- alert when your single-target buff drops off its holder (1.5.0)
  fallSound = false,   -- alert when a watched group buff falls off mid-fight (1.15.0, #33)
  lowMana = 0,         -- pause offering buffs below this mana % (0 = off) (1.4.0)
  specProfiles = {},   -- per-spec overrides: spec key -> { enabled=, rebuffPer= } (1.4.0)
  compact = false,     -- half-height rows without portraits (1.4.0)
  textScale = 1,       -- list text scale, separate from the window scale (1.4.0)
  charPoint = false,   -- remember the window position per character (1.4.0)
  rememberPanelPositions = false,
  panelPoints = {},
  pointByChar = {},    -- charPoint positions: "Name-Realm" -> point table (1.4.0)
  profiles = {},       -- named settings profiles: name -> settings string (1.5.0)
  sync = true,         -- trade "I just buffed them" notes with other BuffRadar users (1.5.0)
  requests = true,     -- tag players who ask for a buff in chat (1.5.0)
  joinDigest = true,   -- one-line summary when joining a group (1.5.0)
  roleFilter = "ALL",  -- window list filter: "ALL", "TANK", "HEALER" or "DAMAGER" (1.5.0)
  showStrip = true,    -- buff toggle strip + filter chips under the title (1.5.0)
  scalePerSpec = false, -- remember a window scale per specialization (1.12.0)
  specScales = {},     -- spec key -> scale (1.12.0)
  gripSnap = true,     -- Shift while dragging a scale grip snaps to 75/100/125/150% (1.12.0)
  tagSymbols = false,  -- add a symbol to row tags so meaning never rests on color (1.12.0)
  reduceMotion = false, -- no idle fade, no border flash (1.12.0)
  rangeWatch = false,  -- say when a player who needs a buff walks into range (1.12.0)
  assumeRange = false, -- list players the client refuses to place, flagged as estimated
  idleFade = 0,        -- fade the window by this % while the mouse is away (0 = off) (1.5.0)
  pill = false,        -- collapse to a small pill while everyone is buffed (1.6.0)
  queueTag = true,     -- tag the top row "up next" right after a cast lands (1.6.0)
  consumables = false, -- coverage line also tracks flasks, food and runes (1.6.0)
  buddySplit = false,  -- share the list with other BuffRadar users present (1.6.0)
  readyPost = false,   -- post the ready-check summary to group chat (leader/assistant) (1.7.0)
  deathRecap = true,   -- print who was missing buffs when you died (1.9.0)
  wipeReport = false,  -- print a rebuff report after a wipe (1.9.0)
  wizardSeen = false,  -- the setup wizard has been run or dismissed (1.9.0)
  customThemes = {},   -- your saved themes: { name, bg, border } (1.10.0)
  rowGap = 0,          -- extra space between rows, 0-8 (1.10.0)
  iconSize = 0,        -- buff icon size 10-24; 0 = automatic (1.10.0)
  strata = "MEDIUM",   -- legacy saved value; frames keep the client's default layer
  coverParts = {},     -- coverage-line parts switched OFF (absent = on) (1.10.0)
  tooltipLevel = "standard", -- row tooltips: minimal | standard | full (1.10.0)
  viewMode = "people",  -- list view: "people" (one row per player) or "buffs" (one row per buff still needed)
  classColors = true,  -- row names in class colors (1.10.0)
  showRealm = false,   -- show -Realm after row names (1.10.0)
  nameTrim = 0,        -- shorten row names past this many letters, 0 = off (1.10.0)
  rowColors = {},      -- colored edge marks on rows: mine|tank|expiring|buddy (1.10.0)
  pinned = "",         -- full or short name of the player pinned to the top (1.7.0)
  weaponWatch = false, -- remind me when my weapon has no temporary enchant (1.7.0)
  fastAura = false,    -- skip refreshes for aura changes that touch no watched buff (1.14.0, Brief 2)
  modClick = false,    -- Shift-click a row casts the group version of its buff (1.14.0, Brief 3)
  pullFlash = false,   -- flash + countdown line when a pull timer starts (1.14.0, Brief 4)
  enterFlash = true,   -- print a reminder when entering an instance unbuffed (1.7.0)
  scanThrottle = false, -- adapt only the periodic scan to movement, group size and latency
  forecastSeconds = 0,  -- lead time for confirmed expiry notices; 0 = off
  smartPriority = false,
  instancePriority = {}, -- instance ID -> buff key; local rules, not shared profiles
  statusMinimap = true,
  visualAlerts = false,
  liteMode = false,
  debuffWatch = false,
  debuffRules = {},     -- bounded list of { spellID, unit, encounterID }
  matrixView = false, selfStatusStrip = false,
  restockEnabled = false, restockTargets = {}, restockSpendCap = 20000, restockUnitCap = 40,
  readinessAura = 0,    -- optional personal consumable aura spell ID
  history = {},        -- last 50 casts through BuffRadar: { t, spell, who } (1.7.0)
  growUp = false,      -- the list grows upward from a fixed bottom edge (1.8.0)
  hideInCombat = true,  -- no buff targets are available while you are in combat
  twoCol = false,      -- two columns when the list is long (1.9.0)
  theme = "midnight",  -- window color theme (1.8.0)
  autoThemePriority = "", -- an empty setting uses the built-in addon priority
  findBox = false,     -- name finder box on the window (1.8.0)
  durationBars = false, -- thin bar per row: time left on the expiring buff (1.8.0)
  raidMarkers = false, -- show raid target markers on rows (1.8.0)
  rangeText = false,   -- word band ("near") on out-of-range rows (1.8.0)
  focusWatch = false,  -- a line about your focus target's buffs (1.8.0)
  pets = false,        -- list group pets that need buffs (1.8.0)
  auraWatch = false,   -- watch your own aura / aspect (Forever) (1.8.0)
  worldWatch = false,  -- show your active world buffs on the coverage line (Forever) (1.8.0)
  drinkWatch = false,  -- mark healers who are drinking (Forever) (1.8.0)
  buffContext = {},    -- per-buff context: buff key -> "raid" | "instance" (1.8.0)
  offenders = {},      -- group sessions where a player was seen unbuffed: name -> count (1.8.0)
  autoProfile = {},    -- load a named profile per context: raid/dungeon/pvp/world/solo -> name (1.6.0)
  customSpells = {},   -- extra spell IDs to watch, added with /br custom (1.6.0)
  customGroup = {},    -- your own group-cast pairs: spell name -> group spell name, /br grouppair (1.15.0)
  stats = {},          -- all-time casts per spell name: name -> count
}

local KNOWN_KEYS = { point = true, dbVersion = true }
for k in pairs(DEFAULTS) do KNOWN_KEYS[k] = true end
local ENUMS = {
  castMethod = { target = true, id = true, macro = true, rank = true },
  clickReg = { both = true, down = true, up = true },
  sortMode = { name = true, role = true, distance = true, need = true },
  roleFilter = { ALL = true, TANK = true, HEALER = true, DAMAGER = true },
  alertSound = { droplet = true, system = true, none = true },
  strata = { LOW = true, MEDIUM = true, HIGH = true, DIALOG = true },
  tooltipLevel = { minimal = true, standard = true, full = true },
  viewMode = { people = true, buffs = true },
}
local RANGES = { bgAlpha = { 0, 1 }, scale = { 0.5, 2 }, cfgScale = { 0.5, 2 },
                 width = { MIN_WIDTH, MAX_WIDTH }, rebuff = { 0, 3600 }, castsTotal = { 0, 1e9 },
                 groupCastMin = { 2, 40 }, minimapAngle = { 0, 360 },
                 lowMana = { 0, 100 }, textScale = { 0.8, 1.5 }, idleFade = { 0, 90 },
                 rowGap = { 0, 8 }, iconSize = { 0, 24 }, nameTrim = { 0, 24 },
                 forecastSeconds = { 0, 300 }, readinessAura = { 0, 2000000 }, restockSpendCap = { 0, 10000000 }, restockUnitCap = { 0, 200 } }

local function IsNumber(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function PositiveID(v)
  return IsNumber(v) and v > 0 and v <= 2000000 and v == math.floor(v)
end

local MAX_DEBUFF_RULES, MAX_INSTANCE_RULES = 8, 24

local function ValidDebuffRule(id, unit, encounter)
  return PositiveID(id) and (unit == "player" or unit == "focus")
    and (encounter == 0 or PositiveID(encounter))
end

local function PriorityKey(key)
  if type(key) ~= "string" or #key > 32 then return false end
  if key == "BLESSINGS" then return X.classic end
  local blessing = key:match("^BLESS_(%u+)$")
  if X.classic and blessing and X.BLESSINGS[blessing] then return true end
  for _, def in ipairs(X.BUFF_DEFS) do if def.key == key then return true end end
  for _, def in ipairs(X.AURA_DEFS or {}) do if def.key == key then return true end end
  return PositiveID(tonumber(key:match("^CUSTOM(%d+)$")))
end

local function CopyInstancePriority(value)
  local clean = {}
  for _, id in ipairs(KeepKeys(value, MAX_INSTANCE_RULES, function(id, key) return PositiveID(id) and PriorityKey(key) end)) do
    clean[id] = value[id]
  end
  return clean
end

local function CopyDebuffRules(value)
  local clean, seen = {}, { player = {}, focus = {} }
  for _, rule in ipairs(value) do
    if type(rule) == "table" and ValidDebuffRule(rule.spellID, rule.unit, rule.encounterID)
      and not seen[rule.unit][rule.spellID] then
      local id = rule.spellID
      clean[#clean + 1] = { spellID = id, unit = rule.unit, encounterID = rule.encounterID }
      seen[rule.unit][id] = true
      if #clean >= MAX_DEBUFF_RULES then break end
    end
  end
  return clean
end

local function Clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function IsProfileName(name)
  return type(name) == "string" and #name <= 40 and name:match("^[%w_%-]+$") ~= nil
end

local MAX_AUTO_PRIORITY_BYTES = 512

local function OrderedAutoThemeAddons(value)
  local order, seen = {}, {}
  if type(value) == "string" and value ~= "" and #value <= MAX_AUTO_PRIORITY_BYTES then
    local byID = {}
    for _, entry in ipairs(X.AUTO_THEME_ADDONS) do byID[entry[2]] = entry end
    for token in value:gmatch("[^,]+") do
      local id = token:match("^%s*(.-)%s*$"):lower()
      if byID[id] and not seen[id] then
        order[#order + 1], seen[id] = byID[id], true
      end
    end
  end
  for _, entry in ipairs(X.AUTO_THEME_ADDONS) do
    if not seen[entry[2]] then order[#order + 1] = entry end
  end
  return order
end

local function EncodeAutoThemePriority(order)
  local ids, isDefault = {}, true
  for i, entry in ipairs(order) do
    ids[i] = entry[2]
    if entry ~= X.AUTO_THEME_ADDONS[i] then isDefault = false end
  end
  return isDefault and "" or table.concat(ids, ",")
end

local function ProfileScalarValid(key, value)
  if key == "theme" then return #value >= 1 and #value <= 24 end
  if key == "autoThemePriority" then return #value <= MAX_AUTO_PRIORITY_BYTES end
  local choices = ENUMS[key]
  return not choices or choices[value] == true
end

-- Each table field is rebuilt from validated values. Never hand a defaults
-- subtable to the writable DB, or touch live settings while checking an import.
local function PlainString(value, limit)
  return type(value) == "string" and #value > 0 and #value <= limit and not value:find("[%z\1-\31\127|]")
end

local function ValidIgnore(name)
  return PlainString(name, 64) and name:find("%S") ~= nil and not name:find(";", 1, true)
end

local function CopyMap(value, limit, valid)
  local clean = {}
  for _, key in ipairs(KeepKeys(value, limit, valid)) do clean[key] = value[key] end
  return clean
end

local function IsBoolean(v) return type(v) == "boolean" end
local function IsNonnegative(v) return IsNumber(v) and v >= 0 end
local function ValidBuffToken(key) return PlainString(key, 40) and key:match("^[A-Z0-9_]+$") end

local function CopyBooleanMap(value)
  return CopyMap(value, LIMITS.enabled, function(k, v) return ValidBuffToken(k) and IsBoolean(v) end)
end

local function CopyRebuffMap(value)
  local clean = CopyMap(value, LIMITS.rebuffPer, function(k, v) return ValidBuffToken(k) and IsNonnegative(v) end)
  for key, v in pairs(clean) do clean[key] = Clamp(v, 0, 600) end
  return clean
end

local anchors = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
  RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
local function ValidPoint(value)
  return type(value) == "table" and anchors[value[1]] and anchors[value[2]]
    and IsNumber(value[3]) and IsNumber(value[4])
    and math.abs(value[3]) <= 100000 and math.abs(value[4]) <= 100000
end

local function CopyPoint(value)
  if ValidPoint(value) then return { value[1], value[2], value[3], value[4] } end
end

local function CopyColor(value)
  if type(value) == "table" and IsNumber(value[1]) and IsNumber(value[2]) and IsNumber(value[3]) then
    return { Clamp(value[1], 0, 1), Clamp(value[2], 0, 1), Clamp(value[3], 0, 1) }
  end
end

local function SpecKey(key)
  return type(key) == "string" and key:match("^s[1-4]$") ~= nil
end

local function CopySpecProfiles(value)
  local clean = {}
  for _, key in ipairs(KeepKeys(value, LIMITS.specProfiles, function(k, v) return SpecKey(k) and type(v) == "table" end)) do
    local p = value[key]
    clean[key] = {
      enabled = type(p.enabled) == "table" and CopyBooleanMap(p.enabled) or {},
      rebuffPer = type(p.rebuffPer) == "table" and CopyRebuffMap(p.rebuffPer) or {},
    }
  end
  return clean
end

local function CopyPlateRestore(value)
  local clean = {}
  for _, name in ipairs(X.friendlyPlateCVars) do
    if IsBoolean(value[name]) then clean[name] = value[name] end
  end
  for _, name in ipairs({ "nameplateShowAll", X.friendlyPlateNamesCVar }) do
    if IsBoolean(value[name]) then clean[name] = value[name] end
  end
  return clean
end

local function CopyHistory(value)
  local recent, clean = {}, {}
  -- Look back through at most 200 slots even for an oversized/corrupt save.
  for i = #value, math.max(1, #value - 199), -1 do
    local entry = value[i]
    if type(entry) == "table" and PlainString(entry.spell, 128) and PlainString(entry.who, 128) then
      recent[#recent + 1] = { t = IsNumber(entry.t) and math.floor(entry.t) or 0, spell = entry.spell, who = entry.who }
      if #recent >= 50 then break end
    end
  end
  for i = #recent, 1, -1 do clean[#clean + 1] = recent[i] end
  return clean
end

local function CopyCustomThemes(value)
  local clean, seen = {}, {}
  for _, theme in ipairs(value) do
    if type(theme) == "table" and type(theme.name) == "string" and #theme.name >= 1 and #theme.name <= 24 then
      local key = theme.name:lower()
      if not seen[key] then
        local bg, border = CopyColor(theme.bg), CopyColor(theme.border)
        if bg and border then
          seen[key] = true
          clean[#clean + 1] = { name = theme.name, bg = bg, border = border }
          if #clean >= 4 then break end
        end
      end
    end
  end
  return clean
end

local function CopyCustomSpells(value)
  local clean, seen = {}, {}
  for _, id in ipairs(value) do
    if IsNumber(id) and id >= 1 and id <= 2000000 and not seen[id] then
      seen[id] = true
      clean[#clean + 1] = math.floor(id)
      if #clean >= 20 then break end
    end
  end
  return clean
end

local MAX_GROUP_PAIRS = 20
local function ValidGroupPair(single, group)
  local function ValidSpell(name)
    return type(name) == "string" and #name >= 1 and #name <= 60
      and name:match("^%S") and name:match("%S$") and not name:find("[%c;%[%]|]")
  end
  return ValidSpell(single) and ValidSpell(group)
end

local function CopyCustomGroup(value)
  return CopyMap(value, MAX_GROUP_PAIRS, ValidGroupPair)
end

local function CopyBuffPriority(value)
  local clean, seen = {}, {}
  for _, key in ipairs(value) do
    if type(key) == "string" and #key <= 40 and not seen[key] then
      seen[key] = true
      clean[#clean + 1] = key
      if #clean >= 24 then break end
    end
  end
  return clean
end

local TABLE_FIELDS = {
  restockTargets = function(value)
    if getmetatable(value) or (issecretvalue and issecretvalue(value)) then return {} end
    return CopyMap(value,16,function(id,n)
      if issecretvalue and (issecretvalue(id) or issecretvalue(n)) then return false end
      return PositiveID(id) and IsNumber(n) and n>=0 and n<=200 and n==math.floor(n)
    end)
  end,
  bgColor = function(value)
    local fallback = DEFAULTS.bgColor
    return CopyColor(value) or { fallback[1], fallback[2], fallback[3] }
  end,
  alertSounds = function(value)
    local clean = {}
    for kind, choice in pairs(value) do
      if (kind == "new" or kind == "drop" or kind == "ask" or kind == "fall") and ENUMS.alertSound[choice] then
        clean[kind] = choice
      end
    end
    return clean
  end,
  buffPrio = CopyBuffPriority,
  instancePriority = CopyInstancePriority,
  debuffRules = CopyDebuffRules,
  buffAssignments = X.CopyAssignments,
  plateRestore = CopyPlateRestore,
  blessingPreferences = function(value)
    local clean = {}
    for class, key in pairs(value) do
      if type(key) == "string" and X.BLESSING_CLASSES[class] and X.BLESSINGS[key] then clean[class] = key end
    end
    return clean
  end,
  enabled = CopyBooleanMap,
  ignored = function(value)
    return CopyMap(value, LIMITS.ignored, function(name, enabled) return enabled == true and ValidIgnore(name) end)
  end,
  coverParts = function(value)
    return CopyMap(value, LIMITS.coverParts, function(k, v) return PlainString(k, 24) and IsBoolean(v) end)
  end,
  specScales = function(value)
    local clean = CopyMap(value, LIMITS.specScales, function(k, v) return SpecKey(k) and IsNumber(v) end)
    for key, scale in pairs(clean) do clean[key] = Clamp(scale, 0.5, 2) end
    return clean
  end,
  specProfiles = CopySpecProfiles,
  pointByChar = function(value)
    local clean = {}
    for _, name in ipairs(KeepKeys(value, LIMITS.pointByChar, function(k, v) return PlainString(k, 128) and ValidPoint(v) end)) do
      clean[name] = CopyPoint(value[name])
    end
    return clean
  end,
  panelPoints = function(value)
    return { settings = CopyPoint(value.settings), ready = CopyPoint(value.ready), daily = CopyPoint(value.daily), matrix = CopyPoint(value.matrix), selfStatus = CopyPoint(value.selfStatus), supplies = CopyPoint(value.supplies) }
  end,
  profiles = function(value)
    return CopyMap(value, LIMITS.profiles, function(k, v) return IsProfileName(k) and type(v) == "string" and #v <= PROFILE_MAX_BYTES end)
  end,
  autoProfile = function(value)
    local clean = {}
    for _, key in ipairs({ "raid", "dungeon", "pvp", "world", "solo" }) do
      if IsProfileName(value[key]) then clean[key] = value[key] end
    end
    return clean
  end,
  history = CopyHistory,
  customSpells = CopyCustomSpells,
  customGroup = CopyCustomGroup,
  customThemes = CopyCustomThemes,
  rowColors = function(value)
    local clean = {}
    for rule, color in pairs(value) do
      if rule == "mine" or rule == "tank" or rule == "expiring" or rule == "buddy" then
        clean[rule] = CopyColor(color)
      end
    end
    return clean
  end,
  buffContext = function(value)
    return CopyMap(value, LIMITS.buffContext, function(k, v) return ValidBuffToken(k) and (v == "raid" or v == "instance") end)
  end,
  rebuffPer = CopyRebuffMap,
  stats = function(value) return CopyMap(value, LIMITS.stats, function(k, v) return PlainString(k, 128) and IsNonnegative(v) end) end,
  offenders = function(value)
    local function Valid(k, v)
      if not PlainString(k, 128) then return false end
      if IsNonnegative(v) then return true end -- legacy display-name key
      return type(v) == "table" and PlainString(v.name, 128) and IsNonnegative(v.count)
    end
    local function Counts(k) local v = value[k]; return type(v) == "number" and v or v.count end
    local clean = {}
    for _, key in ipairs(KeepKeys(value, LIMITS.offenders, Valid, function(a, b)
      return Counts(a) > Counts(b) or (Counts(a) == Counts(b) and a < b)
    end)) do
      local v = value[key]
      if type(v) == "number" then clean["legacy:" .. key] = { name = key, count = v }
      else clean[key] = { name = v.name, count = v.count } end
    end
    return clean
  end,
}

local function CleanSetting(key, value, default)
  local kind = type(default)
  if kind == "table" then
    return TABLE_FIELDS[key](type(value) == "table" and value or {})
  elseif kind == "number" then
    if not IsNumber(value) then value = default end
    local range = RANGES[key]
    if range then value = Clamp(value, range[1], range[2]) end
    if key == "castsTotal" or key == "forecastSeconds" or key == "readinessAura" or key == "restockSpendCap" or key == "restockUnitCap" then value = math.floor(value) end
  elseif type(value) ~= kind then
    return default
  elseif kind == "string" then
    if ENUMS[key] and not ENUMS[key][value] then return default end
    if key == "theme" and #value > 24 then return default end
    if key == "pinned" and (#value > 128 or value:find("[%z\1-\31\127|]")) then return default end
    if key == "autoThemePriority" and value ~= "" then
      return EncodeAutoThemePriority(OrderedAutoThemeAddons(value))
    end
  end
  return value
end

local function CleanTheme(name, themes)
  local id = name:lower()
  if X.THEMES[id] or id == "custom" then return id end
  for _, theme in ipairs(themes) do
    if theme.name == name then return name end
  end
  return "custom"
end

-- Also used for detached profile candidates, without publishing a new DB.
local function PreparePatch(saved, patch)
  local prepared = {}
  for key, value in pairs(patch) do
    if DEFAULTS[key] ~= nil then prepared[key] = CleanSetting(key, value, DEFAULTS[key]) end
  end
  if prepared.theme then prepared.theme = CleanTheme(prepared.theme, saved.customThemes) end
  return prepared
end

local function Sanitize(saved)
  if type(saved) ~= "table" then saved = {} end
  for key in pairs(saved) do
    if not KNOWN_KEYS[key] then saved[key] = nil end
  end
  for key, default in pairs(DEFAULTS) do
    saved[key] = CleanSetting(key, saved[key], default)
  end
  saved.theme = CleanTheme(saved.theme, saved.customThemes)
  saved.point = CopyPoint(saved.point)
  if not IsNumber(saved.dbVersion) then saved.dbVersion = nil end
  return saved
end

local function Migrate(saved)
  local previous = saved.dbVersion or 0
  saved.showOutOfRange, saved.hideInCombat = false, true
  if not X.classic then
    if saved.castMethod == "id" or saved.castMethod == "rank" then saved.castMethod = "target" end
    saved.groupCast = false
  end
  if previous < 3 then saved.castMethod, saved.clickReg = "target", "both" end
  if previous < 4 then saved.includeSelf = true end
  -- Forever shadow protection became an instance-only default in v10.
  if previous < 10 and X.classic and saved.buffContext.SHADOW_PROT == nil then
    saved.buffContext.SHADOW_PROT = "instance"
  end
  -- v11 added the wizard; genuine existing users should not see the hint.
  if previous >= 5 and previous < 11 then saved.wizardSeen = true end
  -- Versions with no transformation take the defaults supplied by Sanitize.
  if previous < DB_VERSION then saved.dbVersion = DB_VERSION end
end

local function ParseSubgroups(value)
  if value == "ALL" then return nil, true end
  if value == "NONE" then return {}, true end
  if type(value) ~= "string" or #value > 15 or #value == 0 then return nil, false end
  local groups = {}
  for token in (value .. ","):gmatch("(.-),") do
    if not token:match("^[1-8]$") then return nil, false end
    local n = tonumber(token)
    if groups[n] then return nil, false end
    groups[n] = true
  end
  return groups, true
end

local db, preserved, saveState
local listeners = {}

local function DeliberateOverflow(saved)
  local profiles, ignored = 0, 0
  if type(saved.profiles) == "table" then
    for name, body in pairs(saved.profiles) do
      if IsProfileName(name) and type(body) == "string" then
        profiles = profiles + 1
        if #body > PROFILE_MAX_BYTES or profiles > LIMITS.profiles then return true end
      end
    end
  end
  if type(saved.ignored) == "table" then
    for name, value in pairs(saved.ignored) do
      if value == true and ValidIgnore(name) then
        ignored = ignored + 1
        if ignored > LIMITS.ignored then return true end
      end
    end
  end
end

local function Load(migrate)
  local original, candidate = BuffRadarDB, {}
  if type(original) == "table" then
    for key in pairs(KNOWN_KEYS) do candidate[key] = original[key] end
  end
  local future = IsNumber(candidate.dbVersion) and candidate.dbVersion > DB_VERSION
  saveState = future and "future" or (DeliberateOverflow(candidate) and "overflow") or nil
  preserved = saveState == "overflow" and original or nil
  local saved = Sanitize(candidate)
  if future then saved.dbVersion = DB_VERSION end
  if migrate or future then Migrate(saved) end
  if not saveState then BuffRadarDB = saved end
  db = saved
  for _, listener in ipairs(listeners) do listener(db) end
  return saveState
end

local function OnDBLoaded(listener)
  listeners[#listeners + 1] = listener
  if db then listener(db) end
end

X.GetDB = function() return db end
X.OnDBLoaded = OnDBLoaded
X.Settings = {
  Load = Load,
  Sanitize = Sanitize,
  PreparePatch = PreparePatch,
  CopyPoint = CopyPoint,
  ValidGroupPair = ValidGroupPair,
  ParseSubgroups = ParseSubgroups,
  MaxGroupPairs = MAX_GROUP_PAIRS,
  Limits = LIMITS,
  Count = Count,
  PlainString = PlainString,
  ValidIgnore = ValidIgnore,
  CanAdd = function(map, kind, key) return map[key] ~= nil or Count(map) < LIMITS[kind] end,
  SaveState = function() return saveState end,
  RemovePreservedEntry = function(kind, key)
    local collection = preserved and saveState == "overflow" and preserved[kind]
    if type(collection) ~= "table" or collection[key] == nil then return false end
    collection[key] = nil
    return true
  end,
  RecordOffenders = function(observed)
    for guid, name in pairs(observed) do
      local old = db.offenders[guid]
      db.offenders[guid] = { name = name, count = (old and old.count or 0) + 1 }
    end
    db.offenders = TABLE_FIELDS.offenders(db.offenders)
  end,
  Defaults = DEFAULTS,
  MinWidth = MIN_WIDTH,
  MaxWidth = MAX_WIDTH,
  ProfileMaxBytes = PROFILE_MAX_BYTES,
  MaxDebuffRules = MAX_DEBUFF_RULES,
  MaxInstanceRules = MAX_INSTANCE_RULES,
  PositiveID = PositiveID,
  ValidDebuffRule = ValidDebuffRule,
  PriorityKey = PriorityKey,
  IsProfileName = IsProfileName,
  ProfileScalarValid = ProfileScalarValid,
  AutoThemeOrder = OrderedAutoThemeAddons,
  EncodeAutoThemeOrder = EncodeAutoThemePriority,
}
