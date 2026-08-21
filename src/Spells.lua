local ADDON_NAME, ns = ...

-- Default tracked buffs, seeded into SavedVariables on first run. After
-- that the user's list in BuffLeaderboardDB.options.tracked is
-- authoritative — buffs are added and removed from the options panel (or
-- /blb track|untrack), so this table is only read when no saved list
-- exists yet.
--
-- Matching is by buff NAME, not spellId: in TBC every rank of a spell is
-- a distinct spellId but shares its name, so name matching covers all
-- ranks for free — and lets users add buffs without hunting down ids.
-- Same-named copies cast by NPCs are already excluded by the
-- player-source filter in Core.lua.
ns.defaultSpells = {
    "Innervate",              -- Druid
    "Power Infusion",         -- Priest
    "Pain Suppression",       -- Priest
    "Fear Ward",              -- Priest
    "Bloodlust",              -- Shaman (no Sated in TBC, chained casts re-apply)
    "Heroism",                -- Shaman
    "Blessing of Protection", -- Paladin
    "Blessing of Freedom",    -- Paladin
    "Blessing of Sacrifice",  -- Paladin
    "Divine Intervention",    -- Paladin
    "Misdirection",           -- Hunter
    "Soulstone Resurrection", -- Warlock
}
