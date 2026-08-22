local ADDON_NAME, ns = ...

local band = bit.band
local PLAYER_TYPE = COMBATLOG_OBJECT_TYPE_PLAYER

local playerGUID
local db -- this character's branch of BuffLeaderboardDB
local opts -- BuffLeaderboardDB.options (account-wide)
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

ns.optionDefaults = {
    trackSelf = false,     -- count tracked buffs you cast on yourself
    announce = false,      -- chat message when a tracked buff lands on you
    whisperThanks = false, -- whisper the caster their rank and total
}

local function InitDB()
    BuffLeaderboardDB = BuffLeaderboardDB or { version = 1, chars = {} }
    BuffLeaderboardDB.options = BuffLeaderboardDB.options or {}
    opts = BuffLeaderboardDB.options
    for k, v in next, ns.optionDefaults do
        if opts[k] == nil then
            opts[k] = v
        end
    end
    -- User-managed tracked list, keyed by lowercased buff name. Seeded from
    -- ns.defaultSpells only when absent; after that the saved list is
    -- authoritative and edited via the options panel or /blb track|untrack.
    if not opts.tracked then
        opts.tracked = {}
        local oldFlags = opts.spells -- pre-0.2 per-spell enable flags
        for _, name in ipairs(ns.defaultSpells) do
            local enabled = true
            if oldFlags and oldFlags[name] ~= nil then
                enabled = oldFlags[name]
            end
            opts.tracked[name:lower()] = {
                name = name,
                enabled = enabled,
                countRefresh = true, -- in TBC a REFRESH is always a re-cast
            }
        end
        opts.spells = nil
    end
end

-------------------------------------------------------------------------------
-- Tracked-list management (used by Options.lua and slash commands)
-------------------------------------------------------------------------------

local function ResolveSpellName(input)
    local id = tonumber(input)
    if not id then
        return input
    end
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(id)
    end
    return (GetSpellInfo(id))
end

-- Accepts a buff name or numeric spellId; returns ok, displayName/error
function ns.AddSpell(input)
    input = strtrim(input or "")
    if input == "" then
        return false, "enter a buff name or spell id"
    end
    local name = ResolveSpellName(input)
    if not name or name == "" then
        return false, ("unknown spell id %s"):format(input)
    end
    local key = name:lower()
    if opts.tracked[key] then
        return false, ("%s is already tracked"):format(name)
    end
    opts.tracked[key] = { name = name, enabled = true, countRefresh = true }
    return true, name
end

function ns.RemoveSpell(key)
    opts.tracked[key] = nil
end

-- Sorted array of tracked entries (live tables, with .key filled in)
function ns.GetTrackedList()
    local list = {}
    for key, entry in next, opts.tracked do
        entry.key = key
        list[#list + 1] = entry
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
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
    local allTimeTotal
    for _, store in ipairs({ db, session }) do
        local rec = GetCasterRecord(store, guid, sourceName)
        rec.total = rec.total + 1
        rec.spells[group] = (rec.spells[group] or 0) + 1
        allTimeTotal = allTimeTotal or rec.total -- db is first
    end
    return allTimeTotal
end

-- All-time rank of a caster: 1 + number of casters with a higher total
local function GetRank(guid)
    local mine = db.casters[guid]
    if not mine then return nil end
    local rank = 1
    for _, rec in next, db.casters do
        if rec.total > mine.total then
            rank = rank + 1
        end
    end
    return rank
end

local lastWhisper = {} -- [guid] = GetTime() of last thank-you whisper
local WHISPER_COOLDOWN = 300 -- at most one thank-you per caster per 5 min

local function OnCombatLogEvent()
    local _, subevent, _, sourceGUID, sourceName, sourceFlags, _,
        destGUID, _, _, _, _, spellName = CombatLogGetCurrentEventInfo()

    local mode = TRACKED[subevent]
    if not mode then return end
    if destGUID ~= playerGUID then return end
    if not spellName then return end

    -- Name matching: all ranks of a TBC spell share one name
    local spell = opts.tracked[spellName:lower()]
    if not spell or not spell.enabled then return end
    if mode ~= "always" and not spell[mode] then return end

    if not sourceGUID or not sourceName then return end
    -- Self-casts (soulstoning yourself, etc.) only if opted in
    if sourceGUID == playerGUID and not opts.trackSelf then return end
    -- Players only: drops pets, guardians, and NPC-applied copies
    if band(sourceFlags, PLAYER_TYPE) == 0 then return end

    local total = Record(sourceGUID, sourceName, spell.name)
    if opts.announce then
        local name = strsplit("-", sourceName)
        print(("|cff33ff99BuffLeaderboard|r: %s -> you: %s (x%d all-time)"):format(
            name, spell.name, total))
    end

    if opts.whisperThanks and sourceGUID ~= playerGUID then
        local now = GetTime()
        if not lastWhisper[sourceGUID] or now - lastWhisper[sourceGUID] > WHISPER_COOLDOWN then
            lastWhisper[sourceGUID] = now
            SendChatMessage(
                ("Thanks for %s! (your rank: %d, total casts: %d)"):format(
                    spell.name, GetRank(sourceGUID), total),
                "WHISPER", nil, sourceName)
        end
    end
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
            ns.SetupOptions()
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
ns.ClassColor = ClassColor -- shared with Options.lua for spell labels

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
    local cmd, arg = strsplit(" ", strtrim(msg or ""), 2)
    cmd = strlower(cmd)
    if cmd == "dump" or cmd == "" then
        Dump(arg and strlower(arg)) -- "session" or default all-time
    elseif cmd == "track" and arg then
        local ok, result = ns.AddSpell(arg)
        if ok then
            print(("|cff33ff99BuffLeaderboard|r: now tracking %s."):format(result))
        else
            print("|cff33ff99BuffLeaderboard|r: " .. result)
        end
    elseif cmd == "untrack" and arg then
        local key = strlower(strtrim(arg))
        local entry = BuffLeaderboardDB.options.tracked[key]
        if entry then
            ns.RemoveSpell(key)
            print(("|cff33ff99BuffLeaderboard|r: no longer tracking %s."):format(entry.name))
        else
            print(("|cff33ff99BuffLeaderboard|r: %s is not tracked."):format(arg))
        end
    elseif cmd == "reset" then
        if arg and strlower(arg) == "confirm" then
            wipe(db.casters)
            wipe(session.casters)
            print("|cff33ff99BuffLeaderboard|r: all-time data for this character reset.")
        else
            print("|cff33ff99BuffLeaderboard|r: this wipes all-time data for this character. Type |cffffff00/blb reset confirm|r to proceed.")
        end
    elseif cmd == "options" or cmd == "config" then
        ns.OpenOptions()
    elseif cmd == "show" or cmd == "hide" then
        print("|cff33ff99BuffLeaderboard|r: frame UI not built yet — use /blb dump.")
    else
        print("|cff33ff99BuffLeaderboard|r commands:")
        print("  /blb dump — all-time leaderboard")
        print("  /blb dump session — this session only")
        print("  /blb track <name or spell id> — add a buff to the tracked list")
        print("  /blb untrack <name> — remove a buff from the tracked list")
        print("  /blb options — open the settings panel")
        print("  /blb reset confirm — wipe this character's data")
    end
end
