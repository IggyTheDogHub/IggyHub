return (function()
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local MarketplaceService = game:GetService("MarketplaceService")
local StatsService = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer

local Library = {}

Library.Flags = {}
Library.Windows = {}
Library.AccentGradient = true
Library.AccentAngle = 360
Library.Shimmer = true
Library._accentGradients = {}

local function normalize(source, map)
    local opts = {}
    if type(source) == "string" then
        opts.Name = source
    elseif type(source) == "table" then
        for key, value in pairs(source) do
            opts[key] = value
        end
    end
    for from, to in pairs(map or {}) do
        if opts[to] == nil and opts[from] ~= nil then
            opts[to] = opts[from]
        end
    end
    if opts.Range then
        opts.Min = opts.Min or opts.Range[1]
        opts.Max = opts.Max or opts.Range[2]
    end
    return opts
end

local function finishElement(tab, opts, element, frame, kind)
    element._type = kind
    element._frame = frame
    element._window = tab and tab.Window
    element._listeners = element._listeners or {}
    local window = tab and tab.Window
    local searchText = opts.Name or opts.Text or opts.Title
    element._searchName = type(searchText) == "string" and searchText or ""
    element._searchKey = string.lower(element._searchName)
    if tab and tab._items then
        table.insert(tab._items, element)
    end
    if opts.Flag then
        Library.Flags[opts.Flag] = element
        if window then
            window:_flagCreated(opts.Flag, element)
        end
    end
    element._userVisible = opts.Visible ~= false
    function element:IsVisible()
        return element._userVisible
    end
    function element:_isShown()
        return element._userVisible and not (tab and tab._userVisible == false)
    end
    function element:SetVisible(visible)
        visible = visible and true or false
        if visible == element._userVisible or element._destroyed then
            return
        end
        element._userVisible = visible
        if not visible then
            if element._onHide then
                element._onHide()
            end
            if element.Open and type(element.SetOpen) == "function" then
                element:SetOpen(false)
            end
        end
        if frame then
            frame.Visible = visible
        end
        if window then
            window._controlsDirty = true
        end
    end
    if frame and not element._userVisible then
        frame.Visible = false
    end
    -- Tooltip: a string, or { Title, Text, Icon }. nil, false or "" hides it.
    function element:SetTooltip(tip)
        element._tooltip = tip
        if frame and window and not element._tooltipBound then
            element._tooltipBound = true
            window:_attachTooltip(element, frame)
        end
    end
    function element:GetTooltip()
        return element._tooltip
    end
    if opts.Tooltip ~= nil and opts.Tooltip ~= false then
        element:SetTooltip(opts.Tooltip)
    end
    function element:Destroy()
        if element._destroyed then
            return
        end
        element._destroyed = true
        if window and window._tipOwner == element then
            window:_hideTooltip()
        end
        for _, disconnect in ipairs(element._listeners) do
            disconnect()
        end
        element._listeners = {}
        if tab and tab._items then
            local index = table.find(tab._items, element)
            if index then
                table.remove(tab._items, index)
            end
        end
        if opts.Flag and Library.Flags[opts.Flag] == element then
            Library.Flags[opts.Flag] = nil
        end
        if window then
            window._controlsDirty = true
        end
        if frame then
            frame:Destroy()
        end
    end
    return element
end

Library.Theme = {
    Accent = Color3.fromRGB(250, 250, 250),
    Accent2 = Color3.fromRGB(0, 0, 0),
    Background = Color3.fromRGB(8, 8, 8),
    Surface = Color3.fromRGB(12, 12, 12),
    Surface2 = Color3.fromRGB(16, 16, 16),
    Surface3 = Color3.fromRGB(24, 24, 24),
    Stroke = Color3.fromRGB(30, 30, 30),
    StrokeHover = Color3.fromRGB(70, 70, 70),
    Outline = Color3.fromRGB(36, 36, 36),
    AccentDark = Color3.fromRGB(14, 14, 14),
    Text = Color3.fromRGB(250, 250, 250),
    Muted = Color3.fromRGB(130, 130, 130),
    Warning = Color3.fromRGB(240, 176, 108),
    Success = Color3.fromRGB(150, 220, 170),
    Error = Color3.fromRGB(240, 120, 120),
    CardHeader = Color3.fromRGB(24, 24, 24),
    TabStructure = Color3.fromRGB(12, 12, 12),
}
Library.DefaultTheme = "BBC"

-- Order decides which key wins when two theme colors are identical.
local THEME_KEYS = {
    "Accent", "Accent2", "Background", "Surface", "Surface2", "Surface3",
    "Stroke", "StrokeHover", "Outline", "Text", "Muted", "Warning", "Success", "Error",
    "CardHeader", "TabStructure",
}

local function rgb(r, g, b)
    return Color3.fromRGB(r, g, b)
end

-- Muted text is drawn small, so lift it toward Text until it clears WCAG AA
-- (4.5:1) against Surface2, the lightest surface it usually sits on.
function Library._readableMuted(muted, text, surface)
    local function luminance(color)
        local function channel(v)
            return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
        end
        return 0.2126 * channel(color.R) + 0.7152 * channel(color.G) + 0.0722 * channel(color.B)
    end
    local back = luminance(surface)
    for step = 0, 20 do
        local candidate = muted:Lerp(text, step / 20)
        local front = luminance(candidate)
        if (math.max(front, back) + 0.05) / (math.min(front, back) + 0.05) >= 4.6 then
            return candidate
        end
    end
    return text
end

local function preset(background, surface, surface2, surface3, strokeColor, strokeHover, accent, accentDark, text, muted, accent2, outline, cardHeader, tabStructure)
    local acc = rgb(table.unpack(accent))
    local mut = rgb(table.unpack(muted))
    local txt = rgb(table.unpack(text))
    local srf2 = rgb(table.unpack(surface2))
    local strk = rgb(table.unpack(strokeColor))
    local srf3 = rgb(table.unpack(surface3))
    local srf = rgb(table.unpack(surface))
    local acc2 = accent2 and rgb(table.unpack(accent2)) or Color3.new(
        (acc.R * 0.7 + mut.R * 0.3),
        (acc.G * 0.7 + mut.G * 0.3),
        (acc.B * 0.7 + mut.B * 0.3)
    )
    local outl = outline and rgb(table.unpack(outline)) or Color3.new(
        math.min(1, strk.R * 1.25),
        math.min(1, strk.G * 1.25),
        math.min(1, strk.B * 1.25)
    )
    return {
        Background = rgb(table.unpack(background)),
        Surface = srf,
        Surface2 = srf2,
        Surface3 = srf3,
        Stroke = strk,
        StrokeHover = rgb(table.unpack(strokeHover)),
        Accent = acc,
        Accent2 = acc2,
        Outline = outl,
        AccentDark = rgb(table.unpack(accentDark)),
        Text = txt,
        Muted = Library._readableMuted(mut, txt, srf2),
        CardHeader = cardHeader and rgb(table.unpack(cardHeader)) or srf3,
        TabStructure = tabStructure and rgb(table.unpack(tabStructure)) or srf,
    }
end

Library.ThemePresets = {
    -- Colours here must not be pure white, pure black or any other colour the
    -- library hard-codes, or those objects would get bound to the theme.
    Midnight = preset({ 15, 18, 26 }, { 18, 22, 31 }, { 22, 26, 37 }, { 37, 44, 60 }, { 34, 40, 55 }, { 70, 84, 112 }, { 128, 160, 246 }, { 14, 18, 30 }, { 228, 232, 242 }, { 116, 126, 148 }),
    Ocean = preset({ 12, 20, 24 }, { 15, 24, 29 }, { 18, 29, 35 }, { 31, 48, 56 }, { 29, 44, 52 }, { 58, 92, 104 }, { 110, 214, 222 }, { 10, 24, 28 }, { 226, 238, 240 }, { 108, 134, 140 }),
    Rose = preset({ 22, 15, 18 }, { 27, 18, 22 }, { 32, 21, 26 }, { 48, 34, 40 }, { 45, 30, 37 }, { 98, 64, 78 }, { 246, 160, 186 }, { 30, 14, 20 }, { 240, 228, 232 }, { 138, 112, 120 }),
    Emerald = preset({ 13, 20, 17 }, { 16, 24, 20 }, { 20, 29, 24 }, { 33, 47, 40 }, { 30, 44, 37 }, { 62, 96, 78 }, { 132, 226, 170 }, { 12, 26, 18 }, { 228, 240, 233 }, { 110, 136, 122 }),
    Amber = preset({ 22, 18, 13 }, { 27, 22, 16 }, { 32, 26, 19 }, { 49, 41, 31 }, { 46, 38, 28 }, { 100, 82, 58 }, { 246, 196, 120 }, { 30, 22, 10 }, { 242, 236, 226 }, { 140, 126, 106 }),
    Mono = preset({ 16, 16, 17 }, { 20, 20, 21 }, { 25, 25, 26 }, { 40, 40, 42 }, { 38, 38, 40 }, { 84, 84, 88 }, { 236, 236, 240 }, { 20, 20, 22 }, { 234, 234, 236 }, { 122, 122, 128 }, { 0, 0, 0 }),
    Nebula = preset({ 14, 12, 28 }, { 18, 15, 35 }, { 23, 19, 43 }, { 39, 32, 68 }, { 35, 29, 62 }, { 84, 68, 140 }, { 199, 125, 255 }, { 22, 10, 40 }, { 236, 230, 252 }, { 124, 114, 160 }),
    Synthwave = preset({ 20, 12, 30 }, { 25, 15, 37 }, { 31, 18, 45 }, { 52, 30, 72 }, { 47, 27, 66 }, { 110, 58, 150 }, { 255, 94, 198 }, { 38, 8, 30 }, { 250, 232, 246 }, { 150, 118, 160 }),
    BBC = preset({ 8, 8, 8 }, { 12, 12, 12 }, { 16, 16, 16 }, { 24, 24, 24 }, { 30, 30, 30 }, { 70, 70, 70 }, { 250, 250, 250 }, { 14, 14, 14 }, { 250, 250, 250 }, { 130, 130, 130 }, { 0, 0, 0 }, { 36, 36, 36 }),
    Velvet = preset({ 20, 10, 16 }, { 25, 12, 20 }, { 31, 15, 25 }, { 50, 25, 40 }, { 46, 23, 37 }, { 104, 52, 82 }, { 222, 110, 170 }, { 30, 8, 20 }, { 244, 228, 238 }, { 142, 106, 126 }),
    Crimson = preset({ 18, 10, 12 }, { 23, 12, 15 }, { 28, 14, 18 }, { 46, 24, 29 }, { 42, 22, 27 }, { 104, 46, 56 }, { 244, 74, 94 }, { 32, 8, 12 }, { 244, 230, 232 }, { 142, 106, 112 }),
    Sunset = preset({ 22, 13, 14 }, { 27, 16, 17 }, { 33, 19, 21 }, { 52, 31, 32 }, { 48, 28, 30 }, { 112, 62, 58 }, { 255, 138, 92 }, { 34, 14, 8 }, { 248, 234, 228 }, { 150, 118, 110 }),
    Gold = preset({ 14, 13, 11 }, { 18, 17, 14 }, { 23, 21, 17 }, { 38, 35, 28 }, { 35, 32, 26 }, { 92, 80, 54 }, { 232, 196, 122 }, { 30, 22, 8 }, { 240, 234, 222 }, { 136, 126, 106 }),
    Cyber = preset({ 13, 13, 15 }, { 17, 17, 19 }, { 21, 21, 24 }, { 36, 36, 40 }, { 33, 33, 37 }, { 86, 84, 70 }, { 250, 226, 72 }, { 30, 26, 4 }, { 240, 240, 232 }, { 126, 124, 118 }),
    Toxic = preset({ 11, 14, 11 }, { 14, 18, 14 }, { 18, 23, 18 }, { 31, 39, 30 }, { 28, 36, 28 }, { 74, 98, 60 }, { 184, 255, 74 }, { 18, 30, 6 }, { 232, 242, 228 }, { 116, 134, 110 }),
    Matcha = preset({ 16, 19, 14 }, { 20, 23, 17 }, { 24, 28, 21 }, { 40, 46, 34 }, { 37, 42, 31 }, { 84, 98, 70 }, { 176, 214, 140 }, { 18, 26, 10 }, { 236, 240, 228 }, { 128, 136, 116 }),
    Aurora = preset({ 10, 20, 22 }, { 12, 25, 27 }, { 15, 30, 33 }, { 26, 50, 53 }, { 24, 45, 48 }, { 50, 104, 104 }, { 94, 240, 180 }, { 6, 30, 22 }, { 224, 246, 240 }, { 102, 142, 134 }),
    Frost = preset({ 13, 17, 23 }, { 16, 21, 28 }, { 20, 26, 34 }, { 34, 43, 56 }, { 31, 40, 52 }, { 72, 92, 118 }, { 164, 214, 255 }, { 12, 22, 34 }, { 230, 238, 246 }, { 114, 128, 146 }),
    Abyss = preset({ 7, 11, 22 }, { 9, 14, 28 }, { 12, 18, 35 }, { 22, 31, 58 }, { 20, 28, 52 }, { 44, 64, 120 }, { 72, 148, 255 }, { 6, 14, 34 }, { 226, 234, 250 }, { 100, 116, 152 }),
    -- Seasonal and themed palettes.
    Halloween = preset({ 18, 12, 20 }, { 23, 15, 25 }, { 28, 18, 30 }, { 46, 30, 48 }, { 43, 28, 44 }, { 104, 62, 40 }, { 255, 138, 36 }, { 36, 16, 4 }, { 246, 234, 224 }, { 146, 120, 128 }),
    Haunted = preset({ 14, 12, 20 }, { 18, 15, 26 }, { 22, 18, 32 }, { 38, 31, 54 }, { 35, 29, 50 }, { 70, 96, 64 }, { 156, 255, 110 }, { 14, 30, 8 }, { 232, 240, 228 }, { 120, 116, 140 }),
    Christmas = preset({ 12, 20, 15 }, { 15, 25, 19 }, { 19, 30, 23 }, { 32, 50, 38 }, { 30, 46, 35 }, { 100, 54, 56 }, { 236, 72, 80 }, { 34, 8, 10 }, { 240, 244, 236 }, { 120, 142, 128 }),
    Valentine = preset({ 24, 12, 17 }, { 30, 14, 21 }, { 36, 17, 25 }, { 58, 27, 40 }, { 54, 25, 37 }, { 130, 56, 84 }, { 255, 92, 140 }, { 40, 8, 20 }, { 252, 232, 240 }, { 160, 112, 132 }),
    Lunar = preset({ 22, 10, 10 }, { 28, 12, 12 }, { 34, 15, 14 }, { 54, 24, 22 }, { 50, 22, 20 }, { 130, 92, 40 }, { 246, 196, 84 }, { 38, 16, 6 }, { 250, 236, 222 }, { 160, 120, 108 }),
    Tropical = preset({ 10, 22, 24 }, { 12, 27, 30 }, { 15, 33, 36 }, { 26, 54, 58 }, { 24, 50, 54 }, { 44, 110, 110 }, { 255, 170, 90 }, { 36, 18, 6 }, { 232, 246, 244 }, { 104, 144, 142 }),
    Dracula = preset({ 24, 25, 33 }, { 29, 30, 40 }, { 34, 36, 47 }, { 52, 55, 70 }, { 48, 50, 64 }, { 98, 114, 164 }, { 189, 147, 249 }, { 26, 18, 44 }, { 246, 246, 238 }, { 126, 132, 168 }),
    Coffee = preset({ 20, 16, 13 }, { 25, 20, 16 }, { 30, 24, 19 }, { 48, 39, 31 }, { 45, 36, 29 }, { 104, 82, 62 }, { 214, 170, 124 }, { 32, 22, 12 }, { 240, 230, 218 }, { 142, 124, 108 }),
}

Library.ThemeName = "Mono"

Library.Assets = {
    Shadow = "rbxassetid://6014261993",
    Glow = "rbxassetid://8992230677",
    Logo = "rbxassetid://103859712365480",
}

local LUCIDE_URL = "https://raw.githubusercontent.com/Footagesus/Icons/refs/heads/main/lucide/dist/Icons.lua"
local lucideSet = nil

local function loadLucide()
    if lucideSet ~= nil then
        return lucideSet
    end
    local ok, result = pcall(function()
        local source = game:HttpGet(LUCIDE_URL)
        return loadstring(source)()
    end)
    if ok and type(result) == "table" then
        lucideSet = result
    else
        lucideSet = false
        warn("[RealIggyLib] lucide icons unavailable: " .. tostring(result))
    end
    return lucideSet
end

local FONT_PRESETS = {
    ValleySans = {
        Regular = "https://raw.githubusercontent.com/HelsinkiTypeStudio/valley-sans/main/fonts/ttf/ValleySans-Regular.ttf",
        Medium = "https://raw.githubusercontent.com/HelsinkiTypeStudio/valley-sans/main/fonts/ttf/ValleySans-Medium.ttf",
        SemiBold = "https://raw.githubusercontent.com/HelsinkiTypeStudio/valley-sans/main/fonts/ttf/ValleySans-SemiBold.ttf",
    },
}

local FONT_WEIGHTS = {
    Regular = { 400, Enum.FontWeight.Regular },
    Medium = { 500, Enum.FontWeight.Medium },
    SemiBold = { 600, Enum.FontWeight.SemiBold },
    Bold = { 700, Enum.FontWeight.Bold },
}

function Library:LoadFont(opts)
    opts = normalize(opts, {})
    if type(writefile) ~= "function" or type(isfile) ~= "function" or typeof(getcustomasset) ~= "function" then
        warn("[RealIggyLib] custom fonts need writefile, isfile and getcustomasset")
        return false
    end
    local name = opts.Name or "CustomFont"
    local weights = opts.Weights or FONT_PRESETS[name]
    if type(weights) ~= "table" then
        warn("[RealIggyLib] no font weights for " .. name)
        return false
    end
    local folder = opts.Folder or "RealIggyFonts"
    pcall(function()
        if type(isfolder) == "function" and type(makefolder) == "function" and not isfolder(folder) then
            makefolder(folder)
        end
    end)
    local faces = {}
    for weightName, url in pairs(weights) do
        local info = FONT_WEIGHTS[weightName]
        if info then
            local path = folder .. "/" .. name .. "-" .. weightName .. ".ttf"
            local ok = true
            if not isfile(path) then
                ok = pcall(function()
                    writefile(path, game:HttpGet(url))
                end)
            end
            if ok then
                table.insert(faces, { name = weightName, weight = info[1], style = "normal", assetId = getcustomasset(path) })
            else
                warn("[RealIggyLib] could not download " .. weightName .. " weight of " .. name)
            end
        end
    end
    if #faces == 0 then
        return false
    end
    local familyPath = folder .. "/" .. name .. ".json"
    local okWrite = pcall(function()
        writefile(familyPath, HttpService:JSONEncode({ name = name, faces = faces }))
    end)
    if not okWrite then
        return false
    end
    local family = getcustomasset(familyPath)
    local function face(weightName, fallback)
        local info = FONT_WEIGHTS[weightName]
        if info and weights[weightName] then
            return Font.new(family, info[2])
        end
        return fallback
    end
    Library.Fonts.Regular = face("Regular", Library.Fonts.Regular)
    Library.Fonts.Medium = face("Medium", face("Regular", Library.Fonts.Medium))
    Library.Fonts.Bold = face("SemiBold", face("Bold", Library.Fonts.Bold))
    return true
end

function Library:PreloadIcons()
    return loadLucide() ~= false
end

-- Numbers, digit strings and asset URLs are custom images; anything else is
-- a lucide name.
local function assetId(value)
    if type(value) == "number" then
        return "rbxassetid://" .. string.format("%.0f", value)
    end
    if type(value) == "string" then
        if value:match("^%d+$") then
            return "rbxassetid://" .. value
        end
        if value:find("^rbxassetid://") or value:find("^rbxasset://") or value:find("^rbxthumb://") or value:find("^http") then
            return value
        end
        if typeof(getcustomasset) == "function" and type(isfile) == "function" and isfile(value) then
            return getcustomasset(value)
        end
    end
    return nil
end

-- Returns image, rect offset, rect size, whether it is a custom image, and
-- whether that custom image should still take the theme tint.
local function resolveIcon(icon)
    if typeof(icon) == "table" then
        return assetId(icon.Image) or icon.Image, icon.RectOffset, icon.RectSize, true, icon.Tint == true
    end
    local asset = assetId(icon)
    if asset then
        return asset, nil, nil, true, false
    end
    if type(icon) ~= "string" then
        return nil
    end
    local name = icon:gsub("^lucide:", "")
    local set = loadLucide()
    if not set then
        return nil
    end
    local entry = (set.Icons and set.Icons[name]) or set[name]
    if type(entry) == "table" then
        local image = entry.Image
        if type(image) == "number" then
            image = "rbxassetid://" .. tostring(image)
        end
        local sheet = (set.Spritesheets and set.Spritesheets[tostring(image)]) or image
        return sheet, entry.ImageRectPosition, entry.ImageRectSize
    elseif type(entry) == "string" then
        return entry
    end
    warn("[RealIggyLib] unknown lucide icon: " .. name)
    return nil
end

local BUTTON_HINT_ICON = "chevron-right"

local FONT_FAMILY = "rbxasset://fonts/families/BuilderSans.json"
Library.Fonts = {
    Regular = Font.new(FONT_FAMILY, Enum.FontWeight.Regular),
    Medium = Font.new(FONT_FAMILY, Enum.FontWeight.Medium),
    Bold = Font.new(FONT_FAMILY, Enum.FontWeight.SemiBold),
    SemiBold = Font.new(FONT_FAMILY, Enum.FontWeight.SemiBold),
}

local Theme = Library.Theme
local Assets = Library.Assets

-- The OuroFlow mark, embedded as a 256px grayscale PNG so it needs no upload.
-- It is written to the workspace once and loaded with getcustomasset; the
-- white-to-grey shading is multiplied by the theme accent like the old logo.
-- Without file functions the uploaded asset above stays in use.
local EMBEDDED_LOGO = "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"

local function decodeBase64(data)
    local lookup = {}
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, #alphabet do
        lookup[alphabet:byte(i)] = i - 1
    end
    local out = {}
    for i = 1, #data, 4 do
        local a, b, c, d = data:byte(i, i + 3)
        local n = lookup[a] * 262144 + lookup[b] * 4096 + (lookup[c] or 0) * 64 + (lookup[d] or 0)
        local x, y, z = n // 65536, n // 256 % 256, n % 256
        if d ~= 61 then
            out[#out + 1] = string.char(x, y, z)
        elseif c ~= 61 then
            out[#out + 1] = string.char(x, y)
        else
            out[#out + 1] = string.char(x)
        end
    end
    return table.concat(out)
end

pcall(function()
    if typeof(getcustomasset) ~= "function" then
        return
    end
    if type(isfile) == "function" and isfile("iggy_logo.png") then
        local asset = getcustomasset("iggy_logo.png")
        if type(asset) == "string" and asset ~= "" then
            Assets.Logo = asset
            return
        end
    end
    if type(writefile) ~= "function" then
        return
    end
    local folder = "RealIggyAssets"
    if type(isfolder) == "function" and type(makefolder) == "function" and not isfolder(folder) then
        makefolder(folder)
    end
    local path = folder .. "/IggyLogo.png"
    local png = decodeBase64(EMBEDDED_LOGO)
    local fresh = type(isfile) == "function" and type(readfile) == "function" and isfile(path) and readfile(path) == png
    if not fresh then
        writefile(path, png)
    end
    local asset = getcustomasset(path)
    if type(asset) == "string" and asset ~= "" then
        Assets.Logo = asset
    end
end)
local Fonts = Library.Fonts

local TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
Library.Touch = TOUCH

local SIDEBAR_WIDTH = 188
local HEADER_HEIGHT = 62
local TAB_TILE_HEIGHT = 34
local CARD_HEIGHT = TOUCH and 54 or 48
local CARD_HEIGHT_DESC = TOUCH and 70 or 64
local DROPDOWN_OPTION_HEIGHT = TOUCH and 40 or 34
local CHIP_HEIGHT = TOUCH and 34 or 28
local PROFILE_HEIGHT = 64
local SEARCH_WIDTH = 176
local STACK_BELOW = 440

-- Elements read their geometry from one of these. Cards stand alone on a tab,
-- rows sit flush inside a groupbox.
local METRICS = {
    Card = {
        Compact = false,
        Height = CARD_HEIGHT,
        DescHeight = CARD_HEIGHT_DESC,
        Chip = CHIP_HEIGHT,
        Option = DROPDOWN_OPTION_HEIGHT,
        TextSize = 14,
        DescSize = 13,
        TitleHeight = 18,
        DescGap = 20,
        DescLine = 17,
        Slider = CARD_HEIGHT_DESC,
    },
    Row = {
        Compact = true,
        Height = TOUCH and 40 or 32,
        DescHeight = TOUCH and 54 or 46,
        Chip = TOUCH and 30 or 24,
        Option = TOUCH and 34 or 28,
        TextSize = 13,
        DescSize = 12,
        TitleHeight = 16,
        DescGap = 17,
        DescLine = 15,
        Slider = TOUCH and 54 or 46,
    },
}

local tweenInfoCache = {}

-- Theme bindings: every instance property painted with a theme color is
-- remembered by theme key, so SetTheme can repaint the whole UI live.
-- Held strongly: an Instance's Lua handle can be collected while the Instance
-- still exists, which would silently drop it from a weak table. Destroyed
-- objects are pruned instead, once they have been parentless for two sweeps.
local themeBindings = {}
local themeHooks = {}
local themeLookup = {}
local orphanMarks = {}
local bindingCount = 0
local sweepAt = 4000

local function pruneTable(map, counted)
    for object in pairs(map) do
        if typeof(object) ~= "Instance" then
            continue
        end
        if object.Parent == nil then
            if orphanMarks[object] then
                map[object] = nil
                orphanMarks[object] = nil
                if counted then
                    bindingCount -= 1
                end
            else
                orphanMarks[object] = true
            end
        else
            orphanMarks[object] = nil
        end
    end
end

local function sweepBindings()
    pruneTable(themeBindings, true)
    pruneTable(themeHooks, false)
    sweepAt = math.max(4000, bindingCount * 2)
end

local function bindTheme(object, property, themeKey)
    local bound = themeBindings[object]
    if not bound then
        bound = {}
        themeBindings[object] = bound
        bindingCount += 1
        if bindingCount >= sweepAt then
            sweepBindings()
        end
    end
    bound[property] = themeKey
end

local function colorKey(color)
    return math.floor(color.R * 255 + 0.5) .. "," .. math.floor(color.G * 255 + 0.5) .. "," .. math.floor(color.B * 255 + 0.5)
end

local function rebuildThemeLookup()
    table.clear(themeLookup)
    for index = #THEME_KEYS, 1, -1 do
        local name = THEME_KEYS[index]
        if name ~= "Accent2" and name ~= "CardHeader" and name ~= "TabStructure" then
            themeLookup[colorKey(Library.Theme[name])] = name
        end
    end
end
rebuildThemeLookup()

local function bindColors(object, props)
    for property, value in pairs(props) do
        if typeof(value) == "Color3" then
            local name = themeLookup[colorKey(value)]
            local bound = themeBindings[object]
            if name then
                if not bound then
                    bound = {}
                    themeBindings[object] = bound
                    bindingCount += 1
                    if bindingCount >= sweepAt then
                        sweepBindings()
                    end
                end
                bound[property] = name
            elseif bound then
                bound[property] = nil
            end
        end
    end
end

-- Repaints every bound property from the colours on screen to the new theme.
-- One Heartbeat loop lerps each theme key once per frame and assigns the
-- result, instead of creating a tween per object, which hitched the frame the
-- theme changed on large UIs. A change mid-fade picks up from what is shown.
local shownTheme = table.clone(Library.Theme)
local themeDriver = nil

local function paintBinding(object, bound, colors)
    for property, name in pairs(bound) do
        if (property == "ImageColor3" or property == "BackgroundColor3") and object:IsA("GuiObject") then
            local grad = object:FindFirstChild("AccentGradient")
            if grad and grad.Enabled then
                continue
            end
        end
        local color = colors[name]
        if color then
            object[property] = color
        end
    end
end

local function paintBindings(colors)
    for object, bound in pairs(themeBindings) do
        pcall(paintBinding, object, bound, colors)
    end
end

local function driveTheme(duration)
    if themeDriver then
        themeDriver:Disconnect()
        themeDriver = nil
    end
    local from, colors = {}, {}
    for _, name in ipairs(THEME_KEYS) do
        local target = Library.Theme[name]
        local current = shownTheme[name] or target
        if current ~= target then
            from[name] = current
            colors[name] = current
        end
    end
    local function finish()
        for _, name in ipairs(THEME_KEYS) do
            colors[name] = Library.Theme[name]
            shownTheme[name] = Library.Theme[name]
        end
        paintBindings(colors)
    end
    if duration <= 0 or next(from) == nil then
        finish()
        return
    end
    local elapsed = 0
    themeDriver = RunService.Heartbeat:Connect(function(deltaTime)
        elapsed += deltaTime
        if elapsed >= duration then
            themeDriver:Disconnect()
            themeDriver = nil
            finish()
            return
        end
        local alpha = 1 - (1 - elapsed / duration) ^ 5
        for name, start in pairs(from) do
            local color = start:Lerp(Library.Theme[name], alpha)
            colors[name] = color
            shownTheme[name] = color
        end
        paintBindings(colors)
    end)
end

-- Runs fn now and again whenever the theme changes, while owner exists.
local function onTheme(owner, fn)
    themeHooks[owner] = fn
    fn()
end

local function tween(object, props, duration, style, direction, raw)
    duration = duration or 0.2
    if object and object:IsA("ImageLabel") and object:FindFirstChild("AccentGradient") then
        local grad = object:FindFirstChild("AccentGradient")
        if grad and grad.Enabled and props.ImageColor3 then
            if props.ImageColor3 == Theme.Muted then
                props.ImageTransparency = props.ImageTransparency or 0.4
            elseif props.ImageColor3 == Theme.Accent or props.ImageColor3 == Theme.Text then
                props.ImageTransparency = props.ImageTransparency or 0
            end
            props.ImageColor3 = nil
            object.ImageColor3 = Color3.new(1, 1, 1)
            raw = true
        end
    end
    if not raw then
        bindColors(object, props)
    end
    if duration <= 0 then
        for key, value in pairs(props) do
            object[key] = value
        end
        return nil
    end
    style = style or Enum.EasingStyle.Quart
    direction = direction or Enum.EasingDirection.Out
    local key = duration .. style.Name .. direction.Name
    local info = tweenInfoCache[key]
    if not info then
        info = TweenInfo.new(duration, style, direction)
        tweenInfoCache[key] = info
    end
    local t = TweenService:Create(object, info, props)
    t:Play()
    return t
end

local function create(className, props, children)
    local inst = Instance.new(className)
    for key, value in pairs(props) do
        if key ~= "Parent" then
            inst[key] = value
        end
    end
    bindColors(inst, props)
    if children then
        for _, child in ipairs(children) do
            child.Parent = inst
        end
    end

    if props.Parent then
        inst.Parent = props.Parent
    end
    return inst
end

-- Corners in pixels follow the player's corner radius setting: each one
-- remembers the radius it was drawn at, and Library:SetCornerRadius rescales
-- them all. Scale corners (pills, circles) stay as they are.
Library.Roundness = 1
-- A strong table: weak keys would drop the Lua handles for corners nothing
-- else in Lua holds, and those corners would never rescale. Destroyed ones
-- are pruned whenever the radius changes.
Library._cornerBases = {}

local function corner(parent, radius)
    radius = radius or UDim.new(0, 8)
    local object = create("UICorner", {
        CornerRadius = radius.Scale == 0 and UDim.new(0, math.floor(radius.Offset * Library.Roundness + 0.5)) or radius,
        Parent = parent,
    })
    if radius.Scale == 0 then
        Library._cornerBases[object] = radius.Offset
    end
    return object
end

-- A corner that ignores the setting, for shapes that animate their own
-- radius (the minimized island, the morph panels).
function Library._fixedCorner(parent, radius)
    return create("UICorner", { CornerRadius = radius, Parent = parent })
end

-- The radius the window's own corners are drawn at right now.
function Library._radius(pixels)
    return math.floor(pixels * Library.Roundness + 0.5)
end

local function stroke(parent, color, transparency, thickness)
    return create("UIStroke", {
        Color = color or Theme.Stroke,
        Transparency = transparency or 0,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent,
    })
end

local function padding(parent, left, right, top, bottom)
    return create("UIPadding", {
        PaddingLeft = UDim.new(0, left or 0),
        PaddingRight = UDim.new(0, right or 0),
        PaddingTop = UDim.new(0, top or 0),
        PaddingBottom = UDim.new(0, bottom or 0),
        Parent = parent,
    })
end

local function label(props)
    local defaults = {
        BackgroundTransparency = 1,
        TextColor3 = Theme.Text,
        TextSize = 14,
        FontFace = Fonts.Medium,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }
    for key, value in pairs(props) do
        defaults[key] = value
    end
    return create("TextLabel", defaults)
end

local function glow(parent, size, position, transparency, rotation)
    local image = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = position,
        Size = size,
        BackgroundTransparency = 1,
        Image = Assets.Glow,
        ImageColor3 = Color3.fromRGB(226, 218, 230),
        ImageTransparency = 1,
        Visible = false,
        ZIndex = 0,
        Parent = parent,
    })
    local gradient = create("UIGradient", {
        Rotation = rotation or 90,
        Parent = image,
    })
    onTheme(gradient, function()
        gradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Theme.Accent)
    end)
    return image
end

local function edgeHighlight(parent)
    return create("Frame", {
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 0,
        Parent = parent,
    })
end

local SHIMMER_TWEEN_INFO = TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, 0)

function Library:GetAccentGradientColorSequence()
    local accent = Theme.Accent or Color3.fromRGB(236, 236, 240)
    local accent2 = Theme.Accent2 or Theme.Muted or Color3.fromRGB(122, 122, 128)
    if self.Shimmer then
        return ColorSequence.new({
            ColorSequenceKeypoint.new(0.0, accent),
            ColorSequenceKeypoint.new(0.5, accent2),
            ColorSequenceKeypoint.new(1.0, accent),
        })
    else
        return ColorSequence.new(accent, accent2)
    end
end

local function attachAccentGradient(parent, opts)
    opts = opts or {}
    local active = opts.Active ~= false

    local gradient = create("UIGradient", {
        Name = "AccentGradient",
        Rotation = Library.AccentAngle or 360,
        Color = Library:GetAccentGradientColorSequence(),
        Transparency = NumberSequence.new(0),
        Offset = Vector2.zero,
        Enabled = Library.AccentGradient and active,
        Parent = parent,
    })

    local shimmerTween = nil

    local controller = {
        Gradient = gradient,
        Active = active,
    }

    local function stopShimmer()
        if shimmerTween then
            shimmerTween:Cancel()
            shimmerTween = nil
        end
        gradient.Offset = Vector2.zero
    end

    local function startShimmer()
        stopShimmer()
        if Library.Shimmer and Library.AccentGradient and controller.Active then
            gradient.Offset = Vector2.new(-0.5, 0)
            shimmerTween = TweenService:Create(gradient, SHIMMER_TWEEN_INFO, {
                Offset = Vector2.new(0.5, 0)
            })
            shimmerTween:Play()
        end
    end

    local function updateParentColor()
        local isGrad = Library.AccentGradient and controller.Active
        if isGrad then
            if parent:IsA("ImageLabel") then
                parent.ImageColor3 = Color3.new(1, 1, 1)
            elseif parent:IsA("GuiObject") then
                parent.BackgroundColor3 = Color3.new(1, 1, 1)
            end
        else
            local themeColor
            if controller.Active then
                themeColor = opts.ThemeKey and Theme[opts.ThemeKey] or opts.FallbackColor or Theme.Accent
            else
                themeColor = opts.InactiveThemeKey and Theme[opts.InactiveThemeKey] or opts.InactiveColor or (parent:IsA("ImageLabel") and (opts.ThemeKey and Theme[opts.ThemeKey] or opts.FallbackColor or Theme.Accent) or Theme.Surface3)
            end
            if parent:IsA("ImageLabel") then
                parent.ImageColor3 = themeColor
            elseif parent:IsA("GuiObject") then
                parent.BackgroundColor3 = themeColor
            end
        end
    end

    function controller:SetActive(state, skipColor)
        controller.Active = state and true or false
        gradient.Enabled = Library.AccentGradient and controller.Active
        if not skipColor then
            updateParentColor()
        end
        if controller.Active and Library.Shimmer and Library.AccentGradient then
            startShimmer()
        else
            stopShimmer()
        end
    end

    function controller:Update()
        if not parent.Parent then
            controller:Destroy()
            return
        end
        gradient.Rotation = Library.AccentAngle or 360
        gradient.Color = Library:GetAccentGradientColorSequence()
        gradient.Enabled = Library.AccentGradient and controller.Active
        updateParentColor()
        if controller.Active and Library.Shimmer and Library.AccentGradient then
            startShimmer()
        else
            stopShimmer()
        end
    end

    function controller:Destroy()
        stopShimmer()
        local idx = table.find(Library._accentGradients, controller)
        if idx then
            table.remove(Library._accentGradients, idx)
        end
        pcall(function() gradient:Destroy() end)
    end

    table.insert(Library._accentGradients, controller)
    updateParentColor()

    if active and Library.Shimmer and Library.AccentGradient then
        startShimmer()
    end

    return controller
end

function Library:SetAccentGradient(enabled)
    self.AccentGradient = enabled and true or false
    for _, grad in ipairs(self._accentGradients) do
        grad:Update()
    end
end

function Library:SetAccentAngle(angle)
    self.AccentAngle = tonumber(angle) or 360
    for _, grad in ipairs(self._accentGradients) do
        grad:Update()
    end
end

function Library:SetShimmer(enabled)
    self.Shimmer = enabled and true or false
    for _, grad in ipairs(self._accentGradients) do
        grad:Update()
    end
end

onTheme(Library, function()
    for _, grad in ipairs(Library._accentGradients) do
        grad:Update()
    end
end)


local CUSTOM_ICON_SCALE = 1.35

local function applyIcon(imageLabel, icon, fixedSize)
    local image, rectOffset, rectSize, custom, tint = resolveIcon(icon)
    if not image then
        return
    end
    imageLabel.Image = image
    imageLabel.ImageRectOffset = rectOffset or Vector2.zero
    imageLabel.ImageRectSize = rectSize or Vector2.zero
    -- The built-in logo is a brand dog logo and preserves original colors.
    if icon == Assets.Logo then
        tint = false
    end
    local keepColours = custom and not tint
    imageLabel:SetAttribute("CustomIcon", keepColours or nil)
    if keepColours then
        -- Original colours, and out of the theme's reach.
        tween(imageLabel, { ImageColor3 = Color3.new(1, 1, 1) }, 0)
    else
        imageLabel.ImageColor3 = Color3.fromRGB(255, 255, 255)
        attachAccentGradient(imageLabel, { Active = true })
    end
    -- Uploaded images usually carry transparent padding and read smaller than
    -- the lucide set, so they are drawn larger. A table icon can pick its own
    -- Scale. Brand logos pass fixedSize, their slots are already sized for them.
    local scale = custom and not fixedSize and icon ~= Assets.Logo and (typeof(icon) == "table" and tonumber(icon.Scale) or CUSTOM_ICON_SCALE) or 1
    local scaler = imageLabel:FindFirstChild("CustomIconScale")
    if scale ~= 1 then
        scaler = scaler or create("UIScale", { Name = "CustomIconScale", Parent = imageLabel })
        scaler.Scale = scale
    elseif scaler then
        scaler:Destroy()
    end
end

-- Selection state for icons: tinted icons change colour, custom images keep
-- their colours and dim instead.
local function tintIcon(imageLabel, color, active, duration)
    if imageLabel:GetAttribute("CustomIcon") then
        tween(imageLabel, { ImageTransparency = active and 0 or 0.4 }, duration)
    else
        local grad = imageLabel:FindFirstChild("AccentGradient")
        if grad and grad.Enabled then
            imageLabel.ImageColor3 = Color3.new(1, 1, 1)
            tween(imageLabel, { ImageTransparency = active and 0 or 0.4 }, duration, nil, nil, true)
        else
            tween(imageLabel, { ImageColor3 = color }, duration)
        end
    end
end

local function defaultParent()
    local hidden
    pcall(function()
        if typeof(gethui) == "function" then
            hidden = gethui()
        end
    end)
    if typeof(hidden) == "Instance" then
        return hidden
    end
    local core
    pcall(function()
        core = game:GetService("CoreGui")
        local probe = Instance.new("Folder")
        probe.Parent = core
        probe:Destroy()
    end)
    if core then
        return core
    end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local insetFrame, insetValue = nil, Vector2.zero
local function pointerPosition()
    local frame = time()
    if insetFrame ~= frame then
        insetFrame = frame
        insetValue = GuiService:GetGuiInset()
    end
    return UserInputService:GetMouseLocation() - insetValue
end

local function isPress(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function usingTouch()
    return UserInputService:GetLastInputType() == Enum.UserInputType.Touch
end

-- A press that turned into a scroll is not a tap. Returns a check to call
-- from the click handler.
local function tapGuard(button, getScroller)
    local startCanvas
    button.InputBegan:Connect(function(input)
        if isPress(input) then
            local frame = getScroller()
            startCanvas = frame and frame.CanvasPosition
        end
    end)
    return function()
        local frame = getScroller()
        return not (startCanvas and frame and (frame.CanvasPosition - startCanvas).Magnitude > 4)
    end
end

local function pointInside(point, object)
    local position, size = object.AbsolutePosition, object.AbsoluteSize
    return point.X >= position.X and point.X <= position.X + size.X
        and point.Y >= position.Y and point.Y <= position.Y + size.Y
end

local function isMove(input)
    return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

local function glowIcon(parent, icon, color, position)
    local holder = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = position,
        Size = UDim2.fromOffset(16, 16),
        BackgroundTransparency = 1,
        Parent = parent,
    })
    local image = create("ImageLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ImageColor3 = color,
        ScaleType = Enum.ScaleType.Fit,
        Parent = holder,
    })
    applyIcon(image, icon)
    return holder, image
end

local function arrowIndicator(parent, anchorX, offsetX)
    local holder = create("Frame", {
        AnchorPoint = Vector2.new(anchorX, 0.5),
        Position = UDim2.new(anchorX, offsetX, 0.5, 0),
        Size = UDim2.fromOffset(18, 18),
        BackgroundTransparency = 1,
        Parent = parent,
    })
    local indicator = {}
    local image = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(16, 16),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ScaleType = Enum.ScaleType.Fit,
        Parent = holder,
    })
    applyIcon(image, "chevron-down")
    if image.Image ~= "" then
        function indicator:Set(open)
            tween(image, {
                Rotation = open and 180 or 0,
                ImageColor3 = open and Theme.Accent or Theme.Muted,
            }, 0.3, Enum.EasingStyle.Quint)
        end
        return indicator
    end
    image:Destroy()
    local function glyph(rotation, transparency)
        return label({
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(18, 18),
            Text = "›",
            TextSize = 22,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextColor3 = Theme.Muted,
            TextTransparency = transparency,
            Rotation = rotation,
            Parent = holder,
        })
    end
    local down = glyph(90, 0)
    local up = glyph(270, 1)
    function indicator:Set(open)
        tween(down, { TextTransparency = open and 1 or 0 }, 0.2)
        tween(up, { TextTransparency = open and 0 or 1, TextColor3 = open and Theme.Accent or Theme.Muted }, 0.2)
    end
    return indicator
end

local ripplePool = {}

local function ripple(button)
    local mouse = pointerPosition()
    local diameter = math.max(button.AbsoluteSize.X, button.AbsoluteSize.Y) * 2.2
    local circle = table.remove(ripplePool)
    -- A pooled circle can't be reparented if it was destroyed along the way.
    if circle and not pcall(function()
        circle.Parent = nil
    end) then
        circle = nil
    end
    if not circle then
        circle = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
        })
        corner(circle, UDim.new(1, 0))
    end
    circle.Position = UDim2.fromOffset(mouse.X - button.AbsolutePosition.X, mouse.Y - button.AbsolutePosition.Y)
    circle.Size = UDim2.fromOffset(0, 0)
    circle.BackgroundColor3 = Theme.Accent
    circle.BackgroundTransparency = 0.82
    circle.ZIndex = button.ZIndex + 1
    circle.Parent = button
    tween(circle, { Size = UDim2.fromOffset(diameter, diameter), BackgroundTransparency = 1 }, 0.55)
    task.delay(0.55, function()
        -- A button destroyed mid-ripple takes the circle with it: drop it.
        if circle.Parent ~= button or not button.Parent then
            pcall(circle.Destroy, circle)
            return
        end
        circle.Parent = nil
        if #ripplePool < 4 then
            table.insert(ripplePool, circle)
        else
            circle:Destroy()
        end
    end)
end

local function flashStroke(strokeObject)
    if not strokeObject or strokeObject:GetAttribute("Hidden") then
        return
    end
    tween(strokeObject, { Color = Theme.Accent, Transparency = 0.2 }, 0.08)
    task.delay(0.12, function()
        tween(strokeObject, { Color = Theme.Stroke, Transparency = 0 }, 0.35)
    end)
end

local function hoverStroke(target, strokeObject)
    target.MouseEnter:Connect(function()
        tween(strokeObject, { Color = Theme.StrokeHover }, 0.12)
    end)
    target.MouseLeave:Connect(function()
        tween(strokeObject, { Color = Theme.Stroke }, 0.25)
    end)
end

local KEY_NAMES = {
    [Enum.KeyCode.LeftControl] = "LCtrl",
    [Enum.KeyCode.RightControl] = "RCtrl",
    [Enum.KeyCode.LeftShift] = "LShift",
    [Enum.KeyCode.RightShift] = "RShift",
    [Enum.KeyCode.LeftAlt] = "LAlt",
    [Enum.KeyCode.RightAlt] = "RAlt",
    [Enum.KeyCode.Return] = "Enter",
    [Enum.KeyCode.Escape] = "Esc",
    [Enum.KeyCode.Backspace] = "Backspace",
}

local function keyName(keyCode)
    if keyCode == nil then
        return "None"
    end
    return KEY_NAMES[keyCode] or keyCode.Name
end

local function safeCall(callback, ...)
    if type(callback) ~= "function" then
        return
    end
    local ok, err = pcall(callback, ...)
    if not ok then
        warn("[RealIggyLib] callback error: " .. tostring(err))
    end
end

-- Runs a user callback on its own thread and waits for it with task.wait.
-- A callback that yields inside an engine call (InvokeServer and the like)
-- resumes at game identity, which can no longer touch the GUI in CoreGui;
-- keeping that on a separate thread leaves the caller's identity intact.
local function isolatedCall(callback)
    local result = nil
    task.spawn(function()
        result = table.pack(pcall(callback))
    end)
    while result == nil do
        task.wait()
    end
    return table.unpack(result, 1, result.n)
end

local function numberFormat(min, max, step)
    local decimals = 0
    local text = tostring(step)
    local dot = text:find("%.")
    if dot then
        decimals = #text - dot
    end
    local pattern = "%." .. decimals .. "f"
    return {
        snap = function(value)
            value = math.floor(value / step + 0.5) * step
            return math.clamp(value, min, max)
        end,
        format = function(value)
            return string.format(pattern, value)
        end,
    }
end

local function metricsOf(tab)
    return tab._metrics or METRICS.Card
end

-- Width of a value control inside a groupbox row. Every dropdown and input in
-- a groupbox uses the same share of the row, so their left edges line up.
local function rowControlWidth(frame, window)
    local width = frame.AbsoluteSize.X / window.Scale.Scale
    return math.clamp(math.floor(width * 0.48), 90, 220)
end

local function card(tab, className, height, opts)
    local compact = metricsOf(tab).Compact
    local props = {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundColor3 = Theme.Surface2,
        BackgroundTransparency = compact and 1 or 0,
        BorderSizePixel = 0,
        LayoutOrder = tab:_nextOrder(),
        Parent = tab.List,
    }
    if className == "TextButton" then
        props.AutoButtonColor = false
        props.Text = ""
    end
    local frame = create(className, props)
    frame:SetAttribute("NoDrag", true)
    corner(frame)
    local frameStroke = stroke(frame, Theme.Stroke, compact and 1 or 0)
    if compact then
        frameStroke:SetAttribute("Hidden", true)
    end
    return frame, frameStroke
end

local function titleDesc(parent, name, desc, rightReserve, metrics)
    metrics = metrics or METRICS.Card
    local title, descLabel
    if desc then
        local top = math.floor((metrics.DescHeight - (metrics.DescGap + metrics.DescLine)) / 2)
        title = label({
            Position = UDim2.fromOffset(14, top),
            Size = UDim2.new(1, -(14 + rightReserve), 0, metrics.TitleHeight),
            Text = name,
            TextSize = metrics.TextSize,
            Parent = parent,
        })
        descLabel = label({
            Position = UDim2.fromOffset(14, top + metrics.DescGap),
            Size = UDim2.new(1, -(14 + rightReserve), 0, metrics.DescLine),
            Text = desc,
            TextSize = metrics.DescSize,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            Parent = parent,
        })
    else
        title = label({
            Position = UDim2.fromOffset(14, 0),
            Size = UDim2.new(1, -(14 + rightReserve), 1, 0),
            Text = name,
            TextSize = metrics.TextSize,
            Parent = parent,
        })
    end
    return title, descLabel
end

local function beginElement(tab, opts, map, className, rightReserve, fallbackName)
    opts = normalize(opts, map)
    local metrics = metricsOf(tab)
    local height = opts.Desc and metrics.DescHeight or metrics.Height
    local frame, frameStroke = card(tab, className or "Frame", height, opts)
    hoverStroke(frame, frameStroke)
    local title, descLabel
    if rightReserve then
        title, descLabel = titleDesc(frame, opts.Name or fallbackName, opts.Desc, rightReserve, metrics)
    end
    return opts, frame, frameStroke, height, title, descLabel
end

local function reserveRight(title, descLabel, width)
    if title then
        title.Size = UDim2.new(1, -(14 + width), title.Size.Y.Scale, title.Size.Y.Offset)
    end
    if descLabel then
        descLabel.Size = UDim2.new(1, -(14 + width), 0, descLabel.Size.Y.Offset)
    end
end

local Tab = {}
Tab.__index = Tab

function Tab:_nextOrder()
    self._order = self._order + 1
    return self._order
end

function Tab:Section(text)
    local visible = not (type(text) == "table" and text.Visible == false)
    if type(text) == "table" then
        text = text.Name or text.Title or ""
    end
    local inset = metricsOf(self).Compact and 14 or 2
    local holder = create("Frame", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        LayoutOrder = self:_nextOrder(),
        Parent = self.List,
    })
    local text_ = label({
        Position = UDim2.fromOffset(inset, 8),
        Size = UDim2.new(0, 0, 0, 16),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = string.upper(text),
        TextSize = 12,
        TextColor3 = Theme.Muted,
        TextTruncate = Enum.TextTruncate.None,
        Parent = holder,
    })
    local ruleInset = inset == 2 and 0 or inset
    local rule = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -ruleInset, 0, 16),
        Size = UDim2.new(1, -12, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        Parent = holder,
    })
    local function fitRule()
        rule.Size = UDim2.new(1, -(text_.AbsoluteSize.X / self.Window.Scale.Scale + inset + 12 + ruleInset), 0, 1)
    end
    text_:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitRule)
    task.defer(fitRule)
    return finishElement(self, { Visible = visible }, {
        Set = function(_, value)
            text_.Text = string.upper(value)
        end,
    }, holder, "Section")
end

function Tab:Divider(opts)
    local caption = type(opts) == "table" and (opts.Text or opts.Name) or type(opts) == "string" and opts or nil
    if caption then
        -- A centred caption with a rule on each side.
        local inset = metricsOf(self).Compact and 14 or 2
        local holder = create("Frame", {
            Size = UDim2.new(1, 0, 0, 18),
            BackgroundTransparency = 1,
            LayoutOrder = self:_nextOrder(),
            Parent = self.List,
        })
        local text_ = label({
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.new(0, 0, 0, 14),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = caption,
            TextSize = 11,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextTruncate = Enum.TextTruncate.None,
            Parent = holder,
        })
        padding(text_, 8, 8)
        local rules = {}
        for index, anchor in ipairs({ 0, 1 }) do
            rules[index] = create("Frame", {
                AnchorPoint = Vector2.new(anchor, 0.5),
                Position = UDim2.new(anchor, anchor == 0 and inset or -inset, 0.5, 0),
                Size = UDim2.new(0.5, -inset, 0, 1),
                BackgroundColor3 = Theme.Outline,
                BorderSizePixel = 0,
                Parent = holder,
            })
            bindTheme(rules[index], "BackgroundColor3", "Outline")
        end
        local function fitRules()
            local half = text_.AbsoluteSize.X / self.Window.Scale.Scale / 2
            for _, rule in ipairs(rules) do
                rule.Size = UDim2.new(0.5, -(inset + half), 0, 1)
            end
        end
        text_:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitRules)
        task.defer(fitRules)
        return finishElement(self, { Visible = not (type(opts) == "table" and opts.Visible == false) }, {
            Set = function(_, value)
                text_.Text = tostring(value)
            end,
        }, holder, "Divider")
    end
    local line = create("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Outline,
        BorderSizePixel = 0,
        LayoutOrder = self:_nextOrder(),
        Parent = self.List,
    })
    bindTheme(line, "BackgroundColor3", "Outline")
    if metricsOf(self).Compact then
        line.BackgroundTransparency = 1
        line.Size = UDim2.new(1, 0, 0, 9)
        local compactLine = create("Frame", {
            Position = UDim2.fromOffset(14, 4),
            Size = UDim2.new(1, -28, 0, 1),
            BackgroundColor3 = Theme.Outline,
            BorderSizePixel = 0,
            Parent = line,
        })
        bindTheme(compactLine, "BackgroundColor3", "Outline")
    end
    return finishElement(self, { Visible = not (type(opts) == "table" and opts.Visible == false) }, {}, line, "Divider")
end

function Tab:Label(opts)
    opts = normalize(opts, { Name = "Text", Title = "Text" })
    local text_ = label({
        Size = UDim2.new(1, 0, 0, 18),
        Text = Library._rich(opts.Text or ""),
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Library._color(opts.Color) or Theme.Muted,
        RichText = true,
        LayoutOrder = self:_nextOrder(),
        Parent = self.List,
    })
    if metricsOf(self).Compact then
        text_.TextSize = 12
        padding(text_, 14, 14)
    else
        padding(text_, 2)
    end
    local handle = {
        Set = function(_, value)
            text_.Text = Library._rich(value)
        end,
        Get = function()
            return text_.Text
        end,
        SetColor = function(_, color)
            tween(text_, { TextColor3 = Library._color(color) or Theme.Muted }, 0.25)
        end,
    }
    if type(opts.Update) == "function" then
        local rate = math.max(tonumber(opts.UpdateRate) or 1, 0.05)
        local running = true
        handle._listeners = handle._listeners or {}
        table.insert(handle._listeners, function()
            running = false
        end)
        task.spawn(function()
            while running and text_.Parent do
                local ok, value = isolatedCall(opts.Update)
                if ok and value ~= nil then
                    text_.Text = Library._rich(value)
                elseif not ok then
                    warn("[RealIggyLib] label update error: " .. tostring(value))
                end
                task.wait(rate)
            end
        end)
        function handle:SetUpdateRate(seconds)
            rate = math.max(tonumber(seconds) or rate, 0.05)
        end
    end
    return finishElement(self, opts, handle, text_, "Label")
end

function Tab:Paragraph(opts)
    opts = normalize(opts, { Title = "Name" })
    local frame = card(self, "Frame", 0, opts)
    frame.AutomaticSize = Enum.AutomaticSize.Y
    if metricsOf(self).Compact then
        padding(frame, 14, 14, 6, 8)
    else
        padding(frame, 14, 14, 11, 12)
    end
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
        Parent = frame,
    })
    label({
        Size = UDim2.new(1, 0, 0, 14),
        Text = opts.Name or "",
        LayoutOrder = 1,
        Parent = frame,
    })
    local content = label({
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = Library._rich(opts.Content or ""),
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None,
        TextYAlignment = Enum.TextYAlignment.Top,
        RichText = true,
        LayoutOrder = 2,
        Parent = frame,
    })
    return finishElement(self, opts, {
        Set = function(_, value)
            content.Text = Library._rich(value)
        end,
    }, frame, "Paragraph")
end

local function rowButton(tab, opts)
    local primary = opts.Style == "Primary"
    local boxHeight = TOUCH and 34 or 28
    local height = boxHeight + 6 + (opts.Desc and 16 or 0)
    local button = card(tab, "TextButton", height, opts)

    local box = create("Frame", {
        Position = UDim2.fromOffset(14, 3),
        Size = UDim2.new(1, -28, 0, boxHeight),
        BackgroundColor3 = primary and Theme.Accent or Theme.Surface3,
        BackgroundTransparency = primary and 0.12 or 0.45,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = button,
    })
    corner(box, UDim.new(0, 6))
    local boxStroke = stroke(box, primary and Theme.Accent or Theme.Stroke, primary and 0.4 or 0)

    local row = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Parent = box,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = row,
    })
    local textColor = primary and Theme.AccentDark or Theme.Text
    if opts.Icon then
        local image = create("ImageLabel", {
            Size = UDim2.fromOffset(14, 14),
            BackgroundTransparency = 1,
            ImageColor3 = primary and Theme.AccentDark or Theme.Accent,
            ScaleType = Enum.ScaleType.Fit,
            LayoutOrder = 1,
            Parent = row,
        })
        applyIcon(image, opts.Icon)
    end
    local title = label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = opts.Name or "Button",
        TextSize = 13,
        TextColor3 = textColor,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        Parent = row,
    })
    if opts.Desc then
        label({
            Position = UDim2.fromOffset(14, boxHeight + 6),
            Size = UDim2.new(1, -28, 0, 14),
            Text = opts.Desc,
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            Parent = button,
        })
    end

    local restBg = primary and 0.12 or 0.45
    button.MouseEnter:Connect(function()
        tween(box, { BackgroundTransparency = primary and 0 or 0.2 }, 0.12)
        tween(boxStroke, primary and { Transparency = 0 } or { Color = Theme.StrokeHover }, 0.12)
    end)
    button.MouseLeave:Connect(function()
        tween(box, { BackgroundTransparency = restBg }, 0.25)
        tween(boxStroke, primary and { Transparency = 0.4 } or { Color = Theme.Stroke }, 0.25)
    end)
    button.MouseButton1Click:Connect(function()
        ripple(box)
        safeCall(opts.Callback)
    end)

    return finishElement(tab, opts, {
        SetText = function(_, value)
            title.Text = value
        end,
    }, button, "Button")
end

function Tab:Button(opts)
    opts = normalize(opts, { Title = "Name", Description = "Desc" })
    if metricsOf(self).Compact then
        return rowButton(self, opts)
    end
    local primary = opts.Style == "Primary"
    local height = opts.Desc and CARD_HEIGHT_DESC or CARD_HEIGHT
    button.ClipsDescendants = true

    local buttonGradientController
    if primary then
        buttonGradientController = attachAccentGradient(button, { Active = true, FallbackColor = Theme.Accent, ThemeKey = "Accent" })
        bindTheme(button, "BackgroundColor3", "Accent")
        bindTheme(buttonStroke, "Color", "Accent")
        if not Library.AccentGradient then
            tween(button, { BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.12 }, 0)
        else
            tween(button, { BackgroundTransparency = 0.12 }, 0)
        end
        tween(buttonStroke, { Color = Theme.Accent }, 0)
        buttonStroke.Transparency = 0.4
        button.MouseEnter:Connect(function()
            tween(button, { BackgroundTransparency = 0 }, 0.12)
            tween(buttonStroke, { Transparency = 0 }, 0.12)
        end)
        button.MouseLeave:Connect(function()
            tween(button, { BackgroundTransparency = 0.12 }, 0.25)
            tween(buttonStroke, { Transparency = 0.4 }, 0.25)
        end)
    else
        hoverStroke(button, buttonStroke)
    end

    local textColor = primary and Theme.AccentDark or Theme.Text
    local iconOffset = 0
    if opts.Icon then
        glowIcon(button, opts.Icon, primary and Theme.AccentDark or Theme.Accent, UDim2.new(0, 14, 0.5, 0))
        iconOffset = 26
    end
    local title = titleDesc(button, opts.Name or "Button", opts.Desc, 30)
    if iconOffset > 0 then
        for _, child in ipairs(button:GetChildren()) do
            if child:IsA("TextLabel") then
                child.Position = child.Position + UDim2.fromOffset(iconOffset, 0)
                child.Size = child.Size - UDim2.fromOffset(iconOffset, 0)
            end
        end
    end
    if primary then
        for _, child in ipairs(button:GetChildren()) do
            if child:IsA("TextLabel") then
                tween(child, { TextColor3 = textColor }, 0)
            end
        end
    end

    glowIcon(button, BUTTON_HINT_ICON, primary and Theme.AccentDark or Theme.Muted, UDim2.new(1, -30, 0.5, 0))

    button.MouseButton1Click:Connect(function()
        ripple(button)
        safeCall(opts.Callback)
    end)

    local elem = finishElement(self, opts, {
        SetText = function(_, value)
            title.Text = value
        end,
    }, button, "Button")
    if buttonGradientController then
        table.insert(elem._listeners, function()
            buttonGradientController:Destroy()
        end)
    end
    return elem
end

function Tab:Toggle(opts)
    local button, buttonStroke
    opts, button, buttonStroke = beginElement(self, opts, { Title = "Name", Description = "Desc", CurrentValue = "Default", Value = "Default" }, "TextButton", 56, "Toggle")

    local pill = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -14, 0.5, 0),
        Size = TOUCH and UDim2.fromOffset(44, 24) or UDim2.fromOffset(36, 20),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = button,
    })
    corner(pill, UDim.new(1, 0))
    stroke(pill, Theme.Stroke)

    local knob = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 3, 0.5, 0),
        Size = TOUCH and UDim2.fromOffset(18, 18) or UDim2.fromOffset(14, 14),
        BackgroundColor3 = Theme.Muted,
        BorderSizePixel = 0,
        Parent = pill,
    })
    corner(knob, UDim.new(1, 0))
    local pillGradientController = attachAccentGradient(pill, {
        Active = opts.Default == true,
        ThemeKey = "Accent",
        InactiveThemeKey = "Surface3",
        InactiveColor = Theme.Surface3,
    })

    local self_ = { Value = opts.Default == true }

    local function render(animate)
        local on = self_.Value
        local duration = animate and 0.25 or 0
        local skipColor = animate and not (Library.AccentGradient and on)
        pillGradientController:SetActive(on, skipColor)
        if not (Library.AccentGradient and on) then
            tween(pill, { BackgroundColor3 = on and Theme.Accent or Theme.Surface3 }, duration)
        end
        local knobSize = TOUCH and 18 or 14
        tween(knob, {
            Position = on and UDim2.new(0, (TOUCH and 44 or 36) - 3 - knobSize, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
            BackgroundColor3 = on and Theme.AccentDark or Theme.Muted,
        }, duration, Enum.EasingStyle.Back)
        if animate then
            tween(knob, { Size = UDim2.fromOffset(knobSize + 4, knobSize - 2) }, 0.08)
            task.delay(0.08, function()
                tween(knob, { Size = UDim2.fromOffset(knobSize, knobSize) }, 0.2, Enum.EasingStyle.Back)
            end)
        end
    end

    local fromClick = false
    function self_:Set(value, silent)
        value = value == true
        if value == self_.Value then
            return
        end
        self_.Value = value
        render(true)
        if not fromClick then
            flashStroke(buttonStroke)
        end
        if not silent then
            safeCall(opts.Callback, value)
        end
    end

    function self_:Get()
        return self_.Value
    end

    render(false)
    button.MouseButton1Click:Connect(function()
        fromClick = true
        self_:Set(not self_.Value)
        fromClick = false
    end)

    local handle = finishElement(self, opts, self_, button, "Toggle")
    table.insert(handle._listeners, function()
        pillGradientController:Destroy()
    end)
    if self_.Value then
        safeCall(opts.Callback, true)
    end
    return handle
end

function Tab:Slider(opts)
    opts = normalize(opts, { Title = "Name", Description = "Desc", CurrentValue = "Default", Value = "Default", Increment = "Step" })
    local min = opts.Min or 0
    local max = opts.Max or 100
    local step = opts.Step or 1
    local suffix = opts.Suffix or ""
    local numbers = numberFormat(min, max, step)

    local metrics = metricsOf(self)
    local compact = metrics.Compact
    local height = metrics.Slider
    local frame, frameStroke = card(self, "Frame", height, opts)
    frame.ClipsDescendants = false
    hoverStroke(frame, frameStroke)

    label({
        Position = UDim2.fromOffset(14, compact and 5 or 12),
        Size = UDim2.new(1, -120, 0, 18),
        Text = opts.Name or "Slider",
        TextSize = metrics.TextSize,
        Parent = frame,
    })

    local valueChip = create("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, compact and -14 or -10, 0, compact and 2 or 9),
        Size = UDim2.fromOffset(40, 24),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = frame,
    })
    corner(valueChip, UDim.new(0, 6))
    local chipStroke = stroke(valueChip)
    local valueLabel = label({
        Size = UDim2.new(1, 0, 1, 0),
        TextSize = 13,
        TextColor3 = Theme.Accent,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextTruncate = Enum.TextTruncate.None,
        Parent = valueChip,
    })
    local valueBox = create("TextBox", {
        Position = UDim2.fromOffset(9, 0),
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = Theme.Text,
        TextSize = 13,
        FontFace = Fonts.Medium,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        Visible = false,
        Parent = valueChip,
    })
    create("UISizeConstraint", { MinSize = Vector2.new(14, 0), Parent = valueBox })
    local suffixLabel = label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = suffix,
        TextSize = 13,
        TextColor3 = Theme.Accent,
        TextTruncate = Enum.TextTruncate.None,
        Visible = false,
        Parent = valueChip,
    })
    local chipButton = create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 2,
        Parent = valueChip,
    })
    local editing = false
    local function fitChip(instant)
        local width
        if editing then
            width = 9 + valueBox.AbsoluteSize.X / (self.Window.Scale.Scale) + suffixLabel.TextBounds.X + 9
            suffixLabel.Position = UDim2.fromOffset(9 + valueBox.AbsoluteSize.X / (self.Window.Scale.Scale), 0)
        else
            width = valueLabel.TextBounds.X + 18
        end
        width = math.max(width, 36)
        if instant then
            valueChip.Size = UDim2.fromOffset(width, 24)
        else
            tween(valueChip, { Size = UDim2.fromOffset(width, 24) }, 0.2)
        end
    end
    valueLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
        if not editing then
            fitChip(false)
        end
    end)
    valueBox:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if editing then
            fitChip(false)
        end
    end)

    local function fraction()
        return (max - min) == 0 and 0 or ((self_ and self_.Value or min) - min) / (max - min)
    end

    local track = create("Frame", {
        Position = UDim2.new(0, 14, 0, height - (compact and 13 or 18)),
        Size = UDim2.new(1, -28, 0, 5),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        ClipsDescendants = false,
        ZIndex = 2,
        Parent = frame,
    })
    corner(track, UDim.new(1, 0))
    local fill = create("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = Library.AccentGradient and Color3.fromRGB(255, 255, 255) or Theme.Accent,
        BorderSizePixel = 0,
        ClipsDescendants = false,
        ZIndex = 2,
        Parent = track,
    })
    corner(fill, UDim.new(1, 0))

    local fillGradientController = attachAccentGradient(fill, { Active = true })

    local knob = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(12, 12),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        ZIndex = 4,
        Parent = track,
    })
    corner(knob, UDim.new(1, 0))


    local hit = create("TextButton", {
        Position = UDim2.new(0, 8, 0, height - (compact and 13 or 18) - (TOUCH and 19 or 13)),
        Size = UDim2.new(1, -16, 0, TOUCH and 40 or 28),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 4,
        Parent = frame,
    })

    local self_ = { Value = math.clamp(opts.Default or min, min, max) }
    local dragging = false
    chipButton.MouseEnter:Connect(function()
        tween(chipStroke, { Color = Theme.StrokeHover }, 0.12)
    end)
    chipButton.MouseLeave:Connect(function()
        if not valueBox:IsFocused() then
            tween(chipStroke, { Color = Theme.Stroke }, 0.2)
        end
    end)
    chipButton.MouseButton1Click:Connect(function()
        editing = true
        valueBox.Text = numbers.format(self_.Value)
        valueLabel.Visible = false
        valueBox.Visible = true
        suffixLabel.Visible = suffix ~= ""
        chipButton.Visible = false
        tween(chipStroke, { Color = Theme.StrokeHover }, 0.12)
        valueBox:CaptureFocus()
        task.defer(fitChip, false)
    end)
    valueBox.FocusLost:Connect(function()
        local typed = tonumber(valueBox.Text)
        editing = false
        valueBox.Visible = false
        suffixLabel.Visible = false
        valueLabel.Visible = true
        chipButton.Visible = true
        tween(chipStroke, { Color = Theme.Stroke }, 0.2)
        if typed then
            self_:Set(typed)
        end
        fitChip(false)
    end)
    local snap = numbers.snap

    local function fraction()
        return (max - min) == 0 and 0 or (self_.Value - min) / (max - min)
    end

    local function moveTo(frac, duration, style)
        style = style or Enum.EasingStyle.Linear
        tween(fill, { Size = UDim2.new(frac, 0, 1, 0) }, duration, style)
        tween(knob, { Position = UDim2.new(frac, 0, 0.5, 0) }, duration, style)
    end

    local function render(duration, style)
        moveTo(fraction(), duration, style)
        valueLabel.Text = numbers.format(self_.Value) .. suffix
    end

    local function settleTo(previousFrac)
        local target = fraction()
        local width = math.max(track.AbsoluteSize.X, 1)
        local overshoot = (target >= previousFrac and 1 or -1) * (5 / width)
        moveTo(math.clamp(target + overshoot, 0, 1), 0.22, Enum.EasingStyle.Quint)
        task.delay(0.22, function()
            if not dragging then
                moveTo(fraction(), 0.18, Enum.EasingStyle.Quint)
            end
        end)
        valueLabel.Text = numbers.format(self_.Value) .. suffix
    end

    local function bounceKnob()
        tween(knob, { Size = UDim2.fromOffset(14, 12) }, 0.08)
        task.delay(0.1, function()
            tween(knob, { Size = UDim2.fromOffset(12, 12) }, 0.25, Enum.EasingStyle.Quint)
        end)
    end

    function self_:Set(value, silent)
        value = snap(tonumber(value) or min)
        if value == self_.Value then
            return
        end
        local previousFrac = fraction()
        self_.Value = value
        if dragging then
            render(0.05)
        else
            settleTo(previousFrac)
            bounceKnob()
            flashStroke(frameStroke)
        end
        if not silent then
            safeCall(opts.Callback, value)
        end
    end

    function self_:Get()
        return self_.Value
    end

    local function updateFromX(x)
        local frac = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        self_:Set(min + (max - min) * frac)
    end

    hit.InputBegan:Connect(function(input)
        if isPress(input) then
            dragging = true
            self_.Dragging = true
            tween(knob, { Size = UDim2.fromOffset(16, 16) }, 0.15, Enum.EasingStyle.Back)
            updateFromX(pointerPosition().X)
        end
    end)

    self.Window:_listen("Changed", function(input)
        if dragging and isMove(input) then
            updateFromX(pointerPosition().X)
        end
    end, self_)

    self.Window:_listen("Ended", function(input)
        if dragging and isPress(input) then
            dragging = false
            self_.Dragging = false
            tween(knob, { Size = UDim2.fromOffset(12, 12) }, 0.2)
            safeCall(opts.OnRelease, self_.Value)
        end
    end, self_)

    self_.Value = snap(self_.Value)
    render(0)
    task.defer(fitChip, true)
    local elem = finishElement(self, opts, self_, frame, "Slider")
    table.insert(elem._listeners, function()
        fillGradientController:Destroy()
    end)
    return elem
end

function Tab:Dropdown(opts)
    opts = normalize(opts, { Title = "Name", Description = "Desc", CurrentOption = "Default", Value = "Default", MultipleOptions = "Multi", Values = "Options" })
    if opts.Multi and type(opts.Default) ~= "table" and opts.Default ~= nil then
        opts.Default = { opts.Default }
    elseif not opts.Multi and type(opts.Default) == "table" then
        opts.Default = opts.Default[1]
    end
    local multi = opts.Multi == true
    local options = opts.Options or {}
    local frame, frameStroke, height
    opts, frame, frameStroke, height = beginElement(self, opts, {}, "Frame")
    local metrics = metricsOf(self)
    local compact = metrics.Compact
    local chipHeight = metrics.Chip
    local window = self.Window
    local ROW = TOUCH and 40 or 30
    local MAX_ROWS = opts.MaxRows or 6
    -- Stacked (the default in compact rows): the chip spans the whole row,
    -- with the name (if any) above it.
    local stacked = compact and opts.Stacked ~= false
    local stackTop = 2
    if stacked then
        stackTop = (opts.Name or "") ~= "" and 20 or 2
        chipHeight = TOUCH and 34 or 30
        height = stackTop + chipHeight + 4
        frame.Size = UDim2.new(1, 0, 0, height)
    end

    local header = create("TextButton", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Parent = frame,
    })
    local titleLabel, descLabel
    if not stacked then
        titleLabel, descLabel = titleDesc(header, opts.Name or "Dropdown", opts.Desc, 180, metrics)
    elseif stackTop > 2 then
        titleLabel = label({
            Position = UDim2.fromOffset(14, 1),
            Size = UDim2.new(1, -28, 0, 16),
            Text = opts.Name,
            TextSize = metrics.TextSize,
            Parent = header,
        })
    end

    local chip = create("Frame", {
        AnchorPoint = stacked and Vector2.zero or Vector2.new(1, 0.5),
        Position = stacked and UDim2.fromOffset(14, stackTop) or UDim2.new(1, compact and -14 or -10, 0.5, 0),
        Size = UDim2.fromOffset(60, chipHeight),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = header,
    })
    corner(chip, UDim.new(0, 6))
    local chipStroke = stroke(chip)
    local valueLabel = label({
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(1, -34, 1, 0),
        TextColor3 = Theme.Muted,
        TextSize = 13,
        TextTruncate = Enum.TextTruncate.None,
        ClipsDescendants = true,
        Parent = chip,
    })
    local arrow = arrowIndicator(chip, 1, -6)
    local measure = label({
        Size = UDim2.fromOffset(0, chipHeight),
        AutomaticSize = Enum.AutomaticSize.X,
        TextSize = 13,
        Visible = false,
        Parent = chip,
    })
    local fullText = ""
    local function trimmed()
        local maxText = (stacked and frame.AbsoluteSize.X / window.Scale.Scale - 28 or compact and rowControlWidth(frame, window) or 190) - 10 - 34
        measure.Text = fullText
        if measure.TextBounds.X <= maxText then
            return fullText
        end
        local text = fullText
        while #text > 1 do
            text = text:sub(1, -2)
            measure.Text = text .. ".."
            if measure.TextBounds.X <= maxText then
                return text .. ".."
            end
        end
        return ".."
    end
    local function fitChip(instant)
        if stacked then
            chip.Size = UDim2.new(1, -28, 0, chipHeight)
            return
        end
        local width
        if compact then
            width = rowControlWidth(frame, window)
        else
            width = math.clamp(valueLabel.TextBounds.X + 10 + 34, 60, 190)
        end
        reserveRight(titleLabel, descLabel, width + (compact and 24 or 20))
        if instant then
            chip.Size = UDim2.fromOffset(width, chipHeight)
        else
            tween(chip, { Size = UDim2.fromOffset(width, chipHeight) }, 0.2)
        end
    end
    valueLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
        if not compact then
            fitChip(false)
        end
    end)
    if compact then
        -- The chip follows the row every frame; re-measuring the text waits
        -- until the width stops changing so resizing stays cheap.
        local lastWidth, pending = 0, false
        frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
            local width = frame.AbsoluteSize.X
            if width == lastWidth then
                return
            end
            lastWidth = width
            fitChip(true)
            if not pending then
                pending = true
                task.delay(0.12, function()
                    pending = false
                    valueLabel.Text = trimmed()
                end)
            end
        end)
    end

    -- Popup: floats over the window under the chip, with search, bulk
    -- actions for multi selection and a scrolling list of checkbox rows.
    -- The popup is a plain clipped frame that unfolds out of the chip, so text
    -- stays crisp. The shadow sits outside the clip.
    local popup = create("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Size = UDim2.fromOffset(220, 0),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 45,
        Parent = window.Body,
    })
    popup:SetAttribute("NoDrag", true)
    local popupShadow = create("ImageLabel", {
        Position = UDim2.fromOffset(-18, -12),
        Size = UDim2.new(1, 36, 1, 36),
        BackgroundTransparency = 1,
        Image = Assets.Shadow,
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450),
        Parent = popup,
    })
    local panel = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = popup,
    })
    corner(panel, UDim.new(0, 10))
    local panelStroke = stroke(panel, Theme.Stroke, 1)
    edgeHighlight(panel)
    local inner = create("Frame", {
        Size = UDim2.new(1, 0, 0, 120),
        BackgroundTransparency = 1,
        Parent = panel,
    })
    padding(inner, 8, 8, 8, 8)

    local searchHolder = create("Frame", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Parent = inner,
    })
    corner(searchHolder, UDim.new(0, 7))
    local searchStroke = stroke(searchHolder)
    local searchIconHolder, searchIcon = glowIcon(searchHolder, "search", Theme.Muted, UDim2.new(0, 10, 0.5, 0))
    searchIconHolder.Size = UDim2.fromOffset(14, 14)
    local searchBox = create("TextBox", {
        Position = UDim2.fromOffset(32, 0),
        Size = UDim2.new(1, -40, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        PlaceholderText = opts.SearchPlaceholder or "Search",
        PlaceholderColor3 = Theme.Muted,
        TextColor3 = Theme.Text,
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ClearTextOnFocus = false,
        Parent = searchHolder,
    })
    searchBox.Focused:Connect(function()
        tween(searchStroke, { Color = Theme.StrokeHover }, 0.15)
        tween(searchIcon, { ImageColor3 = Theme.Accent }, 0.15)
    end)
    searchBox.FocusLost:Connect(function()
        tween(searchStroke, { Color = Theme.Stroke }, 0.2)
        tween(searchIcon, { ImageColor3 = Theme.Muted }, 0.2)
    end)

    local actions = create("Frame", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        Visible = multi,
        Parent = inner,
    })
    local function actionButton(text, position)
        local button = create("TextButton", {
            Position = position,
            Size = UDim2.new(0.5, -3, 1, 0),
            BackgroundColor3 = Theme.Surface3,
            BackgroundTransparency = 0.35,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            ClipsDescendants = true,
            Parent = actions,
        })
        corner(button, UDim.new(0, 6))
        local buttonStroke = stroke(button)
        label({
            Size = UDim2.fromScale(1, 1),
            Text = text,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Center,
            Parent = button,
        })
        button.MouseEnter:Connect(function()
            tween(button, { BackgroundTransparency = 0.05 }, 0.15)
            tween(buttonStroke, { Color = Theme.StrokeHover }, 0.15)
        end)
        button.MouseLeave:Connect(function()
            tween(button, { BackgroundTransparency = 0.35 }, 0.25)
            tween(buttonStroke, { Color = Theme.Stroke }, 0.25)
        end)
        button.MouseButton1Click:Connect(function()
            ripple(button)
        end)
        return button
    end
    local selectAll = actionButton(opts.SelectAllText or "Select all", UDim2.fromOffset(0, 0))
    local clearAll = actionButton(opts.ClearAllText or "Clear all", UDim2.new(0.5, 3, 0, 0))

    local list = create("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, 100),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = TOUCH and 4 or 3,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0.4,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        -- Sized by hand: AutomaticCanvasSize under the window's UIScale
        -- sometimes leaves the canvas short, so the list would not scroll.
        CanvasSize = UDim2.new(),
        Parent = inner,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = list,
    })
    local noResults = label({
        Size = UDim2.new(1, 0, 0, ROW),
        Text = opts.NoResultsText or "No results",
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        LayoutOrder = 0,
        Visible = false,
        Parent = list,
    })

    local self_ = { Open = false }
    local selected = {}
    local optionButtons = {}
    local filter = ""

    local function matches(option)
        return filter == "" or string.find(string.lower(tostring(option)), filter, 1, true) ~= nil
    end

    -- Option labels are rich text, so the part matching the search can light up.
    local function escapeRich(text)
        return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
    end
    local function optionText(option)
        local text = tostring(option)
        local at = filter ~= "" and string.find(string.lower(text), filter, 1, true)
        if not at then
            return escapeRich(text)
        end
        local stop = at + #filter - 1
        return escapeRich(text:sub(1, at - 1))
            .. '<font color="#' .. Theme.Accent:ToHex() .. '"><b>' .. escapeRich(text:sub(at, stop)) .. "</b></font>"
            .. escapeRich(text:sub(stop + 1))
    end

    if multi then
        for _, value in ipairs(opts.Default or {}) do
            selected[value] = true
        end
    elseif opts.Default ~= nil then
        selected[opts.Default] = true
    end

    local function currentValue()
        if multi then
            local picked = {}
            for _, option in ipairs(options) do
                if selected[option] then
                    table.insert(picked, option)
                end
            end
            return picked
        end
        for _, option in ipairs(options) do
            if selected[option] then
                return option
            end
        end
        return nil
    end

    -- A picked row rests on a faint accent tint; hovering lifts either kind.
    local function restRow(entry, duration)
        local on, hover = entry.On == true, entry.Hover == true
        tween(entry.Frame, {
            BackgroundColor3 = on and Theme.Accent or Theme.Surface3,
            BackgroundTransparency = on and (hover and 0.8 or 0.88) or (hover and 0.55 or 1),
        }, duration)
        tween(entry.Label, { TextColor3 = (on or hover) and Theme.Text or Theme.Muted }, duration)
    end

    local function paintOption(button, animate)
        local on = selected[button.Option] == true
        if button.On == on and animate then
            return
        end
        button.On = on
        local duration = animate and 0.18 or 0
        restRow(button, duration)
        if multi then
            tween(button.Box, { BackgroundColor3 = on and Theme.Accent or Theme.Surface2 }, duration)
            tween(button.BoxStroke, { Color = on and Theme.Accent or Theme.Stroke }, duration)
        else
            tween(button.Bar, {
                BackgroundTransparency = on and 0 or 1,
                Size = UDim2.fromOffset(3, on and ROW - 14 or 4),
            }, animate and 0.3 or 0, Enum.EasingStyle.Quint)
        end
        tween(button.Check, { ImageTransparency = on and 0 or 1 }, duration)
        if animate and on then
            button.CheckScale.Scale = 0.5
            tween(button.CheckScale, { Scale = 1 }, 0.3, Enum.EasingStyle.Back)
        else
            button.CheckScale.Scale = 1
        end
    end

    local function renderValue(animate)
        local value = currentValue()
        if #options == 0 then
            fullText = opts.EmptyText or "None"
        elseif multi then
            -- Two names at most, then a count, so a long pick stays readable.
            if #value > 2 then
                fullText = tostring(value[1]) .. ", " .. tostring(value[2]) .. "  +" .. (#value - 2)
            else
                fullText = #value > 0 and table.concat(value, ", ") or (opts.NoneText or "None")
            end
        else
            fullText = value ~= nil and tostring(value) or (opts.NoneText or "None")
        end
        valueLabel.Text = trimmed()
        -- A picked value reads in full colour; "None" stays muted.
        local picked = #options > 0 and (if multi then #value > 0 else value ~= nil)
        tween(valueLabel, { TextColor3 = picked and Theme.Text or Theme.Muted }, animate and 0.15 or 0)
        for _, button in pairs(optionButtons) do
            paintOption(button, animate)
        end
    end

    local function visibleCount()
        local count = 0
        for _, option in ipairs(options) do
            if matches(option) then
                count += 1
            end
        end
        return count
    end

    local searchShown = true
    local targetSize = Vector2.new(220, 120)
    local opened = false
    local function layoutPopup(instant)
        searchShown = opts.Searchable ~= false and #options > (opts.SearchAfter or 0)
        searchHolder.Visible = searchShown
        local top = 0
        if searchShown then
            top += 38
        end
        actions.Position = UDim2.fromOffset(0, top)
        if multi and #options > 0 then
            actions.Visible = true
            top += 34
        else
            actions.Visible = false
        end
        local count = visibleCount()
        noResults.Visible = count == 0
        local rows = math.clamp(count, 1, MAX_ROWS)
        local listHeight = rows * ROW + (rows - 1) * 2
        list.CanvasSize = UDim2.fromOffset(0, math.max(count, 1) * (ROW + 2) - 2)
        local scale = window.Scale.Scale
        -- Shrink the list to whichever side of the chip has more room, so the
        -- popup never runs off a short window (phones in landscape).
        local host = window:_popupHost(frame)
        local bodyHeight = host.AbsoluteSize.Y / scale
        local chipTop = (chip.AbsolutePosition.Y - host.AbsolutePosition.Y) / scale
        local room = math.max(bodyHeight - (chipTop + chip.AbsoluteSize.Y / scale) - 14, chipTop - 14) - top - 16
        if room >= ROW then
            listHeight = math.min(listHeight, room)
        end
        list.Position = UDim2.fromOffset(0, top)
        list.Size = UDim2.new(1, 0, 0, listHeight)
        local width = math.max(math.floor(chip.AbsoluteSize.X / scale), opts.PopupWidth or 210)
        local bodyWidth = host.AbsoluteSize.X / scale
        width = math.min(width, math.max(bodyWidth - 16, 120))
        targetSize = Vector2.new(width, top + listHeight + 16)
        inner.Size = UDim2.new(1, 0, 0, targetSize.Y)
        if not opened then
            return
        end
        if instant then
            popup.Size = UDim2.fromOffset(targetSize.X, targetSize.Y)
        else
            tween(popup, { Size = UDim2.fromOffset(targetSize.X, targetSize.Y) }, 0.22, Enum.EasingStyle.Quint)
        end
    end

    local function applyFilter()
        for option, button in pairs(optionButtons) do
            local shown = matches(option)
            button.Frame.Visible = shown
            if shown then
                button.Label.Text = optionText(option)
            end
        end
    end

    local scroller = nil
    local function place()
        local body = window:_popupHost(frame)
        local scale = window.Scale.Scale
        if scroller then
            local centre = chip.AbsolutePosition + chip.AbsoluteSize / 2
            if not pointInside(centre, scroller) then
                self_:SetOpen(false)
                return
            end
        end
        local bodySize = body.AbsoluteSize / scale
        local chipPosition = (chip.AbsolutePosition - body.AbsolutePosition) / scale
        local chipSize = chip.AbsoluteSize / scale
        local right = math.clamp(chipPosition.X + chipSize.X, targetSize.X + 8, math.max(bodySize.X - 8, targetSize.X + 8))
        local below = chipPosition.Y + chipSize.Y + 6
        -- Opening upward pins the content to the bottom edge so it unfolds from the chip.
        if below + targetSize.Y > bodySize.Y - 8 and chipPosition.Y - 6 - targetSize.Y >= 8 then
            popup.AnchorPoint = Vector2.new(1, 1)
            popup.Position = UDim2.fromOffset(right, chipPosition.Y - 6)
            inner.AnchorPoint = Vector2.new(0, 1)
            inner.Position = UDim2.fromScale(0, 1)
        else
            popup.AnchorPoint = Vector2.new(1, 0)
            popup.Position = UDim2.fromOffset(right, below)
            inner.AnchorPoint = Vector2.zero
            inner.Position = UDim2.fromScale(0, 0)
        end
    end

    local stopFollowing = nil
    local closeGeneration = 0
    -- The page behind stops scrolling while the popup is open, so wheel and
    -- swipe input always reach the list instead of dragging the page away.
    local lockedScroller = nil
    local function unlockScroller()
        if lockedScroller then
            lockedScroller.ScrollingEnabled = true
            lockedScroller = nil
        end
    end
    local function scrollToSelected()
        list.CanvasPosition = Vector2.zero
        if multi then
            return
        end
        local value = currentValue()
        if value == nil then
            return
        end
        for index, option in ipairs(options) do
            if option == value then
                list.CanvasPosition = Vector2.new(0, math.max(0, (index - 2) * (ROW + 2)))
                return
            end
        end
    end
    local function setOpen(open)
        if open == self_.Open then
            return
        end
        self_.Open = open
        arrow:Set(open)
        tween(chipStroke, { Color = open and Theme.Accent or Theme.Stroke, Transparency = open and 0.35 or 0 }, 0.2)
        tween(chip, { BackgroundColor3 = open and Theme.Surface or Theme.Background }, 0.2)
        closeGeneration += 1
        if open then
            if window._closePopup and window._closePopup ~= self_._close then
                window._closePopup()
            end
            window._closePopup = self_._close
            scroller = frame:FindFirstAncestorWhichIsA("ScrollingFrame")
            if scroller and scroller.ScrollingEnabled then
                lockedScroller = scroller
                scroller.ScrollingEnabled = false
            end
            -- Drawn over a floating panel when the dropdown lives in one.
            popup.Parent = window:_popupHost(frame)
            filter = ""
            searchBox.Text = ""
            searchBox.PlaceholderText = opts.SearchPlaceholder or (#options > 6 and ("Search " .. #options .. " options") or "Search")
            applyFilter()
            layoutPopup(true)
            renderValue(false)
            scrollToSelected()
            opened = true
            popup.Size = UDim2.fromOffset(targetSize.X, 0)
            place()
            popup.Visible = true
            tween(popup, { Size = UDim2.fromOffset(targetSize.X, targetSize.Y) }, 0.3, Enum.EasingStyle.Quint)
            tween(panelStroke, { Transparency = 0 }, 0.12)
            tween(popupShadow, { ImageTransparency = 0.4 }, 0.3)
            if not stopFollowing then
                stopFollowing = window:_listen("Render", place)
            end
        else
            if window._closePopup == self_._close then
                window._closePopup = nil
            end
            unlockScroller()
            if searchBox:IsFocused() then
                searchBox:ReleaseFocus()
            end
            opened = false
            tween(popup, { Size = UDim2.fromOffset(targetSize.X, 0) }, 0.2, Enum.EasingStyle.Quint)
            tween(popupShadow, { ImageTransparency = 1 }, 0.16)
            local generation = closeGeneration
            task.delay(0.14, function()
                if closeGeneration == generation and not self_.Open then
                    tween(panelStroke, { Transparency = 1 }, 0.06)
                end
            end)
            task.delay(0.21, function()
                if closeGeneration == generation and not self_.Open then
                    popup.Visible = false
                    if stopFollowing then
                        stopFollowing()
                        stopFollowing = nil
                    end
                end
            end)
        end
    end
    self_._close = function()
        setOpen(false)
    end

    local function commit()
        renderValue(true)
        safeCall(opts.Callback, currentValue())
    end

    local function buildOptions()
        local keep = {}
        for index, option in ipairs(options) do
            keep[option] = index
        end
        for option, button in pairs(optionButtons) do
            if not keep[option] then
                button.Frame:Destroy()
                optionButtons[option] = nil
            end
        end
        for index, option in ipairs(options) do
            local existing = optionButtons[option]
            if existing then
                existing.Frame.LayoutOrder = index
                continue
            end
            local row = create("TextButton", {
                Size = UDim2.new(1, -6, 0, ROW),
                BackgroundColor3 = Theme.Surface3,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = index,
                Parent = list,
            })
            corner(row, UDim.new(0, 7))
            -- Multi selection ticks a checkbox on the left. A single pick
            -- gets an accent bar on the left edge and a check on the right.
            local box, boxStroke, bar, check
            if multi then
                box = create("Frame", {
                    AnchorPoint = Vector2.new(0, 0.5),
                    Position = UDim2.new(0, 8, 0.5, 0),
                    Size = UDim2.fromOffset(18, 18),
                    BackgroundColor3 = Theme.Surface2,
                    BorderSizePixel = 0,
                    Parent = row,
                })
                corner(box, UDim.new(0, 5))
                boxStroke = stroke(box, Theme.Stroke)
                check = create("ImageLabel", {
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.fromScale(0.5, 0.5),
                    Size = UDim2.fromOffset(12, 12),
                    BackgroundTransparency = 1,
                    ImageColor3 = Theme.AccentDark,
                    ImageTransparency = 1,
                    ScaleType = Enum.ScaleType.Fit,
                    Parent = box,
                })
            else
                bar = create("Frame", {
                    AnchorPoint = Vector2.new(0, 0.5),
                    Position = UDim2.new(0, 3, 0.5, 0),
                    Size = UDim2.fromOffset(3, 4),
                    BackgroundColor3 = Theme.Accent,
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    Parent = row,
                })
                corner(bar, UDim.new(1, 0))
                check = create("ImageLabel", {
                    AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, -10, 0.5, 0),
                    Size = UDim2.fromOffset(14, 14),
                    BackgroundTransparency = 1,
                    ImageColor3 = Theme.Accent,
                    ImageTransparency = 1,
                    ScaleType = Enum.ScaleType.Fit,
                    Parent = row,
                })
            end
            applyIcon(check, "check")
            local checkScale = create("UIScale", { Parent = check })
            local text_ = label({
                Position = UDim2.fromOffset(multi and 36 or 14, 0),
                Size = UDim2.new(1, multi and -44 or -46, 1, 0),
                Text = optionText(option),
                TextSize = 13,
                TextColor3 = Theme.Muted,
                RichText = true,
                Parent = row,
            })
            local entry = { Option = option, Frame = row, Box = box, BoxStroke = boxStroke, Bar = bar, Check = check, CheckScale = checkScale, Label = text_, On = nil, Hover = false }
            local isTap = tapGuard(row, function()
                return list
            end)
            row.MouseEnter:Connect(function()
                -- Touch fires enter without a matching leave; skip the hover.
                if usingTouch() then
                    return
                end
                entry.Hover = true
                restRow(entry, 0.15)
                if boxStroke and not selected[option] then
                    tween(boxStroke, { Color = Theme.StrokeHover }, 0.15)
                end
            end)
            row.MouseLeave:Connect(function()
                entry.Hover = false
                restRow(entry, 0.25)
                if boxStroke and not selected[option] then
                    tween(boxStroke, { Color = Theme.Stroke }, 0.25)
                end
            end)
            row.MouseButton1Click:Connect(function()
                if not isTap() then
                    return
                end
                if selected[option] then
                    if not multi and opts.AllowNone == false then
                        setOpen(false)
                        return
                    end
                    selected[option] = nil
                else
                    if not multi then
                        selected = {}
                    end
                    selected[option] = true
                end
                commit()
                if not multi then
                    setOpen(false)
                end
            end)
            optionButtons[option] = entry
            paintOption(entry, false)
        end
        applyFilter()
        if self_.Open then
            layoutPopup(false)
        end
    end

    selectAll.MouseButton1Click:Connect(function()
        for _, option in ipairs(options) do
            if matches(option) then
                selected[option] = true
            end
        end
        commit()
    end)
    clearAll.MouseButton1Click:Connect(function()
        selected = {}
        commit()
    end)

    function self_:Set(value, silent)
        selected = {}
        if multi then
            for _, item in ipairs(type(value) == "table" and value or { value }) do
                selected[item] = true
            end
        elseif value ~= nil then
            selected[value] = true
        end
        renderValue(self_.Open)
        flashStroke(frameStroke)
        if not silent then
            safeCall(opts.Callback, currentValue())
        end
    end

    function self_:Get()
        return currentValue()
    end

    local function sameValue(a, b)
        if type(a) ~= "table" or type(b) ~= "table" then
            return a == b
        end
        if #a ~= #b then
            return false
        end
        for index, item in ipairs(a) do
            if b[index] ~= item then
                return false
            end
        end
        return true
    end

    -- A kept pick only counts once its option exists, so a list filled in after a
    -- config load changes the value; the callback runs so scripts see it.
    function self_:Refresh(newOptions, keepSelection, silent)
        local before = currentValue()
        options = newOptions or {}
        if not keepSelection then
            selected = {}
        end
        buildOptions()
        renderValue(false)
        if not silent and not sameValue(before, currentValue()) then
            safeCall(opts.Callback, currentValue())
        end
    end

    -- Every pick, including ones whose option isn't in the list right now, so
    -- saving never drops them.
    function self_:_saveValue()
        local picked = currentValue()
        if multi then
            local seen = {}
            for _, item in ipairs(picked) do
                seen[item] = true
            end
            for item in pairs(selected) do
                if not seen[item] then
                    table.insert(picked, item)
                end
            end
            return picked
        end
        if picked == nil then
            picked = next(selected)
        end
        return picked
    end

    function self_:SetOpen(open)
        setOpen(open == true)
    end

    local headerTap = tapGuard(header, function()
        return frame:FindFirstAncestorWhichIsA("ScrollingFrame")
    end)
    header.MouseButton1Click:Connect(function()
        if headerTap() then
            setOpen(not self_.Open)
        end
    end)
    -- The chip answers the pointer before it is opened.
    header.MouseEnter:Connect(function()
        if not self_.Open and not usingTouch() then
            tween(chipStroke, { Color = Theme.StrokeHover }, 0.15)
            tween(chip, { BackgroundColor3 = Theme.Surface }, 0.15)
        end
    end)
    header.MouseLeave:Connect(function()
        if not self_.Open then
            tween(chipStroke, { Color = Theme.Stroke }, 0.25)
            tween(chip, { BackgroundColor3 = Theme.Background }, 0.25)
        end
    end)
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        filter = string.lower(searchBox.Text)
        applyFilter()
        if self_.Open then
            layoutPopup(false)
        end
    end)
    self_._listeners = {
        function()
            setOpen(false)
            unlockScroller()
            if stopFollowing then
                stopFollowing()
                stopFollowing = nil
            end
            popup:Destroy()
        end,
    }
    window:_listen("Began", function(input)
        if not self_.Open then
            return
        end
        if input.KeyCode == Enum.KeyCode.Escape then
            setOpen(false)
        elseif isPress(input) then
            local point = pointerPosition()
            if not pointInside(point, popup) and not pointInside(point, header) then
                setOpen(false)
            end
        end
    end, self_)

    buildOptions()
    renderValue(false)
    task.defer(fitChip, true)
    return finishElement(self, opts, self_, frame, "Dropdown")
end

Library._amountSuffixes = { k = 1e3, m = 1e6, b = 1e9, t = 1e12, qa = 1e15, qi = 1e18 }

function Library._parseAmount(text)
    text = string.lower(tostring(text)):gsub("[%s,_%$]", "")
    text = text:gsub("kg$", ""):gsub("/s$", "")
    local number = tonumber(text)
    if number then
        return number
    end
    local digits, suffix = text:match("^(.-)(%a+)$")
    local scale = suffix and Library._amountSuffixes[suffix]
    number = digits and tonumber(digits)
    if number and scale then
        return number * scale
    end
    return nil
end

function Tab:Input(opts)
    local frame, frameStroke, _, titleLabel, descLabel
    opts, frame, frameStroke, _, titleLabel, descLabel = beginElement(self, opts, { Title = "Name", Description = "Desc", PlaceholderText = "Placeholder", CurrentValue = "Default", Value = "Default" }, "Frame", 160, "Input")
    local compact = metricsOf(self).Compact
    local boxHeight = compact and metricsOf(self).Chip + 2 or 30

    local boxHolder = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, compact and -14 or -10, 0.5, 0),
        Size = UDim2.fromOffset(170, boxHeight),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = frame,
    })
    corner(boxHolder, UDim.new(0, 6))
    local boxStroke = stroke(boxHolder)

    local boxIcon = opts.Icon
    if boxIcon then
        glowIcon(boxHolder, boxIcon, Theme.Muted, UDim2.new(0, 8, 0.5, 0))
    end
    local box = create("TextBox", {
        Position = UDim2.fromOffset(boxIcon and 30 or 8, 0),
        Size = UDim2.new(1, boxIcon and -38 or -16, 1, 0),
        BackgroundTransparency = 1,
        Text = opts.Default or "",
        PlaceholderText = opts.Placeholder or "",
        PlaceholderColor3 = Theme.Muted,
        TextColor3 = Theme.Text,
        TextSize = compact and 13 or 14,
        FontFace = Fonts.Regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        TextTruncate = Enum.TextTruncate.None,
        ClipsDescendants = true,
        Parent = boxHolder,
    })
    boxHolder.ClipsDescendants = true

    local lastText = box.Text
    local value = opts.Numeric and Library._parseAmount(lastText) or nil
    if opts.Numeric and not value then
        lastText = ""
    end
    local focused = false
    local textInset = (boxIcon and 30 or 8) + 8
    local function fitBox(instant)
        local width
        if compact then
            width = rowControlWidth(frame, self.Window)
        else
            local cardWidth = frame.AbsoluteSize.X / self.Window.Scale.Scale
            local maxWidth = math.clamp(cardWidth - 14 - 110 - 20, 100, 200)
            local measured = box.TextBounds.X
            if #box.Text == 0 then
                measured = math.min(box.TextBounds.X, 90)
            end
            width = math.clamp(measured + textInset + 12, 90, maxWidth) + (focused and 8 or 0)
            width = math.min(width, maxWidth + 8)
        end
        reserveRight(titleLabel, descLabel, width + (compact and 24 or 20))
        if instant then
            boxHolder.Size = UDim2.fromOffset(width, boxHeight)
        else
            tween(boxHolder, { Size = UDim2.fromOffset(width, boxHeight) }, 0.18)
        end
    end
    local lastWidth = 0
    frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if frame.AbsoluteSize.X ~= lastWidth then
            lastWidth = frame.AbsoluteSize.X
            fitBox(true)
        end
    end)
    box:GetPropertyChangedSignal("Text"):Connect(function()
        fitBox(false)
    end)
    box:GetPropertyChangedSignal("TextBounds"):Connect(function()
        fitBox(false)
    end)
    task.defer(fitBox, true)

    box.Focused:Connect(function()
        focused = true
        tween(boxStroke, { Color = Theme.StrokeHover }, 0.15)
        fitBox(false)
    end)
    box.FocusLost:Connect(function(enterPressed)
        focused = false
        tween(boxStroke, { Color = Theme.Stroke }, 0.15)
        fitBox(false)
        if opts.Numeric then
            local number = Library._parseAmount(box.Text)
            if not number then
                box.Text = lastText
                return
            end
            lastText, value = box.Text, number
            safeCall(opts.Callback, number, enterPressed)
            return
        end
        safeCall(opts.Callback, box.Text, enterPressed)
    end)

    return finishElement(self, opts, {
        Set = function(_, newValue, silent)
            local before = box.Text
            box.Text = tostring(newValue == nil and "" or newValue)
            if opts.Numeric then
                local number = Library._parseAmount(box.Text)
                if number then
                    lastText, value = box.Text, number
                else
                    box.Text = lastText
                    return
                end
            end
            flashStroke(frameStroke)
            -- Configs load through here, so the script hears the loaded text.
            if not silent and box.Text ~= before then
                safeCall(opts.Callback, opts.Numeric and value or box.Text, false)
            end
        end,
        Get = function()
            if opts.Numeric then
                return value
            end
            return box.Text
        end,
        _saveValue = opts.Numeric and function()
            return lastText
        end or nil,
    }, frame, "Input")
end

function Tab:Keybind(opts)
    local frame, frameStroke, _, titleLabel, descLabel
    opts, frame, frameStroke, _, titleLabel, descLabel = beginElement(self, opts, { Title = "Name", Description = "Desc", CurrentKeybind = "Default", Value = "Default" }, "Frame", 110, "Keybind")
    if type(opts.Default) == "string" then
        opts.Default = Enum.KeyCode[opts.Default]
    end
    local compact = metricsOf(self).Compact
    local chipHeight = metricsOf(self).Chip

    local chip = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, compact and -14 or -10, 0.5, 0),
        Size = UDim2.fromOffset(44, chipHeight),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ClipsDescendants = true,
        Parent = frame,
    })
    corner(chip, UDim.new(0, 6))
    local chipStroke = stroke(chip)
    local chipLabel = label({
        Size = UDim2.new(1, 0, 1, 0),
        TextSize = 13,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextTruncate = Enum.TextTruncate.None,
        Parent = chip,
    })

    local self_ = { Value = opts.Default, Listening = false }

    local function fitChip(instant)
        local width = math.max(chipLabel.TextBounds.X + 20, TOUCH and 44 or 36)
        reserveRight(titleLabel, descLabel, width + (compact and 24 or 20))
        if instant then
            chip.Size = UDim2.fromOffset(width, chipHeight)
        else
            tween(chip, { Size = UDim2.fromOffset(width, chipHeight) }, 0.2)
        end
    end
    chipLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
        fitChip(false)
    end)

    local function render()
        chipLabel.Text = self_.Listening and "..." or keyName(self_.Value)
        tween(chipStroke, { Color = self_.Listening and Theme.StrokeHover or Theme.Stroke }, 0.15)
        tween(chipLabel, { TextColor3 = self_.Listening and Theme.Accent or Theme.Muted }, 0.15)
    end

    function self_:Set(keyCode, silent)
        local wasListening = self_.Listening
        self_.Value = keyCode
        self_.Listening = false
        render()
        if not wasListening then
            flashStroke(frameStroke)
        end
        if not silent then
            safeCall(opts.OnChanged, keyCode)
        end
    end

    chip.MouseButton1Click:Connect(function()
        self_.Listening = not self_.Listening
        render()
    end)

    self.Window:_listen("Began", function(input, gameProcessed)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then
            return
        end
        if self_.Listening then
            self.Window._consumedKey = input.KeyCode
            self.Window._consumedAt = os.clock()
            if input.KeyCode == Enum.KeyCode.Escape then
                self_.Listening = false
                render()
            else
                self_:Set(input.KeyCode)
            end
            return
        end
        if not gameProcessed and self_.Value ~= nil and input.KeyCode == self_.Value then
            safeCall(opts.Callback, input.KeyCode)
        end
    end, self_)

    render()
    task.defer(fitChip, true)
    function self_:Get()
        return self_.Value
    end
    self_._onHide = function()
        if self_.Listening then
            self_.Listening = false
            render()
        end
    end
    return finishElement(self, opts, self_, frame, "Keybind")
end

function Tab:ColorPicker(opts)
    local PANEL_HEIGHT = 194
    local frame, frameStroke, height
    opts, frame, frameStroke, height = beginElement(self, opts, { Title = "Name", Description = "Desc", Color = "Default", CurrentValue = "Default", Value = "Default" }, "Frame")
    frame.ClipsDescendants = true
    local metrics = metricsOf(self)
    local compact = metrics.Compact

    local header = create("TextButton", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Parent = frame,
    })
    titleDesc(header, opts.Name or "Color", opts.Desc, 140, metrics)

    -- Closed, the row shows the hex code beside a rounded swatch.
    local swatch = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, compact and -38 or -34, 0.5, 0),
        Size = UDim2.fromOffset(22, 22),
        BorderSizePixel = 0,
        Parent = header,
    })
    corner(swatch, UDim.new(0, 6))
    stroke(swatch, Theme.Stroke)
    local swatchHex = label({
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, compact and -68 or -64, 0.5, 0),
        Size = UDim2.fromOffset(64, 16),
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = header,
    })
    local arrow = arrowIndicator(header, 1, compact and -14 or -12)

    local panel = create("Frame", {
        Position = UDim2.fromOffset(14, height + 2),
        Size = UDim2.new(1, -28, 0, PANEL_HEIGHT - 12),
        BackgroundTransparency = 1,
        Visible = false,
        Parent = frame,
    })

    -- Saturation runs left to right, brightness top to bottom.
    local svBox = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 118),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Parent = panel,
    })
    corner(svBox, UDim.new(0, 8))
    stroke(svBox, Theme.Stroke)
    local svHueGradient = create("UIGradient", {
        Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 0, 0)),
        Parent = svBox,
    })
    local svDark = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BorderSizePixel = 0,
        Parent = svBox,
    })
    corner(svDark, UDim.new(0, 8))
    create("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 0),
        }),
        Rotation = 90,
        Parent = svDark,
    })

    -- Both handles are a white ring filled with the colour under them, with a
    -- faint dark edge so they read on light and dark spots alike.
    local function knob(parent, size)
        local ring = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Size = UDim2.fromOffset(size, size),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            ZIndex = 3,
            Parent = parent,
        })
        corner(ring, UDim.new(1, 0))
        stroke(ring, Color3.new(0, 0, 0), 0.7)
        local fill = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.new(1, -4, 1, -4),
            BorderSizePixel = 0,
            ZIndex = 3,
            Parent = ring,
        })
        corner(fill, UDim.new(1, 0))
        return ring, fill
    end
    local svCursor, svFill = knob(svBox, 14)

    -- Hue is a slim horizontal track under the square.
    local hueBar = create("TextButton", {
        Position = UDim2.fromOffset(0, 132),
        Size = UDim2.new(1, 0, 0, 10),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Parent = panel,
    })
    corner(hueBar, UDim.new(1, 0))
    create("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
            ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 255, 0)),
            ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(0, 255, 0)),
            ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(0, 255, 255)),
            ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(0, 0, 255)),
            ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(255, 0, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
        }),
        Parent = hueBar,
    })
    local hueCursor, hueFill = knob(hueBar, 16)
    hueCursor.Position = UDim2.fromScale(0, 0.5)

    -- Bottom row: a preview chip and hex field on the left, RGB on the right.
    local hexHolder = create("Frame", {
        Position = UDim2.fromOffset(0, 154),
        Size = UDim2.fromOffset(compact and 110 or 124, 28),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = panel,
    })
    corner(hexHolder, UDim.new(0, 7))
    local hexStroke = stroke(hexHolder)
    local preview = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 6, 0.5, 0),
        Size = UDim2.fromOffset(16, 16),
        BorderSizePixel = 0,
        Parent = hexHolder,
    })
    corner(preview, UDim.new(0, 4))
    stroke(preview, Theme.Stroke)
    local hexBox = create("TextBox", {
        Position = UDim2.fromOffset(30, 0),
        Size = UDim2.new(1, -38, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        TextTruncate = Enum.TextTruncate.None,
        ClipsDescendants = false,
        TextColor3 = Theme.Text,
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        Parent = hexHolder,
    })
    local rgbLabel = label({
        Position = UDim2.fromOffset(compact and 118 or 134, 154),
        Size = UDim2.new(1, compact and -118 or -134, 0, 28),
        TextXAlignment = Enum.TextXAlignment.Right,
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = panel,
    })

    local self_ = { Open = false }
    local hue, sat, val = Color3.toHSV(opts.Default or Theme.Accent)
    local dragTarget = nil

    local function toHex(color)
        return string.format("#%02X%02X%02X",
            math.floor(color.R * 255 + 0.5),
            math.floor(color.G * 255 + 0.5),
            math.floor(color.B * 255 + 0.5))
    end

    local function render(duration)
        local color = Color3.fromHSV(hue, sat, val)
        self_.Value = color
        swatch.BackgroundColor3 = color
        preview.BackgroundColor3 = color
        svFill.BackgroundColor3 = color
        hueFill.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
        swatchHex.Text = toHex(color)
        svHueGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(hue, 1, 1))
        tween(svCursor, { Position = UDim2.fromScale(sat, 1 - val) }, duration, Enum.EasingStyle.Quint)
        tween(hueCursor, { Position = UDim2.fromScale(hue, 0.5) }, duration, Enum.EasingStyle.Quint)
        if not hexBox:IsFocused() then
            hexBox.Text = toHex(color)
        end
        rgbLabel.Text = string.format("%d  %d  %d",
            math.floor(color.R * 255 + 0.5),
            math.floor(color.G * 255 + 0.5),
            math.floor(color.B * 255 + 0.5))
    end

    local function commit(duration, silent)
        render(duration)
        if not silent then
            safeCall(opts.Callback, self_.Value)
        end
    end

    function self_:Set(color, silent)
        hue, sat, val = Color3.toHSV(color)
        commit(0.25, silent)
        flashStroke(frameStroke)
    end

    function self_:Get()
        return self_.Value
    end

    local function setOpen(open)
        self_.Open = open
        tween(frame, { Size = UDim2.new(1, 0, 0, open and (height + PANEL_HEIGHT) or height) }, 0.35, Enum.EasingStyle.Quint)
        arrow:Set(open)
        if open then
            panel.Visible = true
        else
            task.delay(0.35, function()
                if not self_.Open then
                    panel.Visible = false
                end
            end)
        end
    end

    function self_:SetOpen(open)
        setOpen(open == true)
    end

    header.MouseButton1Click:Connect(function()
        setOpen(not self_.Open)
    end)

    local function updateSV(position)
        sat = math.clamp((position.X - svBox.AbsolutePosition.X) / svBox.AbsoluteSize.X, 0, 1)
        val = 1 - math.clamp((position.Y - svBox.AbsolutePosition.Y) / svBox.AbsoluteSize.Y, 0, 1)
        commit(0.04)
    end
    local function updateHue(position)
        hue = math.clamp((position.X - hueBar.AbsolutePosition.X) / hueBar.AbsoluteSize.X, 0, 0.999)
        commit(0.04)
    end

    svBox.InputBegan:Connect(function(input)
        if isPress(input) then
            dragTarget = "sv"
            tween(svCursor, { Size = UDim2.fromOffset(18, 18) }, 0.2, Enum.EasingStyle.Quint)
            updateSV(pointerPosition())
        end
    end)
    hueBar.InputBegan:Connect(function(input)
        if isPress(input) then
            dragTarget = "hue"
            tween(hueCursor, { Size = UDim2.fromOffset(20, 20) }, 0.2, Enum.EasingStyle.Quint)
            updateHue(pointerPosition())
        end
    end)
    self.Window:_listen("Changed", function(input)
        if not dragTarget or not isMove(input) then
            return
        end
        local position = pointerPosition()
        if dragTarget == "sv" then
            updateSV(position)
        else
            updateHue(position)
        end
    end, self_)
    self.Window:_listen("Ended", function(input)
        if dragTarget and isPress(input) then
            dragTarget = nil
            tween(svCursor, { Size = UDim2.fromOffset(14, 14) }, 0.25, Enum.EasingStyle.Quint)
            tween(hueCursor, { Size = UDim2.fromOffset(16, 16) }, 0.25, Enum.EasingStyle.Quint)
        end
    end, self_)

    hexBox.Focused:Connect(function()
        tween(hexStroke, { Color = Theme.StrokeHover }, 0.15)
    end)
    hexBox.FocusLost:Connect(function()
        tween(hexStroke, { Color = Theme.Stroke }, 0.15)
        local r, g, b = hexBox.Text:match("^%s*#?(%x%x)(%x%x)(%x%x)%s*$")
        if r then
            self_:Set(Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)))
        else
            hexBox.Text = toHex(self_.Value)
        end
    end)

    render(0)
    return finishElement(self, opts, self_, frame, "ColorPicker")
end

function Tab:Stepper(opts)
    local frame, frameStroke, _, titleLabel, descLabel
    opts, frame, frameStroke, _, titleLabel, descLabel = beginElement(self, opts, { Title = "Name", Description = "Desc", CurrentValue = "Default", Value = "Default", Increment = "Step" }, "Frame", 150, "Stepper")
    local min = opts.Min or 0
    local max = opts.Max or 100
    local step = opts.Step or 1
    local suffix = opts.Suffix or ""
    local numbers = numberFormat(min, max, step)
    local compact = metricsOf(self).Compact
    local chipHeight = metricsOf(self).Chip

    local group = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, compact and -14 or -10, 0.5, 0),
        Size = UDim2.fromOffset(0, chipHeight),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = frame,
    })
    corner(group, UDim.new(0, 6))
    local groupStroke = stroke(group)
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Parent = group,
    })

    local function stepButton(text, order)
        local button = create("TextButton", {
            Size = UDim2.fromOffset(chipHeight, chipHeight),
            BackgroundTransparency = 1,
            Text = text,
            TextColor3 = Theme.Muted,
            TextSize = 18,
            FontFace = Fonts.Medium,
            AutoButtonColor = false,
            LayoutOrder = order,
            Parent = group,
        })
        button.MouseEnter:Connect(function()
            tween(button, { TextColor3 = Theme.Accent }, 0.12)
        end)
        button.MouseLeave:Connect(function()
            tween(button, { TextColor3 = Theme.Muted }, 0.2)
        end)
        return button
    end
    local minus = stepButton("−", 1)
    local valueLabel = label({
        Size = UDim2.new(0, 30, 1, 0),
        TextSize = 13,
        TextColor3 = Theme.Accent,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        Parent = group,
    })
    local plus = stepButton("+", 3)
    local function fitValue(instant)
        local width = math.max(valueLabel.TextBounds.X + 12, 30)
        if instant then
            valueLabel.Size = UDim2.new(0, width, 1, 0)
        else
            tween(valueLabel, { Size = UDim2.new(0, width, 1, 0) }, 0.2)
        end
    end
    valueLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
        fitValue(false)
    end)
    group:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        reserveRight(titleLabel, descLabel, group.AbsoluteSize.X / self.Window.Scale.Scale + (compact and 24 or 20))
    end)

    local self_ = { Value = math.clamp(opts.Default or min, min, max) }
    local snap = numbers.snap
    local fromButton = false
    local function render()
        valueLabel.Text = numbers.format(self_.Value) .. suffix
        tween(minus, { TextTransparency = self_.Value <= min and 0.6 or 0 }, 0.15)
        tween(plus, { TextTransparency = self_.Value >= max and 0.6 or 0 }, 0.15)
    end
    function self_:Set(value, silent)
        value = snap(tonumber(value) or min)
        if value == self_.Value then
            return
        end
        self_.Value = value
        render()
        if not fromButton then
            flashStroke(frameStroke)
        end
        if not silent then
            safeCall(opts.Callback, value)
        end
    end
    function self_:Get()
        return self_.Value
    end

    local function bump(direction)
        fromButton = true
        self_:Set(self_.Value + direction * step)
        fromButton = false
        tween(groupStroke, { Color = Theme.StrokeHover }, 0.08)
        task.delay(0.12, function()
            tween(groupStroke, { Color = Theme.Stroke }, 0.2)
        end)
    end
    local function holdRepeat(button, direction)
        local holding = false
        button.InputBegan:Connect(function(input)
            if not isPress(input) then
                return
            end
            holding = true
            bump(direction)
            task.delay(0.4, function()
                while holding do
                    bump(direction)
                    task.wait(0.07)
                end
            end)
        end)
        button.InputEnded:Connect(function(input)
            if isPress(input) then
                holding = false
            end
        end)
        button.MouseLeave:Connect(function()
            holding = false
        end)
    end
    holdRepeat(minus, -1)
    holdRepeat(plus, 1)

    render()
    task.defer(fitValue, true)
    return finishElement(self, opts, self_, frame, "Stepper")
end

function Tab:Progress(opts)
    opts = normalize(opts, { Title = "Name", Description = "Desc", CurrentValue = "Default", Value = "Default" })
    local metrics = metricsOf(self)
    local compact = metrics.Compact
    local extra = compact and 6 or 10
    local frame, frameStroke = card(self, "Frame", (opts.Desc and metrics.DescHeight or metrics.Height) + extra, opts)
    hoverStroke(frame, frameStroke)
    local top
    if opts.Desc then
        top = math.floor((metrics.DescHeight - (metrics.DescGap + metrics.DescLine)) / 2) - 2
    else
        top = compact and 5 or 12
    end

    label({
        Position = UDim2.fromOffset(14, top),
        Size = UDim2.new(1, -110, 0, 18),
        Text = opts.Name or "Progress",
        TextSize = metrics.TextSize,
        Parent = frame,
    })
    if opts.Desc then
        label({
            Position = UDim2.fromOffset(14, top + metrics.DescGap),
            Size = UDim2.new(1, -110, 0, metrics.DescLine),
            Text = opts.Desc,
            TextSize = metrics.DescSize,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            Parent = frame,
        })
    end
    local valueLabel = label({
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -14, 0, top),
        Size = UDim2.fromOffset(90, 18),
        TextXAlignment = Enum.TextXAlignment.Right,
        TextSize = 13,
        TextColor3 = Library._color(opts.TextColor) or Theme.Accent,
        RichText = true,
        Parent = frame,
    })
    local track = create("Frame", {
        Position = UDim2.new(0, 14, 1, compact and -12 or -16),
        Size = UDim2.new(1, -28, 0, 5),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = frame,
    })
    corner(track, UDim.new(1, 0))
    local fill = create("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = Library._color(opts.Color) or Theme.Accent,
        BorderSizePixel = 0,
        Parent = track,
    })
    corner(fill, UDim.new(1, 0))

    local self_ = { Value = math.clamp(opts.Default or 0, 0, 1) }
    local formatter = opts.Format
    local function render(duration)
        local frac = self_.Value
        tween(fill, { Size = UDim2.new(frac, 0, 1, 0) }, duration, Enum.EasingStyle.Quint)
        if type(formatter) == "function" then
            valueLabel.Text = Library._rich(formatter(frac))
        else
            valueLabel.Text = string.format("%d%%", math.floor(frac * 100 + 0.5))
        end
    end
    function self_:Set(value, silent)
        value = math.clamp(tonumber(value) or 0, 0, 1)
        if value == self_.Value then
            return
        end
        self_.Value = value
        render(0.35)
        if not silent then
            safeCall(opts.Callback, value)
        end
    end
    function self_:Get()
        return self_.Value
    end
    function self_:SetColor(color)
        tween(fill, { BackgroundColor3 = Library._color(color) or Theme.Accent }, 0.25)
    end
    -- The percentage's colour; nil goes back to the accent.
    function self_:SetTextColor(color)
        tween(valueLabel, { TextColor3 = Library._color(color) or Theme.Accent }, 0.25)
    end
    -- Runs render now, and again on a theme change for theme tags in Format.
    onTheme(valueLabel, function()
        render(0)
    end)
    return finishElement(self, opts, self_, frame, "Progress")
end

-- An always-open list the player puts in order: drag a row (by its grip on
-- touch, anywhere on PC) or nudge it with the arrows. Past MaxRows the list
-- scrolls, and dragging near its top or bottom edge scrolls it along.
function Tab:OrderList(opts)
    opts = normalize(opts, { Title = "Name", Description = "Desc", Options = "Items", Values = "Items" })
    local metrics = metricsOf(self)
    local compact = metrics.Compact
    local window = self.Window
    local ROW = TOUCH and 40 or 32
    local GAP = 4
    local STEP = ROW + GAP
    local GRIP = TOUCH and 34 or 26
    local ARROW = TOUCH and 30 or 22
    local maxRows = math.max(math.floor(tonumber(opts.MaxRows) or 6), 1)
    local numbered = opts.Numbered ~= false
    local arrows = opts.Arrows ~= false

    local frame = card(self, "Frame", 0, opts)
    frame.AutomaticSize = Enum.AutomaticSize.Y
    if compact then
        padding(frame, 14, 14, 6, 8)
    else
        padding(frame, 14, 14, 11, 12)
    end
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = frame,
    })
    local name = tostring(opts.Name or "")
    label({
        Size = UDim2.new(1, 0, 0, 18),
        Text = name,
        TextSize = metrics.TextSize,
        Visible = name ~= "",
        LayoutOrder = 1,
        Parent = frame,
    })
    if opts.Desc then
        label({
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Text = opts.Desc,
            TextSize = metrics.DescSize,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextWrapped = true,
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = 2,
            Parent = frame,
        })
    end
    local scroller = create("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, ROW + 2),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = TOUCH and 4 or 3,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0.4,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        -- Sized by hand, like the dropdown list, so it scrolls under UIScale.
        CanvasSize = UDim2.new(),
        ScrollingEnabled = false,
        LayoutOrder = 3,
        Parent = frame,
    })
    scroller:SetAttribute("NoDrag", true)
    local content = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Parent = scroller,
    })
    local empty = label({
        Size = UDim2.new(1, 0, 0, ROW),
        Text = tostring(opts.EmptyText or "Nothing to order"),
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        Visible = false,
        Parent = content,
    })

    -- A lucide icon, or a text glyph when the icon set didn't load.
    local function iconButton(parent, icon, glyph, rotation, props)
        props.BackgroundTransparency = 1
        props.Text = ""
        props.AutoButtonColor = false
        props.Parent = parent
        local button = create("TextButton", props)
        local image = create("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = TOUCH and UDim2.fromOffset(16, 16) or UDim2.fromOffset(14, 14),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Muted,
            ScaleType = Enum.ScaleType.Fit,
            Parent = button,
        })
        applyIcon(image, icon)
        if image.Image ~= "" then
            return button, { Object = image, Color = "ImageColor3", Fade = "ImageTransparency" }
        end
        image:Destroy()
        local text_ = label({
            Size = UDim2.fromScale(1, 1),
            Text = glyph,
            TextSize = 18,
            TextColor3 = Theme.Muted,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextTruncate = Enum.TextTruncate.None,
            Rotation = rotation,
            Parent = button,
        })
        return button, { Object = text_, Color = "TextColor3", Fade = "TextTransparency" }
    end
    local function tint(icon, color, transparency, duration)
        tween(icon.Object, { [icon.Color] = color, [icon.Fade] = transparency }, duration)
    end

    local self_ = {}
    local entries = {}
    -- The last order Set asked for, including items not in the list right now,
    -- so a saved order still applies once Refresh brings those items in.
    local remembered = {}
    local dragging = nil
    local nudge, beginDrag

    local function slotY(slot)
        return 1 + (slot - 1) * STEP
    end

    local function values()
        local list = {}
        for index, entry in ipairs(entries) do
            list[index] = entry.Value
        end
        return list
    end

    local function layout(instant)
        local count = #entries
        for slot, entry in ipairs(entries) do
            entry.Index.Text = tostring(slot)
            if entry ~= dragging then
                tween(entry.Frame, { Position = UDim2.fromOffset(3, slotY(slot)) }, instant and 0 or 0.22, Enum.EasingStyle.Quint)
            end
            if entry.UpIcon then
                tween(entry.UpIcon.Object, { [entry.UpIcon.Fade] = slot == 1 and 0.7 or 0 }, instant and 0 or 0.15)
                tween(entry.DownIcon.Object, { [entry.DownIcon.Fade] = slot == count and 0.7 or 0 }, instant and 0 or 0.15)
            end
        end
    end

    local function fit()
        local count = #entries
        local canvas = math.max(count, 1) * STEP - GAP + 2
        local shown = math.clamp(count, 1, maxRows)
        local height = shown * STEP - GAP + 2
        local scrolling = count > maxRows
        scroller.Size = UDim2.new(1, 0, 0, height)
        scroller.CanvasSize = UDim2.fromOffset(0, canvas)
        content.Size = UDim2.new(1, scrolling and -8 or 0, 0, canvas)
        if not dragging then
            scroller.ScrollingEnabled = scrolling
        end
        empty.Visible = count == 0
        local maxScroll = math.max(canvas - height, 0)
        if scroller.CanvasPosition.Y > maxScroll then
            scroller.CanvasPosition = Vector2.new(0, maxScroll)
        end
    end

    local function changed(silent)
        self_.Value = values()
        if not silent then
            safeCall(opts.Callback, values())
        end
    end

    local function listScroller()
        if scroller.ScrollingEnabled then
            return scroller
        end
        return frame:FindFirstAncestorWhichIsA("ScrollingFrame")
    end

    local function newEntry(value)
        local row = create("Frame", {
            Size = UDim2.new(1, -6, 0, ROW),
            BackgroundColor3 = Theme.Surface,
            BorderSizePixel = 0,
            Parent = content,
        })
        corner(row, UDim.new(0, 7))
        local entry = { Value = value, Frame = row }
        entry.Stroke = stroke(row)
        entry.Scale = create("UIScale", { Parent = row })
        local grip
        grip, entry.GripIcon = iconButton(row, "grip-vertical", "=", 0, {
            Size = UDim2.new(0, GRIP, 1, 0),
        })
        local x = GRIP
        entry.Index = label({
            Position = UDim2.fromOffset(x, 0),
            Size = UDim2.new(0, 22, 1, 0),
            TextSize = 12,
            TextColor3 = Theme.Accent,
            TextTruncate = Enum.TextTruncate.None,
            Visible = numbered,
            Parent = row,
        })
        if numbered then
            x += 22
        end
        local right = arrows and ARROW * 2 + 8 or 10
        entry.Text = label({
            Position = UDim2.fromOffset(x, 0),
            Size = UDim2.new(1, -(x + right), 1, 0),
            Text = tostring(value),
            TextSize = 13,
            Parent = row,
        })
        local buttons = {}
        if arrows then
            local up, down
            up, entry.UpIcon = iconButton(row, "chevron-up", "›", -90, {
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -(ARROW + 6), 0, 0),
                Size = UDim2.new(0, ARROW, 1, 0),
            })
            down, entry.DownIcon = iconButton(row, "chevron-down", "›", 90, {
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -4, 0, 0),
                Size = UDim2.new(0, ARROW, 1, 0),
            })
            for button, direction in pairs({ [up] = -1, [down] = 1 }) do
                local icon = direction < 0 and entry.UpIcon or entry.DownIcon
                local isTap = tapGuard(button, listScroller)
                button.MouseEnter:Connect(function()
                    if not usingTouch() then
                        tween(icon.Object, { [icon.Color] = Theme.Accent }, 0.12)
                    end
                end)
                button.MouseLeave:Connect(function()
                    tween(icon.Object, { [icon.Color] = Theme.Muted }, 0.2)
                end)
                button.MouseButton1Click:Connect(function()
                    if isTap() then
                        nudge(entry, direction)
                    end
                end)
                table.insert(buttons, button)
            end
        end
        grip.InputBegan:Connect(function(input)
            if isPress(input) then
                beginDrag(entry)
            end
        end)
        -- On PC the whole row drags; on touch only the grip does, so a swipe
        -- across the rows still scrolls.
        row.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
                return
            end
            local point = pointerPosition()
            for _, button in ipairs(buttons) do
                if pointInside(point, button) then
                    return
                end
            end
            beginDrag(entry)
        end)
        row.MouseEnter:Connect(function()
            if not usingTouch() and entry ~= dragging then
                tween(entry.Stroke, { Color = Theme.StrokeHover }, 0.12)
                tint(entry.GripIcon, Theme.Text, 0, 0.12)
            end
        end)
        row.MouseLeave:Connect(function()
            if entry ~= dragging then
                tween(entry.Stroke, { Color = Theme.Stroke }, 0.25)
                tint(entry.GripIcon, Theme.Muted, 0, 0.25)
            end
        end)
        return entry
    end

    -- Reuses the rows whose item is still in the list, so a reorder slides
    -- rows instead of rebuilding them.
    local function build(list)
        local pool = {}
        for _, entry in ipairs(entries) do
            pool[entry.Value] = pool[entry.Value] or {}
            table.insert(pool[entry.Value], entry)
        end
        local nextEntries = {}
        for index, value in ipairs(list) do
            local bucket = pool[value]
            local entry = bucket and table.remove(bucket, 1)
            if not entry then
                entry = newEntry(value)
                entry.Frame.Position = UDim2.fromOffset(3, slotY(index))
            end
            nextEntries[index] = entry
        end
        for _, bucket in pairs(pool) do
            for _, entry in ipairs(bucket) do
                entry.Frame:Destroy()
            end
        end
        entries = nextEntries
    end

    -- items sorted by where they sit in ranking; the rest keep their order after.
    local function arrange(items, ranking)
        local left = {}
        for _, value in ipairs(items) do
            left[value] = (left[value] or 0) + 1
        end
        local result = {}
        for _, pass in ipairs({ ranking, items }) do
            for _, value in ipairs(pass) do
                if (left[value] or 0) > 0 then
                    left[value] -= 1
                    table.insert(result, value)
                end
            end
        end
        return result
    end

    local function scrollIntoView(slot)
        local top = slotY(slot) - 1
        local view = scroller.AbsoluteWindowSize.Y / window.Scale.Scale
        local y = scroller.CanvasPosition.Y
        if top < y then
            y = top
        elseif top + ROW + 2 > y + view then
            y = top + ROW + 2 - view
        end
        if y ~= scroller.CanvasPosition.Y then
            tween(scroller, { CanvasPosition = Vector2.new(0, math.max(y, 0)) }, 0.2)
        end
    end

    function nudge(entry, direction)
        if dragging then
            return
        end
        local from = table.find(entries, entry)
        local to = from and from + direction
        if not to or to < 1 or to > #entries then
            return
        end
        entries[from], entries[to] = entries[to], entries[from]
        layout(false)
        tween(entry.Stroke, { Color = Theme.Accent }, 0.08)
        task.delay(0.18, function()
            if entry ~= dragging then
                tween(entry.Stroke, { Color = Theme.Stroke }, 0.3)
            end
        end)
        scrollIntoView(to)
        changed(false)
    end

    local grabOffset, lastPointer = 0, nil
    local startEntries, stopRender, lockedPage = nil, nil, nil

    -- Moves the held row under the pointer and slides the others out of its way.
    local function follow(pointer)
        local scale = window.Scale.Scale
        local y = (pointer.Y - grabOffset - scroller.AbsolutePosition.Y) / scale + scroller.CanvasPosition.Y
        y = math.clamp(y, slotY(1), slotY(#entries))
        dragging.Frame.Position = UDim2.fromOffset(3, y)
        local slot = math.clamp(math.floor((y - 1) / STEP + 0.5) + 1, 1, #entries)
        local current = table.find(entries, dragging)
        if current ~= slot then
            table.remove(entries, current)
            table.insert(entries, slot, dragging)
            layout(false)
        end
    end

    -- Holding the row near the list's top or bottom edge scrolls it, faster
    -- the closer the pointer gets.
    local function autoScroll(deltaTime)
        if not dragging or not lastPointer then
            return
        end
        local scale = window.Scale.Scale
        local top = scroller.AbsolutePosition.Y
        local bottom = top + scroller.AbsoluteSize.Y
        local zone = ROW * scale
        local speed = 0
        if lastPointer.Y < top + zone then
            speed = -(top + zone - lastPointer.Y) / zone
        elseif lastPointer.Y > bottom - zone then
            speed = (lastPointer.Y - (bottom - zone)) / zone
        end
        if speed == 0 then
            return
        end
        local maxScroll = math.max(scroller.CanvasSize.Y.Offset - scroller.AbsoluteWindowSize.Y / scale, 0)
        local y = math.clamp(scroller.CanvasPosition.Y + math.clamp(speed, -1.5, 1.5) * 360 * deltaTime, 0, maxScroll)
        if y ~= scroller.CanvasPosition.Y then
            scroller.CanvasPosition = Vector2.new(0, y)
            follow(lastPointer)
        end
    end

    function beginDrag(entry)
        if dragging or #entries < 2 or self_._destroyed then
            return
        end
        dragging = entry
        startEntries = table.clone(entries)
        lastPointer = pointerPosition()
        grabOffset = lastPointer.Y - entry.Frame.AbsolutePosition.Y
        entry.Frame.ZIndex = 5
        tween(entry.Frame, { BackgroundColor3 = Theme.Surface3 }, 0.12)
        tween(entry.Stroke, { Color = Theme.Accent }, 0.12)
        tween(entry.Scale, { Scale = 1.02 }, 0.18, Enum.EasingStyle.Back)
        tint(entry.GripIcon, Theme.Accent, 0, 0.12)
        -- Neither the list nor the page scrolls under the finger while dragging.
        scroller.ScrollingEnabled = false
        local page = frame:FindFirstAncestorWhichIsA("ScrollingFrame")
        if page and page.ScrollingEnabled then
            lockedPage = page
            page.ScrollingEnabled = false
        end
        stopRender = window:_listen("Render", autoScroll)
    end

    local function endDrag(silent)
        local entry = dragging
        if not entry then
            return
        end
        dragging = nil
        lastPointer = nil
        if stopRender then
            stopRender()
            stopRender = nil
        end
        if lockedPage then
            lockedPage.ScrollingEnabled = true
            lockedPage = nil
        end
        tween(entry.Frame, { BackgroundColor3 = Theme.Surface }, 0.2)
        tween(entry.Stroke, { Color = Theme.Stroke }, 0.25)
        tween(entry.Scale, { Scale = 1 }, 0.2)
        tint(entry.GripIcon, Theme.Muted, 0, 0.25)
        task.delay(0.22, function()
            if entry ~= dragging then
                entry.Frame.ZIndex = 1
            end
        end)
        layout(false)
        fit()
        for index, other in ipairs(entries) do
            if startEntries[index] ~= other then
                changed(silent)
                break
            end
        end
    end

    window:_listen("Changed", function(input)
        if dragging and isMove(input) then
            lastPointer = pointerPosition()
            follow(lastPointer)
        end
    end, self_)
    window:_listen("Ended", function(input)
        if dragging and isPress(input) then
            endDrag(false)
        end
    end, self_)
    table.insert(self_._listeners, function()
        endDrag(true)
    end)
    self_._onHide = function()
        endDrag(false)
    end

    -- Reorders the items already in the list. Unknown items are remembered for
    -- a later Refresh; items missing from the list keep their order after.
    function self_:Set(list, silent)
        if type(list) ~= "table" then
            return
        end
        endDrag(true)
        remembered = table.clone(list)
        build(arrange(values(), remembered))
        layout(false)
        fit()
        changed(silent)
    end

    function self_:Get()
        return values()
    end

    -- Replaces the items. Items that were already there keep the player's
    -- order unless keepOrder is false; new ones go to the end.
    function self_:Refresh(items, keepOrder, silent)
        endDrag(true)
        items = type(items) == "table" and table.clone(items) or {}
        if keepOrder ~= false then
            items = arrange(items, self_:_saveValue())
        else
            remembered = {}
        end
        build(items)
        layout(false)
        fit()
        changed(silent)
    end

    -- The shown order, then remembered items that aren't in the list right now.
    function self_:_saveValue()
        local list = values()
        local left = {}
        for _, value in ipairs(list) do
            left[value] = (left[value] or 0) + 1
        end
        for _, value in ipairs(remembered) do
            if (left[value] or 0) > 0 then
                left[value] -= 1
            else
                table.insert(list, value)
            end
        end
        return list
    end

    build(type(opts.Items) == "table" and opts.Items or {})
    layout(true)
    fit()
    self_.Value = values()
    return finishElement(self, opts, self_, frame, "OrderList")
end


for name, method in pairs(table.clone(Tab)) do
    if type(method) == "function" and name:sub(1, 1) ~= "_" and name:sub(1, 6) ~= "Create" then
        Tab["Create" .. name] = method
    end
end

local function detectExecutor()
    local name
    pcall(function()
        if typeof(identifyexecutor) == "function" then
            name = (identifyexecutor())
        elseif typeof(getexecutorname) == "function" then
            name = getexecutorname()
        end
    end)
    if type(name) == "string" and #name > 0 then
        return name
    end
    return RunService:IsStudio() and "Studio" or "Unknown"
end

local function executorReport(opts)
    local executor = detectExecutor()
    local supported = opts.SupportedExecutors
    if type(supported) == "table" then
        local lowered = string.lower(executor)
        for _, name in ipairs(supported) do
            if string.find(lowered, string.lower(tostring(name)), 1, true) then
                return executor, true, "Your executor is supported and fully compatible."
            end
        end
        return executor, false, "Not on the supported list. Some features may not work."
    end
    local capabilities = {
        { "writefile", writefile },
        { "readfile", readfile },
        { "getcustomasset", getcustomasset },
        { "setclipboard", setclipboard or toclipboard },
        { "request", request or http_request or (syn and syn.request) },
    }
    local missing = {}
    for _, entry in ipairs(capabilities) do
        if type(entry[2]) ~= "function" then
            table.insert(missing, entry[1])
        end
    end
    if #missing == 0 then
        return executor, true, "Your executor is supported and fully compatible."
    end
    return executor, false, "Missing " .. table.concat(missing, ", ") .. ". Some features may not work."
end

-- "Don't ask again" on the unsupported executor warning: the executor's
-- name goes in a file in the script folder, and the warning is skipped while
-- the same executor is in use. Resetting the folder brings it back.
-- A table, not separate locals: the main chunk is at Luau's 200 local limit.
local UnsupportedSkip = {}

function UnsupportedSkip.Path(folder)
    return tostring(folder) .. "/unsupported_skip.txt"
end

function UnsupportedSkip.Available()
    return type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
end

function UnsupportedSkip.Saved(folder, executor)
    if not UnsupportedSkip.Available() then
        return false
    end
    local path = UnsupportedSkip.Path(folder)
    local ok, saved = pcall(function()
        return isfile(path) and readfile(path) or nil
    end)
    return ok and saved == executor
end

function UnsupportedSkip.Write(folder, path, content)
    if not UnsupportedSkip.Available() then
        return false
    end
    return pcall(function()
        if type(isfolder) == "function" and type(makefolder) == "function" then
            local built = ""
            for segment in tostring(folder):gmatch("[^/\\]+") do
                built = built == "" and segment or built .. "/" .. segment
                if not isfolder(built) then
                    makefolder(built)
                end
            end
        end
        writefile(path, content)
    end)
end

function UnsupportedSkip.Save(folder, executor)
    return UnsupportedSkip.Write(folder, UnsupportedSkip.Path(folder), executor)
end

-- Custom disclaimers ticked "Don't show again": one key per line in
-- disclaimers.txt. The key is the disclaimer's Id, or a hash of its title
-- and text, so rewording a disclaimer shows it again.
function UnsupportedSkip.DisclaimerKey(entry)
    if entry.Id ~= nil then
        return (tostring(entry.Id):gsub("[\r\n]", " "))
    end
    local source = tostring(entry.Title) .. "\0" .. tostring(entry.Text)
    local hash = 5381
    for index = 1, #source do
        hash = (hash * 33 + source:byte(index)) % 4294967296
    end
    return string.format("%08x", hash)
end

function UnsupportedSkip.DisclaimerAccepted(folder, key)
    if not UnsupportedSkip.Available() then
        return false
    end
    local path = tostring(folder) .. "/disclaimers.txt"
    local ok, saved = pcall(function()
        return isfile(path) and readfile(path) or ""
    end)
    if not ok or type(saved) ~= "string" then
        return false
    end
    for line in saved:gmatch("[^\r\n]+") do
        if line == key then
            return true
        end
    end
    return false
end

function UnsupportedSkip.AcceptDisclaimer(folder, key)
    if UnsupportedSkip.DisclaimerAccepted(folder, key) then
        return true
    end
    local path = tostring(folder) .. "/disclaimers.txt"
    local ok, saved = pcall(function()
        return isfile(path) and readfile(path) or ""
    end)
    saved = ok and type(saved) == "string" and saved or ""
    if saved ~= "" and not saved:match("\n$") then
        saved ..= "\n"
    end
    return UnsupportedSkip.Write(folder, path, saved .. key .. "\n")
end

local gameInfoCache = nil

local function fetchGameInfo()
    if gameInfoCache == nil then
        local ok, info = pcall(function()
            return MarketplaceService:GetProductInfo(game.PlaceId)
        end)
        gameInfoCache = ok and type(info) == "table" and info or false
    end
    return gameInfoCache or nil
end

local function detectGameName()
    local info = fetchGameInfo()
    if info and info.Name then
        return info.Name
    end
    return RunService:IsStudio() and "Studio" or "Unknown game"
end

local REGION_NAMES = {
    US = "United States", GB = "United Kingdom", DE = "Germany", FR = "France",
    NL = "Netherlands", SG = "Singapore", JP = "Japan", AU = "Australia",
    BR = "Brazil", IN = "India", HK = "Hong Kong", CA = "Canada",
}

local function detectRegion(callback)
    task.spawn(function()
        local requester = request or http_request or (syn and syn.request) or (http and http.request)
        local region
        if type(requester) == "function" then
            pcall(function()
                local response = requester({ Url = "https://ipinfo.io/json", Method = "GET" })
                local body = type(response) == "table" and (response.Body or response.body) or nil
                if type(body) == "string" then
                    local data = HttpService:JSONDecode(body)
                    if type(data) == "table" and data.country then
                        local label = REGION_NAMES[data.country] or data.country
                        region = data.city and (data.city .. ", " .. label) or label
                    end
                end
            end)
        end
        callback(region or "Unavailable")
    end)
end

local NOTIFY_COLORS = setmetatable({}, {
    __index = function(_, kind)
        if kind == "Success" or kind == "Warning" or kind == "Error" then
            return Theme[kind]
        end
        return nil
    end,
})

local Window = {}
Window.__index = Window

-- Shared across executions of the script, so a rerun can find the last window.
function Library._registry()
    local ok, env = pcall(function()
        return getgenv and getgenv() or shared
    end)
    env = ok and type(env) == "table" and env or shared
    if type(env) ~= "table" then
        return nil
    end
    if type(env.__RealIggyWindows) ~= "table" then
        env.__RealIggyWindows = {}
    end
    return env.__RealIggyWindows
end

function Library.Window(_, opts)
    opts = normalize(opts, { Name = "Title", LoadingSubtitle = "Subtitle", ToggleUIKeybind = "Keybind" })

    if type(opts.Keybind) == "string" then
        opts.Keybind = Enum.KeyCode[opts.Keybind]
    end
    local size = opts.Size or UDim2.fromOffset(760, 520)
    local keybind = opts.Keybind or Enum.KeyCode.RightControl

    local self = setmetatable({
        Tabs = {},
        CurrentTab = nil,
        Open = true,
        Keybind = keybind,
        _connections = {},
        _controls = {},
        _inputListeners = { Began = {}, Changed = {}, Ended = {}, Render = {} },
        _frameSteps = {},
        _destroyed = false,
        _identity = { Names = {}, Avatars = {} },
        _pinned = {},
        Minimized = false,
        _hideName = false,
        _hideAvatar = false,
        Title = opts.Title or "RealIggyLib",
        _logoIcon = opts.Icon or Assets.Logo,
        _sessionStart = os.clock(),
        _islandLocked = opts.IslandDraggable == false,
    }, Window)
    local saving = type(opts.ConfigurationSaving) == "table" and opts.ConfigurationSaving or {}
    self.ConfigFolder = saving.FolderName or "RealIggyUI"
    -- Re-executing the script unloads the copy it left behind first, so the
    -- old toggles stop before the new autoload starts them again.
    self._registryKey = "RealIggyLib:" .. tostring(self.ConfigFolder) .. ":" .. tostring(opts.Title or "RealIggyLib")
    local registry = Library._registry()
    if registry then
        local previous = registry[self._registryKey]
        if type(previous) == "table" and type(previous.Destroy) == "function" then
            pcall(previous.Destroy, previous)
        end
        registry[self._registryKey] = self
    end
    self.ConfigName = saving.FileName
    self._configListeners = {}
    self._pendingFlags = {}
    self._autosave = false
    task.spawn(function()
        while not self._destroyed do
            task.wait(10)
            if self._autosave and (self.LoadedConfig or self.ConfigName) then
                pcall(self.SaveConfig, self, self.LoadedConfig or self.ConfigName)
            end
        end
    end)

    if opts.AccentGradient ~= nil then
        Library.AccentGradient = opts.AccentGradient == true
    end
    if opts.AccentAngle ~= nil then
        Library.AccentAngle = tonumber(opts.AccentAngle) or 360
    end
    if opts.Shimmer ~= nil then
        Library.Shimmer = opts.Shimmer == true
    end

    local startTheme = opts.DefaultTheme or opts.Theme
    if startTheme ~= nil then
        Library.DefaultTheme = startTheme
    end
    self:_applyDefaultTheme()
    self._uiScale = math.clamp(tonumber(opts.UIScale) or 1, 0.6, 1.5)
    self._adaptive = opts.AdaptiveSize ~= false
    self.UIScale = self._uiScale
    if opts.Density ~= nil then
        Library:SetDensity(opts.Density)
    end
    if opts.CornerRadius ~= nil then
        Library:SetCornerRadius(opts.CornerRadius, true)
    end
    local function dispatch(kind)
        return function(...)
            for _, handler in ipairs(self._inputListeners[kind]) do
                handler(...)
            end
        end
    end
    local renderDispatch = dispatch("Render")
    table.insert(self._connections, RunService.RenderStepped:Connect(function(deltaTime)
        renderDispatch(deltaTime)
        for _, step in ipairs(self._frameSteps) do
            step(deltaTime)
        end
    end))
    table.insert(self._connections, UserInputService.InputBegan:Connect(dispatch("Began")))
    table.insert(self._connections, UserInputService.InputChanged:Connect(dispatch("Changed")))
    table.insert(self._connections, UserInputService.InputEnded:Connect(dispatch("Ended")))

    local gui = create("ScreenGui", {
        Name = opts.Name or "RealIggyUI",
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
        DisplayOrder = 999,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    self.Gui = gui

    local root = create("Frame", {
        Name = "Window",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = size,
        BackgroundTransparency = 1,
        Parent = gui,
    })
    self.Root = root
    local scale = create("UIScale", { Parent = root })
    self.Scale = scale

    local shadow = create("ImageLabel", {
        Position = UDim2.fromOffset(-25, -25),
        Size = UDim2.new(1, 50, 1, 50),
        BackgroundTransparency = 1,
        Image = Assets.Shadow,
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = 0.6,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450),
        Parent = root,
    })
    self.Shadow = shadow
    self._shadowRest = 0.6

    -- The body is a plain Frame so resizing never re-renders the window into a
    -- texture. It only moves into the fader CanvasGroup while fading.
    local fader = create("CanvasGroup", {
        Name = "Fader",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        GroupTransparency = 1,
        ZIndex = 2,
        Parent = root,
    })
    self._fader = fader
    self._bodyAlpha = 1
    local body = create("Frame", {
        Name = "Body",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 2,
        Parent = fader,
    })
    self.Body = body
    corner(body, UDim.new(0, 10))
    self.BodyStroke = stroke(body, Theme.Stroke)
    edgeHighlight(body)
    -- Background image: made first so everything else in the body draws over it.
    self._backgroundImage = create("ImageLabel", {
        Name = "BackgroundImage",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ScaleType = Enum.ScaleType.Crop,
        ImageTransparency = 1,
        Visible = false,
        ZIndex = 0,
        Parent = body,
    })
    corner(self._backgroundImage, UDim.new(0, 10))
    self.BackgroundTransparency = math.clamp(tonumber(opts.BackgroundTransparency) or 0.35, 0, 1)
    self._backgroundGeneration = 0

    -- The sidebar is a flush, solid rail down the left edge, split from the
    -- content by a single hairline.
    local sidebar = create("Frame", {
        Name = "Sidebar",
        Size = UDim2.new(0, SIDEBAR_WIDTH, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = body,
    })
    self.Sidebar = sidebar
    -- One rounded fill that runs past the rail's right edge, where the rail
    -- clips it: the left corners round with the window, the right edge is
    -- square, and nothing overlaps, so it fades evenly when see-through.
    local sidebarFill = create("Frame", {
        Name = "Fill",
        Size = UDim2.new(1, 24, 1, 0),
        BackgroundColor3 = Theme.TabStructure,
        BorderSizePixel = 0,
        ZIndex = 0,
        Parent = sidebar,
    })
    bindTheme(sidebarFill, "BackgroundColor3", "TabStructure")
    corner(sidebarFill, UDim.new(0, 10))
    self.SidebarFill = sidebarFill
    create("Frame", {
        Name = "Divider",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.fromScale(1, 0),
        Size = UDim2.new(0, 1, 1, 0),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        ZIndex = 2,
        Parent = sidebar,
    })

    local header = create("Frame", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
        BackgroundTransparency = 1,
        Parent = sidebar,
    })
    local logo = create("ImageLabel", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 14, 0.5, 0),
        Size = UDim2.fromOffset(32, 32),
        BackgroundTransparency = 1,
        Image = "",
        ImageColor3 = Theme.Accent,
        ScaleType = Enum.ScaleType.Fit,
        Parent = header,
    })
    applyIcon(logo, opts.Icon or Assets.Logo, true)
    local subtitle = opts.Version or opts.Subtitle
    local showSubtitle = subtitle ~= false
    label({
        Position = UDim2.new(0, 56, 0.5, showSubtitle and -15 or -9),
        Size = UDim2.new(1, -68, 0, 18),
        Text = self.Title,
        TextSize = 14,
        FontFace = Fonts.Bold,
        Parent = header,
    })
    if showSubtitle then
        local subLabel = label({
            Position = UDim2.new(0, 56, 0.5, 3),
            Size = UDim2.new(1, -68, 0, 14),
            Text = tostring(subtitle or ""),
            TextSize = 11,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            Parent = header,
        })
        if subtitle == nil or subtitle == "" or subtitle == "Airflow Engine" then
            task.spawn(function()
                local name = detectGameName()
                if name and subLabel and subLabel.Parent then
                    subLabel.Text = name
                end
            end)
        end
    end

    local profileEnabled = opts.Profile ~= false
    local tabList = create("ScrollingFrame", {
        Name = "Tabs",
        Position = UDim2.fromOffset(0, HEADER_HEIGHT),
        Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + (profileEnabled and PROFILE_HEIGHT + 4 or 12))),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        Parent = sidebar,
    })
    self.TabList = tabList
    -- The highlight sits beside the stack of buttons, so it scrolls and clips
    -- with them and glides between tiles.
    local indicator = create("Frame", {
        Position = UDim2.fromOffset(8, 2),
        Size = UDim2.new(1, -16, 0, TAB_TILE_HEIGHT),
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Visible = false,
        Parent = tabList,
    })
    corner(indicator, UDim.new(0, 7))
    -- The active tab is just a quiet neutral fill with white text; the bar
    -- is kept for callers but stays hidden.
    local pill = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(2, 14),
        BackgroundColor3 = Theme.Accent,
        Visible = false,
        BorderSizePixel = 0,
        Parent = indicator,
    })
    corner(pill, UDim.new(1, 0))
    attachAccentGradient(pill, { Active = true })
    self._indicatorPill = pill
    self.Indicator = indicator
    local stack = create("Frame", {
        Name = "Stack",
        Position = UDim2.fromOffset(8, 2),
        Size = UDim2.new(1, -16, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        ZIndex = 2,
        Parent = tabList,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = stack,
    })
    self._tabStack = stack

    -- More tabs than fit: a fade and a small "more" chip at the hidden end.
    self:_overflowHint(sidebar, tabList, stack, true, Theme.Surface)

    if profileEnabled then
        self:_buildProfile(sidebar)
    end

    local content = create("Frame", {
        Name = "Content",
        Position = UDim2.fromOffset(SIDEBAR_WIDTH + 1, 0),
        Size = UDim2.new(1, -(SIDEBAR_WIDTH + 1), 1, 0),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Parent = body,
    })
    self.Content = content
    self:_sidebarResize(sidebar, tonumber(opts.SidebarWidth) or SIDEBAR_WIDTH)
    self._outLayer = create("CanvasGroup", {
        Name = "TransitionOut",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 2,
        Parent = content,
    })
    self._inLayer = create("CanvasGroup", {
        Name = "TransitionIn",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 3,
        Parent = content,
    })

    local minimizeButton = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -14, 0, 14),
        Size = UDim2.fromOffset(34, 34),
        BackgroundColor3 = Theme.Surface2,
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 5,
        Parent = content,
    })
    minimizeButton:SetAttribute("NoDrag", true)
    -- A bare "minimize" arrows glyph, no box: muted at rest, full text
    -- colour and a touch smaller on hover, as if pulling in.
    local minimizeGlyph = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(20, 20),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ScaleType = Enum.ScaleType.Fit,
        Parent = minimizeButton,
    })
    applyIcon(minimizeGlyph, "minimize-2")
    minimizeButton.MouseEnter:Connect(function()
        tween(minimizeGlyph, { ImageColor3 = Theme.Text, Size = UDim2.fromOffset(18, 18) }, 0.2, Enum.EasingStyle.Quint)
    end)
    minimizeButton.MouseLeave:Connect(function()
        tween(minimizeGlyph, { ImageColor3 = Theme.Muted, Size = UDim2.fromOffset(20, 20) }, 0.25, Enum.EasingStyle.Quint)
    end)
    minimizeButton.MouseButton1Click:Connect(function()
        self:Minimize()
    end)
    self.MinimizeButton = minimizeButton

    if opts.Search ~= false then
        self:_buildSearch(content)
    end

    local notifyHolder = create("Frame", {
        Name = "Notifications",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -20, 1, -20),
        Size = UDim2.new(0, 280, 1, -40),
        BackgroundTransparency = 1,
        Parent = gui,
    })
    local function fitToasts()
        notifyHolder.Size = UDim2.new(0, math.min(280, gui.AbsoluteSize.X - 40), 1, -40)
    end
    table.insert(self._connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitToasts))
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        Padding = UDim.new(0, 4),
        Parent = notifyHolder,
    })
    self.NotifyHolder = notifyHolder
    self._notifyOrder = 0
    self._toasts = {}
    self.MaxNotifications = opts.MaxNotifications or 4

    self._controlsDirty = true
    table.insert(self._connections, body.DescendantAdded:Connect(function()
        self._controlsDirty = true
    end))
    table.insert(self._connections, body.DescendantRemoving:Connect(function()
        self._controlsDirty = true
    end))

    self:SetDragStyle(opts.DragStyle or (opts.DragSkeleton == false and "Off" or "Outline"))
    self:SetIslandStyle(opts.IslandStyle)
    if opts.Transparent then
        self:SetTransparent(true)
    end
    if opts.Background then
        task.spawn(self.SetBackground, self, opts.Background)
    end
    self:_enableDrag()
    self.MaxSize = opts.MaxSize
    self.KeepOnScreen = opts.KeepOnScreen ~= false
    self:_enableResize(opts.MinSize or Vector2.new(480, 360))
    -- The window's exact size rides along in configs as a hidden flag.
    if opts.SaveSize ~= false then
        local window = self
        local sizeFlag = { _type = "WindowSize", _listeners = {} }
        function sizeFlag:Get()
            local current = window:GetSize()
            return { Width = current.X, Height = current.Y }
        end
        function sizeFlag:Set(value)
            if type(value) == "table" and tonumber(value.Width) and tonumber(value.Height) then
                window:SetSize(Vector2.new(tonumber(value.Width), tonumber(value.Height)))
            end
        end
        local flag = type(opts.SaveSize) == "string" and opts.SaveSize or "__WindowSize"
        Library.Flags[flag] = sizeFlag
        self:_flagCreated(flag, sizeFlag)
    end

    table.insert(self._connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then
            return
        end
        if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == self.Keybind then
            task.defer(function()
                local consumed = self._consumedKey == input.KeyCode and os.clock() - (self._consumedAt or 0) < 0.2
                self._consumedKey = nil
                if not consumed and not self._destroyed then
                    if self.Minimized then
                        self:Restore()
                    else
                        self:Toggle(not self.Open)
                    end
                end
            end)
        end
    end))

    pcall(function()
        if typeof(syn) == "table" and typeof(syn.protect_gui) == "function" then
            syn.protect_gui(gui)
        end
    end)
    gui.Parent = opts.Parent or defaultParent()

    scale.Scale = 0.9
    shadow.ImageTransparency = 1
    self.BodyStroke.Transparency = 1
    root.Visible = false
    self:_fitToScreen(true)
    table.insert(self._connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        self:_fitToScreen()
        self:_clampToScreen()
    end))
    local toggleOpts = opts.ToggleButton
    if toggleOpts == nil or toggleOpts == true then
        toggleOpts = {}
    end
    if type(toggleOpts) == "table" then
        self:_createToggleButton(toggleOpts)
    end
    -- The toggle button already brings a hidden window back.
    local toggleShown = self.ToggleButton ~= nil and self:_toggleButtonAllowed()
    if (opts.OpenButton ~= nil and opts.OpenButton ~= false) or (opts.OpenButton == nil and TOUCH and not toggleShown) then
        self:_createOpenButton(type(opts.OpenButton) == "table" and opts.OpenButton or {})
    end
    if opts.Backdrop ~= false then
        self:_buildBackdrop(type(opts.Backdrop) == "table" and opts.Backdrop or {})
    end
    self._introDone = false

    table.insert(Library.Windows, self)

    if opts.Home ~= false then
        self:_buildHome(type(opts.Home) == "table" and opts.Home or {})
    end

    local loading = opts.Loading
    if type(loading) == "table" then
        opts.LoadingDuration = loading.Duration or opts.LoadingDuration
        opts.LoadingText = loading.Text or loading.Subtitle or opts.LoadingText
        opts.LoadingSteps = loading.Steps or opts.LoadingSteps
        opts.LoadingTitle = loading.Title or opts.LoadingTitle
        loading = loading.Enabled ~= false
    end
    -- An executor off the supported list (or missing the file / asset API)
    -- stops at a warning card before the window opens.
    local prompts = {}
    local gate = opts.UnsupportedExecutor
    if gate ~= false then
        gate = type(gate) == "table" and gate or {}
        local list = opts.SupportedExecutors or (type(opts.Home) == "table" and opts.Home.SupportedExecutors or nil)
        local executor, supported, message = executorReport({ SupportedExecutors = list })
        if not supported and not UnsupportedSkip.Saved(self.ConfigFolder, executor) then
            local block = gate.Block == true
            local folder = self.ConfigFolder
            table.insert(prompts, {
                Title = gate.Title or "Unsupported executor",
                Subtitle = executor,
                Text = block and ((gate.Text or message) .. " This script can't run here.") or (gate.Text or message),
                Icon = "shield-alert",
                Color = Theme.Warning,
                ContinueText = "Continue anyway",
                ExitText = "Exit",
                Block = block,
                RememberText = "Don't ask again on this executor",
                Remember = function()
                    UnsupportedSkip.Save(folder, executor)
                end,
            })
        end
    end
    -- Custom disclaimers queue up after the executor warning, in order. Each
    -- one must be accepted (or skipped by an earlier "Don't show again").
    local disclaimers = opts.Disclaimer or opts.Disclaimers
    if type(disclaimers) == "string" or (type(disclaimers) == "table" and (disclaimers.Title ~= nil or disclaimers.Text ~= nil)) then
        disclaimers = { disclaimers }
    end
    if type(disclaimers) == "table" then
        for _, entry in ipairs(disclaimers) do
            if type(entry) == "string" then
                entry = { Text = entry }
            end
            if type(entry) == "table" then
                local key = UnsupportedSkip.DisclaimerKey(entry)
                local folder = self.ConfigFolder
                local block = entry.Block == true
                local rememberable = entry.Remember ~= false and not block
                if not (rememberable and UnsupportedSkip.DisclaimerAccepted(folder, key)) then
                    local callback = entry.Callback
                    table.insert(prompts, {
                        Title = entry.Title or "Disclaimer",
                        Subtitle = entry.Subtitle,
                        Text = entry.Text or "",
                        Icon = entry.Icon or "info",
                        Color = entry.Color or Theme.Accent,
                        ContinueText = entry.AcceptText or "I understand",
                        ExitText = entry.DeclineText == nil and "Exit" or entry.DeclineText,
                        RememberText = rememberable and (entry.RememberText or "Don't show again") or nil,
                        Remember = function()
                            UnsupportedSkip.AcceptDisclaimer(folder, key)
                        end,
                        Callback = type(callback) == "function" and callback or nil,
                        Block = block,
                    })
                end
            end
        end
    end
    if #prompts > 0 then
        opts._prompts = prompts
    end
    if loading == false and opts._prompts then
        opts.LoadingDuration = opts.LoadingDuration or 0.5
        loading = true
    end
    if loading == false then
        task.defer(function()
            self:_playIntro()
        end)
    else
        self:_showLoader(opts)
    end
    return self
end

Library.CreateWindow = Library.Window



function Library:Notify(opts)
    local window = Library.Windows[#Library.Windows]
    if window then
        return window:Notify(opts)
    end
end

function Library:Confirm(opts)
    local window = Library.Windows[#Library.Windows]
    if window then
        return window:Confirm(opts)
    end
end

function Library:Dialog(opts)
    local window = Library.Windows[#Library.Windows]
    if window then
        return window:Dialog(opts)
    end
end

local function isShown(object, stopAt, point)
    local child = object
    while child and child ~= stopAt and child:IsA("GuiObject") do
        if not child.Visible then
            return false
        end
        local parent = child.Parent
        if parent and parent ~= stopAt and parent:IsA("GuiObject") and (parent.ClipsDescendants or parent:IsA("ScrollingFrame")) and not pointInside(point, parent) then
            return false
        end
        child = parent
    end
    return true
end

function Window:_refreshControls()
    local controls = {}
    for _, object in ipairs(self.Body:GetDescendants()) do
        if object:IsA("GuiButton") or object:IsA("TextBox") or object:GetAttribute("NoDrag") then
            table.insert(controls, object)
        end
    end
    self._controls = controls
    self._controlsDirty = false
end

function Window:_overControl(point)
    if self._dialog or self:_overPopout(point) then
        return true
    end
    if self._controlsDirty then
        self:_refreshControls()
    end
    for _, object in ipairs(self._controls) do
        if object.Parent and pointInside(point, object) and isShown(object, self.Body, point) then
            return true
        end
    end
    return false
end

-- Tooltips: one shared card per window that follows the pointer over any
-- element built with Tooltip = "..." or { Title, Text, Icon }. It appears
-- after a short hover (straight away when moving from one tooltip to the
-- next), hides on press, and shows on a long press on touch screens.
function Window:_tooltipCard()
    if self._tip then
        return self._tip
    end
    local holder = create("CanvasGroup", {
        Name = "Tooltip",
        Size = UDim2.fromOffset(0, 0),
        BackgroundTransparency = 1,
        GroupTransparency = 1,
        Visible = false,
        ZIndex = 60,
        Parent = self.Gui,
    })
    local tipScale = create("UIScale", { Parent = holder })
    -- Bare text, no card: a dark outline keeps it readable over anything.
    -- The holder is sized from the text by hand, since scale sizes inside an
    -- automatic size would stretch it across the screen.
    local PAD = 4
    local panel = create("Frame", {
        Position = UDim2.fromOffset(PAD, PAD),
        Size = UDim2.fromOffset(0, 0),
        AutomaticSize = Enum.AutomaticSize.XY,
        BackgroundTransparency = 1,
        Parent = holder,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = panel,
    })
    local function outline(object)
        create("UIStroke", {
            Color = Color3.new(0, 0, 0),
            Transparency = 0.35,
            Thickness = 1,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
            Parent = object,
        })
    end
    local head = create("Frame", {
        Size = UDim2.fromOffset(0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        LayoutOrder = 1,
        Parent = panel,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = head,
    })
    local icon = create("ImageLabel", {
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Accent,
        ScaleType = Enum.ScaleType.Fit,
        LayoutOrder = 1,
        Parent = head,
    })
    local title = label({
        Size = UDim2.fromOffset(0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
        TextSize = 13,
        FontFace = Fonts.Bold,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        Parent = head,
    })
    outline(title)
    local body = label({
        Size = UDim2.fromOffset(0, 0),
        AutomaticSize = Enum.AutomaticSize.XY,
        TextSize = 12,
        FontFace = Fonts.Medium,
        TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None,
        TextYAlignment = Enum.TextYAlignment.Top,
        LineHeight = 1.1,
        LayoutOrder = 2,
        Parent = panel,
    })
    outline(body)
    create("UISizeConstraint", { MaxSize = Vector2.new(240, math.huge), Parent = body })
    local function fit()
        local scale = math.max(tipScale.Scale, 0.01)
        local size = panel.AbsoluteSize / scale
        holder.Size = UDim2.fromOffset(size.X + PAD * 2, size.Y + PAD * 2)
    end
    panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
    local tip = {
        Holder = holder,
        Scale = tipScale,
        Pad = PAD,
        Head = head,
        Icon = icon,
        Title = title,
        Body = body,
        Shown = false,
        Fit = fit,
    }
    self._tip = tip
    -- Follow the pointer, and drop the card once its element is gone or off
    -- screen (tab switched, window hidden or minimized).
    self:_listen("Render", function(deltaTime)
        local owner = self._tipOwner
        if not owner then
            return
        end
        local frame = owner._frame
        if owner._destroyed or not self.Open or self.Minimized or not frame or not frame.Parent
            or (owner._isShown and not owner:_isShown()) or not isShown(frame, self.Body, frame.AbsolutePosition + frame.AbsoluteSize / 2) then
            self:_hideTooltip()
            return
        end
        local pointer = pointerPosition() - self.Gui.AbsolutePosition
        local pad = tip.Pad * tipScale.Scale
        local size = holder.AbsoluteSize - Vector2.one * pad * 2
        local view = self.Gui.AbsoluteSize
        local x, y
        if tip.Touch then
            x, y = pointer.X - size.X / 2, pointer.Y - size.Y - 30
        else
            x, y = pointer.X + 14, pointer.Y + 20
            if x + size.X > view.X - 8 then
                x = pointer.X - size.X - 10
            end
            if y + size.Y > view.Y - 8 then
                y = pointer.Y - size.Y - 12
            end
        end
        local target = Vector2.new(
            math.clamp(x, 8, math.max(8, view.X - size.X - 8)),
            math.clamp(y, 8, math.max(8, view.Y - size.Y - 8))
        )
        local current = tip.Position
        if not current or tip.Snap then
            -- Rises a few pixels into place as it fades in.
            current = target + Vector2.new(0, 6)
            tip.Snap = false
        else
            current = current:Lerp(target, math.min(deltaTime * 22, 1))
        end
        tip.Position = current
        holder.Position = UDim2.fromOffset(math.floor(current.X - pad + 0.5), math.floor(current.Y - pad + 0.5))
    end)
    -- A press anywhere (a dropdown chip inside the card, a key) hides it.
    self:_listen("Began", function(input)
        if self._tipOwner and not tip.Touch and (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.Keyboard) then
            self:_hideTooltip()
        end
    end)
    return tip
end

function Window:_showTooltip(element, touch)
    local value = element._tooltip
    local text, titleText, iconName
    if type(value) == "table" then
        text, titleText, iconName = value.Text or value.Content or value.Desc, value.Title or value.Name, value.Icon
    elseif value ~= nil and value ~= false then
        text = tostring(value)
    end
    if (text == nil or text == "") and (titleText == nil or titleText == "") then
        return
    end
    local tip = self:_tooltipCard()
    tip.Title.Text = titleText or ""
    tip.Title.Visible = titleText ~= nil and titleText ~= ""
    tip.Icon.Visible = iconName ~= nil
    if iconName ~= nil then
        applyIcon(tip.Icon, iconName)
    end
    tip.Head.Visible = tip.Title.Visible or iconName ~= nil
    tip.Body.Text = text or ""
    tip.Body.Visible = text ~= nil and text ~= ""
    tip.Fit()
    tip.Body.TextColor3 = Theme.Text
    tip.Scale.Scale = math.max(self.Scale.Scale, 0.75)
    tip.Touch = touch == true
    local wasShown = tip.Shown
    self._tipOwner = element
    tip.Shown = true
    tip.Generation = (tip.Generation or 0) + 1
    local holder = tip.Holder
    if not wasShown then
        tip.Snap = true
        holder.Visible = true
        holder.GroupTransparency = 1
        tip.Scale.Scale = tip.Scale.Scale * 0.96
    end
    tween(holder, { GroupTransparency = 0 }, 0.14, Enum.EasingStyle.Quad)
    tween(tip.Scale, { Scale = math.max(self.Scale.Scale, 0.75) }, 0.18, Enum.EasingStyle.Back)
end

function Window:_hideTooltip(element)
    local tip = self._tip
    if not tip or not tip.Shown or (element and self._tipOwner ~= element) then
        return
    end
    self._tipOwner = nil
    self._tipHiddenAt = os.clock()
    tip.Shown = false
    tip.Generation = (tip.Generation or 0) + 1
    local generation = tip.Generation
    tween(tip.Holder, { GroupTransparency = 1 }, 0.1, Enum.EasingStyle.Quad)
    task.delay(0.1, function()
        if tip.Generation == generation then
            tip.Holder.Visible = false
        end
    end)
end

function Window:_attachTooltip(element, frame)
    local hovering, token, pressAt = false, 0, nil
    local function begin(delay, touch)
        token += 1
        local mine = token
        task.delay(delay, function()
            if token ~= mine or not hovering or element._destroyed or self._destroyed then
                return
            end
            -- A finger that moved was scrolling, not holding.
            if touch and pressAt and (pointerPosition() - pressAt).Magnitude > 10 then
                return
            end
            self:_showTooltip(element, touch)
        end)
    end
    table.insert(element._listeners, (function()
        local connections = {
            frame.MouseEnter:Connect(function()
                if usingTouch() then
                    return
                end
                hovering = true
                local recent = os.clock() - (self._tipHiddenAt or 0) < 0.35 or self._tipOwner ~= nil
                begin(recent and 0 or 0.45, false)
            end),
            frame.MouseLeave:Connect(function()
                hovering = false
                token += 1
                self:_hideTooltip(element)
            end),
            frame.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.Touch then
                    hovering = true
                    pressAt = pointerPosition()
                    begin(0.5, true)
                end
            end),
            frame.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.Touch then
                    hovering = false
                    token += 1
                    self:_hideTooltip(element)
                end
            end),
        }
        return function()
            for _, connection in ipairs(connections) do
                connection:Disconnect()
            end
        end
    end)())
end

-- While dragging, a stand-in follows the pointer while the window stays put,
-- and the window glides into its spot on release. The look is the player's
-- Drag Style; "Off" drags the window itself.
Library.DragStyles = { "Outline", "Brackets", "Ghost", "Frame", "Off" }

local function makeSkeleton(window)
    local root = window.Root
    local style = window.DragStyle or "Outline"
    local skeleton = create("Frame", {
        AnchorPoint = root.AnchorPoint,
        Position = root.Position,
        Size = UDim2.fromOffset(root.AbsoluteSize.X, root.AbsoluteSize.Y),
        BackgroundColor3 = style == "Ghost" and Theme.Background or Theme.Accent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 40,
        Parent = window.Gui,
    })
    corner(skeleton, UDim.new(0, 10))
    -- Each part fades from hidden to its shown values, and back on release.
    local parts = {}
    local function part(object, shown)
        local hidden = {}
        for key in pairs(shown) do
            hidden[key] = 1
        end
        table.insert(parts, { Object = object, Shown = shown, Hidden = hidden })
    end
    local function brackets(length, inset)
        for _, spot in ipairs({ Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) }) do
            local at = UDim2.new(spot.X, spot.X == 0 and inset or -inset, spot.Y, spot.Y == 0 and inset or -inset)
            for _, size in ipairs({ UDim2.fromOffset(length, 2), UDim2.fromOffset(2, length) }) do
                local bracket = create("Frame", {
                    AnchorPoint = spot,
                    Position = at,
                    Size = size,
                    BackgroundColor3 = Theme.Accent,
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    Parent = skeleton,
                })
                corner(bracket, UDim.new(1, 0))
                part(bracket, { BackgroundTransparency = 0 })
            end
        end
    end
    if style == "Brackets" then
        -- Just the four corners of the window, a little longer.
        brackets(22, 0)
    elseif style == "Ghost" then
        -- A see-through copy of the window's panel.
        part(skeleton, { BackgroundTransparency = 0.35 })
        part(stroke(skeleton, Theme.Stroke, 1, 1), { Transparency = 0 })
    elseif style == "Frame" then
        -- A single quiet line, nothing else.
        part(stroke(skeleton, Theme.StrokeHover, 1, 1), { Transparency = 0 })
    else
        -- Outline: a faint accent wash, an outline and corner brackets.
        part(skeleton, { BackgroundTransparency = 0.92 })
        part(stroke(skeleton, Theme.Accent, 1, 1.5), { Transparency = 0.2 })
        brackets(16, 6)
    end
    local scale = create("UIScale", { Scale = 1.02, Parent = skeleton })
    for _, item in ipairs(parts) do
        tween(item.Object, item.Shown, 0.15, Enum.EasingStyle.Quad)
    end
    tween(scale, { Scale = 1 }, 0.25, Enum.EasingStyle.Quint)
    local function fade()
        for _, item in ipairs(parts) do
            tween(item.Object, item.Hidden, 0.2, Enum.EasingStyle.Quad)
        end
        task.delay(0.22, function()
            skeleton:Destroy()
        end)
    end
    return skeleton, fade
end

function Window:_enableDrag()
    local dragging, moved = false, false
    local grabOffset, pressPoint = Vector2.zero, Vector2.zero
    local target = nil
    local skeleton, fadeSkeleton = nil, nil

    local function centre()
        local root = self.Root
        return root.AbsolutePosition + root.AbsoluteSize * root.AnchorPoint - self.Gui.AbsolutePosition
    end

    local function dropSkeleton()
        if not skeleton then
            return
        end
        local spot = Vector2.new(skeleton.Position.X.Offset, skeleton.Position.Y.Offset)
        if self.KeepOnScreen then
            spot = self:_clampedCentre(spot)
        end
        if self._clampTween then
            self._clampTween:Cancel()
        end
        self._clampTween = tween(self.Root, { Position = UDim2.fromOffset(spot.X, spot.Y) }, 0.3, Enum.EasingStyle.Quint)
        fadeSkeleton()
        skeleton, fadeSkeleton = nil, nil
    end

    table.insert(self._connections, UserInputService.InputBegan:Connect(function(input)
        if not isPress(input) then
            return
        end
        if not self.Open or not self.Root.Visible then
            return
        end
        local point = pointerPosition()
        if self._resizeActive or (self._grip and pointInside(point, self._grip)) then
            return
        end
        if not pointInside(point, self.Body) or self:_overControl(point) then
            return
        end
        if self._clampTween then
            self._clampTween:Cancel()
            self._clampTween = nil
        end
        dragging, moved = true, false
        pressPoint = point
        grabOffset = point - centre()
    end))

    table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
        if not dragging then
            return
        end
        if isPress(input) then
            dragging = false
            target = nil
            if skeleton then
                dropSkeleton()
            else
                self:_clampToScreen()
            end
        end
    end))

    table.insert(self._frameSteps, function(deltaTime)
        if not dragging then
            return
        end
        local point = pointerPosition()
        if not moved and (point - pressPoint).Magnitude > 3 then
            moved = true
            if self.DragSkeleton then
                skeleton, fadeSkeleton = makeSkeleton(self)
            end
        end
        if not moved then
            return
        end
        -- Hidden or minimized mid-drag: land it where the outline is.
        if skeleton and (not self.Open or not self.Root.Visible) then
            dragging = false
            dropSkeleton()
            return
        end
        target = point - grabOffset
        local alpha = 1 - math.exp(-deltaTime * 45)
        if skeleton then
            local current = Vector2.new(skeleton.Position.X.Offset, skeleton.Position.Y.Offset)
            local step = current:Lerp(target, alpha)
            skeleton.Position = UDim2.fromOffset(step.X, step.Y)
        else
            local step = centre():Lerp(target, alpha)
            self.Root.Position = UDim2.fromOffset(step.X, step.Y)
        end
    end)
end

-- One of Library.DragStyles; anything else falls back to "Outline".
-- Returns the style it settled on.
function Window:SetDragStyle(style)
    style = table.find(Library.DragStyles, style) and style or "Outline"
    self.DragStyle = style
    self.DragSkeleton = style ~= "Off"
    return style
end

function Window:GetDragStyle()
    return self.DragStyle
end

-- How the minimized island shows the session card: opening it while
-- hovered, or keeping it open the whole time it's minimized.
Library.IslandStyles = { "Show on Hover", "Always Show" }

-- One of Library.IslandStyles; anything else falls back to "Show on Hover".
-- Returns the style it settled on.
function Window:SetIslandStyle(style)
    style = table.find(Library.IslandStyles, style) and style or "Show on Hover"
    self.IslandStyle = style
    if self._islandSettle then
        self._islandSettle()
    end
    return style
end

function Window:GetIslandStyle()
    return self.IslandStyle
end

-- The older on/off switch: off is the "Off" style, on brings back the
-- default style if it was off.
function Window:SetDragSkeleton(enabled)
    if enabled == false then
        self:SetDragStyle("Off")
    elseif self.DragStyle == "Off" or not self.DragStyle then
        self:SetDragStyle("Outline")
    end
end

-- The sidebar's divider is a grab strip: dragging it sets the rail's width,
-- kept between a usable minimum and enough room for the content.
function Window:_sidebarResize(sidebar, width)
    local divider = sidebar:FindFirstChild("Divider")
    local want = width
    local function apply(value, remember)
        if remember ~= false then
            want = value
        end
        local room = self.Body.AbsoluteSize.X / self.Scale.Scale - 300
        value = math.floor(math.clamp(value, 150, math.max(math.min(300, room), 150)))
        self.SidebarWidth = value
        sidebar.Size = UDim2.new(0, value, 1, 0)
        self.Content.Position = UDim2.fromOffset(value + 1, 0)
        self.Content.Size = UDim2.new(1, -(value + 1), 1, 0)
    end
    self.SetSidebarWidth = function(_, value)
        apply(tonumber(value) or SIDEBAR_WIDTH)
    end
    apply(width)
    local grip = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.new(0, 6, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 6,
        Parent = sidebar,
    })
    grip:SetAttribute("NoDrag", true)
    local dragging, startX, startWidth = false, 0, width
    local function light(on)
        if divider then
            tween(divider, { BackgroundColor3 = on and Theme.Accent or Theme.Stroke }, 0.15)
        end
    end
    grip.MouseEnter:Connect(function()
        light(true)
    end)
    grip.MouseLeave:Connect(function()
        if not dragging then
            light(false)
        end
    end)
    grip.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, startX, startWidth = true, input.Position.X, self.SidebarWidth
            want = startWidth
            light(true)
        end
    end)
    self:_listen("Changed", function(input)
        if dragging and isMove(input) then
            apply(startWidth + (input.Position.X - startX) / self.Scale.Scale)
        end
    end)
    self:_listen("Ended", function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            dragging = false
            light(false)
        end
    end)
    -- Shrinking the window pulls an over-wide rail back in.
    self.Body:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if not dragging then
            apply(want, false)
        end
    end)
end

-- See-through window: the body and sidebar let the game show through, and the
-- shadow lightens so it doesn't smudge behind them.
function Window:SetTransparent(enabled)
    self.Transparent = enabled == true
    local on = self.Transparent
    self._shadowRest = on and 0.85 or 0.6
    tween(self.Body, { BackgroundTransparency = on and 0.35 or 0 }, 0.25)
    -- See-through, the rail stays a touch more solid than the body so the
    -- tabs keep their contrast; over a background image it lets more through.
    local railAlpha = on and 0.5 or (self.Background and 0.45 or 0)
    tween(self.SidebarFill, { BackgroundTransparency = railAlpha }, 0.25)
    if self.Open and not self.Minimized and self.Root.Visible then
        tween(self.Shadow, { ImageTransparency = self._shadowRest }, 0.25)
    end
end

local function orderedChildren(parent)
    local children = {}
    for _, child in ipairs(parent:GetChildren()) do
        if child:IsA("GuiObject") then
            table.insert(children, child)
        end
    end
    table.sort(children, function(a, b)
        return a.LayoutOrder < b.LayoutOrder
    end)
    return children
end

local function popIn(object, delay, force)
    if not object.Visible and not force then
        return
    end
    object.Visible = false
    task.delay(delay, function()
        if not object.Parent then
            return
        end
        local scaleObject = create("UIScale", { Scale = 0.94, Parent = object })
        object.Visible = true
        tween(scaleObject, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
        task.delay(0.4, function()
            scaleObject:Destroy()
        end)
    end)
end

function Window:_revealCards(tab, baseDelay)
    local container = tab.CurrentSubTab or tab
    if container._revealed then
        return
    end
    container._revealed = true
    local index = 0
    local function reveal(object)
        popIn(object, (baseDelay or 0) + index * 0.035)
        index += 1
    end
    local columns = container._columnSet
    for _, child in ipairs(orderedChildren(container.List)) do
        if columns and child == columns.Holder then
            local left, right = orderedChildren(columns.Left), orderedChildren(columns.Right)
            for row = 1, math.max(#left, #right) do
                if left[row] then
                    reveal(left[row])
                end
                if right[row] then
                    reveal(right[row])
                end
            end
        else
            reveal(child)
        end
    end
end

function Window:_playIntro(morph)
    if self._introDone or self._destroyed then
        return
    end
    self._introDone = true
    self:_refreshBackdrop(true)
    task.delay(0.4, function()
        self:_refreshToggleButton()
    end)
    -- Build the minimized bar ahead of time so the first minimize doesn't
    -- pay for it mid-click.
    task.delay(1.5, function()
        if not self._destroyed and not self.MiniBar then
            self:_buildMiniBar()
        end
    end)
    local root, shadow, scale = self.Root, self.Shadow, self.Scale
    if self.CurrentTab then
        self:_revealCards(self.CurrentTab, morph and 0.15 or 0.25)
    end
    root.Visible = true
    if morph then
        scale.Scale = self._fitScale or 1
        root.Position = UDim2.fromScale(0.5, 0.5)
        self:_fade(0, 0.3)
        tween(self.BodyStroke, { Transparency = 0 }, 0.3)
        tween(shadow, { ImageTransparency = 0.6 }, 0.3)
    else
        root.Position = UDim2.new(0.5, 0, 0.5, 24)
        tween(scale, { Scale = self._fitScale or 1 }, 0.5, Enum.EasingStyle.Back)
        tween(root, { Position = UDim2.fromScale(0.5, 0.5) }, 0.5, Enum.EasingStyle.Quint)
        self:_fade(0, 0.35)
        tween(self.BodyStroke, { Transparency = 0 }, 0.35)
    end
    if not morph then
        tween(shadow, { ImageTransparency = 0.6 }, 0.5)
    end

    for index, tab in ipairs(self.Tabs) do
        popIn(tab._button, 0.1 + index * 0.05, true)
    end
    self.Indicator.Visible = false
    task.delay(0.15 + #self.Tabs * 0.05, function()
        if self.CurrentTab then
            self:_placeIndicator(self.CurrentTab)
        end
    end)
end

function Window:_showLoader(opts)
    local duration = opts.LoadingDuration or 1.6
    local gui = self.Gui
    -- A compact card: logo, title and subtitle on top, a checklist of the
    -- loading steps under a hairline, and a thin progress line along the
    -- bottom edge. Everything but the prompt cards lives in one canvas group
    -- so it can fade as a unit.
    local steps = opts.LoadingSteps or { "Preparing interface", "Loading icons", "Almost there" }
    local WIDTH, PAD, STEP = 340, 22, 24
    local listTop = 80
    local height = listTop + #steps * STEP + 18
    local loader = create("CanvasGroup", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 10),
        Size = UDim2.fromOffset(WIDTH, height),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        ZIndex = 10,
        Parent = gui,
    })
    local loaderCorner = corner(loader, UDim.new(0, 12))
    local loaderStroke = stroke(loader, Theme.Stroke, 1)
    local loaderScale = create("UIScale", { Scale = 0.97, Parent = loader })
    local loaderShadow = create("ImageLabel", {
        Position = UDim2.fromOffset(-25, -25),
        Size = UDim2.new(1, 50, 1, 50),
        BackgroundTransparency = 1,
        Image = Assets.Shadow,
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450),
        ZIndex = 0,
        Parent = loader,
    })
    local content = create("CanvasGroup", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Parent = loader,
    })

    local logo = create("ImageLabel", {
        Position = UDim2.fromOffset(PAD, PAD),
        Size = UDim2.fromOffset(30, 30),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Accent,
        ScaleType = Enum.ScaleType.Fit,
        Parent = content,
    })
    applyIcon(logo, opts.Icon or Assets.Logo, true)
    local TEXT_X = PAD + 42
    local titleLabel = label({
        Position = UDim2.fromOffset(TEXT_X, PAD - 2),
        Size = UDim2.new(1, -(TEXT_X + 70), 0, 18),
        Text = opts.LoadingTitle or opts.Title or "RealIggyLib",
        TextSize = 15,
        FontFace = Fonts.Bold,
        Parent = content,
    })
    local statusLabel = label({
        Position = UDim2.fromOffset(TEXT_X, PAD + 17),
        Size = UDim2.new(1, -(TEXT_X + 70), 0, 15),
        Text = opts.LoadingText or opts.Subtitle or "Loading",
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = content,
    })
    local percentLabel = label({
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -PAD, 0, PAD + 6),
        Size = UDim2.fromOffset(56, 16),
        Text = "0%",
        TextSize = 13,
        FontFace = Fonts.Medium,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = content,
    })
    create("Frame", {
        Position = UDim2.fromOffset(PAD, listTop - 14),
        Size = UDim2.new(1, -PAD * 2, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        Parent = content,
    })

    -- Each step: a marker and its text. Pending is a dim dot, the running
    -- step a turning arc, and a finished one a check.
    local rows = {}
    for index, text in ipairs(steps) do
        local row = create("Frame", {
            Position = UDim2.fromOffset(PAD, listTop + (index - 1) * STEP),
            Size = UDim2.new(1, -PAD * 2, 0, STEP),
            BackgroundTransparency = 1,
            Parent = content,
        })
        local dot = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0, 7, 0.5, 0),
            Size = UDim2.fromOffset(6, 6),
            BackgroundColor3 = Theme.Surface3,
            BorderSizePixel = 0,
            Parent = row,
        })
        corner(dot, UDim.new(1, 0))
        local spinner = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0, 7, 0.5, 0),
            Size = UDim2.fromOffset(12, 12),
            BackgroundTransparency = 1,
            Visible = false,
            Parent = row,
        })
        corner(spinner, UDim.new(1, 0))
        local spinnerStroke = create("UIStroke", {
            Color = Theme.Accent,
            Thickness = 2,
            Parent = spinner,
        })
        create("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(0.5, 0),
                NumberSequenceKeypoint.new(0.501, 1),
                NumberSequenceKeypoint.new(1, 1),
            }),
            Parent = spinnerStroke,
        })
        local check = create("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0, 7, 0.5, 0),
            Size = UDim2.fromOffset(14, 14),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Accent,
            ImageTransparency = 1,
            ScaleType = Enum.ScaleType.Fit,
            Parent = row,
        })
        applyIcon(check, "check")
        local stepLabel = label({
            Position = UDim2.fromOffset(24, 0),
            Size = UDim2.new(1, -24, 1, 0),
            Text = tostring(text),
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextTransparency = 1,
            Parent = row,
        })
        rows[index] = { Dot = dot, Spinner = spinner, Check = check, Label = stepLabel, State = "pending" }
        -- The rows fade in one after another once the card is up.
        task.delay(0.15 + index * 0.06, function()
            if loader.Parent and rows[index].State == "pending" then
                tween(stepLabel, { TextTransparency = 0.45 }, 0.3)
            end
        end)
    end
    local function setStep(index, state)
        local row = rows[index]
        if not row or row.State == state then
            return
        end
        row.State = state
        row.Dot.Visible = state == "pending"
        row.Spinner.Visible = state == "active"
        tween(row.Check, { ImageTransparency = state == "done" and 0 or 1 }, 0.2)
        tween(row.Label, {
            TextTransparency = state == "pending" and 0.45 or 0,
            TextColor3 = state == "active" and Theme.Text or Theme.Muted,
        }, 0.2)
    end

    local track = create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 2),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = content,
    })
    local fill = create("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Parent = track,
    })

    tween(loader, { GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) }, 0.45, Enum.EasingStyle.Quint)
    tween(loaderScale, { Scale = 1 }, 0.45, Enum.EasingStyle.Quint)
    tween(loaderShadow, { ImageTransparency = 0.55 }, 0.4)
    tween(fill, { Size = UDim2.fromScale(0.85, 1) }, duration * 0.8, Enum.EasingStyle.Quart)
    -- The percentage follows the bar and the running step's arc turns.
    local percentStep
    percentStep = RunService.RenderStepped:Connect(function(deltaTime)
        if not loader.Parent then
            percentStep:Disconnect()
            return
        end
        percentLabel.Text = math.floor(fill.Size.X.Scale * 100 + 0.5) .. "%"
        for _, row in ipairs(rows) do
            if row.State == "active" then
                row.Spinner.Rotation = (row.Spinner.Rotation + deltaTime * 360) % 360
            end
        end
    end)

    task.spawn(loadLucide)

    for index in ipairs(steps) do
        task.delay(duration * (index - 1) / #steps, function()
            if not loader.Parent then
                return
            end
            if index > 1 then
                setStep(index - 1, "done")
            end
            setStep(index, "active")
        end)
    end
    local function completeSteps()
        for index in ipairs(rows) do
            setStep(index, "done")
        end
    end

    local function finish()
        completeSteps()
        tween(content, { GroupTransparency = 1 }, 0.18)

        local fit = self._fitScale or 1
        local target = self.Root.Size
        tween(loader, {
            Size = UDim2.fromOffset(target.X.Offset * fit, target.Y.Offset * fit),
            Position = UDim2.fromScale(0.5, 0.5),
        }, 0.5, Enum.EasingStyle.Quint)
        tween(loaderCorner, { CornerRadius = UDim.new(0, Library._radius(10)) }, 0.5, Enum.EasingStyle.Quint)
        tween(loaderScale, { Scale = 1 }, 0.5, Enum.EasingStyle.Quint)

        task.delay(0.28, function()
            self:_playIntro(true)
            tween(loader, { GroupTransparency = 1 }, 0.25)
            tween(loaderStroke, { Transparency = 1 }, 0.2)
            tween(loaderShadow, { ImageTransparency = 1 }, 0.2)
        end)
        task.delay(0.6, function()
            loader:Destroy()
        end)
    end

    -- Prompt cards (unsupported executor, custom disclaimers): the checklist
    -- gives way to one card at a time, each with Exit and Continue, before
    -- the window opens.
    local function hideBar()
        completeSteps()
        tween(content, { GroupTransparency = 1 }, 0.18)
    end

    local function showCard(info, onContinue)
        local WIDTH, PAD, MAX_BODY = 360, 24, 220
        local tone = info.Color or Theme.Accent
        -- Fixed width from the start, so the body wraps at its final width
        -- while the loader is still resizing.
        local warnCard = create("CanvasGroup", {
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.fromScale(0.5, 0),
            Size = UDim2.new(0, WIDTH, 1, 0),
            BackgroundTransparency = 1,
            GroupTransparency = 1,
            ZIndex = 5,
            Parent = loader,
        })
        local badge = create("Frame", {
            Position = UDim2.fromOffset(PAD, PAD),
            Size = UDim2.fromOffset(44, 44),
            BackgroundColor3 = tone,
            BackgroundTransparency = 0.86,
            BorderSizePixel = 0,
            Parent = warnCard,
        })
        corner(badge, UDim.new(0, 12))
        stroke(badge, tone, 1).Transparency = 0.6
        local badgeIcon = create("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(22, 22),
            BackgroundTransparency = 1,
            ImageColor3 = tone,
            ScaleType = Enum.ScaleType.Fit,
            Parent = badge,
        })
        applyIcon(badgeIcon, info.Icon or "info")
        label({
            Position = UDim2.fromOffset(PAD + 58, info.Subtitle and PAD + 3 or PAD + 12),
            Size = UDim2.new(1, -(PAD * 2 + 58), 0, 20),
            Text = info.Title,
            TextSize = 17,
            Parent = warnCard,
        })
        if info.Subtitle then
            label({
                Position = UDim2.fromOffset(PAD + 58, PAD + 25),
                Size = UDim2.new(1, -(PAD * 2 + 58), 0, 16),
                Text = tostring(info.Subtitle),
                TextSize = 13,
                TextColor3 = tone,
                Parent = warnCard,
            })
        end
        -- Long text scrolls past MAX_BODY instead of pushing the card off screen.
        local scroller = create("ScrollingFrame", {
            Position = UDim2.fromOffset(PAD, PAD + 60),
            Size = UDim2.new(1, -PAD * 2, 0, 16),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = TOUCH and 4 or 3,
            ScrollBarImageColor3 = Theme.Accent,
            ScrollBarImageTransparency = 0.4,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            CanvasSize = UDim2.new(),
            Parent = warnCard,
        })
        local body = label({
            Size = UDim2.new(1, -8, 0, 0),
            Text = tostring(info.Text),
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextWrapped = true,
            TextTruncate = Enum.TextTruncate.None,
            TextYAlignment = Enum.TextYAlignment.Top,
            Parent = scroller,
        })
        local row = create("Frame", {
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, PAD, 1, -PAD + 4),
            Size = UDim2.new(1, -PAD * 2, 0, 34),
            BackgroundTransparency = 1,
            Parent = warnCard,
        })
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 8),
            Parent = row,
        })

        -- Don't ask again: only offered when Continue is, and the executor
        -- can write the file that remembers it.
        local remember = false
        local rememberRow = nil
        if not info.Block and info.RememberText and UnsupportedSkip.Available() then
            local boxSize = TOUCH and 20 or 16
            rememberRow = create("TextButton", {
                AnchorPoint = Vector2.new(0, 1),
                Position = UDim2.new(0, PAD, 1, -PAD + 4 - 34 - 12),
                Size = UDim2.new(1, -PAD * 2, 0, TOUCH and 28 or 22),
                BackgroundTransparency = 1,
                Text = "",
                AutoButtonColor = false,
                Parent = warnCard,
            })
            local box = create("Frame", {
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.fromScale(0, 0.5),
                Size = UDim2.fromOffset(boxSize, boxSize),
                BackgroundColor3 = Theme.Surface2,
                BorderSizePixel = 0,
                Parent = rememberRow,
            })
            corner(box, UDim.new(0, 4))
            local boxStroke = stroke(box, Theme.Stroke, 1)
            local check = create("ImageLabel", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromOffset(boxSize - 4, boxSize - 4),
                BackgroundTransparency = 1,
                ImageColor3 = Theme.AccentDark,
                ImageTransparency = 1,
                ScaleType = Enum.ScaleType.Fit,
                Parent = box,
            })
            applyIcon(check, "check")
            local rememberLabel = label({
                Position = UDim2.fromOffset(boxSize + 8, 0),
                Size = UDim2.new(1, -(boxSize + 8), 1, 0),
                Text = info.RememberText,
                TextSize = 12,
                FontFace = Fonts.Regular,
                TextColor3 = Theme.Muted,
                Parent = rememberRow,
            })
            rememberRow.MouseEnter:Connect(function()
                tween(boxStroke, { Color = remember and Theme.Accent or Theme.StrokeHover }, 0.12)
                tween(rememberLabel, { TextColor3 = Theme.Text }, 0.12)
            end)
            rememberRow.MouseLeave:Connect(function()
                tween(boxStroke, { Color = remember and Theme.Accent or Theme.Stroke }, 0.2)
                tween(rememberLabel, { TextColor3 = remember and Theme.Text or Theme.Muted }, 0.2)
            end)
            rememberRow.MouseButton1Click:Connect(function()
                remember = not remember
                tween(box, { BackgroundColor3 = remember and Theme.Accent or Theme.Surface2 }, 0.15)
                tween(boxStroke, { Color = remember and Theme.Accent or Theme.Stroke }, 0.15)
                tween(check, { ImageTransparency = remember and 0 or 1 }, 0.15)
                tween(rememberLabel, { TextColor3 = remember and Theme.Text or Theme.Muted }, 0.15)
            end)
        end

        local chosen = false
        local function button(text, primary, order, callback)
            local frame = create("TextButton", {
                Size = UDim2.fromOffset(0, 34),
                AutomaticSize = Enum.AutomaticSize.X,
                BackgroundColor3 = primary and Theme.Accent or Theme.Surface2,
                BackgroundTransparency = primary and 0.12 or 0,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = order,
                Parent = row,
            })
            corner(frame, UDim.new(0, 7))
            local frameStroke = stroke(frame, primary and Theme.Accent or Theme.Stroke, 1)
            frameStroke.Transparency = primary and 0.4 or 0
            padding(frame, 14, 14)
            label({
                Size = UDim2.new(0, 0, 1, 0),
                AutomaticSize = Enum.AutomaticSize.X,
                Text = text,
                TextSize = 13,
                TextColor3 = primary and Theme.AccentDark or Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Center,
                Parent = frame,
            })
            frame.MouseEnter:Connect(function()
                if primary then
                    tween(frame, { BackgroundTransparency = 0 }, 0.12)
                    tween(frameStroke, { Transparency = 0 }, 0.12)
                else
                    tween(frameStroke, { Color = Theme.StrokeHover }, 0.12)
                end
            end)
            frame.MouseLeave:Connect(function()
                if primary then
                    tween(frame, { BackgroundTransparency = 0.12 }, 0.2)
                    tween(frameStroke, { Transparency = 0.4 }, 0.2)
                else
                    tween(frameStroke, { Color = Theme.Stroke }, 0.2)
                end
            end)
            frame.MouseButton1Click:Connect(function()
                if chosen then
                    return
                end
                chosen = true
                callback()
            end)
        end
        if info.ExitText ~= false then
            button(info.ExitText or "Exit", info.Block, 1, function()
                if info.Callback then
                    task.spawn(info.Callback, false)
                end
                tween(loader, { GroupTransparency = 1, Position = UDim2.new(0.5, 0, 0.5, 12) }, 0.25, Enum.EasingStyle.Quint)
                tween(loaderShadow, { ImageTransparency = 1 }, 0.2)
                task.delay(0.25, function()
                    self:Destroy()
                end)
            end)
        end
        if not info.Block then
            button(info.ContinueText or "Continue", true, 2, function()
                if remember and info.Remember then
                    info.Remember()
                end
                if info.Callback then
                    task.spawn(info.Callback, true)
                end
                tween(warnCard, { GroupTransparency = 1 }, 0.15)
                task.delay(0.15, function()
                    warnCard:Destroy()
                    onContinue()
                end)
            end)
        end

        -- The card grows to fit the message, then it fades in. The wrapped
        -- height can land a few frames late (font loading, the scroller's
        -- layout), so the card refits whenever it changes.
        local laidOut = false
        -- TextBounds of wrapped text stops at the label's current height, so
        -- the card would fit to its own clipped text; the full wrapped height
        -- is measured at the body's width instead.
        local function measure()
            local ok, size = pcall(function()
                local params = Instance.new("GetTextBoundsParams")
                params.Text = body.Text
                params.Font = body.FontFace
                params.Size = body.TextSize
                params.Width = WIDTH - PAD * 2 - 8
                return game:GetService("TextService"):GetTextBoundsAsync(params)
            end)
            return ok and size and math.ceil(size.Y) + 2 or body.TextBounds.Y
        end
        local function fit(duration)
            local textHeight = math.max(measure(), 16)
            local bodyHeight = math.min(textHeight, MAX_BODY)
            body.Size = UDim2.new(1, -8, 0, textHeight)
            scroller.Size = UDim2.new(1, -PAD * 2, 0, bodyHeight)
            scroller.CanvasSize = UDim2.fromOffset(0, textHeight)
            local height = PAD + 60 + bodyHeight + 18 + 34 + PAD - 4
            if rememberRow then
                height += rememberRow.Size.Y.Offset + 10
            end
            tween(loader, { Size = UDim2.fromOffset(WIDTH, height) }, duration, Enum.EasingStyle.Quint)
        end
        body:GetPropertyChangedSignal("TextBounds"):Connect(function()
            if laidOut and loader.Parent and warnCard.Parent then
                fit(0.2)
            end
        end)
        task.delay(0.15, function()
            if not loader.Parent then
                return
            end
            laidOut = true
            fit(0.35)
            task.delay(0.12, function()
                tween(warnCard, { GroupTransparency = 0 }, 0.3)
                badge.Size = UDim2.fromOffset(34, 34)
                badge.Position = UDim2.fromOffset(PAD + 5, PAD + 5)
                tween(badge, { Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(PAD, PAD) }, 0.45, Enum.EasingStyle.Back)
            end)
        end)
    end

    local function runPrompts(queue, index)
        if not loader.Parent then
            return
        end
        local info = queue[index]
        if not info then
            finish()
            return
        end
        showCard(info, function()
            runPrompts(queue, index + 1)
        end)
    end

    task.delay(duration, function()
        tween(fill, { Size = UDim2.fromScale(1, 1) }, 0.25, Enum.EasingStyle.Quint)
        task.delay(0.25, function()
            if not loader.Parent then
                return
            end
            if opts._prompts then
                hideBar()
                runPrompts(opts._prompts, 1)
            else
                finish()
            end
        end)
    end)
end

function Window:_fitToScreen(instant)
    local viewport = self.Gui.AbsoluteSize
    if viewport.X == 0 or viewport.Y == 0 then
        return
    end
    local size = self.Root.Size
    -- The player's UI scale, times the adaptive factor for this screen, shrunk
    -- further when the window wouldn't fit.
    local wanted = (self._uiScale or 1) * (self._adaptive ~= false and Library._adaptiveFactor(viewport) or 1)
    local scale = math.min(wanted, (viewport.X - 24) / math.max(size.X.Offset, 1), (viewport.Y - 24) / math.max(size.Y.Offset, 1))
    self._fitScale = math.max(scale, 0.45)
    if self._introDone and self.Open then
        if instant then
            self.Scale.Scale = self._fitScale
        else
            tween(self.Scale, { Scale = self._fitScale }, 0.2)
        end
    end
end

-- Adaptive size: the window is drawn for a 1080p screen and grows on larger
-- ones (up to 1.75x on 4K) or shrinks a little on small laptops, so it covers
-- about the same share of any screen. 1080p-class screens, windowed or with
-- the topbar inset, stay at exactly 1. Touch screens only use the fit.
function Library._adaptiveFactor(viewport)
    if TOUCH then
        return 1
    end
    local factor = math.min(viewport.X / 1920, viewport.Y / 1020)
    if factor > 0.9 and factor < 1.15 then
        return 1
    end
    return math.clamp(math.floor(factor * 20 + 0.5) / 20, 0.85, 1.75)
end

function Window:SetAdaptiveSize(enabled)
    self._adaptive = enabled ~= false
    self:_fitToScreen()
    task.delay(0.22, function()
        if not self._destroyed then
            self:_clampToScreen()
        end
    end)
end

function Window:GetAdaptiveSize()
    return self._adaptive ~= false
end

-- UI scale: 0.6 to 1.5 on top of the automatic fit to small screens.
function Window:SetUIScale(value)
    value = math.clamp(tonumber(value) or 1, 0.6, 1.5)
    self.UIScale = value
    self._uiScale = value
    self:_fitToScreen()
    task.delay(0.22, function()
        if not self._destroyed then
            self:_clampToScreen()
        end
    end)
end

function Window:GetUIScale()
    return self._uiScale or 1
end

-- Density: the spacing between cards, groupboxes and rows. Shared by every
-- window, like the theme. Anything built with Library._space follows it.
Library.DensityModes = { Compact = 0.55, Default = 1, Comfortable = 1.45 }
Library.Density = "Default"

-- Small gaps (a groupbox's 2px rows) still move visibly between modes.
function Library._spaced(base, factor)
    if base <= 0 then
        return 0
    end
    return math.max(math.floor(base * factor + (factor - 1) * 4 + 0.5), 0)
end

function Library._space(object, base)
    local factor = Library.DensityModes[Library.Density] or 1
    if object:IsA("UIListLayout") or object:IsA("UIGridLayout") then
        object:SetAttribute("Space", base)
        object.Padding = UDim.new(0, Library._spaced(base, factor))
    elseif object:IsA("UIPadding") then
        -- base is { left, right, top, bottom }
        object:SetAttribute("SpaceL", base[1])
        object:SetAttribute("SpaceR", base[2])
        object:SetAttribute("SpaceT", base[3])
        object:SetAttribute("SpaceB", base[4])
        object.PaddingLeft = UDim.new(0, math.floor(base[1] * math.sqrt(factor) + 0.5))
        object.PaddingRight = UDim.new(0, math.floor(base[2] * math.sqrt(factor) + 0.5))
        object.PaddingTop = UDim.new(0, Library._spaced(base[3], factor))
        object.PaddingBottom = UDim.new(0, Library._spaced(base[4], factor))
    end
    return object
end

function Library:SetDensity(mode)
    if type(mode) == "string" then
        for name in pairs(Library.DensityModes) do
            if name:lower() == mode:lower() then
                mode = name
                break
            end
        end
    end
    if not Library.DensityModes[mode] then
        mode = "Default"
    end
    Library.Density = mode
    for _, window in ipairs(Library.Windows) do
        if window.Gui and window.Gui.Parent then
            for _, object in ipairs(window.Gui:GetDescendants()) do
                local base = object:GetAttribute("Space")
                if base then
                    Library._space(object, base)
                elseif object:GetAttribute("SpaceL") then
                    Library._space(object, {
                        object:GetAttribute("SpaceL"), object:GetAttribute("SpaceR"),
                        object:GetAttribute("SpaceT"), object:GetAttribute("SpaceB"),
                    })
                end
            end
        end
    end
    return mode
end

function Window:SetDensity(mode)
    return Library:SetDensity(mode)
end

function Window:GetDensity()
    return Library.Density
end

function Window:SetAccentGradient(enabled)
    Library:SetAccentGradient(enabled)
end

function Window:GetAccentGradient()
    return Library.AccentGradient
end

function Window:SetAccentAngle(angle)
    Library:SetAccentAngle(angle)
end

function Window:GetAccentAngle()
    return Library.AccentAngle
end

function Window:SetShimmer(enabled)
    Library:SetShimmer(enabled)
end

function Window:GetShimmer()
    return Library.Shimmer
end


-- Nearest centre that keeps the whole window inside the viewport.
function Window:_clampedCentre(centre)
    local viewport = self.Gui.AbsoluteSize
    local half = self.Root.AbsoluteSize / 2
    return Vector2.new(
        math.clamp(centre.X, math.min(half.X, viewport.X / 2), math.max(viewport.X - half.X, viewport.X / 2)),
        math.clamp(centre.Y, math.min(half.Y, viewport.Y / 2), math.max(viewport.Y - half.Y, viewport.Y / 2))
    )
end

function Window:_clampToScreen()
    if not self.KeepOnScreen or self._resizeActive then
        return
    end
    local root = self.Root
    local centre = root.AbsolutePosition + root.AbsoluteSize / 2 - self.Gui.AbsolutePosition
    local clamped = self:_clampedCentre(centre)
    if (clamped - centre).Magnitude > 0.5 then
        self._clampTween = tween(root, { Position = UDim2.fromOffset(clamped.X, clamped.Y) }, 0.25, Enum.EasingStyle.Quint)
    end
end

function Window:_createOpenButton(opts)
    local gui = self.Gui
    local pill = create("TextButton", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 14),
        Size = UDim2.fromOffset(0, 40),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 30,
        Parent = gui,
    })
    corner(pill, UDim.new(1, 0))
    stroke(pill, Theme.Stroke)
    padding(pill, 12, 16)
    local icon = create("ImageLabel", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(20, 20),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Accent,
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = 31,
        Parent = pill,
    })
    applyIcon(icon, opts.Icon or Assets.Logo, true)
    label({
        Position = UDim2.fromOffset(28, 0),
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = opts.Title or "RealIggyLib",
        TextSize = 13,
        TextTruncate = Enum.TextTruncate.None,
        ZIndex = 31,
        Parent = pill,
    })
    self.OpenButton = pill

    local dragging, moved = false, false
    local grab = Vector2.zero
    pill.InputBegan:Connect(function(input)
        if isPress(input) then
            dragging = true
            moved = false
            grab = pointerPosition() - pill.AbsolutePosition
        end
    end)
    table.insert(self._connections, UserInputService.InputChanged:Connect(function(input)
        if not dragging then
            return
        end
        if isMove(input) then
            local point = pointerPosition() - grab - gui.AbsolutePosition
            if (point - (pill.AbsolutePosition - gui.AbsolutePosition)).Magnitude > 3 then
                moved = true
            end
            pill.AnchorPoint = Vector2.new(0, 0)
            pill.Position = UDim2.fromOffset(
                math.clamp(point.X, 0, math.max(gui.AbsoluteSize.X - pill.AbsoluteSize.X, 0)),
                math.clamp(point.Y, 0, math.max(gui.AbsoluteSize.Y - pill.AbsoluteSize.Y, 0))
            )
        end
    end))
    table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
        if dragging and isPress(input) then
            dragging = false
            if not moved then
                self:Toggle()
            end
        end
    end))
end

-- Square floating button that minimizes and restores the window. Shown on
-- touch devices only, or everywhere with Platform = "Both".
function Window:_toggleButtonAllowed()
    return self._toggleEnabled and (TOUCH or self._togglePlatform == "Both")
end

function Window:_refreshToggleButton()
    local button = self.ToggleButton
    if not button then
        return
    end
    local shown = self._introDone and not self._destroyed and self:_toggleButtonAllowed()
    if shown and not button.Visible then
        button.Visible = true
        button.Size = UDim2.fromOffset(0, 0)
        tween(button, { Size = UDim2.fromOffset(self._toggleSize, self._toggleSize) }, 0.45, Enum.EasingStyle.Quint)
    elseif not shown then
        button.Visible = false
    end
    -- Folded (window minimized or hidden): the outline takes the accent.
    local folded = self.Minimized or not self.Open
    tween(self._toggleStroke, { Color = folded and Theme.Accent or Theme.Stroke, Transparency = folded and 0.3 or 0 }, 0.35)
    local icon = self._toggleIcon
    tween(icon, { Rotation = folded and 180 or 0 }, 0.5, Enum.EasingStyle.Quint)
    if not icon:GetAttribute("CustomIcon") then
        tween(icon, { ImageColor3 = folded and Theme.Text or Theme.Accent }, 0.35)
    end
end

function Window:_createToggleButton(opts)
    local gui = self.Gui
    local size = tonumber(opts.Size) or (TOUCH and 56 or 50)
    local iconSize = math.floor(size * 0.58)
    self._toggleEnabled = opts.Enabled ~= false
    self._togglePlatform = opts.Platform == "Both" and "Both" or "Mobile"
    self._toggleSize = size
    local button = create("TextButton", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = opts.Position or UDim2.new(0, 18 + size / 2, 0.5, 0),
        Size = UDim2.fromOffset(size, size),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ClipsDescendants = true,
        Visible = false,
        ZIndex = 30,
        Parent = gui,
    })
    corner(button, UDim.new(0, 12))
    local buttonStroke = stroke(button, Theme.Stroke)
    local icon = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(iconSize, iconSize),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Accent,
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = 31,
        Parent = button,
    })
    local buttonScale = create("UIScale", { Parent = button })
    self.ToggleButton = button
    self._toggleStroke = buttonStroke
    self._toggleIcon = icon
    self:SetToggleButtonIcon(opts.Icon or "layout-grid")

    local dragging, moved = false, false
    local grab = Vector2.zero
    button.InputBegan:Connect(function(input)
        if isPress(input) then
            dragging = true
            moved = false
            grab = pointerPosition() - button.AbsolutePosition
            tween(buttonScale, { Scale = 0.94 }, 0.18, Enum.EasingStyle.Quint)
        end
    end)
    table.insert(self._connections, UserInputService.InputChanged:Connect(function(input)
        if not dragging or not isMove(input) then
            return
        end
        local point = pointerPosition() - grab - gui.AbsolutePosition
        if (point - (button.AbsolutePosition - gui.AbsolutePosition)).Magnitude > 3 then
            moved = true
        end
        if moved then
            button.AnchorPoint = Vector2.zero
            button.Position = UDim2.fromOffset(
                math.clamp(point.X, 0, math.max(gui.AbsoluteSize.X - button.AbsoluteSize.X, 0)),
                math.clamp(point.Y, 0, math.max(gui.AbsoluteSize.Y - button.AbsoluteSize.Y, 0))
            )
        end
    end))
    table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
        if not dragging or not isPress(input) then
            return
        end
        dragging = false
        tween(buttonScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Quint)
        if moved then
            return
        end
        ripple(button)
        if not self.Open then
            self:Toggle(true)
        elseif self.Minimized then
            self:Restore()
        else
            self:Minimize()
        end
    end))
end

function Window:SetToggleButton(enabled)
    self._toggleEnabled = enabled ~= false
    self:_refreshToggleButton()
end

function Window:SetToggleButtonPlatform(platform)
    self._togglePlatform = platform == "Both" and "Both" or "Mobile"
    self:_refreshToggleButton()
end

function Window:SetToggleButtonIcon(icon)
    local image = self._toggleIcon
    if not image then
        return
    end
    image.Image = ""
    applyIcon(image, icon)
    if image.Image == "" then
        applyIcon(image, Assets.Logo)
    end
    if not image:GetAttribute("CustomIcon") then
        tween(image, { ImageColor3 = (self.Minimized or not self.Open) and Theme.Text or Theme.Accent }, 0)
    end
end

function Window:_enableResize(minSize)
    local maxSize = self.MaxSize or Vector2.new(math.huge, math.huge)
    self._minSize = minSize
    local root = self.Root
    local grip = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(1, 4, 1, 4),
        Size = UDim2.fromOffset(32, 32),
        BackgroundTransparency = 1,
        Active = true,
        ZIndex = 20,
        Parent = root,
    })
    self._grip = grip
    -- An arc that traces the window's own rounded corner: a rounded square
    -- laid over the corner whose outline fades out away from it, so only the
    -- curve and a short run of each edge show. Faint at rest, accent in use.
    local gripArc = create("Frame", {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.fromOffset(12, 12),
        Size = UDim2.fromOffset(26, 26),
        BackgroundTransparency = 1,
        ZIndex = 20,
        Parent = grip,
    })
    corner(gripArc, UDim.new(0, 10))
    local gripStroke = create("UIStroke", {
        Color = Theme.Muted,
        Thickness = 2,
        Transparency = 0.55,
        Parent = gripArc,
    })
    create("UIGradient", {
        Rotation = 45,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.55, 1),
            NumberSequenceKeypoint.new(0.85, 0),
            NumberSequenceKeypoint.new(1, 0),
        }),
        Parent = gripStroke,
    })
    local function lightGrip(on)
        tween(gripStroke, {
            Color = on and Theme.Accent or Theme.Muted,
            Transparency = on and 0 or 0.55,
        }, on and 0.15 or 0.3, Enum.EasingStyle.Quint)
    end

    -- The size follows the pointer through a critically damped spring, so it
    -- glides after the cursor and eases to rest when released instead of
    -- snapping. While resizing, the window is anchored at its top-left corner
    -- so only the right and bottom edges move and nothing jitters on half pixels.
    local STIFFNESS = 20
    local resizing = false
    local startSize = Vector2.zero
    local startPointer = Vector2.zero
    local current = Vector2.zero
    local velocity = Vector2.zero
    local target = Vector2.zero
    local applied = Vector2.zero

    local function readSize()
        return Vector2.new(root.Size.X.Offset, root.Size.Y.Offset)
    end

    local function pin()
        if root.AnchorPoint == Vector2.zero then
            return
        end
        -- A clamp tween still writing centre coordinates would fight the new anchor.
        if self._clampTween then
            self._clampTween:Cancel()
            self._clampTween = nil
        end
        local topLeft = root.AbsolutePosition - self.Gui.AbsolutePosition
        root.AnchorPoint = Vector2.zero
        root.Position = UDim2.fromOffset(topLeft.X, topLeft.Y)
    end

    local function unpin()
        local topLeft = root.AbsolutePosition - self.Gui.AbsolutePosition
        local half = root.AbsoluteSize / 2
        root.AnchorPoint = Vector2.new(0.5, 0.5)
        root.Position = UDim2.fromOffset(topLeft.X + half.X, topLeft.Y + half.Y)
    end

    local function clampSize(size)
        return Vector2.new(
            math.floor(math.clamp(size.X, minSize.X, maxSize.X) + 0.5),
            math.floor(math.clamp(size.Y, minSize.Y, maxSize.Y) + 0.5)
        )
    end

    grip.InputBegan:Connect(function(input)
        if not isPress(input) or not self.Open then
            return
        end
        if not self._resizeActive then
            pin()
            current = readSize()
            velocity = Vector2.zero
            applied = current
        end
        self._resizeActive = true
        resizing = true
        startSize = current
        startPointer = pointerPosition()
        target = clampSize(startSize)
        lightGrip(true)
    end)
    grip.MouseEnter:Connect(function()
        if not resizing then
            lightGrip(true)
        end
    end)
    grip.MouseLeave:Connect(function()
        if not resizing then
            lightGrip(false)
        end
    end)
    table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
        if resizing and isPress(input) then
            resizing = false
            lightGrip(false)
        end
    end))

    table.insert(self._frameSteps, function(deltaTime)
        if not self._resizeActive then
            return
        end
        if resizing then
            local delta = (pointerPosition() - startPointer) / self.Scale.Scale
            target = clampSize(startSize + delta)
        end
        local dt = math.min(deltaTime, 1 / 30)
        local decay = math.exp(-STIFFNESS * dt)
        local offset = current - target
        local drift = (velocity + offset * STIFFNESS) * dt
        velocity = (velocity - drift * STIFFNESS) * decay
        current = target + (offset + drift) * decay

        local rounded = Vector2.new(math.floor(current.X + 0.5), math.floor(current.Y + 0.5))
        if rounded ~= applied then
            applied = rounded
            root.Size = UDim2.fromOffset(rounded.X, rounded.Y)
        end

        if not resizing and (current - target).Magnitude < 0.3 and velocity.Magnitude < 3 then
            current = target
            velocity = Vector2.zero
            applied = target
            root.Size = UDim2.fromOffset(target.X, target.Y)
            unpin()
            self._resizeActive = false
            self:_fitToScreen()
            self:_clampToScreen()
        end
    end)
end

-- The window's own size in pixels, before the UI scale and screen fit.
function Window:GetSize()
    return Vector2.new(self.Root.Size.X.Offset, self.Root.Size.Y.Offset)
end

-- Resizes to an exact size, kept within MinSize and MaxSize. Ignored while the
-- player is dragging the grip.
function Window:SetSize(size, instant)
    if typeof(size) == "UDim2" then
        size = Vector2.new(size.X.Offset, size.Y.Offset)
    end
    if typeof(size) ~= "Vector2" or self._resizeActive then
        return
    end
    local minSize = self._minSize or Vector2.zero
    local maxSize = self.MaxSize or Vector2.new(math.huge, math.huge)
    size = Vector2.new(
        math.floor(math.clamp(size.X, minSize.X, maxSize.X) + 0.5),
        math.floor(math.clamp(size.Y, minSize.Y, maxSize.Y) + 0.5)
    )
    if size == self:GetSize() then
        return
    end
    local duration = (instant or not self.Root.Visible) and 0 or 0.3
    tween(self.Root, { Size = UDim2.fromOffset(size.X, size.Y) }, duration, Enum.EasingStyle.Quint)
    task.delay(duration + 0.02, function()
        if not self._destroyed then
            self:_fitToScreen()
            self:_clampToScreen()
        end
    end)
end

-- Configs are plain JSON, one file per config, in the same shape as a share code:
--   {"Folder":"MyHub","Name":"farm","Version":1,"Config":"{\"AutoFarm\":{\"Value\":true,\"Type\":\"Toggle\"}}"}
-- Config holds the flags as their own JSON string, each one {"Value":...,"Type":...}.
-- Colours are {"Hex":"ff5a5a"}, keybinds are key names, an empty dropdown has no Value.

local CONFIG_VERSION = 1
local LEGACY_SHARE_PREFIX = "realiggy:"

local function configPath(self, name)
    return self.ConfigFolder .. "/" .. name .. ".json"
end

local function fileApiAvailable()
    return type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
end

-- Makes every missing folder along the path, so FolderName can be "Hub/Game".
local function ensureFolder(folder)
    if type(isfolder) ~= "function" or type(makefolder) ~= "function" then
        return
    end
    local path = ""
    for segment in tostring(folder):gmatch("[^/\\]+") do
        path = path == "" and segment or path .. "/" .. segment
        if not isfolder(path) then
            makefolder(path)
        end
    end
end

local function colorToHex(color)
    return string.format("%02x%02x%02x",
        math.floor(color.R * 255 + 0.5),
        math.floor(color.G * 255 + 0.5),
        math.floor(color.B * 255 + 0.5))
end

local function colorFromValue(value)
    if type(value) == "table" then
        if type(value.Hex) == "string" then
            value = value.Hex
        elseif type(value[1]) == "number" then
            -- Older configs stored { r, g, b } in 0-1.
            return Color3.new(value[1], value[2] or 0, value[3] or 0)
        end
    end
    if type(value) == "string" then
        local r, g, b = value:match("^%s*#?(%x%x)(%x%x)(%x%x)%s*$")
        if r then
            return Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16))
        end
    end
    return nil
end

local function serializeFlag(element)
    local kind = element._type
    local value = element:Get()
    if type(element._saveValue) == "function" then
        value = element:_saveValue()
    end
    if kind == "Keybind" then
        return { Type = kind, Value = value and value.Name or nil }
    elseif kind == "ColorPicker" then
        return { Type = kind, Value = typeof(value) == "Color3" and { Hex = colorToHex(value) } or nil }
    end
    return { Type = kind, Value = value }
end

local function deserializeFlag(element, entry, silent)
    local kind = element._type
    local value = entry.Value
    if kind == "Keybind" then
        element:Set(type(value) == "string" and Enum.KeyCode[value] or nil, silent)
    elseif kind == "ColorPicker" then
        local color = colorFromValue(value)
        if color then
            element:Set(color, silent)
        end
    elseif kind == "Dropdown" then
        -- A dropdown saved with nothing picked has no Value at all.
        element:Set(value, silent)
    elseif kind == "Toggle" then
        if type(value) == "boolean" then
            element:Set(value, silent)
        end
    elseif kind == "Slider" or kind == "Stepper" or kind == "Progress" then
        local number = tonumber(value)
        if number then
            element:Set(number, silent)
        end
    elseif value ~= nil then
        element:Set(value, silent)
    end
end

local function entryMatches(element, entry)
    return type(entry) == "table" and (entry.Type == nil or entry.Type == element._type)
end

-- Flags a config holds but no element has claimed yet are kept here. They are
-- applied when an element with that flag is created and written back on save,
-- so a config survives elements that only exist some of the time.
local function collectFlags(self)
    local data = {}
    if self and self._pendingFlags then
        for flag, pending in pairs(self._pendingFlags) do
            data[flag] = pending.Entry
        end
    end
    local ignore = self and self._ignoreFlags or {}
    for flag in pairs(ignore) do
        data[flag] = nil
    end
    for flag, element in pairs(Library.Flags) do
        if not ignore[flag] and element._type and type(element.Get) == "function" then
            local ok, entry = pcall(serializeFlag, element)
            if ok then
                data[flag] = entry
            end
        end
    end
    return data
end

-- Values first, switches last: a toggle's callback then starts with the
-- sliders and dropdowns it reads already in place. Override per window with
-- Window:SetLoadingOrder.
Library.LoadingOrder = { "Dropdown", "Slider", "Stepper", "Input", "ColorPicker", "Keybind", "Toggle" }

-- Flags a config never saves or loads, like Obsidian's SaveManager:SetIgnoreIndexes.
function Window:SetIgnoreFlags(flags)
    self._ignoreFlags = self._ignoreFlags or {}
    for _, flag in ipairs(flags or {}) do
        self._ignoreFlags[flag] = true
    end
end

function Window:SetLoadingOrder(order)
    self._loadingOrder = type(order) == "table" and order or nil
end

function Window:_applyFlags(data, silent)
    silent = silent == true
    self._pendingFlags = {}
    local ignore = self._ignoreFlags or {}
    local order = self._loadingOrder or Library.LoadingOrder
    local queue = {}
    for flag, entry in pairs(data) do
        if not ignore[flag] then
            local element = Library.Flags[flag]
            if element and type(element.Set) == "function" then
                if entryMatches(element, entry) then
                    table.insert(queue, { Element = element, Entry = entry, Rank = table.find(order, element._type) or 0 })
                end
            elseif type(entry) == "table" then
                self._pendingFlags[flag] = { Entry = entry, Silent = silent }
            end
        end
    end
    table.sort(queue, function(a, b)
        return a.Rank < b.Rank
    end)
    -- Like Obsidian: each flag is deferred onto its own thread, so a callback
    -- that loops while its toggle is on can't stall the others or the script
    -- that asked for the load.
    for _, item in ipairs(queue) do
        task.defer(function()
            if not item.Element._destroyed and not self._destroyed then
                pcall(deserializeFlag, item.Element, item.Entry, silent)
            end
        end)
    end
end

-- Every flagged element reports here: its starting value becomes its default,
-- and a value waiting from an earlier load is applied once the constructor returns.
function Window:_flagCreated(flag, element)
    local ok, entry = pcall(serializeFlag, element)
    if ok then
        element._defaultEntry = entry
    end
    local pending = self._pendingFlags and self._pendingFlags[flag]
    if not pending then
        return
    end
    task.defer(function()
        if self._pendingFlags[flag] ~= pending or Library.Flags[flag] ~= element or element._destroyed then
            return
        end
        self._pendingFlags[flag] = nil
        if entryMatches(element, pending.Entry) then
            pcall(deserializeFlag, element, pending.Entry, pending.Silent)
        end
    end)
end

-- Anything listening for config changes (the config manager's status line).
function Window:_configChanged()
    for _, handler in ipairs(self._configListeners) do
        safeCall(handler)
    end
end

function Window:OnConfigChanged(handler)
    table.insert(self._configListeners, handler)
    return function()
        local index = table.find(self._configListeners, handler)
        if index then
            table.remove(self._configListeners, index)
        end
    end
end

local function validConfigName(name)
    return type(name) == "string" and name ~= "" and not name:find('[\\/:%*%?"<>|]')
end

local function encodeConfig(self, name, flags)
    return HttpService:JSONEncode({
        Folder = self.ConfigFolder,
        Name = name,
        Version = CONFIG_VERSION,
        Config = HttpService:JSONEncode(flags),
    })
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for index = 1, #B64 do
    B64_INDEX[B64:byte(index)] = index - 1
end

-- Only for reading the old "airflow:<base64>" share codes.
local function base64Decode(text)
    if #text % 4 ~= 0 then
        return nil
    end
    local out = {}
    for index = 1, #text, 4 do
        local n, pad = 0, 0
        for offset = 0, 3 do
            local byte = text:byte(index + offset)
            local value = B64_INDEX[byte]
            if byte == 61 and index + 3 >= #text then
                pad += 1
                value = 0
            elseif value == nil or pad > 0 then
                return nil
            end
            n = n * 64 + value
        end
        if pad > 2 then
            return nil
        end
        local chunk = string.char(bit32.extract(n, 16, 8), bit32.extract(n, 8, 8), bit32.extract(n, 0, 8))
        table.insert(out, chunk:sub(1, 3 - pad))
    end
    return table.concat(out)
end

-- Reads a config file or a pasted code: the JSON above (Config as a string or
-- a table), a bare flag table, or an old "realiggy:" code. Returns flags, info.
local function decodeConfig(text)
    text = tostring(text or ""):match("^%s*(.-)%s*$")
    if text:sub(1, #LEGACY_SHARE_PREFIX) == LEGACY_SHARE_PREFIX then
        text = base64Decode((text:sub(#LEGACY_SHARE_PREFIX + 1):gsub("%s", "")))
        if not text then
            return nil, "invalid config code"
        end
    end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(text)
    end)
    if not ok or type(data) ~= "table" then
        return nil, "invalid config code"
    end
    local info = {}
    -- A bare flag table could have a flag named Config, but its entry carries a Type.
    if type(data.Config) == "string" or (type(data.Config) == "table" and data.Config.Type == nil) then
        info.Folder = type(data.Folder) == "string" and data.Folder or nil
        info.Name = type(data.Name) == "string" and data.Name or nil
        info.Version = tonumber(data.Version)
        local flags = data.Config
        if type(flags) == "string" then
            ok, flags = pcall(function()
                return HttpService:JSONDecode(data.Config)
            end)
            if not ok then
                return nil, "invalid config code"
            end
        end
        if type(flags) ~= "table" then
            return nil, "invalid config code"
        end
        data = flags
    end
    for flag, entry in pairs(data) do
        if type(flag) ~= "string" or type(entry) ~= "table" then
            return nil, "invalid config code"
        end
    end
    return data, info
end

local function writeConfig(self, name, data)
    if not validConfigName(name) then
        return false, "invalid config name"
    end
    if not fileApiAvailable() then
        return false, "file API unavailable"
    end
    local encoded, text = pcall(encodeConfig, self, name, data)
    if not encoded then
        return false, "could not encode config"
    end
    ensureFolder(self.ConfigFolder)
    return pcall(writefile, configPath(self, name), text)
end

local function readConfig(self, name)
    if not fileApiAvailable() then
        return nil, "file API unavailable"
    end
    if not validConfigName(name) then
        return nil, "invalid config name"
    end
    local path = configPath(self, name)
    if not isfile(path) then
        return nil, "no config named " .. tostring(name)
    end
    local ok, text = pcall(readfile, path)
    if not ok or type(text) ~= "string" then
        return nil, "could not read " .. name
    end
    local data, info = decodeConfig(text)
    if not data then
        return nil, "config is not valid JSON"
    end
    return data, info
end

function Window:ConfigExists(name)
    return validConfigName(name) and fileApiAvailable() and isfile(configPath(self, name)) or false
end

function Window:SaveConfig(name)
    name = name or self.ConfigName
    if not name then
        return false, "no config name"
    end
    local ok, err = writeConfig(self, name, collectFlags(self))
    if ok then
        self.ConfigName = name
    end
    return ok, err
end

function Window:LoadConfig(name, silent)
    name = name or self.ConfigName
    if not name then
        return false, "no config name"
    end
    local data, err = readConfig(self, name)
    if not data then
        return false, err
    end
    self:_applyFlags(data, silent)
    self.ConfigName = name
    self.LoadedConfig = name
    self:_configChanged()
    return true
end

function Window:DeleteConfig(name)
    if not fileApiAvailable() or type(delfile) ~= "function" then
        return false, "file API unavailable"
    end
    if not validConfigName(name) then
        return false, "invalid config name"
    end
    local path = configPath(self, name)
    if not isfile(path) then
        return false, "no config named " .. name
    end
    local ok, err = pcall(delfile, path)
    if not ok then
        return false, err
    end
    if self.LoadedConfig == name then
        self.LoadedConfig = nil
    end
    self:_configChanged()
    return true
end

-- Moves the file and anything pointing at it: the loaded name and both autoloads.
function Window:RenameConfig(name, newName)
    if not validConfigName(newName) then
        return false, "invalid config name"
    end
    if name == newName then
        return true
    end
    if self:ConfigExists(newName) then
        return false, newName .. " already exists"
    end
    local data, err = readConfig(self, name)
    if not data then
        return false, err
    end
    local ok
    ok, err = writeConfig(self, newName, data)
    if not ok then
        return false, err
    end
    if type(delfile) == "function" then
        pcall(delfile, configPath(self, name))
    end
    if self.LoadedConfig == name then
        self.LoadedConfig = newName
    end
    if self.ConfigName == name then
        self.ConfigName = newName
    end
    for _, scope in ipairs({ "Global", "Account" }) do
        if self:GetAutoload(scope) == name then
            self:SetAutoload(newName, scope)
        end
    end
    self:_configChanged()
    return true
end

function Window:ListConfigs()
    local names = {}
    if type(listfiles) ~= "function" or type(isfolder) ~= "function" or not isfolder(self.ConfigFolder) then
        return names
    end
    local ok, paths = pcall(listfiles, self.ConfigFolder)
    if not ok or type(paths) ~= "table" then
        return names
    end
    for _, path in ipairs(paths) do
        local name = path:match("([^/\\]+)%.json$")
        if name then
            table.insert(names, name)
        end
    end
    table.sort(names, function(a, b)
        return a:lower() < b:lower()
    end)
    return names
end

-- Puts every flagged element back to the value it was created with.
function Window:ResetConfig(silent)
    self._pendingFlags = {}
    for _, element in pairs(Library.Flags) do
        if element._defaultEntry and type(element.Set) == "function" then
            pcall(deserializeFlag, element, element._defaultEntry, silent == true)
        end
    end
    self:_configChanged()
    return true
end

-- Empties a folder and removes it, one file at a time when the executor has
-- no delfolder or it refuses a folder that still has files in it.
local function wipeFolder(path)
    if type(isfolder) ~= "function" or not isfolder(path) then
        return true
    end
    if type(delfolder) == "function" and pcall(delfolder, path) and not isfolder(path) then
        return true
    end
    if type(listfiles) == "function" then
        local ok, entries = pcall(listfiles, path)
        for _, entry in ipairs(ok and entries or {}) do
            if isfolder(entry) then
                wipeFolder(entry)
            elseif type(delfile) == "function" then
                pcall(delfile, entry)
            end
        end
    end
    if type(delfolder) == "function" then
        pcall(delfolder, path)
    end
    return not isfolder(path)
end

-- Deletes the script's whole workspace folder: configs, themes, the default
-- theme, autoload, settings and the execution count.
function Window:ClearWorkspace()
    local ok = wipeFolder(self.ConfigFolder)
    self.LoadedConfig = nil
    for _, handler in ipairs(self._workspaceListeners or {}) do
        safeCall(handler)
    end
    self:_configChanged()
    return ok
end

-- Share codes are the same JSON a config file holds.

function Window:ExportConfig(name)
    local data, err
    if name then
        data, err = readConfig(self, name)
        if not data then
            return nil, err
        end
    else
        data = collectFlags(self)
        name = self.LoadedConfig or self.ConfigName
    end
    local ok, code = pcall(encodeConfig, self, name, data)
    if not ok then
        return nil, "could not encode config"
    end
    return code
end

-- Reads a code without applying it. Returns flags and { Folder, Name, Version }.
function Window:DecodeConfig(code)
    return decodeConfig(code)
end

-- saveAs: a name to save under, true for the name inside the code, or nil to
-- only apply it. Codes made for another folder are refused unless force is set.
function Window:ImportConfig(code, saveAs, force)
    local data, info = decodeConfig(code)
    if not data then
        return false, info
    end
    if not force and info.Folder and info.Folder ~= self.ConfigFolder then
        return false, "config is for " .. info.Folder
    end
    if saveAs == true then
        saveAs = info.Name
        if not validConfigName(saveAs) then
            return false, "config has no usable name"
        end
    end
    if saveAs then
        local ok, err = writeConfig(self, saveAs, data)
        if not ok then
            return false, err
        end
    end
    self:_applyFlags(data)
    if saveAs then
        self.ConfigName = saveAs
        self.LoadedConfig = saveAs
    end
    self:_configChanged()
    return true, nil, saveAs
end

local function readText(path)
    if not fileApiAvailable() or not isfile(path) then
        return nil
    end
    local ok, text = pcall(readfile, path)
    if ok and type(text) == "string" and text ~= "" then
        return text
    end
    return nil
end

local function removeFile(path)
    if fileApiAvailable() and type(delfile) == "function" and isfile(path) then
        pcall(delfile, path)
    end
end

-- Manager settings (autoload mode) live beside the configs, apart
-- from the flags, so loading a config never changes them.

local function settingsPath(self)
    return self.ConfigFolder .. "/configsettings.txt"
end

function Window:_readConfigSettings()
    local text = readText(settingsPath(self))
    if text then
        local ok, data = pcall(function()
            return HttpService:JSONDecode(text)
        end)
        if ok and type(data) == "table" then
            return data
        end
    end
    return {}
end

function Window:_writeConfigSettings(changes)
    if not fileApiAvailable() then
        return false, "file API unavailable"
    end
    local data = self:_readConfigSettings()
    for key, value in pairs(changes) do
        data[key] = value
    end
    ensureFolder(self.ConfigFolder)
    return pcall(writefile, settingsPath(self), HttpService:JSONEncode(data))
end

-- Autoload: one config name kept next to the configs, either for every
-- account ("Global") or only the local player ("Account").

local function autoloadPath(self, scope)
    if scope == "Account" then
        return self.ConfigFolder .. "/autoload_" .. tostring(LocalPlayer and LocalPlayer.UserId or 0) .. ".txt"
    end
    return self.ConfigFolder .. "/autoload.txt"
end

function Window:GetAutoloadMode()
    return self:_readConfigSettings().AutoloadMode == "Account" and "Account" or "Global"
end

function Window:GetAutoload(scope)
    if scope then
        return readText(autoloadPath(self, scope))
    end
    return readText(autoloadPath(self, "Account")) or readText(autoloadPath(self, "Global"))
end

function Window:SetAutoload(name, scope)
    if not fileApiAvailable() then
        return false, "file API unavailable"
    end
    scope = scope or self:GetAutoloadMode()
    local ok, err = true, nil
    if name == nil or name == "" then
        removeFile(autoloadPath(self, scope))
        if scope == "Global" then
            removeFile(autoloadPath(self, "Account"))
        end
    else
        ensureFolder(self.ConfigFolder)
        ok, err = pcall(writefile, autoloadPath(self, scope), tostring(name))
        if ok and scope == "Global" then
            removeFile(autoloadPath(self, "Account"))
        end
    end
    self:_configChanged()
    return ok, err
end

-- Switching the mode moves the current autoload so only one stays active.
function Window:SetAutoloadMode(mode)
    mode = mode == "Account" and "Account" or "Global"
    if mode == self:GetAutoloadMode() then
        return true
    end
    local current = self:GetAutoload()
    local ok, err = self:_writeConfigSettings({ AutoloadMode = mode })
    if not ok then
        return false, err
    end
    removeFile(autoloadPath(self, mode == "Account" and "Global" or "Account"))
    if current then
        return self:SetAutoload(current, mode)
    end
    self:_configChanged()
    return true
end

function Window:LoadAutoload(silent)
    if self._autoloaded then
        return false, "autoload already ran"
    end
    self._autoloaded = true
    local name = self:GetAutoload()
    if not name then
        return false, "no autoload config"
    end
    local ok, err = self:LoadConfig(name, silent)
    pcall(self.Notify, self, {
        Title = ok and "Autoload" or "Autoload failed",
        Content = ok and ("Loaded config %q"):format(name) or tostring(err),
        Type = ok and "Success" or "Error",
        Duration = 3,
    })
    return ok, err
end

-- Themes

Library._themeListeners = {}

local function toColor(value)
    if typeof(value) == "Color3" then
        return value
    elseif type(value) == "string" then
        local r, g, b = value:match("^%s*#?(%x%x)(%x%x)(%x%x)%s*$")
        if r then
            return Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16))
        end
    elseif type(value) == "table" then
        local r, g, b = value[1] or value.R, value[2] or value.G, value[3] or value.B
        if tonumber(r) and tonumber(g) and tonumber(b) then
            return Color3.fromRGB(r, g, b)
        end
    end
    return nil
end

local function hexOf(color)
    return string.format("#%02X%02X%02X",
        math.floor(color.R * 255 + 0.5),
        math.floor(color.G * 255 + 0.5),
        math.floor(color.B * 255 + 0.5))
end

-- Coloured text for statuses, metrics, table cells and labels. A theme key
-- used as a tag, <Success>online</Success>, follows theme changes; plain
-- rich text such as <font color="#ff5a5a"> works too. Library.Colorize wraps
-- text for you. Table fields, not locals: the chunk is at Luau's 200 limit.
Library._toneTags = {}
for _, name in ipairs(THEME_KEYS) do
    Library._toneTags[string.lower(name)] = name
end

-- A theme key, a Color3, "#rrggbb" or { r, g, b } as a Color3.
function Library._color(value)
    if type(value) == "string" then
        local key = Library._toneTags[string.lower(value)]
        if key then
            return Theme[key]
        end
    end
    return toColor(value)
end

function Library._rich(text)
    text = tostring(text == nil and "" or text)
    if not string.find(text, "<", 1, true) then
        return text
    end
    return (string.gsub(text, "<(/?)(%a+%d*)>", function(slash, name)
        local key = Library._toneTags[string.lower(name)]
        if not key then
            return nil
        end
        if slash == "/" then
            return "</font>"
        end
        return '<font color="' .. hexOf(Theme[key]) .. '">'
    end))
end

-- Library.Colorize("12 ms", "Success") or Library:Colorize(text, Color3).
function Library.Colorize(...)
    local args = { ... }
    if args[1] == Library then
        table.remove(args, 1)
    end
    local text, color = tostring(args[1] == nil and "" or args[1]), args[2]
    local key = type(color) == "string" and Library._toneTags[string.lower(color)]
    if key then
        return "<" .. key .. ">" .. text .. "</" .. key .. ">"
    end
    local resolved = toColor(color)
    if not resolved then
        return text
    end
    return '<font color="' .. hexOf(resolved) .. '">' .. text .. "</font>"
end

-- The window's corner radius in pixels, 0 (square) to 20; every other
-- rounded corner scales with it. The default is 10. Corners ease to the new
-- radius instead of jumping. Returns the radius it settled on.
function Library:SetCornerRadius(pixels, instant)
    pixels = math.clamp(math.floor((tonumber(pixels) or 10) + 0.5), 0, 20)
    Library.Roundness = pixels / 10
    for object, base in pairs(Library._cornerBases) do
        if not object.Parent then
            Library._cornerBases[object] = nil
        else
            local radius = UDim.new(0, math.floor(base * Library.Roundness + 0.5))
            if instant then
                object.CornerRadius = radius
            else
                tween(object, { CornerRadius = radius }, 0.25, Enum.EasingStyle.Quint)
            end
        end
    end
    return pixels
end

function Library:GetCornerRadius()
    return math.floor(Library.Roundness * 10 + 0.5)
end

function Library:SetTheme(theme, instant)
    if type(theme) == "string" then
        local found = Library.ThemePresets[theme]
        if not found then
            return false
        end
        Library.ThemeName = theme
        theme = found
    elseif type(theme) ~= "table" then
        return false
    end
    local changed = false
    local aliases = {
        ["Card Header"] = "CardHeader",
        ["Card Outline"] = "Outline",
        CardOutline = "Outline",
        ["Tab Structure"] = "TabStructure",
        Sidebar = "TabStructure",
    }
    for alias, target in pairs(aliases) do
        if theme[alias] ~= nil and theme[target] == nil then
            theme[target] = theme[alias]
        end
    end
    for _, name in ipairs(THEME_KEYS) do
        local color = toColor(theme[name])
        if color and color ~= Theme[name] then
            Theme[name] = color
            changed = true
        end
    end
    if not changed then
        return true
    end
    rebuildThemeLookup()
    sweepBindings()
    driveTheme(instant and 0 or 0.3)
    for owner, fn in pairs(themeHooks) do
        if typeof(owner) ~= "Instance" or owner.Parent then
            pcall(fn)
        end
    end
    for _, fn in ipairs(Library._themeListeners) do
        pcall(fn)
    end
    return true
end

function Library:GetTheme()
    local copy = {}
    for _, name in ipairs(THEME_KEYS) do
        copy[name] = Theme[name]
    end
    return copy
end

-- The script's starting theme: a preset name or a colour table. A default the
-- player picked in the theme manager still wins over it.
function Library:SetDefaultTheme(theme)
    Library.DefaultTheme = theme
    if theme == nil then
        return true
    end
    local live = false
    for _, window in ipairs(Library.Windows) do
        if not window._destroyed then
            if window:GetDefaultTheme() then
                return true
            end
            live = true
        end
    end
    return Library:SetTheme(theme, not live)
end

function Library:GetDefaultTheme()
    return Library.DefaultTheme
end

local function themeFolder(self)
    return self.ConfigFolder .. "/themes"
end

function Window:SaveTheme(name)
    if not fileApiAvailable() then
        return false, "file API unavailable"
    end
    if type(name) ~= "string" or name == "" then
        return false, "theme needs a name"
    end
    ensureFolder(self.ConfigFolder)
    ensureFolder(themeFolder(self))
    local data = {}
    for _, key in ipairs(THEME_KEYS) do
        data[key] = hexOf(Theme[key])
    end
    return pcall(function()
        writefile(themeFolder(self) .. "/" .. name .. ".json", HttpService:JSONEncode(data))
    end)
end

function Window:LoadTheme(name, instant)
    if Library.ThemePresets[name] then
        return Library:SetTheme(name, instant)
    end
    local text = readText(themeFolder(self) .. "/" .. tostring(name) .. ".json")
    if not text then
        return false, "no theme named " .. tostring(name)
    end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(text)
    end)
    if not ok or type(data) ~= "table" then
        return false, "theme is not valid JSON"
    end
    Library.ThemeName = name
    return Library:SetTheme(data, instant)
end

function Window:DeleteTheme(name)
    if not fileApiAvailable() or type(delfile) ~= "function" then
        return false, "file API unavailable"
    end
    local path = themeFolder(self) .. "/" .. tostring(name) .. ".json"
    if not isfile(path) then
        return false, "no theme named " .. tostring(name)
    end
    delfile(path)
    if self:GetDefaultTheme() == name then
        self:SetDefaultTheme(nil)
    end
    return true
end

function Window:ListThemes()
    local names = {}
    if type(listfiles) ~= "function" or type(isfolder) ~= "function" or not isfolder(themeFolder(self)) then
        return names
    end
    for _, path in ipairs(listfiles(themeFolder(self))) do
        local name = path:match("([^/\\]+)%.json$")
        if name then
            table.insert(names, name)
        end
    end
    table.sort(names)
    return names
end

function Window:GetDefaultTheme()
    return readText(themeFolder(self) .. "/default.txt")
end

function Window:SetDefaultTheme(name)
    if not fileApiAvailable() then
        return false, "file API unavailable"
    end
    ensureFolder(self.ConfigFolder)
    ensureFolder(themeFolder(self))
    local path = themeFolder(self) .. "/default.txt"
    if name == nil or name == "" then
        if isfile(path) and type(delfile) == "function" then
            pcall(delfile, path)
        end
        return true
    end
    return pcall(writefile, path, tostring(name))
end

function Window:_applyDefaultTheme()
    local name = self:GetDefaultTheme()
    if name then
        local ok, loaded = pcall(self.LoadTheme, self, name, true)
        if ok and loaded then
            return
        end
    end
    if Library.DefaultTheme ~= nil then
        pcall(Library.SetTheme, Library, Library.DefaultTheme, true)
    end
end

-- Background images

-- Image assets anyone can use, from Fluent-modded's themes.
Library.BackgroundPresets = {
    ["Deep Violet"] = "rbxassetid://136310484943077",
    ["Blood Red"] = "rbxassetid://121343473918667",
    ["Cyanic"] = "rbxassetid://95656189244173",
    ["Amber Glow"] = "rbxassetid://107795771598485",
    ["Bloomings"] = "rbxassetid://133541508207801",
    ["Lavender Pink"] = "rbxassetid://126107479485287",
}
Library.BackgroundPresetOrder = { "Deep Violet", "Blood Red", "Cyanic", "Amber Glow", "Bloomings", "Lavender Pink" }

-- Table fields, not locals: the library chunk is at Luau's 200 local limit.
Library._imageExtensions = { png = true, jpg = true, jpeg = true, webp = true, gif = true, bmp = true }

function Window:_backgroundFolder()
    return self.ConfigFolder .. "/backgrounds"
end

function Window:_trimBackground(source)
    return (tostring(source or ""):match("^%s*(.-)%s*$"))
end

-- Turns a background source into something ImageLabel.Image takes. Web images
-- are downloaded once into backgrounds/cache and loaded with getcustomasset,
-- so this yields the first time a URL is used.
function Window:_resolveBackground(source)
    source = self:_trimBackground(source)
    local preset = Library.BackgroundPresets[source]
    if preset then
        return preset
    end
    if source:match("^%d+$") then
        return "rbxassetid://" .. source
    end
    if source:match("^rbxassetid://%d+") or source:match("^rbxasset://") or source:match("^rbxthumb://")
        or source:match("^https?://www%.roblox%.com/asset") then
        return source
    end
    local canLoad = fileApiAvailable() and typeof(getcustomasset) == "function"
    if source:match("^https?://") then
        if not canLoad then
            return nil, "web images need writefile and getcustomasset"
        end
        local clean = source:match("^[^?#]+") or source
        local ext = (clean:match("%.(%w+)$") or "png"):lower()
        if not Library._imageExtensions[ext] then
            ext = "png"
        end
        local key = (clean:gsub("^https?://", ""):gsub("[^%w]", "_")):sub(-60)
        local folder = self:_backgroundFolder() .. "/cache"
        local path = folder .. "/" .. key .. "_" .. #source .. "." .. ext
        if not isfile(path) then
            local ok, body = pcall(function()
                local request = (syn and syn.request) or http_request or request
                if request then
                    local response = request({ Url = source, Method = "GET" })
                    return response and response.Body
                end
                return game:HttpGet(source, true)
            end)
            if not ok or type(body) ~= "string" or #body < 128 then
                return nil, "could not download the image"
            end
            local head = body:sub(1, 64):lower()
            if head:find("<!doctype") or head:find("<html") then
                return nil, "that link is a web page, not an image"
            end
            ensureFolder(folder)
            if not pcall(writefile, path, body) then
                return nil, "could not save the image"
            end
        end
        local ok, asset = pcall(getcustomasset, path)
        if ok and type(asset) == "string" and asset ~= "" then
            return asset
        end
        pcall(delfile, path)
        return nil, "the downloaded file is not an image"
    end
    -- A file in the backgrounds folder, or any path in the workspace.
    if canLoad then
        for _, path in ipairs({ self:_backgroundFolder() .. "/" .. source, source }) do
            if isfile(path) then
                local ok, asset = pcall(getcustomasset, path)
                if ok and type(asset) == "string" and asset ~= "" then
                    return asset
                end
                return nil, "could not load " .. source
            end
        end
    end
    return nil, "no image called " .. source
end

-- source: a preset name, an image asset id, an rbxassetid:// link, an http(s)
-- image URL, or an image file in <ConfigFolder>/backgrounds. nil or "None"
-- removes it. May yield while a web image downloads.
function Window:SetBackground(source)
    self._backgroundGeneration += 1
    local generation = self._backgroundGeneration
    local image = self._backgroundImage
    source = source ~= false and self:_trimBackground(source) or ""
    if source == "" or source == "None" then
        self.Background = nil
        tween(image, { ImageTransparency = 1 }, 0.25)
        task.delay(0.25, function()
            if self._backgroundGeneration == generation then
                image.Visible = false
                image.Image = ""
            end
        end)
        self:SetTransparent(self.Transparent)
        return true
    end
    local asset, err = self:_resolveBackground(source)
    if self._backgroundGeneration ~= generation or self._destroyed then
        return false, "replaced by a newer background"
    end
    if not asset then
        return false, err
    end
    self.Background = source
    image.Image = asset
    image.Visible = true
    tween(image, { ImageTransparency = self.BackgroundTransparency }, 0.3)
    self:SetTransparent(self.Transparent)
    return true
end

function Window:GetBackground()
    return self.Background
end

-- 0 shows the image fully, 1 hides it behind the theme background colour.
function Window:SetBackgroundTransparency(value)
    self.BackgroundTransparency = math.clamp(tonumber(value) or 0.35, 0, 1)
    if self.Background then
        tween(self._backgroundImage, { ImageTransparency = self.BackgroundTransparency }, 0.15)
    end
end

-- Preset names, then the image files in <ConfigFolder>/backgrounds.
function Window:ListBackgrounds()
    local names = table.clone(Library.BackgroundPresetOrder)
    local folder = self:_backgroundFolder()
    if type(listfiles) == "function" and type(isfolder) == "function" and isfolder(folder) then
        local files = {}
        for _, path in ipairs(listfiles(folder)) do
            local name = path:match("([^/\]+)$")
            local ext = name and name:match("%.(%w+)$")
            if ext and Library._imageExtensions[ext:lower()] then
                table.insert(files, name)
            end
        end
        table.sort(files)
        for _, name in ipairs(files) do
            table.insert(names, name)
        end
    end
    return names
end

local function emptyState(parent, icon, text)
    local holder = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, -10),
        Size = UDim2.fromOffset(200, 70),
        BackgroundTransparency = 1,
        Parent = parent,
    })
    local image = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 0),
        Size = UDim2.fromOffset(26, 26),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ImageTransparency = 0.15,
        ScaleType = Enum.ScaleType.Fit,
        Parent = holder,
    })
    applyIcon(image, icon)
    local caption = label({
        Position = UDim2.fromOffset(0, 36),
        Size = UDim2.new(1, 0, 0, 16),
        Text = text,
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = holder,
    })
    return holder, caption, image
end

local function fadeSlideIn(group, restY)
    restY = restY or 0
    group.GroupTransparency = 1
    group.Position = UDim2.fromOffset(0, restY + 14)
    group.Visible = true
    tween(group, { GroupTransparency = 0, Position = UDim2.fromOffset(0, restY) }, 0.32, Enum.EasingStyle.Quint)
end

local function formatDuration(seconds)
    seconds = math.max(math.floor(seconds), 0)
    local days = math.floor(seconds / 86400)
    local hours = math.floor(seconds / 3600) % 24
    local minutes = math.floor(seconds / 60) % 60
    if days > 0 then
        return string.format("%dd %dh", days, hours)
    elseif hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    elseif minutes > 0 then
        return string.format("%dm %ds", minutes, seconds % 60)
    end
    return string.format("%ds", seconds)
end

local function shortId(id)
    if type(id) ~= "string" or id == "" then
        return "Studio"
    end
    if #id > 16 then
        return id:sub(1, 8) .. "..." .. id:sub(-4)
    end
    return id
end

local function copyToClipboard(text)
    local setter = setclipboard or toclipboard or (Clipboard and Clipboard.set)
    if type(setter) ~= "function" then
        return false
    end
    return (pcall(setter, tostring(text)))
end

local function fetchServers(order)
    local url = string.format(
        "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=%s&limit=100&excludeFullGames=true",
        game.PlaceId,
        order
    )
    local ok, body = pcall(function()
        return game:HttpGet(url)
    end)
    if not ok or type(body) ~= "string" then
        return nil
    end
    local decoded, data = pcall(function()
        return HttpService:JSONDecode(body)
    end)
    if not decoded or type(data) ~= "table" or type(data.data) ~= "table" then
        return nil
    end
    return data.data
end

-- Small on/off pill used on the home card for the privacy switches.
local function miniSwitch(parent, initial, order, callback)
    local pill = create("TextButton", {
        Size = UDim2.fromOffset(30, 16),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = order,
        Parent = parent,
    })
    corner(pill, UDim.new(1, 0))
    stroke(pill)
    local knob = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 2, 0.5, 0),
        Size = UDim2.fromOffset(12, 12),
        BackgroundColor3 = Theme.Muted,
        BorderSizePixel = 0,
        Parent = pill,
    })
    corner(knob, UDim.new(1, 0))
    local on = initial == true
    local function render(animate)
        local duration = animate and 0.22 or 0
        tween(pill, { BackgroundColor3 = on and Theme.Accent or Theme.Surface3 }, duration)
        tween(knob, {
            Position = on and UDim2.new(0, 16, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
            BackgroundColor3 = on and Theme.AccentDark or Theme.Muted,
        }, duration, Enum.EasingStyle.Back)
    end
    pill.MouseButton1Click:Connect(function()
        on = not on
        render(true)
        safeCall(callback, on)
    end)
    render(false)
    return pill
end

local function softButton(parent, text, props, callback)
    local button = create("TextButton", {
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.45,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ClipsDescendants = true,
        Parent = parent,
    })
    for key, value in pairs(props) do
        button[key] = value
    end
    corner(button, UDim.new(0, 6))
    local buttonStroke = stroke(button)
    local text_ = label({
        Size = UDim2.fromScale(1, 1),
        Text = text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = button,
    })
    if button.AutomaticSize == Enum.AutomaticSize.X then
        text_.Size = UDim2.new(0, 0, 1, 0)
        text_.AutomaticSize = Enum.AutomaticSize.X
        text_.TextTruncate = Enum.TextTruncate.None
        padding(button, 14, 14)
    end
    button.MouseEnter:Connect(function()
        tween(button, { BackgroundTransparency = 0.15 }, 0.12)
        tween(buttonStroke, { Color = Theme.StrokeHover }, 0.12)
    end)
    button.MouseLeave:Connect(function()
        tween(button, { BackgroundTransparency = 0.45 }, 0.25)
        tween(buttonStroke, { Color = Theme.Stroke }, 0.25)
    end)
    button.MouseButton1Click:Connect(function()
        ripple(button)
        safeCall(callback)
    end)
    return button, text_
end

local function panelCard(parent, height, order)
    local frame = create("Frame", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundColor3 = Theme.Surface2,
        BorderSizePixel = 0,
        LayoutOrder = order,
        Parent = parent,
    })
    frame:SetAttribute("NoDrag", true)
    corner(frame, UDim.new(0, 10))
    stroke(frame)
    return frame
end

local STAT_TYPES = {
    Players = { "users", "Players" },
    Friends = { "user-check", "Friends" },
    Execs = { "zap", "Execs" },
    Session = { "timer", "Session" },
    Uptime = { "timer", "Session" },
    FPS = { "gauge", "FPS" },
    Ping = { "wifi", "Ping" },
    Executor = { "terminal", "Executor" },
    Game = { "gamepad-2", "Game" },
    Region = { "globe", "Region" },
    Time = { "clock", "Time" },
    ServerAge = { "server", "Server age" },
    Memory = { "cpu", "Memory" },
}

-- Health colour for a live metric: Success under good, Warning under bad,
-- Error past it. lowerIsBetter flips the scale (ping, memory).
function Library._healthColor(value, good, bad, lowerIsBetter)
    if type(value) ~= "number" then
        return Theme.Text
    end
    if lowerIsBetter then
        return value <= good and Theme.Success or value <= bad and Theme.Warning or Theme.Error
    end
    return value >= good and Theme.Success or value >= bad and Theme.Warning or Theme.Error
end

local function bumpExecutions(folder)
    if not fileApiAvailable() then
        return nil
    end
    local path = folder .. "/executions.txt"
    local count = 0
    pcall(function()
        ensureFolder(folder)
        if isfile(path) then
            count = tonumber(readfile(path)) or 0
        end
    end)
    count += 1
    pcall(writefile, path, tostring(count))
    return count
end

-- Containers: a tab or sub tab owns a scrolling list. Elements added straight
-- to it stack full width, groupboxes go into two columns underneath.

local function buildContainer(owner, parent, top, emptyIcon, emptyText)
    local list = create("ScrollingFrame", {
        Position = UDim2.fromOffset(0, top),
        Size = UDim2.new(1, 0, 1, -top),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0.5,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        Parent = parent,
    })
    Library._space(padding(list, 24, 24, 2, 24), { 24, 24, 2, 24 })
    Library._space(create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = list,
    }), 8)
    owner.List = list
    owner._items = {}
    owner._groupboxes = {}
    owner._childCount = 0
    owner._emptyText = emptyText
    owner._empty, owner._emptyCaption = emptyState(parent, emptyIcon, emptyText)
    list.ChildAdded:Connect(function(child)
        if child:IsA("GuiObject") then
            owner._childCount += 1
            owner:_refreshEmpty()
        end
    end)
    list.ChildRemoved:Connect(function(child)
        if child:IsA("GuiObject") then
            owner._childCount = math.max(owner._childCount - 1, 0)
            owner:_refreshEmpty()
        end
    end)
    owner:_refreshEmpty()
    return list
end

function Tab:_refreshEmpty()
    local empty = self._empty
    if not empty then
        return
    end
    if self._subTabs then
        empty.Visible = false
    else
        empty.Visible = self._childCount == 0
    end
end

function Tab:_columns()
    if self._columnSet then
        return self._columnSet
    end
    local holder = create("Frame", {
        Name = "Columns",
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 100000,
        Parent = self.List,
    })
    local layout = Library._space(create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 10),
        Parent = holder,
    }), 10)
    local function column(order)
        local frame = create("Frame", {
            Size = UDim2.new(0.5, -5, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            LayoutOrder = order,
            Parent = holder,
        })
        Library._space(create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 10),
            Parent = frame,
        }), 10)
        return frame
    end
    local set = { Holder = holder, Left = column(1), Right = column(2), Counts = { 0, 0 }, Stacked = false }
    local window = self.Window
    -- Narrow windows stack the right column under the left one.
    local function relayout()
        local width = holder.AbsoluteSize.X / window.Scale.Scale
        if width <= 0 then
            return
        end
        local stacked = width < STACK_BELOW
        local gap = layout.Padding.Offset
        if stacked == set.Stacked and gap == set.Gap then
            return
        end
        set.Stacked = stacked
        set.Gap = gap
        layout.FillDirection = stacked and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal
        local size = stacked and UDim2.new(1, 0, 0, 0) or UDim2.new(0.5, -gap / 2, 0, 0)
        set.Left.Size = size
        set.Right.Size = size
    end
    holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
    layout:GetPropertyChangedSignal("Padding"):Connect(relayout)
    task.defer(relayout)
    self._columnSet = set
    return set
end

function Tab:Groupbox(opts, icon)
    if self._groupbox then
        return self.Parent:Groupbox(opts, icon)
    end
    opts = normalize(opts, { Title = "Name" })
    if icon ~= nil and opts.Icon == nil then
        opts.Icon = icon
    end
    local window = self.Window
    local set = self:_columns()
    local side = opts.Side
    if side == "Left" or side == 1 then
        side = 1
    elseif side == "Right" or side == 2 then
        side = 2
    else
        side = set.Counts[1] <= set.Counts[2] and 1 or 2
    end
    set.Counts[side] += 1

    local box = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Surface2,
        BorderSizePixel = 0,
        LayoutOrder = set.Counts[side],
        Parent = side == 1 and set.Left or set.Right,
    })
    box:SetAttribute("NoDrag", true)
    corner(box, UDim.new(0, 10))
    local boxStroke = stroke(box, Theme.Outline)
    bindTheme(boxStroke, "Color", "Outline")
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = box,
    })

    -- The header is a filled strip: icon and bold title on the left, a
    -- chevron on the right. Pressing anywhere on it folds the box.
    local header = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = Theme.CardHeader,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = 1,
        Parent = box,
    })
    bindTheme(header, "BackgroundColor3", "CardHeader")
    corner(header, UDim.new(0, 10))
    -- Squares the strip's lower corners so it meets the body flat.
    local headerFill = create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 10),
        BackgroundColor3 = Theme.CardHeader,
        BorderSizePixel = 0,
        Parent = header,
    })
    bindTheme(headerFill, "BackgroundColor3", "CardHeader")
    -- Left Accent Pill Indicator (matches IggyOuroboros)
    local accentPill = create("Frame", {
        Name = "AccentPill",
        Size = UDim2.new(0, 3, 0, 16),
        Position = UDim2.new(0, 4, 0.5, -8),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        ZIndex = 2,
        Parent = header,
    })
    corner(accentPill, UDim.new(1, 0))
    local titleX = 14
    if opts.Icon then
        local headerIcon = create("ImageLabel", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 14, 0.5, 0),
            Size = UDim2.fromOffset(14, 14),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Accent,
            ScaleType = Enum.ScaleType.Fit,
            ZIndex = 2,
            Parent = header,
        })
        applyIcon(headerIcon, opts.Icon)
        titleX = 37
    end
    local collapseButton = create("ImageLabel", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -14, 0.5, 0),
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = 2,
        Parent = header,
    })
    applyIcon(collapseButton, "chevron-down")
    -- Beside the chevron, a button that pops the box out into a floating
    -- panel (and docks it back once it's out). PopOut = false leaves it off.
    local canPop = opts.PopOut ~= false
    local popButton, popIcon
    if canPop then
        popButton = create("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -34, 0.5, 0),
            Size = UDim2.fromOffset(24, 24),
            BackgroundColor3 = Theme.Surface2,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 3,
            Parent = header,
        })
        corner(popButton, UDim.new(0, 6))
        popIcon = create("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(13, 13),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Muted,
            ImageTransparency = TOUCH and 0 or 0.45,
            ScaleType = Enum.ScaleType.Fit,
            ZIndex = 3,
            Parent = popButton,
        })
        applyIcon(popIcon, "picture-in-picture-2")
    end
    local title = label({
        Position = UDim2.fromOffset(titleX, 0),
        Size = UDim2.new(1, -(titleX + (canPop and 66 or 40)), 1, 0),
        Text = opts.Name or "Groupbox",
        TextSize = 13,
        FontFace = Fonts.Bold,
        ZIndex = 2,
        Parent = header,
    })

    local rule = create("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Outline,
        BorderSizePixel = 0,
        LayoutOrder = 2,
        Parent = box,
    })
    bindTheme(rule, "BackgroundColor3", "Outline")
    local body = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        LayoutOrder = 3,
        Parent = box,
    })
    local inner = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = body,
    })
    Library._space(padding(inner, 0, 0, 6, 8), { 0, 0, 6, 8 })
    Library._space(create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = inner,
    }), 2)

    local group = setmetatable({
        Name = opts.Name or "Groupbox",
        Window = window,
        Parent = self,
        List = inner,
        Frame = box,
        _frame = box,
        _order = 0,
        _groupbox = true,
        _metrics = METRICS.Row,
        _items = {},
    }, Tab)
    table.insert(self._groupboxes, group)

    local collapsed = false
    local generation = 0
    local function setCollapsed(value, instant)
        value = value == true
        if value == collapsed then
            return
        end
        collapsed = value
        generation += 1
        local current = generation
        local duration = instant and 0 or 0.32
        local easing = Enum.EasingStyle.Quart
        -- Anything open inside the box (a dropdown list, a picker, a focused
        -- box) closes with it, rather than floating over a folded header.
        if value then
            for _, element in ipairs(group._items) do
                if element._onHide then
                    element._onHide()
                end
                if element.Open and type(element.SetOpen) == "function" then
                    element:SetOpen(false)
                end
            end
        end
        window._controlsDirty = true
        local scale = window.Scale.Scale
        if value then
            body.AutomaticSize = Enum.AutomaticSize.None
            body.Size = UDim2.new(1, 0, 0, body.AbsoluteSize.Y / scale)
            local t = tween(body, { Size = UDim2.new(1, 0, 0, 0) }, duration, easing)
            tween(rule, { Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1 }, duration, easing)
            tween(headerFill, { BackgroundTransparency = 1 }, duration, easing)
            local function fold()
                if generation == current and collapsed then
                    rule.Visible = false
                    headerFill.Visible = false
                end
            end
            if t then
                t.Completed:Connect(fold)
            elseif duration > 0 then
                task.delay(duration, fold)
            else
                fold()
            end
        else
            rule.Visible = true
            headerFill.Visible = true
            if duration > 0 and not instant then
                tween(rule, { Size = UDim2.new(1, 0, 0, 1), BackgroundTransparency = 0 }, duration, easing)
                tween(headerFill, { BackgroundTransparency = 0 }, duration, easing)
            else
                rule.Size = UDim2.new(1, 0, 0, 1)
                rule.BackgroundTransparency = 0
                headerFill.BackgroundTransparency = 0
            end
            local layout = inner:FindFirstChildWhichIsA("UIListLayout")
            local targetHeight = math.max(
                layout and (layout.AbsoluteContentSize.Y / scale + 14) or 0,
                inner.AbsoluteSize.Y / scale
            )
            local t = tween(body, { Size = UDim2.new(1, 0, 0, targetHeight) }, duration, easing)
            local function settle()
                if generation == current and not collapsed then
                    body.AutomaticSize = Enum.AutomaticSize.Y
                    body.Size = UDim2.new(1, 0, 0, 0)
                end
            end
            if t then
                t.Completed:Connect(settle)
            elseif duration > 0 then
                task.delay(duration, settle)
            else
                settle()
            end
        end
        local motion = instant and 0 or 0.32
        tween(collapseButton, { Rotation = value and -90 or 0 }, motion, easing)
        tween(accentPill, {
            BackgroundTransparency = value and 0.7 or 0,
            Size = value and UDim2.new(0, 3, 0, 8) or UDim2.new(0, 3, 0, 16),
            Position = value and UDim2.new(0, 4, 0.5, -4) or UDim2.new(0, 4, 0.5, -8),
        }, motion, easing)
    end

    local function hover(on)
        local duration = on and 0.15 or 0.25
        tween(collapseButton, { ImageColor3 = on and Theme.Text or Theme.Muted }, duration)
        if popIcon and not TOUCH then
            tween(popIcon, { ImageTransparency = on and 0 or 0.45 }, duration)
        end
    end
    header.MouseEnter:Connect(function()
        hover(true)
    end)
    header.MouseLeave:Connect(function()
        hover(false)
    end)
    local isTap = tapGuard(header, function()
        return box:FindFirstAncestorWhichIsA("ScrollingFrame")
    end)
    -- Popping out: the box itself is lifted out of its column into a panel
    -- on the window's pop-out layer, and a slot holds its place in the column
    -- (pressing the slot docks it back). The header drags the panel; a drop
    -- is clamped on screen and the spot is remembered for the next pop-out.
    local popped, popGeneration = false, 0
    local panel, panelScale, panelShadow, slot, stopPanel
    local dragStart, dragOrigin, dragMoved, suppressClick = nil, nil, false, false
    local animating = false

    local function layerScale()
        return math.max(window.Scale.Scale, 0.05)
    end
    local function toLayer(point)
        return (point - window._popLayer.AbsolutePosition) / layerScale()
    end
    -- Keeps a panel's top-centre spot on screen, header always reachable.
    local function clampSpot(spot, width, height)
        local view = window._popLayer.AbsoluteSize / layerScale()
        local margin = 8
        local x = math.clamp(spot.X, width / 2 + margin, math.max(view.X - width / 2 - margin, width / 2 + margin))
        local y = math.clamp(spot.Y, margin, math.max(view.Y - math.min(height, 120) - margin, margin))
        return Vector2.new(x, y)
    end
    local function closeInner()
        for _, element in ipairs(group._items) do
            if element._onHide then
                element._onHide()
            end
            if element.Open and type(element.SetOpen) == "function" then
                element:SetOpen(false)
            end
        end
    end
    local function setPopIcon(out)
        if popIcon then
            applyIcon(popIcon, out and "minimize-2" or "picture-in-picture-2")
        end
    end

    local function popOut()
        if popped or not canPop or not box.Parent or group._destroyed then
            return
        end
        -- A dock still in flight lands first, so the box is back in its column.
        if group._settleDock then
            group._settleDock()
        end
        local layer = window:_popoutLayer()
        popped = true
        group._popped = true
        popGeneration += 1
        local current = popGeneration
        closeInner()
        window:_closePopups()
        local scale = layerScale()
        local column = box.Parent
        local from = toLayer(box.AbsolutePosition)
        local width = box.AbsoluteSize.X / scale
        local height = box.AbsoluteSize.Y / scale

        -- The slot left behind: starts at the box's height so nothing below
        -- jumps, then eases down to a slim bar.
        slot = create("TextButton", {
            Size = UDim2.new(1, 0, 0, height),
            BackgroundColor3 = Theme.Surface2,
            BackgroundTransparency = 0.6,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            ClipsDescendants = true,
            LayoutOrder = box.LayoutOrder,
            Parent = column,
        })
        slot:SetAttribute("NoDrag", true)
        corner(slot, UDim.new(0, 10))
        stroke(slot, Theme.Stroke, 1).Transparency = 0.3
        local slotLabel = label({
            Size = UDim2.new(1, -24, 0, 40),
            Position = UDim2.fromOffset(12, 0),
            Text = Library._rich(group.Name) .. '<font transparency="0.4">  ·  popped out, click to dock</font>',
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextXAlignment = Enum.TextXAlignment.Center,
            RichText = true,
            TextTransparency = 1,
            Parent = slot,
        })
        local thisSlot = slot
        slot.MouseEnter:Connect(function()
            tween(thisSlot, { BackgroundTransparency = 0.35 }, 0.15)
        end)
        slot.MouseLeave:Connect(function()
            tween(thisSlot, { BackgroundTransparency = 0.6 }, 0.25)
        end)
        slot.MouseButton1Click:Connect(function()
            if slot == thisSlot then
                group:Dock()
            end
        end)
        tween(slot, { Size = UDim2.new(1, 0, 0, 40) }, 0.42, Enum.EasingStyle.Quint)
        tween(slotLabel, { TextTransparency = 0 }, 0.3)
        slot.Visible = box.Visible

        panel = create("Frame", {
            Name = "PopOut",
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.fromOffset(from.X + width / 2, from.Y),
            Size = UDim2.fromOffset(width, height),
            BackgroundTransparency = 1,
            Parent = layer,
        })
        panel:SetAttribute("NoDrag", true)
        panelScale = create("UIScale", { Parent = panel })
        panelShadow = create("ImageLabel", {
            Position = UDim2.fromOffset(-24, -18),
            Size = UDim2.new(1, 48, 1, 44),
            BackgroundTransparency = 1,
            Image = Assets.Shadow,
            ImageColor3 = Color3.new(0, 0, 0),
            ImageTransparency = 1,
            ScaleType = Enum.ScaleType.Slice,
            SliceCenter = Rect.new(49, 49, 450, 450),
            ZIndex = 0,
            Parent = panel,
        })
        table.insert(window._popPanels, panel)
        box.Parent = panel
        window._controlsDirty = true
        setPopIcon(true)

        -- Lifts off the column: a spring up and out to its float spot, with
        -- the shadow deepening under it.
        local spot = clampSpot(group._popSpot or Vector2.new(from.X + width / 2 + 22, from.Y - 14), width, height)
        animating = true
        panelScale.Scale = 0.97
        tween(panel, { Position = UDim2.fromOffset(spot.X, spot.Y) }, 0.5, Enum.EasingStyle.Quint)
        tween(panelScale, { Scale = 1 }, 0.55, Enum.EasingStyle.Back)
        tween(panelShadow, { ImageTransparency = 0.35 }, 0.4)
        task.delay(0.5, function()
            if popGeneration == current then
                animating = false
            end
        end)

        -- Each frame: the panel follows the box's height (folding, rows
        -- coming and going), mirrors its visibility, and stays on screen.
        local thisPanel = panel
        stopPanel = window:_listen("Render", function()
            if panel ~= thisPanel or not thisPanel.Parent then
                return
            end
            local boxHeight = box.AbsoluteSize.Y / layerScale()
            if math.abs(thisPanel.Size.Y.Offset - boxHeight) > 0.5 then
                thisPanel.Size = UDim2.fromOffset(thisPanel.Size.X.Offset, boxHeight)
            end
            thisPanel.Visible = box.Visible
            if slot then
                slot.Visible = box.Visible
            end
            if not animating and not dragStart then
                local position = Vector2.new(thisPanel.Position.X.Offset, thisPanel.Position.Y.Offset)
                local clamped = clampSpot(position, thisPanel.Size.X.Offset, boxHeight)
                if (clamped - position).Magnitude > 0.5 then
                    thisPanel.Position = UDim2.fromOffset(clamped.X, clamped.Y)
                end
            end
        end)
    end

    local function dock(instant)
        if not popped then
            return
        end
        popped = false
        group._popped = false
        popGeneration += 1
        dragStart, dragMoved, suppressClick = nil, false, false
        closeInner()
        window:_closePopups()
        local oldPanel, oldSlot, oldStop, oldScale, oldShadow = panel, slot, stopPanel, panelScale, panelShadow
        panel, slot, stopPanel = nil, nil, nil
        setPopIcon(false)
        group._popSpot = Vector2.new(oldPanel.Position.X.Offset, oldPanel.Position.Y.Offset)
        local settled = false
        local function settle()
            if settled then
                return
            end
            settled = true
            if group._settleDock == settle then
                group._settleDock = nil
            end
            if oldStop then
                oldStop()
            end
            local index = table.find(window._popPanels, oldPanel)
            if index then
                table.remove(window._popPanels, index)
            end
            -- Back into the column, unless it was popped again meanwhile.
            if box.Parent == oldPanel then
                if oldSlot and oldSlot.Parent and not group._destroyed then
                    box.Parent = oldSlot.Parent
                    box.LayoutOrder = oldSlot.LayoutOrder
                end
            end
            if oldSlot then
                oldSlot:Destroy()
            end
            if box.Parent ~= oldPanel then
                oldPanel:Destroy()
            end
            animating = false
            window._controlsDirty = true
        end
        group._settleDock = settle
        -- Flies home only when its slot is on screen; otherwise (another tab,
        -- the window hidden) it just drops back into place.
        local canFly = not instant and oldSlot and oldSlot.Parent and window.Root.Visible and box.Visible
            and oldSlot.AbsoluteSize.X > 0 and isShown(oldSlot, window.Body, oldSlot.AbsolutePosition + oldSlot.AbsoluteSize / 2)
        if not canFly then
            settle()
            return
        end
        animating = true
        local scale = layerScale()
        local height = box.AbsoluteSize.Y / scale
        local width = oldSlot.AbsoluteSize.X / scale
        tween(oldSlot, { Size = UDim2.new(1, 0, 0, height) }, 0.36, Enum.EasingStyle.Quint)
        local oldLabel = oldSlot:FindFirstChildWhichIsA("TextLabel")
        if oldLabel then
            tween(oldLabel, { TextTransparency = 1 }, 0.12)
        end
        -- The slot's top stays put as it grows, so its spot is the landing.
        local target = toLayer(oldSlot.AbsolutePosition)
        tween(oldPanel, {
            Position = UDim2.fromOffset(target.X + width / 2, target.Y),
            Size = UDim2.fromOffset(width, height),
        }, 0.36, Enum.EasingStyle.Quint)
        tween(oldScale, { Scale = 1 }, 0.2)
        tween(oldShadow, { ImageTransparency = 1 }, 0.3)
        task.delay(0.37, settle)
    end

    -- Dragging the floating panel by its header.
    header.InputBegan:Connect(function(input)
        if not popped or not isPress(input) or not panel then
            return
        end
        dragStart = Vector2.new(input.Position.X, input.Position.Y)
        dragOrigin = Vector2.new(panel.Position.X.Offset, panel.Position.Y.Offset)
        dragMoved = false
        suppressClick = false
    end)
    window:_listen("Changed", function(input)
        if not dragStart or not panel or not isMove(input) then
            return
        end
        local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
        if not dragMoved then
            if delta.Magnitude < (TOUCH and 8 or 5) then
                return
            end
            dragMoved, suppressClick = true, true
            animating = false
            closeInner()
            window:_closePopups()
            tween(panelScale, { Scale = 1.025 }, 0.18, Enum.EasingStyle.Quint)
            tween(panelShadow, { ImageTransparency = 0.15 }, 0.18)
        end
        local spot = clampSpot(dragOrigin + delta / layerScale(), panel.Size.X.Offset, panel.Size.Y.Offset)
        panel.Position = UDim2.fromOffset(spot.X, spot.Y)
    end, group)
    window:_listen("Ended", function(input)
        if not dragStart or not isPress(input) then
            return
        end
        dragStart = nil
        if dragMoved and panel then
            dragMoved = false
            tween(panelScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
            tween(panelShadow, { ImageTransparency = 0.35 }, 0.3)
            group._popSpot = Vector2.new(panel.Position.X.Offset, panel.Position.Y.Offset)
        end
    end, group)
    if popButton then
        popButton.MouseEnter:Connect(function()
            tween(popButton, { BackgroundTransparency = 0 }, 0.15)
            tween(popIcon, { ImageColor3 = Theme.Text }, 0.15)
        end)
        popButton.MouseLeave:Connect(function()
            tween(popButton, { BackgroundTransparency = 1 }, 0.25)
            tween(popIcon, { ImageColor3 = Theme.Muted }, 0.25)
        end)
        popButton.MouseButton1Click:Connect(function()
            if popped then
                dock()
            else
                popOut()
            end
        end)
    end

    header.MouseButton1Click:Connect(function()
        if suppressClick then
            suppressClick = false
            return
        end
        if isTap() then
            setCollapsed(not collapsed)
        end
    end)

    function group:PopOut()
        popOut()
    end
    function group:Dock()
        dock()
    end
    function group:IsPoppedOut()
        return popped
    end
    function group:SetCollapsed(value)
        setCollapsed(value)
    end
    function group:Collapse()
        setCollapsed(true)
    end
    function group:Expand()
        setCollapsed(false)
    end
    function group:IsCollapsed()
        return collapsed
    end
    function group:SetTitle(text)
        group.Name = tostring(text)
        title.Text = group.Name
    end
    group._userVisible = opts.Visible ~= false
    function group:IsVisible()
        return group._userVisible
    end
    function group:SetVisible(visible)
        visible = visible and true or false
        if visible == group._userVisible then
            return
        end
        group._userVisible = visible
        if not visible then
            for _, element in ipairs(group._items) do
                if element._onHide then
                    element._onHide()
                end
                if element.Open and type(element.SetOpen) == "function" then
                    element:SetOpen(false)
                end
            end
        end
        box.Visible = visible
        window._controlsDirty = true
    end
    if not group._userVisible then
        box.Visible = false
    end
    function group:Destroy()
        for index = #group._items, 1, -1 do
            local element = group._items[index]
            if type(element.Destroy) == "function" then
                element:Destroy()
            end
        end
        local owner = group.Parent
        local index = table.find(owner._groupboxes, group)
        if index then
            table.remove(owner._groupboxes, index)
        end
        set.Counts[side] = math.max(set.Counts[side] - 1, 0)
        dock(true)
        group._destroyed = true
        window._controlsDirty = true
        box:Destroy()
    end

    if opts.Collapsed then
        setCollapsed(true, true)
    end
    if opts.PoppedOut then
        task.defer(popOut)
    end
    return group
end

local function sideGroupbox(side)
    return function(self, opts, icon)
        opts = normalize(opts, { Title = "Name" })
        opts.Side = side
        return self:Groupbox(opts, icon)
    end
end

Tab.CreateGroupbox = Tab.Groupbox
Tab.AddGroupbox = Tab.Groupbox
Tab.AddLeftGroupbox = sideGroupbox("Left")
Tab.AddRightGroupbox = sideGroupbox("Right")

-- Button rows: equal-width buttons side by side.

function Tab:ButtonRow(opts)
    local specs = type(opts) == "table" and (opts.Buttons or opts) or {}
    local compact = metricsOf(self).Compact
    local boxHeight = TOUCH and 34 or 30
    local frame = card(self, "Frame", boxHeight + (compact and 4 or 14), {})
    local inset = compact and 14 or 7
    local holder = create("Frame", {
        Position = UDim2.fromOffset(inset, compact and 2 or 7),
        Size = UDim2.new(1, -inset * 2, 0, boxHeight),
        BackgroundTransparency = 1,
        Parent = frame,
    })
    local count = math.max(#specs, 1)
    local handle = { Buttons = {} }
    local names = {}
    for index, spec in ipairs(specs) do
        if type(spec) == "string" then
            spec = { Name = spec }
        end
        local text = spec.Name or spec.Title or "Button"
        table.insert(names, text)
        local button, text_ = softButton(holder, text, {
            Position = UDim2.new((index - 1) / count, (index - 1) * 6 / count, 0, 0),
            Size = UDim2.new(1 / count, -6 * (count - 1) / count, 1, 0),
        }, function()
            safeCall(spec.Callback)
        end)
        text_.TextSize = 13
        if spec.Style == "Primary" then
            attachAccentGradient(button, { Active = true, FallbackColor = Theme.Accent, ThemeKey = "Accent" })
            bindTheme(button, "BackgroundColor3", "Accent")
            if not Library.AccentGradient then
                tween(button, { BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.12 }, 0)
            else
                tween(button, { BackgroundTransparency = 0.12 }, 0)
            end
            tween(text_, { TextColor3 = Theme.AccentDark }, 0)
        elseif spec.Style == "Danger" then
            tween(text_, { TextColor3 = Theme.Error }, 0)
        end
        handle.Buttons[index] = { Button = button, Label = text_ }
    end
    function handle:SetText(index, text)
        local entry = handle.Buttons[index]
        if entry then
            entry.Label.Text = tostring(text)
        end
    end
    return finishElement(self, { Name = table.concat(names, " "), Visible = not (type(opts) == "table" and opts.Visible == false) }, handle, frame, "ButtonRow")
end

-- A text box with an action button beside it, for naming new configs and themes.
-- Without buttonText the box spans the row on its own.
local function actionInput(tab, placeholder, buttonText, callback)
    local boxHeight = TOUCH and 34 or 30
    local frame = card(tab, "Frame", boxHeight + 4, {})
    local inset = metricsOf(tab).Compact and 14 or 7
    local box
    local button = buttonText and softButton(frame, buttonText, {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -inset, 0, 2),
        Size = UDim2.fromOffset(0, boxHeight),
        AutomaticSize = Enum.AutomaticSize.X,
    }, function()
        safeCall(callback, box.Text)
    end)
    local holder = create("Frame", {
        Position = UDim2.fromOffset(inset, 2),
        Size = UDim2.new(1, -(inset * 2 + (button and 70 or 0)), 0, boxHeight),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = frame,
    })
    corner(holder, UDim.new(0, 6))
    local holderStroke = stroke(holder)
    box = create("TextBox", {
        Position = UDim2.fromOffset(8, 0),
        Size = UDim2.new(1, -16, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        PlaceholderText = placeholder,
        PlaceholderColor3 = Theme.Muted,
        TextColor3 = Theme.Text,
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ClearTextOnFocus = false,
        Parent = holder,
    })
    box.Focused:Connect(function()
        tween(holderStroke, { Color = Theme.StrokeHover }, 0.15)
    end)
    box.FocusLost:Connect(function(enterPressed)
        tween(holderStroke, { Color = Theme.Stroke }, 0.2)
        if enterPressed and box.Text ~= "" then
            safeCall(callback, box.Text)
        end
    end)
    if button then
        local function fit()
            local width = button.AbsoluteSize.X / tab.Window.Scale.Scale
            holder.Size = UDim2.new(1, -(inset * 2 + width + 6), 0, boxHeight)
        end
        button:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
        task.defer(fit)
    end
    return finishElement(tab, { Name = placeholder }, {
        Get = function()
            return box.Text
        end,
        Set = function(_, value)
            box.Text = tostring(value or "")
        end,
    }, frame, "ActionInput")
end

local function trim(text)
    return (tostring(text or ""):match("^%s*(.-)%s*$"))
end

-- An always-open single-pick list, for the config manager's saved configs.
-- tagsOf(name) returns short markers drawn at the row's right edge.
local function pickList(tab, names, default, rows, tagsOf, onPick, onOpen)
    local ROW = TOUCH and 30 or 24
    local listHeight = ROW * (rows or 5) + 8
    local frame = card(tab, "Frame", listHeight + 4, {})
    local inset = metricsOf(tab).Compact and 14 or 7
    local holder = create("Frame", {
        Position = UDim2.fromOffset(inset, 2),
        Size = UDim2.new(1, -inset * 2, 0, listHeight),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = frame,
    })
    corner(holder, UDim.new(0, 6))
    stroke(holder)
    local scroll = create("ScrollingFrame", {
        Position = UDim2.fromOffset(4, 4),
        Size = UDim2.new(1, -8, 1, -8),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = Theme.Stroke,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = holder,
    })
    create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
    local empty = label({
        Size = UDim2.new(1, 0, 0, ROW),
        Text = "no configs yet",
        TextColor3 = Theme.Muted,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = holder,
    })
    local selected, buttons = nil, {}

    local function paint(instant)
        for name, entry in pairs(buttons) do
            local on = name == selected
            tween(entry.Button, { BackgroundTransparency = on and 0.82 or 1 }, instant and 0 or 0.15)
            tween(entry.Label, { TextColor3 = on and Theme.Accent or Theme.Text }, instant and 0 or 0.15)
            entry.Bar.Visible = on
            local tags = tagsOf and tagsOf(name) or ""
            entry.Tags.Text = tags
            entry.Label.Size = UDim2.new(1, -(18 + entry.Tags.TextBounds.X + (tags ~= "" and 6 or 0)), 1, 0)
        end
    end

    local function pick(name)
        if selected == name then
            return
        end
        selected = name
        paint()
        safeCall(onPick, name)
    end

    local handle = {}
    function handle:Refresh(list)
        for _, entry in pairs(buttons) do
            entry.Button:Destroy()
        end
        buttons = {}
        for index, name in ipairs(list or {}) do
            local button = create("TextButton", {
                Size = UDim2.new(1, -4, 0, ROW),
                BackgroundColor3 = Theme.Accent,
                BackgroundTransparency = 1,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = index,
                Parent = scroll,
            })
            corner(button, UDim.new(0, 4))
            local bar = create("Frame", {
                Position = UDim2.new(0, 0, 0.5, -6),
                Size = UDim2.fromOffset(2, 12),
                BackgroundColor3 = Theme.Accent,
                BorderSizePixel = 0,
                Visible = false,
                Parent = button,
            })
            local text = label({
                Position = UDim2.fromOffset(10, 0),
                Size = UDim2.new(1, -18, 1, 0),
                Text = name,
                TextSize = 13,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = button,
            })
            local tags = label({
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -8, 0, 0),
                Size = UDim2.new(0, 0, 1, 0),
                AutomaticSize = Enum.AutomaticSize.X,
                TextColor3 = Theme.Muted,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Right,
                Parent = button,
            })
            local lastClick = 0
            button.MouseButton1Click:Connect(function()
                -- A second click on the picked row loads it.
                if selected == name and os.clock() - lastClick < 0.35 then
                    lastClick = 0
                    safeCall(onOpen, name)
                    return
                end
                lastClick = os.clock()
                pick(name)
            end)
            button.MouseEnter:Connect(function()
                if selected ~= name then
                    tween(button, { BackgroundTransparency = 0.93 }, 0.1)
                end
            end)
            button.MouseLeave:Connect(function()
                if selected ~= name then
                    tween(button, { BackgroundTransparency = 1 }, 0.15)
                end
            end)
            buttons[name] = { Button = button, Label = text, Tags = tags, Bar = bar }
        end
        if selected and not buttons[selected] then
            pick(nil)
        end
        empty.Visible = next(buttons) == nil
        paint(true)
    end
    function handle:Get()
        return selected
    end
    function handle:Set(name)
        pick(name and buttons[name] and name or nil)
    end
    function handle:Repaint()
        paint(true)
    end
    handle:Refresh(names)
    handle:Set(default)
    return finishElement(tab, { Name = "Configs" }, handle, frame, "PickList")
end

-- Managers go in their own groupbox when added straight to a tab.
local function managerHost(tab, opts, name, icon)
    if tab._groupbox then
        return tab
    end
    local host = tab:Groupbox({ Name = opts.Name or name, Icon = opts.Icon or icon, Side = opts.Side })
    -- Library chrome, not a script feature: the feature list skips it.
    host._manager = true
    return host
end

function Tab:Menu(opts)
    opts = normalize(opts, { Title = "Name" })
    local host = managerHost(self, opts, "Menu", "monitor")
    local window = self.Window

    host:Keybind({
        Name = opts.ToggleUIText or "Toggle UI",
        Default = opts.ToggleUIKeybind or window.Keybind or Enum.KeyCode.RightControl,
        Flag = opts.ToggleUIFlag or "MenuToggleUI",
        Callback = function(key)
            window:SetKeybind(key)
        end,
    })

    host:Toggle({
        Name = opts.ToggleButtonText or "Toggle Button",
        Default = opts.ToggleButtonDefault ~= false,
        Flag = opts.ToggleButtonFlag or "MenuToggleButton",
        Callback = function(state)
            if state then
                window:SetToggleButton(true)
                window:SetToggleButtonPlatform("Both")
                window:SetToggleButtonIcon(opts.ToggleButtonIcon or "bone")
            else
                window:SetToggleButton(false)
            end
        end,
    })

    local afkConn
    host:Toggle({
        Name = opts.AntiAFKText or "Anti AFK",
        Default = opts.AntiAFKDefault ~= false,
        Flag = opts.AntiAFKFlag or "MenuAntiAFK",
        Callback = function(state)
            if state then
                local VirtualUser = game:GetService("VirtualUser")
                local LocalPlayer = game:GetService("Players").LocalPlayer
                if not afkConn then
                    afkConn = LocalPlayer.Idled:Connect(function()
                        VirtualUser:CaptureController()
                        VirtualUser:ClickButton2(Vector2.zero)
                    end)
                    table.insert(window._connections, afkConn)
                end
            else
                if afkConn then
                    afkConn:Disconnect()
                    afkConn = nil
                end
            end
        end,
    })

    local execConn
    host:Toggle({
        Name = opts.AutoExecuteText or "Auto Execute",
        Default = opts.AutoExecuteDefault == true,
        Flag = opts.AutoExecuteFlag or "MenuAutoExecute",
        Callback = function(state)
            if state and not execConn then
                local qot = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
                if qot then
                    local LocalPlayer = game:GetService("Players").LocalPlayer
                    local scriptSource = opts.AutoExecuteScript or ([[loadstring(readfile("%s.luau"))()]]):format(window.Name or "script")
                    execConn = LocalPlayer.OnTeleport:Connect(function()
                        pcall(function()
                            qot(scriptSource)
                        end)
                    end)
                    table.insert(window._connections, execConn)
                end
            elseif not state and execConn then
                execConn:Disconnect()
                execConn = nil
            end
        end,
    })

    local blackScreen
    host:Toggle({
        Name = opts.Disable3DText or "Disable 3D Rendering",
        Default = opts.Disable3DDefault == true,
        Flag = opts.Disable3DFlag or "MenuDisable3D",
        Callback = function(state)
            local RunService = game:GetService("RunService")
            local gui = window.Gui
            if state then
                if not blackScreen and gui then
                    blackScreen = create("Frame", {
                        Name = "Black3DRender",
                        Size = UDim2.fromScale(1, 1),
                        Position = UDim2.fromScale(0, 0),
                        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
                        BorderSizePixel = 0,
                        ZIndex = 0,
                        Parent = gui,
                    })
                end
                if blackScreen then blackScreen.Visible = true end
                pcall(function()
                    RunService:Set3dRenderingEnabled(false)
                end)
            else
                if blackScreen then blackScreen.Visible = false end
                pcall(function()
                    RunService:Set3dRenderingEnabled(true)
                end)
            end
        end,
    })

    local reconnectConn
    host:Toggle({
        Name = opts.AutoReconnectText or "Auto Reconnect",
        Default = opts.AutoReconnectDefault ~= false,
        Flag = opts.AutoReconnectFlag or "MenuAutoReconnect",
        Callback = function(state)
            if state and not reconnectConn then
                local GuiService = game:GetService("GuiService")
                local TeleportService = game:GetService("TeleportService")
                local Players = game:GetService("Players")
                local LocalPlayer = Players.LocalPlayer
                reconnectConn = GuiService.ErrorMessageChanged:Connect(function()
                    pcall(function()
                        task.wait(0.5)
                        if #Players:GetPlayers() <= 1 then
                            TeleportService:Teleport(game.PlaceId, LocalPlayer)
                        else
                            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
                        end
                    end)
                end)
                table.insert(window._connections, reconnectConn)
            elseif not state and reconnectConn then
                reconnectConn:Disconnect()
                reconnectConn = nil
            end
        end,
    })

    host:Button({
        Name = opts.UnloadText or "Unload",
        Icon = opts.UnloadIcon or "power",
        Callback = function()
            window:Confirm({
                Title = "Unload",
                Content = opts.UnloadConfirmText or ("Are you sure you want to unload " .. (window.Name or "the script") .. "?"),
                Icon = opts.UnloadIcon or "power",
                ConfirmText = "Unload",
                Callback = function()
                    window:Destroy()
                end,
            })
        end,
    })

    return host
end

function Tab:ConfigManager(opts)
    opts = normalize(opts, { Title = "Name" })
    local host = managerHost(self, opts, "Configs", "folder")
    local window = self.Window
    local manager = {}
    local list, status, modeList

    local function notify(ok, title, detail)
        window:Notify({ Title = title, Content = detail, Type = ok and "Success" or "Error", Duration = 3 })
    end

    local autoRow
    local function refreshStatus()
        if not status then
            return
        end
        local count = #window:ListConfigs()
        local autoName = window:GetAutoload() or "none"
        local autosaveName = window._autosave and (window.LoadedConfig or "on") or "off"
        status:Set(("%d saved  ·  loaded: %s  ·  auto: %s  ·  autosave: %s"):format(count, window.LoadedConfig or "none", autoName, autosaveName))
        list:Repaint()
        if autoRow then
            local picked = list:Get()
            local isAuto = picked ~= nil and window:GetAutoload() == picked
            autoRow:SetText(1, isAuto and "Clear Autoload" or "Auto Load")
            autoRow:SetText(2, window._autosave and "Autosave: On" or "Auto Save")
        end
    end

    local function pickedName()
        local name = list:Get()
        if not name then
            notify(false, "No config selected", "Pick one from the list first")
        end
        return name
    end

    local names = window:ListConfigs()
    local initial = window.LoadedConfig or window:GetAutoload()
    local nameInput
    list = pickList(host, names, table.find(names, initial) and initial or nil, opts.Rows, function(name)
        local tags = {}
        if name == window.LoadedConfig then
            table.insert(tags, "loaded")
        end
        if name == window:GetAutoload() then
            table.insert(tags, "auto")
        end
        if window._autosave and name == (window.LoadedConfig or window.ConfigName) then
            table.insert(tags, "autosave")
        end
        return table.concat(tags, " · ")
    end, function(name)
        if nameInput then
            nameInput:Set(name or "")
        end
        refreshStatus()
    end, function(name)
        manager:Load(name)
    end)
    status = host:Label("0 saved")
    host:Label("Config Name:")
    nameInput = actionInput(host, opts.Placeholder or "Type config name here...", nil, function(text)
        manager:Create(text)
    end)
    host:ButtonRow({
        { Name = "Save", Callback = function() manager:Save() end },
        { Name = "Load", Callback = function() manager:Load() end },
    })
    host:ButtonRow({
        { Name = "Delete", Style = "Danger", Callback = function() manager:Delete() end },
        { Name = "Refresh", Callback = function() manager:Refresh() end },
    })
    autoRow = host:ButtonRow({
        { Name = "Auto Load", Callback = function() manager:ToggleAutoload() end },
        { Name = "Auto Save", Callback = function() manager:ToggleAutosave() end },
    })
    host:Divider({ Text = "more" })
    host:ButtonRow({
        { Name = "Rename", Callback = function() manager:Rename(nil, nameInput:Get()) end },
        { Name = "Reset", Style = "Danger", Callback = function() manager:Reset() end },
    })
    modeList = host:Dropdown({
        Name = "Autoload mode",
        Stacked = true,
        Options = { "All accounts", "This account" },
        Default = window:GetAutoloadMode() == "Account" and "This account" or "All accounts",
        AllowNone = false,
        Callback = function(choice)
            manager:SetAutoloadMode(choice == "This account" and "Account" or "Global")
        end,
    })
    host:Divider({ Text = "share" })
    host:Button({ Name = "Copy code", Callback = function() manager:Export() end })
    local codeInput = actionInput(host, "paste a config code...", nil, function(text)
        manager:Import(text)
    end)
    host:Button({ Name = "Import code", Callback = function() manager:Import(codeInput:Get()) end })

    function manager:Refresh()
        local names = window:ListConfigs()
        local keep = list:Get()
        list:Refresh(names, true)
        if keep and not table.find(names, keep) then
            list:Set(window.LoadedConfig and table.find(names, window.LoadedConfig) and window.LoadedConfig or nil, true)
        end
        refreshStatus()
    end

    local function select(name)
        manager:Refresh()
        list:Set(name, true)
    end

    function manager:Create(name)
        name = trim(name)
        if name == "" then
            notify(false, "Name the config", "Type a name before creating it")
            return
        end
        if not validConfigName(name) then
            notify(false, "Invalid name", 'Names cannot contain \\ / : * ? " < > |')
            return
        end
        local ok, err = window:SaveConfig(name)
        if ok then
            window.LoadedConfig = name
            nameInput:Set("")
            select(name)
        end
        notify(ok, ok and "Config created" or "Create failed", ok and name or tostring(err))
    end

    function manager:Save(name)
        local typed = trim(nameInput:Get())
        if not name and typed ~= "" and typed ~= list:Get() then
            return manager:Create(typed)
        end
        name = name or list:Get()
        if not name then
            local typed = trim(nameInput:Get())
            if typed == "" then
                notify(false, "No config selected", "Pick one from the list or type a name")
                return
            end
            return manager:Create(typed)
        end
        local ok, err = window:SaveConfig(name)
        if ok then
            window.LoadedConfig = name
            refreshStatus()
        end
        notify(ok, ok and "Config saved" or "Save failed", ok and name or tostring(err))
    end

    function manager:Load(name)
        name = name or pickedName()
        if not name then
            return
        end
        local ok, err = window:LoadConfig(name)
        refreshStatus()
        notify(ok, ok and "Config loaded" or "Load failed", ok and name or tostring(err))
    end

    function manager:Delete(name)
        name = name or pickedName()
        if not name then
            return
        end
        window:Confirm({
            Title = "Delete config",
            Content = "Remove " .. name .. "? This cannot be undone.",
            Icon = "trash-2",
            ConfirmText = "Delete",
            Callback = function()
                local ok, err = window:DeleteConfig(name)
                if ok then
                    if window:GetAutoload("Account") == name then
                        window:SetAutoload(nil, "Account")
                    end
                    if window:GetAutoload("Global") == name then
                        window:SetAutoload(nil, "Global")
                    end
                    list:Set(nil, true)
                end
                manager:Refresh()
                notify(ok, ok and "Config deleted" or "Delete failed", ok and name or tostring(err))
            end,
        })
    end

    function manager:Rename(name, newName)
        name = name or pickedName()
        if not name then
            return
        end
        newName = trim(newName)
        if newName == "" then
            notify(false, "Name the config", "Type the new name in the name box")
            return
        end
        if not validConfigName(newName) then
            notify(false, "Invalid name", 'Names cannot contain \\ / : * ? " < > |')
            return
        end
        local ok, err = window:RenameConfig(name, newName)
        if ok then
            nameInput:Set("")
            select(newName)
        end
        notify(ok, ok and "Config renamed" or "Rename failed", ok and (name .. " -> " .. newName) or tostring(err))
    end

    function manager:Reset()
        window:Confirm({
            Title = "Reset settings",
            Content = "Put every setting back to its default and delete this script's folder? Saved configs, themes and autoload are removed for good.",
            Icon = "rotate-ccw",
            ConfirmText = "Reset",
            Callback = function()
                window:ResetConfig()
                local wiped = window:ClearWorkspace()
                window:_applyDefaultTheme()
                list:Set(nil, true)
                manager:Refresh()
                modeList:Set("All accounts", true)
                notify(wiped, wiped and "Settings reset" or "Reset incomplete",
                    wiped and "Everything is back to its default" or "Some files in " .. window.ConfigFolder .. " could not be deleted")
            end,
        })
    end

    function manager:SetAutoload(name)
        name = name or pickedName()
        if not name then
            return
        end
        local ok, err = window:SetAutoload(name)
        refreshStatus()
        notify(ok, ok and "Autoload set" or "Autoload failed", ok and name or tostring(err))
    end

    function manager:ClearAutoload()
        local current = window:GetAutoload()
        if not current then
            notify(false, "No autoload", "Nothing is set to autoload")
            return
        end
        local ok, err = window:SetAutoload(nil)
        refreshStatus()
        notify(ok, ok and "Autoload cleared" or "Clear failed", ok and current or tostring(err))
    end

    function manager:ToggleAutoload(name)
        name = name or pickedName()
        if not name then
            return
        end
        if window:GetAutoload() == name then
            manager:ClearAutoload()
        else
            manager:SetAutoload(name)
        end
    end

    function manager:ToggleAutosave()
        local name = list:Get() or window.LoadedConfig or window.ConfigName
        if not name then
            notify(false, "No config selected", "Pick or create a config first")
            return
        end
        window._autosave = not window._autosave
        if window._autosave then
            window.LoadedConfig = name
            local ok, err = window:SaveConfig(name)
            notify(ok, ok and "Autosave enabled" or "Autosave error", ok and ("Auto-saving to " .. name) or tostring(err))
        else
            notify(true, "Autosave disabled", "Autosave turned off")
        end
        refreshStatus()
    end

    function manager:SetAutoloadMode(mode)
        local ok, err = window:SetAutoloadMode(mode)
        local label_ = mode == "Account" and "This account" or "All accounts"
        if modeList:Get() ~= label_ then
            modeList:Set(label_, true)
        end
        notify(ok ~= false, ok ~= false and "Autoload mode" or "Mode change failed", ok ~= false and label_ or tostring(err))
    end

    function manager:Export(name)
        local code, err = window:ExportConfig(name)
        if not code then
            notify(false, "Export failed", tostring(err))
            return nil
        end
        window:CopyToClipboard(code, "Config code")
        return code
    end

    function manager:Import(code)
        code = trim(code)
        if code == "" then
            notify(false, "Nothing to import", "Paste a config code first")
            return
        end
        local data, info = window:DecodeConfig(code)
        if not data then
            notify(false, "Import failed", "Invalid config code")
            return
        end
        -- The typed name wins; otherwise the code's own name, never overwriting a config.
        local saveAs = trim(nameInput:Get())
        if saveAs == "" then
            saveAs = nil
            if validConfigName(info.Name) then
                saveAs = info.Name
                local index = 2
                while window:ConfigExists(saveAs) do
                    saveAs = ("%s (%d)"):format(info.Name, index)
                    index += 1
                end
            end
        elseif not validConfigName(saveAs) then
            notify(false, "Invalid name", 'Names cannot contain \\ / : * ? " < > |')
            return
        end
        local function run()
            local ok, err = window:ImportConfig(code, saveAs, true)
            if ok then
                codeInput:Set("")
                if saveAs then
                    nameInput:Set("")
                    select(saveAs)
                end
            end
            notify(ok, ok and "Config imported" or "Import failed", ok and (saveAs or "Applied to current settings") or tostring(err))
        end
        if info.Folder and info.Folder ~= window.ConfigFolder then
            window:Confirm({
                Title = "Different script",
                Content = ("This config was made for %s. Import it anyway? Only matching settings are applied."):format(info.Folder),
                Icon = "triangle-alert",
                ConfirmText = "Import",
                Callback = run,
            })
            return
        end
        run()
    end

    local disconnect = window:OnConfigChanged(function()
        -- Configs can arrive from elsewhere (a cloud install), so the list is reread.
        manager:Refresh()
        if window.LoadedConfig and list:Get() == nil then
            list:Set(window.LoadedConfig, true)
        end
    end)
    status._listeners = status._listeners or {}
    table.insert(status._listeners, disconnect)

    refreshStatus()
    return manager
end

local PRESET_ORDER = {
    "Midnight", "Nebula", "Synthwave", "Velvet", "Rose", "Crimson", "Sunset", "Amber", "Gold",
    "Cyber", "Toxic", "Matcha", "Emerald", "Aurora", "Ocean", "Frost", "Abyss", "Mono", "BBC",
    "Halloween", "Haunted", "Christmas", "Valentine", "Lunar", "Tropical", "Dracula", "Coffee",
}

local function presetNames()
    local names, seen = {}, {}
    for _, name in ipairs(PRESET_ORDER) do
        if Library.ThemePresets[name] then
            table.insert(names, name)
            seen[name] = true
        end
    end
    local extra = {}
    for name in pairs(Library.ThemePresets) do
        if not seen[name] then
            table.insert(extra, name)
        end
    end
    table.sort(extra)
    for _, name in ipairs(extra) do
        table.insert(names, name)
    end
    return names
end

function Tab:ThemeManager(opts)
    opts = normalize(opts, { Title = "Name" })
    local host = managerHost(self, opts, "Themes", "palette")
    local window = self.Window
    local manager = {}
    local themes, status, defaultRow, presets
    local dim, transparent, dragSkeleton, islandStyle
    local background, backgroundInput, backgroundOpacity, backgroundLabel
    local uiScale, density, adaptive, cornerRadius

    local function notify(ok, title, detail)
        window:Notify({ Title = title, Content = detail, Type = ok and "Success" or "Error", Duration = 3 })
    end

    local function refreshStatus()
        local current = window:GetDefaultTheme()
        status:Set("Default theme: " .. (current or "none"))
        local picked = themes:Get() or presets:Get()
        defaultRow:SetText(2, (picked and picked == current) and "Clear Default" or "Set Default")
    end

    local function pickedTheme()
        local name = themes:Get()
        if not name then
            notify(false, "No theme selected", "Pick one from the list first")
        end
        return name
    end

    presets = host:Dropdown({
        Name = "Preset",
        Options = presetNames(),
        Default = Library.ThemePresets[Library.ThemeName or ""] and Library.ThemeName or nil,
        NoneText = "custom",
        AllowNone = false,
        Callback = function(name)
            if name then
                Library:SetTheme(name)
                themes:Set(nil, true)
                refreshStatus()
            end
        end,
    })
    if opts.AccentGradient ~= false then
        host:Toggle({
            Name = "Accent Gradient",
            Default = Library.AccentGradient,
            Callback = function(value)
                window:SetAccentGradient(value)
            end,
        })
    end
    if opts.AccentAngle ~= false then
        host:Slider({
            Name = "Accent Angle",
            Min = 0,
            Max = 360,
            Increment = 5,
            Default = Library.AccentAngle or 360,
            Suffix = "°",
            Callback = function(value)
                window:SetAccentAngle(value)
            end,
        })
    end
    if opts.Shimmer ~= false then
        host:Toggle({
            Name = "Shimmer",
            Default = Library.Shimmer,
            Callback = function(value)
                window:SetShimmer(value)
            end,
        })
    end
    if window._backdrop and opts.Dim ~= false then
        dim = host:Toggle({
            Name = "Dim",
            Default = window._backdropDim,
            Callback = function(value)
                window:SetDim(value)
            end,
        })
    end
    if opts.Transparent ~= false then
        transparent = host:Toggle({
            Name = "Transparent",
            Default = window.Transparent == true,
            Callback = function(value)
                window:SetTransparent(value)
            end,
        })
    end
    if opts.DragSkeleton ~= false and opts.DragStyle ~= false then
        dragSkeleton = host:Dropdown({
            Name = "Drag Style",
            Options = Library.DragStyles,
            Default = window.DragStyle,
            AllowNone = false,
            Callback = function(style)
                if style then
                    window:SetDragStyle(style)
                end
            end,
        })
    end
    if opts.IslandStyle ~= false then
        islandStyle = host:Dropdown({
            Name = "Dynamic Island",
            Options = Library.IslandStyles,
            Default = window.IslandStyle,
            AllowNone = false,
            Callback = function(style)
                if style then
                    window:SetIslandStyle(style)
                end
            end,
        })
    end
    if opts.AdaptiveSize ~= false then
        adaptive = host:Toggle({
            Name = "Adaptive Size",
            Default = window:GetAdaptiveSize(),
            Callback = function(value)
                window:SetAdaptiveSize(value)
            end,
        })
    end
    if opts.Scale ~= false then
        uiScale = host:Slider({
            Name = "UI Scale",
            Min = 60,
            Max = 150,
            Increment = 5,
            Default = math.floor(window:GetUIScale() * 100 + 0.5),
            Suffix = "%",
            -- Rescaling mid-drag would move the slider out from under the
            -- pointer, so a drag applies on release.
            Callback = function(value)
                if not (uiScale and uiScale.Dragging) then
                    window:SetUIScale(value / 100)
                end
            end,
            OnRelease = function(value)
                window:SetUIScale(value / 100)
            end,
        })
    end
    if opts.Density ~= false then
        density = host:Dropdown({
            Name = "Density",
            Options = { "Compact", "Default", "Comfortable" },
            Default = Library.Density,
            AllowNone = false,
            Callback = function(mode)
                if mode then
                    Library:SetDensity(mode)
                end
            end,
        })
    end
    if opts.CornerRadius ~= false then
        cornerRadius = host:Slider({
            Name = "Corner Radius",
            Min = 0,
            Max = 20,
            Increment = 1,
            Default = Library:GetCornerRadius(),
            Suffix = "px",
            Callback = function(value)
                Library:SetCornerRadius(value)
            end,
        })
    end
    if opts.Background ~= false then
        -- The dropdown shows listed images by name, "custom" for ids and links.
        backgroundLabel = function(source)
            if source == nil or source == "" then
                return "None"
            end
            return table.find(window:ListBackgrounds(), source) and source or nil
        end
        local function applyBackground(source, fromList)
            task.spawn(function()
                local ok, err = window:SetBackground(source)
                if ok and not fromList then
                    background:Set(backgroundLabel(window.Background), true)
                elseif not ok and err ~= "replaced by a newer background" then
                    notify(false, "Background failed", tostring(err))
                end
            end)
        end
        local options = window:ListBackgrounds()
        table.insert(options, 1, "None")
        background = host:Dropdown({
            Name = "Background",
            Options = options,
            Default = backgroundLabel(window.Background),
            NoneText = "custom",
            AllowNone = false,
            Callback = function(name)
                if name then
                    applyBackground(name, true)
                end
            end,
        })
        backgroundInput = actionInput(host, "image id or url", "Set", function(text)
            text = trim(text)
            if text == "" then
                notify(false, "No image", "Paste an image id or link first")
                return
            end
            applyBackground(text)
        end)
        backgroundOpacity = host:Slider({
            Name = "Background Opacity",
            Min = 0,
            Max = 100,
            Default = math.floor((1 - window.BackgroundTransparency) * 100 + 0.5),
            Suffix = "%",
            Callback = function(value)
                window:SetBackgroundTransparency(1 - value / 100)
            end,
        })
    end
    local nameInput = actionInput(host, opts.Placeholder or "theme name", "Create", function(text)
        manager:Create(text)
    end)
    themes = host:Dropdown({
        Name = "Theme",
        Options = window:ListThemes(),
        Default = (function()
            local current = window:GetDefaultTheme()
            return current and not Library.ThemePresets[current] and current or nil
        end)(),
        EmptyText = "no themes",
        NoneText = "select",
        Callback = function()
            refreshStatus()
        end,
    })
    host:ButtonRow({
        { Name = "Save", Callback = function() manager:Save() end },
        { Name = "Load", Callback = function() manager:Load() end },
    })
    defaultRow = host:ButtonRow({
        { Name = "Delete", Callback = function() manager:Delete() end },
        { Name = "Set Default", Callback = function() manager:ToggleDefault() end },
    })
    status = host:Label("Default theme: none")

    function manager:Refresh()
        themes:Refresh(window:ListThemes(), true)
        if background then
            local options = window:ListBackgrounds()
            table.insert(options, 1, "None")
            background:Refresh(options, true, true)
        end
        refreshStatus()
    end

    function manager:Create(name)
        name = trim(name)
        if name == "" then
            notify(false, "Name the theme", "Type a name before creating it")
            return
        end
        if Library.ThemePresets[name] then
            notify(false, "Name taken", name .. " is a built-in preset")
            return
        end
        local ok, err = window:SaveTheme(name)
        manager:Refresh()
        if ok then
            themes:Set(name, true)
            nameInput:Set("")
            refreshStatus()
        end
        notify(ok, ok and "Theme created" or "Create failed", ok and name or tostring(err))
    end

    function manager:Save(name)
        name = name or pickedTheme()
        if not name then
            return
        end
        local ok, err = window:SaveTheme(name)
        notify(ok, ok and "Theme saved" or "Save failed", ok and name or tostring(err))
    end

    function manager:Load(name)
        name = name or pickedTheme()
        if not name then
            return
        end
        local ok, err = window:LoadTheme(name)
        if ok then
            presets:Set(nil, true)
        end
        notify(ok ~= false, ok and "Theme loaded" or "Load failed", ok and name or tostring(err))
    end

    function manager:Delete(name)
        name = name or pickedTheme()
        if not name then
            return
        end
        window:Confirm({
            Title = "Delete theme",
            Content = "Remove " .. name .. "? This cannot be undone.",
            Icon = "trash-2",
            ConfirmText = "Delete",
            Callback = function()
                local ok, err = window:DeleteTheme(name)
                manager:Refresh()
                notify(ok, ok and "Theme deleted" or "Delete failed", ok and name or tostring(err))
            end,
        })
    end

    function manager:ToggleDefault(name)
        name = name or themes:Get() or presets:Get()
        if not name then
            notify(false, "Nothing selected", "Pick a theme or a preset first")
            return
        end
        local clearing = window:GetDefaultTheme() == name
        local ok, err = window:SetDefaultTheme(not clearing and name or nil)
        refreshStatus()
        notify(ok ~= false, clearing and "Default cleared" or "Default theme set", ok ~= false and name or tostring(err))
    end

    if opts.Customize ~= false then
        host:Divider()
        local fields = opts.Colors or {
            { "Accent", "Accent" },
            { "Accent2", "Accent 2" },
            { "Background", "Background" },
            { "Surface2", "Surface" },
            { "CardHeader", "Card Header" },
            { "Outline", "Card Outline" },
            { "TabStructure", "Tab Structure" },
            { "Text", "Text" },
            { "Muted", "Muted text" },
        }
        for _, field in ipairs(fields) do
            local key, title = field[1], field[2] or field[1]
            local pending, scheduled = nil, false
            local picker
            picker = host:ColorPicker({
                Name = title,
                Default = Theme[key],
                Callback = function(color)
                    -- Dragging the picker fires every frame; repaint at most
                    -- a dozen times a second.
                    pending = color
                    if scheduled then
                        return
                    end
                    scheduled = true
                    task.delay(0.08, function()
                        scheduled = false
                        Library:SetTheme({ [key] = pending }, true)
                        presets:Set(nil, true)
                    end)
                end,
            })
            table.insert(Library._themeListeners, function()
                if picker.Value ~= Theme[key] then
                    picker:Set(Theme[key], true)
                end
            end)
        end
    end

    -- One hidden flag carries the palette and the look settings above, so
    -- configs save and load the theme. Not a flag per toggle: flagged toggles
    -- would count as running features on the minimized island.
    if opts.Flag ~= false then
        local flag = type(opts.Flag) == "string" and opts.Flag or "__Theme"
        local look = { _type = "Theme", _searchName = "Theme", _searchKey = "theme", _listeners = {} }

        function look:Get()
            local colors = {}
            for _, key in ipairs(THEME_KEYS) do
                colors[key] = colorToHex(Theme[key])
            end
            return {
                Name = presets:Get() or themes:Get(),
                Colors = colors,
                -- if-expressions, not and/or: a switched-off value is false, not nil.
                Dim = if dim then window._backdropDim == true else nil,
                Transparent = if transparent then window.Transparent == true else nil,
                DragStyle = dragSkeleton and window.DragStyle or nil,
                IslandStyle = islandStyle and window.IslandStyle or nil,
                CornerRadius = cornerRadius and Library:GetCornerRadius() or nil,
                UIScale = uiScale and window:GetUIScale() or nil,
                AdaptiveSize = if adaptive then window:GetAdaptiveSize() else nil,
                Density = density and Library.Density or nil,
                -- "" is no background; a missing field leaves it alone on load.
                Background = background and (window.Background or "") or nil,
                BackgroundTransparency = background and window.BackgroundTransparency or nil,
            }
        end

        function look:Set(value)
            if type(value) ~= "table" then
                return
            end
            if type(value.Colors) == "table" then
                Library:SetTheme(value.Colors)
            end
            local name = type(value.Name) == "string" and value.Name or nil
            if name and Library.ThemePresets[name] then
                Library.ThemeName = name
                presets:Set(name, true)
                themes:Set(nil, true)
            else
                if name then
                    Library.ThemeName = name
                end
                presets:Set(nil, true)
                themes:Set(name and table.find(window:ListThemes(), name) and name or nil, true)
            end
            if dim and type(value.Dim) == "boolean" then
                window:SetDim(value.Dim)
                dim:Set(value.Dim, true)
            end
            if transparent and type(value.Transparent) == "boolean" then
                window:SetTransparent(value.Transparent)
                transparent:Set(value.Transparent, true)
            end
            if dragSkeleton and type(value.DragStyle) == "string" then
                dragSkeleton:Set(window:SetDragStyle(value.DragStyle), true)
            elseif dragSkeleton and type(value.DragSkeleton) == "boolean" then
                -- Configs saved before drag styles.
                window:SetDragSkeleton(value.DragSkeleton)
                dragSkeleton:Set(window.DragStyle, true)
            end
            if islandStyle and type(value.IslandStyle) == "string" then
                islandStyle:Set(window:SetIslandStyle(value.IslandStyle), true)
            end
            if cornerRadius and tonumber(value.CornerRadius) then
                cornerRadius:Set(Library:SetCornerRadius(value.CornerRadius), true)
            end
            if adaptive and type(value.AdaptiveSize) == "boolean" then
                window:SetAdaptiveSize(value.AdaptiveSize)
                adaptive:Set(value.AdaptiveSize, true)
            end
            if uiScale and tonumber(value.UIScale) then
                window:SetUIScale(tonumber(value.UIScale))
                uiScale:Set(math.floor(window:GetUIScale() * 100 + 0.5), true)
            end
            if density and type(value.Density) == "string" then
                density:Set(Library:SetDensity(value.Density), true)
            end
            if background and tonumber(value.BackgroundTransparency) then
                window:SetBackgroundTransparency(tonumber(value.BackgroundTransparency))
                backgroundOpacity:Set(math.floor((1 - window.BackgroundTransparency) * 100 + 0.5), true)
            end
            if background and type(value.Background) == "string" and value.Background ~= (window.Background or "") then
                local source = value.Background
                background:Set(backgroundLabel(source), true)
                -- A web image may download first; don't hold up the rest of the config.
                task.spawn(window.SetBackground, window, source)
            end
            refreshStatus()
        end

        Library.Flags[flag] = look
        window:_flagCreated(flag, look)
    end

    -- A reset wipes the themes folder, so drop the stale list.
    window._workspaceListeners = window._workspaceListeners or {}
    table.insert(window._workspaceListeners, function()
        themes:Set(nil, true)
        manager:Refresh()
    end)

    refreshStatus()
    return manager
end

Tab.CreateButtonRow = Tab.ButtonRow
Tab.CreateConfigManager = Tab.ConfigManager
Tab.CreateThemeManager = Tab.ThemeManager
Tab.CreateMenu = Tab.Menu
Tab.CreateMenuManager = Tab.Menu
Tab.MenuManager = Tab.Menu

function Tab:Settings(opts)
    opts = type(opts) == "table" and opts or {}
    local menuHost
    if opts.Menu ~= false then
        menuHost = self:Menu(type(opts.Menu) == "table" and opts.Menu or { Side = "Left" })
    end
    local configHost
    if opts.Configs ~= false then
        configHost = self:ConfigManager(type(opts.Configs) == "table" and opts.Configs or { Side = "Left" })
    end
    local themeHost
    if opts.Themes ~= false then
        themeHost = self:ThemeManager(type(opts.Themes) == "table" and opts.Themes or { Side = "Right" })
    end
    return menuHost, configHost, themeHost
end
Tab.CreateSettings = Tab.Settings

-- Status: read-only key/value lines, mostly for groupboxes, in several styles.

local STATUS_HEIGHT = { Plain = 22, Row = 24, Badge = 28, Dot = 24, Bar = 38, Stat = 46 }

-- Tone: a theme key, a Color3 or "#rrggbb".
local function toneColor(tone)
    return Library._color(tone) or Theme.Accent
end

local function formatNumber(value)
    if value == math.floor(value) then
        return tostring(math.floor(value))
    end
    return string.format("%.1f", value)
end

local function parseFraction(value, max)
    if type(value) == "number" and type(max) == "number" then
        return value, max
    end
    if type(value) == "string" then
        local cleaned = (value:gsub(",", ""))
        local current, total = cleaned:match("^%s*(%-?[%d%.]+)%s*/%s*(%-?[%d%.]+)")
        if current then
            return tonumber(current), tonumber(total)
        end
    end
    return nil, nil
end

function Tab:Status(opts)
    opts = normalize(opts, { Title = "Name", Text = "Value", Content = "Value", CurrentValue = "Value", Default = "Value" })
    local style = STATUS_HEIGHT[opts.Style] and opts.Style or "Plain"
    local compact = metricsOf(self).Compact
    local window = self.Window
    local height = STATUS_HEIGHT[style]
    local pad = compact and 0 or 8
    local frame = card(self, "Frame", height + pad * 2, opts)
    local holder = create("Frame", {
        Position = UDim2.fromOffset(14, pad),
        Size = UDim2.new(1, -28, 0, height),
        BackgroundTransparency = 1,
        Parent = frame,
    })

    local handle = { Value = opts.Value, Max = opts.Max, Tone = opts.Tone or "Accent", Name = opts.Name or "", Color = opts.Color or opts.ValueColor }
    local keyLabel, valueLabel, chip, chipStroke, dot, pulse, fill
    local tinted = false

    local function keyText()
        return style == "Plain" and (handle.Name .. ":") or handle.Name
    end

    if style == "Plain" then
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 5),
            Parent = holder,
        })
        keyLabel = label({
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = 1,
            Parent = holder,
        })
        valueLabel = label({
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            TextSize = 12,
            TextColor3 = Theme.Text,
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = 2,
            Parent = holder,
        })
    elseif style == "Stat" then
        keyLabel = label({
            Position = UDim2.fromOffset(0, 3),
            Size = UDim2.new(1, 0, 0, 14),
            TextSize = 11,
            TextColor3 = Theme.Muted,
            Parent = holder,
        })
        valueLabel = label({
            Position = UDim2.fromOffset(0, 18),
            Size = UDim2.new(1, 0, 0, 24),
            TextSize = 20,
            FontFace = Fonts.Bold,
            TextColor3 = Theme.Text,
            Parent = holder,
        })
    else
        local keyX = 0
        if style == "Dot" then
            keyX = 18
            pulse = create("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0, 5, 0.5, 0),
                Size = UDim2.fromOffset(8, 8),
                BackgroundColor3 = toneColor(handle.Tone),
                BackgroundTransparency = 0.4,
                BorderSizePixel = 0,
                Parent = holder,
            })
            corner(pulse, UDim.new(1, 0))
            dot = create("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0, 5, 0.5, 0),
                Size = UDim2.fromOffset(8, 8),
                BackgroundColor3 = toneColor(handle.Tone),
                BorderSizePixel = 0,
                Parent = holder,
            })
            corner(dot, UDim.new(1, 0))
            if opts.Pulse ~= false then
                TweenService:Create(pulse, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1), {
                    Size = UDim2.fromOffset(20, 20),
                    BackgroundTransparency = 1,
                }):Play()
            else
                pulse.Visible = false
            end
        end
        local rowHeight = style == "Bar" and 18 or height
        keyLabel = label({
            Position = UDim2.fromOffset(keyX, 0),
            Size = UDim2.new(0.55, -keyX, 0, rowHeight),
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            Parent = holder,
        })
        if style == "Badge" then
            tinted = true
            chip = create("Frame", {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, 0, 0.5, 0),
                Size = UDim2.fromOffset(0, 22),
                AutomaticSize = Enum.AutomaticSize.X,
                BackgroundColor3 = toneColor(handle.Tone),
                BackgroundTransparency = 0.86,
                BorderSizePixel = 0,
                Parent = holder,
            })
            corner(chip, UDim.new(1, 0))
            chipStroke = stroke(chip, toneColor(handle.Tone), 0.6)
            padding(chip, 10, 10)
            valueLabel = label({
                Size = UDim2.new(0, 0, 1, 0),
                AutomaticSize = Enum.AutomaticSize.X,
                TextSize = 12,
                TextColor3 = toneColor(handle.Tone),
                TextTruncate = Enum.TextTruncate.None,
                Parent = chip,
            })
        else
            valueLabel = label({
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, 0, 0, 0),
                Size = UDim2.new(0.45, 0, 0, rowHeight),
                TextSize = 12,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Right,
                Parent = holder,
            })
        end
        if style == "Bar" then
            local track = create("Frame", {
                Position = UDim2.fromOffset(0, 25),
                Size = UDim2.new(1, 0, 0, 5),
                BackgroundColor3 = Theme.Surface3,
                BorderSizePixel = 0,
                ClipsDescendants = true,
                Parent = holder,
            })
            corner(track, UDim.new(1, 0))
            fill = create("Frame", {
                Size = UDim2.new(0, 0, 1, 0),
                BackgroundColor3 = toneColor(handle.Tone),
                BorderSizePixel = 0,
                Parent = track,
            })
            corner(fill, UDim.new(1, 0))
        end
    end

    local lastText = nil
    local function render(animate)
        keyLabel.Text = Library._rich(keyText())
        local value = handle.Value
        local text = value == nil and (opts.Placeholder or "-") or tostring(value)
        if style == "Bar" then
            local current, total = parseFraction(value, handle.Max)
            if current and total then
                handle.Max = total
                text = formatNumber(current) .. " / " .. formatNumber(total)
                local fraction = total > 0 and math.clamp(current / total, 0, 1) or 0
                tween(fill, { Size = UDim2.new(fraction, 0, 1, 0) }, animate and 0.4 or 0, Enum.EasingStyle.Quint)
            elseif type(value) == "number" and value <= 1 then
                text = string.format("%d%%", math.floor(value * 100 + 0.5))
                tween(fill, { Size = UDim2.new(math.clamp(value, 0, 1), 0, 1, 0) }, animate and 0.4 or 0, Enum.EasingStyle.Quint)
            end
        end
        text = Library._rich((opts.Prefix or "") .. text .. (opts.Suffix or ""))
        local changed = lastText ~= nil and text ~= lastText
        lastText = text
        valueLabel.Text = text
        local tone = toneColor(handle.Tone)
        local duration = animate and 0.25 or 0
        -- Color paints the whole value; inline tags still win over it.
        local valueColor = not tinted and Library._color(handle.Color) or Theme.Text
        if not tinted and not (changed and animate and opts.Flash ~= false) then
            tween(valueLabel, { TextColor3 = valueColor }, duration)
        end
        if chip then
            tween(chip, { BackgroundColor3 = tone }, duration)
            tween(chipStroke, { Color = tone }, duration)
            tween(valueLabel, { TextColor3 = tone }, duration)
        end
        if dot then
            tween(dot, { BackgroundColor3 = tone }, duration)
            tween(pulse, { BackgroundColor3 = tone }, 0)
        end
        if fill then
            tween(fill, { BackgroundColor3 = tone }, duration)
        end
        -- A brief accent flash marks a changed value.
        if changed and animate and not tinted and opts.Flash ~= false then
            tween(valueLabel, { TextColor3 = Theme.Accent }, 0.08)
            task.delay(0.1, function()
                if valueLabel.Parent then
                    tween(valueLabel, { TextColor3 = Library._color(handle.Color) or Theme.Text }, 0.45)
                end
            end)
        end
    end

    keyLabel.RichText = true
    valueLabel.RichText = true
    -- Theme tags in the text are baked to colours, so repaint on theme change.
    onTheme(holder, function()
        if lastText ~= nil then
            render(false)
        end
    end)

    function handle:Set(value, max)
        handle.Value = value
        if max ~= nil then
            handle.Max = max
        end
        render(true)
    end
    function handle:Get()
        return handle.Value
    end
    function handle:SetTone(tone)
        handle.Tone = tone
        render(true)
    end
    -- nil goes back to the normal text colour.
    function handle:SetColor(color)
        handle.Color = color
        render(true)
    end
    function handle:SetName(name)
        handle.Name = tostring(name)
        render(false)
    end
    function handle:Text()
        return valueLabel.Text
    end
    -- The value's resting colour, for the copy pinned on the minimized island.
    function handle._shownColor()
        if handle.Color ~= nil then
            return Library._color(handle.Color) or Theme.Text
        end
        if style == "Badge" or style == "Dot" or style == "Bar" then
            return toneColor(handle.Tone)
        end
        return Theme.Text
    end

    handle._listeners = {}
    if type(opts.Update) == "function" then
        local rate = math.max(tonumber(opts.UpdateRate) or 1, 0.05)
        local running = true
        table.insert(handle._listeners, function()
            running = false
        end)
        task.spawn(function()
            while running and frame.Parent do
                local ok, value, extra = isolatedCall(opts.Update)
                if ok then
                    if value ~= nil then
                        handle.Value = value
                    end
                    if type(extra) == "number" then
                        handle.Max = extra
                    elseif type(extra) == "string" or typeof(extra) == "Color3" then
                        handle.Tone = extra
                    end
                    render(true)
                else
                    warn("[RealIggyLib] status update error: " .. tostring(value))
                end
                task.wait(rate)
            end
        end)
        function handle:SetUpdateRate(seconds)
            rate = math.max(tonumber(seconds) or rate, 0.05)
        end
    end
    if opts.Pin then
        table.insert(window._pinned, handle)
        table.insert(handle._listeners, function()
            local index = table.find(window._pinned, handle)
            if index then
                table.remove(window._pinned, index)
            end
        end)
    end

    render(false)
    return finishElement(self, opts, handle, frame, "Status")
end

function Tab:Statuses(entries, shared)
    local handles = {}
    for index, entry in ipairs(entries or {}) do
        local entryOpts = type(entry) == "table" and table.clone(entry) or { Name = tostring(entry) }
        for key, value in pairs(shared or {}) do
            if entryOpts[key] == nil then
                entryOpts[key] = value
            end
        end
        local handle = self:Status(entryOpts)
        handles[entryOpts.Name or entryOpts.Title or index] = handle
    end
    return handles
end

-- Status list: a read-only block of rows that grows up to MaxRows, then
-- scrolls inside itself. Rows are reused between refreshes so nothing flickers.
function Tab:StatusList(opts)
    opts = normalize(opts, { Title = "Name" })
    local compact = metricsOf(self).Compact
    local window = self.Window
    local maxRows = math.max(math.floor(tonumber(opts.MaxRows) or 5), 1)
    local frame = card(self, "Frame", 0, opts)
    frame.AutomaticSize = Enum.AutomaticSize.Y
    if compact then
        padding(frame, 14, 14, 6, 8)
    else
        padding(frame, 14, 14, 11, 12)
    end
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
        Parent = frame,
    })
    local heading = label({
        Size = UDim2.new(1, 0, 0, 16),
        Text = string.upper(tostring(opts.Name or "")),
        TextSize = 11,
        TextColor3 = Theme.Muted,
        Visible = tostring(opts.Name or "") ~= "",
        LayoutOrder = 1,
        Parent = frame,
    })
    local scroller = create("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0.4,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        ScrollingEnabled = false,
        LayoutOrder = 2,
        Parent = frame,
    })
    scroller:SetAttribute("NoDrag", true)
    local content = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = scroller,
    })
    local contentPadding = padding(content, 0, 0, 0, 0)
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = content,
    })
    local empty = label({
        Size = UDim2.new(1, 0, 0, 24),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = tostring(opts.EmptyText or "Nothing yet"),
        TextSize = 13,
        LineHeight = 1.1,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 0,
        Parent = content,
    })

    local rowObjects, rows, signature, raw = {}, {}, nil, {}
    local handle = { _listeners = {} }

    -- Fits the list to its first MaxRows rows, measured, so wrapped rows count
    -- at their real height. Past MaxRows the list scrolls.
    local function fit()
        if handle._destroyed then
            return
        end
        local scale = window.Scale.Scale
        local count = #rows
        local height = 0
        if count == 0 then
            height = empty.AbsoluteSize.Y / scale
        else
            local shown = math.min(count, maxRows)
            for index = 1, shown do
                height += rowObjects[index].Frame.AbsoluteSize.Y / scale
            end
            height += (shown - 1) * 2
        end
        height = math.ceil(height)
        local scrolling = count > maxRows
        scroller.ScrollingEnabled = scrolling
        contentPadding.PaddingRight = UDim.new(0, scrolling and 8 or 0)
        if scroller.Size.Y.Offset ~= height then
            scroller.Size = UDim2.new(1, 0, 0, height)
        end
        local maxScroll = math.max(scroller.AbsoluteCanvasSize.Y - scroller.AbsoluteWindowSize.Y, 0) / scale
        if scroller.CanvasPosition.Y > maxScroll then
            scroller.CanvasPosition = Vector2.new(0, maxScroll)
        end
    end

    local function fitText(row)
        if row.Value.Visible then
            row.Text.Size = UDim2.new(1, -(math.ceil(row.Value.AbsoluteSize.X / window.Scale.Scale) + 12), 0, 24)
        else
            row.Text.Size = UDim2.new(1, 0, 0, 24)
        end
    end

    local function newRow(order)
        local holder = create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            LayoutOrder = order,
            Parent = content,
        })
        local row = {
            Frame = holder,
            Text = label({
                Size = UDim2.new(1, 0, 0, 24),
                AutomaticSize = Enum.AutomaticSize.Y,
                Text = "",
                TextSize = 13,
                LineHeight = 1.1,
                FontFace = Fonts.Regular,
                TextColor3 = Theme.Muted,
                TextWrapped = true,
                TextTruncate = Enum.TextTruncate.None,
                RichText = true,
                Parent = holder,
            }),
            Value = label({
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, 0, 0, 0),
                Size = UDim2.new(0, 0, 0, 24),
                AutomaticSize = Enum.AutomaticSize.X,
                Text = "",
                TextSize = 12,
                FontFace = Fonts.Medium,
                TextColor3 = Theme.Text,
                RichText = true,
                TextXAlignment = Enum.TextXAlignment.Right,
                TextTruncate = Enum.TextTruncate.None,
                Visible = false,
                Parent = holder,
            }),
        }
        row.Connections = {
            holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit),
            row.Value:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
                fitText(row)
            end),
        }
        return row
    end

    local function normalizeRow(entry)
        if type(entry) == "table" then
            local text = entry.Text or entry.Name or entry[1]
            local tone = entry.Tone or entry.Color
            return {
                Text = tostring(text == nil and "" or text),
                Value = entry.Value ~= nil and tostring(entry.Value) or nil,
                Tone = (type(tone) == "string" or typeof(tone) == "Color3") and tone or nil,
            }
        end
        return { Text = tostring(entry) }
    end

    local function rowKey(entry)
        return entry.Text .. "\0" .. (entry.Value or "\1") .. "\0" .. tostring(entry.Tone or "")
    end

    -- Tone tints the value, or the text when there is no value.
    local function paint(row, entry)
        local key = rowKey(entry)
        if row.Key == key then
            return
        end
        row.Key = key
        row.Text.Text = Library._rich(entry.Text)
        local tone = entry.Tone and Library._color(entry.Tone) or nil
        if entry.Value then
            row.Value.Text = Library._rich(entry.Value)
            row.Value.Visible = true
            tween(row.Value, { TextColor3 = tone or Theme.Text }, 0)
            tween(row.Text, { TextColor3 = Theme.Muted }, 0)
        else
            row.Value.Visible = false
            tween(row.Text, { TextColor3 = tone or Theme.Muted }, 0)
        end
        fitText(row)
    end

    local function dropRow(row)
        for _, connection in ipairs(row.Connections) do
            connection:Disconnect()
        end
        row.Frame:Destroy()
    end

    function handle:Set(list)
        if type(list) ~= "table" or handle._destroyed then
            return
        end
        local nextRows, keys = {}, {}
        raw = {}
        for index, entry in ipairs(list) do
            raw[index] = type(entry) == "table" and table.clone(entry) or entry
            local row = normalizeRow(entry)
            nextRows[index] = row
            keys[index] = rowKey(row)
        end
        local nextSignature = table.concat(keys, "\2") .. "#" .. #nextRows
        if nextSignature == signature then
            return
        end
        signature = nextSignature
        rows = nextRows
        for index, entry in ipairs(rows) do
            local row = rowObjects[index]
            if not row then
                row = newRow(index)
                rowObjects[index] = row
            end
            paint(row, entry)
        end
        for index = #rowObjects, #rows + 1, -1 do
            dropRow(rowObjects[index])
            rowObjects[index] = nil
        end
        empty.Visible = #rows == 0
        fit()
    end
    function handle:Get()
        local copy = {}
        for index, entry in ipairs(raw) do
            copy[index] = type(entry) == "table" and table.clone(entry) or entry
        end
        return copy
    end
    function handle:Clear()
        handle:Set({})
    end
    function handle:SetName(text)
        text = tostring(text or "")
        heading.Text = string.upper(text)
        heading.Visible = text ~= ""
        handle._searchName = text
        handle._searchKey = string.lower(text)
    end
    local rate = math.max(tonumber(opts.UpdateRate) or 1, 0.05)
    function handle:SetUpdateRate(seconds)
        rate = math.max(tonumber(seconds) or rate, 0.05)
    end

    -- Theme tags are baked into the text, so a theme change repaints the rows.
    onTheme(content, function()
        for index, row in ipairs(rowObjects) do
            if rows[index] then
                row.Key = nil
                paint(row, rows[index])
            end
        end
    end)

    local emptyConnection = empty:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
    table.insert(handle._listeners, function()
        handle._destroyed = true
        emptyConnection:Disconnect()
        for _, row in ipairs(rowObjects) do
            for _, connection in ipairs(row.Connections) do
                connection:Disconnect()
            end
        end
    end)

    -- Refreshes only while someone can see it: window open and not minimized,
    -- its tab and sub tab showing, and neither it nor its groupbox hidden.
    local function onScreen()
        if window._destroyed or not window.Open or window.Minimized or not handle._userVisible then
            return false
        end
        local page = self
        if page._groupbox then
            if page._userVisible == false then
                return false
            end
            page = page.Parent
        end
        if page._isSubTab then
            if page.Parent.CurrentSubTab ~= page then
                return false
            end
            page = page.Parent
        end
        return window.CurrentTab == page
    end

    if type(opts.Update) == "function" then
        local alive = true
        table.insert(handle._listeners, function()
            alive = false
        end)
        task.defer(function()
            local first = true
            while alive and frame.Parent do
                if first or onScreen() then
                    first = false
                    local ok, result = isolatedCall(opts.Update)
                    if ok then
                        if result ~= nil then
                            handle:Set(result)
                        end
                    else
                        warn("[RealIggyLib] status list update error: " .. tostring(result))
                    end
                end
                task.wait(rate)
            end
        end)
    end

    handle:Set(opts.Rows or {})
    return finishElement(self, opts, handle, frame, "StatusList")
end

Tab.CreateStatus = Tab.Status
Tab.AddStatus = Tab.Status
Tab.CreateStatuses = Tab.Statuses
Tab.CreateStatusList = Tab.StatusList
Tab.AddStatusList = Tab.StatusList

-- Image and Viewport: media cards. Image shows a picture from the same sources
-- as window backgrounds, plus "Avatar" for the player's headshot. Viewport
-- shows a 3D model or the player's avatar, turning slowly; drag it to spin it
-- by hand.

function Tab:_mediaCard(opts, defaultHeight)
    opts = normalize(opts, { Title = "Name", Description = "Desc" })
    local metrics = metricsOf(self)
    local compact = metrics.Compact
    local mediaHeight = math.clamp(tonumber(opts.Height) or defaultHeight, 40, 600)
    local inset = compact and 14 or 8
    local hasHead = type(opts.Name) == "string" and opts.Name ~= ""
    local titleTop = compact and 4 or 10
    local mediaTop = hasHead and (titleTop + (opts.Desc and 38 or 22)) or (compact and 4 or inset)
    local height = mediaTop + mediaHeight + (compact and 6 or inset)
    local frame, frameStroke = card(self, "Frame", height, opts)
    hoverStroke(frame, frameStroke)
    local title, descLabel
    if hasHead then
        title = label({
            Position = UDim2.fromOffset(14, titleTop),
            Size = UDim2.new(1, -28, 0, metrics.TitleHeight),
            Text = opts.Name,
            TextSize = metrics.TextSize,
            Parent = frame,
        })
        if opts.Desc then
            descLabel = label({
                Position = UDim2.fromOffset(14, titleTop + metrics.TitleHeight + 1),
                Size = UDim2.new(1, -28, 0, metrics.DescLine),
                Text = opts.Desc,
                TextSize = metrics.DescSize,
                FontFace = Fonts.Regular,
                TextColor3 = Theme.Muted,
                Parent = frame,
            })
        end
    end
    local media = create("Frame", {
        Position = UDim2.fromOffset(inset, mediaTop),
        Size = UDim2.new(1, -inset * 2, 0, mediaHeight),
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = frame,
    })
    corner(media, UDim.new(0, 6))
    stroke(media, Theme.Stroke)
    local placeholder = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(22, 22),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ImageTransparency = 0.3,
        ScaleType = Enum.ScaleType.Fit,
        Parent = media,
    })
    -- A caption over the bottom of the picture, on a dark fade.
    local captionHolder = create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 3,
        Parent = media,
    })
    create("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new(1, 0),
        Parent = captionHolder,
    })
    local caption = label({
        Position = UDim2.fromOffset(10, 8),
        Size = UDim2.new(1, -20, 1, -10),
        TextSize = 12,
        TextColor3 = Color3.new(1, 1, 1),
        ZIndex = 4,
        Parent = captionHolder,
    })
    local function setCaption(text)
        text = text ~= nil and tostring(text) or ""
        caption.Text = text
        captionHolder.Visible = text ~= ""
    end
    setCaption(opts.Caption)
    return opts, {
        Frame = frame,
        Stroke = frameStroke,
        Media = media,
        Placeholder = placeholder,
        Title = title,
        Desc = descLabel,
        SetCaption = setCaption,
    }
end

function Tab:Image(opts)
    local parts
    opts, parts = self:_mediaCard(opts, 160)
    local window = self.Window
    local media = parts.Media
    applyIcon(parts.Placeholder, "image")
    -- Enum lookups throw on unknown names.
    local function scaleType(name, fallback)
        local ok, value = pcall(function()
            return Enum.ScaleType[tostring(name)]
        end)
        return ok and value or fallback
    end
    local image = create("ImageLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ImageTransparency = 1,
        ScaleType = scaleType(opts.ScaleType or "Crop", Enum.ScaleType.Crop),
        ZIndex = 2,
        Parent = media,
    })
    corner(image, UDim.new(0, 6))
    if opts.Color then
        image.ImageColor3 = opts.Color
    end

    local handle = { Value = nil }
    local generation = 0

    -- Yields while a web image downloads. Returns ok, err like SetBackground.
    function handle:SetImage(source)
        generation += 1
        local current = generation
        handle.Value = source
        if source == nil or source == "" or source == "None" then
            tween(image, { ImageTransparency = 1 }, 0.2)
            tween(parts.Placeholder, { ImageTransparency = 0.3 }, 0.2)
            return true
        end
        local asset, err
        if type(source) == "number" then
            asset = "rbxassetid://" .. math.floor(source)
        elseif type(source) == "string" and ({ avatar = true, headshot = true })[source:lower()] then
            asset = "rbxthumb://type=AvatarHeadShot&id=" .. LocalPlayer.UserId .. "&w=420&h=420"
        else
            local ok, result, message = pcall(window._resolveBackground, window, tostring(source))
            if ok then
                asset, err = result, message
            else
                err = tostring(result)
            end
        end
        if generation ~= current then
            return false, "replaced by a newer image"
        end
        if not asset then
            warn("[RealIggyLib] image: " .. tostring(err))
            return false, err
        end
        image.ImageTransparency = 1
        image.Image = asset
        -- Fade in once it has loaded, or after a few seconds regardless.
        task.spawn(function()
            local waited = 0
            while not image.IsLoaded and waited < 4 and generation == current and image.Parent do
                waited += task.wait(0.05)
            end
            if generation == current and image.Parent then
                tween(image, { ImageTransparency = 0 }, 0.35)
                tween(parts.Placeholder, { ImageTransparency = 1 }, 0.2)
            end
        end)
        return true
    end
    handle.Set = handle.SetImage

    function handle:Get()
        return handle.Value
    end

    function handle:SetCaption(text)
        parts.SetCaption(text)
    end

    function handle:SetScaleType(name)
        image.ScaleType = scaleType(name, image.ScaleType)
    end

    function handle:SetColor(color)
        image.ImageColor3 = typeof(color) == "Color3" and color or Color3.new(1, 1, 1)
    end

    function handle:SetTitle(text)
        if parts.Title then
            parts.Title.Text = tostring(text)
        end
    end

    if opts.Image ~= nil then
        task.spawn(handle.SetImage, handle, opts.Image)
    end
    return finishElement(self, opts, handle, parts.Frame, "Image")
end

function Tab:Viewport(opts)
    local parts
    opts, parts = self:_mediaCard(opts, 180)
    local window = self.Window
    local media = parts.Media
    applyIcon(parts.Placeholder, "box")

    local viewport = create("ViewportFrame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ImageTransparency = 1,
        Ambient = opts.Ambient or Color3.fromRGB(165, 160, 175),
        LightColor = opts.LightColor or Color3.fromRGB(255, 250, 245),
        LightDirection = Vector3.new(-0.6, -1, -0.8),
        ZIndex = 2,
        Parent = media,
    })
    local camera = Instance.new("Camera")
    camera.FieldOfView = math.clamp(tonumber(opts.FieldOfView) or 35, 10, 90)
    camera.Parent = viewport
    viewport.CurrentCamera = camera
    local world = Instance.new("WorldModel")
    world.Parent = viewport

    local handle = {
        Model = nil,
        Spin = opts.Spin ~= false,
        SpinSpeed = tonumber(opts.SpinSpeed) or 25,
    }
    local angle = math.rad(tonumber(opts.Angle) or 0)
    local pitch = math.rad(tonumber(opts.Pitch) or 10)
    local distanceScale = tonumber(opts.Distance) or 1
    local center, distance, basis = nil, 10, CFrame.new()
    local source = nil
    local generation = 0
    local dragging, lastX, resumeAt = false, 0, 0

    local function place()
        if not center then
            return
        end
        local direction = basis:VectorToWorldSpace(Vector3.new(
            math.sin(angle) * math.cos(pitch),
            math.sin(pitch),
            -math.cos(angle) * math.cos(pitch)
        ))
        camera.CFrame = CFrame.lookAt(center + direction * distance, center)
    end

    local function fit(model)
        local cf, size
        if model:IsA("Model") then
            cf, size = model:GetBoundingBox()
            basis = model:GetPivot().Rotation
        elseif model:IsA("BasePart") then
            cf, size = model.CFrame, model.Size
            basis = model.CFrame.Rotation
        else
            return false
        end
        center = cf.Position
        local radius = math.max(size.Magnitude / 2, 0.5)
        distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * distanceScale
        place()
        return true
    end

    -- A copy with its scripts and sounds stripped and every part anchored.
    local function prepare(instance)
        local copy = instance
        if opts.Clone ~= false then
            local archivable = instance.Archivable
            pcall(function()
                instance.Archivable = true
            end)
            local ok, result = pcall(instance.Clone, instance)
            pcall(function()
                instance.Archivable = archivable
            end)
            copy = ok and result or nil
        end
        if not copy then
            return nil
        end
        local function clean(object)
            if object:IsA("LuaSourceContainer") or object:IsA("Sound") or object:IsA("ForceField") then
                object:Destroy()
            elseif object:IsA("BasePart") then
                object.Anchored = true
                object.CanCollide = false
            end
        end
        for _, object in ipairs(copy:GetDescendants()) do
            pcall(clean, object)
        end
        if copy:IsA("BasePart") then
            copy.Anchored = true
        end
        local humanoid = copy:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        end
        return copy
    end

    local function resolve(value)
        if type(value) == "function" then
            local ok, result = pcall(value)
            value = ok and result or nil
        end
        if type(value) == "string" and ({ avatar = true, player = true, character = true })[value:lower()] then
            value = LocalPlayer
        end
        if typeof(value) == "Instance" and value:IsA("Player") then
            local character = value.Character
            if not character then
                character = value.CharacterAdded:Wait()
                -- Let the body parts and accessories load in.
                task.wait(0.5)
            end
            value = character
        end
        return typeof(value) == "Instance" and value or nil
    end

    -- Yields while waiting for a character to spawn.
    function handle:SetModel(value)
        generation += 1
        local current = generation
        source = value
        if handle.Model then
            handle.Model:Destroy()
            handle.Model = nil
        end
        center = nil
        if value == nil then
            tween(viewport, { ImageTransparency = 1 }, 0.2)
            tween(parts.Placeholder, { ImageTransparency = 0.3 }, 0.2)
            return true
        end
        local instance = resolve(value)
        if generation ~= current then
            return false, "replaced by a newer model"
        end
        if not instance then
            return false, "no model to show"
        end
        local copy = prepare(instance)
        if not copy then
            return false, "could not copy the model"
        end
        copy.Parent = world
        handle.Model = copy
        if not fit(copy) then
            copy:Destroy()
            handle.Model = nil
            return false, "not a Model or a part"
        end
        viewport.ImageTransparency = 1
        tween(viewport, { ImageTransparency = 0 }, 0.35)
        tween(parts.Placeholder, { ImageTransparency = 1 }, 0.2)
        return true
    end
    handle.Set = handle.SetModel

    function handle:Get()
        return handle.Model
    end

    -- Copies the source again, e.g. after the character respawned or changed.
    function handle:Refresh()
        return handle:SetModel(source)
    end

    function handle:SetSpin(enabled)
        handle.Spin = enabled ~= false
    end

    function handle:SetSpinSpeed(degrees)
        handle.SpinSpeed = tonumber(degrees) or handle.SpinSpeed
    end

    function handle:SetAngle(degrees)
        angle = math.rad(tonumber(degrees) or 0)
        place()
    end

    function handle:SetCaption(text)
        parts.SetCaption(text)
    end

    function handle:SetTitle(text)
        if parts.Title then
            parts.Title.Text = tostring(text)
        end
    end

    media.InputBegan:Connect(function(input)
        if isPress(input) and handle.Model then
            dragging = true
            lastX = pointerPosition().X
        end
    end)
    window:_listen("Changed", function(input)
        if dragging and isMove(input) then
            local x = pointerPosition().X
            angle -= (x - lastX) * 0.012
            lastX = x
            place()
        end
    end, handle)
    window:_listen("Ended", function(input)
        if dragging and isPress(input) then
            dragging = false
            resumeAt = os.clock() + 1.5
        end
    end, handle)
    window:_listen("Render", function(deltaTime)
        if handle.Spin and center and not dragging and os.clock() >= resumeAt and window.Open and not window.Minimized
            and parts.Frame.Visible then
            angle += math.rad(handle.SpinSpeed) * deltaTime
            place()
        end
    end, handle)

    if opts.Model ~= nil then
        task.spawn(handle.SetModel, handle, opts.Model)
    end
    return finishElement(self, opts, handle, parts.Frame, "Viewport")
end

-- Table: rows under a header, sortable by clicking a column. Rank = true adds
-- a # column with medals for the top three, for leaderboards.

function Tab:Table(opts)
    opts = normalize(opts, { Title = "Name", Description = "Desc", Data = "Rows", OnRowClick = "Callback" })
    local window = self.Window
    local metrics = metricsOf(self)
    local compact = metrics.Compact
    local rowHeight = tonumber(opts.RowHeight) or (TOUCH and 32 or 26)
    local maxRows = math.max(math.floor(tonumber(opts.MaxRows) or 8), 1)
    local headerHeight = TOUCH and 28 or 24
    local textSize = compact and 12 or 13
    local inset = compact and 14 or 8
    local hasHead = type(opts.Name) == "string" and opts.Name ~= ""
    local titleTop = compact and 4 or 10
    local searchable = opts.Search ~= false
    local searchHeight = TOUCH and 30 or 26
    local searchTop = hasHead and (titleTop + (opts.Desc and 38 or 22)) or (compact and 4 or inset)
    local gridTop = searchTop + (searchable and searchHeight + 6 or 0)
    local bottom = compact and 6 or inset

    local frame, frameStroke = card(self, "Frame", gridTop + headerHeight + rowHeight + bottom, opts)
    hoverStroke(frame, frameStroke)
    local title
    if hasHead then
        title = label({
            Position = UDim2.fromOffset(14, titleTop),
            Size = UDim2.new(1, -28, 0, metrics.TitleHeight),
            Text = opts.Name,
            TextSize = metrics.TextSize,
            Parent = frame,
        })
        if opts.Desc then
            label({
                Position = UDim2.fromOffset(14, titleTop + metrics.TitleHeight + 1),
                Size = UDim2.new(1, -28, 0, metrics.DescLine),
                Text = opts.Desc,
                TextSize = metrics.DescSize,
                FontFace = Fonts.Regular,
                TextColor3 = Theme.Muted,
                Parent = frame,
            })
        end
    end
    -- Search: filters rows by any cell's text as you type. A count of what
    -- matches shows on the right while it filters.
    local query = ""
    local searchBox, searchCount
    if searchable then
        local holder = create("Frame", {
            Position = UDim2.fromOffset(inset, searchTop),
            Size = UDim2.new(1, -inset * 2, 0, searchHeight),
            BackgroundColor3 = Theme.Surface,
            BorderSizePixel = 0,
            Parent = frame,
        })
        holder:SetAttribute("NoDrag", true)
        corner(holder, UDim.new(0, 6))
        local searchStroke = stroke(holder)
        local iconHolder, searchIcon = glowIcon(holder, "search", Theme.Muted, UDim2.new(0, 9, 0.5, 0))
        iconHolder.Size = UDim2.fromOffset(13, 13)
        searchCount = label({
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -9, 0, 0),
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = "",
            TextSize = 11,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextTruncate = Enum.TextTruncate.None,
            Visible = false,
            Parent = holder,
        })
        searchBox = create("TextBox", {
            Position = UDim2.fromOffset(29, 0),
            Size = UDim2.new(1, -90, 1, 0),
            BackgroundTransparency = 1,
            Text = "",
            PlaceholderText = opts.SearchPlaceholder or "Search",
            PlaceholderColor3 = Theme.Muted,
            TextColor3 = Theme.Text,
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            ClearTextOnFocus = false,
            Parent = holder,
        })
        searchBox.Focused:Connect(function()
            tween(searchStroke, { Color = Theme.StrokeHover }, 0.15)
            tween(searchIcon, { ImageColor3 = Theme.Accent }, 0.15)
        end)
        searchBox.FocusLost:Connect(function()
            tween(searchStroke, { Color = Theme.Stroke }, 0.2)
            tween(searchIcon, { ImageColor3 = Theme.Muted }, 0.2)
        end)
    end

    local grid = create("Frame", {
        Position = UDim2.fromOffset(inset, gridTop),
        Size = UDim2.new(1, -inset * 2, 0, headerHeight + rowHeight),
        BackgroundColor3 = Theme.Surface,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = frame,
    })
    corner(grid, UDim.new(0, 6))
    stroke(grid, Theme.Stroke)
    local header = create("Frame", {
        Size = UDim2.new(1, 0, 0, headerHeight),
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.45,
        BorderSizePixel = 0,
        Parent = grid,
    })
    create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        Parent = header,
    })
    local body = create("ScrollingFrame", {
        Position = UDim2.fromOffset(0, headerHeight),
        Size = UDim2.new(1, 0, 1, -headerHeight),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0.4,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        Parent = grid,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = body,
    })
    local empty = label({
        Position = UDim2.fromOffset(0, headerHeight),
        Size = UDim2.new(1, 0, 0, rowHeight),
        Text = opts.EmptyText or "Nothing here yet",
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = grid,
    })

    local handle = { Rows = {} }
    local shownCount = nil
    local columns, headerCells = {}, {}
    local pool = {}
    local sortKey, sortDescending = nil, false
    local shownHeight = nil
    local MEDALS = {
        Color3.fromRGB(245, 200, 90),
        Color3.fromRGB(200, 206, 218),
        Color3.fromRGB(214, 146, 96),
    }

    local function alignment(column)
        local align = type(column.Align) == "string" and column.Align:lower() or nil
        if align == "right" then
            return Enum.TextXAlignment.Right
        elseif align == "center" or align == "centre" then
            return Enum.TextXAlignment.Center
        end
        return Enum.TextXAlignment.Left
    end

    -- Widths: a number above 1 is pixels, up to 1 is a share of what the pixel
    -- columns leave, and the rest split whatever share is left.
    local function layoutColumns()
        local pixels, shares, autos = 0, 0, 0
        for _, column in ipairs(columns) do
            local width = tonumber(column.Width)
            if width and width > 1 then
                pixels += width
            elseif width and width > 0 then
                shares += width
            else
                autos += 1
            end
        end
        local left = math.max(1 - shares, 0)
        for _, column in ipairs(columns) do
            local width = tonumber(column.Width)
            local share
            if width and width > 1 then
                column.UDim = UDim.new(0, width)
            else
                share = (width and width > 0) and width or (autos > 0 and left / autos or 0)
                column.UDim = UDim.new(share, -pixels * share)
            end
        end
    end

    local function columnValue(row, column)
        if column.Rank then
            return nil
        end
        if row[1] ~= nil or column.Key == nil then
            return row[column.Index]
        end
        return row[column.Key]
    end

    local function display(value, column, row)
        if type(column.Format) == "function" then
            local ok, text = pcall(column.Format, value, row)
            if ok and text ~= nil then
                return tostring(text)
            end
        end
        if type(value) == "number" then
            local whole = value == math.floor(value)
            local text = whole and string.format("%d", value) or string.format("%.2f", value)
            -- Thousands separators on the whole part.
            local sign, int, rest = text:match("^(%-?)(%d+)(.*)$")
            if int then
                int = int:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
                return sign .. int .. rest
            end
            return text
        end
        if value == nil then
            return ""
        end
        return tostring(value)
    end

    local function paintHeader()
        for _, cell in ipairs(headerCells) do
            local column = cell.Column
            local active = sortKey ~= nil and sortKey == column
            tween(cell.Label, { TextColor3 = active and Theme.Text or Theme.Muted }, 0.15)
            cell.Arrow.Visible = active
            if active then
                tween(cell.Arrow, { Rotation = sortDescending and 0 or 180 }, 0.2, Enum.EasingStyle.Quint)
            end
        end
    end

    local function sortedRows()
        local list = {}
        for index, row in ipairs(handle.Rows) do
            list[index] = { Row = row, Index = index }
        end
        if sortKey then
            local column = sortKey
            table.sort(list, function(a, b)
                local x, y = columnValue(a.Row, column), columnValue(b.Row, column)
                local nx, ny = tonumber(x), tonumber(y)
                if nx and ny then
                    if nx ~= ny then
                        if sortDescending then
                            return nx > ny
                        end
                        return nx < ny
                    end
                elseif x ~= nil and y ~= nil then
                    local sx, sy = string.lower(tostring(x)), string.lower(tostring(y))
                    if sx ~= sy then
                        if sortDescending then
                            return sx > sy
                        end
                        return sx < sy
                    end
                elseif x ~= y then
                    -- Empty cells sink to the bottom either way.
                    return x ~= nil
                end
                return a.Index < b.Index
            end)
        end
        -- Ranks come from the full order, so filtering never renumbers them.
        for position, item in ipairs(list) do
            item.Rank = position
        end
        if query == "" then
            return list
        end
        local shown = {}
        for _, item in ipairs(list) do
            for _, column in ipairs(columns) do
                if not column.Rank then
                    local text = display(columnValue(item.Row, column), column, item.Row)
                    text = string.lower((string.gsub(text, "<[^>]->", "")))
                    if string.find(text, query, 1, true) then
                        table.insert(shown, item)
                        break
                    end
                end
            end
        end
        return shown
    end

    local function newRow()
        local rowFrame = create("TextButton", {
            Size = UDim2.new(1, 0, 0, rowHeight),
            BackgroundColor3 = Theme.Surface3,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
            Parent = body,
        })
        -- The accent bar on a highlighted row sits beside the cells, outside
        -- their layout.
        local marker = create("Frame", {
            Position = UDim2.new(0, 3, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5),
            Size = UDim2.new(0, 2, 1, -10),
            BackgroundColor3 = Theme.Accent,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Parent = rowFrame,
        })
        corner(marker, UDim.new(1, 0))
        local cellsFrame = create("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Parent = rowFrame,
        })
        padding(cellsFrame, 10, 10)
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Parent = cellsFrame,
        })
        local entry = { Frame = rowFrame, Marker = marker, Cells = {}, Hover = false }
        for order, column in ipairs(columns) do
            local cell = create("Frame", {
                Size = UDim2.new(column.UDim.Scale, column.UDim.Offset, 1, 0),
                BackgroundTransparency = 1,
                LayoutOrder = order,
                Parent = cellsFrame,
            })
            local text = label({
                Size = UDim2.new(1, -6, 1, 0),
                TextSize = textSize,
                FontFace = column.Rank and Fonts.Bold or Fonts.Regular,
                TextColor3 = Theme.Text,
                TextXAlignment = alignment(column),
                RichText = not column.Rank,
                Parent = cell,
            })
            local badge
            if column.Rank then
                text.Size = UDim2.fromScale(1, 1)
                text.TextXAlignment = Enum.TextXAlignment.Center
                badge = create("Frame", {
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.fromScale(0.5, 0.5),
                    Size = UDim2.fromOffset(rowHeight - 8, rowHeight - 8),
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    ZIndex = 0,
                    Parent = cell,
                })
                corner(badge, UDim.new(1, 0))
            end
            entry.Cells[order] = { Label = text, Badge = badge }
        end
        local canTap = tapGuard(rowFrame, function()
            return body
        end)
        rowFrame.MouseEnter:Connect(function()
            entry.Hover = true
            tween(rowFrame, { BackgroundTransparency = 0.35 }, 0.1)
        end)
        rowFrame.MouseLeave:Connect(function()
            entry.Hover = false
            tween(rowFrame, {
                BackgroundColor3 = entry.Highlighted and Theme.Accent or Theme.Surface3,
                BackgroundTransparency = entry.Rest or 1,
            }, 0.2)
        end)
        rowFrame.MouseButton1Click:Connect(function()
            if entry.Data and canTap() then
                safeCall(opts.Callback, entry.Data, entry.Index)
            end
        end)
        return entry
    end

    local function fitHeight(instant)
        local count = shownCount or #handle.Rows
        local visible = math.clamp(count, 1, maxRows)
        local gridHeight = headerHeight + visible * rowHeight
        local total = gridTop + gridHeight + bottom
        if shownHeight == total then
            return
        end
        local duration = (instant or shownHeight == nil) and 0 or 0.25
        shownHeight = total
        tween(grid, { Size = UDim2.new(1, -inset * 2, 0, gridHeight) }, duration, Enum.EasingStyle.Quint)
        tween(frame, { Size = UDim2.new(1, 0, 0, total) }, duration, Enum.EasingStyle.Quint)
    end

    local function render()
        local list = sortedRows()
        for position, item in ipairs(list) do
            local entry = pool[position]
            if not entry then
                entry = newRow()
                pool[position] = entry
            end
            local row = item.Row
            entry.Data = row
            entry.Index = item.Index
            entry.Frame.LayoutOrder = position
            entry.Frame.Visible = true
            local highlighted = row.Highlight == true
            if not highlighted and type(opts.Highlight) == "function" then
                local ok, result = pcall(opts.Highlight, row, item.Index)
                highlighted = ok and result == true
            end
            entry.Highlighted = highlighted
            entry.Rest = highlighted and 0.86 or (position % 2 == 0 and 0.78 or 1)
            if not entry.Hover then
                entry.Frame.BackgroundColor3 = highlighted and Theme.Accent or Theme.Surface3
                entry.Frame.BackgroundTransparency = entry.Rest
                bindColors(entry.Frame, { BackgroundColor3 = entry.Frame.BackgroundColor3 })
            end
            entry.Marker.BackgroundTransparency = highlighted and 0 or 1
            for order, column in ipairs(columns) do
                local cell = entry.Cells[order]
                if column.Rank then
                    local medal = MEDALS[item.Rank]
                    cell.Label.Text = tostring(item.Rank)
                    cell.Label.TextColor3 = medal and Color3.fromRGB(28, 22, 18) or Theme.Muted
                    bindColors(cell.Label, { TextColor3 = cell.Label.TextColor3 })
                    cell.Badge.BackgroundColor3 = medal or Theme.Surface3
                    cell.Badge.BackgroundTransparency = medal and 0.05 or 1
                else
                    local value = columnValue(row, column)
                    cell.Label.Text = Library._rich(display(value, column, row))
                    -- Column Color: a colour, a theme key or a function(value, row)
                    -- returning either. A row's Colors[key or index] beats it.
                    local wanted = column.Color
                    if type(wanted) == "function" then
                        local ok, result = pcall(wanted, value, row)
                        wanted = ok and result or nil
                    end
                    if type(row.Colors) == "table" then
                        local own = row.Colors[column.Key or column.Index]
                        if own == nil then
                            own = row.Colors[column.Index]
                        end
                        if own ~= nil then
                            wanted = own
                        end
                    end
                    local color = Library._color(wanted) or (highlighted and Theme.Accent or Theme.Text)
                    cell.Label.TextColor3 = color
                    bindColors(cell.Label, { TextColor3 = color })
                end
            end
        end
        for position = #list + 1, #pool do
            pool[position].Frame.Visible = false
            pool[position].Data = nil
        end
        shownCount = #list
        empty.Visible = #list == 0
        empty.Text = (#list == 0 and query ~= "" and #handle.Rows > 0) and (opts.NoMatchText or "No rows match")
            or (opts.EmptyText or "Nothing here yet")
        if searchCount then
            searchCount.Visible = query ~= ""
            searchCount.Text = #list .. " / " .. #handle.Rows
        end
        fitHeight()
    end

    local function buildHeader()
        for _, cell in ipairs(headerCells) do
            cell.Frame:Destroy()
        end
        table.clear(headerCells)
        for _, entry in ipairs(pool) do
            entry.Frame:Destroy()
        end
        table.clear(pool)
        local row = header:FindFirstChild("Cells") or create("Frame", {
            Name = "Cells",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Parent = header,
        })
        if not row:FindFirstChildOfClass("UIListLayout") then
            padding(row, 10, 10)
            create("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                VerticalAlignment = Enum.VerticalAlignment.Center,
                SortOrder = Enum.SortOrder.LayoutOrder,
                Parent = row,
            })
        end
        for order, column in ipairs(columns) do
            local cell = create("TextButton", {
                Size = UDim2.new(column.UDim.Scale, column.UDim.Offset, 1, 0),
                BackgroundTransparency = 1,
                AutoButtonColor = false,
                Text = "",
                LayoutOrder = order,
                Parent = row,
            })
            local align = column.Rank and Enum.TextXAlignment.Center or alignment(column)
            local right = align == Enum.TextXAlignment.Right
            local text = label({
                Size = UDim2.new(1, align == Enum.TextXAlignment.Center and 0 or -16, 1, 0),
                Position = UDim2.fromOffset(right and 16 or 0, 0),
                Text = string.upper(column.Name),
                TextSize = 11,
                FontFace = Fonts.Bold,
                TextColor3 = Theme.Muted,
                TextXAlignment = align,
                Parent = cell,
            })
            local arrow = create("ImageLabel", {
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 0, 0.5, 0),
                Size = UDim2.fromOffset(12, 12),
                BackgroundTransparency = 1,
                ImageColor3 = Theme.Accent,
                ScaleType = Enum.ScaleType.Fit,
                Visible = false,
                Parent = cell,
            })
            applyIcon(arrow, "chevron-down")
            -- The arrow sits just after the header text (before it when the
            -- column is right aligned).
            local function placeArrow()
                local width = text.TextBounds.X
                if right then
                    arrow.Position = UDim2.new(1, -(width + 15), 0.5, 0)
                elseif align == Enum.TextXAlignment.Center then
                    arrow.Position = UDim2.new(0.5, width / 2 + 3, 0.5, 0)
                else
                    local cellWidth = cell.AbsoluteSize.X / math.max(window.Scale.Scale, 0.01)
                    arrow.Position = UDim2.new(0, math.clamp(width + 4, 0, math.max(cellWidth - 12, 0)), 0.5, 0)
                end
            end
            text:GetPropertyChangedSignal("TextBounds"):Connect(placeArrow)
            cell:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeArrow)
            task.defer(placeArrow)
            local sortable = column.Sortable and not column.Rank
            if sortable then
                cell.MouseEnter:Connect(function()
                    if sortKey ~= column then
                        tween(text, { TextColor3 = Theme.Text }, 0.12)
                    end
                end)
                cell.MouseLeave:Connect(function()
                    if sortKey ~= column then
                        tween(text, { TextColor3 = Theme.Muted }, 0.2)
                    end
                end)
                cell.MouseButton1Click:Connect(function()
                    -- Numbers sort high to low first, text A to Z; the second
                    -- click flips it and the third goes back to the given order.
                    if sortKey ~= column then
                        local numeric = false
                        for _, data in ipairs(handle.Rows) do
                            local value = columnValue(data, column)
                            if value ~= nil then
                                numeric = tonumber(value) ~= nil
                                break
                            end
                        end
                        sortKey, sortDescending = column, numeric
                        column.FirstDescending = numeric
                    elseif sortDescending == column.FirstDescending then
                        sortDescending = not sortDescending
                    else
                        sortKey = nil
                    end
                    paintHeader()
                    render()
                end)
            end
            table.insert(headerCells, { Frame = cell, Label = text, Arrow = arrow, Column = column })
        end
        paintHeader()
    end

    function handle:SetColumns(list)
        table.clear(columns)
        if opts.Rank then
            table.insert(columns, { Name = "#", Rank = true, Width = TOUCH and 40 or 36, Sortable = false })
        end
        for index, column in ipairs(type(list) == "table" and list or {}) do
            if type(column) ~= "table" then
                column = { Name = tostring(column) }
            end
            local name = column.Name or column.Title or ("Column " .. index)
            table.insert(columns, {
                Name = name,
                Key = column.Key or name,
                Index = index,
                Width = column.Width,
                Align = column.Align,
                Format = column.Format,
                Color = column.Color,
                Sortable = column.Sortable ~= false and opts.Sortable ~= false,
            })
        end
        sortKey = nil
        layoutColumns()
        buildHeader()
        render()
    end

    local function findColumn(key)
        if type(key) == "number" then
            return columns[key + (opts.Rank and 1 or 0)]
        end
        for _, column in ipairs(columns) do
            if not column.Rank and (column.Key == key or column.Name == key) then
                return column
            end
        end
        return nil
    end

    function handle:SetRows(rows)
        handle.Rows = {}
        for index, row in ipairs(type(rows) == "table" and rows or {}) do
            handle.Rows[index] = type(row) == "table" and row or { row }
        end
        render()
    end
    handle.Set = handle.SetRows

    function handle:GetRows()
        return handle.Rows
    end
    handle.Get = handle.GetRows

    function handle:AddRow(row, position)
        row = type(row) == "table" and row or { row }
        if tonumber(position) then
            table.insert(handle.Rows, math.clamp(math.floor(position), 1, #handle.Rows + 1), row)
        else
            table.insert(handle.Rows, row)
        end
        render()
        return #handle.Rows
    end

    -- Replaces a row (by its index in the list you gave) and flashes it.
    function handle:UpdateRow(index, row)
        if not handle.Rows[index] then
            return false
        end
        handle.Rows[index] = type(row) == "table" and row or { row }
        render()
        for _, entry in ipairs(pool) do
            if entry.Index == index and entry.Frame.Visible then
                local restColor = entry.Highlighted and Theme.Accent or Theme.Surface3
                tween(entry.Frame, { BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.7 }, 0.08)
                task.delay(0.1, function()
                    if not entry.Hover then
                        tween(entry.Frame, { BackgroundColor3 = restColor, BackgroundTransparency = entry.Rest }, 0.5)
                    end
                end)
                break
            end
        end
        return true
    end

    function handle:RemoveRow(index)
        if not handle.Rows[index] then
            return false
        end
        table.remove(handle.Rows, index)
        render()
        return true
    end

    function handle:Clear()
        handle:SetRows({})
    end

    -- Sort(nil) goes back to the given order.
    function handle:Sort(key, descending)
        sortKey = key ~= nil and findColumn(key) or nil
        sortDescending = descending == true
        if sortKey then
            sortKey.FirstDescending = sortDescending
        end
        paintHeader()
        render()
    end

    function handle:SetTitle(text)
        if title then
            title.Text = tostring(text)
        end
    end

    function handle:SetMaxRows(count)
        maxRows = math.max(math.floor(tonumber(count) or maxRows), 1)
        fitHeight()
    end

    handle:SetColumns(opts.Columns or {})
    handle:SetRows(opts.Rows or {})
    if opts.SortBy ~= nil then
        handle:Sort(opts.SortBy, opts.SortDescending ~= false)
    end
    fitHeight(true)
    if searchBox then
        searchBox:GetPropertyChangedSignal("Text"):Connect(function()
            local text = string.lower(trim(searchBox.Text))
            if text ~= query then
                query = text
                body.CanvasPosition = Vector2.zero
                render()
            end
        end)
    end
    function handle:SetSearch(text)
        if searchBox then
            searchBox.Text = tostring(text or "")
        end
    end
    -- Theme tags in cells are baked to colours; repaint them on theme change.
    onTheme(grid, render)
    return finishElement(self, opts, handle, frame, "Table")
end

Tab.CreateImage = Tab.Image
Tab.AddImage = Tab.Image
Tab.CreateViewport = Tab.Viewport
Tab.AddViewport = Tab.Viewport
Tab.CreateTable = Tab.Table
Tab.AddTable = Tab.Table
Tab.CreateLeaderboard = Tab.Table

local function settleSubOut(ui)
    if ui.OutFrame then
        ui.OutFrame.Parent = ui.Area
        ui.OutFrame.Visible = false
        ui.OutFrame = nil
    end
    ui.Out.Visible = false
end

local function settleSubIn(ui)
    if ui.InFrame then
        ui.InFrame.Parent = ui.Area
        ui.InFrame.Position = UDim2.fromOffset(0, 0)
        ui.InFrame = nil
    end
    ui.In.Visible = false
end

function Tab:_setupSubTabs()
    local top = self._headerBottom
    local page = self._page
    local strip = create("ScrollingFrame", {
        Name = "SubTabs",
        Position = UDim2.fromOffset(22, top - 4),
        Size = UDim2.new(1, -44, 0, 32),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        ScrollingDirection = Enum.ScrollingDirection.X,
        AutomaticCanvasSize = Enum.AutomaticSize.X,
        CanvasSize = UDim2.new(),
        Parent = page,
    })
    strip:SetAttribute("NoDrag", true)
    local highlight = create("Frame", {
        Size = UDim2.fromOffset(0, 32),
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Visible = false,
        Parent = strip,
    })
    corner(highlight, UDim.new(0, 8))
    stroke(highlight, Theme.Stroke)
    local row = create("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        ZIndex = 2,
        Parent = strip,
    })
    padding(row, 2, 2, 0, 0)
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = row,
    })
    self.Window:_overflowHint(page, strip, row, false, Theme.Background)
    local areaTop = top + 36
    local area = create("Frame", {
        Name = "SubPages",
        Position = UDim2.fromOffset(0, areaTop),
        Size = UDim2.new(1, 0, 1, -areaTop),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Parent = page,
    })
    local ui = {
        Strip = strip,
        Row = row,
        Highlight = highlight,
        Area = area,
        Out = create("CanvasGroup", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Visible = false,
            ZIndex = 2,
            Parent = area,
        }),
        In = create("CanvasGroup", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Visible = false,
            ZIndex = 3,
            Parent = area,
        }),
        Generation = 0,
    }
    self._sub = ui
    self._subTabs = {}
    self.List.Visible = false
    self:_refreshEmpty()
    -- Keep the pill under the selected tab when widths change after layout.
    row:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if self.CurrentSubTab and not ui.Moving then
            self:_placeSubHighlight(self.CurrentSubTab, true)
        end
    end)
end

function Tab:_placeSubHighlight(sub, instant)
    local ui = self._sub
    local scale = self.Window.Scale.Scale
    local button = sub._button
    local width = button.AbsoluteSize.X / scale
    if width <= 0 then
        return
    end
    local x = (button.AbsolutePosition.X - ui.Row.AbsolutePosition.X) / scale
    local view = ui.Strip.AbsoluteSize.X / scale
    local canvasX = ui.Strip.CanvasPosition.X
    if x < canvasX then
        tween(ui.Strip, { CanvasPosition = Vector2.new(math.max(x - 8, 0), 0) }, 0.3, Enum.EasingStyle.Quint)
    elseif x + width > canvasX + view then
        tween(ui.Strip, { CanvasPosition = Vector2.new(x + width - view + 8, 0) }, 0.3, Enum.EasingStyle.Quint)
    end
end

function Tab:SubTab(opts, icon)
    if self._groupbox or self._isSubTab then
        return self.Parent:SubTab(opts, icon)
    end
    opts = normalize(opts, { Title = "Name", Description = "Desc" })
    if icon ~= nil and opts.Icon == nil then
        opts.Icon = icon
    end
    if not self._subTabs then
        self:_setupSubTabs()
    end
    local ui = self._sub
    local index = #self._subTabs + 1
    local sub = setmetatable({
        Name = opts.Name or ("Page " .. index),
        Window = self.Window,
        Parent = self,
        _order = 0,
        _isSubTab = true,
        _index = index,
        _iconName = opts.Icon,
    }, Tab)
    local frame = create("Frame", {
        Name = sub.Name,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        Parent = ui.Area,
    })
    sub._frame = frame
    buildContainer(sub, frame, 0, opts.Icon or self._iconName or "layout-grid", opts.EmptyText or "Nothing here yet")

    local button = create("TextButton", {
        Size = UDim2.new(0, 0, 0, 28),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Surface2,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = index,
        Parent = ui.Row,
    })
    corner(button, UDim.new(0, 6))
    local btnStroke = stroke(button, Theme.Stroke)
    padding(button, 12, 12)
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = button,
    })
    if opts.Icon then
        local image = create("ImageLabel", {
            Size = UDim2.fromOffset(14, 14),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Muted,
            ScaleType = Enum.ScaleType.Fit,
            LayoutOrder = 1,
            Parent = button,
        })
        applyIcon(image, opts.Icon)
        if image:GetAttribute("CustomIcon") then
            image.ImageTransparency = 0.4
        end
        sub._iconImage = image
    end
    sub._label = label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = sub.Name,
        TextSize = 12,
        FontFace = Fonts.Medium,
        TextColor3 = Theme.Muted,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        Parent = button,
    })
    sub._button = button
    sub._stroke = btnStroke
    button.MouseEnter:Connect(function()
        if self.CurrentSubTab ~= sub then
            tween(button, { BackgroundTransparency = 0.2 }, 0.15)
            tween(sub._label, { TextColor3 = Theme.Text }, 0.15)
            if sub._iconImage then
                tintIcon(sub._iconImage, Theme.Text, true, 0.15)
            end
        end
    end)
    button.MouseLeave:Connect(function()
        if self.CurrentSubTab ~= sub then
            tween(button, { BackgroundTransparency = 0.5 }, 0.2)
            tween(sub._label, { TextColor3 = Theme.Muted }, 0.2)
            if sub._iconImage then
                tintIcon(sub._iconImage, Theme.Muted, false, 0.2)
            end
        end
    end)
    button.MouseButton1Click:Connect(function()
        self:SelectSubTab(sub)
    end)

    table.insert(self._subTabs, sub)
    if index == 1 then
        self:SelectSubTab(sub, true)
    end
    return sub
end

Tab.CreateSubTab = Tab.SubTab
Tab.AddSubTab = Tab.SubTab

function Tab:SelectSubTab(sub, instant)
    if type(sub) ~= "table" then
        for index, entry in ipairs(self._subTabs or {}) do
            if entry.Name == sub or index == sub then
                sub = entry
                break
            end
        end
    end
    if type(sub) ~= "table" or not self._sub then
        return
    end
    local previous = self.CurrentSubTab
    if previous == sub then
        return
    end
    self.Window:_resetSearch()
    self.Window:_closePopups()
    self.CurrentSubTab = sub
    local ui = self._sub
    settleSubOut(ui)
    settleSubIn(ui)
    ui.Generation += 1
    local generation = ui.Generation

    local fade = instant and 0 or 0.2
    if previous then
        if previous._button then
            tween(previous._button, { BackgroundColor3 = Theme.Surface2, BackgroundTransparency = 0.5 }, fade)
        end
        if previous._stroke then
            tween(previous._stroke, { Color = Theme.Stroke }, fade)
        end
        if previous._label then
            tween(previous._label, { TextColor3 = Theme.Muted }, fade)
            previous._label.FontFace = Fonts.Medium
        end
        if previous._iconImage then
            tintIcon(previous._iconImage, Theme.Muted, false, fade)
        end
    end
    if sub then
        if sub._button then
            tween(sub._button, { BackgroundColor3 = Theme.Surface3, BackgroundTransparency = 0 }, fade)
        end
        if sub._stroke then
            tween(sub._stroke, { Color = Color3.fromRGB(60, 60, 65) }, fade)
        end
        if sub._label then
            tween(sub._label, { TextColor3 = Theme.Text }, fade)
            sub._label.FontFace = Fonts.SemiBold
        end
        if sub._iconImage then
            tintIcon(sub._iconImage, Theme.Text, true, fade)
        end
    end
    self:_placeSubHighlight(sub, instant)

    if instant or not previous then
        if previous then
            previous._frame.Visible = false
        end
        sub._frame.Visible = true
        return
    end

    local direction = sub._index > previous._index and 1 or -1
    ui.OutFrame = previous._frame
    previous._frame.Parent = ui.Out
    ui.Out.GroupTransparency = 0
    ui.Out.Position = UDim2.fromOffset(0, 0)
    ui.Out.Visible = true
    tween(ui.Out, { GroupTransparency = 1, Position = UDim2.fromOffset(-direction * 28, 0) }, 0.2)

    ui.InFrame = sub._frame
    sub._frame.Visible = true
    sub._frame.Parent = ui.In
    ui.In.GroupTransparency = 1
    ui.In.Position = UDim2.fromOffset(direction * 28, 0)
    ui.In.Visible = true
    tween(ui.In, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) }, 0.34, Enum.EasingStyle.Quint)

    task.delay(0.2, function()
        if ui.Generation == generation then
            settleSubOut(ui)
        end
    end)
    task.delay(0.34, function()
        if ui.Generation == generation then
            settleSubIn(ui)
        end
    end)
end

-- Search: one box over the whole window. Typing lists matching tabs, pages,
-- groupboxes and controls from every tab; picking one opens its tab and page,
-- scrolls it into view and flashes it.

Window._searchIcons = {
    Tab = "app-window",
    Page = "panels-top-left",
    Groupbox = "layout-grid",
    Button = "mouse-pointer-click",
    ButtonRow = "mouse-pointer-click",
    Toggle = "toggle-right",
    Slider = "sliders-horizontal",
    Dropdown = "list",
    Input = "text-cursor-input",
    Keybind = "keyboard",
    ColorPicker = "palette",
    Stepper = "chevrons-up-down",
    Progress = "activity",
    Status = "activity",
    StatusList = "activity",
    Label = "type",
    Paragraph = "type",
    OrderList = "list-ordered",
}

function Window:_searchResults(query)
    local results = {}
    local function consider(name, entry)
        if type(name) ~= "string" or name == "" then
            return
        end
        local at = string.find(string.lower(name), query, 1, true)
        if not at then
            return
        end
        entry.Name = name
        entry.At = at
        -- Name starts first, then word starts, then anywhere inside a word.
        entry.Rank = at == 1 and 0 or (string.find(string.sub(name, at - 1, at - 1), "[%s%p]") and 1 or 2)
        entry.Order = #results + 1
        table.insert(results, entry)
    end
    local function shown(element)
        return not element._destroyed
            and element._type ~= "Section" and element._type ~= "Divider"
            and (element._isShown == nil or element:_isShown())
    end
    for _, tab in ipairs(self.Tabs) do
        consider(tab.Name, { Kind = "Tab", Tab = tab, Icon = tab._iconName })
        for _, page in ipairs(tab._subTabs or { tab }) do
            local sub = page._isSubTab and page or nil
            local path = tab.Name
            if sub then
                consider(sub.Name, { Kind = "Page", Tab = tab, Sub = sub, Path = tab.Name })
                path = tab.Name .. "  ›  " .. sub.Name
            end
            if not page._noSearch then
                for _, element in ipairs(page._items or {}) do
                    if shown(element) then
                        consider(element._searchName, { Kind = element._type, Tab = tab, Sub = sub, Target = element, Path = path })
                    end
                end
                for _, group in ipairs(page._groupboxes or {}) do
                    if group._userVisible ~= false then
                        consider(group.Name, { Kind = "Groupbox", Tab = tab, Sub = sub, Target = group, Path = path })
                        local groupPath = path .. "  ›  " .. group.Name
                        for _, element in ipairs(group._items) do
                            if shown(element) then
                                consider(element._searchName, { Kind = element._type, Tab = tab, Sub = sub, Target = element, Group = group, Path = groupPath })
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(results, function(a, b)
        if a.Rank ~= b.Rank then
            return a.Rank < b.Rank
        end
        return a.Order < b.Order
    end)
    return results
end

-- Marks a found control: it pops, a soft accent glow blooms around it, a
-- sheen of light sweeps across it and a bright spot runs round its border,
-- then everything breathes once more and fades.
function Window:_flash(frame, radius)
    for _, name in ipairs({ "SearchFlash", "SearchGlow" }) do
        local old = frame:FindFirstChild(name)
        if old then
            old:Destroy()
        end
    end
    radius = radius or 8
    local accent = Theme.Accent
    local bright = accent:Lerp(Color3.new(1, 1, 1), 0.65)

    -- Outer glow: a wide, faint stroke around a second outline.
    local halo = create("Frame", {
        Name = "SearchGlow",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ZIndex = 10,
        Parent = frame,
    })
    corner(halo, UDim.new(0, radius))
    local haloStroke = create("UIStroke", {
        Color = accent,
        Thickness = 1,
        Transparency = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = halo,
    })

    -- Wash with a moving sheen: a brighter diagonal band crosses it once.
    local wash = create("Frame", {
        Name = "SearchFlash",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = accent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 10,
        Parent = frame,
    })
    corner(wash, UDim.new(0, radius))
    local sheen = create("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.7),
            NumberSequenceKeypoint.new(0.4, 0.55),
            NumberSequenceKeypoint.new(0.5, 0),
            NumberSequenceKeypoint.new(0.6, 0.55),
            NumberSequenceKeypoint.new(1, 0.7),
        }),
        Rotation = 18,
        Offset = Vector2.new(-1, 0),
        Parent = wash,
    })

    -- Border light: the ring's gradient turns, so a bright spot runs round it.
    local ring = create("UIStroke", {
        Color = Color3.new(1, 1, 1),
        Thickness = 1.6,
        Transparency = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = wash,
    })
    local runner = create("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, accent),
            ColorSequenceKeypoint.new(0.5, bright),
            ColorSequenceKeypoint.new(1, accent),
        }),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.45),
            NumberSequenceKeypoint.new(0.5, 0),
            NumberSequenceKeypoint.new(1, 0.45),
        }),
        Parent = ring,
    })

    -- Groupboxes clip their rows, so anything drawn outside a control is cut
    -- off at its corners. The strokes go on the inside of the control where
    -- the engine supports it; otherwise everything is inset by its width.
    local inside = pcall(function()
        haloStroke.BorderStrokePosition = Enum.BorderStrokePosition.Inner
        ring.BorderStrokePosition = Enum.BorderStrokePosition.Inner
    end)
    local glowWidth = inside and 6 or 3
    if not inside then
        halo.Position = UDim2.fromOffset(glowWidth + 1, glowWidth + 1)
        halo.Size = UDim2.new(1, -(glowWidth + 1) * 2, 1, -(glowWidth + 1) * 2)
        wash.Position = UDim2.fromOffset(2, 2)
        wash.Size = UDim2.new(1, -4, 1, -4)
    end

    -- A small pop, unless something else is scaling the control already. It
    -- never grows past full size, which would be clipped as well.
    local pop
    if not frame:FindFirstChildOfClass("UIScale") then
        pop = create("UIScale", { Scale = 0.975, Parent = frame })
        tween(pop, { Scale = 1 }, 0.4, Enum.EasingStyle.Quint)
    end

    tween(wash, { BackgroundTransparency = 0.8 }, 0.2, Enum.EasingStyle.Quad)
    tween(ring, { Transparency = 0 }, 0.2, Enum.EasingStyle.Quad)
    tween(haloStroke, { Thickness = glowWidth, Transparency = 0.72 }, 0.35, Enum.EasingStyle.Quint)
    tween(sheen, { Offset = Vector2.new(1, 0) }, 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
    tween(runner, { Rotation = 540 }, 2.2, Enum.EasingStyle.Quad)
    task.spawn(function()
        task.wait(0.75)
        -- One softer breath, then fade out.
        tween(wash, { BackgroundTransparency = 0.9 }, 0.35, Enum.EasingStyle.Sine)
        tween(haloStroke, { Thickness = glowWidth / 2, Transparency = 0.85 }, 0.35, Enum.EasingStyle.Sine)
        task.wait(0.35)
        tween(wash, { BackgroundTransparency = 0.84 }, 0.3, Enum.EasingStyle.Sine)
        tween(haloStroke, { Thickness = glowWidth * 0.85, Transparency = 0.76 }, 0.3, Enum.EasingStyle.Sine)
        task.wait(0.4)
        tween(wash, { BackgroundTransparency = 1 }, 0.55, Enum.EasingStyle.Quad)
        tween(ring, { Transparency = 1 }, 0.65, Enum.EasingStyle.Quad)
        tween(haloStroke, { Thickness = glowWidth, Transparency = 1 }, 0.65, Enum.EasingStyle.Quad)
        task.wait(0.7)
        wash:Destroy()
        halo:Destroy()
        if pop then
            pop:Destroy()
        end
    end)
end

function Window:_revealResult(result)
    local tab, sub, target, group = result.Tab, result.Sub, result.Target, result.Group
    if self.CurrentTab ~= tab then
        self:SelectTab(tab)
    end
    if sub then
        tab:SelectSubTab(sub)
    end
    if not target then
        local button = sub and sub._button or tab._button
        task.delay(0.1, function()
            if button.Parent then
                self:_flash(button, sub and 8 or 10)
            end
        end)
        return
    end
    local expanding = group ~= nil and group:IsCollapsed()
    if expanding then
        group:Expand()
    end
    local list = (sub or tab).List
    task.spawn(function()
        -- Let the freshly shown page lay out before measuring it.
        task.wait()
        task.wait()
        if expanding then
            task.wait(0.3)
        end
        local frame = target._frame
        if self._destroyed or target._destroyed or not frame or not frame.Parent or not list then
            return
        end
        local scale = self.Scale.Scale
        local top = (frame.AbsolutePosition.Y - list.AbsolutePosition.Y) / scale + list.CanvasPosition.Y
        local height = frame.AbsoluteSize.Y / scale
        local view = list.AbsoluteWindowSize.Y / scale
        local limit = math.max(list.AbsoluteCanvasSize.Y / scale - view, 0)
        local y = math.clamp(top + height / 2 - view / 2, 0, limit)
        if math.abs(y - list.CanvasPosition.Y) > 2 then
            tween(list, { CanvasPosition = Vector2.new(0, y) }, 0.45, Enum.EasingStyle.Quint)
            task.wait(0.25)
        end
        if frame.Parent then
            self:_flash(frame, target._groupbox and 10 or 8)
        end
    end)
end

function Window:_resetSearch()
    if self.SearchBox and self.SearchBox.Text ~= "" then
        self.SearchBox.Text = ""
    end
end

-- Page titles stop short of the search box and close button.
function Window:_fitTitle(tab)
    local right = self.SearchBox and (self._searchWidth or SEARCH_WIDTH) + 72 or 56
    local reserve = tab._titleX + right
    tab._title.Size = UDim2.new(1, -reserve, 0, 24)
    if tab._desc then
        tab._desc.Size = UDim2.new(1, -reserve, 0, 16)
    end
end

function Window:_buildSearch(content)
    -- No box: the icon and text sit on a thin baseline. Focus draws an
    -- accent line out from the middle of it.
    local holder = create("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -56, 0, 14),
        Size = UDim2.fromOffset(SEARCH_WIDTH, 34),
        BackgroundColor3 = Theme.Background,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ZIndex = 5,
        Parent = content,
    })
    holder:SetAttribute("NoDrag", true)
    corner(holder, UDim.new(0, 8))
    local holderStroke = stroke(holder, Theme.Stroke, 0, 1)

    -- Kept for the focus handlers below, which recolour it.
    local _, icon = glowIcon(holder, "search", Theme.Muted, UDim2.new(0, 10, 0.5, 0))
    if icon and icon.Parent then
        icon.Parent.AnchorPoint = Vector2.new(0, 0.5)
        icon.Parent.Position = UDim2.new(0, 10, 0.5, 0)
        icon.Parent.Size = UDim2.fromOffset(14, 14)
    end
    local box = create("TextBox", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 30, 0.5, 0),
        Size = UDim2.new(1, -38, 1, -4),
        BackgroundTransparency = 1,
        Text = "",
        PlaceholderText = "Search",
        PlaceholderColor3 = Theme.Muted,
        TextColor3 = Theme.Text,
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ClearTextOnFocus = false,
        Parent = holder,
    })

    onTheme(holder, function()
        holder.BackgroundColor3 = Theme.Background
        holderStroke.Color = box:IsFocused() and Theme.Accent or Theme.Stroke
        box.PlaceholderColor3 = Theme.Muted
        box.TextColor3 = Theme.Text
        if not box:IsFocused() then
            icon.ImageColor3 = Theme.Muted
        else
            icon.ImageColor3 = Theme.Accent
        end
    end)

    holder.InputBegan:Connect(function(input)
        if isPress(input) and not box:IsFocused() then
            box:CaptureFocus()
        end
    end)

    holder.MouseEnter:Connect(function()
        if not box:IsFocused() then
            tween(holderStroke, { Color = Theme.StrokeHover }, 0.2)
            tween(icon, { ImageColor3 = Theme.Text }, 0.2)
        end
    end)
    holder.MouseLeave:Connect(function()
        if not box:IsFocused() then
            tween(holderStroke, { Color = Theme.Stroke }, 0.25)
            tween(icon, { ImageColor3 = Theme.Muted }, 0.25)
        end
    end)
    self.SearchBox = box

    -- Results float over the window under the box, like a dropdown popup.
    local rowHeight = TOUCH and 40 or 34
    local maxRows = 8
    local popup = create("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Size = UDim2.fromOffset(300, 0),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 45,
        Parent = self.Body,
    })
    popup:SetAttribute("NoDrag", true)
    local popupShadow = create("ImageLabel", {
        Position = UDim2.fromOffset(-18, -12),
        Size = UDim2.new(1, 36, 1, 36),
        BackgroundTransparency = 1,
        Image = Assets.Shadow,
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450),
        Parent = popup,
    })
    local panel = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = popup,
    })
    corner(panel, UDim.new(0, 10))
    local panelStroke = stroke(panel, Theme.Stroke, 1)
    edgeHighlight(panel)
    local list = create("ScrollingFrame", {
        Position = UDim2.fromOffset(6, 6),
        Size = UDim2.new(1, -12, 1, -12),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = TOUCH and 4 or 3,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0.4,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        CanvasSize = UDim2.new(),
        Parent = panel,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = list,
    })
    local noResults = label({
        Size = UDim2.new(1, 0, 0, rowHeight),
        Text = "No results",
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        LayoutOrder = 0,
        Visible = false,
        Parent = list,
    })

    local rows = {}
    local results = {}
    local selected = 1
    local open = false
    local generation = 0
    local shownSize = Vector2.new(300, 0)
    local stopFollowing = nil
    local closeResults

    local function place()
        local scale = self.Scale.Scale
        local bodyPosition = self.Body.AbsolutePosition
        local bodyWidth = self.Body.AbsoluteSize.X / scale
        local right = (holder.AbsolutePosition.X + holder.AbsoluteSize.X - bodyPosition.X) / scale
        local top = (holder.AbsolutePosition.Y + holder.AbsoluteSize.Y - bodyPosition.Y) / scale + 6
        right = math.clamp(right, shownSize.X + 8, math.max(bodyWidth - 8, shownSize.X + 8))
        popup.Position = UDim2.fromOffset(right, top)
    end

    local function measure()
        local scale = self.Scale.Scale
        local bodySize = self.Body.AbsoluteSize / scale
        local below = (holder.AbsolutePosition.Y + holder.AbsoluteSize.Y - self.Body.AbsolutePosition.Y) / scale + 6
        local count = math.max(#rows, 1)
        local height = math.min(count, maxRows) * (rowHeight + 2) - 2 + 12
        height = math.max(math.min(height, bodySize.Y - below - 12), rowHeight + 12)
        local width = math.min(math.max(holder.AbsoluteSize.X / scale, 300), math.max(bodySize.X - 16, 160))
        shownSize = Vector2.new(width, height)
    end

    local function paintSelection()
        for index, row in ipairs(rows) do
            local on = index == selected
            tween(row.Button, { BackgroundTransparency = on and 0.35 or 1 }, 0.12)
            tintIcon(row.Icon, on and Theme.Accent or Theme.Muted, on, 0.12)
        end
    end

    local function keepSelectionInView()
        local rowTop = (selected - 1) * (rowHeight + 2)
        local view = list.AbsoluteWindowSize.Y / self.Scale.Scale
        local y = list.CanvasPosition.Y
        if rowTop < y then
            y = rowTop
        elseif rowTop + rowHeight > y + view then
            y = rowTop + rowHeight - view
        else
            return
        end
        list.CanvasPosition = Vector2.new(0, math.max(y, 0))
    end

    local function setOpen(value)
        if value == open then
            return
        end
        open = value
        generation += 1
        local current = generation
        if value then
            if self._closePopup and self._closePopup ~= closeResults then
                self._closePopup()
            end
            self._closePopup = closeResults
            place()
            popup.Size = UDim2.fromOffset(shownSize.X, 0)
            popup.Visible = true
            tween(popup, { Size = UDim2.fromOffset(shownSize.X, shownSize.Y) }, 0.26, Enum.EasingStyle.Quint)
            tween(panelStroke, { Transparency = 0 }, 0.12)
            tween(popupShadow, { ImageTransparency = 0.55 }, 0.26)
            if not stopFollowing then
                stopFollowing = self:_listen("Render", place)
            end
        else
            if self._closePopup == closeResults then
                self._closePopup = nil
            end
            tween(popup, { Size = UDim2.fromOffset(shownSize.X, 0) }, 0.18, Enum.EasingStyle.Quint)
            tween(popupShadow, { ImageTransparency = 1 }, 0.14)
            task.delay(0.19, function()
                if generation == current and not open then
                    popup.Visible = false
                    panelStroke.Transparency = 1
                    if stopFollowing then
                        stopFollowing()
                        stopFollowing = nil
                    end
                end
            end)
        end
    end
    closeResults = function()
        setOpen(false)
    end

    local function choose(result)
        if not result then
            return
        end
        setOpen(false)
        box.Text = ""
        if box:IsFocused() then
            box:ReleaseFocus()
        end
        self:_revealResult(result)
    end

    local function escape(text)
        return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
    end

    local function render(query)
        for _, row in ipairs(rows) do
            row.Button:Destroy()
        end
        table.clear(rows)
        results = self:_searchResults(query)
        selected = 1
        local accent = colorToHex(Theme.Accent)
        for index, result in ipairs(results) do
            if index > 50 then
                break
            end
            local button = create("TextButton", {
                Size = UDim2.new(1, 0, 0, rowHeight),
                BackgroundColor3 = Theme.Surface3,
                BackgroundTransparency = 1,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = index,
                Parent = list,
            })
            corner(button, UDim.new(0, 7))
            -- One line of breadcrumbs: tab, sub tab and groupbox in muted
            -- text, each split by a chevron, ending on the match in accent.
            local crumbs = create("Frame", {
                Position = UDim2.fromOffset(10, 0),
                Size = UDim2.new(1, -20, 1, 0),
                BackgroundTransparency = 1,
                ClipsDescendants = true,
                Parent = button,
            })
            create("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                VerticalAlignment = Enum.VerticalAlignment.Center,
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 5),
                Parent = crumbs,
            })
            local part = 0
            local firstIcon = nil
            local function crumbIcon(icon)
                if not icon then
                    return
                end
                part += 1
                local image = create("ImageLabel", {
                    Size = UDim2.fromOffset(14, 14),
                    BackgroundTransparency = 1,
                    ImageColor3 = Theme.Muted,
                    ScaleType = Enum.ScaleType.Fit,
                    LayoutOrder = part,
                    Parent = crumbs,
                })
                applyIcon(image, icon)
                firstIcon = firstIcon or image
            end
            local function crumbText(text, color, rich)
                part += 1
                return label({
                    Size = UDim2.new(0, 0, 1, 0),
                    AutomaticSize = Enum.AutomaticSize.X,
                    Text = text,
                    RichText = rich == true,
                    TextSize = 13,
                    FontFace = color and Fonts.Medium or Fonts.Regular,
                    TextColor3 = color or Theme.Muted,
                    TextTruncate = Enum.TextTruncate.None,
                    LayoutOrder = part,
                    Parent = crumbs,
                })
            end
            local function chevron()
                crumbText(">")
            end
            local tab, sub, group = result.Tab, result.Sub, result.Group
            local onTab = result.Kind == "Tab"
            local onSub = result.Kind == "Page"
            local onGroup = result.Kind == "Groupbox"
            crumbIcon(tab._iconName or "layout-grid")
            if not onTab then
                crumbText(tab.Name)
                if sub then
                    chevron()
                    crumbIcon(sub._iconName or "layers")
                    if not onSub then
                        crumbText(sub.Name)
                    end
                end
                if group and not onGroup then
                    chevron()
                    crumbText(group.Name)
                end
                if not onSub then
                    chevron()
                end
            end
            -- The match itself: accent, with the typed part in bold.
            local name = result.Name
            local stop = result.At + #query
            local marked = escape(string.sub(name, 1, result.At - 1))
                .. "<b>" .. escape(string.sub(name, result.At, stop - 1)) .. "</b>"
                .. escape(string.sub(name, stop))
            crumbText(marked, Theme.Accent, true)
            local image = firstIcon
            local isTap = tapGuard(button, function()
                return list
            end)
            button.MouseEnter:Connect(function()
                if not usingTouch() then
                    selected = index
                    paintSelection()
                end
            end)
            button.MouseButton1Click:Connect(function()
                if isTap() then
                    choose(result)
                end
            end)
            table.insert(rows, { Button = button, Icon = image })
        end
        noResults.Visible = #rows == 0
        list.CanvasSize = UDim2.fromOffset(0, math.max(#rows, 1) * (rowHeight + 2) - 2)
        list.CanvasPosition = Vector2.zero
        paintSelection()
        measure()
        if open then
            place()
            tween(popup, { Size = UDim2.fromOffset(shownSize.X, shownSize.Y) }, 0.2, Enum.EasingStyle.Quint)
        end
    end

    local function update()
        local query = string.match(string.lower(box.Text), "^%s*(.-)%s*$")
        if query == "" then
            setOpen(false)
            return
        end
        render(query)
        setOpen(true)
    end

    box.Focused:Connect(function()
        local expandedWidth = math.min(math.floor((self._searchWidth or SEARCH_WIDTH) + 54), math.floor(content.AbsoluteSize.X / self.Scale.Scale - 200))
        tween(holder, { Size = UDim2.fromOffset(expandedWidth, 34) }, 0.35, Enum.EasingStyle.Quint)
        tween(holderStroke, { Color = Theme.Accent }, 0.2)
        tween(icon, { ImageColor3 = Theme.Accent }, 0.15)
        if box.Text ~= "" then
            update()
        end
    end)
    box.FocusLost:Connect(function(enterPressed)
        tween(holder, { Size = UDim2.fromOffset(self._searchWidth or SEARCH_WIDTH, 34) }, 0.30, Enum.EasingStyle.Quint)
        tween(holderStroke, { Color = Theme.Stroke }, 0.25)
        tween(icon, { ImageColor3 = Theme.Muted }, 0.25)
        if enterPressed and open then
            choose(results[selected])
        end
    end)
    box:GetPropertyChangedSignal("Text"):Connect(update)
    self:_listen("Began", function(input)
        if not open then
            return
        end
        if input.KeyCode == Enum.KeyCode.Up or input.KeyCode == Enum.KeyCode.Down then
            if #rows > 0 then
                local step = input.KeyCode == Enum.KeyCode.Up and -1 or 1
                selected = math.clamp(selected + step, 1, #rows)
                paintSelection()
                keepSelectionInView()
            end
        elseif input.KeyCode == Enum.KeyCode.Escape then
            setOpen(false)
        elseif isPress(input) then
            local point = pointerPosition()
            if not pointInside(point, popup) and not pointInside(point, holder) then
                setOpen(false)
            end
        end
    end)

    local function fit()
        local width = content.AbsoluteSize.X / self.Scale.Scale
        local searchWidth = math.clamp(math.floor(width * 0.32), 110, SEARCH_WIDTH)
        self._searchWidth = searchWidth
        if not box:IsFocused() then
            holder.Size = UDim2.fromOffset(searchWidth, 34)
        end
        for _, tab in ipairs(self.Tabs) do
            self:_fitTitle(tab)
        end
    end
    content:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
    task.defer(fit)
end

-- Identity: the player's name and headshot shown in the sidebar and on the
-- home tab. The privacy switches hide them everywhere at once.

function Window:_trackName(textLabel, kind)
    table.insert(self._identity.Names, { Label = textLabel, Kind = kind })
    self:_renderIdentity()
end

function Window:_trackAvatar(image, placeholder)
    table.insert(self._identity.Avatars, { Image = image, Placeholder = placeholder })
    self:_renderIdentity(true)
end

function Window:_renderIdentity(instant)
    for _, entry in ipairs(self._identity.Names) do
        if entry.Kind == "User" then
            entry.Label.Text = self._hideName and "@hidden" or ("@" .. LocalPlayer.Name)
        else
            entry.Label.Text = self._hideName and "Hidden" or LocalPlayer.DisplayName
        end
    end
    local duration = instant and 0 or 0.2
    for _, entry in ipairs(self._identity.Avatars) do
        tween(entry.Image, { ImageTransparency = self._hideAvatar and 1 or 0 }, duration)
        tween(entry.Placeholder, { ImageTransparency = self._hideAvatar and 0.2 or 1 }, duration)
    end
end

function Window:SetHideName(hidden)
    self._hideName = hidden == true
    self:_renderIdentity()
end

function Window:SetHideAvatar(hidden)
    self._hideAvatar = hidden == true
    self:_renderIdentity()
end

local function avatar(window, parent, props, ringColor, ringTransparency, ringThickness)
    local holder = create("Frame", {
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = parent,
    })
    for key, value in pairs(props) do
        holder[key] = value
    end
    corner(holder, UDim.new(1, 0))
    stroke(holder, ringColor or Theme.Stroke, ringTransparency or 0, ringThickness or 1)
    local image = create("ImageLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(LocalPlayer.UserId) .. "&w=150&h=150",
        Parent = holder,
    })
    corner(image, UDim.new(1, 0))
    local placeholder = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(0.45, 0.45),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Fit,
        Parent = holder,
    })
    applyIcon(placeholder, "user")
    window:_trackAvatar(image, placeholder)
    return holder
end

function Window:_buildProfile(sidebar)
    create("Frame", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -PROFILE_HEIGHT),
        Size = UDim2.new(1, -20, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        Parent = sidebar,
    })
    local card = create("TextButton", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -8),
        Size = UDim2.new(1, -16, 0, PROFILE_HEIGHT - 16),
        BackgroundColor3 = Theme.Surface2,
        BackgroundTransparency = 0,
        Text = "",
        AutoButtonColor = false,
        Parent = sidebar,
    })
    corner(card, UDim.new(0, 8))
    local cardStroke = stroke(card, Theme.Stroke, 0)
    local head = avatar(self, card, {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 8, 0.5, 0),
        Size = UDim2.fromOffset(32, 32),
    })
    local online = create("Frame", {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, 1, 1, 1),
        Size = UDim2.fromOffset(9, 9),
        BackgroundColor3 = Theme.Success,
        BorderSizePixel = 0,
        ZIndex = 2,
        Parent = head,
    })
    corner(online, UDim.new(1, 0))
    stroke(online, Theme.Surface2, 0, 2)
    local name = label({
        Position = UDim2.new(0, 48, 0.5, -15),
        Size = UDim2.new(1, -74, 0, 15),
        TextSize = 12,
        FontFace = Fonts.Bold,
        Parent = card,
    })
    self:_trackName(name, "Display")
    local gameLabel = label({
        Position = UDim2.new(0, 48, 0.5, 1),
        Size = UDim2.new(1, -74, 0, 13),
        Text = "…",
        TextSize = 11,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = card,
    })
    local chevron = create("ImageLabel", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ScaleType = Enum.ScaleType.Fit,
        Parent = card,
    })
    applyIcon(chevron, "chevron-right")
    task.spawn(function()
        gameLabel.Text = detectGameName()
    end)
    card.MouseEnter:Connect(function()
        if usingTouch() then
            return
        end
        tween(cardStroke, { Color = Theme.StrokeHover }, 0.12)
        tween(chevron, { ImageColor3 = Theme.Text, Position = UDim2.new(1, -6, 0.5, 0) }, 0.15)
    end)
    card.MouseLeave:Connect(function()
        tween(cardStroke, { Color = Theme.Stroke }, 0.2)
        tween(chevron, { ImageColor3 = Theme.Muted, Position = UDim2.new(1, -8, 0.5, 0) }, 0.2)
    end)
    card.MouseButton1Click:Connect(function()
        if self.Home then
            self:SelectTab(self.Home)
        end
    end)
    self.Profile = card
end

-- Server actions

function Window:Rejoin()
    self:Notify({ Title = "Rejoining", Content = "Teleporting back into this server", Icon = "refresh-cw", Duration = 3 })
    task.spawn(function()
        local ok, err = pcall(function()
            if #Players:GetPlayers() <= 1 or game.JobId == "" then
                TeleportService:Teleport(game.PlaceId, LocalPlayer)
            else
                TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
            end
        end)
        if not ok then
            self:Notify({ Title = "Rejoin failed", Content = tostring(err), Type = "Error", Duration = 4 })
        end
    end)
end

local function hopServers(window, order, pick, title)
    task.spawn(function()
        local servers = fetchServers(order)
        if not servers then
            window:Notify({ Title = title .. " failed", Content = "Could not load the server list", Type = "Error", Duration = 4 })
            return
        end
        local candidates = {}
        for _, server in ipairs(servers) do
            if type(server) == "table" and server.id ~= game.JobId then
                local playing, capacity = tonumber(server.playing), tonumber(server.maxPlayers)
                if playing and capacity and playing < capacity then
                    table.insert(candidates, server)
                end
            end
        end
        local target = #candidates > 0 and pick(candidates) or nil
        if not target then
            window:Notify({ Title = title .. " failed", Content = "No other open server found", Type = "Warning", Duration = 4 })
            return
        end
        window:Notify({
            Title = title,
            Content = string.format("Joining a server with %d/%d players", target.playing, target.maxPlayers),
            Icon = "server",
            Duration = 3,
        })
        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, target.id, LocalPlayer)
        end)
        if not ok then
            window:Notify({ Title = title .. " failed", Content = tostring(err), Type = "Error", Duration = 4 })
        end
    end)
end

function Window:ServerHop()
    hopServers(self, "Desc", function(list)
        return list[math.random(1, #list)]
    end, "Server hop")
end

function Window:JoinLowestServer()
    hopServers(self, "Asc", function(list)
        table.sort(list, function(a, b)
            return a.playing < b.playing
        end)
        return list[1]
    end, "Lowest server")
end

function Window:CopyToClipboard(text, what)
    local ok = copyToClipboard(text)
    self:Notify({
        Title = ok and "Copied" or "Clipboard unavailable",
        Content = ok and (what or tostring(text)) or "Your executor has no setclipboard",
        Type = ok and "Success" or "Error",
        Icon = ok and "clipboard-check" or nil,
        Duration = 2.5,
    })
    return ok
end

-- Home

-- Home reads top to bottom: a banner greeting the player, a performance card
-- with live graphs, the server and links side by side, and a status line.

-- A Home card that grows with its stacked contents.
function Window:_homeCard(parent, order)
    local card = panelCard(parent, 0, order)
    card.AutomaticSize = Enum.AutomaticSize.Y
    padding(card, 16, 16, 14, 14)
    create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = card })
    return card
end

-- A small caps heading at the top of a Home card.
function Window:_homeCaption(parent, text, order)
    return label({
        Size = UDim2.new(1, 0, 0, 22),
        Text = string.upper(text),
        TextSize = 10,
        TextColor3 = Theme.Muted,
        TextYAlignment = Enum.TextYAlignment.Top,
        LayoutOrder = order,
        Parent = parent,
    })
end

-- A rounded chip of an icon and short text. Returns the chip, its label and
-- its icon so callers can recolour them.
function Window:_homeChip(parent, order, icon, text, color)
    local chip = create("TextButton", {
        Size = UDim2.fromOffset(0, 24),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = order,
        Parent = parent,
    })
    corner(chip, UDim.new(0, 6))
    local chipStroke = stroke(chip)
    padding(chip, 8, 9)
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = chip,
    })
    local image = create("ImageLabel", {
        Size = UDim2.fromOffset(12, 12),
        BackgroundTransparency = 1,
        ImageColor3 = color or Theme.Muted,
        ScaleType = Enum.ScaleType.Fit,
        LayoutOrder = 1,
        Parent = chip,
    })
    applyIcon(image, icon)
    local text_ = label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = text,
        TextSize = 12,
        TextColor3 = color or Theme.Muted,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        Parent = chip,
    })
    return chip, text_, image, chipStroke
end

-- A chip that flips on press: on, it takes the accent; off, it sits muted.
function Window:_homeToggleChip(parent, order, icon, text, initial, callback)
    local chip, text_, image, chipStroke = self:_homeChip(parent, order, icon, text)
    local on = initial == true
    local function paint(duration)
        tween(chip, { BackgroundColor3 = on and Theme.Accent or Theme.Surface3, BackgroundTransparency = on and 0.85 or 0.2 }, duration)
        tween(chipStroke, { Color = on and Theme.Accent or Theme.Stroke, Transparency = on and 0.6 or 0 }, duration)
        tween(text_, { TextColor3 = on and Theme.Accent or Theme.Muted }, duration)
        tween(image, { ImageColor3 = on and Theme.Accent or Theme.Muted }, duration)
    end
    paint(0)
    chip.MouseButton1Click:Connect(function()
        on = not on
        paint(0.2)
        safeCall(callback, on)
    end)
    return chip
end

function Window:_homeProfile(list, opts, order)
    local banner = panelCard(list, 140, order)
    banner.ClipsDescendants = true

    -- The avatar bust stands on the banner's right edge and fades in from
    -- the left, so it reads as part of the card rather than a framed photo.
    local bust = create("ImageLabel", {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -16, 1, 0),
        Size = UDim2.fromOffset(140, 140),
        BackgroundTransparency = 1,
        Image = "rbxthumb://type=AvatarBust&id=" .. tostring(LocalPlayer.UserId) .. "&w=420&h=420",
        ScaleType = Enum.ScaleType.Fit,
        Parent = banner,
    })
    create("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.45, 0),
            NumberSequenceKeypoint.new(1, 0),
        }),
        Parent = bust,
    })
    local bustPlaceholder = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.6, 0.55),
        Size = UDim2.fromOffset(40, 40),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Fit,
        Parent = bust,
    })
    applyIcon(bustPlaceholder, "user")
    self:_trackAvatar(bust, bustPlaceholder)

    local textWidth = UDim2.new(1, -190, 0, 0)
    label({
        Position = UDim2.fromOffset(22, 20),
        Size = textWidth + UDim2.fromOffset(0, 14),
        Text = string.upper(opts.Welcome or "Welcome back"),
        TextSize = 10,
        TextColor3 = Theme.Muted,
        Parent = banner,
    })
    local nameLabel = label({
        Position = UDim2.fromOffset(22, 35),
        Size = textWidth + UDim2.fromOffset(0, 32),
        TextSize = 26,
        FontFace = Fonts.Bold,
        Parent = banner,
    })
    self:_trackName(nameLabel, "Display")
    local userLabel = label({
        Position = UDim2.fromOffset(22, 67),
        Size = textWidth + UDim2.fromOffset(0, 16),
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = banner,
    })
    self:_trackName(userLabel, "User")

    -- Chips along the bottom: tier, time left, then the privacy toggles.
    local chips = create("Frame", {
        Position = UDim2.new(0, 22, 1, -40),
        Size = UDim2.new(1, -44, 0, 24),
        BackgroundTransparency = 1,
        Parent = banner,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = chips,
    })
    local tier = opts.Tier
    if tier == nil then
        tier = "Free"
    end
    if tier then
        local tierChip, tierText, tierIcon = self:_homeChip(chips, 1, opts.TierIcon or self._logoIcon, tostring(tier), Theme.Accent)
        tierChip.Active = false
        tierText.FontFace = Fonts.Bold
        tierIcon.Size = UDim2.fromOffset(13, 13)
        self.TierLabel = tierText
    end
    local expiryChip, expiryText = self:_homeChip(chips, 2, "clock", "")
    expiryChip.Active = false
    expiryChip.Visible = false
    self:_homeToggleChip(chips, 3, "eye-off", "Name", self._hideName, function(on)
        self:SetHideName(on)
    end)
    self:_homeToggleChip(chips, 4, "user-x", "Avatar", self._hideAvatar, function(on)
        self:SetHideAvatar(on)
    end)

    local discordUrl = opts.Discord or opts.Invite
    if discordUrl then
        local title = opts.InviteTitle or opts.DiscordTitle or "Join Community"
        local commChip = create("TextButton", {
            Name = "CommunityChip",
            Size = UDim2.fromOffset(0, 24),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = Theme.Surface3,
            BackgroundTransparency = 0.5,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            ClipsDescendants = true,
            LayoutOrder = 5,
            Parent = chips,
        })
        corner(commChip, UDim.new(0, 6))
        local commStroke = stroke(commChip)

        local row = create("Frame", {
            Size = UDim2.fromScale(0, 1),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            ZIndex = 2,
            Parent = commChip,
        })
        padding(row, 8, 9)
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 6),
            Parent = row,
        })
        local commIcon = create("ImageLabel", {
            Size = UDim2.fromOffset(12, 12),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Text,
            ScaleType = Enum.ScaleType.Fit,
            LayoutOrder = 1,
            Parent = row,
        })
        applyIcon(commIcon, "message-circle")
        local commText = label({
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = title,
            TextSize = 12,
            TextColor3 = Theme.Text,
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = 2,
            Parent = row,
        })

        task.defer(function()
            if commChip and commChip.Parent then
                local w = math.max(commChip.AbsoluteSize.X / self.Scale.Scale, 100)
                commChip.Size = UDim2.fromOffset(w, 24)
                commChip.AutomaticSize = Enum.AutomaticSize.None
            end
        end)

        commChip.MouseEnter:Connect(function()
            tween(commChip, { BackgroundTransparency = 0 }, 0.15, Enum.EasingStyle.Quint)
            tween(commStroke, { Color = Theme.StrokeHover }, 0.15)
            tween(commIcon, { ImageColor3 = Theme.Accent }, 0.15)
        end)
        commChip.MouseLeave:Connect(function()
            tween(commChip, { BackgroundTransparency = 0.5 }, 0.25, Enum.EasingStyle.Quint)
            tween(commStroke, { Color = Theme.Stroke }, 0.25)
            tween(commIcon, { ImageColor3 = Theme.Text }, 0.25)
        end)
        commChip.MouseButton1Click:Connect(function()
            ripple(commChip)
            self:CopyToClipboard(discordUrl, "Community Invite")
        end)
    end

    return function()
        local value = opts.Expiry
        if type(value) == "function" then
            local ok, result = pcall(value)
            value = ok and result or nil
        end
        if type(value) == "number" then
            local left = value - os.time()
            expiryText.Text = left > 0 and (formatDuration(left) .. " left") or "Expired"
        elseif value ~= nil then
            expiryText.Text = tostring(value)
        end
        expiryChip.Visible = expiryText.Text ~= ""
    end
end

-- A large live readout with a short bar history under it. Returns the value
-- label and a push(value, color) that adds a sample.
function Window:_homeGraph(parent, order, icon, title, ceiling)
    local cell = create("Frame", {
        BackgroundTransparency = 1,
        LayoutOrder = order,
        Parent = parent,
    })
    local holder = glowIcon(cell, icon, Theme.Muted, UDim2.new(0, 0, 0, 7))
    holder.Size = UDim2.fromOffset(12, 12)
    label({
        Position = UDim2.fromOffset(18, 0),
        Size = UDim2.new(1, -18, 0, 14),
        Text = string.upper(title),
        TextSize = 10,
        TextColor3 = Theme.Muted,
        Parent = cell,
    })
    local value = label({
        Position = UDim2.fromOffset(0, 16),
        Size = UDim2.new(1, 0, 0, 28),
        Text = "…",
        TextSize = 24,
        FontFace = Fonts.Bold,
        RichText = true,
        Parent = cell,
    })
    local track = create("Frame", {
        Position = UDim2.fromOffset(0, 50),
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundTransparency = 1,
        Parent = cell,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = track,
    })
    local COUNT = 24
    local bars, samples = {}, {}
    for index = 1, COUNT do
        local bar = create("Frame", {
            Size = UDim2.new(1 / COUNT, -2, 0, 2),
            BackgroundColor3 = Theme.Surface3,
            BorderSizePixel = 0,
            LayoutOrder = index,
            Parent = track,
        })
        corner(bar, UDim.new(0, 2))
        bars[index] = bar
    end
    local function push(sample, color)
        table.insert(samples, sample)
        if #samples > COUNT then
            table.remove(samples, 1)
        end
        local top = ceiling or 1
        for _, s in ipairs(samples) do
            top = math.max(top, s)
        end
        local offset = COUNT - #samples
        for index, bar in ipairs(bars) do
            local s = samples[index - offset]
            local latest = index == COUNT
            local height = s and math.max(s / top, 0.08) or 0
            tween(bar, {
                Size = UDim2.new(1 / COUNT, -2, height, s and 0 or 2),
                BackgroundColor3 = (latest and color) or (s and Theme.Muted or Theme.Surface3),
                BackgroundTransparency = latest and 0 or (s and 0.6 or 0),
            }, 0.35, Enum.EasingStyle.Quint)
        end
    end
    return value, push
end

-- A small figure: value over a caps caption.
function Window:_homeFigure(parent, order, title)
    local cell = create("Frame", {
        BackgroundTransparency = 1,
        LayoutOrder = order,
        Parent = parent,
    })
    local value = label({
        Size = UDim2.new(1, -8, 0, 20),
        Text = "…",
        TextSize = 15,
        FontFace = Fonts.Bold,
        RichText = true,
        Parent = cell,
    })
    label({
        Position = UDim2.fromOffset(0, 21),
        Size = UDim2.new(1, -8, 0, 14),
        Text = string.upper(title),
        TextSize = 10,
        TextColor3 = Theme.Muted,
        Parent = cell,
    })
    return value
end

-- A square tile button: an icon over a short label.
function Window:_homeAction(parent, order, icon, text, callback)
    local button = create("TextButton", {
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ClipsDescendants = true,
        LayoutOrder = order,
        Parent = parent,
    })
    corner(button, UDim.new(0, 8))
    local buttonStroke = stroke(button)
    local image = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 11),
        Size = UDim2.fromOffset(16, 16),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Text,
        ScaleType = Enum.ScaleType.Fit,
        Parent = button,
    })
    applyIcon(image, icon)
    label({
        Position = UDim2.new(0, 4, 0, 32),
        Size = UDim2.new(1, -8, 0, 14),
        Text = text,
        TextSize = 11,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = button,
    })
    button.MouseEnter:Connect(function()
        tween(button, { BackgroundTransparency = 0 }, 0.15, Enum.EasingStyle.Quint)
        tween(buttonStroke, { Color = Theme.StrokeHover }, 0.15)
        tween(image, { ImageColor3 = Theme.Accent }, 0.15)
    end)
    button.MouseLeave:Connect(function()
        tween(button, { BackgroundTransparency = 0.5 }, 0.25, Enum.EasingStyle.Quint)
        tween(buttonStroke, { Color = Theme.Stroke }, 0.25)
        tween(image, { ImageColor3 = Theme.Text }, 0.25)
    end)
    button.MouseButton1Click:Connect(function()
        ripple(button)
        safeCall(callback)
    end)
    return button
end

function Window:_homeGame(parent, order)
    local card = self:_homeCard(parent, order)
    local head = create("Frame", {
        Size = UDim2.new(1, 0, 0, 46),
        BackgroundTransparency = 1,
        LayoutOrder = 1,
        Parent = card,
    })
    local icon = create("ImageLabel", {
        Size = UDim2.fromOffset(44, 44),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Image = "rbxthumb://type=GameIcon&id=" .. tostring(game.GameId) .. "&w=150&h=150",
        Parent = head,
    })
    corner(icon, UDim.new(0, 10))
    stroke(icon)
    local gameName = label({
        Position = UDim2.fromOffset(56, 3),
        Size = UDim2.new(1, -56, 0, 20),
        Text = "Loading",
        TextSize = 15,
        FontFace = Fonts.Bold,
        Parent = head,
    })
    local detail = label({
        Position = UDim2.fromOffset(56, 24),
        Size = UDim2.new(1, -56, 0, 16),
        Text = "",
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = head,
    })
    local owner = nil
    task.spawn(function()
        local info = fetchGameInfo()
        gameName.Text = info and info.Name or detectGameName()
        owner = info and type(info.Creator) == "table" and info.Creator.Name or nil
    end)

    local actions = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 2,
        Parent = card,
    })
    padding(actions, 0, 0, 12, 0)
    create("UIGridLayout", {
        CellPadding = UDim2.fromOffset(6, 6),
        CellSize = UDim2.new(0.25, -5, 0, 54),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = actions,
    })
    self:_homeAction(actions, 1, "refresh-cw", "Rejoin", function()
        self:Rejoin()
    end)
    self:_homeAction(actions, 2, "shuffle", "Hop", function()
        self:ServerHop()
    end)
    self:_homeAction(actions, 3, "users", "Lowest", function()
        self:JoinLowestServer()
    end)
    self:_homeAction(actions, 4, "copy", "Job ID", function()
        self:CopyToClipboard(game.JobId, "Job ID")
    end)

    -- The detail line keeps the player count live.
    return function()
        local count = #Players:GetPlayers() .. "/" .. Players.MaxPlayers .. " players"
        detail.Text = owner and ("by " .. owner .. "  ·  " .. count) or count
    end
end

-- One row of the links card: icon, title and text, and a round icon button.
function Window:_homeLink(card, order, icon, title, text, buttonIcon, callback)
    local row = create("Frame", {
        Size = UDim2.new(1, 0, 0, 46),
        BackgroundTransparency = 1,
        LayoutOrder = order,
        Parent = card,
    })
    create("Frame", {
        Name = "Rule",
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        Parent = row,
    })
    local holder = glowIcon(row, icon, Theme.Accent, UDim2.new(0, 0, 0.5, 0))
    holder.Size = UDim2.fromOffset(16, 16)
    local titleLabel = label({
        Position = UDim2.fromOffset(28, 6),
        Size = UDim2.new(1, -68, 0, 18),
        Text = title,
        TextSize = 13,
        Parent = row,
    })
    local textLabel = label({
        Position = UDim2.fromOffset(28, 24),
        Size = UDim2.new(1, -68, 0, 15),
        Text = text,
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = row,
    })
    local button = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(30, 30),
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Parent = row,
    })
    corner(button, UDim.new(0, 8))
    local buttonStroke = stroke(button)
    local image = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ScaleType = Enum.ScaleType.Fit,
        Parent = button,
    })
    applyIcon(image, buttonIcon)
    button.MouseEnter:Connect(function()
        tween(button, { BackgroundTransparency = 0 }, 0.15, Enum.EasingStyle.Quint)
        tween(buttonStroke, { Color = Theme.StrokeHover }, 0.15)
        tween(image, { ImageColor3 = Theme.Accent }, 0.15)
    end)
    button.MouseLeave:Connect(function()
        tween(button, { BackgroundTransparency = 0.5 }, 0.25, Enum.EasingStyle.Quint)
        tween(buttonStroke, { Color = Theme.Stroke }, 0.25)
        tween(image, { ImageColor3 = Theme.Muted }, 0.25)
    end)
    button.MouseButton1Click:Connect(function()
        safeCall(callback)
    end)
    return row, titleLabel, textLabel
end

-- Builds the links card into parent, or nothing when there are no links and
-- the feature list is off. Returns the card (or nil) and the feature refresh.
function Window:_homeLinks(parent, opts, order)
    local links = {}
    for _, link in ipairs(opts.Links or {}) do
        table.insert(links, link)
    end
    local features = opts.Features
    if #links == 0 and features == false then
        return nil, function() end
    end
    local card = self:_homeCard(parent, order)
    self:_homeCaption(card, "Feature", 0)
    for index, link in ipairs(links) do
        local action = type(link.Callback) == "function"
        self:_homeLink(card, index, link.Icon or "link", link.Title or "", link.Text or "", action and "arrow-up-right" or "copy", function()
            if action then
                safeCall(link.Callback)
            else
                self:CopyToClipboard(link.Copy or link.Text, link.Title)
            end
        end)
    end
    local refresh = function() end
    if features ~= false then
        if type(features) == "table" then
            self._featuresTitle = features.Title
            self._features = features.List or (#features > 0 and features or nil)
        end
        local _, _, text_ = self:_homeLink(card, 100,
            type(features) == "table" and features.Icon or "list-checks",
            type(features) == "table" and features.Title or "Feature list",
            "", "chevron-right", function()
                self:ShowFeatures()
            end)
        refresh = function()
            local desc = type(features) == "table" and features.Desc
            text_.Text = desc or (self:_featureSummary())
        end
        task.defer(refresh)
    end
    -- The first row needs no rule above it.
    local first = nil
    for _, child in ipairs(card:GetChildren()) do
        if child:IsA("Frame") and child:FindFirstChild("Rule") and (not first or child.LayoutOrder < first.LayoutOrder) then
            first = child
        end
    end
    if first then
        first.Rule.Visible = false
    end
    return card, refresh
end

-- A quiet status line under the cards: executor support on the left, the
-- hide key on the right.
function Window:_homeExecutor(list, opts, order)
    local line = create("Frame", {
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundTransparency = 1,
        LayoutOrder = order,
        Parent = list,
    })
    local executor, supported, message = executorReport(opts)
    local dot = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 4, 0.5, 0),
        Size = UDim2.fromOffset(7, 7),
        BackgroundColor3 = supported and Theme.Success or Theme.Warning,
        BorderSizePixel = 0,
        Parent = line,
    })
    corner(dot, UDim.new(1, 0))
    local left = create("Frame", {
        Position = UDim2.fromOffset(18, 0),
        Size = UDim2.new(1, -170, 1, 0),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Parent = line,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = left,
    })
    label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = executor,
        TextSize = 12,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 1,
        Parent = left,
    })
    label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = message,
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = supported and Theme.Muted or Theme.Warning,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        Parent = left,
    })

    local hint = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -2, 0.5, 0),
        Size = UDim2.fromOffset(0, 22),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Parent = line,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = hint,
    })
    label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = TOUCH and "Tap the pill or" or "Hide with",
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 1,
        Parent = hint,
    })
    local chip = create("Frame", {
        Size = UDim2.fromOffset(0, 20),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        LayoutOrder = 2,
        Parent = hint,
    })
    corner(chip, UDim.new(0, 5))
    stroke(chip)
    padding(chip, 6, 6)
    self._keyChipLabel = label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = keyName(self.Keybind),
        TextSize = 11,
        FontFace = Fonts.Bold,
        TextTruncate = Enum.TextTruncate.None,
        Parent = chip,
    })
end

-- Feature list: every control the script adds, grouped by tab, or a list the
-- script writes itself. Items that match a control jump to it when picked.

Window._featureKinds = {
    Toggle = true,
    Slider = true,
    Dropdown = true,
    Input = true,
    Keybind = true,
    ColorPicker = true,
    Stepper = true,
    Button = true,
    ButtonRow = true,
    OrderList = true,
}

function Window:_featureGroups()
    local found, byName = {}, {}
    for _, tab in ipairs(self.Tabs) do
        if tab ~= self.Home and tab._userVisible ~= false then
            local group = { Name = tab.Name, Icon = tab._iconName, Items = {} }
            for _, page in ipairs(tab._subTabs or { tab }) do
                local sub = page._isSubTab and page or nil
                local function add(name, element, box, path)
                    if type(name) ~= "string" or name == "" then
                        return
                    end
                    local item = {
                        Name = name,
                        Kind = element._type == "ButtonRow" and "Button" or element._type,
                        Path = path,
                        Result = { Tab = tab, Sub = sub, Target = element, Group = box },
                    }
                    table.insert(group.Items, item)
                    byName[string.lower(name)] = byName[string.lower(name)] or item
                end
                local function addElement(element, box, path)
                    if element._destroyed or not self._featureKinds[element._type] or (element._isShown and not element:_isShown()) then
                        return
                    end
                    if element._type == "ButtonRow" and element.Buttons then
                        for _, button in ipairs(element.Buttons) do
                            add(button.Label.Text, element, box, path)
                        end
                    else
                        add(element._searchName, element, box, path)
                    end
                end
                if not page._noSearch then
                    for _, element in ipairs(page._items or {}) do
                        addElement(element, nil, sub and sub.Name or nil)
                    end
                    for _, box in ipairs(page._groupboxes or {}) do
                        if box._userVisible ~= false and not box._manager then
                            for _, element in ipairs(box._items) do
                                addElement(element, box, sub and (sub.Name .. "  ›  " .. box.Name) or box.Name)
                            end
                        end
                    end
                end
            end
            if #group.Items > 0 then
                table.insert(found, group)
            end
        end
    end
    local custom = self._features
    if type(custom) ~= "table" then
        return found
    end
    -- A written list: groups of items, or bare items, which gather into one
    -- group where the first one appears.
    local function customItem(entry)
        if type(entry) ~= "table" then
            entry = { Name = entry }
        end
        local name = tostring(entry.Name or entry.Title or entry[1] or "")
        local link = byName[string.lower(name)]
        return {
            Name = name,
            Desc = entry.Desc or entry.Description,
            Tag = entry.Tag,
            Icon = entry.Icon,
            Kind = link and link.Kind,
            Path = link and link.Path,
            Result = link and link.Result,
            Callback = entry.Callback,
        }
    end
    local groups, loose = {}, nil
    for _, entry in ipairs(custom) do
        if type(entry) == "table" and type(entry.Items) == "table" then
            local group = { Name = tostring(entry.Name or entry.Title or "Features"), Icon = entry.Icon, Items = {} }
            for _, item in ipairs(entry.Items) do
                table.insert(group.Items, customItem(item))
            end
            table.insert(groups, group)
        else
            if not loose then
                loose = { Name = self._featuresTitle or "Features", Items = {} }
                table.insert(groups, loose)
            end
            table.insert(loose.Items, customItem(entry))
        end
    end
    return groups
end

function Window:_featureSummary()
    local groups = self:_featureGroups()
    local count = 0
    for _, group in ipairs(groups) do
        count += #group.Items
    end
    local text = count .. (count == 1 and " feature" or " features")
    if type(self._features) ~= "table" and #groups > 0 then
        text ..= " across " .. #groups .. (#groups == 1 and " tab" or " tabs")
    end
    return text, groups, count
end

-- Opens the feature list over the window. Search filters it; picking an item
-- linked to a control closes the list and jumps to that control.
function Window:ShowFeatures()
    if self._dialog then
        self._dialog.Close()
    end
    local summary, groups, total = self:_featureSummary()
    local PAD = 16
    local ROW = TOUCH and 44 or 38
    local body = self.Body

    local overlay = create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 40,
        Parent = body,
    })
    -- A canvas group so the whole list fades as one on open and close.
    local card_ = create("CanvasGroup", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 10),
        Size = UDim2.fromOffset(420, 460),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        Active = true,
        Parent = overlay,
    })
    corner(card_, UDim.new(0, 12))
    local cardStroke = stroke(card_, Theme.Stroke, 1)
    local cardScale = create("UIScale", { Scale = 0.94, Parent = card_ })
    local function fit()
        local scale = self.Scale.Scale
        local size = body.AbsoluteSize / scale
        card_.Size = UDim2.fromOffset(math.min(440, size.X - 24), math.min(480, size.Y - 24))
    end
    fit()
    local fitConnection = body:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

    local iconHolder = glowIcon(card_, "list-checks", Theme.Accent, UDim2.new(0, PAD, 0, PAD + 10))
    iconHolder.Size = UDim2.fromOffset(18, 18)
    label({
        Position = UDim2.fromOffset(PAD + 28, PAD),
        Size = UDim2.new(1, -(PAD * 2 + 28 + 36), 0, 18),
        Text = self._featuresTitle or "Features",
        TextSize = 15,
        Parent = card_,
    })
    label({
        Position = UDim2.fromOffset(PAD + 28, PAD + 19),
        Size = UDim2.new(1, -(PAD * 2 + 28 + 36), 0, 14),
        Text = summary,
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = card_,
    })
    local closeButton = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -(PAD - 6), 0, PAD - 6),
        Size = TOUCH and UDim2.fromOffset(40, 40) or UDim2.fromOffset(32, 32),
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Parent = card_,
    })
    corner(closeButton, UDim.new(0, 8))
    local closeIcon = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(16, 16),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ScaleType = Enum.ScaleType.Fit,
        Parent = closeButton,
    })
    applyIcon(closeIcon, "x")
    if closeIcon.Image == "" then
        closeIcon:Destroy()
        label({ Size = UDim2.fromScale(1, 1), Text = "×", TextSize = 20, TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Center, Parent = closeButton })
    end
    closeButton.MouseEnter:Connect(function()
        tween(closeButton, { BackgroundTransparency = 0.5 }, 0.12)
    end)
    closeButton.MouseLeave:Connect(function()
        tween(closeButton, { BackgroundTransparency = 1 }, 0.2)
    end)

    local top = PAD + 44
    local searchHolder = create("Frame", {
        Position = UDim2.fromOffset(PAD, top),
        Size = UDim2.new(1, -PAD * 2, 0, TOUCH and 36 or 32),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = card_,
    })
    corner(searchHolder, UDim.new(0, 7))
    local searchStroke = stroke(searchHolder)
    local _, searchIcon = glowIcon(searchHolder, "search", Theme.Muted, UDim2.new(0, 10, 0.5, 0))
    searchIcon.Parent.Size = UDim2.fromOffset(14, 14)
    local searchBox = create("TextBox", {
        Position = UDim2.fromOffset(32, 0),
        Size = UDim2.new(1, -40, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        PlaceholderText = "Search features",
        PlaceholderColor3 = Theme.Muted,
        TextColor3 = Theme.Text,
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ClearTextOnFocus = false,
        Parent = searchHolder,
    })
    searchBox.Focused:Connect(function()
        tween(searchStroke, { Color = Theme.StrokeHover }, 0.15)
        tween(searchIcon, { ImageColor3 = Theme.Accent }, 0.15)
    end)
    searchBox.FocusLost:Connect(function()
        tween(searchStroke, { Color = Theme.Stroke }, 0.2)
        tween(searchIcon, { ImageColor3 = Theme.Muted }, 0.2)
    end)
    top += (TOUCH and 36 or 32) + 10

    local scroller = create("ScrollingFrame", {
        Position = UDim2.fromOffset(PAD, top),
        Size = UDim2.new(1, -PAD * 2 + 6, 1, -(top + PAD - 4)),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = TOUCH and 4 or 3,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0.4,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        CanvasSize = UDim2.new(),
        Parent = card_,
    })
    local content = create("Frame", {
        Size = UDim2.new(1, -10, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = scroller,
    })
    local layout = create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = content,
    })
    -- Canvas sized by hand, as elsewhere, so it scrolls under UIScale.
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scroller.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y / self.Scale.Scale + 4)
    end)
    local noResults = label({
        Size = UDim2.new(1, 0, 0, 60),
        Text = total == 0 and "No features yet" or "No matches",
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        LayoutOrder = 0,
        Visible = total == 0,
        Parent = content,
    })

    local dialog = {}
    local closed = false
    local stopEscape = nil
    function dialog.Close()
        if closed then
            return
        end
        closed = true
        if self._dialog == dialog then
            self._dialog = nil
        end
        fitConnection:Disconnect()
        if stopEscape then
            -- Deferred: Close can run from inside the input dispatch loop.
            task.defer(stopEscape)
        end
        if searchBox:IsFocused() then
            searchBox:ReleaseFocus()
        end
        tween(overlay, { BackgroundTransparency = 1 }, 0.18)
        tween(card_, { Position = UDim2.new(0.5, 0, 0.5, 8), GroupTransparency = 1 }, 0.18, Enum.EasingStyle.Quint)
        tween(cardScale, { Scale = 0.96 }, 0.18, Enum.EasingStyle.Quint)
        tween(cardStroke, { Transparency = 1 }, 0.12)
        task.delay(0.2, function()
            overlay:Destroy()
        end)
    end

    local sections = {}
    local order = 0
    for _, group in ipairs(groups) do
        order += 1
        local header = create("Frame", {
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundTransparency = 1,
            LayoutOrder = order,
            Parent = content,
        })
        local headIcon = glowIcon(header, group.Icon or "layout-grid", Theme.Accent, UDim2.new(0, 2, 0, 18))
        headIcon.Size = UDim2.fromOffset(14, 14)
        label({
            Position = UDim2.fromOffset(24, 10),
            Size = UDim2.new(1, -70, 0, 16),
            Text = string.upper(group.Name),
            TextSize = 11,
            TextColor3 = Theme.Muted,
            Parent = header,
        })
        local countLabel = label({
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -4, 0, 10),
            Size = UDim2.new(0, 40, 0, 16),
            Text = tostring(#group.Items),
            TextSize = 11,
            TextColor3 = Theme.Muted,
            TextXAlignment = Enum.TextXAlignment.Right,
            Parent = header,
        })
        local section = { Header = header, Count = countLabel, Rows = {} }
        for _, item in ipairs(group.Items) do
            order += 1
            local sub = item.Desc or item.Path
            local clickable = item.Result ~= nil or type(item.Callback) == "function"
            local row = create("TextButton", {
                Size = UDim2.new(1, 0, 0, sub and ROW + 4 or ROW - 4),
                BackgroundColor3 = Theme.Surface2,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = order,
                Parent = content,
            })
            corner(row, UDim.new(0, 8))
            local rowIcon = glowIcon(row, item.Icon or self._searchIcons[item.Kind] or "check", Theme.Muted, UDim2.new(0, 10, 0.5, 0))
            rowIcon.Size = UDim2.fromOffset(14, 14)
            local right = 12 + (clickable and 22 or 0)
            local tag
            if item.Tag then
                tag = create("Frame", {
                    AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, -(clickable and 30 or 10), 0.5, 0),
                    Size = UDim2.fromOffset(0, 20),
                    AutomaticSize = Enum.AutomaticSize.X,
                    BackgroundColor3 = Theme.Accent,
                    BackgroundTransparency = 0.85,
                    BorderSizePixel = 0,
                    Parent = row,
                })
                corner(tag, UDim.new(0, 5))
                padding(tag, 7, 7)
                label({
                    Size = UDim2.new(0, 0, 1, 0),
                    AutomaticSize = Enum.AutomaticSize.X,
                    Text = tostring(item.Tag),
                    TextSize = 11,
                    TextColor3 = Theme.Accent,
                    TextTruncate = Enum.TextTruncate.None,
                    Parent = tag,
                })
            end
            local nameLabel = label({
                Position = UDim2.fromOffset(34, sub and 5 or 0),
                Size = UDim2.new(1, -(34 + right), 0, sub and 18 or ROW - 4),
                Text = item.Name,
                TextSize = 13,
                Parent = row,
            })
            local subLabel
            if sub then
                subLabel = label({
                    Position = UDim2.fromOffset(34, 23),
                    Size = UDim2.new(1, -(34 + right), 0, 14),
                    Text = sub,
                    TextSize = 11,
                    FontFace = Fonts.Regular,
                    TextColor3 = Theme.Muted,
                    Parent = row,
                })
            end
            if tag then
                local function reserveTag()
                    local width = 34 + right + tag.AbsoluteSize.X / self.Scale.Scale + 8
                    nameLabel.Size = UDim2.new(1, -width, 0, nameLabel.Size.Y.Offset)
                    if subLabel then
                        subLabel.Size = UDim2.new(1, -width, 0, 14)
                    end
                end
                tag:GetPropertyChangedSignal("AbsoluteSize"):Connect(reserveTag)
                task.defer(reserveTag)
            end
            if clickable then
                local go = create("ImageLabel", {
                    AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, -10, 0.5, 0),
                    Size = UDim2.fromOffset(14, 14),
                    BackgroundTransparency = 1,
                    ImageColor3 = Theme.Muted,
                    ImageTransparency = 0.4,
                    ScaleType = Enum.ScaleType.Fit,
                    Parent = row,
                })
                applyIcon(go, "arrow-up-right")
            end
            local isTap = tapGuard(row, function()
                return scroller
            end)
            row.MouseEnter:Connect(function()
                if not usingTouch() then
                    tween(row, { BackgroundTransparency = 0.3 }, 0.12)
                end
            end)
            row.MouseLeave:Connect(function()
                tween(row, { BackgroundTransparency = 1 }, 0.2)
            end)
            row.MouseButton1Click:Connect(function()
                if not clickable or not isTap() then
                    return
                end
                dialog.Close()
                if item.Result then
                    self:_revealResult(item.Result)
                end
                safeCall(item.Callback)
            end)
            table.insert(section.Rows, { Frame = row, Key = string.lower(item.Name .. " " .. (sub or "")) })
        end
        table.insert(sections, section)
    end

    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        local query = string.lower(searchBox.Text)
        local any = false
        for _, section in ipairs(sections) do
            local shown = 0
            for _, row in ipairs(section.Rows) do
                local match = query == "" or string.find(row.Key, query, 1, true) ~= nil
                row.Frame.Visible = match
                if match then
                    shown += 1
                end
            end
            section.Header.Visible = shown > 0
            section.Count.Text = tostring(shown)
            any = any or shown > 0
        end
        noResults.Visible = not any
        scroller.CanvasPosition = Vector2.zero
    end)
    closeButton.MouseButton1Click:Connect(dialog.Close)
    overlay.MouseButton1Click:Connect(dialog.Close)
    stopEscape = self:_listen("Began", function(input)
        if input.KeyCode == Enum.KeyCode.Escape then
            dialog.Close()
        end
    end)

    self._dialog = dialog
    tween(overlay, { BackgroundTransparency = 0.45 }, 0.25)
    tween(card_, { Position = UDim2.fromScale(0.5, 0.5), GroupTransparency = 0 }, 0.3, Enum.EasingStyle.Quint)
    tween(cardScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
    return dialog
end

function Window:_homeStats(list, opts, order, tab)
    local show = opts.Stats or { "Players", "Execs", "Session", "FPS", "Ping" }
    -- FPS and ping get large readouts with a bar history; every other stat
    -- is a small figure in the row under them.
    local card = self:_homeCard(list, order)
    local graphs = create("Frame", {
        Size = UDim2.new(1, 0, 0, 76),
        BackgroundTransparency = 1,
        LayoutOrder = 1,
        Parent = card,
    })
    create("UIGridLayout", {
        CellPadding = UDim2.fromOffset(24, 0),
        CellSize = UDim2.new(0.5, -12, 0, 76),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = graphs,
    })
    local rule = create("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        LayoutOrder = 2,
        Parent = card,
    })
    local figures = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 3,
        Parent = card,
    })
    padding(figures, 0, 0, 12, 0)
    local figureGrid = create("UIGridLayout", {
        CellPadding = UDim2.fromOffset(0, 8),
        CellSize = UDim2.new(0.25, 0, 0, 36),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = figures,
    })
    local values, sparks = {}, {}
    local graphCount, figureCount = 0, 0
    for index, name in ipairs(show) do
        local kind = STAT_TYPES[name]
        if kind and not values[name] then
            if name == "FPS" or name == "Ping" then
                graphCount += 1
                values[name], sparks[name] = self:_homeGraph(graphs, index, kind[1], kind[2], name == "FPS" and 60 or 100)
            else
                figureCount += 1
                values[name] = self:_homeFigure(figures, index, kind[2])
            end
        end
    end
    graphs.Visible = graphCount > 0
    figures.Visible = figureCount > 0
    rule.Visible = graphCount > 0 and figureCount > 0
    if graphCount == 0 then
        padding(figures, 0, 0, 0, 0)
    end
    local function fitFigures()
        local width = figures.AbsoluteSize.X / self.Scale.Scale
        local columns = math.clamp(figureCount, 1, width >= 440 and 5 or 3)
        figureGrid.CellSize = UDim2.new(1 / columns, 0, 0, 36)
    end
    figures:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitFigures)
    task.defer(fitFigures)

    if values.Executor then
        values.Executor.Text = detectExecutor()
    end
    if values.Game then
        values.Game.Text = "Loading"
        task.spawn(function()
            values.Game.Text = detectGameName()
        end)
    end
    if values.Region then
        values.Region.Text = "Loading"
        detectRegion(function(region)
            values.Region.Text = region
        end)
    end
    if values.Execs then
        local executions = bumpExecutions(opts.StatsFolder or self.ConfigFolder)
        values.Execs.Text = executions and tostring(executions) or "—"
    end
    if values.Friends then
        local friends = {}
        local function recount()
            local total = 0
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then
                    local known = friends[player.UserId]
                    if known == nil then
                        local ok, result = pcall(function()
                            return LocalPlayer:IsFriendsWith(player.UserId)
                        end)
                        known = ok and result == true
                        friends[player.UserId] = known
                    end
                    if known then
                        total += 1
                    end
                end
            end
            values.Friends.Text = tostring(total)
        end
        task.spawn(recount)
        table.insert(self._connections, Players.PlayerAdded:Connect(function()
            task.spawn(recount)
        end))
        table.insert(self._connections, Players.PlayerRemoving:Connect(function()
            task.defer(recount)
        end))
    end

    local session = values.Session or values.Uptime
    local started = os.clock()
    local frames = 0
    self:_listen("Render", function()
        frames += 1
    end)
    -- FPS, ping and memory are tinted by how healthy they are, unless the
    -- script turns that off with StatColors = false.
    local tinted = opts.StatColors ~= false
    local function tint(valueLabel, color)
        if tinted and valueLabel.TextColor3 ~= color then
            tween(valueLabel, { TextColor3 = color }, 0.3)
        end
    end
    return function()
        if values.FPS then
            values.FPS.Text = tostring(frames)
            tint(values.FPS, Library._healthColor(frames, 50, 30))
            sparks.FPS(frames, Library._healthColor(frames, 50, 30))
        end
        frames = 0
        if values.Ping then
            local ok, ping = pcall(function()
                return math.floor(LocalPlayer:GetNetworkPing() * 1000)
            end)
            ping = ok and ping or 0
            values.Ping.Text = ping .. "ms"
            tint(values.Ping, Library._healthColor(ping, 90, 180, true))
            sparks.Ping(ping, Library._healthColor(ping, 90, 180, true))
        end
        if values.Players then
            values.Players.Text = #Players:GetPlayers() .. "/" .. Players.MaxPlayers
        end
        if session then
            session.Text = formatDuration(os.clock() - started)
        end
        if values.Time then
            values.Time.Text = os.date(opts.TimeFormat or "%H:%M")
        end
        if values.ServerAge then
            values.ServerAge.Text = formatDuration(workspace.DistributedGameTime)
        end
        if values.Memory then
            local ok, memory = pcall(function()
                return StatsService:GetTotalMemoryUsageMb()
            end)
            values.Memory.Text = ok and string.format("%d MB", memory) or "—"
            tint(values.Memory, ok and Library._healthColor(memory, 1500, 3000, true) or Theme.Text)
        end
    end, function()
        frames = 0
    end
end

local function homePage(sub, page)
    local list = sub.List
    if type(page.Content) == "string" then
        local card_ = panelCard(list, 0, 1)
        card_.AutomaticSize = Enum.AutomaticSize.Y
        padding(card_, 16, 16, 14, 16)
        label({
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Text = page.Content,
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextWrapped = true,
            TextTruncate = Enum.TextTruncate.None,
            TextYAlignment = Enum.TextYAlignment.Top,
            Parent = card_,
        })
    end
    if type(page.Entries) == "table" then
        for index, entry in ipairs(page.Entries) do
            local card_ = panelCard(list, 0, index + 1)
            card_.AutomaticSize = Enum.AutomaticSize.Y
            padding(card_, 16, 16, 14, 16)
            create("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 6),
                Parent = card_,
            })
            local head = create("Frame", {
                Size = UDim2.new(1, 0, 0, 20),
                BackgroundTransparency = 1,
                LayoutOrder = 1,
                Parent = card_,
            })
            label({
                Size = UDim2.new(1, -90, 1, 0),
                Text = entry.Title or entry.Version or "Update",
                TextSize = 15,
                Parent = head,
            })
            if entry.Date or entry.Tag then
                local chip = create("Frame", {
                    AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, 0, 0.5, 0),
                    Size = UDim2.fromOffset(0, 20),
                    AutomaticSize = Enum.AutomaticSize.X,
                    BackgroundColor3 = Theme.Surface,
                    BorderSizePixel = 0,
                    Parent = head,
                })
                corner(chip, UDim.new(0, 5))
                stroke(chip)
                padding(chip, 8, 8)
                label({
                    Size = UDim2.new(0, 0, 1, 0),
                    AutomaticSize = Enum.AutomaticSize.X,
                    Text = entry.Tag or entry.Date,
                    TextSize = 11,
                    TextColor3 = Theme.Muted,
                    TextTruncate = Enum.TextTruncate.None,
                    Parent = chip,
                })
            end
            local body = entry.Content or entry.Body
            if type(entry.Changes) == "table" then
                body = "• " .. table.concat(entry.Changes, "\n• ")
            end
            if body then
                label({
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    Text = body,
                    TextSize = 13,
                    FontFace = Fonts.Regular,
                    TextColor3 = Theme.Muted,
                    TextWrapped = true,
                    TextTruncate = Enum.TextTruncate.None,
                    TextYAlignment = Enum.TextYAlignment.Top,
                    LayoutOrder = 2,
                    Parent = card_,
                })
            end
        end
    end
    if type(page.Build) == "function" then
        safeCall(page.Build, sub, list)
    else
        sub._noSearch = true
    end
end

function Window:_buildHome(opts)
    self._hideName = opts.HideName == true
    self._hideAvatar = opts.HideAvatar == true
    self:_renderIdentity(true)
    local tab = self:Tab({
        Name = opts.Name or "Home",
        Desc = opts.Desc,
        Icon = opts.Icon or "house",
        PageTitle = opts.Title or "Home",
    })
    tab._order = 100
    self.Home = tab

    local pages = opts.Pages or opts.Tabs
    local overview = tab
    if type(pages) == "table" and #pages > 0 then
        overview = tab:SubTab({ Name = opts.OverviewName or "Overview", Icon = opts.TabIcon or "layout-grid" })
    end
    overview._noSearch = true
    overview._order = 100
    local list = overview.List

    local refreshExpiry = self:_homeProfile(list, opts, 1)
    local refreshStats, resetStats = self:_homeStats(list, opts, 2, tab)

    -- Server and links side by side, stacked when narrow.
    local split = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 3,
        Parent = list,
    })
    local splitLayout = create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 10),
        Parent = split,
    })
    local function column(order_)
        local frame = create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            LayoutOrder = order_,
            Parent = split,
        })
        create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = frame })
        return frame
    end
    local leftColumn, rightColumn = column(1), column(2)
    local refreshGame = self:_homeGame(leftColumn, 1)
    local linksCard, refreshFeatures = self:_homeLinks(rightColumn, opts, 1)
    if not linksCard then
        rightColumn:Destroy()
    end
    local function fitSplit()
        local wide = linksCard ~= nil and split.AbsoluteSize.X / self.Scale.Scale >= 540
        splitLayout.FillDirection = wide and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
        local size = wide and UDim2.new(0.5, -5, 0, 0) or UDim2.new(1, 0, 0, 0)
        leftColumn.Size = size
        if linksCard then
            rightColumn.Size = size
        end
    end
    split:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitSplit)
    task.defer(fitSplit)

    self:_homeExecutor(list, opts, 4)

    if type(pages) == "table" then
        for _, page in ipairs(pages) do
            homePage(tab:SubTab({ Name = page.Name or page.Title or "Page", Icon = page.Icon }), page)
        end
    end

    refreshExpiry()
    refreshStats()
    refreshGame()
    task.spawn(function()
        while not self._destroyed and tab._page.Parent do
            task.wait(1)
            if self.Open and self.CurrentTab == tab then
                refreshStats()
                refreshExpiry()
                refreshGame()
                refreshFeatures()
            else
                resetStats()
            end
        end
    end)
    return tab
end

function Window:Tab(opts, icon)
    opts = normalize(opts, { Title = "Name", Description = "Desc" })
    if icon ~= nil and opts.Icon == nil then
        opts.Icon = icon
    end
    local tab = setmetatable({
        Name = opts.Name or "Tab",
        Window = self,
        _order = 0,
    }, Tab)

    local button = create("TextButton", {
        Size = UDim2.new(1, 0, 0, TAB_TILE_HEIGHT),
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = #self.Tabs + 1,
        Parent = self._tabStack,
    })
    corner(button, UDim.new(0, 7))
    local buttonStroke = stroke(button, Theme.Stroke, 1)
    buttonStroke.Enabled = false
    tab._button = button

    local hasIcon = opts.Icon ~= nil
    if hasIcon then
        local iconImage = create("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0, 20, 0.5, 0),
            Size = UDim2.fromOffset(16, 16),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Muted,
            ScaleType = Enum.ScaleType.Fit,
            Parent = button,
        })
        applyIcon(iconImage, opts.Icon)
        if iconImage:GetAttribute("CustomIcon") then
            iconImage.ImageTransparency = 0.4
        end
        tab._icon = iconImage
    end
    tab._label = label({
        Position = UDim2.fromOffset(hasIcon and 38 or 14, 0),
        Size = UDim2.new(1, hasIcon and -46 or -22, 1, 0),
        Text = tab.Name,
        TextSize = 13,
        TextColor3 = Theme.Muted,
        Parent = button,
    })

    local page = create("Frame", {
        Name = tab.Name,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        Parent = self.Content,
    })
    tab._page = page
    local titleX = 24
    if hasIcon then
        local holder = glowIcon(page, opts.Icon, Theme.Accent, UDim2.new(0, 24, 0, 32))
        holder.Size = UDim2.fromOffset(20, 20)
        titleX = 54
    end
    tab._titleX = titleX
    tab._title = label({
        Position = UDim2.fromOffset(titleX, 20),
        Size = UDim2.new(1, -titleX, 0, 24),
        Text = opts.PageTitle or tab.Name,
        TextSize = 22,
        Parent = page,
    })
    if opts.Desc then
        tab._desc = label({
            Position = UDim2.fromOffset(titleX, 44),
            Size = UDim2.new(1, -titleX, 0, 16),
            Text = opts.Desc,
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            Parent = page,
        })
    end
    local listTop = opts.Desc and 70 or 58
    tab._headerBottom = listTop
    tab._iconName = opts.Icon
    buildContainer(tab, page, listTop, opts.Icon or "layout-grid", opts.EmptyText or "Nothing here yet")

    local pressScale = create("UIScale", { Parent = button })
    local function release()
        tween(pressScale, { Scale = 1 }, 0.3, Enum.EasingStyle.Quint)
    end
    button.MouseEnter:Connect(function()
        if self.CurrentTab ~= tab and not usingTouch() then
            tween(button, { BackgroundTransparency = 0.75 }, 0.2, Enum.EasingStyle.Quint)
            tween(tab._label, { TextColor3 = Theme.Text }, 0.2)
            if tab._icon then
                tintIcon(tab._icon, Theme.Text, true, 0.2)
            end
        end
    end)
    button.MouseLeave:Connect(function()
        release()
        if self.CurrentTab ~= tab then
            tween(button, { BackgroundTransparency = 1 }, 0.3, Enum.EasingStyle.Quint)
            tween(tab._label, { TextColor3 = Theme.Muted }, 0.3)
            if tab._icon then
                tintIcon(tab._icon, Theme.Muted, false, 0.3)
            end
        end
    end)
    button.MouseButton1Down:Connect(function()
        tween(pressScale, { Scale = 0.97 }, 0.15, Enum.EasingStyle.Quint)
    end)
    button.MouseButton1Up:Connect(release)
    local isTap = tapGuard(button, function()
        return self.TabList
    end)
    button.MouseButton1Click:Connect(function()
        release()
        if isTap() then
            self:SelectTab(tab)
        end
    end)
    tab._stroke = buttonStroke
    self:_fitTitle(tab)

    if not self._introDone then
        button.Visible = false
    end
    table.insert(self.Tabs, tab)
    if #self.Tabs == 1 then
        task.defer(function()
            if not self.CurrentTab then
                self:SelectTab(tab)
            end
        end)
    end
    return tab
end

Window.CreateTab = Window.Tab

function Tab:Select()
    self.Window:SelectTab(self)
end

-- Cloud configs: a tab for browsing, previewing, installing and publishing
-- configs other players shared. The library draws it; OnFetch, OnPublish and
-- the other callbacks are the script's backend. Favorites, installs and the
-- sort order are remembered in the script's settings file.
function Window:CloudConfigs(opts)
    opts = normalize(opts, { Title = "Name", Description = "Desc" })
    local window = self
    local tab = self:Tab({
        Name = opts.Name or "Cloud",
        Desc = opts.Desc,
        Icon = opts.Icon or "cloud",
        PageTitle = opts.PageTitle,
    })
    tab._noSearch = true
    tab.List.Visible = false
    if tab._empty then
        tab._empty:Destroy()
        tab._empty = nil
    end

    local CARD = 116
    local ROW = TOUCH and 36 or 32
    local CHIP = TOUCH and 30 or 26
    local SORTS = { "Popular", "New", "Top", "Installs" }
    local SORT_NAMES = { Popular = "Popular", New = "Newest", Top = "Top rated", Installs = "Most installed" }
    local FILTERS = { "All", "Favorites", "Mine", "Installed" }
    local NAME_LIMIT = 40
    local DESC_LIMIT = math.max(math.floor(tonumber(opts.DescriptionLimit) or 300), 20)
    local pageSize = math.max(math.floor(tonumber(opts.PageSize) or 20), 1)
    local tagList = type(opts.Tags) == "table" and opts.Tags or {}
    local maxTags = math.max(math.floor(tonumber(opts.MaxTags) or 3), 0)
    local anonName = tostring(opts.StreamerName or "Ouroboros User")

    local cloud = { Tab = tab }
    local records, byId = {}, {}
    local cards = {}
    local hasMore, page, token = false, 0, 0
    local loading = false
    local query = { Search = "", Sort = "Popular", Filter = "All", Tag = nil }
    local views, currentView = {}, nil
    local detail, detailRecord, detailToken = {}, nil, 0

    local stored = window:_readConfigSettings()
    local favorites = type(stored.CloudFavorites) == "table" and stored.CloudFavorites or {}
    local installed = type(stored.CloudInstalled) == "table" and stored.CloudInstalled or {}
    if table.find(SORTS, stored.CloudSort) then
        query.Sort = stored.CloudSort
    elseif table.find(SORTS, opts.Sort) then
        query.Sort = opts.Sort
    end
    local function persist(key, value)
        window:_writeConfigSettings({ [key] = value })
    end

    local function notify(ok, title, detail_)
        window:Notify({ Title = title, Content = detail_, Type = ok and "Success" or "Error", Duration = 3 })
    end

    -- The Home tab's hide-name switch doubles as streamer mode.
    local function streamerOn()
        return window._hideName == true
    end

    -- Records

    local function countFlags(code)
        local data = type(code) == "string" and window:DecodeConfig(code)
        if not data then
            return nil
        end
        local count = 0
        for _ in pairs(data) do
            count += 1
        end
        return count
    end

    local function compact(number)
        number = math.max(math.floor(tonumber(number) or 0), 0)
        if number >= 1e6 then
            return (("%.1f"):format(number / 1e6):gsub("%.0$", "")) .. "m"
        elseif number >= 1e3 then
            return (("%.1f"):format(number / 1e3):gsub("%.0$", "")) .. "k"
        end
        return tostring(number)
    end

    local function ago(stamp)
        stamp = tonumber(stamp)
        if not stamp then
            return nil
        end
        local delta = os.time() - stamp
        if delta < 60 then
            return "just now"
        elseif delta < 3600 then
            return math.floor(delta / 60) .. "m ago"
        elseif delta < 86400 then
            return math.floor(delta / 3600) .. "h ago"
        elseif delta < 604800 then
            return math.floor(delta / 86400) .. "d ago"
        elseif delta < 2592000 then
            return math.floor(delta / 604800) .. "w ago"
        end
        return os.date("%d %b %Y", stamp)
    end

    local function escape(text)
        return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;"))
    end

    -- Rich text with every match of the search drawn in the accent.
    local function highlight(text)
        local needle = string.lower(query.Search)
        if needle == "" then
            return escape(text)
        end
        local lower = string.lower(text)
        local hex = colorToHex(Theme.Accent)
        local out, from = {}, 1
        while true do
            local first, last = string.find(lower, needle, from, true)
            if not first then
                break
            end
            table.insert(out, escape(text:sub(from, first - 1)))
            table.insert(out, ('<font color="#%s"><b>%s</b></font>'):format(hex, escape(text:sub(first, last))))
            from = last + 1
        end
        table.insert(out, escape(text:sub(from)))
        return table.concat(out)
    end

    local function normalizeRecord(raw)
        if type(raw) ~= "table" then
            return nil
        end
        local id = raw.Id ~= nil and tostring(raw.Id) or HttpService:GenerateGUID(false)
        local record = byId[id] or { Id = id }
        for key, value in pairs(raw) do
            if key ~= "Id" then
                record[key] = value
            end
        end
        record.Name = tostring(record.Name or "Untitled")
        record.Author = tostring(record.Author or "Unknown")
        record.Description = record.Description ~= nil and tostring(record.Description) or ""
        local tags = {}
        for _, tag in ipairs(type(record.Tags) == "table" and record.Tags or {}) do
            table.insert(tags, tostring(tag))
        end
        record.Tags = tags
        record.Installs = tonumber(record.Installs) or 0
        record.Likes = tonumber(record.Likes) or 0
        record.Updated = tonumber(record.Updated or record.Created)
        record.Liked = record.Liked == true
        if type(record.Code) ~= "string" or record.Code == "" then
            record.Code = nil
        end
        record.Count = tonumber(record.Count) or countFlags(record.Code)
        record.Mine = record.Mine == true or tonumber(record.AuthorId) == LocalPlayer.UserId or tonumber(record.OwnerId) == LocalPlayer.UserId
        byId[id] = record
        return record
    end

    local function publicRecord(record)
        return {
            Id = record.Id,
            Name = record.Name,
            Description = record.Description,
            Author = record.Author,
            AuthorId = record.AuthorId,
            Tags = table.clone(record.Tags),
            Installs = record.Installs,
            Likes = record.Likes,
            Liked = record.Liked,
            Updated = record.Updated,
            Code = record.Code,
            Count = record.Count,
            Folder = record.Folder,
            Mine = record.Mine,
        }
    end

    -- What is kept locally for favorites and installs: no code, it is refetched.
    local function summary(record)
        local kept = publicRecord(record)
        kept.Code = nil
        kept.Liked = nil
        return kept
    end

    local function installState(record)
        local mark = installed[record.Id]
        if type(mark) ~= "table" then
            return nil
        end
        if record.Updated and tonumber(mark.Updated) and record.Updated > tonumber(mark.Updated) then
            return "Update"
        end
        return "Installed"
    end

    local function otherScript(record)
        return type(record.Folder) == "string" and record.Folder ~= window.ConfigFolder
    end

    -- Small pieces

    local function iconButton(parent, icon, glyph, size, plain)
        local button = create("TextButton", {
            Size = UDim2.fromOffset(size, size),
            BackgroundColor3 = Theme.Surface2,
            BackgroundTransparency = plain and 1 or 0,
            Text = "",
            AutoButtonColor = false,
            Parent = parent,
        })
        corner(button, UDim.new(0, 8))
        if not plain then
            hoverStroke(button, stroke(button))
        end
        local image = create("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(15, 15),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Muted,
            ScaleType = Enum.ScaleType.Fit,
            Parent = button,
        })
        applyIcon(image, icon)
        if image.Image == "" then
            image:Destroy()
            image = label({
                Size = UDim2.fromScale(1, 1),
                Text = glyph,
                TextSize = 15,
                TextColor3 = Theme.Muted,
                TextXAlignment = Enum.TextXAlignment.Center,
                TextTruncate = Enum.TextTruncate.None,
                Parent = button,
            })
        end
        return button, image
    end

    local function primary(button, text_)
        tween(button, { BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.12 }, 0)
        tween(text_, { TextColor3 = Theme.AccentDark }, 0)
        text_.FontFace = Fonts.Bold
    end

    local function clear(parent)
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("GuiObject") then
                child:Destroy()
            end
        end
    end

    local function chip(parent, text, order, onClick)
        local button = create("TextButton", {
            Size = UDim2.fromOffset(0, CHIP),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = Theme.Surface2,
            Text = "",
            AutoButtonColor = false,
            LayoutOrder = order,
            Parent = parent,
        })
        button:SetAttribute("NoDrag", true)
        corner(button, UDim.new(1, 0))
        local chipStroke = stroke(button)
        padding(button, 12, 12)
        local text_ = label({
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = text,
            TextSize = 12,
            TextColor3 = Theme.Muted,
            TextTruncate = Enum.TextTruncate.None,
            Parent = button,
        })
        local object = { Button = button, Label = text_ }
        function object.Set(on, instant)
            local duration = instant and 0 or 0.15
            tween(button, { BackgroundColor3 = on and Theme.Accent or Theme.Surface2 }, duration)
            tween(text_, { TextColor3 = on and Theme.AccentDark or Theme.Muted }, duration)
            tween(chipStroke, { Transparency = on and 1 or 0 }, duration)
        end
        if onClick then
            button.MouseButton1Click:Connect(onClick)
        else
            button.Active = false
        end
        return object
    end

    local function tagPill(parent, text, order)
        local pill = label({
            Size = UDim2.fromOffset(0, 18),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = Theme.Surface3,
            BackgroundTransparency = 0.2,
            Text = text,
            TextSize = 11,
            TextColor3 = Theme.Muted,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = order,
            Parent = parent,
        })
        corner(pill, UDim.new(0, 5))
        padding(pill, 7, 7)
        return pill
    end

    local function hlist(parent, gap, wraps)
        return create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, gap),
            Wraps = wraps == true,
            Parent = parent,
        })
    end

    local function vlist(parent, gap)
        return create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, gap),
            Parent = parent,
        })
    end

    local function wrapped(parent, text, size, color, order, font)
        return label({
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Text = text,
            TextSize = size,
            FontFace = font or Fonts.Regular,
            TextColor3 = color or Theme.Text,
            TextWrapped = true,
            TextTruncate = Enum.TextTruncate.None,
            TextYAlignment = Enum.TextYAlignment.Top,
            LayoutOrder = order,
            Parent = parent,
        })
    end

    local function scroller(parent, visible)
        local frame = create("ScrollingFrame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = Theme.Accent,
            ScrollBarImageTransparency = 0.4,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            CanvasSize = UDim2.new(),
            Visible = visible ~= false,
            Parent = parent,
        })
        frame:SetAttribute("NoDrag", true)
        return frame
    end

    -- A text box on the surface colour. Multi-line boxes show a counter.
    local function field(parent, order, placeholder, height, limit)
        local multi = height > ROW
        local holder = create("Frame", {
            Size = UDim2.new(1, 0, 0, height),
            BackgroundColor3 = Theme.Surface,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            LayoutOrder = order,
            Parent = parent,
        })
        corner(holder, UDim.new(0, 8))
        local holderStroke = stroke(holder)
        local box = create("TextBox", {
            Position = UDim2.fromOffset(10, multi and 8 or 0),
            Size = UDim2.new(1, -20, 1, multi and -24 or 0),
            BackgroundTransparency = 1,
            Text = "",
            PlaceholderText = placeholder,
            PlaceholderColor3 = Theme.Muted,
            TextColor3 = Theme.Text,
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = multi and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
            MultiLine = multi,
            TextWrapped = multi,
            ClearTextOnFocus = false,
            Parent = holder,
        })
        local counter = multi and label({
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -10, 1, -4),
            Size = UDim2.fromOffset(0, 14),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = "",
            TextSize = 11,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextTruncate = Enum.TextTruncate.None,
            Parent = holder,
        })
        box.Focused:Connect(function()
            tween(holderStroke, { Color = Theme.StrokeHover }, 0.15)
        end)
        box.FocusLost:Connect(function()
            tween(holderStroke, { Color = Theme.Stroke }, 0.2)
        end)
        box:GetPropertyChangedSignal("Text"):Connect(function()
            local text = box.Text
            local length = utf8.len(text) or #text
            if limit and length > limit then
                local cut = utf8.offset(text, limit + 1)
                box.Text = cut and text:sub(1, cut - 1) or text:sub(1, limit)
                return
            end
            if counter then
                counter.Text = limit and (length .. "/" .. limit) or ""
            end
        end)
        if counter and limit then
            counter.Text = "0/" .. limit
        end
        return box, holderStroke
    end

    local function uniqueName(base)
        base = trim((tostring(base or ""):gsub('[\\/:%*%?"<>|]', "")))
        if base == "" then
            base = "Cloud config"
        end
        local name, index = base, 2
        while window:ConfigExists(name) do
            name = ("%s (%d)"):format(base, index)
            index += 1
        end
        return name
    end

    -- Layout: the page holds three views that slide over each other.

    local top = tab._headerBottom
    -- One pixel wider than the content on every side: root clips the slide,
    -- and the strokes along its edges would be clipped with it.
    local root = create("Frame", {
        Position = UDim2.fromOffset(23, top - 1),
        Size = UDim2.new(1, -46, 1, -(top + 14)),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Parent = tab._page,
    })
    for _, name in ipairs({ "Browse", "Detail", "Publish" }) do
        views[name] = create("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Visible = false,
            Parent = root,
        })
        padding(views[name], 1, 1, 1, 1)
    end

    local function showView(view)
        if currentView == view then
            return
        end
        local previous = currentView
        currentView = view
        if previous then
            previous.Visible = false
        end
        local fromX = view == views.Browse and -24 or 24
        view.Position = UDim2.fromOffset(fromX, 0)
        view.Visible = true
        tween(view, { Position = UDim2.fromOffset(0, 0) }, 0.3, Enum.EasingStyle.Quint)
    end

    -- Browse: search, publish and refresh, the filter strip, then results.

    local browse = views.Browse
    local toolbar = create("Frame", {
        Size = UDim2.new(1, 0, 0, ROW),
        BackgroundTransparency = 1,
        Parent = browse,
    })
    local publishButton, publishText = softButton(toolbar, "Publish", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.fromScale(1, 0),
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
    }, function()
        cloud:OpenPublish()
    end)
    primary(publishButton, publishText)
    publishButton.Visible = type(opts.OnPublish) == "function"
    local refreshButton, refreshIcon = iconButton(toolbar, "refresh-cw", "R", ROW)
    refreshButton.AnchorPoint = Vector2.new(1, 0)
    local searchHolder = create("Frame", {
        Size = UDim2.new(1, -(ROW + 8), 1, 0),
        BackgroundColor3 = Theme.Surface2,
        BorderSizePixel = 0,
        Parent = toolbar,
    })
    corner(searchHolder, UDim.new(0, 8))
    local searchStroke = stroke(searchHolder)
    local searchIcon, searchImage = glowIcon(searchHolder, "search", Theme.Muted, UDim2.new(0, 10, 0.5, 0))
    searchIcon.Size = UDim2.fromOffset(14, 14)
    local searchBox = create("TextBox", {
        Position = UDim2.fromOffset(32, 0),
        Size = UDim2.new(1, -62, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        PlaceholderText = opts.SearchPlaceholder or (TOUCH and "Search configs..." or "Search configs...   ( / )"),
        PlaceholderColor3 = Theme.Muted,
        TextColor3 = Theme.Text,
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        ClipsDescendants = true,
        Parent = searchHolder,
    })
    local searchClear = iconButton(searchHolder, "x", "x", 24, true)
    searchClear.AnchorPoint = Vector2.new(1, 0.5)
    searchClear.Position = UDim2.new(1, -4, 0.5, 0)
    searchClear.Visible = false

    local fetch
    local searchToken = 0
    local recent = type(stored.CloudRecent) == "table" and stored.CloudRecent or {}
    local recentFrame = create("Frame", {
        Position = UDim2.fromOffset(0, ROW + 4),
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Surface2,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 5,
        Parent = browse,
    })
    corner(recentFrame, UDim.new(0, 8))
    stroke(recentFrame)
    padding(recentFrame, 6, 6, 6, 6)
    vlist(recentFrame, 2)

    local function rememberSearch(text)
        text = trim(text)
        if #text < 2 then
            return
        end
        for index = #recent, 1, -1 do
            if string.lower(recent[index]) == string.lower(text) then
                table.remove(recent, index)
            end
        end
        table.insert(recent, 1, text)
        while #recent > 6 do
            table.remove(recent)
        end
        persist("CloudRecent", recent)
    end

    local function showRecent(show)
        show = show and #recent > 0 and searchBox.Text == ""
        if show == recentFrame.Visible then
            return
        end
        recentFrame.Visible = show
        if not show then
            return
        end
        clear(recentFrame)
        local header = create("Frame", {
            Size = UDim2.new(1, 0, 0, 20),
            BackgroundTransparency = 1,
            LayoutOrder = 0,
            Parent = recentFrame,
        })
        label({
            Position = UDim2.fromOffset(8, 0),
            Size = UDim2.new(1, -60, 1, 0),
            Text = "Recent searches",
            TextSize = 11,
            TextColor3 = Theme.Muted,
            Parent = header,
        })
        local wipe = create("TextButton", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -6, 0, 0),
            Size = UDim2.fromOffset(0, 20),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            Text = "Clear",
            TextSize = 11,
            FontFace = Fonts.Medium,
            TextColor3 = Theme.Accent,
            AutoButtonColor = false,
            Parent = header,
        })
        wipe.MouseButton1Down:Connect(function()
            recent = {}
            persist("CloudRecent", recent)
            showRecent(false)
        end)
        for index, text in ipairs(recent) do
            local row = create("TextButton", {
                Size = UDim2.new(1, 0, 0, TOUCH and 32 or 28),
                BackgroundColor3 = Theme.Surface3,
                BackgroundTransparency = 1,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = index,
                Parent = recentFrame,
            })
            corner(row, UDim.new(0, 6))
            local icon = glowIcon(row, "history", Theme.Muted, UDim2.new(0, 8, 0.5, 0))
            icon.Size = UDim2.fromOffset(13, 13)
            label({
                Position = UDim2.fromOffset(28, 0),
                Size = UDim2.new(1, -34, 1, 0),
                Text = text,
                TextSize = 13,
                FontFace = Fonts.Regular,
                Parent = row,
            })
            row.MouseEnter:Connect(function()
                tween(row, { BackgroundTransparency = 0.5 }, 0.1)
            end)
            row.MouseLeave:Connect(function()
                tween(row, { BackgroundTransparency = 1 }, 0.15)
            end)
            row.MouseButton1Down:Connect(function()
                searchToken += 1
                searchBox.Text = text
                query.Search = text
                rememberSearch(text)
                showRecent(false)
                searchBox:ReleaseFocus()
                fetch(false)
            end)
        end
    end

    local function fitToolbar()
        local scale = window.Scale.Scale
        local publishWidth = publishButton.Visible and (publishButton.AbsoluteSize.X / scale + 8) or 0
        refreshButton.Position = UDim2.new(1, -publishWidth, 0, 0)
        searchHolder.Size = UDim2.new(1, -(publishWidth + ROW + 8), 1, 0)
        recentFrame.Size = UDim2.new(1, -(publishWidth + ROW + 8), 0, 0)
    end
    publishButton:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitToolbar)
    task.defer(fitToolbar)

    -- A pixel taller than the chips on each side, so their strokes aren't clipped.
    local filterRow = create("Frame", {
        Position = UDim2.fromOffset(0, ROW + 7),
        Size = UDim2.new(1, 0, 0, CHIP + 2),
        BackgroundTransparency = 1,
        Parent = browse,
    })
    local sortButton = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -1, 0, 1),
        Size = UDim2.fromOffset(0, CHIP),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Surface2,
        Text = "",
        AutoButtonColor = false,
        Parent = filterRow,
    })
    corner(sortButton, UDim.new(1, 0))
    hoverStroke(sortButton, stroke(sortButton))
    padding(sortButton, 10, 12)
    hlist(sortButton, 6)
    local sortIcon = glowIcon(sortButton, "arrow-down-up", Theme.Accent, UDim2.new())
    sortIcon.Size = UDim2.fromOffset(13, 13)
    local sortLabel = label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = SORT_NAMES[query.Sort],
        TextSize = 12,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        Parent = sortButton,
    })
    local filterStrip = create("ScrollingFrame", {
        Size = UDim2.new(1, -120, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        ScrollingDirection = Enum.ScrollingDirection.X,
        AutomaticCanvasSize = Enum.AutomaticSize.X,
        CanvasSize = UDim2.new(),
        Parent = filterRow,
    })
    filterStrip:SetAttribute("NoDrag", true)
    hlist(filterStrip, 6)
    padding(filterStrip, 1, 1, 1, 1)
    local function fitFilters()
        local width = sortButton.AbsoluteSize.X / window.Scale.Scale
        filterStrip.Size = UDim2.new(1, -(width + 8), 1, 0)
    end
    sortButton:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitFilters)
    task.defer(fitFilters)

    local resultsTop = ROW + 8 + CHIP + 10
    local results = scroller(browse)
    results.Position = UDim2.fromOffset(0, resultsTop)
    results.Size = UDim2.new(1, 0, 1, -resultsTop)
    padding(results, 1, 6, 1, 12)
    vlist(results, 10)
    local summaryRow = create("Frame", {
        Size = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1,
        LayoutOrder = 0,
        Parent = results,
    })
    local summaryLabel = label({
        Size = UDim2.new(1, -100, 1, 0),
        Text = "",
        RichText = true,
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = summaryRow,
    })
    local resetButton = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.fromScale(1, 0),
        Size = UDim2.fromOffset(0, 16),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Text = "Clear filters",
        TextSize = 12,
        FontFace = Fonts.Medium,
        TextColor3 = Theme.Accent,
        AutoButtonColor = false,
        Visible = false,
        Parent = summaryRow,
    })
    local resetFilters

    local function filtered()
        return query.Search ~= "" or query.Tag ~= nil or query.Filter ~= "All"
    end

    -- "12 configs in Favorites, tagged PvP, matching "boss"", or "Searching..."
    local function renderSummary(pending)
        local parts = {}
        if query.Filter ~= "All" then
            table.insert(parts, "in " .. query.Filter)
        end
        if query.Tag then
            table.insert(parts, "tagged " .. escape(query.Tag))
        end
        if query.Search ~= "" then
            table.insert(parts, ('matching <font color="#%s">"%s"</font>'):format(colorToHex(Theme.Accent), escape(query.Search)))
        end
        local context = #parts > 0 and (" " .. table.concat(parts, ", ")) or ""
        if pending or (loading and #records == 0) then
            summaryLabel.Text = "Searching" .. context .. "..."
        else
            local count = #records
            summaryLabel.Text = ("%d%s config%s%s"):format(count, hasMore and "+" or "", (count == 1 and not hasMore) and "" or "s", context)
        end
        resetButton.Visible = filtered()
    end

    local spin = nil
    local function busy(on)
        loading = on
        if on and not spin then
            refreshIcon.Rotation = 0
            spin = TweenService:Create(refreshIcon, TweenInfo.new(0.9, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = 360 })
            spin:Play()
        elseif not on and spin then
            spin:Cancel()
            spin = nil
            tween(refreshIcon, { Rotation = 360 }, 0.35, Enum.EasingStyle.Quint)
        end
        renderSummary()
    end
    local grid = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 1,
        Parent = results,
    })
    local gridLayout = create("UIGridLayout", {
        CellSize = UDim2.new(1, 0, 0, CARD),
        CellPadding = UDim2.fromOffset(8, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = grid,
    })
    local function fitGrid()
        local width = results.AbsoluteSize.X / window.Scale.Scale
        local columns = width >= 620 and 2 or 1
        gridLayout.CellSize = UDim2.new(1 / columns, -(columns - 1) * 8 / columns, 0, CARD)
    end
    results:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitGrid)
    task.defer(fitGrid)
    local moreButton = softButton(results, "Load more", {
        Size = UDim2.new(1, 0, 0, 32),
        LayoutOrder = 2,
        Visible = false,
    }, function()
        cloud:LoadMore()
    end)
    local stateFrame = create("Frame", {
        Size = UDim2.new(1, 0, 0, 180),
        BackgroundTransparency = 1,
        Visible = false,
        LayoutOrder = 3,
        Parent = results,
    })

    -- Loading placeholders that pulse where cards will land.
    local skeletons = {}
    local function addSkeletons(count)
        for _ = 1, count do
            local cell = create("Frame", {
                BackgroundColor3 = Theme.Surface2,
                BorderSizePixel = 0,
                LayoutOrder = 100000 + #skeletons,
                Parent = grid,
            })
            corner(cell, UDim.new(0, 10))
            stroke(cell)
            for index, spec in ipairs({ { 14, 0.45 }, { 36, 0.3 }, { 58, 0.8 }, { 76, 0.6 } }) do
                local bar = create("Frame", {
                    Position = UDim2.fromOffset(14, spec[1]),
                    Size = UDim2.new(spec[2], -14, 0, index == 1 and 14 or 10),
                    BackgroundColor3 = Theme.Surface3,
                    BorderSizePixel = 0,
                    Parent = cell,
                })
                corner(bar, UDim.new(0, 4))
                TweenService:Create(bar, TweenInfo.new(0.75, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
                    BackgroundTransparency = 0.65,
                }):Play()
            end
            table.insert(skeletons, cell)
        end
    end
    local function clearSkeletons()
        for _, cell in ipairs(skeletons) do
            cell:Destroy()
        end
        skeletons = {}
    end

    -- kind: nil hides it, or "empty" / "error" with a message.
    local function setState(kind, text)
        clear(stateFrame)
        stateFrame.Visible = kind ~= nil
        if not kind then
            return
        end
        local holder, caption = emptyState(stateFrame, kind == "error" and "cloud-off" or "search-x", text)
        holder.Size = UDim2.fromOffset(280, 70)
        holder.Position = UDim2.new(0.5, 0, 0, 60)
        caption.TextWrapped = true
        caption.TextTruncate = Enum.TextTruncate.None
        caption.Size = UDim2.new(1, 0, 0, 32)
        if kind == "error" or filtered() then
            softButton(stateFrame, kind == "error" and "Try again" or "Clear filters", {
                AnchorPoint = Vector2.new(0.5, 0),
                Position = UDim2.new(0.5, 0, 0, 132),
                Size = UDim2.fromOffset(0, 30),
                AutomaticSize = Enum.AutomaticSize.X,
            }, function()
                if kind == "error" then
                    cloud:Refresh()
                else
                    resetFilters()
                end
            end)
        end
        renderSummary()
    end

    -- Cards

    local openDetail, installRecord, refreshRecord

    local function renderCard(card)
        local record = card.Record
        card.Title.Text = highlight(record.Name)
        local meta = { "by " .. record.Author }
        local when = ago(record.Updated)
        if when then
            table.insert(meta, when)
        end
        if record.Count then
            table.insert(meta, record.Count .. (record.Count == 1 and " setting" or " settings"))
        end
        card.Meta.Text = table.concat(meta, "  ·  ")
        card.Desc.Text = record.Description ~= "" and highlight(record.Description) or "No description"
        card.Desc.TextTransparency = record.Description ~= "" and 0.2 or 0.55
        card.Likes.Text = compact(record.Likes)
        card.Installs.Text = compact(record.Installs)
        tween(card.Heart, { ImageColor3 = record.Liked and Theme.Accent or Theme.Muted }, 0.15)
        local state = installState(record)
        local badge, color
        if state == "Update" then
            badge, color = "UPDATE", Theme.Accent
        elseif state == "Installed" then
            badge, color = "INSTALLED", Theme.Success
        elseif record.Mine then
            badge, color = "YOURS", Theme.Accent
        elseif otherScript(record) then
            badge, color = "OTHER SCRIPT", Theme.Warning
        end
        card.Badge.Visible = badge ~= nil
        if badge then
            card.Badge.Text = badge
            tween(card.Badge, { TextColor3 = color, BackgroundColor3 = color }, 0)
        end
        card.Star.Visible = favorites[record.Id] ~= nil
        card.InstallText.Text = state == "Update" and "Update" or (state == "Installed" and "Reinstall" or "Install")
        clear(card.TagRow)
        for index, tag in ipairs(record.Tags) do
            if index > 3 then
                tagPill(card.TagRow, "+" .. (#record.Tags - 3), index)
                break
            end
            tagPill(card.TagRow, tag, index)
        end
    end

    local function buildCard(record, order)
        local frame = create("TextButton", {
            BackgroundColor3 = Theme.Surface2,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            LayoutOrder = order,
            Parent = grid,
        })
        frame:SetAttribute("NoDrag", true)
        corner(frame, UDim.new(0, 10))
        hoverStroke(frame, stroke(frame))
        padding(frame, 14, 14, 12, 12)
        local card = { Record = record, Frame = frame }
        card.Title = label({
            Size = UDim2.new(1, -110, 0, 18),
            RichText = true,
            TextSize = 14,
            FontFace = Fonts.Bold,
            Parent = frame,
        })
        local corner_ = create("Frame", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.fromScale(1, 0),
            Size = UDim2.fromOffset(0, 18),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            Parent = frame,
        })
        local cornerLayout = hlist(corner_, 6)
        cornerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
        card.Star = label({
            Size = UDim2.fromOffset(14, 18),
            Text = "★",
            TextSize = 13,
            TextColor3 = Theme.Accent,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = 1,
            Parent = corner_,
        })
        card.Badge = label({
            Size = UDim2.fromOffset(0, 17),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 0.85,
            TextSize = 10,
            FontFace = Fonts.Bold,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = 2,
            Parent = corner_,
        })
        corner(card.Badge, UDim.new(0, 5))
        padding(card.Badge, 6, 6)
        card.Meta = label({
            Position = UDim2.fromOffset(0, 20),
            Size = UDim2.new(1, 0, 0, 16),
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            Parent = frame,
        })
        card.Desc = label({
            Position = UDim2.fromOffset(0, 41),
            RichText = true,
            Size = UDim2.new(1, 0, 0, 30),
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextWrapped = true,
            TextYAlignment = Enum.TextYAlignment.Top,
            Parent = frame,
        })
        local bottom = create("Frame", {
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.fromScale(0, 1),
            Size = UDim2.new(1, 0, 0, 26),
            BackgroundTransparency = 1,
            Parent = frame,
        })
        card.TagRow = create("Frame", {
            Size = UDim2.new(1, -190, 1, 0),
            BackgroundTransparency = 1,
            ClipsDescendants = true,
            Parent = bottom,
        })
        hlist(card.TagRow, 4)
        local install, installText = softButton(bottom, "Install", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.fromOffset(76, 26),
        }, function()
            installRecord(record)
        end)
        primary(install, installText)
        card.InstallText = installText
        local stats = create("Frame", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -86, 0.5, 0),
            Size = UDim2.fromOffset(0, 20),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            Parent = bottom,
        })
        hlist(stats, 4)
        local function stat(icon, order_)
            local holder, image = glowIcon(stats, icon, Theme.Muted, UDim2.new())
            holder.Size = UDim2.fromOffset(12, 12)
            holder.LayoutOrder = order_
            local text_ = label({
                Size = UDim2.fromOffset(0, 20),
                AutomaticSize = Enum.AutomaticSize.X,
                TextSize = 12,
                TextColor3 = Theme.Muted,
                TextTruncate = Enum.TextTruncate.None,
                LayoutOrder = order_ + 1,
                Parent = stats,
            })
            return text_, image
        end
        card.Likes, card.Heart = stat("heart", 1)
        create("Frame", { Size = UDim2.fromOffset(4, 1), BackgroundTransparency = 1, LayoutOrder = 3, Parent = stats })
        card.Installs = stat("download", 4)
        local isTap = tapGuard(frame, function()
            return results
        end)
        frame.MouseButton1Click:Connect(function()
            if isTap() then
                if query.Search ~= "" then
                    rememberSearch(query.Search)
                end
                openDetail(record)
            end
        end)
        cards[record.Id] = card
        renderCard(card)
        return card
    end

    local function renderList()
        for _, card in pairs(cards) do
            card.Frame:Destroy()
        end
        cards = {}
        for index, record in ipairs(records) do
            buildCard(record, index)
        end
    end

    -- Favorites and Installed are kept on this device, so they filter locally.
    local function localRecords()
        local source = query.Filter == "Favorites" and favorites or installed
        local search = string.lower(query.Search)
        local list = {}
        for id, entry in pairs(source) do
            local kept = query.Filter == "Favorites" and entry or (type(entry) == "table" and entry.Record)
            if type(kept) == "table" then
                kept = table.clone(kept)
                kept.Id = id
                local record = normalizeRecord(kept)
                local matches = search == "" or string.find(string.lower(record.Name), search, 1, true)
                    or string.find(string.lower(record.Description), search, 1, true)
                if matches and query.Tag then
                    matches = table.find(record.Tags, query.Tag) ~= nil
                end
                if matches then
                    table.insert(list, record)
                end
            end
        end
        table.sort(list, function(a, b)
            if query.Sort == "New" then
                return (a.Updated or 0) > (b.Updated or 0)
            elseif query.Sort == "Installs" then
                return a.Installs > b.Installs
            end
            return a.Likes > b.Likes
        end)
        return list
    end

    local function emptyText()
        if query.Filter == "Favorites" then
            return "No favorites yet. Open a config and press Favorite to keep it here."
        elseif query.Filter == "Installed" then
            return "Nothing installed from the cloud yet"
        elseif query.Filter == "Mine" then
            return "You haven't published anything yet"
        elseif query.Search ~= "" or query.Tag then
            return "No configs match your search"
        end
        return tostring(opts.EmptyText or "No configs shared yet. Be the first!")
    end

    function fetch(more)
        token += 1
        local myToken = token
        if query.Filter == "Favorites" or query.Filter == "Installed" then
            busy(false)
            clearSkeletons()
            records = localRecords()
            hasMore = false
            renderList()
            moreButton.Visible = false
            setState(#records == 0 and "empty" or nil, emptyText())
            return
        end
        if type(opts.OnFetch) ~= "function" then
            renderList()
            setState(#records == 0 and "empty" or nil, emptyText())
            return
        end
        if more then
            if not hasMore then
                return
            end
            page += 1
        else
            page = 1
            records = {}
            renderList()
            results.CanvasPosition = Vector2.zero
        end
        busy(true)
        clearSkeletons()
        addSkeletons(more and 2 or 4)
        moreButton.Visible = false
        setState(nil)
        local fetchQuery = {
            Search = query.Search,
            Sort = query.Sort,
            Filter = query.Filter,
            Tag = query.Tag,
            Page = page,
            PageSize = pageSize,
            Folder = window.ConfigFolder,
            UserId = LocalPlayer.UserId,
        }
        task.spawn(function()
            local ok, list, extra = isolatedCall(function()
                return opts.OnFetch(fetchQuery)
            end)
            if myToken ~= token then
                return
            end
            busy(false)
            clearSkeletons()
            if not ok or type(list) ~= "table" then
                if more then
                    page -= 1
                end
                if not ok then
                    warn("[RealIggyLib] cloud OnFetch error: " .. tostring(list))
                end
                hasMore = more and hasMore or false
                moreButton.Visible = false
                setState("error", not ok and "Could not load configs" or tostring(extra or "Could not load configs"))
                return
            end
            hasMore = extra == true
            local seen = {}
            for _, record in ipairs(records) do
                seen[record] = true
            end
            for _, raw in ipairs(list) do
                local record = normalizeRecord(raw)
                if record and not seen[record] then
                    seen[record] = true
                    table.insert(records, record)
                    buildCard(record, #records)
                end
            end
            moreButton.Visible = hasMore
            setState(#records == 0 and "empty" or nil, emptyText())
        end)
    end

    -- Near the bottom, the next page loads by itself.
    results:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
        if not hasMore or loading then
            return
        end
        local scale = window.Scale.Scale
        local remaining = results.AbsoluteCanvasSize.Y / scale - results.AbsoluteWindowSize.Y / scale - results.CanvasPosition.Y
        if remaining < 160 then
            fetch(true)
        end
    end)

    -- Filters and sorting

    local filterChips, tagChips = {}, {}
    local function renderFilters(instant)
        for name, object in pairs(filterChips) do
            object.Set(query.Filter == name, instant)
        end
        for name, object in pairs(tagChips) do
            object.Set(query.Tag == name, instant)
        end
        sortLabel.Text = SORT_NAMES[query.Sort]
    end
    for index, name in ipairs(FILTERS) do
        if not (name == "Mine" and opts.MineFilter == false) then
            filterChips[name] = chip(filterStrip, name, index, function()
                if query.Filter ~= name then
                    query.Filter = name
                    renderFilters()
                    fetch(false)
                end
            end)
        end
    end
    if #tagList > 0 then
        create("Frame", {
            Size = UDim2.fromOffset(1, 16),
            BackgroundColor3 = Theme.Stroke,
            BorderSizePixel = 0,
            LayoutOrder = 10,
            Parent = filterStrip,
        })
    end
    for index, tag in ipairs(tagList) do
        tag = tostring(tag)
        tagChips[tag] = chip(filterStrip, tag, 10 + index, function()
            query.Tag = query.Tag ~= tag and tag or nil
            renderFilters()
            fetch(false)
        end)
    end
    sortButton.MouseButton1Click:Connect(function()
        local index = table.find(SORTS, query.Sort) or 1
        query.Sort = SORTS[index % #SORTS + 1]
        persist("CloudSort", query.Sort)
        renderFilters()
        fetch(false)
    end)

    function resetFilters()
        searchToken += 1
        searchBox.Text = ""
        query.Search, query.Tag, query.Filter = "", nil, "All"
        renderFilters()
        fetch(false)
    end
    resetButton.MouseButton1Click:Connect(resetFilters)

    -- Typing searches after a short pause; Enter searches now.
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        searchClear.Visible = searchBox.Text ~= ""
        showRecent(searchBox:IsFocused())
        searchToken += 1
        local mine = searchToken
        local text = trim(searchBox.Text)
        if text ~= query.Search then
            renderSummary(true)
        end
        task.delay(0.35, function()
            text = trim(searchBox.Text)
            if mine == searchToken and text ~= query.Search then
                query.Search = text
                fetch(false)
            end
        end)
    end)
    searchBox.Focused:Connect(function()
        tween(searchStroke, { Color = Theme.Accent }, 0.15)
        tween(searchImage, { ImageColor3 = Theme.Accent }, 0.15)
        showRecent(true)
    end)
    searchBox.FocusLost:Connect(function(enterPressed)
        tween(searchStroke, { Color = Theme.Stroke }, 0.2)
        tween(searchImage, { ImageColor3 = Theme.Muted }, 0.2)
        rememberSearch(searchBox.Text)
        -- Late enough for a press on a recent search to land first.
        task.delay(0.15, function()
            if not searchBox:IsFocused() then
                showRecent(false)
            end
        end)
        if enterPressed then
            searchToken += 1
            local text = trim(searchBox.Text)
            if text ~= query.Search then
                query.Search = text
                fetch(false)
            end
        end
    end)
    searchClear.MouseButton1Click:Connect(function()
        searchToken += 1
        searchBox.Text = ""
        if query.Search ~= "" then
            query.Search = ""
            fetch(false)
        end
    end)
    -- "/" jumps to the search box while the list is showing.
    window:_listen("Began", function(input, processed)
        if processed or input.KeyCode ~= Enum.KeyCode.Slash then
            return
        end
        if window.Open and window.CurrentTab == tab and currentView == views.Browse and not UserInputService:GetFocusedTextBox() then
            task.defer(function()
                searchBox:CaptureFocus()
                searchBox.Text = searchBox.Text:gsub("/$", "")
            end)
        end
    end, cloud)
    refreshButton.MouseButton1Click:Connect(function()
        cloud:Refresh()
    end)

    -- Actions on a record

    -- Runs callback with the record's code, asking the backend for it first
    -- when the list came without codes.
    local function withCode(record, callback, onFail)
        if record.Code then
            callback(record.Code)
            return
        end
        local function fail(reason)
            if onFail then
                onFail(reason)
            else
                notify(false, "Could not load config", reason)
            end
        end
        if type(opts.OnFetchCode) ~= "function" then
            fail("This config has no code")
            return
        end
        task.spawn(function()
            local ok, code, reason = isolatedCall(function()
                return opts.OnFetchCode(publicRecord(record))
            end)
            if ok and type(code) == "string" and code ~= "" then
                record.Code = code
                record.Count = record.Count or countFlags(code)
                callback(code)
            else
                fail(tostring(reason or (not ok and "the request failed") or "no code came back"))
            end
        end)
    end

    function installRecord(record)
        if record._busy then
            return
        end
        record._busy = true
        withCode(record, function(code)
            record._busy = nil
            local data, info = window:DecodeConfig(code)
            if not data then
                notify(false, "Install failed", "The config code is invalid")
                return
            end
            local count = 0
            for _ in pairs(data) do
                count += 1
            end
            local mark = installed[record.Id]
            local saveAs = nil
            if fileApiAvailable() then
                -- An update overwrites the config it installed last time.
                saveAs = type(mark) == "table" and type(mark.Name) == "string" and window:ConfigExists(mark.Name) and mark.Name
                    or uniqueName(record.Name)
            end
            local other = info.Folder and info.Folder ~= window.ConfigFolder
            local function apply(save)
                local name = save and saveAs or nil
                local ok, err = window:ImportConfig(code, name, true)
                if not ok then
                    notify(false, "Install failed", tostring(err))
                    return
                end
                installed[record.Id] = { Updated = record.Updated or os.time(), Name = name, At = os.time(), Record = summary(record) }
                persist("CloudInstalled", installed)
                record.Installs += 1
                refreshRecord(record)
                notify(true, "Config installed", name and ("Saved as " .. name) or "Applied to your current settings")
                if opts.OnInstall then
                    task.spawn(safeCall, opts.OnInstall, publicRecord(record), name)
                end
            end
            local content = ("%s by %s changes %d setting%s."):format(record.Name, record.Author, count, count == 1 and "" or "s")
            if other then
                content ..= (" It was made for %s, so only matching settings apply."):format(info.Folder)
            end
            if saveAs then
                content ..= (" Install also saves it as %s; Apply only doesn't."):format(saveAs)
            end
            local buttons = { { Title = "Cancel" } }
            table.insert(buttons, { Title = "Apply only", Variant = not saveAs and "Primary" or nil, Callback = function()
                apply(false)
            end })
            if saveAs then
                table.insert(buttons, { Title = "Install", Variant = "Primary", Callback = function()
                    apply(true)
                end })
            end
            window:Dialog({
                Title = installState(record) == "Update" and "Update config" or "Install config",
                Content = content,
                Icon = other and "triangle-alert" or "download",
                Buttons = buttons,
            })
        end, function(reason)
            record._busy = nil
            notify(false, "Could not load config", reason)
        end)
    end

    local function toggleLike(record)
        if type(opts.OnLike) ~= "function" or record._liking then
            return
        end
        local liked = not record.Liked
        record.Liked = liked
        record.Likes = math.max(record.Likes + (liked and 1 or -1), 0)
        record._liking = true
        refreshRecord(record)
        task.spawn(function()
            local ok, result, reason = isolatedCall(function()
                return opts.OnLike(publicRecord(record), liked)
            end)
            record._liking = nil
            if not ok or result == false then
                record.Liked = not liked
                record.Likes = math.max(record.Likes + (liked and -1 or 1), 0)
                refreshRecord(record)
                notify(false, "Like not saved", tostring(reason or "Try again in a moment"))
            end
        end)
    end

    local function toggleFavorite(record)
        local on = favorites[record.Id] == nil
        favorites[record.Id] = on and summary(record) or nil
        persist("CloudFavorites", favorites)
        refreshRecord(record)
        window:Notify({
            Title = on and "Added to favorites" or "Removed from favorites",
            Content = record.Name,
            Icon = "star",
            Duration = 2,
        })
    end

    local function removeRecord(record)
        local index = table.find(records, record)
        if index then
            table.remove(records, index)
        end
        byId[record.Id] = nil
        local card = cards[record.Id]
        if card then
            card.Frame:Destroy()
            cards[record.Id] = nil
        end
        if #records == 0 and not loading then
            setState("empty", emptyText())
        end
    end

    local function deleteRecord(record)
        window:Confirm({
            Title = "Delete config",
            Content = ("Remove %s from the cloud? People who installed it keep their copy."):format(record.Name),
            Icon = "trash-2",
            ConfirmText = "Delete",
            Callback = function()
                task.spawn(function()
                    local ok, result, reason = isolatedCall(function()
                        return opts.OnDelete(publicRecord(record))
                    end)
                    if not ok or result == false then
                        notify(false, "Delete failed", tostring(reason or "Try again in a moment"))
                        return
                    end
                    favorites[record.Id] = nil
                    persist("CloudFavorites", favorites)
                    removeRecord(record)
                    showView(views.Browse)
                    notify(true, "Config deleted", record.Name)
                end)
            end,
        })
    end

    local function reportRecord(record)
        local reasons = type(opts.ReportReasons) == "table" and opts.ReportReasons or { "Broken", "Spam", "Inappropriate" }
        local buttons = { { Title = "Cancel" } }
        for _, reason in ipairs(reasons) do
            table.insert(buttons, { Title = tostring(reason), Callback = function()
                task.spawn(function()
                    local ok, result = isolatedCall(function()
                        return opts.OnReport(publicRecord(record), tostring(reason))
                    end)
                    local sent = ok and result ~= false
                    notify(sent, sent and "Report sent" or "Report failed", sent and "Thanks for letting us know" or "Try again in a moment")
                end)
            end })
        end
        window:Dialog({
            Title = "Report config",
            Content = ("What's wrong with %s?"):format(record.Name),
            Icon = "flag",
            Buttons = buttons,
        })
    end

    -- Detail view

    local detailList = scroller(views.Detail)
    padding(detailList, 1, 8, 1, 16)
    vlist(detailList, 10)

    local function valueText(entry)
        local value = type(entry) == "table" and entry.Value or nil
        if value == nil then
            return "None"
        elseif type(value) == "boolean" then
            return value and "On" or "Off"
        elseif type(value) == "number" then
            return (("%.2f"):format(value):gsub("%.?0+$", ""))
        elseif type(value) == "table" then
            if type(value.Hex) == "string" then
                return "#" .. string.upper(value.Hex)
            elseif type(value.Colors) == "table" then
                local text = type(value.Name) == "string" and value.Name or "Custom"
                if type(value.Background) == "string" and value.Background ~= "" then
                    text ..= ", image"
                end
                return text
            end
            local parts = {}
            for index, item in ipairs(value) do
                parts[index] = tostring(item)
            end
            return #parts > 0 and table.concat(parts, ", ") or "None"
        end
        return tostring(value)
    end

    local function encoded(entry)
        local ok, text = pcall(HttpService.JSONEncode, HttpService, type(entry) == "table" and entry.Value or nil)
        return ok and text or tostring(entry)
    end

    local function renderDetail()
        local record = detailRecord
        if not record or not detail.Meta then
            return
        end
        detail.Title.Text = record.Name
        local meta = { "by " .. record.Author }
        local when = ago(record.Updated)
        if when then
            table.insert(meta, "updated " .. when)
        end
        if otherScript(record) then
            table.insert(meta, "made for " .. record.Folder)
        end
        detail.Meta.Text = table.concat(meta, "  ·  ")
        detail.Stats.Text = ("%s like%s  ·  %s install%s"):format(
            compact(record.Likes), record.Likes == 1 and "" or "s",
            compact(record.Installs), record.Installs == 1 and "" or "s")
        if detail.BuiltFor ~= record or detail.BuiltMine ~= record.Mine then
            detail.BuiltFor, detail.BuiltMine = record, record.Mine
            local row = detail.Actions
            clear(row)
            local order = 0
            local function action(text, style, callback)
                order += 1
                local button, text_ = softButton(row, text, {
                    Size = UDim2.new(0, 0, 0, 30),
                    AutomaticSize = Enum.AutomaticSize.X,
                    LayoutOrder = order,
                }, callback)
                text_.TextSize = 13
                if style == "Primary" then
                    primary(button, text_)
                elseif style == "Danger" then
                    tween(text_, { TextColor3 = Theme.Error }, 0)
                end
                return text_
            end
            detail.InstallLabel = action("Install", "Primary", function()
                installRecord(record)
            end)
            if type(opts.OnLike) == "function" then
                detail.LikeLabel = action("Like", nil, function()
                    toggleLike(record)
                end)
            end
            detail.FavoriteLabel = action("Favorite", nil, function()
                toggleFavorite(record)
            end)
            action("Copy code", nil, function()
                withCode(record, function(code)
                    window:CopyToClipboard(code, "Config code")
                end)
            end)
            if record.Mine then
                if type(opts.OnUpdate) == "function" then
                    action("Edit", nil, function()
                        cloud:OpenPublish(record)
                    end)
                end
                if type(opts.OnDelete) == "function" then
                    action("Delete", "Danger", function()
                        deleteRecord(record)
                    end)
                end
            elseif type(opts.OnReport) == "function" then
                action("Report", "Danger", function()
                    reportRecord(record)
                end)
            end
        end
        local state = installState(record)
        detail.InstallLabel.Text = state == "Update" and "Update" or (state == "Installed" and "Reinstall" or "Install")
        if detail.LikeLabel then
            detail.LikeLabel.Text = (record.Liked and "Liked" or "Like") .. "  ·  " .. compact(record.Likes)
        end
        detail.FavoriteLabel.Text = favorites[record.Id] and "Favorited" or "Favorite"
    end

    -- Every setting in the config next to the player's own: changed ones
    -- first, then the same ones, then flags this script doesn't have.
    local function fillPreview(record, myToken)
        local function mismatch(text)
            if detailToken == myToken then
                detail.Summary.Text = text
            end
        end
        withCode(record, function(code)
            if detailToken ~= myToken then
                return
            end
            local data = window:DecodeConfig(code)
            if not data then
                mismatch("The config code is invalid")
                return
            end
            local current = collectFlags(window)
            local rows = {}
            local changed = 0
            for flag, entry in pairs(data) do
                local element = Library.Flags[flag]
                local known = element ~= nil
                local differs = known and encoded(entry) ~= encoded(current[flag])
                if differs then
                    changed += 1
                end
                table.insert(rows, {
                    Name = element and element._searchName ~= "" and element._searchName or flag,
                    Value = valueText(entry),
                    Known = known,
                    Changed = differs,
                    Rank = differs and 0 or (known and 1 or 2),
                })
            end
            table.sort(rows, function(a, b)
                if a.Rank ~= b.Rank then
                    return a.Rank < b.Rank
                end
                return string.lower(a.Name) < string.lower(b.Name)
            end)
            record.Count = #rows
            detail.Summary.Text = changed == 0 and ("%d settings, all the same as yours"):format(#rows)
                or ("%d settings, %d different from yours"):format(#rows, changed)
            clear(detail.Rows)
            for index, item in ipairs(rows) do
                if index > 150 then
                    wrapped(detail.Rows, ("and %d more"):format(#rows - 150), 12, Theme.Muted, index)
                    break
                end
                local rowFrame = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 30),
                    BackgroundColor3 = Theme.Surface2,
                    BackgroundTransparency = item.Changed and 0 or 0.5,
                    BorderSizePixel = 0,
                    LayoutOrder = index,
                    Parent = detail.Rows,
                })
                corner(rowFrame, UDim.new(0, 7))
                if item.Changed then
                    local dot = create("Frame", {
                        AnchorPoint = Vector2.new(0, 0.5),
                        Position = UDim2.new(0, 10, 0.5, 0),
                        Size = UDim2.fromOffset(6, 6),
                        BackgroundColor3 = Theme.Accent,
                        BorderSizePixel = 0,
                        Parent = rowFrame,
                    })
                    corner(dot, UDim.new(1, 0))
                end
                label({
                    Position = UDim2.fromOffset(24, 0),
                    Size = UDim2.new(0.55, -24, 1, 0),
                    Text = item.Known and item.Name or (item.Name .. "  (not in this script)"),
                    TextSize = 12,
                    TextColor3 = item.Known and Theme.Text or Theme.Muted,
                    Parent = rowFrame,
                })
                label({
                    AnchorPoint = Vector2.new(1, 0),
                    Position = UDim2.new(1, -10, 0, 0),
                    Size = UDim2.new(0.45, -10, 1, 0),
                    Text = item.Value,
                    TextSize = 12,
                    FontFace = Fonts.Regular,
                    TextColor3 = item.Changed and Theme.Accent or Theme.Muted,
                    TextXAlignment = Enum.TextXAlignment.Right,
                    Parent = rowFrame,
                })
            end
            if cards[record.Id] then
                renderCard(cards[record.Id])
            end
        end, mismatch)
    end

    function openDetail(record)
        detailRecord = record
        detailToken += 1
        local myToken = detailToken
        clear(detailList)
        detail = {}
        detailList.CanvasPosition = Vector2.zero
        softButton(detailList, "Back", {
            Size = UDim2.new(0, 0, 0, 28),
            AutomaticSize = Enum.AutomaticSize.X,
            LayoutOrder = 1,
        }, function()
            showView(views.Browse)
        end)
        detail.Title = wrapped(detailList, record.Name, 20, Theme.Text, 2, Fonts.Bold)
        detail.Meta = wrapped(detailList, "", 12, Theme.Muted, 3)
        if record.Description ~= "" then
            wrapped(detailList, record.Description, 13, Theme.Text, 4)
        end
        if #record.Tags > 0 then
            local tagsRow = create("Frame", {
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                LayoutOrder = 5,
                Parent = detailList,
            })
            hlist(tagsRow, 4, true)
            for index, tag in ipairs(record.Tags) do
                tagPill(tagsRow, tag, index)
            end
        end
        detail.Stats = wrapped(detailList, "", 12, Theme.Muted, 6)
        detail.Actions = create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            LayoutOrder = 7,
            Parent = detailList,
        })
        hlist(detail.Actions, 6, true)
        create("Frame", {
            Size = UDim2.new(1, 0, 0, 1),
            BackgroundColor3 = Theme.Stroke,
            BorderSizePixel = 0,
            LayoutOrder = 8,
            Parent = detailList,
        })
        wrapped(detailList, "Settings", 14, Theme.Text, 9, Fonts.Bold)
        detail.Summary = wrapped(detailList, "Loading settings...", 12, Theme.Muted, 10)
        detail.Rows = create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            LayoutOrder = 11,
            Parent = detailList,
        })
        vlist(detail.Rows, 4)
        renderDetail()
        showView(views.Detail)
        fillPreview(record, myToken)
    end

    function refreshRecord(record)
        local card = cards[record.Id]
        if card then
            renderCard(card)
        end
        if detailRecord == record and currentView == views.Detail then
            renderDetail()
        end
    end

    -- Publish view: also the edit form for the player's own configs.

    local form = { Mode = "Publish", Record = nil, Source = false, Tags = {}, Busy = false }
    local publishList = scroller(views.Publish)
    padding(publishList, 1, 8, 1, 16)
    vlist(publishList, 8)
    softButton(publishList, "Back", {
        Size = UDim2.new(0, 0, 0, 28),
        AutomaticSize = Enum.AutomaticSize.X,
        LayoutOrder = 1,
    }, function()
        showView(form.Mode == "Edit" and form.Record and views.Detail or views.Browse)
    end)
    local formTitle = wrapped(publishList, "Publish a config", 20, Theme.Text, 2, Fonts.Bold)
    wrapped(publishList, "Name", 12, Theme.Muted, 3)
    local nameBox = field(publishList, 4, "What is it for?", ROW, NAME_LIMIT)
    wrapped(publishList, "Description", 12, Theme.Muted, 5)
    local descBox = field(publishList, 6, "What does it do, and how should people use it?", 90, DESC_LIMIT)
    local tagsTitle = wrapped(publishList, "Tags", 12, Theme.Muted, 7)
    local tagsRow = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 8,
        Parent = publishList,
    })
    hlist(tagsRow, 6, true)
    tagsTitle.Visible = #tagList > 0 and maxTags > 0
    tagsRow.Visible = tagsTitle.Visible
    wrapped(publishList, "Settings to share", 12, Theme.Muted, 9)
    local sourceRow = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 10,
        Parent = publishList,
    })
    hlist(sourceRow, 6, true)
    local sourceSummary = wrapped(publishList, "", 12, Theme.Muted, 11)
    local identityNote = wrapped(publishList, "", 12, Theme.Muted, 12)
    local formError = wrapped(publishList, "", 12, Theme.Error, 13)
    formError.Visible = false
    local submitRow = create("Frame", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundTransparency = 1,
        LayoutOrder = 14,
        Parent = publishList,
    })
    hlist(submitRow, 6)
    local submitButton, submitText = softButton(submitRow, "Publish", {
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        LayoutOrder = 1,
    }, function()
        cloud:_submit()
    end)
    primary(submitButton, submitText)
    softButton(submitRow, "Cancel", {
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        LayoutOrder = 2,
    }, function()
        showView(form.Mode == "Edit" and form.Record and views.Detail or views.Browse)
    end)

    local formTagChips = {}
    local function renderFormTags()
        for tag, object in pairs(formTagChips) do
            object.Set(table.find(form.Tags, tag) ~= nil)
        end
        tagsTitle.Text = maxTags > 0 and ("Tags  (%d/%d)"):format(#form.Tags, maxTags) or "Tags"
    end
    for index, tag in ipairs(tagList) do
        tag = tostring(tag)
        formTagChips[tag] = chip(tagsRow, tag, index, function()
            local at = table.find(form.Tags, tag)
            if at then
                table.remove(form.Tags, at)
            elseif #form.Tags < maxTags then
                table.insert(form.Tags, tag)
            else
                notify(false, "Too many tags", ("Pick up to %d"):format(maxTags))
            end
            renderFormTags()
        end)
    end

    -- The code and setting count for the picked source, or nil and why not.
    local function sourceCode(name)
        if form.Source == "Keep" then
            return nil, form.Record and form.Record.Count
        elseif form.Source then
            local code, err = window:ExportConfig(form.Source)
            if not code then
                return nil, nil, err
            end
            return code, countFlags(code)
        end
        local ok, code = pcall(encodeConfig, window, name ~= "" and name or "Cloud config", collectFlags(window))
        if not ok then
            return nil, nil, "could not encode your settings"
        end
        return code, countFlags(code)
    end

    local sourceChips = {}
    local function renderSource()
        for key, object in pairs(sourceChips) do
            object.Set(key == (form.Source or "*current"))
        end
        local _, count, err = sourceCode(trim(nameBox.Text))
        if err then
            sourceSummary.Text = tostring(err)
        elseif form.Source == "Keep" then
            sourceSummary.Text = "Keeps the settings already published" .. (count and (" (" .. count .. ")") or "")
        else
            sourceSummary.Text = ("%d setting%s from %s"):format(count or 0, count == 1 and "" or "s", form.Source or "your current settings")
        end
    end

    local function buildSources()
        clear(sourceRow)
        sourceChips = {}
        local order = 0
        local function add(key, text)
            order += 1
            sourceChips[key] = chip(sourceRow, text, order, function()
                form.Source = key ~= "*current" and key or false
                renderSource()
            end)
        end
        if form.Mode == "Edit" then
            add("Keep", "Keep published settings")
        end
        add("*current", "Current settings")
        for _, name in ipairs(window:ListConfigs()) do
            add(name, name)
        end
        renderSource()
    end

    local function showError(text)
        formError.Text = tostring(text)
        formError.Visible = true
    end

    function cloud:OpenPublish(record)
        local editing = type(record) == "table" and record.Id and byId[record.Id] or nil
        if editing then
            form.Mode, form.Record = "Edit", editing
            form.Source = "Keep"
            form.Tags = table.clone(editing.Tags)
            nameBox.Text = editing.Name
            descBox.Text = editing.Description
        elseif form.Mode == "Edit" then
            -- Leaving an edit starts a fresh draft; a publish draft is kept.
            form.Mode, form.Record, form.Source, form.Tags = "Publish", nil, false, {}
            nameBox.Text = ""
            descBox.Text = ""
        end
        formTitle.Text = editing and "Edit config" or "Publish a config"
        submitText.Text = editing and "Save changes" or "Publish"
        formError.Visible = false
        local streamer = streamerOn()
        identityNote.Text = streamer and ("Your name is hidden, so you publish as " .. anonName)
            or ("You publish as " .. LocalPlayer.DisplayName)
        renderFormTags()
        buildSources()
        publishList.CanvasPosition = Vector2.zero
        showView(views.Publish)
    end

    nameBox:GetPropertyChangedSignal("Text"):Connect(function()
        formError.Visible = false
    end)

    function cloud:_submit()
        if form.Busy then
            return
        end
        local name = trim(nameBox.Text)
        if name == "" then
            showError("Give your config a name")
            return
        end
        local code, count, err = sourceCode(name)
        if err then
            showError(err)
            return
        end
        if form.Source ~= "Keep" and (count or 0) == 0 then
            showError("There are no settings to share")
            return
        end
        local editing = form.Mode == "Edit" and form.Record or nil
        local callback = editing and opts.OnUpdate or opts.OnPublish
        if type(callback) ~= "function" then
            showError(editing and "Editing isn't available" or "Publishing isn't available")
            return
        end
        local streamer = streamerOn()
        local payload = {
            Name = name,
            Description = trim(descBox.Text),
            Tags = table.clone(form.Tags),
            Code = code,
            Count = count,
            Folder = window.ConfigFolder,
            Author = streamer and anonName or LocalPlayer.DisplayName,
            AuthorId = not streamer and LocalPlayer.UserId or nil,
            OwnerId = LocalPlayer.UserId,
            Streamer = streamer,
        }
        form.Busy = true
        submitText.Text = editing and "Saving..." or "Publishing..."
        formError.Visible = false
        task.spawn(function()
            local ok, result, reason = isolatedCall(function()
                if editing then
                    return callback(publicRecord(editing), payload)
                end
                return callback(payload)
            end)
            form.Busy = false
            submitText.Text = editing and "Save changes" or "Publish"
            if not ok or result == false then
                if not ok then
                    warn("[RealIggyLib] cloud publish error: " .. tostring(result))
                end
                showError(ok and reason and tostring(reason) or "Something went wrong, try again")
                return
            end
            local merged = table.clone(payload)
            merged.Code = code or (editing and editing.Code)
            merged.Updated = os.time()
            if type(result) == "table" then
                for key, value in pairs(result) do
                    merged[key] = value
                end
            end
            if editing then
                merged.Id = editing.Id
                normalizeRecord(merged)
                if favorites[editing.Id] then
                    favorites[editing.Id] = summary(editing)
                    persist("CloudFavorites", favorites)
                end
                refreshRecord(editing)
                notify(true, "Config updated", name)
                openDetail(editing)
            else
                nameBox.Text = ""
                descBox.Text = ""
                form.Tags = {}
                form.Source = false
                if type(result) == "table" then
                    merged.Mine = true
                    local record = normalizeRecord(merged)
                    if query.Filter == "All" or query.Filter == "Mine" then
                        table.insert(records, 1, record)
                        renderList()
                        setState(nil)
                    end
                    notify(true, "Config published", name)
                    openDetail(record)
                else
                    notify(true, "Config published", name)
                    showView(views.Browse)
                    fetch(false)
                end
            end
        end)
    end

    -- Handle

    function cloud:Refresh()
        fetch(false)
    end

    function cloud:LoadMore()
        if not loading then
            fetch(true)
        end
    end

    -- For backends that push results instead of answering OnFetch.
    function cloud:SetConfigs(list, more)
        token += 1
        busy(false)
        clearSkeletons()
        records = {}
        for _, raw in ipairs(type(list) == "table" and list or {}) do
            local record = normalizeRecord(raw)
            if record then
                table.insert(records, record)
            end
        end
        hasMore = more == true
        renderList()
        moreButton.Visible = hasMore
        setState(#records == 0 and "empty" or nil, emptyText())
    end

    function cloud:AddConfigs(list, more)
        token += 1
        busy(false)
        clearSkeletons()
        for _, raw in ipairs(type(list) == "table" and list or {}) do
            local record = normalizeRecord(raw)
            if record and not table.find(records, record) then
                table.insert(records, record)
                buildCard(record, #records)
            end
        end
        hasMore = more == true
        moreButton.Visible = hasMore
        setState(#records == 0 and "empty" or nil, emptyText())
    end

    function cloud:UpdateConfig(id, changes)
        local record = byId[tostring(id)]
        if record and type(changes) == "table" then
            local merged = table.clone(changes)
            merged.Id = record.Id
            normalizeRecord(merged)
            refreshRecord(record)
        end
    end

    function cloud:RemoveConfig(id)
        local record = byId[tostring(id)]
        if record then
            removeRecord(record)
            if detailRecord == record and currentView == views.Detail then
                showView(views.Browse)
            end
        end
    end

    function cloud:SetLoading(on)
        token += 1
        busy(on == true)
        clearSkeletons()
        if loading then
            addSkeletons(4)
            setState(nil)
        end
    end

    function cloud:SetError(text)
        token += 1
        busy(false)
        clearSkeletons()
        setState(text and "error" or nil, tostring(text or ""))
    end

    function cloud:Open(id)
        local record = byId[tostring(id)]
        if record then
            window:SelectTab(tab)
            openDetail(record)
        end
    end

    function cloud:Back()
        showView(views.Browse)
    end

    function cloud:GetQuery()
        return table.clone(query)
    end

    function cloud:GetFavorites()
        local list = {}
        for id, kept in pairs(favorites) do
            local copy = table.clone(kept)
            copy.Id = id
            table.insert(list, copy)
        end
        return list
    end

    function cloud:GetInstalled()
        local list = {}
        for id, mark in pairs(installed) do
            table.insert(list, { Id = id, Name = mark.Name, Updated = mark.Updated, Record = mark.Record })
        end
        return list
    end

    renderFilters(true)
    showView(views.Browse)
    -- The first fetch waits until the tab is opened, so a hidden tab costs nothing.
    local fetched = false
    local function firstFetch()
        if not fetched and tab._page.Visible then
            fetched = true
            fetch(false)
        end
    end
    tab._page:GetPropertyChangedSignal("Visible"):Connect(firstFetch)
    if type(opts.OnFetch) ~= "function" then
        fetched = true
        setState("empty", emptyText())
    else
        task.defer(firstFetch)
    end
    return cloud
end

Window.CreateCloudConfigs = Window.CloudConfigs
Window.CloudConfig = Window.CloudConfigs
Window.CreateCloudConfig = Window.CloudConfigs

-- Tab badges were removed. These stay as no-ops so older scripts that call
-- them keep running.
function Tab:SetBadge() end

function Tab:GetBadge()
    return nil
end

function Window:Dialog(opts)
    opts = normalize(opts, { Text = "Content", Message = "Content" })
    if self._dialog then
        self._dialog.Close()
    end
    local WIDTH = 300
    local PAD = 18

    local overlay = create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 40,
        Parent = self.Body,
    })
    local card = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 10),
        Size = UDim2.fromOffset(WIDTH, 120),
        BackgroundColor3 = Theme.Background,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 41,
        Parent = overlay,
    })
    corner(card, UDim.new(0, 10))
    local cardStroke = stroke(card, Theme.Stroke, 1)
    local cardScale = create("UIScale", { Scale = 0.94, Parent = card })
    local fading = {}

    local titleOffset = 0
    if opts.Icon then
        local holder, image = glowIcon(card, opts.Icon, Theme.Accent, UDim2.new(0, PAD, 0, PAD + 9))
        image.ImageTransparency = 1
        holder.ZIndex = 42
        image.ZIndex = 42
        table.insert(fading, { image, "ImageTransparency", 0 })
        titleOffset = 24
    end
    local title = label({
        Position = UDim2.fromOffset(PAD + titleOffset, PAD),
        Size = UDim2.new(1, -(PAD * 2 + titleOffset), 0, 18),
        Text = opts.Title or "Are you sure?",
        TextSize = 15,
        TextTransparency = 1,
        ZIndex = 42,
        Parent = card,
    })
    table.insert(fading, { title, "TextTransparency", 0 })

    local contentHeight = 0
    if opts.Content then
        local content = label({
            Position = UDim2.fromOffset(PAD, PAD + 24),
            Size = UDim2.new(1, -PAD * 2, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Text = opts.Content,
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextWrapped = true,
            TextTransparency = 1,
            TextTruncate = Enum.TextTruncate.None,
            TextYAlignment = Enum.TextYAlignment.Top,
            ZIndex = 42,
            Parent = card,
        })
        table.insert(fading, { content, "TextTransparency", 0 })
        contentHeight = math.max(content.TextBounds.Y, 16) + 6
        content:GetPropertyChangedSignal("TextBounds"):Connect(function()
            local newHeight = math.max(content.TextBounds.Y, 16) + 6
            if newHeight ~= contentHeight then
                contentHeight = newHeight
                card.Size = UDim2.fromOffset(WIDTH, PAD + 24 + contentHeight + 12 + 34 + PAD)
                local rowFrame = card:FindFirstChild("ButtonRow")
                if rowFrame then
                    rowFrame.Position = UDim2.fromOffset(PAD, PAD + 24 + contentHeight + 12)
                end
            end
        end)
    end

    local row = create("Frame", {
        Name = "ButtonRow",
        Position = UDim2.fromOffset(PAD, PAD + 24 + contentHeight + 12),
        Size = UDim2.new(1, -PAD * 2, 0, 34),
        BackgroundTransparency = 1,
        ZIndex = 42,
        Parent = card,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = row,
    })
    card.Size = UDim2.fromOffset(WIDTH, PAD + 24 + contentHeight + 12 + 34 + PAD)

    local dialog = {}
    local closed = false
    function dialog.Close()
        if closed then
            return
        end
        closed = true
        if self._dialog == dialog then
            self._dialog = nil
        end
        tween(overlay, { BackgroundTransparency = 1 }, 0.18)
        tween(card, { BackgroundTransparency = 1, Position = UDim2.new(0.5, 0, 0.5, 8) }, 0.18, Enum.EasingStyle.Quint)
        tween(cardScale, { Scale = 0.96 }, 0.18, Enum.EasingStyle.Quint)
        tween(cardStroke, { Transparency = 1 }, 0.12)
        for _, entry in ipairs(fading) do
            tween(entry[1], { [entry[2]] = 1 }, 0.12)
        end
        task.delay(0.2, function()
            overlay:Destroy()
        end)
    end

    for index, spec in ipairs(opts.Buttons or {}) do
        local primary = spec.Variant == "Primary"
        local buttonFrame = create("TextButton", {
            Size = UDim2.fromOffset(0, 34),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = primary and Theme.Accent or Theme.Surface2,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            ClipsDescendants = true,
            LayoutOrder = index,
            ZIndex = 43,
            Parent = row,
        })
        corner(buttonFrame, UDim.new(0, 7))
        local buttonStroke = stroke(buttonFrame, primary and Theme.Accent or Theme.Stroke, 1)
        if primary then
            bindTheme(buttonFrame, "BackgroundColor3", "Accent")
            bindTheme(buttonStroke, "Color", "Accent")
        end
        padding(buttonFrame, 14, 14)
        local text = label({
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = spec.Title or spec.Name or "OK",
            TextSize = 13,
            TextColor3 = primary and Theme.AccentDark or Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextTransparency = 1,
            ZIndex = 44,
            Parent = buttonFrame,
        })
        local restBg = primary and 0.12 or 0
        local restStroke = primary and 0.4 or 0
        table.insert(fading, { buttonFrame, "BackgroundTransparency", restBg })
        table.insert(fading, { buttonStroke, "Transparency", restStroke })
        table.insert(fading, { text, "TextTransparency", 0 })
        buttonFrame.MouseEnter:Connect(function()
            if closed then
                return
            end
            if primary then
                tween(buttonFrame, { BackgroundTransparency = 0 }, 0.12)
                tween(buttonStroke, { Transparency = 0 }, 0.12)
            else
                tween(buttonStroke, { Color = Theme.StrokeHover }, 0.12)
            end
        end)
        buttonFrame.MouseLeave:Connect(function()
            if closed then
                return
            end
            if primary then
                tween(buttonFrame, { BackgroundTransparency = restBg }, 0.2)
                tween(buttonStroke, { Transparency = restStroke }, 0.2)
            else
                tween(buttonStroke, { Color = Theme.Stroke }, 0.2)
            end
        end)
        buttonFrame.MouseButton1Click:Connect(function()
            dialog.Close()
            safeCall(spec.Callback)
        end)
    end

    if opts.CloseOnBackdrop ~= false then
        overlay.MouseButton1Click:Connect(function()
            dialog.Close()
            safeCall(opts.OnCancel)
        end)
    end

    self._dialog = dialog
    tween(overlay, { BackgroundTransparency = 0.45 }, 0.25)
    tween(card, { BackgroundTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) }, 0.3, Enum.EasingStyle.Quint)
    tween(cardStroke, { Transparency = 0 }, 0.25)
    tween(cardScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
    for _, entry in ipairs(fading) do
        tween(entry[1], { [entry[2]] = entry[3] }, 0.25)
    end
    return dialog
end

function Window:Confirm(opts)
    opts = normalize(opts, { Text = "Content", Message = "Content" })
    return self:Dialog({
        Title = opts.Title or "Are you sure?",
        Content = opts.Content,
        Icon = opts.Icon,
        OnCancel = opts.OnCancel,
        Buttons = {
            { Title = opts.CancelText or "Cancel", Callback = opts.OnCancel },
            { Title = opts.ConfirmText or "Confirm", Variant = "Primary", Callback = opts.Callback },
        },
    })
end

function Window:_listen(kind, handler, owner)
    local list = self._inputListeners[kind]
    table.insert(list, handler)
    local function disconnect()
        for index, entry in ipairs(list) do
            if entry == handler then
                table.remove(list, index)
                break
            end
        end
    end
    if owner then
        owner._listeners = owner._listeners or {}
        table.insert(owner._listeners, disconnect)
    end
    return disconnect
end

function Window:_indicatorY(tab)
    local stack = self._tabStack
    return (tab._button.AbsolutePosition.Y - stack.AbsolutePosition.Y) / self.Scale.Scale + stack.Position.Y.Offset
end

function Window:_placeIndicator(tab)
    local indicator = self.Indicator
    local targetY = self:_indicatorY(tab)
    if not indicator.Visible then
        indicator.Visible = true
        indicator.Position = UDim2.fromOffset(8, targetY)
        indicator.BackgroundTransparency = 1
        tween(indicator, { BackgroundTransparency = 0.35 }, 0.3)
    end
    tween(indicator, { Position = UDim2.fromOffset(8, targetY) }, 0.45, Enum.EasingStyle.Quint)
end

-- While a tab list or sub tab strip runs past an end, that end gets a fade
-- and a small chip with a chevron and how many tabs are out of sight there.
-- Pressing the chip scrolls most of a view toward them.
function Window:_overflowHint(host, scroller, items, vertical, fadeColor)
    local overlay = create("Frame", {
        AnchorPoint = scroller.AnchorPoint,
        Position = scroller.Position,
        Size = scroller.Size,
        BackgroundTransparency = 1,
        ZIndex = 3,
        Parent = host,
    })
    local function mirror()
        overlay.Position = scroller.Position
        overlay.Size = scroller.Size
        overlay.Visible = scroller.Visible
    end
    for _, property in ipairs({ "Position", "Size", "Visible" }) do
        scroller:GetPropertyChangedSignal(property):Connect(mirror)
    end

    local function axis(vector)
        return vertical and vector.Y or vector.X
    end
    local function scale()
        return self.Scale and self.Scale.Scale or 1
    end
    local function scrollBy(direction)
        local view = axis(scroller.AbsoluteWindowSize) / scale()
        local limit = math.max(axis(scroller.AbsoluteCanvasSize) / scale() - view, 0)
        local target = math.clamp(axis(scroller.CanvasPosition) + direction * view * 0.75, 0, limit)
        tween(scroller, { CanvasPosition = vertical and Vector2.new(0, target) or Vector2.new(target, 0) }, 0.35, Enum.EasingStyle.Quint)
    end

    local hints = {}
    for _, direction in ipairs({ -1, 1 }) do
        local far = direction > 0
        local fade = create("Frame", {
            AnchorPoint = vertical and Vector2.new(0, far and 1 or 0) or Vector2.new(far and 1 or 0, 0),
            Position = vertical and UDim2.fromScale(0, far and 1 or 0) or UDim2.fromScale(far and 1 or 0, 0),
            Size = vertical and UDim2.new(1, 0, 0, 34) or UDim2.new(0, 48, 1, 0),
            BackgroundColor3 = fadeColor,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Visible = false,
            Parent = overlay,
        })
        create("UIGradient", {
            Rotation = vertical and (far and 270 or 90) or (far and 180 or 0),
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(0.4, 0.2),
                NumberSequenceKeypoint.new(1, 1),
            }),
            Parent = fade,
        })
        local home = vertical and UDim2.new(0.5, 0, far and 1 or 0, far and -5 or 5) or UDim2.new(far and 1 or 0, far and -2 or 2, 0.5, 0)
        local chip = create("TextButton", {
            AnchorPoint = vertical and Vector2.new(0.5, far and 1 or 0) or Vector2.new(far and 1 or 0, 0.5),
            Position = home,
            Size = UDim2.fromOffset(0, 20),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = Theme.Surface3,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            Visible = false,
            ZIndex = 2,
            Parent = overlay,
        })
        corner(chip, UDim.new(1, 0))
        local chipStroke = stroke(chip, Theme.Stroke, 1)
        padding(chip, 7, 7)
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 3),
            Parent = chip,
        })
        local arrow = create("ImageLabel", {
            Size = UDim2.fromOffset(12, 12),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Accent,
            ImageTransparency = 1,
            ScaleType = Enum.ScaleType.Fit,
            LayoutOrder = 1,
            ZIndex = 2,
            Parent = chip,
        })
        applyIcon(arrow, vertical and (far and "chevron-down" or "chevron-up") or (far and "chevron-right" or "chevron-left"))
        local arrowFade = "ImageTransparency"
        if arrow.Image == "" then
            arrow:Destroy()
            arrow = label({
                Size = UDim2.fromOffset(10, 20),
                Text = "›",
                TextSize = 16,
                TextColor3 = Theme.Accent,
                TextTransparency = 1,
                TextXAlignment = Enum.TextXAlignment.Center,
                TextTruncate = Enum.TextTruncate.None,
                Rotation = vertical and (far and 90 or -90) or (far and 0 or 180),
                LayoutOrder = 1,
                ZIndex = 2,
                Parent = chip,
            })
            arrowFade = "TextTransparency"
        end
        local count = label({
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = "",
            TextSize = 11,
            TextColor3 = Theme.Text,
            TextTransparency = 1,
            TextTruncate = Enum.TextTruncate.None,
            Visible = false,
            LayoutOrder = 2,
            ZIndex = 2,
            Parent = chip,
        })
        chip.MouseEnter:Connect(function()
            if not usingTouch() then
                tween(chipStroke, { Color = Theme.StrokeHover }, 0.12)
            end
        end)
        chip.MouseLeave:Connect(function()
            tween(chipStroke, { Color = Theme.Stroke }, 0.2)
        end)
        chip.MouseButton1Click:Connect(function()
            scrollBy(direction)
        end)
        hints[direction] = {
            Direction = direction,
            Fade = fade,
            Chip = chip,
            Stroke = chipStroke,
            Arrow = arrow,
            ArrowFade = arrowFade,
            Count = count,
            Home = home,
            Shown = false,
            Generation = 0,
        }
    end

    local function show(hint, on)
        if hint.Shown == on then
            return
        end
        hint.Shown = on
        hint.Generation += 1
        local away = hint.Home + (vertical and UDim2.fromOffset(0, hint.Direction * 6) or UDim2.fromOffset(hint.Direction * 6, 0))
        local value = on and 0 or 1
        if on then
            hint.Fade.Visible = true
            hint.Chip.Visible = true
            hint.Chip.Position = away
            tween(hint.Chip, { Position = hint.Home, BackgroundTransparency = 0.08 }, 0.3, Enum.EasingStyle.Quint)
        else
            tween(hint.Chip, { Position = away, BackgroundTransparency = 1 }, 0.2, Enum.EasingStyle.Quint)
            local generation = hint.Generation
            task.delay(0.21, function()
                if hint.Generation == generation then
                    hint.Fade.Visible = false
                    hint.Chip.Visible = false
                end
            end)
        end
        tween(hint.Fade, { BackgroundTransparency = value }, 0.2)
        tween(hint.Stroke, { Transparency = value }, 0.2)
        tween(hint.Arrow, { [hint.ArrowFade] = value }, 0.2)
        tween(hint.Count, { TextTransparency = value }, 0.2)
    end

    local function refresh()
        local view = axis(scroller.AbsoluteWindowSize)
        local overflow = (axis(scroller.AbsoluteCanvasSize) - view) / scale()
        local position = axis(scroller.CanvasPosition)
        local start = axis(scroller.AbsolutePosition)
        local before, after = 0, 0
        for _, item in ipairs(items:GetChildren()) do
            if item:IsA("GuiObject") and item.Visible and axis(item.AbsoluteSize) > 0 then
                local centre = axis(item.AbsolutePosition) + axis(item.AbsoluteSize) / 2 - start
                if centre < 0 then
                    before += 1
                elseif centre > view then
                    after += 1
                end
            end
        end
        for direction, hint in pairs(hints) do
            local hidden = direction < 0 and before or after
            hint.Count.Text = tostring(hidden)
            hint.Count.Visible = hidden > 0
            show(hint, overflow > 1 and (direction < 0 and position > 1 or direction > 0 and position < overflow - 1))
        end
    end
    for _, property in ipairs({ "CanvasPosition", "AbsoluteCanvasSize", "AbsoluteWindowSize" }) do
        scroller:GetPropertyChangedSignal(property):Connect(refresh)
    end
    task.defer(refresh)
end

function Window:_scrollTabIntoView(tab)
    local list = self.TabList
    local scale = self.Scale.Scale
    local top = (tab._button.AbsolutePosition.Y - list.AbsolutePosition.Y) / scale + list.CanvasPosition.Y
    local bottom = top + tab._button.AbsoluteSize.Y / scale
    local view = list.AbsoluteWindowSize.Y / scale
    local y = list.CanvasPosition.Y
    if top - 8 < y then
        y = top - 8
    elseif bottom + 8 > y + view then
        y = bottom + 8 - view
    else
        return
    end
    tween(list, { CanvasPosition = Vector2.new(0, math.max(0, y)) }, 0.35, Enum.EasingStyle.Quint)
end

function Window:_closePopups()
    if self._closePopup then
        self._closePopup()
    end
end

-- Popped-out groupboxes float on one screen-wide layer above the window. It
-- carries the window's scale, so a panel keeps the size it had in its column,
-- and it shows while the window is open (minimized included).
function Window:_popoutLayer()
    if self._popLayer then
        return self._popLayer
    end
    local layer = create("Frame", {
        Name = "PopOuts",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ZIndex = 20,
        Parent = self.Gui,
    })
    local layerScale = create("UIScale", { Parent = layer })
    self._popLayer = layer
    self._popPanels = {}
    self:_listen("Render", function()
        local scale = math.max(self.Scale.Scale, 0.05)
        if math.abs(layerScale.Scale - scale) > 1e-4 then
            layerScale.Scale = scale
            layer.Size = UDim2.fromScale(1 / scale, 1 / scale)
        end
        layer.Visible = self.Open == true and not self._destroyed
    end)
    return layer
end

-- Where a control's popup is drawn: the pop-out layer for one inside a
-- floating panel, otherwise the window body.
function Window:_popupHost(object)
    local layer = self._popLayer
    if layer and object and object:IsDescendantOf(layer) then
        return layer
    end
    return self.Body
end

-- A floating panel under the point counts as a control, so pressing it never
-- starts a window drag.
function Window:_overPopout(point)
    local layer = self._popLayer
    if not layer or not layer.Visible then
        return false
    end
    for _, panel in ipairs(self._popPanels) do
        if panel.Parent and panel.Visible and pointInside(point, panel) then
            return true
        end
    end
    return false
end

-- Fades the whole body by lending it to the fader CanvasGroup, then hands it
-- back to the root once fully shown so it renders directly again.
function Window:_fade(target, duration)
    local fader, body = self._fader, self.Body
    self._fadeGeneration = (self._fadeGeneration or 0) + 1
    local generation = self._fadeGeneration
    if body.Parent ~= fader then
        fader.GroupTransparency = self._bodyAlpha
        body.Parent = fader
    end
    fader.Visible = true
    self._bodyAlpha = target
    tween(fader, { GroupTransparency = target }, duration)
    task.delay(duration + 0.03, function()
        if self._fadeGeneration == generation and target <= 0 and not self._destroyed then
            body.Parent = self.Root
            fader.Visible = false
        end
    end)
end

function Window:SelectTab(tab)
    if self.CurrentTab == tab then
        return
    end
    local previous = self.CurrentTab
    self:_resetSearch()
    self:_closePopups()
    self.CurrentTab = tab

    self:_settleTransition()
    local generation = (self._transitionGeneration or 0) + 1
    self._transitionGeneration = generation

    if previous then
        tween(previous._label, { TextColor3 = Theme.Muted }, 0.3)
        if previous._icon then
            tintIcon(previous._icon, Theme.Muted, false, 0.3)
        end
        local outLayer = self._outLayer
        previous._page.Parent = outLayer
        self._outPage = previous._page
        outLayer.GroupTransparency = 0
        outLayer.Position = UDim2.fromOffset(0, 0)
        outLayer.Visible = true
        tween(outLayer, { GroupTransparency = 1, Position = UDim2.fromOffset(0, -6) }, 0.2, Enum.EasingStyle.Quint)
        task.delay(0.18, function()
            if self._transitionGeneration == generation then
                self:_settleOut()
            end
        end)
    end

    tween(tab._button, { BackgroundTransparency = 1 }, 0.2)
    tween(tab._stroke, { Transparency = 1 }, 0.2)
    tween(tab._label, { TextColor3 = Theme.Text }, 0.3)
    if tab._icon then
        tintIcon(tab._icon, Theme.Text, true, 0.3)
    end

    self:_placeIndicator(tab)
    self:_scrollTabIntoView(tab)

    local page = tab._page
    page.Position = UDim2.fromOffset(0, 0)
    page.Visible = true
    page.Parent = self._inLayer
    self._inPage = page
    fadeSlideIn(self._inLayer)
    task.delay(0.32, function()
        if self._transitionGeneration == generation then
            self:_settleIn()
        end
    end)
end

function Window:_settleOut()
    local page = self._outPage
    if page then
        page.Parent = self.Content
        page.Visible = false
        self._outPage = nil
    end
    self._outLayer.Visible = false
end

function Window:_settleIn()
    local page = self._inPage
    if page then
        page.Parent = self.Content
        page.Position = UDim2.fromOffset(0, 0)
        self._inPage = nil
    end
    self._inLayer.Visible = false
end

function Window:_settleTransition()
    self:_settleOut()
    self:_settleIn()
end

-- Backdrop: a black tint over the game while the window is up.
-- It fades out when the window is minimized or hidden and fades back in when restored.

function Window:_buildBackdrop(opts)
    local layer = create("Frame", {
        Name = "Backdrop",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 0,
        Parent = self.Gui,
    })
    local tint = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 0,
        Parent = layer,
    })
    -- Darker towards the top and bottom edges.
    create("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(0.5, 0.3),
            NumberSequenceKeypoint.new(1, 0),
        }),
        Parent = tint,
    })
    self._backdrop = layer
    self._backdropTintFrame = tint
    self._backdropFade = 0
    self._backdropShown = false
    self._backdropEnabled = opts.Enabled ~= false
    self._backdropTint = math.clamp(tonumber(opts.Tint) or 0.45, 0, 1)
    self._backdropDim = opts.Dim ~= false
    self._dimLevel = self._backdropDim and 1 or 0
    table.insert(self._frameSteps, function(deltaTime)
        self:_stepBackdrop(deltaTime)
    end)
end

-- The area the particles cover, in the field's own (unscaled) units.
function Window:_stepBackdrop(deltaTime)
    local target = (self._backdropEnabled and self._backdropShown) and 1 or 0
    local fade = self._backdropFade
    if fade == target and target == 0 then
        return
    end
    if fade < target then
        fade = math.min(fade + deltaTime / 0.45, target)
    elseif fade > target then
        fade = math.max(fade - deltaTime / 0.25, target)
    end
    self._backdropFade = fade
    if fade <= 0 then
        self._backdrop.Visible = false
        return
    end
    self._backdrop.Visible = true
    local eased = 1 - (1 - fade) ^ 3
    local dim = self._dimLevel
    if self._backdropDim then
        dim = math.min(dim + deltaTime / 0.3, 1)
    else
        dim = math.max(dim - deltaTime / 0.3, 0)
    end
    self._dimLevel = dim
    self._backdropTintFrame.BackgroundTransparency = 1 - self._backdropTint * eased * dim
end

function Window:_refreshBackdrop()
    if not self._backdrop then
        return
    end
    local shown = self._backdropEnabled and self._introDone and self.Open and not self.Minimized and not self._destroyed
    if shown and not self._backdropShown then
        self._backdrop.Visible = true
    end
    self._backdropShown = shown == true
end

function Window:SetBackdrop(enabled)
    if not self._backdrop then
        return
    end
    self._backdropEnabled = enabled ~= false
    self:_refreshBackdrop()
end

function Window:SetBackdropTint(amount)
    if not self._backdrop then
        return
    end
    self._backdropTint = math.clamp(tonumber(amount) or 0.45, 0, 1)
end

function Window:SetDim(enabled)
    if not self._backdrop then
        return
    end
    self._backdropDim = enabled ~= false
end

-- Minimize: the window folds into a Dynamic Island style pill hanging from
-- the top of the screen. Compact, it shows the logo and a live meter of
-- running toggles. Hovering springs it open into a session card: the
-- player, the game and session time, frame rate and ping meters, the server
-- and running counts, and the key that reopens the window. A
-- notification while minimized opens it briefly to show it. Click or tap
-- restores.

-- One table, not separate locals: the main chunk is at Luau's 200 local limit.
local Mini = {
    -- Sized after the iPhone 18 island: a slimmer, shorter pill sitting close
    -- to the top edge, opening into a wide card with deep rounded corners.
    Top = 8, -- gap from the top of the screen
    Width = TOUCH and 176 or 168, -- compact
    Height = TOUCH and 36 or 32,
    Wide = 340, -- expanded and activity
    Radius = 34, -- corner of the expanded and activity cards
    Bars = 4,
    Pinned = 6,
}

-- The morph is carried by a plain "ghost" panel drawn over the window. The
-- window body itself never moves or fades, so nothing has to be laid out
-- again mid-animation: the ghost covers it, the window is hidden underneath,
-- and on the way back the window is shown under the ghost before it clears.
local function makeGhost(window, position, size, radius)
    if window._ghost then
        window._ghost:Destroy()
    end
    local ghost = create("Frame", {
        Position = UDim2.fromOffset(position.X, position.Y),
        Size = UDim2.fromOffset(size.X, size.Y),
        BackgroundColor3 = Theme.Background,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 29,
        Parent = window.Gui,
    })
    local ghostCorner = Library._fixedCorner(ghost, UDim.new(0, radius))
    local ghostStroke = stroke(ghost, Theme.Stroke, 1)
    window._ghost = ghost
    return ghost, ghostStroke, ghostCorner
end

local function morphGhost(ghost, ghostCorner, position, size, radius, duration)
    tween(ghost, {
        Position = UDim2.fromOffset(position.X, position.Y),
        Size = UDim2.fromOffset(size.X, size.Y),
    }, duration, Enum.EasingStyle.Quint)
    tween(ghostCorner, { CornerRadius = UDim.new(0, radius) }, duration, Enum.EasingStyle.Quint)
end

local function dissolve(window, ghost, ghostStroke, duration)
    tween(ghost, { BackgroundTransparency = 1 }, duration, Enum.EasingStyle.Quad)
    tween(ghostStroke, { Transparency = 1 }, duration, Enum.EasingStyle.Quad)
    task.delay(duration + 0.02, function()
        if window._ghost == ghost then
            window._ghost = nil
        end
        ghost:Destroy()
    end)
end

function Window:_buildMiniBar()
    if self.MiniBar then
        return self.MiniBar
    end
    local gui = self.Gui

    -- The island itself: a black pill hanging from the top of the screen. It
    -- is a canvas so its rounded shape clips whatever layer is showing.
    local island = create("CanvasGroup", {
        Name = "Island",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, Mini.Top),
        Size = UDim2.fromOffset(Mini.Width, Mini.Height),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BorderSizePixel = 0,
        GroupTransparency = 1,
        Visible = false,
        ZIndex = 30,
        Parent = gui,
    })
    local islandCorner = Library._fixedCorner(island, UDim.new(0, Mini.Height / 2))
    local islandScale = create("UIScale", { Parent = island })
    self._miniScale = islandScale
    -- How far the split bubble is out of the pill: drawn back in while the
    -- island is open, budded off again once it settles to the pill.
    local merge = create("NumberValue", { Value = 1 })
    local mergeTween
    self._miniOrb = island

    -- The wide layers keep a fixed width, so nothing reflows while the island
    -- grows around them.
    local function layer(name)
        return create("CanvasGroup", {
            Name = name,
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.fromScale(0.5, 0),
            Size = UDim2.new(0, Mini.Wide, 0, 400),
            BackgroundTransparency = 1,
            GroupTransparency = 1,
            Parent = island,
        })
    end

    -- Compact: the logo leading, a live meter of running toggles trailing.
    -- A graphite surface, lit from the top, so the pill isn't a flat black
    -- slab; it fades with the layer, leaving the open card black.
    local compact = create("CanvasGroup", {
        Name = "Compact",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(30, 30, 34),
        BorderSizePixel = 0,
        Parent = island,
    })
    create("UIGradient", {
        Rotation = 90,
        Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 120, 120)),
        Parent = compact,
    })
    -- The logo sits in a soft accent disc, like an app glyph.
    local logoDisc = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 5, 0.5, 0),
        Size = UDim2.fromOffset(Mini.Height - 10, Mini.Height - 10),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 0.82,
        BorderSizePixel = 0,
        Parent = compact,
    })
    corner(logoDisc, UDim.new(1, 0))
    local logo = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(16, 16),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Accent,
        ScaleType = Enum.ScaleType.Fit,
        Parent = logoDisc,
    })
    applyIcon(logo, self._logoIcon, true)
    -- The script's name beside the logo, so the pill reads at a glance.
    local miniTitle = label({
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, Mini.Height + 2, 0.5, 0),
        Size = UDim2.new(1, -Mini.Height - 2 - 72, 0, 18),
        Text = self.Title,
        TextSize = 13,
        FontFace = Fonts.Bold,
        TextColor3 = Color3.fromRGB(244, 244, 246),
        Parent = compact,
    })
    local meter = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -14, 0.5, 0),
        Size = UDim2.fromOffset(0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Parent = compact,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 7),
        Parent = meter,
    })
    local barsHolder = create("Frame", {
        Size = UDim2.fromOffset(Mini.Bars * 3 + (Mini.Bars - 1) * 2, 16),
        BackgroundTransparency = 1,
        Visible = false,
        LayoutOrder = 1,
        Parent = meter,
    })
    local bars = {}
    for index = 1, Mini.Bars do
        local bar = create("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, (index - 1) * 5, 0.5, 0),
            Size = UDim2.fromOffset(3, 3),
            BackgroundColor3 = Theme.Muted,
            BorderSizePixel = 0,
            Parent = barsHolder,
        })
        corner(bar, UDim.new(1, 0))
        bars[index] = bar
    end
    local countLabel = label({
        Size = UDim2.fromOffset(0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = "",
        TextSize = 13,
        FontFace = Fonts.Bold,
        TextTruncate = Enum.TextTruncate.None,
        Visible = false,
        LayoutOrder = 2,
        Parent = meter,
    })
    -- Idle (nothing running): a health dot tinted by frame rate and the
    -- session clock, so the pill never sits empty.
    local idleDot = create("Frame", {
        Size = UDim2.fromOffset(6, 6),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        LayoutOrder = -1,
        Parent = meter,
    })
    corner(idleDot, UDim.new(1, 0))
    local idleLabel = label({
        Size = UDim2.fromOffset(0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = "0s",
        TextSize = 12,
        FontFace = Fonts.Bold,
        TextColor3 = Color3.fromRGB(220, 220, 224),
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 0,
        Parent = meter,
    })

    -- Expanded, on hover: the player's session.
    local expanded = layer("Expanded")
    local expandedList = create("Frame", {
        Position = UDim2.fromOffset(16, 14),
        Size = UDim2.new(1, -32, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = expanded,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = expandedList,
    })
    -- The open card is the player's session, like a now-playing card: who
    -- and where on top with the session clock, two wide meters for frame
    -- rate and ping, then chips for the server and what's running.
    local top = create("Frame", {
        Size = UDim2.new(1, 0, 0, 48),
        BackgroundTransparency = 1,
        LayoutOrder = 1,
        Parent = expandedList,
    })
    local face = create("ImageLabel", {
        Size = UDim2.fromOffset(48, 48),
        BackgroundColor3 = Color3.fromRGB(38, 38, 41),
        BorderSizePixel = 0,
        Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(LocalPlayer.UserId) .. "&w=150&h=150",
        Parent = top,
    })
    corner(face, UDim.new(0, 12))
    local facePlaceholder = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(20, 20),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Fit,
        Parent = face,
    })
    applyIcon(facePlaceholder, "user")
    self:_trackAvatar(face, facePlaceholder)
    local nameLabel = label({
        Position = UDim2.fromOffset(60, 5),
        Size = UDim2.new(1, -150, 0, 20),
        TextSize = 15,
        FontFace = Fonts.Bold,
        TextColor3 = Color3.fromRGB(244, 244, 246),
        Parent = top,
    })
    self:_trackName(nameLabel, "Display")
    local tabLabel = label({
        Position = UDim2.fromOffset(60, 26),
        Size = UDim2.new(1, -150, 0, 15),
        Text = "",
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = top,
    })
    task.spawn(function()
        tabLabel.Text = detectGameName()
    end)
    local sessionLabel = label({
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 3),
        Size = UDim2.fromOffset(90, 24),
        Text = "0s",
        TextSize = 20,
        FontFace = Fonts.Bold,
        TextColor3 = Color3.fromRGB(244, 244, 246),
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = top,
    })
    label({
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 27),
        Size = UDim2.fromOffset(90, 14),
        Text = "session",
        TextSize = 11,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = top,
    })

    -- Two readouts: a large number with its unit, a caption, and a thin
    -- line under them that fills and tints with how healthy it is.
    local meters = create("Frame", {
        Size = UDim2.new(1, 0, 0, 42),
        BackgroundTransparency = 1,
        LayoutOrder = 2,
        Parent = expandedList,
    })
    local function meterPill(position, caption)
        local cell = create("Frame", {
            Position = position,
            Size = UDim2.new(0.5, -10, 1, 0),
            BackgroundTransparency = 1,
            Parent = meters,
        })
        local value = label({
            Size = UDim2.new(1, -70, 0, 24),
            Text = "",
            TextSize = 20,
            FontFace = Fonts.Bold,
            TextColor3 = Color3.fromRGB(244, 244, 246),
            RichText = true,
            Parent = cell,
        })
        label({
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, 0, 0, 6),
            Size = UDim2.fromOffset(70, 14),
            Text = caption,
            TextSize = 10,
            TextColor3 = Theme.Muted,
            TextXAlignment = Enum.TextXAlignment.Right,
            Parent = cell,
        })
        local track = create("Frame", {
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, 0, 1, -4),
            Size = UDim2.new(1, 0, 0, 3),
            BackgroundColor3 = Color3.fromRGB(38, 38, 42),
            BorderSizePixel = 0,
            Parent = cell,
        })
        corner(track, UDim.new(1, 0))
        local fill = create("Frame", {
            Size = UDim2.fromScale(0, 1),
            BackgroundColor3 = Theme.Success,
            BorderSizePixel = 0,
            Parent = track,
        })
        corner(fill, UDim.new(1, 0))
        return fill, value
    end
    local fpsFill, fpsValue = meterPill(UDim2.fromScale(0, 0), "FRAME RATE")
    local pingFill, pingValue = meterPill(UDim2.new(0.5, 10, 0, 0), "PING")

    -- Chips: a muted name and a bold value, the running count in accent.
    local chips = create("Frame", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1,
        LayoutOrder = 3,
        Parent = expandedList,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = chips,
    })
    local function chipOf(order, name, color)
        local chipFrame = create("Frame", {
            Size = UDim2.fromOffset(0, 30),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = Color3.fromRGB(32, 32, 35),
            BorderSizePixel = 0,
            LayoutOrder = order,
            Parent = chips,
        })
        corner(chipFrame, UDim.new(1, 0))
        padding(chipFrame, 14, 14)
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 7),
            Parent = chipFrame,
        })
        label({
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = name,
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = 1,
            Parent = chipFrame,
        })
        return label({
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = "",
            TextSize = 12,
            FontFace = Fonts.Bold,
            TextColor3 = color or Color3.fromRGB(244, 244, 246),
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = 2,
            Parent = chipFrame,
        })
    end
    local playersValue = chipOf(1, "Players")
    local bigCount = chipOf(2, "Running", Theme.Accent)
    local tabValue = chipOf(3, "Tab")

    -- Pinned statuses are no longer shown here; the holder stays so the
    -- refresh below has somewhere to keep its rows.
    local rowsHolder = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1,
        Visible = false,
        LayoutOrder = 4,
        Parent = expandedList,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = rowsHolder,
    })
    -- What's running, by name, so the count above has something behind it.
    local runningNames = label({
        Size = UDim2.new(1, 0, 0, 15),
        Text = "",
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Color3.fromRGB(200, 200, 206),
        RichText = true,
        Visible = false,
        LayoutOrder = 4,
        Parent = expandedList,
    })
    local hint = label({
        Size = UDim2.new(1, 0, 0, 14),
        TextSize = 11,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        LayoutOrder = 5,
        Parent = expandedList,
    })

    -- Frame rate is counted every frame; the card's values refresh twice a
    -- second while it's open.
    local sessionStart = self._sessionStart or os.clock()
    local frames, frameClock, fps = 0, os.clock(), 60
    self:_listen("Render", function()
        frames += 1
        local now = os.clock()
        if now - frameClock >= 0.5 then
            fps = math.floor(frames / (now - frameClock) + 0.5)
            frames, frameClock = 0, now
        end
    end)
    local function refreshSession()
        sessionLabel.Text = formatDuration(os.clock() - sessionStart)
        idleLabel.Text = sessionLabel.Text
        tween(idleDot, { BackgroundColor3 = Library._healthColor(fps, 50, 30) }, 0.4)
        local unit = '<font size="12" color="#8A8A93"> %s</font>'
        fpsValue.Text = fps .. string.format(unit, "fps")
        tween(fpsFill, {
            Size = UDim2.fromScale(math.clamp(fps / 60, 0.05, 1), 1),
            BackgroundColor3 = Library._healthColor(fps, 50, 30),
        }, 0.4, Enum.EasingStyle.Quint)
        local okPing, ping = pcall(function()
            return math.floor(LocalPlayer:GetNetworkPing() * 1000)
        end)
        ping = okPing and ping or 0
        pingValue.Text = ping .. string.format(unit, "ms")
        -- Lower ping fills more: 40ms or less is full, 400ms and up is low.
        tween(pingFill, {
            Size = UDim2.fromScale(math.clamp(1 - (ping - 40) / 360, 0.05, 1), 1),
            BackgroundColor3 = Library._healthColor(ping, 90, 180, true),
        }, 0.4, Enum.EasingStyle.Quint)
        playersValue.Text = #Players:GetPlayers() .. "/" .. Players.MaxPlayers
        local tab = self.CurrentTab
        tabValue.Text = tab and tab.Name or "-"
    end
    task.spawn(function()
        while island.Parent do
            if island.Visible and self.Minimized then
                refreshSession()
            end
            task.wait(0.5)
        end
    end)

    -- Activity: a notification that arrives while minimized drops in here.
    local activity = layer("Activity")
    local activityList = create("Frame", {
        Position = UDim2.fromOffset(16, 13),
        Size = UDim2.new(1, -32, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = activity,
    })
    local activityChip = create("Frame", {
        Size = UDim2.fromOffset(34, 34),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 0.85,
        BorderSizePixel = 0,
        Parent = activityList,
    })
    corner(activityChip, UDim.new(1, 0))
    local activityIcon = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(17, 17),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Accent,
        ScaleType = Enum.ScaleType.Fit,
        Parent = activityChip,
    })
    local activityText = create("Frame", {
        Position = UDim2.fromOffset(46, 0),
        Size = UDim2.new(1, -46, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = activityList,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 1),
        Parent = activityText,
    })
    local activityTitle = label({
        Size = UDim2.new(1, 0, 0, 18),
        TextSize = 14,
        FontFace = Fonts.Bold,
        LayoutOrder = 1,
        Parent = activityText,
    })
    local activityBody = label({
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None,
        TextYAlignment = Enum.TextYAlignment.Top,
        MaxVisibleGraphemes = 140,
        LayoutOrder = 2,
        Parent = activityText,
    })

    local hit = create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 10,
        Parent = island,
    })

    -- Morphing between shapes: the island springs to its new size while the
    -- old layer fades out and the new one fades in just behind it.
    local layers = { Compact = compact, Expanded = expanded, Activity = activity }
    local mode = "Compact"
    local modeToken = 0
    local sizeTween, cornerTween
    local hovered, pressed = false, false
    local hoverToken = 0
    local dragFrom, dragAnchor, dragging, dragged = nil, nil, false, false
    local activityToken = 0
    local activityLive = false

    local function shapeFor(name)
        if name == "Expanded" then
            return Vector2.new(Mini.Wide, math.floor(expandedList.AbsoluteSize.Y + 28 + 0.5)), Mini.Radius
        elseif name == "Activity" then
            return Vector2.new(Mini.Wide, math.floor(math.max(activityList.AbsoluteSize.Y, 34) + 26 + 0.5)), Mini.Radius
        end
        return Vector2.new(Mini.Width, Mini.Height), Mini.Height / 2
    end

    -- Where the island hangs: the top centre of its shape, as fractions of
    -- the screen so it keeps its spot across resolutions. Dragging moves it;
    -- each shape is clamped on screen, so the wide card slides in from an edge
    -- and the pill goes back to its spot when it folds.
    local saved = self:_readConfigSettings().IslandPosition
    if type(saved) == "table" and tonumber(saved.X) and tonumber(saved.Y) then
        self._islandAnchor = Vector2.new(math.clamp(tonumber(saved.X), 0, 1), math.clamp(tonumber(saved.Y), 0, 1))
    end
    local positionTween
    local function anchorPixels()
        local view = gui.AbsoluteSize
        local anchor = self._islandAnchor
        if not anchor then
            return Vector2.new(view.X / 2, Mini.Top)
        end
        return Vector2.new(anchor.X * view.X, anchor.Y * view.Y)
    end
    local function islandSpot(size, from)
        local view = gui.AbsoluteSize
        local spot = from or anchorPixels()
        local margin = 6
        local x = math.clamp(spot.X, size.X / 2 + margin, math.max(view.X - size.X / 2 - margin, size.X / 2 + margin))
        local y = math.clamp(spot.Y, margin, math.max(view.Y - size.Y - margin, margin))
        return Vector2.new(x, y)
    end
    local function placeIsland(size, duration, style)
        local spot = islandSpot(size)
        if positionTween then
            positionTween:Cancel()
            positionTween = nil
        end
        if duration and duration > 0 then
            positionTween = tween(island, { Position = UDim2.fromOffset(spot.X, spot.Y) }, duration, style or Enum.EasingStyle.Quint)
        else
            island.Position = UDim2.fromOffset(spot.X, spot.Y)
        end
    end
    self._islandReset = function()
        self._islandAnchor = nil
        if island.Visible then
            placeIsland(Vector2.new(island.Size.X.Offset, island.Size.Y.Offset), 0.35)
        end
    end

    local function setMode(name, instant)
        local size, radius = shapeFor(name)
        local changed = name ~= mode
        mode = name
        modeToken += 1
        local token = modeToken
        local current = Vector2.new(island.Size.X.Offset, island.Size.Y.Offset)
        local growing = size.X > current.X + 1 or size.Y > current.Y + 1
        local duration = instant and 0 or (growing and 0.5 or 0.38)
        -- A snap must stop a morph still in flight, or it keeps writing the
        -- old shape over the new one.
        if sizeTween then
            sizeTween:Cancel()
        end
        if cornerTween then
            cornerTween:Cancel()
        end
        placeIsland(size, duration)
        sizeTween = tween(island, { Size = UDim2.fromOffset(size.X, size.Y) }, duration, growing and Enum.EasingStyle.Back or Enum.EasingStyle.Quint)
        cornerTween = tween(islandCorner, { CornerRadius = UDim.new(0, radius) }, duration, Enum.EasingStyle.Quint)
        -- The iOS island gives a soft squeeze as it swells open, then springs
        -- back, so the morph reads as one elastic body rather than a resize.
        if changed and not instant and not pressed and not dragging then
            islandScale.Scale = growing and 0.96 or 1.03
            tween(islandScale, { Scale = 1 }, growing and 0.55 or 0.4, Enum.EasingStyle.Back)
        end
        if changed or instant then
            if mergeTween then
                mergeTween:Cancel()
                mergeTween = nil
            end
            if instant then
                merge.Value = name == "Compact" and 1 or 0
            elseif name == "Compact" then
                -- Wait for the pill to shrink most of the way, then bud off.
                task.delay(duration * 0.55, function()
                    if modeToken == token then
                        mergeTween = tween(merge, { Value = 1 }, 0.6, Enum.EasingStyle.Back)
                    end
                end)
            else
                mergeTween = tween(merge, { Value = 0 }, 0.2, Enum.EasingStyle.Quint)
            end
        end
        if not changed and not instant then
            -- A refit (same shape, new height) bumps the token, which cancels
            -- a fade-in still waiting from the morph; finish it here or the
            -- card stays black until the next hover.
            local target = layers[name]
            if target.GroupTransparency > 0 then
                tween(target, { GroupTransparency = 0 }, 0.22, Enum.EasingStyle.Quad)
            end
            if target ~= compact and target.Position ~= UDim2.fromScale(0.5, 0) then
                tween(target, { Position = UDim2.fromScale(0.5, 0) }, 0.32, Enum.EasingStyle.Quint)
            end
            return
        end
        for key, group in pairs(layers) do
            if key ~= name then
                tween(group, { GroupTransparency = 1 }, instant and 0 or 0.14, Enum.EasingStyle.Quad)
            end
        end
        local target = layers[name]
        if instant then
            target.GroupTransparency = 0
            -- Compact fills the island from its corner; only the wide
            -- layers hang from the centre.
            if target ~= compact then
                target.Position = UDim2.fromScale(0.5, 0)
            end
        else
            -- The new layer rises a few pixels into place as it fades in, so
            -- the content reads as arriving with the shape, not popping in.
            if target ~= compact then
                target.Position = UDim2.new(0.5, 0, 0, 6)
            end
            task.delay(0.1, function()
                if modeToken == token then
                    tween(target, { GroupTransparency = 0 }, 0.22, Enum.EasingStyle.Quad)
                    if target ~= compact then
                        tween(target, { Position = UDim2.fromScale(0.5, 0) }, 0.32, Enum.EasingStyle.Quint)
                    end
                end
            end)
        end
    end

    local function settleMode()
        if hovered and not TOUCH and not dragging then
            setMode("Expanded")
        elseif activityLive then
            setMode("Activity")
        elseif self.IslandStyle == "Always Show" and not dragging then
            self:_refreshMini()
            refreshSession()
            setMode("Expanded")
        else
            setMode("Compact")
        end
    end

    self._islandSettle = function()
        if self.Minimized and island.Visible and not dragging then
            settleMode()
        end
    end

    -- Called by Minimize once the window is out of the way: the island is
    -- reset to its compact pill and its spot handed back for the ghost.
    function self:_miniLand()
        hovered, activityLive = false, false
        activityToken += 1
        islandScale.Scale = 1
        setMode("Compact", true)
        local size = Vector2.new(Mini.Width, Mini.Height)
        local spot = islandSpot(size)
        return Vector2.new(spot.X - size.X / 2, spot.Y), size
    end

    hit.MouseEnter:Connect(function()
        if usingTouch() or dragging then
            return
        end
        hovered = true
        hoverToken += 1
        local token = hoverToken
        -- Already open (the pointer left and came back within the grace):
        -- just stay. Otherwise lean in a touch, and only open once the
        -- pointer rests, so sweeping past the island doesn't burst it open.
        if mode == "Expanded" then
            return
        end
        if not pressed then
            tween(islandScale, { Scale = 1.04 }, 0.18, Enum.EasingStyle.Quint)
        end
        task.delay(0.12, function()
            if hoverToken == token and hovered and self.Minimized and not dragging then
                self:_refreshMini()
                refreshSession()
                setMode("Expanded")
            end
        end)
    end)
    hit.MouseLeave:Connect(function()
        hovered = false
        hoverToken += 1
        local token = hoverToken
        if not pressed then
            tween(islandScale, { Scale = 1 }, 0.25, Enum.EasingStyle.Quint)
        end
        -- A grace period: the card shifts while it morphs and clamps on
        -- screen, so a pointer grazing its edge shouldn't snap it shut.
        task.delay(mode == "Expanded" and 0.28 or 0.1, function()
            if hoverToken == token and not hovered and self.Minimized then
                settleMode()
            end
        end)
    end)
    -- Press and pull to move the island anywhere on screen. It folds to the
    -- pill while carried, lifts a little, and a drop near its home at the top
    -- centre snaps back there. A drag never counts as the click that restores.
    hit.InputBegan:Connect(function(input)
        if not isPress(input) then
            return
        end
        pressed = true
        dragged = false
        tween(islandScale, { Scale = 0.95 }, 0.12, Enum.EasingStyle.Quad)
        if not self._islandLocked then
            dragFrom = Vector2.new(input.Position.X, input.Position.Y)
            dragAnchor = islandSpot(Vector2.new(Mini.Width, Mini.Height))
        end
    end)
    self:_listen("Changed", function(input)
        if not dragFrom or not isMove(input) or not self.Minimized then
            return
        end
        local delta = Vector2.new(input.Position.X, input.Position.Y) - dragFrom
        if not dragging then
            if delta.Magnitude < (TOUCH and 10 or 6) then
                return
            end
            dragging, dragged = true, true
            hovered = false
            setMode("Compact")
            tween(islandScale, { Scale = 1.06 }, 0.2, Enum.EasingStyle.Quint)
        end
        local spot = islandSpot(Vector2.new(Mini.Width, Mini.Height), dragAnchor + delta)
        local view = gui.AbsoluteSize
        self._islandAnchor = Vector2.new(spot.X / math.max(view.X, 1), spot.Y / math.max(view.Y, 1))
        if positionTween then
            positionTween:Cancel()
            positionTween = nil
        end
        island.Position = UDim2.fromOffset(spot.X, spot.Y)
    end)
    table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
        if not isPress(input) then
            return
        end
        dragFrom = nil
        if pressed then
            pressed = false
            tween(islandScale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
        end
        if dragging then
            dragging = false
            local home = Vector2.new(gui.AbsoluteSize.X / 2, Mini.Top)
            local spot = islandSpot(Vector2.new(Mini.Width, Mini.Height))
            if (spot - home).Magnitude < 28 then
                self._islandAnchor = nil
                placeIsland(Vector2.new(Mini.Width, Mini.Height), 0.35, Enum.EasingStyle.Back)
            end
            local anchor = self._islandAnchor
            self:_writeConfigSettings({ IslandPosition = anchor and { X = anchor.X, Y = anchor.Y } or false })
            hovered = not usingTouch() and pointInside(pointerPosition(), island)
            task.delay(0.1, function()
                if self.Minimized and not dragging then
                    settleMode()
                end
            end)
        end
    end))
    -- Keeps the island on screen when the viewport changes size.
    table.insert(self._connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if island.Visible and not dragging then
            placeIsland(Vector2.new(island.Size.X.Offset, island.Size.Y.Offset), 0)
        end
    end))
    hit.MouseButton1Click:Connect(function()
        if dragged then
            dragged = false
            return
        end
        if self.Minimized then
            self:Restore()
        end
    end)
    -- Restore hides the island under the pointer, so MouseLeave never fires.
    self._miniUnhover = function()
        hovered, pressed, activityLive = false, false, false
        dragFrom, dragging = nil, false
        activityToken += 1
        islandScale.Scale = 1
        -- Clicked open while expanded: once the island has faded out, fold it
        -- back to the pill so the next minimize starts from it.
        task.delay(0.15, function()
            if not self.Minimized then
                setMode("Compact", true)
            end
        end)
    end

    -- A notification while minimized: the island opens to show it for a few
    -- seconds, then folds back.
    self._islandActivity = function(opts)
        if not self.Minimized or not island.Visible then
            return
        end
        local color = NOTIFY_COLORS[opts.Type] or Theme.Accent
        activityTitle.Text = tostring(opts.Title or "Notification")
        activityTitle.TextColor3 = NOTIFY_COLORS[opts.Type] or Theme.Text
        activityBody.Text = tostring(opts.Content or "")
        activityBody.Visible = activityBody.Text ~= ""
        local icon = opts.Icon
        if icon == nil then
            icon = ({ Success = "circle-check", Warning = "triangle-alert", Error = "circle-x" })[opts.Type] or "bell"
        end
        applyIcon(activityIcon, icon)
        if not activityIcon:GetAttribute("CustomIcon") then
            activityIcon.ImageColor3 = color
        end
        activityChip.BackgroundColor3 = color
        activityLive = true
        activityToken += 1
        local token = activityToken
        task.defer(function()
            if activityToken == token and not hovered and not dragging then
                setMode("Activity")
                islandScale.Scale = 0.96
                tween(islandScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
            end
        end)
        task.delay(math.clamp(tonumber(opts.Duration) or 3, 1.5, 5), function()
            if activityToken == token then
                activityLive = false
                if self.Minimized and not hovered then
                    settleMode()
                end
            end
        end)
    end

    -- The meter dances while anything runs and lies flat when nothing does.
    local running = 0
    self:_listen("Render", function()
        if island.Visible and running > 0 and mode == "Compact" then
            local now = os.clock()
            for index, bar in ipairs(bars) do
                local wave = 0.5 + 0.5 * math.sin(now * (6 + index * 1.4) + index * 1.9)
                bar.Size = UDim2.fromOffset(3, math.floor(4 + wave * 11 + 0.5))
            end
        end
    end)

    -- Split, like iOS with two Live Activities: when toggles are running and
    -- a status is pinned, the pill keeps the status (logo leading, value
    -- trailing) and the running meter buds off into its own little circle
    -- beside it. One activity alone stays in the single pill.
    local pinValue = label({
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -14, 0.5, 0),
        Size = UDim2.new(1, -52, 0, 18),
        TextSize = 13,
        FontFace = Fonts.Bold,
        TextXAlignment = Enum.TextXAlignment.Right,
        RichText = true,
        TextTransparency = 1,
        Parent = compact,
    })
    local bubble = create("TextButton", {
        Name = "IslandBubble",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(0, 0),
        BackgroundColor3 = Color3.fromRGB(26, 26, 30),
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Visible = false,
        ZIndex = 30,
        Parent = gui,
    })
    corner(bubble, UDim.new(1, 0))
    local split = create("NumberValue", { Value = 0 })
    local splitOn = false
    local pinnedLead = nil
    local function setSplit(on)
        if on == splitOn then
            return
        end
        splitOn = on
        barsHolder.Parent = on and bubble or meter
        barsHolder.AnchorPoint = on and Vector2.new(0.5, 0.5) or Vector2.new(0, 0)
        barsHolder.Position = on and UDim2.fromScale(0.5, 0.5) or UDim2.new()
        meter.Visible = not on
        tween(pinValue, { TextTransparency = on and 0 or 1 }, 0.2, Enum.EasingStyle.Quad)
        -- Buds off with a spring, and is drawn back in quicker.
        tween(split, { Value = on and 1 or 0 }, on and 0.55 or 0.3, on and Enum.EasingStyle.Back or Enum.EasingStyle.Quint)
        if on then
            islandScale.Scale = 0.96
            tween(islandScale, { Scale = 1 }, 0.45, Enum.EasingStyle.Back)
        end
    end
    self:_listen("Render", function()
        local t = split.Value * merge.Value
        local shown = island.Visible and t > 0.02 and island.GroupTransparency < 0.5
        bubble.Visible = shown
        if not shown then
            return
        end
        local origin = gui.AbsolutePosition
        local pos, size = island.AbsolutePosition - origin, island.AbsoluteSize
        local d = math.min(size.Y, Mini.Height)
        local gap = 6
        -- Buds off the side with room to spare: the right, or the left near
        -- the right edge of the screen.
        local right = pos.X + size.X + gap + d <= gui.AbsoluteSize.X
        local edge = right and pos.X + size.X or pos.X
        local dir = right and 1 or -1
        local inner = edge - dir * d * 0.6
        local outer = edge + dir * (gap + d / 2)
        local x = inner + (outer - inner) * t
        local scale = math.clamp(0.35 + 0.65 * t, 0, 1.2)
        -- Liquid: mid-flight the drop stretches along its path and thins,
        -- then rounds back into a circle as it settles.
        local stretch = math.sin(math.clamp(t, 0, 1) * math.pi)
        bubble.Position = UDim2.fromOffset(x, pos.Y + d / 2)
        bubble.Size = UDim2.fromOffset(d * scale * (1 + 0.4 * stretch), d * scale * (1 - 0.18 * stretch))
        bubble.BackgroundTransparency = island.GroupTransparency
    end)
    bubble.MouseButton1Click:Connect(function()
        if self.Minimized then
            self:Restore()
        end
    end)

    local cardRows = {}
    function self:_refreshMini()
        local count = 0
        for _, element in pairs(Library.Flags) do
            if element._type == "Toggle" and element.Value == true then
                count += 1
            end
        end
        if count ~= running then
            local rising = count > running
            running = count
            countLabel.Text = tostring(count)
            for _, bar in ipairs(bars) do
                tween(bar, { BackgroundColor3 = count > 0 and Theme.Accent or Theme.Muted }, 0.25)
                if count == 0 then
                    tween(bar, { Size = UDim2.fromOffset(3, 3) }, 0.25)
                end
            end
            -- A small bump, like a live activity updating.
            if rising and mode == "Compact" and island.Visible then
                islandScale.Scale = 1.06
                tween(islandScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
            end
        end
        bigCount.Text = tostring(count)
        local names = {}
        for _, element in pairs(Library.Flags) do
            if element._type == "Toggle" and element.Value == true and element._searchName ~= "" then
                table.insert(names, element._searchName)
            end
        end
        table.sort(names)
        local shownNames = {}
        for index = 1, math.min(#names, 3) do
            shownNames[index] = Library._rich(names[index])
        end
        local extra = #names - #shownNames
        runningNames.Text = '<font color="#8A8A93">Running </font>' .. table.concat(shownNames, '<font color="#8A8A93"> · </font>')
            .. (extra > 0 and string.format('<font color="#8A8A93">  +%d</font>', extra) or "")
        runningNames.Visible = #names > 0
        pinnedLead = nil
        for _, handle in ipairs(self._pinned) do
            if not handle._isShown or handle:_isShown() then
                pinnedLead = handle
                break
            end
        end
        if pinnedLead then
            local text = tostring(pinnedLead:Text() or "")
            -- A status with nothing to show yet doesn't take the pill.
            if text:gsub("<[^>]*>", ""):match("%S") then
                pinValue.Text = text
                local color = pinnedLead._shownColor and pinnedLead._shownColor() or Theme.Text
                -- Too dark to read on the black pill: fall back to text colour.
                local _, _, value = color:ToHSV()
                pinValue.TextColor3 = value < 0.35 and Theme.Text or color
            else
                pinnedLead = nil
            end
        end
        setSplit(running > 0 and pinnedLead ~= nil)
        -- The pill's own meter: the clock when idle or when the bars budded
        -- off without a status to keep, the bars and count otherwise.
        local barsHere = running > 0 and not splitOn
        idleDot.Visible = not barsHere
        idleLabel.Visible = not barsHere
        countLabel.Visible = barsHere
        barsHolder.Visible = running > 0
        meter.Visible = not splitOn
        miniTitle.Visible = not splitOn
        local key = typeof(self.Keybind) == "EnumItem" and keyName(self.Keybind)
        hint.Text = TOUCH and "Tap to open" or (key and ("Click or press " .. key .. " to open") or "Click to open")

        local list = {}
        for _, handle in ipairs(self._pinned) do
            if (not handle._isShown or handle:_isShown()) and #list < Mini.Pinned then
                table.insert(list, handle)
            end
        end
        rowsHolder.Visible = false
        for index = 1, math.max(#list, #cardRows) do
            local handle = list[index]
            local row = cardRows[index]
            if handle then
                if not row then
                    local frame = create("Frame", {
                        Size = UDim2.new(1, 0, 0, 18),
                        BackgroundTransparency = 1,
                        LayoutOrder = index,
                        Parent = rowsHolder,
                    })
                    row = {
                        Frame = frame,
                        Key = label({
                            Size = UDim2.new(0.5, -4, 1, 0),
                            TextSize = 12,
                            FontFace = Fonts.Regular,
                            TextColor3 = Theme.Muted,
                            RichText = true,
                            Parent = frame,
                        }),
                        Value = label({
                            AnchorPoint = Vector2.new(1, 0),
                            Position = UDim2.fromScale(1, 0),
                            Size = UDim2.new(0.5, -4, 1, 0),
                            TextSize = 12,
                            TextXAlignment = Enum.TextXAlignment.Right,
                            RichText = true,
                            Parent = frame,
                        }),
                    }
                    cardRows[index] = row
                end
                row.Frame.Visible = true
                row.Key.Text = Library._rich(handle.Name)
                row.Value.Text = handle:Text()
                -- Carries the status's own colour: its Color, or its tone
                -- for the tinted styles (badge, dot, bar).
                local color = handle._shownColor and handle._shownColor() or Theme.Text
                if row.Value.TextColor3 ~= color then
                    tween(row.Value, { TextColor3 = color }, 0.2)
                end
            elseif row then
                row.Frame.Visible = false
            end
        end
        -- Rows coming and going change the expanded height.
        if mode == "Expanded" and (hovered or self.IslandStyle == "Always Show") then
            task.defer(function()
                if mode == "Expanded" and (hovered or self.IslandStyle == "Always Show") and self.Minimized then
                    local size = shapeFor("Expanded")
                    if math.abs(size.Y - island.Size.Y.Offset) > 1 then
                        setMode("Expanded")
                    end
                end
            end)
        end
    end

    self.MiniBar = island
    self.Island = island
    return island
end

function Window:Minimize()
    if self.Minimized or not self._introDone or not self.Open or self._destroyed then
        return
    end
    self.Minimized = true
    self._minimizeGeneration = (self._minimizeGeneration or 0) + 1
    local generation = self._minimizeGeneration
    self:_closePopups()
    self:_refreshToggleButton()
    self:_refreshBackdrop()
    local bar = self:_buildMiniBar()
    self:_refreshMini()
    local gui = self.Gui

    -- Starts from whatever is on screen: the window, or a ghost still
    -- mid-flight if a restore was interrupted.
    local fromPosition = self.Root.AbsolutePosition - gui.AbsolutePosition
    local fromSize = self.Root.AbsoluteSize
    local fromAlpha = 1
    if self._ghost then
        fromPosition = self._ghost.AbsolutePosition - gui.AbsolutePosition
        fromSize = self._ghost.AbsoluteSize
        fromAlpha = self._ghost.BackgroundTransparency
    end

    -- 1. The ghost fades in over the window while it eases back a touch.
    local ghost, ghostStroke, ghostCorner = makeGhost(self, fromPosition, fromSize, Library._radius(10))
    ghost.BackgroundTransparency = fromAlpha
    ghostStroke.Transparency = fromAlpha
    tween(ghost, { BackgroundTransparency = 0 }, 0.11, Enum.EasingStyle.Quad)
    tween(ghostStroke, { Transparency = 0 }, 0.11, Enum.EasingStyle.Quad)
    tween(self.Scale, { Scale = (self._fitScale or 1) * 0.985 }, 0.11, Enum.EasingStyle.Quad)
    tween(self.Shadow, { ImageTransparency = 1 }, 0.2)
    bar.Visible = true
    bar.GroupTransparency = 1

    task.delay(0.11, function()
        if self._minimizeGeneration ~= generation or self._destroyed then
            return
        end
        -- 2. Covered by the ghost, the window is hidden and the ghost folds
        -- down into the island.
        self.Root.Visible = false
        self.Scale.Scale = self._fitScale or 1
        local target, size = self:_miniLand(fromPosition + fromSize / 2)
        morphGhost(ghost, ghostCorner, target, size, math.floor(size.Y / 2), 0.36)
        task.delay(0.3, function()
            if self._minimizeGeneration ~= generation or self._destroyed then
                return
            end
            -- 3. The island fades in on top as the ghost lands.
            self._miniScale.Scale = 0.9
            tween(self._miniScale, { Scale = 1 }, 0.3, Enum.EasingStyle.Quint)
            tween(bar, { GroupTransparency = 0 }, 0.18, Enum.EasingStyle.Quad)
            dissolve(self, ghost, ghostStroke, 0.2)
            -- Always Show: once landed as the pill, swell open into the card.
            if self.IslandStyle == "Always Show" then
                task.delay(0.22, function()
                    if self._minimizeGeneration == generation and self._islandSettle then
                        self._islandSettle()
                    end
                end)
            end
        end)
    end)

    task.spawn(function()
        while self.Minimized and self._minimizeGeneration == generation and not self._destroyed do
            self:_refreshMini()
            task.wait(0.5)
        end
    end)
end

function Window:Restore()
    if not self.Minimized or self._destroyed then
        return
    end
    self.Minimized = false
    self._minimizeGeneration = (self._minimizeGeneration or 0) + 1
    local generation = self._minimizeGeneration
    self:_refreshToggleButton()
    self:_refreshBackdrop(true)
    local gui = self.Gui
    local bar = self.MiniBar
    local fit = self._fitScale or 1
    local size = Vector2.new(self.Root.Size.X.Offset, self.Root.Size.Y.Offset) * fit
    local centre = self.Root.AbsolutePosition + self.Root.AbsoluteSize / 2 - gui.AbsolutePosition
    local target = centre - size / 2

    -- Picks up from whatever is on screen: a ghost still mid-flight if
    -- minimize was interrupted, otherwise the island.
    local fromPosition, fromSize = target, size
    local fromAlpha = 1
    if self._ghost then
        fromPosition = self._ghost.AbsolutePosition - gui.AbsolutePosition
        fromSize = self._ghost.AbsoluteSize
        fromAlpha = self._ghost.BackgroundTransparency
    elseif bar and bar.Visible then
        fromPosition = self._miniOrb.AbsolutePosition - gui.AbsolutePosition
        fromSize = self._miniOrb.AbsoluteSize
    end
    if bar and bar.Visible then
        if self._miniUnhover then
            self._miniUnhover()
        end
        tween(bar, { GroupTransparency = 1 }, 0.12, Enum.EasingStyle.Quad)
        task.delay(0.12, function()
            if self._minimizeGeneration == generation then
                bar.Visible = false
            end
        end)
    end

    local ghost, ghostStroke, ghostCorner = makeGhost(self, fromPosition, fromSize, math.floor(math.min(fromSize.X, fromSize.Y) / 2))
    ghost.BackgroundTransparency = fromAlpha
    ghostStroke.Transparency = fromAlpha
    tween(ghost, { BackgroundTransparency = 0 }, 0.1, Enum.EasingStyle.Quad)
    tween(ghostStroke, { Transparency = 0 }, 0.1, Enum.EasingStyle.Quad)
    morphGhost(ghost, ghostCorner, target, size, Library._radius(10), 0.4)
    tween(self.Shadow, { ImageTransparency = self._shadowRest }, 0.45)

    -- Shown under the ghost a little early so its first frames are drawn
    -- while still covered, then the ghost clears to reveal it.
    task.delay(0.3, function()
        if self._minimizeGeneration ~= generation or self._destroyed then
            return
        end
        self.Scale.Scale = fit
        self.BodyStroke.Transparency = 0
        self.Root.Visible = true
    end)
    task.delay(0.4, function()
        if self._ghost == ghost and self._minimizeGeneration == generation then
            dissolve(self, ghost, ghostStroke, 0.22)
        end
    end)
end

-- The minimized island can be dragged anywhere; its spot is remembered in
-- the config folder. These lock it in place or send it back to the top.
function Window:SetIslandDraggable(enabled)
    self._islandLocked = enabled == false
end

function Window:ResetIslandPosition()
    self._islandAnchor = nil
    if self._islandReset then
        self._islandReset()
    end
    self:_writeConfigSettings({ IslandPosition = false })
end

function Window:SetMinimized(minimized)
    if minimized then
        self:Minimize()
    else
        self:Restore()
    end
end

function Window:Toggle(open)
    if not self._introDone then
        return
    end
    if self.Minimized then
        if open ~= false then
            self:Restore()
        end
        return
    end
    if open == nil then
        open = not self.Open
    end
    if open == self.Open then
        return
    end
    self.Open = open
    self:_refreshToggleButton()
    self:_refreshBackdrop(open)
    -- Like minimize, a plain ghost panel carries the scale and fade. The body
    -- is never reparented into the fader or rescaled, which relaid out the
    -- whole window and stuttered on the keypress frame.
    self._minimizeGeneration = (self._minimizeGeneration or 0) + 1
    local generation = self._minimizeGeneration
    local gui = self.Gui
    local fit = self._fitScale or 1
    local size = Vector2.new(self.Root.Size.X.Offset, self.Root.Size.Y.Offset) * fit
    local centre = self.Root.AbsolutePosition + self.Root.AbsoluteSize / 2 - gui.AbsolutePosition
    local shrunk = size * 0.94
    local fromPosition, fromSize, fromAlpha
    if self._ghost then
        fromPosition = self._ghost.AbsolutePosition - gui.AbsolutePosition
        fromSize = self._ghost.AbsoluteSize
        fromAlpha = self._ghost.BackgroundTransparency
    end
    if open then
        local ghost, ghostStroke, ghostCorner = makeGhost(self, fromPosition or centre - shrunk / 2, fromSize or shrunk, Library._radius(10))
        ghost.BackgroundTransparency = fromAlpha or 1
        ghostStroke.Transparency = fromAlpha or 1
        tween(ghost, { BackgroundTransparency = 0 }, 0.12, Enum.EasingStyle.Quad)
        tween(ghostStroke, { Transparency = 0 }, 0.12, Enum.EasingStyle.Quad)
        morphGhost(ghost, ghostCorner, centre - size / 2, size, Library._radius(10), 0.3)
        tween(self.Shadow, { ImageTransparency = self._shadowRest }, 0.3)
        -- Shown under the ghost once it covers the spot, then revealed.
        task.delay(0.2, function()
            if self._minimizeGeneration ~= generation or self._destroyed then
                return
            end
            self.Scale.Scale = fit
            self.BodyStroke.Transparency = 0
            self.Root.Visible = true
        end)
        task.delay(0.3, function()
            if self._ghost == ghost and self._minimizeGeneration == generation then
                dissolve(self, ghost, ghostStroke, 0.18)
            end
        end)
    else
        self:_closePopups()
        local position = fromPosition or self.Root.AbsolutePosition - gui.AbsolutePosition
        local current = fromSize or self.Root.AbsoluteSize
        local ghost, ghostStroke, ghostCorner = makeGhost(self, position, current, Library._radius(10))
        ghost.BackgroundTransparency = fromAlpha or 1
        ghostStroke.Transparency = fromAlpha or 1
        tween(ghost, { BackgroundTransparency = 0 }, 0.08, Enum.EasingStyle.Quad)
        tween(ghostStroke, { Transparency = 0 }, 0.08, Enum.EasingStyle.Quad)
        tween(self.Shadow, { ImageTransparency = 1 }, 0.16)
        task.delay(0.08, function()
            if self._minimizeGeneration ~= generation or self._destroyed then
                return
            end
            self.Root.Visible = false
            morphGhost(ghost, ghostCorner, centre - shrunk / 2, shrunk, Library._radius(10), 0.2)
            dissolve(self, ghost, ghostStroke, 0.16)
        end)
    end
end

function Window:SetKeepOnScreen(enabled)
    self.KeepOnScreen = enabled ~= false
    if self.KeepOnScreen then
        self:_clampToScreen()
    end
end

function Window:SetKeybind(keyCode)
    self.Keybind = keyCode
    if self._keyChipLabel then
        self._keyChipLabel.Text = keyName(keyCode)
    end
end

function Window:Notify(opts)
    opts = normalize(opts, { Text = "Content", Message = "Content", Image = "Icon" })
    if self.Minimized and self._islandActivity then
        self._islandActivity(opts)
    end
    local duration = opts.Duration or 4
    local titleColor = NOTIFY_COLORS[opts.Type] or Theme.Text

    self._notifyOrder = self._notifyOrder + 1
    local outer = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1,
        LayoutOrder = self._notifyOrder,
        Parent = self.NotifyHolder,
    })
    local slide = create("Frame", {
        Position = UDim2.fromOffset(320, 0),
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = outer,
    })
    local shadow = create("ImageLabel", {
        Position = UDim2.fromOffset(-20, -20),
        Size = UDim2.new(1, 40, 1, 40),
        BackgroundTransparency = 1,
        Image = Assets.Shadow,
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450),
        ZIndex = 0,
        Parent = slide,
    })
    local toast = create("CanvasGroup", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        Parent = slide,
    })
    corner(toast, UDim.new(0, 10))
    local toastStroke = stroke(toast, Theme.Stroke)
    edgeHighlight(toast)
    glow(toast, UDim2.fromOffset(260, 120), UDim2.new(1, -10, 0, -10), 0.86, 90)

    local inner = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = toast,
    })
    padding(inner, 16, 16, 14, 24)

    local titleOffset = 0
    if opts.Icon then
        glowIcon(inner, opts.Icon, titleColor == Theme.Text and Theme.Accent or titleColor, UDim2.new(0, 0, 0, 8))
        titleOffset = 24
    end
    label({
        Position = UDim2.fromOffset(titleOffset, 0),
        Size = UDim2.new(1, -28 - titleOffset, 0, 16),
        Text = opts.Title or "Notification",
        TextSize = 14,
        TextColor3 = titleColor,
        Parent = inner,
    })
    local closeButton = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 6, 0, -5),
        Size = UDim2.fromOffset(24, 24),
        BackgroundTransparency = 1,
        Text = "×",
        TextColor3 = Theme.Muted,
        TextSize = 22,
        FontFace = Fonts.Bold,
        AutoButtonColor = false,
        Parent = inner,
    })
    closeButton.MouseEnter:Connect(function()
        tween(closeButton, { TextColor3 = Theme.Text }, 0.15)
    end)
    closeButton.MouseLeave:Connect(function()
        tween(closeButton, { TextColor3 = Theme.Muted }, 0.2)
    end)
    if opts.Content then
        label({
            Position = UDim2.fromOffset(titleOffset, 21),
            Size = UDim2.new(1, -titleOffset, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Text = opts.Content,
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextWrapped = true,
            TextTruncate = Enum.TextTruncate.None,
            TextYAlignment = Enum.TextYAlignment.Top,
            Parent = inner,
        })
    end

    local track = create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 16, 1, -8),
        Size = UDim2.new(1, -32, 0, 3),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = toast,
    })
    corner(track, UDim.new(1, 0))
    local progress = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Parent = track,
    })
    corner(progress, UDim.new(1, 0))

    task.defer(function()
        if outer.Parent then
            tween(outer, { Size = UDim2.new(1, 0, 0, toast.AbsoluteSize.Y) }, 0.3, Enum.EasingStyle.Quint)
        end
    end)
    tween(slide, { Position = UDim2.fromOffset(0, 0) }, 0.5, Enum.EasingStyle.Back)
    tween(toast, { GroupTransparency = 0 }, 0.3)
    tween(shadow, { ImageTransparency = 0.6 }, 0.4)
    tween(progress, { Size = UDim2.fromScale(0, 1) }, duration, Enum.EasingStyle.Linear)

    local dismissed = false
    local function dismiss()
        if dismissed then
            return
        end
        dismissed = true
        for index, entry in ipairs(self._toasts) do
            if entry == dismiss then
                table.remove(self._toasts, index)
                break
            end
        end
        tween(slide, { Position = UDim2.fromOffset(320, 0) }, 0.3, Enum.EasingStyle.Quint)
        tween(toast, { GroupTransparency = 1 }, 0.2)
        tween(toastStroke, { Transparency = 1 }, 0.15)
        tween(shadow, { ImageTransparency = 1 }, 0.2)
        task.delay(0.22, function()
            outer.ClipsDescendants = true
            tween(outer, { Size = UDim2.new(1, 0, 0, -4) }, 0.22, Enum.EasingStyle.Quint)
            task.delay(0.24, function()
                outer:Destroy()
            end)
        end)
    end

    task.delay(duration, dismiss)
    closeButton.MouseButton1Click:Connect(dismiss)

    table.insert(self._toasts, dismiss)
    while #self._toasts > self.MaxNotifications do
        local oldest = table.remove(self._toasts, 1)
        oldest()
    end

    return { Dismiss = dismiss }
end

function Window:Destroy()
    if self._destroyed then
        return
    end
    if self._autosave and (self.LoadedConfig or self.ConfigName) then
        pcall(self.SaveConfig, self, self.LoadedConfig or self.ConfigName)
    end
    self._destroyed = true
    for index, entry in ipairs(Library.Windows) do
        if entry == self then
            table.remove(Library.Windows, index)
            break
        end
    end
    for _, connection in ipairs(self._connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    self._connections = {}
    self._inputListeners = { Began = {}, Changed = {}, Ended = {}, Render = {} }
    self._frameSteps = {}
    if self._pendingFlags then
        self._pendingFlags = {}
    end
    -- Switch this window's toggles off so their feature loops stop with it,
    -- instead of running on beside a re-executed copy.
    for _, element in pairs(Library.Flags) do
        if element._window == self and element._type == "Toggle" and element.Value == true then
            task.spawn(pcall, element.Set, element, false)
        end
    end
    local registry = Library._registry()
    if registry and registry[self._registryKey] == self then
        registry[self._registryKey] = nil
    end

    local gui = self.Gui
    local removed = false
    local function remove()
        if removed then
            return
        end
        removed = true
        if not pcall(gui.Destroy, gui) then
            pcall(function()
                gui.Enabled = false
            end)
        end
    end
    -- The fade out is decoration only. Input is already cut at this point, so
    -- if any of it fails the gui is removed straight away instead of being
    -- left frozen on screen.
    local ok, err = pcall(function()
        if self._dialog then
            self._dialog.Close()
        end
        self:_closePopups()
        local fit = self._fitScale or 1
        tween(self.Scale, { Scale = fit * 0.92 }, 0.22, Enum.EasingStyle.Quint)
        self:_fade(1, 0.2)
        tween(self.BodyStroke, { Transparency = 1 }, 0.12)
        tween(self.Shadow, { ImageTransparency = 1 }, 0.2)
        if self.MiniBar and self.MiniBar.Visible then
            tween(self.MiniBar, { GroupTransparency = 1 }, 0.18)
        end
        if self._backdrop then
            tween(self._backdropTintFrame, { BackgroundTransparency = 1 }, 0.2)
        end
        for _, button in ipairs({ self.ToggleButton, self.OpenButton }) do
            if typeof(button) == "Instance" and button:IsA("GuiObject") then
                tween(button, { Size = UDim2.fromOffset(0, 0) }, 0.2, Enum.EasingStyle.Quint)
            end
        end
    end)
    if not ok then
        warn("[RealIggyLib] unload animation failed, removing the window directly: " .. tostring(err))
        remove()
        return
    end
    task.delay(0.24, remove)
end

Window.Unload = Window.Destroy

-- Unloads every window the library created.
function Library:Destroy()
    for index = #Library.Windows, 1, -1 do
        local window = Library.Windows[index]
        if window then
            window:Destroy()
        end
    end
end

Library.Unload = Library.Destroy

-- A script thread that yielded inside an engine call (InvokeServer and the
-- like) resumes at game identity and can no longer touch the GUI in CoreGui.
-- Every public call checks for that: it raises the thread back to the identity
-- the library loaded at, or, when the executor cannot, runs the call on a
-- trusted Heartbeat thread and waits for its result.
local getIdentity = getthreadidentity or getidentity or get_thread_identity or (syn and syn.get_thread_identity)
local setIdentity = setthreadidentity or setidentity or set_thread_identity or (syn and syn.set_thread_identity)
local loadIdentity = nil
if getIdentity then
    local ok, identity = pcall(getIdentity)
    if ok and type(identity) == "number" then
        loadIdentity = identity
    end
end

local function threadLowered()
    local window = Library.Windows[#Library.Windows]
    local probe = window and window.Gui
    if typeof(probe) ~= "Instance" then
        return false
    end
    return not pcall(function()
        return probe.Name
    end)
end

local trustedQueue = {}
RunService.Heartbeat:Connect(function()
    if #trustedQueue == 0 then
        return
    end
    local queue = trustedQueue
    trustedQueue = {}
    for _, job in ipairs(queue) do
        job()
    end
end)

local function runTrusted(fn, ...)
    local args = table.pack(...)
    local result = nil
    table.insert(trustedQueue, function()
        result = table.pack(pcall(fn, table.unpack(args, 1, args.n)))
    end)
    while result == nil do
        task.wait()
    end
    if not result[1] then
        error(result[2], 0)
    end
    return table.unpack(result, 2, result.n)
end

local guardedObjects = setmetatable({}, { __mode = "k" })
local guardObject

local function guarded(fn)
    return function(...)
        if threadLowered() then
            if setIdentity then
                pcall(setIdentity, loadIdentity or 8)
            end
            if threadLowered() then
                return guardObject(runTrusted(fn, ...))
            end
        end
        return guardObject(fn(...))
    end
end

-- Elements carry their methods as closures, so each returned object gets its
-- public functions wrapped too; windows and tabs share the guarded metatables.
function guardObject(...)
    for index = 1, select("#", ...) do
        local object = select(index, ...)
        if type(object) == "table" and not guardedObjects[object] then
            local meta = getmetatable(object)
            if meta ~= Window and meta ~= Tab then
                guardedObjects[object] = true
                for key, value in pairs(object) do
                    if type(key) == "string" and type(value) == "function" and key:sub(1, 1) ~= "_" then
                        object[key] = guarded(value)
                    elseif type(key) == "number" and type(value) == "table" then
                        guardObject(value)
                    end
                end
            end
        end
    end
    return ...
end

for _, class in ipairs({ Library, Window, Tab }) do
    for key, value in pairs(class) do
        if type(key) == "string" and type(value) == "function" and key:sub(1, 1) ~= "_" then
            class[key] = guarded(value)
        end
    end
end

return Library
end)()
