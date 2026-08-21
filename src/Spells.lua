local ADDON_NAME, ns = ...

-- Tracked external buffs, keyed by spellId (TBC 2.5.x ids).
--
-- TBC spells have ranks, and each rank is a distinct spellId in the combat
-- log. Every rank is registered separately but shares a `group`, so the
-- leaderboard breakdown merges them under one display name.
--
-- Per-entry policy:
--   countRefresh : SPELL_AURA_REFRESH counts as a new cast. In TBC none of
--                  these auras are refreshed by procs or pandemic-style
--                  mechanics — a REFRESH only ever means the caster actually
--                  re-cast the spell on you — so this defaults to true.
--   countDose    : SPELL_AURA_APPLIED_DOSE counts as a new cast. Nothing in
--                  the default list stacks; kept for extensions.
ns.spells = {}

local function Add(group, ids, opts)
    opts = opts or {}
    for _, id in ipairs(ids) do
        ns.spells[id] = {
            group = group,
            countRefresh = opts.countRefresh ~= false, -- default true
            countDose = opts.countDose or false,       -- default false
        }
    end
end

-- Druid
Add("Innervate", { 29166 })

-- Priest
Add("Power Infusion", { 10060 })
Add("Pain Suppression", { 33206 })
Add("Fear Ward", { 6346 })

-- Shaman (no Sated/Exhaustion debuff in TBC, so chained casts re-apply)
Add("Bloodlust", { 2825 })
Add("Heroism", { 32182 })

-- Paladin
Add("Blessing of Protection", { 1022, 5599, 10278 })
Add("Blessing of Freedom", { 1044 })
Add("Blessing of Sacrifice", { 6940, 20729, 27147, 27148 })
Add("Divine Intervention", { 19752 })

-- Hunter
Add("Misdirection", { 34477 })

-- Warlock
Add("Soulstone Resurrection", { 20707, 20762, 20763, 20764, 20765, 27239 })

-- Extension examples (noisy, off by default):
-- Add("Power Word: Shield", { 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901, 25217, 25218 })
-- Add("Blessing of Salvation", { 1038 })
-- Add("Greater Blessing of Salvation", { 25895 })
