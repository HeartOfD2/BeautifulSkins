-- Base locale: the keys ARE the English text, so this file only creates the shared tables.
local _, ns = ...
ns.locales = ns.locales or {}
ns.locales.enUS = {}

-- L resolves against the active locale table (chosen in ADDON_LOADED) and falls back to the key.
ns.activeLocale = ns.locales.enUS
ns.L = setmetatable({}, {
    __index = function(_, key)
        local text = ns.activeLocale[key]
        if text ~= nil then return text end
        return key
    end,
})
