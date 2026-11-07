-- OpenMap: its map menu, redone. The OpenMap button on the map (and /openmap, the minimap button, the key binding)
-- opens our window instead of OpenMap's: search on top, the actions as one row of quick buttons, then the settings
-- in eight pages with a sidebar (Settings\OpenMap.lua; the same pages are in our options window). Theme, accent and
-- font follow BeautifulSkins. The window remembers its place, size and page; it opens next to the OpenMap button
-- until it is moved, and closes with the map.
-- Hook points (OpenMap v0.7.5-beta): the global frame OpenMapMenu (OpenMap's menu, made in mod:SetupPanel; its
-- OnShow is where the OpenMap button, /openmap and the binding end up), mod.db.menuOpen (OpenMap reopens its menu
-- with the map while it is set), mod:OpenMenu, mod:RefreshPanel (after every change of state), mod.CreateSearch,
-- the global OpenMap_Binding(id) (runs an action of the menu), and mod's state reads (PinMode, PinsShown,
-- PinsHidden, IsSketching, IsReporting, NewsUnseen). Post-hooks and HookScript only; nothing is hooked on the map.
local _, ns = ...
local L = ns.L
local Kit, Theme = ns.Kit, ns.Theme
local Paint, Bind, Box, Refresh = Theme.Paint, Theme.Bind, Theme.Box, Theme.Refresh

local M = ns.Modules.Register("openmap", { addon = "OpenMap", setting = "openmap", label = "OpenMap: map menu" })

local SIDE_W, NAV_H, CHIP_H, CHIP_GAP, SEARCH_H = 160, 28, 50, 6, 26
local REOPEN_GRACE = 0.3 -- seconds: OpenMap shows its menu twice when it opens the map for it
local LIT_EVERY = 0.25 -- seconds between looks at the actions' states while the window is open
local ICONS = "Interface\\Icons\\"

local win, ui, menuFrame
local openedAt = 0

local function Mod()
    return ns.OpenMap and ns.OpenMap.Mod() or nil
end

local function Saved()
    return ns.db.openmap
end

local function WorldMap()
    local map = rawget(_G, "WorldMapFrame")
    return type(map) == "table" and map or nil
end

local function MapVisible()
    local map = WorldMap()
    return map ~= nil and map:IsVisible() and true or false
end

-- An action of OpenMap's menu by its id (opens the map first if needed).
local function Binding(id)
    local fn = rawget(_G, "OpenMap_Binding")
    if type(fn) == "function" then fn(id) end
end

---------------------------------------------------------------------------
-- Quick buttons (OpenMap's actions)
---------------------------------------------------------------------------

local function Is(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, ...)
    return ok and v and true or false
end

local function QuestLogShown()
    local map = WorldMap()
    if not map then return false end
    if type(map.IsSidePanelShown) == "function" then return Is(map.IsSidePanelShown, map) end
    local log = ns.T(map.QuestLog) or ns.T(rawget(_G, "QuestMapFrame"))
    return log ~= nil and log:IsShown() and true or false
end

local function Actions(mod)
    local tools = ns.OpenMap
    return {
        { id = "find", label = L["Find me"], icon = ICONS .. "Ability_Hunter_SniperShot",
            tip = L["Glide to where you are. A middle-click on the map centres on you at the current zoom."] },
        { id = "questlog", label = L["Quest log"], icon = ICONS .. "INV_Misc_Book_08",
            tip = L["Show or hide the quest log beside the map."], lit = QuestLogShown },
        { id = "pin", label = L["Drop a pin"], short = L["Pin"], icon = ICONS .. "INV_Misc_Map_01", atlas = "Waypoint-MapPin-Tracked",
            available = tools.PinsOn,
            tip = L["Then click the map: a pin with a note of your own. Ctrl-click on the map does it any time."],
            right = L["Right-click: stop following the waypoint."],
            lit = function() return Is(mod.PinMode) end,
            litLabel = L["Click the map"],
            onRight = function()
                if type(mod.SetPinMode) == "function" then mod.SetPinMode(false) end
                if type(mod.ClearPin) == "function" then mod.ClearPin() end
            end },
        { id = "pins", label = L["Map pins"], icon = ICONS .. "INV_Misc_Map02", available = tools.PinsOn,
            tip = L["Every map pin: go to one, share them or add pins from a code."],
            right = L["Right-click: hide your pins on the map or show them again."],
            lit = function() return Is(mod.PinsShown) end, grey = function() return Is(mod.PinsHidden) end,
            onRight = function()
                if type(mod.SetPinsHidden) == "function" then mod.SetPinsHidden(not Is(mod.PinsHidden)) end
            end },
        { id = "quill", label = L["Quill"], icon = ICONS .. "INV_Feather_04", available = tools.QuillOn,
            tip = L["Draw on the map: lines, arrows, rings and raid marks, kept for you."],
            lit = function() return Is(mod.IsSketching, mod) end },
        { id = "report", label = L["Report a problem"], short = L["Report"], icon = ICONS .. "INV_Misc_Note_01",
            tip = L["Draw where something on the map looks wrong and tell OpenMap's authors about it."],
            lit = function() return Is(mod.IsReporting) end },
        { id = "news", label = L["What's new"], icon = ICONS .. "INV_Scroll_03",
            tip = L["The changes of this OpenMap version (marked until you have looked)."],
            badge = function() return Is(mod.NewsUnseen) end },
    }
end

local function HasAtlas(name)
    return name and C_Texture and type(C_Texture.GetAtlasInfo) == "function" and C_Texture.GetAtlasInfo(name) ~= nil
end

local function PaintChip(b, T)
    local lit = b.lit
    Box(b, T, lit and "select" or "control", lit and "accent" or "border", (not lit) and "button" or nil)
    Paint(b.label, lit and Kit.TextToken(T, "accent") or T.text)
    Paint(b.badge, T.accent)
end

local function Chip(parent)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetHeight(CHIP_H)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(22, 22)
    b.icon:SetPoint("TOP", 0, -6)
    b.label = Kit.Text(b, 11, false)
    b.label:SetPoint("BOTTOMLEFT", 3, 6)
    b.label:SetPoint("BOTTOMRIGHT", -3, 6)
    b.label:SetJustifyH("CENTER")
    b.label:SetWordWrap(false)
    b.badge = b:CreateTexture(nil, "OVERLAY")
    b.badge:SetSize(7, 7)
    b.badge:SetPoint("TOPRIGHT", -5, -5)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    Bind(hl, function(self, T) Paint(self, T.hover) end)
    Kit.Tooltip(b, function(self)
        local a = self.action
        if not a then return nil end
        return { a.label, a.tip, a.right }
    end, "ANCHOR_TOP")
    b:SetScript("OnClick", function(self, button)
        local a = self.action
        if not a then return end
        if button == "RightButton" and a.onRight then a.onRight() else Binding(a.id) end
        if ui then ui.RefreshChips() end
    end)
    Bind(b, PaintChip)
    return b
end

local function ShowAction(b, a)
    b.action = a
    if a.atlas and HasAtlas(a.atlas) then
        b.icon:SetAtlas(a.atlas)
        b.icon:SetTexCoord(0, 1, 0, 1)
    else
        b.icon:SetTexture(a.icon)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

---------------------------------------------------------------------------
-- Sidebar and pages
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
    b.text:SetPoint("LEFT", 14, 0)
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
    b:SetScript("OnClick", function(self) ui.ShowPage(self.key) end)
    return b
end

local function FindPage(key)
    for _, page in ipairs(ui.pageList) do
        if page.key == key then return page end
    end
    return ui.pageList[1]
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function StyleSearch(holder, box)
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", holder, "TOPLEFT", 6, -2)
    box:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -4, 2)
    for _, key in ipairs({ "Left", "Middle", "Right" }) do
        local t = ns.T(box[key])
        if t and type(t.Hide) == "function" then t:Hide() end
    end
    Bind(box, function(self, T)
        Theme.SetFont(self, 12)
        Paint(self, T.text)
        local hint = ns.T(self.Instructions)
        if hint and type(hint.SetTextColor) == "function" then
            Theme.SetFont(hint, 12)
            Paint(hint, T.textDim)
        end
    end)
end

local function Create(mod)
    local saved = Saved()
    ui = { pages = {}, chips = {} }
    win = Kit.Window({
        name = ns.packName .. "OpenMapMenu", title = "OpenMap", w = saved.window.w or 680, h = saved.window.h or 600,
        minW = 580, minH = 460, maxW = 1200, maxH = 1100, resizable = true, geometry = saved.window, strata = "DIALOG",
        headerHeight = 30,
        onShow = function() if ui.current then ui.ShowPage(ui.current) end end,
        onHide = function()
            -- closed by its own button or Escape while the map stays: OpenMap no longer reopens it with the map
            local m = Mod()
            if m and MapVisible() then m.db.menuOpen = false end
        end,
    })
    local version = ns.Version("OpenMap") or ""
    Bind(win, function(self, T)
        local c = T.textDim
        self.title:SetText(("OpenMap  |cff%02x%02x%02x%s|r"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
            math.floor(c[3] * 255 + 0.5), version))
    end)

    local content = win.content
    local y = 0

    -- search (OpenMap's own field and result list, in our frame)
    if type(mod.CreateSearch) == "function" then
        local holder = Kit.Panel(content, "inputBg", "border")
        holder:SetPoint("TOPLEFT", 0, 0)
        holder:SetPoint("TOPRIGHT", 0, 0)
        holder:SetHeight(SEARCH_H)
        local ok, box = pcall(mod.CreateSearch, holder, 300)
        if ok and type(box) == "table" then
            StyleSearch(holder, box)
            ui.search = box
            y = SEARCH_H + 8
        else
            holder:Hide()
        end
    end

    -- quick buttons
    local bar = CreateFrame("Frame", nil, content)
    bar:SetPoint("TOPLEFT", 0, -y)
    bar:SetPoint("TOPRIGHT", 0, -y)
    bar:SetHeight(CHIP_H)
    ui.bar = bar
    ui.actions = Actions(mod)
    for i = 1, #ui.actions do ui.chips[i] = Chip(bar) end
    y = y + CHIP_H + 10

    function ui.LayoutChips()
        local shown = {}
        for _, a in ipairs(ui.actions) do
            if not a.available or a.available() then shown[#shown + 1] = a end
        end
        local w = bar:GetWidth()
        if not w or w <= 0 then return end
        local cw = (w - CHIP_GAP * (#shown - 1)) / math.max(1, #shown)
        for i, b in ipairs(ui.chips) do
            local a = shown[i]
            if a then
                ShowAction(b, a)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", (i - 1) * (cw + CHIP_GAP), 0)
                b:SetWidth(cw)
                b:Show()
            else
                b.action = nil
                b:Hide()
            end
        end
        ui.shownCount = #shown
    end

    function ui.RefreshChips()
        local count = 0
        for _, a in ipairs(ui.actions) do
            if not a.available or a.available() then count = count + 1 end
        end
        if count ~= ui.shownCount then ui.LayoutChips() end
        for _, b in ipairs(ui.chips) do
            local a = b.action
            if a and b:IsShown() then
                local lit = a.lit and a.lit() or false
                local grey = a.grey and a.grey() or false
                local label = lit and a.litLabel or a.short or a.label
                if b.lit ~= lit or b.label:GetText() ~= label then
                    b.lit = lit
                    b.label:SetText(label)
                    Refresh(b)
                end
                b.icon:SetDesaturated(grey)
                b.icon:SetAlpha(grey and 0.5 or 1)
                b.badge:SetShown(a.badge and a.badge() or false)
            end
        end
    end
    bar:SetScript("OnSizeChanged", function() ui.LayoutChips() ui.RefreshChips() end)

    local line = Kit.Divider(content)
    line:SetPoint("TOPLEFT", 0, -(y - 5))
    line:SetPoint("TOPRIGHT", 0, -(y - 5))
    y = y + 4

    -- sidebar
    local side = Kit.Panel(content, "bgAlt", "border", "panel")
    side:SetPoint("TOPLEFT", 0, -y)
    side:SetPoint("BOTTOMLEFT")
    side:SetWidth(SIDE_W)
    ui.pageList = ns.OpenMapSettings.Pages()
    ui.nav = {}
    local ny = -8
    for _, page in ipairs(ui.pageList) do
        local b = NavButton(side, page)
        b:SetPoint("TOPLEFT", 4, ny)
        b:SetPoint("TOPRIGHT", -4, ny)
        ui.nav[#ui.nav + 1] = b
        ny = ny - NAV_H
    end
    -- the window follows BeautifulSkins' theme: a way there
    local look = Kit.Button(side, SIDE_W - 16, L["Theme and colours"], function() ns.host.OpenOptions("appearance") end, 22,
        "ghost")
    look:SetPoint("BOTTOM", 0, 8)
    Kit.Tooltip(look, { L["Theme and colours"], L["This window follows the BeautifulSkins theme, accent and font."] }, "ANCHOR_TOP")

    -- page
    local body = CreateFrame("Frame", nil, content)
    body:SetPoint("TOPLEFT", side, "TOPRIGHT", 12, 0)
    body:SetPoint("BOTTOMRIGHT")
    ui.title = Kit.Text(body, 16, "header")
    ui.title:SetPoint("TOPLEFT", 2, -4)
    ui.title:SetPoint("RIGHT", -2, 0)
    ui.title:SetWordWrap(false)
    ui.crumb = Kit.Text(body, 11, "textDim")
    ui.crumb:SetPoint("TOPLEFT", ui.title, "BOTTOMLEFT", 0, -3)
    ui.crumb:SetPoint("RIGHT", -2, 0)
    ui.crumb:SetWordWrap(false)
    local rule = Kit.Divider(body)
    rule:SetPoint("TOPLEFT", 0, -44)
    rule:SetPoint("TOPRIGHT", 0, -44)
    ui.area = CreateFrame("Frame", nil, body)
    ui.area:SetPoint("TOPLEFT", 0, -50)
    ui.area:SetPoint("BOTTOMRIGHT")

    function ui.ShowPage(key)
        local page = FindPage(key)
        if not page then return end
        for k, entry in pairs(ui.pages) do
            if k ~= page.key then entry.frame:Hide() end
        end
        local entry = ui.pages[page.key]
        if not entry then
            local frame = CreateFrame("Frame", nil, ui.area)
            frame:SetAllPoints()
            local S = ns.host.Settings
            entry = { frame = frame, form = S.RenderKit(frame, S.Rows(page, "standalone")) }
            ui.pages[page.key] = entry
        end
        entry.frame:Show()
        ui.current = page.key
        Saved().page = page.key
        ui.title:SetText(page.label)
        ui.crumb:SetText(page.desc or "")
        for _, b in ipairs(ui.nav) do Refresh(b) end
        entry.form:Refresh()
    end

    function ui.RefreshPage()
        local entry = ui.current and ui.pages[ui.current]
        if entry then entry.form:Refresh() end
    end

    -- closes with the map; the quick buttons follow what happens on the map
    local wait = 0
    win:HookScript("OnUpdate", function(self, elapsed)
        if not MapVisible() then
            self:Hide()
            return
        end
        wait = wait - elapsed
        if wait > 0 then return end
        wait = LIT_EVERY
        ns.Run("openmap", ui.RefreshChips)
    end)
    return win
end

-- OpenMap's menu rectangle in screen pixels (where it would have opened): left, bottom, right, top.
local function Rect(frame)
    if not (frame and type(frame.GetRect) == "function") then return nil end
    local l, b, w, h = frame:GetRect()
    if not (l and b and w and h) then return nil end
    local s = frame:GetEffectiveScale()
    return { l * s, b * s, (l + w) * s, (b + h) * s }
end

-- Next to the OpenMap button (the corner of OpenMap's menu nearest to it), until the player moves the window.
local function Place(rect)
    if Saved().window.point or not rect then
        win:ApplyGeometry()
        return
    end
    local s = win:GetEffectiveScale()
    local us = UIParent:GetEffectiveScale()
    local sw, sh = UIParent:GetWidth() * us, UIParent:GetHeight() * us
    local right = (rect[1] + rect[3]) / 2 > sw / 2
    local low = (rect[2] + rect[4]) / 2 < sh / 2
    local point = (low and "BOTTOM" or "TOP") .. (right and "RIGHT" or "LEFT")
    local x = (right and rect[3] or rect[1]) / s
    local y = (low and rect[2] or rect[4]) / s
    win:ClearAllPoints()
    win:SetPoint(point, UIParent, "BOTTOMLEFT", x, y)
end

local function Open(rect)
    local mod = Mod()
    if not mod then return end
    if not win then Create(mod) end
    if not win:IsShown() then Place(rect) end
    win:Show()
    win:Raise()
    openedAt = GetTime()
    ui.LayoutChips()
    ui.RefreshChips()
    ui.ShowPage(Saved().page or ui.pageList[1].key)
    mod.db.menuOpen = true -- OpenMap opens its menu, so ours, again with the map
end

-- OpenMap showed its menu: ours instead (the OpenMap button toggles it).
local function Intercept(menu)
    local rect = Rect(menu)
    menu:Hide() -- (OpenMap's OnHide clears mod.db.menuOpen while the map is up)
    if win and win:IsShown() then
        if GetTime() - openedAt > REOPEN_GRACE then
            win:Hide()
        else
            local mod = Mod()
            if mod then mod.db.menuOpen = true end
        end
        return
    end
    Open(rect)
end

local function HookMenu()
    if menuFrame then return end
    local menu = rawget(_G, "OpenMapMenu")
    if type(menu) ~= "table" or type(menu.HookScript) ~= "function" then return end
    menuFrame = menu
    menu:HookScript("OnShow", ns.Guard("openmap", Intercept))
    if menu:IsShown() then ns.Run("openmap", Intercept, menu) end
end

function M.Enable()
    local mod = Mod()
    if not mod then return end
    HookMenu()
    if not menuFrame and type(mod.SetupPanel) == "function" then
        hooksecurefunc(mod, "SetupPanel", ns.Guard("openmap", HookMenu))
    end
    -- /openmap, the minimap button, Blizzard's settings page: always open (never toggle shut)
    if type(mod.OpenMenu) == "function" then
        hooksecurefunc(mod, "OpenMenu", ns.Guard("openmap", function()
            if MapVisible() and not (win and win:IsShown()) then Open(Rect(menuFrame)) end
        end))
    end
    if type(mod.RefreshPanel) == "function" then
        hooksecurefunc(mod, "RefreshPanel", ns.Guard("openmap", function()
            if not (win and win:IsShown()) then return end
            ui.RefreshChips()
            ui.RefreshPage()
        end))
    end
end

-- Theme or option changes elsewhere (our options window) reach an open menu.
ns.OnRefresh(function()
    if win and win:IsShown() and M.status == "active" then ns.Run("openmap", ui.RefreshPage) end
end)

-- For the offline test.
M.Open, M.Window = Open, function() return win end
