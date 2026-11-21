-- Bounded session-only history for explicitly ordinary preferences.
-- No identity, cast history, coordinated duties, purchases or network state is stored.
local _, ns = ...
local X = ns.X
local P = {}
X.Preferences = P
local ordinary = {}
for key in ("locked includeSelf avoidPvP autoHide rebuff scale width cfgScale castMethod clickReg bgAlpha showTitle showBorder playSound showCounter groupOnly pauseInCities groupCast groupCastMin sortMode alertSound clickThrough muteInInstance showMinimap lowMana roleFilter showStrip idleFade pill queueTag consumables weaponWatch enterFlash scanThrottle growUp theme autoThemePriority findBox durationBars raidMarkers focusWatch pets auraWatch worldWatch drinkWatch twoCol rowGap iconSize tooltipLevel viewMode classColors showRealm nameTrim scalePerSpec gripSnap tagSymbols reduceMotion rangeWatch assumeRange fastAura modClick pullFlash fallSound compact textScale charPoint pauseInBG pauseTaxi watchDrop forecastSeconds smartPriority statusMinimap visualAlerts liteMode debuffWatch readinessAura rememberPanelPositions matrixView selfStatusStrip restockEnabled restockSpendCap restockUnitCap bgColor enabled rebuffPer buffPrio alertSounds rowColors buffContext specScales restockTargets"):gmatch("%S+") do ordinary[key] = true end
local pass = { sync = true } -- compatibility: explicit existing opt-in, never undoable
local sources = { ui=true, slash=true, slider=true, profile=true, reset=true, other=true }
local history, bytes, serial, generation, active, capturing = {}, 0, 0, 0, nil, false
local function Readable(v) return not X.Readable or X.Readable(v) end
local function Clone(v, depth, budget)
  if not Readable(v) then error("secret",0) end
  local kind = type(v)
  if kind == "nil" or kind == "boolean" then budget.bytes=budget.bytes+8; return v end
  if kind == "number" then
    if v~=v or v==math.huge or v==-math.huge then error("number",0) end
    budget.bytes=budget.bytes+16; return v
  end
  if kind == "string" then
    if #v>512 then error("string",0) end
    budget.bytes=budget.bytes+#v+8; return v
  end
  if kind~="table" or getmetatable(v) or depth>6 then error("table",0) end
  local out={}
  for k,value in pairs(v) do
    budget.nodes=budget.nodes+1
    if budget.nodes>4096 or budget.bytes>65536 or (type(k)~="string" and type(k)~="number") then error("limit",0) end
    local key=Clone(k,depth+1,budget); out[key]=Clone(value,depth+1,budget)
  end
  return out
end
local function Copy(v) return Clone(v,0,{nodes=0,bytes=0}) end
local function Equal(a,b)
  if type(a)~=type(b) then return false end
  if type(a)~="table" then return a==b end
  for k,v in pairs(a) do if not Equal(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end
  return true
end
local function Path(key)
  if type(key)~="string" or #key>96 then return end
  local root,member=key:match("^([%a]+)%.(.+)$")
  root=root or key
  if not ordinary[root] and not pass[root] then return end
  if member and (root~="enabled" and root~="rebuffPer" or not member:match("^[A-Z0-9_]+$")) then return end
  return root,member
end
local function Value(db,key)
  local root,member=Path(key)
  if member then return db[root][member] end
  return db[root]
end
local function Write(db,key,value)
  local root,member=Path(key)
  if member then db[root][member]=Copy(value) else db[root]=Copy(value) end
end
local function Ready()
  if not X.GetDB() then return false,"generation" end
  if X.Settings.SaveState()=="future" then return false,"future" end
  if InCombatLockdown() then return false,"combat" end
  return true
end
local function Validate(db,key,value)
  local root,member=Path(key)
  if not root then return false end
  local v=Copy(value)
  if member then
    local map=Copy(db[root]);map[member]=v;v=map
  elseif v==nil then return false end
  local clean=X.Settings.PreparePatch(db,{[root]=v})
  return Equal(clean[root],v)
end
local function Snapshot(db)
  local out={};for key in pairs(ordinary) do out[key]=Copy(db[key]) end;return out
end
local function Record(before,after,source)
  local changes={}
  for key in pairs(before) do
    if not Equal(before[key],after[key]) then changes[#changes+1]={key=key,before=Copy(before[key]),after=Copy(after[key]),beforePresent=true,afterPresent=true} end
  end
  if #changes==0 then return true end
  table.sort(changes,function(a,b) return a.key<b.key end)
  local size={nodes=0,bytes=0};Clone(changes,0,size)
  if size.bytes>65536 then return false,"limit" end
  serial=serial+1
  history[#history+1]={id=serial,source=sources[source] and source or "other",changes=changes,db=X.GetDB(),generation=generation,size=size.bytes}
  bytes=bytes+size.bytes
  while #history>20 or bytes>65536 do bytes=bytes-history[1].size;table.remove(history,1) end
  return true
end
local function Apply(changes,source)
  local ready,why=Ready();if not ready then return false,why end
  if type(changes)~="table" or getmetatable(changes) then return false,"invalid" end
  local db=X.GetDB();local before=Snapshot(db);local changed,original,roots={},{},{};local count=0
  for key,value in pairs(changes) do
    count=count+1;if count>128 or not Validate(db,key,value) then return false,"invalid" end
    local root,member=Path(key)
    if roots[root] and (not member or roots[root]=="root") then return false,"invalid" end
    roots[root]=member and "leaf" or "root";original[root]=Copy(db[root])
  end
  for key,value in pairs(changes) do
    local root=Path(key)
    if not Equal(Value(db,key),value) then Write(db,key,value);changed[root]=true end
  end
  if not next(changed) then return true end
  if changed.buffPrio then X.prioDirty=true end
  local ok=pcall(function()
    X.SettingsChanged(changed)
    if changed.theme or changed.autoThemePriority then X.ResolveAutoTheme() end
  end)
  if not ok then
    for key,value in pairs(original) do db[key]=value end
    pcall(X.SettingsChanged,changed);return false,"invalid"
  end
  if not capturing and not active then
    local recorded,accepted,reason=pcall(Record,before,Snapshot(db),source)
    if not recorded or not accepted then
      for key,value in pairs(original) do db[key]=value end
      pcall(X.SettingsChanged,changed);return false,reason or "limit"
    end
  end
  return true
end
function P.Transaction(changes,source)
  local ok,a,b=pcall(Apply,changes,source)
  if not ok then return false,"invalid" end
  return a,b
end
function P.Set(key,value,source)
  if value~=nil then return P.Transaction({[key]=value},source) end
  local ready,why=Ready();if not ready then return false,why end
  local db=X.GetDB();local root,member=Path(key)
  if not member or not ordinary[root] then return false,"invalid" end
  local map=Copy(db[root]);map[member]=nil
  return P.Transaction({[root]=map},source)
end
function P.Begin(source)
  local ready,why=Ready();if not ready then return false,why end
  if active then return false,"busy" end
  active={db=X.GetDB(),generation=generation,before=Snapshot(X.GetDB()),source=source};return true
end
function P.Commit()
  local draft=active;active=nil
  if not draft then return false,"empty" end
  if draft.db~=X.GetDB() or draft.generation~=generation then return false,"generation" end
  local ok,accepted,why=pcall(function() return Record(draft.before,Snapshot(X.GetDB()),draft.source) end)
  if not ok or not accepted then
    for key,value in pairs(draft.before) do draft.db[key]=value end
    pcall(X.SettingsChanged,{profile=true});return false,why or "limit"
  end
  return true
end
function P.Capture(callback,source)
  local ready,why=Ready();if not ready then return false,why end
  if type(callback)~="function" then return false,"invalid" end
  if capturing then return callback() end
  local db=X.GetDB();local before=Snapshot(db);capturing=true
  local ok,result=pcall(callback);capturing=false
  if db~=X.GetDB() then return false,"generation" end
  local copied,after=pcall(Snapshot,db)
  if not copied then
    for key,value in pairs(before) do db[key]=value end
    pcall(X.SettingsChanged,{profile=true});return false,"limit"
  end
  for key,value in pairs(after) do
    if not Equal(value,before[key]) and not Validate(db,key,value) then
      for k,v in pairs(before) do db[k]=v end
      X.SettingsChanged({profile=true});return false,"invalid"
    end
  end
  if not ok then
    for key,value in pairs(before) do db[key]=value end
    pcall(X.SettingsChanged,{profile=true});return false,"invalid"
  end
  if not active then
    local recorded,accepted,reason=pcall(Record,before,after,source)
    if not recorded or not accepted then
      for key,value in pairs(before) do db[key]=value end
      pcall(X.SettingsChanged,{profile=true});return false,reason or "limit"
    end
  end
  return true,result
end
function P.History()
  local out={}
  for i=#history,1,-1 do local h=history[i];out[#out+1]={id=h.id,source=h.source,changes=Copy(h.changes)} end
  return out
end
function P.Undo(id)
  if id~=nil and (not Readable(id) or type(id)~="number" or id~=math.floor(id) or id<1) then return false,"invalid" end
  local ready,why=Ready();if not ready then return false,why end
  local index=#history
  if id then while index>0 and history[index].id~=id do index=index-1 end end
  local h=history[index];if not h then return false,"empty" end
  if h.db~=X.GetDB() or h.generation~=generation then return false,"generation" end
  local changes={}
  for _,change in ipairs(h.changes) do
    if not Equal(Value(h.db,change.key),change.after) then return false,"conflict" end
    changes[change.key]=Copy(change.before)
  end
  capturing=true;local ok,reason=P.Transaction(changes,"other");capturing=false
  if not ok then return false,reason end
  bytes=bytes-h.size;table.remove(history,index);return true
end
function P.Allowed(key) local root=Path(key);return root and ordinary[root] or false end
function P.Usage() return {transactions=#history,bytes=bytes} end
function P.Generation() return generation end
X.OnDBLoaded(function() generation=generation+1;history,bytes,active={},0,nil end)
