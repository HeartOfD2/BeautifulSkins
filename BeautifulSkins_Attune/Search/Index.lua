-- Search index: one entry per attunement, per searchable step (quest, NPC, item, other) and per zone of an attunement,
-- built once from Attune's data (through the adapter) and found again by a normalised name. Normalising lowercases,
-- folds accents and umlauts (ä=a, ö=o, ü=u, ß=ss), turns punctuation into spaces and joins spaces, so "dusterbruch"
-- finds "Düsterbruch" and "hakkar" finds "Atal'Hakkar". Every word of a query must match; a word counts as found at the
-- start of a word of the name (better) or anywhere inside it. A single number looks up quest, NPC and item ids first.
-- Only this file knows the ranking; SearchUI draws what Run returns.
local _, ns = ...
local A = ns.Attune

local Search = {}
ns.Search = Search

local find, sub, gsub = string.find, string.sub, string.gsub

-- ASCII only on purpose: the C library's tolower, ispunct and isspace depend on the locale and could touch the bytes
-- of UTF-8 characters.
local LOWER = {}
for i = 65, 90 do LOWER[string.char(i)] = string.char(i + 32) end
local PUNCT = "[\33-\47\58-\64\91-\96\123-\126]"
local SPACES = "[ \t\r\n]+"

local function Lower(text)
    return (gsub(text, "[A-Z]", LOWER))
end

local KIND_ORDER = { "attune", "quest", "npc", "item", "zone", "other" }
Search.KIND_ORDER = KIND_ORDER
Search.FILTERS = { "all", "attune", "quest", "npc", "item", "zone" }
local GROUP_LIMIT, EXPANDED_LIMIT = 25, 150
Search.GROUP_LIMIT, Search.EXPANDED_LIMIT = GROUP_LIMIT, EXPANDED_LIMIT

local stats = { builds = 0, buildMs = 0, entries = 0, queries = 0, lastMs = 0, maxMs = 0, lastHits = 0 }
Search.stats = stats

local function Clock()
    return type(debugprofilestop) == "function" and debugprofilestop() or nil
end

---------------------------------------------------------------------------
-- Normalising
---------------------------------------------------------------------------

-- Accented letters (UTF-8, both cases) and the plain letters they stand for.
local FOLD = {}
do
    local groups = {
        a = "àáâãäåāăąÀÁÂÃÄÅĀĂĄ", ae = "æÆ", c = "çćčÇĆČ", d = "ðďđÐĎĐ", e = "èéêëēęěÈÉÊËĒĘĚ", g = "ğĞ", -- lint:ignore (letter table for folding, not UI text)
        i = "ìíîïīıÌÍÎÏĪİ", l = "łĺľŁĹĽ", n = "ñńňÑŃŇ", o = "òóôõöøōőÒÓÔÕÖØŌŐ", oe = "œŒ", r = "řŕŘŔ", -- lint:ignore (letter table for folding, not UI text)
        s = "śşšŚŞŠ", ss = "ß", t = "ţťŢŤ", th = "þÞ", u = "ùúûüūůűųÙÚÛÜŪŮŰŲ", y = "ýÿÝŸ", z = "źżžŹŻŽ", -- lint:ignore (letter table for folding, not UI text)
    }
    for base, chars in pairs(groups) do
        for ch in chars:gmatch("[\194-\244][\128-\191]*") do FOLD[ch] = base end
    end
end

-- Lowercase, accents and Cyrillic capitals folded; length may change (ß -> ss).
local function Fold(text)
    text = Lower(text)
    text = gsub(text, "[\195-\197][\128-\191]", FOLD)
    text = gsub(text, "\208([\144-\159])", function(c) return "\208" .. string.char(c:byte() + 32) end)
    text = gsub(text, "\208([\160-\175])", function(c) return "\209" .. string.char(c:byte() - 32) end)
    return text
end

function Search.Normalize(text)
    if type(text) ~= "string" then return "" end
    text = gsub(Fold(text), PUNCT, " ")
    text = gsub(text, SPACES, " ")
    text = gsub(text, "^ ", "")
    text = gsub(text, " $", "")
    return text
end
local Normalize = Search.Normalize

-- Folded text with, for every byte of it, the byte range of the original character it came from.
local function FoldMapped(text)
    local parts, from, to, n = {}, {}, {}, 0
    local pos, len = 1, #text
    while pos <= len do
        local _, e = find(text, "^[\1-\127\194-\244][\128-\191]*", pos)
        e = e or pos
        local ch = sub(text, pos, e)
        local r
        if #ch == 1 then
            r = Lower(ch)
            if find(r, PUNCT) or find(r, SPACES) then r = " " end
        else
            r = Fold(ch)
        end
        parts[#parts + 1] = r
        for _ = 1, #r do
            n = n + 1
            from[n], to[n] = pos, e
        end
        pos = e + 1
    end
    return table.concat(parts), from, to
end

---------------------------------------------------------------------------
-- Query
---------------------------------------------------------------------------

-- A query is active from 2 characters, or from a number.
function Search.Parse(text)
    local norm = Normalize(text or "")
    local q = { text = text or "", norm = norm, tokens = {}, spaced = {} }
    for token in norm:gmatch("%S+") do
        q.tokens[#q.tokens + 1] = token
        q.spaced[#q.spaced + 1] = " " .. token
    end
    q.active = #norm >= 2 or (#norm >= 1 and find(norm, "^%d+$") ~= nil)
    q.number = #q.tokens == 1 and find(q.tokens[1], "^%d+$") ~= nil and q.tokens[1] or nil
    return q
end

---------------------------------------------------------------------------
-- Index
---------------------------------------------------------------------------

local index

local function NewEntry(kind, aid, a, name, extra)
    local norm = Normalize(extra and extra.hay or name)
    local entry = {
        kind = kind, aid = aid, aidNum = tonumber(aid) or 0, name = name, norm = norm, padded = " " .. norm,
        attune = a, level = A.AttuneLevel(a), sid = "", sidNum = 0,
    }
    if extra then
        for k, v in pairs(extra) do
            if k ~= "hay" then entry[k] = v end
        end
    end
    return entry
end

local function Build()
    local start = Clock()
    local idx = { key = A.IndexKey(), byKind = {}, byStep = {}, byId = {}, count = 0 }
    for _, kind in ipairs(KIND_ORDER) do idx.byKind[kind] = {} end
    local function Add(entry)
        local list = idx.byKind[entry.kind]
        list[#list + 1] = entry
        idx.count = idx.count + 1
    end
    for _, source in ipairs(A.SearchSource()) do
        local a = source.attune
        local aid = tostring(a.ID)
        local aname = A.AttuneName(a)
        if type(aname) == "string" and aname ~= "" then
            Add(NewEntry("attune", aid, a, aname, { hay = aname .. " " .. tostring(A.ShortName(a) or "") }))
        end
        local zones, zoneOrder = {}, {}
        for _, step in ipairs(source.steps) do
            local name = A.SearchName(step)
            local kind = A.SearchKind(step)
            if name and name ~= "" and kind then
                local sid = tostring(step.ID)
                local ids = A.SearchIds(step)
                local idSet = {}
                for _, id in ipairs(ids) do
                    idSet[id] = true
                    idx.byId[id] = true
                end
                local entry = NewEntry(kind, aid, a, name, { step = step, sid = sid, sidNum = tonumber(sid) or 0,
                    ids = ids, idSet = idSet })
                idx.byStep[aid .. "-" .. sid] = entry
                Add(entry)
            end
            local zone = kind ~= "other" and A.ZoneName(step) or nil
            if zone and zone ~= "" then
                local z = zones[zone]
                if not z then
                    z = { stepIds = {} }
                    zones[zone] = z
                    zoneOrder[#zoneOrder + 1] = zone
                end
                z.stepIds[#z.stepIds + 1] = tostring(step.ID)
                z.first = z.first or step
            end
        end
        for _, zone in ipairs(zoneOrder) do
            local z = zones[zone]
            Add(NewEntry("zone", aid, a, zone, { stepIds = z.stepIds, step = z.first, sid = tostring(z.first.ID),
                sidNum = tonumber(z.first.ID) or 0 }))
        end
    end
    local stop = Clock()
    stats.builds, stats.entries = stats.builds + 1, idx.count
    stats.buildMs = start and stop and (stop - start) or 0
    index = idx
    return idx
end

-- The index, built on first use and again when Attune's version, the language or the list's scope changed.
function Search.Get()
    if not index or index.count == 0 or index.key ~= A.IndexKey() then return Build() end
    return index
end

function Search.Built()
    return index ~= nil
end

---------------------------------------------------------------------------
-- Matching
---------------------------------------------------------------------------

-- nil = no match; 0 = the name starts with the first word; 1 = every word starts a word; 2 = some word only inside one.
local function Rank(entry, q)
    local hay, padded = entry.norm, entry.padded
    local rank = 1
    for i = 1, #q.tokens do
        if not find(padded, q.spaced[i], 1, true) then
            if not find(hay, q.tokens[i], 1, true) then return nil end
            rank = 2
        end
    end
    if rank == 1 and sub(hay, 1, #q.tokens[1]) == q.tokens[1] then rank = 0 end
    return rank
end

-- true when this kind passes the chosen chip.
local function KindAllowed(kind, filter)
    if filter == nil or filter == "all" then return true end
    return filter == kind
end

local function Before(x, y)
    if x.rank ~= y.rank then return x.rank < y.rank end
    local ex, ey = x.entry, y.entry
    if ex.level ~= ey.level then return ex.level < ey.level end
    if ex.norm ~= ey.norm then return ex.norm < ey.norm end
    if ex.aidNum ~= ey.aidNum then return ex.aidNum < ey.aidNum end
    return ex.sidNum < ey.sidNum
end

-- Status of an entry for this character: "done", "active" or "open". A zone is done when all its steps are.
function Search.Status(entry)
    if entry.kind == "attune" then return A.AttuneStatus(entry.aid) end
    if entry.kind == "zone" then
        for _, sid in ipairs(entry.stepIds) do
            if not A.IsStepDone(entry.aid, sid) then return "open" end
        end
        return "done"
    end
    return A.StepStatus(entry.aid, entry.step)
end

-- Runs a query. opts: filter (kind or "all"), onlyOpen, expanded = { [kind] = true } (those groups show more rows).
-- Returns { groups = { { kind, total, items = { { entry, rank, status } ... } } ... }, total } with the groups in
-- KIND_ORDER; a group without hits is left out.
function Search.Run(q, opts)
    opts = opts or {}
    local start = Clock()
    local result = { groups = {}, total = 0 }
    if not q or not q.active or #q.tokens == 0 then return result end
    local idx = Search.Get()
    local idMode = q.number ~= nil and idx.byId[q.number] == true
    for _, kind in ipairs(KIND_ORDER) do
        if KindAllowed(kind, opts.filter) then
            local hits = {}
            for _, entry in ipairs(idx.byKind[kind]) do
                local rank
                if idMode then
                    rank = entry.idSet and entry.idSet[q.number] and 0 or nil
                else
                    rank = Rank(entry, q)
                end
                if rank then
                    local status = (opts.onlyOpen or false) and Search.Status(entry) or nil
                    if not (opts.onlyOpen and status == "done") then
                        hits[#hits + 1] = { entry = entry, rank = rank, status = status }
                    end
                end
            end
            if #hits > 0 then
                table.sort(hits, Before)
                local limit = opts.expanded and opts.expanded[kind] and EXPANDED_LIMIT or GROUP_LIMIT
                local items = {}
                for i = 1, math.min(#hits, limit) do
                    local hit = hits[i]
                    hit.status = hit.status or Search.Status(hit.entry)
                    items[i] = hit
                end
                result.groups[#result.groups + 1] = { kind = kind, total = #hits, items = items }
                result.total = result.total + #hits
            end
        end
    end
    local stop = Clock()
    stats.queries = stats.queries + 1
    if start and stop then
        stats.lastMs = stop - start
        stats.maxMs = math.max(stats.maxMs, stats.lastMs)
    end
    stats.lastHits = result.total
    return result
end

-- true when a card of the open chain belongs to the query: its own name or id matches (kinds as the chip allows) or,
-- for the zone chip and "all", its zone. Used to mark cards and to dim the rest.
function Search.StepMatches(attuneId, step, q, filter)
    if not q or not q.active or type(step) ~= "table" then return false end
    local idx = Search.Get()
    local idMode = q.number ~= nil and idx.byId[q.number] == true
    local entry = idx.byStep[tostring(attuneId) .. "-" .. tostring(step.ID)]
    if entry and KindAllowed(entry.kind, filter) then
        if idMode then
            if entry.idSet[q.number] then return true end
        elseif Rank(entry, q) then
            return true
        end
    end
    if not idMode and KindAllowed("zone", filter) then
        local zone = A.ZoneName(step)
        if zone and A.SearchKind(step) ~= "other" then
            local norm = Normalize(zone)
            if Rank({ norm = norm, padded = " " .. norm }, q) then return true end
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Highlighting
---------------------------------------------------------------------------

local function Escape(text)
    return (gsub(text, "|", "||"))
end
Search.Escape = Escape

-- First place of a word in the folded text: start of a word if there is one, else anywhere. nil without a match.
local function FindWord(folded, token)
    local p = find(" " .. folded, " " .. token, 1, true)
    if p then return p end
    return find(folded, token, 1, true)
end

-- The name with the parts that match the query wrapped in colour: open is a "|cffrrggbb" code. Matches are found in the
-- folded text and mapped back onto the original characters.
function Search.Highlight(name, q, open)
    if type(name) ~= "string" then return "" end
    if not q or not q.active or #q.tokens == 0 then return Escape(name) end
    local folded, from, to
    if find(name, "[\128-\255]") then
        folded, from, to = FoldMapped(name)
    else
        folded = gsub(Lower(name), PUNCT, " ") -- same length as the name
    end
    local marked, any = {}, false
    for _, token in ipairs(q.tokens) do
        local s = FindWord(folded, token)
        if s then
            for i = s, s + #token - 1 do
                if from then
                    for b = from[i], to[i] do marked[b] = true end
                else
                    marked[i] = true
                end
            end
            any = true
        end
    end
    if not any then return Escape(name) end
    local out, run, runMarked = {}, {}, false
    local function Flush()
        if #run == 0 then return end
        local text = Escape(table.concat(run))
        out[#out + 1] = runMarked and (open .. text .. "|r") or text
        run = {}
    end
    for i = 1, #name do
        local on = marked[i] and true or false
        if on ~= runMarked then
            Flush()
            runMarked = on
        end
        run[#run + 1] = sub(name, i, i)
    end
    Flush()
    return table.concat(out)
end
