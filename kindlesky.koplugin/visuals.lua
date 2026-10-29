-- Small monochrome diagrams sized for an e-ink screen. They carry data (heading, climb
-- or descent), not decoration. aircraftKind only supplies the plain-language type label.
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

-- Fill a polygon given in pixel coordinates (scanline fill).
local function polygon(bb, points, color)
    local minY, maxY = math.huge, -math.huge
    for _, p in ipairs(points) do
        minY, maxY = math.min(minY, p[2]), math.max(maxY, p[2])
    end
    for row = math.floor(minY), math.ceil(maxY) do
        local scan_y = row + 0.5
        local hits = {}
        for i = 1, #points do
            local a, b = points[i], points[i % #points + 1]
            if (a[2] <= scan_y and b[2] > scan_y) or (b[2] <= scan_y and a[2] > scan_y) then
                hits[#hits + 1] = a[1] + (scan_y - a[2]) * (b[1] - a[1]) / (b[2] - a[2])
            end
        end
        table.sort(hits)
        for i = 1, #hits - 1, 2 do
            local left, right = math.floor(hits[i]), math.ceil(hits[i + 1])
            if right > left then bb:paintRect(left, row, right - left, 1, color) end
        end
    end
end

-- Heading dial: a ring with north marked and a thick arrow pointing the way the aircraft
-- is travelling. heading is degrees clockwise from north; nil draws the empty dial.
function Visuals.paintCompass(bb, cx, cy, radius, heading, black)
    for degree = 0, 359, 3 do
        local a = math.rad(degree)
        bb:paintRect(math.floor(cx + radius * math.sin(a)), math.floor(cy - radius * math.cos(a)), 2, 2, black)
    end
    bb:paintRect(cx - 1, cy - radius - 5, 3, 10, black) -- north tick
    if type(heading) ~= "number" then return end
    local a = math.rad(heading)
    local ux, uy = math.sin(a), -math.cos(a)
    local px, py = -uy, ux
    local len = radius * 0.78
    local head_len, head_half, shaft_half = radius * 0.5, radius * 0.3, math.max(2, radius * 0.07)
    local base_x, base_y = cx + ux * (len - head_len), cy + uy * (len - head_len)
    local tail_x, tail_y = cx - ux * len * 0.8, cy - uy * len * 0.8
    polygon(bb, {
        { tail_x + px * shaft_half, tail_y + py * shaft_half },
        { base_x + px * shaft_half, base_y + py * shaft_half },
        { base_x - px * shaft_half, base_y - py * shaft_half },
        { tail_x - px * shaft_half, tail_y - py * shaft_half },
    }, black)
    polygon(bb, {
        { cx + ux * len, cy + uy * len },
        { base_x + px * head_half, base_y + py * head_half },
        { base_x - px * head_half, base_y - py * head_half },
    }, black)
end

-- Solid triangle: direction "up" (climbing), "down" (descending) or "level" (a flat bar).
function Visuals.paintTrend(bb, x, y, size, direction, black)
    if direction == "up" then
        polygon(bb, { { x + size / 2, y }, { x + size, y + size }, { x, y + size } }, black)
    elseif direction == "down" then
        polygon(bb, { { x, y }, { x + size, y }, { x + size / 2, y + size } }, black)
    else
        bb:paintRect(math.floor(x), math.floor(y + size / 2 - 2), math.floor(size), 4, black)
    end
end

-- Short badge text for a rail line, e.g. "Lansdale/Doylestown" -> "LAN".
function Visuals.lineBadge(line)
    local word = tostring(line or ""):match("[%a]+") or "?"
    return word:sub(1, 3):upper()
end

return Visuals
