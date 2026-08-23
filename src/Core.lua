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
    rankReplies = false,   -- auto-reply to "!rank" whispers with the sender's rank
    minimapAngle = 220,    -- minimap button position, degrees around the rim
    minimapButton = true,  -- show the minimap button
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

-- Recorded casters for the options panel, alphabetical (there is no
-- combined ladder; ranks are per-buff). db is nil until PLAYER_LOGIN, but
-- the panel can only be opened after that.
function ns.GetCasterList()
    local list = {}
    if not db then return list end
    for guid, rec in next, db.casters do
        list[#list + 1] = {
            guid = guid,
            name = rec.name,
            realm = rec.realm,
            total = rec.total,
        }
    end
    table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
    return list
end

-- Drops a player from this character's leaderboard (all-time and session)
function ns.ForgetCaster(guid)
    if db then
        db.casters[guid] = nil
    end
    session.casters[guid] = nil
    ns.RefreshLeaderboard()
end

-- Buff names with at least one recorded cast, alphabetical. These come
-- from history, not the tracked list, so ladders survive untracking.
function ns.GetRecordedBuffs(sessionOnly)
    local store = sessionOnly and session or db
    local seen, list = {}, {}
    if store then
        for _, rec in next, store.casters do
            for name in next, rec.spells do
                if not seen[name] then
                    seen[name] = true
                    list[#list + 1] = name
                end
            end
        end
    end
    table.sort(list)
    return list
end

-- Ladder for one buff, most casts first; ties break alphabetically
function ns.GetLadder(spellName, sessionOnly)
    local store = sessionOnly and session or db
    local list = {}
    if store then
        for _, rec in next, store.casters do
            local count = rec.spells[spellName]
            if count then
                list[#list + 1] = {
                    name = rec.name,
                    realm = rec.realm,
                    class = rec.class,
                    count = count,
                    lastSeen = rec.lastSeen,
                }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then
            return a.count > b.count
        end
        return (a.name or "") < (b.name or "")
    end)
    return list
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

-- All-time rank of a caster for one buff, by that buff's cast count.
-- Per-buff ladders are the only ranking concept; there is no combined rank.
local function GetSpellRank(guid, spellName)
    local mine = db.casters[guid]
    local mineCount = mine and mine.spells[spellName]
    if not mineCount then return nil end
    local rank = 1
    for _, rec in next, db.casters do
        if (rec.spells[spellName] or 0) > mineCount then
            rank = rank + 1
        end
    end
    return rank
end

-- One-line ladder excerpt for a buff: the #1 caster, the sender's immediate
-- neighbors, and the sender themselves, in ladder order, e.g.
-- "Innervate: #1 Moonpriest (x50) ... #4 Baddruid (x12), #5 you (x10),
-- #6 Weakdruid (x9)". Ranks are by cast count (ties share a rank, matching
-- GetSpellRank); "..." marks skipped entries between #1 and the sender's
-- neighborhood. nil if the sender isn't on that ladder.
local function FormatRankContext(guid, spellName)
    local ladder = {}
    for g, rec in next, db.casters do
        local count = rec.spells[spellName]
        if count then
            ladder[#ladder + 1] = { guid = g, name = rec.name, count = count }
        end
    end
    table.sort(ladder, function(a, b)
        if a.count ~= b.count then
            return a.count > b.count
        end
        return (a.name or "") < (b.name or "")
    end)

    local mine
    for i, entry in ipairs(ladder) do
        entry.rank = (i > 1 and entry.count == ladder[i - 1].count)
            and ladder[i - 1].rank or i
        if entry.guid == guid then mine = i end
    end
    if not mine then return nil end

    local show = { 1 }
    if mine - 1 > 1 then show[#show + 1] = mine - 1 end
    if mine > 1 then show[#show + 1] = mine end
    if mine < #ladder then show[#show + 1] = mine + 1 end

    local reply, prev = spellName .. ":", nil
    for _, i in ipairs(show) do
        local entry = ladder[i]
        local who = entry.guid == guid and "you" or entry.name
        local piece = ("#%d %s (x%d)"):format(entry.rank, who, entry.count)
        if not prev then
            reply = reply .. " " .. piece
        elseif i - prev > 1 then
            reply = reply .. " ... " .. piece
        else
            reply = reply .. ", " .. piece
        end
        prev = i
    end
    return reply
end

local lastWhisper = {} -- [guid] = GetTime() of last thank-you whisper
local WHISPER_COOLDOWN = 300 -- at most one thank-you per caster per 5 min

-- Cast counts worth celebrating in the thank-you whisper: the early ones
-- land quickly enough to hook people, then every 100th. Every milestone
-- ends in 0 or 5, so the "th" suffix is always correct.
local function IsMilestone(count)
    if count == 10 or count == 25 or count == 50 then return true end
    return count >= 100 and count % 100 == 0
end

local lastRankReply = {} -- [guid] = GetTime() of last !rank auto-reply
local RANK_REPLY_COOLDOWN = 30 -- per sender, so !rank can't be spammed

-- Incoming whisper: reply to "!rank" with a ladder excerpt for every buff
-- the sender appears on (one whisper each), or "!rank <buff>" for just that
-- buff. Excerpts show #1 plus the sender's immediate neighbors for context.
local function OnWhisper(text, sender, guid)
    if not opts.rankReplies then return end
    text = strlower(strtrim(text or ""))
    if text ~= "!rank" and not text:match("^!rank%s") then return end
    if not guid or guid == playerGUID then return end

    local now = GetTime()
    if lastRankReply[guid] and now - lastRankReply[guid] < RANK_REPLY_COOLDOWN then
        return
    end
    lastRankReply[guid] = now

    local rec = db and db.casters[guid]
    if not rec then
        SendChatMessage("You haven't cast any tracked buffs on me yet!",
            "WHISPER", nil, sender)
        return
    end

    local spellArg = strtrim(text:sub(6))
    if spellArg == "" then
        -- One excerpt per buff ladder they appear on, biggest count first.
        -- Each fits a whisper on its own; rec.spells is bounded by the
        -- tracked list, so this stays a handful of lines at most.
        local ranks = {}
        for name, count in next, rec.spells do
            ranks[#ranks + 1] = { name = name, count = count }
        end
        table.sort(ranks, function(a, b) return a.count > b.count end)
        for _, entry in ipairs(ranks) do
            SendChatMessage(FormatRankContext(guid, entry.name),
                "WHISPER", nil, sender)
        end
        return
    end

    -- Case-insensitive match against the buffs they have actually cast
    for name in next, rec.spells do
        if strlower(name) == spellArg then
            SendChatMessage(FormatRankContext(guid, name),
                "WHISPER", nil, sender)
            return
        end
    end
    SendChatMessage("You haven't cast that buff on me yet!", "WHISPER", nil, sender)
end

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

    -- Ranks, overtakes, and whispers are all per-buff: "who Innervates me
    -- the most" rather than one combined ladder
    local casterRec = db.casters[sourceGUID]
    local oldCount = casterRec and casterRec.spells[spell.name] or 0
    Record(sourceGUID, sourceName, spell.name)
    local count = oldCount + 1
    ns.RefreshLeaderboard() -- no-op unless the window is open

    -- Overtake detection: rank is 1 + count of strictly-higher counts for
    -- this buff, so going from oldCount to oldCount+1 passes exactly the
    -- players still sitting at oldCount
    local passed
    if oldCount > 0 then
        for guid, rec in next, db.casters do
            if guid ~= sourceGUID and (rec.spells[spell.name] or 0) == oldCount then
                passed = passed or {}
                passed[#passed + 1] = rec.name or "?"
            end
        end
        if passed then
            table.sort(passed)
        end
    end

    if opts.announce then
        local name = strsplit("-", sourceName)
        local msg = ("|cff33ff99BuffLeaderboard|r: %s -> you: %s (x%d)"):format(
            name, spell.name, count)
        if passed then
            msg = ("%s - overtakes %s for %s rank %d!"):format(
                msg, table.concat(passed, ", "), spell.name,
                GetSpellRank(sourceGUID, spell.name))
        end
        print(msg)
    end

    -- Overtakes landing during the cooldown window go unmentioned by design.
    -- Milestones bypass the cooldown: they're rare by construction, so they
    -- can't spam, and a 100th cast shouldn't go uncelebrated.
    if opts.whisperThanks and sourceGUID ~= playerGUID then
        local now = GetTime()
        local milestone = IsMilestone(count)
        if milestone or not lastWhisper[sourceGUID]
            or now - lastWhisper[sourceGUID] > WHISPER_COOLDOWN then
            lastWhisper[sourceGUID] = now
            local details = ("your %s rank: %d, casts: %d"):format(
                spell.name, GetSpellRank(sourceGUID, spell.name), count)
            if passed then
                details = ("%s, overtook: %s"):format(details, table.concat(passed, ", "))
            end
            local thanks = milestone
                and ("That's your %dth %s on me!"):format(count, spell.name)
                or ("Thanks for %s!"):format(spell.name)
            SendChatMessage(
                ("%s (%s)"):format(thanks, details),
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
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLogEvent()
    elseif event == "CHAT_MSG_WHISPER" then
        local text, sender = ...
        OnWhisper(text, sender, select(12, ...)) -- arg 12 is the sender GUID
    elseif event == "ADDON_LOADED" then
        if ... == ADDON_NAME then
            InitDB()
            ns.SetupOptions()
            ns.SetupMinimapButton()
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        InitChar()
        self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        self:RegisterEvent("CHAT_MSG_WHISPER")
    end
end)

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS[class]
    if c then
        return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
    end
    return "|cffcccccc"
end
ns.ClassColor = ClassColor -- shared with Options.lua for spell labels

-- All-time leaderboard for a single buff, matched case-insensitively
local function DumpSpell(filter)
    local lowerFilter = strlower(filter)
    local displayName
    local list = {}
    for _, rec in next, db.casters do
        for name, count in next, rec.spells do
            if strlower(name) == lowerFilter then
                displayName = name
                list[#list + 1] = { rec = rec, count = count }
            end
        end
    end
    if not displayName then
        print(("|cff33ff99BuffLeaderboard|r: no recorded casts of \"%s\"."):format(filter))
        return
    end
    table.sort(list, function(a, b) return a.count > b.count end)

    print(("|cff33ff99BuffLeaderboard|r — %s, all-time:"):format(displayName))
    for i, item in ipairs(list) do
        local rec = item.rec
        local display = rec.realm and (rec.name .. "-" .. rec.realm) or rec.name
        print(("  %d. %s%s|r — %d"):format(
            i, ClassColor(rec.class), display or "?", item.count))
    end
end

local function Dump(arg)
    arg = arg and strtrim(arg) or ""
    local scope = strlower(arg)
    if scope ~= "" and scope ~= "session" then
        return DumpSpell(arg) -- anything else is a buff-name filter
    end

    local store = (scope == "session") and session or db
    local list = {}
    for _, rec in next, store.casters do
        list[#list + 1] = rec
    end
    table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)

    print(("|cff33ff99BuffLeaderboard|r — %s (use /blb dump <buff> for a ladder):"):format(
        scope == "session" and "this session" or "all-time"))
    if #list == 0 then
        print("  (nothing recorded yet)")
        return
    end
    for _, rec in ipairs(list) do
        local display = rec.realm and (rec.name .. "-" .. rec.realm) or rec.name
        local parts = {}
        for group, count in next, rec.spells do
            parts[#parts + 1] = ("%s x%d"):format(group, count)
        end
        table.sort(parts)
        print(("  %s%s|r — %s"):format(
            ClassColor(rec.class), display or "?", table.concat(parts, ", ")))
    end
end

SLASH_BUFFLEADERBOARD1 = "/blb"
SLASH_BUFFLEADERBOARD2 = "/buffleaderboard"
SlashCmdList.BUFFLEADERBOARD = function(msg)
    local cmd, arg = strsplit(" ", strtrim(msg or ""), 2)
    cmd = strlower(cmd)
    if cmd == "" or cmd == "show" or cmd == "toggle" then
        ns.ToggleLeaderboard()
    elseif cmd == "hide" then
        ns.HideLeaderboard()
    elseif cmd == "dump" then
        Dump(arg) -- empty = all-time, "session", or a buff-name filter
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
            ns.RefreshLeaderboard()
            print("|cff33ff99BuffLeaderboard|r: all-time data for this character reset.")
        else
            print("|cff33ff99BuffLeaderboard|r: this wipes all-time data for this character. Type |cffffff00/blb reset confirm|r to proceed.")
        end
    elseif cmd == "options" or cmd == "config" then
        ns.OpenOptions()
    else
        print("|cff33ff99BuffLeaderboard|r commands:")
        print("  /blb — toggle the leaderboard window")
        print("  /blb dump — all casters and their per-buff counts")
        print("  /blb dump session — this session only")
        print("  /blb dump <buff name> — the ladder for one buff")
        print("  /blb track <name or spell id> — add a buff to the tracked list")
        print("  /blb untrack <name> — remove a buff from the tracked list")
        print("  /blb options — open the settings panel")
        print("  /blb reset confirm — wipe this character's data")
    end
end
