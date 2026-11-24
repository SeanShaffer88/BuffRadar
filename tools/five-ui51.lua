-- Actual picker, copy/import/recovery and update-dialog integration contracts.
return function(step,fresh)
  local function New(saved,setup)
    saved=saved or {};saved.lastSeenAddonVersion=saved.lastSeenAddonVersion or "1.17.0"
    return fresh(saved,true,function(c,units)
      c.GetAddOnMetadata=function() return "1.17.0" end
      if setup then setup(c,units) end
    end)
  end
  step("five UI: issue47 Mage All Roles Thorns Done X Escape keep grid and selection",function()
    for _,navigate in ipairs({false,true}) do for _,path in ipairs({"done","x","escape"}) do
      local f=New();local X,c=f.X,f.client
      if X.classic then
        X.AssignmentOptions=function()return {{key="THORNS",name="Thorns"}}end
        X.OpenConfig(true);X.OpenAssignments()
        local cfg,panel=c.BuffRadarConfig,c.BuffRadarAssignments
        if navigate then f.slash("config navigate") end
        local cell=panel.cells.MAGE.ALL;cell:Click();local picker=panel.picker
        assert(picker.keyboard,"first picker open has no native Escape input")
        local option=picker.options[1];option:SetChecked(true);option:Click()
        assert(X.GetAssignment("MAGE","ALL").THORNS)
        if path=="done" then picker.backButton:Click()
        elseif path=="x" then picker.closeButton:Click()
        elseif navigate then cfg.navInput.scripts.OnEscapePressed(cfg.navInput)
        else picker.scripts.OnKeyDown(picker,"ESCAPE") end
        assert(not picker:IsShown() and panel:IsVisible() and panel.closeButton:IsVisible(),path.." closed grid")
        assert(X.GetAssignment("MAGE","ALL").THORNS,path.." discarded immediate selection")
        if navigate then assert(cfg.navInput:HasFocus() and cfg.navOutline.points[1][2]==cell,"origin focus lost") end
        cell:Click();assert(picker.keyboard,"reopened picker has no native Escape input");cfg:Hide();assert(not picker:IsVisible() and not cfg.navInput:HasFocus())
      end
    end end
  end)
  step("five UI: assignment copy stages, rejects stale clicks and returns picker focus",function()
    local f=New();local X,c=f.X,f.client;if not X.classic then return end
    X.SetAssignment("MAGE","ALL",{FORTITUDE=true});X.SetAssignment("WARRIOR","TANK",false)
    X.OpenConfig(true);X.OpenAssignments();f.slash("config navigate")
    local cfg,panel=c.BuffRadarConfig,c.BuffRadarAssignments
    panel.cells.MAGE.ALL:Click();panel.picker.copyCell:Click()
    local frame=assert(X.Workflow.CopyFrame());assert(frame:IsShown() and not cfg.navInput:HasFocus())
    assert(frame:GetFrameLevel()>panel.picker:GetFrameLevel(),"copy rendered below its picker")
    for _=1,10 do if frame.dest.class=="WARRIOR" then break end;frame.classButton:Click() end
    for _=1,6 do if frame.dest.slot=="TANK" then break end;frame.slotButton:Click() end
    assert(frame.model and X.GetAssignment("WARRIOR","TANK")==false)
    local old=frame.apply:GetScript("OnClick");frame.slotButton:Click();old()
    assert(X.GetAssignment("WARRIOR","TANK")==false,"stale destination applied")
    for _=1,6 do if frame.dest.slot=="TANK" then break end;frame.slotButton:Click() end
    frame.apply:Click();assert(X.GetAssignment("WARRIOR","TANK").FORTITUDE and not frame:IsShown())
    assert(panel.picker:IsVisible() and cfg.navInput:HasFocus(),"copy close did not return picker navigation")
    panel.picker.copyRow:Click();frame=assert(X.Workflow.CopyFrame())
    assert(frame.model and not frame.slotButton:IsShown(),"row selector included an invalid slot")
    frame.back:Click();assert(panel.picker:IsVisible() and not frame:IsShown(),"copy Back lost picker")
    panel.picker.copyRow:Click()
    cfg:Hide();assert(not frame:IsShown() and not frame.keyboard,"settings close orphaned copy dialog")
  end)
  step("five UI: selected import applies displayed scope and invalidates old confirmation",function()
    local f=New();local X,db,c=f.X,f.db,f.client
    db.scale=1.4;db.playSound=true;local text=X.Export();db.scale=1;db.playSound=false
    db.ignored.Keep=true;db.pinned="Keep"
    X.ShowExport(text,true);local frame=c.BuffRadarExportFrame;frame.accept:Click()
    assert(frame.sectionWhole and frame.sectionMode:GetText()==X.L["Whole Profile"])
    frame.sectionMode:Click()
    for _,key in ipairs({"alerts","buffrules"}) do local box=frame.sectionChecks[key];box:SetChecked(false);box:Click() end
    assert(frame.sectionDraft and not frame.sectionDraft.all and db.scale==1)
    local old=frame.apply:GetScript("OnClick")
    frame.sectionChecks.appearance:SetChecked(false);frame.sectionChecks.appearance:Click()
    assert(not frame.apply:IsEnabled());old();assert(db.scale==1,"old confirmation ignored new selection")
    frame.sectionChecks.appearance:SetChecked(true);frame.sectionChecks.appearance:Click();frame.apply:Click()
    assert(db.scale==1.4 and db.playSound==false and db.ignored.Keep and db.pinned=="Keep")
    X.ShowExport(text,true);frame.accept:Click();frame.sectionMode:Click()
    frame.back:Click();assert(frame.editBox:IsShown() and not frame.sectionsPanel:IsShown())
  end)
  step("five UI: recovery is preview-only and stale callbacks cannot restore a reopened model",function()
    local f=New();local X,db=f.X,f.db
    db.scale=1.5;db.ignored.Keep=true;db.castsTotal=42
    db.restorePoint={format=1,fromVersion="1.16.0",toVersion="1.17.0",preferences={scale=1}}
    assert(X.Workflow.Recovery());local frame=assert(X.Workflow.RecoveryFrame())
    assert(frame.model and db.scale==1.5)
    local old=frame.apply:GetScript("OnClick");frame:Hide();db.scale=1.4;X.Workflow.Recovery();old()
    assert(db.scale==1.4,"closed review applied a new restore token")
    frame.apply:Click();assert(db.scale==1 and db.ignored.Keep and db.castsTotal==42 and db.restorePoint)
    X.Workflow.Recovery();frame:Hide();assert(not frame.keyboard)
  end)
  step("five UI: update notice has three localized items and all close paths dismiss",function()
    for _,path in ipairs({"dismiss","x","escape","daily"}) do
      local f=New();local X,c,db=f.X,f.client,f.db
      local before=X.Export();assert(X.Workflow.WhatsNew(true));local frame=X.Workflow.UpdatesFrame()
      assert(#frame.items==3 and not frame.scripts.OnUpdate)
      local model=X.Updates.Model();for i=1,3 do assert(frame.items[i]:GetText()==X.L[model.items[i]]) end
      if path=="dismiss" then frame.dismiss:Click() elseif path=="x" then frame.closeButton:Click()
      elseif path=="escape" then frame.scripts.OnKeyDown(frame,"ESCAPE") else frame.daily:Click() end
      assert(not frame:IsShown() and db.updatesDismissedVersion=="1.17.0" and X.Export()==before)
      if path=="daily" then assert(X.Daily.Frame():IsShown()) end
      assert(X.Workflow.WhatsNew(true),"manual reopen failed")
      c.__combat=true;frame:Hide();assert(frame.dismissPending)
      c.__combat=false;f.event("PLAYER_REGEN_ENABLED");assert(not frame.dismissPending)
    end
  end)
  step("five UI: pending updates defer for combat and owned editors",function()
    local f=New({lastSeenAddonVersion="1.16.0"},function(c)c.__combat=true end)
    local X,c=f.X,f.client;assert(X.Updates.Pending() and not X.Workflow.UpdatesFrame())
    c.__combat=false;X.OpenConfig(true);f.event("PLAYER_REGEN_ENABLED")
    assert(not X.Workflow.UpdatesFrame(),"update displaced settings")
    c.BuffRadarConfig:Hide();f.event("PLAYER_ALIVE")
    assert(X.Workflow.UpdatesFrame():IsShown(),"eligible pending update did not open")
  end)
  step("five UI: death suspends active dialog input and alive returns only to current live owner",function()
    local f=New();local X,c,db=f.X,f.client,f.db
    db.restorePoint={format=1,fromVersion="1.16.0",toVersion="1.17.0",preferences={scale=1}}
    X.Workflow.Recovery();local frame=X.Workflow.RecoveryFrame()
    assert(frame.keyboard)
    f.event("PLAYER_DEAD");assert(not frame.keyboard,"dead dialog retained input")
    frame.scripts.OnKeyDown(frame,"TAB");assert(frame.focusIndex==0,"dead dialog moved focus")
    f.event("PLAYER_ALIVE");assert(frame.keyboard,"alive did not restore current dialog")
    f.event("PLAYER_DEAD");frame:Hide();f.event("PLAYER_ALIVE")
    assert(not frame.keyboard,"alive revived closed dialog")
    X.Workflow.WhatsNew(true);frame=X.Workflow.UpdatesFrame();f.event("PLAYER_DEAD")
    assert(not frame.keyboard);frame:Hide();assert(frame.dismissPending)
    c.BuffRadarDB={dbVersion=24,lastSeenAddonVersion="1.17.0",updatesDismissedVersion=""}
    f.event("ADDON_LOADED","BuffRadar");f.event("PLAYER_ALIVE")
    assert(X.GetDB().updatesDismissedVersion=="","stale deferred dismissal wrote replacement")
  end)

  step("five UI: delayed alive unit flag resumes through the existing refresh",function()
    local dead=false
    local f=New({},function(c)c.__over.UnitIsDeadOrGhost=function(unit)return unit=="player" and dead end end)
    local X,db=f.X,f.db
    db.restorePoint={format=1,fromVersion="1.16.0",toVersion="1.17.0",preferences={scale=1}}
    X.Workflow.Recovery();local frame=X.Workflow.RecoveryFrame()
    dead=true;f.event("PLAYER_DEAD");f.event("PLAYER_ALIVE")
    assert(X.lifeCheckPending and not frame.keyboard)
    dead=false;f.advance(1,true);f.advance(0.1)
    assert(not X.PlayerSuspended() and frame.keyboard,"existing life recheck did not resume dialog")
  end)

  step("five UI: section import uses shared keyboard host and preserves paste focus",function()
    local f=New();local X,c=f.X,f.client
    X.ShowExport(X.Export(),true);local frame=c.BuffRadarExportFrame
    assert(frame.editBox:HasFocus() and not frame.keyboard)
    frame.accept:Click();assert(frame.keyboard and not frame.editBox:HasFocus())
    frame.scripts.OnKeyDown(frame,"TAB");assert(frame.buttons[frame.focusIndex]==frame.sectionMode)
    frame.scripts.OnKeyDown(frame,"ENTER");assert(not frame.sectionWhole)
    frame.scripts.OnKeyDown(frame,"TAB");assert(frame.buttons[frame.focusIndex]==frame.sectionChecks.appearance)
    frame.scripts.OnKeyDown(frame,"SPACE");assert(not frame.sectionSelection.appearance)
    c.__combat=true;frame:GetScript("OnEvent")(frame,"PLAYER_REGEN_DISABLED");assert(not frame.keyboard)
    c.__combat=false;frame:GetScript("OnEvent")(frame,"PLAYER_REGEN_ENABLED");assert(frame.keyboard)
    frame.back:Click();assert(frame.editBox:HasFocus() and not frame.keyboard)
    frame:GetScript("OnEvent")(frame,"PLAYER_REGEN_ENABLED")
    frame:GetScript("OnEvent")(frame,"PLAYER_ALIVE")
    assert(frame.editBox:HasFocus() and not frame.keyboard,"paste recaptured review keyboard")
    frame.accept:Click();assert(frame.keyboard,"Back then Review did not enable keyboard")
    f.event("PLAYER_DEAD")
    assert(not frame:IsShown() and not frame.keyboard,"death did not cancel export review")
    f.event("PLAYER_ALIVE");assert(not frame.keyboard,"alive revived canceled import")
    X.ShowExport(X.Export(),true);frame.accept:Click();assert(frame.keyboard,"reopened review has no keyboard");frame.scripts.OnKeyDown(frame,"ESCAPE")
    assert(not frame:IsShown() and not frame.keyboard and not frame.editBox:HasFocus())
    X.ShowExport("copy only",false)
    frame:GetScript("OnEvent")(frame,"PLAYER_REGEN_ENABLED");frame:GetScript("OnEvent")(frame,"PLAYER_ALIVE")
    assert(frame.editBox:HasFocus() and not frame.keyboard,"copy reuse captured review navigation")
    frame:Hide()
  end)

  step("five UI: import paste and review suspend existing modal owners across reuse and combat",function()
    local f=New();local X,c,db=f.X,f.client,f.db
    db.restorePoint={format=1,fromVersion="1.16.0",toVersion="1.17.0",preferences={scale=1}}
    X.Workflow.Recovery();local parent=X.Workflow.RecoveryFrame();assert(parent.keyboard)
    X.ShowExport(X.Export(),true);local child=c.BuffRadarExportFrame
    assert(child.editBox:HasFocus() and not parent.keyboard and not child.keyboard)
    child.accept:Click();assert(child.keyboard and not parent.keyboard and X.DailyAPI.Modal()==child)
    assert(child:GetFrameLevel()>parent:GetFrameLevel(),"import rendered below its modal parent")
    c.__combat=true;f.event("PLAYER_REGEN_DISABLED");c.__combat=false;f.event("PLAYER_REGEN_ENABLED")
    assert(child.keyboard and not parent.keyboard,"two modal controllers after combat")
    child.back:Click();f.event("PLAYER_REGEN_ENABLED")
    assert(child.editBox:HasFocus() and not child.keyboard and not parent.keyboard)
    child:Hide();assert(parent.keyboard and X.DailyAPI.Modal()==parent)
    X.ShowExport("unrelated",false);parent:Hide()
    assert(not child:IsShown() or not parent.keyboard)
    child:Hide();assert(not parent.keyboard)
  end)

  step("five UI: stale import child cannot replace a newer Daily modal generation",function()
    local f=New();local X,db=f.X,f.db
    db.restorePoint={format=1,fromVersion="1.16.0",toVersion="1.17.0",preferences={scale=1}}
    X.Workflow.Recovery();local old=X.Workflow.RecoveryFrame()
    X.ShowExport(X.Export(),true);local child=X.exportFrame;child.accept:Click()
    X.Daily.Open();assert(not child:IsShown() and not old:IsShown(),"root navigation left older controllers visible")
    local current=X.DailyAPI.Modal();child:Hide()
    assert(X.DailyAPI.Modal()==current and X.DailyAPI.Modal()~=old,"stale child revived older modal")
  end)

  step("five UI: plan review after settings review restores the original apply route",function()
    local f=New();local X,c,db=f.X,f.client,f.db
    X.ShowExport(X.Export(),true);local frame=c.BuffRadarExportFrame;frame.accept:Click();frame:Hide()
    X.assign.FORTITUDE="Me"
    local text=assert(X.PlanExport());X.assign.FORTITUDE=nil
    X.ShowExport(text,true,X.L["Review before applying"],"plan")
    frame.accept:Click();assert(frame.draft and not frame.sectionsPanel:IsShown())
    frame.apply:Click();assert(not frame:IsShown(),"prior section handler blocked plan apply")
    local expected=string.format(X.L["Plan applied locally: %d assignments, %d blessings, %d auto profiles."],1,0,0)
    assert(db==X.GetDB() and X.assign.FORTITUDE=="Me","reviewed plan data was not applied")
    assert(f.messages[#f.messages]:find(expected,1,true),"reviewed plan parts message missing")
  end)

end
