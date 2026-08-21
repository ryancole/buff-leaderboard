local ADDON_NAME, ns = ...

-- Canvas-style settings panel (Options -> AddOns -> Buff Leaderboard),
-- modeled on Syndicator's: freeform frame with our own widgets, and the
-- tracked-buff list in a fixed-height inset scroll box.

local function MakeCheckbox(parent, label, getter, setter)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    check:SetScript("OnClick", function(self)
        setter(self:GetChecked() and true or false)
    end)
    check:SetScript("OnShow", function(self)
        self:SetChecked(getter())
    end)
    local text = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetText(label)
    text:SetPoint("LEFT", check, "RIGHT", 5, 1)
    text:SetScript("OnMouseUp", function()
        check:Click()
    end)
    text:SetScript("OnEnter", function()
        check:LockHighlight()
    end)
    text:SetScript("OnLeave", function()
        check:UnlockHighlight()
    end)
    return check
end

-- Fixed-height scrollable list with one class-colored checkbox row per
-- tracked buff group, bound to BuffLeaderboardDB.options.spells.
local function MakeSpellList(parent)
    local container = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")

    local scrollBar = CreateFrame("EventFrame", nil, container, "MinimalScrollBar")
    scrollBar:SetPoint("TOPRIGHT", -10, -5)
    scrollBar:SetPoint("BOTTOMRIGHT", -10, 5)
    local scrollBox = CreateFrame("Frame", nil, container, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 2, -2)
    scrollBox:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMLEFT", -3, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(24)
    view:SetElementInitializer("Button", function(frame, elementData)
        frame:SetPushedTextOffset(0, 0)
        frame:SetHighlightAtlas("search-highlight")
        frame:SetNormalFontObject(GameFontHighlight)
        frame.group = elementData.group
        if not frame.Check then
            frame.Check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
            frame.Check:SetSize(22, 22)
            frame.Check:SetPoint("LEFT", 4, 0)
            frame.Check:SetScript("OnClick", function(self)
                BuffLeaderboardDB.options.spells[frame.group] = self:GetChecked() and true or false
            end)
            frame:SetScript("OnClick", function(self)
                self.Check:Click()
            end)
        end
        frame.Check:SetChecked(BuffLeaderboardDB.options.spells[elementData.group])
        frame:SetText(elementData.group)
        local text = frame:GetFontString()
        text:SetPoint("LEFT", 32, 0)
        text:SetPoint("RIGHT", -5, 0)
        text:SetJustifyH("LEFT")
        local color = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[elementData.class]
        if color then
            text:SetTextColor(color.r, color.g, color.b)
        else
            text:SetTextColor(1, 1, 1)
        end
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    -- Rebuilding the provider on show re-runs initializers, so check states
    -- always reflect the saved options
    container:SetScript("OnShow", function()
        scrollBox:SetDataProvider(CreateDataProvider(ns.spellGroups), true)
    end)

    return container
end

-- Called by Core.lua on ADDON_LOADED, after SavedVariables exist.
function ns.SetupOptions()
    local opts = BuffLeaderboardDB.options

    local panel = CreateFrame("Frame")
    panel:Hide()

    local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    header:SetPoint("TOPLEFT", 15, -10)
    header:SetText(NORMAL_FONT_COLOR:WrapTextInColorCode("Buff Leaderboard"))

    local version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
    local versionText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    versionText:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -5)
    versionText:SetText(WHITE_FONT_COLOR:WrapTextInColorCode(("Version: %s"):format(version or "dev")))

    local trackSelf = MakeCheckbox(panel, "Track self-casts",
        function() return opts.trackSelf end,
        function(v) opts.trackSelf = v end)
    trackSelf:SetPoint("TOPLEFT", versionText, "BOTTOMLEFT", -4, -10)

    local announce = MakeCheckbox(panel, "Announce tracked buffs in chat",
        function() return opts.announce end,
        function(v) opts.announce = v end)
    announce:SetPoint("TOPLEFT", trackSelf, "BOTTOMLEFT", 0, -2)

    local list = MakeSpellList(panel)
    list:SetPoint("TOPLEFT", announce, "BOTTOMLEFT", 4, -30)
    list:SetSize(320, 210)
    local listHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    listHeader:SetPoint("BOTTOMLEFT", list, "TOPLEFT", 0, 5)
    listHeader:SetText("Tracked Buffs")

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
