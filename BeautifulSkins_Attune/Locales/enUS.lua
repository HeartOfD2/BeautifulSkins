-- English is the source language: every key is its own English text. Locales\deDE.lua fills ns.locales.deDE; the
-- language is the host's choice (ns.host.PackLocale). A key the pack does not translate falls back to the host's word.
local _, ns = ...

ns.locales.enUS = {}
ns.activeLocale = ns.locales.enUS

ns.L = setmetatable({}, {
    __index = function(_, key)
        local text = ns.activeLocale[key]
        if text ~= nil then return text end
        local shared = ns.host.activeLocale and ns.host.activeLocale[key]
        if shared ~= nil then return shared end
        return key
    end,
})
