-- Links this skin pack to its host addon (BeautifulSkins, or the host of a single package such as BeautifulAttune):
-- the host is named in this pack's TOC (## X-Beautiful-Host) and keeps its namespace in the global of the same name.
-- Reads the pack does not answer itself (Kit, Theme, Fonts, Env, Say, Queue ...) fall through to the host; whatever
-- the pack defines stays its own, so two packs never overwrite each other. Same file in every pack
-- (tools/templates/Pack.lua, copied by tools/sync_shared.py).
local addonName, ns = ...

local getter = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local hostName = type(getter) == "function" and getter(addonName, "X-Beautiful-Host") or nil
local host = rawget(_G, type(hostName) == "string" and hostName or "BeautifulSkins")
if type(host) ~= "table" or type(host.RegisterPack) ~= "function" then
    error(addonName .. ": its host addon is missing")
end

setmetatable(ns, { __index = host })
ns.host = host
ns.packName = addonName
ns.db = false   -- the pack's SavedVariables, set when the pack loads (never the host's by accident)
ns.locales = {} -- the pack's own texts (Locales\*.lua); ns.L falls back to the host's words
