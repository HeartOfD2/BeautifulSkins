-- Waypoint UI: the in-world waypoint (icon, beam, distance and arrival text), the pinpoint plate and the off-screen
-- navigator arrow in the accent colour, the texts in the EllesmereUI font. Waypoint UI tints these frames through
-- their own SetTint / SetBeamTint / SetIconRecolor whenever the tracked target changes; post-hooks put the accent back
-- right after. Option "Waypoint UI's colours" leaves the colours alone (quest state colours stay).
local _, ns = ...

local FRAMES = { "WUIWaypointFrame", "WUIPinpointFrame", "WUINavigatorFrame" }
local TEXTS = {
    { "WUIWaypointFrame", "Footer", "InfoText" },
    { "WUIWaypointFrame", "Footer", "DistanceText" },
    { "WUIWaypointFrame", "Footer", "ArrivalTimeText" },
    { "WUIPinpointFrame", "Foreground", "Content" },
}

local M = ns.Modules.Register("waypoint", { addon = "WaypointUI", setting = "waypoint", label = "Waypoint UI: colours" })

local Skin = ns.Skin

local function Settings()
    return ns.db.waypoint
end

local function AccentOn()
    return M.status == "active" and Settings().color == "accent"
end

local function Frame(name)
    local f = rawget(_G, name)
    return type(f) == "table" and f or nil
end

local function Tint(frame)
    if not AccentOn() then return end
    local color = ns.AccentTable(1)
    if type(frame.SetTint) == "function" then Skin.Quiet(frame, frame.SetTint, color) end
    if type(frame.SetBeamTint) == "function" then Skin.Quiet(frame, frame.SetBeamTint, color) end
    if Settings().recolorIcon and type(frame.SetIconRecolor) == "function" then
        Skin.Quiet(frame, frame.SetIconRecolor, true)
    end
end

local function HookFrame(frame)
    local after = ns.Guard("waypoint", function(self)
        if Skin.IsBusy(self) then return end
        Tint(self)
    end)
    Skin.Hook(frame, "SetTint", after)
    Skin.Hook(frame, "SetBeamTint", after)
    Skin.Hook(frame, "SetIconRecolor", after)
end

-- Waypoint UI's text elements carry a font object (CreateFont) that every text of the same kind shares; its face
-- becomes ours, size and outline stay.
local function Fonts()
    if not Settings().font then return end
    local path = ns.Font()
    local seen = {}
    for _, p in ipairs(TEXTS) do
        local frame = Frame(p[1])
        local holder = frame and frame[p[2]]
        local element = holder and holder[p[3]]
        local fo = type(element) == "table" and element.__fontObject or nil
        if fo and not seen[fo] and type(fo.GetFont) == "function" then
            seen[fo] = true
            local _, size, flags = fo:GetFont()
            pcall(fo.SetFont, fo, path, size or 14, flags or "")
        end
    end
end

local function Apply()
    for _, name in ipairs(FRAMES) do
        local frame = Frame(name)
        if frame then
            HookFrame(frame)
            Tint(frame)
        end
    end
    Fonts()
end

function M.Enable()
    Apply()
    C_Timer.After(2, ns.Guard("waypoint", Apply)) -- Waypoint UI sets its fonts during its own login work
end

ns.OnRefresh(function()
    if M.status == "active" then ns.Run("waypoint", Apply) end
end)
