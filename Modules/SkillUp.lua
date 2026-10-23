-- SkillUp Forever: its tracked-reagents section in the shared Forever tracker column, in the EllesmereUI quest tracker
-- look (the same look EUI RestedXP Skin gives Shortest Path Forever's journey section). Only SkillUp's own section is
-- touched, through a post-hook on its Update; no SkillUp function is replaced.
local _, ns = ...

local MODULE_NAME = "SkillUpForeverObjectiveTracker" -- SkillUp's section (ObjectiveTrackerModuleTemplate)

local M = ns.Modules.Register("skillup", { addon = "SkillUpForever", setting = "skillup",
    label = "SkillUp Forever: reagents tracker" })

local hooked = false

local function IsOn()
    return M.status == "active"
end

local function Style(module)
    ns.TrackerStyle.StyleModule(module, ns.db.skillup.background, IsOn)
end

-- Returns true once the section exists (SkillUp creates it after login).
local function Apply()
    local module = rawget(_G, MODULE_NAME)
    if type(module) ~= "table" or type(module.Update) ~= "function" then return false end
    if not hooked then
        hooked = true
        hooksecurefunc(module, "Update", ns.Guard("skillup", Style))
    end
    Style(module)
    return true
end

function M.Enable()
    if Apply() then return end
    local ticker
    ticker = C_Timer.NewTicker(1, ns.Guard("skillup", function()
        if Apply() and ticker then
            ticker:Cancel()
            ticker = nil
        end
    end), 30)
end

ns.OnRefresh(function()
    if IsOn() then ns.Run("skillup", Apply) end
end)
