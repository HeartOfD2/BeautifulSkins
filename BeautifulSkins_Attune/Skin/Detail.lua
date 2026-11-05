-- Detail skin: the quest detail panel (rewards and map) that covers Attune's list when a quest card is clicked, the
-- reward window beside Attune's window and the quest giver hint. All three are Attune's own frames, created once and
-- never pooled, so the changes are permanent for the session (taken back when the module is switched off). Attune
-- lays the panel out again on every quest or item event; its text colours (item quality) and its geometry are left
-- alone, the skin draws the box, fonts, the accent line, the map frame and a quality-coloured frame around each
-- reward icon, and looks again after each of Attune's layouts.
local _, ns = ...
local L, A, Theme, Kit, Skin = ns.L, ns.Attune, ns.Theme, ns.Kit, ns.Skin
local Paint, Bind = Theme.Paint, Theme.Bind

local OWN = {}                                         -- undo owner for the permanent changes
local rowDeco = setmetatable({}, { __mode = "k" })     -- reward row -> its icon frame
local zoomOurs = setmetatable({}, { __mode = "k" })    -- Attune's map zoom button -> ours
local ours = { rewardClose = nil, rewardLink = nil, tickets = 0 }

---------------------------------------------------------------------------
-- Small pieces
---------------------------------------------------------------------------

local function Text(fs, size, colorKey)
    if type(fs) ~= "table" or not Skin.Once(fs, "detail-text") then return end
    Skin.NoShadow(OWN, fs)
    Bind(fs, function(self, T)
        Theme.SetFont(self, size)
        if colorKey then Paint(self, T[colorKey] or T.text) end
    end)
end

-- Makes the art of a Blizzard button invisible (its own textures, not the text). Faded, not hidden: the client shows and
-- hides the state textures (pressed, highlight) by itself.
local function Quiet(button)
    for _, region in ipairs({ button:GetRegions() }) do
        if region:GetObjectType() == "Texture" then Skin.Alpha(OWN, region, 0) end
    end
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if type(button[getter]) == "function" then Skin.Alpha(OWN, button[getter](button), 0) end
    end
end

local function CloseGlyph(button)
    if not Skin.Once(button, "detail-close") then return end
    Quiet(button)
    local glyph = Skin.Mine(Kit.Glyph(button, "close", 14, "textDim"))
    glyph:SetPoint("CENTER", button, "CENTER", -3, -3)
    A.HookScript(button, "OnEnter", function() glyph:SetColorKey("danger") end, "detail")
    A.HookScript(button, "OnLeave", function() glyph:SetColorKey("textDim") end, "detail")
end

-- A square frame of 1 px around a reward icon, in the colour of the item quality (the colour Attune gives the name);
-- a plain white name means a common item and gets the neutral edge.
local function RowFrame(row)
    local d = rowDeco[row]
    if d then return d end
    d = Skin.Mine(CreateFrame("Frame", nil, row))
    d.edges = {}
    for i = 1, 4 do
        d.edges[i] = d:CreateTexture(nil, "OVERLAY")
        Theme.Crisp(d.edges[i])
    end
    d.edges[1]:SetPoint("TOPLEFT"); d.edges[1]:SetPoint("TOPRIGHT")
    d.edges[2]:SetPoint("BOTTOMLEFT"); d.edges[2]:SetPoint("BOTTOMRIGHT")
    d.edges[3]:SetPoint("TOPLEFT"); d.edges[3]:SetPoint("BOTTOMLEFT")
    d.edges[4]:SetPoint("TOPRIGHT"); d.edges[4]:SetPoint("BOTTOMRIGHT")
    d:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -1, 1)
    d:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, -1)
    d:SetFrameLevel(row:GetFrameLevel() + 2)
    rowDeco[row] = d
    return d
end

local WHITE = { 1, 1, 1, 1 }

local function Near(r, g, b, color)
    return type(r) == "number" and math.abs(r - color[1]) < 0.01 and math.abs(g - color[2]) < 0.01
        and math.abs(b - color[3]) < 0.01
end

-- Attune colours the name by item quality. White (common) would vanish on a light theme: the name then takes the
-- theme's text colour, and white again on a dark one (the colour we set is recognised as "common" later on).
local function TintRow(row)
    local d = rowDeco[row]
    if not d then return end
    local T = Theme.Get()
    local r, g, b = row.name:GetTextColor()
    local common = type(r) ~= "number" or (r > 0.97 and g > 0.97 and b > 0.97)
        or (d.textColor ~= nil and Near(r, g, b, d.textColor))
    if common then
        local want = T.mode == "light" and T.text or WHITE
        if not Near(r, g, b, want) then
            d.textColor = want
            row.name:SetTextColor(want[1], want[2], want[3], 1) -- runs this again through the hook; then it matches
            return
        end
    end
    local edge = common and T.border or { r, g, b, 1 }
    local size = Skin.Pixel(d)
    d.edges[1]:SetHeight(size); d.edges[2]:SetHeight(size)
    d.edges[3]:SetWidth(size); d.edges[4]:SetWidth(size)
    for _, e in ipairs(d.edges) do Paint(e, edge) end
end

local function StyleRow(row)
    if type(row) ~= "table" or not row.icon or not row.name then return end
    if Skin.Once(row, "detail-row") then
        RowFrame(row)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        Skin.Mine(hl)
        Bind(hl, function(self, T) Paint(self, T.hover) end)
        Text(row.name, 12, nil)
        Text(row.category, 10, "textDim")
        if row.count then Text(row.count, 10, "text") end
        -- Attune sets the name colour on every layout: the frame follows it
        A.HookMethod(row.name, "SetTextColor", function() TintRow(row) end, "detail")
        Theme.OnChange(function() TintRow(row) end)
    end
    -- the gold ring Attune puts on spell icons would sit on top of our frame
    if row.spellFrame then Skin.Alpha(OWN, row.spellFrame, 0) end
    TintRow(row)
end

---------------------------------------------------------------------------
-- The quest detail panel
---------------------------------------------------------------------------

local function StyleMap(parts)
    local map = parts.map
    if Skin.Once(map, "detail-box") then
        Skin.ClearBackdrop(OWN, map)
        Skin.Boxed(map, "canvasBg", "border")
    end
    Text(parts.giver, 11, nil)
    if parts.map.empty then Text(parts.map.empty, 11, "textDim") end
    -- Attune's two zoom buttons stay (invisible); ours sit exactly on them and press them
    for _, z in ipairs(parts.zoomButtons) do
        local button = z.button
        if not zoomOurs[button] then
            Skin.Conceal(OWN, button)
            -- a child of the panel, not of the map: the adapter looks for Attune's buttons among the map's children
            local mine = Skin.Mine(Kit.Button(parts.panel, 22, z.kind == "plus" and "+" or "-",
                function() A.ClickButton(button) end, 20))
            mine:SetAllPoints(button)
            mine:SetFrameLevel(button:GetFrameLevel() + 1)
            zoomOurs[button] = mine
        end
    end
end

local function StylePanel()
    local parts = A.DetailParts()
    if not parts then return end
    local panel = parts.panel
    if Skin.Once(panel, "detail-box") then
        Skin.ClearBackdrop(OWN, panel)
        Skin.Boxed(panel, "sheet", nil)
        A.HookScript(panel, "OnShow", StylePanel, "detail")
        -- Attune sizes the reward list at the end of every layout: that is when new rows and headers exist
        if parts.child then A.HookScript(parts.child, "OnSizeChanged", StylePanel, "detail") end
    end
    Text(parts.title, 16, "text")
    Text(parts.subtitle, 11, "textDim")
    parts.subtitle:SetText(A.Lang("Quest rewards") or L["Quest rewards"])
    if parts.close then CloseGlyph(parts.close) end
    if Skin.Once(parts.separator, "detail-paint") then
        Bind(parts.separator, function(self, T) Paint(self, T.accent) end)
    end
    Text(parts.xp, 11, "accent")
    Text(parts.empty, 11, "textDim")
    for _, header in ipairs(parts.headers) do Text(header, 11, "header") end
    StyleMap(parts)
    for _, row in ipairs(parts.rows) do StyleRow(row) end
end

-- The panel is laid out again 0.4 s after it was opened (rewards that arrived late): look once more then.
local function OnDetail()
    StylePanel()
    if C_Timer then
        C_Timer.After(0.5, function() ns.Modules.Run("detail", StylePanel) end)
    end
end

---------------------------------------------------------------------------
-- The reward window
---------------------------------------------------------------------------

local function StyleRewards()
    local parts = A.RewardParts()
    if not parts then return end
    local frame = parts.frame
    if Skin.Once(frame, "detail-box") then
        Skin.ClearBackdrop(OWN, frame)
        Skin.Boxed(frame, "sheet", "border")
        if parts.scroll then
            local bar = parts.scroll.ScrollBar or _G[(parts.scroll:GetName() or "") .. "ScrollBar"]
            if type(bar) == "table" then Skin.ThinBar(OWN, bar, false, "detail") end
        end
        ours.rewardClose = Skin.Mine(Kit.IconButton(frame, 24, "close", function() frame:Hide() end, L["Close"]))
        ours.rewardClose:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
        ours.rewardClose:SetFrameLevel(frame:GetFrameLevel() + 30)
        if parts.link then
            Skin.Conceal(OWN, parts.link)
            local link = parts.link
            ours.rewardLink = Skin.Mine(Kit.Button(frame, 100, link:GetText() or "", function() A.ClickButton(link) end, 22))
            ours.rewardLink:SetAllPoints(link)
            ours.rewardLink:SetFrameLevel(frame:GetFrameLevel() + 30)
        end
    end
    -- Attune draws the title in its bronze chrome; with the chrome hidden the plain title shows instead
    if parts.chrome then
        Skin.HideFrame(OWN, parts.chrome)
        local container = parts.chrome.TitleContainer
        local text = container and container.TitleText and container.TitleText:GetText() or nil
        if parts.title and text then
            parts.title:SetText(text)
            parts.title:Show()
        end
    end
    Text(parts.title, 14, "text")
    Text(parts.empty, 12, "textDim")
    if ours.rewardLink and parts.link then ours.rewardLink:SetLabel(parts.link:GetText() or "") end
    for _, header in ipairs(parts.headers) do Text(header, 11, "header") end
    for _, row in ipairs(parts.rows) do StyleRow(row) end
end

local function OnRewards()
    StyleRewards()
    if C_Timer then
        C_Timer.After(0.5, function() ns.Modules.Run("detail", StyleRewards) end)
    end
end

---------------------------------------------------------------------------
-- The quest giver hint (a tooltip of Attune's next to the quest tooltip)
---------------------------------------------------------------------------

-- Attune writes the hint in white ("Starts at" even as a colour code): on a light theme the hint stays dark like the
-- game's tooltip next to it. No text shadow.
local DARK_TIP = { 0.08, 0.08, 0.1, 1 }

local function ColorTip(tip)
    local T = Theme.Get()
    local fill, edge = T.mode == "light" and DARK_TIP or T.bgAlt, T.border
    for _, region in ipairs({ tip:GetRegions() }) do
        if region:GetObjectType() == "FontString" then Skin.NoShadow(OWN, region) end
    end
    pcall(function()
        local nine = tip.NineSlice
        if type(nine) == "table" and type(nine.SetCenterColor) == "function" then
            nine:SetCenterColor(fill[1], fill[2], fill[3], 0.97)
            if type(nine.SetBorderColor) == "function" then nine:SetBorderColor(edge[1], edge[2], edge[3], 1) end
        elseif type(tip.SetBackdropColor) == "function" then
            tip:SetBackdropColor(fill[1], fill[2], fill[3], 0.97)
            tip:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
        end
    end)
end

-- Attune creates the hint on the first hover of a quest card; its colours are set again whenever it shows.
local function StyleTip()
    local tip = A.GiverTip()
    if not tip then return end
    if Skin.Once(tip, "detail-tip") then
        A.HookScript(tip, "OnShow", ColorTip, "detail")
        Theme.OnChange(function() ColorTip(tip) end)
    end
    ColorTip(tip)
end

local function OnNode(step)
    if type(step) ~= "table" or step.ID == nil then return end
    local node = A.Node(step.ID)
    if node then A.HookScript(node, "OnEnter", StyleTip, "detail") end
end

-- Frames the tests and the probe may look at.
function Skin.DetailState()
    return { rowDeco = rowDeco, zoomOurs = zoomOurs, ours = ours, panel = StylePanel, rewards = StyleRewards, tip = StyleTip }
end

Theme.OnChange(function()
    if ns.Modules.IsActive("detail") then ns.Modules.Run("detail", StylePanel) end
end)

ns.Modules.Register("detail", {
    requires = { "QuestDetail", "QuestRewards", "Select", "CreateNode", "Lang" },
    setting = "detail",
    Enable = function()
        A.On("questDetail", OnDetail, "detail")
        A.On("questRewards", OnRewards, "detail")
        A.On("node", OnNode, "detail")
        if A.QuestDetail() then StylePanel() end
        if A.RewardFrame() then StyleRewards() end
        StyleTip()
    end,
    Disable = function()
        Skin.Undo(OWN)
        local parts = A.DetailParts()
        if parts then
            Skin.Unbox(parts.panel)
            Skin.Unbox(parts.map)
        end
        if A.RewardFrame() then Skin.Unbox(A.RewardFrame()) end
        for _, d in pairs(rowDeco) do d:Hide() end
        for _, b in pairs(zoomOurs) do b:Hide() end
        if ours.rewardClose then ours.rewardClose:Hide() end
        if ours.rewardLink then ours.rewardLink:Hide() end
    end,
})
