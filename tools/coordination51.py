"""Run two isolated Forever addon clients over an explicit offline message bus."""

import argparse
from dataclasses import dataclass, replace
from pathlib import Path

from lupa import lua51


CLIENT = r"""function(name, guid, withTimer)
  local chat = {}
  local env = WOWSTUB(chat, withTimer, false, true, false)
  local std = { string=string, table=table, math=math, pairs=pairs, ipairs=ipairs, next=next,
    type=type, select=select, pcall=pcall, tostring=tostring, tonumber=tonumber, error=error,
    setmetatable=setmetatable, getmetatable=getmetatable, rawget=rawget, rawset=rawset,
    unpack=unpack, strlower=string.lower, format=string.format, os=os }
  setmetatable(env, { __index = std })
  env._G = env
  local ns, driver = {}, nil
  local units = { player = { name, guid } }
  local leader, now = name, 1000
  local function configure(other, otherGUID, third, newLeader, clock, fourth)
    units.party1 = other and { other, otherGUID } or nil
    units.party2 = third and { "Tara", "Player-1-0003" } or nil
    units.party3 = fourth and { "Wren", "Player-1-0004" } or nil
    leader, now = newLeader, clock
  end
  local timers = {}
  if env.C_Timer then
    env.C_Timer.After = function(delay, callback)
      timers[#timers + 1] = { deadline = now + delay, callback = callback }
    end
  end
  local over = env.__over
  over.GetTime = function() return now end
  over.UnitExists = function(unit) return units[unit] ~= nil end
  over.UnitIsPlayer = over.UnitExists
  over.UnitGUID = function(unit) if units[unit] then return units[unit][2] end end
  over.UnitName = function(unit) if units[unit] then return units[unit][1] end end
  over.UnitFullName = function(unit)
    if units[unit] then return units[unit][1], "TestRealm" end
  end
  over.UnitClass = function(unit)
    if unit == "party2" or unit == "party3" then return "Warrior", "WARRIOR" end
    if units[unit] then return "Priest", "PRIEST" end
  end
  env.IsInGroup = function() return units.party1 ~= nil end
  env.GetNumGroupMembers = function()
    return units.party3 and 4 or units.party2 and 3 or units.party1 and 2 or 0
  end
  env.UnitIsGroupLeader = function(unit) return units[unit] ~= nil and units[unit][1] == leader end
  env.UnitIsGroupAssistant = function() return false end
  env.IsSpellInRange = function() return 1 end
  env.C_ChatInfo = {
    SendAddonMessage = env.SendAddonMessage,
    RegisterAddonMessagePrefix = function() return true end,
  }

  local function fire(event, ...)
    assert(driver.events[event], name .. " did not register " .. event)
    driver.scripts.OnEvent(driver, event, ...)
  end
  local function start()
    for _, frame in ipairs(env.__frames) do
      if frame.events and frame.events.ADDON_LOADED then driver = frame; break end
    end
    assert(driver, "BuffRadar event driver not found")
    for _, frame in ipairs(env.__frames) do
      if frame.events and frame.events.ADDON_LOADED then
        frame.scripts.OnEvent(frame, "ADDON_LOADED", "BuffRadar")
      end
    end
    fire("PLAYER_LOGIN")
    local db = env.BuffRadarDB
    db.pauseInCities, db.hidden, db.autoHide, db.groupCast = false, false, false, false
    db.sync = true
  end
  local function drainTimers()
    for _ = 1, 32 do
      local earliest
      for index, timer in ipairs(timers) do
        if timer.deadline <= now and (not earliest or timer.deadline < timers[earliest].deadline) then
          earliest = index
        end
      end
      if not earliest then return end
      local timer = table.remove(timers, earliest)
      timer.callback()
    end
    error("due timers did not settle")
  end
  local function rowFor(unit)
    local index = 1
    while env["BuffRadarRow" .. index] do
      local row = env["BuffRadarRow" .. index]
      if row:IsShown() and row.entry and row.entry.unit == unit then return row end
      index = index + 1
    end
  end
  return {
    configure = configure,
    load = function(source, path)
      local chunk = assert(loadstring(source, "@" .. path))
      setfenv(chunk, env)
      chunk("BuffRadar", ns)
    end,
    start = start,
    fire = fire,
    advance = function(clock)
      assert(clock >= now, "mock clock cannot move backward")
      local elapsed = clock - now
      now = clock
      if withTimer then
        drainTimers()
      else
        driver.scripts.OnUpdate(driver, elapsed)
      end
    end,
    buffers = function(fortitude, spirit)
      local db = env.BuffRadarDB
      db.enabled.FORTITUDE, db.enabled.DIVINE_SPIRIT = fortitude, spirit
      ns.X.Core.BuildBuffList()
    end,
    slash = function(command) env.SlashCmdList.BUFFRADAR("coordinate " .. command) end,
    toggleSync = function() env.SlashCmdList.BUFFRADAR("sync") end,
    snapshot = function() return ns.X.CoordinationSnapshot() end,
    peerSnapshot = function() return ns.X.SyncPeerSnapshot() end,
    readonlyCoordination = function() return ns.X.CoordinationSnapshot(true) end,
    supportReport = function() return ns.X.Support.Report() end,
    holder = function(key) return ns.X.CoordinatedHolder(key) end,
    manualHolder = function(key) return ns.X.assign[key] end,
    drain = function()
      local sent = env.__addonSent
      env.__addonSent = {}
      return sent
    end,
    refresh = function() env.SlashCmdList.BUFFRADAR("show"); drainTimers() end,
    row = function(unit)
      local row = rowFor(unit)
      return row ~= nil, row and row.entry.handled == true
    end,
    cast = function(unit, castGUID)
      local row = assert(rowFor(unit), name .. " has no visible row for " .. unit)
      local spell = row:GetAttribute("spell")
      assert(spell and spell:find("Power Word: Fortitude", 1, true), "row is not armed for Fortitude")
      assert(row:GetAttribute("unit") == unit, "row armed for wrong unit")
      row.scripts.PreClick(row, "LeftButton", false)
      row.scripts.PostClick(row, "LeftButton", false)
      fire("UNIT_SPELLCAST_SENT", "player", env.UnitName(unit), castGUID, 1244)
      fire("UNIT_SPELLCAST_SUCCEEDED", "player", castGUID, 1244)
    end,
    handledAt = function(targetGUID, key)
      local handled = ns.X.handled[targetGUID]
      return handled and handled.key == key and handled.t or nil
    end,
  }
end"""


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def forever_sources(addon):
    root = addon.resolve().parent
    toc = root.parent / "editions" / "forever" / "BuffRadar.toc"
    files = []
    for line in toc.read_text(encoding="utf-8-sig").splitlines():
        path = line.strip()
        if path and not path.startswith("#") and path.lower().endswith(".lua"):
            source = root / path.replace("\\", "/")
            files.append((path, source.read_text(encoding="utf-8-sig")))
    check(any((root / path.replace("\\", "/")) == addon.resolve() for path, _ in files),
          "addon path is absent from Forever TOC")
    return files


class Client:
    def __init__(self, stub, sources, name, guid, with_timer=True):
        self.name, self.guid = name, guid
        self.outbox = []
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(stub)
        self.api = self.lua.eval(CLIENT)(name, guid, with_timer)
        for path, source in sources:
            self.api.load(source, path)

    def action(self, command):
        self.api.slash(command)

    def snapshot(self):
        return self.api.snapshot()


@dataclass(frozen=True)
class Packet:
    sender: str
    prefix: str
    message: str
    channel: str

    @property
    def body(self):
        parts = self.message.split(";", 6)
        check(parts[:3] == ["SYNC", "3", "D"] and len(parts) == 7,
              f"expected scoped data packet, got {self}")
        return parts[6]

    @property
    def sequence(self):
        return int(self.message.split(";", 6)[5])


class Party:
    def __init__(self, stub, sources, third=False, with_timer=True):
        self.a = Client(stub, sources, "Alia", "Player-1-0001")
        self.b = Client(stub, sources, "Bren", "Player-1-0002", with_timer)
        self.update(self.a, third, 1000)
        for client in (self.a, self.b):
            client.api.start()
            client.api.drain()

    def update(self, leader, third, clock, event=None, fourth=False, clients=None, solo=False):
        clients = (self.a, self.b) if clients is None else clients
        for local, remote in ((self.a, self.b), (self.b, self.a)):
            if local in clients:
                local.api.configure(None if solo else remote.name, remote.guid, third, leader.name, clock, fourth)
        if event:
            for client in clients:
                client.api.fire(event)
                client.outbox.extend(packet for packet in self.drain(client)
                                     if not packet.message.startswith(("HELLO;", "COVER;", "BACK;")))

    @staticmethod
    def drain(client):
        sent = client.api.drain()
        return [Packet(client.name + "-TestRealm", msg.prefix, msg.msg, msg.channel)
                for msg in (sent[i] for i in range(1, len(sent) + 1))]

    @staticmethod
    def capture(client):
        packets = client.outbox + Party.drain(client)
        client.outbox = []
        return packets

    def packet(self, client, start):
        packets = self.capture(client)
        check(len(packets) == 1 and packets[0].body.startswith(start),
              f"{client.name} should send exactly one {start} packet, got {packets}")
        packet = packets[0]
        check((packet.prefix, packet.channel) == ("BuffRadar", "PARTY")
              and len(packet.message) <= 255,
              f"bad packet envelope: {packet}")
        return packet

    @staticmethod
    def deliver(packet, client):
        client.api.fire("CHAT_MSG_ADDON", packet.prefix, packet.message, packet.channel, packet.sender)

    def roster_challenge(self, client):
        packets = self.capture(client)
        check(len(packets) == 1 and packets[0].message.startswith("SYNC;3;B;"),
              f"{client.name} did not send exactly one roster challenge: {packets}")
        packet = packets[0]
        fields = packet.message.split(";")
        check(len(fields) == 5 and len(fields[3]) == 16 and len(fields[4]) == 24
              and (packet.prefix, packet.channel) == ("BuffRadar", "PARTY"),
              f"bad roster challenge envelope: {packet}")
        return packet

    def answer(self, question, sender):
        self.deliver(question, sender)
        outgoing = self.drain(sender)
        proofs = [reply for reply in outgoing if reply.message.startswith("SYNC;3;P;")]
        sender.outbox.extend(reply for reply in outgoing if reply not in proofs)
        check(len(proofs) <= 1, "one challenge produced more than one proof")
        return proofs

    def roster_proof(self, challenge, sender, receiver):
        proofs = self.answer(challenge, sender)
        check(len(proofs) == 1, "current sender ignored roster challenge")
        proof = proofs[0]
        fields = proof.message.split(";")
        _, _, _, digest, nonce = challenge.message.split(";")
        check(len(fields) == 8 and fields[3] == digest and fields[5:7] == [nonce, receiver.guid],
              f"roster proof did not echo scope, challenge and receiver: {proof}")
        return proof

    def exchange(self, packet, receiver):
        """Deliver a data packet and carry its challenge and proof if required."""
        sender = next(client for client in (self.a, self.b) if packet.sender == client.name + "-TestRealm")
        self.deliver(packet, receiver)
        outgoing = self.drain(receiver)
        questions = [reply for reply in outgoing if reply.message.startswith("SYNC;3;Q;")]
        receiver.outbox.extend(reply for reply in outgoing if reply not in questions)
        if not questions:
            return []
        check(len(questions) == 1, "one data packet produced more than one challenge")
        question = questions[0]
        proofs = self.answer(question, sender)
        for proof in proofs:
            self.deliver(proof, receiver)
        return questions + proofs

    @staticmethod
    def opt_in(leader, caster):
        leader.api.buffers(False, True)
        caster.api.buffers(True, False)
        leader.action("on")
        caster.action("on")


def member_status(leader, caster):
    sent = leader.snapshot().sent
    for i in range(1, len(sent) + 1):
        if sent[i].name == caster.name + "-TestRealm":
            return sent[i].status


def publish_plan(party, leader, caster, scope_proved=False):
    leader.action("request")
    request = party.packet(leader, "COORD;1;REQ;")
    controls = party.exchange(request, caster)
    if scope_proved:
        check(not controls, "first request after roster proof required another challenge")
    return request, review_and_publish(party, leader, caster, request)


def review_and_publish(party, leader, caster, request):
    report = party.packet(caster, "COORD;1;REPORT;")
    request_id = request.body.split(";")[-1]
    check(report.body == f"COORD;1;REPORT;{request_id};{leader.guid};FORTITUDE",
          f"caster report did not bind learned Fortitude to leader request: {report}")
    party.exchange(report, leader)
    leader.action("publish")
    check(not party.capture(leader), "leader published before review")
    leader.action("review")
    reviewed = leader.snapshot()
    check(reviewed.canPublish and reviewed.draft and len(reviewed.draft) > 0,
          "review did not produce a publishable draft")
    leader.action("publish")
    plan = party.packet(leader, f"COORD;1;PLAN;{request_id};")
    check(plan.body.endswith(f";{caster.guid};FORTITUDE"), f"bad plan recipient or buffs: {plan}")
    check(member_status(leader, caster) == "sent", "leader did not await peer acknowledgement")
    check(not caster.snapshot().pending and not caster.api.holder("FORTITUDE"),
          "peer state changed before receiving PLAN")
    return plan


def accept_plan(party, leader, caster, plan):
    party.exchange(plan, caster)
    pending = caster.snapshot().pending
    revision = plan.body.split(";")[4]
    check(pending and pending.revision == revision and len(pending["keys"]) == 1
          and pending["keys"][1] == "FORTITUDE"
          and not pending.reviewed and not caster.api.holder("FORTITUDE"),
          "PLAN did not stage the exact unreviewed duty")
    caster.action("accept")
    check(not party.capture(caster) and not caster.api.holder("FORTITUDE"),
          "unreviewed PLAN activated a duty or sent ACK")
    caster.action("inbox")
    check(caster.snapshot().pending.reviewed and not party.capture(caster)
          and not caster.api.holder("FORTITUDE"), "inbox review incorrectly accepted the duty")
    caster.action("accept")
    ack = party.packet(caster, f"COORD;1;ACK;{revision}")
    check(ack.body == f"COORD;1;ACK;{revision}", "ACK did not identify the exact plan")
    check(not caster.snapshot().pending and caster.api.holder("FORTITUDE") == caster.name + "-TestRealm"
          and not caster.api.manualHolder("FORTITUDE"), "acceptance failed or changed manual assignment")
    check(member_status(leader, caster) == "sent", "leader acknowledged before ACK delivery")
    party.exchange(ack, leader)
    check(member_status(leader, caster) == "acknowledged", "leader did not observe delivered ACK")
    return ack


def coordination(stub, sources):
    party = Party(stub, sources)
    leader, caster = party.a, party.b
    leader.api.buffers(False, True)
    leader.action("on")
    leader.action("request")
    party.exchange(party.packet(leader, "COORD;1;REQ;"), caster)
    check(not party.capture(caster), "opted-out caster sent a report")
    print("PASS: opted-out caster ignores leader report request")
    party.update(leader, False, 1011)
    caster.api.buffers(True, False)
    caster.action("on")
    _, plan = publish_plan(party, leader, caster)
    ack = accept_plan(party, leader, caster, plan)
    print("PASS: request, report, reviewed publish, explicit acceptance, and ACK delivery")

    caster_token, leader_token = caster.snapshot().token, leader.snapshot().token
    party.deliver(plan, caster)
    party.deliver(ack, leader)
    check(not caster.snapshot().pending and caster.snapshot().token == caster_token
          and caster.api.holder("FORTITUDE") == caster.name + "-TestRealm"
          and leader.snapshot().token == leader_token and member_status(leader, caster) == "acknowledged"
          and not party.capture(caster) and not party.capture(leader), "duplicate PLAN or ACK changed state")
    print("PASS: duplicate PLAN and ACK do not reopen or modify accepted state")


def cast_sync(stub, sources):
    # A third group member is just a target; it does not run an addon client.
    party = Party(stub, sources, third=True)
    for client in (party.a, party.b):
        client.api.buffers(True, False)
    for index, (sender, receiver) in enumerate(((party.a, party.b), (party.b, party.a)), 1):
        # Advance beyond the previous handled window before testing the reverse direction.
        now = 1000 + 60 * index
        party.update(party.a, True, now)
        sender.api.refresh()
        receiver.api.refresh()
        check(receiver.api.row("party2") == (True, False), "receiver target initially missing or already handled")
        sender.api.cast("party2", f"Cast-1-{index}")
        packet = party.packet(sender, "CAST;")
        check(packet.body == "CAST;FORTITUDE;Player-1-0003", f"incorrect cast packet: {packet}")
        check(receiver.api.handledAt("Player-1-0003", "FORTITUDE") != now,
              "receiver already knew about cast before delivery")
        party.exchange(packet, receiver)
        check(receiver.api.handledAt("Player-1-0003", "FORTITUDE") == now,
              "receiver did not record synced Fortitude on the exact target")
        receiver.api.refresh()
        check(receiver.api.row("party2") == (True, True), "receiver did not mark the target as being buffed")
        party.update(party.a, True, now + 1)
        party.deliver(packet, receiver)
        check(receiver.api.handledAt("Player-1-0003", "FORTITUDE") == now
              and not party.capture(receiver), "duplicate CAST refreshed the handled timer")
        print(f"PASS: {sender.name} to {receiver.name} row cast publishes and marks the target handled")


def stale_cast(stub, sources, boundary):
    party = Party(stub, sources, third=True)
    sender, receiver = party.a, party.b
    for client in (sender, receiver):
        client.api.buffers(True, False)

    def mark():
        return receiver.api.handledAt("Player-1-0003", "FORTITUDE")

    def cast(label):
        sender.api.refresh()
        sender.api.cast("party2", "Cast-1-" + label)
        return party.packet(sender, "CAST;")

    old = cast("first")
    party.deliver(old, receiver)
    questions = party.capture(receiver)
    check(len(questions) == 1 and questions[0].message.startswith("SYNC;3;Q;") and mark() is None,
          "first CAST reached application state before proof")
    old_query = questions[0]
    party.deliver(old_query, sender)
    proofs = party.capture(sender)
    check(len(proofs) == 1 and proofs[0].message.startswith("SYNC;3;P;"), "scope proof was missing")
    old_proof = proofs[0]
    fields = old_proof.message.split(";")
    fields[5] = ("1" if fields[5][0] == "0" else "0") + fields[5][1:]
    party.deliver(replace(old_proof, message=";".join(fields)), receiver)
    check(mark() is None, "proof for a different challenge applied the cast")
    proof_base, floor = old_proof.message.rsplit(";", 1)
    check(floor == str(old.sequence), "proof did not carry the sender's current sequence")
    for bad in (proof_base, *(proof_base + ";" + value for value in ("", "01", "-1", "1.1", "10000000000"))):
        party.deliver(replace(old_proof, message=bad), receiver)
        check(mark() is None, f"missing or malformed proof floor applied the cast: {bad}")
    party.deliver(old_proof, receiver)
    check(mark() == 1000, "first CAST did not apply after scope proof")
    party.update(sender, True, 1000, "GROUP_ROSTER_UPDATE")
    check(mark() == 1000, "identical roster notification cleared a current cast")
    delayed = cast("delayed")
    if boundary == "leader":
        leader, fourth = receiver, False
        party.update(leader, True, 1001, "PARTY_LEADER_CHANGED")
    elif boundary == "roster":
        leader, fourth = sender, True
        party.update(leader, True, 1001, "GROUP_ROSTER_UPDATE", fourth=True)
    else:
        leader, fourth = sender, False
        party.update(leader, True, 1001, "GROUP_ROSTER_UPDATE", fourth=True, clients=(receiver,))
        party.update(leader, True, 1002, "GROUP_ROSTER_UPDATE", clients=(receiver,))
        challenge = party.roster_challenge(receiver)
        proof = party.roster_proof(challenge, sender, receiver)
        check(proof.message.endswith(f";{delayed.sequence}"),
              "known sender did not prove the current sequence in its unchanged epoch")
        party.deliver(proof, receiver)
    check(mark() is None, f"{boundary}: previously delivered cast survived a boundary")

    party.deliver(old_query, sender)
    party.capture(sender)  # A sender that missed the round trip can still echo an old query.
    party.deliver(old_proof, receiver)
    party.exchange(delayed, receiver)
    check(mark() is None and not party.capture(receiver),
          f"{boundary}: delayed CAST or scope proof revived a handled mark")
    party.update(leader, True, 1003, fourth=fourth)
    fresh = cast("fresh")
    controls = party.exchange(fresh, receiver)
    if boundary == "asymmetric roster round trip":
        check(not controls, "known sender's first new cast required a second challenge")
    check(mark() == 1003, f"{boundary}: fresh cast for the same player was lost")
    print(f"PASS: {boundary} clears cast marks and rejects delayed CAST and proof before fresh cast")


def unseen_epoch_after_round_trip(stub, sources):
    party = Party(stub, sources, third=True)
    sender, receiver = party.a, party.b
    sender.api.buffers(True, False)
    sender.api.refresh()
    sender.api.cast("party2", "Cast-1-unseen")
    delayed = party.packet(sender, "CAST;")
    party.update(sender, True, 1000, "GROUP_ROSTER_UPDATE", clients=(receiver,))
    party.update(sender, True, 1001, "GROUP_ROSTER_UPDATE", fourth=True)
    party.update(sender, True, 1002, "GROUP_ROSTER_UPDATE")
    sender_challenge = party.roster_challenge(sender)
    receiver_challenge = party.roster_challenge(receiver)
    check(not party.exchange(delayed, receiver), "roster challenge did not hold the unproved cast")
    party.deliver(party.roster_proof(sender_challenge, receiver, sender), sender)
    party.deliver(party.roster_proof(receiver_challenge, sender, receiver), receiver)
    check(receiver.api.handledAt("Player-1-0003", "FORTITUDE") is None,
          "proof of a new epoch applied a cast from a superseded epoch")
    sender.api.refresh()
    sender.api.cast("party2", "Cast-1-restored")
    check(not party.exchange(party.packet(sender, "CAST;"), receiver),
          "first cast in a restored roster required another challenge")
    check(receiver.api.handledAt("Player-1-0003", "FORTITUDE") == 1002,
          "an unproved old cast blocked the first fresh cast in the restored roster")
    print("PASS: roster proof rejects an unseen old epoch and preserves the first fresh cast")


def receiver_only_round_trip(stub, sources):
    party = Party(stub, sources, third=True)
    sender, caster = party.a, party.b
    party.opt_in(sender, caster)
    request, plan = publish_plan(party, sender, caster)
    sender.api.buffers(True, False)
    stale_packets = [request, plan]
    # Fill the eight-packet hold queue with real older traffic from this epoch.
    for i in range(6):
        sender.api.refresh()
        sender.api.cast("party2", f"Cast-1-before-round-trip-{i}")
        stale_packets.append(party.packet(sender, "CAST;"))
    old_cast = stale_packets[-1]
    check(0 < old_cast.sequence - plan.sequence < 32 and 0 < old_cast.sequence - request.sequence < 32,
          "the older packets must fall within the receive window")

    # Give the receiver a clean addon session. Its new runtime has never seen
    # this sender's epoch, and the sender does not observe the round trip.
    caster = party.b = Client(stub, sources, caster.name, caster.guid)
    party.update(sender, True, 1000, clients=(caster,))
    caster.api.start()
    party.capture(caster)
    party.update(sender, True, 1000, "GROUP_ROSTER_UPDATE", clients=(caster,))
    party.update(sender, True, 1001, "GROUP_ROSTER_UPDATE", fourth=True, clients=(caster,))
    party.update(sender, True, 1002, "GROUP_ROSTER_UPDATE", clients=(caster,))
    challenge = party.roster_challenge(caster)
    party.update(sender, True, 1002, "GROUP_ROSTER_UPDATE", clients=(caster,))
    check(not party.capture(caster), "identical roster event started another challenge")
    caster.api.buffers(True, False)
    caster.action("on")

    for packet in stale_packets:
        check(not party.exchange(packet, caster), "early data started a second challenge")
    check(not party.capture(caster) and not caster.snapshot().pending
          and caster.api.handledAt("Player-1-0003", "FORTITUDE") is None,
          "early data was applied before roster proof arrived")
    proof = party.roster_proof(challenge, sender, caster)
    check(proof.message.endswith(f";{old_cast.sequence}"),
          "sender that missed the boundary did not prove its unchanged epoch and sequence")
    # The sender has already answered B, but let the first new CAST overtake P.
    party.update(sender, True, 1003)
    sender.api.refresh()
    sender.api.cast("party1", "Cast-1-after-round-trip")
    fresh_cast = party.packet(sender, "CAST;")
    check(fresh_cast.message.split(";", 6)[4] == old_cast.message.split(";", 6)[4]
          and fresh_cast.sequence == old_cast.sequence + 1,
          "sender unexpectedly changed epoch or skipped the first sequence after proof")
    check(not party.exchange(fresh_cast, caster) and caster.api.handledAt(caster.guid, "FORTITUDE") is None,
          "reordered new cast started another proof or applied before proof")
    party.deliver(proof, caster)
    check(caster.api.handledAt(caster.guid, "FORTITUDE") == 1003,
          "reordered cast above the floor was lost")
    check(not party.capture(caster) and not caster.snapshot().pending
          and caster.api.handledAt("Player-1-0003", "FORTITUDE") is None,
          "proof restored the buffered REQ, PLAN or CAST at or below its floor")

    party.update(sender, True, 1004)
    check(not party.answer(challenge, sender), "duplicate roster challenge elicited another proof")
    party.deliver(proof, caster)
    for packet in (*stale_packets, fresh_cast):
        check(not party.exchange(packet, caster), "replayed data after proof started a new challenge")
    check(not party.capture(caster) and not caster.snapshot().pending
          and caster.api.handledAt("Player-1-0003", "FORTITUDE") is None
          and caster.api.handledAt(caster.guid, "FORTITUDE") == 1003,
          "duplicate proof reopened the receive window for stale or delivered data")

    party.update(sender, True, 1011)
    sender.api.buffers(False, True)
    _, fresh_plan = publish_plan(party, sender, caster, scope_proved=True)
    accept_plan(party, sender, caster, fresh_plan)
    print("PASS: roster proof preserves a reordered fresh CAST in a full queue and rejects stale replay")


def first_request_overtakes_roster_proof(stub, sources):
    party = Party(stub, sources)
    leader, caster = party.a, party.b
    party.opt_in(leader, caster)
    _, old_plan = publish_plan(party, leader, caster)
    accept_plan(party, leader, caster, old_plan)
    party.update(leader, True, 1010, "GROUP_ROSTER_UPDATE", clients=(caster,))
    party.update(leader, False, 1011, "GROUP_ROSTER_UPDATE", clients=(caster,))
    caster.action("on")
    challenge = party.roster_challenge(caster)
    proof = party.roster_proof(challenge, leader, caster)

    party.update(leader, False, 1012)
    leader.action("request")
    request = party.packet(leader, "COORD;1;REQ;")
    check(not party.exchange(request, caster) and not party.capture(caster),
          "first REQ after the sender replied to B started another challenge or reported before proof")
    party.deliver(proof, caster)
    fresh_plan = review_and_publish(party, leader, caster, request)
    accept_plan(party, leader, caster, fresh_plan)
    print("PASS: the first fresh REQ overtakes roster proof and completes the plan exchange without retry")


def return_receiver_to_roster(party, third=True):
    sender, receiver = party.a, party.b
    party.update(sender, third, 1000, "GROUP_ROSTER_UPDATE", clients=(receiver,))
    party.update(sender, True, 1001, "GROUP_ROSTER_UPDATE", fourth=third, clients=(receiver,))
    party.update(sender, third, 1002, "GROUP_ROSTER_UPDATE", clients=(receiver,))
    return party.roster_challenge(receiver)


def retry_roster_challenge(stub, sources, first_proof_wins):
    party = Party(stub, sources, third=True)
    sender, receiver = party.a, party.b
    sender.api.buffers(True, False)
    sender.action("on")
    sender.action("request")
    old_request = party.packet(sender, "COORD;1;REQ;")

    def cast(label):
        sender.api.refresh()
        sender.api.cast("party2", "Cast-1-" + label)
        return party.packet(sender, "CAST;")

    old_cast = cast("before-retry")
    first = return_receiver_to_roster(party)
    receiver.api.buffers(True, False)
    receiver.action("on")
    proof1 = party.roster_proof(first, sender, receiver)
    check(proof1.message.endswith(f";{old_cast.sequence}"), "first proof did not set the old floor")
    receiver.api.advance(1004.99)
    check(not party.capture(receiver), "warm-up retried before three seconds")
    receiver.api.advance(1005)
    second = party.roster_challenge(receiver)
    check(first.message.rsplit(";", 1)[0] == second.message.rsplit(";", 1)[0] and first != second,
          "retry must use the same roster and a fresh nonce")
    check(not party.capture(receiver), "retry sent application traffic before a proof")

    party.update(sender, True, 1005)
    between_cast = cast("between-proofs")
    proof2 = party.roster_proof(second, sender, receiver)
    check(proof2.message.endswith(f";{between_cast.sequence}") and between_cast.sequence > old_cast.sequence,
          "retry proof did not advance the sender's sequence floor")
    party.update(sender, True, 1006)
    for packet in (old_request, old_cast):
        check(not party.exchange(packet, receiver), "stale traffic during second grace started a targeted proof")
    first_delivered, late = (proof1, proof2) if first_proof_wins else (proof2, proof1)
    party.deliver(first_delivered, receiver)
    party.deliver(late, receiver)
    check(not party.capture(receiver) and receiver.api.handledAt("Player-1-0003", "FORTITUDE") is None,
          "retry proof replayed buffered CAST or REQ")

    for packet in (old_request, old_cast, between_cast):
        check(not party.exchange(packet, receiver), "already-proved sender triggered another challenge")
    expected = 1006 if first_proof_wins else None
    check(receiver.api.handledAt("Player-1-0003", "FORTITUDE") == expected and not party.capture(receiver),
          "alternate proof replaced the established floor or replayed old request")
    party.update(sender, True, 1007)
    check(not party.exchange(cast("after-both-proofs"), receiver)
          and receiver.api.handledAt("Player-1-0003", "FORTITUDE") == 1007,
          "first genuinely new cast after both proofs failed")
    receiver.api.advance(1009)
    check(not party.capture(receiver), "warm-up sent a third challenge")
    sender.api.buffers(False, True)
    party.update(sender, True, 1011)
    _, plan = publish_plan(party, sender, receiver, scope_proved=True)
    accept_plan(party, sender, receiver, plan)
    winner = "late first proof" if first_proof_wins else "retry proof"
    print(f"PASS: one idle retry establishes {winner} and ignores the alternate proof")


def cancelled_roster_retry(stub, sources, reason):
    party = Party(stub, sources, third=False)
    sender, receiver = party.a, party.b
    first = return_receiver_to_roster(party, third=False)
    if reason == "group left":
        party.update(sender, False, 1003, "GROUP_LEFT", clients=(receiver,), solo=True)
    elif reason == "roster changed":
        party.update(receiver, False, 1003, "PARTY_LEADER_CHANGED", clients=(receiver,))
    elif reason == "sync disabled":
        receiver.api.toggleSync()
        receiver.api.toggleSync()  # A canceled attempt stays canceled after re-enable.
    else:
        party.deliver(party.roster_proof(first, sender, receiver), receiver)
    receiver.api.advance(1006)
    check(not party.capture(receiver), f"warm-up retried after {reason}")
    print(f"PASS: no roster retry after {reason}")


def retry_without_native_timer(stub, sources):
    party = Party(stub, sources, third=False, with_timer=False)
    first = return_receiver_to_roster(party, third=False)
    receiver = party.b
    receiver.api.advance(1004)
    check(not party.capture(receiver), "fallback frame retried too early")
    receiver.api.advance(1005)
    second = party.roster_challenge(receiver)
    check(first != second, "fallback frame retry reused original challenge")
    receiver.api.advance(1009)
    check(not party.capture(receiver), "fallback frame sent more than one retry")
    print("PASS: existing frame update retries once without a native timer")


def expired_roster_challenge(stub, sources):
    party = Party(stub, sources, third=True)
    sender, receiver = party.a, party.b
    sender.api.buffers(True, False)
    sender.api.refresh()
    sender.api.cast("party2", "Cast-1-before-challenge")
    delayed = party.packet(sender, "CAST;")
    challenge = return_receiver_to_roster(party)
    late_proof = party.roster_proof(challenge, sender, receiver)
    receiver.api.advance(1005)
    retry = party.roster_challenge(receiver)
    party.update(sender, True, 1005)
    late_retry_proof = party.roster_proof(retry, sender, receiver)

    receiver.api.advance(1009)
    check(not party.capture(receiver), "an unanswered retry scheduled a third roster challenge")
    party.update(sender, True, 1009)
    party.deliver(late_proof, receiver)
    party.deliver(late_retry_proof, receiver)
    controls = party.exchange(delayed, receiver)
    check([packet.message.split(";", 3)[2] for packet in controls] == ["Q", "P"],
          "expired roster proof prevented a targeted fallback challenge")
    check(receiver.api.handledAt("Player-1-0003", "FORTITUDE") is None,
          "targeted proof after an expired roster challenge accepted stale data")
    party.update(sender, True, 1010)
    sender.api.refresh()
    sender.api.cast("party2", "Cast-1-after-targeted-proof")
    check(not party.exchange(party.packet(sender, "CAST;"), receiver)
          and receiver.api.handledAt("Player-1-0003", "FORTITUDE") == 1010,
          "fresh cast after targeted fallback failed to apply")
    print("PASS: expired roster proof falls back to targeted proof and keeps the replay floor")


def stale_messages(stub, sources, leader_changes=False):
    party = Party(stub, sources)
    leader, caster = party.a, party.b
    party.opt_in(leader, caster)
    request, plan = publish_plan(party, leader, caster)
    ack = accept_plan(party, leader, caster, plan)
    fresh_leader, fresh_caster = (caster, leader) if leader_changes else (leader, caster)
    label = "leader handoff with unchanged roster" if leader_changes else "roster change with unchanged leader"
    party.update(fresh_leader, not leader_changes, 1011,
                 "PARTY_LEADER_CHANGED" if leader_changes else "GROUP_ROSTER_UPDATE")
    check(not caster.api.holder("FORTITUDE"), f"{label}: event did not clear the accepted duty")
    check(not leader.snapshot().active and not caster.snapshot().active and not member_status(leader, caster),
          f"{label}: old session, accepted duty, or ACK survived")

    def replay_only(stage):
        tokens = (leader.snapshot().token, caster.snapshot().token)
        for packet, receiver in ((request, caster), (plan, caster), (ack, leader)):
            check(not party.exchange(packet, receiver), f"{label}, {stage}: old packet was challenged")
        check(tokens == (leader.snapshot().token, caster.snapshot().token)
              and not leader.snapshot().pending and not caster.snapshot().pending
              and not party.capture(leader) and not party.capture(caster),
              f"{label}, {stage}: stale packet changed state or sent a reply")

    replay_only("before re-opt-in")
    party.opt_in(fresh_leader, fresh_caster)
    replay_only("after re-opt-in")
    _, fresh_plan = publish_plan(party, fresh_leader, fresh_caster)
    check(fresh_plan.message != plan.message, f"{label}: new publication reused old plan identity")
    replay_only("after fresh publication")
    check(member_status(fresh_leader, fresh_caster) == "sent", f"{label}: stale ACK affected fresh outbox")
    accept_plan(party, fresh_leader, fresh_caster, fresh_plan)
    replay_only("after fresh acknowledgement")
    check(member_status(fresh_leader, fresh_caster) == "acknowledged"
          and fresh_caster.api.holder("FORTITUDE"), f"{label}: stale message cleared fresh acceptance")
    print(f"PASS: {label} clears duties and prevents delayed REQ, PLAN and ACK from changing state")


def legacy_packets(stub, sources):
    party = Party(stub, sources, third=True)
    party.opt_in(party.a, party.b)
    guid = party.b.guid
    party.a.action("request")
    scoped = party.packet(party.a, "COORD;1;REQ;")
    for message in ("COORD;1;REQ;1000.1", f"COORD;1;PLAN;1000.1;1000.2;{guid};FORTITUDE",
                    "CAST;FORTITUDE;Player-1-0003", scoped.message.replace("SYNC;3;", "SYNC;2;", 1)):
        party.deliver(Packet("Alia-TestRealm", "BuffRadar", message, "PARTY"), party.b)
    check(not party.capture(party.b) and not party.b.snapshot().pending
          and party.b.api.handledAt("Player-1-0003", "FORTITUDE") is None,
          "legacy unscoped coordination or cast was accepted in Forever")
    print("PASS: Forever ignores legacy unscoped and v2 coordination traffic")


def peer_status(stub, sources):
    party = Party(stub, sources)
    a, b = party.a, party.b
    party.opt_in(a, b)
    a.action("request")
    request = party.packet(a, "COORD;1;REQ;")
    party.deliver(request, b)
    questions = party.capture(b)
    check(len(questions) == 1 and questions[0].message.startswith("SYNC;3;Q;"), "missing proof challenge")
    check(b.api.peerSnapshot().counts.awaiting == 1, "pending proof not shown")
    for _ in range(2):
        b.api.peerSnapshot()
        b.api.readonlyCoordination()
        report = b.api.supportReport()
        check("Alia" not in report and "Bren" not in report and "sync.awaiting=1" in report,
              "support report leaked names or lost typed summary")
    check(not party.capture(b), "reading peer/support diagnostics sent traffic")
    for proof in party.answer(questions[0], a):
        party.deliver(proof, b)
    check(b.api.peerSnapshot().counts.verified == 1, "proof not shown as verified")
    party.capture(a)
    party.capture(b)
    party.update(a, True, 1001, "GROUP_ROSTER_UPDATE")
    party.capture(a)
    party.capture(b)
    party.update(a, False, 1002, "GROUP_ROSTER_UPDATE")
    party.capture(a)
    warm = party.roster_challenge(b)
    check(b.api.peerSnapshot().counts.awaiting == 1, "roster warmup status missing")
    b.api.advance(1005)
    party.capture(b)
    check(b.api.peerSnapshot().counts.retrying == 1, "automatic retry not shown")
    b.api.advance(1009)
    party.capture(b)
    check(b.api.peerSnapshot().counts.unverified == 1, "exhausted verification still pending")
    incompatible = replace(warm, sender=a.name + "-TestRealm", message=warm.message.replace("SYNC;3;", "SYNC;4;", 1))
    party.deliver(replace(incompatible, sender="Outsider-TestRealm"), b)
    party.deliver(replace(incompatible, channel="WHISPER"), b)
    party.deliver(replace(incompatible, message=incompatible.message.replace(";4;", ";garbage;", 1)), b)
    check(b.api.peerSnapshot().counts.incompatible == 0, "unauthenticated protocol observation affected status")
    party.deliver(incompatible, b)
    check(b.api.peerSnapshot().counts.incompatible == 1, "scoped incompatible protocol missing")
    party.capture(b)
    party.update(b, False, 1010, clients=(b,))  # Identity changed before its event arrives.
    check(b.api.peerSnapshot().counts.unverified == 1 and not b.api.readonlyCoordination().active,
          "unprocessed leader change retained trusted peer/session status")
    check(not party.capture(b), "stale identity read sent a challenge")
    party.update(b, False, 1011, "PARTY_LEADER_CHANGED", clients=(b,))
    check(b.api.peerSnapshot().counts.incompatible == 0, "scope change retained incompatible observation")
    print("PASS: peer diagnostics are pure, scoped, private, and distinguish proof/retry/timeout/protocol states")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stub", type=Path)
    parser.add_argument("addon", type=Path)
    args = parser.parse_args()
    stub = args.stub.read_text(encoding="utf-8-sig")
    sources = forever_sources(args.addon)
    coordination(stub, sources)
    cast_sync(stub, sources)
    stale_messages(stub, sources)
    stale_messages(stub, sources, leader_changes=True)
    for boundary in ("roster", "leader", "asymmetric roster round trip"):
        stale_cast(stub, sources, boundary)
    unseen_epoch_after_round_trip(stub, sources)
    receiver_only_round_trip(stub, sources)
    first_request_overtakes_roster_proof(stub, sources)
    for first_proof_wins in (True, False):
        retry_roster_challenge(stub, sources, first_proof_wins)
    for reason in ("group left", "roster changed", "sync disabled", "every peer proved"):
        cancelled_roster_retry(stub, sources, reason)
    retry_without_native_timer(stub, sources)
    expired_roster_challenge(stub, sources)
    legacy_packets(stub, sources)
    peer_status(stub, sources)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
