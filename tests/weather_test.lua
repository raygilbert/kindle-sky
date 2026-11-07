local dir = ...
local Weather = dofile(dir .. "/kindlesky.koplugin/weather.lua")
local passed = 0
local function check(name, cond) if not cond then error("FAIL: " .. name, 2) end passed = passed + 1 end

check("units explicit", Weather.units("us", 51, 0) == "us" and Weather.units("metric", 40, -75) == "metric")
check("units auto US", Weather.units("auto", 40.24, -75.28) == "us")
check("units auto UK", Weather.units("auto", 51.5, -0.12) == "metric")
check("units auto garbage", Weather.units("auto", nil, nil) == "metric")

local url = Weather.url(40.2412345, -75.2812345, "us")
check("url has rounded coords only", url:find("latitude=40.241&longitude=-75.281", 1, true) ~= nil)
check("url us units", url:find("temperature_unit=fahrenheit", 1, true) and url:find("wind_speed_unit=mph", 1, true))
check("url metric units", Weather.url(51.5, -0.12, "metric"):find("temperature_unit=celsius", 1, true) ~= nil)
check("url sends nothing else personal", not url:find("key") and not url:find("email"))

check("code 0 day", select(2, Weather.describe(0, true)) == "sun")
check("code 0 night", select(2, Weather.describe(0, false)) == "moon")
check("code 2 day/night", select(2, Weather.describe(2, true)) == "part" and select(2, Weather.describe(2, false)) == "cloud")
check("rain codes", select(2, Weather.describe(63)) == "rain" and select(2, Weather.describe(81)) == "rain")
check("snow codes", select(2, Weather.describe(73)) == "snow" and select(2, Weather.describe(86)) == "snow")
check("storm codes", select(2, Weather.describe(95)) == "storm" and select(2, Weather.describe(99)) == "storm")
check("fog", select(2, Weather.describe(45)) == "fog")
check("unknown code is safe", Weather.describe(1234) == "Unknown" and Weather.describe(nil) == "Unknown" and Weather.describe("x") == "Unknown")

check("compass", Weather.compass(0) == "N" and Weather.compass(315) == "NW" and Weather.compass(350) == "N" and Weather.compass(90) == "E" and Weather.compass(-45) == "NW")
check("compass bad", Weather.compass(nil) == nil and Weather.compass("x") == nil)
check("clock", Weather.clock("2026-11-07T06:41") == "6:41 AM" and Weather.clock("2026-11-07T16:52") == "4:52 PM")
check("clock midnight noon", Weather.clock("2026-11-07T00:05") == "12:05 AM" and Weather.clock("2026-11-07T12:00") == "12:00 PM")
check("clock bad", Weather.clock(nil) == nil and Weather.clock("soon") == nil)
check("weekday", Weather.weekday(2026, 11, 7) == "SAT" and Weather.weekday(2026, 11, 8) == "SUN" and Weather.weekday(2024, 2, 29) == "THU" and Weather.weekday(2000, 1, 1) == "SAT")

local function sample()
    local hours = { time = {}, temperature_2m = {}, weather_code = {}, precipitation_probability = {}, is_day = {} }
    for i = 0, 95 do
        local day, h = 7 + math.floor(i / 24), i % 24
        hours.time[#hours.time + 1] = string.format("2026-11-%02dT%02d:00", day, h)
        hours.temperature_2m[#hours.temperature_2m + 1] = 40 + (i % 24) * 0.4
        hours.weather_code[#hours.weather_code + 1] = i >= 24 + 5 and 61 or 2
        hours.precipitation_probability[#hours.precipitation_probability + 1] = (i * 5) % 100
        hours.is_day[#hours.is_day + 1] = (h >= 7 and h < 17) and 1 or 0
    end
    return {
        current = { time = "2026-11-07T20:15", temperature_2m = 47.6, apparent_temperature = 43.8, relative_humidity_2m = 62,
            weather_code = 2, is_day = 0, wind_speed_10m = 9.2, wind_gusts_10m = 16.8, wind_direction_10m = 310,
            pressure_msl = 1019.9 },
        hourly = hours,
        daily = { time = { "2026-11-07", "2026-11-08", "2026-11-09", "2026-11-10", "2026-11-11" },
            weather_code = { 2, 80, 3, 0, 0 }, temperature_2m_max = { 53, 53.4, 47, 51, 55 },
            temperature_2m_min = { 38, 38.2, 33, 31, 30 }, precipitation_probability_max = { 10, 60, 10, 0, 0 },
            sunrise = { "2026-11-07T06:41", "2026-11-08T06:42" }, sunset = { "2026-11-07T16:52", "2026-11-08T16:51" } },
    }
end

local w = assert(Weather.parse(sample(), "us"))
check("now rounded", w.now.temp == 48 and w.now.feels == 44 and w.now.humidity == 62 and w.now.wind == 9 and w.now.gust == 17)
check("now text night", w.now.text == "Partly cloudy" and w.now.icon == "cloud")
check("wind dir", w.now.dir == "NW")
check("pressure inHg", w.now.pressure == "30.12")
check("hi lo sun", w.hi == 53 and w.lo == 38 and w.sunrise == "6:41 AM" and w.sunset == "4:52 PM")
check("hours count", #w.hours == Weather.HOURS)
check("hours start after now", w.hours[1].label == "9 PM" and w.hours[2].label == "10" and w.hours[3].label == "11" and w.hours[4].label == "12 AM" and w.hours[5].label == "1")
check("hour temp rounded", w.hours[1].temp == math.floor(40 + 21 * 0.4 + 0.5))
check("rain_next", w.rain_next == w.hours[1].pop)
check("days are the next three", #w.days == Weather.DAYS and w.days[1].name == "SUN" and w.days[3].name == "TUE")
check("day values", w.days[1].hi == 53 and w.days[1].lo == 38 and w.days[1].icon == "rain" and w.days[1].pop == 60)
check("units kept", w.units == "us")

local m = assert(Weather.parse(sample(), "metric"))
check("metric pressure hPa", m.now.pressure == "1020" and m.units == "metric")

-- Robustness: missing and malformed data must return nil + reason, never raise.
check("nil", select(2, Weather.parse(nil, "us")) ~= nil)
check("string", Weather.parse("x", "us") == nil)
check("error body", Weather.parse({ error = true, reason = "bad" }, "us") == nil)
check("missing blocks", Weather.parse({ current = {} }, "us") == nil)
local bad = sample(); bad.current.temperature_2m = "warm"
check("non-numeric temp", Weather.parse(bad, "us") == nil)
bad = sample(); bad.current.temperature_2m = 0 / 0
check("nan temp", Weather.parse(bad, "us") == nil)
bad = sample(); bad.hourly.time = {}
check("no hours", Weather.parse(bad, "us") == nil)
bad = sample(); bad.daily.time = nil
check("no days", Weather.parse(bad, "us") == nil)
bad = sample(); bad.daily.sunrise = nil; bad.daily.sunset = nil; bad.current.pressure_msl = nil
local partial = assert(Weather.parse(bad, "us"))
check("optional fields absent", partial.sunrise == nil and partial.now.pressure == nil)
bad = sample(); bad.hourly.weather_code = nil; bad.hourly.precipitation_probability = nil; bad.hourly.is_day = nil
local nopop = assert(Weather.parse(bad, "us"))
check("hourly extras absent", nopop.hours[1].pop == nil and nopop.rain_next == nil and #nopop.hours == Weather.HOURS)
bad = sample(); bad.current.time = nil
check("no current time still parses", Weather.parse(bad, "us") ~= nil)
bad = sample(); bad.daily.temperature_2m_max[3] = "x"
check("a bad day is skipped", #assert(Weather.parse(bad, "us")).days == Weather.DAYS - 1)
local tail = sample(); for i = 1, 70 do table.remove(tail.hourly.time); table.remove(tail.hourly.temperature_2m) end
check("short forecast gives fewer hours", #assert(Weather.parse(tail, "us")).hours <= Weather.HOURS)
print(string.format("weather: %d checks passed", passed))
