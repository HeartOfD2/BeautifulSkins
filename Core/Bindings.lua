-- Key binding "Open or close the GearQuest window" (BeautifulSkins_Extras/Bindings.xml): opens and closes GearQuest
-- Forever's window, the same as its slash command /gq (GearQuest has no key binding of its own).
-- The game reads a LoadOnDemand addon's Bindings.xml at login even while that addon stays unloaded (pack switched off,
-- the former addon still running, a load error), so the binding is listed and can be pressed without the pack. Its
-- names and the function it calls therefore live in the host, which always loads. Nothing of GearQuest is replaced:
-- we call its slash handler (SlashCmdList.GEARQUEST), which toggles the window.
local _, ns = ...
local L = ns.L

-- Key bindings need real globals.
BINDING_HEADER_BSKINS = "BeautifulSkins"
BINDING_NAME_BSKINS_GQ_TOGGLE = L["Open or close the GearQuest window"]
ns.OnReady(function() -- the locale is chosen in ADDON_LOADED
    BINDING_NAME_BSKINS_GQ_TOGGLE = L["Open or close the GearQuest window"]
end)

function BeautifulSkins_ToggleGearQuest()
    local handler = type(SlashCmdList) == "table" and SlashCmdList["GEARQUEST"]
    if type(handler) == "function" then
        handler("")
        return
    end
    -- GearQuest not loaded (or switched off): say so instead of a silent key
    ns.Say(L["GearQuest Forever is not loaded."])
end
