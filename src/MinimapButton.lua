local ADDON_NAME, ns = ...

-- Round minimap button: click toggles the leaderboard window, drag slides
-- it around the minimap rim. Hand-rolled instead of LibDBIcon so the addon
-- stays library-free; only the angle is saved (account-wide).

local BUTTON_RADIUS = 80 -- distance from the minimap center to the button

local button

-- Options-panel toggle; the saved flag is applied by the caller
function ns.SetMinimapButtonShown(shown)
    if button then
        button:SetShown(shown)
    end
end

local function SetAngle(degrees)
    local rad = math.rad(degrees)
    button:SetPoint("CENTER", Minimap, "CENTER",
        BUTTON_RADIUS * math.cos(rad), BUTTON_RADIUS * math.sin(rad))
end

-- Called by Core.lua on ADDON_LOADED, after SavedVariables exist.
function ns.SetupMinimapButton()
    local opts = BuffLeaderboardDB.options

    button = CreateFrame("Button", "BuffLeaderboardMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    SetAngle(opts.minimapAngle)
    button:SetShown(opts.minimapButton)

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -5)
    -- Pre-rounded 64x64 TGA baked from assets/logo.png; TGA loads on every
    -- client generation, and the circular alpha means no runtime mask
    icon:SetTexture("Interface\\AddOns\\" .. ADDON_NAME .. "\\assets\\minimap.tga")

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetScript("OnClick", function()
        ns.ToggleLeaderboard()
    end)

    -- While dragging, follow the cursor's angle around the minimap center
    local function OnDragUpdate(self)
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        opts.minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
        SetAngle(opts.minimapAngle)
    end
    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Buff Leaderboard")
        GameTooltip:AddLine("Click to toggle the leaderboard.", 1, 1, 1)
        GameTooltip:AddLine("Drag to move this button.", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end
