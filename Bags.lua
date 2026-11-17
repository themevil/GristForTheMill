-- Bags:
--  * borders: reagent slots get a thick coloured border - the best skill-up colour among your learned recipes
--    that use the item, or blue when one of your professions uses it but you haven't learned a recipe yet.
--    Works with any bag frame whose item buttons expose GetBagID() + GetID() (Blizzard's item button template).
--  * Bag Reagents window (button on the bag): every reagent in your bags grouped by skill-up or type, with
--    tick boxes to sell, trade or delete several at once.
local _, ns = ...

local COLORS = {
    orange = { 1, 0.5, 0.25 },
    yellow = { 1, 0.9, 0.1 },
    green = { 0.3, 0.85, 0.3 },
    gray = { 0.6, 0.6, 0.62 },
    blue = { 0.3, 0.6, 1 },
    other = { 0.75, 0.75, 0.75 },
}
local ORDER = { orange = 1, yellow = 2, green = 3, gray = 4 }
local buttons = {} -- known item buttons (weak keys)
setmetatable(buttons, { __mode = "k" })
local lastScan = 0
local BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_10"

local function Safe(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, v = pcall(fn, ...)
    if ok then
        return v
    end
end

local function State(id, cache)
    if cache[id] ~= nil then
        return cache[id]
    end
    local best, usable
    for _, r in ipairs(ns.Index().reagentFor[id] or {}) do
        local rank = ns.PlayerSkill(r.profession)
        if rank then
            if ns.IsKnown(r.spellID) then
                local d = ns.Difficulty(r, rank)
                if ORDER[d] and (not best or ORDER[d] < ORDER[best]) then
                    best = d
                end
            else
                usable = true
            end
        end
    end
    local st = best or (usable and "blue") or false
    cache[id] = st
    return st
end

---------------------------------------------------------------------------
-- Slot borders: a solid 3 px frame in the skill-up colour plus a glow around it
---------------------------------------------------------------------------
local EDGE = 3

local function Border(button)
    local b = button.RFBorder
    if b then
        return b
    end
    b = { edges = {} }
    -- own frame above the slot's children (bag addons put their own border frames on top of the button)
    local holder = CreateFrame("Frame", nil, button)
    holder:SetAllPoints()
    holder:SetFrameLevel(button:GetFrameLevel() + 10)
    local glow = holder:CreateTexture(nil, "OVERLAY", nil, 6)
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    local w, h = button:GetSize()
    if not w or w < 8 then
        w, h = 37, 37
    end
    glow:SetSize(w * 1.85, h * 1.85)
    glow:SetPoint("CENTER")
    b.glow = glow
    for i = 1, 4 do
        b.edges[i] = holder:CreateTexture(nil, "OVERLAY", nil, 7)
    end
    local e = b.edges
    e[1]:SetPoint("TOPLEFT")
    e[1]:SetPoint("TOPRIGHT")
    e[1]:SetHeight(EDGE)
    e[2]:SetPoint("BOTTOMLEFT")
    e[2]:SetPoint("BOTTOMRIGHT")
    e[2]:SetHeight(EDGE)
    e[3]:SetPoint("TOPLEFT")
    e[3]:SetPoint("BOTTOMLEFT")
    e[3]:SetWidth(EDGE)
    e[4]:SetPoint("TOPRIGHT")
    e[4]:SetPoint("BOTTOMRIGHT")
    e[4]:SetWidth(EDGE)
    function b:Set(c)
        local size = ns.Get("bagBorderSize") or EDGE
        e[1]:SetHeight(size)
        e[2]:SetHeight(size)
        e[3]:SetWidth(size)
        e[4]:SetWidth(size)
        glow:SetVertexColor(c[1], c[2], c[3], 1)
        glow:SetShown(ns.Get("bagGlow") ~= false)
        for _, t in ipairs(e) do
            t:SetColorTexture(c[1], c[2], c[3], 1)
            t:Show()
        end
    end
    function b:Hide()
        glow:Hide()
        for _, t in ipairs(e) do
            t:Hide()
        end
    end
    button.RFBorder = b
    return b
end

-- collect item buttons once in a while (bag addons create them lazily)
-- The bag bar's own buttons (backpack, bag 1-4) also have GetBagID, but they are not item slots - and they
-- are always on screen, which used to make the "bag just opened" check think a bag was already open.
local function IsBagBarButton(f)
    local name = f.GetName and f:GetName()
    if type(name) == "string" and (name:find("BackpackButton") or name:find("Bag%d+Slot") or name:find("BagSlot")
        or name:find("ReagentBag")) then
        return true
    end
    local parent = f.GetParent and f:GetParent()
    local pname = parent and parent.GetName and parent:GetName()
    return type(pname) == "string" and pname:find("BagsBar") ~= nil
end

local function Scan()
    if not EnumerateFrames then
        return
    end
    local f = EnumerateFrames()
    while f do
        if not buttons[f] and f.GetBagID and f.GetID and f.IsObjectType and f:IsObjectType("Button")
            and not IsBagBarButton(f) then
            buttons[f] = true
        end
        f = EnumerateFrames(f)
    end
    lastScan = GetTime()
end

---------------------------------------------------------------------------
-- Bag Reagents window
---------------------------------------------------------------------------
local win
local items = {} -- [itemID] = { id, name, icon, count, slots = { {bag, slot}, ... }, state, sub, price }
local selected = {} -- [itemID] = true
local collapsed = {} -- [group key] = true
local merchantOpen, tradeOpen, pendingTrade = false, false, 0
local ROW_H = 26
local SKILL_GROUPS = {
    { "orange", "Orange Skill Up" },
    { "yellow", "Yellow Skill Up" },
    { "green", "Green Skill Up" },
    { "gray", "No Skill Up" },
    { "blue", "Not Learned Yet" },
    { "other", "Other Professions" },
}
local SKILL_RANK, SKILL_LABEL = {}, {}
for i, g in ipairs(SKILL_GROUPS) do
    SKILL_RANK[g[1]] = i
    SKILL_LABEL[g[1]] = g[2]
end

---------------------------------------------------------------------------
-- Reagent protection: asks before a protected reagent is sold to a vendor.
-- While a vendor is open every protected slot gets a guard (an invisible button over the slot, with a small
-- lock): it takes the right-click, so nothing is sold until you answer "Sell Anyway".
-- Safety net for slots that have no guard (unknown bag frames): the sale is bought back and you are asked.
---------------------------------------------------------------------------
local bypass = {} -- [itemID] = time until which selling it is allowed (the user said yes)
local soldWatch = {} -- protected stacks just clicked at a vendor: { id, count, bag, slot, t }
local rescued = {} -- bought back, waiting for the answer: { id, count }

local function Protected(id, cache)
    if not ns.Get("protectReagents") then
        return false
    end
    if ns.Get("protect_farm") and ns.FarmHas and ns.FarmHas(id) then
        return true
    end
    local st = State(id, cache or {})
    return st and ns.Get("protect_" .. st) and true or false
end
ns.IsProtected = Protected

local function Allow(id, seconds)
    bypass[id] = GetTime() + (seconds or 20)
end

-- the question asked by a guard, before anything is sold
local function AskSell(bag, slot, id)
    local info = Safe(C_Container.GetContainerItemInfo, bag, slot)
    if type(info) ~= "table" or info.itemID ~= id then
        return
    end
    StaticPopupDialogs["REAGENTFARMING_PROTECT_ASK"] = StaticPopupDialogs["REAGENTFARMING_PROTECT_ASK"] or {
        text = "%s",
        button1 = "Sell Anyway",
        button2 = "Keep",
        OnAccept = function(_, d)
            if d and merchantOpen and Safe(C_Container.GetContainerItemID, d.bag, d.slot) == d.id then
                Allow(d.id, 2)
                pcall(C_Container.UseContainerItem, d.bag, d.slot)
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        showAlert = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("REAGENTFARMING_PROTECT_ASK", ("Protected reagent:\n%s%s|r x%d\n\nSell it anyway?"):format(
        ns.QualityColor(id), ns.ItemName(id), info.stackCount or 1), nil, { bag = bag, slot = slot, id = id })
end

-- guard over a protected slot while a vendor is open: takes the right-click (the sale), lets the rest through
local function Guard(button)
    local g = button.RFGuard
    if g then
        return g
    end
    g = CreateFrame("Button", nil, button)
    g:SetAllPoints()
    g:SetFrameLevel(button:GetFrameLevel() + 12)
    g:RegisterForClicks("RightButtonUp")
    if g.SetPassThroughButtons then -- left-click / drag still reach the slot
        pcall(g.SetPassThroughButtons, g, "LeftButton", "MiddleButton")
    end
    if not (g.SetPropagateMouseMotion and pcall(g.SetPropagateMouseMotion, g, true)) then
        g:SetScript("OnEnter", function() -- no pass-through for hovering: show the slot's tooltip ourselves
            local h = button:GetScript("OnEnter")
            if h then
                pcall(h, button)
            end
        end)
        g:SetScript("OnLeave", function()
            local h = button:GetScript("OnLeave")
            if h then
                pcall(h, button)
            end
        end)
    end
    g:SetScript("OnClick", function(self)
        if not merchantOpen then -- left over from a vendor visit: get out of the way
            self:Hide()
            return
        end
        AskSell(self.bag, self.slot, self.id)
    end)
    button.RFGuard = g
    return g
end

-- small gold lock in the corner of a protected reagent's slot (always, not only at a vendor)
local function LockMark(button)
    local m = button.RFLock
    if m then
        return m
    end
    m = CreateFrame("Frame", nil, button)
    m:SetAllPoints()
    m:SetFrameLevel(button:GetFrameLevel() + 11)
    local lock = m:CreateTexture(nil, "OVERLAY")
    lock:SetSize(14, 14)
    lock:SetPoint("TOPLEFT", 1, -1)
    if not lock:SetTexture(ns.Tex("Lock")) then -- our icon needs a client restart to load
        lock:SetTexture("Interface\\PetBattles\\PetBattle-LockIcon")
    end
    lock:SetVertexColor(1, 0.82, 0)
    button.RFLock = m
    return m
end

-- bag slot holding a stack of the item (the one with that count if possible)
local function FindStack(id, count)
    local fb, fs
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        for slot = 1, Safe(C_Container.GetContainerNumSlots, bag) or 0 do
            local info = Safe(C_Container.GetContainerItemInfo, bag, slot)
            if type(info) == "table" and info.itemID == id and not info.isLocked then
                if info.stackCount == count then
                    return bag, slot
                end
                fb, fs = fb or bag, fs or slot
            end
        end
    end
    return fb, fs
end

local function SellRescued()
    local list = rescued
    rescued = {}
    if not merchantOpen then
        ns.Print("The vendor is closed - nothing was sold.")
        return
    end
    for _, e in ipairs(list) do
        Allow(e.id)
        local bag, slot = FindStack(e.id, e.count)
        if bag then
            pcall(C_Container.UseContainerItem, bag, slot)
        end
    end
end

local function AskRescued()
    local names = {}
    for _, e in ipairs(rescued) do
        names[#names + 1] = ("%s%s|r x%d"):format(ns.QualityColor(e.id), ns.ItemName(e.id), e.count)
    end
    StaticPopupDialogs["REAGENTFARMING_PROTECT"] = StaticPopupDialogs["REAGENTFARMING_PROTECT"] or {
        text = "%s",
        button1 = "Sell Anyway",
        button2 = "Keep",
        OnAccept = SellRescued,
        OnCancel = function(_, _, reason)
            if reason ~= "override" then -- "override" = the same question shown again with one more item
                rescued = {}
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        showAlert = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("REAGENTFARMING_PROTECT", "Protected reagent - the sale was undone:\n"
        .. table.concat(names, "\n") .. "\n\nSell anyway?")
end

local function CheckSold()
    if #soldWatch == 0 then
        return
    end
    local keep, acted = {}, false
    for _, w in ipairs(soldWatch) do
        local gone = Safe(C_Container.GetContainerItemID, w.bag, w.slot) ~= w.id
        local done = false
        if gone and not acted and merchantOpen and GetNumBuybackItems then
            for i = GetNumBuybackItems(), 1, -1 do
                local link = GetBuybackItemLink(i)
                if type(link) == "string" and tonumber(link:match("item:(%d+)")) == w.id then
                    BuybackItem(i)
                    rescued[#rescued + 1] = { id = w.id, count = w.count }
                    acted, done = true, true -- one buy-back per pass: the list renumbers itself
                    break
                end
            end
        end
        if not done and GetTime() - w.t < 3 then
            keep[#keep + 1] = w
        end
    end
    soldWatch = keep
    if acted then
        AskRescued()
    end
    if #keep > 0 then
        C_Timer.After(0.3, CheckSold)
    end
end

local function WatchSale(bag, slot)
    if not merchantOpen or type(bag) ~= "number" or type(slot) ~= "number" then
        return
    end
    local info = Safe(C_Container.GetContainerItemInfo, bag, slot)
    local id = type(info) == "table" and info.itemID
    if type(id) ~= "number" or (issecretvalue and issecretvalue(id)) or info.hasNoValue then
        return
    end
    if ns.Get("protectBuyback") == false or (bypass[id] or 0) > GetTime() or not Protected(id) then
        return
    end
    soldWatch[#soldWatch + 1] = { id = id, count = info.stackCount or 1, bag = bag, slot = slot, t = GetTime() }
    C_Timer.After(0.3, CheckSold)
end

local ICON_BAG = "|TInterface\\Buttons\\Button-Backpack-Up:14:14|t"
local ICON_BANK = "|TInterface\\Icons\\INV_Box_02:14:14:0:0:64:64:5:59:5:59|t"

-- how many of the item are in the bank (total owned minus what is in the bags)
local function BankCount(id, inBags)
    local f = C_Item and C_Item.GetItemCount or GetItemCount
    local total = Safe(f, id, true) or 0
    return math.max(total - inBags, 0)
end

local function SellPrice(id)
    local f = C_Item and C_Item.GetItemInfo or GetItemInfo
    if not f then
        return 0
    end
    local r = { pcall(f, id) }
    return r[1] and type(r[12]) == "number" and r[12] or 0
end

-- cooking reagents are split into Fish and Meat (the game only has one "Cooking" type)
local FISH_WORDS = { "fish", "snapper", "trout", "salmon", "eel", "cod", "bass", "mackerel", "yellowtail", "grouper",
    "redgill", "albacore", "lobster", "clam", "squid", "shrimp", "crawdad", "crawler", "firefin", "bloodfin",
    "bonescale", "whitescale", "sunscale", "barbed gill", "puffer", "octopus", "sturgeon", "lamprey", "minnow",
    "herring", "barracuda", "feltail", "darter", "manta", "mullet", "pike", "perch", "carp", "tuna", "shark",
    "crab", "oyster", "mussel", "prawn", "angler" }

local function TypeName(id, subType, name)
    local f = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    local r = f and { pcall(f, id) } or {}
    local cooking = (r[1] and r[7] == 7 and r[8] == 8) or subType == "Cooking"
    if not cooking then
        return subType or "Other"
    end
    local n = " " .. (name or ""):lower() .. " "
    for _, w in ipairs(FISH_WORDS) do
        if n:find(w, 1, true) then
            return "Fish"
        end
    end
    return "Meat"
end

local function ScanBags()
    local out, cache = {}, {}
    if not (C_Container and C_Container.GetContainerItemInfo) then
        return out
    end
    local reagentFor = ns.Index().reagentFor
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        for slot = 1, Safe(C_Container.GetContainerNumSlots, bag) or 0 do
            local info = Safe(C_Container.GetContainerItemInfo, bag, slot)
            local id = type(info) == "table" and info.itemID
            if type(id) == "number" and not (issecretvalue and issecretvalue(id)) then
                local class, icon, _, subType = ns.ItemInstant(id)
                if reagentFor[id] or class == 7 then
                    local it = out[id]
                    if not it then
                        local name = ns.ItemName(id)
                        it = { id = id, count = 0, slots = {}, icon = icon, sub = TypeName(id, subType, name),
                            state = State(id, cache) or "other", name = name, price = SellPrice(id),
                            mine = {}, profs = {} }
                        local seen = {}
                        for _, r in ipairs(reagentFor[id] or {}) do
                            local p = r.profession
                            if p and not seen[p] then
                                seen[p] = true
                                it.profs[#it.profs + 1] = p
                                if ns.PlayerSkill(p) then
                                    it.mine[#it.mine + 1] = p
                                end
                            end
                        end
                        out[id] = it
                    end
                    it.count = it.count + (info.stackCount or 1)
                    it.slots[#it.slots + 1] = { bag, slot }
                    if info.isBound then
                        it.bound = true
                    end
                    if info.hasNoValue then
                        it.price = 0
                    end
                end
            end
        end
    end
    return out
end

-- rows to show: { header = true, key, label, items } and item tables
local function BuildList()
    items = ScanBags()
    for id in pairs(selected) do
        if not items[id] then
            selected[id] = nil
        end
    end
    local q = (win.search:GetText() or ""):lower()
    local mode = ns.Get("bagGroup")
    local byType, byProf = mode == "type", mode == "prof"
    local mine, hideGray = ns.Get("bagMine"), ns.Get("bagHideGray")
    local groups, order, labels = {}, {}, {}
    local function Put(key, label, it)
        if not groups[key] then
            groups[key] = {}
            order[#order + 1] = key
            labels[key] = label
        end
        table.insert(groups[key], it)
    end
    for _, it in pairs(items) do
        if not (mine and it.state == "other") and not (hideGray and it.state == "gray")
            and (q == "" or it.name:lower():find(q, 1, true)) then
            if byProf then -- under every profession that uses it, learned or not (yours only with the filter on)
                local list = mine and it.mine or it.profs
                for _, p in ipairs(list) do
                    local name = ns.ProfessionName(p) or tostring(p)
                    Put("p" .. p, (ns.ProfIcon(p, 16) or "") .. " " .. name, it)
                    labels["p" .. p .. "sort"] = (ns.PlayerSkill(p) and "0" or "1") .. name
                end
                if #list == 0 then
                    Put("pnone", "No Profession", it)
                    labels["pnonesort"] = "2"
                end
            elseif byType then
                Put(it.sub, it.sub, it)
            else
                Put(it.state, nil, it)
            end
        end
    end
    table.sort(order, function(a, b)
        if byProf then
            return labels[a .. "sort"] < labels[b .. "sort"]
        elseif byType then
            return a < b
        end
        return (SKILL_RANK[a] or 99) < (SKILL_RANK[b] or 99)
    end)
    local list = {}
    for _, key in ipairs(order) do
        local g = groups[key]
        table.sort(g, function(a, b)
            if (byType or byProf) and a.state ~= b.state then
                return (SKILL_RANK[a.state] or 99) < (SKILL_RANK[b.state] or 99)
            end
            return a.name < b.name
        end)
        local label = labels[key] or key
        if not byType and not byProf then
            local c = COLORS[key] or COLORS.other
            label = ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, SKILL_LABEL[key] or key)
        end
        list[#list + 1] = { header = true, key = key, label = label, items = g }
        if not collapsed[key] then
            for _, it in ipairs(g) do
                list[#list + 1] = it
            end
        end
    end
    return list
end

local function Selection()
    local n, value, stacks = 0, 0, 0
    for id in pairs(selected) do
        local it = items[id]
        if it then
            n = n + 1
            stacks = stacks + #it.slots
            value = value + it.price * it.count
        end
    end
    return n, value, stacks
end

-- { bag, slot, id } for every stack of the selected items that passes keep(it)
local function SelectedSlots(keep)
    local q = {}
    for id in pairs(selected) do
        local it = items[id]
        if it and (not keep or keep(it)) then
            for _, s in ipairs(it.slots) do
                q[#q + 1] = { s[1], s[2], id }
            end
        end
    end
    return q
end

local function StillThere(s)
    return Safe(C_Container.GetContainerItemID, s[1], s[2]) == s[3]
end

local Render

local function GroupAllSelected(g)
    for _, it in ipairs(g) do
        if not selected[it.id] then
            return false
        end
    end
    return #g > 0
end

local function CreateRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.bar = ns.HeaderBar(r)
    r.sel = r:CreateTexture(nil, "BACKGROUND", nil, 1)
    r.sel:SetAllPoints()
    if not ns.RowArt(r.sel, "selected") then
        r.sel:SetColorTexture(1, 0.82, 0.2, 0.18)
    end
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    if not ns.RowArt(hl, "hover") then
        hl:SetColorTexture(1, 1, 1, 0.08)
    end
    local ok, check = pcall(CreateFrame, "CheckButton", nil, r, "UICheckButtonTemplate")
    if not ok or not check then
        check = CreateFrame("CheckButton", nil, r)
    end
    check:SetSize(22, 22)
    check:SetPoint("LEFT", 2, 0)
    r.check = check
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(20, 20)
    r.icon:SetPoint("LEFT", check, "RIGHT", 2, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.price = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.price:SetPoint("RIGHT", -8, 0)
    r.price:SetWidth(92)
    r.price:SetJustifyH("RIGHT")
    -- two counters with their icons: in the bank, in the bags
    r.bank = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.bank:SetPoint("RIGHT", r.price, "LEFT", -4, 0)
    r.bank:SetWidth(52)
    r.bank:SetJustifyH("LEFT")
    r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.count:SetPoint("RIGHT", r.bank, "LEFT", 0, 0)
    r.count:SetWidth(42) -- bag counter sits close to the bank counter
    r.count:SetJustifyH("LEFT")
    r.skill = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.skill:SetPoint("RIGHT", r.count, "LEFT", -14, 0) -- clear gap between the skill-up arrow and the counters
    r.skill:SetWidth(18)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.sign = r:CreateFontString(nil, "OVERLAY", ns.HEADER_FONT)
    r.sign:SetPoint("RIGHT", -10, 0)

    local function Toggle(d)
        if d.header then
            local on = not GroupAllSelected(d.items)
            for _, it in ipairs(d.items) do
                selected[it.id] = on or nil
            end
        else
            selected[d.id] = not selected[d.id] or nil
        end
        Render()
    end
    check:SetScript("OnClick", function()
        Toggle(r.data)
    end)
    r:SetScript("OnClick", function(self, button)
        local d = self.data
        if d.header then
            collapsed[d.key] = not collapsed[d.key] or nil
            Render()
        elseif button == "RightButton" then
            if ns.ShowReagent then
                ns.ShowReagent(d.id)
            end
        else
            Toggle(d)
        end
    end)
    r:SetScript("OnEnter", function(self)
        local d = self.data
        if d and not d.header then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if not pcall(GameTooltip.SetItemByID, GameTooltip, d.id) then
                GameTooltip:SetText(d.name)
            end
            GameTooltip:AddLine("Right-Click: open in Grist for the Mill", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    return r
end

local function UpdateRow(r, d)
    r.data = d
    r.name:ClearAllPoints()
    if d.header then
        r.bar:SetShown(true)
        r.sel:Hide()
        r.icon:Hide()
        r.skill:SetText("")
        r.count:SetText("")
        r.bank:SetText("")
        r.price:SetText("")
        r.sign:SetText(ns.SignText(not collapsed[d.key]))
        r.name:SetFontObject(ns.HEADER_FONT)
        r.name:SetPoint("LEFT", r.check, "RIGHT", 4, 0)
        r.name:SetPoint("RIGHT", r.sign, "LEFT", -6, 0)
        r.name:SetText(("%s |cffffffff(%d)|r"):format(d.label, #d.items))
        r.check:SetChecked(GroupAllSelected(d.items))
    else
        r.bar:SetShown(false)
        r.sel:SetShown(selected[d.id] and true or false)
        r.icon:SetTexture(d.icon)
        r.icon:Show()
        r.sign:SetText("")
        r.name:SetFontObject("GameFontHighlight")
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.name:SetPoint("RIGHT", r.skill, "LEFT", -4, 0)
        r.name:SetText(ns.QualityColor(d.id) .. d.name .. "|r")
        r.skill:SetText(ns.SkillIcon and ns.SkillIcon(d.state, 14) or "")
        r.count:SetText(ICON_BAG .. " " .. d.count)
        local bank = BankCount(d.id, d.count)
        r.bank:SetText(ICON_BANK .. " " .. (bank > 0 and bank or "|cff7070700|r"))
        r.price:SetText(d.price > 0 and ns.Money(d.price * d.count, 11) or "|cff808080No value|r")
        r.check:SetChecked(selected[d.id] and true or false)
    end
end

-- sticky group headers (same behaviour as the recipe lists of the main window): headers scrolled past dock
-- at the top, headers further down dock at the bottom; clicking a docked header scrolls to its group
local stick, stickPool = {}, {} -- stick = { { y, data, frame }, ... } in list order
local function UpdateSticky()
    if not win then
        return
    end
    local scroll = win.scroll
    local used = 0
    for _, r in ipairs(win.rows) do
        r:SetAlpha(1)
    end
    if #stick > 0 and ns.Get("stickyHeaders") then
        local s, vh, w = scroll:GetVerticalScroll(), scroll:GetHeight(), scroll:GetWidth()
        local function Dock(it, point, offset, target)
            it.frame:SetAlpha(0) -- the real header hides while its docked copy shows
            used = used + 1
            local f = stickPool[used]
            if not f then
                f = CreateRow(scroll)
                f:SetFrameLevel(scroll:GetFrameLevel() + 20)
                local back = f:CreateTexture(nil, "BACKGROUND", nil, -8) -- the list must not show through
                back:SetAllPoints()
                back:SetColorTexture(0.05, 0.04, 0.03, 1)
                f:SetScript("OnClick", function(self)
                    if self.dockBottom then -- its group is below the visible part: bring it into view
                        scroll:SetVerticalScroll(math.max(math.min(self.target, scroll:GetVerticalScrollRange()), 0))
                    else -- docked on top: stays where it is, just collapses / expands its group
                        local d = self.data
                        collapsed[d.key] = not collapsed[d.key] or nil
                        Render()
                    end
                end)
                stickPool[used] = f
            end
            f.dockBottom = point == "BOTTOM"
            f:ClearAllPoints()
            f:SetPoint(point .. "LEFT", scroll, point .. "LEFT", 0, offset)
            f:SetWidth(w)
            UpdateRow(f, it.data)
            f.target = target
            f:Show()
        end
        -- with many groups the docked headers would cover the whole list, so only the nearest ones dock:
        -- together they take at most ~45% of the visible height (the closest few above and below)
        local n = #stick
        local maxDock = math.max(2, math.floor(vh * 0.45 / ROW_H))
        local topCap = math.max(1, math.floor(maxDock / 2))
        local botCap = math.max(1, maxDock - topCap)
        -- headers scrolled past: header i docks when it reaches the (capped) slot it will take
        local topCount = 0
        for i, it in ipairs(stick) do
            if it.y - s < math.min(i - 1, topCap - 1) * ROW_H - 0.5 then
                topCount = i
            else
                break
            end
        end
        local first = math.max(topCount - topCap + 1, 1)
        for i = first, topCount do
            local it = stick[i]
            Dock(it, "TOP", -(i - first) * ROW_H, it.y - math.min(i - 1, topCap) * ROW_H)
        end
        -- headers below the visible part: the first one out of view and the next few after it
        local firstOff
        for i = topCount + 1, n do
            if stick[i].y - s + ROW_H > vh - math.min(n - i, botCap - 1) * ROW_H + 0.5 then
                firstOff = i
                break
            end
        end
        if firstOff then
            local docked = math.min(n - firstOff + 1, botCap)
            for j = 0, docked - 1 do
                local i = firstOff + j
                local it = stick[i]
                Dock(it, "BOTTOM", (docked - 1 - j) * ROW_H, it.y - math.min(i - 1, topCap) * ROW_H)
            end
        end
    end
    for i = used + 1, #stickPool do
        stickPool[i]:Hide()
    end
end

Render = function()
    if not (win and win:IsShown()) then
        return
    end
    if win.group and win.group.Update then
        win.group.Update() -- the choice may have been changed from the Settings tab
    end
    local list = BuildList()
    local child = win.child
    local w = win.scroll:GetWidth()
    child:SetSize(w, math.max(#list * ROW_H, 1))
    for i, d in ipairs(list) do
        local r = win.rows[i]
        if not r then
            r = CreateRow(child)
            r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
            r:SetPoint("RIGHT", child, "RIGHT", 0, 0)
            win.rows[i] = r
        end
        UpdateRow(r, d)
        r:Show()
    end
    for i = #list + 1, #win.rows do
        win.rows[i]:Hide()
    end
    stick = {}
    for i, d in ipairs(list) do
        if d.header then
            stick[#stick + 1] = { y = (i - 1) * ROW_H, data = d, frame = win.rows[i] }
        end
    end
    UpdateSticky()
    win.empty:SetShown(#list == 0)
    local n, value = Selection()
    if n == 0 then
        win.summary:SetText("")
    else
        win.summary:SetText(("%d selected   %s"):format(n, ns.Money(value, 12)))
    end
    win.sell:SetEnabled(n > 0 and merchantOpen)
    win.trade:SetEnabled(n > 0)
    win.delete:SetEnabled(n > 0)
end

local renderPending
local function ScheduleRender()
    if renderPending or not (win and win:IsShown()) then
        return
    end
    renderPending = true
    C_Timer.After(0.15, function()
        renderPending = false
        pcall(Render)
    end)
end

local function Confirm(text, fn)
    StaticPopupDialogs["REAGENTFARMING_BAGS"] = StaticPopupDialogs["REAGENTFARMING_BAGS"] or {
        text = "%s",
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function(_, data)
            if data then
                data()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        showAlert = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("REAGENTFARMING_BAGS", text, nil, fn)
end

local function SellSelected()
    if not merchantOpen then
        ns.Print("Open a vendor to sell.")
        return
    end
    local q = SelectedSlots(function(it)
        return it.price > 0
    end)
    if #q == 0 then
        ns.Print("Nothing selected has a vendor price.")
        return
    end
    local n, value = Selection()
    local guarded = 0
    for id in pairs(selected) do
        if items[id] and Protected(id) then
            guarded = guarded + 1
        end
    end
    local warn = guarded > 0 and ("\n|cffff4040%d of them protected|r"):format(guarded) or ""
    local ask = (ns.Get("bagConfirm") ~= false or guarded > 0) and Confirm or function(_, fn)
        fn()
    end
    ask(("Sell %d selected reagent(s) for %s?%s"):format(n, ns.Money(value, 12), warn), function()
        local i = 0
        local function Step() -- a few stacks per tick, so the server doesn't throttle
            if not merchantOpen then
                return
            end
            for _ = 1, 4 do
                i = i + 1
                local s = q[i]
                if not s then
                    return
                end
                if StillThere(s) then
                    Allow(s[3]) -- already confirmed: don't ask again per stack
                    pcall(C_Container.UseContainerItem, s[1], s[2])
                end
            end
            C_Timer.After(0.25, Step)
        end
        Step()
    end)
end

local function TradeSelected()
    if not tradeOpen then
        if InitiateTrade and UnitExists("target") and UnitIsPlayer("target") and UnitIsFriend("player", "target") then
            pendingTrade = GetTime()
            pcall(InitiateTrade, "target")
        else
            ns.Print("Open a trade window, or target a player, then press Trade.")
        end
        return
    end
    local q = SelectedSlots(function(it)
        return not it.bound
    end)
    local max = (MAX_TRADABLE_ITEMS or 7) - 1 -- the last slot is "will not be traded"
    local slot, placed = 0, 0
    for _, s in ipairs(q) do
        repeat
            slot = slot + 1
        until slot > max or not Safe(GetTradePlayerItemInfo, slot)
        if slot > max then
            break
        end
        if StillThere(s) then
            ClearCursor()
            C_Container.PickupContainerItem(s[1], s[2])
            ClickTradeButton(slot)
            placed = placed + 1
        end
    end
    ClearCursor()
    if placed < #q then
        ns.Print(("Trade window full: %d of %d stacks added."):format(placed, #q))
    end
end

local function DeleteSelected()
    local n, _, stacks = Selection()
    if n == 0 then
        return
    end
    local q = SelectedSlots()
    Confirm(("Delete %d selected reagent(s) (%d stacks)?\n|cffff4040This cannot be undone.|r"):format(n, stacks), function()
        for _, s in ipairs(q) do
            if StillThere(s) then
                ClearCursor()
                C_Container.PickupContainerItem(s[1], s[2])
                if CursorHasItem() then
                    DeleteCursorItem()
                end
            end
        end
        ClearCursor()
        ScheduleRender()
    end)
end

local function ActionButton(parent, label, tip, onClick)
    local b = ns.CreateButton(parent, label, 72)
    if b.SetMotionScriptsWhileDisabled then
        b:SetMotionScriptsWhileDisabled(true)
    end
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(label)
        GameTooltip:AddLine(tip, 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

local function CreateWindow()
    local own = ns.LayoutWidget("BagWindow") -- a layout may bring its own window frame
    local ok, f
    if own then
        f = own("GristForTheMillBags")
        ok = f ~= nil
    else
        ok, f = pcall(CreateFrame, "Frame", "GristForTheMillBags", UIParent, "PortraitFrameTemplate")
    end
    if not ok or not f then
        f = CreateFrame("Frame", "GristForTheMillBags", UIParent, "BackdropTemplate")
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        f:SetBackdropColor(0.05, 0.04, 0.03, 0.9)
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -1, -1)
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -8)
        title:SetText("Bag Reagents")
    end
    if f.Bg then
        f.Bg:SetColorTexture(0.05, 0.04, 0.03, 0.85)
    end
    if f.TopTileStreaks then
        f.TopTileStreaks:Hide()
    end
    if f.SetTitle then
        f:SetTitle("Bag Reagents")
    end
    local portrait = f.PortraitContainer and f.PortraitContainer.portrait or f.portrait
    if f.SetPortraitToAsset then
        pcall(f.SetPortraitToAsset, f, BAG_ICON)
    elseif portrait then
        portrait:SetTexture(BAG_ICON)
    end
    local size = HelperDB and HelperDB.bagWinSize
    f:SetSize(size and size[1] or 480, size and size[2] or 520)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetLeft(), self:GetTop()
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
        HelperDB.bagWinPos = { x, y }
    end)
    if UISpecialFrames then
        table.insert(UISpecialFrames, "GristForTheMillBags") -- Escape closes it
    end
    -- resize: rows stretch with the window, fonts and icons keep their size
    if f.SetResizeBounds then
        f:SetResizeBounds(400, 280, 1000, 1200)
    end
    ns.ResizeGrip(f, nil, ScheduleRender, function()
        HelperDB.bagWinSize = { f:GetWidth(), f:GetHeight() }
        local x, y = f:GetLeft(), f:GetTop()
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
        HelperDB.bagWinPos = { x, y }
        Render()
    end, function()
        f:SetSize(480, 520)
    end)

    -- search + Filter
    local search = ns.CreateSearchBox(f)
    search:SetPoint("TOPLEFT", 70, -32)
    search:SetPoint("RIGHT", f, "RIGHT", -108, 0)
    search:HookScript("OnTextChanged", ScheduleRender)
    f.search = search
    local function FilterMenu(_, root)
        local function Toggle(key, label, tip)
            local item = root:CreateCheckbox(label, function()
                return ns.Get(key) and true or false
            end, function()
                ns.Set(key, not ns.Get(key))
                Render()
            end)
            if item and item.SetTooltip then
                item:SetTooltip(function(tooltip)
                    GameTooltip_SetTitle(tooltip, label)
                    GameTooltip_AddNormalLine(tooltip, tip)
                end)
            end
        end
        Toggle("bagMine", "My Professions Only", "Hide reagents that none of your professions use")
        Toggle("bagHideGray", "Hide No Skill Up", "Hide reagents whose recipes no longer give skill")
    end
    local okF, filter = pcall(CreateFrame, "DropdownButton", nil, f, "WowStyle1FilterDropdownTemplate")
    if okF and filter and filter.SetupMenu then
        filter:SetText("Filter")
        filter:SetupMenu(FilterMenu)
    else
        filter = ns.CreateButton(f, "Filter", 90)
        filter:SetScript("OnClick", function(self)
            if MenuUtil and MenuUtil.CreateContextMenu then
                MenuUtil.CreateContextMenu(self, FilterMenu)
            end
        end)
    end
    filter:SetSize(90, 22)
    filter:SetPoint("LEFT", search, "RIGHT", 4, 0)

    -- Group By
    local group = ns.CreateSegmented(f, { { "Skill Up", "skill" }, { "Profession", "prof" }, { "Type", "type" } }, 280,
        function()
        return ns.Get("bagGroup")
    end, function(v)
        ns.Set("bagGroup", v)
        Render()
    end, "Group by")
    group:SetPoint("TOPLEFT", 70, -60)
    f.group = group

    -- list
    local card = ns.Card(f)
    card:SetPoint("TOPLEFT", 10, -92)
    card:SetPoint("BOTTOMRIGHT", -10, 42)
    local okS, scroll = pcall(CreateFrame, "ScrollFrame", nil, card, "ScrollFrameTemplate")
    if not okS or not scroll or not scroll.ScrollBar then
        scroll = CreateFrame("ScrollFrame", nil, card, "UIPanelScrollFrameTemplate")
    end
    scroll:SetPoint("TOPLEFT", 5, -5)
    scroll:SetPoint("BOTTOMRIGHT", -26, 5)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    f.scroll, f.child, f.rows = scroll, child, {}
    scroll:HookScript("OnVerticalScroll", UpdateSticky)
    scroll:HookScript("OnSizeChanged", UpdateSticky)
    f.empty = card:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.empty:SetPoint("CENTER")
    f.empty:SetText("No reagents in your bags match")

    -- footer: selection summary + actions
    f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.summary:SetPoint("BOTTOMLEFT", 14, 16)
    f.delete = ActionButton(f, "Delete", "Destroy every stack of the ticked reagents (asks first)", DeleteSelected)
    f.delete:SetPoint("BOTTOMRIGHT", -24, 10) -- clear of the resize grip
    f.trade = ActionButton(f, "Trade", "Put the ticked reagents in the trade window.\nNo trade open: starts one with your target.",
        TradeSelected)
    f.trade:SetPoint("RIGHT", f.delete, "LEFT", -4, 0)
    f.sell = ActionButton(f, "Sell", "Sell the ticked reagents to the open vendor (asks first)", SellSelected)
    f.sell:SetPoint("RIGHT", f.trade, "LEFT", -4, 0)

    f:SetScript("OnShow", function()
        C_Timer.After(0, Render)
    end)
    f:Hide()
    return f
end

function ns.ToggleBagReagents(anchor)
    if not win then
        win = CreateWindow()
    end
    if win:IsShown() then
        win:Hide()
        return
    end
    win:ClearAllPoints()
    local pos = HelperDB and HelperDB.bagWinPos
    if pos then
        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos[1], pos[2])
    elseif anchor and anchor.GetLeft and anchor:GetLeft() then -- above the bag button
        win:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 30)
    else
        win:SetPoint("CENTER")
    end
    win:Show()
end

---------------------------------------------------------------------------
-- Bag button: small icon attached to Blizzard's backpack button (bag bar)
---------------------------------------------------------------------------
local bagButton
local function AttachBagButton()
    local root = _G.MainMenuBarBackpackButton
    local b = bagButton
    if b then
        b:SetShown(ns.Get("bagButton") and true or false)
        return
    end
    if not root or not ns.Get("bagButton") then
        return
    end
    b = CreateFrame("Button", nil, root)
    bagButton = b
    b:SetSize(20, 20)
    b:SetPoint("CENTER", root, "TOPRIGHT", -3, -3) -- on the top-right corner, overlapping the bag icon a little
    b:SetFrameLevel(root:GetFrameLevel() + 5)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(BAG_ICON)
    icon:SetTexCoord(0.12, 0.88, 0.12, 0.88)
    if b.CreateMaskTexture then -- round: cuts away the dark square the icon art is painted on
        local mask = b:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
    end
    -- gold ring around the icon (the minimap button border, which is drawn for a 20 px icon)
    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetTexture([[Interface\Minimap\MiniMap-TrackingBorder]])
    ring:SetSize(53, 53)
    ring:SetPoint("TOPLEFT", b, "TOPLEFT", -6, 5)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetSize(34, 34) -- the glow ring only fills ~60% of this texture: oversize it to match the icon
    hl:SetPoint("CENTER")
    hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    hl:SetBlendMode("ADD")
    b:SetScript("OnClick", function()
        ns.ToggleBagReagents(root)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Bag Reagents")
        GameTooltip:AddLine("Every reagent in your bags: sell, trade or delete several at once", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
end

---------------------------------------------------------------------------
-- Refresh: borders on every visible item button, bag button on the backpack's window
---------------------------------------------------------------------------
local function Refresh()
    if GetTime() - lastScan > 5 then
        Scan()
    end
    local on = ns.Get("bagBorders")
    local cache = {}
    pcall(AttachBagButton)
    for button in pairs(buttons) do
        local st
        if button:IsVisible() then
            local okB, bag = pcall(button.GetBagID, button)
            local slot = button:GetID()
            local id
            if okB and type(bag) == "number" and C_Container and C_Container.GetContainerItemID then
                local ok, v = pcall(C_Container.GetContainerItemID, bag, slot)
                id = ok and v or nil
            end
            local plain = type(id) == "number" and not (issecretvalue and issecretvalue(id))
            local protected = plain and Protected(id, cache)
            if protected and ns.Get("bagLock") ~= false then
                LockMark(button):Show()
            elseif button.RFLock then
                button.RFLock:Hide()
            end
            -- vendor open: guard protected slots so a right-click asks first instead of selling
            if protected and merchantOpen and (bypass[id] or 0) <= GetTime() then
                local g = Guard(button)
                g.bag, g.slot, g.id = bag, slot, id
                g:Show()
            elseif button.RFGuard then
                button.RFGuard:Hide()
            end
            if on and plain then
                st = State(id, cache)
                if st and ns.Get("bagColor_" .. st) == false then -- this colour is switched off
                    st = nil
                end
            end
        end
        if st then
            Border(button):Set(COLORS[st])
        elseif button.RFBorder then
            button.RFBorder:Hide()
        end
        if button.RFLock and not button:IsVisible() then
            button.RFLock:Hide()
        end
    end
end

local pending
local function Schedule(delay)
    if pending then
        return
    end
    pending = true
    C_Timer.After(delay or 0.3, function()
        pending = false
        local ok, err = pcall(Refresh)
        if not ok and geterrorhandler then -- surface it in the error log instead of failing silently
            geterrorhandler()(err)
        end
    end)
end
ns.RefreshBagBorders = Schedule

local events = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "BAG_OPEN", "PLAYERBANKSLOTS_CHANGED", "BANKFRAME_OPENED",
    "SKILL_LINES_CHANGED", "TRADE_SKILL_LIST_UPDATE", "LEARNED_SPELL_IN_TAB", "NEW_RECIPE_LEARNED",
    "MERCHANT_SHOW", "MERCHANT_CLOSED", "TRADE_SHOW", "TRADE_CLOSED" }) do
    pcall(events.RegisterEvent, events, ev)
end
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        for _, fn in ipairs({ "OpenAllBags", "ToggleAllBags", "ToggleBackpack", "OpenBackpack", "ToggleBag", "OpenBag" }) do
            if type(_G[fn]) == "function" then
                hooksecurefunc(fn, function()
                    lastScan = 0
                    Schedule(0.2)
                end)
            end
        end
        ns.OnSetting("bagBorders", function()
            Schedule(0)
        end)
        if C_Container and C_Container.UseContainerItem then
            hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
                pcall(WatchSale, bag, slot)
            end)
        end
        ns.OnSetting("stickyHeaders", function()
            pcall(UpdateSticky)
        end)
        for _, key in ipairs({ "bagGroup", "bagMine", "bagHideGray" }) do -- changed from the Settings tab
            ns.OnSetting(key, function()
                ScheduleRender()
            end)
        end
        -- watch for the bag being opened: bag addons build their slots late and don't always go through the
        -- Blizzard open functions, so the first open after a reload would otherwise stay unpainted
        if C_Timer.NewTicker then
            local wasVisible = 0 -- item slots on screen at the last check
            local function Repaint()
                lastScan = 0
                Schedule(0)
            end
            local function VisibleCount()
                local n = 0
                for button in pairs(buttons) do
                    if button:IsVisible() then
                        n = n + 1
                    end
                end
                return n
            end
            C_Timer.NewTicker(0.5, function()
                local n = VisibleCount()
                -- look for new slots: every second while none is on screen (bag addons create a bag's
                -- slots the first time it opens), every 3 s otherwise
                if GetTime() - lastScan > (n == 0 and 1 or 3) and not (InCombatLockdown and InCombatLockdown()) then
                    Scan()
                    n = VisibleCount()
                end
                if n > 0 and n ~= wasVisible then -- slots appeared (or more of them): paint
                    Repaint()
                    C_Timer.After(0.6, Repaint) -- again once the slots have their items
                end
                wasVisible = n
            end)
        end
        for _, key in ipairs({ "bagBorderSize", "bagGlow", "bagLock", "protectReagents", "protect_orange", "protect_yellow", "protect_green", "protect_gray",
            "protect_blue", "protect_farm", "bagButton", "bagColor_orange", "bagColor_yellow", "bagColor_green", "bagColor_gray",
            "bagColor_blue" }) do
            ns.OnSetting(key, function()
                Schedule(0)
            end)
        end
    elseif event == "MERCHANT_SHOW" or event == "MERCHANT_CLOSED" then
        merchantOpen = event == "MERCHANT_SHOW"
        if not merchantOpen then
            soldWatch = {}
        end
        lastScan = 0 -- guards go on / come off right away
    elseif event == "TRADE_SHOW" or event == "TRADE_CLOSED" then
        tradeOpen = event == "TRADE_SHOW"
        if tradeOpen and GetTime() - pendingTrade < 15 then -- the trade we asked for has opened
            pendingTrade = 0
            C_Timer.After(0.1, function()
                pcall(TradeSelected)
            end)
        end
    end
    ScheduleRender()
    Schedule()
end)
