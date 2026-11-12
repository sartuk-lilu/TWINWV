--[[
TWINWV - instant vocation switching for Dragon's Dogma 2 (REFramework Lua mod)

Not a Warfarer Vocation mod - this gives true multiclassing: instant
switching between all 9 base vocations, each with its own hotkey
(+ optional per-vocation modifier), its own set of Extra Skills, and its
own weapon/armor/ring loadout that's remembered automatically.

Optional Vocation Wheel: stand still, hold a key (default: Shift / L3),
point at a vocation with the mouse or right stick, release to switch.

Extra Skills Direct Cast (autorun-only, not shipped in the release package)
binds each of the 6 Extra Skill slots to its own hotkey that casts it
directly via app.HumanCustomSkillID, instead of holding Base+Modifier to
swap it into a normal slot first. See SKILL_CUSTOM_ID below for the skill
id -> engine field mapping this relies on.
--
liludev
https://www.nexusmods.com/dragonsdogma2/mods/1585
]]

local re = re
local sdk = sdk
local imgui = imgui
local json = json
local log = log

local hotkeys_ok, hotkeys = pcall(require, "Hotkeys/Hotkeys")
if not hotkeys_ok or not hotkeys then
    log.error("[TWINWV] Hotkeys/Hotkeys.lua module not found. It is required. Hotkey handling will be disabled.")
    hotkeys = nil
end

local Config

local UI_ACCENT_COLOR = 0xFFE0A030
local UI_MUTED_COLOR = 0xFF999999
local UI_DIVIDER_COLOR = 0xFF484848
local UI_DANGER_COLOR = 0xFF4D4DFF
local UI_COLUMN2_X = 340
local UI_BOX_WIDTH = 640
local UI_VOC_BOX_WIDTH = 300

local UI_SUPPORTS_GROUPS = type(imgui.begin_group) == "function" and type(imgui.end_group) == "function"

local UI_ITEM_WIDTH = 320
local itemWidthOk = true
local function pushItemWidth(width)
    if not itemWidthOk then return end
    local ok = pcall(imgui.push_item_width, width or UI_ITEM_WIDTH)
    if not ok then itemWidthOk = false end
end
local function popItemWidth()
    if not itemWidthOk then return end
    pcall(imgui.pop_item_width)
end

local function sectionHeader(text)
    imgui.text_colored(string.upper(text), UI_ACCENT_COLOR)
end

local function mutedText(text)
    imgui.text_colored(text, UI_MUTED_COLOR)
end

local dividerIdCounter = 0
local function drawDivider(width)
    local ok, pos = pcall(function() return imgui.get_cursor_screen_pos() end)
    if not ok or not pos then
        imgui.separator()
        return
    end
    local y = pos.y + 5
    imgui.draw_list_path_clear()
    imgui.draw_list_path_line_to({ pos.x, y })
    imgui.draw_list_path_line_to({ pos.x + (width or UI_BOX_WIDTH), y })
    imgui.draw_list_path_stroke(UI_DIVIDER_COLOR, false, 1)
    dividerIdCounter = dividerIdCounter + 1
    imgui.invisible_button("##twinwv-divider-" .. dividerIdCounter, { width or UI_BOX_WIDTH, 10 }, 0)
end

local function moveToColumn(x)
    local cursor = imgui.get_cursor_pos()
    imgui.set_cursor_pos({ x, cursor.y })
end

local function moveToSecondColumn()
    imgui.same_line()
    moveToColumn(UI_COLUMN2_X)
end

local function roundToStep(value, step, min, max)
    value = math.floor(value / step + 0.5) * step
    if value < min then value = min end
    if value > max then value = max end
    return value
end

local boxIdCounter = 0
local function boxBegin(nested, width)
    imgui.spacing()
    if not nested then imgui.unindent(20) end
    imgui.begin_rect()
    imgui.indent()
    boxIdCounter = boxIdCounter + 1
    local fontSizeOk, fontSize = pcall(function() return imgui.get_default_font_size() end)
    imgui.invisible_button("##twinwv-box-" .. boxIdCounter,
        { width or UI_BOX_WIDTH, (fontSizeOk and fontSize) or 14 }, 0)
end

local function boxEnd(nested)
    imgui.spacing()
    imgui.spacing()
    imgui.spacing()
    imgui.unindent()
    imgui.end_rect()
    if not nested then imgui.indent(20) end
    imgui.spacing()
end

local function pushBoxTheme()
    imgui.push_style_var(12, 4)
    imgui.push_style_var(21, 3)
    imgui.push_style_color(5, 0xFF464646)
    imgui.push_style_color(7, 0xFF343434)
    imgui.push_style_color(8, 0xFF484848)
    imgui.push_style_color(9, 0xFF565656)
    imgui.push_style_color(18, UI_ACCENT_COLOR)
    imgui.push_style_color(21, 0xFF3A3A3A)
    imgui.push_style_color(22, 0xFF505050)
    imgui.push_style_color(23, 0xFF606060)
    imgui.push_style_color(24, 0xFF343434)
    imgui.push_style_color(25, 0xFF484848)
    imgui.push_style_color(26, 0xFF565656)
end

local function popBoxTheme()
    imgui.pop_style_color(11)
    imgui.pop_style_var(2)
end

local function primaryButton(label)
    imgui.push_style_color(21, 0xFF8C5F31)
    imgui.push_style_color(22, 0xFFA8743B)
    imgui.push_style_color(23, 0xFF704C27)
    local pressed = imgui.button(label)
    imgui.pop_style_color(3)
    return pressed
end

local function dangerButton(label)
    imgui.push_style_color(21, 0xFF3A2E8B)
    imgui.push_style_color(22, 0xFF4A3AAB)
    imgui.push_style_color(23, 0xFF302675)
    local pressed = imgui.button(label)
    imgui.pop_style_color(3)
    return pressed
end

log.info("[TWINWV] loading...")

local TRANSLATION_FILE = "TWINWV_Translation.json"
local LANGUAGES = { "en", "ru", "ko", "fr", "zh" }
local LANGUAGE_LABELS = { "English", "Русский", "한국어", "Français", "中文" }

local TranslationData = json.load_file(TRANSLATION_FILE)
if not TranslationData then
    TranslationData = {}
    log.warn("[TWINWV] " .. TRANSLATION_FILE ..
        " not found - menu text and skill names will show as raw keys/ids until it's restored.")
end

local SKILL_NAME_BY_LANG = {}
for _, lang in ipairs(LANGUAGES) do
    local byId = {}
    local langData = TranslationData[lang]
    if langData and langData.skills then
        for _, entry in ipairs(langData.skills) do
            if entry and entry.id ~= nil then byId[entry.id] = entry.name end
        end
    end
    SKILL_NAME_BY_LANG[lang] = byId
end

-- Skill Creator (by Nickesponja): custom vocations on top of Trickster
-- (Mystic Knight etc.). Its modules live in REFramework's shared Lua state,
-- read through package.loaded (nothing is required - without Skill Creator
-- everything returns nil):
--   _NickCore/Properties: vocation (current custom vocation, "Trickster" for
--     the plain one), vocations[name].name, can_play_move(skill)
--   SkillCreator/UIHandler/Registry: customSkills[id][1|2].nameGuid ->
--     text[guid].uiName - its skill names
--   SkillCreator/SkillHandler: skillInfo.skillIDsToSkills[id] + Executor.play_move
--     - how it casts its own skills from its processCustomSkill hook
local SC = {}
function SC.mod(name)
    local m = package.loaded[name]
    return type(m) == "table" and m or nil
end
function SC.props() return SC.mod("_NickCore/Properties") end
-- current custom vocation (nil - no Skill Creator or plain Trickster)
function SC.vocation()
    local p = SC.props()
    local v = p and p.vocation
    if type(v) == "string" and v ~= "Trickster" then return v end
    return nil
end
function SC.vocationName()
    local v = SC.vocation()
    local p = v and SC.props()
    local d = p and p.vocations and p.vocations[v]
    return d and d.name or nil
end
-- Vocation and Skill Builder (VSB) keeps a registry of the same shape
-- (customSkills[id][lvl].nameGuid -> text[guid].uiName) in
-- VSB.game.skilldefs.registry - the table is replaced on every plan change,
-- so it's looked up every time.
function SC.registries()
    local list = {}
    local reg = SC.mod("SkillCreator/UIHandler/Registry")
    if reg then list[#list + 1] = reg end
    local vsb = SC.mod("VSB.game.skilldefs")
    if vsb and type(vsb.registry) == "table" then list[#list + 1] = vsb.registry end
    return list
end
function SC.skillName(id)
    for _, reg in ipairs(SC.registries()) do
        local info = reg.customSkills and reg.customSkills[id]
        if info and reg.text then
            -- the upgraded name wins over the base one
            for _, lvl in ipairs({ 2, 1 }) do
                local g = info[lvl] and info[lvl].nameGuid
                local t = g and reg.text[g]
                if t and type(t.uiName) == "string" and t.uiName ~= "" then return t.uiName, info.vocation end
            end
        end
    end
    return nil
end
function SC.skill(id)
    local sh = SC.mod("SkillCreator/SkillHandler")
    local map = sh and sh.skillInfo and sh.skillInfo.skillIDsToSkills
    return map and map[id] or nil
end
-- Quick Cast for a Skill Creator skill - the same way it casts from its
-- processCustomSkill hook (our usual requestCustomSkill bypasses that hook).
-- nil - not its case, use the normal Quick Cast; false - its skill, can't right now.
function SC.cast(id)
    local skill = SC.skill(id)
    local ex = SC.mod("SkillCreator/SkillHandler/Executor")
    if not skill or not ex or type(ex.play_move) ~= "function" then return nil end
    if skill.triggerNodes then return nil end -- these only play through their own nodes
    local p = SC.props()
    -- the same check as Skill Creator's is_right_weapon_job: a custom
    -- vocation's skill only on that vocation with its weapon, others by their
    -- vocation's weapon. Otherwise it's cast as a normal skill.
    if p and skill.params then
        local okW, right = pcall(function()
            if type(p.is_custom_vocation) == "function" and p.is_custom_vocation(p.vocation) then
                if skill.params.vocation ~= p.vocation then return false end
                return p.vocations[p.vocation].weaponJob == p.weaponJob
            end
            return p.weaponJob == skill.params.job
        end)
        if not okW or not right then return nil end
    end
    if p and type(p.can_play_move) == "function" then
        local okC, can = pcall(p.can_play_move, skill)
        if not okC or not can then return false end
    end
    local ok, err = pcall(ex.play_move, skill)
    if not ok then log.warn("[TWINWV] Skill Creator cast failed (id " .. tostring(id) .. "): " .. tostring(err)) end
    return ok
end

local function skillName(id)
    -- Skill Creator: its own skills (new ids, not in our dictionary) and the
    -- skills a custom vocation replaces - by its name
    local scName, scVoc = SC.skillName(id)
    if scName and (scVoc == nil or scVoc == SC.vocation() or not (SKILL_NAME_BY_LANG.en and SKILL_NAME_BY_LANG.en[id])) then
        return scName
    end
    local v = SKILL_NAME_BY_LANG[Config.Language] and SKILL_NAME_BY_LANG[Config.Language][id]
    if v ~= nil and v ~= "" then return v end
    v = SKILL_NAME_BY_LANG.en and SKILL_NAME_BY_LANG.en[id]
    if v ~= nil and v ~= "" then return v end
    return "Skill " .. tostring(id)
end

local VOCATIONS = {
    [1] = { id = 1, name = "Fighter",          image = "fighter" },
    [2] = { id = 2, name = "Archer",           image = "archer" },
    [3] = { id = 3, name = "Mage",             image = "mage" },
    [4] = { id = 4, name = "Thief",            image = "thief" },
    [5] = { id = 5, name = "Warrior",          image = "warrior" },
    [6] = { id = 6, name = "Sorcerer",         image = "sorcerer" },
    [7] = { id = 7, name = "Mystic Spearhand", image = "mystic_spearhand" },
    [8] = { id = 8, name = "Magick Archer",    image = "magick_archer" },
    [9] = { id = 9, name = "Trickster",        image = "trickster" },
}

local function vocationName(id)
    -- Trickster under a Skill Creator custom vocation - that vocation's name
    if id == 9 then
        local n = SC.vocationName()
        if n then return n end
    end
    local v = VOCATIONS[id]
    return v and v.name or ("Job " .. tostring(id))
end

local VOCATION_COLOR = {
    [1] = { color = 0xFF5852BA },
    [2] = { color = 0xFF00D1FE },
    [3] = { color = 0xFFDEB452 },
    [4] = { color = 0xFF499867 },
    [5] = { color = 0xFF27235F },
    [6] = { color = 0xFF8D503C },
    [7] = { color = 0xFF5852BA, secondary_color = 0xFFDEB452 },
    [8] = { color = 0xFFDEB452, secondary_color = 0xFF00D1FE },
    [9] = { color = 0xFF743C61 },
}

local function vocationHeader(jobId)
    local voc = VOCATIONS[jobId]
    local col = VOCATION_COLOR[jobId]
    if not voc then return end
    if not col then
        sectionHeader(voc.name)
        return
    end
    local spaceAt = string.find(voc.name, " ", 1, true)
    if col.secondary_color and spaceAt then
        local first = string.upper(string.sub(voc.name, 1, spaceAt - 1))
        local second = string.upper(string.sub(voc.name, spaceAt + 1))
        imgui.text_colored(first, col.color)
        imgui.same_line()
        imgui.text_colored(" " .. second, col.secondary_color)
    else
        imgui.text_colored(string.upper(voc.name), col.color)
    end
end

-- Dark Arisen DLC added 19 new skills (id 102-120). See TWINWV.lua (dev
-- file) for the full write-up and safety caveats around these ids - 8 of
-- them (108,109,110,111,114,115,116,120) point at internal enum fields we
-- previously confirmed to hang/crash BEFORE this DLC, and are intentionally
-- left out of SKILL_CUSTOM_ID below / kept in FORBIDDEN_CUSTOM_SKILL_FIELDS
-- until re-verified in-game.
local VOCATION_SKILLS = {
    [1] = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 102, 103 },
    [2] = { 0, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 104, 105 },
    [3] = { 0, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 106, 107 },
    [4] = { 0, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 101, 108, 109 },
    [5] = { 0, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 110, 111 },
    [6] = { 0, 24, 25, 26, 27, 62, 63, 64, 65, 66, 67, 68, 69, 112, 113 },
    [7] = { 0, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 114, 115 },
    [8] = { 0, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 116, 117 },
    [9] = { 0, 92, 93, 94, 95, 96, 97, 98, 99, 118, 119, 120 },
}

local NUM_BASE_SLOTS = 6
-- 6, not 5 - so the 3x2 grid in the UI doesn't leave an empty cell after the
-- fifth slot (same reasoning as ExtraDirectHotkeys). A sixth weapon loadout
-- per vocation is admittedly overkill - the slot exists purely for symmetry.
local NUM_WEAPON_SLOTS = 6

local CONFIG_FILE = "TWINWV.json"

local DEFAULT_VOCATION_HOTKEYS = {
    [1] = { Key = "F1" },
    [5] = { Key = "F1" },
    [2] = { Key = "F2" },
    [6] = { Key = "F2" },
    [3] = { Key = "F3" },
    [7] = { Key = "F3" },
    [4] = { Key = "F4" },
    [8] = { Key = "F4" },
    [9] = { Key = "F5" },
}

local HOTKEYS_DATA_FILE = "Hotkeys_data.json"
local DEFAULT_MODIFIER_ACTIONS = {
    ["TWINWV_Voc5_$"] = "LShift",
    ["TWINWV_Voc6_$"] = "LShift",
    ["TWINWV_Voc7_$"] = "LShift",
    ["TWINWV_Voc8_$"] = "LShift",
}

-- 20.10 fix (reported bug: "every time I restart the game Shift gets added
-- back to a couple of my vocation hotkeys, no matter how many times I remove
-- it"). The old gate was "this key isn't in modifier_actions yet" - but when
-- the player explicitly clears a modifier via right-click in the Hotkeys
-- widget itself, the widget appears to just DELETE the key from
-- Hotkeys_data.json rather than writing an explicit "no modifier" value - so
-- on the next launch the key looked "missing" again and we silently
-- re-seeded the default. Now we seed defaults EXACTLY ONCE for the lifetime
-- of the config - a flag in OUR OWN TWINWV.json (Config.General, survives
-- game restarts), not in the widget's volatile file - and never touch
-- Hotkeys_data.json again after the first successful seed. From then on
-- it's entirely up to the player, as it should be.
local function seedDefaultHotkeyModifiers()
    if Config.General.DefaultHotkeyModifiersSeeded then return end
    local ok, err = pcall(function()
        local data = json.load_file(HOTKEYS_DATA_FILE) or {}
        if not data.modifier_actions then data.modifier_actions = {} end
        local dirty = false
        for key, defaultModifier in pairs(DEFAULT_MODIFIER_ACTIONS) do
            if data.modifier_actions[key] == nil then
                data.modifier_actions[key] = defaultModifier
                dirty = true
            end
        end
        if dirty then
            json.dump_file(HOTKEYS_DATA_FILE, data)
        end
    end)
    if not ok then
        log.warn("[TWINWV] Could not seed default modifiers into " .. HOTKEYS_DATA_FILE .. ": " .. tostring(err))
        return
    end
    Config.General.DefaultHotkeyModifiersSeeded = true
    pcall(json.dump_file, CONFIG_FILE, Config)
end

local function defaultVocationEntry(jobId)
    local hk = DEFAULT_VOCATION_HOTKEYS[jobId] or { Key = "None" }
    return {
        Key = hk.Key,
        CycleOrder = 0, -- position in Prev/Next cycling (1-9), 0 = not included
        ExtraSkillsA = { 0, 0, 0, 0, 0, 0 },
        WeaponPreset = { items = {} },
        ArmorPreset = { items = {} },
        RingsPreset = { items = {} },
        -- Up to 6 additional weapon loadouts per vocation (control groups,
        -- like in StarCraft) - independent of the WeaponPreset above. See
        -- captureWeaponSlot/applyWeaponSlot.
        WeaponSlots = { { items = {} }, { items = {} }, { items = {} }, { items = {} }, { items = {} }, { items = {} } },
    }
end

local function defaultConfig()
    local cfg = {
        Language = "en",
        ExtraSkillHotkeys = {
            Base = "LControl",
            SubA = "LAlt",
        },
        ExtraDirectHotkeys = {
            Slot1 = "Alpha1", Slot2 = "Alpha2", Slot3 = "Alpha3",
            Slot4 = "Alpha4", Slot5 = "Alpha5", Slot6 = "Alpha6",
        },
        -- Vocation Wheel keys (see RadialWheel): no defaults - the player picks
        -- them, nothing is checked. HoldSec - how long to hold before it opens
        -- (0-0.5 s), 0 = right away. Wheel on the Dash key (Toggle mode) -> set a delay.
        WheelHotkeys = {
            Key = "None",
            Pad = "None",
            HoldSec = 0,
            -- which gamepad stick picks the vocation: "Right" / "Left" / "Either".
            -- Right by default: the wheel also opens on the move, and a still
            -- tilted left stick would pick by the running direction.
            Stick = "Right",
        },
        -- Wheel position per vocation (by jobId): 1-9 clockwise from the top,
        -- 0 = not on the wheel.
        WheelOrder = { 1, 2, 3, 4, 5, 6, 7, 8, 9 },
        -- Vocation Cycling (Prev/Next), independent from the wheel. Default
        -- R3 + LT / R3 + RT (R3 is the modifier, see Cycle.seedModifiers).
        CycleHotkeys = {
            Prev = "LT (L2)",
            Next = "RT (R2)",
            PrevKey = "None", -- keyboard
            NextKey = "None",
        },
        -- Weapon Slots ("control groups" for weapons, see
        -- captureWeaponSlot/applyWeaponSlot). Modifier held = remember the
        -- current weapon into that slot, released = switch to it. Everything
        -- defaults to "None" (like ExtraSkillsDirectCast) - the feature stays
        -- off until the player assigns keys and enables General.WeaponSlotsEnabled.
        WeaponSlotHotkeys = {
            Modifier = "None",
            Slot1 = "None", Slot2 = "None", Slot3 = "None",
            Slot4 = "None", Slot5 = "None", Slot6 = "None",
        },
        -- Ring Presets: temporary rings on top of each vocation's own
        -- (Dragonsbane for a dragon, etc.). 6 fixed slots (Used = added with
        -- "+"), each with a name, vocation checkboxes and rings (StorageId,
        -- like presets). Active = the slot that's on, 0 = off. Keys per slot.
        RingPresets = {
            Active = 0,
            Slots = {},
            Keys = {
                Slot1 = "None", Slot2 = "None", Slot3 = "None",
                Slot4 = "None", Slot5 = "None", Slot6 = "None",
            },
            Hud = {
                Mode = "Always", -- "Always" / "Active" (only the active one, while there is one) / "Hidden"
                Anchor = "CenterRight",
                X = 1, Y = 0,
                Scale = 100,
                Opacity = 80,
            },
        },
        General = {
            ExtraSkillsEnabled = true,
            AutoRememberWeapon = true,
            AutoRememberArmor = true,
            AutoRememberRings = true,
            RemoveJobRequirementsArmor = false,
            RemoveJobRequirementsWeapon = false,
            EnableVocationWheel = false,
            EnableVocationCycling = false,
            CycleConfirmSec = 0.3, -- pause after the last Next/Prev before switching (0.2-0.6)
            CycleModifiersSeeded = false, -- see Cycle.seedModifiers
            WheelSlowMotion = true,
            WheelSlowMotionSpeed = 0.3,
            RearmamentWeaponEffect = true,
            ExtraSkillsDirectCast = false,
            WeaponSlotsEnabled = false,
            DefaultHotkeyModifiersSeeded = false, -- see seedDefaultHotkeyModifiers - once true, we never touch Hotkeys_data.json again
        },
        -- Positions are in % of half the screen (see computeIconPos), so they
        -- land in the same place on 1080p, 1440p and 4K.
        Icon = {
            Enabled = true,
            Anchor = "TopLeft",
            X = 0, Y = 0,
            Scale = 50,
            AutoHide = false, -- fade out after a switch, see Cycle.fadeAlpha
            AutoHideSec = 1.5, -- after how many seconds (1-3)
        },
        -- Skill Bar (see SkillBar), off by default.
        SkillBar = {
            Enabled = false,
            Layout = "OneRow",
            Anchor = "BottomCenter",
            X = 0, Y = 20,
            Scale = 100,
            ShowKeys = true,
            GameKeys = true,
            Opacity = 80,
            NameMode = "Word",
            Keys = { "LMB", "RMB", "Q", "R", "E", "Space" },
            -- key that hides / shows the bar (e.g. dialogue subtitles under it); Hidden is saved
            ToggleKey = "None",
            Hidden = false,
        },
        -- Cycling strip (see Cycle.drawStrip) - its own position, so the
        -- single icon stays where it was when cycling is turned off.
        CycleStrip = {
            Enabled = true,
            Anchor = "BottomLeft",
            X = 25, Y = 5,
            Scale = 40,          -- highlighted icon
            InactiveScale = 70,  -- the others, % of the highlighted one
            AutoHide = false,    -- fade out after a switch, see Cycle.fadeAlpha
            AutoHideSec = 1.5,   -- after how many seconds (1-3)
        },
        Vocations = {},
    }
    for jobId = 1, 9 do cfg.Vocations[jobId] = defaultVocationEntry(jobId) end
    return cfg
end

Config = json.load_file(CONFIG_FILE)
if not Config then Config = defaultConfig() end

if Config.General and Config.General.AutoRememberJewelry ~= nil then
    Config.General.AutoRememberRings = Config.General.AutoRememberJewelry
    Config.General.AutoRememberJewelry = nil
end
if Config.Vocations then
    for jobId = 1, 9 do
        local voc = Config.Vocations[jobId]
        local oldJewelry = voc and voc.JewelryPreset
        if oldJewelry and oldJewelry.items then
            local rings, maskItems = {}, {}
            for _, it in ipairs(oldJewelry.items) do
                if it.SlotEnum == 8 then maskItems[#maskItems + 1] = it
                else rings[#rings + 1] = it end
            end
            voc.RingsPreset = { items = rings }
            if #maskItems > 0 then
                voc.ArmorPreset = voc.ArmorPreset or { items = {} }
                voc.ArmorPreset.items = voc.ArmorPreset.items or {}
                for _, it in ipairs(maskItems) do
                    voc.ArmorPreset.items[#voc.ArmorPreset.items + 1] = it
                end
            end
            voc.JewelryPreset = nil
        end
    end
end

-- 2.6: items are matched by StorageId only - entries saved before it
-- existed (no StorageId) could never match, so drop them. Presets refill on
-- the next re-equip, slots on the next save.
if Config.Vocations then
    local function dropLegacy(preset)
        if type(preset) ~= "table" or type(preset.items) ~= "table" then return end
        local kept = {}
        for _, it in ipairs(preset.items) do
            if type(it) == "table" and it.StorageId then kept[#kept + 1] = it end
        end
        preset.items = kept
    end
    for jobId = 1, 9 do
        local voc = Config.Vocations[jobId]
        if voc then
            dropLegacy(voc.WeaponPreset)
            dropLegacy(voc.ArmorPreset)
            dropLegacy(voc.RingsPreset)
            if type(voc.WeaponSlots) == "table" then
                for _, ws in pairs(voc.WeaponSlots) do dropLegacy(ws) end
            end
        end
    end
end

if Config.ExtraSkillHotkeys then Config.ExtraSkillHotkeys.SubB = nil end
if Config.Vocations then
    for jobId = 1, 9 do
        local voc = Config.Vocations[jobId]
        if voc then voc.ExtraSkillsB = nil end
    end
end

-- 2.5: the switch delay slider was removed (see SwitchGate.COOLDOWN_SEC).
if Config.General then Config.General.SwitchCooldownSec = nil end
-- 2.8: auto-unlock and Flash on Switch removed; icon offsets move from px
-- (taken as 1920x1080) to % of half the screen; the "Center" anchor is gone.
if Config.General then Config.General.UnlockTargetVocation = nil end
do
    local function migratePos(p)
        if type(p) ~= "table" then return end
        if p.X == nil and p.OffsetX ~= nil then
            local ox, oy = tonumber(p.OffsetX) or 0, tonumber(p.OffsetY) or 0
            p.X = math.floor(ox / 960 * 100 * 2 + 0.5) / 2
            p.Y = math.floor(oy / 540 * 100 * 2 + 0.5) / 2
        end
        if p.Anchor == "Center" then p.Anchor = "TopCenter"; p.Y = 7 end
        p.OffsetX, p.OffsetY = nil, nil
    end
    migratePos(Config.Icon)
    if Config.Icon then
        Config.Icon.FlashOnSwitch, Config.Icon.FlashScale, Config.Icon.FlashDurationFrames = nil, nil, nil
    end
end

local function mergeMissing(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = v
        elseif type(v) == "table" and type(dst[k]) == "table" then
            mergeMissing(dst[k], v)
        end
    end
end
-- Updating players already have the wheel on their keys (often Dash - the
-- old Shift / L3 defaults). Opening instantly would break their sprint, so
-- they get a delay once: 0.3 s on Dash, 0.15 s (as before) on other keys.
if type(Config.WheelHotkeys) == "table" and Config.WheelHotkeys.HoldSec == nil then
    local wk = Config.WheelHotkeys
    local onDash = wk.Key == nil or wk.Key == "LShift" or wk.Key == "RShift" or wk.Pad == nil or wk.Pad == "LStickPush"
    wk.HoldSec = onDash and 0.3 or 0.15
    if wk.Key == nil then wk.Key = "LShift" end
    if wk.Pad == nil then wk.Pad = "LStickPush" end
end
mergeMissing(Config, defaultConfig())
for jobId = 1, 9 do
    if not Config.Vocations[jobId] then Config.Vocations[jobId] = defaultVocationEntry(jobId) end
end
do
    local validLanguage = false
    for _, lang in ipairs(LANGUAGES) do if lang == Config.Language then validLanguage = true end end
    if not validLanguage then Config.Language = "en" end
end

-- fallback: text shown if the key is missing even in English (e.g. the
-- translation file wasn't updated together with the script).
local function tr(key, fallback)
    local cur = TranslationData[Config.Language]
    local v = cur and cur.ui and cur.ui[key]
    if v ~= nil and v ~= "" then return v end
    local en = TranslationData.en
    v = en and en.ui and en.ui[key]
    if v ~= nil and v ~= "" then return v end
    return fallback or key
end

local function saveConfig()
    pcall(json.dump_file, CONFIG_FILE, Config)
end
saveConfig()
re.on_config_save(function() saveConfig() end)

local CharacterManager, GUIManager

local function getCharacterManager()
    if not CharacterManager then CharacterManager = sdk.get_managed_singleton("app.CharacterManager") end
    return CharacterManager
end
local function getGUIManager()
    if not GUIManager then GUIManager = sdk.get_managed_singleton("app.GuiManager") end
    return GUIManager
end

local function getPlayer()
    local cm = getCharacterManager()
    if not cm then return nil end
    local ok, player = pcall(function() return cm:call("get_ManualPlayer()") end)
    if ok then return player end
    return nil
end

local function getHuman(player)
    if not player then return nil end
    local ok, human = pcall(function() return player:call("get_Human()") end)
    if ok then return human end
    return nil
end

local function isWeaponDrawn(player)
    if not player then return false end
    local ok, drawn = pcall(function()
        return player:call("get_WeaponDrawContext()"):get_field("IsDrawedWeapon")
    end)
    return ok and drawn == true
end

local function getJobContext(human)
    if not human then return nil end
    local ok, ctx = pcall(function() return human:call("get_JobContext()") end)
    if ok then return ctx end
    return nil
end

local function getSkillContext(human)
    if not human then return nil end
    local ok, ctx = pcall(function() return human:call("get_SkillContext()") end)
    if ok then return ctx end
    return nil
end

local function getCurrentJob()
    local ctx = getJobContext(getHuman(getPlayer()))
    if not ctx then return nil end
    local ok, job = pcall(function() return ctx:get_field("CurrentJob") end)
    if ok then return job end
    return nil
end

local function isGuiPaused()
    local gui = getGUIManager()
    if not gui then return false end
    local ok, paused = pcall(function() return gui:call("isPausedGUI()") end)
    if ok then return paused end
    return false
end

local WEAPON_EQUIP_SLOTS = { [0] = true, [1] = true }
local ARMOR_EQUIP_SLOTS = { [2] = true, [3] = true, [4] = true, [5] = true, [8] = true }
local RINGS_EQUIP_SLOTS = { [6] = true, [7] = true }
local function isWeaponEquipSlot(slot)
    return WEAPON_EQUIP_SLOTS[slot] == true
end

local ItemManager
local ItemManagerMethods

local function getItemManager()
    if not ItemManager then ItemManager = sdk.get_managed_singleton("app.ItemManager") end
    return ItemManager
end

-- Auto-remember used to be gated on isGuiPaused() (see installAutoRememberHook
-- below) so the hook wouldn't react to an ItemManager::applyEquipChange() call
-- made by the mod itself (vocation switch, Weapon Slots recall, strip*) -
-- otherwise the mod would keep overwriting its own presets and hitting disk
-- (json.dump_file) on every switch in real time/combat. Side effect: for
-- players whose game doesn't pause on opening the equipment menu, isGuiPaused()
-- is never true for them, so the hook never fired at all - even for a real,
-- manual re-equip in the actual menu.
--
-- The right signal isn't "game is paused", it's "this particular
-- applyEquipChange() call came from the mod, not the player":
-- applyEquipChangeGuardDepth counts the nesting of our OWN calls (see
-- commitEquipChange below, used by every apply/strip function instead of a
-- direct im:call(...)) - the hook simply ignores the call while the counter
-- is > 0. Any applyEquipChange() that happens OUTSIDE commitEquipChange
-- (counter == 0) is a real player-driven change in the game's own menu,
-- regardless of pause state.
local applyEquipChangeGuardDepth = 0
local function commitEquipChange(im)
    applyEquipChangeGuardDepth = applyEquipChangeGuardDepth + 1
    local ok, err = pcall(function() im:call("applyEquipChange()") end)
    applyEquipChangeGuardDepth = applyEquipChangeGuardDepth - 1
    if not ok then error(err, 0) end
end

local function resolveItemManagerMethods()
    if ItemManagerMethods then return true end
    local im = getItemManager()
    if not im then return false end
    local ok, methods = pcall(function()
        local td = im:get_type_definition()
        return {
            getStorageList = td:get_method("getStorageList"),
            setEquip = td:get_method(
                "setEquip(app.ItemDefine.StorageData, app.Character, app.EquipData.SlotEnum, System.Boolean, System.Boolean)"),
            removeEquip = td:get_method(
                "removeEquip(app.ItemDefine.StorageData, app.Character, System.Boolean, System.Boolean)"),
        }
    end)
    if not ok or not methods or not methods.getStorageList or not methods.setEquip
        or not methods.removeEquip then
        log.warn("[TWINWV] WeaponPresets: could not resolve ItemManager methods - " .. tostring(methods))
        return false
    end
    ItemManagerMethods = methods
    return true
end

local function getPlayerCharaId(player)
    local ok, id = pcall(function() return player:call("get_CharaID()") end)
    if ok then return id end
    return nil
end

local function listPlayerStorage(im, charaId)
    local ok, storage = pcall(function() return ItemManagerMethods.getStorageList:call(im, charaId, nil) end)
    if not ok then return nil end
    return storage
end

-- Presets identify an item by StorageData._StorageId - the id of that exact
-- copy. ItemId is shared by every copy of the same item, and copies can
-- have different stats and passives (DLC), so there is no "any copy with
-- the same name" fallback: if the exact copy isn't in the player's
-- inventory, it isn't equipped. The StorageId survives the storage chest and
-- pawn inventories, so the item is found again once it's back. ItemId is
-- kept only as a sanity check.
local PresetMatch = {}

function PresetMatch.storageIdOf(v)
    local ok, sid = pcall(function() return v._StorageId end)
    if ok and type(sid) == "number" and sid > 0 then return sid end
    return nil
end

function PresetMatch.record(v, slot)
    return { ItemId = v._ItemId, SlotEnum = slot, StorageId = PresetMatch.storageIdOf(v) }
end

-- The storage list can change while we walk it (the engine is still
-- re-equipping during a vocation switch, and our own removeEquip calls can
-- rebuild it), so get_Item(i) with a count taken earlier may return nil or a
-- different item. Take one snapshot of the list and work only with that.
function PresetMatch.snapshot(storage)
    local snap = {}
    local okCount, count = pcall(function() return storage:call("get_Count") end)
    if not okCount or not count then return snap end
    for i = 0, count - 1 do
        local ok, v = pcall(function() return storage:call("get_Item", i) end)
        if ok and v then snap[#snap + 1] = v end
    end
    return snap
end

-- Maps each wanted entry to its exact instance (by StorageId) in the
-- snapshot. Returns picks[n] (instance for items[n], or nil if it's not in
-- the inventory) and used[k] (snapshot positions that will be equipped).
function PresetMatch.resolve(snap, items)
    local used, picks, posBySid = {}, {}, {}
    for k, v in ipairs(snap) do
        local sid = PresetMatch.storageIdOf(v)
        if sid then posBySid[sid] = k end
    end
    for n, want in ipairs(items) do
        local k = want.StorageId and posBySid[want.StorageId]
        if k and not used[k] and snap[k]._ItemId == want.ItemId then
            used[k] = true
            picks[n] = snap[k]
        end
    end
    return picks, used
end

-- Unequips everything in the given slot group that isn't one of the
-- resolved instances (so a different copy of the same item doesn't stay on,
-- and leftover gear like a shield is removed), then equips the preset.
-- (count is unused now - kept so the call sites stay unchanged.)
-- requireAll (Weapon Slots): if any item of the set isn't in the inventory,
-- change nothing and return the number of missing items - otherwise the
-- current weapon would be unequipped with nothing to replace it, which
-- could crash the game. Returns -1 if the set is already worn exactly like
-- this (nothing to do), 0 after applying.
function PresetMatch.apply(im, player, charaId, storage, count, items, slotSet, label, jobId, requireAll)
    local snap = PresetMatch.snapshot(storage)
    local picks, used = PresetMatch.resolve(snap, items)
    if requireAll then
        local missing = 0
        for n = 1, #items do
            if not picks[n] then missing = missing + 1 end
        end
        if missing > 0 then return missing end
        local worn = true
        for n, want in ipairs(items) do
            local v = picks[n]
            if v._IsEquipped ~= true or v:call("get_EquipSlot()") ~= want.SlotEnum then worn = false; break end
        end
        if worn then
            for k, v in ipairs(snap) do
                if v._IsEquipped == true and slotSet[v:call("get_EquipSlot()")] and not used[k] then worn = false; break end
            end
        end
        if worn then return -1 end
    end
    for k, v in ipairs(snap) do
        if v and v._IsEquipped == true and slotSet[v:call("get_EquipSlot()")] and not used[k] then
            local masterData = im:call("getStorageMasterData(app.ItemDefine.StorageData)", v)
            local param = masterData:call("get_Param()")
            ItemManagerMethods.removeEquip:call(im, param, player, false, true)
        end
    end
    for n, want in ipairs(items) do
        local v = picks[n]
        if v then
            local masterData = im:call("getStorageMasterData(app.ItemDefine.StorageData)", v)
            local param = masterData:call("get_Param()")
            local canEquip = param:call("canEquip(app.CharacterID, System.Boolean)", charaId, false)
            if canEquip then
                ItemManagerMethods.setEquip:call(im, param, player, want.SlotEnum, true, true)
            else
                log.warn("[TWINWV] " .. label .. ": item " .. tostring(want.ItemId) ..
                    " for " .. vocationName(jobId) .. " failed canEquip() - skipped.")
            end
        end
    end
    return 0
end

-- Shared capture of the currently-equipped weapon group (both hands/shield)
-- into an items array, without writing to config - reused by both the
-- regular WeaponPreset (auto-remember) and the Weapon Slots below (see
-- captureWeaponSlot).
local function captureWeaponItems()
    if not resolveItemManagerMethods() then return nil, "ItemManager methods unavailable" end
    local im = getItemManager()
    local player = getPlayer()
    if not player then return nil, "no player" end
    local charaId = getPlayerCharaId(player)
    if not charaId then return nil, "no CharaID" end

    local ok, result = pcall(function()
        local storage = listPlayerStorage(im, charaId)
        if not storage then return nil end
        local count = storage:call("get_Count")
        local items = {}
        for i = 0, count - 1 do
            local v = storage:call("get_Item", i)
            if v and v._IsEquipped == true then
                local slot = v:call("get_EquipSlot()")
                if isWeaponEquipSlot(slot) then
                    items[#items + 1] = PresetMatch.record(v, slot)
                end
            end
        end
        return items
    end)
    if not ok or not result then return nil, result end
    return result
end

local function captureWeaponPresetForJob(jobId, quiet)
    local result, err = captureWeaponItems()
    if not result then
        if not quiet then
            log.warn("[TWINWV] captureWeaponPresetForJob(" .. tostring(jobId) .. ") failed: " .. tostring(err))
        end
        return false, err
    end
    if not Config.Vocations[jobId] then return false, "unknown jobId" end
    Config.Vocations[jobId].WeaponPreset = { items = result }
    saveConfig()
    if not quiet then
        log.info("[TWINWV] Weapon preset saved for " .. vocationName(jobId) .. ": " .. #result .. " item(s).")
    end
    return true
end

-- Same capture, but writes into one of the 6 additional slots
-- (Vocations[jobId].WeaponSlots[slot]) instead of the regular WeaponPreset.
-- The slots are a separate, parallel system (control groups) - this never
-- touches the regular auto-remember preset.
local function captureWeaponSlot(jobId, slot, quiet)
    local result, err = captureWeaponItems()
    if not result then
        if not quiet then
            log.warn("[TWINWV] captureWeaponSlot(" .. tostring(jobId) .. "," .. tostring(slot) .. ") failed: " .. tostring(err))
        end
        return false, err
    end
    local entry = Config.Vocations[jobId]
    if not entry then return false, "unknown jobId" end
    entry.WeaponSlots = entry.WeaponSlots or {}
    entry.WeaponSlots[slot] = { items = result }
    saveConfig()
    if not quiet then
        log.info("[TWINWV] Weapon slot " .. slot .. " saved for " .. vocationName(jobId) .. ": " .. #result .. " item(s).")
    end
    return true
end

local function stripEquippedWeapons()
    if not resolveItemManagerMethods() then return end
    local im = getItemManager()
    local player = getPlayer()
    if not player then return end
    local charaId = getPlayerCharaId(player)
    if not charaId then return end

    pcall(function()
        local storage = listPlayerStorage(im, charaId)
        if not storage then return end
        local count = storage:call("get_Count")
        for i = 0, count - 1 do
            local v = storage:call("get_Item", i)
            if v and v._IsEquipped == true and isWeaponEquipSlot(v:call("get_EquipSlot()")) then
                local masterData = im:call("getStorageMasterData(app.ItemDefine.StorageData)", v)
                local param = masterData:call("get_Param()")
                ItemManagerMethods.removeEquip:call(im, param, player, false, true)
            end
        end
        commitEquipChange(im)
    end)
end

-- Shared equip of an items list (see captureWeaponItems) via
-- ItemManager.setEquip, without switching vocations - reused by both the
-- regular WeaponPreset and the Weapon Slots. Returns ok, err (like pcall).
local function applyWeaponItemsForJob(items, jobId, requireAll)
    if not resolveItemManagerMethods() then return false, "ItemManager methods unavailable" end
    local im = getItemManager()
    local player = getPlayer()
    if not player then return false, "no player" end
    local charaId = getPlayerCharaId(player)
    if not charaId then return false, "no CharaID" end

    return pcall(function()
        local storage = listPlayerStorage(im, charaId)
        if not storage then return end
        local count = storage:call("get_Count")

        -- Never leave the character empty-handed: if none of the set's items
        -- are found or can be equipped on this vocation right now (canEquip -
        -- e.g. Skill Creator custom vocations rewrite item vocation flags and
        -- make Trickster's own weapons unusable), the current weapons stay.
        local usable = 0
        local picks = PresetMatch.resolve(PresetMatch.snapshot(storage), items)
        for n = 1, #items do
            local v = picks[n]
            if v then
                local okE, can = pcall(function()
                    local param = im:call("getStorageMasterData(app.ItemDefine.StorageData)", v):call("get_Param()")
                    return param:call("canEquip(app.CharacterID, System.Boolean)", charaId, false)
                end)
                if okE and can then usable = usable + 1 end
            end
        end
        if usable == 0 then
            log.info("[TWINWV] " .. vocationName(jobId) .. ": none of the saved weapons can be equipped now - weapons left as they are.")
            return 1
        end
        local res = PresetMatch.apply(im, player, charaId, storage, count, items, WEAPON_EQUIP_SLOTS, "WeaponPresets", jobId, requireAll)
        if res ~= 0 then return res end -- nothing changed (missing / already worn)
        commitEquipChange(im)
        return 0
    end)
end

local function applyWeaponPresetForJob(jobId)
    local entry = Config.Vocations[jobId]
    local preset = entry and entry.WeaponPreset
    if not preset or not preset.items or #preset.items == 0 then
        -- No preset: weapons are left alone (stripping them left the character
        -- empty-handed); the game itself swaps a weapon the vocation can't use.
        return
    end
    local ok, err = applyWeaponItemsForJob(preset.items, jobId)
    if not ok then
        log.warn("[TWINWV] applyWeaponPresetForJob(" .. tostring(jobId) .. ") threw: " .. tostring(err))
    end
end

-- Switches to one of the additional weapon slots. Unlike
-- applyWeaponPresetForJob (vocation switch), an empty/unsaved slot is NOT
-- "strip the weapon" - it's a no-op, so an unbound slot pressed by accident
-- mid-fight doesn't undress the player. After a successful recall, also
-- re-saves the regular WeaponPreset (if AutoRememberWeapon is on) - the
-- auto-remember hook itself never sees this: recall goes through
-- commitEquipChange (see above), which the hook deliberately ignores for any
-- applyEquipChange() call made from inside the mod's own code - without this
-- explicit resync, switching back to the vocation would revert to the old
-- state. Returns true if the slot was actually applied (used by the caller
-- to decide whether to queue the Rearmament Weapon Effect), false otherwise.
local function applyWeaponSlot(jobId, slot)
    local entry = Config.Vocations[jobId]
    local preset = entry and entry.WeaponSlots and entry.WeaponSlots[slot]
    if not preset or not preset.items or #preset.items == 0 then
        log.warn("[TWINWV] Weapon slot " .. tostring(slot) .. " is empty for " .. vocationName(jobId) .. " - recall ignored.")
        return false
    end
    local ok, err = applyWeaponItemsForJob(preset.items, jobId, true)
    if not ok then
        log.warn("[TWINWV] applyWeaponSlot(" .. tostring(jobId) .. "," .. tostring(slot) .. ") threw: " .. tostring(err))
        return false
    end
    if err == -1 then return false end -- already worn: no re-equip, no Rearmament Effect
    if type(err) == "number" and err > 0 then
        log.warn("[TWINWV] Weapon slot " .. tostring(slot) .. " for " .. vocationName(jobId) .. ": " .. err ..
            " item(s) not in the inventory (sold or stored?) - recall ignored. Save the slot again to replace it.")
        return false
    end
    if Config.General.AutoRememberWeapon then
        pcall(captureWeaponPresetForJob, jobId, true)
    end
    return true
end

local function captureArmorPresetForJob(jobId, quiet)
    if not resolveItemManagerMethods() then return false, "ItemManager methods unavailable" end
    local im = getItemManager()
    local player = getPlayer()
    if not player then return false, "no player" end
    local charaId = getPlayerCharaId(player)
    if not charaId then return false, "no CharaID" end

    local ok, result = pcall(function()
        local storage = listPlayerStorage(im, charaId)
        if not storage then return nil end
        local count = storage:call("get_Count")
        local items = {}
        for i = 0, count - 1 do
            local v = storage:call("get_Item", i)
            if v and v._IsEquipped == true then
                local slot = v:call("get_EquipSlot()")
                if ARMOR_EQUIP_SLOTS[slot] then
                    items[#items + 1] = PresetMatch.record(v, slot)
                end
            end
        end
        return items
    end)
    if not ok or not result then
        if not quiet then
            log.warn("[TWINWV] captureArmorPresetForJob(" .. tostring(jobId) .. ") failed: " .. tostring(result))
        end
        return false, result
    end
    if not Config.Vocations[jobId] then return false, "unknown jobId" end
    Config.Vocations[jobId].ArmorPreset = { items = result }
    saveConfig()
    if not quiet then
        log.info("[TWINWV] Armor preset saved for " .. vocationName(jobId) .. ": " .. #result .. " item(s).")
    end
    return true
end

local function stripEquippedArmor(suppressApply)
    if not resolveItemManagerMethods() then return end
    local im = getItemManager()
    local player = getPlayer()
    if not player then return end
    local charaId = getPlayerCharaId(player)
    if not charaId then return end

    pcall(function()
        local storage = listPlayerStorage(im, charaId)
        if not storage then return end
        local count = storage:call("get_Count")
        for i = 0, count - 1 do
            local v = storage:call("get_Item", i)
            if v and v._IsEquipped == true and ARMOR_EQUIP_SLOTS[v:call("get_EquipSlot()")] then
                local masterData = im:call("getStorageMasterData(app.ItemDefine.StorageData)", v)
                local param = masterData:call("get_Param()")
                ItemManagerMethods.removeEquip:call(im, param, player, false, true)
            end
        end
        if not suppressApply then commitEquipChange(im) end
    end)
end

local function applyArmorPresetForJob(jobId, suppressApply)
    if not resolveItemManagerMethods() then return end

    local entry = Config.Vocations[jobId]
    local preset = entry and entry.ArmorPreset
    if not preset or not preset.items or #preset.items == 0 then
        stripEquippedArmor(suppressApply)
        return
    end

    local im = getItemManager()
    local player = getPlayer()
    if not player then return end
    local charaId = getPlayerCharaId(player)
    if not charaId then return end

    local ok, err = pcall(function()
        local storage = listPlayerStorage(im, charaId)
        if not storage then return end
        local count = storage:call("get_Count")

        PresetMatch.apply(im, player, charaId, storage, count, preset.items, ARMOR_EQUIP_SLOTS, "ArmorPresets", jobId)
        if not suppressApply then commitEquipChange(im) end
    end)
    if not ok then
        log.warn("[TWINWV] applyArmorPresetForJob(" .. tostring(jobId) .. ") threw: " .. tostring(err))
    end
end

local function captureRingsPresetForJob(jobId, quiet)
    if not resolveItemManagerMethods() then return false, "ItemManager methods unavailable" end
    local im = getItemManager()
    local player = getPlayer()
    if not player then return false, "no player" end
    local charaId = getPlayerCharaId(player)
    if not charaId then return false, "no CharaID" end

    local ok, result = pcall(function()
        local storage = listPlayerStorage(im, charaId)
        if not storage then return nil end
        local count = storage:call("get_Count")
        local items = {}
        for i = 0, count - 1 do
            local v = storage:call("get_Item", i)
            if v and v._IsEquipped == true then
                local slot = v:call("get_EquipSlot()")
                if RINGS_EQUIP_SLOTS[slot] then
                    items[#items + 1] = PresetMatch.record(v, slot)
                end
            end
        end
        return items
    end)
    if not ok or not result then
        if not quiet then
            log.warn("[TWINWV] captureRingsPresetForJob(" .. tostring(jobId) .. ") failed: " .. tostring(result))
        end
        return false, result
    end
    if not Config.Vocations[jobId] then return false, "unknown jobId" end
    Config.Vocations[jobId].RingsPreset = { items = result }
    saveConfig()
    if not quiet then
        log.info("[TWINWV] Rings preset saved for " .. vocationName(jobId) .. ": " .. #result .. " item(s).")
    end
    return true
end

--------------------------------------------------------------------------------
-- Ring Presets: temporary rings on top of each vocation's remembered ones.
-- A slot is on and the vocation is checked in it -> switching to it equips
-- the slot's rings (a slot with one ring keeps the vocation's other ring).
-- If any of the slot's rings isn't in the inventory (sold / on a pawn), the
-- vocation's own rings are used. While a slot is on, ring auto-remember is
-- paused for its checked vocations - otherwise the dragon rings would
-- overwrite every vocation's memory. Changing rings by hand while a slot is
-- on isn't remembered anywhere; a slot only changes via "Remember current rings".
--------------------------------------------------------------------------------
local RingOv = { MAX = 6 }

-- Slots is always 6 consecutive entries: a table with holes would be saved
-- to JSON as an object with "3"-style keys and Slots[3] would be nil on load.
do
    local rp = Config.RingPresets
    local src = rp.Slots or {}
    local fixed = {}
    for i = 1, RingOv.MAX do
        local sl = src[i] or src[tostring(i)]
        if type(sl) ~= "table" then sl = { Used = false } end
        if sl.Jobs then
            local j = {}
            for k = 1, 9 do j[k] = (sl.Jobs[k] or sl.Jobs[tostring(k)]) == true end
            sl.Jobs = j
        end
        fixed[i] = sl
    end
    rp.Slots = fixed
    rp.Active = tonumber(rp.Active) or 0
    if rp.Active > 0 and not (fixed[rp.Active] and fixed[rp.Active].Used) then rp.Active = 0 end
end

function RingOv.slot(i)
    local rp = Config.RingPresets
    local sl = rp and rp.Slots and rp.Slots[i]
    if sl and sl.Used then return sl end
    return nil
end

-- the active slot if it's checked for jobId (even when empty - auto-remember
-- stays paused while the player puts on the rings to remember them)
function RingOv.covers(jobId)
    local a = Config.RingPresets and tonumber(Config.RingPresets.Active) or 0
    local sl = a > 0 and RingOv.slot(a) or nil
    if sl and sl.Jobs and sl.Jobs[jobId] then return sl end
    return nil
end

function RingOv.itemsFor(jobId)
    local sl = RingOv.covers(jobId)
    if sl and sl.items and #sl.items > 0 then return sl.items end
    return nil
end

-- the slot's rings + the vocation's rings in ring slots the preset doesn't use
function RingOv.merge(ov, voc)
    local out, usedSlot, usedId = {}, {}, {}
    for _, it in ipairs(ov) do
        out[#out + 1] = it
        usedSlot[it.SlotEnum] = true
        if it.StorageId then usedId[tostring(it.StorageId)] = true end
    end
    for _, it in ipairs(voc or {}) do
        if not usedSlot[it.SlotEnum] and not (it.StorageId and usedId[tostring(it.StorageId)]) then
            out[#out + 1] = it
        end
    end
    return out
end

function RingOv.readCurrent()
    if not resolveItemManagerMethods() then return nil end
    local im = getItemManager()
    local charaId = getPlayerCharaId(getPlayer())
    if not charaId then return nil end
    local ok, items = pcall(function()
        local storage = listPlayerStorage(im, charaId)
        if not storage then return nil end
        local list = {}
        for _, v in ipairs(PresetMatch.snapshot(storage)) do
            if v and v._IsEquipped == true then
                local slot = v:call("get_EquipSlot()")
                if RINGS_EQUIP_SLOTS[slot] then list[#list + 1] = PresetMatch.record(v, slot) end
            end
        end
        return list
    end)
    return ok and items or nil
end

-- Ring name for the menu, by ItemId, in the game's current language. Item
-- names can be "<REF key>" links to a message - expanded via via.gui.message
-- (as in Transmogify by yowave), "<EQABI ...>" tags removed. Cached per id,
-- refreshed every 30 s.
RingOv.names = { at = 0, byId = {}, logged = {} }
function RingOv.expandRefs(text, depth)
    if depth > 8 then return nil end
    local out, pos = {}, 1
    while true do
        local st = string.find(text, "<REF ", pos, true)
        local cl = st and string.find(text, ">", st + 5, true)
        if not cl then break end
        local ok, ref = pcall(function()
            local mt = sdk.find_type_definition("via.gui.message")
            local guid = mt:get_method("getGuidByName(System.String)"):call(nil, string.sub(text, st + 5, cl - 1))
            if not mt:get_method("isExistGuid(System.Guid)"):call(nil, guid) then return nil end
            return mt:get_method("get(System.Guid)"):call(nil, guid)
        end)
        if not ok or type(ref) ~= "string" then return nil end
        ref = RingOv.expandRefs(ref, depth + 1)
        if not ref then return nil end
        out[#out + 1] = string.sub(text, pos, st - 1)
        out[#out + 1] = ref
        pos = cl + 1
    end
    out[#out + 1] = string.sub(text, pos)
    return table.concat(out)
end
function RingOv.itemName(itemId)
    if not itemId then return nil end
    local c = RingOv.names
    local now = os.clock()
    if now - c.at > 30 then c.at, c.byId = now, {} end
    local cached = c.byId[itemId]
    if cached ~= nil then return cached or nil end
    local raw
    pcall(function()
        local data = getItemManager():call("getItemData(System.Int32)", itemId)
        raw = data and data:call("get_Name()")
    end)
    local name
    if type(raw) == "string" and raw ~= "" then
        name = RingOv.expandRefs(raw, 0) or raw
        name = name:gsub("<[^>]*>", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" or name == "Invalid" then name = nil end
    end
    if not name and not c.logged[itemId] then
        c.logged[itemId] = true
        log.info("[TWINWV] Ring Presets: no name for item " .. tostring(itemId) .. " (raw=" .. tostring(raw) .. ")")
    end
    c.byId[itemId] = name or false
    return name
end

function RingOv.capture(i)
    local sl = RingOv.slot(i)
    if not sl then return false end
    local items = RingOv.readCurrent()
    if not items then return false end
    sl.items = items
    saveConfig()
    return true
end

-- "+": first free slot, all vocations checked
function RingOv.add()
    local rp = Config.RingPresets
    rp.Slots = rp.Slots or {}
    for i = 1, RingOv.MAX do
        local sl = rp.Slots[i]
        if not (sl and sl.Used) then
            rp.Slots[i] = { Used = true, Name = "Rings " .. i,
                Jobs = { true, true, true, true, true, true, true, true, true }, items = {} }
            return i
        end
    end
    return nil
end

function RingOv.remove(i)
    local rp = Config.RingPresets
    if rp.Slots and rp.Slots[i] then rp.Slots[i] = { Used = false } end
    if tonumber(rp.Active) == i then rp.Active = 0; RingOv.applyNow() end
end

-- re-equip rings on the current vocation right away (on / off / other slot)
function RingOv.applyNow()
    local job = getCurrentJob()
    if not job or not VOCATIONS[job] then return end
    if RingOv.inFlight and RingOv.inFlight() then return end -- the vocation switch will apply it
    PresetMatch.defer(function() RingOv.applyRings(job) end)
end

function RingOv.toggle(i)
    if not RingOv.slot(i) then return end
    local rp = Config.RingPresets
    rp.Active = (tonumber(rp.Active) == i) and 0 or i
    saveConfig()
    RingOv.applyNow()
end


local function stripEquippedRings(suppressApply)
    if not resolveItemManagerMethods() then return end
    local im = getItemManager()
    local player = getPlayer()
    if not player then return end
    local charaId = getPlayerCharaId(player)
    if not charaId then return end

    pcall(function()
        local storage = listPlayerStorage(im, charaId)
        if not storage then return end
        local count = storage:call("get_Count")
        for i = 0, count - 1 do
            local v = storage:call("get_Item", i)
            if v and v._IsEquipped == true and RINGS_EQUIP_SLOTS[v:call("get_EquipSlot()")] then
                local masterData = im:call("getStorageMasterData(app.ItemDefine.StorageData)", v)
                local param = masterData:call("get_Param()")
                ItemManagerMethods.removeEquip:call(im, param, player, false, true)
            end
        end
        if not suppressApply then commitEquipChange(im) end
    end)
end

local function applyRingsPresetForJob(jobId, suppressApply)
    if not resolveItemManagerMethods() then return end

    local entry = Config.Vocations[jobId]
    local preset = entry and entry.RingsPreset

    -- Ring Presets: an active slot for this vocation -> the slot's rings
    -- (+ the vocation's ring in a free ring slot) if all of the slot's rings
    -- are in the inventory; otherwise the vocation's own rings below.
    local ovItems = RingOv.itemsFor(jobId)
    if ovItems then
        local done = false
        local ok, err = pcall(function()
            local im = getItemManager()
            local player = getPlayer()
            local charaId = player and getPlayerCharaId(player)
            if not charaId then return end
            local storage = listPlayerStorage(im, charaId)
            if not storage then return end
            local picks = PresetMatch.resolve(PresetMatch.snapshot(storage), ovItems)
            for n = 1, #ovItems do
                if not picks[n] then return end
            end
            local merged = RingOv.merge(ovItems, preset and preset.items)
            PresetMatch.apply(im, player, charaId, storage, storage:call("get_Count"), merged, RINGS_EQUIP_SLOTS, "RingPresets", jobId)
            if not suppressApply then commitEquipChange(im) end
            done = true
        end)
        if not ok then log.warn("[TWINWV] Ring preset apply failed: " .. tostring(err)) end
        if done then return end
    end
    -- with ring auto-remember off the mod doesn't touch the vocation's rings
    if not Config.General.AutoRememberRings then return end

    if not preset or not preset.items or #preset.items == 0 then
        stripEquippedRings(suppressApply)
        return
    end

    local im = getItemManager()
    local player = getPlayer()
    if not player then return end
    local charaId = getPlayerCharaId(player)
    if not charaId then return end

    local ok, err = pcall(function()
        local storage = listPlayerStorage(im, charaId)
        if not storage then return end
        local count = storage:call("get_Count")

        PresetMatch.apply(im, player, charaId, storage, count, preset.items, RINGS_EQUIP_SLOTS, "RingsPresets", jobId)
        if not suppressApply then commitEquipChange(im) end
    end)
    if not ok then
        log.warn("[TWINWV] applyRingsPresetForJob(" .. tostring(jobId) .. ") threw: " .. tostring(err))
    end
end
RingOv.applyRings = applyRingsPresetForJob

-- Hooks ItemManager::applyEquipChange and captures the current loadout into
-- the active vocation's preset whenever the player re-equips something
-- through the game's own equipment menu, so presets stay in sync without an
-- explicit save action. Uses applyEquipChangeGuardDepth (see
-- commitEquipChange above) rather than isGuiPaused(): we only ignore calls
-- that happen from inside the mod's own code (vocation switch, Weapon Slots
-- recall, strip*), not every call outside pause - so this reacts to a real
-- re-equip in the menu regardless of whether the player's game pauses on
-- menu-open.
--
-- 15.10 fix: applyEquipChangeGuardDepth alone isn't enough - it only covers
-- applyEquipChange calls made by OUR OWN code (via commitEquipChange), not
-- calls the ENGINE itself makes while a vocation switch is still in flight
-- (e.g. unequipping a piece incompatible with the new job). Such a call used
-- to hit this hook unguarded and overwrite the destination job's preset with
-- transient, not-yet-settled equip state - the reported "sorc legs equipped
-- on switching to mage" bug (and the same for shared rings). Armor/Rings now
-- apply on the same deferred, confirmed-job schedule as Weapon (see
-- pendingArmorJobId/pendingRingsJobId below), and isVocationSwitchInFlight
-- (forward-declared here) makes this hook ignore applyEquipChange entirely
-- while any of the three is still pending, regardless of who called it.
local isVocationSwitchInFlight -- forward declaration, defined near PENDING_ARMOR_* below
local applyEquipChangeHookInstalled = false
local function installAutoRememberHook()
    if applyEquipChangeHookInstalled then return end
    applyEquipChangeHookInstalled = true
    local ok = pcall(function()
        local method = sdk.find_type_definition("app.ItemManager"):get_method("applyEquipChange")
        sdk.hook(method, nil, function(retval)
            if applyEquipChangeGuardDepth > 0 then return retval end
            if isVocationSwitchInFlight and isVocationSwitchInFlight() then return retval end
            local job = getCurrentJob()
            if job and VOCATIONS[job] then
                if Config.General.AutoRememberWeapon then
                    pcall(captureWeaponPresetForJob, job, true)
                end
                if Config.General.AutoRememberArmor then
                    pcall(captureArmorPresetForJob, job, true)
                end
                if Config.General.AutoRememberRings and not RingOv.covers(job) then
                    pcall(captureRingsPresetForJob, job, true)
                end
            end
            return retval
        end)
    end)
    if not ok then
        log.warn("[TWINWV] Could not install auto-remember hook on ItemManager::applyEquipChange.")
    end
end

local ANY_JOB_SENTINEL = 65535
-- Toggles item._Job to ANY_JOB_SENTINEL in place, globally, on the live
-- ItemDataDict entries - not per-slot. Original values are cached per item
-- id so they can be restored exactly when the toggle is turned back off.
local jobRequirementOriginals = { armor = {}, weapon = {} }

local function patchItemJobRequirements(typeName, cacheKey, enable)
    local im = getItemManager()
    if not im then return end
    local ok, err = pcall(function()
        local dict = im:get_field("_ItemDataDict")
        if not dict then return end
        local entries = dict:get_field("_entries")
        if not entries then return end
        local cache = jobRequirementOriginals[cacheKey]

        if enable then
            for _, entry in pairs(entries) do
                local item = entry.value
                if item ~= nil and item:get_type_definition():get_full_name() == typeName and item._Job ~= ANY_JOB_SENTINEL then
                    local id = item:call("get_Id()")
                    if cache[id] == nil then cache[id] = item._Job end
                    item._Job = ANY_JOB_SENTINEL
                end
            end
        else
            for _, entry in pairs(entries) do
                local item = entry.value
                if item ~= nil and item:get_type_definition():get_full_name() == typeName then
                    local id = item:call("get_Id()")
                    if cache[id] ~= nil then
                        item._Job = cache[id]
                        cache[id] = nil
                    end
                end
            end
        end
    end)
    if not ok then
        log.warn("[TWINWV] patchItemJobRequirements(" .. typeName .. ") threw: " .. tostring(err))
    end
end

local lastArmorJobReqState, lastWeaponJobReqState = nil, nil
local function tickJobRequirementToggles()
    if Config.General.RemoveJobRequirementsArmor ~= lastArmorJobReqState then
        patchItemJobRequirements("app.ItemArmorParam", "armor", Config.General.RemoveJobRequirementsArmor)
        lastArmorJobReqState = Config.General.RemoveJobRequirementsArmor
    end
    if Config.General.RemoveJobRequirementsWeapon ~= lastWeaponJobReqState then
        patchItemJobRequirements("app.ItemWeaponParam", "weapon", Config.General.RemoveJobRequirementsWeapon)
        lastWeaponJobReqState = Config.General.RemoveJobRequirementsWeapon
    end
end

-- Filters the Extra Skills dropdown to skills already learned in-game.
-- SkillContext.EnabledCustomSkills._items[i].CustomSkillID is the same
-- field used for this purpose by other vocation-skill mods.
local function getUnlockedSkillIds()
    local skillCtx = getSkillContext(getHuman(getPlayer()))
    if not skillCtx then return nil end
    local ok, result = pcall(function()
        local items = skillCtx:get_field("EnabledCustomSkills"):get_field("_items")
        local set = {}
        for _, entry in pairs(items) do
            -- the list also holds skills NOT learned yet (Level 0 - e.g. DLC
            -- skills; Skill Creator "forgets" a skill the same way). The game
            -- shows those greyed out without a name - not offered.
            if entry and entry.CustomSkillID then
                local okL, lvl = pcall(function() return entry.Level end)
                if not okL or lvl == nil or (tonumber(lvl) or 0) > 0 then set[entry.CustomSkillID] = true end
            end
        end
        return set
    end)
    if ok then return result end
    return nil
end

-- Returns ordered labels/ids arrays (not a {[id]=name} map) so the combo's
-- display order always matches VOCATION_SKILLS - a sparse id-keyed table
-- doesn't guarantee iteration order in Lua, which showed up as a real bug:
-- Fighter's ids happen to be contiguous from 1, so Lua stores them in the
-- table's array part, and "None" (id 0) alone in the hash part - the hash
-- part is enumerated after the array part, so "None" landed last just for
-- that one vocation.
-- 20.10: support for skills added by third-party SkillCreator-based mods
-- (e.g. Dullahan) - swap-based Extra Skills only, no Quick Cast (those mods
-- play skills through their own animation-node system, not through
-- app.HumanCustomSkillID/requestCustomSkill, so there's no stable field name
-- to cast them by in the first place). skillCtx:setSkill() itself accepts
-- any numeric id regardless of where it came from, so the only real gap was
-- that the candidate list below came purely from our own static
-- VOCATION_SKILLS table. Those mods hand out arbitrary ids per pack, so
-- hardcoding them isn't viable - instead we ask the game itself: once the
-- player has unlocked such a skill, it's already in `unlocked`
-- (EnabledCustomSkills, shared across all jobs). We just cross-check that
-- this particular id is registered for THIS job via
-- GuiManager.CustomSkillJobDefineDictionary[jobId][skillId] - the same
-- dictionary SkillCreator itself uses to register new skills per job.
local function skillOptionsForJob(jobId)
    local allIds = VOCATION_SKILLS[jobId] or { 0 }
    local unlocked = getUnlockedSkillIds()
    local filtered = unlocked ~= nil

    local function isCustomSkillRegisteredForJob(jId, skillId)
        local ok, result = pcall(function()
            local gui = getGUIManager()
            if not gui then return false end
            -- ContainsKey first: indexing a missing key throws inside the game
            -- and REFramework logs every one of those as an error.
            local jobDict = gui.CustomSkillJobDefineDictionary
            if not jobDict or not jobDict:call("ContainsKey", jId) then return false end
            local forJob = jobDict:call("get_Item", jId)
            return forJob ~= nil and forJob:call("ContainsKey", skillId) == true
        end)
        return ok and result or false
    end

    local function build(useFilter)
        local ids, labels = {}, {}
        local seen = {}
        for _, sid in ipairs(allIds) do
            if sid == 0 or not useFilter or unlocked[sid] then
                ids[#ids + 1] = sid
                labels[#labels + 1] = skillName(sid)
                seen[sid] = true
            end
        end
        if useFilter and unlocked then
            local discovered = {}
            for sid in pairs(unlocked) do
                if not seen[sid] and sid ~= 0 and isCustomSkillRegisteredForJob(jobId, sid) then
                    discovered[#discovered + 1] = sid
                end
            end
            table.sort(discovered)
            for _, sid in ipairs(discovered) do
                ids[#ids + 1] = sid
                labels[#labels + 1] = skillName(sid)
                seen[sid] = true
            end
        end
        return ids, labels
    end

    local ids, labels = build(filtered)
    if #ids <= 1 then
        filtered = false
        ids, labels = build(false)
    end
    return labels, ids, filtered
end

-- The skill lists are built once per opening of the REFramework menu
-- (and again on a language change), not every frame - building them for 9
-- vocations every frame cost ~30 FPS while the section was open. A skill
-- learned while the menu is open shows up after reopening it.
local SkillOptionsCache = { byJob = {}, lastUiAt = -1 }

local function extraSkillOptionsForJob(jobId)
    local c = SkillOptionsCache.byJob[jobId]
    if not c then
        local labels, ids, filtered = skillOptionsForJob(jobId)
        c = { labels = labels, ids = ids, filtered = filtered }
        SkillOptionsCache.byJob[jobId] = c
    end
    return c.labels, c.ids, c.filtered
end

local function getCurrentEquippedSkills(jobId)
    local skillCtx = getSkillContext(getHuman(getPlayer()))
    if not skillCtx then return nil end
    local skills = {}
    for i = 1, NUM_BASE_SLOTS do
        local ok, id = pcall(function() return skillCtx:getSkillID(jobId, i - 1) end)
        skills[i] = ok and id or 0
    end
    return skills
end

-- (hint from the Extra Skill Slots mod) HumanSkillContext.setSkill only
-- writes a skill the game itself checks as learned, and silently skipped some
-- DLC skills - the Extra Skills swap left an empty/old slot. Write straight
-- into the vocation's equip list instead: getEquipList(job):setSkill(id, slot)
-- - a plain array write, as Extra Skill Slots and True Warfarer do. Falls back
-- to the old call if that fails.
local function writeSkillSlot(skillCtx, jobId, id, slotIdx)
    local ok = pcall(function()
        local equip = skillCtx:call("getEquipList(app.Character.JobEnum)", jobId)
        equip:call("setSkill(app.HumanCustomSkillID, app.HumanSkillContext.SkillSlot)", id, slotIdx)
    end)
    if not ok then
        ok = pcall(function() skillCtx:setSkill(jobId, id, slotIdx) end)
    end
    return ok
end

local function applySkillSet(jobId, skills)
    local allEmpty = true
    for i = 1, NUM_BASE_SLOTS do
        if (skills[i] or 0) ~= 0 then allEmpty = false break end
    end
    if allEmpty then
        log.warn("[TWINWV] applySkillSet: the resulting skill set for " .. vocationName(jobId) ..
            " is completely empty (all 6 slots = no skill) - skipped, to avoid the crash from removing every skill. Set at least one slot.")
        return
    end

    local skillCtx = getSkillContext(getHuman(getPlayer()))
    if not skillCtx then return end
    for i = 1, NUM_BASE_SLOTS do
        writeSkillSlot(skillCtx, jobId, skills[i] or 0, i - 1)
    end
    local gui = getGUIManager()
    if gui then pcall(function() gui:call("setupKeyGuideCustomSkill()") end) end
end

local extraSkillsState = "none"
local extraSkillsSnapshot = nil

local PENDING_WEAPON_MAX_FRAMES = 60
local PENDING_WEAPON_CONFIRM_FRAMES = 5
-- Transmogify compatibility: its removeEquip post-hook (installed even when
-- Transmogify is disabled in its menu) sheathes and destroys the weapons in
-- hand. Run from on_frame that caused the "out of body" / invisible Arisen bug,
-- so all actual equip changes (setEquip/removeEquip) run in
-- LateUpdateBehavior. The tick* functions in on_frame only wait for the
-- vocation change to be confirmed and queue the call here.
PresetMatch.lateQueue = {}
function PresetMatch.defer(fn)
    PresetMatch.lateQueue[#PresetMatch.lateQueue + 1] = fn
end

-- Weapon was drawn before the switch but sheathed after it (Transmogify):
-- draw it again once Transmogify has rebuilt the weapons. wantDraw is read
-- before requestChangeJob / slot recall, redrawFrames is armed after our
-- equip change and counted in LateUpdateBehavior.
PresetMatch.wantDraw = false
PresetMatch.redrawFrames = nil
PresetMatch.redrawStage = nil -- nil / "request" / "done"
PresetMatch.REDRAW_MIN_FRAMES = 2
PresetMatch.REDRAW_MAX_FRAMES = 90
function PresetMatch.isDrawn()
    local player = getPlayer()
    if not player then return false end
    local ok, d = pcall(function() return player:call("get_IsDrawedWeapon()") end)
    if ok and d ~= nil then return d == true end
    return isWeaponDrawn(player)
end
-- High Spellhold (Mage/Sorcerer) used to forget its stored spell after a
-- vocation switch. The stored spell lives in one shared
-- Job06ActionCtrl.<JobMagicUserActionContext>: StockedSpellJob03 (Mage) and
-- StockedSpellJob06 (Sorcerer) hold the skill id, 0 = empty (found via
-- Swiftcast by BeerShigachi). Writing the id back is enough. When leaving
-- Mage/Sorcerer we save that vocation's own field (0 too - spell was used),
-- and write it back once the switch back is confirmed. Session memory only.
local SpellStock = {
    FIELD = { [3] = "StockedSpellJob03", [6] = "StockedSpellJob06" },
    saved = {},
    pendingJob = nil, confirmed = 0, waited = 0,
    CONFIRM_FRAMES = 10, MAX_FRAMES = 120,
}
function SpellStock.ctx()
    local human = getHuman(getPlayer())
    if not human then return nil end
    local ok, ctx = pcall(function()
        local ctrl = human:call("get_Job06ActionCtrl()")
        return ctrl and ctrl["<JobMagicUserActionContext>k__BackingField"]
    end)
    return ok and ctx or nil
end
function SpellStock.capture(fromJob)
    local f = SpellStock.FIELD[fromJob]
    if not f then return end
    local ctx = SpellStock.ctx()
    if not ctx then return end
    local ok, v = pcall(function() return ctx[f] end)
    if ok and type(v) == "number" then SpellStock.saved[fromJob] = v end
end
function SpellStock.arm(toJob)
    if SpellStock.FIELD[toJob] and (SpellStock.saved[toJob] or 0) ~= 0 then
        SpellStock.pendingJob, SpellStock.confirmed, SpellStock.waited = toJob, 0, 0
    else
        SpellStock.pendingJob = nil
    end
end
function SpellStock.tick()
    local job = SpellStock.pendingJob
    if not job then return end
    SpellStock.waited = SpellStock.waited + 1
    if getCurrentJob() == job then
        SpellStock.confirmed = SpellStock.confirmed + 1
    else
        SpellStock.confirmed = 0
    end
    if SpellStock.waited > SpellStock.MAX_FRAMES then SpellStock.pendingJob = nil return end
    if SpellStock.confirmed < SpellStock.CONFIRM_FRAMES then return end
    SpellStock.pendingJob = nil
    local ctx = SpellStock.ctx()
    local id = SpellStock.saved[job]
    if not ctx or not id or id == 0 then return end
    local ok, err = pcall(function() ctx[SpellStock.FIELD[job]] = id end)
    if not ok then log.warn("[TWINWV] Spellhold restore failed: " .. tostring(err)) end
end

-- Keep the Health / Stamina percentage across a vocation switch. The game
-- keeps the absolute value (clamped to the new maximum), so Mage -> Warrior
-- arrived at ~26% Health with the critical-health effect. Full Health would
-- be a cheat, so the percentage is kept instead: while the switch runs (and
-- HOLD_FRAMES frames after the maximum last moved - the preset's rings and
-- armor move it too), whenever the maximum changes the value is set to
-- previous_value / previous_max * new_max, using the PREVIOUS frame (in the
-- switch frame the game has already clamped it). Damage taken meanwhile is
-- kept. Reading/writing Health as in Warfarer Arsenal: Character.get_Hp() /
-- get_OriginalMaxHp(), HitController.setHpValue(hp, false), from
-- LateUpdateBehavior. Stamina: StaminaManager.get_RemainingAmount() /
-- get_MaxValue() / setRemainingAmount(); negative stamina (exhausted) is left alone.
local HpKeep = { armed = false, frames = 0, idle = 0, hp = nil, mx = nil, MAX_FRAMES = 300, HOLD_FRAMES = 60 }
function HpKeep.read()
    local p = getPlayer()
    if not p then return nil end
    local ok, hp, mx = pcall(function() return p:call("get_Hp()"), p:call("get_OriginalMaxHp()") end)
    hp, mx = ok and tonumber(hp), ok and tonumber(mx)
    if not hp or not mx or mx <= 0 then return nil end
    return hp, mx
end
function HpKeep.staminaMgr()
    local p = getPlayer()
    if not p then return nil end
    local ok, sm = pcall(function() return p:call("get_StaminaManager()") end)
    return ok and sm or nil
end
function HpKeep.readSt()
    local sm = HpKeep.staminaMgr()
    if not sm then return nil end
    local ok, st, mx = pcall(function() return sm:call("get_RemainingAmount()"), sm:call("get_MaxValue()") end)
    st, mx = ok and tonumber(st), ok and tonumber(mx)
    if not st or not mx or mx <= 0 then return nil end
    return st, mx
end
function HpKeep.tickSt()
    local st, mx = HpKeep.readSt()
    if not st then return end
    if HpKeep.stMx and math.abs(mx - HpKeep.stMx) > 0.5 then
        local prevSt, prevMx = HpKeep.st, HpKeep.stMx
        if prevSt > 0 then
            local want = math.max(1, math.min(mx, prevSt / prevMx * mx))
            if math.abs(want - st) > 0.5 then
                local sm = HpKeep.staminaMgr()
                pcall(function() sm:call("setRemainingAmount(System.Single)", want) end)
                st = HpKeep.readSt() or want
            end
        end
        HpKeep.idle = 0
    end
    HpKeep.st, HpKeep.stMx = st, mx
end
function HpKeep.arm()
    HpKeep.st, HpKeep.stMx = HpKeep.readSt()
    local hp, mx = HpKeep.read()
    if not hp then HpKeep.armed = false return end
    HpKeep.armed, HpKeep.frames, HpKeep.idle, HpKeep.hp, HpKeep.mx = true, 0, 0, hp, mx
end
function HpKeep.set(hp)
    local p = getPlayer()
    pcall(function()
        local go = p:call("get_GameObject()")
        local hc = go:call("getComponent(System.Type)", sdk.typeof("app.HitController"))
        hc:call("setHpValue", hp, false)
    end)
end
-- from LateUpdateBehavior, every frame
function HpKeep.tick()
    if not HpKeep.armed then return end
    HpKeep.frames = HpKeep.frames + 1
    pcall(HpKeep.tickSt)
    local hp, mx = HpKeep.read()
    if not hp then HpKeep.armed = false return end
    if math.abs(mx - HpKeep.mx) > 0.5 then
        local prevHp, prevMx = HpKeep.hp, HpKeep.mx
        if prevHp > 0 and hp > 0 then -- never touch a dead character
            local want = math.max(1, math.min(mx, prevHp / prevMx * mx))
            if math.abs(want - hp) > 0.5 then
                HpKeep.set(want)
                hp = HpKeep.read() or want
            end
        end
        HpKeep.idle = 0
    else
        HpKeep.idle = HpKeep.idle + 1
    end
    HpKeep.hp, HpKeep.mx = hp, mx
    -- switch and re-equip done, the maximum hasn't moved for a while
    if (HpKeep.idle >= HpKeep.HOLD_FRAMES and not isVocationSwitchInFlight()) or HpKeep.frames >= HpKeep.MAX_FRAMES then
        HpKeep.armed = false
    end
end

function PresetMatch.rememberDrawn()
    PresetMatch.wantDraw = PresetMatch.isDrawn()
end
function PresetMatch.runDeferred()
    local q = PresetMatch.lateQueue
    if #q == 0 then return end
    PresetMatch.lateQueue = {}
    local drawn = PresetMatch.wantDraw or PresetMatch.isDrawn()
    for _, fn in ipairs(q) do
        local ok, err = pcall(fn)
        if not ok then log.warn("[TWINWV] deferred equip apply failed: " .. tostring(err)) end
    end
    if drawn and not PresetMatch.isDrawn() then
        PresetMatch.redrawFrames = 0
        PresetMatch.redrawStage = "request"
    end
    if not isVocationSwitchInFlight() then PresetMatch.wantDraw = false end
end

local pendingWeaponJobId = nil
local pendingWeaponWaitFrames = 0
local pendingWeaponConfirmedFrames = 0

local queueRearmamentWeaponEffect

local suppressNextRearmEffect = false

local function tickPendingWeaponApply()
    if not pendingWeaponJobId then return end
    pendingWeaponWaitFrames = pendingWeaponWaitFrames + 1
    if getCurrentJob() == pendingWeaponJobId then
        pendingWeaponConfirmedFrames = pendingWeaponConfirmedFrames + 1
    else
        pendingWeaponConfirmedFrames = 0
    end
    if pendingWeaponConfirmedFrames >= PENDING_WEAPON_CONFIRM_FRAMES
        or pendingWeaponWaitFrames >= PENDING_WEAPON_MAX_FRAMES then
        local jobId = pendingWeaponJobId
        pendingWeaponJobId = nil
        pendingWeaponWaitFrames = 0
        pendingWeaponConfirmedFrames = 0
        local suppress = suppressNextRearmEffect
        suppressNextRearmEffect = false
        PresetMatch.defer(function()
            applyWeaponPresetForJob(jobId)
            if not suppress then queueRearmamentWeaponEffect(jobId) end
        end)
    end
end

-- 15.10 fix: Armor/Rings used to apply synchronously, right after
-- requestChangeJob(), without waiting for the job switch to actually settle -
-- the same class of bug already fixed for Weapon above. Now deferred the
-- same way, through PENDING_ARMOR_*/PENDING_RINGS_* below, and
-- isVocationSwitchInFlight (used by installAutoRememberHook above) treats
-- any of the three pending* flags as "a vocation switch is still in
-- flight", so the auto-remember hook can't fire on a stray applyEquipChange
-- triggered by the engine mid-switch and stomp the destination job's preset.
local PENDING_ARMOR_MAX_FRAMES = 60
local PENDING_ARMOR_CONFIRM_FRAMES = 5
local pendingArmorJobId = nil
local pendingArmorWaitFrames = 0
local pendingArmorConfirmedFrames = 0

local PENDING_RINGS_MAX_FRAMES = 60
local PENDING_RINGS_CONFIRM_FRAMES = 5
local pendingRingsJobId = nil
local pendingRingsWaitFrames = 0
local pendingRingsConfirmedFrames = 0

RingOv.inFlight = function() return isVocationSwitchInFlight() end
isVocationSwitchInFlight = function()
    return pendingWeaponJobId ~= nil or pendingArmorJobId ~= nil or pendingRingsJobId ~= nil
        or #PresetMatch.lateQueue > 0
end

local function tickPendingArmorApply()
    if not pendingArmorJobId then return end
    pendingArmorWaitFrames = pendingArmorWaitFrames + 1
    if getCurrentJob() == pendingArmorJobId then
        pendingArmorConfirmedFrames = pendingArmorConfirmedFrames + 1
    else
        pendingArmorConfirmedFrames = 0
    end
    if pendingArmorConfirmedFrames >= PENDING_ARMOR_CONFIRM_FRAMES
        or pendingArmorWaitFrames >= PENDING_ARMOR_MAX_FRAMES then
        local jobId = pendingArmorJobId
        pendingArmorJobId = nil
        pendingArmorWaitFrames = 0
        pendingArmorConfirmedFrames = 0
        PresetMatch.defer(function() applyArmorPresetForJob(jobId) end)
    end
end

local function tickPendingRingsApply()
    if not pendingRingsJobId then return end
    pendingRingsWaitFrames = pendingRingsWaitFrames + 1
    if getCurrentJob() == pendingRingsJobId then
        pendingRingsConfirmedFrames = pendingRingsConfirmedFrames + 1
    else
        pendingRingsConfirmedFrames = 0
    end
    if pendingRingsConfirmedFrames >= PENDING_RINGS_CONFIRM_FRAMES
        or pendingRingsWaitFrames >= PENDING_RINGS_MAX_FRAMES then
        local jobId = pendingRingsJobId
        pendingRingsJobId = nil
        pendingRingsWaitFrames = 0
        pendingRingsConfirmedFrames = 0
        PresetMatch.defer(function() applyRingsPresetForJob(jobId) end)
    end
end

local function weaponEquipMatchesPreset(jobId)
    if not resolveItemManagerMethods() then return false end
    local entry = Config.Vocations[jobId]
    local preset = entry and entry.WeaponPreset
    -- Entries match that exact copy by StorageId (entries without one are
    -- dropped on load, the ItemId branch below is just a safety net).
    local wantedSids, wantedIds = {}, {}
    local wantedCount = 0
    if preset and preset.items then
        for _, want in ipairs(preset.items) do
            if want.StorageId then
                if not wantedSids[want.StorageId] then wantedCount = wantedCount + 1 end
                wantedSids[want.StorageId] = true
            else
                if not wantedIds[want.ItemId] then wantedCount = wantedCount + 1 end
                wantedIds[want.ItemId] = true
            end
        end
    end

    local im = getItemManager()
    local player = getPlayer()
    if not player then return false end
    local charaId = getPlayerCharaId(player)
    if not charaId then return false end

    local ok, matches = pcall(function()
        local storage = listPlayerStorage(im, charaId)
        if not storage then return false end
        local count = storage:call("get_Count")
        local actualCount = 0
        for i = 0, count - 1 do
            local v = storage:call("get_Item", i)
            if v and v._IsEquipped == true and isWeaponEquipSlot(v:call("get_EquipSlot()")) then
                local sid = PresetMatch.storageIdOf(v)
                if not ((sid and wantedSids[sid]) or wantedIds[v._ItemId]) then return false end
                actualCount = actualCount + 1
            end
        end
        return actualCount == wantedCount
    end)
    if not ok then return false end
    return matches == true
end

local pendingRearmWeaponEffectJobId = nil

local pendingForceDrawWeapon = false

local REARM_WEAPON_EFFECT_SETTLE_FRAMES = 5
-- Switching vocations re-equips the whole character (weapon+armor+rings, via
-- requestChangeJob plus a deferred confirmation), while a Weapon Slots recall
-- is just a weapon swap in the hands without a vocation change - an order of
-- magnitude less processing. 0 wasn't enough (confirmed in-game), 2 is.
local REARM_WEAPON_EFFECT_SETTLE_FRAMES_WEAPON_SLOT = 2
local rearmWeaponEffectSettleJobId = nil
local rearmWeaponEffectSettleFramesLeft = 0

local function tickRearmWeaponEffectSettle()
    if not rearmWeaponEffectSettleJobId then return end
    rearmWeaponEffectSettleFramesLeft = rearmWeaponEffectSettleFramesLeft - 1
    if rearmWeaponEffectSettleFramesLeft <= 0 then
        pendingRearmWeaponEffectJobId = rearmWeaponEffectSettleJobId
        rearmWeaponEffectSettleJobId = nil
    end
end

local function getJob10WeaponManager()
    local human = getHuman(getPlayer())
    if not human then return nil end
    local ok, mgr = pcall(function() return human:call("get_Job10WeaponManager()") end)
    if ok then return mgr end
    return nil
end

-- Transmogify rebuilds the weapons in hand asynchronously after
-- setEquip/removeEquip. Playing appearWeapon() before it's done leaves the
-- effect on a destroyed/temporary object, so wait while it has a pending
-- weapon preparation (skip the effect after a timeout).
local TRANSMOG_WAIT_MAX_FRAMES = 90
local transmogWaitFrames = 0

local function transmogifyBusy()
    local T = rawget(_G, "Transmogify")
    if type(T) ~= "table" or type(T.HasWorldWeaponPreparation) ~= "function" then return false end
    local player = getPlayer()
    if not player then return false end
    local ok, busy = pcall(T.HasWorldWeaponPreparation, player)
    return ok and busy == true
end

local function getEquippedWeapons()
    local player = getPlayer()
    if not player then return nil, nil end
    local okR, rw = pcall(function() return player:get_RightWeapon() end)
    local okL, lw = pcall(function() return player:get_LeftWeapon() end)
    return okR and rw or nil, okL and lw or nil
end

-- settleFrames is optional, defaults to REARM_WEAPON_EFFECT_SETTLE_FRAMES
-- (vocation switch); Weapon Slots recall passes its own, separate constant
-- (see REARM_WEAPON_EFFECT_SETTLE_FRAMES_WEAPON_SLOT above).
queueRearmamentWeaponEffect = function(jobId, settleFrames)
    if not Config.General.RearmamentWeaponEffect then return end
    rearmWeaponEffectSettleJobId = jobId
    rearmWeaponEffectSettleFramesLeft = settleFrames or REARM_WEAPON_EFFECT_SETTLE_FRAMES
end

local directCastNodeName = ""

-- forceChangeDrawingWeapon() and appearWeapon() (Rearmament Weapon Effect,
-- below) both need to run from inside LateUpdateBehavior - calling them
-- directly from on_frame doesn't work reliably. Both are deferred through a
-- pending flag/job id and picked up here on the next LateUpdateBehavior tick.
local rearmEntryOk = pcall(function()
    re.on_application_entry("LateUpdateBehavior", function()
        PresetMatch.runDeferred()
        pcall(HpKeep.tick)
        do
            local ok, err = pcall(function()
                local human = getHuman(getPlayer())
                if not human then return end
                local gameobj = human:call("get_GameObject()")
                local mfsm2 = gameobj:call("getComponent(System.Type)", sdk.typeof("via.motion.MotionFsm2"))
                directCastNodeName = mfsm2:getCurrentNodeName(0) or directCastNodeName
            end)
        end

        if pendingForceDrawWeapon then
            pendingForceDrawWeapon = false
            local ok, err = pcall(function()
                local human = getHuman(getPlayer())
                if human then human:call("forceChangeDrawingWeapon(System.Boolean)", true) end
            end)
            if not ok then
                log.warn("[TWINWV] Extra Skills Direct Cast: forceChangeDrawingWeapon() failed: " .. tostring(err))
            end
        end

        -- Draw the weapon back (see PresetMatch.redrawFrames). Instant
        -- forceChangeDrawingWeapon(true) doesn't stick after Transmogify's
        -- rebuild, the regular draw action does (Transmogify uses it too).
        local redrawThisFrame = false
        if PresetMatch.redrawFrames then
            local f = PresetMatch.redrawFrames + 1
            PresetMatch.redrawFrames = f
            if f >= PresetMatch.REDRAW_MAX_FRAMES then
                PresetMatch.redrawFrames = nil
                PresetMatch.redrawStage = nil
            elseif f >= PresetMatch.REDRAW_MIN_FRAMES and not transmogifyBusy() then
                if PresetMatch.isDrawn() then
                    PresetMatch.redrawFrames = nil
                    PresetMatch.redrawStage = nil
                elseif PresetMatch.redrawStage == "request" then
                    local ok, err = pcall(function()
                        getPlayer():call("get_HumanActionSelector()"):call("requestDrawWeapon()")
                    end)
                    if not ok then log.warn("[TWINWV] requestDrawWeapon() failed: " .. tostring(err)) end
                    PresetMatch.redrawStage = "done"
                    redrawThisFrame = true
                elseif PresetMatch.redrawStage == "done" and f >= PresetMatch.REDRAW_MIN_FRAMES + 30 then
                    PresetMatch.redrawFrames = nil
                    PresetMatch.redrawStage = nil
                end
            end
        end

        local rearmReady = false
        if pendingRearmWeaponEffectJobId and (redrawThisFrame or PresetMatch.redrawFrames) then
            -- wait until the weapon is back in hand: on a sheathed weapon
            -- appearWeapon() plays the visual only, without the sound
        elseif pendingRearmWeaponEffectJobId then
            if transmogifyBusy() then
                transmogWaitFrames = transmogWaitFrames + 1
                if transmogWaitFrames >= TRANSMOG_WAIT_MAX_FRAMES then
                    pendingRearmWeaponEffectJobId = nil
                    transmogWaitFrames = 0
                end
            else
                transmogWaitFrames = 0
                rearmReady = true
            end
        end

        if rearmReady then
            local jobId = pendingRearmWeaponEffectJobId
            pendingRearmWeaponEffectJobId = nil

            local mgr = getJob10WeaponManager()
            if mgr then
                local rw, lw = getEquippedWeapons()
                local ok, err = pcall(function()
                    if rw then mgr:appearWeapon(rw) end
                    if lw then mgr:appearWeapon(lw) end
                end)
                if not ok then
                    log.warn("[TWINWV] Rearmament Weapon Effect: appearWeapon() failed: " .. tostring(err))
                end
                local okBody, errBody = pcall(function() mgr:generateBodyEffect() end)
                if not okBody then
                    log.warn("[TWINWV] Rearmament Effect: generateBodyEffect() failed: " .. tostring(errBody))
                end
            end

            if not weaponEquipMatchesPreset(jobId) then
                suppressNextRearmEffect = true
                pendingWeaponJobId = jobId
                pendingWeaponWaitFrames = 0
                pendingWeaponConfirmedFrames = 0
            end
        end
    end)
end)
if not rearmEntryOk then
    log.warn("[TWINWV] re.on_application_entry(\"LateUpdateBehavior\") not available - Rearmament Weapon/Armor Effects will stay disabled even if enabled in settings.")
end

-- Switching vocations too fast (or with a menu open) can crash the game:
-- the engine is still re-equipping the character from the previous switch
-- when the next one starts (tested: crashes with a 0.1 s gap, none from
-- 0.2 s). So no switching while the game is paused, and presses are ignored
-- (not queued) until the previous switch has fully finished and at least
-- COOLDOWN_SEC has passed. os.clock() is wall time in REFramework, so this
-- doesn't depend on FPS.
local SwitchGate = {
    -- Minimum time between vocation switches, in seconds (0.2-0.6).
    -- If fast switching still crashes the game on your PC, raise it here.
    COOLDOWN_SEC = 0.2,
    MIN_SEC = 0.2,
    MAX_SEC = 0.6,
    DEFAULT_SEC = 0.2,
    MAX_WAIT_FRAMES = 180,
    lastSwitchAt = nil,
    waitFrames = 0,
}

-- Cutscene detection (hint from DD2 Cutscene Player): timeline events live
-- in app.DemoMediator.<Works>k__BackingField, each with
-- <CurrentState>k__BackingField: 1 = Standby (loaded, not playing - the game
-- keeps a few preloaded during normal gameplay), 11 = END, 13 = unloaded.
-- Never call getWork() - it crashes the game; only the Works field, its _size
-- and get_Item are read. Polled every POLL_FRAMES frames.
SwitchGate.cs = { PLAY_MIN = 2, PLAY_MAX = 12, POLL_FRAMES = 6, frame = 0, active = false }
function SwitchGate.cutscenePoll()
    local cs = SwitchGate.cs
    cs.frame = cs.frame + 1
    if cs.frame < cs.POLL_FRAMES then return cs.active end
    cs.frame = 0
    local active = false
    pcall(function()
        local dm = sdk.get_managed_singleton("app.DemoMediator")
        if not dm then return end
        local works = dm:get_field("<Works>k__BackingField") or dm:get_field("Works")
        if not works then return end
        works = sdk.to_managed_object(works) or works
        local n = tonumber(tostring(works:get_field("_size"))) or -1
        if n <= 0 then return end
        local td = works:get_type_definition()
        local m = td:get_method("get_Item(System.Int32)") or td:get_method("get_Item")
        if not m then return end
        for i = 0, n - 1 do
            local w = m:call(works, i)
            w = w and (sdk.to_managed_object(w) or w)
            local st = w and tonumber(tostring(w:get_field("<CurrentState>k__BackingField"))) or -1
            if st >= cs.PLAY_MIN and st <= cs.PLAY_MAX then active = true break end
        end
    end)
    cs.active = active
    return active
end

function SwitchGate.cooldownSec()
    local v = tonumber(SwitchGate.COOLDOWN_SEC) or SwitchGate.DEFAULT_SEC
    if v < SwitchGate.MIN_SEC then v = SwitchGate.MIN_SEC end
    if v > SwitchGate.MAX_SEC then v = SwitchGate.MAX_SEC end
    return v
end

function SwitchGate.busy()
    return (SwitchGate.lastSwitchAt ~= nil and os.clock() - SwitchGate.lastSwitchAt < SwitchGate.cooldownSec())
        or isVocationSwitchInFlight()
        or rearmWeaponEffectSettleJobId ~= nil
        or pendingRearmWeaponEffectJobId ~= nil
        or PresetMatch.redrawFrames ~= nil
end

local function setVocation(jobId)
    if not VOCATIONS[jobId] then
        log.warn("[TWINWV] setVocation: unknown jobId=" .. tostring(jobId))
        return false
    end

    if isGuiPaused() or SwitchGate.cs.active or SwitchGate.busy() then
        return false
    end

    if getCurrentJob() == jobId then
        return true
    end

    local player = getPlayer()
    if not player then
        log.warn("[TWINWV] setVocation: player not found (save not loaded?)")
        return false
    end
    local human = getHuman(player)
    if not human then
        log.warn("[TWINWV] setVocation: could not get Human")
        return false
    end

    -- No "is this vocation unlocked" check here: the game's flag doesn't
    -- always match reality (e.g. transferred saves), so the game decides.

    local ok, err = pcall(function()
        local jobchanger = human:call("get_JobChanger()")
        if not jobchanger then error("get_JobChanger() returned nil") end
        PresetMatch.rememberDrawn()
        SpellStock.capture(getCurrentJob())
        HpKeep.arm()
        SpellStock.arm(jobId)
        jobchanger:requestChangeJob(jobId)
    end)

    if not ok then
        log.error("[TWINWV] requestChangeJob(" .. jobId .. ") threw: " .. tostring(err) ..
            " - likely no longer compatible with the current game version.")
        return false
    end

    SwitchGate.lastSwitchAt = os.clock()

    extraSkillsState = "none"
    extraSkillsSnapshot = nil

    if Config.General.AutoRememberWeapon then
        pendingWeaponJobId = jobId
        pendingWeaponWaitFrames = 0
        pendingWeaponConfirmedFrames = 0
    else
        pendingWeaponJobId = nil
    end
    if Config.General.AutoRememberArmor then
        pendingArmorJobId = jobId
        pendingArmorWaitFrames = 0
        pendingArmorConfirmedFrames = 0
    else
        pendingArmorJobId = nil
    end
    if Config.General.AutoRememberRings or RingOv.itemsFor(jobId) then
        pendingRingsJobId = jobId
        pendingRingsWaitFrames = 0
        pendingRingsConfirmedFrames = 0
    else
        pendingRingsJobId = nil
    end

    log.info("[TWINWV] -> " .. vocationName(jobId))
    return true
end

-- Safety net: the pending Weapon/Armor/Rings applies have their own frame
-- limits, but the Rearmament Effect only runs from the LateUpdateBehavior
-- callback - if that never comes, busy() would block switching forever.
-- Drop a stuck effect after MAX_WAIT_FRAMES.
function SwitchGate.tick()
    if rearmWeaponEffectSettleJobId ~= nil or pendingRearmWeaponEffectJobId ~= nil then
        SwitchGate.waitFrames = SwitchGate.waitFrames + 1
        if SwitchGate.waitFrames > SwitchGate.MAX_WAIT_FRAMES then
            log.warn("[TWINWV] Rearmament Effect stuck for " .. SwitchGate.MAX_WAIT_FRAMES .. " frames - dropping it.")
            rearmWeaponEffectSettleJobId = nil
            pendingRearmWeaponEffectJobId = nil
            SwitchGate.waitFrames = 0
        end
    else
        SwitchGate.waitFrames = 0
    end
end

-- Vocation Cycling (Prev/Next through vocations by their Cycle order).
-- Works alongside the wheel; handle() is defined further down.
local Cycle = {}

-- Prev/Next default to R3 + LT / R3 + RT - without the modifier, plain
-- LT/RT (regular game buttons) would cycle vocations mid-fight. Seeded once
-- with its own flag (installs from 2.4-2.6 never had it); the player's own
-- entries are never touched.
function Cycle.seedModifiers()
    if Config.General.CycleModifiersSeeded then return end
    local ok = pcall(function()
        local data = json.load_file(HOTKEYS_DATA_FILE) or {}
        if not data.modifier_actions then data.modifier_actions = {} end
        local dirty = false
        for _, key in ipairs({ "TWINWV_CycleNext_$", "TWINWV_CyclePrev_$" }) do
            if data.modifier_actions[key] == nil then
                data.modifier_actions[key] = "R3"
                dirty = true
            end
        end
        if dirty then json.dump_file(HOTKEYS_DATA_FILE, data) end
    end)
    if ok then Config.General.CycleModifiersSeeded = true end
end

local HK = {}

local function registerHotkeysOnce()
    if not hotkeys then return end
    seedDefaultHotkeyModifiers()
    Cycle.seedModifiers()
    for jobId = 1, 9 do
        HK["TWINWV_Voc" .. jobId] = Config.Vocations[jobId].Key
    end
    HK.TWINWV_ExtraBase = Config.ExtraSkillHotkeys.Base
    HK.TWINWV_ExtraSubA = Config.ExtraSkillHotkeys.SubA
    for slot = 1, NUM_BASE_SLOTS do
        HK["TWINWV_ExtraDirect" .. slot] = Config.ExtraDirectHotkeys["Slot" .. slot]
    end
    HK.TWINWV_Wheel = Config.WheelHotkeys.Key
    HK.TWINWV_WheelPad = Config.WheelHotkeys.Pad
    HK.TWINWV_SkillBarToggle = Config.SkillBar.ToggleKey
    HK.TWINWV_CyclePrev = Config.CycleHotkeys.Prev
    HK.TWINWV_CycleNext = Config.CycleHotkeys.Next
    HK.TWINWV_CyclePrevKey = Config.CycleHotkeys.PrevKey
    HK.TWINWV_CycleNextKey = Config.CycleHotkeys.NextKey
    HK.TWINWV_WeaponSlotMod = Config.WeaponSlotHotkeys.Modifier
    for slot = 1, NUM_WEAPON_SLOTS do
        HK["TWINWV_WeaponSlot" .. slot] = Config.WeaponSlotHotkeys["Slot" .. slot]
    end
    for i = 1, RingOv.MAX do
        HK["TWINWV_RingPreset" .. i] = Config.RingPresets.Keys["Slot" .. i]
    end
    -- Hidden hotkeys the player never sees or rebinds (no hotkey_setter is
    -- ever drawn for them) - their only purpose is polling "is Shift/Control/
    -- Alt (either side) physically held right now" via
    -- check_hotkey(name, true, false), since the Hotkeys module itself has no
    -- separate raw API for that - see isHotkeyUncontested below.
    HK.TWINWV_GuardLShift = "LShift"
    HK.TWINWV_GuardRShift = "RShift"
    HK.TWINWV_GuardLControl = "LControl"
    HK.TWINWV_GuardRControl = "RControl"
    HK.TWINWV_GuardLAlt = "LAlt"
    HK.TWINWV_GuardRAlt = "RAlt"
    hotkeys.setup_hotkeys(HK)
end
registerHotkeysOnce()

local function syncHotkeysToConfig()
    if not hotkeys then return end
    hotkeys.update_hotkey_table(HK)
    for jobId = 1, 9 do
        Config.Vocations[jobId].Key = HK["TWINWV_Voc" .. jobId]
    end
    Config.ExtraSkillHotkeys.Base = HK.TWINWV_ExtraBase
    Config.ExtraSkillHotkeys.SubA = HK.TWINWV_ExtraSubA
    for slot = 1, NUM_BASE_SLOTS do
        Config.ExtraDirectHotkeys["Slot" .. slot] = HK["TWINWV_ExtraDirect" .. slot]
    end
    Config.WheelHotkeys.Key = HK.TWINWV_Wheel
    Config.WheelHotkeys.Pad = HK.TWINWV_WheelPad
    Config.SkillBar.ToggleKey = HK.TWINWV_SkillBarToggle
    Config.CycleHotkeys.Prev = HK.TWINWV_CyclePrev
    Config.CycleHotkeys.Next = HK.TWINWV_CycleNext
    Config.CycleHotkeys.PrevKey = HK.TWINWV_CyclePrevKey
    Config.CycleHotkeys.NextKey = HK.TWINWV_CycleNextKey
    Config.WeaponSlotHotkeys.Modifier = HK.TWINWV_WeaponSlotMod
    for slot = 1, NUM_WEAPON_SLOTS do
        Config.WeaponSlotHotkeys["Slot" .. slot] = HK["TWINWV_WeaponSlot" .. slot]
    end
    for i = 1, RingOv.MAX do
        Config.RingPresets.Keys["Slot" .. i] = HK["TWINWV_RingPreset" .. i]
    end
end

-- Cache of "does this action currently carry an extra modifier through the
-- widget's own combo feature" (modifier_actions in HOTKEYS_DATA_FILE) - keyed
-- by action name (TWINWV_Voc5, TWINWV_WeaponSlot3, ...), value is the
-- modifier's category ("Shift"/"Control"/"Alt") or nil (no modifier, or it's
-- a gamepad button like R3 which this guard doesn't concern itself with).
-- Refreshed once every ACTION_MODIFIER_CACHE_REFRESH_FRAMES frames rather
-- than every single frame (avoid hammering disk), but often enough that a
-- change made by the player via right-click in the widget itself takes
-- effect quickly.
local function classifyModifierKeyName(keyName)
    if not keyName or keyName == "" or keyName == "None" then return nil end
    if keyName:find("Shift") then return "Shift" end
    if keyName:find("Control") then return "Control" end
    if keyName:find("Alt") then return "Alt" end
    return nil -- gamepad button (R3, etc.) or something non-keyboard - not guarded
end

local ACTION_MODIFIER_CACHE_REFRESH_FRAMES = 30
local actionModifierCategoryCache = {}
local actionModifierCacheFramesLeft = 0

local function refreshActionModifierCache()
    local ok, data = pcall(json.load_file, HOTKEYS_DATA_FILE)
    local actions = (ok and data and data.modifier_actions) or {}
    local fresh = {}
    for key, value in pairs(actions) do
        local actionName = key:match("^(.+)_%$$")
        if actionName then
            fresh[actionName] = classifyModifierKeyName(value)
        end
    end
    actionModifierCategoryCache = fresh
end
refreshActionModifierCache()

local function tickActionModifierCache()
    actionModifierCacheFramesLeft = actionModifierCacheFramesLeft - 1
    if actionModifierCacheFramesLeft <= 0 then
        actionModifierCacheFramesLeft = ACTION_MODIFIER_CACHE_REFRESH_FRAMES
        refreshActionModifierCache()
    end
end

-- Polls "is Shift/Control/Alt (either side) physically held right now" via
-- the hidden TWINWV_Guard* hotkeys (see registerHotkeysOnce above), since the
-- Hotkeys module itself has no separate raw API for that.
local GUARD_MODIFIER_ACTIONS = {
    Shift = { "TWINWV_GuardLShift", "TWINWV_GuardRShift" },
    Control = { "TWINWV_GuardLControl", "TWINWV_GuardRControl" },
    Alt = { "TWINWV_GuardLAlt", "TWINWV_GuardRAlt" },
}

local function isGuardModifierHeld(category)
    for _, name in ipairs(GUARD_MODIFIER_ACTIONS[category]) do
        if hotkeys.check_hotkey(name, true, false) then return true end
    end
    return false
end

-- A real, confirmed bug (reported by a player): they have an in-game item
-- hotbar bound to Ctrl+Alpha1..6 in the game's own settings, and TWINWV's
-- Extra Skills Direct Cast bound bare to Alpha1..6. The Hotkeys widget checks
-- "is the assigned key down", not "is ONLY the assigned key down" - so
-- Ctrl+Alpha1 satisfies both the bare "Alpha1" binding (our cast) and
-- "Ctrl+Alpha1" (the in-game item, which isn't even part of our Hotkeys at
-- all) - it doesn't matter whether the conflicting bind lives in OUR config;
-- the game or another mod can occupy the same combo externally, and we still
-- have to tell them apart.
--
-- isHotkeyUncontested(actionName) returns false if some Shift/Control/Alt is
-- currently held that ISN'T already accounted for by actionName's own
-- configured combo (actionModifierCategoryCache) and/or the optional
-- extraExemptCategory - for cases like Weapon Slots, which have ANOTHER held
-- modifier of their own besides the action's own combo (see
-- TWINWV_WeaponSlotMod in handleWeaponSlotHotkeys).
local function isHotkeyUncontested(actionName, extraExemptCategory)
    local ownCategory = actionModifierCategoryCache[actionName]
    for category in pairs(GUARD_MODIFIER_ACTIONS) do
        if category ~= ownCategory and category ~= extraExemptCategory and isGuardModifierHeld(category) then
            return false
        end
    end
    return true
end

local function handleVocationSwitchHotkeys()
    if not hotkeys then return end

    local fired = nil
    for jobId = 1, 9 do
        local name = "TWINWV_Voc" .. jobId
        if hotkeys.check_hotkey(name, false, true) and isHotkeyUncontested(name) then
            fired = fired or {}
            fired[#fired + 1] = jobId
        end
    end
    if not fired then return end
    if #fired == 1 then
        setVocation(fired[1])
        return
    end

    -- isHotkeyUncontested already rules out most "bare key vs. same key +
    -- modifier" collisions, but if both vocations use modifiers from our
    -- own three categories (Shift/Control/Alt), both can still fire in the
    -- same frame. Fallback: prefer whichever vocation actually has a
    -- modifier assigned - it's closer to what was physically pressed.
    local chosen = nil
    for _, jobId in ipairs(fired) do
        if actionModifierCategoryCache["TWINWV_Voc" .. jobId] then
            chosen = jobId
            break
        end
    end
    setVocation(chosen or fired[#fired])
end

--------------------------------------------------------------------------------
-- Vocation Wheel (replaces the old Cycle Next/Prev): stand still, hold the
-- wheel key, point at a vocation with the mouse or the right stick, release
-- to switch - one switch per pick instead of cycling through several.
-- Input approach inspired by Warfarer's Arsenal (socastix): mouse movement
-- via via.hid.Mouse (delta, falling back to position difference), right stick
-- via the gamepad's get_AxisR, camera freeze via getInputRotationSpeedRate,
-- slow motion via the scene TimeScale + application GlobalSpeed, and input
-- blocking by clearing the player's app.CharacterInput flags/axes. Mouse and
-- gamepad devices come from the Hotkeys module (hotkeys.mouse / hotkeys.pad).
-- Two bindings because the Hotkeys widget holds one key per action:
-- TWINWV_Wheel (keyboard/mouse button -> steer with the mouse) and
-- TWINWV_WheelPad (gamepad button -> steer with the right stick).
-- Sectors are fixed: vocations 1-9 clockwise from the top.
--------------------------------------------------------------------------------
local RadialWheel = {
    open = false,
    byPad = false,
    sx = 0, sy = 0,
    sel = nil,
    MOUSE_MAX = 120,
    DEAD = 30,
    PAD_DEAD = 0.35,
    order = {}, -- vocations on the wheel, snapshot of Config.WheelOrder taken on open
    mouseProbed = false,
    mouseDeltaMethod = nil,
    mousePosMethod = nil,
    lastMousePos = nil,
    camSkip = false,
    slowActive = false,
    slowCur = 1.0,
    BLOCK_TAIL_FRAMES = 4,
    blockTail = 0,
    playerInputAddr = nil,
    armed = false,
    armedAt = 0,
    armedByPad = false,
}

function RadialWheel.xy(v)
    if v == nil then return nil end
    local ok, x, y = pcall(function() return v.x, v.y end)
    if ok and type(x) == "number" and type(y) == "number" then return x, y end
    ok, x, y = pcall(function() return v:get_field("x"), v:get_field("y") end)
    if ok and type(x) == "number" and type(y) == "number" then return x, y end
    return nil
end

function RadialWheel.mouseDelta()
    local dev = hotkeys and hotkeys.mouse
    if not dev then return 0, 0 end
    if not RadialWheel.mouseProbed then
        RadialWheel.mouseProbed = true
        local ok, td = pcall(function() return dev:get_type_definition() end)
        if ok and td then
            for _, n in ipairs({ "get_DeltaPosition", "get_PosDelta", "get_DeltaPos", "get_Delta", "get_MoveDelta" }) do
                if td:get_method(n) then RadialWheel.mouseDeltaMethod = n; break end
            end
            for _, n in ipairs({ "get_Position", "get_Pos", "get_CursorPosition", "get_ClientPosition" }) do
                if td:get_method(n) then RadialWheel.mousePosMethod = n; break end
            end
        end
        log.info("[TWINWV] Vocation wheel mouse: delta=" .. tostring(RadialWheel.mouseDeltaMethod) ..
            ", position=" .. tostring(RadialWheel.mousePosMethod))
    end
    local pdx, pdy = 0, 0
    if RadialWheel.mousePosMethod then
        local ok, v = pcall(function() return dev:call(RadialWheel.mousePosMethod) end)
        local x, y = RadialWheel.xy(ok and v or nil)
        if x then
            local last = RadialWheel.lastMousePos
            if last then pdx, pdy = x - last[1], y - last[2] end
            RadialWheel.lastMousePos = { x, y }
        end
    end
    if RadialWheel.mouseDeltaMethod then
        local ok, v = pcall(function() return dev:call(RadialWheel.mouseDeltaMethod) end)
        local x, y = RadialWheel.xy(ok and v or nil)
        if x and (x ~= 0 or y ~= 0) then return x, y end
    end
    return pdx, pdy
end

function RadialWheel.readStick(dev, side)
    for _, m in ipairs({ "get_Axis" .. side, "get_RawAxis" .. side }) do
        local ok, v = pcall(function() return dev:call(m) end)
        local x, y = RadialWheel.xy(ok and v or nil)
        if x then return x, y end
    end
    return nil
end
-- the stick that picks (Config.WheelHotkeys.Stick), read from the device
-- itself - the character gets no left stick while the wheel is open
function RadialWheel.padStick()
    local dev = hotkeys and hotkeys.pad
    if not dev then return nil end
    local mode = Config.WheelHotkeys.Stick or "Right"
    if mode == "Left" then return RadialWheel.readStick(dev, "L") end
    if mode == "Either" then
        local rx, ry = RadialWheel.readStick(dev, "R")
        local lx, ly = RadialWheel.readStick(dev, "L")
        if not lx then return rx, ry end
        if not rx then return lx, ly end
        if lx * lx + ly * ly > rx * rx + ry * ry then return lx, ly end -- the one tilted further
        return rx, ry
    end
    return RadialWheel.readStick(dev, "R")
end

function RadialWheel.updateSelection()
    local W = RadialWheel
    if W.byPad then
        local x, y = W.padStick()
        if x and math.sqrt(x * x + y * y) >= W.PAD_DEAD then
            W.sx, W.sy = x * W.MOUSE_MAX, -y * W.MOUSE_MAX
        end
    else
        local dx, dy = W.mouseDelta()
        W.sx, W.sy = W.sx + dx, W.sy + dy
        local len = math.sqrt(W.sx * W.sx + W.sy * W.sy)
        if len > W.MOUSE_MAX then W.sx, W.sy = W.sx / len * W.MOUSE_MAX, W.sy / len * W.MOUSE_MAX end
    end
    local len = math.sqrt(W.sx * W.sx + W.sy * W.sy)
    if len >= W.DEAD then
        local a = math.atan(W.sx, -W.sy)
        if a < 0 then a = a + 2 * math.pi end
        local n = #W.order
        local step = 2 * math.pi / n
        W.sel = W.order[math.floor((a + step / 2) / step) % n + 1]
    else
        W.sel = nil
    end
end

-- Slow motion while the wheel is open. The game (and other mods) write these
-- values too, so they're re-applied at the start of the engine's update
-- entries while active.
function RadialWheel.slowSpeed()
    local v = tonumber(Config.General.WheelSlowMotionSpeed) or 0.3
    if v < 0.1 then v = 0.1 end
    if v > 1.0 then v = 1.0 end
    return v
end

function RadialWheel.setTimeScale(v)
    pcall(function()
        local sm = sdk.get_native_singleton("via.SceneManager")
        local td = sdk.find_type_definition("via.SceneManager")
        local scene = sm and td and sdk.call_native_func(sm, td, "get_CurrentScene")
        if scene then scene:call("set_TimeScale", v) end
    end)
    pcall(function()
        local app = sdk.get_native_singleton("via.Application")
        local td = sdk.find_type_definition("via.Application")
        if app and td then sdk.call_native_func(app, td, "set_GlobalSpeed", v) end
    end)
end

function RadialWheel.tickSlow()
    local W = RadialWheel
    local want = W.open and Config.General.WheelSlowMotion
    if not want and not W.slowActive then return end
    W.slowActive = true
    local target = want and W.slowSpeed() or 1.0
    local step = 0.12
    if W.slowCur < target then W.slowCur = math.min(target, W.slowCur + step)
    else W.slowCur = math.max(target, W.slowCur - step) end
    W.setTimeScale(W.slowCur)
    if not want and W.slowCur >= 1.0 then
        W.setTimeScale(1.0)
        W.slowActive, W.slowCur = false, 1.0
    end
end

function RadialWheel.forceRestoreSpeed()
    if RadialWheel.slowActive then RadialWheel.setTimeScale(1.0) end
    RadialWheel.slowActive, RadialWheel.slowCur = false, 1.0
end

for _, entry in ipairs({ "UpdateBehavior", "LateUpdateBehavior", "BeginRendering" }) do
    pcall(function()
        re.on_pre_application_entry(entry, function()
            if RadialWheel.slowActive then pcall(RadialWheel.setTimeScale, RadialWheel.slowCur) end
        end)
    end)
end

function RadialWheel.close(pick)
    local sel = RadialWheel.sel
    RadialWheel.open = false
    RadialWheel.sel = nil
    RadialWheel.blockTail = RadialWheel.BLOCK_TAIL_FRAMES
    if pick and sel and sel ~= getCurrentJob() then
        setVocation(sel)
    end
end

-- A press first "arms" the wheel; it opens after Config.WheelHotkeys.HoldSec
-- (RadialWheel.holdSec, 0 = right away), standing still or moving. A direct
-- vocation key pressed meanwhile (e.g. Shift+F1) cancels it.
function RadialWheel.holdSec()
    local v = tonumber(Config.WheelHotkeys.HoldSec) or 0
    if v < 0 then v = 0 elseif v > 0.5 then v = 0.5 end
    return v
end

function RadialWheel.playerInputObj()
    local player = getPlayer()
    if not player then return nil end
    for _, owner in ipairs({ player, getHuman(player) }) do
        if owner then
            for _, sig in ipairs({ "get_Input()", "get_CharacterInput()" }) do
                local ok, o = pcall(function() return owner:call(sig) end)
                if ok and o then return o end
            end
        end
    end
    return nil
end

function RadialWheel.directVocationKeyPressed()
    for jobId = 1, 9 do
        if hotkeys.check_hotkey("TWINWV_Voc" .. jobId, false, true) then return true end
    end
    return false
end

-- Vocations with a wheel position > 0, sorted by position.
function RadialWheel.enabledOrder()
    local list = {}
    local order = Config.WheelOrder or {}
    for jobId = 1, 9 do
        local v = tonumber(order[jobId]) or jobId
        if v > 0 then list[#list + 1] = { jobId = jobId, v = v } end
    end
    table.sort(list, function(a, b)
        if a.v ~= b.v then return a.v < b.v end
        return a.jobId < b.jobId
    end)
    local ids = {}
    for i, e in ipairs(list) do ids[i] = e.jobId end
    return ids
end

-- Without REFramework D2D the wheel would be invisible (but still slow the
-- game and block input), and with fewer than 2 vocations there's nothing to pick.
function RadialWheel.canOpen()
    return (d2d ~= nil or d2dx ~= nil) and #RadialWheel.enabledOrder() >= 2
end

function RadialWheel.openNow(byPad)
    local W = RadialWheel
    W.armed = false
    W.order = W.enabledOrder()
    W.open = true
    W.byPad = byPad
    W.sx, W.sy, W.sel = 0, 0, nil
    W.lastMousePos = nil
    W.playerInputAddr = nil
    W.mouseDelta()
end

function RadialWheel.tick()
    local W = RadialWheel
    if W.blockTail > 0 then W.blockTail = W.blockTail - 1 end
    if not hotkeys or not Config.General.EnableVocationWheel then
        W.armed = false
        if W.open then W.close(false) end
        W.tickSlow()
        return
    end
    local blocked = isGuiPaused() or SwitchGate.cs.active or not getCurrentJob()
    if W.open then
        if blocked or W.directVocationKeyPressed() then
            W.close(false)
        else
            W.updateSelection()
            local held = hotkeys.check_hotkey(W.byPad and "TWINWV_WheelPad" or "TWINWV_Wheel", true, false)
            if not held then W.close(true) end
        end
    elseif W.armed then
        local held = hotkeys.check_hotkey(W.armedByPad and "TWINWV_WheelPad" or "TWINWV_Wheel", true, false)
        if blocked or not held or W.directVocationKeyPressed() then
            W.armed = false
        elseif os.clock() - W.armedAt >= W.holdSec() then
            W.openNow(W.armedByPad)
        end
    elseif not blocked then
        local byKey = hotkeys.check_hotkey("TWINWV_Wheel", false, true)
        local byPad = hotkeys.check_hotkey("TWINWV_WheelPad", false, true)
        if (byKey or byPad) and W.canOpen() then
            W.armed = true
            W.armedAt = os.clock()
            W.armedByPad = (byPad and not byKey) and true or false
        end
    end
    W.tickSlow()
end

pcall(function()
    re.on_script_reset(function() pcall(RadialWheel.forceRestoreSpeed) end)
end)

-- Freeze the camera while the wheel is open (mouse/right stick steer the wheel).
pcall(function()
    local td = sdk.find_type_definition("app.RotateCameraControllerBase")
    local m = td and td:get_method("getInputRotationSpeedRate")
    if not m then
        log.warn("[TWINWV] Vocation wheel: camera freeze hook target not found - the camera will move while the wheel is open.")
        return
    end
    sdk.hook(m, function(args)
        RadialWheel.camSkip = false
        if RadialWheel.open then
            RadialWheel.camSkip = true
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end, function(retval)
        if RadialWheel.camSkip then
            RadialWheel.camSkip = false
            return sdk.float_to_ptr(0.0)
        end
        return retval
    end)
end)

-- Block the player's input while the wheel is open and for a few frames after
-- it closes (so releasing the wheel key doesn't reach the game). Only the
-- player's own app.CharacterInput is cleared, never the pawns'.
-- While the Cycling pad modifier (R3) is held, only buttons are blocked
-- ("buttons" mode, see Cycle.updateBlock) - movement and camera stay.
function RadialWheel.blockMode()
    if RadialWheel.open or RadialWheel.blockTail > 0 then return "all" end
    if Cycle.blocking then return "buttons" end
    return nil
end

function RadialWheel.isPlayerInput(obj)
    if RadialWheel.playerInputAddr == nil then
        local player = getPlayer()
        for _, sig in ipairs({ "get_Input()", "get_CharacterInput()" }) do
            local ok, o = pcall(function() return player:call(sig) end)
            if ok and o then
                local okA, addr = pcall(function() return o:get_address() end)
                if okA then RadialWheel.playerInputAddr = addr; break end
            end
        end
        if RadialWheel.playerInputAddr == nil then RadialWheel.playerInputAddr = false end
    end
    if RadialWheel.playerInputAddr then
        local ok, addr = pcall(function() return obj:get_address() end)
        return ok and addr == RadialWheel.playerInputAddr
    end
    local ok, auto = pcall(function() return obj:call("get_IsAutoPad()") end)
    return ok and auto == false
end

function RadialWheel.clearButtons(obj)
    for _, f in ipairs({ "ButtonOnFlags", "ButtonTriggerFlags", "ButtonReleaseFlags", "ButtonRepeatFlags",
                         "OldButtonOnFlags", "ButtonOnFlagsForUI", "PadButton", "PadButtonDown", "PadButtonUp", "PadButtonRepeat" }) do
        pcall(function() obj:set_field(f, 0) end)
    end
end

-- mode "buttons": buttons only. mode "all" (wheel): buttons, movement and camera.
function RadialWheel.clearInput(obj, mode)
    if mode == "buttons" then
        RadialWheel.clearButtons(obj)
        return
    end
    local zero2 = Vector2f.new(0, 0)
    for _, f in ipairs({ "KeyboardMouseAxisR", "<AxisR>k__BackingField", "<GyroAngularVelocity>k__BackingField" }) do
        pcall(function() obj:set_field(f, zero2) end)
    end
    for _, f in ipairs({ "KeyboardMouseAnalogR", "<AnalogR>k__BackingField", "<AxisMagnitudeR>k__BackingField" }) do
        pcall(function() obj:set_field(f, 0.0) end)
    end
    pcall(function() obj:set_field("<IsMouseMovedInFrame>k__BackingField", false) end)
    pcall(function() obj:set_field("<IsPadAxisRMovedInFrame>k__BackingField", false) end)
    if mode ~= "all" then return end
    RadialWheel.clearButtons(obj)
    for _, f in ipairs({ "_AxisL", "KeyboardMouseAxisL" }) do
        pcall(function() obj:set_field(f, zero2) end)
    end
    pcall(function() obj:call("set_AxisL", zero2) end)
    for _, f in ipairs({ "KeyboardMouseAnalogL", "<AnalogL>k__BackingField", "<AxisMagnitudeL>k__BackingField" }) do
        pcall(function() obj:set_field(f, 0.0) end)
    end
    pcall(function() obj:call("set_AxisMagnitudeL", 0.0) end)
    pcall(function() obj:call("set_AnalogL", 0.0) end)
end

pcall(function()
    local td = sdk.find_type_definition("app.CharacterInput")
    local m = td and td:get_method("updateDerived(System.Boolean)")
    if not m then return end
    sdk.hook(m, function(args)
        local storage = thread.get_hook_storage()
        storage.twinwvBlockObj = nil
        local mode = RadialWheel.blockMode()
        if not mode then return end
        local ok, obj = pcall(sdk.to_managed_object, args[2])
        if ok and obj and RadialWheel.isPlayerInput(obj) then
            pcall(RadialWheel.clearInput, obj, mode)
            storage.twinwvBlockObj = obj
        end
    end, function(retval)
        local storage = thread.get_hook_storage()
        local obj = storage.twinwvBlockObj
        storage.twinwvBlockObj = nil
        local mode = RadialWheel.blockMode()
        if obj and mode then pcall(RadialWheel.clearInput, obj, mode) end
        return retval
    end)
end)

pcall(function()
    local td = sdk.find_type_definition("app.UserInput")
    local m = td and td:get_method("update(System.Boolean, System.Boolean)")
    if not m then return end
    sdk.hook(m, function(args)
        local storage = thread.get_hook_storage()
        storage.twinwvUpdObj = nil
        if not RadialWheel.blockMode() then return end
        local ok, obj = pcall(sdk.to_managed_object, args[2])
        if ok and obj then storage.twinwvUpdObj = obj end
    end, function(retval)
        local storage = thread.get_hook_storage()
        local obj = storage.twinwvUpdObj
        storage.twinwvUpdObj = nil
        local mode = RadialWheel.blockMode()
        if obj and mode and RadialWheel.isPlayerInput(obj) then pcall(RadialWheel.clearInput, obj, mode) end
        return retval
    end)
end)

-- Per-frame "this key was already claimed by Weapon Slots" flags - fixes a
-- real collision when a Weapon Slot hotkey N sits on top of (or is a
-- superset combo of) the same key as Extra Skills Direct Cast N (e.g. Quick
-- Cast on Alpha1-6, weapon slots on Alt+Alpha1-6 via the widget's own combo
-- support) - Alt+Alpha1 satisfies both "Alt+Alpha1" (Weapon Slot) and plain
-- "Alpha1" (Extra Direct doesn't know about Alt at all), so without this both
-- would fire on the same press. Weapon Slots runs FIRST in on_frame and marks
-- here that it already claimed the key - Extra Direct skips that same key
-- this frame.
local weaponSlotConsumedThisFrame = {}

-- Vocations with a Cycle order > 0, sorted by it. Next/Prev wrap around; if
-- the current vocation isn't in the list, Next picks the first and Prev the
-- last. Ignored while the wheel is open.
function Cycle.list()
    local list = {}
    for jobId = 1, 9 do
        local voc = Config.Vocations[jobId]
        local order = voc and tonumber(voc.CycleOrder)
        if order and order > 0 then list[#list + 1] = { jobId = jobId, order = order } end
    end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.jobId < b.jobId
    end)
    return list
end

-- Next/Prev don't switch on every press - that would fully re-equip the
-- character on every vocation along the way. Presses only move a cursor
-- (Cycle.target, shown on the cycling strip); the switch happens once,
-- after confirmSec() without Next/Prev. The cursor is dropped when a menu
-- or the wheel opens, a direct vocation key is pressed, or cycling is off.
Cycle.target = nil
Cycle.lastInputAt = 0

function Cycle.confirmSec()
    local v = tonumber(Config.General.CycleConfirmSec) or 0.3
    if v < 0.2 then v = 0.2 elseif v > 0.6 then v = 0.6 end
    return v
end

function Cycle.indexOf(list, jobId)
    for i, e in ipairs(list) do
        if e.jobId == jobId then return i end
    end
    return nil
end

function Cycle.step(direction)
    local list = Cycle.list()
    if #list < 2 then return end
    local idx = Cycle.indexOf(list, Cycle.target or getCurrentJob())
    local nextIdx
    if not idx then
        nextIdx = (direction > 0) and 1 or #list
    else
        nextIdx = (idx - 1 + direction) % #list + 1
    end
    Cycle.target = list[nextIdx].jobId
    Cycle.lastInputAt = os.clock()
end

-- While the pad Prev/Next modifier (R3 by default) is held, the game gets no
-- buttons - otherwise LT/RT also do their own Grab/Sheathe. If R3 is let go
-- before LT/RT, the block holds until those are released too. Only applies
-- when a modifier is actually bound; keyboard Prev/Next are not blocked
-- (their modifier could be Shift/Ctrl, which the game uses all the time).
Cycle.blocking = false

function Cycle.updateBlock()
    local was = Cycle.blocking
    Cycle.blocking = false
    if not hotkeys or not Config.General.EnableVocationCycling then return end
    local modHeld = hotkeys.check_hotkey("TWINWV_CycleNext_$", true) or hotkeys.check_hotkey("TWINWV_CyclePrev_$", true)
    local trigHeld = was and (hotkeys.chk_down and (hotkeys.chk_down("TWINWV_CycleNext") or hotkeys.chk_down("TWINWV_CyclePrev")))
    Cycle.blocking = (modHeld or trigHeld) and true or false
    if Cycle.blocking and not was then RadialWheel.playerInputAddr = nil end
end

function Cycle.handle()
    Cycle.updateBlock()
    if not hotkeys or not Config.General.EnableVocationCycling then Cycle.target = nil; return end
    if RadialWheel.open or isGuiPaused() or RadialWheel.directVocationKeyPressed() then
        Cycle.target = nil
        return
    end
    if hotkeys.check_hotkey("TWINWV_CycleNext", false, true) or hotkeys.check_hotkey("TWINWV_CycleNextKey", false, true) then
        Cycle.step(1)
    elseif hotkeys.check_hotkey("TWINWV_CyclePrev", false, true) or hotkeys.check_hotkey("TWINWV_CyclePrevKey", false, true) then
        Cycle.step(-1)
    end
    if Cycle.target and os.clock() - Cycle.lastInputAt >= Cycle.confirmSec() then
        if Cycle.target == getCurrentJob() then
            Cycle.target = nil -- back where we started - nothing to do
        elseif not SwitchGate.busy() then -- previous switch still running: wait, keep the cursor
            setVocation(Cycle.target)
            Cycle.target = nil
        end
    end
end

-- Control groups for weapons, same idea as in StarCraft - Modifier held +
-- slot key = remember, slot key alone = switch. One shared Modifier for all
-- slots (rather than a separate modifier per slot) - fewer binds, same UX.
-- check_hotkey with pressedOnce=true fires once per press, not every frame
-- it's held. A successful recall also queues the Rearmament Weapon Effect
-- (if enabled) - the same re-equip flash used on a vocation switch, see
-- queueRearmamentWeaponEffect.
-- Ring Presets: a slot's key turns it on, pressing it again turns it off.
function RingOv.handleHotkeys()
    if not hotkeys then return end
    if isGuiPaused() or SwitchGate.cs.active then return end
    for i = 1, RingOv.MAX do
        if RingOv.slot(i) and hotkeys.check_hotkey("TWINWV_RingPreset" .. i, false, true) then
            RingOv.toggle(i)
        end
    end
end

local function handleWeaponSlotHotkeys()
    for slot = 1, NUM_WEAPON_SLOTS do weaponSlotConsumedThisFrame[slot] = false end
    if not hotkeys or not Config.General.WeaponSlotsEnabled then return end
    local job = getCurrentJob()
    if not job or not VOCATIONS[job] then return end

    -- extraExemptCategory: the category of TWINWV_WeaponSlotMod's own bound
    -- key (Modifier held = memorize). It's ANOTHER held modifier besides
    -- whatever combo the slot action itself might carry, so it has to be
    -- explicitly exempted here - otherwise a legitimate "Modifier+SlotN"
    -- press would get blocked by isHotkeyUncontested itself.
    local modCategory = classifyModifierKeyName(Config.WeaponSlotHotkeys.Modifier)
    local modHeld = hotkeys.check_hotkey("TWINWV_WeaponSlotMod", true, false)
    for slot = 1, NUM_WEAPON_SLOTS do
        local name = "TWINWV_WeaponSlot" .. slot
        if hotkeys.check_hotkey(name, false, true) and isHotkeyUncontested(name, modCategory) then
            weaponSlotConsumedThisFrame[slot] = true
            if modHeld then
                captureWeaponSlot(job, slot, false)
            elseif isGuiPaused() or SwitchGate.busy() then
                -- same crash risk as switching vocations - see SwitchGate
            else
                PresetMatch.rememberDrawn()
                PresetMatch.defer(function()
                    if applyWeaponSlot(job, slot) then
                        queueRearmamentWeaponEffect(job, REARM_WEAPON_EFFECT_SETTLE_FRAMES_WEAPON_SLOT)
                    end
                end)
            end
        end
    end
end

local function handleExtraSkills()
    if not hotkeys then return end
    local job = getCurrentJob()
    if not job or not VOCATIONS[job] then return end
    -- Extra Skills can be turned off; if that happens mid-hold, restore the
    -- regular skills.
    if not Config.General.ExtraSkillsEnabled then
        if extraSkillsState ~= "none" then
            if extraSkillsSnapshot then applySkillSet(job, extraSkillsSnapshot) end
            extraSkillsSnapshot = nil
            extraSkillsState = "none"
        end
        return
    end

    local baseHeld = hotkeys.check_hotkey("TWINWV_ExtraBase", true, false)
    local subAHeld = baseHeld and hotkeys.check_hotkey("TWINWV_ExtraSubA", true, false)
    local wantState = subAHeld and "A" or "none"

    if wantState ~= extraSkillsState then
        if extraSkillsState == "none" then
            extraSkillsSnapshot = getCurrentEquippedSkills(job)
        end
        if wantState == "none" then
            if extraSkillsSnapshot then applySkillSet(job, extraSkillsSnapshot) end
            extraSkillsSnapshot = nil
        else
            local entry = Config.Vocations[job]
            applySkillSet(job, entry.ExtraSkillsA)
        end
        extraSkillsState = wantState
    end
end

-- Maps our internal skill id (VOCATION_SKILLS) to the real field name of
-- app.HumanCustomSkillID, found by dumping that enum (CustomHumanSkill.txt)
-- and matching each field to its in-game name through targeted in-game
-- testing (requestCustomSkill only fires while the skill is actually
-- equipped in a base slot, so this can't be derived statically). This
-- mapping isn't documented anywhere else - if you're reading this on
-- GitHub, it's the only public reference for it.
local SKILL_CUSTOM_ID = {
    -- Job01 Fighter
    [1]  = "Job01_BlinkStrike",    -- Burst Strike
    [2]  = "Job01_RisingLunge",    -- Cloudward Slash
    [3]  = "Job01_CymbalAttack",   -- Shield Pummel
    [4]  = "Job01_FullMoonSlash",  -- Full Moon Slash
    [5]  = "Job01_Springboard",    -- Launchboard
    [6]  = "Job01_ShieldSummons",  -- Shield Drum
    [7]  = "Job01_ViolentStab",    -- Gutting Skewer
    [8]  = "Job01_HindsightSlash", -- Hindsight Sweep
    [9]  = "Job01_FullMoonGuard",  -- Flawless Guard
    [10] = "Job01_ShieldCounter",  -- Vengeful Slash
    [11] = "Job01_DivineDefense",  -- Divine Defense
    [12] = "Job01_BravesRaid",     -- Riotous Fury
    -- Dark Arisen DLC (id 102/103) - taken from another mod (True Warfarer
    -- DAV4), NOT verified by us yet - double-check with the debug tools in
    -- TWINWV.lua before fully trusting these.
    [102] = "Job01_RushAttack",  -- Whirlwind Strike (per True Warfarer)
    [103] = "Job01_Ascertain",   -- Shield Precision (per True Warfarer)

    -- Job02 Archer
    [13] = "Job02_ThreefoldArrow",    -- Manifold Shot
    [14] = "Job02_TriadShot",         -- Cascade Shot
    [15] = "Job02_BodyBinder",        -- Deathly Arrow
    [16] = "Job02_MeteorShot",        -- Lyncean Sight
    [17] = "Job02_SpecialAllowBomb",  -- Erupting Shot
    [18] = "Job02_SpecialAllowWater", -- Deluging Shot
    [19] = "Job02_SpecialAllowOil",   -- Incendiary Shot
    [20] = "Job02_SpecialAllowPoison",-- Nocuous Shot
    [21] = "Job02_RandomShot",        -- Tempest Shot
    [22] = "Job02_WhirlingArrow",     -- Spiral Arrow
    [23] = "Job02_FullBlast",         -- Heavenly Shot
    -- Dark Arisen DLC (id 104/105) - taken from another mod, not verified by us:
    [104] = "Job02_FlightShot", -- Falcon Arrow (per True Warfarer)
    [105] = "Job02_HeavyRain",  -- Cloudburst Shot (per True Warfarer)

    -- Job03 Mage
    [24] = "Job03_Firestorm",   -- High Flagration
    [25] = "Job03_Levin",       -- High Levin
    [26] = "Job03_Frigor",      -- High Frigor
    [27] = "Job03_SpellStock",  -- High Spellhold
    [28] = "Job03_GuardBit",    -- High Palladium
    [29] = "Job03_FireBoon",    -- Fire Affinity
    [30] = "Job03_IceBoon",     -- Ice Affinity
    [31] = "Job03_ThunderBoon", -- Lightning Affinity
    [32] = "Job03_HolyShine",   -- High Empyrean
    [33] = "Job03_CureSpot",    -- High Halidom
    [34] = "Job03_HasteSpot",   -- High Celerity
    [35] = "Job03_FullRecover", -- Argent Succor
    [36] = "Job03_SpellBreak",  -- High Solemnity
    [37] = "Job03_HolyGlare",   -- Celestial Paean
    -- Dark Arisen DLC (id 106/107) - taken from another mod, not verified by us:
    [106] = "Job03_DivineShot", -- Virtuous Bolt (per True Warfarer)
    [107] = "Job03_Reraise",    -- Benediction (per True Warfarer)

    -- Job04 Thief
    [38] = "Job04_CuttingWind",       -- Cutting Wind
    [39] = "Job04_Guillotine",        -- Skull Splitter
    [40] = "Job04_Attract",           -- Implicate
    [41] = "Job04_ParryCounter",      -- Masterful Kill
    [42] = "Job04_AbsoluteAvoidance", -- Formless Feint
    [43] = "Job04_HollowOut",         -- Draw and Quarter
    [44] = "Job04_FlameBlade",        -- Ignited Blades
    [45] = "Job04_SmokeScreen",       -- Smoke Shroud
    [46] = "Job04_RemoteBomb",        -- Powder Blast
    [47] = "Job04_WindWave",          -- Concussive Leap
    [48] = "Job04_Stealth",           -- Shadow Veil
    [49] = "Job04_Snatch",            -- Plunder
    [101] = "Job04_FakeMaster",       -- Blades of the Pyre (post-launch skill, unlocked via quest)
    -- Job04_AdvancedTrigger and Job04_CarpetBombing hang the character on cast - never call them.
    -- 15.10: another mod (True Warfarer DAV4) attributes id 108/109 to
    -- exactly these two fields as new DLC skills "Fang Schism"/"Combustive
    -- Caper" - the DLC may well have populated them with real data (as it
    -- did for other previously-anomalous fields), but WE have not verified
    -- this. Deliberately NOT added here and NOT removed from
    -- FORBIDDEN_CUSTOM_SKILL_FIELDS below until re-checked in-game.

    -- Job05 Warrior
    [50] = "Job05_HeavyRunningThrust", -- Ravening Lunge
    [51] = "Job05_HorizontalSlash",    -- Razing Sweep
    [52] = "Job05_CrescentSlash",      -- Heavenward Sunder
    [53] = "Job05_CycloneSlash",       -- Windstorm Slash
    [54] = "Job05_GroundDrill",        -- Diluvian Strike
    [55] = "Job05_CounterAttack",      -- Tidal Wrath
    [56] = "Job05_WarCry",             -- Roar
    [57] = "Job05_LandSlide",          -- Mountain Breaker
    [58] = "Job05_IndomitableLash",    -- Indomitable Lash
    [59] = "Job05_Guts",               -- Inspirit
    -- [60] Catapult Launch and [61] Arc of Might have no mapping: the only
    -- remaining fields, Job05_DashSlashUp and Job05_ScarletVow, freeze the
    -- character on cast.
    -- 15.10: True Warfarer (DAV4) attributes id 110/111 to exactly these two
    -- fields as "Iron Cleave"/"Blood Pact" - NOT added/un-forbidden without
    -- in-game re-verification.

    -- Job06 Sorcerer ([24]/[25]/[26]/[27] shared with Mage above)
    [62] = "Job06_Salamander",  -- High Salamander
    [63] = "Job06_Blizzard",    -- High Hagol
    [64] = "Job06_MineVolt",    -- High Thundermine
    [65] = "Job06_SaintDrain",  -- High Decanter
    [66] = "Job06_RockBeat",    -- High Seism
    [67] = "Job06_AddFlare",    -- Augural Flare
    [68] = "Job06_MeteorFall",  -- Meteoron
    [69] = "Job06_VortexRage",  -- Maelstorm
    -- Dark Arisen DLC (id 112/113) - taken from another mod, not verified by
    -- us (these two fields are NEW, not in our old anomalous-field list):
    [112] = "Job06_ThunderWhip", -- High Brontide (per True Warfarer)
    [113] = "Job06_FrozenStorm", -- Chilling Embrace (per True Warfarer)

    -- Job07 Mystic Spearhand
    [70] = "Job07_PsychoShoot",   -- Devout Offringe
    [71] = "Job07_FarThrow",      -- Unto Heven
    [72] = "Job07_EnergyDrain",   -- Ravinour's Hond
    [73] = "Job07_DragonStinger", -- Dragoun's Foin
    [74] = "Job07_QuickShield",   -- Mirour Shelde
    [76] = "Job07_SkyDive",       -- Skiedragoun's Feste
    [77] = "Job07_Gungnir",       -- Magike Speregonne
    [78] = "Job07_TwoSeconds",    -- Moment's Charge
    [79] = "Job07_DanceOfDeath",  -- Wild Furie
    -- [75] Seching Storm has no mapping: Job07_BladeShoot (its only
    -- remaining field) doesn't work, and Job07_MirageDance/Job07_GravityField
    -- hang the character - never call any of the three.
    -- 15.10: True Warfarer (DAV4) attributes id 114/115 to MirageDance/
    -- GravityField as "Bataille Twinne"/"Hindridge Mirke" - NOT added/
    -- un-forbidden without in-game re-verification.

    -- Job08 Magick Archer
    [80] = "Job08_FlameLance",     -- Blazefang Arrow
    [81] = "Job08_BurningLight",   -- Candescent Orb
    [82] = "Job08_FrostTrace",     -- Frosthunter Bolt
    [83] = "Job08_FrostBlock",     -- Arctic Bolt
    [84] = "Job08_ThunderChain",   -- Boltchain Stake
    [85] = "Job08_ReflectThunder", -- Ricochet Hunter
    [86] = "Job08_AbsorbArrow",    -- Lifetaking Arrow
    [87] = "Job08_LifeReturn",     -- Recovery Arrow
    [88] = "Job08_CounterArrow",   -- Fortalice
    [89] = "Job08_SleepArrow",     -- Soporific Bolt
    [91] = "Job08_SpiritArrow",    -- Martyr's Bolt
    -- [90] Sagittate Avalanche has no mapping: Job08_ShadowBinding hangs the
    -- character, Job08_DivineArrow doesn't work.
    -- 15.10: True Warfarer (DAV4) attributes id 116/117 to exactly these two
    -- fields as new DLC skills - ShadowBinding ("Shadefetter Bolt") and
    -- DivineArrow ("Harmonic Pentad"). [116]=ShadowBinding NOT added/
    -- un-forbidden (hangs). [117]=DivineArrow added below WITH a caveat: it
    -- is not on the hard block-list, but WE previously observed it "doing
    -- nothing" (possibly just untested pre-DLC, like the other anomalous
    -- fields) - re-verify in-game first.
    [117] = "Job08_DivineArrow", -- Harmonic Pentad (per True Warfarer, see caveat above)

    -- Job09 Trickster
    [92] = "Job09_SmokeWall",          -- Illusive Divider
    [93] = "Job09_SmokeGround",        -- Tricky Terrace
    [94] = "Job09_TripFregrance",      -- Visitant Aura
    [95] = "Job09_AttentionFregrance", -- Suffocating Shroud
    [96] = "Job09_PossessionSmoke",    -- Binding Effigy
    [97] = "Job09_RageFregrance",      -- Aromatic Resurgence
    [98] = "Job09_DetectFregrance",    -- Fragrant Alarum
    [99] = "Job09_SmokeDragon",        -- Dragon's Delusion
    -- Job09_SmokeGiants crashes the game to desktop - never test it, even by accident.
    -- Dark Arisen DLC (id 118/119) - taken from another mod, not verified by
    -- us (new fields, not in our old anomalous-field list):
    [118] = "Job09_HealingSmoke",   -- Curing Cloud (per True Warfarer)
    [119] = "Job09_FocusAimSmoke",  -- Diverting Fume (per True Warfarer)
    -- 15.10: True Warfarer (DAV4) attributes id 120 to exactly
    -- Job09_SmokeGiants ("Dream Giant's Pommel") - NOT added/un-forbidden:
    -- this field previously crashed the whole game, test ONLY on a
    -- separate/backup save, if at all.
}

local DIRECT_CAST_MIN_STAMINA = 80
local DIRECT_CAST_INTERVAL_FRAMES = 40

local warnedMissingCustomId = {}
local directCastCooldownLeft = { 0, 0, 0, 0, 0, 0 }

local customSkillIdCache = {}
local function resolveCustomSkillId(fieldName)
    local cached = customSkillIdCache[fieldName]
    if cached ~= nil then return cached end
    local ok, value = pcall(function()
        local t = sdk.find_type_definition("app.HumanCustomSkillID")
        if not t then return nil end
        local field = t:get_field(fieldName)
        if not field then return nil end
        return field:get_data(nil)
    end)
    local resolved = ok and value or nil
    if resolved ~= nil then
        customSkillIdCache[fieldName] = resolved
        log.info("[TWINWV] Extra Skills Direct Cast: resolved app.HumanCustomSkillID." .. fieldName .. " = " .. tostring(resolved))
    end
    return resolved
end

-- Fields confirmed to hang/freeze the character or crash the game on cast.
-- None of these are ever assigned in SKILL_CUSTOM_ID, so this check is a
-- second line of defense against a future mapping mistake - castCustomSkill
-- always checks it before calling requestCustomSkill, regardless of what
-- SKILL_CUSTOM_ID says.
local FORBIDDEN_CUSTOM_SKILL_FIELDS = {
    Job04_AdvancedTrigger = true,
    Job04_CarpetBombing = true,
    Job05_DashSlashUp = true,
    Job05_ScarletVow = true,
    Job07_MirageDance = true,
    Job07_GravityField = true,
    Job08_ShadowBinding = true,
    Job09_SmokeGiants = true, -- crashes the entire game, not just the character
}

local warnedNoCustomSkillAction = {}
local SKILL_SLOT_RESTORE_DELAY_FRAMES = 10
local pendingSkillSlotRestore = {}

local function tickPendingSkillSlotRestore()
    for slot, pending in pairs(pendingSkillSlotRestore) do
        pending.framesLeft = pending.framesLeft - 1
        if pending.framesLeft <= 0 then
            local skillCtx = getSkillContext(getHuman(getPlayer()))
            if skillCtx then
                writeSkillSlot(skillCtx, pending.job, pending.skillId, slot - 1)
            end
            pendingSkillSlotRestore[slot] = nil
        end
    end
end

-- The app.HumanCustomSkillID value the game passes when it casts a skill
-- EQUALS the skill id (seen in game for all DLC skills: 102
-- Job01_RushAttack, 104 Job02_FlightShot, 106 Job03_DivineShot, 108
-- Job04_AdvancedTrigger, 110 Job05_DashSlashUp, 112 Job06_ThunderWhip, 114
-- Job07_MirageDance, 116 Job08_ShadowBinding, 119 Job09_FocusAimSmoke). So
-- the "forbidden" fields in FORBIDDEN_CUSTOM_SKILL_FIELDS are DLC skills -
-- they hung the character when cast before the DLC existed. Skills without
-- an entry in SKILL_CUSTOM_ID are cast straight by id (fieldName = a number),
-- after being put into a real slot like all others. Skills you hold or press
-- again only do their first stage that way (the menu says so).
local QC = {} -- one table: the main chunk's 200-local limit

-- Quick Cast must not bypass Silence: it blocks incanted spells (Begin
-- Incanting) - Mage and Sorcerer skills. Status check as in _NickCore
-- (Utils/Status.lua): StatusConditionCtrl.IsStatusConditionActive(11, false).
QC.SILENCE_ID = 11
function QC.isIncantSkill(skillId)
    if not QC.incant then
        QC.incant = {}
        for _, j in ipairs({ 3, 6 }) do
            for _, sid in ipairs(VOCATION_SKILLS[j] or {}) do QC.incant[sid] = true end
        end
    end
    return QC.incant[skillId] == true
end
function QC.isSilenced(player)
    local ok, on = pcall(function()
        return player:get_field("<StatusConditionCtrl>k__BackingField"):call("IsStatusConditionActive", QC.SILENCE_ID, false)
    end)
    return ok and on == true
end

local function castCustomSkill(player, fieldName)
    if type(fieldName) == "number" then
        local id = fieldName
        local ok, err = pcall(function()
            getHuman(player):call("get_HumanActionSelector()"):requestCustomSkill(id, 0)
        end)
        if not ok then log.warn("[TWINWV] Quick Cast: requestCustomSkill(" .. id .. ") failed: " .. tostring(err)) end
        return ok
    end
    if FORBIDDEN_CUSTOM_SKILL_FIELDS[fieldName] then
        log.warn("[TWINWV] Extra Skills Direct Cast: REFUSING to cast app.HumanCustomSkillID." ..
            tostring(fieldName) .. " - this field is on the hard block-list (known to hang/crash), " ..
            "regardless of what SKILL_CUSTOM_ID says.")
        return false
    end
    local id = resolveCustomSkillId(fieldName)
    if id == nil then
        log.warn("[TWINWV] Extra Skills Direct Cast: could not resolve app.HumanCustomSkillID." .. tostring(fieldName))
        return false
    end
    local ok, err = pcall(function()
        local human = getHuman(player)
        local selector = human:call("get_HumanActionSelector()")
        local actionOk, action = pcall(function() return selector:getCustomSkillAction(id, 0) end)
        if actionOk and not action and not warnedNoCustomSkillAction[fieldName] then
            warnedNoCustomSkillAction[fieldName] = true
            log.warn("[TWINWV] Extra Skills Direct Cast: getCustomSkillAction(app.HumanCustomSkillID." ..
                fieldName .. "=" .. tostring(id) .. ") returned nothing even though the skill should now be equipped - id is likely wrong for this skill.")
        end
        selector:requestCustomSkill(id, 0)
    end)
    if not ok then
        log.warn("[TWINWV] Extra Skills Direct Cast: requestCustomSkill(\"" .. tostring(fieldName) .. "\") failed: " .. tostring(err))
    end
    return ok
end

-- requestCustomSkill only fires for a skill that's actually equipped in one
-- of the 6 base slots - getCustomSkillAction silently returns nothing
-- otherwise, with no error. So a direct cast temporarily swaps the target
-- skill into its real slot with skillCtx:setSkill(), casts it, then restores
-- whatever was there before after SKILL_SLOT_RESTORE_DELAY_FRAMES (too short
-- cuts the animation short, too long holds someone else's skill in a real
-- slot for longer than necessary).
local function attemptDirectCast(slot, job, skillId, fieldName, player)
    local staminaOk, stamina = pcall(function()
        return player:call("get_StaminaManager()"):call("get_RemainingAmount()")
    end)
    if not (staminaOk and stamina and stamina >= DIRECT_CAST_MIN_STAMINA) then return false end

    local skillCtx = getSkillContext(getHuman(player))
    if not skillCtx then return false end
    local snapOk, originalSkillId = pcall(function() return skillCtx:getSkillID(job, slot - 1) end)
    -- Pressed again before the slot was restored: the slot still holds the
    -- previous Extra skill, so take the real original from the pending
    -- restore (otherwise the Extra skill would stay in the base slot).
    local prev = pendingSkillSlotRestore[slot]
    if prev and prev.job == job then snapOk, originalSkillId = true, prev.skillId end
    local setOk = writeSkillSlot(skillCtx, job, skillId, slot - 1)
    if setOk and castCustomSkill(player, fieldName) then
        pendingSkillSlotRestore[slot] = {
            job = job,
            skillId = snapOk and originalSkillId or 0,
            framesLeft = SKILL_SLOT_RESTORE_DELAY_FRAMES,
        }
        return true
    elseif setOk then
        writeSkillSlot(skillCtx, job, (snapOk and originalSkillId) or 0, slot - 1)
    end
    return false
end

local DRAW_WEAPON_WAIT_FRAMES = 5
local pendingDirectCast = {}

local function requestDrawWeapon(player)
    pendingForceDrawWeapon = true
end

local function tickPendingDirectCast()
    for slot, pending in pairs(pendingDirectCast) do
        pending.framesLeft = pending.framesLeft - 1
        if pending.framesLeft <= 0 then
            local player = getPlayer()
            if player then
                if attemptDirectCast(slot, pending.job, pending.skillId, pending.fieldName, player) then
                    directCastCooldownLeft[slot] = DIRECT_CAST_INTERVAL_FRAMES
                end
            end
            pendingDirectCast[slot] = nil
        end
    end
end

local function handleExtraSkillsDirectCast()
    tickPendingSkillSlotRestore()
    tickPendingDirectCast()
    if not hotkeys or not Config.General.ExtraSkillsDirectCast then return end
    local job = getCurrentJob()
    if not job or not VOCATIONS[job] then return end
    local entry = Config.Vocations[job]

    for slot = 1, NUM_BASE_SLOTS do
        if directCastCooldownLeft[slot] > 0 then
            directCastCooldownLeft[slot] = directCastCooldownLeft[slot] - 1
        elseif weaponSlotConsumedThisFrame[slot] then
            -- This same key was already claimed by Weapon Slots this frame
            -- (see the comment on weaponSlotConsumedThisFrame) - don't cast
            -- on top of it.
        elseif hotkeys.check_hotkey("TWINWV_ExtraDirect" .. slot, false, true)
            and isHotkeyUncontested("TWINWV_ExtraDirect" .. slot) then
            local skillId = entry.ExtraSkillsA[slot] or 0
            if skillId ~= 0 then
                local fieldName = SKILL_CUSTOM_ID[skillId] or skillId -- by id, see QC
                local silenced = QC.isIncantSkill(skillId) and QC.isSilenced(getPlayer())
                local scCast = (not silenced) and SC.skill(skillId) and SC.cast(skillId)
                if silenced then
                    -- Silence: no incanted spell, just like the game
                    directCastCooldownLeft[slot] = DIRECT_CAST_INTERVAL_FRAMES
                elseif scCast ~= nil then
                    -- a Skill Creator skill - cast by Skill Creator itself
                    -- (false - not possible right now: stamina/animation)
                    directCastCooldownLeft[slot] = DIRECT_CAST_INTERVAL_FRAMES
                elseif not fieldName then
                    if not warnedMissingCustomId[skillId] then
                        warnedMissingCustomId[skillId] = true
                        log.warn("[TWINWV] Extra Skills Direct Cast: no HumanCustomSkillID mapped yet for skill id " ..
                            tostring(skillId) .. " (\"" .. skillName(skillId) .. "\") - add it to SKILL_CUSTOM_ID.")
                    end
                else
                    local blocked = directCastNodeName == "Job04.Job04_NormalAttack.Job04_Dodge"
                        or directCastNodeName == "Job07.Job07_SkillAttack.Job07_CS07.Job07_SkyDive"
                    local player = getPlayer()
                    if player and not blocked then
                        requestDrawWeapon(player)
                        pendingDirectCast[slot] = {
                            job = job, skillId = skillId, fieldName = fieldName,
                            framesLeft = DRAW_WEAPON_WAIT_FRAMES,
                        }
                        directCastCooldownLeft[slot] = DIRECT_CAST_INTERVAL_FRAMES
                    end
                end
            end
        end
    end
end

installAutoRememberHook()

re.on_frame(function()
    local ok, err = pcall(function()
        tickActionModifierCache()
        handleVocationSwitchHotkeys()
        Cycle.handle()
        RadialWheel.tick()
        handleExtraSkills()
        -- Weapon Slots BEFORE Extra Skills Direct Cast: it marks which keys
        -- it claimed this frame (weaponSlotConsumedThisFrame), and Direct
        -- Cast skips those same keys - see the comment on
        -- weaponSlotConsumedThisFrame above.
        handleWeaponSlotHotkeys()
        RingOv.handleHotkeys()
        -- hide / show the Skill Bar
        if hotkeys and Config.SkillBar.Enabled and not isGuiPaused()
            and hotkeys.check_hotkey("TWINWV_SkillBarToggle", false, true) then
            Config.SkillBar.Hidden = not Config.SkillBar.Hidden
            saveConfig()
        end
        handleExtraSkillsDirectCast()
        tickJobRequirementToggles()
        tickPendingWeaponApply()
        tickPendingArmorApply()
        tickPendingRingsApply()
        SpellStock.tick()
        tickRearmWeaponEffectSettle()
        SwitchGate.tick()
    end)
    if not ok then log.error("[TWINWV] on_frame error: " .. tostring(err)) end
end)

local d2dLib = (d2d ~= nil and d2d) or (d2dx ~= nil and d2dx) or nil
local iconImages = {}
local surfaceW, surfaceH = 1920, 1080

local ANCHORS = { "TopLeft", "TopCenter", "TopRight", "CenterLeft", "CenterRight", "BottomLeft", "BottomCenter", "BottomRight" }

-- Offsets are in % of half the screen (from the anchor toward the screen
-- centre / the next anchor), so a position looks the same at any
-- resolution. On the axis where the anchor is centred (X for
-- TopCenter/BottomCenter, Y for CenterLeft/CenterRight) the range is
-- -100..100 (minus = left/up), otherwise 0..100 inward. Icon size also
-- follows the screen height (Scale 100% = the image's size at 1080p).
local function anchorAxisCentered(anchor)
    return anchor == "TopCenter" or anchor == "BottomCenter", anchor == "CenterLeft" or anchor == "CenterRight"
end

local function resScale()
    return (surfaceH or 1080) / 1080
end

-- pos: a table with Anchor/X/Y in % (Config.Icon or Config.CycleStrip)
local function computeIconPos(iw, ih, pos)
    pos = pos or Config.Icon
    local cX, cY = anchorAxisCentered(pos.Anchor)
    local function clampPct(v, centered)
        v = tonumber(v) or 0
        local lo = centered and -100 or 0
        if v < lo then v = lo elseif v > 100 then v = 100 end
        return v
    end
    local hx = surfaceW / 2 * clampPct(pos.X, cX) / 100
    local hy = surfaceH / 2 * clampPct(pos.Y, cY) / 100
    local W, H = surfaceW, surfaceH
    local a = pos.Anchor
    local x, y
    if a == "TopCenter" then x, y = W / 2 - iw / 2 + hx, hy
    elseif a == "TopRight" then x, y = W - hx - iw, hy
    elseif a == "CenterLeft" then x, y = hx, H / 2 - ih / 2 + hy
    elseif a == "CenterRight" then x, y = W - hx - iw, H / 2 - ih / 2 + hy
    elseif a == "BottomLeft" then x, y = hx, H - hy - ih
    elseif a == "BottomCenter" then x, y = W / 2 - iw / 2 + hx, H - hy - ih
    elseif a == "BottomRight" then x, y = W - hx - iw, H - hy - ih
    else x, y = hx, hy end -- TopLeft
    return x, y
end

-- Wheel drawing (own design): a ring of 9 translucent black sectors with
-- gaps; the pointed sector grows outward and gets a white outline. Icons are
-- the mod's own vocation images (full for the pointed one, -50 for the rest).
-- d2d.ring angles are degrees, 0 = right, clockwise; our 0 = up, hence -90.
-- Older d2d builds without ring fall back to fill_quad slices.
function RadialWheel.drawSector(d, cx, cy, rOut, rIn, startDeg, sweepDeg, color)
    if pcall(d.ring, cx, cy, rOut, rIn, startDeg, sweepDeg, color, true) then return end
    if pcall(d.ring, cx, cy, rOut, rIn, startDeg, sweepDeg, color) then return end
    local parts = math.max(6, math.ceil(sweepDeg / 8))
    for k = 0, parts - 1 do
        local a1 = math.rad(startDeg + sweepDeg * k / parts)
        local a2 = math.rad(startDeg + sweepDeg * (k + 1) / parts)
        pcall(d.fill_quad,
            cx + math.cos(a1) * rIn, cy + math.sin(a1) * rIn,
            cx + math.cos(a1) * rOut, cy + math.sin(a1) * rOut,
            cx + math.cos(a2) * rOut, cy + math.sin(a2) * rOut,
            cx + math.cos(a2) * rIn, cy + math.sin(a2) * rIn,
            color)
    end
end

function RadialWheel.draw()
    if not RadialWheel.open then return end
    local d = d2dLib
    local h = surfaceH
    local cx, cy = surfaceW / 2, h / 2
    local rIn, rOut = h * 0.12, h * 0.29
    local grow = h * 0.035
    local n = #RadialWheel.order
    local step = 360 / n
    local gap = 2.5
    for i, jobId in ipairs(RadialWheel.order) do
        local selected = RadialWheel.sel == jobId
        local centerDeg = (i - 1) * step
        local startDeg = centerDeg - step / 2 + gap / 2 - 90
        local sweepDeg = step - gap
        local outer = rOut + (selected and grow or 0)
        RadialWheel.drawSector(d, cx, cy, outer, rIn, startDeg, sweepDeg, 0xA0000000)
        if selected then
            if not pcall(d.outline_ring, cx, cy, outer, rIn, startDeg, sweepDeg, 3, 0xE6FFFFFF, true) then
                pcall(d.outline_ring, cx, cy, outer, rIn, startDeg, sweepDeg, 3, 0xE6FFFFFF)
            end
        end
        local icon = iconImages[jobId]
        local img = icon and (selected and icon.full or icon.small)
        if img then
            local mid = (rIn + outer) / 2
            local a = math.rad(centerDeg)
            local x, y = cx + math.sin(a) * mid, cy - math.cos(a) * mid
            local size = selected and h * 0.10 or h * 0.075
            local okSize, iw, ih = pcall(function() return img:size() end)
            local k = (okSize and ih and ih > 0) and (size / ih) or 1
            local dw, dh = (okSize and iw or size) * k, (okSize and ih or size) * k
            pcall(d.image, img, x - dw / 2, y - dh / 2, dw, dh)
        end
    end
end

-- Cycling strip: while cycling is on, the cycle vocations in their order
-- instead of the single icon; the one under the cursor (Cycle.target, or
-- the current vocation) is bigger and in full colour. Returns true if drawn.
-- Auto-hide (request from Nexus): the strip / icon stay visible AutoHideSec
-- (slider 1-3 s, default 1.5) after a vocation switch or while cycling with
-- Next/Prev, then fade out over FADE_OUT_SEC. One timer for both, each has
-- its own delay.
Cycle.fade = { job = nil, at = -100 }
Cycle.FADE_OUT_SEC = 0.6
function Cycle.fadeAlpha(autoHide, holdSec)
    local f = Cycle.fade
    local now = os.clock()
    local job = getCurrentJob()
    if job ~= f.job then f.job, f.at = job, now end
    if Cycle.target then f.at = now end
    if not autoHide then return 1 end
    local hold = tonumber(holdSec) or 1.5
    if hold < 1 then hold = 1 elseif hold > 3 then hold = 3 end
    local t = now - f.at
    if t <= hold then return 1 end
    t = t - hold
    if t >= Cycle.FADE_OUT_SEC then return 0 end
    return 1 - t / Cycle.FADE_OUT_SEC
end

-- image with opacity (alpha < 1 - the 5th d2d image parameter)
function Cycle.image(img, x, y, w, h, alpha)
    if alpha >= 1 then
        pcall(d2dLib.image, img, x, y, w, h)
    else
        pcall(d2dLib.image, img, x, y, w, h, alpha)
    end
end

function Cycle.drawStrip(job)
    local cs = Config.CycleStrip
    if not Config.General.EnableVocationCycling or not cs or not cs.Enabled then return false end
    local list = Cycle.list()
    if #list < 2 then return false end
    -- hidden still counts as drawn, so the single icon doesn't show instead
    local alpha = Cycle.fadeAlpha(cs.AutoHide, cs.AutoHideSec)
    if alpha <= 0 then return true end
    local cursor = Cycle.target or job
    local big = (tonumber(cs.Scale) or 40) / 100 * resScale()
    local small = big * (tonumber(cs.InactiveScale) or 70) / 100
    local gap = 8 * big
    local items, totalW, maxH = {}, 0, 0
    for _, e in ipairs(list) do
        local icon = iconImages[e.jobId]
        local sel = e.jobId == cursor
        local img = icon and (sel and icon.full or icon.small)
        if img then
            local okS, iw, ih = pcall(function() return img:size() end)
            if not okS or not iw then iw, ih = 128, 128 end
            local k = sel and big or small
            items[#items + 1] = { img = img, w = iw * k, h = ih * k }
            totalW = totalW + iw * k
            if ih * k > maxH then maxH = ih * k end
        end
    end
    if #items == 0 then return false end
    totalW = totalW + gap * (#items - 1)
    local x, y = computeIconPos(totalW, maxH, cs)
    for _, it in ipairs(items) do
        Cycle.image(it.img, x, y + (maxH - it.h) / 2, it.w, it.h, alpha)
        x = x + it.w + gap
    end
    return true
end

-- Skill Bar (WoW/L2 style): the 6 regular skills + 6 Extra Skills as icon
-- cells on a dark panel (one panel per group, one row or two). The group
-- whose skills are currently in the slots gets a gold frame. Each cell shows
-- the key that casts it (read from the game's own key bindings, or typed in
-- the settings) and a short skill name, since many in-game icons are
-- identical. Icons: images/TWINWV_skills/<Vocation>/<Skill_Name>.png or
-- skill_<id>.png, loaded once in d2d init; missing icon = name only.
-- Text sizes come in fixed steps (key / name / small) that shrink together
-- just enough for the widest label in the step, so nothing overflows.
local SkillBar = { icons = {}, font = nil, cache = { job = nil, at = -1, ids = nil } }

function SkillBar.fileBase(id)
    local name = SKILL_NAME_BY_LANG.en and SKILL_NAME_BY_LANG.en[id]
    if not name or name == "" then return nil end
    name = name:gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    return name
end

function SkillBar.tryImage(path)
    local ok, img = pcall(d2dLib.Image.new, path)
    if not ok or not img then return nil end
    local okS, w = pcall(function() return img:size() end)
    if not okS or not w or w <= 0 then return nil end
    return img
end

function SkillBar.loadIcons()
    SkillBar.icons = {}
    local seen = {}
    local foldersOf, allFolders = {}, {}
    for jobId = 1, 9 do
        local voc = VOCATIONS[jobId]
        local folder = voc and (voc.name:gsub(" ", "_")) or nil
        if folder then
            allFolders[#allFolders + 1] = folder
            for _, id in ipairs(VOCATION_SKILLS[jobId] or {}) do
                foldersOf[id] = foldersOf[id] or {}
                table.insert(foldersOf[id], folder)
            end
        end
    end
    for id, own in pairs(foldersOf) do
        if id ~= 0 then
            local order, used = {}, {}
            for _, f in ipairs(own) do order[#order + 1] = f; used[f] = true end
            for _, f in ipairs(allFolders) do if not used[f] then order[#order + 1] = f end end
            local base = SkillBar.fileBase(id)
            local img
            for _, name in ipairs({ base, "skill_" .. id }) do
                if name then
                    for _, f in ipairs(order) do
                        img = SkillBar.tryImage("TWINWV_skills/" .. f .. "/" .. name .. ".png")
                        if img then break end
                    end
                    img = img or SkillBar.tryImage("TWINWV_skills/" .. name .. ".png")
                end
                if img then break end
            end
            if img then SkillBar.icons[id] = img end
        end
    end
    -- Skills from Skill Creator mods (ids from its registry, not in our lists):
    -- TWINWV_skills/SkillCreator/ (or Trickster/, or the root folder) -
    -- skill_<ID>.png or <Skill_Name>.png (spaces and symbols -> "_", like the
    -- regular ones). The ids and names are written to the log once.
    local scIds, seenSc = {}, {}
    for _, reg in ipairs(SC.registries()) do
        for id in pairs(reg.customSkills or {}) do
            if type(id) == "number" and not seenSc[id] then scIds[#scIds + 1] = id; seenSc[id] = true end
        end
    end
    table.sort(scIds)
    for _, id in ipairs(scIds) do
        if not SkillBar.icons[id] then
            local nm = SC.skillName(id)
            local names = { "skill_" .. id }
            if nm then
                local fb = nm:gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
                if fb ~= "" then names[#names + 1] = fb end
                log.info("[TWINWV] Skill Creator / VSB skill " .. id .. " = " .. nm .. " (icon: skill_" .. id .. ".png" .. (fb ~= "" and (" or " .. fb .. ".png") or "") .. ")")
            end
            local img
            for _, name in ipairs(names) do
                for _, dir in ipairs({ "TWINWV_skills/SkillCreator/", "TWINWV_skills/Trickster/", "TWINWV_skills/" }) do
                    img = SkillBar.tryImage(dir .. name .. ".png")
                    if img then break end
                end
                if img then break end
            end
            if img then SkillBar.icons[id] = img end
        end
    end
    SkillBar.fonts = {}
    for px = 8, 40 do
        local okF, font = pcall(d2dLib.Font.new, "Tahoma", px, true)
        if okF and font then SkillBar.fonts[px] = font end
    end
    -- Ring Presets HUD matches the game's own UI: a serif font (Palatino
    -- Linotype ships with Windows; if missing DirectWrite substitutes one)
    RingOv.fonts = {}
    for px = 10, 40 do
        local okF, font = pcall(d2dLib.Font.new, "Palatino Linotype", px, false)
        if okF and font then RingOv.fonts[px] = font end
    end
end


function SkillBar.fontFor(px)
    local fonts = SkillBar.fonts or {}
    local want = math.floor(px)
    if want > 40 then want = 40 end
    for sz = want, 8, -1 do
        if fonts[sz] then return fonts[sz] end
    end
    for sz = 8, 40 do
        if fonts[sz] then return fonts[sz] end
    end
    return nil
end

function SkillBar.text(d, font, s, x, y, color)
    pcall(d.text, font, s, x + 1, y + 1, 0xFF000000)
    pcall(d.text, font, s, x, y, color)
end

function SkillBar.nameLabel(id)
    local mode = Config.SkillBar.NameMode or "Word"
    if mode == "Off" then return "" end
    local own = Config.SkillLabels and Config.SkillLabels[tostring(id)]
    if own and own ~= "" then return own end
    return SkillBar.firstWord(id)
end

SkillBar.SHORT_EN = {
    [1] = "Burst", [2] = "Cloud", [3] = "Pummel", [4] = "Moon", [5] = "Launch", [6] = "Drum", [7] = "Skewer", [8] = "Sweep",
    [9] = "Guard", [10] = "Vengeful", [11] = "Divine", [12] = "Fury", [13] = "Manifold", [14] = "Cascade", [15] = "Deathly", [16] = "Lyncean",
    [17] = "Erupting", [18] = "Deluging", [19] = "Incend.", [20] = "Nocuous", [21] = "Tempest", [22] = "Spiral", [23] = "Heavenly", [24] = "Flagration",
    [25] = "Levin", [26] = "Frigor", [27] = "Spellhold", [28] = "Palladium", [29] = "Fire", [30] = "Ice", [31] = "Lightning", [32] = "Empyrean",
    [33] = "Halidom", [34] = "Celerity", [35] = "Succor", [36] = "Solemnity", [37] = "Paean", [38] = "Cutting", [39] = "Skull", [40] = "Implicate",
    [41] = "Kill", [42] = "Feint", [43] = "Quarter", [44] = "Ignited", [45] = "Smoke", [46] = "Powder", [47] = "Leap", [48] = "Veil",
    [49] = "Plunder", [50] = "Lunge", [51] = "Razing", [52] = "Sunder", [53] = "Windstorm", [54] = "Diluvian", [55] = "Tidal", [56] = "Roar",
    [57] = "Mountain", [58] = "Lash", [59] = "Inspirit", [60] = "Catapult", [61] = "Arc", [62] = "Salamander", [63] = "Hagol", [64] = "Thunder",
    [65] = "Decanter", [66] = "Seism", [67] = "Augural", [68] = "Meteoron", [69] = "Maelstrom", [70] = "Offringe", [71] = "Heven", [72] = "Ravinour",
    [73] = "Foin", [74] = "Shelde", [75] = "Seching", [76] = "Feste", [77] = "Magike", [78] = "Charge", [79] = "Furie", [80] = "Blazefang",
    [81] = "Orb", [82] = "Frost", [83] = "Arctic", [84] = "Boltchain", [85] = "Ricochet", [86] = "Lifetaking", [87] = "Recovery", [88] = "Fortalice",
    [89] = "Soporific", [90] = "Sagittate", [91] = "Martyr's", [92] = "Divider", [93] = "Terrace", [94] = "Visitant", [95] = "Shroud", [96] = "Effigy",
    [97] = "Aromatic", [98] = "Alarum", [99] = "Delusion", [101] = "Pyre", [102] = "Hurricane", [103] = "Precision", [104] = "Kite", [105] = "Cloudburst",
    [106] = "Exalted", [107] = "Benedict", [108] = "Fanged", [109] = "Caper", [110] = "Cleave", [111] = "Pact", [112] = "Brontide", [113] = "Chilling",
    [114] = "Bataille", [115] = "Hindringe", [116] = "Shade", [117] = "Pentad", [118] = "Vapor", [119] = "Rousing", [120] = "Pommel",
}

SkillBar.SKIP_WORDS = {
    ["Великий"] = true, ["Великая"] = true, ["Великое"] = true, ["Великие"] = true,
    ["Верховный"] = true, ["Верховная"] = true, ["Верховное"] = true, ["Удар"] = true,
    ["de"] = true, ["du"] = true, ["des"] = true, ["la"] = true, ["le"] = true, ["les"] = true,
    ["of"] = true, ["the"] = true, ["and"] = true, ["High"] = true,
}

function SkillBar.firstWord(id)
    local lang = Config.Language or "en"
    local localName = SKILL_NAME_BY_LANG[lang] and SKILL_NAME_BY_LANG[lang][id]
    local w
    if (lang == "en" or not localName or localName == "") and SkillBar.SHORT_EN[id] then
        w = SkillBar.SHORT_EN[id]
    else
        local best = ""
        for word in (skillName(id) or ""):gmatch("%S+") do
            if not SkillBar.SKIP_WORDS[word] and not word:match("^%d+$")
                and SkillBar.ulen(word) > SkillBar.ulen(best) then
                best = word
            end
        end
        w = (best ~= "") and best or ((skillName(id) or ""):match("^(%S+)") or "")
    end
    if SkillBar.ulen(w) > 10 then w = SkillBar.usub(w, 9) .. "." end
    return w
end

function SkillBar.ulen(s)
    local ok, n = pcall(utf8.len, s)
    return (ok and n) or #s
end

function SkillBar.usub(s, n)
    local ok, cut = pcall(utf8.offset, s, n + 1)
    if ok and cut then return s:sub(1, cut - 1) end
    return s:sub(1, n)
end

function SkillBar.shortKey(k)
    if not k or k == "" or k == "None" or k == "[Not Bound]" then return "" end
    k = tostring(k)
    local MOUSE = { LButton = "LMB", RButton = "RMB", MButton = "MMB", XButton1 = "M4", XButton2 = "M5" }
    if MOUSE[k] then return MOUSE[k] end
    k = k:gsub("^Alpha", ""):gsub("^NumPad", "N"):gsub("^L(%u%l+)$", "%1"):gsub("^R(%u%l+)$", "%1")
    k = k:gsub("^Control$", "Ctrl")
    return k
end

-- jonanoj): app.UserInputManager -> get_KeyBindController ->
SkillBar.gk = { at = -10, slots = nil, enumAct = nil, enumKey = nil }

function SkillBar.enumNames(typename)
    local t = sdk.find_type_definition(typename)
    local ids = {}
    if not t then return ids end
    for _, f in ipairs(t:get_fields() or {}) do
        if f:is_static() then
            local ok, v = pcall(function() return f:get_data(nil) end)
            if ok and v ~= nil then ids[v] = f:get_name() end
        end
    end
    return ids
end

function SkillBar.keyBindTable()
    local uim = sdk.get_managed_singleton("app.UserInputManager")
    local kbc = uim and uim:call("get_KeyBindController")
    return kbc and kbc:call("getCurrentKeyBindSettingTable")
end

function SkillBar.forEachKeyBind(fn)
    local gk = SkillBar.gk
    gk.enumAct = gk.enumAct or SkillBar.enumNames("app.CharacterInput.Action")
    gk.enumKey = gk.enumKey or SkillBar.enumNames("via.hid.KeyboardKey")
    local tbl = SkillBar.keyBindTable()
    if not tbl then return false end
    local keys = tbl:call("get_Keys")
    local en = keys and keys:call("GetEnumerator")
    if not en then return false end
    while en:call("MoveNext") do
        local hash = en:call("get_Current")
        local kb = tbl:call("get_Item", hash)
        if kb then
            local act = kb:call("get_CharacterCommand")
            fn(gk.enumAct[act] or tostring(act), gk.enumKey[kb:call("get_PrimaryKey")] or "",
                gk.enumKey[kb:call("get_SecondaryKey")] or "", kb:call("get_WithCustomShift"), kb)
        end
    end
    return true
end

function SkillBar.gameKeys()
    local gk = SkillBar.gk
    local now = os.clock()
    if now - gk.at < 2 then return gk.slots end
    gk.at = now
    local found = {}
    local ok = pcall(SkillBar.forEachKeyBind, function(act, k1, k2)
        local n = act:match("Skill%D*(%d+)$")
        if n and act:find("Skill") then found[#found + 1] = { n = tonumber(n), key = (k1 ~= "" and k1 or k2) } end
    end)
    if not ok or #found == 0 then gk.slots = nil; return nil end
    table.sort(found, function(a, b) return a.n < b.n end)
    local slots = {}
    for i = 1, math.min(#found, NUM_BASE_SLOTS) do slots[i] = SkillBar.shortKey(found[i].key) end
    gk.slots = slots
    return slots
end

function SkillBar.dumpGameKeys()
    local n = 0
    local ok, err = pcall(SkillBar.forEachKeyBind, function(act, k1, k2, shift)
        n = n + 1
        log.info(string.format("[TWINWV] KEYBIND action=%s primary=%s secondary=%s withSwitchWeaponSkill=%s",
            tostring(act), tostring(k1), tostring(k2), tostring(shift)))
    end)
    log.info("[TWINWV] KEYBIND dump: " .. n .. " entries" .. (ok and "" or (" - error: " .. tostring(err))))
    SkillBar.gk.at = -10
end

function SkillBar.comboLabel(action, fallbackKey)
    local ok, str = pcall(function() return hotkeys and hotkeys.get_button_string and hotkeys.get_button_string(action) end)
    if not ok or type(str) ~= "string" or str == "" then return SkillBar.shortKey(fallbackKey) end
    local parts = {}
    for part in str:gmatch("[^+]+") do
        local sk = SkillBar.shortKey((part:gsub("^%s+", ""):gsub("%s+$", "")))
        if sk ~= "" then parts[#parts + 1] = sk end
    end
    return table.concat(parts, "+")
end

function SkillBar.baseIds(job)
    if extraSkillsState ~= "none" and extraSkillsSnapshot then return extraSkillsSnapshot end
    local c = SkillBar.cache
    local now = os.clock()
    -- Quick Cast briefly puts an Extra skill into a real slot and restores
    -- the original a few frames later (pendingSkillSlotRestore). Don't show
    -- that swap on the bar: keep the cache, or use the original ids.
    local swapping = next(pendingSkillSlotRestore) ~= nil
    if swapping and c.job == job and c.ids then return c.ids end
    if c.job ~= job or not c.ids or now - c.at > 0.25 then
        local ids = getCurrentEquippedSkills(job)
        if ids and swapping then
            local copy = {}
            for k, v in pairs(ids) do copy[k] = v end
            for slot, pending in pairs(pendingSkillSlotRestore) do
                if pending.job == job then copy[slot] = pending.skillId end
            end
            ids = copy
        end
        c.ids = ids or c.ids
        c.job, c.at = job, now
    end
    return c.ids or {}
end

SkillBar.COLORS = {
    panel = 0xC0141414, panelEdge = 0xFF3C3C3C, activeEdge = 0xFFC9A55A,
    cell = 0xFF1C1C1C, cellEmpty = 0xFF070707,
    bevelDark = 0xFF000000, bevelLight = 0xFF6A6A6A, bevelLightEmpty = 0xFF262626,
    dim = 0x80000000, name = 0xFFFFFFFF, key = 0xFFFFD27F, stocked = 0xFFFFE040,
}

SkillBar.TIER = { KEY = 0.27, NAME = 0.20, SMALL = 0.14 }

SkillBar.fit = {}
SkillBar.fitCache = {}

function SkillBar.textWidth(s, px)
    local f = SkillBar.fontFor(px)
    if f then
        local ok, w = pcall(function() return f:measure(s) end)
        if ok and type(w) == "number" then return w end
    end
    return SkillBar.ulen(s) * px * 0.62
end

function SkillBar.fitPx(strings, px, maxW)
    local key = string.format("%.1f|%.1f|", px, maxW) .. table.concat(strings, "\1")
    local cached = SkillBar.fitCache[key]
    if cached then return cached end
    SkillBar.fitCacheN = (SkillBar.fitCacheN or 0) + 1
    if SkillBar.fitCacheN > 256 then SkillBar.fitCache, SkillBar.fitCacheN = {}, 1 end
    while px > 8 do
        local ok = true
        for _, str in ipairs(strings) do
            if SkillBar.textWidth(str, px) > maxW then ok = false; break end
        end
        if ok then break end
        px = px - 1
    end
    SkillBar.fitCache[key] = px
    return px
end

function SkillBar.tierText(d, s, tier, size, x, y, color)
    local f = SkillBar.fontFor(SkillBar.fit[tier] or size * tier)
    if f then SkillBar.text(d, f, s, x, y, color) end
end

function SkillBar.slotName(id)
    local nm = SkillBar.nameLabel(id)
    if not SkillBar.icons[id] and nm == "" then nm = SkillBar.firstWord(id) end
    if SkillBar.ulen(nm) > 14 then nm = SkillBar.usub(nm, 13) .. "." end
    return nm
end

-- High Spellhold (id 27) with a stored spell shows the STORED spell's icon
-- and label (the player's own label or the default one) in yellow. The cache
-- is per vocation being drawn; while SpellStock hasn't restored the spell
-- after a switch yet (pendingJob), the saved one is shown right away.
SkillBar.SPELLHOLD_ID = 27
SkillBar.stockCache = { at = -1, id = 0, job = nil }
function SkillBar.stockedFor(id)
    if id ~= SkillBar.SPELLHOLD_ID then return nil end
    local job = SkillBar.drawJob or getCurrentJob()
    if SpellStock.pendingJob and SpellStock.pendingJob == job then
        local v = SpellStock.saved[job]
        if v and v ~= 0 then return v end
        return nil
    end
    local c = SkillBar.stockCache
    local now = os.clock()
    if c.job ~= job or now - c.at > 0.1 then
        c.at, c.id, c.job = now, 0, job
        local f = SpellStock.FIELD[job]
        local ctx = f and SpellStock.ctx()
        if ctx then
            local ok, v = pcall(function() return ctx[f] end)
            if ok and type(v) == "number" then c.id = v end
        end
    end
    if c.id ~= 0 then return c.id end
    return nil
end

-- id actually drawn in the cell, its label and the "stored" flag
function SkillBar.display(id)
    local stocked = SkillBar.stockedFor(id)
    local sid = stocked or id
    local nm = SkillBar.slotName(sid)
    -- show the stored spell's name even with NameMode=Off, otherwise it
    -- isn't visible that this is Spellhold and not a regular skill
    if stocked and nm == "" then
        nm = SkillBar.firstWord(sid)
        if SkillBar.ulen(nm) > 14 then nm = SkillBar.usub(nm, 13) .. "." end
    end
    return sid, nm, stocked ~= nil
end

function SkillBar.computeFit(size, groups)
    local byTier = {}
    local function add(tier, str)
        if str == "" then return end
        byTier[tier] = byTier[tier] or {}
        table.insert(byTier[tier], str)
    end
    for _, g in ipairs(groups) do
        for i = 1, g.n do
            local id = g.ids[i]
            if id and id ~= 0 then
                local _, nm = SkillBar.display(id)
                add(SkillBar.nameTier(nm), nm)
                if Config.SkillBar.ShowKeys then
                    local lb = g.labelFn(i)
                    add(SkillBar.keyTier(lb) .. "k", lb)
                end
            end
        end
    end
    local pad = math.max(2, size * 0.06)
    SkillBar.fit = {}
    for tierKey, strs in pairs(byTier) do
        local isKey = type(tierKey) == "string"
        local tier = isKey and tonumber((tierKey:gsub("k$", ""))) or tierKey
        local px = SkillBar.fitPx(strs, size * tier, isKey and (size - 6) or (size - pad * 2 - 1))
        SkillBar.fit[isKey and tierKey or tier] = px
    end
end

function SkillBar.keyTier(label)
    if label:find("+", 1, true) then return SkillBar.TIER.SMALL end
    return (SkillBar.ulen(label) <= 5) and SkillBar.TIER.KEY or SkillBar.TIER.SMALL
end

function SkillBar.nameTier(name)
    return (SkillBar.ulen(name) <= 10) and SkillBar.TIER.NAME or SkillBar.TIER.SMALL
end

function SkillBar.drawSlot(d, x, y, size, id, label, active)
    local C = SkillBar.COLORS
    local empty = not id or id == 0
    local A = SkillBar.A
    pcall(d.fill_rect, x, y, size, size, A(empty and C.cellEmpty or C.cell))
    local pad = math.max(2, size * 0.06)
    if not empty then
        local sid, nm, stocked = SkillBar.display(id)
        local img = SkillBar.icons[sid]
        if img then
            local op = (tonumber(Config.SkillBar.Opacity) or 100) / 100
            if op >= 1 then
                pcall(d.image, img, x + pad, y + pad, size - pad * 2, size - pad * 2)
            else
                pcall(d.image, img, x + pad, y + pad, size - pad * 2, size - pad * 2, op)
            end
        end
        if nm ~= "" then
            local tier = SkillBar.nameTier(nm)
            local px = SkillBar.fit[tier] or size * tier
            local f = SkillBar.fontFor(px)
            if f then SkillBar.text(d, f, nm, x + pad, y + size - pad - px * 1.25, stocked and C.stocked or C.name) end
        end
        if not active then pcall(d.fill_rect, x, y, size, size, A(C.dim)) end
    end
    pcall(d.outline_rect, x, y, size, size, 1, A(C.bevelDark))
    pcall(d.outline_rect, x + 1, y + 1, size - 2, size - 2, 1, A(empty and C.bevelLightEmpty or C.bevelLight))
    if not empty and label ~= "" and Config.SkillBar.ShowKeys then
        local kt = SkillBar.keyTier(label)
        local f = SkillBar.fontFor(SkillBar.fit[kt .. "k"] or size * kt)
        if f then SkillBar.text(d, f, label, x + 3, y + 2, C.key) end
    end
end

function SkillBar.A(color)
    local k = (tonumber(Config.SkillBar.Opacity) or 100) / 100
    if k >= 1 then return color end
    local a = math.floor(((color >> 24) & 0xFF) * k + 0.5)
    return (a << 24) | (color & 0xFFFFFF)
end

SkillBar.validCache = {}

function SkillBar.validIds(job)
    local c = SkillBar.validCache[job]
    local now = os.clock()
    if not c or now - c.at > 3 then
        local set = {}
        local ok, _, ids = pcall(skillOptionsForJob, job)
        if ok and type(ids) == "table" then
            for _, id in ipairs(ids) do set[id] = true end
        else
            for _, id in ipairs(VOCATION_SKILLS[job] or {}) do set[id] = true end
        end
        c = { set = set, at = now }
        SkillBar.validCache[job] = c
    end
    return c.set
end

function SkillBar.usedCount(ids)
    local n = 0
    for i = 1, NUM_BASE_SLOTS do
        if ids[i] and ids[i] ~= 0 then n = i end
    end
    return n
end

function SkillBar.groupWidth(n, size, gap, edge)
    if n == 0 then return 0 end
    return edge * 2 + size * n + gap * (n - 1)
end

function SkillBar.drawGroup(d, x, y, ids, n, labelFn, active, size, gap, edge)
    if n == 0 then return end
    local C = SkillBar.COLORS
    local w, h = SkillBar.groupWidth(n, size, gap, edge), size + edge * 2
    pcall(d.fill_rect, x, y, w, h, SkillBar.A(C.panel))
    pcall(d.outline_rect, x, y, w, h, active and 2 or 1, SkillBar.A(active and C.activeEdge or C.panelEdge))
    for i = 1, n do
        SkillBar.drawSlot(d, x + edge + (i - 1) * (size + gap), y + edge, size, ids[i], labelFn(i), active)
    end
end

function SkillBar.draw(job)
    SkillBar.drawJob = job
    local sb = Config.SkillBar
    if not sb or not sb.Enabled or sb.Hidden then return end
    local d = d2dLib
    local base = SkillBar.baseIds(job)
    local rawExtra = (Config.Vocations[job] and Config.Vocations[job].ExtraSkillsA) or {}
    local valid = SkillBar.validIds(job)
    local extra = {}
    for i = 1, NUM_BASE_SLOTS do
        local id = rawExtra[i]
        extra[i] = (id and id ~= 0 and valid[id]) and id or 0
    end
    local extraActive = extraSkillsState ~= "none"
    local size = 48 * (tonumber(sb.Scale) or 100) / 100 * resScale()
    local gap = math.max(1, size * 0.04)
    local edge = math.max(2, size * 0.08)
    local groupGap = size * 0.35
    local keys = sb.Keys or {}
    local game = sb.GameKeys and SkillBar.gameKeys() or nil
    local function baseLabel(i)
        if game and game[i] and game[i] ~= "" then return game[i] end
        return SkillBar.shortKey(keys[i])
    end
    local function extraLabel(i)
        if Config.General.ExtraSkillsDirectCast then
            return SkillBar.comboLabel("TWINWV_ExtraDirect" .. i, Config.ExtraDirectHotkeys["Slot" .. i])
        end
        local b = baseLabel(i)
        if b == "" then return "" end
        local parts = {}
        for _, pair in ipairs({ { "TWINWV_ExtraBase", Config.ExtraSkillHotkeys.Base }, { "TWINWV_ExtraSubA", Config.ExtraSkillHotkeys.SubA } }) do
            local sk = SkillBar.comboLabel(pair[1], pair[2])
            if sk ~= "" then parts[#parts + 1] = sk end
        end
        parts[#parts + 1] = b
        local full = table.concat(parts, "+")
        if SkillBar.textWidth(full, 8) > size - 6 then
            for k = 1, #parts - 1 do
                parts[k] = ({ Ctrl = "C", Alt = "A", Shift = "S" })[parts[k]] or parts[k]
            end
            return table.concat(parts, "+")
        end
        return full
    end
    local nB, nE = SkillBar.usedCount(base), SkillBar.usedCount(extra)
    if nB == 0 and nE == 0 then return end
    SkillBar.computeFit(size, { { ids = base, n = nB, labelFn = baseLabel }, { ids = extra, n = nE, labelFn = extraLabel } })
    local wB, wE = SkillBar.groupWidth(nB, size, gap, edge), SkillBar.groupWidth(nE, size, gap, edge)
    local rowH = size + edge * 2
    if sb.Layout ~= "OneRow" then
        local both = nB > 0 and nE > 0
        local totalW = math.max(wB, wE)
        local totalH = both and (rowH * 2 + groupGap * 0.5) or rowH
        local x0, y0 = computeIconPos(totalW, totalH, sb)
        SkillBar.drawGroup(d, x0, y0, extra, nE, extraLabel, extraActive, size, gap, edge)
        SkillBar.drawGroup(d, x0, y0 + ((nE > 0) and (rowH + groupGap * 0.5) or 0), base, nB, baseLabel, not extraActive, size, gap, edge)
    else
        local between = (nB > 0 and nE > 0) and groupGap or 0
        local x0, y0 = computeIconPos(wB + between + wE, rowH, sb)
        SkillBar.drawGroup(d, x0, y0, base, nB, baseLabel, not extraActive, size, gap, edge)
        SkillBar.drawGroup(d, x0 + wB + between, y0, extra, nE, extraLabel, extraActive, size, gap, edge)
    end
end

-- Ring Presets HUD, styled like the game's control hints: no background,
-- light serif text with a soft shadow, the key in a small dark box. The
-- active preset has gold text and a gold key frame. Mode: Always / Active /
-- Hidden. Opacity applies to everything here (there's no background).
function RingOv.A(color)
    local k = (tonumber(Config.RingPresets.Hud.Opacity) or 100) / 100
    if k >= 1 then return color end
    local a = math.floor(((color >> 24) & 0xFF) * k + 0.5)
    return (a << 24) | (color & 0xFFFFFF)
end

function RingOv.fontFor(px)
    local fonts = RingOv.fonts or {}
    local want = math.floor(px)
    if want > 40 then want = 40 end
    for sz = want, 10, -1 do if fonts[sz] then return fonts[sz] end end
    for sz = 10, 40 do if fonts[sz] then return fonts[sz] end end
    return SkillBar.fontFor(px)
end

function RingOv.measure(font, s, px)
    local ok, w = pcall(function() return font:measure(s) end)
    if ok and type(w) == "number" then return w end
    return SkillBar.ulen(s) * px * 0.55
end

-- text with a soft shadow, like the game's hints
function RingOv.text(d, font, s, x, y, color)
    local A = RingOv.A
    pcall(d.text, font, s, x + 2, y + 2, A(0x60000000))
    pcall(d.text, font, s, x + 1, y + 1, A(0xB0000000))
    pcall(d.text, font, s, x, y, A(color))
end

RingOv.COLORS = {
    name = 0xFFD8D4CC, nameActive = 0xFFF2CF6E,
    keyFill = 0xD0202224, keyEdge = 0xFF6E6E6E, keyLight = 0xFF9A9A9A,
    keyText = 0xFFE6E2DA, keyEdgeActive = 0xFFD9B04E,
}

function RingOv.drawHud()
    local rp = Config.RingPresets
    local h = rp and rp.Hud
    if not h or h.Mode == "Hidden" then return end
    local active = tonumber(rp.Active) or 0
    local rows = {}
    for i = 1, RingOv.MAX do
        local sl = RingOv.slot(i)
        if sl and (h.Mode ~= "Active" or i == active) then
            rows[#rows + 1] = {
                name = (sl.Name and sl.Name ~= "") and sl.Name or ("Rings " .. i),
                key = SkillBar.comboLabel("TWINWV_RingPreset" .. i, rp.Keys["Slot" .. i]),
                on = (i == active),
            }
        end
    end
    if #rows == 0 then return end
    local d = d2dLib
    local C = RingOv.COLORS
    local A = RingOv.A
    local scale = (tonumber(h.Scale) or 100) / 100 * resScale()
    local px = math.floor(24 * scale + 0.5)
    if px < 10 then px = 10 elseif px > 40 then px = 40 end
    local kpx = math.max(10, math.floor(px * 0.72 + 0.5))
    local font, kfont = RingOv.fontFor(px), RingOv.fontFor(kpx)
    if not font or not kfont then return end
    local boxH = math.floor(px * 1.15 + 0.5)
    local rowH = math.floor(px * 1.45 + 0.5)
    local gapX = math.floor(px * 0.35 + 0.5)
    -- key column as wide as the widest key so names line up
    local keyW = 0
    for _, r in ipairs(rows) do
        if r.key ~= "" then
            r.kw = math.max(boxH, RingOv.measure(kfont, r.key, kpx) + kpx * 0.7)
            if r.kw > keyW then keyW = r.kw end
        end
    end
    local nameW = 0
    for _, r in ipairs(rows) do
        local w = RingOv.measure(font, r.name, px)
        if w > nameW then nameW = w end
    end
    local totalW = (keyW > 0 and (keyW + gapX) or 0) + nameW
    local totalH = #rows * rowH
    local x0, y0 = computeIconPos(totalW, totalH, h)
    for n, r in ipairs(rows) do
        local y = y0 + (n - 1) * rowH
        local by = y + (rowH - boxH) / 2
        if r.key ~= "" then
            -- key box: dark, thin frame, light top-left corner
            local bx = x0 + keyW - r.kw
            pcall(d.fill_rect, bx, by, r.kw, boxH, A(C.keyFill))
            pcall(d.outline_rect, bx, by, r.kw, boxH, r.on and 2 or 1, A(r.on and C.keyEdgeActive or C.keyEdge))
            pcall(d.fill_rect, bx + 1, by + 1, math.max(2, r.kw * 0.25), 1, A(C.keyLight))
            pcall(d.fill_rect, bx + 1, by + 1, 1, math.max(2, boxH * 0.25), A(C.keyLight))
            local kw = RingOv.measure(kfont, r.key, kpx)
            RingOv.text(d, kfont, r.key, bx + (r.kw - kw) / 2, by + (boxH - kpx * 1.2) / 2, C.keyText)
        end
        local nx = x0 + (keyW > 0 and (keyW + gapX) or 0)
        RingOv.text(d, font, r.name, nx, y + (rowH - px * 1.25) / 2, r.on and C.nameActive or C.name)
    end
end

if d2dLib then
    d2dLib.register(function()
        surfaceW, surfaceH = d2dLib.surface_size()
        pcall(SkillBar.loadIcons)
        for jobId, voc in pairs(VOCATIONS) do
            local full = d2dLib.Image.new("dd2-" .. voc.image .. ".png")
            local small = d2dLib.Image.new("dd2-" .. voc.image .. "-50.png")
            iconImages[jobId] = { full = full, small = small }
        end
    end, function()
        pcall(RadialWheel.draw)
        if isGuiPaused() then return end
        if SwitchGate.cutscenePoll() then return end -- hidden during cutscenes too
        local job = getCurrentJob()
        if not job or not iconImages[job] then return end

        pcall(SkillBar.draw, job)
        pcall(RingOv.drawHud)

        local okStrip, drawn = pcall(Cycle.drawStrip, job)
        if okStrip and drawn then return end
        if not Config.Icon.Enabled then return end

        local img = iconImages[job].small
        local alpha = Cycle.fadeAlpha(Config.Icon.AutoHide, Config.Icon.AutoHideSec)
        if img and alpha > 0 then
            local scale = (tonumber(Config.Icon.Scale) or 50) / 100 * resScale()
            local iw, ih = img:size()
            iw, ih = iw * scale, ih * scale
            local x, y = computeIconPos(iw, ih, Config.Icon)
            Cycle.image(img, x, y, iw, ih, alpha)
        end
    end)
else
    log.warn("[TWINWV] d2d/d2dx not found - vocation icon disabled (switching and skills still work without it).")
end

re.on_draw_ui(function()
    do
        local now = os.clock()
        if now - SkillOptionsCache.lastUiAt > 0.5 then SkillOptionsCache.byJob = {} end
        SkillOptionsCache.lastUiAt = now
    end
    if not imgui.tree_node(tr("menu_title")) then return end

    local changed = false

    local function positionControls(p, id)
        local idx = 1
        for i, a in ipairs(ANCHORS) do if a == p.Anchor then idx = i end end
        pushItemWidth()
        local ac
        ac, idx = imgui.combo(tr("icon_anchor") .. "##" .. id .. "_anchor", idx, ANCHORS)
        if ac then p.Anchor = ANCHORS[idx]; changed = true end
        local cX, cY = anchorAxisCentered(p.Anchor)
        local function pct(label, key, centered)
            local lo = centered and -100 or 0
            local v = tonumber(p[key]) or 0
            if v < lo then v = lo elseif v > 100 then v = 100 end
            local c
            c, v = imgui.slider_float(label .. "##" .. id .. "_" .. key, v, lo, 100, "%.1f%%")
            if c then p[key] = math.floor(v * 2 + 0.5) / 2; changed = true end
        end
        pct(tr("icon_offset_x"), "X", cX)
        pct(tr("icon_offset_y"), "Y", cY)
        local c
        c, p.Scale = imgui.slider_int(tr("icon_scale") .. "##" .. id .. "_scale", tonumber(p.Scale) or 50, 10, 150)
        changed = changed or c
        popItemWidth()
    end

    if imgui.tree_node(tr("section_general")) then
        local c1, c2

        pushBoxTheme()
        boxBegin(false)

        sectionHeader(tr("gs_language_header"))
        local langIdx = 1
        for i, l in ipairs(LANGUAGES) do if l == Config.Language then langIdx = i end end
        local lc
        pushItemWidth()
        lc, langIdx = imgui.combo("##twinwv_language", langIdx, LANGUAGE_LABELS)
        popItemWidth()
        if lc then Config.Language = LANGUAGES[langIdx]; changed = true; SkillOptionsCache.byJob = {} end

        boxEnd(false)
        popBoxTheme()

        pushBoxTheme()
        boxBegin(false)

        sectionHeader(tr("gs_equip_requirements_header"))
        c1, Config.General.RemoveJobRequirementsArmor = imgui.checkbox(tr("gs_remove_job_armor"), Config.General.RemoveJobRequirementsArmor)
        if imgui.is_item_hovered() then imgui.set_tooltip(tr("gs_remove_job_armor_tip")) end
        moveToSecondColumn()
        c2, Config.General.RemoveJobRequirementsWeapon = imgui.checkbox(tr("gs_remove_job_weapon"), Config.General.RemoveJobRequirementsWeapon)
        if imgui.is_item_hovered() then imgui.set_tooltip(tr("gs_remove_job_weapon_tip")) end
        changed = changed or c1 or c2

        imgui.spacing()
        sectionHeader(tr("gs_auto_remember_header"))
        c1, Config.General.AutoRememberWeapon = imgui.checkbox(tr("gs_auto_remember"), Config.General.AutoRememberWeapon)
        if imgui.is_item_hovered() then imgui.set_tooltip(tr("gs_auto_remember_tip")) end
        moveToSecondColumn()
        c2, Config.General.AutoRememberArmor = imgui.checkbox(tr("gs_auto_remember_armor"), Config.General.AutoRememberArmor)
        if imgui.is_item_hovered() then imgui.set_tooltip(tr("gs_auto_remember_armor_tip")) end
        changed = changed or c1 or c2

        c1, Config.General.AutoRememberRings = imgui.checkbox(tr("gs_auto_remember_rings"), Config.General.AutoRememberRings)
        if imgui.is_item_hovered() then imgui.set_tooltip(tr("gs_auto_remember_rings_tip")) end
        changed = changed or c1

        imgui.spacing()
        sectionHeader(tr("gs_rearm_effect_subheader"))
        c1, Config.General.RearmamentWeaponEffect = imgui.checkbox(tr("gs_rearm_effect_enable"), Config.General.RearmamentWeaponEffect)
        if imgui.is_item_hovered() then imgui.set_tooltip(tr("gs_rearm_effect_enable_tip")) end
        changed = changed or c1

        boxEnd(false)
        popBoxTheme()

        pushBoxTheme()
        boxBegin(false)

        sectionHeader(tr("gs_extra_skill_hotkeys_header"))
        c1, Config.General.ExtraSkillsEnabled = imgui.checkbox(tr("gs_extra_enable", "Enable Extra Skills"), Config.General.ExtraSkillsEnabled)
        changed = changed or c1
        if Config.General.ExtraSkillsEnabled then
            mutedText(tr("gs_extra_skill_hotkeys_note"))
            if hotkeys then
                changed = hotkeys.hotkey_setter("TWINWV_ExtraBase", nil, tr("gs_extra_base_group")) or changed
                imgui.same_line()
                changed = hotkeys.hotkey_setter("TWINWV_ExtraSubA", nil, tr("gs_extra_seta_group")) or changed
            else
                mutedText("Hotkeys module not found - hotkeys unavailable.")
            end
        end

        boxEnd(false)
        popBoxTheme()

        pushBoxTheme()
        boxBegin(false)

        sectionHeader(tr("gs_extra_direct_cast_header"))
        local dc
        dc, Config.General.ExtraSkillsDirectCast = imgui.checkbox(tr("gs_extra_direct_cast_enable"), Config.General.ExtraSkillsDirectCast)
        changed = changed or dc
        if Config.General.ExtraSkillsDirectCast then
            if hotkeys then
                imgui.text_colored(tr("gs_extra_direct_cast_hold_note", "Some skills don't work as intended with Quick Cast - compare it with the Extra Skills combo."), 0xFF66CCFF) -- yellow: grey is easy to miss
                imgui.spacing()

                for slot = 1, NUM_BASE_SLOTS do
                    changed = hotkeys.hotkey_setter("TWINWV_ExtraDirect" .. slot, nil,
                        string.format(tr("slot_fmt"), slot)) or changed
                    if slot % 3 ~= 0 then imgui.same_line() end
                end
            else
                mutedText("Hotkeys module not found - hotkeys unavailable.")
            end
        end

        boxEnd(false)
        popBoxTheme()

        pushBoxTheme()
        boxBegin(false)

        sectionHeader(tr("gs_weapon_slots_header"))
        local wsEnable
        wsEnable, Config.General.WeaponSlotsEnabled = imgui.checkbox(tr("gs_weapon_slots_enable"), Config.General.WeaponSlotsEnabled)
        if imgui.is_item_hovered() then imgui.set_tooltip(tr("gs_weapon_slots_enable_tip")) end
        changed = changed or wsEnable

        if Config.General.WeaponSlotsEnabled then
            mutedText(tr("gs_weapon_slots_note"))
            mutedText(tr("gs_weapon_slots_note2"))
            if hotkeys then
                changed = hotkeys.hotkey_setter("TWINWV_WeaponSlotMod", nil, tr("gs_weapon_slots_mod_group")) or changed
                imgui.spacing()
                for slot = 1, NUM_WEAPON_SLOTS do
                    changed = hotkeys.hotkey_setter("TWINWV_WeaponSlot" .. slot, nil,
                        string.format(tr("slot_fmt"), slot)) or changed
                    if slot % 3 ~= 0 then imgui.same_line() end
                end
            else
                mutedText("Hotkeys module not found - hotkeys unavailable.")
            end
        end

        boxEnd(false)
        popBoxTheme()

        pushBoxTheme()
        boxBegin(false)

        sectionHeader(tr("gs_wheel_header", "Vocation Wheel"))
        c1, Config.General.EnableVocationWheel = imgui.checkbox(tr("gs_wheel_enable", "Enable vocation wheel"), Config.General.EnableVocationWheel)
        if imgui.is_item_hovered() then
            imgui.set_tooltip(tr("gs_wheel_enable_tip", "Shows a radial menu with your vocations while the wheel key is held."))
        end
        changed = changed or c1
        if not Config.General.EnableVocationWheel then
        elseif hotkeys then
            mutedText(tr("gs_wheel_note2", "Hold the key, point with the mouse or right stick, release to switch."))
            changed = hotkeys.hotkey_setter("TWINWV_Wheel", nil, tr("gs_wheel_key", "Key (keyboard/mouse)")) or changed
            imgui.same_line()
            changed = hotkeys.hotkey_setter("TWINWV_WheelPad", nil, tr("gs_wheel_pad", "Button (gamepad)")) or changed
            pushItemWidth()
            local dh
            dh, Config.WheelHotkeys.HoldSec = imgui.slider_float(tr("gs_wheel_hold", "Hold to open (s)") .. "##twinwv_wheel_hold",
                RadialWheel.holdSec(), 0.0, 0.5, "%.2f")
            popItemWidth()
            if imgui.is_item_hovered() then
                imgui.set_tooltip(tr("gs_wheel_hold_tip", "0 - the wheel opens as soon as you press the key.\nOn a key the game also uses (e.g. Dash in Toggle mode), set a delay\nso a short press still does the game's action."))
            end
            if dh then Config.WheelHotkeys.HoldSec = math.floor(Config.WheelHotkeys.HoldSec * 20 + 0.5) / 20 end
            changed = changed or dh
            local STICKS = { "Right", "Left", "Either" }
            local stickLabels = { tr("gs_wheel_stick_right", "Right stick"), tr("gs_wheel_stick_left", "Left stick"), tr("gs_wheel_stick_either", "Either stick") }
            local si = 1
            for k, v in ipairs(STICKS) do if v == Config.WheelHotkeys.Stick then si = k end end
            pushItemWidth()
            local sc2
            sc2, si = imgui.combo(tr("gs_wheel_stick", "Pick with (gamepad)") .. "##twinwv_wheel_stick", si, stickLabels)
            popItemWidth()
            if sc2 then Config.WheelHotkeys.Stick = STICKS[si]; changed = true end

            c1, Config.General.WheelSlowMotion = imgui.checkbox(tr("gs_wheel_slowmo", "Slow motion while open"), Config.General.WheelSlowMotion)
            changed = changed or c1
            if Config.General.WheelSlowMotion then
                pushItemWidth()
                c1, Config.General.WheelSlowMotionSpeed = imgui.slider_float(tr("gs_wheel_slowmo_speed", "Game speed") .. "##twinwv_wheel_slowmo",
                    RadialWheel.slowSpeed(), 0.1, 1.0, "%.1fx")
                popItemWidth()
                if c1 then Config.General.WheelSlowMotionSpeed = math.floor(Config.General.WheelSlowMotionSpeed * 10 + 0.5) / 10 end
                changed = changed or c1
            end

            imgui.spacing()
            mutedText(tr("gs_wheel_vocations", "Order on the wheel (0 = hidden):"))
            Config.WheelOrder = Config.WheelOrder or {}
            local gridX = imgui.get_cursor_pos().x
            for jobId = 1, 9 do
                local col = (jobId - 1) % 3
                if col > 0 then
                    imgui.same_line()
                    moveToColumn(gridX + col * 210)
                end
                local old = tonumber(Config.WheelOrder[jobId]) or jobId
                pushItemWidth(70)
                local c, v = imgui.slider_int(vocationName(jobId) .. "##twinwv_wheel_order" .. jobId, old, 0, 9)
                popItemWidth()
                if c and v ~= old then
                    if v ~= 0 then
                        for other = 1, 9 do
                            if other ~= jobId and (tonumber(Config.WheelOrder[other]) or other) == v then
                                v = 0
                                break
                            end
                        end
                    end
                    Config.WheelOrder[jobId] = v
                    changed = true
                end
            end
            if #RadialWheel.enabledOrder() < 2 then
                imgui.text_colored(tr("gs_wheel_need_two", "Pick at least 2 vocations - otherwise the wheel won't open."), 0xFF66CCFF)
            end
            if d2d == nil and d2dx == nil then
                imgui.text_colored(tr("gs_wheel_need_d2d", "REFramework D2D is not installed - the wheel needs it to be drawn."), 0xFF6666FF)
            end
        else
            mutedText("Hotkeys module not found - hotkeys unavailable.")
        end

        boxEnd(false)
        popBoxTheme()

        pushBoxTheme()
        boxBegin(false)

        sectionHeader(tr("gs_cycle_hotkeys_header", "Cycle Vocation"))
        c1, Config.General.EnableVocationCycling = imgui.checkbox(tr("gs_cycle_enable", "Enable vocation cycling"), Config.General.EnableVocationCycling)
        if imgui.is_item_hovered() then
            imgui.set_tooltip(tr("gs_cycle_enable_tip", "Enables the Prev/Next hotkeys below. Only vocations with a Cycle order are included."))
        end
        changed = changed or c1
        if Config.General.EnableVocationCycling then
            mutedText(tr("gs_cycle_hotkeys_note", "Cycle through vocations in the Cycle order"))
            if hotkeys then
                changed = hotkeys.hotkey_setter("TWINWV_CyclePrevKey", nil, tr("gs_cycle_prev_key", "Prev (keyboard)")) or changed
                imgui.same_line()
                changed = hotkeys.hotkey_setter("TWINWV_CycleNextKey", nil, tr("gs_cycle_next_key", "Next (keyboard)")) or changed
                changed = hotkeys.hotkey_setter("TWINWV_CyclePrev", nil, tr("gs_cycle_prev_group", "Prev (gamepad)")) or changed
                imgui.same_line()
                changed = hotkeys.hotkey_setter("TWINWV_CycleNext", nil, tr("gs_cycle_next_group", "Next (gamepad)")) or changed
            else
                mutedText("Hotkeys module not found - hotkeys unavailable.")
            end
            if #Cycle.list() < 2 then
                imgui.text_colored(tr("gs_cycle_need_two", "Set a Cycle order (1-9) for at least 2 vocations below."), 0xFF66CCFF)
            end
            pushItemWidth()
            c1, Config.General.CycleConfirmSec = imgui.slider_float(tr("gs_cycle_confirm", "Switch after") .. "##twinwv_cycle_confirm",
                Cycle.confirmSec(), 0.2, 0.6, "%.1f s")
            popItemWidth()
            if imgui.is_item_hovered() then
                imgui.set_tooltip(tr("gs_cycle_confirm_tip", "How long to wait after the last Next/Prev press before switching. Shorter = faster, longer = more time to scroll."))
            end
            if c1 then Config.General.CycleConfirmSec = math.floor(Config.General.CycleConfirmSec * 10 + 0.5) / 10 end
            changed = changed or c1

            local cs = Config.CycleStrip
            imgui.spacing()
            sectionHeader(tr("icon_strip_header", "Cycling Strip"))
            local sc
            sc, cs.Enabled = imgui.checkbox(tr("icon_strip_enabled", "Show cycling strip") .. "##twinwv_strip_on", cs.Enabled)
            changed = changed or sc
            if cs.Enabled then
                mutedText(tr("icon_strip_desc", "Shows your cycle vocations in order instead of the single icon.\nThe highlighted one is where Next/Prev will take you."))
                positionControls(cs, "twinwv_strip")
                pushItemWidth()
                sc, cs.InactiveScale = imgui.slider_int(tr("icon_strip_inactive_scale", "Other icons (% of the highlighted)") .. "##twinwv_strip_inactive",
                    tonumber(cs.InactiveScale) or 70, 30, 100)
                popItemWidth()
                changed = changed or sc
                sc, cs.AutoHide = imgui.checkbox(tr("icon_autohide", "Hide after a few seconds") .. "##twinwv_strip_autohide", cs.AutoHide == true)
                if imgui.is_item_hovered() then
                    imgui.set_tooltip(tr("icon_autohide_tip", "Fades out after a vocation switch and shows again when you switch or cycle."))
                end
                changed = changed or sc
                if cs.AutoHide then
                    pushItemWidth()
                    sc, cs.AutoHideSec = imgui.slider_float(tr("icon_autohide_sec", "Hide after (s)") .. "##twinwv_strip_autohide_sec",
                        tonumber(cs.AutoHideSec) or 1.5, 1.0, 3.0, "%.1f")
                    popItemWidth()
                    if sc then cs.AutoHideSec = math.floor(cs.AutoHideSec * 10 + 0.5) / 10 end
                    changed = changed or sc
                end
                if not d2dLib then mutedText("d2d/d2dx not found - icon unavailable.") end
            end
        end

        boxEnd(false)
        popBoxTheme()

        if not (Config.General.EnableVocationCycling and Config.CycleStrip.Enabled) then
            pushBoxTheme()
            boxBegin(false)

            sectionHeader(tr("section_icon", "Vocation Icon"))
            local ic
            ic, Config.Icon.Enabled = imgui.checkbox(tr("icon_enabled") .. "##twinwv_icon_on", Config.Icon.Enabled)
            changed = changed or ic
            if Config.Icon.Enabled then
                mutedText(tr("icon_position_desc"))
                positionControls(Config.Icon, "twinwv_icon")
                local ah
                ah, Config.Icon.AutoHide = imgui.checkbox(tr("icon_autohide", "Hide after a few seconds") .. "##twinwv_icon_autohide", Config.Icon.AutoHide == true)
                if imgui.is_item_hovered() then
                    imgui.set_tooltip(tr("icon_autohide_tip", "Fades out after a vocation switch and shows again when you switch or cycle."))
                end
                changed = changed or ah
                if Config.Icon.AutoHide then
                    pushItemWidth()
                    ah, Config.Icon.AutoHideSec = imgui.slider_float(tr("icon_autohide_sec", "Hide after (s)") .. "##twinwv_icon_autohide_sec",
                        tonumber(Config.Icon.AutoHideSec) or 1.5, 1.0, 3.0, "%.1f")
                    popItemWidth()
                    if ah then Config.Icon.AutoHideSec = math.floor(Config.Icon.AutoHideSec * 10 + 0.5) / 10 end
                    changed = changed or ah
                end
                if not d2dLib then mutedText("d2d/d2dx not found - icon unavailable.") end
            end

            boxEnd(false)
            popBoxTheme()
        end

        do
            local sb = Config.SkillBar
            pushBoxTheme()
            boxBegin(false)
            sectionHeader(tr("gs_skillbar_header", "Skill Bar"))
            local sc
            sc, sb.Enabled = imgui.checkbox(tr("gs_skillbar_enable", "Show skill bar") .. "##twinwv_sb_on", sb.Enabled)
            changed = changed or sc
            if sb.Enabled then
                mutedText(tr("gs_skillbar_note", "Icons: reframework/images/TWINWV_skills/<Vocation>/<Skill_Name>.png\n(no icon = the skill's name). Your own icons can replace them."))
                if hotkeys then
                    changed = hotkeys.hotkey_setter("TWINWV_SkillBarToggle", nil, tr("gs_skillbar_toggle", "Hide / show key")) or changed
                    if imgui.is_item_hovered() then
                        imgui.set_tooltip(tr("gs_skillbar_toggle_tip", "Press to hide the skill bar (e.g. when dialogue subtitles show under it), press again to show it."))
                    end
                    if sb.Hidden then
                        imgui.same_line()
                        imgui.text_colored(tr("gs_skillbar_hidden", "(hidden)"), 0xFF66CCFF)
                    end
                end
                local LAYOUTS = { "TwoRows", "OneRow" }
                local li = (sb.Layout == "OneRow") and 2 or 1
                pushItemWidth()
                sc, li = imgui.combo(tr("gs_skillbar_layout", "Layout") .. "##twinwv_sb_layout", li, LAYOUTS)
                popItemWidth()
                if sc then sb.Layout = LAYOUTS[li]; changed = true end
                local MODES = { "Word", "Off" }
                local mi = 1
                for i, m in ipairs(MODES) do if m == sb.NameMode then mi = i end end
                pushItemWidth()
                sc, mi = imgui.combo(tr("gs_skillbar_names", "Skill name on icon") .. "##twinwv_sb_names", mi, MODES)
                popItemWidth()
                if sc then sb.NameMode = MODES[mi]; changed = true end
                positionControls(sb, "twinwv_sb")
                pushItemWidth()
                sc, sb.Opacity = imgui.slider_int(tr("gs_skillbar_opacity", "Opacity (%)") .. "##twinwv_sb_opacity",
                    tonumber(sb.Opacity) or 100, 10, 100)
                popItemWidth()
                if imgui.is_item_hovered() then
                    imgui.set_tooltip(tr("gs_skillbar_opacity_tip", "Background, cells and icons. Text stays fully visible."))
                end
                changed = changed or sc
                sc, sb.ShowKeys = imgui.checkbox(tr("gs_skillbar_keys", "Show key labels") .. "##twinwv_sb_keys", sb.ShowKeys)
                changed = changed or sc
                if sb.ShowKeys then
                    sc, sb.GameKeys = imgui.checkbox(tr("gs_skillbar_gamekeys", "Use the game's key bindings") .. "##twinwv_sb_gk", sb.GameKeys ~= false)
                    changed = changed or sc
                    if imgui.button(tr("gs_skillbar_dumpkeys", "Dump game key bindings to log") .. "##twinwv_sb_dump") then
                        SkillBar.dumpGameKeys()
                    end
                    local gslots = sb.GameKeys and SkillBar.gameKeys() or nil
                    if sb.GameKeys and gslots then
                        mutedText(tr("gs_skillbar_gamekeys_found", "From the game:") .. " " .. table.concat(gslots, " / "))
                    elseif sb.GameKeys then
                        imgui.text_colored(tr("gs_skillbar_gamekeys_none", "Couldn't read the game's bindings - using the fields below."), 0xFF66CCFF)
                    end
                    mutedText(tr("gs_skillbar_keys_note", "Key labels for regular skill slots 1-6 (Extra uses Quick Cast keys if it's on):"))
                    sb.Keys = sb.Keys or {}
                    for i = 1, NUM_BASE_SLOTS do
                        pushItemWidth(90)
                        local kc, kv = imgui.input_text(string.format(tr("slot_fmt"), i) .. "##twinwv_sb_key" .. i, sb.Keys[i] or "")
                        popItemWidth()
                        if kc then sb.Keys[i] = kv; changed = true end
                        if i % 3 ~= 0 then imgui.same_line() end
                    end
                end
                if not d2dLib then mutedText("d2d/d2dx not found - icon unavailable.") end
            end
            boxEnd(false)
            popBoxTheme()
        end

        imgui.tree_pop()
    end

    local function drawVocationBox(jobId, nested, boxWidth)
        local voc = VOCATIONS[jobId]
        local entry = Config.Vocations[jobId]

        pushBoxTheme()
        boxBegin(nested, boxWidth)

        vocationHeader(jobId)

            if hotkeys then
                changed = hotkeys.hotkey_setter("TWINWV_Voc" .. jobId, nil, tr("voc_key_label")) or changed

                local function findHotkeyCollision()
                    local key = entry.Key
                    if not key or key == "None" then return nil end
                    local ownCategory = actionModifierCategoryCache["TWINWV_Voc" .. jobId]
                    for otherId = 1, 9 do
                        if otherId ~= jobId then
                            local otherEntry = Config.Vocations[otherId]
                            if otherEntry and otherEntry.Key == key then
                                local otherCategory = actionModifierCategoryCache["TWINWV_Voc" .. otherId]
                                if otherCategory == ownCategory then
                                    return otherId
                                end
                            end
                        end
                    end
                    return nil
                end
                local collidesWithJobId = findHotkeyCollision()
                if collidesWithJobId then
                    imgui.text_colored(
                        "! Same key+modifier as " .. vocationName(collidesWithJobId) ..
                        " - only one of them will respond. Remove/change the modifier for one in the Hotkeys widget (right-click the key field).",
                        0xFF66CCFF)
                end
            end

            if Config.General.EnableVocationCycling then
                imgui.text(tr("voc_cycle_order_label", "Cycle order") .. ":")
                imgui.same_line()
                pushItemWidth(110)
                local oldOrder = tonumber(entry.CycleOrder) or 0
                local cycleChanged, newCycleOrder = imgui.slider_int("##cycleorder" .. jobId, oldOrder, 0, 9)
                popItemWidth()
                if cycleChanged and newCycleOrder ~= oldOrder then
                    if newCycleOrder ~= 0 then
                        for otherId = 1, 9 do
                            if otherId ~= jobId and tonumber(Config.Vocations[otherId].CycleOrder) == newCycleOrder then
                                newCycleOrder = 0
                                break
                            end
                        end
                    end
                    entry.CycleOrder = newCycleOrder
                    changed = true
                end
                if imgui.is_item_hovered() then imgui.set_tooltip(tr("voc_cycle_order_tip", "Position in the Prev/Next cycle. 0 = excluded.")) end
            end

            imgui.spacing()
            if (Config.General.ExtraSkillsEnabled or Config.General.ExtraSkillsDirectCast)
                and imgui.tree_node(tr("extra_skills_header") .. "##extraskills" .. jobId) then
                local labels, ids, filtered = extraSkillOptionsForJob(jobId)
                if not filtered then
                    mutedText(tr("learned_warning"))
                    imgui.spacing()
                end
                local idToIndex = {}
                for i, sid in ipairs(ids) do idToIndex[sid] = i end

                mutedText(string.format(tr("extra_set_a_fmt"), Config.ExtraSkillHotkeys.SubA))
                for slot = 1, NUM_BASE_SLOTS do
                    local cur = entry.ExtraSkillsA[slot]
                    if cur == nil then cur = 0 end
                    local curIndex = idToIndex[cur] or 1
                    imgui.text(string.format(tr("slot_fmt"), slot) .. ":")
                    imgui.same_line()
                    pushItemWidth(Config.Language == "ru" and 190 or 150)
                    local ic
                    ic, curIndex = imgui.combo("##A" .. jobId .. slot, curIndex, labels)
                    popItemWidth()
                    if ic then
                        entry.ExtraSkillsA[slot] = ids[curIndex] or 0
                        changed = true
                    end
                end

                imgui.tree_pop()
            end

            boxEnd(nested)
            popBoxTheme()
    end

    if imgui.tree_node(tr("section_vocations")) then
        if UI_SUPPORTS_GROUPS then
            local vocGridGapCounter = 0
            local jobId = 1
            while jobId <= 9 do
                local secondJobId = jobId + 1

                imgui.begin_group()
                drawVocationBox(jobId, false, UI_VOC_BOX_WIDTH)
                imgui.end_group()

                if secondJobId <= 9 then
                    imgui.same_line()
                    vocGridGapCounter = vocGridGapCounter + 1
                    imgui.invisible_button("##twinwv-vocgrid-gap-" .. vocGridGapCounter, { 16, 1 }, 0)
                    imgui.same_line()

                    imgui.begin_group()
                    drawVocationBox(secondJobId, false, UI_VOC_BOX_WIDTH)
                    imgui.end_group()
                end

                imgui.spacing()

                jobId = jobId + 2
            end
        else
            for jobId = 1, 9 do
                drawVocationBox(jobId, false)
            end
        end

        imgui.tree_pop()
    end

    -- Skill Labels: the player's own short names for the skill bar (shown only
    -- while the bar is on). Empty = the default short name.
    -- Ring Presets (see RingOv)
    if imgui.tree_node(tr("section_ring_presets", "Ring Presets") .. "##twinwv_rp_section") then
        local rp = Config.RingPresets
        rp.Slots = rp.Slots or {}
        mutedText(tr("rp_note1", "Temporary rings on top of each vocation's own (e.g. Dragonsbane for a dragon fight)."))
        mutedText(tr("rp_note2", "Turn a preset on, put the rings on, press 'Remember current rings'. Turn it off -"))
        mutedText(tr("rp_note3", "every vocation gets its own rings back. Its key toggles it on/off."))

        pushBoxTheme()
        boxBegin(false)
        -- active preset: Off + names (same as the keys)
        local names, map, cur = { tr("rp_off", "Off") }, { 0 }, 1
        for i = 1, RingOv.MAX do
            local sl = RingOv.slot(i)
            if sl then
                names[#names + 1] = (sl.Name ~= "" and sl.Name or ("Rings " .. i))
                map[#map + 1] = i
                if tonumber(rp.Active) == i then cur = #map end
            end
        end
        pushItemWidth()
        local ac, ni = imgui.combo(tr("rp_active", "Active preset") .. "##twinwv_rp_active", cur, names)
        popItemWidth()
        if ac and map[ni] ~= tonumber(rp.Active) then
            rp.Active = map[ni]
            RingOv.applyNow()
            changed = true
        end
        boxEnd(false)
        popBoxTheme()

        for i = 1, RingOv.MAX do
            local sl = RingOv.slot(i)
            if sl then
                local title = (sl.Name ~= "" and sl.Name or ("Rings " .. i))
                if tonumber(rp.Active) == i then title = title .. "  (" .. tr("rp_on", "ON") .. ")" end
                -- "###": the node id is the slot number only - otherwise typing the
                -- name (or ON/OFF) changed the id and collapsed the node on every letter
                if imgui.tree_node(title .. "###twinwv_rp_slot" .. i) then
                    pushItemWidth(200)
                    local nc, nv = imgui.input_text(tr("rp_name", "Name") .. "##twinwv_rp_name" .. i, sl.Name or "")
                    popItemWidth()
                    if nc then sl.Name = nv or ""; changed = true end
                    if hotkeys then
                        changed = hotkeys.hotkey_setter("TWINWV_RingPreset" .. i, nil, tr("rp_key", "Key")) or changed
                    end
                    mutedText(tr("rp_jobs", "Use on these vocations (unchecked keep their own rings):"))
                    sl.Jobs = sl.Jobs or {}
                    for jobId = 1, 9 do
                        local jc, jv = imgui.checkbox(vocationName(jobId) .. "##twinwv_rp_job" .. i .. "_" .. jobId, sl.Jobs[jobId] == true)
                        if jc then
                            sl.Jobs[jobId] = jv
                            changed = true
                            if tonumber(rp.Active) == i and jobId == getCurrentJob() then RingOv.applyNow() end
                        end
                        if jobId % 3 ~= 0 then imgui.same_line() end
                    end
                    if imgui.button(tr("rp_capture", "Remember current rings") .. "##twinwv_rp_cap" .. i) then
                        RingOv.capture(i)
                    end
                    imgui.same_line()
                    local n = sl.items and #sl.items or 0
                    if n > 0 then
                        local parts = {}
                        for _, it in ipairs(sl.items) do parts[#parts + 1] = RingOv.itemName(it.ItemId) or ("#" .. tostring(it.ItemId)) end
                        mutedText(tr("rp_saved", "Saved:") .. " " .. table.concat(parts, ", "))
                    else
                        mutedText(tr("rp_empty", "No rings saved yet"))
                    end
                    if imgui.button(tr("rp_remove", "Remove preset") .. "##twinwv_rp_del" .. i) then
                        RingOv.remove(i)
                        changed = true
                    end
                    imgui.tree_pop()
                end
            end
        end
        local count = 0
        for i = 1, RingOv.MAX do if RingOv.slot(i) then count = count + 1 end end
        if count < RingOv.MAX then
            if imgui.button("+ " .. tr("rp_add", "Add preset") .. "##twinwv_rp_add") then
                RingOv.add()
                changed = true
            end
        end

        pushBoxTheme()
        boxBegin(false)
        sectionHeader(tr("rp_hud", "HUD"))
        local h = rp.Hud
        local MODES = { "Always", "Active", "Hidden" }
        local modeLabels = { tr("rp_hud_always", "Always"), tr("rp_hud_active", "Only the active preset"), tr("rp_hud_hidden", "Hidden") }
        local mi = 1
        for k, m in ipairs(MODES) do if m == h.Mode then mi = k end end
        pushItemWidth()
        local mc
        mc, mi = imgui.combo(tr("rp_hud_mode", "Show") .. "##twinwv_rp_hudmode", mi, modeLabels)
        popItemWidth()
        if mc then h.Mode = MODES[mi]; changed = true end
        if h.Mode ~= "Hidden" then
            positionControls(h, "twinwv_rph")
            pushItemWidth()
            local oc
            oc, h.Opacity = imgui.slider_int(tr("gs_skillbar_opacity", "Opacity (%)") .. "##twinwv_rph_opacity",
                tonumber(h.Opacity) or 100, 10, 100)
            popItemWidth()
            changed = changed or oc
        end
        boxEnd(false)
        popBoxTheme()
        imgui.tree_pop()
    end

    if Config.SkillBar.Enabled and imgui.tree_node(tr("section_skill_labels", "Skill Labels")) then
        Config.SkillLabels = Config.SkillLabels or {}
        mutedText(tr("skill_labels_note", "Your own short names shown on the skill bar. Empty = default."))
        for jobId = 1, 9 do
            if imgui.tree_node(vocationName(jobId) .. "##twinwv_lbl_job" .. jobId) then
                for _, sid in ipairs(VOCATION_SKILLS[jobId] or {}) do
                    if sid ~= 0 then
                        local key = tostring(sid)
                        imgui.text(skillName(sid))
                        imgui.same_line()
                        moveToColumn(260)
                        pushItemWidth(150)
                        local lc, lv = imgui.input_text("##twinwv_lbl" .. sid, Config.SkillLabels[key] or "")
                        popItemWidth()
                        if lc then
                            lv = (lv or ""):gsub("^%s+", ""):gsub("%s+$", "")
                            Config.SkillLabels[key] = (lv ~= "") and lv or nil
                            changed = true
                        end
                    end
                end
                imgui.tree_pop()
            end
        end
        imgui.tree_pop()
    end

    if changed then
        syncHotkeysToConfig()
        saveConfig()
    end

    imgui.tree_pop()
end)

log.info("[TWINWV] loaded")
