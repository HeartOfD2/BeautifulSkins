-- List skin: Attune's list is an AceGUI TreeGroup that is pooled across addons. Its row buttons keep working and stay in
-- place (so Attune's scrolling and click logic is untouched) but their own text, icon and +/- are made invisible; a
-- decoration frame per row, owned by us and anchored to the button, draws the themed row on top of the list area.
-- Everything changed on the widget itself is remembered and taken back when the widget is released (Skin.Undo).
-- Rows keep Attune's pitch (the widget computes how many rows fit from it), so the rows are as high as Attune's.
local _, ns = ...
local A, Theme, Kit, Skin = ns.Attune, ns.Theme, ns.Kit, ns.Skin
local Paint, Bind, Refresh = Theme.Paint, Theme.Bind, Theme.Refresh

local ICON = 16
local rows = {}                                       -- decoration frames; row i belongs to button i
local ofButton = setmetatable({}, { __mode = "k" })   -- button -> its decoration frame (only while skinned)
local shared                                          -- scroll bar mirror and divider, built once
local redrawCount = 0                                 -- for the offline test: redraws of Attune's own list
-- for the probe, per frame: refreshes of Attune's list seen and redraws done in the last frame that had any, and the
-- time of the last redraw (all of it and the part spent reading the rows)
local stats = { at = nil, refreshes = 0, redraws = 0, maxRefreshes = 0, lastMs = 0, rowMs = 0 }

local function Clock()
    return type(debugprofilestop) == "function" and debugprofilestop() or nil
end

-- GetTime() stays the same for a whole frame.
local function FrameStamp()
    return type(GetTime) == "function" and GetTime() or nil
end

local function Count(key)
    local stamp = FrameStamp()
    if stats.at ~= stamp then stats.at, stats.refreshes, stats.redraws = stamp, 0, 0 end
    stats[key] = stats[key] + 1
    if stats.refreshes > stats.maxRefreshes then stats.maxRefreshes = stats.refreshes end
end

---------------------------------------------------------------------------
-- Shared frames: thin scroll bar next to the list, divider between list and chain
---------------------------------------------------------------------------

local function Fill(frame, layer)
    frame.fill = frame:CreateTexture(nil, layer or "BACKGROUND")
    frame.fill:SetAllPoints()
    return frame.fill
end

local function Shared(host)
    if shared then return shared end
    local s = {}
    s.track = Skin.Mine(CreateFrame("Frame", nil, host))
    s.track:SetWidth(5)
    Fill(s.track)
    Bind(s.track, function(self, T) Paint(self.fill, T.track) end)
    s.thumb = Skin.Mine(CreateFrame("Frame", nil, host))
    s.thumb:SetSize(5, 24)
    Fill(s.thumb)
    Bind(s.thumb, function(self, T) Paint(self.fill, T.thumb) end)
    s.divider = Skin.Mine(CreateFrame("Frame", nil, host))
    s.divider:SetWidth(1)
    Fill(s.divider)
    Bind(s.divider, function(self, T) Paint(self.fill, self.hot and T.accent or T.border) end)
    s.track:Hide(); s.thumb:Hide(); s.divider:Hide()
    shared = s
    return s
end

---------------------------------------------------------------------------
-- One decoration frame per list row
---------------------------------------------------------------------------

local function NewRow(host)
    local d = Skin.Mine(CreateFrame("Frame", nil, host))
    d.hover = d:CreateTexture(nil, "BACKGROUND", nil, 1)
    d.hover:SetAllPoints()
    d.select = d:CreateTexture(nil, "BACKGROUND", nil, 2)
    d.select:SetAllPoints()
    d.bar = d:CreateTexture(nil, "BACKGROUND", nil, 3)
    d.bar:SetPoint("TOPLEFT")
    d.bar:SetPoint("BOTTOMLEFT")
    d.bar:SetWidth(2)
    d.icon = d:CreateTexture(nil, "ARTWORK")
    d.icon:SetSize(ICON, ICON)
    d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    d.name = Kit.Text(d, 12, "text")
    d.name:SetWordWrap(false)
    d.count = Kit.Text(d, 11, "textDim")
    d.count:SetJustifyH("RIGHT")
    d.count:SetWidth(40)
    d.chevron = Kit.Glyph(d, "right", 10, "textDim")
    d.check = Kit.Glyph(d, "check", 12, "success")
    Bind(d, function(self, T)
        Paint(self.hover, T.mode == "light" and { 0, 0, 0, 0.05 } or { 1, 1, 1, 0.04 })
        Paint(self.select, Skin.With(T.accent, 0.12))
        Paint(self.bar, T.accent)
    end)
    d:Hide()
    return d
end

-- Anchors that only depend on the kind of row (expansion row, group row, attunement row).
local function Place(d, kind)
    d.name:ClearAllPoints()
    d.count:ClearAllPoints()
    d.chevron:ClearAllPoints()
    d.check:ClearAllPoints()
    d.count:SetPoint("RIGHT", d, "RIGHT", -10, 0)
    d.check:SetPoint("RIGHT", d, "RIGHT", -10, 0)
    if kind == "leaf" then
        d.chevron:Hide()
        d.icon:ClearAllPoints()
        d.icon:SetPoint("LEFT", d, "LEFT", 30, 0)
        d.name:SetPoint("LEFT", d.icon, "RIGHT", 7, 0)
        d.name:SetPoint("RIGHT", d, "RIGHT", -46, 0)
    else
        local indent = kind == "expansion" and 10 or 18
        d.icon:Hide()
        d.check:Hide()
        d.chevron:SetPoint("LEFT", d, "LEFT", indent, 0)
        d.chevron:Show()
        d.name:SetPoint("LEFT", d, "LEFT", indent + 16, 0)
        d.name:SetPoint("RIGHT", d, "RIGHT", kind == "expansion" and -10 or -50, 0)
    end
    d.kind = kind
end

local function SetColor(fs, key)
    if fs.fnColor ~= key then Kit.SetTextColor(fs, key) end
end

local function SetSize(fs, size)
    if fs.fnSize ~= size then Kit.SetTextSize(fs, size) end
end

-- Attune (16001-33+) can draw larger list rows (18 / 24 / 30 px): icon and text grow with the row.
local function RowSizes(button)
    local h = button:GetHeight() or 18
    if h >= 28 then return 24, 16, 13 end
    if h >= 22 then return 20, 14, 12 end
    return ICON, 12, 10
end

local function Draw(d, button, info)
    local T = Theme.Get()
    local icon, textSize, sectionSize = RowSizes(button)
    d.select:SetShown(info.selected)
    d.bar:SetShown(info.selected)
    d.hover:SetShown(button:IsMouseOver() and true or false)
    if info.section then
        local kind = info.level <= 1 and "expansion" or "group"
        if d.kind ~= kind then Place(d, kind) end
        local arrow = info.expanded and "down" or "right"
        if d.chevron.kind ~= arrow then d.chevron:SetKind(arrow) end
        d.name:SetText(Skin.Upper(info.text))
        SetSize(d.name, sectionSize)
        SetColor(d.name, kind == "expansion" and "header" or "textDim")
        if kind == "group" and info.total then
            d.count:SetText(("%d/%d"):format(info.done or 0, info.total))
            SetColor(d.count, (info.total > 0 and info.done == info.total) and "success" or "textDim")
            d.count:Show()
        else
            d.count:SetText("")
        end
        d.icon:Hide()
        d.check:Hide()
        return
    end
    if d.kind ~= "leaf" then Place(d, "leaf") end
    local name = info.text
    if info.levels then name = name .. " " .. Skin.Hex(T.textDim) .. info.levels .. "|r" end
    d.name:SetText(name)
    SetSize(d.name, textSize)
    SetColor(d.name, info.dim and "textDim" or "text")
    if info.icon then
        if d.iconSize ~= icon then
            d.iconSize = icon
            d.icon:SetSize(icon, icon)
        end
        d.icon:SetTexture(info.icon)
        d.icon:SetDesaturated(info.dim and true or false)
        d.icon:SetAlpha(info.dim and 0.6 or 1)
        d.icon:Show()
    else
        d.icon:Hide()
    end
    local done = info.done or (type(info.progress) == "number" and info.progress >= 100)
    d.check:SetShown(done and true or false)
    if done then
        d.count:SetText("")
    elseif info.dim or type(info.progress) ~= "number" then
        d.count:SetText("–")
        SetColor(d.count, "textDim")
    else
        d.count:SetText(("%d%%"):format(info.progress))
        SetColor(d.count, "textDim")
    end
end

---------------------------------------------------------------------------
-- The widget's own parts
---------------------------------------------------------------------------

-- Every text of a row button is hidden, not only the field AceGUI writes to: the button's own font string and any
-- other one on it. Hidden, not faded: on hover and selection the button gives its text the other font object again
-- (expansion rows have two different ones), which sets the alpha back to 1.
local function HideTexts(tree, button)
    Skin.HideFrame(tree, button.text)
    if type(button.GetFontString) == "function" then Skin.HideFrame(tree, button:GetFontString()) end
    for _, region in ipairs({ button:GetRegions() }) do
        if region:GetObjectType() == "FontString" then Skin.HideFrame(tree, region) end
    end
end

local function OnButtonHover(button, on)
    local deco = ofButton[button]
    if not deco then return end
    deco.hover:SetShown(on)
    if button.text and button.text:IsShown() then HideTexts(button.obj, button) end
end

-- Row buttons stay clickable but draw nothing; the decoration frame shows the row.
local function StyleButton(tree, button, d)
    HideTexts(tree, button)
    Skin.Alpha(tree, button.icon, 0)
    Skin.Alpha(tree, button.toggle, 0)
    if type(button.GetHighlightTexture) == "function" then Skin.Alpha(tree, button:GetHighlightTexture(), 0) end
    ofButton[button] = d
    if Skin.Once(button, "hover") then
        A.HookScript(button, "OnEnter", function(b) OnButtonHover(b, true) end, "tree")
        A.HookScript(button, "OnLeave", function(b) OnButtonHover(b, false) end, "tree")
    end
    -- a row exists only while its button does: Attune hides the buttons without a list refresh (its icon grid)
    if Skin.Once(button, "shown") then
        A.HookScript(button, "OnHide", function(b)
            local deco = ofButton[b]
            if deco then deco:Hide() end
        end, "tree")
        A.HookScript(button, "OnShow", function(b)
            local deco = ofButton[b]
            if deco and deco.anchor == b then deco:Show() end
        end, "tree")
    end
end

-- Dragging the scroll bar makes Attune refresh its list on every frame, so this runs in the hot path: everything
-- here is skipped once it already holds. The alpha and the mouse state are still looked at every time rather than
-- set once, because a widget that comes back from the pool brings its own back with it.
local function Fade(tree, region)
    if type(region) ~= "table" or type(region.GetAlpha) ~= "function" then return end
    if (region:GetAlpha() or 1) == 0 then return end
    Skin.Alpha(tree, region, 0)
end

local function Mute(tree, frame)
    if type(frame) ~= "table" or type(frame.GetAlpha) ~= "function" then return end
    local mouse = type(frame.IsMouseEnabled) == "function" and frame:IsMouseEnabled() or false
    if (frame:GetAlpha() or 1) == 0 and not mouse then return end
    Skin.Conceal(tree, frame)
end

-- true when the part has to be anchored to `to` again (and then it is ready for the SetPoint calls).
local function Rebind(part, to)
    if part.boundTo == to then return false end
    part:ClearAllPoints()
    part.boundTo = to
    return true
end

-- Puts our thumb where the slider's value says Attune's thumb is: the thumb travels the bar's height minus its own.
local function PlaceThumb(s)
    local bar, source = s.bar, s.source
    if not (bar and source) then return end
    local height, size = bar:GetHeight(), source:GetHeight()
    if type(height) ~= "number" then height = 0 end
    if type(size) ~= "number" or size <= 0 then size = 24 end
    local min, max = bar:GetMinMaxValues()
    local value = bar:GetValue()
    if type(min) ~= "number" or type(max) ~= "number" or type(value) ~= "number" then min, max, value = 0, 0, 0 end
    local range = max - min
    local fraction = range > 0 and (value - min) / range or 0
    if fraction < 0 then fraction = 0 elseif fraction > 1 then fraction = 1 end
    local offset = -math.floor(fraction * math.max(0, height - size) + 0.5)
    if s.thumbBar ~= bar or s.thumbOffset ~= offset or s.thumbSize ~= size then
        s.thumbBar, s.thumbOffset, s.thumbSize = bar, offset, size
        s.thumb:ClearAllPoints()
        s.thumb:SetHeight(size)
        s.thumb:SetPoint("TOP", bar, "TOP", 0, offset)
    end
end

local function StyleScrollbar(tree, bar, s)
    if type(bar) ~= "table" then return end
    local thumb = type(bar.GetThumbTexture) == "function" and bar:GetThumbTexture() or nil
    if not thumb then return end -- no thumb to mirror: leave Attune's own bar alone
    -- Attune shortens the list frame's height while it refreshes (its "large" rows are taller than the 18 px the tree
    -- counts with) and does that again for every refresh nested in another one. While the bar is dragged the engine
    -- hands over fractional values, the tree rounds them and sets the bar again, which fires a nested refresh: that
    -- one measures with a twice shortened frame and leaves a different range (0..31 instead of 0..23), so the thumb
    -- jumped between two places on every mouse move. With whole steps while dragging there is no nested refresh.
    if type(bar.SetObeyStepOnDrag) == "function" then
        Skin.Remember(tree, "scroll-whole-steps", function()
            local was = type(bar.GetObeyStepOnDrag) == "function" and bar:GetObeyStepOnDrag() or false
            bar:SetObeyStepOnDrag(true)
            return function() bar:SetObeyStepOnDrag(was and true or false) end
        end)
    end
    for _, region in ipairs({ bar:GetRegions() }) do Fade(tree, region) end
    Fade(tree, thumb)
    for _, child in ipairs({ bar:GetChildren() }) do Mute(tree, child) end
    if Rebind(s.track, bar) then
        s.track:SetPoint("TOP", bar, "TOP", 0, 0)
        s.track:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    end
    -- Not anchored to Attune's thumb texture: while the bar is dragged, the engine moves that texture on its own
    -- and a frame anchored to it follows late (ours hung behind the mouse). The place is worked out from the
    -- slider's value instead and set whenever the value, the range or the size changes.
    s.bar, s.source = bar, thumb
    if Skin.Once(bar, "tree-thumb-hooks") then
        for _, script in ipairs({ "OnValueChanged", "OnMinMaxChanged", "OnSizeChanged", "OnShow" }) do
            A.HookScript(bar, script, function() PlaceThumb(s) end, "tree")
        end
    end
    PlaceThumb(s)
    local level = bar:GetFrameLevel()
    if s.track:GetFrameLevel() ~= level + 1 then s.track:SetFrameLevel(level + 1) end
    if s.thumb:GetFrameLevel() ~= level + 2 then s.thumb:SetFrameLevel(level + 2) end
    local shown = bar:IsShown() and true or false
    s.track:SetShown(shown)
    s.thumb:SetShown(shown)
end

local function Hot(dragger, on)
    if not (shared and A.IsOwnTree(dragger.obj)) then return end
    -- Attune's hover is a white bar on the dragger: keep it clear, our divider shows the hover instead
    if type(dragger.SetBackdropColor) == "function" then dragger:SetBackdropColor(1, 1, 1, 0) end
    shared.divider.hot = on
    shared.divider:SetWidth(on and 2 or 1)
    Refresh(shared.divider)
end

local function StyleDivider(dragger, s)
    if type(dragger) ~= "table" then return end
    s.divider:ClearAllPoints()
    s.divider:SetPoint("TOP", dragger, "TOP", 0, 0)
    s.divider:SetPoint("BOTTOM", dragger, "BOTTOM", 0, 0)
    s.divider:SetFrameLevel(dragger:GetFrameLevel() + 1)
    s.divider:Show()
    if Skin.Once(dragger, "hover") then
        A.HookScript(dragger, "OnEnter", function(frame) Hot(frame, true) end, "tree")
        A.HookScript(dragger, "OnLeave", function(frame) Hot(frame, false) end, "tree")
    end
end

local function HideAll()
    for _, d in pairs(rows) do d:Hide() end
    for button in pairs(ofButton) do ofButton[button] = nil end
    if shared then
        shared.track:Hide(); shared.thumb:Hide(); shared.divider:Hide()
        shared.track.boundTo, shared.thumb.boundTo = nil, nil -- anchored again on the next skin (see Rebind)
        shared.thumbBar = nil -- and the thumb placed again (see PlaceThumb)
        shared.divider.hot = false
        shared.divider:SetWidth(1)
    end
end

---------------------------------------------------------------------------
-- Redraw (after every RefreshTree of Attune's list) and release
---------------------------------------------------------------------------

local lastTree                                       -- the list drawn last (for the probe)
local drawnAt                                        -- frame of the last redraw
local pending                                        -- list refreshed again in that frame, drawn next frame

local function Redraw(tree)
    if not A.IsOwnTree(tree) then return end
    local start = Clock()
    local rowTime = 0
    redrawCount = redrawCount + 1
    Count("redraws")
    drawnAt, pending = FrameStamp(), nil
    lastTree = tree
    local parts, host = A.TreeParts(tree), A.MainFrame()
    if not parts or not host then return end
    Skin.Begin(tree)
    local T = Theme.Get()
    local s = Shared(host)
    -- the list area shows the window fill, the chain pane the canvas colour; Attune's art edges stay invisible
    Skin.Backdrop(tree, parts.treeframe, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
    Skin.Backdrop(tree, parts.border, T.canvasBg, { 0, 0, 0, 0 })

    for i, button in ipairs(parts.buttons) do
        local d = rows[i]
        if not d then
            d = NewRow(host)
            rows[i] = d
        end
        local rowStart = Clock()
        local info = button:IsShown() and A.RowInfo(button) or nil
        local rowStop = Clock()
        if rowStart and rowStop then rowTime = rowTime + (rowStop - rowStart) end
        if info then
            StyleButton(tree, button, d)
            if d.anchor ~= button then
                d:ClearAllPoints()
                d:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
                d:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
                d.anchor = button
            end
            if d:GetFrameStrata() ~= button:GetFrameStrata() then d:SetFrameStrata(button:GetFrameStrata()) end
            d:SetFrameLevel(math.max(0, button:GetFrameLevel() - 1))
            Draw(d, button, info)
            d:Show()
        else
            d:Hide()
        end
    end
    for i = #parts.buttons + 1, #rows do rows[i]:Hide() end

    StyleScrollbar(tree, parts.scrollbar, s)
    StyleDivider(parts.dragger, s)
    local stop = Clock()
    if start and stop then stats.lastMs, stats.rowMs = stop - start, rowTime end
end

local function Flush()
    local tree = pending
    pending = nil
    if tree and A.Tree() == tree and Skin.IsSkinned(tree) then Redraw(tree) end
end

-- Attune refreshes its list many times in one go (switching to the list expands every group: one refresh each). The
-- first refresh of a frame is drawn at once, the later ones of that frame once, at the next frame — unless the view
-- switch draws first, when Attune is done.
local function OnRefresh(tree)
    if not A.IsOwnTree(tree) then return end
    Count("refreshes")
    local stamp = FrameStamp()
    if stamp == nil or drawnAt ~= stamp or not C_Timer then
        Redraw(tree)
        return
    end
    local queued = pending ~= nil
    pending = tree
    if not queued then C_Timer.After(0, function() ns.Modules.Run("tree", Flush) end) end
end

local function Release(tree)
    if not Skin.IsSkinned(tree) then return end
    Skin.Undo(tree)
    HideAll()
    pending = nil
end

local function SkinTree(tree)
    if not tree or not A.IsOwnTree(tree) then return end
    Skin.Begin(tree)
    if Skin.Once(tree, "hooks") then
        A.HookMethod(tree, "RefreshTree", OnRefresh, "tree")
        A.HookMethod(tree, "OnRelease", Release, "tree")
    end
    Redraw(tree)
end

-- Attune's grid view and the switch above the list: hidden while the setting is on (the list is forced).
local function ApplyIconView()
    local hide = not ns.db or ns.db.settings.hideIconView ~= false
    A.HideViewToggle(hide)
    if hide then A.ForceListView() end
end

function Skin.ApplyIconView()
    if ns.Modules.IsActive("tree") then ns.Modules.Run("tree", ApplyIconView) end
end

-- Frames and numbers the tests and the probe may look at.
function Skin.TreeState()
    return { rows = rows, shared = shared, ofButton = ofButton, redraws = function() return redrawCount end,
        lastTree = function() return lastTree end, stats = stats }
end

-- Theme, accent or status changes: the rows carry colours in their text, so draw them again.
Theme.OnChange(function()
    local tree = A.Tree()
    if tree and Skin.IsSkinned(tree) then ns.Modules.Run("tree", Redraw, tree) end
end)

ns.Modules.Register("tree", {
    requires = { "ToggleView", "Tree", "IconView", "MainFrame" },
    setting = "tree",
    Enable = function()
        A.On("view", function()
            ApplyIconView()
            SkinTree(A.Tree())
        end, "tree")
        A.On("iconView", function(enabled)
            if enabled then ApplyIconView() end
        end, "tree")
        ApplyIconView()
        SkinTree(A.Tree())
    end,
    Disable = function()
        local tree = A.Tree()
        if tree then Release(tree) end
        A.HideViewToggle(false)
    end,
})
