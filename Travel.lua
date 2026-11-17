-- Travel planner for TomTom arrows: if the target is on another continent, route to the right boat /
-- zeppelin; if it is far on the same continent, route to the nearest flight master first. Re-plans after
-- zone changes, hearthstones, flights and boat rides, until the final leg is set.
-- Flight masters come from QuestieDB (FLIGHT_MASTER npc flag); whether you know a flight path can't be
-- checked away from a flight master, so it is a suggestion.
local _, ns = ...

local FLY_MIN = 1800 -- yards: shorter trips go straight
local FLY_GAIN = 600 -- yards the flight must save
local ARRIVED = 60 -- yards: close enough, stop tracking

-- docks: { faction ("A" / "H" / "N"), from, to, kind } with { uiMap, x, y, name } (0-100 coords, both ways)
local TRANSPORTS = {
    { "A", { 1437, 4.6, 57.1, "Menethil Harbor" }, { 1439, 32.4, 43.8, "Auberdine" }, "Boat" },
    { "A", { 1437, 5.0, 63.5, "Menethil Harbor" }, { 1445, 71.6, 56.4, "Theramore" }, "Boat" },
    { "N", { 1434, 25.9, 73.1, "Booty Bay" }, { 1413, 63.7, 38.6, "Ratchet" }, "Boat" },
    { "H", { 1411, 50.6, 12.6, "Orgrimmar Zeppelin Tower" }, { 1420, 60.7, 58.8, "Undercity Zeppelin Tower" }, "Zeppelin" },
    { "H", { 1411, 50.9, 13.9, "Orgrimmar Zeppelin Tower" }, { 1434, 31.4, 30.0, "Grom'gol Zeppelin Tower" }, "Zeppelin" },
}

local dest -- { map, x, y, label }
local uid -- current TomTom waypoint
local fms -- friendly flight masters: { { name, map, x, y, c, wx, wy }, ... }

local function Safe(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, v = pcall(fn, ...)
    if ok then
        return v
    end
end

local function Pos(map, x, y)
    local c, wx, wy = ns.World(map, x / 100, y / 100)
    if c then
        return { c = c, wx = wx, wy = wy }
    end
end

local function Dist(a, b)
    if a and b and a.c == b.c then
        return math.sqrt((a.wx - b.wx) ^ 2 + (a.wy - b.wy) ^ 2)
    end
    return math.huge
end

local function FlightMasters()
    if fms then
        return fms
    end
    fms = {}
    local ids = NpcDB and Safe(NpcDB.GetAllIds)
    for _, id in ipairs(type(ids) == "table" and ids or {}) do
        local flags = Safe(NpcDB.npcFlags, id)
        if type(flags) == "number" and math.floor(flags / 8) % 2 == 1 then
            local f = Safe(NpcDB.friendlyToFaction, id)
            if not f or f:find(ns.MyFaction(), 1, true) then
                local spawns = Safe(NpcDB.spawns, id)
                for areaId, coords in pairs(type(spawns) == "table" and spawns or {}) do
                    local m = type(coords) == "table" and ns.UiMap(areaId)
                    local xy = m and coords[1]
                    if type(xy) == "table" and type(xy[1]) == "number" and xy[1] >= 0 then
                        local p = Pos(m, xy[1], xy[2])
                        if p then
                            p.name, p.map, p.x, p.y = Safe(NpcDB.name, id) or "Flight Master", m, xy[1], xy[2]
                            fms[#fms + 1] = p
                        end
                    end
                end
            end
        end
    end
    return fms
end

local function NearestFM(p)
    local best, bd
    for _, fm in ipairs(FlightMasters()) do
        local d = Dist(p, fm)
        if d < (bd or math.huge) then
            best, bd = fm, d
        end
    end
    return best, bd
end

local function Zone(map)
    return ns.ZoneName and ns.ZoneName(map) or tostring(map)
end

-- next stop toward target from here: returns map, x, y, step text (nil text = go straight)
local function Leg(here, target)
    local d = Dist(here, target.pos)
    if d < FLY_MIN then
        return nil
    end
    local a, da = NearestFM(here)
    local b, db = NearestFM(target.pos)
    if a and b and a ~= b and da + db + FLY_GAIN < d then
        return a.map, a.x, a.y, ("Fly to %s (%s)"):format(b.name, Zone(b.map))
    end
end

local function Place(map, x, y, title)
    if not (TomTom and TomTom.AddWaypoint) then
        ns.Print("TomTom is not loaded - " .. title .. (" (%.0f, %.0f)"):format(x, y))
        return
    end
    if uid and TomTom.RemoveWaypoint then
        pcall(TomTom.RemoveWaypoint, TomTom, uid)
    end
    uid = TomTom:AddWaypoint(map, x / 100, y / 100, { title = title, crazy = true, from = ns.ADDON_NAME })
end

local function Plan(announce, clicked)
    if not dest then
        return
    end
    local here
    if ns.PlayerWorld then
        local c, wx, wy = ns.PlayerWorld()
        here = c and { c = c, wx = wx, wy = wy }
    end
    local final = { pos = Pos(dest.map, dest.x, dest.y) }
    if not here or not final.pos then
        Place(dest.map, dest.x, dest.y, dest.label)
        dest = nil
        return
    end
    if Dist(here, final.pos) < ARRIVED then
        -- you are there. An arrow you just asked for is still set (the NPC can be hard to spot);
        -- a re-plan after a flight or a zone change just ends the trip
        if clicked then
            Place(dest.map, dest.x, dest.y, dest.label)
            if announce then
                ns.Print("Arrow Set: " .. dest.label)
            end
        end
        dest = nil
        return
    end
    local title, map, x, y
    if here.c ~= final.pos.c then
        -- another continent: best boat / zeppelin for your faction
        local faction, best, bestCost = ns.MyFaction(), nil, nil
        for _, t in ipairs(TRANSPORTS) do
            if t[1] == "N" or t[1] == faction then
                for _, dir in ipairs({ { t[2], t[3] }, { t[3], t[2] } }) do
                    local from, to = Pos(dir[1][1], dir[1][2], dir[1][3]), Pos(dir[2][1], dir[2][2], dir[2][3])
                    local cost = Dist(here, from) + Dist(to, final.pos)
                    if cost < (bestCost or math.huge) then
                        best, bestCost = { from = dir[1], to = dir[2], kind = t[4], pos = from }, cost
                    end
                end
            end
        end
        if best then
            local step = ("Take %s to %s"):format(best.kind, best.to[4])
            local fm, fx, fy, fly = Leg(here, best)
            if fm then
                map, x, y, title = fm, fx, fy, fly .. "  >  " .. step .. "  >  " .. dest.label
            else
                map, x, y, title = best.from[1], best.from[2], best.from[3], step .. " (" .. best.from[4] .. ")  >  " .. dest.label
            end
        end
    else
        local fm, fx, fy, fly = Leg(here, final)
        if fm then
            map, x, y, title = fm, fx, fy, fly .. "  >  " .. dest.label
        end
    end
    if not map then
        Place(dest.map, dest.x, dest.y, dest.label)
        if announce then
            ns.Print("Arrow Set: " .. dest.label)
        end
        return
    end
    Place(map, x, y, title)
    if announce then
        ns.Print("Route: " .. title)
    end
end

function ns.Travel(map, x, y, label)
    dest = { map = map, x = x, y = y, label = label }
    Plan(true, true)
end

local events = CreateFrame("Frame")
for _, ev in ipairs({ "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "PLAYER_CONTROL_GAINED" }) do
    pcall(events.RegisterEvent, events, ev)
end
events:SetScript("OnEvent", function()
    if not dest then
        return
    end
    C_Timer.After(1, function()
        if UnitOnTaxi and UnitOnTaxi("player") then
            return -- re-plan when the flight lands (PLAYER_CONTROL_GAINED)
        end
        Plan(true)
    end)
end)
