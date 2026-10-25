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
local math_min, math_max, math_floor, math_huge = math.min, math.max, math.floor, math.huge
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

-- Edition, picked at load from the client's interface version: the
-- Forever client reports 16001, retail 120105 and up. One source serves
-- both; each edition's zip differs only in its .toc and docs. CLASSIC_FEATURES (true
-- on Forever) turns on spell ranks, group versions of buffs (Prayer of
-- Fortitude, ...) and paladin blessings; on retail their settings, commands
-- and cast modes ("id", "rank") are hidden and that code stays inert.
local CLASSIC_FEATURES
do
  local ok, _, _, _, iface = pcall(GetBuildInfo)
  iface = ok and tonumber(iface) or 0
  CLASSIC_FEATURES = iface > 0 and iface < 100000
end

---------------------------------------------------------------------------
-- Buff data. Edit freely.
--   id/name : rank-1 spell id (used to get the localized name) + English fallback
--   also    : other spells that count as "already has it" (group / greater versions)
--   classes : which classes actually benefit
--   on      : enabled by default (toggle in game with /br toggle KEY)
---------------------------------------------------------------------------
-- Fields:
--   key      settings key (/br toggle KEY, or the checkboxes in /br config)
--   id/name  spell to cast (rank-1 id gives the localized name; English fallback)
--   choices  instead of id/name: alternatives in priority order; the first one you know
--            is cast, and ANY of them already on the target counts as "has it"
--   also     other auras that count as "has it" (group / greater versions)
--   classes  who benefits (ignored for self-only buffs)
--   role     only players with this assigned group role ("TANK", ...); players
--            with no assigned role (strangers, unassigned) fall back to classes
--   self    true = can only be cast on yourself (shown on your own row)
--   groupOnly true = only reaches you and your party/raid (e.g. Battle Shout):
--            players outside your group are never listed for it
--   single   true = yours can sit on only one other player at a time (Earth
--            Shield): while it's on someone, nobody else is listed for it
--   who      short label for the settings window
--   on       enabled by default
local ALL, MANA, MELEE, TANKS, BUFF_DEFS  -- who benefits / what you can cast (per edition)
if not CLASSIC_FEATURES then
  -- Retail edition: all thirteen classes. (The Forever edition lists nine.)
  ALL  = { WARRIOR=true, PALADIN=true, HUNTER=true, ROGUE=true, PRIEST=true,
                 SHAMAN=true, MAGE=true, WARLOCK=true, DRUID=true,
                 DEATHKNIGHT=true, MONK=true, DEMONHUNTER=true, EVOKER=true }
  -- Retail mana users: hunters use focus, so they drop off this list; evokers and
  -- monks (Mistweaver) join it.
  MANA = { PALADIN=true, PRIEST=true, SHAMAN=true, MAGE=true,
                 WARLOCK=true, DRUID=true, MONK=true, EVOKER=true }

  MELEE = { WARRIOR=true, ROGUE=true, PALADIN=true, SHAMAN=true, DRUID=true,
                  DEATHKNIGHT=true, MONK=true, DEMONHUNTER=true }
  TANKS = { WARRIOR=true, PALADIN=true, DRUID=true, DEATHKNIGHT=true,
                  MONK=true, DEMONHUNTER=true }

  -- Retail edition buff set. Retail has no spell ranks and no separate group
  -- versions: casting a raid buff on one group member applies it to the whole
  -- party/raid in range, so the per-person list simply clears as the aura lands.
  -- Blizzard's own list of player-cast long-term raid buffs (hotfix notes,
  -- 2026-04-03): Mark of the Wild, Arcane Intellect, Battle Shout, Power Word:
  -- Fortitude, Skyfury, Source of Magic, Symbiotic Relationship, Blessing of
  -- the Bronze. Source of Magic and Symbiotic Relationship are deliberately NOT
  -- here: each can sit on only ONE player per caster, so everyone else would
  -- show as "missing" forever. Battle Shout and Blessing of the Bronze are
  -- groupOnly: they can't be given to players outside your group, so listing
  -- strangers for them would also leave those strangers "missing" forever.
  -- Spells from the Forever edition that retail removed (mage armors, Divine
  -- Spirit, Fear Ward, Inner Fire, blessings, ...) are gone too — BuffRadar
  -- only ever offers spells found in your spellbook, so they could never fire.
  BUFF_DEFS = {
    -- Mage
    { key="ARCANE_INTELLECT", id=1459,  name="Arcane Intellect",
      also={}, classes=MANA, who="mana users", on=true },
    -- Warrior (new in the retail edition: warriors have no buffs in Forever)
    { key="BATTLE_SHOUT",     id=6673,  name="Battle Shout",
      also={}, classes=ALL, groupOnly=true, who="you & your group", on=true },
    -- Priest
    { key="FORTITUDE",        id=1243,  name="Power Word: Fortitude",
      also={}, classes=ALL, who="everyone", on=true },
    -- Druid
    { key="MARK_OF_THE_WILD", id=1126,  name="Mark of the Wild",
      also={}, classes=ALL, who="everyone", on=true },
    { key="THORNS",           id=467,   name="Thorns",
      also={}, classes=MELEE, who="melee classes (PvP talent)", on=false },
    -- Shaman. Skyfury is NOT groupOnly: it's cast on a target ally, and only
    -- spreads to the whole party/raid when that ally is in your group, so
    -- players outside the group can receive it too.
    { key="SKYFURY",          id=462854, name="Skyfury",
      also={}, classes=ALL, who="everyone", on=true },
    { key="SHAMAN_SHIELD", self=true, who="you", on=true,
      choices={ {52127, "Water Shield"}, {324, "Lightning Shield"} } },
    -- Earth Shield sits on one other player at a time (plus yourself with
    -- Elemental Orbit, which BuffRadar doesn't count): single.
    { key="EARTH_SHIELD",     id=974,   name="Earth Shield",
      also={}, classes=TANKS, role="TANK", single=true, who="tanks", on=false },
    -- Evoker (new in the retail edition)
    { key="BLESSING_OF_THE_BRONZE", id=381732, name="Blessing of the Bronze",
      also={}, classes=ALL, groupOnly=true, who="you & your group", on=true },
    -- Warlock
    { key="UNENDING_BREATH",  id=5697,  name="Unending Breath",
      also={}, classes=ALL, who="everyone (situational)", on=false },
  }
else
  -- Forever edition (1.2.4 tables, unchanged): nine classes, spell ranks,
  -- group versions of buffs, paladin blessings (see BLESSINGS below).
  ALL  = { WARRIOR=true, PALADIN=true, HUNTER=true, ROGUE=true, PRIEST=true,
                 SHAMAN=true, MAGE=true, WARLOCK=true, DRUID=true }
  MANA = { PALADIN=true, HUNTER=true, PRIEST=true, SHAMAN=true, MAGE=true,
                 WARLOCK=true, DRUID=true }

  MELEE = { WARRIOR=true, ROGUE=true, PALADIN=true, SHAMAN=true, DRUID=true }
  TANKS = { WARRIOR=true }

  BUFF_DEFS = {
    -- Mage
    { key="ARCANE_INTELLECT", id=1459,  name="Arcane Intellect",
      also={ {23028, "Arcane Brilliance"} }, groupCast={ 23028, "Arcane Brilliance" },
      classes=MANA, who="mana users", on=true },
    { key="MAGE_ARMOR", self=true, who="you", on=true,
      choices={ {30482, "Molten Armor"}, {6117, "Mage Armor"}, {7302, "Ice Armor"}, {168, "Frost Armor"} } },
    { key="DAMPEN_MAGIC",     id=604,   name="Dampen Magic",
      also={}, classes=ALL, who="everyone (situational)", on=false },
    { key="AMPLIFY_MAGIC",    id=1008,  name="Amplify Magic",
      also={}, classes=ALL, who="everyone (situational)", on=false },
    -- Priest
    { key="FORTITUDE",        id=1243,  name="Power Word: Fortitude",
      also={ {21562, "Prayer of Fortitude"} }, groupCast={ 21562, "Prayer of Fortitude" },
      classes=ALL, who="everyone", on=true },
    { key="DIVINE_SPIRIT",    id=14752, name="Divine Spirit",
      also={ {27681, "Prayer of Spirit"} }, groupCast={ 27681, "Prayer of Spirit" },
      classes=MANA, who="mana users", on=true },
    { key="FEAR_WARD",        id=6346,  name="Fear Ward",
      also={}, classes=TANKS, who="warriors", on=true },
    { key="INNER_FIRE",       id=588,   name="Inner Fire",
      self=true, also={}, who="you", on=true },
    { key="SHADOW_PROT",      id=976,   name="Shadow Protection",
      also={ {27683, "Prayer of Shadow Protection"} }, groupCast={ 27683, "Prayer of Shadow Protection" },
      classes=ALL, who="everyone (situational)", on=false },
    -- Druid
    { key="MARK_OF_THE_WILD", id=1126,  name="Mark of the Wild",
      also={ {21849, "Gift of the Wild"} }, groupCast={ 21849, "Gift of the Wild" },
      classes=ALL, who="everyone", on=true },
    { key="THORNS",           id=467,   name="Thorns",
      also={}, classes=MELEE, who="melee classes", on=true },
    -- Shaman
    { key="SHAMAN_SHIELD", self=true, who="you", on=true,
      choices={ {24398, "Water Shield"}, {324, "Lightning Shield"} } },
    { key="EARTH_SHIELD",     id=974,   name="Earth Shield",
      also={}, classes=TANKS, who="warriors", on=false },
    { key="WATER_BREATHING",  id=131,   name="Water Breathing",
      also={}, classes=ALL, who="everyone (situational)", on=false },
    -- Warlock
    { key="WARLOCK_ARMOR", self=true, who="you", on=true,
      choices={ {28176, "Fel Armor"}, {706, "Demon Armor"}, {687, "Demon Skin"} } },
    { key="UNENDING_BREATH",  id=5697,  name="Unending Breath",
      also={}, classes=ALL, who="everyone (situational)", on=false },
    { key="DETECT_INVIS", classes=ALL, who="everyone (situational)", on=false,
      choices={ {11743, "Detect Greater Invisibility"}, {2970, "Detect Invisibility"},
                {132, "Detect Lesser Invisibility"} } },
  }
end

-- Paladin: only one of YOUR blessings can sit on a player, so each class gets the
-- first blessing in its list that you know. Kings leads every list: it buffs all
-- stats, so a paladin who knows it wants it on everyone. Might/Wisdom are only
-- fallbacks for paladins who don't know Kings yet. (Before 1.2.3 Kings sat
-- second, behind Might/Wisdom — and since Kings is learned after them, anyone
-- who knew Kings already knew the first entry too, so Kings was never cast.)
local BLESSINGS = {
  MIGHT     = { id=19740, name="Blessing of Might",     greater={25782, "Greater Blessing of Might"} },
  WISDOM    = { id=19742, name="Blessing of Wisdom",    greater={25894, "Greater Blessing of Wisdom"} },
  KINGS     = { id=20217, name="Blessing of Kings",     greater={25898, "Greater Blessing of Kings"} },
  SALVATION = { id=1038,  name="Blessing of Salvation", greater={25895, "Greater Blessing of Salvation"} },
  LIGHT     = { id=19977, name="Blessing of Light",     greater={25890, "Greater Blessing of Light"} },
  SANCTUARY = { id=20911, name="Blessing of Sanctuary", greater={25899, "Greater Blessing of Sanctuary"} },
}
local BLESSING_PRIORITY = {
  WARRIOR = { "KINGS", "MIGHT" },
  ROGUE   = { "KINGS", "MIGHT" },
  HUNTER  = { "KINGS", "WISDOM" },   -- Might is melee attack power only
  PALADIN = { "KINGS", "WISDOM", "MIGHT" },
  SHAMAN  = { "KINGS", "WISDOM", "MIGHT" },
  DRUID   = { "KINGS", "WISDOM", "MIGHT" },
  PRIEST  = { "KINGS", "WISDOM" },
  MAGE    = { "KINGS", "WISDOM" },
  WARLOCK = { "KINGS", "WISDOM" },
  -- Retail-only classes. Paladin blessings don't exist on retail, so these
  -- rows never fire there; they keep the table complete over all classes.
  DEATHKNIGHT = { "KINGS", "MIGHT" },
  MONK        = { "KINGS", "WISDOM", "MIGHT" },
  DEMONHUNTER = { "KINGS", "MIGHT" },
  EVOKER      = { "KINGS", "WISDOM" },
}

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
  showOutOfRange = false, -- also list out-of-range players, greyed and unclickable
  sortMode = "name",   -- list order: "name" or "role" (tanks and leaders first)
  ignored = {},        -- player names BuffRadar never lists (right-click a row)
  rebuffPer = {},      -- per-buff rebuff thresholds in seconds: buff key -> seconds
  alertSound = "droplet", -- alert sound: "droplet", "system" or "none"
  muteInInstance = false, -- no alert sound while in a dungeon, raid or battleground
  showMinimap = true,  -- minimap button (the addon compartment works regardless)
  minimapAngle = 215,  -- minimap button position, degrees
  pauseInBG = false,   -- pause listing in battlegrounds and arenas
  lowMana = 0,         -- pause offering buffs below this mana % (0 = off) (1.4.0)
  specProfiles = {},   -- per-spec overrides: spec key -> { enabled=, rebuffPer= } (1.4.0)
  compact = false,     -- half-height rows without portraits (1.4.0)
  textScale = 1,       -- list text scale, separate from the window scale (1.4.0)
  charPoint = false,   -- remember the window position per character (1.4.0)
  pointByChar = {},    -- charPoint positions: "Name-Realm" -> point table (1.4.0)
  stats = {},          -- all-time casts per spell name: name -> count
}
local db

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
  sortMode = { name = true, role = true, distance = true },
  alertSound = { droplet = true, system = true, none = true },
}
local RANGES = { bgAlpha = { 0, 1 }, scale = { 0.5, 2 }, cfgScale = { 0.5, 2 },
                 width = { MIN_WIDTH, MAX_WIDTH }, rebuff = { 0, 3600 }, castsTotal = { 0, 1e9 },
                 groupCastMin = { 2, 40 }, minimapAngle = { 0, 360 },
                 lowMana = { 0, 100 }, textScale = { 0.8, 1.5 } }

local function IsNumber(v)
  return type(v) == "number" and v == v and v ~= math_huge and v ~= -math_huge
end
local function Clamp(v, lo, hi) return math_max(lo, math_min(hi, v)) end

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
      elseif k == "enabled" or k == "ignored" then
        local clean = {}
        if v then
          for key, on in pairs(v) do
            if type(key) == "string" and type(on) == "boolean" then clean[key] = on end
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
      elseif k == "rebuffPer" or k == "stats" then
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
      if type(v) ~= "string" or (ENUMS[k] and not ENUMS[k][v]) then v = def end
    end
    saved[k] = v
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
  ["Friendly nameplates are off."] = "Friendly nameplates are off.",
  ["No supported buffs in your spellbook."] = "No supported buffs in your spellbook.",
  ["combat"] = "combat",
  ["+%d more"] = "+%d more",
  ["Casts: |cffffffff%d|r this session  ·  |cffffffff%d|r all-time"] =
    "Casts: |cffffffff%d|r this session  ·  |cffffffff%d|r all-time",
  ["out of range"] = "out of range",  -- under a greyed row's name
  ["recently rezzed"] = "recently rezzed",  -- under a rezzed player's name (1.4.0)
  ["a buff just expired"] = "a buff just expired",  -- under the name (1.4.0)
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
  ["Drag to resize the width"] = "Drag to resize the width",
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
local function FriendlyPlatesOn()
  if GetCVarBool then
    local ok, v = pcall(GetCVarBool, "nameplateShowFriends")
    if ok and v ~= nil then return v and true or false end
  end
  if GetCVar then
    local ok, v = pcall(GetCVar, "nameplateShowFriends")
    if ok and v ~= nil then return v == "1" or v == 1 or v == true end
  end
  return nil
end

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

local function InRange(spell, unit)
  if UnitIsUnit(unit, "player") then return true end
  local ok, r
  if C_Spell and C_Spell.IsSpellInRange then
    ok, r = pcall(C_Spell.IsSpellInRange, spell, unit)
  elseif IsSpellInRange then
    ok, r = pcall(IsSpellInRange, spell, unit)
  end
  if not ok then r = nil end
  -- A protected (secret) answer can't be compared: treat it as "unknown".
  -- (Readable() below does this elsewhere; it's defined after this function.)
  if r ~= nil and issecretvalue then
    local okS, secret = pcall(issecretvalue, r)
    if not okS or secret then r = nil end
  end
  if r == true or r == 1 then return true end
  if r == false or r == 0 then return false end
  -- Range unknown: fall back to group range / follow distance.
  if UnitInRange then
    local okR, inRange, checked = pcall(UnitInRange, unit)
    if okR and checked then return inRange and true or false end
  end
  if CheckInteractDistance then
    local okC, near = pcall(CheckInteractDistance, unit, 4)
    return okC and near and true or false
  end
  return false
end

-- The Forever engine can hand addons "secret" values that throw when compared or used
-- as table keys. These helpers turn anything unreadable into nil instead of an error.
local function Readable(v)
  if v == nil then return false end
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

local function SafeString(v)
  if not Readable(v) then return nil end
  local ok, s = pcall(tostring, v)
  return ok and s or nil
end

local function SafeNumber(v)
  if not Readable(v) then return nil end
  local ok, n = pcall(tonumber, v)
  return ok and n or nil
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

local function ReadBuff(unit, i)
  -- returns: done (no more buffs), name, expirationTime
  if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
    local ok, a = pcall(C_UnitAuras.GetBuffDataByIndex, unit, i)
    if not ok then return true end
    if a == nil then return true end
    local okN, n = pcall(GetField, a, "name")
    local okE, e = pcall(GetField, a, "expirationTime")
    return false, okN and SafeString(n) or nil, okE and SafeNumber(e) or nil
  elseif UnitBuff then
    local ok, n, _, _, _, _, e = pcall(UnitBuff, unit, i)
    if not ok or n == nil then return true end
    return false, SafeString(n), SafeNumber(e)
  end
  return true
end

-- Index-scan fallback: one reused table, filled at most once per unit per check.
local scanCache, scanUnit = {}, nil
local function ScanInto(unit)
  wipe(scanCache)
  scanUnit = unit
  local now = GetTime()
  for i = 1, 40 do
    local done, name, exp = ReadBuff(unit, i)
    if done then break end
    if name then  -- unreadable buffs are skipped, not fatal
      local remaining = (exp and exp > 0) and (exp - now) or math_huge
      local cur = scanCache[name]
      if not cur or remaining > cur then scanCache[name] = remaining end
    end
  end
end

-- Seconds left on the named buff (math.huge = no expiry), or nil when absent.
-- Modern clients answer this with one direct lookup instead of walking every aura.
local GetAuraByName = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
local function Remaining(unit, name)
  if GetAuraByName then
    local ok, a = pcall(GetAuraByName, unit, name, "HELPFUL")
    if ok then
      if a == nil then return nil end
      local okE, e = pcall(GetField, a, "expirationTime")
      e = okE and SafeNumber(e) or nil
      if e and e > 0 then return e - GetTime() end
      return math_huge
    end
    -- lookup refused (restricted value): fall through to the index scan
  end
  if scanUnit ~= unit then ScanInto(unit) end
  return scanCache[name]
end

local function HasAny(unit, names, minLeft)
  minLeft = minLeft or db.rebuff or 0
  for i = 1, #names do
    local rem = Remaining(unit, names[i])
    if rem and rem > minLeft then return true end
  end
  return false
end

---------------------------------------------------------------------------
-- What can I cast?
---------------------------------------------------------------------------
local known, myBuffs, myBlessing = {}, {}, {}
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
                                groupOnly = d.groupOnly, role = d.role, single = d.single, who = d.who, default = d.on, groupName = groupName }
    end
  end

  wipe(myBlessing)
  for class, list in pairs(CLASSIC_FEATURES and BLESSING_PRIORITY or {}) do
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

  hasAnyBuff = (#myBuffs > 0) or (next(myBlessing) ~= nil)
end
end -- BuildBuffList block

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
local function OnCooldown(name)
  local c = cdCache[name]
  if c ~= nil then return c end
  local start, duration
  if C_Spell and C_Spell.GetSpellCooldown then
    local ok, info = pcall(C_Spell.GetSpellCooldown, name)
    if ok and type(info) == "table" then
      local okS, st = pcall(GetField, info, "startTime")
      local okD, du = pcall(GetField, info, "duration")
      if okS and okD then start, duration = st, du end
    end
  elseif GetSpellCooldown then
    local ok, st, du = pcall(GetSpellCooldown, name)
    if ok then start, duration = st, du end
  end
  local ok, cooling = pcall(IsCooling, start, duration)
  c = (ok and cooling) and true or false
  cdCache[name] = c
  return c
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
local X = { session = {}, dead = {}, rezAt = {}, tally = {}, tallyUnits = 0,
            listA = {}, listB = {}, recentlyGone = {}, sessionCasts = 0,
            missPrev = {}, missNow = {}, expiredAt = {}, rowH = 24 }
X.listedBefore = X.listA  -- guid -> true for names on the board last refresh

function X.Track(unit)
  if not UnitExists(unit) then return end
  local guid = SafeString(UnitGUID(unit))
  if not guid then return end
  if UnitIsDeadOrGhost(unit) then
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

local function Missing(unit, out, isGroup)
  wipe(out)
  local _, class = UnitClass(unit)
  class = SafeString(class)  -- used as a table key below; protected values can't be
  if not class then return 0 end
  local isSelf = UnitIsUnit(unit, "player")
  X.remainTmp = nil
  if isGroup then X.tallyUnits = X.tallyUnits + 1 end
  scanUnit = nil  -- force a fresh index scan (fallback path) for this unit
  local n = 0
  local role, roleRead = nil, false  -- assigned role, read once and only if a buff needs it
  for i = 1, #myBuffs do
    local b = myBuffs[i]
    if b.single and not isSelf and not Single.holder[b.key] and GetAuraByName then
      local ok, a = pcall(GetAuraByName, unit, b.name, "HELPFUL|PLAYER")
      if ok and a ~= nil then Single.holder[b.key], Single.spell[b.key] = unit, b.name end
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
    if applies and IsOn(b.key, b.default) then
      local t
      if isGroup then
        t = X.tally[b.key]
        if not t then t = { total = 0, miss = 0 }; X.tally[b.key] = t end
        t.total = t.total + 1
      end
      if not OnCooldown(b.name)
         and not HasAny(unit, b.names, (db.rebuffPer and db.rebuffPer[b.key]) or db.rebuff) then
        n = n + 1
        out[n] = b.name
        if t then t.miss = t.miss + 1 end
        if n == 1 then  -- still present but inside its rebuff window?
          for _, nm2 in ipairs(b.names) do
            local r = Remaining(unit, nm2)
            if r and r > 0 and r < math_huge then X.remainTmp = r break end
          end
        end
      end
    end
  end
  local bl = myBlessing[class]
  if bl and IsOn("BLESSINGS", true) and (not isSelf or db.includeSelf) then
    local t
    if isGroup then
      t = X.tally.BLESSINGS
      if not t then t = { total = 0, miss = 0 }; X.tally.BLESSINGS = t end
      t.total = t.total + 1
    end
    if not HasAny(unit, bl.names) then
      n = n + 1
      out[n] = bl.name
      if t then t.miss = t.miss + 1 end
      if n == 1 then
        for _, nm2 in ipairs(bl.names) do
          local r = Remaining(unit, nm2)
          if r and r > 0 and r < math_huge then X.remainTmp = r break end
        end
      end
    end
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
  if not UnitExists(unit) or not UnitIsPlayer(unit) then return false end
  if UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then return false end
  if not UnitCanAssist("player", unit) then return false end
  if UnitIsCharmed and UnitIsCharmed(unit) then return false end
  if db.avoidPvP and UnitIsPVP(unit) and not UnitIsPVP("player") then return false end
  return true
end

-- Entry tables are pooled and reused every refresh (no per-refresh garbage).
local entries, entryPool, seen = {}, {}, {}
local nEntries = 0

local function EntryOrder(a, b)
  if a.isSelf ~= b.isSelf then return a.isSelf end
  if (a.rezzed or false) ~= (b.rezzed or false) then return a.rezzed ~= nil end
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
local function RoleOf(unit)
  if UnitIsUnit(unit, "player") then return 0 end
  if AssignedRole(unit) == "TANK" then return 1 end
  local idx = unit:match("^raid(%d+)$")
  if idx and GetRaidRosterInfo then
    local ok, _, _, _, _, _, _, _, _, role = pcall(GetRaidRosterInfo, tonumber(idx))
    if ok and (role == "MAINTANK" or role == "MAINASSIST") then return 1 end
  end
  if UnitIsGroupLeader and UnitIsGroupLeader(unit) then return 2 end
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
  if not Valid(unit) then return end
  -- The GUID is a table key (seen[], the listed sets) and gets compared; a
  -- protected one can't be either, so that unit is skipped.
  local guid = SafeString(UnitGUID(unit))
  if not guid or seen[guid] then return end
  local full, nm = Ignore.UnitNames(unit)
  if next(Ignore.index) and Ignore.Has(full, nm) then return end  -- on the ignore list
  if next(X.session) and X.SessionHas(full, nm) then return end  -- session-only ignore
  seen[guid] = true
  local slot = nEntries + 1
  local e = entries[slot]
  if not e then
    local p = #entryPool
    if p > 0 then e = entryPool[p]; entryPool[p] = nil else e = { missing = {} } end
    entries[slot] = e
  end
  local n = Missing(unit, e.missing, isGroup)
  e.remain1 = X.remainTmp
  if isGroup and n == 0 then X.missNow[guid] = {} end  -- clean baseline for expiry checks
  local inRange = n > 0 and InRange(e.missing[1], unit)
  if n == 0 or (not inRange and not db.showOutOfRange) then return end  -- slot is reused next time
  nEntries = slot
  local _, class = UnitClass(unit)
  -- e.name may be a protected value (display only: SetText accepts those);
  -- sorting uses sortName and the class goes through SafeString (table key).
  e.unit, e.guid, e.name, e.class, e.group = unit, guid, nm or UnitName(unit), SafeString(class), isGroup
  e.fullName, e.sortName = full, nm or ""
  e.isSelf = UnitIsUnit(unit, "player")
  e.rangeBucket = (not inRange) and ((_G.UnitInRange and _G.UnitInRange(unit)) and 1 or 2) or 0
  if isGroup then
    -- Expiry tracking: a buff that was not missing last scan, is missing
    -- now, and is truly gone (not just inside its rebuff window) expired,
    -- was dispelled, or went away with a death.
    local keys, expired = {}, nil
    for j = 1, #e.missing do
      local key = X.KeyOfName(e.missing[j])
      if key then
        keys[key] = true
        local prev = X.missPrev[guid]
        if prev and not prev[key] and not HasAny(unit, { e.missing[j] }, 0) then expired = true end
      end
    end
    X.missNow[guid] = keys
    -- Sticky for a few seconds: the next scan already sees the buff as
    -- "missing last time too", so without this the flag would flap off.
    if expired then X.expiredAt[guid] = GetTime() end
    local ea = X.expiredAt[guid]
    e.expired = (expired or (ea and GetTime() - ea < 10)) or nil
  else
    e.expired = nil
  end
  local rz = X.rezAt[guid]
  e.rezzed = (rz and GetTime() - rz < 60) or nil
  e.outOfRange = not inRange
  e.groupCast = false
  e.role = RoleOf(unit)
end

-- Last-scan diagnostics for /br debug: how many nameplate units the client
-- handed us on the latest pass, and how many of them were players.

local function CollectEntries()
  wipe(seen)
  wipe(cdCache)
  wipe(Single.holder)
  wipe(X.tally)
  X.tallyUnits = 0
  X.missPrev, X.missNow = X.missNow, {}
  wipe(X.missNow)
  nEntries = 0
  X.platesSeen, X.playersSeen = 0, 0
  local list = InRaid() and RAID or PARTY
  X.TrackDeaths(list, "player")
  for i = 1, #list do Consider(list[i], true) end
  Consider("player", true)
  Consider("target", false)
  Consider("mouseover", false)
  for i = 1, #PLATES do
    local u = PLATES[i]
    if UnitExists(u) then
      X.platesSeen = X.platesSeen + 1
      if UnitIsPlayer(u) then X.playersSeen = X.playersSeen + 1 end
    end
    Consider(u, false)
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
  if nEntries > 1 then table_sort(entries, EntryOrder) end
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

-- READY_CHECK: a local summary (the group post is /br announce's job).
function X.ReadyReport()
  CollectEntries()
  local people, casts = 0, 0
  for i = 1, nEntries do
    if entries[i].group then people = people + 1; casts = casts + #entries[i].missing end
  end
  if people == 0 then
    Print("Ready check: everyone in your group is buffed.")
  else
    Print(string.format("Ready check: %d %s missing buffs (%d casts). /br announce posts the list.",
      people, people == 1 and "person is" or "people are", casts))
  end
end

-- Settings export / import: one copyable string. Covers the window look,
-- behavior toggles, buff toggles, rebuff timings and both ignore sets --
-- not positions, cast counts or stats (those belong to one machine / char).
X.EXPORT_KEYS = { "locked", "includeSelf", "avoidPvP", "autoHide", "rebuff", "scale",
  "width", "cfgScale", "castMethod", "clickReg", "bgAlpha", "showTitle", "showBorder",
  "playSound", "showCounter", "groupOnly", "pauseInCities", "groupCast", "groupCastMin",
  "showOutOfRange", "sortMode", "alertSound", "muteInInstance", "showMinimap", "lowMana" }

local function Esc(v) return (tostring(v):gsub("%%", "%%25"):gsub(";", "%%3B"):gsub("=", "%%3D")) end
local function Unesc(v) return (v:gsub("%%3D", "="):gsub("%%3B", ";"):gsub("%%25", "%%")) end

function X.Export()
  local parts = { "BR1" }
  for _, k in ipairs(X.EXPORT_KEYS) do
    local v = db[k]
    if type(v) == "boolean" then parts[#parts + 1] = k .. "=" .. (v and "1" or "0")
    elseif type(v) == "number" or type(v) == "string" then parts[#parts + 1] = k .. "=" .. Esc(v) end
  end
  local c = db.bgColor or DEFAULTS.bgColor
  parts[#parts + 1] = "bgColor=" .. tostring(c[1]) .. "," .. tostring(c[2]) .. "," .. tostring(c[3])
  for _, tname in ipairs({ "enabled", "rebuffPer" }) do
    local keys = {}
    for k in pairs(db[tname] or {}) do keys[#keys + 1] = k end
    table_sort(keys)
    for _, k in ipairs(keys) do
      local v = db[tname][k]
      if type(v) == "boolean" then parts[#parts + 1] = tname .. "." .. Esc(k) .. "=" .. (v and "1" or "0")
      elseif type(v) == "number" then parts[#parts + 1] = tname .. "." .. Esc(k) .. "=" .. tostring(v) end
    end
  end
  local names = {}
  for name in pairs(db.ignored or {}) do names[#names + 1] = name end
  table_sort(names)
  for _, name in ipairs(names) do parts[#parts + 1] = "ignored." .. Esc(name) .. "=1" end
  return table.concat(parts, ";")
end

function X.Import(text)
  if type(text) ~= "string" then return false, "Nothing to import." end
  local fields = {}
  for part in (text .. ";"):gmatch("(.-);") do fields[#fields + 1] = part end
  if fields[1] ~= "BR1" then return false, "That doesn't look like a BuffRadar settings string." end
  local patch = { enabled = {}, rebuffPer = {}, ignored = {} }
  for i = 2, #fields do
    local k, v = fields[i]:match("^(.-)=(.*)$")
    if k and v then
      local sub, sk = k:match("^(%a+)%.(.*)$")
      if sub == "enabled" or sub == "rebuffPer" or sub == "ignored" then
        local key = Unesc(sk)
        if sub == "rebuffPer" then patch.rebuffPer[key] = tonumber(v)
        else patch[sub][key] = (v == "1") end
      elseif k == "bgColor" then
        local r, g, b = v:match("^([%d%.]+),([%d%.]+),([%d%.]+)$")
        if r then patch.bgColor = { tonumber(r), tonumber(g), tonumber(b) } end
      else
        local dt = type(DEFAULTS[k])
        if dt == "boolean" then patch[k] = (v == "1")
        elseif dt == "number" then patch[k] = tonumber(v)
        elseif dt == "string" then patch[k] = Unesc(v) end
      end
    end
  end
  for k, v in pairs(patch) do if v ~= nil then db[k] = v end end
  SanitizeDB(db)  -- repairs anything out of range or mistyped in the string
  Ignore.Rebuild()
  return true, "Settings imported."
end

-- /br announce: post the group's missing buffs to party/raid chat (or
-- print them locally when solo). Lives here, not in HandleSlash, to keep
-- that function's upvalue count down.
function X.Announce()
  CollectEntries()
  local per, order = {}, {}
  for i = 1, nEntries do
    local e = entries[i]
    if e.group then
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
  local ok, lvl = pcall(fn, id)
  if ok and type(lvl) == "number" and lvl > 0 then return lvl end
end

local function PickRank(name, unit)
  local list = ranks[name]
  if not list or #list == 0 then return nil end
  local targetLevel = unit and UnitLevel(unit) or 0
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

function Bind(btn, unit, spell)
  local pick = PickRank(spell, unit)
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
    if UnitIsUnit(unit, "player") then
      btn:SetAttribute("type", "spell")
      btn:SetAttribute("spell", spell)
      btn:SetAttribute("unit", "player")
      return
    end
    if unit:match("^party%d+$") or unit:match("^raid%d+$") then
      btn:SetAttribute("type", "spell")
      btn:SetAttribute("spell", spell)
      btn:SetAttribute("unit", unit)
      return
    end
    local ok, name = pcall(GetUnitName or UnitName, unit, true)
    name = ok and SafeString(name) or nil  -- a protected name can't build a macro: no cast
    if name and name ~= "" then
      btn:SetAttribute("type", "macro")
      btn:SetAttribute("macrotext", "/targetexact " .. name .. "\n/cast " .. spell .. "\n/targetlasttarget")
    end
  elseif method == "id" and pick and pick.id then
    btn:SetAttribute("type", "spell")
    btn:SetAttribute("unit", unit)
    btn:SetAttribute("spell", pick.id)
    btn:SetAttribute("macrotext", nil)
  else
    local text = (method == "rank") and CastText(spell, unit) or spell
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("unit", nil)
    btn:SetAttribute("spell", nil)
    btn:SetAttribute("macrotext", "/cast [@" .. unit .. ",help,nodead] " .. text)
  end
end
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

local function PlayAlert()
  if not db or not db.playSound then return end
  if db.alertSound == "none" then return end
  if db.muteInInstance and InInstanceNow() then return end
  if db.alertSound == "system" and PlaySound then
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
  if X.sessionCasts ~= X.lastCounterSession or total ~= X.lastCounterTotal then
    X.lastCounterSession, X.lastCounterTotal = X.sessionCasts, total
    footerText:SetText(string_format(L["Casts: |cffffffff%d|r this session  ·  |cffffffff%d|r all-time"],
      X.sessionCasts, total))
  end
end

local function NotePendingCast(entry)
  if entry and entry.missing and entry.missing[1] then
    X.pendingCast = { spell = entry.missing[1], time = GetTime() }
  end
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

local function RestorePosition()
  if db.charPoint then
    local k = X.CharKey()
    if k and db.pointByChar[k] then db.point = db.pointByChar[k] end
  end
  frame:ClearAllPoints()
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
  end
  if e.groupCast then
    GameTooltip:AddLine(L["Group version — one cast buffs the whole party."], 0.4, 0.8, 1)
  end
  GameTooltip:AddLine(L["Right-click to ignore this player."], 0.6, 0.6, 0.6)
  GameTooltip:AddLine(L["Shift-right-click to ignore for this session only."], 0.6, 0.6, 0.6)
  if #e.missing > 1 then
    local rest = {}
    for i = 2, #e.missing do rest[#rest + 1] = e.missing[i] end
    GameTooltip:AddLine(string_format(L["Still needs: %s"], table.concat(rest, ", ")), 0.8, 0.8, 0.8, true)
  end
  GameTooltip:Show()
end

local function CreateRow(i)
  local b = CreateFrame("Button", "BuffRadarRow" .. i, frame, "SecureActionButtonTemplate")
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
  b.name:SetPoint("RIGHT", b, "RIGHT", -(MAX_ICONS * 18 + 4), 0)
  b.name:SetJustifyH("LEFT")
  if b.name.SetWordWrap then b.name:SetWordWrap(false) end
  -- "out of range" under the name of a greyed row, so the state doesn't rest
  -- on color alone (RenderRow moves the name up to make room).
  b.far = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  b.far:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -1)
  b.far:SetText(L["out of range"])
  b.far:Hide()

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
    if button ~= "RightButton" and self:GetAttribute("type") then NotePendingCast(self.entry) end
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

-- Width and scale. The window holds secure row buttons, so its size can't
-- change in combat; callers retry after combat (PLAYER_REGEN_ENABLED).
local function ApplyGeometry()
  if not frame or InCombatLockdown() then return end
  frame:SetWidth(db.width or WIDTH)
  frame:SetScale(db.scale or 1)
end

local function ApplyAppearance()
  if not frame then return end
  local c = db.bgColor or DEFAULTS.bgColor
  if frame.SetBackdropColor then
    frame:SetBackdropColor(c[1], c[2], c[3], db.bgAlpha or 0.92)
    frame:SetBackdropBorderColor(0.35, 0.55, 0.8, db.showBorder and 1 or 0)
  end
  if grip then grip:SetShown(not db.locked) end
  title:SetShown(db.showTitle and true or false)
  combatText:ClearAllPoints()
  if db.showTitle then
    combatText:SetPoint("LEFT", title, "RIGHT", 6, 0)
  else
    combatText:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -8)
  end
end

-- One border pulse; restores the normal border shortly after. Assigned
-- here because frame / ApplyAppearance only exist from this point on.
function X.Flash()
  if not frame or not frame.SetBackdropBorderColor or InCombatLockdown() then return end
  frame:SetBackdropBorderColor(1, 0.35, 0.35, 1)
  if C_Timer and C_Timer.After then
    C_Timer.After(0.7, function() if frame then ApplyAppearance() end end)
  else
    X.flashPending = true  -- no timer API: Refresh() restores it next pass
  end
end

-- Copyable settings string window for /br export and /br import.
function X.ShowExport(text, forImport)
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
      local ok, msg = X.Import(f.editBox:GetText())
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
  f.title:SetText(forImport and "BuffRadar -- paste a settings string, then Import"
                             or "BuffRadar -- your settings string (select all, copy)")
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
function X.ApplyRowLayout()
  if not frame or InCombatLockdown() then return end
  local h = db.compact and 16 or ROW_H
  X.rowH = h
  for i = 1, #rows do
    local row = rows[i]
    row:SetHeight(h)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -HEADER_H - (i - 1) * h)
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -HEADER_H - (i - 1) * h)
    if row.portrait then row.portrait:SetShown(not db.compact) end
    local isz = db.compact and 12 or 16
    for j = 1, MAX_ICONS do if row.icons[j] then row.icons[j]:SetSize(isz, isz) end end
    local ts = db.textScale or 1
    if row.name then row.name:SetScale(ts) end
    if row.far then row.far:SetScale(ts) end
    if row.tag then row.tag:SetScale(ts) end
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
  nextBtn.isClear = true
  nextBtn.bGuid = nil
end

-- Secure attribute writes only when what the button should cast actually changed.
local function BindCached(btn, unit, spell, guid)
  local method = db.castMethod
  local lvl = SafeNumber(UnitLevel(unit)) or 0  -- compared below
  if btn.bGuid == guid and btn.bUnit == unit and btn.bSpell == spell
     and btn.bMethod == method and btn.bLevel == lvl then
    return
  end
  Bind(btn, unit, spell)
  btn.bGuid, btn.bUnit, btn.bSpell, btn.bMethod, btn.bLevel = guid, unit, spell, method, lvl
  btn.isClear = false
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
  -- Some Forever builds reject secure snippets; if so, fall back to plain events
  -- (see PLAYER_REGEN_DISABLED and PostClick below) instead of failing.
  pcall(nextBtn.SetAttribute, nextBtn, "_onstate-combat", [[
    if newstate == "combat" then
      self:SetAttribute("type", nil)
      self:SetAttribute("spell", nil)
      self:SetAttribute("unit", nil)
      self:SetAttribute("macrotext", nil)
    end
  ]])
  if RegisterStateDriver then
    nextCombatDriver = pcall(RegisterStateDriver, nextBtn, "combat", "[combat] combat; nocombat")
  end
  if SecureHandlerWrapScript then
    nextWrapped = pcall(SecureHandlerWrapScript, nextBtn, "OnClick", nextBtn, [[ return nil, true ]], [[
      self:SetAttribute("type", nil)
      self:SetAttribute("spell", nil)
      self:SetAttribute("unit", nil)
      self:SetAttribute("macrotext", nil)
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

local function BuildUI()
  if built or InCombatLockdown() then return end

  frame = CreateFrame("Frame", "BuffRadarFrame", UIParent,
                      BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(db.width or WIDTH, HEADER_H + 30)
  frame:SetFrameStrata("MEDIUM")
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
  gear:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 6)
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

  -- Coverage line (1.4.0): "12/15 fully buffed · Fortitude 13/15 · ...",
  -- directly above the footer; Refresh() grows the window when it's shown.
  coverText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  coverText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 9, FOOTER_H + 3)
  coverText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, FOOTER_H + 3)
  coverText:SetJustifyH("LEFT")
  if coverText.SetWordWrap then coverText:SetWordWrap(false) end
  coverText:Hide()

  -- Resize grip: drag the bottom-right corner to change the width.
  grip = CreateFrame("Button", nil, frame)
  grip:SetSize(12, 12)
  grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight", "ADD")
  grip:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" or db.locked or InCombatLockdown() then return end
    frame:StartSizing("RIGHT")
    self.isSizing = true
  end)
  grip:SetScript("OnMouseUp", function(self)
    if not self.isSizing or InCombatLockdown() then return end
    frame:StopMovingOrSizing()
    self.isSizing = false
    db.width = math_floor(frame:GetWidth() + 0.5)
    SavePosition()  -- re-anchor by the top-left corner (sizing can move the anchor)
  end)
  grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["Drag to resize the width"])
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

  for i = 1, MAX_ROWS do CreateRow(i) end

  local okNext, errNext = pcall(BuildNextButton)
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

local function PositionMinimapButton()
  if not minimapBtn then return end
  local angle = math.rad((db and db.minimapAngle) or 215)
  minimapBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
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
    local cx, cy = GetCursorPosition()
    local scale = (Minimap.GetEffectiveScale and Minimap:GetEffectiveScale()) or 1
    cx, cy = cx / scale, cy / scale
    local atan2 = math.atan2 or math.atan
    db.minimapAngle = math.deg(atan2(cy - my, cx - mx)) % 360
    PositionMinimapButton()
  end)
  minimapBtn = b
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
    wipe(row.cMissing)
  end
  if nextBtn then nextBtn.bGuid, nextBtn.isClear = nil, false end
end

local function RenderRow(row, e)
  row.entry, row.guid = e, e.guid
  local m = e.missing
  if row.cGuid ~= e.guid or row.cUnit ~= e.unit then
    -- 3D portrait render: only for a new player/token. Guarded like the rest of
    -- this file: if a build renames or restricts it, the row still renders.
    if SetPortraitTexture then pcall(SetPortraitTexture, row.portrait, e.unit) end
    row.name:SetText(e.name)
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
    row.name:SetPoint("RIGHT", row, "RIGHT", -(MAX_ICONS * 18 + 4), far and 5 or 0)
    row.far:SetShown(far)
    if far then row.name:SetTextColor(0.55, 0.55, 0.55) else row.name:SetTextColor(ClassColor(e.class)) end
  end
  -- Status tag: a rezzed player (lost every buff) is marked under the name;
  -- the name shifts up for it just like the out-of-range layout, minus grey.
  local tag = not far and (e.expired and L["a buff just expired"]
    or (e.rezzed and L["recently rezzed"] or nil)) or nil
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
      row.name:SetPoint("RIGHT", row, "RIGHT", -(MAX_ICONS * 18 + 4), 5)
      row.tag:Show()
    else
      row.tag:Hide()
      if not far then
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", row.portrait, "RIGHT", 6, 0)
        row.name:SetPoint("RIGHT", row, "RIGHT", -(MAX_ICONS * 18 + 4), 0)
      end
    end
  end
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
    if row.bGuid ~= nil then
      row:SetAttribute("type", nil)
      row:SetAttribute("spell", nil)
      row:SetAttribute("unit", nil)
      row:SetAttribute("macrotext", nil)
      row.bGuid = nil
    end
  else
    row:SetAlpha(1)
    BindCached(row, e.unit, m[1], e.guid)
  end
  if not row:IsShown() then row:Show() end
end

-- Shared look for the "nothing to list" states (no buffs known / paused in a city).
local function ShowStatus(text)
  SetShownIfChanged(coverText, false)
  SetTextIfChanged(countText, "")
  SetShownIfChanged(overflowText, false)
  SetTextIfChanged(emptyText, text)
  SetShownIfChanged(emptyText, true)
  UpdateCounter()
  SetHeightIfChanged(frame, HEADER_H + 26 + FOOTER_H)
  SetShownIfChanged(frame, true)
end

-- True while the last refresh found nothing that time alone can change: no
-- supported buffs known, or scanning paused (city / battleground). The steady
-- timer skips its refreshes then; events (zone changes, learning a spell,
-- settings changes) still refresh right away and clear it.
local refreshIdle = false

local function Refresh()
  if not built or InCombatLockdown() then return end
  refreshIdle = false
  local wasAfterCombat = X.afterCombat
  X.afterCombat = nil
  if X.flashPending then X.flashPending = nil; ApplyAppearance() end

  if not hasAnyBuff then
    refreshIdle = true
    ClearNext()
    for i = 1, MAX_ROWS do ClearRow(rows[i]) end
    if sessionShow and not db.hidden then
      ShowStatus(L["No supported buffs in your spellbook."])
    else
      SetShownIfChanged(frame, false)
    end
    return
  end

  local groupHidden = db.groupOnly and not InGroup()

  -- No scanning in major cities
  if db.pauseInCities and InMajorCity() then
    refreshIdle = true
    ClearNext()
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
  local instType = InInstanceNow()
  if db.pauseInBG and (instType == "pvp" or instType == "arena") then
    refreshIdle = true
    ClearNext()
    wipe(X.listedBefore)
    for i = 1, MAX_ROWS do ClearRow(rows[i]) end
    if db.hidden or groupHidden or db.autoHide then
      SetShownIfChanged(frame, false)
    else
      ShowStatus(L["Paused in a battleground."])
    end
    return
  end

  -- Low-mana pause (optional): don't offer buffs you can't afford to cast.
  if db.lowMana and db.lowMana > 0 then
    local pow = _G.UnitPower and _G.UnitPower("player")
    local powMax = _G.UnitPowerMax and _G.UnitPowerMax("player")
    if pow and powMax and powMax > 0 and (pow / powMax * 100) < db.lowMana then
      ClearNext()
      wipe(X.listedBefore)
      for i = 1, MAX_ROWS do ClearRow(rows[i]) end
      if db.hidden or groupHidden or db.autoHide then
        SetShownIfChanged(frame, false)
      else
        ShowStatus(L["Low mana -- buffing paused."])
      end
      return
    end
  end

  local n = CollectEntries()

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
    BindCached(nextBtn, first.unit, first.missing[1], first.guid)
    nextBtn.entry = first
  else
    ClearNext()
  end

  if db.hidden or groupHidden then
    SetShownIfChanged(frame, false)
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
    PlayAlert()
  end

  local shown = math_min(n, MAX_ROWS)
  for i = 1, MAX_ROWS do
    if i <= shown then RenderRow(rows[i], entries[i]) else ClearRow(rows[i]) end
  end
  -- Post-combat catch-up: one border pulse when the frozen list thaws with
  -- work waiting, so a pull's-end rebuff round doesn't go unnoticed.
  if wasAfterCombat and n > 0 and X.Flash then X.Flash() end

  SetTextIfChanged(countText, n > 0 and n or "")
  if n == 0 and FriendlyPlatesOn() == false then
    -- Honest empty state: with friendly nameplates off, the client shows us
    -- nobody outside the group, so "everyone is buffed" would be a lie.
    SetTextIfChanged(emptyText, L["Friendly nameplates are off."])
  else
    SetTextIfChanged(emptyText, L["Everyone nearby is buffed."])
  end
  SetShownIfChanged(emptyText, n == 0)
  if n > MAX_ROWS then
    if not overflowText.cAnchored then
      overflowText:ClearAllPoints()
      overflowText:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -HEADER_H - MAX_ROWS * (X.rowH or ROW_H) - 2)
      overflowText.cAnchored = true
    end
    if overflowText.cCount ~= n then
      overflowText.cCount = n
      overflowText:SetText(string_format(L["+%d more"], n - MAX_ROWS))
    end
    SetShownIfChanged(overflowText, true)
  else
    SetShownIfChanged(overflowText, false)
  end

  -- Coverage / progress line: shown while grouped (even when the list is
  -- empty -- "15/15 fully buffed" is the good-news form of the same line).
  local coverShown = false
  if X.tallyUnits > 1 then
    local listedGroup = 0
    for i = 1, n do if entries[i].group then listedGroup = listedGroup + 1 end end
    local parts = { string_format("%d/%d fully buffed", X.tallyUnits - listedGroup, X.tallyUnits) }
    for _, b in ipairs(myBuffs) do
      local t = not b.self and X.tally[b.key] or nil
      if t and t.total > 0 then
        local nm = b.key:lower():gsub("_", " ")
        parts[#parts + 1] = string_format("%s %d/%d", nm:sub(1, 1):upper() .. nm:sub(2),
          t.total - t.miss, t.total)
      end
    end
    local tb = X.tally.BLESSINGS
    if tb and tb.total > 0 then
      parts[#parts + 1] = string_format("Blessings %d/%d", tb.total - tb.miss, tb.total)
    end
    SetTextIfChanged(coverText, table.concat(parts, "  ·  "))
    coverShown = true
  end
  SetShownIfChanged(coverText, coverShown)

  local h = HEADER_H + (shown > 0 and shown * (X.rowH or ROW_H) or 18) + 8
  if coverShown then h = h + 13 end
  if n > MAX_ROWS then h = h + 14 end
  h = h + FOOTER_H  -- bottom row: settings gear + cast counter
  UpdateCounter()
  SetHeightIfChanged(frame, h)

  SetShownIfChanged(frame, not (db.autoHide and n == 0 and not sessionShow))
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local driver = CreateFrame("Frame")
local refreshQueued = false
local ticker

local function SafeRefresh()
  local ok, err = pcall(Refresh)
  if not ok and err ~= lastError then
    lastError = err
    Print("|cffff4040error:|r " .. tostring(err))
  end
end

-- Steady refresh every UPDATE_INTERVAL via C_Timer; bursts of events (UNIT_AURA storms in
-- raids, nameplates popping in) collapse into a single refresh SOON_DELAY later.
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
    if refreshIdle or InCombatLockdown() then return end
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
      if elapsed >= UPDATE_INTERVAL then
        elapsed = 0
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
  if built then InvalidateRows() end
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
  "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_SUCCEEDED", "UI_ERROR_MESSAGE",
  "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "CVAR_UPDATE", "UPDATE_BINDINGS",
  "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
  "SPELL_DATA_LOAD_RESULT", "UNIT_PORTRAIT_UPDATE",
  "READY_CHECK", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED",
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
    if event == "UNIT_AURA" and type(arg1) == "string" and arg1 ~= "player" and arg1 ~= "target"
       and arg1 ~= "mouseover" and not arg1:find("^party%d") and not arg1:find("^raid%d")
       and not (arg1:find("^nameplate%d") and UnitIsPlayer(arg1)) then
      return
    end
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
  if event == "UNIT_SPELLCAST_SENT" or event == "UNIT_SPELLCAST_FAILED"
     or event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UI_ERROR_MESSAGE" then
    if db and db.clickDebug and (event == "UI_ERROR_MESSAGE" or arg1 == "player") then
      local parts = { SafeString(arg1) or "?" }  -- "?" = nil or protected
      for i = 1, select("#", ...) do parts[#parts + 1] = SafeString((select(i, ...))) or "?" end
      Print("|cffaaaaaa" .. event .. ": " .. table.concat(parts, ", ") .. "|r")
    end
    if event ~= "UNIT_SPELLCAST_SUCCEEDED" or arg1 ~= "player" then return end
    if arg1 == "player" and X.pendingCast and db then
      local spellID = select(2, ...)
      local ok, name = pcall(SpellName, spellID, nil)
      name = ok and SafeString(name) or nil  -- compared and used as a stats key
      if name and name == X.pendingCast.spell and GetTime() - X.pendingCast.time < 3 then
        X.pendingCast = nil
        X.sessionCasts = X.sessionCasts + 1
        db.castsTotal = (db.castsTotal or 0) + 1
        db.stats = db.stats or {}
        db.stats[name] = (db.stats[name] or 0) + 1
        UpdateCounter()
      end
    end
    Soon()
    return
  end
  if event == "CVAR_UPDATE" then
    if arg1 == "ActionButtonUseKeyDown" or arg1 == "ACTION_BUTTON_USE_KEY_DOWN" then
      ApplyNextRegistration()
      if db then pcall(MakeMacro, true) end -- keep an existing BuffRadar macro in sync
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
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    driver:UnregisterEvent("ADDON_LOADED")  -- one-off
    BuffRadarDB = SanitizeDB(BuffRadarDB)
    db = BuffRadarDB
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
    X.SpecSwap()
  elseif event == "PLAYER_LOGIN" then
    driver:UnregisterEvent("PLAYER_LOGIN")  -- one-off
    if not db then
      BuffRadarDB = SanitizeDB(BuffRadarDB)
      db = BuffRadarDB
      Ignore.Rebuild()
    end
    RequestSpellData()
    local ok, err = pcall(BuildBuffList)
    if not ok then Print("|cffff4040error reading spellbook:|r " .. tostring(err)) end
    ok, err = pcall(BuildUI)
    if not ok then Print("|cffff4040error building window:|r " .. tostring(err)) end
    Print("loaded. Type /br to show the window.")
    if FriendlyPlatesOn() == false then
      Print("friendly nameplates are |cffff4040off|r - nearby players outside your group can't be listed until they're on. Type /br plates to turn them on (or press Shift+V).")
    end
    if not hasAnyBuff then
      Print("You don't know any buffs this addon handles yet; the window will appear once you learn one.")
    end
    StartTicker()
    Soon()
  elseif event == "PLAYER_REGEN_DISABLED" then
    if combatText then combatText:Show() end
    -- Lockdown hasn't started yet inside this handler: finish any window drag now.
    if frame and frame.isMoving then
      frame:StopMovingOrSizing()
      frame.isMoving = false
      SavePosition()
    end
    if grip and grip.isSizing then  -- same for a resize in progress
      frame:StopMovingOrSizing()
      grip.isSizing = false
      db.width = math_floor(frame:GetWidth() + 0.5)
      SavePosition()
    end
    if nextBtn then nextBtn.bGuid, nextBtn.isClear = nil, false end  -- driver clears it
    -- Fallback when the secure combat driver isn't available: this event still runs
    -- just before combat lockdown starts, so the key can be disarmed here.
    if not nextCombatDriver then ClearNext() end
  elseif event == "PLAYER_REGEN_ENABLED" then
    X.afterCombat = true  -- Refresh() pulses the border if work is waiting
    if combatText then combatText:Hide() end
    BuildUI()
    ApplyGeometry()  -- a scale/width change made during combat lands now
    X.ApplyRowLayout()
    ApplyNextRegistration()
    Soon()
  elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
    if db then ScheduleRebuild() end
  else
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
-- This section sits in a do ... end block (left unindented). WoW's Lua 5.1
-- refuses to compile a file whose main chunk has more than 200 local
-- variables in scope at once -- and then NOTHING in the file runs: no window,
-- no /br, no minimap button (the 1.3.2 test build hit exactly this). Locals
-- declared inside a block stop counting when the block ends, so the
-- settings-window helpers below don't use up the file's budget. Only
-- OpenConfig and RefreshConfig (declared near the top) are used outside it.
---------------------------------------------------------------------------
do
local cfg

local function MakeCheck(parent, label, getter, setter)
  local cb = CreateFrame("CheckButton", nil, parent)
  cb:SetSize(24, 24)
  cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
  cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
  cb.label:SetText(label)
  cb.FitLabel = function(self)  -- the label is part of the click target, not just the box
    local w = self.label:GetStringWidth()
    if self.label.maxWidth then w = math_min(w, self.label.maxWidth) end
    self:SetHitRectInsets(0, -(w + 4), 0, 0)
  end
  cb:FitLabel()
  cb:SetScript("OnClick", function(self) setter(self:GetChecked() and true or false) end)
  cb.Update = function(self) self:SetChecked(getter() and true or false) end
  return cb
end

-- Hover help for a settings control: a white title line plus wrapped detail.
-- heading/text may be functions, for help that depends on the current state.
local function Tip(widget, heading, text)
  widget:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(type(heading) == "function" and heading() or heading, 1, 1, 1)
    local t = type(text) == "function" and text() or text
    if t then GameTooltip:AddLine(t, 0.85, 0.85, 0.85, true) end
    GameTooltip:Show()
  end)
  widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Seconds entry box (0-3600). Enter or clicking away saves, Esc cancels;
-- onCommit gets the number, or nil for an empty box. Shows getText() otherwise.
local function MakeSecondsBox(parent, getText, onCommit)
  local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  eb:SetSize(40, 20)
  eb:SetAutoFocus(false)
  eb:SetNumeric(true)
  eb:SetMaxLetters(4)
  eb:SetJustifyH("CENTER")
  eb.Revert = function(self) self:SetText(getText()) end
  eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnEscapePressed", function(self) self.cancel = true; self:ClearFocus() end)
  eb:SetScript("OnEditFocusLost", function(self)
    self:HighlightText(0, 0)
    if self.cancel then self.cancel = false; self:Revert(); return end
    local s = self:GetText()
    local n = tonumber(s)
    if s ~= "" and (not n or n > 3600) then
      Print("Rebuff time must be a whole number from 0 to 3600 seconds.")
    else
      onCommit(n)
    end
    self:Revert()
  end)
  return eb
end

local function MakeButton(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function MakeSlider(parent, x, y, width, minV, maxV, step, onChange)
  local slider = CreateFrame("Slider", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  slider:SetOrientation("HORIZONTAL")
  slider:SetSize(width, 17)
  slider:SetPoint("TOPLEFT", x, y)
  if slider.SetBackdrop then
    slider:SetBackdrop({
      bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
      edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
      tile = true, tileSize = 8, edgeSize = 8,
      insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
  end
  slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  slider:SetMinMaxValues(minV, maxV)
  slider:SetValueStep(step)
  if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
  slider:EnableMouse(true)
  slider:EnableMouseWheel(true)
  slider:SetScript("OnMouseWheel", function(self, delta)
    self:SetValue(math.max(minV, math.min(maxV, self:GetValue() + delta * step)))
  end)
  slider:SetScript("OnValueChanged", function(_, v) onChange(v) end)
  return slider
end

local function OpenColorPicker()
  local c = db.bgColor
  local prev = { c[1], c[2], c[3] }
  local function apply()
    local r, g, b = ColorPickerFrame:GetColorRGB()
    db.bgColor = { r, g, b }
    ApplyAppearance()
    RefreshConfig()
  end
  local function cancel()
    db.bgColor = { prev[1], prev[2], prev[3] }
    ApplyAppearance()
    RefreshConfig()
  end
  if ColorPickerFrame.SetupColorPickerAndShow then
    ColorPickerFrame:SetupColorPickerAndShow({
      swatchFunc = apply, cancelFunc = cancel, hasOpacity = false,
      r = c[1], g = c[2], b = c[3],
    })
  else
    ColorPickerFrame.func = apply
    ColorPickerFrame.cancelFunc = cancel
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.previousValues = { r = c[1], g = c[2], b = c[3] }
    ColorPickerFrame:SetColorRGB(c[1], c[2], c[3])
    ColorPickerFrame:Hide()
    ColorPickerFrame:Show()
  end
end

local function PercentText(v) return math_floor(v * 100 + 0.5) .. "%" end

-- Scale picker: the game's menu dropdown, with one entry per SCALE_PRESETS value.
-- A scale set by /br scale that isn't a preset shows as "Custom (n%)". Clients
-- without the dropdown template get a button that steps through the presets.
local function MakeScaleDropdown(parent, getter, setter)
  local ok, dd = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  if ok and dd and dd.SetupMenu then
    dd:SetWidth(120)
    dd:SetupMenu(function(_, root)
      for _, v in ipairs(SCALE_PRESETS) do
        root:CreateRadio(PercentText(v),
          function(x) return math.abs(getter() - x) < 0.001 end,
          function(x) setter(x) end, v)
      end
    end)
    dd.Update = function(self)
      if self.SetDefaultText then self:SetDefaultText("Custom (" .. PercentText(getter()) .. ")") end
      if self.GenerateMenu then self:GenerateMenu() end
    end
    return dd
  end
  local b = MakeButton(parent, "", 120, function(self)
    local cur, nextV = getter(), SCALE_PRESETS[1]
    for _, v in ipairs(SCALE_PRESETS) do
      if v > cur + 0.001 then nextV = v; break end
    end
    setter(nextV)
    self:Update()
  end)
  b.Update = function(self) self:SetText(PercentText(getter())) end
  return b
end

local function SelectTab(key)
  for k, panel in pairs(cfg.panels) do panel:SetShown(k == key) end
  if cfg.nativeTabs then
    PanelTemplates_SetTab(cfg, cfg.tabBtns[key]:GetID())
  else
    for k, btn in pairs(cfg.tabBtns) do
      if k == key then btn:LockHighlight() else btn:UnlockHighlight() end
    end
  end
end

local function BuildConfig()
  -- Blizzard's standard window (title bar, BuffRadar icon in the portrait
  -- corner, close button, inset content area) so it matches the retail UI.
  -- A client without that template gets the original hand-drawn window.
  cfg = CreateFrame("Frame", "BuffRadarConfig", UIParent, "ButtonFrameTemplate")
  local native = cfg.SetTitle and cfg.Inset and cfg.CloseButton and true or false
  if not native then
    cfg:Hide()
    cfg = CreateFrame("Frame", "BuffRadarConfig", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  end
  cfg:SetSize(600, 470)
  cfg:SetScale(db.cfgScale or 1)
  cfg:SetPoint("CENTER")
  cfg:SetFrameStrata("DIALOG")
  cfg:SetClampedToScreen(true)
  cfg:SetMovable(true)
  cfg:EnableMouse(true)
  cfg:RegisterForDrag("LeftButton")
  cfg:SetScript("OnDragStart", cfg.StartMoving)
  cfg:SetScript("OnDragStop", cfg.StopMovingOrSizing)
  if UISpecialFrames then table.insert(UISpecialFrames, "BuffRadarConfig") end -- Esc closes it

  if native then
    cfg:SetTitle("BuffRadar Settings")
    if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(cfg) end
    if cfg.SetPortraitToAsset then
      cfg:SetPortraitToAsset("Interface\\AddOns\\BuffRadar\\Media\\icon.png")
    elseif ButtonFrameTemplate_HidePortrait then
      ButtonFrameTemplate_HidePortrait(cfg)
    end
  else
    if cfg.SetBackdrop then
      cfg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
      })
      cfg:SetBackdropColor(0.05, 0.06, 0.1, 0.97)
      cfg:SetBackdropBorderColor(0.35, 0.55, 0.8, 1)
    end
    local head = cfg:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    head:SetPoint("TOP", 0, -12)
    head:SetText("|cff33ccffBuff|rRadar Settings")
    local close = CreateFrame("Button", nil, cfg, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
  end

  -- Tabs: Blizzard's bottom tabs on the standard window (named
  -- BuffRadarConfigTab1..5, as PanelTemplates expects), otherwise the
  -- original row of buttons along the top.
  cfg.panels, cfg.tabBtns = {}, {}
  cfg.nativeTabs = native and PanelTemplates_SetNumTabs and PanelTemplates_SetTab and true or false
  local tabDefs = {
    { "look", L["Window"] }, { "alerts", L["Alerts"] }, { "buffs", L["Buffs"] },
    { "behavior", L["Behavior"] }, { "data", L["Ignore & Stats"] },
  }
  local tabList, prevTab = {}, nil
  for i, td in ipairs(tabDefs) do
    local key, label = td[1], td[2]
    local function onClick() SelectTab(key); RefreshConfig() end
    local btn
    if cfg.nativeTabs then
      btn = CreateFrame("Button", "BuffRadarConfigTab" .. i, cfg, "PanelTabButtonTemplate")
      btn:SetID(i)
      btn:SetText(label)
      btn:SetScript("OnClick", onClick)
      if PanelTemplates_TabResize then PanelTemplates_TabResize(btn, 0) end
      if prevTab then
        btn:SetPoint("TOPLEFT", prevTab, "TOPRIGHT", 3, 0)
      else
        btn:SetPoint("TOPLEFT", cfg, "BOTTOMLEFT", 11, 2)
      end
      prevTab = btn
      tabList[i] = btn
    else
      btn = MakeButton(cfg, label, 106, onClick)
      btn:SetPoint("TOPLEFT", 16 + (i - 1) * 112, -40)
    end
    cfg.tabBtns[key] = btn
    local panel = CreateFrame("Frame", nil, cfg)
    if native then  -- inside the template's inset area, below the title bar
      panel:SetPoint("TOPLEFT", cfg.Inset, "TOPLEFT", 4, -4)
      panel:SetPoint("BOTTOMRIGHT", cfg.Inset, "BOTTOMRIGHT", -4, 4)
    else
      panel:SetPoint("TOPLEFT", 8, -70)
      panel:SetPoint("BOTTOMRIGHT", -8, 8)
    end
    panel:Hide()
    cfg.panels[key] = panel
  end
  if cfg.nativeTabs then
    cfg.Tabs = tabList  -- newer PanelTemplates look here; older ones use the names
    PanelTemplates_SetNumTabs(cfg, #tabList)
  end

  local function section(panel, text, x, y)
    local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
  end

  ------------------------------------------------------------------
  -- Tab: Window (look)
  ------------------------------------------------------------------
  local look = cfg.panels.look
  section(look, "Appearance", 10, -6)

  local colorLabel = look:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  colorLabel:SetPoint("TOPLEFT", 14, -34)
  colorLabel:SetText("Background color")
  local swatch = CreateFrame("Button", nil, look, BackdropTemplateMixin and "BackdropTemplate" or nil)
  swatch:SetSize(40, 18)
  swatch:SetPoint("LEFT", colorLabel, "RIGHT", 10, 0)
  if swatch.SetBackdrop then
    swatch:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                         edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    swatch:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
  end
  swatch:SetScript("OnClick", OpenColorPicker)
  cfg.swatch = swatch

  local alphaLabel = look:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  alphaLabel:SetPoint("TOPLEFT", 14, -64)
  alphaLabel:SetText("Background opacity")
  local alphaValue = look:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  alphaValue:SetPoint("LEFT", alphaLabel, "RIGHT", 8, 0)
  cfg.alphaValue = alphaValue
  cfg.slider = MakeSlider(look, 16, -84, 250, 0, 100, 5, function(v)
    v = math.floor(v + 0.5)
    db.bgAlpha = v / 100
    alphaValue:SetText(v .. "%")
    ApplyAppearance()
  end)

  cfg.titleCheck = MakeCheck(look, L["Show BuffRadar title"],
    function() return db.showTitle end,
    function(v) db.showTitle = v; ApplyAppearance() end)
  cfg.titleCheck:SetPoint("TOPLEFT", 10, -116)

  cfg.borderCheck = MakeCheck(look, L["Show border"],
    function() return db.showBorder end,
    function(v) db.showBorder = v; ApplyAppearance() end)
  cfg.borderCheck:SetPoint("TOPLEFT", 10, -142)

  cfg.compactCheck = MakeCheck(look, L["Compact rows (no portraits)"],
    function() return db.compact end,
    function(v) db.compact = v; X.ApplyRowLayout(); Refresh() end)
  cfg.compactCheck:SetPoint("TOPLEFT", 250, -116)

  cfg.charPointCheck = MakeCheck(look, L["Per-character window position"],
    function() return db.charPoint end,
    function(v)
      db.charPoint = v
      if v then
        local k = X.CharKey()
        if k and db.point then db.pointByChar[k] = db.point end
      end
    end)
  cfg.charPointCheck:SetPoint("TOPLEFT", 250, -142)

  local scaleLabel = look:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  scaleLabel:SetPoint("TOPLEFT", 14, -178)
  scaleLabel:SetText("Window scale")
  cfg.scaleDrop = MakeScaleDropdown(look,
    function() return db.scale or 1 end,
    function(v)
      if InCombatLockdown() then Print("Can't rescale the window during combat."); return end
      db.scale = v
      ApplyGeometry()
      RefreshConfig()
    end)
  cfg.scaleDrop:SetPoint("LEFT", scaleLabel, "RIGHT", 12, 0)
  local widthHint = look:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  widthHint:SetPoint("TOPLEFT", 14, -206)
  widthHint:SetText("Drag the window's bottom-right corner to change its width.")

  local resetLook = MakeButton(look, "Reset look", 110, function()
    db.bgColor = { DEFAULTS.bgColor[1], DEFAULTS.bgColor[2], DEFAULTS.bgColor[3] }
    db.bgAlpha = DEFAULTS.bgAlpha
    db.showTitle, db.showBorder, db.scale = true, true, 1
    db.width = DEFAULTS.width
    ApplyGeometry()  -- in combat this lands when combat ends
    ApplyAppearance()
    RefreshConfig()
  end)
  resetLook:SetPoint("TOPLEFT", 14, -232)

  cfg.minimapCheck = MakeCheck(look, L["Minimap button (drag it around the minimap)"],
    function() return db.showMinimap end,
    function(v) db.showMinimap = v; if RefreshMinimapButton then RefreshMinimapButton() end end)
  cfg.minimapCheck:SetPoint("TOPLEFT", 10, -268)

  local cfgScaleLabel = look:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  cfgScaleLabel:SetPoint("TOPLEFT", 14, -308)
  cfgScaleLabel:SetText("Settings window scale")
  cfg.cfgScaleDrop = MakeScaleDropdown(look,
    function() return db.cfgScale or 1 end,
    function(v)
      db.cfgScale = v
      cfg:SetScale(v)
      RefreshConfig()
    end)
  cfg.cfgScaleDrop:SetPoint("LEFT", cfgScaleLabel, "RIGHT", 12, 0)

  ------------------------------------------------------------------
  -- Tab: Alerts
  ------------------------------------------------------------------
  local alerts = cfg.panels.alerts
  section(alerts, "New name alert", 10, -6)

  cfg.soundCheck = MakeCheck(alerts, L["Play a sound when a name appears"],
    function() return db.playSound end,
    function(v) db.playSound = v; if v then PlayAlert() end end)
  cfg.soundCheck:SetPoint("TOPLEFT", 10, -30)

  cfg.soundBtn = MakeButton(alerts, "Sound: droplet", 150, function()
    local order = { "droplet", "system", "none" }
    local cur = 1
    for i, s in ipairs(order) do if db.alertSound == s then cur = i end end
    db.alertSound = order[cur % #order + 1]
    RefreshConfig()
    if db.playSound then PlayAlert() end
  end)
  cfg.soundBtn:SetPoint("TOPLEFT", 34, -58)

  local test = MakeButton(alerts, "Test", 60, PlayAlert)
  test:SetPoint("LEFT", cfg.soundBtn, "RIGHT", 10, 0)

  cfg.muteInstCheck = MakeCheck(alerts, L["No alert sound in dungeons, raids or battlegrounds"],
    function() return db.muteInInstance end,
    function(v) db.muteInInstance = v end)
  cfg.muteInstCheck:SetPoint("TOPLEFT", 10, -92)

  section(alerts, "Cast counter", 10, -136)
  cfg.counterCheck = MakeCheck(alerts, L["Show cast counter in the window"],
    function() return db.showCounter end,
    function(v) db.showCounter = v; UpdateCounter(); Refresh() end)
  cfg.counterCheck:SetPoint("TOPLEFT", 10, -160)

  local resetCount = MakeButton(alerts, "Reset counts", 110, function()
    X.sessionCasts, db.castsTotal = 0, 0
    UpdateCounter()
    Print("Cast counts reset.")
  end)
  resetCount:SetPoint("TOPLEFT", 34, -190)

  section(alerts, "Keybinds", 10, -230)
  local keyText = alerts:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  keyText:SetPoint("TOPLEFT", 14, -254)
  local keyText2 = alerts:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  keyText2:SetPoint("TOPLEFT", 14, -270)
  cfg.keyText, cfg.keyText2 = keyText, keyText2

  local setKey = MakeButton(alerts, "Set keybind", 120, OpenKeybinds)
  setKey:SetPoint("TOPLEFT", 14, -288)
  local makeMacro = MakeButton(alerts, "Create macro", 120, function() MakeMacro(false) end)
  makeMacro:SetPoint("LEFT", setKey, "RIGHT", 10, 0)

  local hint = alerts:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 14, -316)
  hint:SetWidth(420)
  hint:SetJustifyH("LEFT")
  hint:SetText("Cast next buff targets the first player in the list. Doesn't fire in combat.")

  ------------------------------------------------------------------
  -- Tab: Buffs
  ------------------------------------------------------------------
  local buffs = cfg.panels.buffs
  section(buffs, "Buffs to offer (only ones you know are listed)", 10, -6)

  -- Each buff row: checkbox + label, then a rebuff-time box. Empty box = use
  -- the all-buffs time below; a number overrides it for that buff only.
  cfg.buffChecks = {}
  local cols = { 10, 302 }
  local rebuffTip = "Offer this buff again when less than this many seconds of it remain. " ..
    "Leave empty to use the all-buffs time below. Press Enter to save, Esc to cancel."
  for i = 1, 16 do
    local cb = MakeCheck(buffs, "", function() return false end, function() end)
    local col = (i <= 8) and 1 or 2
    local row = (i - 1) % 8
    cb:SetPoint("TOPLEFT", cols[col], -34 - row * 26)
    cb.label:SetWidth(196)
    cb.label:SetJustifyH("LEFT")
    if cb.label.SetWordWrap then cb.label:SetWordWrap(false) end
    cb.label.maxWidth = 196
    Tip(cb, function() return cb.itemLabel or "" end,
      function() return "Offered to: " .. (cb.itemWho or "?") .. ". Untick to stop offering it." end)
    cb.rebuffBox = MakeSecondsBox(buffs,
      function() return (cb.itemKey and db.rebuffPer[cb.itemKey]) and tostring(db.rebuffPer[cb.itemKey]) or "" end,
      function(n)
        if not cb.itemKey then return end
        db.rebuffPer[cb.itemKey] = n  -- nil (empty box) = back to the all-buffs time
        Refresh()
      end)
    cb.rebuffBox:SetPoint("LEFT", buffs, "TOPLEFT", cols[col] + 236, -46 - row * 26)
    Tip(cb.rebuffBox, "Rebuff time (seconds)", rebuffTip)
    cb:Hide()
    cb.rebuffBox:Hide()
    cfg.buffChecks[i] = cb
  end
  cfg.rebuffHeads = {}
  for c = 1, 2 do
    local head = buffs:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    head:SetPoint("BOTTOM", buffs, "TOPLEFT", cols[c] + 256, -32)
    head:SetText("Rebuff (s)")
    head:Hide()
    cfg.rebuffHeads[c] = head
  end
  cfg.noBuffs = buffs:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  cfg.noBuffs:SetPoint("TOPLEFT", 14, -36)
  cfg.noBuffs:SetText("You don't know any supported buffs yet.")

  cfg.selfCheck = MakeCheck(buffs, L["Buff myself first (all buffs that suit me)"],
    function() return db.includeSelf end,
    function(v) db.includeSelf = v; Refresh() end)
  cfg.selfCheck:SetPoint("TOPLEFT", 10, -252)
  Tip(cfg.selfCheck, "Buff myself first",
    "Check your own character for every buff that suits your class and list yourself at the top. " ..
    "Self-only buffs (like a shaman's shield) are always checked.")

  local rebuffLabel = buffs:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  rebuffLabel:SetPoint("TOPLEFT", 14, -290)
  rebuffLabel:SetText("Offer a buff again when less than")
  cfg.rebuffDefault = MakeSecondsBox(buffs,
    function() return tostring(db.rebuff or 30) end,
    function(n)
      if not n then return end  -- the all-buffs time can't be empty
      db.rebuff = n
      Refresh()
    end)
  cfg.rebuffDefault:SetPoint("LEFT", rebuffLabel, "RIGHT", 10, 0)
  local rebuffUnit = buffs:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  rebuffUnit:SetPoint("LEFT", cfg.rebuffDefault, "RIGHT", 6, 0)
  rebuffUnit:SetText("seconds remain (all buffs)")
  Tip(cfg.rebuffDefault, "Rebuff time for all buffs (seconds)",
    "A buff that runs out sooner than this is offered again. 0 = only when it's gone. " ..
    "Per-buff boxes above override it. Same as /br rebuff <seconds>.")

  local rebuffHint = buffs:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  rebuffHint:SetPoint("TOPLEFT", 14, -314)
  rebuffHint:SetWidth(540)
  rebuffHint:SetJustifyH("LEFT")
  rebuffHint:SetText("Whole seconds, 0 to 3600. Press Enter to save, Esc to cancel.")

  ------------------------------------------------------------------
  -- Tab: Behavior
  ------------------------------------------------------------------
  local beh = cfg.panels.behavior
  section(beh, "When to show & scan", 10, -6)

  cfg.groupCheck = MakeCheck(beh, L["Only show in a party or raid"],
    function() return db.groupOnly end,
    function(v) db.groupOnly = v; Refresh() end)
  cfg.groupCheck:SetPoint("TOPLEFT", 10, -30)

  cfg.cityCheck = MakeCheck(beh, L["Pause scanning in major cities"],
    function() return db.pauseInCities end,
    function(v) db.pauseInCities = v; Refresh() end)
  cfg.cityCheck:SetPoint("TOPLEFT", 10, -56)

  cfg.bgCheck = MakeCheck(beh, L["Pause in battlegrounds and arenas"],
    function() return db.pauseInBG end,
    function(v) db.pauseInBG = v; Refresh() end)
  cfg.bgCheck:SetPoint("TOPLEFT", 10, -82)

  section(beh, "Casting & order", 302, -6)

  cfg.groupCastCheck = MakeCheck(beh, L["Offer group buffs in a party or raid"],
    function() return db.groupCast end,
    function(v) db.groupCast = v; Refresh() end)
  cfg.groupCastCheck:SetPoint("TOPLEFT", 296, -30)

  local gcLabel = beh:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gcLabel:SetPoint("TOPLEFT", 320, -62)
  gcLabel:SetText("...when at least this many need it:")
  local gcValue = beh:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gcValue:SetPoint("LEFT", gcLabel, "RIGHT", 6, 0)
  cfg.gcValue = gcValue
  cfg.gcSlider = MakeSlider(beh, 322, -80, 150, 2, 10, 1, function(v)
    db.groupCastMin = math.floor(v + 0.5)
    gcValue:SetText(tostring(db.groupCastMin))
    Refresh()
  end)
  -- Group-cast offers need group versions of buffs (Classic only): hide the
  -- controls here and move the rest of the column up into their space.
  local castY = 0
  if not CLASSIC_FEATURES then
    cfg.groupCastCheck:Hide()
    gcLabel:Hide()
    gcValue:Hide()
    cfg.gcSlider:Hide()
    castY = 82
  end

  cfg.oorCheck = MakeCheck(beh, L["Show out-of-range players (greyed)"],
    function() return db.showOutOfRange end,
    function(v) db.showOutOfRange = v; Refresh() end)
  cfg.oorCheck:SetPoint("TOPLEFT", 296, -112 + castY)

  cfg.sortBtn = MakeButton(beh, "Sort: name", 130, function()
    if db.sortMode == "name" then db.sortMode = "role"
    elseif db.sortMode == "role" then db.sortMode = "distance"
    else db.sortMode = "name" end
    RefreshConfig()
    Refresh()
  end)
  cfg.sortBtn:SetPoint("TOPLEFT", 320, -140 + castY)
  local sortHint = beh:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  sortHint:SetPoint("LEFT", cfg.sortBtn, "RIGHT", 8, 0)
  sortHint:SetText("role = tanks & leaders · distance = nearest first")

  local behHint = beh:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  behHint:SetPoint("TOPLEFT", 14, -140)
  behHint:SetWidth(270)
  behHint:SetJustifyH("LEFT")
  behHint:SetText("Right-click any name in the BuffRadar window to ignore that player; manage the list on the Ignore & Stats tab.")

  ------------------------------------------------------------------
  -- Tab: Ignore & Stats
  ------------------------------------------------------------------
  local data = cfg.panels.data
  section(data, "Ignored players", 10, -6)
  cfg.ignoreText = data:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cfg.ignoreText:SetPoint("TOPLEFT", 14, -32)
  cfg.ignoreText:SetWidth(540)
  cfg.ignoreText:SetJustifyH("LEFT")

  -- One cell per ignored name (3 columns x 4 rows), each with a remove button.
  -- RefreshConfig fills them; names past the 12th are counted in ignoreText.
  cfg.ignoreCells = {}
  for i = 1, 12 do
    local col, row = (i - 1) % 3, math_floor((i - 1) / 3)
    local cell = CreateFrame("Frame", nil, data)
    cell:SetSize(176, 20)
    cell:SetPoint("TOPLEFT", 14 + col * 182, -50 - row * 20)
    local x = CreateFrame("Button", nil, cell)
    x:SetSize(14, 14)
    x:SetPoint("LEFT", 0, 0)
    x:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    x:SetHighlightTexture("Interface\\Buttons\\UI-StopButton", "ADD")
    x:SetScript("OnClick", function()
      if not cell.ignored then return end
      local removed = Ignore.Remove(cell.ignored, true)  -- just this entry
      Print("No longer ignoring " .. table.concat(removed, ", ") .. ".")
      RefreshConfig()
      Refresh()
    end)
    x:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine("Stop ignoring " .. tostring(cell.ignored))
      if cell.ignored and not cell.ignored:find("-", 1, true) then
        GameTooltip:AddLine("(this name on every realm)", 0.6, 0.6, 0.6)
      end
      GameTooltip:Show()
    end)
    x:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cell.text = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cell.text:SetPoint("LEFT", x, "RIGHT", 4, 0)
    cell.text:SetPoint("RIGHT", cell, "RIGHT", -2, 0)
    cell.text:SetJustifyH("LEFT")
    if cell.text.SetWordWrap then cell.text:SetWordWrap(false) end
    cell:Hide()
    cfg.ignoreCells[i] = cell
  end

  local clearIgnores = MakeButton(data, "Clear ignore list", 140, function()
    wipe(db.ignored)
    wipe(Ignore.index)
    Print("Ignore list cleared.")
    RefreshConfig()
    Refresh()
  end)
  clearIgnores:SetPoint("TOPLEFT", 14, -138)

  section(data, "Casts by spell (all-time)", 10, -178)
  cfg.statsText = data:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cfg.statsText:SetPoint("TOPLEFT", 14, -204)
  cfg.statsText:SetWidth(540)
  cfg.statsText:SetJustifyH("LEFT")
  local resetStats = MakeButton(data, "Reset stats", 110, function()
    wipe(db.stats)
    Print("Cast statistics reset.")
    RefreshConfig()
  end)
  resetStats:SetPoint("TOPLEFT", 14, -290)

  ------------------------------------------------------------------
  -- Hover help (the Buffs tab sets its own above)
  ------------------------------------------------------------------
  -- Window
  Tip(swatch, "Background color", "Click to pick the BuffRadar window's background color.")
  Tip(cfg.slider, "Background opacity", "0% = fully see-through background (text and icons stay visible). Scroll the mouse wheel to adjust in steps.")
  Tip(cfg.titleCheck, "Show BuffRadar title", "The \"BuffRadar\" name in the window's top-left corner.")
  Tip(cfg.borderCheck, "Show border", "The thin blue edge around the window.")
  Tip(cfg.compactCheck, "Compact rows", "Half-height rows without portraits, for long raid lists. The list text size is /br text <0.8-1.5>.")
  Tip(cfg.charPointCheck, "Per-character window position", "Each character keeps its own window spot. Off: one position shared by all characters.")
  Tip(cfg.scaleDrop, "Window scale", "Makes everything in the list window bigger or smaller. Can't be changed during combat. /br scale accepts any value from 0.5 to 2.")
  Tip(resetLook, "Reset look", "Restores the default color, opacity, title, border, scale and width. Your position and other settings are kept.")
  Tip(cfg.minimapCheck, "Minimap button", "Left-click it to show or hide the window, right-click for settings, drag it around the minimap. The addon compartment (minimap menu) works either way.")
  Tip(cfg.cfgScaleDrop, "Settings window scale", "Makes this settings window bigger or smaller.")
  -- Alerts
  Tip(cfg.soundCheck, "New name alert", "Play a sound when a player appears on the list. Mute it any time with your Mute / unmute key or /br sound.")
  Tip(cfg.soundBtn, "Alert sound", "Click to switch between the water droplet, the game's raid warning sound and no sound. Plays the new choice.")
  Tip(test, "Test", "Play the alert sound now.")
  Tip(cfg.muteInstCheck, "Quiet in instances", "No alert sound in dungeons, raids, battlegrounds or arenas. The list still updates.")
  Tip(cfg.counterCheck, "Cast counter", "Shows casts made through BuffRadar this session and all-time at the bottom of the window.")
  Tip(resetCount, "Reset counts", "Sets this session's and the all-time cast counts to zero. Per-spell stats (Ignore & Stats tab) are kept.")
  Tip(setKey, "Set keybind", "Opens Key Bindings at the BuffRadar section: Cast next buff, Show / hide window, Mute / unmute sound.")
  Tip(makeMacro, "Create macro", "Puts a BuffRadar macro on your cursor. Drop it on an action bar; pressing it casts the next buff.")
  -- Behavior
  Tip(cfg.groupCheck, "Only show in a party or raid", "Hide the window while you're solo. The Cast next buff key still works.")
  Tip(cfg.cityCheck, "Pause in major cities", "No scanning in capital cities, where crowds would fill the list. /br debug shows whether your zone counts as a city.")
  Tip(cfg.bgCheck, "Pause in battlegrounds and arenas", "No scanning in PvP instances.")
  Tip(cfg.groupCastCheck, "Offer group buffs", "When enough group members need a buff, offer its group version (one cast covers the party).")
  Tip(cfg.gcSlider, "Group buff threshold", "How many group members must need the buff before the group version is offered.")
  Tip(cfg.oorCheck, "Show out-of-range players", "Keep players who are too far away on the list, greyed out and not clickable, so you see who's coming.")
  Tip(cfg.sortBtn, "List order", "Click to switch: name = alphabetical; role = you, then tanks, then group leaders; distance = nearest first (in range, then in group range, then the rest). After that, players in range come first, then group members, then by name.")
  -- Ignore & Stats
  Tip(clearIgnores, "Clear ignore list", "Stops ignoring everyone on the list.")
  Tip(resetStats, "Reset stats", "Clears the casts-by-spell statistics. The cast counter is kept.")

  cfg:SetScript("OnShow", function() RefreshConfig() end)
  SelectTab("look")
  cfg:Hide()
end

RefreshConfig = function()
  if not cfg or not cfg:IsShown() then return end
  local c = db.bgColor
  if cfg.swatch.SetBackdropColor then cfg.swatch:SetBackdropColor(c[1], c[2], c[3], 1) end
  cfg.slider:SetValue(math.floor((db.bgAlpha or 0.92) * 100 + 0.5))
  cfg.alphaValue:SetText(math.floor((db.bgAlpha or 0.92) * 100 + 0.5) .. "%")
  cfg.scaleDrop:Update()
  cfg.cfgScaleDrop:Update()
  cfg.titleCheck:Update()
  cfg.borderCheck:Update()
  if cfg.compactCheck then cfg.compactCheck:Update() end
  if cfg.charPointCheck then cfg.charPointCheck:Update() end
  cfg.minimapCheck:Update()
  cfg.soundCheck:Update()
  cfg.soundBtn:SetText("Sound: " .. tostring(db.alertSound))
  cfg.muteInstCheck:Update()
  cfg.counterCheck:Update()
  cfg.keyText:SetText("Cast next buff: " .. KeybindText(NEXT_BINDING))
  cfg.keyText2:SetText("Show / hide: " .. KeybindText("BUFFRADAR_TOGGLE") ..
    "    Mute: " .. KeybindText("BUFFRADAR_MUTE"))
  cfg.groupCheck:Update()
  cfg.cityCheck:Update()
  cfg.bgCheck:Update()
  cfg.groupCastCheck:Update()
  cfg.gcSlider:SetValue(db.groupCastMin or 3)
  cfg.gcValue:SetText(tostring(db.groupCastMin or 3))
  cfg.oorCheck:Update()
  cfg.sortBtn:SetText("Sort: " .. tostring(db.sortMode))

  -- Ignore list: one removable cell per name, the overflow counted in the summary
  local names = Ignore.Sorted()
  local cells = cfg.ignoreCells
  if #names == 0 then
    cfg.ignoreText:SetText("Nobody is ignored. Right-click a name in the window to ignore that player.")
  elseif #names > #cells then
    cfg.ignoreText:SetText(string.format("Ignored (%d) — %d more not shown; /br ignorelist lists all, /br unignore <name> removes one.",
      #names, #names - #cells))
  else
    cfg.ignoreText:SetText(string.format("Ignored (%d) — click the red button to stop ignoring a player. A name without a realm covers every realm.",
      #names))
  end
  for i, cell in ipairs(cells) do
    cell.ignored = names[i]
    if names[i] then
      cell.text:SetText(names[i])
      cell:Show()
    else
      cell:Hide()
    end
  end

  -- Stats summary: top 8 spells by count
  local statRows = {}
  for name, n in pairs(db.stats or {}) do statRows[#statRows + 1] = { name = name, n = n } end
  table.sort(statRows, function(a, b) return a.n > b.n end)
  if #statRows == 0 then
    cfg.statsText:SetText("No casts recorded yet. Statistics count casts made through BuffRadar.")
  else
    local parts = {}
    for i = 1, math.min(8, #statRows) do
      parts[#parts + 1] = string.format("%s: %d", statRows[i].name, statRows[i].n)
    end
    cfg.statsText:SetText(table.concat(parts, "   ·   "))
  end

  local items = {}
  for _, b in ipairs(myBuffs) do
    items[#items + 1] = { key = b.key, default = b.default, label = b.name, who = b.who }
  end
  if next(myBlessing) then
    items[#items + 1] = { key = "BLESSINGS", default = true, label = "Blessings", who = "one per class" }
  end
  for i, cb in ipairs(cfg.buffChecks) do
    local it = items[i]
    if it then
      cb.itemKey, cb.itemLabel, cb.itemWho = it.key, it.label, it.who
      cb.label:SetText(it.label .. "  |cff888888" .. (it.who or "") .. "|r")
      cb:FitLabel()
      cb:SetChecked(IsOn(it.key, it.default) and true or false)
      cb:SetScript("OnClick", function(self)
        db.enabled[it.key] = self:GetChecked() and true or false
        Refresh()
      end)
      cb:Show()
      -- Blessings have no per-buff time (Missing() uses the all-buffs one)
      local showBox = it.key ~= "BLESSINGS"
      cb.rebuffBox:SetShown(showBox)
      if showBox and not cb.rebuffBox:HasFocus() then cb.rebuffBox:Revert() end
    else
      cb.itemKey = nil
      cb:Hide()
      cb.rebuffBox:Hide()
    end
  end
  cfg.rebuffHeads[1]:SetShown(#items > 0)
  cfg.rebuffHeads[2]:SetShown(#items > 8)
  if not cfg.rebuffDefault:HasFocus() then cfg.rebuffDefault:Revert() end
  cfg.noBuffs:SetShown(#items == 0)
  cfg.selfCheck:Update()
end

-- Toggles the settings window; forceShow opens it without toggling it closed.
OpenConfig = function(forceShow)
  if not cfg then BuildConfig() end
  if cfg:IsShown() and not forceShow then cfg:Hide() else cfg:Show() end
end

-- Esc > Options > AddOns > BuffRadar: a short page with a button that opens
-- the full settings window (which has more room than the options page).
if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
  local page = CreateFrame("Frame")
  local head = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  head:SetPoint("TOPLEFT", 16, -16)
  head:SetText("|cff33ccffBuff|rRadar")
  local about = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  about:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -10)
  about:SetWidth(520)
  about:SetJustifyH("LEFT")
  about:SetText("BuffRadar's settings have their own window. You can also open it with the gear " ..
    "icon in the BuffRadar window, by right-clicking the minimap button or the addon menu " ..
    "entry, or with /br config.")
  local open = MakeButton(page, "Open BuffRadar settings", 200, function()
    if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then pcall(HideUIPanel, SettingsPanel) end
    OpenConfig(true)
  end)
  open:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 0, -14)
  local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, page, "BuffRadar")
  if ok and category then pcall(Settings.RegisterAddOnCategory, category) end
end
end -- config window block


---------------------------------------------------------------------------
-- Slash commands (in a do-block too: see the config window section)
---------------------------------------------------------------------------
do
local function OnOff(v) return v and "|cff00ff00on|r" or "|cffff4040off|r" end

local function ListBuffs()
  Print("Buffs you can cast (toggle with /br toggle KEY):")
  local any = false
  for _, b in ipairs(myBuffs) do
    any = true
    Print(string.format("  %s  -  %s (%s)  [%s]", b.key, b.name, b.who or "", OnOff(IsOn(b.key, b.default))))
  end
  if next(myBlessing) then
    any = true
    Print(string.format("  BLESSINGS  -  paladin blessings by class  [%s]", OnOff(IsOn("BLESSINGS", true))))
  end
  if not any then Print("  (none known)") end
end

SLASH_BUFFRADAR1 = "/br"
SLASH_BUFFRADAR2 = "/buffradar"
-- /br selftest: one paste-able block for bug reports.
function X.SelfTest()
  local ver, build, _, iface = GetBuildInfo()
  Print("BuffRadar self-test -- paste this whole block into a bug report:")
  Print(string.format("  version %s · %s edition · interface %s · client %s build %s",
    "1.4.0", CLASSIC_FEATURES and "Forever" or "Retail", tostring(iface), tostring(ver), tostring(build)))
  Print(string.format("  settings dbVersion %s · sort %s · cast mode %s · scale %s",
    tostring(db.dbVersion), tostring(db.sortMode), tostring(db.castMethod), tostring(db.scale)))
  if #myBuffs == 0 then Print("  buffs found: none") end
  for _, b in ipairs(myBuffs) do
    local id
    for _, d in ipairs(BUFF_DEFS) do if d.key == b.key then id = d.id break end end
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
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  if not db then Print("Settings not loaded yet."); return end
  if not built and not InCombatLockdown() then
    local ok, err = pcall(BuildUI)
    if not ok then Print("|cffff4040error building window:|r " .. tostring(err)) end
  end

  local needsOOC = { [""]=true, show=true, hide=true, reset=true, scale=true, macro=true }
  if needsOOC[cmd] and InCombatLockdown() then
    Print("Can't do that during combat.")
    return
  end

  if cmd == "" then
    if frame and frame:IsShown() then
      db.hidden, sessionShow = true, false
      frame:Hide()
      Print("Hidden.")
    else
      db.hidden, sessionShow = false, true
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
  elseif cmd == "sound" then
    db.playSound = not db.playSound
    Print("Droplet sound " .. OnOff(db.playSound))
    if db.playSound then PlayAlert() end
  elseif cmd == "count" or cmd == "counts" then
    Print(string.format("Casts through BuffRadar: %d this session, %d all-time.", X.sessionCasts, db.castsTotal or 0))
  elseif cmd == "resetcount" then
    X.sessionCasts, db.castsTotal = 0, 0
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
    if m == "name" or m == "role" or m == "distance" then db.sortMode = m
    elseif db.sortMode == "name" then db.sortMode = "role"
    elseif db.sortMode == "role" then db.sortMode = "distance"
    else db.sortMode = "name" end
    Print("List order: " .. db.sortMode ..
      (db.sortMode == "role" and " (tanks & leaders first)" or
       db.sortMode == "distance" and " (nearest first)" or ""))
    Refresh()
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
  elseif cmd == "scale" then
    local n = tonumber(rest)
    if n and n >= 0.5 and n <= 2 then
      db.scale = n
      ApplyGeometry()
      if RefreshConfig then RefreshConfig() end
    else
      Print("Usage: /br scale <0.5 - 2>")
    end
  elseif cmd == "reset" then
    db.point = nil
    if frame then RestorePosition() end
    Print("Position reset.")
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
    Print("  /br ignore <name> | unignore <name> | ignorelist")
    Print("  /br rebuff KEY <sec>  - per-buff rebuff timing (see /br buffs for keys)")
    Print("  /br alertsound droplet|system|none  - new-name alert sound")
    Print("  /br announce  - post missing buffs to party/raid chat")
    Print("  /br signore <name> | unsignore <name>  - ignore for this session only")
    Print("  /br bg  - pause in battlegrounds   /br minimap  - toggle minimap button")
    Print("  /br stats  - casts by spell (all-time)")
  end
  Refresh()
end

SlashCmdList.BUFFRADAR = function(msg)
  local ok, err = pcall(HandleSlash, msg)
  if not ok then Print("|cffff4040error:|r " .. tostring(err)) end
end
end -- slash commands block
