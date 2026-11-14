-- BuffRadar - Recaps: death recap (1.9.0) and post-wipe report (1.9.0).
-- Split out of BuffRadar.lua (file split Slice D). Loaded after BuffRadar.lua;
-- talks to it only through the shared X table.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, NS = ...
local X = NS and NS.X
if not X then return end

local Print = X.Print
local math_min = math.min

-- Death recap: when you die, snapshot who was missing what -- the rebuff
-- list for after the rez. Always recorded; printed at death when the
-- setting is on. /br death reprints the last one.
function X.DeathRecap(show)
  local report = X.GroupBuffReport(true)
  local lines, people = X.SnapshotMissing(report), #report.people
  local note = X.GroupCoverageNote(report)
  if note then lines[#lines + 1] = note end
  X.lastDeath = lines
  if not show then return end
  if people == 0 then
    Print("Death recap: " .. (note or "all checked buffs were present."))
  else
    Print(string.format("Death recap: %d %s missing buffs (%d buffs needed) when you died:",
      people, people == 1 and "person was" or "people were", report.buffs))
    for i = 1, math_min(#lines, 12) do Print(lines[i]) end
    if #lines > 12 then Print(string.format("  +%d more", #lines - 12)) end
  end
end

-- Post-wipe report: when a real fight (8+ seconds) ends with several group
-- members dead, that's a wipe -- print who still needs buffs (the run-back
-- rebuff list) and, as leader or assistant, post a one-line summary to
-- group chat, like the ready-check auto-post.
function X.WipeCheck()
  local db = X.GetDB()
  if not db or not db.wipeReport or not X.InGroup() then return end
  if X.combatStart and GetTime() - X.combatStart < 8 then return end
  local total, dead = 0, 0
  local unavailable = 0
  X.ForReportRoster(function(unit, exists)
    local state = exists and X.ReadUnitBool(UnitIsDeadOrGhost, unit)
    total = total + 1
    if state == true then dead = dead + 1
    elseif state == nil then unavailable = unavailable + 1 end
  end)
  if not (dead >= 3 or (total <= 5 and dead >= 2)) then return end
  local report = X.GroupBuffReport(true)
  local lines, people = X.SnapshotMissing(report), #report.people
  local note = X.GroupCoverageNote(report)
  if note then lines[#lines + 1] = note end
  if unavailable > 0 then
    lines[#lines + 1] = string.format("Death status could not be verified for %d %s.",
      unavailable, unavailable == 1 and "player" or "players")
  end
  X.lastWipe = lines
  Print(string.format("Wipe report: %d of %d died. %s", dead, total,
    people == 0 and (note or "All checked buffs are present.")
      or string.format("%d %s missing buffs (%d buffs needed):", people,
        people == 1 and "person is" or "people are", report.buffs)))
  local first = people == 0 and note and 2 or 1
  for i = first, math_min(#lines, 12) do Print(lines[i]) end
  if #lines > 12 then Print(string.format("  +%d more", #lines - 12)) end
  if people > 0 and X.AmLead() then
    X.SendGroupReport(string.format(
      "BuffRadar wipe report: %d of %d died. %d %s missing buffs (%d buffs needed).%s",
      dead, total, people, people == 1 and "person is" or "people are", report.buffs,
      note and (" " .. note) or ""))
  end
end
