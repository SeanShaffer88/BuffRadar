-- One bounded local preference restore point; no automatic restoration.
-- Copyright (C) 2026 Malikor. GPLv3 or later.
local _, ns = ...
local X = ns.X
local R = {}
X.Recovery = R
local limitBytes, limitNodes, limitDepth = 32768, 2048, 6
local serial, pending, captureReason = 0, nil, nil
local function Readable(v)
  if type(v)=="nil" then return true end
  if X.Readable then return X.Readable(v) end
  return not issecretvalue or not issecretvalue(v)
end
local function Clone(v,depth,budget)
  if not Readable(v) then error("invalid",0) end
  local kind=type(v)
  budget.nodes=budget.nodes+1
  if budget.nodes>budget.maxNodes or depth>budget.maxDepth then error("limit",0) end
  if kind=="nil" or kind=="boolean" then budget.bytes=budget.bytes+8
  elseif kind=="number" then
    if v~=v or v==math.huge or v==-math.huge then error("invalid",0) end
    budget.bytes=budget.bytes+32
  elseif kind=="string" then budget.bytes=budget.bytes+2+#v*4
  elseif kind=="table" then
    if getmetatable(v) then error("invalid",0) end
    budget.bytes=budget.bytes+16
    local out={}
    for key,value in pairs(v) do
      if type(key)~="string" and type(key)~="number" then error("invalid",0) end
      out[Clone(key,depth+1,budget)]=Clone(value,depth+1,budget)
    end
    if budget.bytes>budget.maxBytes then error("limit",0) end
    return out
  else error("invalid",0) end
  if budget.bytes>budget.maxBytes then error("limit",0) end
  return v
end
function R.Copy(v)
  local ok,value=pcall(Clone,v,0,{bytes=256,nodes=0,maxBytes=limitBytes,maxNodes=limitNodes,maxDepth=limitDepth})
  if not ok then return nil,"limit" end
  return value
end
-- Clipboard grammar already caps source text at 16 KiB. Its detached review
-- also includes the recipient's bounded maps and human-readable diff lines.
function R.CopyProfile(v)
  local ok,value=pcall(Clone,v,0,{bytes=256,nodes=0,maxBytes=262144,maxNodes=8192,maxDepth=8})
  if not ok then return nil,"limit" end
  return value
end
function R.Equal(a,b)
  if type(a)~=type(b) then return false end
  if type(a)~="table" then return a==b end
  for key,value in pairs(a) do if not R.Equal(value,b[key]) then return false end end
  for key in pairs(b) do if a[key]==nil then return false end end
  return true
end
local function Parts(value)
  if not Readable(value) or type(value)~="string" or #value>32 then return end
  local a,b,c=value:match("^(%d+)%.(%d+)%.(%d+)$")
  if not a then return end
  local out={}
  for i,part in ipairs({a,b,c}) do
    local n=tonumber(part)
    if not n or n>999999 or tostring(n)~=part then return end
    out[i]=n
  end
  return out
end
function R.ValidVersion(value) return Parts(value)~=nil end
function R.CompareVersions(a,b)
  local left,right=Parts(a),Parts(b)
  if not left or not right then return end
  for i=1,3 do if left[i]~=right[i] then return left[i]>right[i] and 1 or -1 end end
  return 0
end
function R.Version()
  local metadata=C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  if type(metadata)~="function" then return end
  local ok,value=pcall(metadata,"BuffRadar","Version")
  if ok and R.ValidVersion(value) then return value end
end
local function Preferences(source,strict)
  if type(source)~="table" or not Readable(source) or getmetatable(source) then return nil,"invalid" end
  local keys=X.Settings.PreferenceKeys()
  local patch={}
  if strict then
    for key in pairs(source) do if not Readable(key) or not keys[key] then return nil,"invalid" end end
  end
  for key in pairs(keys) do
    local value=rawget(source,key)
    if value~=nil then
      if not Readable(value) or type(value)~=type(X.Settings.Defaults[key]) then return nil,"invalid" end
      patch[key]=value
    end
  end
  local copied,why=R.Copy(patch)
  if not copied then return nil,why end
  for key,value in pairs(copied) do
    local ok,clean=pcall(X.Settings.NormalizePreference,key,value)
    if not ok or (type(value)~="number" and not R.Equal(clean,value)) then return nil,"invalid" end
  end
  return copied
end
function R.ValidateRecord(record)
  if type(record)~="table" or not Readable(record) or getmetatable(record) then return {} end
  local format=rawget(record,"format")
  if not Readable(format) or format~=1 then return {} end
  local version=rawget(record,"toVersion")
  if not R.ValidVersion(version) then return {} end
  local bootstrap,prior=rawget(record,"bootstrap"),rawget(record,"fromVersion")
  if not Readable(bootstrap) or not Readable(prior) or (bootstrap~=nil and bootstrap~=true) then return {} end
  if bootstrap then if prior~=nil then return {} end
  elseif not R.ValidVersion(prior) or R.CompareVersions(version,prior)~=1 then return {} end
  local preferences=Preferences(rawget(record,"preferences"),true)
  if not preferences or not next(preferences) then return {} end
  return {format=1,fromVersion=prior,toVersion=version,bootstrap=bootstrap,preferences=preferences}
end
function R.BeforeNormalize(original,current,contract)
  captureReason=nil
  if not R.ValidVersion(current) or (contract and contract.saveState) then return end
  if type(original)~="table" then original={} end
  if not Readable(original) or getmetatable(original) then captureReason="invalid";return end
  local seen=rawget(original,"lastSeenAddonVersion")
  local validSeen=R.ValidVersion(seen)
  local metadata={restorePoint=R.ValidateRecord(rawget(original,"restorePoint")),
    lastSeenAddonVersion=validSeen and seen or current,
    updatesPendingVersion=R.ValidVersion(rawget(original,"updatesPendingVersion")) and rawget(original,"updatesPendingVersion") or "",
    updatesDismissedVersion=R.ValidVersion(rawget(original,"updatesDismissedVersion")) and rawget(original,"updatesDismissedVersion") or ""}
  local preferences,why=Preferences(original,false)
  local exists=preferences and next(preferences)~=nil
  local upgrade=validSeen and R.CompareVersions(current,seen)==1
  if (not validSeen and exists) or upgrade then
    metadata.lastSeenAddonVersion=current
    metadata.updatesPendingVersion=current
    if preferences and exists then
      metadata.restorePoint={format=1,fromVersion=upgrade and seen or nil,toVersion=current,
        bootstrap=not validSeen and true or nil,preferences=preferences}
    else captureReason=why or "empty" end
  elseif not validSeen and not preferences then captureReason=why end
  return metadata
end
function R.Snapshot()
  local db=X.GetDB()
  local record=R.ValidateRecord(db and db.restorePoint)
  return {available=record.format==1,fromVersion=record.fromVersion,toVersion=record.toVersion,
    bootstrap=record.bootstrap==true,reason=captureReason}
end
local function Ready()
  if not X.GetDB() then return false,"generation" end
  local state=X.Settings.SaveState()
  if state then return false,state end
  if InCombatLockdown() or X.PlayerSuspended() then return false,"combat" end
  return true
end
function R.Preview()
  local ok,why=Ready();if not ok then return nil,why end
  local db=X.GetDB()
  local record=R.ValidateRecord(db.restorePoint)
  if record.format~=1 then return nil,"unavailable" end
  local before=Preferences(db,false)
  if not before then return nil,"limit" end
  local patch=X.Settings.PreparePatch(db,record.preferences)
  serial=serial+1
  pending={id=serial,db=db,generation=X.Preferences.Generation(),before=before,record=record,patch=patch}
  return {id=serial,lines=X.ReviewSettings(patch),fromVersion=record.fromVersion,toVersion=record.toVersion,bootstrap=record.bootstrap==true}
end
function R.Apply(review)
  local ok,why=Ready();if not ok then return false,why end
  if type(review)~="table" or not pending or not Readable(review.id) or review.id~=pending.id then return false,"invalid" end
  local draft=pending
  if draft.db~=X.GetDB() or draft.generation~=X.Preferences.Generation() then return false,"generation" end
  local current=Preferences(draft.db,false)
  if not current or not R.Equal(current,draft.before) or not R.Equal(R.ValidateRecord(draft.db.restorePoint),draft.record) then return false,"conflict" end
  local applied,reason=X.Preferences.Transaction(draft.patch,"other")
  if applied then pending=nil end
  return applied,reason
end
X.OnDBLoaded(function() pending=nil end)
