local ADDON_NAME, ns = ...

-- Widgets shared by the leaderboard window's tabs and the settings
-- panel: an inset ScrollBox factory, the tracked-buff and recorded-caster
-- lists (each with per-row remove buttons), the confirm-guarded prune
-- button, and the stack of option checkboxes.

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
    check.Text = text
    text:SetText(label)
    text:SetPoint("LEFT", check, "RIGHT", 5, 1)
    text:SetScript("OnMouseUp", function()
        if check:IsEnabled() then
            check:Click()
        end
    end)
    text:SetScript("OnEnter", function()
        if check:IsEnabled() then
            check:LockHighlight()
        end
    end)
    text:SetScript("OnLeave", function()
        check:UnlockHighlight()
    end)
    return check
end

-- The account-wide option checkboxes, stacked in a container sized to
-- its content. Check states re-read from the saved options on every
-- show, so the settings panel and the window's Options tab stay in sync.
function ns.CreateOptionChecks(parent)
    local opts = BuffLeaderboardDB.options
    local container = CreateFrame("Frame", nil, parent)

    -- A dependsOn entry is a sub-option: indented under its parent and
    -- greyed out (value kept, just not editable) while the parent is off
    local defs = {
        { "Track self-casts", "trackSelf" },
        { "Track buffs only while in a group (party or raid)", "groupOnly" },
        { "Print tracked buffs to your chat window", "announce" },
        { "Whisper casters a thank-you with their rank and total", "whisperThanks" },
        { "Only whisper on special events (overtakes, cast milestones)",
            "whisperSpecialOnly", dependsOn = "whisperThanks" },
        { "Auto-reply to !rank whispers with the sender's rank", "rankReplies" },
        { "Show minimap button", "minimapButton",
            function(v) ns.SetMinimapButtonShown(v) end },
    }

    local checks = {}
    local function UpdateDependents()
        for i, def in ipairs(defs) do
            if def.dependsOn then
                local enabled = opts[def.dependsOn] and true or false
                checks[i]:SetEnabled(enabled)
                checks[i].Text:SetFontObject(
                    enabled and GameFontHighlight or GameFontDisable)
            end
        end
    end

    for i, def in ipairs(defs) do
        local label, key, onChange = def[1], def[2], def[3]
        local check = MakeCheckbox(container, label,
            function() return opts[key] end,
            function(v)
                opts[key] = v
                if onChange then onChange(v) end
                UpdateDependents()
            end)
        -- 26px checkboxes on a 28px pitch
        check:SetPoint("TOPLEFT", def.dependsOn and 20 or 0, -(i - 1) * 28)
        checks[i] = check
    end
    container:SetScript("OnShow", UpdateDependents)

    -- Labels overhang the width freely
    container:SetSize(340, #defs * 28 - 2)

    return container
end

-- Scrollable list clipped to an inset. Rows are Buttons of the given
-- height, set up by rowInitializer(row, elementData).
function ns.CreateScrollList(parent, extent, rowInitializer)
    local container = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")

    local scrollBar = CreateFrame("EventFrame", nil, container, "MinimalScrollBar")
    scrollBar:SetPoint("TOPRIGHT", -10, -5)
    scrollBar:SetPoint("BOTTOMRIGHT", -10, 5)
    local scrollBox = CreateFrame("Frame", nil, container, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 2, -2)
    scrollBox:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMLEFT", -3, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(extent)
    view:SetElementInitializer("Button", rowInitializer)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    return container, scrollBox
end

-- Scrollable list of tracked buffs: enable checkbox, name, delete button.
-- Rows bind to the live entry tables in BuffLeaderboardDB.options.tracked.
function ns.CreateSpellList(parent)
    local container, scrollBox

    local function UpdateList()
        scrollBox:SetDataProvider(CreateDataProvider(ns.GetTrackedList()), true)
    end

    container, scrollBox = ns.CreateScrollList(parent, 24, function(row, elementData)
        row:SetPushedTextOffset(0, 0)
        row:SetHighlightAtlas("search-highlight")
        row:SetNormalFontObject(GameFontHighlight)
        row.entry = elementData
        if not row.Check then
            row.Check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.Check:SetSize(22, 22)
            row.Check:SetPoint("LEFT", 4, 0)
            row.Check:SetScript("OnClick", function(self)
                row.entry.enabled = self:GetChecked() and true or false
            end)
            row:SetScript("OnClick", function(self)
                self.Check:Click()
            end)

            row.Delete = CreateFrame("Button", nil, row)
            row.Delete:SetNormalAtlas("transmog-icon-remove")
            row.Delete:SetPoint("RIGHT", -5, 0)
            row.Delete:SetSize(15, 15)
            row.Delete:SetScript("OnClick", function()
                ns.RemoveSpell(row.entry.key)
                GameTooltip:Hide()
                UpdateList()
            end)
            row.Delete:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Stop tracking this buff")
                GameTooltip:Show()
                self:SetAlpha(0.5)
            end)
            row.Delete:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
                self:SetAlpha(1)
            end)
        end
        row.Check:SetChecked(elementData.enabled)
        row:SetText(elementData.name)
        local text = row:GetFontString()
        text:SetPoint("LEFT", 32, 0)
        text:SetPoint("RIGHT", -24, 0)
        text:SetJustifyH("LEFT")
    end)
    container.UpdateList = UpdateList

    -- Rebuilding the provider on show re-runs initializers, so check states
    -- always reflect the saved options
    container:SetScript("OnShow", UpdateList)

    return container
end

-- Scrollable list of recorded casters in alphabetical order, with a
-- forget button per row to reset that player's rank and history.
function ns.CreateCasterList(parent)
    local container, scrollBox

    local function UpdateList()
        scrollBox:SetDataProvider(CreateDataProvider(ns.GetCasterList()), true)
    end

    container, scrollBox = ns.CreateScrollList(parent, 24, function(row, elementData)
        row:SetPushedTextOffset(0, 0)
        row:SetHighlightAtlas("search-highlight")
        row:SetNormalFontObject(GameFontHighlight)
        row.guid = elementData.guid
        if not row.Delete then
            row.Delete = CreateFrame("Button", nil, row)
            row.Delete:SetNormalAtlas("transmog-icon-remove")
            row.Delete:SetPoint("RIGHT", -5, 0)
            row.Delete:SetSize(15, 15)
            row.Delete:SetScript("OnClick", function()
                ns.ForgetCaster(row.guid)
                GameTooltip:Hide()
                UpdateList()
            end)
            row.Delete:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Forget this player (resets their rank and history)")
                GameTooltip:Show()
                self:SetAlpha(0.5)
            end)
            row.Delete:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
                self:SetAlpha(1)
            end)
        end
        local display = elementData.realm
            and (elementData.name .. "-" .. elementData.realm)
            or elementData.name
        row:SetText(("%s (%d)"):format(display or "?", elementData.total))
        local text = row:GetFontString()
        text:SetPoint("LEFT", 8, 0)
        text:SetPoint("RIGHT", -24, 0)
        text:SetJustifyH("LEFT")
    end)
    container.UpdateList = UpdateList

    container:SetScript("OnShow", UpdateList)

    return container
end

-- Bulk prune of casters who stopped playing with you. Unlike the per-row
-- forget button, one click can wipe a whole roster of names, so it
-- confirms via popup first. The popup's data is the caster list next to
-- whichever button opened it; other lists catch up via their OnShow.
StaticPopupDialogs["BUFFLEADERBOARD_PRUNE"] = {
    text = ("Forget %%d caster%%s not seen in the last %d days?"):format(ns.PRUNE_DAYS),
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data)
        local n = ns.PruneCasters()
        print(("|cff33ff99BuffLeaderboard|r: forgot %d inactive caster%s."):format(
            n, n == 1 and "" or "s"))
        data.UpdateList()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function ns.CreatePruneButton(parent, casterList)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(110, 22)
    button:SetText("Prune Inactive")
    button:SetScript("OnClick", function()
        local n = ns.CountInactiveCasters()
        if n == 0 then
            UIErrorsFrame:AddMessage(
                ("no casters have gone unseen for %d+ days"):format(ns.PRUNE_DAYS), 1, 0.3, 0.3)
        else
            StaticPopup_Show("BUFFLEADERBOARD_PRUNE", n, n == 1 and "" or "s", casterList)
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(("Forget casters not seen in the last %d days"):format(ns.PRUNE_DAYS))
        local n = ns.CountInactiveCasters()
        GameTooltip:AddLine(("Would forget %d caster%s right now"):format(
            n, n == 1 and "" or "s"), 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return button
end
