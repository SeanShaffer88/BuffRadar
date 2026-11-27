-- BuffRadar - settings and plan strings, saved profiles and presets.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, ns = ...
local X = ns.X
local L = X.L
local wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end end

local settings = X.Settings
local BLESSINGS, DEFAULTS, Ignore = X.BLESSINGS, settings.Defaults, X.Ignore
local IsProfileName, PROFILE_MAX_BYTES = settings.IsProfileName, settings.ProfileMaxBytes
local math_floor, math_huge, math_max = math.floor, math.huge, math.max
local string_format, table_sort = string.format, table.sort
local CLIPBOARD_MAX_BYTES = 16384

-- Settings export / import: one copyable string. Covers the window look,
-- behavior toggles, buff toggles, rebuff timings and both ignore sets --
-- not positions, cast counts or stats (those belong to one machine / char).
local EXPORT_KEYS = { "locked", "includeSelf", "avoidPvP", "autoHide", "rebuff", "scale",
  "width", "cfgScale", "castMethod", "clickReg", "bgAlpha", "showTitle", "showBorder",
  "playSound", "showCounter", "groupOnly", "pauseInCities", "groupCast", "groupCastMin",
  "sortMode", "alertSound", "alertSounds", "buffPrio", "clickThrough", "muteInInstance", "showMinimap", "lowMana",
  "sync", "requests", "joinDigest", "roleFilter", "showStrip", "idleFade",
  "pill", "queueTag", "consumables", "buddySplit", "readyPost", "weaponWatch", "enterFlash",
  "scanThrottle", "growUp", "theme", "autoThemePriority", "findBox", "durationBars", "raidMarkers",
  "focusWatch", "pets", "auraWatch", "worldWatch", "drinkWatch", "twoCol",
  "deathRecap", "wipeReport", "rowGap", "iconSize",
  "tooltipLevel", "viewMode", "classColors", "showRealm", "nameTrim",
  "scalePerSpec", "gripSnap", "tagSymbols", "reduceMotion", "rangeWatch", "assumeRange",
  "fastAura", "modClick", "pullFlash", "fallSound", "simpleMode", "performanceMode" }

local function Esc(v) return (tostring(v):gsub("%%", "%%25"):gsub(";", "%%3B"):gsub("=", "%%3D")) end
local function Unesc(v) return (v:gsub("%%3D", "="):gsub("%%3B", ";"):gsub("%%25", "%%")) end

local function ClipboardText(text)
  if type(text) ~= "string" then return nil, L["Nothing to import."] end
  if #text > CLIPBOARD_MAX_BYTES then return nil, L["That import exceeds 16 KiB."] end
  text = text:match("^%s*(.-)%s*$")
  if text == "" then return nil, L["Nothing to import."] end
  return text
end

local function DecodeString(text)
  local value = Unesc(text)
  if not value:find("[%z\1-\31\127]") and Esc(value) == text then return value end
end

local function ClipboardExport(parts)
  local body = table.concat(parts, ";")
  if #body > CLIPBOARD_MAX_BYTES then return nil, L["That export exceeds 16 KiB."] end
  return body
end

function X.Export()
  local db = X.GetDB()
  local parts = { "BR1", "complete=1" }
  for _, k in ipairs(EXPORT_KEYS) do
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
  parts[#parts + 1] = "endExport=1"
  return ClipboardExport(parts)
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
    blessingPreferences = "blessing", rankCap = "rank",
  }
  local scalarKeys, scalarList, legacyScalars = {}, {}, {}
  -- Fields common to every full BR1 export since the original 1.4 writer.
  local legacyRequired = {
    "locked", "includeSelf", "avoidPvP", "autoHide", "rebuff", "scale",
    "width", "cfgScale", "castMethod", "clickReg", "bgAlpha", "showTitle",
    "showBorder", "playSound", "showCounter", "groupOnly", "pauseInCities",
    "groupCast", "groupCastMin", "sortMode", "alertSound", "muteInInstance",
    "showMinimap", "lowMana", "bgColor",
  }
  local retiredScalars = { strata = "string", showOutOfRange = "boolean",
    hideInCombat = "boolean", rangeText = "boolean" }
  local retiredLayers = { LOW = true, MEDIUM = true, HIGH = true, DIALOG = true }
  for _, key in ipairs(EXPORT_KEYS) do
    if type(DEFAULTS[key]) ~= "table" then
      scalarKeys[key], legacyScalars[key] = true, true
      scalarList[#scalarList + 1] = key
    end
  end
  for _, key in ipairs({
    "compact", "textScale", "charPoint", "pauseInBG", "pauseTaxi", "watchDrop",
    "minimapAngle", "pinned", "thornsAnyClassOutdoors", "blessingComplement",
  }) do
    scalarKeys[key] = true
    scalarList[#scalarList + 1] = key
  end

  -- Older BR2 profiles leave these controls unchanged. New snapshots carry
  -- them explicitly. Instance/debuff/consumable IDs remain local settings.
  local featureScalars = { forecastSeconds = true, smartPriority = true, statusMinimap = true,
    visualAlerts = true, liteMode = true }
  for key in pairs(featureScalars) do
    scalarKeys[key] = true
    scalarList[#scalarList + 1] = key
  end
  local optionalFalse = { thornsAnyClassOutdoors = true, blessingComplement = true }

  local function Encode(value)
    if type(value) == "boolean" then return value and "1" or "0" end
    if type(value) == "table" then return table.concat(value, ",", 1, 3) end
    return Esc(value)
  end

  function X.ProfileSnapshot(scope, source)
    local db = source or X.GetDB()
    local excluded=scope=="preferences"
    local parts = { "bgColor=" .. Encode(db.bgColor), "blessingPreferences=1" }
    if scope then parts[#parts+1]="identity=" .. (excluded and "excluded" or "included") end
    for _, key in ipairs(scalarList) do
      if not (excluded and key=="pinned") and (not optionalFalse[key] or db[key]) then
        parts[#parts + 1] = key .. "=" .. Encode(db[key])
      end
    end
    local bytes = #"BR2;" + #table.concat(parts, ";")
    local mode = "buffAssignments=" .. (db.assignmentEnabled and "1" or "0")
    parts[#parts + 1], bytes = mode, bytes + 1 + #mode
    for class, row in pairs(db.buffAssignments) do
      for slot, cell in pairs(row) do
        local field = "a." .. class .. "." .. slot .. "=" .. X.EncodeAssignment(cell)
        bytes = bytes + 1 + #field
        if bytes > PROFILE_MAX_BYTES then return nil end
        parts[#parts + 1] = field
      end
    end
    for map in pairs(profileMaps) do
      for key, value in pairs((excluded and map=="ignored") and {} or db[map]) do
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
      return DecodeString(raw)
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
      local buff = DecodeString(raw)
      if buff and #buff > 0 and #buff <= 40 then return buff end
    elseif kind == "context" then
      if raw == "raid" or raw == "instance" then return raw end
    elseif kind == "blessing" then
      if X.BLESSING_CLASSES[key] and BLESSINGS[raw] then return raw end
    elseif kind == "rank" then
      local rank = raw:match("^%d%d?$") and tonumber(raw)
      if rank and rank >= 1 and rank <= 20 then return rank end
    end
  end

  local function BoundedMapMember(map, member)
    if map == "ignored" then return settings.ValidIgnore(member) end
    if map == "enabled" or map == "rebuffPer" or map == "buffContext" or map == "rankCap" then
      return #member <= 40 and member:match("^[A-Z0-9_]+$")
    end
    if map == "specScales" then return member:match("^s[1-4]$") end
    if map == "coverParts" then return settings.PlainString(member, 24) end
    return true
  end

  local function ParseProfile(body, directImport)
    if type(body) ~= "string" or #body > (directImport and CLIPBOARD_MAX_BYTES or PROFILE_MAX_BYTES) then return nil end
    local version, payload = body:match("^(BR[12]);(.+)$")
    if not version then return nil end
    local modern = version == "BR2"
    local patch, count, scalarFields, priorityKeys = {}, 0, {}, {}
    local assignments, sizes = {}, {}
    if modern then
      for map in pairs(profileMaps) do patch[map] = {} end
    end
    local firstField = true
    for field in (payload .. ";"):gmatch("(.-);") do
      if scalarFields.endExport then return nil end
      local key, raw = field:match("^([^=]+)=(.*)$")
      if not key then return nil end
      local map, member = key:match("^(%a+)%.(.*)$")
      local kind = map and profileMaps[map]
      if modern and key=="identity" then
        if scalarFields.identity or (raw~="excluded" and raw~="included") then return nil end
        scalarFields.identity=raw
      elseif modern and map == "a" then
        local class, slot = member:match("^([A-Z]+)%.([A-Z]+)$")
        if not X.ValidAssignmentCell(class, slot) then return nil end
        local cell = X.DecodeAssignment(raw)
        if cell == nil then return nil end
        local row = assignments[class] or {}
        if row[slot] ~= nil then return nil end
        row[slot], assignments[class] = cell, row
        count = count + 1
      elseif modern and key == "buffAssignments" then
        if (raw ~= "1" and raw ~= "0") or scalarFields[key] then return nil end
        patch.assignmentEnabled, scalarFields[key] = raw == "1", true
      elseif kind and (modern or legacyMaps[map]) then
        member = DecodeString(member)
        if not member or member == "" or not BoundedMapMember(map, member) then return nil end
        local limit = settings.Limits[map]
        if limit then
          sizes[map] = (sizes[map] or 0) + 1
          if sizes[map] > limit then return nil end
        end
        patch[map] = patch[map] or {}
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
        if value == nil or scalarFields[key] or not settings.ProfileScalarValid(key, value) then return nil end
        patch[key], scalarFields[key] = value, true
        count = count + 1
      elseif (modern and key == "strata") or (not modern and retiredScalars[key]) then
        local value = Decode(retiredScalars[key], key, raw)
        if value == nil or scalarFields[key] or (key == "strata" and not retiredLayers[value]) then return nil end
        scalarFields[key] = true
      elseif not modern and (key == "complete" or key == "endExport") then
        if raw ~= "1" or scalarFields[key] or (key == "complete" and not firstField) then return nil end
        scalarFields[key] = true
      else
        return nil
      end
      firstField = false
    end
    if count == 0 then return nil end
    if modern then
      if directImport and not scalarFields.identity then return nil end
      if scalarFields.identity=="excluded" then
        if scalarFields.pinned or next(patch.ignored) then return nil end
        patch.ignored=nil
      end
      if scalarFields.buffAssignments then
        patch.buffAssignments = assignments
      elseif next(assignments) then
        return nil
      end
      if not scalarFields.blessingPreferences then
        if next(patch.blessingPreferences) then return nil end
        patch.blessingPreferences = nil  -- older BR2 profiles leave the preference alone
      end
      if not patch.bgColor then return nil end
      for _, key in ipairs(scalarList) do
        if not scalarFields[key] and key ~= "autoThemePriority" and not featureScalars[key]
          and not (key=="pinned" and scalarFields.identity=="excluded") then
          if optionalFalse[key] or (key == "assumeRange" and scalarFields.strata) then
            patch[key] = false
          else
            return nil
          end
        end
      end
      local highest, priorityCount = 0, 0
      for index in pairs(patch.buffPrio) do
        highest, priorityCount = math_max(highest, index), priorityCount + 1
      end
      if highest ~= priorityCount then return nil end
    else
      if scalarFields.complete ~= scalarFields.endExport then return nil end
      local complete = true
      for _, key in ipairs(legacyRequired) do
        if not scalarFields[key] then complete = false; break end
      end
      if (directImport or scalarFields.complete) and not complete then return nil end
      if scalarFields.complete then
        for key in pairs(legacyScalars) do
          if not scalarFields[key] and key ~= "autoThemePriority" and not featureScalars[key] then return nil end
        end
      end
      if complete then
        for map in pairs(legacyMaps) do patch[map] = patch[map] or {} end
      end
    end
    for _, key in ipairs({ "enabled", "rebuffPer", "rankCap", "ignored", "specScales", "buffContext", "coverParts" }) do
      if patch[key] and settings.Count(patch[key]) > settings.Limits[key] then return nil end
    end
    return patch
  end

  X.ParseProfile = ParseProfile

  function X.ParseSettingsImport(text)
    local body, err = ClipboardText(text)
    if not body then return nil, err end
    local patch = ParseProfile(body, true)
    if not patch then return nil, L["Paste a complete, valid BuffRadar settings export."] end
    return patch, body
  end

  local function Changes(dst, path, before, after)
    if before == after then return end
    if type(before) == "table" or type(after) == "table" then
      before = type(before) == "table" and before or {}
      after = type(after) == "table" and after or {}
      for k, v in pairs(before) do Changes(dst, path .. "." .. k, v, after[k]) end
      for k, v in pairs(after) do if before[k] == nil then Changes(dst, path .. "." .. k, nil, v) end end
    else
      dst[#dst + 1] = string_format("%s: %s → %s", path, tostring(before), tostring(after))
    end
  end

  function X.ReviewSettings(patch)
    local db, lines = X.GetDB(), {}
    local candidate = settings.PreparePatch(db, patch)
    for key in pairs(patch) do Changes(lines, key, db[key], candidate[key]) end
    table_sort(lines)
    return lines
  end

  function X.ApplyProfile(patch)
    if settings.SaveState()=="future" then return false,"future" end
    local db = X.GetDB()
    local candidate = settings.PreparePatch(db, patch)
    local changed, delta = {}, {}
    for key in pairs(patch) do
      Changes(delta, key, db[key], candidate[key])
      if #delta > 0 then changed[key] = true end
      wipe(delta)
    end
    X.blockerProfileRevision = (X.blockerProfileRevision or 0) + 1
    X.assignmentGroupConflicts = nil
    if not next(changed) then return end
    for key in pairs(changed) do db[key] = candidate[key] end
    changed.profile = true
    if changed.buffPrio then X.prioDirty = true end
    if changed.ignored then Ignore.Rebuild() end
    X.SettingsChanged(changed)
    X.ResolveAutoTheme()
  end
end

function X.Import(text)
  local patch, result = X.ParseSettingsImport(text)
  if not patch then return false, result end
  local ok,why=X.ApplyProfile(patch)
  if ok==false then return false,why end
  return true, L["Settings applied locally."]
end

-- Parse the complete original format before projecting any selected sections.
do
  local S, registry = {}, {appearance={},alerts={},buffrules={}}
  X.ProfileSections=S
  local definitions={
    appearance="locked autoHide scale width cfgScale bgAlpha bgColor showTitle showBorder showCounter clickThrough showMinimap showStrip idleFade pill queueTag growUp theme autoThemePriority findBox durationBars raidMarkers twoCol compact textScale rowGap iconSize tooltipLevel viewMode classColors showRealm nameTrim scalePerSpec gripSnap tagSymbols reduceMotion charPoint coverParts rowColors specScales consumables",
    alerts="playSound alertSound alertSounds muteInInstance enterFlash pullFlash fallSound watchDrop rangeWatch visualAlerts statusMinimap deathRecap",
    buffrules="enabled rebuff rebuffPer rankCap buffPrio buffContext blessingPreferences buffAssignments assignmentEnabled thornsAnyClassOutdoors blessingComplement includeSelf avoidPvP castMethod clickReg groupOnly pauseInCities pauseInBG pauseTaxi groupCast groupCastMin sortMode lowMana roleFilter weaponWatch focusWatch pets auraWatch worldWatch drinkWatch scanThrottle fastAura modClick forecastSeconds smartPriority liteMode simpleMode performanceMode debuffWatch readinessAura assumeRange",
  }
  for section,keys in pairs(definitions) do
    for key in keys:gmatch("%S+") do registry[section][key]=true end
  end
  local serial,pending=0,nil
  function S.Registry() return X.Recovery.CopyProfile(registry) end
  function S.Filter(patch,selection)
    local copied=X.Recovery.CopyProfile(patch)
    if type(copied)~="table" then return nil,"invalid" end
    if selection==nil then return copied end -- explicit whole-profile mode
    local selected=X.Recovery.CopyProfile(selection)
    if type(selected)~="table" then return nil,"invalid" end
    local any,out=false,{}
    for section,value in pairs(selected) do
      if not registry[section] or type(value)~="boolean" then return nil,"invalid" end
      if value then
        any=true
        for key in pairs(registry[section]) do if copied[key]~=nil then out[key]=copied[key] end end
      end
    end
    if not any or not next(out) then return nil,"empty" end
    return out
  end
  local function Ready()
    if not X.GetDB() then return false,"generation" end
    local state=settings.SaveState();if state then return false,state end
    if InCombatLockdown() or X.PlayerSuspended() then return false,"combat" end
    return true
  end
  function S.Stage(text,selection)
    local ready,why=Ready();if not ready then return nil,why end
    if not X.Readable(text) or type(text)~="string" then return nil,"invalid" end
    local ok,parsed=pcall(function()
      if text:match("^BuffRadar profile: ") then
        local shared=X.ParseSharedProfile(text)
        return shared and shared.patch
      end
      return X.ParseSettingsImport(text)
    end)
    if not ok or not parsed then return nil,"invalid" end
    local patch,reason=S.Filter(parsed,selection)
    if not patch then return nil,reason end
    local db,before=X.GetDB(),{}
    for key in pairs(patch) do before[key]=db[key] end
    before=X.Recovery.CopyProfile(before)
    if not before then return nil,"limit" end
    serial=serial+1
    local keys={};for key in pairs(patch) do keys[#keys+1]=key end;table_sort(keys)
    local model={id=serial,lines=X.ReviewSettings(patch),keys=keys,all=selection==nil,
      identityIncluded=patch.ignored~=nil or patch.pinned~=nil}
    pending={id=serial,db=db,generation=X.Preferences.Generation(),before=before,patch=patch,model=model}
    return X.Recovery.CopyProfile(model)
  end
  function S.Review(draft)
    local ready,why=Ready();if not ready then return nil,why end
    if type(draft)~="table" or not pending or not X.Readable(draft.id) or draft.id~=pending.id then return nil,"invalid" end
    if pending.db~=X.GetDB() or pending.generation~=X.Preferences.Generation() then return nil,"generation" end
    local before={};for key in pairs(pending.patch) do before[key]=pending.db[key] end
    before=X.Recovery.CopyProfile(before)
    if not before or not X.Recovery.Equal(before,pending.before) then return nil,"conflict" end
    return X.Recovery.CopyProfile(pending.model)
  end
  function S.Apply(draft)
    local reviewed,why=S.Review(draft);if not reviewed then return false,why end
    local owned=pending
    local revision=X.blockerProfileRevision
    local ok,result,reason=pcall(X.ApplyProfile,owned.patch)
    if not ok or result==false then
      for key,value in pairs(owned.before) do owned.db[key]=value end
      X.blockerProfileRevision=revision
      pcall(X.Ignore.Rebuild);pcall(X.SettingsChanged,{profile=true})
      return false,reason or "invalid"
    end
    pending=nil;return true
  end
  X.OnDBLoaded(function() pending=nil end)
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
  return ClipboardExport(parts)
end

local planContexts = { raid = true, dungeon = true, pvp = true, world = true, solo = true }

local function PlanHolder(value)
  return value and #value <= 128 and value:match("^%S") and value:match("%S$")
    and not value:find("[%c;|]")
end

local function ParsePlan(text)
  local fields = {}
  for part in (text .. ";"):gmatch("(.-);") do fields[#fields + 1] = part end
  if fields[1] ~= "BRPLAN1" then return nil end
  local assignments, blessings, auto = {}, {}, {}
  local i = 2
  while i <= #fields do
    local tag = fields[i]
    if not fields[i + 2] then return nil end
    local key, value = DecodeString(fields[i + 1]), DecodeString(fields[i + 2])
    if not key or not value then return nil end
    if tag == "A" then
      if #key > 40 or not key:match("^[A-Z0-9_]+$") or not PlanHolder(value) or assignments[key] then return nil end
      assignments[key] = value
      i = i + 3
    elseif tag == "B" then
      local holder = fields[i + 3] and DecodeString(fields[i + 3])
      if not X.BLESSING_CLASSES[key] or not BLESSINGS[value] or not PlanHolder(holder)
        or holder:lower() == "none" or blessings[key] then return nil end
      blessings[key] = { key = value, name = holder }
      i = i + 4
    elseif tag == "P" then
      if not planContexts[key] or not IsProfileName(value) or auto[key] then return nil end
      auto[key] = value
      i = i + 3
    else
      return nil
    end
  end
  return assignments, blessings, auto
end

function X.ParsePlanImport(text)
  local body, err = ClipboardText(text)
  if not body then return nil, err end
  local assignments, blessings, auto = ParsePlan(body)
  if not assignments then return nil, L["Paste a complete, valid BuffRadar plan export."] end
  return { assignments = assignments, blessings = blessings, auto = auto }
end

function X.ReviewPlan(draft)
  local lines, outbound = {}, {}
  local db = X.GetDB()
  for key, value in pairs(draft.assignments) do
    local nextHolder = value:lower() ~= "none" and value or nil
    if X.assign[key] ~= nextHolder then
      lines[#lines + 1] = string_format("%s: %s → %s", key, X.assign[key] or "—", nextHolder or "—")
      outbound[#outbound + 1] = "ASSIGN;" .. key .. ";" .. value
    end
  end
  for class, plan in pairs(draft.blessings) do
    local before = X.blessPlan[class]
    if not before or before.key ~= plan.key or before.name ~= plan.name then
      lines[#lines + 1] = string_format("%s: %s → %s (%s)", class,
        before and (before.key .. " (" .. before.name .. ")") or "—", plan.key, plan.name)
      outbound[#outbound + 1] = "BLESS;" .. class .. ";" .. plan.key .. ";" .. plan.name
    end
  end
  for context, name in pairs(draft.auto) do
    if db.autoProfile[context] ~= name then
      lines[#lines + 1] = string_format("%s: %s → %s", context, db.autoProfile[context] or "—", name)
    end
    if not db.profiles[name] then
      lines[#lines + 1] = string_format(L["Missing profile for %s: %s"], context, name)
    end
  end
  table_sort(lines)
  table_sort(outbound)
  local scope = db.sync and #outbound > 0 and X.GroupShareScope(outbound) or nil
  return lines, outbound, scope
end

function X.ApplyPlan(draft, shareScope)
  local _, outbound, scope = X.ReviewPlan(draft)
  if shareScope and shareScope ~= scope then return false, L["Group or sharing permission changed. Review the plan again."] end
  local db = X.GetDB()
  local myName = Ignore.UnitNames("player")
  local nA, nB, nP = 0, 0, 0
  for key, value in pairs(draft.assignments) do
    X.SetLocalPlan("ASSIGN", key, value:lower() ~= "none" and value or nil)
    nA = nA + 1
  end
  for class, plan in pairs(draft.blessings) do
    X.SetLocalPlan("BLESS", class, { key = plan.key, name = plan.name,
      mine = myName ~= nil and X.SameUser(plan.name, myName) })
    nB = nB + 1
  end
  for context, name in pairs(draft.auto) do
    db.autoProfile[context] = name
    nP = nP + 1
  end
  local sent = 0
  if shareScope then
    for _, message in ipairs(outbound) do if X.Broadcast(message) then sent = sent + 1 end end
  end
  local outcome = string_format(L["Plan applied locally: %d assignments, %d blessings, %d auto profiles."], nA, nB, nP)
  if shareScope then
    outcome = outcome .. " " .. string_format(L["Game accepted %d of %d sends; delivery is not confirmed."], sent, #outbound)
  end
  return true, outcome
end

function X.PlanImport(text)
  local draft, err = X.ParsePlanImport(text)
  if not draft then return false, err end
  return X.ApplyPlan(draft)
end

-- Share a single profile (1.8.0): one named profile (not all your
-- settings) as a copyable text — a header line naming it, then its
-- settings string. Importing stores it under that name, unapplied.
function X.ProfileShareText(name,scope)
  local preview=X.SharePreview(scope,name)
  return preview and preview.text or nil
end

-- Identity-aware BR2 sharing is structurally separate from legacy full backups.
function X.SharePreview(scope,name)
  scope=scope or "preferences"
  if scope~="preferences" and scope~="full" then return nil,"invalid" end
  local db=X.GetDB()
  if not db then return nil,"generation" end
  local source=db
  if name then
    if not IsProfileName(name) then return nil,"invalid" end
    local patch=X.ParseProfile(db.profiles[name]);if not patch then return nil,"invalid" end
    source={}
    for key,value in pairs(db) do source[key]=value end
    for key,value in pairs(settings.PreparePatch(db,patch)) do source[key]=value end
  end
  local body=X.ProfileSnapshot(scope,source)
  if not body then return nil,"limit" end
  local counts={preferences=0,ignored=0,pinned=0,identitiesExcluded=scope=="preferences"}
  for _ in body:gmatch("[^;]+=[^;]*") do counts.preferences=counts.preferences+1 end
  if scope=="full" then
    for _ in pairs(source.ignored or {}) do counts.ignored=counts.ignored+1 end
    counts.pinned=source.pinned~="" and 1 or 0
  end
  local text=name and ("BuffRadar profile: " .. (scope=="preferences" and "Shared" or name) .. "\n" .. body) or body
  if #text>16384 then return nil,"limit" end
  return {scope=scope,text=text,counts=counts}
end

function X.ParseSharedProfile(text)
  if type(text) ~= "string" then return nil, L["Nothing to import."] end
  if #text > PROFILE_MAX_BYTES + #"BuffRadar profile: " + 42 then
    return nil, L["That shared profile is too large."]
  end
  local name, body = text:match("^BuffRadar profile: ([%w_%-]+)\r?\n(.+)$")
  if not IsProfileName(name) then
    return nil, L["That doesn't look like a shared BuffRadar profile."]
  end
  body = body:match("^%s*(.-)%s*$")
  local patch = X.ParseProfile(body)
  if not patch then return nil, L["The profile's settings string is damaged."] end
  return { name = name, body = body, patch = patch }
end

function X.ProfileMappings(name)
  local used = {}
  for context, mapped in pairs(X.GetDB().autoProfile) do
    if mapped == name then used[#used + 1] = context end
  end
  table_sort(used)
  return used
end

function X.StoreProfile(name, body, reviewedBody)
  local db = X.GetDB()
  if not IsProfileName(name) then
    return false, L["Profile names use letters, numbers, - and _ (max 40)."]
  end
  if not X.ParseProfile(body) then return false, L["The profile's settings string is damaged."] end
  if db.profiles[name] ~= reviewedBody then
    return false, L["That profile already exists or changed. Review it, rename, or explicitly replace it."]
  end
  if not settings.CanAdd(db.profiles, "profiles", name) then
    return false, L["Profile storage is full. Delete a profile first."]
  end
  db.profiles[name] = body
  return true, string_format(L["Profile stored: %s (not loaded)."], name)
end

function X.ProfileImport(text, reviewedBody)
  local draft, err = X.ParseSharedProfile(text)
  if not draft then return false, err end
  return X.StoreProfile(draft.name, draft.body, reviewedBody)
end

function X.SaveProfile(name, reviewedBody)
  local body = X.ProfileSnapshot()
  if not body then return false, L["These settings are too large to save as a profile."] end
  return X.StoreProfile(name, body, reviewedBody)
end

function X.LoadProfile(name)
  local db = X.GetDB()
  local s = db.profiles[name]
  if type(s) ~= "string" then return false end
  local patch = X.ParseProfile(s)
  if not patch then return false, L["The profile's settings string is damaged."] end
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

function X.ProfileCount()
  local live = X.GetDB()
  local profiles = live and rawget(live, "profiles")
  if type(profiles) ~= "table" or getmetatable(profiles) then return nil end
  local count = 0
  for _ in next, profiles do
    count = count + 1
    if count > 1000 then return nil end
  end
  return count
end

-- Shipped presets (1.6.0, replacing a proposed buff-next keybind -- the
-- BuffRadarNextButton binding already ships): one-click window/behavior
-- setups. They touch only the keys listed, never buff toggles or timings,
-- so they compose with spec profiles and named profiles.

function X.ApplyPreset(name)
  local p = X.PRESETS[name]
  if not p then return false end
  X.ApplyProfile(p)
  return true
end
