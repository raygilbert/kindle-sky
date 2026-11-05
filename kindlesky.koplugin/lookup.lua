-- Route and airline lookup through adsbdb.com (https://github.com/mrjackwills/adsbdb).
-- Pure Lua: builds request URLs, parses responses and keeps a small cache. main.lua does the
-- network request. Only an aircraft hex code and a callsign are ever sent, never a location.
local Lookup = {}

local BASE = "https://api.adsbdb.com/v0/"
local TTL_FOUND, TTL_NONE, TTL_ERROR = 6 * 3600, 3600, 120

function Lookup.validHex(hex) return type(hex) == "string" and hex:match("^%x%x%x%x%x%x$") ~= nil end

function Lookup.cleanCallsign(callsign)
    local cs = tostring(callsign or ""):upper():gsub("%s+", "")
    return cs:match("^[A-Z0-9]+$") and #cs >= 3 and #cs <= 8 and cs or nil
end

function Lookup.key(plane)
    if not Lookup.validHex(plane.id) then return nil end
    return plane.id:upper() .. ":" .. (Lookup.cleanCallsign(plane.flight) or "")
end

function Lookup.aircraftUrl(hex, callsign)
    local url = BASE .. "aircraft/" .. hex:upper()
    if callsign then url = url .. "?callsign=" .. callsign end
    return url
end

function Lookup.callsignUrl(callsign) return BASE .. "callsign/" .. callsign end

local function clean(value, max)
    if type(value) ~= "string" then return nil end
    local s = value:gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return s ~= "" and s:sub(1, max or 40) or nil
end

local function airport(a)
    if type(a) ~= "table" then return nil end
    local code = clean(a.iata_code, 4) or clean(a.icao_code, 4)
    if not code then return nil end
    return { code = code:upper(), city = clean(a.municipality, 30) or clean(a.name, 30) }
end

-- Turns a decoded adsbdb response into { airline, type_name, route = { from, to } }, or nil.
function Lookup.parse(response)
    local body = type(response) == "table" and response.response
    if type(body) ~= "table" then return nil end
    local info = {}
    local ac, fr = body.aircraft, body.flightroute
    if type(ac) == "table" then
        local maker, kind = clean(ac.manufacturer, 20), clean(ac.type, 30)
        if kind then info.type_name = maker and (maker .. " " .. kind) or kind end
        info.owner = clean(ac.registered_owner, 40)
    end
    if type(fr) == "table" then
        local airline = type(fr.airline) == "table" and clean(fr.airline.name, 40)
        info.airline = airline or nil
        local from, to = airport(fr.origin), airport(fr.destination)
        if from and to then info.route = { from = from, to = to } end
    end
    info.airline = info.airline or info.owner
    if not (info.airline or info.type_name or info.route) then return nil end
    return info
end

-- Small bounded cache. Entries hold info (a table), or false for "looked up, nothing there".
function Lookup.cache(max)
    return { max = max or 64, items = {}, count = 0 }
end

function Lookup.get(cache, key, now)
    local e = cache.items[key]
    if not e then return "miss" end
    if now - e.at >= e.ttl then
        cache.items[key] = nil
        cache.count = cache.count - 1
        return "miss"
    end
    if e.info then return "found", e.info end
    return e.error and "error" or "none"
end

function Lookup.put(cache, key, info, now, failed)
    if not cache.items[key] then
        if cache.count >= cache.max then
            local oldest, when
            for k, e in pairs(cache.items) do
                if not when or e.at < when then oldest, when = k, e.at end
            end
            if oldest then cache.items[oldest] = nil; cache.count = cache.count - 1 end
        end
        cache.count = cache.count + 1
    end
    cache.items[key] = { info = info or false, at = now, error = failed and true or nil,
        ttl = info and TTL_FOUND or (failed and TTL_ERROR or TTL_NONE) }
end

return Lookup
