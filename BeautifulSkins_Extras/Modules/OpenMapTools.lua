-- OpenMap: map pins and the quill as switches of their own. Off takes the tool away completely, live, and on brings
-- back what the player had: OpenMap's own settings are only ever changed through its public module table
-- (OpenMap = its namespace, :GetModule("worldmap")), and the values we change are remembered in our database.
--   Pins off:  the "Drop a pin" mode ends at once, the pin list closes, your pins and shared pins stay off the map,
--              their buttons leave the map. A Ctrl-click on the map leaves nothing behind: the pin OpenMap makes is
--              taken back and the waypoint is the one from before the click. With Shortest Path Forever it plans a
--              journey there instead, as OpenMap's Shift-click does.
--   Quill off: drawing ends at once (on the map, on a pin, on a dungeon's map), your drawings stay hidden, their
--              buttons leave the map. Drawing for "Report a problem" stays: that is another tool.
-- Hook points (OpenMap v0.7.5-beta): mod.SetPinMode, mod.AddPin, mod:TogglePins, mod:ToggleSketch (post-hooks only),
-- mod.db.favorites / pinsHidden / pinsShared / sketchShown, mod.SetPinsHidden, mod.FinishPin, mod.RefreshPins,
-- mod.RefreshSketch, mod:RefreshPanel.
local _, ns = ...

local M = ns.Modules.Register("openmapTools", { addon = "OpenMap", label = "OpenMap: pins and quill" })

local OM = {}
ns.OpenMap = OM

local PIN_BUTTONS = { pin = true, pins = true }
local QUILL_BUTTONS = { quill = true, sketchShown = true }

-- OpenMap's map module, or nil while OpenMap is missing, off or changed beyond recognition.
function OM.Mod()
    local om = rawget(_G, "OpenMap")
    if type(om) ~= "table" or type(om.GetModule) ~= "function" then return nil end
    local ok, mod = pcall(om.GetModule, om, "worldmap")
    if not ok or type(mod) ~= "table" or type(mod.db) ~= "table" then return nil end
    return mod
end

-- OpenMap's options dialog and its menu (favourites, ticks) follow a change made here.
function OM.Notify()
    local om = rawget(_G, "OpenMap")
    if type(om) == "table" and type(om.NotifyOptions) == "function" then pcall(om.NotifyOptions) end
    local mod = OM.Mod()
    if mod and type(mod.RefreshPanel) == "function" then pcall(mod.RefreshPanel, mod) end
    if OM.OnChanged then pcall(OM.OnChanged) end
end

local function Settings()
    return ns.db.openmap
end

function OM.PinsOn() return Settings().pins ~= false end
function OM.QuillOn() return Settings().quill ~= false end

local function Call(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, ...)
    if not ok then ns.Modules.Fail("openmapTools", err) end
end

-- The map buttons (favourites) of a tool: taken off and remembered, or put back in their old order.
local function TakeButtons(mod, ids, store)
    local favs = ns.T(mod.db.favorites)
    if not favs then return end
    local saved = Settings().saved
    saved[store] = saved[store] or {}
    for i = #favs, 1, -1 do
        if ids[favs[i]] then
            table.insert(saved[store], 1, favs[i])
            table.remove(favs, i)
        end
    end
end

local function GiveButtons(mod, store)
    local favs = ns.T(mod.db.favorites)
    local saved = Settings().saved
    local list = saved[store]
    saved[store] = nil
    if not (favs and type(list) == "table") then return end
    for _, id in ipairs(list) do
        local present = false
        for _, f in ipairs(favs) do if f == id then present = true end end
        if not present then favs[#favs + 1] = id end
    end
end

---------------------------------------------------------------------------
-- Pins
---------------------------------------------------------------------------

local function PinsOff(mod)
    local saved = Settings().saved
    if saved.pinsHidden == nil then saved.pinsHidden = mod.db.pinsHidden == true end
    if saved.pinsShared == nil then saved.pinsShared = mod.db.pinsShared ~= false end
    mod.db.pinsShared = false
    if type(mod.PinMode) == "function" and mod.PinMode() then Call(mod.SetPinMode, false) end
    if type(mod.PinsShown) == "function" and mod.PinsShown() then Call(mod.TogglePins, mod, false) end
    if mod.db.pinsHidden ~= true then
        if type(mod.SetPinsHidden) == "function" then Call(mod.SetPinsHidden, true) else mod.db.pinsHidden = true end
    end
    TakeButtons(mod, PIN_BUTTONS, "pinButtons")
end

local function PinsBack(mod)
    local saved = Settings().saved
    if saved.pinsShared ~= nil then mod.db.pinsShared = saved.pinsShared end
    local hidden = saved.pinsHidden
    saved.pinsShared, saved.pinsHidden = nil, nil
    if hidden ~= nil and (mod.db.pinsHidden == true) ~= hidden then
        if type(mod.SetPinsHidden) == "function" then Call(mod.SetPinsHidden, hidden) else mod.db.pinsHidden = hidden end
    end
    GiveButtons(mod, "pinButtons")
end

-- The waypoint as it stood before a Ctrl-click: OpenMap's DropAtCursor calls SetPinMode(false) right before it drops
-- the pin (which sets the game's waypoint there), so the snapshot of that call is the one of the same frame.
local before

local function Snapshot()
    local snap = { at = GetTime() }
    if C_Map and type(C_Map.HasUserWaypoint) == "function" and type(C_Map.GetUserWaypoint) == "function" then
        local ok, has = pcall(C_Map.HasUserWaypoint)
        local point = ok and has and C_Map.GetUserWaypoint() or nil
        local pos = type(point) == "table" and point.position
        if pos then
            local x, y
            if type(pos.GetXY) == "function" then x, y = pos:GetXY() else x, y = pos.x, pos.y end
            if type(x) == "number" and type(y) == "number" then snap.point = { point.uiMapID, x, y } end
        end
    end
    local mod = OM.Mod()
    snap.own = mod and ns.T(mod.char) and mod.char.pin or nil
    before = snap
end

-- The game's waypoint back as it was before the click. What the game follows (super-tracking) is left alone: those
-- calls are protected on Forever (OpenMap's own attempt is blocked, so the click never changed it).
local function Restore(mod, snap)
    if type(mod.ClearPin) == "function" then mod.ClearPin() end -- the click's waypoint and OpenMap's TomTom point
    if not snap then return end
    local p = snap.point
    if p and C_Map and type(C_Map.SetUserWaypoint) == "function" and UiMapPoint
        and type(UiMapPoint.CreateFromCoordinates) == "function" then
        pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(p[1], p[2], p[3]))
    end
    if snap.own and ns.T(mod.char) then mod.char.pin = snap.own end
end

-- With Shortest Path Forever: a journey to the clicked point, as OpenMap's Shift-click plans one (its API, owner
-- "OpenMap"). False without it, or when it plans nothing (journeys off in its settings, no place to go).
local function Journey(mapID, x, y)
    local spf = rawget(_G, "ShortestPathForever")
    local api = type(spf) == "table" and ns.T(spf.API)
    if not (api and type(api.Navigate) == "function") then return false end
    local ok, started = pcall(api.Navigate, "OpenMap", mapID, x, y)
    return ok and started and true or false
end

-- A pin OpenMap just made (Ctrl-click) while pins are off: its card closes, the pin goes, the waypoint is the one from
-- before the click; with Shortest Path Forever a journey goes there instead.
local function TakeBackPin(mapID, x, y)
    if OM.PinsOn() then return end
    local mod = OM.Mod()
    local pins = mod and ns.T(mod.db.pins)
    local snap = before and before.at == GetTime() and before or nil
    before = nil
    if not (pins and ns.T(pins.list)) then return end
    if type(mod.FinishPin) == "function" then mod.FinishPin() end
    local newest = (tonumber(pins.nextId) or 1) - 1
    for i = #pins.list, 1, -1 do
        local p = pins.list[i]
        if type(p) == "table" and (p.id == newest or (p.map == mapID and p.note == "" and i == #pins.list)) then
            table.remove(pins.list, i)
            break
        end
    end
    -- (AddPin shows hidden pins again so the new one is not dropped out of sight)
    if mod.db.pinsHidden ~= true and type(mod.SetPinsHidden) == "function" then mod.SetPinsHidden(true) end
    if type(mod.RefreshPins) == "function" then mod.RefreshPins() end
    Restore(mod, snap)
    if type(mapID) == "number" and type(x) == "number" and type(y) == "number" then Journey(mapID, x, y) end
end

---------------------------------------------------------------------------
-- Quill
---------------------------------------------------------------------------

local function Sketching(mod)
    return type(mod.IsSketching) == "function" and mod:IsSketching() and true or false
end

local function QuillOff(mod)
    local saved = Settings().saved
    if saved.sketchShown == nil then saved.sketchShown = mod.db.sketchShown ~= false end
    mod.db.sketchShown = false
    if Sketching(mod) and not (type(mod.IsReporting) == "function" and mod.IsReporting()) then
        Call(mod.ToggleSketch, mod, false)
    end
    if type(mod.RefreshSketch) == "function" then Call(mod.RefreshSketch) end
    TakeButtons(mod, QUILL_BUTTONS, "quillButtons")
end

local function QuillBack(mod)
    local saved = Settings().saved
    if saved.sketchShown ~= nil then mod.db.sketchShown = saved.sketchShown end
    saved.sketchShown = nil
    if type(mod.RefreshSketch) == "function" then Call(mod.RefreshSketch) end
    GiveButtons(mod, "quillButtons")
end

-- The quill went up while it is off: put it down again (the report's drawing, sess, is left alone).
local function StopQuill(mod, on, _, _, sess)
    if OM.QuillOn() or sess ~= nil or on == false then return end
    if Sketching(mod) then mod:ToggleSketch(false) end
end

---------------------------------------------------------------------------
-- Switches
---------------------------------------------------------------------------

-- Brings OpenMap in line with both switches (at login and after every change).
function OM.Apply()
    if M.status ~= "active" then return end
    local mod = OM.Mod()
    if not mod then return end
    if OM.PinsOn() then PinsBack(mod) else PinsOff(mod) end
    if OM.QuillOn() then QuillBack(mod) else QuillOff(mod) end
end

function OM.SetPins(on)
    Settings().pins = on and true or false
    ns.Run("openmapTools", OM.Apply)
    OM.Notify()
end

function OM.SetQuill(on)
    Settings().quill = on and true or false
    ns.Run("openmapTools", OM.Apply)
    OM.Notify()
end

local function Hook(mod, key, fn)
    if type(mod[key]) == "function" then hooksecurefunc(mod, key, ns.Guard("openmapTools", fn)) end
end

function M.Enable()
    local mod = OM.Mod()
    if not mod then return end
    Hook(mod, "SetPinMode", function(on)
        if OM.PinsOn() then return end
        if on then mod.SetPinMode(false) else Snapshot() end
    end)
    Hook(mod, "AddPin", TakeBackPin)
    Hook(mod, "TogglePins", function()
        if not OM.PinsOn() and type(mod.PinsShown) == "function" and mod.PinsShown() then mod:TogglePins(false) end
    end)
    Hook(mod, "ToggleSketch", StopQuill)
    OM.Apply()
end
