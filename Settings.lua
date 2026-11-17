-- Settings: defaults, ns.Get / ns.Set, and the Settings tab (menu on the left, one page per entry).
local _, ns = ...

local DEFAULTS = {
    minimap = true, -- minimap button
    stickyHeaders = true, -- category headers dock at the top / bottom of a list while scrolling
    autoOpen = true, -- open Helper next to the profession window when it opens
    scale = 0.85, -- window scale (max 1 = designed size)
    loadMessage = true, -- "loaded" line in chat
    includeBank = true, -- reagent counts include the bank
    allProfs = false, -- show every profession, not just yours
    listGroup = "prof", -- Your Reagents grouped by "prof" or "type"
    bagBorders = true, -- coloured borders on reagents in your bags
    bagBorderSize = 3, -- thickness of the coloured frame (px)
    bagGlow = true, -- glow around the coloured frame
    bagConfirm = true, -- Bag Reagents: ask before the Sell button sells
    filterLearned = false, -- reagent list: only reagents of learned recipes
    filterSkillUp = false, -- reagent list: only reagents of recipes that still give skill
    filterCraftable = false, -- reagent list: only reagents of recipes you can craft now
    ttProtected = true, -- item tooltips: lock + "Protected" on protected reagents
    bagLock = true, -- bags: small lock on the slots of protected reagents
    protectBuyback = true, -- buy back a protected reagent sold from a slot that had no guard
    craftAutoOpen = true, -- crafting: open the Crafting window when a recipe is tracked
    craftSilent = true, -- crafting: craft from the Crafting window without showing the profession window
    craftReqs = true, -- crafting: list anvil / cooking fire / tools needed
    bagColor_orange = true, -- bag borders per skill-up colour
    bagColor_yellow = true,
    bagColor_green = true,
    bagColor_gray = true,
    bagColor_blue = true, -- used by your professions, recipe not learned yet
    df_orange = true, -- recipe filter of the detail pane: skill-up colours shown
    df_yellow = true,
    df_green = true,
    df_gray = true,
    df_red = true, -- locked: skill level too low
    ttLearned = true, -- item tooltips: tick / cross / lock in front of each recipe
    df_learned = true,
    df_unlearned = true,
    df_mats = false, -- only recipes you have every material for
    protectReagents = true, -- ask before a protected reagent is sold to a vendor
    protect_orange = true, -- which reagents are protected, by skill-up colour
    protect_yellow = true,
    protect_green = true,
    protect_gray = false,
    protect_blue = true, -- used by your professions, recipe not learned yet
    protect_farm = true, -- items on the Farming list
    bagButton = true, -- button on the bag that opens the Bag Reagents window
    bagGroup = "skill", -- Bag Reagents grouped by "skill" (skill-up colour) or "type"
    bagMine = false, -- Bag Reagents: only reagents your professions use
    bagHideGray = false, -- Bag Reagents: hide reagents that no longer give skill
    ctrlClick = true, -- Ctrl + Right-Click a reagent in bags opens Helper
    ttUsedIn = true, -- item tooltips: recipes using the reagent
    ttProfIcons = true, -- item tooltips: profession icons
    ttMax = 10, -- item tooltips: recipes listed
    farmPopup = true, -- farming: popup when a goal is reached
    farmSound = true, -- farming: sound with the popup
    farmAutoTracker = true, -- farming: open the tracker window when something is added
    trackerDocking = true, -- dragging the Farming / Crafting window next to the other docks them together
    findTarget = true, -- arrow buttons pointing at an NPC that is close by also target and star it
    layout = "classic", -- look of the addon: "classic" or "modern" (see Layout.lua); read at login
    vendorPrompt = true, -- at a vendor: offer to buy what the farming / crafting lists still need
}
ns.DEFAULTS = DEFAULTS

local listeners = {}

function ns.Get(key)
    local s = HelperDB and HelperDB.settings
    if s and s[key] ~= nil then
        return s[key]
    end
    return DEFAULTS[key]
end

function ns.Set(key, value)
    HelperDB.settings = HelperDB.settings or {}
    HelperDB.settings[key] = value
    for _, fn in ipairs(listeners[key] or {}) do
        pcall(fn, value)
    end
    if ns.RefreshReagents then
        ns.RefreshReagents()
    end
end

-- run fn(value) whenever a setting changes
function ns.OnSetting(key, fn)
    listeners[key] = listeners[key] or {}
    table.insert(listeners[key], fn)
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
local ROW = 26 -- label only: the description shows as a tooltip on mouseover

local function Checkbox(parent, key, label, desc)
    local T = ns.T
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW)
    local hover = row:CreateTexture(nil, "BACKGROUND")
    hover:SetPoint("TOPLEFT", -8, 0)
    hover:SetPoint("BOTTOMRIGHT", 8, 0)
    hover:SetColorTexture(1, 0.82, 0, 0.06)
    hover:Hide()
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", 0, 0)
    text:SetText(label)
    row.tip = desc
    local sw = ns.CreateSwitch(row, function()
        return ns.Get(key)
    end, function(v)
        ns.Set(key, v)
    end)
    sw:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.Update = sw.Update
    row:SetScript("OnClick", function()
        sw:Click()
    end)
    row:SetScript("OnEnter", function(self)
        hover:Show()
        text:SetTextColor(1, 0.82, 0)
        if desc and desc ~= "" then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(label)
            GameTooltip:AddLine(desc, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function()
        hover:Hide()
        text:SetTextColor(unpack(T.text))
        GameTooltip:Hide()
    end)
    -- the tick box sits on top of the row: hovering it shows the same tooltip
    sw:HookScript("OnEnter", function()
        row:GetScript("OnEnter")(row)
    end)
    sw:HookScript("OnLeave", function()
        row:GetScript("OnLeave")(row)
    end)
    return row
end

-- slider: rounded track, round accent thumb, live value; applies on mouse-up
local function Slider(parent, key, label, minV, maxV, step, fmt)
    local T = ns.T
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(44)
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 0, -2)
    text:SetText(label)
    local value = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    value:SetPoint("TOPRIGHT", 0, -2)
    value:SetTextColor(unpack(T.accent))
    local s = CreateFrame("Slider", nil, row, "BackdropTemplate")
    s:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -12)
    s:SetPoint("RIGHT", row, "RIGHT")
    s:SetHeight(10)
    ns.Skin(s, T.panel, T.border, 4)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:SetThumbTexture(ns.Tex("Circle"))
    local thumb = s:GetThumbTexture()
    thumb:SetSize(16, 16)
    thumb:SetVertexColor(unpack(T.accent))
    local fill = s:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", 2, 0)
    fill:SetPoint("RIGHT", thumb, "CENTER")
    fill:SetHeight(4)
    fill:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.6)
    local function Show(v)
        value:SetText(fmt(v))
    end
    s:SetScript("OnValueChanged", function(_, v)
        Show(v)
    end)
    s:SetScript("OnMouseUp", function(self)
        local v = math.floor(self:GetValue() / step + 0.5) * step
        ns.Set(key, v)
    end)
    function row.Update()
        s:SetValue(ns.Get(key))
        Show(ns.Get(key))
    end
    row.Update()
    return row
end

-- one row of small tick boxes with coloured labels; options = { { key, label, {r, g, b}, tip }, ... }
local function CheckRow(parent, options)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(26)
    local boxes = {}
    for i, o in ipairs(options) do
        local ok, cb = pcall(CreateFrame, "CheckButton", nil, row, "UICheckButtonTemplate")
        if not ok or not cb then
            cb = CreateFrame("CheckButton", nil, row)
        end
        cb:SetSize(24, 24)
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", cb, "RIGHT", 1, 0)
        label:SetText(o[2])
        label:SetTextColor(o[3][1], o[3][2], o[3][3])
        cb:SetScript("OnClick", function(self)
            ns.Set(o[1], self:GetChecked() and true or false)
        end)
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(o[2], o[3][1], o[3][2], o[3][3])
            GameTooltip:AddLine(o[4], 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        boxes[i] = cb
    end
    row:SetScript("OnSizeChanged", function(self, w) -- spread evenly over the row
        local step = w / #boxes
        for i, cb in ipairs(boxes) do
            cb:ClearAllPoints()
            cb:SetPoint("LEFT", self, "LEFT", (i - 1) * step - 4, 0)
        end
    end)
    function row.Update()
        for i, cb in ipairs(boxes) do
            cb:SetChecked(ns.Get(options[i][1]) and true or false)
        end
    end
    return row
end

local function Card(parent, title)
    local c = ns.Card(parent, nil, 12)
    -- title on a category bar, like the reagent list headers
    local bar = CreateFrame("Frame", nil, c)
    bar:SetPoint("TOPLEFT", 6, -6)
    bar:SetPoint("TOPRIGHT", -6, -6)
    bar:SetHeight(24)
    ns.HeaderBar(bar, 24, true)
    local t = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("LEFT", bar, "LEFT", 10, 0)
    t:SetText(title)
    t:SetTextColor(1, 0.82, 0)
    c.y = -38
    function c.Add(self, widget)
        widget:SetPoint("TOPLEFT", self, "TOPLEFT", 16, self.y)
        widget:SetPoint("RIGHT", self, "RIGHT", -16, 0)
        self.y = self.y - widget:GetHeight() - 4
        self:SetHeight(-self.y + 10)
        return widget
    end
    return c
end

-- label on the left, joined choice bar on the right; options = { { label, value }, ... }
local function Choice(parent, key, label, options, desc)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(28)
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", 0, 0)
    text:SetText(label)
    local seg = ns.CreateSegmented(row, options, math.min(#options * 100, 320), function()
        return ns.Get(key)
    end, function(v)
        ns.Set(key, v)
    end)
    seg:SetPoint("RIGHT", 0, 0)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if desc then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(label)
            GameTooltip:AddLine(desc, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row.Update = seg.Update
    return row
end

-- small gold caption between groups of options on a page
local function Caption(parent, text)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(24)
    local t = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("BOTTOMLEFT", 0, 4)
    t:SetText(text)
    local line = row:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    line:SetHeight(1)
    line:SetColorTexture(0.55, 0.42, 0.18, 0.6)
    function row.Update()
    end
    return row
end

---------------------------------------------------------------------------
-- Pages: one per entry of the menu on the left. Entry kinds:
--   { "check", key, label, description }      { "slider", key, label, min, max, step, description }
--   { "choice", key, label, options, description }   { "colors", prefix, what }   { "caption", text }
---------------------------------------------------------------------------
local SKILL_COLORS = {
    { "orange", "Orange", { 1, 0.5, 0.25 }, "recipes that always give a skill point" },
    { "yellow", "Yellow", { 1, 0.9, 0.1 }, "recipes that usually give a skill point" },
    { "green", "Green", { 0.3, 0.85, 0.3 }, "recipes that rarely give a skill point" },
    { "gray", "Gray", { 0.7, 0.7, 0.72 }, "learned recipes that no longer give skill" },
    { "blue", "Unlearned", { 0.3, 0.6, 1 }, "your professions' recipes you have not learned yet" },
}

local PAGES = {
    { "General", "Interface\\Icons\\INV_Misc_Gear_01", {
        { "caption", "Window" },
        { "check", "minimap", "Show minimap button", "Show the Grist for the Mill button around the minimap" },
        { "check", "autoOpen", "Open with professions",
            "Open Grist for the Mill next to the profession window whenever you open a profession" },
        { "check", "ctrlClick", "Open with Ctrl + Right-Click",
            "Ctrl + Right-Click a reagent in your bags to see it in the Reagents tab" },
        { "check", "stickyHeaders", "Keep list headers in view",
            "Category headers stay docked at the top and bottom of a list while you scroll" },
        { "choice", "layout", "Layout", { { "Classic", "classic" }, { "Modern", "modern" } },
            "The look of the addon. Modern is still being made: until its art is added it looks the same as Classic. Changing it reloads the interface" },
        { "check", "loadMessage", "Show login message", "Print \"Grist for the Mill loaded\" in chat when you log in" },
        { "caption", "Item tooltips" },
        { "check", "ttUsedIn", "Show recipes using the item", "Item tooltips list your recipes that use the reagent" },
        { "check", "ttProfIcons", "Show profession icons", "Show the profession icon next to each recipe in the tooltip" },
        { "check", "ttLearned", "Show learned status",
            "A tick (learned), cross (not learned) or lock (skill too low) in front of each recipe in the tooltip" },
        { "slider", "ttMax", "Recipes listed", 3, 25, 1, "How many recipes a tooltip lists (hold Shift for all)" },
    } },
    { "Reagents", "Interface\\Icons\\INV_Misc_Herb_07", {
        { "choice", "listGroup", "Group list by", { { "Profession", "prof" }, { "Type", "type" } },
            "How the My Reagents list on the Reagents tab is grouped" },
        { "check", "allProfs", "Show all professions", "Show reagents and recipes of every profession, not just yours" },
        { "check", "includeBank", "Count bank items", "Reagent counts and the reagent list include what is in your bank" },
        { "caption", "Only list reagents of" },
        { "check", "filterLearned", "Learned recipes", "Only list reagents used by recipes you have learned" },
        { "check", "filterSkillUp", "Recipes that give skill",
            "Only list reagents used by recipes that can still raise your skill level" },
        { "check", "filterCraftable", "Recipes you can craft now",
            "Only list reagents of recipes you have every material for" },
        { "caption", "Recipes shown for a reagent" },
        { "check", "df_learned", "Learned", "Show recipes you know" },
        { "check", "df_unlearned", "Not learned", "Show recipes you could learn now but have not" },
        { "check", "df_red", "Locked", "Show recipes your skill level is too low for" },
        { "check", "df_orange", "|cffff8040Orange|r", "Show recipes that always give a skill point" },
        { "check", "df_yellow", "|cffffff00Yellow|r", "Show recipes that usually give a skill point" },
        { "check", "df_green", "|cff40bf40Green|r", "Show recipes that rarely give a skill point" },
        { "check", "df_gray", "|cff999999Gray|r", "Show recipes that no longer give skill" },
        { "check", "df_mats", "Only with materials", "Only show recipes you have every material for" },
    } },
    { "Bags", "Interface\\Icons\\INV_Misc_Bag_08", {
        { "caption", "Slot borders" },
        { "check", "bagBorders", "Show reagent borders",
            "Colour reagent slots in your bags by skill-up colour, or blue if the recipe is not learned yet" },
        { "slider", "bagBorderSize", "Border thickness", 1, 6, 1, "Thickness of the coloured frame around a reagent slot" },
        { "check", "bagGlow", "Show border glow", "Add a soft glow in the same colour around the frame" },
        { "colors", "bagColor_", "Highlight reagents of " },
        { "caption", "Bag Reagents window" },
        { "check", "bagButton", "Show Bag Reagents button",
            "Show a button on the backpack button that lists your bag reagents, to sell, trade or delete several at once" },
        { "choice", "bagGroup", "Group window by", { { "Skill Up", "skill" }, { "Profession", "prof" }, { "Type", "type" } },
            "How the Bag Reagents window is grouped" },
        { "check", "bagMine", "Show my professions only", "Hide reagents that none of your professions use" },
        { "check", "bagHideGray", "Hide gray reagents", "Hide reagents whose recipes no longer give skill" },
        { "check", "bagConfirm", "Ask before selling", "Ask before the Sell button sells the ticked reagents" },
    } },
    { "Protection", "LOCK", {
        { "check", "protectReagents", "Protect reagents",
            "Ask before a protected reagent is sold to a vendor: its slot is guarded while a vendor is open" },
        { "caption", "Reagents protected" },
        { "colors", "protect_", "Protect reagents of " },
        { "check", "protect_farm", "Protect Farming list", "Also protect every item on your Farming list" },
        { "caption", "When a reagent is protected" },
        { "check", "bagLock", "Show lock in bags",
            "A small gold lock in the corner of every protected reagent in your bags" },
        { "check", "ttProtected", "Show lock in tooltips",
            "Show a lock in the top-right corner of the tooltip of protected reagents" },
        { "check", "protectBuyback", "Buy back unguarded sales",
            "If a protected reagent is sold from a slot that could not be guarded, buy it back and ask" },
    } },
    { "Farming & Crafting", "Interface\\Icons\\INV_Hammer_20", {
        { "caption", "Farming tracker" },
        { "check", "farmAutoTracker", "Open tracker automatically",
            "Show the Farming tracker window when something is added to the Farming list" },
        { "check", "farmPopup", "Show goal popup", "Show a popup when a farming goal is reached" },
        { "check", "farmSound", "Play goal sound", "Play a sound with the goal popup" },
        { "caption", "Crafting tracker" },
        { "check", "craftAutoOpen", "Open window automatically", "Show the Crafting window when you track a recipe" },
        { "check", "craftSilent", "Craft without profession window",
            "The Crafting window's Craft button crafts without showing the profession window" },
        { "check", "craftReqs", "Show requirements", "List what a tracked recipe needs nearby: anvil, cooking fire, tools" },
        { "caption", "Both windows" },
        { "check", "trackerDocking", "Dock windows together",
            "Drag the Farming or Crafting window next to the other and they snap together and move as one. Click the chain to separate them" },
        { "caption", "Finding NPCs" },
        { "check", "findTarget", "Target and mark nearby NPCs",
            "Clicking the arrow of a vendor, mob or trainer that is close by also targets it and puts a star on it. Not available in combat" },
        { "caption", "Vendors" },
        { "check", "vendorPrompt", "Offer to buy at vendors",
            "When a vendor sells something your Farming list or a tracked recipe still needs, offer to buy it" },
    } },
}

---------------------------------------------------------------------------
-- Panel: menu on the left, the chosen page on the right
---------------------------------------------------------------------------
function ns.CreateSettingsPanel(f, inset)
    local p = CreateFrame("Frame", nil, f)
    p:SetAllPoints(f)
    local widgets = {}
    local function W(w)
        widgets[#widgets + 1] = w
        return w
    end

    local menu = ns.Card(p, nil, 12)
    menu:SetPoint("TOPLEFT", inset, "TOPLEFT")
    menu:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 0, 40)
    menu:SetWidth(200)

    local pages, buttons = {}, {}
    local current = 1
    local function Select(i)
        current = i
        for j, page in ipairs(pages) do
            page:SetShown(j == i)
            buttons[j].sel:SetShown(j == i)
            buttons[j].text:SetFontObject(j == i and "GameFontHighlight" or "GameFontNormal")
        end
    end

    for i, def in ipairs(PAGES) do
        -- menu entry
        local b = CreateFrame("Button", nil, menu)
        b:SetHeight(28)
        b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 29)
        b:SetPoint("RIGHT", menu, "RIGHT", -6, 0)
        b.sel = b:CreateTexture(nil, "BACKGROUND")
        b.sel:SetAllPoints()
        if not ns.RowArt(b.sel, "selected") then
            b.sel:SetColorTexture(1, 0.82, 0.2, 0.18)
        end
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        if not ns.RowArt(hl, "hover") then
            hl:SetColorTexture(1, 1, 1, 0.08)
        end
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", 6, 0)
        if def[2] == "LOCK" then -- the same gold lock that marks protected reagents
            icon:SetTexture(ns.Tex("Lock"))
            icon:SetVertexColor(1, 0.82, 0)
        else
            icon:SetTexture(def[2])
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        b.text:SetText(def[1])
        b:SetScript("OnClick", function()
            Select(i)
        end)
        buttons[i] = b

        -- page
        local page = Card(p, def[1])
        page:SetPoint("TOPLEFT", menu, "TOPRIGHT", 12, 0)
        page:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT")
        local indent = 0 -- rows under a caption are indented, so they read as belonging to it
        local function Add(w)
            W(w)
            w:SetPoint("TOPLEFT", page, "TOPLEFT", 20 + indent, page.y)
            w:SetPoint("RIGHT", page, "RIGHT", -20, 0)
            page.y = page.y - w:GetHeight() - 4
        end
        for _, e in ipairs(def[3]) do
            local kind = e[1]
            if kind == "check" then
                Add(Checkbox(page, e[2], e[3], e[4]))
            elseif kind == "slider" then
                Add(Slider(page, e[2], e[3], e[4], e[5], e[6], function(v)
                    return tostring(math.floor(v + 0.5))
                end))
            elseif kind == "choice" then
                Add(Choice(page, e[2], e[3], e[4], e[5]))
            elseif kind == "caption" then
                page.y = page.y - 6
                indent = 0
                Add(Caption(page, e[2]))
                indent = 16
            elseif kind == "colors" then
                local options = {}
                for _, c in ipairs(SKILL_COLORS) do
                    options[#options + 1] = { e[2] .. c[1], c[2], c[3], e[3] .. c[4] }
                end
                Add(CheckRow(page, options))
            end
        end
        pages[i] = page
    end

    local reset = ns.CreateButton(p, "Reset to Defaults", 140)
    reset:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 4, 8)
    reset:SetScript("OnClick", function()
        HelperDB.settings = {}
        for key, v in pairs(DEFAULTS) do
            for _, fn in ipairs(listeners[key] or {}) do
                pcall(fn, v)
            end
        end
        for _, w in ipairs(widgets) do
            w.Update()
        end
        if ns.RefreshReagents then
            ns.RefreshReagents()
        end
    end)

    p:SetScript("OnShow", function()
        for _, w in ipairs(widgets) do
            w.Update()
        end
        Select(current)
    end)
    Select(1)
    return p
end
