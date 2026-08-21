local ADDON_NAME, ns = ...

-- Canvas-style settings panel (Options -> AddOns -> Buff Leaderboard),
-- modeled on Syndicator's: freeform frame with our own widgets, and the
-- tracked-buff list in a fixed-height inset scroll box with add/remove.

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

-- Fixed-height scrollable list of tracked buffs: enable checkbox, name,
-- delete button. Rows bind to the live entry tables in
-- BuffLeaderboardDB.options.tracked.
local function MakeSpellList(parent)
    local container = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")

    local scrollBar = CreateFrame("EventFrame", nil, container, "MinimalScrollBar")
    scrollBar:SetPoint("TOPRIGHT", -10, -5)
    scrollBar:SetPoint("BOTTOMRIGHT", -10, 5)
    local scrollBox = CreateFrame("Frame", nil, container, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 2, -2)
    scrollBox:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMLEFT", -3, 0)

    local function UpdateList()
        scrollBox:SetDataProvider(CreateDataProvider(ns.GetTrackedList()), true)
    end
    container.UpdateList = UpdateList

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(24)
    view:SetElementInitializer("Button", function(frame, elementData)
        frame:SetPushedTextOffset(0, 0)
        frame:SetHighlightAtlas("search-highlight")
        frame:SetNormalFontObject(GameFontHighlight)
        frame.entry = elementData
        if not frame.Check then
            frame.Check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
            frame.Check:SetSize(22, 22)
            frame.Check:SetPoint("LEFT", 4, 0)
            frame.Check:SetScript("OnClick", function(self)
                frame.entry.enabled = self:GetChecked() and true or false
            end)
            frame:SetScript("OnClick", function(self)
                self.Check:Click()
            end)

            frame.Delete = CreateFrame("Button", nil, frame)
            frame.Delete:SetNormalAtlas("transmog-icon-remove")
            frame.Delete:SetPoint("RIGHT", -5, 0)
            frame.Delete:SetSize(15, 15)
            frame.Delete:SetScript("OnClick", function()
                ns.RemoveSpell(frame.entry.key)
                GameTooltip:Hide()
                UpdateList()
            end)
            frame.Delete:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Stop tracking this buff")
                GameTooltip:Show()
                self:SetAlpha(0.5)
            end)
            frame.Delete:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
                self:SetAlpha(1)
            end)
        end
        frame.Check:SetChecked(elementData.enabled)
        frame:SetText(elementData.name)
        local text = frame:GetFontString()
        text:SetPoint("LEFT", 32, 0)
        text:SetPoint("RIGHT", -24, 0)
        text:SetJustifyH("LEFT")
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    -- Rebuilding the provider on show re-runs initializers, so check states
    -- always reflect the saved options
    container:SetScript("OnShow", UpdateList)

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

    local listHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    listHeader:SetPoint("TOPLEFT", announce, "BOTTOMLEFT", 4, -20)
    listHeader:SetText("Tracked Buffs")

    local list = MakeSpellList(panel)
    list:SetSize(320, 190)

    -- Add row: buff name or spell id + Add button, above the list
    local addBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    addBox:SetSize(240, 22)
    addBox:SetAutoFocus(false)
    addBox:SetPoint("TOPLEFT", listHeader, "BOTTOMLEFT", 6, -8)

    local addButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addButton:SetSize(70, 22)
    addButton:SetText("Add")
    addButton:SetPoint("LEFT", addBox, "RIGHT", 8, 0)

    local addHint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    addHint:SetPoint("TOPLEFT", addBox, "BOTTOMLEFT", -6, -4)
    addHint:SetText("Add a buff by exact name (all ranks match) or by spell id.")

    list:SetPoint("TOPLEFT", addHint, "BOTTOMLEFT", 0, -8)

    local function DoAdd()
        local ok, result = ns.AddSpell(addBox:GetText())
        if ok then
            addBox:SetText("")
            addBox:ClearFocus()
            list:UpdateList()
        else
            UIErrorsFrame:AddMessage(result, 1, 0.3, 0.3)
        end
    end
    addButton:SetScript("OnClick", DoAdd)
    addBox:SetScript("OnEnterPressed", DoAdd)
    addBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
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
