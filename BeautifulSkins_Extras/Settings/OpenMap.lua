-- OpenMap's settings, sorted anew: eight pages of switches, sliders and choices instead of OpenMap's three tabs of
-- ticks. Drawn by the host in our options window (and EllesmereUI's) and by our map menu (Modules\OpenMapMenu.lua).
-- Values go through OpenMap's own option table (mod:Options(): get, set, range, values, disabled, description), so its
-- side effects run as in its own menu; a setting OpenMap no longer has simply drops out. Labels are ours, the
-- descriptions in the tooltips are OpenMap's (in OpenMap's translation).
local _, ns = ...
local L = ns.L

local OMS = {}
ns.OpenMapSettings = OMS

local function Mod()
    return ns.OpenMap and ns.OpenMap.Mod() or nil
end

local function Notify()
    if ns.OpenMap then ns.OpenMap.Notify() end
end

-- OpenMap's option table (fresh: its closures read the live database).
local function Options()
    local mod = Mod()
    if not (mod and type(mod.Options) == "function") then return {} end
    local ok, opts = pcall(mod.Options, mod)
    return ok and type(opts) == "table" and opts or {}
end

local function Text(value, info)
    if type(value) == "function" then
        local ok, text = pcall(value, info)
        value = ok and text or nil
    end
    return type(value) == "string" and value or nil
end

local function Round(v)
    return math.floor(v * 1000 + 0.5) / 1000
end

-- A row from OpenMap's option `key` (nil when OpenMap has no such option). extra: text, tip (added after OpenMap's
-- description), enabled (combined with OpenMap's own disabled).
local function Opt(opts, key, extra)
    local o = opts[key]
    if type(o) ~= "table" or o.hidden == true or type(o.get) ~= "function" then return nil end
    extra = extra or {}
    local info = { key }
    local tip = Text(o.desc, info)
    if extra.tip then tip = tip and (tip .. "\n\n" .. extra.tip) or extra.tip end
    local row = { text = extra.text or Text(o.name, info) or key, tip = tip, refresh = true }
    local disabled, own = o.disabled, extra.enabled
    row.enabled = function()
        if type(disabled) == "function" then
            local ok, off = pcall(disabled, info)
            if ok and off then return false end
        elseif disabled == true then
            return false
        end
        return own == nil or own()
    end
    local function Get() local ok, v = pcall(o.get, info) return ok and v or nil end
    local function Set(...) o.set(info, ...) Notify() end
    if o.type == "toggle" and type(o.set) == "function" then
        row.type = "toggle"
        row.get = function() return Get() and true or false end
        row.set = function(v) Set(v and true or false) end
    elseif o.type == "range" and type(o.set) == "function" then
        local f = o.isPercent and 100 or 1
        row.type = "slider"
        row.min, row.max = o.min * f, o.max * f
        row.step = (o.step or 0.01) * f
        row.get = function() return (tonumber(Get()) or o.min) * f end
        row.set = function(v) Set(Round(v / f)) end
        if extra.zeroText then row.tip = (row.tip and (row.tip .. "\n\n") or "") .. extra.zeroText end
    elseif o.type == "select" and type(o.set) == "function" then
        row.type = "dropdown"
        row.values = function()
            local values = o.values
            if type(values) == "function" then
                local ok, v = pcall(values, info)
                values = ok and v or {}
            end
            values = type(values) == "table" and values or {}
            local order = type(o.sorting) == "table" and o.sorting or nil
            if not order then
                order = {}
                for k in pairs(values) do order[#order + 1] = k end
                table.sort(order, function(a, b) return tostring(values[a]) < tostring(values[b]) end)
            end
            return values, order
        end
        row.get = Get
        row.set = function(v) Set(v) end
    else
        return nil
    end
    return row
end

-- Appends rows, leaving out the nils of options OpenMap does not have.
local function Add(rows, ...)
    for i = 1, select("#", ...) do
        local row = select(i, ...)
        if row then rows[#rows + 1] = row end
    end
end

-- A header followed by its rows; nothing at all when none of the rows exists.
local function Section(rows, title, ...)
    local list = {}
    Add(list, ...)
    if #list == 0 then return end
    rows[#rows + 1] = { type = "header", text = title }
    for _, row in ipairs(list) do rows[#rows + 1] = row end
end

-- A switch for mod.db[key] (settings OpenMap keeps outside its option table).
local function DbToggle(key, text, tip, after)
    local mod = Mod()
    if not (mod and mod.db[key] ~= nil) then return nil end
    return { type = "toggle", text = text, tip = tip, refresh = true,
        get = function() return mod.db[key] and true or false end,
        set = function(v)
            mod.db[key] = v and true or false
            if after then after(v) elseif type(mod.Refresh) == "function" then mod:Refresh() end
            Notify()
        end }
end

local function NoMod()
    return { { type = "text", text = L["OpenMap is not loaded."] } }
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------

local function QuestieRow()
    if not ns.IsLoaded("Questie") then return nil end
    local function Profile()
        local q = rawget(_G, "Questie")
        return type(q) == "table" and type(q.db) == "table" and q.db.profile or nil
    end
    return { type = "toggle", text = L["Questie icons"], refresh = true,
        tip = L["Questie's quest givers and objectives on the map (Questie's own \"Enable Map Icons\")."],
        get = function() local p = Profile() return p and p.enableMapIcons and true or false end,
        set = function(v)
            local p = Profile()
            local loader = rawget(_G, "QuestieLoader")
            local quests = type(loader) == "table" and type(loader.ImportModule) == "function" and loader:ImportModule("QuestieQuest")
            if not (p and type(quests) == "table" and type(quests.ToggleNotes) == "function") then return end
            p.enableMapIcons = v and true or false
            quests:ToggleNotes(v and true or false)
            Notify()
        end }
end

local function MapRows()
    if not Mod() then return NoMod() end
    local opts, rows = Options(), {}
    local mod = Mod()
    local function Transport() return mod.db.boats or mod.db.zeppelins end
    Section(rows, L["PLACES"],
        Opt(opts, "icons", { text = L["Dungeons and raids"] }),
        Opt(opts, "flight", { text = L["Flight masters"] }),
        Opt(opts, "boats", { text = L["Boats"] }),
        Opt(opts, "zeppelins", { text = L["Zeppelins"] }),
        Opt(opts, "routes", { text = L["Boat and zeppelin routes"], enabled = Transport,
            tip = L["Needs boats or zeppelins."] }),
        Opt(opts, "foundOnly", { text = L["Only places you have found"] }))
    Section(rows, L["QUESTS"],
        Opt(opts, "allQuests", { text = L["Quests from every zone"] }),
        QuestieRow())
    Section(rows, L["YOU AND YOUR GROUP"],
        Opt(opts, "playerArrow", { text = L["Your arrow"] }),
        Opt(opts, "group", { text = L["Party and raid members"] }))
    Section(rows, L["ICONS"],
        Opt(opts, "iconScale", { text = L["Icon size (%)"] }),
        Opt(opts, "iconsFrom", { text = L["Show icons from zoom"], zeroText = L["0 = automatic: each kind from its own zoom."] }),
        Opt(opts, "zoomHidePins", { text = L["Rest icons while zooming"], tip = L["Improves performance."] }))
    return rows
end

local function DungeonRows()
    if not Mod() then return NoMod() end
    local opts, rows = Options(), {}
    local mod = Mod()
    local function Has(fn) return type(mod[fn]) == "function" and mod[fn]() and true or false end
    Section(rows, L["ON THE WORLD MAP"],
        Opt(opts, "dungeonLevels", { text = L["Level ranges under the entrances"] }),
        Has("HasDungeonJournal") and Opt(opts, "entranceClick", { text = L["A click on an entrance opens"] }) or nil)
    Section(rows, L["DUNGEON MAPS"],
        Opt(opts, "dungeonBosses", { text = L["Bosses"] }),
        Has("DungeonQuestSource") and Opt(opts, "dungeonQuests", { text = L["Quests tab"] }) or nil,
        Has("DungeonQuestSource") and Opt(opts, "questSource", { text = L["Quests come from"],
            enabled = function() return mod.db.dungeonQuests and true or false end }) or nil)
    return rows
end

local function TownsfolkRows()
    local mod = Mod()
    if not mod then return NoMod() end
    local kinds = ns.T(mod.TOWNSFOLK) or {}
    local folk = ns.T(mod.db.townsfolk)
    local has = type(mod.HasTownsfolk) == "function" and mod.HasTownsfolk()
    local rows = { { type = "header", text = L["TOWNSFOLK"] } }
    if not (has and folk and #kinds > 0) then
        rows[#rows + 1] = { type = "text", text = L["Townsfolk come from Questie's database. Install Questie (or an addon that offers such a database) to see vendors, trainers and the like on the map."] }
        return rows
    end
    rows[#rows + 1] = { type = "text", text = L["Shown in towns once you zoom in far enough. Rare mobs show out in the wild."] }
    local function Refresh()
        if type(mod.RefreshTownsfolk) == "function" then mod:RefreshTownsfolk() end
        Notify()
    end
    local function Row(kind)
        if type(kind) ~= "table" or type(kind.key) ~= "string" then return nil end
        return { type = "toggle", text = tostring(kind.name or kind.key),
            get = function() return folk[kind.key] and true or false end,
            set = function(v) folk[kind.key] = v and true or false Refresh() end }
    end
    local last = {}
    for _, kind in ipairs(kinds) do
        if type(kind) == "table" and (kind.rare or kind.key == "spirit") then last[#last + 1] = kind
        else Add(rows, Row(kind)) end
    end
    rows[#rows + 1] = { type = "header", text = L["MORE"] }
    for _, kind in ipairs(last) do Add(rows, Row(kind)) end
    local function All(on)
        for _, kind in ipairs(kinds) do
            if type(kind) == "table" and type(kind.key) == "string" then folk[kind.key] = on end
        end
        Refresh()
    end
    rows[#rows + 1] = { type = "button", text = L["Show all"], onClick = function() All(true) end }
    rows[#rows + 1] = { type = "button", text = L["Hide all"], onClick = function() All(false) end }
    return rows
end

local function LookRows()
    local mod = Mod()
    if not mod then return NoMod() end
    local opts, rows = Options(), {}
    local own = type(mod.SetUnexploredOwn) == "function" and {
        type = "toggle", text = L["Own choice for this character"], refresh = true,
        tip = L["This character keeps its own choice for unexplored areas; the others keep the shared one."],
        get = function() return ns.T(mod.char) and mod.char.unexploredOwn and true or false end,
        set = function(v) mod.SetUnexploredOwn(v and true or false) Notify() end } or nil
    Section(rows, L["UNEXPLORED AREAS"],
        Opt(opts, "unexplored", { text = L["Unexplored areas"] }),
        Opt(opts, "darkening", { text = L["Darkening (%)"] }),
        own)
    Section(rows, L["COLOURS"],
        Opt(opts, "colorMatch", { text = L["Colour matching between zones (%)"] }),
        Opt(opts, "desaturate", { text = L["Take colour out (%)"] }))
    Section(rows, L["THE MAP"],
        Opt(opts, "chart", { text = L["Ocean and border when zoomed out"] }),
        Opt(opts, "gapFills", { text = L["Paint the gaps between zones"] }),
        Opt(opts, "hoverHighlight", { text = L["Highlight the zone under the cursor"] }),
        Opt(opts, "zoneLevels", { text = L["Zone levels"] }),
        Opt(opts, "coords", { text = L["Coordinates"] }))
    return rows
end

local function DetailRows()
    if not Mod() then return NoMod() end
    local opts, rows = Options(), {}
    local mod = Mod()
    local function Minimap() return mod.db.minimap and true or false end
    Section(rows, L["ZOOM"],
        Opt(opts, "maxZoom", { text = L["Deepest zoom"] }))
    Section(rows, L["MINIMAP DETAIL"],
        Opt(opts, "minimap", { text = L["Minimap detail up close"] }),
        Opt(opts, "minimapMix", { text = L["Strength (%)"], enabled = Minimap }),
        Opt(opts, "minimapFrom", { text = L["From zoom"], enabled = Minimap }),
        Opt(opts, "minimapDeep", { text = L["Most opacity (%)"], enabled = Minimap }),
        Opt(opts, "cityMinimap", { text = L["In major cities"], enabled = Minimap }),
        Opt(opts, "gapMinimap", { text = L["In the gaps (experimental)"], enabled = Minimap }))
    Section(rows, L["MAP ART"],
        Opt(opts, "soften", { text = L["Soften and add paper grain"] }),
        Opt(opts, "underground", { text = L["Caves and dungeon entrances"] }))
    return rows
end

-- Actions OpenMap can put on the map as buttons of their own (its favourites). Pins and quill only while they're on.
local function Quick()
    return {
        { "find", L["Find me"] }, { "questlog", L["Quest log"] }, { "pin", L["Drop a pin"], "pins" },
        { "pins", L["Map pins"], "pins" }, { "quill", L["Quill"], "quill" }, { "report", L["Report a problem"] },
        { "news", L["What's new"] },
    }
end

local function IsFavorite(mod, id)
    for _, f in ipairs(ns.T(mod.db.favorites) or {}) do
        if f == id then return true end
    end
    return false
end

local function SetFavorite(mod, id, on)
    local favs = ns.T(mod.db.favorites)
    if not favs then return end
    for i = #favs, 1, -1 do
        if favs[i] == id then table.remove(favs, i) end
    end
    if on then favs[#favs + 1] = id end
end

local function QuickRows(mod)
    local rows = {}
    local tools = ns.OpenMap
    for _, q in ipairs(Quick()) do
        local id, needs = q[1], q[3]
        local function Available()
            if needs == "pins" then return tools.PinsOn() end
            if needs == "quill" then return tools.QuillOn() end
            return true
        end
        rows[#rows + 1] = { type = "toggle", text = q[2], refresh = true,
            enabled = function() return mod.db.mapButtons ~= false and Available() end,
            get = function() return IsFavorite(mod, id) end,
            set = function(v) SetFavorite(mod, id, v) Notify() end }
    end
    return rows
end

local function WindowRows()
    local mod = Mod()
    if not mod then return NoMod() end
    local opts, rows = Options(), {}
    local s = ns.host.db and ns.host.db.settings
    if s then
        Section(rows, L["LANGUAGE"],
            { type = "dropdown", text = L["Language"],
                values = function()
                    return { auto = L["Automatic"], enUS = "English", deDE = "Deutsch" }, { "auto", "enUS", "deDE" }
                end,
                get = function() return s.language or "auto" end,
                set = function(key)
                    s.language = key
                    ns.Say(L["The language changes after a reload (/reload)."])
                end,
                tip = L["Language of BeautifulSkins and of this window. OpenMap's own descriptions in the tooltips, townsfolk and place names follow the game's language."] },
            { type = "button", text = L["Reload now"], onClick = function() if type(ReloadUI) == "function" then ReloadUI() end end })
    end
    local reset = type(mod.ResetWindow) == "function" and { type = "button", text = L["Reset size and place"],
        tip = L["The windowed map's size and place back to Blizzard's."],
        onClick = function() mod:ResetWindow() Notify() end } or nil
    Section(rows, L["MAP WINDOW"],
        Opt(opts, "windowScale", { text = L["Map size (%)"] }),
        Opt(opts, "fullWidth", { text = L["Full-screen map fills the width"] }),
        Opt(opts, "chatOverMap", { text = L["Chat over the full-screen map"] }),
        reset)
    Section(rows, L["BEHAVIOUR"],
        Opt(opts, "reopenView", { text = L["When the map opens again"] }),
        Opt(opts, "autoSwitch", { text = L["Load the zone in view"] }),
        Opt(opts, "moveFade", { text = L["Fade while moving (%)"] }),
        Opt(opts, "mapFpsCap", { text = L["Map frame rate cap"], zeroText = L["0 = no cap."] }))
    Section(rows, L["BUTTONS"],
        Opt(opts, "mapButtons", { text = L["OpenMap button on the map"] }),
        DbToggle("tabRail", L["Buttons as tabs on the map's edge"],
            L["The OpenMap button and your quick buttons as tabs at the edge of the map. Off: a row in its bottom left corner. Drag the OpenMap tab along the edge to move them."]),
        Opt(opts, "minimapButton", { text = L["Minimap button"] }))
    if ns.T(mod.db.favorites) then
        rows[#rows + 1] = { type = "header", text = L["QUICK BUTTONS ON THE MAP"] }
        rows[#rows + 1] = { type = "text", text = L["Each action switched on here gets a button of its own next to the OpenMap button."] }
        for _, row in ipairs(QuickRows(mod)) do rows[#rows + 1] = row end
    end
    return rows
end

local function ToolRows()
    local mod = Mod()
    local tools = ns.OpenMap
    local rows = {
        { type = "header", text = L["MAP PINS"] },
        { type = "toggle", text = L["Map pins"], refresh = true,
            tip = L["Off: no \"Drop a pin\", no pin list, no pins on the map, and a Ctrl-click on the map does nothing. On again brings your pins back."],
            get = tools.PinsOn, set = tools.SetPins },
    }
    if mod then
        Add(rows, Opt(Options(), "pinsShared", { text = L["Pins others share with you"], enabled = tools.PinsOn }))
    end
    rows[#rows + 1] = { type = "header", text = L["QUILL"] }
    rows[#rows + 1] = { type = "toggle", text = L["Quill"], refresh = true,
        tip = L["Off: no drawing on the map, on pins or on dungeon maps, and your drawings stay hidden. Drawing for \"Report a problem\" still works. On again brings your drawings back."],
        get = tools.QuillOn, set = tools.SetQuill }
    if mod and mod.db.sketchShown ~= nil then
        rows[#rows + 1] = { type = "toggle", text = L["Show your drawings"], refresh = true, enabled = tools.QuillOn,
            get = function() return mod.db.sketchShown ~= false end,
            set = function(v)
                mod.db.sketchShown = v and true or false
                if type(mod.RefreshSketch) == "function" then mod.RefreshSketch() end
                Notify()
            end }
    end
    if not mod then return rows end
    local more = {}
    if type(mod.TogglePaint) == "function" and type(mod.IsPainting) == "function" then
        more[#more + 1] = { type = "toggle", text = L["Map notes"], refresh = true,
            tip = L["Paint areas on the map and say what is there (/openmap notes)."],
            get = function() return mod:IsPainting() and true or false end,
            set = function(v) mod:TogglePaint(v and true or false) Notify() end }
    end
    if type(mod.ToggleDebugOverlay) == "function" and type(mod.IsDebugOverlay) == "function" then
        more[#more + 1] = { type = "toggle", text = L["Debug overlay (frame rate)"], refresh = true,
            get = function() return mod:IsDebugOverlay() and true or false end,
            set = function(v) mod:ToggleDebugOverlay(v and true or false) Notify() end }
    end
    Section(rows, L["MORE TOOLS"], unpack(more))
    if type(mod.ResetSliders) == "function" then
        rows[#rows + 1] = { type = "header", text = L["RESET"] }
        rows[#rows + 1] = { type = "button", text = L["Every slider to its default"],
            tip = L["Every OpenMap slider back to how OpenMap comes: zoom, icons, colours, minimap detail, map size."],
            onClick = function()
                ns.host.Confirm("openmapSliders", L["Put every OpenMap slider back to its default?"], function()
                    mod:ResetSliders()
                    Notify()
                end)
            end }
    end
    return rows
end

-- Switches other addons add to OpenMap's menu (OpenMapAPI.RegisterMenuToggle), each under its heading.
local function AddonRows()
    local mod = Mod()
    if not (mod and type(mod.ExtraMenuRows) == "function") then return {} end
    local function MakeRow(label, _, _, get, set)
        return { type = "toggle", text = tostring(label), get = get, set = function(v) set(v and true or false) Notify() end }
    end
    local ok, list = pcall(mod.ExtraMenuRows, MakeRow)
    local rows = {}
    for _, entry in ipairs(ok and type(list) == "table" and list or {}) do
        if type(entry) == "table" and entry.type then
            rows[#rows + 1] = entry
        elseif type(entry) == "table" and type(entry[1]) == "string" then
            rows[#rows + 1] = { type = "header", text = entry[1]:upper() }
        end
    end
    return rows
end

function OMS.HasAddonRows()
    return #AddonRows() > 0
end

-- The pages, in sidebar order. key: unique over all packs; icon: for the map menu's sidebar.
function OMS.Pages()
    local pages = {
        { key = "openmap.map", label = L["On the map"], desc = L["Places, quests, your group and the icons."], rows = MapRows },
        { key = "openmap.dungeons", label = L["Dungeons"], desc = L["Entrances on the map and the dungeon maps."], rows = DungeonRows },
        { key = "openmap.townsfolk", label = L["Townsfolk"], desc = L["Vendors, trainers, innkeepers and more in towns."], rows = TownsfolkRows },
        { key = "openmap.look", label = L["Look"], desc = L["Unexplored areas, colours and what the map shows."], rows = LookRows },
        { key = "openmap.detail", label = L["Up close"], desc = L["How far the map zooms and the minimap's detail."], rows = DetailRows },
        { key = "openmap.window", label = L["Window and buttons"], desc = L["Map window, behaviour and the buttons on the map."], rows = WindowRows },
        { key = "openmap.tools", label = L["Pins and quill"], desc = L["Switch OpenMap's tools on or off completely."], rows = ToolRows },
    }
    if OMS.HasAddonRows() then
        pages[#pages + 1] = { key = "openmap.addons", label = L["Other addons"], desc = L["Switches other addons add to OpenMap."], rows = AddonRows }
    end
    return pages
end

-- The module for the options windows (only while OpenMap is loaded).
function OMS.Module()
    if not ns.IsLoaded("OpenMap") then return nil end
    return { key = "OpenMap", title = "OpenMap", desc = L["OpenMap's settings, sorted anew."], pages = OMS.Pages() }
end
