-- Farming tab: items with a target count, progress, vendor / auction value, and a popup when a goal is reached.
-- HelperDB.farm = { { id = itemID, target = n, done = bool }, ... }
-- Auction prices: Auctionator, Auctioneer (AucAdvanced) or TradeSkillMaster, whichever is loaded.
local _, ns = ...

local db, panel, listText, summary, toast
local C_GOLD, C_DIM, C_SOFT, C_HEAD = "|cfff2bf4d", "|cff7d8592", "|cffb4bac4", "|cffe8eaf0"

local function Safe(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, v = pcall(fn, ...)
    if ok then
        return v
    end
end

local function List()
    db.farm = db.farm or {}
    return db.farm
end

local function Find(id)
    for i, e in ipairs(List()) do
        if e.id == id then
            return e, i
        end
    end
end

---------------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------------
local function VendorPrice(id)
    local f = C_Item and C_Item.GetItemInfo or GetItemInfo
    if f then
        local ok, _, _, _, _, _, _, _, _, _, _, sell = pcall(f, id)
        if ok and type(sell) == "number" then
            return sell
        end
    end
    return 0
end

local function AuctionPrice(id)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if api and api.GetAuctionPriceByItemID then
        local v = Safe(api.GetAuctionPriceByItemID, "GristForTheMill", id)
        if type(v) == "number" then
            return v, "Auctionator"
        end
    end
    local auc = AucAdvanced and AucAdvanced.API
    if auc and auc.GetMarketValue then
        local link = select(2, pcall(C_Item and C_Item.GetItemInfo or GetItemInfo, id))
        local v = type(link) == "string" and Safe(auc.GetMarketValue, link)
        if type(v) == "number" then
            return v, "Auctioneer"
        end
    end
    if TSM_API and TSM_API.GetCustomPriceValue then
        local v = Safe(TSM_API.GetCustomPriceValue, "dbmarket", "i:" .. id)
        if type(v) == "number" then
            return v, "TSM"
        end
    end
    return nil
end

-- name of the auction addon the prices come from, or nil when none is installed
local function AuctionSource()
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if api and api.GetAuctionPriceByItemID then
        return "Auctionator"
    elseif AucAdvanced and AucAdvanced.API and AucAdvanced.API.GetMarketValue then
        return "Auctioneer"
    elseif TSM_API and TSM_API.GetCustomPriceValue then
        return "TradeSkillMaster"
    end
end

local function Money(c)
    return ns.Money(c)
end

---------------------------------------------------------------------------
-- Goal popup (toast)
---------------------------------------------------------------------------
local function Toast(e)
    if not ns.Get("farmPopup") then
        return
    end
    local T = ns.T
    if not toast then
        toast = CreateFrame("Button", "HelperFarmToast", UIParent, "BackdropTemplate")
        toast:SetSize(380, 78)
        toast:SetPoint("TOP", UIParent, "TOP", 0, -140)
        toast:SetFrameStrata("DIALOG")
        ns.Skin(toast, T.bg, T.accent, 12)
        ns.SkinGradient(toast, T.bgTop, T.bg)
        ns.Shadow(toast, 18)
        toast.icon = toast:CreateTexture(nil, "ARTWORK")
        toast.icon:SetSize(44, 44)
        toast.icon:SetPoint("LEFT", 16, 0)
        toast.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        toast.title = toast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        toast.title:SetPoint("TOPLEFT", toast.icon, "TOPRIGHT", 12, 0)
        toast.title:SetTextColor(unpack(T.accent))
        toast.title:SetText("Farming Goal Reached!")
        toast.line = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        toast.line:SetPoint("TOPLEFT", toast.title, "BOTTOMLEFT", 0, -4)
        toast.value = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        toast.value:SetPoint("TOPLEFT", toast.line, "BOTTOMLEFT", 0, -4)
        local fade = toast:CreateAnimationGroup()
        local a = fade:CreateAnimation("Alpha")
        a:SetFromAlpha(1)
        a:SetToAlpha(0)
        a:SetDuration(1)
        a:SetStartDelay(7)
        fade:SetScript("OnFinished", function()
            toast:Hide()
        end)
        toast.fade = fade
        toast:SetScript("OnClick", function()
            toast:Hide()
            if ns.Open then
                ns.Open(2)
            end
        end)
        toast:SetScript("OnEnter", function()
            toast.fade:Stop()
            toast:SetAlpha(1)
        end)
        toast:SetScript("OnLeave", function()
            toast.fade:Play()
        end)
    end
    local _, icon = pcall(C_Item and C_Item.GetItemIconByID or GetItemIcon or error, e.id)
    toast.icon:SetTexture(type(icon) ~= "string" and icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    toast.line:SetText(("%s%dx|r %s%s|r"):format(C_HEAD, e.target, ns.QualityColor(e.id), ns.ItemName(e.id)))
    local ah, src = AuctionPrice(e.id)
    toast.value:SetText(("%sVendor|r %s%s"):format(C_DIM, Money(VendorPrice(e.id) * e.target),
        ah and ("    " .. C_DIM .. src .. "|r " .. Money(ah * e.target)) or ""))
    toast:SetAlpha(1)
    toast:Show()
    toast.fade:Stop()
    toast.fade:Play()
    if ns.Get("farmSound") then
        pcall(PlaySound, SOUNDKIT and SOUNDKIT.READY_CHECK or 8960)
    end
end

local function CheckGoals()
    if not db then
        return
    end
    for _, e in ipairs(List()) do
        local have = ns.Have(e.id)
        if have >= e.target and not e.done then
            e.done = true
            Toast(e)
        elseif have < e.target then
            e.done = false
        end
    end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
local function StackSize(id)
    local f = C_Item and C_Item.GetItemInfo or GetItemInfo
    local ok, _, _, _, _, _, _, _, stack = pcall(f or error, id)
    return ok and type(stack) == "number" and stack > 1 and stack or 20
end

local Render

-- add an item (or raise its target by amount); amount nil = one stack more than you have
function ns.FarmAdd(id, amount)
    local e = Find(id)
    if e then
        e.target = e.target + (amount or StackSize(id))
    else
        e = { id = id, target = amount or (ns.Have(id) + StackSize(id)) }
        table.insert(List(), e)
    end
    e.done = ns.Have(id) >= e.target
    ns.Print(("Farming: %s - target %d"):format(ns.ItemName(id), e.target))
    if Render then
        Render()
    end
    if ns.Get("farmAutoTracker") then
        ns.ShowFarmTracker()
    end
end

-- change an item's target by delta (adds the item when needed, removes it at 0)
function ns.FarmAdjust(id, delta)
    local e, i = Find(id)
    if not e then
        if delta <= 0 then
            return
        end
        e = { id = id, target = 0 }
        table.insert(List(), e)
        i = #List()
    end
    e.target = e.target + delta
    if e.target <= 0 then
        table.remove(List(), i)
    else
        e.done = ns.Have(id) >= e.target
    end
    if Render then
        Render()
    end
    if delta > 0 and ns.Get("farmAutoTracker") then
        ns.ShowFarmTracker()
    end
end

-- farming target of an item (0 = not on the list) and a setter (0 removes it)
function ns.FarmTarget(id)
    local e = Find(id)
    return e and e.target or 0
end

function ns.FarmSet(id, n)
    n = math.max(math.floor(n or 0), 0)
    local delta = n - ns.FarmTarget(id)
    if delta ~= 0 then
        ns.FarmAdjust(id, delta)
    end
end

function ns.FarmHas(id)
    return Find(id) ~= nil
end

---------------------------------------------------------------------------
-- Tracker: small movable window (like the quest tracker) with a progress bar per farmed item.
-- Opens when something is added to the farming list; remembers position and visibility.
---------------------------------------------------------------------------
local tracker
local TRACK_W, ROW_H, HEAD_H, FOOT_H = 290, 28, 26, 22
local WHITE = "Interface\\Buttons\\WHITE8X8"
local BRONZE = { 0.32, 0.26, 0.17 }
local STATE_RGB = { done = { 0.25, 1, 0.25 }, some = { 1, 0.82, 0 }, none = { 0.5, 0.5, 0.5 } }

local function ItemIconPath(id)
    local _, icon = pcall(C_Item and C_Item.GetItemIconByID or GetItemIcon or error, id)
    return type(icon) ~= "string" and icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function QualityRGB(id)
    local q = C_Item and C_Item.GetItemQualityByID and Safe(C_Item.GetItemQualityByID, id)
    local c = q and q > 1 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then
        return c.r, c.g, c.b, 0.8
    end
    return BRONZE[1], BRONZE[2], BRONZE[3], 1
end

-- incomplete goals first (list order), finished ones last
local function Sorted()
    local open, done = {}, {}
    for _, e in ipairs(List()) do
        local t = ns.Have(e.id) >= e.target and done or open
        t[#t + 1] = e
    end
    local nDone = #done
    for _, e in ipairs(done) do
        open[#open + 1] = e
    end
    return open, nDone
end

-- what the last removal took away, so it can be undone (this session only):
-- Each is a stack of removals, newest last (so several removals can be undone one after the other):
--   farmUndo[n] = { { e = entry, i = position }, ..., crafts = farmCrafts copy, recipe = { spell, n } }
--   craftUndo[n] = { { spell, i }, ... }
local farmUndo, craftUndo = {}, {}
local farmRedo, craftRedo = {}, {} -- what Undo brought back, newest last: Redo removes it again
local UNDO_MAX = 30

local function PushUndo(stack, action)
    wipe(stack == farmUndo and farmRedo or craftRedo) -- a new removal: nothing left to redo
    stack[#stack + 1] = action
    if #stack > UNDO_MAX then
        table.remove(stack, 1)
    end
end

-- right-click on an undo button: every removal that can be undone, newest first. Picking one undoes it
-- and everything removed after it. label(step) names a step, undo() takes back the newest one.
function ns.UndoMenu(owner, stack, label, undo)
    if #stack == 0 or not (MenuUtil and MenuUtil.CreateContextMenu) then
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Undo back to")
        for k = #stack, 1, -1 do
            local steps = #stack - k + 1
            root:CreateButton(label(stack[k]), function()
                for _ = 1, steps do
                    undo()
                end
            end)
        end
    end)
end

local function Remove(id)
    local e, i = Find(id)
    if i then
        PushUndo(farmUndo, { { e = e, i = i } })
        table.remove(List(), i)
    end
    Render()
end

-- take every finished goal off the farming list (one undo step brings them all back)
function ns.FarmClearDone()
    local list = List()
    local undo = {}
    for i, e in ipairs(list) do
        if ns.Have(e.id) >= e.target then
            undo[#undo + 1] = { e = e, i = i }
        end
    end
    if #undo == 0 then
        return
    end
    for k = #undo, 1, -1 do
        table.remove(list, undo[k].i)
    end
    PushUndo(farmUndo, undo)
    Render()
end

-- put back what the last removal (one item or Remove All) took from the farming list
function ns.FarmUndo()
    local u = table.remove(farmUndo) -- the most recent removal
    if not u then
        return
    end
    if u.recipe and ns.FarmRecipe then -- a recipe taken off in the Recipes view: farm for it again
        ns.FarmRecipe(u.recipe.spell, u.recipe.n)
    end
    local list = List()
    for _, x in ipairs(u) do
        if not Find(x.e.id) then
            table.insert(list, math.min(x.i, #list + 1), x.e)
        end
    end
    if u.crafts then
        db.farmCrafts = db.farmCrafts or {}
        for k, v in pairs(u.crafts) do
            if db.farmCrafts[k] == nil then
                db.farmCrafts[k] = v
            end
        end
    end
    farmRedo[#farmRedo + 1] = u
    Render()
    if ns.RefreshReagents then
        ns.RefreshReagents()
    end
end

-- take off again what the last Undo put back
function ns.FarmRedo()
    local u = table.remove(farmRedo)
    if not u then
        return
    end
    if u.recipe and ns.FarmRecipe then
        ns.FarmRecipe(u.recipe.spell, -u.recipe.n)
    end
    for _, x in ipairs(u) do
        local _, i = Find(x.e.id)
        if i then
            table.remove(List(), i)
        end
    end
    if u.crafts and db.farmCrafts then
        for k in pairs(u.crafts) do
            db.farmCrafts[k] = nil
        end
    end
    farmUndo[#farmUndo + 1] = u -- (not PushUndo: the rest of the redo list stays)
    Render()
    if ns.RefreshReagents then
        ns.RefreshReagents()
    end
end

-- small flat button: texture or a text glyph, dim until hovered
local function MiniButton(parent, size, texture, glyph, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    if texture then
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints()
        t:SetTexture(texture)
    else
        b.glyph = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b.glyph:SetPoint("CENTER", 0, 0)
        b.glyph:SetText(glyph)
    end
    b:SetAlpha(0.45)
    b:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        if tip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(type(tip) == "function" and tip() or tip)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self:SetAlpha(0.45)
        GameTooltip:Hide()
        local p = self:GetParent()
        if p.Hover then
            p:Hover()
        end
    end)
    return b
end

local SUB_H = 20 -- material rows under a craftable item
local PAD_IN = 7 -- space between a tracker window's frame and its rows, so nothing touches the border

-- small Blizzard window (metal frame, title bar, close button) for the Farming / Crafting trackers;
-- falls back to a tooltip-style backdrop if the client has no such template
local function PanelFrame(name, titleText, onClose)
    local own = ns.LayoutWidget("TrackerWindow") -- a layout may bring its own window frame
    if own then
        return own(name, titleText, onClose)
    end
    local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "DefaultPanelTemplate")
    local styled = ok and f ~= nil
    if styled then
        if f.SetTitle then
            f:SetTitle(titleText)
        end
        if f.Bg then -- semi-transparent dark background, like the main window
            f.Bg:SetColorTexture(0.05, 0.04, 0.03, 0.88)
        end
    else
        f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        f:SetBackdropColor(0.05, 0.04, 0.03, 0.85)
        f:SetBackdropBorderColor(0.8, 0.65, 0.4, 1)
        local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("TOP", 0, -8)
        t:SetText(titleText)
    end
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    -- kept inside the frame's border (Blizzard's default placement sits on top of the corner)
    -- 16px, centred on the title bar like the icon on the left; the other header buttons hang off it
    close:SetSize(16, 16)
    close:SetPoint("TOPRIGHT", styled and -10 or -8, styled and -4 or -6)
    close:SetScript("OnClick", onClose)
    f.styled = styled
    -- the panel template draws its frame and title bar on a child above this frame: anything put in the
    -- title bar goes on this layer, which sits above that
    f.head = CreateFrame("Frame", nil, f)
    f.head:SetAllPoints()
    -- Blizzard's panel art sits at a very high frame level (500+), so go above whatever it uses
    local top = f:GetFrameLevel() + 20
    for _, key in ipairs({ "NineSlice", "TitleContainer", "CloseButton" }) do
        local part = f[key]
        if part and part.GetFrameLevel then
            top = math.max(top, part:GetFrameLevel() + 10)
        end
    end
    f.head:SetFrameLevel(top)
    close:SetFrameLevel(top + 1)
    -- addon icon in the top-left corner (round, like the main window's portrait)
    local icon = f.head:CreateTexture(nil, "OVERLAY")
    icon:SetSize(16, 16)
    icon:SetPoint("TOPLEFT", styled and 14 or 12, styled and -4 or -6) -- inside the border, not on it
    icon:SetTexture([[Interface\Icons\INV_Misc_Bag_10]])
    icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    if f.head.CreateMaskTexture then
        local mask = f.head:CreateMaskTexture()
        mask:SetTexture([[Interface\CharacterFrame\TempPortraitAlphaMask]], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
    end
    return f, close
end

-- Scrolling list + resize grip for a tracker window (Farming / Crafting).
-- The rows live on f.content inside f.scroll, between `top` pixels of header and `bottom` pixels of footer.
-- store = the saved table that keeps the size the player dragged the window to (.w, .h); without one the
-- window is as tall as its list, up to 60% of the screen, and scrolls beyond that.
-- Icons and fonts never change size: rows just get wider or narrower with the window.
function ns.TrackerScroll(f, key, store, top, bottom, defaultW, minW, update)
    local BAR_W = 18 -- room the scroll bar takes on the right when the list doesn't fit
    f:SetScale(1)
    store.scale = nil
    f:SetWidth(store.w or defaultW)
    local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, f, "ScrollFrameTemplate")
    if not ok or not scroll or not scroll.ScrollBar then
        scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    end
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(defaultW, 1)
    scroll:SetScrollChild(content)
    local bar = scroll.ScrollBar
    if bar then
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 2, -2)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 2, 2)
    end
    f.scroll, f.content = scroll, content

    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(minW, 120, 800, 1000)
    end
    local grip = CreateFrame("Button", nil, f.head)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -5, 5) -- inside the border
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then -- back to the automatic size
            self.reset = true
            return
        end
        f.sizing = true
        f:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function(self)
        f:StopMovingOrSizing()
        f.sizing = nil
        if self.reset then
            self.reset = nil
            store.w, store.h = nil, nil
            f:SetWidth(defaultW)
        else
            store.w, store.h = f:GetWidth(), f:GetHeight()
        end
        ns.TrackerDragStop(key) -- saves the position and keeps a docked pair together
        update()
    end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Resize")
        GameTooltip:AddLine("Drag to change the size of the window. Right-click for the automatic size", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", GameTooltip_Hide)
    f.grip = grip
    f:HookScript("OnSizeChanged", function()
        if f.sizing then
            update() -- rows follow the window while it is being dragged
        end
    end)

    -- width the rows get right now
    function f.RowWidth()
        return f.rowW or (f:GetWidth() - 2 * PAD_IN)
    end
    -- after the rows are placed: size the window / the scrolling area for a list `contentH` tall.
    -- Returns true when the row width changed (scroll bar came or went): the caller lays the rows out again.
    function f.Layout(contentH, collapsed)
        scroll:SetShown(not collapsed)
        grip:SetShown(not collapsed)
        if collapsed then
            f:SetHeight(HEAD_H + 6)
            return false
        end
        if not f.sizing then
            local auto = math.min(top + contentH + bottom, math.max(UIParent:GetHeight() * 0.6, 200))
            f:SetHeight(store.h or auto)
        end
        local needBar = contentH > f:GetHeight() - top - bottom + 1
        if f.hasBar ~= needBar then
            f.hasBar = needBar
            scroll:ClearAllPoints()
            scroll:SetPoint("TOPLEFT", 0, -top)
            scroll:SetPoint("BOTTOMRIGHT", needBar and -(BAR_W + PAD_IN) or 0, bottom)
        end
        if bar then
            bar:SetShown(needBar)
        end
        local rowW = f:GetWidth() - 2 * PAD_IN - (needBar and BAR_W or 0)
        content:SetSize(rowW + 2 * PAD_IN, math.max(contentH, 1))
        local changed = math.abs(rowW - (f.rowW or -1)) > 0.5
        f.rowW = rowW
        return changed
    end
end

local function AskConfirm(text, fn)
    StaticPopupDialogs["REAGENTFARMING_CONFIRM"] = StaticPopupDialogs["REAGENTFARMING_CONFIRM"] or {
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
        preferredIndex = 3,
    }
    StaticPopup_Show("REAGENTFARMING_CONFIRM", text, nil, fn)
end

-- empty the whole farming list (asks first)
function ns.FarmRemoveAll()
    local n = #List()
    if n == 0 then
        return
    end
    AskConfirm(("Remove all %d items from the Farming list?"):format(n), function()
        local list = List()
        local undo = { crafts = {} }
        for i, e in ipairs(list) do
            undo[i] = { e = e, i = i }
        end
        PushUndo(farmUndo, undo)
        for i = #list, 1, -1 do
            table.remove(list, i)
        end
        if db.farmCrafts then
            for k, v in pairs(db.farmCrafts) do
                undo.crafts[k] = v
                db.farmCrafts[k] = nil
            end
        end
        Render()
        if ns.RefreshReagents then
            ns.RefreshReagents()
        end
    end)
end

-- right-click menu of a tracker row: remove this one / remove all
local function RowMenu(owner, label, removeOne, removeAll)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        removeOne()
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateButton("Remove " .. label, removeOne)
        root:CreateButton("Remove All", removeAll)
    end)
end

-- recipe that makes an item (a learned one if possible), or nil
local function CraftRecipe(id)
    local list = ns.Index and ns.Index().craftedBy[id]
    if not list then
        return nil
    end
    for _, r in ipairs(list) do
        if ns.IsKnown(r.spellID) and #r.reagents > 0 then
            return r
        end
    end
    for _, r in ipairs(list) do
        if ns.Shown(r.profession) and #r.reagents > 0 then
            return r
        end
    end
end

local function TrackerRow(i)
    local r = tracker.rows[i]
    if r then
        return r
    end
    r = CreateFrame("Button", nil, tracker.content)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 0.82, 0, 0.06)
    r.hl:Hide()
    -- main item rows carry the same bronze band as the recipe headers; material sub-rows stay plain
    r.band = r:CreateTexture(nil, "BACKGROUND", nil, -1)
    r.band:SetPoint("TOPLEFT", 8, -1)
    r.band:SetPoint("BOTTOMRIGHT", -8, 1)
    r.band:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], 0.45)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.border = r:CreateTexture(nil, "OVERLAY")
    r.border:SetAllPoints(r.icon)
    r.border:SetTexture("Interface\\Common\\WhiteIconFrame")
    r.tick = r:CreateTexture(nil, "OVERLAY", nil, 2)
    r.tick:SetSize(12, 12)
    r.tick:SetPoint("CENTER", r.icon)
    r.tick:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    -- name line, right to left: remove (own gutter, item rows only), map, pin, count
    r.map = MiniButton(r, 14, ns.Tex("Pin"), nil, "Show on Map")
    r.map:SetAlpha(0.8)
    r.map:SetScript("OnClick", function()
        if ns.ShowItemMap then
            ns.ShowItemMap(r.id)
        end
    end)
    r.pin = MiniButton(r, 14, ns.Tex("Arrow"), nil, "Set Location")
    r.pin:SetAlpha(0.8)
    r.pin:SetPoint("RIGHT", r.map, "LEFT", -3, 0)
    r.pin:SetScript("OnClick", function()
        ns.WaypointNearest(r.id)
    end)
    r.pin:HookScript("OnEnter", function(self) -- nearest source is an NPC close by: also target and star it
        local id = r.id
        local s = ns.NearestSpot and ns.NearestSpot(id)
        if s and ns.ArmTarget then
            ns.ArmTarget(self, s.map, s.x, s.y, s.name, s.kind == "Gather" or s.kind == "Fish", function()
                ns.WaypointNearest(id)
            end)
        end
    end)
    r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.count:SetPoint("RIGHT", r.pin, "LEFT", -6, 0)
    r.del = MiniButton(r, 12, "Interface\\Buttons\\UI-StopButton", nil, "Remove from farming")
    r.del:SetPoint("RIGHT", -9, 2)
    r.del:SetScript("OnClick", function()
        Remove(r.id)
    end)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.track = r:CreateTexture(nil, "BORDER")
    r.track:SetPoint("BOTTOMLEFT", 36, 2)
    r.track:SetPoint("BOTTOMRIGHT", -10, 2)
    r.track:SetHeight(7)
    r.track:SetColorTexture(0, 0, 0, 0) -- no dark track: only the filled part shows
    r.fill = r:CreateTexture(nil, "ARTWORK")
    r.fill:SetPoint("BOTTOMLEFT", 37, 3)
    r.fill:SetHeight(5)
    r.fill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    function r.Hover(self)
        local over = self:IsMouseOver()
        self.hl:SetShown(over)
    end
    r:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if not self.sub then
                local id = self.id
                RowMenu(self, ns.ItemName(id), function()
                    Remove(id)
                end, ns.FarmRemoveAll)
            end
        else
            if ns.ShowReagent then
                ns.ShowReagent(self.id)
            end
            if not IsShiftKeyDown() then
                ns.WaypointNearest(self.id)
            end
        end
    end)
    r:SetScript("OnEnter", function(self)
        self:Hover()
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetItemByID(self.id)
        local near = ns.NearestText and ns.NearestText(self.id)
        GameTooltip:AddLine(" ")
        if near then
            GameTooltip:AddLine("Nearest: " .. near, 1, 0.82, 0)
        end
        GameTooltip:AddLine("Click: open in Grist for the Mill and point TomTom to the nearest source", 0.5, 0.5, 0.5)
        GameTooltip:AddLine("Shift-click: open only", 0.5, 0.5, 0.5)
        GameTooltip:AddLine("Right-click: remove / remove all", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self)
        self:Hover()
        GameTooltip:Hide()
    end)
    tracker.rows[i] = r
    return r
end

-- lay a row out as a main item (icon 26, bar) or a material sub-row (icon 16, indented, no bar)
local function ShapeRow(r, sub)
    r.sub = sub
    r:SetHeight(sub and SUB_H or ROW_H)
    r.icon:ClearAllPoints()
    r.name:ClearAllPoints()
    r.map:ClearAllPoints()
    -- same fonts and sizes as the Crafting window's rows
    r.name:SetFontObject(sub and "GameFontHighlightSmall" or "GameFontNormal")
    r.del:SetShown(not sub)
    if sub then
        r.icon:SetSize(14, 14)
        r.icon:SetPoint("LEFT", 36, 0)
        r.name:SetPoint("LEFT", 55, 0)
        r.map:SetPoint("RIGHT", -25, 0)
    else
        r.icon:SetSize(20, 20)
        r.icon:SetPoint("LEFT", 10, 0)
        -- name, count and buttons centred on the row; the progress bar is a thin strip under them
        r.name:SetPoint("LEFT", 36, 2)
        r.map:SetPoint("RIGHT", -25, 2)
    end
    r.name:SetPoint("RIGHT", r.count, "LEFT", -6, 0)
    r.track:SetShown(not sub)
    r.band:SetShown(not sub)
    r:Hover()
end

-- Recipes view of the Farming tracker: one header per recipe you are farming for (icon, name, crafts,
-- remove), its reagents listed under it
local farmRecipes = {}
local function FarmRecipeOf(spell)
    if farmRecipes[spell] == nil then
        farmRecipes[spell] = ns.FindRecipe and ns.FindRecipe(spell) or false
    end
    return farmRecipes[spell] or nil
end

local function RemoveFarmRecipe(spell)
    local n = db.farmCrafts and db.farmCrafts[spell] or 0
    if n > 0 and ns.FarmRecipe then
        ns.FarmRecipe(spell, -n)
        PushUndo(farmUndo, { recipe = { spell = spell, n = n } })
        Render()
    end
end

local function HeadRow(i)
    local r = tracker.heads[i]
    if r then
        return r
    end
    r = CreateFrame("Button", nil, tracker.content)
    r:SetHeight(ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 8, -1)
    bg:SetPoint("BOTTOMRIGHT", -8, 1)
    bg:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], 0.45)
    -- lit while what this recipe makes is the item open in the Grist for the Mill window
    r.sel = r:CreateTexture(nil, "BORDER")
    r.sel:SetAllPoints(bg)
    r.sel:SetColorTexture(1, 0.82, 0, 0.28)
    r.sel:Hide()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(20, 20)
    r.icon:SetPoint("LEFT", 10, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.del = MiniButton(r, 12, "Interface\\Buttons\\UI-StopButton", nil, "Stop farming for this recipe")
    r.del:SetPoint("RIGHT", -9, 0)
    r.del:SetScript("OnClick", function()
        RemoveFarmRecipe(r.spell)
    end)
    -- track / stop tracking this recipe in the Crafting window: in colour while it is tracked
    r.trackBtn = MiniButton(r, 14, "Interface\\Icons\\Trade_BlackSmithing", nil, function()
        return ns.CraftTracked(r.spell) and "Tracked in the Crafting window. Click to stop tracking"
            or "Track in the Crafting window"
    end)
    r.trackBtn.tex = r.trackBtn:GetRegions()
    r.trackBtn.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.trackBtn:SetPoint("RIGHT", r.del, "LEFT", -6, 0)
    r.trackBtn:SetScript("OnClick", function()
        ns.CraftTrack(r.spell, not ns.CraftTracked(r.spell))
        Render()
    end)
    function r.Hover(self) -- (MiniButton calls this when the pointer leaves it) back to the tracked look
        local on = ns.CraftTracked(self.spell) and true or false
        self.trackBtn.tex:SetDesaturated(not on)
        self.trackBtn:SetAlpha(on and 1 or 0.45)
    end
    r.count = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.count:SetPoint("RIGHT", r.trackBtn, "LEFT", -6, 0)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.name:SetPoint("RIGHT", r.count, "LEFT", -6, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            local spell = self.spell
            RowMenu(self, self.label or "Recipe", function()
                RemoveFarmRecipe(spell)
            end, ns.FarmRemoveAll)
        elseif self.item and ns.ShowReagent then
            ns.ShowReagent(self.item)
        end
    end)
    r:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(self.label or "Recipe")
        GameTooltip:AddLine(("Farming reagents for %d craft(s)"):format(self.crafts or 0), 1, 1, 1)
        GameTooltip:AddLine("Click: open in Grist for the Mill", 0.5, 0.5, 0.5)
        GameTooltip:AddLine("Right-Click: remove / remove all", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    tracker.heads[i] = r
    return r
end

local function UpdateTracker()
    if not tracker or not tracker:IsShown() then
        return
    end
    local items, nDone = Sorted()
    if #items == 0 and #farmUndo == 0 and #farmRedo == 0 then
        tracker:Hide() -- nothing to track; comes back when something is added
        return
    end
    tracker.undo:SetShown(#farmUndo > 0) -- only after a removal that can still be undone
    tracker.undo.steps = #farmUndo
    tracker.PlaceUndo(#farmRedo)
    local min = db.farmTracker and db.farmTracker.min
    local totalV, totalA = 0, 0
    local n, y = 0, 0 -- y: down the scrolling list
    tracker.selY = nil
    local rowW = tracker.RowWidth()
    local function Place(id, have, need, sub)
        n = n + 1
        local r = TrackerRow(n)
        local done = have >= need
        r.id = id
        ShapeRow(r, sub)
        r.icon:SetTexture(ItemIconPath(id))
        r.icon:SetDesaturated(done)
        r.icon:SetAlpha(done and 0.55 or 1)
        r.border:SetVertexColor(QualityRGB(id))
        r.tick:SetShown(done and not sub)
        r.name:SetText(ns.QualityColor(id) .. ns.ItemName(id) .. "|r")
        r.name:SetAlpha(done and 0.55 or 1)
        r.count:SetText(("%d/%d"):format(have, need))
        r.count:SetTextColor(unpack(STATE_RGB[done and "done" or have > 0 and "some" or "none"]))
        local pct = need > 0 and math.min(have / need, 1) or 1
        r.fill:SetShown(not sub and pct > 0)
        r.fill:SetWidth(math.max((rowW - 48) * pct, 1))
        if done then
            r.fill:SetVertexColor(0.1, 0.75, 0.1, 1)
        else
            r.fill:SetVertexColor(0.95, 0.7, 0.1, 1)
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", PAD_IN, -y)
        r:SetWidth(rowW)
        r:SetShown(not min)
        y = y + (sub and SUB_H or ROW_H)
    end
    -- Items / Recipes
    local view = db.farmTracker and db.farmTracker.view == "recipes" and "recipes" or "items"
    tracker.viewBar:SetShown(not min)
    for _, b in ipairs({ tracker.viewItems, tracker.viewRecipes }) do
        local on = b.value == view
        b.bg:SetColorTexture(on and 0.55 or 0, on and 0.42 or 0, on and 0.18 or 0, on and 0.55 or 0.35)
        b.text:SetTextColor(on and 1 or 0.6, on and 1 or 0.6, on and 1 or 0.6)
        if on then
            b:SetBorderColor(1, 0.82, 0, 0.9)
        else
            b:SetBorderColor(0.45, 0.36, 0.2, 0.9)
        end
    end
    local pDone, pAll = nDone, #items -- progress in the title bar: always over the whole list
    local nh = 0
    tracker.otherHead:Hide()
    if view == "recipes" then
        local covered, spells = {}, {}
        for spell, c in pairs(db.farmCrafts or {}) do
            if c > 0 and FarmRecipeOf(spell) then
                spells[#spells + 1] = spell
            end
        end
        table.sort(spells, function(a, b)
            return ns.RecipeName(FarmRecipeOf(a)) < ns.RecipeName(FarmRecipeOf(b))
        end)
        for _, spell in ipairs(spells) do
            local rec, crafts = FarmRecipeOf(spell), db.farmCrafts[spell]
            nh = nh + 1
            local h = HeadRow(nh)
            h.spell, h.crafts, h.item, h.label = spell, crafts, rec.item, ns.RecipeName(rec)
            h.icon:SetTexture(rec.item and ItemIconPath(rec.item) or "Interface\\Icons\\INV_Misc_QuestionMark")
            h.name:SetText(h.label)
            h.count:SetText("|cffffffffx" .. crafts .. "|r")
            h.sel:SetShown(rec.item ~= nil and ns.SelectedItem ~= nil and ns.SelectedItem() == rec.item)
            if h.sel:IsShown() and not tracker.selY then
                tracker.selY = y -- where the highlighted recipe sits in the list
            end
            h:Hover()
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", PAD_IN, -y)
            h:SetWidth(rowW)
            h:SetShown(not min)
            y = y + ROW_H
            for _, rg in ipairs(rec.reagents) do
                Place(rg[1], ns.Have(rg[1]), rg[2] * crafts, true)
                covered[rg[1]] = true
            end
            y = y + 4
        end
        -- what is on the list without belonging to a recipe goes under "Other Items"
        local others = {}
        for _, e in ipairs(items) do
            if covered[e.id] then
                local a = AuctionPrice(e.id)
                totalV = totalV + VendorPrice(e.id) * e.target
                totalA = totalA + (a or 0) * e.target
            else
                others[#others + 1] = e
            end
        end
        if #others > 0 or #spells == 0 then
            tracker.otherHead:ClearAllPoints()
            tracker.otherHead:SetPoint("TOPLEFT", PAD_IN, -y)
            tracker.otherHead:SetWidth(rowW)
            tracker.otherHead.text:SetText(#spells == 0 and #others == 0 and "No recipes being farmed"
                or #spells == 0 and "No recipes - items only" or "Other Items")
            tracker.otherHead:SetShown(not min)
            y = y + 20
        end
        items, nDone = others, 0
    end
    for i = nh + 1, #tracker.heads do
        tracker.heads[i]:Hide()
    end
    local hideDone = db.farmTracker and db.farmTracker.hideDone
    tracker.doneHead:Hide()
    tracker.doneY = nil
    for i, e in ipairs(items) do
        local h = ns.Have(e.id)
        if nDone > 0 and i == #items - nDone + 1 then -- finished goals start here: "Completed (n)" section
            y = y + 4
            tracker.doneY = y -- its place in the list; PlaceDone keeps it in view (docked at the bottom)
            tracker.doneHead:SetWidth(rowW)
            tracker.doneHead.text:SetText(("Completed  |cff808080(%d)|r"):format(nDone))
            tracker.doneHead.sign:SetTexture("Interface\\Buttons\\UI-" .. (hideDone and "Plus" or "Minus") .. "Button-Up")
            tracker.doneHead:SetShown(not min)
            y = y + 20
        end
        if not (hideDone and h >= e.target) then
            Place(e.id, h, e.target, false)
        end
        -- craftable and not finished: the materials for what is still missing
        local recipe = h < e.target and CraftRecipe(e.id)
        if recipe then
            local crafts = math.ceil((e.target - h) / math.max(recipe.count or 1, 1))
            for _, rg in ipairs(recipe.reagents) do
                Place(rg[1], ns.Have(rg[1]), rg[2] * crafts, true)
            end
            y = y + 2
        end
        local a = AuctionPrice(e.id)
        totalV = totalV + VendorPrice(e.id) * e.target
        totalA = totalA + (a or 0) * e.target
    end
    for i = n + 1, #tracker.rows do
        tracker.rows[i]:Hide()
    end
    tracker.progress:SetText(("%d/%d"):format(pDone, pAll))
    if pDone == pAll then
        tracker.progress:SetTextColor(0.25, 1, 0.25)
    else
        tracker.progress:SetTextColor(0.5, 0.5, 0.5)
    end
    tracker.min:SetNormalTexture("Interface\\Buttons\\UI-" .. (min and "Plus" or "Minus") .. "Button-Up")
    tracker.vendor:SetText("|cff808080Vendor|r  " .. Money(totalV))
    -- auction value: only with an auction addon installed (hover says which one the prices are from)
    local source = AuctionSource()
    tracker.auction:SetText(source and ("|cff808080Auction House|r  " .. (totalA > 0 and Money(totalA) or "|cff808080-|r"))
        or "")
    for _, x in ipairs({ tracker.line1, tracker.line2, tracker.vendor }) do
        x:SetShown(not min)
    end
    tracker.auction:SetShown(not min and source ~= nil)
    tracker.auctionHit:SetShown(not min and source ~= nil)
    tracker.auctionHit.source = source
    if tracker.Layout(y + 4, min) and not tracker.again then
        tracker.again = true -- the scroll bar came or went: the rows have a new width
        UpdateTracker()
        tracker.again = nil
        return
    end
    if tracker.scrollTo then -- "Completed" was just opened from the bottom of the window: bring it into view
        -- (the scroll frame only learns its new range a frame later: work it out from the list itself)
        local to = tracker.scrollTo
        tracker.scrollTo = nil
        local function Go()
            local range = math.max((tracker.content:GetHeight() or 0) - (tracker.scroll:GetHeight() or 0), 0)
            tracker.scroll:SetVerticalScroll(math.max(math.min(to, range), 0))
            tracker.PlaceDone()
        end
        Go()
        C_Timer.After(0, Go)
    end
    tracker.PlaceDone()
    ns.ApplyTrackerDock()
end

function ns.ShowFarmTracker(show)
    db.farmTracker = db.farmTracker or {}
    if show == false then
        if tracker then
            tracker:Hide()
        end
        db.farmTracker.shown = false
        return
    end
    if #List() == 0 then
        return
    end
    if not tracker then
        local close
        tracker, close = PanelFrame("HelperFarmTracker", "Farming", function()
            ns.ShowFarmTracker(false)
        end)
        -- header + the Items / Recipes bar above the list, the value line below it
        ns.TrackerScroll(tracker, "farm", db.farmTracker, HEAD_H + 4 + 24, FOOT_H + 8, TRACK_W + 2 * PAD_IN, 230,
            function()
                UpdateTracker()
            end)
        tracker:SetFrameStrata("HIGH") -- above action bars and other HUD buttons
        tracker:SetToplevel(true)
        tracker:SetClampedToScreen(true)
        tracker:SetMovable(true)
        tracker:EnableMouse(true)
        tracker:RegisterForDrag("LeftButton")
        -- dragging: see "Docking" below (a docked pair moves as one, and a drag can dock the two)
        tracker:SetScript("OnDragStart", function()
            ns.TrackerDragStart("farm")
        end)
        tracker:SetScript("OnDragStop", function()
            ns.TrackerDragStop("farm")
        end)
        tracker:HookScript("OnHide", function()
            ns.ApplyTrackerDock()
        end)
        local pos = db.farmTracker.pos
        if pos then
            tracker:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
        else
            tracker:SetPoint("TOPRIGHT", UIParent, "RIGHT", -60, 160)
        end
        -- header: title, done / total, minimise, close
        tracker.min = MiniButton(tracker.head, 16, "Interface\\Buttons\\UI-MinusButton-Up", nil, function()
            return db.farmTracker.min and "Expand" or "Minimise"
        end)
        tracker.min:SetAlpha(1)
        tracker.min:SetPoint("RIGHT", close, "LEFT", -3, 0)
        tracker.min:SetScript("OnClick", function()
            db.farmTracker.min = not db.farmTracker.min
            UpdateTracker()
        end)
        local clear = MiniButton(tracker.head, 14, "Interface\\Buttons\\UI-GroupLoot-Pass-Up", nil, "Remove All")
        clear:SetAlpha(0.8)
        clear:SetPoint("RIGHT", tracker.min, "LEFT", -3, 0)
        clear:SetScript("OnClick", ns.FarmRemoveAll)
        tracker.undo = MiniButton(tracker.head, 14, "Interface\\Buttons\\UI-RefreshButton", nil, function()
            return ("Undo remove (%d). Right-click: choose how far back"):format(tracker.undo.steps or 0)
        end)
        tracker.undo:SetAlpha(0.9)
        tracker.undo:SetPoint("RIGHT", clear, "LEFT", -3, 0)
        tracker.undo:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        tracker.undo:SetScript("OnClick", function(self, button)
            if button ~= "RightButton" then
                ns.FarmUndo()
                return
            end
            ns.UndoMenu(self, farmUndo, function(u)
                if u.recipe then
                    local rec = ns.FindRecipe and ns.FindRecipe(u.recipe.spell)
                    return "Recipe: " .. (rec and ns.RecipeName(rec) or "?")
                elseif #u == 1 then
                    return ns.QualityColor(u[1].e.id) .. ns.ItemName(u[1].e.id) .. "|r"
                end
                return ("%d items"):format(#u)
            end, ns.FarmUndo)
        end)
        tracker.undo:Hide()
        -- Redo: the Undo arrow mirrored; only there after an Undo. Order in the header: undo, redo, remove all
        tracker.redo = MiniButton(tracker.head, 14, "Interface\\Buttons\\UI-RefreshButton", nil, function()
            return ("Redo remove (%d)"):format(tracker.redo.steps or 0)
        end)
        tracker.redo:GetRegions():SetTexCoord(1, 0, 0, 1)
        tracker.redo:SetAlpha(0.9)
        tracker.redo:SetPoint("RIGHT", clear, "LEFT", -3, 0)
        tracker.redo:SetScript("OnClick", function()
            ns.FarmRedo()
        end)
        tracker.redo:Hide()
        function tracker.PlaceUndo(steps)
            tracker.redo.steps = steps
            tracker.redo:SetShown(steps > 0)
            tracker.undo:ClearAllPoints()
            tracker.undo:SetPoint("RIGHT", steps > 0 and tracker.redo or clear, "LEFT", -3, 0)
        end
        tracker.progress = tracker.head:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tracker.progress:SetPoint("TOPLEFT", 35, tracker.styled and -6 or -9)
        tracker.progress:SetDrawLayer("OVERLAY", 7)
        local function Line(point, y)
            local l = tracker:CreateTexture(nil, "ARTWORK")
            l:SetPoint(point .. "LEFT", 8 + PAD_IN, y)
            l:SetPoint(point .. "RIGHT", -8 - PAD_IN, y)
            l:SetHeight(1)
            l:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], 0.35)
            return l
        end
        tracker.line1 = Line("TOP", -HEAD_H)
        tracker.line2 = Line("BOTTOM", FOOT_H + 4)
        tracker.vendor = tracker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tracker.vendor:SetPoint("BOTTOMLEFT", 10 + PAD_IN, 11)
        tracker.auction = tracker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tracker.auction:SetPoint("BOTTOMRIGHT", -18 - PAD_IN, 11) -- clear of the resize grip
        tracker.auctionHit = CreateFrame("Frame", nil, tracker) -- hover area over the auction value
        tracker.auctionHit:SetAllPoints(tracker.auction)
        tracker.auctionHit:EnableMouse(true)
        tracker.auctionHit:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Prices from " .. (self.source or "an auction addon"))
            GameTooltip:Show()
        end)
        tracker.auctionHit:SetScript("OnLeave", GameTooltip_Hide)
        tracker.rows = {}
        tracker.heads = {}
        -- Items / Recipes: list the goals one by one, or grouped under the recipes they are for
        tracker.viewBar = CreateFrame("Frame", nil, tracker)
        tracker.viewBar:SetHeight(20)
        tracker.viewBar:SetPoint("TOPLEFT", 8 + PAD_IN, -(HEAD_H + 3))
        tracker.viewBar:SetPoint("TOPRIGHT", -8 - PAD_IN, -(HEAD_H + 3))
        local function ViewButton(label, value, point, tip)
            local b = CreateFrame("Button", nil, tracker.viewBar)
            -- each tab takes half of the bar, whatever the window's width
            if point == "LEFT" then
                b:SetPoint("TOPLEFT")
                b:SetPoint("BOTTOMRIGHT", tracker.viewBar, "BOTTOM", -1, 0)
            else
                b:SetPoint("TOPRIGHT")
                b:SetPoint("BOTTOMLEFT", tracker.viewBar, "BOTTOM", 1, 0)
            end
            b.value = value
            b.bg = b:CreateTexture(nil, "BACKGROUND")
            b.bg:SetAllPoints()
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 0.82, 0, 0.12)
            ns.TabBorder(b)
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.text:SetPoint("CENTER")
            b.text:SetText(label)
            b:SetScript("OnClick", function()
                db.farmTracker.view = value
                UpdateTracker()
            end)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(label)
                GameTooltip:AddLine(tip, 0.9, 0.9, 0.9, true)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", GameTooltip_Hide)
            return b
        end
        tracker.viewItems = ViewButton("Items", "items", "LEFT", "Every farming goal, one by one")
        tracker.viewRecipes = ViewButton("Recipes", "recipes", "RIGHT",
            "Grouped under the recipes you are farming for, each with its own remove button")
        tracker.otherHead = CreateFrame("Frame", nil, tracker.content)
        tracker.otherHead:SetSize(TRACK_W, 18)
        tracker.otherHead.text = tracker.otherHead:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tracker.otherHead.text:SetPoint("LEFT", 10, -2)
        tracker.otherHead.text:SetTextColor(0.7, 0.7, 0.7)
        -- "Completed (n)" section header; click to fold the finished goals away
        -- it lives on the window, not in the scrolling list: when its place in the list is below the visible
        -- part it stays docked at the bottom of the list, so the finished goals are always one click away
        tracker.doneHead = CreateFrame("Button", nil, tracker)
        tracker.doneHead:SetSize(TRACK_W, 20)
        tracker.doneHead:SetFrameLevel(tracker.scroll:GetFrameLevel() + 20)
        local dbg = tracker.doneHead:CreateTexture(nil, "BACKGROUND")
        dbg:SetPoint("TOPLEFT", 6, 0)
        dbg:SetPoint("BOTTOMRIGHT", -6, 0)
        dbg:SetColorTexture(0.07, 0.06, 0.05, 1) -- solid, so rows scrolling under it don't show through
        tracker.doneHead.bg = dbg
        tracker.doneHead.sign = tracker.doneHead:CreateTexture(nil, "ARTWORK")
        tracker.doneHead.sign:SetSize(14, 14)
        tracker.doneHead.sign:SetPoint("RIGHT", -9, -2)
        function tracker.PlaceDone()
            local head, scroll = tracker.doneHead, tracker.scroll
            if not tracker.doneY or not head:IsShown() then
                return
            end
            local at = tracker.doneY - (scroll:GetVerticalScroll() or 0)
            local last = (scroll:GetHeight() or 0) - 20
            local closed = db.farmTracker.hideDone
            if closed then
                at = last -- collapsed: it never moves, always the last line of the list area
            end
            head.docked = not closed and at > last
            head.bg:SetShown(closed or head.docked)
            head:ClearAllPoints()
            head:SetPoint("TOPLEFT", scroll, "TOPLEFT", PAD_IN, -math.max(math.min(at, last), 0))
        end
        tracker.scroll:HookScript("OnVerticalScroll", tracker.PlaceDone)
        tracker.scroll:HookScript("OnSizeChanged", tracker.PlaceDone)
        local dl = tracker.doneHead:CreateTexture(nil, "ARTWORK")
        dl:SetPoint("TOPLEFT", 8, 0)
        dl:SetPoint("TOPRIGHT", -8, 0)
        dl:SetHeight(1)
        dl:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], 0.35)
        tracker.doneHead.text = tracker.doneHead:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tracker.doneHead.text:SetPoint("LEFT", 10, -2)
        tracker.doneHead.text:SetTextColor(0.25, 1, 0.25)
        tracker.doneHead:SetScript("OnClick", function(self)
            if self.docked and not db.farmTracker.hideDone then
                tracker.scrollTo = tracker.doneY -- already open, just out of sight: go there
            else
                db.farmTracker.hideDone = not db.farmTracker.hideDone
                if not db.farmTracker.hideDone then
                    tracker.scrollTo = tracker.doneY
                end
            end
            UpdateTracker()
        end)
        tracker.doneHead:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(db.farmTracker.hideDone and "Show Completed"
                or self.docked and "Go to Completed" or "Hide Completed")
            GameTooltip:Show()
        end)
        tracker.doneHead:SetScript("OnLeave", GameTooltip_Hide)
        -- clear the finished goals in one click
        local clearDone = MiniButton(tracker.doneHead, 14, "Interface\\Buttons\\UI-GroupLoot-Pass-Up", nil,
            "Remove Completed")
        clearDone:SetAlpha(0.8)
        clearDone:SetPoint("RIGHT", tracker.doneHead.sign, "LEFT", -6, 0)
        clearDone:SetScript("OnClick", ns.FarmClearDone)
        -- background firms up while the mouse is over the tracker
        tracker:SetScript("OnShow", UpdateTracker)
    end
    db.farmTracker.shown = true
    tracker:Show()
    UpdateTracker()
end

---------------------------------------------------------------------------
-- Panel: one card per farmed item (icon, name, have / target, progress bar, value, target stepper)
---------------------------------------------------------------------------
local CARD_H = 62

-- open / close the Farming tracker window (minimap right-click, button on the Farming tab)
function ns.ToggleFarmTracker()
    if tracker and tracker:IsShown() then
        ns.ShowFarmTracker(false)
    elseif #List() == 0 then
        ns.Print("Your farming list is empty - add an item first.")
    else
        ns.ShowFarmTracker()
    end
end

local function SetTarget(id, n)
    local e = Find(id)
    if e then
        e.target = math.max(math.floor(n or 1), 1)
        e.done = ns.Have(id) >= e.target
    end
    Render()
end

local function StepButton(parent, kind)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(16, 16)
    b:SetNormalTexture("Interface\\Buttons\\UI-" .. kind .. "Button-Up")
    b:SetPushedTexture("Interface\\Buttons\\UI-" .. kind .. "Button-Down")
    b:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    return b
end

local function CreateFarmCard(parent)
    local f = CreateFrame("Button", nil, parent, "BackdropTemplate")
    ns.Skin(f, { 0.08, 0.07, 0.06, 0.95 }, { BRONZE[1], BRONZE[2], BRONZE[3], 1 }, 4)
    ns.SkinGradient(f, { 0.13, 0.11, 0.09, 0.95 }, { 0.08, 0.07, 0.06, 0.95 })
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(40, 40)
    f.icon:SetPoint("LEFT", 10, 0)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.border = f:CreateTexture(nil, "OVERLAY")
    f.border:SetAllPoints(f.icon)
    f.border:SetTexture("Interface\\Common\\WhiteIconFrame")
    f.tick = f:CreateTexture(nil, "OVERLAY", nil, 2)
    f.tick:SetSize(16, 16)
    f.tick:SetPoint("BOTTOMRIGHT", f.icon, "BOTTOMRIGHT", 4, -4)
    f.tick:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")

    -- right column: target stepper, then pin + remove
    f.plus = StepButton(f, "Plus")
    f.plus:SetPoint("TOPRIGHT", -10, -10)
    f.box = CreateFrame("EditBox", nil, f)
    f.box:SetSize(40, 18)
    f.box:SetPoint("RIGHT", f.plus, "LEFT", -2, 0)
    f.box:SetAutoFocus(false)
    f.box:SetNumeric(true)
    f.box:SetMaxLetters(5)
    f.box:SetJustifyH("CENTER")
    f.box:SetFontObject("NumberFontNormal")
    local boxBg = f.box:CreateTexture(nil, "BACKGROUND")
    boxBg:SetAllPoints()
    boxBg:SetColorTexture(0, 0, 0, 0.55)
    local edge = CreateFrame("Frame", nil, f.box, "BackdropTemplate")
    edge:SetAllPoints()
    ns.Skin(edge, { 0, 0, 0, 0 }, { 0.4, 0.4, 0.4, 1 }, 0)
    f.minus = StepButton(f, "Minus")
    f.minus:SetPoint("RIGHT", f.box, "LEFT", -2, 0)
    f.targetLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.targetLabel:SetPoint("RIGHT", f.minus, "LEFT", -6, 0)
    f.targetLabel:SetText("Target")
    local function Step(d)
        local e = Find(f.id)
        if e then
            SetTarget(f.id, e.target + d * (IsShiftKeyDown() and 20 or 5))
        end
    end
    f.plus:SetScript("OnClick", function()
        Step(1)
    end)
    f.minus:SetScript("OnClick", function()
        Step(-1)
    end)
    for _, b in ipairs({ f.plus, f.minus }) do
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self == f.plus and "Target +5" or "Target -5")
            GameTooltip:AddLine("Shift-Click: 20 at a time", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
    end
    f.box:SetScript("OnEnterPressed", function(self)
        SetTarget(f.id, tonumber(self:GetText()) or 1)
        self:ClearFocus()
    end)
    f.box:SetScript("OnEscapePressed", f.box.ClearFocus)
    f.box:SetScript("OnEditFocusGained", f.box.HighlightText)
    f.box:SetScript("OnEditFocusLost", function(self)
        local e = Find(f.id)
        self:SetText(e and tostring(e.target) or "")
    end)
    f.del = MiniButton(f, 16, nil, "x", "Remove from Farming")
    f.del:SetPoint("BOTTOMRIGHT", -10, 10)
    f.del:SetScript("OnClick", function()
        Remove(f.id)
    end)
    f.pin = MiniButton(f, 16, ns.Tex("Arrow"), nil, "Set Location")
    f.pin:SetPoint("RIGHT", f.del, "LEFT", -6, 0)
    f.pin:SetScript("OnClick", function()
        ns.WaypointNearest(f.id)
    end)
    f.pin:HookScript("OnEnter", function(self) -- nearest source is an NPC close by: also target and star it
        local id = f.id
        local s = ns.NearestSpot and ns.NearestSpot(id)
        if s and ns.ArmTarget then
            ns.ArmTarget(self, s.map, s.x, s.y, s.name, s.kind == "Gather" or s.kind == "Fish", function()
                ns.WaypointNearest(id)
            end)
        end
    end)

    -- middle: name + count, bar, value line
    f.count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.count:SetPoint("TOPRIGHT", -170, -10)
    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.name:SetPoint("TOPLEFT", 60, -10)
    f.name:SetPoint("RIGHT", f.count, "LEFT", -8, 0)
    f.name:SetJustifyH("LEFT")
    f.name:SetWordWrap(false)
    f.track = f:CreateTexture(nil, "BORDER")
    f.track:SetPoint("TOPLEFT", 60, -29)
    f.track:SetPoint("RIGHT", -170, 0)
    f.track:SetHeight(5)
    f.track:SetColorTexture(1, 1, 1, 0.07)
    f.fill = f:CreateTexture(nil, "ARTWORK")
    f.fill:SetPoint("TOPLEFT", f.track, "TOPLEFT")
    f.fill:SetHeight(5)
    f.fill:SetTexture(WHITE)
    f.value = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.value:SetPoint("TOPLEFT", 60, -40)
    f.value:SetPoint("RIGHT", -170, 0)
    f.value:SetJustifyH("LEFT")
    f.value:SetWordWrap(false)

    f:SetScript("OnClick", function(self)
        if ns.ShowReagent then
            ns.ShowReagent(self.id)
        end
    end)
    f:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.62, 0.5, 0.3, 1)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetItemByID(self.id)
        local near = ns.NearestText and ns.NearestText(self.id)
        if near then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Nearest: " .. near, 1, 0.82, 0)
        end
        GameTooltip:AddLine("Click: open on the Reagents tab", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(BRONZE[1], BRONZE[2], BRONZE[3], 1)
        GameTooltip:Hide()
    end)
    return f
end

local function UpdateFarmCard(f, e, w)
    local h = ns.Have(e.id)
    local done = h >= e.target
    local state = done and "done" or h > 0 and "some" or "none"
    f.id = e.id
    f.icon:SetTexture(ItemIconPath(e.id))
    f.border:SetVertexColor(QualityRGB(e.id))
    f.tick:SetShown(done)
    f.name:SetText(ns.QualityColor(e.id) .. ns.ItemName(e.id) .. "|r")
    f.count:SetText(("%d / %d"):format(h, e.target))
    f.count:SetTextColor(unpack(STATE_RGB[state]))
    local pct = e.target > 0 and math.min(h / e.target, 1) or 1
    f.fill:SetShown(pct > 0)
    f.fill:SetWidth(math.max((w - 230) * pct, 1))
    if done then
        f.fill:SetVertexColor(0.25, 1, 0.25, 0.7)
    else
        f.fill:SetVertexColor(1, 0.82, 0, 0.9)
    end
    local a = AuctionPrice(e.id)
    f.value:SetText(("%sVendor|r  %s%s"):format(C_DIM, Money(VendorPrice(e.id) * e.target),
        a and ("      " .. C_DIM .. "Auction|r  " .. Money(a * e.target)) or ""))
    if not f.box:HasFocus() then
        f.box:SetText(tostring(e.target))
    end
    return CARD_H
end

-- section bar of the Farming tab ("In Progress" / "Done"), collapsible like the reagent list categories
local function CreateSection(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(25)
    b.bar = ns.HeaderBar(b)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.5)
    b.text = b:CreateFontString(nil, "OVERLAY", ns.HEADER_FONT)
    b.text:SetPoint("LEFT", 10, 0)
    b.sign = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    b.sign:SetPoint("RIGHT", -8, 0)
    b:SetScript("OnClick", function(self)
        db.farmClosed = db.farmClosed or {}
        db.farmClosed[self.key] = not db.farmClosed[self.key] or nil
        Render()
    end)
    return b
end

local function UpdateSection(b, d)
    b.key = d.key
    b.text:SetText(("%s  %s(%d)|r"):format(d.name, C_DIM, d.count))
    b.bar:SetOpen(d.open)
    b.sign:SetText(ns.SignText(d.open))
    return 25
end

function Render()
    UpdateTracker()
    if ns.UpdateCraftTracker then
        ns.UpdateCraftTracker()
    end
    if not panel or not panel:IsVisible() then
        return
    end
    local lines, totalV, totalA, have, need = {}, 0, 0, 0, 0
    local items, done = Sorted()
    if #items == 0 then
        lines[1] = " "
        lines[2] = C_DIM .. "Your farming list is empty.|r"
        lines[3] = " "
        lines[4] = C_SOFT .. "Add items with the box on the right (type a name or ID, or Shift-Click an item),|r"
        lines[5] = C_SOFT .. "or use |r" .. C_GOLD .. "Farming|r" .. C_SOFT .. " on a recipe card of the Reagents tab.|r"
    end
    local closed = db.farmClosed or {}
    local function Section(key, name, count)
        local open = not closed[key]
        lines[#lines + 1] = { widget = "section", gap = open and 6 or 8,
            data = { key = key, name = name, count = count, open = open } }
        return open
    end
    local nOpen = #items - done
    local show = true
    for i, e in ipairs(items) do
        local h = ns.Have(e.id)
        local a = AuctionPrice(e.id)
        totalV = totalV + VendorPrice(e.id) * e.target
        totalA = totalA + (a or 0) * e.target
        have, need = have + math.min(h, e.target), need + e.target
        if i == 1 and nOpen > 0 then
            show = Section("open", "In Progress", nOpen)
        end
        if i == nOpen + 1 then
            if nOpen > 0 then
                lines[#lines + 1] = { space = 4 }
            end
            show = Section("done", "Done", done)
        end
        if show then
            lines[#lines + 1] = { widget = "farm", data = e, gap = 6 }
        end
    end
    listText:SetLines(lines)
    local _, src = AuctionPrice(items[1] and items[1].id or 2589)
    summary:SetText(table.concat({
        C_GOLD .. "Progress|r",
        ("%s%d / %d|r goals done"):format(C_HEAD, done, #items),
        ("%s%d / %d|r items"):format(C_HEAD, have, need),
        " ",
        C_GOLD .. "Estimated Value|r",
        C_DIM .. "Vendor|r   " .. Money(totalV),
        C_DIM .. "Auction|r  " .. (totalA > 0 and Money(totalA) or (C_DIM .. "-|r")),
        C_DIM .. "(" .. (src and ("prices from " .. src) or "no auction addon prices yet") .. ")|r",
    }, "\n"))
end

-- resolve typed text: item link, item ID, or exact item name (cached items)
local function ResolveItem(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local id = tonumber(text:match("item:(%d+)")) or tonumber(text)
    if id then
        return id
    end
    if text ~= "" then
        local f = C_Item and C_Item.GetItemInfo or GetItemInfo
        local ok, _, link = pcall(f or error, text)
        if ok and type(link) == "string" then
            return tonumber(link:match("item:(%d+)"))
        end
    end
end

function ns.CreateFarmPanel(f, inset, helperDB)
    db = helperDB
    local T = ns.T
    panel = CreateFrame("Frame", nil, f)
    panel:SetAllPoints(f)

    local left = ns.Card(panel, nil, 12)
    left:SetPoint("TOPLEFT", inset, "TOPLEFT")
    left:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -312, 0)
    local title = left:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Farming List")
    title:SetTextColor(unpack(T.accent))
    local removeAll = ns.CreateButton(left, "Remove All", 96)
    removeAll:SetPoint("TOPRIGHT", -16, -9)
    removeAll:SetScript("OnClick", function()
        ns.FarmRemoveAll()
    end)
    local sep = left:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(unpack(T.border))
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", 16, -36)
    sep:SetPoint("TOPRIGHT", -16, -36)
    listText = ns.CreateScrollText(left)
    listText:RegisterWidget("farm", CreateFarmCard, UpdateFarmCard)
    listText:RegisterWidget("section", CreateSection, UpdateSection)
    listText:SetPoint("TOPLEFT", 14, -46)
    listText:SetPoint("BOTTOMRIGHT", -30, 12)

    local right = ns.Card(panel, nil, 12)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, 0)
    right:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT")
    local addTitle = right:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    addTitle:SetPoint("TOPLEFT", 16, -14)
    addTitle:SetText("Add Item")
    addTitle:SetTextColor(unpack(T.accent))
    local hint = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", addTitle, "BOTTOMLEFT", 0, -4)
    hint:SetText("Name, item ID or Shift-Click an item")
    local box = ns.CreateEditBox(right)
    box:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
    box:SetPoint("RIGHT", right, "RIGHT", -16, 0)
    local amount = ns.CreateEditBox(right)
    amount:SetWidth(70)
    amount:SetNumeric(true)
    amount:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -8)
    local amountLabel = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    amountLabel:SetPoint("LEFT", amount, "RIGHT", 8, 0)
    amountLabel:SetText("Target (empty = one stack)")
    local add = ns.CreateButton(right, "Add to List", 120)
    add:SetPoint("TOPLEFT", amount, "BOTTOMLEFT", 0, -10)
    local function DoAdd()
        local id = ResolveItem(box:GetText())
        if not id then
            ns.Print("Item Not Found - Try Its ID or Shift-Click It")
            return
        end
        local n = tonumber(amount:GetText())
        local e = Find(id)
        if e and n then
            e.target = n
            e.done = ns.Have(id) >= n
            Render()
        else
            ns.FarmAdd(id, n)
        end
        box:SetText("")
        amount:SetText("")
        box:ClearFocus()
        amount:ClearFocus()
    end
    add:SetScript("OnClick", DoAdd)
    local trackerBtn = ns.CreateButton(right, "Farming Window", 130)
    trackerBtn:SetPoint("TOPLEFT", add, "BOTTOMLEFT", 0, -8)
    trackerBtn:SetScript("OnClick", ns.ToggleFarmTracker)
    trackerBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Farming Tracker")
        GameTooltip:AddLine("Open or close the small window that tracks your farming goals", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    trackerBtn:SetScript("OnLeave", GameTooltip_Hide)
    local craftBtn = ns.CreateButton(right, "Crafting Window", 130)
    craftBtn:SetPoint("LEFT", trackerBtn, "RIGHT", 8, 0)
    craftBtn:SetScript("OnClick", function()
        ns.ToggleCraftTracker()
    end)
    craftBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Crafting Tracker")
        GameTooltip:AddLine("Open or close the small window with the recipes you track (Track box on a recipe card)",
            0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    craftBtn:SetScript("OnLeave", GameTooltip_Hide)
    box:SetScript("OnEnterPressed", DoAdd)
    amount:SetScript("OnEnterPressed", DoAdd)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    amount:SetScript("OnEscapePressed", amount.ClearFocus)
    -- Shift-Click an item while the box has focus inserts its link
    if ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", function(link)
            if box:HasFocus() and type(link) == "string" then
                box:SetText(link)
            end
        end)
    end

    local sep2 = right:CreateTexture(nil, "ARTWORK")
    sep2:SetColorTexture(unpack(T.border))
    sep2:SetHeight(1)
    sep2:SetPoint("TOPLEFT", trackerBtn, "BOTTOMLEFT", 0, -16)
    sep2:SetPoint("RIGHT", right, "RIGHT", -16, 0)
    summary = right:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    summary:SetPoint("TOPLEFT", sep2, "BOTTOMLEFT", 0, -14)
    summary:SetPoint("RIGHT", right, "RIGHT", -16, 0)
    summary:SetJustifyH("LEFT")
    summary:SetSpacing(5)

    local track = ns.CreateButton(right, "Tracker", 90)
    track:SetPoint("BOTTOMRIGHT", -16, 14)
    track:SetScript("OnClick", function()
        local shown = _G.HelperFarmTracker and _G.HelperFarmTracker:IsShown()
        ns.ShowFarmTracker(not shown)
    end)
    local clear = ns.CreateButton(right, "Clear Done", 110)
    clear:SetPoint("BOTTOMLEFT", 16, 14)
    clear:SetScript("OnClick", function()
        local keep = {}
        for _, e in ipairs(List()) do
            if ns.Have(e.id) < e.target then
                keep[#keep + 1] = e
            end
        end
        db.farm = keep
        Render()
    end)

    panel:SetScript("OnShow", Render)
    local events = CreateFrame("Frame")
    for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED", "GET_ITEM_INFO_RECEIVED" }) do
        pcall(events.RegisterEvent, events, ev)
    end
    local pending
    events:SetScript("OnEvent", function()
        if pending then
            return
        end
        pending = true
        C_Timer.After(0.5, function()
            pending = false
            CheckGoals()
            Render()
        end)
    end)
    -- (the Farming / Crafting windows stay closed after a login or reload until they are opened again)
    ns.OnSetting("craftReqs", function()
        if ns.UpdateCraftTracker then
            ns.UpdateCraftTracker()
        end
    end)
    -- first check without popups for goals already met at login
    for _, e in ipairs(List()) do
        e.done = ns.Have(e.id) >= e.target
    end
    return panel
end

---------------------------------------------------------------------------
-- Crafting tracker: a small window (same look as the Farming tracker) listing the recipes you chose to
-- track - "N ready" + a Craft button (or why it can't be crafted yet) and the materials with have / need.
-- HelperDB.craftList = { spellID, ... }   HelperDB.craftTracker = { shown, min, pos }
---------------------------------------------------------------------------
local craftWin
local CRAFT_W, CRAFT_ROW, CRAFT_SUB = 330, ROW_H, SUB_H
-- CRAFT_INDENT: where a recipe's name starts, so its materials line up under it
-- CRAFT_EDGE: right edge of the Craft / status / have-need column (the remove icon sits in the gutter beyond)
-- CRAFT_STATUS: widest a recipe's status text may get
local CRAFT_INDENT, CRAFT_EDGE = 35, 28
local recipeCache = {}

local function CraftDB()
    local d = db or HelperDB
    d.craftList = d.craftList or {}
    d.craftTracker = d.craftTracker or {}
    return d
end

local function CraftRecipeOf(spellID)
    if recipeCache[spellID] == nil then
        recipeCache[spellID] = ns.FindRecipe and ns.FindRecipe(spellID) or false
    end
    return recipeCache[spellID] or nil
end

function ns.CraftTracked(spellID)
    for i, id in ipairs(CraftDB().craftList) do
        if id == spellID then
            return i
        end
    end
end

local function RecipeIconPath(rec)
    if rec.item then
        return ItemIconPath(rec.item)
    end
    local tex = C_Spell and C_Spell.GetSpellTexture and Safe(C_Spell.GetSpellTexture, rec.spellID)
    return tex or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local UpdateCraftWin

-- tooltip of a recipe row's Craft button (what a click does) or of its status text (why it can't be crafted)
local function CraftTip(owner, r)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    local name = r.rec and ns.RecipeName and ns.RecipeName(r.rec) or "recipe"
    if r.craft:IsEnabled() then
        local n = r.crafts or 1
        GameTooltip:SetText("Craft " .. name)
        GameTooltip:AddLine(("You have materials for %d"):format(n), 0.25, 1, 0.25)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Click", "Craft one", 1, 0.82, 0, 1, 1, 1)
        if n > 1 then
            GameTooltip:AddDoubleLine("Shift-click", ("Craft all %d"):format(n), 1, 0.82, 0, 1, 1, 1)
        end
    else
        GameTooltip:SetText("Can't craft " .. name .. " yet")
        for _, line in ipairs(r.why or {}) do
            GameTooltip:AddLine(line, 1, 0.25, 0.25, true)
        end
    end
    GameTooltip:Show()
end

local function CraftRow(i)
    local r = craftWin.rows[i]
    if r then
        return r
    end
    r = CreateFrame("Button", nil, craftWin.content)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 6, 0)
    hl:SetPoint("BOTTOMRIGHT", -6, 0)
    hl:SetColorTexture(1, 1, 1, 0.06)
    -- recipe rows carry the same bronze band as the recipe headers of the Farming window
    r.band = r:CreateTexture(nil, "BACKGROUND")
    r.band:SetPoint("TOPLEFT", 6, -1)
    r.band:SetPoint("BOTTOMRIGHT", -6, 1)
    r.band:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], 0.45)
    -- lit while what this recipe makes is the item open in the Grist for the Mill window
    r.sel = r:CreateTexture(nil, "BORDER")
    r.sel:SetAllPoints(r.band)
    r.sel:SetColorTexture(1, 0.82, 0, 0.28)
    r.sel:Hide()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.remove = MiniButton(r, 12, "Interface\\Buttons\\UI-StopButton", nil, "Stop tracking")
    r.remove:SetPoint("RIGHT", -9, 0)
    r.remove:SetScript("OnClick", function()
        ns.CraftTrack(r.spell, false)
    end)
    -- material rows: show on map + arrow to the nearest source, as in the Farming window
    r.map = MiniButton(r, 14, ns.Tex("Pin"), nil, "Show on Map")
    r.map:SetAlpha(0.8)
    r.map:SetPoint("RIGHT", -8, 0)
    r.map:SetScript("OnClick", function()
        if ns.ShowItemMap then
            ns.ShowItemMap(r.item)
        end
    end)
    r.pin = MiniButton(r, 14, ns.Tex("Arrow"), nil, "Set Location")
    r.pin:SetAlpha(0.8)
    r.pin:SetPoint("RIGHT", r.map, "LEFT", -3, 0)
    r.pin:SetScript("OnClick", function()
        ns.WaypointNearest(r.item)
    end)
    r.pin:HookScript("OnEnter", function(self) -- nearest source is an NPC close by: also target and star it
        local id = r.item
        local s = ns.NearestSpot and ns.NearestSpot(id)
        if s and ns.ArmTarget then
            ns.ArmTarget(self, s.map, s.x, s.y, s.name, s.kind == "Gather" or s.kind == "Fish", function()
                ns.WaypointNearest(id)
            end)
        end
    end)
    function r.Hover(self) -- (MiniButton calls this when the pointer leaves it) back to the resting look
        self.map:SetAlpha(0.8)
        self.pin:SetAlpha(0.8)
    end
    r.craft = ns.CreateButton(r, "Craft", 52)
    r.craft:SetHeight(18)
    r.craft:SetPoint("RIGHT", -CRAFT_EDGE, 0)
    if r.craft.SetNormalFontObject then
        r.craft:SetNormalFontObject("GameFontNormalSmall")
        r.craft:SetHighlightFontObject("GameFontHighlightSmall")
        r.craft:SetDisabledFontObject("GameFontDisableSmall")
    end
    if r.craft.SetMotionScriptsWhileDisabled then
        r.craft:SetMotionScriptsWhileDisabled(true)
    end
    r.craft:SetScript("OnClick", function()
        local craft = ns.Get("craftSilent") ~= false and ns.CraftSilent or ns.DoCraft
        if r.rec and craft then
            craft(r.rec, r.crafts)
        end
    end)
    r.craft:SetScript("OnEnter", function(self)
        CraftTip(self, r)
    end)
    r.craft:SetScript("OnLeave", GameTooltip_Hide)
    r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.count:SetJustifyH("RIGHT")
    r.count:SetWordWrap(false)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            local spell = self.spell
            local rec = spell and ns.FindRecipe and ns.FindRecipe(spell)
            RowMenu(self, rec and ns.RecipeName(rec) or "Recipe", function()
                ns.CraftTrack(spell, false)
            end, ns.CraftRemoveAll)
        elseif self.item and ns.ShowReagent then
            ns.ShowReagent(self.item)
        end
    end)
    r:SetScript("OnEnter", function(self)
        if self.item then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            if not pcall(GameTooltip.SetItemByID, GameTooltip, self.item) then
                GameTooltip:SetText(ns.ItemName(self.item))
            end
            GameTooltip:AddLine("Click: open in Grist for the Mill", 0.6, 0.6, 0.6)
            GameTooltip:AddLine("Right-click: stop tracking / remove all", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    craftWin.rows[i] = r
    return r
end

-- recipe row (band: icon, name, then "N ready" + Craft or the reason it can't be crafted, remove in its own
-- gutter) or material row (icon under the recipe's name, name, have/need in the same right-hand column)
local function ShapeCraftRow(r, sub)
    r:SetHeight(sub and CRAFT_SUB or CRAFT_ROW)
    r.icon:ClearAllPoints()
    r.icon:SetSize(sub and 14 or 20, sub and 14 or 20)
    r.icon:SetPoint("LEFT", sub and CRAFT_INDENT or 10, 0)
    r.craft:SetShown(not sub)
    r.remove:SetShown(not sub)
    r.band:SetShown(not sub)
    r.map:Hide()
    r.pin:Hide()
    r.sel:Hide()
    r.count:ClearAllPoints()
    r.count:SetWidth(0)
    r.count:SetPoint("RIGHT", -CRAFT_EDGE, 0)
    r.name:ClearAllPoints()
    r.name:SetFontObject(sub and "GameFontHighlightSmall" or "GameFontNormal")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
    r.name:SetPoint("RIGHT", r.count, "LEFT", -6, 0)
    r.name:SetWordWrap(false)
end

-- right-hand side of a recipe row: "N ready" + Craft; the button is greyed out while something is in the
-- way, and its tooltip says what
local function SetCraftState(r, crafts)
    local can = #r.why == 0
    r.craft:SetEnabled(can)
    r.count:ClearAllPoints()
    r.count:SetPoint("RIGHT", r.craft, "LEFT", -6, 0)
    r.count:SetText(can and ("%d ready"):format(crafts) or "")
    r.count:SetTextColor(unpack(STATE_RGB.done))
end

UpdateCraftWin = function()
    if not craftWin or not craftWin:IsShown() then
        return
    end
    local d = CraftDB()
    if #d.craftList == 0 and #craftUndo == 0 and #craftRedo == 0 then
        craftWin:Hide() -- nothing tracked; comes back when a recipe is added
        return
    end
    craftWin.undo:SetShown(#craftUndo > 0) -- only after a removal that can still be undone
    craftWin.undo.steps = #craftUndo
    craftWin.PlaceUndo(#craftRedo)
    local min = d.craftTracker.min
    local n, y, ready = 0, 0, 0 -- y: down the scrolling list
    craftWin.selY = nil
    local rowW = craftWin.RowWidth()
    local function Next(sub)
        n = n + 1
        local r = CraftRow(n)
        ShapeCraftRow(r, sub)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", PAD_IN, -y)
        r:SetWidth(rowW)
        r:Show()
        y = y + (sub and CRAFT_SUB or CRAFT_ROW)
        return r
    end
    -- All / Ready to Craft: the second tab keeps only the recipes you know and have the materials for
    local view = d.craftTracker.view == "ready" and "ready" or "all"
    for _, b in ipairs({ craftWin.viewAll, craftWin.viewReady }) do
        local on = b.value == view
        b.bg:SetColorTexture(on and 0.55 or 0, on and 0.42 or 0, on and 0.18 or 0, on and 0.55 or 0.35)
        b.text:SetTextColor(on and 1 or 0.6, on and 1 or 0.6, on and 1 or 0.6)
        if on then
            b:SetBorderColor(1, 0.82, 0, 0.9)
        else
            b:SetBorderColor(0.45, 0.36, 0.2, 0.9)
        end
    end
    local list = {}
    for _, spell in ipairs(d.craftList) do
        local rec = CraftRecipeOf(spell)
        if rec and ns.IsKnown(spell) and (ns.MaxCrafts and ns.MaxCrafts(rec) or 0) > 0 then
            ready = ready + 1
            list[#list + 1] = spell
        end
    end
    craftWin.viewReady.text:SetText(("Ready to Craft (%d)"):format(ready))
    if view == "all" then
        list = d.craftList
    end
    craftWin.empty:SetShown(#list == 0)
    if #list == 0 then
        craftWin.empty:SetText(view == "ready" and "Nothing ready to craft" or "No recipes tracked")
        y = y + 28
    end
    for _, spell in ipairs(list) do
        local rec = CraftRecipeOf(spell)
        if rec then
            local known = ns.IsKnown(spell)
            local crafts = ns.MaxCrafts and ns.MaxCrafts(rec) or 0
            local r = Next(false)
            r.spell, r.rec, r.crafts, r.item = spell, rec, crafts, rec.item
            r.icon:SetTexture(RecipeIconPath(rec))
            r.icon:SetDesaturated(not known)
            r.name:SetText((rec.item and ns.QualityColor(rec.item) or "|cffffd100")
                .. (ns.RecipeName and ns.RecipeName(rec) or tostring(spell)) .. "|r")
            -- what the recipe needs nearby / in your bags (anvil, cooking fire, tools): green when met
            local reqs = C_TradeSkillUI and C_TradeSkillUI.GetRecipeRequirements
                and Safe(C_TradeSkillUI.GetRecipeRequirements, spell)
            local parts, unmet = {}, {}
            for _, q in ipairs(type(reqs) == "table" and reqs or {}) do
                if type(q) == "table" and q.name then
                    parts[#parts + 1] = (q.met and "|cff40ff40" or "|cffff4040") .. q.name .. "|r"
                    if not q.met then
                        unmet[#unmet + 1] = q.name
                    end
                end
            end
            -- Craft only shows once the recipe is known, the materials are there and every requirement is met
            r.why = {}
            if not known then
                r.why[#r.why + 1] = "Learn this recipe first"
            end
            if crafts <= 0 then
                r.why[#r.why + 1] = "Missing materials"
            end
            if #unmet > 0 then
                r.why[#r.why + 1] = "Requires " .. table.concat(unmet, ", ")
            end
            SetCraftState(r, crafts)
            r.sel:SetShown(rec.item ~= nil and ns.SelectedItem ~= nil and ns.SelectedItem() == rec.item)
            if r.sel:IsShown() and not craftWin.selY then
                craftWin.selY = y - CRAFT_ROW -- where the highlighted recipe sits in the list
            end
            if not min then
                if ns.Get("craftReqs") ~= false then
                    if #parts > 0 then
                        local s = Next(true)
                        s.spell, s.rec, s.item = spell, nil, nil
                        s.icon:SetTexture(nil)
                        s.count:SetText("")
                        -- a long list wraps onto more lines instead of being cut off
                        s.name:SetWordWrap(true)
                        -- no icon on this line: the text starts right under the recipe's icon
                        s.name:ClearAllPoints()
                        s.name:SetPoint("LEFT", s, "LEFT", 10, 0)
                        s.name:SetPoint("RIGHT", s, "RIGHT", -CRAFT_EDGE, 0)
                        s.name:SetJustifyH("LEFT")
                        s.name:SetText("|cff909090Requires:|r " .. table.concat(parts, "|cff909090,|r "))
                        local h = math.max(CRAFT_SUB, math.ceil(s.name:GetStringHeight()) + 4)
                        s:SetHeight(h)
                        y = y + h - CRAFT_SUB
                    end
                end
                if not known then
                    -- what teaches it: the pattern / plans item, or a trainer. Click opens it in Grist for the Mill
                    local s = Next(true)
                    local teach = rec.recipeItem
                    s.spell, s.rec, s.item = spell, nil, teach or rec.item
                    s.icon:SetTexture(nil)
                    s.count:SetText("")
                    s.name:ClearAllPoints()
                    s.name:SetPoint("LEFT", s, "LEFT", 10, 0)
                    s.name:SetPoint("RIGHT", s, "RIGHT", -CRAFT_EDGE, 0)
                    s.name:SetJustifyH("LEFT")
                    s.name:SetText("|cff909090Not learned:|r " .. (teach
                        and (ns.QualityColor(teach) .. "[" .. ns.ItemName(teach) .. "]|r")
                        or "|cffffd100[Taught by a trainer]|r"))
                end
                for _, rg in ipairs(rec.reagents or {}) do
                    local have, need = ns.Have(rg[1]), rg[2]
                    local s = Next(true)
                    s.spell, s.rec, s.item = spell, nil, rg[1]
                    s.map:Show()
                    s.pin:Show()
                    s.count:ClearAllPoints()
                    s.count:SetPoint("RIGHT", s.pin, "LEFT", -6, 0)
                    s.icon:SetTexture(ItemIconPath(rg[1]))
                    s.icon:SetDesaturated(false)
                    s.name:SetText(ns.QualityColor(rg[1]) .. ns.ItemName(rg[1]) .. "|r")
                    s.count:SetText(("%d/%d"):format(have, need))
                    s.count:SetTextColor(unpack(STATE_RGB[have >= need and "done" or have > 0 and "some" or "none"]))
                end
                y = y + 6
            end
        end
    end
    for i = n + 1, #craftWin.rows do
        craftWin.rows[i]:Hide()
    end
    craftWin.progress:SetText(("|cff40ff40%d|r / %d ready"):format(ready, #d.craftList))
    craftWin.min:GetRegions():SetTexture("Interface\\Buttons\\UI-" .. (min and "Plus" or "Minus") .. "Button-Up")
    if craftWin.Layout(y, false) and not craftWin.again then
        craftWin.again = true -- the scroll bar came or went: the rows have a new width
        UpdateCraftWin()
        craftWin.again = nil
        return
    end
    ns.ApplyTrackerDock()
end
ns.UpdateCraftTracker = UpdateCraftWin

-- the item open in the Grist for the Mill window changed: move the highlight in both windows
function ns.RefreshTrackers()
    UpdateTracker()
    UpdateCraftWin()
    -- bring the highlighted recipe into view in both lists. Done now and again shortly after: the scroll
    -- frames settle their size and range a frame late, and an early jump can be thrown away
    local function Reveal()
        for _, w in ipairs({ tracker or false, craftWin or false }) do
            if w and w:IsShown() and w.selY and w.scroll:IsShown() then
                local view, at = w.scroll:GetHeight() or 0, w.scroll:GetVerticalScroll() or 0
                if w.selY < at or w.selY + ROW_H > at + view then
                    local range = math.max((w.content:GetHeight() or 0) - view, 0)
                    local to = math.max(math.min(w.selY - 4, range), 0)
                    w.scroll:SetVerticalScroll(to)
                    if w.scroll.ScrollBar and w.scroll.ScrollBar.SetScrollPercentage and range > 0 then
                        pcall(w.scroll.ScrollBar.SetScrollPercentage, w.scroll.ScrollBar, to / range)
                    end
                end
            end
        end
    end
    Reveal()
    C_Timer.After(0, Reveal)
    C_Timer.After(0.2, Reveal)
end

function ns.ShowCraftTracker(show)
    local d = CraftDB()
    if show == false then
        if craftWin then
            craftWin:Hide()
        end
        d.craftTracker.shown = false
        return
    end
    if #d.craftList == 0 then
        return
    end
    if not craftWin then
        local close
        craftWin, close = PanelFrame("GristForTheMillCraftTracker", "Crafting", function()
            ns.ShowCraftTracker(false)
        end)
        ns.TrackerScroll(craftWin, "craft", CraftDB().craftTracker, HEAD_H + 4 + 24, 14, -- 24: the tab bar
            CRAFT_W + 2 * PAD_IN, 260, function()
                UpdateCraftWin()
            end)
        craftWin:SetFrameStrata("HIGH")
        craftWin:SetToplevel(true)
        craftWin:SetClampedToScreen(true)
        craftWin:SetMovable(true)
        craftWin:EnableMouse(true)
        craftWin:RegisterForDrag("LeftButton")
        craftWin:SetScript("OnDragStart", function()
            ns.TrackerDragStart("craft")
        end)
        craftWin:SetScript("OnDragStop", function()
            ns.TrackerDragStop("craft")
        end)
        craftWin:HookScript("OnHide", function()
            ns.ApplyTrackerDock()
        end)
        local pos = d.craftTracker.pos
        if pos then
            craftWin:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos[1], pos[2])
        else
            craftWin:SetPoint("TOPRIGHT", UIParent, "RIGHT", -330, 160) -- left of the Farming tracker
        end
        craftWin.min = MiniButton(craftWin.head, 16, "Interface\\Buttons\\UI-MinusButton-Up", nil, function()
            return CraftDB().craftTracker.min and "Show materials" or "Hide materials"
        end)
        craftWin.min:SetAlpha(1)
        craftWin.min:SetPoint("RIGHT", close, "LEFT", -3, 0)
        craftWin.min:SetScript("OnClick", function()
            local t = CraftDB().craftTracker
            t.min = not t.min
            UpdateCraftWin()
        end)
        local clear = MiniButton(craftWin.head, 14, "Interface\\Buttons\\UI-GroupLoot-Pass-Up", nil, "Stop tracking all")
        clear:SetAlpha(0.8)
        clear:SetPoint("RIGHT", craftWin.min, "LEFT", -3, 0)
        clear:SetScript("OnClick", function()
            ns.CraftRemoveAll()
        end)
        craftWin.undo = MiniButton(craftWin.head, 14, "Interface\\Buttons\\UI-RefreshButton", nil, function()
            return ("Undo remove (%d). Right-click: choose how far back"):format(craftWin.undo.steps or 0)
        end)
        craftWin.undo:SetAlpha(0.9)
        craftWin.undo:SetPoint("RIGHT", clear, "LEFT", -3, 0)
        craftWin.undo:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        craftWin.undo:SetScript("OnClick", function(self, button)
            if button ~= "RightButton" then
                ns.CraftUndo()
                return
            end
            ns.UndoMenu(self, craftUndo, function(u)
                if #u == 1 then
                    local rec = ns.FindRecipe and ns.FindRecipe(u[1].spell)
                    return rec and ns.RecipeName(rec) or "Recipe"
                end
                return ("%d recipes"):format(#u)
            end, ns.CraftUndo)
        end)
        craftWin.undo:Hide()
        -- Redo: the Undo arrow mirrored; only there after an Undo. Order in the header: undo, redo, remove all
        craftWin.redo = MiniButton(craftWin.head, 14, "Interface\\Buttons\\UI-RefreshButton", nil, function()
            return ("Redo remove (%d)"):format(craftWin.redo.steps or 0)
        end)
        craftWin.redo:GetRegions():SetTexCoord(1, 0, 0, 1)
        craftWin.redo:SetAlpha(0.9)
        craftWin.redo:SetPoint("RIGHT", clear, "LEFT", -3, 0)
        craftWin.redo:SetScript("OnClick", function()
            ns.CraftRedo()
        end)
        craftWin.redo:Hide()
        function craftWin.PlaceUndo(steps)
            craftWin.redo.steps = steps
            craftWin.redo:SetShown(steps > 0)
            craftWin.undo:ClearAllPoints()
            craftWin.undo:SetPoint("RIGHT", steps > 0 and craftWin.redo or clear, "LEFT", -3, 0)
        end
        craftWin.progress = craftWin.head:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        craftWin.progress:SetPoint("TOPLEFT", 35, craftWin.styled and -6 or -9)
        craftWin.progress:SetDrawLayer("OVERLAY", 7)
        local line = craftWin:CreateTexture(nil, "ARTWORK")
        line:SetPoint("TOPLEFT", 8 + PAD_IN, -HEAD_H)
        line:SetPoint("TOPRIGHT", -8 - PAD_IN, -HEAD_H)
        line:SetHeight(1)
        line:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], 0.35)
        craftWin.rows = {}
        -- All / Ready to Craft tabs (same look as the Items / Recipes tabs of the Farming window)
        local bar = CreateFrame("Frame", nil, craftWin)
        bar:SetHeight(20)
        bar:SetPoint("TOPLEFT", 8 + PAD_IN, -(HEAD_H + 3))
        bar:SetPoint("TOPRIGHT", -8 - PAD_IN, -(HEAD_H + 3))
        local function ViewButton(label, value, left, tip)
            local b = CreateFrame("Button", nil, bar)
            if left then
                b:SetPoint("TOPLEFT")
                b:SetPoint("BOTTOMRIGHT", bar, "BOTTOM", -1, 0)
            else
                b:SetPoint("TOPRIGHT")
                b:SetPoint("BOTTOMLEFT", bar, "BOTTOM", 1, 0)
            end
            b.value = value
            b.bg = b:CreateTexture(nil, "BACKGROUND")
            b.bg:SetAllPoints()
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 0.82, 0, 0.12)
            ns.TabBorder(b)
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.text:SetPoint("CENTER")
            b.text:SetText(label)
            b:SetScript("OnClick", function()
                CraftDB().craftTracker.view = value
                craftWin.scroll:SetVerticalScroll(0)
                UpdateCraftWin()
            end)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(label)
                GameTooltip:AddLine(tip, 0.9, 0.9, 0.9, true)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", GameTooltip_Hide)
            return b
        end
        craftWin.viewAll = ViewButton("All", "all", true, "Every tracked recipe")
        craftWin.viewReady = ViewButton("Ready to Craft", "ready", false,
            "Only the recipes you know and have the materials for")
        craftWin.empty = craftWin.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        craftWin.empty:SetPoint("TOPLEFT", PAD_IN + 10, -8)
        craftWin:SetScript("OnShow", UpdateCraftWin)
        -- requirements depend on where you stand (a fire or anvil nearby): re-check once a second
        local since = 0
        craftWin:SetScript("OnUpdate", function(_, dt)
            since = since + dt
            if since >= 1 then
                since = 0
                UpdateCraftWin()
            end
        end)
    end
    d.craftTracker.shown = true
    craftWin:Show()
    UpdateCraftWin()
end

function ns.ToggleCraftTracker()
    if craftWin and craftWin:IsShown() then
        ns.ShowCraftTracker(false)
    elseif #CraftDB().craftList == 0 then
        ns.Print("No recipes tracked - tick Track on a recipe card first.")
    else
        ns.ShowCraftTracker()
    end
end

-- both tracker windows at once (minimap menu): opens them, or closes them when both are already open
function ns.ToggleTrackers()
    local farmOn = tracker and tracker:IsShown()
    local craftOn = craftWin and craftWin:IsShown()
    if farmOn and craftOn then
        ns.ShowFarmTracker(false)
        ns.ShowCraftTracker(false)
        return
    end
    if #List() == 0 and #CraftDB().craftList == 0 then
        ns.Print("Nothing to show - the farming list is empty and no recipes are tracked.")
        return
    end
    ns.ShowFarmTracker()
    ns.ShowCraftTracker()
end

-- track again what the last removal (one recipe or Remove All) took away
function ns.CraftUndo()
    local u = table.remove(craftUndo) -- the most recent removal
    if not u then
        return
    end
    local list = CraftDB().craftList
    for _, x in ipairs(u) do
        if not ns.CraftTracked(x.spell) then
            table.insert(list, math.min(x.i, #list + 1), x.spell)
        end
    end
    craftRedo[#craftRedo + 1] = u
    UpdateCraftWin()
    if ns.RefreshReagents then
        ns.RefreshReagents()
    end
end

-- stop tracking again what the last Undo brought back
function ns.CraftRedo()
    local u = table.remove(craftRedo)
    if not u then
        return
    end
    local list = CraftDB().craftList
    for _, x in ipairs(u) do
        local i = ns.CraftTracked(x.spell)
        if i then
            table.remove(list, i)
        end
    end
    craftUndo[#craftUndo + 1] = u -- (not PushUndo: the rest of the redo list stays)
    UpdateCraftWin()
    if ns.RefreshReagents then
        ns.RefreshReagents()
    end
end

-- stop tracking every recipe (asks first)
function ns.CraftRemoveAll()
    local d = CraftDB()
    if #d.craftList == 0 then
        return
    end
    AskConfirm(("Stop tracking all %d recipes?"):format(#d.craftList), function()
        local undo = {}
        for i, spell in ipairs(d.craftList) do
            undo[i] = { spell = spell, i = i }
        end
        PushUndo(craftUndo, undo)
        for i = #d.craftList, 1, -1 do
            table.remove(d.craftList, i)
        end
        UpdateCraftWin()
        if ns.RefreshReagents then
            ns.RefreshReagents()
        end
    end)
end

-- start / stop tracking a recipe (Track box on the recipe cards, x in the tracker)
function ns.CraftTrack(spellID, on)
    local d = CraftDB()
    local i = ns.CraftTracked(spellID)
    if on and not i then
        table.insert(d.craftList, spellID)
        if ns.Get("craftAutoOpen") ~= false then
            ns.ShowCraftTracker()
        end
    elseif not on and i then
        PushUndo(craftUndo, { { spell = spellID, i = i } })
        table.remove(d.craftList, i)
    end
    UpdateCraftWin()
    if ns.RefreshReagents then
        ns.RefreshReagents() -- the Track boxes on the cards
    end
end

---------------------------------------------------------------------------
-- Docking the Farming and Crafting windows together. Drag one so an edge comes close to an edge of the
-- other: it snaps on and from then on the two move as one. A chain button sits on the shared edge,
-- centred on the smaller window; clicking it separates them again.
-- HelperDB.trackerDock = { child = "farm" | "craft", side = "LEFT" | "RIGHT" | "TOP" | "BOTTOM" }
--   (the child hangs on that side of the other window)
---------------------------------------------------------------------------
local dockBtns, dragging = {}, nil -- one chain button per window (see ApplyTrackerDock)
local SNAP = 30 -- how close two edges must be, in pixels, to snap together

local function TrackerWin(key)
    if key == "farm" then
        return tracker
    end
    return craftWin
end

local function OtherKey(key)
    return key == "farm" and "craft" or "farm"
end

-- pin a window where it is now (top-left fixed, so it grows downwards) and remember the place
local function SaveTrackerPos(key)
    local w = TrackerWin(key)
    local x, y = w and w:GetLeft(), w and w:GetTop()
    if not x or not y then
        return
    end
    w:ClearAllPoints()
    w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    if key == "farm" then
        db.farmTracker = db.farmTracker or {}
        db.farmTracker.pos = { "TOPLEFT", "BOTTOMLEFT", x, y }
    else
        CraftDB().craftTracker.pos = { x, y }
    end
end

local function Undock()
    local d = db and db.trackerDock
    if not d then
        return
    end
    db.trackerDock = nil
    local child = TrackerWin(d.child)
    if child and child:GetLeft() then
        -- stays where it is, moved a little away so it is clear the two are separate now
        local x, y = child:GetLeft(), child:GetTop()
        local dx = d.side == "LEFT" and -16 or d.side == "RIGHT" and 16 or 0
        local dy = d.side == "TOP" and 16 or d.side == "BOTTOM" and -16 or 0
        child:ClearAllPoints()
        child:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x + dx, y + dy)
        SaveTrackerPos(d.child)
    end
    for _, b in pairs(dockBtns) do
        b:Hide()
    end
end

function ns.ApplyTrackerDock()
    local d = db and db.trackerDock
    if d and ns.Get("trackerDocking") == false then
        Undock()
        return
    end
    local child = d and TrackerWin(d.child)
    local parent = d and TrackerWin(OtherKey(d.child))
    if not (child and parent and child:IsShown() and parent:IsShown()) then
        for _, b in pairs(dockBtns) do
            b:Hide()
        end
        return
    end
    child:ClearAllPoints()
    if d.side == "LEFT" then
        child:SetPoint("TOPRIGHT", parent, "TOPLEFT", -2, 0)
    elseif d.side == "RIGHT" then
        child:SetPoint("TOPLEFT", parent, "TOPRIGHT", 2, 0)
    elseif d.side == "BOTTOM" then
        child:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -2)
    else
        child:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", 0, 2)
    end
    -- The chain sits on the seam between the two windows. Each window carries its own copy of it, at the
    -- same spot: whichever window is in front draws its copy whole, so the chain is never half covered,
    -- and it stays on the windows' own layer (other windows cover it like they cover these two).
    local function ChainOn(win)
        local btn = dockBtns[win]
        if btn then
            return btn
        end
        btn = CreateFrame("Button", nil, win.head)
        btn:SetSize(22, 22)
        btn:SetFrameLevel(win.head:GetFrameLevel() + 5)
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask") -- round dark backing
        bg:SetVertexColor(0.05, 0.04, 0.03, 0.95)
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 3, -3)
        icon:SetPoint("BOTTOMRIGHT", -3, 3)
        if not icon:SetTexture(ns.Tex("Link")) then -- our chain icon needs a client restart to load
            icon:SetTexture("Interface\\FriendsFrame\\UI-FriendsFrame-Link")
        end
        icon:SetVertexColor(1, 0.82, 0)
        -- round gold border, the one minimap buttons (and the bag button) wear
        local ring = btn:CreateTexture(nil, "OVERLAY")
        ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        ring:SetSize(53, 53)
        ring:SetPoint("TOPLEFT", btn, "TOPLEFT", -5, 4)
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        hl:SetBlendMode("ADD")
        btn:SetScript("OnClick", Undock)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Windows Docked")
            GameTooltip:AddLine("The Farming and Crafting windows move together. Click to separate them", 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", GameTooltip_Hide)
        dockBtns[win] = btn
        return btn
    end
    -- on the shared edge, centred on the smaller of the two windows
    local sideways = d.side == "LEFT" or d.side == "RIGHT"
    local childSmaller
    if sideways then
        childSmaller = (child:GetHeight() or 0) <= (parent:GetHeight() or 0)
    else
        childSmaller = (child:GetWidth() or 0) <= (parent:GetWidth() or 0)
    end
    local OPP = { LEFT = "RIGHT", RIGHT = "LEFT", TOP = "BOTTOM", BOTTOM = "TOP" }
    for _, win in ipairs({ child, parent }) do
        local btn = ChainOn(win)
        -- centred on the middle of the 2px gap between the two windows, not on one window's edge
        local toParent = { LEFT = { 1, 0 }, RIGHT = { -1, 0 }, TOP = { 0, -1 }, BOTTOM = { 0, 1 } }
        local dx, dy = toParent[d.side][1], toParent[d.side][2]
        btn:ClearAllPoints()
        if childSmaller then
            btn:SetPoint("CENTER", child, OPP[d.side], dx, dy)
        else
            btn:SetPoint("CENTER", parent, d.side, -dx, -dy)
        end
        btn:Show()
    end
end

-- after a drag: does an edge of this window sit close enough to the other window to dock?
local function TrySnap(key)
    if ns.Get("trackerDocking") == false then
        return
    end
    local a, b = TrackerWin(key), TrackerWin(OtherKey(key))
    if not (a and b and a:IsShown() and b:IsShown() and a:GetLeft() and b:GetLeft()) then
        return
    end
    local sa, sb = a:GetScale(), b:GetScale() -- the windows can be resized separately: compare in one unit
    local al, ar, at, ab = a:GetLeft() * sa, a:GetRight() * sa, a:GetTop() * sa, a:GetBottom() * sa
    local bl, br, bt, bb = b:GetLeft() * sb, b:GetRight() * sb, b:GetTop() * sb, b:GetBottom() * sb
    local side
    if math.min(at, bt) - math.max(ab, bb) > 20 then -- side by side
        if math.abs(al - br) < SNAP then
            side = "RIGHT"
        elseif math.abs(ar - bl) < SNAP then
            side = "LEFT"
        end
    end
    if not side and math.min(ar, br) - math.max(al, bl) > 20 then -- one above the other
        if math.abs(at - bb) < SNAP then
            side = "BOTTOM"
        elseif math.abs(ab - bt) < SNAP then
            side = "TOP"
        end
    end
    if side then
        db.trackerDock = { child = key, side = side }
    end
end

-- drag handlers of both windows: a docked pair moves as one
function ns.TrackerDragStart(key)
    local d = db and db.trackerDock
    local other = TrackerWin(OtherKey(key))
    local mover = (d and d.child == key and other and other:IsShown()) and OtherKey(key) or key
    dragging = mover
    TrackerWin(mover):StartMoving()
end

function ns.TrackerDragStop(key)
    local mover = dragging or key
    dragging = nil
    local w = TrackerWin(mover)
    if w then
        w:StopMovingOrSizing()
        SaveTrackerPos(mover)
    end
    if not (db and db.trackerDock) then
        TrySnap(key)
    end
    ns.ApplyTrackerDock()
end

-- Blizzard's own "Track Recipe" tick box in the profession window also adds the recipe to the Crafting
-- window (and unticking it takes it off again)
local trackEvents = CreateFrame("Frame")
pcall(trackEvents.RegisterEvent, trackEvents, "TRACKED_RECIPE_UPDATE")
trackEvents:SetScript("OnEvent", function(_, _, recipeID, tracked)
    if type(recipeID) ~= "number" or not (db or HelperDB) then
        return
    end
    if tracked and not CraftRecipeOf(recipeID) then
        return -- a recipe the addon has no data for
    end
    if (ns.CraftTracked(recipeID) ~= nil) ~= (tracked and true or false) then
        ns.CraftTrack(recipeID, tracked and true or false)
    end
end)

---------------------------------------------------------------------------
-- Vendor prompt: when a vendor sells something you still need for the Farming list or for a tracked
-- recipe, a small window offers to buy it - tick what you want, change the amounts (default: what is missing).
---------------------------------------------------------------------------
local buyWin
local vendorOpen = false
local BUY_W, BUY_ROW = 380, 28

local function MerchantInfo(i)
    local price, stack, avail
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = Safe(C_MerchantFrame.GetItemInfo, i)
        if type(info) == "table" then
            price, stack, avail = info.price, info.stackCount, info.numAvailable
        end
    elseif GetMerchantItemInfo then
        local ok, _, _, p, q, a = pcall(GetMerchantItemInfo, i)
        if ok then
            price, stack, avail = p, q, a
        end
    end
    return tonumber(price) or 0, math.max(tonumber(stack) or 1, 1), tonumber(avail) or -1
end

-- { index, id, need, each (price per item), stack (items per purchase), limit, qty, on } for every vendor
-- item still missing from the Farming list or from the materials of a tracked recipe
local function VendorOffers()
    -- total wanted per item: farming targets, plus the materials of farming goals you can craft (the
    -- sub-rows of the tracker, e.g. the vials for a potion), and the materials of tracked recipes
    local farmReq, craftReq = {}, {}
    for _, e in ipairs(List()) do
        farmReq[e.id] = (farmReq[e.id] or 0) + e.target
        local h = ns.Have(e.id)
        local recipe = h < e.target and CraftRecipe(e.id)
        if recipe then
            local crafts = math.ceil((e.target - h) / math.max(recipe.count or 1, 1))
            for _, rg in ipairs(recipe.reagents) do
                farmReq[rg[1]] = (farmReq[rg[1]] or 0) + rg[2] * crafts
            end
        end
    end
    for _, spell in ipairs(CraftDB().craftList) do
        local rec = CraftRecipeOf(spell)
        for _, rg in ipairs(rec and rec.reagents or {}) do
            craftReq[rg[1]] = math.max(craftReq[rg[1]] or 0, rg[2])
        end
    end
    local need = {}
    for _, t in ipairs({ farmReq, craftReq }) do
        for id, want in pairs(t) do
            local missing = want - ns.Have(id)
            if missing > 0 then
                need[id] = math.max(need[id] or 0, missing)
            end
        end
    end
    local offers, seen = {}, {}
    local trace = { t = time(), need = {}, sold = {}, api = (GetMerchantNumItems and GetMerchantItemID) and true or false }
    for id, n in pairs(need) do
        trace.need[#trace.need + 1] = id .. "x" .. n
    end
    db.vendorTrace = db.vendorTrace or {}
    table.insert(db.vendorTrace, trace)
    while #db.vendorTrace > 6 do
        table.remove(db.vendorTrace, 1)
    end
    if not (GetMerchantNumItems and GetMerchantItemID) or not next(need) then
        return offers
    end
    trace.count = GetMerchantNumItems()
    for i = 1, GetMerchantNumItems() do
        local id = GetMerchantItemID(i)
        if #trace.sold < 60 then
            local _, st, av = MerchantInfo(i)
            trace.sold[#trace.sold + 1] = tostring(id) .. ":" .. st .. ":" .. av
        end
        if id and need[id] and not seen[id] then
            seen[id] = true
            local price, stack, avail = MerchantInfo(i)
            local limit = avail >= 0 and avail * stack or nil -- limited stock
            local qty = math.ceil(need[id] / stack) * stack
            if limit then
                qty = math.min(qty, limit)
            end
            if qty > 0 then
                offers[#offers + 1] = { index = i, id = id, need = need[id], each = price / stack, stack = stack,
                    limit = limit, qty = qty, on = true }
            end
        end
    end
    return offers
end

local function BuyTotals()
    local total, n = 0, 0
    for _, o in ipairs(buyWin.offers) do
        if o.on and o.qty > 0 then
            total = total + o.each * o.qty
            n = n + 1
        end
    end
    local money = GetMoney and GetMoney() or math.huge
    buyWin.total:SetText("Total  " .. (total > money and "|cffff4040" or "") .. Money(total))
    buyWin.buy:SetEnabled(n > 0 and total <= money)
end

local function BuyRow(i)
    local r = buyWin.rows[i]
    if r then
        return r
    end
    r = CreateFrame("Frame", nil, buyWin)
    r:SetSize(BUY_W, BUY_ROW)
    r:EnableMouse(true)
    local ok, check = pcall(CreateFrame, "CheckButton", nil, r, "UICheckButtonTemplate")
    if not ok or not check then
        check = CreateFrame("CheckButton", nil, r)
    end
    check:SetSize(22, 22)
    check:SetPoint("LEFT", 10, 0)
    check:SetScript("OnClick", function(self)
        r.offer.on = self:GetChecked() and true or false
        BuyTotals()
    end)
    r.check = check
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(20, 20)
    r.icon:SetPoint("LEFT", check, "RIGHT", 2, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.cost = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.cost:SetPoint("RIGHT", -12, 0)
    r.cost:SetWidth(84)
    r.cost:SetJustifyH("RIGHT")
    r.box = ns.CreateEditBox(r)
    r.box:SetSize(44, 20)
    r.box:SetPoint("RIGHT", r.cost, "LEFT", -6, 0)
    r.box:SetNumeric(true)
    r.box:SetMaxLetters(4)
    r.box:SetJustifyH("CENTER")
    r.box:SetScript("OnTextChanged", function(self)
        local o = r.offer
        if not o then
            return
        end
        local n = tonumber(self:GetText()) or 0
        if o.limit then
            n = math.min(n, o.limit)
        end
        o.qty = n
        r.cost:SetText(Money(o.each * n))
        BuyTotals()
    end)
    r.box:SetScript("OnEnterPressed", r.box.ClearFocus)
    r.box:SetScript("OnEscapePressed", r.box.ClearFocus)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.name:SetPoint("RIGHT", r.box, "LEFT", -8, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r:SetScript("OnEnter", function(self)
        local o = self.offer
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if not pcall(GameTooltip.SetItemByID, GameTooltip, o.id) then
            GameTooltip:SetText(ns.ItemName(o.id))
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(("Missing: %d"):format(o.need), 1, 0.82, 0)
        if o.stack > 1 then
            GameTooltip:AddLine(("Sold in lots of %d"):format(o.stack), 0.8, 0.8, 0.8)
        end
        if o.limit then
            GameTooltip:AddLine(("Only %d in stock"):format(o.limit), 1, 0.4, 0.4)
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    buyWin.rows[i] = r
    return r
end

local function BuyChosen()
    local queue = {}
    for _, o in ipairs(buyWin.offers) do
        if o.on and o.qty > 0 then
            local left = math.ceil(o.qty / o.stack) * o.stack -- whole lots only
            local maxStack = math.max(tonumber(Safe(GetMerchantItemMaxStack, o.index)) or o.stack, o.stack)
            while left > 0 do
                local q = math.min(left, maxStack)
                queue[#queue + 1] = { o.index, q, o.id }
                left = left - q
            end
        end
    end
    buyWin:Hide()
    local i = 0
    local function Step() -- one purchase per tick, so the server keeps up
        i = i + 1
        local q = queue[i]
        if not q or not vendorOpen then
            return
        end
        if GetMerchantItemID(q[1]) == q[3] then
            pcall(BuyMerchantItem, q[1], q[2])
        end
        C_Timer.After(0.15, Step)
    end
    Step()
end

local function ShowBuyPrompt()
    if not vendorOpen or ns.Get("vendorPrompt") == false or not db then
        return
    end
    local offers = VendorOffers()
    local trace = db.vendorTrace and db.vendorTrace[#db.vendorTrace]
    if trace then
        trace.offers = #offers
    end
    if #offers == 0 then
        if buyWin then
            buyWin:Hide()
        end
        return
    end
    if not buyWin then
        buyWin = PanelFrame("GristForTheMillBuy", "Buy Reagents", function()
            buyWin:Hide()
        end)
        buyWin:SetWidth(BUY_W)
        buyWin:SetFrameStrata("DIALOG") -- above the tracker windows, which may sit right beside the vendor
        buyWin:SetToplevel(true)
        buyWin:SetClampedToScreen(true)
        buyWin:SetMovable(true)
        buyWin:EnableMouse(true)
        buyWin:RegisterForDrag("LeftButton")
        buyWin:SetScript("OnDragStart", buyWin.StartMoving)
        buyWin:SetScript("OnDragStop", buyWin.StopMovingOrSizing)
        buyWin.rows = {}
        local note = buyWin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        note:SetPoint("TOPLEFT", 14, -(HEAD_H + 6))
        note:SetPoint("RIGHT", -14, 0)
        note:SetJustifyH("LEFT")
        note:SetTextColor(0.75, 0.75, 0.75)
        note:SetText("This vendor sells items you still need for farming or crafting.")
        buyWin.total = buyWin:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        buyWin.total:SetPoint("BOTTOMLEFT", 14, 16)
        buyWin.buy = ns.CreateButton(buyWin, "Buy", 90)
        buyWin.buy:SetPoint("BOTTOMRIGHT", -12, 10)
        buyWin.buy:SetScript("OnClick", BuyChosen)
        local skip = ns.CreateButton(buyWin, "Not Now", 90)
        skip:SetPoint("RIGHT", buyWin.buy, "LEFT", -6, 0)
        skip:SetScript("OnClick", function()
            buyWin:Hide()
        end)
    end
    buyWin.offers = offers
    local y = HEAD_H + 28
    for i, o in ipairs(offers) do
        local r = BuyRow(i)
        r.offer = o
        r.check:SetChecked(true)
        r.icon:SetTexture(ItemIconPath(o.id))
        r.name:SetText(ns.QualityColor(o.id) .. ns.ItemName(o.id) .. "|r")
        r.box:SetText(tostring(o.qty))
        r.cost:SetText(Money(o.each * o.qty))
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -y)
        r:Show()
        y = y + BUY_ROW
    end
    for i = #offers + 1, #buyWin.rows do
        buyWin.rows[i]:Hide()
    end
    buyWin:SetHeight(y + 46)
    buyWin:ClearAllPoints()
    if MerchantFrame and MerchantFrame:IsShown() and MerchantFrame:GetRight() then
        buyWin:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 12, 0)
    else
        buyWin:SetPoint("CENTER", 0, 80)
    end
    buyWin:Show()
    buyWin:Raise()
    BuyTotals()
    if trace then
        trace.shown = buyWin:IsVisible() and true or false
        trace.at = ("%d,%d %dx%d"):format(buyWin:GetLeft() or -1, buyWin:GetTop() or -1, buyWin:GetWidth() or -1,
            buyWin:GetHeight() or -1)
    end
    return true
end

local vendorEvents = CreateFrame("Frame")
pcall(vendorEvents.RegisterEvent, vendorEvents, "MERCHANT_SHOW")
pcall(vendorEvents.RegisterEvent, vendorEvents, "MERCHANT_CLOSED")
pcall(vendorEvents.RegisterEvent, vendorEvents, "MERCHANT_UPDATE")
local visit, prompted = 0, false -- this vendor visit; whether the prompt has already been shown during it
-- The vendor's item list is not always ready when the window opens (items the client has not seen yet
-- come in a moment later), so the check is repeated a few times and on every list update, until the
-- prompt has been shown once for this visit.
local function TryPrompt(v)
    if db then
        db.vendorCalls = (db.vendorCalls or 0) + 1
        db.vendorState = ("visit=%s v=%s prompted=%s open=%s setting=%s"):format(tostring(visit), tostring(v),
            tostring(prompted), tostring(vendorOpen), tostring(ns.Get("vendorPrompt")))
    end
    if v ~= visit or prompted or not vendorOpen then
        return
    end
    local ok, shown = pcall(ShowBuyPrompt)
    if not ok then
        if geterrorhandler then
            geterrorhandler()(shown)
        end
    elseif shown then
        prompted = true
    end
end
vendorEvents:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_UPDATE" then
        TryPrompt(visit)
        return
    end
    vendorOpen = event == "MERCHANT_SHOW"
    if vendorOpen then
        visit = visit + 1
        prompted = false
        local v = visit
        for _, delay in ipairs({ 0.3, 1, 2, 4 }) do
            C_Timer.After(delay, function()
                TryPrompt(v)
            end)
        end
    elseif buyWin then
        buyWin:Hide()
    end
end)
