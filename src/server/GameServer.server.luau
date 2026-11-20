-- Haunted Brainrot Manor: the whole game loop, server-authoritative.
-- One script, one place for state: playerState holds every player's cash, income
-- progress, quests, index, upgrades and what they are carrying. Everything else
-- -- the cast, the model factory, the base plots -- lives in the modules this
-- script requires. The client only draws the HUD and asks for actions; the
-- server decides.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BrainrotData = require(ReplicatedStorage.Shared.BrainrotData)
local BrainrotFactory = require(ReplicatedStorage.Shared.BrainrotFactory)
local BaseManager = require(script.Parent.BaseManager)

local GameEvent = ReplicatedStorage:WaitForChild("GameEvent")
local PlayerAction = ReplicatedStorage:WaitForChild("PlayerAction")

local bases = BaseManager.new(Workspace)

-- The one place state lives: [player] = { cash, totalEarned, multiplier, stars,
-- hasSpeedBoots, hasGoldenGlove, slapReadyAt, carrying, base, quests, indexFound,
-- punishedThisStorm, lockCount }.
local playerState = {}
local stormActive = false
local stormLeft = 0
local nextStormIn = BrainrotData.STORM_INTERVAL

-- The Ghost Burglar's own little state machine: Idle, Roaming, Fleeing.
local burglar = { model = nil, phase = "Idle", stolenModel = nil, hp = 0 }

-- The Poltergeist Boss: alive only during a storm, in the manor facade arena.
local boss = { model = nil, hp = 0, maxHp = 0, defeated = false }

-- Haunted Ghosts loose in the manor: { model, hp, lastStealAt = {} }.
local ghosts = {}
local nextGhostIn = BrainrotData.GHOST_INTERVAL_MIN

-- Forward declarations: the whack handler below calls these, and they are
-- defined in their own sections further down the file.
local damageGhost
local damageBoss

local conveyorFolder = Instance.new("Folder")
conveyorFolder.Name = "ConveyorBrainrots"
conveyorFolder.Parent = Workspace

local placedFolder = Instance.new("Folder")
placedFolder.Name = "PlacedBrainrots"
placedFolder.Parent = Workspace

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

local function sendNotify(player, text)
	GameEvent:FireClient(player, { type = "Notify", text = text })
end

local function broadcastNotify(text)
	for player, _ in pairs(playerState) do
		sendNotify(player, text)
	end
end

-- Pays cash into a player's pocket and keeps leaderstats in sync.
local function payCash(player, amount)
	local state = playerState[player]
	if state == nil then
		return
	end
	state.cash += amount
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats ~= nil then
		leaderstats.Cash.Value = state.cash
	end
end

-- A floating damage number: "-1" or "+$250" that rises and fades above a hit.
local function spawnDamageNumber(position, text, color)
	local anchor = Instance.new("Part")
	anchor.Name = "DamageAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.5, 0.5, 0.5)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = Workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DamageNumber"
	billboard.Size = UDim2.fromOffset(120, 30)
	billboard.ExtentsOffsetWorldSpace = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = anchor
	billboard.Parent = Workspace

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextStrokeTransparency = 0.2
	label.Parent = billboard

	task.spawn(function()
		for step = 1, 10 do
			if anchor.Parent == nil then
				return
			end
			anchor.CFrame += Vector3.new(0, 0.35, 0)
			label.TextTransparency = step / 10
			task.wait(0.07)
		end
		billboard:Destroy()
		anchor:Destroy()
	end)
end

local function getHumanoid(player)
	local character = player.Character
	if character == nil then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local function getRootPart(player)
	local character = player.Character
	if character == nil then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

-- True when a world position is inside one of the haunted fog zones.
local function isInFogZone(position)
	for _, zone in ipairs(BrainrotData.FOG_ZONES) do
		if position.X >= zone.minX and position.X <= zone.maxX
			and position.Z >= zone.minZ and position.Z <= zone.maxZ then
			return true
		end
	end
	return false
end

-- One place decides WalkSpeed, recomputed often so the storm slow, the fog
-- slow, the whack stun and the Speed Boots never fight each other. Stun beats
-- everything, then the storm slow, then the fog, then the boots.
local function updateWalkSpeed(player)
	local state = playerState[player]
	local humanoid = getHumanoid(player)
	if humanoid == nil then
		return
	end
	local now = os.clock()
	if state ~= nil and now < (state.stunnedUntil or 0) then
		humanoid.WalkSpeed = 0
		return
	end
	if state ~= nil and now < (state.stormSlowedUntil or 0) then
		humanoid.WalkSpeed = BrainrotData.STORM_SLOW_SPEED
		return
	end
	local root = getRootPart(player)
	if root ~= nil and isInFogZone(root.Position) then
		humanoid.WalkSpeed = BrainrotData.FOG_SLOW_SPEED
		return
	end
	if state ~= nil and state.hasSpeedBoots then
		humanoid.WalkSpeed = BrainrotData.SPEED_BOOTS_WALK_SPEED
		return
	end
	humanoid.WalkSpeed = BrainrotData.BASE_WALK_SPEED
end

local function refreshWalkSpeed(player)
	updateWalkSpeed(player)
end

-- Income per second from everything standing on the player's base, times their
-- rebirth multiplier.
local function calculateIncomePerSecond(player)
	local state = playerState[player]
	if state == nil or state.base == nil then
		return 0
	end
	local total = 0
	for _, model in ipairs(bases:getPlacedModels(state.base)) do
		total += model:GetAttribute("Rate") or 0
	end
	return total * state.multiplier
end

local function countPlacedBrainrots(player)
	local state = playerState[player]
	if state == nil or state.base == nil then
		return 0
	end
	return #bases:getPlacedModels(state.base)
end

--------------------------------------------------------------------------------
-- Quests and the Prize Book (index)
--------------------------------------------------------------------------------

-- Adds progress to a quest. Completing one pays the reward straight into cash.
local function addQuestProgress(player, questId, amount)
	local state = playerState[player]
	if state == nil then
		return
	end
	local quest = BrainrotData.getQuestById(questId)
	if quest == nil or state.quests.done[questId] then
		return
	end
	local progress = (state.quests.progress[questId] or 0) + amount
	state.quests.progress[questId] = math.min(progress, quest.target)
	if state.quests.progress[questId] >= quest.target then
		state.quests.done[questId] = true
		state.cash += quest.reward
		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats ~= nil then
			leaderstats.Cash.Value = state.cash
		end
		sendNotify(player, "QUEST DONE: " .. quest.name .. "  +$" .. quest.reward .. "!")
	end
end

-- Sets an absolute quest value (for "collect $100,000 total", which tracks a
-- running total rather than counting events).
local function setQuestProgress(player, questId, value)
	local state = playerState[player]
	if state == nil then
		return
	end
	local quest = BrainrotData.getQuestById(questId)
	if quest == nil or state.quests.done[questId] then
		return
	end
	state.quests.progress[questId] = math.min(value, quest.target)
	if state.quests.progress[questId] >= quest.target then
		state.quests.done[questId] = true
		state.cash += quest.reward
		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats ~= nil then
			leaderstats.Cash.Value = state.cash
		end
		sendNotify(player, "QUEST DONE: " .. quest.name .. "  +$" .. quest.reward .. "!")
	end
end

-- State-based quests, checked after every buy, claim and money tick: owning a
-- Legendary or better, owning a Mythic or better, and filling all 8 slots.
local function checkStateQuests(player)
	local state = playerState[player]
	if state == nil or state.base == nil then
		return
	end
	local bestRank = 0
	for _, model in ipairs(bases:getPlacedModels(state.base)) do
		local rank = BrainrotData.getRarityRank(model:GetAttribute("Rarity"))
		if rank > bestRank then
			bestRank = rank
		end
	end
	if bestRank >= BrainrotData.getRarityRank("Legendary") then
		addQuestProgress(player, "own-legendary", 1)
	end
	if countPlacedBrainrots(player) >= BrainrotData.SLOTS_PER_BASE then
		addQuestProgress(player, "full-base", 1)
	end
end

-- The Prize Book: every brainrot a player has ever owned, counted once. A new
-- entry is announced to the whole server, like the top games do.
local function recordIndexEntry(player, model)
	local state = playerState[player]
	if state == nil then
		return
	end
	local brainrotId = model:GetAttribute("BrainrotId")
	if brainrotId == nil or state.indexFound[brainrotId] then
		return
	end
	state.indexFound[brainrotId] = true
	local foundCount = 0
	for _ in pairs(state.indexFound) do
		foundCount += 1
	end

	-- Prize Book set bonus: owning every brainrot of one rarity pays once.
	local newDef = nil
	for _, castDef in ipairs(BrainrotData.CAST) do
		if castDef.id == brainrotId then
			newDef = castDef
			break
		end
	end
	if newDef ~= nil and not state.setBonuses[newDef.rarity] then
		local foundOfRarity = 0
		for _, castDef in ipairs(BrainrotData.CAST) do
			if castDef.rarity == newDef.rarity and state.indexFound[castDef.id] then
				foundOfRarity += 1
			end
		end
		if foundOfRarity >= BrainrotData.getRarityTotal(newDef.rarity) then
			state.setBonuses[newDef.rarity] = true
			local bonus = BrainrotData.SET_BONUSES[newDef.rarity] or 0
			state.cash += bonus
			local leaderstats = player:FindFirstChild("leaderstats")
			if leaderstats ~= nil then
				leaderstats.Cash.Value = state.cash
			end
			sendNotify(player, "SET COMPLETE: every " .. newDef.rarity .. " brainrot!  +$" .. bonus .. "!")
		end
	end

	GameEvent:FireAllClients({
		type = "PrizeBook",
		text = "PRIZE BOOK: new entry " .. model.Name .. " (" .. foundCount .. "/36)",
	})
end

--------------------------------------------------------------------------------
-- Goal, objective, set progress
--------------------------------------------------------------------------------

local function formatClock(seconds)
	local minutes = math.floor(seconds / 60)
	local rest = math.floor(seconds % 60)
	if rest < 10 then
		return minutes .. ":0" .. rest
	end
	return minutes .. ":" .. rest
end

-- The goal line: one line that always tells the player what the game is
-- about right now. It replaces the old feature strip.
local function computeGoalLine(player, indexCount)
	local state = playerState[player]
	local vaultText = "Vault: LOCKED"
	if state ~= nil and state.vaultUnlocked then
		vaultText = "Vault: OPEN"
	end
	if boss.model ~= nil then
		return "GOAL: Prize Book " .. indexCount .. "/36  ·  BOSS " .. boss.hp .. "/" .. boss.maxHp .. " HP  ·  " .. vaultText
	end
	return "GOAL: Prize Book " .. indexCount .. "/36  ·  Boss in " .. formatClock(nextStormIn) .. "  ·  " .. vaultText
end

-- The current objective step: the one thing the player should do next. It
-- changes as they progress, so the game always has a point from second one.
local function computeObjectiveText(player, indexCount, slotsUsed)
	local state = playerState[player]
	if state == nil then
		return "Buy a brainrot — touch one on the conveyor or press E"
	end
	if indexCount == 0 then
		return "First: buy a brainrot — walk up to the conveyor and press E"
	end
	if slotsUsed < 3 then
		return "Fill your base — buy brainrots off the conveyor"
	end
	if state.stars == 0 then
		return "Earn $100K total, then REBIRTH [R] for x2 income"
	end
	if not state.vaultUnlocked then
		return "Open the Vault — Rebirth 1 or $50K cash (Boss drops help!)"
	end
	return "Vault open! Complete the Prize Book — " .. indexCount .. "/36"
end

-- Per-rarity set progress for the Prize Book panel: found, total, bonus, paid.
local function buildSetProgress(player)
	local state = playerState[player]
	local sets = {}
	for _, rarity in ipairs(BrainrotData.RARITY_ORDER) do
		local found = 0
		if state ~= nil then
			for _, castDef in ipairs(BrainrotData.CAST) do
				if castDef.rarity == rarity and state.indexFound[castDef.id] then
					found += 1
				end
			end
		end
		table.insert(sets, {
			rarity = rarity,
			found = found,
			total = BrainrotData.getRarityTotal(rarity),
			bonus = BrainrotData.SET_BONUSES[rarity] or 0,
			paid = state ~= nil and state.setBonuses[rarity] == true,
		})
	end
	return sets
end

--------------------------------------------------------------------------------
-- HUD payload
--------------------------------------------------------------------------------

-- The HUD payload: cash, income, storm timing, quests, index, slots, burglar.
local function sendHudUpdate(player)
	local state = playerState[player]
	if state == nil then
		return
	end
	local carryingName = ""
	if state.carrying ~= nil and state.carrying.Parent ~= nil then
		carryingName = state.carrying.Name
	end
	local questStates = {}
	for _, quest in ipairs(BrainrotData.QUESTS) do
		table.insert(questStates, {
			id = quest.id,
			name = quest.name,
			target = quest.target,
			reward = quest.reward,
			progress = state.quests.progress[quest.id] or 0,
			done = state.quests.done[quest.id] == true,
		})
	end
	local indexIds = {}
	local indexCount = 0
	for brainrotId in pairs(state.indexFound) do
		table.insert(indexIds, brainrotId)
		indexCount += 1
	end
	local goalLine = computeGoalLine(player, indexCount)
	local objectiveText = computeObjectiveText(player, indexCount, countPlacedBrainrots(player))
	local ghostsActive = 0
	for _, ghost in ipairs(ghosts) do
		if ghost.model ~= nil and ghost.model.Parent ~= nil then
			ghostsActive += 1
		end
	end
	GameEvent:FireClient(player, {
		type = "Hud",
		cash = state.cash,
		totalEarned = state.totalEarned,
		income = calculateIncomePerSecond(player),
		multiplier = state.multiplier,
		stars = state.stars,
		stormActive = stormActive,
		stormLeft = stormLeft,
		stormIn = nextStormIn,
		carrying = carryingName,
		hasSpeedBoots = state.hasSpeedBoots,
		hasGoldenGlove = state.hasGoldenGlove,
		quests = questStates,
		indexCount = indexCount,
		indexIds = indexIds,
		slotsUsed = countPlacedBrainrots(player),
		slotsTotal = BrainrotData.SLOTS_PER_BASE,
		burglarActive = burglar.model ~= nil,
		goalLine = goalLine,
		objectiveText = objectiveText,
		bossActive = boss.model ~= nil,
		bossHp = boss.hp,
		bossMaxHp = boss.maxHp,
		bossDefeated = boss.defeated,
		vaultUnlocked = state.vaultUnlocked == true,
		nextGhostIn = nextGhostIn,
		ghostsActive = ghostsActive,
		setProgress = buildSetProgress(player),
	})
end

--------------------------------------------------------------------------------
-- Brainrots on the conveyor
--------------------------------------------------------------------------------

-- One touch handler per brainrot. On the lane it is a buy; on someone else's
-- base it is a steal. The model's State attribute decides which.
local function attachTouchHandler(model)
	local body = model.PrimaryPart
	local debounce = false
	body.Touched:Connect(function(hit)
		if debounce then
			return
		end
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if player == nil then
			return
		end
		local state = playerState[player]
		if state == nil then
			return
		end
		debounce = true
		task.delay(0.4, function()
			debounce = false
		end)

		local brainrotState = model:GetAttribute("State")
		if brainrotState == "Conveyor" then
			tryBuyBrainrot(player, model)
		elseif brainrotState == "Owned" then
			tryPickUpStolenBrainrot(player, model)
		end
	end)
end

-- Spawns one brainrot at the Manor Gate and walks it down the haunted hallway
-- to the Crypt Gate. forceMutation (storm spawns) guarantees a mutation and
-- lets the walk run through the storm; normal brainrots freeze while the storm
-- rages, because the conveyor pauses.
local function spawnConveyorBrainrot(forceMutation, startElapsed)
	local def = BrainrotData.pickBrainrotDef()
	local mutation = nil
	if forceMutation then
		mutation = BrainrotData.rollForcedMutation()
	else
		mutation = BrainrotData.rollMutation()
	end
	local model = BrainrotFactory.buildBrainrotModel(def, mutation)
	model.Parent = conveyorFolder
	model:PivotTo(CFrame.new(0, BrainrotData.CONVEYOR_HEIGHT, BrainrotData.CONVEYOR_START_Z))
	attachTouchHandler(model)

	-- The buy prompt: press E near a brainrot on the lane to buy it. Touch
	-- still works too; the prompt is what makes the buy readable.
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Buy"
	prompt.ObjectText = model.Name .. " — $" .. model:GetAttribute("Price")
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = model.PrimaryPart
	prompt.Triggered:Connect(function(promptPlayer)
		tryBuyBrainrot(promptPlayer, model)
	end)

	task.spawn(function()
		local elapsed = startElapsed or 0
		while elapsed < BrainrotData.CONVEYOR_TIME do
			if model.Parent == nil then
				return -- bought, stolen or destroyed; the walk is over
			end
			if not stormActive or forceMutation then
				elapsed += 0.1
				local t = elapsed / BrainrotData.CONVEYOR_TIME
				local z = BrainrotData.CONVEYOR_START_Z
					+ (BrainrotData.CONVEYOR_END_Z - BrainrotData.CONVEYOR_START_Z) * t
				local bob = math.sin(t * math.pi * 6) * 0.25
				model:PivotTo(CFrame.new(0, BrainrotData.CONVEYOR_HEIGHT + bob, z))
			end
			task.wait(0.1)
		end
		-- Reached the Crypt Gate unsold: despawn.
		if model.Parent ~= nil and model:GetAttribute("State") == "Conveyor" then
			model:Destroy()
		end
	end)
end

-- Pre-fill the lane so the first view is alive from second zero: two
-- brainrots already partway down the hallway when the server starts.
spawnConveyorBrainrot(false, 8)
spawnConveyorBrainrot(false, 17)

-- The conveyor loop: one new brainrot every SPAWN_INTERVAL seconds, paused
-- while the storm sweeps the grounds.
task.spawn(function()
	while true do
		if not stormActive then
			spawnConveyorBrainrot(false)
		end
		task.wait(BrainrotData.SPAWN_INTERVAL)
	end
end)

-- Flies a bought brainrot from the lane to its slot over about a second.
local function flyModelToSlot(model, targetPosition)
	local startCFrame = model:GetPivot()
	local targetCFrame = CFrame.new(targetPosition)
	local steps = 10
	for step = 1, steps do
		if model.Parent == nil then
			return
		end
		local t = step / steps
		local eased = 1 - (1 - t) * (1 - t) -- ease out, fast then settling
		model:PivotTo(startCFrame:Lerp(targetCFrame, eased))
		task.wait(0.08)
	end
end

-- Flips a brainrot's name tag from conveyor mode (with the BUY price) to base
-- mode (just the earn rate).
local function setTagToBaseMode(model)
	BrainrotFactory.setTagText(
		model,
		model.Name,
		{ rarity = model:GetAttribute("Rarity") },
		model:GetAttribute("Rate"),
		model:GetAttribute("Price"),
		false
	)
end

-- Touch-to-buy: cash out, the brainrot flies to the player's first free slot and
-- starts earning. Every check happens here, on the server, never on the client.
function tryBuyBrainrot(player, model)
	local state = playerState[player]
	if state == nil or state.base == nil then
		return
	end
	local price = model:GetAttribute("Price")
	if state.cash < price then
		sendNotify(player, "Not enough cash! " .. model.Name .. " costs $" .. price)
		return
	end
	local slotIndex = bases:getFreeSlotIndex(state.base)
	if slotIndex == nil then
		sendNotify(player, "Your base is full! Rebirth to make room.")
		return
	end

	state.cash -= price
	local prompt = model.PrimaryPart:FindFirstChildOfClass("ProximityPrompt")
	if prompt ~= nil then
		prompt:Destroy()
	end
	model:SetAttribute("State", "Owned")
	model:SetAttribute("OwnerUserId", player.UserId)
	model.Parent = placedFolder
	bases:placeModel(state.base, model, slotIndex)
	setTagToBaseMode(model)
	recordIndexEntry(player, model)
	addQuestProgress(player, "grab-5", 1)
	addQuestProgress(player, "grab-15", 1)
	checkStateQuests(player)
	sendNotify(player, "Bought " .. model.Name .. " for $" .. price .. "!")

	local slotPosition = bases:getSlotPosition(state.base, slotIndex)
	task.spawn(flyModelToSlot, model, slotPosition)
	sendHudUpdate(player)
end

--------------------------------------------------------------------------------
-- Stealing, carrying, whacking
--------------------------------------------------------------------------------

-- Touching a brainrot on ANOTHER player's base picks it up: it rides above the
-- thief's head until they reach their own base pad. A locked base cannot be
-- stolen from, and a player can only carry one brainrot at a time.
function tryPickUpStolenBrainrot(player, model)
	local state = playerState[player]
	if state == nil or state.base == nil then
		return
	end
	if state.carrying ~= nil then
		return -- already carrying one; one theft at a time
	end
	local ownerUserId = model:GetAttribute("OwnerUserId")
	if ownerUserId == player.UserId then
		return -- it is already yours
	end
	local owner = Players:GetPlayerByUserId(ownerUserId)
	local ownerBase = bases:getBaseOf(owner)
	if ownerBase == nil then
		return
	end
	if bases:isLocked(ownerBase) then
		sendNotify(player, "That base is LOCKED — you cannot steal from it!")
		return
	end

	bases:removeModel(ownerBase, model)
	model:SetAttribute("State", "Carried")
	model:SetAttribute("CarrierUserId", player.UserId)
	state.carrying = model
	sendNotify(player, "You stole " .. model.Name .. "! Run it to your base!")
	if owner ~= nil then
		sendNotify(owner, player.DisplayName .. " stole your " .. model.Name .. "! Whack them!")
	end
	sendHudUpdate(player)
end

-- Carried brainrots hover above the carrier's head, updated every frame.
RunService.Heartbeat:Connect(function()
	for player, state in pairs(playerState) do
		updateWalkSpeed(player)
		local model = state.carrying
		if model ~= nil then
			local root = getRootPart(player)
			if model.Parent == nil or root == nil then
				state.carrying = nil
			else
				model:PivotTo(CFrame.new(root.Position + Vector3.new(0, BrainrotData.CARRY_HEIGHT, 0)))
			end
		end
	end
end)

-- A thief who reaches their own base pad claims the stolen brainrot: it takes
-- the first free slot and starts earning for its new owner.
local function claimCarriedBrainrot(player)
	local state = playerState[player]
	if state == nil or state.base == nil or state.carrying == nil then
		return
	end
	local model = state.carrying
	if model.Parent == nil then
		state.carrying = nil
		return
	end
	local slotIndex = bases:getFreeSlotIndex(state.base)
	if slotIndex == nil then
		sendNotify(player, "Your base is full — no room for the stolen brainrot!")
		return
	end
	model:SetAttribute("State", "Owned")
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("CarrierUserId", 0)
	model.Parent = placedFolder
	bases:placeModel(state.base, model, slotIndex)
	state.carrying = nil
	setTagToBaseMode(model)
	recordIndexEntry(player, model)
	addQuestProgress(player, "steal-1", 1)
	checkStateQuests(player)
	sendNotify(player, "Claimed " .. model.Name .. " — it earns for you now!")
	local slotPosition = bases:getSlotPosition(state.base, slotIndex)
	task.spawn(flyModelToSlot, model, slotPosition)
	sendHudUpdate(player)
end

-- Every base pad listens for a carrier walking in with a stolen brainrot.
for _, base in ipairs(bases.bases) do
	base.pad.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if player == nil then
			return
		end
		local state = playerState[player]
		if state == nil or state.base ~= base or state.carrying == nil then
			return
		end
		claimCarriedBrainrot(player)
	end)
end

-- Sends a stolen brainrot back to its owner's first free slot. Used when the
-- thief is whacked, dies, or leaves. Returns false when there is nowhere to put
-- it, and the model is destroyed instead.
local function returnBrainrotToOwner(model)
	local owner = Players:GetPlayerByUserId(model:GetAttribute("OwnerUserId"))
	local ownerBase = bases:getBaseOf(owner)
	if ownerBase == nil then
		model:Destroy()
		return false
	end
	local slotIndex = bases:getFreeSlotIndex(ownerBase)
	if slotIndex == nil then
		model:Destroy()
		return false
	end
	model:SetAttribute("State", "Owned")
	model:SetAttribute("CarrierUserId", 0)
	model.Parent = placedFolder
	bases:placeModel(ownerBase, model, slotIndex)
	setTagToBaseMode(model)
	task.spawn(flyModelToSlot, model, bases:getSlotPosition(ownerBase, slotIndex))
	return true
end

-- Walks a model from where it is to a target position over a duration, bobbing
-- with every step. Carries an optional second model above its head (the
-- burglar's loot). Returns false when the model vanished mid-walk.
local function walkModelTo(model, targetPosition, duration, carriedModel)
	if model.Parent == nil then
		return false
	end
	local startPosition = model:GetPivot().Position
	local elapsed = 0
	while elapsed < duration do
		if model.Parent == nil then
			return false
		end
		elapsed += 0.1
		local t = math.min(elapsed / duration, 1)
		local position = startPosition:Lerp(targetPosition, t)
		local bob = math.abs(math.sin(t * math.pi * 8)) * 0.5
		model:PivotTo(CFrame.new(position + Vector3.new(0, bob, 0)))
		if carriedModel ~= nil and carriedModel.Parent ~= nil then
			carriedModel:PivotTo(CFrame.new(position + Vector3.new(0, 7, 0)))
		end
		task.wait(0.1)
	end
	return true
end

-- Forward: damageBurglar (below) calls whackBurglar (after it).
local whackBurglar

-- A whack lands on the Ghost Burglar: one damage off his three HP. At zero he
-- drops the loot and the defender gets a cash bonus.
local function damageBurglar(player)
	if burglar.model == nil then
		return
	end
	burglar.hp -= 1
	local model = burglar.model
	if model.Parent == nil then
		return
	end
	model:SetAttribute("HP", burglar.hp)
	BrainrotFactory.setHealthBar(model, burglar.hp, BrainrotData.BURGLAR_HP)
	spawnDamageNumber(model:GetPivot().Position + Vector3.new(0, 6, 0), "-1", Color3.fromRGB(255, 220, 100))
	if burglar.hp > 0 then
		sendNotify(player, "You hit the Burglar! " .. burglar.hp .. "/" .. BrainrotData.BURGLAR_HP .. " HP left!")
		return
	end
	payCash(player, BrainrotData.BURGLAR_DEFEND_BONUS)
	sendNotify(player, "Burglar defeated! Defender bonus +$" .. BrainrotData.BURGLAR_DEFEND_BONUS)
	whackBurglar(player)
end

-- Whacking the Ghost Burglar: his loot goes back to its owner, the whacker gets
-- quest credit, and the burglar vanishes in a puff of indignation.
whackBurglar = function(player)
	addQuestProgress(player, "whack-1", 1)
	if burglar.stolenModel ~= nil then
		local stolen = burglar.stolenModel
		burglar.stolenModel = nil
		local owner = Players:GetPlayerByUserId(stolen:GetAttribute("OwnerUserId"))
		returnBrainrotToOwner(stolen)
		if owner ~= nil then
			sendNotify(owner, player.DisplayName .. " whacked the burglar — your " .. stolen.Name .. " is back!")
		end
	end
	broadcastNotify(player.DisplayName .. " WHACKED the Ghost Burglar!")
	if burglar.model ~= nil then
		burglar.model:Destroy()
	end
	burglar.model = nil
	burglar.phase = "Idle"
	GameEvent:FireAllClients({ type = "Burglar", active = false })
	for otherPlayer, _ in pairs(playerState) do
		sendHudUpdate(otherPlayer)
	end
end

-- The Slap Glove, now a whacking glove: the nearest thief in range drops what
-- they are carrying, gets thrown backwards and stands stunned for three
-- seconds. The Ghost Burglar takes priority over player thieves. The Golden
-- Glove upgrade cuts the cooldown from five seconds to two.
local function slapThief(player)
	local state = playerState[player]
	if state == nil then
		return
	end
	local now = os.clock()
	if now < state.slapReadyAt then
		return
	end
	local cooldown = BrainrotData.SLAP_COOLDOWN
	if state.hasGoldenGlove then
		cooldown = BrainrotData.SLAP_COOLDOWN_GLOVE
	end
	state.slapReadyAt = now + cooldown

	local slapperRoot = getRootPart(player)
	if slapperRoot == nil then
		return
	end

	-- The burglar first: he is the bigger prize.
	if burglar.model ~= nil and burglar.model.Parent ~= nil then
		local burglarDistance = (burglar.model:GetPivot().Position - slapperRoot.Position).Magnitude
		if burglarDistance <= BrainrotData.SLAP_RANGE then
			damageBurglar(player)
			return
		end
	end

	-- Haunted Ghosts next: the closest one in range takes the hit.
	local nearestGhost = nil
	local nearestGhostDistance = BrainrotData.SLAP_RANGE
	for _, ghost in ipairs(ghosts) do
		if ghost.model ~= nil and ghost.model.Parent ~= nil then
			local ghostDistance = (ghost.model:GetPivot().Position - slapperRoot.Position).Magnitude
			if ghostDistance <= nearestGhostDistance then
				nearestGhost = ghost
				nearestGhostDistance = ghostDistance
			end
		end
	end
	if nearestGhost ~= nil then
		damageGhost(player, nearestGhost)
		return
	end

	-- Then the Poltergeist Boss, when he is up in the arena.
	if boss.model ~= nil and boss.model.Parent ~= nil then
		local bossDistance = (boss.model:GetPivot().Position - slapperRoot.Position).Magnitude
		if bossDistance <= BrainrotData.SLAP_RANGE then
			damageBoss(player)
			return
		end
	end

	local nearestThief = nil
	local nearestDistance = BrainrotData.SLAP_RANGE
	for otherPlayer, otherState in pairs(playerState) do
		if otherPlayer ~= player and otherState.carrying ~= nil then
			local thiefRoot = getRootPart(otherPlayer)
			if thiefRoot ~= nil then
				local distance = (thiefRoot.Position - slapperRoot.Position).Magnitude
				if distance <= nearestDistance then
					nearestThief = otherPlayer
					nearestDistance = distance
				end
			end
		end
	end
	if nearestThief == nil then
		return
	end

	local thiefState = playerState[nearestThief]
	local stolen = thiefState.carrying
	thiefState.carrying = nil
	returnBrainrotToOwner(stolen)

	local thiefRoot = getRootPart(nearestThief)
	if thiefRoot ~= nil then
		local away = (thiefRoot.Position - slapperRoot.Position).Unit
		away = Vector3.new(away.X, 0, away.Z).Unit
		thiefRoot.CFrame = thiefRoot.CFrame + away * BrainrotData.SLAP_KNOCKBACK
	end
	thiefState.stunnedUntil = os.clock() + BrainrotData.SLAP_STUN_TIME
	updateWalkSpeed(nearestThief)

	sendNotify(player, "WHACK! " .. nearestThief.DisplayName .. " dropped " .. stolen.Name .. "!")
	sendNotify(nearestThief, player.DisplayName .. " whacked you! Your stolen brainrot went home!")
end

-- Builds the Slap Glove tool and hands it to a character. Called on spawn and
-- respawn, so the glove is never lost for long.
local function giveSlapGlove(player)
	local character = player.Character
	if character == nil then
		return
	end
	if character:FindFirstChild("Slap Glove") ~= nil or player.Backpack:FindFirstChild("Slap Glove") ~= nil then
		return
	end
	local tool = Instance.new("Tool")
	tool.Name = "Slap Glove"
	tool.RequiresHandle = true
	tool.ToolTip = "Whack a thief (or the Ghost Burglar) to make them drop what they stole — or press F"

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1.5, 0.5, 2.5)
	handle.Color = Color3.fromRGB(255, 220, 130)
	handle.Material = Enum.Material.SmoothPlastic
	handle.Parent = tool

	tool.Activated:Connect(function()
		slapThief(player)
	end)
	tool.Parent = player.Backpack
end

--------------------------------------------------------------------------------
-- The Ghost Burglar
--------------------------------------------------------------------------------

-- Picks a random occupied base with brainrots on it, preferring unlocked ones.
local function pickBurglarTargetBase()
	local candidates = {}
	for _, base in ipairs(bases.bases) do
		if base.owner ~= nil and #bases:getPlacedModels(base) > 0 and not bases:isLocked(base) then
			table.insert(candidates, base)
		end
	end
	if #candidates == 0 then
		return nil
	end
	return candidates[math.random(1, #candidates)]
end

-- One burglar visit: he appears at the manor door, walks to a random unlocked
-- base, grabs its best brainrot, and runs for the exit. A locked base sends him
-- looking elsewhere. If nobody whacks him, the loot is gone for good.
local function runBurglarVisit()
	local model = BrainrotFactory.buildBurglarModel()
	local spawnPoint = Workspace:WaitForChild("BurglarSpawn")
	model.Parent = Workspace
	model:PivotTo(CFrame.new(spawnPoint.Position + Vector3.new(0, 2.5, 0)))
	burglar.model = model
	burglar.phase = "Roaming"
	burglar.stolenModel = nil
	burglar.hp = BrainrotData.BURGLAR_HP
	GameEvent:FireAllClients({ type = "Burglar", active = true })
	broadcastNotify("👻 THE GHOST BURGLAR IS IN THE MANOR! Whack him! [F]")
	for player, _ in pairs(playerState) do
		sendHudUpdate(player)
	end

	local visitStart = os.clock()
	local targetBase = pickBurglarTargetBase()
	if targetBase == nil then
		-- Nothing worth stealing: he wanders off after a look around.
		task.wait(8)
	else
		-- Walk to the base, then check again: it may have locked meanwhile.
		local arrived = walkModelTo(model, targetBase.padCenter + Vector3.new(0, 2.5, 0), BrainrotData.BURGLAR_WALK_TIME)
		if arrived and model.Parent ~= nil then
			if bases:isLocked(targetBase) or #bases:getPlacedModels(targetBase) == 0 then
				targetBase = pickBurglarTargetBase()
				if targetBase ~= nil then
					walkModelTo(model, targetBase.padCenter + Vector3.new(0, 2.5, 0), BrainrotData.BURGLAR_WALK_TIME)
				end
			end
		end

		-- Grab the best brainrot on the base, if there is still one to grab.
		if model.Parent ~= nil and targetBase ~= nil and not bases:isLocked(targetBase) then
			local bestModel = nil
			local bestRate = 0
			for _, placed in ipairs(bases:getPlacedModels(targetBase)) do
				local rate = placed:GetAttribute("Rate") or 0
				if rate > bestRate then
					bestRate = rate
					bestModel = placed
				end
			end
			if bestModel ~= nil then
				bases:removeModel(targetBase, bestModel)
				bestModel:SetAttribute("State", "Carried")
				bestModel:SetAttribute("CarrierUserId", 0)
				burglar.stolenModel = bestModel
				burglar.phase = "Fleeing"
				local owner = targetBase.owner
				if owner ~= nil then
					sendNotify(owner, "👻 The Ghost Burglar stole your " .. bestModel.Name .. "! WHACK HIM! [F]")
				end
			end
		end
	end

	-- Run for the exit. If he is carrying loot and makes it, the loot is gone.
	if model.Parent ~= nil and os.clock() - visitStart < BrainrotData.BURGLAR_VISIT_TIME then
		walkModelTo(model, Vector3.new(0, 2.5, 118), BrainrotData.BURGLAR_FLEE_TIME, burglar.stolenModel)
	end
	if burglar.stolenModel ~= nil and burglar.stolenModel.Parent ~= nil then
		local stolen = burglar.stolenModel
		local owner = Players:GetPlayerByUserId(stolen:GetAttribute("OwnerUserId"))
		stolen:Destroy()
		if owner ~= nil then
			sendNotify(owner, "The Ghost Burglar escaped with your " .. stolen.Name .. "!")
		end
	end
	if model.Parent ~= nil then
		model:Destroy()
	end
	burglar.model = nil
	burglar.stolenModel = nil
	burglar.phase = "Idle"
	GameEvent:FireAllClients({ type = "Burglar", active = false })
	for player, _ in pairs(playerState) do
		sendHudUpdate(player)
	end
end

-- The burglar loop: a visit every BURGLAR_INTERVAL seconds, one at a time.
task.spawn(function()
	while true do
		task.wait(BrainrotData.BURGLAR_INTERVAL)
		if burglar.model == nil then
			runBurglarVisit()
		end
	end
end)

--------------------------------------------------------------------------------
-- Haunted Ghosts
--------------------------------------------------------------------------------

local GHOST_SPAWN_POINTS = {
	Vector3.new(0, 2.5, -100),
	Vector3.new(-120, 2.5, 0),
	Vector3.new(120, 2.5, 0),
	Vector3.new(0, 2.5, 100),
}

-- One ghost: it spawns at a random edge of the plaza and chases the nearest
-- player until whacked. Touch steals cash and knocks the victim back.
local function spawnGhost()
	local model = BrainrotFactory.buildGhostModel()
	local spawnPoint = GHOST_SPAWN_POINTS[math.random(1, #GHOST_SPAWN_POINTS)]
	model.Parent = Workspace
	model:PivotTo(CFrame.new(spawnPoint))
	local ghost = { model = model, hp = BrainrotData.GHOST_HP, lastStealAt = {} }
	table.insert(ghosts, ghost)
	broadcastNotify("A Haunted Ghost is loose in the manor! Whack it! [F]")

	task.spawn(function()
		while model.Parent ~= nil do
			-- Find the nearest player.
			local nearestPlayer = nil
			local nearestDistance = math.huge
			for player, _ in pairs(playerState) do
				local root = getRootPart(player)
				if root ~= nil then
					local distance = (root.Position - model:GetPivot().Position).Magnitude
					if distance < nearestDistance then
						nearestDistance = distance
						nearestPlayer = player
					end
				end
			end
			if nearestPlayer == nil then
				task.wait(0.5)
			else
				local root = getRootPart(nearestPlayer)
				if root == nil then
					task.wait(0.5)
				else
					local position = model:GetPivot().Position
					local direction = root.Position - position
					direction = Vector3.new(direction.X, 0, direction.Z)
					if direction.Magnitude > 2 then
						direction = direction.Unit
						local bob = math.abs(math.sin(os.clock() * 4)) * 0.4
						model:PivotTo(CFrame.new(position + direction * BrainrotData.GHOST_SPEED * 0.1 + Vector3.new(0, bob, 0)))
					end
					-- Touch: steal cash, knock the victim back, then cool down.
					if nearestDistance <= 5 then
						local now = os.clock()
						local lastSteal = ghost.lastStealAt[nearestPlayer] or 0
						if now - lastSteal >= BrainrotData.GHOST_TOUCH_COOLDOWN then
							ghost.lastStealAt[nearestPlayer] = now
							local victimState = playerState[nearestPlayer]
							if victimState ~= nil then
								local stolen = BrainrotData.GHOST_STEAL_FLAT
									+ math.floor(victimState.cash * BrainrotData.GHOST_STEAL_FRAC)
								victimState.cash = math.max(victimState.cash - stolen, 0)
								local leaderstats = nearestPlayer:FindFirstChild("leaderstats")
								if leaderstats ~= nil then
									leaderstats.Cash.Value = victimState.cash
								end
								spawnDamageNumber(root.Position + Vector3.new(0, 4, 0), "-$" .. stolen, Color3.fromRGB(255, 80, 80))
								sendNotify(nearestPlayer, "A ghost stole $" .. stolen .. " from you! Whack it back!")
								local away = root.Position - position
								away = Vector3.new(away.X, 0, away.Z)
								if away.Magnitude > 0.1 then
									root.CFrame += away.Unit * 6
								end
							end
						end
					end
					task.wait(0.1)
				end
			end
		end
	end)
end

-- Removes a ghost from the live list (called on defeat).
local function removeGhost(ghost)
	for i, entry in ipairs(ghosts) do
		if entry == ghost then
			table.remove(ghosts, i)
			return
		end
	end
end

-- A whack lands on a ghost: one damage, a damage number, and at zero HP the
-- ghost pops into cash — and sometimes a mutated brainrot on the lane.
damageGhost = function(player, ghost)
	ghost.hp -= 1
	local model = ghost.model
	if model.Parent == nil then
		return
	end
	model:SetAttribute("HP", ghost.hp)
	BrainrotFactory.setHealthBar(model, ghost.hp, BrainrotData.GHOST_HP)
	spawnDamageNumber(model:GetPivot().Position + Vector3.new(0, 5, 0), "-1", Color3.fromRGB(255, 220, 100))
	if ghost.hp > 0 then
		return
	end
	removeGhost(ghost)
	model:Destroy()
	payCash(player, BrainrotData.GHOST_CASH_DROP)
	sendNotify(player, "Ghost defeated!  +$" .. BrainrotData.GHOST_CASH_DROP)
	local state = playerState[player]
	if state ~= nil then
		state.ghostsDefeated += 1
		addQuestProgress(player, "defeat-ghosts-3", 1)
	end
	if math.random() < BrainrotData.GHOST_MUTATION_DROP_CHANCE then
		spawnConveyorBrainrot(true)
		broadcastNotify("The ghost dropped a MUTATED brainrot on the lane!")
	end
	for otherPlayer, _ in pairs(playerState) do
		sendHudUpdate(otherPlayer)
	end
end

-- Ghosts spawn from the per-second money tick, which counts nextGhostIn down
-- so the HUD can show exactly when the next ghosts arrive.

--------------------------------------------------------------------------------
-- The Manor Vault
--------------------------------------------------------------------------------

-- Opens the vault: the door slides down, the treasure lights up, the opener
-- gets the payout once, and the whole server hears about it.
local function openVault(player)
	local state = playerState[player]
	if state == nil or state.vaultUnlocked then
		return
	end
	state.vaultUnlocked = true
	payCash(player, BrainrotData.VAULT_PAYOUT)
	local door = Workspace:FindFirstChild("VaultDoor")
	if door ~= nil then
		door.Transparency = 0.75
		door.CanCollide = false
		door.CFrame -= Vector3.new(0, 12, 0)
	end
	local sign = Workspace:FindFirstChild("VaultSign")
	if sign ~= nil then
		local gui = sign:FindFirstChild("SignGui")
		if gui ~= nil then
			local label = gui:FindFirstChild("SignLabel")
			if label ~= nil then
				label.Text = "MANOR VAULT — OPEN"
			end
		end
	end
	local treasure = Workspace:FindFirstChild("VaultTreasure")
	if treasure ~= nil then
		for _, part in ipairs(treasure:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Transparency = 0
			end
		end
		local chest = treasure:FindFirstChild("Chest")
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 215, 0)
		light.Brightness = 2
		light.Range = 24
		light.Parent = chest or treasure
	end
	broadcastNotify("🔓 " .. player.DisplayName .. " OPENED THE MANOR VAULT!  +$" .. BrainrotData.VAULT_PAYOUT)
	for otherPlayer, _ in pairs(playerState) do
		sendHudUpdate(otherPlayer)
	end
end

-- Checks the vault condition after anything that changes cash or rebirths.
local function checkVaultUnlock(player)
	local state = playerState[player]
	if state == nil or state.vaultUnlocked then
		return
	end
	if state.stars >= BrainrotData.VAULT_UNLOCK_REBIRTH or state.cash >= BrainrotData.VAULT_UNLOCK_CASH then
		openVault(player)
	end
end

--------------------------------------------------------------------------------
-- Money tick, storm countdown, HUD
--------------------------------------------------------------------------------

-- Every second: every player's brainrots pay out, the storm clock ticks down,
-- and the HUD gets fresh numbers. This is also where a storm starts.
task.spawn(function()
	while true do
		task.wait(BrainrotData.MONEY_TICK)
		for player, state in pairs(playerState) do
			local income = calculateIncomePerSecond(player)
			if income > 0 then
				state.cash += income
				state.totalEarned += income
				local leaderstats = player:FindFirstChild("leaderstats")
				if leaderstats ~= nil then
					leaderstats.Cash.Value = state.cash
				end
			end
			setQuestProgress(player, "collect-100k", state.totalEarned)
			checkVaultUnlock(player)
		end

		if stormActive then
			stormLeft -= BrainrotData.MONEY_TICK
			if stormLeft <= 0 then
				endSnackStorm()
			end
		else
			nextStormIn -= BrainrotData.MONEY_TICK
			if nextStormIn <= 0 then
				startSnackStorm()
			end
		end

		-- Ghosts arrive on a countdown the HUD can show.
		nextGhostIn -= BrainrotData.MONEY_TICK
		if nextGhostIn <= 0 then
			nextGhostIn = math.random(BrainrotData.GHOST_INTERVAL_MIN, BrainrotData.GHOST_INTERVAL_MAX)
			local alive = 0
			for _, ghost in ipairs(ghosts) do
				if ghost.model ~= nil and ghost.model.Parent ~= nil then
					alive += 1
				end
			end
			local playerCount = 0
			for _ in pairs(playerState) do
				playerCount += 1
			end
			if playerCount > 0 and alive < BrainrotData.GHOST_MAX_ALIVE then
				local count = math.random(1, math.min(3, BrainrotData.GHOST_MAX_ALIVE - alive))
				for _ = 1, count do
					spawnGhost()
				end
			end
		end

		for player, _ in pairs(playerState) do
			sendHudUpdate(player)
		end
	end
end)

--------------------------------------------------------------------------------
-- Poltergeist Storm
--------------------------------------------------------------------------------

-- A player caught outside their own base during a storm is slowed for ten
-- seconds and loses five percent of their cash. The base pad is the safe zone.
local function punishPlayerCaughtOutside(player)
	local state = playerState[player]
	if state == nil or state.base == nil then
		return
	end
	local root = getRootPart(player)
	if root == nil then
		return
	end
	if bases:isPointInBase(state.base, root.Position) then
		return -- safe at home
	end
	state.punishedThisStorm = true
	state.stormSlowedUntil = os.clock() + BrainrotData.STORM_SLOW_TIME
	updateWalkSpeed(player)
	local lost = math.floor(state.cash * BrainrotData.STORM_CASH_LOSS)
	state.cash -= lost
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats ~= nil then
		leaderstats.Cash.Value = state.cash
	end
	sendNotify(player, "The storm caught you outside! -$" .. lost .. " and slowed!")
end

-- The Poltergeist Boss, the storm's climax: he spawns in the manor facade
-- arena with HP that scales with the player count, and patrols the arena
-- instead of stomping across the whole plaza.
local function spawnBoss()
	local playerCount = 0
	for _ in pairs(playerState) do
		playerCount += 1
	end
	local model = BrainrotFactory.buildStormBossModel()
	local spawnPoint = Workspace:WaitForChild("BossSpawn")
	model.Parent = Workspace
	model:PivotTo(CFrame.new(spawnPoint.Position + Vector3.new(0, 6, 0)))
	boss.model = model
	boss.maxHp = BrainrotData.BOSS_HP_BASE + BrainrotData.BOSS_HP_PER_PLAYER * math.max(playerCount - 1, 0)
	boss.hp = boss.maxHp
	boss.defeated = false
	model:SetAttribute("HP", boss.hp)
	model:SetAttribute("MaxHP", boss.maxHp)
	BrainrotFactory.setHealthBar(model, boss.hp, boss.maxHp)
	GameEvent:FireAllClients({ type = "Boss", active = true })
	broadcastNotify("👻 THE POLTERGEIST BOSS IS IN THE ARENA! Whack him together! [F]")

	task.spawn(function()
		local direction = 1
		while model.Parent ~= nil and stormActive do
			local position = model:GetPivot().Position
			local nextX = position.X + direction * 0.35
			if nextX > BrainrotData.BOSS_ARENA_HALF_X then
				direction = -1
			elseif nextX < -BrainrotData.BOSS_ARENA_HALF_X then
				direction = 1
			end
			local nextZ = BrainrotData.BOSS_ARENA_MIN_Z + 12 + math.sin(os.clock() * 0.5) * 8
			local bob = math.abs(math.sin(os.clock() * 3)) * 1.2
			model:PivotTo(CFrame.new(nextX, 6 + bob, nextZ))
			task.wait(0.1)
		end
	end)
end

-- A whack lands on the Boss: one damage, quest credit for the hitter, and at
-- zero HP the Boss falls — a guaranteed mutated brainrot, cash for everyone
-- nearby, and the storm's climax pays out.
damageBoss = function(player)
	if boss.model == nil then
		return
	end
	boss.hp -= 1
	local model = boss.model
	if model.Parent == nil then
		return
	end
	model:SetAttribute("HP", boss.hp)
	BrainrotFactory.setHealthBar(model, boss.hp, boss.maxHp)
	spawnDamageNumber(model:GetPivot().Position + Vector3.new(0, 10, 0), "-1", Color3.fromRGB(255, 220, 100))
	local state = playerState[player]
	if state ~= nil then
		state.bossDamage += 1
		addQuestProgress(player, "damage-boss", 1)
	end
	if boss.hp > 0 then
		for otherPlayer, _ in pairs(playerState) do
			sendHudUpdate(otherPlayer)
		end
		return
	end
	boss.defeated = true
	local bossPosition = model:GetPivot().Position
	model:Destroy()
	boss.model = nil
	GameEvent:FireAllClients({ type = "Boss", active = false })
	spawnConveyorBrainrot(true)
	for otherPlayer, _ in pairs(playerState) do
		local root = getRootPart(otherPlayer)
		if root ~= nil and (root.Position - bossPosition).Magnitude <= BrainrotData.BOSS_PAYOUT_RANGE then
			payCash(otherPlayer, BrainrotData.BOSS_PAYOUT)
			sendNotify(otherPlayer, "BOSS DEFEATED!  +$" .. BrainrotData.BOSS_PAYOUT)
		end
	end
	broadcastNotify("👻 THE POLTERGEIST BOSS IS DEFEATED! A mutated brainrot is on the lane!")
	for otherPlayer, _ in pairs(playerState) do
		sendHudUpdate(otherPlayer)
	end
end

-- The fog wall sweeps the grounds from one end to the other over the storm.
local function sweepStormWall()
	local wall = Workspace:WaitForChild("StormWall")
	task.spawn(function()
		local elapsed = 0
		while elapsed < BrainrotData.STORM_DURATION do
			if not stormActive then
				return
			end
			elapsed += 0.1
			local t = elapsed / BrainrotData.STORM_DURATION
			local z = -160 + 320 * t
			wall.CFrame = CFrame.new(0, 20, z)
			task.wait(0.1)
		end
	end)
end

function startSnackStorm()
	stormActive = true
	stormLeft = BrainrotData.STORM_DURATION
	for _, state in pairs(playerState) do
		state.punishedThisStorm = false
	end
	for player, _ in pairs(playerState) do
		GameEvent:FireClient(player, { type = "StormStart", duration = BrainrotData.STORM_DURATION })
		punishPlayerCaughtOutside(player)
	end
	sweepStormWall()
	spawnBoss()

	-- The storm's own gift: mutated brainrots drop onto the lane, one a second.
	-- Every brainrot spawned during a storm is mutated, guaranteed.
	for i = 1, BrainrotData.STORM_SPAWN_COUNT do
		task.delay(i, function()
			if stormActive then
				spawnConveyorBrainrot(true)
			end
		end)
	end

	-- Halfway through, catch anyone who wandered back out of their base.
	task.delay(BrainrotData.STORM_DURATION / 2, function()
		if stormActive then
			for player, _ in pairs(playerState) do
				punishPlayerCaughtOutside(player)
			end
		end
	end)
end

function endSnackStorm()
	stormActive = false
	stormLeft = 0
	nextStormIn = BrainrotData.STORM_INTERVAL
	local wall = Workspace:WaitForChild("StormWall")
	wall.CFrame = CFrame.new(0, 20, -300)
	-- The Boss escapes when the storm ends, unless the players defeated him.
	if boss.model ~= nil then
		if boss.model.Parent ~= nil then
			boss.model:Destroy()
		end
		boss.model = nil
		if not boss.defeated then
			broadcastNotify("The Poltergeist Boss escaped into the fog...")
			GameEvent:FireAllClients({ type = "Boss", active = false })
		end
	end
	for player, state in pairs(playerState) do
		GameEvent:FireClient(player, { type = "StormEnd" })
		sendNotify(player, "The storm passed! The conveyor is running again.")
		-- Surviving a storm at home counts toward the quest.
		if not state.punishedThisStorm then
			addQuestProgress(player, "survive-2", 1)
		end
	end
end

--------------------------------------------------------------------------------
-- Buttons: lock, rebirth, upgrades
--------------------------------------------------------------------------------

local function onPlayerAction(player, action)
	local state = playerState[player]
	if state == nil then
		return
	end

	if action == "Lock" then
		if state.base == nil then
			sendNotify(player, "You have no base to lock yet!")
			return
		end
		local _, message = bases:tryLock(state.base)
		sendNotify(player, message)

	elseif action == "Rebirth" then
		if state.base == nil then
			sendNotify(player, "You have no base — nothing to rebirth from!")
			return
		end
		if state.totalEarned < BrainrotData.REBIRTH_THRESHOLD then
			sendNotify(
				player,
				"Rebirth needs $" .. BrainrotData.REBIRTH_THRESHOLD .. " total earned (you have $"
					.. state.totalEarned .. ")"
			)
			return
		end
		for _, model in ipairs(bases:getPlacedModels(state.base)) do
			model:Destroy()
		end
		state.base.placed = {}
		state.cash = 0
		state.totalEarned = 0
		state.multiplier = math.min(state.multiplier * 2, BrainrotData.REBIRTH_MAX_MULTIPLIER)
		state.stars += 1
		state.base.stars = state.stars
		bases:updateSign(state.base)
		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats ~= nil then
			leaderstats.Cash.Value = 0
			leaderstats.Rebirths.Value = state.stars
		end
		addQuestProgress(player, "rebirth-1", 1)
		checkVaultUnlock(player)
		sendNotify(player, "REBIRTH! Your income is now x" .. state.multiplier .. " forever!")
		sendHudUpdate(player)

	elseif action == "BuySpeedBoots" then
		if state.hasSpeedBoots then
			sendNotify(player, "You already own Speed Boots!")
			return
		end
		if state.cash < BrainrotData.SPEED_BOOTS_PRICE then
			sendNotify(player, "Speed Boots cost $" .. BrainrotData.SPEED_BOOTS_PRICE .. "!")
			return
		end
		state.cash -= BrainrotData.SPEED_BOOTS_PRICE
		state.hasSpeedBoots = true
		refreshWalkSpeed(player)
		sendNotify(player, "Speed Boots equipped! WalkSpeed 24.")
		sendHudUpdate(player)

	elseif action == "BuyGoldenGlove" then
		if state.hasGoldenGlove then
			sendNotify(player, "You already own the Golden Glove!")
			return
		end
		if state.cash < BrainrotData.GOLDEN_GLOVE_PRICE then
			sendNotify(player, "The Golden Glove costs $" .. BrainrotData.GOLDEN_GLOVE_PRICE .. "!")
			return
		end
		state.cash -= BrainrotData.GOLDEN_GLOVE_PRICE
		state.hasGoldenGlove = true
		sendNotify(player, "Golden Glove equipped! Whack cooldown is now 2s.")
		sendHudUpdate(player)
	end
end

PlayerAction.OnServerEvent:Connect(onPlayerAction)

--------------------------------------------------------------------------------
-- Players joining and leaving
--------------------------------------------------------------------------------

local function onPlayerAdded(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local cashValue = Instance.new("IntValue")
	cashValue.Name = "Cash"
	cashValue.Value = BrainrotData.START_CASH
	cashValue.Parent = leaderstats

	local rebirthValue = Instance.new("IntValue")
	rebirthValue.Name = "Rebirths"
	rebirthValue.Value = 0
	rebirthValue.Parent = leaderstats

	local base = bases:assignBase(player)
	playerState[player] = {
		cash = BrainrotData.START_CASH,
		totalEarned = 0,
		multiplier = 1,
		stars = 0,
		hasSpeedBoots = false,
		hasGoldenGlove = false,
		slapReadyAt = 0,
		stunnedUntil = 0,
		stormSlowedUntil = 0,
		carrying = nil,
		base = base,
		quests = { progress = {}, done = {} },
		indexFound = {},
		setBonuses = {},
		ghostsDefeated = 0,
		bossDamage = 0,
		vaultUnlocked = false,
		punishedThisStorm = false,
	}

	if base == nil then
		sendNotify(player, "All six bases are taken — hang around until a plot frees up!")
	else
		sendNotify(player, "Welcome to Haunted Brainrot Manor! GOAL: complete the Prize Book (36) and defeat the Poltergeist Boss to open the Vault. Your base is Base " .. base.index .. " — buy a brainrot on the hallway (touch it or press E)!")
	end

	player.CharacterAdded:Connect(function(character)
		task.wait(0.5)
		refreshWalkSpeed(player)
		giveSlapGlove(player)
		-- Dying drops a stolen brainrot: it goes straight back to its owner's base.
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil then
			humanoid.Died:Connect(function()
				local state = playerState[player]
				if state ~= nil and state.carrying ~= nil then
					local stolen = state.carrying
					state.carrying = nil
					returnBrainrotToOwner(stolen)
					sendNotify(player, "You died and dropped " .. stolen.Name .. " — it went home!")
				end
			end)
		end
	end)
	if player.Character ~= nil then
		task.wait(0.5)
		refreshWalkSpeed(player)
		giveSlapGlove(player)
	end
	sendHudUpdate(player)
end

local function onPlayerRemoving(player)
	local state = playerState[player]
	if state ~= nil and state.carrying ~= nil then
		returnBrainrotToOwner(state.carrying)
	end
	bases:releaseBase(player)
	playerState[player] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
