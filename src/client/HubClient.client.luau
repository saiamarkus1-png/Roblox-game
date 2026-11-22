-- Studio Hub client: a Discord-style panel inside your game.
--  * Left rail of game icons, channels per game, live chat
--  * Multi-view grid that shows up to 4 games at once
--  * Pop any game out into a floating window you can drag and resize (up to 4)
--  * Play button teleports to that game
-- Press H (or tap the Hub button) to open it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Hub = ReplicatedStorage:WaitForChild("StudioHub")
local Config = require(Hub:WaitForChild("HubConfig"))
local Remotes = Hub:WaitForChild("Remotes")
local RTeleport = Remotes:WaitForChild("Teleport")
local RPost = Remotes:WaitForChild("PostMessage")
local RNew = Remotes:WaitForChild("NewMessage")
local RNotice = Remotes:WaitForChild("Notice")
local RGetState = Remotes:WaitForChild("GetState")

---------------------------------------------------------------------------
-- Theme
---------------------------------------------------------------------------
local C = {
	bg = Color3.fromRGB(14, 16, 21),
	rail = Color3.fromRGB(19, 21, 28),
	side = Color3.fromRGB(24, 27, 35),
	main = Color3.fromRGB(29, 32, 41),
	raise = Color3.fromRGB(37, 41, 53),
	line = Color3.fromRGB(46, 51, 65),
	fg = Color3.fromRGB(232, 234, 240),
	dim = Color3.fromRGB(154, 161, 178),
	faint = Color3.fromRGB(102, 109, 126),
	accent = Color3.fromRGB(255, 107, 90),
	accentInk = Color3.fromRGB(26, 13, 11),
	ok = Color3.fromRGB(60, 207, 142),
	warn = Color3.fromRGB(245, 184, 74),
	info = Color3.fromRGB(106, 168, 255),
	bad = Color3.fromRGB(255, 92, 122),
}
local STATUS_COLOR = {
	Idea = C.dim,
	Building = C.info,
	Playtesting = C.warn,
	Launched = C.ok,
	Paused = C.bad,
}
local NAME_COLORS = {
	Color3.fromRGB(106, 168, 255),
	Color3.fromRGB(176, 124, 255),
	Color3.fromRGB(255, 122, 198),
	Color3.fromRGB(245, 184, 74),
	Color3.fromRGB(60, 207, 142),
	Color3.fromRGB(46, 196, 196),
}
local F = Enum.Font.Gotham
local FM = Enum.Font.GothamMedium
local FB = Enum.Font.GothamBold

---------------------------------------------------------------------------
-- Small UI helpers
---------------------------------------------------------------------------
local function make(className, props, children)
	local inst = Instance.new(className)
	local parent = nil
	for k, v in pairs(props or {}) do
		if k == "Parent" then
			parent = v
		else
			inst[k] = v
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(r)
	return make("UICorner", { CornerRadius = UDim.new(0, r) })
end
local function round()
	return make("UICorner", { CornerRadius = UDim.new(0.5, 0) })
end
local function stroke(color)
	return make("UIStroke", {
		Color = color or C.line,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end
local function padding(t, r, b, l)
	return make("UIPadding", {
		PaddingTop = UDim.new(0, t),
		PaddingRight = UDim.new(0, r or t),
		PaddingBottom = UDim.new(0, b or t),
		PaddingLeft = UDim.new(0, l or r or t),
	})
end
local function list(dir, gap, hAlign)
	return make("UIListLayout", {
		FillDirection = dir or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap or 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
	})
end

local function text(props)
	local defaults = {
		BackgroundTransparency = 1,
		Font = F,
		TextSize = 14,
		TextColor3 = C.fg,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}
	for k, v in pairs(props) do
		defaults[k] = v
	end
	return make("TextLabel", defaults)
end

-- style: "pri" (accent), "ghost", or default
local function button(label, props, onClick, style)
	local bg, fg = C.raise, C.fg
	if style == "pri" then
		bg, fg = C.accent, C.accentInk
	elseif style == "ghost" then
		bg, fg = C.main, C.dim
	end
	local p = {
		Text = label,
		Font = FM,
		TextSize = 13,
		TextColor3 = fg,
		BackgroundColor3 = bg,
		AutoButtonColor = true,
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
	}
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	local b = make("TextButton", p, { corner(7), padding(0, 10, 0, 10) })
	if style ~= "pri" and style ~= "ghost" then
		stroke().Parent = b
	end
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

local function clear(frame)
	for _, child in ipairs(frame:GetChildren()) do
		if not child:IsA("UIBase") then
			child:Destroy()
		end
	end
end
local function clearAll(frame)
	for _, child in ipairs(frame:GetChildren()) do
		child:Destroy()
	end
end

local function initials(name)
	local out = ""
	for word in string.gmatch(name, "%w+") do
		out = out .. string.upper(string.sub(word, 1, 1))
		if #out >= 2 then
			break
		end
	end
	return out ~= "" and out or "?"
end

local function richEscape(s)
	s = string.gsub(s, "&", "&amp;")
	s = string.gsub(s, "<", "&lt;")
	s = string.gsub(s, ">", "&gt;")
	s = string.gsub(s, '"', "&quot;")
	s = string.gsub(s, "'", "&apos;")
	return s
end

local function avatarBadge(g, size)
	return make("TextLabel", {
		Text = initials(g.name),
		Font = FB,
		TextSize = math.floor(size * 0.42),
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = g.color,
		Size = UDim2.fromOffset(size, size),
	}, { corner(math.floor(size * 0.3)) })
end

local function statusPill(status)
	local color = STATUS_COLOR[status] or C.dim
	return make("TextLabel", {
		Text = "● " .. status,
		Font = FB,
		TextSize = 11,
		TextColor3 = color,
		BackgroundColor3 = C.raise,
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
	}, { round(), padding(0, 8, 0, 8) })
end

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
local Games = Config.Games
local gamesByKey = {}
for i, g in ipairs(Games) do
	g.order = i
	gamesByKey[g.key] = g
end

local history = {}
local liveInfo = {}
local currentPlaceId = game.PlaceId

local ok, result = pcall(function()
	return RGetState:InvokeServer()
end)
if ok and result then
	history = result.history or {}
	liveInfo = result.info or {}
	currentPlaceId = result.currentPlaceId or currentPlaceId
end
for _, g in ipairs(Games) do
	history[g.key] = history[g.key] or {}
	for _, c in ipairs(Config.Channels) do
		history[g.key][c] = history[g.key][c] or {}
	end
end

local state = {
	view = "home", -- "home" | "game" | "grid"
	gameKey = nil,
	channel = Config.Channels[1],
	layout = math.min(4, #Games),
	slots = {},
	floats = {}, -- { key, x, y, w, h, z, frame }
}
if state.layout == 3 then
	state.layout = 4
end
for i = 1, 4 do
	state.slots[i] = Games[i] and Games[i].key or nil
end
local panelTab = {}
local nextZ = 10

local function isHere(g)
	return g.placeId > 0 and g.placeId == currentPlaceId
end

local function teleport(g)
	RTeleport:FireServer(g.key)
end

---------------------------------------------------------------------------
-- Screen
---------------------------------------------------------------------------
local gui = make("ScreenGui", {
	Name = "StudioHub",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 20,
	Parent = player:WaitForChild("PlayerGui"),
})

local toggleBtn = button("Studio Hub", {
	Name = "Toggle",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 12, 1, -12),
	Size = UDim2.fromOffset(0, 36),
	TextSize = 14,
	Parent = gui,
}, nil, "pri")

local main = make("Frame", {
	Name = "Main",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.9, 0.82),
	BackgroundColor3 = C.main,
	ClipsDescendants = true,
	Visible = false,
	Parent = gui,
}, {
	corner(14),
	stroke(),
	make("UISizeConstraint", { MaxSize = Vector2.new(1080, 660), MinSize = Vector2.new(300, 260) }),
})

local floatLayer = make("Frame", {
	Name = "Floats",
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	Parent = gui,
})

local toastLabel = text({
	Name = "Toast",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -64),
	Size = UDim2.fromOffset(0, 36),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 0,
	BackgroundColor3 = C.fg,
	TextColor3 = C.bg,
	Font = FM,
	TextXAlignment = Enum.TextXAlignment.Center,
	Visible = false,
	ZIndex = 50,
	Parent = gui,
})
corner(9).Parent = toastLabel
padding(0, 14, 0, 14).Parent = toastLabel

local toastId = 0
local function toast(msg)
	toastId += 1
	local id = toastId
	toastLabel.Text = msg
	toastLabel.Visible = true
	task.delay(2.8, function()
		if toastId == id then
			toastLabel.Visible = false
		end
	end)
end
RNotice.OnClientEvent:Connect(toast)

local rail = make("ScrollingFrame", {
	Name = "Rail",
	Size = UDim2.new(0, 64, 1, 0),
	BackgroundColor3 = C.rail,
	BorderSizePixel = 0,
	ScrollBarThickness = 0,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = main,
}, { list(nil, 8, Enum.HorizontalAlignment.Center), padding(12, 0, 12, 0) })

local side = make("Frame", {
	Name = "Side",
	Position = UDim2.fromOffset(64, 0),
	Size = UDim2.new(0, 200, 1, 0),
	BackgroundColor3 = C.side,
	BorderSizePixel = 0,
	Parent = main,
})

local content = make("Frame", {
	Name = "Content",
	BackgroundTransparency = 1,
	Parent = main,
})

local closeBtn = make("TextButton", {
	Text = "X",
	Font = FB,
	TextSize = 14,
	TextColor3 = C.dim,
	BackgroundColor3 = C.raise,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 10),
	Size = UDim2.fromOffset(30, 30),
	ZIndex = 5,
	Parent = main,
}, { corner(8) })

local function isNarrow()
	return main.AbsoluteSize.X < 640
end

---------------------------------------------------------------------------
-- Chat views (live-updating lists)
---------------------------------------------------------------------------
local chatViews = {} -- { key, channel, list, compact }

local function nameColor(msg)
	if msg.system then
		return C.accent
	end
	return NAME_COLORS[(msg.userId % #NAME_COLORS) + 1]
end

local function messageRow(msg, compact)
	local av = compact and 26 or 34
	local row = make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	local avatar
	if msg.system or msg.userId <= 0 then
		avatar = make("TextLabel", {
			Text = "SH",
			Font = FB,
			TextSize = 11,
			TextColor3 = C.accentInk,
			BackgroundColor3 = C.accent,
			Size = UDim2.fromOffset(av, av),
		}, { round() })
	else
		avatar = make("ImageLabel", {
			Image = "rbxthumb://type=AvatarHeadShot&id=" .. msg.userId .. "&w=48&h=48",
			BackgroundColor3 = C.raise,
			Size = UDim2.fromOffset(av, av),
		}, { round() })
	end
	avatar.Parent = row

	local stamp = os.date("%H:%M", msg.t)
	text({
		RichText = true,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextSize = compact and 13 or 14,
		Text = string.format(
			'<font color="#%s"><b>%s</b></font>  <font color="#%s" size="11">%s</font>\n%s',
			nameColor(msg):ToHex(),
			richEscape(msg.name),
			C.faint:ToHex(),
			stamp,
			richEscape(msg.text)
		),
		Position = UDim2.fromOffset(av + 8, 0),
		Size = UDim2.new(1, -(av + 8), 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = row,
	})
	return row
end

local function scrollToBottom(scroller)
	task.defer(function()
		if scroller.Parent then
			local y = scroller.AbsoluteCanvasSize.Y - scroller.AbsoluteWindowSize.Y
			scroller.CanvasPosition = Vector2.new(0, math.max(0, y))
		end
	end)
end

local function buildChat(parent, key, channel, compact)
	local g = gamesByKey[key]
	local inputH = compact and 34 or 40
	local scroller = make("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -(inputH + 12)),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.line,
		Parent = parent,
	}, { list(nil, compact and 8 or 12), padding(compact and 8 or 14) })

	text({
		Text = "This is the start of #" .. channel .. " in " .. g.name .. ".",
		TextColor3 = C.faint,
		TextSize = 12,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = -1,
		Parent = scroller,
	})

	for i, msg in ipairs(history[key][channel]) do
		local row = messageRow(msg, compact)
		row.LayoutOrder = i
		row.Parent = scroller
	end
	scrollToBottom(scroller)

	local bar = make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, compact and 6 or 12, 1, -6),
		Size = UDim2.new(1, compact and -12 or -24, 0, inputH),
		BackgroundColor3 = C.raise,
		Parent = parent,
	}, { corner(9) })

	local box = make("TextBox", {
		PlaceholderText = "Message #" .. channel,
		PlaceholderColor3 = C.faint,
		Text = "",
		ClearTextOnFocus = false,
		Font = F,
		TextSize = 14,
		TextColor3 = C.fg,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -80, 1, 0),
		ClipsDescendants = true,
		Parent = bar,
	})

	local function send()
		local msg = string.gsub(box.Text, "^%s+", "")
		if #msg > 0 then
			RPost:FireServer(key, channel, string.sub(msg, 1, Config.MaxMessageLength))
			box.Text = ""
		end
	end
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			send()
		end
	end)
	button("Send", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.fromOffset(0, inputH - 8),
		Parent = bar,
	}, send, "pri")

	table.insert(chatViews, { key = key, channel = channel, list = scroller, compact = compact })
end

---------------------------------------------------------------------------
-- Panels: one game in a grid slot or floating window
---------------------------------------------------------------------------
local render -- forward declaration
local renderFloats
local popOut

local function cycleKey(currentKey, step, skip)
	local idx = gamesByKey[currentKey] and gamesByKey[currentKey].order or 1
	for _ = 1, #Games do
		idx = ((idx - 1 + step) % #Games) + 1
		local k = Games[idx].key
		if not (skip and skip[k]) then
			return k
		end
	end
	return currentKey
end

local function infoView(parent, g)
	local scroller = make("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		Parent = parent,
	}, { list(nil, 10), padding(12) })

	if g.placeId > 0 then
		make("ImageLabel", {
			Image = "rbxthumb://type=Asset&id=" .. g.placeId .. "&w=420&h=420",
			BackgroundColor3 = C.raise,
			Size = UDim2.fromOffset(120, 120),
			LayoutOrder = 1,
			Parent = scroller,
		}, { corner(10) })
	else
		local badge = avatarBadge(g, 72)
		badge.LayoutOrder = 1
		badge.Parent = scroller
	end

	local live = liveInfo[g.key]
	text({
		Text = g.name,
		Font = FB,
		TextSize = 17,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 2,
		Parent = scroller,
	})
	local pill = statusPill(g.status)
	pill.LayoutOrder = 3
	pill.Parent = scroller
	text({
		Text = g.blurb or "",
		TextColor3 = C.dim,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 4,
		Parent = scroller,
	})
	text({
		Text = g.placeId > 0 and ("Place " .. g.placeId .. (live and ("  ·  On Roblox: " .. live.robloxName) or ""))
			or "Not published yet",
		TextColor3 = C.faint,
		TextSize = 12,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 5,
		Parent = scroller,
	})

	local label, style = "Play", "pri"
	if isHere(g) then
		label, style = "You're here", nil
	elseif g.placeId <= 0 then
		label, style = "Coming soon", nil
	end
	button(label, { LayoutOrder = 6, Size = UDim2.fromOffset(0, 32), Parent = scroller }, function()
		teleport(g)
	end, style)
end

local function buildPanel(parent, place, idx, key)
	local g = gamesByKey[key]
	local tabKey = place .. idx
	local tab = panelTab[tabKey] or Config.Channels[1]

	local header = make("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = C.side,
		BorderSizePixel = 0,
		Active = true,
		Parent = parent,
	})
	local badge = avatarBadge(g, 24)
	badge.Position = UDim2.new(0, 10, 0.5, -12)
	badge.Parent = header
	text({
		Text = g.name,
		Font = FB,
		TextSize = 13,
		Position = UDim2.fromOffset(42, 0),
		Size = UDim2.new(1, -230, 1, 0),
		Parent = header,
	})

	local acts = make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 0),
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = header,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 4),
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local function small(label, fn, order)
		button(label, { Size = UDim2.fromOffset(0, 26), TextSize = 12, LayoutOrder = order, Parent = acts }, fn, "ghost")
	end

	-- change which game this panel shows
	local function swap(step)
		if place == "slot" then
			state.slots[idx] = cycleKey(key, step)
			render()
		else
			local skip = {}
			for i, f in ipairs(state.floats) do
				if i ~= idx then
					skip[f.key] = true
				end
			end
			state.floats[idx].key = cycleKey(key, step, skip)
			renderFloats()
		end
	end
	small("<", function()
		swap(-1)
	end, 1)
	small(">", function()
		swap(1)
	end, 2)

	if place == "slot" then
		small("Pop out", function()
			popOut(key, idx)
		end, 3)
		small("X", function()
			state.slots[idx] = nil
			render()
		end, 4)
	else
		small("Dock", function()
			local f = table.remove(state.floats, idx)
			local placed = false
			for i = 1, state.layout do
				if not state.slots[i] then
					state.slots[i] = f.key
					placed = true
					break
				end
			end
			if not placed then
				state.slots[state.layout] = f.key
			end
			state.view = "grid"
			main.Visible = true
			renderFloats()
			render()
		end, 3)
		small("X", function()
			table.remove(state.floats, idx)
			renderFloats()
			if state.view == "grid" then
				render()
			end
		end, 4)
	end

	-- tabs
	local tabs = make("Frame", {
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = C.side,
		BorderSizePixel = 0,
		Parent = parent,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 2),
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		padding(0, 6, 0, 6),
		make("Frame", { -- divider line
			BackgroundColor3 = C.line,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 1),
		}),
	})
	local tabList = {}
	for _, c in ipairs(Config.Channels) do
		table.insert(tabList, { c, "#" .. c })
	end
	table.insert(tabList, { "info", "Info" })
	for i, t in ipairs(tabList) do
		local on = tab == t[1]
		make("TextButton", {
			Text = t[2],
			Font = FM,
			TextSize = 12,
			TextColor3 = on and C.fg or C.dim,
			BackgroundColor3 = C.raise,
			BackgroundTransparency = on and 0 or 1,
			Size = UDim2.fromOffset(0, 24),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = i,
			Parent = tabs,
		}, { corner(6), padding(0, 8, 0, 8) }).Activated:Connect(function()
			panelTab[tabKey] = t[1]
			if place == "slot" then
				render()
			else
				renderFloats()
			end
		end)
	end

	local body = make("Frame", {
		Position = UDim2.fromOffset(0, 72),
		Size = UDim2.new(1, 0, 1, -72),
		BackgroundColor3 = C.main,
		BorderSizePixel = 0,
		Parent = parent,
	})
	if tab == "info" then
		infoView(body, g)
	else
		buildChat(body, key, tab, true)
	end
	return header
end

---------------------------------------------------------------------------
-- Floating windows
---------------------------------------------------------------------------
local function dragHandle(handle, getOrigin, onMove, onEnd)
	handle.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then
			return
		end
		local start = input.Position
		local ox, oy = getOrigin()
		local moveConn, endConn
		moveConn = UserInputService.InputChanged:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
				local d = i.Position - start
				onMove(ox + d.X, oy + d.Y)
			end
		end)
		endConn = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				moveConn:Disconnect()
				endConn:Disconnect()
				if onEnd then
					onEnd()
				end
			end
		end)
	end)
end

function renderFloats()
	clearAll(floatLayer)
	local screen = gui.AbsoluteSize
	for i, f in ipairs(state.floats) do
		local frame = make("Frame", {
			Position = UDim2.fromOffset(f.x, f.y),
			Size = UDim2.fromOffset(f.w, f.h),
			BackgroundColor3 = C.side,
			ClipsDescendants = true,
			ZIndex = f.z,
			Active = true,
			Parent = floatLayer,
		}, { corner(12), stroke(C.faint) })

		frame.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				nextZ += 1
				f.z = nextZ
				frame.ZIndex = nextZ
			end
		end)

		local header = buildPanel(frame, "float", i, f.key)
		dragHandle(header, function()
			return f.x, f.y
		end, function(x, y)
			f.x = math.clamp(x, -f.w + 80, screen.X - 80)
			f.y = math.clamp(y, 0, screen.Y - 40)
			frame.Position = UDim2.fromOffset(f.x, f.y)
		end)

		-- resize grip in the bottom-right corner
		local grip = make("TextButton", {
			Text = "//",
			Font = FB,
			TextSize = 10,
			TextColor3 = C.faint,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.fromScale(1, 1),
			Size = UDim2.fromOffset(18, 18),
			ZIndex = 5,
			Parent = frame,
		})
		dragHandle(grip, function()
			return f.w, f.h
		end, function(w, h)
			f.w = math.clamp(w, 260, screen.X - 16)
			f.h = math.clamp(h, 220, screen.Y - 16)
			frame.Size = UDim2.fromOffset(f.w, f.h)
		end)
	end
end

function popOut(key, fromSlot)
	for _, f in ipairs(state.floats) do
		if f.key == key then
			nextZ += 1
			f.z = nextZ
			renderFloats()
			toast("Already popped out")
			return
		end
	end
	if #state.floats >= Config.MaxWindows then
		toast("You can pop out " .. Config.MaxWindows .. " games at once. Close one first.")
		return
	end
	local screen = gui.AbsoluteSize
	local n = #state.floats
	local w = math.min(360, screen.X - 24)
	local h = math.min(440, screen.Y - 80)
	nextZ += 1
	table.insert(state.floats, {
		key = key,
		x = math.max(8, screen.X - w - 24 - n * 32),
		y = math.max(8, math.min(screen.Y - h - 8, 60 + n * 32)),
		w = w,
		h = h,
		z = nextZ,
	})
	if fromSlot and state.slots[fromSlot] == key then
		state.slots[fromSlot] = nil
	end
	renderFloats()
	render()
end

---------------------------------------------------------------------------
-- Main window views
---------------------------------------------------------------------------
local function topBar(titleText)
	local bar = make("Frame", {
		Name = "Top",
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundTransparency = 1,
		Parent = content,
	}, {
		make("Frame", {
			BackgroundColor3 = C.line,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 1),
		}),
	})
	text({
		Text = titleText,
		Font = FB,
		TextSize = 16,
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(0.4, 0, 1, 0),
		Parent = bar,
	})
	local acts = make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -50, 0, 0),
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = bar,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			VerticalAlignment = Enum.VerticalAlignment.Center,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	return acts
end

local function body(top)
	return make("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, top),
		Size = UDim2.new(1, 0, 1, -top),
		Parent = content,
	})
end

local function homeView()
	local acts = topBar("All games")
	button("Multi-view", { Parent = acts }, function()
		state.view = "grid"
		render()
	end)

	local scroller = make("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		Parent = body(50),
	}, { list(nil, 14), padding(16) })

	text({
		Text = "Your games",
		Font = FB,
		TextSize = 12,
		TextColor3 = C.faint,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 1,
		Parent = scroller,
	})
	local cards = make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = scroller,
	}, {
		make("UIGridLayout", {
			CellSize = UDim2.fromOffset(230, 156),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for i, g in ipairs(Games) do
		local card = make("Frame", {
			BackgroundColor3 = C.side,
			LayoutOrder = i,
			Parent = cards,
		}, { corner(12), stroke(), padding(12) })
		local b = avatarBadge(g, 30)
		b.Parent = card
		text({
			Text = g.name,
			Font = FB,
			TextSize = 14,
			Position = UDim2.fromOffset(40, 0),
			Size = UDim2.new(1, -40, 0, 30),
			Parent = card,
		})
		local pill = statusPill(isHere(g) and "You're here" or g.status)
		if isHere(g) then
			pill.TextColor3 = C.ok
		end
		pill.Position = UDim2.fromOffset(0, 38)
		pill.Parent = card
		text({
			Text = g.blurb or "",
			TextColor3 = C.dim,
			TextSize = 12,
			TextWrapped = true,
			Position = UDim2.fromOffset(0, 64),
			Size = UDim2.new(1, 0, 0, 30),
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = card,
		})
		local row = make("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 26),
			Parent = card,
		}, {
			make("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		button("Open", { Size = UDim2.fromOffset(0, 26), TextSize = 12, LayoutOrder = 1, Parent = row }, function()
			state.view, state.gameKey, state.channel = "game", g.key, Config.Channels[1]
			render()
		end)
		button("Pop out", { Size = UDim2.fromOffset(0, 26), TextSize = 12, LayoutOrder = 2, Parent = row }, function()
			popOut(g.key)
		end)
		if g.placeId > 0 and not isHere(g) then
			button("Play", { Size = UDim2.fromOffset(0, 26), TextSize = 12, LayoutOrder = 3, Parent = row }, function()
				teleport(g)
			end, "pri")
		end
	end

	-- What's happening: newest messages across every game
	text({
		Text = "What's happening",
		Font = FB,
		TextSize = 12,
		TextColor3 = C.faint,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 3,
		Parent = scroller,
	})
	local feed = {}
	for _, g in ipairs(Games) do
		for _, c in ipairs(Config.Channels) do
			for _, m in ipairs(history[g.key][c]) do
				table.insert(feed, { g = g, c = c, m = m })
			end
		end
	end
	table.sort(feed, function(a, b)
		return a.m.t > b.m.t
	end)
	for i = 1, math.min(12, #feed) do
		local item = feed[i]
		text({
			RichText = true,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextSize = 13,
			Text = string.format(
				'<font color="#%s"><b>%s</b></font> <font color="#%s">· %s · #%s</font>\n%s',
				nameColor(item.m):ToHex(),
				richEscape(item.m.name),
				C.faint:ToHex(),
				richEscape(item.g.name),
				item.c,
				richEscape(item.m.text)
			),
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 3 + i,
			Parent = scroller,
		})
	end
end

local function gameView()
	local g = gamesByKey[state.gameKey]
	local acts = topBar((isNarrow() and "" or g.name .. "  /  ") .. "#" .. state.channel)
	button("Pop out", { Parent = acts }, function()
		popOut(g.key)
	end)
	button("Add to grid", { Parent = acts }, function()
		local placed = false
		for i = 1, 4 do
			if state.slots[i] == g.key then
				placed = true
			end
		end
		if not placed then
			for i = 1, 4 do
				if not state.slots[i] then
					state.slots[i] = g.key
					placed = true
					break
				end
			end
		end
		if not placed then
			state.slots[4] = g.key
		end
		state.layout = 4
		state.view = "grid"
		render()
	end)

	local top = 50
	if isNarrow() then
		-- no sidebar on small screens, so show channel tabs here
		local tabs = make("Frame", {
			Position = UDim2.fromOffset(0, 50),
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundTransparency = 1,
			Parent = content,
		}, {
			make("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 4),
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			padding(0, 10, 0, 10),
		})
		for i, c in ipairs(Config.Channels) do
			button("#" .. c, { Size = UDim2.fromOffset(0, 26), TextSize = 12, LayoutOrder = i, Parent = tabs }, function()
				state.channel = c
				render()
			end, state.channel == c and nil or "ghost")
		end
		top = 84
	end
	buildChat(body(top), g.key, state.channel, false)
end

local function gridView()
	local acts = topBar("Multi-view")
	text({
		Text = #state.floats .. "/" .. Config.MaxWindows .. " popped out",
		TextColor3 = C.faint,
		TextSize = 12,
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 0,
		Parent = acts,
	})
	for i, n in ipairs({ 1, 2, 4 }) do
		button(tostring(n), { LayoutOrder = i, Size = UDim2.fromOffset(32, 28), AutomaticSize = Enum.AutomaticSize.None, Parent = acts }, function()
			state.layout = n
			render()
		end, state.layout == n and "pri" or nil)
	end

	local area = body(50)
	-- size cells from the main window (always measured, unlike a frame made this frame)
	local W = math.max(260, main.AbsoluteSize.X - 64)
	local H = math.max(200, main.AbsoluteSize.Y - 50)
	local gap = 10
	local narrow = isNarrow()
	local cols = (narrow or state.layout == 1) and 1 or 2
	local rows = (not narrow and state.layout == 4) and 2 or 1
	local cellW = math.floor((W - gap * (cols + 1)) / cols)
	local cellH = narrow and 360 or math.floor((H - gap * (rows + 1)) / rows)

	local scroller = make("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = narrow and 4 or 0,
		Parent = area,
	}, {
		make("UIGridLayout", {
			CellSize = UDim2.fromOffset(cellW, cellH),
			CellPadding = UDim2.fromOffset(gap, gap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		padding(gap),
	})

	for i = 1, state.layout do
		local key = state.slots[i]
		if key and not gamesByKey[key] then
			key = nil
		end
		if key then
			local slot = make("Frame", {
				BackgroundColor3 = C.side,
				ClipsDescendants = true,
				LayoutOrder = i,
				Parent = scroller,
			}, { corner(12), stroke() })
			buildPanel(slot, "slot", i, key)
		else
			local slot = make("Frame", {
				BackgroundTransparency = 1,
				LayoutOrder = i,
				Parent = scroller,
			}, { corner(12), stroke(C.line) })
			local picks = make("ScrollingFrame", {
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollBarThickness = 4,
				Parent = slot,
			}, { list(nil, 6, Enum.HorizontalAlignment.Center), padding(16) })
			text({
				Text = "Empty slot. Pick a game:",
				TextColor3 = C.faint,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 0, 20),
				Parent = picks,
			})
			for j, g in ipairs(Games) do
				button(g.name, { LayoutOrder = j, Parent = picks }, function()
					state.slots[i] = g.key
					render()
				end)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Rail + sidebar
---------------------------------------------------------------------------
local function railButton(labelText, color, selected, onClick, order)
	local b = make("TextButton", {
		Text = labelText,
		Font = FB,
		TextSize = 15,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = color,
		AutoButtonColor = true,
		Size = UDim2.fromOffset(44, 44),
		LayoutOrder = order,
		Parent = rail,
	}, { make("UICorner", { CornerRadius = selected and UDim.new(0, 14) or UDim.new(0.5, 0) }) })
	if selected then
		make("UIStroke", { Color = C.fg, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
	end
	b.Activated:Connect(onClick)
	return b
end

local function renderRail()
	clear(rail)
	railButton("Home", C.raise, state.view == "home", function()
		state.view = "home"
		render()
	end, 1).TextSize = 11
	local gridLabel = "Grid"
	if #state.floats > 0 then
		gridLabel = "Grid " .. #state.floats
	end
	railButton(gridLabel, C.raise, state.view == "grid", function()
		state.view = "grid"
		render()
	end, 2).TextSize = 11
	make("Frame", {
		BackgroundColor3 = C.line,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(28, 2),
		LayoutOrder = 3,
		Parent = rail,
	})
	for i, g in ipairs(Games) do
		local b = railButton(initials(g.name), g.color, state.view == "game" and state.gameKey == g.key, function()
			state.view, state.gameKey, state.channel = "game", g.key, Config.Channels[1]
			render()
		end, 3 + i)
		make("Frame", { -- status dot
			BackgroundColor3 = STATUS_COLOR[g.status] or C.dim,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, 2, 1, 2),
			Size = UDim2.fromOffset(12, 12),
			Parent = b,
		}, { round(), make("UIStroke", { Color = C.rail, Thickness = 2 }) })
	end
end

local function sideButton(labelText, selected, onClick, order, countText)
	local b = make("TextButton", {
		Text = "",
		BackgroundColor3 = C.raise,
		BackgroundTransparency = selected and 0 or 1,
		AutoButtonColor = true,
		Size = UDim2.new(1, 0, 0, 32),
		LayoutOrder = order,
		Parent = side,
	}, { corner(6) })
	text({
		Text = labelText,
		TextColor3 = selected and C.fg or C.dim,
		Font = FM,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -50, 1, 0),
		Parent = b,
	})
	if countText then
		text({
			Text = countText,
			TextColor3 = C.faint,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 0),
			Size = UDim2.new(0, 60, 1, 0),
			Parent = b,
		})
	end
	b.Activated:Connect(onClick)
	return b
end

local function sideLabel(t, order)
	text({
		Text = string.upper(t),
		Font = FB,
		TextSize = 11,
		TextColor3 = C.faint,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = order,
		Parent = side,
	})
end

local function renderSide()
	clearAll(side)
	list(nil, 2).Parent = side
	padding(12, 8, 12, 8).Parent = side

	if state.view == "game" then
		local g = gamesByKey[state.gameKey]
		text({
			Text = g.name,
			Font = FB,
			TextSize = 15,
			Size = UDim2.new(1, 0, 0, 22),
			LayoutOrder = 1,
			Parent = side,
		})
		local pill = statusPill(isHere(g) and "You're here" or g.status)
		pill.LayoutOrder = 2
		pill.Parent = side
		sideLabel("Channels", 3)
		for i, c in ipairs(Config.Channels) do
			sideButton("# " .. c, state.channel == c, function()
				state.channel = c
				render()
			end, 3 + i, tostring(#history[g.key][c]))
		end
		sideLabel("Game", 20)
		local label, style = "Play", "pri"
		if isHere(g) then
			label, style = "You're here", nil
		elseif g.placeId <= 0 then
			label, style = "Coming soon", nil
		end
		button(label, { LayoutOrder = 21, Size = UDim2.new(1, 0, 0, 32), AutomaticSize = Enum.AutomaticSize.None, Parent = side }, function()
			teleport(g)
		end, style)
		text({
			Text = g.blurb or "",
			TextColor3 = C.dim,
			TextSize = 12,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 22,
			Parent = side,
		})
	else
		text({
			Text = "Studio Hub",
			Font = FB,
			TextSize = 15,
			Size = UDim2.new(1, 0, 0, 22),
			LayoutOrder = 1,
			Parent = side,
		})
		sideLabel("Games · " .. #Games, 2)
		for i, g in ipairs(Games) do
			sideButton(g.name, false, function()
				state.view, state.gameKey, state.channel = "game", g.key, Config.Channels[1]
				render()
			end, 2 + i, g.status)
		end
	end
end

---------------------------------------------------------------------------
-- Render
---------------------------------------------------------------------------
function render()
	-- forget chat views that were destroyed
	local alive = {}
	for _, v in ipairs(chatViews) do
		if v.list.Parent and v.list:IsDescendantOf(floatLayer) then
			table.insert(alive, v)
		end
	end
	chatViews = alive

	if state.view == "game" and not gamesByKey[state.gameKey] then
		state.view = "home"
	end

	local showSide = state.view ~= "grid" and not isNarrow()
	side.Visible = showSide
	local left = showSide and 264 or 64
	content.Position = UDim2.fromOffset(left, 0)
	content.Size = UDim2.new(1, -left, 1, 0)

	renderRail()
	if showSide then
		renderSide()
	end
	clearAll(content)
	if state.view == "game" then
		gameView()
	elseif state.view == "grid" then
		gridView()
	else
		homeView()
	end
end

local baseRenderFloats = renderFloats
function renderFloats()
	-- drop chat views that lived in old floating windows
	local alive = {}
	for _, v in ipairs(chatViews) do
		if v.list.Parent and not v.list:IsDescendantOf(floatLayer) then
			table.insert(alive, v)
		end
	end
	chatViews = alive
	baseRenderFloats()
end

---------------------------------------------------------------------------
-- Live messages
---------------------------------------------------------------------------
RNew.OnClientEvent:Connect(function(key, channel, msg)
	if not history[key] or not history[key][channel] then
		return
	end
	local h = history[key][channel]
	table.insert(h, msg)
	while #h > Config.HistorySize do
		table.remove(h, 1)
	end
	for _, v in ipairs(chatViews) do
		if v.key == key and v.channel == channel and v.list.Parent then
			local row = messageRow(msg, v.compact)
			row.LayoutOrder = #v.list:GetChildren() + 1000
			row.Parent = v.list
			scrollToBottom(v.list)
		end
	end
	if main.Visible and state.view == "home" then
		render()
	end
end)

---------------------------------------------------------------------------
-- Open / close
---------------------------------------------------------------------------
local function setOpen(open)
	main.Visible = open
	toggleBtn.Text = open and "Close Hub" or "Studio Hub"
	if open then
		render()
	end
end
toggleBtn.Activated:Connect(function()
	setOpen(not main.Visible)
end)
closeBtn.Activated:Connect(function()
	setOpen(false)
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Config.ToggleKey then
		setOpen(not main.Visible)
	end
end)

-- re-layout when the window changes size (e.g. phone rotates)
local lastNarrow = nil
local pending = false
main:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	if pending or not main.Visible then
		return
	end
	pending = true
	task.delay(0.2, function()
		pending = false
		local n = isNarrow()
		if n ~= lastNarrow or state.view == "grid" then
			lastNarrow = n
			render()
		end
	end)
end)
