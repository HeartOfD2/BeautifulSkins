-- Optional EllesmereUI integration: a sidebar section "Beautiful Skins" in EllesmereUI's options window with the pages of
-- Settings\Settings.lua, drawn with EllesmereUI.Widgets (searchable there). Runs only with EllesmereUI loaded and the
-- option on; RegisterPlugin works only at load, so switching the option takes effect after /reload.
local _, ns = ...
local L = ns.L
local Settings = ns.Settings

local PLUGIN_ID = "BeautifulSkins"
local MODULE_KEY = "BeautifulSkins"

ns.hosts = ns.hosts or {}

local function E()
    local e = rawget(_G, "EllesmereUI")
    return type(e) == "table" and e or nil
end

local function IsPrebuild()
    local e = E()
    return e and type(e.IsSearchPrebuild) == "function" and e.IsSearchPrebuild() or false
end

local function Pad()
    local e = E()
    return e and e.CONTENT_PAD or 45
end

local function RefreshPage()
    local e = E()
    if e and type(e.RefreshPage) == "function" then pcall(e.RefreshPage, e) end
end

local liveTexts = {} -- { fs, get } re-read when EllesmereUI restores a cached page
local gated = {}     -- { frame, enabled } rows that only work in one mode (an own colour)

-- Dims and locks rows whose enabled() is false (EllesmereUI's colour picker has no disabled state of its own).
local function UpdateGated()
    for _, g in ipairs(gated) do
        local on = g.enabled() and true or false
        g.frame:SetAlpha(on and 1 or 0.3)
        for _, child in ipairs({ g.frame:GetChildren() }) do
            if child.EnableMouse then child:EnableMouse(on) end
        end
    end
end

local function TextRow(parent, y, row)
    local str = row.get and row.get() or row.text or ""
    local h = 20 + 16 * select(2, str:gsub("\n", "\n"))
    if IsPrebuild() then return h end
    local text = parent:CreateFontString(nil, "OVERLAY")
    local path = ns.Font()
    ns.SetFont(text, path, 13, "")
    text:SetTextColor(0.75, 0.75, 0.75)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    text:SetPoint("TOPLEFT", parent, "TOPLEFT", Pad() + 20, y - 6)
    text:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(Pad() + 20), y - 6)
    if text.SetSpacing then text:SetSpacing(4) end
    text:SetText(str)
    if row.get then liveTexts[#liveTexts + 1] = { fs = text, get = row.get } end
    return math.max(h, math.floor((text:GetStringHeight() or 0) + 14))
end

local function Render(parent, yOffset, rows)
    local W = E() and E().Widgets
    if type(W) ~= "table" then return 1 end
    local y = yOffset
    for _, row in ipairs(rows) do
        local set = row.set and function(...)
            if row.enabled and not row.enabled() then return end
            row.set(...)
            RefreshPage()
            UpdateGated()
        end
        local _, h
        if row.type == "header" then
            _, h = W:SectionHeader(parent, row.text, y, row.tip)
        elseif row.type == "toggle" then
            _, h = W:Toggle(parent, row.text, y, function() return row.get() and true or false end, set, row.tip)
        elseif row.type == "slider" then
            _, h = W:Slider(parent, row.text, y, row.min, row.max, row.step, row.get, set, row.tip)
        elseif row.type == "dropdown" then
            local values, order = row.values()
            _, h = W:Dropdown(parent, row.text, y, values, row.get, set, order, row.tip)
        elseif row.type == "button" then
            _, h = W:Button(parent, row.text, y, row.onClick)
        elseif row.type == "color" then
            local frame
            frame, h = W:ColorPicker(parent, row.text, y, row.get, set, false)
            if row.enabled and type(frame) == "table" and frame.SetAlpha then
                gated[#gated + 1] = { frame = frame, enabled = row.enabled }
            end
        elseif row.type == "text" then
            h = TextRow(parent, y, row)
        end
        y = y - (h or 0)
    end
    UpdateGated()
    return math.abs(y)
end

local byName = {}

local function Open()
    local e = E()
    if not (e and type(e.OpenPlugin) == "function") then return false end
    local first = Settings.Pages()[1]
    local ok, opened = pcall(e.OpenPlugin, PLUGIN_ID, MODULE_KEY, first.label)
    return ok and opened and true or false
end

local function Register()
    local e = E()
    if not e then
        ns.registerResult = "no EllesmereUI"
        return
    end
    if not ns.db.integrateEUI then
        ns.registerResult = "integration off"
        return
    end
    if type(e.RegisterPlugin) ~= "function" then
        ns.registerResult = "no RegisterPlugin"
        return
    end
    local names = {}
    for i, page in ipairs(Settings.Pages()) do
        names[i] = page.label
        byName[page.label] = page
    end
    local module = {
        key = MODULE_KEY,
        title = L["Settings"],
        description = L["Skins for GearQuest, SkillUp, Whisper Messenger and Waypoint UI."],
        pages = names,
        buildPage = function(pageName, parent, y)
            local page = byName[pageName]
            if page then return Render(parent, y, page.rows()) end
            return 1
        end,
        onPageCacheRestore = function()
            for _, live in ipairs(liveTexts) do live.fs:SetText(live.get()) end
            UpdateGated()
        end,
    }
    -- The section label must not start with "EUI"/"Ellesmere" (EllesmereUI rejects such a registration).
    local ok, result = pcall(e.RegisterPlugin, PLUGIN_ID, { label = L["Beautiful Skins"], modules = { module } })
    ns.registerResult = ok and result or ("error: " .. tostring(result))
    if ok and result ~= false then ns.hosts.eui = { Open = Open } end
end

ns.OnReady(Register)
