-- BuffRadar - click-to-buff list for World of Warcraft (RETAIL edition)
-- Ported from the WoW: Forever edition (1.2.3). Same engine; the buff set,
-- class tables and interface version target retail (Midnight, patch 12.1.5).
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
local WIDTH     = 210
local HEADER_H  = 24
local MAX_ICONS = 5
local UPDATE_INTERVAL = 0.4
local FOOTER_H  = 16
local SOUND_FILE = "Interface\\AddOns\\BuffRadar\\Media\\droplet.ogg"

---------------------------------------------------------------------------
-- Buff data. Edit freely.
--   id/name : rank-1 spell id (used to get the localized name) + English fallback
--   also    : other spells that count as "already has it" (group / greater versions)
--   classes : which classes actually benefit
--   on      : enabled by default (toggle in game with /br toggle KEY)
---------------------------------------------------------------------------
-- Retail edition: all thirteen classes. (The Forever edition lists nine.)
local ALL  = { WARRIOR=true, PALADIN=true, HUNTER=true, ROGUE=true, PRIEST=true,
               SHAMAN=true, MAGE=true, WARLOCK=true, DRUID=true,
               DEATHKNIGHT=true, MONK=true, DEMONHUNTER=true, EVOKER=true }
-- Retail mana users: hunters use focus, so they drop off this list; evokers and
-- monks (Mistweaver) join it.
local MANA = { PALADIN=true, PRIEST=true, SHAMAN=true, MAGE=true,
               WARLOCK=true, DRUID=true, MONK=true, EVOKER=true }

local MELEE = { WARRIOR=true, ROGUE=true, PALADIN=true, SHAMAN=true, DRUID=true,
                DEATHKNIGHT=true, MONK=true, DEMONHUNTER=true }
local TANKS = { WARRIOR=true, PALADIN=true, DRUID=true, DEATHKNIGHT=true,
                MONK=true, DEMONHUNTER=true }

-- Fields:
--   key      settings key (/br toggle KEY, or the checkboxes in /br config)
--   id/name  spell to cast (rank-1 id gives the localized name; English fallback)
--   choices  instead of id/name: alternatives in priority order; the first one you know
--            is cast, and ANY of them already on the target counts as "has it"
--   also     other auras that count as "has it" (group / greater versions)
--   classes  who benefits (ignored for self-only buffs)
--   self     true = can only be cast on yourself (shown on your own row)
--   who      short label for the settings window
--   on       enabled by default
-- Retail edition buff set. Retail has no spell ranks and no separate group
-- versions: casting a raid buff on one group member applies it to the whole
-- party/raid in range, so the per-person list simply clears as the aura lands.
-- Blizzard's own list of player-cast long-term raid buffs (hotfix notes,
-- 2026-04-03): Mark of the Wild, Arcane Intellect, Battle Shout, Power Word:
-- Fortitude, Skyfury, Source of Magic, Symbiotic Relationship, Blessing of
-- the Bronze. The last two are deliberately NOT here: each can sit on only
-- ONE player per caster, so everyone else would show as "missing" forever.
-- Spells from the Forever edition that retail removed (mage armors, Divine
-- Spirit, Fear Ward, Inner Fire, blessings, ...) are gone too — BuffRadar
-- only ever offers spells found in your spellbook, so they could never fire.
local BUFF_DEFS = {
  -- Mage
  { key="ARCANE_INTELLECT", id=1459,  name="Arcane Intellect",
    also={}, classes=MANA, who="mana users", on=true },
  -- Warrior (new in the retail edition: warriors have no buffs in Forever)
  { key="BATTLE_SHOUT",     id=6673,  name="Battle Shout",
    also={}, classes=ALL, who="everyone", on=true },
  -- Priest
  { key="FORTITUDE",        id=1243,  name="Power Word: Fortitude",
    also={}, classes=ALL, who="everyone", on=true },
  -- Druid
  { key="MARK_OF_THE_WILD", id=1126,  name="Mark of the Wild",
    also={}, classes=ALL, who="everyone", on=true },
  { key="THORNS",           id=467,   name="Thorns",
    also={}, classes=MELEE, who="melee classes (PvP talent)", on=false },
  -- Shaman
  { key="SKYFURY",          id=462854, name="Skyfury",
    also={}, classes=ALL, who="everyone", on=true },
  { key="SHAMAN_SHIELD", self=true, who="you", on=true,
    choices={ {52127, "Water Shield"}, {324, "Lightning Shield"} } },
  { key="EARTH_SHIELD",     id=974,   name="Earth Shield",
    also={}, classes=TANKS, who="tanks", on=false },
  -- Evoker (new in the retail edition)
  { key="BLESSING_OF_THE_BRONZE", id=381732, name="Blessing of the Bronze",
    also={}, classes=ALL, who="everyone", on=true },
  -- Warlock
  { key="UNENDING_BREATH",  id=5697,  name="Unending Breath",
    also={}, classes=ALL, who="everyone (situational)", on=false },
}

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
  sortMode = "name",   -- list order: "name" or "role" (tanks and healers first)
  ignored = {},        -- player names BuffRadar never lists (right-click a row)
  rebuffPer = {},      -- per-buff rebuff thresholds in seconds: buff key -> seconds
  alertSound = "droplet", -- alert sound: "droplet", "system" or "none"
  muteInInstance = false, -- no alert sound while in a dungeon, raid or battleground
  showMinimap = true,  -- minimap button (the addon compartment works regardless)
  minimapAngle = 215,  -- minimap button position, degrees
  pauseInBG = false,   -- pause listing in battlegrounds and arenas
  stats = {},          -- all-time casts per spell name: name -> count
}
local db

-- SavedVariables sanity check: anything missing, mistyped, out of range or left over
-- from an older layout is repaired or dropped, so a damaged WTF file can't break the addon.
local KNOWN_KEYS = { point = true, dbVersion = true }
for k in pairs(DEFAULTS) do KNOWN_KEYS[k] = true end
local ENUMS = {
  castMethod = { target = true, id = true, macro = true, rank = true },
  clickReg = { both = true, down = true, up = true },
  sortMode = { name = true, role = true },
  alertSound = { droplet = true, system = true, none = true },
}
local RANGES = { bgAlpha = { 0, 1 }, scale = { 0.5, 2 }, rebuff = { 0, 3600 }, castsTotal = { 0, 1e9 },
                 groupCastMin = { 2, 40 }, minimapAngle = { 0, 360 } }

local function IsNumber(v)
  return type(v) == "number" and v == v and v ~= math_huge and v ~= -math_huge
end
local function Clamp(v, lo, hi) return math_max(lo, math_min(hi, v)) end

local function SanitizeDB(saved)
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

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffBuffRadar|r: " .. tostring(msg))
end

---------------------------------------------------------------------------
-- Localization scaffolding: enUS strings are the keys. A translation file
-- can set BuffRadarLocales["deDE"] = { ["Paused in a major city."] = "..." }
-- before this file loads; only the window's status lines are wired so far.
---------------------------------------------------------------------------
local L = {
  ["Paused in a major city."] = "Paused in a major city.",
  ["Paused in a battleground."] = "Paused in a battleground.",
  ["Everyone nearby is buffed."] = "Everyone nearby is buffed.",
  ["Friendly nameplates are off."] = "Friendly nameplates are off.",
  ["No supported buffs in your spellbook."] = "No supported buffs in your spellbook.",
}
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
local function BookInfo(i)
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

local function BuildBuffList()
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
      known[n] = true
      bookCount = bookCount + 1
      ranks[n] = ranks[n] or {}
      local num = tonumber((sub or ""):match("(%d+)")) or 0
      table.insert(ranks[n], { rank = num, sub = sub, id = id })
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
                                who = d.who, default = d.on, groupName = groupName }
    end
  end

  wipe(myBlessing)
  for class, list in pairs(BLESSING_PRIORITY) do
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
local function Missing(unit, out)
  wipe(out)
  local _, class = UnitClass(unit)
  if not class then return 0 end
  local isSelf = UnitIsUnit(unit, "player")
  scanUnit = nil  -- force a fresh index scan (fallback path) for this unit
  local n = 0
  for i = 1, #myBuffs do
    local b = myBuffs[i]
    local applies
    if b.self then
      applies = isSelf
    else
      applies = b.classes[class] and (not isSelf or db.includeSelf)
    end
    if applies and IsOn(b.key, b.default) and not OnCooldown(b.name)
       and not HasAny(unit, b.names, (db.rebuffPer and db.rebuffPer[b.key]) or db.rebuff) then
      n = n + 1
      out[n] = b.name
    end
  end
  local bl = myBlessing[class]
  if bl and IsOn("BLESSINGS", true) and (not isSelf or db.includeSelf)
     and not HasAny(unit, bl.names) then
    n = n + 1
    out[n] = bl.name
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
  if db.sortMode == "role" and (a.role or 3) ~= (b.role or 3) then
    return (a.role or 3) < (b.role or 3)
  end
  if (a.outOfRange or false) ~= (b.outOfRange or false) then return not a.outOfRange end
  if a.group ~= b.group then return a.group end
  return (a.name or "") < (b.name or "")
end

-- Sort priority for "role" mode: you, then tanks (raid MAINTANK/MAINASSIST),
-- then group leaders, then everyone else. Classic gives no spec/role query,
-- so this is roster flags only — no guessing from class.
local function RoleOf(unit)
  if UnitIsUnit(unit, "player") then return 0 end
  local idx = unit:match("^raid(%d+)$")
  if idx and GetRaidRosterInfo then
    local ok, _, _, _, _, _, _, _, _, role = pcall(GetRaidRosterInfo, tonumber(idx))
    if ok and (role == "MAINTANK" or role == "MAINASSIST") then return 1 end
  end
  if UnitIsGroupLeader and UnitIsGroupLeader(unit) then return 2 end
  return 3
end

local function Consider(unit, isGroup)
  if not Valid(unit) then return end
  local guid = UnitGUID(unit)
  if not guid or seen[guid] then return end
  local okN, nm = pcall(UnitName, unit)
  nm = okN and SafeString(nm) or nil
  if nm and db.ignored and db.ignored[nm] then return end  -- on the ignore list
  seen[guid] = true
  local slot = nEntries + 1
  local e = entries[slot]
  if not e then
    local p = #entryPool
    if p > 0 then e = entryPool[p]; entryPool[p] = nil else e = { missing = {} } end
    entries[slot] = e
  end
  local n = Missing(unit, e.missing)
  local inRange = n > 0 and InRange(e.missing[1], unit)
  if n == 0 or (not inRange and not db.showOutOfRange) then return end  -- slot is reused next time
  nEntries = slot
  local _, class = UnitClass(unit)
  e.unit, e.guid, e.name, e.class, e.group = unit, guid, nm or UnitName(unit), class, isGroup
  e.isSelf = UnitIsUnit(unit, "player")
  e.outOfRange = not inRange
  e.groupCast = false
  e.role = RoleOf(unit)
end

-- Last-scan diagnostics for /br debug: how many nameplate units the client
-- handed us on the latest pass, and how many of them were players.
local scanPlatesSeen, scanPlayersSeen = 0, 0

local function CollectEntries()
  wipe(seen)
  wipe(cdCache)
  nEntries = 0
  scanPlatesSeen, scanPlayersSeen = 0, 0
  local list = InRaid() and RAID or PARTY
  for i = 1, #list do Consider(list[i], true) end
  Consider("player", true)
  Consider("target", false)
  Consider("mouseover", false)
  for i = 1, #PLATES do
    local u = PLATES[i]
    if UnitExists(u) then
      scanPlatesSeen = scanPlatesSeen + 1
      if UnitIsPlayer(u) then scanPlayersSeen = scanPlayersSeen + 1 end
    end
    Consider(u, false)
  end
  for i = #entries, nEntries + 1, -1 do  -- return the unused tail to the pool
    entryPool[#entryPool + 1] = entries[i]
    entries[i] = nil
  end
  if nEntries > 1 then table_sort(entries, EntryOrder) end
  return nEntries
end

---------------------------------------------------------------------------
-- Rank selection: highest rank you know that the target can receive.
-- Classic rule: a buff fails if its rank's required level is more than 10
-- above the target's level. If the client can't tell us spell levels, we
-- simply use the highest rank.
---------------------------------------------------------------------------
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

local function Bind(btn, unit, spell)
  local pick = PickRank(spell, unit)
  local method = db.castMethod
  if method == "target" then
    -- Same approach as BuffYou (MIT, by datdata): self-casts go straight to "player";
    -- anyone else is targeted by exact name, then the buff is cast by plain name
    -- (which uses your highest rank), then your previous target is restored.
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
    local ok, name = pcall(GetUnitName or UnitName, unit, true)
    if ok and type(name) == "string" and name ~= "" then
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

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
local frame, title, countText, emptyText, overflowText, combatText, nextBtn
local OpenConfig, RefreshConfig, MakeMacro  -- defined further down
local QueueRefresh  -- assigned to the event coalescer further down
local BuildMinimapButton  -- assigned in the minimap section further down
local footerText
local sessionCasts = 0
local pendingCast            -- { spell = name, time = t } set when a BuffRadar button is clicked
local listedA, listedB = {}, {}  -- double-buffered "who was listed" sets (no per-refresh tables)
local listedBefore = listedA     -- guid -> true for names on the board last refresh
local recentlyGone = {}      -- guid -> time they dropped off (stops in/out-of-range flicker dings)
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
local PlayDroplet = PlayAlert  -- older call sites use this name

local lastCounterSession, lastCounterTotal
local function UpdateCounter()
  if not footerText then return end
  local show = db.showCounter and true or false
  if (footerText:IsShown() and true or false) ~= show then footerText:SetShown(show) end
  local total = db.castsTotal or 0
  if sessionCasts ~= lastCounterSession or total ~= lastCounterTotal then
    lastCounterSession, lastCounterTotal = sessionCasts, total
    footerText:SetText(string_format("Casts: |cffffffff%d|r this session  ·  |cffffffff%d|r all-time",
      sessionCasts, total))
  end
end

local function NotePendingCast(entry)
  if entry and entry.missing and entry.missing[1] then
    pendingCast = { spell = entry.missing[1], time = GetTime() }
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
end

-- Where a named anchor point sits inside a frame, as fractions of its
-- width (from the left edge) and height (from the bottom edge).
local POINT_FRACTION = {
  TOPLEFT = { 0, 1 },     TOP = { 0.5, 1 },   TOPRIGHT = { 1, 1 },
  LEFT = { 0, 0.5 },      CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
  BOTTOMLEFT = { 0, 0 },  BOTTOM = { 0.5, 0 },   BOTTOMRIGHT = { 1, 0 },
}

local function RestorePosition()
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
  if UnitExists(e.unit) and UnitGUID(e.unit) == e.guid then
    GameTooltip:SetUnit(e.unit)
  else
    GameTooltip:AddLine(e.name)
  end
  GameTooltip:AddLine(" ")
  if e.outOfRange then
    GameTooltip:AddLine("Out of range — move closer to cast:", 1, 0.5, 0.3)
    GameTooltip:AddLine("|cff00ff00" .. e.missing[1] .. "|r")
  else
    GameTooltip:AddLine("Click to cast: |cff00ff00" .. e.missing[1] .. "|r")
  end
  if e.groupCast then
    GameTooltip:AddLine("Group version — one cast buffs the whole party.", 0.4, 0.8, 1)
  end
  GameTooltip:AddLine("Right-click to ignore this player.", 0.6, 0.6, 0.6)
  if #e.missing > 1 then
    local rest = {}
    for i = 2, #e.missing do rest[#rest + 1] = e.missing[i] end
    GameTooltip:AddLine("Still needs: " .. table.concat(rest, ", "), 0.8, 0.8, 0.8, true)
  end
  GameTooltip:Show()
end

local function CreateRow(i)
  local b = CreateFrame("Button", "BuffRadarRow" .. i, frame, "SecureActionButtonTemplate")
  b:SetSize(WIDTH - 12, ROW_H)
  b:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -HEADER_H - (i - 1) * ROW_H)
  if db.clickReg == "down" then
    b:RegisterForClicks("AnyDown")
  elseif db.clickReg == "up" then
    b:RegisterForClicks("AnyUp")
  else
    b:RegisterForClicks("AnyUp", "AnyDown")
  end
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

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
    if not e or not e.name or not db then return end
    db.ignored = db.ignored or {}
    if db.ignored[e.name] then
      db.ignored[e.name] = nil
      Print("No longer ignoring " .. e.name .. ".")
    else
      db.ignored[e.name] = true
      Print("Ignoring " .. e.name .. ". Right-click again or /br unignore to undo.")
    end
    if QueueRefresh then QueueRefresh() end
  end)
  b:SetScript("PostClick", function(self, button, down)
    if self:GetAttribute("type") then NotePendingCast(self.entry) end
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

local function ApplyAppearance()
  if not frame then return end
  local c = db.bgColor or DEFAULTS.bgColor
  if frame.SetBackdropColor then
    frame:SetBackdropColor(c[1], c[2], c[3], db.bgAlpha or 0.92)
    frame:SetBackdropBorderColor(0.35, 0.55, 0.8, db.showBorder and 1 or 0)
  end
  title:SetShown(db.showTitle and true or false)
  combatText:ClearAllPoints()
  if db.showTitle then
    combatText:SetPoint("LEFT", title, "RIGHT", 6, 0)
  else
    combatText:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -8)
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
  local lvl = UnitLevel(unit) or 0
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
  nextBtn:HookScript("PostClick", function(self, button, down)
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
  frame:SetSize(WIDTH, HEADER_H + 30)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
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
    GameTooltip:AddLine("BuffRadar settings")
    GameTooltip:Show()
  end)
  gear:SetScript("OnLeave", function() GameTooltip:Hide() end)

  countText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  countText:SetPoint("RIGHT", close, "LEFT", -2, 0)

  combatText = frame:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
  combatText:SetPoint("LEFT", title, "RIGHT", 6, 0)
  combatText:SetText("combat")
  combatText:Hide()

  emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  emptyText:SetPoint("TOPLEFT", 10, -HEADER_H - 3)
  emptyText:SetText("Everyone nearby is buffed.")

  overflowText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  overflowText:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -HEADER_H)

  footerText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footerText:SetPoint("LEFT", gear, "RIGHT", 5, 0)
  footerText:SetJustifyH("LEFT")

  for i = 1, MAX_ROWS do CreateRow(i) end

  local okNext, errNext = pcall(BuildNextButton)
  if not okNext then Print("|cffff4040keybind button unavailable:|r " .. tostring(errNext)) end

  frame:SetScale(db.scale or 1)
  RestorePosition()
  ApplyAppearance()
  UpdateCounter()
  BuildMinimapButton()
  built = true
end

---------------------------------------------------------------------------
-- Minimap button + addon compartment
---------------------------------------------------------------------------
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
    GameTooltip:AddLine("Left-click: show / hide the window", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click: settings", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Drag: move around the minimap", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
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

  if AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
    pcall(AddonCompartmentFrame.RegisterAddon, AddonCompartmentFrame, {
      text = "BuffRadar",
      icon = "Interface\\AddOns\\BuffRadar\\Media\\icon.png",
      notCheckable = true,
      func = function() OpenConfig() end,
    })
  end
end

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
    row.cGuid, row.cUnit, row.bGuid = nil, nil, nil
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
    row.name:SetTextColor(ClassColor(e.class))
    row.cGuid, row.cUnit = e.guid, e.unit
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
    row.name:SetTextColor(0.55, 0.55, 0.55)
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
  SetTextIfChanged(countText, "")
  SetShownIfChanged(overflowText, false)
  SetTextIfChanged(emptyText, text)
  SetShownIfChanged(emptyText, true)
  UpdateCounter()
  SetHeightIfChanged(frame, HEADER_H + 26 + FOOTER_H)
  SetShownIfChanged(frame, true)
end

local function Refresh()
  if not built or InCombatLockdown() then return end

  if not hasAnyBuff then
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
    ClearNext()
    wipe(listedBefore)
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
    ClearNext()
    wipe(listedBefore)
    for i = 1, MAX_ROWS do ClearRow(rows[i]) end
    if db.hidden or groupHidden or db.autoHide then
      SetShownIfChanged(frame, false)
    else
      ShowStatus(L["Paused in a battleground."])
    end
    return
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
    wipe(listedBefore)
    return
  end

  -- Droplet sound when someone new appears on the board
  local now, newName = GetTime(), false
  local listedNow = (listedBefore == listedA) and listedB or listedA
  wipe(listedNow)
  for i = 1, n do
    local guid = entries[i].guid
    listedNow[guid] = true
    if entries[i].outOfRange then
      -- greyed rows don't ding: they're not castable yet
    elseif not listedBefore[guid] then
      local gone = recentlyGone[guid]
      if not gone or now - gone > 10 then newName = true end
    end
  end
  for guid in pairs(listedBefore) do
    if not listedNow[guid] then recentlyGone[guid] = now end
  end
  for guid, t in pairs(recentlyGone) do
    if now - t > 60 then recentlyGone[guid] = nil end
  end
  listedBefore = listedNow
  if newName and db.playSound and now - lastSoundAt > 1 then
    lastSoundAt = now
    PlayDroplet()
  end

  local shown = math_min(n, MAX_ROWS)
  for i = 1, MAX_ROWS do
    if i <= shown then RenderRow(rows[i], entries[i]) else ClearRow(rows[i]) end
  end

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
      overflowText:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -HEADER_H - MAX_ROWS * ROW_H - 2)
      overflowText.cAnchored = true
    end
    if overflowText.cCount ~= n then
      overflowText.cCount = n
      overflowText:SetText(string_format("+%d more", n - MAX_ROWS))
    end
    SetShownIfChanged(overflowText, true)
  else
    SetShownIfChanged(overflowText, false)
  end

  local h = HEADER_H + (shown > 0 and shown * ROW_H or 18) + 8
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
  StartTicker = function()
    if not ticker then ticker = C_Timer.NewTicker(UPDATE_INTERVAL, SafeRefresh) end
  end
else
  -- Fallback for clients without C_Timer: throttled accumulator, never per-frame work.
  local elapsed = 0
  StartTicker = function()
    driver:SetScript("OnUpdate", function(_, dt)
      elapsed = elapsed + dt
      if elapsed >= UPDATE_INTERVAL then
        elapsed = 0
        SafeRefresh()
      end
    end)
  end
  Soon = function()
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
  for _, b in pairs(BLESSINGS) do
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
}) do
  pcall(driver.RegisterEvent, driver, ev)
end

driver:SetScript("OnEvent", function(_, event, arg1, ...)
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
      local parts = { tostring(arg1) }
      for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
      Print("|cffaaaaaa" .. event .. ": " .. table.concat(parts, ", ") .. "|r")
    end
    if event ~= "UNIT_SPELLCAST_SUCCEEDED" or arg1 ~= "player" then return end
    if arg1 == "player" and pendingCast and db then
      local spellID = select(2, ...)
      local ok, name = pcall(SpellName, spellID, nil)
      if ok and name == pendingCast.spell and GetTime() - pendingCast.time < 3 then
        pendingCast = nil
        sessionCasts = sessionCasts + 1
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
  elseif event == "PLAYER_LOGIN" then
    driver:UnregisterEvent("PLAYER_LOGIN")  -- one-off
    if not db then
      BuffRadarDB = SanitizeDB(BuffRadarDB)
      db = BuffRadarDB
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
    if nextBtn then nextBtn.bGuid, nextBtn.isClear = nil, false end  -- driver clears it
    -- Fallback when the secure combat driver isn't available: this event still runs
    -- just before combat lockdown starts, so the key can be disarmed here.
    if not nextCombatDriver then ClearNext() end
  elseif event == "PLAYER_REGEN_ENABLED" then
    if combatText then combatText:Hide() end
    BuildUI()
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
-- Keybind + macro helpers
---------------------------------------------------------------------------
local function MacroBody()
  if GetCVarBool and GetCVarBool("ActionButtonUseKeyDown") then
    return "/click BuffRadarNextButton LeftButton 1"
  end
  return "/click BuffRadarNextButton"
end

local function KeybindText(binding)
  local k1, k2 = nil, nil
  if GetBindingKey then k1, k2 = GetBindingKey(binding or NEXT_BINDING) end
  if not k1 then return "|cff888888not bound|r" end
  local function nice(k) return (GetBindingText and GetBindingText(k)) or k end
  return "|cffffd100" .. nice(k1) .. (k2 and (", " .. nice(k2)) or "") .. "|r"
end

local function OpenKeybinds()
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

---------------------------------------------------------------------------
-- Config window (tabbed: Window / Alerts / Buffs / Behavior / Ignore & Stats)
---------------------------------------------------------------------------
local cfg
local cfgTab = "look"

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
  cb:SetScript("OnClick", function(self) setter(self:GetChecked() and true or false) end)
  cb.Update = function(self) self:SetChecked(getter() and true or false) end
  return cb
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

local function SelectTab(key)
  cfgTab = key
  for k, panel in pairs(cfg.panels) do panel:SetShown(k == key) end
  for k, btn in pairs(cfg.tabBtns) do
    if k == key then btn:LockHighlight() else btn:UnlockHighlight() end
  end
end

local function BuildConfig()
  cfg = CreateFrame("Frame", "BuffRadarConfig", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  cfg:SetSize(600, 470)
  cfg:SetPoint("CENTER")
  cfg:SetFrameStrata("DIALOG")
  cfg:SetClampedToScreen(true)
  cfg:SetMovable(true)
  cfg:EnableMouse(true)
  cfg:RegisterForDrag("LeftButton")
  cfg:SetScript("OnDragStart", cfg.StartMoving)
  cfg:SetScript("OnDragStop", cfg.StopMovingOrSizing)
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
  if UISpecialFrames then table.insert(UISpecialFrames, "BuffRadarConfig") end -- Esc closes it

  local head = cfg:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  head:SetPoint("TOP", 0, -12)
  head:SetText("|cff33ccffBuff|rRadar Settings")

  local close = CreateFrame("Button", nil, cfg, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)

  -- Tabs
  cfg.panels, cfg.tabBtns = {}, {}
  local tabDefs = {
    { "look", "Window" }, { "alerts", "Alerts" }, { "buffs", "Buffs" },
    { "behavior", "Behavior" }, { "data", "Ignore & Stats" },
  }
  for i, td in ipairs(tabDefs) do
    local key, label = td[1], td[2]
    local btn = MakeButton(cfg, label, 106, function() SelectTab(key); RefreshConfig() end)
    btn:SetPoint("TOPLEFT", 16 + (i - 1) * 112, -40)
    cfg.tabBtns[key] = btn
    local panel = CreateFrame("Frame", nil, cfg)
    panel:SetPoint("TOPLEFT", 8, -70)
    panel:SetPoint("BOTTOMRIGHT", -8, 8)
    panel:Hide()
    cfg.panels[key] = panel
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

  cfg.titleCheck = MakeCheck(look, "Show BuffRadar title",
    function() return db.showTitle end,
    function(v) db.showTitle = v; ApplyAppearance() end)
  cfg.titleCheck:SetPoint("TOPLEFT", 10, -116)

  cfg.borderCheck = MakeCheck(look, "Show border",
    function() return db.showBorder end,
    function(v) db.showBorder = v; ApplyAppearance() end)
  cfg.borderCheck:SetPoint("TOPLEFT", 10, -142)

  local scaleLabel = look:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  scaleLabel:SetPoint("TOPLEFT", 14, -178)
  scaleLabel:SetText("Window scale")
  local scaleValue = look:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  scaleValue:SetPoint("LEFT", scaleLabel, "RIGHT", 8, 0)
  cfg.scaleValue = scaleValue
  cfg.scaleSlider = MakeSlider(look, 16, -198, 250, 50, 200, 5, function(v)
    v = math.floor(v + 0.5)
    db.scale = v / 100
    scaleValue:SetText(v .. "%")
    if frame then frame:SetScale(db.scale) end
  end)

  local resetLook = MakeButton(look, "Reset look", 110, function()
    db.bgColor = { DEFAULTS.bgColor[1], DEFAULTS.bgColor[2], DEFAULTS.bgColor[3] }
    db.bgAlpha = DEFAULTS.bgAlpha
    db.showTitle, db.showBorder, db.scale = true, true, 1
    if frame then frame:SetScale(1) end
    ApplyAppearance()
    RefreshConfig()
  end)
  resetLook:SetPoint("TOPLEFT", 14, -232)

  cfg.minimapCheck = MakeCheck(look, "Minimap button (drag it around the minimap)",
    function() return db.showMinimap end,
    function(v) db.showMinimap = v; if RefreshMinimapButton then RefreshMinimapButton() end end)
  cfg.minimapCheck:SetPoint("TOPLEFT", 10, -268)

  ------------------------------------------------------------------
  -- Tab: Alerts
  ------------------------------------------------------------------
  local alerts = cfg.panels.alerts
  section(alerts, "New name alert", 10, -6)

  cfg.soundCheck = MakeCheck(alerts, "Play a sound when a name appears",
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

  cfg.muteInstCheck = MakeCheck(alerts, "No alert sound in dungeons, raids or battlegrounds",
    function() return db.muteInInstance end,
    function(v) db.muteInInstance = v end)
  cfg.muteInstCheck:SetPoint("TOPLEFT", 10, -92)

  section(alerts, "Cast counter", 10, -136)
  cfg.counterCheck = MakeCheck(alerts, "Show cast counter in the window",
    function() return db.showCounter end,
    function(v) db.showCounter = v; UpdateCounter(); Refresh() end)
  cfg.counterCheck:SetPoint("TOPLEFT", 10, -160)

  local resetCount = MakeButton(alerts, "Reset counts", 110, function()
    sessionCasts, db.castsTotal = 0, 0
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

  cfg.buffChecks = {}
  local cols = { 10, 302 }
  for i = 1, 16 do
    local cb = MakeCheck(buffs, "", function() return false end, function() end)
    local col = (i <= 8) and 1 or 2
    local row = (i - 1) % 8
    cb:SetPoint("TOPLEFT", cols[col], -34 - row * 26)
    cb:Hide()
    cfg.buffChecks[i] = cb
  end
  cfg.noBuffs = buffs:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  cfg.noBuffs:SetPoint("TOPLEFT", 14, -36)
  cfg.noBuffs:SetText("You don't know any supported buffs yet.")

  cfg.selfCheck = MakeCheck(buffs, "Buff myself first (all buffs that suit me)",
    function() return db.includeSelf end,
    function(v) db.includeSelf = v; Refresh() end)
  cfg.selfCheck:SetPoint("TOPLEFT", 10, -252)

  local rebuffHint = buffs:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  rebuffHint:SetPoint("TOPLEFT", 14, -284)
  rebuffHint:SetWidth(540)
  rebuffHint:SetJustifyH("LEFT")
  rebuffHint:SetText("Rebuff timing: /br rebuff <seconds> sets it for all buffs; /br rebuff KEY <seconds> (e.g. /br rebuff THORNS 60) sets one buff. Keys are listed by /br buffs.")

  ------------------------------------------------------------------
  -- Tab: Behavior
  ------------------------------------------------------------------
  local beh = cfg.panels.behavior
  section(beh, "When to show & scan", 10, -6)

  cfg.groupCheck = MakeCheck(beh, "Only show in a party or raid",
    function() return db.groupOnly end,
    function(v) db.groupOnly = v; Refresh() end)
  cfg.groupCheck:SetPoint("TOPLEFT", 10, -30)

  cfg.cityCheck = MakeCheck(beh, "Pause scanning in major cities",
    function() return db.pauseInCities end,
    function(v) db.pauseInCities = v; Refresh() end)
  cfg.cityCheck:SetPoint("TOPLEFT", 10, -56)

  cfg.bgCheck = MakeCheck(beh, "Pause in battlegrounds and arenas",
    function() return db.pauseInBG end,
    function(v) db.pauseInBG = v; Refresh() end)
  cfg.bgCheck:SetPoint("TOPLEFT", 10, -82)

  section(beh, "Casting & order", 302, -6)

  cfg.groupCastCheck = MakeCheck(beh, "Offer group buffs in a party or raid",
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

  cfg.oorCheck = MakeCheck(beh, "Show out-of-range players (greyed)",
    function() return db.showOutOfRange end,
    function(v) db.showOutOfRange = v; Refresh() end)
  cfg.oorCheck:SetPoint("TOPLEFT", 296, -112)

  cfg.sortBtn = MakeButton(beh, "Sort: name", 130, function()
    db.sortMode = (db.sortMode == "role") and "name" or "role"
    RefreshConfig()
    Refresh()
  end)
  cfg.sortBtn:SetPoint("TOPLEFT", 320, -140)
  local sortHint = beh:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  sortHint:SetPoint("LEFT", cfg.sortBtn, "RIGHT", 8, 0)
  sortHint:SetText("role = tanks & leaders first")

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
  local clearIgnores = MakeButton(data, "Clear ignore list", 140, function()
    wipe(db.ignored)
    Print("Ignore list cleared.")
    RefreshConfig()
    Refresh()
  end)
  clearIgnores:SetPoint("TOPLEFT", 14, -84)

  section(data, "Casts by spell (all-time)", 10, -124)
  cfg.statsText = data:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cfg.statsText:SetPoint("TOPLEFT", 14, -150)
  cfg.statsText:SetWidth(540)
  cfg.statsText:SetJustifyH("LEFT")
  local resetStats = MakeButton(data, "Reset stats", 110, function()
    wipe(db.stats)
    Print("Cast statistics reset.")
    RefreshConfig()
  end)
  resetStats:SetPoint("TOPLEFT", 14, -236)

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
  cfg.scaleSlider:SetValue(math.floor((db.scale or 1) * 100 + 0.5))
  cfg.scaleValue:SetText(math.floor((db.scale or 1) * 100 + 0.5) .. "%")
  cfg.titleCheck:Update()
  cfg.borderCheck:Update()
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

  -- Ignore list summary
  local names = {}
  for name in pairs(db.ignored or {}) do names[#names + 1] = name end
  table.sort(names)
  cfg.ignoreText:SetText(#names == 0 and "Nobody is ignored. Right-click a name in the window to ignore that player."
    or ("Ignored (" .. #names .. "): " .. table.concat(names, ", ")))

  -- Stats summary: top 8 spells by count
  local rows = {}
  for name, n in pairs(db.stats or {}) do rows[#rows + 1] = { name = name, n = n } end
  table.sort(rows, function(a, b) return a.n > b.n end)
  if #rows == 0 then
    cfg.statsText:SetText("No casts recorded yet. Statistics count casts made through BuffRadar.")
  else
    local parts = {}
    for i = 1, math.min(8, #rows) do
      parts[#parts + 1] = string.format("%s: %d", rows[i].name, rows[i].n)
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
      cb.label:SetText(it.label .. "  |cff888888" .. (it.who or "") .. "|r")
      cb:SetChecked(IsOn(it.key, it.default) and true or false)
      cb:SetScript("OnClick", function(self)
        db.enabled[it.key] = self:GetChecked() and true or false
        Refresh()
      end)
      cb:Show()
    else
      cb:Hide()
    end
  end
  cfg.noBuffs:SetShown(#items == 0)
  cfg.selfCheck:Update()
end

OpenConfig = function()
  if not cfg then BuildConfig() end
  if cfg:IsShown() then cfg:Hide() else cfg:Show() end
end


---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
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
    if db.playSound then PlayDroplet() end
  elseif cmd == "count" or cmd == "counts" then
    Print(string.format("Casts through BuffRadar: %d this session, %d all-time.", sessionCasts, db.castsTotal or 0))
  elseif cmd == "resetcount" then
    sessionCasts, db.castsTotal = 0, 0
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
    if m == "target" or m == "id" or m == "macro" or m == "rank" then
      if InCombatLockdown() then Print("Can't change mode during combat."); return end
      db.castMethod = m
      Print("Cast mode: " .. m)
    else
      Print("Usage: /br mode target|id|macro|rank   (currently " .. tostring(db.castMethod) .. ")")
      Print("  target = target the player, cast, restore your target (default)")
      Print("  id = cast the chosen rank by spell ID")
      Print("  macro = /cast by plain name (game picks highest rank)")
      Print("  rank = /cast Name(Rank N)")
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
    Print(string.format("client %s build %s (interface %s), class %s, spellbook entries %d, window built %s",
      tostring(ver), tostring(build), tostring(iface), tostring(myClass), bookCount, tostring(built)))
    local names = {}
    for _, b in ipairs(myBuffs) do names[#names + 1] = b.name end
    for class, b in pairs(myBlessing) do names[#names + 1] = class .. "=" .. b.name end
    Print("buffs found: " .. (#names > 0 and table.concat(names, ", ") or "none"))
    for _, b in ipairs(myBuffs) do
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
      scanPlatesSeen, scanPlayersSeen))
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
    Print("Window lock " .. OnOff(db.locked))
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
      local found = (key == "BLESSINGS")
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
    if m == "name" or m == "role" then db.sortMode = m
    else db.sortMode = (db.sortMode == "role") and "name" or "role" end
    Print("List order: " .. db.sortMode .. (db.sortMode == "role" and " (tanks & leaders first)" or ""))
    Refresh()
  elseif cmd == "ignore" then
    if rest == "" then Print("Usage: /br ignore <name>  (or right-click a row)"); return end
    db.ignored[rest] = true
    Print("Ignoring " .. rest .. ".")
    Refresh()
  elseif cmd == "unignore" then
    if rest == "" then Print("Usage: /br unignore <name>"); return end
    db.ignored[rest] = nil
    Print("No longer ignoring " .. rest .. ".")
    Refresh()
  elseif cmd == "ignorelist" or cmd == "ignores" then
    local names = {}
    for name in pairs(db.ignored or {}) do names[#names + 1] = name end
    table.sort(names)
    Print(#names == 0 and "Ignore list is empty." or ("Ignored: " .. table.concat(names, ", ")))
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
      if frame then frame:SetScale(n) end
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
    local found = (key == "BLESSINGS")
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
    Print("  /br mode target|id|macro|rank  - how clicks cast (default target)")
    Print("  /br clickreg both|down|up  - which half of the click casts")
    Print("  /br plates  - turn on friendly nameplates (needed for non-group players)")
    Print("  /br groupcast [on|off|<n>]  - offer group buffs when n+ players need one")
    Print("  /br sort name|role  - list order (role = tanks & leaders first)")
    Print("  /br ignore <name> | unignore <name> | ignorelist")
    Print("  /br rebuff KEY <sec>  - per-buff rebuff timing (see /br buffs for keys)")
    Print("  /br alertsound droplet|system|none  - new-name alert sound")
    Print("  /br bg  - pause in battlegrounds   /br minimap  - toggle minimap button")
    Print("  /br stats  - casts by spell (all-time)")
  end
  Refresh()
end

SlashCmdList.BUFFRADAR = function(msg)
  local ok, err = pcall(HandleSlash, msg)
  if not ok then Print("|cffff4040error:|r " .. tostring(err)) end
end
