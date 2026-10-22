-- Format the display's clock and ISS pass times for Eastern time.
-- Kindle/KOReader may run with TZ=UTC even when the user's wall clock is Eastern.
local Time = {}

local month_offsets = {0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4}

local function weekday(year, month, day)
    if month < 3 then year = year - 1 end
    return (year + math.floor(year / 4) - math.floor(year / 100)
        + math.floor(year / 400) + month_offsets[month] + day) % 7
end

local function eastern_offset(timestamp)
    local utc = os.date("!*t", timestamp)
    local month, day, hour = utc.month, utc.day, utc.hour
    local march_sunday = 8 + (7 - weekday(utc.year, 3, 1)) % 7
    local november_sunday = 1 + (7 - weekday(utc.year, 11, 1)) % 7
    local summer = month > 3 and month < 11
        or month == 3 and (day > march_sunday or day == march_sunday and hour >= 7)
        or month == 11 and (day < november_sunday or day == november_sunday and hour < 6)
    return summer and -4 * 3600 or -5 * 3600, summer and "EDT" or "EST"
end

function Time.formatEastern(timestamp, format)
    local offset, zone = eastern_offset(timestamp)
    return os.date("!" .. format, timestamp + offset), zone
end

return Time
