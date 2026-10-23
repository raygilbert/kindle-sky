-- Small, approximate orbit viewer for CelesTrak OMM/JSON elements.
-- Uses Kepler motion with secular J2 drift. OMM elements are fitted for SGP4,
-- so these look angles are indicative, not precise pass predictions.
local Satellites = {}

local pi, sin, cos, sqrt = math.pi, math.sin, math.cos, math.sqrt
local rad, deg = math.rad, math.deg
local floor, atan2 = math.floor, math.atan2
local mu, earth_radius, j2 = 398600.8, 6378.135, 0.001082616
local xke = 0.0743669161331734132 -- WGS-72 Earth radii^(3/2) per minute
local seconds_per_day = 86400
local two_pi = 2 * pi

local function julian_date(value)
    if type(value) ~= "string" then return nil end
    local year, month, day, hour, minute, second =
        value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d%.?%d*)")
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    hour, minute, second = tonumber(hour), tonumber(minute), tonumber(second)
    if not year or not month or not day or not hour or not minute or not second
        or month < 1 or month > 12 or day < 1 or day > 31
        or hour > 23 or minute > 59 or second >= 61 then return nil end
    local a = floor((14 - month) / 12)
    local y, m = year + 4800 - a, month + 12 * a - 3
    local jdn = day + floor((153 * m + 2) / 5) + 365 * y
        + floor(y / 4) - floor(y / 100) + floor(y / 400) - 32045
    return jdn - 0.5 + (hour * 3600 + minute * 60 + second) / seconds_per_day
end

local function finite(value)
    local n = tonumber(value)
    if n and n == n and n ~= math.huge and n ~= -math.huge then return n end
end

function Satellites.parse(response, now)
    if type(response) ~= "table" then return nil end
    local found, seen = {}, {}
    local current_jd = (now or os.time()) / seconds_per_day + 2440587.5
    for _, row in ipairs(response) do
        if type(row) == "table" then
            local id = finite(row.NORAD_CAT_ID)
            local epoch = julian_date(row.EPOCH)
            local motion = finite(row.MEAN_MOTION)
            local e = finite(row.ECCENTRICITY)
            local inclination = finite(row.INCLINATION)
            local raan = finite(row.RA_OF_ASC_NODE)
            local argp = finite(row.ARG_OF_PERICENTER)
            local anomaly = finite(row.MEAN_ANOMALY)
            if id and epoch and motion and e and inclination and raan and argp and anomaly
                and not seen[id] and motion >= 6 and motion <= 17 and e >= 0 and e < 0.2
                and current_jd - epoch >= -1 and current_jd - epoch <= 3 then
                seen[id] = true
                local name = tostring(row.OBJECT_NAME or ("NORAD " .. id)):gsub("[%c]", " ")
                if #name > 32 then name = name:sub(1, 32) end
                found[#found + 1] = {
                    id = id, name = name, epoch = epoch, motion = motion,
                    e = e, inclination = rad(inclination), raan = rad(raan),
                    argp = rad(argp), anomaly = rad(anomaly),
                }
            end
        end
    end
    return found
end

local function gmst(jd)
    local t = (jd - 2451545.0) / 36525
    return rad((280.46061837 + 360.98564736629 * (jd - 2451545)
        + 0.000387933 * t * t - t * t * t / 38710000) % 360)
end

local function sun_direction(jd)
    -- Low-precision solar direction is sufficient for a twilight/shadow hint.
    local days = jd - 2451545.0
    local mean_longitude = rad((280.460 + 0.9856474 * days) % 360)
    local mean_anomaly = rad((357.528 + 0.9856003 * days) % 360)
    local longitude = mean_longitude + rad(1.915) * sin(mean_anomaly)
        + rad(0.020) * sin(2 * mean_anomaly)
    local obliquity = rad(23.439 - 0.0000004 * days)
    return cos(longitude), cos(obliquity) * sin(longitude), sin(obliquity) * sin(longitude)
end

function Satellites.position(sat, now, lat, lon)
    if not sat or not finite(lat) or not finite(lon) then return nil end
    local jd = now / seconds_per_day + 2440587.5
    local dt = (jd - sat.epoch) * seconds_per_day
    if dt < -seconds_per_day or dt > 3 * seconds_per_day then return nil end
    -- Undo the Kozai mean-motion adjustment carried by GP/OMM elements.
    local no = sat.motion * two_pi / 1440
    local cos_i = cos(sat.inclination)
    local one_minus_e2 = 1 - sat.e * sat.e
    local ak = (xke / no) ^ (2 / 3)
    local d1 = 0.75 * j2 * (3 * cos_i * cos_i - 1)
        / (sqrt(one_minus_e2) * one_minus_e2)
    local delta = d1 / (ak * ak)
    local adel = ak * (1 - delta * delta - delta * (1 / 3 + 134 * delta * delta / 81))
    no = no / (1 + d1 / (adel * adel))
    local n = no / 60
    local a = (mu / (n * n)) ^ (1 / 3)
    local p = a * (1 - sat.e * sat.e)
    local ci = cos(sat.inclination)
    local factor = j2 * (earth_radius / p) ^ 2 * n
    local raan = sat.raan - 1.5 * factor * ci * dt
    local argp = sat.argp + 0.75 * factor * (5 * ci * ci - 1) * dt
    local mean = (sat.anomaly + (n + 0.75 * factor * sqrt(1 - sat.e * sat.e)
        * (3 * ci * ci - 1)) * dt) % two_pi
    local eccentric = mean
    for _ = 1, 7 do
        eccentric = eccentric - (eccentric - sat.e * sin(eccentric) - mean)
            / (1 - sat.e * cos(eccentric))
    end
    local true_anomaly = atan2(sqrt(1 - sat.e * sat.e) * sin(eccentric),
        cos(eccentric) - sat.e)
    local r = a * (1 - sat.e * cos(eccentric))
    local u = argp + true_anomaly
    local cu, su, co, so, si = cos(u), sin(u), cos(raan), sin(raan), sin(sat.inclination)
    local x = r * (co * cu - so * su * ci)
    local y = r * (so * cu + co * su * ci)
    local z = r * su * si
    local theta = gmst(jd)
    local x_ecef = cos(theta) * x + sin(theta) * y
    local y_ecef = -sin(theta) * x + cos(theta) * y
    local latitude, longitude = rad(lat), rad(lon)
    local clat, slat, clon, slon = cos(latitude), sin(latitude), cos(longitude), sin(longitude)
    local flattening = 1 / 298.257223563
    local ecc2 = flattening * (2 - flattening)
    local normal = earth_radius / sqrt(1 - ecc2 * slat * slat)
    local dx = x_ecef - normal * clat * clon
    local dy = y_ecef - normal * clat * slon
    local dz = z - normal * (1 - ecc2) * slat
    local east = -slon * dx + clon * dy
    local north = -slat * clon * dx - slat * slon * dy + clat * dz
    local up = clat * clon * dx + clat * slon * dy + slat * dz
    local range = sqrt(east * east + north * north + up * up)
    local sx, sy, sz = sun_direction(jd)
    local sun_x = cos(theta) * sx + sin(theta) * sy
    local sun_y = -sin(theta) * sx + cos(theta) * sy
    local sun_elevation = deg(math.asin(math.max(-1, math.min(1,
        clat * clon * sun_x + clat * slon * sun_y + slat * sz))))
    local sun_dot = x * sx + y * sy + z * sz
    local sunlit = sun_dot >= 0 or sqrt(math.max(0, r * r - sun_dot * sun_dot)) > earth_radius
    local dark_sky = sun_elevation <= -6
    return {
        id = sat.id, name = sat.name,
        bearing = (deg(atan2(east, north)) + 360) % 360,
        elevation = deg(math.asin(math.max(-1, math.min(1, up / range)))),
        range_km = range, altitude_km = r - earth_radius,
        iss = sat.id == 25544,
        sunlit = sunlit, dark_sky = dark_sky,
        possible_visible = sunlit and dark_sky,
    }
end

function Satellites.overhead(catalog, now, lat, lon, min_elevation)
    local found = {}
    for _, sat in ipairs(catalog or {}) do
        local position = Satellites.position(sat, now, lat, lon)
        if position and position.elevation >= (min_elevation or 10) then
            found[#found + 1] = position
        end
    end
    table.sort(found, function(a, b) return a.elevation > b.elevation end)
    return found
end

function Satellites.feature(overhead)
    for _, sat in ipairs(overhead or {}) do
        if sat.iss and sat.elevation >= 20 then return sat end
    end
    return overhead and overhead[1] or nil
end

return Satellites
