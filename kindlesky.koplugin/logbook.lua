-- Logbook of captured aircraft: which types and which individual airframes the owner has
-- confirmed, and how many times. Pure Lua with no KOReader requires; main.lua loads and saves it.
local Logbook = {}

local MAX_TYPES, MAX_REGS = 500, 2000

local function clip(value, max)
    local s = tostring(value or ""):gsub("[%c]", " ")
    return s:sub(1, max)
end

local function count_of(value)
    local n = math.floor(tonumber(value) or 0)
    return n >= 1 and math.min(n, 999999) or 1
end

local function stamp(value, fallback)
    local n = tonumber(value)
    return n and n > 0 and n or fallback
end

function Logbook.new(now)
    return { version = 1, since = now or os.time(), types = {}, regs = {} }
end

-- Accepts whatever was read from disk and returns a well-formed book, dropping anything odd.
function Logbook.sanitize(data, now)
    now = now or os.time()
    local book = Logbook.new(now)
    if type(data) ~= "table" then return book end
    book.since = stamp(data.since, now)
    local nt, nr = 0, 0
    if type(data.types) == "table" then
        for code, t in pairs(data.types) do
            if type(code) == "string" and #code >= 1 and #code <= 8 and type(t) == "table" and nt < MAX_TYPES then
                book.types[code] = { name = clip(t.name, 40), count = count_of(t.count),
                    first = stamp(t.first, now), last = stamp(t.last, now) }
                nt = nt + 1
            end
        end
    end
    if type(data.regs) == "table" then
        for reg, r in pairs(data.regs) do
            if type(reg) == "string" and #reg >= 1 and #reg <= 12 and type(r) == "table" and nr < MAX_REGS then
                book.regs[reg] = { type = clip(r.type, 8), airline = clip(r.airline, 40), count = count_of(r.count),
                    first = stamp(r.first, now), last = stamp(r.last, now), last_day = clip(r.last_day, 8) }
                nr = nr + 1
            end
        end
    end
    return book
end

local function norm(value, max)
    local s = tostring(value or ""):upper():gsub("[^A-Z0-9%-]", "")
    return s ~= "" and s:sub(1, max) or nil
end

-- Reduce a plane (and what we know about it) to the keys the book uses.
-- plane: { model, registration, id, description }; info: optional { airline, type_name }.
function Logbook.entry(plane, info)
    local code = norm(plane.model, 8)
    local reg = norm(plane.registration, 12) or norm(plane.id, 12)
    if not reg then return nil end
    local name = (info and info.type_name) or ""
    if name == "" then name = tostring(plane.description or "") end
    if name == "" then name = tostring(plane.model or "") end
    return { type = code, type_name = clip(name, 40), reg = reg,
        airline = clip(info and info.airline or "", 40) }
end

-- What the book already knows about this plane. day is a string such as "20261104".
function Logbook.status(book, entry, day)
    if not entry then return { new_type = false, new_reg = false, today = false, type_count = 0, reg_count = 0 } end
    local t, r = entry.type and book.types[entry.type], book.regs[entry.reg]
    return {
        new_type = entry.type ~= nil and t == nil,
        new_reg = r == nil,
        today = r ~= nil and day ~= nil and r.last_day == day,
        type_count = t and t.count or 0,
        reg_count = r and r.count or 0,
    }
end

local function evict(map, limit)
    local n = 0
    for _ in pairs(map) do n = n + 1 end
    while n > limit do
        local oldest, when
        for key, v in pairs(map) do
            if not when or v.last < when then oldest, when = key, v.last end
        end
        map[oldest] = nil
        n = n - 1
    end
end

-- Record a confirmed capture. Returns the result, or nil and "today" when this airframe was
-- already captured on the same day (so a second tap cannot inflate the counts).
function Logbook.capture(book, entry, now, day)
    if not entry then return nil, "unidentified" end
    local before = Logbook.status(book, entry, day)
    if before.today then return nil, "today" end
    if entry.type then
        local t = book.types[entry.type]
        if not t then
            t = { name = entry.type_name, count = 0, first = now, last = now }
            book.types[entry.type] = t
        end
        t.count = t.count + 1
        t.last = now
        if entry.type_name ~= "" then t.name = entry.type_name end
    end
    local r = book.regs[entry.reg]
    if not r then
        r = { type = entry.type or "", airline = entry.airline, count = 0, first = now, last = now, last_day = "" }
        book.regs[entry.reg] = r
    end
    r.count = r.count + 1
    r.last = now
    r.last_day = day or ""
    if entry.airline ~= "" then r.airline = entry.airline end
    if entry.type then r.type = entry.type end
    evict(book.types, MAX_TYPES)
    evict(book.regs, MAX_REGS)
    return {
        new_type = before.new_type, new_reg = before.new_reg,
        type_count = entry.type and book.types[entry.type].count or 0, reg_count = r.count,
    }
end

function Logbook.totals(book)
    local types, regs, airlines, seen = 0, 0, 0, {}
    for _ in pairs(book.types) do types = types + 1 end
    for _, r in pairs(book.regs) do
        regs = regs + 1
        local a = r.airline:upper()
        if a ~= "" and not seen[a] then seen[a] = true; airlines = airlines + 1 end
    end
    return { types = types, planes = regs, airlines = airlines }
end

-- Types, most recently seen first. Returns the items for one page, the page used, and the page count.
function Logbook.list(book, page, per_page)
    local items = {}
    for code, t in pairs(book.types) do
        items[#items + 1] = { type = code, name = t.name, count = t.count, first = t.first, last = t.last }
    end
    table.sort(items, function(a, b)
        if a.last ~= b.last then return a.last > b.last end
        return a.type < b.type
    end)
    per_page = math.max(1, per_page or 6)
    local pages = math.max(1, math.ceil(#items / per_page))
    page = math.max(1, math.min(math.floor(tonumber(page) or 1), pages))
    local out = {}
    for i = (page - 1) * per_page + 1, math.min(#items, page * per_page) do out[#out + 1] = items[i] end
    return out, page, pages
end

return Logbook
