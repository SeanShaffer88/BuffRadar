-- BuffRadar - daily navigation and explicit local preference reviews.
-- Copyright (C) 2026 Malikor. GPLv3 or later.
local _, ns = ...
local X, L = ns.X, ns.X.L
local D = {}
X.Daily = D
local daily, review, generation = nil, nil, 0
local modal
local panels={}

local function Label(parent, text, y, height)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", 16, y); fs:SetWidth(448); fs:SetHeight(height or 34)
  fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP"); fs:SetWordWrap(true); fs:SetText(text)
  return fs
end

local function Capture(frame, enabled)
  enabled=enabled and not InCombatLockdown() and not X.PlayerSuspended()
    and not (frame.activeChild and frame.activeChild:IsShown())
  if frame.dailyKeyboardPolicy then enabled=enabled and frame.dailyKeyboardPolicy(frame) end
  if frame.dailyCaptureAdapter then frame.dailyCaptureAdapter(enabled);return end
  frame:EnableKeyboard(enabled)
  if not InCombatLockdown() then frame:SetPropagateKeyboardInput(true) end
end

-- One owner for every parent/child suspension; stale child hides never revive another view.
local function SuspendForChild(parent,child,canClose)
  if not child or not child:IsShown() then
    if parent:IsVisible() and (not modal or modal==parent) then Capture(parent,true) end
    return
  end
  local token={}
  parent.activeChild,parent.inputChildToken=child,token
  child.dailyInputOwner={parent=parent,token=token,generation=generation,inputGeneration=parent.inputGeneration,
    canClose=canClose~=false,contentGeneration=child.dailyInputContentGeneration}
  Capture(parent,false)
  if child.dailyInputHook then return end
  child.dailyInputHook=true
  child:HookScript("OnHide",function(self)
    local owner=self.dailyInputOwner;self.dailyInputOwner=nil
    if not owner then return end
    local frame=owner.parent
    if frame.activeChild~=self or frame.inputChildToken~=owner.token then return end
    frame.activeChild,frame.inputChildToken=nil,nil
    if owner.generation~=generation or owner.inputGeneration~=frame.inputGeneration then return end
    if modal==self or modal==nil then
      modal=frame.dailyPanelRegistered and frame~=daily and frame:IsVisible() and frame or nil
    end
    if frame:IsVisible() and owner.generation==generation and owner.inputGeneration==frame.inputGeneration
      and (not modal or modal==frame) then Capture(frame,true) end
  end)
end

local function CloseOwnedChild(frame)
  local child=frame.activeChild
  if not child or not child:IsShown() then return false end
  local owner=child.dailyInputOwner
  local owned=owner and owner.parent==frame and owner.token==frame.inputChildToken
    and owner.generation==generation and owner.inputGeneration==frame.inputGeneration
    and owner.canClose and owner.contentGeneration==child.dailyInputContentGeneration
  local protected=child.IsProtected and child:IsProtected()
  if owned and not (protected and InCombatLockdown()) then child:Hide() end
  if not child:IsShown() then return false end
  -- A reused or protected child survives; its ancestor waits without claiming close ownership.
  local ancestor=frame.dailyInputOwner
  if ancestor and ancestor.parent.activeChild==frame and ancestor.parent.inputChildToken==ancestor.token
    and ancestor.generation==generation and ancestor.inputGeneration==ancestor.parent.inputGeneration then
    modal=child
    SuspendForChild(ancestor.parent,child,false)
  elseif modal==frame then modal=child end
  return true
end

local function RegisterPanel(frame)
  if frame.dailyPanelRegistered then return end
  frame.dailyPanelRegistered=true;frame.dailyHostRegistered=true
  frame.focusIndex=frame.focusIndex or 0
  frame.buttons=frame.buttons or {}
  frame.buttonCount=frame.buttonCount or 0
  frame:HookScript("OnShow",function(self)
    if self.activeChild and self.activeChild:IsShown() then SuspendForChild(self,self.activeChild,false) end
    Capture(self,true)
  end)
  frame:HookScript("OnHide",function(self)
    local deferred=CloseOwnedChild(self)
    Capture(self,false)
    self.inputGeneration=(self.inputGeneration or 0)+1
    if not deferred then self.activeChild,self.inputChildToken=nil,nil end
  end)
  frame:SetScript("OnKeyDown",function(self,key)
    if InCombatLockdown() or X.PlayerSuspended() or (self.dailyKeyboardPolicy and not self.dailyKeyboardPolicy(self))
      or (self.activeChild and self.activeChild:IsShown()) then return end
    if key=="ESCAPE" then self:Hide()
    elseif key=="TAB" then
      local list=self.buttons
      if list[self.focusIndex] then list[self.focusIndex]:UnlockHighlight() end
      local delta=IsShiftKeyDown and IsShiftKeyDown() and -1 or 1
      for _=1,#list do
        self.focusIndex=(self.focusIndex-1+delta)%#list+1
        if list[self.focusIndex]:IsShown() and list[self.focusIndex]:IsEnabled() then list[self.focusIndex]:LockHighlight(); break end
      end
    elseif key=="ENTER" or key=="SPACE" then
      local button=self.buttons[self.focusIndex]
      if button and button:IsShown() and button:IsEnabled() then
        if button.dailyActivate then button.dailyActivate() else button:Click() end
      end
    else self:SetPropagateKeyboardInput(true); return end
    self:SetPropagateKeyboardInput(false)
  end)
  frame:RegisterEvent("PLAYER_REGEN_DISABLED"); frame:RegisterEvent("PLAYER_REGEN_ENABLED")
  frame:RegisterEvent("PLAYER_DEAD");frame:RegisterEvent("PLAYER_ALIVE")
  panels[#panels+1]=frame
  frame:HookScript("OnEvent",function(self,event)
    if event=="PLAYER_ALIVE" and X.lifeCheckPending then self.lifeReturnPending=true end
    Capture(self,self:IsShown() and (not modal or modal==self));D.Refresh()
  end)
end

local function Panel(name, title, height)
  local frame = X.PanelWidget("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(480, height); frame:SetPoint("CENTER"); frame:SetClampedToScreen(true)
  frame:SetFrameStrata("DIALOG"); frame:EnableMouse(true)
  if frame.SetBackdrop then
    frame:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true,tileSize=16,edgeSize=12,
      insets={left=3,right=3,top=3,bottom=3} })
    frame:SetBackdropColor(0.04,0.05,0.09,0.98)
  end
  frame.title=Label(frame,title,-16,24)
  RegisterPanel(frame)
  if UISpecialFrames then table.insert(UISpecialFrames,name) end
  return frame
end

local function Button(parent,text,x,y,width,callback)
  parent.buttonCount=parent.buttonCount+1
  local button=parent.buttons[parent.buttonCount]
  if not button then
    button=X.PanelWidget("Button",nil,parent,"UIPanelButtonTemplate")
    parent.buttons[parent.buttonCount]=button
  end
  button:ClearAllPoints()
  button:SetPoint("TOPLEFT",x,y); button:SetSize(width,27); button:SetText(L[text])
  button:SetScript("OnClick",callback); button:Show()
  return button
end

local function Route(callback, target)
  if InCombatLockdown() or X.PlayerSuspended() then return end
  if daily then Capture(daily,false) end
  callback()
  local child=target and target()
  if child and child:IsShown() then modal=child end
  if daily then SuspendForChild(daily,child) end
end

function D.Refresh()
  if not X.PlayerSuspended() then
    for _,frame in ipairs(panels) do
      if frame.lifeReturnPending then
        frame.lifeReturnPending=nil;Capture(frame,frame:IsVisible() and (not modal or modal==frame))
      end
    end
  end
  if X.Workflow and X.Workflow.Refresh then X.Workflow.Refresh() end
  if not daily or not daily:IsShown() then return end
  local f=X.Status.Freshness and X.Status.Freshness(GetTime()) or {state="never"}
  local states={never="No completed scan",current="Current",stale="Scan stale",paused="Scan paused",unavailable="Unavailable"}
  local age=type(f.age)=="number" and string.format(L["%ds"],math.floor(f.age)) or L["Unknown"]
  daily.freshness:SetText(string.format(L["Last completed scan: %s · %s"],L[states[f.state] or "Unknown"],age))
  local status=X.Status.Diagnostics()
  local why=status.partial and L["Discovery is incomplete or filtered."] or X.Status.Description()
  if not X.InGroup() and X.FriendlyPlatesOn()==false then why=L["Friendly nameplates are off."] end
  daily.discovery:SetText(why)
  local direct,macroLine=X.DeliveryLines()
  daily.delivery:SetText(direct.."\n"..macroLine)
end

function D.Open()
  -- A deliberate root navigation retires the prior owned modal chain first.
  for _=1,8 do
    local prior=modal
    if not prior or prior==daily or not prior:IsShown() then break end
    if InCombatLockdown() and prior.IsProtected and prior:IsProtected() then return end
    prior:Hide()
    if modal==prior then modal=nil end
  end
  generation=generation+1; modal=nil
  if not daily then
    daily=Panel("BuffRadarDaily",L["Daily Tasks"],570)
    daily.freshness=Label(daily,"",-48,35)
    Label(daily,L["Discover"],-92,22); daily.discovery=Label(daily,"",-119,36)
    Button(daily,"First cast guide",16,-160,215,function() Route(X.Support.Open,X.Support.Frame) end)
    if X.classic then Button(daily,"Nearby Player Diagnostics",247,-160,217,function()
      if X.OpenNearbyDiagnostics then Route(X.OpenNearbyDiagnostics,function() return _G.BuffRadarNearbyDiagnostics end) end
    end) end
    Label(daily,L["Cast"],-204,22); daily.delivery=Label(daily,"",-232,70)
    Button(daily,"Open Buff List",16,-306,215,function()
      if InCombatLockdown() or X.PlayerSuspended() then return end
      Route(function()
        local window=X.GetFrame(); if window and not window:IsShown() then X.ToggleWindow() end
      end,X.GetFrame)
    end)
    Button(daily,"Cast next buff",247,-306,104,function() Route(X.Core.OpenKeybinds,function() return _G.SettingsPanel end) end)
    Button(daily,"Macro",359,-306,105,function() if not InCombatLockdown() then X.Core.MakeMacro() end end)
    Label(daily,L["Prepare"],-350,22)
    Button(daily,"Open personal checks",16,-378,215,function() Route(function() X.RaidPreparationCommand("personal") end,function() local cfg=_G.BuffRadarConfig; return cfg and cfg.assignmentPanel and cfg.assignmentPanel.preparation end) end)
    Button(daily,"Coverage Matrix",247,-378,217,function() if X.Views then Route(X.Views.ShowMatrix,X.Views.GetMatrixFrame) end end)
    Button(daily,"Supplies",16,-412,215,function() if X.Supplies then Route(X.Supplies.Show,X.Supplies.GetFrame) end end)
    Button(daily,"Recent Changes",247,-412,217,function() D.Recent() end)
    Button(daily,"Share Preferences",16,-446,215,function() D.Share() end)
    Button(daily,"Self Buff Status",247,-446,217,function() if X.Views then X.Views.ToggleSelf() end end)
    Button(daily,"Expert Settings",16,-480,215,function() Route(function() X.OpenConfig(true) end,function() return _G.BuffRadarConfig end) end)
    Button(daily,"Copy Support Report",247,-480,217,function() Route(X.Support.ShowReport,function() return X.exportFrame end) end)
    Button(daily,"Optional Views",16,-524,215,function() Route(X.OpenDailyOptions,function() return _G.BuffRadarConfig end) end)
    Button(daily,"Close",247,-524,217,function() daily:Hide() end)
    daily:HookScript("OnHide",function() generation=generation+1; modal=nil end)
  end
  daily:Show(); Capture(daily,true); D.Refresh()
  if X.Updates then X.Updates.Show() end
end

local function Review(title)
  if not review then
    review=Panel("BuffRadarDailyReview",title,430)
    review.description=Label(review,"",-55,90)
    review.rows={}
    for i=1,5 do review.rows[i]=Label(review,"",-145-(i-1)*37,32); review.rows[i]:SetWidth(326) end
    review:HookScript("OnHide",function(self)
      if modal==self then
        modal=nil
        if daily and daily:IsShown() and self.dailyGeneration==generation then Capture(daily,true) end
      end
    end)
  end
  for _,button in ipairs(review.buttons) do button:Hide() end
  for _,row in ipairs(review.rows) do row:SetText("") end
  local deferred=CloseOwnedChild(review)
  review.inputGeneration=(review.inputGeneration or 0)+1
  if not deferred then review.activeChild,review.inputChildToken=nil,nil end
  review.buttonCount=0; review.focusIndex=0; review.model=nil; review.title:SetText(title)
  if daily then Capture(daily,false) end
  review.dailyGeneration=generation; modal=review
  review:Show()
  if daily then SuspendForChild(daily,review) end
  return review
end

function D.Share(scope, name)
  if InCombatLockdown() or X.PlayerSuspended() then return end
  scope=scope=="full" and "full" or "preferences"
  local model=X.SharePreview(scope,name)
  if not model then X.Print(L["Export could not be prepared."]); return end
  local f=Review(L["Share Preferences"])
  f.model=model
  f.description:SetText(L[scope=="full" and "Full backup includes player names. Review before copying."
    or "Preferences only. The recipient keeps their ignored players and named exceptions."])
  local categories={{"preferences","Share Preferences"},{"ignored","Ignored players"},{"pinned","pinned"}}
  for i,category in ipairs(categories) do
    local value=model.counts and model.counts[category[1]]
    local count=type(value)=="number" and tostring(value) or L["Unknown"]
    f.rows[i]:SetText(string.format(L["%s: %s"],L[category[2]],count))
  end
  Button(f,scope=="full" and "Preferences Only" or "Full backup (includes player names)",16,-344,448,function()
    D.Share(scope=="full" and "preferences" or "full",name)
  end)
  Button(f,"Copy",16,-379,215,function()
    if InCombatLockdown() or X.PlayerSuspended() then return end
    if f.model and f.model.scope==scope then
      Capture(f,false)
      X.ShowExport(f.model.text,false,L["Share Preferences"])
      SuspendForChild(f,X.exportFrame)
    end
  end)
  Button(f,"Close",247,-379,217,function() f:Hide() end)
end

function D.Recent(page)
  if InCombatLockdown() or X.PlayerSuspended() or not X.Preferences then return end
  local f=Review(L["Recent Changes"])
  local history=X.Preferences.History()
  page=math.max(1,math.min(math.ceil(#history/5),tonumber(page) or 1))
  f.description:SetText(L["Recent ordinary preferences only. Purchases, identities and network actions cannot be undone."])
  for i=1,5 do
    local record=history[(page-1)*5+i]
    if record then
      local keys={}
      for _,change in ipairs(record.changes) do
        local function Value(v,present)
          if not present then return L["None"] end
          if type(v)=="boolean" then return L[v and "On" or "Off"] end
          if type(v)=="number" then return tostring(v) end
          if type(v)=="string" then return L[v] end
          return L["Unknown"]
        end
        keys[#keys+1]=string.format(L["%s: %s -> %s"],change.key,
          Value(change.before,change.beforePresent),Value(change.after,change.afterPresent))
      end
      f.rows[i]:SetText(string.format(L["Change %d: %s"],record.id,table.concat(keys,", ")))
      Button(f,"Undo",356,-145-(i-1)*37,108,function()
        local ok=X.Preferences.Undo(record.id)
        X.Print(L[ok and "Preference change undone." or "Undo refused. The current values or session changed."])
        D.Recent()
      end)
    end
  end
  Button(f,"Previous",16,-344,215,function() D.Recent(page-1) end)
  Button(f,"Next",247,-344,217,function() D.Recent(page+1) end)
  Button(f,"Close",16,-379,448,function() f:Hide() end)
end

function D.Frame() return daily end
function D.ReviewFrame() return review end
X.ext.daily=function() D.Open(); return true end
X.ext.prefs=function(rest)
  if rest=="undo" then
    local ok=X.Preferences.Undo()
    X.Print(L[ok and "Preference change undone." or "Undo refused. The current values or session changed."])
  else D.Recent() end
  return true
end

-- Private native-dialog host shared by workflow frames and settings adapters.
X.DailyAPI={Panel=Panel,RegisterPanel=RegisterPanel,Label=Label,Button=Button,Capture=Capture,Suspend=SuspendForChild,
  CloseOwned=CloseOwnedChild,Modal=function() return modal end,
  SetModal=function(frame) modal=frame end}
function X.DailyAPI.RegisterHost(frame,adapter)
  frame.dailyCaptureAdapter=adapter
  if frame.dailyHostRegistered then return end
  frame.dailyHostRegistered=true
  frame:HookScript("OnHide",function(self)
    local deferred=CloseOwnedChild(self)
    Capture(self,false)
    self.inputGeneration=(self.inputGeneration or 0)+1
    if not deferred then self.activeChild,self.inputChildToken=nil,nil end
    self.dailyNavigationReturn=nil
  end)
end
