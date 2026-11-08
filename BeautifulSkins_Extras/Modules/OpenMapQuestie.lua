-- OpenMap: Questie's icons that Questie draws while OpenMap's map is open stay over the map's art (the player's find,
-- 08.11.2026: a townsfolk kind switched off and on again in Questie's options, with the map open, was missing on OpenMap's
-- map until the map was closed and opened again; the same holds for every icon Questie adds with the map open).
-- Why: OpenMap lifts Questie's icons above the art of its stitched map as HereBeDragons places them (Map/Extras.lua Lift,
-- in its wrapper of the pins provider's HandlePin). Questie draws from a queue (Modules/Map/QuestieMap.lua ProcessQueue):
-- HBDPins:AddWorldMapIconMap places the icon, and OpenMap lifts it, right there; straight after, Questie calls
-- QuestieMap.utils.SetDrawOrder(frame), which fixes the frame level at 2016 and up again: under OpenMap's art. Opening the
-- map places every icon afresh (the provider's RefreshAllData, lifted after Questie's order), so only icons drawn with the
-- map open were hidden.
-- Fix: a post-hook on QuestieMap.utils.SetDrawOrder lifts the icon again exactly as OpenMap does (Questie's own order among
-- its icons kept: level - QUESTIE_BASE + S.artTop + 1), only while OpenMap's map is stitched and the icon sits on a pin of
-- the world map. Nothing of OpenMap's or Questie's is replaced; frame levels of addon frames only, no Blizzard frame.
-- Hook points (Questie 12.6.4, OpenMap v0.8.2; checked by tools/openmap_contract.py, Questie next to the OpenMap folder):
-- QuestieLoader:ImportModule("QuestieMap").utils.SetDrawOrder, OpenMap.MapStitch.artTop, mod.IsStitched, QUESTIE_BASE 2015
-- and the formula of Map/Extras.lua Lift, a map pin's .icon and .owningMap (HereBeDragons' pins on WorldMapFrame).
local _, ns = ...

local M = ns.Modules.Register("openmapQuestie", { addon = "OpenMap", label = "OpenMap: Questie's icons over the map" })

local QM = { lifted = 0 }
ns.OpenMapQuestie = QM

local QUESTIE_BASE = 2015 -- OpenMap's (Map/Extras.lua): the fixed frame level Questie's map icons start from

local function Stitch()
    local om = rawget(_G, "OpenMap")
    local s = type(om) == "table" and om.MapStitch
    return type(s) == "table" and s or nil
end

-- The icon again above OpenMap's art, as OpenMap's Lift does, while it is on a pin of OpenMap's stitched map.
local function Lift(frame)
    if type(frame) ~= "table" or type(frame.GetParent) ~= "function" then return end
    local pin = frame:GetParent()
    if type(pin) ~= "table" or rawget(pin, "icon") ~= frame or rawget(pin, "owningMap") ~= rawget(_G, "WorldMapFrame") then
        return -- (a minimap icon, or one not on the map now)
    end
    local mod = ns.OpenMap and ns.OpenMap.Mod()
    if not (mod and type(mod.IsStitched) == "function" and mod.IsStitched()) then return end
    local S = Stitch()
    local top = S and S.artTop
    if type(top) ~= "number" then return end
    local level = frame:GetFrameLevel()
    if type(level) ~= "number" or level > top then return end
    frame:SetFixedFrameLevel(false)
    frame:SetFrameLevel(level - QUESTIE_BASE + top + 1)
    frame:SetFixedFrameLevel(true)
    QM.lifted = QM.lifted + 1
end

local hooked = false

local function HookQuestie()
    if hooked then return end
    local loader = rawget(_G, "QuestieLoader")
    if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then return end
    local ok, map = pcall(loader.ImportModule, loader, "QuestieMap")
    local utils = ok and type(map) == "table" and ns.T(map.utils)
    if not (utils and type(utils.SetDrawOrder) == "function") then return end
    hooked = true
    hooksecurefunc(utils, "SetDrawOrder", ns.Guard("openmapQuestie", Lift))
end

-- Whether Questie's drawing is hooked (for the tests and the module's state).
function QM.Hooked() return hooked end

function M.Enable()
    if not (ns.OpenMap and ns.OpenMap.Mod()) then return end
    ns.OnAddonLoaded("Questie", function() ns.Run("openmapQuestie", HookQuestie) end)
end
