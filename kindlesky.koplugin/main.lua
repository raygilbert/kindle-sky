local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local PluginShare = require("pluginshare")
local Screen = Device.screen
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Blitbuffer = require("ffi/blitbuffer")
local JSON = require("json")
local https = require("ssl.https")
local socketutil = require("socketutil")
local _ = require("gettext")

local plugin_dir = debug.getinfo(1, "S").source:match("^@(.*/)")
local Data = dofile(plugin_dir .. "data.lua")
local Visuals = dofile(plugin_dir .. "visuals.lua")
local Time = dofile(plugin_dir .. "time.lua")
local Rotation = dofile(plugin_dir .. "rotation.lua")
local Trains = dofile(plugin_dir .. "trains.lua")
local Satellites = dofile(plugin_dir .. "satellites.lua")
local W, H = Screen:getWidth(), Screen:getHeight()
local BLACK, WHITE, GRAY = Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_DARK_GRAY

-- Diagnostics: a short log so an unexpected exit leaves a trace. It holds no location data.
local DIAG_LOG = DataStorage:getSettingsDir() .. "/kindlesky_diagnostics.log"
local DIAG_MAX_BYTES = 64 * 1024

local function diag(kind, detail)
    pcall(function()
        local file = io.open(DIAG_LOG, "a")
        if not file then return end
        if file:seek("end") > DIAG_MAX_BYTES then
            file:close()
            os.remove(DIAG_LOG .. ".1")
            os.rename(DIAG_LOG, DIAG_LOG .. ".1")
            file = io.open(DIAG_LOG, "w")
            if not file then return end
        end
        file:write(os.date("%Y-%m-%d %H:%M:%S", os.time()), "  ", kind,
            detail and ("  " .. tostring(detail)) or "", "\n")
        file:close()
    end)
end

local function battery_text()
    local ok, value = pcall(function()
        local power = Device:getPowerDevice()
        return string.format("battery %d%%%s", power:getCapacity(), power:isCharging() and " (charging)" or "")
    end)
    return ok and value or "battery unknown"
end

-- Memory use of this process and the whole device, read from /proc. A steady climb before an
-- unexplained exit points at memory; a flat line points at something else ending the process.
local LOW_MEMORY_KB = 48 * 1024

local function memory_info()
    local info = {}
    pcall(function()
        for line in io.lines("/proc/self/status") do
            local rss = line:match("^VmRSS:%s+(%d+)")
            if rss then info.rss_kb = tonumber(rss) end
            local threads = line:match("^Threads:%s+(%d+)")
            if threads then info.threads = tonumber(threads) end
        end
        local free, buffers, cached
        for line in io.lines("/proc/meminfo") do
            local key, kb = line:match("^(%w+):%s+(%d+)")
            if key == "MemAvailable" then info.available_kb = tonumber(kb)
            elseif key == "MemFree" then free = tonumber(kb)
            elseif key == "Buffers" then buffers = tonumber(kb)
            elseif key == "Cached" then cached = tonumber(kb) end
        end
        info.available_kb = info.available_kb or ((free or 0) + (buffers or 0) + (cached or 0))
        local uptime = io.open("/proc/uptime", "r")
        if uptime then
            info.uptime_s = tonumber((uptime:read("*l") or ""):match("^(%d+)"))
            uptime:close()
        end
    end)
    info.lua_kb = collectgarbage("count")
    return info
end

local function memory_text(info)
    info = info or memory_info()
    local function mb(kb) return kb and string.format("%d", kb / 1024) or "?" end
    return string.format("rss %s MB, device free %s MB, lua %d KB, threads %s, uptime %s min",
        mb(info.rss_kb), mb(info.available_kb), info.lua_kb, tostring(info.threads or "?"),
        info.uptime_s and string.format("%d", info.uptime_s / 60) or "?")
end

-- KOReader exits when a scheduled task or paint raises a Lua error, which on a Kindle
-- looks like a return to the home screen. Contain the error, log it, and keep running.
local function guarded(label, fn, on_error)
    return function(...)
        local ok, err = xpcall(fn, debug.traceback, ...)
        if not ok then
            diag(label .. " error", err)
            if on_error then pcall(on_error) end
        end
    end
end

local function text(bb, value, x, y, size, max_width, bold)
    local widget = TextWidget:new {
        text = tostring(value or ""),
        face = Font:getFace("cfont", size),
        max_width = max_width or W - x - 20,
        bold = bold or false,
    }
    widget:paintTo(bb, x, y)
    widget:free()
end

local function rule(bb, y)
    bb:paintRect(24, y, W - 48, 2, BLACK)
end

local function ring(bb, cx, cy, radius, color)
    for degree = 0, 359, 2 do
        local a = math.rad(degree)
        bb:paintRect(math.floor(cx + radius * math.cos(a)), math.floor(cy + radius * math.sin(a)), 2, 2, color)
    end
end

local function line(bb, x1, y1, x2, y2, color)
    local steps = math.max(math.abs(x2 - x1), math.abs(y2 - y1))
    if steps == 0 then return end
    for step = 0, steps do
        local x = math.floor(x1 + (x2 - x1) * step / steps + 0.5)
        local y = math.floor(y1 + (y2 - y1) * step / steps + 0.5)
        bb:paintRect(x, y, 2, 2, color)
    end
end

local function age(ts)
    if not ts then return "--" end
    local seconds = math.max(0, os.time() - ts)
    return seconds < 60 and (seconds .. "s") or (math.floor(seconds / 60) .. "m")
end

local Dashboard = InputContainer:extend {}

function Dashboard:init()
    self.dimen = Geom:new { x = 0, y = 0, w = W, h = H }
    local whole = Geom:new { x = 0, y = 0, w = W, h = H }
    self.ges_events = {
        SwitchView = { GestureRange:new { ges = "tap", range = whole } },
        CloseView = { GestureRange:new { ges = "hold", range = whole } },
    }
end

function Dashboard:onSwitchView(_, ges)
    local app = self.owner
    local px, py = ges and ges.pos and ges.pos.x or 0, ges and ges.pos and ges.pos.y or 0
    local nearest, best = nil, 20 * 20
    if app.mode ~= "satellites" then
        for _, dot in ipairs(self.radar_dots or {}) do
            local d = (px - dot.x)^2 + (py - dot.y)^2
            if d < best then nearest, best = dot.index, d end
        end
    end
    if app.mode == "home" then
        if nearest then
            app.selected_index = nearest
            app.mode = "aircraft"
        elseif py >= (W > H and 402 or 625) then
            app.mode = "satellites"
        else
            app.mode = "aircraft"
        end
    elseif app.mode == "aircraft" then
        if nearest then
            app.selected_index = nearest
        elseif py < 108 then
            app.mode = "home"
        elseif px < W / 2 and app.aircraft and #app.aircraft > 0 then
            app.selected_index = (app.selected_index or 1) % #app.aircraft + 1
        else
            app.mode = "satellites"
        end
    elseif app.mode == "satellites" and app.train_provider then
        app.mode = "trains"
    else
        app.mode = "home"
    end
    if app.mode == "aircraft" and app.aircraft and app.aircraft[app.selected_index or 1] then
        app.rotation_state.last_id = Rotation.identity(app.aircraft[app.selected_index or 1], app.selected_index or 1)
    end
    app:scheduleRotation()
    UIManager:setDirty(self, "full")
    return true
end

function Dashboard:onCloseView()
    self.owner:stop()
    return true
end

function Dashboard:paintTo(bb, x, y)
    local ok, err = xpcall(function() self:paintContent(bb, x, y) end, debug.traceback)
    if ok then return end
    if err ~= self.last_paint_error then
        self.last_paint_error = err
        diag("paint error", err)
    end
    pcall(function()
        bb:paintRect(x, y, W, H, WHITE)
        text(bb, "Display error", 24, 120, 30, W - 48, true)
        text(bb, "Details: koreader/settings/kindlesky_diagnostics.log", 24, 170, 18, W - 48)
    end)
end

function Dashboard:paintContent(bb, x, y)
    local app = self.owner
    bb:paintRect(x, y, W, H, WHITE)
    text(bb, "KINDLE HORIZON", 24, 18, 34, W - 48, true)
    local clock, zone = Time.format(os.time(), "%I:%M %p", app.settings.timezone)
    text(bb, clock:gsub("^0", "") .. " " .. zone, W - 185, 25, 18, 165, true)
    local mode_name = app.mode == "home" and "AT A GLANCE" or
        (app.mode == "aircraft" and "AIRCRAFT" or (app.mode == "satellites" and "SATELLITES" or "TRAINS"))
    text(bb, "LOCAL  /  " .. mode_name, 24, 68, 20, 350)
    local air_status = (app.aircraft_error and "STALE " or "") .. age(app.aircraft_updated_at)
    local satellite_status = (app.satellite_error and "STALE " or "") .. age(app.catalog_updated_at)
    local train_status = app.train_provider and ("  RAIL " .. (app.train_error and "STALE " or "") .. age(app.train_updated_at)) or ""
    text(bb, "AIR " .. air_status .. "  SAT " .. satellite_status .. train_status,
        W > H and 418 or 285, 75, 15, W > H and 360 or 310)
    rule(bb, 103)
    self.radar_dots = {}
    if app.mode == "home" then
        self:paintHome(bb)
    elseif app.mode == "aircraft" then
        self:paintAircraft(bb)
    elseif app.mode == "trains" then
        self:paintTrains(bb)
    else
        self:paintSatellites(bb)
    end
    rule(bb, H - 71)
    local source = app.mode == "home" and "adsb.fi / CelesTrak"
        or (app.mode == "aircraft" and "https://adsb.fi" or
        (app.mode == "trains" and (app.train_provider == "septa" and "SEPTA Regional Rail API" or "Transport for London API")
        or "CelesTrak GP / approximate sky positions"))
    text(bb, source, 24, H - 58, 15)
    local hint = app.mode == "home" and "Tap radar: aircraft   Tap satellite: sky   Hold: exit"
        or (app.mode == "aircraft" and "Tap left: next   Right: satellites   Header: home"
        or (app.mode == "satellites" and app.train_provider and "Tap: trains   Hold: exit" or "Tap: home   Hold: exit"))
    text(bb, hint, 24, H - 33, 16)
end

local function trainBadge(bb, x, y, line)
    bb:paintRect(x, y, 76, 46, BLACK)
    bb:paintRect(x + 3, y + 3, 70, 40, WHITE)
    text(bb, Visuals.lineBadge(line), x + 9, y + 8, 24, 62, true)
end

function Dashboard:paintTrains(bb)
    local app, provider, trains = self.owner, self.owner.train_provider, self.owner.trains
    local wide = W > H
    local right_x, bar_w = W - 24 - 176, 176
    if provider == "septa" then
        text(bb, "SEPTA REGIONAL RAIL", 24, 126, 24, W - 48, true)
        text(bb, string.format("%d trains within %d nm  /  positions approximate", #(trains or {}),
            app.settings.radius_nm), 24, 165, 18, W - 48)
        if app.train_error then text(bb, "STALE  /  " .. app.train_error, 24, 195, 17, W - 48) end
        if not trains then
            text(bb, "Waiting for nearby trains", 24, 245, 24, W - 48)
        elseif #trains == 0 then
            text(bb, "No Regional Rail trains in range", 24, 245, 24, W - 48)
        else
            local count = math.min(#trains, wide and 4 or 6)
            for i = 1, count do
                local train, y = trains[i], 215 + (i - 1) * (wide and 75 or 85)
                trainBadge(bb, 24, y, train.line)
                text(bb, "To " .. train.destination, 116, y - 2, 23, right_x - 130, true)
                text(bb, string.format("#%s  /  %.1f nm away", train.number, train.distance_nm),
                    116, y + 28, 17, right_x - 130)
                text(bb, train.line .. (train.next_stop ~= "" and ("  /  next: " .. train.next_stop) or ""),
                    116, y + 50, 15, W - 140)
                local delay = train.delay
                text(bb, delay and (delay > 0 and (delay .. " min late") or "on time") or "delay unknown",
                    right_x, y - 2, 21, bar_w, delay ~= nil and delay > 0)
                -- Delay bar: full width is 15 minutes or more late.
                bb:paintRect(right_x, y + 30, bar_w, 12, BLACK)
                bb:paintRect(right_x + 2, y + 32, bar_w - 4, 8, WHITE)
                if delay and delay > 0 then
                    bb:paintRect(right_x + 2, y + 32, math.floor((bar_w - 4) * math.min(delay, 15) / 15), 8, BLACK)
                end
            end
        end
    else
        local stop = app.train_stop
        text(bb, "LONDON RAIL ARRIVALS", 24, 126, 24, W - 48, true)
        text(bb, stop and (stop.name .. string.format("  /  %.1f km away", stop.distance_km))
            or "Finding the nearest station", 24, 165, 19, W - 48)
        if app.train_error then text(bb, "STALE  /  " .. app.train_error, 24, 195, 17, W - 48) end
        if not trains then
            text(bb, "Waiting for arrival predictions", 24, 245, 24, W - 48)
        elseif #trains == 0 then
            text(bb, "No predicted arrivals at this station", 24, 245, 22, W - 48)
        else
            local count = math.min(#trains, wide and 5 or 7)
            for i = 1, count do
                local train, y = trains[i], 215 + (i - 1) * (wide and 61 or 70)
                trainBadge(bb, 24, y, train.line)
                text(bb, "To " .. train.destination, 116, y - 2, 22, right_x - 130, true)
                text(bb, train.line .. (train.platform ~= "" and ("  /  " .. train.platform) or ""),
                    116, y + 26, 17, right_x - 130)
                text(bb, string.format("%d min", train.minutes), right_x, y + 2, 28, bar_w, true)
            end
        end
        text(bb, "Station predictions, not train positions", 24, H - 100, 17, W - 48)
    end
end

function Dashboard:paintRadar(bb, ac, cx, cy, radius, range_nm, selected_index)
    ring(bb, cx, cy, radius, BLACK)
    ring(bb, cx, cy, math.floor(radius / 2), GRAY)
    bb:paintRect(cx - 1, cy - radius, 2, radius * 2, GRAY)
    bb:paintRect(cx - radius, cy - 1, radius * 2, 2, GRAY)
    bb:paintRect(cx - 4, cy - 4, 8, 8, BLACK)
    text(bb, "N", cx - 8, cy - radius - 26, 17, 20)
    text(bb, string.format("%g nm", range_nm / 2), cx + math.floor(radius / 2) - 23, cy + 7, 14, 54)
    text(bb, tostring(range_nm) .. " nm", cx + radius - 53, cy + 7, 15, 62)
    local function drawAircraft(i)
        local a = ac[i]
        local distance = math.min(1, a.distance_nm / range_nm)
        local bearing = math.rad(a.bearing)
        local px = math.floor(cx + math.sin(bearing) * distance * radius)
        local py = math.floor(cy - math.cos(bearing) * distance * radius)
        self.radar_dots[#self.radar_dots + 1] = { x = px, y = py, index = i }
        local selected = i == selected_index
        local size = selected and 11 or 6
        bb:paintRect(px - math.floor(size / 2), py - math.floor(size / 2), size, size, BLACK)
        if selected then
            -- Ring and callsign tie the dot to the detail panel next to the radar.
            ring(bb, px, py, 14, BLACK)
            local label = a.flight ~= "" and a.flight or (a.registration ~= "" and a.registration or a.id)
            local label_w = 9 * #label + 8
            local label_x = px > cx and (px - 19 - label_w) or (px + 19)
            bb:paintRect(label_x - 2, py - 11, label_w + 4, 20, WHITE)
            text(bb, label, label_x, py - 11, 14, label_w, true)
        end
        if a.heading then
            local head = math.rad(a.heading)
            local tipx = math.floor(px + math.sin(head) * 13)
            local tipy = math.floor(py - math.cos(head) * 13)
            line(bb, px, py, tipx, tipy, BLACK)
        end
    end
    for i = 1, math.min(#ac, 24) do
        if i ~= selected_index then drawAircraft(i) end
    end
    -- The selected aircraft goes last so nothing paints over its ring and label.
    if selected_index and ac[selected_index] then drawAircraft(selected_index) end
end

-- Heading dial for one aircraft, with the plain-language reading beside or below it.
function Dashboard:paintHeading(bb, plane, cx, cy, radius, label_x, label_y, label_w, line_h, size)
    Visuals.paintCompass(bb, cx, cy, radius, plane.heading, BLACK)
    text(bb, "N", cx - 6, cy - radius - math.floor(size * 1.5), size - 2, 20, true)
    text(bb, plane.heading and string.format("HDG %03d deg", math.floor(plane.heading + 0.5) % 360) or "HDG --",
        label_x, label_y, size, label_w, true)
    local direction, climb = Data.climb(plane.vrate_fpm)
    if climb then
        local marker = math.floor(size * 0.8)
        Visuals.paintTrend(bb, label_x, label_y + line_h + math.floor((size - marker) / 2) + 2, marker, direction, BLACK)
        text(bb, climb, label_x + marker + 6, label_y + line_h, size, label_w - marker - 6)
    end
    local motion = Data.motion(plane.heading, plane.bearing)
    if motion then text(bb, motion, label_x, label_y + 2 * line_h, size, label_w, true) end
end

-- Small sky disc for the Home view: the featured satellite is the big square, the rest are dots.
function Dashboard:paintMiniSky(bb, overhead, feature, cx, cy, radius)
    Visuals.paintCompass(bb, cx, cy, radius, nil, BLACK)
    ring(bb, cx, cy, math.floor(radius / 2), GRAY)
    bb:paintRect(cx - 1, cy - radius, 2, radius * 2, GRAY)
    bb:paintRect(cx - radius, cy - 1, radius * 2, 2, GRAY)
    text(bb, "N", cx - 6, cy - radius - 22, 14, 20, true)
    local function mark(sat, size)
        local distance = (90 - math.min(90, sat.elevation)) / 90 * radius
        local bearing = math.rad(sat.bearing)
        local px = math.floor(cx + math.sin(bearing) * distance)
        local py = math.floor(cy - math.cos(bearing) * distance)
        bb:paintRect(px - math.floor(size / 2), py - math.floor(size / 2), size, size, BLACK)
    end
    for i = 1, math.min(#overhead, 12) do
        if overhead[i] ~= feature then mark(overhead[i], 5) end
    end
    if feature then
        mark(feature, 13)
    end
end

function Dashboard:paintHome(bb)
    local app, ac = self.owner, self.owner.aircraft
    local landscape = W > H
    local first = ac and ac[1]
    local radar_x, radar_y, radar_r = landscape and 192 or math.floor(W / 2), landscape and 266 or 270, landscape and 110 or 115
    text(bb, ac and ("NEARBY  /  " .. #ac .. " AIRCRAFT") or "NEARBY  /  UNAVAILABLE",
        24, 122, 21, landscape and 350 or W - 48, true)
    self:paintRadar(bb, ac or {}, radar_x, radar_y, radar_r, app.settings.radius_nm, 1)
    local tx, top, column_width = landscape and 411 or 24, landscape and 128 or 412, landscape and 355 or W - 48
    if landscape then bb:paintRect(392, 121, 2, 270, GRAY) end
    local feature_label = first and (first.emergency and "EMERGENCY" or (first.military and "MILITARY"
        or (first.rare and "UNUSUAL" or "FEATURED"))) or "FEATURED AIRCRAFT"
    if first then feature_label = feature_label .. "  /  " .. select(2, Visuals.aircraftKind(first)):upper() end
    text(bb, (app.aircraft_error and "STALE / " or "") .. feature_label, tx, top, 18, column_width, true)
    if first then
        local name = first.flight ~= "" and first.flight or (first.registration ~= "" and first.registration or first.id)
        local text_w = landscape and 235 or 390
        text(bb, name, tx, top + 37, landscape and 38 or 34, text_w, true)
        text(bb, (first.model ~= "" and first.model or "Unknown type") .. "  " .. first.registration,
            tx, top + 89, 21, text_w)
        text(bb, string.format("%.1f nm  /  %03d deg", first.distance_nm, first.bearing),
            tx, top + 128, 22, text_w)
        local altitude = first.altitude_ft and (tostring(math.floor(first.altitude_ft + 0.5)) .. " ft") or "-- ft"
        local speed = first.speed_kt and (tostring(math.floor(first.speed_kt + 0.5)) .. " kt") or "-- kt"
        text(bb, altitude .. "  /  " .. speed, tx, top + 166, 21, text_w)
        if landscape then
            self:paintHeading(bb, first, 705, 213, 46, 636, 272, 140, 22, 16)
            local nearest = first
            for _, plane in ipairs(ac) do
                if plane.distance_nm < nearest.distance_nm then nearest = plane end
            end
            if nearest ~= first then
                local nearest_name = nearest.flight ~= "" and nearest.flight or nearest.registration
                text(bb, string.format("Nearest: %s  %.1f nm", nearest_name, nearest.distance_nm),
                    tx, top + 210, 17, column_width)
            end
        else
            self:paintHeading(bb, first, 508, 495, 36, 436, 540, 150, 20, 16)
        end
    else
        text(bb, app.aircraft_error or "No aircraft in range", tx, top + 58, 21, column_width)
    end
    local divider = landscape and 404 or 631
    rule(bb, divider)
    local overhead = app.satellites or {}
    local feature = Satellites.feature(overhead)
    text(bb, string.format("SATELLITES ABOVE 10 DEG  /  %d", #overhead),
        24, divider + 17, 19, W - 48, true)
    if feature then
        text(bb, feature.name, 24, divider + 48, landscape and 28 or 23,
            landscape and 590 or 400, true)
        text(bb, string.format("%03d deg direction  /  %.0f deg high", feature.bearing, feature.elevation),
            24, divider + (landscape and 86 or 76), landscape and 20 or 17,
            landscape and 590 or 410)
        if landscape then
            self:paintMiniSky(bb, overhead, feature, 705, 474, 44)
        else
            self:paintMiniSky(bb, overhead, feature, 520, 687, 34)
        end
    else
        text(bb, app.satellite_error or "No catalog satellites high in the sky", 24,
            divider + 53, landscape and 21 or 18, W - 48)
    end
end

function Dashboard:paintAircraft(bb)
    local app, ac = self.owner, self.owner.aircraft
    if W > H then return self:paintAircraftLandscape(bb) end
    if not ac then
        text(bb, "AIRCRAFT DATA UNAVAILABLE", 24, 135, 25, W - 48, true)
        text(bb, app.aircraft_error or "Check Wi-Fi", 24, 180, 19)
        return
    end
    text(bb, string.format("%d aircraft within %d nm", #ac, app.settings.radius_nm), 24, 126, 22)
    local first = ac[app.selected_index or 1] or ac[1]
    if first then
        local tag = first.emergency and "EMERGENCY" or (first.military and "REPORTED MILITARY" or (first.rare and "RARE AIRCRAFT" or "NEAREST"))
        text(bb, tag .. "  /  " .. (app.selected_index or 1) .. " OF " .. #ac, 24, 178, 18, W - 48, true)
        text(bb, first.flight ~= "" and first.flight or (first.registration ~= "" and first.registration or first.id), 24, 211, 40, W - 48, true)
        text(bb, first.description ~= "" and first.description or select(2, Visuals.aircraftKind(first)), 24, 266, 20, W - 48)
        text(bb, (first.model ~= "" and first.model or "Unknown type") .. "  " .. first.registration, 24, 300, 19)
        text(bb, string.format("%.1f nm  /  %03d deg", first.distance_nm, first.bearing), 24, 335, 22)
        local altitude = first.altitude_ft and (tostring(math.floor(first.altitude_ft + 0.5)) .. " ft") or "-- ft"
        local speed = first.speed_kt and (tostring(math.floor(first.speed_kt + 0.5)) .. " kt") or "-- kt"
        text(bb, altitude .. "  /  " .. speed, 24, 374, 20)
    else
        text(bb, "No aircraft in range", 24, 210, 30, W - 48, true)
    end
    rule(bb, 412)
    if first then
        self:paintHeading(bb, first, 90, 497, 44, 160, 467, 400, 26, 20)
    end
    text(bb, "RADAR", 24, 556, 17, W - 48, true)
    self:paintRadar(bb, ac, math.floor(W / 2), 637, 56, app.settings.radius_nm, app.selected_index or 1)
end

function Dashboard:paintAircraftLandscape(bb)
    local app, ac = self.owner, self.owner.aircraft
    if not ac then
        text(bb, "AIRCRAFT DATA UNAVAILABLE", 24, 145, 25, 360, true)
        text(bb, app.aircraft_error or "Check Wi-Fi", 24, 190, 19, 360)
        return
    end
    text(bb, string.format("%d aircraft within %d nm", #ac, app.settings.radius_nm), 24, 126, 22, 360)
    local first = ac[app.selected_index or 1] or ac[1]
    if first then
        local tag = first.emergency and "EMERGENCY" or (first.military and "REPORTED MILITARY" or (first.rare and "RARE AIRCRAFT" or "NEAREST"))
        text(bb, tag .. "  /  " .. (app.selected_index or 1) .. " OF " .. #ac, 24, 177, 18, 350, true)
        text(bb, first.flight ~= "" and first.flight or (first.registration ~= "" and first.registration or first.id), 24, 208, 38, 350, true)
        text(bb, first.description ~= "" and first.description or select(2, Visuals.aircraftKind(first)), 24, 259, 20, 350)
        text(bb, (first.model ~= "" and first.model or "Unknown type") .. "  " .. first.registration, 24, 292, 19, 350)
        text(bb, string.format("%.1f nm  /  %03d deg", first.distance_nm, first.bearing), 24, 328, 22, 350)
        local altitude = first.altitude_ft and (tostring(math.floor(first.altitude_ft + 0.5)) .. " ft") or "-- ft"
        local speed = first.speed_kt and (tostring(math.floor(first.speed_kt + 0.5)) .. " kt") or "-- kt"
        text(bb, altitude .. "  /  " .. speed, 24, 365, 20, 350)
    else
        text(bb, "No aircraft in range", 24, 210, 27, 350, true)
    end
    bb:paintRect(391, 122, 2, 383, GRAY)
    text(bb, "WHICH WAY IT IS GOING", 421, 126, 19, 350, true)
    if first then
        self:paintHeading(bb, first, 480, 238, 52, 560, 198, 210, 28, 19)
    end
    text(bb, "NEARBY RADAR", 421, 306, 18, 350, true)
    self:paintRadar(bb, ac, 592, 425, 64, app.settings.radius_nm, app.selected_index or 1)
end

function Dashboard:paintSatelliteSky(bb, satellites, cx, cy, radius)
    ring(bb, cx, cy, radius, BLACK)
    ring(bb, cx, cy, math.floor(radius / 2), GRAY)
    bb:paintRect(cx - 1, cy - radius, 2, radius * 2, GRAY)
    bb:paintRect(cx - radius, cy - 1, radius * 2, 2, GRAY)
    text(bb, "N", cx - 8, cy - radius - 27, 18, 20, true)
    text(bb, "E", cx + radius + 9, cy - 10, 18, 20, true)
    text(bb, "S", cx - 8, cy + radius + 6, 18, 20, true)
    text(bb, "W", cx - radius - 25, cy - 10, 18, 20, true)
    for i = 1, math.min(#satellites, 12) do
        local sat = satellites[i]
        local distance = (90 - math.min(90, sat.elevation)) / 90 * radius
        local bearing = math.rad(sat.bearing)
        local px = math.floor(cx + math.sin(bearing) * distance)
        local py = math.floor(cy - math.cos(bearing) * distance)
        local size = sat.iss and 12 or (i <= 3 and 9 or 5)
        bb:paintRect(px - math.floor(size / 2), py - math.floor(size / 2), size, size, BLACK)
    end
end

function Dashboard:paintSatellites(bb)
    local app = self.owner
    local overhead = app.satellites or {}
    local featured = Satellites.feature(overhead)
    local wide = W > H
    local names = {}
    if featured then names[#names + 1] = featured end
    for _, sat in ipairs(overhead) do
        if sat ~= featured and #names < 3 then names[#names + 1] = sat end
    end
    text(bb, string.format("%d SATELLITES ABOVE 10 DEG", #overhead), 24, 126,
        wide and 23 or 22, wide and 355 or 400, true)
    if not app.catalog then
        text(bb, app.satellite_error or "Waiting for orbital data", 24, 175, 21,
            wide and 350 or W - 48)
    elseif #overhead == 0 then
        text(bb, app.satellite_error or "None of the tracked satellites is high in the sky", 24, 175,
            wide and 19 or 20, wide and 350 or W - 48)
    end
    for i, sat in ipairs(names) do
        local y = (wide and 184 or 206) + (i - 1) * (wide and 82 or 77)
        text(bb, (sat.iss and "ISS  /  " or "") .. sat.name, 24, y,
            wide and 23 or 22, wide and 345 or W - 48, true)
        text(bb, string.format("%03d deg direction  /  %.0f deg high  /  %.0f km away",
            sat.bearing, sat.elevation, sat.range_km), 24, y + 31,
            wide and 17 or 18, wide and 345 or W - 48)
        local visibility = sat.possible_visible and "POSSIBLY VISIBLE / weather unknown"
            or (sat.sunlit and "DAYLIGHT OR TWILIGHT SKY" or "IN EARTH SHADOW")
        text(bb, visibility, 24, y + 54, 15, wide and 345 or W - 48)
    end
    if wide then
        bb:paintRect(391, 122, 2, 383, GRAY)
        text(bb, "YOUR SKY NOW", 432, 127, 20, 340, true)
        self:paintSatelliteSky(bb, overhead, 592, 297, 112)
        text(bb, "Approximate positions / visibility is an estimate", 24, 485, 16, 590)
    else
        rule(bb, 453)
        text(bb, "YOUR SKY NOW", 24, 471, 20, W - 48, true)
        self:paintSatelliteSky(bb, overhead, math.floor(W / 2), 615, 85)
        text(bb, "Approximate positions / visibility is an estimate", 24, 707, 15, W - 48)
    end
end

local Sky = WidgetContainer:extend { name = "kindlesky", is_doc_only = false }
-- Public example location: New York City. Set your own location in the plugin menu.
local defaults = { lat = 40.7128, lon = -74.0060, radius_nm = 40, refresh_seconds = 120,
    landscape = true, auto_rotate = true, timezone = "auto" }
local ROTATE_SECONDS = 90
local CATALOG_SECONDS = 2 * 60 * 60
local MAX_RESPONSE_BYTES = 2 * 1024 * 1024
local CA_BUNDLE = DataStorage:getFullDataDir() .. "/data/ca-bundle.crt"

local function get_json(url)
    local chunks = {}
    local ca_file = io.open(CA_BUNDLE, "rb")
    if not ca_file then return nil, "CA bundle unavailable" end
    ca_file:close()
    local bytes = 0
    socketutil:set_timeout(8, 15)
    local table_sink = socketutil.table_sink(chunks)
    local function limited_sink(chunk, err)
        if chunk then
            bytes = bytes + #chunk
            if bytes > MAX_RESPONSE_BYTES then return nil, "Response too large" end
        end
        return table_sink(chunk, err)
    end
    local called, ok, code = pcall(https.request, {
        url = url,
        method = "GET",
        sink = limited_sink,
        headers = { ["User-Agent"] = "KindleSky/0.3 (personal e-ink display)" },
        protocol = "any",
        options = { "all", "no_sslv2", "no_sslv3", "no_tlsv1" },
        verify = "peer",
        cafile = CA_BUNDLE,
        redirect = false,
    })
    socketutil:reset_timeout()
    if not called then return nil, "Network request failed" end
    if ok ~= 1 then return nil, tostring(code or "Request failed") end
    if code ~= 200 then return nil, "HTTP " .. tostring(code) end
    local valid, value = pcall(JSON.decode, table.concat(chunks))
    if not valid or type(value) ~= "table" then return nil, "Invalid response" end
    return value
end

function Sky:init()
    self.settings_file = LuaSettings:open(DataStorage:getSettingsDir() .. "/kindlesky.lua")
    self.catalog_file = LuaSettings:open(DataStorage:getSettingsDir() .. "/kindlesky_catalog.lua")
    self.settings = self.settings_file:readSetting("settings") or defaults
    self.catalog = self.catalog_file:readSetting("catalog")
    if type(self.catalog) ~= "table" then self.catalog = nil end
    self.catalog_updated_at = self.catalog_file:readSetting("updated_at")
    self.catalog_checked_at = self.catalog_file:readSetting("checked_at")
    self.catalog_halted = self.catalog_file:readSetting("halted") == true
    if self.settings.landscape == nil then self.settings.landscape = true end
    if self.settings.auto_rotate == nil then self.settings.auto_rotate = true end
    if not Time.isValidZone(self.settings.timezone) then self.settings.timezone = "auto" end
    self.mode = "home"
    self.selected_index = 1
    self.rotation_state = {}
    self.alerted_emergency_ids = {}
    self.running = false
    self.refresh_task = guarded("refresh", function() self:refresh() end)
    self.rotate_task = guarded("rotate", function() self:rotateView() end,
        function() self:scheduleRotation() end)
    self.ui.menu:registerToMainMenu(self)
end

function Sky:saveSettings()
    self.settings_file:saveSetting("settings", self.settings)
    self.settings_file:flush()
end

function Sky:saveCatalog()
    self.catalog_file:saveSetting("catalog", self.catalog)
    self.catalog_file:saveSetting("updated_at", self.catalog_updated_at)
    self.catalog_file:saveSetting("checked_at", self.catalog_checked_at)
    self.catalog_file:saveSetting("halted", self.catalog_halted or false)
    self.catalog_file:flush()
end

function Sky:setKeepAwake(enabled)
    if not Device:isKindle() then return end
    if enabled then
        if self.keep_awake_active then return end
        self.previous_keepalive = PluginShare.keepalive
        self.previous_pause_auto_suspend = PluginShare.pause_auto_suspend
        if not PluginShare.keepalive then
            local result = os.execute("lipc-set-prop com.lab126.powerd preventScreenSaver 1")
            self.keep_awake_applied = result == 0 or result == true
        end
        if self.keep_awake_applied or self.previous_keepalive then
            -- KOReader's AutoSuspend plugin uses these flags for its own timer.
            PluginShare.keepalive = true
            PluginShare.pause_auto_suspend = true
            self.keep_awake_active = true
        end
    elseif self.keep_awake_active then
        PluginShare.keepalive = self.previous_keepalive
        PluginShare.pause_auto_suspend = self.previous_pause_auto_suspend
        if self.keep_awake_applied and not PluginShare.keepalive then
            os.execute("lipc-set-prop com.lab126.powerd preventScreenSaver 0")
        end
        self.keep_awake_applied = false
        self.keep_awake_active = false
    end
end

function Sky:scheduleRotation()
    UIManager:unschedule(self.rotate_task)
    if self.running and self.settings.auto_rotate then
        UIManager:scheduleIn(ROTATE_SECONDS, self.rotate_task)
    end
end

function Sky:rotateView()
    if not self.running or not self.settings.auto_rotate then return end
    local previous_mode = self.mode
    local now = os.time()
    if self.emergency_hold_until and now < self.emergency_hold_until then
        self.mode = "aircraft"
    elseif self.mode == "home" then
        if self.aircraft and #self.aircraft > 0 then
            self.selected_index, self.rotation_state = Rotation.choose(self.aircraft, self.rotation_state)
            self.mode = "aircraft"
        else
            self.mode = "satellites"
        end
    elseif self.mode == "aircraft" then
        self.mode = "satellites"
    elseif self.mode == "satellites" and self.train_provider then
        self.mode = "trains"
    else
        self.mode = "home"
    end
    if self.mode ~= previous_mode then
        self.rotation_count = (self.rotation_count or 0) + 1
        if self.dashboard then
            UIManager:setDirty(self.dashboard, self.rotation_count % 6 == 0 and "full" or "ui")
        end
    end
    self:scheduleRotation()
end

function Sky:start()
    if self.running then return end
    self.running = true
    self.refresh_ticks = 0
    diag("started", battery_text())
    self.previous_rotation = Screen:getRotationMode()
    local rotation = self.settings.landscape and Screen.DEVICE_ROTATED_COUNTER_CLOCKWISE or Screen.DEVICE_ROTATED_UPRIGHT
    if self.previous_rotation ~= rotation then Screen:setRotationMode(rotation) end
    W, H = Screen:getWidth(), Screen:getHeight()
    self.mode = "home"
    self.selected_index = 1
    self.rotation_state = {}
    self.alerted_emergency_ids = {}
    self.emergency_hold_until = nil
    self.aircraft_error = "Waiting for Wi-Fi"
    self.satellite_error = self.catalog and nil or "Waiting for orbital data"
    self.train_provider = Trains.provider(self.settings.lat, self.settings.lon)
    self.train_error = self.train_provider and "Waiting for Wi-Fi" or nil
    self.dashboard = Dashboard:new { owner = self }
    UIManager:show(self.dashboard)
    UIManager:preventStandby()
    self:setKeepAwake(true)
    self:scheduleRotation()
    self.refresh_task()
end

function Sky:stop()
    if not self.running then return end
    self.running = false
    diag("stopped", ((debug.traceback("stop called from:", 2):gsub("%s*\n%s*", " | ")):sub(1, 400))
        .. "  " .. battery_text())
    UIManager:unschedule(self.refresh_task)
    UIManager:unschedule(self.rotate_task)
    self:setKeepAwake(false)
    UIManager:allowStandby()
    if self.dashboard then UIManager:close(self.dashboard) end
    self.dashboard = nil
    if self.previous_rotation and Screen:getRotationMode() ~= self.previous_rotation then
        Screen:setRotationMode(self.previous_rotation)
    end
    W, H = Screen:getWidth(), Screen:getHeight()
    self.previous_rotation = nil
    UIManager:setDirty("all", "full")
end

function Sky:refresh()
    if not self.running then return end
    UIManager:unschedule(self.refresh_task)
    UIManager:scheduleIn(self.settings.refresh_seconds, self.refresh_task)
    self.refresh_ticks = (self.refresh_ticks or 0) + 1
    if self.refresh_ticks % 15 == 1 then
        diag("heartbeat", string.format("tick %d, %s, wifi %s, %s", self.refresh_ticks, battery_text(),
            NetworkMgr:isConnected() and "up" or "down", memory_text()))
    elseif self.refresh_ticks % 5 == 0 then
        -- Every ten minutes while free memory is low, so the minutes before a kill are on record.
        local info = memory_info()
        if info.available_kb and info.available_kb < LOW_MEMORY_KB then
            diag("low memory", memory_text(info))
        end
    end
    self.satellites = self.catalog and Satellites.overhead(self.catalog, os.time(),
        self.settings.lat, self.settings.lon, 10) or nil
    if self.catalog_updated_at and os.time() - self.catalog_updated_at > 3 * 86400 then
        self.satellite_error = "Orbital data expired"
    end
    if not NetworkMgr:isConnected() then
        self.aircraft_error = "Wi-Fi offline"
        self.satellite_error = "Wi-Fi offline"
        if self.train_provider then self.train_error = "Wi-Fi offline" end
        if not self.aircraft_updated_at or os.time() - self.aircraft_updated_at > 600 then self.aircraft = nil end
        if not self.train_updated_at or os.time() - self.train_updated_at > 600 then self.trains = nil end
        if self.dashboard then UIManager:setDirty(self.dashboard, "ui") end
    end
    NetworkMgr:runWhenConnected(function()
        guarded("data update", function() self:refreshData() end, function()
            if self.dashboard then UIManager:setDirty(self.dashboard, "ui") end
        end)()
        -- TLS contexts hold native memory the Lua collector does not count, so collect after each
        -- round of requests instead of waiting for Lua's own heap to grow.
        collectgarbage("collect")
        NetworkMgr:afterWifiAction()
    end)
end

function Sky:refreshData()
    if not self.running then return end
    local emergency_preempted = false
    local lat, lon = self.settings.lat, self.settings.lon
    local aircraft_url = string.format("https://opendata.adsb.fi/api/v3/lat/%.4f/lon/%.4f/dist/%d", lat, lon, self.settings.radius_nm)
    local aircraft_response, aircraft_error = get_json(aircraft_url)
    if aircraft_response then
        local selected = self.aircraft and self.aircraft[self.selected_index]
        local selected_id = selected and selected.id
        self.aircraft = Data.aircraft(aircraft_response, lat, lon, self.settings.radius_nm)
        self.aircraft_updated_at = os.time()
        self.aircraft_error = nil
        self.selected_index = 1
        if selected_id then
            for i, plane in ipairs(self.aircraft) do
                if plane.id == selected_id then self.selected_index = i; break end
            end
        end
        for i, plane in ipairs(self.aircraft) do
            if plane.emergency then
                local identity = Rotation.identity(plane, i)
                if not self.alerted_emergency_ids[identity] then
                    self.alerted_emergency_ids[identity] = true
                    if not emergency_preempted then
                        self.selected_index = i
                        self.rotation_state.last_id = identity
                        self.rotation_state.last_priority_id = identity
                        self.mode = "aircraft"
                        self.emergency_hold_until = os.time() + ROTATE_SECONDS
                        self:scheduleRotation()
                        emergency_preempted = true
                    end
                end
            end
        end
    else
        self.aircraft_error = aircraft_error or "Aircraft data unavailable"
        if not self.aircraft_updated_at or os.time() - self.aircraft_updated_at > 600 then self.aircraft = nil end
    end
    if not self.catalog_halted and (not self.catalog_checked_at
        or os.time() - self.catalog_checked_at >= CATALOG_SECONDS) then
        self.catalog_checked_at = os.time()
        local response, request_error = get_json("https://celestrak.org/NORAD/elements/gp.php?GROUP=VISUAL&FORMAT=JSON")
        if response then
            local catalog = Satellites.parse(response, os.time())
            local has_iss = false
            for _, sat in ipairs(catalog or {}) do
                if sat.id == 25544 then has_iss = true; break end
            end
            if catalog and not has_iss then
                local iss_response, iss_error = get_json("https://celestrak.org/NORAD/elements/gp.php?CATNR=25544&FORMAT=JSON")
                if iss_response then
                    for _, sat in ipairs(Satellites.parse(iss_response, os.time()) or {}) do
                        catalog[#catalog + 1] = sat
                    end
                elseif iss_error and iss_error:match("^HTTP ") then
                    self.catalog_halted = true
                end
            end
            if catalog and #catalog > 0 then
                self.catalog, self.catalog_updated_at = catalog, os.time()
                self.satellite_error = nil
            else
                self.satellite_error = "Orbital catalog unavailable"
            end
        else
            self.satellite_error = request_error or "Orbital catalog unavailable"
            if request_error and request_error:match("^HTTP ") then
                self.catalog_halted = true
            end
        end
        self:saveCatalog()
    end
    self.satellites = self.catalog and Satellites.overhead(self.catalog, os.time(), lat, lon, 10) or nil
    if self.train_provider == "septa" then
        local response, request_error = get_json("https://www3.septa.org/api/TrainView/index.php")
        if response then
            self.trains = Trains.septa(response, lat, lon, self.settings.radius_nm)
            self.train_updated_at, self.train_error = os.time(), nil
        else
            self.train_error = request_error or "Train data unavailable"
        end
    elseif self.train_provider == "tfl" then
        if not self.train_stop and (not self.train_stop_checked_at or os.time() - self.train_stop_checked_at > 3600) then
            local stops, request_error = get_json(Trains.stopUrl(lat, lon))
            self.train_stop_checked_at = os.time()
            self.train_stop = stops and Trains.closestStop(stops, lat, lon) or nil
            if not self.train_stop then self.train_error = request_error or "No rail station within 1.5 km" end
        end
        if self.train_stop then
            local arrivals, request_error = get_json("https://api.tfl.gov.uk/StopPoint/" .. self.train_stop.id .. "/Arrivals")
            if arrivals then
                self.trains = Trains.tfl(arrivals)
                self.train_updated_at, self.train_error = os.time(), nil
            else
                self.train_error = request_error or "Arrival predictions unavailable"
            end
        end
    end
    if self.train_error and (not self.train_updated_at or os.time() - self.train_updated_at > 600) then
        self.trains = nil
    end
    self.refresh_count = (self.refresh_count or 0) + 1
    if self.dashboard then UIManager:setDirty(self.dashboard, self.refresh_count % 30 == 0 and "full" or "ui") end
end

function Sky:onSuspend()
    diag("suspend", battery_text())
    UIManager:unschedule(self.refresh_task)
    UIManager:unschedule(self.rotate_task)
end

function Sky:onResume()
    diag("resume", battery_text())
    if self.running then
        self:scheduleRotation()
        self.refresh_task()
    end
end

function Sky:onCloseWidget()
    self:stop()
end

function Sky:configure()
    local dialog
    dialog = MultiInputDialog:new {
        title = _("Kindle Horizon location and refresh"),
        fields = {
            { text = tostring(self.settings.lat), hint = _("Latitude"), input_type = "number" },
            { text = tostring(self.settings.lon), hint = _("Longitude"), input_type = "number" },
            { text = tostring(self.settings.radius_nm), hint = _("Radius in nautical miles"), input_type = "number" },
            { text = tostring(self.settings.refresh_seconds), hint = _("Refresh seconds"), input_type = "number" },
        },
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Save"), callback = function()
                local fields = dialog:getFields()
                local lat, lon = tonumber(fields[1]), tonumber(fields[2])
                local radius, interval = tonumber(fields[3]), tonumber(fields[4])
                if not lat or not lon or lat < -90 or lat > 90 or lon < -180 or lon > 180
                    or not radius or radius < 1 or radius > 250 or not interval or interval < 60 then
                    UIManager:show(InfoMessage:new { text = _("Check coordinates, radius (1–250), and refresh (60+ seconds).") })
                    return
                end
                self.settings = { lat = lat, lon = lon, radius_nm = math.floor(radius),
                    refresh_seconds = math.floor(interval), landscape = self.settings.landscape,
                    auto_rotate = self.settings.auto_rotate, timezone = self.settings.timezone }
                self.train_provider = Trains.provider(lat, lon)
                self.train_stop, self.train_stop_checked_at = nil, nil
                self.trains, self.train_updated_at = nil, nil
                self.train_error = self.train_provider and "Waiting for Wi-Fi" or nil
                self.satellites = self.catalog and Satellites.overhead(self.catalog, os.time(), lat, lon, 10) or nil
                if not self.train_provider and self.mode == "trains" then self.mode = "home" end
                self:saveSettings()
                UIManager:close(dialog)
                if self.running then self.refresh_task() end
            end },
        } },
    }
    UIManager:show(dialog)
end

function Sky:addToMainMenu(menu_items)
    local timezone_items = {}
    for zone_index = 1, #Time.zones do
        local zone = Time.zones[zone_index]
        timezone_items[#timezone_items + 1] = {
            text = _(zone.label),
            checked_func = function() return self.settings.timezone == zone.id end,
            callback = function()
                self.settings.timezone = zone.id
                self:saveSettings()
                if self.dashboard then UIManager:setDirty(self.dashboard, "full") end
            end,
        }
    end
    menu_items.kindlesky = {
        text = _("Kindle Horizon"),
        sorting_hint = "tools",
        sub_item_table = {
            { text = _("Start display"), callback = function() self:start() end },
            { text = _("Stop display"), callback = function() self:stop() end },
            { text = _("Landscape display"), checked_func = function() return self.settings.landscape end,
              callback = function() self.settings.landscape = true; self:saveSettings() end },
            { text = _("Portrait display"), checked_func = function() return not self.settings.landscape end,
              callback = function() self.settings.landscape = false; self:saveSettings() end },
            { text = _("Auto-cycle views (90 s)"), checked_func = function() return self.settings.auto_rotate end,
              callback = function()
                  self.settings.auto_rotate = not self.settings.auto_rotate
                  self:saveSettings()
                  self:scheduleRotation()
              end },
            { text = _("Set location and refresh"), callback = function() self:configure() end },
            { text = _("Retry satellite catalog"), callback = function()
                  self.catalog_halted, self.catalog_checked_at = nil, nil
                  self:saveCatalog()
                  if self.running then self.refresh_task() end
              end },
            { text = _("Show nearby trains"), enabled_func = function()
                  return Trains.provider(self.settings.lat, self.settings.lon) ~= nil
              end, callback = function()
                  if not self.running then self:start() end
                  self.mode = "trains"
                  self:scheduleRotation()
                  if self.dashboard then UIManager:setDirty(self.dashboard, "full") end
              end },
            { text = _("Time zone"), sub_item_table = timezone_items },
        },
    }
end

return Sky
