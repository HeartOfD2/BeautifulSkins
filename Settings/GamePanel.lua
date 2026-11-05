-- A short entry in the game's options (Options > AddOns): where players look first. It explains where the options
-- live and opens them with one click. Every call is guarded: the Settings API changed shape in recent clients.
local _, ns = ...
local L = ns.L

local category

local function Build()
    local api = rawget(_G, "Settings")
    if not (type(api) == "table" and type(api.RegisterCanvasLayoutCategory) == "function") then return end
    local panel = CreateFrame("Frame")
    panel:Hide()
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(ns.PACKAGE.title)
    local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    text:SetPoint("RIGHT", -16, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    text:SetText(L["All options are in our own window (or in the EllesmereUI options when the integration is on). Command: %s"]
        :format(ns.PACKAGE.slash[1]))
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(200, 26)
    button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)
    button:SetText(L["Open the options"])
    button:SetScript("OnClick", function()
        if type(HideUIPanel) == "function" and SettingsPanel then pcall(HideUIPanel, SettingsPanel) end
        ns.OpenOptions()
    end)
    category = api.RegisterCanvasLayoutCategory(panel, ns.PACKAGE.title)
    if type(api.RegisterAddOnCategory) == "function" then api.RegisterAddOnCategory(category) end
end

ns.OnReady(function()
    if ns.dormant then return end
    local ok, err = pcall(Build)
    if not ok and ns.db and ns.db.debug then geterrorhandler()(err) end
end)
