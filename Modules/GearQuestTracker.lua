-- GearQuest Forever: its tracker ("GearQuest Tracker") in the look of the EllesmereUI quest tracker and of the
-- Forever tracker column: background, title in the accent with a divider, hunt names and descriptions in the
-- tracker's fonts and colours, flat "Enable Guide" boxes. The tracker stays where GearQuest puts it. Post-hooks on
-- GearQuest's Refresh restyle new rows; when a font changed, GearQuest lays the rows out once more.
local _, ns = ...
local L = ns.L
local Track, Skin = ns.TrackerStyle, ns.Skin

local M = ns.Modules.Register("gqTracker", { addon = "GearQuestForever", setting = "gqTracker",
    label = "GearQuest: tracker" })

local deco          -- { bg, divider } on the tracker frame
local relayout = false

local function GQ()
    local gq = rawget(_G, "GearQuest")
    return type(gq) == "table" and gq or nil
end

local function Decor(frame, title)
    if not deco then
        deco = {}
        deco.bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        deco.bg:SetPoint("TOPLEFT", frame, "TOPLEFT", -6, 4)
        deco.bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 4, -4)
        deco.divider = frame:CreateTexture(nil, "ARTWORK")
        deco.divider:SetHeight(1)
    end
    deco.divider:ClearAllPoints()
    deco.divider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    deco.divider:SetPoint("RIGHT", frame, "RIGHT", -2, 0)
    return deco
end

local function StyleRow(row, font, titleSize, lineSize)
    local changed = false
    changed = Track.StyleFont(row.name, titleSize, font) or changed
    changed = Track.StyleFont(row.desc, lineSize, font) or changed
    changed = Track.StyleFont(row.guideLabel, lineSize, font) or changed
    Track.SetColor(row.name, Track.TitleColor())
    Track.SetColor(row.desc, Track.LINE)
    local r, g, b = ns.Accent()
    if row.guideLabel then row.guideLabel:SetTextColor(r, g, b) end
    if row.guideCheck then Skin.Check(row.guideCheck) end
    local hl = row.GetHighlightTexture and row:GetHighlightTexture()
    if hl then
        hl:SetColorTexture(r, g, b, 0.10)
        hl:SetAlpha(1)
    end
    return changed
end

local function Style()
    local gq = GQ()
    local tracker = gq and gq.Tracker
    local frame = tracker and tracker.frame
    if not frame then return end
    local font = Track.Font()
    local headerSize, titleSize, lineSize = Track.Sizes()
    local r, g, b = ns.Accent()
    local changed = false

    if tracker.title then
        changed = Track.StyleFont(tracker.title, headerSize, font) or changed
        tracker.title:SetTextColor(r, g, b)
        local d = Decor(frame, tracker.title)
        d.divider:SetColorTexture(r, g, b, 1)
        local opacity = ns.Clamp(ns.db.gqTracker.background, 0, 100, 60) / 100
        local br, bg, bb = Track.BackgroundColor()
        d.bg:SetColorTexture(br, bg, bb, opacity)
        d.bg:SetShown(opacity > 0)
    end
    local collapse = tracker.collapseBtn
    if collapse and collapse.GetNormalTexture then Track.Tint(collapse:GetNormalTexture(), r, g, b) end

    for _, row in ipairs(tracker.entryRows or {}) do
        changed = StyleRow(row, font, titleSize, lineSize) or changed
    end
    -- GearQuest measured the rows with the old font: lay them out once more (our hook skips that pass).
    if changed and not relayout then
        C_Timer.After(0, function()
            relayout = true
            pcall(tracker.Refresh, tracker)
            relayout = false
        end)
    end
end

function M.Enable()
    local gq = GQ()
    if not (gq and gq.Tracker) then return end
    hooksecurefunc(gq.Tracker, "Refresh", ns.Guard("gqTracker", function()
        if not relayout then Style() end
    end))
    if type(gq.Tracker.UpdateCollapseButton) == "function" then
        hooksecurefunc(gq.Tracker, "UpdateCollapseButton", ns.Guard("gqTracker", function(self)
            local btn = self.collapseBtn
            if btn and btn.GetNormalTexture then Track.Tint(btn:GetNormalTexture(), ns.Accent()) end
        end))
    end
    Style()
    -- Option: the hunts as a section of the Forever tracker column (needs Shortest Path Forever or SkillUp Forever).
    if ns.db.gqTracker.column then
        local tries = 0
        local ticker
        local function Try()
            tries = tries + 1
            if ns.GearQuestColumn.Start() or tries >= 10 then
                if ticker then ticker:Cancel() end
                ticker = nil
                if not ns.GearQuestColumn.IsOn() then
                    ns.Say(L["The Forever tracker column is missing (Shortest Path Forever or SkillUp Forever): GearQuest keeps its own tracker."])
                end
            end
        end
        ticker = C_Timer.NewTicker(1, ns.Guard("gqTracker", Try), 10)
        Try()
    end
end

ns.OnRefresh(function()
    if M.status == "active" then ns.Run("gqTracker", Style) end
end)
