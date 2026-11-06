local dir = ...
local Logbook = dofile(dir .. "/kindlesky.koplugin/logbook.lua")
local Lookup = dofile(dir .. "/kindlesky.koplugin/lookup.lua")
local passed = 0
local function check(name, cond) if not cond then error("FAIL: " .. name, 2) end passed = passed + 1 end

-- ---------- logbook ----------
local plane = { model = "B738", registration = "N12345", id = "a1b2c3", description = "BOEING 737-800" }
local info = { airline = "United Airlines", type_name = "Boeing 737-800" }
local book = Logbook.new(1000)
local e = Logbook.entry(plane, info)
check("entry keys", e.type == "B738" and e.reg == "N12345" and e.airline == "United Airlines")
check("entry falls back to hex", Logbook.entry({ model = "A320", registration = "", id = "abc123" }, nil).reg == "ABC123")
check("entry needs an identifier", Logbook.entry({ model = "A320", registration = "", id = "" }, nil) == nil)
check("entry without type still ok", Logbook.entry({ model = "", registration = "G-ABCD", id = "400001" }, nil).type == nil)

local st = Logbook.status(book, e, "20261104")
check("empty book: everything is new", st.new_type and st.new_reg and not st.today)
local r1 = Logbook.capture(book, e, 2000, "20261104")
check("first capture is new type and plane", r1.new_type and r1.new_reg and r1.type_count == 1 and r1.reg_count == 1)
check("second tap same day is refused", select(2, Logbook.capture(book, e, 2100, "20261104")) == "today")
check("counts unchanged by refused tap", book.types.B738.count == 1 and book.regs.N12345.count == 1)
check("status after capture", Logbook.status(book, e, "20261104").today and not Logbook.status(book, e, "20261105").today)
local r2 = Logbook.capture(book, e, 90000, "20261105")
check("next day same plane counts again", not r2.new_type and not r2.new_reg and r2.type_count == 2 and r2.reg_count == 2)
local other = Logbook.entry({ model = "B738", registration = "N99999", id = "a00001" }, info)
local r3 = Logbook.capture(book, other, 91000, "20261105")
check("same type new plane", not r3.new_type and r3.new_reg and r3.type_count == 3 and r3.reg_count == 1)
local beluga = Logbook.entry({ model = "BLCF", registration = "F-GSTB", id = "3a1b2c", description = "AIRBUS BELUGA" }, { airline = "Airbus Transport", type_name = "Airbus A300-608ST Beluga" })
Logbook.capture(book, beluga, 92000, "20261105")
local totals = Logbook.totals(book)
check("totals", totals.types == 2 and totals.planes == 3 and totals.airlines == 2)
check("type name updated from lookup", book.types.BLCF.name == "Airbus A300-608ST Beluga")

local items, page, pages = Logbook.list(book, 1, 6)
check("list newest first", items[1].type == "BLCF" and items[2].type == "B738" and page == 1 and pages == 1)
local big = Logbook.new(1)
for i = 1, 14 do Logbook.capture(big, { type = "T" .. i, type_name = "Type " .. i, reg = "R" .. i, airline = "" }, 100 + i, "d" .. i) end
local _, p, ps = Logbook.list(big, 99, 6)
check("pages clamp", ps == 3 and p == 3)
check("page 0 clamps", select(2, Logbook.list(big, 0, 6)) == 1)
check("empty list", #Logbook.list(Logbook.new(1), 1, 6) == 0 and select(3, Logbook.list(Logbook.new(1), 1, 6)) == 1)

-- eviction keeps the book bounded
local huge = Logbook.new(1)
for i = 1, 2105 do Logbook.capture(huge, { type = nil, type_name = "", reg = "X" .. i, airline = "" }, i, "d" .. i) end
local n = 0 for _ in pairs(huge.regs) do n = n + 1 end
check("registrations are capped", n == 2000 and huge.regs["X1"] == nil and huge.regs["X2105"] ~= nil)

-- sanitize
check("sanitize non-table", Logbook.sanitize("junk", 5).since == 5)
local dirty = Logbook.sanitize({ since = "x", types = { B738 = { name = 5, count = -3, first = "z" }, [5] = {}, TOOLONGCODE1 = {}, A320 = "bad" },
    regs = { N1 = { type = {}, airline = "A\nB", count = 1e12 }, [{}] = 1 } }, 7)
check("sanitize keeps valid entries", dirty.types.B738 ~= nil and dirty.types.B738.count == 1 and dirty.types.A320 == nil and dirty.types.TOOLONGCODE1 == nil)
check("sanitize clips values", dirty.regs.N1.count == 999999 and dirty.regs.N1.airline == "A B" and dirty.since == 7)
check("sanitized book works", Logbook.capture(dirty, Logbook.entry({ model = "B738", registration = "N5", id = "000001" }, nil), 10, "d") ~= nil)

-- ---------- lookup ----------
check("valid hex", Lookup.validHex("a1B2c3") and not Lookup.validHex("a1b2c") and not Lookup.validHex("a1b2c3 ") and not Lookup.validHex("a1b2/3") and not Lookup.validHex(nil))
check("callsign cleaned", Lookup.cleanCallsign("UAL1234  ") == "UAL1234" and Lookup.cleanCallsign("a/b") == nil and Lookup.cleanCallsign("AB") == nil and Lookup.cleanCallsign("") == nil)
check("key", Lookup.key({ id = "a1b2c3", flight = "UAL1234" }) == "A1B2C3:UAL1234" and Lookup.key({ id = "zz" }) == nil)
check("urls", Lookup.aircraftUrl("a1b2c3", "UAL1234") == "https://api.adsbdb.com/v0/aircraft/A1B2C3?callsign=UAL1234"
    and Lookup.aircraftUrl("a1b2c3", nil) == "https://api.adsbdb.com/v0/aircraft/A1B2C3"
    and Lookup.callsignUrl("UAL1234") == "https://api.adsbdb.com/v0/callsign/UAL1234")

local full = { response = {
    aircraft = { type = "737-800", manufacturer = "Boeing", registration = "N12345", registered_owner = "United Air Lines Inc" },
    flightroute = { callsign = "UAL1234", airline = { name = "United Airlines" },
        origin = { iata_code = "PHL", icao_code = "KPHL", municipality = "Philadelphia", name = "Philadelphia International Airport" },
        destination = { iata_code = "ORD", icao_code = "KORD", municipality = "Chicago", name = "O'Hare" } } } }
local p = Lookup.parse(full)
check("parse airline prefers route airline", p.airline == "United Airlines")
check("parse type", p.type_name == "Boeing 737-800")
check("parse route", p.route.from.code == "PHL" and p.route.to.city == "Chicago")
local only_ac = Lookup.parse({ response = { aircraft = { type = "A300", manufacturer = "Airbus", registered_owner = "Airbus Transport" } } })
check("aircraft only", only_ac.airline == "Airbus Transport" and only_ac.route == nil)
local no_iata = Lookup.parse({ response = { flightroute = { airline = { name = "X" }, origin = { icao_code = "EGLL", name = "Heathrow" }, destination = { icao_code = "LFPG", municipality = "Paris" } } } })
check("icao fallback", no_iata.route.from.code == "EGLL" and no_iata.route.from.city == "Heathrow")
check("unknown responses", Lookup.parse({ response = "unknown callsign" }) == nil and Lookup.parse(nil) == nil and Lookup.parse({}) == nil and Lookup.parse("x") == nil)
check("hostile values", Lookup.parse({ response = { aircraft = { type = 5, manufacturer = {}, registered_owner = "A\0B\n" } } }).airline == "A B")
check("partial route ignored", Lookup.parse({ response = { flightroute = { airline = { name = "X" }, origin = { iata_code = "PHL" } } } }).route == nil)

-- cache
local cache = Lookup.cache(3)
check("miss", Lookup.get(cache, "a", 0) == "miss")
Lookup.put(cache, "a", p, 0)
check("found", Lookup.get(cache, "a", 10) == "found" and select(2, Lookup.get(cache, "a", 10)) == p)
check("found expires", Lookup.get(cache, "a", 6 * 3600 + 1) == "miss")
Lookup.put(cache, "n", false, 0)
check("none cached", Lookup.get(cache, "n", 100) == "none" and Lookup.get(cache, "n", 3601) == "miss")
Lookup.put(cache, "e", false, 0, true)
check("error cached briefly", Lookup.get(cache, "e", 60) == "error" and Lookup.get(cache, "e", 121) == "miss")
for i = 1, 10 do Lookup.put(cache, "k" .. i, p, i) end
check("cache bounded", cache.count <= 3 and Lookup.get(cache, "k10", 11) == "found" and Lookup.get(cache, "k1", 11) == "miss")
print(string.format("logbook and lookup: %d checks passed", passed))
