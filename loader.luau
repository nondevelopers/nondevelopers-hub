--[[
    nondevelopers loader
    One script to execute. Picks the right script for the current game,
    falls back to the universal hub when the game is not supported.
]]--

if not game:IsLoaded() then game.Loaded:Wait() end

-- config -------------------------------------------------------------
local BASE = "https://raw.githubusercontent.com/nondevelopers/nondev-scripts/main/"
local FALLBACK = "hub.luau" -- your current nondevelopers_hub.luau

-- key = game.GameId (universe, covers every place of the game)
--       or game.PlaceId (one specific place; checked first)
local SUPPORTED = {
    -- [1234567890] = "games/example_game.luau",
    -- [9876543210] = "games/another_game.luau",
}
-----------------------------------------------------------------------

local env = getgenv()
if env.NonDevLoaded then return end -- block double execution
env.NonDevLoaded = true

local function run(path)
    local ok, src = pcall(game.HttpGet, game, BASE .. path)
    if not ok or type(src) ~= "string" or src:sub(1, 3) == "404" then
        return false, "fetch failed: " .. path
    end
    local fn, compileErr = loadstring(src)
    if not fn then return false, compileErr end
    return pcall(fn)
end

local target = SUPPORTED[game.PlaceId] or SUPPORTED[game.GameId]
local ok, err = false, nil

if target then
    ok, err = run(target)
    if not ok then
        warn("[nondev] game script failed, using hub:", err)
    end
end

if not ok then
    ok, err = run(FALLBACK)
    if not ok then
        env.NonDevLoaded = false -- allow a retry
        warn("[nondev] hub failed:", err)
    end
end
