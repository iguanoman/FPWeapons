--[[ FP Weapons
     First-person weapons, hands and arms for World of Warcraft.
     by iguanoman ]]
local addonName = ...

--==[ Settings & defaults ]=====================================================
-- (Clients without Midnight's secret values: nothing is ever secret.)
local issecretvalue = _G.issecretvalue or function() return false end
-- Settings grouped by topic, and the addon's running state in one table, to stay well under
-- Lua's limit of 200 local variables per file
local Defaults = {}   -- starting poses
local Anim = {}       -- hand / arm idle animations
local Sheath = {}     -- putting the weapons away
local Cleave = {}     -- scripted weapon swings
local Bash = {}       -- scripted shield bashes
local State = {}      -- what's happening right now (first-person on, swing progress, timers...)

-- Last-resort poses per hand, used only when no weapon-type, race or shipped default applies.
-- Built from a few numbers: the main hand sits right, the off hand mirrors it on the left,
-- and the ranged weapon sits low in the middle.
local function BasePose(scale, side, height, yaw)
    return { scale = scale, facing = yaw, pitch = 0.0, roll = 0.0, posX = side, posY = 0.0, posZ = height }
end
Defaults.ARM = {         -- old hand/arm mode
    MH = BasePose(7.0, 0.6, -1.0, 3.4), OH = BasePose(7.0, -0.6, -1.0, 2.9), RW = BasePose(7.0, 0, -1.2, 3.2),
}
-- a 2H weapon or staff in the right hand is held further out, tilted across the body
Defaults.ARM.MH_2H = BasePose(8.5, 1.2, -1.7, 3.4)
Defaults.ARM.MH_2H.posY, Defaults.ARM.MH_2H.pitch, Defaults.ARM.MH_2H.roll = 1.75, -0.4, -1.2

-- Per-hand info. "RW" is the ranged weapon: it shows the ranged slot (18, on clients that still
-- have one) or whatever item / model ID is entered in its Custom Item ID box.
local HANDS = {
    MH = { prefix = "mh", slot = 16, defType = "AUTO", tryOnSlot = "MAINHANDSLOT" },
    OH = { prefix = "oh", slot = 17, defType = "AUTO", tryOnSlot = "SECONDARYHANDSLOT" },
    RW = { prefix = "rw", slot = 18, defType = "AUTO", tryOnSlot = "RANGEDSLOT" },
}

-- Which weapon types each tab may use. Guns/crossbows and bows are ranged-only;
-- Wands are ranged-only too. Shield / Offhand is not allowed in the main hand; 2H Melee and
-- Staff are main-hand only.
local ALLOWED_TYPES = {
    MH = { AUTO = true, NONE = true, MELEE_1H = true, MELEE_2H = true, STAFF = true, EMPTY = true },
    OH = { AUTO = true, NONE = true, MELEE_1H = true, MELEE_1H_CASTER = true, SHIELD = true, OFFHAND = true },
    RW = { AUTO = true, NONE = true, GUN = true, BOW = true, WAND = true },
}
local SLOT_TO_HAND = { [16] = "MH", [17] = "OH", [18] = "RW" }

-- Accepts "MH" / "OH" / "RW", or the old boolean form (true = MH, false = OH).
local function HandKey(hand)
    if hand == true then return "MH" elseif hand == false then return "OH" end
    return HANDS[hand] and hand or "MH"
end

-- Abilities that should always fire the ranged weapon (Auto Shot, Shoot bow/gun/crossbow, Shoot wand, Throw)
-- Ranged attacks: Auto Shot, Shoot (wand / older clients), Throw, Shoot Bow / Gun / Crossbow
local RANGED_SPELLS = { [75] = true, [3018] = true, [5019] = true, [2764] = true,
                        [2480] = true, [7918] = true, [7919] = true }

-- Animation the hand/arm model plays by default, OfferLoop (character animation ID).
Anim.ID = 1784
-- Weapon types that use a different hand/arm animation: ArtBowLoop (968), ArtMainLoop (962).
-- (Anim.ID / Anim.BY_TYPE / Anim.SPEED_BY_TYPE are read by the ModelScene renderer.)
-- A key of "<TAB>_<TYPE>" (e.g. OH_MELEE_1H_CASTER) applies on that tab only and wins over the plain type.
Anim.BY_TYPE = {
    OH_MELEE_1H_CASTER = 940,   -- Caster Hand (Spell Casts OH)
    SHIELD = 968,
    OFFHAND = 968,
    BOW = 968,      -- same as Shield
    GUN = 962,
    WAND = 962,     -- same as Gun / Crossbow
}
-- Playback speed per weapon type in hand/arm mode (1 = normal, 0.5 = half speed).
-- Like Anim.BY_TYPE, a "<TAB>_<TYPE>" key applies on that tab only.
Anim.SPEED_BY_TYPE = {
    OH_MELEE_1H_CASTER = 0.5,   -- Caster Hand (Spell Casts OH)
    GUN = 0.5,
    BOW = 0.3,
    WAND = 0.5,     -- same as Gun / Crossbow
}


---@return table<string, any>
local function NewSettings()
    ---@type table<string, any>
    local db = {
        showEnchants = true,
        autoSheath = true,
        dynamicLighting = true,
        lightStrength = 1.0,
        ignoredSpells = {},
        enableBob = true,
        autoZoomToggle = true,
        showOrientation = false,  -- orientation sliders in the settings panel (shown/hidden by its toggle)  -- turn FPS mode on/off automatically at maximum camera zoom-in
        bobIntensity = 0.5,
        savedZoom = 0,
    }
    -- per hand (main, off, ranged): weapon type, custom item IDs and saved poses per type
    for _, pre in ipairs({ "mh", "oh", "rw" }) do
        db[pre .. "_type"], db[pre .. "_overrides"], db[pre .. "_transforms"] = "AUTO", {}, {}
    end
    return db
end

FPWeaponsDB = FPWeaponsDB or NewSettings()

--==[ Overlay & weapon model frames ]===========================================
local overlayFrame = CreateFrame("Frame", "FPWeaponsOverlay", UIParent)
overlayFrame:SetAllPoints(UIParent)
overlayFrame:SetFrameStrata("BACKGROUND")
-- This frame stays shown for the whole session. Weapons are hidden by fading them to zero
-- alpha instead (a 3D model ignores its parent's alpha), because a model frame that's hidden
-- and shown again loses part of its scale and position. State.fpOn says whether first-person mode is on.
State.fpOn = false
overlayFrame:EnableMouse(false)

local mhWeapon = CreateFrame("DressUpModel", nil, overlayFrame)
mhWeapon:SetAllPoints(overlayFrame)

local ohWeapon = CreateFrame("DressUpModel", nil, overlayFrame)
ohWeapon:SetAllPoints(overlayFrame)

local rwWeapon = CreateFrame("DressUpModel", nil, overlayFrame)
rwWeapon:SetAllPoints(overlayFrame)

local MODELS = { MH = mhWeapon, OH = ohWeapon, RW = rwWeapon }

-------------------------------------------------------------------------------
-- HAND/ARM MODE: MODELSCENE
-- Hand/arm mode renders through ModelScene actors instead of the DressUpModels above, because
-- actors support animation playback speed (DressUpModel:SetAnimation has no speed control).
-- Weapon-only mode still uses the DressUpModels. Everything for this lives in the one "Scene"
-- table to stay under Lua's 200 top-level local variable limit.
--
-- Scene space (yards): the camera sits at 0,0,0 looking forward. Slider Position X = right,
-- Position Y = away from the camera (depth), Position Z = up. The character's origin is the
-- centre of its body, so rotations pivot around the body rather than the feet.
-- Yaw / Facing uses the same convention as before: ~3.14 = facing away from the camera.
-------------------------------------------------------------------------------
local Scene = {
    ok = false,
    frames = {},
    actors = {},
    pending = {},           -- dressing to apply once an actor's model has loaded
    playing = {},           -- animation each actor is currently playing ("animID:speed")
    loaded = {},            -- true once the game has reported an actor's model as loaded
    loadEvents = 0,         -- how many OnModelLoaded events have fired (for /fpw scene)
    RETRY_TIMES = { 0.25, 0.6, 1.0, 1.6, 2.4, 3.5 },  -- re-apply checks while a model loads
    LOGIN_REBUILDS = { 5 },     -- seconds after loading in: rebuild the hand/arm models from scratch
    MISSING_REBUILD = 1.5,      -- if item data wasn't ready during a build, rebuild after this long
    missingTries = {},          -- [hand] = such rebuilds in a row (max 4 per hand)
    ready = {},             -- true once an actor has loaded + been dressed (until then it's hidden)
    fade = {},              -- 0..1 fade-in after loading
    FADE_TIME = 0.15,       -- seconds to fade a freshly loaded model in
    SETTLE_TIME = 0.15,     -- after loading/dressing, wait this long before showing it
    FOV = 0.9,              -- camera vertical field of view (radians); higher = wider view
    IDLE_SPEED = 0.75,      -- playback speed of the idle hand/arm animation (types without their own speed)
    NEAR_CLIP = 0.01,
    MOTION_POS = 0.3,       -- swing/bob/sheathe movement is scaled by this (the camera is close)
    MOTION_ROT = 0.5,       -- swing/sheathe rotation is scaled by this
    LIGHT_SIGN = -1,        -- flip to 1 if the model looks lit from behind
    SLEEVE_SLOTS = { 4, 5, 9, 10 },  -- shirt, chest, wrist, hands: so the arm and sleeve aren't bare
    LOOK_SLOTS = { 16, 17, 18, 4, 5, 9, 10 },  -- slots whose transmogged look is read: weapons and sleeve
    -- Starting transforms in hand/arm mode (used until you change them with the sliders)
    DEFAULTS = {
        MH = { scale = 1.0, facing = 3.14, pitch = 0.0, roll = 0.0, posX = 0.0, posY = -0.1, posZ = -0.4 },
        OH = { scale = 1.0, facing = 3.14, pitch = 0.0, roll = 0.0, posX = 0.0, posY = -0.1, posZ = -0.4 },
        RW = { scale = 1.0, facing = 3.14, pitch = 0.0, roll = 0.0, posX = 0.0, posY = -0.1, posZ = -0.4 },
    },
    -- Per-weapon-type starting transforms in hand/arm mode (override DEFAULTS above)
    TYPE_DEFAULTS = {
        MH = {
            MELEE_1H        = { scale = 11.7, facing = 3.0, pitch = -0.75, roll = -1.25, posX = 0.65, posY = 1.15, posZ = -0.7 },
            MELEE_1H_CASTER = { scale = 11.7, facing = 3.0, pitch = -0.75, roll = -1.25, posX = 0.65, posY = 1.15, posZ = -0.7 },
            MELEE_2H        = { scale = 11.7, facing = 3.0, pitch = -0.75, roll = -1.25, posX = 0.65, posY = 1.15, posZ = -0.7 },
            STAFF           = { scale = 11.7, facing = 3.0, pitch = -0.75, roll = -1.25, posX = 0.65, posY = 1.15, posZ = -0.7 },
            EMPTY           = { scale = 1.0, facing = 3.14, pitch = -0.75, roll = 0.0, posX = 0.1, posY = 0.8, posZ = -0.75 },  -- Caster Hand (MH)
        },
        OH = {
            SHIELD  = { scale = 1.0, facing = 1.5, pitch = 0.55, roll = -0.85, posX = -0.85, posY = 0.35, posZ = -0.4 },
            MELEE_1H = { scale = 1.0, facing = 1.5, pitch = 0.55, roll = -0.85, posX = -0.85, posY = 0.35, posZ = -0.4 },  -- same as Shield
            MELEE_1H_CASTER = { scale = 1.0, facing = 1.9, pitch = -2.25, roll = -0.65, posX = -0.3, posY = 0.2, posZ = 0.15 },  -- Caster Hand (OH)
            OFFHAND = { scale = 1.0, facing = 1.5, pitch = 0.55, roll = -0.85, posX = -0.85, posY = 0.35, posZ = -0.4 },
        },
        RW = {
            BOW     = { scale = 1.0, facing = 1.85, pitch = 0.7, roll = -0.9, posX = -0.6, posY = 0.15, posZ = -0.4 },
            GUN     = { scale = 1.0, facing = 3.55, pitch = 0.0, roll = 0.0, posX = 0.35, posY = 0.95, posZ = -1.05 },
            WAND    = { scale = 1.0, facing = 3.55, pitch = 0.0, roll = 0.0, posX = 0.35, posY = 0.95, posZ = -1.05 },
        },
    },
    -- MELEE ATTACKS (hand/arm mode): instead of moving the model around, each attack plays a
    -- character animation on that hand's model, then returns to its idle hand animation.
    -- ANIMS lists the animation IDs per "<TAB>_<TYPE>"; attacks cycle through the list (like the
    -- old 3-swing combo). A type listed here gets no scripted swing motion in hand/arm mode; an
    -- empty list means no attack animation at all. Types not listed keep their scripted motion
    -- (e.g. Shield bashes). Weapon-only mode always uses the scripted motion (no arm to animate).
    attack = {
        ANIMS = {
            -- (1H Melee on the Mainhand isn't listed: it uses the scripted heavy swing.
            --  To give it an animation again:  MH_MELEE_1H = { 654 },)
            MH_MELEE_2H        = { 58 },    -- 2H Melee
            OH_MELEE_1H        = { 1132 },  -- 1H Melee on the Offhand (the mainhand model is untouched)
            -- (dual wield 1H + 1H uses the "DUAL" action profile instead: Scene.cast.PROFILES)
        },
        SPEED = 1.0,     -- playback speed of the attack animations
        SPEEDS = {       -- per "<TAB>_<TYPE>" speed, overriding SPEED
            MH_MELEE_2H = 0.5,   -- 2H Melee attack at half speed
        },
        IMPACT = 0.25,   -- seconds into the attack where the hit lands (timed to your real swings)
        MAX = 0.9,       -- back to the idle hand animation after this long (at speed 1) if the
                         -- game doesn't report the attack animation finished
        active = {},     -- [hand] = true while an attack animation is playing
        token = {},
        -- Shield bashes only play when you block or use one of these shield abilities
        SHIELD_SPELLS = {
            [23922] = true, [2565] = true, [871] = true, [385952] = true, [23920] = true,  -- Warrior: Shield Slam/Block/Wall/Charge, Spell Reflection
            [31935] = true, [53600] = true,                                                -- Paladin: Avenger's Shield, Shield of the Righteous
            [72] = true,                                                                   -- Shield Bash (classic)
        },
        -- Each melee type has an ATTACK POSE (position while its attack animation plays), edited
        -- with "Edit Attack Pose"; it starts as a copy of the weapon's normal position.
        BLEND_TIME = 0.08,  -- seconds to glide into the attack pose
        BLEND_OUT = 0.25,   -- seconds to glide back out; starts this long before the attack ends,
                            -- so the arm is already heading home as the animation finishes
        -- How long each attack animation runs (seconds at speed 1) before switching back to idle.
        -- Animations hold their last frame, so a length that's too long shows a freeze and then
        -- a snap; too short cuts the swing off. Tune in game with  /fpw attacklen <id> <seconds>.
        LENGTHS = { [654] = 0.9, [58] = 0.75, [1132] = 0.9, [212] = 0.9, [650] = 0.9 },
        easing = {},        -- [hand] = true while gliding back before the attack ends
        CUT_SHORT = 0,      -- end every melee attack animation this many seconds early (0 = let it play through)
        blend = {},         -- [hand] 0 = normal pose, 1 = attack pose
        editing = nil,      -- "MH" / "OH" while "Edit Attack Pose" is on
    },
    -- SPELL CASTING (only with Caster Hand on both the Mainhand and the Offhand, in hand/arm mode):
    -- when a spell with a cast time starts, both hand models vanish and a separate casting model
    -- ("CAST") loops CAST_ANIM for the whole cast; when the spell goes off it plays RELEASE_ANIM,
    -- then the hands come back. An interrupted/cancelled cast brings the hands straight back.
    -- Instant spells skip the casting part and just play RELEASE_ANIM.
    cast = {
        -- ACTION PROFILES: which hands the action model replaces, and which animations it plays,
        -- for each weapon combination. The first matching profile wins, so combos come first.
        -- mh / oh = required weapon type for that hand (left out = anything). replace = hands that
        -- vanish while the action model is up (it holds those hands' weapons; Caster Hands are
        -- empty). cast = loops while casting, channel = loops while channelling, release = plays
        -- when the spell goes off (and after a channel), attack = melee attacks (dual wield).
        -- Several IDs in a list = they take turns. Each profile has its own poses ("key").
        PROFILES = {
            -- combinations
            { key = "BOTH",      mh = "EMPTY",    oh = "MELEE_1H_CASTER", replace = { MH = true, OH = true },
              cast = { 1088 }, release = { 904 },  channel = { 890 }, label = "MH + OH caster" },
            { key = "STAFF_OHC", mh = "STAFF",    oh = "MELEE_1H_CASTER", replace = { MH = true },
              cast = { 918 },  release = { 1104 }, channel = { 888 }, label = "Caster weapon + OH caster" },
            { key = "1H_OHC",    mh = "MELEE_1H", oh = "MELEE_1H_CASTER", replace = { MH = true },
              cast = { 918 },  release = { 1104 }, channel = { 888 }, label = "1H + OH caster" },
            { key = "MHC_ITEM",  mh = "EMPTY",    oh = "OFFHAND",         replace = { MH = true },
              cast = { 900 },  release = { 1110 }, channel = { 888 }, label = "MH caster + held item" },
            { key = "DUAL",      mh = "MELEE_1H", oh = "MELEE_1H",        replace = { MH = true, OH = true },
              attack = { 212, 650 }, label = "dual wield" },
            -- single hand (the other hand can be anything not covered above)
            { key = "MH",    mh = "EMPTY",           replace = { MH = true },
              cast = { 900 },      release = { 1092 }, channel = { 888 }, label = "MH caster" },
            { key = "STAFF", mh = "STAFF",           replace = { MH = true },
              cast = { 1040 },     release = { 1104 }, channel = { 888 }, label = "Caster weapon" },
            { key = "OH",    oh = "MELEE_1H_CASTER", replace = { OH = true },
              cast = { 922, 900 }, release = { 1108 }, channel = { 888 }, label = "OH caster" },
        },
        idx = {},               -- which ID of each list is next
        animKind = "cast",      -- kind of animation the action model is playing (for its speed)
        CAST_ANIM = 1088,       -- (fallbacks if a profile has no list for something)
        RELEASE_ANIM = 1092,
        CAST_SPEED = 1.0,       -- playback speed of CAST_ANIM (1 = normal)
        RELEASE_SPEED = 0.75,   -- playback speed of RELEASE_ANIM
        RELEASE_LINGER = 0.4,   -- seconds a release always plays before the next cast's pose takes over,
                                -- so chained spells don't snap straight from release back to casting
        RELEASE_MAX = 0.80,     -- how long the release animation is shown before the hands come back, at
                                -- normal speed: it is stretched to match RELEASE_SPEED (0.80 at 0.75x
                                -- = ~1.07s). Sooner if the game reports the animation finished. The
                                -- hands start their return RETURN_TIME before the end, so they arrive as it ends.
        STOP_GRACE = 0.15,      -- after a cast stops, wait this long for "succeeded" before cancelling
        -- After the release the hands come back from behind (pulled in toward you) to forward:
        RETURN_BACK = 1.6,      -- how far back they start (before the close-camera MOTION_POS scaling)
        RETURN_DROP = 0.7,      -- how far below they start: with RETURN_BACK this makes the path a
                                -- diagonal (up and forward); 0 = straight forward
        RETURN_TIME = 0.3,      -- seconds to push forward into place
        -- Caster Hands stay invisible while pulled back (the camera's near cut-off would slice
        -- through the arm/shoulder) and fade in as they arrive. 0 = fully back, 1 = in place:
        FADE_START = 0.55,      -- start fading in this far along the path
        FADE_END = 0.9,         -- fully visible by here
        returnBlend = 0,        -- 1 = fully back, 0 = in place
        returning = false,      -- hands already on their way back while the release finishes
        DEFAULT = { scale = 1.0, facing = 2.1, pitch = -0.35, roll = 1.3, posX = -0.15, posY = 1.4, posZ = -0.55 },          -- cast pose
        RELEASE_DEFAULT = { scale = 1.0, facing = 2.85, pitch = -0.2, roll = -0.9, posX = 0.55, posY = 0.6, posZ = -0.8 },  -- release pose
        state = nil,            -- nil / "casting" / "stopping" / "channeling" / "release" / "attack"
        showing = false,        -- casting model visible (hands hidden)
        editing = false,        -- false / "cast" / "release" / "attack": which pose the panel is editing
        anim = 1088,            -- animation the casting model should be playing
        token = 0,
    },
}
do
    for _, hand in ipairs({ "MH", "OH", "RW", "CAST" }) do
        local ok, f = pcall(CreateFrame, "ModelScene", nil, overlayFrame)
        if ok and f and f.CreateActor then
            f:SetAllPoints(overlayFrame)
            pcall(f.SetCameraPosition, f, 0, 0, 0)
            pcall(f.SetCameraOrientationByYawPitchRoll, f, 0, 0, 0)
            pcall(f.SetCameraFieldOfView, f, Scene.FOV)
            pcall(f.SetCameraNearClip, f, Scene.NEAR_CLIP)
            pcall(f.SetCameraFarClip, f, 100)
            pcall(f.SetAlpha, f, 0)
            local okA, a = pcall(f.CreateActor, f)
            if okA and a then
                pcall(a.SetUseCenterForOrigin, a, true, true, true)
                Scene.frames[hand] = f
                Scene.actors[hand] = a
            end
        end
    end
    Scene.ok = (Scene.actors.MH and Scene.actors.OH and Scene.actors.RW) and true or false
    -- An invisible extra copy of your character that is never undressed, used only to read
    -- which transmog appearances your weapons are showing (see Scene.Probe)
    if Scene.frames.MH then
        local okP, pa = pcall(Scene.frames.MH.CreateActor, Scene.frames.MH)
        if okP and pa then
            pcall(pa.SetAlpha, pa, 0)
            pcall(pa.SetPosition, pa, 0, 0, -1000)
            Scene.probe = pa
        end
    end
end

local RefreshWeaponModels  -- forward declaration (defined in the ITEM RENDER LOGIC section)

-- Default hand/arm-mode orientations for every race (taken from a tuned Skyborne female). Same
-- layout as a race entry in FPWeapons_RaceDefaults.lua; a race's own saved or shipped defaults
-- come first, and the per-type defaults above are used for anything not listed here.
Scene.GENERIC_DEFAULTS = {
        MH = {
            EMPTY                  = { scale = 1, facing = 3.14, pitch = -0.75, roll = 0, posX = 0.1, posY = 0.8, posZ = -0.75 },
            MELEE_1H               = { scale = 11.7, facing = 3, pitch = -0.75, roll = -1.25, posX = 0.65, posY = 1.15, posZ = -0.7 },
            MELEE_1H_ATTACK        = { scale = 11.7, facing = 3.45, pitch = -0.7, roll = -0.55, posX = 0.4, posY = -0.35, posZ = -0.85 },
            MELEE_1H_CASTER        = { scale = 11.7, facing = 3, pitch = -0.75, roll = -1.25, posX = 0.65, posY = 1.15, posZ = -0.7 },
            MELEE_1H_CASTER_ATTACK = { scale = 11.7, facing = 3.45, pitch = -0.7, roll = -0.55, posX = 0.4, posY = -0.35, posZ = -0.85 },
            MELEE_2H               = { scale = 11.7, facing = 3, pitch = -0.75, roll = -0.8, posX = 0.45, posY = 1.15, posZ = -0.9 },
            MELEE_2H_ATTACK        = { scale = 11.7, facing = 3.45, pitch = -0.7, roll = -0.55, posX = 0.45, posY = 0.95, posZ = -0.8 },
            STAFF                  = { scale = 11.7, facing = 3, pitch = -0.75, roll = -1.25, posX = 0.65, posY = 1.15, posZ = -0.7 },
        },
        OH = {
            MELEE_1H               = { scale = 1, facing = 1.5, pitch = 0.55, roll = -0.9, posX = -0.85, posY = 0.45, posZ = -0.4 },
            MELEE_1H_ATTACK        = { scale = 1, facing = 3.3, pitch = 0.5, roll = 1.05, posX = -0.3, posY = -0.6, posZ = 0 },
            MELEE_1H_CASTER        = { scale = 1, facing = 1.9, pitch = -2.25, roll = -0.65, posX = -0.3, posY = 0.2, posZ = 0.15 },
            SHIELD                 = { scale = 1, facing = 1.5, pitch = 0.55, roll = -0.85, posX = -0.85, posY = 0.35, posZ = -0.4 },
        },
        RW = {
            BOW                    = { scale = 1, facing = 1.85, pitch = 0.7, roll = -0.9, posX = -0.6, posY = 0.15, posZ = -0.4 },
            GUN                    = { scale = 1, facing = 3.55, pitch = 0, roll = 0, posX = 0.35, posY = 0.95, posZ = -1.05 },
            WAND                   = { scale = 1, facing = 3.55, pitch = 0, roll = 0, posX = 0.35, posY = 0.95, posZ = -1.05 },
        },
        CAST               = { scale = 1, facing = 2.1, pitch = -0.7, roll = 1.25, posX = -0.15, posY = 1.4, posZ = -0.55 },
        CAST_1H_OHC        = { scale = 1, facing = 3.8, pitch = -0.2, roll = -1.4, posX = 0.55, posY = 1, posZ = -0.65 },
        CAST_MH            = { scale = 1, facing = 3.8, pitch = -0.5, roll = -1.15, posX = 0.5, posY = -0.05, posZ = -0.85 },
        CAST_MHC_ITEM      = { scale = 1, facing = 3.7, pitch = 0, roll = -1.9, posX = 0.5, posY = 0.8, posZ = -0.3 },
        CAST_OH            = { scale = 1, facing = 2.8, pitch = -0.15, roll = 1.35, posX = -0.85, posY = 1.75, posZ = -0.65 },
        CAST_STAFF         = { scale = 1, facing = 5.75, pitch = -0.45, roll = -1.4, posX = -1.15, posY = 1.2, posZ = -0.6 },
        CAST_STAFF_OHC     = { scale = 1, facing = 4.3, pitch = -0.3, roll = -1.2, posX = 0.65, posY = 0.95, posZ = -0.65 },
        RELEASE            = { scale = 1, facing = 3.1, pitch = -0.6, roll = 0.05, posX = -0.15, posY = 0.55, posZ = -1.05 },
        RELEASE_MH         = { scale = 1, facing = 2.85, pitch = -0.2, roll = -0.9, posX = -0.1, posY = 0, posZ = -0.7 },
        RELEASE_MHC_ITEM   = { scale = 1, facing = 3, pitch = -0.8, roll = -0.8, posX = 0.35, posY = 1.05, posZ = -0.65 },
        RELEASE_OH         = { scale = 1, facing = 3.2, pitch = -0.5, roll = 0.65, posX = -0.6, posY = 0.5, posZ = -1 },
        RELEASE_STAFF_OHC  = { scale = 1, facing = 3.2, pitch = -0.5, roll = 0.25, posX = -0.1, posY = 0.7, posZ = -1.1 },
        RELEASE_STAFF      = { scale = 1, facing = 3.25, pitch = -0.5, roll = 0.05, posX = 0.25, posY = 0.95, posZ = -1.1 },
        RELEASE_1H_OHC     = { scale = 1, facing = 3.15, pitch = -0.5, roll = -0.15, posX = 0.2, posY = 0.6, posZ = -0.95 },
        ATTACK_DUAL        = { scale = 1, facing = 3.15, pitch = -0.95, roll = 0, posX = -0.05, posY = 0.9, posZ = -1.2 },
}

-- DYNAMIC LIGHTING settings (see the DYNAMIC LIGHTING section)
Scene.light = {
    COLOR_EASE = 3.0,    -- seconds for brightness/colour changes (dusk, going indoors...) to settle
    DIR_EASE = 0.15,     -- seconds for the light direction to follow you as you turn
    SUN_FLIP = 1,        -- set to -1 if facing the sun leaves your hands dark (and vice versa)
    FLASH_TIME = 0.35,   -- seconds a spell flash takes to fade
    FLASH_BOOST = 0.6,   -- how bright a spell flash is
    FLASH_COLOR = { 1.0, 0.85, 0.6 },  -- default flash colour (warm)
    SPELL_COLORS = {     -- optional flash colour per spell ID, e.g. [133] = { 1.0, 0.5, 0.2 } (Fireball)
    },
    UPDATE = 0.05,       -- seconds between lighting updates
    flash = 0, flashColor = nil, timer = 0,
}

-- True when hand/arm mode should render through the ModelScene
function Scene.Active()
    return Scene.ok and true or false
end

--==[ Sheathe, stealth & mounts ]===============================================
State.mountHidden = false

-- Sheathe state / draw state. Weapons are lowered out of view when out of combat and raised back
-- when you enter combat or use an ability.
Sheath.DELAY   = 10    -- seconds after leaving combat before the weapons are sheathed
Sheath.ABILITY_HOLD   = 10    -- seconds the weapons stay drawn after an out-of-combat ability
Sheath.DRAW_SPEED     = 4.5   -- blend units per second when drawing (fast)
Sheath.SPEED   = 2.2   -- blend units per second when sheathing (slower, more deliberate)
Sheath.DROP    = 1.1   -- how far the weapons drop out of the bottom of the view
Sheath.BACK    = 0.35  -- how far they pull back toward you while lowering
Sheath.SIDE    = 0.35  -- how far they swing out to their own side while lowering
Sheath.TILT    = 0.5   -- pitch tilt while lowering (flip the sign if the tip tips the wrong way)
Sheath.ROLL    = 0.35  -- roll tilt while lowering
Sheath.HAND_MULT = 1.5 -- hand/arm mode needs a bigger drop (the model is larger)

State.sheathBlend = UnitAffectingCombat("player") and 0 or 1  -- 0 = drawn, 1 = fully sheathed
State.drawTimer = 0

local function SheathEase()
    local b = State.sheathBlend
    return b * b * (3 - 2 * b)  -- smoothstep
end

-- RANGED SWAP: the ranged weapon is never on screen together with the main / off hand. While a
-- main or off hand is showing, the ranged weapon stays put away; a ranged attack brings it out
-- (and puts the other hands away) for a few seconds after the last shot, then it swaps back.
-- The swap is a sheathe of one set and a draw of the other: the hands being put away drop out
-- of view first (first half of SWAP_TIME), then the others rise into place (second half).
Scene.ranged = { out = 0, untilT = 0, HOLD = 5, SWAP_TIME = 0.5 }
function Scene.ranged.MeleeShown()
    return (mhWeapon.fpVisible or ohWeapon.fpVisible) and true or false
end
-- How far a hand is put away by the swap: 0 = in place, 1 = fully lowered out of view
function Scene.ranged.Drop(hand)
    local R = Scene.ranged
    if not R.MeleeShown() then return 0 end
    local d
    if hand == "RW" then d = (1 - R.out) * 2
    elseif hand == "MH" or hand == "OH" then d = R.out * 2
    else return 0 end
    return d > 1 and 1 or d
end
function Scene.ranged.Ease(hand)
    local d = Scene.ranged.Drop(hand)
    return d * d * (3 - 2 * d)
end
-- Multiplier for a hand's visibility: like the sheathe, it fades over the last of the drop
function Scene.ranged.Factor(hand)
    local d = Scene.ranged.Drop(hand)
    if d <= 0.6 then return 1 end
    return 1 - (d - 0.6) / 0.4
end
-- Bring the ranged weapon out (on the press of a ranged attack, and again on each shot)
function Scene.ranged.Out()
    Scene.ranged.untilT = GetTime() + Scene.ranged.HOLD
    State.drawTimer = math.max(State.drawTimer, Sheath.ABILITY_HOLD)
end
-- Steps the swap each frame; true while it's moving
function Scene.ranged.Step(elapsed)
    local R = Scene.ranged
    local target = (GetTime() < R.untilT) and 1 or 0
    if R.out == target then return false end
    local step = elapsed / R.SWAP_TIME
    R.out = (target > R.out) and math.min(1, R.out + step) or math.max(0, R.out - step)
    return true
end

-- How visible the weapons are before sheathing etc.: hidden when first-person mode is off or
-- you're mounted, see-through while stealthed
Scene.STEALTH_ALPHA = 0.35
function Scene.BaseAlpha()
    if not State.fpOn or State.mountHidden then return 0 end
    return IsStealthed() and Scene.STEALTH_ALPHA or 1
end

local function UpdateVisibility()
    local alphaVal = 0
    if State.fpOn and not State.mountHidden then
        alphaVal = Scene.BaseAlpha()
        if State.sheathBlend > 0.6 then  -- fade out over the last of the drop so it can't linger on screen
            alphaVal = alphaVal * (1 - (State.sheathBlend - 0.6) / 0.4)
        end
    end
    mhWeapon:SetAlpha(alphaVal * Scene.ranged.Factor("MH"))
    ohWeapon:SetAlpha(alphaVal * Scene.ranged.Factor("OH"))
    rwWeapon:SetAlpha(alphaVal * Scene.ranged.Factor("RW"))
    local c = Scene.cast
    local casting = c.showing and Scene.CastEnabled and Scene.CastEnabled()
    local base = Scene.BaseAlpha()
    -- Caster Hands: visibility follows how far along their back/forward path they are
    -- (0 = fully back, 1 = in place), so they only appear once clear of the camera's cut-off
    local function along(prog)
        local k = (prog - c.FADE_START) / (c.FADE_END - c.FADE_START)
        k = k < 0 and 0 or (k > 1 and 1 or k)
        return k * k * (3 - 2 * k)
    end
    local rb = c.returnBlend * c.returnBlend * (3 - 2 * c.returnBlend)
    local overlap = c.returning and (c.state == "release" or c.state == "attack")  -- hands arriving as it finishes
    for hand, f in pairs(Scene.frames) do
        local av = alphaVal
        if hand == "CAST" then
            -- shown only while casting/editing, instantly, at full (or stealth) strength;
            -- at the end of a release it fades out as the hands fade in
            av = (casting and State.fpOn and not State.mountHidden) and base or 0
            if overlap then av = av * (1 - along(1 - rb)) end
        elseif casting and not overlap and Scene.Replaced and Scene.Replaced(hand) then
            av = 0  -- hands the action model replaces vanish instantly while it's up
        elseif Scene.CasterHand and Scene.CasterHand(hand) then
            -- for the post-release return and for sheathe/draw alike
            local sb = State.sheathBlend * State.sheathBlend * (3 - 2 * State.sheathBlend)  -- same easing as the motion
            av = base * along(1 - sb) * along(1 - rb)
        elseif c.returnBlend > 0 and Scene.Replaced and Scene.Replaced(hand) then
            av = av * along(1 - rb)  -- a replaced weapon hand (staff, 1H...) fades in on its way back
        end
        av = av * (Scene.fade[hand] or 1)  -- hidden while loading, then fades in
        av = av * Scene.ranged.Factor(hand)    -- ranged weapon and main / off hand take turns
        pcall(f.SetAlpha, f, av)
        local a = Scene.actors[hand]
        if a then pcall(a.SetAlpha, a, av) end
    end
end
UpdateVisibility()  -- start invisible

-- Riding (mount, vehicle or flight path): the weapons are put away and the camera pulls back
-- so you can see what you're riding; getting off brings the first-person view back.
Scene.MOUNT_CAMERA_OUT = 9   -- yards the camera pulls back while riding
Scene.CAMERA_ALL_IN = 40      -- (more than enough to zoom fully back in)
local function UpdateMountState()
    if not State.fpOn then return end
    local riding = (IsMounted() or UnitInVehicle("player") or UnitOnTaxi("player")) and true or false
    if riding == State.mountHidden then return end
    State.mountHidden = riding
    UpdateVisibility()
    if riding then CameraZoomOut(Scene.MOUNT_CAMERA_OUT) else CameraZoomIn(Scene.CAMERA_ALL_IN) end
end

--==[ Motion state ]============================================================
State.mhMotion = 0
State.ohMotion = 0
State.rwMotion = 0
State.mhMotionRate = 3.5   -- progress units per second (per hand so heavy swings can be slower)
State.ohMotionRate = 3.5
State.rwMotionRate = 3.0
State.nudgeFlip = false  -- flips each resync so the engine can't ignore "unchanged" values
State.comboStep = 1
State.mainHandNext = true

-- View-motion tuning
-- Movement sway (Skyrim-style). All values are at Sway Strength 1.0; the slider scales them.
local Bob = {
    STRIDE_RATE  = 8.0,    -- stride cycle speed at a run (radians/s; one cycle = two steps)
    RUN_SPEED    = 7,      -- movement speed (yards/s) treated as a full run
    SWAY_X       = 0.035,  -- side-to-side sway, weight shifting from foot to foot
    DIP_Z        = 0.025,  -- dip at each footfall (the weapon traces a "U" between steps)
    ROLL         = 0.05,   -- tilt toward the stepping side (radians)
    PITCH        = 0.03,   -- nod down on each footfall (radians)
    TURN_GAIN    = 0.35,   -- how strongly turning makes the weapons trail behind
    TURN_X       = 0.05,   -- how far they trail sideways on a fast turn
    TURN_FACING  = 0.12,   -- how far they twist on a fast turn (flip the sign if it twists the wrong way)
    TURN_SETTLE  = 7,      -- how quickly they catch up after a turn (higher = snappier)
    BREATH_RATE  = 1.4,    -- idle breathing speed (radians/s)
    BREATH_Z     = 0.004,  -- idle breathing rise/fall
    BREATH_PITCH = 0.008,  -- idle breathing tilt
    -- state
    phase = 0, breath = 0, turn = 0, speedK = 1, lastFacing = nil,
}
Bob.AIR_LIFT = 0.05   -- how far the weapons float up while airborne
Bob.LANDING_DIP  = 0.12   -- how far the weapons dip on landing

-- View-motion state
State.strideBlend = 0       -- 0..1 fade for the walking bob (eases out instead of freezing mid-offset)
State.airBlend = 0      -- 0..1 while airborne
State.landingDip = 0       -- 1 -> 0 landing-dip timer
State.wasAirborne = false
State.reassertTimer = 0
State.lookPollTimer = 0
State.lastLookKey = nil

--==[ Weapon effects (enchant glow) ]===========================================

-- A value we're allowed to look at, or nil (secret values can't be compared or stored)
local function Readable(v)
    if v ~= nil and not issecretvalue(v) then return v end
    return nil
end

-- Temporary weapon effects (stones, oils, imbues), per hand: the effect's enchant ID, -1 when an
-- effect is there but the game won't say which, or nil when there's none
local function ReadTempEffects()
    if not GetWeaponEnchantInfo then return nil, nil end
    local r = { pcall(GetWeaponEnchantInfo) }
    if not r[1] then return nil, nil end
    -- returns: has, expiry, charges, id for the main hand, then the same four for the off hand
    local function effect(has, id)
        if not Readable(has) then return nil end
        return tonumber(Readable(id)) or -1
    end
    return effect(r[2], r[5]), effect(r[6], r[9])
end

-- A permanent enchant is the field after the item ID in the item link ("item:ID:ENCHANT:...")
local function EnchantFromLink(link)
    link = Readable(link)
    if type(link) ~= "string" then return nil end
    local id = tonumber(link:match("item:%d+:(%d*)") or "")
    return (id and id > 0) and id or nil
end

-- The effect a weapon slot shows: a temporary effect wins over a permanent enchant (only one
-- glow can be shown). Returns the enchant ID and "temp" / "perm", or nil.
local function SlotEffect(slotID)
    if FPWeaponsDB.showEnchants == false then return nil end
    local tempMH, tempOH = ReadTempEffects()
    local temp = (slotID == 16 and tempMH) or (slotID == 17 and tempOH) or nil
    if temp then return temp, "temp" end
    local perm = EnchantFromLink(GetInventoryItemLink("player", slotID))
    if perm then return perm, "perm" end
    return nil
end

-- An enchant's illusion visual, for the weapon-only renderer (nil if the game has none for it)
local function EffectVisual(enchantID)
    if not (enchantID and enchantID > 0) then return nil end
    local lookup = C_TransmogCollection and C_TransmogCollection.GetIllusionInfo
    if not lookup then return nil end
    local ok, info = pcall(lookup, enchantID)
    return (ok and type(info) == "table" and info.visualID) or nil
end

-- Current movement speed in yards/s (nil if the game won't say)
function Bob.GetSpeed()
    local ok, speed = pcall(GetUnitSpeed, "player")
    if ok and type(speed) == "number" and not issecretvalue(speed) then return speed end
    return nil
end

-- Turn lag: track how fast you're turning and let the weapons trail behind, then settle.
-- Returns true while there's any lag left to show.
function Bob.UpdateTurn(elapsed)
    local ok, facing = pcall(GetPlayerFacing)
    local target = 0
    if ok and type(facing) == "number" and not issecretvalue(facing) then
        if Bob.lastFacing and elapsed > 0 then
            local d = facing - Bob.lastFacing
            if d > math.pi then d = d - 2 * math.pi elseif d < -math.pi then d = d + 2 * math.pi end
            target = math.max(-1, math.min(1, (d / elapsed) * Bob.TURN_GAIN))
        end
        Bob.lastFacing = facing
    else
        Bob.lastFacing = nil  -- facing unavailable (e.g. restricted in some content): no turn lag
    end
    Bob.turn = Bob.turn + (target - Bob.turn) * (1 - math.exp(-elapsed * Bob.TURN_SETTLE))
    if math.abs(Bob.turn) < 0.0005 and target == 0 then Bob.turn = 0 end
    return Bob.turn ~= 0
end

-- Moving: by speed when the game will say; otherwise falling or mouse-steering counts as moving
local function IsMoving()
    local speed = Bob.GetSpeed()
    if speed then return speed > 0 end
    return (IsFalling() or IsMouselooking()) and true or false
end


-- Per-weapon-type starting transforms (used in both weapon-only and hand/arm mode until you
-- change them with the sliders). Written for the right side; the offhand gets a mirrored copy.
Defaults.ONEHAND = { scale = 6.2, facing = 3.4, pitch = -0.8, roll = -1.5, posX = 1.4, posY = 2.05, posZ = -1.7 }
Defaults.TYPE = {
    MELEE_1H = Defaults.ONEHAND,
    MELEE_1H_CASTER = Defaults.ONEHAND,
    WAND = Defaults.ONEHAND,
    EMPTY = Defaults.ONEHAND,   -- Empty Hand uses the same settings as Wand
    -- Gun / Crossbow and Bow are ranged-only, so these are used as-is on the Ranged tab
    GUN = { scale = 11.7, facing = 3.35, pitch = 0.05, roll = 0.3, posX = -0.05, posY = 2.0, posZ = -1.85 },
    BOW = { scale = 10.1, facing = 0.7, pitch = -0.3, roll = 1.05, posX = 1.1, posY = 1.7, posZ = -1.85 },
}

-- Per-type defaults for the mainhand: all melee weapons (and Staff, which follows 2H).
Defaults.MH_MELEE = { scale = 8.5, facing = 3.4, pitch = -0.85, roll = -1.2, posX = 1.2, posY = 1.55, posZ = -1.8 }
Defaults.MH_TYPE = {
    MELEE_1H = Defaults.MH_MELEE,
    MELEE_1H_CASTER = Defaults.MH_MELEE,
    MELEE_2H = Defaults.MH_MELEE,
    STAFF = Defaults.MH_MELEE,
}

-- Per-type defaults written specifically for the offhand (used as-is, not mirrored).
Defaults.OH_TYPE = {
    SHIELD = { scale = 6.0, facing = 1.9, pitch = 0.65, roll = 0.0, posX = -1.35, posY = 3.25, posZ = -1.6 },
    MELEE_1H = { scale = 6.0, facing = 1.9, pitch = 0.65, roll = 0.0, posX = -1.35, posY = 3.25, posZ = -1.6 },  -- same as Shield
    OFFHAND = { scale = 6.0, facing = 2.1, pitch = 0.45, roll = -0.6, posX = -0.9, posY = 3.75, posZ = -1.45 },
}

local function MirrorTransform(t)
    return {
        scale = t.scale,
        facing = (2 * math.pi) - t.facing,
        pitch = t.pitch,
        roll = -t.roll,
        posX = -t.posX,
        posY = t.posY,
        posZ = t.posZ,
    }
end

-- AUTO-DETECT: work out each hand's weapon type from what you have equipped.
-- Bows, guns, crossbows and wands sit in the main-hand slot on modern clients, so they go to the
-- Ranged tab (and the main hand shows nothing). An empty off hand becomes a Caster Hand for
-- Intellect specs holding a 1H or nothing, and stays empty otherwise.
Scene.auto = {
    -- weapon (item class 2) subclasses
    MH_SUB = { [0] = "MELEE_1H", [4] = "MELEE_1H", [7] = "MELEE_1H", [9] = "MELEE_1H", [11] = "MELEE_1H",
               [12] = "MELEE_1H", [13] = "MELEE_1H", [14] = "MELEE_1H", [15] = "MELEE_1H",
               [1] = "MELEE_2H", [5] = "MELEE_2H", [6] = "MELEE_2H", [8] = "MELEE_2H", [17] = "MELEE_2H",
               [20] = "MELEE_2H", [10] = "STAFF" },
    RANGED_SUB = { [2] = "BOW", [3] = "GUN", [18] = "GUN", [16] = "GUN", [19] = "WAND" },
    CASTER_CLASSES = { MAGE = true, PRIEST = true, WARLOCK = true, EVOKER = true },
}
function Scene.auto.Info(slot)
    local okI, id = pcall(GetInventoryItemID, "player", slot)
    if not okI or not id then return nil end
    local ok, _, _, _, equipLoc, _, classID, subID = pcall(C_Item and C_Item.GetItemInfoInstant, id)
    if not ok then return nil end
    return classID, subID, equipLoc
end
function Scene.auto.IsCaster()
    local ok, spec = pcall(GetSpecialization)
    if ok and spec then
        local ok2, _, _, _, _, _, stat = pcall(GetSpecializationInfo, spec)
        if ok2 and type(stat) == "number" then return stat == 4 end  -- 4 = Intellect
    end
    local okC, _, class = pcall(UnitClass, "player")
    return (okC and Scene.auto.CASTER_CLASSES[class or ""]) or false
end
Scene.CASTER_SWITCH = { MELEE_1H = true, STAFF = true }
-- classes whose main-hand weapon counts as a Caster Weapon
Scene.CASTER_WEAPON_CLASSES = { MAGE = true, PRIEST = true, WARLOCK = true, SHAMAN = true, PALADIN = true, DRUID = true }
function Scene.IsCasterClass()
    local ok, _, class = pcall(UnitClass, "player")
    return (ok and Scene.CASTER_WEAPON_CLASSES[class or ""]) and true or false
end
Scene.autoAttackOn = false   -- (kept up to date every frame)
-- True when the main hand switches between Caster Weapon and One-Handed with Auto Attack.
-- Only the type changes then, not the model, so the hand isn't rebuilt for it.
function Scene.MainSwitches()
    if FPWeaponsDB.mh_type ~= "AUTO" or not Scene.IsCasterClass() then return false end
    local mh = Scene.auto.Detect()
    return Scene.CASTER_SWITCH[mh] and true or false
end

-- Returns the detected types for MH, OH and RW
function Scene.auto.Detect()
    local A = Scene.auto
    local mh, rw, rwSlot = "EMPTY", "NONE", nil
    -- an actual ranged slot (older clients) first
    local c18, s18 = A.Info(18)
    if c18 == 2 and A.RANGED_SUB[s18] then rw, rwSlot = A.RANGED_SUB[s18], 18 end
    local c, sub, loc = A.Info(16)
    if c == 2 and A.RANGED_SUB[sub] then
        rw, rwSlot, mh = A.RANGED_SUB[sub], 16, "NONE"
    elseif c == 2 then
        mh = A.MH_SUB[sub] or ((loc == "INVTYPE_2HWEAPON") and "MELEE_2H" or "MELEE_1H")
    elseif c then
        mh = "MELEE_1H"
    end
    local oh
    c, sub, loc = A.Info(17)
    if c == 4 and sub == 6 then oh = "SHIELD"
    elseif c == 2 then oh = "MELEE_1H"        -- any weapon in the off hand (incl. Titan's Grip 2H)
    elseif c then oh = "OFFHAND"              -- held-in-off-hand items
    elseif (mh == "EMPTY" or mh == "MELEE_1H" or rw == "WAND") and A.IsCaster() then oh = "MELEE_1H_CASTER"
    elseif mh == "EMPTY" then oh = "MELEE_1H_CASTER"  -- bare hands: both hands cast
    else oh = "NONE" end
    return mh, oh, rw, rwSlot
end

local function GetHandType(hand)
    local key = HandKey(hand)
    local h = HANDS[key]
    local t = FPWeaponsDB[h.prefix .. "_type"]
    -- A type this hand can no longer use (e.g. a Gun saved on the main hand) falls back to the default
    if not t or not ALLOWED_TYPES[key][t] then t = h.defType end
    local mh, oh, rw, rwSlot
    if t == "AUTO" or (key ~= "RW" and FPWeaponsDB.rw_type == "AUTO") then mh, oh, rw, rwSlot = Scene.auto.Detect() end
    if t == "AUTO" then
        t = (key == "MH" and mh) or (key == "OH" and oh) or rw
        -- For caster classes, an auto-detected one-handed weapon or staff is a Caster Weapon for
        -- spells and a One-Handed Weapon while Auto Attack is on. Other classes always swing it
        -- as a melee weapon (a staff two-handed).
        if key == "MH" and Scene.CASTER_SWITCH[t] then
            if Scene.IsCasterClass() then
                t = Scene.autoAttackOn and "MELEE_1H" or "STAFF"
            elseif t == "STAFF" then
                t = "MELEE_2H"
            end
        end
    end
    -- An auto-detected bow / gun / crossbow is held in both hands, so the main and off hand show
    -- nothing even if you picked a type for them by hand (a wand only takes the main hand)
    if key ~= "RW" and rwSlot == 16 and (key == "MH" or rw ~= "WAND") then t = "NONE" end
    return t
end

-- Weapon type to use for animations (swing motion, hand/arm animation, timing).
-- 1H Melee on the Offhand animates exactly like a Shield.
Anim.OH_AS = { MELEE_1H = "SHIELD" }
local function GetAnimType(hand)
    local ty = GetHandType(hand)
    if HandKey(hand) == "OH" and Anim.OH_AS[ty] then return Anim.OH_AS[ty] end
    return ty
end

local GetPose
-- A pose saved or written with other names (side / depth / height / yaw / size, or x / y / z),
-- or with values missing, is put into the names the addon uses (in place), so it can't break
-- the models. Returns the same table.
Scene.POSE_ALIASES = {
    posX = { "side", "x" }, posY = { "depth", "y" }, posZ = { "height", "z" },
    facing = { "yaw" }, scale = { "size" }, pitch = {}, roll = {},
}
Scene.POSE_FALLBACK = { posX = 0, posY = 0, posZ = 0, facing = math.pi, scale = 1, pitch = 0, roll = 0 }
function Scene.FixPose(t)
    if type(t) ~= "table" then return t end
    for field, names in pairs(Scene.POSE_ALIASES) do
        if type(t[field]) ~= "number" then
            for _, alt in ipairs(names) do
                if type(t[alt]) == "number" then t[field] = t[alt]; break end
            end
            if type(t[field]) ~= "number" then t[field] = Scene.POSE_FALLBACK[field] end
        end
    end
    return t
end

GetPose = function(hand)
    if hand == "ATTACK_MH" or hand == "ATTACK_OH" then
        -- Attack pose for this hand's current weapon type (hand/arm mode). Starts from this race's
        -- saved default, else a copy of the weapon's normal position.
        local h = hand:sub(8)
        local ty = GetHandType(h)
        local tkey = HANDS[h].prefix .. "_transforms"
        FPWeaponsDB[tkey] = FPWeaponsDB[tkey] or {}
        local key = ty .. "_ATTACK_SCENE"
        if not FPWeaponsDB[tkey][key] then
            local d = (Scene.RaceDefault and Scene.RaceDefault(h, ty .. "_ATTACK")) or GetPose(h)
            FPWeaponsDB[tkey][key] = {
                scale = d.scale, facing = d.facing, pitch = d.pitch or 0, roll = d.roll or 0, posX = d.posX, posY = d.posY, posZ = d.posZ,
            }
        end
        return Scene.FixPose(FPWeaponsDB[tkey][key])
    end
    if hand == "CAST" or hand == "RELEASE" or hand == "ATTACK" then
        -- The action model's cast / release / attack poses (channels use the cast pose). Each caster setup (both hands, Mainhand
        -- only, Offhand only) has its own pair. A missing pose starts from this race's saved
        -- default, else (single-hand setups) a copy of the both-hands pose, else the built-in one.
        local setup = (Scene.CastSetup and Scene.CastSetup()) or "BOTH"
        if hand == "ATTACK" then local pa = Scene.Profile(true); setup = pa and pa.key or setup end
        local key = Scene.PoseKey(hand, setup)
        if not FPWeaponsDB[key] then
            local d = Scene.RaceDefault and Scene.RaceDefault(hand, setup)
            if not d and setup ~= "BOTH" then d = FPWeaponsDB[Scene.PoseKey(hand, "BOTH")] end
            d = d or (hand == "RELEASE" and Scene.cast.RELEASE_DEFAULT or Scene.cast.DEFAULT)
            FPWeaponsDB[key] = {
                scale = d.scale, facing = d.facing, pitch = d.pitch or 0, roll = d.roll or 0, posX = d.posX, posY = d.posY, posZ = d.posZ,
            }
        end
        return Scene.FixPose(FPWeaponsDB[key])
    end
    hand = HandKey(hand)
    local ty = GetHandType(hand)
    local listKey = HANDS[hand].prefix .. "_transforms"
    FPWeaponsDB[listKey] = FPWeaponsDB[listKey] or {}
    local saved = FPWeaponsDB[listKey]

    -- Where a pose starts before you've moved it: the most specific default that exists
    local base, poseKey = nil, ty .. "_ARM"
    if Scene.Active() then
        -- ModelScene hand/arm mode has its own units, so its own poses (saved as TYPE_SCENE)
        base = (Scene.RaceDefault and Scene.RaceDefault(hand, ty))
            or Scene.TYPE_DEFAULTS[hand][ty] or Scene.DEFAULTS[hand]
        poseKey = ty .. "_SCENE"
    else
        local typeDefault = Defaults.TYPE[ty]
        if hand == "MH" and Defaults.MH_TYPE[ty] then base = Defaults.MH_TYPE[ty]
        elseif hand == "OH" and Defaults.OH_TYPE[ty] then base = Defaults.OH_TYPE[ty]
        elseif typeDefault then base = (hand == "OH") and MirrorTransform(typeDefault) or typeDefault
        else
            base = (hand == "MH" and (ty == "MELEE_2H" or ty == "STAFF")) and Defaults.ARM.MH_2H or Defaults.ARM[hand]
        end
        poseKey = ty .. "_ARM"   -- (the old hand renderer keeps its own poses)
    end

    local pose = saved[poseKey]
    if not pose then
        pose = {}
        for _, f in ipairs({ "scale", "facing", "posX", "posY", "posZ" }) do pose[f] = base[f] end
        pose.pitch, pose.roll = base.pitch or 0, base.roll or 0
        saved[poseKey] = pose
    end

    pose.pitch, pose.roll = pose.pitch or 0, pose.roll or 0
    return Scene.FixPose(pose)
end

-- Heavy 2H swing

Cleave.SPEED = 1.2        -- 2H swings last ~0.83s (1H swings are ~0.29s); lower = slower
Cleave.TRAVEL = 0.85   -- scales how far the weapon TRAVELS in a 2H swing (1.0 = full keyframes)
Cleave.TURN = 1.0 -- scales how far the weapon ROTATES (pitch/roll) in a 2H swing
Cleave.PITCH_DIR = 1      -- set to -1 if the blade tilts the wrong way (back on the strike, forward on the windup)
Cleave.ROLL_DIR = 1       -- set to -1 if the diagonal slashes lean the wrong way

-- Easing curves (t from 0 to 1)
local Curve = {
    Out   = function(t) local r = 1 - t; return 1 - r * r * r end,   -- fast start, gentle stop
    In    = function(t) return t * t * t end,                         -- gentle start, fast finish
    InOut = function(t)                                               -- gentle at both ends
        if t < 0.5 then return 4 * t * t * t end
        local r = 1 - t
        return 1 - 4 * r * r * r
    end,
}

--                  x      y      z    facing  scale  pitch   roll
-- pitch: negative = tip tilts back/up (windup), positive = tip drives forward/down (strike)
-- roll:  tilts the blade sideways so diagonal cuts actually look diagonal
Cleave.WINDUP = {
    [1] = {  0.45, -0.15,  0.50, -0.50, 0.00, -0.55,  0.60 },  -- high right: raise sword up behind the right shoulder
    [2] = { -0.45, -0.15,  0.40,  0.45, 0.00, -0.45, -0.60 },  -- backhand: cock it up and out to the left
    [3] = {  0.15, -0.20,  0.70, -0.15, 0.00, -0.95,  0.10 },  -- overhead: haul it high and back over the head
}
Cleave.STRIKE = {
    [1] = { -0.70,  0.35, -0.55,  0.95, 0.12,  0.70, -0.80 },  -- diagonal cut: forward, down and across to low left
    [2] = {  0.65,  0.35, -0.45, -0.85, 0.12,  0.55,  0.80 },  -- backhand cut: forward, down and across to low right
    [3] = { -0.05,  0.45, -0.70,  0.15, 0.14,  0.95, -0.15 },  -- overhead chop: straight down and into the screen
}
Cleave.FIELDS = 7
State.cleaveOut = { 0, 0, 0, 0, 0, 0, 0 }

-- Swing settings (one table, to stay under Lua's local variable limit)
local Swing = {
    SPEEDS = { MELEE_1H = 1.45, MELEE_1H_CASTER = 1.45, MELEE_2H = 1.05 },  -- higher = faster; 1H quicker than 2H
    IMPACT_T = 0.45,  -- point in the swing (0-1) where the blade passes the target
    FOLLOW = 0.2,     -- follow-through: how far the weapon carries on past the strike pose
    -- per-swing variation, so no two swings are identical (re-rolled every swing by Swing.New)
    var = { MH = { amp = 1, rot = 1, arc = 1 }, OH = { amp = 1, rot = 1, arc = 1 } },
}

function Swing.New(hand)
    local v = Swing.var[hand]
    if not v then return end
    v.amp = 0.9 + math.random() * 0.2    -- 90-110% of the travel
    v.rot = 0.9 + math.random() * 0.2    -- 90-110% of the rotation
    v.arc = 0.8 + math.random() * 0.4    -- how much the path bows forward
end

-- Realistic swing: a weighted wind-up, a strike that accelerates along a curved arc (not a
-- straight line), follow-through past the target, then a recovery that settles naturally.
local function GetCleave(p, pattern, hand)
    local t = 1 - p
    local w, st, o = Cleave.WINDUP[pattern] or Cleave.WINDUP[1], Cleave.STRIKE[pattern] or Cleave.STRIKE[1], State.cleaveOut
    local v = Swing.var[hand or "MH"] or Swing.var.MH

    -- follow-through pose: the strike carries on in the same direction it was travelling
    local function follow(i) return st[i] + (st[i] - w[i]) * Swing.FOLLOW end

    if t < 0.30 then
        -- wind-up: eases in and out, like shifting the weapon's weight back
        local k = t / 0.30
        k = k * k * (3 - 2 * k)
        for i = 1, Cleave.FIELDS do o[i] = w[i] * k end
    elseif t < 0.52 then
        -- strike: accelerates, peaks as it passes the target, carries on into the follow-through,
        -- travelling along a curve that bows forward (and stays high) through the middle of the cut
        local s = (t - 0.30) / 0.22
        local e = s * s * (3 - 2 * s)
        local a, b, c = (1 - e) * (1 - e), 2 * (1 - e) * e, e * e
        for i = 1, Cleave.FIELDS do
            local f = follow(i)
            local mid = (w[i] + f) * 0.5
            if i == 2 then mid = mid + 0.28 * v.arc end   -- bow forward
            if i == 3 then mid = mid + 0.10 * v.arc end   -- keep the blade up mid-arc
            o[i] = a * w[i] + b * mid + c * f
        end
    else
        -- recovery: drift back to rest, settling slightly past it before coming to a stop
        local r = (t - 0.52) / 0.48
        local k = Curve.InOut(r)
        local settle = math.sin(k * math.pi) * 0.06
        for i = 1, Cleave.FIELDS do
            local f = follow(i)
            o[i] = f * (1 - k) - f * settle
        end
    end

    for i = 1, 5 do o[i] = o[i] * Cleave.TRAVEL * v.amp end
    o[6] = o[6] * Cleave.TURN * Cleave.PITCH_DIR * v.rot
    o[7] = o[7] * Cleave.TURN * Cleave.ROLL_DIR * v.rot
    return o
end

-- All melee weapon types use the heavy (2H-style) swing.
Cleave.TYPES = { MELEE_1H = true, MELEE_1H_CASTER = true, MELEE_2H = true }

-- Shield bash
-- Brace back, drive the shield forward hard, hold on impact, jolt from the hit, then recover.

Bash.SPEED = 1.8        -- bash lasts ~0.55s; lower = slower
Bash.INTENSITY = 1.0    -- scales how far the shield travels
Bash.IMPACT_T = 0.38    -- point in the bash where the hit lands (used to time it to the swing)

--                  inward  fwd     up   facing  scale  pitch   roll   (inward = toward screen centre)
Bash.WINDUP = {
    [1] = { -0.10, -0.32, -0.05,  0.15, 0.00, -0.15,  0.10 },  -- brace: pull the shield in tight to the body
    [2] = { -0.35, -0.20,  0.00,  0.40, 0.00,  0.00,  0.30 },  -- cock it out wide to the side
}
Bash.STRIKE = {
    [1] = {  0.10,  0.80,  0.10, -0.10, 0.12,  0.20,  0.00 },  -- straight punch into the target
    [2] = {  0.55,  0.60,  0.05, -0.55, 0.10,  0.10, -0.35 },  -- sweeping bash across the body
}
State.shieldOut = { 0, 0, 0, 0, 0, 0, 0 }

local function GetShieldBash(p, pattern)
    local t = 1 - p
    -- Only two bashes (straight punch, sweep across); the third swing in the cycle repeats the punch
    local w, st, o = Bash.WINDUP[pattern] or Bash.WINDUP[1], Bash.STRIKE[pattern] or Bash.STRIKE[1], State.shieldOut

    if t < 0.25 then                                  -- brace
        local k = Curve.Out(t / 0.25)
        for i = 1, 7 do o[i] = w[i] * k end
    elseif t < Bash.IMPACT_T then                   -- drive forward, accelerating into the hit
        local k = Curve.In((t - 0.25) / (Bash.IMPACT_T - 0.25))
        for i = 1, 7 do o[i] = w[i] + (st[i] - w[i]) * k end
    elseif t < 0.50 then                              -- impact hold (hitstop)
        for i = 1, 7 do o[i] = st[i] end
    else                                              -- recover
        local k = Curve.InOut((t - 0.50) / 0.50)
        for i = 1, 7 do o[i] = st[i] * (1 - k) end
    end

    -- Impact jolt: the shield is knocked back toward you and shudders as it connects
    if t >= Bash.IMPACT_T and t < 0.85 then
        local d = t - Bash.IMPACT_T
        local env = math.exp(-d * 10)
        o[2] = o[2] - math.sin(d * 40) * env * 0.12   -- knock-back along the depth axis
        o[3] = o[3] + math.sin(d * 60) * env * 0.04
        o[1] = o[1] + math.sin(d * 52) * env * 0.03
        o[6] = o[6] + math.sin(d * 45) * env * 0.08
    end

    for i = 1, 5 do o[i] = o[i] * Bash.INTENSITY end
    return o
end

-- Staff / held item as a spell goes out (weapon-only mode; hand mode plays real animations):
-- pushed toward the target and lifted, on a slightly different line each combo step.
-- { forward, lift, inward, twist }
Scene.CAST_PUSH = {
    { 0.20, 0.06, 0.00, 0.10 },
    { 0.14, 0.14, 0.06, -0.15 },
    { 0.10, 0.04, 0.16, 0.25 },
}
function Scene.CastPush(p, step)
    local v = Scene.CAST_PUSH[step] or Scene.CAST_PUSH[1]
    local k = math.sin(p * math.pi * 0.5)   -- out quickly, then eases back to rest
    return v[1] * k, v[2] * k, v[3] * k, v[4] * k
end

-- Ranged kick per shot: { pull back, lift, tip tilt }. It eases out, so the kick is sharpest the
-- moment the shot fires and the weapon settles back smoothly instead of stopping dead.
Scene.RECOIL = { GUN = { 0.28, 0.11, 0.17 }, BOW = { 0.17, 0.02, 0.04 } }
function Scene.Recoil(ty, p)
    local r = Scene.RECOIL[ty]
    local k = p * p
    return r[1] * k, r[2] * k, r[3] * k
end

-- Old hand/arm renderer (a DressUpModel, only used when ModelScene isn't available): the model
-- re-frames its own camera every time it loads, which would move every saved position. So the
-- first settled camera is remembered per hand and put back whenever the poses are applied.
Scene.legacyCam = {}
function Scene.legacyCam.Saved()
    FPWeaponsDB.handCam = FPWeaponsDB.handCam or {}
    return FPWeaponsDB.handCam
end
function Scene.legacyCam.Remember(model, key)
    if not (model and model.GetCameraPosition and model.GetCameraTarget) then return end
    if model.MakeCurrentCameraCustom then pcall(model.MakeCurrentCameraCustom, model) end
    local v = {}
    for _, get in ipairs({ model.GetCameraPosition, model.GetCameraTarget }) do
        local r = { pcall(get, model) }
        if not r[1] then return end
        for i = 2, 4 do
            if type(r[i]) ~= "number" then return end
            v[#v + 1] = r[i]
        end
    end
    -- an all-zero camera means the model hasn't loaded yet: try again another time
    for _, n in ipairs(v) do
        if n ~= 0 then Scene.legacyCam.Saved()[key] = v; return end
    end
end
function Scene.legacyCam.Restore(model, key)
    local v = Scene.legacyCam.Saved()[key]
    if not (v and model and model.SetCameraPosition and model.SetCameraTarget) then return end
    local custom = model.HasCustomCamera and model:HasCustomCamera()
    if custom == false and model.MakeCurrentCameraCustom then pcall(model.MakeCurrentCameraCustom, model) end
    pcall(model.SetCameraPosition, model, v[1], v[2], v[3])
    pcall(model.SetCameraTarget, model, v[4], v[5], v[6])
end

local function ApplyPoses()
    FPWeaponsDB = FPWeaponsDB or NewSettings()
    
    local mhType = GetHandType("MH")
    local ohType = GetAnimType("OH")
    local rwType = GetHandType("RW")

    local mhT = GetPose("MH")
    local ohT = GetPose("OH")
    if Scene.AttackPose then  -- glide toward the attack pose while an attack animation plays
        mhT = Scene.AttackPose("MH", mhT)
        ohT = Scene.AttackPose("OH", ohT)
    end
    local rwT = GetPose("RW")

    -- working copies of each pose, which the motion below adds to
    local function lay(t) return t.scale, t.facing, t.posX, t.posY, t.posZ end
    local mhScale, mhFacing, mhX, mhY, mhZ = lay(mhT)
    local ohScale, ohFacing, ohX, ohY, ohZ = lay(ohT)
    local rwScale, rwFacing, rwX, rwY, rwZ = lay(rwT)
    local mhPitch, ohPitch, rwPitch = mhT.pitch or 0, ohT.pitch or 0, rwT.pitch or 0
    local mhRoll, ohRoll, rwRoll = mhT.roll or 0, ohT.roll or 0, rwT.roll or 0

    if FPWeaponsDB.enableBob then
        local intensity = FPWeaponsDB.bobIntensity or 0.5

        -- Stride: sway side to side once per two steps, dipping at each footfall (a "U" arc),
        -- tilting toward the stepping side and nodding down as each foot lands.
        local b = State.strideBlend * intensity * Bob.speedK
        local s = math.sin(Bob.phase)
        local footfall = math.abs(s)                 -- 1 at each footfall, 0 mid-stride
        local bobX = s * Bob.SWAY_X * b
        local bobZ = (0.5 - footfall) * 2 * Bob.DIP_Z * b
        local bobRoll = s * Bob.ROLL * b
        local bobPitch = (footfall - 0.5) * 2 * Bob.PITCH * b

        -- Idle breathing: fades out as the stride fades in
        local idle = (1 - State.strideBlend) * intensity
        local br = math.sin(Bob.breath * Bob.BREATH_RATE)
        bobZ = bobZ + br * Bob.BREATH_Z * idle
        bobPitch = bobPitch - br * Bob.BREATH_PITCH * idle

        -- Turn lag: the weapons trail behind when you turn, then catch up
        bobX = bobX + Bob.turn * Bob.TURN_X * intensity
        local bobFacing = Bob.turn * Bob.TURN_FACING * intensity

        -- In the air: a little float; landing: a dip that recovers
        local jumpZ = ((State.airBlend * Bob.AIR_LIFT) - (math.sin(State.landingDip * math.pi) * Bob.LANDING_DIP)) * intensity

        -- The whole view sways together, so every hand moves the same way
        mhX, mhZ = mhX + bobX, mhZ + bobZ + jumpZ
        ohX, ohZ = ohX + bobX, ohZ + bobZ + jumpZ
        rwX, rwZ = rwX + bobX, rwZ + bobZ + jumpZ
        mhFacing, ohFacing, rwFacing = mhFacing + bobFacing, ohFacing + bobFacing, rwFacing + bobFacing
        mhPitch, ohPitch, rwPitch = mhPitch + bobPitch, ohPitch + bobPitch, rwPitch + bobPitch
        mhRoll, ohRoll, rwRoll = mhRoll + bobRoll, ohRoll + bobRoll, rwRoll + bobRoll
    end

    -- MH Animations
    if State.mhMotion > 0 and mhType ~= "NONE" then
        local p = State.mhMotion
        if Cleave.TYPES[mhType] and not (Scene.MeleeAnimated and Scene.MeleeAnimated("MH")) then
            local o = GetCleave(p, State.comboStep, "MH")
            mhX = mhX + o[1]
            mhY = mhY + o[2]
            mhZ = mhZ + o[3]
            mhFacing = mhFacing + o[4]
            mhScale = mhScale * (1 + o[5])
            mhPitch = mhPitch + o[6]
            mhRoll = mhRoll + o[7]
        elseif mhType == "EMPTY" then
            -- Caster Hand (MH): no attack motion; only its hand/arm animation plays
        elseif mhType == "STAFF" then
            local fwd, lift, inward, twist = Scene.CastPush(p, State.comboStep)
            mhX, mhY, mhZ, mhFacing = mhX - inward, mhY + fwd, mhZ + lift, mhFacing + twist
        elseif mhType == "SHIELD" then
            local o = GetShieldBash(p, State.comboStep)
            mhX = mhX - o[1]           -- mirrored: inward is to the left for the right hand
            mhY = mhY + o[2]
            mhZ = mhZ + o[3]
            mhFacing = mhFacing + o[4]
            mhScale = mhScale * (1 + o[5])
            mhPitch = mhPitch + o[6]
            mhRoll = mhRoll + o[7]
        end
    end

    -- Offhand Animations
    if State.ohMotion > 0 and ohType ~= "NONE" then
        local p = State.ohMotion
        if ohType == "MELEE_1H_CASTER" then
            -- Caster Hand (OH): no attack motion; only its hand/arm animation plays
        elseif Cleave.TYPES[ohType] and not (Scene.MeleeAnimated and Scene.MeleeAnimated("OH")) then
            local o = GetCleave(p, State.comboStep, "OH")
            ohX = ohX - o[1]           -- mirrored for the left hand
            ohY = ohY + o[2]
            ohZ = ohZ + o[3]
            ohFacing = ohFacing - o[4]
            ohScale = ohScale * (1 + o[5])
            ohPitch = ohPitch + o[6]
            ohRoll = ohRoll - o[7]     -- roll mirrored for the left hand
        elseif ohType == "STAFF" or ohType == "OFFHAND" then
            -- (an off-hand item is pushed out the same way as a staff)
            local fwd, lift, inward, twist = Scene.CastPush(p, State.comboStep)
            ohX, ohY, ohZ, ohFacing = ohX + inward, ohY + fwd, ohZ + lift, ohFacing - twist
        elseif ohType == "SHIELD" and not (Scene.MeleeAnimated and Scene.MeleeAnimated("OH")) then
            local o = GetShieldBash(p, State.comboStep)
            ohX = ohX + o[1]           -- o[1] is "inward" (toward the centre of the screen)
            ohY = ohY + o[2]
            ohZ = ohZ + o[3]
            ohFacing = ohFacing - o[4]
            ohScale = ohScale * (1 + o[5])
            ohPitch = ohPitch + o[6]
            ohRoll = ohRoll - o[7]
        end
    end

    -- Ranged Animations (recoil / release; progress runs 1 -> 0 so the kick is sharpest at the start)
    if State.rwMotion > 0 and rwType ~= "NONE" then
        local p = State.rwMotion
        if Scene.RECOIL[rwType] then
            local back, up, tilt = Scene.Recoil(rwType, p)
            rwY, rwZ, rwPitch = rwY - back, rwZ + up, rwPitch - tilt
        elseif rwType == "WAND" then
            -- Quick jab toward the target with an upward flick of the tip as the bolt leaves,
            -- then a light kick back on release
            local jab = math.sin(p * math.pi)
            rwY = rwY + (jab * 0.22) - (p * p * 0.06)
            rwZ = rwZ + (jab * 0.06)
            rwPitch = rwPitch - (jab * 0.35)
            rwFacing = rwFacing + (jab * 0.1)
        else
            rwY = rwY + (math.sin(p * math.pi) * 0.2)
            rwZ = rwZ - (math.sin(p * math.pi) * 0.15)
        end
    end

    -- Sheathe / draw offsets: weapons drop away, pull back and tilt out toward their own side.
    -- (The ranged swap uses the same motion: the set being swapped off is sheathed, the other drawn.)
    local se = (State.sheathBlend > 0) and SheathEase() or 0
    local R = Scene.ranged
    local eM, eO, eR = math.max(se, R.Ease("MH")), math.max(se, R.Ease("OH")), math.max(se, R.Ease("RW"))
    if eM > 0 or eO > 0 or eR > 0 then
        local m = Sheath.HAND_MULT
        -- Caster Hands don't drop down: they pull back toward you (and push forward on draw),
        -- the same motion as their return after a spell release.
        local c = Scene.cast
        if mhType == "EMPTY" then
            mhY, mhZ = mhY - c.RETURN_BACK * eM, mhZ - c.RETURN_DROP * eM
        else
            mhX = mhX + Sheath.SIDE * eM * m
            mhY = mhY - Sheath.BACK * eM * m
            mhZ = mhZ - Sheath.DROP * eM * m
            mhPitch = mhPitch + Sheath.TILT * eM
            mhRoll = mhRoll + Sheath.ROLL * eM
        end
        if ohType == "MELEE_1H_CASTER" then
            ohY, ohZ = ohY - c.RETURN_BACK * eO, ohZ - c.RETURN_DROP * eO
        else
            ohX = ohX - Sheath.SIDE * eO * m
            ohY = ohY - Sheath.BACK * eO * m
            ohZ = ohZ - Sheath.DROP * eO * m
            ohPitch = ohPitch + Sheath.TILT * eO
            ohRoll = ohRoll - Sheath.ROLL * eO
        end
        -- ranged sits in the middle: drop straight down and back, no sideways swing
        rwY = rwY - Sheath.BACK * eR * m
        rwZ = rwZ - Sheath.DROP * eR * m
        rwPitch = rwPitch + Sheath.TILT * eR
    end

    -- Post-release return: hands push forward from behind into place
    local rb = Scene.cast.returnBlend
    if rb > 0 then
        local k = rb * rb * (3 - 2 * rb)  -- smoothstep
        local back, drop = Scene.cast.RETURN_BACK * k, Scene.cast.RETURN_DROP * k
        if Scene.Replaced("MH") then mhY, mhZ = mhY - back, mhZ - drop end  -- only the hands that were replaced
        if Scene.Replaced("OH") then ohY, ohZ = ohY - back, ohZ - drop end
    end

    local nudge = State.nudgeFlip and 0.0001 or 0

    if Scene.Active() then
        Scene.Apply("MH", mhT, mhScale, mhFacing, mhPitch, mhRoll, mhX, mhY, mhZ)
        Scene.Apply("OH", ohT, ohScale, ohFacing, ohPitch, ohRoll, ohX, ohY, ohZ)
        Scene.Apply("RW", rwT, rwScale, rwFacing, rwPitch, rwRoll, rwX, rwY, rwZ)
        if Scene.actors.CAST then
            local c = Scene.cast
            local releasing = c.state == "release" or (not c.state and c.editing == "release")
            local attacking = c.state == "attack" or (not c.state and c.editing == "attack")
            local ct = GetPose(releasing and "RELEASE" or attacking and "ATTACK" or "CAST")
            Scene.Apply("CAST", ct, ct.scale, ct.facing, ct.pitch or 0, ct.roll or 0, ct.posX, ct.posY, ct.posZ)
        end
        UpdateVisibility()
        return
    end

    -- old hand renderer (no ModelScene): keep each model's camera fixed (see Scene.legacyCam)
    for key, m in pairs({ mh = mhWeapon, oh = ohWeapon, rw = rwWeapon }) do
        if m.ZeroCachedCenterXY then m:ZeroCachedCenterXY() end
        Scene.legacyCam.Restore(m, key)
    end

    mhWeapon:SetModelScale(mhScale + nudge)
    mhWeapon:SetFacing(mhFacing)
    if mhWeapon.SetPitch then mhWeapon:SetPitch(mhPitch) end
    if mhWeapon.SetRoll then mhWeapon:SetRoll(mhRoll) end
    mhWeapon:SetPosition(mhY, mhX, mhZ)

    ohWeapon:SetModelScale(ohScale + nudge)
    ohWeapon:SetFacing(ohFacing)
    if ohWeapon.SetPitch then ohWeapon:SetPitch(ohPitch) end
    if ohWeapon.SetRoll then ohWeapon:SetRoll(ohRoll) end
    ohWeapon:SetPosition(ohY, ohX, ohZ)

    rwWeapon:SetModelScale(rwScale + nudge)
    rwWeapon:SetFacing(rwFacing)
    if rwWeapon.SetPitch then rwWeapon:SetPitch(rwPitch) end
    if rwWeapon.SetRoll then rwWeapon:SetRoll(rwRoll) end
    rwWeapon:SetPosition(rwY, rwX, rwZ)

    UpdateVisibility()
end

-- Old hand/arm mode: (re)start a model's idle animation for its weapon type. Loading a model
-- resets its animation, so this runs after every load.
local function PlayLegacyIdle(model)
    if not (model and model.SetAnimation) then return end
    local hand
    for h, m in pairs(MODELS) do if m == model then hand = h end end
    local ty = hand and GetAnimType(hand)
    local anim = ty and (Anim.BY_TYPE[hand .. "_" .. ty] or Anim.BY_TYPE[ty]) or Anim.ID
    local speed = ty and (Anim.SPEED_BY_TYPE[hand .. "_" .. ty] or Anim.SPEED_BY_TYPE[ty])
    -- speed needs the 3-argument form (animation, variation, speed); fall back to the plain one
    local played = speed and speed ~= 1 and pcall(model.SetAnimation, model, anim, 0, speed)
    if not played then pcall(model.SetAnimation, model, anim) end
    if model.ZeroCachedCenterXY then model:ZeroCachedCenterXY() end
end

-- ModelScene: place an actor. t is the saved (slider) transform; the other values are the final
-- ones including swing/bob/sheathe, whose offsets are scaled down for the close-up camera.
function Scene.Apply(hand, t, scale, facing, pitch, roll, x, y, z)
    local a = Scene.actors[hand]
    if not a then return end
    t = Scene.FixPose(t)
    x, y, z = x or t.posX, y or t.posY, z or t.posZ
    scale, facing, pitch, roll = scale or t.scale, facing or t.facing, pitch or t.pitch, roll or t.roll
    local mp, mr = Scene.MOTION_POS, Scene.MOTION_ROT
    x = t.posX + (x - t.posX) * mp
    y = t.posY + (y - t.posY) * mp
    z = t.posZ + (z - t.posZ) * mp
    facing = t.facing + (facing - t.facing) * mr
    pitch = (t.pitch or 0) + (pitch - (t.pitch or 0)) * mr
    roll = (t.roll or 0) + (roll - (t.roll or 0)) * mr
    scale = t.scale + (scale - t.scale) * mp
    pcall(a.SetScale, a, scale)
    pcall(a.SetYaw, a, facing + math.pi)   -- facing ~3.14 (away from camera) = yaw ~0 (camera's forward)
    pcall(a.SetPitch, a, pitch)
    pcall(a.SetRoll, a, roll)
    pcall(a.SetPosition, a, y, -x, z)      -- scene: +X forward, +Y left, +Z up
end

-- Item (ID or link) -> transmog appearance source ID, which is what actors' TryOn takes
function Scene.SourceFor(item)
    if not (item and C_TransmogCollection and C_TransmogCollection.GetItemInfo) then return nil end
    local ok, _, sourceID = pcall(C_TransmogCollection.GetItemInfo, item)
    if ok and type(sourceID) == "number" and sourceID > 0 then return sourceID end
    return nil
end

-- An item's own look; for a worn item, its exact version (item link) first, then the plain item
function Scene.WornSource(itemID, invSlot)
    local link = invSlot and Readable(GetInventoryItemLink("player", invSlot))
    return (link and Scene.SourceFor(link)) or Scene.SourceFor(itemID)
end

-- The appearance (and weapon illusion) transmogged onto an equipment slot, as transmog source IDs.
-- Each slot has a "transmog location"; the applied source is what other players see.
-- TRANSMOG: what each weapon slot looks like, read off the invisible copy of your character.
-- [slot] = { src = appearance source ID, ill = illusion source ID }
Scene.tmog = {}
Scene.lastProbe = -10
Scene.tmogBlank = {}   -- [slot] = the last read gave no answer
function Scene.ProbeRead()
    local a = Scene.probe
    if not (a and a.GetItemTransmogInfo) then return end
    local function num(v)
        if type(v) == "number" and not issecretvalue(v) and v > 0 then return v end
    end
    if a.IsLoaded and not a:IsLoaded() then return end   -- (still loading: try again at the next read)
    local changed = false
    for _, slot in ipairs(Scene.LOOK_SLOTS) do
        local ok, info = pcall(a.GetItemTransmogInfo, a, slot)
        local src = ok and type(info) == "table" and num(info.appearanceID) or nil
        local ill = ok and type(info) == "table" and num(info.illusionID) or nil
        -- No answer while a weapon is worn may mean "couldn't read it" rather than "no transmog":
        -- only believe it when two reads in a row say so (an answer that comes and goes would
        -- otherwise rebuild the hand every time)
        local blank = not src and GetInventoryItemID("player", slot)
        local sure = not blank or Scene.tmogBlank[slot]
        Scene.tmogBlank[slot] = blank or nil
        if sure then
            local old = Scene.tmog[slot]
            if (old and old.src) ~= src or (old and old.ill) ~= ill then changed = true end
            Scene.tmog[slot] = src and { src = src, ill = ill } or nil
        end
    end
    if changed and State.fpOn then
        Scene.probeRebuild = true   -- (this rebuild needn't read the copy again)
        RefreshWeaponModels(true, "transmog read from your character changed")
        Scene.probeRebuild = nil
    end
end
-- Rebuild the copy from your character, then read it once it has loaded
function Scene.Probe()
    local a = Scene.probe
    if not a then return end
    Scene.lastProbe = GetTime()
    pcall(a.SetModelByUnit, a, "player", false, true)
    for _, t in ipairs({ 0.3, 1.0, 2.5 }) do C_Timer.After(t, Scene.ProbeRead) end
end

-- The appearance (and weapon illusion) shown on an equipment slot, as transmog source IDs
-- The first of these names an enum table has (enum names differ between client builds)
function Scene.EnumValue(enum, ...)
    if type(enum) ~= "table" then return nil end
    for i = 1, select("#", ...) do
        local v = enum[select(i, ...)]
        if v ~= nil then return v end
    end
    return nil
end

-- Asks the game which transmog is applied to a slot. Since patch 12.0 the lookup returns one
-- table instead of separate values; both forms are handled.
function Scene.AppliedTransmog(slot, kind)
    if not (slot and kind) then return nil end
    local function num(v)
        if type(v) == "number" and not issecretvalue(v) and v > 0 then return v end
    end
    local mod = Scene.EnumValue(Enum and Enum.TransmogModification, "Main", "None") or 0
    local loc
    local TU = rawget(_G, "TransmogUtil")   -- (Blizzard interface helper; may not exist on every client)
    if TU and TU.GetTransmogLocation then
        local ok, l = pcall(TU.GetTransmogLocation, slot, kind, mod)
        if ok then loc = l end
    end
    loc = loc or { slotID = slot, type = kind, modification = mod }
    local src
    if C_Transmog and C_Transmog.GetSlotVisualInfo then
        local ok, a, _, c, _, _, _, _, hide = pcall(C_Transmog.GetSlotVisualInfo, loc)
        if ok and type(a) == "table" then
            if a.isHideVisual ~= true then src = num(a.appliedSourceID) end
        elseif ok and hide ~= true then
            src = num(c)
        end
    end
    if not src and TU and TU.GetInfoForEquippedSlot then
        local ok, a = pcall(TU.GetInfoForEquippedSlot, loc)
        if ok then src = num(type(a) == "table" and a.appliedSourceID or a) end
    end
    return src
end

-- The appearance (and weapon illusion) shown on an equipment slot, as transmog source IDs:
-- what the invisible copy of your character is actually wearing first, then the game's answer.
-- (Since Midnight's transmog outfits, a weapon slot keeps a separate look for each kind of
-- weapon - one-handed, two-handed, Titan's Grip... - and the game's answer can be the look
-- saved for a different kind than the one you're holding. The copy shows the real one.)
function Scene.Transmog(slot)
    if not slot then return nil, nil end
    local pt = Scene.tmog[slot]
    if pt and pt.src then return pt.src, pt.ill end
    local T = Enum and Enum.TransmogType
    local look = T and Scene.AppliedTransmog(slot, T.Appearance or 0)
    local illusion = T and Scene.AppliedTransmog(slot, T.Illusion or 1)
    return look or nil, illusion or nil
end

-- What's in the weapon slots and whether each has a temporary effect on it (not how long is left)
function Scene.WeaponSignature()
    local r = { pcall(GetWeaponEnchantInfo) }
    local sig = tostring(r[1] and Readable(r[2])) .. tostring(r[1] and Readable(r[5])) .. ":"
             .. tostring(r[1] and Readable(r[6])) .. tostring(r[1] and Readable(r[9]))
    for _, slot in ipairs({ 16, 17, 18 }) do sig = sig .. "|" .. tostring(Readable(GetInventoryItemLink("player", slot))) end
    return sig
end

function Scene.IllusionFor(enchantID)
    if not (enchantID and enchantID > 0 and C_TransmogCollection and C_TransmogCollection.GetIllusionInfo) then return nil end
    local ok, info = pcall(C_TransmogCollection.GetIllusionInfo, enchantID)
    if ok and type(info) == "table" and info.sourceID then return info.sourceID end
    return nil
end

-- Play this hand's animation at its configured speed
-- Play this hand's animation at its configured speed. Does nothing if that exact animation is
-- already playing: restarting it is what made the arm snap back to its first frame.
function Scene.PlayAnim(hand)
    local a = Scene.actors[hand]
    if not (a and Scene.Active()) then return end
    if Scene.attack.active[hand] then return end  -- an attack animation is playing; it resumes after
    local animID, speed
    if hand == "CAST" then
        local c = Scene.cast
        animID = c.anim
        speed = (c.animKind == "release") and c.RELEASE_SPEED or (c.animKind == "attack") and Scene.attack.SPEED or c.CAST_SPEED
    else
        local ty = GetAnimType(hand)
        animID = Anim.BY_TYPE[hand .. "_" .. ty] or Anim.BY_TYPE[ty] or Anim.ID
        speed = Anim.SPEED_BY_TYPE[hand .. "_" .. ty] or Anim.SPEED_BY_TYPE[ty] or Scene.IDLE_SPEED
    end
    local key = animID .. ":" .. speed
    -- Only trust "already playing" once the model is confirmed loaded: an animation set while it
    -- is still loading is thrown away when the load finishes (that's what broke the login load).
    if Scene.playing[hand] == key and Scene.IsLoaded(hand) then
        -- Double-check with the engine where it can tell us; otherwise trust what we last set
        local ok, cur = pcall(a.GetAnimation, a)
        if not (ok and type(cur) == "number" and cur ~= animID) then return end
    end
    if not pcall(a.SetAnimation, a, animID, 0, speed) then
        pcall(a.SetAnimation, a, animID)
    end
    Scene.playing[hand] = key
end

-- True once the game says this actor's model has loaded (via OnModelLoaded or IsLoaded)
function Scene.IsLoaded(hand)
    if Scene.loaded[hand] then return true end
    local a = Scene.actors[hand]
    local ok, res = pcall(a.IsLoaded, a)
    if ok and res == true then
        Scene.loaded[hand] = true
        return true
    end
    return false
end

-- Show a freshly loaded model once it has settled (dressed + animating), with a short fade-in
function Scene.MarkReady(hand)
    if Scene.pending[hand] then Scene.ready[hand] = true end
end

-- Advance fade-ins; returns true while any model is still fading
function Scene.StepFade(elapsed)
    local changed = false
    for hand in pairs(Scene.actors) do
        local f = Scene.fade[hand] or 1
        if Scene.ready[hand] and f < 1 then
            Scene.fade[hand] = math.min(1, f + elapsed / Scene.FADE_TIME)
            changed = true
        end
    end
    return changed
end

-- Strip the character down to bracers/gloves + this hand's weapon
-- Engine animation blending: when on, the game blends from one animation into the next (e.g.
-- attack -> idle) instead of jumping to the new animation's first frame. /fpw animblend on|off
function Scene.ApplyAnimBlend(a)
    if not (a and a.SetAnimationBlendOperation) then return false end
    local ops = Enum and Enum.ModelBlendOperation
    local op
    if FPWeaponsDB.animBlend ~= false then op = Scene.EnumValue(ops, "Anim", "Blend") or 1
    else op = Scene.EnumValue(ops, "None") or 0 end
    return pcall(a.SetAnimationBlendOperation, a, op)
end

function Scene.Dress(hand)
    local a, p = Scene.actors[hand], Scene.pending[hand]
    if not (a and p) then return end
    Scene.ApplyAnimBlend(a)
    pcall(a.SetUseCenterForOrigin, a, true, true, true)  -- the pivot can be reset by a model load
    pcall(a.Undress, a)
    for _, src in ipairs(p.arm) do pcall(a.TryOn, a, src) end
    if p.weapon then
        local ok = pcall(a.TryOn, a, p.weapon, HANDS[hand].tryOnSlot, p.illusion)
        if not ok then pcall(a.TryOn, a, p.weapon) end
    end
    for _, w in ipairs(p.extra or {}) do
        local ok = pcall(a.TryOn, a, w.src, w.slot, w.illusion)
        if not ok then pcall(a.TryOn, a, w.src) end
    end
    Scene.PlayAnim(hand)
end

-- weapons (action model only): list of { item = itemID, enchant = enchantID, slot = "MAINHANDSLOT" }
-- invSlot: the equipment slot the weapon is worn in (nil for a custom item ID), so its
-- transmogged appearance and illusion are shown instead of the item's own look
function Scene.Tmog(entry, invSlot)
    entry.invSlot = invSlot
    local look, illusion = Scene.Transmog(invSlot)
    if look then entry.src = look end
    if illusion and FPWeaponsDB.showEnchants ~= false then entry.illusion = illusion end
    return entry
end
function Scene.Render(hand, itemID, enchantID, weapons, invSlot)
    local a = Scene.actors[hand]
    if not a then return end
    local w0 = Scene.Tmog({ src = Scene.WornSource(itemID, invSlot), illusion = Scene.IllusionFor(enchantID) }, invSlot)
    local p = { arm = {}, weapon = w0.src, illusion = w0.illusion, invSlot = invSlot, extra = {} }
    local missing = (itemID and not p.weapon)
    for _, w in ipairs(weapons or {}) do
        -- (the transmogged look counts too: the item's own look isn't always reported)
        local e = Scene.Tmog({ src = Scene.WornSource(w.item, w.invSlot), slot = w.slot, illusion = Scene.IllusionFor(w.enchant) }, w.invSlot)
        if e.src then p.extra[#p.extra + 1] = e else missing = true end
    end
    for _, slot in ipairs(Scene.SLEEVE_SLOTS) do
        -- the transmogged look you're wearing, else the item's own look
        local link = GetInventoryItemLink("player", slot)
        local src = link and (Scene.Transmog(slot) or Scene.WornSource(GetInventoryItemID("player", slot), slot))
        if src then p.arm[#p.arm + 1] = src elseif link then missing = true end
    end
    Scene.pending[hand] = p
    Scene.attack.active[hand] = nil  -- a rebuild cancels any attack animation in progress
    -- Item data not loaded yet (common right after logging in): rebuild once it has had time
    -- (counted per hand: some items never report a look, and a hand that builds fine mustn't
    -- restart another hand's count, or the retries never stop)
    local tries = Scene.missingTries[hand] or 0
    if missing and tries < 4 then
        Scene.missingTries[hand] = tries + 1
        C_Timer.After(Scene.MISSING_REBUILD, function()
            if Scene.pending[hand] == p and Scene.Active() then RefreshWeaponModels(true, hand .. " item data wasn't loaded") end
        end)
    elseif not missing then
        Scene.missingTries[hand] = 0
    end
    -- Hide it while it loads and gets dressed, so the build steps aren't visible
    Scene.ready[hand], Scene.fade[hand], Scene.playing[hand], Scene.loaded[hand] = false, 0, nil, false
    UpdateVisibility()
    pcall(a.ClearModel, a)
    -- (unit, sheatheWeapons, autoDress, hideWeapons, usePlayerNativeForm, holdBowString)
    pcall(a.SetModelByUnit, a, "player", false, true, false, true, GetHandType(hand) == "BOW")
    pcall(a.SetUseCenterForOrigin, a, true, true, true)
    Scene.Dress(hand)  -- usually too early (still loading); the checks below / OnModelLoaded redo it

    -- Load checks. A slow load (e.g. right after logging in) throws away anything applied before
    -- it finishes, so keep checking: once the model is confirmed loaded, dress it and start its
    -- animation one final time and show it. If the game can't tell us it has loaded, keep
    -- re-applying through the whole window and show it after the last check.
    local last = Scene.RETRY_TIMES[#Scene.RETRY_TIMES]
    for _, t in ipairs(Scene.RETRY_TIMES) do
        C_Timer.After(t, function()
            if Scene.pending[hand] ~= p then return end  -- re-rendered since
            if Scene.IsLoaded(hand) then
                if not p.dressed then
                    p.dressed = true
                    Scene.playing[hand] = nil
                    Scene.Dress(hand)
                    ApplyPoses()
                    C_Timer.After(Scene.SETTLE_TIME, function()
                        if Scene.pending[hand] == p then Scene.MarkReady(hand) end
                    end)
                else
                    Scene.PlayAnim(hand)
                end
            else
                Scene.playing[hand] = nil
                Scene.Dress(hand)
                ApplyPoses()
                if t == last then Scene.MarkReady(hand) end
            end
        end)
    end
end

function Scene.Clear(hand)
    local a = Scene.actors[hand]
    Scene.pending[hand] = nil
    Scene.ready[hand], Scene.fade[hand], Scene.playing[hand], Scene.loaded[hand] = false, 1, nil, false
    if a then pcall(a.ClearModel, a) end
end

function Scene.PushLight(v)
    local s = Scene.LIGHT_SIGN
    for _, f in pairs(Scene.frames) do
        pcall(f.SetLightVisible, f, true)
        pcall(f.SetLightDirection, f, s * v[1], s * v[2], s * v[3])
        pcall(f.SetLightAmbientColor, f, v[5] * v[4], v[6] * v[4], v[7] * v[4])
        pcall(f.SetLightDiffuseColor, f, v[9] * v[8], v[10] * v[8], v[11] * v[8])
    end
end

-------------------------------------------------------------------------------
-- PER-RACE DEFAULTS (hand/arm mode)
-- (Defaults shipped with the addon live in FPWeapons_RaceDefaults.lua; see that file.)
-- Each race/sex has a different height and arm length, so hand/arm positions tuned on one
-- character don't fit another. "Save as Race Default" copies this character's hand/arm positions
-- (every weapon type it has positioned, plus the cast/release poses) into FPWeaponsRaceDB, which
-- is shared by the whole account (needs "## SavedVariables: FPWeaponsRaceDB" in the .toc).
-- Any other character of the same race and sex then starts from those positions wherever it
-- hasn't positioned something itself. Forms that change the model (Worgen human form, Dracthyr
-- visage) are kept separately.
-------------------------------------------------------------------------------
function Scene.RaceKey()
    local okR, raceName, raceFile = pcall(UnitRace, "player")
    if not okR or type(raceFile) ~= "string" or issecretvalue(raceFile) then return nil end
    local okS, sex = pcall(UnitSex, "player")
    local female = okS and sex == 3
    local alt = false
    if C_PlayerInfo and C_PlayerInfo.GetAlternateFormInfo then
        local ok, hasAlt, inAlt = pcall(C_PlayerInfo.GetAlternateFormInfo)
        alt = ok and hasAlt and inAlt and true or false
    end
    local key = raceFile .. (female and "_F" or "_M") .. (alt and "_alt" or "")
    local label = tostring(raceName or raceFile) .. (female and " Female" or " Male") .. (alt and " (other form)" or "")
    return key, label
end

local function CopyTransform(t)
    return { scale = t.scale, facing = t.facing, pitch = t.pitch or 0, roll = t.roll or 0, posX = t.posX, posY = t.posY, posZ = t.posZ }
end

-- The saved race default for a hand + weapon type, or for "CAST" / "RELEASE"; nil if none
-- Looks in the player's own saved race defaults (FPWeaponsRaceDB) first, then in the defaults
-- shipped with the addon (FPWeaponsBuiltinRaceDefaults, in FPWeapons_RaceDefaults.lua). Both use
-- the same layout, so a block copied from the SavedVariables file works as a shipped default.
function Scene.RaceDefault(hand, weaponType)
    local key = Scene.RaceKey()
    local function look(entry)
        if type(entry) ~= "table" then return nil end
        if hand == "CAST" or hand == "RELEASE" or hand == "ATTACK" then
            local setup = weaponType  -- (for poses the second argument is the caster setup)
            return entry[(setup and setup ~= "BOTH") and (hand .. "_" .. setup) or hand]
        end
        return type(entry[hand]) == "table" and entry[hand][weaponType] or nil
    end
    local function from(store) return key and type(store) == "table" and look(store[key]) or nil end
    -- player's own > shipped for this race > generic default for everyone
    return Scene.FixPose(from(FPWeaponsRaceDB) or from(FPWeaponsBuiltinRaceDefaults) or look(Scene.GENERIC_DEFAULTS))
end

-- Save this character's hand/arm positions as the default for its race. Returns count, label.
function Scene.SaveRaceDefaults()
    if type(FPWeaponsRaceDB) ~= "table" then return nil, "no-store" end
    local key, label = Scene.RaceKey()
    if not key then return nil, "no-race" end
    local entry, n = {}, 0
    for hand, h in pairs(HANDS) do
        entry[hand] = {}
        for k, t in pairs(FPWeaponsDB[h.prefix .. "_transforms"] or {}) do
            local ty = type(k) == "string" and k:match("^(.+)_SCENE$")
            if ty and type(t) == "table" then entry[hand][ty] = CopyTransform(t); n = n + 1 end
        end
    end
    for _, pr in ipairs(Scene.cast.PROFILES) do
        local setup = pr.key
        for _, kind in ipairs({ "CAST", "RELEASE", "ATTACK" }) do
            local t = FPWeaponsDB[Scene.PoseKey(kind, setup)]
            if t then entry[setup == "BOTH" and kind or (kind .. "_" .. setup)] = CopyTransform(t); n = n + 1 end
        end
    end
    FPWeaponsRaceDB[key] = entry
    return n, label
end

-- MELEE ATTACK ANIMATIONS (see Scene.attack)
-- True when this hand's weapon type attacks with animation IDs (hand/arm mode only)
function Scene.MeleeAnimated(hand)
    if not Scene.Active() then return false end
    return Scene.attack.ANIMS[hand .. "_" .. GetHandType(hand)] ~= nil
end

-- Length of an attack animation (seconds at speed 1): your /fpw attacklen value, else LENGTHS, else MAX
function Scene.AttackLength(id)
    local saved = FPWeaponsDB.attackLengths and FPWeaponsDB.attackLengths[id]
    return saved or Scene.attack.LENGTHS[id] or Scene.attack.MAX
end

-- How long an attack animation actually plays: its length minus CUT_SHORT (never under 0.1s)
-- Playback speed of this hand's attack animation (SPEEDS for its weapon type, else SPEED)
function Scene.AttackSpeed(hand)
    local A = Scene.attack
    return A.SPEEDS[hand .. "_" .. GetHandType(hand)] or A.SPEED
end

function Scene.AttackPlayTime(id)
    return math.max(0.1, Scene.AttackLength(id) - Scene.attack.CUT_SHORT)
end

function Scene.EndAttack(hand)
    Scene.attack.easing[hand] = nil
    Scene.attack.active[hand] = nil
    Scene.playing[hand] = nil
    Scene.PlayAnim(hand)  -- back to the idle hand animation
end

-- Play this hand's next attack animation. advance = seconds to skip (to land on your real swing).
function Scene.PlayAttack(hand, pattern, advance)
    if not Scene.MeleeAnimated(hand) then return end
    local A, a = Scene.attack, Scene.actors[hand]
    local list = A.ANIMS[hand .. "_" .. GetHandType(hand)]
    if not (a and list and #list > 0) then return end
    local id = list[((pattern or 1) - 1) % #list + 1]
    A.token[hand] = (A.token[hand] or 0) + 1
    local tok = A.token[hand]
    A.active[hand] = true
    Scene.playing[hand] = nil
    -- (animation, variation, speed, offset seconds); older clients may not take the offset
    local sp = Scene.AttackSpeed(hand)
    if not pcall(a.SetAnimation, a, id, 0, sp, advance or 0) then
        if not pcall(a.SetAnimation, a, id, 0, sp) then pcall(a.SetAnimation, a, id) end
    end
    A.easing[hand] = nil
    local length = math.max(0.1, Scene.AttackPlayTime(id) / sp - (advance or 0))  -- slower = longer
    C_Timer.After(math.max(0, length - A.BLEND_OUT), function()
        if A.token[hand] == tok and A.active[hand] and A.editing ~= hand then A.easing[hand] = true end
    end)
    C_Timer.After(length, function()
        if A.token[hand] == tok and A.active[hand] and A.editing ~= hand then Scene.EndAttack(hand) end
    end)
end

for _, hand in ipairs({ "MH", "OH" }) do
    local a = Scene.actors[hand]
    if a then
        -- when the attack animation finishes, go back to the idle hand animation
        -- (while editing the attack pose it just keeps looping)
        pcall(a.SetScript, a, "OnAnimFinished", function()
            if Scene.attack.editing == hand then
                Scene.PlayAttack(hand, 1)
            elseif Scene.attack.active[hand] then
                Scene.EndAttack(hand)
            end
        end)
    end
end

-- Normal pose t, blended toward this hand's attack pose by its blend amount
function Scene.AttackPose(hand, t)
    local b = Scene.attack.blend[hand] or 0
    if b <= 0 or not Scene.MeleeAnimated(hand) then return t end
    local at = GetPose("ATTACK_" .. hand)
    local k = b * b * (3 - 2 * b)
    local function mix(x, y) return (x or 0) + ((y or 0) - (x or 0)) * k end
    return {
        scale = mix(t.scale, at.scale), facing = mix(t.facing, at.facing), pitch = mix(t.pitch, at.pitch),
        roll = mix(t.roll, at.roll), posX = mix(t.posX, at.posX), posY = mix(t.posY, at.posY), posZ = mix(t.posZ, at.posZ),
    }
end

-- Glide each hand into/out of its attack pose; returns true while anything is moving
function Scene.StepAttackBlend(elapsed)
    local A, changed = Scene.attack, false
    for _, hand in ipairs({ "MH", "OH" }) do
        local target = ((A.active[hand] and not A.easing[hand]) or A.editing == hand) and 1 or 0
        local b = A.blend[hand] or 0
        if b ~= target then
            local step = elapsed / ((target > b) and A.BLEND_TIME or A.BLEND_OUT)
            b = (target > b) and math.min(target, b + step) or math.max(target, b - step)
            A.blend[hand] = b
            changed = true
        end
    end
    return changed
end

-- Turn "Edit Attack Pose" on for a hand (loops its first attack animation), or off (nil)
function Scene.SetAttackEdit(hand)
    local A = Scene.attack
    local prev = A.editing
    A.editing = hand
    if prev and prev ~= hand then
        A.token[prev] = (A.token[prev] or 0) + 1
        Scene.EndAttack(prev)
    end
    if hand then
        Scene.PlayAttack(hand, 1)
        A.token[hand] = (A.token[hand] or 0) + 1  -- cancel the auto-return timer: keep looping
    end
end

-- True for a hand currently set to Caster Hand (MH: Caster Hand (Spell Casts MH), OH: Caster Hand (Spell Casts OH))
function Scene.CasterHand(hand)
    if hand == "MH" then return GetHandType("MH") == "EMPTY" end
    if hand == "OH" then return GetHandType("OH") == "MELEE_1H_CASTER" end
    return false
end

-- Casting model is only used with Caster Hand on both hands, in hand/arm mode
-- Which caster setup is active: "BOTH", "MH" (Mainhand Caster Hand only), "OH" (Offhand only) or nil
-- The action profile for the current weapon combination (hand/arm mode), or nil.
-- Spells always see a switching main hand (see Scene.MainSwitches) as a Caster Weapon, even while
-- Auto Attack has it swinging as One-Handed, so casting keeps one setup and one pose; forAttack
-- asks for the profile melee attacks use instead.
function Scene.Profile(forAttack)
    if not (Scene.Active() and Scene.actors.CAST) then return nil end
    local mh, oh = GetHandType("MH"), GetHandType("OH")
    if not forAttack and Scene.MainSwitches() then mh = "STAFF" end
    for _, pr in ipairs(Scene.cast.PROFILES) do
        if (pr.mh == nil or pr.mh == mh) and (pr.oh == nil or pr.oh == oh) then return pr end
    end
    return nil
end

-- Key of the current profile ("BOTH", "STAFF", "DUAL", ...), used for its saved poses
function Scene.CastSetup()
    local pr = Scene.Profile()
    return pr and pr.key or nil
end

function Scene.CastEnabled()
    return Scene.Profile() ~= nil
end

-- True when the action model replaces this hand in the current profile
function Scene.Replaced(hand)
    local pr = Scene.Profile()
    return pr and pr.replace[hand] and true or false
end

-- Next animation ID of a kind ("cast"/"release"/"channel"/"attack") for the current profile;
-- lists with several IDs take turns
function Scene.NextAnim(kind, peek)
    local pr = Scene.Profile(kind == "attack")
    local list = pr and pr[kind]
    if not list or #list == 0 then return nil end
    local c = Scene.cast
    local i = c.idx[kind] or 1
    if i > #list then i = 1 end
    if not peek then c.idx[kind] = i + 1 end
    return list[i]
end

-- Saved-variable key for a setup's cast/release pose (the both-hands keys are the original ones)
function Scene.PoseKey(kind, setup)
    local base = (kind == "CAST") and "cast_transform" or (kind == "ATTACK") and "attack_transform" or "release_transform"
    if setup and setup ~= "BOTH" then return base .. "_" .. setup end
    return base
end

-- Short label for the current setup, for the settings panel
function Scene.SetupLabel()
    local pr = Scene.Profile()
    if not pr or pr.key == "BOTH" then return "" end
    return " (" .. pr.label .. ")"
end

-- Switch the casting state: nil (hands), "casting" (loop CAST_ANIM), "release" (RELEASE_ANIM once)
function Scene.SetCastState(state)
    local c = Scene.cast
    local prev = c.state
    c.waiting = nil   -- any cast waiting for the release to finish is superseded
    c.state = state
    if state == "release" then c.releaseAt = GetTime() end
    if (prev == "release" or prev == "attack") and state == nil and not c.editing and not c.returning then
        Scene.StartReturn()  -- release ended early (the game said it finished): come back now
    end
    if state ~= "release" and state ~= "attack" then c.returning = false end
    c.token = c.token + 1
    if state == "casting" then
        c.anim, c.animKind, c.showing = Scene.NextAnim("cast") or c.CAST_ANIM, "cast", true
        c.returnBlend = 0  -- a new cast hides the hands straight away
    elseif state == "stopping" then
        c.showing = true   -- (keeps the cast animation going for a moment)
    elseif state == "channeling" then
        c.anim, c.animKind, c.showing = Scene.NextAnim("channel") or c.CAST_ANIM, "channel", true
        c.returnBlend = 0
    elseif state == "attack" then
        c.animKind, c.showing = "attack", true  -- (c.anim set by Scene.ActionAttack)
        c.returnBlend = 0
        local tok = c.token
        local length = Scene.AttackPlayTime(c.anim) / Scene.attack.SPEED
        -- the hands crossfade back in over the end of the attack, like after a spell release
        C_Timer.After(math.max(0, length - c.RETURN_TIME), function()
            if c.token == tok and c.state == "attack" and not c.editing then Scene.StartReturn() end
        end)
        C_Timer.After(length, function()
            if c.token == tok and c.state == "attack" then Scene.SetCastState(nil) end
        end)
    elseif state == "release" then
        local rel = Scene.NextAnim("release")
        if not rel then  -- this profile has no release: hands come straight back
            return Scene.SetCastState(nil)
        end
        c.anim, c.animKind, c.showing = rel, "release", true
        local tok = c.token
        -- Start the hands' return so they arrive just as the release finishes (the release model
        -- fades out while they fade in), then end the release.
        local length = c.RELEASE_MAX / c.RELEASE_SPEED  -- slower playback = longer release
        C_Timer.After(math.max(0, length - c.RETURN_TIME), function()
            if c.token == tok and c.state == "release" and not c.editing then Scene.StartReturn() end
        end)
        C_Timer.After(length, function()
            if c.token == tok then Scene.SetCastState(nil) end
        end)
    else
        -- editing keeps that pose's animation on screen
        local kind = (c.editing == "release") and "release" or (c.editing == "attack") and "attack" or "cast"
        c.anim = Scene.NextAnim(kind, true) or c.CAST_ANIM
        c.animKind = kind
        c.showing = c.editing and true or false
    end
    if state ~= "stopping" and (c.showing or state == nil) then
        Scene.playing.CAST = nil  -- restart from the first frame
        Scene.PlayAnim("CAST")
    end
    ApplyPoses()  -- switch between the cast and release poses straight away
    UpdateVisibility()
end

-- Bring the hands back from behind to forward (instead of the rise-from-below draw) and keep
-- them drawn for a while. Used at the end of a spell release.
function Scene.StartReturn()
    local c = Scene.cast
    c.returnBlend = 1
    c.returning = true
    State.sheathBlend = 0
    State.drawTimer = math.max(State.drawTimer, Sheath.ABILITY_HOLD)
    UpdateVisibility()
end

-- Melee attack on the action model (profiles with an attack list, e.g. dual wield).
-- Returns true if it played (so the hands don't swing themselves).
function Scene.ActionAttack(advance)
    local c = Scene.cast
    local pr = Scene.Profile(true)
    if not (State.fpOn and pr and pr.attack) then return false end
    if c.state == "casting" or c.state == "channeling" or c.state == "stopping" then return true end
    local id = Scene.NextAnim("attack")
    if not id then return false end
    c.anim = id
    Scene.SetCastState("attack")
    Scene.playing.CAST = nil
    local a = Scene.actors.CAST
    if a and not pcall(a.SetAnimation, a, id, 0, Scene.attack.SPEED, advance or 0) then
        Scene.PlayAnim("CAST")
    end
    Scene.playing.CAST = id .. ":" .. Scene.attack.SPEED
    UpdateVisibility()
    return true
end

-- Which pose the orientation sliders are editing ("CAST" / "RELEASE"), or nil for the current tab
function Scene.EditTarget()
    if Scene.attack.editing then return "ATTACK_" .. Scene.attack.editing end
    local e = Scene.cast.editing
    if e == "cast" then return "CAST" elseif e == "release" then return "RELEASE" elseif e == "attack" then return "ATTACK" end
    return nil
end

if Scene.actors.CAST then
    -- When the release animation finishes, bring the hands back
    pcall(Scene.actors.CAST.SetScript, Scene.actors.CAST, "OnAnimFinished", function()
        if Scene.cast.state == "release" then Scene.SetCastState(nil) end
    end)
end

if Scene.probe then pcall(Scene.probe.SetScript, Scene.probe, "OnModelLoaded", function() Scene.ProbeRead() end) end

for hand, a in pairs(Scene.actors) do
    pcall(a.SetScript, a, "OnModelLoaded", function()
        Scene.loadEvents = Scene.loadEvents + 1
        Scene.loaded[hand] = true
        Scene.playing[hand] = nil  -- a (re)load resets the model's animation, so it must be replayed
        local p = Scene.pending[hand]
        if p and not p.dressed then
            p.dressed = true  -- once per render (dressing can re-fire the load)
            Scene.Dress(hand)
        else
            Scene.PlayAnim(hand)
        end
        ApplyPoses()
        -- Let any reload caused by dressing finish before it becomes visible
        C_Timer.After(Scene.SETTLE_TIME, function()
            if Scene.pending[hand] == p then Scene.MarkReady(hand) end
        end)
    end)
end

-- Model frames ignore poses set before they finish loading and can drop them when shown again,
-- so after those moments the poses are applied again a few times over the next seconds.
Scene.REASSERT_SHOWN = { 0, 0.1, 0.3, 0.6, 1.0, 1.5, 2.5 }
Scene.REASSERT_COMBAT = { 0.1, 0.5, 1.0 }
Scene.REASSERT_LOADING = { 0.05, 0.3, 0.8, 1.5, 2.5 }
Scene.REASSERT_TURNED_ON = { 0.05, 0.25, 0.6, 1.2, 2.5 }
function Scene.Reassert(times)
    ApplyPoses()
    for _, t in ipairs(times) do C_Timer.After(t, ApplyPoses) end
end
function Scene.ReassertShown() Scene.Reassert(Scene.REASSERT_SHOWN) end

mhWeapon:SetScript("OnModelLoaded", function(self) PlayLegacyIdle(self); ApplyPoses() end)
ohWeapon:SetScript("OnModelLoaded", function(self) PlayLegacyIdle(self); ApplyPoses() end)
rwWeapon:SetScript("OnModelLoaded", function(self) PlayLegacyIdle(self); ApplyPoses() end)
mhWeapon:SetScript("OnShow", Scene.ReassertShown)
ohWeapon:SetScript("OnShow", Scene.ReassertShown)
rwWeapon:SetScript("OnShow", Scene.ReassertShown)
overlayFrame:HookScript("OnShow", Scene.ReassertShown)

-- DYNAMIC LIGHTING
-- UI model frames render in their own scene and can't see the world's lighting, so this
-- approximates it with Model:SetLight, driven by in-game time of day (GetGameTime follows the
-- world's day/night cycle), indoors vs outdoors, stealth and low health. 

State.lightState = nil       -- eased current values (see LIGHT_KEYS)
State.lightApplied = false   -- true once we've overridden the default model light
State.lightAPIForm = nil     -- 1 = table form of SetLight, 2 = positional form (auto-detected)

--                      dirX  dirY  dirZ  ambI  ambR ambG ambB  difI  difR difG difB
Scene.light.NEUTRAL = {  0,  -0.5,  1.0,  0.75, 1,   1,   1,    1.0,  1,   1,   1   }
Scene.light.COUNT = 11

local function Lerp(a, b, k) return a + (b - a) * k end
local function Clamp01(v) return v < 0 and 0 or (v > 1 and 1 or v) end

local function ComputeLightTarget()
    local hour, minute = GetGameTime()
    local t = (hour or 12) + (minute or 0) / 60

    -- 0 at night, 1 at midday, with a quick ramp so mornings/evenings aren't mushy
    local day = 0
    if t >= 6 and t <= 18 then day = Clamp01(math.sin((t - 6) / 12 * math.pi) * 1.6) end
    -- warm sunrise/sunset glow within ~1.75h of 6:00 and 18:00
    local dusk = Clamp01(1 - math.min(math.abs(t - 6), math.abs(t - 18)) / 1.75)

    -- Light direction: the sun rises in the east, crosses the south and sets in the west; at night
    -- a moon high in the south. It's fixed to the world, so turning toward it lights your hands
    -- from the front and turning away backlights them. If the game won't say which way you're
    -- facing, it falls back to a direction fixed to the screen.
    local dx, dy, dz
    local okF, facing = pcall(GetPlayerFacing)
    local haveFacing = okF and type(facing) == "number" and not issecretvalue(facing)
    local isDay = t >= 6 and t <= 18
    local a = isDay and ((t - 6) / 12 * math.pi) or 0
    local an = isDay and 0 or ((((t - 18) % 24) / 12) * math.pi)  -- moon: 0 at 18:00, pi at 06:00
    local moonHigh = isDay and 0 or math.sin(an)                   -- 1 around midnight
    if haveFacing then
        local az, horiz, elev
        if isDay then
            az, horiz, elev = 1.5 * math.pi - a, 0.85, 0.25 + math.sin(a) * 0.75   -- east -> south -> west
        else
            az, horiz, elev = 1.5 * math.pi - an, 0.6, 0.3 + moonHigh * 0.6       -- moon: east -> south -> west
        end
        local rel = az - facing
        local f = Scene.light.SUN_FLIP
        dx, dy, dz = f * math.cos(rel) * horiz, f * math.sin(rel) * horiz, elev
    elseif isDay then
        dx, dy, dz = math.cos(a), -0.5, 0.25 + math.sin(a) * 0.75
    else
        dx, dy, dz = math.cos(an) * 0.8, -0.5, 0.35 + moonHigh * 0.65
    end

    -- Night: moonlight is a real directional light (silvery blue), with a soft cool ambient so the
    -- hands stay readable instead of going flat and murky; a little dimmer as the moon sets.
    local ai = Lerp(0.50, 0.75, day)
    local ar, ag, ab = Lerp(0.55, 1.00, day), Lerp(0.62, 1.00, day), Lerp(0.85, 1.00, day)
    local di = Lerp(0.45 * (0.75 + 0.25 * moonHigh), 1.00, day)
    local dr, dg, db = Lerp(0.70, 1.00, day), Lerp(0.80, 0.97, day), Lerp(1.00, 0.90, day)

    -- Sunrise / sunset 
    ar, ag, ab = Lerp(ar, 1.0, dusk * 0.5), Lerp(ag, 0.80, dusk * 0.5), Lerp(ab, 0.65, dusk * 0.5)
    dr, dg, db = Lerp(dr, 1.0, dusk * 0.8), Lerp(dg, 0.60, dusk * 0.8), Lerp(db, 0.35, dusk * 0.8)
    di = math.max(di, dusk * 0.7)

    -- Indoors. Inns and city buildings (where you're resting): warm torchlight from above.
    -- Dungeons, raids, scenarios and caves: dimmer and cooler.
    if IsIndoors and IsIndoors() then
        local inInstance, itype = false, nil
        if IsInInstance then inInstance, itype = IsInInstance() end
        local dungeon = (inInstance and itype ~= "none" and itype ~= "pvp" and itype ~= "arena")
            or not (IsResting and IsResting())
        dx, dy, dz = 0, -0.3, 1.0
        if dungeon then
            di = di * 0.35
            ai = ai * 0.75
            dr, dg, db = Lerp(dr, 0.80, 0.5), Lerp(dg, 0.85, 0.5), Lerp(db, 1.00, 0.5)
            ar, ag, ab = Lerp(ar, 0.70, 0.5), Lerp(ag, 0.78, 0.5), Lerp(ab, 0.95, 0.5)
        else
            local night = 1 - day  -- at night the torches and hearths carry the light: warmer, not as dim
            di = math.max(di * 0.45, 0.55 * night)
            ai = ai * 0.9
            local warm = 0.5 + 0.35 * night
            dr, dg, db = Lerp(dr, 1.0, warm), Lerp(dg, 0.80, warm), Lerp(db, 0.58, warm)
            ar, ag, ab = Lerp(ar, 1.0, 0.4 + 0.2 * night), Lerp(ag, 0.86, 0.4 + 0.2 * night), Lerp(ab, 0.72, 0.4 + 0.2 * night)
        end
    end

    -- Underwater: blue-green, dimmer, light filtering down from above. Swimming at the surface
    -- gets a lighter version.
    local under = (IsSubmerged and IsSubmerged()) and 1 or ((IsSwimming and IsSwimming()) and 0.35 or 0)
    if under > 0 then
        dx, dy, dz = Lerp(dx, 0, under), Lerp(dy, 0, under), Lerp(dz, 1.0, under)
        di = di * Lerp(1, 0.55, under)
        ai = ai * Lerp(1, 0.85, under)
        dr, dg, db = Lerp(dr, 0.50, under), Lerp(dg, 0.85, under), Lerp(db, 0.95, under)
        ar, ag, ab = Lerp(ar, 0.45, under), Lerp(ag, 0.75, under), Lerp(ab, 0.90, under)
    end

    -- Stealth: dimmer
    if IsStealthed and IsStealthed() then
        ar, ag, ab = ar * 0.8, ag * 0.85, ab * 1.0
        dr, dg, db = dr * 0.8, dg * 0.85, db * 1.0
        di = di * 0.8
    end

    -- Low health: red wash 
    local okH, hp = pcall(function()
        local cur, max = UnitHealth("player"), UnitHealthMax("player")
        return cur / max
    end)
    if okH and type(hp) == "number" and hp < 0.35 then
        local k = Clamp01((0.35 - hp) / 0.35) * 0.6
        ar, ag, ab = Lerp(ar, 1.0, k), Lerp(ag, 0.4, k), Lerp(ab, 0.4, k)
        dr, dg, db = Lerp(dr, 1.0, k), Lerp(dg, 0.4, k), Lerp(db, 0.4, k)
    end

    local raw = { dx, dy, dz, ai, ar, ag, ab, di, dr, dg, db }
    local strength = 1.0  -- dynamic lighting always at full strength (no setting any more)
    local out = {}
    for i = 1, Scene.light.COUNT do out[i] = Lerp(Scene.light.NEUTRAL[i], raw[i], strength) end
    return out
end

local function PushLight(model, v)
    if not (model and model.SetLight) then return end
    if State.lightAPIForm ~= 2 then
        local ok = pcall(model.SetLight, model, true, {
            omnidirectional = false,
            point = CreateVector3D(v[1], v[2], v[3]),
            ambientIntensity = v[4],
            ambientColor = CreateColor(v[5], v[6], v[7]),
            diffuseIntensity = v[8],
            diffuseColor = CreateColor(v[9], v[10], v[11]),
        })
        if ok then State.lightAPIForm = 1 return end
        State.lightAPIForm = 2  -- table form rejected: use the older positional form from now on
    end
    pcall(model.SetLight, model, true, false, v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], v[10], v[11])
end

local function UpdateLighting(dt)
    local enabled = true  -- dynamic lighting is always on (Lighting Strength 0 = plain neutral light)
    if not enabled then
        if State.lightApplied then  -- just switched off: restore the neutral light once
            State.lightState = nil
            State.lightApplied = false
            PushLight(mhWeapon, Scene.light.NEUTRAL)
            PushLight(ohWeapon, Scene.light.NEUTRAL)
            PushLight(rwWeapon, Scene.light.NEUTRAL)
            Scene.PushLight(Scene.light.NEUTRAL)
        end
        return
    end

    local L = Scene.light
    local target = ComputeLightTarget()
    if not State.lightState then
        State.lightState = target  -- first update: snap
    else
        dt = dt or L.UPDATE
        local kDir = 1 - math.exp(-dt / L.DIR_EASE)            -- direction follows turning quickly
        local kCol = 1 - math.exp(-dt * 3 / L.COLOR_EASE)      -- colours settle over COLOR_EASE seconds
        for i = 1, Scene.light.COUNT do State.lightState[i] = Lerp(State.lightState[i], target[i], i <= 3 and kDir or kCol) end
    end
    State.lightApplied = true

    -- Spell flash: a brief glow on top of the current light
    local out = State.lightState
    if L.flash > 0 then
        local fl, c = L.flash, L.flashColor or L.FLASH_COLOR
        out = {}
        for i = 1, Scene.light.COUNT do out[i] = State.lightState[i] end
        out[8] = out[8] + L.FLASH_BOOST * fl
        for i = 0, 2 do
            out[9 + i] = Lerp(out[9 + i], c[i + 1], fl * 0.6)
            out[5 + i] = Lerp(out[5 + i], c[i + 1], fl * 0.3)
        end
        L.flash = math.max(0, fl - (dt or L.UPDATE) / L.FLASH_TIME)
    end
    PushLight(mhWeapon, out)
    PushLight(ohWeapon, out)
    PushLight(rwWeapon, out)
    Scene.PushLight(out)
end

local TriggerSwing   -- (defined further down; the frame update needs to call it)

State.autoAttackWasOn = false

-- True while melee Auto Attack is toggled on, there is a target, and you're in combat.
-- Auto Attack stays "on" when you target an enemy from range before the fight starts, but no
-- swings land until combat begins, so the loop waits for combat too.
Scene.AUTO_ATTACK = 6603   -- the Auto Attack spell
local function IsAutoAttacking()
    if not (UnitAffectingCombat("player") and UnitExists("target")) then return false end
    local ok, on = pcall(C_Spell and C_Spell.IsCurrentSpell, Scene.AUTO_ATTACK)
    return (ok and on) and true or false
end

-- SWING TIMERS
-- With the combat log off-limits there is no swing signal detectable, so the swing is
-- predicted from your real weapon speeds and kept in step with the game:
--  * one timer per hand (main hand / off hand run on their own speeds when dual wielding)
--  * haste changes rescale the time remaining on the current swing immediately
--  * the animation is started EARLY by its own wind-up time, so the moment of impact lands on
--    the predicted swing instead of arriving after it
--  * timers wait while the target is out of melee range, and the first swing on reaching
--    range plays immediately (the way the game's first swing does)
--  * timers re-anchor when you engage or change weapons

local swing = {
    mh = { t = 0, speed = nil, fired = false },
    oh = { t = 0, speed = nil, fired = false },
}
State.swingPoll = 0
State.swingInRange = true
Swing.RANGE_ITEM = 37727  -- 5 yd range-check item; if the check isn't usable we assume in range

local function ReadWeaponSpeeds()
    local ok, mh, oh = pcall(UnitAttackSpeed, "player")
    if not ok or type(mh) ~= "number" or issecretvalue(mh) or mh <= 0 then return nil end
    if type(oh) ~= "number" or issecretvalue(oh) or oh <= 0 then oh = nil end
    return mh, oh
end

-- Is the target within melee range? Asks the game about Auto Attack's own range first: that's
-- the check that decides whether you actually swing, and it keeps working in combat (it's what
-- turns action buttons red). The range-check item is only a fallback, because the game blocks
-- item range checks against enemies in combat, which made swings play while out of range.
local function CheckMeleeRange()
    if not UnitExists("target") then return false end
    local function answer(ok, res)
        if ok and type(res) == "boolean" and not issecretvalue(res) then return res end
        if ok and (res == 1 or res == 0) then return res == 1 end  -- older API: 1 / 0
        return nil
    end
    local r = answer(pcall(C_Spell and C_Spell.IsSpellInRange, 6603, "target"))   -- Auto Attack
    if r == nil then r = answer(pcall(C_Item and C_Item.IsItemInRange, Swing.RANGE_ITEM, "target")) end
    if r == nil then return true end  -- the game won't say either way: don't block swings
    return r
end

-- Seconds between starting the animation and its moment of impact, per weapon type
local function SwingLead(hand)
    if Scene.MeleeAnimated and Scene.MeleeAnimated(hand == "OH" and "OH" or "MH") then
        return Scene.attack.IMPACT / Scene.AttackSpeed(hand == "OH" and "OH" or "MH")  -- animation-ID attacks: when the hit lands
    end
    local ty
    if hand == "OH" then ty = GetAnimType("OH") else ty = GetAnimType("MH") end
    if ty == "NONE" or ty == nil then ty = (hand == "OH") and GetAnimType("MH") or GetAnimType("OH") end
    if Cleave.TYPES[ty] then return Swing.IMPACT_T / (Swing.SPEEDS[ty] or Cleave.SPEED)  -- when the blade passes the target
    elseif ty == "SHIELD" then return Bash.IMPACT_T / Bash.SPEED
    elseif ty == "GUN" or ty == "BOW" then return 0
    end
    return 0.1
end

local function RescaleHand(h, newSpeed)
    if h.speed and h.speed > 0 and math.abs(h.speed - newSpeed) > 0.001 then
        h.t = h.t * newSpeed / h.speed   -- haste change: keep the same fraction of the swing left
    end
    h.speed = newSpeed
end

local function RefreshSwingSpeeds()
    local mh, oh = ReadWeaponSpeeds()
    if mh then
        RescaleHand(swing.mh, mh)
        if oh then RescaleHand(swing.oh, oh) else swing.oh.speed = nil end
    elseif not swing.mh.speed then
        swing.mh.speed = 2.0
    end
end

-- Call when the swing timer restarts (weapon change)
local function ResetSwingTimers()
    RefreshSwingSpeeds()
    swing.mh.t = swing.mh.speed or 2.0
    swing.mh.fired = false
    swing.oh.t = swing.oh.speed and (swing.oh.speed * 0.5 + 0.2) or 0
    swing.oh.fired = false
end

local function StepSwingHand(h, hand, dt)
    if not h.speed then return end
    h.t = h.t - dt
    if not State.swingInRange then
        if h.t < 0 then h.t = 0 end  -- swing is ready; waiting to reach melee range
        return
    end
    local lead = SwingLead(hand or "MH")
    if not h.fired and h.t <= lead then
        h.fired = true
        -- If we're already inside the wind-up window, skip into it rather than starting late
        local advance = math.min(math.max(0, lead - h.t), lead * 0.6)
        TriggerSwing(hand, advance)
    end
    if h.t <= 0 then
        h.t = h.t + h.speed
        if h.t < 0 then h.t = h.speed end  -- long hitch: don't try to catch up
        h.fired = false
    end
end

local function UpdateSwingTimers(dt, justEngaged)
    State.swingPoll = State.swingPoll + dt
    if State.swingPoll >= 0.1 or justEngaged then
        State.swingPoll = 0
        RefreshSwingSpeeds()
        State.swingInRange = CheckMeleeRange()
    end
    if justEngaged then
        swing.mh.t = 0
        swing.mh.fired = false
        swing.oh.t = swing.oh.speed and (swing.mh.speed or 2.0) * 0.5 or 0
        swing.oh.fired = false
    end
    local dual = swing.oh.speed ~= nil
    StepSwingHand(swing.mh, dual and "MH" or nil, dt)
    if dual then StepSwingHand(swing.oh, "OH", dt) end
end

overlayFrame:SetScript("OnUpdate", function(self, elapsed)
    if not State.fpOn then return end  -- frame stays shown (alpha 0) while FPS mode is off
    if Scene.StepFade(elapsed) then UpdateVisibility() end
    local swapping = Scene.ranged.Step(elapsed)
    if swapping then UpdateVisibility() end
    local attackMoving = Scene.StepAttackBlend(elapsed)
    local updated = attackMoving or swapping  -- (gliding into/out of an attack pose needs redrawing)
    local airborne = IsFalling() and true or false
    local inCombat = UnitAffectingCombat("player") and true or false
    if State.wasAirborne and not airborne then State.landingDip = 1 end   -- just touched down
    State.wasAirborne = airborne

    -- Stride sway runs while moving on the ground out of combat. State.strideBlend fades it in and out,
    -- and its phase only moves while striding, so after a jump it carries on mid-step.
    -- The stride rhythm and size follow your actual speed (walking is slower and smaller).
    local wantBob = FPWeaponsDB.enableBob and not airborne and not inCombat and IsMoving()
    if wantBob then
        local spd = Bob.GetSpeed() or Bob.RUN_SPEED
        local rel = spd / Bob.RUN_SPEED
        Bob.phase = Bob.phase + elapsed * Bob.STRIDE_RATE * math.max(0.45, math.min(1.4, rel))
        Bob.speedK = Bob.speedK + (math.max(0.5, math.min(1.2, rel)) - Bob.speedK) * math.min(1, elapsed * 4)
        State.strideBlend = math.min(1, State.strideBlend + elapsed * 6)
        updated = true
    elseif State.strideBlend > 0 then
        State.strideBlend = math.max(0, State.strideBlend - elapsed * 4)
        updated = true
    end
    if FPWeaponsDB.enableBob then
        Bob.breath = Bob.breath + elapsed
        Bob.UpdateTurn(elapsed)
        updated = true  -- breathing / turn lag animate continuously
    end

    -- In the air the weapons float up a little; landing gives them a dip that fades out
    local airTarget = airborne and 1 or 0
    if State.airBlend ~= airTarget then
        local step = elapsed * 8
        State.airBlend = (airTarget > State.airBlend) and math.min(airTarget, State.airBlend + step) or math.max(airTarget, State.airBlend - step)
        updated = true
    end

    if State.landingDip > 0 then
        State.landingDip = math.max(0, State.landingDip - elapsed * 3.5)
        updated = true
    end

    -- Every quarter second the poses are sent again (with a tiny alternating nudge so the engine
    -- can't skip them as unchanged): a model the engine reset on its own snaps straight back.
    State.reassertTimer = State.reassertTimer + elapsed
    if State.reassertTimer >= 0.25 then
        State.reassertTimer = 0
        State.nudgeFlip = not State.nudgeFlip
        updated = true
    end
    Scene.light.timer = Scene.light.timer + elapsed
    if Scene.light.timer >= Scene.light.UPDATE then
        UpdateLighting(Scene.light.timer)
        Scene.light.timer = 0
    end

    -- Post-release return motion (see Scene.cast.RETURN_*)
    if Scene.cast.returnBlend > 0 then
        Scene.cast.returnBlend = math.max(0, Scene.cast.returnBlend - elapsed / Scene.cast.RETURN_TIME)
        updated = true
    end

    -- Sheathe / draw: stay drawn in combat or while State.drawTimer runs; otherwise lower out of view.
    local autoSheath = FPWeaponsDB.autoSheath ~= false
    if inCombat then
        State.drawTimer = math.max(State.drawTimer, Sheath.DELAY)  -- so the delay starts counting once combat ends
    elseif State.drawTimer > 0 then
        State.drawTimer = math.max(0, State.drawTimer - elapsed)
    end
    local wantSheathed = autoSheath and not inCombat and State.drawTimer <= 0
    if wantSheathed and State.sheathBlend < 1 then
        State.sheathBlend = math.min(1, State.sheathBlend + elapsed * Sheath.SPEED)
        updated = true
    elseif not wantSheathed and State.sheathBlend > 0 then
        State.sheathBlend = math.max(0, State.sheathBlend - elapsed * Sheath.DRAW_SPEED)
        updated = true
    end

    -- Auto Attack swings come with no cast event, so they're timed from your weapon speed
    -- (see the swing timers above) while Auto Attack is on.
    local autoAttacking = IsAutoAttacking()
    if autoAttacking ~= Scene.autoAttackOn then
        Scene.autoAttackOn = autoAttacking
        if Scene.MainSwitches() then
            -- main hand: Caster Weapon <-> One-Handed (new idle animation and pose, same model);
            -- the casting model is rebuilt only if the weapon combination's profile changed
            Scene.PlayAnim("MH")
            RefreshWeaponModels()
            if Scene.PanelShown and Scene.PanelShown() then Scene.RefreshPanel() end
            updated = true
        end
    end
    if autoAttacking then
        UpdateSwingTimers(elapsed, not State.autoAttackWasOn)
    end
    State.autoAttackWasOn = autoAttacking

    if State.mhMotion > 0 then
        State.mhMotion = math.max(0, State.mhMotion - (elapsed * State.mhMotionRate))
        updated = true
    end

    if State.ohMotion > 0 then
        State.ohMotion = math.max(0, State.ohMotion - (elapsed * State.ohMotionRate))
        updated = true
    end

    if State.rwMotion > 0 then
        State.rwMotion = math.max(0, State.rwMotion - (elapsed * State.rwMotionRate))
        updated = true
    end

    -- Once a second: has a weapon's effect or transmog look changed? (No dependable event says so.)
    State.lookPollTimer = State.lookPollTimer + elapsed
    if State.lookPollTimer >= 1.0 then
        State.lookPollTimer = 0
        -- Enchants and transmog looks: there's no reliable event for either changing (a transmog
        -- can also show up a moment after login / after it's applied), so check every second and
        -- rebuild any hand whose look changed
        local ek = tostring(SlotEffect(16)) .. ":" .. tostring(SlotEffect(17)) .. ":" .. tostring(SlotEffect(18))
        local T, gameKey = Enum and Enum.TransmogType, ""
        for _, slot in ipairs(Scene.LOOK_SLOTS) do
            local look, ill = Scene.Transmog(slot)
            ek = ek .. "|" .. tostring(look) .. "/" .. tostring(ill)
            if T then gameKey = gameKey .. "|" .. tostring(Scene.AppliedTransmog(slot, T.Appearance or 0)) end
        end
        -- the game's own answer changed (an outfit swap, say): read your character again
        if gameKey ~= State.lastGameLookKey then
            if State.lastGameLookKey and GetTime() - Scene.lastProbe > 2 then Scene.Probe() end
            State.lastGameLookKey = gameKey
        end
        if ek ~= State.lastLookKey then
            State.lastLookKey = ek
            RefreshWeaponModels()  -- (only rebuilds a hand whose look actually changed)
        end
    end

    if updated then
        ApplyPoses()
    end
end)

State.lastTriggerTime = 0

-- Raise the weapons (cancels any pending sheathe). holdSeconds keeps them out for that long
-- after combat ends / when used out of combat.
local function DrawWeapons(holdSeconds)
    State.drawTimer = math.max(State.drawTimer, holdSeconds or Sheath.ABILITY_HOLD)
end

-- hand: optional "MH" / "OH" to force which hand swings (used when the real swing tells us);
-- otherwise hands alternate when dual wielding.
TriggerSwing = function(hand, advance)
    local mhType = GetHandType("MH")
    local ohType = GetAnimType("OH")

    local rwType = GetHandType("RW")

    local shieldOH = GetHandType("OH") == "SHIELD"
    if hand == "SHIELD" then
        -- block or shield ability: the shield bashes (nothing else moves)
        if not shieldOH or State.rwMotion > 0 then return end  -- (never during a ranged animation)
        State.lastTriggerTime = GetTime()
        DrawWeapons()
        State.ohMotionRate = Bash.SPEED
        State.ohMotion = 1.0
        State.comboStep = (State.comboStep >= 3) and 1 or State.comboStep + 1  -- three swings, then repeat
        ApplyPoses()
        return
    end

    local mhCanSwing = (mhType ~= "NONE")
    local ohCanSwing = (ohType ~= "NONE") and not shieldOH  -- shields only bash on blocks / shield abilities
    local rwCanShoot = (rwType ~= "NONE") and rwWeapon.fpHasModel == true
    State.lastTriggerTime = GetTime()
    DrawWeapons()

    -- Ranged weapon: only for a ranged attack (Auto Shot, Shoot...), or when it's the only weapon
    -- being shown. It's brought out for the shot, and the main / off hand are put away meanwhile.
    if rwCanShoot and hand ~= "MH" and hand ~= "OH" then
        if hand == "RW" or (not mhCanSwing and not ohCanSwing) then
            Scene.ranged.Out()
            -- Never overlap melee and ranged: a shot cancels any mainhand/offhand animation in progress
            State.mhMotion, State.ohMotion = 0, 0
            if Scene.Active() then
                for _, h in ipairs({ "MH", "OH" }) do
                    if Scene.attack.active[h] then
                        Scene.attack.token[h] = (Scene.attack.token[h] or 0) + 1
                        Scene.EndAttack(h)
                    end
                end
                if Scene.cast.state == "attack" then Scene.SetCastState(nil) end
            end
            if rwType == "BOW" then State.rwMotionRate = 2.5
            elseif rwType == "WAND" then State.rwMotionRate = 3.5
            else State.rwMotionRate = 3.0 end
            State.rwMotion = math.max(0.05, 1.0 - (advance or 0) * State.rwMotionRate)
            ApplyPoses()
            return
        end
    end
    if hand == "RW" then hand = nil end
    if State.rwMotion > 0 then return end  -- never overlap: no melee while a ranged animation is playing
    -- a melee attack puts the ranged weapon away again straight away
    Scene.ranged.untilT = 0

    -- Dual wield (or any profile with attack animations): the action model, holding both weapons,
    -- replaces both hands and plays the combo attack
    if Scene.ActionAttack and Scene.ActionAttack(advance) then
        ApplyPoses()
        return
    end

    -- advance: seconds of the animation to skip (start part-way through the wind-up)
    local swung
    local function swingMH()
        swung = "MH"
        State.mhMotionRate = Cleave.TYPES[mhType] and (Swing.SPEEDS[mhType] or Cleave.SPEED) or (mhType == "SHIELD" and Bash.SPEED) or 3.5
        if Cleave.TYPES[mhType] then Swing.New("MH") end
        State.mhMotion = math.max(0.05, 1.0 - (advance or 0) * State.mhMotionRate)
    end
    local function swingOH()
        swung = "OH"
        State.ohMotionRate = Cleave.TYPES[ohType] and (Swing.SPEEDS[ohType] or Cleave.SPEED) or (ohType == "SHIELD" and Bash.SPEED) or 3.5
        if Cleave.TYPES[ohType] then Swing.New("OH") end
        State.ohMotion = math.max(0.05, 1.0 - (advance or 0) * State.ohMotionRate)
    end

    if mhCanSwing and ohCanSwing then
        local useMH
        if hand == "MH" then useMH = true
        elseif hand == "OH" then useMH = false
        else useMH = State.mainHandNext end
        if useMH then swingMH() else swingOH() end
        State.mainHandNext = not useMH   -- next unforced swing uses the other hand
    elseif mhCanSwing then
        swingMH()
    elseif ohCanSwing then
        swingOH()
    end

    State.comboStep = (State.comboStep >= 3) and 1 or State.comboStep + 1  -- three swings, then repeat
    if swung then Scene.PlayAttack(swung, State.comboStep, advance) end
    ApplyPoses()
end

--==[ Choosing what each hand shows ]===========================================
-- A Custom Item ID typed in the panel: a number (an item ID, or a model file ID when it's larger
-- than any item ID), or an item link / name. Returns "item" or "model" and the ID, or nil.
Scene.MODEL_FILE_ABOVE = 500000
function Scene.ParseCustomID(text)
    if type(text) ~= "string" or text == "" then return nil end
    local n = tonumber(text)
    if n then return (n > Scene.MODEL_FILE_ABOVE) and "model" or "item", n end
    local item = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(text)
    if item then return "item", item end
    return nil
end

-- The item an equipment slot shows: its transmog appearance's item if it has one, else the item
-- itself. (Callers decide whether the hand shows anything at all.)
local function SlotLookItem(slotID)
    local look = Scene.Transmog(slotID)
    if look and C_TransmogCollection and C_TransmogCollection.GetSourceInfo then
        local okS, info = pcall(C_TransmogCollection.GetSourceInfo, look)
        if okS and type(info) == "table" and info.itemID then return info.itemID end
    end

    local okI, invID = pcall(GetInventoryItemID, "player", slotID)
    return okI and invID or nil
end


-- What a hand should show: "item" + item ID, "model" + model file ID, "empty" (a bare hand) or nil
local function WhatHandShows(slotID)
    local hand = SLOT_TO_HAND[slotID] or "MH"
    local overridesKey = HANDS[hand].prefix .. "_overrides"

    local currentType = GetHandType(hand)
    if currentType == "NONE" then return nil end
    if currentType == "EMPTY" then return "empty", 0 end  -- just the hand, no weapon
    if hand == "OH" and currentType == "MELEE_1H_CASTER" then return "empty", 0 end  -- Caster Hand (OH): no weapon either

    local customKind, customID = Scene.ParseCustomID((FPWeaponsDB[overridesKey] or {})[currentType])
    if customKind then return customKind, customID end

    local srcSlot = slotID
    if hand == "RW" and FPWeaponsDB.rw_type == "AUTO" then
        srcSlot = select(4, Scene.auto.Detect()) or slotID
    end
    local itemID = SlotLookItem(srcSlot)
    if itemID then return "item", itemID, srcSlot end
    return nil
end

-- Old hand/arm mode: your character stripped down to its sleeve (shirt, chest, bracers, gloves)
-- holding the weapon
function Scene.LegacyHand(frame, hand, kind, itemID, enchantID)
    frame:SetUnit("player")
    frame:Undress()
    for _, slot in ipairs(Scene.SLEEVE_SLOTS) do
        local id = GetInventoryItemID("player", slot)
        if id then pcall(frame.TryOn, frame, "item:" .. id) end
    end
    if kind == "item" then
        local link = "item:" .. itemID
        if not pcall(frame.TryOn, frame, link, HANDS[hand].tryOnSlot, enchantID) then pcall(frame.TryOn, frame, link) end
    end
    -- (gear finishing loading restarts the animation, so start it again a few times)
    PlayLegacyIdle(frame)
    for _, t in ipairs({ 0.2, 0.6, 1.2 }) do C_Timer.After(t, function() PlayLegacyIdle(frame) end) end
    -- once it's settled, remember this hand's camera if none is remembered yet (Scene.legacyCam)
    local camKey = HANDS[hand].prefix
    C_Timer.After(2.5, function()
        if not Scene.legacyCam.Saved()[camKey] then
            Scene.legacyCam.Remember(frame, camKey)
            ApplyPoses()
        end
    end)
end

-- Build what one hand shows. Rebuilding wipes a model frame's scale and position, so a hand is
-- only rebuilt when something it shows has changed (or when forced). Returns true if rebuilt.
local function BuildHand(modelFrame, slotID, force)
    local hand = SLOT_TO_HAND[slotID] or "MH"
    local kind, value, invSlot = WhatHandShows(slotID)
    modelFrame.fpHasModel = (kind ~= nil)
    modelFrame.fpVisible = (kind ~= nil)   -- something actually on screen
    local useHand = (kind == "item" or kind == "empty")   -- (a custom model file is shown on its own)

    local enchantID = (kind == "item") and SlotEffect(slotID) or nil

    -- everything that decides what the hand looks like
    local look, illusion = Scene.Transmog(invSlot)
    local builtAs = (hand == "MH" and Scene.MainSwitches()) and "CASTER_SWITCH" or tostring(GetHandType(hand))
    local parts = { tostring(kind), tostring(value), "fx" .. tostring(enchantID or 0), builtAs,
                    "look" .. tostring(look) .. "/" .. tostring(illusion) }
    if useHand then
        parts[#parts + 1] = "arm"
        for _, slot in ipairs(Scene.SLEEVE_SLOTS) do
            parts[#parts + 1] = tostring(GetInventoryItemID("player", slot) or 0) .. "/" .. tostring((Scene.Transmog(slot)))
        end
    end
    local key = table.concat(parts, ":")

    if not force and modelFrame.fpKey == key then return false end
    if Swing.debugRebuild then
        DEFAULT_CHAT_FRAME:AddMessage(("|cff00ff00[FPWeapons rebuild]|r %s (%s)\n  was: %s\n  now: %s"):format(
            hand, tostring(Scene.rebuildWhy), tostring(modelFrame.fpKey), key))
    end
    modelFrame.fpKey = key

    modelFrame:ClearModel()
    if not (useHand and Scene.ok) then Scene.Clear(hand) end
    if not kind then return true end

    if kind == "model" then
        modelFrame:SetModel(value)
    elseif Scene.ok then
        Scene.Render(hand, (kind == "item") and value or nil, enchantID, nil, invSlot)
    else
        Scene.LegacyHand(modelFrame, hand, kind, value, enchantID)
    end
    return true
end

RefreshWeaponModels = function(force, why)
    if not State.fpOn then return end
    Scene.rebuildWhy = force and (why or "forced") or "look changed"
    if force and not Scene.probeRebuild and GetTime() - Scene.lastProbe > 2 then Scene.Probe() end
    local changedMH = BuildHand(mhWeapon, 16, force)
    local changedOH = BuildHand(ohWeapon, 17, force)
    local changedRW = BuildHand(rwWeapon, 18, force)
    -- Casting model: build it ahead of time so it can appear instantly when a cast starts
    if Scene.actors.CAST then
        local pr = Scene.Profile()
        -- while Auto Attack is on, a setup with melee attacks on this model (dual wield) gets it
        local attackPr = (Scene.autoAttackOn or Scene.cast.editing == "attack") and Scene.Profile(true)
        if attackPr and attackPr.attack then pr = attackPr end
        if pr then
            -- it holds the weapons of the hands it replaces (Caster Hands are empty hands)
            local weapons, key = {}, pr.key
            for _, h in ipairs({ "MH", "OH" }) do
                local ty = GetHandType(h)
                if pr.replace[h] and ty ~= "EMPTY" and ty ~= "MELEE_1H_CASTER" then
                    local slot = HANDS[h].slot
                    local kind, value, invSlot = WhatHandShows(slot)
                    if kind == "item" then
                        local ench = FPWeaponsDB.showEnchants ~= false and SlotEffect(slot) or nil
                        weapons[#weapons + 1] = { item = value, enchant = ench, slot = HANDS[h].tryOnSlot, invSlot = invSlot }
                        key = key .. ":t" .. tostring((Scene.Transmog(invSlot)))
                        key = key .. ":" .. h .. value .. ":" .. tostring(ench)
                    end
                end
            end
            if force or not Scene.pending.CAST or Scene.castKey ~= key then
                if Swing.debugRebuild then
                    DEFAULT_CHAT_FRAME:AddMessage(("|cff00ff00[FPWeapons rebuild]|r casting model (%s)\n  was: %s\n  now: %s"):format(
                        force and tostring(Scene.rebuildWhy) or (Scene.pending.CAST and "setup changed" or "not built yet"), tostring(Scene.castKey), key))
                end
                Scene.castKey = key
                Scene.Render("CAST", nil, nil, weapons)
            end
        else
            Scene.castKey = nil
            if Scene.pending.CAST then Scene.Clear("CAST") end
            Scene.cast.editing = false
            if Scene.cast.state then Scene.SetCastState(nil) end
        end
    end
    ApplyPoses()
    -- rebuilt models load in the background (whole characters take longer): pose them again as they do
    if changedMH or changedOH or changedRW then Scene.Reassert(Scene.REASSERT_LOADING) end
end

--==[ Turning first-person mode on / off ]======================================
-- Turning first-person mode off zooms the camera back out toward where it was, capped at this
-- many yards (0 = leave the camera where it is).
Scene.ZOOM_BACK_MAX = 3

-- Camera settings first-person mode switches on: { setting, value while on, value to restore if
-- the previous one wasn't recorded }
Scene.CAMERA_CVARS = {
    { "cameraSmoothStyle", 4, 1 },        -- camera follows where you face
    { "cameraTerrainTilt", 1, 0 },        -- tilt with the ground
    { "cameraMode", 1, 0 },
    { "test_cameraDynamicPitch", 1, 0 },  -- look up / down naturally
}
Scene.cameraBefore = {}
function Scene.CameraSettings(on)
    for _, c in ipairs(Scene.CAMERA_CVARS) do
        local name = c[1]
        if on then
            Scene.cameraBefore[name] = GetCVar(name)
            SetCVar(name, c[2])
        else
            local before = Scene.cameraBefore[name]
            SetCVar(name, (before ~= nil) and before or c[3])
        end
    end
end

-- alreadyZoomedIn: the camera is already in first person (auto toggle), so don't zoom.

local function EnableFPSControls(alreadyZoomedIn)
    State.mountHidden = false
    
    FPWeaponsDB.savedZoom = GetCameraZoom()

    Scene.CameraSettings(true)
    if not alreadyZoomedIn then CameraZoomIn(Scene.CAMERA_ALL_IN) end

    State.fpOn = true
    UpdateVisibility()
    Scene.ReassertShown()
    -- Keep the hand models already built (rebuilding them each time cost their poses); they
    -- are only rebuilt if they never were or what they should show has changed.
    RefreshWeaponModels()
    -- and pose them again once the frames are laid out and the camera has settled
    Scene.Reassert(Scene.REASSERT_TURNED_ON)
    UpdateVisibility()
    UpdateMountState()
end

-- skipZoom: leave the camera where it is (the auto toggle uses this: you're already zooming out)
local function DisableFPSControls(skipZoom)
    State.fpOn = false
    State.mountHidden = false
    UpdateVisibility()

    Scene.CameraSettings(false)

    local zoomBack = FPWeaponsDB.savedZoom
    if not skipZoom and zoomBack and zoomBack > 0 and Scene.ZOOM_BACK_MAX > 0 then
        CameraZoomOut(math.min(zoomBack, Scene.ZOOM_BACK_MAX))
    end
end

-- words that open the settings panel: /fpw config, /fpw options...
Scene.OPEN_PANEL_WORDS = { config = true, settings = true, options = true, opt = true, menu = true }

local function ToggleFirstPerson()
    if InCombatLockdown() then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FPWeapons]|r FPW cannot be enabled/disabled in combat")
        return
    end

    if State.fpOn then
        DisableFPSControls()
    else
        EnableFPSControls()
    end
end

-------------------------------------------------------------------------------
-- AUTO TOGGLE AT MAX ZOOM
-- FPS mode turns on when the camera reaches maximum zoom-in (first person) and off as soon as it
-- leaves it. Only the moment the camera crosses that point counts, so "/fpw" still works by hand:
-- the auto toggle won't fight it until the camera crosses the threshold again.
-- In combat the switch waits until combat ends. While mounted, the addon's own mount zoom-out
-- doesn't turn FPS mode off (it zooms back in when you dismount, as before).
-------------------------------------------------------------------------------
local AutoZoom = {
    MAX_ZOOM = 0.05,   -- camera distance (yards) that counts as "fully zoomed in"
    POLL = 0.1,        -- seconds between checks
    timer = 0,
    SETTLE_MAX = 3,    -- after FPS mode turns on, ignore the camera being "out" for up to this long
    settleUntil = nil, -- while set, waiting for the camera to settle at max zoom-in
    lastActive = false,
    wasAtMax = nil,    -- nil = not checked yet
    pending = nil,     -- "on" / "off" waiting to be applied (e.g. until combat ends)
    frame = CreateFrame("Frame"),
}
AutoZoom.frame:SetScript("OnUpdate", function(self, elapsed)
    AutoZoom.timer = AutoZoom.timer + elapsed
    if AutoZoom.timer < AutoZoom.POLL then return end
    AutoZoom.timer = 0
    if not FPWeaponsDB or FPWeaponsDB.autoZoomToggle == false then
        AutoZoom.wasAtMax, AutoZoom.pending = nil, nil
        return
    end

    local ok, zoom = pcall(GetCameraZoom)
    if not ok or type(zoom) ~= "number" or issecretvalue(zoom) then return end
    local atMax = zoom <= AutoZoom.MAX_ZOOM

    -- When FPS mode has just turned on (by any route), the camera may still be travelling in.
    -- Treat it as "at max" until it gets there, so that trip can't switch FPS mode back off.
    if State.fpOn and not AutoZoom.lastActive then
        AutoZoom.settleUntil = GetTime() + AutoZoom.SETTLE_MAX
    end
    AutoZoom.lastActive = State.fpOn
    if AutoZoom.settleUntil then
        if atMax or not State.fpOn or GetTime() > AutoZoom.settleUntil then
            AutoZoom.settleUntil = nil
        else
            atMax = true
        end
    end

    if atMax ~= AutoZoom.wasAtMax then
        AutoZoom.wasAtMax = atMax
        AutoZoom.pending = atMax and "on" or "off"
    end

    local want = AutoZoom.pending
    if not want then return end
    if want == "off" and (State.mountHidden or IsMounted() or UnitInVehicle("player") or UnitOnTaxi("player")) then
        AutoZoom.pending = nil  -- the mount zoom-out is the addon's own; stay in FPS mode
        return
    end
    if InCombatLockdown() then return end  -- try again once combat ends
    AutoZoom.pending = nil
    if want == "on" and not State.fpOn then
        EnableFPSControls(true)
        AutoZoom.lastActive = true  -- camera is already at max: nothing to wait for
    elseif want == "off" and State.fpOn then
        DisableFPSControls(true)
    end
end)

--==[ Settings panel ]==========================================================
local optionsFrame = CreateFrame("Frame", "FPWeaponsConfig", UIParent)
-- Everything below up to the matching "end" lives in its own block: only optionsFrame is used
-- outside it, and this keeps the file well under Lua's 200 top-level local variable limit.
do
local W = 350          -- panel width
local PAD = 20         -- left / right margin
local CW = W - PAD * 2 -- content width
local UI = {           -- colours
    panel  = { 0.05, 0.05, 0.06, 0.92 },
    band   = { 0.10, 0.10, 0.12, 1 },
    edge   = { 0.28, 0.28, 0.31, 1 },
    gold   = { 1.00, 0.82, 0.00 },
    dim    = { 0.62, 0.62, 0.65 },
    btn    = { 0.15, 0.15, 0.17, 1 },
    btnSel = { 0.50, 0.38, 0.06, 1 },
    warn   = { 0.36, 0.08, 0.07, 1 },
}

optionsFrame:SetSize(W, 600)
optionsFrame:SetPoint("CENTER", UIParent, "CENTER", (tonumber(UIParent:GetWidth()) or 1024) / 4, 0)  -- right side, halfway to the edge
optionsFrame:SetMovable(true)
optionsFrame:EnableMouse(true)
optionsFrame:RegisterForDrag("LeftButton")
optionsFrame:SetScript("OnDragStart", optionsFrame.StartMoving)
optionsFrame:SetScript("OnDragStop", optionsFrame.StopMovingOrSizing)
optionsFrame:SetClampedToScreen(true)
optionsFrame:Hide()

-- 1px lines and filled boxes
function UI.Fill(parent, layer, color)
    local t = parent:CreateTexture(nil, layer)
    t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    return t
end
function UI.Outline(frame, color)
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, -1 },
                         { "TOPLEFT", "BOTTOMLEFT", -1, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 1, 0 } }) do
        local t = UI.Fill(frame, "BORDER", color)
        t:SetPoint(e[1], frame, e[1], e[3], e[4])
        t:SetPoint(e[2], frame, e[2], e[3], e[4])
        if e[3] == 0 then t:SetHeight(1) else t:SetWidth(1) end
    end
end

do -- background, title band, title, close button
UI.Fill(optionsFrame, "BACKGROUND", UI.panel):SetAllPoints(optionsFrame)
UI.Outline(optionsFrame, UI.edge)
-- title band
local band = UI.Fill(optionsFrame, "BORDER", UI.band)
band:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 0, 0)
band:SetPoint("TOPRIGHT", optionsFrame, "TOPRIGHT", 0, 0)
band:SetHeight(38)
local bandLine = UI.Fill(optionsFrame, "ARTWORK", { UI.gold[1], UI.gold[2], UI.gold[3], 0.35 })
bandLine:SetPoint("TOPLEFT", band, "BOTTOMLEFT", 0, 0)
bandLine:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT", 0, 0)
bandLine:SetHeight(1)

local title = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", PAD, -11)
title:SetText("FP Weapons")
local subtitle = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
subtitle:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 1)
subtitle:SetText("settings")

local closeBtn = CreateFrame("Button", nil, optionsFrame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", optionsFrame, "TOPRIGHT", -2, -2)
end

-- Hover help
function UI.Tip(frame, text)
    frame:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

-- Flat button: dark box, light text, faint highlight on hover; SetSelected marks the chosen one
-- of a group. align = "LEFT" puts the text at the left (for the dropdown).
function UI.Flat(parent, w, h, text, align)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.bg = UI.Fill(b, "BACKGROUND", UI.btn)
    b.bg:SetAllPoints(b)
    UI.Outline(b, { 0.25, 0.25, 0.28, 1 })
    UI.Fill(b, "HIGHLIGHT", { 1, 1, 1, 0.07 }):SetAllPoints(b)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if align == "LEFT" then fs:SetPoint("LEFT", b, "LEFT", 8, 0) else fs:SetPoint("CENTER", b, "CENTER", 0, 0) end
    b:SetFontString(fs)
    b:SetText(text or "")
    b.base = UI.btn
    function b:SetSelected(on)
        local c = on and UI.btnSel or self.base
        self.bg:SetColorTexture(c[1], c[2], c[3], c[4])
        fs:SetFontObject(on and "GameFontNormalSmall" or "GameFontHighlightSmall")
    end
    -- a muted red, for buttons that throw settings away
    function b:SetWarning()
        self.base = UI.warn
        self.bg:SetColorTexture(UI.warn[1], UI.warn[2], UI.warn[3], UI.warn[4])
        fs:SetTextColor(1, 0.86, 0.82)
    end
    return b
end

-- Section heading: gold small caps with a faint rule running to the right edge
function UI.Heading(text)
    local fs = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetText(text:upper())
    -- (the rule only hangs off the heading, so it moves with it; its width fills the rest of the row)
    local rule = UI.Fill(optionsFrame, "ARTWORK", { UI.gold[1], UI.gold[2], UI.gold[3], 0.2 })
    rule:SetHeight(1)
    rule:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    local ok, tw = pcall(fs.GetStringWidth, fs)
    rule:SetWidth(math.max(20, CW - 8 - ((ok and type(tw) == "number" and tw > 0) and tw or (#text * 7))))
    return fs
end
function UI.Note(text)
    local fs = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetText(text or "")
    fs:SetJustifyH("LEFT")
    return fs
end

local activeTab = "MH"

local WEAPON_TYPES = {
    { text = "Auto (Detect Equipped Weapon)", value = "AUTO" },
    { text = "Hidden", value = "NONE" },
    { text = "Gun / Crossbow", value = "GUN" },
    { text = "Bow", value = "BOW" },
    { text = "One-Handed Weapon", value = "MELEE_1H" },
    -- tabText: a different label on that tab; tabLast: listed at the bottom on that tab
    { text = "One-Handed (Caster)", value = "MELEE_1H_CASTER",
      tabText = { OH = "Caster Hand (Off Hand)" }, tabLast = { OH = true } },
    { text = "Two-Handed Weapon", value = "MELEE_2H" },
    { text = "Caster Weapon", value = "STAFF" },
    { text = "Wand", value = "WAND" },
    { text = "Caster Hand (Main Hand)", value = "EMPTY" },
    { text = "Shield", value = "SHIELD" },
    { text = "Off-Hand Item", value = "OFFHAND" },
}

local RefreshPanel
Scene.RefreshPanel = function() RefreshPanel() end  -- (for code above the panel)
Scene.PanelShown = function() return optionsFrame:IsShown() end
local LayoutPanel
local panelLoading = false  -- true while sliders are being loaded from saved data (so loading never writes back)

--== Weapons section =========================================================
local weaponsHead = UI.Heading("Weapons")

-- Hand tabs: one segmented row
local TABS, TAB_ORDER = {}, { { "MH", "Main Hand" }, { "OH", "Off Hand" }, { "RW", "Ranged" } }
local tabW = (CW - 4) / 3
for i, t in ipairs(TAB_ORDER) do
    local b = UI.Flat(optionsFrame, tabW, 24, t[2])
    b.tabKey = t[1]
    TABS[t[1]] = b
end

local typeLabel = UI.Note("Weapon type")
local typePicker = UI.Flat(optionsFrame, CW, 24, "", "LEFT")
typePicker:SetPoint("TOPLEFT", typeLabel, "BOTTOMLEFT", 0, -5)
do
    local arrow = typePicker:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", typePicker, "RIGHT", -8, 0)
    arrow:SetRotation(-math.pi / 2)  -- (the texture points right; turn it to point down)
end
UI.Tip(typePicker, "What this hand holds, which decides its animations and poses. Auto follows your equipped weapons.")

local typeList = CreateFrame("Frame", nil, optionsFrame)
typeList:SetSize(CW, 200)
typeList:SetPoint("TOPLEFT", typePicker, "BOTTOMLEFT", 0, -2)
typeList:SetFrameStrata("DIALOG")
typeList:Hide()
UI.Fill(typeList, "BACKGROUND", { 0.09, 0.09, 0.10, 0.98 }):SetAllPoints(typeList)
UI.Outline(typeList, UI.edge)

-- The label a weapon type shows on the current tab
local function TypeLabel(item)
    return (item.tabText and item.tabText[activeTab]) or item.text
end

local function ShowPickedType()
    local saved = FPWeaponsDB[HANDS[activeTab].prefix .. "_type"]
    local currentVal = GetHandType(activeTab)
    for _, item in ipairs(WEAPON_TYPES) do
        if item.value == currentVal then
            local label = TypeLabel(item)
            if saved == "AUTO" then label = "Auto: " .. label:gsub("%s*%b()$", "") end
            typePicker:SetText(label)
            break
        end
    end
end

local typeListButtons = {}

-- Show only the weapon types the current tab is allowed to use, and size the menu to fit
local function LayoutTypeMenu()
    local allowed = ALLOWED_TYPES[activeTab]
    local saved = FPWeaponsDB[HANDS[activeTab].prefix .. "_type"] or "AUTO"
    local row = 0
    -- two passes: normal entries first, then any entry marked to go last on this tab
    for pass = 1, 2 do
        for _, btn in ipairs(typeListButtons) do
            local item = btn.typeItem
            local isLast = (item.tabLast and item.tabLast[activeTab]) and true or false
            if (pass == 2) == isLast then
                btn:ClearAllPoints()
                if allowed[item.value] then
                    btn:SetText(TypeLabel(item))
                    btn:SetSelected(item.value == saved)
                    btn:SetPoint("TOPLEFT", typeList, "TOPLEFT", 6, -6 - (row * 22))
                    btn:Show()
                    row = row + 1
                else
                    btn:Hide()
                end
            end
        end
    end
    typeList:SetHeight(12 + row * 22 - 2)
end

for i, item in ipairs(WEAPON_TYPES) do
    local btn = UI.Flat(typeList, CW - 12, 20, item.text, "LEFT")
    btn:SetPoint("TOPLEFT", typeList, "TOPLEFT", 6, -6 - ((i - 1) * 22))
    btn.typeValue = item.value
    btn.typeItem = item
    typeListButtons[#typeListButtons + 1] = btn
    btn:SetScript("OnClick", function()
        FPWeaponsDB[HANDS[activeTab].prefix .. "_type"] = item.value
        typeList:Hide()
        RefreshPanel()
        RefreshWeaponModels(true)
    end)
end

typePicker:SetScript("OnClick", function()
    if typeList:IsShown() then typeList:Hide() else LayoutTypeMenu(); typeList:Show() end
end)

--== Position (collapsible) ==================================================
local orientToggle = UI.Flat(optionsFrame, CW, 22, "")
orientToggle:SetScript("OnClick", function()
    FPWeaponsDB.showOrientation = not FPWeaponsDB.showOrientation
    LayoutPanel()
end)
UI.Tip(orientToggle, "Move and turn the model for this hand and weapon type. Each weapon type remembers its own position.")

-- Which pose the sliders edit: the hand at rest, or the casting model's cast / release poses,
-- or the attack pose. Only the ones this weapon setup has are offered.
local POSES = { { "rest", "Resting" }, { "cast", "Cast" }, { "release", "Release" }, { "attack", "Attack" } }
local poseBtns = {}
for _, p in ipairs(POSES) do
    local b = UI.Flat(optionsFrame, 70, 20, p[2])
    b.poseKey = p[1]
    poseBtns[p[1]] = b
end
local poseNote = UI.Note()

-- The pose currently being edited ("rest" when none of the others)
local function EditedPose()
    local e = Scene.cast.editing
    if e == "cast" or e == "release" or e == "attack" then return e end
    if Scene.attack.editing == activeTab then return "attack" end
    return "rest"
end

-- The attack setup for melee attacks on the casting model (dual wield), if this tab has one
local function ActionAttackProfile()
    local pa = Scene.Profile(true)
    if pa and pa.attack and pa.replace[activeTab] then return pa end
    return nil
end

local function SelectPose(kind)
    local c = Scene.cast
    if Scene.attack.editing then Scene.SetAttackEdit(nil) end
    local hadCast = c.editing
    c.editing = false
    if kind == "cast" or kind == "release" then
        c.editing = kind
        RefreshWeaponModels()   -- make sure the casting model is built
    elseif kind == "attack" then
        if ActionAttackProfile() then
            c.editing = "attack"
            RefreshWeaponModels()
        else
            Scene.SetAttackEdit(activeTab)
        end
    end
    if (hadCast or c.editing) and not c.state then Scene.SetCastState(nil) end  -- refreshes what's visible
    RefreshPanel()
end
for key, b in pairs(poseBtns) do
    b:SetScript("OnClick", function() SelectPose(key) end)
end
UI.Tip(poseBtns.cast, "Shows the casting model holding its cast pose, so you can position it.")
UI.Tip(poseBtns.release, "Shows the casting model's release (spell going off) pose, so you can position it.")
UI.Tip(poseBtns.attack, "Loops this hand's attack, so you can position its attack pose.")

-- SLIDERS. Each slider carries its own label, step and (for pose sliders) the pose field it edits,
-- plus whether a saved value outside its range should widen the range instead of being clamped.
local function MakeSlider(name, label, lo, hi, step, field, widen)
    local sl = CreateFrame("Slider", name, optionsFrame, "OptionsSliderTemplate")
    sl:SetSize(CW - 10, 16)
    sl:SetMinMaxValues(lo, hi)
    sl:SetValueStep(step)
    sl.label, sl.step, sl.field, sl.widen = label, step, field, widen
    sl.text, sl.lowText, sl.highText = _G[name .. "Text"], _G[name .. "Low"], _G[name .. "High"]
    sl.lowText:SetText(tostring(lo))
    sl.highText:SetText(tostring(hi))
    -- (the value is in the label; the end numbers only add clutter)
    sl.lowText:Hide()
    sl.highText:Hide()
    return sl
end
-- Round to the slider's step
function Scene.Snap(v, step) return step * math.floor(v / step + 0.5) end
function Scene.SliderText(sl, value)
    sl.text:SetText(("%s: %." .. ((sl.step < 0.1) and 2 or 1) .. "f"):format(sl.label, value))
end
-- Show a saved value on a slider (widening its range first if it lies outside it, so the value
-- is shown as it is rather than clamped)
function Scene.ShowSlider(sl, value)
    if sl.widen then
        local lo, hi = sl:GetMinMaxValues()
        if value < lo or value > hi then
            lo, hi = math.min(lo, math.floor(value) - 1), math.max(hi, math.ceil(value) + 1)
            sl:SetMinMaxValues(lo, hi)
            sl.lowText:SetText(tostring(lo))
            sl.highText:SetText(tostring(hi))
        end
    end
    sl:SetValue(value)
    Scene.SliderText(sl, value)
end

local sFacing = MakeSlider("FPW_S_Facing", "Yaw / Facing (Z Axis)", 0.0, 6.28, 0.05, "facing")
local sPosX = MakeSlider("FPW_S_PosX", "Side to Side (X)", -8.0, 8.0, 0.05, "posX", true)
local sPosY = MakeSlider("FPW_S_PosY", "Near / Far (Y)", -8.0, 8.0, 0.05, "posY", true)
local sPosZ = MakeSlider("FPW_S_PosZ", "Height (Z)", -8.0, 8.0, 0.05, "posZ", true)
local sPitch = MakeSlider("FPW_S_Pitch", "Pitch (Y Axis)", -3.14, 3.14, 0.05, "pitch")
local sRoll = MakeSlider("FPW_S_Roll", "Roll (X Axis)", -3.14, 3.14, 0.05, "roll")
Scene.poseSliders = { sFacing, sPosX, sPosY, sPosZ, sPitch, sRoll }

-- Reset the pose being shown (this weapon type's resting pose, or the cast / release / attack pose)
local resetPoseBtn = UI.Flat(optionsFrame, (CW - 6) / 2, 22, "Reset Pose")
resetPoseBtn:SetWarning()
UI.Tip(resetPoseBtn, "Puts the pose selected above (resting, cast, release or attack) back to its default.")
resetPoseBtn:SetScript("OnClick", function()
    local target = Scene.EditTarget()
    if target == "CAST" or target == "RELEASE" or target == "ATTACK" then
        local pr = (target == "ATTACK") and ActionAttackProfile() or Scene.Profile()
        FPWeaponsDB[Scene.PoseKey(target, pr and pr.key or "BOTH")] = nil
    else
        -- a hand pose: remove the saved table GetPose hands out from its list
        local hand = target and target:sub(8) or activeTab
        local list = FPWeaponsDB[HANDS[hand].prefix .. "_transforms"] or {}
        local pose = GetPose(target or activeTab)
        for k, v in pairs(list) do if v == pose then list[k] = nil end end
    end
    RefreshPanel()
    ApplyPoses()
end)

-- "Save as <Race> Default" (see PER-RACE DEFAULTS)
Scene.raceBtn = UI.Flat(optionsFrame, CW, 22, "Save as Race Default")
Scene.raceBtn:HookScript("OnEnter", function(self)
    if not GameTooltip then return end
    local _, label = Scene.RaceKey()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Save as " .. (label or "Race") .. " Default", 1, 0.82, 0)
    GameTooltip:AddLine("Every position on this character becomes the starting point for your other "
        .. (label or "same-race") .. " characters (wherever they haven't set their own).", 1, 1, 1, true)
    GameTooltip:Show()
end)
Scene.raceBtn:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
Scene.raceBtn:SetScript("OnClick", function()
    local n, label = Scene.SaveRaceDefaults()
    local msg
    if n then
        msg = "Saved " .. n .. " hand/arm positions as the default for " .. label .. ". Other " .. label
            .. " characters will start from these wherever they haven't positioned something themselves."
    elseif label == "no-store" then
        msg = "|cffff6060Can't save race defaults:|r add  ## SavedVariables: FPWeaponsRaceDB  to FPWeapons.toc and /reload."
    else
        msg = "|cffff6060Can't save race defaults:|r your race couldn't be read right now."
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FPWeapons]|r " .. msg)
end)

--== Options section ==========================================================
local optionsHead = UI.Heading("Options")

local function Check(name, label, tip)
    local cb = CreateFrame("CheckButton", name, optionsFrame, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    local fs = _G[name .. "Text"]
    fs:SetText(label)
    fs:SetFontObject("GameFontHighlightSmall")
    if tip then UI.Tip(cb, tip) end
    return cb
end

local enchantCheck = Check("FPW_EnchantCheck", "Weapon enchant glow",
    "Shows enchant and weapon-effect glows (and transmog illusions) on the weapons.")
local sheathCheck = Check("FPW_SheathCheck", "Sheathe out of combat",
    "Puts the weapons away out of combat; abilities and combat bring them out again.")
local autoZoomCheck = Check("FPW_AutoZoomCheck", "Turn on at full zoom-in",
    "First-person mode turns on when you zoom all the way in, and off when you zoom back out.")
local bobCheck = Check("FPW_BobCheck", "Movement sway",
    "The weapons sway as you walk, turn and jump, and breathe gently when you stand still.")
local sBobIntensity = MakeSlider("FPW_S_BobIntensity", "Sway Strength", 0.1, 3.0, 0.1)
sBobIntensity:SetWidth(CW - 40)

autoZoomCheck:SetScript("OnClick", function(self)
    FPWeaponsDB.autoZoomToggle = self:GetChecked() and true or false
end)

-- SHEATHE / DRAW KEY: a key (set in the panel) that flips the "Sheathe out of combat" option:
-- on = weapons go away now (out of combat) and come out on abilities as usual, off = they stay drawn.
Scene.bindOwner = CreateFrame("Frame")
Scene.sheatheClick = CreateFrame("Button", "FPWeaponsSheatheButton", UIParent)
Scene.sheatheClick:SetScript("OnClick", function() Scene.ToggleSheath() end)
function Scene.ToggleSheath()
    local on = FPWeaponsDB.autoSheath == false  -- the new setting
    FPWeaponsDB.autoSheath = on
    sheathCheck:SetChecked(on)
    if on then
        State.drawTimer = 0               -- put them away right now (if out of combat)
        Scene.ranged.untilT = 0
    else
        State.drawTimer = Sheath.ABILITY_HOLD    -- (same as unticking the box)
    end
end
function Scene.ApplySheatheKey()
    if InCombatLockdown and InCombatLockdown() then Scene.keyPending = true return end  -- bindings are locked in combat
    Scene.keyPending = nil
    if ClearOverrideBindings then pcall(ClearOverrideBindings, Scene.bindOwner) end
    local k = FPWeaponsDB and FPWeaponsDB.sheatheKey
    if k and k ~= "" and SetOverrideBindingClick then
        pcall(SetOverrideBindingClick, Scene.bindOwner, true, k, "FPWeaponsSheatheButton")
    end
end
Scene.keyBtn = UI.Flat(optionsFrame, 104, 20, "")
UI.Tip(Scene.keyBtn, "A key that switches \"Sheathe out of combat\" on and off. Click, then press the key (Esc clears it).")
function Scene.UpdateKeyText()
    local k = FPWeaponsDB and FPWeaponsDB.sheatheKey
    Scene.keyBtn:SetText(Scene.capturingKey and "Press a key..."
        or ((k and k ~= "") and ("Key: " .. k) or "Set Key"))
end
Scene.MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
                        LMETA = true, RMETA = true, UNKNOWN = true }
Scene.keyBtn:SetScript("OnClick", function(self)
    if InCombatLockdown and InCombatLockdown() then
        print("|cff00ff00[FPWeapons]|r The key can't be changed in combat.")
        return
    end
    Scene.capturingKey = true
    -- (a key handler takes all keyboard input, so it only exists while waiting for the key)
    self:SetScript("OnKeyDown", Scene.OnBindKey)
    self:EnableKeyboard(true)
    if self.SetPropagateKeyboardInput then pcall(self.SetPropagateKeyboardInput, self, false) end
    Scene.UpdateKeyText()
end)
function Scene.StopKeyCapture(self)
    Scene.capturingKey = nil
    self:SetScript("OnKeyDown", nil)
    self:EnableKeyboard(false)
    if self.SetPropagateKeyboardInput then pcall(self.SetPropagateKeyboardInput, self, true) end
    Scene.UpdateKeyText()
end
function Scene.OnBindKey(self, key)
    if not Scene.capturingKey or Scene.MODIFIER_KEYS[key] then return end
    if key == "ESCAPE" then
        FPWeaponsDB.sheatheKey = nil
    else
        local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
            .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
        FPWeaponsDB.sheatheKey = combo
    end
    Scene.StopKeyCapture(self)
    Scene.ApplySheatheKey()
end
Scene.keyBtn:SetScript("OnHide", function(self)
    if Scene.capturingKey then Scene.StopKeyCapture(self) end
end)

--== Footer ===================================================================
-- (red: they throw settings away; placed by LayoutPanel under Reset Pose / Save as Race Default)
local resetHandBtn = UI.Flat(optionsFrame, (CW - 6) / 2, 22, "Reset This Tab")
resetHandBtn:SetWarning()
UI.Tip(resetHandBtn, "Sets this tab back to Auto and clears every position saved for it.")
local resetAllBtn = UI.Flat(optionsFrame, (CW - 6) / 2, 22, "Reset Everything")
resetAllBtn:SetWarning()
UI.Tip(resetAllBtn, "Clears every setting and position on this character.")

--== Layout ===================================================================
-- Stacks everything top to bottom (skipping what's hidden) and sizes the panel to fit
LayoutPanel = function()
    local y = -52
    local function place(frame, top, x)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", PAD + (x or 0), top)
        frame:Show()
    end
    local function slider(sl, shown, x)
        if not shown then sl:Hide() return end
        place(sl, y - 15, (x or 0) + 5)   -- (its label sits above it)
        y = y - 38
    end

    -- Weapons
    place(weaponsHead, y); y = y - 18
    for i, t in ipairs(TAB_ORDER) do
        place(TABS[t[1]], y, (i - 1) * (tabW + 2))
        TABS[t[1]]:SetSelected(t[1] == activeTab)
    end
    y = y - 34
    place(typeLabel, y); y = y - 46   -- (the picker hangs below its label)

    -- Position
    local showO = FPWeaponsDB.showOrientation == true
    place(orientToggle, y)
    orientToggle:SetText((showO and "-  " or "+  ") .. "Adjust Position")
    y = y - 30

    -- which poses this tab has
    local prof = Scene.Profile()
    local hasCast = prof and prof.cast and prof.replace[activeTab] and true or false
    local actionAttack = ActionAttackProfile()
    local alist = (activeTab == "MH" or activeTab == "OH") and Scene.MeleeAnimated(activeTab)
        and Scene.attack.ANIMS[activeTab .. "_" .. GetHandType(activeTab)]
    local hasAttack = (actionAttack or (alist and #alist > 0)) and true or false
    -- stop editing a pose this setup no longer has
    local c = Scene.cast
    if ((c.editing == "cast" or c.editing == "release") and not hasCast) or (c.editing == "attack" and not actionAttack) then
        c.editing = false
        Scene.SetCastState(c.state)
    end
    if Scene.attack.editing and (Scene.attack.editing ~= activeTab or not hasAttack) then Scene.SetAttackEdit(nil) end

    local offered = { rest = true, cast = hasCast, release = hasCast, attack = hasAttack }
    local list = {}
    for _, p in ipairs(POSES) do
        if offered[p[1]] then list[#list + 1] = poseBtns[p[1]] else poseBtns[p[1]]:Hide() end
    end
    local editing = EditedPose()
    if showO then
        if #list > 1 then
            local bw = (CW - 2 * (#list - 1)) / #list
            for i, b in ipairs(list) do
                b:SetWidth(bw)
                place(b, y, (i - 1) * (bw + 2))
                b:SetSelected(b.poseKey == editing)
            end
            y = y - 24
            local setup = (editing == "attack" and actionAttack) or ((editing == "cast" or editing == "release") and prof)
            if setup and setup.label then
                place(poseNote, y)
                poseNote:SetText("Setup: " .. setup.label)
                y = y - 14
            else
                poseNote:Hide()
            end
            y = y - 4
        else
            for _, b in ipairs(list) do b:Hide() end
            poseNote:Hide()
        end
        -- positions X, Y, Z, then rotations about X, Y, Z
        for _, sl in ipairs({ sPosX, sPosY, sPosZ }) do slider(sl, true) end
        y = y - 6   -- (a little space between moving and turning)
        for _, sl in ipairs({ sRoll, sPitch, sFacing }) do slider(sl, true) end
    else
        for _, b in pairs(poseBtns) do b:Hide() end
        poseNote:Hide()
        for _, sl in ipairs(Scene.poseSliders) do sl:Hide() end
    end
    -- Reset Pose / Reset This Tab, then (while adjusting) Save as Race Default underneath
    local bw = (CW - 4) / 2
    for i, b in ipairs({ resetPoseBtn, resetHandBtn }) do
        b:SetWidth(bw)
        place(b, y, (i - 1) * (bw + 4))
    end
    y = y - 26
    if showO and Scene.Active() then
        place(Scene.raceBtn, y)
        y = y - 26
    else
        Scene.raceBtn:Hide()
    end
    y = y - 8

    -- Options
    y = y - 6
    place(optionsHead, y); y = y - 20
    for _, cb in ipairs({ enchantCheck, sheathCheck, autoZoomCheck, bobCheck }) do
        place(cb, y, -4)
        if cb == sheathCheck then
            place(Scene.keyBtn, y - 2, CW - 104)
            Scene.UpdateKeyText()
        end
        y = y - 24
    end
    slider(sBobIntensity, FPWeaponsDB.enableBob == true, 24)

    -- Reset Everything at the very bottom, away from everyday controls
    y = y - 8
    place(resetAllBtn, y)
    resetAllBtn:SetWidth(CW)
    y = y - 22

    optionsFrame:SetHeight(-y + 14)
end

sheathCheck:SetScript("OnClick", function(self)
    FPWeaponsDB.autoSheath = self:GetChecked() and true or false
    if not FPWeaponsDB.autoSheath then State.drawTimer = Sheath.ABILITY_HOLD end
    ApplyPoses()
end)

enchantCheck:SetScript("OnClick", function(self)
    FPWeaponsDB.showEnchants = self:GetChecked() and true or false
    RefreshWeaponModels(true)
end)

bobCheck:SetScript("OnClick", function(self)
    FPWeaponsDB.enableBob = self:GetChecked() and true or false
    ApplyPoses()
    LayoutPanel()  -- Sway Strength only shows while sway is on
end)

sBobIntensity:SetScript("OnValueChanged", function(self, value)
    value = Scene.Snap(value, self.step)
    FPWeaponsDB.bobIntensity = value
    Scene.SliderText(self, value)
    ApplyPoses()
end)


RefreshPanel = function()
    panelLoading = true
    ShowPickedType()

    bobCheck:SetChecked(FPWeaponsDB.enableBob == true)
    enchantCheck:SetChecked(FPWeaponsDB.showEnchants ~= false)
    sheathCheck:SetChecked(FPWeaponsDB.autoSheath ~= false)
    Scene.UpdateKeyText()
    autoZoomCheck:SetChecked(FPWeaponsDB.autoZoomToggle ~= false)
    LayoutPanel()

    Scene.ShowSlider(sBobIntensity, FPWeaponsDB.bobIntensity or 0.5)

    local pose = GetPose(Scene.EditTarget() or activeTab)
    for _, sl in ipairs(Scene.poseSliders) do Scene.ShowSlider(sl, pose[sl.field] or 0) end

    panelLoading = false
    ApplyPoses()
end

optionsFrame:SetScript("OnShow", RefreshPanel)
optionsFrame:SetScript("OnHide", function()
    -- closing the panel ends pose editing
    typeList:Hide()
    if Scene.attack.editing then Scene.SetAttackEdit(nil) end
    if Scene.cast.editing then
        Scene.cast.editing = false
        Scene.SetCastState(Scene.cast.state)
    end
end)

-- Moving a pose slider edits that field of the pose being edited. (While the panel is filling
-- the sliders in, nothing is written back: the slider would hand back a snapped/clamped copy.)
for _, sl in ipairs(Scene.poseSliders) do
    sl:SetScript("OnValueChanged", function(self, value)
        if panelLoading then return end
        value = Scene.Snap(value, self.step)
        GetPose(Scene.EditTarget() or activeTab)[self.field] = value
        Scene.SliderText(self, value)
        ApplyPoses()
    end)
end

local function OpenTab(tab)
    activeTab = tab
    typeList:Hide()
    -- a different hand: stop editing the last one's poses
    if Scene.attack.editing and Scene.attack.editing ~= tab then Scene.SetAttackEdit(nil) end
    RefreshPanel()
end
for key, b in pairs(TABS) do
    b:SetScript("OnClick", function() OpenTab(key) end)
end
OpenTab("MH")

resetHandBtn:SetScript("OnClick", function()
    local h = HANDS[activeTab]
    FPWeaponsDB[h.prefix .. "_type"] = h.defType
    FPWeaponsDB[h.prefix .. "_overrides"] = {}
    FPWeaponsDB[h.prefix .. "_transforms"] = {}
    typeList:Hide()
    RefreshPanel()
    RefreshWeaponModels(true)
end)

resetAllBtn:SetScript("OnClick", function()
    FPWeaponsDB = NewSettings()
    typeList:Hide()
    RefreshPanel()
    RefreshWeaponModels(true)
end)

end -- settings panel (kept in its own block so its many locals don't count against Lua's 200-local limit)

--==[ Slash commands & events ]=================================================

SLASH_FPWEAPONS1 = "/fpw"
SLASH_FPWEAPONS2 = "/fpweapons"
SlashCmdList["FPWEAPONS"] = function(msg)
    local function say(t) DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FPWeapons]|r " .. t) end
    local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)%s*$")
    local function spellName(id)
        local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
        return (n or "?") .. " (" .. id .. ")"
    end
    if cmd == "tmog" or cmd == "transmog" then
        -- what the addon thinks each weapon slot looks like
        for _, slot in ipairs({ 16, 17, 18 }) do
            local pt = Scene.tmog[slot]
            local okI, item = pcall(GetInventoryItemID, "player", slot)
            local T = Enum and Enum.TransmogType
            say(("slot %d: item %s | game says: %s | read from character: %s%s | shown: %s"):format(slot, tostring(okI and item or nil),
                tostring(T and Scene.AppliedTransmog(slot, T.Appearance or 0)),
                tostring(pt and pt.src), (pt and pt.ill) and (" (illusion " .. pt.ill .. ")") or "",
                tostring((Scene.Transmog(slot)))))
        end
        if not Scene.probe then say("(hand/arm mode isn't available, so transmog can't be read)") end
        Scene.Probe()
        return
    elseif cmd == "sheathe" or cmd == "sheath" then
        Scene.ToggleSheath()  -- (for macros: /fpw sheathe)
        return
    elseif cmd == "debugrebuild" then
        Swing.debugRebuild = not Swing.debugRebuild
        say("Rebuild debug " .. (Swing.debugRebuild and "ON - each time a hand's model is reloaded, chat says which hand, why, and what changed" or "OFF"))
        return
    elseif cmd == "debugcombat" then
        Swing.debugCombat = not Swing.debugCombat
        say("Combat debug " .. (Swing.debugCombat and "ON - get hit, block and parry; each line shows what the game reported" or "OFF"))
        return
    elseif cmd == "debugcast" then
        Swing.debugCast = not Swing.debugCast
        say("Cast debug " .. (Swing.debugCast and ("ON (FPS mode is " .. (State.fpOn and "ON" or "OFF") .. ") - press some abilities; every line says whether it animated and, if not, why") or "OFF"))
        return
    elseif cmd == "ignorelast" then
        if State.lastTriggerSpellID then
            FPWeaponsDB.ignoredSpells = FPWeaponsDB.ignoredSpells or {}
            FPWeaponsDB.ignoredSpells[State.lastTriggerSpellID] = true
            say("Will no longer swing for " .. spellName(State.lastTriggerSpellID))
        else
            say("No spell has triggered a swing yet.")
        end
        return
    elseif cmd == "ignore" or cmd == "unignore" then
        local id = tonumber(arg)
        if not id then say("Usage: /fpw " .. cmd .. " <spellID>") return end
        FPWeaponsDB.ignoredSpells = FPWeaponsDB.ignoredSpells or {}
        FPWeaponsDB.ignoredSpells[id] = (cmd == "ignore") or nil
        say((cmd == "ignore" and "Ignoring " or "No longer ignoring ") .. spellName(id))
        return
    elseif cmd == "ignored" then
        local n = 0
        for id in pairs(FPWeaponsDB.ignoredSpells or {}) do n = n + 1; say(spellName(id)) end
        if n == 0 then say("No ignored spells.") end
        return
    end
    if Scene.OPEN_PANEL_WORDS[msg] then
        if optionsFrame:IsShown() then optionsFrame:Hide() else optionsFrame:Show() end
    elseif msg:match("^animblend") then
        -- /fpw animblend on|off : engine animation blending on the hand/arm and action models
        local v = msg:match("^animblend%s+(%a+)")
        if v == "on" or v == "off" then FPWeaponsDB.animBlend = (v == "on") end
        local supported = false
        for _, a in pairs(Scene.actors) do if Scene.ApplyAnimBlend(a) then supported = true end end
        local ops = Enum and Enum.ModelBlendOperation
        local names = {}
        if type(ops) == "table" then for k, n in pairs(ops) do names[#names + 1] = tostring(k) .. "=" .. tostring(n) end end
        say("Animation blending: " .. (FPWeaponsDB.animBlend ~= false and "ON" or "OFF")
            .. (supported and "" or "  |cffff6060(not supported by this client: the setting has no effect)|r"))
        say("  blend operations available: " .. (#names > 0 and table.concat(names, ", ") or "none listed"))
        say("  /fpw animblend on  |  /fpw animblend off   (applies immediately)")
    elseif msg:match("^attacklen") then
        -- /fpw attacklen <animID> <seconds> : how long an attack animation runs before going back to idle
        -- /fpw attacklen <animID>           : back to the default
        local idStr, secStr = msg:match("^attacklen%s+(%d+)%s*([%d%.]*)$")
        local id = tonumber(idStr)
        if not id then
            say("Usage: /fpw attacklen <animID> <seconds>   e.g. /fpw attacklen 654 0.7")
            for animID in pairs(Scene.attack.LENGTHS) do
                say("  " .. animID .. ": " .. Scene.AttackLength(animID) .. "s  (plays " .. Scene.AttackPlayTime(animID) .. "s after CUT_SHORT)")
            end
            return
        end
        FPWeaponsDB.attackLengths = FPWeaponsDB.attackLengths or {}
        FPWeaponsDB.attackLengths[id] = tonumber(secStr)
        say("Attack animation " .. id .. " length: " .. Scene.AttackLength(id) .. "s  (plays " .. Scene.AttackPlayTime(id) .. "s after CUT_SHORT)")
    elseif msg == "racedefault clear" then
        local key, label = Scene.RaceKey()
        if type(FPWeaponsRaceDB) == "table" and key then
            FPWeaponsRaceDB[key] = nil
            say("Cleared the saved hand/arm defaults for " .. label .. ".")
        end
    elseif msg == "racedefault" then
        local key, label = Scene.RaceKey()
        local function count(store)
            local e = type(store) == "table" and key and store[key]
            if type(e) ~= "table" then return nil end
            local n = 0
            for _, v in pairs(e) do
                if type(v) == "table" then
                    if v.posX ~= nil then n = n + 1 else for _ in pairs(v) do n = n + 1 end end  -- a pose, or a hand's weapon types
                end
            end
            return n
        end
        local mine, shipped = count(FPWeaponsRaceDB), count(FPWeaponsBuiltinRaceDefaults)
        say((label or "Your race") .. "  (key: " .. tostring(key) .. ")")
        say("  saved by you: " .. (mine and (mine .. " positions") or "none")
            .. (type(FPWeaponsRaceDB) ~= "table" and "  (FPWeaponsRaceDB isn't in the .toc yet)" or "")
            .. "   shipped with the addon: " .. (shipped and (shipped .. " positions") or "none"))
        say("  /fpw racedefault clear  removes the ones saved by you (shipped ones are kept).")
    elseif msg == "scene" then
        -- Reports whether the ModelScene hand/arm renderer is available and in use
        local a, f = Scene.actors.MH, Scene.frames.MH
        local function has(o, m) return (o and o[m]) and "yes" or "NO" end
        say("ModelScene renderer: " .. (Scene.ok and "available" or "NOT available (using old hand mode)")
            .. "  in use: " .. tostring(Scene.Active()))
        say("scene camera: SetCameraPosition=" .. has(f, "SetCameraPosition")
            .. " SetCameraOrientationByYawPitchRoll=" .. has(f, "SetCameraOrientationByYawPitchRoll")
            .. " SetCameraFieldOfView=" .. has(f, "SetCameraFieldOfView"))
        say("actor: SetModelByUnit=" .. has(a, "SetModelByUnit") .. " TryOn=" .. has(a, "TryOn")
            .. " SetAnimation=" .. has(a, "SetAnimation") .. " SetUseCenterForOrigin=" .. has(a, "SetUseCenterForOrigin")
            .. " IsLoaded=" .. has(a, "IsLoaded") .. " GetAnimation=" .. has(a, "GetAnimation"))
        say("model-loaded events received: " .. Scene.loadEvents
            .. "  loaded: MH=" .. tostring(Scene.loaded.MH) .. " OH=" .. tostring(Scene.loaded.OH) .. " RW=" .. tostring(Scene.loaded.RW))
        for _, hand in ipairs({ "MH", "OH", "RW" }) do
            local p = Scene.pending[hand]
            say(hand .. ": weaponSource=" .. tostring(p and p.weapon) .. " armPieces=" .. tostring(p and #p.arm))
        end
    elseif msg == "resetcam" then
        FPWeaponsDB.handCam = nil
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FPWeapons]|r Hand/arm camera cleared; it will be re-recorded the next time the hand model loads.")
        if State.fpOn then RefreshWeaponModels(true) end
    elseif msg == "debug" then
        -- Each hand's saved pose next to what its model frame reports right now
        local function say(t) DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FPWeapons]|r " .. t) end
        local function n(v) return type(v) == "number" and ("%.2f"):format(v) or "?" end
        local function ask(m, fn) local r = { pcall(m[fn], m) }; return r[1] and r or {} end
        say(("first-person %s, camera zoom %s"):format(State.fpOn and "ON" or "off", n(GetCameraZoom())))
        for _, hand in ipairs({ "MH", "OH", "RW" }) do
            local t, m = GetPose(hand), MODELS[hand]
            local sc, yaw, pos = ask(m, "GetModelScale"), ask(m, "GetFacing"), ask(m, "GetPosition")
            say(("%s  pose: size %s, yaw %s, side %s, near/far %s, height %s"):format(hand,
                n(t.scale), n(t.facing), n(t.posX), n(t.posY), n(t.posZ)))
            say(("%s  frame: size %s, yaw %s, position %s / %s / %s, %s, alpha %s"):format(hand,
                n(sc[2]), n(yaw[2]), n(pos[2]), n(pos[3]), n(pos[4]),
                m:IsShown() and "shown" or "hidden", n(m:GetEffectiveAlpha())))
        end
    elseif msg == "enchants" then
        -- What weapon effect each slot has and how the weapon-only renderer showed it
        local function say(t) DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FPWeapons]|r " .. t) end
        say("effects shown: " .. ((FPWeaponsDB.showEnchants ~= false) and "yes" or "no (turned off)"))
        if GetWeaponEnchantInfo then
            local r = { pcall(GetWeaponEnchantInfo) }
            local function fx(i) return ("has %s, id %s, expires %s, charges %s"):format(
                tostring(r[i]), tostring(r[i + 3]), tostring(r[i + 1]), tostring(r[i + 2])) end
            say("temporary effects -> main hand: " .. fx(2) .. " | off hand: " .. fx(6))
        else
            say("temporary effects: this client can't report them")
        end
        local NAMES = { [16] = "Main hand", [17] = "Off hand", [18] = "Ranged" }
        for _, slotID in ipairs({ 16, 17, 18 }) do
            local id, kind = SlotEffect(slotID)
            say(("%s: %s, illusion visual %s"):format(NAMES[slotID],
                id and (("%s effect %s"):format(kind, id)) or "no effect", tostring(EffectVisual(id))))
        end
    else
        ToggleFirstPerson()
    end
end

-------------------------------------------------------------------------------
-- Which casts should make the weapons swing / draw? Crafting, gathering and other
-- non-combat casts are ignored. Every check is pcall-guarded because several of these APIs
-- vary between client builds. Anything that still slips through can be ignored by hand with
-- "/fpw ignorelast" (see the slash commands).
-------------------------------------------------------------------------------
State.lastTriggerSpellID = nil

-- Common gathering / profession spells (per-expansion variants are caught by the other checks
-- or by /fpw ignorelast).
local NON_COMBAT_SPELLS = {
    [2575] = true,   [2576] = true,   [3564] = true,   [10248] = true, [29354] = true, [50310] = true,  -- Mining
    [2366] = true,   [2368] = true,   [3570] = true,   [11993] = true, [28695] = true, [50300] = true,  -- Herb Gathering
    [8613] = true,   [8617] = true,   [8618] = true,   [10768] = true, [32678] = true, [50305] = true,  -- Skinning
    [131474] = true, [7620] = true,   [7731] = true,   [7732] = true,  [18248] = true,                   -- Fishing
    [13262] = true,  [31252] = true,  [51005] = true,  [80451] = true,                                   -- Disenchant / Prospecting / Milling / Survey
    [3365] = true,   [6478] = true,   [6477] = true,   [21651] = true, [22810] = true,                   -- Opening
    [2656] = true,   [2018] = true,   [2108] = true,   [3908] = true,  [2259] = true,  [2550] = true,    -- Smelting / Blacksmithing / Leatherworking / Tailoring / Alchemy / Cooking bases
}

local function ShouldAnimateForSpell(spellID)
    if type(spellID) ~= "number" or issecretvalue(spellID) then return true end  -- unknown: behave as before

    local ignored = FPWeaponsDB.ignoredSpells
    if ignored and ignored[spellID] then return false, "on your ignore list" end
    if NON_COMBAT_SPELLS[spellID] then return false, "gathering/profession spell" end
    if spellID == 6603 then return false, "Auto Attack toggle (swing timer handles it)" end

    -- Crafting: a trade skill recipe. (Some clients hand back a table for any ID, so
    -- the table alone proves nothing: it has to be a learned recipe for this exact spell.)
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
        local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, spellID)
        if ok and type(info) == "table" and info.recipeID == spellID and info.learned == true then
            return false, "known trade skill recipe"
        end
    end
    -- Crafting while the profession window is open
    if ProfessionsFrame and ProfessionsFrame.IsShown and ProfessionsFrame:IsShown() then return false, "profession window is open" end
    local oldTradeSkill = rawget(_G, "TradeSkillFrame")   -- (the profession window on older clients)
    if oldTradeSkill and oldTradeSkill.IsShown and oldTradeSkill:IsShown() then return false, "profession window is open" end

    -- Mounts
    if C_MountJournal and C_MountJournal.GetMountFromSpell then
        local ok, mountID = pcall(C_MountJournal.GetMountFromSpell, spellID)
        if ok and mountID then return false, "mount" end
    end

    return true
end

-------------------------------------------------------------------------------
-- ABILITY DETECTION
-- Attack animations play only when an instant ability actually goes off
-- (UNIT_SPELLCAST_SUCCEEDED), never on the button press. Spells with a cast time are skipped:
-- finishing a cast isn't a melee attack. Auto Attack swings come from the swing timers above.
-- "/fpw debugcast" prints what's seen.
-------------------------------------------------------------------------------
State.lastAbilityTime, State.lastAbilitySpell = 0, nil

local function DStr(v)
    if issecretvalue(v) then return "<secret>" end
    return tostring(v)
end

local function CastDebug(t)
    if Swing.debugCast then DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FPWeapons cast]|r " .. t) end
end

local function SafeSpellID(v)
    if type(v) == "number" and not issecretvalue(v) then return v end
    return nil
end

local function AbilityPressed(spellID, source)
    if not State.fpOn then CastDebug(source .. ": NOT animating - FPS mode is off (toggle it on)") return end
    local allowed, why = ShouldAnimateForSpell(spellID)
    if not allowed then CastDebug(source .. " " .. DStr(spellID) .. ": NOT animating - filtered: " .. tostring(why)) return end
    local now = GetTime()
    if now - State.lastAbilityTime < 0.25 then CastDebug(source .. " " .. DStr(spellID) .. ": skipped - duplicate of the same press") return end
    State.lastAbilityTime = now
    State.lastAbilitySpell = SafeSpellID(spellID)
    State.lastTriggerSpellID = State.lastAbilitySpell
    CastDebug(source .. " " .. DStr(spellID) .. ": ANIMATING")
    TriggerSwing((State.lastAbilitySpell and RANGED_SPELLS[State.lastAbilitySpell]) and "RW"
        or (State.lastAbilitySpell and Scene.attack.SHIELD_SPELLS[State.lastAbilitySpell]) and "SHIELD" or nil)
end

-- Action bar presses (mouse clicks and keybinds both run through UseAction)
if hooksecurefunc and UseAction then
    pcall(hooksecurefunc, "UseAction", function(slot)
        CastDebug("UseAction hook fired, slot " .. tostring(slot))
        if not State.fpOn then CastDebug("press: NOT animating - FPS mode is off (toggle it on)") return end
        local ok, actionType, id = pcall(GetActionInfo, slot)
        if not ok or issecretvalue(actionType) then return end
        local spellID
        if actionType == "spell" then
            spellID = SafeSpellID(id)
        elseif actionType == "macro" and GetMacroSpell and SafeSpellID(id) then
            local okM, mid = pcall(GetMacroSpell, id)
            spellID = okM and SafeSpellID(mid) or nil
        elseif actionType ~= "item" then
            return  -- mounts, companions, equipment sets, etc.
        end
        -- Ignore presses that can't happen right now (not usable / still on cooldown)
        local okU, usable = pcall(C_ActionBar and C_ActionBar.IsUsableAction, slot)
        if okU and not issecretvalue(usable) and usable == false then CastDebug("press slot " .. tostring(slot) .. ": not usable") return end
        do
            local okC, cd = pcall(C_ActionBar and C_ActionBar.GetActionCooldown, slot)
            local start = okC and type(cd) == "table" and cd.startTime
            local duration = okC and type(cd) == "table" and cd.duration
            if type(start) == "number" and type(duration) == "number"
               and not issecretvalue(start) and not issecretvalue(duration)
               and start > 0 and duration > 1.6 then
                CastDebug("press slot " .. tostring(slot) .. ": on cooldown")
                return
            end
        end
        CastDebug("press " .. DStr(spellID) .. ": seen (animates only when it actually goes off)")
        if spellID and RANGED_SPELLS[spellID] then Scene.ranged.Out() end  -- swap to the ranged weapon now
    end)
end

local listener = CreateFrame("Frame")
-- Every event the addon listens to, by what it's for. (Registered with pcall: an event a client
-- doesn't have is simply skipped.)
Scene.EVENTS = {
    -- loading in
    "ADDON_LOADED", "PLAYER_ENTERING_WORLD",
    -- combat state, stealth, mounts
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UPDATE_STEALTH", "UNIT_AURA",
    "PLAYER_MOUNT_DISPLAY_CHANGED", "VEHICLE_UPDATE",
    -- gear, looks, spec
    "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
    "TRANSMOGRIFY_SUCCESS", "TRANSMOGRIFY_UPDATE", "TRANSMOGRIFY_CLOSE",
    -- casts and abilities (SENT fires the instant a cast is sent)
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
    -- blocks and parries (shield bash)
    "UNIT_COMBAT", "COMBAT_TEXT_UPDATE",
}
for _, ev in ipairs(Scene.EVENTS) do
    pcall(listener.RegisterEvent, listener, ev)
end

-- Casting model state machine. UNIT_SPELLCAST_START only fires for spells with a cast time.
local function CleanGUID(g) if type(g) == "string" and not issecretvalue(g) then return g end end
function Scene.CastEvent(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" and State.fpOn
        and ShouldAnimateForSpell(spellID) then
        local L = Scene.light
        local id = (type(spellID) == "number" and not issecretvalue(spellID)) and spellID or nil
        L.flash, L.flashColor = 1, id and L.SPELL_COLORS[id] or nil
    end
    local c = Scene.cast
    local pr = Scene.Profile()
    if State.fpOn and pr and (event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START")
        and (Scene.castKey or ""):match("^[^:]*") ~= pr.key then
        RefreshWeaponModels()  -- the casting model was last built for melee attacks: build it for spells
    end
    -- A new cast / channel starting while the last spell's release is still fresh waits until the
    -- release has shown for RELEASE_LINGER, then takes over (unless it ended in the meantime)
    local function Begin(state)
        local guid = CleanGUID(castGUID)
        local left = (c.state == "release") and (c.RELEASE_LINGER - (GetTime() - (c.releaseAt or 0))) or 0
        if left <= 0.02 then
            c.guid = guid
            return Scene.SetCastState(state)
        end
        local w = { state = state, guid = guid }
        c.waiting = w
        C_Timer.After(left, function()
            if c.waiting == w then
                c.guid = w.guid
                Scene.SetCastState(w.state)
            end
        end)
    end
    if (event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP") and c.waiting then
        c.waiting = nil   -- the waiting cast ended before it was shown (the release just carries on)
        if event == "UNIT_SPELLCAST_CHANNEL_STOP" then return end
    end
    if event == "UNIT_SPELLCAST_START" then
        if not (State.fpOn and pr and pr.cast) then return end
        if not ShouldAnimateForSpell(spellID) then return end  -- crafting, mounts, etc.
        Begin("casting")
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        if not (State.fpOn and pr and pr.channel) then return end
        if not ShouldAnimateForSpell(spellID) then return end
        Begin("channeling")
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if c.state == "channeling" then Scene.SetCastState("release") end  -- release, then the hands return
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if c.state == "channeling" then
            return  -- a channel's "succeeded" fires as it starts; its release comes when it stops
        elseif c.state == "casting" or c.state == "stopping" then
            -- ignore an instant spell going off mid-cast: it must be the cast we're showing
            local g = CleanGUID(castGUID)
            if c.guid and g and g ~= c.guid then return end
            Scene.SetCastState("release")
        else
            -- Instant cast (no cast-time "start"): skip straight to the release animation.
            -- Also restarts the release if instants are cast back to back.
            if not (State.fpOn and pr and pr.release) then return end
            if not ShouldAnimateForSpell(spellID) then return end  -- auto attack, mounts, crafting, etc.
            c.guid = CleanGUID(castGUID)
            Scene.SetCastState("release")
        end
    elseif not c.state or c.state == "release" or c.state == "attack" then
        return
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        Scene.SetCastState(nil)
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" then
        -- STOP also fires when a cast completes, so give "succeeded" a moment to arrive
        if c.state == "casting" then
            Scene.SetCastState("stopping")
            local tok = c.token
            C_Timer.After(c.STOP_GRACE, function()
                if c.token == tok and c.state == "stopping" then Scene.SetCastState(nil) end
            end)
        end
    end
end

listener:SetScript("OnEvent", function(self, event, ...)
    local arg1 = ...
    -- Track spells with a cast time, so their "succeeded" isn't mistaken for an instant ability
    if arg1 == "player" then
        if event == "UNIT_SPELLCAST_START" then
            Swing.casting, Swing.castGUID = true, CleanGUID(select(2, ...))
        elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
            if Swing.casting then Swing.casting, Swing.castStop = false, GetTime() end
        end
    end
    if event == "UNIT_COMBAT" or event == "COMBAT_TEXT_UPDATE" then
        -- Shield bash when you block (full or partial) or parry. Two sources, because either may
        -- be unavailable: UNIT_COMBAT (what hit you and how) and COMBAT_TEXT_UPDATE (what feeds
        -- the game's own "Block!" / "Parry!" popups).
        local a1, a2, a3 = ...
        local action, flag
        if event == "UNIT_COMBAT" then
            if a1 ~= "player" then return end
            action, flag = a2, a3
        else
            action = a1
        end
        local function show(v) return issecretvalue(v) and "<secret>" or tostring(v) end
        local function is(v)
            return type(v) == "string" and not issecretvalue(v)
                and (v == "BLOCK" or v == "PARRY" or v:find("BLOCK") ~= nil)
        end
        local hit = is(action) or is(flag)
        if Swing.debugCombat then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FPWeapons combat]|r " .. event .. ": " .. show(action)
                .. (flag ~= nil and (" / " .. show(flag)) or "") .. (hit and "  -> SHIELD BASH" or ""))
        end
        if hit and State.fpOn then
            -- both sources can report the same block: only bash once
            local now = GetTime()
            if now - (Swing.lastBlock or 0) > 0.2 then
                Swing.lastBlock = now
                TriggerSwing("SHIELD")
            end
        end
        return
    end
    if event:find("^UNIT_SPELLCAST_") and event ~= "UNIT_SPELLCAST_SENT" then
        Scene.CastEvent(event, ...)
        if event ~= "UNIT_SPELLCAST_SUCCEEDED" then return end  -- the others are only for the casting model
    end
    if Swing.debugCast and (event == "UNIT_SPELLCAST_SENT" or event == "UNIT_SPELLCAST_SUCCEEDED") and arg1 == "player" then
        CastDebug("event received: " .. event)
    end
    if event == "ADDON_LOADED" and arg1 == addonName then
        FPWeaponsDB = FPWeaponsDB or NewSettings()
        -- (settings saved by older versions may lack a hand's lists)
        for _, h in pairs(HANDS) do
            for _, list in ipairs({ "_overrides", "_transforms" }) do
                FPWeaponsDB[h.prefix .. list] = FPWeaponsDB[h.prefix .. list] or {}
            end
        end
        FPWeaponsDB.rw_type = FPWeaponsDB.rw_type or "NONE"
        FPWeaponsDB.showHand = nil   -- (weapon-only mode was removed: hands & arms are always shown)
        FPWeaponsRaceDB = FPWeaponsRaceDB or {}  -- account-wide per-race defaults (see .toc)
        Scene.ApplySheatheKey()

        for hand, h in pairs(HANDS) do
            local key = h.prefix .. "_type"
            if not ALLOWED_TYPES[hand][FPWeaponsDB[key] or ""] then
                FPWeaponsDB[key] = h.defType
            end
        end
        -- Cast / release poses whose defaults were changed: each new default replaces this
        -- character's saved copy once (so an older copy can't hide it); later edits are kept.
        -- { flag, pose kind, setup }
        for _, u in ipairs({
            { "casterWeaponPoseV1", "CAST", "STAFF" },     -- Caster Weapon cast
            { "mhCasterPoseV1", "CAST", "MH" },            -- Main Hand caster cast
            { "mhCasterPoseV1r", "RELEASE", "MH" },        -- Main Hand caster release
            { "bothCasterPoseV1r", "RELEASE", "BOTH" },    -- both hands caster release
        }) do
            if not FPWeaponsDB[u[1]] then  -- (cast / release poses)
                FPWeaponsDB[u[1]] = true
                local d = Scene.GENERIC_DEFAULTS[(u[3] == "BOTH") and u[2] or (u[2] .. "_" .. u[3])]
                FPWeaponsDB[Scene.PoseKey(u[2], u[3])] = {
                    scale = d.scale, facing = d.facing, pitch = d.pitch, roll = d.roll, posX = d.posX, posY = d.posY, posZ = d.posZ }
            end
        end
        -- Hand poses whose defaults were changed, the same way: { flag, hand, weapon type }
        for _, u in ipairs({
            { "ohCasterHandPoseV1", "OH", "MELEE_1H_CASTER" },   -- Caster Hand (off hand)
        }) do
            if not FPWeaponsDB[u[1]] then
                FPWeaponsDB[u[1]] = true
                local d = Scene.GENERIC_DEFAULTS[u[2]][u[3]]
                local list = HANDS[u[2]].prefix .. "_transforms"
                FPWeaponsDB[list] = FPWeaponsDB[list] or {}
                FPWeaponsDB[list][u[3] .. "_SCENE"] = {
                    scale = d.scale, facing = d.facing, pitch = d.pitch, roll = d.roll, posX = d.posX, posY = d.posY, posZ = d.posZ }
            end
        end
        -- Auto-detect: switch every hand to it once (pick a type by hand to override)
        if not FPWeaponsDB.autoTypesV1 then
            FPWeaponsDB.autoTypesV1 = true
            for _, h in pairs(HANDS) do FPWeaponsDB[h.prefix .. "_type"] = "AUTO" end
        end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" or (event == "PLAYER_EQUIPMENT_CHANGED" and SLOT_TO_HAND[arg1]) then
        -- weapon (or spec) changed: auto-detected types may differ now
        ResetSwingTimers()
        if State.fpOn then C_Timer.After(0.25, function() Scene.Probe(); RefreshWeaponModels() end) end
        if optionsFrame:IsShown() then C_Timer.After(0.3, Scene.RefreshPanel) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        State.sheathBlend = (UnitAffectingCombat("player") or FPWeaponsDB.autoSheath == false) and 0 or 1
        State.drawTimer = 0
        -- Right after loading in, the character model and item data may not be ready, so a hand/arm
        -- model built then can come out wrong. Rebuild it from scratch a little later (this is
        -- what re-selecting the weapon type was doing).
        for _, t in ipairs(Scene.LOGIN_REBUILDS) do
            C_Timer.After(t, function()
                if State.fpOn and Scene.Active() then RefreshWeaponModels(true) end
            end)
        end
            elseif event == "UNIT_SPELLCAST_SENT" then
        if arg1 == "player" then
            CastDebug("sent " .. DStr(select(4, ...)) .. ": waiting for it to go off")
            local sid = SafeSpellID(select(4, ...))
            if State.fpOn and sid and RANGED_SPELLS[sid] then Scene.ranged.Out() end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if arg1 == "player" then
            local castGUID, spellID = select(2, ...)
            -- A spell with a cast time finishing: not an instant ability, no attack animation
            local g = CleanGUID(castGUID)
            local fromCast
            if g and Swing.castGUID then
                fromCast = (g == Swing.castGUID)
            else
                fromCast = Swing.casting or (GetTime() - (Swing.castStop or -10) < 0.3)
            end
            if fromCast then
                Swing.castGUID = nil
                CastDebug("succeeded " .. DStr(spellID) .. ": cast-time spell, no attack animation")
                return
            end
            AbilityPressed(spellID, "succeeded")
        end
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        if event == "PLAYER_REGEN_ENABLED" and Scene.keyPending then Scene.ApplySheatheKey() end
        if event == "PLAYER_REGEN_DISABLED" then DrawWeapons(Sheath.DELAY) else State.drawTimer = math.max(State.drawTimer, Sheath.DELAY) end
        if State.fpOn then Scene.Reassert(Scene.REASSERT_COMBAT) end  -- (an engine-side reset at a combat change would stick)
    elseif event == "UPDATE_STEALTH" or (event == "UNIT_AURA" and arg1 == "player") then
        UpdateVisibility()
    elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" or event == "VEHICLE_UPDATE" then
        UpdateMountState()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        -- other gear: the arm wears your shirt, chest, bracers and gloves
        if State.fpOn then C_Timer.After(0.25, RefreshWeaponModels) end
    else
        if State.fpOn then
            if event == "TRANSMOGRIFY_SUCCESS" or event == "TRANSMOGRIFY_UPDATE" or event == "TRANSMOGRIFY_CLOSE" then
                -- new look on the same item: re-read it, then rebuild
                C_Timer.After(0.3, function() Scene.Probe(); RefreshWeaponModels(true, "transmog event") end)
            elseif event == "UNIT_INVENTORY_CHANGED" and arg1 == "player" then
                -- Fires when a weapon effect (sharpening stone, oil, imbue...) is applied or wears off.
                -- The game doesn't reliably say which effect is on the weapon, so rebuild the hands
                -- from your character outright (bursts of these events give a single rebuild).
                -- On retail this event also fires for many unrelated things, so only rebuild when a
                -- weapon, or whether it has an effect on it, actually changed.
                if not Scene.invRebuild then
                    Scene.invRebuild = true
                    C_Timer.After(0.4, function()
                        Scene.invRebuild = nil
                        local sig = Scene.WeaponSignature()
                        if sig ~= Scene.lastWeaponSig then
                            Scene.lastWeaponSig = sig
                            RefreshWeaponModels(true, "weapon or weapon effect changed")
                        end
                    end)
                end
            elseif event == "PLAYER_EQUIPMENT_CHANGED" then
                C_Timer.After(0.25, RefreshWeaponModels)
            end
        end
    end
end)
