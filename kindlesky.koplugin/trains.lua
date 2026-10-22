local Data = dofile(debug.getinfo(1, "S").source:match("^@(.*/)") .. "data.lua")
local Trains = {}

-- These are feed coverage gates, not a claim that every point has service.
function Trains.provider(lat, lon)
    lat, lon = tonumber(lat), tonumber(lon)
    if not lat or not lon then return nil end
    if lat >= 39.5 and lat <= 40.6 and lon >= -76.2 and lon <= -74.5 then return "septa" end
    if lat >= 51.2 and lat <= 51.75 and lon >= -0.55 and lon <= 0.35 then return "tfl" end
    return nil
end

function Trains.septa(response, lat, lon, radius_nm)
    if type(response) ~= "table" then return nil end
    local found = {}
    for _, row in ipairs(response) do
        local rlat, rlon = tonumber(row.lat), tonumber(row.lon)
        if rlat and rlon then
            local distance_nm = Data.distance_km(lat, lon, rlat, rlon) / 1.852
            if distance_nm <= radius_nm then
                found[#found + 1] = {
                    number = tostring(row.trainno or "?"), line = tostring(row.line or "Regional Rail"),
                    destination = tostring(row.dest or "Unknown"), next_stop = tostring(row.nextstop or ""),
                    current_stop = tostring(row.currentstop or ""), delay = tonumber(row.late),
                    distance_nm = distance_nm, bearing = Data.bearing(lat, lon, rlat, rlon),
                }
            end
        end
    end
    table.sort(found, function(a, b) return a.distance_nm < b.distance_nm end)
    return found
end

function Trains.closestStop(response, lat, lon)
    local stops = response and response.stopPoints
    if type(stops) ~= "table" then return nil end
    local best, distance
    for _, stop in ipairs(stops) do
        local slat, slon = tonumber(stop.lat), tonumber(stop.lon)
        if slat and slon and type(stop.id) == "string" and stop.id:match("^[%w]+$") then
            local d = Data.distance_km(lat, lon, slat, slon)
            if not distance or d < distance then
                best, distance = { id = stop.id, name = tostring(stop.commonName or "Nearby station"), distance_km = d }, d
            end
        end
    end
    return best
end

function Trains.tfl(response)
    if type(response) ~= "table" then return nil end
    local found = {}
    for _, row in ipairs(response) do
        local seconds = tonumber(row.timeToStation)
        local mode = tostring(row.modeName or "")
        if seconds and seconds >= 0 and seconds <= 7200
            and (mode == "tube" or mode == "dlr" or mode == "overground" or mode == "elizabeth-line") then
            found[#found + 1] = {
                line = tostring(row.lineName or "Rail"), destination = tostring(row.destinationName or "Unknown"),
                platform = tostring(row.platformName or ""), minutes = math.ceil(seconds / 60), mode = mode,
            }
        end
    end
    table.sort(found, function(a, b) return a.minutes < b.minutes end)
    return found
end

function Trains.stopUrl(lat, lon)
    return string.format("https://api.tfl.gov.uk/StopPoint?lat=%.4f&lon=%.4f&stopTypes=NaptanMetroStation,NaptanRailStation&radius=1500&modes=tube,dlr,overground,elizabeth-line&categories=none&returnLines=false", lat, lon)
end

return Trains
