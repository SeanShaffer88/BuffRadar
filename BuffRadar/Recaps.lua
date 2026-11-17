-- BuffRadar - Recaps: death recap (1.9.0) and post-wipe report (1.9.0).
-- Split out of BuffRadar.lua (file split Slice D). Loaded after BuffRadar.lua;
-- talks to it only through the shared X table.
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, NS = ...
local X = NS and NS.X
if not X then return end

local Print, L = X.Print, X.L
local math_min = math.min

local READY_ROWS = 7
local READY_RETENTION = 15
local readyCheck, readyView, readyShow
local readyOffset = 0

local function ReadStatus(unit)
  if type(GetReadyCheckStatus) ~= "function" then return nil end
  local ok, status = pcall(GetReadyCheckStatus, unit)
  if ok and X.Readable(status) and type(status) == "string"
    and (status == "ready" or status == "notready" or status == "waiting") then return status end
end

local function FindMember(members, guid, full)
  if not guid and not full then return nil end
  local match
  for _, member in ipairs(members) do
    if guid and member.guid == guid then return member end
    if full and member.full == full and (not guid or not member.guid) then
      if match then return nil end
      match = member
    end
  end
  return match
end

local function BuffDetails(member)
  local parts = {}
  for _, name in ipairs(member.missing) do parts[#parts + 1] = string.format(L["%s missing"], name) end
  for _, buff in ipairs(member.expiring) do
    parts[#parts + 1] = string.format(L["%s expires in %ds"], buff.name, buff.seconds)
  end
  for _, name in ipairs(member.unavailable) do parts[#parts + 1] = string.format(L["%s unavailable"], name) end
  if member.unknown and #member.unavailable == 0 then parts[#parts + 1] = L["Buff coverage unavailable"] end
  if #parts == 0 then parts[1] = member.checked and L["Checked buffs present"] or L["No applicable buffs"] end
  return parts
end

local function ReadyDetails(member)
  if member.ignored then return L["Buffs ignored"] end
  return table.concat(BuffDetails(member), " · ")
end

local function ScrollReady(delta)
  if not readyCheck then return end
  readyOffset = math.max(0, math_min(readyOffset + delta, #readyCheck.members - READY_ROWS))
  X.RenderReadyCheck()
end

local function BuildReadyView()
  local f = CreateFrame("Frame", "BuffRadarReadyCheck", UIParent)
  f:SetSize(430, 350)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 85)
  f:SetClampedToScreen(true)
  f:SetFrameStrata("DIALOG")
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, delta) ScrollReady(delta > 0 and -1 or 1) end)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(f)
  bg:SetColorTexture(0.055, 0.065, 0.08, 0.96)
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 13, -12)
  title:SetPoint("TOPRIGHT", -34, -12)
  title:SetJustifyH("LEFT")
  title:SetText(L["BuffRadar Ready Check"])
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function() X.ReadyViewCommand("hide") end)
  f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.summary:SetPoint("TOPLEFT", 13, -37)
  f.summary:SetPoint("TOPRIGHT", -13, -37)
  f.summary:SetJustifyH("LEFT")
  local reagentLine = CreateFrame("Frame", nil, f)
  reagentLine:SetPoint("TOPLEFT", 13, -55)
  reagentLine:SetPoint("TOPRIGHT", -13, -55)
  reagentLine:SetHeight(16)
  reagentLine:EnableMouse(true)
  f.reagents = reagentLine:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.reagents:SetAllPoints(reagentLine)
  f.reagents:SetJustifyH("LEFT")
  f.reagents:SetWordWrap(false)
  reagentLine:SetScript("OnEnter", function(self)
    local snapshot = readyCheck
    if not snapshot or not snapshot.reagents then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(snapshot.reagents, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  reagentLine:SetScript("OnLeave", function() GameTooltip:Hide() end)
  reagentLine:SetScript("OnHide", function(self)
    if GameTooltip.GetOwner and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
  end)
  f.rows = {}
  for i = 1, READY_ROWS do
    local row = CreateFrame("Frame", nil, f)
    row:SetPoint("TOPLEFT", 13, -77 - (i - 1) * 33)
    row:SetPoint("TOPRIGHT", -13, -77 - (i - 1) * 33)
    row:SetHeight(32)
    row:EnableMouse(true)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta) ScrollReady(delta > 0 and -1 or 1) end)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.label:SetPoint("TOPLEFT")
    row.label:SetPoint("TOPRIGHT")
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.detail:SetPoint("TOPLEFT", 6, -15)
    row.detail:SetPoint("TOPRIGHT", -3, -15)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(self.label:GetText())
      GameTooltip:AddLine(self.detail:GetText(), 1, 1, 1, true)
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnHide", function(self)
      if GameTooltip.GetOwner and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)
    f.rows[i] = row
  end
  f.footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.footer:SetPoint("BOTTOMLEFT", 13, 8)
  f.snapshot = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.snapshot:SetPoint("BOTTOMLEFT", 13, 24)
  return f
end

function X.RaidPreparationSnapshot(personal)
  if not X.classic or not X.InGroup() or InCombatLockdown() or X.PlayerSuspended() then return end
  local report = X.GroupBuffReport(false, true, true)
  local reagents, incomplete = X.ReagentEstimate(report)
  local snapshot = { members = {}, reagents = reagents, incomplete = incomplete }
  local size = X.ReadUnitNumber(GetNumGroupMembers)
  if not size or #report.members ~= size then snapshot.incomplete = true end
  for _, member in ipairs(report.members) do
    local guid, name = member.guid, member.full
    if not guid then
      snapshot.incomplete = true
    elseif not member.ignored then
      local parts = BuffDetails(member)
      local attention = #member.missing > 0 or #member.expiring > 0
      local unknown = member.unknown or #member.unavailable > 0
      for _, def in ipairs(X.CONS_DEFS) do
        local has
        if member.observable then has = X.ConsHas(member.unit, def) end
        if has == false then
          parts[#parts + 1] = string.format(L["%s missing"], L[def.label])
          attention = true
        elseif has == nil then
          parts[#parts + 1] = string.format(L["%s unavailable"], L[def.label])
          unknown = true
        end
      end
      if not name or name == "" then
        name, unknown, snapshot.incomplete = L["Player details unavailable"], true, true
      end
      snapshot.members[#snapshot.members + 1] = { guid = guid, name = name, details = parts,
        status = attention and "attention" or (unknown and "unknown" or "clear"), unknown = not not unknown }
    end
  end
  if personal then
    local notices = {}
    if X.WeaponEnchantMissing() then notices[#notices + 1] = L["Temporary weapon coating missing"] end
    local ok, _, class = pcall(UnitClass, "player")
    if ok and X.Readable(class) and (class == "HUNTER" or class == "WARLOCK")
      and X.ReadUnitBool(UnitExists, "pet") == false then notices[#notices + 1] = L["No active pet"] end
    snapshot.personal = #notices > 0 and table.concat(notices, " · ") or L["No personal reminders"]
  end
  return snapshot
end

function X.RaidPreparationCommand(mode)
  if not X.classic then return end
  if mode == "hide" then X.CloseRaidPreparation(); return end
  if InCombatLockdown() or X.PlayerSuspended() then return end
  if mode == "next" or mode == "prev" then X.MoveRaidPreparation(mode == "next" and 1 or -1); return end
  if mode ~= "" and mode ~= "show" and mode ~= "personal" then
    Print(L["Use /br prep show, personal, hide, next, or prev."])
    return
  end
  if not X.InGroup() then Print(L["Join a party or raid to use Raid Preparation."]); return end
  X.OpenRaidPreparation(mode == "personal")
end

local READY_LABELS = { ready = "Ready", notready = "Not ready", waiting = "Waiting",
  unknown = "Unknown", unanswered = "No response" }

function X.RenderReadyCheck()
  if not readyShow or not readyCheck or X.PlayerSuspended() then
    if readyView then readyView:Hide() end
    return
  end
  readyView = readyView or BuildReadyView()
  local counts = { ready = 0, notready = 0, waiting = 0, unknown = 0, unanswered = 0 }
  for _, member in ipairs(readyCheck.members) do counts[member.status] = counts[member.status] + 1 end
  local middle = readyCheck.finished and string.format(L["No response %d"], counts.unanswered)
    or string.format(L["Waiting %d"], counts.waiting)
  readyView.summary:SetText(string.format(L["Ready %d · %s · Not ready %d · Unknown %d"],
    counts.ready, middle, counts.notready, counts.unknown))
  readyView.reagents:SetText(readyCheck.reagents or "")
  for i, row in ipairs(readyView.rows) do
    local member = readyCheck.members[readyOffset + i]
    if member then
      row.label:SetText(member.name .. " — " .. L[READY_LABELS[member.status]])
      row.detail:SetText(ReadyDetails(member))
    end
    row:SetShown(member ~= nil)
  end
  local total = #readyCheck.members
  readyView.footer:SetText(total > READY_ROWS and string.format(L["Players %d–%d of %d · Scroll or /br ready next"],
    readyOffset + 1, math_min(readyOffset + READY_ROWS, total), total) or "/br ready hide")
  readyView.snapshot:SetText(readyCheck.finished and L["Showing buff coverage at the end of the ready check."] or "")
  readyView:Show()
end

function X.ClearReadyCheck()
  readyCheck, readyOffset = nil, 0
  if readyView then readyView:Hide() end
end

function X.ExpireReadyCheck()
  if readyCheck and readyCheck.finished and GetTime() >= readyCheck.finished + READY_RETENTION then X.ClearReadyCheck() end
end

function X.ReadyViewCommand(mode)
  if mode == "hide" then
    readyShow = false
    X.RenderReadyCheck()
  elseif mode == "next" or mode == "prev" then
    ScrollReady(mode == "next" and 1 or -1)
  elseif mode == "" or mode == "show" then
    readyShow = true
    X.ExpireReadyCheck()
    if readyCheck then X.RenderReadyCheck()
    else Print(L["Ready-check details will open at the next ready check in your group."]) end
  else
    Print("Usage: /br ready [show|hide|next|prev]")
  end
end

function X.StartReadyCheck()
  X.ClearReadyCheck()
  if not X.InGroup() or X.PlayerSuspended() then return nil end
  local report = X.GroupBuffReport(false, true)
  for _, member in ipairs(report.members) do member.status = ReadStatus(member.unit) or "unknown" end
  readyCheck = { members = report.members, reagents = X.ReagentSummary and X.ReagentSummary(report) }
  X.RenderReadyCheck()
  return report
end

function X.ConfirmReadyCheck(unit, response)
  if not readyCheck or readyCheck.finished or not X.Readable(unit) or type(unit) ~= "string"
    or (not unit:match("^party[1-4]$") and not unit:match("^raid%d%d?$") and unit ~= "player") then return end
  if X.ReadUnitBool(UnitExists, unit) ~= true then return end
  local guid, full = X.ReadyIdentity(unit)
  local member = FindMember(readyCheck.members, guid, full)
  if not member then return end
  if X.Readable(response) and type(response) == "boolean" then
    member.status = response and "ready" or "notready"
  else
    member.status = ReadStatus(unit) or member.status
  end
  X.RenderReadyCheck()
end

function X.FinishReadyCheck(preempted)
  if not readyCheck or readyCheck.finished then return end
  if X.Readable(preempted) and preempted == true then X.ClearReadyCheck(); return end
  local report = X.GroupBuffReport(false, true)
  for _, member in ipairs(readyCheck.members) do
    if member.status == "waiting" then member.status = "unanswered" end
    local current = FindMember(report.members, member.guid, member.full)
    if current then
      member.missing, member.expiring, member.unavailable = current.missing, current.expiring, current.unavailable
      member.checked, member.unknown, member.ignored = current.checked, current.unknown, current.ignored
    else
      member.missing, member.expiring, member.unavailable = {}, {}, {}
      member.checked, member.unknown, member.ignored = nil, true, nil
    end
  end
  readyCheck.reagents = X.ReagentSummary and X.ReagentSummary(report)
  readyCheck.finished = GetTime()
  X.RenderReadyCheck()
end

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
  local combatStart = X.combatStart
  X.combatStart = nil
  if not combatStart or GetTime() - combatStart < 8 then return end
  local db = X.GetDB()
  if not db or not db.wipeReport or not X.InGroup() then return end
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
