-- Reagents tab: lists the reagents of the professions you have (grouped by profession).
-- Details: header card (icon, name, type, level), what it teaches / is crafted by, the
-- recipes it is used in (grouped by profession, collapsible), where to get recipes and
-- vendors with TomTom arrows, and a Wowhead Forever link.
-- Data sources: Ext/Recipes.lua (recipe database built from the game's own data tables),
-- and optionally QuestieDB globals (ItemDB / NpcDB / ObjectDB / QuestDB), TomTom.
local _, ns = ...

local WOWHEAD = "https://www.wowhead.com/forever/%s=%d"
local CAPTURE_QUESTS = false -- quests disabled for now (user request); item details still mention quests as text
local MAX_SOURCES = 2 -- vendors / drops shown per recipe
local PROFESSIONS = {
    [129] = "First Aid", [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy",
    [182] = "Herbalism", [185] = "Cooking", [186] = "Mining", [197] = "Tailoring",
    [202] = "Engineering", [333] = "Enchanting", [356] = "Fishing", [393] = "Skinning",
    [755] = "Jewelcrafting", [773] = "Inscription",
}
local HIDDEN_PROFESSIONS = { [40] = true } -- 40 = Poisons (rogue skill): left out of tooltips and lists
-- skill-up icons (Blizzard profession atlases), with a tinted-arrow fallback
local SKILLUP = {
    orange = { "Professions-Icon-Skill-High", 3, 255, 128, 64 },
    yellow = { "Professions-Icon-Skill-Medium", 2, 255, 255, 0 },
    green = { "Professions-Icon-Skill-Low", 1, 64, 191, 64 },
}
local DIFF_ORDER = { orange = 1, yellow = 2, green = 3, gray = 4, red = 5, none = 6 }
local MEDIA = "Interface\\AddOns\\GristForTheMill\\Media\\"
local ARROW = "|T" .. MEDIA .. "Arrow:14:14:0:-1|t" -- TomTom arrow
local MAPICON = "|T" .. MEDIA .. "Pin:14:14:0:-1|t" -- open the side map
local BAR = "|TInterface\\Buttons\\WHITE8X8:14:3:0:0:8:8:0:8:0:8:242:191:77|t  " -- section accent bar
local SPOTS_MAX = 8 -- locations listed in reagent tooltips
local MAX_SCAN = 300 -- npcs / objects scanned per item for locations
local MAX_MAP_POINTS = 600 -- spawn dots per zone on the side map
local KIND_ICON = {
    Vendor = "|TInterface\\GossipFrame\\VendorGossipIcon:14:14:0:-1|t ",
    Drop = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:14:14:0:-1|t ",
    Gather = "|TInterface\\Icons\\Trade_Herbalism:14:14:0:0:64:64:5:59:5:59|t ",
    Fish = "|TInterface\\Icons\\Trade_Fishing:14:14:0:0:64:64:5:59:5:59|t ",
    Trainer = "|TInterface\\Icons\\INV_Misc_Book_09:14:14:0:0:64:64:5:59:5:59|t ",
}
local KIND_ORDER = { "Vendor", "Drop", "Gather", "Fish", "Trainer" }
local KIND_TITLE = { Vendor = "Sold by", Drop = "Drops from", Gather = "Gathered from", Fish = "Fished in", Trainer = "Trainer" }
local PROF_ICONS = {
    [129] = "Spell_Holy_SealOfSacrifice", [164] = "Trade_BlackSmithing", [165] = "Trade_LeatherWorking",
    [171] = "Trade_Alchemy", [182] = "Trade_Herbalism", [185] = "INV_Misc_Food_15", [186] = "Trade_Mining",
    [197] = "Trade_Tailoring", [202] = "Trade_Engineering", [333] = "Trade_Engraving", [356] = "Trade_Fishing",
    [393] = "INV_Misc_Pelt_Wolf_01", [755] = "INV_Misc_Gem_01", [773] = "INV_Inscription_Tradeskill01",
}
local SKILL_TIP = {
    orange = "Orange - Always Gives a Skill Up",
    yellow = "Yellow - Usually Gives a Skill Up",
    green = "Green - Rarely Gives a Skill Up",
    gray = "Gray - No Skill Up",
    red = "Skill Level Too Low to Craft",
}
local C_GOLD, C_DIM, C_SOFT, C_HEAD = "|cffffd100", "|cff7d8592", "|cffb4bac4", "|cffe8eaf0"

local db, panel, list, detail, urlBox
local searchText = ""
local head = {}
local selected
local index, zoneMap
local toggles = {} -- [key] = true/false; nil = default

local function Safe(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, v = pcall(fn, ...)
    if ok then
        return v
    end
end

local function Clean(s)
    return (tostring(s or ""):gsub("[|:]", " "))
end

---------------------------------------------------------------------------
-- Item / game info
---------------------------------------------------------------------------
local function ItemName(id)
    local name = C_Item and C_Item.GetItemNameByID and Safe(C_Item.GetItemNameByID, id)
    if not name and GetItemInfo then
        name = Safe(GetItemInfo, id)
    end
    if not name then
        if C_Item and C_Item.RequestLoadItemDataByID then
            Safe(C_Item.RequestLoadItemDataByID, id)
        end
        name = ItemDB and Safe(ItemDB.name, id)
    end
    return name or ("item " .. id)
end

local function ItemInstant(id)
    local f = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if not f then
        return nil
    end
    local ok, _, itemType, subType, _, icon, classID = pcall(f, id)
    if ok then
        return classID, icon, itemType, subType
    end
end

local function Icon(id, size)
    local _, icon = ItemInstant(id or 0)
    if not icon then
        return ""
    end
    size = size or 14
    return ("|T%s:%d:%d:0:-1:64:64:5:59:5:59|t "):format(icon, size, size)
end

local function QualityColor(id)
    local q = C_Item and C_Item.GetItemQualityByID and Safe(C_Item.GetItemQualityByID, id)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    return c and c.hex or "|cffffffff"
end

local function RequiredLevel(id)
    local f = C_Item and C_Item.GetItemInfo or GetItemInfo
    if not f then
        return nil
    end
    local ok, _, _, _, _, minLevel = pcall(f, id)
    return ok and type(minLevel) == "number" and minLevel > 1 and minLevel or nil
end

-- colour for a required level vs the player's level (quest-difficulty style)
local function LevelColor(req)
    if not req then
        return "|cffffffff"
    end
    if req > UnitLevel("player") then
        return "|cffff2020"
    end
    if GetQuestDifficultyColor then
        local c = Safe(GetQuestDifficultyColor, req)
        if c and c.r then
            return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
        end
    end
    return "|cff40bf40"
end

local function QuestName(id)
    return (QuestDB and Safe(QuestDB.name, id))
        or (C_QuestLog and C_QuestLog.GetTitleForQuestID and Safe(C_QuestLog.GetTitleForQuestID, id))
        or ("quest " .. id)
end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        return Safe(C_Spell.GetSpellName, id)
    end
    return GetSpellInfo and Safe(GetSpellInfo, id)
end

local function ProfessionName(line)
    if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
        local n = Safe(C_TradeSkillUI.GetTradeSkillDisplayName, line)
        if n and n ~= "" then
            return n
        end
    end
    return PROFESSIONS[line] or ("Profession " .. tostring(line))
end

local function RecipeName(r)
    return (r.item and ItemName(r.item)) or SpellName(r.spellID) or r.name or ("recipe " .. r.spellID)
end

---------------------------------------------------------------------------
-- Player skill / difficulty / known
---------------------------------------------------------------------------
local function PlayerSkill(line)
    if GetProfessions and GetProfessionInfo then
        local profs = { GetProfessions() }
        for i = 1, 6 do
            if profs[i] then
                local _, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(profs[i])
                if skillLine == line then
                    return rank, maxRank
                end
            end
        end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        local want = PROFESSIONS[line]
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
            if not isHeader and name == want then
                return rank, maxRank
            end
        end
    end
end

local function Difficulty(r, rank)
    if not rank then
        return "none"
    end
    if rank < (r.skill or 1) then
        return "red"
    end
    if not r.yellow or not r.gray then
        return "orange"
    end
    local green = math.floor((r.yellow + r.gray) / 2)
    if rank < r.yellow then
        return "orange"
    elseif rank < green then
        return "yellow"
    elseif rank < r.gray then
        return "green"
    end
    return "gray"
end

local function IsKnown(spellID)
    if IsPlayerSpell and Safe(IsPlayerSpell, spellID) then
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Recipe index (Ext/Recipes.lua)
---------------------------------------------------------------------------
local function Normalize(spellID, r)
    local reagents = {}
    if type(r.reagents) == "string" then
        for id, n in r.reagents:gmatch("(%d+):(%d+)") do
            reagents[#reagents + 1] = { tonumber(id), tonumber(n) }
        end
    elseif type(r.reagents) == "table" then
        for i = 1, #r.reagents, 2 do
            reagents[#reagents + 1] = { r.reagents[i], r.reagents[i + 1] }
        end
    end
    return {
        spellID = spellID, item = r.item, profession = r.profession, skill = r.skill,
        yellow = r.yellow, gray = r.gray, count = r.count or 1, reagents = reagents,
        name = r.name, recipeItem = r.recipeItem, recipeItemBound = r.recipeItemBound,
    }
end

local function Index()
    if index then
        return index
    end
    local all = {}
    for id, r in pairs(ns.Database and ns.Database.Recipes or {}) do
        all[id] = Normalize(id, r)
    end

    -- skill lines that are in the recipe data but are not treated as professions here
    for id, r in pairs(all) do
        if HIDDEN_PROFESSIONS[r.profession or 0] then
            all[id] = nil
        end
    end

    index = { reagentFor = {}, craftedBy = {}, taughtBy = {} }
    local function add(t, k, r)
        t[k] = t[k] or {}
        t[k][#t[k] + 1] = r
    end
    for _, r in pairs(all) do
        for _, rg in ipairs(r.reagents) do
            add(index.reagentFor, rg[1], r)
        end
        if r.item then
            add(index.craftedBy, r.item, r)
        end
        if r.recipeItem then
            add(index.taughtBy, r.recipeItem, r)
        end
    end
    return index
end

local function ItemCategory(id)
    local class = ItemInstant(id)
    if class == 9 then
        return "Recipe"
    elseif class == 12 then
        return "Quest Item"
    elseif Index().reagentFor[id] or class == 7 then
        return "Reagent"
    elseif class == 2 or class == 4 then
        return "Equipment"
    end
    return "Other"
end

---------------------------------------------------------------------------
-- Locations (QuestieDB) and TomTom
---------------------------------------------------------------------------
local function UiMap(areaId)
    if QuestieLoader and QuestieLoader.ImportModule then
        local ZoneDB = Safe(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
        if ZoneDB and ZoneDB.GetUiMapIdByAreaId then
            local m = Safe(ZoneDB.GetUiMapIdByAreaId, ZoneDB, areaId)
            if m and m > 0 then
                return m
            end
        end
    end
    if not zoneMap then
        zoneMap = {}
        local support = LibQuestieDB and LibQuestieDB.Support
        local zdb = support and Safe(support.Get, "ZoneDB")
        local p = zdb and zdb.private
        if p then
            for _, key in ipairs({ "areaIdToUiMapId", "areaIdToUiMapIdOverride" }) do
                local chunk = type(p[key]) == "string" and loadstring(p[key])
                local t = chunk and Safe(chunk)
                if type(t) == "table" then
                    for k, v in pairs(t) do
                        zoneMap[k] = v
                    end
                end
            end
        end
    end
    local m = zoneMap[areaId]
    return m and m > 0 and m or nil
end

local function MyFaction()
    return UnitFactionGroup("player") == "Horde" and "H" or "A"
end

-- source: NpcDB or ObjectDB; returns { name, sub, friendly, loc = { map, x, y } }
local function Where(source, id)
    if not source then
        return nil
    end
    local here = C_Map and C_Map.GetBestMapForUnit and Safe(C_Map.GetBestMapForUnit, "player")
    local spawns = Safe(source.spawns, id)
    local best
    if type(spawns) == "table" then
        for areaId, coords in pairs(spawns) do
            local c = coords[1]
            if c and c[1] and c[1] >= 0 then
                local m = UiMap(areaId)
                if m and (not best or m == here) then
                    best = { map = m, x = c[1], y = c[2] }
                    if m == here then
                        break
                    end
                end
            end
        end
    end
    local faction = Safe(source.friendlyToFaction, id)
    return {
        name = Safe(source.name, id) or ("#" .. id),
        sub = Safe(source.subName, id),
        friendly = not faction or faction:find(MyFaction(), 1, true) ~= nil,
        loc = best,
    }
end

local function SetWaypoint(map, x, y, label)
    if ns.Travel then
        ns.Travel(map, x, y, label)
        return
    end
    if not (TomTom and TomTom.AddWaypoint) then
        ns.Print("TomTom is not loaded - go to " .. label .. (" (%.0f, %.0f)"):format(x, y))
        return
    end
    TomTom:AddWaypoint(map, x / 100, y / 100, { title = label, crazy = true, from = ns.ADDON_NAME })
    ns.Print("Arrow set: " .. label)
end

---------------------------------------------------------------------------
-- World distances (for "nearest" spawns)
---------------------------------------------------------------------------
local mapXf = {}

-- affine map->world transform per uiMap: { continent, ox, oy, ax, ay, bx, by }
local function MapXf(map)
    local xf = mapXf[map]
    if xf == nil then
        xf = false
        if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
            local ok0, c0, p0 = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(0, 0))
            local ok1, c1, p1 = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(1, 0))
            local ok2, c2, p2 = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(0, 1))
            if ok0 and ok1 and ok2 and c0 and p0 and p1 and p2 and c0 == c1 and c0 == c2 then
                xf = { c0, p0.x, p0.y, p1.x - p0.x, p1.y - p0.y, p2.x - p0.x, p2.y - p0.y }
            end
        end
        mapXf[map] = xf
    end
    return xf or nil
end

local function World(map, x, y) -- x, y in 0..1
    local xf = MapXf(map)
    if xf then
        return xf[1], xf[2] + x * xf[4] + y * xf[6], xf[3] + x * xf[5] + y * xf[7]
    end
end

local function PlayerWorld()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then
        return nil
    end
    local ok, c, wx, wy = pcall(function()
        local map = C_Map.GetBestMapForUnit("player")
        local pos = map and C_Map.GetPlayerMapPosition(map, "player")
        if pos then
            return World(map, pos:GetXY())
        end
    end)
    if ok and c then
        return c, wx, wy
    end
end

local function ZoneName(map)
    local mi = C_Map and Safe(C_Map.GetMapInfo, map)
    return mi and mi.name or ("Map " .. map)
end

local function Yards(d)
    return d < 1000 and ("%d Yds"):format(d) or ("%.1fk Yds"):format(d / 1000)
end

---------------------------------------------------------------------------
-- Where items come from (QuestieDB spawns)
---------------------------------------------------------------------------
-- calls fn(name, kind, uiMap, x, y) for every known spawn (x, y in 0-100)
---------------------------------------------------------------------------
-- Fishing: where each fish is caught. Questie has no data for open-water fishing, so this is a hand-made
-- table: one well-known fishing place per zone (approximate coordinates, 0-100), keyed by Questie area id,
-- and for each fish the zones whose inland ("i") or coastal ("c") water holds it.
---------------------------------------------------------------------------
local WATER = {
    [1] = { i = { 35, 43, "Iceflow Lake" } },
    [12] = { i = { 53, 66, "Crystal Lake" } },
    [141] = { i = { 59, 63, "Lake Al'Ameth" }, c = { 56, 92, "Rut'theran Village" } },
    [14] = { c = { 59, 78, "Coast by Sen'jin Village" } },
    [215] = { i = { 43, 55, "Stonebull Lake" } },
    [85] = { i = { 67, 45, "Brightwater Lake" } },
    [40] = { c = { 29, 48, "Longshore" } },
    [38] = { i = { 50, 40, "The Loch" } },
    [148] = { c = { 36, 44, "Auberdine" } },
    [130] = { i = { 66, 42, "Lordamere Lake" } },
    [17] = { i = { 45, 23, "Lushwater Oasis" }, c = { 64, 37, "Ratchet" } },
    [44] = { i = { 38, 55, "Lake Everstill" } },
    [11] = { c = { 8, 59, "Menethil Harbor" } },
    [267] = { c = { 51, 63, "Southshore" } },
    [331] = { i = { 48, 68, "Mystral Lake" }, c = { 12, 28, "Zoram Strand" } },
    [406] = { i = { 50, 42, "Mirkfallon Lake" } },
    [36] = { i = { 19, 78, "Lordamere Lake" } },
    [45] = { c = { 32, 82, "Faldir's Cove" } },
    [33] = { i = { 42, 20, "Lake Nazferiti" }, c = { 27, 77, "Booty Bay" } },
    [405] = { c = { 22, 73, "Shadowprey Village" } },
    [15] = { c = { 70, 50, "Theramore" } },
    [8] = { i = { 70, 45, "Pool of Tears" } },
    [47] = { c = { 78, 80, "Revantusk Village" } },
    [440] = { c = { 68, 23, "Steamwheedle Port" } },
    [357] = { i = { 73, 44, "Wildwind Lake" }, c = { 45, 45, "The Forgotten Coast" } },
    [16] = { c = { 47, 60, "Bay of Storms" } },
    [361] = { i = { 41, 47, "Bloodvenom Falls" } },
    [28] = { i = { 63, 78, "Darrowmere Lake" } },
    [139] = { i = { 58, 72, "Lake Mereldar" } },
    [618] = { i = { 32, 36, "Frostfire Hot Springs" } },
    [493] = { i = { 52, 45, "Lake Elune'ara" } },
}
-- [fish item] = { water kind, { area ids }, note }
local FISH = {
    [6291] = { "i", { 12, 1, 141, 215, 85 } }, -- Raw Brilliant Smallfish
    [6303] = { "c", { 141, 14, 40, 148 } }, -- Raw Slitherskin Mackerel
    [6289] = { "i", { 38, 130, 17, 44 } }, -- Raw Longjaw Mud Snapper
    [6317] = { "i", { 38, 130, 44 } }, -- Raw Loch Frenzy
    [6308] = { "i", { 44, 331, 406 } }, -- Raw Bristle Whisker Catfish
    [6361] = { "c", { 40, 148, 17, 267, 11 } }, -- Raw Rainbow Fin Albacore
    [6358] = { "c", { 40, 148, 17, 267, 11, 331 } }, -- Oily Blackmouth
    [6359] = { "c", { 267, 11, 45, 33, 405, 15 } }, -- Firefin Snapper
    [6362] = { "c", { 11, 267, 45, 33, 405, 15 } }, -- Raw Rockscale Cod
    [21071] = { "i", { 38, 130, 17, 406, 331 } }, -- Raw Sagefish
    [21153] = { "i", { 36, 33 } }, -- Raw Greater Sagefish
    [8365] = { "i", { 36, 33, 8 } }, -- Raw Mithril Head Trout
    [4603] = { "c", { 33, 440, 357, 47, 16 } }, -- Raw Spotted Yellowtail
    [13754] = { "c", { 440, 357, 47, 16 } }, -- Raw Glossy Mightfish
    [13756] = { "c", { 440, 357, 47, 16 }, "Summer" }, -- Raw Summer Bass
    [13755] = { "c", { 440, 357, 47, 16 }, "Winter" }, -- Winter Squid
    [13422] = { "c", { 440, 357, 47, 16 } }, -- Stonescale Eel
    [13758] = { "i", { 357, 361, 28 } }, -- Raw Redgill
    [13759] = { "i", { 357, 361, 28, 493 }, "Night" }, -- Raw Nightfin Snapper
    [13760] = { "i", { 357, 361, 28, 493 }, "Day" }, -- Raw Sunscale Salmon
    [13889] = { "i", { 618, 139 } }, -- Raw Whitescale Salmon
    [13888] = { "c", { 16 } }, -- Darkclaw Lobster
    [13893] = { "c", { 16 } }, -- Large Raw Mightfish
    [6522] = { "i", { 17 } }, -- Deviate Fish
}

-- fn(name, "Fish", uiMap, x, y) for every place the fish is caught
local function ForEachFishingSpot(id, fn)
    local f = FISH[id]
    if not f then
        return
    end
    for _, area in ipairs(f[2]) do
        local w = WATER[area] and WATER[area][f[1]]
        local m = w and UiMap(area)
        if m then
            fn(w[3] .. (f[3] and (" (" .. f[3] .. ")") or ""), "Fish", m, w[1], w[2])
        end
    end
end

local function ForEachSpawn(id, fn)
    ForEachFishingSpot(id, fn)
    if not ItemDB then
        return
    end
    local scanned = 0
    local function scan(source, ids, kind, friendlyOnly)
        if not source or type(ids) ~= "table" then
            return
        end
        for _, sid in ipairs(ids) do
            scanned = scanned + 1
            if scanned > MAX_SCAN then
                return
            end
            local name = Safe(source.name, sid)
            local ok = name ~= nil
            if ok and kind == "Gather" then
                -- chests and other lockboxes hold the item now and then: not something you can farm
                local low = tostring(name):lower()
                for _, word in ipairs({ "chest", "footlocker", "strongbox", "lockbox", "coffer", "trunk", "treasure" }) do
                    if low:find(word, 1, true) then
                        ok = false
                        break
                    end
                end
            end
            if ok and friendlyOnly then
                local f = Safe(source.friendlyToFaction, sid)
                ok = not f or f:find(MyFaction(), 1, true) ~= nil
            end
            local spawns = ok and Safe(source.spawns, sid)
            if type(spawns) == "table" then
                for areaId, coords in pairs(spawns) do
                    local m = type(coords) == "table" and UiMap(areaId)
                    if m then
                        for _, xy in ipairs(coords) do
                            if type(xy) == "table" and type(xy[1]) == "number" and type(xy[2]) == "number" and xy[1] >= 0 then
                                fn(name, kind, m, xy[1], xy[2])
                            end
                        end
                    end
                end
            end
        end
    end
    scan(NpcDB, Safe(ItemDB.vendors, id), "Vendor", true)
    scan(NpcDB, Safe(ItemDB.npcDrops, id), "Drop")
    scan(ObjectDB, Safe(ItemDB.objectDrops, id), "Gather")
end

-- nearest spawn per (kind, name, zone): { name, kind, map, x, y, dist (yards, same continent) }, nearest first
local spotCache = {}

local function Spots(id)
    local cached = spotCache[id]
    if cached and GetTime() - cached.t < 10 then
        return cached.list
    end
    local found, byKey = {}, {}
    local pc, px, py = PlayerWorld()
    ForEachSpawn(id, function(name, kind, m, x, y)
        local d
        if pc then
            local wc, wx, wy = World(m, x / 100, y / 100)
            if wc == pc then
                d = math.sqrt((wx - px) ^ 2 + (wy - py) ^ 2)
            end
        end
        local key = kind .. "|" .. name .. "|" .. m
        local at = byKey[key]
        local spot = { name = name, kind = kind, map = m, x = x, y = y, dist = d }
        if not at then
            found[#found + 1] = spot
            byKey[key] = #found
        elseif d and (not found[at].dist or d < found[at].dist) then
            found[at] = spot
        end
    end)
    table.sort(found, function(a, b)
        if a.dist and b.dist then
            return a.dist < b.dist
        elseif a.dist or b.dist then
            return a.dist ~= nil
        end
        return a.name < b.name
    end)
    -- a crafted item whose recipe you haven't learned and a trainer teaches: the trainers, after the
    -- real sources (so "nearest source" stays a place where the item itself can be had)
    local seen = {}
    for _, r in ipairs(ns.Trainers and Index().craftedBy[id] or {}) do
        if not r.recipeItem and r.profession and not seen[r.profession] and not ns.IsKnown(r.spellID) then
            seen[r.profession] = true
            local n = 0
            for _, t in ipairs(ns.Trainers(r.profession, r.skill)) do
                if t.ok and n < 5 then -- only trainers able to teach at this skill level
                    n = n + 1
                    found[#found + 1] = { name = t.name .. (t.sub and (" <" .. t.sub .. ">") or ""), kind = "Trainer",
                        map = t.map, x = t.x, y = t.y, dist = t.dist }
                end
            end
        end
    end
    spotCache[id] = { t = GetTime(), list = found }
    return found
end

-- all spawns grouped by zone, for the side map: { [uiMap] = { { name, kind, x, y }, ... } }
local function MapPoints(id)
    local byMap = {}
    ForEachSpawn(id, function(name, kind, m, x, y)
        local t = byMap[m] or {}
        byMap[m] = t
        if #t < MAX_MAP_POINTS then
            t[#t + 1] = { name = name, kind = kind, x = x, y = y }
        end
    end)
    return byMap
end

---------------------------------------------------------------------------
-- Profession trainers (QuestieDB: TRAINER npc flag + title such as "Expert Blacksmith")
---------------------------------------------------------------------------
local TRAINER_WORDS = {
    [129] = { "first aid", "surgeon", "physician" }, [164] = { "blacksmith" }, [165] = { "leatherwork" },
    [171] = { "alchem" }, [182] = { "herbalis" }, [185] = { "cooking", "chef", "cook" }, [186] = { "mining", "miner" },
    [197] = { "tailor" }, [202] = { "engineer" }, [333] = { "enchant" }, [356] = { "fishing", "fisherman", "angler" },
    [393] = { "skinn" }, [755] = { "jewelcraft" }, [773] = { "inscription", "scribe" },
}
local trainerIndex -- { [profession] = { npcId, ... } }

local function TrainerIndex()
    if trainerIndex then
        return trainerIndex
    end
    trainerIndex = {}
    local ids = NpcDB and Safe(NpcDB.GetAllIds)
    if type(ids) ~= "table" then
        return trainerIndex
    end
    for _, id in ipairs(ids) do
        local flags = Safe(NpcDB.npcFlags, id)
        local sub = type(flags) == "number" and math.floor(flags / 16) % 2 == 1 and Safe(NpcDB.subName, id)
        if type(sub) == "string" then
            local low = sub:lower()
            if not low:find("suppl") then
                for prof, words in pairs(TRAINER_WORDS) do
                    for _, w in ipairs(words) do
                        if low:find(w, 1, true) then
                            trainerIndex[prof] = trainerIndex[prof] or {}
                            table.insert(trainerIndex[prof], id)
                            break
                        end
                    end
                end
            end
        end
    end
    return trainerIndex
end

-- trainer rank from the title: apprentice / journeyman 1, expert / plain "Trainer" 2, artisan / master 3
local function TrainerTier(sub)
    local low = (sub or ""):lower()
    if low:find("artisan") or low:find("master") or low:find("grand") then
        return 3
    elseif low:find("expert") or low:find("trainer") then
        return 2
    end
    return 1
end

-- friendly trainers for a profession, best first: able to teach the recipe's skill, then nearest
local function Trainers(prof, skill)
    local need = (skill or 0) >= 200 and 3 or (skill or 0) >= 125 and 2 or 1
    local pc, px, py = PlayerWorld()
    local out = {}
    for _, id in ipairs(TrainerIndex()[prof] or {}) do
        local f = Safe(NpcDB.friendlyToFaction, id)
        if not f or f:find(MyFaction(), 1, true) then
            local sub = Safe(NpcDB.subName, id)
            local best
            local spawns = Safe(NpcDB.spawns, id)
            for areaId, coords in pairs(type(spawns) == "table" and spawns or {}) do
                local m = type(coords) == "table" and UiMap(areaId)
                for _, xy in ipairs(m and coords or {}) do
                    if type(xy) == "table" and type(xy[1]) == "number" and xy[1] >= 0 then
                        local d
                        if pc then
                            local wc, wx, wy = World(m, xy[1] / 100, xy[2] / 100)
                            if wc == pc then
                                d = math.sqrt((wx - px) ^ 2 + (wy - py) ^ 2)
                            end
                        end
                        if not best or (d and (not best.dist or d < best.dist)) then
                            best = { map = m, x = xy[1], y = xy[2], dist = d }
                        end
                    end
                end
            end
            if best then
                best.name, best.sub, best.ok = Safe(NpcDB.name, id) or ("#" .. id), sub, TrainerTier(sub) >= need
                out[#out + 1] = best
            end
        end
    end
    table.sort(out, function(a, b)
        if a.ok ~= b.ok then
            return a.ok
        end
        if a.dist and b.dist then
            return a.dist < b.dist
        elseif a.dist or b.dist then
            return a.dist ~= nil
        end
        return a.name < b.name
    end)
    return out
end

ns.Trainers = Trainers -- (used by Spots above; on ns: this file is at Lua's limit of top-level locals)

local function HasSources(id)
    if FISH[id] then
        return true
    end
    if not ItemDB then
        return false
    end
    for _, key in ipairs({ "npcDrops", "objectDrops", "vendors" }) do
        local t = Safe(ItemDB[key], id)
        if type(t) == "table" and #t > 0 then
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Small text helpers
---------------------------------------------------------------------------
local L

local function add(s)
    L[#L + 1] = s
end

local function gap()
    if #L > 0 and L[#L] ~= " " then
        add(" ")
    end
end



local function Section(text, note)
    gap()
    add(BAR .. C_GOLD .. text .. "|r" .. (note and ("  " .. C_DIM .. note .. "|r") or ""))
end

-- toggle state with a default
local function IsOn(key, default)
    local v = toggles[key]
    if v == nil then
        return default
    end
    return v
end

local function ItemLink(id, color, size)
    return ("%s|Haddon:Helper:sel:item:%d|h%s%s|r|h"):format(Icon(id, size or 14), id, color or "|cffffffff",
        ns.Escape(ItemName(id)))
end

local function MapLink(id, map)
    return ("|Haddon:Helper:map:%d:%d|h%s|h"):format(id, map or 0, MAPICON)
end

-- yards from the player to a {map, x, y} (0-100 coords); nil on another continent
local function Dist(loc)
    if not loc then
        return nil
    end
    if loc.dist then
        return loc.dist
    end
    local pc, px, py = PlayerWorld()
    if not pc then
        return nil
    end
    local wc, wx, wy = World(loc.map, loc.x / 100, loc.y / 100)
    if wc == pc then
        return math.sqrt((wx - px) ^ 2 + (wy - py) ^ 2)
    end
end

-- "pin Action Name <Title>  Zone (x, y)" for a card source line; returns text, distance text
local function PlaceText(info, action)
    local who = "|cffffffff" .. info.name .. "|r" .. (info.sub and (" " .. C_DIM .. "<" .. info.sub .. ">|r") or "")
    if not info.loc then
        return ("%s%s|r %s  %s- No Map Position|r"):format(C_DIM, action, who, C_DIM), ""
    end
    local link = ("|Haddon:Helper:way:%d:%.2f:%.2f:%s|h%s|h"):format(
        info.loc.map, info.loc.x, info.loc.y, Clean(info.name .. " - " .. action), ARROW)
    local d = Dist(info.loc)
    return ("%s %s%s|r %s  %s%s (%.0f, %.0f)|r"):format(link, C_DIM, action, who, C_SOFT, ZoneName(info.loc.map),
        info.loc.x, info.loc.y), d and (C_DIM .. Yards(d) .. "|r") or ""
end

local profIconCache = {}

-- profession filter: yours, or every profession when the "All Professions" setting is on
local function Shown(p)
    return p ~= nil and (ns.Get("allProfs") or PlayerSkill(p) ~= nil)
end

local function ProfIcon(line, size)
    size = size or 16
    local tex = profIconCache[line] or (PROF_ICONS[line] and ("Interface\\Icons\\" .. PROF_ICONS[line]))
    if not tex then
        tex = false
        if GetProfessions and GetProfessionInfo then
            local profs = { GetProfessions() }
            for i = 1, 6 do
                if profs[i] then
                    local _, icon, _, _, _, _, skillLine = GetProfessionInfo(profs[i])
                    if skillLine == line and icon then
                        tex = icon
                    end
                end
            end
        end
        profIconCache[line] = tex or nil
    end
    return tex and ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t "):format(tex, size, size) or ""
end

-- skill-up icon for a recipe difficulty (lock when skill too low, nothing when gray)
local atlasOk = {}

local function SkillIcon(diff, size)
    size = size or 14
    if diff == "red" then
        -- locked: your skill is too low for the recipe. Always a grey padlock
        return ("|T%s:%d:%d:0:-1:64:64:0:64:0:64:153:153:153|t"):format(ns.Tex("Lock"), size, size)
    end
    if diff == "gray" then
        return "" -- no skill-up: no icon (only orange / yellow / green get an arrow)
    end
    local s = SKILLUP[diff]
    if not s then
        return ""
    end
    if atlasOk[s[1]] == nil then
        atlasOk[s[1]] = (C_Texture and C_Texture.GetAtlasInfo and Safe(C_Texture.GetAtlasInfo, s[1])) and true or false
    end
    if atlasOk[s[1]] then
        return ("|A:%s:%d:%d:0:-1|a"):format(s[1], size, size)
    end
    local arrow = ("|TInterface\\Buttons\\Arrow-Up-Up:%d:%d:0:-1:32:32:0:32:0:32:%d:%d:%d|t"):format(
        size, math.floor(size * 0.6), s[3], s[4], s[5])
    return arrow:rep(s[2])
end

local function Learned(known, size, plain)
    size = size or 14
    local tex = ("|TInterface\\RaidFrame\\ReadyCheck-%s:%d:%d:0:-1|t"):format(known and "Ready" or "NotReady", size, size)
    if plain then
        return tex
    end
    return ("|Haddon:Helper:tip:learned:%d|h%s|h"):format(known and 1 or 0, tex)
end

-- reagent availability (bags + bank): green = enough, yellow = some, gray = none
local HAVE = { green = "|cff6fd16f", yellow = "|cffe6b84a", gray = "|cff6b7280" }

-- How many of an item you have. One redraw asks this thousands of times (every reagent of every recipe,
-- more so with the "can craft now" filter or all professions shown), so answers are kept for a quarter
-- of a second instead of asking the game each time.
local haveCache, haveAt, haveBank = {}, 0, nil
local function Have(id)
    local bank = ns.Get("includeBank") and true or false
    local now = GetTime()
    if now - haveAt > 0.25 or bank ~= haveBank then
        wipe(haveCache)
        haveAt, haveBank = now, bank
    end
    local v = haveCache[id]
    if v == nil then
        if C_Item and C_Item.GetItemCount then
            v = Safe(C_Item.GetItemCount, id, bank, false, bank, bank) or 0
        else
            v = GetItemCount and Safe(GetItemCount, id, bank) or 0
        end
        haveCache[id] = v
    end
    return v
end

-- (bags, bank) counts
local function HaveSplit(id)
    local bags = 0
    if C_Item and C_Item.GetItemCount then
        bags = Safe(C_Item.GetItemCount, id, false, false, false, false) or 0
    elseif GetItemCount then
        bags = Safe(GetItemCount, id, false) or 0
    end
    local total = Have(id)
    return bags, math.max(total - bags, 0)
end

local BAG_ICON = "|TInterface\\Buttons\\Button-Backpack-Up:13:13|t"
local BANK_ICON = "|TInterface\\Icons\\INV_Box_02:13:13:0:0:64:64:5:59:5:59|t"

-- Bags / Bank columns for the reagent list (0 shown dimmed)
local function Columns(id)
    local bags, bank = HaveSplit(id)
    local function n(v)
        return (v > 0 and "|cffffffff" or C_DIM) .. v .. "|r"
    end
    if ns.Get("includeBank") then
        return { n(bags), n(bank) }
    end
    return { "", n(bags) } -- bank not counted: no bank column, the bag count takes the right-hand place
end

-- tooltip line with only the non-zero places
local function SplitTooltip(id)
    local bags, bank = HaveSplit(id)
    local left = bags > 0 and ("Bags  " .. bags .. " " .. BAG_ICON) or ""
    local right = ns.Get("includeBank") and bank > 0 and ("Bank  " .. bank .. " " .. BANK_ICON) or ""
    if left ~= "" or right ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(left ~= "" and left or right, left ~= "" and right or "", 1, 1, 1, 1, 1, 1)
    end
end

local function ReagentState(have, need)
    if have >= need then
        return "green"
    end
    return have > 0 and "yellow" or "gray"
end

local function RecipeState(r)
    if #r.reagents == 0 then
        return "gray"
    end
    local full, some = 0, 0
    for _, rg in ipairs(r.reagents) do
        local st = ReagentState(Have(rg[1]), rg[2])
        if st == "green" then
            full = full + 1
        elseif st == "yellow" then
            some = some + 1
        end
    end
    if full == #r.reagents then
        return "green"
    end
    return (full + some) > 0 and "yellow" or "gray"
end

local function Money(c)
    return ns.Money(c)
end

-- vendor price: exact if seen at a merchant (HelperDB.prices), else ~4x the sell price
local function BuyPrice(id)
    local seen = db.prices and db.prices[id]
    if seen then
        return Money(seen)
    end
    local f = C_Item and C_Item.GetItemInfo or GetItemInfo
    if f then
        local ok, _, _, _, _, _, _, _, _, _, _, sell = pcall(f, id)
        if ok and type(sell) == "number" and sell > 0 then
            return Money(sell * 4)
        end
    end
end

-- collapsible groups per area ("list" = left menu, "detail" = right side), for Collapse / Expand All
local areaKeys = { list = {}, detail = {} }

local function Group(area, key)
    areaKeys[area][key] = true
    return IsOn(key, true)
end

local function AnyOpen(area)
    for key in pairs(areaKeys[area]) do
        if IsOn(key, true) then
            return true
        end
    end
    return false
end

-- how to learn the recipe, as rows for the card's learn panel: { left text, right text }
local function LearnRows(r)
    local rows = {}
    local function Src(info, action)
        local text, dist = PlaceText(info, action)
        rows[#rows + 1] = { text, dist }
    end
    if not r.recipeItem then
        local rank = PlayerSkill(r.profession)
        local short = rank and r.skill and rank < r.skill
        rows[1] = { "|cffffffffTrainer|r",
            r.skill and ((short and "|cffff4040" or C_DIM) .. "Requires Skill Level " .. r.skill .. "|r") or "" }
        local trainers = r.profession and Trainers(r.profession, r.skill) or {}
        for i = 1, math.min(#trainers, MAX_SOURCES) do
            local t = trainers[i]
            Src({ name = t.name, sub = t.sub, loc = t }, "Trainer")
        end
        if #trainers == 0 then
            rows[#rows + 1] = { C_DIM .. "No Trainer Location Known|r", "" }
        end
        return rows
    end
    local vendors = ItemDB and Safe(ItemDB.vendors, r.recipeItem)
    local price = vendors and BuyPrice(r.recipeItem)
    rows[1] = { ItemLink(r.recipeItem, QualityColor(r.recipeItem))
        .. (r.recipeItemBound and ("  " .. C_DIM .. "Bind on Pickup|r") or ""), price or "" }
    if not ItemDB then
        return rows
    end
    local shown = 0
    for _, npc in ipairs(vendors or {}) do
        local info = Where(NpcDB, npc)
        if info and info.friendly and shown < MAX_SOURCES then
            Src(info, "Buy from")
            shown = shown + 1
        end
    end
    if vendors and shown == 0 then
        rows[#rows + 1] = { C_DIM .. "Only Sold by the Other Faction|r", "" }
    elseif not vendors then
        local drops = Safe(ItemDB.npcDrops, r.recipeItem)
        for i = 1, math.min(#(drops or {}), MAX_SOURCES) do
            local info = Where(NpcDB, drops[i])
            if info then
                Src(info, "Drops from")
            end
        end
        if not drops then
            rows[#rows + 1] = { C_DIM .. "No Vendor or Drop Known|r", "" }
        end
    end
    return rows
end

-- how many times you can craft it now (0 if any reagent is short)
local function MaxCrafts(r)
    local n
    for _, rg in ipairs(r.reagents) do
        local c = math.floor(Have(rg[1]) / math.max(rg[2], 1))
        n = n and math.min(n, c) or c
    end
    return n or 0
end

-- availability tag: "Craft xN" (green) or "Partial" (yellow); nothing when you have none.
-- craftable + learned: a hammer button that opens the profession on this recipe
local CRAFT = "|T" .. MEDIA .. "Craft:14:14:0:-1|t"
local CRAFT_OFF = "|T" .. MEDIA .. "CraftOff:14:14:0:-1|t" -- not learned: greyed out

local function CraftTag(r, known, plain)
    local st = RecipeState(r)
    if st == "green" then
        local n = MaxCrafts(r)
        local can = known and PlayerSkill(r.profession) ~= nil
        local icon = can and CRAFT or CRAFT_OFF
        if not plain then
            icon = ("|Haddon:Helper:craft:%d:%d:%d:%d|h%s|h"):format(r.spellID, r.profession or 0, n, can and 1 or 0, icon)
        end
        return "  " .. icon .. " " .. HAVE.green .. "x " .. n .. "|r"
    end
    return ""
end

-- rarity of the recipe itself (its Recipe / Pattern / Formula item); trainer recipes use the crafted item
local function RecipeColor(r)
    local id = r.recipeItem or r.item
    return id and QualityColor(id) or "|cffffffff"
end


local recommended -- spellID marked "Recommended" in the current Used In list

local DIFF_SCORE = { orange = 30, yellow = 20, green = 10, gray = 0, red = -50, none = -60 }

local function PickRecommended(recipes)
    local best, bestScore, n = nil, nil, 0
    for _, r in ipairs(recipes or {}) do
        local rank = PlayerSkill(r.profession)
        if rank then
            n = n + 1
            local score = DIFF_SCORE[Difficulty(r, rank)] + (IsKnown(r.spellID) and 100 or 0)
                + (MaxCrafts(r) > 0 and 5 or 0) + (RecipeState(r) == "yellow" and 2 or 0)
            if not bestScore or score > bestScore then
                best, bestScore = r.spellID, score
            end
        end
    end
    return n >= 2 and best or nil
end

local function FindRecipe(spellID)
    for _, t in ipairs({ Index().reagentFor, Index().craftedBy, Index().taughtBy }) do
        for _, list_ in pairs(t) do
            for _, x in ipairs(list_) do
                if x.spellID == spellID then
                    return x
                end
            end
        end
    end
end

-- set the crafts count for a recipe; reagent targets change by need x difference
local function SetFarmCrafts(spellID, n)
    local r = FindRecipe and FindRecipe(spellID)
    if not r then
        return
    end
    db.farmCrafts = db.farmCrafts or {}
    local old = db.farmCrafts[spellID] or 0
    n = math.max(math.floor(n or 0), 0)
    db.farmCrafts[spellID] = n > 0 and n or nil
    local delta = n - old
    if delta ~= 0 and ns.FarmAdjust then
        for _, rg in ipairs(r.reagents) do
            ns.FarmAdjust(rg[1], rg[2] * delta)
        end
    end
    -- farming for a recipe also tracks it in the Crafting window
    if old == 0 and n > 0 and ns.CraftTrack and not ns.CraftTracked(spellID) then
        ns.CraftTrack(spellID, true)
    end
    if ns.RefreshReagents then
        ns.RefreshReagents()
    end
end

-- farm reagents for more / fewer crafts of a recipe; returns the new count (nil = recipe not in the database)
function ns.FarmRecipe(spellID, delta)
    if not (spellID and FindRecipe(spellID)) then
        return nil
    end
    if delta and delta ~= 0 then
        SetFarmCrafts(spellID, (db.farmCrafts and db.farmCrafts[spellID] or 0) + delta)
    end
    return db.farmCrafts and db.farmCrafts[spellID] or 0
end

-- small floating number box for "[N]"
local countBox
local function AskFarmCrafts(spellID)
    if not countBox then
        countBox = ns.CreateEditBox(UIParent)
        countBox:SetSize(60, 22)
        countBox:SetFrameStrata("DIALOG")
        countBox:SetNumeric(true)
        countBox:SetScript("OnEnterPressed", function(self)
            SetFarmCrafts(self.spellID, tonumber(self:GetText()) or 0)
            self:Hide()
        end)
        countBox:SetScript("OnEscapePressed", function(self)
            self:Hide()
        end)
        countBox:SetScript("OnEditFocusLost", function(self)
            self:Hide()
        end)
    end
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    countBox:ClearAllPoints()
    countBox:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale + 30, y / scale)
    countBox.spellID = spellID
    countBox:SetText(tostring(db.farmCrafts and db.farmCrafts[spellID] or 0))
    countBox:Show()
    countBox:SetFocus()
    countBox:HighlightText()
end

local STAR = "|T" .. MEDIA .. "Star:14:14:0:-1|t"

-- one recipe = one real-frame card (built by the "recipe" widget, see Recipe Card below)
local function RecipeCard(r, highlight, withSource)
    add({ widget = "recipe", x = 8, gap = 6,
        data = { r = r, highlight = highlight, withSource = withSource, rec = r.spellID == recommended } })
end

-- recipes grouped by profession (only yours unless allProfs); the recommended recipe first
-- recipe filter of the detail pane (Filter button next to the tabs)
local DETAIL_FILTERS = {
    { title = "Skill Up" },
    { "df_orange", "|cffff8040Orange|r", "Recipes that always give a skill point" },
    { "df_yellow", "|cffffff00Yellow|r", "Recipes that usually give a skill point" },
    { "df_green", "|cff40bf40Green|r", "Recipes that rarely give a skill point" },
    { "df_gray", "|cff999999No Skill Up|r", "Recipes that no longer give skill" },
    { title = "Recipe" },
    { "df_learned", "Learned", "Recipes you know" },
    { "df_unlearned", "Not Learned", "Recipes you could learn now but have not" },
    { "df_red", "Locked", "Recipes your skill level is too low for" },
    { title = "Materials" },
    { "df_mats", "Have Materials", "Only recipes you have every material for" },
}

local function DetailPasses(r)
    -- a recipe is learned, not learned (you could learn it now) or locked (your skill is too low)
    local rank = PlayerSkill(r.profession)
    local diff = rank and Difficulty(r, rank)
    local known = IsKnown(r.spellID)
    if diff == "red" and not known then
        if ns.Get("df_red") == false then
            return false
        end
    else
        if diff and diff ~= "red" and ns.Get("df_" .. diff) == false then
            return false
        end
        if ns.Get(known and "df_learned" or "df_unlearned") == false then
            return false
        end
    end
    if ns.Get("df_mats") and RecipeState(r) ~= "green" then
        return false
    end
    return true
end

local function RecipeGroups(recipes, highlight, keyPrefix, allProfs)
    local groups, order = {}, {}
    local hidden = 0
    for _, r in ipairs(recipes) do
        local p = r.profession or 0
        if (allProfs or Shown(p)) and not DetailPasses(r) then
            hidden = hidden + 1
        elseif allProfs or Shown(p) then
            if not groups[p] then
                groups[p] = {}
                order[#order + 1] = p
            end
            table.insert(groups[p], r)
        end
    end
    table.sort(order, function(a, b)
        return ProfessionName(a) < ProfessionName(b)
    end)
    if hidden > 0 then
        add({ space = 8 })
        add({ text = C_DIM .. hidden .. " recipe(s) hidden by the filter|r", indent = 12 })
        add({ space = 8 })
    end
    for gi, p in ipairs(order) do
        local list_ = groups[p]
        table.sort(list_, function(a, b)
            if (a.spellID == recommended) ~= (b.spellID == recommended) then
                return a.spellID == recommended
            end
            return (a.skill or 0) < (b.skill or 0)
        end)
        local key = keyPrefix .. p
        local open = Group("detail", key)
        local rank = PlayerSkill(p)
        if gi > 1 then
            add({ space = 6 })
        end
        add({ widget = "group", gap = 0, data = { key = key, open = open, name = ProfessionName(p), count = #list_,
            icon = (ProfIcon(p) or ""):match("^|T([^:]+):") } })
        if open then
            add({ space = 5 })
            for _, r in ipairs(list_) do
                RecipeCard(r, highlight, rank ~= nil)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Header card + item details (tabs: Creates / Created By / Where To Find)
---------------------------------------------------------------------------
local TAB_KEYS = { "creates", "created", "where" }
local TAB_NAMES = { creates = "Crafts", created = "Created by", where = "Where to Find?" }
local TAB_ICONS = {
    creates = "Interface\\Icons\\INV_Hammer_20",
    created = "Interface\\Icons\\INV_Scroll_03",
    where = ns.Tex("Pin"),
}
local tabButtons = {}
local detailTab = "creates"

-- selection + history for the Back button
local history = {}
local function Select(kind, id)
    if selected and selected.id ~= id then
        history[#history + 1] = { kind = selected.kind, id = selected.id, tab = detailTab }
        if #history > 50 then
            table.remove(history, 1)
        end
    end
    selected = { kind = kind, id = id }
end

-- the item open in the Reagents tab while it is on screen (the tracker windows highlight its recipes)
function ns.SelectedItem()
    if selected and selected.kind == "item" and panel and panel:IsVisible() then
        return selected.id
    end
end
function ns.TellTrackers() -- (on ns: this file is at Lua's limit of 200 top-level locals)
    local id = ns.SelectedItem()
    if id ~= ns.shownItem then
        ns.shownItem = id
        if ns.RefreshTrackers then
            ns.RefreshTrackers()
        end
    end
end
local collapse = {}

local function SetHeader(iconPath, name, sub, have)
    head.icon:SetTexture(iconPath or "Interface\\Icons\\INV_Misc_QuestionMark")
    head.name:SetText(name or "")
    head.sub:SetText(sub or "")
    -- bag and bank counts (always both, 0 included), big, with their icons; no separate total
    head.haveLabel:Hide()
    if have and selected then
        local bags, bank = HaveSplit(selected.id)
        local function Part(icon, n)
            return ("|T%s|t %s%d|r"):format(icon, n > 0 and "|cffffffff" or C_DIM, n)
        end
        local text = Part("Interface\\Buttons\\Button-Backpack-Up:20:20", bags)
        if ns.Get("includeBank") then
            text = text .. "    " .. Part("Interface\\Icons\\INV_Box_02:20:20:0:0:64:64:5:59:5:59", bank)
        end
        head.have:SetText(text)
    else
        head.have:SetText("")
    end
    -- quality colour from the name's |cAARRGGBB: icon border + soft glow
    local r, g, b = (name or ""):match("^|c%x%x(%x%x)(%x%x)(%x%x)")
    r, g, b = tonumber(r or "a0", 16) / 255, tonumber(g or "a0", 16) / 255, tonumber(b or "a0", 16) / 255
    head.frame:SetBackdropBorderColor(r, g, b, 1)
    ns.Gradient(head.glow, "HORIZONTAL", { r, g, b, 0.18 }, { r, g, b, 0 })
end

local function MyRecipeCount(recipes)
    local n = 0
    for _, r in ipairs(recipes or {}) do
        if Shown(r.profession) then
            n = n + 1
        end
    end
    return n
end

local function RenderCreates(id)
    local idx = Index()
    local taught = idx.taughtBy[id]
    if taught then
        Section("Teaches")
        for _, r in ipairs(taught) do
            RecipeCard(r, nil, false)
        end
    end
    local uses = idx.reagentFor[id]
    recommended = PickRecommended(uses)
    if uses then
        if MyRecipeCount(uses) > 0 then
            RecipeGroups(uses, id, "use:")
        else
            Section(ns.Get("allProfs") and "Not Used by Any Profession" or "Not Used by Your Professions", #uses .. " Recipes in Other Professions")
        end
    end
    local quest = ItemDB and Safe(ItemDB.startQuest, id)
    if quest and quest ~= 0 then
        Section("Starts a Quest")
        if CAPTURE_QUESTS then
            add("  |Haddon:Helper:sel:quest:" .. quest .. "|h|cffffff00[" .. ns.Escape(QuestName(quest)) .. "]|r|h")
        else
            add("  |cffffff00" .. ns.Escape(QuestName(quest)) .. "|r")
        end
    end
end

local function RenderCreated(id)
    RecipeGroups(Index().craftedBy[id] or {}, nil, "made:", true)
end

-- sources grouped by kind, nearest first; each line: pin (TomTom), map (side map), distance, name, zone
local function RenderWhere(id)
    local spots = Spots(id)
    local first = spots[1]
    for _, kind in ipairs(KIND_ORDER) do
        local any = false
        for _, s in ipairs(spots) do
            if s.kind == kind then
                if not any then
                    gap()
                    add(BAR .. KIND_ICON[kind] .. C_GOLD .. KIND_TITLE[kind] .. "|r")
                    any = true
                end
                -- "~" in front of the label: not an NPC (a node or a fishing spot), nothing to target
                local way = ("|Haddon:Helper:way:%d:%.2f:%.2f:%s|h%s|h"):format(s.map, s.x, s.y,
                    ((kind == "Gather" or kind == "Fish") and "~" or "") .. Clean(s.name), ARROW)
                -- name <title> - zone (x, y) - distance - Nearest
                local who, title = s.name:match("^(.-)%s*(<.*>)$")
                local sep = C_DIM .. " - |r"
                add(("    %s %s  %s%s|r%s%s%s%s (%.0f, %.0f)|r%s%s%s|r%s"):format(way, MapLink(id, s.map),
                    C_HEAD, who or s.name, title and (" " .. C_DIM .. title .. "|r") or "", sep,
                    C_SOFT, ZoneName(s.map), s.x, s.y, sep,
                    s.dist and C_HEAD or C_DIM, s.dist and Yards(s.dist) or "Far",
                    s == first and (sep .. C_GOLD .. "Nearest|r") or ""))
            end
        end
    end
end

local function UpdateTabs(counts)
    if not counts[detailTab] or counts[detailTab] == 0 then
        for _, k in ipairs(TAB_KEYS) do
            if (counts[k] or 0) > 0 then
                detailTab = k
                break
            end
        end
    end
    local prev
    for _, k in ipairs(TAB_KEYS) do
        local b, n = tabButtons[k], counts[k] or 0
        local show = k ~= "created" or n > 0 -- raw reagents have no "Created By"
        b:SetShown(show)
        if show then
            b:ClearAllPoints()
            if prev then
                b:SetPoint("LEFT", prev, "RIGHT", 2, 0)
            else
                b:SetPoint("TOPLEFT", head.card, "BOTTOMLEFT", 0, -10)
            end
            prev = b
        end
        b:SetText(("%s  %s(%d)|r"):format(TAB_NAMES[k], C_DIM, n))
        b:SetEnabled(n > 0)
        b:SetSelected(k == detailTab and n > 0)
    end
end

local function RenderItem(id)
    urlBox.url = WOWHEAD:format("item", id)
    local _, icon, itemType, subType = ItemInstant(id)
    local reqLevel = RequiredLevel(id)
    local parts = { C_GOLD .. ItemCategory(id) .. "|r" }
    if itemType and itemType ~= "" then
        parts[#parts + 1] = itemType .. ((subType and subType ~= "" and subType ~= itemType) and (" / " .. subType) or "")
    end
    if reqLevel then
        parts[#parts + 1] = LevelColor(reqLevel) .. "Requires Level " .. reqLevel .. "|r"
    end
    SetHeader(icon, QualityColor(id) .. ns.Escape(ItemName(id)) .. "|r",
        C_SOFT .. table.concat(parts, C_DIM .. "  \194\183  |r" .. C_SOFT) .. "|r", tostring(Have(id)))

    local idx = Index()
    local quest = ItemDB and Safe(ItemDB.startQuest, id)
    local counts = {
        creates = #(idx.taughtBy[id] or {}) + MyRecipeCount(idx.reagentFor[id]) + ((quest and quest ~= 0) and 1 or 0),
        created = #(idx.craftedBy[id] or {}),
        where = #Spots(id),
    }
    UpdateTabs(counts)
    -- header Craft button: when the selected item is something your professions make
    local made
    for _, r in ipairs(idx.craftedBy[id] or {}) do
        if Shown(r.profession) and #r.reagents > 0 and (not made or (IsKnown(r.spellID) and not IsKnown(made.spellID))) then
            made = r
        end
    end
    head.made = made
    head.craft:SetShown(made ~= nil)
    if made then
        local rank = PlayerSkill(made.profession)
        head.crafts = MaxCrafts(made)
        head.craft:SetEnabled(IsKnown(made.spellID) and rank ~= nil and RecipeState(made) == "green"
            and Difficulty(made, rank) ~= "red")
        head.craftWhy = not IsKnown(made.spellID) and "Learn this recipe first" or rank == nil and "You don't have this profession"
            or "Missing reagents"
    end
    head.have:ClearAllPoints()
    head.have:SetPoint("RIGHT", made and head.craft or head.farmBtn, "LEFT", -18, 0)
    head.UpdateFarm()
    if (counts[detailTab] or 0) == 0 then
        if idx.reagentFor[id] then
            RenderCreates(id) -- "not used by your professions"
        else
            gap()
            add("   " .. C_DIM .. "Nothing Known About This Item Yet.|r")
        end
        return
    end
    if detailTab == "creates" then
        RenderCreates(id)
    elseif detailTab == "created" then
        RenderCreated(id)
    else
        RenderWhere(id)
    end
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------
local function IsMyReagent(id)
    for _, r in ipairs(Index().reagentFor[id] or {}) do
        if Shown(r.profession) then
            return true
        end
    end
    return false
end

-- item tooltips (bags etc.): recipes of your professions that use this reagent
-- lock shown in the top-right corner of an item tooltip when the reagent is protected;
-- hidden again whenever the tooltip is cleared or closed
local function ProtectedLock(tt)
    local lock = tt.RFLock
    if not lock then
        lock = tt:CreateTexture(nil, "OVERLAY", nil, 7)
        lock:SetSize(18, 18)
        lock:SetPoint("TOPRIGHT", -7, -7)
        lock:SetTexture(ns.Tex("Lock"))
        lock:SetVertexColor(1, 0.82, 0)
        lock:Hide()
        tt.RFLock = lock
        local function Hide()
            lock:Hide()
        end
        tt:HookScript("OnHide", Hide)
        pcall(tt.HookScript, tt, "OnTooltipCleared", Hide)
    end
    return lock
end

local function ItemTooltip(tt, data)
    if (tt ~= GameTooltip and tt ~= ItemRefTooltip) or (InCombatLockdown and InCombatLockdown()) then
        return
    end
    local id = data and data.id
    if type(id) ~= "number" or (issecretvalue and issecretvalue(id)) then
        return
    end
    if ns.Get("ttProtected") ~= false and ns.IsProtected and ns.IsProtected(id) then
        ProtectedLock(tt):Show() -- gold lock in the tooltip's top-right corner
    end
    if not ns.Get("ttUsedIn") then
        return
    end
    local mine = {}
    for _, r in ipairs(Index().reagentFor[id] or {}) do
        if Shown(r.profession) then
            mine[#mine + 1] = { r = r, diff = Difficulty(r, PlayerSkill(r.profession)) }
        end
    end
    if #mine == 0 then
        return
    end
    table.sort(mine, function(a, b)
        if a.diff ~= b.diff then
            return DIFF_ORDER[a.diff] < DIFF_ORDER[b.diff]
        end
        return (a.r.skill or 0) < (b.r.skill or 0)
    end)
    local max = IsShiftKeyDown() and #mine or ns.Get("ttMax") -- hold Shift for the whole list
    tt:AddLine(" ")
    -- header: an icon for each profession that uses the item
    local profIcons, seenProf = "", {}
    for _, e in ipairs(mine) do
        local p = e.r.profession
        if p and not seenProf[p] then
            seenProf[p] = true
            profIcons = profIcons .. ProfIcon(p, 14)
        end
    end
    tt:AddLine("Used in (" .. #mine .. ")  " .. profIcons, 0.95, 0.75, 0.3)
    for i = 1, math.min(#mine, max) do
        local e = mine[i]
        local need = "?"
        for _, rg in ipairs(e.r.reagents) do
            if rg[1] == id then
                need = rg[2]
            end
        end
        local known = IsKnown(e.r.spellID)
        local skillUp = e.diff ~= "red" and SkillIcon(e.diff, 12) or ""
        -- tick = learned, cross = not learned, grey lock = locked (skill too low)
        local mark = ""
        if ns.Get("ttLearned") ~= false then
            mark = (e.diff == "red" and not known) and SkillIcon("red", 12) or Learned(known, 12, true)
        end
        local left = (ns.Get("ttProfIcons") and ProfIcon(e.r.profession, 12) or "") .. mark
            .. (skillUp ~= "" and skillUp or "|TInterface\\Common\\spacer:12:12|t") .. " |cff999999x" .. need .. "|r  "
            .. RecipeColor(e.r) .. RecipeName(e.r) .. "|r" .. CraftTag(e.r, known, true)
        tt:AddLine(left, 1, 1, 1)
    end
    if #mine > max then
        tt:AddLine("+" .. (#mine - max) .. " More (Shift)", 0.5, 0.5, 0.5)
    end
    tt:AddLine(" ") -- keep clear of whatever follows (quest progress, other addons)
end

local function SpotsTooltip(id)
    local spots = Spots(id)
    if #spots == 0 then
        return
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Where to Find (Nearest First)", 0.95, 0.75, 0.3)
    for i = 1, math.min(#spots, SPOTS_MAX) do
        local s = spots[i]
        GameTooltip:AddDoubleLine(KIND_ICON[s.kind] .. s.name,
            ZoneName(s.map) .. (s.dist and ("  " .. Yards(s.dist)) or ""), 1, 1, 1, 0.7, 0.7, 0.7)
    end
    if #spots > SPOTS_MAX then
        GameTooltip:AddLine("+" .. (#spots - SPOTS_MAX) .. " More", 0.5, 0.5, 0.5)
    end
    GameTooltip:AddLine(ARROW .. " TomTom Arrow    " .. MAPICON .. " Show on Map", 0.5, 0.5, 0.5)
end


local function SkillTip(spellID)
    local r
    for _, list_ in pairs(Index().craftedBy) do
        for _, x in ipairs(list_) do
            if x.spellID == spellID then
                r = x
            end
        end
    end
    for _, list_ in pairs(Index().reagentFor) do
        if r then
            break
        end
        for _, x in ipairs(list_) do
            if x.spellID == spellID then
                r = x
                break
            end
        end
    end
    if not r then
        return
    end
    local diff = Difficulty(r, PlayerSkill(r.profession))
    GameTooltip:SetText(SKILL_TIP[diff] or "Skill")
    local green = r.yellow and r.gray and math.floor((r.yellow + r.gray) / 2)
    GameTooltip:AddLine(("Skill Level: Learn %s  -  |cffffff00Yellow %s|r  -  |cff40bf40Green %s|r  -  |cff808080Gray %s|r"):format(
        tostring(r.skill or "?"), tostring(r.yellow or "?"), tostring(green or "?"), tostring(r.gray or "?")), 1, 1, 1)
    local rank = PlayerSkill(r.profession)
    if rank then
        GameTooltip:AddLine("Your Skill Level: " .. rank, 0.7, 0.7, 0.7)
    end
end

local function OnLinkEnter(owner, link)
    local id = tonumber(link:match("^addon:Helper:sel:item:(%d+)$"))
    local near = tonumber(link:match("^addon:Helper:near:(%d+)$"))
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
    if id then
        GameTooltip:SetItemByID(id)
        SplitTooltip(id)
        SpotsTooltip(id)
    elseif near then
        local s = Spots(near)[1]
        GameTooltip:SetText("TomTom Arrow to the Nearest")
        if s then
            GameTooltip:AddLine(("%s%s - %s%s"):format(KIND_ICON[s.kind], s.name, ZoneName(s.map),
                s.dist and ("  " .. Yards(s.dist)) or ""), 1, 1, 1)
            if ns.ArmTarget then -- close-by NPC: the click also targets and stars it
                ns.ArmTarget(nil, s.map, s.x, s.y, s.name, s.kind == "Gather" or s.kind == "Fish", function()
                    ns.WaypointNearest(near)
                end)
            end
        else
            GameTooltip:AddLine("No Known Location", 0.5, 0.5, 0.5)
        end
    elseif link:find("^addon:Helper:map:") then
        GameTooltip:SetText("Show on Map")
        GameTooltip:AddLine("Opens the side map with every known spawn", 0.7, 0.7, 0.7)
    elseif link:find("^addon:Helper:way:") then
        GameTooltip:SetText("Set Location")
        GameTooltip:AddLine("Can use TomTom arrows", 0.9, 0.9, 0.9, true)
        local map, x, y, label = link:match("^addon:Helper:way:(%d+):([%d%.]+):([%d%.]+):(.*)$")
        if map and ns.ArmTarget then -- close-by NPC: the click also targets and stars it
            local notNpc = label:sub(1, 1) == "~" -- a node or a fishing spot
            label = notNpc and label:sub(2) or label
            map, x, y = tonumber(map), tonumber(x), tonumber(y)
            ns.ArmTarget(nil, map, x, y, label, notNpc, function()
                SetWaypoint(map, x, y, label)
            end)
        end
    elseif link:find("^addon:Helper:craft:") then
        local prof, n, can = link:match("^addon:Helper:craft:%d+:(%d+):(%d+):(%d)$")
        GameTooltip:SetText("Craft  |cff6fd16fx" .. (n or "?") .. "|r")
        if can == "1" then
            GameTooltip:AddLine("Click: Open " .. ProfessionName(tonumber(prof)) .. " On This Recipe", 0.8, 0.8, 0.8)
        else
            GameTooltip:AddLine("You Have the Reagents But Haven't Learned This Recipe", 0.9, 0.35, 0.35)
        end
    elseif link:find("^addon:Helper:tip:learned:") then
        local known = link:sub(-1) == "1"
        GameTooltip:SetText(known and "Learned" or "Not Learned", known and 0.4 or 0.9, known and 0.85 or 0.35, known and 0.4 or 0.35)
    elseif link:find("^addon:Helper:farmr:") then
        GameTooltip:SetText("Farming")
        GameTooltip:AddLine("Click: farm reagents for one more craft (adds to the Farming list)", 0.8, 0.8, 0.8, true)
    elseif link:find("^addon:Helper:farmn:") then
        GameTooltip:SetText("Crafts to Farm for")
        GameTooltip:AddLine("Click to type a number - reagent targets follow it", 0.8, 0.8, 0.8, true)
    elseif link == "addon:Helper:tip:rec" then
        GameTooltip:SetText("Recommended")
        GameTooltip:AddLine("Best use of this reagent for you: learned, best skill-up, craftable now", 0.8, 0.8, 0.8, true)
    elseif link:find("^addon:Helper:tip:skill:") then
        SkillTip(tonumber(link:match("(%d+)$")))
    else
        GameTooltip:Hide()
        return
    end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- List + panel
---------------------------------------------------------------------------
-- reagents of your professions that you own: { [profession] = { itemID, ... } }
-- Filter menu next to the search box: keep a reagent only if one of its recipes passes every ticked filter
local FILTERS = {
    { "filterLearned", "Learned Recipes", "Only reagents used by recipes you have learned" },
    { "filterSkillUp", "Gives Skill-Up", "Only reagents used by recipes that can still raise your skill level" },
    { "filterCraftable", "Can Craft Now", "Only reagents of recipes you have every material for" },
}

local function PassesFilter(r)
    if ns.Get("filterLearned") and not IsKnown(r.spellID) then
        return false
    end
    if ns.Get("filterSkillUp") then
        local d = Difficulty(r, PlayerSkill(r.profession))
        if d ~= "orange" and d ~= "yellow" and d ~= "green" then
            return false
        end
    end
    if ns.Get("filterCraftable") and RecipeState(r) ~= "green" then
        return false
    end
    return true
end

local function MyReagents()
    local byProf, seen = {}, {}
    for itemId, recipes in pairs(Index().reagentFor) do
        -- only items you own are listed: check that first, it skips the recipe filters for everything else
        if Have(itemId) > 0 then
            for _, r in ipairs(recipes) do
                local p = r.profession
                if Shown(p) and PassesFilter(r) then
                    seen[p] = seen[p] or {}
                    if not seen[p][itemId] then
                        seen[p][itemId] = true
                        byProf[p] = byProf[p] or {}
                        table.insert(byProf[p], itemId)
                    end
                end
            end
        end
    end
    return byProf
end

local function UpdateCollapse(area)
    local b = collapse[area]
    if b then
        b:SetShown(next(areaKeys[area]) ~= nil)
        b:SetText(AnyOpen(area) and "Collapse All" or "Expand All")
    end
end

local function Render()
    ns.TellTrackers()
    if not panel or not panel:IsVisible() then
        return
    end
    wipe(areaKeys.list)
    wipe(areaKeys.detail)
    head.listSub:SetText((ns.Get("includeBank") and "Bags + Bank" or "Bags") .. (ns.Get("allProfs") and "  -  All Professions" or ""))
    -- groups: by profession, or by reagent type (item subtype: Cloth, Herb, Metal & Stone, ...)
    local byProf = MyReagents()
    local groups, order = {}, {}
    local byType = ns.Get("listGroup") == "type"
    for p, items in pairs(byProf) do
        for _, id in ipairs(items) do
            if searchText == "" or ItemName(id):lower():find(searchText, 1, true) then
                local gk, name, icon
                if byType then
                    local _, ic, itemType, subType = ItemInstant(id)
                    name = (subType and subType ~= "" and subType) or itemType or "Other"
                    gk, icon = "type:" .. name, ic
                else
                    gk, name = "prof:" .. p, ProfessionName(p)
                    icon = (ProfIcon(p) or ""):match("^|T([^:]+):")
                end
                local g = groups[gk]
                if not g then
                    g = { key = gk, name = name, icon = icon, items = {}, seen = {} }
                    groups[gk] = g
                    order[#order + 1] = g
                end
                if not g.seen[id] then
                    g.seen[id] = true
                    g.items[#g.items + 1] = id
                end
            end
        end
    end
    table.sort(order, function(x, y)
        return x.name < y.name
    end)

    local rows = {}
    if #order == 0 then
        rows[1] = { text = C_DIM .. (searchText ~= "" and "No Match" or "No Reagents of Your Professions") .. "|r" }
    end
    for _, g in ipairs(order) do
        local items = g.items
        table.sort(items, function(x, y)
            return ItemName(x) < ItemName(y)
        end)
        selected = selected or { kind = "item", id = items[1] }
        local key = "list:" .. g.key
        local open = Group("list", key)
        rows[#rows + 1] = { header = true, key = key, icon = g.icon, open = open,
            text = g.name .. "  " .. C_DIM .. "(" .. #items .. ")|r" }
        if open then
            for _, id in ipairs(items) do
                local _, icon = ItemInstant(id)
                rows[#rows + 1] = { id = id, icon = icon, text = QualityColor(id) .. ItemName(id) .. "|r",
                    cols = Columns(id), selected = selected and selected.id == id }
            end
        end
    end
    list:SetRows(rows)
    UpdateCollapse("list")

    L = {}
    recommended = nil
    urlBox.url = ""
    if selected then
        RenderItem(selected.id)
    else
        UpdateTabs({})
        head.craft:Hide()
        SetHeader(nil, C_DIM .. "Nothing Selected|r", "Ctrl + Right-Click a reagent in your bags to open it here")
    end
    head.back:SetEnabled(#history > 0)
    urlBox:SetText(urlBox.url)
    urlBox:SetCursorPosition(0)
    detail:SetLines(L)
    UpdateCollapse("detail")
end
ns.RefreshReagents = function()
    Render()
end

local pending
local function ScheduleRender()
    if pending then
        return
    end
    pending = true
    C_Timer.After(0.3, function()
        pending = false
        Render()
    end)
end

-- open the profession window on a recipe (C_TradeSkillUI.OpenRecipe, else just the profession)
local function OpenCraft(spellID, prof)
    if InCombatLockdown and InCombatLockdown() then
        ns.Print("Can't Open Professions in Combat")
        return
    end
    -- Helper docks to the right of the profession window once it is up
    local function Behind()
        C_Timer.After(0.1, function()
            if ns.HookProfFrames then
                ns.HookProfFrames()
            end
            for _, name in ipairs({ "ProfessionsFrame", "TradeSkillFrame" }) do
                local fr = _G[name]
                if fr and fr:IsShown() and ns.DockTo then
                    ns.DockTo(fr)
                    return
                end
            end
        end)
    end
    local ts = C_TradeSkillUI
    if ts and ts.OpenRecipe and pcall(ts.OpenRecipe, spellID) then
        Behind()
        return
    end
    if ts and ts.OpenTradeSkill and prof > 0 and pcall(ts.OpenTradeSkill, prof) then
        Behind()
        return
    end
    ns.Print("Open " .. ProfessionName(prof) .. " To Craft " .. (SpellName(spellID) or "This Recipe"))
end

-- a reagent was picked here: select a recipe that uses it in the open profession window
-- (your learned / best skill-up one first); nothing happens if that profession isn't the open one
local function SyncProfession(id)
    local pf = _G.ProfessionsFrame
    local ts = C_TradeSkillUI
    if not (pf and pf:IsShown() and ts and ts.OpenRecipe and ts.GetBaseProfessionInfo) then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    local info = Safe(ts.GetBaseProfessionInfo)
    local prof = info and info.professionID
    local mine = {}
    for _, r in ipairs(Index().reagentFor[id] or {}) do
        if r.profession == prof then
            mine[#mine + 1] = r
        end
    end
    if #mine == 0 then
        return
    end
    local best = PickRecommended(mine) or mine[1].spellID
    ns.syncedRecipe = best -- so the profession window's change doesn't bounce back here
    pcall(ts.OpenRecipe, best)
end

-- craft a recipe: the game only crafts while that profession is open, so craft right away if it is,
-- otherwise open it on the recipe (the next click crafts). Shift = as many as there are materials for.
local function DoCraft(r, crafts)
    local ts = C_TradeSkillUI
    local pf = _G.ProfessionsFrame
    local info = ts and ts.GetBaseProfessionInfo and Safe(ts.GetBaseProfessionInfo)
    if pf and pf:IsShown() and info and info.professionID == r.profession and ts.CraftRecipe then
        local n = IsShiftKeyDown() and math.max(crafts or 1, 1) or 1
        ns.syncedRecipe = r.spellID
        pcall(ts.OpenRecipe, r.spellID)
        if not pcall(ts.CraftRecipe, r.spellID, n) then
            ns.Print("Couldn't Start Crafting " .. RecipeName(r))
        end
    else
        OpenCraft(r.spellID, r.profession or 0)
        ns.Print(ProfessionName(r.profession) .. " Opened - Click Craft Again to Make " .. RecipeName(r))
    end
end

-- a recipe card was clicked: select that recipe in the open profession window (same profession only)
-- Craft from the Crafting tracker without showing the profession window. The game only crafts while a
-- profession is open, so it is opened invisibly (alpha 0), the craft is started, and it is closed again
-- once the casting stops. ns.silentCraft tells the profession-window hooks to stay out of the way.
local silent -- { spell, n, t = start time, cast = last time a cast was seen, tried }

local function EndSilent()
    local pf = _G.ProfessionsFrame
    if pf and pf:IsShown() then
        if not pcall(HideUIPanel, pf) or pf:IsShown() then
            pf:Hide()
        end
    end
    if pf then
        pf:SetAlpha(1)
    end
    ns.silentCraft, silent = nil, nil
end

local function SilentTick()
    if not silent then
        return
    end
    local pf = _G.ProfessionsFrame
    local now = GetTime()
    if pf and pf:IsShown() then
        pf:SetAlpha(0)
        if (UnitCastingInfo and UnitCastingInfo("player")) or (UnitChannelInfo and UnitChannelInfo("player")) then
            silent.cast = now
        end
        if not silent.cast and not silent.hinted and now - silent.t > 1 then
            silent.hinted = true -- the craft has to come from a click: nothing started from the first one
            ns.Print("Click Craft Again to Make " .. (silent.name or "It"))
        end
    elseif now - silent.t > 1.5 then -- closed by something else (Escape, another window)
        if pf then
            pf:SetAlpha(1)
        end
        ns.silentCraft, silent = nil, nil
        return
    end
    -- done 1.5 s after the last cast; if no cast ever started, stay open (hidden) a while so a
    -- second click can craft directly
    if (silent.cast and now - silent.cast > 1.5) or (not silent.cast and now - silent.t > 12) then
        EndSilent()
        return
    end
    C_Timer.After(0.25, SilentTick)
end

function ns.CraftSilent(r, crafts)
    if InCombatLockdown and InCombatLockdown() then
        ns.Print("Can't Craft in Combat")
        return
    end
    local ts = C_TradeSkillUI
    local pf = _G.ProfessionsFrame
    if not (ts and ts.OpenTradeSkill and ts.CraftRecipe) or (pf and pf:IsShown() and not silent) then
        DoCraft(r, crafts) -- no such API, or the profession window is really open: the normal way
        return
    end
    local n = IsShiftKeyDown() and math.max(crafts or 1, 1) or 1
    local info = ts.GetBaseProfessionInfo and Safe(ts.GetBaseProfessionInfo)
    if silent and pf and pf:IsShown() and info and info.professionID == r.profession then
        -- still open (hidden) from the previous click: craft right away
        silent.spell, silent.n, silent.t, silent.cast, silent.hinted = r.spellID, n, GetTime(), nil, true
        pcall(ts.CraftRecipe, r.spellID, n)
        return
    end
    local fresh = silent == nil
    silent = { spell = r.spellID, n = n, t = GetTime(), name = RecipeName(r) }
    ns.silentCraft = true
    if pf then
        pf:SetAlpha(0)
    end
    if not pcall(ts.OpenTradeSkill, r.profession or 0) then
        EndSilent()
        DoCraft(r, crafts)
        return
    end
    -- try in this same click (crafts only start from a click); works when the profession is ready at once
    pcall(ts.CraftRecipe, r.spellID, n)
    if fresh then
        C_Timer.After(0.2, SilentTick)
    end
end

local function SyncRecipe(r)
    local pf = _G.ProfessionsFrame
    local ts = C_TradeSkillUI
    if not (r and pf and pf:IsShown() and ts and ts.OpenRecipe and ts.GetBaseProfessionInfo) then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    local info = Safe(ts.GetBaseProfessionInfo)
    if info and info.professionID == r.profession then
        ns.syncedRecipe = r.spellID
        pcall(ts.OpenRecipe, r.spellID)
    end
end

-- a recipe card was clicked: open what it makes here, and select the recipe in the profession window
local function SelectCard(r)
    SyncRecipe(r)
    if r and r.item and not (selected and selected.id == r.item) then
        Select("item", r.item)
        Render()
        detail:SetVerticalScroll(0)
    end
end

local function ToggleAll(area)
    local open = AnyOpen(area)
    for k in pairs(areaKeys[area]) do
        toggles[k] = not open
    end
    Render()
end

-- nearest source of an item: { name, kind, map, x, y, dist } (nil when unknown)
function ns.NearestSpot(id)
    return Spots(id)[1]
end

function ns.WaypointNearest(id)
    local s = Spots(id)[1]
    if s then
        SetWaypoint(s.map, s.x, s.y, Clean(s.name .. " - " .. ItemName(id)))
    else
        ns.Print("No Known Location for " .. ItemName(id))
    end
    return s
end

-- side map with every known spawn of an item
function ns.ShowItemMap(id)
    local s = Spots(id)[1]
    if ns.ShowMap and s then
        ns.ShowMap(ItemName(id), MapPoints(id), s.map)
    else
        ns.Print("No Known Location for " .. ItemName(id))
    end
end

-- nearest source of an item as text: "Name - Zone  120 yd" (nil when unknown)
function ns.NearestText(id)
    local s = Spots(id)[1]
    if s then
        return ("%s - %s%s"):format(s.name, ZoneName(s.map), s.dist and ("  " .. Yards(s.dist)) or "")
    end
end

local function OnLink(link)
    local kind, id = link:match("^addon:Helper:sel:(%a+):(%d+)$")
    if kind then
        Select(kind, tonumber(id))
        Render()
        SyncProfession(selected.id)
        detail:SetVerticalScroll(0)
        return
    end
    local key = link:match("^addon:Helper:tog:(.+)$")
    if key then
        local default = not key:find("^gray:")
        toggles[key] = not IsOn(key, default)
        Render()
        return
    end
    local mid, mmap = link:match("^addon:Helper:map:(%d+):(%d+)$")
    if mid then
        mid, mmap = tonumber(mid), tonumber(mmap)
        if mmap == 0 then
            local s = Spots(mid)[1]
            mmap = s and s.map
        end
        if ns.ShowMap then
            ns.ShowMap(ItemName(mid), MapPoints(mid), mmap)
        end
        return
    end
    local farmr = tonumber(link:match("^addon:Helper:farmr:(%d+)$"))
    if farmr then
        SetFarmCrafts(farmr, (db.farmCrafts and db.farmCrafts[farmr] or 0) + 1)
        return
    end
    local farmn = tonumber(link:match("^addon:Helper:farmn:(%d+)$"))
    if farmn then
        AskFarmCrafts(farmn)
        return
    end
    local cspell, cprof, _, ccan = link:match("^addon:Helper:craft:(%d+):(%d+):(%d+):(%d)$")
    if cspell then
        if ccan == "1" then
            OpenCraft(tonumber(cspell), tonumber(cprof))
        else
            ns.Print("Learn " .. (SpellName(tonumber(cspell)) or "This Recipe") .. " First")
        end
        return
    end
    local near = tonumber(link:match("^addon:Helper:near:(%d+)$"))
    if near then
        ns.WaypointNearest(near)
        return
    end
    local map, x, y, label = link:match("^addon:Helper:way:(%d+):([%d%.]+):([%d%.]+):(.*)$")
    if map then
        SetWaypoint(tonumber(map), tonumber(x), tonumber(y), label:sub(1, 1) == "~" and label:sub(2) or label)
    end
end

ns.SetWaypoint = SetWaypoint
ns.Have = Have
ns.HaveSplit = HaveSplit
ns.ItemName = ItemName
ns.QualityColor = QualityColor
ns.Icon = Icon
ns.Index = Index
ns.PlayerSkill = PlayerSkill
ns.Difficulty = Difficulty
ns.IsKnown = IsKnown
ns.Shown = Shown
ns.World = World
ns.UiMap = UiMap
ns.MyFaction = MyFaction
ns.ZoneName = ZoneName
ns.PlayerWorld = PlayerWorld
ns.SkillIcon = SkillIcon
ns.FindRecipe = FindRecipe
ns.MaxCrafts = MaxCrafts
ns.DoCraft = DoCraft
ns.RecipeName = RecipeName
ns.ProfessionName = ProfessionName
ns.ProfIcon = ProfIcon
ns.ItemInstant = ItemInstant

-- left list rows: header toggles its group, item selects; hover shows the item tooltip
local function OnRowClick(d)
    if not d then
        return
    end
    if d.header then
        toggles[d.key] = not IsOn(d.key, true)
        Render()
    elseif d.id then
        Select("item", d.id)
        Render()
        SyncProfession(d.id)
        detail:SetVerticalScroll(0)
    end
end

local function OnRowEnter(row, d)
    if d and d.id then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(d.id)
        SplitTooltip(d.id)
        SpotsTooltip(d.id)
        GameTooltip:Show()
    end
end

-- a reagent was clicked in the profession window: show it here (no tab switch)
function ns.SelectReagent(id)
    if type(id) ~= "number" or (selected and selected.id == id) then
        return
    end
    Select("item", id)
    Render()
    if detail then
        detail:SetVerticalScroll(0)
    end
end

-- a recipe was picked in the profession window: show its first reagent (no tab switch)
function ns.SelectRecipeReagent(spellID)
    local r = spellID and FindRecipe(spellID)
    local first = r and r.reagents[1] and r.reagents[1][1]
    if not first or (selected and selected.id == first) then
        return
    end
    Select("item", first)
    Render()
    if detail then
        detail:SetVerticalScroll(0)
    end
end

-- open the Reagents tab on an item
function ns.ShowReagent(id)
    Select("item", id)
    local wasVisible = panel and panel:IsVisible()
    if ns.Open then
        ns.Open(1)
    end
    if wasVisible then -- otherwise showing the tab has just drawn it: don't draw twice
        Render()
    end
    if detail then
        detail:SetVerticalScroll(0)
    end
end

---------------------------------------------------------------------------
-- Hooks: item tooltips, Ctrl + right-click in bags, merchant prices
---------------------------------------------------------------------------
local function CtrlRightClick(id)
    if ns.Get("ctrlClick") and type(id) == "number" and not (issecretvalue and issecretvalue(id)) and IsControlKeyDown()
        and not (InCombatLockdown and InCombatLockdown()) and IsMyReagent(id) then
        ns.ShowReagent(id)
        return true
    end
end

-- remember vendor prices of recipes and reagents (HelperDB.prices)
local function ScanMerchant()
    if not (GetMerchantNumItems and GetMerchantItemID) then
        return
    end
    db.prices = db.prices or {}
    local idx = Index()
    for i = 1, GetMerchantNumItems() do
        local id = GetMerchantItemID(i)
        if id and (idx.taughtBy[id] or idx.reagentFor[id]) then
            local price, qty
            if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
                local info = Safe(C_MerchantFrame.GetItemInfo, i)
                price, qty = info and info.price, info and info.stackCount
            elseif GetMerchantItemInfo then
                local ok, _, _, p, q = pcall(GetMerchantItemInfo, i)
                if ok then
                    price, qty = p, q
                end
            end
            if type(price) == "number" and price > 0 then
                db.prices[id] = math.floor(price / math.max(qty or 1, 1))
            end
        end
    end
end

local function InstallHooks()
    -- pressing / releasing Shift while an item tooltip is up redraws it (full "Used In" list)
    local mod = CreateFrame("Frame")
    pcall(mod.RegisterEvent, mod, "MODIFIER_STATE_CHANGED")
    mod:SetScript("OnEvent", function(_, _, key)
        if type(key) ~= "string" or not key:find("SHIFT") or not GameTooltip:IsShown() or not ns.Get("ttUsedIn") then
            return
        end
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        if GameTooltip.RefreshData then
            pcall(GameTooltip.RefreshData, GameTooltip)
        else
            local owner = GameTooltip:GetOwner()
            local onEnter = owner and owner.GetScript and owner:GetScript("OnEnter")
            if onEnter then
                pcall(onEnter, owner)
            end
        end
    end)
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ItemTooltip)
    end
    -- Blizzard bags send modified clicks through HandleModifiedItemClick; some bag addons use UseContainerItem
    local last = 0
    hooksecurefunc("HandleModifiedItemClick", function(link)
        if type(link) == "string" and not (issecretvalue and issecretvalue(link))
            and GetMouseButtonClicked and GetMouseButtonClicked() == "RightButton"
            and CtrlRightClick(tonumber(link:match("item:(%d+)"))) then
            last = GetTime()
        end
    end)
    if C_Container and C_Container.UseContainerItem and C_Container.GetContainerItemID then
        hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
            if GetTime() ~= last then
                CtrlRightClick(Safe(C_Container.GetContainerItemID, bag, slot))
            end
        end)
    end
    local merchant = CreateFrame("Frame")
    for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE" }) do
        pcall(merchant.RegisterEvent, merchant, event)
    end
    merchant:SetScript("OnEvent", function()
        pcall(ScanMerchant)
    end)
end

---------------------------------------------------------------------------
-- Recipe Card (real frames). Layout, card-local:
--   result icon 40 at (10,10) with corner badges: skill-up (top right), learned (bottom left), yield (bottom right)
--   title x60 y12, subtitle x60 y32 (status words), action column on the right: Craft button + Farming stepper
--   separator at y60, reagents in a 2-column grid of 32px slots from y68, recessed learn panel when not learned
---------------------------------------------------------------------------
local CARD_TOP, CARD_BOTTOM = { 0.13, 0.11, 0.09, 0.95 }, { 0.08, 0.07, 0.06, 0.95 }
local CARD_LOCKED_TOP = { 0.16, 0.08, 0.07, 0.95 }
local CARD_BORDER = { 0.32, 0.26, 0.17, 1 }
local CARD_HOVER = { 0.62, 0.5, 0.3, 1 }
local CARD_REC = { 1, 0.82, 0, 0.85 }
local HAVE_RGB = { green = { 0.25, 1, 0.25 }, yellow = { 1, 0.82, 0 }, gray = { 0.5, 0.5, 0.5 } }
local SLOT_H, SLOT_GAP, GRID_Y, LEARN_ROW = 24, 2, 68, 18
local COUNT_W = 44 -- have / need column in front of each reagent
local TITLE_FONT = _G.GameFontHighlightMedium and "GameFontHighlightMedium" or "GameFontHighlight"
local DOT = C_DIM .. "  \194\183  |r"

local function QualityRGB(id)
    local q = id and C_Item and C_Item.GetItemQualityByID and Safe(C_Item.GetItemQualityByID, id)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then
        return c.r, c.g, c.b
    end
    return 0.45, 0.45, 0.45
end

local function Tooltip(frame, fill)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        fill(self)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

local function IconButton(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetAllPoints()
    b.border:SetTexture("Interface\\Common\\WhiteIconFrame")
    return b
end

local function SetItemIcon(b, id, desaturate)
    local _, icon = ItemInstant(id or 0)
    b.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    b.icon:SetDesaturated(desaturate and true or false)
    b.icon:SetAlpha(desaturate and 0.8 or 1)
    b.border:SetVertexColor(QualityRGB(id))
end

-- 16px utility button (pin / map): dim until hovered
local function UtilityButton(parent, texture, onClick, link)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(16, 16)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetTexture(texture)
    b:SetAlpha(0.45)
    b:SetScript("OnClick", function(self)
        onClick(self)
    end)
    b:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        OnLinkEnter(self, link(self))
    end)
    b:SetScript("OnLeave", function(self)
        self:SetAlpha(0.45)
        GameTooltip:Hide()
    end)
    return b
end

local function ReagentSlot(parent)
    local s = CreateFrame("Button", nil, parent)
    s:SetHeight(SLOT_H)
    s.item = IconButton(s, SLOT_H - 2)
    s.item:SetPoint("LEFT", COUNT_W + 8, 0)
    s.item:EnableMouse(false)
    s.glow = s.item:CreateTexture(nil, "OVERLAY", nil, 2)
    s.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    s.glow:SetBlendMode("ADD")
    s.glow:SetSize(SLOT_H * 1.8, SLOT_H * 1.8)
    s.glow:SetPoint("CENTER")
    s.glow:SetAlpha(0.5)
    s.glow:Hide()
    s.name = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.name:SetPoint("LEFT", s.item, "RIGHT", 8, 0)
    s.name:SetPoint("RIGHT", -44, 0)
    s.name:SetJustifyH("LEFT")
    s.name:SetWordWrap(false)
    s.count = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.count:SetPoint("LEFT", 0, 0)
    s.count:SetWidth(COUNT_W)
    s.count:SetJustifyH("RIGHT")
    s.hl = s:CreateTexture(nil, "BACKGROUND")
    s.hl:SetAllPoints()
    s.hl:SetColorTexture(1, 0.82, 0, 0.06)
    s.hl:Hide()
    s.map = UtilityButton(s, ns.Tex("Pin"), function(self)
        OnLink("addon:Helper:map:" .. self:GetParent().id .. ":0")
    end, function(self)
        return "addon:Helper:map:" .. self:GetParent().id .. ":0"
    end)
    s.map:SetPoint("RIGHT", -2, 0)
    s.pin = UtilityButton(s, ns.Tex("Arrow"), function(self)
        OnLink("addon:Helper:near:" .. self:GetParent().id)
    end, function(self)
        return "addon:Helper:near:" .. self:GetParent().id
    end)
    s.pin:SetPoint("RIGHT", s.map, "LEFT", -4, 0)
    s:SetScript("OnClick", function(self)
        OnLink("addon:Helper:sel:item:" .. self.id)
    end)
    s:SetScript("OnEnter", function(self)
        self.hl:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.id)
        SplitTooltip(self.id)
        SpotsTooltip(self.id)
        GameTooltip:Show()
    end)
    s:SetScript("OnLeave", function(self)
        self.hl:Hide()
        GameTooltip:Hide()
    end)
    return s
end

local function StepButton(parent, kind)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(16, 16)
    b:SetNormalTexture("Interface\\Buttons\\UI-" .. kind .. "Button-Up")
    b:SetPushedTexture("Interface\\Buttons\\UI-" .. kind .. "Button-Down")
    b:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    return b
end

local function FarmCount(spellID)
    return db.farmCrafts and db.farmCrafts[spellID] or 0
end

-- collapsible profession bar (same look as the category bars of the reagent list)
local function CreateGroupHeader(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(24)
    b.bar = ns.HeaderBar(b, 24)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.5)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(18, 18)
    b.icon:SetPoint("LEFT", 6, 0)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.text:SetPoint("LEFT", 30, 0)
    b.sign = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    b.sign:SetPoint("RIGHT", -8, 0)
    b:SetScript("OnClick", function(self)
        OnLink("addon:Helper:tog:" .. self.key)
    end)
    return b
end

local function UpdateGroupHeader(b, d)
    b.key = d.key
    b.icon:SetTexture(d.icon)
    b.icon:SetShown(d.icon ~= nil)
    b.text:SetPoint("LEFT", d.icon and 30 or 8, 0)
    b.text:SetText(("%s  %s(%d)|r"):format(d.name, C_DIM, d.count))
    b.bar:SetOpen(d.open)
    b.text:SetFontObject(ns.HEADER_FONT)
    b.sign:SetText(ns.SignText(d.open))
    return 24
end

local function CreateRecipeCardFrame(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    ns.Skin(f, CARD_BOTTOM, CARD_BORDER, 4)
    f.hover = f:CreateTexture(nil, "BACKGROUND", nil, 3)
    f.hover:SetPoint("TOPLEFT", 1, -1)
    f.hover:SetPoint("BOTTOMRIGHT", -1, 1)
    f.hover:SetColorTexture(1, 1, 1, 0.04)
    f.hover:Hide()
    -- not learned: a soft red glow fading down from the top of the card
    f.red = f:CreateTexture(nil, "BACKGROUND", nil, 4)
    f.red:SetPoint("TOPLEFT", 1, -1)
    f.red:SetPoint("TOPRIGHT", -1, -1)
    f.red:SetHeight(64)
    ns.Gradient(f.red, "VERTICAL", { 0.85, 0.12, 0.1, 0 }, { 0.85, 0.12, 0.1, 0.2 })
    f.red:Hide()

    -- result icon + badges
    f.icon = IconButton(f, 40)
    f.icon:SetPoint("TOPLEFT", 10, -10)
    Tooltip(f.icon, function(self)
        GameTooltip:SetItemByID(self.id)
    end)
    f:EnableMouse(true)
    f:SetScript("OnMouseUp", function(self)
        SelectCard(self.r)
    end)
    f.icon:SetScript("OnClick", function(self)
        if not IsShiftKeyDown() then
            SelectCard(f.r)
        end
        if IsShiftKeyDown() and ChatEdit_InsertLink then
            local get = C_Item and C_Item.GetItemInfo or GetItemInfo
            local _, link = get(self.id)
            if link then
                ChatEdit_InsertLink(link)
            end
        end
    end)
    f.yield = f.icon:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    f.yield:SetPoint("BOTTOMRIGHT", -2, 2)
    f.skill = CreateFrame("Button", nil, f)
    f.skill:SetSize(22, 18)
    f.skill:SetPoint("CENTER", f.icon, "TOPRIGHT", -2, -2)
    f.skill:SetFrameLevel(f.icon:GetFrameLevel() + 2)
    f.skill.text = f.skill:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.skill.text:SetPoint("CENTER")
    Tooltip(f.skill, function()
        local r = f.r
        SkillTip(r.spellID)
        local rank = PlayerSkill(r.profession)
        if f.locked then
            GameTooltip:AddLine(("Requires Skill Level %s  (You: %s)"):format(tostring(r.skill or "?"), tostring(rank or "-")), 1, 0.25, 0.25)
        end
    end)
    f.learned = CreateFrame("Frame", nil, f)
    f.learned:SetSize(14, 14)
    f.learned:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMLEFT", -3, -3)
    f.learned:SetFrameLevel(f.icon:GetFrameLevel() + 2)
    f.learned.tex = f.learned:CreateTexture(nil, "OVERLAY")
    f.learned.tex:SetAllPoints()
    f.learned:EnableMouse(true)
    Tooltip(f.learned, function()
        local known = IsKnown(f.r.spellID)
        GameTooltip:SetText(known and "Learned" or "Not Learned", known and 0.4 or 1, known and 0.85 or 0.25, known and 0.4 or 0.25)
    end)

    -- title + status line
    f.title = f:CreateFontString(nil, "OVERLAY", TITLE_FONT)
    f.title:SetPoint("TOPLEFT", 60, -12)
    f.title:SetPoint("RIGHT", -140, 0)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    -- hovering the recipe name shows the crafted item's tooltip (like the icon)
    f.titleHit = CreateFrame("Frame", nil, f)
    f.titleHit:SetPoint("TOPLEFT", f.title, "TOPLEFT", 0, 2)
    f.titleHit:SetHeight(18)
    f.titleHit:EnableMouse(true)
    f.titleHit:SetScript("OnMouseUp", function()
        SelectCard(f.r)
    end)
    Tooltip(f.titleHit, function(self)
        if self.id then
            GameTooltip:SetItemByID(self.id)
        end
    end)
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.sub:SetPoint("TOPLEFT", 60, -33)
    f.sub:SetPoint("RIGHT", -140, 0)
    f.sub:SetJustifyH("LEFT")
    f.sub:SetWordWrap(false)

    -- action column: Craft + Farming stepper
    f.craft = ns.CreateButton(f, "Craft", 96)
    f.craft:SetPoint("TOPRIGHT", -10, -10)
    local okT, track = pcall(CreateFrame, "CheckButton", nil, f, "UICheckButtonTemplate")
    if not okT or not track then
        track = CreateFrame("CheckButton", nil, f)
    end
    track:SetSize(24, 24)
    track:SetPoint("RIGHT", f.craft, "LEFT", 0, 0)
    track:SetScript("OnClick", function(self)
        if ns.CraftTrack then
            ns.CraftTrack(f.r.spellID, self:GetChecked() and true or false)
        end
    end)
    Tooltip(track, function()
        GameTooltip:SetText("Track in Crafting Window")
        GameTooltip:AddLine("Lists this recipe, its materials and a Craft button in the small Crafting window",
            0.8, 0.8, 0.8, true)
    end)
    f.track = track
    if f.craft.SetMotionScriptsWhileDisabled then
        f.craft:SetMotionScriptsWhileDisabled(true)
    end
    f.craft:SetScript("OnClick", function()
        DoCraft(f.r, f.crafts)
    end)
    f.craft:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self:IsEnabled() then
            GameTooltip:SetText("Craft  |cff40ff40x" .. (f.crafts or 1) .. "|r")
            GameTooltip:AddLine("Click: craft one   Shift-Click: craft all " .. (f.crafts or 1), 0.8, 0.8, 0.8)
            GameTooltip:AddLine("If " .. ProfessionName(f.r.profession) .. " isn't open, the first click opens it", 0.6, 0.6, 0.6, true)
        else
            GameTooltip:SetText("Can't Craft Yet")
            GameTooltip:AddLine(f.why or "", 1, 0.25, 0.25)
        end
        GameTooltip:Show()
    end)
    f.craft:SetScript("OnLeave", GameTooltip_Hide)

    local function Step(delta)
        SetFarmCrafts(f.r.spellID, FarmCount(f.r.spellID) + delta * (IsShiftKeyDown() and 5 or 1))
    end
    f.plus = StepButton(f, "Plus")
    f.plus:SetPoint("TOPRIGHT", -10, -39)
    f.plus:SetScript("OnClick", function()
        Step(1)
    end)
    f.box = CreateFrame("EditBox", nil, f)
    f.box:SetSize(30, 18)
    f.box:SetPoint("RIGHT", f.plus, "LEFT", -2, 0)
    f.box:SetAutoFocus(false)
    f.box:SetNumeric(true)
    f.box:SetMaxLetters(4)
    f.box:SetJustifyH("CENTER")
    f.box:SetFontObject("NumberFontNormal")
    f.box:SetTextInsets(2, 2, 0, 0)
    local boxBg = f.box:CreateTexture(nil, "BACKGROUND")
    boxBg:SetAllPoints()
    boxBg:SetColorTexture(0, 0, 0, 0.55)
    local boxEdge = CreateFrame("Frame", nil, f.box, "BackdropTemplate")
    boxEdge:SetAllPoints()
    ns.Skin(boxEdge, { 0, 0, 0, 0 }, { 0.4, 0.4, 0.4, 1 }, 0)
    f.box:SetScript("OnEnterPressed", function(self)
        SetFarmCrafts(f.r.spellID, tonumber(self:GetText()) or 0)
        self:ClearFocus()
    end)
    f.box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    f.box:SetScript("OnEditFocusLost", function(self)
        self:SetText(tostring(FarmCount(f.r.spellID)))
    end)
    f.box:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    Tooltip(f.box, function()
        GameTooltip:SetText("Crafts to Farm for")
        GameTooltip:AddLine("Type a number and press Enter - reagent targets on the Farming tab follow it", 0.8, 0.8, 0.8, true)
    end)
    f.minus = StepButton(f, "Minus")
    f.minus:SetPoint("RIGHT", f.box, "LEFT", -2, 0)
    f.minus:SetScript("OnClick", function()
        Step(-1)
    end)
    for _, b in ipairs({ f.plus, f.minus }) do
        Tooltip(b, function(self)
            GameTooltip:SetText(self == f.plus and "One More Craft" or "One Less Craft")
            GameTooltip:AddLine("Shift-Click: 5 at a time", 0.8, 0.8, 0.8)
        end)
    end
    f.farm = CreateFrame("Button", nil, f)
    f.farm:SetHeight(18)
    f.farm:SetPoint("RIGHT", f.minus, "LEFT", -6, 0)
    f.farm.text = f.farm:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.farm.text:SetPoint("RIGHT")
    f.farm.text:SetText("Farming")
    f.farm:SetWidth(f.farm.text:GetStringWidth() + 2)
    f.farm:SetScript("OnClick", function()
        Step(1)
    end)
    Tooltip(f.farm, function()
        GameTooltip:SetText("Farming")
        GameTooltip:AddLine("Click: farm the reagents for one more craft (adds them to the Farming tab)", 0.8, 0.8, 0.8, true)
    end)

    -- separator + reagent grid
    f.sep = f:CreateTexture(nil, "BORDER")
    f.sep:SetPoint("TOPLEFT", 10, -60)
    f.sep:SetPoint("TOPRIGHT", -10, -60)
    f.sep:SetHeight(1)
    f.sep:SetColorTexture(1, 1, 1, 0.06)
    f.slots = {}
    f.none = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.none:SetPoint("TOPLEFT", 10, -GRID_Y)
    f.none:SetText("Reagents Unknown")

    -- recessed learn panel (only when not learned)
    f.learn = CreateFrame("Frame", nil, f)
    local lbg = f.learn:CreateTexture(nil, "BACKGROUND")
    lbg:SetAllPoints()
    lbg:SetColorTexture(0, 0, 0, 0.3)
    local ltop = f.learn:CreateTexture(nil, "BORDER")
    ltop:SetPoint("TOPLEFT")
    ltop:SetPoint("TOPRIGHT")
    ltop:SetHeight(1)
    ltop:SetColorTexture(0, 0, 0, 0.6)
    local lbottom = f.learn:CreateTexture(nil, "BORDER")
    lbottom:SetPoint("BOTTOMLEFT")
    lbottom:SetPoint("BOTTOMRIGHT")
    lbottom:SetHeight(1)
    lbottom:SetColorTexture(1, 1, 1, 0.05)
    f.learn.rows = {}
    f.learnTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.learnTitle:SetText("Learn")
    detail:LinkFrame(f.learn)

    -- hover: brighter border + faint overlay
    f:SetScript("OnUpdate", function(self)
        local over = self:IsMouseOver() and detail:IsMouseOver()
        if over ~= self.over then
            self.over = over
            self.hover:SetShown(over)
            self:SetBackdropBorderColor(unpack(over and (self.rec and CARD_REC or CARD_HOVER) or self.border))
        end
    end)
    return f
end

local function LearnRow(lp, i)
    local row = lp.rows[i]
    if not row then
        row = {}
        row.left = lp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.left:SetJustifyH("LEFT")
        row.left:SetWordWrap(false)
        row.right = lp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.right:SetJustifyH("RIGHT")
        row.right:SetWordWrap(false)
        lp.rows[i] = row
    end
    return row
end

local function UpdateRecipeCard(f, d, w)
    local r = d.r
    f.r, f.rec = r, d.rec
    local rank = PlayerSkill(r.profession)
    local diff = Difficulty(r, rank)
    local known = IsKnown(r.spellID)
    local locked = diff == "red"
    local state = RecipeState(r)
    local crafts = MaxCrafts(r)
    f.locked, f.crafts = locked, crafts
    f.track:SetChecked(ns.CraftTracked and ns.CraftTracked(r.spellID) and true or false)

    -- frame
    f:SetBackdropColor(unpack(CARD_BOTTOM))
    ns.SkinGradient(f, locked and CARD_LOCKED_TOP or CARD_TOP, CARD_BOTTOM)
    f.border = d.rec and CARD_REC or CARD_BORDER
    f.over = nil -- repaint hover on the next frame
    f:SetBackdropBorderColor(unpack(f.border))

    -- icon + badges
    local id = r.item or r.recipeItem
    f.icon.id = id
    SetItemIcon(f.icon, id, not known or locked)
    f.yield:SetText((r.count or 1) > 1 and tostring(r.count) or "")
    local badge = SkillIcon(diff, 16)
    f.skill.text:SetText(badge)
    f.skill:SetShown(badge ~= "")
    f.learned:Hide(); f.learned.tex:SetTexture("Interface\\RaidFrame\\ReadyCheck-" .. (known and "Ready" or "NotReady"))

    -- title + status
    f.title:SetText(RecipeColor(r) .. ns.Escape(RecipeName(r)) .. "|r")
    f.title:SetAlpha(locked and 0.6 or 1)
    f.red:SetShown(not known)
    f.titleHit.id = id
    f.titleHit:SetWidth(math.min(f.title:GetStringWidth(), math.max(w - 200, 40)))
    local status
    local learnedText = Learned(known, 12, true) .. (known and " |cff40ff40Learned|r" or " |cffff4040Not Learned|r")
    if locked and not known then
        learnedText = SkillIcon("red", 12) .. " |cff999999Locked|r"
    end
    if locked then
        status = "|cffff4040Requires Skill Level " .. tostring(r.skill or "?") .. "|r"
    elseif not known then
        status = nil
    elseif #r.reagents == 0 then
        status = C_DIM .. "Reagents Unknown|r"
    elseif state == "green" then
        status = "|cff40ff40Ready|r"
    else
        local missing = 0
        for _, rg in ipairs(r.reagents) do
            if Have(rg[1]) < rg[2] then
                missing = missing + 1
            end
        end
        status = C_DIM .. "Missing " .. missing .. "|r"
    end
    status = learnedText .. (status and (DOT .. status) or "")
    f.sub:SetText(d.rec and (STAR .. " " .. C_GOLD .. "Recommended|r" .. DOT .. status) or status)

    -- actions
    local can = known and not locked and state == "green" and rank ~= nil
    f.why = not known and "Learn this recipe first" or locked and ("Requires skill level " .. tostring(r.skill or "?"))
        or rank == nil and "You don't have this profession" or "Missing reagents"
    f.craft:SetEnabled(can)
    local farmable = #r.reagents > 0
    for _, x in ipairs({ f.plus, f.minus, f.box, f.farm }) do
        x:SetShown(farmable)
    end
    local fc = FarmCount(r.spellID)
    if not f.box:HasFocus() then
        f.box:SetText(tostring(fc))
    end
    f.box:SetTextColor(fc > 0 and 1 or 0.5, fc > 0 and 0.82 or 0.5, fc > 0 and 0 or 0.5)

    -- reagents: one row each
    for i, rg in ipairs(r.reagents) do
        local s = f.slots[i]
        if not s then
            s = ReagentSlot(f)
            f.slots[i] = s
        end
        local rid, need = rg[1], rg[2]
        local have = Have(rid)
        s.id = rid
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", 10, -(GRID_Y + (i - 1) * (SLOT_H + SLOT_GAP)))
        s:SetWidth(w - 20)
        SetItemIcon(s.item, rid)
        s.name:SetText((rid == d.highlight and C_GOLD or "|cffffffff") .. ns.Escape(ItemName(rid)) .. "|r")
        s.count:SetText(("%d/%d"):format(have, need))
        s.count:SetTextColor(unpack(HAVE_RGB[ReagentState(have, need)]))
        local src = HasSources(rid)
        s.pin:SetShown(src)
        s.map:SetShown(src)
        s:Show()
    end
    for i = #r.reagents + 1, #f.slots do
        f.slots[i]:Hide()
    end
    f.none:SetShown(#r.reagents == 0)
    local rows = #r.reagents
    local y = #r.reagents > 0 and (GRID_Y + rows * SLOT_H + (rows - 1) * SLOT_GAP) or (GRID_Y + 14)

    -- learn panel
    local lp = f.learn
    if d.withSource and not known then
        local lines = LearnRows(r)
        local pw = w - 20
        f.learnTitle:ClearAllPoints()
        f.learnTitle:SetPoint("TOPLEFT", 10, -(y + 10))
        f.learnTitle:Show()
        y = y + 16
        lp:ClearAllPoints()
        lp:SetPoint("TOPLEFT", 10, -(y + 8))
        lp:SetWidth(pw)
        for i, line in ipairs(lines) do
            local lr = LearnRow(lp, i)
            local top = -(8 + (i - 1) * (LEARN_ROW + 2))
            lr.right:ClearAllPoints()
            lr.right:SetPoint("TOPRIGHT", -8, top - 3)
            lr.right:SetWidth(0)
            lr.right:SetText(line[2] or "")
            local rw = (line[2] or "") ~= "" and ((lr.right.GetUnboundedStringWidth or lr.right.GetStringWidth)(lr.right) + 2) or 0
            lr.right:SetWidth(math.max(rw, 1))
            lr.left:ClearAllPoints()
            lr.left:SetPoint("TOPLEFT", 8, top - 3)
            lr.left:SetWidth(math.max(pw - 16 - rw - (rw > 0 and 10 or 0), 40))
            lr.left:SetText(line[1])
            lr.left:Show()
            lr.right:Show()
        end
        for i = #lines + 1, #lp.rows do
            lp.rows[i].left:Hide()
            lp.rows[i].right:Hide()
        end
        local ph = 16 + #lines * LEARN_ROW + (#lines - 1) * 2
        lp:SetHeight(ph)
        lp:Show()
        y = y + 8 + ph
    else
        lp:Hide()
        f.learnTitle:Hide()
    end
    return y + 10
end

---------------------------------------------------------------------------
-- Panel layout
---------------------------------------------------------------------------
local LIST_W = 285
local PAD = 14

function ns.CreateInfoPanel(f, inset, helperDB)
    db = helperDB
    -- icons used inside texts: from the active layout (the values above are only the load-time defaults)
    ARROW = "|T" .. ns.Tex("Arrow") .. ":14:14:0:-1|t"
    MAPICON = "|T" .. ns.Tex("Pin") .. ":14:14:0:-1|t"
    CRAFT = "|T" .. ns.Tex("Craft") .. ":14:14:0:-1|t"
    CRAFT_OFF = "|T" .. ns.Tex("CraftOff") .. ":14:14:0:-1|t"
    STAR = "|T" .. ns.Tex("Star") .. ":14:14:0:-1|t"
    TAB_ICONS.where = ns.Tex("Pin")
    db.info = nil -- old hover history (feature replaced by the reagent list)
    local T = ns.T

    panel = CreateFrame("Frame", nil, f)
    panel:SetAllPoints(f)

    -- left inset: search, Collapse All, group-by and Mine / All switches, then the row list
    local left = ns.Card(panel)
    left:SetPoint("TOPLEFT", inset, "TOPLEFT")
    left:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT")
    left:SetWidth(LIST_W + 2 * PAD + 12)
    head.listSub = left:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall") -- (kept for Render)
    head.listSub:Hide()
    local search = ns.CreateSearchBox(left)
    search:SetPoint("TOPLEFT", 14, -66)
    search:SetPoint("RIGHT", left, "RIGHT", -104, 0)
    -- Filter button, like the profession window's
    local function FilterMenu(_, root)
        for _, flt in ipairs(FILTERS) do
            local item = root:CreateCheckbox(flt[2], function()
                return ns.Get(flt[1]) and true or false
            end, function()
                ns.Set(flt[1], not ns.Get(flt[1]))
            end)
            if item and item.SetTooltip then
                item:SetTooltip(function(tooltip)
                    GameTooltip_SetTitle(tooltip, flt[2])
                    GameTooltip_AddNormalLine(tooltip, flt[3])
                end)
            end
        end
        root:CreateDivider()
        root:CreateCheckbox("Include Bank", function()
            return ns.Get("includeBank") and true or false
        end, function()
            ns.Set("includeBank", not ns.Get("includeBank"))
        end)
    end
    local ok, filter = pcall(CreateFrame, "DropdownButton", nil, left, "WowStyle1FilterDropdownTemplate")
    if ok and filter and filter.SetupMenu then
        filter:SetText("Filter")
        filter:SetupMenu(FilterMenu)
    else
        filter = ns.CreateButton(left, "Filter", 90)
        filter:SetScript("OnClick", function(self)
            if MenuUtil and MenuUtil.CreateContextMenu then
                MenuUtil.CreateContextMenu(self, FilterMenu)
            end
        end)
    end
    filter:SetSize(90, 22)
    filter:SetPoint("LEFT", search, "RIGHT", 4, 0)
    search:HookScript("OnTextChanged", function(self)
        searchText = (self:GetText() or ""):lower()
        ScheduleRender()
    end)
    -- same size and column as the Group By / Show bars, on its own row under them
    -- looks like a category bar and spans the list width, like the category rows
    collapse.list = ns.CreateHeaderButton(left, "Collapse All")
    collapse.list.fit = true
    collapse.list:SetText("Collapse All")
    collapse.list:SetPoint("TOPRIGHT", left, "TOPRIGHT", -28, -94)
    collapse.list:SetScript("OnClick", function()
        ToggleAll("list")
    end)
    local listTitle = left:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listTitle:SetPoint("LEFT", left, "TOPLEFT", 14, -106)
    listTitle:SetText("My Reagents")
    local groupSwitch = ns.CreateSegmented(left, { { "Profession", "prof", "Group reagents by the profession that uses them" },
        { "Category", "type", "Group reagents by kind: Cloth, Herb, Metal & Stone, Leather..." } }, 240, function()
        return ns.Get("listGroup")
    end, function(v)
        ns.Set("listGroup", v)
    end, "Group by")
    groupSwitch:SetPoint("TOPLEFT", 10, -8)
    local profSwitch = ns.CreateSegmented(left, { { "My Professions", false, "Only reagents your professions use" },
        { "All Professions", true, "Reagents of every profession" } }, 240, function()
        return ns.Get("allProfs") and true or false
    end, function(v)
        ns.Set("allProfs", v)
    end, "Show")
    profSwitch:SetPoint("TOPLEFT", 10, -36)
    ns.OnSetting("allProfs", function()
        profSwitch.Update()
    end)
    list = ns.CreateRowList(left, OnRowClick, OnRowEnter)
    list:SetPoint("TOPLEFT", left, "TOPLEFT", 6, -150)
    -- column titles above the list: bag and bank icons, right-aligned over the numbers (tooltip on hover)
    local function ColumnIcon(texture, tip)
        local b = CreateFrame("Frame", nil, left)
        b:SetSize(ns.COL_W, 18)
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetSize(18, 18)
        t:SetPoint("RIGHT", 0, 0)
        t:SetTexture(texture)
        if texture:find("\\Icons\\", 1, true) then
            t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tip)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        return b
    end
    local bankCol = ColumnIcon("Interface\\Icons\\INV_Box_02", "In Your Bank")
    bankCol:SetPoint("BOTTOMRIGHT", list, "TOPRIGHT", -10, 6)
    local bagCol = ColumnIcon("Interface\\Buttons\\Button-Backpack-Up", "In Your Bags")
    local function PlaceColumns() -- the bank column only exists while the bank is counted
        local bank = ns.Get("includeBank") and true or false
        bankCol:SetShown(bank)
        bagCol:ClearAllPoints()
        if bank then
            bagCol:SetPoint("RIGHT", bankCol, "LEFT", -4, 0)
        else
            bagCol:SetPoint("BOTTOMRIGHT", list, "TOPRIGHT", -10, 6)
        end
    end
    PlaceColumns()
    ns.OnSetting("includeBank", PlaceColumns)
    list:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -26, 6)

    -- right: header card (quality-bordered icon, name, details, count on the right)
    local card = ns.Card(panel)
    card:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, 0)
    card:SetPoint("RIGHT", inset, "RIGHT")
    card:SetHeight(72)
    head.card = card
    local glow = card:CreateTexture(nil, "BACKGROUND", nil, 1)
    glow:SetPoint("TOPLEFT", 1, -1)
    glow:SetPoint("BOTTOMLEFT", 1, 1)
    glow:SetWidth(300)
    head.glow = glow
    head.frame = CreateFrame("Frame", nil, card, "BackdropTemplate")
    head.frame:SetSize(48, 48)
    head.frame:SetPoint("LEFT", PAD + 30, 0)
    -- Back: the previously selected item (and the tab it was on)
    head.back = CreateFrame("Button", nil, card)
    head.back:SetSize(28, 28)
    head.back:SetPoint("LEFT", 8, 0)
    head.back:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    head.back:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
    head.back:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled")
    head.back:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    head.back:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- go back to history[k] (the last page by default), dropping it and everything after it
    local function GoBack(k)
        k = k or #history
        local h = history[k]
        if h then
            for i = #history, k, -1 do
                table.remove(history, i)
            end
            selected = { kind = h.kind, id = h.id }
            detailTab = h.tab or detailTab
            Render()
            detail:SetVerticalScroll(0)
        end
    end
    head.back:SetScript("OnClick", function(self, button)
        if button ~= "RightButton" then
            GoBack()
        elseif #history > 0 and MenuUtil and MenuUtil.CreateContextMenu then
            -- every page visited, newest first: jump straight to one
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateTitle("Go back to")
                for k = #history, math.max(#history - 24, 1), -1 do
                    local h = history[k]
                    local _, icon = ItemInstant(h.id)
                    local mark = icon and ("|T%s:16:16:0:0:64:64:5:59:5:59|t "):format(icon) or ""
                    root:CreateButton(mark .. QualityColor(h.id) .. ItemName(h.id) .. "|r", function()
                        GoBack(k)
                    end)
                end
            end)
        end
    end)
    head.back:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        local h = history[#history]
        GameTooltip:SetText("Back")
        if h then
            GameTooltip:AddLine(ItemName(h.id), 1, 1, 1)
            GameTooltip:AddLine("Right-click: choose a page to go back to", 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    head.back:SetScript("OnLeave", GameTooltip_Hide)
    ns.Skin(head.frame, { 0, 0, 0, 1 }, T.border, 0)
    head.icon = head.frame:CreateTexture(nil, "ARTWORK")
    head.icon:SetPoint("TOPLEFT", 2, -2)
    head.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    head.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    head.have = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    -- Farming stepper (same control as on the recipe cards): "Farming  - [n] +" = this item's farming target
    local farmBtn = CreateFrame("Frame", nil, card)
    farmBtn:SetSize(124, 20)
    farmBtn:SetPoint("RIGHT", -PAD, 0)
    local function FarmTarget()
        return selected and ns.FarmTarget and ns.FarmTarget(selected.id) or 0
    end
    local fbox
    local function SetFarm(n)
        if selected and ns.FarmSet then
            ns.FarmSet(selected.id, n)
        end
        fbox:SetText(tostring(FarmTarget()))
    end
    local fplus = StepButton(farmBtn, "Plus")
    fplus:SetPoint("RIGHT", 0, 0)
    fbox = CreateFrame("EditBox", nil, farmBtn)
    fbox:SetSize(34, 18)
    fbox:SetPoint("RIGHT", fplus, "LEFT", -2, 0)
    fbox:SetAutoFocus(false)
    fbox:SetNumeric(true)
    fbox:SetMaxLetters(5)
    fbox:SetJustifyH("CENTER")
    fbox:SetFontObject("NumberFontNormal")
    fbox:SetTextInsets(2, 2, 0, 0)
    local fboxBg = fbox:CreateTexture(nil, "BACKGROUND")
    fboxBg:SetAllPoints()
    fboxBg:SetColorTexture(0, 0, 0, 0.55)
    local fboxEdge = CreateFrame("Frame", nil, fbox, "BackdropTemplate")
    fboxEdge:SetAllPoints()
    ns.Skin(fboxEdge, { 0, 0, 0, 0 }, { 0.4, 0.4, 0.4, 1 }, 0)
    fbox:SetScript("OnEnterPressed", function(self)
        SetFarm(tonumber(self:GetText()) or 0)
        self:ClearFocus()
    end)
    fbox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    fbox:SetScript("OnEditFocusLost", function(self)
        self:SetText(tostring(FarmTarget()))
    end)
    fbox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    Tooltip(fbox, function()
        GameTooltip:SetText("Farming Target")
        GameTooltip:AddLine("How many of this item to farm. Type a number and press Enter; 0 removes it from the Farming tab",
            0.8, 0.8, 0.8, true)
    end)
    local fminus = StepButton(farmBtn, "Minus")
    fminus:SetPoint("RIGHT", fbox, "LEFT", -2, 0)
    fplus:SetScript("OnClick", function()
        SetFarm(FarmTarget() + (IsShiftKeyDown() and 5 or 1))
    end)
    fminus:SetScript("OnClick", function()
        SetFarm(FarmTarget() - (IsShiftKeyDown() and 5 or 1))
    end)
    for _, b in ipairs({ fplus, fminus }) do
        Tooltip(b, function(self)
            GameTooltip:SetText(self == fplus and "One More" or "One Less")
            GameTooltip:AddLine("Shift-Click: 5 at a time", 0.8, 0.8, 0.8)
        end)
    end
    local flabel = farmBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    flabel:SetPoint("RIGHT", fminus, "LEFT", -6, 0)
    flabel:SetText("Farming")
    function head.UpdateFarm()
        if not fbox:HasFocus() then
            fbox:SetText(tostring(FarmTarget()))
        end
    end
    head.have:SetPoint("RIGHT", farmBtn, "LEFT", -18, 0)
    head.farmBtn = farmBtn
    head.craft = ns.CreateButton(card, "Craft", 76)
    head.craft:SetPoint("RIGHT", farmBtn, "LEFT", -8, 0)
    head.craft:Hide()
    if head.craft.SetMotionScriptsWhileDisabled then
        head.craft:SetMotionScriptsWhileDisabled(true)
    end
    head.craft:SetScript("OnClick", function()
        if head.made then
            DoCraft(head.made, head.crafts)
        end
    end)
    head.craft:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        if self:IsEnabled() then
            GameTooltip:SetText("Craft  |cff40ff40x" .. (head.crafts or 1) .. "|r")
            GameTooltip:AddLine("Click: craft one   Shift-Click: craft all " .. (head.crafts or 1), 0.8, 0.8, 0.8)
        else
            GameTooltip:SetText("Can't Craft Yet")
            GameTooltip:AddLine(head.craftWhy or "", 1, 0.25, 0.25)
        end
        GameTooltip:Show()
    end)
    head.craft:SetScript("OnLeave", GameTooltip_Hide)
    head.haveLabel = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    head.haveLabel:SetPoint("TOPRIGHT", head.have, "BOTTOMRIGHT", 0, -3)
    head.haveLabel:SetText("In Bags + Bank")
    head.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    head.name:SetPoint("TOPLEFT", head.frame, "TOPRIGHT", 14, -4)
    head.name:SetPoint("RIGHT", head.have, "LEFT", -16, 0)
    head.name:SetJustifyH("LEFT")
    head.name:SetWordWrap(false)
    head.sub = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    head.sub:SetPoint("TOPLEFT", head.name, "BOTTOMLEFT", 0, -7)
    head.sub:SetPoint("RIGHT", head.have, "LEFT", -16, 0)
    head.sub:SetJustifyH("LEFT")
    head.sub:SetWordWrap(false)

    -- right: folder tabs attached to the body card
    local prev
    for _, k in ipairs(TAB_KEYS) do
        local b = ns.CreateTab(panel, TAB_NAMES[k], 170, TAB_ICONS[k])
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", 2, 0)
        else
            b:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -10)
        end
        b:SetScript("OnClick", function()
            detailTab = k
            Render()
            detail:SetVerticalScroll(0)
        end)
        tabButtons[k] = b
        prev = b
    end

    -- Filter for the recipe lists, at the right end of the tab row
    local function DetailMenu(_, root)
        for i, flt in ipairs(DETAIL_FILTERS) do
            if flt.title then
                if i > 1 then
                    root:CreateDivider()
                end
                if root.CreateTitle then
                    root:CreateTitle(flt.title)
                end
            else
                local item = root:CreateCheckbox(flt[2], function()
                    return ns.Get(flt[1]) and true or false
                end, function()
                    ns.Set(flt[1], not ns.Get(flt[1]))
                end)
                if item and item.SetTooltip then
                    item:SetTooltip(function(tooltip)
                        GameTooltip_SetTitle(tooltip, flt[2])
                        GameTooltip_AddNormalLine(tooltip, flt[3])
                    end)
                end
            end
        end
    end
    local okD, dfilter = pcall(CreateFrame, "DropdownButton", nil, panel, "WowStyle1FilterDropdownTemplate")
    if okD and dfilter and dfilter.SetupMenu then
        dfilter:SetText("Filter")
        dfilter:SetupMenu(DetailMenu)
    else
        dfilter = ns.CreateButton(panel, "Filter", 90)
        dfilter:SetScript("OnClick", function(self)
            if MenuUtil and MenuUtil.CreateContextMenu then
                MenuUtil.CreateContextMenu(self, DetailMenu)
            end
        end)
    end
    dfilter:SetSize(90, 22)
    dfilter:SetPoint("TOPRIGHT", card, "BOTTOMRIGHT", 0, -12)

    local body = ns.Card(panel, T.panel)
    body:SetPoint("TOPLEFT", tabButtons.creates, "BOTTOMLEFT", 0, -6)
    body:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT")
    body:SetFrameLevel(tabButtons.creates:GetFrameLevel() - 1)
    ns.SetCardKind(body, "detail") -- the recipe pane art of the profession window
    detail = ns.CreateScrollText(body, OnLink, OnLinkEnter)
    detail:RegisterWidget("recipe", CreateRecipeCardFrame, UpdateRecipeCard)
    detail.stickyKind = "group" -- profession headers stay visible, docked at the top / bottom
    detail.keepBar = true -- the recipe pane's scrollbar stays visible
    if detail.ScrollBar then
        detail.ScrollBar:SetAlpha(1)
        -- keep the scrollbar and its arrows inside the panel's border
        detail.ScrollBar:ClearAllPoints()
        detail.ScrollBar:SetPoint("TOPLEFT", detail, "TOPRIGHT", 5, -8)
        detail.ScrollBar:SetPoint("BOTTOMLEFT", detail, "BOTTOMRIGHT", 5, 8)
    end
    detail:RegisterWidget("group", CreateGroupHeader, UpdateGroupHeader)
    detail:SetPoint("TOPLEFT", body, "TOPLEFT", PAD + 2, -PAD - 4) -- clear of the pane's top and left border
    detail:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -PAD - 16, PAD - 4)

    -- footer: Wowhead badge + short url box (click to select, Ctrl+C to copy)
    local badge = CreateFrame("Button", nil, panel)
    badge:SetSize(22, 22)
    badge:SetPoint("LEFT", f, "BOTTOMLEFT", PAD + 4, 22) -- 22: the middle of the footer strip
    local btex = badge:CreateTexture(nil, "ARTWORK")
    btex:SetAllPoints()
    btex:SetTexture(ns.Tex("Wowhead"))
    urlBox = ns.CreateEditBox(panel)
    urlBox:SetWidth(330)
    urlBox:SetPoint("LEFT", badge, "RIGHT", 8, 0)
    urlBox.url = ""
    local function SelectUrl()
        urlBox:SetFocus()
        urlBox:HighlightText()
    end
    local function UrlTip(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Wowhead")
        GameTooltip:AddLine("Click, then Ctrl+C to copy the link", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end
    badge:SetScript("OnClick", SelectUrl)
    badge:SetScript("OnEnter", UrlTip)
    badge:SetScript("OnLeave", GameTooltip_Hide)
    urlBox:SetScript("OnMouseUp", SelectUrl)
    urlBox:SetScript("OnEnter", UrlTip)
    urlBox:SetScript("OnLeave", GameTooltip_Hide)
    urlBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then -- read-only: restore and keep it selected for Ctrl+C
            self:SetText(self.url)
            self:HighlightText()
        end
    end)
    urlBox:SetScript("OnEscapePressed", urlBox.ClearFocus)
    urlBox:SetScript("OnEnterPressed", urlBox.ClearFocus)

    -- footer, right side: open / close the addon's other windows
    local prevBtn
    for _, w in ipairs({
        { "Farming", "Farming Window", "Open or close the Farming tracker window", function()
            ns.ToggleFarmTracker()
        end },
        { "Crafting", "Crafting Window", "Open or close the Crafting tracker window", function()
            ns.ToggleCraftTracker()
        end },
        { "Bag Reagents", "Bag Reagents", "Open or close the Bag Reagents window: sell, trade or delete reagents in bulk",
            function()
                ns.ToggleBagReagents()
            end },
    }) do
        local b = ns.CreateButton(panel, w[1], 100)
        if prevBtn then
            b:SetPoint("RIGHT", prevBtn, "LEFT", -4, 0)
        else
            b:SetPoint("RIGHT", f, "BOTTOMRIGHT", -24, 22) -- same centre line; clear of the resize grip
        end
        b:SetScript("OnClick", w[4])
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(w[2])
            GameTooltip:AddLine(w[3], 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        prevBtn = b
    end

    panel:SetScript("OnShow", Render)
    panel:SetScript("OnHide", ns.TellTrackers)
    for _, event in ipairs({ "GET_ITEM_INFO_RECEIVED", "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED",
        "SKILL_LINES_CHANGED", "TRADE_SKILL_LIST_UPDATE" }) do
        pcall(panel.RegisterEvent, panel, event)
    end
    panel:SetScript("OnEvent", ScheduleRender)

    InstallHooks()
    return panel
end
