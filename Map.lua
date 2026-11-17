-- Side map: zone map art (C_Map art layers) with a dot per known spawn, attached to the
-- right of the Helper window. ns.ShowMap(title, byMap, preferredMap) where
-- byMap = { [uiMapID] = { { name, kind, x, y (0-100) }, ... } }.
local _, ns = ...

local W = 440 -- map width in pixels
local held -- profession window closed for the map: { prof = id, recipe = spellID }
local frame, canvas, tiles, dots, player, title, zoneText, legend, prevBtn, nextBtn, empty
local zones, zoneIdx, points, mapTitle = {}, 1, {}, ""
local current

local function ArtLayer(map)
    if not (C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then
        return nil
    end
    local okL, layers = pcall(C_Map.GetMapArtLayers, map)
    local okT, files = pcall(C_Map.GetMapArtLayerTextures, map, 1)
    if okL and okT and layers and layers[1] and files and #files > 0 then
        return layers[1], files
    end
end

-- overlays that make a zone look fully explored: Ext/MapOverlays.lua (all of them, by map art),
-- else the ones you have explored (C_MapExplorationInfo). Same tiling as Blizzard's exploration layer.
local overlayTex = {}

local function Overlays(map)
    local art = C_Map and C_Map.GetMapArtID and select(2, pcall(C_Map.GetMapArtID, map))
    local all = ns.MapOverlays and type(art) == "number" and ns.MapOverlays[art]
    if all then
        local out = {}
        for i, o in ipairs(all) do
            out[i] = { textureWidth = o[1], textureHeight = o[2], offsetX = o[3], offsetY = o[4], fileDataIDs = o[5] }
        end
        return out
    end
    local ex = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures
    local ok, list = pcall(ex or error, map)
    return ok and list or {}
end

local function DrawOverlays(map, layer, scale)
    for _, t in ipairs(overlayTex) do
        t:Hide()
    end
    local n = 0
    local TW, TH = layer.tileWidth, layer.tileHeight
    for _, o in ipairs(Overlays(map)) do
        local wide, tall = math.ceil(o.textureWidth / TW), math.ceil(o.textureHeight / TH)
        for j = 1, tall do
            local ph, fh = TH, TH
            if j == tall then
                ph = o.textureHeight % TH
                if ph == 0 then
                    ph = TH
                end
                fh = 16
                while fh < ph do
                    fh = fh * 2
                end
            end
            for k = 1, wide do
                local pw, fw = TW, TW
                if k == wide then
                    pw = o.textureWidth % TW
                    if pw == 0 then
                        pw = TW
                    end
                    fw = 16
                    while fw < pw do
                        fw = fw * 2
                    end
                end
                local file = o.fileDataIDs[(j - 1) * wide + k]
                if file then
                    n = n + 1
                    local t = overlayTex[n] or canvas:CreateTexture(nil, "ARTWORK", nil, 2)
                    overlayTex[n] = t
                    t:SetTexture(file)
                    t:SetTexCoord(0, pw / fw, 0, ph / fh)
                    t:SetSize(pw * scale, ph * scale)
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", canvas, "TOPLEFT", (o.offsetX + TW * (k - 1)) * scale,
                        -(o.offsetY + TH * (j - 1)) * scale)
                    t:Show()
                end
            end
        end
    end
end

local function UpdatePlayer()
    player:Hide()
    if not current or not (C_Map and C_Map.GetBestMapForUnit) then
        return
    end
    local ok, x, y = pcall(function()
        if C_Map.GetBestMapForUnit("player") ~= current then
            return nil
        end
        local pos = C_Map.GetPlayerMapPosition(current, "player")
        if pos then
            return pos:GetXY()
        end
    end)
    if ok and x and y then
        player:ClearAllPoints()
        player:SetPoint("CENTER", canvas, "TOPLEFT", x * canvas:GetWidth(), -y * canvas:GetHeight())
        player:Show()
    end
end

local function Dot(i)
    local d = dots[i]
    if not d then
        d = CreateFrame("Button", nil, canvas)
        d:SetSize(12, 12)
        d.tex = d:CreateTexture(nil, "OVERLAY")
        d.tex:SetAllPoints()
        d.tex:SetTexture(ns.Tex("Dot"))
        d:SetScript("OnEnter", function(self)
            self:SetSize(16, 16)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.p.name)
            GameTooltip:AddLine(("%s  -  (%.1f, %.1f)"):format(self.p.kind, self.p.x, self.p.y), 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Click: TomTom Arrow", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)
        d:SetScript("OnLeave", function(self)
            self:SetSize(12, 12)
            GameTooltip:Hide()
        end)
        d:SetScript("OnClick", function(self)
            if ns.SetWaypoint then
                ns.SetWaypoint(current, self.p.x, self.p.y, self.p.name)
            end
        end)
        dots[i] = d
    end
    return d
end

local function Draw()
    for _, t in ipairs(tiles) do
        t:Hide()
    end
    for _, d in ipairs(dots) do
        d:Hide()
    end
    current = zones[zoneIdx]
    title:SetText(mapTitle)
    prevBtn:SetShown(#zones > 1)
    nextBtn:SetShown(#zones > 1)
    if not current then
        zoneText:SetText("No Known Spawns")
        legend:SetText("")
        empty:Show()
        canvas:SetHeight(W * 2 / 3)
        player:Hide()
        return
    end
    zoneText:SetText(("%s  |cff7d8592%d / %d|r"):format(ns.ZoneName and ns.ZoneName(current) or current, zoneIdx, #zones))

    local layer, files = ArtLayer(current)
    empty:SetShown(not layer)
    if layer then
        local scale = W / layer.layerWidth
        canvas:SetHeight(math.floor(layer.layerHeight * scale + 0.5))
        local cols = math.ceil(layer.layerWidth / layer.tileWidth)
        for i, file in ipairs(files) do
            local t = tiles[i] or canvas:CreateTexture(nil, "ARTWORK")
            tiles[i] = t
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            t:SetTexture(file)
            t:SetSize(layer.tileWidth * scale, layer.tileHeight * scale)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", canvas, "TOPLEFT", col * layer.tileWidth * scale, -row * layer.tileHeight * scale)
            t:Show()
        end
        DrawOverlays(current, layer, scale)
    else
        canvas:SetHeight(W * 2 / 3)
        for _, t in ipairs(overlayTex) do
            t:Hide()
        end
    end

    local names, order = {}, {}
    for i, p in ipairs(points[current] or {}) do
        local d = Dot(i)
        d.p = p
        d:ClearAllPoints()
        d:SetPoint("CENTER", canvas, "TOPLEFT", p.x / 100 * W, -p.y / 100 * canvas:GetHeight())
        d.tex:SetVertexColor(1, 0.35, 0.3)
        if p.kind == "Vendor" then
            d.tex:SetVertexColor(0.45, 0.95, 0.45)
        elseif p.kind == "Gather" then
            d.tex:SetVertexColor(1, 0.85, 0.3)
        elseif p.kind == "Fish" then
            d.tex:SetVertexColor(0.3, 0.75, 1)
        end
        d:Show()
        if not names[p.name] then
            names[p.name] = 0
            order[#order + 1] = p.name
        end
        names[p.name] = names[p.name] + 1
    end
    table.sort(order, function(a, b)
        return names[a] > names[b]
    end)
    local parts = {}
    for i = 1, math.min(#order, 8) do
        parts[#parts + 1] = ("|cffe8eaf0%s|r |cff7d8592x %d|r"):format(order[i], names[order[i]])
    end
    if #order > 8 then
        parts[#parts + 1] = ("|cff7d8592+%d more|r"):format(#order - 8)
    end
    legend:SetText(table.concat(parts, "\n"))
    UpdatePlayer()
end

local function Create()
    local T = ns.T
    local parent = _G.HelperMainFrame or UIParent
    local okT, tf = pcall(CreateFrame, "Frame", "HelperMapFrame", parent, "PortraitFrameTemplate")
    local templated = okT and tf
    frame = templated or CreateFrame("Frame", "HelperMapFrame", parent, "BackdropTemplate")
    frame:SetWidth(W + 28)
    frame:SetPoint("TOPLEFT", parent, "TOPRIGHT", 52, 0)
    frame:SetFrameStrata("MEDIUM")
    if templated then
        if frame.SetTitle then
            frame:SetTitle("Map")
        end
        if frame.SetPortraitToAsset then
            pcall(frame.SetPortraitToAsset, frame, ns.Tex("Map"))
        end
    else
        ns.Skin(frame, T.bg, { 0, 0, 0, 1 }, 12)
        ns.SkinGradient(frame, T.bgTop, T.bg)
        ns.Shadow(frame)
        ns.TitleBar(frame, 44)
    end
    -- invisible anchor for the title row
    local bar = CreateFrame("Frame", nil, frame)
    if templated then -- below the Blizzard title bar, right of the portrait
        bar:SetPoint("TOPLEFT", 62, -22)
        bar:SetPoint("TOPRIGHT", -8, -22)
        bar:SetHeight(36)
    else
        bar:SetPoint("TOPLEFT")
        bar:SetPoint("TOPRIGHT")
        bar:SetHeight(44)
    end

    local icon = frame:CreateTexture(nil, "OVERLAY")
    icon:SetSize(22, 22)
    icon:SetPoint("LEFT", bar, "LEFT", 12, 0)
    icon:SetTexture(ns.Tex("Map"))
    icon:SetShown(not templated)
    title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 2)
    title:SetPoint("RIGHT", bar, "RIGHT", -44, 0)
    title:SetJustifyH("LEFT")
    title:SetTextColor(unpack(T.accent))
    zoneText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zoneText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)

    local close = ns.CreateButton(frame, "X", 24)
    close:SetPoint("RIGHT", bar, "RIGHT", -10, 0)
    close:SetScript("OnClick", function()
        frame:Hide()
    end)
    if templated then
        close:Hide()
        close:ClearAllPoints()
        close:SetPoint("RIGHT", bar, "RIGHT", 18, 0)
    end
    nextBtn = ns.CreateButton(frame, ">", 24)
    nextBtn:SetPoint("RIGHT", close, "LEFT", -12, 0)
    prevBtn = ns.CreateButton(frame, "<", 24)
    prevBtn:SetPoint("RIGHT", nextBtn, "LEFT", -4, 0)
    nextBtn:SetScript("OnClick", function()
        zoneIdx = zoneIdx % #zones + 1
        Draw()
    end)
    prevBtn:SetScript("OnClick", function()
        zoneIdx = (zoneIdx - 2) % #zones + 1
        Draw()
    end)

    local holder = ns.Card(frame, T.panel, 4)
    holder:SetPoint("TOPLEFT", 13, templated and -64 or -58)
    holder:SetPoint("TOPRIGHT", -13, templated and -64 or -58)
    canvas = CreateFrame("Frame", nil, holder)
    canvas:SetPoint("TOPLEFT", 1, -1)
    canvas:SetSize(W, W * 2 / 3)
    canvas:SetClipsChildren(true)
    holder:SetHeight(W * 2 / 3 + 2)
    hooksecurefunc(canvas, "SetHeight", function(_, h)
        holder:SetHeight(h + 2)
    end)
    empty = canvas:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("CENTER")
    empty:SetText("No Map Art for This Zone")

    player = canvas:CreateTexture(nil, "OVERLAY", nil, 7)
    player:SetSize(14, 14)
    player:SetTexture(ns.Tex("DotBlue"))

    local lt = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lt:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 2, -12)
    lt:SetText("Spawns in This Zone")
    lt:SetTextColor(unpack(T.accent))
    local key = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    key:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", -2, -12)
    key:SetText("|cffff6060Drop|r  |cff80ff80Vendor|r  |cffffe066Gather|r  |cff4dbfffFish|r  |cff50c8ffYou|r")
    legend = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    legend:SetPoint("TOPLEFT", lt, "BOTTOMLEFT", 0, -6)
    legend:SetJustifyH("LEFT")
    legend:SetSpacing(3)
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.t = (self.t or 0) + elapsed
        if self.t > 0.25 then
            self.t = 0
            UpdatePlayer()
            local h = 64 + holder:GetHeight() + 12 + 14 + 6 + legend:GetStringHeight() + 16
            self:SetHeight(math.max(h, 200))
        end
    end)
    tiles, dots = {}, {}
end

function ns.ShowMap(name, byMap, preferred)
    if not frame then
        Create()
    end
    points, mapTitle = byMap or {}, name or ""
    -- make room: close the profession window while the map is up; it reopens on the same recipe
    local pf = _G.ProfessionsFrame
    local ts = C_TradeSkillUI
    if pf and pf:IsShown() and not held and ts and ts.GetBaseProfessionInfo
        and not (InCombatLockdown and InCombatLockdown()) then
        local ok, info = pcall(ts.GetBaseProfessionInfo)
        held = { prof = ok and info and info.professionID, recipe = ns.profRecipe }
        ns.mapHolding = true
        if not pcall(HideUIPanel, pf) then
            pf:Hide()
        end
    end
    if not frame.holdHooked then
        frame.holdHooked = true
        frame:HookScript("OnHide", function(self)
            local h = held
            held, ns.mapHolding = nil, nil
            local parent = self:GetParent()
            if not h or (parent and not parent:IsShown()) or (InCombatLockdown and InCombatLockdown()) then
                return
            end
            if not (h.recipe and ts.OpenRecipe and pcall(ts.OpenRecipe, h.recipe)) and h.prof and ts.OpenTradeSkill then
                pcall(ts.OpenTradeSkill, h.prof)
            end
        end)
    end
    wipe(zones)
    for m in pairs(points) do
        zones[#zones + 1] = m
    end
    table.sort(zones, function(a, b)
        if a == preferred or b == preferred then
            return a == preferred
        end
        return #points[a] > #points[b]
    end)
    zoneIdx = 1
    frame:Show()
    Draw()
    frame.t = 1
end
