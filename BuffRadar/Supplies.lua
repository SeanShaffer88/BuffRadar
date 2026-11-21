-- BuffRadar - opt-in, quote-bound reagent purchases. No automatic buying.
-- Copyright (C) 2026 Malikor. GPLv3 or later.
local _, ns = ...
local X, S = ns.X, {}
local L = X.L
X.Supplies = S
local session, sequence, opened, consent, listener, frame = 0, 0, false, nil, nil, nil
local supported = {}
for _, id in pairs(X.groupReagents) do supported[id] = true end

local function Number(v, lo, hi)
  return X.Readable(v) and type(v) == "number" and v == v and v >= lo and v <= hi and v == math.floor(v)
end
local function Call(fn, ...)
  if type(fn) ~= "function" then return end
  local function pack(...) return {n=select("#",...),...} end
  local result = pack(pcall(fn, ...))
  if not result[1] then return end
  local values={n=result.n-1}
  for i=2,result.n do values[i-1]=result[i] end
  return values
end
local function Copy(t)
  local result = {}
  for k, v in pairs(t) do result[k] = type(v) == "table" and Copy(v) or v end
  return result
end
local function ValidSettings(db)
  if not db or db.restockEnabled ~= true or type(db.restockTargets) ~= "table"
      or not Number(db.restockSpendCap, 0, 10000000) or not Number(db.restockUnitCap, 0, 200) then return end
  local count = 0
  for id, target in pairs(db.restockTargets) do
    if not Number(id,1,2000000) or not supported[id] or not Number(target, 0, 200) then return end
    count = count + 1
    if count > 16 then return end
  end
  return true
end
local function NPC()
  local value = Call(UnitGUID, "npc")
  value = value and value[1]
  if X.Readable(value) and type(value) == "string" and #value > 0 and #value <= 128 then return value end
end
local function FreeSlots()
  local fn = C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
  local count = 0
  for bag = 0, 4 do
    local r = Call(fn, bag)
    if not r or not Number(r[1], 0, 100) or not Number(r[2], 0, 1000000) then return end
    if r[2] == 0 then count = count + r[1] end
  end
  return count
end
local function Carried(id)
  local fn = C_Item and C_Item.GetItemCount or GetItemCount
  local r = Call(fn, id, false, false, false, false)
  return r and Number(r[1], 0, 1000000) and r[1] or nil
end
local function Stack(id)
  local fn = C_Item and C_Item.GetItemInfo or GetItemInfo
  local r = Call(fn, id)
  return r and Number(r[8], 1, 10000) and r[8] or nil
end
local function Item(index)
  local r, link = Call(GetMerchantItemInfo, index), Call(GetMerchantItemLink, index)
  local limit = Call(GetMerchantItemMaxStack, index)
  if not r or not link or not X.Readable(link[1]) or type(link[1]) ~= "string" then return end
  if (type(r[8])~="nil" and not X.Readable(r[8])) or (type(r[9])~="nil" and not X.Readable(r[9])) then return end
  local id = tonumber(link[1]:match("item:(%d+)"))
  if not supported[id] or not X.Readable(r[1]) or type(r[1]) ~= "string" or #r[1] > 200
      or not Number(r[3], 1, 10000000) or not Number(r[4], 1, 200)
      or not Number(r[5], -1, 1000000) or not limit or not Number(limit[1], 1, 10000) then return end
  -- Classic's modern tuple has purchasable, usable, extendedCost in 6..8.
  -- The legacy tuple has usable, extendedCost in 6..7. Reject ambiguity.
  local modern = X.Readable(r[6]) and X.Readable(r[7]) and X.Readable(r[8])
    and type(r[6]) == "boolean" and type(r[7]) == "boolean" and type(r[8]) == "boolean"
  local legacy = r.n == 7 and type(r[8]) == "nil" and X.Readable(r[6]) and X.Readable(r[7])
    and type(r[6]) == "boolean" and type(r[7]) == "boolean"
  if modern then
    if not r[6] or r[8] or r[9] ~= nil then return end
  elseif legacy then
    if not r[6] or r[7] then return end
  else return end
  return {index=index,id=id,name=r[1],price=r[3],bundle=r[4],stock=r[5],limit=limit[1]}
end
local function Quote()
  local db = X.GetDB()
  local quote = {rows={},session=session,reason="Restock data is unavailable."}
  if X.Settings.SaveState()=="future" then return quote end
  if not db or db.restockEnabled ~= true then quote.reason="Restock previews are off."; return quote end
  if InCombatLockdown() or X.PlayerSuspended() then
    quote.reason="Restock requires an out-of-combat merchant visit."; return quote
  end
  if not opened then quote.reason="Open a merchant to preview restocking."; return quote end
  if not ValidSettings(db) then return quote end
  local npc, slots, money, total = NPC(), FreeSlots(), Call(GetMoney), Call(GetMerchantNumItems)
  if not npc or not slots or not money or not Number(money[1], 0, 100000000000)
      or not total or not Number(total[1], 0, 1000) or type(BuyMerchantItem) ~= "function" then return quote end
  quote.npc, quote.slots, quote.money = npc, slots, money[1]
  quote.spendCap, quote.unitCap, quote.targets = db.restockSpendCap, db.restockUnitCap, Copy(db.restockTargets)
  for index = 1, total[1] do
    local item = Item(index)
    if item and db.restockTargets[item.id] and #quote.rows < 16 then
      local target, carried, stack = db.restockTargets[item.id], Carried(item.id), Stack(item.id)
      if carried and stack then
        local need = math.max(0, target - carried)
        local units = math.min(need, db.restockUnitCap, item.limit, slots * stack)
        if item.stock >= 0 then units = math.min(units, item.stock) end
        units = math.min(units, math.floor(math.min(money[1], db.restockSpendCap) / item.price) * item.bundle)
        units = math.floor(units / item.bundle) * item.bundle
        if units > 0 then
          item.quantity, item.cost, item.target, item.carried, item.stack = units,
            (units / item.bundle) * item.price, target, carried, stack
          quote.rows[#quote.rows + 1] = item
        end
      end
    end
  end
  quote.reason = #quote.rows > 0 and "Review the next purchase. Nothing is bought until you confirm."
    or "No restock targets need a purchase."
  return quote
end
local function Same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for key, value in pairs(a) do if not Same(value, b[key]) then return false end end
  for key in pairs(b) do if a[key] == nil then return false end end
  return true
end

function S.Preview()
  sequence, consent = sequence + 1, nil
  local quote = Quote()
  quote.id = sequence
  if #quote.rows > 0 then consent = Copy(quote) end
  return quote
end
function S.Confirm(id)
  local approved = consent
  consent = nil -- consume before any API call, including failures/reentrancy
  if X.Settings.SaveState()=="future" then return false, L["Purchase quote changed. Refresh the preview."] end
  if not approved or id ~= approved.id then return false, L["Purchase quote changed. Refresh the preview."] end
  local current = Quote()
  current.id = id
  if not Same(approved, current) then return false, L["Purchase quote changed. Refresh the preview."] end
  local item = approved.rows[1]
  -- One row per explicit confirmation avoids inferring async purchase outcomes.
  local ok = pcall(BuyMerchantItem, item.index, item.quantity)
  if not ok then return false, L["Purchase could not be requested."] end
  return true, L["Purchase request sent. Check your bags before reviewing again."]
end
function S.OnEvent(event)
  if event == "MERCHANT_SHOW" then session, opened = session + 1, true
  elseif event == "MERCHANT_CLOSED" then session, opened = session + 1, false end
  consent = nil
  if frame and frame:IsShown() then
    frame.confirm:Disable()
    frame.hint:SetText(L["Purchase quote changed. Refresh the preview."])
    if event == "PLAYER_REGEN_DISABLED" then frame:Hide() end
  end
end
local function Listen()
  if listener then return end
  listener = CreateFrame("Frame")
  for _, event in ipairs({"MERCHANT_SHOW","MERCHANT_CLOSED","MERCHANT_UPDATE","MERCHANT_FILTER_ITEM_UPDATE",
      "BAG_UPDATE_DELAYED","PLAYER_MONEY","PLAYER_REGEN_DISABLED","PLAYER_DEAD"}) do listener:RegisterEvent(event) end
  listener:SetScript("OnEvent", function(_, event) S.OnEvent(event) end)
  if MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown() and not opened then S.OnEvent("MERCHANT_SHOW") end
end
function S.SetEnabled(value)
  if type(value) ~= "boolean" or InCombatLockdown() or not X.GetDB() or X.Settings.SaveState()=="future" then return false end
  X.SetPreference("restockEnabled", value)
  if X.GetDB().restockEnabled ~= value then return false end
  consent = nil; Listen(); return true
end
function S.SetTarget(id, target)
  local db = X.GetDB()
  if not db or X.Settings.SaveState()=="future" or InCombatLockdown() or not Number(id,1,2000000)
      or not supported[id] or not Number(target, 0, 200) then return false end
  local targets, n = {}, 0
  for key, value in pairs(db.restockTargets or {}) do targets[key], n = value, n + 1 end
  if target > 0 and targets[id] == nil and n >= 16 then return false end
  targets[id] = target > 0 and target or nil
  db.restockTargets, consent = targets, nil
  return true
end
function S.SetLimits(copper, units)
  local db = X.GetDB()
  if not db or X.Settings.SaveState()=="future" or InCombatLockdown() or not Number(copper,0,10000000) or not Number(units,0,200) then return false end
  db.restockSpendCap, db.restockUnitCap, consent = copper, units, nil
  return true
end
local function Create()
  frame = X.PanelWidget("Frame", "BuffRadarSupplies", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(500,580); frame:SetPoint("CENTER"); frame:SetClampedToScreen(true)
  frame:SetMovable(true);frame:EnableMouse(true);frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart",function(self) if not InCombatLockdown() then self:StartMoving() end end)
  if X.BindPanelPosition then X.BindPanelPosition(frame,"supplies",0) end
  if frame.SetBackdrop then
    frame:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=12})
    frame:SetBackdropColor(.04,.05,.09,.98)
  end
  local function text(y,h)
    local t=frame:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    t:SetPoint("TOPLEFT",18,y);t:SetWidth(464);t:SetHeight(h);t:SetJustifyH("LEFT");t:SetWordWrap(true)
    return t
  end
  text(-18,24):SetText(L["Supplies"])
  frame.hint=text(-48,60);frame.body=text(-112,160)
  text(-280,34):SetText(L["Reagent restocking uses empty general bag slots conservatively."])
  local controls={}
  local function button(label,x,y,w,action)
    local b=X.PanelWidget("Button",nil,frame,"UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT",x,y);b:SetSize(w,26);b:SetText(L[label]);b:SetScript("OnClick",action)
    controls[#controls+1]=b;return b
  end
  local function input(label,x,y)
    local t=text(y,18);t:ClearAllPoints();t:SetPoint("TOPLEFT",x,y);t:SetWidth(215);t:SetText(L[label])
    local e=X.PanelWidget("EditBox",nil,frame,"InputBoxTemplate")
    e:SetPoint("TOPLEFT",x,y-22);e:SetSize(210,24);e:SetAutoFocus(false);e:SetMaxLetters(10)
    controls[#controls+1]=e;return e
  end
  frame.item=input("Item ID",22,-323);frame.target=input("Target Quantity",264,-323)
  button("Set Target",22,-375,210,function()
    if not S.SetTarget(tonumber(frame.item:GetText()),tonumber(frame.target:GetText())) then
      frame.hint:SetText(L["Restock targets are limited to supported reagents."])
    else S.Show() end
  end)
  button("Enable Restock Previews",264,-375,210,function() S.SetEnabled(not X.GetDB().restockEnabled);S.Show() end)
  frame.spend=input("Spend Cap (Copper)",22,-410);frame.units=input("Item Cap",264,-410)
  button("Save Limits",22,-462,210,function()
    if not S.SetLimits(tonumber(frame.spend:GetText()),tonumber(frame.units:GetText())) then
      frame.hint:SetText(L["Restock settings are invalid."])
    else S.Show() end
  end)
  button("Refresh Preview",264,-462,210,S.Show)
  frame.confirm=button("Confirm Next Purchase",22,-502,452,function()
    local _, message=S.Confirm(frame.draftID);frame.confirm:Disable();frame.hint:SetText(message)
  end)
  button("Close",22,-538,452,function() frame:Hide() end)
  local focus=0
  frame:SetScript("OnKeyDown",function(self,key)
    if InCombatLockdown() then return end
    if key=="ESCAPE" then self:Hide()
    elseif key=="TAB" then
      if controls[focus] then controls[focus]:UnlockHighlight() end
      focus=focus % #controls+1;controls[focus]:LockHighlight()
      if controls[focus].SetFocus and controls[focus]:GetObjectType()=="EditBox" then controls[focus]:SetFocus() end
    elseif (key=="ENTER" or key=="SPACE") and focus>0 and controls[focus]:GetObjectType()~="EditBox" then controls[focus]:Click()
    else self:SetPropagateKeyboardInput(true);return end
    self:SetPropagateKeyboardInput(false)
  end)
  frame:SetScript("OnHide",function(self) consent=nil;self:EnableKeyboard(false) end)
end
function S.Show()
  if InCombatLockdown() or X.PlayerSuspended() then return false end
  Listen();if not frame then Create() end
  local draft=S.Preview();frame.draftID=draft.id
  local lines={}
  for i=1,math.min(4,#draft.rows) do
    local row=draft.rows[i]
    lines[#lines+1]=(i==1 and "> " or "")..string.format(L["%s: carried %d / target %d · buy %d · %d copper"],row.name,row.carried,row.target,row.quantity,row.cost)
  end
  local db=X.GetDB()
  if db then
    lines[#lines+1]=string.format(L["Restock limits: %d copper · %d items"],db.restockSpendCap,db.restockUnitCap)
    frame.spend:SetText(tostring(db.restockSpendCap));frame.units:SetText(tostring(db.restockUnitCap))
  end
  frame.hint:SetText(L[draft.reason]);frame.body:SetText(table.concat(lines,"\n\n"))
  if #draft.rows>0 then frame.confirm:Enable() else frame.confirm:Disable() end
  frame:EnableKeyboard(true);frame:Show();return true
end
function S.GetFrame() return frame end
