-- Our options in the game's options window (Settings API), always registered: the place to go without EllesmereUI.
-- Rows come from Settings\Settings.lua; rows only EllesmereUI's widgets can draw (colour pickers) are left out. Every
-- call is guarded: the Settings API changed shape in recent clients.
local _, ns = ...
local L = ns.L

local category

local function VarType(kind)
    local T = Settings.VarType
    if not T then return nil end
    if kind == "toggle" then return T.Boolean end
    if kind == "slider" then return T.Number end
    return T.String
end

local function Proxy(row, variable, default)
    local get, set = row.get, row.set
    return Settings.RegisterProxySetting(category, variable, VarType(row.type), row.text, default, get, set)
end

local function AddRow(layout, row, index)
    local variable = ("BeautifulSkins_%d"):format(index)
    if row.type == "header" then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(row.text))
    elseif row.type == "toggle" then
        local setting = Proxy(row, variable, true)
        Settings.CreateCheckbox(category, setting, row.tip)
    elseif row.type == "slider" then
        local setting = Proxy(row, variable, row.min)
        local options = Settings.CreateSliderOptions(row.min, row.max, row.step)
        if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
            options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
                return row.step < 1 and ("%.2f"):format(value) or tostring(math.floor(value + 0.5))
            end)
        end
        Settings.CreateSlider(category, setting, options, row.tip)
    elseif row.type == "dropdown" then
        local labels, order = row.values()
        local setting = Proxy(row, variable, order[1])
        Settings.CreateDropdown(category, setting, function()
            local container = Settings.CreateControlTextContainer()
            for _, key in ipairs(order) do container:Add(key, labels[key]) end
            return container:GetData()
        end, row.tip)
    elseif row.type == "button" then
        layout:AddInitializer(CreateSettingsButtonInitializer(row.text, row.text, row.onClick, row.tip, true))
    end
end

local function Build()
    if not (Settings and type(Settings.RegisterVerticalLayoutCategory) == "function"
        and type(Settings.RegisterProxySetting) == "function") then
        return
    end
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory("BeautifulSkins")
    local index = 0
    for _, page in ipairs(ns.Settings.Pages()) do
        if page.key ~= "info" then
            for _, row in ipairs(page.rows()) do
                index = index + 1
                if row.only ~= "eui" then
                    local ok, err = pcall(AddRow, layout, row, index)
                    if not ok and ns.db and ns.db.debug then geterrorhandler()(err) end
                end
            end
        end
    end
    Settings.RegisterAddOnCategory(category)
end

ns.OnReady(function()
    local ok, err = pcall(Build)
    if not ok then
        category = nil
        geterrorhandler()(err)
    end
end)

function ns.OpenSettingsPanel()
    if not (category and Settings.OpenToCategory) then return false end
    local id = category.GetID and category:GetID() or category.ID
    local ok = pcall(Settings.OpenToCategory, id)
    if not ok then ns.Say(L["The options are in the game menu: Options > AddOns > BeautifulSkins."]) end
    return true
end
