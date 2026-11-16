-- BuffRadar - Coordination: cast sync between BuffRadar users (1.5.0),
-- caster coordination (1.15.26), chat buff requests, per-buff context
-- checks and the join digest.
-- Loaded after BuffRadar.lua through the .toc. This is file-split Slice E
-- (1.15.34): the code below moved verbatim from BuffRadar.lua and reaches
-- that file's locals through X.coordAPI, which BuffRadar.lua fills in
-- before this file loads. The settings table arrives through X.dbSinks
-- once it exists; the two counters the main file reassigns (list length,
-- whether any buff is known) are read through accessors.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, NS = ...
local X = NS and NS.X
if not X or not X.coordAPI then return end
local A = X.coordAPI

local db = X.GetDB and X.GetDB()  -- nil until ADDON_LOADED; X.dbSinks updates it
X.dbSinks = X.dbSinks or {}
X.dbSinks[#X.dbSinks + 1] = function(value) db = value end

local L, Print, PlayAlert, QueueRefresh = A.L, A.Print, A.PlayAlert, A.QueueRefresh
local Ignore, Readable, IsOn = A.Ignore, A.Readable, A.IsOn
local InRaid, InGroup, InInstanceNow = A.InRaid, A.InGroup, A.InInstanceNow
local BLESSINGS, BUFF_DEFS, CLASSIC_FEATURES = A.BLESSINGS, A.BUFF_DEFS, A.CLASSIC_FEATURES
local RAID, PARTY, myBuffs, entries = A.RAID, A.PARTY, A.myBuffs, A.entries
local pairs, ipairs, next, type, pcall = pairs, ipairs, next, type, pcall
local tonumber = tonumber
local math_floor, math_max = math.floor, math.max
local string_format = string.format
local table_sort = table.sort
local wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
local GetTime, InCombatLockdown = GetTime, InCombatLockdown
local UnitExists, UnitGUID, UnitClass, UnitName = UnitExists, UnitGUID, UnitClass, UnitName

---------------------------------------------------------------------------
-- Coordination (1.5.0): cast sync between BuffRadar users, chat buff
-- requests, and a one-line summary when you join a group.
---------------------------------------------------------------------------
function X.InitSync()
  if X.syncReg then return end
  X.syncReg = true
  if _G.C_ChatInfo and _G.C_ChatInfo.RegisterAddonMessagePrefix then
    pcall(_G.C_ChatInfo.RegisterAddonMessagePrefix, "BuffRadar")
  elseif _G.RegisterAddonMessagePrefix then
    pcall(_G.RegisterAddonMessagePrefix, "BuffRadar")
  end
end

local function SyncChannel()
  if InRaid() then return "RAID" end
  if InGroup() then return "PARTY" end
end

-- One broadcast to the group's BuffRadar users (party or raid channel).
function X.Broadcast(msg)
  if not db or not db.sync then return false end
  local channel = SyncChannel()
  local send = (_G.C_ChatInfo and _G.C_ChatInfo.SendAddonMessage) or _G.SendAddonMessage
  if not channel or not send then return false end
  local ok, result = pcall(send, "BuffRadar", msg, channel)
  if not ok then return false end
  if type(result) == "nil" then return true end -- legacy API has no return value
  if not Readable(result) then return false end
  if type(result) == "number" then
    local success = _G.Enum and _G.Enum.SendAddonMessageResult and _G.Enum.SendAddonMessageResult.Success
    return result == (success or 0)
  end
  return result ~= false
end

-- Tell the other BuffRadar users in the group "I just cast KEY on GUID",
-- so their lists sink that player instead of double-casting the same buff.
function X.SyncSend(key, guid)
  local message = "CAST;" .. key .. ";" .. guid
  if CLASSIC_FEATURES then X.SendScopedSync(message) else X.Broadcast(message) end
end

-- Cover-me handoff (1.7.0): while you're dead or AFK, tell the other
-- BuffRadar users so your duties pass to them; tell them when you're
-- back. Broadcasts on state change, and re-sends every couple of
-- minutes while you're still away so their cover doesn't lapse.
function X.SendCover()
  if not db then return end
  local me = Ignore.UnitNames("player")
  if not me then return end
  local covered = X.PlayerSuspended() or X.ReadUnitBool(_G.UnitIsAFK, "player") == true
  if X.myCover == covered and not covered then return end
  if X.myCover == covered and GetTime() - (X.coverSentAt or 0) < 120 then return end
  X.myCover = covered
  X.coverSentAt = GetTime()
  X.Broadcast((covered and "COVER;" or "BACK;") .. me)
end

-- Do two player names refer to the same user? Names ride the wire as
-- typed (often the bare short name), while identity checks use full
-- "Name-Realm" strings. Same when the full names match, or the short
-- names match and neither side names a conflicting realm — the same
-- rule the ignore list has always used for bare names.
function X.SameUser(a, b)
  if not a or not b then return false end
  if Ignore.Key(a) == Ignore.Key(b) then return true end
  local as, ar = a:match("^([^%-]+)%-?(.*)$")
  local bs, br = b:match("^([^%-]+)%-?(.*)$")
  if Ignore.Key(as or "") ~= Ignore.Key(bs or "") then return false end
  if ar and ar ~= "" and br and br ~= ""
     and Ignore.Key(ar) ~= Ignore.Key(br) then return false end
  return true
end

do
  local supportedKeys = { BLESSINGS = true }
  for _, def in ipairs(BUFF_DEFS) do supportedKeys[def.key] = true end
  for _, def in ipairs(X.AURA_DEFS or {}) do supportedKeys[def.key] = true end

  local function ReadText(value)
    return type(value) == "string" and Readable(value)
  end

  local function ValidName(name)
    return ReadText(name) and #name <= 128 and name:find("%S") and not name:find("[%c;|]")
  end

  local function ValidBuffKey(key)
    return supportedKeys[key] or (#key <= 16 and key:match("^CUSTOM[1-9]%d*$"))
  end

  -- A refused realm is different from a readable empty realm, which means local.
  -- The ignore list can fall back to a short name, but roster authorization
  -- must never fill in a realm the game withheld.
  local function RosterNames(unit)
    local ok, name, realm = pcall(UnitFullName or UnitName, unit)
    if not ok or not ValidName(name) then return end
    if type(realm) ~= "nil" and (not ReadText(realm) or (realm ~= "" and not ValidName(realm))) then return end
    if not realm or realm == "" then
      if GetNormalizedRealmName then
        local realmOK, localRealm = pcall(GetNormalizedRealmName)
        if realmOK and ValidName(localRealm) then realm = localRealm end
      end
    end
    return realm and realm ~= "" and name .. "-" .. realm:gsub("%s+", "") or name, name
  end

  -- Match a full name exactly, or accept a bare name only if it is unique
  -- across the readable roster. The raid list already includes the player.
  function X.SenderUnit(sender)
    if not ValidName(sender) then return end
    local key = Ignore.Key(sender)
    local qualified = key:find("-", 1, true)
    local raid = InRaid()
    local roster = raid and RAID or PARTY
    local found, canonical
    for i = raid and 1 or 0, #roster do
      local unit = roster[i] or "player"
      if X.ReadUnitBool(UnitExists, unit) == true then
        local full, short = RosterNames(unit)
        if not full then
          if not qualified then return end
        elseif key == Ignore.Key(qualified and full or short) then
          if found then return end
          found, canonical = unit, full
        end
      end
    end
    return found, canonical
  end

  local function PlanRank(unit)
    local leader = X.ReadUnitBool(_G.UnitIsGroupLeader, unit)
    if leader == true then return 2 end
    local assistant = X.ReadUnitBool(_G.UnitIsGroupAssistant, unit)
    local idx = unit:match("^raid(%d+)$")
    if idx and GetRaidRosterInfo then
      local ok, _, rank = pcall(GetRaidRosterInfo, tonumber(idx))
      if ok and type(rank) == "number" and Readable(rank) and rank == 2 then return 2 end
      if ok and type(rank) == "number" and Readable(rank) and rank == 1 then return 1 end
      if assistant == true then return 1 end
      if ok and type(rank) == "number" and Readable(rank) and rank == 0 then return 0 end
    end
    if assistant == true then return 1 end
    if leader == false and (assistant == false or not InRaid()) then return 0 end
  end

  local function HasPlanRole(unit, forBless)
    if (PlanRank(unit) or 0) > 0 then return true end
    if forBless then
      local ok, _, class = pcall(UnitClass, unit)
      return ok and ReadText(class) and class == "PALADIN"
    end
    return false
  end

  function X.SenderTrusted(sender, forBless)
    local unit = X.SenderUnit(sender)
    return unit ~= nil and HasPlanRole(unit, forBless)
  end

  function X.AmLead()
    if HasPlanRole("player") then return true end
    if InRaid() then
      for i = 1, #RAID do
        if X.IsSelf(RAID[i]) == true then return HasPlanRole(RAID[i]) end
      end
    end
    return false
  end

  function X.PruneSyncRoster()
    if not next(X.peers) and not next(X.cover) then return end
    local roster = InRaid() and RAID or PARTY
    local present = {}
    for _, unit in ipairs(roster) do
      if X.ReadUnitBool(UnitExists, unit) == true then
        local full = RosterNames(unit)
        if full then present[Ignore.Key(full)] = true end
      end
    end
    for key in pairs(X.peers) do
      if not present[key] then X.peers[key] = nil end
    end
    for name in pairs(X.cover) do
      if not present[Ignore.Key(name)] then X.cover[name] = nil end
    end
  end

  local function RememberCast(guid, key, now)
    if not X.handled[guid] then
      local count, oldestGuid, oldestTime = 0, nil, now
      for seenGuid, handled in pairs(X.handled) do
        count = count + 1
        if not oldestGuid or handled.t < oldestTime then
          oldestGuid, oldestTime = seenGuid, handled.t
        end
      end
      if count >= 128 then X.handled[oldestGuid] = nil end
    end
    X.handled[guid] = { key = key, t = now }
  end

  local function OtherSyncSender(sender, channel)
    local unit, name = X.SenderUnit(sender)
    if not unit or unit == "player" then return end
    local me, senderKey = RosterNames("player"), Ignore.Key(name)
    if me and senderKey == Ignore.Key(me) then return end
    if channel == "RAID" then
      local isSelf = X.IsSelf(unit)
      if isSelf == true or (isSelf == nil and not me) then return end
    end
    return unit, name, senderKey, me
  end

  do
    local active, sequence, generation, token = nil, 0, 0, 0
    local resetReason
    local scope, nonceSerial
    local departedScopes, departedCount = {}, 0
    local retired, retirementOrder, retirementSlot = {}, {}, 1
    local statusLabels = { sent = "Awaiting acknowledgement", acknowledged = "Acknowledged",
      failed = "Send failed", localOnly = "Assigned locally" }

    local function SetSession(session, rosterChanged)
      active = session
      resetReason = rosterChanged and "Caster coordination was cleared because the group or its leadership changed." or nil
      generation = generation + 1
      token = token + 1
    end

    local function NotifyCoordination()
      token = token + 1
      if X.QueueCoordinationRefresh then X.QueueCoordinationRefresh() end
    end

    local function CoordinationGUID(unit)
      local ok, guid = pcall(UnitGUID, unit)
      if ok and ReadText(guid) and #guid <= 85 and guid:match("^Player%-%w[%w%-]*$") then return guid end
    end

    local function CoordinationRoster()
      local channel = SyncChannel()
      if not channel then return end
      local members, ids, leaders = {}, {}, 0
      local size = X.ReadUnitNumber(GetNumGroupMembers)
      X.ForReportRoster(function(unit, exists)
        local guid = exists and CoordinationGUID(unit)
        local name = guid and RosterNames(unit)
        local rank = name and PlanRank(unit)
        if rank ~= nil and not members[guid] then
          members[guid] = { name = name, unit = unit }
          ids[#ids + 1] = guid .. "=" .. rank
          if rank == 2 then leaders = leaders + 1 end
        end
      end)
      if size ~= #ids or leaders ~= 1 then return end
      table_sort(ids)
      return members, channel .. ":" .. table.concat(ids, ",")
    end

    local function SyncDigest(identity)
      local first, second = 0, 0
      for i = 1, #identity do
        local byte = identity:byte(i)
        first = (first * 131 + byte) % 2147483647
        second = (second * 137 + byte) % 2147483629
      end
      return string_format("%08x%08x", first, second)
    end

    local function NewSyncNonce()
      nonceSerial = (nonceSerial or 0) + 1
      return string_format("%06x%06x%06x%06x", math.random(0, 0xffffff), math.random(0, 0xffffff),
        math_floor(GetTime() * 1000) % 0x1000000, nonceSerial % 0x1000000)
    end

    local function RetireSyncEpoch(guid, epoch)
      if not epoch then return end
      local key = guid .. ":" .. epoch
      if retired[key] then return end
      local oldest = retirementOrder[retirementSlot]
      if oldest then retired[oldest] = nil end
      retired[key] = true
      retirementOrder[retirementSlot] = key
      retirementSlot = retirementSlot % 160 + 1
    end

    local function RememberDepartedScope(identity)
      if not departedScopes or departedScopes[identity] then return end
      if departedCount >= 64 then
        -- Once the history is full, require a fresh proof floor on every entry.
        departedScopes = nil
        return
      end
      departedScopes[identity] = true
      departedCount = departedCount + 1
    end

    local function BroadcastSyncWarmup(current, now)
      local nonce = NewSyncNonce()
      if not X.Broadcast("SYNC;3;B;" .. current.digest .. ";" .. nonce) then return false end
      current.priorWarmNonce, current.warmNonce, current.warmExpires = current.warmNonce, nonce, now + 3
      return true
    end

    local function RetrySyncWarmup(current)
      if not current or scope ~= current or not current.warmRetryAt then return end
      local now = GetTime()
      if now < current.warmRetryAt then return end
      current.warmRetryAt = nil
      if not db or not db.sync then return end
      local members, identity = CoordinationRoster()
      local me = CoordinationGUID("player")
      if identity ~= current.identity or not me or not members[me] then return end
      for guid in pairs(members) do
        local peer = current.peers[guid]
        if guid ~= me and not (peer and peer.epoch) then
          if BroadcastSyncWarmup(current, now) then
            -- Reordered data can still be proved by either broadcast. Keep
            -- only the existing bounded queues for this one extra window.
            for _, unresolved in pairs(current.peers) do
              if not unresolved.epoch and unresolved.pending then
                for _, pending in ipairs(unresolved.pending) do
                  if not pending.challenge then pending.expires = current.warmExpires end
                end
              end
            end
          end
          return
        end
      end
    end

    local function StartSyncWarmup(current)
      if not current or not current.requireProofFloor or current.warmAttempted or not db or not db.sync then return end
      current.warmAttempted = true
      local now = GetTime()
      BroadcastSyncWarmup(current, now)
      current.warmRetryAt = now + 3
      if C_Timer and C_Timer.After then
        C_Timer.After(3, function() RetrySyncWarmup(current) end)
      end
    end

    function X.RunDueSyncWarmupRetry()
      RetrySyncWarmup(scope)
    end

    local function UpdateSyncScope(force)
      if not CLASSIC_FEATURES then return end
      local members, identity = CoordinationRoster()
      if scope and scope.identity == identity and not force then
        StartSyncWarmup(scope)
        return scope, members
      end
      if scope then
        RememberDepartedScope(scope.identity)
        -- Remember epochs seen in the last scope in case this roster returns.
        for guid, peer in pairs(scope.peers) do
          RetireSyncEpoch(guid, peer.epoch)
          if peer.observed then
            for _, epoch in ipairs(peer.observed) do RetireSyncEpoch(guid, epoch) end
          end
        end
        wipe(X.handled)
      end
      if active and (force or active.identity ~= identity) then SetSession(nil, true) end
      scope = identity and { identity = identity, digest = SyncDigest(identity), epoch = NewSyncNonce(),
        requireProofFloor = not departedScopes or departedScopes[identity], seq = 0, peers = {} } or nil
      StartSyncWarmup(scope)
      return scope, members
    end

    function X.SendScopedSync(payload)
      if not db or not db.sync then return false end
      local current = UpdateSyncScope()
      if not current then return false end
      local seq = current.seq + 1
      local message = "SYNC;3;D;" .. current.digest .. ";" .. current.epoch .. ";" .. seq .. ";" .. payload
      if #message > 255 or not X.Broadcast(message) then return false end
      current.seq = seq
      return true
    end

    local function Session()
      if not active then return end
      if not db or not db.sync then SetSession(nil); return end
      local _, members = UpdateSyncScope()
      return active, members
    end

    local function LearnedKeys()
      local keys = {}
      for _, buff in ipairs(myBuffs) do
        if supportedKeys[buff.key] and not buff.self and not buff.custom
          and IsOn(buff.key, buff.default) and X.ContextOK(buff.key) then keys[buff.key] = true end
      end
      if X.HasKnownBlessings() and IsOn("BLESSINGS", true) and X.ContextOK("BLESSINGS") then
        keys.BLESSINGS = true
      end
      return keys
    end

    local function SortedKeys(keys)
      local list = {}
      for key in pairs(keys) do list[#list + 1] = key end
      table_sort(list)
      return list
    end

    local function KeyList(keys)
      return table.concat(SortedKeys(keys), ",")
    end

    local function ParseKeys(list)
      if list == "-" then return {} end
      if not list:match("^[%u_]+[,_%u]*$") then return end
      local keys = {}
      for key in list:gmatch("[%u_]+") do
        if keys[key] or not supportedKeys[key] then return end
        keys[key] = true
      end
      if KeyList(keys) == list then return keys end
    end

    local function SendCoord(kind, id, recipient, list)
      local message = "COORD;1;" .. kind .. ";" .. id
      if recipient then message = message .. ";" .. recipient end
      if list then message = message .. ";" .. (list ~= "" and list or "-") end
      return X.SendScopedSync(message)
    end

    local function NextCoordID()
      sequence = sequence + 1
      return string_format("%d.%d", math_floor(GetTime() * 1000), sequence)
    end

    local function DraftPlan(session, members, localGUID, localKeys)
      local demand, ordered, rows, loads = {}, {}, {}, {}
      for key in pairs(session.requested) do demand[key] = true end
      for guid, report in pairs(session.reports) do
        if members[guid] then
          if guid == localGUID then report = localKeys end
          for key in pairs(report) do demand[key] = true end
        end
      end
      for key in pairs(demand) do ordered[#ordered + 1] = key end
      table_sort(ordered)
      for _, key in ipairs(ordered) do
        local manual = X.assign[key]
        local choice
        if not manual then
          for guid, report in pairs(session.reports) do
            if guid == localGUID then report = localKeys end
            if members[guid] and report[key] then
              local load, existing = loads[guid] or 0, loads[choice] or 0
              if not choice or load < existing or (load == existing and guid < choice) then choice = guid end
            end
          end
        end
        rows[#rows + 1] = { key = key, guid = choice, manual = manual }
        if choice then loads[choice] = (loads[choice] or 0) + 1 end
      end
      return rows
    end

    local function SamePlan(a, b)
      if #a ~= #b then return false end
      for i, row in ipairs(a) do
        local other = b[i]
        if row.key ~= other.key or row.guid ~= other.guid or row.manual ~= other.manual then return false end
      end
      return true
    end

    local function PlanNames(row, members)
      local before = row.manual or L["Unassigned"]
      local after = row.guid and members[row.guid].name or row.manual or L["Provider unavailable"]
      return before, after
    end

    local function ReviewPlan(session, members)
      local me = CoordinationGUID("player")
      if me then session.reports[me] = LearnedKeys() end
      session.draft = DraftPlan(session, members)
      Print(L["Review Caster Plan"])
      if #session.draft == 0 then Print(L["No learned buff capabilities have been reported."]) end
      for _, row in ipairs(session.draft) do
        local before, after = PlanNames(row, members)
        Print(string_format(L["%s: %s -> %s"], row.key, before, after))
      end
    end

    local function ParsePlanRest(value)
      local revision, target, list = value:match("^(%d+%.%d+);([^;]+);([^;]+)$")
      if revision and #revision <= 32 then return revision, target, ParseKeys(list) end
    end

    local function NewerRevision(revision, previous)
      if not previous then return true end
      local millis, order = revision:match("^(%d+)%.(%d+)$")
      local oldMillis, oldOrder = previous:match("^(%d+)%.(%d+)$")
      return tonumber(millis) > tonumber(oldMillis)
        or (tonumber(millis) == tonumber(oldMillis) and tonumber(order) > tonumber(oldOrder))
    end

    local function PendingPlan(session, members, now)
      local pending = session.pending
      local coordinator = pending and members[pending.sender]
      local reply = coordinator and session.replies[pending.sender]
      if reply and reply.id == pending.id and now - reply.time <= 180 and HasPlanRole(coordinator.unit) then
        return pending, reply.time + 180
      end
    end

    function X.CoordinationSnapshot()
      local snapshot = { generation = generation, token = token, reports = {}, sent = {} }
      if not CLASSIC_FEATURES then
        snapshot.reason = "Caster Coordination is available in WoW: Forever."
        return snapshot
      end
      if not db or not db.sync or not SyncChannel() or InCombatLockdown() or X.PlayerSuspended() then
        snapshot.reason = "Caster Coordination needs cast sync and a group outside combat."
        return snapshot
      end
      local session, members = Session()
      snapshot.generation, snapshot.token, snapshot.available = generation, token, true
      if not session then
        local _, identity = CoordinationRoster()
        if not identity then
          snapshot.available, snapshot.reason = false, "Roster information is unavailable."
        else
          snapshot.reason = resetReason
        end
        return snapshot
      end
      local now = GetTime()
      local function Deadline(time)
        if time and time > now and (not snapshot.nextRefreshAt or time < snapshot.nextRefreshAt) then
          snapshot.nextRefreshAt = time
        end
      end
      snapshot.active, snapshot.leader = true, X.AmLead()
      local pending, pendingAt = PendingPlan(session, members, now)
      if pending then
        snapshot.pending = { name = pending.name, keys = SortedKeys(pending.keys),
          revision = pending.revision, reviewed = pending.reviewed == true }
        Deadline(pendingAt + 0.01)
      end
      if session.accepted and now <= session.accepted.expires then
        snapshot.accepted = { keys = SortedKeys(session.accepted.keys) }
        Deadline(session.accepted.expires + 0.01)
      end
      if not snapshot.leader then return snapshot end
      local readyAt = session.requestAt and session.requestAt + 10
      snapshot.canRequest = not readyAt or now >= readyAt
      Deadline(readyAt)
      snapshot.reportRequest = session.request ~= nil and now <= session.expires
      if snapshot.reportRequest then
        Deadline(session.expires + 0.01)
        local currentReports = {}
        for guid, member in pairs(members) do
          local keys = session.reports[guid]
          currentReports[#currentReports + 1] = { name = member.name, keys = keys and SortedKeys(keys) }
        end
        table_sort(currentReports, function(a, b) return a.name < b.name end)
        snapshot.reports = currentReports
        if session.draft then
          snapshot.draft = {}
          for _, row in ipairs(session.draft) do
            local before, after = PlanNames(row, members)
            snapshot.draft[#snapshot.draft + 1] = { key = row.key, before = before, after = after }
          end
          snapshot.canPublish = SamePlan(session.draft, DraftPlan(session, members, CoordinationGUID("player"), LearnedKeys()))
        end
      end
      if session.sent and now <= session.sent.expires then
        Deadline(session.sent.expires + 0.01)
        for _, guid in ipairs(session.sent.order) do
          snapshot.sent[#snapshot.sent + 1] = { name = members[guid].name, status = session.sent.recipients[guid] }
        end
      end
      return snapshot
    end

    local function OnCoordMessage(body, unit, name, now)
      local kind, id, rest = body:match("^;(%u+);(%d+%.%d+)(.*)$")
      if not kind or #id > 32 then return end
      local session, members = Session()
      local guid = session and CoordinationGUID(unit)
      local me = guid and CoordinationGUID("player")
      if not me or not members[guid] then return end
      if kind == "REQ" and rest == "" and HasPlanRole(unit) then
        if session.replies[guid] and now - session.replies[guid].time < 10 then return end
        session.replies[guid] = { id = id, time = now }
        SendCoord("REPORT", id, guid, KeyList(LearnedKeys()))
        if session.pending and session.pending.sender == guid then NotifyCoordination() end
      elseif kind == "REPORT" and session.request == id and now <= session.expires and X.AmLead() then
        local target, list = rest:match("^;([^;]+);([^;]+)$")
        if not list or target ~= me or session.reports[guid] then return end
        local keys = ParseKeys(list)
        if not keys then return end
        session.reports[guid] = keys
        NotifyCoordination()
      elseif kind == "PLAN" and HasPlanRole(unit) then
        if rest:sub(1, 1) ~= ";" then return end
        local reply = session.replies[guid]
        local revision, target, keys = ParsePlanRest(rest:sub(2))
        if not reply or reply.id ~= id or now - reply.time > 180 or target ~= me or not keys
          or not NewerRevision(revision, reply.revision) then return end
        local learned = LearnedKeys()
        for key in pairs(keys) do if not learned[key] then return end end
        reply.revision = revision
        session.pending = { sender = guid, name = name, id = id, revision = revision, keys = keys }
        Print(string_format(L["Caster plan from %s. Use /br coordinate inbox to review it."], name))
        NotifyCoordination()
      elseif kind == "ACK" and session.sent and now <= session.sent.expires and id == session.sent.revision and rest == "" then
        if session.sent.recipients[guid] == "sent" then
          session.sent.recipients[guid] = "acknowledged"
          NotifyCoordination()
        end
      end
    end

    function X.OnCoordinationRoster(force)
      UpdateSyncScope(force)
      if active and (not db or not db.sync) then SetSession(nil) end
      if X.QueueCoordinationRefresh then X.QueueCoordinationRefresh() end
    end

    function X.StopCoordination()
      SetSession(nil)
      if scope and (not db or not db.sync) then
        scope.warmRetryAt = nil
        scope.warmNonce, scope.priorWarmNonce, scope.warmExpires = nil, nil, nil
        for _, peer in pairs(scope.peers) do peer.pending = nil end
      end
      if X.QueueCoordinationRefresh then X.QueueCoordinationRefresh() end
    end

    function X.CoordinatedHolder(key)
      local accepted = active and db.sync and active.accepted
      if accepted and GetTime() <= accepted.expires then return accepted.keys[key] and accepted.name end
    end

    local function Coordinate(command, argument)
      if not CLASSIC_FEATURES then Print(L["Caster Coordination is available in WoW: Forever."]); return end
      if command == "off" then
        X.StopCoordination()
        if QueueRefresh then QueueRefresh() end
        Print(L["Caster Coordination is off."])
        return
      end
      if command == "" then
        Print(L["Use /br coordinate panel|on|off|request|need|review|publish|status|inbox|accept|decline."])
        return
      end
      if not db or not db.sync or not SyncChannel() or InCombatLockdown() or X.PlayerSuspended() then
        Print(L["Caster Coordination needs cast sync and a group outside combat."]); return
      end
      if command == "on" then
        local current = UpdateSyncScope()
        if not current then Print(L["Roster information is unavailable."]); return end
        SetSession({ identity = current.identity, reports = {}, replies = {}, requested = {} })
        Print(L["Caster Coordination is on for this group."]); return
      end
      local session, members = Session()
      if not session then Print(L["Use /br coordinate on to join this group's caster planning."]); return end
      local me = CoordinationGUID("player")
      local now = GetTime()
      if not me or not members[me] then Print(L["Roster information is unavailable."]); return end
      if command == "inbox" or command == "accept" or command == "decline" then
        local pending = PendingPlan(session, members, now)
        if not pending then
          session.pending = nil; Print(L["No current caster plan to review."]); return
        end
        if command == "inbox" then
          pending.reviewed = true
          Print(string_format(L["Caster plan from %s: %s. Use /br coordinate accept or decline."],
            pending.name, next(pending.keys) and KeyList(pending.keys) or L["No assigned buffs"]))
        elseif command == "decline" then
          session.pending = nil
        elseif not pending.reviewed then
          Print(L["Review the caster plan with /br coordinate inbox first."])
        else
          local learned = LearnedKeys()
          for key in pairs(pending.keys) do
            if not learned[key] or X.assign[key] and not X.SameUser(X.assign[key], members[me].name) then
              Print(L["Your learned buffs or existing assignments changed. Ask for a new caster plan."]); return
            end
          end
          if not SendCoord("ACK", pending.revision) then Print(L["The caster message could not be sent."]); return end
          session.accepted = next(pending.keys) and { keys = pending.keys, name = members[me].name,
            coordinator = pending.sender, expires = now + 180 } or nil
          session.pending = nil
          Print(L["Caster duties accepted."])
          if QueueRefresh then QueueRefresh() end
        end
        return
      end
      if not X.AmLead() then Print(L["Only the group leader or an assistant can manage caster plans."]); return end
      if command == "request" then
        if session.requestAt and now - session.requestAt < 10 then return end
        local id = NextCoordID()
        if not SendCoord("REQ", id) then Print(L["The caster message could not be sent."]); return end
        session.request, session.requestAt, session.expires = id, now, now + 180
        session.reports, session.draft = { [me] = LearnedKeys() }, nil
        Print(L["Asked group members for their learned buffs."])
      elseif command == "need" then
        local key = argument and argument:upper()
        if not key or not supportedKeys[key] then Print(L["Use /br coordinate need <BUFF KEY>."]); return end
        session.requested[key] = true
        session.draft = nil
      elseif command == "status" and session.sent then
        for _, guid in ipairs(session.sent.order) do
          local status = session.sent.recipients[guid]
          Print(string_format(L["%s: %s"], members[guid].name, L[statusLabels[status]]))
        end
      elseif not session.request or now > session.expires then
        Print(L["Request fresh caster reports with /br coordinate request."])
      elseif command == "publish" then
        if not session.draft then Print(L["Review the caster plan with /br coordinate review first."]); return end
        session.reports[me] = LearnedKeys()
        local fresh = DraftPlan(session, members)
        if not SamePlan(session.draft, fresh) then
          Print(L["Caster reports or assignments changed. Review the updated draft before publishing."])
          ReviewPlan(session, members); return
        end
        local plan, order, revision = {}, {}, NextCoordID()
        for _, row in ipairs(fresh) do
          if row.guid then
            if not plan[row.guid] then plan[row.guid] = {}; order[#order + 1] = row.guid end
            plan[row.guid][row.key] = true
          end
        end
        if session.sent then
          for _, guid in ipairs(session.sent.order) do
            if not plan[guid] and session.reports[guid] then plan[guid] = {}; order[#order + 1] = guid end
          end
        end
        if not next(plan) then Print(L["No new caster duties to send."]); return end
        table_sort(order)
        local sent = { revision = revision, order = order, recipients = {}, expires = now + 180 }
        for _, guid in ipairs(order) do
          local keys = plan[guid]
          if guid == me then
            session.accepted = next(keys) and { keys = keys, name = members[guid].name,
              coordinator = me, expires = now + 180 } or nil
            sent.recipients[guid] = "localOnly"
          else
            -- Include the report request and a separate publication revision.
            local target = revision .. ";" .. guid
            sent.recipients[guid] = SendCoord("PLAN", session.request, target, KeyList(keys)) and "sent" or "failed"
          end
        end
        session.sent, session.draft = sent, nil
        if QueueRefresh then QueueRefresh() end
        Coordinate("status")
      else
        ReviewPlan(session, members)
      end
    end

    function X.Coordinate(command, argument, expectedToken)
      if expectedToken ~= nil then
        Session()
        if expectedToken ~= token then
          if X.QueueCoordinationRefresh then X.QueueCoordinationRefresh() end
          return
        end
      end
      Coordinate(command, argument)
      NotifyCoordination()
    end

    local function ScopedPayload(payload)
      local first, guid = payload:match("^CAST;([%w_]+);([%a]+%-%w[%w%-]*)$")
      if guid and #guid <= 85 and ValidBuffKey(first) then return first, guid end
      local body = payload:match("^COORD;1(;.+)$")
      if body and active and not InCombatLockdown() and not X.PlayerSuspended() then
        return body
      end
    end

    local function ApplyScopedPacket(packet, unit, name, senderKey, now)
      local first, guid = ScopedPayload(packet.payload)
      if not first then return end
      if guid then
        RememberCast(guid, first, now)
        local presence = X.peers[senderKey] or {}
        presence.t, presence.name = now, name
        X.peers[senderKey] = presence
        if QueueRefresh then QueueRefresh() end
      elseif packet.generation == generation then
        OnCoordMessage(first, unit, name, now)
      end
    end

    local function SyncControl(kind, current, epoch, challenge, target)
      local message = "SYNC;3;" .. kind .. ";" .. current.digest .. ";" .. epoch .. ";" .. challenge .. ";" .. target
      if kind == "P" then message = message .. ";" .. current.seq end
      return X.Broadcast(message)
    end

    local function NewSyncSequence(window, seq)
      -- Broadcast plan rows can arrive out of order. A fixed receive window
      -- accepts that reordering without replaying a previously seen packet.
      local slot = seq % 32
      if seq <= window.floor or seq <= window.high - 32 or window[slot] == seq then return false end
      window.high = math_max(window.high, seq)
      window[slot] = seq
      return true
    end

    local function FindSyncPending(peer, epoch, now)
      if not peer or not peer.pending then return end
      for i = #peer.pending, 1, -1 do
        local pending = peer.pending[i]
        if now > pending.expires then
          table.remove(peer.pending, i)
        elseif pending.epoch == epoch then
          return pending
        end
      end
    end

    local function ObserveSyncEpoch(peer, epoch)
      local observed = peer.observed or {}
      for _, previous in ipairs(observed) do if previous == epoch then return end end
      if #observed >= 4 then table.remove(observed, 1) end
      observed[#observed + 1] = epoch
      peer.observed = observed
    end

    function X.HandleScopedSync(version, rest, channel, source, now)
      if not CLASSIC_FEATURES or version ~= "3" then return end
      local kind, digest, epoch, field, payload = rest:match("^;([DQP]);([%da-f]+);([%da-f]+);([^;]+);(.+)$")
      if not kind then
        digest, field = rest:match("^;B;([%da-f]+);([%da-f]+)$")
        if not digest or #field ~= 24 then return end
        kind = "B"
      end
      if #digest ~= 16 or (epoch and #epoch ~= 24) then return end
      local me = CoordinationGUID("player")
      if not me then return end
      local proofFloor
      if kind == "P" or kind == "Q" then
        local target = payload
        if kind == "P" then
          local floor
          target, floor = payload:match("^([^;]+);([^;]+)$")
          if not floor or #floor > 10 or (floor ~= "0" and not floor:match("^[1-9]%d*$")) then return end
          proofFloor = tonumber(floor)
        end
        if target ~= me or #field ~= 24 or not field:match("^[%da-f]+$") then return end
      end
      local unit, name, senderKey = OtherSyncSender(source, channel)
      local sender = unit and CoordinationGUID(unit)
      if not sender then return end
      local current, members = UpdateSyncScope()
      if not current or current.digest ~= digest or not members[sender] or not members[me] then return end
      local peer = current.peers[sender] or {}
      local warmActive = current.warmExpires and now <= current.warmExpires
      if kind == "B" then
        if peer.warmReplyAt and now - peer.warmReplyAt < 1 then return end
        local answered = peer.warmReplies or {}
        for _, nonce in ipairs(answered) do if nonce == field then return end end
        if SyncControl("P", current, current.epoch, field, sender) then
          if #answered >= 4 then table.remove(answered, 1) end
          answered[#answered + 1] = field
          peer.warmReplies, peer.warmReplyAt = answered, now
          current.peers[sender] = peer
        end
      elseif kind == "Q" then
        if epoch == current.epoch and peer.answered ~= field and SyncControl("P", current, epoch, field, sender) then
          peer.answered = field
          current.peers[sender] = peer
        end
      elseif kind == "P" then
        local pending = FindSyncPending(peer, epoch, now)
        local isWarm = field == current.warmNonce or field == current.priorWarmNonce
        if isWarm then
          if not warmActive or peer.epoch then return end
        else
          if not pending or pending.challenge ~= field then return end
          if current.requireProofFloor and proofFloor < pending.challengeSeq then return end
          if not current.requireProofFloor and retired[sender .. ":" .. epoch] then return end
        end
        if peer.epoch ~= epoch then RetireSyncEpoch(sender, peer.epoch) end
        -- A sender may have missed the transition back to this exact roster.
        -- Accept only traffic it produced after answering the new challenge.
        local window = pending and pending.window or { high = 0, floor = 0 }
        if current.requireProofFloor then window.floor = proofFloor end
        peer.epoch, peer.window, peer.pending = epoch, window, nil
        current.peers[sender] = peer
        if pending then
          table_sort(pending.packets, function(a, b) return a.seq < b.seq end)
          for _, packet in ipairs(pending.packets) do
            if packet.seq > window.floor then ApplyScopedPacket(packet, unit, name, senderKey, now) end
          end
        end
      else
        if #field > 10 or not field:match("^[1-9]%d*$") or not ScopedPayload(payload) then return end
        local seq = tonumber(field)
        local packet = { payload = payload, generation = generation, seq = seq }
        if peer.epoch == epoch then
          if not NewSyncSequence(peer.window, seq) then return end
          ApplyScopedPacket(packet, unit, name, senderKey, now)
        else
          if not current.requireProofFloor and retired[sender .. ":" .. epoch] then return end
          local pending = FindSyncPending(peer, epoch, now)
          if not pending then
            local challenge, expires
            if warmActive and not peer.epoch then
              -- Let the broadcast proof arrive before issuing a targeted
              -- challenge that would count these held packets in its floor.
              expires = current.warmExpires
            else
              challenge, expires = NewSyncNonce(), now + 5
              if not SyncControl("Q", current, epoch, challenge, sender) then return end
            end
            pending = { epoch = epoch, challenge = challenge, challengeSeq = seq, expires = expires,
              window = { high = 0, floor = 0 }, packets = {} }
            peer.pending = peer.pending or {}
            if #peer.pending >= 2 then table.remove(peer.pending, 1) end
            peer.pending[#peer.pending + 1] = pending
            current.peers[sender] = peer
            ObserveSyncEpoch(peer, epoch)
          end
          local replace
          if #pending.packets >= 8 then
            if pending.challenge then return end
            -- A burst of stale packets must not crowd newer cast or plan data
            -- out of the queue before the broadcast proof supplies its floor.
            local lowest = seq
            for index, held in ipairs(pending.packets) do
              if held.seq < lowest then replace, lowest = index, held.seq end
            end
            if not replace then return end
          end
          if not NewSyncSequence(pending.window, seq) then return end
          pending.packets[replace or #pending.packets + 1] = packet
          return
        end
      end
    end
  end

  function X.OnAddonMsg(prefix, msg, channel, sender)
    if not db or not db.sync or not ReadText(prefix) or prefix ~= "BuffRadar" then return end
    if not ReadText(channel) or channel ~= SyncChannel() then return end
    if not ReadText(msg) or #msg > 255 then return end
    local kind, first, rest = msg:match("^([A-Z]+);([^;]+)(.*)$")
    if not kind then return end
    local now = GetTime()
    if kind == "SYNC" then
      X.HandleScopedSync(first, rest, channel, sender, now)
      return
    end

    local unit, name, senderKey, me = OtherSyncSender(sender, channel)
    if not unit then return end
    if kind == "CAST" then
      if CLASSIC_FEATURES then return end
      local guid = rest:match("^;([%a]+%-%w[%w%-]*)$")
      if not guid or #guid > 85 or not ValidBuffKey(first) then return end
      RememberCast(guid, first, now)
    elseif kind == "ASSIGN" then
      local holder = rest:match("^;([^;]+)$")
      if not ValidBuffKey(first) or not ValidName(holder) or not HasPlanRole(unit) then return end
      if holder:lower() == "none" then X.assign[first] = nil else X.assign[first] = holder end
    elseif kind == "BLESS" then
      local key, holder = rest:match("^;([%w_]+);([^;]+)$")
      if not key or not X.BLESSING_CLASSES[first] or not ValidName(holder)
        or (key ~= "NONE" and not BLESSINGS[key]) or not HasPlanRole(unit, true) then return end
      if key == "NONE" or holder == "none" then
        X.blessPlan[first] = nil
      else
        X.blessPlan[first] = { key = key, name = holder, mine = me ~= nil and X.SameUser(holder, me) }
      end
    elseif kind == "COVER" or kind == "BACK" or kind == "HELLO" or kind == "HERE" then
      if rest ~= "" or not ValidName(first) or not X.SameUser(first, name) then return end
      if kind == "COVER" then X.cover[name] = now + 300 end
      if kind == "BACK" then X.cover[name] = nil end
    else
      return
    end

    local peer = X.peers[senderKey] or {}
    peer.t, peer.name = now, name
    X.peers[senderKey] = peer
    if kind == "HELLO" and me and (not peer.replyAt or now - peer.replyAt >= 10) then
      peer.replyAt = now
      X.Broadcast("HERE;" .. me)
    end
    if kind == "ASSIGN" and X.QueueCoordinationRefresh then X.QueueCoordinationRefresh() end
    if QueueRefresh then QueueRefresh() end
  end
end

-- A whisper or a nearby "buff ..." marks that player's row while it is up.
function X.OnChatAsk(text, author)
  if not db or not db.requests or X.PlayerSuspended() then return end
  if type(text) ~= "string" or not Readable(text)
    or type(author) ~= "string" or not Readable(author) then return end
  if not text:lower():find("buff", 1, true) then return end
  local short = author:match("^[^%-]+") or author
  local ka, ks = Ignore.Key(author), Ignore.Key(short)
  for i = 1, A.nEntries() do
    local e = entries[i]
    if e and (Ignore.Key(e.fullName or "") == ka or Ignore.Key(e.sortName or "") == ks) then
      if (not X.asked[e.guid] or GetTime() - X.asked[e.guid] > 30)
         and db.playSound and GetTime() - X.lastSoundAt > 1 then
        X.lastSoundAt = GetTime()
        PlayAlert("ask")
      end
      X.asked[e.guid] = GetTime()
      if QueueRefresh then QueueRefresh() end
      return
    end
  end
end

-- Does one of my equipped weapons lack a temporary enchant (a shaman
-- imbue, a rogue poison, an oil or a sharpening stone)? (1.7.0)
-- GetWeaponEnchantInfo is the game's own answer; a hand only counts
-- when a weapon is actually equipped in it.
-- Per-buff context (1.8.0): a buff can be limited to raids or to
-- instances (dungeons, raids, battlegrounds) and is then simply not
-- offered anywhere else. Set with /br context KEY raid|instance|always.
-- On Forever, Shadow Protection ships with the instance limit as its
-- default (the resistance-context rule) until the user changes it.
function X.ContextOK(key)
  local c = db and db.buffContext and db.buffContext[key]
  if not c then return true end
  if c == "raid" then return InRaid() end
  if c == "instance" then return InInstanceNow() ~= nil end
  return true
end

function X.WeaponEnchantMissing()
  local fn = _G.GetWeaponEnchantInfo
  if not fn then return false end
  local ok, hasMH, _, _, _, hasOH = pcall(fn)
  if not ok or not Readable(hasMH) or not Readable(hasOH) then return false end
  local function equipped(slot)
    if not _G.GetInventoryItemID then return true end
    local okI, id = pcall(_G.GetInventoryItemID, "player", slot)
    return okI and Readable(id) and id ~= nil
  end
  if not hasMH and equipped(16) then return true end
  if not hasOH and equipped(17) then return true end
  return false
end

-- Instance-entry reminder (1.7.0): stepping into a dungeon, raid or
-- battleground with buffs still missing gets one clear line, once per
-- entry — the run-start counterpart of the join digest.
function X.InstanceCheck()
  if not db then return end
  local ctx = X.Context()
  local inside = ctx == "dungeon" or ctx == "raid" or ctx == "pvp"
  if inside and not X.wasInside and db.enterFlash and InGroup() and A.hasAnyBuff()
     and not X.PlayerSuspended() then
    local report = X.GroupBuffReport()
    local people = #report.people
    if people > 0 then
      Print(string.format("Entered the %s with buffs missing: %d %s still need buffs (%d buffs needed).",
        ctx == "dungeon" and "dungeon" or (ctx == "raid" and "raid" or "battleground"),
        people, people == 1 and "person" or "people", report.buffs))
    end
  end
  X.wasInside = inside
end

-- One line in chat: how much buffing the group (or the run) still needs.
-- Counts everyone, ignoring the window's role filter.
function X.JoinDigest(why)
  if not db or not InGroup() or X.PlayerSuspended() then return end
  local report = X.GroupBuffReport()
  local people = #report.people
  if people == 0 then return end
  Print(string.format("%s: %d %s missing buffs (%d buffs needed).",
    why == "run" and "Run starting" or "Joined a group",
    people, people == 1 and "person is" or "people are", report.buffs))
end

-- Roster events: only the step from solo to grouped triggers the join
-- summary, not every roster shuffle afterwards.
function X.OnRoster()
  local g = InGroup()
  if not g and X.CloseRaidPreparation then X.CloseRaidPreparation() end
  if not InRaid() then X.subgroupDuties = nil end
  X.PruneBlessingExceptions()
  X.PruneAssignmentRoleOverrides()
  X.PruneBlockerUndo()
  if db then X.SendCover() end  -- roster changes refresh a live cover (1.7.0)
  if X.inGroupPrev == false and g and db and db.joinDigest and A.hasAnyBuff() then
    if C_Timer and C_Timer.After then
      C_Timer.After(1.5, function() X.JoinDigest("join") end)
    else
      X.JoinDigest("join")
    end
  end
  -- Presence (1.6.0): say hello (throttled) so other users know a buddy is
  -- here; assignments and plans belong to the group, so they end with it.
  if g and db and db.sync and GetTime() - (X.helloAt or 0) > 10 then
    X.helloAt = GetTime()
    local me = Ignore.UnitNames("player")
    if me then X.Broadcast("HELLO;" .. me) end
  end
  if g then
    X.PruneSyncRoster()
  else
    wipe(X.assign)
    wipe(X.blessPlan)
    wipe(X.peers)
    wipe(X.cover)
    wipe(X.handled)
    X.upTotal, X.upFull = 0, 0  -- the run is over (1.6.0)
    -- Repeat-offender history (1.8.0): the session that just ended
    -- counts once for everyone who was seen unbuffed during it.
    if db then
      for name in pairs(X.offNow) do
        db.offenders[name] = (db.offenders[name] or 0) + 1
      end
      local orows = {}
      for nm, c in pairs(db.offenders) do orows[#orows + 1] = { nm = nm, c = c } end
      if #orows > 50 then  -- keep the worst 50 only
        table_sort(orows, function(a, b) return a.c > b.c end)
        for i = 51, #orows do db.offenders[orows[i].nm] = nil end
      end
    end
    wipe(X.offNow)
  end
  X.inGroupPrev = g
end
