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
  ["recently rezzed"] = "kürzlich wiederbelebt",
  ["a buff just expired"] = "ein Buff ist gerade abgelaufen",
  ["being buffed"] = "wird gerade gebufft",
  ["asked for a buff"] = "hat um einen Buff gebeten",
  ["up next"] = "als Nächstes dran",
  ["your assignment"] = "deine Aufgabe",
  ["assigned elsewhere"] = "anderswo zugewiesen",
  ["buddy's watch"] = "Partners Liste",
  ["All buffed"] = "Alle gebufft",
  ["Collapse to a pill while everyone is buffed"] = "Zu einer Pille schrumpfen, solange alle gebufft sind",
  ["Tag the next row after a cast"] = "Nächste Zeile nach einem Zauber markieren",
  ["Track flasks, food and runes (coverage line)"] = "Fläschchen, Essen und Runen verfolgen (Abdeckungszeile)",
  ["Split the list with other BuffRadar users"] = "Liste mit anderen BuffRadar-Nutzern aufteilen",
  ["Post the ready-check summary to group chat"] = "Bereitschafts-Zusammenfassung in den Gruppenchat posten",
  ["pinned"] = "angepinnt",
  ["weapon enchant missing"] = "Waffenzauber fehlt",
  ["Watch my weapon enchant"] = "Waffenzauber überwachen",
  ["Halve the rescan rate in big groups"] = "Aktualisierung in großen Gruppen halbieren",
  ["Remind me when entering an instance unbuffed"] = "Beim Betreten einer Instanz an fehlende Buffs erinnern",
  ["Low mana -- buffing paused."] = "Wenig Mana -- Buffen pausiert.",
  ["Shift-right-click to ignore for this session only."] =
    "Umschalt-Rechtsklick: nur für diese Sitzung ignorieren.",
  ["Still needs: %s"] = "Braucht noch: %s",
  -- window buttons, minimap button and addon menu
  ["BuffRadar settings"] = "BuffRadar-Einstellungen",
  ["Drag to resize the width"] = "Ziehen, um die Breite zu ändern",
  ["Left-click: show / hide the window"] = "Linksklick: Fenster ein-/ausblenden",
  ["Right-click: settings"] = "Rechtsklick: Einstellungen",
  ["Drag: move around the minimap"] = "Ziehen: um die Minikarte verschieben",
  -- settings window (1.4.0)
  ["Window"] = "Fenster",
  ["Alerts"] = "Signale",
  ["Buffs"] = "Buffs",
  ["Behavior"] = "Verhalten",
  ["Ignore & Stats"] = "Ignorieren & Statistik",
  ["Show BuffRadar title"] = "BuffRadar-Titel anzeigen",
  ["Show border"] = "Rahmen anzeigen",
  ["Minimap button (drag it around the minimap)"] = "Minimap-Schaltfläche (um die Minimap ziehen)",
  ["Play a sound when a name appears"] = "Ton abspielen, wenn ein Name erscheint",
  ["No alert sound in dungeons, raids or battlegrounds"] =
    "Kein Alarmton in Dungeons, Raids oder Schlachtfeldern",
  ["Show cast counter in the window"] = "Zauberzähler im Fenster anzeigen",
  ["Buff myself first (all buffs that suit me)"] = "Mich zuerst buffen (alle passenden Buffs)",
  ["Only show in a party or raid"] = "Nur in Gruppe oder Raid anzeigen",
  ["Pause scanning in major cities"] = "Scannen in Hauptstädten pausieren",
  ["Pause in battlegrounds and arenas"] = "In Schlachtfeldern und Arenen pausieren",
  ["Sync casts with other BuffRadar users"] = "Zauber mit anderen BuffRadar-Nutzern abstimmen",
  ["Mark players who ask for a buff in chat"] = "Spieler markieren, die im Chat um Buffs bitten",
  ["Print a summary when joining a group"] = "Beim Gruppenbeitritt eine Zusammenfassung ausgeben",
  ["Buff toggle strip on the window"] = "Buff-Schalterleiste am Fenster",
  ["Paused on a flight path."] = "Auf einer Flugroute pausiert.",
  ["Pause on flight paths"] = "Auf Flugrouten pausieren",
  ["Alert when a watched buff drops"] = "Alarm, wenn ein überwachter Buff abfällt",
  ["Offer group buffs in a party or raid"] = "Gruppenbuffs in Gruppe oder Raid anbieten",
  ["Show out-of-range players (greyed)"] = "Spieler außer Reichweite anzeigen (grau)",
  ["Compact rows (no portraits)"] = "Kompakte Zeilen (ohne Porträts)",
  ["Per-character window position"] = "Fensterposition pro Charakter",
  ["~%dm left"] = "~%d Min. übrig",
  ["~%ds left"] = "~%d Sek. übrig",
  -- 1.8.0
  ["Grow the list upward"] = "Liste nach oben wachsen lassen",
  ["Two columns when the list is long"] = "Zwei Spalten, wenn die Liste lang ist",
  ["Print a recap when I die"] = "Zusammenfassung drucken, wenn ich sterbe",
  ["Print a report after a wipe"] = "Bericht nach einem Wipe drucken",
  ["Hide the window in combat"] = "Fenster im Kampf verstecken",
  ["pet"] = "Begleiter",
  ["drinking"] = "trinkt gerade",
  ["near"] = "in der Nähe",
  ["Watch group pets"] = "Gruppenbegleiter beobachten",
  ["Watch my aura or aspect"] = "Meine Aura / meinen Aspekt beobachten",
  ["Watch my world buffs"] = "Welt-Buffs auf mir beobachten",
  ["Mark healers who are drinking"] = "Heiler markieren, die gerade trinken",
  ["Show a name finder on the window"] = "Namenssuche im Fenster anzeigen",
}
