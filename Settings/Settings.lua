-- Options registry and the shared pages. Options are described once as data and drawn by two renderers:
-- Settings.RenderKit (our own options window, Kit form rows) and Settings/EUIPages.lua (a section in the EllesmereUI
-- options window). The host contributes the "General" module; every loaded pack adds its own modules through
-- ns.RegisterPack(..., { modules = fn }).
-- A module is { key, title, desc, pages = { { key, label, rows = function() -> rows } } }; page keys are unique over
-- all modules (packs prefix theirs).
-- Row types (all may carry tip; cond = function() -> bool, evaluated when the page is built; only = "standalone" | "eui"
-- for rows that belong to one host; enabled = function() -> bool dims and locks the row while false):
--   header { text }                               toggle { text, get, set }
--   slider { text, min, max, step, get, set }     dropdown { text, values() -> labels, order, get, set }
--   button { text, onClick }                      color { text, get() -> r, g, b, set(r, g, b) }
--   palette { text, colors, get() -> r, g, b | nil, set(r, g, b) }    text { text or get() -> text }
--   preview { text }  sample sentence in the chosen font
--   themes { text, get, set }  every theme as a card (our own window only; EllesmereUI's keeps a dropdown)
--   custom { height, build(parent) -> frame with :Update() }  a pack's own drawing (arrow preview ...)
-- refresh = true: other rows may show a changed value afterwards (renderers re-read the page).
local _, ns = ...
local L = ns.L
local Theme, Kit = ns.Theme, ns.Kit
local P = ns.PACKAGE

local Settings = {}
ns.Settings = Settings

local function Reload()
    if type(ReloadUI) == "function" then ReloadUI() end
end
Settings.Reload = Reload

---------------------------------------------------------------------------
-- Shared row sets (host module)
---------------------------------------------------------------------------

local function ThemeValues()
    local values, order = {}, {}
    for i, theme in ipairs(Theme.List()) do
        values[theme.key] = theme.label
        order[i] = theme.key
    end
    return values, order
end

local function LanguageValues()
    return { auto = L["Automatic"], enUS = "English", deDE = "Deutsch" }, { "auto", "enUS", "deDE" }
end

-- The palette marks a color only while the accent is an own color.
local function PaletteGet()
    if Theme.AccentMode() ~= "custom" then return nil end
    return Theme.CustomAccent()
end

-- Appearance rows; packs that need the same choices on their own pages can reuse them (Settings.AppearanceRows()).
function Settings.AppearanceRows()
    return {
        { type = "header", text = L["APPEARANCE"] },
        -- our own window shows every theme as a card; EllesmereUI's window keeps its dropdown
        { type = "themes", text = L["Theme"], get = Theme.Current, only = "standalone",
            set = function(key) Theme.Set(key) end, refresh = true,
            tip = L["Look of our own windows and of the skinned windows that follow a theme (Attune)."] },
        { type = "dropdown", text = L["Theme"], values = ThemeValues, get = Theme.Current, only = "eui",
            set = function(key) Theme.Set(key) end, refresh = true,
            tip = L["Look of our own windows and of the skinned windows that follow a theme (Attune)."] },
        { type = "dropdown", text = L["Font"], values = function() return ns.Fonts.Values() end,
            get = function() return ns.Fonts.Current() end,
            set = function(key) Theme.SetFontChoice(key) end,
            tip = ns.HasEUI()
                and L["Font of all our texts. \"EllesmereUI font\" follows the font set in EllesmereUI (only while it is installed and enabled)."]
                or L["Font of all our texts."] },
        { type = "preview", text = L["The quick brown fox jumps over the lazy dog. 0123456789"] },
        { type = "dropdown", text = L["Accent color"], values = Theme.AccentModes, get = Theme.AccentMode,
            set = function(mode) Theme.SetAccentMode(mode) end, refresh = true,
            tip = L["Highlight color of every theme and of every skin: headings, lines, arrows, buttons and switches."] },
        { type = "palette", text = L["Own color"], colors = Theme.PALETTE, get = PaletteGet,
            set = function(r, g, b) Theme.SetCustomAccent(r, g, b) end, refresh = true,
            tip = L["Click a color to use it as the accent."] },
        { type = "color", text = L["Pick any color"], get = Theme.CustomAccent,
            set = function(r, g, b) Theme.SetCustomAccent(r, g, b) end, refresh = true,
            tip = L["Opens the color picker. The chosen color becomes the accent."] },
    }
end

-- The theme editor (one custom row, UI/ThemeEditor.lua).
function Settings.ThemeEditorRows()
    return {
        { type = "header", text = L["OWN THEMES"] },
        { type = "text", text = L["Make your own theme from any theme, change every color and share it as a code. The theme you edit is in use, so every window shows the change at once."] },
        Kit.ThemeEditorRow(),
    }
end

local function PackRows()
    local rows = {}
    if #ns.Packs.order <= 1 then return rows end
    rows[#rows + 1] = { type = "header", text = L["SKIN PACKS"] }
    rows[#rows + 1] = { type = "text", text = L["Each pack skins one addon or a group of addons. A pack whose addon is not installed stays asleep. Changes take effect after a reload."] }
    for _, entry in ipairs(ns.Packs.order) do
        rows[#rows + 1] = { type = "toggle", text = L[entry.title] or entry.key,
            tip = function() return ns.Packs.StatusText(entry) end,
            get = function() return ns.Packs.SwitchedOn(entry.key) end,
            set = function(value)
                ns.db.settings.packs[entry.key] = (not value) and false or nil
                ns.Say(L["Takes effect after /reload."])
            end }
    end
    rows[#rows + 1] = { type = "button", text = L["Reload now"], onClick = Reload }
    return rows
end

local function GeneralRows()
    local s = ns.db.settings
    local rows = {
        { type = "header", text = L["LANGUAGE"] },
        { type = "dropdown", text = L["Language"], values = LanguageValues,
            get = function() return s.language or "auto" end,
            set = function(key)
                s.language = key
                ns.Say(L["The language changes after a reload (/reload)."])
            end,
            tip = ns.HasEUI() and L["Automatic uses the EllesmereUI language when it is installed, else the language of the game."]
                or L["Automatic uses the language of the game."] },
        { type = "header", text = L["INTEGRATION"] },
        { type = "toggle", text = L["Integrate into EllesmereUI"], cond = ns.HasEUI,
            get = function() return s.integrateEUI ~= false end,
            set = function(value)
                s.integrateEUI = value and true or false
                ns.Say(L["The EllesmereUI integration changes after a reload (/reload)."])
            end,
            tip = L["Adds our section to the EllesmereUI options window; the slash command and the minimap button open it there. Off: our own window. Takes effect after a reload."] },
        { type = "text", cond = function() return not ns.HasEUI() end,
            text = L["Without EllesmereUI every option lives in this window. With EllesmereUI installed the same pages can also appear in its options window."] },
        { type = "toggle", text = L["Show the minimap button"],
            get = function() return not s.minimap.hide end,
            set = function(value)
                s.minimap.hide = not value
                if ns.MinimapButton then ns.MinimapButton.Apply() end
            end,
            tip = L["Left-click opens the options, right-click the quick actions. Drag it to move it along the minimap."] },
    }
    for _, row in ipairs(PackRows()) do rows[#rows + 1] = row end
    rows[#rows + 1] = { type = "header", text = L["RESET"] }
    rows[#rows + 1] = { type = "button", text = L["Reset look and language"], onClick = function() ns.AskReset() end,
        tip = L["Theme, font, accent, language and window position back to the defaults, then the interface reloads. The options of the skins stay."] }
    return rows
end

local function InfoRows()
    return {
        { type = "header", text = L["VERSIONS"] },
        { type = "text", get = function() return table.concat(ns.InfoLines(), "\n") end },
        { type = "header", text = L["SKIN PACKS"] },
        { type = "text", get = function() return table.concat(ns.PackLines(), "\n") end },
        { type = "button", text = L["Print the state to the chat"], onClick = function() ns.PrintStatus() end },
        { type = "header", text = L["COMMANDS"] },
        { type = "text", get = function() return table.concat(ns.CommandLines(), "\n") end },
        { type = "button", text = L["Open in EllesmereUI"], only = "standalone",
            cond = function() return ns.hosts.eui ~= nil end,
            onClick = function()
                if ns.OpenOptions(nil, "eui") and ns.Options then ns.Options.Hide() end
            end },
        { type = "text", text = L["Unofficial skins. Not affiliated with the authors of the skinned addons or of EllesmereUI."] },
    }
end

---------------------------------------------------------------------------
-- Registry
---------------------------------------------------------------------------

local function HostModule()
    return { key = "General", title = L["General"], desc = L["Look, language, packs and information."], pages = {
        { key = "appearance", label = L["Appearance"], rows = Settings.AppearanceRows },
        { key = "themeeditor", label = L["Theme editor"], rows = Settings.ThemeEditorRows },
        { key = "general", label = L["General"], rows = GeneralRows },
        { key = "info", label = L["Info"], rows = InfoRows },
    } }
end

-- Every module in sidebar order: General first, then the loaded packs in package order. Built at call time (the
-- locale is final only after ADDON_LOADED).
function Settings.Modules()
    local list = { HostModule() }
    for _, entry in ipairs(ns.Packs.Loaded()) do
        if entry.def.modules then
            local ok, modules = pcall(entry.def.modules)
            if ok and type(modules) == "table" then
                for _, module in ipairs(modules) do list[#list + 1] = module end
            elseif not ok then
                geterrorhandler()(modules)
            end
        end
    end
    return list
end

-- page, module of a page key (nil when unknown).
function Settings.FindPage(key)
    for _, module in ipairs(Settings.Modules()) do
        for _, page in ipairs(module.pages) do
            if page.key == key then return page, module end
        end
    end
    return nil
end

-- The first page of the first module (the page a fresh window opens on).
function Settings.FirstPage()
    local modules = Settings.Modules()
    -- with exactly one pack (a single package) its own first page is the natural start
    local start = modules[2] and #ns.Packs.order == 1 and modules[2] or modules[1]
    return start.pages[1].key
end

local function Allowed(row, host)
    if row.only and row.only ~= host then return false end
    if row.cond and not row.cond() then return false end
    return true
end

-- Rows of a page for a host ("eui" | "standalone"); rows whose cond fails or that belong to the other host are left out.
function Settings.Rows(page, host)
    host = host or "standalone"
    if not (page and page.rows) then return {} end
    local ok, made = pcall(page.rows)
    if not ok then
        geterrorhandler()(made)
        return {}
    end
    local rows = {}
    for _, row in ipairs(made) do
        if Allowed(row, host) then rows[#rows + 1] = row end
    end
    return rows
end

-- Tooltip text of a row (a string or a function).
function Settings.Tip(row)
    local tip = row.tip
    if type(tip) == "function" then
        local ok, text = pcall(tip)
        tip = ok and text or nil
    end
    return tip
end

---------------------------------------------------------------------------
-- Standalone renderer (Kit form rows in a scroll area)
---------------------------------------------------------------------------

local PAD_X, GAP_Y = 6, 2

local function CustomRow(parent, r)
    local row = CreateFrame("Frame", nil, parent)
    row.rowHeight = r.height or 60
    row:SetHeight(row.rowHeight)
    local ok, inner = pcall(r.build, row)
    if not ok then geterrorhandler()(inner) end
    row.inner = ok and inner or nil
    function row:Update()
        if self.inner and self.inner.Update then pcall(self.inner.Update, self.inner) end
    end
    return row
end

-- Dims and locks a row while its enabled() is false.
local function Gate(row, enabled)
    local on = enabled() and true or false
    row:SetAlpha(on and 1 or 0.35)
    if row.control then
        if row.control.EnableMouse then row.control:EnableMouse(on) end
        for _, child in ipairs({ row.control:GetChildren() }) do
            if child.EnableMouse then child:EnableMouse(on) end
        end
    end
end

-- Builds rows into a scroll area filling parent; returns the area with :Refresh() (re-read every value).
function Settings.RenderKit(parent, rows)
    local area = Kit.ScrollArea(parent)
    area:SetAllPoints()
    area.rows = {}
    local child = area.child

    local function Wrap(fn, r)
        if not fn then return nil end
        return function(...)
            if r.enabled and not r.enabled() then return end
            fn(...)
            area:Refresh()
        end
    end

    for _, r in ipairs(rows) do
        local row
        local tip = Settings.Tip(r)
        if r.type == "header" then
            row = Kit.SectionHeader(child, r.text)
        elseif r.type == "toggle" then
            row = Kit.ToggleRow(child, r.text, r.get, Wrap(r.set, r), tip)
        elseif r.type == "slider" then
            -- sliders call set while dragging: no page refresh per step
            local set = r.set
            row = Kit.SliderRow(child, r.text, r.min, r.max, r.step, r.get, function(...)
                if r.enabled and not r.enabled() then return end
                set(...)
            end, tip)
        elseif r.type == "dropdown" then
            row = Kit.DropdownRow(child, r.text, r.values, r.get, Wrap(r.set, r), tip)
        elseif r.type == "button" then
            row = Kit.ButtonRow(child, r.text, function()
                if r.enabled and not r.enabled() then return end
                r.onClick()
                area:Refresh()
            end, tip)
        elseif r.type == "color" then
            row = Kit.ColorRow(child, r.text, r.get, Wrap(r.set, r), tip)
        elseif r.type == "palette" then
            row = Kit.PaletteRow(child, r.text, r.colors, r.get, Wrap(r.set, r), tip)
        elseif r.type == "text" then
            row = Kit.TextRow(child, r.text, r.get)
        elseif r.type == "preview" then
            row = Kit.PreviewRow(child, r.text)
        elseif r.type == "themes" then
            row = Kit.ThemeGalleryRow(child, r.text, r.get, Wrap(r.set, r), tip)
        elseif r.type == "custom" and r.build then
            row = CustomRow(child, r)
        end
        if row then
            row.def = r
            area.rows[#area.rows + 1] = row
        end
    end

    function area:Layout()
        local y = 0
        for _, row in ipairs(self.rows) do
            if row.Measure then row:Measure() end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", child, "TOPLEFT", PAD_X, -y)
            row:SetPoint("TOPRIGHT", child, "TOPRIGHT", -PAD_X, -y)
            y = y + (row.rowHeight or 44) + GAP_Y
        end
        self:SetContentHeight(y + 12)
    end

    function area:Refresh()
        for _, row in ipairs(self.rows) do
            row:Update()
            if row.def and row.def.enabled then Gate(row, row.def.enabled) end
        end
        self:Layout() -- dynamic texts change their height
    end

    -- wrapped text changes its height with the width
    child:HookScript("OnSizeChanged", function() area:Layout() end)
    area:Layout()
    area:Refresh()
    return area
end

-- Sidebar badge text of a module (pack version), nil for none.
function Settings.Title()
    return P.title
end
