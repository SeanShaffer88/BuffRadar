-- BuffRadar: German (deDE) text for the main window, its row tooltips and the
-- minimap / addon-menu tooltips. Used automatically on German game clients.
--
-- Also the template for other languages:
--   1. Copy this file as Locales\<code>.lua (frFR, esES, esMX, ptBR, itIT,
--      ruRU, koKR, zhCN, zhTW) and change "deDE" below to that code.
--   2. Translate the right-hand side of each line. The left-hand side is the
--      English text BuffRadar looks up -- leave it exactly as it is.
--   3. Keep %d and %s (numbers / names filled in later) and |cff......|r
--      color codes. Leave a line out to keep it in English.
--   4. Add the file to BuffRadar.toc, above BuffRadar.lua.
-- tools\check.ps1 reports keys BuffRadar doesn't use and mismatched %d / %s.

BuffRadarLocales = BuffRadarLocales or {}
BuffRadarLocales.deDE = {
  -- window status lines
  ["Paused in a major city."] = "In einer Hauptstadt pausiert.",
  ["Paused in a battleground."] = "Auf einem Schlachtfeld pausiert.",
  ["Everyone nearby is buffed."] = "Alle in der Nähe sind gebufft.",
  ["Friendly nameplates are off."] = "Freundliche Namensplaketten sind aus.",
  ["No supported buffs in your spellbook."] = "Keine unterstützten Buffs im Zauberbuch.",
  ["combat"] = "Kampf",
  ["out of range"] = "außer Reichweite",
  ["+%d more"] = "+%d weitere",
  ["Casts: |cffffffff%d|r this session  ·  |cffffffff%d|r all-time"] =
    "Zauber: |cffffffff%d|r diese Sitzung  ·  |cffffffff%d|r insgesamt",
  -- row tooltip
  ["Out of range — move closer to cast:"] = "Außer Reichweite – näher herangehen, um zu wirken:",
  ["Click to cast: %s"] = "Klicken zum Wirken: %s",
  ["Group version — one cast buffs the whole party."] = "Gruppenversion – ein Zauber bufft die ganze Gruppe.",
  ["Right-click to ignore this player."] = "Rechtsklick, um diesen Spieler zu ignorieren.",
  ["Still needs: %s"] = "Braucht noch: %s",
  -- window buttons, minimap button and addon menu
  ["BuffRadar settings"] = "BuffRadar-Einstellungen",
  ["Drag to resize the width"] = "Ziehen, um die Breite zu ändern",
  ["Left-click: show / hide the window"] = "Linksklick: Fenster ein-/ausblenden",
  ["Right-click: settings"] = "Rechtsklick: Einstellungen",
  ["Drag: move around the minimap"] = "Ziehen: um die Minikarte verschieben",
}
