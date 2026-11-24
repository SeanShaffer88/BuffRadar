-- Actual native UI integration, privacy and input-boundary regressions.
return function(step,fresh)
  step("eight UI: daily open is read-only and routes remain explicit",function()
    local f=fresh({matrixView=false,selfStatusStrip=false},true)
    local X,c,db=f.X,f.client,f.db
    local scans,casts,sends=0,0,0
    X.Refresh=function() scans=scans+1 end
    X.Core.MakeMacro=function() casts=casts+1 end
    c.SendAddonMessage=function() sends=sends+1 end
    X.Daily.Open()
    local frame=assert(X.Daily.Frame())
    assert(frame:IsShown() and scans==0 and casts==0 and sends==0)
    assert(not db.matrixView and not db.selfStatusStrip)
    assert(not frame.scripts.OnUpdate,"daily panel must be event driven")
    for _,button in ipairs(frame.buttons) do
      assert(button.size[2]==27 and -button.points[1][3]+button.size[2]<=frame.size[2],"daily button exceeds panel")
    end
    frame.scripts.OnKeyDown(frame,"TAB")
    assert(frame.focusIndex==1)
    c.__combat=true
    frame.scripts.OnEvent(frame,"PLAYER_REGEN_DISABLED")
    frame.scripts.OnKeyDown(frame,"ENTER")
    assert(casts==0 and scans==0 and sends==0)
  end)
  step("eight UI: safe export scope, reusable review and keyboard return",function()
    local f=fresh({},true);local X=f.X
    X.Daily.Open();X.Daily.Share()
    local review=assert(X.Daily.ReviewFrame())
    assert(review.model.scope=="preferences")
    f.client.__combat=true;review.scripts.OnEvent(review,"PLAYER_REGEN_DISABLED")
    assert(not review.keyboard,"combat review captured keyboard")
    f.client.__combat=false;review.scripts.OnEvent(review,"PLAYER_REGEN_ENABLED")
    assert(review.keyboard and not X.Daily.Frame().keyboard,"review keyboard did not return after combat")
    local count=#f.client.__frames
    for _=1,20 do X.Daily.Share() end
    assert(#f.client.__frames==count,"review leaks frames on repeated open")
    review.buttons[2]:Click()
    assert(X.exportFrame:IsShown() and X.exportFrame.editBox:GetText()==review.model.text)
    f.client.__combat=true;review.scripts.OnEvent(review,"PLAYER_REGEN_DISABLED")
    f.client.__combat=false;review.scripts.OnEvent(review,"PLAYER_REGEN_ENABLED")
    assert(not review.keyboard,"review captured underneath export child after combat")
    X.exportFrame:Hide()
    assert(review:IsShown() and review.keyboard,"child close did not return review keyboard")
    review.buttons[2]:Click();f.client.__combat=true;X.exportFrame:Hide()
    assert(not review.keyboard,"child close captured review during combat")
    f.client.__combat=false;review.scripts.OnEvent(review,"PLAYER_REGEN_ENABLED")
    assert(review.keyboard,"un-nested review did not resume after combat")
    review.buttons[2]:Click();review:Hide();X.exportFrame:Hide()
    assert(not review.keyboard,"closed review resurrected after child close")
    X.Daily.Share();review=X.Daily.ReviewFrame()
    review.buttons[1]:Click()
    assert(review.model.scope=="full","full backup requires explicit scope action")
    X.Daily.Recent()
    assert(not review.model,"undo review retained a sharing payload")
  end)
  step("eight UI: settings intent search is reordered, bounded and read-only",function()
    local f=fresh({},true);local X=f.X
    X.OpenConfig(true)
    local cfg=f.client.BuffRadarConfig
    assert(#X.CfgSearch("/br scale")>0)
    local initial=X.CfgSearch("/br daily");assert(#initial>0)
    X.CfgAlias(cfg.dailyBtn,{"alpha beta gamma","/br daily"})
    assert(#X.CfgSearch("gamma alpha")>0)
    assert(#X.CfgSearch(X.L["change window size"])>0)
    assert(#X.CfgSearch(X.L["can't see players"])>0)
    assert(#X.CfgSearch(string.rep("a",81))==0)
    local before=f.db.matrixView
    X.OpenDailyOptions()
    assert(cfg.dailyOptions:IsShown() and f.db.matrixView==before)
    local a=X.CfgSearch("/br daily"); local b=X.CfgSearch("/br daily")
    assert(#a==#b and a[1].widget==b[1].widget)
  end)
  step("eight UI: child dialogs return keyboard only to their live daily generation",function()
    local f=fresh({matrixView=true},true);local X,c=f.X,f.client
    X.Daily.Open();local d=X.Daily.Frame()
    local function click(label)
      for _,b in ipairs(d.buttons) do if b:GetText()==X.L[label] then b:Click();return end end
      error("missing route "..label)
    end
    click("Open Buff List");X.GetFrame():Hide();assert(d.keyboard,"buff list close lost keyboard")
    click("Coverage Matrix");local m=assert(X.Views.GetMatrixFrame());m:Hide()
    assert(d.keyboard,"matrix close lost keyboard")
    click("Supplies");local s=assert(X.Supplies.GetFrame());s:Hide()
    assert(d.keyboard,"supplies close lost keyboard")
    click("Supplies");d:Hide();s:Hide();assert(not d.keyboard,"closed parent regained keyboard")
    X.Daily.Open();click("Supplies")
    c.__combat=true;s:Hide()
    assert(not d.keyboard,"combat close enabled keyboard")
  end)

  step("eight UI: cycle, role and color gestures record one reversible preference",function()
    local f=fresh({},true);local X,c,db=f.X,f.client,f.db
    X.OpenConfig(true);local cfg=c.BuffRadarConfig
    local before=db.sortMode;cfg.sortBtn:Click()
    local history=X.Preferences.History()
    assert(#history>0 and db.sortMode~=before)
    assert(X.Preferences.Undo(history[1].id) and db.sortMode==before)
    before=db.roleFilter
    local chip=c.BuffRadarChipTANK
    chip:Click();history=X.Preferences.History()
    assert(db.roleFilter=="TANK" and history[1].changes[1].key=="roleFilter")
    assert(X.Preferences.Undo(history[1].id) and db.roleFilter==before)
    local picker=c.ColorPickerFrame;local options
    picker.SetupColorPickerAndShow=function(self,args) options=args;self:Show() end
    picker.GetColorRGB=function() return 0.7,0.6,0.5 end
    local previous=db.theme;local count=#X.Preferences.History()
    cfg.swatch:Click();options.swatchFunc();options.swatchFunc()
    assert(#X.Preferences.History()==count,"color preview created history")
    options.cancelFunc();picker:Hide()
    assert(db.theme==previous and #X.Preferences.History()==count,"cancel created history")
    cfg.swatch:Click();options.swatchFunc();picker:Hide()
    history=X.Preferences.History()
    assert(#history==count+1 and db.theme=="custom","accepted color was not one gesture")
    assert(X.Preferences.Undo(history[1].id) and db.theme==previous)
  end)

  step("eight UI: stale color callbacks cannot write replacement, future, combat or reopened state",function()
    for _,mode in ipairs({"replacement","future","combat","reopen"}) do
      local f=fresh({theme="forest"},true);local X,c=f.X,f.client
      X.OpenConfig(true);local cfg=c.BuffRadarConfig;local picker=c.ColorPickerFrame;local options
      picker.SetupColorPickerAndShow=function(self,args) options=args;self:Show() end
      picker.GetColorRGB=function() return 0.7,0.6,0.5 end
      cfg.swatch:Click();options.swatchFunc();local old=options
      if mode=="replacement" then c.BuffRadarDB={dbVersion=24,theme="crimson"};f.event("ADDON_LOADED","BuffRadar");X.OpenConfig(true)
      elseif mode=="future" then c.BuffRadarDB={dbVersion=999,theme="crimson"};f.event("ADDON_LOADED","BuffRadar")
      elseif mode=="combat" then c.__combat=true
      else cfg.swatch:Click();options.swatchFunc() end
      local db=X.GetDB();local theme,color=db.theme,db.bgColor
      old.cancelFunc();old.swatchFunc()
      if mode~="reopen" then picker:Hide() end
      assert(X.GetDB()==db and db.theme==theme and db.bgColor==color,"stale picker wrote "..mode)
      if mode=="reopen" then options.cancelFunc();picker:Hide() end
    end
  end)

  step("eight UI: closing parents closes owned descendants and defers unrelated or protected children",function()
    local f=fresh({},true);local X,c=f.X,f.client
    X.Daily.Open();X.Daily.Share();local d,r=X.Daily.Frame(),X.Daily.ReviewFrame()
    r.buttons[2]:Click();r:Hide()
    assert(not X.exportFrame:IsShown() and not r.keyboard and d.keyboard,"owned export survived review close")
    X.Daily.Share();r.buttons[2]:Click();d:Hide()
    assert(not d.keyboard and not r:IsShown() and not r.keyboard and not X.exportFrame:IsShown(),"owned descendant survived Daily close")
    X.Daily.Open();X.Daily.Share();r.buttons[2]:Click()
    X.ShowExport("unrelated copy",false,X.L["Copy"])
    r:Hide()
    assert(X.exportFrame:IsShown() and not d.keyboard and not r.keyboard,"reused export was hidden or background captured")
    X.exportFrame:Hide();assert(d.keyboard,"surviving child did not release ancestor")
    local native=c.SettingsPanel
    native.IsProtected=function() return true end
    X.Core.OpenKeybinds=function() native:Show() end
    for _,button in ipairs(d.buttons) do if button:GetText()==X.L["Cast next buff"] then button:Click() end end
    c.__combat=true;d:Hide()
    assert(native:IsShown() and not d.keyboard,"combat close hid protected child")
    c.__combat=false;native:Hide();assert(not d.keyboard,"protected child revived closed Daily")
  end)

end
