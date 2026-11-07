-- Options of the Extras skins as row data; the host draws them (its own window and the EllesmereUI section, see the
-- host's Settings\Settings.lua for every row type). Registered as one module with four pages.
-- Row types used here (all may carry tip):
--   header { text }   toggle { text, get, set }   slider { text, min, max, step, get, set }
--   dropdown { text, values() -> labels, order, get, set }   button { text, onClick }
--   color { text, get() -> r, g, b, set(r, g, b), enabled() -> bool }   text { get() -> text }
local _, ns = ...
local L = ns.L

local Settings = {}
ns.Settings = Settings

local function Reload()
    if type(ReloadUI) == "function" then ReloadUI() end
end

local function Refresh()
    ns.RefreshAll()
end

-- get/set pair for ns.db[section][key] (section nil = top level); after(value) runs after a change.
local function Field(section, key, after)
    local function Tbl() return section and ns.db[section] or ns.db end
    return function() return Tbl()[key] end, function(value)
        Tbl()[key] = value
        if after then after(value) else Refresh() end
    end
end

local function ColorField(section, key)
    local function Tbl() return section and ns.db[section] or ns.db end
    return function()
        local c = Tbl()[key]
        return c.r, c.g, c.b
    end, function(r, g, b)
        Tbl()[key] = { r = r, g = g, b = b }
        Refresh()
    end
end

local function Toggle(text, section, key, tip, after)
    local get, set = Field(section, key, after)
    return { type = "toggle", text = text, get = function() return get() ~= false end, set = set, tip = tip }
end

local function ModuleToggle(id, text)
    local get, set = Field("modules", id, function()
        if (id == "whisper" or id == "whisperButton") and ns.WhisperLook then ns.WhisperLook.OptionChanged() end
        ns.Say(ns.L["Takes effect after /reload."])
    end)
    return { type = "toggle", text = text, get = function() return get() ~= false end, set = set,
        tip = L["Takes effect after /reload."] }
end

local function Values(pairsList)
    return function()
        local labels, order = {}, {}
        for i, p in ipairs(pairsList) do
            labels[p[1]] = p[2]
            order[i] = p[1]
        end
        return labels, order
    end
end

local function SkinRows()
    return {
        { type = "header", text = L["SKINS"] },
        { type = "text", text = L["Each skin works only while its addon is installed. Changes take effect after a reload."] },
        ModuleToggle("whisper", L["Whisper Messenger: look"]),
        ModuleToggle("whisperButton", L["Whisper Messenger: chat button"]),
        ModuleToggle("gqTracker", L["GearQuest: tracker"]),
        ModuleToggle("gqArrow", L["GearQuest: arrow"]),
        ModuleToggle("gqWindow", L["GearQuest: window"]),
        ModuleToggle("gqPopups", L["GearQuest: popups and toasts"]),
        ModuleToggle("skillup", L["SkillUp Forever: reagents tracker"]),
        ModuleToggle("waypoint", L["Waypoint UI: colours"]),
        ModuleToggle("openmap", L["OpenMap: new map menu"]),
        { type = "toggle", text = L["OpenMap: map pins"], refresh = true,
            tip = L["Off takes OpenMap's map pins away completely (\"Drop a pin\", the pin list, the pins on the map). Works at once."],
            get = function() return ns.OpenMap.PinsOn() end, set = function(v) ns.OpenMap.SetPins(v) end },
        { type = "toggle", text = L["OpenMap: quill"], refresh = true,
            tip = L["Off takes OpenMap's quill away completely (drawing on the map, your drawings). Works at once."],
            get = function() return ns.OpenMap.QuillOn() end, set = function(v) ns.OpenMap.SetQuill(v) end },
        { type = "button", text = L["Reload UI"], onClick = Reload },
        { type = "header", text = L["STATE"] },
        { type = "text", get = function()
            local lines = {}
            for _, def in ipairs(ns.Modules.order) do
                lines[#lines + 1] = ("%s: %s"):format(L[def.label or def.id], ns.ModuleStatus(def))
            end
            return table.concat(lines, "\n")
        end },
        { type = "header", text = L["RESET"] },
        { type = "button", text = L["Reset these skins"], onClick = function()
            ns.host.Confirm("extrasReset", L["Reset the options of the GearQuest, SkillUp, Whisper and Waypoint skins?"],
                function()
                    ns.ResetSettings()
                    ns.Say(L["Settings reset. /reload applies every part."])
                end)
        end },
    }
end

local function WhisperRows()
    local cornerGet, cornerSet = Field("whisper", "corner")
    local function Changed()
        if ns.WhisperLook then ns.WhisperLook.OptionChanged() end
        Refresh()
    end
    return {
        { type = "header", text = L["WHISPER MESSENGER"] },
        Toggle(L["Dark flat look"], "whisper", "look",
            L["Whisper Messenger's dark jade preset, its flat frame and the EllesmereUI font. Takes effect after /reload."],
            Changed),
        Toggle(L["Hide Whisper Messenger's own icons"], "whisper", "hideOwnIcons",
            L["Only our chat button stays (with the number of unread whispers)."], Changed),
        { type = "header", text = L["CHAT BUTTON"] },
        { type = "text", get = function()
            return L["With EllesmereUI Chat the button sits in the chat sidebar below the last icon. With \"Free Move Icons\" on in EllesmereUI it moves with Shift-drag."]
        end },
        { type = "button", text = L["Reset button position"], onClick = function()
            if ns.WhisperButton then ns.WhisperButton.ResetPosition() end
        end },
        { type = "dropdown", text = L["Corner without EllesmereUI Chat"], get = cornerGet, set = cornerSet,
            values = Values({ { "TOPRIGHT", L["Top right"] }, { "TOPLEFT", L["Top left"] },
                { "BOTTOMRIGHT", L["Bottom right"] }, { "BOTTOMLEFT", L["Bottom left"] } }) },
        Toggle(L["Show only on mouse-over"], "whisper", "hover",
            L["Without EllesmereUI Chat: the button shows while the mouse is over the chat or a whisper is unread."]),
        Toggle(L["Glow while a whisper is unread"], "whisper", "glow"),
    }
end

local function GearQuestRows()
    local styleGet, styleSet = Field("arrow", "style")
    local colorModeGet, colorModeSet = Field("arrow", "color")
    local unitGet, unitSet = Field("arrow", "unit")
    local scaleGet, scaleSet = Field("arrow", "scale")
    local bgGet, bgSet = Field("gqTracker", "background")
    local customGet, customSet = ColorField("arrow", "customColor")
    local rows = {
        { type = "header", text = L["TRACKER"] },
        Toggle(L["Hunts in the Forever tracker column"], "gqTracker", "column",
            L["One tracker for Shortest Path, SkillUp and GearQuest: the hunts become a section of the Forever tracker column and GearQuest's own tracker hides. The arrow is then free. Takes effect after /reload."],
            function() ns.Say(L["Takes effect after /reload."]) end),
        { type = "slider", text = L["Background opacity"], min = 0, max = 100, step = 5, get = bgGet, set = bgSet },
        { type = "header", text = L["ARROW"] },
        { type = "dropdown", text = L["Style"], get = styleGet, set = styleSet,
            values = Values({ { "CHEVRON", L["Chevron"] }, { "RING", L["Ring"] }, { "PILL", L["Pill"] }, { "CLASSIC", L["Classic"] } }) },
        { type = "dropdown", text = L["Colour"], get = colorModeGet, set = colorModeSet,
            values = Values({ { "ACCENT", L["Accent"] }, { "DIRECTION", L["By direction"] }, { "CUSTOM", L["Own colour"] } }),
            tip = L["By direction: green ahead, yellow to the side, red behind."] },
        { type = "color", text = L["Own colour"], get = customGet, set = customSet,
            enabled = function() return ns.db.arrow.color == "CUSTOM" end },
        { type = "slider", text = L["Size"], min = 0.5, max = 1.5, step = 0.05, get = scaleGet, set = scaleSet },
        { type = "dropdown", text = L["Distance unit"], get = unitGet, set = unitSet,
            values = Values({ { "yd", L["Yards"] }, { "m", L["Metres"] } }) },
        Toggle(L["Show distance"], "arrow", "showDistance"),
        Toggle(L["Show the hunt's name"], "arrow", "showName"),
        Toggle(L["Free arrow"], "arrow", "detached",
            L["The arrow sits on its own frame instead of above GearQuest's tracker (always free with the tracker column)."]),
        Toggle(L["Lock the free arrow"], "arrow", "locked", L["Unlocked: drag the arrow with the left mouse button."]),
        { type = "button", text = L["Reset arrow position"], onClick = function()
            if ns.GearQuestArrow then ns.GearQuestArrow.ResetPosition() end
        end },
        { type = "header", text = L["WINDOW"] },
        { type = "toggle", text = L["Show GearQuest's portrait"],
            get = function() return not ns.db.gqWindow.hidePortrait end,
            set = function(on)
                ns.db.gqWindow.hidePortrait = not on
                ns.Say(L["Takes effect after /reload."])
            end,
            tip = L["The round picture in the top left corner of GearQuest's window. Takes effect after /reload."] },
    }
    -- With the RestedXP pack the hunts use its arrow (style, colour, size, position are set there): these rows are off.
    local inArrow = false
    for _, row in ipairs(rows) do
        if row.type == "header" then inArrow = row.text == L["ARROW"] end
        if inArrow and row.type ~= "header" then
            local own = row.enabled
            row.enabled = function()
                if type(ns.GQArrowShared) == "function" and ns.GQArrowShared() then return false end
                return own == nil or own()
            end
        end
    end
    return rows
end

local function OtherRows()
    local skillGet, skillSet = Field("skillup", "background")
    local colorGet, colorSet = Field("waypoint", "color", function() ns.Say(L["Takes effect with the next waypoint."]) Refresh() end)
    return {
        { type = "header", text = L["SKILLUP FOREVER"] },
        { type = "slider", text = L["Background opacity"], min = 0, max = 100, step = 5, get = skillGet, set = skillSet },
        { type = "header", text = L["WAYPOINT UI"] },
        { type = "dropdown", text = L["Colour"], get = colorGet, set = colorSet,
            values = Values({ { "accent", L["Accent"] }, { "own", L["Waypoint UI's colours"] } }),
            tip = L["Waypoint UI's colours show the quest state (complete, repeatable, important)."] },
        Toggle(L["Tint the icon as well"], "waypoint", "recolorIcon"),
        Toggle(L["EllesmereUI font for the texts"], "waypoint", "font", L["Takes effect after /reload."]),
    }
end

-- One module in the host's options: four pages (keys carry the pack prefix, page keys are unique over all packs).
function Settings.Modules()
    local list = {
        { key = "Extras", title = L["More skins"], desc = L["GearQuest, SkillUp, Whisper Messenger, Waypoint UI and OpenMap."],
            pages = {
                { key = "extras.skins", label = L["Skins"], rows = SkinRows },
                { key = "extras.whisper", label = "Whisper Messenger", rows = WhisperRows },
                { key = "extras.gearquest", label = "GearQuest", rows = GearQuestRows },
                { key = "extras.other", label = L["SkillUp & Waypoint"], rows = OtherRows },
            } },
    }
    local openmap = ns.OpenMapSettings and ns.OpenMapSettings.Module()
    if openmap then list[#list + 1] = openmap end
    return list
end
