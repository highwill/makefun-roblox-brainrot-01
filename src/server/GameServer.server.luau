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
local burglar = { model = nil, phase = "Idle", stolenModel = nil }

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

local function getWalkSpeedFor(player)
	local state = playerState[player]
	if state == nil then
		return BrainrotData.BASE_WALK_SPEED
	end
	if state.hasSpeedBoots then
		return BrainrotData.SPEED_BOOTS_WALK_SPEED
	end
	return BrainrotData.BASE_WALK_SPEED
end

local function refreshWalkSpeed(player)
	local humanoid = getHumanoid(player)
	if humanoid ~= nil then
		humanoid.WalkSpeed = getWalkSpeedFor(player)
	end
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
	if bestRank >= BrainrotData.getRarityRank("Mythic") then
		addQuestProgress(player, "own-mythic", 1)
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
	GameEvent:FireAllClients({
		type = "PrizeBook",
		text = "PRIZE BOOK: new entry " .. model.Name .. " (" .. foundCount .. "/36)",
	})
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
local function spawnConveyorBrainrot(forceMutation)
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

	task.spawn(function()
		local elapsed = 0
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

-- Whacking the Ghost Burglar: his loot goes back to its owner, the whacker gets
-- quest credit, and the burglar vanishes in a puff of indignation.
local function whackBurglar(player)
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
			whackBurglar(player)
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
	local thiefHumanoid = getHumanoid(nearestThief)
	if thiefRoot ~= nil then
		local away = (thiefRoot.Position - slapperRoot.Position).Unit
		away = Vector3.new(away.X, 0, away.Z).Unit
		thiefRoot.CFrame = thiefRoot.CFrame + away * BrainrotData.SLAP_KNOCKBACK
	end
	if thiefHumanoid ~= nil then
		thiefHumanoid.WalkSpeed = 0
		task.delay(BrainrotData.SLAP_STUN_TIME, function()
			if thiefHumanoid.Parent ~= nil then
				thiefHumanoid.WalkSpeed = getWalkSpeedFor(nearestThief)
			end
		end)
	end

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
	local humanoid = getHumanoid(player)
	if humanoid ~= nil then
		humanoid.WalkSpeed = BrainrotData.STORM_SLOW_SPEED
		task.delay(BrainrotData.STORM_SLOW_TIME, function()
			if humanoid.Parent ~= nil then
				humanoid.WalkSpeed = getWalkSpeedFor(player)
			end
		end)
	end
	local lost = math.floor(state.cash * BrainrotData.STORM_CASH_LOSS)
	state.cash -= lost
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats ~= nil then
		leaderstats.Cash.Value = state.cash
	end
	sendNotify(player, "The storm caught you outside! -$" .. lost .. " and slowed!")
end

-- The Poltergeist stomps down the plaza from the Manor Gate to the Crypt Gate,
-- bobbing with every step, while the fog wall sweeps behind him.
local function bossStompAcrossPlaza()
	local boss = BrainrotFactory.buildStormBossModel()
	local spawnPoint = Workspace:WaitForChild("BossSpawn")
	boss.Parent = Workspace
	boss:PivotTo(CFrame.new(spawnPoint.Position + Vector3.new(0, 6, 0)))

	task.spawn(function()
		local elapsed = 0
		while elapsed < BrainrotData.STORM_DURATION do
			if boss.Parent == nil then
				return
			end
			if stormActive then
				elapsed += 0.1
				local t = elapsed / BrainrotData.STORM_DURATION
				local z = -105 + 225 * t
				local stomp = math.abs(math.sin(t * math.pi * 10)) * 1.5
				boss:PivotTo(CFrame.new(0, 6 + stomp, z))
			end
			task.wait(0.1)
		end
		if boss.Parent ~= nil then
			boss:Destroy()
		end
	end)
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
	bossStompAcrossPlaza()

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
		local ok, message = bases:tryLock(state.base)
		sendNotify(player, message)
		if ok then
			state.lockCount += 1
			addQuestProgress(player, "lock-3", 1)
		end

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
		carrying = nil,
		base = base,
		quests = { progress = {}, done = {} },
		indexFound = {},
		punishedThisStorm = false,
		lockCount = 0,
	}

	if base == nil then
		sendNotify(player, "All six bases are taken — hang around until a plot frees up!")
	else
		sendNotify(player, "Welcome to Haunted Brainrot Manor! Your base is Base " .. base.index .. ". Touch a brainrot on the haunted hallway to buy it!")
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
