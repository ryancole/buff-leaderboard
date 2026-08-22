local ADDON_NAME, ns = ...

-- Main leaderboard window (/blb): recorded buffs down the left, the
-- selected buff's ladder on the right, with an all-time/session toggle.
-- Built lazily on first show, so SavedVariables and the character DB are
-- guaranteed to exist. Same ScrollBox idioms as Options.lua.

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
-- forgotten; cheap no-op while the window is closed
function ns.RefreshLeaderboard()
    if frame and frame:IsShown() then
        Refresh()
    end
end

-- Scrollable list clipped to an inset, per the Options.lua pattern
local function MakeScrollList(parent, rowInitializer)
    local container = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")

    local scrollBar = CreateFrame("EventFrame", nil, container, "MinimalScrollBar")
    scrollBar:SetPoint("TOPRIGHT", -10, -5)
    scrollBar:SetPoint("BOTTOMRIGHT", -10, 5)
    local scrollBox = CreateFrame("Frame", nil, container, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 2, -2)
    scrollBox:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMLEFT", -3, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(22)
    view:SetElementInitializer("Button", rowInitializer)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    return container, scrollBox
end

-- Left pane row: a buff name; clicking selects its ladder
local function InitBuffRow(row, buffName)
    row:SetPushedTextOffset(0, 0)
    row:SetHighlightAtlas("search-highlight")
    -- Gold for the selected buff, white for the rest
    row:SetNormalFontObject(
        buffName == selectedBuff and GameFontNormal or GameFontHighlight)
    row:SetText(buffName)
    local text = row:GetFontString()
    text:SetPoint("LEFT", 8, 0)
    text:SetPoint("RIGHT", -8, 0)
    text:SetJustifyH("LEFT")
    row:SetScript("OnClick", function()
        selectedBuff = buffName
        Refresh()
    end)
end

-- Right pane row: rank, class-colored caster, cast count
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
    row:SetText(("%s%d.|r %s%s|r"):format(
        rankColor, rank, ns.ClassColor(entry.class), display or "?"))
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

local function CreateWindow()
    -- Named so UISpecialFrames can close it with Escape
    frame = CreateFrame("Frame", "BuffLeaderboardFrame", UIParent, "BasicFrameTemplate")
    frame:SetSize(470, 400)
    frame:SetPoint("CENTER")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame.TitleText:SetText("Buff Leaderboard")
    tinsert(UISpecialFrames, "BuffLeaderboardFrame")

    local buffHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    buffHeader:SetPoint("TOPLEFT", 14, -32)
    buffHeader:SetText("Buffs")

    local buffList, buffScrollBox = MakeScrollList(frame, InitBuffRow)
    buffList:SetPoint("TOPLEFT", 10, -48)
    buffList:SetPoint("BOTTOMLEFT", 10, 34)
    buffList:SetWidth(150)
    frame.buffScrollBox = buffScrollBox

    frame.LadderHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.LadderHeader:SetPoint("TOPLEFT", buffHeader, "TOPLEFT", 156, 0)
    frame.LadderHeader:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    frame.LadderHeader:SetJustifyH("LEFT")

    local ladderList, ladderScrollBox = MakeScrollList(frame, InitLadderRow)
    ladderList:SetPoint("TOPLEFT", buffList, "TOPRIGHT", 6, 0)
    ladderList:SetPoint("BOTTOMRIGHT", -10, 34)
    frame.ladderScrollBox = ladderScrollBox

    frame.Empty = ladderList:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    frame.Empty:SetPoint("CENTER")
    frame.Empty:SetText("Nothing recorded yet")

    -- Scope toggle: all-time (default) vs this session
    local sessionCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
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
    local announce = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
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

    frame:SetScript("OnShow", Refresh)
    -- The frame is born visible, so OnShow doesn't fire for the first open
    Refresh()
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
