-- Layouts: the look of the addon. "classic" is the Blizzard-style look the addon has always had;
-- "modern" is the upcoming one. The player picks one in Settings > General ("layout"); it is read once
-- at login, so switching needs a /reload.
--
-- A layout only lists what it changes. Everything it leaves out falls back to classic, so a layout can
-- be filled in piece by piece:
--   media     folder (under the addon folder) its textures live in
--   textures  [name] = true (same file name in its own folder) or "OtherFile": the textures it brings.
--             Code asks ns.Tex("Arrow") and gets the active layout's file, or classic's
--   colors    overrides for the theme colours in ns.T (bg, panel, raised, hover, border, accent, text, dim...)
--   fonts     font objects by role (title, body, small, number)
--   metrics   sizes by role (rowHeight, subRowHeight, headerHeight, padding, radius)
--   widgets   [kind] = function(...) building that widget its own way. A builder gets the same arguments
--             as the classic one and must return an object with the same fields and methods:
--               Button(parent, label, width)            -> Button with :SetText / :SetEnabled
--               Tab(parent, label, width, icon)         -> Button with :SetText / :SetSelected / :SetEnabled
--               SideTab(parent, icon, tip)              -> CheckButton with :SetSelected
--               MainWindow(name)                        -> the main window frame (title, portrait, close)
--               BagWindow(name)                         -> the Bag Reagents window frame
--               TrackerWindow(name, title, onClose)     -> frame, closeButton; frame.head = layer for the
--                                                          title-bar buttons, frame.styled = true
local _, ns = ...

local BASE = "Interface\\AddOns\\GristForTheMill\\"

ns.Layouts = {
    classic = {
        key = "classic",
        title = "Classic",
        media = "Media\\",
        textures = {},
        colors = {},
        fonts = { title = "GameFontNormal", body = "GameFontHighlight", small = "GameFontHighlightSmall",
            number = "GameFontHighlightSmall" },
        metrics = { rowHeight = 28, subRowHeight = 20, headerHeight = 26, padding = 7, radius = 8 },
        widgets = {},
    },
    modern = {
        key = "modern",
        title = "Modern",
        media = "Media\\Modern\\",
        -- add a line here for every texture dropped into Media\Modern (a new file needs a client restart):
        --     Arrow = true, Pin = true, Lock = true, ...
        textures = {},
        colors = {},
        fonts = {},
        metrics = {},
        widgets = {},
    },
}

local active -- fixed at the first use after login, so one session never mixes two layouts

function ns.Layout()
    if active then
        return active
    end
    local chosen = ns.Layouts[ns.Get and ns.Get("layout") or "classic"] or ns.Layouts.classic
    if HelperDB then -- settings are readable: this is the layout for the session
        active = chosen
    end
    return chosen
end

-- path of a texture by name, in the active layout if it brings one, else classic's
function ns.Tex(name)
    local L = ns.Layout()
    local own = L.textures[name]
    if own then
        return BASE .. L.media .. (own == true and name or own)
    end
    return BASE .. ns.Layouts.classic.media .. name
end

-- font object / size for a role, falling back to classic
function ns.LayoutFont(role)
    return ns.Layout().fonts[role] or ns.Layouts.classic.fonts[role]
end

function ns.LayoutMetric(role)
    return ns.Layout().metrics[role] or ns.Layouts.classic.metrics[role]
end

-- the active layout's own builder for a kind of widget (nil: build it the classic way)
function ns.LayoutWidget(kind)
    return ns.Layout().widgets[kind]
end

-- at login, before any window exists: the active layout's colours replace the theme's
function ns.ApplyLayout()
    for key, c in pairs(ns.Layout().colors) do
        local t = ns.T and ns.T[key]
        if t then
            for i = 1, 4 do -- in place: other files hold on to these colour tables
                t[i] = c[i] or t[i]
            end
        end
    end
end
