"""Run two isolated Forever addon clients over an explicit offline message bus."""

import argparse
from dataclasses import dataclass
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
  local function configure(other, otherGUID, third, newLeader, clock)
    units.party1 = { other, otherGUID }
    units.party2 = third and { "Tara", "Player-1-0003" } or nil
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
    if unit == "party2" then return "Warrior", "WARRIOR" end
    if units[unit] then return "Priest", "PRIEST" end
  end
  env.IsInGroup = function() return units.party1 ~= nil end
  env.GetNumGroupMembers = function() return units.party2 and 3 or units.party1 and 2 or 0 end
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


class Party:
    def __init__(self, stub, sources, third=False):
        self.a = Client(stub, sources, "Alia", "Player-1-0001")
        self.b = Client(stub, sources, "Bren", "Player-1-0002")
        self.update(self.a, third, 1000)
        for client in (self.a, self.b):
            client.api.start()
            client.api.drain()

    def update(self, leader, third, clock, event=None):
        for local, remote in ((self.a, self.b), (self.b, self.a)):
            local.api.configure(remote.name, remote.guid, third, leader.name, clock)
        if event:
            for client in (self.a, self.b):
                client.api.fire(event)
                client.api.drain()  # Ignore independent presence notifications.

    @staticmethod
    def capture(client):
        sent = client.api.drain()
        return [Packet(client.name + "-TestRealm", msg.prefix, msg.msg, msg.channel)
                for msg in (sent[i] for i in range(1, len(sent) + 1))]

    def packet(self, client, start):
        packets = self.capture(client)
        check(len(packets) == 1 and packets[0].message.startswith(start),
              f"{client.name} should send exactly one {start} packet, got {packets}")
        packet = packets[0]
        check((packet.prefix, packet.channel) == ("BuffRadar", "PARTY"),
              f"bad packet envelope: {packet}")
        return packet

    @staticmethod
    def deliver(packet, client):
        client.api.fire("CHAT_MSG_ADDON", packet.prefix, packet.message, packet.channel, packet.sender)

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
    party.deliver(request, caster)
    report = party.packet(caster, "COORD;1;REPORT;")
    request_id = request.message.split(";")[-1]
    check(report.message == f"COORD;1;REPORT;{request_id};{leader.guid};FORTITUDE",
          f"caster report did not bind learned Fortitude to leader request: {report}")
    party.deliver(report, leader)
    leader.action("publish")
    check(not party.capture(leader), "leader published before review")
    leader.action("review")
    reviewed = leader.snapshot()
    check(reviewed.canPublish and reviewed.draft and len(reviewed.draft) > 0,
          "review did not produce a publishable draft")
    leader.action("publish")
    plan = party.packet(leader, f"COORD;1;PLAN;{request_id};")
    check(plan.message.endswith(f";{caster.guid};FORTITUDE"), f"bad plan recipient or buffs: {plan}")
    check(member_status(leader, caster) == "sent", "leader did not await peer acknowledgement")
    check(not caster.snapshot().pending and not caster.api.holder("FORTITUDE"),
          "peer state changed before receiving PLAN")
    return request, plan


def accept_plan(party, leader, caster, plan):
    party.deliver(plan, caster)
    pending = caster.snapshot().pending
    revision = plan.message.split(";")[4]
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
    check(ack.message == f"COORD;1;ACK;{revision}", "ACK did not identify the exact plan")
    check(not caster.snapshot().pending and caster.api.holder("FORTITUDE") == caster.name + "-TestRealm"
          and not caster.api.manualHolder("FORTITUDE"), "acceptance failed or changed manual assignment")
    check(member_status(leader, caster) == "sent", "leader acknowledged before ACK delivery")
    party.deliver(ack, leader)
    check(member_status(leader, caster) == "acknowledged", "leader did not observe delivered ACK")
    return ack


def coordination(stub, sources):
    party = Party(stub, sources)
    leader, caster = party.a, party.b
    leader.api.buffers(False, True)
    leader.action("on")
    leader.action("request")
    party.deliver(party.packet(leader, "COORD;1;REQ;"), caster)
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
        check(packet.message == "CAST;FORTITUDE;Player-1-0003", f"incorrect cast packet: {packet}")
        check(receiver.api.handledAt("Player-1-0003", "FORTITUDE") != now,
              "receiver already knew about cast before delivery")
        party.deliver(packet, receiver)
        check(receiver.api.handledAt("Player-1-0003", "FORTITUDE") == now,
              "receiver did not record synced Fortitude on the exact target")
        receiver.api.refresh()
        check(receiver.api.row("party2") == (True, True), "receiver did not mark the target as being buffed")
        print(f"PASS: {sender.name} to {receiver.name} row cast publishes and marks the target handled")


def stale_messages(stub, sources, leader_changes=False, probe=False):
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
        party.deliver(plan, caster)
        party.deliver(ack, leader)
        check(tokens == (leader.snapshot().token, caster.snapshot().token)
              and not leader.snapshot().pending and not caster.snapshot().pending
              and not party.capture(leader) and not party.capture(caster),
              f"{label}, {stage}: stale packet changed state or sent a reply")

    replay_only("before re-opt-in")
    party.opt_in(fresh_leader, fresh_caster)
    replay_only("after re-opt-in")
    if probe:
        party.deliver(request, caster)
        # REPORT may also be rejected if a future protocol revision binds REQ to the new party.
        party.capture(caster)
        party.deliver(plan, caster)
        if caster.snapshot().pending:
            print("REPRODUCED: full old REQ then PLAN reopened a pending duty after roster change and re-opt-in")
            return 1
        print("PASS: full old REQ then PLAN did not reopen a pending duty")
        return 0
    _, fresh_plan = publish_plan(party, fresh_leader, fresh_caster)
    check(fresh_plan.message != plan.message, f"{label}: new publication reused old plan identity")
    replay_only("after fresh publication")
    check(member_status(fresh_leader, fresh_caster) == "sent", f"{label}: stale ACK affected fresh outbox")
    accept_plan(party, fresh_leader, fresh_caster, fresh_plan)
    replay_only("after fresh acknowledgement")
    check(member_status(fresh_leader, fresh_caster) == "acknowledged"
          and fresh_caster.api.holder("FORTITUDE"), f"{label}: stale message cleared fresh acceptance")
    print(f"PASS: {label} clears duties; delayed PLAN and ACK cannot reopen or alter old or fresh state")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stub", type=Path)
    parser.add_argument("addon", type=Path)
    parser.add_argument("--probe-full-replay", action="store_true",
                        help="check full old request/plan replay after re-opt-in; exit 1 if reproduced")
    args = parser.parse_args()
    stub = args.stub.read_text(encoding="utf-8-sig")
    sources = forever_sources(args.addon)
    if args.probe_full_replay:
        return stale_messages(stub, sources, probe=True)
    coordination(stub, sources)
    cast_sync(stub, sources)
    stale_messages(stub, sources)
    stale_messages(stub, sources, leader_changes=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
