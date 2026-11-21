-- ForeverDungeonJournal: its dungeon tracker in the flat EllesmereUI look, and raid symbols for the bosses.
-- Look: flat panel with an accent edge, header with flat icon buttons (reset, our gear, close), the stats (time, mob XP,
-- gold) on a band with separators, round portraits with a ring (accent once killed, a check badge instead of the red X),
-- and the divider under the stats as a progress bar of the bosses killed.
-- Marks: Shift-left-click on a living boss's portrait targets it and puts its raid symbol on it. Every boss of a dungeon
-- has its own symbol (star, circle, diamond, ... in tracker order; the skull stays the rares', ForeverDungeonJournal
-- marks those itself); the gear in the header opens a small panel to pick one per boss. The symbol shows as a badge on
-- the portrait. Out of range (/targetexact finds no one) nothing is marked and the old target comes back.
--
-- Hook points (ForeverDungeonJournal 2.1.2, Systems\RunLogUI.lua; checked in the installed addon):
--   ForeverDungeonJournal_NS (FDJ): post-hooks on FDJ.UpdateRunTracker (redraws the tracker every second) and
--   FDJ.TrackerLootToggle (makes the tracker's loot row); FDJ.LocalizeBossName for the names in our panel.
--   ForeverDungeonJournalRunTracker: logo, title, reset (.Icon), close, handle, timeLabel/time, xpLabel/xp,
--   goldLabel/gold, line, raresLabel, grip, groupRow, lootRow, run (.dungeon), portraits[] (Portrait(): tex, dim, x;
--   boss, kill, isRare, group, fightGroup).
--   ForeverDungeonJournalBossTarget<n>: secure buttons over the living bosses' portraits (type "macro", macrotext
--   "/cleartarget\n/targetexact <name>", .portrait); ForeverDungeonJournal lays them out only out of combat. We add the
--   attribute "shift-macrotext1" (out of combat only) and never touch its own attributes.
local _, ns = ...
local L = ns.L
local C, Skin, Kit = ns.Colors, ns.Skin, ns.Kit

local M = ns.Modules.Register("dungeonJournal", { addon = "ForeverDungeonJournal", setting = "dungeonJournal",
    label = "Dungeon Journal: tracker" })

local DJ = {}
ns.DungeonJournal = DJ

local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
local BUTTON = "ForeverDungeonJournalBossTarget"
-- Default symbols in tracker order: star, circle, diamond, triangle, moon, square, cross (no skull).
DJ.DEFAULT_ORDER = { 1, 2, 3, 4, 5, 6, 7 }
function DJ.SymbolName(symbol)
    return ({ L["Star"], L["Circle"], L["Diamond"], L["Triangle"], L["Moon"], L["Square"], L["Cross"], L["Skull"] })[symbol]
end

local function Weak() return setmetatable({}, { __mode = "k" }) end

local deco = Weak()     -- portrait -> { ring, badge }
local hooked = Weak()   -- secure button or portrait -> true (HookScript once)
local applied = Weak()  -- secure button -> shift macro we set (false = none)
local fontSig = Weak()  -- FontString -> font we applied
local panel             -- our "Boss symbols" panel
local trackerDeco       -- our textures and buttons on the tracker

local function FDJ()
    local fdj = rawget(_G, "ForeverDungeonJournal_NS")
    return type(fdj) == "table" and fdj or nil
end

local function Tracker()
    return ns.T(rawget(_G, "ForeverDungeonJournalRunTracker"))
end

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

function DJ.Icon(symbol, size)
    return ("|T" .. ICON .. ":%d|t"):format(symbol, size or 14)
end

---------------------------------------------------------------------------
-- Symbols per boss
---------------------------------------------------------------------------

local function DungeonKey(t)
    local run = t and ns.T(t.run)
    local key = run and run.dungeon
    if type(key) ~= "string" or key == "" then return nil end
    return key
end

-- The bosses of the shown run in tracker order: portraits of bosses (no rares, no groups, no fights).
function DJ.Bosses(t)
    local list = {}
    for _, f in ipairs(ns.T(t and t.portraits) or {}) do
        local boss = ns.T(f.boss)
        if f:IsShown() and boss and type(boss.name) == "string" and not f.isRare and not f.group and not f.fightGroup then
            list[#list + 1] = f
        end
    end
    return list
end

-- Symbol of a boss: the one chosen in our panel, else the default for its place in the tracker (0 = none).
function DJ.Symbol(dungeon, name, index)
    local marks = dungeon and ns.db.dungeonJournal.marks[dungeon]
    local chosen = marks and marks[name]
    if type(chosen) == "number" and chosen >= 0 and chosen <= 8 and chosen == math.floor(chosen) then return chosen end
    local order = DJ.DEFAULT_ORDER
    return order[((index or 1) - 1) % #order + 1]
end

function DJ.SetSymbol(dungeon, name, symbol)
    if not (dungeon and name) then return end
    local all = ns.db.dungeonJournal.marks
    all[dungeon] = all[dungeon] or {}
    all[dungeon][name] = symbol
    DJ.Refresh()
end

function DJ.ResetDungeon(dungeon)
    if dungeon then ns.db.dungeonJournal.marks[dungeon] = nil end
    DJ.Refresh()
end

-- Shift macro for ForeverDungeonJournal's own one ("/cleartarget\n/targetexact <name>"): mark the target only when
-- /targetexact found the boss (in range, alive), clear an older mark first (/tm toggles a symbol the unit already
-- wears), and bring the old target back when the boss was not found.
function DJ.MarkMacro(base, symbol)
    if type(base) ~= "string" or not base:find("/targetexact", 1, true) then return nil end
    if type(symbol) ~= "number" or symbol < 1 or symbol > 8 then return nil end
    return base .. "\n/tm [@target,exists,nodead] 0\n/tm [@target,exists,nodead] " .. symbol
        .. "\n/targetlasttarget [noexists]"
end

-- Symbol per boss portrait of the shown tracker.
local function SymbolMap(t)
    local map, dungeon = {}, DungeonKey(t)
    for i, f in ipairs(DJ.Bosses(t)) do map[f] = DJ.Symbol(dungeon, f.boss.name, i) end
    return map
end

---------------------------------------------------------------------------
-- Look
---------------------------------------------------------------------------

local function Font(fs, size)
    if not (fs and fs.SetFont) then return end
    local path, flags = ns.Font()
    local sig = path .. "|" .. size .. "|" .. flags
    if fontSig[fs] == sig then return end
    fontSig[fs] = sig
    ns.SetFont(fs, path, size, flags)
    if fs.SetShadowOffset then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, flags == "" and 0.8 or 0)
    end
end

-- Flat look on a frame made with ForeverDungeonJournal's backdrop (its own colours made invisible).
local function FlatBackdrop(frame, color, alpha)
    if frame.SetBackdropColor then
        frame:SetBackdropColor(0, 0, 0, 0)
        frame:SetBackdropBorderColor(0, 0, 0, 0)
    end
    Skin.Flat(frame, color, alpha, C.border)
end

-- A flat square button look on ForeverDungeonJournal's reset button (its template art faded).
local function FlatReset(reset)
    if not reset or hooked[reset] then return end
    hooked[reset] = true
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
        local tex = reset[getter] and reset[getter](reset)
        if tex then tex:SetAlpha(0) end
    end
    reset:SetSize(18, 18)
    Skin.Flat(reset, C.control, 1, C.border)
    Skin.Hover(reset, 0.25)
    if reset.Icon then
        reset.Icon:SetSize(11, 11)
        reset.Icon:SetVertexColor(C.soft[1], C.soft[2], C.soft[3])
        reset:HookScript("OnEnter", function(self) self.Icon:SetVertexColor(ns.Accent()) end)
        reset:HookScript("OnLeave", function(self) self.Icon:SetVertexColor(C.soft[1], C.soft[2], C.soft[3]) end)
    end
end

local function Ring(f, state)
    local d = deco[f]
    if not d then return end
    local r, g, b = ns.Accent()
    if state == "hover" then
        d.ring:SetVertexColor(r, g, b, 1)
    elseif f.kill then
        d.ring:SetVertexColor(r, g, b, 0.75)
    else
        d.ring:SetVertexColor(0.24, 0.24, 0.24, 1)
    end
end

local function PortraitDeco(f)
    local d = deco[f]
    if d then return d end
    d = {}
    deco[f] = d
    local w = f:GetWidth() or 38
    -- a filled circle a little larger than the portrait, behind it: a 2 px ring
    d.ring = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    d.ring:SetTexture(CIRCLE)
    d.ring:SetPoint("CENTER")
    d.ring:SetSize(w + 4, w + 4)
    d.badge = f:CreateTexture(nil, "OVERLAY", nil, 7)
    d.badge:SetSize(15, 15)
    d.badge:SetPoint("TOPRIGHT", f, "TOPRIGHT", 3, 3)
    d.badge:Hide()
    -- killed: a check badge instead of the big red X
    if f.x and f.x.SetTexture then
        f.x:SetTexture(CHECK)
        f.x:ClearAllPoints()
        f.x:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
        f.x:SetSize(16, 16)
    end
    if f.dim and f.dim.SetVertexColor then f.dim:SetVertexColor(0, 0, 0, 0.45) end
    if not hooked[f] and f.HookScript then
        hooked[f] = true
        f:HookScript("OnEnter", ns.Guard("dungeonJournal", function(self) Ring(self, "hover") end))
        f:HookScript("OnLeave", ns.Guard("dungeonJournal", function(self) Ring(self) end))
    end
    return d
end

local function StylePortraits(t, symbols)
    local db = ns.db.dungeonJournal
    for _, f in ipairs(ns.T(t.portraits) or {}) do
        local d = PortraitDeco(f)
        d.ring:SetShown(f:IsShown())
        Ring(f)
        local symbol = symbols[f]
        local show = db.mark and db.badges and symbol and symbol > 0 and not f.kill
        if show then d.badge:SetTexture(ICON:format(symbol)) end
        d.badge:SetShown(show and true or false)
    end
end

-- x offset of a column label (ForeverDungeonJournal anchors it TOPLEFT of the tracker).
local function ColumnX(label)
    if not (label and label:IsShown()) then return nil end
    local _, _, _, x = label:GetPoint(1)
    return type(x) == "number" and x or nil
end

local function Decor(t)
    if trackerDeco then return trackerDeco end
    local d = {}
    trackerDeco = d
    d.edge = t:CreateTexture(nil, "BORDER", nil, 6)
    d.edge:SetPoint("TOPLEFT", 1, -1)
    d.edge:SetPoint("TOPRIGHT", -1, -1)
    d.edge:SetHeight(2)
    d.band = t:CreateTexture(nil, "BACKGROUND", nil, -6)
    d.seps = { t:CreateTexture(nil, "ARTWORK"), t:CreateTexture(nil, "ARTWORK") }
    d.fill = t:CreateTexture(nil, "ARTWORK", nil, 2)
    d.fill:SetHeight(2)
    -- our gear: the boss symbols panel
    d.gear = Kit.IconButton(t, 18, "gear", function() DJ.TogglePanel() end,
        { L["Boss symbols"], L["Pick the raid symbol of each boss. Shift-left-click on a boss's portrait marks it."] })
    d.gear:SetFrameLevel((t.handle and t.handle:GetFrameLevel() or t:GetFrameLevel()) + 6)
    Skin.Flat(d.gear, C.control, 1, C.border)
    return d
end

local function StyleHeader(t, d)
    local r, g, b = ns.Accent()
    d.edge:SetColorTexture(r, g, b, 0.9)
    if t.logo then
        t.logo:SetSize(16, 16)
    end
    if t.title then
        Font(t.title, 13)
        t.title:SetTextColor(C.text[1], C.text[2], C.text[3])
    end
    FlatReset(t.reset)
    if t.close then Skin.Close(t.close) end
    -- gear left of the close button (left of the corner when the tracker is locked and its X is hidden)
    d.gear:ClearAllPoints()
    if t.close and t.close:IsShown() then
        d.gear:SetPoint("RIGHT", t.close, "LEFT", -1, 0)
    else
        d.gear:SetPoint("TOPRIGHT", t, "TOPRIGHT", -6, -5)
    end
    -- the dungeon's name leaves room for the gear (ForeverDungeonJournal measured without it)
    if t.title and t.title.GetWidth then
        local width = (t:GetWidth() or 236) - 30 - 26 - 22
        if t.reset and t.reset:IsShown() then width = width - 24 end
        local current = t.title:GetWidth() or 0
        if current > width then t.title:SetWidth(math.max(1, width)) end
    end
end

local function StyleStats(t, d)
    local labels = { t.timeLabel, t.xpLabel, t.goldLabel }
    for _, fs in ipairs(labels) do
        if fs then
            Font(fs, 9)
            fs:SetTextColor(C.dim[1] + 0.12, C.dim[2] + 0.12, C.dim[3] + 0.12)
            local text = fs:GetText()
            if type(text) == "string" then fs:SetText(text:upper()) end
        end
    end
    for _, fs in ipairs({ t.time, t.xp, t.gold }) do Font(fs, 16) end
    local xs = {}
    for _, fs in ipairs(labels) do
        local x = ColumnX(fs)
        if x then xs[#xs + 1] = x end
    end
    table.sort(xs)
    local band = #xs > 0
    d.band:SetShown(band)
    if band then
        local c = C.inset
        d.band:SetColorTexture(c[1], c[2], c[3], 0.85)
        d.band:ClearAllPoints()
        d.band:SetPoint("TOPLEFT", t, "TOPLEFT", 4, -25)
        d.band:SetPoint("TOPRIGHT", t, "TOPRIGHT", -4, -25)
        d.band:SetHeight(41)
    end
    for i, sep in ipairs(d.seps) do
        local x = xs[i + 1]
        sep:SetShown(band and x ~= nil)
        if band and x then
            sep:SetColorTexture(1, 1, 1, 0.07)
            sep:ClearAllPoints()
            sep:SetPoint("TOPLEFT", t, "TOPLEFT", x - 7, -30)
            sep:SetSize(1, 31)
        end
    end
end

-- The divider under the stats: a 2 px bar, filled in the accent by the share of bosses killed.
local function StyleProgress(t, d)
    local line = t.line
    if not line then return end
    line:SetHeight(2)
    line:SetColorTexture(1, 1, 1, 0.08)
    local bosses = DJ.Bosses(t)
    local killed = 0
    for _, f in ipairs(bosses) do if f.kill then killed = killed + 1 end end
    local share = #bosses > 0 and killed / #bosses or 0
    local width = (t:GetWidth() or 236) - 16
    d.fill:ClearAllPoints()
    d.fill:SetPoint("TOPLEFT", line, "TOPLEFT", 0, 0)
    d.fill:SetWidth(math.max(1, width * share))
    local r, g, b = ns.Accent()
    d.fill:SetColorTexture(r, g, b, 1)
    d.fill:SetShown(share > 0 and line:IsShown())
    d.killed, d.total = killed, #bosses
end

local function StyleRows(t)
    if t.raresLabel then
        Font(t.raresLabel, 9)
        local r, g, b = ns.Accent()
        t.raresLabel:SetTextColor(r, g, b)
        local text = t.raresLabel:GetText()
        if type(text) == "string" then t.raresLabel:SetText(text:upper()) end
    end
    local alpha = ns.Clamp(ns.db.dungeonJournal.background, 0, 100, 90) / 100
    for _, row in ipairs({ t.groupRow, t.lootRow }) do
        if ns.T(row) then FlatBackdrop(row, C.inset, math.max(alpha, 0.9)) end
    end
end

local function Style(t, symbols)
    local d = Decor(t)
    local alpha = ns.Clamp(ns.db.dungeonJournal.background, 0, 100, 90) / 100
    local pr, pg, pb = ns.PanelColor()
    FlatBackdrop(t, { pr, pg, pb }, alpha)
    StyleHeader(t, d)
    StyleStats(t, d)
    StyleProgress(t, d)
    StyleRows(t)
    StylePortraits(t, symbols)
end

---------------------------------------------------------------------------
-- Shift-left-click on ForeverDungeonJournal's secure boss buttons
---------------------------------------------------------------------------

local function HookButton(b)
    if hooked[b] then return end
    hooked[b] = true
    b:HookScript("OnEnter", ns.Guard("dungeonJournal", function(self)
        local f = ns.T(self.portrait)
        if f then Ring(f, "hover") end
        local t = Tracker()
        local symbol = f and t and SymbolMap(t)[f]
        if ns.db.dungeonJournal.mark and symbol and symbol > 0 and GameTooltip:IsOwned(self) then
            local r, g, bb = ns.Accent()
            GameTooltip:AddLine(L["Shift-left-click: target and mark %s"]:format(DJ.Icon(symbol)), r, g, bb)
            GameTooltip:Show()
        end
    end))
    b:HookScript("OnLeave", ns.Guard("dungeonJournal", function(self)
        local f = ns.T(self.portrait)
        if f then Ring(f) end
    end))
end

local function ApplyButtons(t, symbols)
    if InCombat() then return end
    local on = ns.db.dungeonJournal.mark and t:IsShown()
    local i = 1
    while i <= 40 do
        local b = rawget(_G, BUTTON .. i)
        if not ns.T(b) then break end
        local want = false
        local f = ns.T(b.portrait)
        if on and b:IsShown() and f and symbols[f] then
            want = DJ.MarkMacro(b:GetAttribute("macrotext"), symbols[f]) or false
        end
        if applied[b] ~= want then
            b:SetAttribute("shift-macrotext1", want or nil)
            applied[b] = want
        end
        HookButton(b)
        i = i + 1
    end
end

---------------------------------------------------------------------------
-- Panel: one symbol per boss
---------------------------------------------------------------------------

local ROW_H, PICK = 26, 20

local function BossName(name)
    local fdj = FDJ()
    if fdj and type(fdj.LocalizeBossName) == "function" then
        local ok, loc = pcall(fdj.LocalizeBossName, name)
        if ok and type(loc) == "string" and loc ~= "" then return loc end
    end
    return name
end

local function DungeonName(t)
    local fdj, key = FDJ(), DungeonKey(t)
    if key and fdj and type(fdj.LocalizeDungeonName) == "function" then
        local ok, loc = pcall(fdj.LocalizeDungeonName, key)
        if ok and type(loc) == "string" and loc ~= "" then return loc end
    end
    return key or ""
end

local function PickButton(row, symbol)
    local b = CreateFrame("Button", nil, row)
    b:SetSize(PICK, PICK)
    b.symbol = symbol
    b.sel = CreateFrame("Frame", nil, b)
    b.sel:SetAllPoints()
    b.sel:SetFrameLevel(math.max(0, b:GetFrameLevel() - 1))
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.12)
    if symbol > 0 then
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetTexture(ICON:format(symbol))
        b.icon:SetPoint("CENTER")
        b.icon:SetSize(PICK - 6, PICK - 6)
    else
        b.icon = Kit.Glyph(b, "minus", PICK - 8, "textDim")
        b.icon:SetPoint("CENTER")
    end
    b:SetScript("OnClick", function(self)
        local p = self:GetParent()
        DJ.SetSymbol(p.dungeon, p.bossName, self.symbol)
    end)
    Kit.Tooltip(b, function(self)
        if self.symbol == 0 then return { L["No symbol"], L["Shift-left-click only targets this boss."] } end
        return { DJ.SymbolName(self.symbol) }
    end, "ANCHOR_TOP")
    return b
end

local function PanelRow(p, i)
    local row = p.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, p.body)
    row:SetHeight(ROW_H)
    row.name = Kit.Text(row, 12, "text")
    row.name:SetPoint("LEFT", 2, 0)
    row.name:SetWidth(112)
    row.name:SetWordWrap(false)
    row.picks = {}
    for s = 0, 8 do
        local b = PickButton(row, s)
        b:SetPoint("LEFT", row, "LEFT", 118 + s * (PICK + 2), 0)
        row.picks[s] = b
    end
    p.rows[i] = row
    return row
end

local function Paint(btn, selected, usedElsewhere)
    local r, g, b = ns.Accent()
    if selected then
        Skin.Flat(btn.sel, { r, g, b }, 0.25, { r, g, b, 1 })
        btn.sel:Show()
    else
        btn.sel:Hide()
    end
    btn.icon:SetAlpha((usedElsewhere and not selected) and 0.35 or 1)
end

function DJ.RenderPanel()
    local p, t = panel, Tracker()
    if not (p and p:IsShown()) then return end
    if not (t and t:IsShown()) then
        p:Hide()
        return
    end
    local dungeon = DungeonKey(t)
    p.sub:SetText(DungeonName(t))
    p.check:Update()
    local bosses, symbols = DJ.Bosses(t), SymbolMap(t)
    local count = {}
    for _, f in ipairs(bosses) do
        local s = symbols[f]
        count[s] = (count[s] or 0) + 1
    end
    for i, f in ipairs(bosses) do
        local row = PanelRow(p, i)
        row.dungeon, row.bossName = dungeon, f.boss.name
        row.name:SetText(BossName(f.boss.name))
        Kit.SetTextColor(row.name, f.kill and "textDim" or "text")
        local mine = symbols[f]
        for s = 0, 8 do
            local used = s > 0 and (count[s] or 0) > ((s == mine) and 1 or 0)
            Paint(row.picks[s], s == mine, used)
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", p.body, "TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("RIGHT", p.body, "RIGHT", 0, 0)
        row:Show()
    end
    for i = #bosses + 1, #p.rows do p.rows[i]:Hide() end
    p.empty:SetShown(#bosses == 0)
    local bodyH = math.max(1, #bosses) * ROW_H
    p.body:SetHeight(bodyH)
    p:SetHeight(72 + bodyH + 70)
end

local function BuildPanel()
    local p = Kit.Panel(UIParent, "bg", "border")
    p:SetSize(338, 200)
    p:SetFrameStrata("DIALOG")
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    p:Hide()
    rawset(_G, "BeautifulSkinsDungeonSymbols", p)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "BeautifulSkinsDungeonSymbols") end
    p.edge = p:CreateTexture(nil, "BORDER", nil, 6)
    p.edge:SetPoint("TOPLEFT", 1, -1)
    p.edge:SetPoint("TOPRIGHT", -1, -1)
    p.edge:SetHeight(2)
    p.title = Kit.Text(p, 13, "accent")
    p.title:SetPoint("TOPLEFT", 12, -11)
    p.title:SetText(L["Boss symbols"])
    p.sub = Kit.Text(p, 11, "textDim")
    p.sub:SetPoint("LEFT", p.title, "RIGHT", 8, 0)
    p.sub:SetPoint("RIGHT", p, "RIGHT", -34, 0)
    p.sub:SetWordWrap(false)
    p.close = Kit.IconButton(p, 18, "close", function() p:Hide() end)
    p.close:SetPoint("TOPRIGHT", -7, -7)
    p.check = Kit.Checkbox(p, L["Shift-left-click marks the boss"],
        function() return ns.db.dungeonJournal.mark end,
        function(on)
            ns.db.dungeonJournal.mark = on and true or false
            DJ.Refresh()
        end, 12)
    p.check:SetPoint("TOPLEFT", 12, -36)
    p.body = CreateFrame("Frame", nil, p)
    p.body:SetPoint("TOPLEFT", 12, -66)
    p.body:SetPoint("RIGHT", p, "RIGHT", -12, 0)
    p.rows = {}
    p.empty = Kit.Text(p.body, 12, "textDim")
    p.empty:SetPoint("TOPLEFT", 2, -6)
    p.empty:SetText(L["No bosses in this tracker."])
    p.hint = Kit.Text(p, 11, "textDim")
    p.hint:SetPoint("BOTTOMLEFT", 12, 40)
    p.hint:SetPoint("RIGHT", p, "RIGHT", -12, 0)
    p.hint:SetWordWrap(true)
    p.hint:SetText(L["Only marks a boss in range. The skull stays with the rares. Dimmed symbols belong to another boss."])
    p.reset = Kit.Button(p, 110, L["Defaults"], function()
        DJ.ResetDungeon(DungeonKey(Tracker()))
    end, 22)
    p.reset:SetPoint("BOTTOMLEFT", 12, 10)
    ns.Theme.Bind(p.edge, function(self)
        local r, g, b = ns.Accent()
        self:SetColorTexture(r, g, b, 0.9)
    end)
    p:SetScript("OnShow", function() DJ.RenderPanel() end)
    return p
end

local function PlacePanel(p, t)
    p:ClearAllPoints()
    local right = (t:GetRight() or 0) * (t:GetEffectiveScale() or 1)
    local screen = (UIParent:GetWidth() or 0) * (UIParent:GetEffectiveScale() or 1)
    local width = (p:GetWidth() or 338) * (p:GetEffectiveScale() or 1)
    if right + width + 8 > screen then
        p:SetPoint("TOPRIGHT", t, "TOPLEFT", -6, 0)
    else
        p:SetPoint("TOPLEFT", t, "TOPRIGHT", 6, 0)
    end
end

function DJ.TogglePanel(show)
    local t = Tracker()
    if not t then return end
    panel = panel or BuildPanel()
    if show == nil then show = not panel:IsShown() end
    if not show then
        panel:Hide()
        return
    end
    PlacePanel(panel, t)
    panel:Show()
    DJ.RenderPanel()
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

local function Update()
    local t = Tracker()
    if not (t and t:IsShown()) then
        if panel then panel:Hide() end
        return
    end
    local symbols = SymbolMap(t)
    Style(t, symbols)
    ApplyButtons(t, symbols)
    if panel and panel:IsShown() then DJ.RenderPanel() end
end

function DJ.Refresh()
    if M.status == "active" then ns.Run("dungeonJournal", Update) end
end

function M.Enable()
    local fdj = FDJ()
    if not (fdj and type(fdj.UpdateRunTracker) == "function") then return end
    hooksecurefunc(fdj, "UpdateRunTracker", ns.Guard("dungeonJournal", Update))
    if type(fdj.TrackerLootToggle) == "function" then
        hooksecurefunc(fdj, "TrackerLootToggle", ns.Guard("dungeonJournal", Update))
    end
    Update()
end

ns.OnRefresh(function()
    DJ.Refresh()
end)
