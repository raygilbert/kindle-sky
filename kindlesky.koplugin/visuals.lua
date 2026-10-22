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
    if code:match("^A[23]") or code:match("^B7") or code:match("^CRJ")
        or code:match("^E7") or code:match("^E19") or contains(description, "AIRBUS")
        or contains(description, "BOEING") or contains(description, "REGIONAL JET") then
        return "airliner", "Airliner"
    end
    return "aircraft", "Aircraft"
end

local outlines = {
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

function Visuals.paintAircraft(bb, x, y, width, height, aircraft, black)
    local kind, label = Visuals.aircraftKind(aircraft)
    polygon(bb, outlines[kind], x, y, width, height, black)
    if kind == "light_prop" then
        bb:paintRect(math.floor(x + width * 0.40), math.floor(y + height * 0.03),
            math.max(2, math.floor(width * 0.20)), 2, black)
    elseif kind == "turboprop" then
        for _, center in ipairs({0.27, 0.73}) do
            bb:paintRect(math.floor(x + width * center), math.floor(y + height * 0.28), 3,
                math.max(5, math.floor(height * 0.28)), black)
        end
    elseif kind == "helicopter" then
        bb:paintRect(math.floor(x + width * 0.05), math.floor(y + height * 0.40),
            math.floor(width * 0.90), 4, black)
        bb:paintRect(math.floor(x + width * 0.38), math.floor(y + height * 0.90),
            math.floor(width * 0.24), 3, black)
    elseif kind == "airliner" or kind == "business_jet" then
        for _, center in ipairs({0.31, 0.69}) do
            bb:paintRect(math.floor(x + width * center), math.floor(y + height * 0.57),
                math.max(3, math.floor(width * 0.035)), math.max(5, math.floor(height * 0.16)), black)
        end
    end
    return label
end

function Visuals.paintISS(bb, x, y, width, height, black, white)
    local panel_y = math.floor(y + height * 0.14)
    local panel_h = math.max(12, math.floor(height * 0.72))
    local panel_w = math.floor(width * 0.33)
    local right_x = math.floor(x + width - panel_w)
    for _, panel_x in ipairs({x, right_x}) do
        panel_x = math.floor(panel_x)
        bb:paintRect(panel_x, panel_y, panel_w, panel_h, black)
        for i = 1, 3 do
            bb:paintRect(panel_x + math.floor(i * panel_w / 4), panel_y + 2, 2, panel_h - 4, white)
        end
        for i = 1, 2 do
            bb:paintRect(panel_x + 2, panel_y + math.floor(i * panel_h / 3), panel_w - 4, 2, white)
        end
    end
    local center_x = math.floor(x + width / 2)
    local center_y = math.floor(y + height / 2)
    bb:paintRect(math.floor(x + panel_w), center_y - 3, math.floor(width - 2 * panel_w), 6, black)
    bb:paintRect(center_x - 17, center_y - 16, 34, 32, black)
    bb:paintRect(center_x - 11, center_y - 22, 22, 44, black)
    bb:paintRect(center_x - 5, center_y - 27, 10, 54, black)
end

return Visuals
