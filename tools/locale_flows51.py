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
  assert(X.HistoryText()==pack["No casts recorded yet — buffs you cast through BuffRadar will be listed here."],"history empty state not localized")
  X.Refresh()
  for _,frame in ipairs(e.__frames) do
    if frame.roleKey and frame.fs then
      local label=({ALL='All',TANK='Tank',HEALER='Heal',DAMAGER='DPS'})[frame.roleKey]
      assert(label and frame.fs:GetText()==pack[label],'untranslated role chip')
      assert(frame.fs.width==frame.size[1],'role chip text is unbounded')
    end
  end
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
  local oldException=X.SetBlessingException
  local errorKey='Join a group and leave combat to set a blessing exception.'
  X.SetBlessingException=function() return nil,errorKey end
  e.SlashCmdList.BUFFRADAR('bless player Nobody DEFAULT')
  X.SetBlessingException=oldException
  local ok,reason=X.IgnoreImport('not a BRI1 string')
  assert(not ok and pack[reason],'ignore error has no translation')
  X.Daily.Open()
  local daily=assert(X.Daily.Frame())
  assert(daily:IsShown() and daily.title:GetText()==pack['Daily Tasks'])
  assert(daily.freshness:GetText():find(pack['Last completed scan: %s · %s']:match('^([^%%]*)'),1,true))
  X.Preferences.Set('scale',1.1,'ui');X.Daily.Recent()
  local recent=assert(X.Daily.ReviewFrame())
  assert(recent:IsShown() and recent.title:GetText()==pack['Recent Changes'])
  assert(recent.rows[1]:GetText()~='')
  X.Daily.Share()
  assert(recent.model.scope=='preferences' and recent.title:GetText()==pack['Share Preferences'])
  assert(recent.description:GetText()==pack['Preferences only. The recipient keeps their ignored players and named exceptions.'])
  for _,row in ipairs(recent.rows) do
    local text=row:GetText() or ''
    assert(not text:find('identitiesExcluded',1,true) and not text:find('preferences:',1,true)
      and not text:find('true',1,true) and not text:find('false',1,true),'raw share category leaked')
  end
  recent:Hide()
  X.Preferences.Set('matrixView',true,'ui');X.Views.ShowMatrix()
  assert(X.Views.GetMatrixFrame():IsShown())
  X.Views.ToggleSelf();assert(X.Views.GetSelfFrame():IsShown())
  X.Supplies.Show();assert(X.Supplies.GetFrame():IsShown())
  local profile=assert(X.Export())
  X.ShowExport(profile,true)
  e.BuffRadarExportFrame.accept:Click()
  assert(e.BuffRadarExportFrame.review:IsShown(), 'localized import review did not open')
  return count
end''')
for locale in ("deDE", "frFR", "esES", "ruRU", "zhCN"):
    count = check(sources, locale)
    print(f"{locale}: {count} localized keys; first-cast/report/search/setup/import-preview/daily/undo/share/matrix/self/supplies flows PASS")
