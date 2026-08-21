local ADDON_NAME, ns = ...

-- Registers the panel under Options -> AddOns. Called by Core.lua on
-- ADDON_LOADED, after SavedVariables (and BuffLeaderboardDB.options) exist.
function ns.SetupOptions()
    local opts = BuffLeaderboardDB.options

    local category = Settings.RegisterVerticalLayoutCategory("Buff Leaderboard")
    ns.settingsCategory = category

    do
        local setting = Settings.RegisterAddOnSetting(category,
            "BUFFLEADERBOARD_TRACK_SELF", "trackSelf", opts,
            Settings.VarType.Boolean, "Track self-casts", ns.optionDefaults.trackSelf)
        Settings.CreateCheckbox(category, setting,
            "Also count tracked buffs you cast on yourself, e.g. your own Soulstone.")
    end

    do
        local setting = Settings.RegisterAddOnSetting(category,
            "BUFFLEADERBOARD_ANNOUNCE", "announce", opts,
            Settings.VarType.Boolean, "Announce tracked buffs", ns.optionDefaults.announce)
        Settings.CreateCheckbox(category, setting,
            "Print a chat message whenever a tracked buff lands on you.")
    end

    Settings.RegisterAddOnCategory(category)
end

function ns.OpenOptions()
    if ns.settingsCategory then
        Settings.OpenToCategory(ns.settingsCategory:GetID())
    end
end
