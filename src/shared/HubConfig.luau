-- Studio Hub settings. Edit this file to list your own games.
--
-- placeId: the number in your game's Roblox link, for example
--   https://www.roblox.com/games/1234567890/My-Game  ->  placeId = 1234567890
-- Leave placeId = 0 for a game that isn't published yet. Its Play button
-- shows "Coming soon" instead of teleporting.
--
-- status is just a label: "Idea", "Building", "Playtesting", "Launched" or "Paused".

return {
	-- Key that opens and closes the hub on PC.
	ToggleKey = Enum.KeyCode.H,

	-- How many games can be popped out into floating windows at once.
	MaxWindows = 4,

	-- Chat channels each game gets.
	Channels = { "lobby", "playtest", "launch" },

	-- How many messages each channel remembers while the server is running.
	HistorySize = 50,

	-- Longest message a player can send.
	MaxMessageLength = 200,

	-- Your games. The first four start in the 4-game grid.
	-- These are examples: change the names and put in your real place IDs.
	Games = {
		{
			key = "lava",
			name = "Climb the Lava Tower",
			placeId = 0,
			status = "Building",
			color = Color3.fromRGB(255, 107, 90),
			blurb = "Race up the tower before the lava catches you.",
		},
		{
			key = "egg",
			name = "Hatch the Mega Egg",
			placeId = 0,
			status = "Playtesting",
			color = Color3.fromRGB(176, 124, 255),
			blurb = "Collect coins, hatch eggs, and build a pet team.",
		},
		{
			key = "cart",
			name = "Cart Ride Rush",
			placeId = 0,
			status = "Launched",
			color = Color3.fromRGB(60, 207, 142),
			blurb = "Ride carts through the canyon and don't fall off.",
		},
		{
			key = "turkey",
			name = "Turkey Toss Arena",
			placeId = 0,
			status = "Idea",
			color = Color3.fromRGB(245, 184, 74),
			blurb = "Throw turkeys at targets. Farther throws earn more coins.",
		},
	},
}
