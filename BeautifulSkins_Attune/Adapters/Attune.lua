-- Attune adapter: the ONLY file that knows Attune's globals, frame names and widget paths (besides the contract in
-- AttuneCompat.lua). Skin, search and settings code ask ns.Attune.* and never touch Attune directly.
-- Everything here is read-only and defensive: missing parts return nil instead of raising errors. Attune's own
-- functions are hooked with hooksecurefunc only; handlers run through the module guard (ns.Modules.Run).
local _, ns = ...

local A = {}
ns.Attune = A

local Compat = ns.AttuneCompat
local TOLERANCE = 0.02
local ZOOM_MIN, ZOOM_MAX = 0.1, 1.5
-- Attune clamps its own zoom to this range; outside it the skin scales the chain itself
local ATTUNE_ZOOM_MIN, ATTUNE_ZOOM_MAX = 0.5, 1.0

local windowSeen = false
local currentAttune
local charKey
local unknownStates = {}

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function IsFrame(value)
    return type(value) == "table" and type(value.GetObjectType) == "function"
end

local function DB()
    local db = _G.Attune_DB
    return type(db) == "table" and db or nil
end

local function Data()
    local data = _G.Attune_Data
    return type(data) == "table" and data or nil
end

-- Attune's AceLocale table creates (and caches) missing keys on read; rawget keeps it untouched.
function A.Lang(key)
    local lang = _G.AttuneLang
    if type(lang) ~= "table" or key == nil then return nil end
    local text = rawget(lang, key)
    if type(text) == "string" and text ~= "" then return text end
    return nil
end
local Lang = A.Lang

local function Plain(value)
    if value == nil or ns.IsSecret(value) then return nil end
    return value
end

---------------------------------------------------------------------------
-- Version and contract
---------------------------------------------------------------------------

function A.Version()
    local getter = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    if type(getter) ~= "function" then return nil end
    local ok, version = pcall(getter, "Attune", "Version")
    if ok and type(version) == "string" and version ~= "" then return version end
    return nil
end

function A.TestedVersions()
    return Compat.testedVersions
end

function A.IsTestedVersion()
    local version = A.Version()
    for _, tested in ipairs(Compat.testedVersions) do
        if tested == version then return true end
    end
    return false
end

function A.IsWindowSeen()
    return windowSeen
end

-- Roots of "@alias.field" contract names.
local aliases = {
    Tree = function() return A.Tree() end,
    Graph = function() return A.GraphScroll() end,
    Main = function() return A.MainWidget() end,
    Next = function() return A.NextFrame() end,
    Broker = function() return A.Broker() end,
}

-- State of one contract entry: "ok", "missing", "window" (waits for Attune's window), "view" (needs the list view
-- or a selected chain), "lazy" (created on demand, never blocks) or "offline" (frame-name prefix, checked offline).
local function EntryState(entry)
    local name = entry.name
    if name:find("*", 1, true) then return "offline" end
    local notYet = entry.when == "lazy" and "lazy" or (entry.when == "window" and not windowSeen and "window") or nil

    if entry.kind == "function" then
        if type(_G[name]) == "function" then return "ok" end
        return notYet or "missing"
    elseif entry.kind == "frame" then
        if IsFrame(_G[name]) then return "ok" end
        return notYet or "missing"
    elseif entry.kind == "global" then
        if _G[name] ~= nil then return "ok" end
        return notYet or "missing"
    elseif entry.kind == "field" then
        local root, rest = name:match("^@?([%w_]+)%.(.+)$")
        if not root then return "missing" end
        local value
        if name:sub(1, 1) == "@" then
            local resolve = aliases[root]
            value = resolve and resolve()
            if value == nil then return notYet or "view" end
        else
            value = _G[root]
            if value == nil then return notYet or "missing" end
        end
        local parent = value
        local silent = root == "AttuneLang" -- AceLocale (silent) invents missing keys on read: look raw
        for key in rest:gmatch("[^%.]+") do
            if type(value) ~= "table" then return notYet or "missing" end
            parent = value
            if silent then value = rawget(value, key) else value = value[key] end
        end
        if value ~= nil or (entry.nilable and type(parent) == "table") then return "ok" end
        return notYet or "missing"
    end
    return "missing"
end

local STATE_RANK = { ok = 0, offline = 0, lazy = 1, view = 2, window = 3, missing = 4 }

-- Aggregated state of a capability: the worst state of its entries, plus the names behind that state.
function A.CapState(cap)
    local worst, names = nil, {}
    for _, entry in ipairs(Compat.contract) do
        if entry.cap == cap then
            local state = EntryState(entry)
            if worst == nil or STATE_RANK[state] > STATE_RANK[worst] then
                worst, names = state, { entry.name }
            elseif state == worst and STATE_RANK[state] > 0 then
                names[#names + 1] = entry.name
            end
        end
    end
    return worst or "missing", names
end

-- true = usable, false = missing, nil = not decidable yet (window not opened, other view shown).
function A.Has(cap)
    local state = A.CapState(cap)
    if state == "missing" then return false end
    if state == "window" or state == "view" then return nil end
    return true
end

-- Every entry that is missing right now: { { cap = ..., name = ... }, ... }.
function A.Missing()
    local list = {}
    for _, entry in ipairs(Compat.contract) do
        if EntryState(entry) == "missing" then
            list[#list + 1] = { cap = entry.cap, name = entry.name }
        end
    end
    return list
end

-- One row per capability in contract order, for diag and probe: { cap, state, names }.
function A.Report()
    local rows, seen = {}, {}
    for _, entry in ipairs(Compat.contract) do
        if not seen[entry.cap] then
            seen[entry.cap] = true
            local state, names = A.CapState(entry.cap)
            rows[#rows + 1] = { cap = entry.cap, state = state, names = names }
        end
    end
    return rows
end

---------------------------------------------------------------------------
-- Guarded hooks (post-hooks only; Attune's code always runs first and unchanged)
---------------------------------------------------------------------------

function A.Hook(name, handler, moduleId)
    if type(_G[name]) ~= "function" then return false end
    hooksecurefunc(name, function(...) ns.Modules.Run(moduleId, handler, ...) end)
    return true
end

-- Named hook points, so modules never need Attune's function names. Arguments are Attune's own:
-- window (), view (noToggle), portrait (), select (attuneId, quiet), node (step, parent, posX, posY),
-- sideFeeder (endStep, sideSteps, colX, boxW, endX, endY), zoom (zoom), zoomSlider (), pan (), iconView (enabled),
-- reloadTree (), questDetail (step), questDetailHide (), questRewards (step), resultList (title),
-- resultRows () (after the list and after every row Attune adds a moment later).
local HOOK_POINTS = {
    window = { cap = "Frame", name = "Attune_Frame" },
    view = { cap = "ToggleView", name = "Attune_ToggleView" },
    portrait = { cap = "Portrait", name = "Attune_UpdateWindowPortrait" },
    select = { cap = "Select", name = "Attune_Select" },
    node = { cap = "CreateNode", name = "Attune_CreateNode" },
    sideFeeder = { cap = "SideFeeder", name = "Attune_DrawSideFeeder" },
    zoom = { cap = "Zoom", name = "Attune_ApplyGraphZoom" },
    zoomSlider = { cap = "Zoom", name = "Attune_CreateZoomSlider" },
    pan = { cap = "Pan", name = "Attune_ApplyGraphPan" },
    iconView = { cap = "IconView", name = "Attune_SetIconView" },
    reloadTree = { cap = "ReloadTree", name = "Attune_ReloadAttuneTree" },
    questDetail = { cap = "QuestDetail", name = "Attune_ShowQuestDetail" },
    questDetailHide = { cap = "QuestDetail", name = "Attune_HideQuestDetail" },
    questRewards = { cap = "QuestRewards", name = "Attune_ShowQuestRewards" },
    resultList = { cap = "Results", name = "Attune_ShowResultList" },
    resultRows = { cap = "Results", name = "Attune_UpdateResultScroll" },
    nextLayout = { cap = "NextWindow", name = "Attune_NextFrameLayout" },
    nextUpdate = { cap = "NextWindow", name = "Attune_NextFrameUpdate" },
}

-- Capability behind a hook point (for a module's requires list).
function A.HookPointCap(point)
    return HOOK_POINTS[point] and HOOK_POINTS[point].cap or nil
end

function A.On(point, handler, moduleId)
    local entry = HOOK_POINTS[point]
    if not entry then return false end
    return A.Hook(entry.name, handler, moduleId)
end

-- Post-hook on a method of one object (an AceGUI widget instance, a frame).
function A.HookMethod(object, method, handler, moduleId)
    if type(object) ~= "table" or type(object[method]) ~= "function" then return false end
    hooksecurefunc(object, method, function(...) ns.Modules.Run(moduleId, handler, ...) end)
    return true
end

function A.HookScript(frame, script, handler, moduleId)
    if not IsFrame(frame) or not frame:HasScript(script) then return false end
    frame:HookScript(script, function(...) ns.Modules.Run(moduleId, handler, ...) end)
    return true
end

---------------------------------------------------------------------------
-- Character, faction, class
---------------------------------------------------------------------------

-- Attune keys its characters as "<first> <second>" from the two values of UnitName("player").
function A.CharKey()
    if charKey then return charKey end
    local first, second = UnitName("player")
    first, second = Plain(first), Plain(second)
    if type(first) ~= "string" or first == "" then return nil end
    local db = DB()
    local toons = db and type(db.toons) == "table" and db.toons or nil
    if not toons then return nil end
    if second ~= nil then
        local key = first .. " " .. tostring(second)
        if toons[key] then
            charKey = key
            return key
        end
    end
    -- Fallback: exactly one saved character whose key starts with our name.
    local prefix, found = first .. " ", nil
    for key in pairs(toons) do
        if type(key) == "string" and key:sub(1, #prefix) == prefix then
            if found then return nil end
            found = key
        end
    end
    charKey = found
    return found
end

function A.Toon()
    local key = A.CharKey()
    local db = DB()
    if not key or not db or type(db.toons) ~= "table" then return nil end
    local toon = db.toons[key]
    return type(toon) == "table" and toon or nil
end

function A.PlayerClass()
    local _, classFile = UnitClass("player")
    classFile = Plain(classFile)
    return type(classFile) == "string" and classFile or nil
end

function A.PlayerFaction()
    local faction = Plain(UnitFactionGroup("player"))
    return type(faction) == "string" and faction or nil
end

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

function A.Attunes()
    local data = Data()
    return data and type(data.attunes) == "table" and data.attunes or {}
end

function A.AttuneById(id)
    if id == nil then return nil end
    id = tostring(id)
    local data = Data()
    if not data then return nil end
    if type(data.attuneById) == "table" then return data.attuneById[id] end
    for _, a in pairs(A.Attunes()) do
        if a.ID == id then return a end
    end
    return nil
end

function A.AttuneName(a)
    return type(a) == "table" and a.NAME or nil
end

-- All steps of one attunement (including spacers and steps outside the current patch, see IsStepVisible).
function A.StepsOf(id)
    if id == nil then return {} end
    id = tostring(id)
    local data = Data()
    if not data then return {} end
    if type(data.stepsByAttune) == "table" then return data.stepsByAttune[id] or {} end
    local list = {}
    if type(data.steps) == "table" then
        for _, step in pairs(data.steps) do
            if step.ID_ATTUNE == id then list[#list + 1] = step end
        end
    end
    return list
end

function A.FindStep(attuneId, stepId)
    if stepId == nil then return nil end
    stepId = tostring(stepId)
    for _, step in ipairs(A.StepsOf(attuneId)) do
        if tostring(step.ID) == stepId then return step end
    end
    return nil
end

-- Attune hides steps outside their patch window (VALIDFROM/VALIDTO).
function A.IsStepVisible(step)
    local check = _G.showPatchStep
    if type(check) ~= "function" then return true end
    local ok, visible = pcall(check, step)
    return not ok or visible and true or false
end

local TYPE_KEYS = {
    ["Quest"] = "quest", ["Pick Up"] = "pickup", ["Turn In"] = "turnin", ["Item"] = "item", ["Kill"] = "kill",
    ["Interact"] = "interact", ["Click"] = "click", ["Level"] = "level", ["Rep"] = "rep", ["Attune"] = "attune",
    ["End"] = "end", ["Spacer"] = "spacer",
}

-- Stable lower-case type of a step: quest, pickup, turnin, item, kill, interact, click, level, rep, attune, end,
-- spacer or other.
function A.TypeKey(step)
    return type(step) == "table" and TYPE_KEYS[step.TYPE] or "other"
end

function A.IsSideStep(step)
    return type(step) == "table" and step.SIDE and true or false
end

-- Looks up "<prefix><id>", for "a|b" ids also "<prefix><a>".
local function LangById(prefix, wowheadId)
    if wowheadId == nil then return nil end
    local id = tostring(wowheadId)
    return Lang(prefix .. id) or Lang(prefix .. (id:match("^(%d+)") or ""))
end

-- Name of a step as Attune titles its card (without the "owned/needed" item count).
function A.StepName(step)
    if type(step) ~= "table" then return nil end
    local key = A.TypeKey(step)
    local name
    if key == "item" then
        name = LangById("I_", step.ID_WOWHEAD)
    elseif key == "kill" or key == "interact" then
        name = LangById("N1_", step.ID_WOWHEAD)
    elseif key == "quest" or key == "pickup" or key == "turnin" then
        name = LangById("Q1_", step.ID_WOWHEAD)
    else
        name = LangById("O_", step.ID_WOWHEAD)
    end
    if name then return name end
    if type(step.STEP) == "string" and step.STEP ~= "" then return step.STEP end
    return nil
end

function A.ZoneName(step)
    if type(step) ~= "table" then return nil end
    local location = step.LOCATION
    if type(location) ~= "string" or location == "" then return nil end
    return Lang(location) or location
end

-- Attune's own (localized) word for the step type, as on its cards.
function A.TypeName(step)
    if type(step) ~= "table" then return nil end
    if step.SIDE then return Lang("Inside") or "Inside" end
    local key = A.TypeKey(step)
    if key == "level" then return Lang("Required level") or step.TYPE end
    if key == "attune" then return Lang("Attunement or key") or step.TYPE end
    if key == "rep" then return Lang("Reputation") or step.TYPE end
    return Lang(step.TYPE) or step.TYPE
end

-- Progress of this character in percent (0-100); nil without Attune data for this character.
function A.Progress(id)
    local toon = A.Toon()
    if not toon then return nil end
    local value = type(toon.attuned) == "table" and toon.attuned[tostring(id)] or nil
    return type(value) == "number" and value or 0
end

function A.IsStepDone(attuneId, stepId)
    local toon = A.Toon()
    if not toon or type(toon.done) ~= "table" then return false end
    return toon.done[tostring(attuneId) .. "-" .. tostring(stepId)] and true or false
end

function A.IsQuestActive(questId)
    questId = tonumber(questId)
    if not questId or not (C_QuestLog and C_QuestLog.IsOnQuest) then return false end
    local ok, active = pcall(C_QuestLog.IsOnQuest, questId)
    return ok and active and true or false
end

-- Class quests count only for their class (Attune shows them greyed for other classes).
function A.TracksProgress(attuneId)
    local a = A.AttuneById(attuneId)
    if not a or a.CLASS == nil or a.CLASS == "" then return true end
    return A.PlayerClass() == a.CLASS
end

-- Same filter as Attune's list: not deprecated (unless shown), class quests per option, own faction or both.
function A.IsVisibleInList(a)
    if type(a) ~= "table" then return false end
    local db = DB() or {}
    if a.DEPRECATED ~= nil and not db.showDeprecatedAttunes then return false end
    if a.CLASS ~= nil and a.CLASS ~= "" and not db.showAllClassQuests and A.PlayerClass() ~= a.CLASS then
        return false
    end
    return a.FACTION == "Both" or a.FACTION == A.PlayerFaction()
end

function A.ShowsAllClassQuests()
    local db = DB()
    return db and db.showAllClassQuests and true or false
end

function A.StoredZoom()
    local db = DB()
    return db and type(db.zoom) == "number" and db.zoom or nil
end

-- The attunement whose chain is shown (tracked from Attune_Select, else Attune's last viewed path).
function A.CurrentAttune()
    if currentAttune then return currentAttune end
    local getter = _G.Attune_GetLastViewed
    if type(getter) ~= "function" then return nil end
    local ok, path = pcall(getter)
    if not ok or type(path) ~= "string" then return nil end
    return path:match("([^\001]+)$")
end

---------------------------------------------------------------------------
-- Finders (all return nil when the part does not exist right now)
---------------------------------------------------------------------------

function A.MainFrame()
    local frame = _G.Attune_MainFrame
    return IsFrame(frame) and frame or nil
end

function A.MainWidget()
    local frame = A.MainFrame()
    local widget = frame and frame.obj
    return type(widget) == "table" and widget or nil
end

function A.Chrome()
    local chrome = _G.AttuneBronzeChrome
    return IsFrame(chrome) and chrome or nil
end

-- Attune's results button is a global with the generic name "GuildButton": only accept it inside Attune's window.
function A.ResultsButton()
    local button, main = _G.GuildButton, A.MainFrame()
    if IsFrame(button) and main and button:GetParent() == main then return button end
    return nil
end

function A.SurveyMenu()
    local frame = _G.Attune_SurveyMenuFrame
    return IsFrame(frame) and frame or nil
end

-- The backdrop frame of the survey menu. AceGUI's InlineGroup keeps it only as the parent of its content (there is no
-- widget.border field), so it is found from there.
function A.SurveyMenuBorder()
    local menu = A.SurveyMenu()
    local widget = menu and menu.obj
    if type(widget) ~= "table" then return nil end
    if IsFrame(widget.border) then return widget.border end
    local content = widget.content
    local border = IsFrame(content) and content:GetParent() or nil
    if IsFrame(border) and border ~= menu then return border end
    return nil
end

-- The list widget (AceGUI TreeGroup). Only exists in the list view; pooled, so always check before use.
function A.Tree()
    local widget = A.MainWidget()
    local first = widget and type(widget.children) == "table" and widget.children[1]
    if type(first) == "table" and first.type == "TreeGroup" then return first end
    return nil
end

function A.IsOwnTree(widget)
    return widget ~= nil and widget == A.Tree()
end

function A.ResultsGroup()
    local widget = A.MainWidget()
    local first = widget and type(widget.children) == "table" and widget.children[1]
    if type(first) == "table" and first.type == "SimpleGroup" then return first end
    return nil
end

-- The scroll widget holding the chain: TreeGroup > right panel > ScrollFrame.
function A.GraphScroll()
    local tree = A.Tree()
    local right = tree and type(tree.children) == "table" and tree.children[1]
    local scroll = type(right) == "table" and type(right.children) == "table" and right.children[1]
    if type(scroll) == "table" and scroll.type == "ScrollFrame" then return scroll end
    return nil
end

function A.IsOwnGraphScroll(widget)
    return widget ~= nil and widget == A.GraphScroll()
end

function A.GraphRoot()
    local root = _G.Attune_GraphRoot
    return IsFrame(root) and root or nil
end

-- Card of a step plus its parts: { icon, title, type, notif, notifText } (parts may be nil).
function A.Node(stepId)
    if stepId == nil then return nil end
    local id = tostring(stepId)
    local node = _G["Attune_Node_" .. id]
    if not IsFrame(node) then return nil end
    return node, {
        icon = _G["Attune_Icon_" .. id],
        title = _G["Attune_Title_" .. id],
        type = _G["Attune_Type_" .. id],
        notif = _G["Attune_Notif_" .. id],
        notifText = _G["Attune_NotifText_" .. id],
    }
end

function A.StepIdOfNode(node)
    if not IsFrame(node) then return nil end
    local name = node:GetName()
    return type(name) == "string" and name:match("^Attune_Node_(.+)$") or nil
end

local LINE_PREFIXES = { "Attune_Line1_", "Attune_Line2_", "Attune_Line3_" }

-- Visible connector lines that end at this step (incoming lines, spacer fill, side feeder of the end card).
function A.LinesOf(step)
    local lines = {}
    if type(step) ~= "table" or step.ID == nil then return lines end
    local id = tostring(step.ID)
    local function add(line)
        if IsFrame(line) and line:IsShown() then lines[#lines + 1] = line end
    end
    for from in tostring(step.FOLLOWS or ""):gmatch("[^&|]+") do
        for _, prefix in ipairs(LINE_PREFIXES) do
            add(_G[prefix .. id .. "_" .. from])
        end
    end
    add(_G["Attune_SpacerFill_" .. id])
    add(_G["Attune_SideFeeder_" .. id])
    return lines
end

-- Shown cards of the open chain: list of { step = ..., node = ... } in data order.
function A.ShownNodes()
    local list = {}
    for _, step in ipairs(A.StepsOf(A.CurrentAttune())) do
        local node = A.Node(step.ID)
        if node and node:IsShown() then list[#list + 1] = { step = step, node = node } end
    end
    return list
end

function A.OrMarks()
    local list, i = {}, 1
    while IsFrame(_G["Attune_OrLabel_" .. i]) do
        list[#list + 1] = _G["Attune_OrLabel_" .. i]
        i = i + 1
    end
    return list
end

function A.SideBox()
    local box, title = _G.Attune_SideBox, _G.Attune_SideBoxTitle
    return IsFrame(box) and box or nil, IsFrame(title) and title or nil
end

-- Attune's dungeon art: a BACKGROUND texture with a numeric file id on the chain's outer scroll frame.
function A.DungeonArt()
    local scroll = A.GraphScroll()
    local frame = scroll and scroll.frame
    if not IsFrame(frame) then return nil end
    local fallback
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == "Texture" and region:GetDrawLayer() == "BACKGROUND"
            and type(region:GetTexture()) == "number" then
            if region:IsShown() then return region end
            fallback = fallback or region
        end
    end
    return fallback
end

-- Attune's zoom slider (pooled AceGUI Slider on the chain's scroll frame).
function A.ZoomSlider()
    local scroll = A.GraphScroll()
    local frame = scroll and scroll.frame
    if not IsFrame(frame) then return nil end
    for _, child in ipairs({ frame:GetChildren() }) do
        local widget = child.obj
        if type(widget) == "table" and widget.type == "Slider" and child:IsShown() then return widget end
    end
    return nil
end

function A.QuestDetail()
    local frame = _G.AttuneQuestDetail
    return IsFrame(frame) and frame or nil
end

function A.RewardFrame()
    local frame = _G.AttuneQuestRewardFrame
    return IsFrame(frame) and frame or nil
end

function A.GiverTip()
    local frame = _G.AttuneGiverTip
    return IsFrame(frame) and frame or nil
end

function A.ResultHolder()
    local holder = _G.attunelocal_resultHolder
    return type(holder) == "table" and holder or nil
end

function A.ViewToggle()
    local bar = _G.attunelocal_viewToggle
    return type(bar) == "table" and bar or nil
end

-- The parts of Attune's window the skin replaces or moves: AceGUI Frame widget fields plus the buttons Attune adds.
-- { host, content, statusBar, statusText, closeButton, titleFrame, sizerSE, sizerS, sizerE, chrome } or nil.
function A.WindowParts()
    local host, widget = A.MainFrame(), A.MainWidget()
    if not host or not widget or not IsFrame(widget.content) then return nil end
    local statusText = widget.statustext
    local statusBar = type(statusText) == "table" and type(statusText.GetParent) == "function" and statusText:GetParent() or nil
    if not IsFrame(statusBar) then statusBar = nil end
    local closeButton
    for _, child in ipairs({ host:GetChildren() }) do
        if child.obj == widget and child ~= statusBar and child:GetObjectType() == "Button" then
            closeButton = child
            break
        end
    end
    local title = type(widget.titletext) == "table" and widget.titletext:GetParent() or nil
    return {
        host = host, content = widget.content, statusBar = statusBar, statusText = statusText,
        closeButton = closeButton, titleFrame = IsFrame(title) and title or nil,
        sizerSE = IsFrame(widget.sizer_se) and widget.sizer_se or nil,
        sizerS = IsFrame(widget.sizer_s) and widget.sizer_s or nil,
        sizerE = IsFrame(widget.sizer_e) and widget.sizer_e or nil,
        chrome = A.Chrome(),
    }
end

-- Attune's survey button is anonymous: the button of the window that carries Attune's "Survey" text.
function A.SurveyButton()
    local host = A.MainFrame()
    if not host then return nil end
    local label, results = Lang("Survey") or "Survey", A.ResultsButton()
    for _, child in ipairs({ host:GetChildren() }) do
        if child ~= results and child:GetObjectType() == "Button" and type(child.GetText) == "function"
            and child:GetText() == label then
            return child
        end
    end
    return nil
end

-- Runs the OnClick script of a button as a click would (also while the button is hidden or not clickable).
function A.ClickButton(button, mouseButton)
    if not IsFrame(button) then return false end
    local script = button:GetScript("OnClick")
    if type(script) == "function" then
        script(button, mouseButton or "LeftButton")
        return true
    end
    if type(button.Click) == "function" then
        button:Click()
        return true
    end
    return false
end

-- Runs a script of one of Attune's frames (status texts on enter/leave) without replacing it.
function A.RunScript(frame, script, ...)
    if not IsFrame(frame) then return end
    local handler = frame:GetScript(script)
    if type(handler) == "function" then handler(frame, ...) end
end

---------------------------------------------------------------------------
-- Attune's second window ("Attune: Next") and Attune's own options
---------------------------------------------------------------------------

-- The window lists the next step of every attunement. Its close button switches it off for good
-- (Attune_DB.showNextSteps = false) and only Attune's own options bring it back, so the skin offers a way back.
-- Attune builds the window the first time it is shown; before that there is nothing to skin.
function A.NextFrame()
    local f = _G.AttuneNextFrame
    if type(f) == "table" and type(f.GetObjectType) == "function" and f.scroll then return f end
end

-- Its parts. scroll, content, empty, grip, minBtn and rows are fields of the frame. Attune keeps the rest in locals:
-- its background, its title bar and its four gold edges are all textures of the frame and all of them give way to
-- our own, so they are collected as one list rather than told apart. The two remaining buttons are the title and the
-- close button; the close button is the only one of the two with a size of its own (16x16), the title is anchored.
function A.NextParts()
    local f = A.NextFrame()
    if not f then return end
    local parts = { frame = f, scroll = f.scroll, content = f.content, empty = f.empty, grip = f.grip,
        minBtn = f.minBtn, rows = type(f.rows) == "table" and f.rows or {}, art = {} }
    for _, region in ipairs({ f:GetRegions() }) do
        if region:GetObjectType() == "Texture" then parts.art[#parts.art + 1] = region end
    end
    for _, child in ipairs({ f:GetChildren() }) do
        if child ~= f.scroll and child ~= f.grip and child ~= f.minBtn and child:GetObjectType() == "Button" then
            if math.abs((child:GetWidth() or 0) - 16) < 0.5 then parts.close = child else parts.title = child end
        end
    end
    return parts
end

function A.HasNextWindow()
    return A.Has("NextWindow") == true
end

function A.NextWindowShown()
    local db = _G.Attune_DB
    return type(db) == "table" and db.showNextSteps ~= false
end

-- Writes to Attune's saved variables, the second place where the skin does (the other is Attune_DB.zoom): the
-- option is the only switch Attune offers for that window. Answers the state it left behind.
function A.ToggleNextWindow()
    local db = _G.Attune_DB
    local update = _G.Attune_NextFrameUpdate
    if type(db) ~= "table" or type(update) ~= "function" then return A.NextWindowShown() end
    db.showNextSteps = not A.NextWindowShown()
    pcall(update)
    return A.NextWindowShown()
end

-- Attune's own name for that window, for our tooltip (AceLocale invents missing keys on read: look raw).
function A.NextWindowName()
    local lang = _G.AttuneLang
    local text = type(lang) == "table" and rawget(lang, "NextSteps_TITLE") or nil
    return type(text) == "string" and text ~= "" and text or nil
end

-- A library by name. LibStub is a table with a __call metamethod (not a function), so it is asked through its
-- GetLibrary method; a missing library or LibStub answers nil.
local function Library(name)
    local libStub = _G.LibStub
    if type(libStub) ~= "table" or type(libStub.GetLibrary) ~= "function" then return nil end
    local ok, lib = pcall(libStub.GetLibrary, libStub, name, true)
    if ok and type(lib) == "table" then return lib end
end

-- Attune's config dialog, the route that does not need Attune's broker.
local function ConfigDialog()
    local dialog = Library("AceConfigDialog-3.0")
    if dialog and type(dialog.Open) == "function" then return dialog end
end

-- Attune's LibDataBroker data object. Attune keeps it in a file-local (`local Attune_Broker`), so there is no
-- global of that name to read: the data object is looked up by its name in LibDataBroker, which Attune registers
-- it with when it enables itself (later than login, hence looked at on every use).
function A.Broker()
    local ldb = Library("LibDataBroker-1.1")
    if ldb and type(ldb.GetDataObjectByName) == "function" then
        local ok, broker = pcall(ldb.GetDataObjectByName, ldb, "Attune_Broker")
        if ok and type(broker) == "table" and type(broker.OnClick) == "function" then return broker end
    end
end

-- Is there any way to open Attune's options? The broker is the complete one, the config dialog the fallback, and
-- either is enough for the button to make sense.
function A.CanOpenAttuneOptions()
    return A.Broker() ~= nil or ConfigDialog() ~= nil
end

-- Attune's own options, opened the way Attune's minimap button does it on a right click. Attune keeps the settings
-- category id in a local, so its own handler is the only complete route; the config dialog is the fallback.
function A.OpenAttuneOptions()
    local broker = A.Broker()
    if broker and pcall(broker.OnClick, broker, "RightButton") then return true end
    local dialog = ConfigDialog()
    if dialog then return pcall(dialog.Open, dialog, "Attune") and true or false end
    return false
end

-- Attune's own close logic (closes the survey menu, saves the list state), as its close button does.
function A.CloseWindow()
    local chrome = A.Chrome()
    if chrome and A.ClickButton(chrome.CloseButton) then return true end
    local main = A.MainFrame()
    if main then
        main:Hide()
        return true
    end
    return false
end

function A.StartMoving()
    local main = A.MainFrame()
    if main and main:IsMovable() then main:StartMoving() end
end

-- Stops moving and stores the position the way Attune's title bar does (AceGUI status table).
function A.StopMoving()
    local main, widget = A.MainFrame(), A.MainWidget()
    if not main then return end
    main:StopMovingOrSizing()
    local status = widget and (widget.status or widget.localstatus)
    if type(status) == "table" then
        status.top = main:GetTop()
        status.left = main:GetLeft()
    end
end

-- The list view exists exactly when the TreeGroup is the window's first child.
function A.IsListView()
    return A.Tree() ~= nil
end

-- Switches between the list and the results view through Attune's own results button.
function A.SwitchView(list)
    if A.IsListView() == (list and true or false) then return false end
    return A.ClickButton(A.ResultsButton())
end

-- Attune's own words for the two views, as on its buttons.
function A.ViewNames()
    return Lang("Attunes"), Lang("Results")
end

function A.SurveyName()
    return Lang("Survey")
end

-- Icon view (grid instead of list): a saved option of Attune. Forcing the list uses Attune's own setter.
function A.IconViewActive()
    local db = DB()
    return db ~= nil and db.iconView and true or false
end

-- Attune's icon grid: shown instead of the list buttons while its icon view is on.
function A.IconGridShown()
    local grid = _G.attunelocal_iconView
    return IsFrame(grid) and grid:IsShown() and true or false
end

function A.ForceListView()
    if not A.IconViewActive() then return false end
    local setter = _G.Attune_SetIconView
    if type(setter) ~= "function" then return false end
    setter(false)
    return true
end

-- Attune's list/icon switch above the list. It shows itself again on every list build: hook once, hide on show.
local hideViewToggle = false
local viewToggleHooked = setmetatable({}, { __mode = "k" })

function A.HideViewToggle(hide)
    hideViewToggle = hide and true or false
    local bar = A.ViewToggle()
    if not IsFrame(bar) then return end
    if hideViewToggle then
        if not viewToggleHooked[bar] then
            viewToggleHooked[bar] = true
            A.HookScript(bar, "OnShow", function(self)
                if hideViewToggle then self:Hide() end
            end, "tree")
        end
        bar:Hide()
    else
        bar:Show()
    end
end

---------------------------------------------------------------------------
-- Chain graph: geometry, card parts, lines, header, scroll
---------------------------------------------------------------------------

-- Attune's layout constants (locals in Attune, catalogue §5). Units are those of the chain root (zoom 1).
A.GRAPH = {
    nodeWidth = 170, nodeHeight = 48, hGap = 10, vGap = 30, iconSize = 32, lineThickness = 6,
    sidePad = 10, sideGap = 8, sideBoxGap = 28,
}

-- Opacity Attune gives its faint dungeon picture behind the chain.
A.DUNGEON_ART_ALPHA = 0.08

function A.NodeWidth(step)
    if type(step) == "table" and step.HALFSIZE then return (A.GRAPH.nodeWidth - A.GRAPH.hGap) / 2 end
    return A.GRAPH.nodeWidth
end

-- The icon Attune puts on a card (the end card shows the attunement's own icon).
function A.StepIcon(step)
    if type(step) ~= "table" then return nil end
    if A.TypeKey(step) == "end" then
        local a = A.AttuneById(step.ID_ATTUNE)
        if a and a.ICON then return a.ICON end
    end
    return step.ICON
end

-- Position of a card relative to the chain root's top centre: x, y (y <= 0).
function A.NodePosition(node)
    if not IsFrame(node) then return nil end
    local _, _, _, x, y = node:GetPoint(1)
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    return x, y
end

-- Attune's guild badge on a card: count text and kind ("here" = others on this step, "done" = others attuned), or nil.
function A.NodeBadge(parts, step)
    local notif, text = parts and parts.notif, parts and parts.notifText
    if not IsFrame(notif) or not notif:IsShown() then return nil end
    local count = text and type(text.GetText) == "function" and text:GetText() or nil
    count = Plain(count)
    if count == nil or count == "" then return nil end
    local kind = A.TypeKey(step) == "end" and "done" or "here"
    local normal = type(notif.GetNormalTexture) == "function" and notif:GetNormalTexture() or nil
    local file = normal and type(normal.GetTexture) == "function" and normal:GetTexture() or nil
    if type(file) == "string" then
        file = file:lower()
        if file:find("completion", 1, true) then kind = "done" elseif file:find("notification", 1, true) then kind = "here" end
    end
    return tostring(count), kind
end

-- Incoming connectors of a card, one entry per predecessor: { line1, line2, line3, dx, dy } where dx/dy is the
-- predecessor's position minus this card's (chain units). Only connectors Attune shows (End <- inside steps use the
-- side feeder instead).
function A.IncomingLines(step, node)
    local list = {}
    if type(step) ~= "table" or step.ID == nil then return list end
    local follows = tostring(step.FOLLOWS or "0")
    if follows == "0" then return list end
    local id = tostring(step.ID)
    local curX, curY = A.NodePosition(node)
    if not curX then return list end
    for from in follows:gmatch("[^&|]+") do
        local l1, l2, l3 = _G["Attune_Line1_" .. id .. "_" .. from], _G["Attune_Line2_" .. id .. "_" .. from],
            _G["Attune_Line3_" .. id .. "_" .. from]
        local px, py = A.NodePosition(_G["Attune_Node_" .. from])
        if px and IsFrame(l1) and IsFrame(l2) and IsFrame(l3) and l1:IsShown() then
            list[#list + 1] = { line1 = l1, line2 = l2, line3 = l3, dx = px - curX, dy = py - curY, from = from }
        end
    end
    return list
end

function A.SpacerFill(step)
    local line = type(step) == "table" and _G["Attune_SpacerFill_" .. tostring(step.ID)] or nil
    return IsFrame(line) and line:IsShown() and line or nil
end

function A.SideFeeder(step)
    local line = type(step) == "table" and _G["Attune_SideFeeder_" .. tostring(step.ID)] or nil
    return IsFrame(line) and line:IsShown() and line or nil
end

-- Attune's chain header: pooled AceGUI labels at the top of the chain scroll, then the "mask" group that sizes the
-- scroll area. { scroll, group (title group), title (label), desc (label), labels = { every header widget }, mask }.
function A.ChainHeader()
    local scroll = A.GraphScroll()
    if not scroll then return nil end
    local kids = type(scroll.children) == "table" and scroll.children or {}
    local h = { scroll = scroll, labels = {} }
    for i, w in ipairs(kids) do
        if type(w) == "table" then
            local first = type(w.children) == "table" and w.children[1] or nil
            if w.type == "SimpleGroup" and i == #kids and i > 1 then
                h.mask = w
            elseif w.type == "SimpleGroup" and type(first) == "table" and first.type == "Label" and not h.group then
                h.group, h.title = w, first
                h.labels[#h.labels + 1] = w
            elseif w.type == "Label" then
                h.labels[#h.labels + 1] = w
                local fs = w.label
                local text = fs and type(fs.GetText) == "function" and fs:GetText() or nil
                if h.group and not h.desc and type(text) == "string" and text:find("%S") then h.desc = w end
            end
        end
    end
    return h
end

-- Attune's "Work in progress" note over an empty chain (anonymous frame with a .text font string).
function A.WorkInProgress()
    local scroll = A.GraphScroll()
    local frame = scroll and scroll.frame
    if not IsFrame(frame) then return nil end
    for _, child in ipairs({ frame:GetChildren() }) do
        local text = child.obj == nil and child.text or nil
        if type(text) == "table" and type(text.GetObjectType) == "function" and text:GetObjectType() == "FontString" then
            return child
        end
    end
    return nil
end

-- Current chain zoom (the root's scale; Attune keeps it in Attune_DB.zoom).
function A.Zoom()
    local root = A.GraphRoot()
    local zoom = root and root:GetScale() or A.StoredZoom() or 1
    if type(zoom) ~= "number" or zoom < 0.01 then zoom = 1 end
    return zoom
end

-- Header height in scroll-content units. Set by the skin when its own chain header replaces Attune's labels;
-- nil leaves Attune's own layout alone. Anchor offsets are in the scaled root's space, hence the division by zoom
-- (as Attune does since 16001-33).
local graphHeader, graphHeight

function A.SetGraphHeader(height)
    graphHeader = type(height) == "number" and height > 0 and height or nil
    A.PlaceGraph()
end

function A.GraphHeader()
    return graphHeader
end

-- Re-anchors the chain root below our header, keeping Attune's horizontal pan.
function A.PlaceGraph()
    local root = A.GraphRoot()
    if not root or not graphHeader or root:GetNumPoints() < 1 then return end
    local point, relative, relativePoint, x = root:GetPoint(1)
    if point ~= "TOP" or not IsFrame(relative) then return end
    root:ClearAllPoints()
    root:SetPoint("TOP", relative, relativePoint or "TOP", type(x) == "number" and x or 0, -graphHeader / A.Zoom())
end

-- Unscaled chain height, read from Attune's mask right after a build (mask = height * zoom + 50).
local function NoteGraphHeight()
    local h = A.ChainHeader()
    local mask = h and h.mask
    if not mask or type(mask.frame) ~= "table" then
        graphHeight = nil
        return
    end
    local zoom = A.StoredZoom() or 1
    graphHeight = math.max(0, ((mask.frame:GetHeight() or 50) - 50) / (zoom > 0 and zoom or 1))
end

function A.GraphHeight()
    return graphHeight
end

-- Makes the scroll area as tall as our header plus the zoomed chain (Attune sizes it for its own header and does
-- not resize it on a live zoom).
local function LabelStack(h)
    local stack = 0
    for _, w in ipairs(h.labels) do
        if type(w.frame) == "table" then stack = stack + (w.frame:GetHeight() or 0) end
    end
    return stack
end

function A.FitGraphContent()
    local h = A.ChainHeader()
    if not h or not h.mask or not graphHeight then return false end
    local stack = LabelStack(h)
    local header = graphHeader or stack + 8
    local need = header + graphHeight * A.Zoom() + 50 - stack
    if type(h.mask.SetHeight) ~= "function" or type(h.scroll.DoLayout) ~= "function" then return false end
    h.mask:SetHeight(math.max(1, need))
    h.scroll:DoLayout()
    return true
end

-- Vertical scroll of the chain: offset, visible height, content height (scroll-content units), bar shown.
function A.GraphScrollState()
    local scroll = A.GraphScroll()
    if not scroll or not IsFrame(scroll.scrollframe) or not IsFrame(scroll.content) then return nil end
    local status = scroll.status or scroll.localstatus or {}
    return tonumber(status.offset) or 0, scroll.scrollframe:GetHeight() or 0, scroll.content:GetHeight() or 0,
        scroll.scrollBarShown and true or false
end

function A.ScrollGraphTo(offset)
    local scroll = A.GraphScroll()
    local _, view, content, shown = A.GraphScrollState()
    if not shown or type(offset) ~= "number" or not IsFrame(scroll.scrollbar) then return false end
    local range = content - view
    if range <= 0 then return false end
    offset = math.max(0, math.min(range, offset))
    scroll.scrollbar:SetValue(offset / range * 1000)
    return true
end

-- Half the width the open chain needs (chain units): widest card edge or the inside box, measured from the centre.
function A.ChainExtent()
    local extent = 0
    for _, item in ipairs(A.ShownNodes()) do
        local x = A.NodePosition(item.node)
        if x then extent = math.max(extent, math.abs(x) + A.NodeWidth(item.step) / 2) end
    end
    local box = A.SideBox()
    if box and box:IsShown() then
        local x = A.NodePosition(box)
        if x then extent = math.max(extent, math.abs(x) + (box:GetWidth() or 0) / 2) end
    end
    return extent
end

-- Lowest card edge of the open chain or of the inside box (chain units below the chain's top). Attune's own chain
-- height adds a spacer below the end card; fitting uses this instead.
function A.ChainBottom()
    local bottom = 0
    for _, item in ipairs(A.ShownNodes()) do
        local _, y = A.NodePosition(item.node)
        if y then bottom = math.max(bottom, -y + (item.node:GetHeight() or A.GRAPH.nodeHeight)) end
    end
    local box = A.SideBox()
    if box and box:IsShown() then
        local _, y = A.NodePosition(box)
        if y then bottom = math.max(bottom, -y + (box:GetHeight() or 0)) end
    end
    return bottom
end

-- Where the chain starts in the scroll content (unscaled): below our header, else below Attune's labels.
function A.GraphTop()
    if graphHeader then return graphHeader end
    local h = A.ChainHeader()
    return h and LabelStack(h) + 8 or 0
end

-- Visible width and height of the chain area (scroll-content units).
function A.GraphViewWidth()
    local scroll = A.GraphScroll()
    return scroll and IsFrame(scroll.scrollframe) and scroll.scrollframe:GetWidth() or nil
end

function A.GraphViewHeight()
    local scroll = A.GraphScroll()
    return scroll and IsFrame(scroll.scrollframe) and scroll.scrollframe:GetHeight() or nil
end

---------------------------------------------------------------------------
-- List rows: what the skin needs to draw one row of Attune's list
---------------------------------------------------------------------------

-- The widget fields of the list the skin styles. nil without the list.
function A.TreeParts(tree)
    tree = tree or A.Tree()
    if not tree then return nil end
    return {
        widget = tree, frame = tree.frame, treeframe = tree.treeframe, border = tree.border, dragger = tree.dragger,
        scrollbar = tree.scrollbar, buttons = type(tree.buttons) == "table" and tree.buttons or {},
    }
end

local function TreeStatus(tree)
    return type(tree) == "table" and (tree.status or tree.localstatus) or nil
end

-- What a shown list button stands for, as plain data:
--   section: { section = true, level, text, expanded, done, total }          (expansion and group rows)
--   leaf:    { level, text, levels, icon, done, dim, progress, selected }    (one attunement)
-- Colour codes of Attune's texts are removed (the skin colours by theme). nil when the button holds no row.
function A.RowInfo(button)
    local line = type(button) == "table" and button.treeline or nil
    if type(line) ~= "table" then return nil end
    local node
    if type(line.tree) == "table" then
        for _, sibling in ipairs(line.tree) do
            if type(sibling) == "table" and sibling.value == line.value then
                node = sibling
                break
            end
        end
    end
    local status = TreeStatus(button.obj)
    local groups = status and status.groups
    local plain = tostring(line.text or "")
    plain = plain:gsub("|c%x%x%x%x%x%x%x%x", "")
    plain = plain:gsub("|r", "")
    local info = {
        level = tonumber(line.level) or 1,
        text = plain,
        selected = button.selected and true or false,
        id = line.value,
    }
    if line.hasChildren then
        info.section = true
        info.expanded = groups and groups[line.uniquevalue] and true or false
        if node and type(node.children) == "table" then
            local done = 0
            for _, child in ipairs(node.children) do
                if type(child) == "table" and child.done then done = done + 1 end
            end
            info.done, info.total = done, #node.children
        end
        return info
    end
    local name, levels = plain:match("^(.-)%s*(%(%d+%s*%-%s*%d+%))$")
    info.text, info.levels = name or plain, levels
    info.icon = node and node.sourceIcon or line.icon
    info.done = node and node.done and true or false
    info.dim = node and node.dim and true or false
    if A.TracksProgress(line.value) then info.progress = A.Progress(line.value) end
    return info
end

---------------------------------------------------------------------------
-- Status mapping: Attune paints its status as colours; we read them back.
-- States: done, ready, locked, key_open, key_done, other_class, spacer, unknown.
---------------------------------------------------------------------------

local NODE_COLORS = {
    { "done", 0.373, 0.729, 0.275 },
    { "ready", 0.851, 0.608, 0.0 },
    { "locked", 0.1, 0.1, 0.1 },
    { "key_open", 0.557, 0.055, 0.075 },
    { "key_done", 0.055, 0.306, 0.576 },
}

local LINE_LAYERS = { [2] = "done", [1] = "ready", [0] = "locked" }

local function Near(a, b)
    return type(a) == "number" and math.abs(a - b) <= TOLERANCE
end

local function NoteUnknown(kind, text)
    local key = kind .. " " .. text
    unknownStates[key] = (unknownStates[key] or 0) + 1
end

function A.UnknownStates()
    local list = {}
    for key, count in pairs(unknownStates) do list[#list + 1] = { key = key, count = count } end
    table.sort(list, function(x, y) return x.key < y.key end)
    return list
end

-- step is optional; without it the step is looked up from the card name in the open chain.
-- Spacer cards never get a backdrop from Attune (no colour to read), so the step type decides first.
function A.NodeState(node, step)
    if not IsFrame(node) then return "unknown" end
    step = step or A.FindStep(A.CurrentAttune(), A.StepIdOfNode(node))
    if step and A.TypeKey(step) == "spacer" then return "spacer" end
    if type(node.GetBackdropColor) ~= "function" then return "unknown" end
    local r, g, b, a = node:GetBackdropColor()
    if type(r) ~= "number" then
        NoteUnknown("card", "no colour")
        return "unknown"
    end
    if type(a) == "number" and a < 0.01 then return "spacer" end
    local state
    for _, entry in ipairs(NODE_COLORS) do
        if Near(r, entry[2]) and Near(g, entry[3]) and Near(b, entry[4]) then
            state = entry[1]
            break
        end
    end
    if not state then
        NoteUnknown("card", ("%.3f %.3f %.3f %.2f"):format(r, g, b, a or 1))
        return "unknown"
    end
    if step and not A.TracksProgress(step.ID_ATTUNE) then return "other_class" end
    return state
end

function A.LineState(line)
    if not IsFrame(line) or type(line.GetDrawLayer) ~= "function" then return "unknown" end
    local layer, sublevel = line:GetDrawLayer()
    local state = layer == "ARTWORK" and LINE_LAYERS[sublevel] or nil
    if state then return state end
    NoteUnknown("line", ("%s %s"):format(tostring(layer), tostring(sublevel)))
    return "unknown"
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

-- Same as typing /attune: opens (building it the first time) or closes Attune's window.
function A.ToggleWindow()
    local handler = _G.Attune_SlashCommandHandler
    if type(handler) ~= "function" then return false end
    handler("")
    return true
end

function A.IsWindowShown()
    local frame = A.MainFrame()
    return frame ~= nil and frame:IsShown()
end

-- Select an attunement in Attune's list (opens the window and the list view if needed).
-- Returns true, or false plus a reason: "no_window", "no_list", "not_in_list".
function A.SelectAttune(id)
    if id == nil then return false, "not_in_list" end
    id = tostring(id)
    if not A.IsWindowShown() then A.ToggleWindow() end
    if not A.IsWindowShown() then return false, "no_window" end
    if not A.Tree() and type(_G.Attune_ToggleView) == "function" then _G.Attune_ToggleView() end
    local tree = A.Tree()
    if not tree or type(tree.SelectByPath) ~= "function" then return false, "no_list" end
    local pathFor = _G.Attune_PathForAttune
    local path = type(pathFor) == "function" and pathFor(id) or nil
    if type(path) ~= "string" then return false, "not_in_list" end
    tree:SelectByPath(strsplit("\001", path))
    return true
end

-- Zoom 0.1-1.5. From 0.5 to 1.0 through Attune's live zoom. Outside that Attune's zoom would clamp: the stored zoom
-- is set and the root scaled the way Attune_ApplyGraphZoom does it (its pan limits read the stored zoom); without the
-- pan function the open chain is rebuilt quietly. Without a chain the stored zoom alone is set (the next build uses
-- it). Returns the zoom that was applied.
function A.ApplyZoom(zoom)
    if type(zoom) ~= "number" then return nil end
    zoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, zoom))
    local db = DB()
    if zoom >= ATTUNE_ZOOM_MIN - 0.0001 and zoom <= ATTUNE_ZOOM_MAX then
        local apply = _G.Attune_ApplyGraphZoom
        if type(apply) == "function" then
            apply(zoom)
            return zoom
        end
        if not db then return nil end
    end
    if not db then return nil end
    db.zoom = zoom
    local root, limits = A.GraphRoot(), _G.Attune_UpdateGraphPanLimits
    if root and A.GraphScroll() then
        if type(limits) == "function" then
            root:SetScale(zoom)
            limits()
        else
            local select, current = _G.Attune_Select, A.CurrentAttune()
            if type(select) == "function" and current then select(current, true) end
        end
    end
    return zoom
end

-- Largest zoom Attune itself allows (1.0); above it the skin scales the chain.
function A.AttuneZoomMax()
    return ATTUNE_ZOOM_MAX
end

-- Zoom range of the skin (Attune's own is 0.5-1.0).
function A.ZoomRange()
    return ZOOM_MIN, ZOOM_MAX
end

---------------------------------------------------------------------------
-- Search: data source, statuses, bringing a card into view
---------------------------------------------------------------------------

-- What the search index depends on; another value means the index is built again (version, language, the options that
-- change what Attune's list shows).
function A.IndexKey()
    local db = DB() or {}
    return table.concat({
        tostring(A.Version()), tostring(type(GetLocale) == "function" and GetLocale() or ""),
        db.showAllClassQuests and "c1" or "c0", db.showDeprecatedAttunes and "d1" or "d0",
        tostring(A.PlayerClass()), tostring(A.PlayerFaction()),
    }, "|")
end

-- Search kind of a step: quest (quest, pick up, turn in), npc (kill, interact), item, other (click, level, reputation,
-- attunement or key). Placeholders and the end card are not searchable.
local SEARCH_KIND = {
    quest = "quest", pickup = "quest", turnin = "quest", item = "item", kill = "npc", interact = "npc",
    click = "other", level = "other", rep = "other", attune = "other",
}

function A.SearchKind(step)
    return SEARCH_KIND[A.TypeKey(step)]
end

-- Name of a step as its card shows it: the localized name for quests, items and NPCs, else the step's own text.
function A.SearchName(step)
    if type(step) ~= "table" then return nil end
    local key = A.TypeKey(step)
    if key == "quest" or key == "pickup" or key == "turnin" or key == "item" or key == "kill" or key == "interact" then
        return A.StepName(step)
    end
    local text = step.STEP
    if type(text) ~= "string" or text == "" then return nil end
    return Lang(text) or text
end

-- Wowhead ids behind a step (quest, NPC or item ids; "a|b" holds several) as strings. Level and reputation steps carry
-- no id worth searching.
function A.SearchIds(step)
    local kind = A.SearchKind(step)
    local ids = {}
    if kind == "other" or kind == nil or step.ID_WOWHEAD == nil then return ids end
    for part in tostring(step.ID_WOWHEAD):gmatch("%d+") do ids[#ids + 1] = part end
    return ids
end

-- The attunements the list shows (its scope) with their searchable steps: { { attune = a, steps = { step, ... } }, ... },
-- ordered by attunement id.
function A.SearchSource()
    local list = {}
    for _, a in pairs(A.Attunes()) do
        if A.IsVisibleInList(a) then
            local steps = {}
            for _, step in ipairs(A.StepsOf(a.ID)) do
                if A.SearchKind(step) and A.IsStepVisible(step) then steps[#steps + 1] = step end
            end
            list[#list + 1] = { attune = a, steps = steps }
        end
    end
    table.sort(list, function(x, y)
        return (tonumber(x.attune.ID) or 0) < (tonumber(y.attune.ID) or 0)
    end)
    return list
end

-- First number of an attunement's level range ("23-26"), for ordering.
function A.AttuneLevel(a)
    local first = type(a) == "table" and tostring(a.LEVELS or ""):match("%d+")
    return tonumber(first) or 999
end

-- "done", "active" or "open" for one attunement of this character (a class quest of another class counts as open).
function A.AttuneStatus(id)
    if not A.TracksProgress(id) then return "open" end
    local progress = A.Progress(id)
    if progress == nil or progress <= 0 then return "open" end
    if progress >= 100 then return "done" end
    return "active"
end

-- "done", "active" (a quest in the log) or "open" for one step.
function A.StepStatus(attuneId, step)
    if type(step) ~= "table" then return "open" end
    if A.IsStepDone(attuneId, step.ID) then return "done" end
    if A.SearchKind(step) == "quest" then
        for _, id in ipairs(A.SearchIds(step)) do
            if A.IsQuestActive(id) then return "active" end
        end
    end
    return "open"
end

-- Scrolls the open chain so that the card sits in the middle of the view; returns the card (nil without it). Attune's
-- horizontal pan cannot be set (it is local to Attune); NodeSide tells whether the card is out of view sideways.
function A.RevealNode(stepId)
    local node = A.Node(stepId)
    if not node then return nil end
    local _, y = A.NodePosition(node)
    if not y then return node end
    local _, view = A.GraphScrollState()
    local middle = A.GraphTop() + (-y + (node:GetHeight() or A.GRAPH.nodeHeight) / 2) * A.Zoom()
    A.ScrollGraphTo(middle - (view or 0) / 2)
    return node
end

-- "left" or "right" when the card lies completely outside the chain view sideways, else nil. Screen positions, each
-- scaled by its own effective scale.
function A.NodeSide(node)
    local scroll = A.GraphScroll()
    local view = scroll and scroll.scrollframe
    if not IsFrame(view) or not IsFrame(node) then return nil end
    local nl, nr, vl, vr = node:GetLeft(), node:GetRight(), view:GetLeft(), view:GetRight()
    if not (nl and nr and vl and vr) then return nil end
    local ns, vs = node:GetEffectiveScale() or 1, view:GetEffectiveScale() or 1
    nl, nr, vl, vr = nl * ns, nr * ns, vl * vs, vr * vs
    if nr <= vl then return "left" end
    if nl >= vr then return "right" end
    return nil
end

---------------------------------------------------------------------------
-- Quest details, reward window, results table: the parts the skin restyles
---------------------------------------------------------------------------

-- The quest detail panel and its parts, or nil without it. Attune's panel is one named frame that lives for good; the
-- close button and the two map zoom buttons are locals of Attune, found among the children.
-- { panel, title, subtitle, close, scroll, child, xp, empty, separator, map, giver, rows, headers, zoomButtons = { {
--   button, kind = "plus"|"minus" } } }
function A.DetailParts()
    local panel = A.QuestDetail()
    if not panel or type(panel.title) ~= "table" or not IsFrame(panel.map) then return nil end
    local close
    for _, child in ipairs({ panel:GetChildren() }) do
        if child:GetObjectType() == "Button" then
            close = child
            break
        end
    end
    local zoomButtons = {}
    for _, child in ipairs({ panel.map:GetChildren() }) do
        if child:GetObjectType() == "Button" then
            local text = child:GetText()
            zoomButtons[#zoomButtons + 1] = { button = child, kind = text == "+" and "plus" or "minus" }
        end
    end
    return {
        panel = panel, title = panel.title, subtitle = panel.subtitle, close = close, scroll = panel.rewardScroll,
        child = panel.rewardChild, xp = panel.xpText, empty = panel.empty, separator = panel.separator, map = panel.map,
        giver = panel.giver, rows = type(panel.rows) == "table" and panel.rows or {},
        headers = type(panel.headers) == "table" and panel.headers or {}, zoomButtons = zoomButtons,
    }
end

-- The reward window beside Attune's window (Attune 16001-34 no longer opens it, the hook point stays for older and later
-- versions) or nil. { frame, title, link, empty, scroll, content, rows, headers, chrome, close }
function A.RewardParts()
    local frame = A.RewardFrame()
    if not frame then return nil end
    local close
    for _, child in ipairs({ frame:GetChildren() }) do
        if child:GetObjectType() == "Button" and child ~= frame.urlBtn then
            close = child
            break
        end
    end
    return {
        frame = frame, title = frame.title, link = frame.urlBtn, empty = frame.empty, scroll = frame.scroll,
        content = frame.content, rows = type(frame.rows) == "table" and frame.rows or {},
        headers = type(frame.headers) == "table" and frame.headers or {}, chrome = frame.bronze, close = close,
    }
end

-- Height of one row of the results table (Attune's own number).
function A.ResultRowHeight()
    local height = _G.Attune_ResultRowHeight
    if type(height) == "function" then
        local ok, value = pcall(height)
        if ok and type(value) == "number" then return value end
    end
    return 26
end

-- The frames of the results table that Attune keeps for good: { holder, headerBg, nameShade, divider, headerLine, vbar,
-- hbar, nameContent, bodyContent, headerContent, nameHead } or nil before the first results view. nameHead is the corner
-- above the name column that carries the column heads (Level, Class, Characters).
function A.ResultParts()
    local holder = _G.attunelocal_resultHolder
    if not IsFrame(holder) then return nil end
    return {
        holder = holder, headerBg = holder.headerBg, nameShade = holder.nameShade, divider = holder.divider,
        headerLine = holder.headerLine, vbar = holder.vbar, hbar = holder.hbar, nameContent = holder.nameContent,
        bodyContent = holder.bodyContent, headerContent = holder.headerContent, nameHead = holder.nameHead,
    }
end

-- The AceGUI container Attune mounted into a scroll child of the table (the last shown one; a released one is hidden).
local function MountedWidget(content)
    if not IsFrame(content) then return nil end
    local found
    for _, child in ipairs({ content:GetChildren() }) do
        local widget = child.obj
        if type(widget) == "table" and widget.frame == child and child:IsShown() and type(widget.children) == "table" then
            found = widget
        end
    end
    return found
end

-- The pooled containers of the table: { heads = the column heads over the names (Level, Class, Characters), header = the
-- attunement icons over the cells, names = group of the name rows, body = group of the cell rows } (any may be missing).
-- Rows are appended at the end while Attune builds them one by one.
function A.ResultTable()
    local p = A.ResultParts()
    if not p then return {} end
    return { heads = MountedWidget(p.nameHead), header = MountedWidget(p.headerContent),
        names = MountedWidget(p.nameContent), body = MountedWidget(p.bodyContent) }
end

-- The text widgets (Label, InteractiveLabel) inside a pooled container, depth first; fn(widget) for each.
function A.EachLabel(container, fn)
    if type(container) ~= "table" or type(container.children) ~= "table" then return end
    for _, child in ipairs(container.children) do
        if type(child) == "table" then
            if (child.type == "Label" or child.type == "InteractiveLabel") and type(child.label) == "table" then
                fn(child)
            elseif type(child.children) == "table" then
                A.EachLabel(child, fn)
            end
        end
    end
end

-- The pooled controls above the table in the results view: { title = Label, radios = { CheckBox ... }, slider = Slider }
-- (any may be missing).
function A.ResultControls()
    local controls = { radios = {} }
    local group = A.ResultsGroup()
    for _, child in ipairs(group and type(group.children) == "table" and group.children or {}) do
        if type(child) == "table" and child.type == "SimpleGroup" then
            for _, widget in ipairs(type(child.children) == "table" and child.children or {}) do
                if type(widget) == "table" then
                    if widget.type == "CheckBox" then
                        controls.radios[#controls.radios + 1] = widget
                    elseif widget.type == "Slider" then
                        controls.slider = widget
                    elseif widget.type == "Label" and not controls.title then
                        controls.title = widget
                    end
                end
            end
        end
    end
    return controls
end

---------------------------------------------------------------------------
-- Adapter hooks: notice the first window, the open chain and view changes
---------------------------------------------------------------------------

ns.Modules.Register("adapter", {
    requires = { "Frame", "ToggleView", "Select" },
    Enable = function()
        A.On("window", function()
            windowSeen = true
            ns.Modules.CheckAll()
        end, "adapter")
        A.On("select", function(attuneId)
            if attuneId ~= nil then currentAttune = tostring(attuneId) end
            NoteGraphHeight()
        end, "adapter")
        -- Attune re-anchors the chain on every pan, zoom and resize: keep it below our header
        A.On("pan", function() A.PlaceGraph() end, "adapter")
        A.On("view", function()
            ns.Modules.CheckAll()
        end, "adapter")
        -- Attune's window may already exist (module enabled late): pick it up now.
        if A.MainFrame() then windowSeen = true end
    end,
})
