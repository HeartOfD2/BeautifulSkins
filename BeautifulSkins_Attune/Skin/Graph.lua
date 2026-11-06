-- Chain skin: Attune's cards, connectors, OR marks, inside box and chain header in the theme.
-- Cards, lines, OR marks and the inside box are Attune's own named frames (never pooled): Attune redraws them on every
-- build, so they are styled again after each build. Attune's drawing of a card (backdrop, icon, texts, badge) stays in
-- place but invisible, its colours stay readable for the status mapping; a decoration frame per card draws the card.
-- The chain header of Attune is a stack of pooled AceGUI labels: they are left untouched and covered by our own,
-- opaque header card (own frames, anchored next to the pooled ones). The chain then starts below our header.
-- Attune repaints a card on every build (a new backdrop, then its status colours), so the status is read first and
-- Attune's drawing made invisible again after each build. Backdrop pieces are hidden, not faded: in the client a
-- texture's colour alpha is its alpha, and the status is read from that colour.
local _, ns = ...
local L, A, Theme, Kit, Skin = ns.L, ns.Attune, ns.Theme, ns.Kit, ns.Skin
local Paint, Bind, Refresh = Theme.Paint, Theme.Bind, Theme.Refresh

local G = A.GRAPH
local OWN = {}                                         -- undo owner for changes on Attune's own chain frames
local decos = setmetatable({}, { __mode = "k" })       -- card -> decoration frame
local orDecos = setmetatable({}, { __mode = "k" })     -- OR mark -> our capsule
local crisp = setmetatable({}, { __mode = "k" })       -- Attune lines already snapped to the pixel grid
local BACKDROP_PIECES = { "Center", "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "TopLeftCorner",
    "TopRightCorner", "BottomLeftCorner", "BottomRightCorner" }
local LINE_WEIGHTS = { fine = 2, normal = 3, strong = 4 }
local ART_MODES = { banner = true, background = true, off = true }
local BOX_TITLE = 18                                   -- the inside box grows upwards by this for its title
local HEAD_PAD_X, HEAD_PAD_TOP, HEAD_PAD_BOTTOM = 26, 22, 12
local BANNER_H = 156

local H                                                -- header card, built once
-- lastMs/maxMs: our own time per chain build (Attune's work in between is not counted); moved: our frames that had to
-- be put back above their Attune frame at the last build (for the probe)
local stats = { builds = 0, cards = 0, lastMs = 0, maxMs = 0, moved = 0 }

local function Setting(key, default)
    local settings = ns.db and ns.db.settings
    if settings and settings[key] ~= nil then return settings[key] end
    return default
end

local function LineWeight()
    return LINE_WEIGHTS[Setting("lineWeight", "normal")] or LINE_WEIGHTS.normal
end

local function ArtMode()
    local mode = Setting("dungeonArt", "banner")
    return ART_MODES[mode] and mode or "banner"
end

-- Whole physical pixels for a design measure given in px at 100 % zoom.
local function Px(base, zoom, minimum)
    return math.max(minimum or 1, math.floor(base * zoom * Skin.Density() + 0.5))
end

local function Clock()
    return type(debugprofilestop) == "function" and debugprofilestop() or nil
end

---------------------------------------------------------------------------
-- Words of the type line (own words, the design's)
---------------------------------------------------------------------------

local typeWords
local function TypeWords()
    if typeWords then return typeWords end
    typeWords = {
        pickup = L["Accept"], turnin = L["Hand in"], quest = L["Quest"], item = L["Item"], level = L["Required level"],
        rep = L["Reputation"], attune = L["Attunement or key"], kill = L["Kill"], interact = L["Interact"],
        click = L["Click"],
    }
    return typeWords
end

local NO_ZONE = { level = true, rep = true, attune = true }

-- The design's word for the type of a step ("Accept", "Hand in", "Quest" ...); the search uses it for its context line.
function Skin.TypeWord(step)
    return TypeWords()[A.TypeKey(step)] or A.TypeName(step) or ""
end

local function TypeLine(step)
    local key = A.TypeKey(step)
    local word = TypeWords()[key] or A.TypeName(step) or ""
    local zone = not NO_ZONE[key] and A.ZoneName(step) or nil
    if zone and zone ~= "" then return word .. " · " .. zone end
    return word
end

---------------------------------------------------------------------------
-- Card decoration
---------------------------------------------------------------------------

local function StatusColor(s, T, key, tokenKey)
    return s[key] or T[s[tokenKey] or ""] or T.textDim
end

local function PaintDeco(d, T)
    if not d.state then return end
    local s = Theme.Status(d.state)
    Paint(d.bg, T.bgAlt)
    if s.fill then
        Paint(d.tint, s.fill)
        d.tint:Show()
    else
        d.tint:Hide()
    end
    local edge = d.hot and T.accent or s.edge or T.border
    for i = 1, 4 do Paint(d.edges[i], edge) end
    local stripe = StatusColor(s, T, "stripe", "stripeKey")
    Paint(d.stripe, stripe)
    Paint(d.iconBack, { 0, 0, 0, 0.8 })
    d.icon:SetDesaturated(s.dim and true or false)
    if s.dim then d.icon:SetVertexColor(0.7, 0.7, 0.7) else d.icon:SetVertexColor(1, 1, 1) end
    Paint(d.mark.fill, stripe)
    local badge = d.badge
    if badge.kind == "done" then
        Paint(badge.fill, T.success)
        Paint(badge.text, { 0.03, 0.08, 0.05, 1 })
    else
        Paint(badge.fill, T.accent)
        Paint(badge.text, T.onAccent)
    end
    d:SetAlpha(s.alpha or 1)
end

local function NewDeco(node)
    local d = Skin.Mine(CreateFrame("Frame", nil, node))
    d:SetAllPoints(node)
    d.bg = d:CreateTexture(nil, "BACKGROUND", nil, -8)
    d.bg:SetAllPoints()
    d.tint = d:CreateTexture(nil, "BACKGROUND", nil, -7)
    d.tint:SetAllPoints()
    d.edges = {}
    for i = 1, 4 do
        d.edges[i] = d:CreateTexture(nil, "BORDER", nil, 7)
        Theme.Crisp(d.edges[i])
    end
    local top, bottom, left, right = d.edges[1], d.edges[2], d.edges[3], d.edges[4]
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
    bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT")
    left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT")
    right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT")
    d.stripe = d:CreateTexture(nil, "ARTWORK", nil, 2)
    d.stripe:SetPoint("TOPLEFT"); d.stripe:SetPoint("BOTTOMLEFT")
    Theme.Crisp(d.stripe)
    d.iconBack = d:CreateTexture(nil, "ARTWORK", nil, 0)
    d.iconBack:SetPoint("TOPLEFT", d, "TOPLEFT", 10, -8)
    d.iconBack:SetSize(G.iconSize, G.iconSize)
    d.icon = d:CreateTexture(nil, "ARTWORK", nil, 1)
    d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    d.mark = CreateFrame("Frame", nil, d)
    d.mark:SetSize(12, 12)
    d.mark:SetPoint("TOPLEFT", d, "TOPLEFT", 34, -30)
    d.mark.fill = d.mark:CreateTexture(nil, "ARTWORK")
    d.mark.fill:SetAllPoints()
    d.mark.glyph = Kit.Glyph(d.mark, "check", 10, "white")
    d.mark.glyph:SetPoint("CENTER")
    d.title = Kit.Text(d, 11, "text")
    d.title:SetWordWrap(false)
    d.count = Kit.Text(d, 10, "text")
    d.count:SetJustifyH("RIGHT")
    d.typeLine = Kit.Text(d, 10, "textDim")
    d.typeLine:SetWordWrap(false)
    d.badge = CreateFrame("Frame", nil, d)
    d.badge:SetHeight(16)
    d.badge:SetPoint("TOPRIGHT", d, "TOPRIGHT", 8, 5)
    d.badge.fill = d.badge:CreateTexture(nil, "ARTWORK")
    d.badge.fill:SetAllPoints()
    d.badge.text = Kit.Text(d.badge, 10, false)
    d.badge.text:SetPoint("CENTER")
    Bind(d, PaintDeco)
    return d
end

-- Anchors depending on the kind of card ("card", "half", "end") and an item count on the right.
local function Place(d, kind, hasCount)
    if d.kind == kind and d.hasCount == hasCount then return end
    d.kind, d.hasCount = kind, hasCount
    local left = kind == "half" and 46 or 50
    local right = kind == "half" and -4 or -8
    local titleY = kind == "end" and -16 or -8
    d.title:ClearAllPoints()
    d.title:SetPoint("TOPLEFT", d, "TOPLEFT", left, titleY)
    d.title:SetPoint("TOPRIGHT", d, "TOPRIGHT", hasCount and -40 or right, titleY)
    d.count:ClearAllPoints()
    d.count:SetPoint("TOPRIGHT", d, "TOPRIGHT", -8, -8)
    d.typeLine:ClearAllPoints()
    d.typeLine:SetPoint("TOPLEFT", d, "TOPLEFT", left, -25)
    d.typeLine:SetPoint("TOPRIGHT", d, "TOPRIGHT", right, -25)
    if d.title.fnSize ~= (kind == "end" and 12 or 11) then Kit.SetTextSize(d.title, kind == "end" and 12 or 11) end
end

-- Sizes that are whole screen pixels at the current zoom and UI scale (only redone when one of them changed).
local function Geometry(d)
    local px = Skin.Pixel(d)
    local zoom = A.Zoom()
    local key = ("%.5f %.3f %d"):format(px, zoom, d.edgeSize or 1)
    if d.geometry == key then return end
    d.geometry = key
    local edge = (d.edgeSize or 1) * Skin.Density() * px
    d.edges[1]:SetHeight(edge); d.edges[2]:SetHeight(edge)
    d.edges[3]:SetWidth(edge); d.edges[4]:SetWidth(edge)
    d.stripe:SetWidth(Px(3, zoom, 2) * px)
    d.icon:ClearAllPoints()
    d.icon:SetPoint("TOPLEFT", d.iconBack, "TOPLEFT", px, -px)
    d.icon:SetPoint("BOTTOMRIGHT", d.iconBack, "BOTTOMRIGHT", -px, px)
    d.mark.glyph:CheckScale()
end

local function SetTextColor(fs, key)
    if fs.fnColor ~= key then Kit.SetTextColor(fs, key) end
end

local function SetHot(node, hot)
    local d = decos[node]
    if d and d.hot ~= hot then
        d.hot = hot
        d.look = nil
        Refresh(d)
    end
end

local function Hover(node) SetHot(node, true) end
local function Unhover(node) SetHot(node, false) end

-- Attune's own drawing on a card: kept in place, made invisible after every build (its colours stay readable).
local function ConcealAttuneCard(node, parts)
    for _, key in ipairs(BACKDROP_PIECES) do
        local piece = node[key]
        if type(piece) == "table" then Skin.HideFrame(OWN, piece) end
    end
    Skin.Alpha(OWN, parts.icon, 0)
    Skin.Alpha(OWN, parts.title, 0)
    Skin.Alpha(OWN, parts.type, 0)
    Skin.Alpha(OWN, parts.notif, 0)
end

local function StyleCard(step, node, parts)
    local state = A.NodeState(node, step)
    ConcealAttuneCard(node, parts)
    local d = decos[node]
    if state == "spacer" then
        if d then d:Hide() end
        return
    end
    if not d then
        d = NewDeco(node)
        decos[node] = d
    end
    d.step, d.state, d.hot = step, state, node:IsMouseOver() and true or false
    local key = A.TypeKey(step)
    local kind = key == "end" and "end" or (step.HALFSIZE and "half" or "card")

    local title = Skin.Plain(parts.title and parts.title:GetText() or "")
    if title == "" then title = A.StepName(step) or "" end
    local count, name = title:match("^(%d+/%d+)%s+(.+)$")
    Place(d, kind, count ~= nil)
    d.title:SetText(name or title)
    d.count:SetText(count or "")
    d.count:SetShown(count ~= nil)
    d.typeLine:SetText(kind == "end" and "" or TypeLine(step))
    d.typeLine:SetShown(kind ~= "end")

    d.icon:SetTexture(A.StepIcon(step))
    d.mark:SetShown(state == "done" or state == "key_done")
    local badgeText, badgeKind = A.NodeBadge(parts, step)
    if badgeText then
        d.badge.kind = badgeKind
        d.badge.text:SetText(badgeText)
        d.badge:SetWidth(math.max(22, (d.badge.text:GetStringWidth() or 0) + 10))
        d.badge:Show()
    else
        d.badge:Hide()
    end

    local s = Theme.Status(state)
    d.edgeSize = math.max(s.edgeSize or 1, kind == "end" and 2 or 1)
    SetTextColor(d.title, s.dim and "textDim" or "text")
    Geometry(d)
    local look = ("%s %s %s"):format(state, tostring(d.hot), tostring(d.badge.kind))
    if d.look ~= look then
        d.look = look
        Refresh(d)
    end
    d:Show()

    -- Attune sets the card's scripts anew on every build, so the hover hooks are added again each time
    A.HookScript(node, "OnEnter", Hover, "graph")
    A.HookScript(node, "OnLeave", Unhover, "graph")
end

---------------------------------------------------------------------------
-- Connectors: status colour, thickness in whole pixels, closed corners
---------------------------------------------------------------------------

local function LineColor(line)
    local s = Theme.Status(A.LineState(line))
    local T = Theme.Get()
    return s.line or T[s.lineKey or ""] or T.textDim
end

local function Paint1(line, t)
    if not crisp[line] then
        crisp[line] = true
        Theme.Crisp(line)
    end
    line:SetThickness(t)
    local c = LineColor(line)
    line:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

local function Segment(line, t, x1, y1, x2, y2)
    Paint1(line, t)
    line:SetStartPoint("TOP", x1, y1)
    line:SetEndPoint("TOP", x2, y2)
end

-- Attune's three segments per connector (down from the source, across, down into the card), redrawn so the
-- vertical ones reach half a thickness past the corner and the horizontal one half a thickness past each vertical:
-- corners close without a gap or an overhang. Both ends reach one pixel under the cards.
local function StyleLines(step, node)
    local px = Skin.Pixel(node)
    local t = Px(LineWeight(), A.Zoom(), 1) * px
    local h = t / 2
    for _, c in ipairs(A.IncomingLines(step, node)) do
        local ys = c.dy - G.nodeHeight
        local ym = ys - G.vGap / 2
        Segment(c.line1, t, c.dx, ys + px, c.dx, ym - h)
        Segment(c.line3, t, 0, ym + h, 0, -px)
        Segment(c.line2, t, math.min(0, c.dx) - h, ym, math.max(0, c.dx) + h, ym)
    end
    local fill = A.SpacerFill(step)
    if fill then Paint1(fill, t) end
    local feeder = A.SideFeeder(step)
    if feeder then Paint1(feeder, t) end
end

---------------------------------------------------------------------------
-- OR marks, inside box, work-in-progress note
---------------------------------------------------------------------------

local function PaintOr(o, T)
    o.pill:SetColors(T.bgAlt, Theme.Status("ready").line or T.accent)
end

local function StyleOr(holder)
    Skin.Alpha(OWN, holder.ring, 0)
    Skin.Alpha(OWN, holder.fill, 0)
    Skin.Alpha(OWN, holder.label, 0)
    local o = orDecos[holder]
    if not o then
        o = Skin.Mine(CreateFrame("Frame", nil, holder))
        o:SetPoint("CENTER")
        o.pill = Skin.Pill(o)
        o.text = Kit.Text(o, 9, "text")
        o.text:SetPoint("CENTER", 0, 0)
        Bind(o, PaintOr)
        orDecos[holder] = o
    end
    local word = Skin.Plain(holder.label and holder.label:GetText() or "")
    o.text:SetText(Skin.Upper(word ~= "" and word or "OR"))
    o:SetSize(math.max(28, (o.text:GetStringWidth() or 0) + 14), 16)
    o.pill:Layout()
    o:Show()
end

local sideDeco

local function PaintSide(b, T)
    Paint(b.fill, T.mode == "light" and { 0, 0, 0, 0.03 } or { 1, 1, 1, 0.025 })
    for i = 1, 4 do Paint(b.edges[i], T.border) end
end

local function SideGeometry(b)
    local px = Skin.Pixel(b)
    b.edges[1]:SetHeight(px); b.edges[2]:SetHeight(px)
    b.edges[3]:SetWidth(px); b.edges[4]:SetWidth(px)
end

local function StyleSideBox()
    local box, title = A.SideBox()
    if not box or not box:IsShown() then return end
    -- Attune repaints the box on every build; its own look stays invisible
    Skin.Backdrop(OWN, box, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
    if title then Skin.Alpha(OWN, title, 0) end
    local b = sideDeco
    if not b or b:GetParent() ~= box then
        b = Skin.Mine(CreateFrame("Frame", nil, box))
        b.fill = b:CreateTexture(nil, "BACKGROUND")
        b.fill:SetAllPoints()
        b.edges = {}
        for i = 1, 4 do
            b.edges[i] = b:CreateTexture(nil, "BORDER")
            Theme.Crisp(b.edges[i])
        end
        b.edges[1]:SetPoint("TOPLEFT"); b.edges[1]:SetPoint("TOPRIGHT")
        b.edges[2]:SetPoint("BOTTOMLEFT"); b.edges[2]:SetPoint("BOTTOMRIGHT")
        b.edges[3]:SetPoint("TOPLEFT"); b.edges[3]:SetPoint("BOTTOMLEFT")
        b.edges[4]:SetPoint("TOPRIGHT"); b.edges[4]:SetPoint("BOTTOMRIGHT")
        b.title = Kit.Text(b, 10, "textDim")
        b.title:SetPoint("TOPLEFT", b, "TOPLEFT", G.sidePad, -7)
        Bind(b, PaintSide)
        sideDeco = b
    end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", box, "TOPLEFT", 0, BOX_TITLE)
    b:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
    b.title:SetText(Skin.Upper(Skin.Plain(title and title:GetText() or "")))
    SideGeometry(b)
    b:Show()
end

-- Attune rewrites the counts of an open character trial straight on its cards, without a build of the chain.
local function OnStatLabels()
    for _, item in ipairs(A.ShownNodes()) do
        local d = decos[item.node]
        if d and A.TypeKey(item.step) == "stat" then
            local _, parts = A.Node(item.step.ID)
            if parts.title then d.title:SetText(Skin.Plain(parts.title:GetText() or "")) end
        end
    end
end

local function StyleWorkInProgress()
    local wip = A.WorkInProgress()
    if not wip or not Skin.Once(wip, "style") then return end
    Bind(wip.text, function(self, T)
        Theme.SetFont(self, 16)
        Paint(self, T.textDim)
        if self.SetShadowOffset then self:SetShadowOffset(0, 0) end
    end)
end

---------------------------------------------------------------------------
-- Chain header: icon, name, chips, progress, description; optional dungeon banner
---------------------------------------------------------------------------

local function Tag(parent)
    local t = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    t:SetHeight(18)
    t.text = Kit.Text(t, 10, "header")
    t.text:SetPoint("LEFT", t, "LEFT", 7, 0)
    t.text:SetWordWrap(false)
    Bind(t, function(self, T) Theme.Box(self, T, "control", "border") end)
    return t
end

local function BuildHead()
    local host = A.MainFrame()
    local h = { tags = {} }
    -- clip holder over the visible chain area; the card scrolls with Attune's content
    h.clip = Skin.Mine(CreateFrame("Frame", nil, host))
    if h.clip.SetClipsChildren then h.clip:SetClipsChildren(true) end
    local card = CreateFrame("Frame", nil, h.clip)
    h.card = card
    card.bg = card:CreateTexture(nil, "BACKGROUND", nil, -8)
    card.bg:SetAllPoints()
    card.art = card:CreateTexture(nil, "BACKGROUND", nil, -7)
    card.art:SetPoint("TOPLEFT")
    card.art:SetPoint("TOPRIGHT")
    card.fade = card:CreateTexture(nil, "BACKGROUND", nil, -6)
    card.fade:SetTexture("Interface\\Buttons\\WHITE8X8")
    card.fade:SetAllPoints(card.art)
    Bind(card, function(self, T)
        Paint(self.bg, T.canvasBg)
        local c = T.canvasBg
        if self.fade.SetGradient and type(CreateColor) == "function" then
            self.fade:SetGradient("VERTICAL", CreateColor(c[1], c[2], c[3], 1), CreateColor(c[1], c[2], c[3], 0))
        else
            Paint(self.fade, { c[1], c[2], c[3], 0.6 })
        end
    end)

    card.iconBack = card:CreateTexture(nil, "ARTWORK", nil, 0)
    card.iconBack:SetSize(40, 40)
    card.iconBack:SetPoint("TOPLEFT", card, "TOPLEFT", HEAD_PAD_X, -HEAD_PAD_TOP)
    card.iconBack:SetColorTexture(0, 0, 0, 0.55)
    card.icon = card:CreateTexture(nil, "ARTWORK", nil, 1)
    card.icon:SetPoint("TOPLEFT", card.iconBack, "TOPLEFT", 1, -1)
    card.icon:SetPoint("BOTTOMRIGHT", card.iconBack, "BOTTOMRIGHT", -1, 1)
    card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    card.name = Kit.Text(card, 20, "text")
    card.name:SetPoint("TOPLEFT", card.iconBack, "TOPRIGHT", 14, 2)
    card.name:SetPoint("RIGHT", card, "RIGHT", -HEAD_PAD_X, 0)
    card.name:SetWordWrap(false)
    card.tagRow = CreateFrame("Frame", nil, card)
    card.tagRow:SetSize(1, 18)
    card.tagRow:SetPoint("TOPLEFT", card.iconBack, "TOPRIGHT", 14, -28)

    card.prog = CreateFrame("Frame", nil, card)
    card.prog:SetSize(220, 12)
    card.prog:SetPoint("TOPLEFT", card.tagRow, "BOTTOMLEFT", 0, -10)
    card.track = card.prog:CreateTexture(nil, "ARTWORK", nil, 0)
    card.track:SetSize(220, 4)
    card.track:SetPoint("LEFT")
    card.bar = card.prog:CreateTexture(nil, "ARTWORK", nil, 1)
    card.bar:SetHeight(4)
    card.bar:SetPoint("LEFT")
    card.pct = Kit.Text(card.prog, 12, "text")
    card.pct:SetPoint("LEFT", card.track, "RIGHT", 10, 0)
    card.pdim = Kit.Text(card.prog, 11, "textDim")
    card.pdim:SetPoint("LEFT", card.pct, "RIGHT", 10, 0)
    Bind(card.prog, function(_, T)
        Paint(card.track, T.track)
        Paint(card.bar, T.accent)
    end)

    card.desc = Kit.Text(card, 12, "textDim")
    card.desc:SetJustifyV("TOP")
    card.desc:SetWordWrap(true)
    if card.desc.SetSpacing then card.desc:SetSpacing(5) end
    h.clip:Hide()
    return h
end

local function FactionText(faction)
    if faction == "Alliance" then return type(FACTION_ALLIANCE) == "string" and FACTION_ALLIANCE or L["Alliance"] end
    if faction == "Horde" then return type(FACTION_HORDE) == "string" and FACTION_HORDE or L["Horde"] end
    if faction == "Both" then return L["Both factions"] end
    return nil
end

local function TagTexts(a)
    local list = {}
    if type(a.LEVELS) == "string" and a.LEVELS ~= "" then list[#list + 1] = L["Level %s"]:format((a.LEVELS:gsub("%-", "–"))) end
    local size = tonumber(a.GROUPSIZE)
    if size and size > 0 then list[#list + 1] = L["%d players"]:format(size) end
    local faction = FactionText(a.FACTION)
    if faction then list[#list + 1] = faction end
    if type(a.CLASS) == "string" and a.CLASS ~= "" then
        local names = LOCALIZED_CLASS_NAMES_MALE
        list[#list + 1] = type(names) == "table" and names[a.CLASS] or a.CLASS
    end
    return list
end

-- Steps of the chain this character has done, out of all shown steps (spacers do not count; as Attune counts).
local function StepCount(id)
    local done, total = 0, 0
    for _, step in ipairs(A.StepsOf(id)) do
        if A.IsStepVisible(step) and A.TypeKey(step) ~= "spacer" then
            total = total + 1
            if A.IsStepDone(id, step.ID) then done = done + 1 end
        end
    end
    return done, total
end

-- Fills the header for the open chain and returns its height (scroll-content units).
local function FillHead(card, id, width)
    local a = A.AttuneById(id)
    if not a then return 0 end
    card.icon:SetTexture(a.ICON)
    card.name:SetText(A.AttuneName(a) or "")
    local x = 0
    local texts = TagTexts(a)
    for i, text in ipairs(texts) do
        local t = H.tags[i] or Tag(card.tagRow)
        H.tags[i] = t
        t.text:SetText(text)
        t:SetWidth((t.text:GetStringWidth() or 0) + 14)
        t:ClearAllPoints()
        t:SetPoint("LEFT", card.tagRow, "LEFT", x, 0)
        x = x + t:GetWidth() + 4
        t:Show()
    end
    for i = #texts + 1, #H.tags do H.tags[i]:Hide() end

    local progress = A.TracksProgress(id) and A.Progress(id) or nil
    local y = HEAD_PAD_TOP + 28 + 18 -- name line, tag row
    if type(progress) == "number" then
        local pct = math.max(0, math.min(100, progress))
        card.bar:SetWidth(math.max(0.01, 220 * pct / 100))
        card.bar:SetShown(pct > 0)
        card.pct:SetText(("%d %%"):format(pct))
        local done, total = StepCount(id)
        card.pdim:SetText(L["%d of %d steps done"]:format(done, total))
        card.prog:Show()
        y = y + 10 + 12
    else
        card.prog:Hide()
    end

    local desc = type(a.DESC) == "string" and a.DESC or ""
    card.desc:ClearAllPoints()
    if desc ~= "" then
        local textWidth = math.min(640, math.max(200, width - HEAD_PAD_X * 2 - 54))
        card.desc:SetWidth(textWidth)
        card.desc:SetPoint("TOPLEFT", card, "TOPLEFT", HEAD_PAD_X + 54, -(y + 10))
        card.desc:SetText(desc)
        card.desc:Show()
        y = y + 10 + (card.desc:GetStringHeight() or 0)
    else
        card.desc:Hide()
    end
    return math.max(y, HEAD_PAD_TOP + 40) + HEAD_PAD_BOTTOM
end

-- The dungeon picture: as a banner behind the header (Attune's own faint background hidden), as Attune's faint
-- background, or not at all. Attune's picture lives on the pooled scroll frame: changes are undone on its release.
local function ApplyArt(scroll, card, height)
    local art = A.DungeonArt()
    local mode = ArtMode()
    local file = art and art:IsShown() and art:GetTexture() or nil
    if art then
        if mode == "background" then
            art:SetAlpha(A.DUNGEON_ART_ALPHA)
        else
            Skin.Alpha(scroll, art, 0)
        end
    end
    if mode == "banner" and file then
        local bannerH = math.min(BANNER_H, height)
        card.art:SetTexture(file)
        card.art:SetHeight(bannerH)
        -- the picture is about twice as wide as high: show a centred band of it
        local width = math.max(1, card:GetWidth() or 1)
        local band = math.min(1, 2 * bannerH / width)
        card.art:SetTexCoord(0, 1, 0.5 - band / 2, 0.5 + band / 2)
        card.art:SetAlpha(0.55)
        card.art:Show()
        card.fade:Show()
    else
        card.art:Hide()
        card.fade:Hide()
    end
end

local function HideHead()
    if H then H.clip:Hide() end
end

---------------------------------------------------------------------------
-- Frame levels: our drawing lies right above the Attune frame it belongs to
---------------------------------------------------------------------------

-- Attune moves its chain between parents (off to UIParent for the results view and back) and sets levels of its own
-- frames (it lifts the inside cards above its box after creating them). The client keeps our child frames above them
-- (probe: no frame had to be put back), the check after every build stays as a cheap guard. true when something had
-- to change.
local function Above(frame, base)
    local changed = false
    local strata = base:GetFrameStrata()
    if frame:GetFrameStrata() ~= strata then
        frame:SetFrameStrata(strata)
        changed = true
    end
    local level = (base:GetFrameLevel() or 0) + 1
    if frame:GetFrameLevel() ~= level then
        frame:SetFrameLevel(level)
        changed = true
    end
    return changed
end

local function StackHead()
    if not (H and H.clip:IsShown()) then return end
    local card = H.card
    Above(card, H.clip)
    Above(card.tagRow, card)
    Above(card.prog, card)
    for _, tag in ipairs(H.tags) do Above(tag, card.tagRow) end
end

local function Restack()
    local moved = 0
    for _, item in ipairs(A.ShownNodes()) do
        local d = decos[item.node]
        if d and d:IsShown() then
            if Above(d, item.node) then moved = moved + 1 end
            Above(d.mark, d)
            Above(d.badge, d)
        end
    end
    for holder, o in pairs(orDecos) do
        if o:IsShown() and Above(o, holder) then moved = moved + 1 end
    end
    if sideDeco and sideDeco:IsShown() then Above(sideDeco, sideDeco:GetParent()) end
    StackHead()
    return moved
end

-- Covers Attune's header labels with our header card; the chain starts below it.
local function StyleHead(id)
    local header = A.ChainHeader()
    local scroll = header and header.scroll
    local host = A.MainFrame()
    if not scroll or not host or not header.group then
        HideHead()
        A.SetGraphHeader(nil)
        return
    end
    H = H or BuildHead()
    local clip, card = H.clip, H.card
    clip:ClearAllPoints()
    clip:SetAllPoints(scroll.scrollframe)
    clip:SetFrameStrata(scroll.scrollframe:GetFrameStrata())
    clip:SetFrameLevel(scroll.content:GetFrameLevel() + 2)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 0, 0)
    card:SetPoint("TOPRIGHT", scroll.content, "TOPRIGHT", 0, 0)
    local width = scroll.content:GetWidth() or 0
    if width < 100 then width = 600 end

    -- at least as tall as Attune's labels, so none of them shows below the card
    local stack = 0
    for _, w in ipairs(header.labels) do stack = stack + (w.frame:GetHeight() or 0) end
    local height = math.max(FillHead(card, id, width), stack + 8)
    card:SetHeight(height)
    ApplyArt(scroll, card, height)
    clip:Show()
    StackHead()
    A.SetGraphHeader(height)
end

---------------------------------------------------------------------------
-- Build hooks
---------------------------------------------------------------------------

local buildOwn = 0                                   -- our time in the current build so far (ms)

local function OnNode(step, _, _, _)
    if type(step) ~= "table" or step.ID == nil then return end
    local start = Clock()
    local node, parts = A.Node(step.ID)
    if node then
        StyleCard(step, node, parts)
        StyleLines(step, node)
    end
    local stop = Clock()
    if start and stop then buildOwn = buildOwn + (stop - start) end
end

-- The side feeder is drawn after the end card: style it once it exists.
local function OnSideFeeder(endStep)
    if type(endStep) ~= "table" then return end
    local node = A.Node(endStep.ID)
    if node then StyleLines(endStep, node) end
end

-- Attune's chain scroll is pooled: on its release take our changes back and hide what belongs to it.
local function OnScrollRelease(scroll)
    Skin.Undo(scroll)
    HideHead()
end

local function WatchScroll(scroll)
    Skin.Begin(scroll)
    if Skin.Once(scroll, "graph-release") then
        A.HookMethod(scroll, "OnRelease", OnScrollRelease, "graph")
    end
end

local function OnSelect(id)
    local start = Clock()
    local own = buildOwn
    buildOwn = 0
    local scroll = A.GraphScroll()
    if not scroll then return end
    WatchScroll(scroll)
    for _, holder in ipairs(A.OrMarks()) do
        if holder:IsShown() then StyleOr(holder) elseif orDecos[holder] then orDecos[holder]:Hide() end
    end
    if sideDeco and not (A.SideBox() and A.SideBox():IsShown()) then sideDeco:Hide() end
    StyleSideBox()
    StyleWorkInProgress()
    StyleHead(id ~= nil and tostring(id) or A.CurrentAttune())
    A.FitGraphContent()
    stats.moved = Restack()

    local cards = 0
    for _, d in pairs(decos) do
        if d:IsVisible() then cards = cards + 1 end
    end
    stats.builds, stats.cards = stats.builds + 1, cards
    local stop = Clock()
    if start and stop then
        stats.lastMs = own + (stop - start)
        stats.maxMs = math.max(stats.maxMs, stats.lastMs)
    end
end

-- Zoom or scale changed: pixel sizes and line geometry again, without a rebuild.
local function RefreshChain()
    for _, item in ipairs(A.ShownNodes()) do
        local d = decos[item.node]
        if d and d:IsShown() then Geometry(d) end
        StyleLines(item.step, item.node)
    end
    for holder, o in pairs(orDecos) do
        if holder:IsShown() then o.pill:Layout() end
    end
    if sideDeco and sideDeco:IsShown() then SideGeometry(sideDeco) end
end

function Skin.GraphRefresh()
    if ns.Modules.IsActive("graph") then ns.Modules.Run("graph", RefreshChain) end
end

-- Settings that change the drawing (line weight, dungeon picture): restyle the open chain.
function Skin.GraphApplySettings()
    if not ns.Modules.IsActive("graph") then return end
    ns.Modules.Run("graph", function()
        RefreshChain()
        if A.GraphScroll() then StyleHead(A.CurrentAttune()) end
    end)
end

-- Frames and numbers the tests and the probe may look at.
function Skin.GraphState()
    return { decos = decos, orDecos = orDecos, side = sideDeco, head = H, stats = stats, restack = Restack }
end

-- Line colours are set on Attune's lines, not bound: recolour them on theme and status scheme changes.
Theme.OnChange(function() Skin.GraphRefresh() end)

ns.Modules.Register("graph", {
    requires = { "Select", "CreateNode", "SideFeeder", "GraphRoot", "GraphScroll", "Nodes", "Lines", "OrMarks", "Pan" },
    setting = "graph",
    Enable = function()
        A.On("node", OnNode, "graph")
        A.On("sideFeeder", OnSideFeeder, "graph")
        A.On("select", OnSelect, "graph")
        A.On("statLabels", OnStatLabels, "graph")
        A.On("view", function()
            if not A.IsListView() then HideHead() end
        end, "graph")
        -- a chain built before the module was enabled: restyle it now
        if A.GraphScroll() and A.CurrentAttune() then
            for _, item in ipairs(A.ShownNodes()) do
                local node, parts = A.Node(item.step.ID)
                if node then
                    StyleCard(item.step, node, parts)
                    StyleLines(item.step, node)
                end
            end
            OnSelect(A.CurrentAttune())
        end
    end,
    Disable = function()
        for _, d in pairs(decos) do d:Hide() end
        for _, o in pairs(orDecos) do o:Hide() end
        if sideDeco then sideDeco:Hide() end
        HideHead()
        Skin.Undo(OWN)
        A.SetGraphHeader(nil)
    end,
})
