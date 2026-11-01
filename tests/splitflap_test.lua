-- Run with: python3 tests/run_unit.py   (needs the lupa package; no KOReader required)
local dir = ...
local S = dofile(dir .. "/kindlesky.koplugin/splitflap.lua")
local passed = 0
local function check(name, cond) if not cond then error("FAIL: " .. name, 2) end passed = passed + 1 end
local function badge(line) return (tostring(line):match("^%S+") or "?"):sub(1, 3):upper() end

-- clean
check("clean upper", S.clean("Center City") == "CENTER CITY")
check("clean accents become spaces", S.clean("Zürich"):find("ZRICH") == nil and #S.clean("Zürich") >= 5)
check("clean punctuation kept", S.clean("St. Pancras-A&B") == "ST. PANCRAS-A&B")
check("clean nil", S.clean(nil) == "")

-- sequence
local seq = S.sequence("A", "D", 5)
check("sequence walks", table.concat(seq) == "BCD")
check("sequence ends at target", S.sequence("Z", "A", 3)[#S.sequence("Z", "A", 3)] == "A")
check("sequence capped", #S.sequence("A", "9", 3) == 3)
check("sequence same glyph", #S.sequence("A", "A", 3) == 1 and S.sequence("A", "A", 3)[1] == "A")
check("sequence wraps", table.concat(S.sequence("9", "A", 5)):sub(-1) == "A")
check("sequence unknown glyphs safe", #S.sequence("~", "!", 3) >= 1)
check("sequence deterministic", table.concat(S.sequence("Q", "7", 4)) == table.concat(S.sequence("Q", "7", 4)))

-- board
local spec = S.specFor("septa", true)
check("spec cols", spec.cols == 27 and spec.nrows == 7)
local function septa(n, delay, dest) return { number = n, line = "Lansdale/Doylestown", destination = dest or "Center City", delay = delay } end
local trains = { septa("428", 0), septa("9312", 4, "Warminster"), septa("5522", nil, "Wilmington") }
local b1, keys1 = S.boardFor("septa", true, trains, nil, badge)
check("board shape", #b1.rows == 7 and #b1.rows[1].cells == 27)
check("row used flags", b1.rows[1].used and b1.rows[3].used and not b1.rows[4].used)
check("status text on time", table.concat(b1.rows[1].cells):sub(21) == "ON TIME")
check("status late outlined", b1.rows[2].outline and table.concat(b1.rows[2].cells):sub(21) == "LATE 4 ")
check("unknown outlined", b1.rows[3].outline and table.concat(b1.rows[3].cells):sub(21) == "UNKNOWN")
check("on time not outlined", not b1.rows[1].outline)
check("badge", table.concat(b1.rows[1].cells):sub(5, 7) == "LAN")
check("destination truncated to cells", #table.concat(S.boardFor("septa", true, { septa("1", 0, "A very long destination name indeed") }, nil, badge).rows[1].cells) == 27)

-- diff
check("diff identical empty", #S.diff(b1, b1) == 0)
local late = { septa("428", 3), trains[2], trains[3] }
local b2 = S.boardFor("septa", true, late, keys1, badge)
local d = S.diff(b1, b2)
check("diff finds status cells only", #d > 0 and #d <= 7)
for _, ch in ipairs(d) do check("diff in row 1 status", ch.row == 1 and ch.col >= 21) end
check("diff nil without previous", S.diff(nil, b2) == nil)
check("diff nil across layouts", S.diff(b1, S.boardFor("septa", false, trains, nil, badge)) == nil)

-- slots stay put when order changes
local reordered = { trains[3], trains[1], trains[2] }
local b3 = S.boardFor("septa", true, reordered, keys1, badge)
check("slots stable on re-sort", #S.diff(b1, b3) == 0)
local with_new = { trains[1], septa("77", 0, "Trenton"), trains[2], trains[3] }
local b4 = S.boardFor("septa", true, with_new, keys1, badge)
check("new train takes the free slot", table.concat(b4.rows[4].cells):sub(1, 2) == "77")
check("existing rows untouched by new train", #S.diff(b1, b4) > 0 and (function() for _, ch in ipairs(S.diff(b1, b4)) do if ch.row ~= 4 then return false end end return true end)())
local gone = { trains[1], trains[3] }
local b5, keys5 = S.boardFor("septa", true, gone, keys1, badge)
check("departed train frees its slot", not b5.rows[2].used and b5.rows[3].used)
check("keys follow slots", keys5[1] == "428" and keys5[2] == nil and keys5[3] == "5522")
local many = {}
for i = 1, 20 do many[i] = septa(tostring(100 + i), 0) end
check("more trains than slots is capped", #S.boardFor("septa", true, many, nil, badge).rows == 7)
local dup = { septa("1", 0), septa("1", 5) }
check("duplicate keys do not crash", S.boardFor("septa", true, dup, nil, badge).rows[2].used)

-- tfl
local tfl = { { line = "Central", destination = "Ealing Broadway Underground Station", platform = "Westbound - Platform 1", minutes = 2 },
              { line = "Elizabeth line", destination = "Reading Rail Station", platform = "", minutes = 0 },
              { line = "Northern", destination = "Morden", platform = "Platform 2", minutes = 240 } }
local t1 = S.boardFor("tfl", true, tfl, nil, badge)
check("tfl dest trimmed", table.concat(t1.rows[1].cells):sub(4, 18) == "EALING BROADWAY")
check("tfl platform", table.concat(t1.rows[1].cells):sub(19, 22) == "1   ")
check("tfl minutes", table.concat(t1.rows[1].cells):sub(23, 28) == "2 MIN ")
check("tfl due", table.concat(t1.rows[2].cells):sub(23, 28) == "DUE   ")
check("tfl big minutes", table.concat(t1.rows[3].cells):sub(23, 28) == "99+   ")
check("tfl never outlined", not t1.rows[1].outline and not t1.rows[2].outline)

-- plan
local plan = S.plan(d, { max_steps = 3, max_rows = 4, max_frames = 14 })
check("plan frames bounded", plan.frames > 0 and plan.frames <= 14)
check("plan covers every change", #plan.cells == #d)
local plan2 = S.plan(d, { max_steps = 3, max_rows = 4, max_frames = 14 })
check("plan deterministic", plan.frames == plan2.frames and #plan.cells == #plan2.cells)
local one = S.plan({ { row = 1, col = 1, from = "A", to = "B" } }, { max_steps = 2 })
check("single change flips once then settles", one.frames == #one.cells[1].seq)
-- cellAt reaches the final state and never flips afterwards
for _, cell in ipairs(plan.cells) do
    local g, _, flipping = S.cellAt(plan, b2, cell.row, cell.col, plan.frames)
    check("final glyph reached", g == b2.rows[cell.row].cells[cell.col] and not flipping)
    local g0, _, f0 = S.cellAt(plan, b2, cell.row, cell.col, 0)
    check("before start shows old glyph", cell.start > 0 and g0 == cell.from and not f0 or cell.start == 0)
end
-- row cap: changes past max_rows snap at frame 0
local wide = {}
for r = 1, 6 do wide[#wide + 1] = { row = r, col = 1, from = "A", to = "Z" } end
local capped = S.plan(wide, { max_steps = 3, max_rows = 2, max_frames = 14 })
local snap = capped.by_pos[6 * 1000 + 1]
check("rows beyond cap snap", #snap.seq == 1 and snap.start == 0)
check("frame cap holds", S.plan(wide, { max_steps = 6, max_rows = 6, max_frames = 8 }).frames <= 8)
local lo, hi = S.dirtyRows(capped)
check("dirty rows", lo == 1 and hi == 6)

-- painter calls only the context
local calls = 0
local ctx = { black = 1, white = 0, rect = function() calls = calls + 1 end, glyph = function() calls = calls + 1 end }
S.paint(ctx, b2, { x0 = 24, y0 = 160, pitch = 25, cw = 23, ch = 36, row_pitch = 50 }, plan, 2)
check("painter draws", calls > 27 * 3)
S.paint(ctx, b2, { x0 = 24, y0 = 160, pitch = 25, cw = 23, ch = 36, row_pitch = 50 }, nil, 0)
check("painter static", true)
print(string.format("splitflap: %d checks passed", passed))
