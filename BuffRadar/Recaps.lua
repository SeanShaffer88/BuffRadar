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
  local lines, people, casts = X.SnapshotMissing(function(e)
    return (e.group or e.unit == "player") and not e.pet
  end)
  X.lastDeath = lines
  if not show then return end
  if people == 0 then
    Print("Death recap: nobody in your group was missing a buff when you died.")
  else
    Print(string.format("Death recap: %d %s missing buffs (%d casts) when you died:",
      people, people == 1 and "person is" or "people are", casts))
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
  local function scan(unit)
    if UnitExists(unit) then
      total = total + 1
      if X.ReadUnitBool(UnitIsDeadOrGhost, unit) == true then dead = dead + 1 end
    end
  end
  scan("player")
  if X.InRaid() then
    for i = 1, 40 do scan("raid" .. i) end
  else
    for i = 1, 4 do scan("party" .. i) end
  end
  if not (dead >= 3 or (total <= 5 and dead >= 2)) then return end
  local lines, people, casts = X.SnapshotMissing(function(e)
    return e.group and not e.pet
  end)
  X.lastWipe = lines
  Print(string.format("Wipe report: %d of %d died. %s", dead, total,
    people == 0 and "Everyone still standing is buffed."
      or string.format("%d %s missing buffs (%d casts):", people,
        people == 1 and "person is" or "people are", casts)))
  for i = 1, math_min(#lines, 12) do Print(lines[i]) end
  if #lines > 12 then Print(string.format("  +%d more", #lines - 12)) end
  if people > 0 and X.AmLead() then
    local channel = X.InRaid() and "RAID" or "PARTY"
    if _G.SendChatMessage then
      _G.SendChatMessage(string.format(
        "BuffRadar wipe report: %d of %d died; %d %s missing buffs (%d casts).",
        dead, total, people, people == 1 and "person is" or "people are", casts), channel)
    end
  end
end
