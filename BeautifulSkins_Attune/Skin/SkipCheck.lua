-- "Will not do" skin: Attune's checkbox at the bottom right of the chain (since 16001-36) in the look of the zoom bar.
-- Attune's button keeps its click, tooltip and wheel. Its own drawing is made invisible and ours lies on top of it
-- without taking the mouse. Attune places the button again on every build of the list view, so we do too.
local _, ns = ...
local A, Theme, Kit, Skin = ns.Attune, ns.Theme, ns.Kit, ns.Skin
local Bind = Theme.Bind

local OWN = {}             -- undo owner for the changes on Attune's button
local HEIGHT, BOX, PAD, GAP = 24, 14, 10, 6
local RIGHT_INSET, BOTTOM_INSET = 34, 10 -- the right edge of the zoom bar: the chain's scroll bar stays free
local LEVEL_ABOVE_CONTENT = 60           -- level of the zoom bar

local d                    -- our drawing, built once (Attune keeps its button too)

local function Repaint(self, T)
    self.pill:SetColors(T.popup, self.hot and T.accent or T.border)
end

local function Build(frame)
    local o = Skin.Mine(CreateFrame("Frame", nil, frame))
    o:SetAllPoints(frame)
    o.pill = Skin.Pill(o)
    o.box = Kit.Panel(o, "inputBg", "border", "input")
    o.box:SetSize(BOX, BOX)
    o.box:SetPoint("RIGHT", o, "RIGHT", -PAD, 0)
    o.mark = Kit.Glyph(o.box, "check", 12, "accent")
    o.mark:SetPoint("CENTER")
    o.label = Kit.Text(o, 12, "text")
    o.label:SetPoint("RIGHT", o.box, "LEFT", -GAP, 0)
    Bind(o, Repaint)
    local function Hot(on)
        o.hot = on
        Repaint(o, Theme.Get())
    end
    A.HookScript(frame, "OnEnter", function() Hot(true) end, "skipCheck")
    A.HookScript(frame, "OnLeave", function() Hot(false) end, "skipCheck")
    return o
end

-- The state of the box. Attune calls its update on every selection and after every click.
local function Update()
    local frame = A.SkipCheck()
    if not frame or not d then return end
    local checked, label = A.SkipCheckState(frame)
    d.mark:SetShown(checked)
    d.label:SetText(label)
    local width = d.label:GetStringWidth() or 0
    if width < 20 then width = 8 * #label end -- the font may not be measured yet
    frame:SetWidth(PAD + width + GAP + BOX + PAD)
    d.pill:Layout()
    d:Show()
end

local function Style()
    local frame, scroll = A.SkipCheck(), A.GraphScroll()
    if not frame or not scroll then return end
    Skin.Remember(OWN, "place", function()
        local points, width, height = Skin.Points(frame), frame:GetWidth(), frame:GetHeight()
        local level = frame:GetFrameLevel()
        return function()
            Skin.RestorePoints(frame, points)
            frame:SetWidth(width)
            frame:SetHeight(height)
            frame:SetFrameLevel(level)
        end
    end)
    for _, region in ipairs({ frame:GetRegions() }) do Skin.Alpha(OWN, region, 0) end
    d = d or Build(frame)
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMRIGHT", scroll.frame, "BOTTOMRIGHT", -RIGHT_INSET, BOTTOM_INSET)
    frame:SetHeight(HEIGHT)
    frame:SetFrameLevel(scroll.content:GetFrameLevel() + LEVEL_ABOVE_CONTENT)
    Update()
end

function Skin.SkipCheckState()
    return d
end

ns.Modules.Register("skipCheck", {
    requires = { "SkipCheck", "GraphScroll" },
    setting = "graph",
    Enable = function()
        A.On("skipCheck", Style, "skipCheck")
        A.On("skipCheckUpdate", Update, "skipCheck")
        Style() -- the list view may already be up
    end,
    Disable = function()
        Skin.Undo(OWN)
        if d then d:Hide() end
    end,
})
