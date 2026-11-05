-- Theme editor: own themes made from any theme, every color picked freely, a live contrast check (WCAG 4.5:1 for text)
-- and sharing as one line of text (export / import). The editor is one Kit frame, so both option windows (our own and
-- the section in EllesmereUI's) show it as a custom row: Kit.ThemeEditor(parent) -> frame with :Update().
-- The theme being edited is the theme in use, so every change shows at once in every window.
local _, ns = ...
local L = ns.L
local Theme, Kit = ns.Theme, ns.Kit
local Bind = Theme.Bind

local EDITOR_H = 600
Kit.THEME_EDITOR_H = EDITOR_H
local LINE_H, CELL_H, CONTROL_W = 30, 28, 220

local function TokenLabels()
    return {
        bg = L["Window"], bgAlt = L["Header area"], control = L["Buttons"], inputBg = L["Input fields"],
        border = L["Borders"], text = L["Text"], textDim = L["Secondary text"], header = L["Headings"],
        accent = L["Accent"], onAccent = L["Text on the accent"], danger = L["Warning"],
    }
end

local function Label(parent, text, size, color)
    local fs = Kit.Text(parent, size or 12, color or "text")
    fs:SetText(text or "")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function Hex(c)
    return string.format("%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5))
end

function Kit.ThemeEditor(parent)
    local ed = CreateFrame("Frame", nil, parent)
    ed:SetAllPoints(parent)
    ed:SetHeight(EDITOR_H)

    local function Key()
        local current = Theme.Current()
        if Theme.IsOwn(current) then return current end
        if ed.key and Theme.IsOwn(ed.key) then return ed.key end
        local first = Theme.OwnList()[1]
        return first and first.key or nil
    end

    local function Use(key)
        ed.key = key
        if key then Theme.Set(key) end
        ed:Update()
    end

    -- Own themes: pick, new, delete
    local pickLabel = Label(ed, L["Own theme"])
    pickLabel:SetPoint("TOPLEFT", 4, -8)
    ed.pick = Kit.Dropdown(ed, CONTROL_W, function()
        local values, order = {}, {}
        for i, entry in ipairs(Theme.OwnList()) do
            values[entry.key] = entry.label
            order[i] = entry.key
        end
        return values, order
    end, function() return Key() end, Use)
    ed.pick:SetPoint("TOPRIGHT", -4, -4)

    ed.new = Kit.Button(ed, 200, L["New from the current theme"], function()
        Use(Theme.NewOwn(Theme.Current()))
    end, 24, "primary")
    ed.new:SetPoint("TOPLEFT", 4, -38)
    Kit.Tooltip(ed.new, { L["New from the current theme"], L["Copies the colors of the theme in use into a new own theme and switches to it."] })
    ed.delete = Kit.ConfirmButton(ed, 110, L["Delete"], function()
        local key = Key()
        if key then Theme.DeleteOwn(key) end
        ed.key = nil
        ed:Update()
    end, 24)
    ed.delete:SetPoint("LEFT", ed.new, "RIGHT", 8, 0)

    ed.empty = Label(ed, L["No own theme yet. \"New from the current theme\" copies the theme in use; then change any color."], 12, "textDim")
    ed.empty:SetPoint("TOPLEFT", 4, -76)
    ed.empty:SetPoint("TOPRIGHT", -4, -76)
    ed.empty:SetWordWrap(true)

    -- Everything below edits the chosen theme.
    local body = CreateFrame("Frame", nil, ed)
    body:SetPoint("TOPLEFT", 0, -72)
    body:SetPoint("BOTTOMRIGHT")
    ed.body = body
    local y = 0

    local nameLabel = Label(body, L["Name"])
    nameLabel:SetPoint("TOPLEFT", 4, -(y + 8))
    ed.name = Kit.EditBox(body, CONTROL_W, 22, { maxLetters = 40, onEnter = function(text)
        local key = Key()
        if key then Theme.RenameOwn(key, text) end
        ed:Update()
    end })
    ed.name:SetPoint("TOPRIGHT", -4, -(y + 4))
    ed.name.edit:HookScript("OnEditFocusLost", function(self)
        local key = Key()
        if key then Theme.RenameOwn(key, self:GetText()) end
        ed:Update()
    end)
    y = y + LINE_H

    local modeLabel = Label(body, L["Kind"])
    modeLabel:SetPoint("TOPLEFT", 4, -(y + 8))
    ed.mode = Kit.Dropdown(body, CONTROL_W, function()
        return { dark = L["Dark"], light = L["Light"] }, { "dark", "light" }
    end, function()
        local def = Theme.OwnDef(Key())
        return def and def.mode == "light" and "light" or "dark"
    end, function(mode)
        local key = Key()
        if key then Theme.SetOwnMode(key, mode) end
        ed:Update()
    end)
    ed.mode:SetPoint("TOPRIGHT", -4, -(y + 4))
    Kit.Tooltip(modeLabel, { L["Kind"], L["Dark or light: decides how hover and tracks are shaded."] })
    modeLabel:SetHeight(22)
    y = y + LINE_H + 6

    -- Colors in two columns
    local colorsHead = Label(body, L["COLORS"], 11, "accent")
    colorsHead:SetPoint("TOPLEFT", 4, -y)
    y = y + 20
    ed.cells = {}
    local labels = TokenLabels()
    local cols = 2
    for i, token in ipairs(Theme.OWN_TOKENS) do
        local cell = CreateFrame("Frame", nil, body)
        cell:SetHeight(CELL_H)
        cell.row, cell.col = math.floor((i - 1) / cols), (i - 1) % cols
        cell.top = y
        cell.swatch = Kit.ColorButton(cell, function() return Theme.OwnColor(Key(), token) end, function(r, g, b)
            local key = Key()
            if key then Theme.SetOwnColor(key, token, r, g, b) end
        end, 20)
        cell.swatch:SetPoint("LEFT", 0, 0)
        cell.label = Label(cell, labels[token])
        cell.label:SetPoint("LEFT", cell.swatch, "RIGHT", 8, 0)
        cell.label:SetPoint("RIGHT", -4, 0)
        cell.hex = Label(cell, "", 10, "textDim")
        cell.hex:SetPoint("RIGHT", -6, 0)
        cell.hex:SetJustifyH("RIGHT")
        if token == "accent" then
            Kit.Tooltip(cell.swatch, { labels[token], L["Used while the accent color is set to \"Theme default\"."] })
        end
        cell.token = token
        ed.cells[i] = cell
    end
    y = y + math.ceil(#Theme.OWN_TOKENS / cols) * CELL_H + 10

    -- Contrast
    local contrastHead = Label(body, L["CONTRAST"], 11, "accent")
    contrastHead:SetPoint("TOPLEFT", 4, -y)
    local contrastHint = Label(body, L["Text should reach 4.5 : 1 to stay easy to read."], 10, "textDim")
    contrastHint:SetPoint("LEFT", contrastHead, "RIGHT", 10, 0)
    y = y + 20
    ed.lines = {}
    for i = 1, 7 do
        local left = Label(body, "", 12, "text")
        left:SetPoint("TOPLEFT", 4, -(y + (i - 1) * 18))
        local right = Label(body, "", 12, "text")
        right:SetPoint("TOPRIGHT", -4, -(y + (i - 1) * 18))
        right:SetJustifyH("RIGHT")
        ed.lines[i] = { left = left, right = right }
    end
    y = y + 7 * 18 + 12

    -- Share
    local shareHead = Label(body, L["SHARE"], 11, "accent")
    shareHead:SetPoint("TOPLEFT", 4, -y)
    y = y + 20
    ed.code = Kit.EditBox(body, 200, 22, { placeholder = L["Paste a theme code here"] })
    ed.code:SetPoint("TOPLEFT", 4, -y)
    ed.code:SetPoint("TOPRIGHT", -232, -y)
    ed.code.edit:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    ed.import = Kit.Button(body, 108, L["Import"], function()
        local key, reason = Theme.ImportOwn(ed.code:GetText())
        if key then
            ed.code:SetText("")
            ed.status, ed.statusBad = L["Imported as a new own theme."], false
            Use(key)
        else
            ed.status = reason == "code" and L["That is no theme code (it starts with BT1:)."]
                or L["The code is damaged or incomplete."]
            ed.statusBad = true
            ed:Update()
        end
    end, 22)
    ed.import:SetPoint("TOPRIGHT", -4, -y)
    ed.export = Kit.Button(body, 108, L["Export"], function()
        local code = Theme.ExportOwn(Key())
        if not code then return end
        ed.code:SetText(code)
        ed.code:SetFocus()
        ed.code.edit:HighlightText()
        ed.statusBad = false
        ed.status = L["Code ready: Ctrl+C copies it. Import pastes it on another account or for a friend."]
        ed:Update()
    end, 22)
    ed.export:SetPoint("RIGHT", ed.import, "LEFT", -8, 0)
    y = y + 28
    ed.statusText = Label(body, "", 11, "textDim")
    ed.statusText:SetPoint("TOPLEFT", 4, -y)
    ed.statusText:SetPoint("TOPRIGHT", -4, -y)
    ed.statusText:SetWordWrap(true)

    -- Columns follow the width.
    local function Place()
        local w = math.max(300, ed:GetWidth() or 0)
        local cellW = math.floor((w - 8) / cols)
        for _, cell in ipairs(ed.cells) do
            cell:ClearAllPoints()
            cell:SetWidth(cellW - 8)
            cell:SetPoint("TOPLEFT", body, "TOPLEFT", 4 + cell.col * cellW, -(cell.top + cell.row * CELL_H))
        end
    end
    ed:SetScript("OnSizeChanged", Place)

    function ed:Update()
        Place()
        local key = Key()
        local has = key ~= nil
        self.body:SetShown(has)
        self.empty:SetShown(not has)
        self.delete:SetEnabled(has)
        self.pick:SetEnabled(has)
        self.pick:Update()
        if not has then return end
        local def = Theme.OwnDef(key)
        if not self.name.edit:HasFocus() then self.name:SetText(def and def.name or "") end
        self.mode:Update()
        for _, cell in ipairs(self.cells) do
            cell.swatch:Update()
            cell.hex:SetText("#" .. Hex({ Theme.OwnColor(key, cell.token) }))
        end
        local T = Theme.Get()
        local good, bad = Hex(T.success), Hex(T.danger)
        for i, entry in ipairs(Theme.OwnContrast(key)) do
            local line = self.lines[i]
            if line then
                line.left:SetText(entry.label)
                line.right:SetText(string.format("|cff%s%.1f : 1  %s|r", entry.ok and good or bad, entry.ratio,
                    entry.ok and L["good"] or L["too low"]))
            end
        end
        self.statusText:SetText(self.status or "")
        Kit.SetTextColor(self.statusText, self.statusBad and "danger" or "textDim")
    end

    -- a theme or accent change elsewhere (or our own edit) shows the new values
    Bind(ed, function(self) if self.Update then self:Update() end end)
    ed:Update()
    return ed
end

-- Row description for a settings page (custom row; both renderers draw it).
function Kit.ThemeEditorRow()
    return { type = "custom", height = EDITOR_H, build = function(parent) return Kit.ThemeEditor(parent) end }
end
