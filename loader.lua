repeat task.wait() until game:IsLoaded()

local StarterGui = game:GetService("StarterGui")
local MarketplaceService = game:GetService("MarketplaceService")

local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title or "Iggy Hub",
            Text = text or "",
            Duration = duration or 5
        })
    end)
end

-- Supported Games Table
-- Maps UniverseId (GameId) and PlaceId to corresponding scripts
local REPO_BASE = "https://raw.githubusercontent.com/IggyTheDogHub/IggyHub/main/"

local GAMES = {
    -- Grow a Chicken Fighter
    ["GrowAChickenFighter"] = {
        Name = "Grow a Chicken Fighter",
        UniverseIds = { [10338952197] = true },
        PlaceIds = {
            [94640181989498] = true,
            [94939256104840] = true,
        },
        ScriptPath = "chicken.lua"
    },
    -- Roll Anime to Fight!
    ["RollAnimeToFight"] = {
        Name = "Roll Anime to Fight!",
        UniverseIds = { [10298144467] = true },
        PlaceIds = {
            [107653945083776] = true, -- Main Lobby / World
            [133207600268474] = true, -- Red Knight's Dungeon (Raids)
            [107431701292918] = true, -- Ant Kingdom (Chimera Raids)
            [89230410866378]  = true, -- Clover Dungeon (Clover Portals)
            [133623616308412] = true, -- Infinite Tower
            [109743888989638] = true, -- Trading Hub
            [139348108626702] = true, -- Modules
        },
        ScriptPath = "ratf.lua"
    },
    -- Anime Dice
    ["AnimeDice"] = {
        Name = "Anime Dice",
        UniverseIds = { [10708913337] = true },
        PlaceIds = {
            [113290951185459] = true,
        },
        ScriptPath = "dice.lua",
        FallbackPaths = { "AnimeDice.lua", "animedice.lua" }
    }
}

-- Wait briefly for GameId to populate if 0 (common during fast teleports / autoexecute)
local waitStart = tick()
while (not game.GameId or game.GameId == 0) and (tick() - waitStart < 3) do
    task.wait(0.1)
end

local currentGame = nil
local currentPlaceId = game.PlaceId
local currentUniverseId = game.GameId

-- Identify current game by UniverseId first (handles all subplaces), then PlaceId fallback
for _, gameConfig in pairs(GAMES) do
    if (currentUniverseId and gameConfig.UniverseIds[currentUniverseId]) or (currentPlaceId and gameConfig.PlaceIds and gameConfig.PlaceIds[currentPlaceId]) then
        currentGame = gameConfig
        break
    end
end

if not currentGame then
    local gameName = "Unknown Game"
    pcall(function()
        local productInfo = MarketplaceService:GetProductInfo(currentPlaceId)
        if productInfo and productInfo.Name then
            gameName = productInfo.Name
        end
    end)
    
    warn("[Iggy Hub] Unsupported game detected:")
    warn("  Name: " .. tostring(gameName))
    warn("  PlaceId: " .. tostring(currentPlaceId))
    warn("  UniverseId: " .. tostring(currentUniverseId))
    
    notify("Iggy Hub", "Unsupported game: " .. tostring(gameName) .. "\n(PlaceId: " .. tostring(currentPlaceId) .. ")", 7)
    return
end

-- Cache-busting parameter to ensure players always run the newest commit
local cacheBust = "?v=" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))

notify("Iggy Hub", "Loading " .. currentGame.Name .. "...", 4)

local candidatePaths = { currentGame.ScriptPath }
if currentGame.FallbackPaths then
    for _, fallback in ipairs(currentGame.FallbackPaths) do
        table.insert(candidatePaths, fallback)
    end
end

local fetchSuccess, scriptContent = false, nil
local lastAttemptUrl = ""

for _, path in ipairs(candidatePaths) do
    local scriptUrl = REPO_BASE .. path .. cacheBust
    lastAttemptUrl = scriptUrl
    local ok, res = pcall(function()
        return game:HttpGet(scriptUrl)
    end)
    if ok and res and #res > 0 and not res:find("404: Not Found") then
        fetchSuccess = true
        scriptContent = res
        break
    end
end

if not fetchSuccess or not scriptContent or #scriptContent == 0 then
    warn("[Iggy Hub] Failed to download script from: " .. lastAttemptUrl)
    notify("Iggy Hub Error", "Failed to download script from GitHub. Make sure the file exists.", 6)
    return
end

local loadSuccess, loadError = pcall(function()
    local exec = loadstring(scriptContent)
    if exec then
        exec()
    else
        error("Syntax error or empty script received.")
    end
end)

if not loadSuccess then
    warn("[Iggy Hub] Execution error: " .. tostring(loadError))
    notify("Iggy Hub Error", "Failed to run script: " .. tostring(loadError), 6)
end
