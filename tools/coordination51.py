"""Run two isolated Forever addon clients over an explicit offline message bus."""

import argparse
from dataclasses import dataclass, replace
from pathlib import Path

from lupa import lua51


CLIENT = r"""function(name, guid)
  local chat = {}
  local env = WOWSTUB(chat, true, false, true, false)
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
    units.party1 = { other, otherGUID }
    units.party2 = third and { "Tara", "Player-1-0003" } or nil
    units.party3 = fourth and { "Wren", "Player-1-0004" } or nil
    leader, now = newLeader, clock
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
    for _ = 1, 8 do
      if #env.__timers == 0 then return end
      local timers = env.__timers
      env.__timers = {}
      for _, callback in ipairs(timers) do callback() end
    end
    assert(#env.__timers == 0, "timer drain did not settle")
  end
  local function rowFor(unit)
    for _, row in ipairs(ns.X.slashAPI.rows) do
      if row:IsShown() and row.entry and row.entry.unit == unit then return row end
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
    buffers = function(fortitude, spirit)
      local db = env.BuffRadarDB
      db.enabled.FORTITUDE, db.enabled.DIVINE_SPIRIT = fortitude, spirit
      ns.X.slashAPI.BuildBuffList()
    end,
    slash = function(command) env.SlashCmdList.BUFFRADAR("coordinate " .. command) end,
    snapshot = function() return ns.X.CoordinationSnapshot() end,
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
    def __init__(self, stub, sources, name, guid):
        self.name, self.guid = name, guid
        self.outbox = []
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(stub)
        self.api = self.lua.eval(CLIENT)(name, guid)
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
        check(parts[:3] == ["SYNC", "2", "D"] and len(parts) == 7,
              f"expected scoped data packet, got {self}")
        return parts[6]


class Party:
    def __init__(self, stub, sources, third=False):
        self.a = Client(stub, sources, "Alia", "Player-1-0001")
        self.b = Client(stub, sources, "Bren", "Player-1-0002")
        self.update(self.a, third, 1000)
        for client in (self.a, self.b):
            client.api.start()
            client.api.drain()

    def update(self, leader, third, clock, event=None, fourth=False, clients=None):
        clients = (self.a, self.b) if clients is None else clients
        for local, remote in ((self.a, self.b), (self.b, self.a)):
            if local in clients:
                local.api.configure(remote.name, remote.guid, third, leader.name, clock, fourth)
                if event:
                    local.api.fire(event)
                    local.api.drain()  # Ignore independent presence notifications.

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

    def exchange(self, packet, receiver):
        """Deliver a data packet and carry its challenge and proof if required."""
        sender = next(client for client in (self.a, self.b) if packet.sender == client.name + "-TestRealm")
        self.deliver(packet, receiver)
        outgoing = self.drain(receiver)
        questions = [reply for reply in outgoing if reply.message.startswith("SYNC;2;Q;")]
        receiver.outbox.extend(reply for reply in outgoing if reply not in questions)
        if not questions:
            return []
        check(len(questions) == 1, "one data packet produced more than one challenge")
        question = questions[0]
        self.deliver(question, sender)
        outgoing = self.drain(sender)
        proofs = [reply for reply in outgoing if reply.message.startswith("SYNC;2;P;")]
        sender.outbox.extend(reply for reply in outgoing if reply not in proofs)
        check(len(proofs) <= 1, "one challenge produced more than one proof")
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


def publish_plan(party, leader, caster):
    leader.action("request")
    request = party.packet(leader, "COORD;1;REQ;")
    party.exchange(request, caster)
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
    return request, plan


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
    check(len(questions) == 1 and questions[0].message.startswith("SYNC;2;Q;") and mark() is None,
          "first CAST reached application state before proof")
    old_query = questions[0]
    party.deliver(old_query, sender)
    proofs = party.capture(sender)
    check(len(proofs) == 1 and proofs[0].message.startswith("SYNC;2;P;"), "scope proof was missing")
    old_proof = proofs[0]
    fields = old_proof.message.split(";")
    fields[5] = ("1" if fields[5][0] == "0" else "0") + fields[5][1:]
    party.deliver(replace(old_proof, message=";".join(fields)), receiver)
    check(mark() is None, "proof for a different challenge applied the cast")
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
    check(mark() is None, f"{boundary}: previously delivered cast survived a boundary")

    party.deliver(old_query, sender)
    party.capture(sender)  # A sender that missed the round trip can still echo an old query.
    party.deliver(old_proof, receiver)
    party.exchange(delayed, receiver)
    check(mark() is None and not party.capture(receiver),
          f"{boundary}: delayed CAST or scope proof revived a handled mark")
    if boundary == "asymmetric roster round trip":
        party.update(leader, True, 1001, "GROUP_ROSTER_UPDATE", fourth=True, clients=(sender,))
        party.update(leader, True, 1002, "GROUP_ROSTER_UPDATE", clients=(sender,))

    party.update(leader, True, 1003, fourth=fourth)
    fresh = cast("fresh")
    party.exchange(fresh, receiver)
    check(mark() == 1003, f"{boundary}: fresh cast for the same player was lost")
    print(f"PASS: {boundary} clears cast marks and rejects delayed CAST and proof before fresh cast")


def unseen_epoch_after_round_trip(stub, sources):
    party = Party(stub, sources, third=True)
    sender, receiver = party.a, party.b
    sender.api.buffers(True, False)
    sender.api.refresh()
    sender.api.cast("party2", "Cast-1-unseen")
    delayed = party.packet(sender, "CAST;")
    party.update(sender, True, 1001, "GROUP_ROSTER_UPDATE", fourth=True)
    party.update(sender, True, 1002, "GROUP_ROSTER_UPDATE")

    controls = party.exchange(delayed, receiver)
    check(len(controls) == 1 and controls[0].message.startswith("SYNC;2;Q;"),
          "the sender vouched for a superseded epoch after the original roster returned")
    check(receiver.api.handledAt("Player-1-0003", "FORTITUDE") is None,
          "an unseen old cast was applied while its scope was unproved")
    sender.api.refresh()
    sender.api.cast("party2", "Cast-1-restored")
    party.exchange(party.packet(sender, "CAST;"), receiver)
    check(receiver.api.handledAt("Player-1-0003", "FORTITUDE") == 1002,
          "an unproved old cast blocked a fresh cast in the restored roster")
    print("PASS: restored roster rejects an unseen old cast and accepts fresh traffic")


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
    for message in ("COORD;1;REQ;1000.1", f"COORD;1;PLAN;1000.1;1000.2;{guid};FORTITUDE",
                    "CAST;FORTITUDE;Player-1-0003"):
        party.deliver(Packet("Alia-TestRealm", "BuffRadar", message, "PARTY"), party.b)
    check(not party.capture(party.b) and not party.b.snapshot().pending
          and party.b.api.handledAt("Player-1-0003", "FORTITUDE") is None,
          "legacy unscoped coordination or cast was accepted in Forever")
    print("PASS: Forever ignores legacy unscoped coordination and casts")


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
    legacy_packets(stub, sources)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
