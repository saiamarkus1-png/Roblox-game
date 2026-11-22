-- Studio Hub server: chat channels for each game, text filtering, and teleports.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local TextService = game:GetService("TextService")
local MarketplaceService = game:GetService("MarketplaceService")

local Hub = ReplicatedStorage:WaitForChild("StudioHub")
local Config = require(Hub:WaitForChild("HubConfig"))

-- Remotes ---------------------------------------------------------------
local Remotes = Hub:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = Hub
end

local function remote(className: string, name: string)
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = Remotes
	end
	return r
end

local RTeleport = remote("RemoteEvent", "Teleport")
local RPost = remote("RemoteEvent", "PostMessage")
local RNew = remote("RemoteEvent", "NewMessage")
local RNotice = remote("RemoteEvent", "Notice")
local RGetState = remote("RemoteFunction", "GetState")

-- Lookups ---------------------------------------------------------------
local gamesByKey = {}
for _, g in ipairs(Config.Games) do
	gamesByKey[g.key] = g
end

local channelOk = {}
for _, c in ipairs(Config.Channels) do
	channelOk[c] = true
end

-- history[gameKey][channel] = { {name, userId, text, t}, ... }
local history = {}
for _, g in ipairs(Config.Games) do
	history[g.key] = {}
	for _, c in ipairs(Config.Channels) do
		history[g.key][c] = {}
	end
end

local function systemPost(gameKey: string, channel: string, text: string)
	local msg = { name = "Studio Hub", userId = 0, text = text, t = os.time(), system = true }
	table.insert(history[gameKey][channel], msg)
	RNew:FireAllClients(gameKey, channel, msg)
end

-- Fill in the real Roblox name for published games (runs in the background).
local liveInfo = {}
task.spawn(function()
	for _, g in ipairs(Config.Games) do
		if typeof(g.placeId) == "number" and g.placeId > 0 then
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(g.placeId)
			end)
			if ok and info then
				liveInfo[g.key] = { robloxName = info.Name, description = info.Description }
			end
		end
	end
end)

RGetState.OnServerInvoke = function(_player)
	return {
		history = history,
		info = liveInfo,
		currentPlaceId = game.PlaceId,
	}
end

-- Chat ------------------------------------------------------------------
local lastPost = {}

RPost.OnServerEvent:Connect(function(player, gameKey, channel, text)
	if typeof(gameKey) ~= "string" or typeof(channel) ~= "string" or typeof(text) ~= "string" then
		return
	end
	if not gamesByKey[gameKey] or not channelOk[channel] then
		return
	end

	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	if #text == 0 then
		return
	end
	if #text > Config.MaxMessageLength then
		text = string.sub(text, 1, Config.MaxMessageLength)
	end

	-- one message per second per player
	local now = os.clock()
	if lastPost[player] and now - lastPost[player] < 1 then
		RNotice:FireClient(player, "Slow down a little.")
		return
	end
	lastPost[player] = now

	-- Roblox requires all player text shown to others to be filtered.
	local ok, filtered = pcall(function()
		local result = TextService:FilterStringAsync(text, player.UserId)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		RNotice:FireClient(player, "Your message couldn't be sent. Try again.")
		return
	end

	local msg = { name = player.DisplayName, userId = player.UserId, text = filtered, t = os.time() }
	local list = history[gameKey][channel]
	table.insert(list, msg)
	while #list > Config.HistorySize do
		table.remove(list, 1)
	end
	RNew:FireAllClients(gameKey, channel, msg)
end)

Players.PlayerRemoving:Connect(function(player)
	lastPost[player] = nil
end)

-- Teleports -------------------------------------------------------------
RTeleport.OnServerEvent:Connect(function(player, gameKey)
	local g = typeof(gameKey) == "string" and gamesByKey[gameKey]
	if not g then
		return
	end
	if typeof(g.placeId) ~= "number" or g.placeId <= 0 then
		RNotice:FireClient(player, g.name .. " isn't published yet.")
		return
	end
	if g.placeId == game.PlaceId then
		RNotice:FireClient(player, "You're already in " .. g.name .. ".")
		return
	end
	if RunService:IsStudio() then
		RNotice:FireClient(player, "Teleports only work in a live game, not in Studio.")
		return
	end

	RNotice:FireClient(player, "Teleporting to " .. g.name .. "...")
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(g.placeId, { player })
	end)
	if not ok then
		warn("[StudioHub] Teleport failed:", err)
		RNotice:FireClient(player, "Teleport failed. Check that the game is public.")
	end
end)

TeleportService.TeleportInitFailed:Connect(function(player, _result, message)
	RNotice:FireClient(player, "Teleport failed: " .. tostring(message))
end)

-- Starter messages so the channels aren't empty the first time.
for _, g in ipairs(Config.Games) do
	systemPost(g.key, "lobby", "Welcome to #lobby for " .. g.name .. ". Post updates and ideas here.")
end
