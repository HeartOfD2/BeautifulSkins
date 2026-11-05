-- Navigation arrow in the EllesmereUI look (same styles and colour modes as the arrow of EUI RestedXP Skin): Chevron,
-- Ring, Pill and Classic; colour by accent, by direction or custom; a distance row and a name row. The arrow only draws
-- what its owner hands it (Draw / SetRows); it has no data source and no update loop of its own.
local addonName, ns = ...

local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
local WIDTH = 160
local GAP = 2

-- Per style: height of the glyph area, size of the arrowhead inside it, size of the state symbol.
local STYLE = {
    CHEVRON = { hub = 64, glyph = 64, symbol = 56 },
    RING = { hub = 72, glyph = 44, symbol = 40 },
    PILL = { hub = 40, glyph = 28, symbol = 28 },
    CLASSIC = { hub = 64, glyph = 64, symbol = 56 },
}
local PILL_W = 150
local ROWS = { dist = { 20, 24 }, name = { 13, 16 } } -- font size, row height
local PILL_DIST = { 16, 20 }

local GREEN = { 0x3F / 255, 0xBF / 255, 0x5F / 255 }
local YELLOW = { 0xF0 / 255, 0xC8 / 255, 0x60 / 255 }
local RED = { 0xE5 / 255, 0x53 / 255, 0x4B / 255 }
local GREEN_LIMIT, YELLOW_LIMIT = math.rad(30), math.rad(110)

local Arrow = {}
ns.Arrow = Arrow

local function Settings()
    return ns.db and ns.db.arrow or ns.DEFAULTS.arrow
end

-- Colour of the arrowhead for a style and an angle (radians, 0 = straight ahead).
local function ColorFor(style, angle)
    local s = Settings()
    local mode = s.color
    if style == "CLASSIC" and mode ~= "CUSTOM" then mode = "DIRECTION" end
    if mode == "CUSTOM" then
        local c = s.customColor
        if type(c) == "table" and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
            return c.r, c.g, c.b
        end
    elseif mode == "DIRECTION" and angle then
        local off = math.abs((angle + math.pi) % (2 * math.pi) - math.pi)
        local c = off <= GREEN_LIMIT and GREEN or (off <= YELLOW_LIMIT and YELLOW or RED)
        return c[1], c[2], c[3]
    end
    return ns.Accent()
end

-- Creates the arrow as a child of parent (it shows and hides with it). The frame never takes the mouse, so dragging
-- still reaches the parent.
function Arrow.Create(parent)
    local self = {}
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(WIDTH, 64)
    f:EnableMouse(false)
    self.frame = f

    local hub = CreateFrame("Frame", nil, f)
    hub:SetSize(64, 64)
    hub:SetPoint("TOP", f, "TOP", 0, 0)

    local function MakeTex(layer, file, sublevel)
        local tex = f:CreateTexture(nil, layer, nil, sublevel or 0)
        if file then tex:SetTexture(MEDIA .. file .. ".tga") end
        tex:SetPoint("CENTER", hub, "CENTER", 0, 0)
        tex:Hide()
        return tex
    end

    local ringFace = MakeTex("BACKGROUND", "ring")
    ringFace:SetVertexColor(10 / 255, 12 / 255, 12 / 255, 0.55)
    local ringEdge = MakeTex("BORDER", "ring_edge")
    ringEdge:SetVertexColor(1, 1, 1, 0.25)
    local ringNorth = MakeTex("BORDER")
    ringNorth:SetColorTexture(1, 1, 1, 0.6)
    ringNorth:SetSize(2, 8)
    ringNorth:ClearAllPoints()
    ringNorth:SetPoint("TOP", hub, "TOP", 0, -3)

    local pillBg = f:CreateTexture(nil, "BACKGROUND")
    pillBg:SetColorTexture(0x12 / 255, 0x0F / 255, 0x0C / 255, 0.88)
    pillBg:Hide()
    local pillEdges = {}
    for i = 1, 4 do
        local edge = f:CreateTexture(nil, "BORDER")
        edge:SetColorTexture(1, 1, 1, 0.10)
        edge:Hide()
        pillEdges[i] = edge
    end
    local pillField = f:CreateTexture(nil, "BORDER", nil, 1)
    pillField:Hide()

    local cOutline = MakeTex("BACKGROUND", "chevron_outline", 1)
    cOutline:SetVertexColor(0, 0, 0, 0.7)
    local cFill = MakeTex("ARTWORK", "chevron")
    local cRelief = MakeTex("OVERLAY", "chevron_relief")
    cRelief:SetVertexColor(0, 0, 0, 0.22)
    local bOutline = MakeTex("BACKGROUND", "block_outline", 1)
    bOutline:SetVertexColor(0, 0, 0, 0.7)
    local bFill = MakeTex("ARTWORK", "block")

    local symbolBack = MakeTex("BACKGROUND", nil, 2)
    symbolBack:SetVertexColor(0, 0, 0, 0.6)
    local symbol = MakeTex("ARTWORK", nil, 1)

    local chevronParts = { cOutline, cFill, cRelief }
    local blockParts = { bOutline, bFill }
    local symbolParts = { symbolBack, symbol }

    local function SetParts(list, shown)
        for i = 1, #list do list[i]:SetShown(shown) end
    end

    local function MakeRow()
        local fs = f:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
        fs:SetWidth(WIDTH)
        fs:SetJustifyH("CENTER")
        fs:SetWordWrap(false)
        return fs
    end
    local distText, nameText = MakeRow(), MakeRow()
    nameText:SetTextColor(1, 1, 1, 0.75)

    local style = "CHEVRON"
    local lastColor

    local function ApplyColor(angle)
        local r, g, b = ColorFor(style, angle)
        local key = ("%.3f:%.3f:%.3f"):format(r, g, b)
        if key == lastColor then return end
        lastColor = key
        cFill:SetVertexColor(r, g, b, 1)
        bFill:SetVertexColor(r, g, b, 1)
        symbol:SetVertexColor(r, g, b, 1)
        pillField:SetColorTexture(r, g, b, 0.15)
    end

    -- Sizes, style and fonts from the settings (after an option, accent or font change).
    function self.Layout()
        local s = Settings()
        style = STYLE[s.style] and s.style or "CHEVRON"
        local spec = STYLE[style]
        local pill = style == "PILL"
        local offset = (WIDTH - PILL_W) / 2
        f:SetScale(ns.Clamp(s.scale, 0.5, 2, 0.8))
        lastColor = nil

        hub:ClearAllPoints()
        hub:SetSize(spec.hub, spec.hub)
        if pill then
            hub:SetPoint("TOPLEFT", f, "TOPLEFT", offset, 0)
        else
            hub:SetPoint("TOP", f, "TOP", 0, 0)
        end
        for _, part in ipairs(chevronParts) do part:SetSize(spec.glyph, spec.glyph) end
        for _, part in ipairs(blockParts) do part:SetSize(spec.glyph, spec.glyph) end
        for _, part in ipairs(symbolParts) do part:SetSize(spec.symbol, spec.symbol) end
        symbolBack:SetSize(spec.symbol * 1.12, spec.symbol * 1.12)
        local ring = style == "RING"
        ringFace:SetShown(ring); ringEdge:SetShown(ring); ringNorth:SetShown(ring)
        if ring then
            ringFace:SetSize(spec.hub, spec.hub)
            ringEdge:SetSize(spec.hub, spec.hub)
        end
        pillBg:SetShown(pill); pillField:SetShown(pill)
        for _, edge in ipairs(pillEdges) do edge:SetShown(pill) end
        if pill then
            pillBg:ClearAllPoints(); pillBg:SetPoint("TOPLEFT", f, "TOPLEFT", offset, 0); pillBg:SetSize(PILL_W, spec.hub)
            pillField:ClearAllPoints(); pillField:SetPoint("TOPLEFT", pillBg, "TOPLEFT", 0, 0)
            pillField:SetSize(spec.hub, spec.hub)
            local e = pillEdges
            e[1]:ClearAllPoints(); e[1]:SetPoint("TOPLEFT", pillBg); e[1]:SetPoint("TOPRIGHT", pillBg); e[1]:SetHeight(1)
            e[2]:ClearAllPoints(); e[2]:SetPoint("BOTTOMLEFT", pillBg); e[2]:SetPoint("BOTTOMRIGHT", pillBg); e[2]:SetHeight(1)
            e[3]:ClearAllPoints(); e[3]:SetPoint("TOPLEFT", pillBg); e[3]:SetPoint("BOTTOMLEFT", pillBg); e[3]:SetWidth(1)
            e[4]:ClearAllPoints(); e[4]:SetPoint("TOPRIGHT", pillBg); e[4]:SetPoint("BOTTOMRIGHT", pillBg); e[4]:SetWidth(1)
        end

        local path, flags = ns.Font()
        if flags == "" then flags = "OUTLINE" end -- readable over the game world
        local y = -spec.hub - GAP
        distText:ClearAllPoints()
        if s.showDistance ~= false then
            if pill then
                ns.SetFont(distText, path, PILL_DIST[1], flags)
                distText:SetWidth(PILL_W - spec.hub - 14)
                distText:SetJustifyH("LEFT")
                distText:SetPoint("LEFT", hub, "RIGHT", 8, 0)
                distText:SetHeight(PILL_DIST[2])
            else
                ns.SetFont(distText, path, ROWS.dist[1], flags)
                distText:SetWidth(WIDTH)
                distText:SetJustifyH("CENTER")
                distText:SetPoint("TOP", f, "TOP", 0, y)
                distText:SetHeight(ROWS.dist[2])
                y = y - ROWS.dist[2]
            end
            distText:Show()
        else
            distText:Hide()
        end
        nameText:ClearAllPoints()
        ns.SetFont(nameText, path, ROWS.name[1], flags)
        if s.showName ~= false then
            nameText:SetWidth(WIDTH)
            nameText:SetPoint("TOP", f, "TOP", 0, y)
            nameText:SetHeight(ROWS.name[2])
            nameText:Show()
            y = y - ROWS.name[2]
        else
            nameText:Hide()
        end
        f:SetHeight(-y)
        distText:SetTextColor(1, 1, 1, 1)
    end

    -- kind: "ARROW" (rotated by angle, radians, counter-clockwise positive), "CHECK", "TRANSPORT" or "NONE".
    function self.Draw(kind, angle)
        if kind == "ARROW" then
            local classic = style == "CLASSIC"
            SetParts(symbolParts, false)
            SetParts(chevronParts, not classic)
            SetParts(blockParts, classic)
            for _, part in ipairs(classic and blockParts or chevronParts) do part:SetRotation(angle or 0) end
        elseif kind == "CHECK" or kind == "TRANSPORT" then
            SetParts(chevronParts, false)
            SetParts(blockParts, false)
            local name = kind == "CHECK" and "check" or "transport"
            if symbol.file ~= name then
                symbol.file = name
                symbol:SetTexture(MEDIA .. name .. ".tga")
                symbolBack:SetTexture(MEDIA .. name .. ".tga")
            end
            SetParts(symbolParts, true)
        else
            SetParts(chevronParts, false)
            SetParts(blockParts, false)
            SetParts(symbolParts, false)
        end
        -- direction colours measure the turn clockwise-positive, like the player sees it
        ApplyColor(kind == "ARROW" and -(angle or 0) or nil)
    end

    -- Only touches a row when its text really changed (owners call this every frame).
    function self.SetRows(dist, name)
        dist, name = dist or "", name or ""
        if distText.lastText ~= dist then
            distText.lastText = dist
            distText:SetText(dist)
        end
        if nameText.lastText ~= name then
            nameText.lastText = name
            nameText:SetText(name)
        end
    end

    self.Layout()
    return self
end
