-- Options described once as data and drawn by two renderers: Settings\EUIPages.lua (a section in the EllesmereUI
-- options window) and Settings\Panel.lua (the game's options, without EllesmereUI).
-- Row types (all may carry tip; only = "eui" for rows the game's panel cannot draw):
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

local function GeneralRows()
    local accentGet, accentSet = Field(nil, "accentMode")
    local langGet, langSet = Field(nil, "language", function() ns.Say(L["Takes effect after /reload."]) end)
    local colorGet, colorSet = ColorField(nil, "accentCustom")
    return {
        { type = "header", text = L["APPEARANCE"] },
        { type = "dropdown", text = L["Accent colour"], get = accentGet, set = accentSet,
            values = Values({ { "eui", L["EllesmereUI accent"] }, { "class", L["Class colour"] }, { "custom", L["Own colour"] } }),
            tip = L["Colour of headings, dividers, the arrow and the waypoint. Without EllesmereUI the EllesmereUI accent is jade."] },
        { type = "color", text = L["Own colour"], get = colorGet, set = colorSet, only = "eui",
            enabled = function() return ns.db.accentMode == "custom" end },
        { type = "dropdown", text = L["Language"], get = langGet, set = langSet,
            values = Values({ { "auto", L["Automatic"] }, { "enUS", "English" }, { "deDE", "Deutsch" } }) },
        Toggle(L["Options in EllesmereUI"], nil, "integrateEUI", L["Takes effect after /reload."],
            function() ns.Say(L["Takes effect after /reload."]) end),
        { type = "header", text = L["SKINS"] },
        ModuleToggle("whisper", L["Whisper Messenger: look"]),
        ModuleToggle("whisperButton", L["Whisper Messenger: chat button"]),
        ModuleToggle("gqTracker", L["GearQuest: tracker"]),
        ModuleToggle("gqArrow", L["GearQuest: arrow"]),
        ModuleToggle("gqWindow", L["GearQuest: window"]),
        ModuleToggle("gqPopups", L["GearQuest: popups and toasts"]),
        ModuleToggle("skillup", L["SkillUp Forever: reagents tracker"]),
        ModuleToggle("waypoint", L["Waypoint UI: colours"]),
        { type = "button", text = L["Reload UI"], onClick = Reload },
        { type = "button", text = L["Reset all settings"], onClick = function()
            ns.ResetSettings()
            ns.Say(L["Settings reset. /reload applies every part."])
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
    return {
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
        { type = "color", text = L["Own colour"], get = customGet, set = customSet, only = "eui",
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

local function InfoRows()
    return {
        { type = "header", text = L["INFO"] },
        { type = "text", get = function()
            local lines = { ("BeautifulSkins %s"):format(ns.Version()) }
            for _, def in ipairs(ns.Modules.order) do
                lines[#lines + 1] = ("%s: %s"):format(L[def.label or def.id], ns.ModuleStatus(def))
            end
            return table.concat(lines, "\n")
        end },
        { type = "text", get = function()
            return L["Unofficial skins. Not affiliated with the authors of the skinned addons or of EllesmereUI."]
        end },
    }
end

-- Pages, built at call time (the locale is final only after ADDON_LOADED).
function Settings.Pages()
    return {
        { key = "general", label = L["General"], rows = GeneralRows },
        { key = "whisper", label = "Whisper Messenger", rows = WhisperRows },
        { key = "gearquest", label = "GearQuest", rows = GearQuestRows },
        { key = "other", label = L["SkillUp & Waypoint"], rows = OtherRows },
        { key = "info", label = L["Info"], rows = InfoRows },
    }
end
