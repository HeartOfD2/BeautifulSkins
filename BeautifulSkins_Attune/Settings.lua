-- Options of the Attune skin as row data; the host draws them in its own window and in the EllesmereUI section (row
-- types: the host's Settings\Settings.lua). Theme, font, accent and language are the host's (General > Appearance).
local _, ns = ...
local L = ns.L

local function Reload()
    if type(ReloadUI) == "function" then ReloadUI() end
end

local function LookRows()
    local s = ns.db.settings
    local Theme = ns.Theme
    return {
        { type = "header", text = L["STATUS"] },
        { type = "dropdown", text = L["Status colors"], values = Theme.StatusSchemes, get = Theme.StatusScheme,
            set = function(key) Theme.SetStatusScheme(key) end,
            tip = L["Colors of done, ready and locked steps. \"Attune classic\" keeps Attune's own tones."] },
        { type = "text", text = L["Theme, font and accent color are set under General > Appearance and apply to Attune's window as well."] },

        { type = "header", text = L["WINDOW"] },
        { type = "slider", text = L["Window scale"], min = 70, max = 130, step = 5,
            get = function() return math.floor(ns.Skin.WindowScale() * 100 + 0.5) end,
            set = function(value) ns.Skin.SetWindowScale(value / 100) end,
            tip = L["Scales Attune's whole window between 70 % and 130 %."] },
        { type = "toggle", text = L["Hide the icon view"],
            get = function() return s.hideIconView ~= false end,
            set = function(value)
                s.hideIconView = value and true or false
                ns.Skin.ApplyIconView()
            end,
            tip = L["Always shows Attune's list and hides its switch between list and icons."] },

        { type = "header", text = L["CHAIN"] },
        { type = "dropdown", text = L["Line weight"],
            values = function()
                return { fine = L["Fine"], normal = L["Normal"], strong = L["Strong"] }, { "fine", "normal", "strong" }
            end,
            get = function() return s.lineWeight or "normal" end,
            set = function(key)
                s.lineWeight = key
                ns.Skin.GraphApplySettings()
            end,
            tip = L["Thickness of the connectors between the steps (2, 3 or 4 pixels at 100 %)."] },
        { type = "dropdown", text = L["Dungeon picture"],
            values = function()
                return { banner = L["Banner"], background = L["Background"], off = L["Off"] }, { "banner", "background", "off" }
            end,
            get = function() return s.dungeonArt or "banner" end,
            set = function(key)
                s.dungeonArt = key
                ns.Skin.GraphApplySettings()
            end,
            tip = L["Banner above the chain, a faint background as in Attune, or no picture."] },
        { type = "button", text = L["Open or close Attune"], onClick = function() ns.ToggleAttune() end },
    }
end

local function SearchZoomRows()
    local s = ns.db.settings
    local function Search() return s.search end
    local function Apply() ns.Skin.SearchApplySettings() end
    return {
        { type = "header", text = L["SEARCH"] },
        { type = "toggle", text = L["Mark matches in the chain"],
            get = function() return Search().mark ~= false end,
            set = function(value)
                Search().mark = value and true or false
                Apply()
            end,
            tip = L["While you search, matching cards of the open chain get an accent frame and the others are dimmed."] },
        { type = "toggle", text = L["Only open steps"],
            get = function() return Search().onlyOpen and true or false end,
            set = function(value)
                Search().onlyOpen = value and true or false
                Apply()
            end,
            tip = L["Hides what is already done from the results. Same as the switch in the result list."] },
        { type = "dropdown", text = L["Filter"], values = function() return ns.Skin.SearchFilters() end,
            get = function() return Search().filter or "all" end,
            set = function(key)
                Search().filter = key
                Apply()
            end,
            tip = L["Which kind of entries the search shows. Same as the chips in the result list."] },
        { type = "text", text = L["Click into the search field above the list, or type and use the arrow keys, Enter and Esc."] },

        { type = "header", text = L["ZOOM"] },
        { type = "toggle", text = L["Zoom above 100 %"],
            get = function() return s.zoomAbove100 ~= false end,
            set = function(value)
                s.zoomAbove100 = value and true or false
                ns.Skin.ZoomApplySettings()
            end,
            tip = L["Lets the zoom bar go up to 150 %. Attune itself stops at 100 %."] },
        { type = "text", text = L["The zoom bar sits at the top right of the chain: minus, percent, plus and \"fit the whole chain\". Ctrl + mouse wheel over the chain zooms as well (10 % steps, 5 % below 50 %)."] },
    }
end

-- Module switches in the order of the window from top to bottom.
local function ModuleList()
    return {
        { key = "window", text = L["Window"],
            tip = L["Flat frame, header with the view switch, status bar and survey menu. The search needs it."] },
        { key = "tree", text = L["List"], tip = L["Rows of Attune's list: sections, icons, levels and progress."] },
        { key = "graph", text = L["Chain"], tip = L["Cards, connectors, the head card and the dungeon picture."] },
        { key = "zoom", text = L["Zoom bar"],
            tip = L["Zoom bar, fit button and Ctrl + mouse wheel; zoom from 10 % to 150 %."] },
        { key = "search", text = L["Search"],
            tip = L["Search field above the list with filters, result list and jump to the card."] },
        { key = "detail", text = L["Quest details"], tip = L["Quest detail panel, map, rewards and the quest giver hint."] },
        { key = "results", text = L["Results"], tip = L["The results table, its choices and the level slider."] },
        { key = "nextWindow", text = L["Next window"],
            tip = L["Attune's small window with the next step of every attunement."] },
    }
end

local function PartRows()
    local s = ns.db.settings
    local rows = {
        { type = "header", text = L["SKIN MODULES"] },
        { type = "text", text = L["Each part of the skin can be switched off. Changes take effect after a reload; Attune itself keeps working either way."] },
    }
    for _, m in ipairs(ModuleList()) do
        rows[#rows + 1] = { type = "toggle", text = m.text, tip = m.tip,
            get = function() return s.modules[m.key] ~= false end,
            set = function(value) s.modules[m.key] = value and true or false end }
    end
    rows[#rows + 1] = { type = "button", text = L["Reload now"], onClick = Reload }

    rows[#rows + 1] = { type = "header", text = L["STATE"] }
    rows[#rows + 1] = { type = "text", get = function() return table.concat(ns.ModuleLines(), "\n") end }
    rows[#rows + 1] = { type = "toggle", text = L["Version notice"],
        get = function() return s.versionNotice ~= false end,
        set = function(value) s.versionNotice = value and true or false end,
        tip = L["One chat line per session when the installed Attune version has not been tested with this skin."] }
    rows[#rows + 1] = { type = "button", text = L["Print the diagnostics to the chat"], onClick = function() ns.Diag() end,
        tip = L["Same as /battune diag."] }

    rows[#rows + 1] = { type = "header", text = L["RESET"] }
    rows[#rows + 1] = { type = "button", text = L["Reset the Attune skin"], onClick = function() ns.AskReset() end,
        tip = L["Every option on these pages back to its default, then the interface reloads. Asks first."] }
    return rows
end

function ns.OptionModules()
    return {
        {
            key = "Attune", title = L["Attune"],
            desc = L["Attune's window in a modern, flat look with search and zoom."],
            pages = {
                { key = "attune.look", label = L["Look"], rows = LookRows },
                { key = "attune.search", label = L["Search & zoom"], rows = SearchZoomRows },
                { key = "attune.parts", label = L["Parts"], rows = PartRows },
            },
        },
    }
end
