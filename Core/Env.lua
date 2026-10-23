-- Environment: where accent colour, font, language and panel colour come from. This file holds the answers for "no
-- EllesmereUI"; Core\EUI.lua replaces them while EllesmereUI is loaded. The skins only ask ns.Env and never know who
-- answers.
local _, ns = ...

local Env = {}
ns.Env = Env

local listeners = {}

function Env.HasEUI() return false end
function Env.Accent() return nil end
function Env.FontPath() return nil end
function Env.Locale() return nil end
function Env.PanelColor() return nil end

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

function ns.HasEUI()
    return Env.HasEUI()
end

function ns.PreferredLocale()
    return Env.Locale()
end

-- EllesmereUI specific reads the skins use (all nil without EllesmereUI); Core\EUI.lua fills them.
ns.EUI = {
    ChatData = function() return nil end,       -- EllesmereUI's per-chat-frame data (sidebar and its buttons)
    ChatSettings = function() return nil end,   -- chat settings of the active EllesmereUI profile
    TrackerSettings = function() return nil end, -- quest tracker settings of the active profile
    TrackerFont = function() return nil end,    -- path, flags, shadow of the quest tracker font
    PrimeShadow = function() end,               -- lets a FontString carry EllesmereUI's text shadow
    SidebarOrder = function() return nil end,   -- sidebar icon buttons of ChatFrame1 in chain order
}
