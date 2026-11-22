"""Exercise transient theme previews against the real Forever modules in Lua 5.1."""
import argparse
import importlib.util
import sys
from pathlib import Path

from lupa import lua51

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("buffradar_coordination_fixture", Path(__file__).with_name("coordination51.py"))
fixture = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = fixture
spec.loader.exec_module(fixture)
CLIENT, forever_sources = fixture.CLIENT, fixture.forever_sources


TEST = r'''function(api)
  local X, env = api.x(), api.env
  local db = X.GetDB()
  local function same(a,b) return a[1]==b[1] and a[2]==b[2] and a[3]==b[3] end
  local beforeTheme, beforeColor = db.theme, {unpack(db.bgColor)}
  local count = X.Preferences.Usage().transactions
  local owner = assert(X.BeginThemePreview())
  assert(X.PreviewTheme(owner,"ui.elvui"))
  assert(db.theme==beforeTheme and same(db.bgColor,beforeColor),"preview persisted")
  assert(X.ThemeBackground()==X.ThemeDef("ui.elvui").bg,"candidate not rendered")
  assert(X.Preferences.Usage().transactions==count,"preview recorded history")
  assert(X.CancelThemePreview(owner))
  assert(db.theme==beforeTheme and same(db.bgColor,beforeColor),"cancel changed settings")
  assert(not X.ApplyThemePreview(owner),"cancelled owner committed")

  owner=assert(X.BeginThemePreview())
  assert(X.PreviewTheme(owner,"ui.elvui"))
  assert(X.ApplyThemePreview(owner))
  assert(db.theme=="ui.elvui" and same(db.bgColor,X.ThemeDef("ui.elvui").bg),"Apply lost palette")
  assert(X.Preferences.Usage().transactions==count+1,"Apply not one undo transaction")
  assert(X.Preferences.Undo())
  assert(db.theme==beforeTheme and same(db.bgColor,beforeColor),"undo lost original palette")

  owner=assert(X.BeginThemePreview())
  assert(X.PreviewTheme(owner,"ui.elvui"))
  X.ApplyTheme("midnight")
  assert(not X.ApplyThemePreview(owner),"manual selection did not invalidate preview")
  owner=assert(X.BeginThemePreview())
  assert(X.PreviewTheme(owner,"ui.elvui"))
  db.autoThemePriority="changed"
  assert(not X.ApplyThemePreview(owner),"priority edit did not invalidate owner")
  db.autoThemePriority=""

  local loaded={ElvUI=true}
  env.IsAddOnLoaded=function(name) return loaded[name]==true end
  owner=assert(X.BeginThemePreview())
  assert(X.PreviewTheme(owner,X.AUTO_THEME_ID))
  assert(X.ThemePreviewState(owner).addon=="ElvUI","Auto source missing")
  loaded.ElvUI=false
  assert(X.ThemePreviewState(owner).addon==nil,"Auto preview kept unloaded addon")
  loaded.ElvUI=true
  assert(X.ApplyThemePreview(owner))
  assert(db.theme==X.AUTO_THEME_ID and X.autoThemeAddon=="ElvUI","Auto Apply did not resolve locally")
  owner=assert(X.BeginThemePreview())
  assert(X.PreviewTheme(owner,"midnight"))
  assert(X.ThemeLabel(true)=="Auto (ElvUI)","preview leaked into committed theme label")
  assert(X.AutoThemeStatus()=="Selected: ElvUI (ElvUI)","preview leaked into committed Auto source")
  X.CancelThemePreview(owner)

  owner=assert(X.BeginThemePreview())
  assert(X.PreviewTheme(owner,"ui.elvui"))
  env.__combat=true
  assert(not X.ApplyThemePreview(owner),"combat committed preview")
  env.__combat=false
  assert(not X.ThemePreviewState(owner),"combat left preview alive")

  env.SlashCmdList.BUFFRADAR("theme preview")
  local panel=assert(env.BuffRadarThemePreview,"preview panel missing")
  assert(panel:IsVisible() and panel.previous.navigation and panel.apply.navigation,"preview inaccessible")
  panel.next:Click()
  local committed=db.theme
  panel.cancel:Click()
  assert(not panel:IsShown() and db.theme==committed,"panel cancel persisted selection")
  env.SlashCmdList.BUFFRADAR("theme preview")
  assert(panel:IsVisible())
  env.BuffRadarConfig:Hide()
  assert(not panel:IsShown() and not X.ThemePreviewState(),"parent hide leaked preview")
  env.SlashCmdList.BUFFRADAR("theme preview")
  owner=panel.owner
  local generation=X.Preferences.Generation()
  X.Settings.Load(false)
  db=X.GetDB()
  assert(X.Preferences.Generation()>generation and not X.ApplyThemePreview(owner),"DB replacement kept old owner")
  X.RefreshConfig()
  assert(not panel:IsShown(),"profile reload left preview modal open")
  db.theme="custom"
  owner=assert(X.BeginThemePreview())
  assert(X.ThemePreviewState(owner).id=="custom","custom palette cannot open preview")
  X.CancelThemePreview(owner)
  env.BuffRadarDB.dbVersion=999
  X.Settings.Load(false)
  assert(X.Settings.SaveState()=="future" and not X.BeginThemePreview(),"future save allowed preview edits")
  return true
end'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--addon", type=Path, default=Path("BuffRadar/BuffRadar.lua"))
    args = parser.parse_args()
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(Path(__file__).with_name("wowstub.lua").read_text(encoding="utf-8"))
    adapter = CLIENT.replace("return {\n    configure = configure,", "return {\n    x = function() return ns.X end, env = env, configure = configure,")
    api = lua.eval(adapter)("Aster", "Player-1-0001", True)
    for path, source in forever_sources(args.addon):
        api.load(source, path)
    api.start()
    lua.eval(TEST)(api)
    print("theme preview: transient state, Apply/Cancel, Auto resolution, invalidation and accessible panel passed")


if __name__ == "__main__":
    main()
