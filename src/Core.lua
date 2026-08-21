local ADDON_NAME, ns = ...

local band = bit.band
local PLAYER_TYPE = COMBATLOG_OBJECT_TYPE_PLAYER

local playerGUID
local db -- this character's branch of BuffLeaderboardDB
local session = { casters = {} } -- in-memory only, same shape as db
ns.session = session

-- Subevent -> which whitelist flag gates it ("always" for plain applies)
local TRACKED = {
    SPELL_AURA_APPLIED = "always",
    SPELL_AURA_REFRESH = "countRefresh",
    SPELL_AURA_APPLIED_DOSE = "countDose",
}

-------------------------------------------------------------------------------
-- SavedVariables
-------------------------------------------------------------------------------
-- Account-wide file, bucketed per character GUID so alts don't mix and a
-- cross-character view stays possible later.
--
-- BuffLeaderboardDB = {
--   version = 1,
--   chars = {
--     [playerGUID] = {
--       name, realm,
--       casters = {
--         [casterGUID] = { name, realm, class, total, lastSeen,
--                          spells = { [group] = count } },
--       },
--     },
--   },
-- }

local function InitDB()
    BuffLeaderboardDB = BuffLeaderboardDB or { version = 1, chars = {} }
end

local function InitChar()
    playerGUID = UnitGUID("player")
    local chars = BuffLeaderboardDB.chars
    chars[playerGUID] = chars[playerGUID] or {
        name = UnitName("player"),
        realm = GetRealmName(),
        casters = {},
    }
    db = chars[playerGUID]
end

-------------------------------------------------------------------------------
-- Recording
-------------------------------------------------------------------------------

local function GetCasterRecord(store, guid, sourceName)
    local rec = store.casters[guid]
    if not rec then
        rec = { total = 0, spells = {} }
        store.casters[guid] = rec
    end
    -- GUID is the stable key; name/realm are display data refreshed on every
    -- hit, since same-realm sources arrive without the "-Realm" suffix.
    local name, realm = strsplit("-", sourceName)
    rec.name = name
    rec.realm = realm or rec.realm -- keep an earlier suffixed sighting
    if not rec.class then
        -- May return nil until the client has resolved the GUID; retried on
        -- the next application from the same caster.
        local _, class = GetPlayerInfoByGUID(guid)
        rec.class = class
    end
    rec.lastSeen = time()
    return rec
end

local function Record(guid, sourceName, group)
    for _, store in ipairs({ db, session }) do
        local rec = GetCasterRecord(store, guid, sourceName)
        rec.total = rec.total + 1
        rec.spells[group] = (rec.spells[group] or 0) + 1
    end
end

local function OnCombatLogEvent()
    local _, subevent, _, sourceGUID, sourceName, sourceFlags, _,
        destGUID, _, _, _, spellId = CombatLogGetCurrentEventInfo()

    local mode = TRACKED[subevent]
    if not mode then return end
    if destGUID ~= playerGUID then return end

    local spell = ns.spells[spellId]
    if not spell then return end
    if mode ~= "always" and not spell[mode] then return end

    -- Self-casts excluded entirely for now (soulstoning yourself, etc.)
    if not sourceGUID or sourceGUID == playerGUID then return end
    if not sourceName then return end
    -- Players only: drops pets, guardians, and NPC-applied copies
    if band(sourceFlags, PLAYER_TYPE) == 0 then return end

    Record(sourceGUID, sourceName, spell.group)
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            InitDB()
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        InitChar()
        self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLogEvent()
    end
end)

-------------------------------------------------------------------------------
-- Slash commands (chat dump until the frame UI lands)
-------------------------------------------------------------------------------

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS[class]
    if c then
        return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
    end
    return "|cffcccccc"
end

local function Dump(scope)
    local store = (scope == "session") and session or db
    local list = {}
    for _, rec in next, store.casters do
        list[#list + 1] = rec
    end
    table.sort(list, function(a, b) return a.total > b.total end)

    print(("|cff33ff99BuffLeaderboard|r — %s:"):format(
        scope == "session" and "this session" or "all-time"))
    if #list == 0 then
        print("  (nothing recorded yet)")
        return
    end
    for i, rec in ipairs(list) do
        local display = rec.realm and (rec.name .. "-" .. rec.realm) or rec.name
        local parts = {}
        for group, count in next, rec.spells do
            parts[#parts + 1] = ("%s x%d"):format(group, count)
        end
        table.sort(parts)
        print(("  %d. %s%s|r — %d  (%s)"):format(
            i, ClassColor(rec.class), display or "?", rec.total,
            table.concat(parts, ", ")))
    end
end

SLASH_BUFFLEADERBOARD1 = "/blb"
SLASH_BUFFLEADERBOARD2 = "/buffleaderboard"
SlashCmdList.BUFFLEADERBOARD = function(msg)
    local cmd, arg = strsplit(" ", strlower(strtrim(msg or "")), 2)
    if cmd == "dump" or cmd == "" then
        Dump(arg) -- "session" or default all-time
    elseif cmd == "reset" then
        if arg == "confirm" then
            wipe(db.casters)
            wipe(session.casters)
            print("|cff33ff99BuffLeaderboard|r: all-time data for this character reset.")
        else
            print("|cff33ff99BuffLeaderboard|r: this wipes all-time data for this character. Type |cffffff00/blb reset confirm|r to proceed.")
        end
    elseif cmd == "show" or cmd == "hide" then
        print("|cff33ff99BuffLeaderboard|r: frame UI not built yet — use /blb dump.")
    else
        print("|cff33ff99BuffLeaderboard|r commands:")
        print("  /blb dump — all-time leaderboard")
        print("  /blb dump session — this session only")
        print("  /blb reset confirm — wipe this character's data")
    end
end
