"""Start the real Forever addon in each locale before any module loads."""
from pathlib import Path
from lupa import lua51

ROOT = Path(__file__).resolve().parents[1]
lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.execute((ROOT / "tools/wowstub.lua").read_text(encoding="utf-8"))
files = [line.strip().replace("\\", "/") for line in (ROOT / "editions/forever/BuffRadar.toc").read_text().splitlines()
         if line.strip().endswith(".lua")]
sources = lua.table_from([lua.table_from((name, (ROOT / "BuffRadar" / name).read_text(encoding="utf-8-sig"))) for name in files])
check = lua.eval(r'''function(sources, locale)
  local e = WOWSTUB({}, true, false, true, locale)
  setmetatable(e, {__index=_G}); e._G=e
  local ns={}
  for _, file in ipairs(sources) do setfenv(assert(loadstring(file[2],file[1])),e)('BuffRadar',ns) end
  local X, driver=ns.X
  for _, f in ipairs(e.__frames) do if f.events.ADDON_LOADED and f.events.PLAYER_LOGIN then driver=f end end
  assert(driver)
  driver.scripts.OnEvent(driver,'ADDON_LOADED','BuffRadar')
  driver.scripts.OnEvent(driver,'PLAYER_LOGIN')
  local pack=assert(ns.Locales[locale])
  local count=0
  for key,value in pairs(X.L) do assert(pack[key] and pack[key]==value,'English fallback: '..key); count=count+1 end
  X.Refresh()
  e.SlashCmdList.BUFFRADAR('firstcast')
  local guide=X.Support.Frame()
  assert(guide:IsShown() and guide.title:GetText()==pack['First cast guide'])
  assert(guide.body.width==374 and guide.body.height==88 and guide.delivery.height==94)
  X.Support.Close()
  X.OpenWizard(); assert(X.wizardFrame:IsShown()); X.wizardFrame:Hide()
  X.OpenConfig(true)
  X.OpenSettingsSearch()
  local cfg=e.BuffRadarConfig
  cfg.searchBox:SetText(pack['First cast guide']); cfg.searchBox.scripts.OnTextChanged(cfg.searchBox)
  assert(#cfg.searchResults>0 and cfg.searchRows[1]:GetText():find(pack['First cast guide'],1,true))
  cfg.searchRows[1]:Click()
  assert(cfg.navOutline.points[1][2]==cfg.readiness.firstCast and cfg.readiness.firstCast:IsVisible())
  X.Support.ShowReport()
  assert(e.BuffRadarExportFrame:IsShown() and e.BuffRadarExportFrame.editBox:GetText():find('BuffRadarSupport/1',1,true))
  e.BuffRadarExportFrame:Hide()
  local profile=assert(X.Export())
  X.ShowExport(profile,true)
  e.BuffRadarExportFrame.accept:Click()
  assert(e.BuffRadarExportFrame.review:IsShown(), 'localized import review did not open')
  return count
end''')
for locale in ("deDE", "frFR", "esES", "ruRU", "zhCN"):
    count = check(sources, locale)
    print(f"{locale}: {count} localized keys; first-cast/report/search/setup/import-preview flows PASS")
