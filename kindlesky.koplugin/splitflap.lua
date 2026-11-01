-- Split-flap style departure board: a fixed grid of tiles where only the cells whose text
-- changed visibly flip, in a short cascade. Everything here is pure Lua with no KOReader
-- requires, so it can be unit tested outside the device. The painter draws through a small
-- context table (rect and glyph functions) that main.lua provides.
local Splitflap = {}

Splitflap.STRIP = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-&'/+"

local strip_index = {}
for i = 1, #Splitflap.STRIP do strip_index[Splitflap.STRIP:sub(i, i)] = i end

-- Upper-case ASCII only. Anything the strip does not hold (accents, symbols) becomes a space.
function Splitflap.clean(value)
    local s = tostring(value or ""):upper()
    s = s:gsub("[\128-\255]+", " "):gsub("[^A-Z0-9%.%-&'/+ ]", " ")
    return s
end

-- fields: list of { key = "dest", cells = 13, label = "TO" }
function Splitflap.spec(fields, nrows, gap)
    local spec = { fields = fields, nrows = nrows, gap = gap or 16, cols = 0, field_of = {}, first = {} }
    for fi, f in ipairs(fields) do
        spec.first[fi] = spec.cols + 1
        for _ = 1, f.cells do
            spec.cols = spec.cols + 1
            spec.field_of[spec.cols] = fi
        end
    end
    return spec
end

-- rows: list (at most spec.nrows) of { text = { key = "string" }, outline = bool } or false for an empty slot.
function Splitflap.build(spec, rows)
    local board = { spec = spec, rows = {} }
    for r = 1, spec.nrows do
        local item, cells = rows[r], {}
        local used = type(item) == "table"
        local c = 0
        for _, f in ipairs(spec.fields) do
            local s = used and Splitflap.clean(item.text and item.text[f.key]) or ""
            for i = 1, f.cells do
                c = c + 1
                cells[c] = s:sub(i, i) ~= "" and s:sub(i, i) or " "
            end
        end
        board.rows[r] = { cells = cells, used = used, outline = used and item.outline == true or false }
    end
    return board
end

-- Cells that differ between two boards of the same shape. Returns nil when no comparison is
-- possible (no previous board, or a different layout), which callers treat as "do not animate".
function Splitflap.diff(old, new)
    if not old or not new or old.spec ~= new.spec then return nil end
    local out = {}
    for r = 1, new.spec.nrows do
        local a, b = old.rows[r].cells, new.rows[r].cells
        for c = 1, new.spec.cols do
            if a[c] ~= b[c] then out[#out + 1] = { row = r, col = c, from = a[c], to = b[c] } end
        end
    end
    return out
end

-- Walk the strip forward from one glyph to another. At most max_steps glyphs are shown and the
-- last one is always the target. Deterministic, so frames can be tested.
function Splitflap.sequence(from, to, max_steps)
    max_steps = math.max(1, math.floor(max_steps or 3))
    local a, b = strip_index[from] or 1, strip_index[to] or 1
    local n, seq, i, guard = #Splitflap.STRIP, {}, a, 0
    while i ~= b and guard < n do
        i = i % n + 1
        guard = guard + 1
        seq[#seq + 1] = Splitflap.STRIP:sub(i, i)
    end
    if #seq == 0 then seq[1] = to end
    while #seq > max_steps do table.remove(seq, 1) end
    seq[#seq] = to
    return seq
end

-- opts: max_steps (glyphs per cell), max_rows (rows that animate; the rest snap), max_frames.
function Splitflap.plan(changes, opts)
    opts = opts or {}
    local max_steps, max_rows, max_frames = opts.max_steps or 3, opts.max_rows or 4, opts.max_frames or 14
    local order, rank = {}, {}
    for _, ch in ipairs(changes) do
        if not rank[ch.row] then order[#order + 1] = ch.row; rank[ch.row] = 0 end
    end
    table.sort(order)
    for i, r in ipairs(order) do rank[r] = i end
    local anim = { cells = {}, by_pos = {}, rows = {}, nrows = #order, frames = 0 }
    for _, ch in ipairs(changes) do
        local cell
        if rank[ch.row] > max_rows then
            cell = { row = ch.row, col = ch.col, from = ch.from, seq = { ch.to }, start = 0 }
        else
            local seq = Splitflap.sequence(ch.from, ch.to, max_steps)
            local start = (rank[ch.row] - 1) * 2 + math.floor((ch.col - 1) / 6)
            start = math.max(0, math.min(start, max_frames - #seq))
            cell = { row = ch.row, col = ch.col, from = ch.from, seq = seq, start = start }
        end
        anim.cells[#anim.cells + 1] = cell
        anim.by_pos[cell.row * 1000 + cell.col] = cell
        anim.rows[cell.row] = true
        anim.frames = math.max(anim.frames, cell.start + #cell.seq)
    end
    return anim
end

-- State of one cell at frame k: glyph to show, previous glyph (bottom half while flipping), flipping flag.
function Splitflap.cellAt(anim, board, r, c, k)
    local final = board.rows[r].cells[c]
    local cell = anim and anim.by_pos[r * 1000 + c]
    if not cell then return final, final, false end
    local i = k - cell.start
    if i < 0 then return cell.from, cell.from, false end
    if i >= #cell.seq - 1 then return cell.seq[#cell.seq], cell.seq[#cell.seq], false end
    return cell.seq[i + 1], i == 0 and cell.from or cell.seq[i], true
end

-- Keep trains in the slot they already hold so a re-sort does not make every row flip.
-- previous: list of keys by slot ({} entries allowed). items: current items, nearest first.
function Splitflap.assign(previous, items, key_of, nslots)
    local keyed, taken = {}, {}
    local seen = {}
    for i, item in ipairs(items) do
        local k = key_of(item)
        seen[k] = (seen[k] or 0) + 1
        if seen[k] > 1 then k = k .. "#" .. seen[k] end
        keyed[k] = { item = item, index = i }
    end
    local slots, keys = {}, {}
    for s = 1, nslots do
        local k = previous and previous[s]
        if k and keyed[k] and not taken[k] then
            slots[s], keys[s], taken[k] = keyed[k].item, k, true
        end
    end
    local pending = {}
    for k, v in pairs(keyed) do if not taken[k] then pending[#pending + 1] = { key = k, index = v.index, item = v.item } end end
    table.sort(pending, function(a, b) return a.index < b.index end)
    local p = 1
    for s = 1, nslots do
        if not slots[s] and pending[p] then
            slots[s], keys[s] = pending[p].item, pending[p].key
            p = p + 1
        end
    end
    return slots, keys
end

-- ---------- Rail adapters ----------
local specs = {}

local function septa_text(train, badge)
    local delay = train.delay
    local status = "UNKNOWN"
    if delay then status = delay > 0 and ("LATE " .. math.min(99, math.floor(delay + 0.5))) or "ON TIME" end
    return { no = train.number, line = badge, dest = train.destination, status = status },
        delay == nil or delay > 0
end

function Splitflap.specFor(provider, wide)
    local key = provider .. (wide and "-w" or "-p")
    if specs[key] then return specs[key] end
    local spec
    if provider == "septa" then
        spec = Splitflap.spec({
            { key = "no", cells = 4, label = "TRAIN" }, { key = "line", cells = 3, label = "LINE" },
            { key = "dest", cells = wide and 13 or 11, label = "TO" }, { key = "status", cells = 7, label = "STATUS" },
        }, wide and 7 or 9, wide and 16 or 10)
    else
        spec = Splitflap.spec({
            { key = "line", cells = 3, label = "LINE" }, { key = "dest", cells = wide and 15 or 10, label = "TO" },
            { key = "plat", cells = 4, label = "PLAT" }, { key = "min", cells = 6, label = "DUE" },
        }, wide and 7 or 9, wide and 16 or 10)
    end
    specs[key] = spec
    return spec
end

function Splitflap.trainKey(provider, train)
    if provider == "septa" then return tostring(train.number) end
    return tostring(train.line) .. "|" .. tostring(train.destination)
end

local function tfl_dest(name)
    name = tostring(name or "")
    name = name:gsub(" Underground Station$", ""):gsub(" Rail Station$", ""):gsub(" DLR Station$", "")
    return name
end

-- Returns the board and the slot keys to remember for the next update.
function Splitflap.boardFor(provider, wide, trains, previous_keys, badge_of)
    local spec = Splitflap.specFor(provider, wide)
    local key_of = function(t) return Splitflap.trainKey(provider, t) end
    local slots, keys = Splitflap.assign(previous_keys, trains or {}, key_of, spec.nrows)
    local rows = {}
    for s = 1, spec.nrows do
        local t = slots[s]
        if t then
            if provider == "septa" then
                local text, outline = septa_text(t, badge_of(t.line))
                rows[s] = { text = text, outline = outline }
            else
                local m = tonumber(t.minutes) or 0
                local due = m <= 0 and "DUE" or (m >= 100 and "99+" or (m .. " MIN"))
                local plat = tostring(t.platform or ""):match("(%d+%a?)%s*$") or ""
                rows[s] = { text = { line = badge_of(t.line), dest = tfl_dest(t.destination), plat = plat, min = due }, outline = false }
            end
        else
            rows[s] = false
        end
    end
    return Splitflap.build(spec, rows), keys
end

-- ---------- Painter ----------
-- geom: { x0, y0, pitch, cw, ch, row_pitch }. The context supplies:
--   ctx.rect(x, y, w, h, color), ctx.glyph(g, x, y, w, h, dark, part) with part "full", "top" or "bottom",
--   ctx.black, ctx.white.
local function paintCell(ctx, geom, x, y, g, prev, flipping, dark)
    local ink = dark and ctx.white or ctx.black
    local w, h = geom.cw, geom.ch
    ctx.rect(x, y, w, h, ctx.black)
    if not dark then ctx.rect(x + 2, y + 2, w - 4, h - 4, ctx.white) end
    local mid = y + math.floor(h / 2)
    if flipping then
        ctx.glyph(g, x, y, w, h, dark, "top")
        ctx.glyph(prev, x, y, w, h, dark, "bottom")
        -- The falling flap: a wide band across the split.
        ctx.rect(x, mid - 3, w, 6, ink)
    else
        ctx.glyph(g, x, y, w, h, dark, "full")
        ctx.rect(x, mid, w, 1, ink)
    end
end

function Splitflap.cellX(spec, geom, c)
    return geom.x0 + (c - 1) * geom.pitch + (spec.field_of[c] - 1) * spec.gap
end

function Splitflap.paint(ctx, board, geom, anim, k)
    local spec = board.spec
    for r = 1, spec.nrows do
        local row = board.rows[r]
        if row.used or (anim and anim.rows[r]) then
            local y = geom.y0 + (r - 1) * geom.row_pitch
            for c = 1, spec.cols do
                local g, prev, flipping = Splitflap.cellAt(anim, board, r, c, k or 0)
                paintCell(ctx, geom, Splitflap.cellX(spec, geom, c), y, g, prev, flipping, not row.outline or spec.field_of[c] ~= spec.field_of[spec.cols])
            end
        end
    end
end

-- Rows y-range touched by an animation, for a limited screen refresh.
function Splitflap.dirtyRows(anim)
    local lo, hi
    for r in pairs(anim.rows) do
        lo = lo and math.min(lo, r) or r
        hi = hi and math.max(hi, r) or r
    end
    return lo, hi
end

return Splitflap
