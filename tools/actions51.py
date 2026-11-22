"""Exercise fixed Actions launchers and shared settings search in real Lua 5.1."""
import argparse
import importlib.util
import sys
from pathlib import Path
from xml.etree import ElementTree

from lupa import lua51

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("buffradar_actions_fixture", Path(__file__).with_name("coordination51.py"))
fixture = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = fixture
spec.loader.exec_module(fixture)

TEST = r'''function(api, binding)
  local X, env = api.x(), api.env
  local db = X.GetDB()
  assert(X.OpenActions())
  local cfg = assert(env.BuffRadarConfig)
  assert(cfg.searchMode=="actions" and cfg.searchResultsPanel:IsVisible(),"blank Actions list not browsable")
  assert(#X.CfgSearch("","actions")==14,"wrong action catalog")
  local first=cfg.searchRows[1].entry
  cfg.searchNext:Click();cfg.searchPrev:Click()
  assert(cfg.searchRows[1].entry==first,"unstable action paging")
  for _,entry in ipairs(X.CfgSearch("","settings")) do assert(entry.kind~="action","Settings mode leaked actions") end
  for _,entry in ipairs(X.CfgSearch("","actions")) do
    assert(entry.kind=="action" and entry.command:sub(1,4)=="/br ","missing action shortcut")
  end
  assert(#X.CfgSearch(string.rep("x",81))==0 and #X.CfgSearch({})==0,"unbounded search input")
  local packets,serial,profile = #env.__addonSent,X.CastSuccessSerial(),X.ProfileSnapshot()
  for _=1,3 do
    for _,entry in ipairs(X.CfgSearch("","actions")) do X.ActionState(entry.id) end
    X.CfgSearch("/br coordinate panel")
  end
  assert(#env.__addonSent==packets and X.CastSuccessSerial()==serial and X.ProfileSnapshot()==profile,
    "search/status sent packets, cast, or changed preferences")
  assert(not X.RunAction("/br reset") and not X.ActionState({}).available,"unknown action dispatched")

  local oldGroup,oldSuspended=X.InGroup,X.PlayerSuspended
  X.InGroup=function() return false end
  assert(not X.ActionState("preparation").available,"solo preparation claimed Ready")
  local beforePanels=#env.__frames
  assert(not X.RunAction("preparation") and #env.__frames==beforePanels,"stale solo preparation ran")
  X.InGroup=oldGroup
  db.liteMode=true
  assert(X.ActionState("preparation").reason==X.L["Raid Preparation is paused in Lite mode."],"missing Lite reason")
  assert(not X.RunAction("preparation"),"Lite preparation ran")
  db.liteMode=false
  X.PlayerSuspended=function() return true end
  assert(not X.RunAction("support") and not X.OpenActions(),"suspended launcher ran")
  X.PlayerSuspended=oldSuspended

  -- Availability changes after a result is rendered must win over that result.
  X.OpenActions();cfg.searchBox:SetText("/br support");cfg.searchBox.scripts.OnTextChanged(cfg.searchBox)
  assert(cfg.searchRows[1].entry.id=="support")
  env.__combat=true
  cfg.searchRows[1]:Click()
  assert(cfg.searchRows[1]:IsEnabled() and cfg.searchRows[1]:GetText():find(X.L["Can't do that during combat."],1,true),
    "unavailable row lost visible reason or keyboard access")
  assert(not env.BuffRadarExport or not env.BuffRadarExport:IsVisible(),"stale combat result opened report")
  env.__combat=false

  -- Real settings input controller retains keyboard focus across main-tab launch.
  X.OpenSettingsNavigation(false);X.OpenActions()
  cfg.searchBox:SetText(X.L["Profiles"]);cfg.searchBox.scripts.OnTextChanged(cfg.searchBox)
  cfg.searchBox.scripts.OnTabPressed(cfg.searchBox)
  cfg.navInput.scripts.OnEnterPressed(cfg.navInput)
  assert(cfg.curTab=="data" and cfg.navInput:HasFocus() and cfg.navOutline.points[1][2]==cfg.profileBox,
    "Profiles lost keyboard navigation")
  local spoken={}
  env.Enum=env.Enum or {};env.Enum.TtsVoiceType={Standard=1}
  env.TextToSpeech_GetSelectedVoice=function() return {voiceID=1} end
  env.C_TTSSettings={GetSpeechRate=function() return 1 end,GetSpeechVolume=function() return 1 end}
  env.C_VoiceChat={SpeakText=function(_,text) spoken[#spoken+1]=text end}
  X.OpenSettingsNavigation(true);X.OpenActions()
  cfg.searchBox:SetText(X.L["Profiles"]);cfg.searchBox.scripts.OnTextChanged(cfg.searchBox)
  cfg.searchBox.scripts.OnTabPressed(cfg.searchBox)
  cfg.navInput.scripts.OnEnterPressed(cfg.navInput)
  api.advance(1001)
  assert(cfg.navInput:HasFocus() and #spoken>0 and spoken[#spoken]:find(X.L["Profile name"],1,true),
    "Profiles lost narration")
  local oldSelfTest=X.SelfTest
  X.SelfTest=function() error("fixture fault") end
  assert(not X.RunAction("selftest") and cfg.navInput:HasFocus(),"launcher fault stranded keyboard focus")
  X.SelfTest=oldSelfTest

  assert(X.RunAction("why"))
  local panel=assert(cfg.actionWhyPanel)
  assert(panel:IsVisible() and panel.name.navigation and panel.explain.navigation,"Why form missing navigation")
  local oldWhy,received,calls=X.Why,nil,0
  X.Why=function(name) received=name;calls=calls+1 end
  panel.name:SetText("  Beryl-TestRealm  ");panel.explain:Click()
  assert(received=="Beryl-TestRealm" and calls==1,"Why form did not trim direct argument")
  panel.name:SetText("|cffffffffsecret");panel.explain:Click()
  panel.name:SetText(string.rep("x",81));panel.explain:Click()
  assert(calls==1,"Why accepted overlong or formatted input")
  panel.name:SetText("/br reset");panel.explain:Click()
  assert(received=="/br reset" and X.ProfileSnapshot()==profile,"Why dispatched a slash command")
  X.Why=oldWhy
  cfg.navInput.scripts.OnEscapePressed(cfg.navInput)
  assert(not panel:IsShown() and panel.name:GetText()=="","Why Escape retained input")

  -- Opening group diagnostics needs no opt-in and sends no application packet.
  api.configure("Beryl","Player-1-0002",false,"Beryl",1002)
  api.fire("GROUP_ROSTER_UPDATE")
  packets=#env.__addonSent
  assert(X.RunAction("peers"))
  assert(cfg.assignmentPanel.coordination.tab=="peers" and cfg.assignmentPanel.coordination:IsVisible(),
    "Peer Status did not select Peers")
  assert(#env.__addonSent==packets,"opening Peer Status broadcast a message")
  X.OpenActions()
  local source=assert(loadstring(binding,"@Bindings.xml"));setfenv(source,env);source()
  assert(cfg.searchMode=="actions" and cfg.searchResultsPanel:IsVisible(),"optional XML binding did not open Actions")
  assert(X.CastSuccessSerial()==serial,"Actions binding cast a buff")

  local gear
  for _,frame in ipairs(env.__frames) do
    if frame.parent==env.BuffRadarFrame and frame.highlight and frame.highlight.file=="Interface\\Buttons\\UI-OptionsButton" then gear=frame end
  end
  assert(gear,"settings gear missing")
  local oldShift,oldConfig,oldDaily,oldActions=env.IsShiftKeyDown,X.OpenConfig,X.Daily.Open,X.OpenActions
  local settings,daily,actions=0,0,0
  X.OpenConfig=function() settings=settings+1 end
  X.Daily.Open=function() daily=daily+1 end
  X.OpenActions=function() actions=actions+1 end
  env.IsShiftKeyDown=function() return false end
  gear.scripts.OnClick(gear,"LeftButton")
  gear.scripts.OnClick(gear,"RightButton")
  env.IsShiftKeyDown=function() return true end
  gear.scripts.OnClick(gear,"LeftButton")
  gear.scripts.OnClick(gear,"RightButton")
  assert(settings==1 and daily==2 and actions==1,"gear shortcuts changed existing destinations")
  env.IsShiftKeyDown,X.OpenConfig,X.Daily.Open,X.OpenActions=oldShift,oldConfig,oldDaily,oldActions
  env.SlashCmdList.BUFFRADAR("actions")
  assert(cfg.searchMode=="actions","slash Actions entry missing")

  local future={dbVersion=999999,theme="midnight",foreign="preserve"}
  env.BuffRadarDB=future;X.Settings.Load(false)
  assert(not X.ActionState("themes").available and not X.RunAction("profiles"),"future settings allowed edits")
  assert(X.ActionState("support").available and X.RunAction("support"),"future settings blocked read-only report")
  assert(env.BuffRadarDB==future and future.foreign=="preserve","read-only report replaced future save")
  return true
end'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--addon", type=Path, default=Path("BuffRadar/BuffRadar.lua"))
    args = parser.parse_args()
    bindings = ElementTree.parse(args.addon.parent / "Bindings.xml").getroot()
    action_binding = [node for node in bindings if node.attrib.get("name") == "BUFFRADAR_ACTIONS"]
    assert len(action_binding) == 1
    for with_timer in (True, False):
        lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        lua.execute(Path(__file__).with_name("wowstub.lua").read_text(encoding="utf-8"))
        adapter = fixture.CLIENT.replace("return {\n    configure = configure,",
            "return {\n    x = function() return ns.X end, env = env, configure = configure,")
        api = lua.eval(adapter)("Aster", "Player-1-0001", with_timer)
        for path, source in fixture.forever_sources(args.addon):
            api.load(source, path)
        api.start()
        lua.eval(TEST)(api, (action_binding[0].text or "").strip())
        print(f"Actions: catalog, purity, guards, keyboard, narration, forms and bindings passed (timer={with_timer})")


if __name__ == "__main__":
    main()
