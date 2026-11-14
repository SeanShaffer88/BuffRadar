-- BuffRadar - Profiles: export/import strings, buff plans, saved profiles and
-- presets (/br export, import, plan, profile, preset). Split out of
-- BuffRadar.lua (file split Slice E). Loaded after BuffRadar.lua; talks to it
-- only through the shared X table.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, NS = ...
local X = NS and NS.X
if not X then return end

local BLESSINGS, DEFAULTS, Ignore = X.BLESSINGS, X.DEFAULTS, X.Ignore
local Esc, Unesc, SanitizeDB = X.Esc, X.Unesc, X.SanitizeDB
local IsProfileName, PROFILE_MAX_BYTES = X.IsProfileName, X.PROFILE_MAX_BYTES
local math_floor, math_huge, math_max = math.floor, math.huge, math.max
local string_format, table_sort = string.format, table.sort

function X.Export()
  local db = X.GetDB()
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
  local db = X.GetDB()
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

-- BR2 is the named profile format. Keep BR1 exports readable by older clients.
-- Profile data is deliberately limited to preferences rather than account data,
-- such as stored profiles, custom definitions, character anchors and cast history.
do
  local legacyMaps = { enabled = true, rebuffPer = true, ignored = true }
  local profileMaps = {
    enabled = "boolean", rebuffPer = "number", ignored = "boolean",
    alertSounds = "sound", buffPrio = "priority", coverParts = "boolean",
    rowColors = "color", buffContext = "context", specScales = "number",
    blessingPreferences = "blessing",
  }
  local scalarKeys, scalarList, legacyScalars = {}, {}, {}
  for _, key in ipairs(X.EXPORT_KEYS) do
    if type(DEFAULTS[key]) ~= "table" then
      scalarKeys[key], legacyScalars[key] = true, true
      scalarList[#scalarList + 1] = key
    end
  end
  for _, key in ipairs({
    "compact", "textScale", "charPoint", "pauseInBG", "pauseTaxi", "watchDrop",
    "minimapAngle", "rangeText", "pinned",
  }) do
    scalarKeys[key] = true
    scalarList[#scalarList + 1] = key
  end

  local function Encode(value)
    if type(value) == "boolean" then return value and "1" or "0" end
    if type(value) == "table" then return table.concat(value, ",", 1, 3) end
    return Esc(value)
  end

  function X.ProfileSnapshot()
    local db = X.GetDB()
    local parts = { "bgColor=" .. Encode(db.bgColor), "blessingPreferences=1" }
    for _, key in ipairs(scalarList) do
      parts[#parts + 1] = key .. "=" .. Encode(db[key])
    end
    local bytes = #"BR2;" + #table.concat(parts, ";")
    for map in pairs(profileMaps) do
      for key, value in pairs(db[map]) do
        local field = map .. "." .. Esc(key) .. "=" .. Encode(value)
        bytes = bytes + 1 + #field
        if bytes > PROFILE_MAX_BYTES then return nil end
        parts[#parts + 1] = field
      end
    end
    if bytes > PROFILE_MAX_BYTES then return nil end
    table_sort(parts)
    return "BR2;" .. table.concat(parts, ";")
  end

  local function Number(raw)
    local n = tonumber(raw)
    if n and n == n and n ~= math_huge and n ~= -math_huge then return n end
  end

  local function Decode(kind, key, raw)
    if kind == "boolean" then
      if raw == "1" then return true end
      if raw == "0" then return false end
    elseif kind == "number" then
      return Number(raw)
    elseif kind == "string" then
      return Unesc(raw)
    elseif kind == "color" then
      local r, g, b = raw:match("^([^,]+),([^,]+),([^,]+)$")
      r, g, b = Number(r), Number(g), Number(b)
      if r and g and b and r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1 then
        return { r, g, b }
      end
    elseif kind == "sound" then
      if (key == "new" or key == "drop" or key == "ask" or key == "fall")
         and (raw == "droplet" or raw == "system" or raw == "none") then return raw end
    elseif kind == "priority" then
      local buff = Unesc(raw)
      if #buff > 0 and #buff <= 40 then return buff end
    elseif kind == "context" then
      if raw == "raid" or raw == "instance" then return raw end
    elseif kind == "blessing" then
      if X.BLESSING_CLASSES[key] and BLESSINGS[raw] then return raw end
    end
  end

  function X.ParseProfile(body)
    if type(body) ~= "string" or #body > PROFILE_MAX_BYTES then return nil end
    local version, payload = body:match("^(BR[12]);(.+)$")
    if not version then return nil end
    local modern = version == "BR2"
    local patch, count, scalarFields, priorityKeys = {}, 0, {}, {}
    for map in pairs(modern and profileMaps or legacyMaps) do patch[map] = {} end
    for field in (payload .. ";"):gmatch("(.-);") do
      local key, raw = field:match("^([^=]+)=(.*)$")
      if not key then return nil end
      local map, member = key:match("^(%a+)%.(.*)$")
      local kind = map and profileMaps[map]
      if kind and (modern or legacyMaps[map]) then
        member = Unesc(member)
        if member == "" then return nil end
        if map == "buffPrio" then
          member = Number(member)
          if not member or member < 1 or member > 24 or member ~= math_floor(member) then return nil end
        elseif map == "rowColors" and member ~= "mine" and member ~= "tank"
           and member ~= "expiring" and member ~= "buddy" then return nil
        end
        local value = Decode(kind, member, raw)
        if value == nil or patch[map][member] ~= nil or (map == "rebuffPer" and value < 0) then
          return nil
        end
        if map == "buffPrio" then
          if priorityKeys[value] then return nil end
          priorityKeys[value] = true
        end
        patch[map][member] = value
        count = count + 1
      elseif modern and key == "blessingPreferences" then
        if raw ~= "1" or scalarFields[key] then return nil end
        scalarFields[key] = true
      elseif key == "bgColor" or (modern and scalarKeys[key]) or legacyScalars[key] then
        local value = Decode(key == "bgColor" and "color" or type(DEFAULTS[key]), key, raw)
        if value == nil or scalarFields[key] or not X.ProfileScalarValid(key, value) then return nil end
        patch[key], scalarFields[key] = value, true
        count = count + 1
      elseif modern then
        return nil
      end
    end
    if count == 0 then return nil end
    if modern then
      if not scalarFields.blessingPreferences then
        if next(patch.blessingPreferences) then return nil end
        patch.blessingPreferences = nil  -- older BR2 profiles leave the preference alone
      end
      if not patch.bgColor then return nil end
      for _, key in ipairs(scalarList) do if not scalarFields[key] then return nil end end
      local highest, priorityCount = 0, 0
      for index in pairs(patch.buffPrio) do
        highest, priorityCount = math_max(highest, index), priorityCount + 1
      end
      if highest ~= priorityCount then return nil end
    end
    return patch
  end

  function X.ApplyProfile(patch)
    local db = X.GetDB()
    -- Normalize the complete proposed state before changing the live settings.
    local candidate = {}
    for key, value in pairs(db) do candidate[key] = value end
    for key, value in pairs(patch) do candidate[key] = value end
    SanitizeDB(candidate)
    for key in pairs(patch) do db[key] = candidate[key] end
    X.prioDirty = true
    Ignore.Rebuild()
  end
end

-- Buff plan strings (1.8.0): the group's plan — assignments, the
-- blessing plan and the auto-profile map — as one copyable string, so a
-- plan built on one character can be handed to another BuffRadar user.
-- Personal settings are NOT part of it; use profiles for those.
function X.PlanExport()
  local db = X.GetDB()
  local parts = { "BRPLAN1" }
  local keys = {}
  for k in pairs(X.assign) do keys[#keys + 1] = k end
  table_sort(keys)
  for _, k in ipairs(keys) do
    parts[#parts + 1] = "A;" .. Esc(k) .. ";" .. Esc(X.assign[k])
  end
  local classes = {}
  for c in pairs(X.blessPlan) do classes[#classes + 1] = c end
  table_sort(classes)
  for _, c in ipairs(classes) do
    local p = X.blessPlan[c]
    parts[#parts + 1] = "B;" .. Esc(c) .. ";" .. Esc(p.key) .. ";" .. Esc(p.name)
  end
  local ctxs = {}
  for c in pairs(db.autoProfile) do ctxs[#ctxs + 1] = c end
  table_sort(ctxs)
  for _, c in ipairs(ctxs) do
    parts[#parts + 1] = "P;" .. Esc(c) .. ";" .. Esc(db.autoProfile[c])
  end
  return table.concat(parts, ";")
end

function X.PlanImport(text)
  local db = X.GetDB()
  if type(text) ~= "string" then return false, "Nothing to import." end
  local fields = {}
  for part in (text .. ";"):gmatch("(.-);") do fields[#fields + 1] = part end
  if fields[1] ~= "BRPLAN1" then
    return false, "That doesn't look like a BuffRadar plan string."
  end
  local nA, nB, nP = 0, 0, 0
  local i = 2
  while i <= #fields do
    local tag = fields[i]
    if tag == "A" and fields[i + 2] then
      X.assign[Unesc(fields[i + 1])] = Unesc(fields[i + 2])
      nA = nA + 1
      i = i + 3
    elseif tag == "B" and fields[i + 3] then
      local cls, bkey, holder = Unesc(fields[i + 1]), Unesc(fields[i + 2]),
        Unesc(fields[i + 3])
      if BLESSINGS[bkey] then
        local me = Ignore.UnitNames("player")
        X.blessPlan[cls] = { key = bkey, name = holder,
          mine = me ~= nil and Ignore.Key(holder) == Ignore.Key(me) }
        nB = nB + 1
      end
      i = i + 4
    elseif tag == "P" and fields[i + 2] then
      db.autoProfile[Unesc(fields[i + 1])] = Unesc(fields[i + 2])
      nP = nP + 1
      i = i + 3
    else
      i = i + 1
    end
  end
  -- Share the plan onward, so the group converges on the same plan.
  if nA > 0 and X.AmLead() then
    for k, v in pairs(X.assign) do X.Broadcast("ASSIGN;" .. k .. ";" .. v) end
  end
  if nB > 0 then
    local _, myClass = UnitClass("player")
    if X.AmLead() or myClass == "PALADIN" then
      for c, p in pairs(X.blessPlan) do
        X.Broadcast("BLESS;" .. c .. ";" .. p.key .. ";" .. p.name)
      end
    end
  end
  -- (No repaint here: the import window's accept button repaints on OK.)
  if RefreshConfig then RefreshConfig() end
  return true, string_format("Plan imported: %d assignments, %d blessings, %d auto profiles.",
    nA, nB, nP)
end

-- Share a single profile (1.8.0): one named profile (not all your
-- settings) as a copyable text — a header line naming it, then its
-- settings string. Importing stores it under that name, unapplied.
function X.ProfileShareText(name)
  local db = X.GetDB()
  local s = db.profiles[name]
  if not IsProfileName(name) or not X.ParseProfile(s) then return nil end
  return "BuffRadar profile: " .. name .. "\n" .. s
end

function X.ProfileImport(text)
  local db = X.GetDB()
  if type(text) ~= "string" then return false, "Nothing to import." end
  if #text > PROFILE_MAX_BYTES + #"BuffRadar profile: " + 42 then
    return false, "That shared profile is too large."
  end
  local name, body = text:match("^BuffRadar profile: ([%w_%-]+)\r?\n(.+)$")
  if not IsProfileName(name) then
    return false, "That doesn't look like a shared BuffRadar profile."
  end
  body = body:match("^%s*(.-)%s*$")
  if not X.ParseProfile(body) then
    return false, "The profile's settings string is damaged."
  end
  db.profiles[name] = body
  if RefreshConfig then RefreshConfig() end
  return true, "Profile imported: " .. name
    .. " — /br profile load " .. name .. " applies it."
end

function X.SaveProfile(name)
  local db = X.GetDB()
  if not IsProfileName(name) then
    return false, "Profile names use letters, numbers, - and _ (max 40)."
  end
  local body = X.ProfileSnapshot()
  if not body then return false, "These settings are too large to save as a profile." end
  if not X.ParseProfile(body) then return false, "The current settings cannot be saved as a profile." end
  db.profiles[name] = body
  return true
end

function X.LoadProfile(name)
  local db = X.GetDB()
  local s = db.profiles[name]
  if type(s) ~= "string" then return false end
  local patch = X.ParseProfile(s)
  if not patch then return false, "The profile's settings string is damaged." end
  X.ApplyProfile(patch)
  return true
end

function X.DeleteProfile(name)
  local db = X.GetDB()
  if db.profiles[name] == nil then return false end
  db.profiles[name] = nil
  return true
end

function X.ProfileNames()
  local db = X.GetDB()
  local names = {}
  for name in pairs(db.profiles) do names[#names + 1] = name end
  table_sort(names)
  return names
end

-- Shipped presets (1.6.0, replacing a proposed buff-next keybind -- the
-- BuffRadarNextButton binding already ships): one-click window/behavior
-- setups. They touch only the keys listed, never buff toggles or timings,
-- so they compose with spec profiles and named profiles.

function X.ApplyPreset(name)
  local db = X.GetDB()
  local p = X.PRESETS[name]
  if not p then return false end
  for k, v in pairs(p) do
    if DEFAULTS[k] ~= nil and type(v) == type(DEFAULTS[k]) then db[k] = v end
  end
  return true
end
