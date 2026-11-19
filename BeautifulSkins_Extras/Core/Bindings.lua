-- Key binding (Bindings.xml): opens and closes GearQuest Forever's window, the same as its slash command /gq
-- (GearQuest has no key binding of its own). The binding shows in the game's key bindings under BeautifulSkins.
-- Nothing of GearQuest is replaced: we call its slash handler (SlashCmdList.GEARQUEST), which toggles the window.
local _, ns = ...
local L = ns.L

-- Key bindings need real globals.
BINDING_HEADER_BSKINS = "BeautifulSkins"
BINDING_NAME_BSKINS_GQ_TOGGLE = L["Open or close the GearQuest window"]

function BeautifulSkins_ToggleGearQuest()
    local handler = type(SlashCmdList) == "table" and SlashCmdList["GEARQUEST"]
    if type(handler) == "function" then
        handler("")
        return
    end
    -- GearQuest not loaded (or switched off): say so instead of a silent key
    ns.Say(L["GearQuest Forever is not loaded."])
end
