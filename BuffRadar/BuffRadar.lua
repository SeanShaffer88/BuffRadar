-- BuffRadar - click-to-buff list for World of Warcraft (Retail and Forever)
-- One source for both editions: the buff set and class tables are picked at
-- load from the client's interface version (see CLASSIC_FEATURES below).
-- Copyright (C) 2026 Malikor
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.
--
-- A small window listing nearby friendly players who are missing one of YOUR buffs.
-- Click a name to cast the next buff that player still needs. A player stays on the
-- list until every buff you can cast that suits their class has been applied.
--
-- Notes on how WoW works here:
--  * Casting from an addon requires secure buttons. Secure buttons cannot be created,
--    moved, re-pointed or shown/hidden during combat, so the list FREEZES while you
--    are in combat and catches up the moment combat ends.
--  * Players outside your party/raid are found through friendly nameplates (and your
--    target and mouseover). Turn friendly nameplates on (Shift+V, or /br plates)
--    to see strangers. There is no API that lists nearby players directly.

local ADDON = ...

-- Cached globals: hot paths (refresh, aura reads, row rendering) use these locals
-- instead of a global-table lookup on every call.
local _G = _G
local pairs, ipairs, next, type, select, pcall = pairs, ipairs, next, type, select, pcall
local tostring, tonumber = tostring, tonumber
local math_min, math_max, math_floor, math_ceil, math_huge = math.min, math.max, math.floor, math.ceil, math.huge
local string_format = string.format
local table_sort = table.sort
local wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
local GetTime, InCombatLockdown = GetTime, InCombatLockdown
local UnitExists, UnitGUID, UnitIsUnit, UnitClass, UnitName, UnitLevel =
      UnitExists, UnitGUID, UnitIsUnit, UnitClass, UnitName, UnitLevel
local UnitIsPlayer, UnitIsDeadOrGhost, UnitIsConnected, UnitCanAssist, UnitIsPVP =
      UnitIsPlayer, UnitIsDeadOrGhost, UnitIsConnected, UnitCanAssist, UnitIsPVP
local SOON_DELAY = 0.1  -- event-driven refreshes are coalesced into one per 0.1s

-- Key Bindings menu labels (Bindings.xml defines the binding itself)
BINDING_HEADER_BUFFRADAR = "BuffRadar"
BINDING_CATEGORY_BUFFRADAR = "BuffRadar"
_G["BINDING_NAME_CLICK BuffRadarNextButton:LeftButton"] = "Cast next buff"
_G["BINDING_NAME_CLICK BuffRadarGroupButton:LeftButton"] = "Cast next group buff"
BINDING_NAME_BUFFRADAR_TOGGLE = "Show / hide window"
BINDING_NAME_BUFFRADAR_MUTE = "Mute / unmute sound"
local NEXT_BINDING = "CLICK BuffRadarNextButton:LeftButton"
local MACRO_NAME = "BuffRadar"

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
local MAX_ROWS  = 15
local ROW_H     = 24
local WIDTH     = 210  -- default window width; drag the corner grip to change it
local MIN_WIDTH, MAX_WIDTH = 180, 400
local SCALE_PRESETS = { 0.5, 0.75, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2 }  -- scale dropdowns
local HEADER_H  = 24
local MAX_ICONS = 5
local UPDATE_INTERVAL = 0.4
local FOOTER_H  = 16
local SOUND_FILE = "Interface\\AddOns\\BuffRadar\\Media\\droplet.ogg"

-- Enhancement state (1.4.0), declared up here so every later section -- and
-- Extras.lua -- can reach it. One table on purpose: the main chunk is at
-- Lua 5.1's 200-local limit, so new state lives here, not in new locals.
local X = (select(2, ...) and select(2, ...).X) or {}
do
  local _defs = { session = {}, dead = {}, rezAt = {}, tally = {}, tallyUnits = 0,
            listA = {}, listB = {}, recentlyGone = {}, sessionCasts = 0,
            missPrev = {}, missNow = {}, expiredAt = {}, rowH = 24,
            handled = {}, asked = {}, applyFilter = true,
            failedTargets = {},
            prevHolder = {}, queueAt = 0, consTally = {},
            assign = {}, blessPlan = {}, peers = {}, cover = {}, myCover = false,
            expiryTally = {}, upTotal = 0, upFull = 0,
            search = "", offNow = {}, drinkSet = {}, focusMiss = {}, cfgReg = {} }
  for k, v in pairs(_defs) do if X[k] == nil then X[k] = v end end
end
X.hid = 0  -- last time an aura read came back unreadable (secret) (1.12.0)
if select(2, ...) then select(2, ...).X = X end  -- shared with Data.lua / Extras.lua

-- Buff data lives in Data.lua (loaded first through the .toc); these
-- locals alias the shared tables so the rest of this file reads as it
-- always has.
local CLASSIC_FEATURES = X.classic
local ALL, BUFF_DEFS = X.ALL, X.BUFF_DEFS
local BLESSINGS = X.BLESSINGS
-- (X.MANA / X.MELEE / X.TANKS / X.AURA_DEFS / X.BLESSING_PRIORITY are read
-- through X at their few use sites, to keep main-chunk locals freed.)
---------------------------------------------------------------------------
-- Saved settings
---------------------------------------------------------------------------
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
  scanThrottle = false, -- halve the steady rescan rate in groups over 20 (1.7.0)
  history = {},        -- last 50 casts through BuffRadar: { t, spell, who } (1.7.0)
  growUp = false,      -- the list grows upward from a fixed bottom edge (1.8.0)
  hideInCombat = true,  -- no buff targets are available while you are in combat
  twoCol = false,      -- two columns when the list is long (1.9.0)
  theme = "midnight",  -- window color theme: midnight/crimson/forest/parchment/custom (1.8.0)
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
local db
local PROFILE_MAX_BYTES = 4000

local function IsProfileName(name)
  return type(name) == "string" and #name <= 40 and name:match("^[%w_%-]+$") ~= nil
end

-- SavedVariables sanity check: anything missing, mistyped, out of range or left over
-- from an older layout is repaired or dropped, so a damaged WTF file can't break the addon.
-- (Its helpers live in a do-block to stay within Lua 5.1's 200-local limit for
-- the file; see the config window section.)
local SanitizeDB
do
local KNOWN_KEYS = { point = true, dbVersion = true }
for k in pairs(DEFAULTS) do KNOWN_KEYS[k] = true end
local ENUMS = {
  castMethod = { target = true, id = true, macro = true, rank = true },
  clickReg = { both = true, down = true, up = true },
  sortMode = { name = true, role = true, distance = true, need = true },
  roleFilter = { ALL = true, TANK = true, HEALER = true, DAMAGER = true },
  alertSound = { droplet = true, system = true, none = true },
  theme = { midnight = true, crimson = true, forest = true, parchment = true, custom = true },
  strata = { LOW = true, MEDIUM = true, HIGH = true, DIALOG = true },
  tooltipLevel = { minimal = true, standard = true, full = true },
  viewMode = { people = true, buffs = true },
}
local RANGES = { bgAlpha = { 0, 1 }, scale = { 0.5, 2 }, cfgScale = { 0.5, 2 },
                 width = { MIN_WIDTH, MAX_WIDTH }, rebuff = { 0, 3600 }, castsTotal = { 0, 1e9 },
                 groupCastMin = { 2, 40 }, minimapAngle = { 0, 360 },
                 lowMana = { 0, 100 }, textScale = { 0.8, 1.5 }, idleFade = { 0, 90 },
                 rowGap = { 0, 8 }, iconSize = { 0, 24 }, nameTrim = { 0, 24 } }

local function IsNumber(v)
  return type(v) == "number" and v == v and v ~= math_huge and v ~= -math_huge
end
local function Clamp(v, lo, hi) return math_max(lo, math_min(hi, v)) end

function X.ProfileScalarValid(key, value)
  if key == "theme" then return #value >= 1 and #value <= 24 end
  local choices = ENUMS[key]
  return not choices or choices[value] == true
end

function SanitizeDB(saved)
  if type(saved) ~= "table" then saved = {} end
  for k in pairs(saved) do
    if type(k) ~= "string" or not KNOWN_KEYS[k] then saved[k] = nil end
  end
  for k, def in pairs(DEFAULTS) do
    local v, dt = saved[k], type(def)
    if dt == "table" then
      if type(v) ~= "table" then v = nil end
      if k == "bgColor" then
        if v and IsNumber(v[1]) and IsNumber(v[2]) and IsNumber(v[3]) then
          v = { Clamp(v[1], 0, 1), Clamp(v[2], 0, 1), Clamp(v[3], 0, 1) }
        else
          v = { def[1], def[2], def[3] }
        end
      elseif k == "alertSounds" then
        local clean = {}
        if v then
          for kind, choice in pairs(v) do
            if (kind == "new" or kind == "drop" or kind == "ask" or kind == "fall")
               and (choice == "droplet" or choice == "system" or choice == "none") then
              clean[kind] = choice
            end
          end
        end
        v = clean
      elseif k == "buffPrio" then
        local clean, seenKeys = {}, {}
        if v then
          for _, key in ipairs(v) do
            if type(key) == "string" and #key <= 40 and not seenKeys[key] then
              seenKeys[key] = true
              clean[#clean + 1] = key
              if #clean >= 24 then break end
            end
          end
        end
        v = clean
      elseif k == "blessingPreferences" then
        local clean = {}
        if v then
          for class, key in pairs(v) do
            if type(class) == "string" and type(key) == "string"
               and X.BLESSING_CLASSES[class] and BLESSINGS[key] then clean[class] = key end
          end
        end
        v = clean
      elseif k == "enabled" or k == "ignored" or k == "coverParts" then
        local clean = {}
        if v then
          for key, on in pairs(v) do
            if type(key) == "string" and type(on) == "boolean" then clean[key] = on end
          end
        end
        v = clean
      elseif k == "specScales" then
        local clean = {}
        if v then
          for sk, n in pairs(v) do
            if type(sk) == "string" and IsNumber(n) then clean[sk] = Clamp(n, 0.5, 2) end
          end
        end
        v = clean
      elseif k == "specProfiles" then
        local clean = {}
        if v then
          for sk, prof in pairs(v) do
            if type(sk) == "string" and type(prof) == "table" then
              local p = { enabled = {}, rebuffPer = {} }
              if type(prof.enabled) == "table" then
                for key, on in pairs(prof.enabled) do
                  if type(key) == "string" and type(on) == "boolean" then p.enabled[key] = on end
                end
              end
              if type(prof.rebuffPer) == "table" then
                for key, n in pairs(prof.rebuffPer) do
                  if type(key) == "string" and IsNumber(n) and n >= 0 then p.rebuffPer[key] = n end
                end
              end
              clean[sk] = p
            end
          end
        end
        v = clean
      elseif k == "pointByChar" then
        local clean = {}
        if v then
          for name, p in pairs(v) do
            if type(name) == "string" and type(p) == "table" and type(p[1]) == "string"
               and type(p[2]) == "string" and IsNumber(p[3]) and IsNumber(p[4]) then
              clean[name] = { p[1], p[2], p[3], p[4] }
            end
          end
        end
        v = clean
      elseif k == "profiles" then
        local clean = {}
        if v then
          for name, s in pairs(v) do
            if IsProfileName(name) and type(s) == "string" and #s <= PROFILE_MAX_BYTES then
              clean[name] = s
            end
          end
        end
        v = clean
      elseif k == "autoProfile" then
        local clean = {}
        if v then
          for ctx, name in pairs(v) do
            if type(ctx) == "string" and type(name) == "string" and #name <= 40 then
              clean[ctx] = name
            end
          end
        end
        v = clean
      elseif k == "history" then
        local clean = {}
        if v then
          for _, e in ipairs(v) do
            if type(e) == "table" and type(e.spell) == "string" and type(e.who) == "string" then
              clean[#clean + 1] = { t = IsNumber(e.t) and math_floor(e.t) or 0,
                                    spell = e.spell, who = e.who }
            end
          end
        end
        while #clean > 50 do table.remove(clean, 1) end
        v = clean
      elseif k == "customSpells" then
        local clean, seenIds = {}, {}
        if v then
          for _, id in ipairs(v) do
            if IsNumber(id) and id >= 1 and id <= 2000000 and not seenIds[id] then
              seenIds[id] = true
              clean[#clean + 1] = math_floor(id)
              if #clean >= 20 then break end
            end
          end
        end
        v = clean
      elseif k == "customGroup" then
        local clean, n = {}, 0
        if v then
          for single, group in pairs(v) do
            if type(single) == "string" and type(group) == "string"
               and #single >= 1 and #single <= 60 and #group >= 1 and #group <= 60 then
              clean[single] = group
              n = n + 1
              if n >= 20 then break end
            end
          end
        end
        v = clean
      elseif k == "customThemes" then
        local clean, seenNames = {}, {}
        if v then
          for _, t in ipairs(v) do
            if type(t) == "table" and type(t.name) == "string" and #t.name >= 1 and #t.name <= 24
               and type(t.bg) == "table" and type(t.border) == "table"
               and IsNumber(t.bg[1]) and IsNumber(t.bg[2]) and IsNumber(t.bg[3])
               and IsNumber(t.border[1]) and IsNumber(t.border[2]) and IsNumber(t.border[3])
               and not seenNames[t.name:lower()] then
              seenNames[t.name:lower()] = true
              clean[#clean + 1] = {
                name = t.name,
                bg = { Clamp(t.bg[1], 0, 1), Clamp(t.bg[2], 0, 1), Clamp(t.bg[3], 0, 1) },
                border = { Clamp(t.border[1], 0, 1), Clamp(t.border[2], 0, 1), Clamp(t.border[3], 0, 1) },
              }
              if #clean >= 4 then break end
            end
          end
        end
        v = clean
      elseif k == "rowColors" then
        local clean = {}
        if v then
          for rule, c in pairs(v) do
            if (rule == "mine" or rule == "tank" or rule == "expiring" or rule == "buddy")
               and type(c) == "table" and IsNumber(c[1]) and IsNumber(c[2]) and IsNumber(c[3]) then
              clean[rule] = { Clamp(c[1], 0, 1), Clamp(c[2], 0, 1), Clamp(c[3], 0, 1) }
            end
          end
        end
        v = clean
      elseif k == "buffContext" then
        local clean = {}
        if v then
          for key, ctx in pairs(v) do
            if type(key) == "string" and (ctx == "raid" or ctx == "instance") then
              clean[key] = ctx
            end
          end
        end
        v = clean
      elseif k == "rebuffPer" or k == "stats" or k == "offenders" then
        local clean = {}
        if v then
          for key, n in pairs(v) do
            if type(key) == "string" and IsNumber(n) and n >= 0 then clean[key] = n end
          end
        end
        v = clean
      elseif not v then
        v = {}
        for i, x in pairs(def) do v[i] = x end
      end
    elseif dt == "number" then
      if not IsNumber(v) then v = def end
      local r = RANGES[k]
      if r then v = Clamp(v, r[1], r[2]) end
      if k == "castsTotal" then v = math_floor(v) end
    elseif dt == "boolean" then
      if type(v) ~= "boolean" then v = def end
    elseif dt == "string" then
      -- theme is exempt from its enum: a saved theme's name is valid too
      -- (checked properly after the loop, once customThemes is clean).
      if type(v) ~= "string" or (ENUMS[k] and k ~= "theme" and not ENUMS[k][v]) then v = def end
      if k == "theme" and type(v) == "string" and #v > 24 then v = def end
    end
    saved[k] = v
  end
  if type(saved.theme) == "string" and not ENUMS.theme[saved.theme] then
    local found = false
    for _, t in ipairs(saved.customThemes or {}) do
      if t.name == saved.theme then found = true; break end
    end
    if not found then saved.theme = "custom" end
  end
  local p = saved.point
  if p ~= nil and not (type(p) == "table" and type(p[1]) == "string" and type(p[2]) == "string"
                       and IsNumber(p[3]) and IsNumber(p[4])) then
    saved.point = nil
  end
  if saved.dbVersion ~= nil and not IsNumber(saved.dbVersion) then saved.dbVersion = nil end
  return saved
end
end -- SanitizeDB block

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffBuffRadar|r: " .. tostring(msg))
end

---------------------------------------------------------------------------
-- Localization scaffolding: enUS strings are the keys. A translation file
-- can set BuffRadarLocales["deDE"] = { ["Paused in a major city."] = "..." }
-- before this file loads; only the window's status lines are wired so far.
---------------------------------------------------------------------------
-- Every string the main window, its row tooltips and the minimap / addon-menu
-- tooltips show is listed here (the list doubles as the translator's checklist).
-- Strings with %d / %s are string.format patterns: keep the placeholders.
-- Any key a translation leaves out falls back to English.
local L = {
  -- window status lines
  ["Paused in a major city."] = "Paused in a major city.",
  ["Paused in a battleground."] = "Paused in a battleground.",
  ["Everyone nearby is buffed."] = "Everyone nearby is buffed.",
  ["Some buff information is unavailable."] = "Some buff information is unavailable.",
  ["Estimated range"] = "Estimated range",
  ["Friendly nameplates are off."] = "Friendly nameplates are off.",
  ["Range could not be confirmed; the list may be incomplete."] = "Range could not be confirmed; the list may be incomplete.",
  ["No supported buffs in your spellbook."] = "No supported buffs in your spellbook.",
  ["combat"] = "combat",
  ["Blessings by class"] = "Blessings by class",
  ["Default (%s)"] = "Default (%s)",
  ["Default blessing"] = "Default blessing",
  ["Previously selected blessing unavailable"] = "Previously selected blessing unavailable",
  ["An active group blessing plan takes precedence."] = "An active group blessing plan takes precedence.",
  ["+%d more"] = "+%d more",
  ["Casts: |cffffffff%d|r this session  ·  |cffffffff%d|r all-time"] =
    "Casts: |cffffffff%d|r this session  ·  |cffffffff%d|r all-time",
  -- Compact form, used when the window is too narrow for the line above.
  ["Casts: |cffffffff%d|r / |cffffffff%d|r"] = "Casts: |cffffffff%d|r / |cffffffff%d|r",
  ["out of range"] = "out of range",  -- under a greyed row's name
  ["recently rezzed"] = "recently rezzed",  -- under a rezzed player's name (1.4.0)
  ["a buff just expired"] = "a buff just expired",  -- under the name (1.4.0)
  ["being buffed"] = "being buffed",  -- another BuffRadar user just cast it (1.5.0)
  ["asked for a buff"] = "asked for a buff",  -- asked in chat (1.5.0)
  ["up next"] = "up next",  -- the row your next cast should go to (1.6.0)
  ["your assignment"] = "your assignment",  -- the leader gave this buff to you (1.6.0)
  ["assigned elsewhere"] = "assigned elsewhere",  -- the leader gave this buff to another user (1.6.0)
  ["buddy's watch"] = "buddy's watch",  -- buddy split gave this row to the other user (1.6.0)
  ["All buffed"] = "All buffed",  -- pill text (1.6.0)
  ["Collapse to a pill while everyone is buffed"] = "Collapse to a pill while everyone is buffed",
  ["Tag the next row after a cast"] = "Tag the next row after a cast",
  ["Track flasks, food and runes (coverage line)"] = "Track flasks, food and runes (coverage line)",
  ["Split the list with other BuffRadar users"] = "Split the list with other BuffRadar users",
  ["Post the ready-check summary to group chat"] = "Post the ready-check summary to group chat",
  ["pinned"] = "pinned",  -- row tag for the pinned player (1.7.0)
  ["weapon enchant missing"] = "weapon enchant missing",  -- row tag (1.7.0)
  ["Watch my weapon enchant"] = "Watch my weapon enchant",
  ["Grow the list upward"] = "Grow the list upward",
  ["Two columns when the list is long"] = "Two columns when the list is long",
  ["Print a recap when I die"] = "Print a recap when I die",
  ["Print a report after a wipe"] = "Print a report after a wipe",
  ["Hide the window in combat"] = "Hide the window in combat",
  ["pet"] = "pet",  -- row tag for a group pet (1.8.0)
  ["drinking"] = "drinking",  -- row tag for a drinking healer (1.8.0)
  ["near"] = "near",  -- range band word for a greyed row (1.8.0)
  ["Watch group pets"] = "Watch group pets",
  ["Watch my aura or aspect"] = "Watch my aura or aspect",
  ["Watch my world buffs"] = "Watch my world buffs",
  ["Mark healers who are drinking"] = "Mark healers who are drinking",
  ["Show a name finder on the window"] = "Show a name finder on the window",
  ["Remind me when entering an instance unbuffed"] = "Remind me when entering an instance unbuffed",
  ["Halve the rescan rate in big groups"] = "Halve the rescan rate in big groups",
  ["Skip rescans for aura changes that touch no watched buff"] = "Skip rescans for aura changes that touch no watched buff",
  ["Shift-click a row casts the group version of its buff"] = "Shift-click a row casts the group version of its buff",
  ["Shift-click to cast: %s"] = "Shift-click to cast: %s",
  ["Flash when a pull timer starts"] = "Flash when a pull timer starts",
  ["Low mana -- buffing paused."] = "Low mana -- buffing paused.",
  ["~%dm left"] = "~%dm left",  -- on a row whose buff is about to expire
  ["~%ds left"] = "~%ds left",
  -- settings window (tabs and the main Window / Alerts / Buffs / Behavior
  -- checkboxes; the rest of the settings window is English for now)
  ["Window"] = "Window", ["Alerts"] = "Alerts", ["Buffs"] = "Buffs",
  ["Behavior"] = "Behavior", ["Ignore & Stats"] = "Ignore & Stats",
  ["Show BuffRadar title"] = "Show BuffRadar title",
  ["Show border"] = "Show border",
  ["Minimap button (drag it around the minimap)"] = "Minimap button (drag it around the minimap)",
  ["Play a sound when a name appears"] = "Play a sound when a name appears",
  ["No alert sound in dungeons, raids or battlegrounds"] =
    "No alert sound in dungeons, raids or battlegrounds",
  ["Show cast counter in the window"] = "Show cast counter in the window",
  ["Buff myself first (all buffs that suit me)"] = "Buff myself first (all buffs that suit me)",
  ["Only show in a party or raid"] = "Only show in a party or raid",
  ["Pause scanning in major cities"] = "Pause scanning in major cities",
  ["Pause in battlegrounds and arenas"] = "Pause in battlegrounds and arenas",
  ["Sync casts with other BuffRadar users"] = "Sync casts with other BuffRadar users",
  ["Mark players who ask for a buff in chat"] = "Mark players who ask for a buff in chat",
  ["Print a summary when joining a group"] = "Print a summary when joining a group",
  ["Buff toggle strip on the window"] = "Buff toggle strip on the window",
  ["Paused on a flight path."] = "Paused on a flight path.",
  ["Pause on flight paths"] = "Pause on flight paths",
  ["Alert when a watched buff drops"] = "Alert when a watched buff drops",
["Sound when a buff falls off in combat"] = "Sound when a buff falls off in combat",
  ["Offer group buffs in a party or raid"] = "Offer group buffs in a party or raid",
  ["Show out-of-range players (greyed)"] = "Show out-of-range players (greyed)",
  ["Compact rows (no portraits)"] = "Compact rows (no portraits)",
  ["Per-character window position"] = "Per-character window position",
  ["Shift-right-click to ignore for this session only."] =
    "Shift-right-click to ignore for this session only.",
  -- row tooltip
  ["Out of range — move closer to cast:"] = "Out of range — move closer to cast:",
  ["Click to cast: %s"] = "Click to cast: %s",
  ["Group version — one cast buffs the whole party."] = "Group version — one cast buffs the whole party.",
  ["Right-click to ignore this player."] = "Right-click to ignore this player.",
  ["Still needs: %s"] = "Still needs: %s",
  -- window buttons, minimap button and addon menu
  ["BuffRadar settings"] = "BuffRadar settings",
  ["Drag to resize the window"] = "Drag to resize the window",
  ["Left-click: show / hide the window"] = "Left-click: show / hide the window",
  ["Right-click: settings"] = "Right-click: settings",
  ["Drag: move around the minimap"] = "Drag: move around the minimap",
}
setmetatable(L, { __index = function(_, k) return k end })
do
  local loc = (GetLocale and GetLocale()) or "enUS"
  local pack = _G.BuffRadarLocales and _G.BuffRadarLocales[loc]
  if type(pack) == "table" then
    for k, v in pairs(pack) do if type(v) == "string" then L[k] = v end end
  end
end

---------------------------------------------------------------------------
-- API helpers (tolerant of old and new client APIs)
---------------------------------------------------------------------------
local function SpellName(id, fallback)
  local n
  if C_Spell and C_Spell.GetSpellName then
    n = C_Spell.GetSpellName(id)
  elseif GetSpellInfo then
    n = GetSpellInfo(id)
  end
  return n or fallback
end

local iconCache = {}
local function SpellIcon(name)
  if iconCache[name] == nil then
    local tex
    if C_Spell and C_Spell.GetSpellTexture then tex = C_Spell.GetSpellTexture(name) end
    if not tex and GetSpellTexture then tex = GetSpellTexture(name) end
    iconCache[name] = tex or "Interface\\Icons\\INV_Misc_QuestionMark"
  end
  return iconCache[name]
end

local BookInfo  -- spellbook readers: block-scoped helpers (200-local limit)
do
local BANK = BOOKTYPE_SPELL or "spell"
local function BookName(i)
  if GetSpellBookItemName then
    return (GetSpellBookItemName(i, BANK))
  elseif C_SpellBook and C_SpellBook.GetSpellBookItemName and Enum and Enum.SpellBookSpellBank then
    return (C_SpellBook.GetSpellBookItemName(i, Enum.SpellBookSpellBank.Player))
  elseif GetSpellName then
    return (GetSpellName(i, BANK))
  end
end

-- name, rank text ("Rank 5" or ""), spell id
function BookInfo(i)
  local name, sub, id
  if C_SpellBook and C_SpellBook.GetSpellBookItemInfo and Enum and Enum.SpellBookSpellBank then
    local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, i, Enum.SpellBookSpellBank.Player)
    if ok and type(info) == "table" then
      name, sub, id = info.name, info.subName, info.spellID or info.actionID
    end
  end
  if not name and GetSpellBookItemName then
    name, sub = GetSpellBookItemName(i, BANK)
    if GetSpellBookItemInfo then
      local _, sid = GetSpellBookItemInfo(i, BANK)
      id = id or sid
    end
  end
  if not name then name = BookName(i) end
  return name, sub, id
end
end -- spellbook readers block

local function InRaid()
  if IsInRaid then return IsInRaid() end
  return GetNumRaidMembers and GetNumRaidMembers() > 0
end

local function InGroup()
  if IsInGroup then
    local ok, v = pcall(IsInGroup)
    if ok and v then return true end
  end
  if InRaid() then return true end
  if GetNumGroupMembers then
    local ok, n = pcall(GetNumGroupMembers)
    if ok and type(n) == "number" and n > 0 then return true end
  end
  if GetNumPartyMembers then
    local ok, n = pcall(GetNumPartyMembers)
    if ok and type(n) == "number" and n > 0 then return true end
  end
  return false
end

-- Non-group players are only visible to addons through friendly nameplates,
-- so this CVar decides whether strangers can be listed at all. Returns
-- true/false when the client answers, nil when it can't say.
function X.ReadBooleanCVar(name)
  local reader = (C_CVar and C_CVar.GetCVar) or GetCVar
  if not reader then return nil end
  local ok, value = pcall(reader, name)
  if not ok then return nil end
  if value == "1" or value == 1 or value == true then return true end
  if value == "0" or value == 0 or value == false then return false end
end

function X.FriendlyPlatesOn()
  for _, name in ipairs(X.friendlyPlateCVars) do
    local value = X.ReadBooleanCVar(name)
    if value ~= nil then return value, name end
  end
  if not ((C_CVar and C_CVar.GetCVar) or GetCVar) and GetCVarBool then
    -- A boolean-only client can establish an enabled CVar. False can also
    -- mean that the name is unsupported.
    for _, name in ipairs(X.friendlyPlateCVars) do
      local ok, value = pcall(GetCVarBool, name)
      if ok and value == true then return true, name end
    end
  end
end
X.friendlyPlateCVars = { "nameplateShowFriendlyPlayers", "nameplateShowFriends" }

-- Major cities. Matched by map ID (both the classic-era and modern ID sets, since the
-- Forever client could use either) and by zone name as a fallback.
local CITY_MAP_IDS = {
  [1453]=true, [1454]=true, [1455]=true, [1456]=true, [1457]=true, [1458]=true, -- classic-era
  [1947]=true, [1954]=true, [1955]=true,                                        -- Exodar, Silvermoon, Shattrath
  [84]=true, [85]=true, [87]=true, [88]=true, [89]=true, [90]=true,             -- modern IDs
  [103]=true, [110]=true, [111]=true,
}
local CITY_NAMES = {
  ["Stormwind City"]=true, ["Stormwind"]=true, ["Ironforge"]=true, ["Darnassus"]=true,
  ["Orgrimmar"]=true, ["Thunder Bluff"]=true, ["Undercity"]=true,
  ["The Exodar"]=true, ["Exodar"]=true, ["Silvermoon City"]=true, ["Shattrath City"]=true,
  ["Dornogal"]=true,
}

-- returns isCity, mapID, zoneName (the last two for /br debug)
local function InMajorCity()
  local mapID, zone
  if C_Map and C_Map.GetBestMapForUnit then
    local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
    if ok and type(id) == "number" then mapID = id end
  end
  if GetRealZoneText then
    local ok, z = pcall(GetRealZoneText)
    if ok and type(z) == "string" then zone = z end
  end
  if zone and CITY_NAMES[zone] then return true, mapID, zone end
  -- walk up a couple of parent maps (city sub-areas report their own map ID)
  local id, hops = mapID, 0
  while id and hops < 3 do
    if CITY_MAP_IDS[id] then return true, mapID, zone end
    local info
    if C_Map and C_Map.GetMapInfo then
      local ok, i = pcall(C_Map.GetMapInfo, id)
      if ok then info = i end
    end
    id = info and info.parentMapID
    hops = hops + 1
  end
  return false, mapID, zone
end

-- The Forever engine can hand addons "secret" values that throw when compared or used
-- as table keys. These helpers turn anything unreadable into nil instead of an error.
local function Readable(v)
  if type(v) == "nil" then return false end
  if issecretvalue then
    local ok, secret = pcall(issecretvalue, v)
    if not ok or secret then return false end
  end
  if canaccessvalue then
    local ok, can = pcall(canaccessvalue, v)
    if not ok or not can then return false end
  end
  return true
end

X.Readable = Readable  -- Extras.lua classifies API results with this

function X.IsSelf(unit)
  if not Readable(unit) or type(unit) ~= "string" then return nil end
  if unit == "player" then return true end
  local ok, same = pcall(UnitIsUnit, unit, "player")
  if ok and Readable(same) and type(same) == "boolean" then return same end
end

do
  local function RangeResult(value)
    if not Readable(value) then return nil end
    if value == true or value == 1 then return true end
    if value == false or value == 0 then return false end
  end

  local function QueryRange(api, first, second)
    local ok, value = pcall(api, first, second)
    if ok then return RangeResult(value) end
  end

  local function InRange(spell, unit)
    local modern = C_Spell and C_Spell.IsSpellInRange
    local legacy = IsSpellInRange
    if modern then
      local result = QueryRange(modern, spell, unit)
      if result ~= nil then return result end
    end
    if legacy then
      local result = QueryRange(legacy, spell, unit)
      if result ~= nil then return result end
    end
    -- Some Forever clients expose spell range without a readable answer.
    -- Use a checked group/interaction distance only when neither API answered.
    if UnitInRange then
      local ok, inRange, checked = pcall(UnitInRange, unit)
      if ok and RangeResult(checked) == true then
        local result = RangeResult(inRange)
        if result ~= nil then return result, true end
      end
    end
    if CheckInteractDistance then
      local result = QueryRange(CheckInteractDistance, unit, 4)
      if result ~= nil then return result, true end
    end
    -- Nothing answered. The default stays strict: an unknown range is not
    -- replaced with a guess. On a client that never answers that empties the
    -- window completely, so db.assumeRange opts into the other trade. A unit
    -- only reaches this line as a tracked nameplate or a group member, and the
    -- client has already filtered both by proximity, so the guess is a narrow
    -- one; the row is flagged estimated and a cast that is really too far just
    -- fails with the game's own out-of-range error.
    X.rangeSilent = true
    if db.assumeRange then return true, true end
    return false
  end

  function X.FilterInRange(unit, source, out, isSelf)
    wipe(out)
    if isSelf == nil then isSelf = X.IsSelf(unit) end
    if isSelf == nil then return 0 end
    local n, approximate = 0, false
    for i = 1, #source do
      local inRange, estimated
      if isSelf then inRange = true else inRange, estimated = InRange(source[i], unit) end
      if inRange then
        n = n + 1
        out[n] = source[i]
        if n == 1 then approximate = estimated or false end
      end
    end
    return n, approximate
  end
end

function X.ReadRaidMarker(unit)
  local api = _G.GetRaidTargetIndex
  if not db.raidMarkers or type(api) ~= "function" then return nil end
  local ok, marker = pcall(api, unit)
  if ok and Readable(marker) and type(marker) == "number"
    and marker >= 1 and marker <= 8 and marker == math_floor(marker) then
    return marker
  end
end

local function SafeString(v)
  if not Readable(v) then return nil end
  local ok, s = pcall(tostring, v)
  return ok and s or nil
end

-- A unit flag the client may refuse to answer: true or false when it answers,
-- nil when the value is restricted. Callers decide what an unknown means,
-- because a refusal must never silently empty the whole list.
function X.ReadUnitBool(api, ...)
  if type(api) ~= "function" then return nil end
  local ok, value = pcall(api, ...)
  if not ok then return nil end
  local t = type(value)                     -- type() is safe on a restricted value
  if t == "nil" then return false end        -- the classic "1 or nil" false case
  if not Readable(value) then return nil end
  if t == "boolean" then return value end
  if t == "number" then return value ~= 0 end
end

function X.ReadUnitNumber(api, ...)
  if type(api) ~= "function" then return nil end
  local ok, value = pcall(api, ...)
  if ok and Readable(value) and type(value) == "number" and value == value
      and value > -math_huge and value < math_huge then return value end
end

function X.LowMana()
  local power = X.ReadUnitNumber(_G.UnitPower, "player", 0)
  local maximum = X.ReadUnitNumber(_G.UnitPowerMax, "player", 0)
  return power ~= nil and maximum ~= nil and maximum > 0 and power / maximum * 100 < db.lowMana
end

-- Group role the player picked (dungeon finder / role check): "TANK", "HEALER"
-- or "DAMAGER"; nil for strangers, unassigned players or an unreadable answer.
local function AssignedRole(unit)
  if not UnitGroupRolesAssigned then return nil end
  local ok, r = pcall(UnitGroupRolesAssigned, unit)
  r = ok and SafeString(r) or nil
  if r == "TANK" or r == "HEALER" or r == "DAMAGER" then return r end
  return nil
end

local function GetField(t, k) return t[k] end  -- shared pcall target (no per-call closures)

do
  -- A restricted named lookup returns zero values. An explicit nil is
  -- the normal result when the requested aura is absent.
  local function FirstResult(...)
    return select("#", ...), ...
  end
  local function Call(lookup, unit, name, filter)
    return FirstResult(lookup(unit, name, filter))
  end
  function X.QueryNamedAura(lookup, unit, name, filter)
    local ok, count, aura = pcall(Call, lookup, unit, name, filter)
    if ok and count > 0 then
      if type(aura) == "nil" then return nil, true end
      if Readable(aura) and type(aura) == "table" then return aura, true end
    end
    return nil, false
  end
end

do
  local function AuraExpiration(a)
    local ok, expiry = pcall(GetField, a, "expirationTime")
    if ok and Readable(expiry) and type(expiry) == "number" and expiry >= 0 and expiry < math_huge then
      return expiry
    end
  end

  function X.ReadBuff(unit, i)
    -- done, name, expirationTime, complete (only when done)
    local name, expiry
    if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
      local ok, aura = pcall(C_UnitAuras.GetBuffDataByIndex, unit, i)
      if not ok then return true, nil, nil, false end
      if type(aura) == "nil" then return true, nil, nil, true end
      if Readable(aura) and type(aura) == "table" then
        local nameOK, value = pcall(GetField, aura, "name")
        if nameOK then name = value end
        expiry = AuraExpiration(aura)
      end
    elseif UnitBuff then
      local ok, value, _, _, _, _, expiration = pcall(UnitBuff, unit, i)
      if not ok then return true, nil, nil, false end
      if type(value) == "nil" then return true, nil, nil, true end
      name, expiry = value, expiration
    else
      return true, nil, nil, false
    end
    if not Readable(name) or type(name) ~= "string" then
      X.hid = GetTime()
      return false
    end
    if not Readable(expiry) or type(expiry) ~= "number" or not (expiry >= 0 and expiry < math_huge) then expiry = nil end
    return false, name, expiry
  end

  local function SecondsLeft(expiry, now)
    if expiry == nil then return nil end
    if expiry == 0 then return math_huge end
    return expiry - now
  end

  -- Index fallback reuses its cache for one unit during a single scan.
  local scanCache, uncertainExpiry, complete = {}, {}, false
  local function ScanInto(unit)
    wipe(scanCache)
    wipe(uncertainExpiry)
    X.scanUnit, complete = unit, false
    local now, namesReadable = GetTime(), true
    for i = 1, 40 do
      local done, name, expiry, ended = X.ReadBuff(unit, i)
      if done then
        complete = ended and namesReadable
        break
      elseif name then
        local seconds = SecondsLeft(expiry, now)
        local cached = scanCache[name]
        if seconds and (not cached or seconds > cached) then scanCache[name] = seconds end
        if seconds == nil then uncertainExpiry[name] = true end
      else
        namesReadable = false
      end
    end
  end

  function X.Remaining(unit, name)
    -- Seconds left (math.huge = permanent), presence, unknown alternate timer.
    local lookup = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
    if lookup then
      local aura, definitive = X.QueryNamedAura(lookup, unit, name, "HELPFUL")
      if definitive then
        if not aura then return nil, "absent" end
        return SecondsLeft(AuraExpiration(aura), GetTime()), "present"
      end
    end
    if X.scanUnit ~= unit then ScanInto(unit) end
    if scanCache[name] or uncertainExpiry[name] then
      return scanCache[name], "present", uncertainExpiry[name] or not complete
    end
    return nil, complete and "absent" or "unknown"
  end
end

---------------------------------------------------------------------------
-- Fast aura (1.14.0, Brief 2): is this incremental UNIT_AURA payload about
-- a buff BuffRadar watches? Answers from the payload itself: addedAuras
-- carry full aura data; removed/updated instance ids are resolved through
-- a per-unit cache of ids seen in addedAuras (a removed aura can no longer
-- be asked about), then through the client API. ANY doubt -- unreadable
-- name, unknown id, missing cache -- answers "relevant", and the caller
-- does the normal full refresh. Never answers from a guess.
---------------------------------------------------------------------------
function X.AuraRelevant(unit, added, updated, removed)
  local watch = X.watchNames
  if not watch then return true end
  local cache = X.auraIds or {}; X.auraIds = cache
  local byUnit = cache[unit]
  local function validID(id)
    return Readable(id) and type(id) == "number" and id > 0 and id == math_floor(id)
  end
  local function remember(id, nm)
    if id and nm then
      if not byUnit then byUnit = {}; cache[unit] = byUnit end
      byUnit[id] = nm
    end
  end
  if added then
    for _, a in ipairs(added) do
      if not Readable(a) or type(a) ~= "table" then return true end
      local name, id = a.name, a.auraInstanceID
      if not Readable(name) or type(name) ~= "string" or not validID(id) then return true end
      remember(id, name)
      if watch[name] then return true end
    end
  end
  if updated then
    for _, id in ipairs(updated) do
      if not validID(id) then return true end
      local nm = byUnit and byUnit[id]
      if not nm and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
        local ok, d = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, id)
        if ok and Readable(d) and type(d) == "table" then
          nm = SafeString(GetField(d, "name")); remember(id, nm)
        end
      end
      if not nm then return true end
      if watch[nm] then return true end
    end
  end
  if removed then
    for _, id in ipairs(removed) do
      if not validID(id) then return true end
      local nm = byUnit and byUnit[id]
      if byUnit then byUnit[id] = nil end
      if not nm then return true end
      if watch[nm] then return true end
    end
  end
  return false
end

do
  local function ValidAuraField(value, expectedType)
    return type(value) == "nil" or (Readable(value) and type(value) == expectedType)
  end

  local function InspectAuraEvent(unit, info)
    if not Readable(info) or type(info) ~= "table" then return true end
    local full, added = info.isFullUpdate, info.addedAuras
    local removed, updated = info.removedAuraInstanceIDs, info.updatedAuraInstanceIDs
    if not ValidAuraField(full, "boolean") or not ValidAuraField(added, "table")
      or not ValidAuraField(removed, "table") or not ValidAuraField(updated, "table") then
      return true
    end
    if not full and not added and not removed and not updated then return false end
    local probe = X.auraProbe or {}; X.auraProbe = probe
    probe.seen = (probe.seen or 0) + 1
    if full then
      probe.full = (probe.full or 0) + 1
      if X.auraIds then X.auraIds[unit] = nil end
    end
    if added then probe.added = (probe.added or 0) + 1 end
    if removed then probe.removed = (probe.removed or 0) + 1 end
    if updated then probe.updated = (probe.updated or 0) + 1 end
    if db and db.fastAura and not full and not X.AuraRelevant(unit, added, updated, removed) then
      probe.skipped = (probe.skipped or 0) + 1
      return false
    end
    return true
  end

  function X.AuraEventNeedsRefresh(unit, info)
    if not Readable(unit) or type(unit) ~= "string" then return true end
    if unit ~= "player" and unit ~= "target" and unit ~= "mouseover"
      and not unit:find("^party%d+$") and not unit:find("^raid%d+$")
      and not (unit:find("^nameplate%d+$")
               and X.ReadUnitBool(UnitIsPlayer, unit) == true) then return false end
    local ok, refresh = pcall(InspectAuraEvent, unit, info)
    if not ok and X.auraIds then X.auraIds[unit] = nil end
    return not ok or refresh
  end
end

local function HasAny(unit, names, minLeft)
  minLeft = minLeft or db.rebuff or 0
  local unknown = false
  for i = 1, #names do
    local rem, presence, uncertainTimer = X.Remaining(unit, names[i])
    if rem and rem > minLeft then return true end
    if presence == "present" and rem == nil and minLeft == 0 then return true end
    if presence == "unknown" or (presence == "present" and (rem == nil or uncertainTimer)) then
      unknown = true
    end
  end
  if unknown then return nil end
  return false
end

---------------------------------------------------------------------------
-- What can I cast?
---------------------------------------------------------------------------
local known, myBuffs, myBlessing, blessKnown = {}, {}, {}, {}
local ranks = {}   -- ranks[name] = { {rank=n, sub="Rank n", id=spellID}, ... } ascending
local hasAnyBuff = false
local bookCount = 0
local sessionShow = false   -- user explicitly opened the window this session
local lastError

local BuildBuffList  -- reads the spellbook; helpers block-scoped (200-local limit)
do
local function KnowsSpell(id, name)
  if known[name] then return true end
  if C_SpellBook and C_SpellBook.IsSpellKnown then
    local ok, k = pcall(C_SpellBook.IsSpellKnown, id)
    if ok and k then return true end
  end
  if IsPlayerSpell and IsPlayerSpell(id) then return true end
  if IsSpellKnown and IsSpellKnown(id) then return true end
  return false
end

-- Number of spellbook slots, from the modern skill-line API or legacy tabs; 0 = unknown.
local function SpellbookSize()
  local total = 0
  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo then
    local ok, lines = pcall(C_SpellBook.GetNumSpellBookSkillLines)
    if ok and type(lines) == "number" then
      for t = 1, lines do
        local okI, info = pcall(C_SpellBook.GetSpellBookSkillLineInfo, t)
        if okI and type(info) == "table" then
          total = math_max(total, (info.itemIndexOffset or 0) + (info.numSpellBookItems or 0))
        end
      end
    end
  end
  if total == 0 and GetNumSpellTabs and GetSpellTabInfo then
    local ok, tabs = pcall(GetNumSpellTabs)
    if ok and type(tabs) == "number" then
      for t = 1, tabs do
        local _, _, offset, num = GetSpellTabInfo(t)
        total = math_max(total, (offset or 0) + (num or 0))
      end
    end
  end
  return total
end

local function ByRank(a, b) return a.rank < b.rank end

function BuildBuffList()
  wipe(known)
  local total = SpellbookSize()
  local probing = total == 0      -- size unknown: walk until the book clearly ends
  if probing then total = 600 end
  bookCount = 0
  wipe(ranks)
  local misses = 0
  for i = 1, total do
    local ok, n, sub, id = pcall(BookInfo, i)
    if ok and n then
      misses = 0
      known[n] = true  -- name-based fallback for KnowsSpell: kept on every edition
      bookCount = bookCount + 1
      if CLASSIC_FEATURES then  -- spell ranks: Forever only (retail has none)
        ranks[n] = ranks[n] or {}
        local num = tonumber((sub or ""):match("(%d+)")) or 0
        table.insert(ranks[n], { rank = num, sub = sub, id = id })
      end
    else
      misses = misses + 1
      if probing and misses >= 30 then break end
    end
  end
  for _, list in pairs(ranks) do
    table_sort(list, ByRank)
  end

  wipe(myBuffs)
  for _, d in ipairs(BUFF_DEFS) do
    local castName, names = nil, {}
    if d.choices then
      for _, c in ipairs(d.choices) do
        local n = SpellName(c[1], c[2])
        names[#names + 1] = n
        if not castName and KnowsSpell(c[1], n) then castName = n end
      end
    else
      local n = SpellName(d.id, d.name)
      names[1] = n
      if KnowsSpell(d.id, n) then castName = n end
    end
    if castName then
      for _, a in ipairs(d.also or {}) do names[#names + 1] = SpellName(a[1], a[2]) end
      local groupName
      if d.groupCast then
        local gn = SpellName(d.groupCast[1], d.groupCast[2])
        if KnowsSpell(d.groupCast[1], gn) then groupName = gn end
      end
      myBuffs[#myBuffs + 1] = { key = d.key, name = castName, names = names,
                                classes = d.classes or ALL, self = d.self,
                                groupOnly = d.groupOnly, role = d.role, single = d.single, who = d.who, default = d.on, groupName = groupName, pets = d.pets }
    end
  end

  -- Custom watched spells (1.6.0): any spell you know can join the list.
  -- A spell whose name matches a built-in buff is skipped -- it is already
  -- watched, and listing it twice would double its rows.
  for _, id in ipairs(db and db.customSpells or {}) do
    local n = SpellName(id, nil)
    if n and KnowsSpell(id, n) then
      local dup = false
      for _, b in ipairs(myBuffs) do if b.name == n then dup = true break end end
      if not dup then
        myBuffs[#myBuffs + 1] = { key = "CUSTOM" .. id, name = n, names = { n },
                                  classes = ALL, default = true, custom = id }
      end
    end
  end

  -- Aura / aspect watch (1.8.0, Forever): self-only stances join the
  -- buff list while the watch is on, like the custom spells above.
  if CLASSIC_FEATURES and db and db.auraWatch then
    for _, d in ipairs(X.AURA_DEFS or {}) do
      local castName, names = nil, {}
      for _, c in ipairs(d.choices) do
        local n = SpellName(c[1], c[2])
        names[#names + 1] = n
        if not castName and KnowsSpell(c[1], n) then castName = n end
      end
      if castName then
        local dup = false
        for _, b in ipairs(myBuffs) do if b.name == castName then dup = true break end end
        if not dup then
          myBuffs[#myBuffs + 1] = { key = d.key, name = castName, names = names,
                                    classes = ALL, self = true, aura = true,
                                    who = d.who, default = true }
        end
      end
    end
  end

  wipe(myBlessing)
  for class, list in pairs(CLASSIC_FEATURES and X.BLESSING_PRIORITY or {}) do
    for _, k in ipairs(list) do
      local b = BLESSINGS[k]
      local name = SpellName(b.id, b.name)
      if KnowsSpell(b.id, name) then
        myBlessing[class] = { name = name,
                              names = { name, SpellName(b.greater[1], b.greater[2]) } }
        break
      end
    end
  end

  -- Every blessing you know, by key: the blessing planner (1.6.0) picks
  -- from this instead of the per-class priority list when a plan is set.
  wipe(blessKnown)
  for k, b in pairs(BLESSINGS) do
    local name = SpellName(b.id, b.name)
    if KnowsSpell(b.id, name) then
      blessKnown[k] = { name = name,
                        names = { name, SpellName(b.greater[1], b.greater[2]) } }
    end
  end

  do  -- watched aura names for the fast-aura relevance check (1.14.0)
    local watch = {}
    for _, b in ipairs(myBuffs) do
      if b.name then watch[b.name] = true end
      for _, n in ipairs(b.names or {}) do watch[n] = true end
    end
    for _, cd in ipairs(X.CONS_DEFS or {}) do
      for _, n in ipairs(cd.names or {}) do watch[n] = true end
      if cd.sub then watch[cd.sub] = true end
    end
    for _, b in pairs(blessKnown) do
      if type(b) == "table" then
        if b.name then watch[b.name] = true end
        for _, n in ipairs(b.names or {}) do watch[n] = true end
      end
    end
    X.watchNames = watch
  end
  hasAnyBuff = (#myBuffs > 0) or (CLASSIC_FEATURES and next(blessKnown) ~= nil)
end
end -- BuildBuffList block

function X.HasKnownBlessings()
  return CLASSIC_FEATURES and next(blessKnown) ~= nil
end

function X.BlessingOptions(class)
  if not X.BLESSING_CLASSES[class] then return {} end
  local list = { { key = "DEFAULT", name = myBlessing[class] and myBlessing[class].name } }
  for _, key in ipairs(X.BLESSING_KEYS) do
    local knownBlessing = blessKnown[key]
    if knownBlessing then list[#list + 1] = { key = key, name = knownBlessing.name } end
  end
  return list
end

function X.BlessingPreference(class)
  return db.blessingPreferences[class] or "DEFAULT"
end

function X.SetBlessingPreference(class, key)
  if not CLASSIC_FEATURES or not X.BLESSING_CLASSES[class] then return false end
  if key == "DEFAULT" then
    db.blessingPreferences[class] = nil
  elseif blessKnown[key] then
    db.blessingPreferences[class] = key
  else
    return false
  end
  return true
end

function X.BlessingForClass(class)
  local plan = X.blessPlan[class]
  if plan then return plan.mine and blessKnown[plan.key] or nil end
  return blessKnown[db.blessingPreferences[class]] or myBlessing[class]
end

local function IsOn(key, default)
  local v = db.enabled[key]
  if v == nil then return default end
  return v
end

-- True while a spell is on a real cooldown (longer than the global cooldown), e.g. Fear Ward.
-- Answers are cached for the duration of one refresh (cdCache is wiped per refresh).
local cdCache = {}
local function IsCooling(start, duration)
  return start ~= nil and duration ~= nil and start > 0 and duration > 1.5
end
local function SpellCD(name)
  if C_Spell and C_Spell.GetSpellCooldown then
    local ok, info = pcall(C_Spell.GetSpellCooldown, name)
    if ok and type(info) == "table" then
      local okS, st = pcall(GetField, info, "startTime")
      local okD, du = pcall(GetField, info, "duration")
      if okS and okD then return st, du end
    end
    return nil, nil
  elseif GetSpellCooldown then
    local ok, st, du = pcall(GetSpellCooldown, name)
    if ok then return st, du end
  end
  return nil, nil
end
local function OnCooldown(name)
  local c = cdCache[name]
  if c ~= nil then return c end
  local start, duration = SpellCD(name)
  local ok, cooling = pcall(IsCooling, start, duration)
  c = (ok and cooling) and true or false
  cdCache[name] = c
  return c
end

-- Seconds left on a spell's real cooldown (0 when ready or only the GCD is
-- running). Cached per refresh like OnCooldown (wiped with cdCache).
local cdLeftCache = {}
local function CooldownLeft(name)
  local c = cdLeftCache[name]
  if c ~= nil then return c end
  local start, duration = SpellCD(name)
  local left = 0
  local ok, cooling = pcall(IsCooling, start, duration)
  if ok and cooling then
    left = start + duration - GetTime()
    if left < 0 then left = 0 end
  end
  cdLeftCache[name] = left
  return left
end

-- Ordered list of my spells this unit still needs.
-- Your own row: self-only buffs always; other buffs only with /br self.
-- isGroup: the unit came from your party/raid roster (or is you); group-only
-- buffs are skipped for everyone else.

-- Single-target buffs (Earth Shield): during each scan, holder[key] is the
-- unit that has YOUR copy (found with the "PLAYER" aura filter, i.e. cast by
-- you), and CollectEntries then drops that buff from everyone else's row.
-- If the game can't tell whose it is, nothing is dropped (the old behavior).
-- keep/drop are scratch lists reused by CollectEntries.
local Single = { holder = {}, spell = {}, keep = {}, drop = {} }

---------------------------------------------------------------------------
-- Enhancement state (1.4.0). One table on purpose: the main chunk is near
-- Lua 5.1's 200-local limit, so new state lives here, not in new locals.
--   session: session-only ignore set, Ignore.Key(name) -> true (never saved)
--   dead / rezAt: group members seen dead, and when each was seen alive
--     again -- a rezzed player has lost every buff and jumps the queue
--   tally: per-buff coverage over group members from the latest scan,
--     buff key -> { total = n, miss = n }; tallyUnits = members scanned
---------------------------------------------------------------------------

-- Consumables watch (1.6.0): not castable, so these never make rows --
-- they only feed the coverage line. Matched by aura name: exact names, or
-- a substring ("Flask of ..." covers every flask on both clients).
X.CONS_DEFS = {
  { key = "FLASK", label = "Flask", sub = "Flask of" },
  { key = "FOOD", label = "Food", names = { "Well Fed" } },
}
if not CLASSIC_FEATURES then
  X.CONS_DEFS[#X.CONS_DEFS + 1] = { key = "RUNE", label = "Rune", sub = "Augment Rune" }
end

-- World-buff watch (1.8.0, Forever): the famous world buffs on YOU,
-- matched by aura name like the consumables above. Feeds one segment of
-- the coverage line, so a raid can see whose Dragonslayer is ticking.
X.WORLD_BUFFS = {
  { name = "Rallying Cry of the Dragonslayer" }, { name = "Warchief's Blessing" },
  { name = "Songflower Serenade" }, { name = "Spirit of Zandalar" },
  { sub = "Sayge's Dark Fortune" }, { name = "Fengus' Ferocity" },
  { name = "Mol'dar's Moxie" }, { name = "Slip'kik's Savvy" },
  { name = "Traces of Silithid" },
}

function X.WorldBuffsText()
  if not CLASSIC_FEATURES then return nil end
  local found = {}
  for i = 1, 40 do
    local done, name = X.ReadBuff("player", i)
    if done then break end
    if name then
      for _, w in ipairs(X.WORLD_BUFFS) do
        if (w.name and name == w.name) or (w.sub and name:find(w.sub, 1, true)) then
          local left = X.Remaining("player", name)
          local when = ""
          if left and left < math_huge then
            when = left >= 3600 and string_format(" ~%dh", math_floor(left / 3600))
              or string_format(" ~%dm", math_floor(left / 60))
          end
          found[#found + 1] = name .. when
          break
        end
      end
    end
  end
  if #found == 0 then return nil end
  return "World: " .. table.concat(found, ", ")
end

function X.ConsHas(unit, def)
  local complete = true
  for i = 1, 40 do
    local done, name, _, ended = X.ReadBuff(unit, i)
    if done then
      if ended and complete then return false end
      return nil
    end
    if name then
      if def.sub and name:find(def.sub, 1, true) then return true end
      if def.names then
        for _, nm in ipairs(def.names) do if name == nm then return true end end
      end
    else complete = false end
  end
end
X.listedBefore = X.listA  -- guid -> true for names on the board last refresh

function X.Track(unit)
  if not UnitExists(unit) then return end
  local guid = SafeString(UnitGUID(unit))
  if not guid then return end
  if X.ReadUnitBool(UnitIsDeadOrGhost, unit) == true then
    X.dead[guid] = true
  elseif X.dead[guid] then
    X.dead[guid] = nil
    X.rezAt[guid] = GetTime()
  end
end

function X.TrackDeaths(list, extra)
  for i = 1, #list do X.Track(list[i]) end
  if extra then X.Track(extra) end
end

local function Missing(unit, out, isGroup, isSelf)
  wipe(out)
  X.remainTmp, X.auraUnknown = nil, nil
  local _, class = UnitClass(unit)
  class = SafeString(class)  -- used as a table key below; protected values can't be
  if not class then return 0 end
  if isGroup and db.consumables then
    for _, cd in ipairs(X.CONS_DEFS) do
      local t = X.consTally[cd.key]
      if not t then t = { total = 0, miss = 0 }; X.consTally[cd.key] = t end
      local has = X.ConsHas(unit, cd)
      if has ~= nil then t.total = t.total + 1 end
      if has == false then t.miss = t.miss + 1 end
    end
  end
  X.scanUnit = nil  -- force a fresh index scan (fallback path) for this unit
  local n = 0
  local role, roleRead = nil, false  -- assigned role, read once and only if a buff needs it
  local lookup = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
  for i = 1, #myBuffs do
    local b = myBuffs[i]
    if b.single and not isSelf and not Single.holder[b.key] and lookup then
      local aura = X.QueryNamedAura(lookup, unit, b.name, "HELPFUL|PLAYER")
      if aura then
        Single.holder[b.key], Single.spell[b.key] = unit, b.name
      end
    end
    local applies
    if b.self then
      applies = isSelf
    else
      applies = b.classes[class] and (not isSelf or db.includeSelf)
                and (isGroup or isSelf or not b.groupOnly)
      if applies and b.role then
        if not roleRead then role, roleRead = AssignedRole(unit), true end
        if role and role ~= b.role then applies = false end  -- e.g. a DPS death knight
      end
    end
    if applies and IsOn(b.key, b.default) and X.ContextOK(b.key) then
      local thr = (db.rebuffPer and db.rebuffPer[b.key]) or db.rebuff
      local has = HasAny(unit, b.names, thr)
      if has == nil then X.auraUnknown = true end
      local t
      if isGroup and has ~= nil then
        t = X.tally[b.key]
        if not t then t = { total = 0, miss = 0 }; X.tally[b.key] = t end
        t.total = t.total + 1
      end
      if not OnCooldown(b.name) then
        if has == false then
          n = n + 1
          out[n] = b.name
          if t then t.miss = t.miss + 1 end
          if n == 1 then  -- still present but inside its rebuff window?
            for _, nm2 in ipairs(b.names) do
              local r = X.Remaining(unit, nm2)
              if r and r > 0 and r < math_huge then X.remainTmp = r break end
            end
          end
        elseif isGroup and has == true then
          -- Group expiry watch (1.7.0): the buff is up, but inside its
          -- last five minutes — count it toward the coverage warning.
          local soonest = math_huge
          for _, nm2 in ipairs(b.names) do
            local r = X.Remaining(unit, nm2)
            if r and r < soonest then soonest = r end
          end
          if soonest <= 300 then
            X.expiryTally[b.key] = (X.expiryTally[b.key] or 0) + 1
          end
        end
      end
    end
  end
  local bl = CLASSIC_FEATURES and X.BlessingForClass(class)
  if bl and IsOn("BLESSINGS", true) and (not isSelf or db.includeSelf)
     and X.ContextOK("BLESSINGS") then
    local has = HasAny(unit, bl.names)
    if has == nil then X.auraUnknown = true end
    local t
    if isGroup and has ~= nil then
      t = X.tally.BLESSINGS
      if not t then t = { total = 0, miss = 0 }; X.tally.BLESSINGS = t end
      t.total = t.total + 1
    end
    if has == false then
      n = n + 1
      out[n] = bl.name
      if t then t.miss = t.miss + 1 end
      if n == 1 then
        for _, nm2 in ipairs(bl.names) do
          local r = X.Remaining(unit, nm2)
          if r and r > 0 and r < math_huge then X.remainTmp = r break end
        end
      end
    elseif isGroup and has == true then
      -- Blessings count toward the group expiry watch too (1.7.0).
      local soonest = math_huge
      for _, nm2 in ipairs(bl.names) do
        local r = X.Remaining(unit, nm2)
        if r and r < soonest then soonest = r end
      end
      if soonest <= 300 then
        X.expiryTally.BLESSINGS = (X.expiryTally.BLESSINGS or 0) + 1
      end
    end
  end
  if isGroup and not X.auraUnknown then
    X.tallyUnits = X.tallyUnits + 1
    if n > 0 then X.tallyMissingUnits = X.tallyMissingUnits + 1 end
  elseif isGroup then
    X.tallyUnknownUnits = X.tallyUnknownUnits + 1
  end
  return n
end

---------------------------------------------------------------------------
-- Who is around?
---------------------------------------------------------------------------
local RAID, PARTY, PLATES = {}, {}, {}
for i = 1, 40 do RAID[i] = "raid" .. i; PLATES[i] = "nameplate" .. i end
for i = 1, 4 do PARTY[i] = "party" .. i end

local function Valid(unit)
  -- Existence and "is a player" stay strict: a refusal there would let NPCs
  -- onto the list. The flags below are permissive instead, because excluding a
  -- player on an unreadable answer costs the whole feature, while listing one
  -- who cannot be buffed costs a single failed cast with a clear error.
  if X.ReadUnitBool(UnitExists, unit) ~= true then return false end
  if X.ReadUnitBool(UnitIsPlayer, unit) ~= true then return false end
  if X.ReadUnitBool(UnitIsDeadOrGhost, unit) == true then return false end
  if X.ReadUnitBool(UnitIsConnected, unit) == false then return false end
  -- Self is inherently assistable; some Classic clients reject this API check.
  local isSelf = X.IsSelf(unit)
  if isSelf == nil then return false end
  if not isSelf and X.ReadUnitBool(UnitCanAssist, "player", unit) == false then return false end
  if not UnitAffectingCombat then return false end
  local okPlayer, playerCombat = pcall(UnitAffectingCombat, "player")
  if not okPlayer or not Readable(playerCombat) or playerCombat ~= false then return false end
  local okUnit, unitCombat = pcall(UnitAffectingCombat, unit)
  if not okUnit or not Readable(unitCombat) or unitCombat ~= false then return false end
  if UnitIsCharmed then
    local ok, charmed = pcall(UnitIsCharmed, unit)
    if not ok or not Readable(charmed) or charmed ~= false then return false end
  end
  if _G.UnitInPhase then  -- a player in another phase can't be reached or buffed
    if X.ReadUnitBool(_G.UnitInPhase, unit) == false then return false end
  end
  if db.avoidPvP then
    local ok, flagged = pcall(UnitIsPVP, unit)
    if not ok or not Readable(flagged) or flagged ~= false then
      local okPlayerPvP, playerFlagged = pcall(UnitIsPVP, "player")
      if not okPlayerPvP or not Readable(playerFlagged) or playerFlagged ~= true then return false end
    end
  end
  return true, isSelf
end

-- Your buff priority (1.10.0): db.buffPrio holds buff keys in the
-- order you want them offered. The map (display name -> position) is
-- rebuilt lazily whenever the spellbook or the saved order changed.
X.prioDirty = true
function X.RebuildPrio()
  X.prioDirty = false
  X.prioIdx = {}
  if not db or not db.buffPrio then return end
  local byKey = {}
  for _, b in ipairs(myBuffs) do byKey[b.key] = b.name end
  for i, key in ipairs(db.buffPrio) do
    local nm = byKey[key]
    if nm and not X.prioIdx[nm] then X.prioIdx[nm] = i end
  end
end

-- Entry tables are pooled and reused every refresh (no per-refresh garbage).
local entries, entryPool, seen = {}, {}, {}
local nEntries = 0

local function EntryOrder(a, b)
  if a.isSelf ~= b.isSelf then return a.isSelf end
  if (a.pinned or false) ~= (b.pinned or false) then return a.pinned ~= nil end
  if (a.rezzed or false) ~= (b.rezzed or false) then return a.rezzed ~= nil end
  if (a.mine or false) ~= (b.mine or false) then return a.mine ~= nil end
  if (a.theirs or false) ~= (b.theirs or false) then return not a.theirs end
  if (a.buddy or false) ~= (b.buddy or false) then return not a.buddy end
  if (a.handled or false) ~= (b.handled or false) then return not a.handled end
  if (a.pet or false) ~= (b.pet or false) then return not a.pet end
  if db.sortMode == "need" and (a.prio1 or 999) ~= (b.prio1 or 999) then
    return (a.prio1 or 999) < (b.prio1 or 999)
  end
  if db.sortMode == "need" and #a.missing ~= #b.missing then return #a.missing > #b.missing end
  if db.sortMode == "distance" and (a.rangeBucket or 2) ~= (b.rangeBucket or 2) then
    return (a.rangeBucket or 2) < (b.rangeBucket or 2)
  end
  if db.sortMode == "role" and (a.role or 3) ~= (b.role or 3) then
    return (a.role or 3) < (b.role or 3)
  end
  if (a.outOfRange or false) ~= (b.outOfRange or false) then return not a.outOfRange end
  if a.group ~= b.group then return a.group end
  return a.sortName < b.sortName  -- readable name, or "" (a shown name may be protected)
end

-- Sort priority for "role" mode: you, then tanks, then group leaders, then
-- everyone else. Tanks are players with the TANK group role (retail role
-- check / dungeon finder) or the raid MAINTANK/MAINASSIST flag — never a
-- guess from class.
local function RoleOf(unit, isSelf)
  if isSelf then return 0 end
  if AssignedRole(unit) == "TANK" then return 1 end
  local idx = unit:match("^raid(%d+)$")
  if idx and GetRaidRosterInfo then
    local ok, _, _, _, _, _, _, _, _, role = pcall(GetRaidRosterInfo, tonumber(idx))
    if ok and (role == "MAINTANK" or role == "MAINASSIST") then return 1 end
  end
  if UnitIsGroupLeader then
    local ok, leader = pcall(UnitIsGroupLeader, unit)
    if ok and Readable(leader) and leader == true then return 2 end
  end
  return 3
end

---------------------------------------------------------------------------
-- Ignore list. db.ignored keeps names as entered (value true -- the same
-- format as before 1.3.2); matching goes through Ignore.index, keyed by
-- Ignore.Key(): lowercase, spaces removed. "Name-Realm" ignores one player;
-- a bare "Name" (every entry saved before 1.3.2) ignores that name on any realm.
---------------------------------------------------------------------------
-- One table rather than separate locals: the file's main chunk is close to
-- Lua 5.1's 200-local limit (see the config window section).
--   index: Ignore.Key(name) -> name as stored in db.ignored
--   realm: your own realm, filled in on first use
local Ignore = { index = {} }

function Ignore.Key(name) return (name:gsub("%s+", "")):lower() end
X.Ignore = Ignore  -- for Extras.lua (1.13.0)

-- Called after the saved settings load: builds the index and drops entries
-- that differ only in case or spacing ("bob" next to "Bob").
function Ignore.Rebuild()
  wipe(Ignore.index)
  local dupes
  for name in pairs(db.ignored) do
    local k = Ignore.Key(name)
    if Ignore.index[k] then
      dupes = dupes or {}
      dupes[#dupes + 1] = name
    else
      Ignore.index[k] = name
    end
  end
  if dupes then
    for _, name in ipairs(dupes) do db.ignored[name] = nil end
  end
end

-- Returns false when the name (in any spelling) is already on the list.
function Ignore.Add(name)
  local k = Ignore.Key(name)
  if Ignore.index[k] then return false end
  db.ignored[name] = true
  Ignore.index[k] = name
  return true
end

-- Removes the matching entry. Unless exact, a bare name also removes that
-- name's Name-Realm entries, so "/br unignore Bob" clears Bob on every realm.
-- Returns the removed names as they were stored.
function Ignore.Remove(name, exact)
  local k, removed = Ignore.Key(name), {}
  if Ignore.index[k] then removed[1] = Ignore.index[k] end
  if not exact and not k:find("-", 1, true) then
    local prefix = k .. "-"
    for key, stored in pairs(Ignore.index) do
      if key:sub(1, #prefix) == prefix then removed[#removed + 1] = stored end
    end
  end
  for _, stored in ipairs(removed) do
    db.ignored[stored] = nil
    Ignore.index[Ignore.Key(stored)] = nil
  end
  return removed
end

-- "Name-Realm" (your own realm filled in) and the bare name; nil when unreadable.
function Ignore.UnitNames(unit)
  local name, realm
  if UnitFullName then
    local ok, n, r = pcall(UnitFullName, unit)
    if ok then name, realm = SafeString(n), SafeString(r) end
  end
  if not name then
    local ok, n = pcall(UnitName, unit)
    name = ok and SafeString(n) or nil
  end
  if not name then return nil, nil end
  if not realm or realm == "" then
    if not Ignore.realm and GetNormalizedRealmName then
      local ok, r = pcall(GetNormalizedRealmName)
      Ignore.realm = ok and SafeString(r) or nil
    end
    realm = Ignore.realm
  end
  return realm and realm ~= "" and (name .. "-" .. realm) or name, name
end

function Ignore.Has(full, short)
  if full and Ignore.index[Ignore.Key(full)] then return true end
  return short ~= nil and Ignore.index[Ignore.Key(short)] ~= nil
end

function Ignore.ByKey(a, b) return Ignore.Key(a) < Ignore.Key(b) end
-- Ignored names as stored, sorted alphabetically (case-insensitive).
function Ignore.Sorted()
  local names = {}
  for name in pairs(db.ignored) do names[#names + 1] = name end
  table_sort(names, Ignore.ByKey)
  return names
end

-- Session-only ignore (1.4.0): same keying as the saved list, never persisted.
function X.SessionHas(full, short)
  if full and X.session[Ignore.Key(full)] then return true end
  return short ~= nil and X.session[Ignore.Key(short)] ~= nil
end

local function Consider(unit, isGroup)
  local valid, isSelf = Valid(unit)
  if not valid then return end
  -- The GUID is a table key (seen[], the listed sets) and gets compared; a
  -- protected one can't be either, so that unit is skipped.
  local guid = SafeString(UnitGUID(unit))
  if not guid or seen[guid] then return end
  local blockedUntil = X.failedTargets[guid]
  if blockedUntil then
    if blockedUntil > GetTime() then return end
    X.failedTargets[guid] = nil
  end
  local full, nm = Ignore.UnitNames(unit)
  if next(Ignore.index) and Ignore.Has(full, nm) then return end  -- on the ignore list
  if next(X.session) and X.SessionHas(full, nm) then return end  -- session-only ignore
  if X.applyFilter and isGroup and db.roleFilter ~= "ALL"
     and _G.UnitGroupRolesAssigned  -- clients without assigned roles: no filtering
     and not isSelf
     and AssignedRole(unit) ~= db.roleFilter then return end  -- role filter (window only)
  seen[guid] = true
  -- Healer drinking (1.8.0, Forever): anyone in the group with a Drink
  -- aura is marked; healing classes also feed the coverage line count.
  X.scanUnit = nil
  if isGroup and db.drinkWatch and CLASSIC_FEATURES
     and select(2, X.Remaining(unit, "Drink")) == "present" then
    X.drinkSet[guid] = true
    local _, dclass = UnitClass(unit)
    dclass = SafeString(dclass)
    if dclass == "PRIEST" or dclass == "PALADIN" or dclass == "SHAMAN"
       or dclass == "DRUID" then
      X.drinkHealers = (X.drinkHealers or 0) + 1
    end
  end
  local slot = nEntries + 1
  local e = entries[slot]
  if not e then
    local p = #entryPool
    if p > 0 then e = entryPool[p]; entryPool[p] = nil else e = { missing = {}, allMissing = {} } end
    entries[slot] = e
  end
  if not e.allMissing then e.allMissing = {} end
  local allN = Missing(unit, e.allMissing, isGroup, isSelf)
  local auraUnknown = X.auraUnknown
  e.remain1 = X.remainTmp
  if isGroup and not auraUnknown and allN == 0 then X.missNow[guid] = {} end
  local n, approximate = X.FilterInRange(unit, e.allMissing, e.missing, isSelf)
  if allN > 0 and n == 0 and db.rangeWatch then X.farNow[guid] = nm or UnitName(unit) or true end
  if n == 0 then return end  -- only list targets with a buff currently in range
  nEntries = slot
  local _, class = UnitClass(unit)
  -- e.name may be a protected value (display only: SetText accepts those);
  -- sorting uses sortName and the class goes through SafeString (table key).
  e.unit, e.guid, e.name, e.class, e.group = unit, guid, nm or UnitName(unit), SafeString(class), isGroup
  e.fullName, e.sortName = full, nm or ""
  e.isSelf = isSelf
  e.rangeBucket = 0
  e.approximateRange = approximate
  e.marker = X.ReadRaidMarker(unit)
  if isGroup and not auraUnknown then
    -- Expiry tracking: a buff that was not missing last scan, is missing
    -- now, and is truly gone (not just inside its rebuff window) expired,
    -- was dispelled, or went away with a death.
    local keys, expired, fallExpired = {}, nil, nil
    for j = 1, #e.allMissing do
      local key = X.KeyOfName(e.allMissing[j])
      if key then
        keys[key] = true
        local prev = X.missPrev[guid]
        if prev and not prev[key] and HasAny(unit, { e.allMissing[j] }, 0) == false then
          expired = true
          if not Single.spell[key] then fallExpired = true end
        end
      end
    end
    X.missNow[guid] = keys
    -- Sticky for a few seconds: the next scan already sees the buff as
    -- "missing last time too", so without this the flag would flap off.
    if expired then X.expiredAt[guid] = GetTime() end
    -- #33 (1.15.0): a group buff that was up before the fight and is gone
    -- at the first scan after it fell off here -- CheckFalls plays the
    -- distinct "fall" alert for it (single-target buffs excluded: they
    -- have their own drop alert in CheckDrops).
    if fallExpired and db.fallSound and X.afterCombatScan then X.fallPending = true end
    local ea = X.expiredAt[guid]
    e.expired = (expired or (ea and GetTime() - ea < 10)) or nil
  else
    e.expired = nil
  end
  local rz = X.rezAt[guid]
  e.rezzed = (rz and GetTime() - rz < 60) or nil
  e.outOfRange = false
  e.groupCast = false
  e.role = RoleOf(unit, isSelf)
  e.pet = nil
end

-- What a pet still needs (1.8.0): only the buffs whose definitions say
-- they land on pets (Fortitude, Mark of the Wild, Arcane Intellect).
-- Pets have no class list to check against, and they never feed the
-- coverage tallies -- this writes only the entry's missing list.
function X.PetMissing(unit, out)
  wipe(out)
  X.scanUnit = nil
  local n = 0
  for i = 1, #myBuffs do
    local b = myBuffs[i]
    if b.pets and not b.self and IsOn(b.key, b.default) and X.ContextOK(b.key)
       and not OnCooldown(b.name) then
      local thr = (db.rebuffPer and db.rebuffPer[b.key]) or db.rebuff
      if HasAny(unit, b.names, thr) == false then
        n = n + 1
        out[n] = b.name
      end
    end
  end
  return n
end

-- A group pet joins the list as its own row (1.8.0): the row targets the
-- pet unit, shows the pet's name and portrait, and sorts just after the
-- players. Pooled-entry hygiene mirrors Consider, plus pet=true.
function X.ConsiderPet(petUnit, ownerUnit)
  if not UnitExists(petUnit) then return end
  if X.ReadUnitBool(UnitIsDeadOrGhost, petUnit) == true then return end
  if X.ReadUnitBool(UnitCanAssist, "player", petUnit) == false then return end
  local isSelf = X.IsSelf(petUnit)
  if isSelf == nil then return end
  local guid = SafeString(UnitGUID(petUnit))
  if not guid or seen[guid] then return end
  seen[guid] = true
  local pname = SafeString(UnitName(petUnit))
  if not pname then return end
  local slot = nEntries + 1
  local e = entries[slot]
  if not e then
    local p = #entryPool
    if p > 0 then e = entryPool[p]; entryPool[p] = nil else e = { missing = {}, allMissing = {} } end
    entries[slot] = e
  end
  if not e.allMissing then e.allMissing = {} end
  local allN = X.PetMissing(petUnit, e.allMissing)
  if allN == 0 then return end
  local n, approximate = X.FilterInRange(petUnit, e.allMissing, e.missing, isSelf)
  if n == 0 then return end
  nEntries = slot
  local _, oclass = UnitClass(ownerUnit)
  e.unit, e.guid, e.name = petUnit, guid, pname
  e.sortName = (SafeString(UnitName(ownerUnit)) or "") .. " " .. pname
  e.fullName = nil
  e.class = SafeString(oclass)
  e.group, e.isSelf, e.pet = true, false, true
  e.rangeBucket = 0
  e.approximateRange = approximate
  e.marker = X.ReadRaidMarker(petUnit)
  e.remain1 = nil
  e.expired, e.rezzed = nil, nil
  e.outOfRange = false
  e.groupCast = false
  e.role = 3
end

-- Last-scan diagnostics for /br debug: how many nameplate units the client
-- handed us on the latest pass, and how many of them were players.

local function CollectEntries()
  wipe(seen)
  wipe(cdCache)
  wipe(cdLeftCache)
  wipe(Single.holder)
  wipe(X.tally)
  wipe(X.consTally)
  wipe(X.expiryTally)
  wipe(X.drinkSet)
  X.drinkHealers = 0
  X.tallyUnits, X.tallyMissingUnits, X.tallyUnknownUnits = 0, 0, 0
  X.rangeSilent = false
  X.missPrev, X.missNow = X.missNow, {}
  wipe(X.missNow)
  X.fallPending = nil
  nEntries = 0
  X.platesSeen, X.playersSeen = 0, 0
  local list = InRaid() and RAID or PARTY
  X.TrackDeaths(list, "player")
  for i = 1, #list do Consider(list[i], true) end
  Consider("player", true)
  -- Group pets (1.8.0): your pet and your group members' pets, as rows.
  if db and db.pets then
    X.ConsiderPet("pet", "player")
    if InRaid() then
      for i = 1, 40 do X.ConsiderPet("raidpet" .. i, RAID[i]) end
    else
      for i = 1, 4 do X.ConsiderPet("partypet" .. i, PARTY[i]) end
    end
  end
  Consider("target", false)
  Consider("mouseover", false)
  for i = 1, #PLATES do
    local u = PLATES[i]
    if UnitExists(u) then
      X.platesSeen = X.platesSeen + 1
      if X.ReadUnitBool(UnitIsPlayer, u) == true then X.playersSeen = X.playersSeen + 1 end
    end
    Consider(u, false)
  end
  -- Name finder (1.8.0): with a search text set, the window lists only
  -- matching names. Reports (announce, digests) turn it off together with
  -- the role filter, so their counts stay honest.
  if X.applyFilter and X.search and X.search ~= "" then
    local keep, drop = Single.keep, Single.drop
    wipe(keep); wipe(drop)
    for i = 1, nEntries do
      local e = entries[i]
      if (e.sortName or ""):lower():find(X.search, 1, true) then
        keep[#keep + 1] = e
      else
        drop[#drop + 1] = e
      end
    end
    for i = 1, #keep do entries[i] = keep[i] end
    for i = 1, #drop do entries[#keep + i] = drop[i] end
    nEntries = #keep
  end
  -- Single-target buffs whose holder was found: only the holder's row may
  -- still offer it (when it's about to run out). Rows left with nothing to
  -- cast drop off; every entry object stays in entries[] exactly once, the
  -- dropped ones after nEntries, so the tail loop below pools them.
  if next(Single.holder) then
    local keep, drop = Single.keep, Single.drop
    wipe(keep); wipe(drop)
    for i = 1, nEntries do
      local e = entries[i]
      for key, holderUnit in pairs(Single.holder) do
        if e.unit ~= holderUnit then
          local m, spell = e.missing, Single.spell[key]
          for j = #m, 1, -1 do
            if m[j] == spell then table.remove(m, j) end
          end
        end
      end
      if e.missing[1] then keep[#keep + 1] = e else drop[#drop + 1] = e end
    end
    for i = 1, #keep do entries[i] = keep[i] end
    for i = 1, #drop do entries[#keep + i] = drop[i] end
    nEntries = #keep
  end
  for i = #entries, nEntries + 1, -1 do  -- return the unused tail to the pool
    entryPool[#entryPool + 1] = entries[i]
    entries[i] = nil
  end
  -- Coordination marks (1.5.0): a player another BuffRadar user just buffed
  -- sinks in the order (see EntryOrder) and shows a tag; a player who asked
  -- for a buff in chat is tagged while the request is fresh.
  local nowT = GetTime()
  for i = 1, nEntries do
    local e = entries[i]
    local h = X.handled[e.guid]
    e.handled = (h and nowT - h.t < 5 and h.key == X.KeyOfName(e.missing[1])) or nil
    local ak = X.asked[e.guid]
    e.asked = (ak and nowT - ak < 120) or nil
    e.drinking = X.drinkSet[e.guid] or nil
    -- Repeat-offender history (1.8.0): remember who was seen unbuffed
    -- this group session; the count lands when the group ends.
    if e.group and not e.pet and e.sortName and e.sortName ~= "" then
      X.offNow[e.sortName] = true
    end
    e.queued = nil  -- set after the sort, on the new top row only
    e.weapon = nil  -- set below, on your own row only (pooled entries)
  end
  -- Weapon watch (1.7.0): your own row carries the reminder tag.
  if db and db.weaponWatch and X.WeaponEnchantMissing() then
    for i = 1, nEntries do
      if entries[i].isSelf then entries[i].weapon = true end
    end
  end
  for guid, h in pairs(X.handled) do if nowT - h.t > 60 then X.handled[guid] = nil end end
  for key, p in pairs(X.peers) do if nowT - p.t >= 90 then X.peers[key] = nil end end
  for name, exp in pairs(X.cover) do if exp <= nowT then X.cover[name] = nil end end
  for guid, t in pairs(X.asked) do if nowT - t > 180 then X.asked[guid] = nil end end
  -- Assignments + buddy split (1.6.0): your assigned buffs float, buffs
  -- assigned to someone else sink; with buddy split on, the entries are
  -- shared between the BuffRadar users present by a stable hash of the
  -- player GUID, so every user works their own share of the list.
  local meFull = Ignore.UnitNames("player")
  local myKey = meFull and Ignore.Key(meFull)
  local users, myIdx = nil, 0
  if db and db.buddySplit and InGroup() and myKey then
    local keys = { myKey }
    for k, p in pairs(X.peers) do
      -- A covered (dead/AFK) buddy leaves the rotation: their share is
      -- redistributed among the users who are actually here (1.7.0).
      local away = false
      for cname, exp in pairs(X.cover) do
        if exp > nowT and X.SameUser(p.name, cname) then away = true break end
      end
      if nowT - p.t < 90 and k ~= myKey and not away then
        keys[#keys + 1] = k
      end
    end
    if #keys >= 2 then
      table_sort(keys)
      users = keys
      for i, k in ipairs(keys) do if k == myKey then myIdx = i break end end
    end
  end
  for i = 1, nEntries do
    local e = entries[i]
    local k = X.KeyOfName(e.missing[1])
    local who = k and X.assign[k]
    -- Holder identity goes through SameUser: assignments carry the
    -- name as typed (often short), my identity is the full name.
    -- An assignment held by a covered (dead/AFK) user counts as mine:
    -- that's the handoff doing its job (1.7.0).
    e.mine = nil
    if who then
      if meFull and X.SameUser(who, meFull) then
        e.mine = true
      else
        for cname, exp in pairs(X.cover) do
          if exp > nowT and X.SameUser(who, cname) then e.mine = true break end
        end
      end
    end
    e.theirs = (who and not e.mine) or nil
    -- Pin (1.7.0): one named player floats above every sort.
    e.pinned = (db and db.pinned ~= ""
      and X.SameUser(db.pinned, e.fullName or "")) or nil
    e.buddy = nil
    if users and not e.isSelf and not e.rezzed then
      local s = 0
      for j = 1, #e.guid do s = s + e.guid:byte(j) end
      if s % #users ~= myIdx - 1 then e.buddy = true end
    end
  end
  -- your buff priority: each row offers its buffs in your order (the
  -- first one is the click target and the first icon), and each row
  -- remembers its best position for the "need" sort tiebreak
  if X.prioDirty then X.RebuildPrio() end
  if X.prioIdx and next(X.prioIdx) then
    for i = 1, nEntries do
      local e = entries[i]
      local m = e.missing
      for a = 2, #m do
        local v, av = m[a], X.prioIdx[m[a]] or 999
        local bI = a - 1
        while bI >= 1 and (X.prioIdx[m[bI]] or 999) > av do
          m[bI + 1] = m[bI]
          bI = bI - 1
        end
        m[bI + 1] = v
      end
      e.prio1 = X.prioIdx[m[1]] or 999
    end
  end
  if nEntries > 1 then table_sort(entries, EntryOrder) end
  -- Cast queue highlight (1.6.0): right after one of your casts lands, the
  -- new top row is where the next cast should go.
  if nEntries > 0 and db and db.queueTag and nowT - (X.queueAt or 0) < 3 then
    entries[1].queued = true
  end
  return nEntries
end

-- Spell name -> buff key, rebuilt when the spellbook changes. Used to tell
-- "this buff vanished" (expired / dispelled / death) from "never had it".
function X.KeyOfName(name)
  if X.nameKeyStamp ~= bookCount then
    X.nameKeyStamp = bookCount
    X.nameKey = {}
    for _, b in ipairs(myBuffs) do X.nameKey[b.name] = b.key end
    for _, b in pairs(myBlessing) do X.nameKey[b.name] = "BLESSINGS" end
  end
  return X.nameKey[name]
end

X.ext = {}   -- extra slash commands, registered by Extras.lua: name -> function(rest)

-- Per-spec profiles (retail-style specialization API only; clients without
-- it simply never swap). Only the buff toggles and rebuff timings are
-- per-spec -- the rest of the settings are about the window, not the spec.
function X.SpecKey()
  if not _G.GetSpecialization then return nil end
  local ok, idx = pcall(_G.GetSpecialization)
  if ok and type(idx) == "number" and idx > 0 then return "s" .. idx end
  return nil
end


function X.SpecSwap()
  local key = X.SpecKey()
  if not key or X.spec == key then return end
  if X.spec then
    local p = db.specProfiles[X.spec] or {}
    p.enabled, p.rebuffPer = db.enabled, db.rebuffPer
    db.specProfiles[X.spec] = p
  end
  if db.scalePerSpec then
    if X.spec then db.specScales[X.spec] = db.scale end
    local sc = db.specScales[key]
    if sc and sc ~= db.scale then
      db.scale = sc
      if X.ApplyScaleNow then X.ApplyScaleNow() end
    end
  end
  X.spec = key
  local p = db.specProfiles[key]
  if p then
    db.enabled = p.enabled or {}
    db.rebuffPer = p.rebuffPer or {}
  else
    -- First visit to this spec: it inherits a copy of the current toggles,
    -- so later edits here can't leak into the previous spec's profile.
    local e, r = {}, {}
    for k, v in pairs(db.enabled) do e[k] = v end
    for k, v in pairs(db.rebuffPer) do r[k] = v end
    db.enabled, db.rebuffPer = e, r
  end
end

-- Missing-buff snapshot for the recap reports (Recaps.lua, file split Slice D):
-- rebuilds the unfiltered entry list and returns one text line per person
-- that pass(e) accepts, plus the person and cast counts.
function X.SnapshotMissing(pass)
  local keep = X.applyFilter
  X.applyFilter = false
  CollectEntries()
  X.applyFilter = keep
  local lines = {}
  local people, casts = 0, 0
  for i = 1, nEntries do
    local e = entries[i]
    if pass(e) then
      people = people + 1
      casts = casts + #e.missing
      lines[#lines + 1] = "  " .. (SafeString(e.name) or e.sortName or "?")
        .. ": " .. table.concat(e.missing, ", ")
    end
  end
  return lines, people, casts
end

-- READY_CHECK: a local summary (the group post is /br announce's job).
-- X.DeathRecap and X.WipeCheck live in Recaps.lua since Slice D.
function X.ReadyReport()
  local keep = X.applyFilter
  X.applyFilter = false
  CollectEntries()
  X.applyFilter = keep
  local people, casts = 0, 0
  for i = 1, nEntries do
    if entries[i].group and not entries[i].pet then people = people + 1; casts = casts + #entries[i].missing end
  end
  if people == 0 then
    Print("Ready check: everyone in your group is buffed.")
  else
    Print(string.format("Ready check: %d %s missing buffs (%d casts). /br announce posts the list.",
      people, people == 1 and "person is" or "people are", casts))
    -- Auto-post (1.7.0): the leader or an assistant can have the summary
    -- posted to group chat too, so the group sees it without asking.
    if db.readyPost and X.AmLead() then
      local channel = InRaid() and "RAID" or (InGroup() and "PARTY" or nil)
      if channel and _G.SendChatMessage then
        _G.SendChatMessage(string.format(
          "BuffRadar ready check: %d %s missing buffs (%d casts).",
          people, people == 1 and "person is" or "people are", casts), channel)
      end
    end
  end
end

-- Settings export / import: one copyable string. Covers the window look,
-- behavior toggles, buff toggles, rebuff timings and both ignore sets --
-- not positions, cast counts or stats (those belong to one machine / char).
X.EXPORT_KEYS = { "locked", "includeSelf", "avoidPvP", "autoHide", "rebuff", "scale",
  "width", "cfgScale", "castMethod", "clickReg", "bgAlpha", "showTitle", "showBorder",
  "playSound", "showCounter", "groupOnly", "pauseInCities", "groupCast", "groupCastMin",
  "sortMode", "alertSound", "alertSounds", "buffPrio", "clickThrough", "muteInInstance", "showMinimap", "lowMana",
  "sync", "requests", "joinDigest", "roleFilter", "showStrip", "idleFade",
  "pill", "queueTag", "consumables", "buddySplit", "readyPost", "weaponWatch", "enterFlash",
  "scanThrottle", "growUp", "theme", "findBox", "durationBars", "raidMarkers",
  "focusWatch", "pets", "auraWatch", "worldWatch", "drinkWatch", "twoCol",
  "deathRecap", "wipeReport", "rowGap", "iconSize",
  "tooltipLevel", "viewMode", "classColors", "showRealm", "nameTrim",
  "scalePerSpec", "gripSnap", "tagSymbols", "reduceMotion", "rangeWatch", "assumeRange",
  "fastAura", "modClick", "pullFlash", "fallSound" }

local function Esc(v) return (tostring(v):gsub("%%", "%%25"):gsub(";", "%%3B"):gsub("=", "%%3D")) end
local function Unesc(v) return (v:gsub("%%3D", "="):gsub("%%3B", ";"):gsub("%%25", "%%")) end

-- X.Export, X.Import, plan strings, profiles and presets live in Profiles.lua
-- since Slice E (Esc/Unesc stay here: the settings window takes Esc by value).

-- /br announce: post the group's missing buffs to party/raid chat (or
-- print them locally when solo). Lives here, not in HandleSlash, to keep
-- that function's upvalue count down.
function X.Announce()
  local keep = X.applyFilter
  X.applyFilter = false
  CollectEntries()
  X.applyFilter = keep
  local per, order = {}, {}
  for i = 1, nEntries do
    local e = entries[i]
    if e.group and not e.pet then
      for _, spell in ipairs(e.missing) do
        if not per[spell] then per[spell] = {}; order[#order + 1] = spell end
        local nm = SafeString(e.name) or e.sortName
        per[spell][#per[spell] + 1] = (nm and nm ~= "") and nm or "?"
      end
    end
  end
  if #order == 0 then
    Print("Everyone in your group is buffed -- nothing to announce.")
    return
  end
  local segs = {}
  for _, spell in ipairs(order) do
    local names = per[spell]
    local shownNames = {}
    for i = 1, math_min(3, #names) do shownNames[i] = names[i] end
    local seg = spell .. ": " .. table.concat(shownNames, ", ")
    if #names > 3 then seg = seg .. " +" .. (#names - 3) end
    segs[#segs + 1] = seg
  end
  local text = "BuffRadar -- missing buffs: " .. table.concat(segs, " · ")
  local channel = InRaid() and "RAID" or (InGroup() and "PARTY" or nil)
  if channel and _G.SendChatMessage then
    _G.SendChatMessage(text, channel)
    Print("Announced missing buffs to " .. channel:lower() .. " chat.")
  else
    Print(text)
  end
end

---------------------------------------------------------------------------
-- Rank selection: highest rank you know that the target can receive.
-- Classic rule: a buff fails if its rank's required level is more than 10
-- above the target's level. If the client can't tell us spell levels, we
-- simply use the highest rank.
-- (Rank helpers are block-scoped; only Bind is used outside: 200-local limit.)
---------------------------------------------------------------------------
local Bind
do
local function LevelLearned(id)
  if not id then return nil end
  local fn = (C_Spell and C_Spell.GetSpellLevelLearned) or GetSpellLevelLearned
  if not fn then return nil end
  local lvl = X.ReadUnitNumber(fn, id)
  if lvl and lvl > 0 then return lvl end
end

local function PickRank(name, unit)
  local list = ranks[name]
  if not list or #list == 0 then return nil end
  local targetLevel = unit and X.ReadUnitNumber(UnitLevel, unit) or 0
  local pick = list[#list]
  if targetLevel and targetLevel > 0 then
    for k = #list, 1, -1 do
      local req = LevelLearned(list[k].id)
      if not req or req - 10 <= targetLevel then pick = list[k]; break end
      pick = list[k]  -- keep falling back toward rank 1
    end
  end
  return pick
end

local function CastText(name, unit)
  local pick = PickRank(name, unit)
  if pick and pick.sub and pick.sub ~= "" and pick.rank > 0 then
    return name .. "(" .. pick.sub .. ")"
  end
  return name
end

-- Group version of a castable buff, for modifier clicks (1.14.0, Brief 3):
-- the def's groupCast (Prayer of Fortitude, Gift of the Wild, ...) or a
-- blessing's greater version; nil when the buff has none.
local function GroupSpellFor(spell)
  if not spell then return nil end
  for _, d in ipairs(X.BUFF_DEFS or {}) do
    if d.groupCast then
      local cn = d.id and SpellName(d.id, d.name) or d.name
      if cn == spell then return SpellName(d.groupCast[1], d.groupCast[2]) end
    end
  end
  for _, b in pairs(X.BLESSINGS or {}) do
    if b.greater and SpellName(b.id, b.name) == spell then
      return SpellName(b.greater[1], b.greater[2])
    end
  end
  local cg = db and db.customGroup and db.customGroup[spell]
  if cg then return cg end
  return nil
end
X.GroupSpellFor = GroupSpellFor

function Bind(btn, unit, spell, isSelf)
  local pick = PickRank(spell, unit)
  local gspell = (db.modClick and CLASSIC_FEATURES) and GroupSpellFor(spell) or nil
  btn:SetAttribute("shift-type1", nil)
  btn:SetAttribute("shift-spell1", nil)
  btn:SetAttribute("shift-unit1", nil)
  btn:SetAttribute("shift-macrotext1", nil)
  local method = db.castMethod
  if method == "target" then
    -- Self-casts go straight to "player", and party/raid members are cast on
    -- by their group unit (party2, raid14, ...), so your target never changes.
    -- Anyone else -- nameplate, target or mouseover units, which can point at
    -- a different player by the time you click -- uses BuffYou's approach
    -- (MIT, by datdata): target them by exact name, cast the buff by plain
    -- name (your highest rank), then restore your previous target.
    -- Group units are rebound on every roster change (GROUP_ROSTER_UPDATE
    -- refreshes the list); only a roster change during combat, while the
    -- list is frozen, can leave a row pointing at whoever took that slot.
    btn:SetAttribute("type", nil)
    btn:SetAttribute("unit", nil)
    btn:SetAttribute("spell", nil)
    btn:SetAttribute("macrotext", nil)
    if isSelf then
      btn:SetAttribute("type", "spell")
      btn:SetAttribute("spell", spell)
      btn:SetAttribute("unit", "player")
      if gspell then
        btn:SetAttribute("shift-type1", "spell")
        btn:SetAttribute("shift-spell1", gspell)
        btn:SetAttribute("shift-unit1", "player")
      end
      return
    end
    if unit:match("^party%d+$") or unit:match("^raid%d+$") then
      btn:SetAttribute("type", "spell")
      btn:SetAttribute("spell", spell)
      btn:SetAttribute("unit", unit)
      if gspell then
        btn:SetAttribute("shift-type1", "spell")
        btn:SetAttribute("shift-spell1", gspell)
        btn:SetAttribute("shift-unit1", unit)
      end
      return
    end
    local ok, name = pcall(GetUnitName or UnitName, unit, true)
    name = ok and SafeString(name) or nil  -- a protected name can't build a macro: no cast
    if name and name ~= "" then
      btn:SetAttribute("type", "macro")
      btn:SetAttribute("macrotext", "/targetexact " .. name .. "\n/cast " .. spell .. "\n/targetlasttarget")
      if gspell then
        btn:SetAttribute("shift-type1", "macro")
        btn:SetAttribute("shift-macrotext1", "/targetexact " .. name .. "\n/cast " .. gspell .. "\n/targetlasttarget")
      end
    end
  elseif method == "id" and pick and pick.id then
    btn:SetAttribute("type", "spell")
    btn:SetAttribute("unit", unit)
    btn:SetAttribute("spell", pick.id)
    btn:SetAttribute("macrotext", nil)
    if gspell then
      local gpick = PickRank(gspell, unit)
      btn:SetAttribute("shift-type1", "spell")
      btn:SetAttribute("shift-unit1", unit)
      btn:SetAttribute("shift-spell1", (gpick and gpick.id) or gspell)
    end
  else
    local text = (method == "rank") and CastText(spell, unit) or spell
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("unit", nil)
    btn:SetAttribute("spell", nil)
    btn:SetAttribute("macrotext", "/cast [@" .. unit .. ",help,nodead] " .. text)
    if gspell then
      local gtext = (method == "rank") and CastText(gspell, unit) or gspell
      btn:SetAttribute("shift-type1", "macro")
      btn:SetAttribute("shift-macrotext1", "/cast [@" .. unit .. ",help,nodead] " .. gtext)
    end
  end
end
X.PickRank, X.CastText = PickRank, CastText  -- for BindGroup (1.15.0), outside the block
end -- Bind block

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
local frame, title, countText, emptyText, overflowText, combatText, nextBtn, coverText
local OpenConfig, RefreshConfig, MakeMacro  -- defined further down
local QueueRefresh  -- assigned to the event coalescer further down
local BuildMinimapButton, RefreshMinimapButton  -- assigned in the minimap section further down
local footerText
-- (X.sessionCasts, X.pendingCast, the double-buffered listed sets and
-- X.recentlyGone live on X since 1.4.0 -- see the enhancement state block.)
local lastSoundAt = 0

local function InInstanceNow()
  if IsInInstance then
    local ok, inInst, t = pcall(IsInInstance)
    if ok and inInst then return t end
  end
  return nil
end

local function PlayAlert(kind)
  if not db or not db.playSound then return end
  -- a sound chosen for this kind of alert wins; otherwise the main choice
  local choice = (kind and db.alertSounds and db.alertSounds[kind]) or db.alertSound
  if choice == "none" then return end
  if db.muteInInstance and InInstanceNow() then return end
  if choice == "system" and PlaySound then
    local id = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959
    if pcall(PlaySound, id, "Master") then return end
  end
  if PlaySoundFile then pcall(PlaySoundFile, SOUND_FILE, "Master") end
end

local function UpdateCounter()
  if not footerText then return end
  local show = db.showCounter and true or false
  if (footerText:IsShown() and true or false) ~= show then footerText:SetShown(show) end
  local total = db.castsTotal or 0
  -- The counter shares its row with the settings gear and stops short of the
  -- resize grip, so a narrow window used to cut it to "39 all-t...". Width is
  -- part of the cache key so a resize re-fits the line, not just a new cast.
  local room = footerText:GetWidth() or 0
  if X.sessionCasts ~= X.lastCounterSession or total ~= X.lastCounterTotal
     or room ~= X.lastCounterRoom then
    X.lastCounterSession, X.lastCounterTotal, X.lastCounterRoom = X.sessionCasts, total, room
    footerText:SetText(string_format(L["Casts: |cffffffff%d|r this session  ·  |cffffffff%d|r all-time"],
      X.sessionCasts, total))
    if room > 0 and footerText:GetStringWidth() > room then
      footerText:SetText(string_format(L["Casts: |cffffffff%d|r / |cffffffff%d|r"],
        X.sessionCasts, total))
    end
  end
end

local function NotePendingCast(entry, spellOverride)
  if entry and entry.missing and entry.missing[1] then
    local spell = spellOverride or entry.missing[1]
    X.pendingCast = { spell = spell, time = GetTime(),
                      guid = entry.guid, key = X.KeyOfName(spell),
                      who = entry.sortName }
  end
end

function X.SkipPendingCast()
  local pending = X.pendingCast
  if not pending or not pending.guid or GetTime() - pending.time > 4 then return false end
  X.failedTargets[pending.guid] = GetTime() + 30
  X.pendingCast = nil
  return true
end

-- These errors mean the saved target is no longer castable right now.
-- Skip only target/range failures; mana, cooldown, and other errors stay pending.
X.castTargetFailureGlobals = {
  "SPELL_FAILED_LINE_OF_SIGHT", "ERR_SPELL_FAILED_LINE_OF_SIGHT",
  "SPELL_FAILED_OUT_OF_RANGE", "ERR_OUT_OF_RANGE", "ERR_SPELL_OUT_OF_RANGE",
  "SPELL_FAILED_BAD_TARGETS", "ERR_INVALID_TARGET", "ERR_BADATTACKTARGET",
  "SPELL_FAILED_TARGETS_DEAD", "ERR_TARGET_DEAD",
}
function X.IsTargetCastFailure(message)
  if type(message) ~= "string" then return false end
  local lower = message:lower()
  if lower:find("line of sight", 1, true) or lower:find("out of range", 1, true)
    or lower:find("too far away", 1, true) or lower:find("invalid target", 1, true)
    or lower:find("bad target", 1, true) or lower:find("target is dead", 1, true)
    or lower:find("target no longer exists", 1, true) then return true end
  for _, key in ipairs(X.castTargetFailureGlobals) do
    local token = _G[key]
    if type(token) == "string" and token ~= "" and message:find(token, 1, true) then return true end
  end
  return false
end

---------------------------------------------------------------------------
-- Coordination (1.5.0): cast sync between BuffRadar users, chat buff
-- requests, and a one-line summary when you join a group.
---------------------------------------------------------------------------
function X.InitSync()
  if X.syncReg then return end
  X.syncReg = true
  if _G.C_ChatInfo and _G.C_ChatInfo.RegisterAddonMessagePrefix then
    pcall(_G.C_ChatInfo.RegisterAddonMessagePrefix, "BuffRadar")
  elseif _G.RegisterAddonMessagePrefix then
    pcall(_G.RegisterAddonMessagePrefix, "BuffRadar")
  end
end

local function SyncChannel()
  if InRaid() then return "RAID" end
  if InGroup() then return "PARTY" end
end

-- One broadcast to the group's BuffRadar users (party or raid channel).
function X.Broadcast(msg)
  if not db or not db.sync then return end
  local channel = SyncChannel()
  if not channel then return end
  if _G.C_ChatInfo and _G.C_ChatInfo.SendAddonMessage then
    pcall(_G.C_ChatInfo.SendAddonMessage, "BuffRadar", msg, channel)
  elseif _G.SendAddonMessage then
    pcall(_G.SendAddonMessage, "BuffRadar", msg, channel)
  end
end

-- Tell the other BuffRadar users in the group "I just cast KEY on GUID",
-- so their lists sink that player instead of double-casting the same buff.
function X.SyncSend(key, guid)
  X.Broadcast("CAST;" .. key .. ";" .. guid)
end

-- Cover-me handoff (1.7.0): while you're dead or AFK, tell the other
-- BuffRadar users so your duties pass to them; tell them when you're
-- back. Broadcasts on state change, and re-sends every couple of
-- minutes while you're still away so their cover doesn't lapse.
function X.SendCover()
  if not db then return end
  local me = Ignore.UnitNames("player")
  if not me then return end
  local covered = (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") and true)
    or (_G.UnitIsAFK and _G.UnitIsAFK("player") and true) or false
  if X.myCover == covered and not covered then return end
  if X.myCover == covered and GetTime() - (X.coverSentAt or 0) < 120 then return end
  X.myCover = covered
  X.coverSentAt = GetTime()
  X.Broadcast((covered and "COVER;" or "BACK;") .. me)
end

-- Do two player names refer to the same user? Names ride the wire as
-- typed (often the bare short name), while identity checks use full
-- "Name-Realm" strings. Same when the full names match, or the short
-- names match and neither side names a conflicting realm — the same
-- rule the ignore list has always used for bare names.
function X.SameUser(a, b)
  if not a or not b then return false end
  if Ignore.Key(a) == Ignore.Key(b) then return true end
  local as, ar = a:match("^([^%-]+)%-?(.*)$")
  local bs, br = b:match("^([^%-]+)%-?(.*)$")
  if Ignore.Key(as or "") ~= Ignore.Key(bs or "") then return false end
  if ar and ar ~= "" and br and br ~= ""
     and Ignore.Key(ar) ~= Ignore.Key(br) then return false end
  return true
end

do
  local supportedKeys = { BLESSINGS = true }
  for _, def in ipairs(BUFF_DEFS) do supportedKeys[def.key] = true end
  for _, def in ipairs(X.AURA_DEFS or {}) do supportedKeys[def.key] = true end

  local function ReadText(value)
    return type(value) == "string" and Readable(value)
  end

  local function ValidName(name)
    return ReadText(name) and #name <= 128 and name:find("%S") and not name:find("[%c;|]")
  end

  local function ValidBuffKey(key)
    return supportedKeys[key] or (#key <= 16 and key:match("^CUSTOM[1-9]%d*$"))
  end

  -- A refused realm is different from a readable empty realm, which means local.
  -- The ignore list can fall back to a short name, but roster authorization
  -- must never fill in a realm the game withheld.
  local function RosterNames(unit)
    local ok, name, realm = pcall(UnitFullName or UnitName, unit)
    if not ok or not ValidName(name) then return end
    if type(realm) ~= "nil" and (not ReadText(realm) or (realm ~= "" and not ValidName(realm))) then return end
    if not realm or realm == "" then
      if GetNormalizedRealmName then
        local realmOK, localRealm = pcall(GetNormalizedRealmName)
        if realmOK and ValidName(localRealm) then realm = localRealm end
      end
    end
    return realm and realm ~= "" and name .. "-" .. realm:gsub("%s+", "") or name, name
  end

  -- Match a full name exactly, or accept a bare name only if it is unique
  -- across the readable roster. The raid list already includes the player.
  function X.SenderUnit(sender)
    if not ValidName(sender) then return end
    local key = Ignore.Key(sender)
    local qualified = key:find("-", 1, true)
    local raid = InRaid()
    local roster = raid and RAID or PARTY
    local found, canonical
    for i = raid and 1 or 0, #roster do
      local unit = roster[i] or "player"
      if X.ReadUnitBool(UnitExists, unit) == true then
        local full, short = RosterNames(unit)
        if not full then
          if not qualified then return end
        elseif key == Ignore.Key(qualified and full or short) then
          if found then return end
          found, canonical = unit, full
        end
      end
    end
    return found, canonical
  end

  local function HasPlanRole(unit, forBless)
    if X.ReadUnitBool(_G.UnitIsGroupLeader, unit) == true
      or X.ReadUnitBool(_G.UnitIsGroupAssistant, unit) == true then return true end
    local idx = unit:match("^raid(%d+)$")
    if idx and GetRaidRosterInfo then
      local ok, _, rank = pcall(GetRaidRosterInfo, tonumber(idx))
      if ok and type(rank) == "number" and Readable(rank) and (rank == 1 or rank == 2) then
        return true
      end
    end
    if forBless then
      local ok, _, class = pcall(UnitClass, unit)
      return ok and ReadText(class) and class == "PALADIN"
    end
    return false
  end

  function X.SenderTrusted(sender, forBless)
    local unit = X.SenderUnit(sender)
    return unit ~= nil and HasPlanRole(unit, forBless)
  end

  function X.AmLead()
    if HasPlanRole("player") then return true end
    if InRaid() then
      for i = 1, #RAID do
        if X.IsSelf(RAID[i]) == true then return HasPlanRole(RAID[i]) end
      end
    end
    return false
  end

  function X.PruneSyncRoster()
    if not next(X.peers) and not next(X.cover) then return end
    local roster = InRaid() and RAID or PARTY
    local present = {}
    for _, unit in ipairs(roster) do
      if X.ReadUnitBool(UnitExists, unit) == true then
        local full = RosterNames(unit)
        if full then present[Ignore.Key(full)] = true end
      end
    end
    for key in pairs(X.peers) do
      if not present[key] then X.peers[key] = nil end
    end
    for name in pairs(X.cover) do
      if not present[Ignore.Key(name)] then X.cover[name] = nil end
    end
  end

  local function RememberCast(guid, key, now)
    if not X.handled[guid] then
      local count, oldestGuid, oldestTime = 0, nil, now
      for seenGuid, handled in pairs(X.handled) do
        count = count + 1
        if not oldestGuid or handled.t < oldestTime then
          oldestGuid, oldestTime = seenGuid, handled.t
        end
      end
      if count >= 128 then X.handled[oldestGuid] = nil end
    end
    X.handled[guid] = { key = key, t = now }
  end

  function X.OnAddonMsg(prefix, msg, channel, sender)
    if not db or not db.sync or not ReadText(prefix) or prefix ~= "BuffRadar" then return end
    if not ReadText(channel) or channel ~= SyncChannel() then return end
    if not ReadText(msg) or #msg > 255 then return end
    local kind, first, rest = msg:match("^([A-Z]+);([^;]+)(.*)$")
    if not kind then return end
    local unit, name = X.SenderUnit(sender)
    if not unit then return end
    local me = RosterNames("player")
    local senderKey = Ignore.Key(name)
    if unit == "player" or (me and senderKey == Ignore.Key(me)) then return end
    if channel == "RAID" then
      local isSelf = X.IsSelf(unit)
      if isSelf == true or (isSelf == nil and not me) then return end
    end

    local now = GetTime()
    if kind == "CAST" then
      local guid = rest:match("^;([%a]+%-%w[%w%-]*)$")
      if not guid or #guid > 85 or not ValidBuffKey(first) then return end
      RememberCast(guid, first, now)
    elseif kind == "ASSIGN" then
      local holder = rest:match("^;([^;]+)$")
      if not ValidBuffKey(first) or not ValidName(holder) or not HasPlanRole(unit) then return end
      if holder:lower() == "none" then X.assign[first] = nil else X.assign[first] = holder end
    elseif kind == "BLESS" then
      local key, holder = rest:match("^;([%w_]+);([^;]+)$")
      if not key or not X.BLESSING_CLASSES[first] or not ValidName(holder)
        or (key ~= "NONE" and not BLESSINGS[key]) or not HasPlanRole(unit, true) then return end
      if key == "NONE" or holder == "none" then
        X.blessPlan[first] = nil
      else
        X.blessPlan[first] = { key = key, name = holder, mine = me ~= nil and X.SameUser(holder, me) }
      end
    elseif kind == "COVER" or kind == "BACK" or kind == "HELLO" or kind == "HERE" then
      if rest ~= "" or not ValidName(first) or not X.SameUser(first, name) then return end
      if kind == "COVER" then X.cover[name] = now + 300 end
      if kind == "BACK" then X.cover[name] = nil end
    else
      return
    end

    local peer = X.peers[senderKey] or {}
    peer.t, peer.name = now, name
    X.peers[senderKey] = peer
    if kind == "HELLO" and me and (not peer.replyAt or now - peer.replyAt >= 10) then
      peer.replyAt = now
      X.Broadcast("HERE;" .. me)
    end
    if QueueRefresh then QueueRefresh() end
  end
end

-- A whisper or a nearby "buff ..." marks that player's row while it is up.
function X.OnChatAsk(text, author)
  if not db or not db.requests then return end
  if type(text) ~= "string" or type(author) ~= "string" then return end
  if not text:lower():find("buff", 1, true) then return end
  local short = author:match("^[^%-]+") or author
  local ka, ks = Ignore.Key(author), Ignore.Key(short)
  for i = 1, nEntries do
    local e = entries[i]
    if e and (Ignore.Key(e.fullName or "") == ka or Ignore.Key(e.sortName or "") == ks) then
      if (not X.asked[e.guid] or GetTime() - X.asked[e.guid] > 30)
         and db.playSound and GetTime() - lastSoundAt > 1 then
        lastSoundAt = GetTime()
        PlayAlert("ask")
      end
      X.asked[e.guid] = GetTime()
      if QueueRefresh then QueueRefresh() end
      return
    end
  end
end

-- Does one of my equipped weapons lack a temporary enchant (a shaman
-- imbue, a rogue poison, an oil or a sharpening stone)? (1.7.0)
-- GetWeaponEnchantInfo is the game's own answer; a hand only counts
-- when a weapon is actually equipped in it.
-- Per-buff context (1.8.0): a buff can be limited to raids or to
-- instances (dungeons, raids, battlegrounds) and is then simply not
-- offered anywhere else. Set with /br context KEY raid|instance|always.
-- On Forever, Shadow Protection ships with the instance limit as its
-- default (the resistance-context rule) until the user changes it.
function X.ContextOK(key)
  local c = db and db.buffContext and db.buffContext[key]
  if not c then return true end
  if c == "raid" then return InRaid() end
  if c == "instance" then return InInstanceNow() ~= nil end
  return true
end

function X.WeaponEnchantMissing()
  local fn = _G.GetWeaponEnchantInfo
  if not fn then return false end
  local ok, hasMH, _, _, _, hasOH = pcall(fn)
  if not ok then return false end
  local function equipped(slot)
    if not _G.GetInventoryItemID then return true end
    local okI, id = pcall(_G.GetInventoryItemID, "player", slot)
    return okI and id ~= nil
  end
  if not hasMH and equipped(16) then return true end
  if not hasOH and equipped(17) then return true end
  return false
end

-- Instance-entry reminder (1.7.0): stepping into a dungeon, raid or
-- battleground with buffs still missing gets one clear line, once per
-- entry — the run-start counterpart of the join digest.
function X.InstanceCheck()
  if not db then return end
  local ctx = X.Context()
  local inside = ctx == "dungeon" or ctx == "raid" or ctx == "pvp"
  if inside and not X.wasInside and db.enterFlash and InGroup() and hasAnyBuff then
    local keep = X.applyFilter
    X.applyFilter = false
    CollectEntries()
    X.applyFilter = keep
    local people, casts = 0, 0
    for i = 1, nEntries do
      if entries[i].group and not entries[i].pet then
        people = people + 1; casts = casts + #entries[i].missing
      end
    end
    if people > 0 then
      Print(string.format("Entered the %s with buffs missing: %d %s still need buffs (%d casts).",
        ctx == "dungeon" and "dungeon" or (ctx == "raid" and "raid" or "battleground"),
        people, people == 1 and "person" or "people", casts))
    end
  end
  X.wasInside = inside
end

-- One line in chat: how much buffing the group (or the run) still needs.
-- Counts everyone, ignoring the window's role filter.
function X.JoinDigest(why)
  if not db or not InGroup() then return end
  local keep = X.applyFilter
  X.applyFilter = false
  CollectEntries()
  X.applyFilter = keep
  local people, casts = 0, 0
  for i = 1, nEntries do
    if entries[i].group and not entries[i].pet then people = people + 1; casts = casts + #entries[i].missing end
  end
  if people == 0 then return end
  Print(string.format("%s: %d %s missing buffs (%d casts).",
    why == "run" and "Run starting" or "Joined a group",
    people, people == 1 and "person is" or "people are", casts))
end

-- Roster events: only the step from solo to grouped triggers the join
-- summary, not every roster shuffle afterwards.
function X.OnRoster()
  local g = InGroup()
  if db then X.SendCover() end  -- roster changes refresh a live cover (1.7.0)
  if X.inGroupPrev == false and g and db and db.joinDigest and hasAnyBuff then
    if C_Timer and C_Timer.After then
      C_Timer.After(1.5, function() X.JoinDigest("join") end)
    else
      X.JoinDigest("join")
    end
  end
  -- Presence (1.6.0): say hello (throttled) so other users know a buddy is
  -- here; assignments and plans belong to the group, so they end with it.
  if g and db and db.sync and GetTime() - (X.helloAt or 0) > 10 then
    X.helloAt = GetTime()
    local me = Ignore.UnitNames("player")
    if me then X.Broadcast("HELLO;" .. me) end
  end
  if g then
    X.PruneSyncRoster()
  else
    wipe(X.assign)
    wipe(X.blessPlan)
    wipe(X.peers)
    wipe(X.cover)
    wipe(X.handled)
    X.upTotal, X.upFull = 0, 0  -- the run is over (1.6.0)
    -- Repeat-offender history (1.8.0): the session that just ended
    -- counts once for everyone who was seen unbuffed during it.
    if db then
      for name in pairs(X.offNow) do
        db.offenders[name] = (db.offenders[name] or 0) + 1
      end
      local orows = {}
      for nm, c in pairs(db.offenders) do orows[#orows + 1] = { nm = nm, c = c } end
      if #orows > 50 then  -- keep the worst 50 only
        table_sort(orows, function(a, b) return a.c > b.c end)
        for i = 51, #orows do db.offenders[orows[i].nm] = nil end
      end
    end
    wipe(X.offNow)
  end
  X.inGroupPrev = g
end

local rows = {}
local built = false

local function ClassColor(class)
  local c = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class])
         or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
  if c then return c.r, c.g, c.b end
  return 1, 1, 1
end

-- The window is ALWAYS anchored by its top-left corner, and only by that
-- corner. Refresh() changes the frame's height as names are added and
-- removed; with any other anchor (the old default was LEFT, and a drag
-- could leave CENTER or BOTTOM) SetHeight grows/shrinks the frame around
-- that point, so the top edge -- and the whole window -- jumps up and down
-- as the list changes. Anchored at TOPLEFT, the top edge stays exactly
-- where the user put it and the list grows/shrinks downward only.
-- Saved positions are therefore stored as a TOPLEFT anchor:
--   { "TOPLEFT", <UIParent point>, x, y }
-- (Same fix as Forever edition 1.2.4; the two editions share the
-- BuffRadarDB saved variable format, so positions saved by either
-- edition's fixed version load unchanged in the other.)
local function SavePosition()
  if db.growUp then
    -- Grow-up form: the bottom-left corner is the anchor (see X.ApplyAnchor).
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if left and bottom then
      frame:ClearAllPoints()
      frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
      db.point = { "BOTTOMLEFT", "BOTTOMLEFT", left, bottom }
      if db.charPoint then
        local k = X.CharKey()
        if k then db.pointByChar[k] = db.point end
      end
      return
    end
  end
  local left, top = frame:GetLeft(), frame:GetTop()
  if left and top then
    -- Store the top-left corner in screen coordinates (origin bottom-left;
    -- GetLeft/GetTop and SetPoint offsets use the same coordinate system
    -- for this frame). Re-anchor in that form right away, too:
    -- StopMovingOrSizing can leave the frame anchored by whatever point
    -- the drag used, which would bring the jumping back until next reload.
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    db.point = { "TOPLEFT", "BOTTOMLEFT", left, top }
  else
    -- Position not measurable yet (frame never laid out): keep whatever
    -- anchor the drag left rather than saving nothing. RestorePosition
    -- converts a non-TOPLEFT anchor like this one on the next load.
    local p, _, rp, x, y = frame:GetPoint()
    if p then db.point = { p, rp, x, y } end
  end
  if db.charPoint then
    local k = X.CharKey()
    if k and db.point then db.pointByChar[k] = db.point end
  end
end

-- Where a named anchor point sits inside a frame, as fractions of its
-- width (from the left edge) and height (from the bottom edge).
local POINT_FRACTION = {
  TOPLEFT = { 0, 1 },     TOP = { 0.5, 1 },   TOPRIGHT = { 1, 1 },
  LEFT = { 0, 0.5 },      CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
  BOTTOMLEFT = { 0, 0 },  BOTTOM = { 0.5, 0 },   BOTTOMRIGHT = { 1, 0 },
}

-- Forget the saved window spot (shared and per-character), so the next
-- RestorePosition lands on the default anchor.
function X.ClearSavedPoint()
  db.point = nil
  if db.charPoint then
    local k = X.CharKey()
    if k then db.pointByChar[k] = nil end
  end
end

local function RestorePosition()
  if db.charPoint then
    local k = X.CharKey()
    if k and db.pointByChar[k] then db.point = db.pointByChar[k] end
  end
  frame:ClearAllPoints()
  -- Rescue (1.5.0): a saved spot can end up off-screen after a monitor or
  -- resolution change. Saved points anchor TOPLEFT to the screen's
  -- BOTTOMLEFT, so x is the left edge and y the top edge from the bottom;
  -- if the window would be (mostly) unreachable, forget the spot instead
  -- of restoring it blind.
  if db.point and db.point[1] == "TOPLEFT" and db.point[2] == "BOTTOMLEFT"
     and _G.GetScreenWidth and _G.GetScreenHeight then
    local okW, sw = pcall(_G.GetScreenWidth)
    local okH, sh = pcall(_G.GetScreenHeight)
    local x, y = db.point[3], db.point[4]
    if okW and okH and type(sw) == "number" and type(sh) == "number"
       and (x < 30 - frame:GetWidth() or x > sw - 50 or y < 50 or y > sh) then
      X.ClearSavedPoint()
    end
  end
  if db.growUp and db.point and db.point[1] == "BOTTOMLEFT" then
    -- Grow-up form (1.8.0): restore the bottom anchor as saved.
    frame:SetPoint("BOTTOMLEFT", UIParent, db.point[2], db.point[3], db.point[4])
    return
  end
  if not db.point then
    -- Default spot, in top-left form: the pre-1.3.1 default anchored the
    -- frame's LEFT point at (40, 80) from the screen's left edge; at the
    -- height the frame is built with, that puts the top-left corner half
    -- a build-height above it.
    frame:SetPoint("TOPLEFT", UIParent, "LEFT", 40, 80 + (HEADER_H + 30) / 2)
    return
  end
  local p, rp, x, y = db.point[1], db.point[2], db.point[3], db.point[4]
  local f = POINT_FRACTION[p]
  if p == "TOPLEFT" or not f then
    frame:SetPoint(p, UIParent, rp, x, y)
    return
  end
  -- Legacy save (1.3.0 and earlier stored the drag anchor verbatim, e.g.
  -- LEFT or CENTER): convert it to a TOPLEFT anchor against the same
  -- point of UIParent. The top-left corner sits (-fx * W, (1 - fy) * H)
  -- from the old anchor point, so with the frame's current size the
  -- window does not move at all in this conversion -- it just stops
  -- moving afterwards, when its height starts changing. The height at
  -- drag time was never saved, so this preserves the position as
  -- restored now, not necessarily the exact top edge seen while dragging.
  local w, h = frame:GetWidth(), frame:GetHeight()
  db.point = { "TOPLEFT", rp, x - f[1] * w, y + (1 - f[2]) * h }
  frame:SetPoint("TOPLEFT", UIParent, rp, db.point[3], db.point[4])
end

local function Row_OnEnter(self)
  if not self.entry then return end
  local e = self.entry
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  if UnitExists(e.unit) and SafeString(UnitGUID(e.unit)) == e.guid then
    GameTooltip:SetUnit(e.unit)
  else
    GameTooltip:AddLine(e.name)
  end
  GameTooltip:AddLine(" ")
  if e.outOfRange then
    GameTooltip:AddLine(L["Out of range — move closer to cast:"], 1, 0.5, 0.3)
    GameTooltip:AddLine("|cff00ff00" .. e.missing[1] .. "|r")
  else
    GameTooltip:AddLine(string_format(L["Click to cast: %s"], "|cff00ff00" .. e.missing[1] .. "|r"))
    if db.modClick and CLASSIC_FEATURES then
      local gs = X.GroupSpellFor(e.missing[1])
      if gs then
        GameTooltip:AddLine(string_format(L["Shift-click to cast: %s"], "|cff00ff00" .. gs .. "|r"))
      end
    end
  end
  if e.groupCast then
    GameTooltip:AddLine(L["Group version — one cast buffs the whole party."], 0.4, 0.8, 1)
  end
  -- Tooltip detail (1.10.0): minimal stops at the cast line.
  if db.tooltipLevel == "minimal" then GameTooltip:Show() return end
  GameTooltip:AddLine(L["Right-click to ignore this player."], 0.6, 0.6, 0.6)
  GameTooltip:AddLine(L["Shift-right-click to ignore for this session only."], 0.6, 0.6, 0.6)
  if #e.missing > 1 then
    local rest = {}
    for i = 2, #e.missing do rest[#rest + 1] = e.missing[i] end
    GameTooltip:AddLine(string_format(L["Still needs: %s"], table.concat(rest, ", ")), 0.8, 0.8, 0.8, true)
  end
  -- The full picture (1.7.0): buffs this player HAS from your set, with
  -- the time left on each, soonest first — so a hover answers "what do
  -- they still need, and what's about to run out?" in one look.
  if UnitExists(e.unit) then
    local missSet = {}
    for _, m in ipairs(e.missing) do missSet[m] = true end
    local have, seenHave = {}, {}
    for _, def in ipairs(myBuffs) do
      local nm = def.name
      if nm and not seenHave[nm] and not missSet[nm] then
        seenHave[nm] = true
        local left = X.Remaining(e.unit, nm)
        if left and left < math_huge and left > 0 then
          have[#have + 1] = { name = nm, left = left }
        end
      end
    end
    table_sort(have, function(x, y) return x.left < y.left end)
    for i = 1, math_min(6, #have) do
      local h = have[i]
      local t = h.left >= 90 and string_format(L["~%dm left"], math_floor(h.left / 60))
        or string_format(L["~%ds left"], math_floor(h.left))
      GameTooltip:AddLine(h.name .. " — " .. t, 0.55, 0.85, 0.55)
    end
  end
  -- Full tooltips (1.10.0) add the context lines: class and group, the
  -- range in words, and which other classes could cast the first buff.
  if db.tooltipLevel == "full" then
    local bits = {}
    if e.class then bits[#bits + 1] = e.class:sub(1, 1) .. e.class:sub(2):lower() end
    bits[#bits + 1] = e.group and "In your group" or "Nearby, not in your group"
    if not e.outOfRange then bits[#bits + 1] = "in cast range"
    elseif e.approximateRange then bits[#bits + 1] = L["Estimated range"]
    elseif e.rangeBucket == 1 then bits[#bits + 1] = "near — just out of range" end
    GameTooltip:AddLine(table.concat(bits, " · "), 0.7, 0.7, 0.7)
    -- Which other classes could cast the first missing buff: scanned
    -- from the definitions on the spot (a hover is rare; no state kept).
    local _, myClass = UnitClass("player")
    local names, seenCls = {}, {}
    for _, d in ipairs(BUFF_DEFS) do
      local dn
      if d.choices then dn = SpellName(d.choices[1][1], d.choices[1][2])
      else dn = SpellName(d.id, d.name) end
      if dn == e.missing[1] then
        for c in pairs(d.classes or ALL) do
          if c ~= myClass and not seenCls[c] then
            seenCls[c] = true
            names[#names + 1] = c:sub(1, 1) .. c:sub(2):lower()
          end
        end
      end
    end
    table_sort(names)
    if #names > 0 then
      GameTooltip:AddLine("Also castable by: " .. table.concat(names, ", "), 0.7, 0.7, 0.7, true)
    end
  end
  GameTooltip:Show()
end

-- The name field stops this far short of the row's right edge to leave
-- room for the buff icons; it follows the icon size (1.10.0).
local function IconInset()
  local isz = (db.iconSize or 0) > 0 and db.iconSize or (db.compact and 12 or 16)
  return MAX_ICONS * (isz + 2) + 4
end

function X.InstallCombatDriver(button, snippet)
  if not RegisterStateDriver then return false end
  local ok, accepted = pcall(button.SetAttribute, button, "_onstate-combat", snippet)
  if not ok or accepted == false then return false end
  ok, accepted = pcall(RegisterStateDriver, button, "combat", "[combat] combat; nocombat")
  return ok and accepted ~= false
end

local function CreateRow(i)
  local b = CreateFrame("Button", "BuffRadarRow" .. i, frame,
                        "SecureActionButtonTemplate,SecureHandlerStateTemplate")
  -- Anchored on both sides, so rows follow the window's width when it's resized.
  b:SetHeight(ROW_H)
  b:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -HEADER_H - (i - 1) * ROW_H)
  b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -HEADER_H - (i - 1) * ROW_H)
  if db.clickReg == "down" then
    b:RegisterForClicks("AnyDown")
  elseif db.clickReg == "up" then
    b:RegisterForClicks("AnyUp")
  else
    b:RegisterForClicks("AnyUp", "AnyDown")
  end
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  -- Right-click only ignores (see the OnClick hook below). Bind() sets the plain
  -- "type" attribute, which the secure template uses for EVERY mouse button
  -- unless a button-specific one exists; this "type2" override is a made-up
  -- action the template doesn't know, so a right-click casts nothing.
  -- Bind() never touches "type2", so this holds for the row's lifetime.
  b:SetAttribute("type2", "buffradarignore")
  b.combatDriver = X.InstallCombatDriver(b, [[
    if newstate == "combat" then
      self:SetAttribute("type", nil)
      self:SetAttribute("spell", nil)
      self:SetAttribute("unit", nil)
      self:SetAttribute("macrotext", nil)
      self:SetAttribute("shift-type1", nil)
      self:SetAttribute("shift-spell1", nil)
      self:SetAttribute("shift-unit1", nil)
      self:SetAttribute("shift-macrotext1", nil)
    end
  ]])

  b.portrait = b:CreateTexture(nil, "ARTWORK")
  b.portrait:SetSize(ROW_H - 2, ROW_H - 2)
  b.portrait:SetPoint("LEFT", 1, 0)
  if b.CreateMaskTexture and b.portrait.AddMaskTexture then
    local m = b:CreateMaskTexture()
    m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
                 "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(b.portrait)
    b.portrait:AddMaskTexture(m)
  end

  b.cMissing = {}  -- render cache: icons currently drawn
  b.icons = {}
  for j = 1, MAX_ICONS do
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetSize(16, 16)
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if j == 1 then
      t:SetPoint("RIGHT", b, "RIGHT", -2, 0)
    else
      t:SetPoint("RIGHT", b.icons[j - 1], "LEFT", -2, 0)
    end
    b.icons[j] = t
  end

  b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.name:SetPoint("LEFT", b.portrait, "RIGHT", 6, 0)
  b.name:SetPoint("RIGHT", b, "RIGHT", -(IconInset()), 0)
  b.name:SetJustifyH("LEFT")
  if b.name.SetWordWrap then b.name:SetWordWrap(false) end
  -- "out of range" under the name of a greyed row, so the state doesn't rest
  -- on color alone (RenderRow moves the name up to make room).
  b.far = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  b.far:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -1)
  b.far:SetText(L["out of range"])
  b.far:Hide()

  -- Duration bar (1.8.0): a thin bar along the row's bottom edge showing
  -- how much of a 30-minute span the expiring buff has left.
  b.tint = b:CreateTexture(nil, "OVERLAY")
  b.tint:SetTexture("Interface\\Buttons\\WHITE8X8")
  b.tint:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -1)
  b.tint:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 1)
  b.tint:SetWidth(3)
  b.tint:Hide()
  b.bar = b:CreateTexture(nil, "ARTWORK")
  b.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
  b.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, 1)
  b.bar:SetHeight(3)
  b.bar:SetWidth(10)
  b.bar:Hide()
  -- Raid marker badge (1.8.0): the player's raid target icon, drawn over
  -- the portrait's top-left corner.
  b.marker = b:CreateTexture(nil, "OVERLAY")
  b.marker:SetSize(12, 12)
  b.marker:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  b.marker:Hide()

  -- Short status tag under the name ("recently rezzed"); shares the slot
  -- with the out-of-range label, which wins when both would apply.
  b.tag = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.tag:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -1)
  b.tag:SetTextColor(1, 0.85, 0.4)
  b.tag:Hide()

  -- HookScript, never SetScript: SetScript would REPLACE the
  -- SecureActionButtonTemplate's own OnClick (SecureActionButton_OnClick),
  -- which is what actually performs the cast -- with it replaced, clicks run
  -- only this handler and nothing is ever cast (the 1.2.0/1.2.1 bug).
  b:HookScript("OnClick", function(self, button, down)
    if button ~= "RightButton" or InCombatLockdown() then return end
    -- With AnyUp+AnyDown registered, OnClick fires twice per physical click;
    -- toggle on exactly one phase (release, unless casts trigger on press).
    if down ~= (db.clickReg == "down") then return end
    local e = self.entry
    if not e or not db then return end
    local short = SafeString(e.name)  -- a protected (secret) name can't be stored
    local who = e.fullName or short   -- Name-Realm: ignores this one player only
    if not who then return end
    if _G.IsShiftKeyDown and _G.IsShiftKeyDown() then
      local k = Ignore.Key(who)
      if X.session[k] then
        X.session[k] = nil
        Print("No longer ignoring " .. who .. " for this session.")
      else
        X.session[k] = true
        Print("Ignoring " .. who .. " for this session only (not saved).")
      end
      if QueueRefresh then QueueRefresh() end
      return
    end
    if Ignore.Has(e.fullName, short) then
      -- (a row still showing an ignored player: it drops off on the next refresh)
      local removed = Ignore.Remove(who)
      if #removed == 0 and short then removed = Ignore.Remove(short) end
      Print("No longer ignoring " .. table.concat(removed, ", ") .. ".")
    else
      Ignore.Add(who)
      Print("Ignoring " .. who .. ". Undo with /br unignore " .. who .. " or on the Ignore & Stats tab.")
    end
    if QueueRefresh then QueueRefresh() end
  end)
  b:SetScript("PostClick", function(self, button, down)
    -- (a right-click casts nothing, so it mustn't count toward the cast counter)
    if button ~= "RightButton" and self:GetAttribute("type") then
      -- Modifier click (Brief 3): bookkeep the spell the secure dispatch
      -- actually cast (the group version), not the row's plain pick.
      local override
      if button == "LeftButton" and db.modClick and _G.IsShiftKeyDown and _G.IsShiftKeyDown()
         and self.entry and self.entry.missing then
        override = X.GroupSpellFor(self.entry.missing[1])
      end
      NotePendingCast(self.entry, override)
    end
    if db.clickDebug then
      Print(string.format("click: %s %s | type=%s | %s", tostring(button),
        down and "down" or "up", tostring(self:GetAttribute("type")),
        tostring(self:GetAttribute("macrotext") or
                 (tostring(self:GetAttribute("spell")) .. " @" .. tostring(self:GetAttribute("unit"))))))
    end
  end)
  b:SetScript("OnEnter", Row_OnEnter)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Hide()
  rows[i] = b
end

local grip  -- width resize grip, bottom-right corner (built in BuildUI)

-- Color themes (1.8.0): a theme is a background color + border color pair.
-- Picking one sets both; picking a custom background color afterwards
-- switches the theme back to "custom" (border returns to the default).

-- Saved themes (1.10.0): your own background + border pairs, kept in
-- db.customThemes, usable anywhere a built-in theme is.
function X.SavedTheme(name)
  if not db or not name then return nil end
  for _, t in ipairs(db.customThemes or {}) do
    if t.name:lower() == name:lower() then
      return { label = t.name, bg = t.bg, border = t.border }
    end
  end
  return nil
end

function X.ThemeDef(name)
  if not name then return nil end
  return X.THEMES[name] or X.SavedTheme(name)
end

-- The cycle order: the four built-ins, then your saved themes.
function X.ThemeOrder()
  local order = {}
  for _, k in ipairs(X.THEME_ORDER) do order[#order + 1] = k end
  if db then
    for _, t in ipairs(db.customThemes or {}) do order[#order + 1] = t.name end
  end
  return order
end

function X.ThemeBorder()
  local t = db and X.ThemeDef(db.theme)
  if t then return t.border end
  return { 0.35, 0.55, 0.8 }
end

-- Grow-up (1.8.0): normally the window hangs from its top-left corner and
-- the list grows downward. With grow-up on, the window stands on its
-- bottom-left corner instead, so the list grows upward and the bottom
-- edge never moves. The saved point records which form it holds.
function X.ApplyAnchor()
  if not frame then return end
  local left = frame:GetLeft()
  if not left then return end
  if db.growUp then
    local bottom = frame:GetBottom()
    if not bottom then return end
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    db.point = { "BOTTOMLEFT", "BOTTOMLEFT", left, bottom }
  else
    local top = frame:GetTop()
    if not top then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    db.point = { "TOPLEFT", "BOTTOMLEFT", left, top }
  end
  if db.charPoint then
    local k = X.CharKey()
    if k then db.pointByChar[k] = db.point end
  end
end

-- Title suffix (1.12.0): "(update pending)" while a size/scale change waits
-- for combat to end; "(data hidden)" while the game is withholding aura
-- data from addons (secret values), so a stale-looking list has a reason.
function X.UpdateTitleMarks()
  if not title then return end
  local hid = X.hid > 0 and (GetTime() - X.hid) < 10
  local key = (X.geoPending and "p" or "") .. (hid and "h" or "")
  if X.titleKey == key then return end
  X.titleKey = key
  local txt = "|cff33ccffBuff|rRadar"
  if X.geoPending then txt = txt .. " |cffffa040(update pending)|r" end
  if hid then txt = txt .. " |cffffa040(data hidden)|r" end
  title:SetText(txt)
end

-- Width and scale. The window holds secure row buttons, so its size can't
-- change in combat; callers retry after combat (PLAYER_REGEN_ENABLED).
local function ApplyGeometry()
  if not frame then return end
  if InCombatLockdown() then
    X.geoPending = true  -- lands at PLAYER_REGEN_ENABLED; the title says so meanwhile (1.12.0)
    X.UpdateTitleMarks()
    return
  end
  X.geoPending = nil
  -- Two-column layout (1.9.0): each column keeps the chosen width, with
  -- a small gap between the columns.
  local cols = X.cols or 1
  frame:SetWidth((db.width or WIDTH) * cols + (cols - 1) * 6)
  frame:SetScale(db.scale or 1)
  X.UpdateTitleMarks()
end

function X.ApplyScaleNow() ApplyGeometry() end

local function ApplyAppearance()
  if not frame then return end
  if InCombatLockdown() then
    X.appearancePending = true
    return
  end
  X.appearancePending = nil
  X.flashPending = nil
  local c = db.bgColor or DEFAULTS.bgColor
  local bc = X.ThemeBorder()
  if frame.SetBackdropColor then
    frame:SetBackdropColor(c[1], c[2], c[3], db.bgAlpha or 0.92)
    frame:SetBackdropBorderColor(bc[1], bc[2], bc[3], db.showBorder and 1 or 0)
  end
  if X.pill and X.pill.SetBackdropColor then
    X.pill:SetBackdropColor(c[1], c[2], c[3], db.bgAlpha or 0.92)
    X.pill:SetBackdropBorderColor(bc[1], bc[2], bc[3], db.showBorder and 1 or 0)
  end
  if grip then grip:SetShown(not db.locked) end
  if X.gripL then X.gripL:SetShown(not db.locked) end
  if X.edge then X.edge:SetShown(not db.locked) end
  title:SetShown(db.showTitle and true or false)
  combatText:ClearAllPoints()
  if db.showTitle then
    combatText:SetPoint("LEFT", title, "RIGHT", 6, 0)
  else
    combatText:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -8)
  end
end

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
          if RefreshConfig then RefreshConfig() end
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
      local t = db.theme or "custom"
      return "Theme: " .. t:sub(1, 1):upper() .. t:sub(2)
    end
    b:SetText(themeLabel())
    b:SetScript("OnClick", function()
      local order = X.ThemeOrder()
      local cur = 1
      for i, k in ipairs(order) do if k:lower() == (db.theme or ""):lower() then cur = i end end
      X.ApplyTheme(order[cur % #order + 1])
      if RefreshConfig then RefreshConfig() end
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
    b:SetScript("OnClick", function() OpenConfig() end)
    b:Show()
    w.next:SetText("Finish")
    w.next:Show()
  end
  w.pageText:SetText("Step " .. n .. " of 3")
end

function X.OpenWizard()
  if not db then return end
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
  local t = X.ThemeDef(name)
  if not t then return false end
  if X.SavedTheme(name) then name = t.label end  -- keep the saved spelling
  db.theme = name
  db.bgColor = { t.bg[1], t.bg[2], t.bg[3] }
  ApplyAppearance()
  if RefreshConfig then RefreshConfig() end
  return true
end

-- Save the current look (background + the border now in effect) as one
-- of your themes (1.10.0). Returns the name, or nil plus a reason.
function X.SaveTheme(name)
  name = (name or ""):match("^%s*(.-)%s*$")
  if not name:match("^[%w%-]+$") or #name > 24 then return nil, "name" end
  if X.THEMES[name:lower()] or name:lower() == "custom" then return nil, "taken" end
  local b = X.ThemeBorder()
  local entry = { name = name,
    bg = { db.bgColor[1], db.bgColor[2], db.bgColor[3] },
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
      if (db.theme or ""):lower() == t.name:lower() then
        db.theme = "custom"
        ApplyAppearance()
        if RefreshConfig then RefreshConfig() end
      end
      return true
    end
  end
  return false
end

-- One border pulse; restores the normal border shortly after. Assigned
-- here because frame / ApplyAppearance only exist from this point on.
function X.Flash()
  if not frame or not frame.SetBackdropBorderColor or InCombatLockdown() or db.reduceMotion then return end
  frame:SetBackdropBorderColor(1, 0.35, 0.35, 1)
  if C_Timer and C_Timer.After then
    C_Timer.After(0.7, function() if frame then ApplyAppearance() end end)
  else
    X.flashPending = true  -- no timer API: Refresh() restores it next pass
  end
end

-- Watched-buff drop alert (1.5.0): your single-target buff (Earth Shield)
-- was on someone at the last scan and is gone now, while that player is
-- still around -- say so instead of silently re-offering it. The alert
-- fires once per drop: prevHolder only refills when the buff is seen on
-- someone again. A holder change (you recast it on someone else) is a
-- move, not a drop. Runs after each CollectEntries in Refresh.
X.farNow, X.farPrev = {}, {}
-- Range watch (1.12.0): a player who needed a buff and was out of range
-- last scan, and is in range now, still needs it -> one chat line + the
-- alert sound. The game does not allow casting automatically, so this
-- only tells you; the click is yours.
function X.CheckRange()
  if not db.rangeWatch then
    wipe(X.farPrev); wipe(X.farNow); return
  end
  for i = 1, nEntries do
    local e = entries[i]
    local g = e.guid
    if g and X.farPrev[g] and not e.outOfRange and not e.pet then
      Print(string_format("%s is in range now and still needs a buff.", tostring(X.farPrev[g])))
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
-- is not on the list. Runs the same checks the scan runs, in the same
-- order, and reports the first one that decides it; when none does, the
-- player is listed and this says what they are missing. Missing() with
-- isGroup=true feeds the coverage tallies, so the caller refreshes
-- right after to rebuild them.
function X.Why(name)
  if not db then return end
  local want = (name or ""):lower()
  local unit, full, short, isGroup
  local function try(u, grp)
    if not UnitExists(u) then return false end
    local f, s = Ignore.UnitNames(u)
    if not f then return false end
    local fl, sl = f:lower(), (s or ""):lower()
    if fl == want or sl == want or fl:find(want, 1, true) or sl:find(want, 1, true) then
      unit, full, short, isGroup = u, f, s, grp
      return true
    end
    return false
  end
  local list = InRaid() and RAID or PARTY
  for i = 1, #list do if try(list[i], true) then break end end
  if not unit then try("player", true) end
  if not unit then try("target", false) end
  if not unit then
    Print("Why: no player named '" .. name .. "' in your group.")
    return
  end
  local disp = short or full
  if Ignore.Has(full, short) then
    Print(disp .. " is on your ignore list, so they are never listed. /br unignore " .. disp .. " undoes it.")
    return
  end
  if X.SessionHas(full, short) then
    Print(disp .. " is ignored for this session only (Shift+right-click on a row). It clears when you reload.")
    return
  end
  local valid, isSelf = Valid(unit)
  if not valid then
    Print(disp .. " can't be buffed right now (dead, offline, in combat, charmed or in another phase), so they are not listed.")
    return
  end
  local allMiss, miss = {}, {}
  local n = Missing(unit, allMiss, isGroup, isSelf)
  if n == 0 then
    if X.auraUnknown then
      Print(disp .. ": buff information is unavailable.")
    else
      Print(disp .. " already has every buff you can give them.")
    end
    return
  end
  local inRange = X.FilterInRange(unit, allMiss, miss, isSelf)
  if inRange == 0 then
    Print(disp .. " needs " .. table.concat(allMiss, ", ") .. " but none are in cast range; move closer before buffing.")
    return
  end
  local guid = UnitGUID(unit)
  for i = 1, nEntries do
    if entries[i].guid == guid then
      local shown = false
      for r = 1, MAX_ROWS do
        if rows[r] and rows[r].entry == entries[i] then shown = true break end
      end
      if shown then
        Print(disp .. " is on the list (row " .. i .. "), missing: " .. table.concat(miss, ", ") .. ".")
      else
        Print(disp .. " needs " .. table.concat(miss, ", ") .. " and is collected, but the row is not shown -- the role filter under the title is the usual reason.")
      end
      return
    end
  end
  if X.search and X.search ~= "" and not (disp:lower():find(X.search, 1, true)) then
    Print(disp .. " needs " .. table.concat(miss, ", ") .. ", but the name finder ('" .. X.search .. "') hides them. Clear the finder text to see everyone.")
    return
  end
  Print(disp .. " is not on the list right now; they need: " .. table.concat(miss, ", ") .. ".")
end

function X.CheckDrops()
  local lookup = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
  local uncertain = {}
  if db.watchDrop then
    for key, prev in pairs(X.prevHolder) do
      if not Single.holder[key] and prev.unit and UnitExists(prev.unit) and lookup then
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
    X.prevHolder[key] = { unit = unit, name = SafeString(UnitName(unit)) or unit }
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
  local keep = X.applyFilter
  X.applyFilter = false
  CollectEntries()
  X.applyFilter = keep
  local per, people = {}, 0
  for i = 1, nEntries do
    local e = entries[i]
    if e.group and not e.pet then
      people = people + 1
      for j = 1, #e.missing do
        local n = SafeString(e.missing[j]) or "?"
        per[n] = (per[n] or 0) + 1
      end
    end
  end
  local counts = {}
  for n, c in pairs(per) do counts[#counts + 1] = { n = n, c = c } end
  table_sort(counts, function(a, b) if a.c ~= b.c then return a.c > b.c end return a.n < b.n end)
  return counts, people
end

-- Discord summary (1.8.0): the group's buff state as a small markdown
-- block, ready to paste into a Discord message.
function X.DiscordText()
  local keep = X.applyFilter
  X.applyFilter = false
  CollectEntries()
  X.applyFilter = keep
  local lines = { "**BuffRadar — group buff check**" }
  if X.tallyUnits > 1 or (X.tallyUnits > 0 and X.tallyUnknownUnits > 0) then
    lines[#lines + 1] = string_format("%d/%d fully buffed",
      X.tallyUnits - X.tallyMissingUnits, X.tallyUnits)
  end
  local people = {}
  for i = 1, nEntries do
    local e = entries[i]
    if e.group then
      people[#people + 1] = (SafeString(e.name) or e.sortName or "?")
        .. " — " .. table.concat(e.missing, ", ")
    end
  end
  if #people == 0 and X.tallyUnknownUnits == 0 then
    lines[#lines + 1] = "Everyone is buffed."
  elseif #people > 0 then
    lines[#lines + 1] = "Still needs buffs:"
    for _, p in ipairs(people) do lines[#lines + 1] = "- " .. p end
  end
  if X.upTotal >= 10 then
    lines[#lines + 1] = string_format("Coverage uptime this run: %d%%",
      math_floor(100 * X.upFull / X.upTotal + 0.5))
  end
  return table.concat(lines, "\n")
end

function X.ShowExport(text, forImport, titleText, mode)
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
        if RefreshConfig then RefreshConfig() end
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

-- Your own "Name-Realm", for per-character settings.
function X.CharKey()
  local full = Ignore.UnitNames("player")
  return full
end

-- Compact rows + list text scale (1.4.0). Re-anchors every row; height
-- changes are not combat-safe on secure buttons, so this no-ops in combat
-- and lands on the post-combat refresh instead.
-- Click-through (1.10.0): while the window is locked AND the player
-- asked for it, the window and its rows stop eating mouse clicks, so
-- clicks land on the game world behind them. Never changed in combat
-- (secure buttons refuse it there); re-applied when combat ends and
-- whenever the lock or the setting changes.
function X.ApplyClickThrough()
  if not frame or not db then return end
  if InCombatLockdown and InCombatLockdown() then return end
  local mouse = not (db.clickThrough and db.locked)
  if frame.EnableMouse then frame:EnableMouse(mouse) end
  for i = 1, MAX_ROWS do
    local row = rows[i]
    if row and row.EnableMouse then row:EnableMouse(mouse) end
  end
  if nextBtn and nextBtn.EnableMouse then nextBtn:EnableMouse(mouse) end
end

function X.ApplyRowLayout()
  if not frame or InCombatLockdown() then return end
  local h = db.compact and 16 or ROW_H
  X.rowH = h
  if X.findBar then
    X.findBar:SetShown(db.findBox and true or false)
    X.findBar:ClearAllPoints()
    X.findBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -HEADER_H - X.BarHeight())
    X.findBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -HEADER_H - X.BarHeight())
  end
  local top = HEADER_H + X.BarHeight() + (db.findBox and 16 or 0)
  X.topH = top
  if X.bar then X.bar:SetShown(X.BarHeight() > 0) end
  -- Two-column layout (1.9.0): rows fill the first column top to
  -- bottom, then the second. X.cols / X.rowsPerCol are kept current by
  -- Refresh; with one column this is exactly the old anchoring.
  local per = X.rowsPerCol or MAX_ROWS
  local cols = X.cols or 1
  local cellW = (db.width or WIDTH) + 6  -- column width + the gap
  for i = 1, #rows do
    local row = rows[i]
    local col = math_floor((i - 1) / per)
    local idx = (i - 1) % per
    row:SetHeight(h)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 6 + col * cellW, -top - idx * (h + (db.rowGap or 0)))
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(6 + (cols - 1 - col) * cellW), -top - idx * (h + (db.rowGap or 0)))
    if row.portrait then row.portrait:SetShown(not db.compact) end
    local isz = (db.iconSize or 0) > 0 and db.iconSize or (db.compact and 12 or 16)
    for j = 1, MAX_ICONS do if row.icons[j] then row.icons[j]:SetSize(isz, isz) end end
    local ts = db.textScale or 1
    if row.name then row.name:SetScale(ts) end
    if row.far then row.far:SetScale(ts) end
    if row.tag then row.tag:SetScale(ts) end
  end
  if emptyText then
    emptyText:ClearAllPoints()
    emptyText:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -top - 3)
  end
end

---------------------------------------------------------------------------
-- Toggle strip, filter chips and idle fade (1.5.0). The bar under the
-- title carries one icon button per buff you can cast (click toggles it,
-- like the Buffs tab) and the role filter chips on the right.
---------------------------------------------------------------------------
function X.BarHeight()
  return (db and db.showStrip and hasAnyBuff) and 18 or 0
end

function X.RefreshStrip()
  if not X.stripBtns or not db then return end
  local parts = {}
  for _, b in ipairs(myBuffs) do parts[#parts + 1] = b.key .. (IsOn(b.key, b.default) and "1" or "0") end
  if next(myBlessing) then parts[#parts + 1] = "BLESSINGS" .. (IsOn("BLESSINGS", true) and "1" or "0") end
  local sig = table.concat(parts, ",") .. "|" .. bookCount
  if sig == X.stripSig then return end
  X.stripSig = sig
  local i = 0
  local function place(key, name, default)
    i = i + 1
    local b = X.stripBtns[i]
    if not b then return end
    b.buffKey, b.buffName, b.buffDefault = key, name, default
    local on = IsOn(key, default)
    b.tex:SetTexture(SpellIcon(name))
    b.tex:SetAlpha(on and 1 or 0.3)
    if b.tex.SetDesaturated then b.tex:SetDesaturated(not on) end
    b:Show()
  end
  for _, b in ipairs(myBuffs) do place(b.key, b.name, b.default) end
  if next(myBlessing) then
    local _, anyB = next(myBlessing)
    if anyB then place("BLESSINGS", anyB.name, true) end
  end
  for j = i + 1, #X.stripBtns do X.stripBtns[j]:Hide() end
end

function X.RefreshChips()
  if not X.chipBtns or not db then return end
  for _, b in ipairs(X.chipBtns) do
    if b.roleKey == db.roleFilter then b.fs:SetTextColor(1, 0.85, 0.3)
    else b.fs:SetTextColor(0.55, 0.55, 0.55) end
  end
end

-- Idle fade: while the mouse is elsewhere the whole window goes partly
-- see-through; moving the mouse over it brings it back. Polled from the
-- refresh ticker (no per-frame work).
function X.UpdateFade()
  if not frame or not db then return end
  local target = 1
  if db.idleFade and db.idleFade > 0 and not db.reduceMotion and not frame.isMoving and not (grip and grip.isSizing)
     and not (X.gripL and X.gripL.isSizing) and not (X.edge and X.edge.isSizing) then
    local over = frame.IsMouseOver and frame:IsMouseOver()
    if not over then target = 1 - db.idleFade / 100 end
  end
  if X.curAlpha ~= target then
    X.curAlpha = target
    frame:SetAlpha(target)
  end
end

-- The keybind / macro button. Like the rows, it's set up between clicks (never during one).
-- It casts on press when "ActionButtonUseKeyDown" is on and on release otherwise, so one
-- key press = one cast. It clears itself after each use and whenever combat starts.
local function ApplyNextRegistration()
  if not nextBtn or InCombatLockdown() then return end
  if GetCVarBool and GetCVarBool("ActionButtonUseKeyDown") then
    nextBtn:RegisterForClicks("LeftButtonDown")
  else
    nextBtn:RegisterForClicks("LeftButtonUp")
  end
  if X.groupBtn then
    if GetCVarBool and GetCVarBool("ActionButtonUseKeyDown") then
      X.groupBtn:RegisterForClicks("LeftButtonDown")
    else
      X.groupBtn:RegisterForClicks("LeftButtonUp")
    end
  end
end

local nextWrapped, nextCombatDriver = false, false

local function ClearNext()
  if not nextBtn or InCombatLockdown() then return end
  nextBtn.entry = nil
  if nextBtn.isClear then return end  -- already disarmed: skip four protected writes
  nextBtn:SetAttribute("type", nil)
  nextBtn:SetAttribute("spell", nil)
  nextBtn:SetAttribute("unit", nil)
  nextBtn:SetAttribute("macrotext", nil)
  nextBtn:SetAttribute("shift-type1", nil)
  nextBtn:SetAttribute("shift-spell1", nil)
  nextBtn:SetAttribute("shift-unit1", nil)
  nextBtn:SetAttribute("shift-macrotext1", nil)
  nextBtn.isClear = true
  nextBtn.bGuid = nil
end

local function ClearGroup()
  if not X.groupBtn or InCombatLockdown() then return end
  X.groupBtn.entry = nil
  if X.groupBtn.isClear then return end  -- already disarmed: skip the protected writes
  X.groupBtn:SetAttribute("type", nil)
  X.groupBtn:SetAttribute("spell", nil)
  X.groupBtn:SetAttribute("unit", nil)
  X.groupBtn:SetAttribute("macrotext", nil)
  X.groupBtn.isClear = true
  X.groupBtn.bGuid = nil
end
X.ClearGroup = ClearGroup


-- Group-cast keybind (1.15.0): the group button's plain attribute family
-- carries the GROUP version of the head row's buff, so one key press
-- casts it. When the buff has no group version the button falls back to
-- the plain cast -- the key is never dead, same as the next-buff key.
-- Mirrors Bind's cast-method branches for the single spell it writes;
-- Bind itself is untouched (rows and the next-buff button keep their
-- proven path).
local function BindGroup(btn, unit, spell, isSelf)
  local gspell = (CLASSIC_FEATURES and X.GroupSpellFor(spell)) or spell
  local pick = X.PickRank(gspell, unit)
  local method = db.castMethod
  if method == "target" then
    btn:SetAttribute("type", nil)
    btn:SetAttribute("unit", nil)
    btn:SetAttribute("spell", nil)
    btn:SetAttribute("macrotext", nil)
    if isSelf then
      btn:SetAttribute("type", "spell")
      btn:SetAttribute("spell", gspell)
      btn:SetAttribute("unit", "player")
      return
    end
    if unit:match("^party%d+$") or unit:match("^raid%d+$") then
      btn:SetAttribute("type", "spell")
      btn:SetAttribute("spell", gspell)
      btn:SetAttribute("unit", unit)
      return
    end
    local ok, name = pcall(GetUnitName or UnitName, unit, true)
    name = ok and SafeString(name) or nil  -- a protected name can't build a macro: no cast
    if name and name ~= "" then
      btn:SetAttribute("type", "macro")
      btn:SetAttribute("macrotext", "/targetexact " .. name .. "\n/cast " .. gspell .. "\n/targetlasttarget")
    end
  elseif method == "id" and pick and pick.id then
    btn:SetAttribute("type", "spell")
    btn:SetAttribute("unit", unit)
    btn:SetAttribute("spell", pick.id)
    btn:SetAttribute("macrotext", nil)
  else
    local text = (method == "rank") and X.CastText(gspell, unit) or gspell
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("unit", nil)
    btn:SetAttribute("spell", nil)
    btn:SetAttribute("macrotext", "/cast [@" .. unit .. ",help,nodead] " .. text)
  end
end

local function BindGroupCached(btn, unit, spell, guid)
  if not btn.combatDriver then return false end
  local isSelf = X.IsSelf(unit)
  if isSelf == nil then ClearGroup(); return false end
  local gspell = (CLASSIC_FEATURES and X.GroupSpellFor(spell)) or spell
  local method = db.castMethod
  local lvl = X.ReadUnitNumber(UnitLevel, unit) or 0
  if btn.bGuid == guid and btn.bUnit == unit and btn.bSpell == gspell
     and btn.bMethod == method and btn.bLevel == lvl and btn.bSelf == isSelf then
    return btn:GetAttribute("type") ~= nil
  end
  BindGroup(btn, unit, spell, isSelf)
  btn.bGuid, btn.bUnit, btn.bSpell, btn.bMethod, btn.bLevel = guid, unit, gspell, method, lvl
  btn.bSelf = isSelf
  btn.isClear = false
  return btn:GetAttribute("type") ~= nil
end

function X.ClearRowCast(btn)
  if InCombatLockdown() then return end
  btn:SetAttribute("type", nil)
  btn:SetAttribute("spell", nil)
  btn:SetAttribute("unit", nil)
  btn:SetAttribute("macrotext", nil)
  btn:SetAttribute("shift-type1", nil)
  btn:SetAttribute("shift-spell1", nil)
  btn:SetAttribute("shift-unit1", nil)
  btn:SetAttribute("shift-macrotext1", nil)
  btn.bGuid = nil
end

-- Secure attribute writes only when what the button should cast actually changed.
local function BindCached(btn, unit, spell, guid)
  if not btn.combatDriver then return false end
  local isSelf = X.IsSelf(unit)
  if isSelf == nil then
    if btn.bGuid ~= nil then X.ClearRowCast(btn) end
    return false
  end
  local method = db.castMethod
  local lvl = X.ReadUnitNumber(UnitLevel, unit) or 0
  if btn.bGuid == guid and btn.bUnit == unit and btn.bSpell == spell
     and btn.bMethod == method and btn.bLevel == lvl and btn.bSelf == isSelf
     and btn.bMod == (db.modClick and true or false) then
    return btn:GetAttribute("type") ~= nil
  end
  Bind(btn, unit, spell, isSelf)
  btn.bGuid, btn.bUnit, btn.bSpell, btn.bMethod, btn.bLevel = guid, unit, spell, method, lvl
  btn.bSelf = isSelf
  btn.bMod = db.modClick and true or false
  btn.isClear = false
  return btn:GetAttribute("type") ~= nil
end

-- Arm the group button with the head row (called from Refresh, which is
-- at its upvalue ceiling and reaches the button only through X).
function X.ArmGroupBtn(first)
  if not X.groupBtn then return end
  X.groupBtn.entry = BindGroupCached(X.groupBtn, first.unit, first.missing[1], first.guid) and first or nil
end

local function BuildNextButton()
  nextBtn = CreateFrame("Button", "BuffRadarNextButton", UIParent,
                        "SecureActionButtonTemplate,SecureHandlerStateTemplate")
  nextBtn:SetSize(1, 1)
  nextBtn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
  nextBtn:SetAlpha(0)
  nextBtn:EnableMouse(false)
  nextBtn:Show()
  ApplyNextRegistration()
  -- Secure snippets clear the button the instant combat starts and right after each use.
  -- Leave casting disarmed if the client cannot install combat clearing.
  nextCombatDriver = X.InstallCombatDriver(nextBtn, [[
    if newstate == "combat" then
      self:SetAttribute("type", nil)
      self:SetAttribute("spell", nil)
      self:SetAttribute("unit", nil)
      self:SetAttribute("macrotext", nil)
      self:SetAttribute("shift-type1", nil)
      self:SetAttribute("shift-spell1", nil)
      self:SetAttribute("shift-unit1", nil)
      self:SetAttribute("shift-macrotext1", nil)
    end
  ]])
  nextBtn.combatDriver = nextCombatDriver
  if SecureHandlerWrapScript then
    nextWrapped = pcall(SecureHandlerWrapScript, nextBtn, "OnClick", nextBtn, [[ return nil, true ]], [[
      self:SetAttribute("type", nil)
      self:SetAttribute("spell", nil)
      self:SetAttribute("unit", nil)
      self:SetAttribute("macrotext", nil)
      self:SetAttribute("shift-type1", nil)
      self:SetAttribute("shift-spell1", nil)
      self:SetAttribute("shift-unit1", nil)
      self:SetAttribute("shift-macrotext1", nil)
    ]])
  end
  nextBtn:HookScript("PostClick", function(self, _, down)
    NotePendingCast(self.entry)
    self.bGuid, self.isClear = nil, false  -- attributes changed outside our cache
    if not nextWrapped then ClearNext() end  -- one press = one cast
    if db.clickDebug then
      Print(string.format("next-buff key: %s | type=%s | %s", down and "down" or "up",
        tostring(self:GetAttribute("type")), tostring(self:GetAttribute("macrotext") or
        self:GetAttribute("spell"))))
    end
  end)
end

-- The group-cast keybind button (1.15.0): same hidden secure pattern as
-- the next-buff button -- combat driver clears it, the wrap clears it
-- after each use, PostClick books the cast that actually happened (the
-- group version when there is one).
local function BuildGroupButton()
  local btn = CreateFrame("Button", "BuffRadarGroupButton", UIParent,
                         "SecureActionButtonTemplate,SecureHandlerStateTemplate")
  X.groupBtn = btn
  btn:SetSize(1, 1)
  btn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
  btn:SetAlpha(0)
  btn:EnableMouse(false)
  btn:Show()
  ApplyNextRegistration()
  X.groupCombatDriver = X.InstallCombatDriver(btn, [[
    if newstate == "combat" then
      self:SetAttribute("type", nil)
      self:SetAttribute("spell", nil)
      self:SetAttribute("unit", nil)
      self:SetAttribute("macrotext", nil)
    end
  ]])
  btn.combatDriver = X.groupCombatDriver
  if SecureHandlerWrapScript then
    X.groupWrapped = pcall(SecureHandlerWrapScript, btn, "OnClick", btn, [[ return nil, true ]], [[
      self:SetAttribute("type", nil)
      self:SetAttribute("spell", nil)
      self:SetAttribute("unit", nil)
      self:SetAttribute("macrotext", nil)
    ]])
  end
  btn:HookScript("PostClick", function(self, _, down)
    local e = self.entry
    NotePendingCast(e, e and e.missing and (CLASSIC_FEATURES and GroupSpellFor(e.missing[1])) or nil)
    self.bGuid, self.isClear = nil, false  -- attributes changed outside our cache
    if not X.groupWrapped then ClearGroup() end  -- one press = one cast
    if db.clickDebug then
      Print(string.format("group-buff key: %s | type=%s | %s", down and "down" or "up",
        tostring(self:GetAttribute("type")), tostring(self:GetAttribute("macrotext") or
        self:GetAttribute("spell"))))
    end
  end)
end

-- Scale drag (1.11.0). Cursor-driven; the OnUpdate runs only while a grip is
-- held. Scale = the cursor's horizontal distance from the fixed bottom
-- corner divided by the window's unscaled width.
X.SNAPS = { 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2 }

function X.ScaleFromCursor(g)
  local cx = GetCursorPosition() / UIParent:GetEffectiveScale()
  local w = g.baseW
  if not w or w <= 0 then return db.scale or 1 end
  local ns = (g.side == "RIGHT") and (cx - g.fixedX) / w or (g.fixedX - cx) / w
  if db.gripSnap ~= false and IsShiftKeyDown and IsShiftKeyDown() then
    local best, bd = ns, 0.06  -- Shift: snap to a preset within 6%
    for _, p in ipairs(X.SNAPS) do
      local d = math.abs(ns - p)
      if d < bd then best, bd = p, d end
    end
    ns = best
  end
  if ns < 0.5 then ns = 0.5 elseif ns > 2 then ns = 2 end  -- same bounds as RANGES.scale
  return ns
end

function X.PlaceScaled(g, ns)
  local left = (g.side == "RIGHT") and g.fixedX or (g.fixedX - g.baseW * ns)
  frame:SetScale(ns)
  frame:ClearAllPoints()
  if db.growUp then
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left / ns, g.fixedY / ns)
  else
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / ns, g.fixedY / ns)
  end
end

function X.EndEdgeDrag(e)
  if not e or not e.isSizing or InCombatLockdown() then return end
  e.isSizing = false
  frame:StopMovingOrSizing()
  local cols = X.cols or 1
  local w = (frame:GetWidth() - (cols - 1) * 6) / cols
  db.width = math.max(MIN_WIDTH, math.min(MAX_WIDTH, math_floor(w + 0.5)))
  ApplyGeometry()
  SavePosition()
end

function X.BeginScaleDrag(g)
  local s = frame:GetScale() or 1
  local l, r = frame:GetLeft(), frame:GetRight()
  local y = db.growUp and frame:GetBottom() or frame:GetTop()
  if not (l and r and y) then return end
  g.baseW = frame:GetWidth()
  g.fixedX = (g.side == "RIGHT") and l * s or r * s
  g.fixedY = y * s
  g.isSizing = true
  g:SetScript("OnUpdate", function(self)
    if InCombatLockdown() then X.EndScaleDrag(self); return end
    local ns = X.ScaleFromCursor(self)
    db.scale = ns
    X.PlaceScaled(self, ns)
  end)
end

function X.EndScaleDrag(g)
  if not g or not g.isSizing then return end
  g:SetScript("OnUpdate", nil)
  if InCombatLockdown() then return end
  g.isSizing = false
  local ns = math_floor((db.scale or 1) * 100 + 0.5) / 100
  db.scale = ns
  X.PlaceScaled(g, ns)
  SavePosition()
  if RefreshConfig then RefreshConfig() end
end

function X.EndWindowDrags()
  if InCombatLockdown() then return end
  if frame and frame.isMoving then
    frame:StopMovingOrSizing()
    frame.isMoving = false
    SavePosition()
  end
  X.EndScaleDrag(grip)
  X.EndScaleDrag(X.gripL)
  X.EndEdgeDrag(X.edge)
end

local function BuildUI()
  if built or InCombatLockdown() then return end

  frame = CreateFrame("Frame", "BuffRadarFrame", UIParent,
                      BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(db.width or WIDTH, HEADER_H + 30)
  -- Keep the client's default MEDIUM layer. Changing strata on the live
  -- frame can be blocked by some Forever clients and is not needed for casts.
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:SetResizable(true)
  -- Only the width is user-sized (StartSizing("RIGHT")); the height bounds are
  -- wide open because Refresh() sets the height to fit the list.
  if frame.SetResizeBounds then
    frame:SetResizeBounds(MIN_WIDTH, 1, MAX_WIDTH, 4000)
  elseif frame.SetMinResize then
    frame:SetMinResize(MIN_WIDTH, 1)
    frame:SetMaxResize(MAX_WIDTH, 4000)
  end
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    if not db.locked and not InCombatLockdown() then
      self:StartMoving()
      self.isMoving = true
    end
  end)
  frame:SetScript("OnDragStop", function(self)
    if not self.isMoving or InCombatLockdown() then return end
    self:StopMovingOrSizing()
    self.isMoving = false
    SavePosition()
  end)
  if frame.SetBackdrop then
    frame:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.04, 0.05, 0.09, 0.92)
    frame:SetBackdropBorderColor(0.35, 0.55, 0.8, 1)
  end

  title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 9, -7)
  title:SetText("|cff33ccffBuff|rRadar")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetSize(22, 22)
  close:SetPoint("TOPRIGHT", 0, 0)
  close:SetScript("OnClick", function()
    if InCombatLockdown() then Print("Can't hide during combat."); return end
    db.hidden = true
    frame:Hide()
    Print("Hidden. Type /br to show it again.")
  end)

  local gear = CreateFrame("Button", nil, frame)
  gear:SetSize(14, 14)
  gear:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 6)
  gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
  gear:SetHighlightTexture("Interface\\Buttons\\UI-OptionsButton", "ADD")
  gear:SetScript("OnClick", function() OpenConfig() end)
  gear:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["BuffRadar settings"])
    GameTooltip:Show()
  end)
  gear:SetScript("OnLeave", function() GameTooltip:Hide() end)

  countText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  countText:SetPoint("RIGHT", close, "LEFT", -2, 0)

  combatText = frame:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
  combatText:SetPoint("LEFT", title, "RIGHT", 6, 0)
  combatText:SetText(L["combat"])
  combatText:Hide()

  emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  emptyText:SetPoint("TOPLEFT", 10, -HEADER_H - 3)
  emptyText:SetText(L["Everyone nearby is buffed."])

  overflowText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  overflowText:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -HEADER_H)

  footerText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footerText:SetPoint("LEFT", gear, "RIGHT", 5, 0)
  footerText:SetPoint("RIGHT", frame, "BOTTOMRIGHT", -16, 13)  -- clear of the resize grip
  footerText:SetJustifyH("LEFT")
  if footerText.SetWordWrap then footerText:SetWordWrap(false) end
  X.footerText = footerText

  -- Coverage line (1.4.0): "12/15 fully buffed · Fortitude 13/15 · ...",
  -- directly above the footer; Refresh() grows the window when it's shown.
  coverText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  coverText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 9, FOOTER_H + 3)
  coverText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, FOOTER_H + 3)
  coverText:SetJustifyH("LEFT")
  if coverText.SetWordWrap then coverText:SetWordWrap(false) end
  coverText:Hide()

  -- All-buffed pill (1.6.0): with /br pill on, the full window collapses to
  -- this small button while the group is fully buffed. It sits where the
  -- window's top-left corner is; clicking it peeks at the full window.
  local pill = CreateFrame("Button", "BuffRadarPill", UIParent,
                           BackdropTemplateMixin and "BackdropTemplate" or nil)
  pill:SetSize(150, 22)
  pill:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  if pill.SetBackdrop then
    pill:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    pill:SetBackdropColor(0.04, 0.05, 0.09, 0.92)
    pill:SetBackdropBorderColor(0.35, 0.55, 0.8, 1)
  end
  pill.text = pill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  pill.text:SetPoint("CENTER", 0, 0)
  pill.text:SetText(L["All buffed"])
  pill:SetScript("OnClick", function(self)
    X.pillPeek = GetTime() + 5
    self:Hide()
    if frame then frame:Show() end
  end)
  pill:Hide()
  X.pill = pill

  -- Toggle strip + role filter bar (1.5.0), directly under the title:
  -- your buff icons on the left (click one to toggle that buff), the role
  -- filter chips on the right. ApplyRowLayout shows/hides the bar and
  -- moves the rows below it.
  local bar = CreateFrame("Frame", nil, frame)
  bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -HEADER_H)
  bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -HEADER_H)
  bar:SetHeight(18)
  X.bar = bar
  X.stripBtns = {}
  for i = 1, 10 do
    local b = CreateFrame("Button", "BuffRadarStrip" .. i, bar)
    b:SetSize(16, 16)
    b:SetPoint("LEFT", bar, "LEFT", (i - 1) * 17, 0)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints(b)
    b:SetScript("OnClick", function(self)
      if InCombatLockdown() or not self.buffKey then return end
      db.enabled[self.buffKey] = not IsOn(self.buffKey, self.buffDefault)
      X.stripSig = nil
      if QueueRefresh then QueueRefresh() end
    end)
    b:SetScript("OnEnter", function(self)
      if not self.buffKey then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(self.buffName or self.buffKey)
      GameTooltip:AddLine(IsOn(self.buffKey, self.buffDefault) and "On -- click to turn off"
        or "Off -- click to turn on", 0.7, 0.7, 0.7)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    X.stripBtns[i] = b
  end
  X.chipBtns = {}
  local chipDefs = {
    { "ALL", "All", 26, -98 }, { "TANK", "Tank", 32, -64 },
    { "HEALER", "Heal", 32, -30 }, { "DAMAGER", "DPS", 28, 0 },
  }
  for _, cd in ipairs(chipDefs) do
    local b = CreateFrame("Button", "BuffRadarChip" .. cd[1], bar)
    b:SetSize(cd[3], 16)
    b:SetPoint("RIGHT", bar, "RIGHT", cd[4], 0)
    b.roleKey = cd[1]
    b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.fs:SetAllPoints(b)
    b.fs:SetJustifyH("CENTER")
    b.fs:SetText(cd[2])
    b:SetScript("OnClick", function(self)
      db.roleFilter = self.roleKey
      X.RefreshChips()
      if QueueRefresh then QueueRefresh() end
    end)
    X.chipBtns[#X.chipBtns + 1] = b
  end
  X.RefreshChips()

  -- Scale grips (1.11.0): drag either bottom corner to rescale the whole
  -- window (frame, rows, icons and text) together. The opposite bottom
  -- corner stays put on screen; the top edge (or bottom edge when the list
  -- grows up) stays put vertically. Width is set with /br width.
  local function MakeScaleGrip(side)
    local g = CreateFrame("Button", nil, frame)
    g:SetSize(12, 12)
    g.side = side
    local right = side == "RIGHT"
    g:SetPoint(right and "BOTTOMRIGHT" or "BOTTOMLEFT", frame, right and "BOTTOMRIGHT" or "BOTTOMLEFT",
               right and -3 or 3, 3)
    g:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    g:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    g:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight", "ADD")
    if not right then  -- mirror the right-corner art for the left corner
      local texs = { g:GetNormalTexture(), g:GetPushedTexture(), g:GetHighlightTexture() }
      for i = 1, 3 do
        if texs[i] and texs[i].SetTexCoord then texs[i]:SetTexCoord(1, 0, 0, 1) end
      end
    end
    g:SetScript("OnMouseDown", function(self, button)
      if button ~= "LeftButton" or db.locked or InCombatLockdown() then return end
      X.BeginScaleDrag(self)
    end)
    g:SetScript("OnMouseUp", function(self) X.EndScaleDrag(self) end)
    g:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, right and "ANCHOR_RIGHT" or "ANCHOR_LEFT")
      GameTooltip:AddLine(L["Drag to resize the window"])
      GameTooltip:AddLine(string.format("%d%%%s", math_floor((db.scale or 1) * 100 + 0.5),
        db.scalePerSpec and (X.spec and ("  (scale saved for " .. X.spec .. ")") or "  (per-spec scale on)") or ""),
        0.8, 0.8, 0.8)
      if db.gripSnap ~= false then GameTooltip:AddLine("Hold Shift to snap to 75 / 100 / 125 / 150%", 0.6, 0.6, 0.6) end
      GameTooltip:Show()
    end)
    g:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return g
  end
  grip = MakeScaleGrip("RIGHT")
  X.gripL = MakeScaleGrip("LEFT")

  -- Width handle (1.12.0): drag the right edge to change the list width,
  -- the job the old corner grip did. Kept clear of the corner grip.
  local edge = CreateFrame("Button", nil, frame)
  edge:SetWidth(5)
  edge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -HEADER_H)
  edge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 18)
  edge:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" or db.locked or InCombatLockdown() then return end
    frame:StartSizing("RIGHT")
    self.isSizing = true
  end)
  edge:SetScript("OnMouseUp", function(self) X.EndEdgeDrag(self) end)
  edge:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:AddLine("Drag to change the width")
    GameTooltip:Show()
  end)
  edge:SetScript("OnLeave", function() GameTooltip:Hide() end)
  X.edge = edge

  -- Name finder (1.8.0): a slim bar under the toggle strip holding one
  -- edit box; while it has text, the list shows only matching names.
  -- ApplyRowLayout positions and shows/hides it.
  local findBar = CreateFrame("Frame", nil, frame)
  findBar:SetHeight(16)
  local findLabel = findBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  findLabel:SetPoint("LEFT", 2, 0)
  findLabel:SetText("Find:")
  local findEdit = CreateFrame("EditBox", nil, findBar, "InputBoxTemplate")
  findEdit:SetSize(130, 16)
  findEdit:SetPoint("LEFT", findLabel, "RIGHT", 6, 0)
  findEdit:SetAutoFocus(false)
  findEdit:SetMaxLetters(24)
  findEdit:SetScript("OnTextChanged", function(self)
    X.search = (self:GetText() or ""):lower()
    if QueueRefresh then QueueRefresh() end
  end)
  findEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  findEdit:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
  end)
  findBar:Hide()
  X.findBar, X.findEdit = findBar, findEdit

  -- Focus watch line (1.8.0): one line about your focus target's buffs,
  -- directly above the coverage line. Refresh fills and shows it.
  local focusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  focusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 9, FOOTER_H + 17)
  focusText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, FOOTER_H + 17)
  focusText:SetJustifyH("LEFT")
  if focusText.SetWordWrap then focusText:SetWordWrap(false) end
  focusText:Hide()
  X.focusText = focusText

  for i = 1, MAX_ROWS do CreateRow(i) end

  -- Hide in combat; outside combat, Refresh decides what should be visible.
  if RegisterStateDriver then
    frame.visibilityDriver = pcall(RegisterStateDriver, frame, "visibility", "[combat] hide")
    pill.visibilityDriver = pcall(RegisterStateDriver, pill, "visibility", "[combat] hide")
  end

  local okNext, errNext = pcall(BuildNextButton)
  pcall(BuildGroupButton)
  if not okNext then Print("|cffff4040keybind button unavailable:|r " .. tostring(errNext)) end

  ApplyGeometry()
  RestorePosition()
  ApplyAppearance()
  X.ApplyRowLayout()
  UpdateCounter()
  BuildMinimapButton()
  built = true
end

---------------------------------------------------------------------------
-- Minimap button + addon compartment (block-scoped: 200-local limit)
---------------------------------------------------------------------------
do
local minimapBtn

local function MinimapRadii()
  local w = Minimap.GetWidth and Minimap:GetWidth()
  local h = Minimap.GetHeight and Minimap:GetHeight()
  return w and w > 0 and w / 2 + 5 or 80, h and h > 0 and h / 2 + 5 or 80
end

local function PositionMinimapButton()
  if not minimapBtn then return end
  local angle = math.rad((db and db.minimapAngle) or 215)
  local rx, ry = MinimapRadii()
  minimapBtn:ClearAllPoints()
  minimapBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * rx, math.sin(angle) * ry)
end

function RefreshMinimapButton()
  if not minimapBtn then return end
  if db and db.showMinimap then
    minimapBtn:Show()
    PositionMinimapButton()
  else
    minimapBtn:Hide()
  end
end

BuildMinimapButton = function()
  if minimapBtn or not Minimap then return end
  local b = CreateFrame("Button", "BuffRadarMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", 0, 1)
  icon:SetTexture("Interface\\AddOns\\BuffRadar\\Media\\icon.png")
  local border = b:CreateTexture(nil, "ARTWORK")
  border:SetSize(52, 52)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff33ccffBuff|rRadar")
    GameTooltip:AddLine(L["Left-click: show / hide the window"], 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L["Right-click: settings"], 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L["Drag: move around the minimap"], 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- A Button only receives left clicks unless told otherwise; without this the
  -- right-click-for-settings in the tooltip never fired.
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then OpenConfig()
    elseif BuffRadar_ToggleWindow then BuffRadar_ToggleWindow() end
  end)
  b:SetScript("OnDragStart", function(self) self.dragging = true end)
  b:SetScript("OnDragStop", function(self) self.dragging = false end)
  b:SetScript("OnUpdate", function(self)
    if not self.dragging or not db then return end
    local mx, my = Minimap:GetCenter()
    if not mx or not my then return end
    local cx, cy = GetCursorPosition()
    local scale = (Minimap.GetEffectiveScale and Minimap:GetEffectiveScale()) or 1
    cx, cy = cx / scale, cy / scale
    local rx, ry = MinimapRadii()
    local atan2 = math.atan2 or math.atan
    db.minimapAngle = math.deg(atan2((cy - my) / ry, (cx - mx) / rx)) % 360
    PositionMinimapButton()
  end)
  minimapBtn = b
  if Minimap.HookScript then Minimap:HookScript("OnSizeChanged", PositionMinimapButton) end
  RefreshMinimapButton()

  -- Addon compartment (the minimap's addon menu): same clicks as the minimap
  -- button. The click callback's arguments differ between client versions:
  -- newer menus pass a table with .buttonName, older dropdowns pass the mouse
  -- button as the 5th argument; anything else counts as a left click.
  if AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
    pcall(AddonCompartmentFrame.RegisterAddon, AddonCompartmentFrame, {
      text = "BuffRadar",
      icon = "Interface\\AddOns\\BuffRadar\\Media\\icon.png",
      notCheckable = true,
      registerForAnyClick = true,
      func = function(...)
        local a2, a5 = select(2, ...), select(5, ...)
        local mouse = (type(a2) == "table" and a2.buttonName) or a5
        if mouse == "RightButton" then OpenConfig()
        elseif BuffRadar_ToggleWindow then BuffRadar_ToggleWindow() end
      end,
      funcOnEnter = function(button)
        if type(button) ~= "table" then return end
        GameTooltip:SetOwner(button, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff33ccffBuff|rRadar")
        GameTooltip:AddLine(L["Left-click: show / hide the window"], 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["Right-click: settings"], 0.8, 0.8, 0.8)
        GameTooltip:Show()
      end,
      funcOnLeave = function() GameTooltip:Hide() end,
    })
  end
end
end -- minimap block

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
-- Widget writes only when the value actually changes (no redundant redraws).
local function SetTextIfChanged(fs, text)
  if fs.cText ~= text then fs.cText = text; fs:SetText(text) end
end
local function SetShownIfChanged(w, show)
  if (w:IsShown() and true or false) ~= show then
    if show then w:Show() else w:Hide() end
  end
end
-- Height changes are safe to make freely: the frame is anchored by its
-- TOPLEFT corner only (see SavePosition/RestorePosition), so growing or
-- shrinking the height moves only the bottom edge -- the list grows
-- downward and the top of the window never moves.
local function SetHeightIfChanged(f, h)
  if f.cHeight ~= h then f.cHeight = h; f:SetHeight(h) end
end

local function ClearRow(row)
  row.entry, row.guid = nil, nil
  if row:IsShown() then row:Hide() end
end

local function InvalidateRows()
  for i = 1, #rows do
    local row = rows[i]
    row.cGuid, row.cUnit, row.bGuid, row.cFar, row.cTag = nil, nil, nil, nil, nil
    row.cBar, row.cMarker, row.cFarTxt = nil, nil, nil
    row.cTint = nil
    wipe(row.cMissing)
  end
  if nextBtn then nextBtn.bGuid, nextBtn.isClear = nil, false end
end

-- The name shown on a row (1.10.0): optionally with the realm, and
-- optionally shortened.
local function DispName(e)
  local nm = (db.showRealm and e.fullName) or e.name or ""
  local trim = db.nameTrim or 0
  if trim > 0 and #nm > trim then nm = nm:sub(1, trim) .. "…" end
  return nm
end

-- Tag symbols (1.12.0): with tagSymbols on, a status tag also carries a
-- symbol, so its meaning never rests on color alone.
function X.InvalidateTags()
  for i = 1, #rows do rows[i].cTag = false end
  if QueueRefresh then QueueRefresh() end
end

X.TAGSYM = setmetatable({}, { __index = function() return "*" end })
do
  local T = X.TAGSYM
  T[L["a buff just expired"]] = "!"; T[L["recently rezzed"]] = "+"; T[L["up next"]] = ">"
  T[L["being buffed"]] = "~"; T[L["your assignment"]] = "#"; T[L["assigned elsewhere"]] = "x"
  T[L["buddy's watch"]] = "&"; T[L["pinned"]] = "^"; T[L["weapon enchant missing"]] = "/"
  T[L["drinking"]] = "o"; T[L["asked for a buff"]] = "?"; T[L["pet"]] = "p"
end

local function RenderRow(row, e)
  row.entry, row.guid = e, e.guid
  local m = e.missing
  if row.cGuid ~= e.guid or row.cUnit ~= e.unit then
    -- 3D portrait render: only for a new player/token. Guarded like the rest of
    -- this file: if a build renames or restricts it, the row still renders.
    if SetPortraitTexture then pcall(SetPortraitTexture, row.portrait, e.unit) end
    row.name:SetText(DispName(e))
    row.cGuid, row.cUnit = e.guid, e.unit
    row.cFar = nil  -- new player on this row: set color and layout below
  end
  -- In range: class-colored name centered on the row. Out of range: grey name
  -- moved up, with "out of range" under it. (Before 1.3.2 the grey stayed
  -- after the player came back into range.)
  local far = e.outOfRange and true or false
  if row.cFar ~= far then
    row.cFar = far
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row.portrait, "RIGHT", 6, far and 5 or 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -(IconInset()), far and 5 or 0)
    row.far:SetShown(far)
    if far then row.name:SetTextColor(0.55, 0.55, 0.55)
    elseif db.classColors then row.name:SetTextColor(ClassColor(e.class))
    else row.name:SetTextColor(0.92, 0.92, 0.92) end
  end
  -- Status tag: a rezzed player (lost every buff) is marked under the name;
  -- the name shifts up for it just like the out-of-range layout, minus grey.
  local tag
  if not far then
    if e.expired then tag = L["a buff just expired"]
    elseif e.rezzed then tag = L["recently rezzed"]
    elseif e.queued then tag = L["up next"]
    elseif e.handled then tag = L["being buffed"]
    elseif e.mine then tag = L["your assignment"]
    elseif e.theirs then tag = L["assigned elsewhere"]
    elseif e.buddy then tag = L["buddy's watch"]
    elseif e.pinned then tag = L["pinned"]
    elseif e.weapon then tag = L["weapon enchant missing"]
    elseif e.drinking then tag = L["drinking"]
    elseif e.asked then tag = L["asked for a buff"]
    elseif e.pet then tag = L["pet"] end
  end
  if tag and db.tagSymbols then
    tag = (X.TAGSYM[tag] or "*") .. " " .. tag
  end
  if not tag and e.remain1 then
    tag = e.remain1 >= 90 and string_format(L["~%dm left"], math_floor(e.remain1 / 60))
      or string_format(L["~%ds left"], math_floor(e.remain1))
  end
  if row.cTag ~= tag then
    row.cTag = tag
    if tag then
      row.tag:SetText(tag)
      row.name:ClearAllPoints()
      row.name:SetPoint("LEFT", row.portrait, "RIGHT", 6, 5)
      row.name:SetPoint("RIGHT", row, "RIGHT", -(IconInset()), 5)
      row.tag:Show()
    else
      row.tag:Hide()
      if not far then
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", row.portrait, "RIGHT", 6, 0)
        row.name:SetPoint("RIGHT", row, "RIGHT", -(IconInset()), 0)
      end
    end
  end
  -- Range band in words (1.8.0): a greyed row in group range reads
  -- "near" instead of "out of range" when the setting is on.
  local farTxt = far and (db.rangeText and e.rangeBucket == 1 and L["near"] or L["out of range"]) or nil
  if row.cFarTxt ~= farTxt then
    row.cFarTxt = farTxt
    if farTxt then row.far:SetText(farTxt) end
  end
  -- Duration bar (1.8.0): the expiring buff's remaining time as a share
  -- of 30 minutes; the color band shifts green -> yellow -> red.
  local barKey
  if db.durationBars and e.remain1 and e.remain1 < math_huge then
    local frac = math_min(1, e.remain1 / 1800)
    local band = e.remain1 < 300 and 1 or (e.remain1 < 900 and 2 or 3)
    barKey = math_floor(frac * 40) .. ":" .. band
    if row.cBar ~= barKey then
      row.cBar = barKey
      row.bar:SetWidth(math_max(2, (row:GetWidth() - 4) * frac))
      if band == 1 then row.bar:SetVertexColor(1, 0.3, 0.3)
      elseif band == 2 then row.bar:SetVertexColor(1, 0.85, 0.4)
      else row.bar:SetVertexColor(0.4, 0.9, 0.4) end
      row.bar:Show()
    end
  end
  if not barKey then
    -- Unconditional: InvalidateRows clears the cache without touching
    -- the texture, so the hide can't ride on the cache alone.
    row.cBar = nil
    row.bar:Hide()
  end
  -- Raid marker badge (1.8.0).
  local mk = (db.raidMarkers and e.marker) or nil
  if row.cMarker ~= mk then
    row.cMarker = mk
    if mk then
      row.marker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. mk)
      row.marker:Show()
    else
      row.marker:Hide()
    end
  end
  if not mk then row.marker:Hide() end
  -- Row color mark (1.10.0): a colored strip on the row's left edge for
  -- the first matching rule you switched on — yours, tanks, expiring
  -- soon, your split partner's half.
  local tint
  local rc = db.rowColors
  if rc then
    if rc.mine and e.mine then tint = rc.mine
    elseif rc.tank and e.role == 1 then tint = rc.tank
    elseif rc.expiring and (e.expired or (e.remain1 and e.remain1 < 300)) then tint = rc.expiring
    elseif rc.buddy and e.buddy then tint = rc.buddy end
  end
  if row.cTint ~= tint then
    row.cTint = tint
    if tint then
      row.tint:SetVertexColor(tint[1], tint[2], tint[3])
      row.tint:Show()
    else
      row.tint:Hide()
    end
  end
  if not tint then row.tint:Hide() end
  local cm, changed = row.cMissing, false
  for j = 1, MAX_ICONS do
    if cm[j] ~= m[j] then changed = true; break end
  end
  if changed then
    for j = 1, MAX_ICONS do
      local t, spell = row.icons[j], m[j]
      if spell then
        t:SetTexture(SpellIcon(spell))
        t:SetAlpha(j == 1 and 1 or 0.5)
        t:Show()
      else
        t:Hide()
      end
      cm[j] = spell
    end
  end
  if e.outOfRange then
    -- Greyed placeholder row: no live binding behind the click, and the
    -- cached binding is cleared so a reused row can't cast a stale target.
    row:SetAlpha(0.6)
    if row.bGuid ~= nil then X.ClearRowCast(row) end
  else
    row:SetAlpha(1)
    BindCached(row, e.unit, m[1], e.guid)
  end
  if not row:IsShown() then row:Show() end
end

-- Row color marks (1.10.0): named colors for the row edge strip.
X.ROW_PALETTE = {
  gold = { 1, 0.8, 0.2 }, sky = { 0.4, 0.7, 1 }, red = { 1, 0.35, 0.35 },
  green = { 0.45, 0.95, 0.45 }, violet = { 0.75, 0.5, 1 },
}
X.ROW_PALETTE_ORDER = { "gold", "sky", "red", "green", "violet" }

function X.RowColorName(rule)
  local c = db.rowColors and db.rowColors[rule]
  if not c then return "off" end
  for name, rgb in pairs(X.ROW_PALETTE) do
    if rgb[1] == c[1] and rgb[2] == c[2] and rgb[3] == c[3] then return name end
  end
  return "custom"
end

function X.SetRowColor(rule, c)
  db.rowColors = db.rowColors or {}
  db.rowColors[rule] = c and { c[1], c[2], c[3] } or nil
  InvalidateRows()
  if QueueRefresh then QueueRefresh() end
end

-- Shared look for the "nothing to list" states (no buffs known / paused in a city).
local function ShowStatus(text)
  if X.pill then SetShownIfChanged(X.pill, false) end
  if X.focusText then SetShownIfChanged(X.focusText, false) end
  SetShownIfChanged(coverText, false)
  SetTextIfChanged(countText, "")
  SetShownIfChanged(overflowText, false)
  SetTextIfChanged(emptyText, text)
  SetShownIfChanged(emptyText, true)
  UpdateCounter()
  SetHeightIfChanged(frame, (X.topH or HEADER_H) + 26 + FOOTER_H)
  SetShownIfChanged(frame, true)
end

-- Pick an honest explanation for an empty list when the client cannot verify range.
function X.EmptyStatus()
  if (X.tallyUnknownUnits or 0) > 0 then
    return L["Some buff information is unavailable."]
  end
  if X.FriendlyPlatesOn() == false then
    return L["Friendly nameplates are off."]
  end
  if X.rangeSilent then
    return L["Range could not be confirmed; the list may be incomplete."]
  end
  return L["Everyone nearby is buffed."]
end

-- True while the last refresh found nothing that time alone can change: no
-- supported buffs known, or scanning paused (city / battleground). The steady
-- timer skips its refreshes then; events (zone changes, learning a spell,
-- settings changes) still refresh right away and clear it.
local refreshIdle = false

-- Coverage-line parts (1.10.0): the line is assembled from parts, each
-- with its own switch in db.coverParts; absent means on.
local function CoverOn(part)
  local cp = db and db.coverParts
  return not cp or cp[part] ~= false
end

-- Group-by-buff view (1.10.0): fold the people entries into one row
-- per buff still needed. Each folded row stands for the buff itself:
-- its name carries the count, and it borrows an in-range holder (if
-- any) as its cast target, so clicking the row buffs that player with
-- exactly that spell. Only the render stage uses the folded list --
-- coverage, sounds and reports keep working on people.
function X.BuildBuffView(list, n)
  local bySpell, order = {}, {}
  for i = 1, n do
    local e = list[i]
    if not e.header then
      for j = 1, #(e.missing or {}) do
        local spell = e.missing[j]
        local g = bySpell[spell]
        if not g then
          g = { spell = spell, count = 0, missing = { spell }, group = true }
          bySpell[spell] = g
          order[#order + 1] = g
        end
        g.count = g.count + 1
        if (not e.outOfRange and (g.unit == nil or g.outOfRange)) or g.unit == nil then
          g.unit, g.class = e.unit, e.class
          g.outOfRange = e.outOfRange and true or false
          g.rangeBucket, g.approximateRange = e.rangeBucket, e.approximateRange
        end
      end
    end
  end
  table_sort(order, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.spell < b.spell
  end)
  for i = 1, #order do
    local g = order[i]
    g.name = g.count > 1 and (g.spell .. " x" .. g.count) or g.spell
    g.sortName = g.spell
    g.guid = "buff:" .. g.spell .. "#" .. g.count
  end
  return order, #order
end

X.IsMajorCity, X.CurrentInstance = InMajorCity, InInstanceNow
X.BindCached = BindCached

local function Refresh()
  if not built or InCombatLockdown() then return end
  refreshIdle = false
  X.applyFilter = true  -- the window honors the role filter; reports turn it off
  local wasAfterCombat = X.afterCombat
  X.afterCombat = nil
  X.afterCombatScan = wasAfterCombat or nil
  if X.flashPending then ApplyAppearance() end

  if not hasAnyBuff then
    refreshIdle = true
    ClearNext()
    X.ClearGroup()
    for i = 1, MAX_ROWS do ClearRow(rows[i]) end
    if sessionShow and not db.hidden then
      ShowStatus(L["No supported buffs in your spellbook."])
    else
      SetShownIfChanged(frame, false)
      if X.pill then SetShownIfChanged(X.pill, false) end
    end
    return
  end

  local groupHidden = db.groupOnly and not InGroup()

  -- No scanning in major cities
  if db.pauseInCities and X.IsMajorCity() then
    refreshIdle = true
    ClearNext()
    X.ClearGroup()
    wipe(X.listedBefore)
    for i = 1, MAX_ROWS do ClearRow(rows[i]) end
    if db.hidden or groupHidden or db.autoHide then
      SetShownIfChanged(frame, false)
    else
      ShowStatus(L["Paused in a major city."])
    end
    return
  end

  -- No scanning in battlegrounds / arenas (optional; flag rules make lists noisy)
  local instType = X.CurrentInstance()
  if db.pauseInBG and (instType == "pvp" or instType == "arena") then
    refreshIdle = true
    ClearNext()
    X.ClearGroup()
    wipe(X.listedBefore)
    for i = 1, MAX_ROWS do ClearRow(rows[i]) end
    if db.hidden or groupHidden or db.autoHide then
      SetShownIfChanged(frame, false)
    else
      ShowStatus(L["Paused in a battleground."])
    end
    return
  end

  -- No scanning on a flight path (optional): you can't cast mid-flight.
  if db.pauseTaxi and _G.UnitOnTaxi then
    local ok, onTaxi = pcall(_G.UnitOnTaxi, "player")
    if ok and onTaxi then
      refreshIdle = true
      ClearNext()
    X.ClearGroup()
      wipe(X.listedBefore)
      for i = 1, MAX_ROWS do ClearRow(rows[i]) end
      if db.hidden or groupHidden or db.autoHide then
        SetShownIfChanged(frame, false)
      else
        ShowStatus(L["Paused on a flight path."])
      end
      return
    end
  end

  -- Low-mana pause (optional): don't offer buffs you can't afford to cast.
  if db.lowMana and db.lowMana > 0 and X.LowMana() then
      ClearNext()
      X.ClearGroup()
      wipe(X.listedBefore)
      for i = 1, MAX_ROWS do ClearRow(rows[i]) end
      if db.hidden or groupHidden or db.autoHide then
        SetShownIfChanged(frame, false)
      else
        ShowStatus(L["Low mana -- buffing paused."])
      end
      return
  end

  local n = CollectEntries()
  X.CheckDrops()
  X.CheckRange()
  X.CheckFalls()
  X.UpdateTitleMarks()
  X.RefreshStrip()
  X.RefreshChips()

  -- Group-cast mode: if enough group members need the same group-castable
  -- buff, the first such row offers the group version instead (one cast
  -- covers the party). Only the first matching row is converted.
  if db.groupCast and n > 0 then
    local tally = {}
    for i = 1, n do
      local e = entries[i]
      if e.group and not e.isSelf and not e.outOfRange then
        for _, spell in ipairs(e.missing) do
          for _, b in ipairs(myBuffs) do
            if b.name == spell and b.groupName then
              tally[b.key] = (tally[b.key] or 0) + 1
            end
          end
        end
      end
    end
    for i = 1, n do
      local e = entries[i]
      if e.outOfRange then break end
      local converted = false
      for _, b in ipairs(myBuffs) do
        if b.name == e.missing[1] and b.groupName
           and (tally[b.key] or 0) >= (db.groupCastMin or 3) then
          e.missing[1] = b.groupName
          e.groupCast = true
          converted = true
          break
        end
      end
      if converted then break end
    end
  end

  -- Keybind / macro target: first player in the list, their next missing buff.
  if n > 0 and nextBtn and not entries[1].outOfRange then
    local first = entries[1]
    nextBtn.entry = X.BindCached(nextBtn, first.unit, first.missing[1], first.guid) and first or nil
    X.ArmGroupBtn(first)
  else
    ClearNext()
    X.ClearGroup()
  end

  if db.hidden or groupHidden then
    SetShownIfChanged(frame, false)
    if X.pill then SetShownIfChanged(X.pill, false) end
    wipe(X.listedBefore)
    return
  end

  -- Droplet sound when someone new appears on the board
  local now, newName = GetTime(), false
  local listedNow = (X.listedBefore == X.listA) and X.listB or X.listA
  wipe(listedNow)
  for i = 1, n do
    local guid = entries[i].guid
    listedNow[guid] = true
    -- (greyed out-of-range rows don't ding: they're not castable yet)
    if not entries[i].outOfRange and not X.listedBefore[guid] then
      local gone = X.recentlyGone[guid]
      if not gone or now - gone > 10 then newName = true end
    end
  end
  for guid in pairs(X.listedBefore) do
    if not listedNow[guid] then X.recentlyGone[guid] = now end
  end
  for guid, t in pairs(X.recentlyGone) do
    if now - t > 60 then X.recentlyGone[guid] = nil end
  end
  X.listedBefore = listedNow
  if newName and db.playSound and now - lastSoundAt > 1 then
    lastSoundAt = now
    PlayAlert("new")
  end

  -- group-by-buff view folds the render list; everything above this
  -- point (coverage, sounds, counts) still works on people
  local viewEntries, viewN = entries, n
  if db.viewMode == "buffs" then viewEntries, viewN = X.BuildBuffView(entries, n) end
  local shown = math_min(viewN, MAX_ROWS)
  -- Two-column layout (1.9.0): with the setting on and a long list, the
  -- rows split into two columns and the frame widens to match. The
  -- column state lives on X so ApplyRowLayout anchors consistently.
  local wantCols = (db.twoCol and shown > 8) and 2 or 1
  local rowsTall = wantCols == 2 and math_floor((shown + 1) / 2) or shown
  if wantCols ~= (X.cols or 1) or rowsTall ~= (X.rowsTall or shown) then
    X.cols, X.rowsTall = wantCols, rowsTall
    X.rowsPerCol = wantCols == 2 and rowsTall or MAX_ROWS
    X.ApplyRowLayout()
    ApplyGeometry()
  end
  for i = 1, MAX_ROWS do
    if i <= shown then RenderRow(rows[i], viewEntries[i]) else ClearRow(rows[i]) end
  end
  -- Post-combat catch-up: one border pulse when the frozen list thaws with
  -- work waiting, so a pull's-end rebuff round doesn't go unnoticed.
  if wasAfterCombat and n > 0 and X.Flash then X.Flash() end

  SetTextIfChanged(countText, n > 0 and n or "")
  if n == 0 then
    SetTextIfChanged(emptyText, X.EmptyStatus())
  end
  SetShownIfChanged(emptyText, n == 0)
  if viewN > MAX_ROWS then
    if overflowText.cTall ~= rowsTall then  -- re-anchor when the column split changes (1.9.0)
      overflowText.cTall = rowsTall
      overflowText:ClearAllPoints()
      overflowText:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -(X.topH or HEADER_H) - rowsTall * (X.rowH or ROW_H) - math_max(0, rowsTall - 1) * (db.rowGap or 0) - 2)
    end
    if overflowText.cCount ~= viewN then
      overflowText.cCount = viewN
      overflowText:SetText(string_format(L["+%d more"], viewN - MAX_ROWS))
    end
    SetShownIfChanged(overflowText, true)
  else
    SetShownIfChanged(overflowText, false)
  end

  -- Coverage / progress line: shown while grouped (even when the list is
  -- empty -- "15/15 fully buffed" is the good-news form of the same line).
  local coverShown = false
  if X.tallyUnits > 1 or (X.tallyUnits > 0 and X.tallyUnknownUnits > 0) then
    local parts = {}
    if CoverOn("progress") then
      parts[#parts + 1] = string_format("%d/%d fully buffed", X.tallyUnits - X.tallyMissingUnits, X.tallyUnits)
    end
    if CoverOn("buffs") then
    for _, b in ipairs(myBuffs) do
      local t = not b.self and X.tally[b.key] or nil
      if t and t.total > 0 then
        local nm = b.key:lower():gsub("_", " ")
        local seg = string_format("%s %d/%d", nm:sub(1, 1):upper() .. nm:sub(2),
          t.total - t.miss, t.total)
        -- A buff on a real cooldown is never counted as missing (you can't
        -- cast it anyway), so its count can look complete while people
        -- still need it -- flag the cooldown so the number isn't trusted
        -- blindly.
        local left = CooldownLeft(b.name)
        if left > 5 then
          seg = seg .. (left >= 60 and string_format(" (~%dm cd)", math_floor(left / 60 + 0.5))
                        or string_format(" (~%ds cd)", math_floor(left + 0.5)))
        end
        parts[#parts + 1] = seg
      end
    end
    local tb = X.tally.BLESSINGS
    if tb and tb.total > 0 then
      parts[#parts + 1] = string_format("Blessings %d/%d", tb.total - tb.miss, tb.total)
    end
    end
    if db.consumables then
      for _, cd in ipairs(X.CONS_DEFS) do
        local t = X.consTally[cd.key]
        if t and t.total > 0 then
          parts[#parts + 1] = string_format("%s %d/%d", cd.label, t.total - t.miss, t.total)
        end
      end
    end
    -- Coverage uptime (1.6.0): the share of grouped scans this run that
    -- found nobody missing anything. A scan-based score, reset when a
    -- Mythic+ run starts and when the group ends.
    if X.tallyUnknownUnits == 0 then
      X.upTotal = X.upTotal + 1
      if X.tallyMissingUnits == 0 then X.upFull = X.upFull + 1 end
    end
    if X.upTotal >= 10 and CoverOn("uptime") then
      parts[#parts + 1] = string_format("Uptime %d%%",
        math_floor(100 * X.upFull / X.upTotal + 0.5))
    end
    -- Coverage roster (1.7.0): which BuffRadar users are on duty, how
    -- many assignments each holds, and who is covered (dead/AFK) —
    -- so a group can see the buffing is staffed at a glance.
    if db.sync then
      local nowC = GetTime()
      -- Assignment counts keyed by short name: holders are recorded as
      -- typed (often short), users are known by full name.
      local held = {}
      for _, who in pairs(X.assign) do
        local wk = Ignore.Key(who:match("^[^%-]+") or who)
        held[wk] = (held[wk] or 0) + 1
      end
      local duty = {}
      local meF = Ignore.UnitNames("player")
      if meF then
        local mk = Ignore.Key(meF:match("^[^%-]+") or meF)
        duty[#duty + 1] = (meF:match("^[^%-]+") or meF)
          .. (held[mk] and (" (" .. held[mk] .. ")") or "")
      end
      local peerNames = {}
      for k, p in pairs(X.peers) do
        if nowC - p.t < 90 then peerNames[#peerNames + 1] = k end
      end
      table_sort(peerNames)
      for _, k in ipairs(peerNames) do
        local p = X.peers[k]
        local short = (p.name:match("^[^%-]+") or p.name)
        for cname, exp in pairs(X.cover) do
          if exp > nowC and X.SameUser(p.name, cname) then
            short = short .. " (away)" break
          end
        end
        local hk = Ignore.Key(p.name:match("^[^%-]+") or p.name)
        if held[hk] then short = short .. " (" .. held[hk] .. ")" end
        duty[#duty + 1] = short
      end
      if #duty > 1 and CoverOn("roster") then
        parts[#parts + 1] = "Radar: " .. table.concat(duty, ", ")
      end
    end
    -- Group expiry warning (1.7.0): a group buff inside its last five
    -- minutes on at least half its holders is about to become the
    -- whole list — say so while there's time to refresh it calmly.
    local worstKey, worstSoon, worstTotal = nil, 0, 0
    for key, soon in pairs(X.expiryTally) do
      local t = X.tally[key]
      if t and soon >= 3 and soon * 2 >= t.total and soon > worstSoon then
        worstKey, worstSoon, worstTotal = key, soon, t.total
      end
    end
    if worstKey and CoverOn("expiry") then
      local nm = worstKey == "BLESSINGS" and "Blessings" or worstKey
      if worstKey ~= "BLESSINGS" then
        for _, def in ipairs(myBuffs) do
          if def.key == worstKey then nm = def.name break end
        end
      end
      parts[#parts + 1] = string_format("%s <5m on %d/%d", nm, worstSoon, worstTotal)
    end
    -- Weapon watch (1.7.0): when your own row isn't on the list to
    -- carry the tag, the coverage line carries the reminder instead.
    if db.weaponWatch and X.WeaponEnchantMissing() then
      local selfListed = false
      for i = 1, nEntries do
        if entries[i].isSelf then selfListed = true break end
      end
      if not selfListed then
        parts[#parts + 1] = "your weapon has no enchant"
      end
    end
    -- World-buff watch (1.8.0): your active world buffs, with time left.
    if db.worldWatch and CoverOn("world") then
      local wb = X.WorldBuffsText()
      if wb then parts[#parts + 1] = wb end
    end
    -- Healer drinking (1.8.0): healers sitting down to drink between
    -- pulls — the group waits for them, not the other way round.
    if db.drinkWatch and CoverOn("drink") and (X.drinkHealers or 0) > 0 then
      parts[#parts + 1] = X.drinkHealers == 1 and "Healer drinking"
        or string_format("%d healers drinking", X.drinkHealers)
    end
    -- Pull countdown (1.15.0): while a pull timer runs (Extras tracks it
    -- in X.pull), the coverage line itself counts down -- the part of the
    -- pull-timer feature 1.14.0 trimmed. The steady ticker rebuilds this
    -- line every 0.4s while the list is live, and Extras refreshes again
    -- the moment the timer ends, so the number never goes stale.
    if X.pull and X.pull.endsAt then
      local left = math_ceil(X.pull.endsAt - GetTime())
      if left > 0 then parts[#parts + 1] = string_format("Pull in %ds", left) end
    end
    SetTextIfChanged(coverText, table.concat(parts, "  ·  "))
    X.coverFrac = string_format("%d/%d", X.tallyUnits - X.tallyMissingUnits, X.tallyUnits)
    coverShown = #parts > 0
  end
  SetShownIfChanged(coverText, coverShown)

  -- Focus watch (1.8.0): what your focus target still needs, on its own
  -- line above the coverage line. Missing() runs with isGroup=false, so
  -- the focus never touches the coverage tallies.
  local focusShown = false
  local focusValid, focusSelf
  if db.focusWatch and X.focusText then focusValid, focusSelf = Valid("focus") end
  if focusValid then
    local fname = SafeString(UnitName("focus"))
    if fname then
      local fn = Missing("focus", X.focusMiss, false, focusSelf)
      if fn > 0 then
        local fparts = {}
        for i = 1, math_min(fn, 3) do fparts[#fparts + 1] = X.focusMiss[i] end
        SetTextIfChanged(X.focusText, "Focus " .. fname .. ": needs "
          .. table.concat(fparts, ", ") .. (fn > 3 and (" +" .. (fn - 3)) or ""))
      elseif not X.auraUnknown then
        SetTextIfChanged(X.focusText, "Focus " .. fname .. ": buffed")
      end
      focusShown = fn > 0 or not X.auraUnknown
    end
  end
  if X.focusText then SetShownIfChanged(X.focusText, focusShown) end

  local h = (X.topH or HEADER_H) + (shown > 0 and rowsTall * (X.rowH or ROW_H) + math_max(0, rowsTall - 1) * (db.rowGap or 0) or 18) + 8
  if coverShown then h = h + 13 end
  if focusShown then h = h + 13 end
  if n > MAX_ROWS then h = h + 14 end
  h = h + FOOTER_H  -- bottom row: settings gear + cast counter
  UpdateCounter()
  SetHeightIfChanged(frame, h)

  -- All-buffed pill (1.6.0): in a group with nobody missing anything, the
  -- window can collapse to the pill until someone needs a buff again (or
  -- the pill is clicked for a peek).
  local pillMode = db.pill and n == 0 and InGroup() and not db.hidden
    and not groupHidden and GetTime() > (X.pillPeek or 0)
  if pillMode and X.pill then
    SetTextIfChanged(X.pill.text, "|cff33ccffBuff|rRadar · "
      .. (X.coverFrac and (X.coverFrac .. " ") or "") .. L["All buffed"])
    SetShownIfChanged(frame, false)
    SetShownIfChanged(X.pill, true)
  else
    if X.pill then SetShownIfChanged(X.pill, false) end
    SetShownIfChanged(frame, not (db.autoHide and n == 0 and not sessionShow))
  end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local driver = CreateFrame("Frame")
local refreshQueued = false
local ticker

X.perf = { n = 0, total = 0, max = 0, last = 0 }
local function SafeRefresh()
  local t0 = debugprofilestop and debugprofilestop()
  local ok, err = pcall(Refresh)
  if t0 then
    local dt = debugprofilestop() - t0
    local pf = X.perf
    pf.n, pf.total, pf.last = pf.n + 1, pf.total + dt, dt
    if dt > pf.max then pf.max = dt end
  end
  if not ok and err ~= lastError then
    lastError = err
    Print("|cffff4040error:|r " .. tostring(err))
  end
end

-- Steady refresh every UPDATE_INTERVAL via C_Timer; bursts of events (UNIT_AURA storms in
-- raids, nameplates popping in) collapse into a single refresh SOON_DELAY later.
-- How many players are in my group, me included (0 when solo)?
local function GroupSize()
  if GetNumGroupMembers then
    local ok, n = pcall(GetNumGroupMembers)
    if ok and type(n) == "number" then return n end
  end
  if GetNumRaidMembers then
    local ok, n = pcall(GetNumRaidMembers)
    if ok and type(n) == "number" and n > 0 then return n end
  end
  if GetNumPartyMembers then
    local ok, n = pcall(GetNumPartyMembers)
    if ok and type(n) == "number" then return n > 0 and n + 1 or 0 end
  end
  return 0
end

-- Scan throttle (1.7.0): in very large groups the steady rescan runs at
-- half rate. Event-driven refreshes are never throttled.
local function ScanThrottled()
  return db and db.scanThrottle and GroupSize() > 20
end

local Soon, StartTicker
if C_Timer and C_Timer.NewTicker and C_Timer.After then
  -- Only the queued callback clears its own flag, so ticker refreshes can't spawn
  -- extra parallel chains of queued refreshes.
  local function QueuedRefresh()
    refreshQueued = false
    SafeRefresh()
  end
  Soon = function()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(SOON_DELAY, QueuedRefresh)
  end
  -- The steady tick catches what no event reports (players walking in and out
  -- of range, buffs running low, cooldowns ending); it has nothing to do while
  -- Refresh() reports idle, and in combat, when Refresh() can't run anyway.
  local function TickRefresh()
    X.UpdateFade()
    if refreshIdle or InCombatLockdown() then return end
    if ScanThrottled() then
      X.tickSkip = not X.tickSkip
      if X.tickSkip then return end
    end
    SafeRefresh()
  end
  StartTicker = function()
    if not ticker then ticker = C_Timer.NewTicker(UPDATE_INTERVAL, TickRefresh) end
  end
else
  -- Fallback for clients without C_Timer: throttled accumulator, never per-frame work.
  -- soonPending marks an event-driven refresh, which runs even while idle.
  local elapsed, soonPending = 0, false
  StartTicker = function()
    driver:SetScript("OnUpdate", function(_, dt)
      elapsed = elapsed + dt
      if elapsed >= (ScanThrottled() and UPDATE_INTERVAL * 2 or UPDATE_INTERVAL) then
        elapsed = 0
        X.UpdateFade()
        if soonPending or not refreshIdle then
          soonPending = false
          SafeRefresh()
        end
      end
    end)
  end
  Soon = function()
    soonPending = true
    if elapsed < UPDATE_INTERVAL - SOON_DELAY then elapsed = UPDATE_INTERVAL - SOON_DELAY end
  end
end
QueueRefresh = Soon

-- Spellbook changes arrive in bursts (SPELLS_CHANGED can fire many times in a row):
-- rebuild the buff list once, shortly after the burst.
local rebuildQueued = false
local function RebuildNow()
  rebuildQueued = false
  if not db then return end
  wipe(iconCache)
  local ok, err = pcall(BuildBuffList)
  if not ok then Print("|cffff4040error reading spellbook:|r " .. tostring(err)) end
  X.prioDirty = true
  if built then InvalidateRows() end
  if built then X.ApplyRowLayout() end
  if RefreshConfig then RefreshConfig() end
  Soon()
end
local function ScheduleRebuild()
  if rebuildQueued then return end
  rebuildQueued = true
  if C_Timer and C_Timer.After then C_Timer.After(0.25, RebuildNow) else RebuildNow() end
end

-- Spell names come from the client cache. On a cold cache, ask for the data and rebuild
-- when it arrives (until then the English fallback names are used).
local watchedSpells = {}
local function WantSpell(id)
  if type(id) ~= "number" or not (C_Spell and C_Spell.RequestLoadSpellData) then return end
  local cached = true
  if C_Spell.IsSpellDataCached then
    local ok, c = pcall(C_Spell.IsSpellDataCached, id)
    cached = ok and c and true or false
  end
  if not cached then
    watchedSpells[id] = true
    pcall(C_Spell.RequestLoadSpellData, id)
  end
end
local function RequestSpellData()
  for _, d in ipairs(BUFF_DEFS) do
    WantSpell(d.id)
    if d.groupCast then WantSpell(d.groupCast[1]) end
    if d.choices then for _, c in ipairs(d.choices) do WantSpell(c[1]) end end
    if d.also then for _, a in ipairs(d.also) do WantSpell(a[1]) end end
  end
  for _, b in pairs(CLASSIC_FEATURES and BLESSINGS or {}) do
    WantSpell(b.id)
    WantSpell(b.greater[1])
  end
end

-- Register events one at a time and ignore any this client doesn't have
-- (newer clients throw an error for unknown event names, which would stop the whole file).
for _, ev in ipairs({
  "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
  "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE",
  "GROUP_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE",
  "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "UNIT_AURA", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
  "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UI_ERROR_MESSAGE",
  "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "CVAR_UPDATE", "UPDATE_BINDINGS",
  "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
  "SPELL_DATA_LOAD_RESULT", "UNIT_PORTRAIT_UPDATE",
  "READY_CHECK", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED",
  "CHAT_MSG_ADDON", "CHAT_MSG_WHISPER", "CHAT_MSG_SAY", "CHALLENGE_MODE_START",
  "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_FLAGS_CHANGED",
  "PLAYER_FOCUS_CHANGED",
}) do
  pcall(driver.RegisterEvent, driver, ev)
end

driver:SetScript("OnEvent", function(_, event, arg1, ...)
  -- The busiest events, filtered first. They only ever lead to a list refresh:
  --  * in combat the list is frozen and PLAYER_REGEN_ENABLED refreshes it
  --    afterwards, so they're dropped outright;
  --  * UNIT_AURA also fires for units BuffRadar never lists (enemy and NPC
  --    nameplates, pets, bosses, arena opponents) -- those are dropped too.
  if event == "UNIT_AURA" or event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED"
     or event == "UPDATE_MOUSEOVER_UNIT" then
    if InCombatLockdown() then return end
    if event == "UNIT_AURA" and not X.AuraEventNeedsRefresh(arg1, ...) then return end
    Soon()
    return
  end
  if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
    if arg1 == ADDON then
      Print("|cffff4040the game blocked a BuffRadar action|r (" .. event .. ": " ..
        tostring((...)) .. "). Please send this line to the developer.")
    end
    return
  end
  if event == "UNIT_SPELLCAST_SENT" or event == "UNIT_SPELLCAST_SUCCEEDED"
     or event == "UI_ERROR_MESSAGE" then
    if db and db.clickDebug and (event == "UI_ERROR_MESSAGE" or arg1 == "player") then
      local parts = { SafeString(arg1) or "?" }  -- "?" = nil or protected
      for i = 1, select("#", ...) do parts[#parts + 1] = SafeString((select(i, ...))) or "?" end
      Print("|cffaaaaaa" .. event .. ": " .. table.concat(parts, ", ") .. "|r")
    end
    if event == "UI_ERROR_MESSAGE" and X.pendingCast then
      local pending = X.pendingCast
      if GetTime() - pending.time < 4 then
        local message = type(arg1) == "string" and arg1 or ""
        for i = 1, select("#", ...) do
          local part = select(i, ...)
          if type(part) == "string" then message = message .. " " .. part end
        end
        if X.IsTargetCastFailure(message) then
          if X.SkipPendingCast() then Soon() end
        end
      end
      return
    end
    if event ~= "UNIT_SPELLCAST_SUCCEEDED" or arg1 ~= "player" then return end
    if arg1 == "player" and X.pendingCast and db then
      local spellID = select(2, ...)
      local ok, name = pcall(SpellName, spellID, nil)
      name = ok and SafeString(name) or nil  -- compared and used as a stats key
      if name and name == X.pendingCast.spell and GetTime() - X.pendingCast.time < 3 then
        local pk, pg, pw = X.pendingCast.key, X.pendingCast.guid, X.pendingCast.who
        X.pendingCast = nil
        X.failedTargets[pg] = nil
        X.sessionCasts = X.sessionCasts + 1
        db.castsTotal = (db.castsTotal or 0) + 1
        db.stats = db.stats or {}
        db.stats[name] = (db.stats[name] or 0) + 1
        -- Cast history (1.7.0): the last 50 casts through BuffRadar.
        db.history = db.history or {}
        db.history[#db.history + 1] = { t = (time and time()) or 0, spell = name,
                                        who = (pw and pw ~= "") and pw or "?" }
        while #db.history > 50 do table.remove(db.history, 1) end
        UpdateCounter()
        if pk and pg then X.SyncSend(pk, pg) end
        X.queueAt = GetTime()  -- the new top row is "up next" for a moment (1.6.0)
      end
    end
    Soon()
    return
  end
  if event == "CVAR_UPDATE" then
    if arg1 == "ActionButtonUseKeyDown" or arg1 == "ACTION_BUTTON_USE_KEY_DOWN" then
      ApplyNextRegistration()
      if db then pcall(MakeMacro, true) end -- keep an existing BuffRadar macro in sync
    elseif type(arg1) == "string" then
      local name = arg1:lower()
      if name == "nameplateshowfriendlyplayers" or name == "nameplateshowfriends" or name == "nameplateshowall" then
        Soon()
      end
    end
    return
  elseif event == "UPDATE_BINDINGS" then
    if RefreshConfig then RefreshConfig() end
    return
  elseif event == "SPELL_DATA_LOAD_RESULT" then
    if watchedSpells[arg1] then
      watchedSpells[arg1] = nil
      ScheduleRebuild()
    end
    return
  elseif event == "READY_CHECK" then
    if db then X.ReadyReport() end
    return
  elseif event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
    if db then X.SpecSwap(); Soon() end
    return
  elseif event == "UNIT_PORTRAIT_UPDATE" then
    for i = 1, #rows do
      if rows[i].cUnit == arg1 then rows[i].cGuid = nil end  -- redraw that portrait
    end
    Soon()
    return
  end
  if event == "CHAT_MSG_ADDON" then
    if db then X.OnAddonMsg(arg1, ...) end
    return
  end
  if event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_SAY" then
    if db then X.OnChatAsk(arg1, (select(1, ...))) end
    return
  end
  if event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST"
     or event == "PLAYER_FLAGS_CHANGED" then
    if db then X.SendCover() end  -- cover-me handoff state may have changed (1.7.0)
    if event == "PLAYER_DEAD" and db and X.DeathRecap then X.DeathRecap(db.deathRecap) end  -- (1.9.0)
    return
  end
  if event == "GROUP_ROSTER_UPDATE" then
    if db then X.OnRoster() end
    if db and X.AutoProfileCheck then X.AutoProfileCheck() end
    Soon()
    return
  end
  if event == "CHALLENGE_MODE_START" then
    if db then
      X.upTotal, X.upFull = 0, 0  -- a fresh run, a fresh uptime score (1.6.0)
      Soon()
      if db.joinDigest and hasAnyBuff then X.JoinDigest("run") end
    end
    return
  end
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    driver:UnregisterEvent("ADDON_LOADED")  -- one-off
    BuffRadarDB = SanitizeDB(BuffRadarDB)
    db = BuffRadarDB
    db.showOutOfRange, db.hideInCombat = false, true
    local preVersion = db.dbVersion or 0  -- the version the save came from (1.9.0 wizard gate)
    Ignore.Rebuild()
    -- Settings shared with the Forever edition: Classic-only choices fall back
    -- to the defaults here (their controls are hidden on this edition).
    if not CLASSIC_FEATURES then
      if db.castMethod == "id" or db.castMethod == "rank" then db.castMethod = "target" end
      db.groupCast = false
    end
    if (db.dbVersion or 0) < 3 then
      db.castMethod = "target"
      db.clickReg = "both"
    end
    if (db.dbVersion or 0) < 4 then
      db.includeSelf = true   -- yourself is always checked first now
      db.dbVersion = 4
    end
    if (db.dbVersion or 0) < 5 then
      db.dbVersion = 5        -- 1.2.0: new settings take their defaults; nothing to migrate
    end
    if (db.dbVersion or 0) < 6 then
      db.dbVersion = 6        -- 1.4.0: specProfiles / lowMana added; nothing to migrate
    end
    if (db.dbVersion or 0) < 7 then
      db.dbVersion = 7        -- 1.5.0: profiles / sync / role filter added; nothing to migrate
    end
    if (db.dbVersion or 0) < 9 then
      db.dbVersion = 9        -- 1.7.0: readyPost / pinned / weaponWatch / enterFlash / scanThrottle / history added; nothing to migrate
    end
    if (db.dbVersion or 0) < 10 then
      db.dbVersion = 10       -- 1.8.0: new watch/search settings take their defaults
      -- Resistance context (#32): on Forever, shadow protection is a
      -- pre-pull buff for instances by default, not an always-on need.
      -- The player can change it any time with /br context SHADOW_PROT.
      if CLASSIC_FEATURES and db.buffContext.SHADOW_PROT == nil then
        db.buffContext.SHADOW_PROT = "instance"
      end
    end
    if (db.dbVersion or 0) < 11 then
      db.dbVersion = 11       -- 1.9.0: twoCol / deathRecap / wipeReport / wizardSeen added
      -- Anyone with a real save history (1.2.0 or later) is not a new
      -- user: don't nag them with the first-run wizard hint.
      if preVersion >= 5 then db.wizardSeen = true end
    end
    if (db.dbVersion or 0) < 12 then
      db.dbVersion = 12       -- 1.10.0: customization settings take their defaults
    end
    if (db.dbVersion or 0) < 13 then
      db.dbVersion = 13       -- 1.12.0: scalePerSpec / specScales / gripSnap / tagSymbols / reduceMotion / rangeWatch take their defaults
    end
    if (db.dbVersion or 0) < 14 then
      db.dbVersion = 14       -- 1.14.0: fastAura / modClick / pullFlash take their defaults (all off)
    end
    if (db.dbVersion or 0) < 15 then
      db.dbVersion = 15       -- 1.15.0: fallSound / customGroup take their defaults (fallSound off)
    end
    if (db.dbVersion or 0) < 16 then
      db.dbVersion = 16       -- Per-class blessing preferences start with the default priority.
    end
    if (db.dbVersion or 0) < 17 then
      db.dbVersion = 17       -- assumeRange takes its default (off)
    end
    X.SpecSwap()
  elseif event == "PLAYER_LOGIN" then
    driver:UnregisterEvent("PLAYER_LOGIN")  -- one-off
    if not db then
      BuffRadarDB = SanitizeDB(BuffRadarDB)
      db = BuffRadarDB
      Ignore.Rebuild()
    end
    X.InitSync()
    X.inGroupPrev = InGroup()
    RequestSpellData()
    local ok, err = pcall(BuildBuffList)
    if not ok then Print("|cffff4040error reading spellbook:|r " .. tostring(err)) end
    X.prioDirty = true
    ok, err = pcall(BuildUI)
    if not ok then Print("|cffff4040error building window:|r " .. tostring(err)) end
    X.ApplyClickThrough()
    Print("loaded. Type /br to show the window.")
    if not db.wizardSeen then
      Print("New to BuffRadar? /br wizard runs a one-minute setup.")
    end
    if X.FriendlyPlatesOn() == false then
      Print("friendly nameplates are |cffff4040off|r - nearby players outside your group can't be listed until they're on. Type /br plates to turn them on (or press Shift+V).")
    end
    if not hasAnyBuff then
      Print("You don't know any buffs this addon handles yet; the window will appear once you learn one.")
    end
    StartTicker()
    Soon()
  elseif event == "PLAYER_REGEN_DISABLED" then
    X.combatStart = GetTime()  -- the wipe report times the fight from here (1.9.0)
    if combatText then combatText:Show() end
    -- Drivers clear cast attributes in combat; protected drag and visibility
    -- work can run here only if the client has not started lockdown.
    if not InCombatLockdown() then
      X.EndWindowDrags()
      if frame and not frame.visibilityDriver then frame:Hide() end
      if X.pill and not X.pill.visibilityDriver then X.pill:Hide() end
    end
  elseif event == "PLAYER_REGEN_ENABLED" then
    X.afterCombat = true  -- Refresh() pulses the border if work is waiting
    if InCombatLockdown() then return end
    X.EndWindowDrags()
    if combatText then combatText:Hide() end
    BuildUI()
    -- Secure snippets cleared the attributes behind the display cache.
    for i = 1, #rows do rows[i].bGuid = nil end
    if nextBtn then nextBtn.bGuid, nextBtn.isClear = nil, false end
    if X.groupBtn then X.groupBtn.bGuid, X.groupBtn.isClear = nil, false end
    ApplyGeometry()  -- a scale/width change made during combat lands now
    if X.appearancePending or X.flashPending then ApplyAppearance() end
    X.ApplyRowLayout()
    X.ApplyClickThrough()
    ApplyNextRegistration()
    if db and X.WipeCheck then X.WipeCheck() end  -- post-wipe report (1.9.0)
    Soon()
  elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
    if db then ScheduleRebuild() end
  else
    if (event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE") and db then X.OnRoster() end
    if (event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED"
        or event == "ZONE_CHANGED_INDOORS") and db then
      if X.AutoProfileCheck then X.AutoProfileCheck() end
      if event == "ZONE_CHANGED_NEW_AREA" then X.InstanceCheck() end
    end
    Soon()
  end
end)

---------------------------------------------------------------------------
-- Keybind actions (Bindings.xml calls these)
---------------------------------------------------------------------------
function BuffRadar_ToggleWindow()
  if not db then return end
  db.hidden = not db.hidden
  sessionShow = not db.hidden
  if InCombatLockdown() then
    Print(db.hidden and "Window will hide when combat ends." or "Window will show when combat ends.")
    return
  end
  if not db.hidden and db.groupOnly and not InGroup() then
    Print("Window is set to show only in a party or raid.")
  end
  Refresh()
end

function BuffRadar_ToggleSound()
  if not db then return end
  db.playSound = not db.playSound
  Print(db.playSound and "Sound |cff00ff00on|r" or "Sound |cffff4040muted|r")
  if RefreshConfig then RefreshConfig() end
end

---------------------------------------------------------------------------
-- Keybind + macro helpers (block-scoped except the two below: 200-local limit)
---------------------------------------------------------------------------
local KeybindText, OpenKeybinds
do
local function MacroBody()
  if GetCVarBool and GetCVarBool("ActionButtonUseKeyDown") then
    return "/click BuffRadarNextButton LeftButton 1"
  end
  return "/click BuffRadarNextButton"
end

function KeybindText(binding)
  local k1, k2 = nil, nil
  if GetBindingKey then k1, k2 = GetBindingKey(binding or NEXT_BINDING) end
  if not k1 then return "|cff888888not bound|r" end
  local function nice(k) return (GetBindingText and GetBindingText(k)) or k end
  return "|cffffd100" .. nice(k1) .. (k2 and (", " .. nice(k2)) or "") .. "|r"
end

function OpenKeybinds()
  if InCombatLockdown() then Print("Can't open key bindings during combat."); return end
  local ok = false
  if Settings and Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
    ok = pcall(Settings.OpenToCategory, Settings.KEYBINDINGS_CATEGORY_ID, BINDING_HEADER_BUFFRADAR)
  end
  if not ok then
    Print("Open Game Menu > Options > Keybindings and look for the BuffRadar section.")
  end
end

local function MacroIcon()
  for _, b in ipairs(myBuffs) do
    local t = SpellIcon(b.name)
    if type(t) == "number" then return t end
  end
  return 134400 -- question mark
end

-- Creates (or updates) an account-wide macro named "BuffRadar" and puts it on the cursor.
MakeMacro = function(quiet)
  if InCombatLockdown() then Print("Can't edit macros during combat."); return end
  if not (GetMacroIndexByName and CreateMacro and EditMacro) then
    Print("Macro API unavailable. Make a macro yourself containing: " .. MacroBody())
    return
  end
  local body = MacroBody()
  local idx = GetMacroIndexByName(MACRO_NAME)
  if idx and idx > 0 then
    EditMacro(idx, MACRO_NAME, MacroIcon(), body)
  else
    if quiet then return end
    local numGlobal = GetNumMacros and GetNumMacros() or 0
    if numGlobal >= (MAX_ACCOUNT_MACROS or 120) then
      Print("Your general macro slots are full. Make room, or add this line to any macro: " .. body)
      return
    end
    idx = CreateMacro(MACRO_NAME, MacroIcon(), body, nil)
  end
  if quiet then return end
  if idx and PickupMacro then pcall(PickupMacro, idx) end
  Print("Macro |cffffd100BuffRadar|r is on your cursor; drop it on an action bar. It runs: " .. body)
end
end -- keybind + macro block

---------------------------------------------------------------------------
-- Config window (tabbed: Window / Alerts / Buffs / Behavior / Ignore & Stats)
--
-- The whole settings window lives in Config.lua since 1.15.0 (file split
-- Slice B): the builders, the tabs, BuildConfig, RefreshConfig and
-- OpenConfig moved there verbatim from the do-block that used to sit
-- here, and reach this file's locals through X.cfgAPI (filled in at the
-- bottom of this file). These forward locals delegate to it.
---------------------------------------------------------------------------
RefreshConfig = function() if X.RefreshConfig then X.RefreshConfig() end end
OpenConfig = function(forceShow) if X.OpenConfig then X.OpenConfig(forceShow) end end


---------------------------------------------------------------------------
-- Slash commands: HandleSlash and its helpers (OnOff, ListBuffs,
-- X.Context, X.AutoProfileCheck, X.SelfTest) live in Slash.lua since
-- 1.15.0 (file split Slice C), reaching this file's locals through
-- X.slashAPI (filled in at the bottom of this file). Main keeps only
-- the hand-off and the SlashCmdList registration below.
---------------------------------------------------------------------------
-- Handed to Extras.lua (the optional second file): the few locals it needs.
-- (X.OnOff is published by Slash.lua, where OnOff lives since Slice C.)
X.Print, X.L, X.Refresh, X.BUFF_DEFS = Print, L, Refresh, BUFF_DEFS

-- Handed to Config.lua (the settings window, file split Slice B): the
-- locals it needs, through one table so the bridge costs this file a
-- single main-chunk local. Every value has a stable identity (functions,
-- and tables that are mutated in place, never replaced).
X.cfgAPI = {
  L = L, Print = Print, Refresh = Refresh, PlayAlert = PlayAlert,
  ApplyAppearance = ApplyAppearance, ApplyGeometry = ApplyGeometry,
  BuildBuffList = BuildBuffList, InvalidateRows = InvalidateRows,
  UpdateCounter = UpdateCounter, IsOn = IsOn, Esc = Esc,
  KeybindText = KeybindText, OpenKeybinds = OpenKeybinds, MakeMacro = MakeMacro,
  Missing = Missing, RefreshMinimapButton = RefreshMinimapButton,
  myBuffs = myBuffs, myBlessing = myBlessing, Single = Single, Ignore = Ignore,
  BLESSINGS = BLESSINGS, DEFAULTS = DEFAULTS, SCALE_PRESETS = SCALE_PRESETS,
  CLASSIC_FEATURES = CLASSIC_FEATURES, NEXT_BINDING = NEXT_BINDING,
}

-- Handed to Slash.lua (every /br command, file split Slice C): functions
-- and stable tables by value; state this file reassigns or fills after
-- load (window, grip, build/session flags) through the two accessors.
X.slashAPI = {
  Print = Print, Refresh = Refresh, RefreshConfig = RefreshConfig, OpenConfig = OpenConfig,
  PlayAlert = PlayAlert, ApplyAppearance = ApplyAppearance, ApplyGeometry = ApplyGeometry,
  BuildBuffList = BuildBuffList, BuildUI = BuildUI, InvalidateRows = InvalidateRows,
  IsOn = IsOn, FriendlyPlatesOn = X.FriendlyPlatesOn, InGroup = InGroup,
  InInstanceNow = InInstanceNow, InMajorCity = InMajorCity, MakeMacro = MakeMacro,
  OpenKeybinds = OpenKeybinds, RefreshMinimapButton = RefreshMinimapButton,
  RestorePosition = RestorePosition, SpellName = SpellName, UpdateCounter = UpdateCounter,
  QueueRefresh = QueueRefresh,
  ALL = ALL, BLESSINGS = BLESSINGS, BUFF_DEFS = BUFF_DEFS, Ignore = Ignore, Single = Single,
  myBuffs = myBuffs, myBlessing = myBlessing, entries = entries, seen = seen,
  known = known, ranks = ranks, rows = rows,
  CLASSIC_FEATURES = CLASSIC_FEATURES, MAX_WIDTH = MAX_WIDTH, MIN_WIDTH = MIN_WIDTH,
  getState = function()
    return { frame = frame, grip = grip, built = built, hasAnyBuff = hasAnyBuff,
             sessionShow = sessionShow, lastError = lastError, bookCount = bookCount,
             nextWrapped = nextWrapped, nextCombatDriver = nextCombatDriver }
  end,
  setSessionShow = function(v) sessionShow = v end,
}
X.GetDB = function() return db end
X.SanitizeDB, X.IsProfileName, X.PROFILE_MAX_BYTES = SanitizeDB, IsProfileName, PROFILE_MAX_BYTES
X.Esc, X.Unesc, X.DEFAULTS = Esc, Unesc, DEFAULTS  -- for Profiles.lua
X.InGroup, X.InRaid = InGroup, InRaid  -- for Recaps.lua
X.CLASSIC = CLASSIC_FEATURES
X.GetFrame = function() return frame end
X.PositionSave = SavePosition
X.ApplyAppearance = ApplyAppearance

SlashCmdList.BUFFRADAR = function(msg)
  if not X.HandleSlash then
    Print("BuffRadar commands are unavailable (Slash.lua did not load).")
    return
  end
  local ok, err = pcall(X.HandleSlash, msg)
  if not ok then Print("|cffff4040error:|r " .. tostring(err)) end
end
