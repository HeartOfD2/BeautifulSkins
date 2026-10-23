-- Whisper Messenger: the look. Whisper Messenger paints itself from its own theme presets and reads its settings once,
-- when it loads. So instead of painting over its window, this skin chooses Whisper Messenger's own flat frame
-- ("hudStyle" off), its dark jade preset (EllesmereUI's accent family) and the EllesmereUI font through Whisper
-- Messenger's saved settings, before Whisper Messenger reads them. The previous values are kept and put back when the
-- skin is switched off. The chat button (Modules\WhisperButton.lua) also asks for Whisper Messenger's floating icon
-- ("iconMode" widget) so it can read the unread count from it while it stays hidden.
local _, ns = ...
local L = ns.L

local ADDON = "WhisperMessenger"
local PRESET = "jade_dark"
local HUD_FLAT = "off"

local M = ns.Modules.Register("whisper", { addon = ADDON, setting = "whisper", label = "Whisper Messenger: look" })
ns.WhisperLook = M

local function WMSettings()
    local db = rawget(_G, "WhisperMessengerDB")
    if type(db) ~= "table" then return nil end
    if type(db.settings) ~= "table" then db.settings = {} end
    return db.settings
end

local function SamePath(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    return a:gsub("/", "\\"):lower() == b:gsub("/", "\\"):lower()
end

-- Name under which our font is registered in LibSharedMedia (Whisper Messenger's font menu lists those names).
local function FontName()
    if not ns.HasEUI() then return nil end
    local path = ns.Font()
    local lib = rawget(_G, "LibStub")
    local ok, lsm = pcall(function() return lib and lib("LibSharedMedia-3.0", true) end)
    if not (ok and lsm and type(lsm.HashTable) == "function") then return nil end
    local okList, list = pcall(lsm.HashTable, lsm, "font")
    if not (okList and type(list) == "table") then return nil end
    for name, file in pairs(list) do
        if SamePath(file, path) then return name end
    end
    return nil
end

-- Writes the wanted values into Whisper Messenger's settings (or gives its own back). Returns true when something
-- changed. Runs for switched-off skins too, so their values go back.
function M.Write()
    local settings = WMSettings()
    if not (settings and ns.db) then return false end
    local w = ns.db.whisper
    if type(w.backup) ~= "table" then w.backup = {} end
    local backup = w.backup
    local changed = false
    local function Set(key, value)
        if backup[key] == nil then
            local current = settings[key]
            backup[key] = current == nil and false or current -- false = "was not set"
        end
        if settings[key] ~= value then
            settings[key] = value
            changed = true
        end
    end
    local function Restore(key)
        if backup[key] == nil then return end
        local value = backup[key]
        if value == false then value = nil end
        if settings[key] ~= value then changed = true end
        settings[key] = value
        backup[key] = nil
    end

    if ns.Modules.SwitchedOn("whisper") and w.look then
        Set("hudStyle", HUD_FLAT)
        Set("themePreset", PRESET)
        local font = FontName()
        if font then Set("fontFamily", font) else Restore("fontFamily") end
    else
        Restore("hudStyle")
        Restore("themePreset")
        Restore("fontFamily")
    end
    if ns.Modules.SwitchedOn("whisperButton") and w.hideOwnIcons then
        Set("iconMode", "widget")
    else
        Restore("iconMode")
    end
    return changed
end

-- Whisper Messenger has built its window and icon already (it read its settings before we could write them).
local function WMStarted()
    return rawget(_G, "WhisperMessengerToggleIcon") ~= nil or rawget(_G, "WhisperMessengerWindow") ~= nil
        or rawget(_G, "WhisperMessengerMinimapIcon") ~= nil
end

ns.OnReady(function()
    ns.OnAddonLoaded(ADDON, function()
        local started = WMStarted()
        local changed = M.Write()
        M.pendingReload = started and changed
    end)
end)

-- The values Whisper Messenger saves at logout are the ones it starts with next time.
ns.RegisterEvent("PLAYER_LOGOUT", function()
    M.Write()
end)

function M.Enable()
    if M.pendingReload then
        ns.Say(L["Whisper Messenger shows its new look after /reload."])
    end
end

-- Options changed a switch: write at once; Whisper Messenger takes it on the next /reload.
function M.OptionChanged()
    if M.Write() then
        ns.Say(L["Whisper Messenger takes this change after /reload."])
    end
end
