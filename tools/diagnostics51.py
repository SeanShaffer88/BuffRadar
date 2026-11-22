"""Read-only BG/blessing diagnostics on the real Forever Lua 5.1 modules."""
import argparse
import importlib.util
from pathlib import Path
import sys
sys.dont_write_bytecode = True
from lupa import lua51


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--addon', type=Path, required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('coordination', Path(__file__).with_name('coordination51.py'))
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(Path(__file__).with_name('wowstub.lua').read_text(encoding='utf-8-sig'))
    client = lua.eval(mod.CLIENT.replace('configure = configure,', 'configure = configure, env=env, chat=chat, x=function() return ns.X end,'))('Alice', 'Player-1-0001', True)
    for path, source in mod.forever_sources(args.addon):
        client.load(source, path)
    client.start()
    lua.eval(r'''function(client)
      local X, e = client.x(), client.env
      local o, db = e.__over, e.BuffRadarDB
      db.pauseInCities,db.pauseTaxi,db.pauseInBG=false,false,false
      e.IsInInstance=function() return true,"pvp" end
      o.UnitIsPVP=function() return true end
      o.UnitAffectingCombat=function() return false end
      local c=X.DiagnosticContext()
      assert(c.instance=="pvp" and c.policy=="none", "BG disabled context")
      db.pauseInBG=true
      assert(X.DiagnosticContext().policy=="battleground", "BG enabled pause")
      e.IsInInstance=function() error("private context") end
      assert(X.DiagnosticContext().policy=="unknown", "unavailable BG context claimed none")
      e.IsInInstance=function() return true,"arena" end
      assert(X.DiagnosticContext().policy=="battleground", "arena pause")
      o.UnitAffectingCombat=function() return 0 end
      assert(X.DiagnosticContext().combat==nil and X.DiagnosticContext().blocker=="unknown", "numeric combat coerced")
      o.UnitAffectingCombat=function() return false end
      X.scanUnit,X.blessingScanUnit,X.hid="old","oldBlessing",false
      local before=X.Support.Report()
      assert(not pcall(X.WithDiagnosticReads,function()
        X.scanUnit,X.blessingScanUnit,X.hid="new","newBlessing",true
        error("private diagnostic failure")
      end))
      assert(X.scanUnit=="old" and X.blessingScanUnit=="oldBlessing" and X.hid==false,"scratch error restoration")
      X.Why("nobody")
      assert(X.scanUnit=="old" and X.blessingScanUnit=="oldBlessing" and X.hid==false,"Why scratch restoration")
      assert(X.Support.Report()==before,"Why mutated support state")
      db.pauseInBG=false
      e.IsInInstance=function() return false,"none" end
      o.UnitClass=function() return "Paladin","PALADIN" end
      local book={{"Blessing of Kings","Rank 1",20217},{"Blessing of Wisdom","Rank 3",19852},{"Blessing of Might","Rank 2",19834}}
      e.GetSpellTabInfo=function() return "Holy",nil,0,#book end
      e.GetSpellBookItemName=function(i) if book[i] then return book[i][1],book[i][2] end end
      e.GetSpellBookItemInfo=function(i) return "SPELL",book[i] and book[i][3] end
      e.IsPlayerSpell=function() return false end
      X.Core.BuildBuffList()
      local k=X.BlessingKnowledge()
      assert(k.cacheReady and k.detected.KINGS and k.detected.WISDOM and k.maxRank.WISDOM==3,"cached actual blessings")
      local d={}
      local b,source=X.BlessingForClass("PALADIN",nil,nil,nil,nil,d)
      assert(b and source==nil and d.source=="default" and d.preferred=="KINGS","default return compatibility")
      db.blessingPreferences.PALADIN="WISDOM"
      d={};b,source=X.BlessingForClass("PALADIN",nil,nil,nil,nil,d)
      assert(source==nil and d.preferred=="WISDOM" and d.source=="preference","manual preference provenance")
      X.blessPlan.PALADIN={mine=false,key="KINGS"}
      d={};b,source=X.BlessingForClass("PALADIN",nil,nil,nil,nil,d)
      assert(not b and source=="other" and d.source=="plan_other","other Paladin plan")
      X.blessPlan.PALADIN={mine=true,key="WISDOM"}
      d={};b,source=X.BlessingForClass("PALADIN",nil,nil,nil,nil,d)
      assert(source=="plan" and d.selected=="WISDOM","own plan provenance")
      X.blessPlan.PALADIN=nil
      X.blessingExceptions={ ["Player-1-0001"]="MIGHT" }
      d={};b,source=X.BlessingForClass("PALADIN","player",nil,nil,nil,d)
      assert(source=="exception" and d.selected=="MIGHT","exception provenance")
      X.blessingExceptions={}
      d={};b,source=X.BlessingForClass("PALADIN",nil,{BLESS_WISDOM=true},nil,nil,d)
      assert(source==nil and d.source=="assignment" and d.selected=="WISDOM","assignment provenance")
      db.blessingPreferences.PALADIN=nil
      local owner=X.BlessingOwner
      X.BlessingOwner=function(_,names) return names[1]=="Blessing of Kings" and "other" or "absent" end
      d={};local preferred=X.BlessingForClass("PALADIN")
      local alternative=X.ComplementWorldBlessing("player","PALADIN",preferred,d)
      assert(alternative~=preferred and d.preferredOwner=="other" and d.outcome=="alternate_available","complement choice trace")
      X.BlessingOwner=function() return "unknown" end
      d={};assert(X.ComplementWorldBlessing("player","PALADIN",preferred,d)==preferred and d.outcome=="ownership_unknown","unknown owner changed selection")
      X.BlessingOwner=owner
      local rankRecords
      for index=1,30 do
        local name,value=debug.getupvalue(X.DefaultRank,index)
        if name=="ranks" then rankRecords=value;break end
        if not name then break end
      end
      assert(rankRecords,"rank fixture upvalue")
      e.GetSpellLevelLearned=function() return 10 end
      for _,records in pairs(rankRecords) do for _,record in ipairs(records) do record.learned=nil end end
      local casts,realm=db.castsTotal,X.Ignore.realm
      local chatBefore=#client.chat
      X.Why("Alice")
      local output=table.concat(client.chat,"\n",chatBefore+1)
      assert(output:find("Context:",1,true) and output:find("Blessing of Kings",1,true) and output:find("Built-in class priority",1,true),"Why omitted human-readable context or blessing source")
      assert(db.castsTotal==casts and X.Ignore.realm==realm and X.scanUnit=="old","real recipient Why mutated state")
      X.FilterInRange("player",{"Blessing of Kings"},{},true,true)
      for _,records in pairs(rankRecords) do for _,record in ipairs(records) do assert(record.learned==nil,"diagnostics populated cold rank cache") end end
      local secret=setmetatable({},{__tostring=function() error("secret rank converted") end})
      e.issecretvalue=function(value) return rawequal(value,secret) end
      book[2][2]=secret;X.Core.BuildBuffList()
      assert(X.BlessingKnowledge().maxRank.WISDOM==nil,"secret rank metadata invented")

      for _,bad in ipairs({false,42,"unreadable"}) do
        book[2][2]=bad
        X.Core.BuildBuffList()
        assert(X.BlessingKnowledge().maxRank.WISDOM==nil,"rank metadata invented")
      end
      book[2][2]=nil;X.Core.BuildBuffList()
      assert(X.BlessingKnowledge().maxRank.WISDOM==nil,"nil rank metadata invented")
      e.GetSpellBookItemName=function(i) if i==2 then error("private book") end return book[i][1],book[i][2] end
      X.Core.BuildBuffList()
      assert(not X.BlessingKnowledge().cacheReady and X.BlessingKnowledge().detected.KINGS==nil,"partial book claims absent blessings")
      e.GetSpellBookItemName=function(i) if book[i] then return book[i][1],book[i][2] end end
      e.C_SpellBook={GetNumSpellBookSkillLines=function() return 2 end,
        GetSpellBookSkillLineInfo=function(index) if index==2 then error("private tab") end return {itemIndexOffset=0,numSpellBookItems=1} end}
      X.Core.BuildBuffList()
      assert(not X.BlessingKnowledge().cacheReady,"partial skill lines claimed complete book")
      e.C_SpellBook=nil
      e.GetSpellTabInfo=function() return "Holy",nil,0,0 end
      e.GetSpellBookItemName=function() return nil end
      X.Core.BuildBuffList()
      assert(not X.BlessingKnowledge().cacheReady,"empty book claims learned/unlearned certainty")
      X.DiagnosticContext=function() error("Private-Name-Realm") end
      X.BlessingKnowledge=function() return setmetatable({},{__index=function() error("private") end}) end
      local report=X.Support.Report()
      assert(report:find("pause.blocker=unknown",1,true) and report:find("blessings.detected.KINGS=unknown",1,true))
      assert(not report:find("Private",1,true) and #report<16384,"private diagnostic error escaped")
    end''')(client)
    print('PASS: typed BG/arena pauses, strict unknown flags, read-only Why and error restoration, private snapshot failure')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
