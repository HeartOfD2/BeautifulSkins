-- Optional EllesmereUI integration: one sidebar section (PACKAGE.pluginLabel) with the same pages as our own options window
-- (Settings/OptionsWindow.lua). Runs only when EllesmereUI is loaded and settings.integrateEUI is on; RegisterPlugin
-- works only at load, so switching the setting takes effect after /reload. This is the only file that touches
-- EllesmereUI.Widgets; the pages are drawn here from the row descriptions in Settings/Settings.lua.
local _, ns = ...
local L = ns.L
local Settings = ns.Settings

local PLUGIN_ID = ns.name

local function IsPrebuild()
    local E = EllesmereUI
    return type(E) == "table" and type(E.IsSearchPrebuild) == "function" and E.IsSearchPrebuild() or false
end

local function Pad()
    return EllesmereUI.CONTENT_PAD or 45
end

-- Frame for Kit parts inside an EUI page; fnCtx = "eui" paints them with EllesmereUI's panel colours.
local function Host(parent, y, height)
    local host = CreateFrame("Frame", nil, parent)
    host.fnCtx = "eui"
    host:SetPoint("TOPLEFT", parent, "TOPLEFT", Pad(), y)
    host:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -Pad(), y)
    host:SetHeight(height)
    return host
end

local byName = {}    -- localized page name (what EUI hands back) -> page
local liveTexts = {} -- computed texts on built pages: { fs, get }; EUI caches pages, so they are re-read on restore

---------------------------------------------------------------------------
-- Renderer: row descriptions -> EllesmereUI.Widgets (searchable by EUI)
---------------------------------------------------------------------------

-- Re-read the values of EUI's widgets on the page (after a row changed others, e.g. accent mode).
local function RefreshEUIPage()
    local E = EllesmereUI
    if type(E.RefreshPage) == "function" then pcall(E.RefreshPage, E) end
end

-- Own frames (palette, preview, text) are never built during EUI's search pre-build; they only reserve space then.
local function PaletteRow(parent, y, row)
    if IsPrebuild() then return 40 end
    local host = Host(parent, y, 40)
    local label = ns.Kit.Text(host, 14, "text")
    label:SetPoint("LEFT", 20, 0)
    label:SetText(row.text)
    local palette = ns.Kit.Palette(host, row.colors, row.get, function(r, g, b)
        row.set(r, g, b)
        RefreshEUIPage()
    end, 20)
    palette:SetPoint("RIGHT", -20, 0)
    local tip = Settings.Tip(row)
    if tip then ns.Kit.Tooltip(host, { row.text, tip }, "ANCHOR_TOPLEFT") end
    host:EnableMouse(tip ~= nil)
    return 40
end

-- Sample sentence in the chosen font (a Kit text: it follows the font setting by itself).
local function PreviewRow(parent, y, row)
    if IsPrebuild() then return 52 end
    local host = Host(parent, y - 4, 44)
    local box = ns.Kit.Panel(host, "inputBg", "border", "input")
    box:SetPoint("TOPLEFT", 20, 0)
    box:SetPoint("BOTTOMRIGHT", -20, 0)
    local text = ns.Kit.Text(box, 16, "text")
    text:SetPoint("LEFT", 12, 0)
    text:SetPoint("RIGHT", -12, 0)
    text:SetWordWrap(false)
    text:SetText(row.text)
    return 52
end

-- Static or computed text (versions, module states); computed texts are read when the page is built.
local function TextRow(parent, y, row)
    local str = row.get and row.get() or row.text or ""
    local h = 20 + 16 * select(2, str:gsub("\n", "\n"))
    if IsPrebuild() then return h end
    local text = parent:CreateFontString(nil, "OVERLAY")
    ns.Theme.SetFont(text, 13)
    text:SetTextColor(0.75, 0.75, 0.75)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    text:SetPoint("TOPLEFT", parent, "TOPLEFT", Pad() + 20, y - 6)
    text:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(Pad() + 20), y - 6)
    if text.SetSpacing then text:SetSpacing(4) end
    text:SetText(str)
    if row.get then liveTexts[#liveTexts + 1] = { fs = text, get = row.get } end
    return math.max(h, math.floor((text:GetStringHeight() or 0) + 14))
end

-- A pack's own drawing (custom row) on a Kit frame inside the page.
local function CustomRow(parent, y, row)
    local height = row.height or 60
    if IsPrebuild() then return height end
    local host = Host(parent, y, height)
    local ok, inner = pcall(row.build, host)
    if not ok then geterrorhandler()(inner) end
    if ok and inner and inner.Update then
        pcall(inner.Update, inner)
        liveTexts[#liveTexts + 1] = { update = inner }
    end
    return height
end

local gated = {} -- { frame, enabled } rows that only work in one mode

-- Dims and locks rows whose enabled() is false (EUI's widgets have no disabled state of their own).
local function UpdateGated()
    for _, g in ipairs(gated) do
        local on = g.enabled() and true or false
        g.frame:SetAlpha(on and 1 or 0.3)
        for _, child in ipairs({ g.frame:GetChildren() }) do
            if child.EnableMouse then child:EnableMouse(on) end
        end
    end
end

local function Render(parent, yOffset, rows)
    local W = EllesmereUI.Widgets
    if type(W) ~= "table" then return 1 end
    local y = yOffset
    for _, row in ipairs(rows) do
        local set = row.set
        if set then
            set = function(...)
                if row.enabled and not row.enabled() then return end
                row.set(...)
                if row.refresh then RefreshEUIPage() end
                UpdateGated()
            end
        end
        local tip = Settings.Tip(row)
        local frame, h
        if row.type == "header" then
            frame, h = W:SectionHeader(parent, row.text, y, tip)
        elseif row.type == "toggle" then
            frame, h = W:Toggle(parent, row.text, y, function() return row.get() and true or false end, set, tip)
        elseif row.type == "slider" then
            frame, h = W:Slider(parent, row.text, y, row.min, row.max, row.step, row.get, set, tip)
        elseif row.type == "dropdown" then
            local values, order = row.values()
            frame, h = W:Dropdown(parent, row.text, y, values, row.get, set, order, tip)
        elseif row.type == "button" then
            frame, h = W:Button(parent, row.text, y, function()
                if row.enabled and not row.enabled() then return end
                row.onClick()
                RefreshEUIPage()
            end)
        elseif row.type == "color" then
            frame, h = W:ColorPicker(parent, row.text, y, row.get, set, false)
        elseif row.type == "palette" then
            h = PaletteRow(parent, y, row)
        elseif row.type == "text" then
            h = TextRow(parent, y, row)
        elseif row.type == "preview" then
            h = PreviewRow(parent, y, row)
        elseif row.type == "custom" and row.build then
            h = CustomRow(parent, y, row)
        end
        if row.enabled and type(frame) == "table" and frame.SetAlpha and not IsPrebuild() then
            gated[#gated + 1] = { frame = frame, enabled = row.enabled }
        end
        y = y - (h or 0)
    end
    UpdateGated()
    return math.abs(y)
end

---------------------------------------------------------------------------
-- Host entry point (router)
---------------------------------------------------------------------------

local function Open(pageKey)
    local page, module = Settings.FindPage(pageKey or Settings.FirstPage())
    if not page then page, module = Settings.FindPage(Settings.FirstPage()) end
    local E = EllesmereUI
    if not (type(E) == "table" and type(E.OpenPlugin) == "function") then
        ns.Say(L["EllesmereUI is missing or too old (no plugin API)."])
        return false
    end
    local ok, opened = pcall(E.OpenPlugin, PLUGIN_ID, module.key, page.label)
    if not (ok and opened) then
        ns.Say(L["EllesmereUI is missing or too old (no plugin API)."])
        return false
    end
    return true
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

local function Module(module)
    local names = {}
    for i, page in ipairs(module.pages) do
        names[i] = page.label
        byName[page.label] = page
    end
    return {
        key = module.key,
        title = module.title,
        description = module.desc,
        pages = names,
        buildPage = function(pageName, parent, y)
            local page = byName[pageName]
            if page then return Render(parent, y, Settings.Rows(page, "eui")) end
            return 1
        end,
        onPageCacheRestore = function()
            ns.Theme.CheckLive() -- accent or font may have changed while the page was hidden
            for _, live in ipairs(liveTexts) do -- module states, versions, custom drawings
                if live.fs then live.fs:SetText(live.get()) end
                if live.update then pcall(live.update.Update, live.update) end
            end
            UpdateGated()
        end,
    }
end

local function Register()
    if ns.dormant then
        ns.registerResult = "dormant (runs in " .. tostring(ns.PACKAGE.yieldTo) .. ")"
        return
    end
    local E = EllesmereUI
    if type(E) ~= "table" then
        ns.registerResult = "no EllesmereUI"
        return
    end
    if not ns.db.settings.integrateEUI then
        ns.registerResult = "integration off"
        return
    end
    if type(E.RegisterPlugin) ~= "function" then
        ns.registerResult = "no RegisterPlugin"
        return
    end
    local modules = {}
    for i, module in ipairs(Settings.Modules()) do modules[i] = Module(module) end
    -- The section label must not start with "EUI"/"Ellesmere" (EUI rejects the whole registration).
    local ok, result = pcall(E.RegisterPlugin, PLUGIN_ID, { label = ns.PACKAGE.pluginLabel or ns.PACKAGE.title, modules = modules })
    ns.registerResult = ok and result or ("error: " .. tostring(result))
    if ok and result ~= false then
        ns.hosts.eui = {
            Open = Open,
            IsShown = function() return false end, -- EUI's panel opens and closes itself
            Hide = function() end,
        }
    end
end

ns.OnReady(Register)
