-- Options of the RestedXP skin as row data; the host draws them in its own window and in the EllesmereUI section (row
-- types: the host's Settings\Settings.lua). Two modules: the guide window (General, Fonts, Colors) and navigation
-- (Arrow with live preview, Compass bar, Journey, Map). Options only write ns.db and ask for a refresh; the skin parts
-- apply them (ns.RefreshAll).
local _, ns = ...
local L = ns.L

local SKIN_HINT = {
    MISSING = L["EllesmereUIBlizzardSkin is not loaded: the guide window skin is off and the colours use the fallback or custom colour."],
    MASTER = L["Skinning of other addons is switched off in EllesmereUI: the guide window skin is off (it returns after /reload once skinning is on)."],
    ADDON = L["Skinning of BeautifulRestedXP is switched off in EllesmereUI (Third-Party Addons): the guide window skin is off (it returns after /reload once skinning is on)."],
    SILENT = L["EllesmereUI has not applied its skin to BeautifulRestedXP: the guide window skin is off (it returns after /reload once the skin is applied)."],
}

local NO_SPF = L["ShortestPathForever is not loaded."]

---------------------------------------------------------------------------
-- Row helpers
---------------------------------------------------------------------------

-- After a change: let the parts apply it; sync names the option whose ShortestPathForever counterpart follows.
local function Changed(opt)
    if opt.sync then
        ns.SPF.OnOptionChanged(opt.sync)
    elseif opt.rxpArrow then
        ns.RXPArrow.OnOptionChanged()
    else
        ns.RefreshAll()
    end
end

local function Values(map, order)
    return function()
        local labels = {}
        for k, v in pairs(map) do labels[k] = v end
        return labels, order
    end
end

-- kind: toggle | slider | dropdown. opt: min, max, step, values, order, tip, enabled, get/set (value transforms),
-- page (other rows depend on it), sync, rxpArrow.
local function Row(section, key, kind, text, opt)
    opt = opt or {}
    local row = {
        type = kind, text = L[text], tip = opt.tip and L[opt.tip] or nil,
        min = opt.min, max = opt.max, step = opt.step,
        enabled = opt.enabled, refresh = opt.page,
        get = function()
            local v = ns.db[section][key]
            if opt.get then return opt.get(v) end
            if kind == "toggle" then return v and true or false end
            return v
        end,
        set = function(v)
            if opt.set then v = opt.set(v) end
            ns.db[section][key] = v
            Changed(opt)
        end,
    }
    if kind == "dropdown" then row.values = Values(opt.values, opt.order) end
    return row
end

local function ColorOf(c, default)
    if type(c) == "table" and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
        return c.r, c.g, c.b
    end
    return default[1], default[2], default[3]
end

local function ColorRow(text, get, set, opt)
    opt = opt or {}
    return {
        type = "color", text = L[text], tip = opt.tip and L[opt.tip] or nil, enabled = opt.enabled,
        get = get,
        set = function(r, g, b)
            set(r, g, b)
            Changed(opt)
        end,
    }
end

-- ShortestPathForever-backed rows: the value lives in SPF; reading and writing go through the bridge.
local function SpfRow(key, kind, text, opt)
    opt = opt or {}
    return {
        type = kind, text = L[text], tip = opt.tip and L[opt.tip] or nil,
        min = opt.min, max = opt.max, step = opt.step,
        enabled = function() return ns.SPF.Has(key) end,
        get = function()
            local v = ns.SPF.Get(key)
            if kind == "toggle" then return v == true end
            return type(v) == "number" and v or opt.min
        end,
        set = function(v) ns.SPF.Set(key, v) end,
    }
end

local function Header(text)
    return { type = "header", text = L[text] }
end

local function Note(text, cond)
    return { type = "text", text = text, cond = cond }
end

local function Percent(default)
    return function(v) return math.floor((type(v) == "number" and v or default) * 100 + 0.5) end,
        function(v) return v / 100 end
end

---------------------------------------------------------------------------
-- Guide window
---------------------------------------------------------------------------

local function GeneralRows()
    local off, reason = ns.SkinningOff()
    local tintGet, tintSet = Percent(0.12)
    local skinOn = function() return not ns.SkinningOff() end
    return {
        Header("GUIDE WINDOW"),
        { type = "text", cond = function() return off end,
          text = SKIN_HINT[reason] or SKIN_HINT.SILENT },
        Row("guide", "enabled", "toggle", "Restyle RestedXP", {
            page = true, tip = "Switches the whole guide window skin on or off. Off gives RestedXP's own look back." }),
        { type = "toggle", text = L["Use the theme in RestedXP"], enabled = skinOn,
          tip = L["Sets RestedXP's own theme setting to the BeautifulRestedXP theme. Off: RestedXP's previous theme."],
          get = function() return ns.ThemeActive() and true or false end,
          set = function(on) ns.SetThemeActive(on and true or false) end },

        Header("DISPLAY"),
        Row("guide", "layout", "dropdown", "Layout", {
            values = { COMPACT = L["Compact"], STANDARD = L["RestedXP standard"] }, order = { "COMPACT", "STANDARD" },
            tip = "Compact is the EllesmereUI look; RestedXP standard leaves the window as RestedXP draws it.",
        }),
        Row("guide", "alpha", "slider", "Window opacity", { min = 0.3, max = 1, step = 0.05 }),
        Row("guide", "width", "slider", "Window width", {
            min = 230, max = 480, step = 10,
            get = function(v) return (type(v) == "number" and v >= 240) and v or 230 end,
            set = function(v) return v < 240 and 0 or v end,
            tip = "The lowest position (230) keeps the width RestedXP uses. Higher values set the width in pixels (240 to 480).",
        }),
        Row("guide", "followAccent", "toggle", "Follow the accent colour", {
            page = true, tip = "Off: the accent colour set on the Colors page is used.",
        }),
        Row("guide", "tint", "slider", "Background tint (%)", {
            min = 0, max = 30, step = 1, get = tintGet, set = tintSet,
            tip = "How strongly the accent colour tints the window background.",
        }),
        Row("guide", "header", "toggle", "Show header"),
        Row("guide", "border", "dropdown", "Border", {
            values = { NONE = L["None"], THIN = L["Thin (1 px)"] }, order = { "NONE", "THIN" },
        }),
        Row("guide", "growth", "dropdown", "Window grows", {
            values = { UP = L["Upwards"], DOWN = L["Downwards"] }, order = { "UP", "DOWN" },
            tip = "Which edge of the window stays in place when its height changes.",
        }),

        Header("STEPS"),
        Row("guide", "upcoming", "slider", "Upcoming steps", {
            min = 0, max = 5, step = 1,
            tip = "How many upcoming steps are listed. This also sets the window height; the mouse wheel scrolls through the whole guide.",
        }),
        Row("guide", "stepNumbers", "toggle", "Step numbers"),
        Row("guide", "progress", "toggle", "Progress bar"),
        Row("guide", "lockBoxes", "toggle", "Pin target icons to the window", {
            tip = "Keeps RestedXP's item and target boxes on the edge of the window. Drag a box (Alt, if RestedXP locks its frames) to move it along the edge or to another edge. Changes apply outside of combat.",
        }),
        Row("guide", "boxEdge", "dropdown", "Box position", {
            values = { AUTO = L["Automatic"], BOTTOM = L["Bottom"], TOP = L["Top"], LEFT = L["Left"], RIGHT = L["Right"] },
            order = { "AUTO", "BOTTOM", "TOP", "LEFT", "RIGHT" },
            tip = "Which edge of the window the item and target boxes sit on. Automatic uses the bottom edge unless there is no room under the window.",
        }),

        Header("BEHAVIOR"),
        Row("guide", "hideCombat", "toggle", "Hide in combat"),
        Row("guide", "hideInstance", "toggle", "Hide in instances"),
        Row("guide", "blockV2", "toggle", "Block guide window v2 (needs /reload)", {
            tip = "RestedXP's beta window v2 replaces the classic window that BeautifulRestedXP styles. On: v2 is switched off in RestedXP; type /reload afterwards.",
        }),
        Row("guide", "animations", "dropdown", "Animations", {
            values = { OFF = L["Off"], SUBTLE = L["Subtle"] }, order = { "OFF", "SUBTLE" },
        }),

        Header("RESET"),
        { type = "button", text = L["Reset window position"], onClick = function()
            if not ns.GuideSkin.ResetPosition() then ns.Say(L["The guide window is not available."]) end
        end },
        { type = "button", text = L["Reset to defaults"], onClick = function()
            ns.host.Confirm("rxpReset", L["Reset every RestedXP skin option to its default?"], function()
                ns.ResetToDefaults()
                ns.Say(L["BeautifulRestedXP options were reset to the defaults."])
            end)
        end },
    }
end

local function FontRows()
    return {
        Header("FONT"),
        Row("guide", "font", "dropdown", "Font", {
            values = { EUI = L["Follow the skin font"], GAME = L["Game font"] }, order = { "EUI", "GAME" },
            tip = "Follow the skin font uses the font chosen under General > Appearance (with EllesmereUI: its font). The game font is the client's default font.",
        }),
        Header("SIZES"),
        Row("guide", "sizeTitle", "slider", "Title", { min = 12, max = 20, step = 1 }),
        Row("guide", "sizeGoal", "slider", "Current step", { min = 11, max = 20, step = 1 }),
        Row("guide", "sizeRow", "slider", "Upcoming steps text", { min = 11, max = 16, step = 1 }),
    }
end

local function ColorRows()
    local guide = function() return ns.db.guide end
    local ownWindow = function() return type(guide().background) == "table" end
    local ownProgress = function() return type(guide().progressColor) == "table" end
    local WINDOW = { 0x16 / 255, 0x16 / 255, 0x18 / 255 }
    return {
        Header("ACCENT"),
        ColorRow("Accent colour",
            function() return ColorOf(guide().customColor, ns.FALLBACK_ACCENT) end,
            function(r, g, b) guide().customColor = { r = r, g = g, b = b } end,
            { enabled = function() return guide().followAccent == false end,
              tip = "Switch off \"Follow the accent colour\" on the General page to use your own." }),
        { type = "toggle", text = L["Own window colour"], refresh = true,
          tip = L["Off: the window colour comes from the accent tint. Examples: 161618 or 0F172A."],
          get = ownWindow,
          set = function(on)
              guide().background = on and { r = WINDOW[1], g = WINDOW[2], b = WINDOW[3] } or false
              Changed({})
          end },
        ColorRow("Window colour",
            function() return ColorOf(guide().background, WINDOW) end,
            function(r, g, b) guide().background = { r = r, g = g, b = b } end,
            { enabled = ownWindow, tip = "Switch on \"Own window colour\" first." }),

        Header("PROGRESS"),
        { type = "toggle", text = L["Own progress colour"], refresh = true,
          tip = L["Off: progress bars use the accent colour."],
          get = ownProgress,
          set = function(on)
              local r, g, b = ns.Accent()
              guide().progressColor = on and { r = r, g = g, b = b } or false
              Changed({})
          end },
        ColorRow("Progress colour",
            function() return ColorOf(guide().progressColor, ns.FALLBACK_ACCENT) end,
            function(r, g, b) guide().progressColor = { r = r, g = g, b = b } end,
            { enabled = ownProgress, tip = "Switch on \"Own progress colour\" first." }),
    }
end

---------------------------------------------------------------------------
-- Navigation
---------------------------------------------------------------------------

local function PreviewRow()
    return {
        type = "custom", height = ns.ARROW_PREVIEW_HEIGHT or 176,
        build = function(parent)
            local _, preview = ns.BuildArrowHeader(parent, 12)
            return preview
        end,
    }
end

local function ArrowRows()
    local nav = function() return ns.db.nav end
    local spf = function() return ns.SPF.Loaded() end
    local scaleGet, scaleSet = Percent(0.70)
    return {
        PreviewRow(),
        Header("SOURCE"),
        Row("nav", "source", "dropdown", "Navigation source", {
            values = { AUTO = L["Automatic"], SPF = "ShortestPathForever", RXP = "RestedXP" }, order = { "AUTO", "SPF", "RXP" },
            page = true, sync = "source",
            tip = "Where the arrow gets its route from. Without ShortestPathForever the arrow points in a straight line to the step target.",
        }),
        Row("nav", "replaceSpfArrow", "toggle", "Hide the ShortestPathForever arrow", {
            sync = "replaceSpfArrow",
            enabled = function() return spf() and nav().source == "RXP" end,
            tip = "Only available with ShortestPathForever loaded and the source set to RestedXP. With ShortestPathForever guiding, its own arrow is not shown anyway.",
        }),
        Row("nav", "transports", "toggle", "Plan transport", {
            sync = "transports", enabled = spf,
            tip = "ShortestPathForever may use the hearthstone and teleports when planning the route.",
        }),
        Row("nav", "stepEndOnly", "toggle", "Aim at the step end only", {
            sync = "stepEndOnly", enabled = spf,
            tip = "ShortestPathForever marks only the end of each walking stretch instead of every bend.",
        }),
        Row("nav", "nextMarker", "toggle", "Arrow to the next map marker", {
            tip = "The arrow always aims at the map marker that is tracked right now (ShortestPathForever's next bend, as its own arrow does), even for journeys of your own. Distance and time still refer to the target.",
        }),
        Row("nav", "hideRxpArrow", "toggle", "Hide RestedXP's own arrow", {
            rxpArrow = true,
            tip = "Makes RestedXP's arrow invisible, so only one arrow is shown. RestedXP keeps working behind it. Off shows it again and puts your previous RestedXP setting back.",
        }),
        Row("nav", "rememberJourney", "toggle", "Remember your own journey", {
            sync = "rememberJourney", enabled = spf,
            tip = "Switches on ShortestPathForever's \"Keep journeys after a reload\", so the target switch knows your last own journey (a quest, a map click, /way) and can go back to it. Off puts your previous setting back.",
        }),
        Note(NO_SPF, function() return not spf() end),

        Header("ARROW"),
        Row("nav", "style", "dropdown", "Arrow style", {
            values = { CHEVRON = L["Chevron"], RING = L["Ring"], PILL = L["Pill"], CLASSIC = L["Classic"] },
            order = { "CHEVRON", "RING", "PILL", "CLASSIC" },
        }),
        Row("nav", "scale", "slider", "Size (%)", { min = 50, max = 200, step = 5, get = scaleGet, set = scaleSet }),
        Row("nav", "color", "dropdown", "Colour", {
            values = { ACCENT = L["Follow accent colour"], DIRECTION = L["By direction"], CUSTOM = L["Custom"] },
            order = { "ACCENT", "DIRECTION", "CUSTOM" }, page = true,
        }),
        ColorRow("Custom arrow colour",
            function() return ColorOf(nav().customColor, ns.FALLBACK_ACCENT) end,
            function(r, g, b) nav().customColor = { r = r, g = g, b = b } end,
            { enabled = function() return nav().color == "CUSTOM" end, tip = "Set the colour to \"Custom\" first." }),
        Row("nav", "alpha", "slider", "Opacity", { min = 0.2, max = 1, step = 0.05 }),
        Row("nav", "showDistance", "toggle", "Show distance"),
        Row("nav", "showETA", "toggle", "Show arrival time"),
        Row("nav", "showName", "toggle", "Show target name"),
        Row("nav", "unit", "dropdown", "Unit", {
            values = { m = L["Metres"], yd = L["Yards"] }, order = { "m", "yd" }, sync = "unit",
        }),
        Row("nav", "hideCombat", "toggle", "Hide in combat"),

        Header("POSITION"),
        Row("nav", "locked", "toggle", "Lock position", {
            tip = "Off: drag the arrow with the left mouse button; right-click centres it horizontally.",
        }),
        Row("nav", "centerLock", "toggle", "Keep arrow centred", {
            tip = "Keeps the arrow on the vertical centre line of the screen. When unlocked, dragging only moves it up and down.",
        }),
        { type = "button", text = L["Reset arrow position"], onClick = function() ns.ResetArrowPosition() end },
    }
end

local function CompassRows()
    local spf = function() return ns.SPF.Loaded() end
    return {
        Note(NO_SPF, function() return not spf() end),
        Header("COMPASS BAR"),
        SpfRow("compass", "toggle", "Show compass bar"),
        SpfRow("compassScale", "slider", "Compass size (%)", { min = 50, max = 200, step = 10 }),
        SpfRow("compassBackground", "slider", "Compass background (%)", { min = 0, max = 80, step = 10 }),
        SpfRow("compassTime", "toggle", "Show the time left under the compass"),
        Header("LOOK"),
        Row("spfSkin", "compass", "toggle", "Restyle the compass", {
            enabled = spf,
            tip = "Ticks, letters and the centre mark in the skin look: accent colour for north, the centre and the walking marks, the skin font, the window colour behind the band. Off gives ShortestPathForever's own look back.",
        }),
    }
end

local function JourneyRows()
    local spf = function() return ns.SPF.Loaded() end
    local skinned = function() return spf() and ns.db.spfSkin.journey end
    return {
        Note(NO_SPF, function() return not spf() end),
        Header("JOURNEY"),
        SpfRow("journeyTracker", "toggle", "Show journey in tracker", {
            tip = "ShortestPathForever's Journey section in the objective tracker column: where you are going, the time left and each step.",
        }),
        Row("spfSkin", "journey", "toggle", "Restyle the journey", {
            page = true, enabled = spf,
            tip = "The Journey section in the look of the quest tracker: header in the accent colour with a thin line, matching fonts and text colours, a dark panel behind it. Off gives ShortestPathForever's own look back.",
        }),
        Row("spfSkin", "journeyBackground", "slider", "Journey background (%)", {
            min = 0, max = 100, step = 5, enabled = skinned,
            tip = "Opacity of the panel behind the Journey. Its colour is the one of the EllesmereUI quest tracker, otherwise the window colour. 0 shows no panel.",
        }),
        Row("spfSkin", "currentAccent", "toggle", "Current step in the accent colour", {
            enabled = skinned, tip = "Off: the current step is white.",
        }),
    }
end

local function MapRows()
    local spf = function() return ns.SPF.Loaded() end
    return {
        Note(NO_SPF, function() return not spf() end),
        Header("MAP"),
        SpfRow("mapRoutes", "toggle", "Show routes on the map"),
        SpfRow("pins", "toggle", "Show map pins"),
        SpfRow("mapPinScale", "slider", "Pin size (%)", { min = 25, max = 200, step = 5 }),
        SpfRow("transit", "toggle", "Show lifts and tram"),
        SpfRow("portals", "toggle", "Show portals"),
        SpfRow("mapFlightMasters", "toggle", "Show flight masters"),
        SpfRow("flightPinScale", "slider", "Flight master size (%)", { min = 25, max = 200, step = 5 }),
        Header("MINIMAP"),
        SpfRow("minimapPins", "toggle", "Show minimap pins"),
        SpfRow("minimapPinScale", "slider", "Minimap pin size (%)", { min = 25, max = 200, step = 5 }),
    }
end

---------------------------------------------------------------------------
-- Modules (registered with the host in Core.lua)
---------------------------------------------------------------------------

function ns.OptionModules()
    return {
        {
            key = "RXPGuide", title = L["Guide window"],
            desc = L["RestedXP Guides in the skin look: window, steps and colors."],
            pages = {
                { key = "rxp.general", label = L["General"], rows = GeneralRows },
                { key = "rxp.fonts", label = L["Fonts"], rows = FontRows },
                { key = "rxp.colors", label = L["Colors"], rows = ColorRows },
            },
        },
        {
            key = "RXPNav", title = L["Navigation"],
            desc = L["Arrow and route. Route planning comes from ShortestPathForever, the arrow from BeautifulRestedXP."],
            pages = {
                { key = "rxp.arrow", label = L["Arrow"], rows = ArrowRows },
                { key = "rxp.compass", label = L["Compass bar"], rows = CompassRows },
                { key = "rxp.journey", label = L["Journey"], rows = JourneyRows },
                { key = "rxp.map", label = L["Map"], rows = MapRows },
            },
        },
    }
end
