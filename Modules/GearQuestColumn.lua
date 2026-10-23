-- GearQuest Forever in the Forever tracker column (option): one tracker for Shortest Path Forever's journey, SkillUp's
-- reagents and GearQuest's hunts. Our own section (ObjectiveTrackerModuleTemplate) lists the hunts GearQuest tracks and
-- is attached to the shared column through ForeverTrackerHost.Attach, the way SkillUp and Shortest Path attach theirs.
-- GearQuest's own tracker window stays hidden meanwhile and the arrow is free (Modules\GearQuestArrow.lua).
-- Left click on a hunt: arrow on/off; right click: the hunt in GearQuest's window. Part of the "gqTracker" skin.
local _, ns = ...
local L = ns.L
local Skin = ns.Skin

local MODULE_NAME = "BeautifulSkinsGearQuestTracker"
local MAX_WORDS = 14

local Column = {}
ns.GearQuestColumn = Column

local module

local function GQ()
    local gq = rawget(_G, "GearQuest")
    return type(gq) == "table" and gq or nil
end

local function Host()
    local host = rawget(_G, "ForeverTrackerHost")
    return type(host) == "table" and type(host.Attach) == "function" and host or nil
end

local function FirstWords(text, count)
    if type(text) ~= "string" or text == "" then return "" end
    local words = {}
    for word in text:gsub("\n+", " "):gmatch("%S+") do
        if #words >= count then return table.concat(words, " ") .. "..." end
        words[#words + 1] = word
    end
    return table.concat(words, " ")
end

-- The hunt's one-line description as GearQuest's tracker builds it.
local function Describe(gq, entry)
    local data = gq.Data
    local ok, text = pcall(function()
        local t = entry.instructions
        if entry.sourceType == "profession" and type(data.GetProfessionInstructions) == "function" then
            t = data:GetProfessionInstructions(entry)
        elseif type(data.VendorBoughtLine) == "function" then
            local line = data:VendorBoughtLine(entry)
            if line and line ~= "" then t = line end
        end
        if type(data.SanitizeText) == "function" then t = data:SanitizeText(t) or t end
        return t
    end)
    return FirstWords(ok and text or entry.instructions, MAX_WORDS)
end

local function Name(gq, entry)
    local ok, name = pcall(gq.Data.GetEntryDisplayName, gq.Data, entry)
    if ok and type(name) == "string" then return name end
    return entry.itemId and ("Item " .. entry.itemId) or "?"
end

local Mix = {}

function Mix:LayoutContents()
    local gq = GQ()
    if not (gq and gq.Tracker and gq.Data) then return end
    local ok, entries = pcall(gq.Tracker.GetTrackedEntries, gq.Tracker)
    if not ok or type(entries) ~= "table" then return end
    local guided = gq.Guide and type(gq.Guide.GuidedId) == "function" and gq.Guide:GuidedId() or nil
    local C = OBJECTIVE_TRACKER_COLOR
    for _, entry in ipairs(entries) do
        local block = self:GetBlock(entry.id)
        block.bsEntry = entry
        block:SetHeader(Name(gq, entry))
        block:AddObjective("desc", Describe(gq, entry))
        if guided == entry.id then
            block:AddObjective("guide", L["Arrow on (click to stop)"], nil, nil, nil, C and C.Complete)
        else
            block:AddObjective("guide", L["Click: show the arrow"])
        end
        if not self:LayoutBlock(block) then return end
    end
end

function Mix:OnBlockHeaderClick(block, mouseButton)
    local gq = GQ()
    local entry = block and block.bsEntry
    if not (gq and entry) then return end
    if mouseButton == "RightButton" then
        if gq.Tracker and type(gq.Tracker.OpenHunt) == "function" then gq.Tracker:OpenHunt(entry.id) end
        return
    end
    local guide = gq.Guide
    if not guide then return end
    if type(guide.GuidedId) == "function" and guide:GuidedId() == entry.id then
        guide:Dismiss()
    else
        guide:ShowEntry(entry)
    end
    self:MarkDirty()
end

function Column.IsOn()
    return ns.db.gqTracker.column == true and module ~= nil
end

local function Dirty()
    if module then module:MarkDirty() end
end

-- GearQuest's own tracker window: hidden while its hunts are in the column.
local function HideOwnTracker(gq)
    local frame = gq.Tracker and gq.Tracker.frame
    if not frame then return end
    local function Keep(self)
        if Column.IsOn() and self:IsShown() then self:Hide() end
    end
    Skin.Hook(frame, "Show", Keep)
    Skin.Hook(frame, "SetShown", Keep)
    Keep(frame)
end

local function Attach()
    local host = Host()
    if host and module then pcall(host.Attach, module) end
end

-- Builds and attaches the section; false when the column (Shortest Path / SkillUp) or the tracker is not there.
function Column.Start()
    if module then return true end
    local gq = GQ()
    local host = Host()
    if not (gq and gq.Tracker and host and rawget(_G, "ObjectiveTrackerFrame")) then return false end
    local parent = type(host.GetParent) == "function" and host or UIParent
    module = CreateFrame("Frame", MODULE_NAME, parent, "ObjectiveTrackerModuleTemplate")
    Mixin(module, Mix)
    module:SetHeader(L["GearQuest hunts"])
    Attach()
    C_Timer.After(2, Attach) -- the column settles after the loading screen
    hooksecurefunc(gq.Tracker, "Refresh", ns.Guard("gqTracker", function()
        Dirty()
        HideOwnTracker(gq)
    end))
    if gq.Guide and type(gq.Guide.RefreshChecks) == "function" then
        hooksecurefunc(gq.Guide, "RefreshChecks", ns.Guard("gqTracker", Dirty))
    end
    if type(module.Update) == "function" then
        hooksecurefunc(module, "Update", ns.Guard("gqTracker", function(self)
            ns.TrackerStyle.StyleModule(self, ns.db.gqTracker.background, function() return true end)
        end))
    end
    HideOwnTracker(gq)
    Dirty()
    return true
end
