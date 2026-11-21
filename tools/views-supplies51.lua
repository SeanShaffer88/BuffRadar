-- Original read-only display and explicit purchase-boundary regressions.
return function(step, fresh)
  local function merchant(f)
    local c, db = f.client, f.db
    db.restockEnabled, db.restockTargets = true, { [17020] = 20 }
    db.restockSpendCap, db.restockUnitCap = 20000, 40
    c.__buys, c.__money, c.__carried, c.__price, c.__stock, c.__free = {}, 100000, 3, 100, -1, 10
    c.UnitGUID = function(unit) if unit == "npc" then return "Creature-0-123" end return "Player-1-1" end
    c.GetMerchantNumItems = function() return 1 end
    c.GetMerchantItemInfo = function() return "Arcane Powder", 1, c.__price, 5, c.__stock, true, true, false end
    c.GetMerchantItemLink = function() return "|Hitem:17020:0|h[Arcane Powder]|h" end
    c.GetMerchantItemMaxStack = function() return 20 end
    c.GetMoney = function() return c.__money end
    c.GetItemCount = function() return c.__carried end
    c.C_Item = { GetItemCount=c.GetItemCount, GetItemInfo=function() return "Powder", nil, nil, nil, nil, nil, nil, 20 end }
    c.C_Container = { GetContainerNumFreeSlots=function(bag) return bag == 0 and c.__free or 0, 0 end }
    c.BuyMerchantItem = function(index, quantity) c.__buys[#c.__buys + 1] = {index,quantity} end
    f.X.Supplies.OnEvent("MERCHANT_SHOW")
  end

  step("views: optional models are bounded, stable, copied and unknown remains unknown", function()
    local f = fresh({includeSelf=true,pauseInCities=false}, true)
    local X = f.X
    assert(X.Views and X.Supplies, "optional display and supplies modules must load")
    X.CoverageEvidence = function(scope)
      return {generation=3, buffs={{key="A",name="Alpha"},{key="B",name="Beta"}},
        members={{guid="Player-1",label="Player",subgroup=1,cells={A={state="confirmed"},B={state="unknown"}}}},
        incomplete=scope == "group",freshness={state="current"}}
    end
    local matrix = X.Views.MatrixModel()
    assert(matrix.rows[1].cells[2].state == "unknown")
    local self = X.Views.SelfModel()
    assert(self.slots[1].key == "A" and self.slots[2].key == "B")
    self.slots[1].state = "missing"
    assert(X.Views.SelfModel().slots[1].state == "confirmed")
    assert(not X.Views.GetMatrixFrame() and not X.Views.GetSelfFrame(), "model reads must not create UI")
  end)

  step("supplies: preview never buys, bundles round down, confirmation is one use", function()
    local f = fresh({}, true); merchant(f)
    local S, c = f.X.Supplies, f.client
    local draft = S.Preview()
    assert(#c.__buys == 0 and draft.rows[1].quantity == 15 and draft.rows[1].cost == 300)
    draft.rows[1].quantity = 200
    assert(S.Confirm(draft.id))
    assert(#c.__buys == 1 and c.__buys[1][2] == 15, "caller mutation cannot change consent")
    assert(not S.Confirm(draft.id) and #c.__buys == 1)
  end)

  step("supplies: stale quotes, merchant changes and combat never buy", function()
    local f = fresh({}, true); merchant(f)
    local S, c = f.X.Supplies, f.client
    local d = S.Preview(); c.__price = 200
    assert(not S.Confirm(d.id) and #c.__buys == 0)
    d = S.Preview(); S.OnEvent("MERCHANT_CLOSED"); S.OnEvent("MERCHANT_SHOW")
    assert(not S.Confirm(d.id) and #c.__buys == 0)
    d = S.Preview(); c.__combat = true
    assert(not S.Confirm(d.id) and #c.__buys == 0)
  end)

  step("supplies: unsupported cost, stock, bags, gold and caps fail closed", function()
    local f = fresh({}, true); merchant(f)
    local S, c, db = f.X.Supplies, f.client, f.db
    c.__money = 0; assert(#S.Preview().rows == 0)
    c.__money, c.__free = 100000, 0; assert(#S.Preview().rows == 0)
    c.__free, c.__stock = 10, 0; assert(#S.Preview().rows == 0)
    c.__stock, db.restockUnitCap = -1, 4; assert(#S.Preview().rows == 0)
    db.restockUnitCap, db.restockSpendCap = 40, 99; assert(#S.Preview().rows == 0)
    db.restockSpendCap = 20000
    c.GetMerchantItemInfo = function() return "Powder",1,100,5,-1,true,true,true end
    assert(#S.Preview().rows == 0 and #c.__buys == 0)
    assert(not S.SetTarget(999999, 20), "unrecognized reagents cannot be purchased")
    assert(not S.SetLimits(0/0, 20))
  end)

  step("supplies: settings and merchant events cannot buy", function()
    local f = fresh({}, true); merchant(f)
    local S, c = f.X.Supplies, f.client
    assert(S.SetEnabled(false)); assert(#S.Preview().rows == 0)
    assert(S.SetEnabled(true)); assert(S.SetTarget(17020, 20)); assert(S.SetLimits(500, 20))
    S.OnEvent("MERCHANT_UPDATE"); S.OnEvent("BAG_UPDATE_DELAYED"); S.OnEvent("PLAYER_MONEY")
    assert(#c.__buys == 0)
  end)

  step("supplies: future schemas cannot quote or purchase and preserve the original save",function()
    local f=fresh({dbVersion=900,restockEnabled=true,restockTargets={[17020]=20},restockSpendCap=20000,restockUnitCap=40},true)
    local saved=f.client.BuffRadarDB
    merchant(f)
    assert(f.X.Settings.SaveState()=="future")
    local quote=f.X.Supplies.Preview()
    assert(#quote.rows==0 and not f.X.Supplies.Confirm(quote.id) and #f.client.__buys==0)
    assert(f.client.BuffRadarDB==saved and saved.dbVersion==900)
    local normal=fresh({},true);merchant(normal)
    quote=normal.X.Supplies.Preview()
    normal.X.Settings.SaveState=function() return "future" end
    assert(not normal.X.Supplies.Confirm(quote.id) and #normal.client.__buys==0)
  end)

  step("supplies: exact current item, count, NPC and thrown purchase are revalidated", function()
    local f=fresh({},true);merchant(f)
    local S,c=f.X.Supplies,f.client
    local d=S.Preview();c.__carried=10;assert(not S.Confirm(d.id) and #c.__buys==0)
    d=S.Preview();c.UnitGUID=function() return "Creature-0-other" end
    assert(not S.Confirm(d.id) and #c.__buys==0)
    d=S.Preview();c.GetMerchantItemLink=function() return "item:17029" end
    assert(not S.Confirm(d.id) and #c.__buys==0)
    merchant(f);d=S.Preview();c.BuyMerchantItem=function() error("purchase failed") end
    assert(not S.Confirm(d.id) and not S.Confirm(d.id))
    c.GetMerchantItemInfo=function() return "Powder",1,0/0,5,-1,true,true,false end
    assert(#S.Preview().rows==0)
    c.GetMerchantItemInfo=nil;assert(#S.Preview().rows==0)
  end)

  step("views: real frames and merchant preview never cast or buy and release keyboard in combat",function()
    local f=fresh({},true);merchant(f)
    local X,c=f.X,f.client
    assert(X.Views.ShowMatrix());assert(X.Views.ToggleSelf());assert(X.Supplies.Show())
    local matrix,strip,supply=X.Views.GetMatrixFrame(),X.Views.GetSelfFrame(),X.Supplies.GetFrame()
    assert(matrix:IsShown() and strip:IsShown() and supply:IsShown() and #c.__buys==0)
    assert(not matrix.scripts.OnUpdate and not strip.scripts.OnUpdate and not supply.scripts.OnUpdate)
    c.__combat=true
    matrix.scripts.OnEvent(matrix,"PLAYER_REGEN_DISABLED");strip.scripts.OnEvent(strip,"PLAYER_REGEN_DISABLED")
    X.Supplies.OnEvent("PLAYER_REGEN_DISABLED")
    assert(not matrix:IsShown() and not strip:IsShown() and not supply:IsShown())
    assert(not matrix.keyboard and not strip.keyboard and not supply.keyboard and #c.__buys==0)
  end)
end
