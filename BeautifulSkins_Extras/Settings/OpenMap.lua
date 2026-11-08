-- OpenMap's settings, sorted anew: pages of switches, sliders and choices instead of OpenMap's three tabs of
-- ticks. Drawn by the host in our options window (and EllesmereUI's) and by our map menu (Modules\OpenMapMenu.lua).
-- Values go through OpenMap's own option table (mod:Options(): get, set, range, values, disabled, description), so its
-- side effects run as in its own menu; a setting OpenMap no longer has simply drops out. Labels are ours, the
-- descriptions in the tooltips are OpenMap's (in OpenMap's translation). A setting a new OpenMap version brings and
-- none of our pages shows comes up by itself on the page "New in OpenMap", under OpenMap's own name, until it is sorted
-- in here (tools/openmap_contract.py lists such settings offline; docs/openmap-update.md).
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

-- OpenMap options our rows below do not show through Opt, with the reason: shown by another row of ours, or left out on
-- purpose. Neither they nor the keys Opt builds come up on the page "New in OpenMap". tools/openmap_contract.py reads
-- this table: one entry per line, key = "reason".
OMS.ELSEWHERE = {
    news = "the quick button What's new in the map menu (OpenMap_Binding news)",
    resetSliders = "our button Every slider to its default (Pins and quill), which asks first",
    sketchShown = "our switch Show your drawings (Pins and quill), tied to our quill switch",
}

-- The keys of OpenMap's options our pages show: every Opt call notes its key, also for an option OpenMap lacks or hides
-- here. NewKeys builds every page first, so the list is whole when it is read.
local used = {}

-- AceConfig's hidden: true or a function of info.
local function Hidden(o, info)
    local hidden = o.hidden
    if type(hidden) == "function" then
        local ok, v = pcall(hidden, info)
        return ok and v and true or false
    end
    return hidden == true
end

-- A row from OpenMap's option `key` (nil when OpenMap has no such option or hides it). extra: text, tip (added after
-- OpenMap's description), enabled (combined with OpenMap's own disabled), when (false: not shown here, the key still
-- counts as ours). Types: toggle, range, select, color, execute (a button; asks first when OpenMap's option says so).
local function Opt(opts, key, extra)
    used[key] = true
    extra = extra or {}
    if extra.when == false then return nil end
    local o = opts[key]
    if type(o) ~= "table" then return nil end
    local info = { key, type = o.type, option = o } -- (as AceConfig's info: OpenMap's ns.Bind reads info.type for colours)
    if Hidden(o, info) then return nil end
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
    local readable = type(o.get) == "function" and type(o.set) == "function"
    local function Get() local ok, v = pcall(o.get, info) return ok and v or nil end
    local function Set(...) o.set(info, ...) Notify() end
    if o.type == "toggle" and readable then
        row.type = "toggle"
        row.get = function() return Get() and true or false end
        row.set = function(v) Set(v and true or false) end
    elseif o.type == "range" and readable and type(o.min) == "number" and type(o.max) == "number" then
        local f = o.isPercent and 100 or 1
        row.type = "slider"
        row.min, row.max = o.min * f, o.max * f
        row.step = (o.step or 0.01) * f
        row.get = function() return (tonumber(Get()) or o.min) * f end
        row.set = function(v) Set(Round(v / f)) end
        if extra.zeroText then row.tip = (row.tip and (row.tip .. "\n\n") or "") .. extra.zeroText end
    elseif o.type == "color" and readable then
        row.type = "color"
        row.get = function()
            local ok, r, g, b = pcall(o.get, info)
            if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
            return 1, 1, 1
        end
        row.set = function(r, g, b) Set(r, g, b) end
    elseif o.type == "execute" and type(o.func) == "function" then
        row.type = "button"
        local function Run() o.func(info) Notify() end
        row.onClick = function()
            local confirm = o.confirm
            if type(confirm) == "function" then
                local ok, v = pcall(confirm, info)
                confirm = ok and v or nil
            end
            if not confirm then return Run() end
            local text = type(confirm) == "string" and confirm or Text(o.confirmText, info) or (row.text .. "?")
            ns.host.Confirm("openmap_" .. key, text, Run)
        end
    elseif o.type == "select" and readable then
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

-- A slider for the size of one kind of OpenMap's icons (Modules\OpenMapSizes.lua), in percent of OpenMap's icon size;
-- nil while the sizes do not work (OpenMap changed beyond recognition).
local function SizeRow(key, text, enabled)
    local sizes = ns.OpenMapSizes
    if not (sizes and sizes.Available()) then return nil end
    return { type = "slider", text = text .. " (%)", enabled = enabled,
        min = sizes.MIN, max = sizes.MAX, step = sizes.STEP,
        get = function() return math.floor(sizes.Get(key) * 100 + 0.5) end,
        set = function(v) sizes.Set(key, v / 100) end }
end

-- The section of size sliders (header, what they do, the sliders, a button back to 100 %); nothing without sliders.
local function SizeSection(rows, keys, ...)
    local list = {}
    Add(list, ...)
    if #list == 0 then return end
    rows[#rows + 1] = { type = "header", text = L["SIZE BY KIND"] }
    rows[#rows + 1] = { type = "text", text = L["Each kind's icons at this percentage of OpenMap's icon size (page On the map): 100 % is as big as every other icon. Questie's icons keep the size Questie's options give them."] }
    for _, row in ipairs(list) do rows[#rows + 1] = row end
    rows[#rows + 1] = { type = "button", text = L["All back to 100 %"], refresh = true,
        onClick = function() ns.OpenMapSizes.Reset(keys()) Notify() end }
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
        Opt(opts, "group", { text = L["Party and raid members"] }),
        Opt(opts, "friends", { text = L["Friends and guild"] }),
        Opt(opts, "friendsShare", { text = L["Share where you are"],
            tip = L["OpenMap asks once, as the map opens, whether you want to share. It stays off unless you say yes."] }))
    Section(rows, L["ICONS"],
        Opt(opts, "iconScale", { text = L["Icon size (%)"] }),
        Opt(opts, "iconsFrom", { text = L["Show icons from zoom"], zeroText = L["0 = automatic: each kind from its own zoom."] }),
        Opt(opts, "zoomHidePins", { text = L["Rest icons while zooming"], tip = L["Improves performance."] }))
    local sizes = ns.OpenMapSizes
    SizeSection(rows, function() return sizes.MapKeys() end,
        SizeRow("dungeons", L["Dungeons and raids"]),
        SizeRow("flight", L["Flight masters"]),
        SizeRow("boats", L["Boats"]),
        SizeRow("zeppelins", L["Zeppelins"]),
        SizeRow("quests", L["Quests in your log"]),
        SizeRow("group", L["Party and raid members"]),
        SizeRow("friends", L["Friends and guild"]),
        SizeRow("userpins", L["Map pins"], ns.OpenMap.PinsOn),
        SizeRow("notes", L["Map notes"]),
        SizeRow("waypoint", L["Waypoint"]))
    return rows
end

local function DungeonRows()
    if not Mod() then return NoMod() end
    local opts, rows = Options(), {}
    local mod = Mod()
    local function Has(fn) return type(mod[fn]) == "function" and mod[fn]() and true or false end
    Section(rows, L["ON THE WORLD MAP"],
        Opt(opts, "dungeonLevels", { text = L["Level ranges under the entrances"] }),
        Opt(opts, "entranceClick", { text = L["A click on an entrance opens"], when = Has("HasDungeonJournal") }))
    Section(rows, L["DUNGEON MAPS"],
        Opt(opts, "dungeonBosses", { text = L["Bosses"] }),
        Opt(opts, "dungeonQuests", { text = L["Quests tab"], when = Has("DungeonQuestSource") }),
        Opt(opts, "questSource", { text = L["Quests come from"], when = Has("DungeonQuestSource"),
            enabled = function() return mod.db.dungeonQuests and true or false end }))
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
    local sliders = {}
    for _, kind in ipairs(kinds) do
        if type(kind) == "table" and type(kind.key) == "string" then
            sliders[#sliders + 1] = SizeRow("tf_" .. kind.key, tostring(kind.name or kind.key),
                function() return folk[kind.key] and true or false end)
        end
    end
    SizeSection(rows, function() return ns.OpenMapSizes.TownsfolkKeys() end, unpack(sliders))
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
        Opt(opts, "darkenColor", { text = L["Darkening colour"] }),
        Opt(opts, "darkenColorReset", { text = L["Default darkening colour"] }),
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
    -- (OpenMap's own button since 0.8.0, greyed while Move Any sizes and places the map; before, mod:ResetWindow)
    local reset = Opt(opts, "resetWindow", { text = L["Reset size and place"],
        tip = L["The windowed map's size and place back to Blizzard's."] })
    if not (reset or opts.resetWindow) and type(mod.ResetWindow) == "function" then
        reset = { type = "button", text = L["Reset size and place"],
            tip = L["The windowed map's size and place back to Blizzard's."],
            onClick = function() mod:ResetWindow() Notify() end }
    end
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
        local opts = Options()
        Add(rows,
            Opt(opts, "ctrlClickPin", { text = L["Ctrl-click drops a pin"], enabled = tools.PinsOn,
                tip = L["With \"Map pins\" off, a Ctrl-click on the map does nothing at all, whatever this switch says."] }),
            Opt(opts, "pinsShared", { text = L["Pins others share with you"], enabled = tools.PinsOn }))
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

-- Our pages of OpenMap's settings (the ones that sort them in).
local function SortedPages()
    return {
        { key = "openmap.map", label = L["On the map"], desc = L["Places, quests, your group and the icons."], rows = MapRows },
        { key = "openmap.dungeons", label = L["Dungeons"], desc = L["Entrances on the map and the dungeon maps."], rows = DungeonRows },
        { key = "openmap.townsfolk", label = L["Townsfolk"], desc = L["Vendors, trainers, innkeepers and more in towns."], rows = TownsfolkRows },
        { key = "openmap.look", label = L["Look"], desc = L["Unexplored areas, colours and what the map shows."], rows = LookRows },
        { key = "openmap.detail", label = L["Up close"], desc = L["How far the map zooms and the minimap's detail."], rows = DetailRows },
        { key = "openmap.window", label = L["Window and buttons"], desc = L["Map window, behaviour and the buttons on the map."], rows = WindowRows },
        { key = "openmap.tools", label = L["Pins and quill"], desc = L["Switch OpenMap's tools on or off completely."], rows = ToolRows },
    }
end

-- AceConfig types that are no setting of their own.
local NOT_SETTINGS = { header = true, description = true, group = true }

-- OpenMap's settings that none of our pages shows and ELSEWHERE does not name (visible ones only), in OpenMap's order.
local function NewKeys(opts)
    used = {}
    for _, page in ipairs(SortedPages()) do pcall(page.rows) end
    local keys = {}
    for key, o in pairs(opts) do
        if type(key) == "string" and type(o) == "table" and not used[key] and not OMS.ELSEWHERE[key]
            and not NOT_SETTINGS[o.type] and not Hidden(o, { key, type = o.type, option = o }) then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys, function(a, b)
        local oa, ob = tonumber(opts[a].order) or 1000, tonumber(opts[b].order) or 1000
        if oa ~= ob then return oa < ob end
        return a < b
    end)
    return keys
end

function OMS.NewKeys()
    if not Mod() then return {} end
    return NewKeys(Options())
end

-- OpenMap's new settings under its own names and descriptions, until we sort them in (one we cannot draw: a line that
-- points to OpenMap's own window).
local function NewRows()
    if not Mod() then return NoMod() end
    local opts = Options()
    local keys = NewKeys(opts)
    local rows = {
        { type = "header", text = L["NEW IN OPENMAP"] },
        { type = "text", text = L["Settings of this OpenMap version that BeautifulSkins has not sorted in yet, under OpenMap's own names and descriptions. The gear at the top of the map menu opens OpenMap's own options window with every setting."] },
    }
    for _, key in ipairs(keys) do
        local row = Opt(opts, key)
        if not row then
            local name = Text(opts[key].name, { key }) or key
            row = { type = "text", text = L["%s: only in OpenMap's own options window."]:format(name) }
        end
        rows[#rows + 1] = row
    end
    return rows
end

-- The pages, in sidebar order. key: unique over all packs. "New in OpenMap" only while OpenMap has settings we have not
-- sorted in.
function OMS.Pages()
    local pages = SortedPages()
    if #OMS.NewKeys() > 0 then
        pages[#pages + 1] = { key = "openmap.new", label = L["New in OpenMap"],
            desc = L["OpenMap's settings that are not sorted in yet."], rows = NewRows }
    end
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
