-- Weather from Open-Meteo (https://open-meteo.com), CC BY 4.0, no key, free for non-commercial use.
-- Pure Lua: builds the request URL and turns the JSON into a small table the screen can draw.
-- main.lua does the network request. Only the latitude and longitude are ever sent.
local Weather = {}

local BASE = "https://api.open-meteo.com/v1/forecast"
Weather.TTL = 30 * 60        -- ask again after this long
Weather.RETRY = 5 * 60       -- after a failure
Weather.STALE = 3 * 3600     -- stop showing data older than this
Weather.HOURS, Weather.DAYS = 8, 3

-- "us" (Fahrenheit, mph, inHg) or "metric" (Celsius, km/h, hPa). "auto" picks by position.
function Weather.units(setting, lat, lon)
    if setting == "us" or setting == "metric" then return setting end
    lat, lon = tonumber(lat), tonumber(lon)
    if lat and lon and lat >= 18 and lat <= 72 and lon >= -170 and lon <= -66 then return "us" end
    return "metric"
end

function Weather.url(lat, lon, units)
    local us = units == "us"
    return string.format("%s?latitude=%.3f&longitude=%.3f&timezone=auto&forecast_days=%d"
        .. "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day,"
        .. "wind_speed_10m,wind_gusts_10m,wind_direction_10m,pressure_msl"
        .. "&hourly=temperature_2m,weather_code,precipitation_probability,is_day"
        .. "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"
        .. "&temperature_unit=%s&wind_speed_unit=%s",
        BASE, lat, lon, Weather.DAYS + 1, us and "fahrenheit" or "celsius", us and "mph" or "kmh")
end

-- WMO weather interpretation codes -> short text and an icon name.
-- Icons: sun, moon, part (sun behind cloud), cloud, fog, rain, snow, storm.
function Weather.describe(code, is_day)
    code = tonumber(code)
    if not code then return "Unknown", "cloud" end
    if code == 0 then return is_day == false and "Clear" or "Sunny", is_day == false and "moon" or "sun" end
    if code == 1 then return "Mostly clear", is_day == false and "moon" or "sun" end
    if code == 2 then return "Partly cloudy", is_day == false and "cloud" or "part" end
    if code == 3 then return "Overcast", "cloud" end
    if code == 45 or code == 48 then return "Fog", "fog" end
    if code >= 51 and code <= 55 then return "Drizzle", "rain" end
    if code == 56 or code == 57 then return "Freezing drizzle", "rain" end
    if code == 61 then return "Light rain", "rain" end
    if code == 63 then return "Rain", "rain" end
    if code == 65 then return "Heavy rain", "rain" end
    if code == 66 or code == 67 then return "Freezing rain", "rain" end
    if code == 71 then return "Light snow", "snow" end
    if code == 73 then return "Snow", "snow" end
    if code == 75 then return "Heavy snow", "snow" end
    if code == 77 then return "Snow grains", "snow" end
    if code >= 80 and code <= 82 then return "Showers", "rain" end
    if code == 85 or code == 86 then return "Snow showers", "snow" end
    if code == 95 then return "Thunderstorm", "storm" end
    if code == 96 or code == 99 then return "Thunderstorm, hail", "storm" end
    return "Unknown", "cloud"
end

local COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
function Weather.compass(degrees)
    degrees = tonumber(degrees)
    if not degrees then return nil end
    return COMPASS[math.floor(((degrees % 360) + 22.5) / 45) % 8 + 1]
end

-- "2026-11-07T06:41" -> year, month, day, hour, minute (local time of the place).
local function parseTime(s)
    if type(s) ~= "string" then return nil end
    local y, mo, d, h, mi = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d)")
    if y then return tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi) end
    y, mo, d = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if y then return tonumber(y), tonumber(mo), tonumber(d), 0, 0 end
end

-- 12-hour clock text: "6:41 AM", or just the hour ("9 PM" / "10") for the hour strip.
function Weather.clock(s)
    local _, _, _, h, mi = parseTime(s)
    if not h then return nil end
    return string.format("%d:%02d %s", (h + 11) % 12 + 1, mi, h < 12 and "AM" or "PM")
end

local function hourLabel(h, with_suffix)
    local n = (h + 11) % 12 + 1
    if with_suffix or h == 0 or h == 12 then return n .. (h < 12 and " AM" or " PM") end
    return tostring(n)
end

-- Weekday name of a calendar date (Sakamoto's method), independent of the device time zone.
local DAYS = { "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" }
function Weather.weekday(y, m, d)
    local t = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
    if m < 3 then y = y - 1 end
    return DAYS[(y + math.floor(y / 4) - math.floor(y / 100) + math.floor(y / 400) + t[m] + d) % 7 + 1]
end

local function num(v)
    if type(v) == "number" and v == v and v > -1e6 and v < 1e6 then return v end
end

local function round(v) return v and math.floor(v + 0.5) or nil end

-- Parse an Open-Meteo forecast response. Returns a table, or nil and a reason.
function Weather.parse(resp, units)
    if type(resp) ~= "table" then return nil, "Invalid response" end
    if resp.error then return nil, "Weather service error" end
    local cur, hourly, daily = resp.current, resp.hourly, resp.daily
    if type(cur) ~= "table" or type(hourly) ~= "table" or type(daily) ~= "table" then
        return nil, "Incomplete weather data"
    end
    local temp = num(cur.temperature_2m)
    if not temp then return nil, "No temperature" end
    local us = units == "us"
    local is_day = cur.is_day ~= 0
    local text, icon = Weather.describe(cur.weather_code, is_day)
    local pressure = num(cur.pressure_msl)
    if pressure and us then pressure = pressure * 0.02953 end
    local out = {
        units = us and "us" or "metric",
        time = type(cur.time) == "string" and cur.time or nil,
        now = {
            temp = round(temp), feels = round(num(cur.apparent_temperature)),
            humidity = round(num(cur.relative_humidity_2m)), text = text, icon = icon,
            wind = round(num(cur.wind_speed_10m)), gust = round(num(cur.wind_gusts_10m)),
            dir = Weather.compass(cur.wind_direction_10m),
            pressure = pressure and (us and string.format("%.2f", pressure) or string.format("%d", round(pressure))) or nil,
        },
        hours = {}, days = {},
    }

    local dtimes, dcode = daily.time, daily.weather_code
    local dhi, dlo, dpop = daily.temperature_2m_max, daily.temperature_2m_min, daily.precipitation_probability_max
    if type(dtimes) ~= "table" or type(dhi) ~= "table" or type(dlo) ~= "table" then return nil, "No daily data" end
    out.hi, out.lo = round(num(dhi[1])), round(num(dlo[1]))
    out.sunrise = type(daily.sunrise) == "table" and Weather.clock(daily.sunrise[1]) or nil
    out.sunset = type(daily.sunset) == "table" and Weather.clock(daily.sunset[1]) or nil
    for i = 2, Weather.DAYS + 1 do
        local y, mo, d = parseTime(dtimes[i])
        if y and num(dhi[i]) and num(dlo[i]) then
            local dtext, dicon = Weather.describe(type(dcode) == "table" and dcode[i], true)
            out.days[#out.days + 1] = { name = Weather.weekday(y, mo, d), hi = round(dhi[i]), lo = round(dlo[i]),
                text = dtext, icon = dicon, pop = type(dpop) == "table" and round(num(dpop[i])) or nil }
        end
    end

    -- Hourly strip: the next hours after the current time (ISO strings compare in time order).
    local htimes, htemp, hcode = hourly.time, hourly.temperature_2m, hourly.weather_code
    local hpop, hday = hourly.precipitation_probability, hourly.is_day
    if type(htimes) ~= "table" or type(htemp) ~= "table" then return nil, "No hourly data" end
    local first
    for i, t in ipairs(htimes) do
        if type(t) == "string" and out.time and t > out.time then first = i; break end
    end
    first = first or 2
    for i = first, math.min(#htimes, first + Weather.HOURS - 1) do
        local _, _, _, h = parseTime(htimes[i])
        if h and num(htemp[i]) then
            local htext, hicon = Weather.describe(type(hcode) == "table" and hcode[i], type(hday) ~= "table" or hday[i] ~= 0)
            out.hours[#out.hours + 1] = { label = hourLabel(h, #out.hours == 0), temp = round(htemp[i]),
                icon = hicon, text = htext, pop = type(hpop) == "table" and round(num(hpop[i])) or nil }
        end
    end
    if #out.hours == 0 then return nil, "No hourly data" end
    out.rain_next = out.hours[1].pop
    return out
end

function Weather.tempUnit(units) return units == "us" and "F" or "C" end
function Weather.speedUnit(units) return units == "us" and "mph" or "km/h" end
function Weather.pressureUnit(units) return units == "us" and "in" or "hPa" end

return Weather
