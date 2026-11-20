-- Haunted Brainrot Manor: the HUD and the player's buttons.
-- One LocalScript, one job: drawing the interface and forwarding the player's
-- choices to the server. It never decides anything about money, ownership or
-- the storm; it only shows what the server tells it and asks for what the
-- player clicks. Every keybind goes through ContextActionService, so the game
-- never fights Roblox's own input handling.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local GameEvent = ReplicatedStorage:WaitForChild("GameEvent")
local PlayerAction = ReplicatedStorage:WaitForChild("PlayerAction")
local BrainrotData = require(ReplicatedStorage.Shared.BrainrotData)

--------------------------------------------------------------------------------
-- Building the HUD
--------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "ManorHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local function makeCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

-- Title strip, centred at the very top.
local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleStrip"
titleLabel.AnchorPoint = Vector2.new(0.5, 0)
titleLabel.Position = UDim2.new(0.5, 0, 0, 4)
titleLabel.Size = UDim2.fromOffset(560, 26)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "👻 HAUNTED BRAINROT MANOR 👻"
titleLabel.TextColor3 = Color3.fromRGB(200, 170, 255)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 22
titleLabel.TextStrokeTransparency = 0.3
titleLabel.Parent = gui

-- Top bar, centred: big cash, income per second, rebirth multiplier.
local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.AnchorPoint = Vector2.new(0.5, 0)
topBar.Position = UDim2.new(0.5, 0, 0, 32)
topBar.Size = UDim2.fromOffset(520, 66)
topBar.BackgroundColor3 = Color3.fromRGB(20, 14, 35)
topBar.BackgroundTransparency = 0.1
topBar.BorderSizePixel = 0
topBar.Parent = gui
makeCorner(topBar, 12)

local cashLabel = Instance.new("TextLabel")
cashLabel.Name = "Cash"
cashLabel.Position = UDim2.new(0, 0, 0, 4)
cashLabel.Size = UDim2.new(0.55, 0, 0, 40)
cashLabel.BackgroundTransparency = 1
cashLabel.Text = "$100"
cashLabel.TextColor3 = Color3.fromRGB(140, 255, 140)
cashLabel.Font = Enum.Font.GothamBold
cashLabel.TextSize = 32
cashLabel.Parent = topBar

local incomeLabel = Instance.new("TextLabel")
incomeLabel.Name = "Income"
incomeLabel.Position = UDim2.new(0.55, 0, 0, 4)
incomeLabel.Size = UDim2.new(0.45, 0, 0, 40)
incomeLabel.BackgroundTransparency = 1
incomeLabel.Text = "+$0/s"
incomeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
incomeLabel.Font = Enum.Font.GothamBold
incomeLabel.TextSize = 26
incomeLabel.Parent = topBar

local rebirthLabel = Instance.new("TextLabel")
rebirthLabel.Name = "Rebirth"
rebirthLabel.Position = UDim2.new(0, 0, 0, 42)
rebirthLabel.Size = UDim2.new(1, 0, 0, 20)
rebirthLabel.BackgroundTransparency = 1
rebirthLabel.Text = "REBIRTH 0  ·  x1 MULT"
rebirthLabel.TextColor3 = Color3.fromRGB(200, 170, 255)
rebirthLabel.Font = Enum.Font.GothamBold
rebirthLabel.TextSize = 16
rebirthLabel.Parent = topBar

-- Live event banner, across the top under the cash bar. Always visible: the
-- storm countdown in calm weather, the live storm while it rages.
local eventBanner = Instance.new("TextLabel")
eventBanner.Name = "EventBanner"
eventBanner.AnchorPoint = Vector2.new(0.5, 0)
eventBanner.Position = UDim2.new(0.5, 0, 0, 106)
eventBanner.Size = UDim2.fromOffset(720, 42)
eventBanner.BackgroundColor3 = Color3.fromRGB(35, 25, 60)
eventBanner.BackgroundTransparency = 0.1
eventBanner.BorderSizePixel = 0
eventBanner.Text = "NEXT POLTERGEIST STORM 2:30"
eventBanner.TextColor3 = Color3.fromRGB(220, 210, 255)
eventBanner.Font = Enum.Font.GothamBold
eventBanner.TextSize = 20
eventBanner.Parent = gui
makeCorner(eventBanner, 10)

-- Burglar banner, under the event banner. Only while he is in the manor.
local burglarBanner = Instance.new("TextLabel")
burglarBanner.Name = "BurglarBanner"
burglarBanner.AnchorPoint = Vector2.new(0.5, 0)
burglarBanner.Position = UDim2.new(0.5, 0, 0, 154)
burglarBanner.Size = UDim2.fromOffset(720, 36)
burglarBanner.BackgroundColor3 = Color3.fromRGB(150, 30, 40)
burglarBanner.BackgroundTransparency = 0.1
burglarBanner.BorderSizePixel = 0
burglarBanner.Text = "👻 THE GHOST BURGLAR IS IN THE MANOR! WHACK HIM! [F]"
burglarBanner.TextColor3 = Color3.fromRGB(255, 255, 255)
burglarBanner.Font = Enum.Font.GothamBold
burglarBanner.TextSize = 19
burglarBanner.Visible = false
burglarBanner.Parent = gui
makeCorner(burglarBanner, 10)

-- Quest panel, right side: all 11 quests with progress and cash rewards.
local questPanel = Instance.new("Frame")
questPanel.Name = "QuestPanel"
questPanel.AnchorPoint = Vector2.new(1, 0)
questPanel.Position = UDim2.new(1, -12, 0, 200)
questPanel.Size = UDim2.fromOffset(320, 420)
questPanel.BackgroundColor3 = Color3.fromRGB(20, 14, 35)
questPanel.BackgroundTransparency = 0.15
questPanel.BorderSizePixel = 0
questPanel.Parent = gui
makeCorner(questPanel, 12)

local questHeader = Instance.new("TextLabel")
questHeader.Name = "Header"
questHeader.Size = UDim2.new(1, 0, 0, 30)
questHeader.BackgroundTransparency = 1
questHeader.Text = "QUESTS  0/11 done"
questHeader.TextColor3 = Color3.fromRGB(255, 210, 90)
questHeader.Font = Enum.Font.GothamBold
questHeader.TextSize = 18
questHeader.Parent = questPanel

local questRows = {}
for i, quest in ipairs(BrainrotData.QUESTS) do
	local row = Instance.new("TextLabel")
	row.Name = "Quest_" .. quest.id
	row.Position = UDim2.new(0, 10, 0, 30 + (i - 1) * 34)
	row.Size = UDim2.new(1, -20, 0, 32)
	row.BackgroundTransparency = 1
	row.Text = quest.name
	row.TextColor3 = Color3.fromRGB(230, 220, 255)
	row.Font = Enum.Font.Gotham
	row.TextSize = 14
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.TextWrapped = true
	row.Parent = questPanel
	questRows[quest.id] = row
end

-- Prize Book feed, left side: the newest index entries, as they happen.
local feedPanel = Instance.new("Frame")
feedPanel.Name = "PrizeFeed"
feedPanel.Position = UDim2.new(0, 12, 0, 200)
feedPanel.Size = UDim2.fromOffset(320, 170)
feedPanel.BackgroundColor3 = Color3.fromRGB(20, 14, 35)
feedPanel.BackgroundTransparency = 0.15
feedPanel.BorderSizePixel = 0
feedPanel.Parent = gui
makeCorner(feedPanel, 12)

local feedHeader = Instance.new("TextLabel")
feedHeader.Name = "Header"
feedHeader.Size = UDim2.new(1, 0, 0, 30)
feedHeader.BackgroundTransparency = 1
feedHeader.Text = "📖 PRIZE BOOK"
feedHeader.TextColor3 = Color3.fromRGB(255, 210, 90)
feedHeader.Font = Enum.Font.GothamBold
feedHeader.TextSize = 18
feedHeader.Parent = feedPanel

local feedLines = {}
for i = 1, 4 do
	local line = Instance.new("TextLabel")
	line.Name = "FeedLine" .. i
	line.Position = UDim2.new(0, 10, 0, 30 + (i - 1) * 32)
	line.Size = UDim2.new(1, -20, 0, 30)
	line.BackgroundTransparency = 1
	line.Text = ""
	line.TextColor3 = Color3.fromRGB(180, 255, 180)
	line.Font = Enum.Font.Gotham
	line.TextSize = 14
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.TextWrapped = true
	line.Parent = feedPanel
	feedLines[i] = line
end

local function pushFeedLine(text)
	for i = 4, 2, -1 do
		feedLines[i].Text = feedLines[i - 1].Text
	end
	feedLines[1].Text = text
end

-- Info panel, bottom-left: slots, index count, rebirth.
local infoPanel = Instance.new("Frame")
infoPanel.Name = "InfoPanel"
infoPanel.Position = UDim2.new(0, 12, 1, -150)
infoPanel.Size = UDim2.fromOffset(250, 64)
infoPanel.BackgroundColor3 = Color3.fromRGB(20, 14, 35)
infoPanel.BackgroundTransparency = 0.15
infoPanel.BorderSizePixel = 0
infoPanel.Parent = gui
makeCorner(infoPanel, 10)

local slotsLabel = Instance.new("TextLabel")
slotsLabel.Name = "Slots"
slotsLabel.Position = UDim2.new(0, 10, 0, 6)
slotsLabel.Size = UDim2.new(1, -20, 0, 26)
slotsLabel.BackgroundTransparency = 1
slotsLabel.Text = "SLOTS 0/8"
slotsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
slotsLabel.Font = Enum.Font.GothamBold
slotsLabel.TextSize = 18
slotsLabel.TextXAlignment = Enum.TextXAlignment.Left
slotsLabel.Parent = infoPanel

local indexLabel = Instance.new("TextLabel")
indexLabel.Name = "Index"
indexLabel.Position = UDim2.new(0, 10, 0, 32)
indexLabel.Size = UDim2.new(1, -20, 0, 26)
indexLabel.BackgroundTransparency = 1
indexLabel.Text = "INDEX 0/36"
indexLabel.TextColor3 = Color3.fromRGB(200, 170, 255)
indexLabel.Font = Enum.Font.GothamBold
indexLabel.TextSize = 18
indexLabel.TextXAlignment = Enum.TextXAlignment.Left
indexLabel.Parent = infoPanel

-- Bottom strip: the content counts, always on screen.
local bottomStrip = Instance.new("TextLabel")
bottomStrip.Name = "BottomStrip"
bottomStrip.AnchorPoint = Vector2.new(0.5, 1)
bottomStrip.Position = UDim2.new(0.5, 0, 1, -2)
bottomStrip.Size = UDim2.fromOffset(760, 18)
bottomStrip.BackgroundTransparency = 1
bottomStrip.Text = "36 BRAINROTS  ·  8 RARITIES  ·  6 MUTATIONS  ·  THIEVES  ·  LOCK  ·  REBIRTH"
bottomStrip.TextColor3 = Color3.fromRGB(180, 170, 210)
bottomStrip.Font = Enum.Font.GothamBold
bottomStrip.TextSize = 14
bottomStrip.Parent = gui

-- Carrying banner, just above the buttons.
local carryLabel = Instance.new("TextLabel")
carryLabel.Name = "CarryHint"
carryLabel.AnchorPoint = Vector2.new(0.5, 1)
carryLabel.Position = UDim2.new(0.5, 0, 1, -140)
carryLabel.Size = UDim2.fromOffset(560, 36)
carryLabel.BackgroundColor3 = Color3.fromRGB(200, 110, 20)
carryLabel.BackgroundTransparency = 0.1
carryLabel.BorderSizePixel = 0
carryLabel.Text = ""
carryLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
carryLabel.Font = Enum.Font.GothamBold
carryLabel.TextSize = 18
carryLabel.Visible = false
carryLabel.Parent = gui
makeCorner(carryLabel, 10)

-- Status line for server replies ("Base locked for 60s", "Not enough cash"...).
local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.AnchorPoint = Vector2.new(0.5, 1)
statusLabel.Position = UDim2.new(0.5, 0, 1, -180)
statusLabel.Size = UDim2.fromOffset(600, 28)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = ""
statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextSize = 16
statusLabel.TextStrokeTransparency = 0.4
statusLabel.Parent = gui

-- Bottom buttons: LOCK / WHACK / UPGRADES / REBIRTH / INDEX, with keybinds.
local buttonRow = Instance.new("Frame")
buttonRow.Name = "Buttons"
buttonRow.AnchorPoint = Vector2.new(0.5, 1)
buttonRow.Position = UDim2.new(0.5, 0, 1, -24)
buttonRow.Size = UDim2.fromOffset(700, 56)
buttonRow.BackgroundTransparency = 1
buttonRow.Parent = gui

local buttonLayout = Instance.new("UIListLayout")
buttonLayout.FillDirection = Enum.FillDirection.Horizontal
buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
buttonLayout.Padding = UDim.new(0, 10)
buttonLayout.Parent = buttonRow

local function makeButton(name, text, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.fromOffset(130, 56)
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.TextWrapped = true
	button.Parent = buttonRow
	makeCorner(button, 10)
	return button
end

local lockButton = makeButton("LockButton", "🔒 LOCK [L]", Color3.fromRGB(70, 110, 200))
local whackButton = makeButton("WhackButton", "🥊 WHACK [F]", Color3.fromRGB(200, 90, 40))
local upgradesButton = makeButton("UpgradesButton", "⬆️ UPGRADES [U]", Color3.fromRGB(60, 140, 200))
local rebirthButton = makeButton("RebirthButton", "⭐ REBIRTH [R]\n$100K", Color3.fromRGB(160, 80, 220))
local indexButton = makeButton("IndexButton", "📖 INDEX [B]\n0/36 found", Color3.fromRGB(60, 170, 90))

-- Upgrades panel, hidden until UPGRADES is pressed: the two real upgrades.
local upgradesPanel = Instance.new("Frame")
upgradesPanel.Name = "UpgradesPanel"
upgradesPanel.AnchorPoint = Vector2.new(0.5, 1)
upgradesPanel.Position = UDim2.new(0.5, 0, 1, -88)
upgradesPanel.Size = UDim2.fromOffset(340, 60)
upgradesPanel.BackgroundColor3 = Color3.fromRGB(20, 14, 35)
upgradesPanel.BackgroundTransparency = 0.1
upgradesPanel.BorderSizePixel = 0
upgradesPanel.Visible = false
upgradesPanel.Parent = gui
makeCorner(upgradesPanel, 10)

local bootsButton = Instance.new("TextButton")
bootsButton.Name = "BootsButton"
bootsButton.Position = UDim2.new(0, 10, 0, 8)
bootsButton.Size = UDim2.fromOffset(155, 44)
bootsButton.BackgroundColor3 = Color3.fromRGB(60, 170, 90)
bootsButton.BorderSizePixel = 0
bootsButton.Text = "🥾 Speed Boots\n$5,000"
bootsButton.TextColor3 = Color3.fromRGB(255, 255, 255)
bootsButton.Font = Enum.Font.GothamBold
bootsButton.TextSize = 15
bootsButton.TextWrapped = true
bootsButton.Parent = upgradesPanel
makeCorner(bootsButton, 8)

local gloveButton = Instance.new("TextButton")
gloveButton.Name = "GloveButton"
gloveButton.Position = UDim2.new(1, -165, 0, 8)
gloveButton.Size = UDim2.fromOffset(155, 44)
gloveButton.BackgroundColor3 = Color3.fromRGB(200, 150, 40)
gloveButton.BorderSizePixel = 0
gloveButton.Text = "🧤 Golden Glove\n$2,500"
gloveButton.TextColor3 = Color3.fromRGB(255, 255, 255)
gloveButton.Font = Enum.Font.GothamBold
gloveButton.TextSize = 15
gloveButton.TextWrapped = true
gloveButton.Parent = upgradesPanel
makeCorner(gloveButton, 8)

-- Index panel, hidden until INDEX is pressed: all 36 brainrots, found ones lit.
local indexPanel = Instance.new("Frame")
indexPanel.Name = "IndexPanel"
indexPanel.AnchorPoint = Vector2.new(0.5, 0.5)
indexPanel.Position = UDim2.fromScale(0.5, 0.5)
indexPanel.Size = UDim2.fromOffset(520, 460)
indexPanel.BackgroundColor3 = Color3.fromRGB(20, 14, 35)
indexPanel.BackgroundTransparency = 0.05
indexPanel.BorderSizePixel = 0
indexPanel.Visible = false
indexPanel.Parent = gui
makeCorner(indexPanel, 12)

local indexHeader = Instance.new("TextLabel")
indexHeader.Name = "Header"
indexHeader.Size = UDim2.new(1, 0, 0, 34)
indexHeader.BackgroundTransparency = 1
indexHeader.Text = "📖 PRIZE BOOK — 0/36 found"
indexHeader.TextColor3 = Color3.fromRGB(255, 210, 90)
indexHeader.Font = Enum.Font.GothamBold
indexHeader.TextSize = 20
indexHeader.Parent = indexPanel

local indexClose = Instance.new("TextButton")
indexClose.Name = "Close"
indexClose.AnchorPoint = Vector2.new(1, 0)
indexClose.Position = UDim2.new(1, -8, 0, 6)
indexClose.Size = UDim2.fromOffset(28, 28)
indexClose.BackgroundColor3 = Color3.fromRGB(150, 40, 50)
indexClose.BorderSizePixel = 0
indexClose.Text = "X"
indexClose.TextColor3 = Color3.fromRGB(255, 255, 255)
indexClose.Font = Enum.Font.GothamBold
indexClose.TextSize = 16
indexClose.Parent = indexPanel
makeCorner(indexClose, 6)

local indexScroll = Instance.new("ScrollingFrame")
indexScroll.Name = "List"
indexScroll.Position = UDim2.new(0, 10, 0, 40)
indexScroll.Size = UDim2.new(1, -20, 1, -50)
indexScroll.BackgroundTransparency = 1
indexScroll.BorderSizePixel = 0
indexScroll.ScrollBarThickness = 6
indexScroll.CanvasSize = UDim2.new(0, 0, 0, #BrainrotData.CAST * 22)
indexScroll.Parent = indexPanel

local indexRows = {}
for i, def in ipairs(BrainrotData.CAST) do
	local row = Instance.new("TextLabel")
	row.Name = "Index_" .. def.id
	row.Position = UDim2.new(0, 0, 0, (i - 1) * 22)
	row.Size = UDim2.new(1, 0, 0, 20)
	row.BackgroundTransparency = 1
	row.Text = "·  " .. def.name .. "  (" .. def.rarity .. ")  $" .. def.rate .. "/s"
	row.TextColor3 = Color3.fromRGB(120, 115, 140)
	row.Font = Enum.Font.Gotham
	row.TextSize = 14
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.Parent = indexScroll
	indexRows[def.id] = row
end

local function refreshIndexPanel(foundIds)
	local foundSet = {}
	for _, id in ipairs(foundIds) do
		foundSet[id] = true
	end
	for _, def in ipairs(BrainrotData.CAST) do
		local row = indexRows[def.id]
		if foundSet[def.id] then
			row.Text = "✓  " .. def.name .. "  (" .. def.rarity .. ")  $" .. def.rate .. "/s"
			row.TextColor3 = Color3.fromRGB(140, 255, 140)
		else
			row.Text = "·  " .. def.name .. "  (" .. def.rarity .. ")  $" .. def.rate .. "/s"
			row.TextColor3 = Color3.fromRGB(120, 115, 140)
		end
	end
end

--------------------------------------------------------------------------------
-- Wiring the buttons to the server
--------------------------------------------------------------------------------

local function activateGlove()
	local character = player.Character
	if character == nil then
		return
	end
	local glove = character:FindFirstChild("Slap Glove")
	if glove ~= nil then
		glove:Activate()
	end
end

lockButton.MouseButton1Click:Connect(function()
	PlayerAction:FireServer("Lock")
end)

whackButton.MouseButton1Click:Connect(activateGlove)

upgradesButton.MouseButton1Click:Connect(function()
	upgradesPanel.Visible = not upgradesPanel.Visible
end)

rebirthButton.MouseButton1Click:Connect(function()
	PlayerAction:FireServer("Rebirth")
end)

indexButton.MouseButton1Click:Connect(function()
	indexPanel.Visible = not indexPanel.Visible
end)

indexClose.MouseButton1Click:Connect(function()
	indexPanel.Visible = false
end)

bootsButton.MouseButton1Click:Connect(function()
	PlayerAction:FireServer("BuySpeedBoots")
end)

gloveButton.MouseButton1Click:Connect(function()
	PlayerAction:FireServer("BuyGoldenGlove")
end)

-- Every keybind through ContextActionService. F whacks with the glove, L locks
-- the base, U opens upgrades, R rebirths, B opens the Prize Book.
local function bindKey(name, key, fn)
	ContextActionService:BindAction(name, function(_, inputState, _)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		fn()
		return Enum.ContextActionResult.Sink
	end, false, key)
end

bindKey("LockBase", Enum.KeyCode.L, function()
	PlayerAction:FireServer("Lock")
end)
bindKey("WhackBrainrot", Enum.KeyCode.F, activateGlove)
bindKey("ToggleUpgrades", Enum.KeyCode.U, function()
	upgradesPanel.Visible = not upgradesPanel.Visible
end)
bindKey("Rebirth", Enum.KeyCode.R, function()
	PlayerAction:FireServer("Rebirth")
end)
bindKey("ToggleIndex", Enum.KeyCode.B, function()
	indexPanel.Visible = not indexPanel.Visible
end)

--------------------------------------------------------------------------------
-- Everything the server sends
--------------------------------------------------------------------------------

local function showStatus(text)
	statusLabel.Text = text
	task.delay(4, function()
		if statusLabel.Text == text then
			statusLabel.Text = ""
		end
	end)
end

local function formatClock(seconds)
	local minutes = math.floor(seconds / 60)
	local rest = math.floor(seconds % 60)
	if rest < 10 then
		return minutes .. ":0" .. rest
	end
	return minutes .. ":" .. rest
end

GameEvent.OnClientEvent:Connect(function(payload)
	if payload.type == "Hud" then
		cashLabel.Text = BrainrotData.formatMoney(payload.cash)
		incomeLabel.Text = "+" .. BrainrotData.formatMoney(payload.income) .. "/s"
		rebirthLabel.Text = "REBIRTH " .. payload.stars .. "  ·  x" .. payload.multiplier .. " MULT"

		if payload.stormActive then
			eventBanner.BackgroundColor3 = Color3.fromRGB(60, 160, 70)
			eventBanner.Text = "👻 POLTERGEIST STORM! EVERY BRAINROT IS MUTATED  " .. payload.stormLeft .. "s"
		elseif payload.stormIn <= 15 then
			eventBanner.BackgroundColor3 = Color3.fromRGB(160, 110, 20)
			eventBanner.Text = "⚠️ POLTERGEIST STORM IN " .. payload.stormIn .. "s — GET TO YOUR BASE!"
		else
			eventBanner.BackgroundColor3 = Color3.fromRGB(35, 25, 60)
			eventBanner.Text = "NEXT POLTERGEIST STORM " .. formatClock(payload.stormIn)
		end

		burglarBanner.Visible = payload.burglarActive

		if payload.carrying ~= "" then
			carryLabel.Visible = true
			carryLabel.Text = "CARRYING: " .. payload.carrying .. "  —  RUN TO YOUR BASE!"
		else
			carryLabel.Visible = false
		end

		local doneCount = 0
		for _, quest in ipairs(payload.quests) do
			local row = questRows[quest.id]
			if row ~= nil then
				if quest.done then
					doneCount += 1
					row.Text = "✓ " .. quest.name .. "  " .. quest.progress .. "/" .. quest.target .. "  +$" .. quest.reward
					row.TextColor3 = Color3.fromRGB(140, 255, 140)
				else
					row.Text = quest.name .. "  " .. quest.progress .. "/" .. quest.target .. "  +$" .. quest.reward
					row.TextColor3 = Color3.fromRGB(230, 220, 255)
				end
			end
		end
		questHeader.Text = "QUESTS  " .. doneCount .. "/11 done"

		slotsLabel.Text = "SLOTS " .. payload.slotsUsed .. "/" .. payload.slotsTotal
		indexLabel.Text = "INDEX " .. payload.indexCount .. "/36"
		indexButton.Text = "📖 INDEX [B]\n" .. payload.indexCount .. "/36 found"
		indexHeader.Text = "📖 PRIZE BOOK — " .. payload.indexCount .. "/36 found"
		refreshIndexPanel(payload.indexIds)

		if payload.hasSpeedBoots then
			bootsButton.Text = "🥾 Speed Boots\nOWNED"
		end
		if payload.hasGoldenGlove then
			gloveButton.Text = "🧤 Golden Glove\nOWNED"
		end
		local ownedUpgrades = 0
		if payload.hasSpeedBoots then
			ownedUpgrades += 1
		end
		if payload.hasGoldenGlove then
			ownedUpgrades += 1
		end
		upgradesButton.Text = "⬆️ UPGRADES [U]\n" .. ownedUpgrades .. "/2 bought"

	elseif payload.type == "Notify" then
		showStatus(payload.text)

	elseif payload.type == "PrizeBook" then
		pushFeedLine(payload.text)

	elseif payload.type == "StormStart" then
		eventBanner.BackgroundColor3 = Color3.fromRGB(60, 160, 70)
		eventBanner.Text = "👻 POLTERGEIST STORM! EVERY BRAINROT IS MUTATED  " .. payload.duration .. "s"

	elseif payload.type == "StormEnd" then
		eventBanner.BackgroundColor3 = Color3.fromRGB(35, 25, 60)

	elseif payload.type == "Burglar" then
		burglarBanner.Visible = payload.active
	end
end)
