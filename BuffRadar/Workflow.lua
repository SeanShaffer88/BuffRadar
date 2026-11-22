-- Reviewed assignment copies, local preference restore and update navigation.
-- Copyright (C) 2026 Malikor. GPLv3 or later.
local _,ns=...
local X,L=ns.X,ns.X.L
local W={}
X.Workflow=W
local dialogs=X.DailyAPI
local copy,recovery,notice
local lifePending=false
local function Ready() return not InCombatLockdown() and not X.PlayerSuspended() end
local function Refused() X.Print(L["The current values changed. Review again before applying."]) end
local function Frame(name,title)
  local f=dialogs.Panel(name,L[title],510)
  f.description=dialogs.Label(f,"",-47,50)
  f.rows={}
  for i=1,8 do f.rows[i]=dialogs.Label(f,"",-139-(i-1)*32,30) end
  f.page=1
  f.previous=dialogs.Button(f,"Previous",16,-405,215,function() f.page=f.page-1;f.render() end)
  f.next=dialogs.Button(f,"Next",247,-405,217,function() f.page=f.page+1;f.render() end)
  f.apply=dialogs.Button(f,"Apply Copy",16,-440,215,function() end)
  f.refresh=dialogs.Button(f,"Review Changes",247,-440,217,function() f.prepare() end)
  f.close=dialogs.Button(f,"Cancel",16,-476,448,function() f:Hide() end)
  local x=X.PanelWidget("Button",nil,f,"UIPanelCloseButton")
  x:SetPoint("TOPRIGHT",-3,-3);x:SetSize(24,24);x:SetScript("OnClick",function() f:Hide() end)
  f.closeButton=x
  f:HookScript("OnHide",function(self)
    self.model=nil;self.workflowEpoch=(self.workflowEpoch or 0)+1
    if dialogs.Modal()==self then dialogs.SetModal(nil) end
  end)
  f:Hide()
  return f
end
local function Rows(f,lines)
  local pages=math.max(1,math.ceil(#lines/#f.rows))
  f.page=math.max(1,math.min(pages,f.page))
  for i,row in ipairs(f.rows) do row:SetText(lines[(f.page-1)*#f.rows+i] or "") end
  f.previous:SetEnabled(f.page>1);f.next:SetEnabled(f.page<pages)
end
local function Show(f,parent,origin)
  dialogs.CloseOwned(f)
  parent=parent or dialogs.Modal() or (X.WorkflowParent and X.WorkflowParent())
  if not parent then local host=X.Daily.Frame();if host and host:IsVisible() then parent=host end end
  local ancestor=parent
  for _=1,8 do
    if ancestor==f then parent=nil;break end
    local owner=ancestor and ancestor.dailyInputOwner
    ancestor=owner and owner.parent
    if not ancestor then break end
  end
  if (not parent or not parent.configWorkflowHost) and X.ReleaseWorkflowNavigation then X.ReleaseWorkflowNavigation() end
  f.workflowEpoch=(f.workflowEpoch or 0)+1
  if parent then f:SetFrameLevel(parent:GetFrameLevel()+10) end
  f:Show();dialogs.SetModal(f)
  if parent and not (X.HostWorkflow and X.HostWorkflow(parent,f,origin)) then dialogs.Suspend(parent,f) end
end

local function Class(class)
  local names=_G.LOCALIZED_CLASS_NAMES_MALE
  return names and names[class] or class
end
local function Slot(slot)
  local labels={ALL="All Roles",WORLD="World",TANK="Tank",HEALER="Heal",DAMAGER="DPS"}
  return L[labels[slot] or "Unknown"]
end
local function Cell(value)
  if value==nil then return L["Default"] end
  if value==false then return L["None"] end
  local names,known={},{}
  for _,option in ipairs(X.AssignmentOptions()) do known[option.key]=option.name end
  for key in pairs(value) do names[#names+1]=known[key] or key end
  table.sort(names);return table.concat(names,", ")
end
function W.Copy(kind,source,parent,origin)
  if not Ready() or not X.classic or not X.AssignmentCopy then return false end
  if (kind~="cell" and kind~="row") or type(source)~="table"
    or not X.ValidAssignmentCell(source.class,kind=="row" and "ALL" or source.slot) then return false end
  if not copy then
    copy=Frame("BuffRadarAssignmentCopy", "Review Assignment Copy")
    copy.close:ClearAllPoints();copy.close:SetPoint("TOPLEFT",247,-476);copy.close:SetSize(217,27)
    copy.back=dialogs.Button(copy,"Back",16,-476,215,function() copy:Hide() end)
    copy.classButton=dialogs.Button(copy,"Destination Class",16,-104,215,function()
      local order=X.BLESSING_CLASS_ORDER;local index=1
      for i,class in ipairs(order) do if class==copy.dest.class then index=i end end
      copy.dest.class=order[index%#order+1];copy.prepare()
    end)
    copy.slotButton=dialogs.Button(copy,"Destination Role",247,-104,217,function()
      local order=X.ASSIGNMENT_SLOTS;local index=1
      for i,slot in ipairs(order) do if slot==copy.dest.slot then index=i end end
      copy.dest.slot=order[index%#order+1];copy.prepare()
    end)
    copy.buttons={copy.classButton,copy.slotButton,copy.previous,copy.next,copy.apply,copy.refresh,copy.back,copy.close}
    copy.prepare=function()
      local stagedSource=copy.kind=="row" and {class=copy.source.class} or copy.source
      local dest=copy.kind=="row" and {class=copy.dest.class} or copy.dest
      copy.model=select(1,X.AssignmentCopy.Stage(copy.kind,stagedSource,dest))
      copy.page=1;copy.render()
    end
    copy.render=function()
      local f=copy;local model=f.model
      f.classButton:SetText(L["Destination Class"]..": "..Class(f.dest.class))
      f.slotButton:SetText(L["Destination Role"]..": "..Slot(f.dest.slot))
      f.slotButton:SetShown(f.kind=="cell")
      f.description:SetText(string.format(L["Copy %s → %s"],Class(f.source.class)..(f.kind=="cell" and (", "..Slot(f.source.slot)) or ""),
        Class(f.dest.class)..(f.kind=="cell" and (", "..Slot(f.dest.slot)) or "")).."\n"..L["Choose a destination, then review before applying."])
      local lines={}
      if model then
        for _,change in ipairs(model.changes or {}) do
          lines[#lines+1]=string.format(L["%s: %s -> %s"],Class(change.class)..", "..Slot(change.slot),Cell(change.before),Cell(change.after))
        end
        if #lines==0 then lines[1]=L["No Changes"] end
        if model.incomplete then lines[#lines+1]=L["Buff coverage unavailable"] end
        if #(model.rows or {})>0 then
          lines[#lines+1]=L["Current-Group Changes"]
          for _,row in ipairs(model.rows) do
            lines[#lines+1]=string.format(L["%s: %s -> %s"],row.name or L["Unknown"],
              table.concat(row.losses or {},", "),table.concat(row.gains or {},", "))
          end
        end
      else lines[1]=L["The current values changed. Review again before applying."] end
      Rows(f,lines);f.apply:SetText(L["Apply Copy"])
      f.apply:SetEnabled(model~=nil and not model.incomplete and #(model.changes or {})>0)
      local epoch=f.workflowEpoch
      f.apply:SetScript("OnClick",function()
        if not Ready() or not f:IsShown() or f.workflowEpoch~=epoch or f.model~=model then return end
        if X.AssignmentCopy.Apply(model) then X.Print(L["Assignment copy applied."]);f:Hide();if X.RefreshConfig then X.RefreshConfig() end
        else f.model=nil;f.apply:Disable();Refused() end
      end)
    end
  end
  copy.kind=kind;copy.source={class=source.class,slot=source.slot}
  copy.dest={class=source.class,slot=source.slot or "ALL"}
  copy.description:SetText(L["Choose a destination, then review before applying."])
  Show(copy,parent,origin);copy.prepare()
  return true
end
function W.Recovery(parent,origin)
  if not Ready() then return false end
  if not recovery then
    recovery=Frame("BuffRadarRecovery", "Local Preference Restore Point")
    recovery.prepare=function() recovery.model=select(1,X.Recovery.Preview());recovery.page=1;recovery.render() end
    recovery.render=function()
      local f,model=recovery,recovery.model
      local lines=model and model.lines or {L["No local preference restore point is available."]}
      if #lines==0 then lines={L["No Changes"]} end
      f.description:SetText(model and ((model.bootstrap and L["Legacy Preference Snapshot"]
        or string.format(L["Before %s → %s"],model.fromVersion or L["Unknown"],model.toVersion or L["Unknown"]))
        .."\n"..L["Player identities, profiles, cast history and purchase authorization are excluded."])
        or L["One local preference snapshot. This is not a file backup."])
      Rows(f,lines);f.apply:SetText(L["Restore Reviewed Preferences"]);f.apply:SetEnabled(model~=nil and #model.lines>0)
      local epoch=f.workflowEpoch
      f.apply:SetScript("OnClick",function()
        if not Ready() or not f:IsShown() or f.workflowEpoch~=epoch or f.model~=model then return end
        if X.Recovery.Apply(model) then X.Print(L["Preferences restored."]);f:Hide()
        else f.model=nil;f.apply:Disable();Refused() end
      end)
    end
  end
  Show(recovery,parent,origin);recovery.prepare();return true
end
function W.WhatsNew(manual,parent,origin)
  if not Ready() or X.Settings.SaveState() then return false end
  if not notice then
    notice=dialogs.Panel("BuffRadarWhatsNew",L["What's New in BuffRadar"],390)
    notice.items={}
    for i=1,3 do notice.items[i]=dialogs.Label(notice,"",-66-(i-1)*83,72) end
    notice.daily=dialogs.Button(notice,"Open Daily Tasks",16,-340,215,function() notice:Hide();X.Daily.Open() end)
    notice.dismiss=dialogs.Button(notice,"Dismiss",247,-340,217,function() notice:Hide() end)
    local x=X.PanelWidget("Button",nil,notice,"UIPanelCloseButton")
    x:SetPoint("TOPRIGHT",-3,-3);x:SetScript("OnClick",function() notice:Hide() end);notice.closeButton=x
    notice:HookScript("OnHide",function(self)
      local same=self.noticeDB==X.GetDB() and self.noticeGeneration==X.Preferences.Generation()
        and self.version~=nil and self.version==X.Recovery.Version()
      if same and not X.Updates.Dismiss() then
        self.dismissPending={db=self.noticeDB,generation=self.noticeGeneration,version=self.version}
      end
      if dialogs.Modal()==self then dialogs.SetModal(nil) end
    end)
  end
  local model=X.Updates.Model()
  for i=1,3 do notice.items[i]:SetText(L[model.items[i]]) end
  notice.version=model.version;notice.manual=manual==true
  notice.noticeDB=X.GetDB();notice.noticeGeneration=X.Preferences.Generation()
  if not parent then local host=X.Daily.Frame();if host and host:IsShown() then parent=host end end
  Show(notice,parent,origin);return true
end
X.ShowUpdates=function() return W.WhatsNew(false) end
X.UpdatesBlocked=function()
  if notice and notice.dismissPending then return true end
  if dialogs.Modal() and dialogs.Modal():IsShown() then return true end
  if X.WorkflowModalBlocked and X.WorkflowModalBlocked() then return true end
  return X.exportFrame and X.exportFrame:IsShown() or false
end
function W.CopyFrame() return copy end
function W.RecoveryFrame() return recovery end
function W.UpdatesFrame() return notice end
X.ext.recovery=function() W.Recovery();return true end
X.ext.whatsnew=function() W.WhatsNew(true);return true end
local events=CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN");events:RegisterEvent("PLAYER_REGEN_ENABLED");events:RegisterEvent("PLAYER_ALIVE")
local function Eligibility()
  if not Ready() then
    if X.lifeCheckPending then lifePending=true end
    return
  end
  lifePending=false
  if notice and notice.dismissPending then
    local pending=notice.dismissPending
    if pending.db~=X.GetDB() or pending.generation~=X.Preferences.Generation() or pending.version~=X.Recovery.Version()
      or X.Updates.Dismiss() then notice.dismissPending=nil end
  end
  X.Updates.Show()
end
W.Refresh=function() if lifePending then Eligibility() end end
events:SetScript("OnEvent",Eligibility)
