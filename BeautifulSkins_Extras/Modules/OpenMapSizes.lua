-- OpenMap: a size of its own for each kind of icon on OpenMap's map (the player's wish, 08.11.2026: flight masters
-- bigger, say). Each kind gets a factor on OpenMap's "Icon size" (1 = 100 %: as big as every other icon), live.
-- OpenMap keeps its icons in named pin sets (Map/Stitch.lua S.PinSet(key)). A pin gets its size only in S.AddPin
-- (pin:SetScale(S.iconScale)) and in S.SetIconScale (every pin of every set); nothing else of OpenMap's scales a pin.
-- Post-hooks on both put every pin of a kind with a factor at S.iconScale times the factor. Questie's icons on OpenMap's
-- map are not OpenMap's pins (HereBeDragons, Map/Extras.lua) and keep the size Questie's options give them.
-- Hook points (OpenMap v0.8.2, checked by tools/openmap_contract.py): the global OpenMap's MapStitch (ns.MapStitch),
-- S.AddPin, S.SetIconScale, S.GetPinSet, S.iconScale, set.pins, the set keys in KINDS below and "tf_" .. key for each
-- of mod.TOWNSFOLK (Map/Townsfolk.lua). Post-hooks on OpenMap's own table only; OpenMap's own frames, no Blizzard ones.
local _, ns = ...

local M = ns.Modules.Register("openmapSizes", { addon = "OpenMap", label = "OpenMap: icon size by kind" })

local SZ = {}
ns.OpenMapSizes = SZ

-- The kinds of the page "On the map", in its order: our key and OpenMap's pin sets of the kind. Each townsfolk kind is
-- a kind of its own, under the key of its set ("tf_vendor" ...).
SZ.KINDS = {
    { key = "dungeons", sets = { "dungeons" } },
    { key = "flight", sets = { "flight" } },
    { key = "boats", sets = { "boats" } }, -- (airships too: OpenMap puts them among the boats)
    { key = "zeppelins", sets = { "zeppelins" } },
    { key = "quests", sets = { "quests" } },
    { key = "group", sets = { "group" } },
    { key = "friends", sets = { "friends", "friendzones" } },
    { key = "userpins", sets = { "userpins" } },
    { key = "notes", sets = { "notes" } },
    { key = "waypoint", sets = { "waypoint" } },
}
SZ.MIN, SZ.MAX, SZ.STEP = 50, 200, 5 -- percent of OpenMap's icon size (the sliders')

local SETS_OF = {} -- our key -> OpenMap's set keys
for _, kind in ipairs(SZ.KINDS) do SETS_OF[kind.key] = kind.sets end

local stitch      -- OpenMap's MapStitch, once hooked
local any = false -- whether any kind has a factor other than 1 (the hook on S.AddPin has nothing to do otherwise)
local kindOf = setmetatable({}, { __mode = "k" }) -- OpenMap's set -> our key, or false (a set of no kind of ours)

local function Saved()
    return ns.db.openmap.sizes
end

local function Stitch()
    local om = rawget(_G, "OpenMap")
    local s = type(om) == "table" and om.MapStitch
    if type(s) ~= "table" then return nil end
    for _, fn in ipairs({ "AddPin", "SetIconScale", "GetPinSet" }) do
        if type(s[fn]) ~= "function" then return nil end
    end
    return s
end

-- OpenMap's townsfolk kinds ({ key = "vendor", name = ... }), or an empty list.
function SZ.Townsfolk()
    local mod = ns.OpenMap and ns.OpenMap.Mod()
    return mod and ns.T(mod.TOWNSFOLK) or {}
end

local function SetsOf(key)
    if SETS_OF[key] then return SETS_OF[key] end
    if type(key) == "string" and key:sub(1, 3) == "tf_" then return { key } end
    return {}
end

-- Every key a factor can have: ours and one per townsfolk kind.
local function AllKeys()
    local keys = {}
    for _, kind in ipairs(SZ.KINDS) do keys[#keys + 1] = kind.key end
    for _, folk in ipairs(SZ.Townsfolk()) do
        if type(folk) == "table" and type(folk.key) == "string" then keys[#keys + 1] = "tf_" .. folk.key end
    end
    return keys
end

-- The kind of one of OpenMap's sets. A set is made once and kept, so each is looked up once: every set of every kind
-- that exists by now is noted, a set found nowhere is no kind of ours.
local function KindOf(set)
    local kind = kindOf[set]
    if kind ~= nil then return kind end
    for _, key in ipairs(AllKeys()) do
        for _, setKey in ipairs(SetsOf(key)) do
            local s = stitch.GetPinSet(setKey)
            if s ~= nil then kindOf[s] = key end
        end
    end
    if kindOf[set] == nil then kindOf[set] = false end
    return kindOf[set]
end

local function Clamp(f)
    f = tonumber(f)
    if not f then return 1 end
    return math.max(SZ.MIN / 100, math.min(SZ.MAX / 100, f))
end

-- The factor of a kind (1 while none is set).
function SZ.Get(key)
    local f = Saved()[key]
    return f ~= nil and Clamp(f) or 1
end

local function Base()
    return tonumber(stitch and stitch.iconScale) or 1
end

local function Recount()
    any = false
    for _, f in pairs(Saved()) do
        if Clamp(f) ~= 1 then any = true return end
    end
end

-- Every pin of the kind at OpenMap's icon size times the kind's factor.
local function ApplyKind(key)
    if not stitch then return end
    local k = Base() * SZ.Get(key)
    for _, setKey in ipairs(SetsOf(key)) do
        local set = stitch.GetPinSet(setKey)
        local pins = type(set) == "table" and ns.T(set.pins)
        if pins then
            for _, pin in ipairs(pins) do pin:SetScale(k) end
        end
    end
end

-- After OpenMap's S.SetIconScale (every pin at the new size): the kinds with a factor of their own again.
local function ApplyAll()
    if not any then return end
    for key in pairs(Saved()) do
        if SZ.Get(key) ~= 1 then ApplyKind(key) end
    end
end

-- After OpenMap's S.AddPin: its new pin is the set's last.
local function OnAddPin(set)
    if not any or type(set) ~= "table" then return end
    local key = KindOf(set)
    if not key then return end
    local f = SZ.Get(key)
    if f == 1 then return end
    local pins = ns.T(set.pins)
    local pin = pins and pins[#pins]
    if pin then pin:SetScale(Base() * f) end
end

-- Whether the sizes work (OpenMap loaded and as we know it).
function SZ.Available()
    return M.status == "active" and stitch ~= nil
end

-- A kind's factor, live (1 = as every other icon; kept out of the database).
function SZ.Set(key, f)
    local pct = math.floor(Clamp(f) * 100 / SZ.STEP + 0.5) * SZ.STEP -- (whole percent: 1.5, not 1.5000000000000002)
    f = pct ~= 100 and pct / 100 or nil
    Saved()[key] = f
    Recount()
    ns.Run("openmapSizes", ApplyKind, key)
end

-- Kinds back to 100 %: the given keys, or all of them.
function SZ.Reset(keys)
    for _, key in ipairs(keys or AllKeys()) do
        if Saved()[key] ~= nil then SZ.Set(key, 1) end
    end
end

-- The keys of the townsfolk kinds, for the reset on their page.
function SZ.TownsfolkKeys()
    local keys = {}
    for _, folk in ipairs(SZ.Townsfolk()) do
        if type(folk) == "table" and type(folk.key) == "string" then keys[#keys + 1] = "tf_" .. folk.key end
    end
    return keys
end

-- The keys of the page "On the map".
function SZ.MapKeys()
    local keys = {}
    for _, kind in ipairs(SZ.KINDS) do keys[#keys + 1] = kind.key end
    return keys
end

function M.Enable()
    local s = Stitch()
    if not s then return end
    stitch = s
    hooksecurefunc(s, "AddPin", ns.Guard("openmapSizes", OnAddPin))
    hooksecurefunc(s, "SetIconScale", ns.Guard("openmapSizes", ApplyAll))
    Recount()
    ApplyAll()
end
