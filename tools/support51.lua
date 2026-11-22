-- Original privacy/lifecycle fixtures. Real cast correlation remains the authority.
return function(step, fresh)
  local function prepared(f)
    local X, c = f.X, f.client
    local button = assert(X.GetNextButton())
    assert(button.entry, "fixture needs an armed cast")
    local id = button.bActionID or (button.bSpell == "Arcane Intellect" and 1459
      or button.bSpell == "Divine Spirit" and 14752 or 1243)
    -- Retail's minimal base stub has no spell lookup API. Supply this known
    -- fixture spell contract so real correlation can verify its intended ID.
    if not c.C_Spell then
      c.C_Spell = {
        GetSpellName=function(value) if value == id then return button.bSpell end end,
        GetSpellIDForSpellIdentifier=function(value) if value == button.bSpell then return id end end,
      }
    end
    local name, realm = c.UnitFullName(button.entry.unit)
    local target = realm and (name .. "-" .. realm) or name
    return button, id, target
  end
  local function cast(f, token, terminal)
    local X = f.X
    local button, id, target = prepared(f)
    X.BeginCastClick(button, "LeftButton", false, "next-buff key")
    X.CastEvent("UNIT_SPELLCAST_SENT", "player", target, token, id)
    X.CastEvent(terminal or "UNIT_SPELLCAST_SUCCEEDED", "player", token, id)
    X.EndCastClick(button, "LeftButton", false, "next-buff key")
    return id
  end

  step("support: typed report excludes all free text and performs no external action", function()
    local f = fresh({ includeSelf=false, pauseInCities=false }, true)
    local X, c, db = f.X, f.client, f.db
    X.Refresh()
    local sentinel = "Private Name-Realm 玩家 87123"
    db.profiles[sentinel], db.activeProfile = "BR2;" .. sentinel, sentinel
    db.ignored[sentinel], db.history[1], db.customSpells[1] = true, { who=sentinel, spell=sentinel }, { name=sentinel }
    X.lastTargetCastProblem = { message=sentinel, guid=sentinel }
    c.__macros[1] = { name="BuffRadar", body="/say " .. sentinel }
    X.RefreshFault(sentinel)
    local before, writes, sends = db.castsTotal, c.__macroWrites, 0
    local function forbidden() sends = sends + 1; error("support performed an external action") end
    c.SendChatMessage, c.SendAddonMessage, c.OpenURL = forbidden, forbidden, forbidden
    c.CastSpellByName, c.CastSpellByID, c.EditMacro, c.CreateMacro = forbidden, forbidden, forbidden, forbidden
    if c.C_ChatInfo then c.C_ChatInfo.SendAddonMessage = forbidden end
    local report = X.Support.Report()
    assert(#report <= 16384 and report:find("BuffRadarSupport/1",1,true)==1 and not report:find(sentinel,1,true))
    assert(report:find("settings.includeSelf=false",1,true) and report:find("errors.unclassified=1",1,true))
    local allowed, seen = {}, {}
    for _, key in ipairs({ "client.interface", "settings.schema", "profiles.count", "buffs.supported",
      "discovery.actionable", "discovery.expiring", "cast.successSerial", "errors.unclassified",
      "timing.scan.samples", "timing.scan.lastMs", "errors.scan", "errors.blocked", "errors.forbidden",
      "sync.verified", "sync.awaiting", "sync.retrying", "sync.unverified", "sync.incompatible" }) do allowed[key]="number" end
    for _, key in ipairs({ "addon.supported", "settings.includeSelf", "settings.groupOnly", "settings.hidden",
      "settings.groupCast", "settings.modClick", "settings.assignmentEnabled", "settings.sync",
      "discovery.partial", "report.truncated", "sync.available" }) do allowed[key]="boolean" end
    local themes, addons = {custom=true}, {}
    for _, id in ipairs(X.THEME_ORDER) do themes[id]=true end
    for _, entry in ipairs(X.AUTO_THEME_ADDONS) do addons[entry[1]]=true end
    allowed["theme.selected"], allowed["theme.resolved"], allowed["theme.addon"] = themes, themes, addons
    allowed["client.version"], allowed["addon.version"], allowed["client.build"]="version","version","digits"
    allowed["client.locale"]={enUS=true,enGB=true,deDE=true,frFR=true,esES=true,ruRU=true,zhCN=true}
    allowed["addon.edition"]={Forever=true,Retail=true}
    allowed["settings.castMethod"]={target=true,rank=true,id=true,macro=true}
    allowed["settings.sortMode"]={name=true,role=true,distance=true,need=true}
    allowed["settings.roleFilter"]={ALL=true,TANK=true,HEALER=true,DAMAGER=true}
    allowed["profiles.context"]={solo=true,world=true,dungeon=true,raid=true,pvp=true}
    allowed["discovery.state"]={unavailable=true,attention=true,critical=true,covered=true,unknown=true}
    local reasons={ready=true,no_target=true,disarmed=true,recipient=true,unsafe=true,overflow=true,
      api=true,missing=true,unreadable=true,custom=true,combat=true,editor=true,running=true,sync=true}
    allowed["delivery.direct"],allowed["delivery.macro"]=reasons,reasons
    allowed["guide.state"]={inactive=true,discovering=true,blocked=true,ready=true,awaiting_user_cast=true,confirmed=true,paused=true}
    for line in report:gmatch("[^\n]+") do
      if line:find("=",1,true) then
        local key, value=line:match("^([%w%.]+)=(.*)$")
        local kind=key and allowed[key]
        assert(kind and not seen[key], "unexpected or duplicate report field: " .. tostring(key))
        seen[key]=true
        if value~="unknown" then
          if kind=="number" then local n=tonumber(value); assert(n and n>=0 and n<math.huge)
          elseif kind=="boolean" then assert(value=="true" or value=="false")
          elseif kind=="version" then assert(value:match("^%d+%.%d+%.%d+$") and #value<=24)
          elseif kind=="digits" then assert(value:match("^%d+$") and #value<=24)
          else assert(kind[value], "unexpected report enum") end
        end
      end
    end
    for key in pairs(allowed) do assert(seen[key], "missing typed report field: " .. key) end
    assert(X.Support.Report()==report and db.castsTotal==before and c.__macroWrites==writes and sends==0)
    db.sortMode="distance"; assert(X.Support.Report():find("settings.sortMode=distance",1,true))
    db.sortMode="class"; assert(X.Support.Report():find("settings.sortMode=unknown",1,true)); db.sortMode="name"
    f.slash("support")
    assert(c.BuffRadarExportFrame:IsShown() and c.BuffRadarExportFrame.editBox:GetText():find(report,1,true)
      and sends==0 and c.__macroWrites==writes, "copy dialog transmitted or changed state")
  end)

  step("support: invalid, secret and hostile diagnostics become unknown", function()
    local secret = setmetatable({}, { __tostring=function() error("secret converted") end })
    local f = fresh({}, true, function(c) c.issecretvalue=function(v) return rawequal(v,secret) end end)
    local X, c = f.X, f.client
    X.Status.Diagnostics=function() return { state=secret, partial=secret, actionable=0/0, expiring=math.huge } end
    X.CastDelivery=function() return setmetatable({}, { __index=function() error("hostile delivery inspected") end }) end
    c.GetBuildInfo=function() return secret, "Name-Realm", "", math.huge end
    f.db.profiles=setmetatable({}, { __index=function() error("profile inspected") end })
    f.db.includeSelf=false; f.db.groupOnly=true; f.db.hidden=secret
    local report=X.Support.Report()
    assert(report:find("settings.includeSelf=false",1,true) and report:find("settings.groupOnly=true",1,true)
      and report:find("settings.hidden=unknown",1,true) and report:find("discovery.partial=unknown",1,true))
    assert(report:find("client.version=unknown",1,true) and report:find("profiles.count=unknown",1,true)
      and not report:find("Name-Realm",1,true))
    X.Support.Open(); X.Support.Close()
  end)

  step("support: typed fault counts and sync summaries never include peer or error text", function()
    local f=fresh({},true)
    local X=f.X
    local secret="PrivateFriend-Realm private error text"
    f.event("ADDON_ACTION_BLOCKED","OtherAddon",secret)
    f.event("ADDON_ACTION_BLOCKED","BuffRadar",secret)
    f.event("ADDON_ACTION_FORBIDDEN","BuffRadar",secret)
    X.Support.RecordFault(secret)
    X.SyncPeerSnapshot=function() return { available=true, members={{name=secret}},
      counts={verified=2,awaiting=1,retrying=0,unverified=3,incompatible=0} } end
    f.db.theme=secret; X.autoThemeAddon=secret; X.autoThemeResolved=secret
    local report=X.Support.Report()
    assert(not report:find(secret,1,true) and report:find("errors.blocked=1",1,true)
      and report:find("errors.forbidden=1",1,true) and report:find("sync.verified=2",1,true)
      and report:find("theme.selected=unknown",1,true))
    X.SyncPeerSnapshot=function() error(secret) end
    assert(X.Support.Report():find("sync.verified=unknown",1,true))
  end)

  step("support: only a fresh correlated user success confirms one active guide", function()
    local f=fresh({ includeSelf=false, pauseInCities=false, castMethod="id" },true)
    local X=f.X
    X.Refresh(); X.Support.Open()
    assert(X.Support.Snapshot().state=="ready", "direct-ready path was blocked by a missing macro")
    local before=f.db.castsTotal
    X.CastEvent("UNIT_SPELLCAST_SUCCEEDED","player","manual",1243)
    assert(X.Support.Snapshot().state=="ready" and f.db.castsTotal==before)
    local button, ambiguousID, target=prepared(f)
    X.BeginCastClick(button,"LeftButton",false,"next-buff key")
    X.BeginCastClick(button,"LeftButton",false,"next-buff key")
    X.CastEvent("UNIT_SPELLCAST_SENT","player",target,"ambiguous",ambiguousID)
    X.CastEvent("UNIT_SPELLCAST_SUCCEEDED","player","ambiguous",ambiguousID)
    X.EndCastClick(button,"LeftButton",false,"next-buff key")
    assert(X.Support.Snapshot().state=="ready" and f.db.castsTotal==before,
      "ambiguous same-spell intent confirmed the guide")
    cast(f,"failed","UNIT_SPELLCAST_FAILED")
    assert(X.Support.Snapshot().state=="ready" and f.db.castsTotal==before)
    local id=cast(f,"credited")
    assert(X.Support.Snapshot().state=="confirmed" and f.db.castsTotal==before+1)
    X.CastEvent("UNIT_SPELLCAST_SUCCEEDED","player","credited",id)
    assert(f.db.castsTotal==before+1)
    X.Support.Close(); X.Support.Open()
    X.CastEvent("UNIT_SPELLCAST_SUCCEEDED","player","credited",id)
    assert(X.Support.Snapshot().state~="confirmed", "reopen inherited a completed cast")
    X.Support.Close()
    X.ObserveCastSuccess(function(serial,source,spellID)
      assert(type(serial)=="number" and (source=="row" or source=="binding" or source=="macro")
        and type(spellID)=="number", "observer received non-typed cast data")
      error("observer fault must be isolated")
    end)
    cast(f,"observer-fault")
    assert(f.db.castsTotal==before+2, "observer error broke canonical counting")
    X.ObserveCastSuccess(nil)
  end)

  step("support: an older in-flight intent cannot complete a reopened attempt", function()
    local f=fresh({ includeSelf=false, pauseInCities=false, castMethod="id" },true)
    local X=f.X
    X.Refresh()
    local button,id,target=prepared(f)
    X.BeginCastClick(button,"LeftButton",false,"next-buff key")
    X.CastEvent("UNIT_SPELLCAST_SENT","player",target,"before-guide",id)
    X.EndCastClick(button,"LeftButton",false,"next-buff key")
    X.Support.Open()
    X.CastEvent("UNIT_SPELLCAST_SUCCEEDED","player","before-guide",id)
    assert(X.Support.Snapshot().state~="confirmed" and f.db.castsTotal==1,
      "pre-guide pending intent confirmed a fresh attempt or was not actually credited")
    X.BeginCastClick(button,"LeftButton",false,"next-buff key")
    X.CastEvent("UNIT_SPELLCAST_SENT","player",target,"before-reopen",id)
    X.EndCastClick(button,"LeftButton",false,"next-buff key")
    X.Support.Close(); X.Support.Open()
    X.CastEvent("UNIT_SPELLCAST_SUCCEEDED","player","before-reopen",id)
    assert(X.Support.Snapshot().state~="confirmed" and f.db.castsTotal==2,
      "old generation pending success confirmed a reopened guide or was not actually credited")
    X.Support.Close()
  end)

  step("support: covered unknown paused and macro-only discovery stay distinct", function()
    local f=fresh({},true)
    local X=f.X
    local status={state="covered",partial=false}
    local delivery={directReady=false,macroReady=false,directReason="no_target",reason="missing",macroState="unavailable"}
    X.Status.Diagnostics=function() return status end
    X.CastDelivery=function() return delivery end
    X.Support.Open(); assert(X.Support.Snapshot().reason=="covered")
    status.state="unknown"; status.partial=true; X.SupportChanged()
    assert(X.Support.Snapshot().reason=="unknown")
    status.state="unavailable"; status.partial=false; status.reason="paused"; X.SupportChanged()
    assert(X.Support.Snapshot().reason=="inactive")
    status.reason="updating"; X.SupportChanged()
    assert(X.Support.Snapshot().state=="discovering")
    delivery.macroReady=true; delivery.reason="ready"; X.SupportChanged()
    assert(X.Support.Snapshot().state=="ready", "ready macro path was blocked by direct unavailability")
    X.playerDead=true; X.SupportChanged(); assert(X.Support.Snapshot().state=="paused")
    X.playerDead=false
    for i=#X.Core.Buffs,1,-1 do X.Core.Buffs[i]=nil end
    X.HasKnownBlessings=function() return false end
    X.SupportChanged(); assert(X.Support.Snapshot().reason=="no_buffs")
    X.Support.Close()
  end)

  step("support: guide pauses keyboard safely and releases all attempt state", function()
    local f=fresh({ includeSelf=false, pauseInCities=false },true)
    local X,c=f.X,f.client
    X.Refresh(); f.slash("firstcast")
    local frame=X.Support.Frame()
    local propagation=frame.SetPropagateKeyboardInput
    frame.SetPropagateKeyboardInput=function(self,value)
      assert(not c.InCombatLockdown(), "nocombat propagation called")
      return propagation(self,value)
    end
    frame.scripts.OnKeyDown(frame,"TAB")
    c.__combat=true; f.event("PLAYER_REGEN_DISABLED")
    assert(X.Support.Snapshot().state=="paused" and not frame.keyboard)
    frame.scripts.OnKeyDown(frame,"W")
    X.Support.Close(); X.Support.Open()
    assert(not frame.keyboard and X.Support.Snapshot().state=="paused")
    c.__combat=false; f.event("PLAYER_REGEN_ENABLED"); f.advance(3); X.Refresh()
    assert(frame.keyboard and X.Support.Snapshot().state~="paused")
    frame.report:Click()
    assert(not frame.keyboard and c.BuffRadarExportFrame:IsShown())
    c.BuffRadarExportFrame:Hide()
    assert(frame.keyboard, "report close did not restore guide keyboard")
    frame.scripts.OnKeyDown(frame,"TAB")
    frame.setup:Click()
    assert(not frame.keyboard and X.wizardFrame:IsShown())
    X.wizardFrame:Hide()
    assert(frame.keyboard, "setup close did not restore guide keyboard")
    if frame.nearby then
      local profile=X.ProfileSnapshot()
      frame.nearby:Click()
      assert(c.BuffRadarNearbyDiagnostics:IsShown() and not frame.keyboard
        and X.ProfileSnapshot()==profile, "opening discovery diagnostics changed settings or retained capture")
      c.BuffRadarNearbyDiagnostics:Hide()
      assert(frame.keyboard, "discovery diagnostics close did not restore guide keyboard")
    end
    frame.scripts.OnKeyDown(frame,"ESCAPE")
    assert(not frame.keyboard and not X.Support.Snapshot().active and not frame:GetScript("OnUpdate"))
    local old=X.supported; X.supported=false
    X.Support.Open(); assert(X.Support.Snapshot().reason=="unsupported")
    X.supported=old; X.Support.Close()
    f.slash("config")
    local cfg=c.BuffRadarConfig
    local button=cfg.readiness.firstCast
    assert(-button.points[1][3]+button.size[2]<=502, "settings support row extends below fallback content")
  end)
end
