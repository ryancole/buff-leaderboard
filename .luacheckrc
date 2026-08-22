-- Check against WoW's Lua dialect: 5.1 syntax and stdlib. luacheck itself
-- may run on any Lua version; this is what it validates *against*.
std = "lua51"

max_line_length = false

ignore = {
    "211/ADDON_NAME", -- every file destructures ...; not all use the name
    "211/_",          -- discarded values
    "212",            -- unused arguments (self in handlers, etc.)
    "213/_",          -- discarded loop variables
}

-- Globals this addon is allowed to create or assign
globals = {
    "BuffLeaderboardDB", -- SavedVariables
    "SLASH_BUFFLEADERBOARD1",
    "SLASH_BUFFLEADERBOARD2",
    "SlashCmdList",
}

-- WoW-provided API, read-only
read_globals = {
    -- Lua extensions in the WoW environment
    "bit", "date", "time", "strlower", "strsplit", "strtrim", "tinsert",
    "wipe",
    -- API functions
    "CombatLogGetCurrentEventInfo", "CreateFrame", "GetPlayerInfoByGUID",
    "GetRealmName", "GetSpellInfo", "GetTime", "IsInGroup", "IsInGuild",
    "IsInRaid", "SendChatMessage", "UnitGUID", "UnitName",
    -- Namespaces
    "C_AddOns", "C_Spell", "MenuUtil", "Settings",
    -- ScrollBox utilities
    "CreateDataProvider", "CreateScrollBoxListLinearView", "ScrollUtil",
    -- Frames, fonts, and constants
    "COMBATLOG_OBJECT_TYPE_PLAYER", "GameFontHighlight", "GameFontNormal",
    "GameTooltip", "NORMAL_FONT_COLOR", "RAID_CLASS_COLORS", "UIErrorsFrame",
    "UIParent", "UISpecialFrames", "WHITE_FONT_COLOR",
}
