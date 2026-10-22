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
    local list = response and (response.ac or response.aircraft) or {}
    for _, ac in ipairs(list) do
        local alat, alon = tonumber(ac.lat), tonumber(ac.lon)
        local seen = tonumber(ac.seen_pos or ac.seen or 999)
        if alat and alon and seen <= 120 then
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
    table.sort(found, function(a, b)
        if a.rare ~= b.rare then return a.rare end
        return a.distance_nm < b.distance_nm
    end)
    return found
end

function Data.iss(response, lat, lon)
    if not response or not tonumber(response.latitude) or not tonumber(response.longitude) then return nil end
    local ilat, ilon = tonumber(response.latitude), tonumber(response.longitude)
    local altitude = tonumber(response.altitude) or 0
    local ground_distance = Data.distance_km(lat, lon, ilat, ilon)
    local earth_radius = 6371
    local central_angle = ground_distance / earth_radius
    local elevation = math.deg(math.atan2((earth_radius + altitude) * math.cos(central_angle) - earth_radius,
        (earth_radius + altitude) * math.sin(central_angle)))
    return {
        lat = ilat, lon = ilon,
        altitude_km = altitude,
        velocity_kmh = tonumber(response.velocity),
        distance_km = ground_distance,
        bearing = Data.bearing(lat, lon, ilat, ilon),
        elevation = elevation,
        timestamp = tonumber(response.timestamp),
    }
end

function Data.pass(response, now)
    local p = response and response.pass
    if not p or not tonumber(p.startUTC) then return nil end
    local start = tonumber(p.startUTC)
    local finish = tonumber(p.endUTC) or start + 600
    if finish < now then return nil end
    return {
        start = start,
        peak = tonumber(p.peakUTC),
        finish = finish,
        minutes = math.max(0, math.ceil((start - now) / 60)),
        direction = tostring(p.startDirection or "?"),
        peak_direction = tostring(p.peakDirection or "?"),
        end_direction = tostring(p.endDirection or "?"),
        elevation = tonumber(p.maxElevation),
        duration_seconds = tonumber(p.durationSeconds),
        visible = p.visible == true,
        active = p.inProgress == true or (start <= now and now <= finish),
    }
end

return Data
