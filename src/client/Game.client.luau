-- Haunted Brainrot Manor: the HUD and the player's buttons.
-- One LocalScript, one job: drawing the interface and forwarding the player's
-- choices to the server. It never decides anything about money, ownership or
-- the storm; it only shows what the server tells it and asks for what the
-- player clicks. Every keybind goes through ContextActionService, so the game
-- never fights Roblox's own input handling.
--
-- Layout, fixed zones so nothing piles up (scale-based, so it holds at any
-- viewport from a small Studio window up to 1920x1080):
--   top-center bar, inset below Roblox's own top bar and clear of the chat
--   window (left) and the leaderboard (right): row 1 title + cash + $/s,
--   row 2 rebirth + multiplier + slots in ONE label, one line
--   one event banner under the top bar (storm / boss HP / burglar / ghosts),
--   fully opaque, text scaled to fit
--   one objective line under the banner: the next thing to do
--   left: quests, scrollable, collapsible; right: Prize Book, scrollable,
--   collapsible — both sized in scale with min/max clamps, so no row clips
--   bottom: status, goal tracker, then the 5 verb buttons, one row
--   the backpack UI is off: the Slap Glove's name never prints over the
--   buttons (the tool still works when equipped)
-- Brainrot name tags are distance-culled: the 4 nearest within 25 studs get a
-- full label, further ones get a small rarity dot, beyond 60 studs nothing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

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

-- The backpack UI (hotbar + equipped-tool name) stays off: the "Slap Glove"
-- label used to print over the button row. The glove still works when
-- equipped; only its name tag and hotbar slot are hidden.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local function makeCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

-- Top bar, centred, inset below Roblox's own top bar (y=48) and clear of
-- the chat window (left) and the leaderboard (right). Row 1 is the title,
-- cash and income; row 2 is rebirth, multiplier and slots in ONE label, so
-- the stats can never jumble. Width is scale-based, text is scaled to fit.
local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.AnchorPoint = Vector2.new(0.5, 0)
topBar.Position = UDim2.new(0.5, 0, 0, 48)
topBar.Size = UDim2.new(0.38, 0, 0, 54)
topBar.BackgroundColor3 = Color3.fromRGB(20, 14, 35)
topBar.BackgroundTransparency = 0
topBar.BorderSizePixel = 0
topBar.Parent = gui
makeCorner(topBar, 10)

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Position = UDim2.new(0, 8, 0, 0)
titleLabel.Size = UDim2.new(0.40, -8, 0, 30)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "👻 BRAINROT MANOR"
titleLabel.TextColor3 = Color3.fromRGB(200, 170, 255)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 14
titleLabel.TextScaled = true
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = topBar
local titleSizeCap = Instance.new("UITextSizeConstraint")
titleSizeCap.MaxTextSize = 14
titleSizeCap.Parent = titleLabel

local cashLabel = Instance.new("TextLabel")
cashLabel.Name = "Cash"
cashLabel.Position = UDim2.new(0.40, 0, 0, 0)
cashLabel.Size = UDim2.new(0.32, 0, 0, 30)
cashLabel.BackgroundTransparency = 1
cashLabel.Text = "$100"
cashLabel.TextColor3 = Color3.fromRGB(140, 255, 140)
cashLabel.Font = Enum.Font.GothamBold
cashLabel.TextSize = 22
cashLabel.TextScaled = true
cashLabel.Parent = topBar
local cashSizeCap = Instance.new("UITextSizeConstraint")
cashSizeCap.MaxTextSize = 22
cashSizeCap.Parent = cashLabel

local incomeLabel = Instance.new("TextLabel")
incomeLabel.Name = "Income"
incomeLabel.Position = UDim2.new(0.72, 0, 0, 0)
incomeLabel.Size = UDim2.new(0.28, -8, 0, 30)
incomeLabel.BackgroundTransparency = 1
incomeLabel.Text = "+$0/s"
incomeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
incomeLabel.Font = Enum.Font.GothamBold
incomeLabel.TextSize = 17
incomeLabel.TextScaled = true
incomeLabel.TextXAlignment = Enum.TextXAlignment.Right
incomeLabel.Parent = topBar
local incomeSizeCap = Instance.new("UITextSizeConstraint")
incomeSizeCap.MaxTextSize = 17
incomeSizeCap.Parent = incomeLabel

-- Row 2: rebirth, multiplier and slots in one label on one line. Two labels
-- on two lines in a 34px corner panel is what made the stats jumble.
local statsLabel = Instance.new("TextLabel")
statsLabel.Name = "Stats"
statsLabel.Position = UDim2.new(0, 0, 0, 30)
statsLabel.Size = UDim2.new(1, 0, 0, 24)
statsLabel.BackgroundTransparency = 1
statsLabel.Text = "REBIRTH 0  ·  x1 MULT  ·  SLOTS 0/8"
statsLabel.TextColor3 = Color3.fromRGB(200, 170, 255)
statsLabel.Font = Enum.Font.GothamBold
statsLabel.TextSize = 13
statsLabel.TextScaled = true
statsLabel.Parent = topBar
local statsSizeCap = Instance.new("UITextSizeConstraint")
statsSizeCap.MaxTextSize = 13
statsSizeCap.Parent = statsLabel

-- No separate top-right panel: the leaderboard lives in that corner, and
-- the stats now ride row 2 of the top bar (statsLabel above).

-- The one event banner: storm countdown, live storm, Boss HP, burglar alert,
-- or ghosts loose. Exactly one of them, never two stacked.
local eventBanner = Instance.new("Frame")
eventBanner.Name = "EventBanner"
eventBanner.AnchorPoint = Vector2.new(0.5, 0)
eventBanner.Position = UDim2.new(0.5, 0, 0, 110)
eventBanner.Size = UDim2.new(0.52, 0, 0, 40)
eventBanner.BackgroundColor3 = Color3.fromRGB(35, 25, 60)
eventBanner.BackgroundTransparency = 0
eventBanner.BorderSizePixel = 0
eventBanner.Parent = gui
makeCorner(eventBanner, 10)

local eventBannerText = Instance.new("TextLabel")
eventBannerText.Name = "Text"
eventBannerText.Position = UDim2.new(0, 0, 0, 0)
eventBannerText.Size = UDim2.new(1, 0, 1, -10)
eventBannerText.BackgroundTransparency = 1
eventBannerText.Text = "NEXT POLTERGEIST STORM 2:30"
eventBannerText.TextColor3 = Color3.fromRGB(220, 210, 255)
eventBannerText.Font = Enum.Font.GothamBold
eventBannerText.TextSize = 19
eventBannerText.TextScaled = true
eventBannerText.Parent = eventBanner
local bannerSizeCap = Instance.new("UITextSizeConstraint")
bannerSizeCap.MaxTextSize = 19
bannerSizeCap.Parent = eventBannerText

local bossBarBack = Instance.new("Frame")
bossBarBack.Name = "BossBarBack"
bossBarBack.Position = UDim2.new(0, 8, 1, -12)
bossBarBack.Size = UDim2.new(1, -16, 0, 8)
bossBarBack.BackgroundColor3 = Color3.fromRGB(40, 10, 15)
bossBarBack.BorderSizePixel = 0
bossBarBack.Visible = false
bossBarBack.Parent = eventBanner

local bossBarFill = Instance.new("Frame")
bossBarFill.Name = "BossBarFill"
bossBarFill.Size = UDim2.new(1, 0, 1, 0)
bossBarFill.BackgroundColor3 = Color3.fromRGB(90, 230, 90)
bossBarFill.BorderSizePixel = 0
bossBarFill.Parent = bossBarBack

-- Objective line: the one thing to do next. One line, under the banner.
local objectiveLabel = Instance.new("TextLabel")
objectiveLabel.Name = "Objective"
objectiveLabel.AnchorPoint = Vector2.new(0.5, 0)
objectiveLabel.Position = UDim2.new(0.5, 0, 0, 154)
objectiveLabel.Size = UDim2.new(0.56, 0, 0, 18)
objectiveLabel.BackgroundTransparency = 1
objectiveLabel.Text = ""
objectiveLabel.TextColor3 = Color3.fromRGB(180, 255, 180)
objectiveLabel.Font = Enum.Font.GothamBold
objectiveLabel.TextSize = 14
objectiveLabel.TextScaled = true
objectiveLabel.Parent = gui
local objectiveSizeCap = Instance.new("UITextSizeConstraint")
objectiveSizeCap.MaxTextSize = 14
objectiveSizeCap.Parent = objectiveLabel

-- Quest panel, left side: 3 rows visible, the rest scrolls. Collapsible.
local questPanel = Instance.new("Frame")
questPanel.Name = "QuestPanel"
questPanel.Position = UDim2.new(0, 12, 0, 180)
questPanel.Size = UDim2.new(0, 300, 0.30, 0)
questPanel.BackgroundColor3 = Color3.fromRGB(20, 14, 35)
questPanel.BackgroundTransparency = 0.15
questPanel.BorderSizePixel = 0
questPanel.Parent = gui
makeCorner(questPanel, 12)
local questSizeCap = Instance.new("UISizeConstraint")
questSizeCap.MinSize = Vector2.new(300, 120)
questSizeCap.MaxSize = Vector2.new(300, 200)
questSizeCap.Parent = questPanel

local questHeader = Instance.new("TextButton")
questHeader.Name = "Header"
questHeader.Size = UDim2.new(1, 0, 0, 30)
questHeader.BackgroundTransparency = 1
questHeader.Text = "QUESTS  0/11"
questHeader.TextColor3 = Color3.fromRGB(255, 210, 90)
questHeader.Font = Enum.Font.GothamBold
questHeader.TextSize = 16
questHeader.Parent = questPanel

local questScroll = Instance.new("ScrollingFrame")
questScroll.Name = "List"
questScroll.Position = UDim2.new(0, 0, 0, 32)
questScroll.Size = UDim2.new(1, 0, 1, -34)
questScroll.BackgroundTransparency = 1
questScroll.BorderSizePixel = 0
questScroll.ScrollBarThickness = 5
questScroll.CanvasSize = UDim2.new(0, 0, 0, #BrainrotData.QUESTS * 26)
questScroll.Parent = questPanel

local questRows = {}
for i, quest in ipairs(BrainrotData.QUESTS) do
	local row = Instance.new("TextLabel")
	row.Name = "Quest_" .. quest.id
	row.Position = UDim2.new(0, 10, 0, (i - 1) * 26)
	row.Size = UDim2.new(1, -20, 0, 24)
	row.BackgroundTransparency = 1
	row.Text = quest.name
	row.TextColor3 = Color3.fromRGB(230, 220, 255)
	row.Font = Enum.Font.Gotham
	row.TextSize = 13
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.Parent = questScroll
	questRows[quest.id] = row
end

local questsCollapsed = false
questHeader.MouseButton1Click:Connect(function()
	questsCollapsed = not questsCollapsed
	if questsCollapsed then
		questPanel.Size = UDim2.fromOffset(300, 32)
		questScroll.Visible = false
	else
		questPanel.Size = UDim2.new(0, 300, 0.30, 0)
		questScroll.Visible = true
	end
end)

-- Prize Book panel, right side: progress bar + one row per rarity set.
-- Collapsible.
local bookPanel = Instance.new("Frame")
bookPanel.Name = "PrizeBookPanel"
bookPanel.AnchorPoint = Vector2.new(1, 0)
bookPanel.Position = UDim2.new(1, -12, 0, 180)
bookPanel.Size = UDim2.new(0, 300, 0.30, 0)
bookPanel.BackgroundColor3 = Color3.fromRGB(20, 14, 35)
bookPanel.BackgroundTransparency = 0.15
bookPanel.BorderSizePixel = 0
bookPanel.Parent = gui
makeCorner(bookPanel, 12)
local bookSizeCap = Instance.new("UISizeConstraint")
bookSizeCap.MinSize = Vector2.new(300, 150)
bookSizeCap.MaxSize = Vector2.new(300, 240)
bookSizeCap.Parent = bookPanel

local bookHeader = Instance.new("TextButton")
bookHeader.Name = "Header"
bookHeader.Size = UDim2.new(1, 0, 0, 30)
bookHeader.BackgroundTransparency = 1
bookHeader.Text = "📖 PRIZE BOOK  0/36"
bookHeader.TextColor3 = Color3.fromRGB(255, 210, 90)
bookHeader.Font = Enum.Font.GothamBold
bookHeader.TextSize = 16
bookHeader.Parent = bookPanel

local bookBarBack = Instance.new("Frame")
bookBarBack.Name = "BarBack"
bookBarBack.Position = UDim2.new(0, 10, 0, 34)
bookBarBack.Size = UDim2.new(1, -20, 0, 12)
bookBarBack.BackgroundColor3 = Color3.fromRGB(40, 30, 60)
bookBarBack.BorderSizePixel = 0
bookBarBack.Parent = bookPanel

local bookBarFill = Instance.new("Frame")
bookBarFill.Name = "BarFill"
bookBarFill.Size = UDim2.new(0, 0, 1, 0)
bookBarFill.BackgroundColor3 = Color3.fromRGB(140, 255, 140)
bookBarFill.BorderSizePixel = 0
bookBarFill.Parent = bookBarBack

-- The rarity rows ride a ScrollingFrame, so the 8th row can never be cut
-- off at the panel's bottom edge, however short the viewport is.
local bookScroll = Instance.new("ScrollingFrame")
bookScroll.Name = "Sets"
bookScroll.Position = UDim2.new(0, 0, 0, 50)
bookScroll.Size = UDim2.new(1, 0, 1, -56)
bookScroll.BackgroundTransparency = 1
bookScroll.BorderSizePixel = 0
bookScroll.ScrollBarThickness = 5
bookScroll.CanvasSize = UDim2.new(0, 0, 0, #BrainrotData.RARITY_ORDER * 19)
bookScroll.Parent = bookPanel

local setRows = {}
for i, rarity in ipairs(BrainrotData.RARITY_ORDER) do
	local row = Instance.new("TextLabel")
	row.Name = "Set_" .. rarity
	row.Position = UDim2.new(0, 10, 0, (i - 1) * 19)
	row.Size = UDim2.new(1, -20, 0, 18)
	row.BackgroundTransparency = 1
	row.Text = rarity .. "  0/" .. BrainrotData.getRarityTotal(rarity)
	row.TextColor3 = BrainrotData.RARITY_COLORS[rarity]
	row.Font = Enum.Font.Gotham
	row.TextSize = 13
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.Parent = bookScroll
	setRows[rarity] = row
end

local bookCollapsed = false
bookHeader.MouseButton1Click:Connect(function()
	bookCollapsed = not bookCollapsed
	if bookCollapsed then
		bookPanel.Size = UDim2.fromOffset(300, 32)
		bookBarBack.Visible = false
		bookScroll.Visible = false
	else
		bookPanel.Size = UDim2.new(0, 300, 0.30, 0)
		bookBarBack.Visible = true
		bookScroll.Visible = true
	end
end)

-- Goal tracker, bottom-center: the point of the game, one line.
local goalTracker = Instance.new("TextLabel")
goalTracker.Name = "GoalTracker"
goalTracker.AnchorPoint = Vector2.new(0.5, 1)
goalTracker.Position = UDim2.new(0.5, 0, 1, -80)
goalTracker.Size = UDim2.new(0.60, 0, 0, 20)
goalTracker.BackgroundTransparency = 1
goalTracker.Text = "GOAL: Prize Book 0/36 · Boss in 2:30 · Vault: LOCKED"
goalTracker.TextColor3 = Color3.fromRGB(255, 210, 90)
goalTracker.Font = Enum.Font.GothamBold
goalTracker.TextSize = 15
goalTracker.TextScaled = true
goalTracker.Parent = gui
local goalSizeCap = Instance.new("UITextSizeConstraint")
goalSizeCap.MaxTextSize = 15
goalSizeCap.Parent = goalTracker

-- Carrying banner, just above the goal tracker.
local carryLabel = Instance.new("TextLabel")
carryLabel.Name = "CarryHint"
carryLabel.AnchorPoint = Vector2.new(0.5, 1)
carryLabel.Position = UDim2.new(0.5, 0, 1, -116)
carryLabel.Size = UDim2.new(0.44, 0, 0, 36)
carryLabel.BackgroundColor3 = Color3.fromRGB(200, 110, 20)
carryLabel.BackgroundTransparency = 0.1
carryLabel.BorderSizePixel = 0
carryLabel.Text = ""
carryLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
carryLabel.Font = Enum.Font.GothamBold
carryLabel.TextSize = 18
carryLabel.TextScaled = true
carryLabel.Visible = false
carryLabel.Parent = gui
makeCorner(carryLabel, 10)
local carrySizeCap = Instance.new("UITextSizeConstraint")
carrySizeCap.MaxTextSize = 18
carrySizeCap.Parent = carryLabel

-- Status line for server replies ("Base locked for 60s", "Not enough cash"...).
local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.AnchorPoint = Vector2.new(0.5, 1)
statusLabel.Position = UDim2.new(0.5, 0, 1, -158)
statusLabel.Size = UDim2.new(0.24, 0, 0, 40)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = ""
statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextSize = 15
statusLabel.TextWrapped = true
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.TextStrokeTransparency = 0.4
statusLabel.Parent = gui

-- Bottom buttons: LOCK / WHACK / UPGRADES / REBIRTH / INDEX, with keybinds.
-- One row, one line of text each.
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
local rebirthButton = makeButton("RebirthButton", "⭐ REBIRTH [R]", Color3.fromRGB(160, 80, 220))
local indexButton = makeButton("IndexButton", "📖 INDEX [B]", Color3.fromRGB(60, 170, 90))

-- Upgrades panel, hidden until UPGRADES is pressed: the two real upgrades.
-- Narrow and stacked (180 wide) so it fits in the gap between the side
-- panels instead of overlapping them.
local upgradesPanel = Instance.new("Frame")
upgradesPanel.Name = "UpgradesPanel"
upgradesPanel.AnchorPoint = Vector2.new(0.5, 1)
upgradesPanel.Position = UDim2.new(0.5, 0, 1, -196)
upgradesPanel.Size = UDim2.fromOffset(180, 112)
upgradesPanel.BackgroundColor3 = Color3.fromRGB(20, 14, 35)
upgradesPanel.BackgroundTransparency = 0.1
upgradesPanel.BorderSizePixel = 0
upgradesPanel.Visible = false
upgradesPanel.Parent = gui
makeCorner(upgradesPanel, 10)

local bootsButton = Instance.new("TextButton")
bootsButton.Name = "BootsButton"
bootsButton.Position = UDim2.new(0, 10, 0, 8)
bootsButton.Size = UDim2.fromOffset(160, 44)
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
gloveButton.Position = UDim2.new(0, 10, 0, 60)
gloveButton.Size = UDim2.fromOffset(160, 44)
gloveButton.BackgroundColor3 = Color3.fromRGB(200, 150, 40)
gloveButton.BorderSizePixel = 0
gloveButton.Text = "🧤 Golden Glove\n$2,500"
gloveButton.TextColor3 = Color3.fromRGB(255, 255, 255)
gloveButton.Font = Enum.Font.GothamBold
gloveButton.TextSize = 15
gloveButton.TextWrapped = true
gloveButton.Parent = upgradesPanel
makeCorner(gloveButton, 8)

-- Index panel, hidden until INDEX is pressed: the reward rules on top, then
-- all 36 brainrots, found ones lit.
local indexPanel = Instance.new("Frame")
indexPanel.Name = "IndexPanel"
indexPanel.AnchorPoint = Vector2.new(0.5, 0.5)
indexPanel.Position = UDim2.fromScale(0.5, 0.5)
indexPanel.Size = UDim2.new(0.45, 0, 0.72, 0)
indexPanel.BackgroundColor3 = Color3.fromRGB(20, 14, 35)
indexPanel.BackgroundTransparency = 0.05
indexPanel.BorderSizePixel = 0
indexPanel.Visible = false
indexPanel.Parent = gui
makeCorner(indexPanel, 12)
local indexSizeCap = Instance.new("UISizeConstraint")
indexSizeCap.MinSize = Vector2.new(380, 320)
indexSizeCap.MaxSize = Vector2.new(540, 500)
indexSizeCap.Parent = indexPanel

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

local rulesLabel = Instance.new("TextLabel")
rulesLabel.Name = "RewardRules"
rulesLabel.Position = UDim2.new(0, 10, 0, 40)
rulesLabel.Size = UDim2.new(1, -20, 0, 92)
rulesLabel.BackgroundTransparency = 1
rulesLabel.Text = table.concat(BrainrotData.REWARD_RULES, "\n")
rulesLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
rulesLabel.Font = Enum.Font.Gotham
rulesLabel.TextSize = 13
rulesLabel.TextXAlignment = Enum.TextXAlignment.Left
rulesLabel.TextYAlignment = Enum.TextYAlignment.Top
rulesLabel.TextWrapped = true
rulesLabel.Parent = indexPanel

local indexScroll = Instance.new("ScrollingFrame")
indexScroll.Name = "List"
indexScroll.Position = UDim2.new(0, 10, 0, 138)
indexScroll.Size = UDim2.new(1, -20, 1, -148)
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
-- Brainrot name-tag culling: the 4 nearest within 25 studs get the full
-- label (staggered vertically so they never stack); further ones get a small
-- rarity dot; beyond 60 studs, nothing. This is what stops the screen
-- looking like a wall of ads.
--------------------------------------------------------------------------------

local function refreshBrainrotTags()
	local character = player.Character
	if character == nil then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil then
		return
	end
	local nearby = {}
	for _, folderName in ipairs({ "ConveyorBrainrots", "PlacedBrainrots" }) do
		local folder = Workspace:FindFirstChild(folderName)
		if folder ~= nil then
			for _, model in ipairs(folder:GetChildren()) do
				if model:IsA("Model") then
					local tag = model:FindFirstChild("NameTag")
					if tag ~= nil then
						local distance = (model:GetPivot().Position - root.Position).Magnitude
						table.insert(nearby, {
							tag = tag,
							dot = model:FindFirstChild("DotTag"),
							distance = distance,
						})
					end
				end
			end
		end
	end
	table.sort(nearby, function(a, b)
		return a.distance < b.distance
	end)
	for i, entry in ipairs(nearby) do
		if i <= 4 and entry.distance <= 25 then
			entry.tag.Enabled = true
			entry.tag.ExtentsOffsetWorldSpace = Vector3.new(0, 6.5 + (i - 1) * 1.6, 0)
			if entry.dot ~= nil then
				entry.dot.Enabled = false
			end
		elseif entry.distance <= 60 then
			entry.tag.Enabled = false
			if entry.dot ~= nil then
				entry.dot.Enabled = true
			end
		else
			entry.tag.Enabled = false
			if entry.dot ~= nil then
				entry.dot.Enabled = false
			end
		end
	end
end

task.spawn(function()
	while true do
		refreshBrainrotTags()
		task.wait(0.25)
	end
end)

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
		statsLabel.Text = "REBIRTH " .. payload.stars .. "  ·  x" .. payload.multiplier .. " MULT  ·  SLOTS " .. payload.slotsUsed .. "/" .. payload.slotsTotal

		-- The one event banner, by priority: Boss HP, burglar, storm, ghosts,
		-- storm warning, countdown. Never two at once.
		bossBarBack.Visible = false
		if payload.bossActive then
			eventBanner.BackgroundColor3 = Color3.fromRGB(120, 20, 60)
			eventBannerText.Text = "👻 POLTERGEIST BOSS — WHACK IT! [F]  " .. payload.bossHp .. "/" .. payload.bossMaxHp .. " HP"
			bossBarBack.Visible = true
			local frac = payload.bossHp / math.max(payload.bossMaxHp, 1)
			bossBarFill.Size = UDim2.new(frac, 0, 1, 0)
			if frac > 0.5 then
				bossBarFill.BackgroundColor3 = Color3.fromRGB(90, 230, 90)
			elseif frac > 0.25 then
				bossBarFill.BackgroundColor3 = Color3.fromRGB(255, 190, 60)
			else
				bossBarFill.BackgroundColor3 = Color3.fromRGB(255, 70, 60)
			end
		elseif payload.burglarActive then
			eventBanner.BackgroundColor3 = Color3.fromRGB(150, 30, 40)
			eventBannerText.Text = "🚨 THE GHOST BURGLAR IS IN THE MANOR! WHACK HIM! [F]"
		elseif payload.stormActive then
			if payload.bossDefeated then
				eventBanner.BackgroundColor3 = Color3.fromRGB(60, 160, 70)
				eventBannerText.Text = "👻 BOSS DEFEATED! The storm ends in " .. payload.stormLeft .. "s"
			else
				eventBanner.BackgroundColor3 = Color3.fromRGB(60, 160, 70)
				eventBannerText.Text = "👻 POLTERGEIST STORM! EVERY BRAINROT IS MUTATED  " .. payload.stormLeft .. "s"
			end
		elseif payload.ghostsActive > 0 and payload.stormIn > 30 then
			eventBanner.BackgroundColor3 = Color3.fromRGB(60, 120, 60)
			eventBannerText.Text = "👻 " .. payload.ghostsActive .. " HAUNTED GHOSTS LOOSE — WHACK THEM! [F]"
		elseif payload.stormIn <= 15 then
			eventBanner.BackgroundColor3 = Color3.fromRGB(160, 110, 20)
			eventBannerText.Text = "⚠️ POLTERGEIST STORM IN " .. payload.stormIn .. "s — GET TO YOUR BASE!"
		else
			eventBanner.BackgroundColor3 = Color3.fromRGB(35, 25, 60)
			eventBannerText.Text = "NEXT POLTERGEIST STORM " .. formatClock(payload.stormIn)
		end

		objectiveLabel.Text = payload.objectiveText or ""
		goalTracker.Text = payload.goalLine or ""

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
		if payload.ghostsActive > 0 then
			questHeader.Text = "QUESTS  " .. doneCount .. "/" .. #payload.quests .. "  ·  👻 " .. payload.ghostsActive .. " GHOSTS"
		else
			questHeader.Text = "QUESTS  " .. doneCount .. "/" .. #payload.quests .. "  ·  GHOSTS IN " .. formatClock(payload.nextGhostIn)
		end

		bookHeader.Text = "📖 PRIZE BOOK  " .. payload.indexCount .. "/36"
		bookBarFill.Size = UDim2.new(payload.indexCount / 36, 0, 1, 0)
		for _, setInfo in ipairs(payload.setProgress) do
			local row = setRows[setInfo.rarity]
			if row ~= nil then
				if setInfo.paid then
					row.Text = "✓ " .. setInfo.rarity .. "  " .. setInfo.found .. "/" .. setInfo.total .. "  ·  +$" .. setInfo.bonus .. " PAID"
					row.TextColor3 = Color3.fromRGB(140, 255, 140)
				elseif setInfo.found >= setInfo.total then
					row.Text = setInfo.rarity .. "  " .. setInfo.found .. "/" .. setInfo.total .. "  ·  +$" .. setInfo.bonus
					row.TextColor3 = BrainrotData.RARITY_COLORS[setInfo.rarity]
				else
					row.Text = setInfo.rarity .. "  " .. setInfo.found .. "/" .. setInfo.total .. "  ·  +$" .. setInfo.bonus
					local dim = BrainrotData.RARITY_COLORS[setInfo.rarity]
					row.TextColor3 = Color3.new(dim.R * 0.55, dim.G * 0.55, dim.B * 0.55)
				end
			end
		end

		indexHeader.Text = "📖 PRIZE BOOK — " .. payload.indexCount .. "/36 found"
		refreshIndexPanel(payload.indexIds)

		if payload.hasSpeedBoots then
			bootsButton.Text = "🥾 Speed Boots\nOWNED"
		end
		if payload.hasGoldenGlove then
			gloveButton.Text = "🧤 Golden Glove\nOWNED"
		end

	elseif payload.type == "Notify" then
		showStatus(payload.text)

	elseif payload.type == "PrizeBook" then
		showStatus(payload.text)

	elseif payload.type == "StormStart" then
		eventBanner.BackgroundColor3 = Color3.fromRGB(60, 160, 70)
		eventBannerText.Text = "👻 POLTERGEIST STORM! EVERY BRAINROT IS MUTATED  " .. payload.duration .. "s"

	elseif payload.type == "StormEnd" then
		eventBanner.BackgroundColor3 = Color3.fromRGB(35, 25, 60)

	elseif payload.type == "Burglar" then
		-- The burglar alert rides the single event banner via the Hud payload.

	elseif payload.type == "Boss" then
		-- The Boss HP bar rides the single event banner via the Hud payload.
	end
end)
