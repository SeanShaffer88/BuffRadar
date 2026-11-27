-- Focused release-candidate regressions using the same isolated clients as the smoke gate.
return function(step, fresh, testClient, loadClient, forever)
  step("audit: combat edge latches secure actions before lockdown state catches up", function()
    local f = fresh({ dbVersion = 24 }, true)
    local X = f.X
    assert(X.SecureActionAllowed(), "safe test client could not arm a secure action")
    f.event("PLAYER_REGEN_DISABLED") -- intentionally leave the mock lockdown API false
    assert(not X.SecureActionAllowed() and not X.SecureWriteAllowed(),
      "combat-edge latch did not block protected actions and writes")
    f.event("PLAYER_REGEN_ENABLED")
    assert(X.SecureActionAllowed(), "post-combat event did not release the action latch")
    f.event("PLAYER_DEAD")
    assert(not X.SecureActionAllowed(), "dead player retained an action-ready state")
  end)

  step("audit: excluded single-buff holders retain ownership in either roster order", function()
    if forever then return end
    for _, exclusion in ipairs({ "permanent", "session", "role", "failed" }) do
      for _, holder in ipairs({ "party1", "party2" }) do
        local other = holder == "party1" and "party2" or "party1"
        local f = fresh({ includeSelf = false, pauseInCities = false, rebuff = 30,
          enabled = { EARTH_SHIELD = true }, roleFilter = exclusion == "role" and "TANK" or "ALL" }, true, function(c, units)
          units.player, units.party1, units.party2 = { "Me", "SHAMAN" }, { "Alia", "WARRIOR" }, { "Bren", "WARRIOR" }
          c.IsPlayerSpell = function(id) return id == 974 end
          c.UnitGroupRolesAssigned = function(unit) return unit == holder and "HEALER" or "TANK" end
        end)
        local X, present, mine = f.X, true, true
        f.O.Aura = function(unit, spell, filter)
          if unit == holder and spell == "Earth Shield" and present
              and (mine or not filter:find("PLAYER", 1, true)) then return { expirationTime = 700 } end
        end
        local function offered(unit)
          for i = 1, X.Core.EntryCount() do
            local entry = X.Core.Entries[i]
            if entry.unit == unit then
              for _, spell in ipairs(entry.missing) do if spell == "Earth Shield" then return true end end
            end
          end
          return false
        end
        if exclusion == "permanent" then f.slash("ignore " .. f.units[holder][1] .. "-Realm")
        elseif exclusion == "session" then f.slash("signore " .. f.units[holder][1] .. "-Realm")
        elseif exclusion == "failed" then X.failedTargets[f.client.UnitGUID(holder)] = 200 end
        X.Refresh()
        assert(not offered(other), exclusion .. " holder lost ownership when enumerated as " .. holder)
        mine = false; X.Refresh()
        assert(offered(other), "another caster's aura suppressed the offer")
        mine, present = true, false; X.Refresh()
        assert(offered(other), "removed aura left stale ownership")
        f.O.Aura = function(unit, spell)
          if unit == "player" and spell == "Earth Shield" then return { expirationTime = 700 } end
        end
        X.Refresh()
        assert(offered(other), "self aura incorrectly claimed the other-player slot")
        f.O.Aura = function(unit, spell)
          if unit == holder and spell == "Earth Shield" then return { expirationTime = 700 } end
        end
        X.Core.Missing(holder, {}, true, false, true)
        assert(not next(X.Core.Single.holder), "report-only aura reads changed ownership")
      end
    end
  end)

  local function mentions(messages, text, first)
    local count = 0
    for i = (first or 0) + 1, #messages do
      if messages[i]:find(text, 1, true) then count = count + 1 end
    end
    return count
  end

  local function rowFor(client, unit)
    for i = 1, 15 do
      local row = client["BuffRadarRow" .. i]
      if row.entry and row.entry.unit == unit then return row end
    end
  end

  local function profile(f, rebuff)
    local body, count = assert(f.X.ProfileSnapshot()):gsub(";rebuff=%d+;", ";rebuff=" .. rebuff .. ";")
    assert(count == 1)
    return body
  end

  local function review(f, command, text)
    f.slash(command)
    local dialog = assert(f.client.BuffRadarExportFrame)
    dialog.editBox:SetText(text)
    dialog.accept:Click()
    return dialog
  end

  step("audit: unsupported clients leave saves untouched and park only an owned macro", function()
    local parked = "# BuffRadar\n/stopmacro [combat][@player,dead]"
    local cases = {
      { 16000, "/click BuffRadarNextButton", parked },
      { forever and 120105 or 16001, "/say My own macro", "/say My own macro" },
      { 16002, parked .. "\n/click BuffRadarMacroButton\n/cast [@party1,help,nodead] Fortitude", parked, true },
    }
    for _, case in ipairs(cases) do
      local c, messages = testClient()
      c.GetBuildInfo = function() return "bad", "0", "", case[1] end
      local original = { scale = 9, opaque = {} }
      c.BuffRadarDB = original
      local i = c.CreateMacro("BuffRadar", 134400, case[2])
      local X, driver = loadClient(c)
      c.__combat = case[4] or false
      driver.scripts.OnEvent(driver, "ADDON_LOADED", "BuffRadar")
      assert(not X.GetDB() and c.BuffRadarDB == original and original.scale == 9)
      assert(not X.supported and not X.pullFrame and not c.__settings.registered)
      assert(not c.BuffRadarNextButton and not c.BuffRadarFrame and c.BuffRadarAPI.GetSummary().actionable == 0)
      assert(mentions(messages, X.L["BuffRadar requires the Forever package on Interface 16001. Casting is disabled."]) == 1)
      if c.__combat then
        assert(driver.events.PLAYER_REGEN_ENABLED and c.GetMacroBody(i) == case[2])
        c.__combat = false
        driver.scripts.OnEvent(driver, "PLAYER_REGEN_ENABLED")
      end
      assert(not next(driver.events) and c.GetMacroBody(i) == case[3])
    end
  end)

  step("audit: detached nested saves, future-version preservation and rejected placement", function()
    local original = { dbVersion = 900, futureOnly = { "keep" }, scale = math.huge,
      enabled = { FORTITUDE = false, INNER_FIRE = false, SHADOWGUARD = false, garbage = true },
      specProfiles = { s1 = { enabled = { FORTITUDE = true, FAKE = {} }, rebuffPer = { FORTITUDE = 2000 } },
        junk = { enabled = {} } },
      point = { "WAT", "CENTER", 2, 3 }, pointByChar = { ok = { "CENTER", "CENTER", 5, 6 }, bad = { "CENTER", "CENTER", 0/0, 1 } },
      customGroup = { Fortitude = "Prayer", Broken = "X;Y" }, stats = { Bright = 2, Bad = -1 }, offenders = { Alia = 3 } }
    local f = fresh(original)
    local db = f.db
    assert(f.client.BuffRadarDB == original and db ~= original and db.dbVersion == 26)
    assert(db.scale == 1 and not db.futureOnly and not db.point and not db.pointByChar.bad)
    assert(db.specProfiles.s1.rebuffPer.FORTITUDE == 600 and not db.specProfiles.s1.enabled.FAKE and not db.specProfiles.junk)
    assert(db.customGroup.Fortitude == "Prayer" and not db.customGroup.Broken and not db.stats.Bad)
    assert(db.offenders["legacy:Alia"].count == 3)
    db.pointByChar.ok[3], db.specProfiles.s1.enabled.FORTITUDE = 55, false
    assert(original.pointByChar.ok[3] == 5 and original.specProfiles.s1.enabled.FORTITUDE and original.futureOnly[1] == "keep")
    f.slash("scale 1.5")
    assert(original.scale == math.huge and original.dbVersion == 900)
    local rejected = false
    local g = fresh({ point = { "TOPLEFT", "CENTER", 177, 4 } }, false, function(c)
      local create = c.CreateFrame
      c.CreateFrame = function(kind, name, parent, template)
        local frame = create(kind, name, parent, template)
        if name == "BuffRadarFrame" then
          local place = frame.SetPoint
          frame.SetPoint = function(self, p, rel, rp, x, y)
            if x == 177 then rejected = true; error("refused saved anchor") end
            place(self, p, rel, rp, x, y)
          end
        end
        return frame
      end
    end)
    assert(rejected and g.X.WindowReady() and not g.db.point and g.client.BuffRadarFrame.points[1][3] == "LEFT")
    local h = fresh({ point = { "TOPRIGHT", "TOPRIGHT", 88888, 88888 } })
    assert(h.X.WindowReady() and not h.db.point, "plausible but off-screen point was restored")
  end)

  step("audit: storage limits reject additions atomically and preserve oversized legacy saves", function()
    local f = fresh({})
    local X, db = f.X, f.db
    for i = 1, X.Settings.Limits.profiles do assert(X.SaveProfile("P" .. i)) end
    assert(not X.SaveProfile("Overflow") and X.Settings.Count(db.profiles) == X.Settings.Limits.profiles)
    local names = {}
    for i = 1, X.Settings.Limits.ignored - 1 do names[i] = "Name" .. i end
    assert(X.Ignore.AddMany(names) == #names)
    assert(not X.Ignore.AddMany({ "Extra", "Second" }) and not db.ignored.Extra and not db.ignored.Second)
    for i = 1, X.Settings.MaxGroupPairs do f.slash('grouppair "Single ' .. i .. '" "Group ' .. i .. '"') end
    f.slash('grouppair "Overflow" "Group"')
    f.slash('grouppair "Single 1" "[harm]Action"')
    assert(not db.customGroup.Overflow and db.customGroup["Single 1"] == "Group 1")
    local original = { dbVersion = 22, profiles = db.profiles, ignored = db.ignored }
    original.profiles.Overflow = original.profiles.P1
    local g = fresh(original)
    assert(g.client.BuffRadarDB == original and g.X.Settings.SaveState() == "overflow" and original.profiles.Overflow)
    g.slash("storage delete profile Overflow")
    assert(not original.profiles.Overflow and original.profiles.P1 and original.dbVersion == 22)
    assert(g.X.Settings.Load(true) == nil and g.client.BuffRadarDB ~= original and g.client.BuffRadarDB.dbVersion == 26)
  end)

  step("audit: settings review supports cancel, edit paste and re-review after drift", function()
    local f = fresh({ rebuff = 27, hidden = false }, true)
    local text, change = assert(f.X.Export()):gsub(";rebuff=27;", ";rebuff=79;")
    assert(change == 1)
    local d = review(f, "import", text)
    assert(d.review:IsShown() and d.draft and not d.share:IsShown() and f.db.rebuff == 27)
    assert(d.reviewText:GetText():find("rebuff: 27 → 79", 1, true))
    d.back:Click()
    assert(d.editBox:IsShown() and d.editBox:GetText() == text and not d.draft)
    d.accept:Click(); d.cancel:Click()
    assert(not d:IsShown() and not d.draft and f.db.rebuff == 27 and not f.client.__editFocus)
    d = review(f, "import", text)
    local oldHistory, oldPositions = f.db.history, f.db.panelPoints
    f.slash("rebuff 40")
    d.apply:Click()
    assert(d:IsShown() and f.db.rebuff == 40 and d.reviewText:GetText():find("rebuff: 40 → 79", 1, true))
    d.apply:Click()
    assert(not d:IsShown() and f.db.rebuff == 79 and f.db.history == oldHistory and f.db.panelPoints == oldPositions)
    local over = review(f, "import", "BR1;" .. string.rep("x", 16384))
    assert(over.editBox:IsShown() and not over.draft and f.db.rebuff == 79)
    local many = {}
    for i = 1, f.X.Settings.Limits.ignored + 1 do many[i] = ";ignored.More" .. i .. "=1" end
    local oversized = text:gsub(";endExport=1$", table.concat(many) .. ";endExport=1")
    assert(#oversized < 16384 and not f.X.ParseSettingsImport(oversized))
    assert(not f.X.Import(oversized) and not next(f.db.ignored))
  end)

  step("audit: profile import exposes collisions, rechecks replacement and can rename without loading", function()
    local f = fresh({ rebuff = 27 })
    local db = f.db
    local prior, changed, body = profile(f, 15), profile(f, 16), profile(f, 79)
    db.profiles.Alpha, db.autoProfile.raid = prior, "Alpha"
    local d = review(f, "profile import", "BuffRadar profile: Alpha\n" .. body)
    assert(d.apply:GetText() == f.X.L["Replace profile"] and d.reviewText:GetText():find("raid", 1, true))
    assert(d.reviewText:GetText():find("rebuff: 27 → 79", 1, true) and db.profiles.Alpha == prior)
    db.profiles.Alpha = changed
    d.apply:Click()
    assert(d:IsShown() and db.profiles.Alpha == changed and db.rebuff == 27)
    d.nameBox:SetText("Beta"); d.nameBox.scripts.OnTextChanged(d.nameBox)
    assert(d.apply:GetText() == f.X.L["Save profile"])
    d.apply:Click()
    assert(not d:IsShown() and db.profiles.Beta == body and db.profiles.Alpha == changed and db.rebuff == 27)
    d = review(f, "profile import", "BuffRadar profile: Alpha\n" .. body)
    d.apply:Click()
    assert(db.profiles.Alpha == body and db.autoProfile.raid == "Alpha" and db.rebuff == 27)
  end)

  step("audit: plan review is local by default and sharing rejects membership and authority drift", function()
    local f = fresh({ sync = true }, true)
    local X, c = f.X, f.client
    local leader = "Me"
    c.UnitIsGroupLeader = function(unit) return c.UnitName(unit) == leader end
    f.event("GROUP_ROSTER_UPDATE")
    local function sent()
      local total = 0
      for _, message in ipairs(c.__addonSent) do if message.msg:sub(1, 7) == "ASSIGN;" then total = total + 1 end end
      return total
    end
    local text = "BRPLAN1;A;FORTITUDE;Alia;P;raid;Future"
    local d = review(f, "plan import", text)
    assert(d.share:IsShown() and d.reviewText:GetText():find("Future", 1, true))
    assert(d.back.points[1][3] ~= d.share.points[1][3] and d.share.points[1][3] ~= d.apply.points[1][3])
    d.apply:Click()
    assert(X.assign.FORTITUDE == "Alia" and f.db.autoProfile.raid == "Future" and sent() == 0)
    text = "BRPLAN1;A;FORTITUDE;Bren"
    d = review(f, "plan import", text)
    local before = f.units.party1
    f.units.party1 = { "Substitute", "MAGE" }; f.event("GROUP_ROSTER_UPDATE")
    f.units.party1 = before; f.event("GROUP_ROSTER_UPDATE")
    d.share:Click()
    assert(d:IsShown() and X.assign.FORTITUDE == "Alia" and sent() == 0, "same members returned after churn")
    d = review(f, "plan import", text)
    leader = "Bren"; f.event("PARTY_LEADER_CHANGED")
    d.share:Click()
    assert(d:IsShown() and X.assign.FORTITUDE == "Alia" and sent() == 0)
    leader = "Me"; f.event("PARTY_LEADER_CHANGED")
    d = review(f, "plan import", text)
    f.units.party1, f.units.party2 = f.units.party2, f.units.party1
    f.event("GROUP_ROSTER_UPDATE")
    d.share:Click()
    assert(not d:IsShown() and X.assign.FORTITUDE == "Bren" and sent() == 1, "reorder retired an otherwise current review")
    local guid = f.O.UnitGUID
    f.O.UnitGUID = function(unit) return guid(unit == "party1" and "party2" or unit) end
    f.event("GROUP_ROSTER_UPDATE")
    d = review(f, "plan import", "BRPLAN1;A;FORTITUDE;Alia")
    assert(not X.GroupIdentity() and not d.share:IsShown() and sent() == 1, "duplicate GUID allowed sharing")
  end)

  step("audit: remote legacy plan ownership restores local values after authority loss", function()
    local f = fresh({ sync = true }, true)
    local X, c = f.X, f.client
    local leader = "Alia"
    c.UnitIsGroupLeader = function(unit) return c.UnitName(unit) == leader end
    X.SetLocalPlan("ASSIGN", "FORTITUDE", "Local-Realm")
    local prior = { key = "KINGS", name = "Local-Realm" }
    X.SetLocalPlan("BLESS", "WARRIOR", prior)
    f.event("CHAT_MSG_ADDON", "BuffRadar", "ASSIGN;FORTITUDE;Alia-Realm", "PARTY", "Alia-Realm")
    f.event("CHAT_MSG_ADDON", "BuffRadar", "BLESS;WARRIOR;MIGHT;Alia-Realm", "PARTY", "Alia-Realm")
    assert(X.assign.FORTITUDE == "Alia-Realm" and X.blessPlan.WARRIOR.key == "MIGHT")
    leader = "Bren"; f.event("PARTY_LEADER_CHANGED")
    assert(X.assign.FORTITUDE == "Local-Realm" and X.blessPlan.WARRIOR == prior)
    f.event("CHAT_MSG_ADDON", "BuffRadar", "ASSIGN;FORTITUDE;Bren-Realm", "PARTY", "Bren-Realm")
    assert(X.assign.FORTITUDE == "Bren-Realm")
    f.units.party1 = { "Substitute", "PRIEST" }; f.event("GROUP_ROSTER_UPDATE")
    assert(X.assign.FORTITUDE == "Local-Realm", "previous membership kept its overlay")
    f.event("CHAT_MSG_ADDON", "BuffRadar", "ASSIGN;FORTITUDE;Bren-Realm", "PARTY", "Bren-Realm")
    assert(X.assign.FORTITUDE == "Bren-Realm")
    f.slash("sync")
    assert(X.assign.FORTITUDE == "Local-Realm" and not f.db.sync)
  end)

  step("audit: refresh faults before arm and after partial paint disarm all actions and recover", function()
    local f = fresh({ includeSelf = false }, true)
    local X, c = f.X, f.client
    local nextButton, group = c.BuffRadarNextButton, c.BuffRadarGroupButton
    X.Refresh(); f.slash("macro")
    local index = assert(c.GetMacroIndexByName("BuffRadar"))
    local parked = "# BuffRadar\n/stopmacro [combat][@player,dead]"
    local function unavailable(why)
      local status = f.api.GetStatus()
      assert(status.state == "unavailable" and status.reason == why and #status.targets == 0)
      assert(not nextButton.entry and not group.entry and not nextButton.attrs.type and not group.attrs.type)
      assert(not next(X.tally) and not X.ScrollRows(1))
      for i = 1, 15 do
        local row = c["BuffRadarRow" .. i]
        assert(not row.entry and not row.attrs.type and not row.attrs["shift-type1"])
      end
    end
    local function armed()
      assert(f.api.GetSummary().actionable >= 2 and nextButton.attrs.type and group.attrs.type)
      assert(c.GetMacroBody(index) ~= parked)
    end
    armed()
    local prepare = X.PrepareWindowScan
    X.PrepareWindowScan = function() error("fault before arm") end
    X.Refresh(); unavailable("updating")
    assert(c.GetMacroBody(index) == parked)
    X.PrepareWindowScan = prepare
    X.Refresh(); armed()
    local row = c.BuffRadarRow2
    local paint = row.SetAlpha
    row.SetAlpha = function() error("fault during second row paint") end
    X.Refresh(); unavailable("updating")
    assert(c.GetMacroBody(index) == parked)
    row.SetAlpha = paint
    X.Refresh(); armed()

    -- Simulate the secure driver's clearing before dispatching the combat event.
    -- Counts record attempted protected writes even if pcall swallowed an error.
    local attempts = 0
    for _, button in ipairs({ nextButton, group, c.BuffRadarRow1, c.BuffRadarRow2, c.BuffRadarFrame }) do
      for _, method in ipairs({ "SetAttribute", "Hide", "Show", "SetPoint" }) do
        local original = button[method]
        button[method] = function(self, ...)
          if c.__combat then attempts = attempts + 1; error("protected write in combat") end
          return original(self, ...)
        end
      end
      for attribute in pairs(button.attrs) do if attribute ~= "_onstate-combat" then button.attrs[attribute] = nil end end
    end
    local edit = c.EditMacro
    c.EditMacro = function(...)
      if c.__combat then attempts = attempts + 1; error("macro write in combat") end
      return edit(...)
    end
    c.__combat = true; f.event("PLAYER_REGEN_DISABLED")
    X.RefreshFault("fault while locked")
    unavailable("combat")
    assert(attempts == 0 and c.GetMacroBody(index):find("/stopmacro [combat][@player,dead]", 1, true))
    c.__combat = false; f.event("PLAYER_REGEN_ENABLED"); f.advance(0.11)
    armed()
  end)

  step("audit: short viewport reuses secure rows and cached paint shares fault cleanup", function()
    local f = fresh({ scale = 1.5, includeSelf = true, showStrip = false }, true)
    local X, c = f.X, f.client
    f.units.party3, f.units.party4 = { "Dara", "PRIEST" }, { "Elio", "MAGE" }
    c.GetNumGroupMembers = function() return 5 end
    X.Refresh()
    local row, frames = c.BuffRadarRow1, #c.__frames
    c.UIParent.GetHeight = function() return 160 end
    f.event("DISPLAY_SIZE_CHANGED"); f.advance(0.11)
    assert(c.BuffRadarFrame.height * f.db.scale <= 160 and #c.__frames == frames,
      "height=" .. tostring(c.BuffRadarFrame.height * f.db.scale) .. " frames=" .. #c.__frames .. "/" .. frames)
    local first, nextEntry = assert(row.entry).guid, c.BuffRadarNextButton.entry
    assert(X.ScrollRows(1), "the short viewport did not scroll")
    assert(row.entry.guid ~= first and c.BuffRadarNextButton.entry == nextEntry, "scroll changed the cast-next entry")
    local paint = row.SetAlpha
    row.SetAlpha = function() error("cached paint fault") end
    assert(not X.ScrollRows(-1))
    assert(not row.entry and not row.attrs.type and not c.BuffRadarNextButton.attrs.type and f.api.GetSummary().reason == "updating")
    row.SetAlpha = paint
    X.Refresh()
    assert(row.entry and row.attrs.type and c.BuffRadarNextButton.attrs.type and #c.__frames == frames)
    X.InvalidateRows() -- invalidate the presentation cache just before retiring an armed row
    f.db.hidden = true; X.Refresh()
    assert(not row.entry and not row.attrs.type and not row.attrs["shift-type1"] and c.BuffRadarNextButton.attrs.type)
  end)

  step("audit: group actions fall back for target, range, reagents and stale identity", function()
    if not forever then return end
    local f = fresh({ includeSelf = false, modClick = true, groupCast = true, groupCastMin = 2, pets = true }, true)
    local X, c, db = f.X, f.client, f.db
    local single, prayer = "Power Word: Fortitude", "Prayer of Fortitude"
    db.enabled[f.manaKey] = false
    local group = c.BuffRadarGroupButton
    X.Refresh()
    assert(group.bSpell == prayer and c.BuffRadarNextButton.bSpell == prayer)
    c.GetSpellCooldown = function(spell) if spell == prayer then return 95, 20 end return 0, 0 end
    X.Refresh()
    assert(group.bSpell == single and c.BuffRadarNextButton.bSpell == single)
    c.GetSpellCooldown = nil
    c.IsSpellInRange = function(spell) return spell ~= prayer and 1 or 0 end
    X.Refresh()
    local row = assert(rowFor(c, "party1"))
    assert(row.bSpell == single and row.bGroupSpell == single and group.bSpell == single)
    c.IsSpellInRange = function(spell) if spell ~= prayer then return 1 end end
    c.UnitInRange = function() return nil end
    db.assumeRange = true; X.Refresh()
    assert(group.bSpell == single, "assumed range armed the group version")
    c.IsSpellInRange = function() return 1 end
    c.C_Item.GetItemCount = function() return nil end
    X.InvalidateReagents(); X.Refresh()
    assert(group.bSpell == single and row.bGroupSpell == single)
    c.C_Item.GetItemCount = function() return 10 end
    X.InvalidateReagents(); X.Refresh()
    assert(group.bSpell == prayer)
    f.units[group.entry.unit] = { "New", "PRIEST" }
    group.scripts.PreClick(group, "LeftButton", false)
    assert(not group.attrs.type and not group.entry)
    f.units.partypet1 = { "Wolf", "WARRIOR" }
    f.O.UnitIsPlayer = function(unit) return f.units[unit] ~= nil and unit ~= "partypet1" end
    f.O.Aura = function(unit, spell)
      if unit ~= "partypet1" and spell == single then return { expirationTime = 0 } end
    end
    X.Refresh()
    row = assert(rowFor(c, "partypet1"))
    assert(row.bSpell == single and row.bGroupSpell == single and group.bSpell == single)
    assert(not X.GroupOffer(single, "partypet1"))
    assert(row.attrs.type == "spell" and row.attrs.unit == "partypet1" and not row.attrs.macrotext)
    assert(c.BuffRadarNextButton.attrs.unit == "partypet1" and group.attrs.unit == "partypet1")
    f.slash("macro")
    local macro = c.GetMacroIndexByName("BuffRadar")
    assert(c.GetMacroBody(macro):find("/click BuffRadarNextButton", 1, true))
    f.units.partypet1 = { "AnotherWolf", "WARRIOR" }
    f.event("UNIT_PET", "party1")
    assert(not c.GetMacroBody(macro):find("/click", 1, true), "stale pet token left the macro armed")
    row.scripts.PreClick(row, "LeftButton", false)
    assert(not row.attrs.type and not row.entry)
    f.advance(0.11)
    assert(c.GetMacroBody(macro):find("/click BuffRadarNextButton", 1, true), "pet-change refresh did not re-arm")
    f.slash("subgroup FORTITUDE 1")
    assert(not X.GetSubgroupDuty("FORTITUDE"), "party accepted raid-only subgroup duty")
    for _, value in ipairs({ "1,1", "1,,2", "1,", "0", "9", "1.0", "ALL,1" }) do
      local _, ok = X.Settings.ParseSubgroups(value)
      assert(not ok, "invalid subgroup set: " .. value)
    end
  end)

  step("audit: ineligible rank is not armed except in explicit plain macro mode", function()
    if not forever then return end
    local f = fresh({ includeSelf = false, castMethod = "target" }, true, function(c)
      c.UnitLevel = function(unit) return unit == "party1" and 15 or 25 end
      c.GetSpellLevelLearned = function(id) return id == 1243 and 30 or (id == 1244 and 40 or nil) end
    end)
    f.db.enabled[f.manaKey] = false
    for _, method in ipairs({ "target", "id", "rank" }) do
      f.db.castMethod = method
      f.X.Refresh()
      local low, allowed = rowFor(f.client, "party1"), rowFor(f.client, "party2")
      assert(not low and allowed and allowed.bRankID == 1243 and allowed.attrs.type, method .. " chose the wrong rank")
    end
    f.db.castMethod = "macro"
    f.X.Refresh()
    assert(rowFor(f.client, "party1"), "explicit plain macro mode changed")
  end)

  step("audit: aura IDs are locale-independent and unavailable helpful reads never prove absence", function()
    if not forever then return end
    local f = fresh({ readinessAura = 801, worldWatch = true }, false, function(c) c.GetLocale = function() return "deDE" end end)
    local c, X = f.client, f.X
    local list = {
      { name = "Stärkungszauber", spellId = 17626, expirationTime = 500 },
      { name = "Satt", spellId = 19705, expirationTime = 500 },
      { name = "Trinken", spellId = 430, expirationTime = 500 },
      { name = "Drachentöter", spellId = 22888, expirationTime = 500 },
    }
    f.O.AuraList = function() return list end
    local reads = 0
    c.C_UnitAuras.GetPlayerAuraBySpellID = function(id)
      reads = reads + 1
      assert(id == 801)
      return { spellId = 801, expirationTime = 0, isHarmful = false }
    end
    local got = X.ObserveConsumables("player", {}, true, true, 801)
    assert(got.FOOD and got.FLASK and got.DRINK and got.OPTIONAL and reads == 1)
    assert(X.WorldBuffsText():find("Drachentöter", 1, true))
    c.C_UnitAuras.GetPlayerAuraBySpellID = function() return { spellId = 801, expirationTime = 0 } end
    assert(X.ObserveConsumables("player", {}, false, false, 801).OPTIONAL == false, "unclassified aura proved helpful")
    c.C_UnitAuras.GetPlayerAuraBySpellID = function() return { spellId = 801, expirationTime = 0, isHarmful = true } end
    assert(X.ObserveConsumables("player", {}, false, false, 801).OPTIONAL == false, "harmful aura proved helpful")
    c.C_UnitAuras.GetPlayerAuraBySpellID = function() return nil end
    c.C_UnitAuras.GetBuffDataByIndex = function() error("restricted auras") end
    got = X.ObserveConsumables("player", {}, true, true, 801)
    assert(not next(got) and X.WorldBuffsText():find(X.L["Some world buff information is unavailable."], 1, true))
    c.C_UnitAuras.GetBuffDataByIndex = function()
      reads = reads + 1
      return { name = "Anderer Zauber", spellId = 332, expirationTime = 0 }
    end
    reads = 0
    assert(not next(X.ObserveConsumables("player", {}, true, true, 801)) and reads == 40)
    c.C_UnitAuras = nil
    got = X.ObserveConsumables("player", {}, true, true, 801)
    assert(got.FOOD and got.FLASK and got.DRINK and got.OPTIONAL == false, "legacy tuple lost spell identity")
    c.GetInventoryItemID = function(_, slot) return slot == 17 and 112 or nil end
    c.GetWeaponEnchantInfo = function() return false, 0, 0, 0, false end
    c.GetItemInfoInstant = function() return 112, nil, nil, "INVTYPE_SHIELD", nil, 4 end
    assert(X.WeaponCoatingState() == "na")
    c.GetItemInfoInstant = function() return 112, nil, nil, "INVTYPE_WEAPONOFFHAND", nil, 2 end
    assert(X.WeaponCoatingState() == "missing")
    c.GetItemInfoInstant = function() return nil end
    assert(X.WeaponCoatingState() == "unknown")
  end)

  step("audit: roster observations survive an unknown read but retire after departure and expiry", function()
    local f = fresh({ includeSelf = false }, true)
    local X, c = f.X, f.client
    f.db.enabled[f.manaKey] = false
    local guid = c.UnitGUID("party1")
    local previous = c.C_UnitAuras.GetBuffDataByIndex
    local covered = true
    f.O.Aura = function(unit, spell)
      if unit == "party1" and spell == "Power Word: Fortitude" and covered then return { expirationTime = 0 } end
    end
    X.Refresh()
    assert(X.missPrev[guid] and not X.missPrev[guid].FORTITUDE)
    covered = false
    f.O.Aura = function() error("no named aura read") end
    c.C_UnitAuras.GetBuffDataByIndex = function(unit, ...) if unit ~= "party1" then return previous(unit, ...) end end
    X.Refresh()
    assert(X.missPrev[guid] and not X.missPrev[guid].FORTITUDE and not X.expiredAt[guid])
    f.O.Aura, c.C_UnitAuras.GetBuffDataByIndex = nil, previous
    X.Refresh()
    assert(X.expiredAt[guid] and X.missPrev[guid].FORTITUDE)
    local dead = true
    f.O.UnitIsDeadOrGhost = function(unit) return unit == "party1" and dead end
    X.Refresh(); assert(X.dead[guid])
    dead = false
    X.Refresh(); assert(X.rezAt[guid] and not X.dead[guid])
    f.advance(11); X.Refresh(); assert(not X.expiredAt[guid] and X.rezAt[guid])
    f.units.party1 = { "Replacement", "PRIEST" }
    f.event("GROUP_ROSTER_UPDATE")
    assert(not X.missPrev[guid] and not X.rezAt[guid] and not X.dead[guid] and not X.expiredAt[guid])
  end)

  step("audit: pull ownership ignores unrelated and ambiguous stops and boss-mod traffic outside group scope", function()
    local f = fresh({ forecastSeconds = 30 }, true)
    local X, c = f.X, f.client
    if not X.pullFrame then return end
    c.UnitIsGroupLeader = function(unit) return unit == "party1" end
    f.event("START_TIMER", 2, 15, 15)
    local timer = assert(X.pull)
    f.event("START_PLAYER_COUNTDOWN", "Player-1-Alia", 15, 15)
    assert(X.pull == timer and timer.owner == "Player-1-Alia")
    f.event("STOP_TIMER_OF_TYPE", 2)
    f.event("CANCEL_PLAYER_COUNTDOWN", "Player-1-Bren")
    assert(X.pull == timer)
    f.event("CANCEL_PLAYER_COUNTDOWN", "Player-1-Alia")
    assert(not X.pull)
    f.event("START_PLAYER_COUNTDOWN", "Player-1-Stranger", 20)
    assert(not X.pull)
    f.event("START_PLAYER_COUNTDOWN", "Player-1-Alia", 20)
    f.event("START_PLAYER_COUNTDOWN", "Player-1-Alia", 11)
    f.event("CANCEL_PLAYER_COUNTDOWN", "Player-1-Alia")
    assert(X.pull and X.pull.ambiguousStop)
    f.advance(12, true)
    assert(not X.pull, "replacement never expired")
    f.event("CHAT_MSG_ADDON", "D5", "PT\t10\t33", "RAID", "Alia-Realm")
    f.event("CHAT_MSG_ADDON", "D5", "PT\t10\tbroken", "PARTY", "Alia-Realm")
    f.event("CHAT_MSG_ADDON", "D5", "PT\t10\t33", "PARTY", "Alia-WrongRealm")
    assert(not X.pull)
    f.event("CHAT_MSG_ADDON", "D5", "PT\t10\t33", "PARTY", "Alia-Realm")
    assert(X.pull and X.pull.owner == "Player-1-Alia")
    f.event("CHAT_MSG_ADDON", "D5", "PT\t0", "PARTY", "Alia-Realm")
    assert(X.pull, "mapless stop canceled a scoped timer")
    f.event("CHAT_MSG_ADDON", "D5", "PT\t0\t34", "PARTY", "Alia-Realm")
    assert(X.pull, "different timer ID canceled a scoped timer")
    f.event("CHAT_MSG_ADDON", "D5", "PT\t0\t33", "PARTY", "Alia-Realm")
    assert(not X.pull)
    f.event("CHAT_MSG_ADDON", "D5", "PT\t10", "PARTY", "Alia-Realm")
    f.event("CHAT_MSG_ADDON", "D5", "PT\t0", "PARTY", "Alia-Realm")
    assert(X.pull, "mapless stop canceled an unidentified timer")
    c.UnitIsGroupLeader = function(unit) return unit == "party2" end
    f.event("PARTY_LEADER_CHANGED")
    assert(not X.pull, "timer retained without a trusted sender")
    X.tally = { FORTITUDE = { miss = 1 } }
    f.slash("pullflash on")
    f.event("START_PLAYER_COUNTDOWN", "Player-1-Bren", 20)
    local active = assert(X.pull)
    f.slash("pullflash off")
    assert(X.pull == active, "disabling flash discarded an active forecast")
    f.slash("forecast off")
    assert(not X.pull, "disabling both consumers retained a pull")
  end)

  step("audit: delayed join digest cannot cross a leave and rejoin", function()
    local f = fresh({ joinDigest = true, includeSelf = false })
    if not f.client.C_Timer then return end
    local joined = false
    f.client.IsInGroup = function() return joined end
    f.client.GetNumGroupMembers = function() return joined and 2 or 0 end
    local function enter(name)
      joined, f.units.party1 = true, { name, "PRIEST" }
      f.event("GROUP_ROSTER_UPDATE")
    end
    enter("First"); f.advance(0.40)
    joined, f.units.party1 = false, nil; f.event("GROUP_LEFT")
    enter("Second"); f.advance(1.11)
    assert(mentions(f.messages, f.X.L["Joined a group"]) == 0)
    f.advance(0.50)
    assert(mentions(f.messages, f.X.L["Joined a group"]) == 1)
    joined, f.units.party1 = false, nil; f.event("GROUP_LEFT")
    enter("Third")
    enter("Changed"); enter("Third")
    f.advance(2)
    assert(mentions(f.messages, f.X.L["Joined a group"]) == 1, "a retired membership printed a delayed digest")
  end)

  step("audit: chat reports distinguish refusal, submission and delivery uncertainty", function()
    local f = fresh({ includeSelf = false }, true)
    local X, c, L = f.X, f.client, f.X.L
    local requested = L["Group chat send requested; delivery is not confirmed."]
    local accepted = L["Game accepted the group chat send; delivery is not confirmed."]
    local n = #f.messages
    f.slash("announce")
    assert(#c.__sent == 1 and c.__sent[1].chattype == "PARTY" and mentions(f.messages, requested, n) == 1)
    c.SendChatMessage = function() return true end
    n = #f.messages; f.slash("announce")
    assert(mentions(f.messages, accepted, n) == 1)
    c.SendChatMessage = function() return false end
    n = #f.messages; f.slash("announce")
    assert(mentions(f.messages, L["The game did not accept the send."], n) == 1
      and mentions(f.messages, L["BuffRadar -- missing buffs: "], n) == 1 and mentions(f.messages, accepted, n) == 0)
    c.SendChatMessage = function() error("chat refused") end
    assert(not X.SendGroupReport("Local"))
    local calls = 0
    c.C_ChatInfo = { SendChatMessage = function(text, channel)
      assert(text == "Local" and channel == "RAID"); calls = calls + 1
    end }
    c.IsInRaid = function() return true end
    assert(X.SendGroupReport("Local") == "RAID" and calls == 1)
    calls, c.C_ChatInfo, c.IsInRaid = 0, nil, nil
    c.SendChatMessage = function() calls = calls + 1 end
    assert(not X.SendGroupReport(string.rep("x", 256)) and calls == 0)
    c.IsInGroup, c.GetNumGroupMembers = function() return false end, function() return 0 end
    assert(not X.SendGroupReport("Local") and calls == 0)
  end)

  step("audit: settings and import fall back when optional templates refuse; panel positions are opt-in", function()
    local refused = 0
    local f = fresh({}, true, function(c)
      c.BackdropTemplateMixin = {}
      c.__rejectTemplate = function(_, _, template)
        local reject = template and not template:find("Secure", 1, true)
        if reject then refused = refused + 1 end
        return reject
      end
    end)
    local c, db, L = f.client, f.db, f.X.L
    assert(f.X.WindowReady() and c.BuffRadarRow1)
    f.slash("config")
    local cfg = assert(c.BuffRadarConfig)
    assert(cfg:IsShown() and not cfg.nativeTabs and cfg.scaleDrop:GetText() ~= "" and refused > 0)
    local dialog = review(f, "profile import", "BuffRadar profile: Usable\n" .. profile(f, 40))
    assert(dialog.draft and dialog.review:IsShown())
    dialog.apply:Click(); assert(db.profiles.Usable)
    cfg.GetPoint = function() return "CENTER", c.UIParent, "CENTER", 51, 26 end
    cfg.scripts.OnDragStop(cfg)
    assert(not db.panelPoints.settings)
    f.slash("positions on")
    cfg.scripts.OnDragStop(cfg)
    cfg:Hide(); cfg:Show()
    assert(db.panelPoints.settings[3] == 51 and cfg.points[1][4] == 51)
    f.slash("ready show"); f.event("READY_CHECK")
    local ready = assert(c.BuffRadarReadyCheck)
    ready.GetPoint = function() return "CENTER", c.UIParent, "CENTER", 31, 11 end
    ready.scripts.OnDragStop(ready)
    assert(db.panelPoints.ready[3] == 31)
    f.slash("positions reset")
    assert(db.rememberPanelPositions and not next(db.panelPoints) and ready.points[1][5] == 85 and cfg.points[1][4] == 0)
    f.slash("positions off")
    assert(not db.rememberPanelPositions)
    assert(c["BINDING_NAME_CLICK BuffRadarNextButton:LeftButton"] == L["Cast next buff"])
    local button = c.BuffRadarMinimapButton
    assert(not button.scripts.OnUpdate)
    button.scripts.OnDragStart(button); assert(button.dragging and not button.scripts.OnUpdate)
    button.scripts.OnDragStop(button); assert(not button.dragging and not button.scripts.OnUpdate)
  end)

  step("audit: CPU counters measure scan, import, preparation and combat debuff work independently", function()
    local tick = 0
    local f = fresh({ debuffWatch = true, debuffRules = { { spellID = 710, unit = "player", encounterID = 0 } } }, true,
      function(c) c.debugprofilestop = function() tick = tick + 0.1; return tick end end)
    local t = f.X.timings
    f.X.Refresh()
    assert(t.scan.n >= 1 and t.scan.max > 0 and t.import.n == 0)
    review(f, "profile import", "BuffRadar profile: Timing\n" .. profile(f, 42)).apply:Click()
    assert(t.import.n == 2 and t.import.total > 0)
    if forever then f.slash("readiness"); assert(t.prepare.n >= 1 and t.prepare.last > 0) end
    local before = t.scan.n
    f.client.__combat = true; f.event("PLAYER_REGEN_DISABLED")
    assert(t.scan.n == before and t.combatDebuff.n >= 1 and t.combatDebuff.total > 0)
    f.client.debugprofilestop = function() error("profiling clock not available") end
    f.client.__combat = false; f.event("PLAYER_REGEN_ENABLED"); f.advance(0.11)
    assert(t.scan.n == before and f.api.GetSummary().actionable > 0, "optional timing prevented recovery")
  end)

  step("audit: Nearby resolves against the painted viewport and does no target work while closed", function()
    if not forever then return end
    local f = fresh({ includeSelf = false }, true)
    local X, c = f.X, f.client
    local reads, explain = 0, X.ExplainCurrentTarget
    X.ExplainCurrentTarget = function(...)
      reads = reads + 1
      return explain(...)
    end
    f.slash("nearby")
    local panel = assert(c.BuffRadarNearbyDiagnostics)
    assert(panel:IsShown() and reads == 1)
    f.units.target = { "Drifter", "PRIEST" }
    f.event("PLAYER_TARGET_CHANGED")
    assert(panel.targetDirty and reads == 2)
    f.advance(0.11)
    assert(not panel.targetDirty and reads == 3 and panel.details:GetText():find("Drifter is on the list", 1, true))
    f.db.hidden = true
    f.units.target = { "Traveler", "MAGE" }
    f.event("PLAYER_TARGET_CHANGED"); f.advance(0.11)
    assert(not panel.targetDirty and reads == 5 and not c.BuffRadarFrame:IsShown())
    assert(panel.details:GetText():find("Traveler", 1, true) and not panel.details:GetText():find("on the list", 1, true))
    panel:Hide()
    f.units.target = { "Third", "MAGE" }
    f.event("PLAYER_TARGET_CHANGED"); f.advance(0.11, true)
    assert(reads == 5 and not panel.targetDirty and not panel.events.PLAYER_TARGET_CHANGED and not panel.events.CVAR_UPDATE)
    f.slash("nearby")
    assert(panel:IsShown() and panel.events.PLAYER_TARGET_CHANGED and panel.events.CVAR_UPDATE
      and panel.details:GetText():find("Third", 1, true) and reads == 6)
  end)

  step("audit: offender histories stay bounded, use GUIDs and count once per group", function()
    local f = fresh({}, true)
    local X, c = f.X, f.client
    local first = "Player-1-001"
    for i = 1, 160 do X.TrackOffender(string.format("Player-1-%03d", i), "SameName") end
    X.TrackOffender(first, "UpdatedName")
    assert(X.Settings.Count(X.offNow) == 128 and X.offNow[first] == "UpdatedName")
    c.IsInGroup, c.GetNumGroupMembers = function() return false end, function() return 0 end
    f.units.party1, f.units.party2 = nil, nil
    f.event("GROUP_LEFT")
    local off = f.db.offenders
    assert(X.Settings.Count(off) == 50 and off[first].name == "UpdatedName" and off[first].count == 1)
    assert(off["Player-1-002"].name == "SameName" and off["Player-1-002"].count == 1)
    f.event("GROUP_ROSTER_UPDATE")
    assert(not next(X.offNow) and f.db.offenders[first].count == 1)
  end)
end
