--[[
TWINWV - instant vocation switching for Dragon's Dogma 2 (REFramework Lua mod)

Not a Warfarer Vocation mod - this gives true multiclassing: instant
switching between all 9 base vocations, each with its own hotkey
(+ optional per-vocation modifier), its own set of Extra Skills, and its
own weapon/armor/ring loadout that's remembered automatically.

Extra Skills Direct Cast (autorun-only, not shipped in the release package)
binds each of the 6 Extra Skill slots to its own hotkey that casts it
directly via app.HumanCustomSkillID, instead of holding Base+Modifier to
swap it into a normal slot first. See SKILL_CUSTOM_ID below for the skill
id -> engine field mapping this relies on.

lilu_dev
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

local function skillName(id)
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

local VOCATION_SKILLS = {
    [1] = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 },
    [2] = { 0, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23 },
    [3] = { 0, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37 },
    [4] = { 0, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 101 },
    [5] = { 0, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61 },
    [6] = { 0, 24, 25, 26, 27, 62, 63, 64, 65, 66, 67, 68, 69 },
    [7] = { 0, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79 },
    [8] = { 0, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91 },
    [9] = { 0, 92, 93, 94, 95, 96, 97, 98, 99 },
}

local NUM_BASE_SLOTS = 6

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
    ["TWINWV_CycleNext_$"] = "R3",
    ["TWINWV_CyclePrev_$"] = "R3",
}

local function seedDefaultHotkeyModifiers()
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
    end
end

local function defaultVocationEntry(jobId)
    local hk = DEFAULT_VOCATION_HOTKEYS[jobId] or { Key = "None" }
    return {
        Key = hk.Key,
        ExtraSkillsA = { 0, 0, 0, 0, 0, 0 },
        CycleOrder = 0,
        WeaponPreset = { items = {} },
        ArmorPreset = { items = {} },
        RingsPreset = { items = {} },
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
        CycleHotkeys = {
            Prev = "LT (L2)",
            Next = "RT (R2)",
        },
        General = {
            UnlockTargetVocation = true,
            AutoRememberWeapon = true,
            AutoRememberArmor = true,
            AutoRememberRings = true,
            RemoveJobRequirementsArmor = false,
            RemoveJobRequirementsWeapon = false,
            EnableVocationCycling = false,
            RearmamentWeaponEffect = true,
            ExtraSkillsDirectCast = false,
        },
        Icon = {
            Enabled = true,
            Anchor = "TopLeft",
            OffsetX = 40, OffsetY = 40,
            Scale = 80,
            FlashOnSwitch = true, FlashScale = 30, FlashDurationFrames = 60,
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

if Config.ExtraSkillHotkeys then Config.ExtraSkillHotkeys.SubB = nil end
if Config.Vocations then
    for jobId = 1, 9 do
        local voc = Config.Vocations[jobId]
        if voc then voc.ExtraSkillsB = nil end
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
mergeMissing(Config, defaultConfig())
for jobId = 1, 9 do
    if not Config.Vocations[jobId] then Config.Vocations[jobId] = defaultVocationEntry(jobId) end
end
do
    local validLanguage = false
    for _, lang in ipairs(LANGUAGES) do if lang == Config.Language then validLanguage = true end end
    if not validLanguage then Config.Language = "en" end
end

local function tr(key)
    local cur = TranslationData[Config.Language]
    local v = cur and cur.ui and cur.ui[key]
    if v ~= nil and v ~= "" then return v end
    local en = TranslationData.en
    v = en and en.ui and en.ui[key]
    if v ~= nil and v ~= "" then return v end
    return key
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

local function captureWeaponPresetForJob(jobId, quiet)
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
            if v._IsEquipped == true then
                local slot = v:call("get_EquipSlot()")
                if isWeaponEquipSlot(slot) then
                    items[#items + 1] = { ItemId = v._ItemId, SlotEnum = slot }
                end
            end
        end
        return items
    end)
    if not ok or not result then
        if not quiet then
            log.warn("[TWINWV] captureWeaponPresetForJob(" .. tostring(jobId) .. ") failed: " .. tostring(result))
        end
        return false, result
    end
    if not Config.Vocations[jobId] then return false, "unknown jobId" end
    Config.Vocations[jobId].WeaponPreset = { items = result }
    saveConfig()
    if not quiet then
        log.info("[TWINWV] Weapon preset saved for " .. vocationName(jobId) .. ": " .. #result .. " item(s).")
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
            if v._IsEquipped == true and isWeaponEquipSlot(v:call("get_EquipSlot()")) then
                local masterData = im:call("getStorageMasterData(app.ItemDefine.StorageData)", v)
                local param = masterData:call("get_Param()")
                ItemManagerMethods.removeEquip:call(im, param, player, false, true)
            end
        end
        im:call("applyEquipChange()")
    end)
end

local function applyWeaponPresetForJob(jobId)
    if not resolveItemManagerMethods() then return end

    local entry = Config.Vocations[jobId]
    local preset = entry and entry.WeaponPreset
    if not preset or not preset.items or #preset.items == 0 then
        stripEquippedWeapons()
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

        local wantedIds = {}
        for _, want in ipairs(preset.items) do wantedIds[want.ItemId] = true end
        for i = 0, count - 1 do
            local v = storage:call("get_Item", i)
            if v._IsEquipped == true and isWeaponEquipSlot(v:call("get_EquipSlot()")) and not wantedIds[v._ItemId] then
                local masterData = im:call("getStorageMasterData(app.ItemDefine.StorageData)", v)
                local param = masterData:call("get_Param()")
                ItemManagerMethods.removeEquip:call(im, param, player, false, true)
            end
        end

        for _, want in ipairs(preset.items) do
            for i = 0, count - 1 do
                local v = storage:call("get_Item", i)
                if v._ItemId == want.ItemId then
                    local masterData = im:call("getStorageMasterData(app.ItemDefine.StorageData)", v)
                    local param = masterData:call("get_Param()")
                    local canEquip = param:call("canEquip(app.CharacterID, System.Boolean)", charaId, false)
                    if canEquip then
                        ItemManagerMethods.setEquip:call(im, param, player, want.SlotEnum, true, true)
                    else
                        log.warn("[TWINWV] WeaponPresets: item " .. tostring(want.ItemId) ..
                            " for " .. vocationName(jobId) .. " failed canEquip() - skipped.")
                    end
                    break
                end
            end
        end
        im:call("applyEquipChange()")
    end)
    if not ok then
        log.warn("[TWINWV] applyWeaponPresetForJob(" .. tostring(jobId) .. ") threw: " .. tostring(err))
    end
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
            if v._IsEquipped == true then
                local slot = v:call("get_EquipSlot()")
                if ARMOR_EQUIP_SLOTS[slot] then
                    items[#items + 1] = { ItemId = v._ItemId, SlotEnum = slot }
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
            if v._IsEquipped == true and ARMOR_EQUIP_SLOTS[v:call("get_EquipSlot()")] then
                local masterData = im:call("getStorageMasterData(app.ItemDefine.StorageData)", v)
                local param = masterData:call("get_Param()")
                ItemManagerMethods.removeEquip:call(im, param, player, false, true)
            end
        end
        if not suppressApply then im:call("applyEquipChange()") end
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

        local wantedIds = {}
        for _, want in ipairs(preset.items) do wantedIds[want.ItemId] = true end
        for i = 0, count - 1 do
            local v = storage:call("get_Item", i)
            if v._IsEquipped == true and ARMOR_EQUIP_SLOTS[v:call("get_EquipSlot()")] and not wantedIds[v._ItemId] then
                local masterData = im:call("getStorageMasterData(app.ItemDefine.StorageData)", v)
                local param = masterData:call("get_Param()")
                ItemManagerMethods.removeEquip:call(im, param, player, false, true)
            end
        end

        for _, want in ipairs(preset.items) do
            for i = 0, count - 1 do
                local v = storage:call("get_Item", i)
                if v._ItemId == want.ItemId then
                    local masterData = im:call("getStorageMasterData(app.ItemDefine.StorageData)", v)
                    local param = masterData:call("get_Param()")
                    local canEquip = param:call("canEquip(app.CharacterID, System.Boolean)", charaId, false)
                    if canEquip then
                        ItemManagerMethods.setEquip:call(im, param, player, want.SlotEnum, true, true)
                    else
                        log.warn("[TWINWV] ArmorPresets: item " .. tostring(want.ItemId) ..
                            " for " .. vocationName(jobId) .. " failed canEquip() - skipped.")
                    end
                    break
                end
            end
        end
        if not suppressApply then im:call("applyEquipChange()") end
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
            if v._IsEquipped == true then
                local slot = v:call("get_EquipSlot()")
                if RINGS_EQUIP_SLOTS[slot] then
                    items[#items + 1] = { ItemId = v._ItemId, SlotEnum = slot }
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
            if v._IsEquipped == true and RINGS_EQUIP_SLOTS[v:call("get_EquipSlot()")] then
                local masterData = im:call("getStorageMasterData(app.ItemDefine.StorageData)", v)
                local param = masterData:call("get_Param()")
                ItemManagerMethods.removeEquip:call(im, param, player, false, true)
            end
        end
        if not suppressApply then im:call("applyEquipChange()") end
    end)
end

local function applyRingsPresetForJob(jobId, suppressApply)
    if not resolveItemManagerMethods() then return end

    local entry = Config.Vocations[jobId]
    local preset = entry and entry.RingsPreset
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

        local wantedIds = {}
        for _, want in ipairs(preset.items) do wantedIds[want.ItemId] = true end
        for i = 0, count - 1 do
            local v = storage:call("get_Item", i)
            if v._IsEquipped == true and RINGS_EQUIP_SLOTS[v:call("get_EquipSlot()")] and not wantedIds[v._ItemId] then
                local masterData = im:call("getStorageMasterData(app.ItemDefine.StorageData)", v)
                local param = masterData:call("get_Param()")
                ItemManagerMethods.removeEquip:call(im, param, player, false, true)
            end
        end

        for _, want in ipairs(preset.items) do
            for i = 0, count - 1 do
                local v = storage:call("get_Item", i)
                if v._ItemId == want.ItemId then
                    local masterData = im:call("getStorageMasterData(app.ItemDefine.StorageData)", v)
                    local param = masterData:call("get_Param()")
                    local canEquip = param:call("canEquip(app.CharacterID, System.Boolean)", charaId, false)
                    if canEquip then
                        ItemManagerMethods.setEquip:call(im, param, player, want.SlotEnum, true, true)
                    else
                        log.warn("[TWINWV] RingsPresets: item " .. tostring(want.ItemId) ..
                            " for " .. vocationName(jobId) .. " failed canEquip() - skipped.")
                    end
                    break
                end
            end
        end
        if not suppressApply then im:call("applyEquipChange()") end
    end)
    if not ok then
        log.warn("[TWINWV] applyRingsPresetForJob(" .. tostring(jobId) .. ") threw: " .. tostring(err))
    end
end

-- Hooks ItemManager::applyEquipChange and captures the current loadout into
-- the active vocation's preset right after the equipment menu closes
-- (isGuiPaused() going false->true is the signal), so presets stay in sync
-- without an explicit save action.
local applyEquipChangeHookInstalled = false
local function installAutoRememberHook()
    if applyEquipChangeHookInstalled then return end
    applyEquipChangeHookInstalled = true
    local ok = pcall(function()
        local method = sdk.find_type_definition("app.ItemManager"):get_method("applyEquipChange")
        sdk.hook(method, nil, function(retval)
            if not isGuiPaused() then return retval end
            local job = getCurrentJob()
            if job and VOCATIONS[job] then
                if Config.General.AutoRememberWeapon then
                    pcall(captureWeaponPresetForJob, job, true)
                end
                if Config.General.AutoRememberArmor then
                    pcall(captureArmorPresetForJob, job, true)
                end
                if Config.General.AutoRememberRings then
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
            if entry and entry.CustomSkillID then set[entry.CustomSkillID] = true end
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
local function skillOptionsForJob(jobId)
    local allIds = VOCATION_SKILLS[jobId] or { 0 }
    local unlocked = getUnlockedSkillIds()
    local filtered = unlocked ~= nil

    local function build(useFilter)
        local ids, labels = {}, {}
        for _, sid in ipairs(allIds) do
            if sid == 0 or not useFilter or unlocked[sid] then
                ids[#ids + 1] = sid
                labels[#labels + 1] = skillName(sid)
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

local function extraSkillOptionsForJob(jobId)
    return skillOptionsForJob(jobId)
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

local function applySkillSet(jobId, skills)
    local allEmpty = true
    for i = 1, NUM_BASE_SLOTS do
        if (skills[i] or 0) ~= 0 then allEmpty = false break end
    end
    if allEmpty then
        log.warn("[TWINWV] applySkillSet: итоговый набор для " .. vocationName(jobId) ..
            " полностью пустой (все 6 слотов = 'нет скилла') - применение пропущено, " ..
            "чтобы не повторить краш от полного снятия скиллов. Настрой хотя бы один слот.")
        return
    end

    local skillCtx = getSkillContext(getHuman(getPlayer()))
    if not skillCtx then return end
    for i = 1, NUM_BASE_SLOTS do
        pcall(function() skillCtx:setSkill(jobId, skills[i] or 0, i - 1) end)
    end
    local gui = getGUIManager()
    if gui then pcall(function() gui:call("setupKeyGuideCustomSkill()") end) end
end

local extraSkillsState = "none"
local extraSkillsSnapshot = nil

local PENDING_WEAPON_MAX_FRAMES = 60
local PENDING_WEAPON_CONFIRM_FRAMES = 5
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
        applyWeaponPresetForJob(jobId)
        if suppressNextRearmEffect then
            suppressNextRearmEffect = false
        else
            queueRearmamentWeaponEffect(jobId)
        end
    end
end

local function weaponEquipMatchesPreset(jobId)
    if not resolveItemManagerMethods() then return false end
    local entry = Config.Vocations[jobId]
    local preset = entry and entry.WeaponPreset
    local wantedIds = {}
    local wantedCount = 0
    if preset and preset.items then
        for _, want in ipairs(preset.items) do
            if not wantedIds[want.ItemId] then wantedCount = wantedCount + 1 end
            wantedIds[want.ItemId] = true
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
            if v._IsEquipped == true and isWeaponEquipSlot(v:call("get_EquipSlot()")) then
                if not wantedIds[v._ItemId] then return false end
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

local function getEquippedWeapons()
    local player = getPlayer()
    if not player then return nil, nil end
    local okR, rw = pcall(function() return player:get_RightWeapon() end)
    local okL, lw = pcall(function() return player:get_LeftWeapon() end)
    return okR and rw or nil, okL and lw or nil
end

queueRearmamentWeaponEffect = function(jobId)
    if not Config.General.RearmamentWeaponEffect then return end
    rearmWeaponEffectSettleJobId = jobId
    rearmWeaponEffectSettleFramesLeft = REARM_WEAPON_EFFECT_SETTLE_FRAMES
end

local directCastNodeName = ""

-- forceChangeDrawingWeapon() and appearWeapon() (Rearmament Weapon Effect,
-- below) both need to run from inside LateUpdateBehavior - calling them
-- directly from on_frame doesn't work reliably. Both are deferred through a
-- pending flag/job id and picked up here on the next LateUpdateBehavior tick.
local rearmEntryOk = pcall(function()
    re.on_application_entry("LateUpdateBehavior", function()
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

        if pendingRearmWeaponEffectJobId then
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

local function checkUnlockJob(human, jobId)
    if not Config.General.UnlockTargetVocation or not human then return end
    pcall(function()
        local jobContext = getJobContext(human)
        if jobContext and not jobContext:isJobQualified(jobId) then
            jobContext:setJobQualified(jobId)
            local gui = getGUIManager()
            if gui then gui:requestGetJobNotice(jobId) end
        end
    end)
end

local function setVocation(jobId)
    if not VOCATIONS[jobId] then
        log.warn("[TWINWV] setVocation: unknown jobId=" .. tostring(jobId))
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

    checkUnlockJob(human, jobId)

    local ok, err = pcall(function()
        local jobchanger = human:call("get_JobChanger()")
        if not jobchanger then error("get_JobChanger() returned nil") end
        jobchanger:requestChangeJob(jobId)
    end)

    if not ok then
        log.error("[TWINWV] requestChangeJob(" .. jobId .. ") threw: " .. tostring(err) ..
            " - likely no longer compatible with the current game version.")
        return false
    end

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
        applyArmorPresetForJob(jobId)
    end
    if Config.General.AutoRememberRings then
        applyRingsPresetForJob(jobId)
    end

    log.info("[TWINWV] -> " .. vocationName(jobId))
    return true
end

local HK = {}

local function registerHotkeysOnce()
    if not hotkeys then return end
    seedDefaultHotkeyModifiers()
    for jobId = 1, 9 do
        HK["TWINWV_Voc" .. jobId] = Config.Vocations[jobId].Key
    end
    HK.TWINWV_ExtraBase = Config.ExtraSkillHotkeys.Base
    HK.TWINWV_ExtraSubA = Config.ExtraSkillHotkeys.SubA
    for slot = 1, NUM_BASE_SLOTS do
        HK["TWINWV_ExtraDirect" .. slot] = Config.ExtraDirectHotkeys["Slot" .. slot]
    end
    HK.TWINWV_CyclePrev = Config.CycleHotkeys.Prev
    HK.TWINWV_CycleNext = Config.CycleHotkeys.Next
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
    Config.CycleHotkeys.Prev = HK.TWINWV_CyclePrev
    Config.CycleHotkeys.Next = HK.TWINWV_CycleNext
end

local function handleVocationSwitchHotkeys()
    if not hotkeys then return end
    for jobId = 1, 9 do
        if hotkeys.check_hotkey("TWINWV_Voc" .. jobId, false, true) then
            setVocation(jobId)
        end
    end
end

local function getCycleOrderList()
    local list = {}
    for jobId = 1, 9 do
        local voc = Config.Vocations[jobId]
        local order = voc and voc.CycleOrder
        if order and order > 0 then
            list[#list + 1] = { jobId = jobId, order = order }
        end
    end
    table.sort(list, function(a, b) return a.order < b.order end)
    return list
end

local function cycleVocation(direction)
    local list = getCycleOrderList()
    if #list == 0 then
        log.warn("[TWINWV] Cycle Vocation: ни у одной профессии не задан Cycle order - нечего листать.")
        return
    end
    if #list == 1 then return end

    local curJob = getCurrentJob()
    local idx = nil
    for i, entry in ipairs(list) do
        if entry.jobId == curJob then idx = i; break end
    end

    local nextIdx
    if not idx then
        nextIdx = (direction > 0) and 1 or #list
    else
        nextIdx = idx + direction
        if nextIdx < 1 then nextIdx = #list end
        if nextIdx > #list then nextIdx = 1 end
    end
    setVocation(list[nextIdx].jobId)
end

local function handleVocationCycleHotkeys()
    if not hotkeys or not Config.General.EnableVocationCycling then return end
    if hotkeys.check_hotkey("TWINWV_CycleNext", false, true) then
        cycleVocation(1)
    elseif hotkeys.check_hotkey("TWINWV_CyclePrev", false, true) then
        cycleVocation(-1)
    end
end

local function handleExtraSkills()
    if not hotkeys then return end
    local job = getCurrentJob()
    if not job or not VOCATIONS[job] then return end

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

    -- Job06 Sorcerer ([24]/[25]/[26]/[27] shared with Mage above)
    [62] = "Job06_Salamander",  -- High Salamander
    [63] = "Job06_Blizzard",    -- High Hagol
    [64] = "Job06_MineVolt",    -- High Thundermine
    [65] = "Job06_SaintDrain",  -- High Decanter
    [66] = "Job06_RockBeat",    -- High Seism
    [67] = "Job06_AddFlare",    -- Augural Flare
    [68] = "Job06_MeteorFall",  -- Meteoron
    [69] = "Job06_VortexRage",  -- Maelstorm

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
                pcall(function() skillCtx:setSkill(pending.job, pending.skillId, slot - 1) end)
            end
            pendingSkillSlotRestore[slot] = nil
        end
    end
end

local function castCustomSkill(player, fieldName)
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
    local setOk = pcall(function() skillCtx:setSkill(job, skillId, slot - 1) end)
    if setOk and castCustomSkill(player, fieldName) then
        pendingSkillSlotRestore[slot] = {
            job = job,
            skillId = snapOk and originalSkillId or 0,
            framesLeft = SKILL_SLOT_RESTORE_DELAY_FRAMES,
        }
        return true
    elseif setOk then
        pcall(function() skillCtx:setSkill(job, (snapOk and originalSkillId) or 0, slot - 1) end)
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
        elseif hotkeys.check_hotkey("TWINWV_ExtraDirect" .. slot, false, true) then
            local skillId = entry.ExtraSkillsA[slot] or 0
            if skillId ~= 0 then
                local fieldName = SKILL_CUSTOM_ID[skillId]
                if not fieldName then
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
        handleVocationSwitchHotkeys()
        handleVocationCycleHotkeys()
        handleExtraSkills()
        handleExtraSkillsDirectCast()
        tickJobRequirementToggles()
        tickPendingWeaponApply()
        tickRearmWeaponEffectSettle()
    end)
    if not ok then log.error("[TWINWV] on_frame error: " .. tostring(err)) end
end)

local d2dLib = (d2d ~= nil and d2d) or (d2dx ~= nil and d2dx) or nil
local iconImages = {}
local flashFramesLeft = 0
local lastKnownJob = nil
local surfaceW, surfaceH = 1920, 1080

local ANCHORS = { "TopLeft", "TopCenter", "TopRight", "Center", "BottomLeft", "BottomCenter", "BottomRight" }

local function computeIconPos(iw, ih)
    local ox, oy = Config.Icon.OffsetX, Config.Icon.OffsetY
    local anchor = Config.Icon.Anchor
    local x, y

    if anchor == "TopLeft" then x, y = ox, oy
    elseif anchor == "TopCenter" then x, y = surfaceW / 2 - iw / 2 + ox, oy
    elseif anchor == "TopRight" then x, y = surfaceW - ox - iw, oy
    elseif anchor == "Center" then x, y = surfaceW / 2 - iw / 2 + ox, surfaceH / 2 - ih / 2 + oy
    elseif anchor == "BottomLeft" then x, y = ox, surfaceH - oy - ih
    elseif anchor == "BottomCenter" then x, y = surfaceW / 2 - iw / 2 + ox, surfaceH - oy - ih
    elseif anchor == "BottomRight" then x, y = surfaceW - ox - iw, surfaceH - oy - ih
    else x, y = ox, oy end

    return x, y
end

if d2dLib then
    d2dLib.register(function()
        surfaceW, surfaceH = d2dLib.surface_size()
        for jobId, voc in pairs(VOCATIONS) do
            local full = d2dLib.Image.new("dd2-" .. voc.image .. ".png")
            local small = d2dLib.Image.new("dd2-" .. voc.image .. "-50.png")
            iconImages[jobId] = { full = full, small = small }
        end
    end, function()
        if not Config.Icon.Enabled then return end
        if isGuiPaused() then return end
        local job = getCurrentJob()
        if not job or not iconImages[job] then return end

        if job ~= lastKnownJob then
            if lastKnownJob ~= nil and Config.Icon.FlashOnSwitch then
                flashFramesLeft = Config.Icon.FlashDurationFrames
            end
            lastKnownJob = job
        end

        local icon = iconImages[job]
        local baseScale = Config.Icon.Scale / 100
        local scale = (flashFramesLeft > 0)
            and (baseScale * (1 + Config.Icon.FlashScale / 100))
            or baseScale
        local img = (flashFramesLeft > 0) and icon.full or icon.small
        if img then
            local iw, ih = img:size()
            iw, ih = iw * scale, ih * scale
            local x, y = computeIconPos(iw, ih)
            d2dLib.image(img, x, y, iw, ih)
        end
        if flashFramesLeft > 0 then flashFramesLeft = flashFramesLeft - 1 end
    end)
else
    log.warn("[TWINWV] d2d/d2dx not found - vocation icon disabled (switching and skills still work without it).")
end

re.on_draw_ui(function()
    if not imgui.tree_node(tr("menu_title")) then return end

    local changed = false

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
        if lc then Config.Language = LANGUAGES[langIdx]; changed = true end

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

        imgui.spacing()
        sectionHeader(tr("gs_vocation_subheader"))
        c1, Config.General.UnlockTargetVocation = imgui.checkbox(tr("gs_unlock_vocation"), Config.General.UnlockTargetVocation)
        if imgui.is_item_hovered() then imgui.set_tooltip(tr("gs_unlock_vocation_tip")) end
        changed = changed or c1

        boxEnd(false)
        popBoxTheme()

        pushBoxTheme()
        boxBegin(false)

        sectionHeader(tr("gs_extra_skill_hotkeys_header"))
        mutedText(tr("gs_extra_skill_hotkeys_note"))
        if hotkeys then
            changed = hotkeys.hotkey_setter("TWINWV_ExtraBase", nil, tr("gs_extra_base_group")) or changed
            imgui.same_line()
            changed = hotkeys.hotkey_setter("TWINWV_ExtraSubA", nil, tr("gs_extra_seta_group")) or changed

            imgui.spacing()
            sectionHeader(tr("gs_extra_direct_cast_header"))
            local dc
            dc, Config.General.ExtraSkillsDirectCast = imgui.checkbox(tr("gs_extra_direct_cast_enable"), Config.General.ExtraSkillsDirectCast)
            changed = changed or dc

            if Config.General.ExtraSkillsDirectCast then
                imgui.text_colored(tr("gs_extra_direct_cast_broken_intro"), UI_DANGER_COLOR)
                imgui.text_colored(tr("gs_extra_direct_cast_broken_warrior_name") .. ":", VOCATION_COLOR[5].color)
                imgui.same_line()
                imgui.text(" " .. tr("gs_extra_direct_cast_broken_warrior_skills"))
                imgui.text_colored(tr("gs_extra_direct_cast_broken_mystic_spearhand_name") .. ":", VOCATION_COLOR[7].color)
                imgui.same_line()
                imgui.text(" " .. tr("gs_extra_direct_cast_broken_mystic_spearhand_skills"))
                imgui.text_colored(tr("gs_extra_direct_cast_broken_magick_archer_name") .. ":", VOCATION_COLOR[8].color)
                imgui.same_line()
                imgui.text(" " .. tr("gs_extra_direct_cast_broken_magick_archer_skills"))
                imgui.spacing()

                for slot = 1, NUM_BASE_SLOTS do
                    changed = hotkeys.hotkey_setter("TWINWV_ExtraDirect" .. slot, nil,
                        string.format(tr("slot_fmt"), slot)) or changed
                    if slot % 3 ~= 0 then imgui.same_line() end
                end
            end
        else
            mutedText("Hotkeys module not found - hotkeys unavailable.")
        end

        boxEnd(false)
        popBoxTheme()

        pushBoxTheme()
        boxBegin(false)

        sectionHeader(tr("gs_cycle_hotkeys_header"))
        mutedText(tr("gs_cycle_hotkeys_note"))
        c1, Config.General.EnableVocationCycling = imgui.checkbox(tr("gs_cycle_enable"), Config.General.EnableVocationCycling)
        if imgui.is_item_hovered() then imgui.set_tooltip(tr("gs_cycle_enable_tip")) end
        changed = changed or c1
        if hotkeys then
            changed = hotkeys.hotkey_setter("TWINWV_CyclePrev", nil, tr("gs_cycle_prev_group")) or changed
            imgui.same_line()
            changed = hotkeys.hotkey_setter("TWINWV_CycleNext", nil, tr("gs_cycle_next_group")) or changed
        else
            mutedText("Hotkeys module not found - hotkeys unavailable.")
        end

        boxEnd(false)
        popBoxTheme()

        imgui.tree_pop()
    end

    local function drawVocationBox(jobId, nested, boxWidth)
        local voc = VOCATIONS[jobId]
        local entry = Config.Vocations[jobId]

        pushBoxTheme()
        boxBegin(nested, boxWidth)

        vocationHeader(jobId)

            if hotkeys and not Config.General.EnableVocationCycling then
                changed = hotkeys.hotkey_setter("TWINWV_Voc" .. jobId, nil, tr("voc_key_label")) or changed
            end

            if Config.General.EnableVocationCycling then
                imgui.text(tr("voc_cycle_order_label") .. ":")
                imgui.same_line()
                pushItemWidth(110)
                local cycleChanged, newCycleOrder = imgui.slider_int(
                    "##cycleorder" .. jobId, entry.CycleOrder or 0, 0, 9)
                popItemWidth()
                if cycleChanged and newCycleOrder ~= (entry.CycleOrder or 0) then
                    if newCycleOrder ~= 0 then
                        for otherId = 1, 9 do
                            if otherId ~= jobId and Config.Vocations[otherId].CycleOrder == newCycleOrder then
                                newCycleOrder = 0
                                break
                            end
                        end
                    end
                    entry.CycleOrder = newCycleOrder
                    changed = true
                end
                if imgui.is_item_hovered() then imgui.set_tooltip(tr("voc_cycle_order_tip")) end
            end

            imgui.spacing()
            if imgui.tree_node(tr("extra_skills_header") .. "##extraskills" .. jobId) then
                local labels, ids, filtered = extraSkillOptionsForJob(jobId)
                if not filtered then
                    mutedText(tr("learned_warning"))
                    imgui.spacing()
                end
                local idToIndex = {}
                for i, sid in ipairs(ids) do idToIndex[sid] = i - 1 end

                mutedText(string.format(tr("extra_set_a_fmt"), Config.ExtraSkillHotkeys.SubA))
                for slot = 1, NUM_BASE_SLOTS do
                    local cur = entry.ExtraSkillsA[slot]
                    if cur == nil then cur = 0 end
                    local curIndex = idToIndex[cur] or 0
                    imgui.text(string.format(tr("slot_fmt"), slot) .. ":")
                    imgui.same_line()
                    pushItemWidth(Config.Language == "ru" and 190 or 150)
                    local ic
                    ic, curIndex = imgui.combo("##A" .. jobId .. slot, curIndex, labels)
                    popItemWidth()
                    if ic then
                        entry.ExtraSkillsA[slot] = ids[curIndex + 1] or 0
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

    if imgui.tree_node(tr("section_icon")) then
        if not d2dLib then mutedText("d2d/d2dx not found - icon unavailable.") end
        local c

        pushBoxTheme()
        boxBegin(false)

        sectionHeader(tr("icon_position_header"))
        mutedText(tr("icon_position_desc"))

        c, Config.Icon.Enabled = imgui.checkbox(tr("icon_enabled"), Config.Icon.Enabled)
        changed = changed or c

        local anchorIdx = 1
        for i, a in ipairs(ANCHORS) do if a == Config.Icon.Anchor then anchorIdx = i end end
        local ac
        pushItemWidth()
        ac, anchorIdx = imgui.combo(tr("icon_anchor"), anchorIdx, ANCHORS)
        if ac then Config.Icon.Anchor = ANCHORS[anchorIdx]; changed = true end

        c, Config.Icon.OffsetX = imgui.slider_int(tr("icon_offset_x"), Config.Icon.OffsetX, 0, 1000)
        if c then Config.Icon.OffsetX = roundToStep(Config.Icon.OffsetX, 10, 0, 1000) end
        changed = changed or c
        c, Config.Icon.OffsetY = imgui.slider_int(tr("icon_offset_y"), Config.Icon.OffsetY, 0, 1000)
        if c then Config.Icon.OffsetY = roundToStep(Config.Icon.OffsetY, 10, 0, 1000) end
        changed = changed or c
        c, Config.Icon.Scale = imgui.slider_int(tr("icon_scale"), Config.Icon.Scale, 10, 150)
        changed = changed or c
        popItemWidth()

        boxEnd(false)
        popBoxTheme()

        pushBoxTheme()
        boxBegin(false)

        sectionHeader(tr("icon_flash_header"))
        mutedText(tr("icon_flash_desc"))

        c, Config.Icon.FlashOnSwitch = imgui.checkbox(tr("icon_flash"), Config.Icon.FlashOnSwitch)
        changed = changed or c
        if Config.Icon.FlashOnSwitch then
            pushItemWidth()
            c, Config.Icon.FlashScale = imgui.slider_int(tr("icon_flash_scale"), Config.Icon.FlashScale, 0, 100)
            changed = changed or c
            c, Config.Icon.FlashDurationFrames = imgui.slider_int(tr("icon_flash_duration"), Config.Icon.FlashDurationFrames, 30, 180)
            if c then Config.Icon.FlashDurationFrames = roundToStep(Config.Icon.FlashDurationFrames, 10, 30, 180) end
            changed = changed or c
            popItemWidth()
        end

        boxEnd(false)
        popBoxTheme()

        imgui.tree_pop()
    end

    if changed then
        syncHotkeysToConfig()
        saveConfig()
    end

    imgui.tree_pop()
end)

log.info("[TWINWV] loaded")
