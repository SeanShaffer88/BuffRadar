-- Domain regression cases for reviewed copy/import/recovery/update boundaries.
return function(step,fresh,TestClient,LoadClient,forever)
  step('five core: configured assignment copy preserves false/default/custom and rejects drift',function()
    if not forever then return end
    local f=fresh({},true);local X=f.X
    assert(X.AssignmentCopy,'assignment-copy domain missing')
    assert(X.SetAssignment('MAGE','ALL',false));assert(X.SetAssignment('PRIEST','ALL',{FORTITUDE=true}))
    local draft=assert(X.AssignmentCopy.Stage('cell',{class='MAGE',slot='ALL'},{class='PRIEST',slot='ALL'}))
    assert(f.db.buffAssignments.PRIEST.ALL.FORTITUDE and #draft.changes==1)
    draft.changes[1].after={THORNS=true}
    assert(X.AssignmentCopy.Apply(draft));assert(f.db.buffAssignments.PRIEST.ALL==false)
    local clear=assert(X.AssignmentCopy.Stage('cell',{class='MAGE',slot='WORLD'},{class='PRIEST',slot='ALL'}))
    assert(X.AssignmentCopy.Apply(clear));assert(f.db.buffAssignments.PRIEST==nil)
    local d=assert(X.AssignmentCopy.Stage('row',{class='MAGE'},{class='PRIEST'}))
    X.SetAssignment('MAGE','TANK',{FORTITUDE=true})
    assert(not X.AssignmentCopy.Apply(d));assert(f.db.buffAssignments.PRIEST==nil)
  end)
  step('five core: selected imports validate entire input then preserve excluded data',function()
    local f=fresh({},true);local X,db=f.X,f.db
    assert(X.ProfileSections,'section import domain missing')
    db.scale=1.5;db.playSound=false;local text=X.Export();db.scale=1;db.playSound=true
    db.ignored.Private=true;db.pinned='Private';db.sync=false
    local d=assert(X.ProfileSections.Stage(text,{appearance=true}))
    assert(X.ProfileSections.Apply(d));assert(db.scale==1.5 and db.playSound==true and db.sync==false and db.ignored.Private and db.pinned=='Private')
    assert(not X.ProfileSections.Stage(text..';unknown=1',{appearance=true}))
    assert(not X.ProfileSections.Stage(text,{}))
    local conflict=assert(X.ProfileSections.Stage(text,{appearance=true}));db.scale=1.2
    assert(not X.ProfileSections.Apply(conflict) and db.scale==1.2)
  end)
  step('five core: legacy bootstrap capture is bounded copied and retained on same-version reload',function()
    local f=fresh({scale=9,ignored={Private=true},castsTotal=7},true,function(c) c.GetAddOnMetadata=function() return "1.17.0" end;c.BuffRadarDB.lastSeenAddonVersion=nil end)
    local X,db=f.X,f.db;assert(X.Recovery,'recovery domain missing')
    local summary=X.Recovery.Snapshot();assert(summary.available and summary.bootstrap and summary.fromVersion==nil)
    assert(db.scale==2 and db.restorePoint.preferences.scale==9 and db.castsTotal==7 and db.ignored.Private)
    assert(X.Updates.Pending());assert(X.Updates.Dismiss());assert(not X.Updates.Pending())
    local original=db.restorePoint;f.event('ADDON_LOADED','BuffRadar')
    assert(X.Recovery.Snapshot().available and not X.Updates.Pending())
    assert(f.X.GetDB().restorePoint~=original,'restore point aliases previous save')
    local draft=assert(X.Recovery.Preview());local before=f.X.GetDB().scale
    f.X.GetDB().scale=1.3;assert(not X.Recovery.Apply(draft) and f.X.GetDB().scale==1.3)
    assert(before==2)
  end)
  step('five core: whole imports retain near-limit legacy identity maps and selected scopes never include them',function()
    local f=fresh({},true);local X,db=f.X,f.db
    for n=1,192 do db.ignored[string.format('%03d',n)..string.rep('A',57)..'-X']=true end
    local text=assert(X.Export());assert(#text>12000 and #text<=16384)
    local parsed=assert(X.ParseSettingsImport(text))
    local whole=assert(X.ProfileSections.Filter(parsed,nil));assert(X.Settings.Count(whole.ignored)==192)
    local partial=assert(X.ProfileSections.Filter(parsed,{appearance=true,alerts=true,buffrules=true}))
    for _,key in ipairs({'ignored','pinned','sync','requests','joinDigest','buddySplit','readyPost','wipeReport','autoProfile','restockEnabled','restockTargets'}) do assert(partial[key]==nil,key) end
    assert(X.ProfileSections.Stage(text,nil))
    local registry=X.ProfileSections.Registry();registry.appearance.scale=nil
    assert(X.ProfileSections.Registry().appearance.scale)
    assert(not X.ProfileSections.Filter(parsed,{unknown=true}))
  end)
  step('five core: assignment rows are bounded atomic and current-group review catches context changes',function()
    if not forever then return end
    local f=fresh({},true);local X,db,c=f.X,f.db,f.client
    X.SetAssignmentEnabled(true);X.SetAssignment('MAGE','ALL',false);X.SetAssignment('MAGE','TANK',{FORTITUDE=true})
    X.SetAssignment('PRIEST','ALL',{FORTITUDE=true})
    local d=assert(X.AssignmentCopy.Stage('row',{class='MAGE'},{class='PRIEST'}));assert(#d.changes>=2 and #d.rows>0)
    local before=X.Recovery.Copy(db.buffAssignments)
    local change=X.SettingsChanged;X.SettingsChanged=function()error('fixture')end
    assert(not X.AssignmentCopy.Apply(d));X.SettingsChanged=change
    assert(X.Recovery.Equal(before,db.buffAssignments),'half-applied row')
    assert(X.AssignmentCopy.Apply(d));assert(db.buffAssignments.PRIEST.ALL==false and db.buffAssignments.PRIEST.TANK.FORTITUDE)
    assert(db.buffAssignments.PRIEST.TANK~=db.buffAssignments.MAGE.TANK)
    local empty=assert(X.AssignmentCopy.Stage('row',{class='MAGE'},{class='MAGE'}));assert(#empty.changes==0)
    assert(not X.AssignmentCopy.Stage('cell',{class='NOPE',slot='ALL'},{class='MAGE',slot='ALL'}))
    assert(not X.AssignmentCopy.Stage('row',{class='MAGE',slot='ALL'},{class='PRIEST'}))
    assert(not X.SetAssignment('MAGE','ALL',{AMPLIFY_MAGIC=true,DAMPEN_MAGIC=true}))
    assert(not X.SetAssignment('MAGE','ALL',{BLESS_KINGS=true,BLESS_MIGHT=true}))
    local drift=assert(X.AssignmentCopy.Stage('cell',{class='MAGE',slot='ALL'},{class='PRIEST',slot='ALL'}))
    f.units.party2[1]='Changed';assert(not X.AssignmentCopy.Apply(drift));f.units.party2[1]='Bren'
    drift=assert(X.AssignmentCopy.Stage('cell',{class='MAGE',slot='ALL'},{class='PRIEST',slot='ALL'}))
    X.SetAssignment('PRIEST','ALL',{DIVINE_SPIRIT=true});assert(not X.AssignmentCopy.Apply(drift))
    drift=assert(X.AssignmentCopy.Stage('cell',{class='MAGE',slot='ALL'},{class='PRIEST',slot='ALL'}))
    c.__combat=true;assert(not X.AssignmentCopy.Apply(drift))
  end)
  step('five core: first install and schema-only saves establish no restore point or pending notice',function()
    for _,initial in ipairs({false,{dbVersion=24}}) do
      local c=TestClient();c.GetAddOnMetadata=function()return '1.17.0'end
      c.BuffRadarDB=initial or nil
      local X,start=LoadClient(c)
      start.scripts.OnEvent(start,'ADDON_LOADED','BuffRadar')
      assert(X.GetDB().lastSeenAddonVersion=='1.17.0' and not X.Recovery.Snapshot().available and not X.Updates.Pending())
    end
  end)
  step('five core: numeric upgrades capture raw preferences once and reject unsafe oversized snapshots',function()
    local f=fresh({},true);local R=f.X.Recovery
    local raw={scale=9,lastSeenAddonVersion='1.9.0',ignored={Private=true},castsTotal=13,profiles={Private='BR1;'},sync=true}
    local nextSave=assert(R.BeforeNormalize(raw,'1.10.0',{}))
    assert(nextSave.restorePoint.fromVersion=='1.9.0' and nextSave.restorePoint.preferences.scale==9)
    for _,key in ipairs({'ignored','castsTotal','profiles','sync','restorePoint','lastSeenAddonVersion'}) do assert(nextSave.restorePoint.preferences[key]==nil,key) end
    raw.scale=1;assert(nextSave.restorePoint.preferences.scale==9)
    nextSave.scale=1.5
    local same=R.BeforeNormalize(nextSave,'1.10.0',{});assert(same.restorePoint.preferences.scale==9)
    local down=R.BeforeNormalize(nextSave,'1.8.0',{});assert(down.lastSeenAddonVersion=='1.10.0' and down.restorePoint.preferences.scale==9)
    assert(not R.BeforeNormalize(nextSave,'1.11.0',{saveState='future'}))
    assert(not R.BeforeNormalize(nextSave,'1.11.0',{saveState='overflow'}))
    local huge={};for n=1,3000 do huge['KEY'..n]=true end
    nextSave.enabled=huge
    local refused=R.BeforeNormalize(nextSave,'1.11.0',{});assert(refused.restorePoint.preferences.scale==9)
    nextSave.enabled=nil;nextSave.scale=0/0
    assert(R.BeforeNormalize(nextSave,'1.11.0',{}).restorePoint.preferences.scale==9)
    nextSave.scale=setmetatable({},{})
    assert(R.BeforeNormalize(nextSave,'1.11.0',{}).restorePoint.preferences.scale==9)
    assert(R.CompareVersions('1.10.0','1.9.0')==1 and not R.ValidVersion('01.2.3') and not R.ValidVersion('1.2'))
  end)
  step('five core: explicit restore is copied conflict-bound and preserves excluded live data',function()
    local f=fresh({scale=1.4,castsTotal=9,ignored={Private=true},profiles={Keep='BR1;width=240'}},true,function(c)
      c.GetAddOnMetadata=function()return '1.17.0'end;c.BuffRadarDB.lastSeenAddonVersion=nil
    end)
    local X,db=f.X,f.db;db.scale=1
    local d=assert(X.Recovery.Preview());d.lines[1]='tampered'
    assert(X.Recovery.Apply(d));assert(db.scale==1.4 and db.castsTotal==9 and db.ignored.Private and db.profiles.Keep)
    assert(X.Recovery.Snapshot().available and #X.Preferences.History()==1)
    local d2=assert(X.Recovery.Preview());db.restorePoint.preferences.scale=1.2
    assert(not X.Recovery.Apply(d2) and db.scale==1.4)
    local old=X.Updates.Model();old.items[1]='tampered';assert(X.Updates.Model().items[1]~='tampered')
    local shown=0;X.ShowUpdates=function()shown=shown+1;return true end
    X.UpdatesBlocked=function()return true end;assert(not X.Updates.Show(true) and shown==0)
    X.UpdatesBlocked=function()return false end;assert(X.Updates.Show(true) and shown==1)
    f.client.InCombatLockdown=function()return true end;assert(not X.Updates.Dismiss())
  end)

  step('five core: actual future and overflow loads preserve original recovery metadata without capture',function()
    for _,mode in ipairs({'future','overflow'}) do
      local input={dbVersion=mode=='future' and 999 or 23,scale=1.5,lastSeenAddonVersion='1.16.0',updatesPendingVersion='1.16.0'}
      if mode=='overflow' then input.profiles={};for n=1,33 do input.profiles['P'..n]='BR1;width=240' end end
      local original
      local f=fresh(input,true,function(c)
        c.GetAddOnMetadata=function()return '1.17.0'end;original=c.BuffRadarDB
      end)
      assert(f.client.BuffRadarDB==original and original.lastSeenAddonVersion=='1.16.0' and original.updatesPendingVersion=='1.16.0' and original.restorePoint==nil)
      assert(f.X.Settings.SaveState()==mode and not f.X.Recovery.Preview() and not f.X.Updates.Pending())
    end
  end)
  step('five core: checkpoint refuses secret and deep data without traversing unknown save fields',function()
    local f=fresh({},true);local R,c=f.X.Recovery,f.client
    local good=R.BeforeNormalize({scale=1.4,lastSeenAddonVersion='1.16.0'},'1.17.0',{})
    local secret={};c.issecretvalue=function(v)return v==secret end
    good.scale=secret
    local declined=R.BeforeNormalize(good,'1.18.0',{})
    assert(declined.restorePoint.preferences.scale==1.4)
    assert(not R.ValidateRecord({format=secret,toVersion='1.17.0',preferences={scale=1}}).format)
    good.scale=1.2;good.enabled={A={B={C={D={E={F={G={H=true}}}}}}}}
    assert(R.BeforeNormalize(good,'1.18.0',{}).restorePoint.preferences.scale==1.4)
    local arbitrary={};arbitrary.loop=arbitrary
    local safe=R.BeforeNormalize({scale=1.3,unknown=arbitrary},'1.17.0',{})
    assert(safe.restorePoint.preferences.scale==1.3 and safe.restorePoint.preferences.unknown==nil)
  end)
  step('five core: account-wide dismissal survives a second character while eligibility stays event-driven',function()
    local f=fresh({scale=1.4},true,function(c)
      c.GetAddOnMetadata=function()return '1.17.0'end;c.BuffRadarDB.lastSeenAddonVersion=nil
    end)
    local X,c=f.X,f.client;local shown=0
    X.ShowUpdates=function()shown=shown+1;return true end;X.UpdatesBlocked=function()return false end
    c.__combat=true;assert(X.Updates.Pending() and not X.Updates.Show() and shown==0)
    c.__combat=false;assert(X.Updates.Show() and shown==1 and X.Updates.Pending())
    assert(X.Updates.Dismiss() and not X.Updates.Pending())
    local shared=X.GetDB();shared.scale=1.1
    local second=TestClient();second.BuffRadarDB=shared;second.GetAddOnMetadata=function()return '1.17.0'end
    local Y,start=LoadClient(second);start.scripts.OnEvent(start,'ADDON_LOADED','BuffRadar')
    assert(not Y.Updates.Pending() and Y.GetDB().scale==1.1 and Y.GetDB().restorePoint.preferences.scale==1.4)
    assert(Y.Updates.Model().version=='1.17.0' and #Y.Updates.Model().items==3)
  end)

end
