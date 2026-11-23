"""Exercise real Forever startup across independent Lua states and durable saves.

Only SavedVariables and modeled game macros/bindings/action slots cross a relog.
This is an offline native-API adapter, not execution of secure game actions.
"""

import argparse
from copy import deepcopy
from pathlib import Path
import xml.etree.ElementTree as ET

from lupa import lua51
from lupa.lua51 import lua_type


CLIENT = r'''function(withTimer, other, otherGUID, covered, loaded, newline)
  local env = WOWSTUB({}, withTimer, false, true, false)
  local std = {string=string, table=table, math=math, pairs=pairs, ipairs=ipairs,
    next=next, type=type, select=select, pcall=pcall, tostring=tostring,
    tonumber=tonumber, error=error, setmetatable=setmetatable,
    getmetatable=getmetatable, rawget=rawget, rawset=rawset, unpack=unpack,
    strlower=string.lower, format=string.format, os=os}
  setmetatable(env, {__index=std}); env._G=env
  local ns, driver, timers, now = {}, nil, {}, 1000
  local units = {player={"Healer", "Player-1-Self"}}
  if other then units.party1={other, otherGUID} end
  local over=env.__over
  over.GetTime=function() return now end
  over.UnitExists=function(unit) return units[unit]~=nil end
  over.UnitIsPlayer=over.UnitExists
  over.UnitGUID=function(unit) return units[unit] and units[unit][2] end
  over.UnitName=function(unit) return units[unit] and units[unit][1] end
  over.UnitFullName=function(unit) return units[unit] and units[unit][1], "TestRealm" end
  over.UnitClass=function(unit) if units[unit] then return "Priest", "PRIEST" end end
  over.Aura=function(unit)
    if unit=="player" or covered then return {expirationTime=now+3600} end
  end
  env.IsInGroup=function() return units.party1~=nil end
  env.GetNumGroupMembers=function() return units.party1 and 2 or 0 end
  env.UnitIsGroupLeader=function(unit) return unit=="player" end
  env.IsSpellInRange=function() return 1 end
  env.IsAddOnLoaded=function(addon) return loaded[addon]==true end
  env.C_AddOns=nil
  if env.C_Timer then env.C_Timer.After=function(delay, callback)
    timers[#timers+1]={deadline=now+delay, callback=callback}
  end end
  local rawBody=env.GetMacroBody
  env.GetMacroBody=function(index)
    local body=rawBody(index)
    if not body then return end
    if newline=="crlf" then return body:gsub("\r\n", "\n"):gsub("\n", "\r\n").."\r\n" end
    if newline=="trailing" then return body.."\n\n" end
    return body
  end
  local bindingMap, actions={}, {}
  env.GetBindingAction=function(key) return bindingMap[key] or "" end
  env.GetBindingKey=function(command)
    local keys={}
    for key, value in pairs(bindingMap) do if value==command then keys[#keys+1]=key end end
    table.sort(keys); return unpack(keys)
  end
  local function fire(event, ...)
    for _, frame in ipairs(env.__frames) do
      if frame.events and frame.events[event] and frame.scripts.OnEvent then
        frame.scripts.OnEvent(frame, event, ...)
      end
    end
  end
  return {
    env=env, ns=ns,
    load=function(source,path) local fn=assert(loadstring(source,"@"..path)); setfenv(fn,env); fn("BuffRadar",ns) end,
    restore=function(db, macros, bindings, slots)
      env.BuffRadarDB=db
      for index, macro in pairs(macros) do env.__macros[index]=macro end
      bindingMap, actions=bindings, slots
    end,
    start=function() fire("ADDON_LOADED","BuffRadar"); fire("PLAYER_LOGIN") end,
    world=function() fire("PLAYER_ENTERING_WORLD") end,
    logout=function() fire("PLAYER_LOGOUT") end,
    slash=function(text) env.SlashCmdList.BUFFRADAR(text) end,
    refresh=function()
      now=now+10
      for _=1,64 do
        local index
        for i,t in ipairs(timers) do if t.deadline<=now then index=i; break end end
        if not index then break end
        table.remove(timers,index).callback()
      end
      ns.X.Refresh()
    end,
    row=function()
      for _,f in ipairs(env.__frames) do
        if f.frameName and f.frameName:match("^BuffRadarRow%d+$") and f.entry and f:IsShown() then return f end
      end
    end,
    bind=function(key, command) bindingMap[key]=command end,
    slot=function(index, macro) actions[index]=macro end,
    durable=function() return env.BuffRadarDB,env.__macros,bindingMap,actions end,
    press=function(key,body)
      local command=bindingMap[key]
      if not command then return nil end
      local frame, button=command:match("^CLICK ([^:]+):(.+)$")
      if frame then
        local rebuilt=assert(env[frame],"binding frame missing")
        if rebuilt.scripts.PreClick then rebuilt.scripts.PreClick(rebuilt,button,false) end
        local unit=rebuilt:GetAttribute("unit")
        if rebuilt.scripts.PostClick then rebuilt.scripts.PostClick(rebuilt,button,false) end
        return unit,rebuilt.frameName
      end
      local fn=assert(loadstring(body,"@Bindings.xml")); setfenv(fn,env); fn()
      return command
    end,
  }
end'''


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def plain(value):
    """Copy only the plain WoW save tree; reject runtime handles/functions."""
    if lua_type(value) == "table":
        return {plain(key): plain(item) for key, item in value.items()}
    check(value is None or isinstance(value, (str, int, float, bool)),
          f"non-durable value crossed relog: {type(value).__name__}")
    return value


class Client:
    def __init__(self, stub, sources, other, covered=False, loaded=(),
                 newline="lf", with_timer=True, saved=None):
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(stub)
        self.api = self.lua.eval(CLIENT)(with_timer, other,
            f"Player-1-{other}" if other else None, covered,
            self.decode({name: True for name in loaded}), newline)
        for path, source in sources:
            self.api.load(source, path)
        if saved:
            self.api.restore(*(self.decode(deepcopy(item)) for item in saved))

    def decode(self, value):
        if isinstance(value, dict):
            return self.lua.table_from({self.decode(k): self.decode(v) for k, v in value.items()})
        return value

    @property
    def db(self):
        return self.api.env.BuffRadarDB

    @property
    def x(self):
        return self.api.ns.X

    def save(self):
        return tuple(plain(value) for value in self.api.durable())

    def body(self):
        return self.api.env["__macros"][1].body


def sources_for(addon):
    root = addon.resolve().parent
    sources = []
    for line in (root.parent / "editions/forever/BuffRadar.toc").read_text(encoding="utf-8-sig").splitlines():
        path = line.strip()
        if path and not path.startswith("#") and path.lower().endswith(".lua"):
            sources.append((path, (root / path.replace("\\", "/")).read_text(encoding="utf-8-sig")))
    check(any((root / path.replace("\\", "/")) == addon.resolve() for path, _ in sources), "addon absent from TOC")
    return sources


def run(stub, sources, bindings):
    a = Client(stub, sources, "Before", loaded=("ElvUI", "EllesmereUI"))
    a.api.start(); a.api.world()
    for command in ("show", "theme auto", "macro"):
        a.api.slash(command)
    a.db.pauseInCities=False
    a.db.includeSelf=False
    a.db.groupCast=False
    a.db.castMethod="target"
    a.db.enabled.FORTITUDE=True
    a.db.enabled.DIVINE_SPIRIT=False
    a.db.rebuff=67
    a.db.bgColor=a.decode({1: .12, 2: .23, 3: .34})
    a.db.rebuffPer.FORTITUDE=81
    a.db.customThemes=a.decode({1: {"name": "Relog", "bg": {1:.1,2:.2,3:.3}, "border":{1:.4,2:.5,3:.6}}})
    a.x.MoveAutoThemePriority("ui.ellesmereui", -1)
    a.api.slash("profile save Relog")
    for i, command in enumerate(bindings):
        a.api.bind(f"F{i+6}", command)
    a.api.slot(7, 1)
    a.x.Core.BuildBuffList(); a.api.refresh()
    check(a.x.CastDelivery().directReady, "A never acquired a cast target")
    check("/click BuffRadarNextButton" in a.body() and a.x.GetNextButton().entry.guid=="Player-1-Before", "A macro was not armed for initial recipient")
    check(a.x.autoThemeAddon == "EllesmereUI", "A did not honor changed Auto priority")
    abrupt = a.save()
    # An older managed exact-target body may survive a crash or an upgrade.
    # It must be parked before a fresh roster can repopulate the same unit token.
    exact = deepcopy(abrupt)
    exact[1][1]["body"] = ("# BuffRadar\n/stopmacro [combat][@player,dead]\n"
        "/click BuffRadarMacroButton\n/cleartarget\n/targetexact Before\n"
        "/cast [help,nodead] Power Word: Fortitude\n/cleartarget")
    a.api.logout()
    graceful = a.save()
    check("/click" not in a.body(), "graceful logout retained old macro action")
    count=0
    for with_timer in (True, False):
        for label, saved in (("graceful", graceful), ("abrupt", abrupt), ("old-exact", exact)):
            for newline in ("lf", "crlf", "trailing"):
                b = Client(stub, sources, "After", loaded=("ElvUI",), newline=newline,
                           with_timer=with_timer, saved=saved)
                b.api.start()
                check("/click" not in b.body() and "/cast" not in b.body() and "Before" not in b.body(), "login armed saved recipient before scan")
                check(not b.x.CastDelivery().directReady, "login inherited a runtime queue")
                b.api.world(); b.api.refresh()
                check(b.x.CastDelivery().directReady and b.x.CastDelivery().macroReady, "fresh cast delivery did not arm")
                button=b.x.GetNextButton()
                row=b.api.row()
                check(button.entry.guid=="Player-1-After" and button.GetAttribute(button,"unit")=="party1", "next button retained A recipient")
                check(row and row.entry.guid=="Player-1-After" and row.GetAttribute(row,"unit")=="party1", "row retained A recipient")
                check("/click BuffRadarNextButton" in b.body() and "Before" not in b.body(), "managed macro did not follow rebuilt B queue")
                durable=b.save()
                check(durable[3][7]==1 and durable[1][1]["name"]=="BuffRadar", "macro action slot identity was lost")
                check(durable[2]==saved[2], "native bindings were lost")
                for i,(command,body) in enumerate(bindings.items()):
                    before_hidden,before_sound=b.db.hidden,b.db.playSound
                    result=b.api.press(f"F{i+6}", body)
                    if command.startswith("CLICK "):
                        check(result[1]==command.split(" ",1)[1].split(":")[0], "binding failed to resolve newly rebuilt named frame")
                        if "NextButton" in command:
                            check(result[0]=="party1", "rebuilt next binding lost its current cast target")
                    elif command=="BUFFRADAR_TOGGLE": check(b.db.hidden!=before_hidden, "toggle binding did not operate")
                    elif command=="BUFFRADAR_MUTE": check(b.db.playSound!=before_sound, "mute binding did not operate")
                    elif command=="BUFFRADAR_ACTIONS":
                        check(b.api.env.BuffRadarConfig.searchMode=="actions" and b.api.env.BuffRadarConfig.searchResultsPanel.IsVisible(b.api.env.BuffRadarConfig.searchResultsPanel), "Actions binding did not open the rebuilt menu")
                check(b.db.rebuff==67 and b.db.rebuffPer.FORTITUDE==81, "nested preferences lost")
                check(b.db.profiles.Relog and b.db.customThemes[1].name=="Relog", "profile/custom palette lost")
                check(b.db.theme=="ui.auto" and b.db.autoThemePriority==saved[0]["autoThemePriority"], "Auto settings changed on relog")
                check(b.x.autoThemeAddon=="ElvUI", "Auto reused A addon instead of detecting B")
                b.db.rebuffPer.FORTITUDE=19
                check(saved[0]["rebuffPer"]["FORTITUDE"]==81 and a.db.rebuffPer.FORTITUDE==81, "save aliases a Lua state")
                count+=1
                print(f"PASS relog {label}/{newline}/timer={with_timer}")
    for mode in ("custom", "empty", "manual"):
        saved=deepcopy(abrupt)
        if mode=="custom": saved[1][1]["body"]="# BuffRadar\n/say custom text"
        if mode=="manual": saved[0]["theme"]="midnight"
        b=Client(stub,sources,"After",covered=mode=="empty",loaded=("ElvUI",),saved=saved)
        b.api.start(); b.api.world(); b.api.refresh()
        if mode=="custom":
            check(b.body()==saved[1][1]["body"] and b.x.CastDelivery().reason=="custom", "custom macro was overwritten")
        elif mode=="empty":
            check(not b.x.CastDelivery().directReady and "/click" not in b.body() and "/cast" not in b.body(), "empty queue retained armed action")
        else:
            check(b.db.theme=="midnight" and b.x.autoThemeAddon is None, "manual palette followed loaded vendor")
            check(plain(b.x.ThemeBackground())==saved[0]["bgColor"], "manual background was changed")
        count+=1
        print(f"PASS relog {mode}")
    print(f"Relog: {count} scenarios passed (independent Lua 5.1 states; offline native adapters).")


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stub",type=Path)
    parser.add_argument("addon",type=Path)
    args=parser.parse_args()
    bindings={node.attrib["name"]: (node.text or "").strip()
              for node in ET.parse(args.addon.parent/"Bindings.xml").getroot()}
    check(set(bindings)=={"CLICK BuffRadarNextButton:LeftButton", "CLICK BuffRadarGroupButton:LeftButton", "BUFFRADAR_TOGGLE", "BUFFRADAR_MUTE", "BUFFRADAR_ACTIONS"}, "expected all five XML binding identities")
    run(args.stub.read_text(encoding="utf-8-sig"), sources_for(args.addon), bindings)


if __name__ == "__main__":
    main()
