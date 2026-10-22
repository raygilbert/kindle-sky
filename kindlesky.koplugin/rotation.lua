-- Choose a different aircraft for each automatic Aircraft view.
-- With two or more priority aircraft, slots follow priority/priority/ordinary.
-- A single priority aircraft alternates with ordinary traffic to avoid repeats.
local Rotation = {}

function Rotation.identity(aircraft, index)
    if aircraft.id and aircraft.id ~= "" then return aircraft.id end
    if aircraft.registration and aircraft.registration ~= "" then return aircraft.registration end
    if aircraft.flight and aircraft.flight ~= "" then return aircraft.flight end
    return tostring(index)
end

local function nextCandidate(pool, last_pool_id, avoid_id)
    if #pool == 0 then return nil end
    local start = 1
    for i, entry in ipairs(pool) do
        if entry.id == last_pool_id then
            start = i % #pool + 1
            break
        end
    end
    for step = 0, #pool - 1 do
        local entry = pool[(start + step - 1) % #pool + 1]
        if entry.id ~= avoid_id then return entry end
    end
end

function Rotation.choose(aircraft, state)
    state = state or {}
    local priority, ordinary = {}, {}
    for index, plane in ipairs(aircraft or {}) do
        local entry = { index = index, id = Rotation.identity(plane, index) }
        if plane.rare then
            priority[#priority + 1] = entry
        else
            ordinary[#ordinary + 1] = entry
        end
    end
    if #priority + #ordinary == 0 then return nil, state end

    local want_priority
    if #ordinary == 0 then
        want_priority = true
    elseif #priority == 0 then
        want_priority = false
    elseif #priority == 1 then
        want_priority = state.last_id ~= priority[1].id
    else
        want_priority = (state.slot or 0) % 3 ~= 2
    end

    local first, second = want_priority and priority or ordinary,
        want_priority and ordinary or priority
    local first_cursor = want_priority and state.last_priority_id or state.last_ordinary_id
    local second_cursor = want_priority and state.last_ordinary_id or state.last_priority_id
    local chosen = nextCandidate(first, first_cursor, state.last_id)
        or nextCandidate(second, second_cursor, state.last_id)
        or nextCandidate(first, first_cursor, nil)
        or nextCandidate(second, second_cursor, nil)
    state.slot = (state.slot or 0) + 1
    state.last_id = chosen.id
    for _, entry in ipairs(priority) do
        if entry.id == chosen.id then state.last_priority_id = chosen.id; break end
    end
    for _, entry in ipairs(ordinary) do
        if entry.id == chosen.id then state.last_ordinary_id = chosen.id; break end
    end
    return chosen.index, state
end

return Rotation
