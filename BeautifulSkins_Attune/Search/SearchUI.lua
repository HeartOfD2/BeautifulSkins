-- Search: a field in a strip above Attune's list, a result overlay under it (filter chips, "only open", groups, rows with
-- the match highlighted and a status dot), keyboard control, the jump to a hit (list selection, chain build, vertical
-- scroll, pulse, edge arrow) and the marking of matching cards in the open chain. All frames are ours; Attune's list
-- widget is only used as an anchor, and Attune's own functions are reached through ns.Attune. The data side is
-- Search/Index.lua.
local _, ns = ...
local L, A, Theme, Kit, Skin, Search = ns.L, ns.Attune, ns.Theme, ns.Kit, ns.Skin, ns.Search
local Paint, Bind, Refresh = Theme.Paint, Theme.Bind, Theme.Refresh

local BORDER, HEADER_H, STATUS_H = 1, 40, 24 -- the window's measures (Skin/Window.lua)
local ROOM, COLUMN_FALLBACK = 44, 265        -- strip height; list column width without a list
local ROW_H, GROUP_H, MORE_H, CHIP_H, PAD = 36, 24, 24, 22, 8
local OVERLAY_MIN, OVERLAY_MAX = 380, 560
local PULSE_SECONDS, NOTE_SECONDS = 3, 4

local searchOn = false
local W                                                   -- our frames, built once
local S = { q = Search.Parse(""), flat = {}, sel = nil, open = false, expanded = {}, token = 0 }
local marks = setmetatable({}, { __mode = "k" })          -- card -> mark frame
local stats = { renders = 0, renderMs = 0, maxRenderMs = 0, marked = 0, dimmed = 0, jumps = 0 }

local Render, CloseOverlay, Choose, ApplyMarks

local function Cfg()
    local settings = ns.db and ns.db.settings
    local cfg = settings and settings.search
    if type(cfg) ~= "table" then return { filter = "all", onlyOpen = false, mark = true } end
    return cfg
end

local function Clock()
    return type(debugprofilestop) == "function" and debugprofilestop() or nil
end

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------

local function FilterLabel(key)
    if key == "attune" then return L["Attunements"] end
    if key == "quest" then return L["Quests"] end
    if key == "npc" then return L["NPCs"] end
    if key == "item" then return L["Items"] end
    if key == "zone" then return L["Zones"] end
    return L["All"]
end

local function GroupLabel(kind)
    if kind == "attune" then return L["Attunements & dungeons"] end
    if kind == "quest" then return L["Quests"] end
    if kind == "npc" then return L["NPCs"] end
    if kind == "item" then return L["Items"] end
    if kind == "zone" then return L["Zones"] end
    return L["Other steps"]
end

-- "Type · Attunement · Zone" for a step, level and group size for an attunement.
local function Context(e)
    local a = e.attune
    if e.kind == "attune" then
        local parts = {}
        if type(a.LEVELS) == "string" and a.LEVELS ~= "" then parts[#parts + 1] = L["Level %s"]:format(a.LEVELS) end
        local size = tonumber(a.GROUPSIZE)
        if size then parts[#parts + 1] = L["%d players"]:format(size) end
        -- the short code ("BRD", "Strat") is searchable, so it is shown as well
        if type(a.SHORT) == "string" and a.SHORT ~= "" and Search.Normalize(a.SHORT) ~= Search.Normalize(e.name) then
            parts[#parts + 1] = a.SHORT
        end
        return table.concat(parts, " · ")
    end
    if e.kind == "zone" then
        return L["Zone"] .. " · " .. (A.AttuneName(a) or "") .. " · " .. L["%d steps"]:format(#e.stepIds)
    end
    local word = Skin.TypeWord and Skin.TypeWord(e.step) or A.TypeName(e.step) or ""
    local parts = { word, A.AttuneName(a) or "" }
    local zone = e.kind ~= "other" and A.ZoneName(e.step) or nil
    if zone and zone ~= "" then parts[#parts + 1] = zone end
    return table.concat(parts, " · ")
end

local function Note(text)
    if not W then return end
    W.note:SetText(text or "")
    W.note:SetShown(text ~= nil)
    S.token = S.token + 1
    local token = S.token
    if text and C_Timer then
        C_Timer.After(NOTE_SECONDS, function()
            if S.token == token and W then W.note:SetShown(false) end
        end)
    end
end

---------------------------------------------------------------------------
-- Pulse and edge arrow
---------------------------------------------------------------------------

local pulseToken = 0

local function StopPulse()
    pulseToken = pulseToken + 1
    if not W then return end
    W.pulse.anim:Stop()
    W.pulse:Hide()
    W.pulse:SetParent(W.host)
    W.arrow.anim:Stop()
    W.arrow:Hide()
end

-- Edge width of a frame that sits in the zoomed chain: whole screen pixels at any zoom.
local function SizeEdges(frame, pixels)
    local edge = pixels * Skin.Density() * Skin.Pixel(frame)
    frame.edges[1]:SetHeight(edge); frame.edges[2]:SetHeight(edge)
    frame.edges[3]:SetWidth(edge); frame.edges[4]:SetWidth(edge)
    return edge
end

-- A frame in the accent around a card that blinks for a few seconds.
local function Pulse(node)
    local p = W.pulse
    local same = p:GetParent() == node and p:IsShown()
    pulseToken = pulseToken + 1
    local token = pulseToken
    p:SetParent(node)
    local unit = SizeEdges(p, 1)
    SizeEdges(p, 2)
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", node, "TOPLEFT", -3 * unit, 3 * unit)
    p:SetPoint("BOTTOMRIGHT", node, "BOTTOMRIGHT", 3 * unit, -3 * unit)
    p:SetFrameStrata(node:GetFrameStrata())
    p:SetFrameLevel(node:GetFrameLevel() + 30)
    p:Show()
    if not same then p.anim:Play() end
    if C_Timer then
        C_Timer.After(PULSE_SECONDS, function()
            if pulseToken == token and W then StopPulse() end
        end)
    end
end

-- Arrow at the edge of the chain view pointing to a card that lies outside it sideways.
local function ShowArrow(side)
    local scroll = A.GraphScroll()
    local view = scroll and scroll.scrollframe
    local arrow = W.arrow
    if not side or not view then
        arrow:Hide()
        return
    end
    arrow:ClearAllPoints()
    if side == "left" then
        arrow:SetPoint("LEFT", view, "LEFT", 8, 0)
    else
        arrow:SetPoint("RIGHT", view, "RIGHT", -28, 0)
    end
    arrow.glyph:SetKind(side)
    arrow:SetFrameStrata(scroll.frame:GetFrameStrata())
    arrow:SetFrameLevel(scroll.content:GetFrameLevel() + 70)
    arrow:Show()
    arrow.anim:Play()
end

---------------------------------------------------------------------------
-- Jump to a hit
---------------------------------------------------------------------------

-- Brings the hit's card into view and lets it pulse. final = last attempt: the edge arrow decides then.
local function RevealEntry(entry, final)
    if entry.kind == "attune" or entry.sid == "" then return end
    if A.CurrentAttune() ~= entry.aid then return end
    local node = A.RevealNode(entry.sid)
    if not node or not node:IsShown() then return end
    Pulse(node)
    if final then ShowArrow(A.NodeSide(node)) end
end

local function Jump(entry)
    stats.jumps = stats.jumps + 1
    StopPulse()
    local ok, reason = A.SelectAttune(entry.aid)
    if not ok then
        Note(reason == "not_in_list" and L["This entry is not in Attune's list."] or L["Attune's window is not available."])
        return
    end
    Note(nil)
    S.reveal = entry
    RevealEntry(entry, false)
    if C_Timer then
        -- the scroll area learns its new height a frame later
        C_Timer.After(0, function()
            if S.reveal == entry then ns.Modules.Run("search", RevealEntry, entry, false) end
        end)
        C_Timer.After(0.3, function()
            if S.reveal == entry then
                ns.Modules.Run("search", RevealEntry, entry, true)
                S.reveal = nil
            end
        end)
    end
end

function Choose(item)
    if not item or not item.entry then return end
    local entry = item.entry
    CloseOverlay()
    W.field.edit:ClearFocus()
    Jump(entry)
end

---------------------------------------------------------------------------
-- Marking cards of the open chain
---------------------------------------------------------------------------

local function MarkFrame(node)
    local m = marks[node]
    if m then return m end
    m = Skin.Mine(CreateFrame("Frame", nil, node))
    m:SetAllPoints(node)
    m.dim = m:CreateTexture(nil, "OVERLAY", nil, 2)
    m.dim:SetAllPoints()
    m.edges = {}
    for i = 1, 4 do
        m.edges[i] = m:CreateTexture(nil, "OVERLAY", nil, 3)
        Theme.Crisp(m.edges[i])
    end
    m.edges[1]:SetPoint("TOPLEFT"); m.edges[1]:SetPoint("TOPRIGHT")
    m.edges[2]:SetPoint("BOTTOMLEFT"); m.edges[2]:SetPoint("BOTTOMRIGHT")
    m.edges[3]:SetPoint("TOPLEFT"); m.edges[3]:SetPoint("BOTTOMLEFT")
    m.edges[4]:SetPoint("TOPRIGHT"); m.edges[4]:SetPoint("BOTTOMRIGHT")
    Bind(m, function(self, T)
        Paint(self.dim, Skin.With(T.canvasBg, 0.62))
        for _, edge in ipairs(self.edges) do Paint(edge, T.accent) end
    end)
    marks[node] = m
    return m
end

local function ClearMarks()
    for _, m in pairs(marks) do m:Hide() end
    stats.marked, stats.dimmed = 0, 0
end

-- While a search is active the matching cards get an accent frame and the others a veil. A chain without any match is
-- left alone.
function ApplyMarks()
    ClearMarks()
    if not searchOn or not S.q.active or Cfg().mark == false or not A.IsListView() then return end
    local attuneId = A.CurrentAttune()
    if not attuneId then return end
    local filter = Cfg().filter
    local shown, hits = {}, 0
    for _, item in ipairs(A.ShownNodes()) do
        if A.TypeKey(item.step) ~= "spacer" then
            local hit = Search.StepMatches(attuneId, item.step, S.q, filter)
            shown[#shown + 1] = { node = item.node, hit = hit }
            if hit then hits = hits + 1 end
        end
    end
    if hits == 0 then return end
    for _, item in ipairs(shown) do
        local m = MarkFrame(item.node)
        m:SetFrameStrata(item.node:GetFrameStrata())
        m:SetFrameLevel(item.node:GetFrameLevel() + 25)
        m.dim:SetShown(not item.hit)
        for _, edge in ipairs(m.edges) do edge:SetShown(item.hit) end
        SizeEdges(m, 2)
        m:Show()
    end
    stats.marked, stats.dimmed = hits, #shown - hits
end

-- The chain was zoomed: the accent frames keep their weight in screen pixels.
function Skin.SearchResize()
    if not W or not searchOn then return end
    for _, m in pairs(marks) do
        if m:IsShown() then SizeEdges(m, 2) end
    end
    if W.pulse:IsShown() then SizeEdges(W.pulse, 2) end
end

---------------------------------------------------------------------------
-- Result overlay: rows, group heads, "more" rows
---------------------------------------------------------------------------

local function StatusColor(status, T)
    if status == "done" then return T.success end
    if status == "active" then
        local s = Theme.Status("ready")
        return s.stripe or T[s.stripeKey or ""] or T.accent
    end
    return Skin.With(T.textDim, 0.5)
end

local function NewRow(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(ROW_H)
    b.sel = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.sel:SetAllPoints()
    b.bar = b:CreateTexture(nil, "BACKGROUND", nil, 2)
    b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT")
    b.bar:SetWidth(2)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(24, 24)
    b.icon:SetPoint("LEFT", b, "LEFT", 10, 0)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.dot = b:CreateTexture(nil, "ARTWORK")
    b.dot:SetSize(8, 8)
    b.dot:SetPoint("RIGHT", b, "RIGHT", -12, 0)
    b.name = Kit.Text(b, 12, "text")
    b.name:SetPoint("TOPLEFT", b, "TOPLEFT", 42, -6)
    b.name:SetPoint("TOPRIGHT", b, "TOPRIGHT", -28, -6)
    b.name:SetWordWrap(false)
    b.ctx = Kit.Text(b, 10, "textDim")
    b.ctx:SetPoint("TOPLEFT", b, "TOPLEFT", 42, -21)
    b.ctx:SetPoint("TOPRIGHT", b, "TOPRIGHT", -28, -21)
    b.ctx:SetWordWrap(false)
    Bind(b, function(self, T)
        Paint(self.sel, Skin.With(T.accent, 0.12))
        Paint(self.bar, T.accent)
        Paint(self.hl, T.hover)
        Paint(self.dot, StatusColor(self.status, T))
    end)
    b:SetScript("OnClick", function(self) Choose(self.item) end)
    return b
end

local function NewHead(parent)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(GROUP_H)
    h.label = Kit.Text(h, 11, "header")
    h.label:SetPoint("LEFT", h, "LEFT", 10, 0)
    h.count = Kit.Text(h, 10, "textDim")
    h.count:SetPoint("RIGHT", h, "RIGHT", -12, 0)
    h.count:SetJustifyH("RIGHT")
    h.line = Kit.Divider(h)
    h.line:SetPoint("BOTTOMLEFT")
    h.line:SetPoint("BOTTOMRIGHT")
    return h
end

local function NewMore(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(MORE_H)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.label = Kit.Text(b, 11, "accent")
    b.label:SetPoint("LEFT", b, "LEFT", 42, 0)
    Bind(b, function(self, T) Paint(self.hl, T.hover) end)
    b:SetScript("OnClick", function(self)
        S.expanded[self.kind] = true
        Render()
    end)
    return b
end

local function Take(kind, used)
    local n = (used[kind] or 0) + 1
    used[kind] = n
    local list = W.pool[kind]
    local f = list[n]
    if not f then
        f = W.make[kind](W.area.child)
        list[n] = f
    end
    f:Show()
    return f
end

local function Place(frame, y)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", W.area.child, "TOPLEFT", 0, -y)
    frame:SetPoint("TOPRIGHT", W.area.child, "TOPRIGHT", 0, -y)
end

local function FillRow(row, hit, accent)
    local e = hit.entry
    row.item, row.entry, row.status, row.selected = hit, e, hit.status, false
    row.name:SetText(Search.Highlight(e.name, S.q, accent))
    row.ctx:SetText(Context(e))
    local icon = (e.kind == "attune" or e.kind == "zone") and e.attune.ICON or (e.step and A.StepIcon(e.step)) or nil
    if icon then
        row.icon:SetTexture(icon)
        row.icon:Show()
    else
        row.icon:Hide()
    end
    row.sel:Hide()
    row.bar:Hide()
    Refresh(row)
end

local function UpdateSelection()
    for i, row in ipairs(S.flat) do
        local on = i == S.sel
        row.selected = on
        row.sel:SetShown(on)
        row.bar:SetShown(on)
    end
end

-- Scrolls the result list so the selected row is visible.
local function RevealRow()
    local row = S.flat[S.sel]
    if not row or not row.y then return end
    local area = W.area
    local top, bottom = row.y, row.y + ROW_H
    local offset, view = area:GetOffset(), area.scroll:GetHeight() or 0
    if top < offset then
        area:SetOffset(math.max(0, top - GROUP_H))
    elseif bottom > offset + view then
        area:SetOffset(bottom - view)
    end
end

local function SizeOverlay(contentHeight)
    local host = W.host
    local available = math.max(160, (host:GetHeight() or 700) - HEADER_H - ROOM - STATUS_H - 24)
    local height = math.min(available, W.headH + contentHeight + 6)
    local width = math.max(OVERLAY_MIN, math.min(OVERLAY_MAX, W.wantWidth))
    width = math.min(width, math.max(260, (host:GetWidth() or 1200) - PAD * 2))
    W.overlay:SetSize(width, math.max(W.headH + 60, height))
end

function Render()
    if not W or not searchOn then return end
    local start = Clock()
    local cfg = Cfg()
    local result = Search.Run(S.q, { filter = cfg.filter, onlyOpen = cfg.onlyOpen, expanded = S.expanded })
    S.result = result
    local T = Theme.Get()
    local accent = Skin.Hex(T.accent)
    local used, flat, y = {}, {}, 0
    for _, group in ipairs(result.groups) do
        local head = Take("head", used)
        Place(head, y)
        head.label:SetText(GroupLabel(group.kind))
        head.count:SetText(tostring(group.total))
        y = y + GROUP_H
        for _, hit in ipairs(group.items) do
            local row = Take("row", used)
            Place(row, y)
            FillRow(row, hit, accent)
            row.y = y
            y = y + ROW_H
            flat[#flat + 1] = row
        end
        if group.total > #group.items then
            local more = Take("more", used)
            Place(more, y)
            more.kind = group.kind
            more.label:SetText(L["+ %d more …"]:format(group.total - #group.items))
            y = y + MORE_H
        end
    end
    for kind, list in pairs(W.pool) do
        for i = (used[kind] or 0) + 1, #list do list[i]:Hide() end
    end
    W.empty:SetShown(result.total == 0)
    if result.total == 0 then y = 56 end
    W.count:SetText(result.total > 0 and L["%d results"]:format(result.total) or "")
    W.area:SetContentHeight(y)
    W.area:SetOffset(0)
    S.flat, S.sel = flat, #flat > 0 and 1 or nil
    UpdateSelection()
    SizeOverlay(y)
    W.overlay:Show()
    for key, chip in pairs(W.chips) do
        chip.active = key == cfg.filter
        Refresh(chip)
    end
    local stop = Clock()
    stats.renders = stats.renders + 1
    if start and stop then
        stats.renderMs = stop - start
        stats.maxRenderMs = math.max(stats.maxRenderMs, stats.renderMs)
    end
end

function CloseOverlay()
    S.open = false
    if W then W.overlay:Hide() end
end

---------------------------------------------------------------------------
-- The field
---------------------------------------------------------------------------

local function UpdateField()
    local hasText = W.field:GetText() ~= ""
    local cfg = Cfg()
    W.clear:SetShown(hasText)
    local tag = cfg.filter ~= "all" and FilterLabel(cfg.filter) or nil
    W.tag:SetText(tag or "")
    W.tag:SetShown(tag ~= nil)
    local right = 8 + (hasText and 22 or 0)
    W.tag:ClearAllPoints()
    W.tag:SetPoint("RIGHT", W.field, "RIGHT", -right, 0)
    local edit = W.field.edit
    edit:ClearAllPoints()
    edit:SetPoint("TOPLEFT", W.field, "TOPLEFT", 26, 0)
    edit:SetPoint("BOTTOMRIGHT", W.field, "BOTTOMRIGHT", -(right + (tag and (W.tag:GetStringWidth() + 8) or 0)), 0)
end

local function OnChange(text, userInput)
    if not W then return end
    S.q = Search.Parse(text)
    UpdateField()
    if S.q.active then
        if userInput then S.open = true end
        if S.open then Render() end
    else
        CloseOverlay()
    end
    ApplyMarks()
end

local function Clear()
    W.field:SetText("")
    OnChange("", false)
    StopPulse()
    W.field:SetFocus()
end

-- Moves the selection by delta rows; the card of the chosen hit blinks as a preview when it is in the open chain.
local function Move(delta)
    if not S.open or #S.flat == 0 then return end
    local sel = (S.sel or 0) + delta
    S.sel = math.max(1, math.min(#S.flat, sel))
    UpdateSelection()
    RevealRow()
    local entry = S.flat[S.sel].entry
    if entry.kind ~= "attune" and entry.aid == A.CurrentAttune() then
        local node = A.Node(entry.sid)
        if node and node:IsShown() then
            Pulse(node)
            return
        end
    end
    StopPulse()
end

local function SetFilter(key)
    Cfg().filter = key
    UpdateField()
    if S.q.active then
        S.open = true
        Render()
    end
    ApplyMarks()
    if W.field.edit:HasFocus() == false then W.field:SetFocus() end
end

local function SetOnlyOpen(on)
    Cfg().onlyOpen = on and true or false
    if S.q.active then
        S.open = true
        Render()
    end
    if W.field.edit:HasFocus() == false then W.field:SetFocus() end
end

---------------------------------------------------------------------------
-- Building the frames
---------------------------------------------------------------------------

local function NewChip(parent, key)
    local b = CreateFrame("Button", nil, parent)
    b.label = Kit.Text(b, 11, false)
    b.label:SetPoint("CENTER")
    b.label:SetText(FilterLabel(key))
    b:SetSize(math.max(36, b.label:GetStringWidth() + 22), CHIP_H)
    b.pill = Skin.Pill(b)
    b.key = key
    Bind(b, function(self, T)
        local on = self.active
        self.pill:SetColors(on and T.accent or T.inputBg, on and T.accent or (self.hovered and T.textDim or T.border))
        Paint(self.label, on and T.onAccent or (self.hovered and T.text or T.textDim))
    end)
    b:SetScript("OnEnter", function(self) self.hovered = true; Refresh(self) end)
    b:SetScript("OnLeave", function(self) self.hovered = false; Refresh(self) end)
    b:SetScript("OnClick", function() SetFilter(key) end)
    return b
end

local function BuildOverlay(host)
    local o = Skin.Mine(Kit.Panel(host, "popup", "border", "popup"))
    o:SetFrameStrata("DIALOG")
    o:SetFrameLevel(20)
    o:EnableMouse(true)
    o:Hide()
    W.overlay = o
    W.chips = {}
    W.pool = { row = {}, head = {}, more = {} }
    W.make = { row = NewRow, head = NewHead, more = NewMore }

    -- chips in a row, wrapping when the overlay is too narrow; below them the "only open" switch and the hit count
    local x, y, total = PAD, PAD, 0
    local widths = {}
    for _, key in ipairs(Search.FILTERS) do
        local chip = NewChip(o, key)
        W.chips[key] = chip
        widths[#widths + 1] = chip:GetWidth()
        total = total + chip:GetWidth() + 4
    end
    W.wantWidth = math.max(OVERLAY_MIN, math.min(OVERLAY_MAX, total + PAD * 2))
    local limit = W.wantWidth - PAD
    local rowsUsed = 1
    for i, key in ipairs(Search.FILTERS) do
        local chip = W.chips[key]
        if x + widths[i] > limit and x > PAD then
            x, y = PAD, y + CHIP_H + 4
            rowsUsed = rowsUsed + 1
        end
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", o, "TOPLEFT", x, -y)
        x = x + widths[i] + 4
    end
    y = y + CHIP_H + 8
    W.only = Kit.Checkbox(o, L["Only open"], function() return Cfg().onlyOpen and true or false end, SetOnlyOpen, 12)
    W.only:SetPoint("TOPLEFT", o, "TOPLEFT", PAD + 2, -y)
    W.count = Kit.Text(o, 11, "textDim")
    W.count:SetPoint("TOPRIGHT", o, "TOPRIGHT", -(PAD + 4), -(y + 3))
    W.count:SetJustifyH("RIGHT")
    y = y + 24
    W.headH = y
    W.headLine = Kit.Divider(o)
    W.headLine:SetPoint("TOPLEFT", o, "TOPLEFT", 1, -y)
    W.headLine:SetPoint("TOPRIGHT", o, "TOPRIGHT", -1, -y)

    W.area = Kit.ScrollArea(o)
    W.area:SetPoint("TOPLEFT", o, "TOPLEFT", 1, -(y + 1))
    W.area:SetPoint("BOTTOMRIGHT", o, "BOTTOMRIGHT", -1, 1)
    W.empty = Kit.Hint(W.area, L["No results"])
    W.empty:ClearAllPoints()
    W.empty:SetPoint("TOPLEFT", W.area, "TOPLEFT", 12, -20)
    W.empty:SetPoint("TOPRIGHT", W.area, "TOPRIGHT", -12, -20)
    W.empty:Hide()

    -- a click anywhere else closes the overlay (and gives the keyboard back); no blocking of the click itself
    o:SetScript("OnEvent", function()
        if not S.open then return end
        if o:IsMouseOver() or W.cell:IsMouseOver() then return end
        CloseOverlay()
        W.field.edit:ClearFocus()
    end)
    o:SetScript("OnShow", function(self) pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    o:SetScript("OnHide", function(self) pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
end

local function BuildEffects(host)
    local p = Skin.Mine(CreateFrame("Frame", nil, host))
    p.edges = {}
    for i = 1, 4 do
        p.edges[i] = p:CreateTexture(nil, "OVERLAY")
        Theme.Crisp(p.edges[i])
    end
    p.edges[1]:SetPoint("TOPLEFT"); p.edges[1]:SetPoint("TOPRIGHT")
    p.edges[2]:SetPoint("BOTTOMLEFT"); p.edges[2]:SetPoint("BOTTOMRIGHT")
    p.edges[3]:SetPoint("TOPLEFT"); p.edges[3]:SetPoint("BOTTOMLEFT")
    p.edges[4]:SetPoint("TOPRIGHT"); p.edges[4]:SetPoint("BOTTOMRIGHT")
    p.anim = p:CreateAnimationGroup()
    p.anim:SetLooping("BOUNCE")
    local fade = p.anim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.25)
    fade:SetDuration(0.5)
    Bind(p, function(self, T)
        for _, edge in ipairs(self.edges) do Paint(edge, T.accent) end
    end)
    p:Hide()
    W.pulse = p

    local arrow = Skin.Mine(CreateFrame("Button", nil, host))
    arrow:SetSize(30, 30)
    arrow.pill = Skin.Pill(arrow)
    arrow.glyph = Kit.Glyph(arrow, "right", 16, "onAccent")
    arrow.glyph:SetPoint("CENTER")
    arrow.anim = arrow:CreateAnimationGroup()
    arrow.anim:SetLooping("BOUNCE")
    local blink = arrow.anim:CreateAnimation("Alpha")
    blink:SetFromAlpha(1)
    blink:SetToAlpha(0.4)
    blink:SetDuration(0.5)
    Bind(arrow, function(self, T) self.pill:SetColors(T.accent, T.accent) end)
    arrow:SetScript("OnClick", function(self) self:Hide() end)
    arrow:Hide()
    W.arrow = arrow
end

local function Build(host)
    local w = { host = host }
    W = w
    local strip = Skin.Mine(CreateFrame("Frame", nil, host))
    w.strip = strip
    strip:SetPoint("TOPLEFT", host, "TOPLEFT", BORDER, -(BORDER + HEADER_H))
    strip:SetPoint("TOPRIGHT", host, "TOPRIGHT", -BORDER, -(BORDER + HEADER_H))
    strip:SetHeight(ROOM)
    strip:SetFrameLevel(host:GetFrameLevel() + 38)
    strip.line = Kit.Divider(strip)
    strip.line:SetPoint("BOTTOMLEFT")
    strip.line:SetPoint("BOTTOMRIGHT")

    -- the part above the list column
    local cell = CreateFrame("Frame", nil, strip)
    w.cell = cell
    cell.vline = Kit.Divider(cell, true)
    cell.vline:SetPoint("TOPRIGHT")
    cell.vline:SetPoint("BOTTOMRIGHT")

    w.field = Kit.EditBox(cell, 200, 28, { placeholder = L["Search: attunement, quest, item …"], size = 12,
        maxLetters = 60, onChange = OnChange })
    w.field:SetPoint("TOPLEFT", cell, "TOPLEFT", PAD, -PAD)
    w.field:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -PAD, PAD)
    w.field.placeholder:ClearAllPoints()
    w.field.placeholder:SetPoint("LEFT", w.field, "LEFT", 26, 0)
    w.field.placeholder:SetPoint("RIGHT", w.field, "RIGHT", -8, 0)
    w.lens = Kit.Glyph(w.field, "search", 14, "textDim")
    w.lens:SetPoint("LEFT", w.field, "LEFT", 8, 0)
    w.clear = Kit.IconButton(w.field, 18, "close", Clear, L["Clear search"])
    w.clear:SetPoint("RIGHT", w.field, "RIGHT", -4, 0)
    w.clear:Hide()
    w.tag = Kit.Text(w.field, 10, "accent")
    w.tag:Hide()

    -- a short note right of the field (an entry that is not reachable)
    w.note = Kit.Text(strip, 11, "textDim")
    w.note:SetPoint("LEFT", cell, "RIGHT", 14, 0)
    w.note:Hide()

    local edit = w.field.edit
    if type(edit.SetAltArrowKeyMode) == "function" then edit:SetAltArrowKeyMode(false) end
    edit:SetScript("OnEscapePressed", function(self)
        if self:GetText() ~= "" then
            self:SetText("")
            StopPulse()
        else
            CloseOverlay()
            self:ClearFocus()
        end
    end)
    edit:SetScript("OnEnterPressed", function(self)
        local row = S.open and S.flat[S.sel or 1] or nil
        if row then Choose(row.item) else self:ClearFocus() end
    end)
    edit:HookScript("OnArrowPressed", function(_, key)
        if key == "DOWN" then Move(1) elseif key == "UP" then Move(-1) end
    end)
    edit:HookScript("OnEditFocusGained", function()
        Search.Get() -- the index is built when the field gets the focus, not at the first key
        if S.q.active then
            S.open = true
            Render()
        end
    end)
    edit:HookScript("OnEditFocusLost", function()
        -- a click on the overlay takes the focus for a moment: look again a little later
        if C_Timer then
            C_Timer.After(0.15, function()
                if W and S.open and not edit:HasFocus() and not W.overlay:IsMouseOver() then CloseOverlay() end
            end)
        end
    end)

    BuildOverlay(host)
    w.overlay:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", PAD, -2)
    BuildEffects(host)
    UpdateField()
    return w
end

-- The cell above the list column ends where the list's tree frame ends.
local function Attach()
    if not W then return end
    local tree = A.Tree()
    local cell, frame = W.cell, tree and tree.treeframe
    cell:ClearAllPoints()
    cell:SetPoint("BOTTOMLEFT", W.strip, "BOTTOMLEFT", 0, 0)
    if frame then
        cell:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, ROOM)
    else
        cell:SetPoint("TOPLEFT", W.strip, "TOPLEFT", 0, 0)
        cell:SetWidth(COLUMN_FALLBACK)
    end
end

---------------------------------------------------------------------------
-- Hooks
---------------------------------------------------------------------------

local function OnView()
    if not W then return end
    local list = A.IsListView()
    W.strip:SetShown(list)
    if list then
        Attach()
    else
        CloseOverlay()
        W.field.edit:ClearFocus()
        StopPulse()
        ClearMarks()
    end
end

-- A chain was built: mark its cards for the active search; reveal the card of a hit that was just chosen.
local function OnSelect()
    if not W then return end
    ApplyMarks()
    local entry = S.reveal
    if entry then
        if entry.aid == A.CurrentAttune() then RevealEntry(entry, false) else S.reveal = nil end
    end
end

-- Theme, accent or status colours changed: an open list shows its match colour anew.
Theme.OnChange(function()
    if W and searchOn and S.open then ns.Modules.Run("search", Render) end
end)

-- Choices of the filter (labels, order) for the options.
function Skin.SearchFilters()
    local values, order = {}, { "all", "attune", "quest", "npc", "item", "zone" }
    for _, key in ipairs(order) do values[key] = FilterLabel(key) end
    return values, order
end

-- A search setting changed in the options: field tag, chips, switch, open result list and marks follow.
function Skin.SearchApplySettings()
    if not W or not searchOn then return end
    ns.Modules.Run("search", function()
        UpdateField()
        W.only:Update()
        if S.open then Render() end
        ApplyMarks()
    end)
end

-- Frames the tests and the probe may look at.
function Skin.SearchState()
    return { W = function() return W end, S = S, marks = marks, stats = stats, render = Render, apply = ApplyMarks,
        choose = Choose, move = Move, setFilter = SetFilter, setOnlyOpen = SetOnlyOpen, change = OnChange,
        reveal = RevealEntry }
end

ns.Modules.Register("search", {
    requires = { "Frame", "ToggleView", "Select", "MainFrame", "Tree", "Data", "StepIndex", "PatchStep", "Lang", "DB",
        "Path" },
    setting = "search",
    Enable = function()
        -- the strip sits under our window header: without the window skin there is nothing to attach to
        if not Skin.Window() then return end
        searchOn = true
        local host = A.MainFrame()
        if not W then Build(host) end
        Skin.SetSearchRoom(ROOM)
        Skin.PlaceContent()
        A.On("view", OnView, "search")
        A.On("select", OnSelect, "search")
        OnView()
    end,
    Disable = function()
        searchOn = false
        Skin.SetSearchRoom(0)
        if W then
            CloseOverlay()
            W.strip:Hide()
            StopPulse()
        end
        ClearMarks()
        Skin.PlaceContent()
    end,
})
