-- GearQuest Forever: the guide arrow above its tracker, drawn by our arrow (the styles and colour modes of EUI RestedXP
-- Skin) with the distance and the hunt's name below it. GearQuest keeps computing the direction: every frame it picks
-- one of 32 frames of its arrow sheet (SetTexCoord); a post-hook turns that frame into an angle for our arrow.
-- GearQuest's own arrow and distance text are made invisible (vertex alpha 0 / alpha 0), never removed; GearQuest's
-- frame still takes the mouse (drag moves the tracker, the tooltip shows the hunt).
local _, ns = ...
local L = ns.L
local C = ns.Colors
local Skin, T = ns.Skin, ns.T

local SHEET_FRAMES = 32
local HERE = "Here"
local YARDS_PER_METER = 1.0936

local M = ns.Modules.Register("gqArrow", { addon = "GearQuestForever", setting = "gqArrow", label = "GearQuest: arrow" })
ns.GearQuestArrow = M

local arrow
local guide
local names = {} -- entry id -> display name
local lastIndex

local function GQ()
    local gq = rawget(_G, "GearQuest")
    return type(gq) == "table" and gq or nil
end

local function EntryName(id)
    if not id then return "" end
    if names[id] then return names[id] end
    local gq = GQ()
    local data = gq and gq.Data
    if not (data and type(data.GetEntryById) == "function") then return "" end
    local ok, name = pcall(function()
        local entry = data:GetEntryById(id)
        if not entry then return nil end
        if type(data.GetEntryDisplayName) == "function" then return data:GetEntryDisplayName(entry) end
        return entry.questName
    end)
    name = ok and type(name) == "string" and name or ""
    names[id] = name
    return name
end

-- GearQuest's line ("123 yards", "Here", a zone name, a dock kind) in our words and unit.
local function DistanceRow(text)
    if type(text) ~= "string" or text == "" or text == " " then return "" end
    if text == HERE then return L["Arrived"] end
    if text == "No pin" then return L["No location"] end
    local yards = tonumber(text:match("^(%d+) yards$"))
    if yards then
        if ns.db.arrow.unit == "m" then
            return ("%d m"):format(math.floor(yards / YARDS_PER_METER + 0.5))
        end
        return ("%d yd"):format(yards)
    end
    return text
end

local function Draw(left)
    if not (arrow and guide) then return end
    if type(left) ~= "number" or ns.IsSecret(left) then return end
    local index = math.floor(left * SHEET_FRAMES + 0.5) % SHEET_FRAMES
    local text = guide.distanceText
    if text == HERE then
        if lastIndex ~= HERE then arrow.Draw("CHECK") end
        lastIndex = HERE
    elseif index ~= lastIndex then
        -- GearQuest's frames turn clockwise from "straight ahead"; textures rotate counter-clockwise
        arrow.Draw("ARROW", -(index / SHEET_FRAMES) * 2 * math.pi)
        lastIndex = index
    end
    arrow.SetRows(DistanceRow(text), EntryName(guide.entryId))
end

-- GearQuest's close button ("X"): our font and colours.
local function StyleClose(frame)
    for _, child in ipairs({ frame:GetChildren() }) do
        if child:GetObjectType() == "Button" and child ~= (arrow and arrow.frame) then
            for _, region in ipairs({ child:GetRegions() }) do
                if region:GetObjectType() == "FontString" and region:GetText() == "X" then
                    local path = ns.Font()
                    ns.SetFont(region, path, 13, "OUTLINE")
                    region:SetText("\195\151") -- multiplication sign
                    region:SetTextColor(C.soft[1], C.soft[2], C.soft[3])
                    child:HookScript("OnEnter", function() region:SetTextColor(ns.Accent()) end)
                    child:HookScript("OnLeave", function() region:SetTextColor(C.soft[1], C.soft[2], C.soft[3]) end)
                    return
                end
            end
        end
    end
end

-- Free mode: the arrow sits on its own (movable) frame instead of above GearQuest's tracker; GearQuest's guide frame
-- keeps working invisibly (alpha 0, no mouse) and its visibility is mirrored.
local holder, closeBtn

local function Detached()
    return ns.db.arrow.detached == true or ns.db.gqTracker.column == true
end

local function SavePoint()
    local point, _, relPoint, x, y = holder:GetPoint(1)
    if point and ns.CanAccess(x) and ns.CanAccess(y) and type(x) == "number" then
        ns.db.arrow.point = { point, relPoint, math.floor(x * 10 + 0.5) / 10, math.floor(y * 10 + 0.5) / 10 }
    end
end

local function BuildHolder()
    holder = CreateFrame("Frame", "BeautifulSkinsGearQuestArrow", UIParent)
    holder:SetSize(160, 110)
    holder:SetClampedToScreen(true)
    holder:SetMovable(true)
    holder:RegisterForDrag("LeftButton")
    holder:SetScript("OnDragStart", function(self)
        if not ns.db.arrow.locked and not InCombatLockdown() then self:StartMoving() end
    end)
    holder:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePoint()
    end)
    holder:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(EntryName(guide and guide.entryId))
        GameTooltip:AddLine(L["Drag to move the arrow"], 0.75, 0.75, 0.75)
        GameTooltip:Show()
    end)
    holder:SetScript("OnLeave", function() GameTooltip:Hide() end)
    closeBtn = CreateFrame("Button", nil, holder)
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -18, 0)
    local x = closeBtn:CreateFontString(nil, "OVERLAY")
    ns.SetFont(x, STANDARD_TEXT_FONT, 14, "OUTLINE")
    x:SetPoint("CENTER")
    x:SetText("\195\151")
    x:SetTextColor(C.soft[1], C.soft[2], C.soft[3])
    closeBtn:SetScript("OnEnter", function(self)
        x:SetTextColor(ns.Accent())
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Remove the guide"])
        GameTooltip:Show()
    end)
    closeBtn:SetScript("OnLeave", function()
        x:SetTextColor(C.soft[1], C.soft[2], C.soft[3])
        GameTooltip:Hide()
    end)
    closeBtn:SetScript("OnClick", function()
        local gq = GQ()
        if gq and gq.Guide and type(gq.Guide.Dismiss) == "function" then gq.Guide:Dismiss() end
    end)
end

-- Puts the arrow above GearQuest's tracker or on its own frame (after a setting changed).
local function Place()
    if not (holder and guide) then return end
    holder:ClearAllPoints()
    if Detached() then
        holder:SetParent(UIParent)
        holder:SetFrameStrata("MEDIUM")
        local p = ns.db.arrow.point
        if type(p) == "table" and type(p[1]) == "string" and type(p[3]) == "number" and type(p[4]) == "number" then
            holder:SetPoint(p[1], UIParent, p[2] or p[1], p[3], p[4])
        else
            holder:SetPoint("TOP", UIParent, "TOP", 0, -160)
        end
        holder:EnableMouse(not ns.db.arrow.locked)
        holder:SetShown(guide:IsShown())
        closeBtn:Show()
        Skin.Quiet(guide, guide.SetAlpha, 0)
        guide:EnableMouse(false)
    else
        holder:SetParent(guide)
        holder:SetPoint("TOP", guide, "TOP", 0, -4)
        holder:SetFrameLevel(guide:GetFrameLevel() + 2)
        holder:EnableMouse(false)
        holder:Show()
        closeBtn:Hide()
        Skin.Quiet(guide, guide.SetAlpha, 1)
        guide:EnableMouse(true)
    end
end

local function Setup()
    local gq = GQ()
    local frame = gq and gq.Guide and gq.Guide.frame
    if not frame or guide then return guide ~= nil end
    guide = frame
    BuildHolder()
    arrow = ns.Arrow.Create(holder)
    arrow.frame:SetPoint("TOP", holder, "TOP", 0, 0)
    if frame.arrow then
        Skin.Hide(frame.arrow) -- GearQuest sets alpha 1 every frame; the hook puts 0 back
        hooksecurefunc(frame.arrow, "SetTexCoord", ns.Guard("gqArrow", function(_, left) Draw(left) end))
    end
    Skin.Hide(T(frame.distance))
    -- in free mode GearQuest's (invisible) guide frame still decides when there is something to show
    frame:HookScript("OnShow", function() if Detached() and holder then holder:Show() end end)
    frame:HookScript("OnHide", function() if Detached() and holder then holder:Hide() end end)
    Skin.Hook(frame, "SetAlpha", function(self, a)
        if Skin.IsBusy(self) or not Detached() or a == 0 then return end
        Skin.Quiet(self, self.SetAlpha, 0)
    end)
    StyleClose(frame)
    arrow.Draw("NONE")
    Place()
    return true
end

function M.Enable()
    if Setup() then return end
    local gq = GQ()
    if gq and gq.Guide and type(gq.Guide.Init) == "function" then
        hooksecurefunc(gq.Guide, "Init", ns.Guard("gqArrow", Setup))
    end
end

function M.ResetPosition()
    ns.db.arrow.point = nil
    ns.Run("gqArrow", Place)
end

ns.OnRefresh(function()
    if M.status == "active" and arrow then
        ns.Run("gqArrow", function()
            arrow.Layout()
            lastIndex = nil
            Place()
        end)
    end
end)
