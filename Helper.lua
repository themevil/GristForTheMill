local FOLDER_NAME, ns = ...
local ADDON_NAME = "Grist for the Mill" -- display name

local MAX_ERRORS = 50
-- addon icon: Blizzard's own reagent-pouch art (portrait, minimap button, profession-window button)
local ICON_ROUND = "Interface\\Icons\\INV_Misc_Bag_10"

local db, mainFrame
local panels = {}

ns.ADDON_NAME = ADDON_NAME
ns.FOLDER_NAME = FOLDER_NAME
ns.PLUS = "|TInterface\\Buttons\\UI-PlusButton-Up:14:14|t "
ns.MINUS = "|TInterface\\Buttons\\UI-MinusButton-Up:14:14|t "

function ns.Escape(s)
    return (tostring(s):gsub("|", "||"))
end

-- money with Blizzard coin icons: "1 [gold] 20 [silver] 5 [copper]" (zero parts left out)
function ns.Money(c, size)
    c = math.floor(c or 0)
    size = size or 12
    local function part(n, coin)
        return ("%d|TInterface\\MoneyFrame\\UI-%sIcon:%d:%d:2:0|t"):format(n, coin, size, size)
    end
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local out = {}
    if g > 0 then
        out[#out + 1] = part(g, "Gold")
    end
    if s > 0 then
        out[#out + 1] = part(s, "Silver")
    end
    if cp > 0 or #out == 0 then
        out[#out + 1] = part(cp, "Copper")
    end
    return table.concat(out, " ")
end

function ns.Print(msg)
    print("|cff33ff99" .. ADDON_NAME .. "|r: " .. msg)
end

---------------------------------------------------------------------------
-- Theme: rounded dark cards (9-slice textures), soft shadows, gold accent
---------------------------------------------------------------------------
local WHITE = "Interface\\Buttons\\WHITE8X8"
local MEDIA = "Interface\\AddOns\\GristForTheMill\\Media\\"
local T = {
    bg = { 0.043, 0.05, 0.066, 0.97 },
    bgTop = { 0.075, 0.084, 0.108, 0.97 },
    panel = { 0.071, 0.082, 0.106, 1 },
    raised = { 0.106, 0.12, 0.152, 1 },
    raisedTop = { 0.128, 0.144, 0.18, 1 },
    hover = { 0.15, 0.17, 0.215, 1 },
    border = { 0.17, 0.19, 0.235, 1 },
    accent = { 0.95, 0.75, 0.3, 1 },
    onAccent = { 0.1, 0.08, 0.04, 1 },
    text = { 0.92, 0.93, 0.95, 1 },
    dim = { 0.55, 0.58, 0.64, 1 },
    off = { 0.35, 0.37, 0.42, 1 },
}
ns.T = T
ns.WHITE = WHITE
ns.MEDIA = MEDIA

local function Color(c)
    return CreateColor and CreateColor(c[1], c[2], c[3], c[4] or 1)
end

local function SliceTexture(f, layer, sub, file, margin)
    local t = f:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(file)
    t:SetTextureSliceMargins(margin, margin, margin, margin)
    if t.SetTextureSliceMode then
        t:SetTextureSliceMode(Enum and Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched or 0)
    end
    t:SetAllPoints()
    return t
end

local canSlice -- client supports 9-slice textures (rounded corners)

-- background + 1px border. radius 4 / 8 / 12 (rounded) or 0 (square backdrop).
-- Keeps the backdrop API (SetBackdropColor / SetBackdropBorderColor) either way.
function ns.Skin(f, bg, border, radius)
    radius = radius or 8
    if canSlice == nil then
        local probe = UIParent:CreateTexture()
        canSlice = probe.SetTextureSliceMargins ~= nil
        probe:Hide()
    end
    if radius > 0 and canSlice then
        if not f.rbg then
            local file = radius <= 4 and "Round4" or radius <= 8 and "Round8" or "Round12"
            local margin = (radius <= 4 and 4 or radius <= 8 and 8 or 12) + 1
            f.rbg = SliceTexture(f, "BACKGROUND", -6, ns.Tex(file), margin)
            f.rbd = SliceTexture(f, "BORDER", -6, ns.Tex(file .. "Border"), margin)
            f.SetBackdropColor = function(self, r, g, b, a)
                self.rbg:SetVertexColor(r, g, b, a or 1)
            end
            f.SetBackdropBorderColor = function(self, r, g, b, a)
                self.rbd:SetVertexColor(r, g, b, a or 1)
            end
        end
        f:SetBackdropColor(unpack(bg or T.panel))
        f:SetBackdropBorderColor(unpack(border or T.border))
        return
    end
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(unpack(bg or T.panel))
    f:SetBackdropBorderColor(unpack(border or T.border))
end

-- vertical gradient on a skinned frame's background (top -> bottom)
function ns.SkinGradient(f, top, bottom)
    local tex = f.rbg
    if tex and CreateColor then
        pcall(tex.SetGradient, tex, "VERTICAL", Color(bottom), Color(top))
    end
end

function ns.Card(parent, bg, radius)
    local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    ns.Skin(c, bg or T.raised, T.border, radius or 8)
    if not bg or bg == T.raised then
        ns.SkinGradient(c, T.raisedTop, T.raised)
    end
    return c
end

function ns.Gradient(tex, orient, c1, c2)
    tex:SetTexture(WHITE)
    if CreateColor and pcall(tex.SetGradient, tex, orient, Color(c1), Color(c2)) then
        return
    end
    tex:SetVertexColor(unpack(c1))
end

-- soft drop shadow around a frame
function ns.Shadow(f, spread)
    spread = spread or 24
    local t = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    t:SetTexture(ns.Tex("Shadow"))
    if t.SetTextureSliceMargins then
        t:SetTextureSliceMargins(40, 40, 40, 40)
        if t.SetTextureSliceMode then
            t:SetTextureSliceMode(Enum and Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched or 0)
        end
    end
    t:SetPoint("TOPLEFT", -spread, spread - 4)
    t:SetPoint("BOTTOMRIGHT", spread, -spread - 4)
    t:SetVertexColor(0, 0, 0, 0.9)
    return t
end

-- title bar decoration: thin top highlight, accent line fading out, used by the window and the map
function ns.TitleBar(f, height)
    local hl = f:CreateTexture(nil, "ARTWORK")
    hl:SetPoint("TOPLEFT", 14, -1)
    hl:SetPoint("TOPRIGHT", -14, -1)
    hl:SetHeight(1)
    hl:SetColorTexture(1, 1, 1, 0.07)
    local glow = f:CreateTexture(nil, "ARTWORK")
    glow:SetPoint("TOPLEFT", 14, -height)
    glow:SetPoint("TOPRIGHT", -14, -height)
    glow:SetHeight(1)
    ns.Gradient(glow, "HORIZONTAL", T.accent, { T.accent[1], T.accent[2], T.accent[3], 0 })
    local haze = f:CreateTexture(nil, "BORDER")
    haze:SetPoint("TOPLEFT", 14, -height + 24)
    haze:SetPoint("TOPRIGHT", -14, -height + 24)
    haze:SetHeight(24)
    ns.Gradient(haze, "VERTICAL", { T.accent[1], T.accent[2], T.accent[3], 0.05 }, { T.accent[1], T.accent[2], T.accent[3], 0 })
end

---------------------------------------------------------------------------
-- Blizzard profession-window art: category header bars, collapse icons and panel backgrounds use the
-- same atlases as the profession window when the client has them (own textures otherwise).
---------------------------------------------------------------------------
local function AtlasOK(name)
    return name ~= nil and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end
ns.AtlasOK = AtlasOK

-- Category bar: the profession list's own header texture. It is one image with the collapse sign
-- baked in at the right end; the expanded / collapsed variants are read from the live profession list
-- (same atlas until both have been seen). "plain" bars (titles, toggles) crop the sign off.
local HEADER_ATLAS = "common-button-list-collapseExpand"
local mirrored = { header = {} } -- art read from the live profession window
ns.headerBars = {}

-- returns an object with :SetShown(bool) and :SetOpen(bool).
-- One texture showing the header atlas exactly as the profession list does (stretched to the bar).
function ns.HeaderBar(f)
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    local bar = { open = true }
    function bar.Refresh()
        local live = mirrored.header.open or mirrored.header.closed
        local atlas = live and live.atlas or HEADER_ATLAS
        if AtlasOK(atlas) then
            t:SetAtlas(atlas)
        else
            t:SetTexture(ns.Tex("Header"))
            if t.SetTextureSliceMargins then
                t:SetTextureSliceMargins(6, 6, 6, 6)
            end
        end
    end
    function bar.SetOpen(self, open)
        self.open = open and true or false
    end
    function bar.SetShown(_, shown)
        t:SetShown(shown)
    end
    bar.Refresh()
    table.insert(ns.headerBars, bar)
    return bar
end

-- "-" / "+" sign of a category bar
function ns.SignText(open)
    return open and "-" or "+"
end

-- fonts of the profession list
ns.HEADER_FONT = _G.GameFontNormalMed3 and "GameFontNormalMed3" or "GameFontNormal"

-- row art of the profession list: selected and hover
function ns.RowArt(tex, kind)
    local atlas = kind == "selected" and "Professions_Recipe_Active" or "Professions_Recipe_Hover"
    if AtlasOK(atlas) then
        tex:SetAtlas(atlas)
        tex:SetBlendMode(kind == "selected" and "BLEND" or "ADD")
        return true
    end
end

-- panel backgrounds: every ns.Card gets the profession window's panel art
local LIST_BG = "Professions-background-summarylist"
local DETAIL_BG = "Profession-background-card-Engineering"
ns.styleCards = {}

local function ApplyCardArt(c)
    if not c.art then
        return
    end
    local atlas = c.styleKind == "detail" and (mirrored.detail or DETAIL_BG) or mirrored.list or LIST_BG
    if atlas and AtlasOK(atlas) then
        c.art:SetAtlas(atlas)
        c.art:Show()
        c.wash:Hide()
    else
        c.art:Hide()
        c.wash:Show()
    end
end

function ns.StyleCard(c)
    c.wash = c:CreateTexture(nil, "BACKGROUND", nil, 2)
    c.wash:SetPoint("TOPLEFT", 3, -3)
    c.wash:SetPoint("BOTTOMRIGHT", -3, 3)
    ns.Gradient(c.wash, "VERTICAL", { 0.10, 0.07, 0.04, 0.75 }, { 0.20, 0.15, 0.09, 0.75 })
    c.art = c:CreateTexture(nil, "BACKGROUND", nil, 3)
    c.art:SetPoint("TOPLEFT", 3, -3)
    c.art:SetPoint("BOTTOMRIGHT", -3, 3)
    c.inside = c:CreateTexture(nil, "BORDER")
    c.inside:SetAllPoints(c.art)
    if AtlasOK("common-insideframe") then
        c.inside:SetAtlas("common-insideframe")
    end
    c.inside:Hide()
    table.insert(ns.styleCards, c)
    ApplyCardArt(c)
end

function ns.SetCardKind(c, kind)
    c.styleKind = kind
    if c.inside then
        c.inside:SetShown(kind == "detail" and AtlasOK("common-insideframe"))
    end
    ApplyCardArt(c)
end

local function Describe(reg)
    local layer, sub = "", 0
    if reg.GetDrawLayer then
        layer, sub = reg:GetDrawLayer()
    end
    local w, h = reg:GetSize()
    return ("%s layer=%s/%s atlas=%s tex=%s size=%.0fx%.0f shown=%s key=%s"):format(reg:GetObjectType(), tostring(layer),
        tostring(sub), tostring(reg.GetAtlas and reg:GetAtlas()), tostring(reg.GetTexture and reg:GetTexture()), w or 0,
        h or 0, tostring(reg:IsShown()), tostring(reg.GetDebugName and reg:GetDebugName()))
end

-- read the look of the live profession window: panel atlases now, plus a description of its side
-- tabs and category bars saved to HelperDB.styleDump (for matching the art exactly)
function ns.MirrorProfStyle(fr, sideTab, tabCount)
    local cp = fr.CraftingPage
    local list = cp and cp.RecipeList
    local form = cp and cp.SchematicForm
    local function AtlasOf(t)
        return t and t.GetAtlas and t:GetAtlas() or nil
    end
    mirrored.list = AtlasOf(list and list.Background) or mirrored.list
    mirrored.detail = AtlasOf(form and form.Background) or mirrored.detail
    for _, c in ipairs(ns.styleCards) do
        ApplyCardArt(c)
    end
    -- category bar art, expanded and collapsed, from the list's header rows
    if list and list.ScrollBox and list.ScrollBox.GetFrames then
        for _, row in ipairs(list.ScrollBox:GetFrames() or {}) do
            local reg = row.GetObjectType and row:GetObjectType() == "Button" and row:GetRegions()
            for _, x in ipairs(reg and { row:GetRegions() } or {}) do
                if x:GetObjectType() == "Texture" and x:GetDrawLayer() == "ARTWORK" and x:GetAtlas()
                    and x:GetAtlas():find("collapse") then
                    local node = row.GetElementData and row:GetElementData()
                    local closed = node and node.IsCollapsed and node:IsCollapsed()
                    mirrored.header[closed and "closed" or "open"] = { file = x:GetTexture(), coords = { x:GetTexCoord() },
                        atlas = x:GetAtlas() }
                end
            end
        end
        for _, bar in ipairs(ns.headerBars) do
            bar:Refresh()
        end
    end
    if HelperDB then
        local out = { "frame=" .. tostring(fr:GetName()), "listBg=" .. tostring(mirrored.list),
            "detailBg=" .. tostring(mirrored.detail), "headerAtlas=" .. tostring(AtlasOK(HEADER_ATLAS)),
            "sideTabsFound=" .. tostring(tabCount),
            "headerOpen=" .. tostring(mirrored.header.open and mirrored.header.open.atlas),
            "headerClosed=" .. tostring(mirrored.header.closed and mirrored.header.closed.atlas) }
        local function Dump(label, f, depth)
            if not f or #out > 150 then
                return
            end
            local w, h = f:GetSize()
            out[#out + 1] = ("%s: %s %.0fx%.0f template=%s"):format(label, f:GetObjectType(), w or 0, h or 0,
                tostring(f.GetDebugName and f:GetDebugName()))
            for _, reg in ipairs({ f:GetRegions() }) do
                out[#out + 1] = "   " .. Describe(reg)
            end
            if (depth or 0) > 0 then
                for i, child in ipairs({ f:GetChildren() }) do
                    if i <= 4 then
                        Dump(label .. "." .. i, child, depth - 1)
                    end
                end
            end
        end
        pcall(Dump, "sideTab", sideTab, 1)
        if list and list.ScrollBox and list.ScrollBox.GetFrames then
            local n = 0
            for _, row in ipairs(list.ScrollBox:GetFrames() or {}) do
                if n < 3 then
                    n = n + 1
                    pcall(Dump, "listRow" .. n, row, 0)
                end
            end
        end
        pcall(Dump, "recipeList", list, 0)
        pcall(Dump, "schematic", form, 0)
        pcall(Dump, "frame", fr, 0)
        HelperDB.styleDump = out
    end
end

---------------------------------------------------------------------------
-- Scrolling text with clickable |Haddon:Helper:...|h links. Text starts at the
-- top; SetLines keeps the scroll position unless toTop is true.
---------------------------------------------------------------------------
function ns.CreateScrollText(parent, onLink, onEnter)
    -- modern slim scrollbar when the client has it, classic one otherwise
    local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, parent, "ScrollFrameTemplate")
    if not ok or not scroll or not scroll.ScrollBar then
        scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    end
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)

    local text = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT")
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetSpacing(3)
    text:SetTextColor(unpack(T.text))

    child:SetHyperlinksEnabled(true)
    child:SetScript("OnHyperlinkClick", function(_, link, linkText, button)
        if onLink then
            onLink(link, linkText, button)
        end
    end)
    if onEnter then
        child:SetScript("OnHyperlinkEnter", function(self, link)
            onEnter(self, link)
        end)
        child:SetScript("OnHyperlinkLeave", function()
            GameTooltip:Hide()
        end)
    end

    -- block layout (used when lines contain tables): plain strings flow as text runs; cards get a
    -- background, padding and per-line FontStrings with a lead column and fixed right-aligned slots.
    --   { card = true, x = indent, bg = rgba, bg2 = rgba (gradient bottom), border = rgba, accent = rgba|nil,
    --     padL = n, padR = n, padV = n, gap = n }                                   -- begin card
    --   { cardEnd = true }
    --   { text = s, lead = { s, w }, right = s | { { s, w, justify }, ... }, indent = n, gap = n,
    --     nowrap = bool, font = fontObject }                                         -- line
    --   { rule = true, indent = n, above = n, below = n }                            -- 1px divider
    --   { space = n }                                                                -- vertical space
    local fsPool, fsUsed = {}, 0
    local cardPool, cardUsed = {}, 0
    local rulePool, ruleUsed = {}, 0
    local slice = child:CreateTexture().SetTextureSliceMargins ~= nil

    local function FS(font)
        fsUsed = fsUsed + 1
        local fs = fsPool[fsUsed]
        if not fs then
            fs = child:CreateFontString(nil, "OVERLAY")
            fs:SetJustifyV("TOP")
            fsPool[fsUsed] = fs
        end
        fs:SetFontObject(font or "GameFontHighlight")
        fs:SetTextColor(unpack(T.text))
        fs:SetSpacing(3)
        fs:SetWordWrap(true)
        fs:ClearAllPoints()
        fs:Show()
        return fs
    end

    local function SliceTex(file, sub)
        local t = child:CreateTexture(nil, "BACKGROUND", nil, sub)
        t:SetTexture(ns.Tex(file))
        if slice then
            t:SetTextureSliceMargins(5, 5, 5, 5)
            if t.SetTextureSliceMode then
                t:SetTextureSliceMode(Enum and Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched or 0)
            end
        else
            t:SetTexture(WHITE)
        end
        return t
    end

    local function Card()
        cardUsed = cardUsed + 1
        local c = cardPool[cardUsed]
        if not c then
            c = { bg = SliceTex("Round4", 1), border = SliceTex("Round4Border", 2), accent = child:CreateTexture(nil, "BORDER") }
            c.accent:SetTexture(WHITE)
            cardPool[cardUsed] = c
        end
        return c
    end

    local function Rule()
        ruleUsed = ruleUsed + 1
        local r = rulePool[ruleUsed]
        if not r then
            r = child:CreateTexture(nil, "BORDER")
            r:SetTexture(WHITE)
            rulePool[ruleUsed] = r
        end
        r:ClearAllPoints()
        r:Show()
        return r
    end

    local function Paint(c, hover)
        local bg, bg2, bd = c.spec.bg or T.raised, c.spec.bg2, c.spec.border or T.border
        local d = hover and 0.04 or 0
        local top = { bg[1] + d, bg[2] + d, bg[3] + d, bg[4] or 1 }
        c.bg:SetVertexColor(1, 1, 1, 1)
        local graded = bg2 and CreateColor and pcall(c.bg.SetGradient, c.bg, "VERTICAL",
            CreateColor(bg2[1] + d, bg2[2] + d, bg2[3] + d, bg2[4] or 1), CreateColor(unpack(top)))
        if not graded then
            c.bg:SetVertexColor(unpack(top))
        end
        c.border:SetVertexColor(bd[1], bd[2], bd[3], hover and math.max((bd[4] or 1) * 0.5, 0.45) + 0.2 or (bd[4] or 1))
    end

    -- real-frame widgets: scroll:RegisterWidget(kind, create(parent) -> frame, update(frame, data, width) -> height)
    -- entry { widget = kind, data = d, x = indent, gap = n }; frames are pooled per kind
    local widgets, widgetUsed = {}, {}
    function scroll.RegisterWidget(_, kind, create, update)
        widgets[kind] = { create = create, update = update, pool = {} }
    end
    -- let a widget's own FontStrings use the same |H links as the text
    function scroll.LinkFrame(_, frame)
        frame:SetHyperlinksEnabled(true)
        frame:SetScript("OnHyperlinkClick", function(_, link, linkText, button)
            if onLink then
                onLink(link, linkText, button)
            end
        end)
        if onEnter then
            frame:SetScript("OnHyperlinkEnter", function(self, link)
                onEnter(self, link)
            end)
            frame:SetScript("OnHyperlinkLeave", function()
                GameTooltip:Hide()
            end)
        end
    end
    scroll.child = child

    -- sticky headers (scroll.stickyKind = widget kind): every header of that kind stays visible.
    -- Ones scrolled past dock at the top, ones further down dock at the bottom; clicking a docked
    -- header scrolls to its section.
    local stick, stickPool = {}, {}
    local function UpdateSticky()
        local wd = scroll.stickyKind and widgets[scroll.stickyKind]
        local used = 0
        for _, it in ipairs(stick) do
            it.frame:SetAlpha(1)
        end
        if wd and #stick > 0 and ns.Get("stickyHeaders") then
            local s, vh, w = scroll:GetVerticalScroll(), scroll:GetHeight(), scroll:GetWidth()
            local function Dock(item, point, offset, target)
                item.frame:SetAlpha(0) -- the real header hides while its docked copy shows (no double image)
                used = used + 1
                local f = stickPool[used]
                if not f then
                    f = wd.create(scroll)
                    f:SetFrameLevel(scroll:GetFrameLevel() + 20)
                    -- solid backing so the list never shows through or around the docked header
                    local back = f:CreateTexture(nil, "BACKGROUND", nil, -8)
                    back:SetAllPoints() -- exactly the header: the panel's own border stays visible
                    back:SetColorTexture(0.05, 0.04, 0.03, 1)
                    f:SetScript("OnClick", function(self)
                        scroll:SetVerticalScroll(math.max(math.min(self.target, scroll:GetVerticalScrollRange()), 0))
                    end)
                    stickPool[used] = f
                end
                f:ClearAllPoints()
                f:SetPoint(point .. "LEFT", scroll, point .. "LEFT", 0, offset)
                f:SetWidth(w)
                wd.update(f, item.data, w)
                f:SetHeight(item.h)
                f.target = target
                f:Show()
            end
            local before = {} -- height of the headers above each header (its slot when docked on top)
            local sum = 0
            for i, it in ipairs(stick) do
                before[i] = sum
                sum = sum + it.h
            end
            local topCount = 0
            for i, it in ipairs(stick) do
                if it.y - s < before[i] - 0.5 then
                    Dock(it, "TOP", -before[i], it.y - before[i])
                    topCount = i
                else
                    break
                end
            end
            local bottom = 0
            for i = #stick, topCount + 1, -1 do
                local it = stick[i]
                if it.y - s + it.h > vh - bottom + 0.5 then
                    Dock(it, "BOTTOM", bottom, it.y - before[i])
                    bottom = bottom + it.h
                else
                    break
                end
            end
        end
        for i = used + 1, #stickPool do
            stickPool[i]:Hide()
        end
    end
    scroll:HookScript("OnVerticalScroll", UpdateSticky)
    scroll:HookScript("OnSizeChanged", UpdateSticky)

    local hovered
    local function Layout(lines, w)
        text:Hide()
        hovered = nil
        fsUsed, cardUsed, ruleUsed = 0, 0, 0
        wipe(widgetUsed)
        wipe(stick)
        local y, run, card, cardTop = 0, {}, nil, 0
        local function FlushRun()
            if #run == 0 then
                return
            end
            local fs = FS()
            fs:SetPoint("TOPLEFT", 0, -y)
            fs:SetWidth(w)
            fs:SetJustifyH("LEFT")
            fs:SetText(table.concat(run, "\n"))
            y = y + fs:GetStringHeight() + 3
            run = {}
        end
        -- content box of the current card (or the whole width)
        local function Box()
            if not card then
                return 0, w
            end
            local x0 = (card.x or 0) + (card.padL or 8)
            return x0, w - (card.padR or 8)
        end
        for _, e in ipairs(lines) do
            if type(e) == "string" then
                if card then
                    e = { text = e }
                else
                    run[#run + 1] = e
                end
            end
            if type(e) == "table" then
                FlushRun()
                if e.card then
                    card, cardTop = e, y
                    y = y + (e.padV or 6)
                elseif e.cardEnd and card then
                    y = y + (card.padV or 6) - (card.lastGap or 0)
                    local c = Card()
                    c.spec, c.top, c.bottom = card, cardTop, y
                    for _, t in ipairs({ c.bg, c.border }) do
                        t:ClearAllPoints()
                        t:SetPoint("TOPLEFT", card.x or 0, -cardTop)
                        t:SetPoint("BOTTOMRIGHT", child, "TOPRIGHT", 0, -y)
                        t:Show()
                    end
                    Paint(c, false)
                    c.accent:ClearAllPoints()
                    c.accent:SetPoint("TOPLEFT", (card.x or 0) + 1, -cardTop - 1)
                    c.accent:SetPoint("BOTTOMLEFT", child, "TOPLEFT", (card.x or 0) + 1, -y + 1)
                    c.accent:SetWidth(3)
                    c.accent:SetVertexColor(unpack(card.accent or { 0, 0, 0, 0 }))
                    c.accent:SetShown(card.accent ~= nil)
                    y = y + (card.gap or 6)
                    card = nil
                elseif e.space then
                    y = y + e.space
                elseif e.widget and widgets[e.widget] then
                    local wd = widgets[e.widget]
                    local n = (widgetUsed[e.widget] or 0) + 1
                    widgetUsed[e.widget] = n
                    local f = wd.pool[n]
                    if not f then
                        f = wd.create(child)
                        wd.pool[n] = f
                    end
                    local x = e.x or 0
                    f:ClearAllPoints()
                    f:SetPoint("TOPLEFT", x, -y)
                    f:SetWidth(w - x)
                    f:Show()
                    local h = wd.update(f, e.data, w - x) or f:GetHeight()
                    f:SetHeight(h)
                    if e.widget == scroll.stickyKind then
                        stick[#stick + 1] = { y = y, h = h, data = e.data, frame = f }
                    end
                    y = y + h + (e.gap or 6)
                elseif e.rule then
                    local x0, x1 = Box()
                    y = y + (e.above or 3)
                    local r = Rule()
                    r:SetPoint("TOPLEFT", x0 + (e.indent or 0), -y)
                    r:SetPoint("TOPRIGHT", child, "TOPLEFT", x1, -y)
                    r:SetHeight(1)
                    r:SetVertexColor(unpack(e.color or { 1, 1, 1, 0.1 }))
                    y = y + 1 + (e.below or 5)
                    if card then
                        card.lastGap = 0
                    end
                else
                    local x0, x1 = Box()
                    local x = x0 + (e.indent or 0)
                    local h, right = 0, x1
                    -- right slots, laid out right to left; a plain string is one slot sized to fit
                    local slots = e.right
                    if type(slots) == "string" then
                        slots = slots ~= "" and { { slots } } or nil
                    end
                    for i = #(slots or {}), 1, -1 do
                        local s = slots[i]
                        local rf = FS(e.font)
                        rf:SetWordWrap(false)
                        rf:SetText(s[1] or "")
                        local sw = s[2]
                        if not sw then
                            rf:SetWidth(0)
                            sw = math.min((rf.GetUnboundedStringWidth or rf.GetStringWidth)(rf) + 2, (x1 - x) * 0.6)
                        end
                        rf:SetWidth(sw)
                        rf:SetJustifyH(s[3] or "RIGHT")
                        rf:SetPoint("TOPRIGHT", child, "TOPLEFT", right, -y)
                        if (s[1] or "") ~= "" then
                            h = math.max(h, rf:GetStringHeight())
                        end
                        right = right - sw - (s[4] or 6)
                    end
                    if e.lead then
                        local lf = FS(e.font)
                        lf:SetWordWrap(false)
                        lf:SetJustifyH("RIGHT")
                        lf:SetWidth(e.lead[2])
                        lf:SetText(e.lead[1])
                        lf:SetPoint("TOPLEFT", x, -y)
                        h = math.max(h, lf:GetStringHeight())
                        x = x + e.lead[2] + 8
                    end
                    if e.text and e.text ~= "" then
                        local fs = FS(e.font)
                        fs:SetJustifyH("LEFT")
                        fs:SetWordWrap(not e.nowrap)
                        fs:SetWidth(math.max(right - x - 4, 20))
                        fs:SetText(e.text)
                        fs:SetPoint("TOPLEFT", x, -y)
                        h = math.max(h, fs:GetStringHeight())
                    end
                    local gap = e.gap or 3
                    y = y + h + gap
                    if card then
                        card.lastGap = gap
                    end
                end
            end
        end
        FlushRun()
        for i = fsUsed + 1, #fsPool do
            fsPool[i]:Hide()
        end
        for i = cardUsed + 1, #cardPool do
            local c = cardPool[i]
            c.bg:Hide()
            c.border:Hide()
            c.accent:Hide()
        end
        for i = ruleUsed + 1, #rulePool do
            rulePool[i]:Hide()
        end
        for kind, wd in pairs(widgets) do
            for i = (widgetUsed[kind] or 0) + 1, #wd.pool do
                wd.pool[i]:Hide()
            end
        end
        return y
    end

    -- card hover: lighten the card under the cursor
    scroll:HookScript("OnUpdate", function(self)
        if cardUsed == 0 then
            return
        end
        local over
        if self:IsMouseOver() then
            local _, cy = GetCursorPosition()
            local top = child:GetTop()
            if top then
                local yy = top - cy / child:GetEffectiveScale()
                for i = 1, cardUsed do
                    local c = cardPool[i]
                    if yy >= c.top and yy <= c.bottom then
                        over = c
                        break
                    end
                end
            end
        end
        if over ~= hovered then
            if hovered then
                Paint(hovered, false)
            end
            if over then
                Paint(over, true)
            end
            hovered = over
        end
    end)

    function scroll.SetLines(self, lines, toTop)
        local prev = toTop and 0 or self:GetVerticalScroll()
        local w = self:GetWidth()
        child:SetWidth(w)
        local blocks = false
        for _, e in ipairs(lines) do
            if type(e) == "table" then
                blocks = true
                break
            end
        end
        if blocks then
            child:SetHeight(math.max(Layout(lines, w), 1))
        else
            if fsUsed > 0 or cardUsed > 0 or ruleUsed > 0 or next(widgetUsed) then
                Layout({}, w) -- hide pooled block regions
            end
            text:Show()
            text:SetWidth(w)
            text:SetText(table.concat(lines, "\n"))
            child:SetHeight(math.max(text:GetStringHeight(), 1))
        end
        self:UpdateScrollChildRect()
        self:SetVerticalScroll(math.min(prev, self:GetVerticalScrollRange()))
        UpdateSticky()
    end

    -- scrollbar only visible while scrolling (or hovering it); fades out after a moment
    local bar = scroll.ScrollBar
    if bar then
        bar:SetAlpha(0)
        local token = 0
        local function Reveal()
            token = token + 1
            local mine = token
            bar:SetAlpha(1)
            C_Timer.After(1.2, function()
                if mine == token and not bar:IsMouseOver() and not scroll.keepBar then
                    bar:SetAlpha(0)
                end
            end)
        end
        scroll:HookScript("OnVerticalScroll", Reveal)
        scroll:HookScript("OnMouseWheel", Reveal)
        bar:HookScript("OnEnter", Reveal)
        bar:HookScript("OnLeave", Reveal)
        if bar.HookScript then
            pcall(bar.HookScript, bar, "OnMouseDown", Reveal)
        end
    end

    return scroll
end

-- Blizzard look (matches the profession window): inset panels, red panel buttons, check buttons,
-- input boxes, side tabs with icons, and a row list with gold-bordered category bars.
local function Try(template, frameType, parent, name)
    local ok, f = pcall(CreateFrame, frameType or "Frame", name, parent, template)
    if ok and f then
        return f
    end
end

-- inset panel (dark stone, thin bevel)
function ns.Card(parent, bg, radius)
    local c = Try("InsetFrameTemplate", "Frame", parent)
    if c then
        ns.StyleCard(c) -- the profession window's panel background
        return c
    end
    c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    ns.Skin(c, bg or T.raised, T.border, radius or 8)
    return c
end

-- red panel button
function ns.CreateButton(parent, label, width)
    local own = ns.LayoutWidget("Button")
    if own then
        return own(parent, label, width)
    end
    local b = Try("UIPanelButtonTemplate", "Button", parent) or CreateFrame("Button", nil, parent)
    b:SetSize(width or 80, 22)
    b:SetText(label)
    return b
end

-- thin outline around a flat tab, so it reads as a tab; b:SetBorderColor(r, g, b, a) recolours it
function ns.TabBorder(b)
    local edges = {}
    for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = b:CreateTexture(nil, "BORDER")
        if i <= 2 then
            t:SetPoint(side .. "LEFT")
            t:SetPoint(side .. "RIGHT")
            t:SetHeight(1)
        else
            t:SetPoint("TOP" .. side)
            t:SetPoint("BOTTOM" .. side)
            t:SetWidth(1)
        end
        edges[i] = t
    end
    function b.SetBorderColor(_, r, g, bl, al)
        for _, t in ipairs(edges) do
            t:SetColorTexture(r, g, bl, al or 1)
        end
    end
    b:SetBorderColor(0.45, 0.36, 0.2, 0.9)
end

---------------------------------------------------------------------------
-- Find target: an arrow button / link that points at an NPC (vendor, mob, trainer) which is close by also
-- targets it and puts a star on it, in the same click.
-- Addons may not change your target or set raid icons themselves (the game blocks both); only a click on
-- a secure button running a macro can. So while the pointer is over such an arrow, an invisible secure
-- button lies on top of it: the click runs "/targetexact <name>" + "/tm 1", then sets the arrow as usual.
-- Not available in combat (secure buttons can't be set up then): the arrow just works as before.
---------------------------------------------------------------------------
do
    local NEAR = 150 -- yards: closer than this counts as "close by"
    local overlay

    local function Yards(map, x, y) -- distance to a spot on the map you are on (nil when elsewhere / unknown)
        if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos
            and CreateVector2D) or C_Map.GetBestMapForUnit("player") ~= map then
            return nil
        end
        local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
        if not ok or not pos then
            return nil
        end
        local ok1, _, a = pcall(C_Map.GetWorldPosFromMapPos, map, pos)
        local ok2, _, b = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x / 100, y / 100))
        if ok1 and ok2 and a and b then
            return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
        end
    end

    local function Disarm()
        if overlay and overlay:IsShown() and not InCombatLockdown() then
            overlay:Hide()
        end
    end

    -- owner: the arrow button (nil = an arrow inside a text, under the pointer). label: "Name",
    -- "Name - what for" or "Name <Title>". action: what the click does besides targeting (sets the arrow).
    -- Returns true when the secure button took the arrow's place.
    function ns.ArmTarget(owner, map, x, y, label, notNpc, action)
        if notNpc or ns.Get("findTarget") == false or InCombatLockdown() then
            return false
        end
        local name = (label:match("^(.-) %- ") or label):gsub("%s*<.*>%s*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
        local dist = name ~= "" and Yards(map, x, y)
        if not dist or dist > NEAR then
            return false -- far away: nothing to target, the arrow is an ordinary button
        end
        if not overlay then
            local ok, b = pcall(CreateFrame, "Button", "GristForTheMillTargetButton", UIParent, "SecureActionButtonTemplate")
            if not ok or not b then
                return false
            end
            overlay = b
            b:SetFrameStrata("TOOLTIP")
            -- the macro must run once per click: on press or on release, whichever the client uses
            local down = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
            b:RegisterForClicks(down and "LeftButtonDown" or "LeftButtonUp")
            b:SetAttribute("type", "macro")
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
            hl:SetBlendMode("ADD")
            b:HookScript("PostClick", function(self)
                if self.action then
                    self.action()
                end
            end)
            b:HookScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText("Set Location")
                GameTooltip:AddLine("Can use TomTom arrows", 0.9, 0.9, 0.9, true)
                GameTooltip:Show()
            end)
            b:HookScript("OnLeave", function()
                GameTooltip:Hide()
                Disarm()
            end)
            b:HookScript("OnUpdate", function(self) -- the list scrolled or the window moved under it
                if not self:IsMouseOver() then
                    Disarm()
                end
            end)
            local ev = CreateFrame("Frame")
            ev:RegisterEvent("PLAYER_REGEN_DISABLED") -- last moment a secure button may be hidden
            ev:SetScript("OnEvent", function()
                if overlay:IsShown() then
                    overlay:Hide()
                end
            end)
        end
        overlay.npc, overlay.action = name, action
        -- /cleartarget first: when the NPC is not in sight nothing gets the star by mistake
        -- "/tm 1" on a unit that already has the star takes it off again, so clear the icon first:
        -- a second click leaves the star where it is
        overlay:SetAttribute("macrotext", "/cleartarget\n/targetexact " .. name .. "\n/tm 0\n/tm 1")
        local ui = UIParent:GetEffectiveScale()
        overlay:ClearAllPoints()
        local left, bottom, w, h
        if owner then
            left, bottom, w, h = owner:GetRect()
        end
        if left then
            local k = owner:GetEffectiveScale() / ui
            overlay:SetSize(w * k, h * k)
            overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * k, bottom * k)
        else
            local cx, cy = GetCursorPosition()
            overlay:SetSize(20, 20)
            overlay:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / ui, cy / ui)
        end
        overlay:Show()
        return true
    end
end

-- resize grip (the diagonal lines) for the bottom-right corner of window f. start() runs before the
-- drag, moved() while the window changes size, stop() after it; right-click calls reset() if given
function ns.ResizeGrip(f, start, moved, stop, reset)
    f:SetResizable(true)
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetFrameLevel(f:GetFrameLevel() + 600) -- above the panels and Blizzard's frame art
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            self.reset = true
            return
        end
        if start then
            start()
        end
        f.sizing = true
        f:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function(self)
        f:StopMovingOrSizing()
        f.sizing = nil
        if self.reset then
            self.reset = nil
            if reset then
                reset()
            end
        end
        stop()
    end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Resize")
        GameTooltip:AddLine("Drag to change the size of the window. Right-click for the normal size", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", GameTooltip_Hide)
    f:HookScript("OnSizeChanged", function()
        if f.sizing and moved then
            moved()
        end
    end)
    return grip
end

-- flat tab (icon + label), same look as the Items / Recipes tabs of the Farming window:
-- selected = bronze fill + white text, others dark with grey text
function ns.CreateTab(parent, label, width, icon)
    local own = ns.LayoutWidget("Tab")
    if own then
        return own(parent, label, width, icon)
    end
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(24)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    ns.TabBorder(b)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.12)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    local iconMarkup = icon and ("|T%s:14:14:0:0:64:64:5:59:5:59|t "):format(icon) or ""
    function b.SetText(self, text)
        self.text:SetText(iconMarkup .. (text or ""))
        self:SetWidth(math.max(self.text:GetStringWidth() + 24, 60)) -- as wide as the label needs
    end
    function b.SetSelected(self, on)
        self.selected = on
        self.bg:SetColorTexture(on and 0.55 or 0, on and 0.42 or 0, on and 0.18 or 0, on and 0.55 or 0.35)
        local c = not self:IsEnabled() and 0.4 or on and 1 or 0.6
        self:SetAlpha(self:IsEnabled() and 1 or 0.4) -- nothing behind this tab: greyed out, icon too
        if on then
            self:SetBorderColor(1, 0.82, 0, 0.9) -- the open tab: gold outline
        else
            self:SetBorderColor(0.45, 0.36, 0.2, self:IsEnabled() and 0.9 or 0.45)
        end
        self.text:SetTextColor(c, c, c)
    end
    b:HookScript("OnEnable", function(self)
        self:SetSelected(self.selected)
    end)
    b:HookScript("OnDisable", function(self)
        self:SetSelected(self.selected)
    end)
    b:SetText(label)
    b:SetSelected(false)
    return b
end

-- side tab on the right edge of a window: square icon, tooltip, glow when selected
function ns.CreateSideTab(parent, icon, tip)
    local own = ns.LayoutWidget("SideTab")
    if own then
        return own(parent, icon, tip)
    end
    local b = CreateFrame("CheckButton", nil, parent)
    -- slim brown-gold frame with cut corners, drawn over the icon (its corners hide under the frame)
    b:SetSize(52, 52)
    local bg = b:CreateTexture(nil, "OVERLAY", nil, 1)
    bg:SetAllPoints()
    bg:SetTexture(ns.Tex("SideTab"))
    local ico = b:CreateTexture(nil, "ARTWORK")
    ico:SetSize(40, 40)
    ico:SetPoint("CENTER")
    local black = b:CreateTexture(nil, "BACKGROUND", nil, -1)
    black:SetAllPoints(ico)
    black:SetColorTexture(0, 0, 0, 1)
    b.ownArt = { bg, black }
    b.ico = ico
    ico:SetTexture(icon)
    if icon:find("\\Icons\\") then
        ico:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    -- hover / selected glows must be additive (their textures have a black background)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    local hl = b:GetHighlightTexture()
    hl:ClearAllPoints()
    hl:SetAllPoints(ico)
    hl:SetBlendMode("ADD")
    -- selected: the same frame in bright gold
    b:SetCheckedTexture(ns.Tex("SideTabSel"))
    local ck = b:GetCheckedTexture()
    ck:ClearAllPoints()
    ck:SetAllPoints(b)
    ck:SetBlendMode("BLEND")
    ck:SetDrawLayer("OVERLAY", 2)
    b.badge = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.badge:SetPoint("BOTTOMRIGHT", ico, "BOTTOMRIGHT", 2, -2)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tip or tip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    function b.SetSelected(self, on)
        self:SetChecked(on)
        ico:SetDesaturated(false)
        ico:SetAlpha(1)
        for _, t in ipairs(self.selArt or {}) do
            t:SetShown(on and true or false)
        end
    end
    -- keep SetText for the error badge: "Errors  |cff..3|r" -> badge "3"
    function b.SetText(self, text)
        self.tip = (text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local n = (text or ""):match("(%d+)")
        self.badge:SetText(n or "")
    end
    b.tip = tip
    return b
end

-- two or more small buttons acting as a switch; options = { { label, value }, ... }
function ns.CreateSegmented(parent, options, width, get, set, label)
    -- one joined bar: active choice filled gold (like the category bars) with white text, others dim;
    -- optional label in front ("Group By", "Show")
    local box = CreateFrame("Frame", nil, parent)
    local labelW = 0
    if label then
        local l = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetPoint("LEFT", 0, 0)
        l:SetText(label)
        labelW = 64
    end
    box:SetSize(width + labelW, 24)
    local track = CreateFrame("Frame", nil, box, "BackdropTemplate")
    track:SetPoint("LEFT", labelW, 0)
    track:SetSize(width, 24)
    ns.Skin(track, { 0, 0, 0, 0.55 }, { 0.55, 0.42, 0.18, 1 }, 4)
    local segW = (width - 4) / #options
    local segs = {}
    local function Update()
        local v = get()
        for _, sg in ipairs(segs) do
            local on = sg.value == v
            sg.fill:SetShown(on)
            sg.text:SetFontObject(on and "GameFontHighlightSmall" or "GameFontDisableSmall")
            sg.mark:SetShown(on)
        end
    end
    for i, o in ipairs(options) do
        local sg = CreateFrame("Button", nil, track)
        sg:SetSize(segW, 20)
        sg:SetPoint("LEFT", 2 + (i - 1) * segW, 0)
        sg.fill = ns.HeaderBar(sg, 20, true)
        local hl = sg:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.82, 0.2, 0.12)
        sg.mark = sg:CreateTexture(nil, "ARTWORK")
        sg.mark:SetSize(12, 12)
        sg.mark:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        sg.text = sg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sg.text:SetPoint("CENTER", 6, 0)
        sg.text:SetText(o[1])
        sg.mark:SetPoint("LEFT", 6, 0) -- tick pinned to the left edge of the segment
        sg.value = o[2]
        sg:SetScript("OnClick", function()
            set(o[2])
            Update()
        end)
        if o[3] then
            sg:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:SetText(o[1])
                GameTooltip:AddLine(o[3], 0.9, 0.9, 0.9, true)
                GameTooltip:Show()
            end)
            sg:SetScript("OnLeave", GameTooltip_Hide)
        end
        segs[i] = sg
    end
    box.Update = Update
    Update()
    return box
end

-- check button (Blizzard tick box); get() -> bool, set(bool)
function ns.CreateSwitch(parent, get, set)
    local cb = Try("UICheckButtonTemplate", "CheckButton", parent) or CreateFrame("CheckButton", nil, parent)
    cb:SetSize(26, 26)
    function cb.Update()
        cb:SetChecked(get() and true or false)
    end
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
    end)
    cb.Update()
    return cb
end

-- input box
function ns.CreateEditBox(parent)
    local e = Try("InputBoxTemplate", "EditBox", parent) or CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    e:SetHeight(22)
    e:SetAutoFocus(false)
    e:SetFontObject(ChatFontNormal)
    e:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    e:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
    end)
    return e
end

-- search box (magnifier + placeholder + clear button)
function ns.CreateSearchBox(parent)
    local e = Try("SearchBoxTemplate", "EditBox", parent) or ns.CreateEditBox(parent)
    e:SetHeight(20)
    e:SetAutoFocus(false)
    return e
end

---------------------------------------------------------------------------
-- Row list: category bars (gold-bordered, collapse -/+) and item rows (icon, name, right text),
-- hover highlight and a gold selection bar - like the profession recipe list.
-- rows = { { header = true, key, text, icon, count, open }, { id, text, icon, right, selected }, ... }
---------------------------------------------------------------------------
ns.COL_W = 36 -- width of a numeric column in row lists

-- button styled like a category bar (brown fill, gold border, gold text, -/+ on the right)
function ns.CreateHeaderButton(parent, label)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(24)
    local hbar = ns.HeaderBar(b, 24)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.5)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", 8, 0)
    b:SetFontString(fs)
    local sign = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sign:SetPoint("RIGHT", -8, 0)
    local setText = b.SetText
    b.SetText = function(self, text)
        setText(self, text)
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", 8, 0)
        hbar:SetOpen((text or ""):find("^Collapse") ~= nil)
        sign:SetText(ns.SignText((text or ""):find("^Collapse") ~= nil))
        if self.fit then -- hug the text: margin + text + gap + sign + margin
            self:SetWidth(8 + fs:GetStringWidth() + 10 + sign:GetStringWidth() + 8)
        end
    end
    b:SetText(label)
    return b
end

function ns.CreateRowList(parent, onClick, onEnter)
    local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, parent, "ScrollFrameTemplate")
    if not ok or not scroll or not scroll.ScrollBar then
        scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    end
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    local pool = {}
    local HEAD_H, ROW_H = 25, 20

    local function NewRow(owner)
        local r = CreateFrame("Button", nil, owner)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r.bar = ns.HeaderBar(r, 24)
        r.sel = r:CreateTexture(nil, "BACKGROUND")
        r.sel:SetAllPoints()
        if not ns.RowArt(r.sel, "selected") then
            ns.Gradient(r.sel, "HORIZONTAL", { 1, 0.82, 0.2, 0.55 }, { 1, 0.82, 0.2, 0 })
        end
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints()
        if not ns.RowArt(r.hl, "hover") then
            r.hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            r.hl:SetBlendMode("ADD")
            r.hl:SetAlpha(0.5)
        end
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.right:SetPoint("RIGHT", -8, 0)
        r.right:SetJustifyH("RIGHT")
        -- optional numeric columns (e.g. Bags / Bank), right-aligned, fixed width
        r.c2 = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.c2:SetPoint("RIGHT", -8, 0)
        r.c2:SetWidth(ns.COL_W)
        r.c2:SetJustifyH("RIGHT")
        r.c1 = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.c1:SetPoint("RIGHT", r.c2, "LEFT", -4, 0)
        r.c1:SetWidth(ns.COL_W)
        r.c1:SetJustifyH("RIGHT")
        r:SetScript("OnClick", function(self, button)
            if onClick then
                onClick(self.data, button)
            end
        end)
        r:SetScript("OnEnter", function(self)
            if onEnter then
                onEnter(self, self.data)
            end
        end)
        r:SetScript("OnLeave", GameTooltip_Hide)
        return r
    end

    local function Row(i)
        local r = pool[i]
        if not r then
            r = NewRow(child)
            pool[i] = r
        end
        return r
    end

    -- dress a row for its data (header bar or item row); returns its height
    local function Fill(r, d, w)
        r.data = d
        local h = d.header and HEAD_H or ROW_H
        r:SetSize(w - 2, h)
        r.bar:SetShown(d.header)
        r.bar:SetOpen(d.open)
        r.sel:SetShown(not d.header and d.selected)
        r.icon:ClearAllPoints()
        if d.header then
            r.icon:SetSize(18, 18)
            r.icon:SetPoint("LEFT", 6, 0)
            r.text:SetFontObject(ns.HEADER_FONT)
            r.right:SetFontObject("GameFontNormalLarge")
            r.right:SetText(ns.SignText(d.open))
            r.right:SetTextColor(1, 0.82, 0)
        else
            r.icon:SetSize(16, 16)
            r.icon:SetPoint("LEFT", 24, 0)
            r.text:SetFontObject(d.selected and "GameFontNormal" or "GameFontHighlight")
            r.right:SetFontObject("GameFontHighlightSmall")
            r.right:SetText(d.cols and "" or (d.right or ""))
            r.right:SetTextColor(1, 1, 1)
        end
        r.icon:SetTexture(d.icon)
        r.icon:SetShown(d.icon ~= nil)
        if d.icon then
            r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end
        r.text:ClearAllPoints()
        r.text:SetPoint("LEFT", d.icon and r.icon or r, d.icon and "RIGHT" or "LEFT", d.icon and 6 or 8, 0)
        r.c1:SetShown(d.cols ~= nil)
        r.c2:SetShown(d.cols ~= nil)
        if d.cols then
            r.c1:SetText(d.cols[1])
            r.c2:SetText(d.cols[2])
            r.text:SetPoint("RIGHT", r.c1, "LEFT", -6, 0)
        else
            r.text:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
        end
        r.text:SetText(d.text or "")
        return h
    end

    -- sticky category headers (setting "stickyHeaders"): the nearest headers scrolled past dock at the top,
    -- the nearest ones below the visible part dock at the bottom - together at most ~45% of the height.
    -- A header docked on top behaves like the real one (click = collapse); one docked at the bottom
    -- scrolls its category into view.
    local stick, stickPool = {}, {} -- stick = { { y, data, frame }, ... } in list order
    local function UpdateSticky()
        local used = 0
        for _, it in ipairs(stick) do
            it.frame:SetAlpha(1)
        end
        if #stick > 0 and ns.Get("stickyHeaders") then
            local s, vh, w = scroll:GetVerticalScroll(), scroll:GetHeight(), scroll:GetWidth()
            local function Dock(it, point, offset, target)
                it.frame:SetAlpha(0) -- the real header hides while its docked copy shows
                used = used + 1
                local f = stickPool[used]
                if not f then
                    f = NewRow(scroll)
                    f:SetFrameLevel(scroll:GetFrameLevel() + 20)
                    local back = f:CreateTexture(nil, "BACKGROUND", nil, -8) -- the list must not show through
                    back:SetAllPoints()
                    back:SetColorTexture(0.05, 0.04, 0.03, 1)
                    f:SetScript("OnClick", function(self, button)
                        if self.dockBottom then
                            scroll:SetVerticalScroll(math.max(math.min(self.target, scroll:GetVerticalScrollRange()), 0))
                        elseif onClick then
                            onClick(self.data, button)
                        end
                    end)
                    stickPool[used] = f
                end
                f:ClearAllPoints()
                f:SetPoint(point .. "LEFT", scroll, point .. "LEFT", 0, offset)
                Fill(f, it.data, w)
                f.dockBottom = point == "BOTTOM"
                f.target = target
                f:Show()
            end
            local n = #stick
            local maxDock = math.max(2, math.floor(vh * 0.45 / HEAD_H))
            local topCap = math.max(1, math.floor(maxDock / 2))
            local botCap = math.max(1, maxDock - topCap)
            local topCount = 0
            for i, it in ipairs(stick) do
                if it.y - s < math.min(i - 1, topCap - 1) * HEAD_H - 0.5 then
                    topCount = i
                else
                    break
                end
            end
            local first = math.max(topCount - topCap + 1, 1)
            for i = first, topCount do
                local it = stick[i]
                Dock(it, "TOP", -(i - first) * HEAD_H, it.y - math.min(i - 1, topCap) * HEAD_H)
            end
            local firstOff
            for i = topCount + 1, n do
                if stick[i].y - s + HEAD_H > vh - math.min(n - i, botCap - 1) * HEAD_H + 0.5 then
                    firstOff = i
                    break
                end
            end
            if firstOff then
                local docked = math.min(n - firstOff + 1, botCap)
                for j = 0, docked - 1 do
                    local i = firstOff + j
                    local it = stick[i]
                    Dock(it, "BOTTOM", (docked - 1 - j) * HEAD_H, it.y - math.min(i - 1, topCap) * HEAD_H)
                end
            end
        end
        for i = used + 1, #stickPool do
            stickPool[i]:Hide()
        end
    end
    scroll:HookScript("OnVerticalScroll", UpdateSticky)
    scroll:HookScript("OnSizeChanged", UpdateSticky)

    function scroll.SetRows(self, rows)
        local w = self:GetWidth()
        child:SetWidth(w)
        local y = 0
        stick = {}
        for i, d in ipairs(rows) do
            local r = Row(i)
            if d.header then
                y = y + (i > 1 and 6 or 0)
            end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
            r:SetAlpha(1)
            local h = Fill(r, d, w)
            if d.header then
                stick[#stick + 1] = { y = y, data = d, frame = r }
            end
            r:Show()
            y = y + h
        end
        for i = #rows + 1, #pool do
            pool[i]:Hide()
        end
        child:SetHeight(math.max(y, 1))
        self:UpdateScrollChildRect()
        self:SetVerticalScroll(math.min(self:GetVerticalScroll(), self:GetVerticalScrollRange()))
        UpdateSticky()
    end

    return scroll
end

---------------------------------------------------------------------------
-- Error log. With BugGrabber installed it owns the error handler (and blocks
-- seterrorhandler), so read its DB. Without it, keep Blizzard's popup and
-- also save to HelperDB.errors.
---------------------------------------------------------------------------
local earlyErrors = {}

local function RecordError(msg, stack)
    msg = tostring(msg)
    local list = earlyErrors
    if HelperDB then
        HelperDB.errors = HelperDB.errors or {}
        list = HelperDB.errors
    end
    for _, e in ipairs(list) do
        if e.msg == msg then
            e.count = e.count + 1
            e.t = time()
            return
        end
    end
    table.insert(list, { msg = msg, stack = stack and stack:sub(1, 800), count = 1, t = time() })
    while #list > MAX_ERRORS do
        table.remove(list, 1)
    end
end

if not BugGrabber then
    local defaultHandler = geterrorhandler()
    seterrorhandler(function(msg, ...)
        pcall(RecordError, msg, debugstack(3))
        return defaultHandler(msg, ...)
    end)
end

---------------------------------------------------------------------------
-- Main window with tabs
---------------------------------------------------------------------------
local function Toggle()
    if mainFrame then
        mainFrame:SetShown(not mainFrame:IsShown())
    end
end

local TABS = { "Reagents", "Farming", "Settings" }
local TAB_ICONS = {
    "Interface\\Icons\\INV_Misc_Bag_10",
    "Interface\\Icons\\INV_Pick_02",
    "Interface\\Icons\\INV_Misc_Gear_01",
}
local tabs = {}

-- side tabs stack without gaps
local function LayoutTabs()
    for i, t in ipairs(tabs) do
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", 1, -52 - (i - 1) * (ns.tabStep or 57))
    end
end

local function SelectTab(id)
    if not tabs[id] then
        id = 1
    end
    db.tab = id
    for i, p in ipairs(panels) do
        p:SetShown(i == id)
    end
    for i, t in ipairs(tabs) do
        t:SetSelected(i == id)
    end
end

function ns.Open(tab)
    if mainFrame then
        mainFrame:Show()
        SelectTab(tab)
    end
end

---------------------------------------------------------------------------
-- Docking: while a profession window is open, Helper sits pinned to its right side;
-- back to the saved position when it closes. Dragging Helper undocks it.
---------------------------------------------------------------------------
local PROF_FRAMES = { "ProfessionsFrame", "TradeSkillFrame" }
local docked
local hookedProf = {}

local function PlaceSaved()
    mainFrame:ClearAllPoints()
    if db.pos then
        mainFrame:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
    else
        -- default: where Blizzard opens the profession window (left panel slot)
        local sc = mainFrame:GetScale()
        mainFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16 / sc, -116 / sc)
    end
end

local MAX_SCALE = 1 -- the window never gets bigger than its designed size
local SIDE_TABS = 64 -- width of Helper's own side tabs

local function UserScale()
    return MAX_SCALE -- same scale as Blizzard windows (the resize setting was removed)
end

-- how far the profession window's own side tabs stick out past its right edge
local function ProfTabsWidth(prof)
    local right, extra = prof:GetRight(), 0
    if right then
        for _, c in ipairs({ prof:GetChildren() }) do
            local r = c:IsShown() and c:GetRight()
            if r and r > right and r - right < 120 then
                extra = math.max(extra, r - right)
            end
        end
    end
    return math.max(extra, 46)
end

local FULL_W, FULL_H, MIN_W = 1020, 690, 760

-- the profession window's own side tabs: buttons hanging just past its right edge. They may be its
-- children, grandchildren, or separate frames anchored next to it (then found by position).
local function ProfSideTabs(prof)
    local right, top, bottom = prof:GetRight(), prof:GetTop(), prof:GetBottom()
    local found = {}
    if not (right and top and bottom) then
        return found
    end
    local pScale = prof:GetEffectiveScale()
    local function Fits(c)
        if c == mainFrame or not c.IsVisible or not c:IsVisible() or not c.GetObjectType then
            return false
        end
        local t = c:GetObjectType()
        if t ~= "Button" and t ~= "CheckButton" then
            return false
        end
        local s = c:GetEffectiveScale() / pScale
        local l, r, ct, w, h = c:GetLeft(), c:GetRight(), c:GetTop(), c:GetSize()
        if not (l and r and ct) then
            return false
        end
        l, r, ct, w, h = l * s, r * s, ct * s, w * s, h * s
        return l > right - 12 and r > right + 16 and r < right + 110 and ct <= top and ct >= bottom
            and w >= 24 and w <= 90 and h >= 24 and h <= 90
    end
    local function Scan(f, depth)
        for _, c in ipairs({ f:GetChildren() }) do
            if Fits(c) then
                found[#found + 1] = c
            elseif depth > 0 then
                Scan(c, depth - 1)
            end
        end
    end
    Scan(prof, 4)
    return found
end

local function RegionArt(reg)
    return tostring(reg.GetAtlas and reg:GetAtlas()) .. "|" .. tostring(reg.GetTexture and reg:GetTexture())
end

local function IsSelectedTab(t)
    return t.GetChecked and t:GetChecked() and true or false
end

-- copy a texture region of a profession tab onto one of Helper's tabs (same art, size, position)
local function CopyRegion(reg, src, dst)
    local layer, sub = reg:GetDrawLayer()
    local c = dst:CreateTexture(nil, layer, nil, sub)
    if reg:GetAtlas() then
        c:SetAtlas(reg:GetAtlas())
    else
        c:SetTexture(reg:GetTexture())
        c:SetTexCoord(reg:GetTexCoord())
    end
    c:SetSize(reg:GetSize())
    local n = reg:GetNumPoints()
    for i = 1, n do
        local p, rel, rp, x, y = reg:GetPoint(i)
        if rel ~= src and rel ~= nil then -- anchored to something else: place by its real offset
            n = 0
            break
        end
        c:SetPoint(p, dst, rp, x, y)
    end
    if n == 0 then
        c:ClearAllPoints()
        local sl, st = src:GetLeft(), src:GetTop()
        local rl, rt = reg:GetLeft(), reg:GetTop()
        if sl and st and rl and rt then
            c:SetPoint("TOPLEFT", dst, "TOPLEFT", rl - sl, rt - st)
        else
            c:SetAllPoints()
        end
    end
    c:SetVertexColor(reg:GetVertexColor())
    c:SetBlendMode(reg:GetBlendMode())
    c:SetAlpha(reg:GetAlpha())
    return c
end

-- make Helper's side tabs look like the profession window's: same frame art, size and spacing.
-- The icon slot is the region whose texture differs from tab to tab; art that only the selected
-- tab shows becomes Helper's "selected" art.
function ns.CloneProfTabs(prof)
    local list = ProfSideTabs(prof)
    local plain, selected
    for _, t in ipairs(list) do
        if IsSelectedTab(t) then
            selected = selected or t
        else
            plain = plain or t
        end
    end
    local src = plain or list[1]
    ns.MirrorProfStyle(prof, src, #list)
    if not src or tabs.cloned or #list < 2 then -- need several real tabs to be sure
        return
    end
    local other
    for _, t in ipairs(list) do
        if t ~= src and select("#", t:GetRegions()) == select("#", src:GetRegions()) then
            other = other or t
        end
    end
    local regs = { src:GetRegions() }
    local oregs = other and { other:GetRegions() } or {}
    local sregs = selected and select("#", selected:GetRegions()) == #regs and { selected:GetRegions() } or {}
    local art, selArt, iconReg = {}, {}, nil
    for i, reg in ipairs(regs) do
        if reg:GetObjectType() == "Texture" then
            local layer = reg:GetDrawLayer()
            local o = oregs[i]
            local isIcon = o and o:GetObjectType() == "Texture" and RegionArt(o) ~= RegionArt(reg)
            if isIcon then
                iconReg = iconReg or reg
            elseif layer ~= "HIGHLIGHT" and (reg:GetAtlas() or reg:GetTexture()) then
                if reg:IsShown() and reg:GetAlpha() > 0 then
                    art[#art + 1] = reg
                elseif sregs[i] and sregs[i]:IsShown() then
                    selArt[#selArt + 1] = sregs[i]
                end
            end
        end
    end
    if #art == 0 then
        return
    end
    tabs.cloned = true
    local w, h = src:GetSize()
    for _, t in ipairs(tabs) do
        for _, own in ipairs(t.ownArt or {}) do
            own:Hide()
        end
        t:SetSize(w, h)
        t.ico:ClearAllPoints()
        if iconReg then
            t.ico:SetSize(iconReg:GetSize())
            local sl, st, rl, rt = src:GetLeft(), src:GetTop(), iconReg:GetLeft(), iconReg:GetTop()
            if sl and st and rl and rt then
                t.ico:SetPoint("TOPLEFT", t, "TOPLEFT", rl - sl, rt - st)
            else
                t.ico:SetPoint("CENTER")
            end
            t.ico:SetTexCoord(iconReg:GetTexCoord())
            t.ico:SetDrawLayer(iconReg:GetDrawLayer())
        else
            t.ico:SetSize(math.min(w, h) * 0.72, math.min(w, h) * 0.72)
            t.ico:SetPoint("CENTER")
        end
        for _, reg in ipairs(art) do
            CopyRegion(reg, src, t)
        end
        t.selArt = {}
        for _, reg in ipairs(selArt) do
            t.selArt[#t.selArt + 1] = CopyRegion(reg, selected, t)
        end
        if #t.selArt > 0 then -- the profession window's own "selected" look replaces Helper's glow
            local ck = t:GetCheckedTexture()
            if ck then
                ck:SetAlpha(0)
            end
        end
        t:SetSelected(t:GetChecked())
    end
    -- same vertical spacing as the profession tabs
    local step
    if other and src:GetTop() and other:GetTop() then
        step = math.abs(src:GetTop() - other:GetTop())
    end
    ns.tabStep = (step and step >= h and step < h * 2) and step or (h + 6)
    LayoutTabs()
end

-- re-render what depends on the window size
local function Relayout()
    C_Timer.After(0, function()
        if ns.RefreshReagents then
            ns.RefreshReagents()
        end
    end)
end

-- docked: same scale as the profession window (so title bar, portrait, fonts and tabs are the same
-- size), same top and height; the width takes what is left of the screen
function ns.DockTo(prof)
    if not mainFrame or not prof or not prof:IsShown() then
        return
    end
    docked = prof
    local gap = ProfTabsWidth(prof) + 6
    pcall(ns.CloneProfTabs, prof)
    local ui = UIParent:GetEffectiveScale()
    local pScale = prof:GetEffectiveScale()
    local scale = pScale / ui
    local avail = (UIParent:GetRight() * ui - (prof:GetRight() + gap) * pScale) / pScale - SIDE_TABS
    if avail < MIN_W then -- not enough room at full size: shrink just enough
        scale = scale * math.max(avail / MIN_W, 0.5)
        avail = MIN_W
    end
    mainFrame:SetScale(scale)
    mainFrame:SetSize(math.min(FULL_W, avail), prof:GetHeight() * pScale / mainFrame:GetEffectiveScale())
    mainFrame:ClearAllPoints()
    mainFrame:SetPoint("TOPLEFT", prof, "TOPRIGHT", gap * pScale / mainFrame:GetEffectiveScale(), 0)
    Relayout()
end

local function Undock()
    if docked then
        docked = nil
        mainFrame:SetScale(UserScale())
        mainFrame:SetSize(db.size and db.size[1] or FULL_W, db.size and db.size[2] or FULL_H)
        PlaceSaved()
        Relayout()
    end
end

local function ShownProf()
    for _, name in ipairs(PROF_FRAMES) do
        local fr = _G[name]
        if fr and fr:IsShown() then
            return fr
        end
    end
end

-- profession frames are load-on-demand: hook them when they exist
function ns.HookProfFrames()
    for _, name in ipairs(PROF_FRAMES) do
        local fr = _G[name]
        if fr and not hookedProf[fr] then
            hookedProf[fr] = true
            -- icon-only button on the skill bar's row
            local open = CreateFrame("Button", nil, fr)
            open:SetSize(24, 24)
            open:SetPoint("TOPRIGHT", fr, "TOPRIGHT", -52, -40)
            open:SetFrameStrata("HIGH")
            local oi = open:CreateTexture(nil, "ARTWORK")
            oi:SetAllPoints()
            oi:SetTexture(ICON_ROUND)
            oi:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            local ob = open:CreateTexture(nil, "OVERLAY")
            ob:SetAllPoints()
            ob:SetTexture("Interface\\Common\\WhiteIconFrame")
            ob:SetVertexColor(0.8, 0.65, 0.4)
            open:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            open:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
            open:SetScript("OnClick", function()
                if mainFrame then
                    mainFrame:SetShown(not mainFrame:IsShown())
                end
            end)
            open:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(ADDON_NAME)
                GameTooltip:AddLine("Open or close the Grist for the Mill window", 0.8, 0.8, 0.8)
                GameTooltip:Show()
            end)
            open:SetScript("OnLeave", GameTooltip_Hide)

            -- "Farm" button for the recipe selected in the profession window
            local function SelectedRecipe()
                local form = fr.CraftingPage and fr.CraftingPage.SchematicForm
                if form then
                    local info = form.GetRecipeInfo and form:GetRecipeInfo() or form.currentRecipeInfo
                    return info and info.recipeID
                end
                if GetTradeSkillSelectionIndex and GetTradeSkillRecipeLink then
                    local link = GetTradeSkillRecipeLink(GetTradeSkillSelectionIndex())
                    return link and tonumber(link:match("enchant:(%d+)"))
                end
            end
            local form = fr.CraftingPage and fr.CraftingPage.SchematicForm
            -- Farming stepper for the recipe shown: "Farming  - [n] +" (same control as on the recipe cards)
            local farm = CreateFrame("Frame", nil, form or fr)
            farm:SetSize(132, 20)
            if form then
                farm:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 14, 10)
            else
                farm:SetPoint("BOTTOMLEFT", fr, "BOTTOMLEFT", 22, 8)
            end
            farm:SetFrameLevel((form or fr):GetFrameLevel() + 10)
            local function StepBtn(kind)
                local b = CreateFrame("Button", nil, farm)
                b:SetSize(16, 16)
                b:SetNormalTexture("Interface\\Buttons\\UI-" .. kind .. "Button-Up")
                b:SetPushedTexture("Interface\\Buttons\\UI-" .. kind .. "Button-Down")
                b:SetDisabledTexture("Interface\\Buttons\\UI-" .. kind .. "Button-Disabled")
                b:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
                return b
            end
            farm.label = farm:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            farm.label:SetPoint("LEFT", 0, 0)
            farm.label:SetText("Farming")
            farm.minus = StepBtn("Minus")
            farm.minus:SetPoint("LEFT", farm.label, "RIGHT", 6, 0)
            farm.box = CreateFrame("EditBox", nil, farm)
            farm.box:SetSize(34, 18)
            farm.box:SetPoint("LEFT", farm.minus, "RIGHT", 2, 0)
            farm.box:SetAutoFocus(false)
            farm.box:SetNumeric(true)
            farm.box:SetMaxLetters(4)
            farm.box:SetJustifyH("CENTER")
            farm.box:SetFontObject("NumberFontNormal")
            local boxBg = farm.box:CreateTexture(nil, "BACKGROUND")
            boxBg:SetAllPoints()
            boxBg:SetColorTexture(0, 0, 0, 0.55)
            local boxEdge = CreateFrame("Frame", nil, farm.box, "BackdropTemplate")
            boxEdge:SetAllPoints()
            ns.Skin(boxEdge, { 0, 0, 0, 0 }, { 0.4, 0.4, 0.4, 1 }, 0)
            farm.plus = StepBtn("Plus")
            farm.plus:SetPoint("LEFT", farm.box, "RIGHT", 2, 0)
            -- clicking a reagent of the recipe shown in the profession window selects it in Grist for the Mill
            local hookedSlots = {}
            local function SlotItem(slot)
                local b = slot.Button
                local id = b and b.GetItemID and b:GetItemID()
                if not id and slot.GetReagentSlotSchematic then
                    local sch = slot:GetReagentSlotSchematic()
                    id = sch and sch.reagents and sch.reagents[1] and sch.reagents[1].itemID
                end
                return id
            end
            local function HookReagentSlots()
                local f = fr.CraftingPage and fr.CraftingPage.SchematicForm
                for _, slots in pairs(f and type(f.reagentSlots) == "table" and f.reagentSlots or {}) do
                    for _, slot in ipairs(type(slots) == "table" and slots or {}) do
                        local target = slot.Button or slot
                        if not hookedSlots[target] and target.HookScript then
                            hookedSlots[target] = true
                            target:HookScript("OnMouseDown", function()
                                local okI, item = pcall(SlotItem, slot)
                                if okI and item and ns.SelectReagent then
                                    ns.SelectReagent(item)
                                end
                            end)
                        end
                    end
                end
            end
            local lastRecipe
            fr:HookScript("OnShow", function()
                lastRecipe = nil -- opening the window: show the recipe it opens on
            end)
            local function Refresh()
                if ns.silentCraft then
                    return
                end
                pcall(HookReagentSlots)
                local ok, id = pcall(SelectedRecipe)
                -- picking another recipe selects its first reagent in Grist for the Mill
                if ok and id and id ~= lastRecipe then
                    if ns.SelectRecipeReagent and id ~= ns.syncedRecipe then
                        ns.SelectRecipeReagent(id)
                    end
                    ns.syncedRecipe = nil
                    lastRecipe = id
                    ns.profRecipe = id -- remembered for reopening the window (side map)
                end
                local n = ok and ns.FarmRecipe and ns.FarmRecipe(id)
                local known = type(n) == "number"
                farm.minus:SetEnabled(known and n > 0)
                farm.plus:SetEnabled(known)
                farm.box:SetEnabled(known)
                if not farm.box:HasFocus() then
                    farm.box:SetText(tostring(known and n or 0))
                end
                local on = known and n > 0
                farm.box:SetTextColor(on and 1 or 0.5, on and 0.82 or 0.5, on and 0 or 0.5)
            end
            -- set the number of crafts to farm for (0 takes the recipe off the Farming list)
            local function SetCrafts(n)
                local ok, id = pcall(SelectedRecipe)
                local cur = ok and id and ns.FarmRecipe and ns.FarmRecipe(id)
                if type(cur) == "number" then
                    ns.FarmRecipe(id, math.max(math.floor(n or 0), 0) - cur)
                end
                Refresh()
            end
            local function Step(dir)
                local ok, id = pcall(SelectedRecipe)
                local cur = ok and id and ns.FarmRecipe and ns.FarmRecipe(id)
                if type(cur) == "number" then
                    SetCrafts(cur + dir * (IsShiftKeyDown() and 5 or 1))
                end
            end
            farm.plus:SetScript("OnClick", function()
                Step(1)
            end)
            farm.minus:SetScript("OnClick", function()
                Step(-1)
            end)
            farm.box:SetScript("OnEnterPressed", function(self)
                SetCrafts(tonumber(self:GetText()) or 0)
                self:ClearFocus()
            end)
            farm.box:SetScript("OnEscapePressed", farm.box.ClearFocus)
            farm.box:SetScript("OnEditFocusLost", Refresh)
            farm.box:SetScript("OnEditFocusGained", farm.box.HighlightText)
            local function Tip(owner, title, line)
                owner:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText(title)
                    GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true)
                    GameTooltip:Show()
                end)
                owner:SetScript("OnLeave", GameTooltip_Hide)
            end
            Tip(farm.plus, "One More Craft", "Adds the reagents for one more craft to the Farming list. Shift-Click: 5 at a time")
            Tip(farm.minus, "One Less Craft", "Shift-Click: 5 at a time")
            Tip(farm.box, "Crafts to Farm for", "Type a number and press Enter - reagent targets on the Farming tab follow it")
            local since = 0
            farm:SetScript("OnUpdate", function(_, dt)
                since = since + dt
                if since > 0.4 then
                    since = 0
                    Refresh()
                end
            end)
            fr:HookScript("OnShow", function(self)
                if ns.silentCraft then -- opened invisibly to craft from the Crafting tracker
                    self:SetAlpha(0)
                    return
                end
                self:SetAlpha(1)
                if mainFrame and ns.Get("autoOpen") and not mainFrame:IsShown() then
                    mainFrame.autoOpened = true
                    mainFrame:Show()
                end
                if mainFrame and mainFrame:IsShown() then
                    ns.DockTo(self)
                end
            end)
            if fr:IsShown() and ns.silentCraft then
                fr:SetAlpha(0)
            elseif fr:IsShown() and mainFrame and ns.Get("autoOpen") then -- hooked while already open
                mainFrame:Show()
                ns.DockTo(fr)
            end
            fr:HookScript("OnHide", function(self)
                if ns.mapHolding or ns.silentCraft then -- side map / hidden craft: nothing to undo
                    return
                end
                if docked == self then
                    Undock()
                    if mainFrame.autoOpened then -- it came with the profession window: it leaves with it
                        mainFrame.autoOpened = nil
                        mainFrame:Hide()
                    end
                end
            end)
        end
    end
end

local function CreateMainFrame()
    -- Blizzard portrait frame (same art as the profession window); plain backdrop frame if missing
    local own = ns.LayoutWidget("MainWindow") -- a layout may bring its own window frame
    local ok, f
    if own then
        f = own("HelperMainFrame")
        ok = f ~= nil
    else
        ok, f = pcall(CreateFrame, "Frame", "HelperMainFrame", UIParent, "PortraitFrameTemplate")
    end
    if not ok or not f then
        f = CreateFrame("Frame", "HelperMainFrame", UIParent, "BackdropTemplate")
        ns.Skin(f, T.bg, { 0, 0, 0, 1 }, 12)
    end
    mainFrame = f
    if f.Bg then -- semi-transparent dark background (like Blizzard's settings panel and the farming tracker)
        f.Bg:SetColorTexture(0.05, 0.04, 0.03, 0.85)
    end
    if f.TopTileStreaks then
        f.TopTileStreaks:Hide()
    end
    f:SetSize(db.size and db.size[1] or FULL_W, db.size and db.size[2] or FULL_H)
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    if db.pos then
        f:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
    else
        f:SetPoint("CENTER")
    end
    if f.SetTitle then
        f:SetTitle(ADDON_NAME)
    end
    -- portrait: the addon icon (API differs between client versions)
    local portrait = f.PortraitContainer and f.PortraitContainer.portrait or f.portrait
    if f.SetPortraitToAsset then
        pcall(f.SetPortraitToAsset, f, ICON_ROUND)
    elseif portrait then
        portrait:SetTexture(ICON_ROUND)
    end

    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    -- double-click the title bar: dock next to the open profession window again
    local lastClick = 0
    f:HookScript("OnMouseDown", function(self, button)
        local top = self:GetTop()
        local _, cy = GetCursorPosition()
        if button ~= "LeftButton" or not top or top - cy / self:GetEffectiveScale() > 26 then
            return
        end
        local now = GetTime()
        if now - lastClick < 0.4 then
            local prof = ShownProf()
            if prof then
                ns.DockTo(prof)
            end
        end
        lastClick = now
    end)
    f:SetScript("OnDragStart", function(self)
        if docked then -- moving it by hand undocks
            docked = nil
            self:SetScale(UserScale())
        end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        db.pos = { point, relPoint, x, y }
    end)
    tinsert(UISpecialFrames, "HelperMainFrame")
    -- resize: fonts and icons keep their size, the lists and cards take the room
    if f.SetResizeBounds then
        f:SetResizeBounds(MIN_W, 420, 1700, 1300)
    end
    ns.ResizeGrip(f, function()
        if docked then -- resizing it by hand undocks, like moving it
            docked = nil
            f:SetScale(UserScale())
        end
    end, Relayout, function()
        db.size = { f:GetWidth(), f:GetHeight() }
        local point, _, relPoint, x, y = f:GetPoint()
        db.pos = { point, relPoint, x, y }
        Relayout()
    end, function()
        f:SetSize(FULL_W, FULL_H)
    end)

    -- tabs: square icon tabs on the right edge, outside the frame
    for i = 1, #TABS do
        local t = ns.CreateSideTab(f, TAB_ICONS[i], TABS[i])
        t:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, -48 - (i - 1) * 52)
        t:SetScript("OnClick", function()
            SelectTab(i)
        end)
        tabs[i] = t
    end
    mainFrame = f
    LayoutTabs()

    local inset = CreateFrame("Frame", nil, f)
    inset:SetPoint("TOPLEFT", 10, -64)
    inset:SetPoint("BOTTOMRIGHT", -10, 40)

    panels[1] = ns.CreateInfoPanel(f, inset, db)
    panels[2] = ns.CreateFarmPanel(f, inset, db)
    panels[3] = ns.CreateSettingsPanel(f, inset)
    f:SetScale(UserScale())
    ns.OnSetting("scale", function(v)
        f:SetScale(math.min(v, MAX_SCALE))
        if docked then
            ns.DockTo(docked)
        end
    end)
    f:SetScript("OnShow", function()
        ns.HookProfFrames()
        local prof = ShownProf()
        if prof then
            ns.DockTo(prof)
        end
    end)
    SelectTab(math.min(db.tab or 1, #TABS))
    f:Hide()
end

local function UpdateMinimapPos(btn)
    local a = math.rad(db.minimapAngle)
    local r = Minimap:GetWidth() / 2 + 5
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function CreateMinimapButton()
    local btn = CreateFrame("Button", "HelperMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetTexture(ICON_ROUND)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:SetPoint("TOPLEFT", 6, -5)
    if btn.CreateMaskTexture then -- round it like other minimap buttons
        local mask = btn:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
    end

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            -- menu: which window to open
            if MenuUtil and MenuUtil.CreateContextMenu then
                MenuUtil.CreateContextMenu(btn, function(_, root)
                    if root.CreateTitle then
                        root:CreateTitle(ADDON_NAME)
                    end
                    root:CreateButton("Farming", function()
                        ns.ToggleFarmTracker()
                    end)
                    root:CreateButton("Crafting", function()
                        ns.ToggleCraftTracker()
                    end)
                    root:CreateButton("Farming and Crafting", function()
                        ns.ToggleTrackers()
                    end)
                    root:CreateButton("Bag Reagents", function()
                        ns.ToggleBagReagents()
                    end)
                end)
            elseif ns.ToggleFarmTracker then
                ns.ToggleFarmTracker()
            end
        else
            -- the minimap button always opens on the Reagents tab
            if mainFrame and mainFrame:IsShown() then
                mainFrame:Hide()
            else
                ns.Open(1)
            end
        end
    end)
    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            UpdateMinimapPos(self)
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(ADDON_NAME)
        GameTooltip:AddLine("Click: open/close\nRight-Click: farming / crafting windows\nDrag: move", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    UpdateMinimapPos(btn)
    btn:SetShown(ns.Get("minimap"))
    ns.OnSetting("minimap", function(v)
        btn:SetShown(v)
    end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
pcall(frame.RegisterEvent, frame, "TRADE_SKILL_SHOW")
if not BugGrabber then
    frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    frame:RegisterEvent("ADDON_ACTION_BLOCKED")
    frame:RegisterEvent("LUA_WARNING")
end
frame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if type(arg1) == "string" and (arg1:find("Professions") or arg1:find("TradeSkill")) then
            C_Timer.After(0, ns.HookProfFrames)
        end
        return
    end
    if event == "TRADE_SKILL_SHOW" then -- the profession window is up: make sure its buttons exist
        C_Timer.After(0, ns.HookProfFrames)
        return
    end
    if event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
        pcall(RecordError, ("[%s] AddOn '%s' tried to call the protected function '%s'."):format(
            event, tostring(arg1), tostring(arg2)))
    elseif event == "LUA_WARNING" then
        pcall(RecordError, "LUA_WARNING: " .. tostring(arg2 or arg1))
    elseif event == "PLAYER_LOGIN" then
        HelperDB = HelperDB or {}
        db = HelperDB
        db.errors = db.errors or {}
        for _, e in ipairs(earlyErrors) do
            RecordError(e.msg, e.stack)
        end
        wipe(earlyErrors)
        local setCVar = C_CVar and C_CVar.SetCVar or SetCVar
        setCVar("scriptErrors", "1")

        db.minimapAngle = db.minimapAngle or 225

        -- the look chosen in Settings: its colours go in before any window is built
        ns.ApplyLayout()
        ns.OnSetting("layout", function()
            StaticPopupDialogs["GRISTFORTHEMILL_LAYOUT"] = StaticPopupDialogs["GRISTFORTHEMILL_LAYOUT"] or {
                text = "The layout changes after the interface reloads.\n\nReload now?",
                button1 = "Reload",
                button2 = "Later",
                OnAccept = function()
                    ReloadUI()
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
            StaticPopup_Show("GRISTFORTHEMILL_LAYOUT")
        end)
        CreateMinimapButton()
        CreateMainFrame()
        ns.HookProfFrames() -- in case the profession UI was loaded before Helper
        if ns.Get("loadMessage") then
            print("|cff33ff99" .. ADDON_NAME .. "|r loaded - /helper or /rf")
        end
    end
end)

SLASH_HELPER1 = "/helper"
SLASH_HELPER2 = "/grist"
SLASH_HELPER3 = "/rf"
SlashCmdList.HELPER = Toggle
