-- Core freshness, identity-sharing and ordinary preference regressions.
return function(step, fresh)
  step("eight core: actual scan freshness keeps success separate from pause/failure", function()
    local f = fresh({ includeSelf=false, pauseInCities=false }, true)
    local X, c = f.X, f.client
    c.__over.GetTime = function() return 1000 end
    X.Refresh()
    local first = X.Status.Freshness()
    assert(first.state == "current" and first.lastCompletedAt == 1000)
    c.__over.GetTime = function() return 1002 end
    X.Refresh()
    local second = X.Status.Freshness()
    assert(second.generation > first.generation and second.lastCompletedAt == 1002)
    X.Status.Unavailable("paused")
    assert(X.Status.Freshness().state == "paused" and X.Status.Freshness().lastCompletedAt == 1002)
    X.RefreshFault("fixture scan failure")
    assert(X.Status.Freshness().state == "unavailable" and X.Status.Freshness().lastCompletedAt == 1002)
    c.__over.GetTime = function() return 1020 end
    X.Refresh()
    assert(X.Status.Freshness().state == "current")
    assert(X.Status.Freshness(0).state == "unavailable")
  end)
  step("eight core: preferences sharing preserves recipient identities", function()
    local f = fresh({ includeSelf=false, pauseInCities=false }, true)
    local X, db = f.X, f.db
    local private = "Secret-Player名字"
    db.ignored[private], db.pinned = true, private
    local preview = assert(X.SharePreview())
    assert(preview.scope == "preferences" and preview.text:find("identity=excluded",1,true))
    assert(not preview.text:find(private,1,true) and db.pinned == private and db.ignored[private])
    local recipient = fresh({ includeSelf=false, pauseInCities=false }, true)
    recipient.db.ignored["Keep-Recipient"], recipient.db.pinned = true, "Keep-Recipient"
    assert(recipient.X.Import(preview.text))
    assert(recipient.db.ignored["Keep-Recipient"] and recipient.db.pinned == "Keep-Recipient")
    local full = assert(X.SharePreview("full"))
    assert(full.text:find(private,1,true),"full omitted identity")
    local imported,why=recipient.X.Import(full.text);assert(imported,tostring(why).." :: "..full.text)
    assert(recipient.db.ignored[private] and recipient.db.pinned == private)
    assert(not X.ParseProfile(preview.text .. ";identity=excluded"))
    assert(not X.ParseProfile(preview.text .. ";ignored.Bad=1"))
  end)
  step("eight core: preference undo is atomic bounded and detached", function()
    local f = fresh({ includeSelf=false, pauseInCities=false }, true)
    local X, db, c = f.X, f.db, f.client
    local P = assert(X.Preferences)
    assert(P.Set("includeSelf",true,"ui")); local h = P.History(); assert(#h == 1)
    assert(P.Undo(h[1].id)); assert(db.includeSelf == false)
    assert(P.Set("enabled.FORTITUDE",false,"ui")); assert(P.Undo()); assert(db.enabled.FORTITUDE == nil)
    assert(P.Begin("slider")); assert(P.Set("scale",1.1)); assert(P.Set("scale",1.2)); assert(P.Commit())
    h=P.History(); assert(#h == 1 and #h[1].changes == 1)
    h[1].changes[1].after = 999; assert(P.History()[1].changes[1].after == 1.2)
    db.scale = 1.3; assert(not P.Undo() and db.scale == 1.3)
    for i=1,25 do assert(P.Set("rebuff",i,"slash")) end
    assert(#P.History() <= 20)
    c.InCombatLockdown = function() return true end
    assert(not P.Undo())
    assert(not P.Set("castsTotal",0,"ui"))
  end)
  step("eight core: freshness copies and attempts never invent completion", function()
    local f=fresh({pauseInCities=false},true);local S=f.X.Status
    f.client.__over.GetTime=function() return 2000 end;f.X.Refresh()
    local a=S.Freshness();local gen=a.generation;a.generation=999
    assert(S.Freshness().generation==gen and S.Freshness(2020).state=="stale")
    f.client.__over.GetTime=function() return 2001 end;S.Attempt();S.Unavailable("paused")
    assert(S.Freshness().generation==gen and S.Freshness().lastCompletedAt==2000)
    f.client.__over.GetTime=function() return -1 end;S.Attempt()
    assert(S.Freshness().state=="unavailable" and S.Freshness().lastCompletedAt==2000)
  end)
  step("eight core: sharing excludes identity stores and copies preview counts", function()
    local f=fresh({},true);local X,db=f.X,f.db
    db.ignored.PrivateIgnored=true;db.pinned="PrivatePinned"
    db.activeProfile="PrivateProfile";db.autoProfile.raid="PrivateAuto"
    db.specProfiles.s1="PrivateSpec";db.profiles.PrivateProfile=X.ProfileSnapshot()
    local p=assert(X.SharePreview());local n=assert(X.SharePreview("preferences","PrivateProfile"))
    for _,name in ipairs({"PrivateIgnored","PrivatePinned","PrivateProfile","PrivateAuto","PrivateSpec"}) do
      assert(not p.text:find(name,1,true) and not n.text:find(name,1,true))
    end
    assert(n.text:find("BuffRadar profile: Shared",1,true))
    assert(not X.ParseProfile(p.text:gsub("identity=excluded","identity=invalid",1)))
    assert(not X.Import(string.rep("x",16385)))
    p.counts.ignored=99;assert(X.SharePreview().counts.ignored==0)
  end)
  step("eight core: preference failures roll back and future saves remain untouched", function()
    local f=fresh({},true);local P,db=f.X.Preferences,f.db
    local old=db.scale
    assert(not P.Capture(function() db.scale=1.5;error("fixture") end,"ui") and db.scale==old)
    local huge={};for j=1,5000 do huge["KEY"..j]=true end
    assert(not P.Set("enabled",huge) and P.Usage().bytes<=65536)
    local map={FORTITUDE=false};assert(P.Set("enabled",map));map.FORTITUDE=true
    assert(db.enabled.FORTITUDE==false)
    assert(not P.Set("pinned","identity") and not P.Set("syncPlayers",{}))
    local future=fresh({dbVersion=999,scale=1},true)
    assert(not future.X.Preferences.Set("scale",1.5) and not future.X.Preferences.Undo())
    assert(not P.Undo({}) and not P.Set("restockSpendCap",0/0))
    f.client.BuffRadarDB={dbVersion=24};f.event("ADDON_LOADED","BuffRadar")
    assert(#P.History()==0 and not P.Undo())
  end)
  step("eight core: evidence commits atomically and getters never query units", function()
    local f=fresh({pauseInCities=false,matrixView=true,selfStatusStrip=true},true)
    local X,c=f.X,f.client;X.Refresh()
    local before=X.CoverageEvidence("group")
    assert(before.generation>0 and #before.members<=40 and #before.buffs<=24)
    local own=X.CoverageEvidence("self");assert(#own.members==1 and #own.buffs<=16)
    assert(#before.members>0 and #before.buffs>0)
    local k=before.buffs[1].key;before.members[1].cells[k].state="corrupted"
    assert(X.CoverageEvidence().members[1].cells[k].state~="corrupted")
    X.BeginCoverageEvidence();local gen=X.CoverageEvidence().generation
    assert(gen==before.generation)
    c.UnitExists=function() error("getter queried host") end
    assert(X.CoverageEvidence().generation==gen and X.CoverageEvidence("self").generation==gen)
    X.Status.Unavailable("combat");assert(X.CoverageEvidence().generation==gen)
  end)

end
