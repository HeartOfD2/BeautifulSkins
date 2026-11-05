-- Environment adapter: where accent colour, font, language and panel colour come from. This file holds the defaults for
-- "no other addon involved"; Adapters/EUI.lua replaces them while EllesmereUI is loaded. The rest of the addon only
-- asks ns.Env and never knows who answers.
local _, ns = ...

local Env = {}
ns.Env = Env

local listeners = {}

-- Is the optional integration host present? (Replaced by Adapters/EUI.lua.)
function Env.HasEUI()
    return false
end

-- Accent colour of the host as r, g, b (0..1), or nil when there is none.
function Env.Accent()
    return nil
end

-- Font file and outline flag of the host, or nil.
function Env.FontPath()
    return nil
end

-- Language of the host ("enUS", "deDE", ...), or nil.
function Env.Locale()
    return nil
end

-- Panel background of the host as r, g, b, or nil.
function Env.PanelColor()
    return nil
end

-- Called before the values above are read on purpose (a window opens): lets the host drop values it cached.
function Env.Poll()
end

-- fn() runs after the host changed accent, font or panel colour.
function Env.OnChange(fn)
    listeners[#listeners + 1] = fn
end

function Env.Changed()
    for i = 1, #listeners do
        local ok, err = pcall(listeners[i])
        if not ok then geterrorhandler()(err) end
    end
end

-- Kept as short helpers for the many callers (settings rows, fonts, themes).
function ns.HasEUI()
    return Env.HasEUI()
end

-- Core asks for this when the language setting is "auto".
function ns.PreferredLocale()
    return Env.Locale()
end
