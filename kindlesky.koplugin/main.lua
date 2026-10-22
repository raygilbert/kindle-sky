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
local W, H = Screen:getWidth(), Screen:getHeight()
local BLACK, WHITE, GRAY = Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_DARK_GRAY

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

local function pass_time(ts, timezone)
    if not ts then return "--" end
    local display, zone = Time.format(ts, "%a %I:%M %p", timezone)
    return display:gsub(" 0", " ") .. " " .. zone
end

local function pass_headline(pass, timezone)
    if pass.active then return "NOW  /  " .. pass_time(pass.start, timezone) end
    if pass.minutes <= 60 then return "IN " .. pass.minutes .. " MIN  /  " .. pass_time(pass.start, timezone) end
    return pass_time(pass.start, timezone)
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
    if app.mode ~= "iss" then
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
            app.mode = "iss"
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
            app.mode = "iss"
        end
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
    local app = self.owner
    bb:paintRect(x, y, W, H, WHITE)
    text(bb, "KINDLE SKY", 24, 18, 34, W - 48, true)
    local clock, zone = Time.format(os.time(), "%I:%M %p", app.settings.timezone)
    text(bb, clock:gsub("^0", "") .. " " .. zone, W - 185, 25, 18, 165, true)
    local mode_name = app.mode == "home" and "AT A GLANCE" or (app.mode == "aircraft" and "AIRCRAFT" or "ISS")
    text(bb, "LOCAL  /  " .. mode_name, 24, 68, 20, 350)
    local air_status = (app.aircraft_error and "STALE " or "") .. age(app.aircraft_updated_at)
    local iss_status = (app.iss_error and "STALE " or "") .. age(app.iss_updated_at)
    text(bb, "AIR " .. air_status .. "  ISS " .. iss_status, W > H and 465 or 310, 75, 15, W > H and 310 or 280)
    rule(bb, 103)
    self.radar_dots = {}
    if app.mode == "home" then
        self:paintHome(bb)
    elseif app.mode == "aircraft" then
        self:paintAircraft(bb)
    else
        self:paintISS(bb)
    end
    rule(bb, H - 71)
    local source = app.mode == "home" and "adsb.fi / wheretheiss.at / issinfo.net"
        or (app.mode == "aircraft" and "https://adsb.fi" or "wheretheiss.at / issinfo.net")
    text(bb, source, 24, H - 58, 15)
    local hint = app.mode == "home" and "Tap radar: aircraft   Tap pass: ISS   Hold: exit"
        or (app.mode == "aircraft" and "Tap left: next   Right: ISS   Header: home" or "Tap: home   Hold: exit")
    text(bb, hint, 24, H - 33, 16)
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
        local size = i == selected_index and 9 or 6
        bb:paintRect(px - math.floor(size / 2), py - math.floor(size / 2), size, size, BLACK)
        if a.heading then
            local head = math.rad(a.heading)
            local tipx = math.floor(px + math.sin(head) * 13)
            local tipy = math.floor(py - math.cos(head) * 13)
            line(bb, px, py, tipx, tipy, BLACK)
        end
    end
    for i = 1, math.min(#ac, 24) do drawAircraft(i) end
    if selected_index and selected_index > 24 and ac[selected_index] then drawAircraft(selected_index) end
end

function Dashboard:paintHome(bb)
    local app, ac, pass = self.owner, self.owner.aircraft, self.owner.next_pass
    local landscape = W > H
    local first = ac and ac[1]
    local radar_x, radar_y, radar_r = landscape and 192 or math.floor(W / 2), landscape and 266 or 270, landscape and 110 or 115
    text(bb, ac and ("NEARBY  /  " .. #ac .. " AIRCRAFT") or "NEARBY  /  UNAVAILABLE",
        24, 122, 21, landscape and 350 or W - 48, true)
    self:paintRadar(bb, ac or {}, radar_x, radar_y, radar_r, app.settings.radius_nm, 1)
    local tx, top, column_width = landscape and 411 or 24, landscape and 128 or 412, landscape and 355 or W - 48
    if landscape then bb:paintRect(392, 121, 2, 270, GRAY) end
    local feature_label = first and (first.emergency and "EMERGENCY" or (first.military and "MILITARY"
        or (first.rare and "UNUSUAL AIRCRAFT" or "FEATURED AIRCRAFT"))) or "FEATURED AIRCRAFT"
    text(bb, (app.aircraft_error and "STALE / " or "") .. feature_label, tx, top, 19, column_width, true)
    if first then
        local name = first.flight ~= "" and first.flight or (first.registration ~= "" and first.registration or first.id)
        local visual_x, visual_y = landscape and 650 or 440, landscape and 160 or 453
        local visual_w, visual_h = landscape and 110 or 110, landscape and 47 or 60
        local visual_label = Visuals.paintAircraft(bb, visual_x, visual_y, visual_w, visual_h, first, BLACK)
        text(bb, visual_label, visual_x - 8, visual_y + visual_h + 2, 15, 130)
        text(bb, name, tx, top + 37, landscape and 38 or 34, landscape and 225 or 390, true)
        text(bb, (first.model ~= "" and first.model or "Unknown type") .. "  " .. first.registration,
            tx, top + 89, 21, landscape and 225 or 390)
        text(bb, string.format("%.1f nm  /  %03d deg", first.distance_nm, first.bearing),
            tx, top + 128, 22, column_width)
        local altitude = first.altitude_ft and (tostring(math.floor(first.altitude_ft + 0.5)) .. " ft") or "-- ft"
        local speed = first.speed_kt and (tostring(math.floor(first.speed_kt + 0.5)) .. " kt") or "-- kt"
        text(bb, altitude .. "  /  " .. speed, tx, top + 166, 21, column_width)
        if landscape then
            local nearest = first
            for _, plane in ipairs(ac) do
                if plane.distance_nm < nearest.distance_nm then nearest = plane end
            end
            if nearest ~= first then
                local nearest_name = nearest.flight ~= "" and nearest.flight or nearest.registration
                text(bb, string.format("Nearest: %s  %.1f nm", nearest_name, nearest.distance_nm),
                    tx, top + 210, 17, column_width)
            end
        end
    else
        text(bb, app.aircraft_error or "No aircraft in range", tx, top + 58, 21, column_width)
    end
    local divider = landscape and 404 or 631
    rule(bb, divider)
    text(bb, (app.pass_error and pass and "STALE / " or "") .. "NEXT VISIBLE ISS PASS", 24, divider + 17, 19, W - 48, true)
    Visuals.paintISS(bb, landscape and 647 or 450, divider + (landscape and 30 or 28),
        landscape and 110 or 105, landscape and 53 or 44, BLACK, WHITE)
    if pass then
        text(bb, pass_headline(pass, app.settings.timezone), 24, divider + 46, landscape and 30 or 25,
            landscape and 590 or 410, true)
        text(bb, string.format("Look %s to %s  /  peaks at %.0f deg", pass.direction, pass.end_direction, pass.elevation or 0),
            24, divider + (landscape and 87 or 78), landscape and 21 or 18,
            landscape and 590 or 410)
    else
        text(bb, app.pass_error or "No visible pass in 10 days", 24, divider + 52, 21, W - 48)
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
        local label = Visuals.paintAircraft(bb, 100, 432, 400, 91, first, BLACK)
        text(bb, label .. " / representative shape", 24, 527, 16, W - 48)
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
    text(bb, "WHAT IT LOOKS LIKE", 421, 126, 19, 350, true)
    if first then
        local label = Visuals.paintAircraft(bb, 446, 158, 292, 111, first, BLACK)
        text(bb, label .. " / representative shape", 421, 273, 17, 350)
    end
    text(bb, "NEARBY RADAR", 421, 306, 18, 350, true)
    self:paintRadar(bb, ac, 592, 425, 64, app.settings.radius_nm, app.selected_index or 1)
end

function Dashboard:paintSkyView(bb, iss, cx, cy, radius)
    ring(bb, cx, cy, radius, BLACK)
    ring(bb, cx, cy, math.floor(radius / 2), GRAY)
    bb:paintRect(cx - 1, cy - radius, 2, radius * 2, GRAY)
    bb:paintRect(cx - radius, cy - 1, radius * 2, 2, GRAY)
    text(bb, "N", cx - 7, cy - radius - 25, 17, 20)
    text(bb, "E", cx + radius + 8, cy - 10, 17, 20)
    if radius >= 50 then text(bb, "S", cx - 7, cy + radius + 6, 17, 20) end
    text(bb, "W", cx - radius - 23, cy - 10, 17, 20)
    if iss.elevation and iss.elevation > 0 then
        local distance = (90 - math.min(90, iss.elevation)) / 90 * radius
        local bearing = math.rad(iss.bearing or 0)
        local px = math.floor(cx + math.sin(bearing) * distance)
        local py = math.floor(cy - math.cos(bearing) * distance)
        bb:paintRect(px - 7, py - 7, 14, 14, BLACK)
    elseif radius >= 50 then
        bb:paintRect(cx - 90, cy - 17, 180, 34, WHITE)
        text(bb, "BELOW HORIZON", cx - 87, cy - 12, 18, 174, true)
    end
end

function Dashboard:paintISS(bb)
    local app, iss, pass = self.owner, self.owner.iss, self.owner.next_pass
    if W > H then return self:paintISSLandscape(bb) end
    if not iss then
        text(bb, "ISS DATA UNAVAILABLE", 24, 135, 25, W - 48, true)
        text(bb, app.iss_error or "Check Wi-Fi", 24, 180, 19)
        return
    end
    text(bb, "INTERNATIONAL SPACE STATION", 24, 130, 21, W - 48, true)
    text(bb, string.format("%.1f%s  /  %.1f%s", math.abs(iss.lat), iss.lat < 0 and "S" or "N", math.abs(iss.lon), iss.lon < 0 and "W" or "E"), 24, 176, 24)
    text(bb, string.format("%.0f km altitude", iss.altitude_km or 0), 24, 220, 23)
    text(bb, string.format("%.0f km/h  /  %.0f km ground range", iss.velocity_kmh or 0, iss.distance_km), 24, 258, 20)
    text(bb, iss.elevation > 0 and string.format("%.0f deg above %03d deg", iss.elevation, iss.bearing)
        or "Below your horizon now", 24, 284, 17, W - 48, true)
    rule(bb, 307)
    text(bb, "THE ISS / SOLAR ARRAYS", 24, 322, 18, W - 48, true)
    Visuals.paintISS(bb, 70, 356, W - 140, 72, BLACK, WHITE)
    text(bb, "Solar panels flank the central modules", 24, 436, 17, W - 48)
    text(bb, "LOCAL SKY VIEW", 24, 463, 17, W - 48, true)
    self:paintSkyView(bb, iss, math.floor(W / 2), 521, 32)
    rule(bb, 575)
    text(bb, "NEXT VISIBLE PASS", 24, 590, 18, W - 48, true)
    if pass then
        text(bb, pass_headline(pass, app.settings.timezone), 24, 623, 28, W - 48, true)
        text(bb, string.format("%s to %s  /  max %.0f deg", pass.direction, pass.end_direction, pass.elevation or 0), 24, 671, 21)
    else
        text(bb, app.pass_error or "No visible pass in 10 days", 24, 632, 21)
    end
end

function Dashboard:paintISSLandscape(bb)
    local app, iss, pass = self.owner, self.owner.iss, self.owner.next_pass
    if not iss then
        text(bb, "ISS DATA UNAVAILABLE", 24, 145, 25, 360, true)
        text(bb, app.iss_error or "Check Wi-Fi", 24, 190, 19, 360)
        return
    end
    text(bb, "INTERNATIONAL SPACE STATION", 24, 128, 21, 365, true)
    text(bb, string.format("%.1f%s  /  %.1f%s", math.abs(iss.lat), iss.lat < 0 and "S" or "N", math.abs(iss.lon), iss.lon < 0 and "W" or "E"), 24, 177, 24, 355)
    text(bb, string.format("%.0f km altitude", iss.altitude_km or 0), 24, 219, 23, 355)
    text(bb, string.format("%.0f km/h", iss.velocity_kmh or 0), 24, 259, 23, 355)
    text(bb, string.format("%.0f km ground range", iss.distance_km), 24, 296, 21, 355)
    local sky_text = iss.elevation > 0 and string.format("%.0f deg above %03d deg", iss.elevation, iss.bearing)
        or "Below your horizon now"
    text(bb, sky_text, 24, 338, 19, 355, true)
    bb:paintRect(391, 122, 2, 383, GRAY)
    text(bb, "THE ISS / SOLAR ARRAYS", 421, 128, 19, 350, true)
    Visuals.paintISS(bb, 432, 162, 328, 92, BLACK, WHITE)
    text(bb, "Solar panels + central modules", 421, 261, 17, 350)
    text(bb, "LOCAL SKY NOW", 421, 288, 17, 350, true)
    self:paintSkyView(bb, iss, 592, 342, 34)
    rule(bb, 392)
    text(bb, "NEXT VISIBLE PASS", 24, 409, 19, W - 48, true)
    if pass then
        text(bb, pass_headline(pass, app.settings.timezone), 24, 440, 25, 380, true)
        text(bb, string.format("%s to %s  /  max %.0f deg", pass.direction, pass.end_direction, pass.elevation or 0), 421, 451, 21, 350)
    else
        text(bb, app.pass_error or "No visible pass in 10 days", 24, 450, 21, W - 48)
    end
end

local Sky = WidgetContainer:extend { name = "kindlesky", is_doc_only = false }
-- Public example location: New York City. Set your own location in the plugin menu.
local defaults = { lat = 40.7128, lon = -74.0060, radius_nm = 40, refresh_seconds = 120,
    landscape = true, auto_rotate = true, timezone = "auto" }
local ROTATE_SECONDS = 90

local function get_json(url)
    local chunks = {}
    socketutil:set_timeout(8, 15)
    local called, ok, code = pcall(https.request, {
        url = url,
        method = "GET",
        sink = socketutil.table_sink(chunks),
        headers = { ["User-Agent"] = "KindleSky/0.3 (personal e-ink display)" },
        protocol = "any",
        options = { "all", "no_sslv2", "no_sslv3" },
        verify = "none", -- Public display data; see README for the TLS limitation.
    })
    socketutil:reset_timeout()
    if not called then return nil, "Network request failed" end
    if ok ~= 1 or code ~= 200 then return nil, "HTTP " .. tostring(code) end
    local valid, value = pcall(JSON.decode, table.concat(chunks))
    if not valid or type(value) ~= "table" then return nil, "Invalid response" end
    return value
end

function Sky:init()
    self.settings_file = LuaSettings:open(DataStorage:getSettingsDir() .. "/kindlesky.lua")
    self.settings = self.settings_file:readSetting("settings") or defaults
    if self.settings.landscape == nil then self.settings.landscape = true end
    if self.settings.auto_rotate == nil then self.settings.auto_rotate = true end
    if not Time.isValidZone(self.settings.timezone) then self.settings.timezone = "auto" end
    self.mode = "home"
    self.selected_index = 1
    self.rotation_state = {}
    self.alerted_emergency_ids = {}
    self.running = false
    self.refresh_task = function() self:refresh() end
    self.rotate_task = function() self:rotateView() end
    self.ui.menu:registerToMainMenu(self)
end

function Sky:saveSettings()
    self.settings_file:saveSetting("settings", self.settings)
    self.settings_file:flush()
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
    local pass, now = self.next_pass, os.time()
    local imminent_pass = pass and pass.visible and now <= pass.finish
        and (pass.active or pass.start - now <= 600)
    if self.emergency_hold_until and now < self.emergency_hold_until then
        self.mode = "aircraft"
    elseif imminent_pass then
        self.mode = "iss"
    elseif self.mode == "home" then
        if self.aircraft and #self.aircraft > 0 then
            self.selected_index, self.rotation_state = Rotation.choose(self.aircraft, self.rotation_state)
            self.mode = "aircraft"
        else
            self.mode = "iss"
        end
    elseif self.mode == "aircraft" then
        self.mode = "iss"
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
    self.iss_error = "Waiting for Wi-Fi"
    self.dashboard = Dashboard:new { owner = self }
    UIManager:show(self.dashboard)
    UIManager:preventStandby()
    self:setKeepAwake(true)
    self:scheduleRotation()
    self:refresh()
end

function Sky:stop()
    if not self.running then return end
    self.running = false
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
    if self.next_pass then
        local now = os.time()
        if now > self.next_pass.finish then
            self.next_pass = nil
            self.pass_checked_at = nil
        else
            self.next_pass.minutes = math.max(0, math.ceil((self.next_pass.start - now) / 60))
            self.next_pass.active = self.next_pass.start <= now
        end
    end
    if not NetworkMgr:isConnected() then
        self.aircraft_error = "Wi-Fi offline"
        self.iss_error = "Wi-Fi offline"
        self.pass_error = "Wi-Fi offline"
        if not self.aircraft_updated_at or os.time() - self.aircraft_updated_at > 600 then self.aircraft = nil end
        if not self.iss_updated_at or os.time() - self.iss_updated_at > 600 then self.iss = nil end
        if self.dashboard then UIManager:setDirty(self.dashboard, "ui") end
    end
    NetworkMgr:runWhenConnected(function()
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
        local iss_response, iss_error = get_json("https://api.wheretheiss.at/v1/satellites/25544")
        if iss_response then
            self.iss = Data.iss(iss_response, lat, lon)
            self.iss_updated_at = os.time()
            self.iss_error = self.iss and nil or "Invalid ISS position"
        else
            self.iss_error = iss_error or "ISS data unavailable"
            if not self.iss_updated_at or os.time() - self.iss_updated_at > 600 then self.iss = nil end
        end
        if self.next_pass and os.time() > self.next_pass.finish then
            self.next_pass = nil
            self.pass_checked_at = nil
        end
        if not self.pass_checked_at or os.time() - self.pass_checked_at > 3600 then
            local pass_url = string.format("https://issinfo.net/next-pass?lat=%.4f&lon=%.4f&format=json", lat, lon)
            local pass_response, pass_error = get_json(pass_url)
            if pass_response then
                self.next_pass = Data.pass(pass_response, os.time())
                self.pass_error = nil
                self.pass_checked_at = os.time()
            else
                self.pass_error = pass_error or "Pass prediction unavailable"
            end
        elseif self.next_pass then
            self.pass_error = nil
        end
        if self.next_pass then
            self.next_pass.minutes = math.max(0, math.ceil((self.next_pass.start - os.time()) / 60))
            self.next_pass.active = self.next_pass.start <= os.time() and os.time() <= self.next_pass.finish
        end
        if not emergency_preempted and not (self.emergency_hold_until and os.time() < self.emergency_hold_until)
            and self.next_pass and self.next_pass.visible and self.next_pass.minutes <= 10
            and not self.next_pass.active and self.alerted_pass_start ~= self.next_pass.start then
            self.mode = "iss"
            self.alerted_pass_start = self.next_pass.start
        end
        self.refresh_count = (self.refresh_count or 0) + 1
        if self.dashboard then UIManager:setDirty(self.dashboard, self.refresh_count % 30 == 0 and "full" or "ui") end
        NetworkMgr:afterWifiAction()
    end)
end

function Sky:onSuspend()
    UIManager:unschedule(self.refresh_task)
    UIManager:unschedule(self.rotate_task)
end

function Sky:onResume()
    if self.running then
        self:scheduleRotation()
        self:refresh()
    end
end

function Sky:onCloseWidget()
    self:stop()
end

function Sky:configure()
    local dialog
    dialog = MultiInputDialog:new {
        title = _("Kindle Sky location and refresh"),
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
                self:saveSettings()
                UIManager:close(dialog)
                if self.running then self:refresh() end
            end },
        } },
    }
    UIManager:show(dialog)
end

function Sky:addToMainMenu(menu_items)
    local timezone_items = {}
    -- Do not name the loop index "_": it would shadow the gettext function used below.
    for _index, zone in ipairs(Time.zones) do
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
        text = _("Kindle Sky"),
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
            { text = _("Time zone"), sub_item_table = timezone_items },
        },
    }
end

return Sky
