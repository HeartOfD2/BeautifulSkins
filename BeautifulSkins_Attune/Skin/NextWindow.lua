-- "Attune: Next" skin: Attune's second window, a small list with the next step of every attunement. Attune builds it
-- the first time it is shown, never pools it, and lays its rows out again on every refresh -- so our own pieces are
-- built once and the rows are looked at after each of Attune's layouts. Attune's own background, title bar and gold
-- edges are faded rather than removed, its texts keep their own colour codes, and everything is taken back when the
-- module is switched off (Skin.Undo). Attune's buttons keep their handlers; only their art is ours.
local _, ns = ...
local A, Theme, Kit, Skin = ns.Attune, ns.Theme, ns.Kit, ns.Skin
local Paint, Bind, Box = Theme.Paint, Theme.Bind, Theme.Box

local OWN = {}        -- undo owner for the permanent changes on Attune's frames
local ours            -- our frames on Attune's window, built once
local BAR_H = 20      -- Attune's own title bar height (its title and buttons sit in it)
local ROW_SIZE = 12
local TITLE_SIZE = 13
local HIGHLIGHT = 0.18

local function Text(fs, size, colorKey)
    if type(fs) ~= "table" or not Skin.Once(fs, "next-text") then return end
    Skin.NoShadow(OWN, fs)
    Bind(fs, function(self, T)
        Theme.SetFont(self, size)
        if colorKey then Paint(self, T[colorKey] or T.text) end
    end)
end

-- Attune's "x" and "_" are font strings with their own colour code baked in, so recolouring them does nothing:
-- they are hidden and ours is drawn on the button instead. The button itself is untouched and keeps working.
local function Glyph(button, kind, tag, hotKey)
    if type(button) ~= "table" or not Skin.Once(button, tag) then return end
    if type(button.text) == "table" then Skin.HideFrame(OWN, button.text) end
    local glyph = Skin.Mine(Kit.Glyph(button, kind, 10, "textDim"))
    glyph:SetPoint("CENTER")
    A.HookScript(button, "OnEnter", function() glyph:SetColorKey(hotKey or "text") end, "nextWindow")
    A.HookScript(button, "OnLeave", function() glyph:SetColorKey("textDim") end, "nextWindow")
end

-- A row keeps Attune's text (it carries Attune's own colours for name and state) and gets our font; the yellow
-- quest highlight gives way to a quiet accent wash.
local function StyleRow(row)
    if type(row) ~= "table" or not Skin.Once(row, "next-row") then return end
    Text(row.text, ROW_SIZE)
    for _, region in ipairs({ row:GetRegions() }) do
        if region:GetObjectType() == "Texture" and region:GetDrawLayer() == "HIGHLIGHT" then
            Skin.Alpha(OWN, region, 0)
        end
    end
    local hl = Skin.Mine(row:CreateTexture(nil, "HIGHLIGHT"))
    hl:SetAllPoints()
    Bind(hl, function(self, T) Paint(self, T.accent, HIGHLIGHT) end)
end

-- Our fill, edge and title bar. They are children of Attune's window at its own frame level, so they sit over its
-- faded art and under everything Attune puts on top (its scroll frame, title, buttons and grip are higher).
local function Build(frame)
    if ours then return ours end
    local level = frame:GetFrameLevel()
    local o = {}
    o.back = Skin.Mine(CreateFrame("Frame", nil, frame))
    o.back:SetAllPoints(frame)
    o.back:SetFrameLevel(level)
    Bind(o.back, function(self, T) Box(self, T, "bg", "border") end)

    o.bar = Skin.Mine(CreateFrame("Frame", nil, frame))
    o.bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    o.bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    o.bar:SetHeight(BAR_H - 1)
    o.bar:SetFrameLevel(level)
    o.bar.fill = o.bar:CreateTexture(nil, "BACKGROUND")
    o.bar.fill:SetAllPoints()
    o.bar.line = Kit.Divider(o.bar)
    o.bar.line:SetPoint("BOTTOMLEFT")
    o.bar.line:SetPoint("BOTTOMRIGHT")
    Bind(o.bar, function(self, T) Paint(self.fill, T.bgAlt) end)
    ours = o
    return o
end

local function Style()
    local p = A.NextParts()
    if not p then return end
    for _, region in ipairs(p.art) do Skin.Alpha(OWN, region, 0) end -- its fill, title bar and gold edges
    local o = Build(p.frame)
    o.back:Show()
    o.bar:SetShown(not p.frame.minimized) -- minimised, only the title bar is left and it is the whole window
    Text(p.title and p.title.text, TITLE_SIZE, "header")
    Text(p.empty, ROW_SIZE, "textDim")
    Glyph(p.close, "close", "next-close", "danger")
    Glyph(p.minBtn, "minus", "next-min")
    for _, row in ipairs(p.rows) do StyleRow(row) end
end

ns.Modules.Register("nextWindow", {
    requires = { "NextWindow" },
    setting = "nextWindow",
    Enable = function()
        A.On("nextLayout", Style, "nextWindow")
        A.On("nextUpdate", Style, "nextWindow")
        Style() -- the window may already be up
    end,
    Disable = function()
        Skin.Undo(OWN)
        if ours then
            ours.back:Hide()
            ours.bar:Hide()
        end
    end,
})
