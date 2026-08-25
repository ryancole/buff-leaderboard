local ADDON_NAME, ns = ...

-- Main leaderboard window (/blb), paged by character-frame-style tabs
-- along the bottom edge: the leaderboard itself (recorded buffs down the
-- left, the selected buff's ladder on the right, with an all-time/session
-- toggle), the tracked-buff list, the recorded casters, and the options.
-- The management and options tabs use the same shared widgets as the
-- settings panel (Widgets.lua). Built lazily on first show, so
-- SavedVariables and the character DB are guaranteed to exist.

local frame
local selectedBuff -- display name of the buff whose ladder is shown
local sessionOnly = false

-- Gold/silver/bronze rank numbers for the podium spots
local RANK_COLORS = {
    [1] = "|cffffd700",
    [2] = "|cffc0c0c0",
    [3] = "|cffcd7f32",
}

local ANNOUNCE_TOP_N = 5

-- Channels offered by the announce menu; ones whose availability check
-- fails are shown disabled
local ANNOUNCE_CHANNELS = {
    { label = "Say",   chatType = "SAY" },
    { label = "Yell",  chatType = "YELL" },
    { label = "Party", chatType = "PARTY", available = IsInGroup },
    { label = "Raid",  chatType = "RAID",  available = IsInRaid },
    { label = "Guild", chatType = "GUILD", available = IsInGuild },
}

-- Sends the visible ladder's top entries to a chat channel, honoring the
-- window's current all-time/session scope. Plain text: chat strips
-- escape codes, so no class colors here.
local function AnnounceTop(chatType)
    if not selectedBuff then return end
    local ladder = ns.GetLadder(selectedBuff, sessionOnly)
    local n = math.min(#ladder, ANNOUNCE_TOP_N)
    if n == 0 then return end
    SendChatMessage(("Top %d %s casters on me (%s):"):format(
        n, selectedBuff, sessionOnly and "this session" or "all-time"), chatType)
    for i = 1, n do
        local entry = ladder[i]
        local display = entry.realm
            and (entry.name .. "-" .. entry.realm) or entry.name
        SendChatMessage(("%d. %s - %d casts"):format(
            i, display or "?", entry.count), chatType)
    end
end

local function Refresh()
    local buffs = ns.GetRecordedBuffs(sessionOnly)

    -- Keep the selection when possible, else fall back to the first buff
    local valid = false
    for _, name in ipairs(buffs) do
        if name == selectedBuff then
            valid = true
            break
        end
    end
    if not valid then
        selectedBuff = buffs[1]
    end

    frame.buffScrollBox:SetDataProvider(CreateDataProvider(buffs), true)
    local ladder = selectedBuff and ns.GetLadder(selectedBuff, sessionOnly) or {}
    frame.ladderScrollBox:SetDataProvider(CreateDataProvider(ladder), true)

    if selectedBuff then
        frame.LadderHeader:SetText(("%s — %s"):format(
            selectedBuff, sessionOnly and "this session" or "all-time"))
    else
        frame.LadderHeader:SetText(sessionOnly and "this session" or "all-time")
    end
    frame.Empty:SetShown(#buffs == 0)
    frame.AnnounceButton:SetEnabled(#ladder > 0)
end

-- Called by Core.lua whenever a tracked buff is recorded or a caster is
-- forgotten; cheap no-op while the window is closed. Only the visible tab
-- is refreshed — hidden tabs catch up via OnShow when selected. The
-- tracked-buff tab never changes from recording, so it needs neither.
function ns.RefreshLeaderboard()
    if not (frame and frame:IsShown()) then return end
    if frame.selectedTab == 1 then
        Refresh()
    elseif frame.selectedTab == 3 then
        frame.casterList.UpdateList()
    end
end

-- Left pane row: spell icon and buff name; clicking selects its ladder
local function InitBuffRow(row, buffName)
    row:SetPushedTextOffset(0, 0)
    row:SetHighlightAtlas("search-highlight")
    -- Gold for the selected buff, white for the rest
    row:SetNormalFontObject(
        buffName == selectedBuff and GameFontNormal or GameFontHighlight)
    -- Question mark until the buff's icon has been cached from a sighting,
    -- so names stay aligned either way
    local icon = ns.GetBuffIcon(buffName) or "Interface\\Icons\\INV_Misc_QuestionMark"
    row:SetText(("|T%s:16|t %s"):format(icon, buffName))
    local text = row:GetFontString()
    text:SetPoint("LEFT", 8, 0)
    text:SetPoint("RIGHT", -8, 0)
    text:SetJustifyH("LEFT")
    row:SetScript("OnClick", function()
        selectedBuff = buffName
        Refresh()
    end)
end

-- Inline escape for a caster's class icon, cropped out of the class
-- spritesheet. entry.class can be nil until the client has resolved the
-- caster's GUID (see Core.lua), so those rows get no icon.
local function ClassIcon(class)
    local coords = class and CLASS_ICON_TCOORDS[class]
    if not coords then return "" end
    return ("|TInterface\\TargetingFrame\\UI-Classes-Circles:14:14:0:0:256:256:%d:%d:%d:%d|t "):format(
        coords[1] * 256, coords[2] * 256, coords[3] * 256, coords[4] * 256)
end

-- Right pane row: rank, class icon, class-colored caster, cast count
local function InitLadderRow(row, entry)
    row:SetPushedTextOffset(0, 0)
    row:SetHighlightAtlas("search-highlight")
    row:SetNormalFontObject(GameFontHighlight)
    if not row.Count then
        row.Count = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.Count:SetPoint("RIGHT", -8, 0)
    end

    local rank = row:GetOrderIndex()
    local rankColor = RANK_COLORS[rank] or "|cffcccccc"
    local display = entry.realm and (entry.name .. "-" .. entry.realm) or entry.name
    row:SetText(("%s%d.|r %s%s%s|r"):format(
        rankColor, rank, ClassIcon(entry.class),
        ns.ClassColor(entry.class), display or "?"))
    local text = row:GetFontString()
    text:SetPoint("LEFT", 8, 0)
    text:SetPoint("RIGHT", row.Count, "LEFT", -8, 0)
    text:SetJustifyH("LEFT")
    row.Count:SetText(entry.count)

    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(display or "?")
        GameTooltip:AddLine(("Casts of %s: %d"):format(selectedBuff, entry.count),
            1, 1, 1)
        if entry.lastSeen then
            GameTooltip:AddLine(
                ("Last cast: %s"):format(date("%Y-%m-%d %H:%M", entry.lastSeen)),
                1, 1, 1)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- Tab 1: the leaderboard proper — buff list, ladder, scope toggle,
-- announce button
local function BuildLeaderboardPage(page)
    local buffHeader = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    buffHeader:SetPoint("TOPLEFT", 14, -8)
    buffHeader:SetText("Buffs")

    local buffList, buffScrollBox = ns.CreateScrollList(page, 22, InitBuffRow)
    buffList:SetPoint("TOPLEFT", 10, -24)
    buffList:SetPoint("BOTTOMLEFT", 10, 34)
    buffList:SetWidth(150)
    frame.buffScrollBox = buffScrollBox

    frame.LadderHeader = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.LadderHeader:SetPoint("TOPLEFT", buffHeader, "TOPLEFT", 156, 0)
    frame.LadderHeader:SetPoint("RIGHT", page, "RIGHT", -14, 0)
    frame.LadderHeader:SetJustifyH("LEFT")

    local ladderList, ladderScrollBox = ns.CreateScrollList(page, 22, InitLadderRow)
    ladderList:SetPoint("TOPLEFT", buffList, "TOPRIGHT", 6, 0)
    ladderList:SetPoint("BOTTOMRIGHT", -10, 34)
    frame.ladderScrollBox = ladderScrollBox

    frame.Empty = ladderList:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    frame.Empty:SetPoint("CENTER")
    frame.Empty:SetText("Nothing recorded yet")

    -- Scope toggle: all-time (default) vs this session
    local sessionCheck = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    sessionCheck:SetSize(26, 26)
    sessionCheck:SetPoint("BOTTOMLEFT", 8, 4)
    sessionCheck:SetChecked(sessionOnly)
    sessionCheck:SetScript("OnClick", function(self)
        sessionOnly = self:GetChecked() and true or false
        Refresh()
    end)
    local sessionLabel = sessionCheck:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    sessionLabel:SetText("This session only")
    sessionLabel:SetPoint("LEFT", sessionCheck, "RIGHT", 3, 1)

    -- Announce the selected buff's top casters; the channel is picked
    -- from a context menu so misclicks can't spam anything
    local announce = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    announce:SetSize(130, 22)
    announce:SetPoint("BOTTOMRIGHT", -8, 6)
    announce:SetText(("Announce Top %d"):format(ANNOUNCE_TOP_N))
    announce:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(owner, rootDescription)
            rootDescription:CreateTitle("Announce to")
            for _, channel in ipairs(ANNOUNCE_CHANNELS) do
                local button = rootDescription:CreateButton(channel.label, function()
                    AnnounceTop(channel.chatType)
                end)
                if channel.available and not channel.available() then
                    button:SetEnabled(false)
                end
            end
        end)
    end)
    frame.AnnounceButton = announce

    page:SetScript("OnShow", Refresh)
end

-- Tab 2: manage the tracked-buff list, mirroring the settings panel
local function BuildBuffsPage(page)
    local header = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 14, -10)
    header:SetText("Tracked Buffs")

    -- Add row: buff name or spell id + Add button, above the list
    local addBox = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    addBox:SetSize(250, 22)
    addBox:SetAutoFocus(false)
    addBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 6, -8)

    local addButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    addButton:SetSize(70, 22)
    addButton:SetText("Add")
    addButton:SetPoint("LEFT", addBox, "RIGHT", 8, 0)

    local addHint = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    addHint:SetPoint("TOPLEFT", addBox, "BOTTOMLEFT", -6, -4)
    addHint:SetText("Add a buff by exact name (all ranks match) or by spell id.")

    local list = ns.CreateSpellList(page)
    list:SetPoint("TOPLEFT", addHint, "BOTTOMLEFT", -4, -8)
    list:SetPoint("BOTTOMRIGHT", -10, 10)

    local function DoAdd()
        local ok, result = ns.AddSpell(addBox:GetText())
        if ok then
            addBox:SetText("")
            addBox:ClearFocus()
            list.UpdateList()
        else
            UIErrorsFrame:AddMessage(result, 1, 0.3, 0.3)
        end
    end
    addButton:SetScript("OnClick", DoAdd)
    addBox:SetScript("OnEnterPressed", DoAdd)
    addBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
end

-- Tab 4: the account-wide option checkboxes, mirroring the settings panel
local function BuildOptionsPage(page)
    local header = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 14, -10)
    header:SetText("Options")

    local checks = ns.CreateOptionChecks(page)
    checks:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
end

-- Tab 3: everyone recorded on this character, with forget and prune
local function BuildCastersPage(page)
    local header = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 14, -10)
    header:SetText("Recorded Casters")

    local casterList = ns.CreateCasterList(page)
    casterList:SetPoint("TOPLEFT", 10, -34)
    casterList:SetPoint("BOTTOMRIGHT", -10, 10)
    frame.casterList = casterList

    local prune = ns.CreatePruneButton(page, casterList)
    prune:SetPoint("LEFT", header, "RIGHT", 12, 0)
end

local function CreateWindow()
    -- Named so UISpecialFrames can close it with Escape
    frame = CreateFrame("Frame", "BuffLeaderboardFrame", UIParent, "BasicFrameTemplate")
    frame:SetSize(470, 400)
    -- Above center so the window sits over the empty upper screen rather
    -- than the character and action bars
    frame:SetPoint("CENTER", 0, 150)
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame.TitleText:SetText("Buff Leaderboard")
    tinsert(UISpecialFrames, "BuffLeaderboardFrame")

    -- One page frame per tab, covering the body below the title bar.
    -- Pages refresh themselves via OnShow, which also fires for the
    -- visible page whenever the window itself is reopened.
    frame.Pages = {}
    local function MakePage()
        local page = CreateFrame("Frame", nil, frame)
        page:SetPoint("TOPLEFT", 0, -24)
        page:SetPoint("BOTTOMRIGHT")
        page:Hide()
        frame.Pages[#frame.Pages + 1] = page
        return page
    end

    local function SelectTab(index)
        PanelTemplates_SetTab(frame, index) -- sets frame.selectedTab
        for i, page in ipairs(frame.Pages) do
            page:SetShown(i == index)
        end
    end

    -- Character-frame-style tabs hanging off the bottom edge. Global tab
    -- names follow the <frame name>Tab<n> convention PanelTemplates
    -- resolves buttons by.
    --
    -- The template's OnShow re-resizes each tab using the parent's
    -- tabPadding, defaulting to 24 when unset — which would regrow the
    -- tabs past our creation-time size every time the window is reopened.
    frame.tabPadding = 0
    local tabs = { "Leaderboard", "Tracked Buffs", "Casters", "Options" }
    local previousTab
    for i, label in ipairs(tabs) do
        local tab = CreateFrame("Button", "BuffLeaderboardFrameTab" .. i, frame,
            "PanelTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(label)
        if previousTab then
            tab:SetPoint("TOPLEFT", previousTab, "TOPRIGHT", -15, 0)
        else
            tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 11, 2)
        end
        tab:SetScript("OnClick", function(self)
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
            SelectTab(self:GetID())
        end)
        PanelTemplates_TabResize(tab, 0)
        previousTab = tab
    end
    PanelTemplates_SetNumTabs(frame, #tabs)

    BuildLeaderboardPage(MakePage())
    BuildBuffsPage(MakePage())
    BuildCastersPage(MakePage())
    BuildOptionsPage(MakePage())

    -- The frame is born visible, so showing page 1 fires its OnShow and
    -- runs the first Refresh
    SelectTab(1)
end

function ns.ShowLeaderboard()
    if not frame then
        CreateWindow()
    end
    frame:Show() -- OnShow refreshes
end

function ns.HideLeaderboard()
    if frame then
        frame:Hide()
    end
end

function ns.ToggleLeaderboard()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        ns.ShowLeaderboard()
    end
end
