-- KOReader can inherit UTC even when the Kindle's native clock shows local time.
-- Keep a portable fallback for North American zones instead of changing process TZ.
local Time = {}

Time.zones = {
    { id = "auto", label = "Auto (device, then Eastern)" },
    { id = "device", label = "Device time zone" },
    { id = "America/New_York", label = "Eastern" },
    { id = "America/Chicago", label = "Central" },
    { id = "America/Denver", label = "Mountain" },
    { id = "America/Los_Angeles", label = "Pacific" },
    { id = "America/Anchorage", label = "Alaska" },
    { id = "America/Phoenix", label = "Arizona" },
    { id = "Pacific/Honolulu", label = "Hawaii" },
    { id = "UTC", label = "UTC" },
}

local zone_rules = {
    ["America/New_York"] = { -5, "EST", "EDT" },
    ["America/Chicago"] = { -6, "CST", "CDT" },
    ["America/Denver"] = { -7, "MST", "MDT" },
    ["America/Los_Angeles"] = { -8, "PST", "PDT" },
    ["America/Anchorage"] = { -9, "AKST", "AKDT" },
    ["America/Phoenix"] = { -7, "MST" },
    ["Pacific/Honolulu"] = { -10, "HST" },
    UTC = { 0, "UTC" },
}

local month_offsets = {0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4}

local function weekday(year, month, day)
    if month < 3 then year = year - 1 end
    return (year + math.floor(year / 4) - math.floor(year / 100)
        + math.floor(year / 400) + month_offsets[month] + day) % 7
end

local function uses_daylight(timestamp, base_offset)
    local utc = os.date("!*t", timestamp)
    local march_sunday = 8 + (7 - weekday(utc.year, 3, 1)) % 7
    local november_sunday = 1 + (7 - weekday(utc.year, 11, 1)) % 7
    -- US daylight time starts at 02:00 standard time and ends at 02:00 daylight time.
    local march_start = 2 - base_offset
    local november_end = 2 - (base_offset + 1)
    if utc.month > 3 and utc.month < 11 then return true end
    if utc.month == 3 then
        return utc.day > march_sunday or utc.day == march_sunday and utc.hour >= march_start
    end
    if utc.month == 11 then
        return utc.day < november_sunday or utc.day == november_sunday and utc.hour < november_end
    end
    return false
end

local function device_zone(timestamp)
    local zone = os.date("%Z", timestamp)
    if not zone or zone == "" then zone = os.date("%z", timestamp) end
    return zone ~= "" and zone or "LOCAL"
end

function Time.isValidZone(zone)
    return zone == "auto" or zone == "device" or zone_rules[zone] ~= nil
end

function Time.format(timestamp, format, selected_zone)
    local zone = selected_zone or "auto"
    if zone == "auto" then
        local device_name = device_zone(timestamp)
        local device_offset = os.date("%z", timestamp)
        -- Some Kindle launchers leave KOReader in UTC despite the native clock.
        zone = (device_name == "UTC" or device_name == "GMT" or device_offset == "+0000")
            and "America/New_York" or "device"
    end
    if zone == "device" then
        return os.date(format, timestamp), device_zone(timestamp)
    end
    local rule = zone_rules[zone] or zone_rules["America/New_York"]
    local daylight = rule[3] and uses_daylight(timestamp, rule[1])
    local offset = rule[1] + (daylight and 1 or 0)
    return os.date("!" .. format, timestamp + offset * 3600), daylight and rule[3] or rule[2]
end

return Time
