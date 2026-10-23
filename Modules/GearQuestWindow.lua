-- GearQuest Forever: the main window (list, details, filters, tabs, settings, simulator) and its small windows (the
-- upgrade bar at the character panel, the "Hunt obtained" toast, the portrait guide's bubble) in the flat look:
-- dark panels with hair-line borders instead of metal edges and parchment, flat buttons, check boxes and scroll bars,
-- light text instead of the dark parchment text, the accent instead of the classic gold. GearQuest's font sizes stay
-- (its layouts are measured with them); only the window title takes our font.
-- GearQuest builds parts of the window late (menus, pages, rows). A skin pass walks the window after it is shown and
-- after GearQuest's building and refreshing functions ran (post-hooks, at most ten passes a second). Everything
-- already skinned is skipped, so a pass only touches what is new.
local _, ns = ...
local Skin = ns.Skin
local C = ns.Colors
local T = ns.T

local LOG_FRAME = "GearQuestLogFrame"
local LOG_PANELS = { "GearQuestSlotRankPanel", "GearQuestSimulateDialog", "GearQuestSourceFilterMenu" }
local POPUPS = { "GearQuestObtainToast", "GearQuestUpgradeBar", "GearQuestPortraitGuide", "GearQuestCustomSpecPanel" }
-- GearQuest.Log functions after which the window may have new parts (name patterns).
local PATTERNS = { "^Show", "^Select", "^Refresh", "^Build", "^Create", "^Toggle", "^Layout", "^Render", "^Populate",
    "^Update", "^Ensure", "^Open", "^Set" }
local SKIP = { "Tooltip", "Mouse", "Scroll", "Hover", "Pulse" }
local PASS_DELAY = 0.1

local Win = ns.Modules.Register("gqWindow", { addon = "GearQuestForever", setting = "gqWindow",
    label = "GearQuest: window" })
local Pop = ns.Modules.Register("gqPopups", { addon = "GearQuestForever", setting = "gqPopups",
    label = "GearQuest: popups and toasts" })

local function GQ()
    local gq = rawget(_G, "GearQuest")
    return type(gq) == "table" and gq or nil
end

local function Global(name)
    local f = rawget(_G, name)
    return type(f) == "table" and f.GetObjectType and f or nil
end

-- Textures GearQuest loads from its own files: parchment becomes a dark fill, the speech-bubble tail goes.
local function TextureRule(tex)
    if Skin.done[tex] then return end
    Skin.done[tex] = "seen" -- looked at once; GearQuest sets these files when it creates the texture
    local file = tex.GetTexture and tex:GetTexture()
    if type(file) ~= "string" then return end
    local lower = file:lower()
    if lower:find("parchment", 1, true) then
        Skin.Solid(tex, C.inset, 1)
    elseif lower:find("tail", 1, true) and lower:find("gearquest", 1, true) then
        Skin.Hide(tex)
    end
end

-- GearQuest keeps its decoration in fields of the frame it decorates (its files are known to the client by file id,
-- so the texture path cannot be read): parchment, colour fills, drawn gold edges, the rail icons.
local FILL_FIELDS = { "blackBg", "gqFill", "gqOpenCover" }
local EDGE_FIELDS = { "gqBorderTop", "gqBorderBottom", "gqBorderLeft", "gqBorderRight",
    "gqEdgeTop", "gqEdgeBottom", "gqEdgeLeft", "gqEdgeRight" }

local function FieldRules(frame)
    local parchment = T(frame.gqParchment)
    if parchment and Skin.done[parchment] ~= "solid" then Skin.Solid(parchment, C.inset, 1) end
    for _, key in ipairs(FILL_FIELDS) do Skin.Fill(T(frame[key])) end
    for _, key in ipairs(EDGE_FIELDS) do
        local edge = T(frame[key])
        if edge and Skin.done[edge] ~= "solid" then Skin.Solid(edge, C.border, 1) end
    end
    local icon = T(frame.gqIcon)
    if icon and Skin.done[icon] ~= "icon" and icon.SetDesaturated then
        Skin.done[icon] = "icon"
        icon:SetDesaturated(true)
    end
end

local function Visit(object, kind)
    if kind == "Texture" then
        TextureRule(object)
    elseif kind ~= "FontString" then
        FieldRules(object)
        Skin.Auto(object, kind)
    else
        Skin.Auto(object, kind)
    end
end

local function WalkIfShown(frame)
    if frame and frame:IsShown() then Skin.Walk(frame, Visit) end
end

-- ----------------------------------------------------------------------------------------------- main window

local chromeDone = false

-- The window's own chrome, once: no metal frame, no portrait, flat background, title in our font.
local function Chrome(frame)
    if chromeDone then return end
    chromeDone = true
    Skin.Hide(T(frame.NineSlice))
    Skin.Hide(T(frame.gqOuterBorder))
    for _, key in ipairs({ "Bg", "TitleBg", "TopTileStreaks" }) do Skin.Hide(T(frame[key])) end
    if ns.db.gqWindow.hidePortrait then
        Skin.Hide(T(frame.gqPortraitHolder))
        Skin.Hide(T(frame.PortraitContainer))
        Skin.Hide(T(frame.portrait))
    end
    Skin.Flat(frame, C.panel, C.panelAlpha)
    Skin.Solid(T(frame.blackBg), C.panel, C.panelAlpha)
    for _, inset in ipairs({ T(frame.listInset) or false, T(frame.detailBg) or false }) do
        if inset then
            Skin.Solid(T(inset.blackBg), C.inset, 1)
            Skin.Solid(T(inset.gqParchment), C.inset, 1)
        end
    end
    local container = T(frame.TitleContainer)
    local title = container and T(container.TitleText) or T(frame.TitleText)
    if title then
        ns.KeepSizeFont(title)
        Skin.Text(title)
    end
    local close = T(frame.CloseButton) or Global(LOG_FRAME .. "CloseButton")
    if close then Skin.Close(close) end
end

local function WindowPass()
    local frame = Global(LOG_FRAME)
    if not (frame and frame:IsShown()) then return end
    Chrome(frame)
    Skin.Walk(frame, Visit)
    for _, name in ipairs(LOG_PANELS) do WalkIfShown(Global(name)) end
end

local function PopupPass()
    for _, name in ipairs(POPUPS) do WalkIfShown(Global(name)) end
end

local queued = false
local function QueuePass()
    if queued then return end
    queued = true
    C_Timer.After(PASS_DELAY, function()
        queued = false
        ns.Run("gqWindow", WindowPass)
        ns.Run("gqPopups", PopupPass)
    end)
end

local function Wanted(name)
    if type(name) ~= "string" then return false end
    for _, skip in ipairs(SKIP) do
        if name:find(skip, 1, true) then return false end
    end
    for _, pattern in ipairs(PATTERNS) do
        if name:find(pattern) then return true end
    end
    return false
end

-- Post-hooks on the building and refreshing functions of a GearQuest table (e.g. GearQuest.Log).
local function HookTable(tbl)
    if type(tbl) ~= "table" then return end
    local names = {}
    for key, value in pairs(tbl) do
        if type(value) == "function" and Wanted(key) then names[#names + 1] = key end
    end
    for _, key in ipairs(names) do hooksecurefunc(tbl, key, QueuePass) end
end

local function HookShown(name, fn)
    local frame = Global(name)
    if frame and not Skin.done[frame] then frame:HookScript("OnShow", fn) end
    return frame
end

-- While the window is open a pass also runs twice a second: GearQuest rebuilds tabs and pages from local functions no
-- hook can reach. Already skinned parts are skipped, so a pass over an unchanged window costs little.
local WATCH_EVERY = 0.5
local watchTicker

local function WatchWindow(frame)
    frame:HookScript("OnShow", function()
        QueuePass()
        if watchTicker then watchTicker:Cancel() end
        watchTicker = C_Timer.NewTicker(WATCH_EVERY, QueuePass)
    end)
    frame:HookScript("OnHide", function()
        if watchTicker then watchTicker:Cancel() end
        watchTicker = nil
    end)
end

function Win.Enable()
    local gq = GQ()
    if not gq then return end
    HookTable(gq.Log)
    local frame = Global(LOG_FRAME)
    if frame then
        WatchWindow(frame)
    elseif gq.Log and type(gq.Log.Init) == "function" then
        local watching = false
        hooksecurefunc(gq.Log, "Init", function()
            local f = Global(LOG_FRAME)
            if f and not watching then
                watching = true
                WatchWindow(f)
            end
        end)
    end
    QueuePass()
end

-- Popups appear on their own (an upgrade found, a hunt obtained, the guide speaks): they are walked when shown.
local popupHooked = {}

local function HookPopups()
    for _, name in ipairs(POPUPS) do
        if not popupHooked[name] and HookShown(name, QueuePass) then popupHooked[name] = true end
    end
end

function Pop.Enable()
    local gq = GQ()
    if not gq then return end
    for _, key in ipairs({ "Toast", "Popup", "PortraitGuide" }) do HookTable(gq[key]) end
    HookPopups()
    -- they are created the first time they are needed
    C_Timer.NewTicker(2, ns.Guard("gqPopups", HookPopups), 30)
    QueuePass()
end

ns.OnRefresh(function()
    if Win.status == "active" or Pop.status == "active" then QueuePass() end
end)
