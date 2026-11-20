-- Brainrot Bazaar -- Snack Sprites: owns the six base plots and everything about them.
-- One module, one job: bases. It knows where the plots are, which slots are free,
-- who owns what, and whether a base is locked. It never touches money, the
-- conveyor or the storm; the GameServer asks it questions and it answers.

local BrainrotData = require(game:GetService("ReplicatedStorage").Shared.BrainrotData)

local BaseManager = {}
BaseManager.__index = BaseManager

-- Reads the six Base1..Base6 folders Rojo built into Workspace: pad, fence, sign
-- and the eight slot pads each. The sign label is what players read, so it is
-- kept here and refreshed whenever an owner, a star or a lock changes.
function BaseManager.new(workspace)
	local self = setmetatable({}, BaseManager)
	self.bases = {}

	for index = 1, BrainrotData.BASE_COUNT do
		local folder = workspace:WaitForChild("Base" .. index)
		local slots = {}
		for slot = 1, BrainrotData.SLOTS_PER_BASE do
			slots[slot] = folder:WaitForChild("Slot" .. slot)
		end
		self.bases[index] = {
			index = index,
			folder = folder,
			pad = folder:WaitForChild("Pad"),
			padCenter = folder:WaitForChild("Pad").Position,
			signLabel = folder:WaitForChild("Sign"):WaitForChild("SignGui"):WaitForChild("SignLabel"),
			slots = slots,
			owner = nil,
			ownerName = "",
			stars = 0,
			lockedUntil = 0,
			lockCooldownUntil = 0,
			placed = {}, -- [slotIndex] = brainrot Model standing on that slot
		}
		self:updateSign(self.bases[index])
	end

	return self
end

-- The sign over a base: owner name, one star per rebirth, and a lock warning.
function BaseManager:updateSign(base)
	if base.owner == nil then
		base.signLabel.Text = "Base " .. base.index .. "\nFREE — walk in to claim it"
		return
	end
	local stars = string.rep("★", base.stars)
	local lockNote = ""
	if self:isLocked(base) then
		lockNote = "\n🔒 LOCKED"
	end
	base.signLabel.Text = base.ownerName .. " " .. stars .. lockNote
end

function BaseManager:isLocked(base)
	return os.time() < base.lockedUntil
end

-- Locks a base for LOCK_DURATION seconds. Returns false with a reason when the
-- lock is still cooling down from the last use.
function BaseManager:tryLock(base)
	local now = os.time()
	if now < base.lockCooldownUntil then
		return false, "Lock is cooling down for " .. (base.lockCooldownUntil - now) .. "s"
	end
	base.lockedUntil = now + BrainrotData.LOCK_DURATION
	base.lockCooldownUntil = now + BrainrotData.LOCK_COOLDOWN
	self:updateSign(base)
	return true, "Base locked for " .. BrainrotData.LOCK_DURATION .. "s"
end

-- Gives the first free plot to a player who just joined. Returns nil when all
-- six plots are taken; the player can still walk around, just not earn.
function BaseManager:assignBase(player)
	for _, base in ipairs(self.bases) do
		if base.owner == nil then
			base.owner = player
			base.ownerName = player.DisplayName
			base.stars = 0
			base.lockedUntil = 0
			base.lockCooldownUntil = 0
			self:updateSign(base)
			return base
		end
	end
	return nil
end

-- Frees a plot when its owner leaves. Anything still standing on it is destroyed.
function BaseManager:releaseBase(player)
	local base = self:getBaseOf(player)
	if base == nil then
		return
	end
	for slot, model in pairs(base.placed) do
		if model.Parent ~= nil then
			model:Destroy()
		end
		base.placed[slot] = nil
	end
	base.owner = nil
	base.ownerName = ""
	base.stars = 0
	base.lockedUntil = 0
	base.lockCooldownUntil = 0
	self:updateSign(base)
end

function BaseManager:getBaseOf(player)
	if player == nil then
		return nil
	end
	for _, base in ipairs(self.bases) do
		if base.owner == player then
			return base
		end
	end
	return nil
end

-- First empty slot on a base, or nil when all eight are full.
function BaseManager:getFreeSlotIndex(base)
	for slot = 1, BrainrotData.SLOTS_PER_BASE do
		if base.placed[slot] == nil then
			return slot
		end
	end
	return nil
end

-- The world position a brainrot stands on for a given slot, just above the pad.
function BaseManager:getSlotPosition(base, slotIndex)
	local slotPart = base.slots[slotIndex]
	return slotPart.Position + Vector3.new(0, 2.2, 0)
end

-- Records a brainrot as standing on a slot. The caller moves the model there.
function BaseManager:placeModel(base, model, slotIndex)
	base.placed[slotIndex] = model
end

-- Takes a brainrot off its slot and returns it. The caller moves it elsewhere.
function BaseManager:removeModel(base, model)
	for slot, placed in pairs(base.placed) do
		if placed == model then
			base.placed[slot] = nil
			return slot
		end
	end
	return nil
end

-- Which slot a model stands on, or nil when it is not on this base.
function BaseManager:findModelSlot(base, model)
	for slot, placed in pairs(base.placed) do
		if placed == model then
			return slot
		end
	end
	return nil
end

-- Every brainrot currently earning on a base.
function BaseManager:getPlacedModels(base)
	local models = {}
	for _, model in pairs(base.placed) do
		if model.Parent ~= nil then
			table.insert(models, model)
		end
	end
	return models
end

-- True when a world position is inside this base's pad (the safe zone during a
-- storm). The pad is 26 wide, so 13 studs from the centre in either direction.
function BaseManager:isPointInBase(base, position)
	local dx = math.abs(position.X - base.padCenter.X)
	local dz = math.abs(position.Z - base.padCenter.Z)
	return dx <= 13 and dz <= 13
end

return BaseManager
