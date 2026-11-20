-- Haunted Brainrot Manor: turns a cast definition into a blocky 3D Model.
-- One module, one job: building characters. It never touches the game state; the
-- server decides where a model goes and who owns it, this module only shapes it.
-- Everything that makes one brainrot different from another lives in the data
-- table (BrainrotData.CAST): body and head colours plus one accessory spec, so
-- 36 characters stay one small builder instead of 36 special cases.

local BrainrotData = require(script.Parent.BrainrotData)

local BrainrotFactory = {}

local function makePart(name, size, color, shape, material, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Shape = shape or Enum.PartType.Block
	part.Material = material or Enum.Material.SmoothPlastic
	part.Transparency = transparency or 0
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = true
	part.CanQuery = true
	return part
end

-- The one accessory part per cast member, built straight from the spec in the
-- data table: shape, size, offset from the model origin, rotation, colour.
local function buildAccessory(def)
	local spec = def.accessory
	local part = makePart(
		"Accessory",
		spec.size,
		spec.color,
		Enum.PartType[spec.shape],
		spec.material,
		spec.transparency
	)
	part.CFrame = CFrame.new(spec.offset)
		* CFrame.Angles(math.rad(spec.rot.X), math.rad(spec.rot.Y), math.rad(spec.rot.Z))
	return part
end

-- The floating name tag every brainrot wears: name, rarity and mutation on one
-- line, $/s and the BUY price on the next, readable from across the plaza so a
-- player can spot a Mythic from the spawn point. showBuy is true while the
-- brainrot rides the conveyor and false once it lives on a base.
local function buildNameTag(model, displayName, def, effectiveRate, price, showBuy)
	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromOffset(240, 76)
	tag.ExtentsOffsetWorldSpace = Vector3.new(0, 6.5, 0)
	tag.AlwaysOnTop = false
	tag.Parent = model

	local label = Instance.new("TextLabel")
	label.Name = "TagLabel"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(15, 12, 25)
	label.BackgroundTransparency = 0.15
	label.BorderSizePixel = 0
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = tag

	local rarityStripe = Instance.new("Frame")
	rarityStripe.Name = "RarityStripe"
	rarityStripe.Size = UDim2.new(1, 0, 0, 6)
	rarityStripe.Position = UDim2.new(0, 0, 1, -6)
	rarityStripe.BorderSizePixel = 0
	rarityStripe.BackgroundColor3 = BrainrotData.RARITY_COLORS[def.rarity]
	rarityStripe.Parent = label

	BrainrotFactory.setTagText(model, displayName, def, effectiveRate, price, showBuy)
	return tag
end

-- Rewrites the tag text from the model's own attributes, so the server can flip
-- a brainrot from "BUY $X" on the conveyor to plain "$/s" on a base.
function BrainrotFactory.setTagText(model, displayName, def, effectiveRate, price, showBuy)
	local tag = model:FindFirstChild("NameTag")
	if tag == nil then
		return
	end
	local label = tag:FindFirstChild("TagLabel")
	if label == nil then
		return
	end
	if showBuy then
		label.Text = displayName .. "\n" .. def.rarity .. "  |  +$" .. effectiveRate .. "/s\nBUY $" .. price
	else
		label.Text = displayName .. "\n" .. def.rarity .. "  |  +$" .. effectiveRate .. "/s"
	end
end

-- A Rainbow brainrot cycles its body colour through the spectrum while it lives.
-- The loop watches the model's parent, so it stops on its own when the model is
-- destroyed or re-parented out of the world.
local function startRainbowCycle(model, body)
	task.spawn(function()
		local hue = 0
		while model.Parent ~= nil do
			hue = (hue + 0.04) % 1
			body.Color = Color3.fromHSV(hue, 0.75, 1)
			task.wait(0.4)
		end
	end)
end

-- Builds the whole Model for one brainrot: body, head, one accessory, name tag.
-- The model is anchored and moved with PivotTo, never by physics, so every part
-- stays exactly where the factory put it. Returns the Model, unparented; the
-- caller parents it and sets its first CFrame.
function BrainrotFactory.buildBrainrotModel(def, mutation)
	local effectiveRate = BrainrotData.getEffectiveRate(def, mutation)
	local displayName = BrainrotData.getDisplayName(def, mutation)
	local price = BrainrotData.getPrice(def, mutation)

	local model = Instance.new("Model")
	model.Name = displayName

	local bodyColor = def.bodyColor
	local bodyMaterial = Enum.Material.SmoothPlastic
	local bodyTransparency = 0
	if mutation then
		if mutation.tint then
			bodyColor = mutation.tint
		end
		if mutation.neon then
			bodyMaterial = Enum.Material.Neon
		end
		if mutation.ghostly then
			bodyTransparency = 0.4
		end
	end

	local body = makePart("Body", Vector3.new(4, 4, 4), bodyColor, Enum.PartType.Block, bodyMaterial, bodyTransparency)
	body.CFrame = CFrame.new(0, 0, 0)
	body.Parent = model
	model.PrimaryPart = body

	local head = makePart("Head", Vector3.new(3.2, 3, 3.2), def.headColor)
	head.CFrame = CFrame.new(0, 3.5, 0)
	head.Parent = model

	local accessory = buildAccessory(def)
	accessory.Parent = model

	buildNameTag(model, displayName, def, effectiveRate, price, true)

	-- Everything the server needs to know about this brainrot, on the model itself.
	model:SetAttribute("BrainrotId", def.id)
	model:SetAttribute("Rarity", def.rarity)
	model:SetAttribute("Rate", effectiveRate)
	model:SetAttribute("Price", price)
	model:SetAttribute("Mutation", mutation and mutation.name or "None")
	model:SetAttribute("State", "Conveyor")
	model:SetAttribute("OwnerUserId", 0)

	if mutation and mutation.name == "Rainbow" then
		startRainbowCycle(model, body)
	end

	return model
end

-- The Ghost Burglar: a black-clad thief with a mask and a loot sack who roams
-- the manor grounds, steals from an unlocked base and runs for the exit.
function BrainrotFactory.buildBurglarModel()
	local model = Instance.new("Model")
	model.Name = "The Ghost Burglar"

	local body = makePart("Body", Vector3.new(4, 4, 4), Color3.fromRGB(30, 30, 40))
	body.CFrame = CFrame.new(0, 0, 0)
	body.Parent = model
	model.PrimaryPart = body

	local head = makePart("Head", Vector3.new(3.2, 3, 3.2), Color3.fromRGB(220, 220, 230))
	head.CFrame = CFrame.new(0, 3.5, 0)
	head.Parent = model

	local mask = makePart("Mask", Vector3.new(3.4, 1, 0.5), Color3.fromRGB(15, 15, 20))
	mask.CFrame = CFrame.new(0, 3.9, 1.6)
	mask.Parent = model

	local sack = makePart("LootSack", Vector3.new(3, 3, 3), Color3.fromRGB(120, 85, 45), Enum.PartType.Ball)
	sack.CFrame = CFrame.new(2.6, 0.5, 0)
	sack.Parent = model

	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromOffset(260, 76)
	tag.ExtentsOffsetWorldSpace = Vector3.new(0, 6.5, 0)
	tag.Parent = model

	local label = Instance.new("TextLabel")
	label.Name = "TagLabel"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(15, 12, 25)
	label.BackgroundTransparency = 0.15
	label.BorderSizePixel = 0
	label.TextColor3 = Color3.fromRGB(255, 120, 120)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = "THE GHOST BURGLAR\nWHACK HIM! [F]"
	label.Parent = tag

	return model
end

-- The Poltergeist, the storm boss: a huge pale ghost with a floating crown who
-- stomps down the plaza while the fog wall sweeps behind him.
function BrainrotFactory.buildStormBossModel()
	local model = Instance.new("Model")
	model.Name = "The Poltergeist"

	local body = makePart("Body", Vector3.new(9, 9, 9), Color3.fromRGB(220, 225, 245), Enum.PartType.Block, Enum.Material.SmoothPlastic, 0.25)
	body.CFrame = CFrame.new(0, 0, 0)
	body.Parent = model
	model.PrimaryPart = body

	local head = makePart("Head", Vector3.new(7, 6, 7), Color3.fromRGB(235, 238, 250), Enum.PartType.Block, Enum.Material.SmoothPlastic, 0.25)
	head.CFrame = CFrame.new(0, 7.5, 0)
	head.Parent = model

	local crown = makePart("Crown", Vector3.new(6, 2.5, 6), Color3.fromRGB(255, 215, 0), Enum.PartType.Cylinder, Enum.Material.Neon)
	crown.CFrame = CFrame.new(0, 12, 0) * CFrame.Angles(0, 0, math.rad(90))
	crown.Parent = model

	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromOffset(320, 80)
	tag.ExtentsOffsetWorldSpace = Vector3.new(0, 14, 0)
	tag.Parent = model

	local label = Instance.new("TextLabel")
	label.Name = "TagLabel"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(15, 12, 25)
	label.BackgroundTransparency = 0.15
	label.BorderSizePixel = 0
	label.TextColor3 = Color3.fromRGB(180, 220, 255)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = "THE POLTERGEIST\nGET TO YOUR BASE!"
	label.Parent = tag

	return model
end

return BrainrotFactory
