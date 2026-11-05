-- Our options window: a plain themed frame, works with and without EllesmereUI and in combat. Sidebar with
-- the modules as headings and their pages below, the page on the right. Pages are built on first use and cached; their
-- content comes from the row descriptions in Settings/Settings.lua.
local addonName, ns = ...
local L = ns.L
local Theme, Kit, Settings = ns.Theme, ns.Kit, ns.Settings
local Paint, Bind, Refresh = Theme.Paint, Theme.Bind, Theme.Refresh

local Options = {}
ns.Options = Options

local SIDE_W, GAP, NAV_H = 168, 12, 28
local LOGO = "Interface\\AddOns\\" .. addonName .. "\\Media\\Icon"

local win, ui

local function Saved()
    return ns.db.settings.options
end

---------------------------------------------------------------------------
-- Sidebar
---------------------------------------------------------------------------

local function NavButton(parent, page)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(NAV_H)
    b.key = page.key
    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetAllPoints()
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.mark = b:CreateTexture(nil, "ARTWORK")
    b.mark:SetPoint("TOPLEFT")
    b.mark:SetPoint("BOTTOMLEFT")
    b.mark:SetWidth(2)
    b.text = Kit.Text(b, 12, false)
    b.text:SetPoint("LEFT", 16, 0)
    b.text:SetPoint("RIGHT", -6, 0)
    b.text:SetWordWrap(false)
    b.text:SetText(page.label)
    Bind(b, function(self, T)
        local active = ui and ui.current == self.key
        Paint(self.sel, T.select)
        self.sel:SetShown(active and true or false)
        Paint(self.hl, T.hover)
        Paint(self.mark, T.accent)
        self.mark:SetShown(active and true or false)
        Paint(self.text, active and T.text or T.textDim)
    end)
    b:SetScript("OnClick", function(self) Options.ShowPage(self.key) end)
    return b
end

local function BuildSidebar(side)
    -- brand block: logo, name and version
    local logo = side:CreateTexture(nil, "ARTWORK")
    logo:SetSize(32, 32)
    logo:SetPoint("TOPLEFT", 10, -10)
    logo:SetTexture(LOGO)
    local name = Kit.Text(side, 14, "header")
    name:SetPoint("TOPLEFT", logo, "TOPRIGHT", 8, -1)
    name:SetPoint("RIGHT", -8, 0)
    name:SetWordWrap(false)
    name:SetText(ns.PACKAGE.title)
    local version = Kit.Text(side, 10, "textDim")
    version:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
    version:SetText("v" .. ns.Version())
    local line = Kit.Divider(side)
    line:SetPoint("TOPLEFT", 10, -50)
    line:SetPoint("TOPRIGHT", -10, -50)

    -- the page list scrolls once the packs bring more pages than the window is high
    local list = Kit.ScrollArea(side)
    list:SetPoint("TOPLEFT", 0, -56)
    list:SetPoint("BOTTOMRIGHT", 0, 4)
    local nav = list.child
    ui.nav = {}
    local y = -4
    for _, module in ipairs(Settings.Modules()) do
        local heading = Kit.Text(nav, 10, "accent")
        heading:SetPoint("TOPLEFT", 12, y - 4)
        heading:SetPoint("RIGHT", -8, 0)
        heading:SetWordWrap(false)
        heading:SetText(module.title)
        y = y - 20
        for _, page in ipairs(module.pages) do
            local b = NavButton(nav, page)
            b:SetPoint("TOPLEFT", 4, y)
            b:SetPoint("TOPRIGHT", -4, y)
            ui.nav[#ui.nav + 1] = b
            y = y - NAV_H
        end
        y = y - 8
    end
    list:SetContentHeight(-y + 4)
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local function Create()
    local saved = Saved()
    ui = { pages = {} }
    win = Kit.Window({
        name = addonName .. "Options", title = ns.PACKAGE.title, w = saved.w or 740, h = saved.h or 560, minW = 600, minH = 420,
        maxW = 1600, maxH = 1200, resizable = true, geometry = saved, strata = "HIGH", headerHeight = 34,
        onShow = function()
            local entry = ui.current and ui.pages[ui.current]
            if entry and entry.form then entry.form:Refresh() end
        end,
        onHide = function() Kit.CloseMenu() end,
    })

    local content = win.content
    local side = Kit.Panel(content, "bgAlt", "border", "panel")
    side:SetPoint("TOPLEFT")
    side:SetPoint("BOTTOMLEFT")
    side:SetWidth(SIDE_W)
    ui.side = side
    BuildSidebar(side)

    local body = CreateFrame("Frame", nil, content)
    body:SetPoint("TOPLEFT", side, "TOPRIGHT", GAP, 0)
    body:SetPoint("BOTTOMRIGHT")
    ui.body = body
    ui.title = Kit.Text(body, 16, "header")
    ui.title:SetPoint("TOPLEFT", 2, -2)
    ui.title:SetPoint("RIGHT", -2, 0)
    ui.title:SetWordWrap(false)
    ui.crumb = Kit.Text(body, 11, "textDim")
    ui.crumb:SetPoint("TOPLEFT", ui.title, "BOTTOMLEFT", 0, -3)
    ui.crumb:SetPoint("RIGHT", -2, 0)
    ui.crumb:SetWordWrap(false)
    local line = Kit.Divider(body)
    line:SetPoint("TOPLEFT", 0, -42)
    line:SetPoint("TOPRIGHT", 0, -42)
    ui.area = CreateFrame("Frame", nil, body)
    ui.area:SetPoint("TOPLEFT", 0, -52)
    ui.area:SetPoint("BOTTOMRIGHT")
    return win
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

-- Shows a page (built on first use).
function Options.ShowPage(key)
    if not win then Create() end
    local page, module = Settings.FindPage(key)
    if not page then page, module = Settings.FindPage(Settings.FirstPage()) end
    key = page.key
    for k, entry in pairs(ui.pages) do
        if k ~= key then entry.frame:Hide() end
    end
    local entry = ui.pages[key]
    if not entry then
        local frame = CreateFrame("Frame", nil, ui.area)
        frame:SetAllPoints()
        entry = { frame = frame, form = Settings.RenderKit(frame, Settings.Rows(page, "standalone")) }
        ui.pages[key] = entry
    end
    entry.frame:Show()
    ui.current = key
    Saved().page = key
    ui.title:SetText(page.label)
    ui.crumb:SetText(module.title .. "  \194\183  " .. module.desc)
    for _, b in ipairs(ui.nav) do Refresh(b) end
    entry.form:Refresh()
    return true
end

-- Opens the window on pageKey (nil = the last page).
function Options.Open(pageKey)
    if not win then Create() end
    win:Show()
    return Options.ShowPage(pageKey or Saved().page or Settings.FirstPage())
end

function Options.Toggle()
    if win and win:IsShown() then
        win:Hide()
    else
        Options.Open()
    end
end

function Options.IsShown()
    return win ~= nil and win:IsShown() and true or false
end

function Options.Hide()
    if win then win:Hide() end
end

-- Key of the shown page and its form (nil before the first open).
function Options.Current()
    if not ui then return nil end
    local entry = ui.pages[ui.current]
    return ui.current, entry and entry.form
end

ns.hosts.standalone = { Open = Options.Open, IsShown = Options.IsShown, Hide = Options.Hide }
