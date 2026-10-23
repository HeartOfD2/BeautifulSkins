-- English is the source language: every key is its own English text. Locales\deDE.lua fills ns.locales.deDE; Core picks
-- the table at load (setting "language": automatic = EllesmereUI's language, else the client's).
local _, ns = ...

ns.locales = ns.locales or {}

ns.L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})
