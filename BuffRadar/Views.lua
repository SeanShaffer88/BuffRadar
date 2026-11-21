-- BuffRadar - optional read-only views of the canonical completed scan.
-- Copyright (C) 2026 Malikor. GPLv3 or later.
local _, ns = ...
local X, V = ns.X, {}
local L = X.L
X.Views = V
local matrix, strip, rowPage, buffPage, selected = nil, nil, 1, 1, nil
local labels = {confirmed="Confirmed",missing="Missing",unknown="Unknown",["not-applicable"]="Not applicable"}
local symbols = {confirmed="+",missing="!",unknown="?",["not-applicable"]="-"}
local colors = {confirmed={.5,1,.5},missing={1,.5,.5},unknown={1,.85,.4},["not-applicable"]={.6,.6,.6}}

local function Snapshot(scope)
  local value = X.CoverageEvidence and X.CoverageEvidence(scope)
  return value or {buffs={},members={},incomplete=true,reason="No readable buff evidence."}
end
local function Freshness(snapshot)
  return snapshot.freshness or (X.Status and X.Status.Freshness and X.Status.Freshness()) or {state="never"}
end
local function Model(scope)
  local snapshot=Snapshot(scope)
  local model={buffs={},rows={},slots={},generation=snapshot.generation,freshness=Freshness(snapshot)}
  local paused=model.freshness.state~="current"
  for i=1,math.min(scope=="self" and 16 or 24,#snapshot.buffs) do
    local buff=snapshot.buffs[i]
    model.buffs[i]={key=buff.key,name=buff.name or buff.label or buff.key,spellID=buff.spellID,icon=buff.icon}
  end
  for i=1,math.min(scope=="self" and 1 or 40,#snapshot.members) do
    local member=snapshot.members[i]
    local row={guid=member.guid or member.identity,label=member.label or member.name,subgroup=member.subgroup,cells={}}
    for j,buff in ipairs(model.buffs) do
      local cell=member.cells[buff.key] or {state="unknown"}
      local state=labels[cell.state] and cell.state or "unknown"
      if paused and state~="not-applicable" then state="unknown" end
      row.cells[j]={key=buff.key,name=buff.name,state=state,expiresAt=not paused and cell.expiresAt or nil}
    end
    model.rows[i]=row
  end
  if scope=="self" then
    for j,buff in ipairs(model.buffs) do
      local cell=model.rows[1] and model.rows[1].cells[j] or {state="unknown"}
      model.slots[j]={key=buff.key,name=buff.name,spellID=buff.spellID,icon=buff.icon,state=cell.state,expiresAt=cell.expiresAt}
    end
  end
  return model
end
function V.MatrixModel() return Model("group") end
function V.SelfModel() return Model("self") end
local function Badge(model)
  local state=model.freshness.state
  if state=="paused" then return L["Scan paused"] end
  if state=="stale" then return L["Scan stale"] end
  if state~="current" then return L["No completed scan"] end
  return X.Status and X.Status.Description() or L["Confirmed"]
end
local function Tip(button,text)
  button:SetScript("OnEnter",function(self)
    GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText(text);GameTooltip:Show()
  end)
  button:SetScript("OnLeave",function() GameTooltip:Hide() end)
end
local function Label(parent,x,y,width,text)
  local label=parent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  label:SetPoint("TOPLEFT",x,y);label:SetWidth(width);label:SetHeight(30);label:SetWordWrap(true);label:SetText(text or "")
  return label
end
local function Panel(name,title,width,height,key,offset)
  local panel=X.PanelWidget("Frame",name,UIParent,BackdropTemplateMixin and "BackdropTemplate" or nil)
  panel:SetSize(width,height);panel:SetPoint("CENTER");panel:SetClampedToScreen(true)
  local db=X.GetDB();panel:SetScale(db and db.cfgScale or 1)
  if panel.SetBackdrop then
    panel:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=12})
    panel:SetBackdropColor(.04,.05,.09,.97)
  end
  Label(panel,15,-12,width-30,L[title])
  panel:SetMovable(true);panel:EnableMouse(true);panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart",function(self) if not InCombatLockdown() then self:StartMoving() end end)
  if X.BindPanelPosition then X.BindPanelPosition(panel,key,offset) end
  panel:RegisterEvent("PLAYER_REGEN_DISABLED");panel:RegisterEvent("PLAYER_REGEN_ENABLED")
  panel:SetScript("OnEvent",function(self,event)
    if event=="PLAYER_REGEN_DISABLED" then self:EnableKeyboard(false);self:Hide()
    else V.Refresh() end
  end)
  return panel
end
local function Button(parent,label,x,y,width,action)
  local b=X.PanelWidget("Button",nil,parent,"UIPanelButtonTemplate")
  b:SetPoint("TOPLEFT",x,y);b:SetSize(width,25);b:SetText(L[label]);b:SetScript("OnClick",action)
  return b
end
local function Keyboard(panel,controls)
  local focus=0
  panel:SetScript("OnHide",function(self) self:EnableKeyboard(false) end)
  panel:SetScript("OnKeyDown",function(self,key)
    if InCombatLockdown() then return end
    if key=="ESCAPE" then
      if self==strip then X.SetPreference("selfStatusStrip",false) end
      self:Hide()
    elseif key=="TAB" then
      if controls[focus] then controls[focus]:UnlockHighlight() end
      local delta=IsShiftKeyDown and IsShiftKeyDown() and -1 or 1
      focus=(focus-1+delta)%#controls+1;controls[focus]:LockHighlight()
    elseif (key=="ENTER" or key=="SPACE") and controls[focus] then controls[focus]:Click()
    else self:SetPropagateKeyboardInput(true);return end
    self:SetPropagateKeyboardInput(false)
  end)
end
local function CreateMatrix()
  matrix=Panel("BuffRadarCoverageMatrix","Coverage Matrix",690,450,"matrix",0)
  matrix.badge=Label(matrix,18,-45,654)
  matrix.headers,matrix.rows={},{}
  for j=1,6 do matrix.headers[j]=Label(matrix,160+(j-1)*85,-82,82) end
  local controls={}
  for i=1,8 do
    local row={name=Button(matrix,"Player",18,-118-(i-1)*30,137,function() end),cells={}}
    for j=1,6 do row.cells[j]=Label(matrix,160+(j-1)*85,-115-(i-1)*30,82) end
    matrix.rows[i]=row;controls[#controls+1]=row.name
  end
  controls[#controls+1]=Button(matrix,"Previous Players",18,-371,155,function() rowPage=math.max(1,rowPage-1);V.Refresh() end)
  controls[#controls+1]=Button(matrix,"Next Players",180,-371,155,function() rowPage=rowPage+1;V.Refresh() end)
  controls[#controls+1]=Button(matrix,"Previous Buffs",345,-371,155,function() buffPage=math.max(1,buffPage-1);V.Refresh() end)
  controls[#controls+1]=Button(matrix,"Next Buffs",507,-371,155,function() buffPage=buffPage+1;V.Refresh() end)
  controls[#controls+1]=Button(matrix,"Close",18,-410,644,function() matrix:Hide() end)
  Keyboard(matrix,controls)
end
local function RenderMatrix()
  local model=V.MatrixModel()
  local pages=math.max(1,math.ceil(#model.rows/8))
  rowPage,buffPage=math.min(rowPage,pages),math.min(buffPage,math.max(1,math.ceil(#model.buffs/6)))
  matrix.badge:SetText(string.format(L["%s · Page %d/%d"],Badge(model),rowPage,pages))
  local found=false
  for _,member in ipairs(model.rows) do if member.guid==selected then found=true end end
  if not found then selected=nil end
  for j=1,6 do local buff=model.buffs[(buffPage-1)*6+j];matrix.headers[j]:SetText(buff and buff.name or "") end
  for i=1,8 do
    local row=matrix.rows[i];local member=model.rows[(rowPage-1)*8+i]
    row.name:SetText(member and member.label or "");row.name:SetShown(member~=nil)
    if member then
      local identity,name=member.guid,member.label
      row.name:SetScript("OnClick",function() selected=identity;if X.Why then X.Why(name) end end)
      Tip(row.name,name)
    end
    for j=1,6 do
      local cell=member and member.cells[(buffPage-1)*6+j]
      row.cells[j]:SetText(cell and symbols[cell.state] or "")
      if cell then row.cells[j]:SetTextColor(unpack(colors[cell.state])) end
    end
    if member then
      local details={member.label}
      for _,cell in ipairs(member.cells) do details[#details+1]=string.format(L["%s · %s"],cell.name,L[labels[cell.state]]) end
      Tip(row.name,table.concat(details,"\n"))
    end
  end
end
local function CreateStrip()
  strip=Panel("BuffRadarSelfStatus","Self Buff Status",482,210,"selfStatus",-150)
  strip.badge=Label(strip,15,-38,452);strip.slots={}
  for i=1,16 do
    local x,y=15+((i-1)%8)*57,-76-math.floor((i-1)/8)*50
    local slot=X.PanelWidget("Button",nil,strip)
    slot:SetSize(54,47);slot:SetPoint("TOPLEFT",x,y)
    slot.text=Label(slot,0,0,54);strip.slots[i]=slot
  end
  local close=Button(strip,"Close",15,-178,452,function() X.SetPreference("selfStatusStrip",false);strip:Hide() end)
  Keyboard(strip,{close})
end
local function RenderStrip()
  local model=V.SelfModel();strip.badge:SetText(Badge(model))
  for i=1,16 do
    local slot,value=strip.slots[i],model.slots[i]
    slot:SetShown(value~=nil)
    if value then
      slot.text:SetText(symbols[value.state].."\n"..value.name);slot.text:SetTextColor(unpack(colors[value.state]))
      local text=string.format(L["%s · %s"],value.name,L[labels[value.state]])
      if type(value.expiresAt)=="number" and value.expiresAt>GetTime() then
        text=string.format(L["%s · %s · %ds"],value.name,L[labels[value.state]],math.floor(value.expiresAt-GetTime()))
      end
      Tip(slot,text)
    end
  end
end
function V.Refresh()
  local db=X.GetDB()
  if not db then return end
  if InCombatLockdown() or X.PlayerSuspended() then
    if matrix then matrix:Hide() end;if strip then strip:Hide() end;return
  end
  if matrix and matrix:IsShown() then
    if db.matrixView then RenderMatrix() else matrix:Hide() end
  end
  if db.selfStatusStrip then
    if not strip then CreateStrip() end
    RenderStrip();strip:Show()
  elseif strip then strip:Hide() end
end
function V.ShowMatrix()
  if InCombatLockdown() or X.PlayerSuspended() then return false end
  X.SetPreference("matrixView",true)
  if not matrix then CreateMatrix() end
  RenderMatrix();matrix:EnableKeyboard(true);matrix:Show();return true
end
function V.ToggleMatrix()
  if InCombatLockdown() then return false end
  local db=X.GetDB();if not db then return false end
  X.SetPreference("matrixView",not db.matrixView)
  if db.matrixView then return V.ShowMatrix() end
  V.Refresh();return true
end
function V.ToggleSelf()
  if InCombatLockdown() then return false end
  local db=X.GetDB();if not db then return false end
  X.SetPreference("selfStatusStrip",not db.selfStatusStrip);V.Refresh()
  if strip and strip:IsShown() then strip:EnableKeyboard(true) end
  return true
end
function V.GetMatrixFrame() return matrix end
function V.GetSelfFrame() return strip end
