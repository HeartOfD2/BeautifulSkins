-- Results skin: the table of characters in Attune's results view. The table itself is a frame Attune keeps for good (the
-- "holder" with its header strip, frozen name column, divider, header line and two scroll bars); its rows and cells are
-- pooled AceGUI widgets that Attune builds anew on every refresh, one row a moment after the other. The skin draws the
-- holder in the theme (box, header and name strip, lines, thin scroll bars), stripes every other row behind the cells,
-- gives every text of the table and of the controls above it the theme's colour without a shadow, and tints the radio
-- buttons and the level slider. Changes on pooled widgets are taken back when the widget is released.
local _, ns = ...
local A, Theme, Skin = ns.Attune, ns.Theme, ns.Skin
local Paint, Bind = Theme.Paint, Theme.Bind

local OWN = {}                                         -- undo owner for the permanent changes on Attune's own frames
local stripes = setmetatable({}, { __mode = "k" })     -- scroll content -> its stripe textures
local bars = {}                                        -- { v = {track, thumb}, h = {track, thumb} }
local GAP, MAX_STRIPES = 4, 400                        -- Attune puts a 4 px gap above the first row

---------------------------------------------------------------------------
-- Stripes behind the rows
---------------------------------------------------------------------------

local function ZebraColor(T)
    return T.mode == "light" and { 0, 0, 0, 0.045 } or { 1, 1, 1, 0.035 }
end

-- Every second row of a scroll content (names or cells) gets a faint stripe. Rows have Attune's fixed height and follow
-- each other from the 4 px gap on, so the stripes need no knowledge of the rows themselves.
local function Zebra(content)
    if type(content) ~= "table" then return end
    local list = stripes[content]
    if not list then
        list = {}
        stripes[content] = list
    end
    local rowHeight = A.ResultRowHeight()
    local rows = rowHeight > 0 and math.floor(((content:GetHeight() or 0) - GAP) / rowHeight) or 0
    rows = math.max(0, math.min(rows, MAX_STRIPES))
    local used = 0
    for k = 1, rows - 1, 2 do
        used = used + 1
        local tex = list[used]
        if not tex then
            tex = Skin.Mine(content:CreateTexture(nil, "BACKGROUND"))
            Bind(tex, function(self, T) Paint(self, ZebraColor(T)) end)
            list[used] = tex
        end
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(GAP + k * rowHeight))
        tex:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(GAP + k * rowHeight))
        tex:SetHeight(rowHeight)
        tex:Show()
    end
    for i = used + 1, #list do list[i]:Hide() end
end

---------------------------------------------------------------------------
-- The holder
---------------------------------------------------------------------------

-- The single texture of a thin line frame (divider, header line).
local function LineTexture(frame)
    if type(frame) ~= "table" or type(frame.GetRegions) ~= "function" then return nil end
    return (frame:GetRegions())
end

local function StyleHolder(p)
    local holder = p.holder
    if Skin.Once(holder, "results-box") then
        Skin.ClearBackdrop(OWN, holder)
        Skin.Boxed(holder, "canvasBg", "border")
        if p.headerBg then Bind(p.headerBg, function(self, T) Paint(self, T.bgAlt) end) end
        if p.nameShade then Bind(p.nameShade, function(self, T) Paint(self, Skin.With(T.bgAlt, 0.55)) end) end
        for _, frame in ipairs({ p.divider, p.headerLine }) do
            local tex = LineTexture(frame)
            if tex then Bind(tex, function(self, T) Paint(self, T.border) end) end
        end
        if p.vbar then bars.v = Skin.ThinBar(OWN, p.vbar, false, "results") end
        if p.hbar then bars.h = Skin.ThinBar(OWN, p.hbar, true, "results") end
        for _, content in ipairs({ p.bodyContent, p.nameContent }) do
            if content then A.HookScript(content, "OnSizeChanged", function() Zebra(content) end, "results") end
        end
    end
    Zebra(p.bodyContent)
    Zebra(p.nameContent)
end

---------------------------------------------------------------------------
-- The pooled controls above the table
---------------------------------------------------------------------------

local function Release(widget)
    Skin.Undo(widget)
end

-- Opens the undo list of a pooled widget and has AceGUI call us when it is released (the callback list is cleared at
-- every release, so it is set again each time the widget is skinned). A release callback Attune set itself is never
-- replaced: then the widget's OnRelease method is post-hooked instead (once; the hook stays with the pooled widget and
-- does nothing while it is not skinned).
local function Hold(widget)
    Skin.Begin(widget)
    local current = type(widget.events) == "table" and widget.events.OnRelease or nil
    if current == nil or current == Release then
        if type(widget.SetCallback) == "function" then widget:SetCallback("OnRelease", Release) end
    elseif Skin.Once(widget, "results-release") then
        A.HookMethod(widget, "OnRelease", Release, "results")
    end
end

local function StyleRadio(widget, T)
    Hold(widget)
    Skin.VertexColor(widget, widget.checkbg, T.textDim)
    Skin.VertexColor(widget, widget.check, T.accent)
    Skin.VertexColor(widget, widget.highlight, Skin.With(T.accent, 0.35))
    Skin.FlatText(widget, widget.text, T.text)
end

local function StyleSlider(widget, T)
    Hold(widget)
    Skin.FlatText(widget, widget.label, T.text)
    Skin.FlatText(widget, widget.lowtext, T.textDim)
    Skin.FlatText(widget, widget.hightext, T.textDim)
    Skin.FlatText(widget, widget.editbox, T.text)
    Skin.Backdrop(widget, widget.editbox, T.inputBg, T.border)
    local slider = widget.slider
    local thumb = type(slider) == "table" and type(slider.GetThumbTexture) == "function" and slider:GetThumbTexture() or nil
    Skin.VertexColor(widget, thumb, T.accent)
end

local function StyleControls()
    local controls = A.ResultControls()
    local T = Theme.Get()
    if controls.title then
        Hold(controls.title)
        Skin.FlatText(controls.title, controls.title.label, T.text)
    end
    for _, radio in ipairs(controls.radios) do StyleRadio(radio, T) end
    if controls.slider then StyleSlider(controls.slider, T) end
end

---------------------------------------------------------------------------
-- The texts of the table (column heads, names, levels, percentages)
---------------------------------------------------------------------------

-- A text widget in the theme's colour without a shadow. Returns false when it was done already (unless all = true:
-- after a theme change every text is painted again).
local function StyleLabel(widget, color, all)
    if Skin.IsSkinned(widget) and not all then return false end
    Hold(widget)
    Skin.FlatText(widget, widget.label, color)
    return true
end

-- Attune appends the rows one by one at the end of a container: walk back from the end and stop at the first row that
-- is done, so each new row costs only its own texts. The column heads are texts right in their container.
local function StyleContainer(container, color, all)
    if not container then return end
    local children = container.children
    for i = #children, 1, -1 do
        local child = children[i]
        if type(child) == "table" then
            if child.type == "Label" or child.type == "InteractiveLabel" then
                StyleLabel(child, color, all)
            elseif type(child.children) == "table" then
                if Skin.IsSkinned(child) and not all then return end
                Hold(child) -- marks the row; released with it
                A.EachLabel(child, function(label) StyleLabel(label, color, all) end)
            end
        end
    end
end

local function StyleTable(all)
    local T = Theme.Get()
    local table = A.ResultTable()
    StyleContainer(table.heads, T.header, all)
    StyleContainer(table.header, T.textDim, all)
    StyleContainer(table.names, T.text, all)
    StyleContainer(table.body, T.text, all)
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

local function Apply(all)
    local parts = A.ResultParts()
    if parts then StyleHolder(parts) end
    if A.ResultsGroup() then StyleControls() end
    if parts then StyleTable(all) end
end

-- Attune added a row (or finished the list): style what is new.
local function OnRows()
    if A.IsListView() then return end
    StyleTable(false)
end

-- The holder exists after the first results view; the controls are built anew on each switch to it.
local function OnView()
    if not A.IsListView() then Apply() end
end

-- Frames the tests and the probe may look at.
function Skin.ResultsState()
    return { stripes = stripes, bars = bars, apply = Apply, zebra = Zebra, rows = OnRows }
end

Theme.OnChange(function()
    if ns.Modules.IsActive("results") and not A.IsListView() then ns.Modules.Run("results", Apply, true) end
end)

ns.Modules.Register("results", {
    requires = { "ToggleView", "Results", "Lang" },
    setting = "results",
    Enable = function()
        A.On("resultList", function() Apply(false) end, "results")
        A.On("resultRows", OnRows, "results")
        A.On("view", OnView, "results")
        Apply()
    end,
    Disable = function()
        Skin.Undo(OWN)
        local p = A.ResultParts()
        if p then Skin.Unbox(p.holder) end
        for _, list in pairs(stripes) do
            for _, tex in ipairs(list) do tex:Hide() end
        end
        for _, bar in pairs(bars) do
            bar.track:Hide()
            bar.thumb:Hide()
        end
    end,
})
