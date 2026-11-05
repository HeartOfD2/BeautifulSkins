-- Whisper Messenger: a button that opens and closes its window, with the number of unread whispers.
-- With EllesmereUI Chat it sits in the chat sidebar below the last icon, looks like EllesmereUI's own icons (size,
-- colour, faded until hovered) and moves with Shift-drag while EllesmereUI's "Free Move Icons" is on. Without it, a
-- small button sits in a corner of the first chat window (like the copy button of EUI Tweaks). Whisper Messenger's
-- own floating and minimap icons can be hidden. Unread whispers are counted from the whisper events while Whisper
-- Messenger's window is closed (reset when it opens); a number on Whisper Messenger's own badge counts as well.
-- EllesmereUI's sidebar is only read: our button is our own frame, anchored below EllesmereUI's last icon, and no
-- geometry of the chat frames is ever read (ChatFrame1 is an Edit Mode frame; resolving its layout would taint it).
local addonName, ns = ...
local L = ns.L
local C = ns.Colors

local ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\Whisper"
local GLOW = "Interface\\AddOns\\" .. addonName .. "\\Media\\Glow"
local BASE_SIZE = 22      -- EllesmereUI's sidebar icon size at scale 1
local ICON_ALPHA, ICON_HOVER_ALPHA = 0.4, 0.9
local CHAT_SIZE = 18
local CORNERS = { TOPLEFT = { 3, -3 }, TOPRIGHT = { -3, -3 }, BOTTOMLEFT = { 3, 3 }, BOTTOMRIGHT = { -3, 3 } }

local M = ns.Modules.Register("whisperButton", { addon = "WhisperMessenger", setting = "whisperButton",
    label = "Whisper Messenger: chat button" })
ns.WhisperButton = M

local button, icon, badge, badgeText, glow, pulse
local mode            -- "sidebar" | "chat"
local unread = 0
local eventCount, badgeCount = 0, 0 -- whispers since the window was last open / number on Whisper Messenger's badge
local hovering = false
local watched = setmetatable({}, { __mode = "k" })

local function Settings()
    return ns.db.whisper
end

local function Toggle()
    local fn = rawget(_G, "WhisperMessenger_Toggle")
    if type(fn) == "function" then
        fn()
        return
    end
    local slash = SlashCmdList and SlashCmdList.WHISPERMESSENGER
    if type(slash) == "function" then slash("") end
end

-- ------------------------------------------------------------------------------------------- look

local function SidebarColor()
    local cfg = ns.EUI.ChatSettings()
    if cfg and cfg.iconUseAccent then
        local r, g, b = ns.Env.Accent()
        if r then return r, g, b end
        return ns.Accent()
    end
    if cfg and type(cfg.iconR) == "number" then return cfg.iconR, cfg.iconG or 1, cfg.iconB or 1 end
    return 1, 1, 1
end

local function Paint()
    if not button then return end
    if mode == "sidebar" then
        local r, g, b = SidebarColor()
        icon:SetVertexColor(r, g, b, (hovering or unread > 0) and ICON_HOVER_ALPHA or ICON_ALPHA)
    else
        if hovering then
            local r, g, b = ns.Accent()
            icon:SetVertexColor(r, g, b, 1)
        else
            icon:SetVertexColor(1, 1, 1, 0.9)
        end
    end
    local r, g, b = ns.Accent()
    badge.bg:SetColorTexture(r, g, b, 1)
    badge:SetShown(unread > 0)
    local wantGlow = unread > 0 and Settings().glow ~= false
    glow:SetVertexColor(r, g, b, 1)
    glow:SetShown(wantGlow)
    if wantGlow and not pulse:IsPlaying() then
        pulse:Play()
    elseif not wantGlow and pulse:IsPlaying() then
        pulse:Stop()
    end
    badgeText:SetText(unread > 99 and "99+" or tostring(unread))
    local path = ns.Font()
    ns.SetFont(badgeText, path, 9, "")
end

-- Without EllesmereUI Chat and with "show on hover": visible while the mouse is over the chat or a whisper waits.
local watch = CreateFrame("Frame")
watch:Hide()
local acc = 0
watch:SetScript("OnUpdate", function(_, elapsed) -- lint:ignore (0.1 s, only while the corner button hides on its own)
    acc = acc + elapsed
    if acc < 0.1 then return end
    acc = 0
    if not (button and mode == "chat") then return end
    local cf = rawget(_G, "ChatFrame1")
    local over = button:IsMouseOver() or (cf and cf:IsMouseOver())
    button:SetAlpha((over or unread > 0) and 1 or 0)
end)

-- ------------------------------------------------------------------------------------------- button

local function Tooltip(self)
    GameTooltip:SetOwner(self, mode == "sidebar" and "ANCHOR_RIGHT" or "ANCHOR_TOP")
    GameTooltip:SetText("Whisper Messenger")
    if unread > 0 then
        GameTooltip:AddLine(L["Unread whispers: %d"]:format(unread), 1, 1, 1)
    end
    GameTooltip:AddLine(L["Click: open or close"], 0.75, 0.75, 0.75)
    local cfg = ns.EUI.ChatSettings()
    if mode == "sidebar" and cfg and cfg.freeMoveIcons then
        GameTooltip:AddLine(L["Shift-drag: move"], 0.75, 0.75, 0.75)
    end
    GameTooltip:Show()
end

local drag = { active = false }

local function Place() end -- set below

local function FreeMoveOn()
    local cfg = ns.EUI.ChatSettings()
    return mode == "sidebar" and cfg ~= nil and cfg.freeMoveIcons == true
end

local function DragUpdate(self)
    if not IsMouseButtonDown("LeftButton") then
        self:SetScript("OnUpdate", nil)
        drag.active = false
        return
    end
    local es = self:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    if not (ns.CanAccess(cx) and ns.CanAccess(cy) and type(cx) == "number" and es and es > 0) then return end
    local off = Settings().offset
    off.x = math.floor((drag.baseX + (cx / es - drag.x)) * 10 + 0.5) / 10
    off.y = math.floor((drag.baseY + (cy / es - drag.y)) * 10 + 0.5) / 10
    Place()
end

local function Build(parent)
    button = CreateFrame("Button", nil, parent)
    button:RegisterForClicks("LeftButtonUp")
    icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    -- soft accent glow behind the icon, pulsing while a whisper is unread
    glow = button:CreateTexture(nil, "BACKGROUND", nil, -1)
    glow:SetTexture(GLOW)
    glow:SetBlendMode("ADD")
    glow:SetPoint("TOPLEFT", button, "TOPLEFT", -10, 10)
    glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 10, -10)
    glow:Hide()
    pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.25)
    fade:SetToAlpha(0.95)
    fade:SetDuration(0.8)
    fade:SetSmoothing("IN_OUT")
    badge = CreateFrame("Frame", nil, button)
    badge:SetSize(14, 11)
    badge:SetPoint("TOPRIGHT", button, "TOPRIGHT", 5, 4)
    badge:SetFrameLevel(button:GetFrameLevel() + 3)
    badge.bg = badge:CreateTexture(nil, "BACKGROUND")
    badge.bg:SetAllPoints()
    badgeText = badge:CreateFontString(nil, "OVERLAY")
    ns.SetFont(badgeText, STANDARD_TEXT_FONT, 9, "")
    badgeText:SetPoint("CENTER", 0, 0)
    badgeText:SetTextColor(0.05, 0.05, 0.05)
    badge:Hide()

    button:SetScript("OnClick", function()
        if drag.moved then
            drag.moved = false
            return
        end
        Toggle()
        if M.AfterToggle then M.AfterToggle() end
    end)
    button:SetScript("OnEnter", function(self)
        hovering = true
        Paint()
        Tooltip(self)
    end)
    button:SetScript("OnLeave", function()
        hovering = false
        Paint()
        GameTooltip:Hide()
    end)
    button:SetScript("OnMouseDown", function(self, which)
        if which ~= "LeftButton" or not IsShiftKeyDown() or not FreeMoveOn() then return end
        local es = self:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        if not (ns.CanAccess(cx) and type(cx) == "number" and es and es > 0) then return end
        local off = Settings().offset
        drag.x, drag.y, drag.baseX, drag.baseY = cx / es, cy / es, off.x or 0, off.y or 0
        drag.active, drag.moved = true, true
        GameTooltip:Hide()
        self:SetScript("OnUpdate", DragUpdate) -- lint:ignore (only while the mouse button is held)
    end)
    button:SetScript("OnMouseUp", function(self)
        if drag.active then
            self:SetScript("OnUpdate", nil)
            drag.active = false
        end
    end)
end

-- ------------------------------------------------------------------------------------------- placing

local function LastShown(list)
    local last
    for _, entry in ipairs(list) do
        if entry.button:IsShown() then last = entry end
    end
    return last
end

local placeQueued = false
local function QueuePlace()
    if placeQueued then return end
    placeQueued = true
    C_Timer.After(0, function()
        placeQueued = false
        ns.Run("whisperButton", Place)
    end)
end

local function WatchShown(frame)
    if not frame or watched[frame] then return end
    watched[frame] = true
    frame:HookScript("OnShow", QueuePlace)
    frame:HookScript("OnHide", QueuePlace)
end

local function PlaceSidebar(list, sidebar)
    local cfg = ns.EUI.ChatSettings() or {}
    local size = BASE_SIZE * ns.Clamp(cfg.sidebarIconScale, 0.3, 3, 1)
    button:SetSize(size, size)
    icon:ClearAllPoints()
    icon:SetAllPoints(button)
    icon:SetDesaturated(true)
    local gap = ns.Clamp(cfg.sidebarIconSpacing, 0, 60, 10)
    local off = FreeMoveOn() and Settings().offset or { x = 0, y = 0 }
    local last = LastShown(list)
    button:ClearAllPoints()
    if last then
        local anchor = last.button
        if last.tail and last.tail.IsShown and last.tail:IsShown() and not last.button._sbTailInside then
            anchor = last.tail
        end
        button:SetPoint("TOP", anchor, "BOTTOM", off.x or 0, -gap + (off.y or 0))
        button:Show()
    elseif #list == 0 then
        button:SetPoint("TOP", sidebar, "TOP", off.x or 0, -gap + (off.y or 0))
        button:Show()
    else
        button:Hide() -- EllesmereUI hides its icons: the sidebar is hidden or faded out
    end
end

local function PlaceChat()
    local cf = rawget(_G, "ChatFrame1")
    if not cf then return end
    local s = Settings()
    local corner = CORNERS[s.corner] and s.corner or "TOPRIGHT"
    button:SetSize(CHAT_SIZE, CHAT_SIZE)
    ns.Skin.Flat(button, C.panel, 0.75, { 0, 0, 0, 0 })
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetDesaturated(true)
    button:ClearAllPoints()
    button:SetPoint(corner, cf, corner, CORNERS[corner][1], CORNERS[corner][2])
    button:SetFrameStrata("HIGH")
    button:Show()
    watch:SetShown(s.hover ~= false)
    if s.hover == false then button:SetAlpha(1) end
end

Place = function()
    if not button then return end
    if mode == "sidebar" then
        local list, sidebar = ns.EUI.SidebarOrder()
        if not list then return end
        for _, entry in ipairs(list) do
            WatchShown(entry.button)
            WatchShown(entry.tail)
        end
        WatchShown(sidebar)
        PlaceSidebar(list, sidebar)
    else
        PlaceChat()
    end
    Paint()
end

-- ------------------------------------------------------------------------------------------- unread count

local function ReadCount(text)
    if type(text) ~= "string" or ns.IsSecret(text) then return nil end
    if text == "" then return 0 end
    local n = tonumber(text:match("^(%d+)"))
    return n
end

-- The badge of Whisper Messenger's icon: a small child frame whose only text is a number (or empty).
local function BadgeLabel(owner)
    if not owner or not owner.GetChildren then return nil end
    for _, child in ipairs({ owner:GetChildren() }) do
        local w = child.GetWidth and child:GetWidth()
        if ns.CanAccess(w) and type(w) == "number" and w > 0 and w <= 32 then
            for _, region in ipairs({ child:GetRegions() }) do
                if region:GetObjectType() == "FontString" and ReadCount(region:GetText()) then return region end
            end
        end
    end
    return nil
end

local sourceHooked = setmetatable({}, { __mode = "k" })

local function Recount()
    unread = math.max(eventCount, badgeCount)
    Paint()
end

local function HookCount(label)
    if sourceHooked[label] then return end
    sourceHooked[label] = true
    hooksecurefunc(label, "SetText", ns.Guard("whisperButton", function(_, text)
        local n = ReadCount(text)
        if n then
            badgeCount = n
            Recount()
        end
    end))
    badgeCount = ReadCount(label:GetText()) or 0
end

local function WindowShown()
    local win = rawget(_G, "WhisperMessengerWindow")
    return type(win) == "table" and win.IsShown and win:IsShown() or false
end

-- Opening Whisper Messenger's window reads the whispers: our own count starts again.
local function MarkRead()
    if eventCount == 0 then return end
    eventCount = 0
    Recount()
end

local function WatchWindow()
    local win = rawget(_G, "WhisperMessengerWindow")
    if type(win) ~= "table" or watched[win] then return end
    watched[win] = true
    win:HookScript("OnShow", ns.Guard("whisperButton", MarkRead))
end

-- A whisper arrived (the event's text is never read: it may be a secret value in instances).
local lastWhisper = "-"

local function OnWhisper()
    lastWhisper = date and date("%H:%M:%S") or "?"
    if M.status ~= "active" or WindowShown() then return end
    eventCount = eventCount + 1
    Recount()
end
ns.RegisterEvent("CHAT_MSG_WHISPER", function() ns.Run("whisperButton", OnWhisper) end)
ns.RegisterEvent("CHAT_MSG_BN_WHISPER", function() ns.Run("whisperButton", OnWhisper) end)

-- Our click may have created and opened the window for the first time.
function M.AfterToggle()
    WatchWindow()
    if WindowShown() then MarkRead() end
end

-- Whisper Messenger's own icons: hidden (and kept hidden) while the option is on.
local function KeepHidden(frame)
    if not frame then return end
    if Settings().hideOwnIcons then
        ns.Skin.Hook(frame, "Show", function(self)
            if Settings().hideOwnIcons and M.status == "active" then self:Hide() end
        end)
        frame:Hide()
    end
end

local function FindSources()
    local toggleIcon = rawget(_G, "WhisperMessengerToggleIcon")
    local minimapIcon = rawget(_G, "WhisperMessengerMinimapIcon")
    local label = BadgeLabel(toggleIcon) or BadgeLabel(minimapIcon)
    if label then HookCount(label) end
    WatchWindow()
    KeepHidden(toggleIcon)
    KeepHidden(minimapIcon)
    return toggleIcon ~= nil or minimapIcon ~= nil
end

-- ------------------------------------------------------------------------------------------- wiring

local function Setup()
    local list, sidebar = ns.EUI.SidebarOrder()
    local wantMode = (list and sidebar) and "sidebar" or "chat"
    if button and wantMode == mode then
        Place()
        return true
    end
    if wantMode == "chat" and not rawget(_G, "ChatFrame1") then return false end
    if not button then
        Build(wantMode == "sidebar" and sidebar or rawget(_G, "ChatFrame1"))
    else
        button:SetParent(wantMode == "sidebar" and sidebar or rawget(_G, "ChatFrame1"))
    end
    mode = wantMode
    Place()
    return true
end

function M.Enable()
    local tries = 0
    local ticker
    local function Look()
        tries = tries + 1
        local sourcesFound = FindSources()
        -- EllesmereUI builds its sidebar a moment after login; until then (and without it) the chat corner is used
        local placed = Setup()
        if (sourcesFound and placed and mode == "sidebar") or tries >= 10 then
            if ticker then ticker:Cancel() end
            ticker = nil
        end
    end
    ticker = C_Timer.NewTicker(1, ns.Guard("whisperButton", Look), 10)
    Look()
end

function M.ResetPosition()
    local off = Settings().offset
    off.x, off.y = 0, 0
    if button then ns.Run("whisperButton", Place) end
end

ns.OnRefresh(function()
    if M.status == "active" and button then
        ns.Run("whisperButton", function()
            FindSources()
            Place()
        end)
    end
end)

-- /bskins whisper: what the button knows (for a test report).
function M.Debug()
    ns.Say(("whisper button: status %s, mode %s, shown %s, unread %d (events %d, badge %d), last whisper %s"):format(
        tostring(M.status), tostring(mode), tostring(button and button:IsShown() or false), unread, eventCount,
        badgeCount, lastWhisper))
    ns.Say(("window shown %s, glow %s, glow option %s, Whisper Messenger icon %s"):format(tostring(WindowShown()),
        tostring(glow and glow:IsShown() or false), tostring(Settings().glow ~= false),
        tostring(rawget(_G, "WhisperMessengerToggleIcon") ~= nil)))
end
