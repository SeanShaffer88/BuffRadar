-- BuffRadar - click-to-buff list for World of Warcraft (Retail and Forever)
-- One source for both editions: the buff set and class tables are picked at
-- load from the client's interface version by Data.lua.
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

local ADDON, namespace = ...
local X = namespace.X

-- Cached globals: hot paths (scans and aura reads) use these locals
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
local NEXT_BINDING = "CLICK BuffRadarNextButton:LeftButton"
local MACRO_NAME = "BuffRadar"

local UPDATE_INTERVAL = 0.4
local SOUND_FILE = "Interface\\AddOns\\BuffRadar\\Media\\droplet.ogg"

-- Runtime state used across the feature modules, not SavedVariables.
do
  local shared = {
    session = {}, dead = {}, rezAt = {}, tally = {}, tallyUnits = 0,
    sessionCasts = 0, missPrev = {}, missNow = {}, expiredAt = {},
    handled = {}, asked = {}, applyFilter = true, failedTargets = {},
    prevHolder = {}, queueAt = 0, consTally = {}, assign = {}, blessPlan = {},
    peers = {}, cover = {}, myCover = false, expiryTally = {}, upTotal = 0, upFull = 0,
    search = "", offNow = {}, drinkSet = {},
    hid = 0,  -- last unreadable aura data
  }
  for key, value in pairs(shared) do X[key] = value end
end

local CLASSIC_FEATURES = X.classic
local ALL, BUFF_DEFS = X.ALL, X.BUFF_DEFS
local BLESSINGS = X.BLESSINGS
-- (X.MANA / X.MELEE / X.TANKS / X.AURA_DEFS / X.BLESSING_PRIORITY are read
-- through X at their few use sites, to keep main-chunk locals freed.)
local db
X.OnDBLoaded(function(value) db = value end)

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffBuffRadar|r: " .. tostring(msg))
end

---------------------------------------------------------------------------
-- Localization scaffolding: enUS strings are the keys. A translation file
-- can set the addon's private Locales["deDE"] before this file loads.
---------------------------------------------------------------------------
-- Every string the main window, its row tooltips and the minimap / addon-menu
-- tooltips show is listed here (the list doubles as the translator's checklist).
-- Strings with %d / %s are string.format patterns: keep the placeholders.
-- Any key a translation leaves out falls back to English.
local L = X.L
_G["BINDING_NAME_CLICK BuffRadarNextButton:LeftButton"] = L["Cast next buff"]
_G["BINDING_NAME_CLICK BuffRadarGroupButton:LeftButton"] = L["Cast next group buff"]
BINDING_NAME_BUFFRADAR_TOGGLE = L["Show / hide window"]
BINDING_NAME_BUFFRADAR_MUTE = L["Mute / unmute sound"]

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
  local inRaid = X.ReadUnitBool(IsInRaid)
  if inRaid ~= nil then return inRaid end
  return (X.ReadUnitNumber(GetNumRaidMembers) or 0) > 0
end

local function InGroup()
  if X.ReadUnitBool(IsInGroup) == true or InRaid() then return true end
  return (X.ReadUnitNumber(GetNumGroupMembers) or 0) > 0
    or (X.ReadUnitNumber(GetNumPartyMembers) or 0) > 0
end

-- Non-group players are only visible to addons through friendly nameplates,
-- so this CVar decides whether strangers can be listed at all. Returns
-- true/false when the client answers, nil when it can't say.
function X.ReadBooleanCVar(name)
  local reader = (C_CVar and C_CVar.GetCVar) or GetCVar
  if not reader then return nil end
  local ok, value = pcall(reader, name)
  if not ok or not X.Readable(value) then return nil end
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
      if ok and X.Readable(value) and value == true then return true, name end
    end
  end
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

  local function InRange(spell, unit, diagnostic)
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
    if not diagnostic then X.rangeSilent = true end
    if db.assumeRange then return true, true, true end
    return false, nil, true
  end

  function X.GroupSpellInRange(spell, unit, isSelf)
    if isSelf then return true end
    local inRange, _, unknown = InRange(spell, unit, true)
    return inRange and not unknown
  end

  function X.FilterInRange(unit, source, out, isSelf, diagnostic)
    wipe(out)
    if isSelf == nil then isSelf = X.IsSelf(unit) end
    if isSelf == nil then return 0 end
    local n, approximate, unknown, rankLimited = 0, false, false, false
    local level = CLASSIC_FEATURES and X.ReadUnitNumber(UnitLevel, unit)
    for i = 1, #source do
      local inRange, estimated, unreadable
      if X.RankTooLow(source[i], level, db.castMethod) then
        rankLimited = true
      elseif isSelf then
        inRange = true
      else
        inRange, estimated, unreadable = InRange(source[i], unit, diagnostic)
      end
      if unreadable then unknown = true end
      if inRange then
        n = n + 1
        out[n] = source[i]
        if n == 1 then approximate = estimated or false end
      end
    end
    return n, approximate, unknown, rankLimited
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

-- Guarded unit identity reads for the scan path. A client that raises,
-- refuses or returns a protected value makes the unit absent for this scan
-- instead of aborting the whole refresh.
function X.UnitPresent(unit)
  return X.ReadUnitBool(UnitExists, unit) == true
end

function X.UnitGUIDOf(unit)
  local ok, guid = pcall(UnitGUID, unit)
  if not ok then return nil end
  guid = SafeString(guid)
  if guid and guid ~= "" then return guid end
end

function X.UnitClassToken(unit)
  local ok, _, class = pcall(UnitClass, unit)
  if ok then return SafeString(class) end
end

function X.UnitNameOf(unit)
  local ok, name = pcall(UnitName, unit)
  if ok then return SafeString(name) end
end

function X.PlayerSuspended()
  return X.playerDead == true or X.ReadUnitBool(_G.UnitIsDeadOrGhost, "player") == true
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
  if not UnitGroupRolesAssigned then return nil, true end
  local ok, r = pcall(UnitGroupRolesAssigned, unit)
  if not ok or (type(r) ~= "nil" and not Readable(r)) then return nil, false end
  if r == "TANK" or r == "HEALER" or r == "DAMAGER" then return r, true end
  return nil, true
end

local function GetField(t, k) return t[k] end  -- shared pcall target (no per-call closures)

do
  -- A restricted aura lookup can return zero values. An explicit nil is
  -- the normal result when the requested aura is absent.
  local function FirstResult(...)
    return select("#", ...), ...
  end
  local function Call(lookup, ...)
    return FirstResult(lookup(...))
  end
  function X.QueryAura(lookup, ...)
    local ok, count, aura = pcall(Call, lookup, ...)
    if ok and count > 0 then
      if type(aura) == "nil" then return nil, true end
      if Readable(aura) and type(aura) == "table" then return aura, true end
    end
    return nil, false
  end
  X.QueryNamedAura = X.QueryAura
end

do
  local function AuraExpiration(a)
    local ok, expiry = pcall(GetField, a, "expirationTime")
    if ok and Readable(expiry) and type(expiry) == "number" and expiry >= 0 and expiry < math_huge then
      return expiry
    end
  end

  local function SourceOwner(source)
    if not Readable(source) or type(source) ~= "string" or source == "" then return "unknown" end
    if source == "player" or source == "pet" then return "mine" end
    -- Use readable identities rather than assuming UnitIsUnit's false
    -- means a different caster on a restricted unit.
    local caster, player = X.UnitGUIDOf(source), X.UnitGUIDOf("player")
    if caster and player then return caster == player and "mine" or "other" end
    return "unknown"
  end

  local function AuraOwner(aura)
    local ok, mine = pcall(GetField, aura, "isFromPlayerOrPlayerPet")
    if ok and Readable(mine) and type(mine) == "boolean" then return mine and "mine" or "other" end
    local sourceOK, source = pcall(GetField, aura, "sourceUnit")
    return sourceOK and SourceOwner(source) or "unknown"
  end

  local function BuffTuple(...) return select("#", ...), ... end
  local function ReadLegacyBuff(unit, i) return BuffTuple(UnitBuff(unit, i)) end

  function X.ReadBuff(unit, i, withOwner, withID)
    -- done, name, expirationTime, complete (when done), optional owner/ID
    local name, expiry, owner, id
    local lookup = C_UnitAuras and (C_UnitAuras.GetBuffDataByIndex or C_UnitAuras.GetAuraDataByIndex)
    if lookup then
      local aura, definitive = X.QueryAura(lookup, unit, i, "HELPFUL")
      if not definitive then return true, nil, nil, false end
      if not aura then return true, nil, nil, true end
      local nameOK, value = pcall(GetField, aura, "name")
      if nameOK then name = value end
      expiry = AuraExpiration(aura)
      if withOwner then owner = AuraOwner(aura) end
      if withID then
        local read, spell = pcall(GetField, aura, "spellId")
        if read then id = spell end
      end
    elseif UnitBuff then
      -- UnitBuff's rank-less return list: expirationTime, then source.
      local ok, count, value, _, _, _, _, expiration, source, _, _, spell = pcall(ReadLegacyBuff, unit, i)
      if not ok or count == 0 then return true, nil, nil, false end
      if type(value) == "nil" then return true, nil, nil, true end
      name, expiry, id = value, expiration, spell
      if withOwner then owner = SourceOwner(source) end
    else
      return true, nil, nil, false
    end
    if not Readable(name) or type(name) ~= "string" or name == "" then
      X.hid = GetTime()
      name = nil
    end
    if withID and not (Readable(id) and X.Settings.PositiveID(id)) then id = nil end
    if not Readable(expiry) or type(expiry) ~= "number" or not (expiry >= 0 and expiry < math_huge) then expiry = nil end
    return false, name, expiry, nil, owner, id
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

  -- Only used when the nearby complement option is on. The index fallback
  -- shares one walk across all the blessing families for this recipient.
  local owners, ownersComplete = {}, false
  local function MergeOwner(a, b)
    if a == "mine" or b == "mine" then return "mine" end
    if a == "unknown" or b == "unknown" then return "unknown" end
    if a == "other" or b == "other" then return "other" end
    return "absent"
  end

  local function IndexedOwner(unit, name)
    if X.blessingScanUnit ~= unit then
      wipe(owners)
      X.blessingScanUnit, ownersComplete = unit, false
      local now, readableNames = GetTime(), true
      for i = 1, 40 do
        local done, auraName, expiry, ended, owner = X.ReadBuff(unit, i, true)
        if done then ownersComplete = ended and readableNames; break end
        if not auraName then
          readableNames = false
        elseif not expiry or expiry == 0 or expiry > now then
          owners[auraName] = MergeOwner(owners[auraName], owner)
        end
      end
    end
    if owners[name] == "mine" then return "mine" end
    if not ownersComplete then return "unknown" end
    return owners[name] or "absent"
  end

  local function NamedOwner(unit, name)
    local lookup = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
    if lookup then
      local aura, definitive = X.QueryNamedAura(lookup, unit, name, "HELPFUL")
      if definitive then
        if not aura then return "absent" end
        local expiry = AuraExpiration(aura)
        if expiry and expiry ~= 0 and expiry <= GetTime() then return "absent" end
        local owner = AuraOwner(aura)
        if owner ~= "unknown" then return owner end
        local indexed = IndexedOwner(unit, name)
        return indexed ~= "absent" and indexed or "unknown"
      end
    end
    return IndexedOwner(unit, name)
  end

  function X.BlessingOwner(unit, names)
    return MergeOwner(NamedOwner(unit, names[1]), NamedOwner(unit, names[2]))
  end
end

---------------------------------------------------------------------------
-- Fast aura (1.14.0, Brief 2): is this incremental UNIT_AURA payload about
-- a buff BuffRadar watches? Answers from the payload itself: addedAuras
-- carry full aura data; removed/updated instance ids are resolved through
-- a per-unit cache of watched ids seen in addedAuras (a removed aura can no longer
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
    return Readable(id) and type(id) == "number" and id > 0 and id < math_huge and id == math_floor(id)
  end
  local function remember(id, nm)
    if nm and watch[nm] then
      if not byUnit then byUnit = {}; cache[unit] = byUnit end
      byUnit[id] = nm
    elseif byUnit then
      byUnit[id] = nil
    end
  end
  local relevant = false
  if added then
    for _, a in ipairs(added) do
      if not Readable(a) or type(a) ~= "table" then cache[unit] = nil; return true end
      local name, id = a.name, a.auraInstanceID
      if not Readable(name) or type(name) ~= "string" or name == "" or not validID(id) then
        cache[unit] = nil
        return true
      end
      if watch[name] or (byUnit and byUnit[id]) then relevant = true end
      remember(id, name)
    end
  end
  if updated then
    for _, id in ipairs(updated) do
      if not validID(id) then cache[unit] = nil; return true end
      local nm = byUnit and byUnit[id]
      if not nm and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
        local ok, d = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, id)
        if ok and Readable(d) and type(d) == "table" then
          local name = GetField(d, "name")
          if Readable(name) and type(name) == "string" and name ~= "" then
            nm = name
            remember(id, nm)
          end
        end
      end
      if not nm or watch[nm] then relevant = true end
    end
  end
  if removed then
    for _, id in ipairs(removed) do
      if not validID(id) then cache[unit] = nil; return true end
      local nm = byUnit and byUnit[id]
      if byUnit then byUnit[id] = nil end
      if not nm or watch[nm] then relevant = true end
    end
  end
  if byUnit and not next(byUnit) then cache[unit] = nil end
  return relevant
end

do
  local function ValidAuraField(value, expectedType)
    return type(value) == "nil" or (Readable(value) and type(value) == expectedType)
  end

  local function InspectAuraEvent(unit, info)
    if not Readable(info) or type(info) ~= "table" then
      if X.auraIds then X.auraIds[unit] = nil end
      return true
    end
    local full, added = info.isFullUpdate, info.addedAuras
    local removed, updated = info.removedAuraInstanceIDs, info.updatedAuraInstanceIDs
    if not ValidAuraField(full, "boolean") or not ValidAuraField(added, "table")
      or not ValidAuraField(removed, "table") or not ValidAuraField(updated, "table") then
      if X.auraIds then X.auraIds[unit] = nil end
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
    local optional = db and not db.liteMode and ((unit == "player" and db.worldWatch)
      or ((db.consumables or db.drinkWatch) and (unit == "player" or unit:match("^party%d+$") or unit:match("^raid%d+$"))))
    if db and db.fastAura and not full and not optional then
      if not X.AuraRelevant(unit, added, updated, removed) then
        probe.skipped = (probe.skipped or 0) + 1
        return false
      end
    elseif X.auraIds then
      X.auraIds[unit] = nil
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

local scanHorizon  -- coverage/forecast lookahead for the current list scan only
local function HasAny(unit, names, minLeft, measure)
  minLeft = minLeft or db.rebuff or 0
  local ceiling = measure and math_max(minLeft, measure) or minLeft
  local longest, unknown, untimed = 0, false, false
  for i = 1, #names do
    local rem, presence, uncertainTimer = X.Remaining(unit, names[i])
    if rem and rem > ceiling then return true end
    if rem and rem > longest then longest = rem end
    if presence == "present" and rem == nil then
      if minLeft == 0 and not measure then return true end
      untimed = true
    end
    if presence == "unknown" or (presence == "present" and (rem == nil or uncertainTimer)) then
      unknown = true
    end
  end
  -- When measuring, an unreadable or later equivalent can outlast the
  -- shorter aura. Only forecast loss of coverage when the whole family ends.
  local has = longest > minLeft or (minLeft == 0 and untimed)
  if unknown then return has and true or nil end
  return has, longest
end

do
  local function ObserveFamily(unit, names, cutoff)
    local longest, partial, untimed = 0, false, false
    for _, name in ipairs(names) do
      local left, presence, uncertain = X.Remaining(unit, name)
      if left and left > cutoff then return "present", nil, nil, true end
      if left and left > longest then longest = left end
      if presence == "present" and not left then untimed = true end
      if presence == "unknown" or (presence == "present" and (not left or uncertain)) then partial = true end
    end
    if longest > 0 or untimed then return "present", longest, partial, untimed end
    return partial and "unknown" or "absent", longest, partial
  end

  function X.FortitudeCoverage(unit, names, threshold, measure)
    local state, longest, uncertain, untimed = ObserveFamily(unit, names, math_max(threshold, measure or 0))
    if state == "present" and not longest then return true end
    if state == "unknown" then return nil end
    local covered = state == "present" and (longest > threshold or (threshold == 0 and untimed))
    if uncertain then return covered and true or nil end
    return covered, longest
  end
end

---------------------------------------------------------------------------
-- What can I cast?
---------------------------------------------------------------------------
local known, myBuffs, myBlessing, blessKnown, blessKeys = {}, {}, {}, {}, {}
local ranks = {}   -- ranks[name] = { {rank=n, sub="Rank n", id=spellID}, ... } ascending
local hasAnyBuff = false
local bookCount = 0
local sessionShow = false   -- user explicitly opened the window this session
local lastError
local scanFaults = 0
function X.ScanFaultCount() return scanFaults end

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
  X.nameKeyStamp = nil -- custom buffs can change without changing the spellbook size
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
        myBlessing[class] = { name = name, priorityKey = "BLESS_" .. k,
                              names = { name, SpellName(b.greater[1], b.greater[2]) } }
        break
      end
    end
  end

  -- Every blessing you know, by key: the blessing planner (1.6.0) picks
  -- from this instead of the per-class priority list when a plan is set.
  wipe(blessKnown)
  wipe(blessKeys)
  for k, b in pairs(BLESSINGS) do
    local name = SpellName(b.id, b.name)
    if KnowsSpell(b.id, name) then
      blessKeys[name] = "BLESS_" .. k
      blessKnown[k] = { name = name, priorityKey = blessKeys[name],
                        names = { name, SpellName(b.greater[1], b.greater[2]) } }
    end
  end

  do  -- watched aura names for the fast-aura relevance check (1.14.0)
    local watch = {}
    for _, b in ipairs(myBuffs) do
      if b.name then watch[b.name] = true end
      for _, n in ipairs(b.names or {}) do watch[n] = true end
    end
    for _, b in pairs(blessKnown) do
      if type(b) == "table" then
        if b.name then watch[b.name] = true end
        for _, n in ipairs(b.names or {}) do watch[n] = true end
      end
    end
    X.watchNames, X.auraIds = watch, nil
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

function X.SetBlessingComplement(enabled)
  if not X.HasKnownBlessings() or X.PlayerSuspended() then return false end
  db.blessingComplement = enabled == true
  X.Refresh()
  if X.RefreshConfig then X.RefreshConfig() end
  return true
end

function X.ComplementWorldBlessing(unit, class, preferred)
  local owner = X.BlessingOwner(unit, preferred.names)
  if owner ~= "other" then
    -- With an unreadable caster, don't switch blessing or top up one that
    -- could belong to a different Paladin. Regular missing-aura checks stay in force.
    return preferred, owner == "unknown" and HasAny(unit, preferred.names, 0) == true
  end
  local alternate, uncertain
  for _, key in ipairs(X.BLESSING_PRIORITY[class] or {}) do
    local blessing = blessKnown[key]
    if blessing and blessing.name ~= preferred.name then
      local source = X.BlessingOwner(unit, blessing.names)
      if source == "mine" then return blessing end -- keep our own alternate, even if an earlier one is now free
      if source == "absent" and not alternate then alternate = blessing end
      if source == "unknown" then uncertain = true end
    end
  end
  if alternate and not uncertain then return alternate end
  return preferred, true -- already covered; do not refresh another Paladin's copy
end

function X.AssignmentEnabled()
  return CLASSIC_FEATURES and db and db.assignmentEnabled == true or false
end

function X.SetAssignmentEnabled(enabled)
  if not CLASSIC_FEATURES or not db or type(enabled) ~= "boolean" then return false end
  db.assignmentEnabled = enabled
  X.assignmentGroupConflicts = nil
  return true
end

function X.SetThornsAnyClassOutdoors(enabled)
  if not CLASSIC_FEATURES or not db or type(enabled) ~= "boolean" then return false end
  db.thornsAnyClassOutdoors = enabled
  X.Refresh()
  if X.RefreshConfig then X.RefreshConfig() end
  if X.QueueAssignmentPreviewRefresh then X.QueueAssignmentPreviewRefresh() end
  return true
end

function X.ThornsAnyClassOutdoors()
  if not CLASSIC_FEATURES or not db.thornsAnyClassOutdoors then return false end
  local ok, instanced = pcall(_G.IsInInstance)
  return ok and type(instanced) == "boolean" and Readable(instanced) and not instanced
end

function X.GetAssignment(class, slot)
  local row = db and db.buffAssignments[class]
  if row then return X.CopyAssignment(row[slot]) end
end

function X.SetAssignment(class, slot, value)
  if not CLASSIC_FEATURES or not db or not X.ValidAssignmentCell(class, slot) then return false end
  local cell = X.CopyAssignment(value)
  if value ~= nil and cell == nil then return false end
  local row = db.buffAssignments[class]
  if cell ~= nil then
    row = row or {}
    row[slot], db.buffAssignments[class] = cell, row
  elseif row then
    row[slot] = nil
    if not next(row) then db.buffAssignments[class] = nil end
  end
  local undo = X.blockerUndo
  if undo and undo.kind == "rule" and undo.class == class and undo.slot == slot then X.blockerUndo = nil end
  X.assignmentGroupConflicts = nil
  return true
end

function X.AssignmentOptions()
  local options = {}
  if not CLASSIC_FEATURES then return options end
  for _, buff in ipairs(myBuffs) do
    if not buff.self and not buff.custom then
      options[#options + 1] = { key = buff.key, name = buff.name, icon = SpellIcon(buff.name) }
    end
  end
  for _, key in ipairs(X.BLESSING_KEYS) do
    local blessing = blessKnown[key]
    if blessing then
      options[#options + 1] = { key = "BLESS_" .. key, name = blessing.name, icon = SpellIcon(blessing.name) }
    end
  end
  return options
end

function X.ResolveAssignment(class, role, proposal)
  if not X.AssignmentEnabled() then return nil, "DEFAULT" end
  local row = db.buffAssignments[class]
  if proposal and proposal.kind == "row" and proposal.class == class then row = proposal.values end
  if proposal and proposal.kind == "rule" and proposal.class == class then
    local slot = role or "WORLD"
    local roleCell, allCell = row and row[slot], row and row.ALL
    if proposal.slot == slot then roleCell = proposal.value end
    if proposal.slot == "ALL" then allCell = proposal.value end
    if roleCell ~= nil then return roleCell, slot end
    if allCell ~= nil then return allCell, "ALL" end
    return nil, "DEFAULT"
  end
  if row then
    local slot = role or "WORLD"
    local cell = row[slot]
    if cell ~= nil then return cell, slot end
    if row.ALL ~= nil then return row.ALL, "ALL" end
  end
  return nil, "DEFAULT"
end

function X.BlessingForClass(class, unit, assignment, proposal, rosterMember)
  local plan = X.blessPlan[class]
  if plan and not plan.mine then return nil, "other" end
  if unit and X.blessingExceptions then
    local key = rosterMember and rosterMember.guid
    if not rosterMember then
      local ok, guid = pcall(UnitGUID, unit)
      key = ok and SafeString(guid)
    end
    local exception = key and X.blessingExceptions[key]
    if proposal and proposal.kind == "exception" and proposal.guid == key then exception = proposal.value end
    if exception then return blessKnown[exception], "exception" end
  end
  if plan then return blessKnown[plan.key], "plan" end
  if assignment ~= nil then
    if assignment then
      for _, key in ipairs(X.BLESSING_KEYS) do
        if assignment["BLESS_" .. key] then return blessKnown[key] end
      end
    end
    return nil
  end
  return blessKnown[db.blessingPreferences[class]] or myBlessing[class]
end

function X.AssignmentForUnit(class, unit, isGroup, isSelf, proposal, rosterMember)
  if not class or isSelf ~= false or not X.AssignmentEnabled() then return nil, "DEFAULT" end
  local role, manual
  if rosterMember then
    role, manual = rosterMember.role, rosterMember.manual
  elseif isGroup then
    role, manual = AssignedRole(unit), X.GetAssignmentRoleOverride(unit)
  end
  local assignment, source = X.ResolveAssignment(class, role or manual, proposal)
  return assignment, source, role, isGroup, manual
end

function X.AssignmentRuleText(class, role, source, assignment, isGroup, manual)
  if not class then return L["Rule unavailable"] end
  local names = _G.LOCALIZED_CLASS_NAMES_MALE
  local name = names and names[class] or class
  local text
  if not source or source == "DEFAULT" then
    text = string_format(L["%s · Built-in rules"], name)
  else
    local label = source == "ALL" and L["All Roles"] or source == "WORLD" and L["World"]
      or source == "TANK" and L["Tank"] or source == "HEALER" and L["Heal"] or L["DPS"]
    local format = L["%s · %s rule"]
    if source == "WORLD" or (source == "ALL" and not role and not manual) then
      format = isGroup and L["%s · %s rule (role unavailable)"] or L["%s · %s rule (nearby player)"]
    end
    text = string_format(format, name, label)
    if assignment == false then text = string_format(L["%s · None"], text) end
  end
  if manual then
    local manualLabel = manual == "TANK" and L["Tank"] or manual == "HEALER" and L["Heal"] or L["DPS"]
    text = string_format(role and L["%s · Manual role: %s (game role takes precedence)"]
      or L["%s · Manual role: %s"], text, manualLabel)
  end
  return text
end

do
local function ReadBlessingGUID(unit)
  local ok, guid = pcall(UnitGUID, unit)
  if ok and Readable(guid) and type(guid) == "string" and guid ~= "" then return guid end
end

local function CanEditBlessing()
  return CLASSIC_FEATURES and not InCombatLockdown() and InGroup() and not X.PlayerSuspended()
end

local function BlessingMemberClass(unit, guid)
  if not guid or ReadBlessingGUID(unit) ~= guid then return nil end
  local ok, _, class = pcall(UnitClass, unit)
  class = ok and SafeString(class)
  if X.BLESSING_CLASSES[class] then return class end
end

local function ChangeBlessingException(unit, guid, key)
  local class = BlessingMemberClass(unit, guid)
  if not class then return nil, "Choose an exact party or raid member name." end
  local plan = X.blessPlan[class]
  if key ~= "DEFAULT" and plan and not plan.mine then
    return nil, "The group plan assigns that class to another paladin."
  end
  X.blessingExceptions = X.blessingExceptions or {}
  if key == "DEFAULT" then X.blessingExceptions[guid] = nil
  else X.blessingExceptions[guid] = key end
  local undo = X.blockerUndo
  if undo and undo.kind == "exception" and undo.guid == guid then X.blockerUndo = nil end
  X.assignmentGroupConflicts = nil
  return X.Ignore.UnitNames(unit)
end

local function FindBlessingMember(guid)
  local match
  X.ForReportRoster(function(unit, exists)
    if not match and exists and ReadBlessingGUID(unit) == guid then match = unit end
  end)
  return match
end

function X.GetBlessingExceptionForGUID(guid)
  if not CanEditBlessing() or not Readable(guid) or type(guid) ~= "string" or guid == ""
    or not X.blessingExceptions or not X.blessingExceptions[guid] then return nil end
  local unit = FindBlessingMember(guid)
  local class = unit and BlessingMemberClass(unit, guid)
  if not class then return nil end
  local name = X.Ignore.UnitNames(unit)
  if not name or name == "" then return nil end
  local plan = X.blessPlan[class]
  local options = {}
  for _, key in ipairs(X.BLESSING_KEYS) do
    local spell = blessKnown[key]
    if spell then options[#options + 1] = { key = key, name = spell.name } end
  end
  return { name = name, key = X.blessingExceptions[guid], options = options, canSet = not plan or plan.mine == true }
end

function X.SetBlessingExceptionForGUID(guid, key, restore)
  if not CanEditBlessing() or not Readable(guid) or type(guid) ~= "string" or guid == "" then return nil end
  if not restore and (not X.blessingExceptions or not X.blessingExceptions[guid]) then return nil end
  if not Readable(key) or type(key) ~= "string" or (key ~= "DEFAULT" and not blessKnown[key]) then return nil end
  local unit = FindBlessingMember(guid)
  local name = unit and X.Ignore.UnitNames(unit)
  if not name or name == "" then return nil end
  return ChangeBlessingException(unit, guid, key)
end

function X.SetBlessingException(name, key)
  if not CanEditBlessing() then
    return nil, "Join a group and leave combat to set a blessing exception."
  end
  if key ~= "DEFAULT" and not blessKnown[key] then return nil, "Choose a blessing you know or use DEFAULT." end
  local targetGUID
  if name == "target" then
    targetGUID = ReadBlessingGUID("target")
    if not targetGUID then return nil, "Target an exact party or raid member." end
  end
  local exact, exactGUID, short, shortGUID, exactAmbiguous, shortAmbiguous
  X.ForReportRoster(function(unit, exists)
    if not exists then return end
    local full, first = X.Ignore.UnitNames(unit)
    local guid = ReadBlessingGUID(unit)
    if not guid then return end
    if guid == targetGUID or (not targetGUID and full and full:lower() == name) then
      if exactGUID and exactGUID ~= guid then exactAmbiguous = true end
      exact, exactGUID = unit, guid
    end
    if not targetGUID and first and first:lower() == name then
      if shortGUID and shortGUID ~= guid then shortAmbiguous = true end
      short, shortGUID = unit, guid
    end
  end)
  local unit = not exactAmbiguous and (exact or (not shortAmbiguous and short))
  if not unit then return nil, "Choose an exact party or raid member name." end
  return ChangeBlessingException(unit, exact and exactGUID or shortGUID, key)
end
end

-- A roster update retires departed GUIDs, even if their unit tokens are reused.
function X.PruneBlessingExceptions()
  if not X.blessingExceptions or not next(X.blessingExceptions) then return end
  if not InGroup() then wipe(X.blessingExceptions); return end
  local seen, incomplete = {}, false
  X.ForReportRoster(function(unit, exists)
    local ok, guid = pcall(UnitGUID, unit)
    guid = ok and SafeString(guid)
    if exists and guid then seen[guid] = true end
    if not exists or not guid then incomplete = true end
  end)
  if incomplete then return end
  for guid in pairs(X.blessingExceptions) do
    if not seen[guid] then X.blessingExceptions[guid] = nil end
  end
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
local function OnCooldown(name, cache)
  cache = cache or cdCache
  local c = cache[name]
  if c ~= nil then return c end
  local start, duration = SpellCD(name)
  local ok, cooling = pcall(IsCooling, start, duration)
  c = (ok and cooling) and true or false
  cache[name] = c
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

do -- one bounded helpful-aura observation, no aura state kept across units
  local english = not GetLocale or GetLocale() == "enUS" or GetLocale() == "enGB"
  local function Family(key, label, ids, name, fragment)
    local def = { key = key, label = label, ids = {}, names = {}, unresolved = ids, retryAt = 0,
      legacyName = not CLASSIC_FEATURES and english and name or nil,
      legacyFragment = not CLASSIC_FEATURES and english and fragment or nil }
    for _, id in ipairs(ids) do def.ids[id] = true end
    return def
  end
  X.CONS_DEFS = {
    Family("FLASK", "Flask", { 17626, 17627, 17628, 17629 }, nil, "Flask of"),
    Family("FOOD", "Food", { 19705, 19706, 19708, 19709, 19710 }, "Well Fed"),
  }
  if not CLASSIC_FEATURES then X.CONS_DEFS[3] = Family("RUNE", "Rune", {}, nil, "Augment Rune") end
  local drink = Family("DRINK", "Drink", { 430, 431, 432, 1133, 1135, 1137, 10250, 22734 })
  local world = Family("WORLD", "World", { 22888, 16609, 15366, 24425, 22817, 22818, 22820, 29534,
    23735, 23736, 23737, 23738, 23766, 23767, 23768, 23769 })

  local function Resolve(def, now)
    if #def.unresolved == 0 or now < def.retryAt then return end
    def.retryAt = now + 10
    for i = #def.unresolved, 1, -1 do
      local ok, name = pcall(SpellName, def.unresolved[i])
      if ok and SafeString(name) and name ~= "" then
        def.names[name] = true
        table.remove(def.unresolved, i)
      end
    end
  end

  local function OptionalAura(unit, id, now)
    local api = C_UnitAuras
    if not api then return end
    local aura
    if unit == "player" and api.GetPlayerAuraBySpellID then
      aura = X.QueryAura(api.GetPlayerAuraBySpellID, id)
    elseif api.GetUnitAuraBySpellID then
      aura = X.QueryAura(api.GetUnitAuraBySpellID, unit, id)
    end
    -- An exact match can prove presence. Nil cannot prove absence: the unit
    -- may be out of sight or restricted. Let the bounded helpful scan decide.
    if not aura then return end
    local ok, spell, expiration, helpful, harmful = pcall(function()
      return aura.spellId, aura.expirationTime, aura.isHelpful, aura.isHarmful
    end)
    if not ok or not Readable(spell) or spell ~= id or not Readable(expiration)
      or type(expiration) ~= "number" or not (expiration == 0 or (expiration > now and expiration < math_huge)) then return end
    if type(helpful) ~= "nil" and (not Readable(helpful) or helpful ~= true) then return end
    if type(harmful) ~= "nil" and (not Readable(harmful) or harmful ~= false) then return end
    return helpful == true or harmful == false -- absence of both flags is not proof
  end

  local function Matches(def, id, name)
    if id and def.ids[id] then return true end
    if name and (def.names[name] or name == def.legacyName
      or (def.legacyFragment and name:find(def.legacyFragment, 1, true))) then return true end
    -- A known aura ID suffices for a defined ID catalogue, but neither an
    -- unreadable ID nor an untranslated name can prove absence on its own.
    if (id and next(def.ids)) or (name and (def.legacyName or def.legacyFragment
      or (next(def.names) and #def.unresolved == 0))) then return false end
  end

  function X.ObserveConsumables(unit, output, checkFood, checkDrink, optional)
    wipe(output)
    local now = GetTime()
    local remaining, unavailable = checkFood and #X.CONS_DEFS or 0, {}
    if checkFood then for _, def in ipairs(X.CONS_DEFS) do Resolve(def, now) end end
    if checkDrink then Resolve(drink, now); remaining = remaining + 1 end
    if optional then remaining = remaining + 1 end
    if optional and OptionalAura(unit, optional, now) then output.OPTIONAL, remaining = true, remaining - 1 end
    if remaining == 0 then return output end
    local drinkUnknown, optionalUnknown
    for i = 1, 40 do
      local done, name, expiry, complete, _, id = X.ReadBuff(unit, i, false, true)
      if done then
        if complete then
          if checkFood then
            for _, def in ipairs(X.CONS_DEFS) do
              if output[def.key] == nil and not unavailable[def.key]
                and (next(def.ids) or def.legacyName or def.legacyFragment) then output[def.key] = false end
            end
          end
          if checkDrink and not output.DRINK and not drinkUnknown then output.DRINK = false end
          if optional and not output.OPTIONAL and not optionalUnknown then output.OPTIONAL = false end
        end
        return output
      end
      if not expiry or expiry == 0 or expiry > now then
        if checkFood then
          for _, def in ipairs(X.CONS_DEFS) do
            local key = def.key
            if not output[key] then
              local match = Matches(def, id, name)
              if match then output[key] = true; remaining = remaining - 1
              elseif match == nil then unavailable[key] = true end
            end
          end
        end
        if checkDrink and not output.DRINK then
          local match = Matches(drink, id, name)
          if match then output.DRINK = true; remaining = remaining - 1
          elseif match == nil then drinkUnknown = true end
        end
        if optional and not output.OPTIONAL then
          if id == optional then output.OPTIONAL = true; remaining = remaining - 1
          elseif not id then optionalUnknown = true end
        end
      end
      if remaining == 0 then break end -- every requested category hit
    end
    return output
  end

  local observation = {}
  function X.ScanConsumables(unit)
    local checkFood = db.consumables
    local checkDrink = CLASSIC_FEATURES and db.drinkWatch
    if db.liteMode or not (checkFood or checkDrink) then return end
    X.ObserveConsumables(unit, observation, checkFood, checkDrink)
    if checkFood then
      for _, def in ipairs(X.CONS_DEFS) do
        local has, t = observation[def.key], X.consTally[def.key]
        if not t then t = { total = 0, miss = 0, unknown = 0 }; X.consTally[def.key] = t end
        if has == nil then t.unknown = t.unknown + 1
        else
          t.total = t.total + 1
          if not has then t.miss = t.miss + 1 end
        end
      end
    end
    return observation.DRINK
  end

  function X.WorldBuffsText()
    if not CLASSIC_FEATURES then return nil end
    local found, complete, now = {}, false, GetTime()
    Resolve(world, now)
    local unreadable = false
    for i = 1, 40 do
      local done, name, expiry, ended, _, id = X.ReadBuff("player", i, false, true)
      if done then complete = ended and not unreadable; break end
      if not expiry or expiry == 0 or expiry > now then
        local match = Matches(world, id, name)
        if match and name then
          local when, left = "", expiry and expiry > 0 and expiry - now
          if left then
            when = left >= 3600 and string_format(" ~%dh", math_floor(left / 3600))
              or string_format(" ~%dm", math_floor(left / 60))
          end
          found[#found + 1] = name .. when
        elseif match ~= false then unreadable = true end
      end
    end
    if not complete then found[#found + 1] = L["Some world buff information is unavailable."] end
    if #found > 0 then return L["World"] .. ": " .. table.concat(found, ", ") end
  end
end

do
  local current, spare = {}, {}
  local function Track(unit, now)
    if X.ReadUnitBool(UnitExists, unit) ~= true then return end
    local guid = X.UnitGUIDOf(unit)
    if not guid or current[guid] then return end
    current[guid] = true
    local dead = X.ReadUnitBool(UnitIsDeadOrGhost, unit)
    if dead == true then
      X.dead[guid], X.rezAt[guid] = now, nil
    elseif dead == false and X.dead[guid] then
      X.dead[guid], X.rezAt[guid] = nil, now
    end
  end

  function X.TrackDeaths(list)
    local now = GetTime()
    wipe(current)
    for i = 1, #list do Track(list[i], now) end
    Track("player", now)
    for guid, last in pairs(X.dead) do if not current[guid] or now - last >= 600 then X.dead[guid] = nil end end
    for guid, last in pairs(X.rezAt) do if not current[guid] or now - last >= 60 then X.rezAt[guid] = nil end end
    for guid, last in pairs(X.expiredAt) do if not current[guid] or now - last >= 10 then X.expiredAt[guid] = nil end end
    for guid, keys in pairs(X.missPrev) do
      if not current[guid] then
        X.missPrev[guid] = nil
        wipe(keys)
        spare[#spare + 1] = keys
      end
    end
  end

  function X.ResetMissingScan()
    for guid, keys in pairs(X.missNow) do
      wipe(keys)
      spare[#spare + 1] = keys
      X.missNow[guid] = nil
    end
  end

  function X.RecordMissing(guid, unit, spells, unknown)
    local previous = X.missPrev[guid]
    if unknown and not previous then return end
    local slot = #spare
    local keys = spare[slot] or {}
    spare[slot] = nil
    X.missNow[guid] = keys
    if unknown then
      for k in pairs(previous) do keys[k] = true end
      return
    end
    local expired, fall
    for _, spell in ipairs(spells) do
      local key = X.KeyOfName(spell)
      if key then
        keys[key] = true
        if previous and not previous[key] then
          local names
          for _, b in ipairs(myBuffs) do if b.name == spell then names = b.names; break end end
          local blessing = blessKeys[spell] and blessKnown[blessKeys[spell]:sub(7)]
          if HasAny(unit, names or (blessing and blessing.names) or { spell }, 0) == false then
            expired, fall = true, fall or not Single.spell[key]
          end
        end
      end
    end
    return expired, fall
  end
end

local function MeasureExpiry(unit, key, name, has, left, observe, blessing)
  if scanHorizon and left and observe and X.SubgroupAllows(key, unit, true) then
    X.Intel.Observe(unit, key, name, left, blessing)
  end
  if has == true and left and left <= 300 then
    X.expiryTally[key] = (X.expiryTally[key] or 0) + 1
  end
end

local function Missing(unit, out, isGroup, isSelf, report, detail)
  wipe(out)
  if not report then X.remainTmp, X.auraUnknown, X.auraNeedsBuff = nil, nil, nil end
  local reviewing = report == "assignmentReview"
  local subgroupKey = detail and detail.subgroupKey
  local class = reviewing and detail.member.class
  if not reviewing then
    local ok, _, file = pcall(UnitClass, unit)
    class = ok and SafeString(file) or nil  -- class is used as a table key
  end
  if not class then
    if report == "why" then detail.rule = L["Rule unavailable"] end
    return 0, true, false
  end
  if not reviewing then X.scanUnit, X.blessingScanUnit = nil, nil end -- fresh index scans for aura readers
  local n = 0
  local unknown, checked
  local proposal, member
  if reviewing then proposal, member = detail.proposal, detail.member end
  local assignment, source, role, roleRead, manual = X.AssignmentForUnit(class, unit, isGroup, isSelf, proposal, member)
  if reviewing and not roleRead then role, roleRead = member.role, true end
  if report == "why" then
    detail.assignment = assignment ~= nil
    detail.rule = X.AssignmentRuleText(class, role, source, assignment, isGroup, manual)
  end
  for i = 1, #myBuffs do
    local b = myBuffs[i]
    local applies, outdoorThorns
    if b.self then
      applies = isSelf
    else
      outdoorThorns = assignment == nil and b.key == "THORNS" and not b.classes[class]
        and X.ThornsAnyClassOutdoors()
      applies = (b.classes[class] or outdoorThorns) and (not isSelf or db.includeSelf)
                and (isGroup or isSelf or not b.groupOnly)
      if applies and b.role then
        if not roleRead then role, roleRead = AssignedRole(unit), true end
        if role and role ~= b.role then applies = false end  -- e.g. a DPS death knight
      end
      if assignment ~= nil and not b.custom then
        applies = assignment and assignment[b.key] and (isGroup or not b.groupOnly)
          and (not b.single or applies)
      end
    end
    local eligible = (not subgroupKey or subgroupKey == b.key and not b.self)
      and applies and IsOn(b.key, b.default) and X.ContextOK(b.key)
    if report == "why" and eligible and outdoorThorns then
      detail.rule = detail.rule .. " · " .. L["Thorns: Any Class Outdoors"]
    end
    local coverage = b.key == "FORTITUDE" and X.FortitudeCoverage or HasAny
    if report == "evidence" then
      if detail.selfOnly then eligible = true end -- actual player auras, independent of tracking toggles
      local has,left
      if eligible and detail.observable then has,left=coverage(unit,b.names,0,3600000) end
      detail.record(b.key,eligible,has,left)
    elseif report == "raidCoverage" then
      if eligible and not b.self then
        local has
        if detail.observable then has = coverage(unit, b.names, 0) end
        detail.record(b.name, has)
      end
    elseif reviewing and eligible then
      out[#out + 1] = b.name
    elseif eligible then
      local thr = report and report ~= "why" and 0
        or (db.rebuffPer and db.rebuffPer[b.key]) or db.rebuff
      local has, left = coverage(unit, b.names, thr, not report and isGroup and scanHorizon)
      if report then
        checked = true
        if has == nil then unknown = true end
        if report == "why" and has == false and OnCooldown(b.name, detail.cooldowns) then
          detail.cooldown[#detail.cooldown + 1] = b.name
        elseif has == false then
          n = n + 1; out[n] = b.name
        end
        if report == "ready" then X.RecordReadyAura(detail, unit, b.name, b.names, has, b.key) end
      else
        if has == nil then X.auraUnknown = true
        elseif has == false then X.auraNeedsBuff = true end
        local t
        if isGroup and has ~= nil then
          t = X.tally[b.key]
          if not t then t = { total = 0, miss = 0 }; X.tally[b.key] = t end
          t.total = t.total + 1
          MeasureExpiry(unit, b.key, b.name, has, left, not b.single)
        end
        if has == false and not OnCooldown(b.name) then
          n = n + 1
          out[n] = b.name
          if t then t.miss = t.miss + 1 end
          if n == 1 and left and left > 0 then X.remainTmp = left end
        end
      end
    end
  end

  local bl, blessingSource
  if CLASSIC_FEATURES then
    bl, blessingSource = X.BlessingForClass(class, (isGroup or isSelf) and unit, assignment, proposal, member)
  end
  if report == "why" then
    if blessingSource == "exception" then detail.blessing = L["Blessing: player exception"]
    elseif blessingSource == "plan" then detail.blessing = L["Blessing: group plan"]
    elseif blessingSource == "other" then detail.blessing = L["Blessing assigned to another Paladin"] end
  end
  local blessingEligible = (not subgroupKey or subgroupKey == "BLESSINGS")
    and bl and IsOn("BLESSINGS", true) and (not isSelf or db.includeSelf)
    and X.ContextOK("BLESSINGS")
  if report == "evidence" then
    if detail.selfOnly then blessingEligible=bl~=nil end
    local has,left
    if blessingEligible and detail.observable then has,left=HasAny(unit,bl.names,0,3600000) end
    detail.record("BLESSINGS",blessingEligible,has,left)
  elseif report == "raidCoverage" then
    if blessingEligible then
      local has
      if detail.observable then has = HasAny(unit, bl.names, 0) end
      detail.record(bl.name, has)
    end
  elseif reviewing and blessingEligible then
    out[#out + 1] = bl.name
  elseif blessingEligible then
    local covered
    if db.blessingComplement and not isGroup and isSelf == false and assignment == nil and not blessingSource then
      local preferred = bl
      bl, covered = X.ComplementWorldBlessing(unit, class, preferred)
      if report == "why" and bl ~= preferred then detail.blessing = L["Blessing: complement another Paladin"] end
    end
    local has, left = covered, nil
    if not has then
      local thr = report and report ~= "why" and 0 or db.rebuff
      has, left = HasAny(unit, bl.names, thr, not report and isGroup and scanHorizon)
    end
    if report then
      checked = true
      if has == nil then unknown = true end
      if report == "why" and has == false and OnCooldown(bl.name, detail.cooldowns) then
        detail.cooldown[#detail.cooldown + 1] = bl.name
      elseif has == false then n = n + 1; out[n] = bl.name end
      if report == "ready" then X.RecordReadyAura(detail, unit, bl.name, bl.names, has, "BLESSINGS") end
    else
      if has == nil then X.auraUnknown = true
      elseif has == false then X.auraNeedsBuff = true end
      local t
      if isGroup and has ~= nil then
        t = X.tally.BLESSINGS
        if not t then t = { total = 0, miss = 0 }; X.tally.BLESSINGS = t end
        t.total = t.total + 1
        MeasureExpiry(unit, "BLESSINGS", bl.name, has, left, true, bl.priorityKey)
      end
      if has == false and not OnCooldown(bl.name) then
        n = n + 1
        out[n] = bl.name
        if t then t.miss = t.miss + 1 end
        if n == 1 and left and left > 0 then X.remainTmp = left end
      end
    end
  end
  if report then return n, unknown, checked end
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
    if key == "BLESSINGS" then
      for name in pairs(blessKeys) do if not X.prioIdx[name] then X.prioIdx[name] = i end end
    end
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
  if a.smartTier ~= b.smartTier then return a.smartTier < b.smartTier end
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
  if a.group ~= b.group then return a.group end
  return a.sortName < b.sortName  -- readable name, or "" (a shown name may be protected)
end

-- Sort priority for "role" mode: you, then tanks, then group leaders, then
-- everyone else. Tanks are players with the TANK group role (retail role
-- check / dungeon finder) or the raid MAINTANK/MAINASSIST flag — never a
-- guess from class.
local function RoleOf(unit, isSelf)
  if isSelf then return 0, db.smartPriority and AssignedRole(unit) or nil end
  local assigned = AssignedRole(unit)
  if assigned == "TANK" then return 1, assigned end
  local idx = unit:match("^raid(%d+)$")
  if idx and GetRaidRosterInfo then
    local ok, _, _, _, _, _, _, _, _, _, role = pcall(GetRaidRosterInfo, tonumber(idx))
    if ok and Readable(role) and (role == "MAINTANK" or role == "MAINASSIST") then
      return 1, assigned or (role == "MAINTANK" and "TANK" or nil)
    end
  end
  if UnitIsGroupLeader then
    local ok, leader = pcall(UnitIsGroupLeader, unit)
    if ok and Readable(leader) and leader == true then return 2, assigned end
  end
  return 3, assigned
end

---------------------------------------------------------------------------
-- Ignore list. db.ignored keeps names as entered (value true -- the same
-- format as before 1.3.2); matching goes through Ignore.index, keyed by
-- Ignore.Key(): lowercase, spaces removed. "Name-Realm" ignores one player;
-- a bare "Name" (every entry saved before 1.3.2) ignores that name on any realm.
---------------------------------------------------------------------------
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
  for _, name in ipairs(Ignore.Sorted()) do
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
-- What a stored ignore entry may be: a plausible name or name-realm. Game
-- escape codes ("|"), control characters and the list separator never occur
-- in player names, and a stored one would render as markup in the list.
Ignore.Valid = X.Settings.ValidIgnore

function Ignore.AddMany(names)
  local add, pending = {}, {}
  local available = X.Settings.Limits.ignored - X.Settings.Count(db.ignored)
  for _, name in ipairs(names) do
    if Ignore.Valid(name) then
      local key = Ignore.Key(name)
      if not Ignore.index[key] and not pending[key] then
        if #add >= available then return nil, L["Ignore list is full. Remove entries first."] end
        pending[key] = true
        add[#add + 1] = name
      end
    end
  end
  for _, name in ipairs(add) do db.ignored[name], Ignore.index[Ignore.Key(name)] = true, name end
  return #add
end

function Ignore.Add(name)
  local n, err = Ignore.AddMany({ name })
  return n == 1, err
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

-- Your own "Name-Realm", for per-character settings.
function X.CharKey()
  local full = Ignore.UnitNames("player")
  return full
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

local function ObserveSingleHolder(unit, isSelf)
  if isSelf then return end
  local lookup = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
  if not lookup then return end
  for _, buff in ipairs(myBuffs) do
    if buff.single and not Single.holder[buff.key] then
      local aura = X.QueryNamedAura(lookup, unit, buff.name, "HELPFUL|PLAYER")
      if aura then Single.holder[buff.key], Single.spell[buff.key] = unit, buff.name end
    end
  end
end

local function Consider(unit, isGroup)
  local valid, isSelf = Valid(unit)
  if not valid then return end
  -- The GUID is a table key (seen[], the listed sets) and gets compared; a
  -- protected one can't be either, so that unit is skipped.
  local guid = X.UnitGUIDOf(unit)
  if not guid or seen[guid] then return end
  -- A hidden row still owns its single-target buff, so observe it before
  -- ignore, retry and role filters can exclude its recipient.
  ObserveSingleHolder(unit, isSelf)
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
  if isGroup and X.ScanConsumables(unit) then
    X.drinkSet[guid] = true
    local dclass = X.UnitClassToken(unit)
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
  if auraUnknown then X.scanHasUnknownBuffs = true end
  if allN > 0 or X.auraNeedsBuff then X.scanHasMissingBuffs = true end
  e.remain1, e.expiringSpell = X.remainTmp, e.allMissing[1]
  local expired, fallExpired
  if isGroup then expired, fallExpired = X.RecordMissing(guid, unit, e.allMissing, auraUnknown) end
  if expired then X.expiredAt[guid] = GetTime() end
  if fallExpired and db.fallSound and X.afterCombatScan then X.fallPending = true end
  local queue = e.allMissing
  if X.subgroupDuties and next(X.subgroupDuties) and InRaid() then
    e.subgroupMissing = e.subgroupMissing or {}
    queue = X.FilterSubgroupDuties(unit, isGroup, e.allMissing, e.subgroupMissing)
  end
  local n, approximate = X.FilterInRange(unit, queue, e.missing, isSelf)
  if #queue > 0 and n == 0 and db.rangeWatch then X.farNow[guid] = nm or true end
  if n == 0 then return end
  local class = X.UnitClassToken(unit)
  e.unit, e.guid, e.name, e.class, e.group = unit, guid, nm or unit, class, isGroup
  e.fullName, e.sortName = full, nm or ""
  e.isSelf = isSelf
  e.rangeBucket = 0
  e.approximateRange = approximate
  e.marker = X.ReadRaidMarker(unit)
  local ea = X.expiredAt[guid]
  e.expired = isGroup and not auraUnknown and (expired or (ea and GetTime() - ea < 10)) or nil
  nEntries = slot
  local rz = X.rezAt[guid]
  e.rezzed = (rz and GetTime() - rz < 60) or nil
  e.groupCast = false
  e.role, e.groupRole = RoleOf(unit, isSelf)
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
  if not X.UnitPresent(petUnit) then return end
  if X.ReadUnitBool(UnitIsDeadOrGhost, petUnit) == true then return end
  if X.ReadUnitBool(UnitCanAssist, "player", petUnit) == false then return end
  local isSelf = X.IsSelf(petUnit)
  if isSelf == nil then return end
  local guid = X.UnitGUIDOf(petUnit)
  if not guid or seen[guid] then return end
  seen[guid] = true
  local pname = X.UnitNameOf(petUnit)
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
  local queue = e.allMissing
  if X.subgroupDuties and next(X.subgroupDuties) and InRaid() then
    e.subgroupMissing = e.subgroupMissing or {}
    queue = X.FilterSubgroupDuties(ownerUnit, true, e.allMissing, e.subgroupMissing)
  end
  local n, approximate = X.FilterInRange(petUnit, queue, e.missing, isSelf)
  if n == 0 then return end
  nEntries = slot
  local oclass = X.UnitClassToken(ownerUnit)
  e.unit, e.guid, e.name = petUnit, guid, pname
  e.sortName = (X.UnitNameOf(ownerUnit) or "") .. " " .. pname
  e.fullName = nil
  e.class = SafeString(oclass)
  e.group, e.isSelf, e.pet = true, false, true
  e.rangeBucket = 0
  e.approximateRange = approximate
  e.marker = X.ReadRaidMarker(petUnit)
  e.remain1, e.expiringSpell, e.groupRole = nil, nil, nil
  e.expired, e.rezzed = nil, nil
  e.groupCast = false
  e.role = 3
end

-- Last-scan diagnostics for /br debug: how many nameplate units the client
-- handed us on the latest pass, and how many of them were players.

local function MissingOrder(entry, spell)
  local manual = X.prioIdx and X.prioIdx[spell] or 999
  local tier = db.smartPriority and X.Intel.Tier(entry, X.KeyOfName(spell), blessKeys[spell]) or 3
  return tier * 1000 + manual
end

local function OrderMissing(entry)
  local m = entry.missing
  if db.smartPriority or (X.prioIdx and next(X.prioIdx)) then
    for i = 2, #m do
      local v, order = m[i], MissingOrder(entry, m[i])
      local j = i - 1
      while j >= 1 and MissingOrder(entry, m[j]) > order do
        m[j + 1] = m[j]
        j = j - 1
      end
      m[j + 1] = v
    end
  end
  entry.smartTier = math_floor(MissingOrder(entry, m[1]) / 1000)
  entry.prio1 = X.prioIdx and X.prioIdx[m[1]] or nil
  if entry.expiringSpell ~= m[1] then entry.remain1 = nil end
end

do
  local committed={group={generation=0,buffs={},members={},incomplete=true},self={generation=0,buffs={},members={},incomplete=true}}
  local pending
  local function Clone(value)
    if type(value)~="table" then return value end
    local out={};for k,v in pairs(value) do out[k]=Clone(v) end;return out
  end
  local function Build(scope)
    local selfOnly=scope=="self"
    local result={buffs={},members={},incomplete=false,overflow=false}
    local definitions={}
    for _,b in ipairs(myBuffs) do definitions[#definitions+1]={key=b.key,name=b.name,spellID=b.id} end
    if next(blessKnown) then definitions[#definitions+1]={key="BLESSINGS",name=L["Blessings"]} end
    table_sort(definitions,function(a,b) return a.key<b.key end)
    local maxBuffs=selfOnly and 16 or 24
    local admitted={}
    for i,b in ipairs(definitions) do
      if i>maxBuffs then result.overflow,result.incomplete=true,true;break end
      result.buffs[#result.buffs+1]=b;admitted[b.key]=true
    end
    local knownGUIDs={}
    local function Member(unit)
      if X.ReadUnitBool(UnitExists,unit)~=true then return end
      local guid=X.UnitGUIDOf(unit)
      if not guid then result.incomplete=true;return end
      if knownGUIDs[guid] then return end
      if #result.members>=40 then result.overflow,result.incomplete=true,true;return end
      knownGUIDs[guid]=true
      local full,name=Ignore.UnitNames(unit)
      local subgroup=InRaid() and X.RaidSubgroup(tonumber(unit:match("^raid(%d+)$"))) or 1
      local row={guid=guid,unit=unit,label=full or name or unit,subgroup=subgroup or 0,cells={}}
      for _,b in ipairs(result.buffs) do row.cells[b.key]={state="unknown"} end
      result.members[#result.members+1]=row
      local observable=X.ReadUnitBool(UnitIsConnected,unit)==true and X.ReadUnitBool(UnitIsDeadOrGhost,unit)==false
      if UnitInPhase and X.ReadUnitBool(UnitInPhase,unit)~=true then observable=false end
      local isSelf=X.ReadUnitBool(UnitIsUnit,unit,"player")
      if isSelf==nil then result.incomplete=true;return end
      Missing(unit,{},true,isSelf,"evidence",{selfOnly=selfOnly,observable=observable,record=function(key,eligible,has,left)
        if not admitted[key] then return end
        local state=not eligible and "not-applicable" or has==true and "confirmed" or has==false and "missing" or "unknown"
        local cell={state=state};row.cells[key]=cell
        if state=="unknown" then result.incomplete=true end
        if state=="confirmed" and X.Readable(left) and type(left)=="number" and left==left and left>=0 and left<math.huge then
          local now=X.ReadUnitNumber(GetTime);if now and now>=0 then cell.expiresAt=now+left end
        end
      end})
    end
    if selfOnly then Member("player")
    else
      local list=InRaid() and RAID or PARTY
      for i=1,#list do Member(list[i]) end
      Member("player")
      local expected=X.ReadUnitNumber(GetNumGroupMembers)
      if expected and expected>0 and #result.members~=expected then result.incomplete=true end
    end
    return result
  end
  function X.BeginCoverageEvidence()
    pending={}
    if db.matrixView then pending.group=Build("group") end
    if db.selfStatusStrip then pending.self=Build("self") end
  end
  function X.CommitCoverageEvidence(generation,at)
    for _,scope in ipairs({"group","self"}) do
      local value=pending and pending[scope]
      if value then value.generation,value.observedAt=generation,at;committed[scope]=value
      elseif not (scope=="group" and db.matrixView or scope=="self" and db.selfStatusStrip) then
        committed[scope]={generation=generation,observedAt=at,buffs={},members={},incomplete=true}
      end
    end
    pending=nil
  end
  function X.CoverageEvidence(scope)
    local result=Clone(committed[scope=="self" and "self" or "group"])
    result.freshness=X.Status.Freshness();return result
  end
end

local function CollectEntries()
  X.Status.Attempt()
  X.BeginCoverageEvidence()
  local nowT = GetTime()
  scanHorizon = X.Intel.BeginScan()
  for guid, untilTime in pairs(X.failedTargets) do
    if untilTime <= nowT then X.failedTargets[guid] = nil end
  end
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
  X.scanHasUnknownBuffs, X.scanHasMissingBuffs, X.scanNameFiltered = false, false, false
  X.rangeSilent = false
  X.ResetMissingScan()
  X.fallPending = nil
  nEntries = 0
  X.platesSeen, X.playersSeen = 0, 0
  local list = InRaid() and RAID or PARTY
  X.TrackDeaths(list)
  for i = 1, #list do Consider(list[i], true) end
  Consider("player", true)
  -- Group pets (1.8.0): your pet and your group members' pets, as rows.
  if db.pets and not db.liteMode then
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
    if X.ReadUnitBool(UnitExists, u) == true then
      X.platesSeen = X.platesSeen + 1
      if X.ReadUnitBool(UnitIsPlayer, u) == true then X.playersSeen = X.playersSeen + 1 end
      Consider(u, false)
    end
  end
  if X.UpdateNearbyScanCount then X.UpdateNearbyScanCount() end
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
    X.scanNameFiltered = #drop > 0
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
  if X.prioDirty then X.RebuildPrio() end
  -- Set the primary spell before classifying casts handled by another
  -- player, assignments, and duration tags. All consume that same offer.
  for i = 1, nEntries do OrderMissing(entries[i]) end
  -- Coordination marks (1.5.0): a player another BuffRadar user just buffed
  -- sinks in the order (see EntryOrder) and shows a tag; a player who asked
  -- for a buff in chat is tagged while the request is fresh.
  for i = 1, nEntries do
    local e = entries[i]
    local h = X.handled[e.guid]
    e.handled = (h and nowT - h.t < 5 and h.key == X.KeyOfName(e.missing[1])) or nil
    local ak = X.asked[e.guid]
    e.asked = (ak and nowT - ak < 120) or nil
    e.drinking = X.drinkSet[e.guid] or nil
    -- Repeat-offender history (1.8.0): remember who was seen unbuffed
    -- this group session; the count lands when the group ends.
    if e.group and not e.isSelf and not e.pet and e.fullName then X.TrackOffender(e.guid, e.fullName) end
    e.queued = nil  -- set after the sort, on the new top row only
    e.weapon = nil  -- set below, on your own row only (pooled entries)
  end
  -- Weapon watch (1.7.0): your own row carries the reminder tag.
  if db.weaponWatch and not db.liteMode and X.WeaponEnchantMissing() then
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
    local who = k and (X.assign[k] or X.CoordinatedHolder(k))
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
  if nEntries > 1 then table_sort(entries, EntryOrder) end
  -- Cast queue highlight (1.6.0): right after one of your casts lands, the
  -- new top row is where the next cast should go.
  if nEntries > 0 and db and db.queueTag and nowT - (X.queueAt or 0) < 3 then
    entries[1].queued = true
  end
  scanHorizon = nil
  return nEntries
end

-- Spell name -> buff key, rebuilt when the spellbook changes. Used to tell
-- "this buff vanished" (expired / dispelled / death) from "never had it".
function X.KeyOfName(name)
  if X.nameKeyStamp ~= bookCount then
    X.nameKeyStamp = bookCount
    X.nameKey = {}
    for _, b in ipairs(myBuffs) do X.nameKey[b.name] = b.key end
    for _, b in pairs(blessKnown) do X.nameKey[b.name] = "BLESSINGS" end
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
  if ok and Readable(idx) and type(idx) == "number" and idx >= 1 and idx <= 4 and idx == math_floor(idx) then return "s" .. idx end
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
      if X.ApplyGeometry then X.ApplyGeometry() end
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

-- Raid tokens already include the player. In a party, scan the player once
-- before the party tokens. An unreadable occupied slot is unknown, not absent.
function X.ForReportRoster(visit, limit)
  local raid = InRaid()
  local roster = raid and RAID or PARTY
  for i = raid and 1 or 0, limit and math_min(limit, #roster) or #roster do
    local unit = roster[i] or "player"
    local exists = X.ReadUnitBool(UnitExists, unit)
    if exists ~= false then visit(unit, exists) end
  end
end

function X.ReadyIdentity(unit)
  local ok, guid = pcall(UnitGUID, unit)
  local full, name = Ignore.UnitNames(unit)
  return ok and SafeString(guid) or nil, full, name
end

function X.RaidSubgroup(index)
  if not index or not GetRaidRosterInfo then return nil end
  local ok, _, _, subgroup = pcall(GetRaidRosterInfo, index)
  if ok and Readable(subgroup) and type(subgroup) == "number"
    and subgroup >= 1 and subgroup <= 8 and subgroup == math_floor(subgroup) then return subgroup end
end

function X.RaidCoverage()
  if not CLASSIC_FEATURES or not db or InCombatLockdown() or X.PlayerSuspended() then return nil end
  local raid = InRaid()
  local report = { raid = raid, incomplete = false, groups = {}, grouped = InGroup() }
  if not report.grouped then return report end
  local count, seenGUIDs, groups = 0, {}, {}
  local size = X.ReadUnitNumber(GetNumGroupMembers)
  X.ForReportRoster(function(unit, exists)
    if not exists then report.incomplete = true; return end
    local guid, full, short = X.ReadyIdentity(unit)
    if not guid or guid == "" or seenGUIDs[guid] then report.incomplete = true; return end
    seenGUIDs[guid], count = true, count + 1
    local isSelf = X.IsSelf(unit)
    if not full or full == "" or isSelf == nil then report.incomplete = true; return end
    if Ignore.Has(full, short) or X.SessionHas(full, short) then return end
    local subgroup = 1
    if raid then
      subgroup = X.RaidSubgroup(tonumber(unit:match("^raid(%d+)$"))) or 0
      if subgroup == 0 then report.incomplete = true end
    end
    local group = groups[subgroup]
    if not group then group = {}; groups[subgroup] = group end
    local memberStatus = {}
    local observable = X.ReadUnitBool(UnitIsDeadOrGhost, unit) == false
      and X.ReadUnitBool(UnitIsConnected, unit) == true
    if _G.UnitInPhase and X.ReadUnitBool(_G.UnitInPhase, unit) ~= true then observable = false end
    local _, unknown = Missing(unit, {}, true, isSelf, "raidCoverage", {
      observable = observable,
      record = function(spell, has)
        local rank = has == true and 3 or has == nil and 2 or 1
        if rank > (memberStatus[spell] or 0) then memberStatus[spell] = rank end
      end,
    })
    if unknown then report.incomplete = true end
    for spell, rank in pairs(memberStatus) do
      local row = group[spell]
      if not row then row = { name = spell, confirmed = 0, missing = {}, unknown = {} }; group[spell] = row end
      if rank == 3 then row.confirmed = row.confirmed + 1
      elseif rank == 2 then row.unknown[#row.unknown + 1] = full
      else row.missing[#row.missing + 1] = full end
    end
  end)
  X.scanUnit = nil
  if count ~= size then report.incomplete = true end
  for offset = 1, 9 do
    local subgroup = offset % 9
    local group = groups[subgroup]
    if group and next(group) then
      local buffs = {}
      for _, buff in pairs(group) do
        table_sort(buff.missing)
        table_sort(buff.unknown)
        buffs[#buffs + 1] = buff
      end
      table_sort(buffs, function(a, b) return a.name < b.name end)
      report.groups[#report.groups + 1] = { id = subgroup, buffs = buffs }
    end
  end
  return report
end

do
  local function MemberGUID(unit)
    local ok, guid = pcall(UnitGUID, unit)
    if ok and type(guid) == "string" and Readable(guid) and guid ~= "" then return guid end
  end

  function X.GetAssignmentRoleOverride(unit)
    if not X.assignmentRoleOverrides or not next(X.assignmentRoleOverrides) then return nil end
    local guid = MemberGUID(unit)
    return guid and X.assignmentRoleOverrides[guid]
  end

  function X.SetAssignmentRole(unit, guid, role)
    if not X.AssignmentEnabled() or InCombatLockdown() or X.PlayerSuspended() or not InGroup()
      or not Readable(unit) or type(unit) ~= "string"
      or not Readable(guid) or type(guid) ~= "string" or guid == ""
      or (type(role) ~= "nil" and (not Readable(role)
        or (role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER"))) then
      return false
    end
    local matched = false
    X.ForReportRoster(function(member, exists)
      if exists and member == unit and X.IsSelf(member) == false
        and MemberGUID(member) == guid and (role == nil or not AssignedRole(member)) then
        matched = true
      end
    end)
    if not matched then return false end
    X.assignmentRoleOverrides = X.assignmentRoleOverrides or {}
    X.assignmentRoleOverrides[guid] = role
    X.assignmentGroupConflicts = nil
    return true
  end

  function X.PruneAssignmentRoleOverrides()
    if not X.assignmentRoleOverrides or not next(X.assignmentRoleOverrides) then return end
    local size = X.ReadUnitNumber(GetNumGroupMembers)
    if not size or size <= 0 then return end  -- GROUP_LEFT clears the entire session
    local limit = math_floor(size) - (InRaid() and 0 or 1)
    local rosterGUIDs, count, incomplete = {}, 0, false
    X.ForReportRoster(function(member, exists)
      local guid = exists and MemberGUID(member)
      if guid and not rosterGUIDs[guid] then
        rosterGUIDs[guid], count = true, count + 1
      else
        incomplete = true
      end
    end, limit)
    if incomplete or count ~= size then return end
    for guid in pairs(X.assignmentRoleOverrides) do
      if not rosterGUIDs[guid] then X.assignmentRoleOverrides[guid] = nil end
    end
  end

  function X.AssignmentRoleEditorState(unit, exists)
    if not exists or not X.AssignmentEnabled() or X.IsSelf(unit) ~= false then return end
    local guid = MemberGUID(unit)
    if not guid then return end
    local manual = X.assignmentRoleOverrides and X.assignmentRoleOverrides[guid]
    local canSet = AssignedRole(unit) == nil
    return guid, manual, canSet or manual ~= nil, canSet
  end
end

-- Coverage is independent of cast distance, cooldowns and window filters.
-- Keep the report out of the live entry pool so it cannot alter click metadata.
function X.GroupBuffReport(survivorsOnly, details, preparation)
  local report = { people = {}, buffs = 0, checked = 0, unknown = 0 }
  if details then report.members = {} end
  local seenGUIDs = preparation and {}
  X.ForReportRoster(function(unit, exists)
    local dead = X.ReadUnitBool(UnitIsDeadOrGhost, unit)
    if survivorsOnly and dead == true then return end
    local isSelf = X.IsSelf(unit)
    local full, name
    if exists then full, name = Ignore.UnitNames(unit) end
    local detail
    if details then
      local guid
      if exists then guid = X.ReadyIdentity(unit) end
      detail = { unit = unit, name = name or unit, full = full,
        guid = guid, missing = {}, expiring = {}, unavailable = {} }
      report.members[#report.members + 1] = detail
    end
    if preparation and detail then
      local guid = detail.guid
      if not guid or guid == "" or seenGUIDs[guid] then
        detail.guid, detail.unknown = nil, true
        report.unknown = report.unknown + 1
        return
      end
      seenGUIDs[guid] = true
    end
    local ignored
    if preparation then
      ignored = Ignore.Has(full, name) or X.SessionHas(full, name)
      if ignored and detail then detail.ignored = true end
      if ignored then return end
    end
    local connected
    if exists and isSelf ~= nil and dead == false then
      connected = X.ReadUnitBool(UnitIsConnected, unit)
    end
    local observable = exists and isSelf ~= nil and dead == false and connected == true
    if preparation then
      if observable and _G.UnitInPhase and X.ReadUnitBool(_G.UnitInPhase, unit) ~= true then observable = false end
      if detail then detail.observable = observable end
    end
    if not exists or isSelf == nil or dead ~= false or connected == false
      or (preparation and not observable) then
      report.unknown = report.unknown + 1
      if detail then detail.unknown = true end
      return
    end
    if not preparation and (Ignore.Has(full, name) or X.SessionHas(full, name)) then
      if detail then detail.ignored = true end
      return
    end
    local buffs = detail and detail.missing or {}
    local n, unknown, checked = Missing(unit, buffs, true, isSelf, detail and "ready" or true, detail)
    if detail then detail.unknown, detail.checked = unknown, checked end
    if unknown then report.unknown = report.unknown + 1
    elseif checked then report.checked = report.checked + 1 end
    if n > 0 then
      report.people[#report.people + 1] = { name = name or unit, buffs = buffs, unit = unit,
        guid = detail and detail.guid }
      report.buffs = report.buffs + n
    end
  end)
  -- The fallback aura cache belongs to the last scanned unit.
  X.scanUnit = nil
  return report
end

function X.RecordReadyAura(detail, unit, spell, names, has, key)
  if has == nil then
    detail.unavailable[#detail.unavailable + 1] = spell
  elseif has == true then
    local limit = (db.rebuffPer and db.rebuffPer[key]) or db.rebuff
    local longest, timerUnknown = 0, false
    for _, name in ipairs(names) do
      local seconds, presence, uncertain = X.Remaining(unit, name)
      if seconds and seconds > longest then longest = seconds end
      if presence == "unknown" or (presence == "present" and (not seconds or uncertain)) then
        timerUnknown = true
      end
    end
    if longest > 0 and longest <= limit and timerUnknown then
      detail.unavailable[#detail.unavailable + 1] = spell
    elseif longest > 0 and longest <= limit then
      detail.expiring[#detail.expiring + 1] = { name = spell, seconds = math_ceil(longest) }
    elseif longest == 0 and timerUnknown then
      detail.unavailable[#detail.unavailable + 1] = spell
    end
  end
end

function X.GroupCoverageNote(report)
  if report.unknown > 0 then
    return string_format(L[report.unknown == 1 and "Buff coverage could not be verified for %d player."
      or "Buff coverage could not be verified for %d players."], report.unknown)
  end
  if report.checked == 0 then return L["No applicable buffs were found to check."] end
end

-- WoW owns group-chat permissions. A refused send leaves the report local.
function X.SendGroupReport(text)
  local channel = InRaid() and "RAID" or (InGroup() and "PARTY" or nil)
  local send = (_G.C_ChatInfo and _G.C_ChatInfo.SendChatMessage) or _G.SendChatMessage
  if not channel then return nil, L["No group channel."] end
  if type(send) ~= "function" then return nil, L["Group chat is unavailable."] end
  if #text > 255 then return nil, L["The message exceeds the chat limit."] end
  local ok, accepted = pcall(send, text, channel)
  if ok and type(accepted) == "nil" then return channel, nil, false end -- no delivery result from the client
  if ok and Readable(accepted) and accepted == true then return channel, nil, true end
  return nil, L["The game did not accept the send."]
end

function X.SnapshotMissing(report)
  local lines = {}
  for _, person in ipairs(report.people) do
    lines[#lines + 1] = "  " .. person.name .. ": " .. table.concat(person.buffs, ", ")
  end
  return lines
end

function X.ReadyReport(report)
  if X.PlayerSuspended() then return end
  report = report or X.GroupBuffReport()
  local people = #report.people
  local note = X.GroupCoverageNote(report)
  if people == 0 then
    Print(string_format(L["Ready check: %s"],note or L["all checked buffs are present."]))
  else
    Print(string_format(L["Ready check: %d %s missing buffs (%d buffs needed). /br announce posts the list."],
      people, people == 1 and L["person is"] or L["people are"], report.buffs))
    if note then Print(note) end
    -- Auto-post (1.7.0): the leader or an assistant can have the summary
    -- posted to group chat too, so the group sees it without asking.
    if db.readyPost and X.AmLead() then
      local sent, failure = X.SendGroupReport(string_format(L["BuffRadar ready check: %d %s missing buffs (%d buffs needed).%s"],
        people, people == 1 and L["person is"] or L["people are"], report.buffs,
        note and (" " .. note) or ""))
      if not sent then Print(string_format(L["Local only — not sent: %s"], failure)) end
    end
  end
end

-- /br announce: post the group's missing buffs to party/raid chat (or
-- print them locally when solo).
function X.Announce()
  local report = X.GroupBuffReport()
  local note = X.GroupCoverageNote(report)
  local per, order = {}, {}
  for _, person in ipairs(report.people) do
    for _, spell in ipairs(person.buffs) do
      if not per[spell] then per[spell] = {}; order[#order + 1] = spell end
      per[spell][#per[spell] + 1] = person.name
    end
  end
  if #order == 0 then
    Print(note or L["All checked buffs are present -- nothing to announce."])
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
  local text = L["BuffRadar -- missing buffs: "] .. table.concat(segs, " · ")
    .. (note and (" · " .. note) or "")
  local channel, failure, accepted = X.SendGroupReport(text)
  if channel then
    Print(L[accepted and "Game accepted the group chat send; delivery is not confirmed."
      or "Group chat send requested; delivery is not confirmed."])
  else
    Print(string_format(L["Local only — not sent: %s"], failure))
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

local function RankRequirement(record)
  if not record.learned then record.learned = LevelLearned(record.id) end
  return record.learned
end

local function PickRank(name, unit, targetLevel)
  local list = ranks[name]
  if not list or #list == 0 then return nil end
  if targetLevel == nil then targetLevel = unit and X.ReadUnitNumber(UnitLevel, unit) or 0 end
  local pick = list[#list]
  if targetLevel and targetLevel > 0 then
    for k = #list, 1, -1 do
      local req = RankRequirement(list[k])
      if not req or req - 10 <= targetLevel then pick = list[k]; break end
      pick = list[k]  -- keep falling back toward rank 1
    end
  end
  return pick
end

local function CastText(name, pick)
  if pick and pick.sub and pick.sub ~= "" and pick.rank > 0 then
    return name .. "(" .. pick.sub .. ")"
  end
  return name
end

function X.DefaultRank(spell, level)
  local list = ranks[spell]
  if not list or not level or level <= 0 then return nil end
  for i = #list, 1, -1 do
    local record = list[i]
    local requirement = RankRequirement(record)
    if not requirement then return nil end
    if requirement - 10 <= level then return #list > 1 and record or nil end
  end
  return false
end

function X.RankTooLow(spell, level, method)
  return CLASSIC_FEATURES and method ~= "macro" and X.DefaultRank(spell, level) == false
end

function X.BindingRank(spell, unit, level, method)
  if X.RankTooLow(spell, level, method) then return false end
  if method == "target" then return X.DefaultRank(spell, level) end
  return PickRank(spell, unit, level)
end

-- Group version of a castable buff, for modifier clicks (1.14.0, Brief 3):
-- the def's groupCast (Prayer of Fortitude, Gift of the Wild, ...) or a
-- blessing's greater version; nil when the buff has none.
local function GroupSpellFor(spell)
  if not spell then return nil end
  for _, d in ipairs(X.BUFF_DEFS or {}) do
    if d.groupCast then
      local cn = d.id and SpellName(d.id, d.name) or d.name
      if cn == spell then return SpellName(d.groupCast[1], d.groupCast[2]), d.groupCast[1] end
    end
  end
  for _, b in pairs(X.BLESSINGS or {}) do
    if b.greater and SpellName(b.id, b.name) == spell then
      return SpellName(b.greater[1], b.greater[2]), b.greater[1], true
    end
  end
  local cg = db and db.customGroup and db.customGroup[spell]
  if cg then return cg end
  return nil
end
X.GroupSpellFor = GroupSpellFor

local reagents = {}
local function ReagentCount(item, cache)
  cache = cache or reagents
  local cached = cache[item]
  if cached ~= nil then return cached end
  local api = _G.C_Item and _G.C_Item.GetItemCount or _G.GetItemCount
  local count = X.ReadUnitNumber(api, item, false, false, false, false)
  cache[item] = count and count >= 0 and count or false
  return cache[item]
end

function X.InvalidateReagents()
  wipe(reagents)
end

local function UnitClassFile(unit)
  local ok, _, class = pcall(UnitClass, unit)
  return ok and SafeString(class)
end

-- A responsibility limits our queue. It is separate from the recipient's
-- saved assignment and from coverage, which always describes the whole group.
function X.SubgroupAllows(key, unit, isGroup)
  local groups = X.subgroupDuties and X.subgroupDuties[key]
  if not groups or not InRaid() then return true end
  local index = tonumber(unit:match("^raid(%d+)$"))
  if not index and _G.UnitInRaid then
    local ok, value = pcall(_G.UnitInRaid, unit)
    if not ok then return false end
    if type(value) == "nil" then return not isGroup end
    if not Readable(value) then return false end
    if type(value) == "number" and value >= 1 and value <= 40 and value == math_floor(value) then index = value end
  end
  local subgroup = index and X.RaidSubgroup(index)
  return subgroup ~= nil and groups[subgroup] == true
end

function X.SubgroupBuffKey(spell)
  for _, buff in ipairs(myBuffs) do
    if buff.name == spell and not buff.self then return buff.key end
  end
  for _, blessing in pairs(blessKnown) do
    if blessing.name == spell then return "BLESSINGS" end
  end
end

function X.FilterSubgroupDuties(unit, isGroup, spells, out)
  wipe(out)
  for _, spell in ipairs(spells) do
    local key = X.SubgroupBuffKey(spell)
    if not key or X.SubgroupAllows(key, unit, isGroup) then
      out[#out + 1] = spell
    end
  end
  return out
end

function X.SubgroupDutyOptions()
  local options = {}
  if not CLASSIC_FEATURES then return options end
  for _, buff in ipairs(myBuffs) do
    if not buff.self then options[#options + 1] = { key = buff.key, name = buff.name } end
  end
  if X.HasKnownBlessings() then options[#options + 1] = { key = "BLESSINGS", name = L["Blessings"] } end
  table_sort(options, function(a, b)
    if a.name == b.name then return a.key < b.key end
    return a.name < b.name
  end)
  return options
end

function X.GetSubgroupDuty(key)
  local groups = type(key) == "string" and Readable(key) and X.subgroupDuties and X.subgroupDuties[key]
  if not groups then return nil end
  local copy = {}
  for id in pairs(groups) do copy[id] = true end
  return copy
end

do
  local function KnownSubgroupKey(key)
    if type(key) ~= "string" or not Readable(key) then return false end
    if key == "BLESSINGS" then return X.HasKnownBlessings() end
    for _, buff in ipairs(myBuffs) do
      if buff.key == key and not buff.self then return true end
    end
    return false
  end

  function X.CanEditSubgroupDuty(key, groups)
    if not CLASSIC_FEATURES or not db or not InRaid() or InCombatLockdown() or X.PlayerSuspended()
      or not KnownSubgroupKey(key) then return false end
    if type(groups) == "nil" then return true end
    if type(groups) ~= "table" or not Readable(groups) then return false end
    for id, selected in pairs(groups) do
      if type(id) ~= "number" or not Readable(id) or id < 1 or id > 8 or id ~= math_floor(id)
        or type(selected) ~= "boolean" or not Readable(selected) or not selected then return false end
    end
    return true
  end

  function X.SetSubgroupDuty(key, groups)
    if not X.CanEditSubgroupDuty(key, groups) then return false end
    local copy
    if groups then
      copy = {}
      for id in pairs(groups) do copy[id] = true end
    end
    X.subgroupDuties = X.subgroupDuties or {}
    X.subgroupDuties[key] = copy
    X.assignmentGroupConflicts = nil
    X.Refresh()
    if X.QueueSubgroupDutyRefresh then X.QueueSubgroupDutyRefresh(key) end
    return true
  end

  X.KnownSubgroupKey = KnownSubgroupKey
end

function X.SubgroupDutyCommand(input)
  if not CLASSIC_FEATURES then return end
  if InCombatLockdown() or X.PlayerSuspended() then return end
  local key, selection = input:upper():match("^%s*(%S+)%s+(%S+)%s*$")
  if input:match("^%s*$") then
    local lines = {}
    for buffKey, groups in pairs(X.subgroupDuties or {}) do
      local selected = {}
      for i = 1, 8 do if groups[i] then selected[#selected + 1] = i end end
      lines[#lines + 1] = buffKey .. " · " .. (#selected > 0 and table.concat(selected, ", ") or L["None"])
    end
    table_sort(lines)
    if #lines == 0 then Print(L["No subgroup responsibilities."]) end
    for _, line in ipairs(lines) do Print(line) end
    local keys = {}
    for _, buff in ipairs(myBuffs) do if not buff.self then keys[#keys + 1] = buff.key end end
    if X.HasKnownBlessings() then keys[#keys + 1] = "BLESSINGS" end
    table_sort(keys)
    if #keys > 0 then Print(string_format(L["Available Buff Keys: %s"], table.concat(keys, ", "))) end
    return
  end
  if not X.KnownSubgroupKey(key) or not selection or not InRaid() then
    Print(L["In a raid, use /br subgroup BUFF 1,2,3 or ALL or NONE."])
    return
  end
  local groups, valid = X.Settings.ParseSubgroups(selection)
  if not valid then Print(L["Use subgroup numbers 1 to 8, separated by commas."]); return end
  if X.SetSubgroupDuty(key, groups) then Print(string_format(L["Subgroup responsibility updated for %s."], key)) end
end

local function AddGroupBlocker(report, member, blocker)
  if not report.first then report.first = blocker end
  local ok, guid = pcall(UnitGUID, member)
  local key = ok and Readable(guid) and type(guid) == "string" and guid ~= "" and guid or member
  if report.seen[key] then return end
  report.seen[key] = true
  report.members[#report.members + 1] = blocker
  blocker.memberKey = key
  if key ~= member then blocker.guid = key end
end

-- Broad spells use single-target fallback if the observed affected roster
-- includes someone excluded by an assignment.
local function GroupAssignmentConflict(spell, groupSpell, unit, greater, baseID, cache)
  if not X.AssignmentEnabled() or not next(db.buffAssignments) then return false end
  if not baseID or not (X.IsSelf(unit) or unit:match("^party%d+$") or unit:match("^raid%d+$")) then
    return { first = { kind = "scope", spell = groupSpell, single = spell }, members = {} }
  end
  local targetClass = greater and UnitClassFile(unit)
  if greater and not targetClass then
    return { first = { kind = "roster", spell = groupSpell, single = spell }, members = {}, incomplete = true }
  end
  local scope = targetClass and spell .. ":" .. targetClass or spell
  cache = cache or X.assignmentGroupConflicts
  if cache and cache[scope] ~= nil then return cache[scope] end
  local buffKey
  if not greater then
    for _, buff in ipairs(myBuffs) do
      if buff.name == spell and not buff.custom then buffKey = buff.key; break end
    end
    if not buffKey then return { first = { kind = "scope", spell = groupSpell, single = spell }, members = {} } end
  end
  local report = { members = {}, seen = {} }
  local rosterCount = 0
  X.ForReportRoster(function(member, exists)
    rosterCount = rosterCount + 1
    if exists and X.IsSelf(member) then return end
    local class = exists and UnitClassFile(member)
    if not class then
      report.incomplete = true
      if not report.first then report.first = { kind = "roster", spell = groupSpell, single = spell } end
      return
    end
    if greater and class ~= targetClass then return end
    local assignment, source, role, _, manual = X.AssignmentForUnit(class, member, true, false)
    if assignment == nil then return end
    local kind, blessing
    if greater then
      local selected, owner = X.BlessingForClass(class, member, assignment)
      if selected and selected.name == spell then return end
      kind, blessing = owner, selected and selected.name
    elseif assignment and assignment[buffKey] then
      return
    end
    AddGroupBlocker(report, member, { kind = kind or "rule", spell = groupSpell, single = spell,
      name = Ignore.UnitNames(member), rule = X.AssignmentRuleText(class, role, source, assignment, true, manual),
      blessing = blessing, class = class, slot = source })
  end)
  local conflict = false
  if report.first then
    local size = X.ReadUnitNumber(GetNumGroupMembers)
    if size and rosterCount < size then report.incomplete = true end
    conflict = report
  end
  if cache then cache[scope] = conflict end
  return conflict
end

function X.GroupBlockersFor(spell, name, unit, greater, baseID, preview)
  local draft = preview and preview.subgroupDuty
  if InRaid() and (draft or X.subgroupDuties and next(X.subgroupDuties)) then
    local key = X.SubgroupBuffKey(spell)
    local groups = key and X.subgroupDuties and X.subgroupDuties[key]
    if draft and draft.key == key then groups = draft.groups end
    if groups then
      local targetClass = greater and UnitClassFile(unit)
      local cache = draft and draft.key == key and draft.scopes
      local scope = targetClass or (greater and "unknown" or "raid")
      local cached = cache and cache[scope]
      local blocked, unknown
      if cached then
        blocked, unknown = cached.blocked, cached.unknown
      else
        unknown = greater and not targetClass
        local count = 0
        X.ForReportRoster(function(member, exists)
          if not exists then unknown = true; return end
          count = count + 1
          local class = greater and UnitClassFile(member)
          if not greater or not class or class == targetClass then
            local subgroup = X.RaidSubgroup(tonumber(member:match("^raid(%d+)$")))
            if not subgroup then unknown = true
            elseif not groups[subgroup] then blocked = true end
          end
        end)
        if count ~= X.ReadUnitNumber(GetNumGroupMembers) then unknown = true end
        if cache then cache[scope] = { blocked = blocked, unknown = unknown } end
      end
      if blocked or unknown then
        local kind = blocked and "subgroup" or "roster"
        return { first = { kind = kind, spell = name, single = spell }, members = {}, incomplete = unknown }, "subgroup"
      end
    end
  end
  local blocker = GroupAssignmentConflict(spell, name, unit, greater, baseID, preview and preview.conflicts)
  if greater and X.blessingExceptions and next(X.blessingExceptions) then
    local class = UnitClassFile(unit)
    local report = { first = blocker and blocker.first, members = {}, seen = {}, incomplete = blocker and blocker.incomplete }
    local rosterCount = 0
    if blocker then
      for _, member in ipairs(blocker.members) do
        report.members[#report.members + 1] = member
        report.seen[member.memberKey] = true
      end
    end
    X.ForReportRoster(function(member, exists)
      rosterCount = rosterCount + 1
      local memberClass = exists and UnitClassFile(member)
      if not memberClass then report.incomplete = true end
      if not exists or memberClass ~= class then return end
      local ok, guid = pcall(UnitGUID, member)
      local key = ok and SafeString(guid)
      if not key or key == "" then report.incomplete = true end
      local exception = key and X.blessingExceptions[key]
      local blessing = exception and blessKnown[exception]
      if blessing and (member == unit or blessing.name ~= spell) then
        AddGroupBlocker(report, member, { kind = "exception", spell = name, single = spell,
          name = Ignore.UnitNames(member), blessing = blessing.name, class = memberClass })
      end
    end)
    if report.first then
      local size = X.ReadUnitNumber(GetNumGroupMembers)
      if size and rosterCount < size then report.incomplete = true end
      return report, blocker and "assignment" or "exception"
    end
  end
  if blocker then return blocker, "assignment" end
end

-- Reapplied per roster/scan, shared by automatic, modifier and keybind offers.
function X.GroupOffer(spell, unit, preview)
  if not CLASSIC_FEATURES then return nil end
  local name, baseID, greater = GroupSpellFor(spell)
  if not name then return nil end
  local raid = InRaid()
  local valid, isSelf = Valid(unit)
  if not valid or not X.UnitGUIDOf(unit) or (not isSelf and not (InGroup()
      and (raid and unit:match("^raid%d+$") or not raid and unit:match("^party[1-4]$")))) then
    return nil, nil, nil, "target"
  end
  local list = ranks[name]
  local pick = X.BindingRank(name, unit, X.ReadUnitNumber(UnitLevel, unit), db.castMethod)
  if pick == false or (not known[name] and not (baseID and (X.ReadUnitBool(_G.IsPlayerSpell, baseID)
      or X.ReadUnitBool(_G.IsSpellKnown, baseID)))) then return nil end
  if not preview and OnCooldown(name) then return nil end
  if not preview and not X.GroupSpellInRange(name, unit, isSelf) then
    return nil, nil, nil, "range"
  end
  local blocker, reason = X.GroupBlockersFor(spell, name, unit, greater, baseID, preview)
  if blocker then return nil, nil, nil, reason, nil, blocker end
  local exact = db.castMethod ~= "macro" and pick
  local item = X.groupReagents[(exact and exact.id) or (list and list[#list].id) or baseID]
  local count = item and ReagentCount(item, preview and preview.reagents)
  if count == false or count == 0 then return nil, item, count, "reagent" end
  return name, item, count, nil, greater
end

local function ReagentName(item)
  local api = (_G.C_Item and _G.C_Item.GetItemNameByID) or _G.GetItemInfo
  if api then
    local ok, name = pcall(api, item)
    if ok and type(name) == "string" and Readable(name) and name ~= "" then return name end
  end
  return tostring(item)
end

local function GroupBlockerText(blocker)
  local name = blocker.name and blocker.name ~= "" and blocker.name or L["A group member"]
  if blocker.kind == "subgroup" then
    return string_format(L["%s could reach a subgroup outside your responsibility."], blocker.spell)
  elseif blocker.kind == "roster" then
    return string_format(L["%s could not be verified because roster information is unavailable."], blocker.spell)
  elseif blocker.kind == "scope" then
    return string_format(L["%s could not be verified because its group coverage is unknown."], blocker.spell)
  elseif blocker.kind == "exception" then
    return string_format(L["%s conflicts with %s's individual blessing exception (%s)."],
      blocker.spell, name, blocker.blessing or blocker.single)
  elseif blocker.kind == "other" then
    return string_format(L["%s is blocked because %s's blessing is assigned to another Paladin."], blocker.spell, name)
  elseif blocker.kind == "plan" then
    return string_format(L["%s is blocked because %s has a different group-plan blessing (%s)."],
      blocker.spell, name, blocker.blessing or L["Rule unavailable"])
  else
    return string_format(L["%s would reach %s, whose assignment excludes %s (%s)."],
      blocker.spell, name, blocker.single, blocker.rule)
  end
end

function X.GroupOfferReason(item, count, reason, blockers, compact)
  if reason == "target" then return L["No eligible group target."] end
  if reason == "range" then return L["Group spell range could not be confirmed."] end
  if blockers then
    local first, total = blockers.first, #blockers.members
    local text
    if compact and total > 0 then
      local template = total == 1 and L["%s is blocked by %d group member."]
        or L["%s is blocked by %d group members."]
      text = string_format(template, first.spell, total)
      if blockers.incomplete then
        text = text .. " " .. L["The blocker list may be incomplete because some roster information is unavailable."]
      end
      if first.kind == "scope" then text = text .. " " .. GroupBlockerText(first) end
    else
      text = GroupBlockerText(first)
    end
    return text .. " " .. string_format(L["Using %s on one player instead."], first.single)
  end
  if reason == "assignment" then return L["Group buff would conflict with an assignment."] end
  if reason == "exception" then return L["Group blessing would conflict with a player exception."] end
  if reason == "reagent" then
    return string_format(count == false and L["Could not check reagent: %s."] or L["Missing reagent: %s."],
      ReagentName(item))
  end
end

-- Evaluate the draft with the same range, rank and group checks as the queue.
-- The draft is passed by value for this query, never installed in session state.
function X.PreviewSubgroupDuty(key, groups)
  if not X.CanEditSubgroupDuty(key, groups) then return nil end
  local report = { members = {}, incomplete = false }
  local context = { conflicts = {}, reagents = {}, subgroupDuty = { key = key, groups = groups, scopes = {} } }
  local size = X.ReadUnitNumber(GetNumGroupMembers)
  local seenGUIDs, count, cooldowns = {}, 0, {}
  X.ForReportRoster(function(unit, exists)
    if not exists then report.incomplete = true; return end
    local guid, full, short = X.ReadyIdentity(unit)
    if not guid or guid == "" or seenGUIDs[guid] then report.incomplete = true; return end
    seenGUIDs[guid], count = true, count + 1
    local subgroup = X.RaidSubgroup(tonumber(unit:match("^raid(%d+)$"))) or 0
    local row = { name = full or short or L["Player details unavailable"], subgroup = subgroup }
    if not full or subgroup == 0 then report.incomplete = true end
    if not full or subgroup == 0 and groups then
      row.status = "unknown"
    elseif groups and not groups[subgroup] then
      row.status = "excluded"
    else
      row.status = "eligible"
    end
    report.members[#report.members + 1] = row
    if row.status ~= "eligible" then return end
    local valid, isSelf = Valid(unit)
    if not valid then row.detail = L["Currently ineligible"]; return end
    if Ignore.Has(full, short) or X.SessionHas(full, short) then row.detail = L["Ignored"]; return end
    if X.failedTargets[guid] and X.failedTargets[guid] > GetTime() then
      row.detail = L["Temporarily skipped after a failed cast"]
      return
    end
    local missing, available = {}, {}
    local detail = { subgroupKey = key, cooldown = {}, cooldowns = cooldowns }
    local _, unknown, checked = Missing(unit, missing, true, isSelf, "why", detail)
    local _, _, rangeUnknown, rankLimited = X.FilterInRange(unit, missing, available, isSelf, true)
    if unknown then row.detail = L["Buff information unavailable"]
    elseif rangeUnknown then row.detail = L["Range could not be confirmed"]
    elseif rankLimited then row.detail = L["No eligible rank or range"]
    elseif #missing > #available then row.detail = L["Out of cast range"]
    elseif #detail.cooldown > 0 then row.detail = string_format(L["On cooldown: %s"], table.concat(detail.cooldown, ", "))
    elseif #available == 0 then row.detail = checked and L["No buffs due"] or L["No applicable buffs"] end
    local spell = available[1]
    if spell then
      row.spell = spell
      local offer, item, quantity, reason, _, blockers = X.GroupOffer(spell, unit, context)
      row.group = offer
      row.fallback = X.GroupOfferReason(item, quantity, reason, blockers)
      if not offer and not row.fallback then row.fallback = L["No available group version for this target."] end
    end
  end)
  X.scanUnit = nil
  if count ~= size then report.incomplete = true end
  table_sort(report.members, function(a, b)
    if a.subgroup == b.subgroup then return a.name < b.name end
    if a.subgroup == 0 then return false end
    if b.subgroup == 0 then return true end
    return a.subgroup < b.subgroup
  end)
  return report
end

local function GroupBlockerDetails(blockers, lines, actions, origin)
  local first = blockers.first
  if #blockers.members == 0 or first.kind == "scope" then
    lines[#lines + 1] = GroupBlockerText(first)
  end
  for _, blocker in ipairs(blockers.members) do
    lines[#lines + 1] = GroupBlockerText(blocker)
    if blocker.guid and blocker.name and blocker.name ~= "" then
      if blocker.kind == "rule" and X.ValidAssignmentCell(blocker.class, blocker.slot) then
        actions[#lines] = { kind = "rule", class = blocker.class, slot = blocker.slot, guid = blocker.guid,
          origin = origin, single = blocker.single, baseline = X.GetAssignment(blocker.class, blocker.slot),
          profileRevision = X.blockerProfileRevision }
      elseif blocker.kind == "exception" then
        actions[#lines] = { kind = "exception", guid = blocker.guid, name = blocker.name, class = blocker.class,
          origin = origin, single = blocker.single, baseline = X.blessingExceptions[blocker.guid],
          profileRevision = X.blockerProfileRevision }
      end
    end
  end
  if blockers.incomplete and (#blockers.members > 0 or first.kind ~= "roster") then
    lines[#lines + 1] = L["The blocker list may be incomplete because some roster information is unavailable."]
  end
  lines[#lines + 1] = string_format(L["Using %s on one player instead."], first.single)
end

do
local function SameSnapshot(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for key, value in pairs(a) do
    if not SameSnapshot(value, b[key]) then return false end
  end
  for key in pairs(b) do
    if a[key] == nil then return false end
  end
  return true
end

local function ReviewRoster()
  local raid = InRaid()
  local size = X.ReadUnitNumber(GetNumGroupMembers)
  local incomplete = not size or size < 2 or size > (raid and 40 or 5) or size ~= math_floor(size)
  local roster, count = {}, 0
  X.ForReportRoster(function(unit, exists)
    if not exists then incomplete = true; return end
    local ok, guid = pcall(UnitGUID, unit)
    local class, isSelf = UnitClassFile(unit), X.IsSelf(unit)
    local full, short = Ignore.UnitNames(unit)
    local role, roleReadable = AssignedRole(unit)
    if not ok or not Readable(guid) or type(guid) ~= "string" or guid == "" or roster[guid]
      or not class or isSelf == nil or not full or full == "" then
      incomplete = true
      return
    end
    if not roleReadable then incomplete = true end
    local eligible = Valid(unit) and not Ignore.Has(full, short) and not X.SessionHas(full, short)
    roster[guid] = { unit = unit, guid = guid, name = full, class = class, isSelf = isSelf, role = role,
      manual = X.assignmentRoleOverrides and X.assignmentRoleOverrides[guid], eligible = eligible }
    count = count + 1
  end)
  return roster, incomplete or count ~= size, raid
end

local function StillBlocks(action, origin)
  if not origin.eligible then return false end
  local offers, offered = {}, false
  Missing(origin.unit, offers, true, origin.isSelf, "assignmentReview", { member = origin })
  for _, spell in ipairs(offers) do
    if spell == action.single then offered = true; break end
  end
  if not offered then return false end
  local name, baseID, greater = GroupSpellFor(action.single)
  if not name or (baseID and not known[name] and not X.ReadUnitBool(_G.IsPlayerSpell, baseID)
    and not X.ReadUnitBool(_G.IsSpellKnown, baseID)) then return false end
  local report = X.GroupBlockersFor(action.single, name, origin.unit, greater, baseID, { conflicts = {} })
  for _, blocker in ipairs(report and report.members or {}) do
    if blocker.kind == action.kind and blocker.guid == action.guid and blocker.class == action.class
      and (action.kind ~= "rule" or blocker.slot == action.slot) then return true end
  end
  return false
end

local function AddedOffers(before, after)
  local prior, added = {}, {}
  for _, spell in ipairs(before) do prior[spell] = true end
  for _, spell in ipairs(after) do
    if not prior[spell] then
      added[#added + 1] = spell
      prior[spell] = true
    end
  end
  return added
end

-- Compare assignment offers before aura, range, and cooldown checks so those
-- transient states cannot be mistaken for a buff gained or lost by an edit.
function X.ReviewBlockerEdit(action, value)
  if not CLASSIC_FEATURES or not db or not InGroup() or InCombatLockdown() or X.PlayerSuspended()
    or type(action) ~= "table" or action.profileRevision ~= X.blockerProfileRevision
    or type(action.guid) ~= "string" or not Readable(action.guid) or action.guid == ""
    or type(action.origin) ~= "string" or not Readable(action.origin) or action.origin == ""
    or type(action.single) ~= "string" or not Readable(action.single) or action.single == ""
    or type(action.class) ~= "string" or not Readable(action.class) then return nil end
  local proposal = { kind = action.kind, class = action.class, slot = action.slot, guid = action.guid }
  if action.kind == "rule" then
    if not X.AssignmentEnabled() or type(action.slot) ~= "string" or not Readable(action.slot)
      or not X.ValidAssignmentCell(action.class, action.slot)
      or not SameSnapshot(action.baseline, X.GetAssignment(action.class, action.slot)) then return nil end
    proposal.value = X.CopyAssignment(value)
    if type(value) ~= "nil" and proposal.value == nil then return nil end
  elseif action.kind == "exception" then
    local key = X.blessingExceptions and X.blessingExceptions[action.guid]
    local plan = X.blessPlan[action.class]
    if not key or action.baseline ~= key or not Readable(value) or type(value) ~= "string"
      or (value ~= "DEFAULT" and (not blessKnown[value] or (plan and not plan.mine))) then return nil end
    if value ~= "DEFAULT" then proposal.value = value end
  else
    return nil
  end

  local roster, incomplete, raid = ReviewRoster()
  local target, origin = roster[action.guid], roster[action.origin]
  if target and target.class ~= action.class then return nil end
  if not incomplete and (not target or not origin or not StillBlocks(action, origin)) then return nil end
  local review = { action = action, proposal = proposal, incomplete = incomplete, rows = {},
    state = { raid = raid, spec = X.spec, members = {} } }
  for guid, member in pairs(roster) do
    local before, after = {}, {}
    if member.eligible then
      Missing(member.unit, before, true, member.isSelf, "assignmentReview", { member = member })
      Missing(member.unit, after, true, member.isSelf, "assignmentReview", { member = member, proposal = proposal })
    end
    local assignment, source = X.AssignmentForUnit(member.class, member.unit, true, member.isSelf, nil, member)
    local plan = X.blessPlan[member.class]
    review.state.members[guid] = { class = member.class, name = member.name, isSelf = member.isSelf,
      role = member.role, manual = member.manual, eligible = member.eligible, source = source,
      assignment = X.CopyAssignment(assignment), plan = plan and { key = plan.key, name = plan.name, mine = plan.mine },
      exception = X.blessingExceptions and X.blessingExceptions[guid], before = before, after = after }
    local gains, losses = AddedOffers(before, after), AddedOffers(after, before)
    if #gains > 0 or #losses > 0 then
      review.rows[#review.rows + 1] = { name = member.name, gains = gains, losses = losses }
    end
  end
  table_sort(review.rows, function(a, b) return a.name < b.name end)
  return review
end

-- Configured-rule copies have their own bounded review, never blocker undo.
do
  local A, serial, pending = {}, 0, nil
  X.AssignmentCopy=A
  local function Ready()
    if not CLASSIC_FEATURES or not db then return false,"unavailable" end
    local state=X.Settings.SaveState();if state then return false,state end
    if InCombatLockdown() or X.PlayerSuspended() then return false,"combat" end
    return true
  end
  local function Selector(kind,value)
    local copy=X.Recovery.Copy(value)
    if type(copy)~="table" or type(copy.class)~="string" or not X.ValidAssignmentCell(copy.class,"ALL") then return end
    for key in pairs(copy) do if key~="class" and (kind~="cell" or key~="slot") then return end end
    if kind=="cell" and not X.ValidAssignmentCell(copy.class,copy.slot) then return end
    return {class=copy.class,slot=copy.slot}
  end
  local function Row(class)
    local row=db.buffAssignments[class] or {}
    local copied=X.Recovery.Copy(row)
    if not copied then return end
    for slot,value in pairs(copied) do
      if not X.ValidAssignmentCell(class,slot) or not SameSnapshot(value,X.CopyAssignment(value)) then return end
    end
    return copied
  end
  local function ValueKind(value) return value==nil and "default" or value==false and "none" or "custom" end
  local function Build(kind,source,dest)
    local sourceRow,destRow=Row(source.class),Row(dest.class)
    if not sourceRow or not destRow then return nil,"invalid" end
    local changes={}
    local slots=kind=="cell" and {dest.slot} or X.ASSIGNMENT_SLOTS
    for _,slot in ipairs(slots) do
      local before=destRow[slot]
      local after
      if kind=="cell" then after=sourceRow[source.slot] else after=sourceRow[slot] end
      if not SameSnapshot(before,after) then
        changes[#changes+1]={class=dest.class,slot=slot,before=X.CopyAssignment(before),after=X.CopyAssignment(after),
          beforeKind=ValueKind(before),afterKind=ValueKind(after)}
      end
    end
    local proposal
    if kind=="cell" then proposal={kind="rule",class=dest.class,slot=dest.slot,value=sourceRow[source.slot]}
    else proposal={kind="row",class=dest.class,values=sourceRow} end
    local roster,incomplete,raid={},false,false
    if InGroup() then roster,incomplete,raid=ReviewRoster() end
    local rows,state={}, {group=InGroup(),raid=raid,spec=X.spec,enabled=db.assignmentEnabled,
      revision=X.blockerProfileRevision,members={}}
    for guid,member in pairs(roster) do
      local before,after={},{}
      if member.eligible then
        Missing(member.unit,before,true,member.isSelf,"assignmentReview",{member=member})
        Missing(member.unit,after,true,member.isSelf,"assignmentReview",{member=member,proposal=proposal})
      end
      state.members[guid]={unit=member.unit,name=member.name,class=member.class,role=member.role,
        manual=member.manual,eligible=member.eligible,isSelf=member.isSelf,before=before,after=after,
        plan=X.blessPlan[member.class],exception=X.blessingExceptions and X.blessingExceptions[guid]}
      local gains,losses=AddedOffers(before,after),AddedOffers(after,before)
      if #gains>0 or #losses>0 then rows[#rows+1]={name=member.name,gains=gains,losses=losses} end
    end
    table_sort(rows,function(a,b) return a.name<b.name end)
    local model={kind=kind,source=source,dest=dest,changes=changes,rows=rows,incomplete=incomplete}
    local copied=X.Recovery.Copy({sourceRow=sourceRow,destRow=destRow,state=state,model=model})
    if not copied then return nil,"limit" end
    return copied
  end
  function A.Stage(kind,source,dest)
    local ready,why=Ready();if not ready then return nil,why end
    if kind~="cell" and kind~="row" then return nil,"invalid" end
    source,dest=Selector(kind,source),Selector(kind,dest)
    if not source or not dest then return nil,"invalid" end
    local owned,reason=Build(kind,source,dest)
    if not owned then return nil,reason end
    serial=serial+1;owned.model.id=serial
    owned.db,owned.generation=db,X.Preferences.Generation()
    pending=owned
    return X.Recovery.Copy(owned.model)
  end
  function A.Review(draft)
    local ready,why=Ready();if not ready then return nil,why end
    if type(draft)~="table" or not pending or not Readable(draft.id) or draft.id~=pending.model.id then return nil,"invalid" end
    if pending.db~=db or pending.generation~=X.Preferences.Generation() then return nil,"generation" end
    local old=pending.model
    local current,reason=Build(old.kind,old.source,old.dest)
    if not current then return nil,reason end
    if current.model.incomplete then return nil,"unavailable" end
    if not SameSnapshot(current.sourceRow,pending.sourceRow) or not SameSnapshot(current.destRow,pending.destRow)
      or not SameSnapshot(current.state,pending.state) then return nil,"conflict" end
    return X.Recovery.Copy(old)
  end
  function A.Apply(draft)
    local reviewed,why=A.Review(draft);if not reviewed then return false,why end
    local model=pending.model
    local nextMap=X.Recovery.Copy(db.buffAssignments)
    if not nextMap then return false,"limit" end
    local row=nextMap[model.dest.class] or {}
    for _,change in ipairs(model.changes) do row[change.slot]=X.CopyAssignment(change.after) end
    nextMap[model.dest.class]=next(row) and row or nil
    if not SameSnapshot(nextMap,X.CopyAssignments(nextMap)) then return false,"invalid" end
    if #model.changes==0 then pending=nil;return true end
    local oldMap,oldUndo,oldRevision,oldConflicts=db.buffAssignments,X.blockerUndo,X.blockerProfileRevision,X.assignmentGroupConflicts
    db.buffAssignments=nextMap
    X.blockerUndo,X.assignmentGroupConflicts=nil,nil
    X.blockerProfileRevision=(X.blockerProfileRevision or 0)+1
    local ok=pcall(X.SettingsChanged,{buffAssignments=true,profile=true})
    if not ok then
      db.buffAssignments,X.blockerUndo,X.blockerProfileRevision,X.assignmentGroupConflicts=oldMap,oldUndo,oldRevision,oldConflicts
      pcall(X.SettingsChanged,{profile=true});return false,"invalid"
    end
    pending=nil;return true
  end
  X.OnDBLoaded(function() pending=nil end)
end

function X.ApplyBlockerEdit(action, value, previous)
  if not previous or previous.action ~= action or previous.incomplete then return false end
  local fresh = X.ReviewBlockerEdit(action, value)
  if not fresh then return false end
  if fresh.incomplete or not SameSnapshot(previous.proposal, fresh.proposal)
    or not SameSnapshot(previous.state, fresh.state) then return false, fresh end
  if InCombatLockdown() or X.PlayerSuspended() then return false end
  local prior, applied = action.baseline
  local after = fresh.proposal.value
  if SameSnapshot(prior, after) then return true end
  if action.kind == "rule" then applied = X.SetAssignment(action.class, action.slot, after)
  else applied = X.SetBlessingExceptionForGUID(action.guid, after or "DEFAULT") ~= nil end
  if applied then
    X.blockerUndo = { kind = action.kind, guid = action.guid, class = action.class, slot = action.slot,
      revision = X.blockerProfileRevision, prior = prior, after = after }
  end
  return applied
end

function X.UndoBlockerEdit()
  if not CLASSIC_FEATURES or not db or InCombatLockdown() or X.PlayerSuspended() then return end
  local undo = X.blockerUndo
  if not undo then return false, "There is no blocker edit to undo." end
  local function expired()
    X.blockerUndo = nil
    return false, "The blocker edit can no longer be undone."
  end
  if not InGroup() or undo.revision ~= X.blockerProfileRevision then return expired() end
  local roster, incomplete = ReviewRoster()
  if incomplete then return false, "The group could not be checked. Try Undo again when roster information is available." end
  local member = roster[undo.guid]
  if not member or member.class ~= undo.class then return expired() end
  local applied
  if undo.kind == "rule" then
    if not X.AssignmentEnabled() or not SameSnapshot(undo.after, X.GetAssignment(undo.class, undo.slot)) then
      return expired()
    end
    applied = X.SetAssignment(undo.class, undo.slot, undo.prior)
  else
    local current = X.blessingExceptions and X.blessingExceptions[undo.guid]
    if current ~= undo.after then return expired() end
    applied = X.SetBlessingExceptionForGUID(undo.guid, undo.prior or "DEFAULT", true) ~= nil
  end
  if not applied then return expired() end
  X.blockerUndo = nil
  return true, "The last blocker edit was undone."
end

function X.PruneBlockerUndo()
  local undo = X.blockerUndo
  if not undo or InCombatLockdown() or X.PlayerSuspended() then return end
  if not InGroup() then X.blockerUndo = nil; return end
  local roster, incomplete = ReviewRoster()
  if not incomplete and not roster[undo.guid] then X.blockerUndo = nil end
end
end

-- Out-of-combat snapshot, separate from the live queue and secure cast rows.
function X.AssignmentPreview()
  local members = {}
  if not CLASSIC_FEATURES or not db or not InGroup() or InCombatLockdown() or X.PlayerSuspended() then return members end
  local cooldowns, groupPreview = {}, { conflicts = {}, reagents = {} }
  local size = X.ReadUnitNumber(GetNumGroupMembers)
  local limit = size and size > 0 and math_floor(size) - (InRaid() and 0 or 1) or nil
  X.ForReportRoster(function(unit, exists)
    local guid, full, short
    if exists then guid, full, short = X.ReadyIdentity(unit) end
    local row = { name = full or short or L["Player details unavailable"], identity = guid,
      buffs = {}, available = {} }
    if full then
      row.unit = unit
      row.guid, row.roleOverride, row.roleEditable, row.roleCanSet = X.AssignmentRoleEditorState(unit, exists)
    end
    members[#members + 1] = row
    local valid, isSelf = Valid(unit)
    if not exists or not guid or not full then
      row.rule, row.status = L["Rule unavailable"], L["Player details unavailable"]
    elseif not valid or Ignore.Has(full, short) or X.SessionHas(full, short) then
      local class = UnitClassFile(unit)
      local assignment, source, role, _, manual = X.AssignmentForUnit(class, unit, true, X.IsSelf(unit))
      row.rule = X.AssignmentRuleText(class, role, source, assignment, true, manual)
      row.status = valid and L["Ignored"] or L["Currently ineligible"]
    else
      local detail = { cooldown = {}, cooldowns = cooldowns }
      local _, unknown = Missing(unit, row.buffs, true, isSelf, "why", detail)
      row.evaluated, row.unknown = true, unknown
      row.rule = detail.rule
      local _, _, rangeUnknown, rankLimited = X.FilterInRange(unit, row.buffs, row.available, isSelf, true)
      if X.failedTargets[guid] and X.failedTargets[guid] > GetTime() then
        row.status = L["Temporarily skipped after a failed cast"]
        wipe(row.available)
      elseif unknown then row.status = L["Buff information unavailable"]
      elseif rangeUnknown then row.status = L["Range could not be confirmed"]
      elseif rankLimited then row.status = L["No eligible rank or range"]
      elseif #row.buffs > #row.available then row.status = L["Out of cast range"] end
      if #detail.cooldown > 0 then
        local note = string_format(L["On cooldown: %s"], table.concat(detail.cooldown, ", "))
        row.status = row.status and row.status .. " · " .. note or note
        for _, spell in ipairs(detail.cooldown) do row.buffs[#row.buffs + 1] = spell end
      end
      if detail.blessing then row.rule = row.rule .. " · " .. detail.blessing end
      local group, details, actions = {}, {}, {}
      for _, spell in ipairs(row.available) do
        local offer, item, count, reason, _, blocker = X.GroupOffer(spell, unit, groupPreview)
        local text = X.GroupOfferReason(item, count, reason, blocker, true)
        if blocker then GroupBlockerDetails(blocker, details, actions, guid) end
        if offer then group[#group + 1] = string_format(L["Group option: %s"], offer)
        elseif text then group[#group + 1] = blocker and text or spell .. " · " .. text end
      end
      if #group > 0 then row.group = table.concat(group, " · ") end
      if #details > 0 then row.groupDetails, row.groupActions = details, actions end
    end
  end, limit)
  -- The index fallback is a one-unit scratch buffer. Invalidate it after
  -- reading a roster so later live scans rebuild it for their own unit.
  X.scanUnit = nil
  return members
end

-- Estimate reagent use for eligible group spells independently of the automatic
-- group-cast minimum. Ordinary group versions share a spell scope; Greater
-- Blessings consume a reagent per spell and recipient class.
function X.ReagentEstimate(report)
  if not CLASSIC_FEATURES or not report then return {}, false end
  local preview = { conflicts = {}, reagents = {} }
  local needed, scopes, unclassified = {}, {}, false
  for _, person in ipairs(report.people) do
    for _, spell in ipairs(person.buffs) do
      local name, _, greater = GroupSpellFor(spell)
      if name then
        local offer, item, _, reason, _, blocker = X.GroupOffer(spell, person.unit, preview)
        local class = not greater and "" or UnitClassFile(person.unit)
        if item and class then
          local scope = name .. ":" .. class
          if scopes[scope] == nil then scopes[scope] = item
          elseif scopes[scope] ~= item then scopes[scope] = false; unclassified = true end
        elseif offer or (blocker and blocker.incomplete) or (not class and reason ~= "exception") then
          unclassified = true
        end
      end
    end
  end
  for _, item in pairs(scopes) do
    if item then needed[item] = (needed[item] or 0) + 1 end
  end
  local rows = {}
  for item, amount in pairs(needed) do
    local count = ReagentCount(item, preview.reagents)
    rows[#rows + 1] = { name = ReagentName(item), item = item,
      carried = count ~= false and count or nil, needed = amount }
  end
  table_sort(rows, function(a, b)
    if a.name == b.name then return a.item < b.item end
    return a.name < b.name
  end)
  return rows, unclassified or report.unknown > 0
end

function X.ReagentSummary(report)
  local rows, incomplete = X.ReagentEstimate(report)
  if #rows == 0 and not incomplete then return nil end
  local parts = {}
  for _, row in ipairs(rows) do
    parts[#parts + 1] = string_format("%s %s/%d", row.name, row.carried or "?", row.needed)
  end
  table_sort(parts)
  if incomplete then parts[#parts + 1] = L["some needs unknown"] end
  return string_format(L["Estimated group reagents (carried/needed): %s"], table.concat(parts, ", "))
end

local function MacroArgument(value)
  return type(value) == "string" and Readable(value) and value:find("%S") and not value:find("[%c;%[%]|]")
end

local function ExactCastName(unit)
  if CLASSIC_FEATURES then
    -- On Forever the second return is a surname, not a realm. Use the
    -- unmodified name for targeting, not a shortened name from the list.
    local ok, first, surname = pcall(_G.UnitNameUnmodified or UnitName, unit)
    if not ok or not MacroArgument(first) then return nil end
    if type(surname) == "nil" then return first end
    if not Readable(surname) then return nil end
    if surname == "" then return first end
    local constants = _G.Constants and _G.Constants.CharacterNameSeparatorConsts
    local separator = constants and constants.CHARACTERNAME_SURNAME_SEPARATOR or " "
    if MacroArgument(surname) then return first .. separator .. surname end
    return nil
  end
  local ok, full = pcall(GetUnitName or UnitName, unit, true)
  if ok and MacroArgument(full) then return full end
end

function X.NeedsExactTarget(unit, isSelf, method)
  return method == "target" and not isSelf and unit ~= "pet" and not unit:match("^party[1-4]$")
    and not unit:match("^raid%d+$") and not unit:match("^partypet[1-4]$") and not unit:match("^raidpet%d+$")
end

local function ExactCastMacro(name, text, hadTarget)
  if not MacroArgument(text) then return nil end
  -- A failed /targetexact must not leave a friendly previous target (or
  -- auto-self-cast) eligible. Restore the target, or the lack of one.
  local macro = "/cleartarget\n/targetexact " .. name .. "\n/cast [help,nodead] " .. text
    .. (hadTarget and "\n/targetlasttarget" or "\n/cleartarget")
  if #macro <= 255 then return macro end
end

function X.ExactCastBody(unit, text, shifted, hadTarget)
  local name = ExactCastName(unit)
  if name then
    return ExactCastMacro(name, text, hadTarget), shifted and ExactCastMacro(name, shifted, hadTarget)
  end
end

local function UnitCastMacro(unit, text)
  if MacroArgument(text) then
    local macro = "/cast [@" .. unit .. ",help,nodead] " .. text
    if #macro <= 255 then return macro end
  end
end

function Bind(btn, unit, spell, isSelf, pick, gspell, gpick, hadTarget)
  btn:SetAttribute("shift-type1", nil)
  btn:SetAttribute("shift-spell1", nil)
  btn:SetAttribute("shift-unit1", nil)
  btn:SetAttribute("shift-macrotext1", nil)
  local method = db.castMethod
  if method == "target" then
    -- Self, party/raid and pet casts use their unit tokens directly, so
    -- your target never changes and a pet does not need a unique name.
    -- Anyone else -- nameplate, target or mouseover units, which can point at
    -- a different player by the time you click -- uses BuffYou's approach
    -- (MIT, by datdata): target them by exact name, cast the buff,
    -- then restore your previous target.
    -- PreClick checks the live GUID before acting on a reused unit token.
    btn:SetAttribute("type", nil)
    btn:SetAttribute("unit", nil)
    btn:SetAttribute("spell", nil)
    btn:SetAttribute("macrotext", nil)
    if isSelf then
      btn:SetAttribute("type", "spell")
      btn:SetAttribute("spell", (pick and pick.id) or spell)
      btn:SetAttribute("unit", "player")
      if gspell then
        btn:SetAttribute("shift-type1", "spell")
        btn:SetAttribute("shift-spell1", (gpick and gpick.id) or gspell)
        btn:SetAttribute("shift-unit1", "player")
      end
      return
    end
    if not X.NeedsExactTarget(unit, isSelf, method) then
      btn:SetAttribute("type", "spell")
      btn:SetAttribute("spell", (pick and pick.id) or spell)
      btn:SetAttribute("unit", unit)
      if gspell then
        btn:SetAttribute("shift-type1", "spell")
        btn:SetAttribute("shift-spell1", (gpick and gpick.id) or gspell)
        btn:SetAttribute("shift-unit1", unit)
      end
      return
    end
    local macro, shifted = X.ExactCastBody(unit, CastText(spell, pick), gspell and CastText(gspell, gpick), hadTarget)
    if macro then
      btn:SetAttribute("type", "macro")
      btn:SetAttribute("macrotext", macro)
      if shifted then
        btn:SetAttribute("shift-type1", "macro")
        btn:SetAttribute("shift-macrotext1", shifted)
      end
    end
  elseif method == "id" and pick and pick.id then
    btn:SetAttribute("type", "spell")
    btn:SetAttribute("unit", unit)
    btn:SetAttribute("spell", pick.id)
    btn:SetAttribute("macrotext", nil)
    if gspell then
      btn:SetAttribute("shift-type1", "spell")
      btn:SetAttribute("shift-unit1", unit)
      btn:SetAttribute("shift-spell1", (gpick and gpick.id) or gspell)
    end
  else
    local text = UnitCastMacro(unit, method == "rank" and CastText(spell, pick) or spell)
    btn:SetAttribute("type", text and "macro" or nil)
    btn:SetAttribute("unit", nil)
    btn:SetAttribute("spell", nil)
    btn:SetAttribute("macrotext", text)
    local shifted = gspell and UnitCastMacro(unit, method == "rank" and CastText(gspell, gpick) or gspell)
    if text and shifted then
      btn:SetAttribute("shift-type1", "macro")
      btn:SetAttribute("shift-macrotext1", shifted)
    end
  end
end
X.PickRank, X.CastText = PickRank, CastText
end -- Bind block

local MakeMacro  -- defined with the macro helpers below
local QueueRefresh  -- assigned to the event coalescer below
X.lastSoundAt = 0  -- shared with Coordination.lua

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

do
local castTargetFailureGlobals = {
  "SPELL_FAILED_LINE_OF_SIGHT", "ERR_SPELL_FAILED_LINE_OF_SIGHT",
  "SPELL_FAILED_OUT_OF_RANGE", "ERR_OUT_OF_RANGE", "ERR_SPELL_OUT_OF_RANGE",
  "SPELL_FAILED_BAD_TARGETS", "ERR_INVALID_TARGET", "ERR_BADATTACKTARGET",
  "SPELL_FAILED_TARGETS_DEAD", "ERR_TARGET_DEAD",
}
local function IsTargetCastFailure(message)
  if type(message) ~= "string" then return false end
  local lower = message:lower()
  if lower:find("line of sight", 1, true) or lower:find("out of range", 1, true)
    or lower:find("too far away", 1, true) or lower:find("invalid target", 1, true)
    or lower:find("bad target", 1, true) or lower:find("target is dead", 1, true)
    or lower:find("target no longer exists", 1, true) then return true end
  for _, key in ipairs(castTargetFailureGlobals) do
    local token = _G[key]
    if Readable(token) and type(token) == "string" and token ~= "" and message == token then return true end
  end
  return false
end

local pending = {}
local seenCastGUIDs = {}
local dispatch, awaitingSent, rowPress, recentFailure
local traceSequence = 0

local function Trace(label, ...)
  if not db or not db.clickDebug then return end
  traceSequence = traceSequence + 1
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = SafeString((select(i, ...))) or "?" end
  Print(string_format("|cffaaaaaa#%d %.3f %s: %s|r", traceSequence, GetTime(), label, table.concat(parts, ", ")))
end

local function StringField(value)
  if Readable(value) and type(value) == "string" and value ~= "" then return value end
end

local function SpellID(value)
  if Readable(value) and type(value) == "number" and value > 0
      and value < math_huge and value == math_floor(value) then return value end
end

local function CastTargetNames(unit, macro)
  local exact = macro and (macro:match("^/targetexact ([^\r\n]+)") or macro:match("\n/targetexact ([^\r\n]+)"))
  if exact then return exact, exact:lower() end
  -- Forever's NameUtil combines the two character-name fields using the
  -- client's surname separator. Treat the resulting name as an exact alias.
  local nameUtil = _G.NameUtil
  if CLASSIC_FEATURES and nameUtil and nameUtil.FormatUnitNameForDisplay then
    local ok, value = pcall(nameUtil.FormatUnitNameForDisplay, unit, true)
    local display = ok and StringField(value)
    if display then return display, display:lower() end
    return
  end
  local name, realm
  if UnitFullName then
    local ok, short, unitRealm = pcall(UnitFullName, unit)
    if not ok or (type(short) ~= "nil" and not Readable(short))
      or (type(unitRealm) ~= "nil" and not Readable(unitRealm)) then return end
    name, realm = StringField(short), StringField(unitRealm)
  end
  if not name then
    local ok, short = pcall(UnitName, unit)
    if ok then name = StringField(short) end
  end
  if not name then return end
  local localRealm = GetNormalizedRealmName and StringField(GetNormalizedRealmName())
  local full = realm or localRealm
  local preferred
  if GetUnitName then
    local ok, value = pcall(GetUnitName, unit, true)
    if ok then preferred = StringField(value) end
  end
  local localTarget = not realm or (localRealm and realm:lower() == localRealm:lower())
  if preferred and not localTarget and preferred:sub(-#realm - 1):lower() ~= "-" .. realm:lower() then
    preferred = nil
  end
  return preferred or name, full and (name .. "-" .. full):lower() or nil,
    localTarget and name:lower() or nil, preferred and preferred:lower() or nil
end

local successSerial, successObserver, successEpoch = 0, nil, 0
function X.BeginCastClick(btn, button, down, label, barBody)
  local entry = btn.entry
  Trace(label .. " pre", button, down and "down" or "up", entry and entry.missing and entry.missing[1])
  recentFailure = nil
  if dispatch then dispatch.ambiguous = true; return end
  if button ~= "LeftButton" or not db or InCombatLockdown() or X.PlayerSuspended() then
    awaitingSent, rowPress = nil, nil
    return
  end
  local now, isRow = GetTime(), label == "click"
  local previous = isRow and not down and rowPress and rowPress.button == btn and rowPress
  local waiting = awaitingSent and awaitingSent.expires > now and awaitingSent
  rowPress, awaitingSent = nil, nil
  if not entry or not entry.unit or not entry.missing or not entry.missing[1] then return end
  local shift = _G.IsShiftKeyDown and _G.IsShiftKeyDown()
    and not (_G.IsControlKeyDown and _G.IsControlKeyDown())
    and not (_G.IsAltKeyDown and _G.IsAltKeyDown()) and btn:GetAttribute("shift-type1")
  local action = shift or btn:GetAttribute("type")
  if action ~= "spell" and action ~= "macro" then return end
  local guid = entry.castGuid or entry.guid -- folded rows borrow a real recipient
  local ok, currentGUID = pcall(UnitGUID, entry.unit)
  if not guid or not ok or StringField(currentGUID) ~= guid then return end
  local macro = action == "macro" and (barBody or StringField(btn:GetAttribute(shift and "shift-macrotext1" or "macrotext")))
  if action == "macro" and not macro then return end
  local nameOfTarget, full, short, preferred = CastTargetNames(entry.unit, macro)
  if not nameOfTarget then return end
  local name = (shift and btn.bGroupSpell) or btn.bSpell or entry.missing[1]
  local id = SpellID(btn:GetAttribute(shift and "shift-spell1" or "spell"))
  if not id then
    if shift then id = SpellID(btn.bGroupID) else id = SpellID(btn.bActionID) end
  end
  local list = ranks[name]
  if not id and list and list[1] then
    local pick = db.castMethod == "rank" and X.PickRank(name, entry.unit) or list[#list]
    id = pick and SpellID(pick.id)
  end
  if not id and C_Spell and C_Spell.GetSpellIDForSpellIdentifier then
    local resolved, value = pcall(C_Spell.GetSpellIDForSpellIdentifier, name)
    if resolved then id = SpellID(value) end
  end
  local press = previous
  if isRow and down then
    press = { button = btn, guid = guid, id = id, spell = name }
    rowPress = press
  end
  local samePress = previous and previous.guid == guid and previous.id == id and previous.spell == name
  -- A rapid retry for the same recipient and spell is still one identifiable
  -- intent: Forever may emit SENT after PostClick, even after another click.
  local sameIntent = waiting and waiting.guid == guid and waiting.expectedID == id and waiting.spell == name
  local ambiguous = (previous and not samePress)
    or (waiting and not (samePress and waiting.press == previous) and not sameIntent)
  local keyDown = not isRow and GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
  dispatch = { button = btn, spell = name, expectedID = id, guid = guid, who = nameOfTarget,
    source = label == "click" and "row" or label == "bar macro" and "macro" or "binding",
    supportEpoch = successEpoch,
    full = full, short = short, preferred = preferred, terminals = {}, ambiguous = ambiguous,
    press = press, deferred = (isRow or label == "bar macro" or (not not down) == (not not keyDown)) and not entry.pet }
  Trace("expected", name, id, nameOfTarget, guid)
end

local function IsFailedCast(event)
  return event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET"
end

function X.ObserveCastSuccess(observer)
  successEpoch = successEpoch + 1
  successObserver = type(observer) == "function" and observer or nil
  return successSerial
end
function X.CastSuccessSerial() return successSerial end

local function ApplyCast(cast, terminal, targetError)
  if terminal == "UNIT_SPELLCAST_SUCCEEDED" then
    local name = cast.spell
    X.failedTargets[cast.guid] = nil
    X.lastTargetCastProblem = nil
    X.sessionCasts = X.sessionCasts + 1
    db.castsTotal = (db.castsTotal or 0) + 1
    db.stats = db.stats or {}
    if X.Settings.PlainString(name, 128) then
      if X.Settings.CanAdd(db.stats, "stats", name) then db.stats[name] = (db.stats[name] or 0) + 1 end
      if X.Settings.PlainString(cast.who, 128) then
        if #db.history >= 50 then table.remove(db.history, 1) end
        db.history[#db.history + 1] = { t = (time and time()) or 0, spell = name, who = cast.who }
      end
    end
    X.UpdateCounter()
    local key = X.KeyOfName(name)
    if key then X.SyncSend(key, cast.guid) end
    X.queueAt = GetTime()
    Trace("attributed", terminal, cast.sentGUID)
    successSerial = successSerial + 1
    if successObserver and cast.supportEpoch == successEpoch then pcall(successObserver, successSerial, cast.source, cast.sentID) end
  elseif targetError and IsFailedCast(terminal) then
    local expires = GetTime() + 30
    X.failedTargets[cast.guid] = expires
    X.lastTargetCastProblem = { guid = cast.guid, expires = expires, message = targetError }
    Print(cast.who .. ": " .. targetError)
    Trace("target skipped", cast.sentGUID)
    if QueueRefresh then QueueRefresh() end
  end
end

local function ConfirmCast(cast)
  local now = GetTime()
  for i = #seenCastGUIDs, 1, -1 do
    local seenCast = seenCastGUIDs[i]
    if seenCast.expires <= now then
      table.remove(seenCastGUIDs, i)
    elseif seenCast.guid == cast.sentGUID then
      return
    end
  end
  if #seenCastGUIDs == 16 then table.remove(seenCastGUIDs, 1) end
  seenCastGUIDs[#seenCastGUIDs + 1] = { guid = cast.sentGUID, expires = now + 15 }
  local terminal
  for _, outcome in ipairs(cast.terminals) do
    if outcome.guid == cast.sentGUID and outcome.id == cast.sentID then
      terminal = outcome
      break
    end
  end
  if terminal then
    ApplyCast(cast, terminal.event, cast.targetError)
    if terminal.event == "UNIT_SPELLCAST_FAILED" and not cast.hadError and terminal == cast.latestEvent then
      recentFailure = { cast = cast, event = terminal.event, time = terminal.time }
    end
    if terminal.event == "UNIT_SPELLCAST_SUCCEEDED" and QueueRefresh then QueueRefresh() end
    return
  end
  cast.button, cast.terminals = nil, nil
  cast.expires = now + 15
  if #pending == 8 then table.remove(pending, 1) end
  pending[#pending + 1] = cast
end

function X.EndCastClick(btn, button, down, label)
  local cast = dispatch
  Trace(label .. " post", button, down and "down" or "up", cast and cast.sentGUID)
  if not cast or cast.button ~= btn then return end
  dispatch = nil
  if cast.press and (cast.sawSent or cast.hadError or cast.ambiguous) then cast.press.settled = true end
  if cast.sentGUID and not cast.ambiguous and not cast.repeated then
    ConfirmCast(cast)
  elseif cast.deferred and cast.expectedID and not cast.sawSent and not cast.ambiguous and not cast.hadError
      and not (cast.press and cast.press.settled) then
    -- The Forever field trace showed SENT arriving after PostClick. A short
    -- window plus exact spell ID and target bounds the fallback. The client
    -- exposes no origin token for an identical manual cast in this window.
    cast.button, cast.expires = nil, GetTime() + 0.250
    awaitingSent = cast
  end
  if cast.refresh and QueueRefresh then QueueRefresh() end
end

function X.CastEvent(event, unit, ...)
  if event == "UI_ERROR_MESSAGE" then
    Trace(event, unit, ...)
    local message = StringField((...)) or StringField(unit)
    local failure = recentFailure
    recentFailure = nil
    if failure and failure.time == GetTime() and message and IsTargetCastFailure(message) then
      ApplyCast(failure.cast, failure.event, message)
    elseif failure then
      Trace("failure reason ignored", failure.cast.sentGUID)
    end
    if dispatch then
      dispatch.hadError = true
      if not failure and message and IsTargetCastFailure(message) then dispatch.targetError = message end
    else
      if awaitingSent and awaitingSent.press then awaitingSent.press.settled = true end
      awaitingSent = nil
    end
    return false
  end
  if StringField(unit) ~= "player" then return false end
  recentFailure = nil
  Trace(event, unit, ...)
  local cast = dispatch
  if cast then cast.latestEvent = nil end
  if event == "UNIT_SPELLCAST_SENT" then
    local deferred = not cast
    if deferred then
      cast, awaitingSent = awaitingSent, nil
      if cast and cast.expires <= GetTime() then return false end
    elseif awaitingSent then
      awaitingSent = nil -- an intervening player cast invalidates the older intent
      cast.deferred = false
    end
    if not cast then return false end
    cast.repeated = cast.press and cast.press.settled
    if cast.press then cast.press.settled = true end
    if cast.sawSent then cast.ambiguous = true; return false end
    cast.sawSent = true
    local target, guid, id = ...
    target, guid, id = StringField(target), StringField(guid), SpellID(id)
    if not target or not guid or not id then return false end
    local key = target:lower()
    if key ~= cast.full and key ~= cast.short and key ~= cast.preferred then
      Trace("target did not match", target, cast.who)
      return false
    end
    if cast.expectedID then
      if id ~= cast.expectedID then return false end
    else
      local ok, name = pcall(SpellName, id, nil)
      if not ok or StringField(name) ~= cast.spell then return false end
    end
    cast.sentGUID, cast.sentID = guid, id
    if deferred and not cast.repeated then ConfirmCast(cast) end
    return false
  end

  local guid, id = ...
  guid, id = StringField(guid), SpellID(id)
  if guid and id then
    local now = GetTime()
    for i = #pending, 1, -1 do
      local prior = pending[i]
      if prior.expires <= now then
        table.remove(pending, i)
      elseif prior.sentGUID == guid and prior.sentID == id then
        table.remove(pending, i)
        if event == "UNIT_SPELLCAST_FAILED" then
          recentFailure = { cast = prior, event = event, time = now }
        else
          ApplyCast(prior, event)
        end
        if cast and event == "UNIT_SPELLCAST_SUCCEEDED" then cast.refresh = true; return false end
        return event == "UNIT_SPELLCAST_SUCCEEDED"
      end
    end
    if cast and #cast.terminals < 8 then
      local terminal = { guid = guid, id = id, event = event, time = now }
      cast.latestEvent = terminal
      cast.terminals[#cast.terminals + 1] = terminal
    elseif cast then
      cast.ambiguous = true
    end
  end
  -- A manual buff still changes the aura list. Defer refresh during dispatch
  -- so the bookkeeping operates on the original click rather than a new row.
  if cast and event == "UNIT_SPELLCAST_SUCCEEDED" then cast.refresh = true end
  return not cast and event == "UNIT_SPELLCAST_SUCCEEDED"
end

function X.ResetCastTracking()
  dispatch, awaitingSent, rowPress, recentFailure, pending, seenCastGUIDs = nil, nil, nil, nil, {}, {}
  X.lastTargetCastProblem = nil
end

function X.ClearCastIntent()
  dispatch, awaitingSent, rowPress, recentFailure = nil, nil, nil, nil
end
end -- cast tracking

function X.RowTargetMatches(e)
  local guid = e and (e.castGuid or e.guid)
  if not guid or not e.unit then return false end
  local ok, current = pcall(UnitGUID, e.unit)
  return ok and SafeString(current) == guid
end

---------------------------------------------------------------------------
-- Queue refresh
---------------------------------------------------------------------------
X.farNow, X.farPrev = {}, {} -- range-watch sets shared with Wizard.lua

-- While scanning is idle the ticker waits for a spell, zone or roster event.
local refreshIdle = false

local function ClearCastQueue()
  X.ClearKeybindCasts()
  X.SyncCastMacro(true)
end

local function SuspendBuffing()
  refreshIdle = true
  X.Status.Unavailable("dead")
  X.ResetCastTracking()
  X.SuspendWindow()
  X.SyncCastMacro(true)
end

function X.UpdatePlayerLife(event)
  local wasDead = X.playerDead
  if event == "PLAYER_DEAD" then
    X.playerDead = true
    X.lifeCheckPending = nil
  else
    local dead = X.ReadUnitBool(_G.UnitIsDeadOrGhost, "player")
    if dead ~= nil then X.playerDead = dead end
    if event == "PLAYER_UNGHOST" and dead == nil then X.playerDead = false end
    if event == "PLAYER_UNGHOST" or event == "PLAYER_ALIVE" then
      -- The synchronous event can precede the unit flag update. Recheck on
      -- the existing tick until the client confirms that casting can resume.
      X.lifeCheckPending = X.playerDead or nil
    elseif not X.playerDead then
      X.lifeCheckPending = nil
    end
  end
  if X.playerDead then
    SuspendBuffing()
  elseif wasDead then
    X.RefreshMinimapButton()
    if QueueRefresh then QueueRefresh() end
  end
  if wasDead ~= X.playerDead and event ~= "PLAYER_LOGIN" then X.SendCover() end
end

local function ScanConfirmsGroupBuffed()
  if X.scanHasUnknownBuffs or X.scanHasMissingBuffs or X.scanNameFiltered then return false end
  local size = X.ReadUnitNumber(_G.GetNumGroupMembers)
  return size ~= nil and size > 1 and X.tallyUnits == size
end

-- Focus is outside the group tallies. Pass display text, not aura reads,
-- back to the window.
local focusMissing = {}
local function FocusLine()
  local valid, isSelf = Valid("focus")
  if not valid then return end
  local name = X.UnitNameOf("focus")
  if not name then return end
  local count = Missing("focus", focusMissing, false, isSelf)
  if count > 0 then
    return string_format(L["Focus %s: needs %s"], name,
      table.concat(focusMissing, ", ", 1, math_min(count, 3)) .. (count > 3 and (" +" .. (count - 3)) or ""))
  end
  if not X.auraUnknown then return string_format(L["Focus %s: buffed"],name) end
end

local function PauseReason()
  if db.pauseInCities and InMajorCity() then return L["Paused in a major city."], true end
  if db.pauseInBG then
    local instance = InInstanceNow()
    if instance == "pvp" or instance == "arena" then return L["Paused in a battleground."], true end
  end
  if db.pauseTaxi and _G.UnitOnTaxi then
    local ok, onTaxi = pcall(_G.UnitOnTaxi, "player")
    if ok and onTaxi then return L["Paused on a flight path."], true end
  end
  if db.lowMana and db.lowMana > 0 and X.LowMana() then return L["Low mana -- buffing paused."] end
end

local function OfferGroupCast(n)
  -- Group-cast mode: if enough group members need the same group-castable
  -- buff, the first such row offers the group version instead (one cast
  -- covers the party). Only the first matching row is converted.
  if db.groupCast and n > 0 then
    local tally = {}
    for i = 1, n do
      local e = entries[i]
      if e.group and not e.isSelf and not e.pet and X.RowTargetMatches(e) then
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
      local converted = false
      if e.group and not e.pet then
        for _, b in ipairs(myBuffs) do
          if b.name == e.missing[1] and b.groupName
             and (tally[b.key] or 0) >= (db.groupCastMin or 3) then
            local offer, item, count, reason, _, blocker = X.GroupOffer(b.name, e.unit)
            if offer then
              e.missing[1] = offer
              e.groupCast = true
              converted = true
            else
              X.groupFallback = X.GroupOfferReason(item, count, reason, blocker)
              X.groupFallbackSummary = blocker and X.GroupOfferReason(item, count, reason, blocker, true) or X.groupFallback
              X.groupFallbackEntry = X.groupFallback and e or nil
            end
            break
          end
        end
      end
      if converted then break end
    end
  end
end

-- Reuse the two listing sets instead of allocating one on every scan.
local listA, listB, recentlyGone = {}, {}, {}
local listedBefore = listA

local function AlertOnNewEntries(n)
  -- Droplet sound when someone new appears on the board
  local now, newName = GetTime(), false
  local listedNow = (listedBefore == listA) and listB or listA
  wipe(listedNow)
  for i = 1, n do
    local guid = entries[i].guid
    listedNow[guid] = true
    -- (greyed out-of-range rows don't ding: they're not castable yet)
    if not listedBefore[guid] then
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
  if newName then
    X.VisualBuffAlert()
    if db.playSound and now - X.lastSoundAt > 1 then
      X.lastSoundAt = now
      PlayAlert("new")
    end
  end
end

local function Refresh()
  if not X.WindowReady() or X.macroParked then return end
  if X.PlayerSuspended() then
    if not refreshIdle or not X.playerDead then X.UpdatePlayerLife() end
    return
  end
  if InCombatLockdown() then X.Status.Unavailable("combat"); return end
  if X.HasHeldRow() then return end
  X.assignmentGroupConflicts = X.AssignmentEnabled() and next(db.buffAssignments) and {} or nil
  refreshIdle = false
  X.applyFilter = true  -- the window honors the role filter; reports turn it off
  local wasAfterCombat = X.afterCombat
  X.afterCombat = nil
  X.afterCombatScan = wasAfterCombat or nil
  X.PrepareWindowScan()

  if not hasAnyBuff then
    refreshIdle = true
    ClearCastQueue()
    X.Status.Unavailable("inactive")
    X.ShowWindowStatus(sessionShow and not db.hidden and L["No supported buffs in your spellbook."])
    return
  end

  local groupHidden = db.groupOnly and not InGroup()
  local reason, idle = PauseReason()
  if reason then
    refreshIdle = idle or false
    ClearCastQueue()
    X.Status.Unavailable("paused")
    wipe(listedBefore)
    local showStatus = not (db.hidden or groupHidden or db.autoHide)
    X.ShowWindowStatus(showStatus and reason, not showStatus)
    return
  end

  X.groupFallback, X.groupFallbackEntry, X.groupFallbackSummary = nil, nil, nil
  local n = CollectEntries()
  X.CheckDrops()
  X.CheckRange()
  X.CheckFalls()
  X.RefreshWindowHeader()
  OfferGroupCast(n)

  -- The native keys and bar macro follow the scan even when the list is hidden.
  X.SetNextCast(n > 0 and entries[1] or nil)
  X.SyncCastMacro()
  if db.hidden or groupHidden then
    X.ShowWindowStatus()
    wipe(listedBefore)
    if X.UpdateNearbyTargetAfterScan then X.UpdateNearbyTargetAfterScan() end
  else
    X.RenderQueue(entries, n, sessionShow, wasAfterCombat)
    AlertOnNewEntries(n)
  end
  X.Status.Publish(entries, n)
  X.missPrev, X.missNow = X.missNow, X.missPrev
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local driver = CreateFrame("Frame")
local refreshQueued = false
local ticker

do
  local function RecordTiming(kind, start, ...)
    local stop = X.ReadUnitNumber(debugprofilestop)
    if stop and stop >= start then
      local dt, stat = stop - start, X.timings[kind]
      stat.n, stat.total, stat.last = stat.n + 1, stat.total + dt, dt
      if dt > stat.max then stat.max = dt end
    end
    return ...
  end

  function X.Measure(kind, work, ...)
    local start = X.ReadUnitNumber(debugprofilestop)
    if not start then return work(...) end
    return RecordTiming(kind, start, work(...))
  end
end

X.timings = {}
for _, kind in ipairs({ "scan", "prepare", "import", "debuff", "combatDebuff" }) do
  X.timings[kind] = { n = 0, total = 0, max = 0, last = 0 }
end

function X.RefreshFault(err)
  scanFaults = math_min(1000000, scanFaults + 1)
  scanHorizon, nEntries, X.afterCombatScan, X.fallPending = nil, 0, nil, nil
  X.groupFallback, X.groupFallbackEntry, X.groupFallbackSummary = nil, nil, nil
  X.scanUnit, X.blessingScanUnit = nil, nil
  X.scanHasUnknownBuffs, X.scanHasMissingBuffs, X.scanNameFiltered = true, false, false
  X.tallyUnits, X.tallyMissingUnits, X.tallyUnknownUnits = 0, 0, 0
  wipe(X.tally); wipe(X.consTally); wipe(X.expiryTally)
  X.ClearCastIntent()
  pcall(X.AbortWindowScan)
  pcall(X.SyncCastMacro, true)
  pcall(X.Status.Unavailable, InCombatLockdown() and "combat" or "updating")
  if err ~= lastError then
    lastError = err
    Print(string_format(L["|cffff4040error:|r %s"],tostring(err)))
  end
end

local function SafeRefresh()
  local ok, err = X.Measure("scan", pcall, Refresh)
  if not ok then X.RefreshFault(err) end
end

-- Steady refresh every UPDATE_INTERVAL via C_Timer; bursts of events (UNIT_AURA storms in
-- raids, nameplates popping in) collapse into a single refresh SOON_DELAY later.
-- How many players are in my group, me included (0 when solo)?
local function GroupSize()
  if GetNumGroupMembers then
    local n = X.ReadUnitNumber(GetNumGroupMembers)
    if n then return n end
  end
  local raid = X.ReadUnitNumber(GetNumRaidMembers)
  if raid and raid > 0 then return raid end
  local party = X.ReadUnitNumber(GetNumPartyMembers)
  return party and party > 0 and party + 1 or 0
end

-- Movement events and combat exit wake the steady ticker without delaying
-- event-driven refreshes. Scan policy is sampled at most once per cycle.
local scanTicksRemaining = 0
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
    if X.lifeCheckPending then
      if X.ReadUnitBool(_G.UnitIsDeadOrGhost, "player") == false then X.UpdatePlayerLife() end
    end
    if X.playerDead then return end
    if X.ExpireReadyCheck then X.ExpireReadyCheck() end
    X.UpdateFade()
    X.TickMinimapPulse()
    if refreshIdle or InCombatLockdown() then return end
    if db.scanThrottle and scanTicksRemaining > 0 then
      scanTicksRemaining = scanTicksRemaining - 1
      return
    end
    scanTicksRemaining = X.Intel.ScanTicks(GroupSize) - 1
    SafeRefresh()
  end
  StartTicker = function()
    if not ticker then ticker = C_Timer.NewTicker(UPDATE_INTERVAL, TickRefresh) end
  end
else
  -- Fallback for clients without C_Timer: throttled accumulator, never per-frame work.
  -- Event bursts have their own deadline and can refresh even while idle.
  local elapsed, soonElapsed, interval = 0, nil, nil
  StartTicker = function()
    driver:SetScript("OnUpdate", function(_, dt)
      elapsed = elapsed + dt
      local eventPending = soonElapsed ~= nil
      if eventPending then
        soonElapsed = soonElapsed + dt
        if soonElapsed < SOON_DELAY then return end
      else
        if elapsed < UPDATE_INTERVAL then return end
        if not refreshIdle and not InCombatLockdown() then
          if not db.scanThrottle then interval = UPDATE_INTERVAL end
          interval = interval or UPDATE_INTERVAL * X.Intel.ScanTicks(GroupSize)
          if elapsed < interval then return end
        end
      end
      elapsed, soonElapsed, interval = 0, nil, nil
      X.RunDueSyncWarmupRetry()
      if X.lifeCheckPending then
        if X.ReadUnitBool(_G.UnitIsDeadOrGhost, "player") == false then X.UpdatePlayerLife() end
      end
      if X.playerDead then return end
      if X.ExpireReadyCheck then X.ExpireReadyCheck() end
      if X.TickPull then X.TickPull() end
      X.UpdateFade()
      X.TickMinimapPulse()
      if not InCombatLockdown() and (eventPending or not refreshIdle) then SafeRefresh() end
    end)
  end
  Soon = function()
    soonElapsed = soonElapsed or 0
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
  if not ok then Print(string_format(L["|cffff4040error reading spellbook:|r %s"],tostring(err))) end
  X.prioDirty = true
  if X.WindowReady() then
    X.InvalidateRows()
    X.ApplyRowLayout()
  end
  if X.RefreshConfig then X.RefreshConfig() end
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

-- An incompatible install needs only the startup warning and, if locked
-- down, one combat-exit callback to park an owned action-bar macro.
if not X.supported then
  driver:RegisterEvent("ADDON_LOADED")
  driver:RegisterEvent("PLAYER_LOGIN")
else
  -- Register events one at a time and ignore any this client doesn't have
  -- (newer clients throw an error for unknown event names, which would stop the whole file).
  for _, ev in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE",
    "GROUP_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "PARTY_LEADER_CHANGED",
    "PLAYER_ROLES_ASSIGNED", "GROUP_LEFT", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED",
    "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "UNIT_AURA", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED", "UI_ERROR_MESSAGE",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "CVAR_UPDATE", "UPDATE_BINDINGS", "UPDATE_MACROS",
    "PLAYER_LEAVING_WORLD", "PLAYER_LOGOUT",
    "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
    "SPELL_DATA_LOAD_RESULT", "UNIT_PORTRAIT_UPDATE", "BAG_UPDATE_DELAYED",
    "READY_CHECK", "READY_CHECK_CONFIRM", "READY_CHECK_FINISHED",
    "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED",
    "CHAT_MSG_ADDON", "CHAT_MSG_WHISPER", "CHAT_MSG_SAY", "CHALLENGE_MODE_START",
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_FLAGS_CHANGED",
    "PLAYER_FOCUS_CHANGED", "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING",
    "ENCOUNTER_START", "ENCOUNTER_END", "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED", "UNIT_PET",
  }) do
    pcall(driver.RegisterEvent, driver, ev)
  end
end

driver:SetScript("OnEvent", function(self, event, arg1, ...)
  if not X.supported then
    if event == "PLAYER_LOGIN" or (event == "ADDON_LOADED" and arg1 == ADDON) then
      self:UnregisterAllEvents()
      if InCombatLockdown() then self:RegisterEvent("PLAYER_REGEN_ENABLED") else X.SyncCastMacro(true) end
      Print(L["BuffRadar requires the Forever package on Interface 16001. Casting is disabled."])
    elseif event == "PLAYER_REGEN_ENABLED" and not InCombatLockdown() then
      self:UnregisterAllEvents()
      X.SyncCastMacro(true)
    end
    return
  end
  if X.auraIds then
    if event == "PLAYER_TARGET_CHANGED" then X.auraIds.target = nil
    elseif event == "UPDATE_MOUSEOVER_UNIT" then X.auraIds.mouseover = nil
    elseif (event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED")
      and type(arg1) == "string" and Readable(arg1) then X.auraIds[arg1] = nil
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED"
      or event == "RAID_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
      wipe(X.auraIds)
    end
  end
  -- The flattened action-bar macro has no pre-cast GUID check. Park it
  -- immediately if a tracked token changes, without rebuilding the list.
  if event == "NAME_PLATE_UNIT_REMOVED" or event == "NAME_PLATE_UNIT_ADDED" then
    if type(arg1) == "string" and Readable(arg1) then X.DisarmStaleCastMacro(arg1, event == "NAME_PLATE_UNIT_REMOVED") end
  elseif event == "PLAYER_TARGET_CHANGED" then
    X.DisarmStaleCastMacro("target")
  elseif event == "UPDATE_MOUSEOVER_UNIT" then
    X.DisarmStaleCastMacro("mouseover")
  elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE"
      or event == "GROUP_LEFT" or event == "UNIT_PET" then
    X.DisarmStaleCastMacro()
  end
  -- The busiest events, filtered first. They queue a list refresh:
  --  * in combat the list is frozen and PLAYER_REGEN_ENABLED refreshes it
  --    afterwards, so they're dropped outright;
  --  * UNIT_AURA also fires for units BuffRadar never lists (enemy and NPC
  --    nameplates, pets, bosses, arena opponents) -- those are dropped too.
  if event == "UNIT_AURA" or event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED"
     or event == "UPDATE_MOUSEOVER_UNIT" then
    if InCombatLockdown() or X.playerDead then
      if event == "UNIT_AURA" and X.auraIds and Readable(arg1) and type(arg1) == "string" then
        X.auraIds[arg1] = nil
      end
      return
    end
    if event == "UNIT_AURA" then
      if X.QueuePersonalReadiness and Readable(arg1) and arg1 == "player" then X.QueuePersonalReadiness() end
      if not X.AuraEventNeedsRefresh(arg1, ...) then return end
    end
    Soon()
    return
  end
  if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
    if arg1 == ADDON then
      if X.Support then X.Support.RecordFault(event == "ADDON_ACTION_BLOCKED" and "blocked" or "forbidden") end
      Print(string_format(L["|cffff4040the game blocked a BuffRadar action|r (%s)"],event .. ": " .. tostring((...))))
    end
    return
  end
  if event == "UNIT_SPELLCAST_SENT" or event == "UNIT_SPELLCAST_SUCCEEDED"
     or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET"
     or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UI_ERROR_MESSAGE" then
    if db and X.CastEvent(event, arg1, ...) then Soon() end
    return
  end
  if event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
    Soon() -- the secure viewport is resized only by an unlocked refresh
    return
  elseif event == "PLAYER_STARTED_MOVING" or event == "PLAYER_STOPPED_MOVING" then
    scanTicksRemaining = 0
    if db and db.scanThrottle and not refreshIdle and not InCombatLockdown() then Soon() end
    return
  elseif event == "ENCOUNTER_START" then
    X.Intel.ClearPreparation()
    X.Debuffs.Encounter(arg1)
    if db and db.forecastSeconds > 0 and not InCombatLockdown() then Soon() end
    return
  elseif event == "ENCOUNTER_END" then
    X.Debuffs.Encounter(nil)
    local success = select(4, ...)
    if Readable(success) and (success == 0 or success == false) then
      X.Intel.MarkWipe()
      if db and db.smartPriority and not InCombatLockdown() then Soon() end
    end
    return
  elseif event == "UPDATE_INVENTORY_DURABILITY" or event == "PLAYER_EQUIPMENT_CHANGED" or event == "UNIT_PET" then
    if X.QueuePersonalReadiness and (event ~= "UNIT_PET" or Readable(arg1) and arg1 == "player") then
      X.QueuePersonalReadiness()
    end
    if event == "UNIT_PET" and db and db.pets and not InCombatLockdown() then Soon() end
    return
  elseif event == "CVAR_UPDATE" then
    local name = type(arg1) == "string" and Readable(arg1) and arg1:lower()
    if name == "actionbuttonusekeydown" or name == "action_button_use_key_down" then
      X.ApplyNextRegistration()
      if db then X.SyncCastMacro() end
    elseif name == "nameplateshowfriendlyplayers" or name == "nameplateshowfriends"
        or name == "nameplateshowall" or name == "nameplateshowonlynameforfriendlyplayerunits" then
      Soon()
    end
    return
  elseif event == "UPDATE_MACROS" then
    if X.InvalidateCastMacro() and db then Soon() end
    return
  elseif event == "UPDATE_BINDINGS" then
    if X.RefreshConfig then X.RefreshConfig() end
    return
  elseif event == "PARTY_LEADER_CHANGED" then
    X.CheckLegacyAuthority()
    if X.CheckPullRoster then X.CheckPullRoster() end
    X.OnCoordinationRoster(true)
    Soon()
    return
  elseif event == "PLAYER_ROLES_ASSIGNED" then
    X.OnCoordinationRoster()
    local assignments = X.AssignmentEnabled()
    if assignments then X.assignmentGroupConflicts = nil end
    if db and (db.smartPriority or assignments) then Soon() end
    if X.QueueAssignmentPreviewRefresh then X.QueueAssignmentPreviewRefresh() end
    return
  elseif event == "GROUP_LEFT" then
    X.CheckLegacyAuthority(not InGroup())
    X.joinGeneration = (X.joinGeneration or 0) + 1
    X.OnRoster()
    X.OnCoordinationRoster(true)
    if not InGroup() then
      X.Intel.ResetContext()
      if X.CloseRaidPreparation then X.CloseRaidPreparation(true) end
    end
    X.Status.Unavailable("updating")
    if not InRaid() then X.subgroupDuties = nil end
    local size = X.ReadUnitNumber(GetNumGroupMembers)
    if (size and size <= 0) or (not size and not InGroup()) then
      X.assignmentRoleOverrides = nil
      X.blockerUndo = nil
    else
      X.PruneAssignmentRoleOverrides()
    end
    X.assignmentGroupConflicts = nil
    Soon()
    if X.QueueAssignmentPreviewRefresh then X.QueueAssignmentPreviewRefresh() end
    return
  elseif event == "BAG_UPDATE_DELAYED" then
    X.InvalidateReagents()
    if X.QueueAssignmentPreviewRefresh then X.QueueAssignmentPreviewRefresh(true) end
    Soon()
    return
  elseif event == "SPELL_DATA_LOAD_RESULT" then
    if watchedSpells[arg1] then
      watchedSpells[arg1] = nil
      ScheduleRebuild()
    end
    return
  elseif event == "READY_CHECK" then
    if db then X.ReadyReport(X.StartReadyCheck()) end
    return
  elseif event == "READY_CHECK_CONFIRM" then
    if db then X.ConfirmReadyCheck(arg1, (...)) end
    return
  elseif event == "READY_CHECK_FINISHED" then
    if db then X.FinishReadyCheck(arg1) end
    return
  elseif event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
    if db then X.SpecSwap(); Soon() end
    return
  elseif event == "UNIT_PORTRAIT_UPDATE" then
    X.InvalidatePortrait(arg1)
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
  if event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
    X.UpdatePlayerLife(event)
    X.Debuffs.Refresh()
    if event == "PLAYER_DEAD" and db then
      X.Intel.ClearPreparation()
      X.ClearReadyCheck()
      if X.DeathRecap then X.DeathRecap(db.deathRecap) end
    end
    return
  end
  if event == "PLAYER_FLAGS_CHANGED" then
    if db then X.SendCover() end
    return
  end
  if event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_LOGOUT" then
    X.macroParked = true
    ClearCastQueue()
    X.Status.Unavailable("updating")
    X.Intel.ResetContext()
    X.Debuffs.Clear()
    return
  end
  if event == "PLAYER_ENTERING_WORLD" then
    X.macroParked = nil
    ClearCastQueue()
    X.OnCoordinationRoster()
    X.ResetCastTracking()
    X.ClearReadyCheck()
    X.UpdatePlayerLife(event)
    X.Status.Unavailable(X.playerDead and "dead" or "updating")
    X.Intel.ResetContext()
    X.Debuffs.Encounter(nil)
    Soon()
    return
  end
  if event == "GROUP_ROSTER_UPDATE" then
    X.assignmentGroupConflicts = nil
    X.OnCoordinationRoster()
    if db then X.OnRoster() end
    if not InGroup() then
      X.ClearReadyCheck()
      X.Intel.ResetContext()
    end
    if not InCombatLockdown() and not X.playerDead then X.Status.Unavailable("updating") end
    if db and X.AutoProfileCheck then X.AutoProfileCheck() end
    Soon()
    if X.QueueAssignmentPreviewRefresh then X.QueueAssignmentPreviewRefresh() end
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
    if arg1 ~= ADDON then
      if db and db.theme == X.AUTO_THEME_ID then
        for _, entry in ipairs(X.AUTO_THEME_ADDONS) do
          if arg1 == entry[1] then X.ResolveAutoTheme(); break end
        end
      end
      return
    end
    X.ShowSaveState(X.Settings.Load(true))
    X.Status.Unavailable("updating")
    Ignore.Rebuild()
    X.SpecSwap()
    X.ResolveAutoTheme()
  elseif event == "PLAYER_LOGIN" then
    driver:UnregisterEvent("PLAYER_LOGIN")  -- one-off
    if not db then
      -- Defensive fallback: normally ADDON_LOADED has already migrated the save.
      X.ShowSaveState(X.Settings.Load(false))
      Ignore.Rebuild()
    end
    X.ResolveAutoTheme()
    X.UpdatePlayerLife(event)
    X.InitSync()
    X.SendCover()
    X.inGroupPrev = InGroup()
    RequestSpellData()
    local ok, err = pcall(BuildBuffList)
    if not ok then Print(string_format(L["|cffff4040error reading spellbook:|r %s"],tostring(err))) end
    X.prioDirty = true
    ok, err = pcall(X.BuildUI)
    if not ok then Print(string_format(L["|cffff4040error building window:|r %s"],tostring(err))) end
    X.ApplyClickThrough()
    X.Debuffs.Apply()
    X.SyncCastMacro(true) -- migrate the built-in macro, but never arm a prior session's queue
    Print(L["loaded. Type /br to show the window."])
    if not db.wizardSeen then
      Print(L["New to BuffRadar? Run /br wizard for Quick Setup."])
    end
    if X.FriendlyPlatesOn() == false then
      Print(L["friendly nameplates are |cffff4040off|r - nearby players outside your group can't be listed until they're on. Type /br plates to turn them on (or press Shift+V)."])
    end
    if not hasAnyBuff then
      Print(L["You don't know any buffs this addon handles yet; the window will appear once you learn one."])
    end
    StartTicker()
    Soon()
  elseif event == "PLAYER_REGEN_DISABLED" then
    if X.CloseNearbyDiagnostics then X.CloseNearbyDiagnostics() end
    if X.CloseRaidPreparation then X.CloseRaidPreparation() end
    X.auraIds = nil
    X.ClearCastIntent()
    X.combatStart = GetTime()  -- the wipe report times the fight from here (1.9.0)
    X.BeginWindowCombat()
    X.Intel.ClearPreparation()
    X.Status.Unavailable(X.playerDead and "dead" or "combat")
    X.TickMinimapPulse()
    X.Debuffs.Refresh()
  elseif event == "PLAYER_REGEN_ENABLED" then
    X.afterCombat = true  -- Refresh() pulses the border if work is waiting
    if InCombatLockdown() then return end
    scanTicksRemaining = 0
    X.Intel.WakeAfterCombat()
    X.Debuffs.Refresh()
    X.SyncCastMacro(true)
    if not X.EndWindowCombat() then
      SuspendBuffing()
      if db and X.WipeCheck then X.WipeCheck() end
      return
    end
    if db and X.WipeCheck then X.WipeCheck() end  -- post-wipe report (1.9.0)
    Soon()
  elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
    if db then ScheduleRebuild() end
  else
    if (event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE") and db then
      X.OnCoordinationRoster()
      X.OnRoster()
      if not InGroup() then X.Intel.ResetContext() end
      if not InCombatLockdown() and not X.playerDead then X.Status.Unavailable("updating") end
      if X.QueueAssignmentPreviewRefresh then X.QueueAssignmentPreviewRefresh() end
    end
    if (event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED"
        or event == "ZONE_CHANGED_INDOORS") and db then
      if X.AutoProfileCheck then X.AutoProfileCheck() end
      if event == "ZONE_CHANGED_NEW_AREA" then
        X.Intel.ResetContext()
        X.Debuffs.Encounter(nil)
        if not InCombatLockdown() and not X.playerDead then X.Status.Unavailable("updating") end
        X.InstanceCheck()
      end
    end
    Soon()
  end
end)

---------------------------------------------------------------------------
-- Keybind actions (Bindings.xml calls these)
---------------------------------------------------------------------------
function BuffRadar_ToggleSound()
  if not db or X.PlayerSuspended() then return end
  db.playSound = not db.playSound
  Print(db.playSound and L["Sound |cff00ff00on|r"] or L["Sound |cffff4040muted|r"])
  if X.RefreshConfig then X.RefreshConfig() end
end

---------------------------------------------------------------------------
-- Keybind + macro helpers (block-scoped except the two below: 200-local limit)
---------------------------------------------------------------------------
local KeybindText, OpenKeybinds
do
local MACRO_HEADER = "# BuffRadar\n/stopmacro [combat][@player,dead]"
local MACRO_NOTE = "/click BuffRadarMacroButton"
local LEGACY_CLICK = "/click BuffRadarNextButton"
local macro = {}

local function IsLegacyClick(body)
  return body == LEGACY_CLICK or body == LEGACY_CLICK .. " LeftButton 1"
end

local function IsManagedMacro(body)
  if IsLegacyClick(body) or body == MACRO_HEADER then return true end
  if #body > 255 or body:sub(1, #MACRO_HEADER + 1) ~= MACRO_HEADER .. "\n" then return false end
  local text = body:sub(#MACRO_HEADER + 2)
  if IsLegacyClick(text) then return true end
  if text:sub(1, #MACRO_NOTE + 1) ~= MACRO_NOTE .. "\n" then return false end
  text = text:sub(#MACRO_NOTE + 2)
  -- The marker alone does not claim a user's edited macro at the next login.
  if text:match("^/cast %[[^\r\n]+$") then return true end
  local handBack = text:match("^/cleartarget\n/targetexact [^\r\n]+\n/cast %[[^\r\n]+\n(/[^\r\n]+)$")
  return handBack == "/targetlasttarget" or handBack == "/cleartarget"
end

-- The game hands stored macro text back with a trailing line break after a
-- relog (and may use CR LF). Compare on the text itself, or BuffRadar
-- refuses its own macro at login and leaves it frozen until it is remade.
local function MacroText(body)
  body = body:gsub("\r\n?", "\n")
  return (body:gsub("%s+$", ""))
end

local function ReadMacro()
  if not (GetMacroIndexByName and GetMacroBody) then return end
  local ok, id = pcall(GetMacroIndexByName, MACRO_NAME)
  if ok and type(id) == "number" and Readable(id) and id > 0 then
    local read, body = pcall(GetMacroBody, id)
    return id, read and type(body) == "string" and Readable(body) and MacroText(body) or nil
  end
end

local function MacroBody(disarmed)
  local nextBtn = X.GetNextButton()
  local entry = nextBtn and (nextBtn.entry or nextBtn.deliveryEntry)
  if disarmed or X.macroParked or X.PlayerSuspended() or InCombatLockdown() then return MACRO_HEADER, "disarmed" end
  if not entry then return MACRO_HEADER, "no_target" end
  if not X.RowTargetMatches(entry) then return MACRO_HEADER, "recipient" end
  if not nextBtn.entry then return MACRO_HEADER, "unsafe" end
  local action = nextBtn:GetAttribute("type")
  if action == "spell" then
    local down = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
    return MACRO_HEADER .. "\n" .. LEGACY_CLICK .. (down and " LeftButton 1" or ""), "ready"
  end
  if action ~= "macro" then return MACRO_HEADER, "unsafe" end
  -- WoW cannot /click a button that runs macrotext from an action-bar macro.
  -- Write the already prepared action as top-level commands instead. The
  -- only /click in this path is an ordinary button for cast bookkeeping.
  local text, shifted = nextBtn:GetAttribute("macrotext"), nextBtn:GetAttribute("shift-macrotext1")
  if db.castMethod ~= "target" and X.NeedsExactTarget(entry.unit, entry.isSelf, "target") then
    -- In other cast modes the button may carry a mutable nameplate or
    -- mouseover token. Never embed that token in a stored macro.
    text, shifted = X.ExactCastBody(entry.unit, nextBtn.bSpellText, shifted and nextBtn.bGroupText, X.UnitPresent("target"))
    if nextBtn:GetAttribute("shift-type1") and not shifted then return MACRO_HEADER, "unsafe" end
  end
  if not text then return MACRO_HEADER, "unsafe" end
  if shifted and shifted ~= text then
    local a, condition, spell, b = text:match("^(.-)/cast (%b[]) ([^\r\n]+)(.*)$")
    local sa, sc, ss, sb = shifted:match("^(.-)/cast (%b[]) ([^\r\n]+)(.*)$")
    if not condition or not sc or sa ~= a or sb ~= b then return MACRO_HEADER, "unsafe" end
    text = a .. "/cast [mod:shift,nomod:ctrl,nomod:alt," .. sc:sub(2) .. " " .. ss
      .. "; " .. condition .. " " .. spell .. b
  end
  local body = MACRO_HEADER .. "\n" .. MACRO_NOTE .. "\n" .. text
  if #body > 255 then return MACRO_HEADER, "overflow" end
  return body, "ready"
end

function X.InvalidateCastMacro()
  if macro.writing then return false end
  macro.checked = false
  return true
end

local function TrackMacro(index, body)
  -- A macro can be renumbered. A changed body, not a new slot number,
  -- is what makes us stop managing it for this session.
  if macro.body and body then
    macro.owned = macro.owned and macro.body == body
  else
    macro.owned = body and IsManagedMacro(body)
  end
  macro.index, macro.body, macro.checked = index, body, true
end

local function RunningMacro()
  if not GetRunningMacro then return end
  local ok, index = pcall(GetRunningMacro)
  if ok and type(index) == "number" and Readable(index) and index > 0 then return index end
end

local function MacroEditorOpen()
  local editor = _G.MacroFrame
  if not (editor and editor:IsShown()) then return false end
  -- UPDATE_MACROS makes the game reload the edit box from disk. Do not
  -- discard unsaved text in the macro editor while following the queue.
  if macro.editor ~= editor then
    macro.editor = editor
    editor:HookScript("OnHide", function()
      if not X.InvalidateCastMacro() then return end
      if not X.supported or X.PlayerSuspended() then X.SyncCastMacro(true) else Soon() end
    end)
  end
  return true
end

-- A diagnostic read uses the same body decision as synchronization. It never
-- creates or edits a macro, attaches editor hooks, or arms protected buttons.
function X.CastDelivery()
  local proposed, proposedReason = MacroBody()
  local nextBtn = X.GetNextButton()
  local entry = nextBtn and nextBtn.entry
  local action = nextBtn and nextBtn:GetAttribute("type")
  local directReason = "ready"
  if X.macroParked or X.PlayerSuspended() or InCombatLockdown() then directReason = "disarmed"
  elseif not nextBtn or not (entry or nextBtn.deliveryEntry) then directReason = "no_target"
  elseif not X.RowTargetMatches(entry or nextBtn.deliveryEntry) then directReason = "recipient"
  elseif not entry or nextBtn.bGuid ~= entry.guid or (action ~= "spell" and action ~= "macro") then directReason = "unsafe" end
  local result = { directReady = directReason == "ready", directReason = directReason,
    macroReady = false, macroState = "unavailable", reason = proposedReason,
    proposedReason = proposedReason }
  if not (GetMacroIndexByName and GetMacroBody and EditMacro) then result.reason = "api"; return result end
  local index, stored = ReadMacro()
  if not index then result.reason = "missing"; return result end
  if not stored then result.reason = "unreadable"; return result end
  local owned
  if macro.body then owned = macro.owned and macro.body == stored else owned = IsManagedMacro(stored) end
  if not owned then result.reason = "custom"; return result end
  if proposedReason ~= "ready" and not InCombatLockdown() then
    return result
  elseif proposed ~= stored then
    local editor = _G.MacroFrame
    if InCombatLockdown() then result.reason = "combat"
    elseif editor and editor:IsShown() then result.reason = "editor"
    elseif RunningMacro() then result.reason = "running"
    else result.reason = "sync" end
    result.macroState = "pending"
  elseif proposedReason == "ready" then
    result.reason, result.macroState, result.macroReady = "ready", "ready", true
  end
  return result
end

local deliveryReasons = {
  ready = "Ready", no_target = "No queued target.", disarmed = "Casting is intentionally disarmed.",
  recipient = "Recipient changed or is unreadable.", unsafe = "Cast cannot be represented safely.",
  overflow = "Cast exceeds 255 bytes.", api = "Macro controls are unavailable.",
  missing = "Create the managed macro with /br macro.", unreadable = "Stored macro could not be read.",
  custom = "The macro is custom or no longer managed.", combat = "Synchronization waits until combat ends.",
  editor = "Close the macro editor to synchronize.", running = "Synchronization waits for the running macro.",
  sync = "Waiting for synchronization.",
}

function X.DeliveryLines()
  local state = X.CastDelivery()
  return string_format(L["Cast next buff: %s"], L[deliveryReasons[state.directReason]]),
    string_format(L["Action-bar macro %s: %s"],
      state.macroState == "ready" and L["Ready"] or state.macroState == "pending" and L["Pending"] or L["Unavailable"],
      L[deliveryReasons[state.reason]])
end

local function SyncCastMacro(disarmed)
  if (not db and not disarmed) or InCombatLockdown() or macro.writing or not EditMacro then return end
  if not macro.checked then
    local index, body = ReadMacro()
    if index and not body then return end
    TrackMacro(index, body)
  end
  if not macro.owned then return end
  local body = MacroBody(disarmed)
  if body == macro.body or MacroEditorOpen() or RunningMacro() then return end
  -- Recheck immediately before a write. Never write to an old index or
  -- over a body edited since the last UPDATE_MACROS notification.
  local index, current = ReadMacro()
  if index and not current then return end
  TrackMacro(index, current)
  if not macro.owned or body == current then return end
  macro.writing = true
  pcall(EditMacro, index, nil, nil, body)
  macro.writing = false
  local id, saved = ReadMacro()
  if id == index and saved == body then macro.body = body end
end

function X.SyncCastMacro(disarmed)
  SyncCastMacro(disarmed)
  local state = X.CastDelivery()
  local nextBtn = X.GetNextButton()
  local entry = nextBtn and (nextBtn.entry or nextBtn.deliveryEntry)
  local signature = state.directReason .. ":" .. state.reason .. ":" .. state.macroState
    .. ":" .. tostring(entry and (entry.castGuid or entry.guid)) .. ":" .. tostring(nextBtn and nextBtn.bSpellText)
  if signature ~= macro.deliverySignature then
    macro.deliverySignature = signature
    if X.RefreshNextPreview then X.RefreshNextPreview() end
    if X.SupportChanged then pcall(X.SupportChanged) end
  end
end

function X.DisarmStaleCastMacro(unit, removed)
  local nextBtn = X.GetNextButton()
  local entry = macro.owned and nextBtn and nextBtn.entry
  if entry and (not unit or unit == entry.unit) and (removed or not X.RowTargetMatches(entry)) then
    X.SyncCastMacro(true)
  end
end

function X.RecordBarMacroClick()
  local nextBtn = X.GetNextButton()
  -- Observation only: this button cannot cancel the following /cast line.
  if not (macro.checked and macro.owned and macro.body:find(MACRO_NOTE, 1, true)
      and RunningMacro() == macro.index and macro.body == MacroBody()) then return end
  local id, body = ReadMacro()
  if id ~= macro.index or body ~= macro.body then return end
  X.BeginCastClick(nextBtn, "LeftButton", false, "bar macro", body)
  X.EndCastClick(nextBtn, "LeftButton", false, "bar macro")
end

function KeybindText(binding)
  local k1, k2 = nil, nil
  if GetBindingKey then k1, k2 = GetBindingKey(binding or NEXT_BINDING) end
  if not k1 then return "|cff888888" .. L["not bound"] .. "|r" end
  local function nice(k) return (GetBindingText and GetBindingText(k)) or k end
  return "|cffffd100" .. nice(k1) .. (k2 and (", " .. nice(k2)) or "") .. "|r"
end

function OpenKeybinds()
  if X.PlayerSuspended() then return end
  if InCombatLockdown() then Print(L["Can't open key bindings during combat."]); return end
  local ok = false
  if Settings and Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
    ok = pcall(Settings.OpenToCategory, Settings.KEYBINDINGS_CATEGORY_ID, BINDING_HEADER_BUFFRADAR)
  end
  if not ok then
    Print(L["Open Game Menu > Options > Keybindings and look for the BuffRadar section."])
  end
end

local function MacroIcon()
  for _, b in ipairs(myBuffs) do
    local t = SpellIcon(b.name)
    if type(t) == "number" then return t end
  end
  return 134400 -- question mark
end

-- Create or update the owned macro and put it on the cursor. Background
-- refreshes never create one or touch a custom macro of the same name.
local function PrintDelivery()
  local direct, bar = X.DeliveryLines()
  Print(direct); Print(bar)
end

MakeMacro = function()
  if InCombatLockdown() then Print(L["Can't edit macros during combat."]); PrintDelivery(); return end
  if not (GetMacroIndexByName and GetMacroBody and CreateMacro and EditMacro) then
    Print(L["Macro controls are unavailable. Bind Cast next buff with /br key instead."])
    PrintDelivery()
    return
  end
  if MacroEditorOpen() then
    Print(L["Close the macro editor before creating the BuffRadar macro."])
    PrintDelivery()
    return
  end
  local idx, current = ReadMacro()
  if not idx or current then TrackMacro(idx, current) end
  local body = MacroBody()
  if idx and (not current or not macro.owned) then
    Print(L["Rename your custom BuffRadar macro first, or bind Cast next buff with /br key."])
    PrintDelivery()
    return
  end
  if not idx and GetNumMacros then
    local constants = _G.Constants and _G.Constants.MacroConsts
    local cap = (constants and constants.MAX_ACCOUNT_MACROS) or MAX_ACCOUNT_MACROS or 120
    if GetNumMacros() >= cap then
      Print(L["Your general macro slots are full. Make room or bind Cast next buff with /br key."])
      PrintDelivery()
      return
    end
  end
  macro.writing = true
  if not idx then
    pcall(CreateMacro, MACRO_NAME, MacroIcon(), body, nil)
  elseif current ~= body then
    pcall(EditMacro, idx, nil, nil, body)
  end
  macro.writing = false
  local id, saved = ReadMacro()
  if not id or saved ~= body then
    Print(L["Couldn't save the BuffRadar macro. Bind Cast next buff with /br key instead."])
    PrintDelivery()
    return
  end
  macro.index, macro.body, macro.owned, macro.checked = id, body, true, true
  if PickupMacro then pcall(PickupMacro, id) end
  Print(L["Place the BuffRadar macro on an action bar. It follows the next buff automatically."])
  PrintDelivery()
end
end -- keybind + macro block

-- Addon-private entry points. Consumers read the current queue counts and
-- session flags through accessors; the spell and entry tables are reused.
X.Print, X.L, X.Refresh = Print, L, SafeRefresh
X.InGroup, X.InRaid = InGroup, InRaid
X.Core = {
  BuildBuffList = BuildBuffList,
  PlayAlert = PlayAlert,
  QueueRefresh = QueueRefresh,
  IsOn = IsOn,
  InInstance = InInstanceNow,
  InMajorCity = InMajorCity,
  KeybindText = KeybindText,
  OpenKeybinds = OpenKeybinds,
  MakeMacro = MakeMacro,
  NextBinding = NEXT_BINDING,
  UpdateInterval = UPDATE_INTERVAL,
  Bind = Bind,
  SafeString = SafeString,
  SpellName = SpellName,
  SpellIcon = SpellIcon,
  CooldownLeft = CooldownLeft,
  FocusLine = FocusLine,
  ScanConfirmsGroupBuffed = ScanConfirmsGroupBuffed,
  Missing = Missing,
  Valid = Valid,
  Single = Single,
  Buffs = myBuffs,
  BlessingsByClass = myBlessing,
  Entries = entries,
  Ranks = ranks,
  RAID = RAID, PARTY = PARTY, PLATES = PLATES,
  EntryCount = function() return nEntries end,
  HasAnyBuff = function() return hasAnyBuff end,
  BookCount = function() return bookCount end,
  LastError = function() return lastError end,
  SessionShow = function() return sessionShow end,
  SetSessionShow = function(shown) sessionShow = shown end,
}
