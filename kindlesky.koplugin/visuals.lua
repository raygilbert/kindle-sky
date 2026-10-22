-- Monochrome diagrams sized for an e-ink screen.
-- Aircraft outlines represent broad categories, never a specific airframe or livery.
local Visuals = {}

local function contains(value, pattern)
    return value:find(pattern, 1, true) ~= nil
end

function Visuals.aircraftKind(aircraft)
    local code = tostring(aircraft and aircraft.model or ""):upper()
    local description = tostring(aircraft and aircraft.description or ""):upper()
    if code:match("^H60") or code:match("^R22") or code:match("^R44")
        or code:match("^B40[67]") or code:match("^EC[0-9]")
        or contains(description, "HELICOPTER") or contains(description, "ROTORCRAFT") then
        return "helicopter", "Helicopter"
    end
    if code:match("^F1[568]") or code:match("^F2[23]") or code:match("^F35")
        or contains(description, "FIGHTER") then
        return "fighter", "Fighter jet"
    end
    if code:match("^TBM") or code:match("^B190") or code:match("^AT[467]")
        or code:match("^DH8") or code:match("^PC12") or code:match("^C208")
        or contains(description, "TURBOPROP") then
        return "turboprop", "Turboprop"
    end
    if code:match("^C1[578]") or code:match("^C20[67]") or code:match("^P28")
        or code:match("^DA[24]") or code:match("^SR2") or code:match("^PA[0-9]")
        or contains(description, "SKYHAWK") or contains(description, "CIRRUS") then
        return "light_prop", "Small prop"
    end
    if code:match("^GLF") or code:match("^C5[26]") or code:match("^E54")
        or code:match("^H25") or code:match("^LJ") or contains(description, "CITATION")
        or contains(description, "GULFSTREAM") or contains(description, "HAWKER") then
        return "business_jet", "Business jet"
    end
    if code:match("^A3[34589]") or code:match("^B7[4678]")
        or code:match("^B77") or code:match("^B78") or code:match("^A388")
        or contains(description, "WIDEBODY") then
        return "widebody", "Widebody jet"
    end
    if code:match("^A[23]") or code:match("^B7") or code:match("^CRJ")
        or code:match("^E7") or code:match("^E19") or contains(description, "AIRBUS")
        or contains(description, "BOEING") or contains(description, "REGIONAL JET") then
        return "airliner", "Airliner"
    end
    return "aircraft", "Aircraft"
end

local outlines = {
    widebody = {
        {50,2},{55,10},{58,33},{99,61},{99,70},{58,55},{58,78},
        {73,88},{73,95},{50,87},{27,95},{27,88},{42,78},{42,55},
        {1,70},{1,61},{42,33},{45,10},
    },
    airliner = {
        {50,2},{54,9},{56,33},{96,58},{96,65},{55,53},{55,78},
        {70,88},{70,94},{50,86},{30,94},{30,88},{45,78},{45,53},
        {4,65},{4,58},{44,33},{46,9},
    },
    business_jet = {
        {50,2},{54,10},{55,41},{90,63},{90,68},{55,57},{55,80},
        {68,89},{68,94},{50,86},{32,94},{32,89},{45,80},{45,57},
        {10,68},{10,63},{45,41},{46,10},
    },
    light_prop = {
        {50,3},{54,12},{54,37},{96,37},{96,45},{54,49},{54,80},
        {69,87},{69,93},{50,87},{31,93},{31,87},{46,80},{46,49},
        {4,45},{4,37},{46,37},{46,12},
    },
    turboprop = {
        {50,2},{54,10},{55,36},{97,40},{97,47},{55,50},{55,80},
        {70,88},{70,94},{50,86},{30,94},{30,88},{45,80},{45,50},
        {3,47},{3,40},{45,36},{46,10},
    },
    fighter = {
        {50,2},{54,13},{56,45},{97,83},{97,91},{55,71},{55,88},
        {50,96},{45,88},{45,71},{3,91},{3,83},{44,45},{46,13},
    },
    helicopter = {
        {50,16},{57,23},{61,42},{58,63},{54,72},{54,95},
        {46,95},{46,72},{42,63},{39,42},{43,23},
    },
}
outlines.aircraft = outlines.airliner

local function polygon(bb, points, x, y, width, height, color)
    local vertices = {}
    for _, point in ipairs(points) do
        vertices[#vertices + 1] = { x + point[1] * width / 100, y + point[2] * height / 100 }
    end
    for row = math.floor(y), math.floor(y + height) do
        local scan_y = row + 0.5
        local intersections = {}
        for i = 1, #vertices do
            local a, b = vertices[i], vertices[i % #vertices + 1]
            if (a[2] <= scan_y and b[2] > scan_y) or (b[2] <= scan_y and a[2] > scan_y) then
                intersections[#intersections + 1] = a[1] + (scan_y - a[2]) * (b[1] - a[1]) / (b[2] - a[2])
            end
        end
        table.sort(intersections)
        for i = 1, #intersections - 1, 2 do
            local left = math.floor(intersections[i])
            local right = math.ceil(intersections[i + 1])
            if right > left then bb:paintRect(left, row, right - left, 1, color) end
        end
    end
end

function Visuals.paintAircraft(bb, x, y, width, height, aircraft, black, white)
    local kind, label = Visuals.aircraftKind(aircraft)
    polygon(bb, outlines[kind], x, y, width, height, black)
    white = white or require("ffi/blitbuffer").COLOR_WHITE
    -- Cockpit glazing and surface marks stay chunky enough for the small Home view.
    if kind ~= "helicopter" and width >= 100 then
        bb:paintRect(math.floor(x + width * 0.47), math.floor(y + height * 0.15),
            math.max(4, math.floor(width * 0.06)), math.max(2, math.floor(height * 0.035)), white)
    end
    if kind == "light_prop" then
        bb:paintRect(math.floor(x + width * 0.37), math.floor(y + height * 0.07),
            math.max(6, math.floor(width * 0.26)), 2, black)
        if width >= 200 then
            bb:paintRect(math.floor(x + width * 0.18), math.floor(y + height * 0.40),
                math.floor(width * 0.10), 2, white)
            bb:paintRect(math.floor(x + width * 0.72), math.floor(y + height * 0.40),
                math.floor(width * 0.10), 2, white)
        end
    elseif kind == "turboprop" then
        for _, center in ipairs({0.27, 0.73}) do
            bb:paintRect(math.floor(x + width * center) - 2, math.floor(y + height * 0.29), 4,
                math.max(7, math.floor(height * 0.26)), black)
            bb:paintRect(math.floor(x + width * center) - math.max(4, math.floor(width * 0.035)),
                math.floor(y + height * 0.30), math.max(8, math.floor(width * 0.07)), 2, black)
        end
    elseif kind == "helicopter" then
        bb:paintRect(math.floor(x + width * 0.02), math.floor(y + height * 0.42),
            math.floor(width * 0.96), math.max(2, math.floor(height * 0.045)), black)
        bb:paintRect(math.floor(x + width * 0.45), math.floor(y + height * 0.23),
            math.floor(width * 0.10), math.max(2, math.floor(height * 0.06)), white)
        bb:paintRect(math.floor(x + width * 0.38), math.floor(y + height * 0.90),
            math.floor(width * 0.24), 3, black)
    elseif kind == "airliner" or kind == "business_jet" or kind == "widebody" then
        for _, center in ipairs({0.31, 0.69}) do
            bb:paintRect(math.floor(x + width * center), math.floor(y + height * 0.57),
                math.max(3, math.floor(width * 0.035)), math.max(5, math.floor(height * 0.16)), black)
        end
        if kind == "widebody" and width >= 200 then
            for _, center in ipairs({0.19, 0.81}) do
                bb:paintRect(math.floor(x + width * center), math.floor(y + height * 0.66),
                    math.max(3, math.floor(width * 0.03)), math.max(5, math.floor(height * 0.13)), black)
            end
        end
    elseif kind == "fighter" and width >= 200 then
        bb:paintRect(math.floor(x + width * 0.465), math.floor(y + height * 0.23),
            math.max(5, math.floor(width * 0.07)), math.max(3, math.floor(height * 0.13)), white)
    end
    return label
end

function Visuals.paintISS(bb, x, y, width, height, black, white)
    local panel_y = math.floor(y + height * 0.16)
    local panel_h = math.floor(height * 0.68)
    local panel_w = math.floor(width * 0.185)
    local gap = math.max(3, math.floor(width * 0.018))
    local positions = {x, x + panel_w + gap, x + width - 2 * panel_w - gap, x + width - panel_w}
    for _, panel_x in ipairs(positions) do
        panel_x = math.floor(panel_x)
        bb:paintRect(panel_x, panel_y, panel_w, panel_h, black)
        for i = 1, 3 do
            bb:paintRect(panel_x + math.floor(i * panel_w / 4), panel_y + 1, 1, panel_h - 2, white)
        end
        for i = 1, 2 do
            bb:paintRect(panel_x + 1, panel_y + math.floor(i * panel_h / 3), panel_w - 2, 1, white)
        end
    end
    local center_x = math.floor(x + width / 2)
    local center_y = math.floor(y + height / 2)
    bb:paintRect(math.floor(x + 2 * panel_w + gap), center_y - 2,
        math.floor(width - 4 * panel_w - 2 * gap), 4, black)
    local body_w = math.max(12, math.floor(width * 0.12))
    bb:paintRect(center_x - math.floor(body_w / 2), center_y - math.floor(height * 0.19),
        body_w, math.floor(height * 0.38), black)
    bb:paintRect(center_x - math.floor(body_w * 0.31), center_y - math.floor(height * 0.28),
        math.floor(body_w * 0.62), math.floor(height * 0.56), black)
    bb:paintRect(center_x - 1, center_y - math.floor(height * 0.36), 2,
        math.floor(height * 0.72), black)
end

function Visuals.paintTrain(bb, x, y, width, height, provider, black, white)
    local body_y = math.floor(y + height * 0.15)
    local body_h = math.floor(height * 0.65)
    local body_x = math.floor(x + width * 0.04)
    local body_w = math.floor(width * 0.92)
    bb:paintRect(body_x, body_y, body_w, body_h, black)
    -- Light window bands and doors make a readable train at small e-ink sizes.
    local car_count = provider == "tfl" and 4 or 3
    local slot = body_w / car_count
    for car = 0, car_count - 1 do
        local base = body_x + math.floor(car * slot)
        local window_y = body_y + math.floor(body_h * 0.20)
        local window_h = math.max(4, math.floor(body_h * 0.30))
        bb:paintRect(base + math.floor(slot * 0.10), window_y,
            math.max(4, math.floor(slot * 0.43)), window_h, white)
        bb:paintRect(base + math.floor(slot * 0.67), body_y + math.floor(body_h * 0.17),
            math.max(3, math.floor(slot * 0.23)), math.floor(body_h * 0.65), white)
        if car > 0 then bb:paintRect(base, body_y + 2, 2, body_h - 4, white) end
    end
    local wheel_y = body_y + body_h
    for _, fraction in ipairs({0.16, 0.36, 0.64, 0.84}) do
        bb:paintRect(math.floor(body_x + body_w * fraction), wheel_y, math.max(5, math.floor(width * 0.04)),
            math.max(3, math.floor(height * 0.10)), black)
    end
    bb:paintRect(body_x + math.floor(body_w * 0.07), body_y + body_h - 4,
        math.floor(body_w * 0.86), 2, white)
end

return Visuals
