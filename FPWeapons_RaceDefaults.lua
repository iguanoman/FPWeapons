-------------------------------------------------------------------------------
-- FP Weapons - shipped per-race defaults (hand/arm mode)
--
-- These are the starting positions every player of a race/sex gets in hand/arm mode, wherever
-- they haven't positioned something themselves. A player's own "Save as Race Default" values
-- (FPWeaponsRaceDB) take priority over these; the per-weapon-type defaults in FPWeapons.lua are
-- used for anything not listed here.
--
-- HOW TO FILL THIS IN
--  1. On a character of each race/sex, position everything in hand/arm mode (each weapon type,
--     and the cast/release poses for each caster setup), then click "Save as <Race> Default".
--  2. /reload or log out, so the game writes the file.
--  3. Open  WTF\Account\<ACCOUNT>\SavedVariables\FPWeapons.lua  and copy the entries out of
--     FPWeaponsRaceDB = { ... }  into the table below (same layout, nothing to convert).
--     Each entry looks like:
--        ["Human_F"] = {
--            ["MH"] = { ["MELEE_1H"] = { scale = 1, facing = 3.0, pitch = -0.75, roll = -1.25, posX = 0.65, posY = 1.15, posZ = -0.7 }, ... },
--            ["OH"] = { ["SHIELD"] = { ... }, ... },
--            ["RW"] = { ["BOW"] = { ... }, ... },
--            ["CAST"] = { ... },     ["RELEASE"] = { ... },       -- both hands Caster Hand
--            ["CAST_MH"] = { ... },  ["RELEASE_MH"] = { ... },    -- Mainhand Caster Hand only
--            ["CAST_OH"] = { ... },  ["RELEASE_OH"] = { ... },    -- Offhand Caster Hand only
--        },
--  4. Optional: "/fpw racedefault clear" on your own characters afterwards, so you see exactly
--     what players will get.
--
-- KEYS are the game's internal race name + _M / _F (+ _alt for Worgen human form / Dracthyr
-- visage). "/fpw racedefault" in game prints the key for the character you're on. Playable races:
--   Human  Dwarf  NightElf  Gnome  Draenei  Worgen  Pandaren  Dracthyr  EarthenDwarf
--   VoidElf  LightforgedDraenei  DarkIronDwarf  KulTiran  Mechagnome
--   Orc  Scourge (Undead)  Tauren  Troll  BloodElf  Goblin  Nightborne
--   HighmountainTauren  MagharOrc  ZandalariTroll  Vulpera
--   (check new/rare ones with /fpw racedefault; e.g. Haranir)
-------------------------------------------------------------------------------
FPWeaponsBuiltinRaceDefaults = {
    ["Dwarf_M"] = {
        ["MH"] = {
            ["EMPTY"] = { scale = 1, facing = 3.14, pitch = -1, roll = -0.05, posX = -0.15, posY = 1.55, posZ = -0.7 },
            ["MELEE_1H"] = { scale = 11.7, facing = 3.55, pitch = -0.5, roll = -1, posX = 0.5, posY = 2.6, posZ = -1 },
            ["MELEE_1H_CASTER"] = { scale = 11.7, facing = 3.5, pitch = -0.75, roll = -1, posX = 0.45, posY = 2.85, posZ = -1 },
            ["MELEE_2H"] = { scale = 11.7, facing = 3.45, pitch = -0.55, roll = -1, posX = 0.45, posY = 2.4, posZ = -0.95 },
            ["STAFF"] = { scale = 11.7, facing = 3.3, pitch = -0.2, roll = -0.85, posX = 0.35, posY = 1.9, posZ = -0.95 },
        },
        ["OH"] = {
            ["MELEE_1H_CASTER"] = { scale = 1, facing = 1.9, pitch = -1.8, roll = -1.4, posX = -0.6, posY = 1.3, posZ = -0.75 },
            ["SHIELD"] = { scale = 1, facing = 1.5, pitch = 0.25, roll = -0.85, posX = -0.85, posY = 0.35, posZ = -0.4 },
        },
        ["CAST"] = { scale = 1, facing = 2.1, pitch = -0.35, roll = 1.3, posX = -0.15, posY = 1.4, posZ = -0.45 },
        ["CAST_MH"] = { scale = 1, facing = 2.1, pitch = -0.35, roll = 1.3, posX = -0.15, posY = 1.4, posZ = -0.55 },
        ["RELEASE"] = { scale = 1, facing = 2.85, pitch = -0.35, roll = -0.9, posX = 0.35, posY = 1.05, posZ = -0.8 },
    },
    ["Gnome_M"] = {
        ["MH"] = {
            ["EMPTY"] = { scale = 1, facing = 3.14, pitch = -0.75, roll = -1.75, posX = 0.15, posY = 1.8, posZ = -0.65 },
            ["MELEE_1H"] = { scale = 11.7, facing = 3.3, pitch = -0.25, roll = -1.4, posX = 0.25, posY = 1.35, posZ = -0.6 },
            ["MELEE_1H_CASTER"] = { scale = 11.7, facing = 3, pitch = -0.35, roll = -1.25, posX = 0.25, posY = 1.9, posZ = -0.7 },
            ["MELEE_2H"] = { scale = 11.7, facing = 3, pitch = -0.2, roll = -1.3, posX = 0.15, posY = 1.3, posZ = -0.65 },
            ["STAFF"] = { scale = 11.7, facing = 3.1, pitch = -0.15, roll = -1.15, posX = 0.05, posY = 1.4, posZ = -0.6 },
        },
        ["OH"] = {
            ["MELEE_1H"] = { scale = 1, facing = 1.6, pitch = 0.55, roll = -0.75, posX = -0.6, posY = 0.65, posZ = -0.05 },
            ["MELEE_1H_CASTER"] = { scale = 1, facing = 4.9, pitch = -2.3, roll = -2.1, posX = -0.15, posY = 1.2, posZ = -0.65 },
            ["SHIELD"] = { scale = 1, facing = 1.6, pitch = -0.05, roll = -0.85, posX = -0.6, posY = 0.8, posZ = -0.35 },
            ["OFFHAND"] = { scale = 1, facing = 1.6, pitch = 0.55, roll = -0.85, posX = -0.6, posY = 0.6, posZ = -0.05 },
        },
        ["CAST"] = { scale = 1, facing = 2.05, pitch = -0.6, roll = 1.2, posX = -0.05, posY = 0.8, posZ = -0.35 },
        ["CAST_MH"] = { scale = 1, facing = 2.1, pitch = -0.35, roll = 1.3, posX = -0.15, posY = 1.4, posZ = -0.55 },
        ["RELEASE"] = { scale = 1, facing = 2.85, pitch = -0.2, roll = -0.9, posX = 0, posY = 1.2, posZ = -0.6 },
    },
    ["Human_F"] = {
        ["MH"] = {
            ["EMPTY"] = { scale = 1, facing = 3.14, pitch = -0.75, roll = -1.25, posX = 0.5, posY = 0.8, posZ = -0.75 },
            ["MELEE_1H"] = { scale = 11.7, facing = 3.25, pitch = -0.4, roll = -0.9, posX = 0.35, posY = 1.15, posZ = -0.8 },
            ["MELEE_1H_CASTER"] = { scale = 11.7, facing = 3.45, pitch = -0.25, roll = -1.1, posX = 0.5, posY = 1, posZ = -0.75 },
            ["MELEE_2H"] = { scale = 11.7, facing = 3.3, pitch = -0.15, roll = -1, posX = 0.4, posY = 1.05, posZ = -0.75 },
        },
        ["OH"] = {
            ["MELEE_1H"] = { scale = 1, facing = 1.95, pitch = 0.3, roll = -0.95, posX = -0.45, posY = 0.4, posZ = -0.45 },
            ["MELEE_1H_CASTER"] = { scale = 1, facing = 3, pitch = -1.95, roll = -1.4, posX = 0.05, posY = 0.8, posZ = -0.65 },
            ["SHIELD"] = { scale = 1, facing = 1.5, pitch = 0, roll = -0.65, posX = -0.8, posY = 0.8, posZ = -1 },
            ["OFFHAND"] = { scale = 1, facing = 2.05, pitch = 0.4, roll = -0.8, posX = -0.35, posY = 0.1, posZ = -0.5 },
        },
        ["CAST"] = { scale = 1, facing = 2.1, pitch = -0.35, roll = 1.3, posX = -0.15, posY = 1.4, posZ = -0.55 },
        ["CAST_MH"] = { scale = 1, facing = 2.1, pitch = -0.35, roll = 1.3, posX = -0.15, posY = 1.4, posZ = -0.55 },
        ["RELEASE"] = { scale = 1, facing = 2.85, pitch = -0.2, roll = -0.9, posX = 0.55, posY = 0.6, posZ = -0.8 },
    },
    ["Human_M"] = {
        ["MH"] = {
            ["EMPTY"] = { scale = 1, facing = 3.14, pitch = -0.6, roll = -1.1, posX = 0.45, posY = 1.7, posZ = -0.95 },
            ["MELEE_1H"] = { scale = 11.7, facing = 3, pitch = -0.35, roll = -1.05, posX = 0.35, posY = 1.4, posZ = -0.85 },
            ["MELEE_1H_CASTER"] = { scale = 11.7, facing = 3, pitch = -0.35, roll = -1.25, posX = 0.45, posY = 1.3, posZ = -0.85 },
            ["MELEE_2H"] = { scale = 11.7, facing = 3, pitch = -0.4, roll = -1.35, posX = 0.6, posY = 1.75, posZ = -0.85 },
            ["STAFF"] = { scale = 11.7, facing = 3, pitch = -0.25, roll = -1.05, posX = 0.4, posY = 1.7, posZ = -0.95 },
        },
        ["OH"] = {
            ["MELEE_1H_CASTER"] = { scale = 1, facing = 0.6, pitch = -1.65, roll = -0.1, posX = -0.6, posY = 0.95, posZ = -0.7 },
            ["SHIELD"] = { scale = 1, facing = 1.5, pitch = 0.55, roll = -0.85, posX = -0.85, posY = 0.35, posZ = -0.4 },
        },
        ["CAST"] = { scale = 1, facing = 2.1, pitch = -0.35, roll = 1.3, posX = -0.15, posY = 1.4, posZ = -0.55 },
        ["CAST_MH"] = { scale = 1, facing = 2.1, pitch = -0.35, roll = 1.3, posX = -0.15, posY = 1.4, posZ = -0.55 },
        ["CAST_OH"] = { scale = 1, facing = 2.1, pitch = -0.35, roll = 1.3, posX = -0.15, posY = 1.4, posZ = -0.55 },
        ["RELEASE"] = { scale = 1, facing = 2.85, pitch = -0.2, roll = -0.9, posX = 0.55, posY = 0.6, posZ = -0.95 },
        ["RELEASE_OH"] = { scale = 1, facing = 2.85, pitch = -0.2, roll = -0.9, posX = 0.55, posY = 0.6, posZ = -0.95 },
    },
    ["NightElf_F"] = {
        ["MH"] = {
            ["EMPTY"] = { scale = 1, facing = 3.05, pitch = -0.55, roll = -2, posX = 0.85, posY = 1.3, posZ = -0.4 },
            ["MELEE_1H"] = { scale = 11.7, facing = 3.1, pitch = -0.25, roll = -1.1, posX = 0.65, posY = 1.9, posZ = -1 },
            ["MELEE_1H_CASTER"] = { scale = 11.7, facing = 3.15, pitch = -0.3, roll = -1.15, posX = 0.7, posY = 2.1, posZ = -1 },
            ["MELEE_2H"] = { scale = 11.7, facing = 3, pitch = -0.2, roll = -1.35, posX = 0.65, posY = 1.6, posZ = -0.8 },
            ["STAFF"] = { scale = 11.7, facing = 3.2, pitch = 0, roll = -1.25, posX = 0.7, posY = 2.05, posZ = -0.95 },
        },
        ["OH"] = {
            ["MELEE_1H_CASTER"] = { scale = 1, facing = 3.25, pitch = -1, roll = -3.15, posX = -0.65, posY = 1.05, posZ = -0.35 },
            ["SHIELD"] = { scale = 1, facing = 1.5, pitch = 0.55, roll = -0.85, posX = -0.85, posY = 0.35, posZ = -0.4 },
        },
        ["CAST"] = { scale = 1, facing = 2, pitch = -0.25, roll = 1.25, posX = -0.25, posY = 1.7, posZ = -0.6 },
        ["CAST_MH"] = { scale = 1, facing = 2.1, pitch = -0.35, roll = 1.3, posX = -0.15, posY = 1.4, posZ = -0.55 },
        ["RELEASE"] = { scale = 1, facing = 2.85, pitch = -0.25, roll = -0.7, posX = 0.4, posY = 1, posZ = -1.1 },
    },
    ["NightElf_M"] = {
        ["MH"] = {
            ["EMPTY"] = { scale = 1, facing = 3.14, pitch = -0.75, roll = -0.2, posX = -0.1, posY = 1.4, posZ = -1.05 },
            ["MELEE_1H"] = { scale = 11.7, facing = 3.05, pitch = -0.2, roll = -0.95, posX = 0.5, posY = 1.8, posZ = -1.1 },
            ["MELEE_1H_CASTER"] = { scale = 11.7, facing = 3.05, pitch = -0.3, roll = -1, posX = 0.5, posY = 1.6, posZ = -1.1 },
            ["MELEE_2H"] = { scale = 11.7, facing = 3.05, pitch = -0.35, roll = -1.15, posX = 0.7, posY = 1.55, posZ = -1.05 },
            ["STAFF"] = { scale = 11.7, facing = 3.35, pitch = -0.45, roll = -1.05, posX = 0.65, posY = 1.8, posZ = -1.05 },
        },
        ["OH"] = {
            ["MELEE_1H"] = { scale = 1, facing = 1.5, pitch = 0.55, roll = -0.85, posX = -0.85, posY = 0.35, posZ = -0.4 },
            ["MELEE_1H_CASTER"] = { scale = 1, facing = 2.4, pitch = -1.8, roll = -1.15, posX = -0.3, posY = 1, posZ = -0.85 },
            ["SHIELD"] = { scale = 1, facing = 1.5, pitch = 0.55, roll = -0.85, posX = -0.85, posY = 0.35, posZ = -0.4 },
        },
        ["RW"] = {
            ["BOW"] = { scale = 1, facing = 1.85, pitch = 0.7, roll = -1, posX = -0.75, posY = 0.5, posZ = -0.25 },
            ["GUN"] = { scale = 1, facing = 3.55, pitch = 0.05, roll = 0.4, posX = 0.1, posY = 0.85, posZ = -1.2 },
            ["WAND"] = { scale = 1, facing = 3.55, pitch = 0, roll = 0, posX = 0.35, posY = 0.95, posZ = -1.5 },
        },
        ["CAST"] = { scale = 1, facing = 2.1, pitch = -0.35, roll = 1.3, posX = -0.15, posY = 1.9, posZ = -0.55 },
        ["CAST_MH"] = { scale = 1, facing = 2.1, pitch = -0.35, roll = 1.3, posX = -0.15, posY = 1.4, posZ = -0.55 },
        ["RELEASE"] = { scale = 1, facing = 2.85, pitch = -0.2, roll = -0.9, posX = 0.65, posY = 0.95, posZ = -1.2 },
    },
    ["Orc_M"] = {
        ["MH"] = {
            ["EMPTY"] = { scale = 1, facing = 3.14, pitch = -0.75, roll = -1.7, posX = 0.7, posY = 2.1, posZ = -1.05 },
            ["MELEE_1H"] = { scale = 11.7, facing = 3, pitch = -0.4, roll = -1, posX = 0.35, posY = 1.45, posZ = -1.2 },
            ["MELEE_1H_CASTER"] = { scale = 11.7, facing = 3, pitch = -0.35, roll = -1.15, posX = 0.35, posY = 1.7, posZ = -1.15 },
            ["MELEE_2H"] = { scale = 11.7, facing = 3.05, pitch = -0.35, roll = -1, posX = 0.35, posY = 1.55, posZ = -1.2 },
            ["STAFF"] = { scale = 11.7, facing = 3, pitch = -0.3, roll = -1.25, posX = 0.5, posY = 1.75, posZ = -1.15 },
        },
        ["OH"] = {
            ["MELEE_1H_CASTER"] = { scale = 1, facing = 4.5, pitch = -2.85, roll = -1.9, posX = 0.25, posY = 2.6, posZ = -1.1 },
            ["SHIELD"] = { scale = 1, facing = 1.5, pitch = 0.55, roll = -0.85, posX = -0.85, posY = 0.35, posZ = -0.4 },
            ["OFFHAND"] = { scale = 1, facing = 1.5, pitch = 0.55, roll = -0.85, posX = -0.85, posY = 0.35, posZ = -0.4 },
        },
        ["RW"] = {
            ["BOW"] = { scale = 1, facing = 3.7, pitch = 0.45, roll = -0.1, posX = 0.85, posY = 1.6, posZ = -1.5 },
            ["GUN"] = { scale = 1, facing = 3.3, pitch = 0, roll = 0.4, posX = 0.05, posY = 2.45, posZ = -1.35 },
            ["WAND"] = { scale = 1, facing = 3.55, pitch = 0, roll = 0, posX = 0.5, posY = 2.45, posZ = -1.7 },
        },
        ["CAST"] = { scale = 1, facing = 2.1, pitch = -0.5, roll = 1.3, posX = -0.05, posY = 1.85, posZ = -0.75 },
        ["CAST_MH"] = { scale = 1, facing = 2.1, pitch = -0.35, roll = 1.3, posX = -0.15, posY = 1.4, posZ = -0.55 },
        ["RELEASE"] = { scale = 1, facing = 2.85, pitch = -0.2, roll = -0.4, posX = 0.15, posY = 1.2, posZ = -1.3 },
    },
    ["Scourge_M"] = {
        ["MH"] = {
            ["EMPTY"] = { scale = 1, facing = 3.6, pitch = -0.85, roll = -1.65, posX = 0.4, posY = 1.45, posZ = -0.7 },
            ["MELEE_1H"] = { scale = 11.7, facing = 3.1, pitch = -0.35, roll = -1.3, posX = 0.25, posY = 1.4, posZ = -0.8 },
            ["MELEE_1H_CASTER"] = { scale = 11.7, facing = 3, pitch = -0.75, roll = -1.25, posX = 0.3, posY = 1.15, posZ = -0.85 },
            ["MELEE_2H"] = { scale = 11.7, facing = 3, pitch = -0.75, roll = -1.3, posX = 0.25, posY = 1.5, posZ = -0.8 },
            ["STAFF"] = { scale = 11.7, facing = 3, pitch = -0.75, roll = -1.25, posX = 0.25, posY = 1.15, posZ = -0.8 },
        },
        ["OH"] = {
            ["MELEE_1H"] = { scale = 1, facing = 1.5, pitch = 0.55, roll = -0.85, posX = -0.85, posY = -0.05, posZ = -0.4 },
            ["MELEE_1H_CASTER"] = { scale = 1, facing = 2.55, pitch = -0.6, roll = -2.55, posX = -1, posY = 1.1, posZ = -0.15 },
            ["SHIELD"] = { scale = 1, facing = 1.5, pitch = 0.55, roll = -0.85, posX = -0.85, posY = 0.35, posZ = -0.4 },
        },
        ["CAST"] = { scale = 1, facing = 2.1, pitch = -0.35, roll = 1.3, posX = -0.15, posY = 1.4, posZ = -0.55 },
        ["CAST_MH"] = { scale = 1, facing = 2.1, pitch = -0.35, roll = 1.3, posX = -0.15, posY = 1.4, posZ = -0.55 },
        ["CAST_OH"] = { scale = 1, facing = 2.1, pitch = -0.35, roll = 1.3, posX = -0.15, posY = 1.4, posZ = -0.55 },
        ["RELEASE"] = { scale = 1, facing = 2.85, pitch = -0.2, roll = -0.9, posX = 0.55, posY = 0.6, posZ = -0.8 },
    },
    ["Skyborne_F"] = {
        ["MH"] = {
            ["EMPTY"] = { scale = 1, facing = 3.14, pitch = -0.75, roll = 0, posX = 0.1, posY = 0.8, posZ = -0.75 },
            ["MELEE_1H"] = { scale = 11.7, facing = 3, pitch = -0.75, roll = -1.25, posX = 0.65, posY = 1.15, posZ = -0.7 },
            ["MELEE_1H_ATTACK"] = { scale = 11.7, facing = 3.45, pitch = -0.7, roll = -0.55, posX = 0.4, posY = -0.35, posZ = -0.85 },
            ["MELEE_1H_CASTER"] = { scale = 11.7, facing = 3, pitch = -0.75, roll = -1.25, posX = 0.65, posY = 1.15, posZ = -0.7 },
            ["MELEE_1H_CASTER_ATTACK"] = { scale = 11.7, facing = 3.45, pitch = -0.7, roll = -0.55, posX = 0.4, posY = -0.35, posZ = -0.85 },
            ["MELEE_2H"] = { scale = 11.7, facing = 3, pitch = -0.75, roll = -1.25, posX = 0.65, posY = 1.15, posZ = -0.7 },
            ["MELEE_2H_ATTACK"] = { scale = 11.7, facing = 3.45, pitch = -0.7, roll = -0.55, posX = 0.45, posY = 0.95, posZ = -0.8 },
            ["STAFF"] = { scale = 11.7, facing = 3, pitch = -0.75, roll = -1.25, posX = 0.65, posY = 1.15, posZ = -0.7 },
        },
        ["OH"] = {
            ["MELEE_1H"] = { scale = 1, facing = 1.5, pitch = 0.55, roll = -0.9, posX = -0.85, posY = 0.45, posZ = -0.4 },
            ["MELEE_1H_ATTACK"] = { scale = 1, facing = 3.3, pitch = 0.5, roll = 1.05, posX = -0.3, posY = -0.6, posZ = 0 },
            ["SHIELD"] = { scale = 1, facing = 1.5, pitch = 0.55, roll = -0.85, posX = -0.85, posY = 0.35, posZ = -0.4 },
        },
        ["RW"] = {
            ["BOW"] = { scale = 1, facing = 1.85, pitch = 0.7, roll = -0.9, posX = -0.6, posY = 0.15, posZ = -0.4 },
            ["GUN"] = { scale = 1, facing = 3.55, pitch = 0, roll = 0, posX = 0.35, posY = 0.95, posZ = -1.05 },
            ["WAND"] = { scale = 1, facing = 3.55, pitch = 0, roll = 0, posX = 0.35, posY = 0.95, posZ = -1.05 },
        },
        ["CAST"] = { scale = 1, facing = 2.1, pitch = -0.7, roll = 1.25, posX = -0.15, posY = 1.4, posZ = -0.55 },
        ["CAST_1H_OHC"] = { scale = 1, facing = 2.1, pitch = -0.35, roll = 1.3, posX = -0.15, posY = 1.4, posZ = -0.55 },
        ["CAST_MH"] = { scale = 1, facing = 3.8, pitch = -0.5, roll = -1.15, posX = 0.3, posY = 0.85, posZ = -0.65 },
        ["CAST_MHC_ITEM"] = { scale = 1, facing = 3.7, pitch = 0, roll = -1.9, posX = 0.5, posY = 0.8, posZ = -0.3 },
        ["CAST_OH"] = { scale = 1, facing = 2.8, pitch = -0.15, roll = 1.35, posX = -0.85, posY = 1.75, posZ = -0.65 },
        ["CAST_STAFF"] = { scale = 1, facing = 2.1, pitch = -0.35, roll = 1.3, posX = -0.15, posY = 1.4, posZ = -0.55 },
        ["CAST_STAFF_OHC"] = { scale = 1, facing = 4.3, pitch = -0.3, roll = -1.2, posX = 0.65, posY = 0.95, posZ = -0.65 },
        ["RELEASE"] = { scale = 1, facing = 3.25, pitch = -0.5, roll = 0.05, posX = -0.05, posY = 0.4, posZ = -1.05 },
        ["RELEASE_MH"] = { scale = 1, facing = 2.85, pitch = -0.2, roll = -0.9, posX = 0.55, posY = 0.6, posZ = -0.8 },
        ["RELEASE_MHC_ITEM"] = { scale = 1, facing = 3, pitch = -0.8, roll = -0.8, posX = 0.35, posY = 1.05, posZ = -0.65 },
        ["RELEASE_OH"] = { scale = 1, facing = 3.2, pitch = -0.5, roll = 0.65, posX = -0.6, posY = 0.5, posZ = -1 },
        ["RELEASE_STAFF_OHC"] = { scale = 1, facing = 3.2, pitch = -0.5, roll = 0.25, posX = -0.1, posY = 0.7, posZ = -1.1 },
    },
    ["Skyborne_M"] = {
        ["MH"] = {
            ["EMPTY"] = { scale = 1, facing = 3, pitch = -0.85, roll = -1.5, posX = 0.65, posY = 1.95, posZ = -0.8 },
            ["MELEE_1H"] = { scale = 11.7, facing = 3.75, pitch = -0.05, roll = -1.25, posX = 0.8, posY = 1.5, posZ = -0.85 },
            ["MELEE_1H_CASTER"] = { scale = 11.7, facing = 3.65, pitch = -0.1, roll = -1.25, posX = 0.75, posY = 1.55, posZ = -0.85 },
            ["MELEE_2H"] = { scale = 11.7, facing = 3.4, pitch = 0.1, roll = -1.2, posX = 0.65, posY = 0.8, posZ = -0.8 },
            ["STAFF"] = { scale = 11.7, facing = 3.55, pitch = -0.5, roll = -1.2, posX = 0.65, posY = 1.8, posZ = -1 },
        },
        ["OH"] = {
            ["MELEE_1H"] = { scale = 1, facing = 1.85, pitch = 0.35, roll = -0.9, posX = -0.75, posY = 0.8, posZ = -0.65 },
            ["MELEE_1H_CASTER"] = { scale = 1, facing = 2.55, pitch = -1.65, roll = -1.4, posX = -0.25, posY = 1.2, posZ = -0.7 },
            ["SHIELD"] = { scale = 1, facing = 1.5, pitch = 0.55, roll = -0.85, posX = -1, posY = 0.35, posZ = -0.5 },
            ["OFFHAND"] = { scale = 1, facing = 1.5, pitch = 0.55, roll = -0.85, posX = -1.05, posY = 0.35, posZ = -0.45 },
        },
        ["CAST"] = { scale = 1, facing = 2.1, pitch = -0.35, roll = 1.25, posX = -0.15, posY = 2.2, posZ = -0.6 },
        ["CAST_MH"] = { scale = 1, facing = 2.1, pitch = -0.35, roll = 1.3, posX = -0.15, posY = 1.4, posZ = -0.55 },
        ["CAST_OH"] = { scale = 1, facing = 2.1, pitch = -0.35, roll = 1.3, posX = -0.15, posY = 1.4, posZ = -0.55 },
        ["RELEASE"] = { scale = 1, facing = 3.05, pitch = -0.3, roll = -0.95, posX = 0.7, posY = 1.8, posZ = -1.05 },
    },
    ["Tauren_M"] = {
        ["MH"] = {
            ["EMPTY"] = { scale = 1, facing = 3.55, pitch = -0.75, roll = -1.35, posX = 0.6, posY = 2.8, posZ = -1.6 },
            ["MELEE_1H"] = { scale = 11.7, facing = 3, pitch = -0.4, roll = -1.25, posX = 0.4, posY = 2.2, posZ = -1.7 },
            ["MELEE_1H_CASTER"] = { scale = 11.7, facing = 3, pitch = -0.35, roll = -0.95, posX = 0.25, posY = 2.45, posZ = -1.6 },
            ["MELEE_2H"] = { scale = 11.7, facing = 3, pitch = -0.75, roll = -0.6, posX = -0.45, posY = 2.2, posZ = -1.8 },
            ["STAFF"] = { scale = 11.7, facing = 3, pitch = -0.35, roll = -1.15, posX = 0.45, posY = 3, posZ = -1.75 },
        },
        ["OH"] = {
            ["MELEE_1H_CASTER"] = { scale = 1, facing = 2.05, pitch = -0.5, roll = -1, posX = -1.6, posY = 1.5, posZ = -0.1 },
            ["SHIELD"] = { scale = 1, facing = 1.5, pitch = 0.55, roll = -0.85, posX = -0.85, posY = 0.35, posZ = -0.4 },
        },
        ["RW"] = {
            ["BOW"] = { scale = 1, facing = 2.95, pitch = 0.25, roll = 0.35, posX = -0.95, posY = 2.25, posZ = -1.55 },
            ["GUN"] = { scale = 1, facing = 3.55, pitch = 0.2, roll = 0.5, posX = 0, posY = 0.25, posZ = -1.15 },
        },
        ["CAST"] = { scale = 1, facing = 2.1, pitch = -0.35, roll = 1.6, posX = -0.15, posY = 2.15, posZ = -1.1 },
        ["CAST_MH"] = { scale = 1, facing = 2.1, pitch = -0.35, roll = 1.85, posX = -0.5, posY = 2.45, posZ = -1.35 },
        ["RELEASE"] = { scale = 1, facing = 2.85, pitch = -0.2, roll = -0.9, posX = 0.85, posY = 1.7, posZ = -1.35 },
        ["RELEASE_MH"] = { scale = 1, facing = 2.85, pitch = -0.2, roll = -0.9, posX = 0.75, posY = 1.55, posZ = -1.55 },
    },
    ["Troll_M"] = {
        ["MH"] = {
            ["EMPTY"] = { scale = 1, facing = 3, pitch = -0.75, roll = -2.05, posX = 0.7, posY = 2.05, posZ = -1 },
            ["MELEE_1H"] = { scale = 11.7, facing = 3, pitch = -0.75, roll = -1.25, posX = 0.4, posY = 2.8, posZ = -1.35 },
            ["MELEE_1H_CASTER"] = { scale = 11.7, facing = 3, pitch = -0.65, roll = -1.25, posX = 0.45, posY = 2.6, posZ = -1.3 },
            ["MELEE_2H"] = { scale = 11.7, facing = 3, pitch = -0.75, roll = -1.25, posX = 0.45, posY = 2.85, posZ = -1.35 },
            ["STAFF"] = { scale = 11.7, facing = 3, pitch = -0.75, roll = -1.25, posX = 0.35, posY = 2.2, posZ = -1.3 },
        },
        ["OH"] = {
            ["MELEE_1H_CASTER"] = { scale = 1, facing = 1.15, pitch = -1.15, roll = 0.35, posX = -0.35, posY = 1.1, posZ = -0.6 },
            ["SHIELD"] = { scale = 1, facing = 1.5, pitch = 0.55, roll = -0.85, posX = -0.85, posY = 0.35, posZ = -0.4 },
        },
        ["RW"] = {
            ["BOW"] = { scale = 1, facing = 3.6, pitch = 0.25, roll = 0.15, posX = 0.4, posY = 1.15, posZ = -1.35 },
            ["GUN"] = { scale = 1, facing = 3.55, pitch = 0, roll = 0, posX = 0.85, posY = 1.05, posZ = -1.55 },
            ["WAND"] = { scale = 1, facing = 3.55, pitch = 0, roll = 0, posX = 0.5, posY = 1.5, posZ = -1.6 },
        },
        ["CAST"] = { scale = 1, facing = 2.1, pitch = -0.35, roll = 1.3, posX = -0.25, posY = 2.5, posZ = -0.95 },
        ["CAST_MH"] = { scale = 1, facing = 2.1, pitch = -0.35, roll = 1.3, posX = -0.15, posY = 1.4, posZ = -0.55 },
        ["RELEASE"] = { scale = 1, facing = 2.85, pitch = -0.2, roll = -0.9, posX = 0.55, posY = 0.85, posZ = -1.1 },
    },
}
