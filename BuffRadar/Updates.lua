-- Account-wide, event-driven update notices. UI is supplied by the host.
-- Copyright (C) 2026 Malikor. GPLv3 or later.
local _, ns = ...
local X=ns.X
local U={}
X.Updates=U
local items={"Search settings and actions without memorizing commands.",
  "Check peer verification and copy a private support report.",
  "Preview themes before applying or cancelling changes."}
function U.Model()
  return {version=X.Recovery.Version(),contentRevision=1,items={items[1],items[2],items[3]}}
end
function U.Pending()
  local db=X.GetDB()
  local version=X.Recovery.Version()
  return db~=nil and X.Settings.SaveState()==nil and version~=nil and db.updatesPendingVersion==version
    and db.updatesDismissedVersion~=version or false
end
function U.Dismiss()
  local db,version=X.GetDB(),X.Recovery.Version()
  if not db or not version or X.Settings.SaveState() or InCombatLockdown() or X.PlayerSuspended() then return false end
  db.updatesDismissedVersion=version
  if db.updatesPendingVersion==version then db.updatesPendingVersion="" end
  return true
end
function U.Show(manual)
  if not manual and not U.Pending() then return false end
  if not X.GetDB() or X.Settings.SaveState() or InCombatLockdown() or X.PlayerSuspended()
    or (X.UpdatesBlocked and X.UpdatesBlocked()) or type(X.ShowUpdates)~="function" then return false end
  return X.ShowUpdates(U.Model())==true
end
