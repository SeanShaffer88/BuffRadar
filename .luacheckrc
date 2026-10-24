-- luacheck settings for BuffRadar (run through tools\check.ps1).
-- WoW runs Lua 5.1.
std = "lua51"
max_line_length = false

-- The game's API is hundreds of globals luacheck doesn't know, so reading an
-- unknown global (warning 113) is allowed. Creating or changing one is still
-- reported: that catches accidental globals, like the RefreshMinimapButton
-- leak fixed in 1.3.2. These are the globals BuffRadar is meant to create:
globals = {
  "BuffRadarDB",                                     -- saved variables (.toc)
  "BuffRadarLocales",                                -- filled by Locales\*.lua
  "BuffRadar_ToggleWindow", "BuffRadar_ToggleSound", -- called by Bindings.xml
  "SLASH_BUFFRADAR1", "SLASH_BUFFRADAR2",            -- /br, /buffradar
  "SlashCmdList",                                    -- SlashCmdList.BUFFRADAR
  "BINDING_HEADER_BUFFRADAR", "BINDING_CATEGORY_BUFFRADAR",
  "BINDING_NAME_BUFFRADAR_TOGGLE", "BINDING_NAME_BUFFRADAR_MUTE",
  "UISpecialFrames",                                 -- Esc closes the settings window
  "ColorPickerFrame",  -- older clients' color picker is set up through its fields
}
ignore = { "113" }
