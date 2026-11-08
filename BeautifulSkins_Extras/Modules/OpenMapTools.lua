-- OpenMap: map pins and the quill as switches of their own. Off takes the tool away completely, live, and on brings
-- back what the player had: OpenMap's own settings are only ever changed through its public module table
-- (OpenMap = its namespace, :GetModule("worldmap")), and the values we change are remembered in our database.
--   Pins off:  the "Drop a pin" mode ends at once, the pin list closes, your pins and shared pins stay off the map,
--              their buttons leave the map. A Ctrl-click on the map does nothing at all: OpenMap's drop never runs, so
--              it neither makes a pin nor touches the game's waypoint (which is Shortest Path Forever's bend while a
--              journey runs).
--   Quill off: drawing ends at once (on the map, on a pin, on a dungeon's map), your drawings stay hidden, their
--              buttons leave the map. Drawing for "Report a problem" stays: that is another tool.
-- Hook points (OpenMap v0.8.2, checked by tools/openmap_contract.py): mod.SetPinMode, mod:TogglePins, mod:ToggleSketch (post-hooks),
-- mod.db.favorites / pinsHidden / pinsShared / sketchShown, mod.SetPinsHidden, mod.RefreshSketch, mod:RefreshPanel.
-- One exception to "post-hooks only" (07.11.2026, for the user's wish that Ctrl-click does nothing): mod.DropWaypoint (Ctrl-click and the pin mode's
-- click, WorldMap.lua DropAtCursor) gets a wrapper that stops it while pins are off. A post-hook comes too late: OpenMap
-- has already replaced the game's waypoint, which during a journey is Shortest Path Forever's bend, and SPF then loses
-- its guidance. The wrapper only touches OpenMap's own module table (no Blizzard code) and passes through otherwise.
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

-- The map buttons (favourites) of a tool: taken off and remembered, or put back where they were. saved.order keeps the
-- row of buttons as it stood before the first tool left (both tools may be off, and come back in any order); a button
-- comes back after the nearest one that stood before it and is there again. Lists saved before the order existed come
-- back at the end, as before.
local BUTTON_STORES = { "pinButtons", "quillButtons" }

local function IndexOf(list, value)
    for i, v in ipairs(list) do
        if v == value then return i end
    end
end

-- The row before anything is taken; a button the player added since joins it after the one before it.
local function RememberOrder(saved, favs)
    local order = saved.order
    if type(order) ~= "table" then
        order = {}
        for i, id in ipairs(favs) do order[i] = id end
        saved.order = order
        return
    end
    for i, id in ipairs(favs) do
        if not IndexOf(order, id) then
            local before = i > 1 and IndexOf(order, favs[i - 1])
            table.insert(order, before and before + 1 or 1, id)
        end
    end
end

local function TakeButtons(mod, ids, store)
    local favs = ns.T(mod.db.favorites)
    if not favs then return end
    local saved = Settings().saved
    local taking = false
    for _, id in ipairs(favs) do
        if ids[id] then taking = true end
    end
    if not taking then return end
    RememberOrder(saved, favs)
    saved[store] = saved[store] or {}
    for i = #favs, 1, -1 do
        if ids[favs[i]] then
            table.insert(saved[store], 1, favs[i])
            table.remove(favs, i)
        end
    end
end

-- Where a returning button goes: after the nearest button that stood before it in the remembered row and is there now.
local function Slot(favs, order, id)
    local at = type(order) == "table" and IndexOf(order, id)
    if not at then return #favs + 1 end
    for k = at - 1, 1, -1 do
        local present = IndexOf(favs, order[k])
        if present then return present + 1 end
    end
    return 1
end

local function GiveButtons(mod, store)
    local favs = ns.T(mod.db.favorites)
    local saved = Settings().saved
    local list = saved[store]
    saved[store] = nil
    if favs and type(list) == "table" then
        for _, id in ipairs(list) do
            if not IndexOf(favs, id) then table.insert(favs, Slot(favs, saved.order, id), id) end
        end
    end
    for _, other in ipairs(BUTTON_STORES) do
        if saved[other] ~= nil then return end
    end
    saved.order = nil -- every button is back
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

-- Ctrl-click (and a click in pin mode) while pins are off: OpenMap's drop does not run at all.
local dropBlocked = false

local function BlockDrop(mod)
    local drop = mod.DropWaypoint
    if type(drop) ~= "function" or dropBlocked then return end
    dropBlocked = true
    mod.DropWaypoint = function(...)
        if M.status == "active" and not OM.PinsOn() then return end
        return drop(...)
    end
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
        if on and not OM.PinsOn() then mod.SetPinMode(false) end
    end)
    BlockDrop(mod)
    Hook(mod, "TogglePins", function()
        if not OM.PinsOn() and type(mod.PinsShown) == "function" and mod.PinsShown() then mod:TogglePins(false) end
    end)
    Hook(mod, "ToggleSketch", StopQuill)
    OM.Apply()
end
