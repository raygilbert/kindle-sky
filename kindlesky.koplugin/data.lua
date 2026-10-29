local Data = {}

local pi = math.pi
local function rad(deg) return deg * pi / 180 end

function Data.distance_km(lat1, lon1, lat2, lon2)
    local dlat, dlon = rad(lat2 - lat1), rad(lon2 - lon1)
    local a = math.sin(dlat / 2)^2 + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dlon / 2)^2
    a = math.max(0, math.min(1, a))
    return 6371 * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
end

function Data.bearing(lat1, lon1, lat2, lon2)
    local a, b = rad(lat1), rad(lat2)
    local dlon = rad(lon2 - lon1)
    local y = math.sin(dlon) * math.cos(b)
    local x = math.cos(a) * math.sin(b) - math.sin(a) * math.cos(b) * math.cos(dlon)
    return (math.deg(math.atan2(y, x)) + 360) % 360
end

local rare_types = { A388=true, A225=true, A124=true, A337=true, A342=true, B748=true, AN22=true }

function Data.aircraft(response, lat, lon, radius_nm)
    local found = {}
    local list = type(response) == "table" and (response.ac or response.aircraft) or {}
    if type(list) ~= "table" then return found end
    for _, ac in ipairs(list) do
        if type(ac) == "table" then
            local alat, alon = tonumber(ac.lat), tonumber(ac.lon)
            local seen = tonumber(ac.seen_pos or ac.seen or 999)
            if alat and alon and seen and seen <= 120 then
                local km = Data.distance_km(lat, lon, alat, alon)
                local nm = km / 1.852
                if nm <= radius_nm then
                    local model = tostring(ac.t or ac.type or "")
                    local squawk = tostring(ac.squawk or "")
                    local flags = tonumber(ac.dbFlags) or 0
                    local military = flags % 2 == 1
                    local emergency = squawk == "7700" or squawk == "7600" or squawk == "7500"
                    local rare = emergency or military or rare_types[model] or false
                    found[#found + 1] = {
                        id = tostring(ac.hex or ""),
                        flight = tostring(ac.flight or ""):gsub("%s+$", ""),
                        registration = tostring(ac.r or ""),
                        model = model,
                        description = tostring(ac.desc or ""),
                        altitude_ft = ac.alt_baro == "ground" and 0 or tonumber(ac.alt_baro or ac.alt_geom),
                        speed_kt = tonumber(ac.gs),
                        heading = tonumber(ac.track),
                        vrate_fpm = tonumber(ac.baro_rate or ac.geom_rate),
                        distance_nm = nm,
                        bearing = Data.bearing(lat, lon, alat, alon),
                        emergency = emergency,
                        military = military,
                        rare = rare,
                        squawk = squawk,
                    }
                end
            end
        end
    end
    table.sort(found, function(a, b)
        if a.rare ~= b.rare then return a.rare end
        return a.distance_nm < b.distance_nm
    end)
    return found
end

-- Is the aircraft heading toward the observer, away, or across? bearing is the direction
-- from the observer to the aircraft; heading is the aircraft's own track. nil when unknown.
function Data.motion(heading, bearing)
    if type(heading) ~= "number" or type(bearing) ~= "number" then return nil end
    local diff = math.abs((heading - (bearing + 180) + 540) % 360 - 180)
    if diff <= 60 then return "APPROACHING" end
    if diff >= 120 then return "MOVING AWAY" end
    return "CROSSING"
end

-- Climb or descent from a vertical rate in feet per minute. Under 300 fpm counts as level.
function Data.climb(vrate_fpm)
    if type(vrate_fpm) ~= "number" then return nil, nil end
    local rounded = math.floor(math.abs(vrate_fpm) / 100 + 0.5) * 100
    if rounded < 300 then return "level", "LEVEL" end
    if vrate_fpm > 0 then return "up", string.format("+%d fpm", rounded) end
    return "down", string.format("-%d fpm", rounded)
end

return Data
