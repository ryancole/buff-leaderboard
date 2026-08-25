local ADDON_NAME, ns = ...

-- Canvas-style settings panel (Options -> AddOns -> Buff Leaderboard),
-- modeled on Syndicator's: freeform frame with the shared option
-- checkboxes from Widgets.lua. The tracked-buff and recorded-caster
-- lists live in the leaderboard window's tabs; the panel just points
-- there.

-- Called by Core.lua on ADDON_LOADED, after SavedVariables exist.
function ns.SetupOptions()
    local panel = CreateFrame("Frame")
    panel:Hide()

    local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    header:SetPoint("TOPLEFT", 15, -10)
    header:SetText(NORMAL_FONT_COLOR:WrapTextInColorCode("Buff Leaderboard"))

    -- Substituted by the packager at release; raw keyword means a dev copy
    local version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
    if not version or version:find("@") then
        version = "dev"
    end
    local versionText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    versionText:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -5)
    versionText:SetText(WHITE_FONT_COLOR:WrapTextInColorCode(("Version: %s"):format(version or "dev")))

    local checks = ns.CreateOptionChecks(panel)
    checks:SetPoint("TOPLEFT", versionText, "BOTTOMLEFT", -4, -10)

    -- Tracked buffs and recorded casters moved to the leaderboard
    -- window's tabs; leave a pointer for anyone looking here for them
    local listsHint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    listsHint:SetPoint("TOPLEFT", checks, "BOTTOMLEFT", 4, -20)
    listsHint:SetText("Tracked buffs and recorded casters are managed in the leaderboard window (/blb).")

    local openButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    openButton:SetSize(140, 22)
    openButton:SetText("Open Leaderboard")
    openButton:SetPoint("TOPLEFT", listsHint, "BOTTOMLEFT", 0, -8)
    openButton:SetScript("OnClick", function()
        HideUIPanel(SettingsPanel) -- the window would open underneath it
        ns.ShowLeaderboard()
    end)

    -- Required no-op handlers for canvas settings panels
    panel.OnCommit = function() end
    panel.OnDefault = function() end
    panel.OnRefresh = function() end

    local category = Settings.RegisterCanvasLayoutCategory(panel, "Buff Leaderboard")
    ns.settingsCategory = category
    Settings.RegisterAddOnCategory(category)
end

function ns.OpenOptions()
    if ns.settingsCategory then
        Settings.OpenToCategory(ns.settingsCategory:GetID())
    end
end
