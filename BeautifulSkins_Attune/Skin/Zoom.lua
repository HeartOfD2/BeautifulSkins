-- Zoom skin: Attune's zoom slider (a pooled AceGUI slider) is hidden and replaced by a zoom bar at the top right of the
-- chain: minus, percent (click = 100 %), plus, fit. Ctrl+mouse wheel over the chain zooms; the wheel alone and
-- Shift+wheel keep Attune's own behaviour. From 10 to 150 %: minus/plus in steps of 25 % above 50 % and in smaller ones
-- below, Ctrl+wheel in steps of 10 % (5 % below 50 %). From 50 to 100 % through Attune's own zoom, outside it Attune's
-- stored zoom is set and the chain scaled the same way (Attune itself stays within 50-100 %; above 100 % only with the
-- setting "zoomAbove100"). Fit shows the whole chain, width and height, up to 100 %. The zoom is kept per account and
-- restored after login (Attune clamps its own at login).
local _, ns = ...
local L, A, Theme, Kit, Skin = ns.L, ns.Attune, ns.Theme, ns.Kit, ns.Skin
local Paint, Bind = Theme.Paint, Theme.Bind

local MIN, MAX = A.ZoomRange()
local BUTTON_STEPS = { 0.1, 0.15, 0.2, 0.25, 0.3, 0.4, 0.5, 0.75, 1, 1.25, 1.5 }
local WHEEL_STEPS = {}     -- 5 % up to 50 %, then 10 %
for i = 2, 10 do WHEEL_STEPS[#WHEEL_STEPS + 1] = i * 0.05 end
for i = 6, 15 do WHEEL_STEPS[#WHEEL_STEPS + 1] = i * 0.1 end
local WHEEL_STEP = 45      -- content units AceGUI scrolls per wheel notch; taken back when Ctrl+wheel zooms
local SCROLLBAR_ROOM = 20  -- the chain's scroll bar takes this much from the right edge when it shows
-- free space beside the chain after "fit": Attune keeps its pan within 60 units past half the view, so 32 on each side
-- leaves the whole chain visible whatever the pan; below it a little air
local FIT_MARGIN, FIT_BOTTOM, FIT_MAX, FIT_GRID = 32, 16, 1, 0.05
local BAR_H, BUTTON = 28, 22

local Z                    -- the zoom bar, built once
local hiddenSlider         -- Attune's slider we hid last (shown again when the module is switched off)

local function Setting(key, default)
    local settings = ns.db and ns.db.settings
    if settings and settings[key] ~= nil then return settings[key] end
    return default
end

local function MaxZoom()
    return Setting("zoomAbove100", true) ~= false and MAX or A.AttuneZoomMax()
end

local function Clamp(zoom)
    return math.max(MIN, math.min(MaxZoom(), zoom))
end

---------------------------------------------------------------------------
-- Zooming
---------------------------------------------------------------------------

local function Update()
    if not Z then return end
    local zoom = A.Zoom()
    Z.value.text:SetText(("%d %%"):format(math.floor(zoom * 100 + 0.5)))
    local function Enable(button, on)
        button:SetEnabled(on)
        button:SetAlpha(on and 1 or 0.35)
    end
    Enable(Z.minus, zoom > MIN + 0.001)
    Enable(Z.plus, zoom < MaxZoom() - 0.001)
end

-- Zooms and keeps the point in the middle of the view where it was. offsetBefore: the scroll offset to keep the middle
-- of (Ctrl+wheel: Attune's own wheel handler has already scrolled one notch).
local function ZoomTo(zoom, offsetBefore)
    zoom = Clamp(zoom)
    local old = A.Zoom()
    if math.abs(zoom - old) < 0.001 then
        Update()
        return
    end
    local offset, view = A.GraphScrollState()
    if offsetBefore then offset = offsetBefore end
    local header = A.GraphHeader() or 0
    local anchor = offset and view and (offset + view / 2 - header) / old or nil
    local applied = A.ApplyZoom(zoom)
    if not applied then return end
    if ns.db then ns.db.settings.zoom = applied end
    Skin.GraphRefresh()
    if Skin.SearchResize then Skin.SearchResize() end
    A.FitGraphContent()
    if anchor and anchor > 0 then A.ScrollGraphTo(header + anchor * applied - view / 2) end
    Update()
end

-- One step up (dir 1) or down (-1) on a list of zoom values; a zoom between two values goes to the next one.
local function Step(dir, steps, offsetBefore)
    local zoom = A.Zoom()
    local first, last, by = 1, #steps, 1
    if dir < 0 then first, last, by = #steps, 1, -1 end
    for i = first, last, by do
        local value = steps[i]
        if (dir > 0 and value > zoom + 0.001) or (dir < 0 and value < zoom - 0.001) then
            ZoomTo(value, offsetBefore)
            return
        end
    end
    Update()
end

-- Largest zoom (5 % grid, 10-100 %) at which the whole chain fits the view: its widest stage with a margin on both
-- sides, and its height in what is left below the header (the header does not zoom).
local function FitZoom()
    local extent, width = A.ChainExtent(), A.GraphViewWidth()
    if not width or extent <= 0 then return nil end
    local zoom = math.min(FIT_MAX, (width - FIT_MARGIN * 2) / (extent * 2))
    local bottom, height = A.ChainBottom(), A.GraphViewHeight()
    if height and bottom > 0 then zoom = math.min(zoom, (height - A.GraphTop() - FIT_BOTTOM) / bottom) end
    return math.max(MIN, math.floor(zoom / FIT_GRID + 1e-6) * FIT_GRID)
end

local function Fit()
    local zoom = FitZoom()
    if not zoom then return end
    ZoomTo(zoom)
    A.ScrollGraphTo(0)
end

local function OnWheel(frame, delta)
    local scroll = A.GraphScroll()
    if not scroll or frame ~= scroll.scrollframe or type(delta) ~= "number" or delta == 0 then return end
    if not (IsControlKeyDown and IsControlKeyDown()) or (IsShiftKeyDown and IsShiftKeyDown()) then return end
    local dir = delta > 0 and 1 or -1
    local offset, view, content, shown = A.GraphScrollState()
    local before
    if shown and offset then before = math.max(0, math.min(content - view, offset + WHEEL_STEP * dir)) end
    Step(dir, WHEEL_STEPS, before)
end

---------------------------------------------------------------------------
-- The bar
---------------------------------------------------------------------------

local function Build(host)
    local z = Skin.Mine(CreateFrame("Frame", nil, host))
    z:SetHeight(BAR_H)
    z:EnableMouse(true) -- clicks between the buttons must not start dragging the chain
    z.pill = Skin.Pill(z)
    Bind(z, function(self, T) self.pill:SetColors(T.popup, T.border) end)

    z.minus = Kit.IconButton(z, BUTTON, "minus", function() Step(-1, BUTTON_STEPS) end, L["Zoom out"])
    z.minus:SetPoint("LEFT", z, "LEFT", 4, 0)
    z.value = CreateFrame("Button", nil, z)
    z.value:SetSize(50, BUTTON)
    z.value:SetPoint("LEFT", z.minus, "RIGHT", 2, 0)
    z.value.text = Kit.Text(z.value, 12, "text")
    z.value.text:SetPoint("CENTER")
    z.value.hl = z.value:CreateTexture(nil, "HIGHLIGHT")
    z.value.hl:SetAllPoints()
    Bind(z.value.hl, function(self, T) Paint(self, T.hover) end)
    z.value:SetScript("OnClick", function() ZoomTo(1) end)
    Kit.Tooltip(z.value, { L["Zoom"], L["Click: 100 %. Ctrl+mouse wheel over the chain: zoom."] }, "ANCHOR_BOTTOM")
    z.plus = Kit.IconButton(z, BUTTON, "plus", function() Step(1, BUTTON_STEPS) end, L["Zoom in"])
    z.plus:SetPoint("LEFT", z.value, "RIGHT", 2, 0)
    z.sep = z:CreateTexture(nil, "ARTWORK")
    z.sep:SetSize(1, 14)
    z.sep:SetPoint("LEFT", z.plus, "RIGHT", 3, 0)
    Theme.Crisp(z.sep)
    Bind(z.sep, function(self, T) Paint(self, T.border) end)
    z.fit = Kit.IconButton(z, BUTTON, "fit", Fit, L["Fit the whole chain"])
    z.fit:SetPoint("LEFT", z.sep, "RIGHT", 3, 0)
    z:SetWidth(4 + BUTTON + 2 + 50 + 2 + BUTTON + 3 + 1 + 3 + BUTTON + 6)
    z.pill:Layout()
    z:Hide()
    return z
end

-- Puts the bar on the chain area (after every build of the chain or of Attune's slider) and hides Attune's slider.
local function Attach()
    local scroll, host = A.GraphScroll(), A.MainFrame()
    if not scroll or not host then
        if Z then Z:Hide() end
        return
    end
    local slider = A.ZoomSlider()
    if slider and type(slider.frame) == "table" then
        slider.frame:Hide() -- AceGUI hides it on release anyway: nothing to take back for the pool
        hiddenSlider = slider
    end
    Z = Z or Build(host)
    Z:ClearAllPoints()
    -- on the outer frame, which keeps its width when the scroll bar appears; the bar's room stays free
    Z:SetPoint("TOPRIGHT", scroll.frame, "TOPRIGHT", -(SCROLLBAR_ROOM + 14), -10)
    Z:SetFrameStrata(scroll.frame:GetFrameStrata())
    Z:SetFrameLevel(scroll.content:GetFrameLevel() + 60)
    local sf = scroll.scrollframe
    if Skin.Once(sf, "zoom-wheel") then A.HookScript(sf, "OnMouseWheel", OnWheel, "zoom") end
    local root = A.GraphRoot()
    Z:SetShown(A.IsListView() and root ~= nil and root:IsShown())
    Update()
end

-- Restores the saved zoom (Attune clamps its own to 100 % at login) and keeps it within the allowed range.
local function Restore()
    local saved = Setting("zoom", nil)
    local zoom = type(saved) == "number" and saved or A.StoredZoom() or 1
    zoom = Clamp(zoom)
    if math.abs(zoom - (A.StoredZoom() or 1)) > 0.001 or A.Zoom() > MaxZoom() + 0.001 then
        if A.GraphRoot() and A.GraphScroll() then ZoomTo(zoom) else A.ApplyZoom(zoom) end
    end
end

-- The setting "zoom above 100 %" changed: limit the zoom and the bar.
function Skin.ZoomApplySettings()
    if not ns.Modules.IsActive("zoom") then return end
    ns.Modules.Run("zoom", function()
        if A.Zoom() > MaxZoom() + 0.001 then ZoomTo(MaxZoom()) end
        Update()
    end)
end

function Skin.ZoomState()
    return { bar = Z, step = Step, fit = Fit, fitZoom = FitZoom, zoomTo = ZoomTo, wheel = OnWheel, max = MaxZoom,
        min = MIN, restore = Restore }
end

ns.Modules.Register("zoom", {
    requires = { "Zoom", "Select", "GraphRoot", "GraphScroll", "StoredZoom", "Pan" },
    setting = "zoom",
    Enable = function()
        A.On("zoomSlider", Attach, "zoom")
        A.On("select", Attach, "zoom")
        A.On("view", function()
            if Z and not A.IsListView() then Z:Hide() end
        end, "zoom")
        Restore()
        if A.GraphScroll() then Attach() end
    end,
    Disable = function()
        if Z then Z:Hide() end
        -- only while the slider still sits on Attune's chain (a released one may belong to another addon now)
        local scroll = A.GraphScroll()
        local frame = hiddenSlider and hiddenSlider.frame
        if scroll and type(frame) == "table" and frame:GetParent() == scroll.frame then frame:Show() end
    end,
})
