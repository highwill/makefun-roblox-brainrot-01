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

	-- The dot tag: a tiny rarity-coloured dot the client shows for brainrots
	-- too far away to read the full label. One small dot, never a wall of text.
	local dot = Instance.new("BillboardGui")
	dot.Name = "DotTag"
	dot.Size = UDim2.fromOffset(14, 14)
	dot.ExtentsOffsetWorldSpace = Vector3.new(0, 6.5, 0)
	dot.AlwaysOnTop = false
	dot.Enabled = false
	dot.Parent = model

	local dotMark = Instance.new("Frame")
	dotMark.Name = "Dot"
	dotMark.Size = UDim2.fromScale(1, 1)
	dotMark.BackgroundColor3 = BrainrotData.RARITY_COLORS[def.rarity]
	dotMark.BorderSizePixel = 0
	dotMark.Parent = dot
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dotMark

	return tag
end

-- The enemy tag: name on top, an HP bar underneath. Ghosts, the burglar and
-- the Boss all wear one, so a player can always see what to hit and how much
-- fight is left in it. The server updates the bar with setHealthBar.
local function buildEnemyTag(model, nameText, nameColor, width, yOffset)
	local tag = Instance.new("BillboardGui")
	tag.Name = "EnemyTag"
	tag.Size = UDim2.fromOffset(width, 52)
	tag.ExtentsOffsetWorldSpace = Vector3.new(0, yOffset, 0)
	tag.AlwaysOnTop = true
	tag.Parent = model

	local label = Instance.new("TextLabel")
	label.Name = "TagLabel"
	label.Size = UDim2.new(1, 0, 0, 26)
	label.BackgroundColor3 = Color3.fromRGB(15, 12, 25)
	label.BackgroundTransparency = 0.15
	label.BorderSizePixel = 0
	label.TextColor3 = nameColor
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = nameText
	label.Parent = tag

	local barBack = Instance.new("Frame")
	barBack.Name = "BarBack"
	barBack.Position = UDim2.new(0, 0, 0, 30)
	barBack.Size = UDim2.new(1, 0, 0, 12)
	barBack.BackgroundColor3 = Color3.fromRGB(40, 10, 15)
	barBack.BorderSizePixel = 0
	barBack.Parent = tag

	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(90, 230, 90)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBack

	return tag
end

-- Sets an enemy's HP bar from its current and maximum HP. Green above half,
-- amber below half, red when nearly beaten.
function BrainrotFactory.setHealthBar(model, hp, maxHp)
	local tag = model:FindFirstChild("EnemyTag")
	if tag == nil then
		return
	end
	local barBack = tag:FindFirstChild("BarBack")
	if barBack == nil then
		return
	end
	local fill = barBack:FindFirstChild("BarFill")
	if fill == nil then
		return
	end
	local frac = math.clamp(hp / math.max(maxHp, 1), 0, 1)
	fill.Size = UDim2.new(frac, 0, 1, 0)
	if frac > 0.5 then
		fill.BackgroundColor3 = Color3.fromRGB(90, 230, 90)
	elseif frac > 0.25 then
		fill.BackgroundColor3 = Color3.fromRGB(255, 190, 60)
	else
		fill.BackgroundColor3 = Color3.fromRGB(255, 70, 60)
	end
end

-- A red outline so a threat reads as a threat at a glance.
local function addThreatHighlight(model)
	local highlight = Instance.new("Highlight")
	highlight.Name = "ThreatHighlight"
	highlight.FillColor = Color3.fromRGB(255, 40, 40)
	highlight.FillTransparency = 0.85
	highlight.OutlineColor = Color3.fromRGB(255, 60, 60)
	highlight.OutlineTransparency = 0
	highlight.Parent = model
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

-- A Haunted Ghost: a small pale-green wisp that chases the nearest player and
-- steals cash on touch. Three whacks defeat it. Its HP bar is the EnemyTag.
function BrainrotFactory.buildGhostModel()
	local model = Instance.new("Model")
	model.Name = "Haunted Ghost"

	local body = makePart("Body", Vector3.new(3.5, 3.5, 3.5), Color3.fromRGB(170, 230, 170), Enum.PartType.Ball, Enum.Material.Neon, 0.25)
	body.CFrame = CFrame.new(0, 0, 0)
	body.Parent = model
	model.PrimaryPart = body

	local eyeLeft = makePart("EyeLeft", Vector3.new(0.7, 0.9, 0.5), Color3.fromRGB(20, 20, 25))
	eyeLeft.CFrame = CFrame.new(-0.8, 0.8, 1.7)
	eyeLeft.Parent = model

	local eyeRight = makePart("EyeRight", Vector3.new(0.7, 0.9, 0.5), Color3.fromRGB(20, 20, 25))
	eyeRight.CFrame = CFrame.new(0.8, 0.8, 1.7)
	eyeRight.Parent = model

	buildEnemyTag(model, "HAUNTED GHOST  ·  WHACK! [F]", Color3.fromRGB(170, 255, 170), 170, 5)
	BrainrotFactory.setHealthBar(model, BrainrotData.GHOST_HP, BrainrotData.GHOST_HP)
	addThreatHighlight(model)

	model:SetAttribute("HP", BrainrotData.GHOST_HP)
	model:SetAttribute("MaxHP", BrainrotData.GHOST_HP)
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

	buildEnemyTag(model, "THE GHOST BURGLAR  ·  WHACK! [F]", Color3.fromRGB(255, 120, 120), 260, 6.5)
	BrainrotFactory.setHealthBar(model, BrainrotData.BURGLAR_HP, BrainrotData.BURGLAR_HP)
	addThreatHighlight(model)

	model:SetAttribute("HP", BrainrotData.BURGLAR_HP)
	model:SetAttribute("MaxHP", BrainrotData.BURGLAR_HP)
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

	buildEnemyTag(model, "THE POLTERGEIST BOSS  ·  WHACK! [F]", Color3.fromRGB(180, 220, 255), 340, 14)
	addThreatHighlight(model)

	-- The server overwrites these with the scaled HP right after spawning.
	model:SetAttribute("HP", BrainrotData.BOSS_HP_BASE)
	model:SetAttribute("MaxHP", BrainrotData.BOSS_HP_BASE)
	BrainrotFactory.setHealthBar(model, BrainrotData.BOSS_HP_BASE, BrainrotData.BOSS_HP_BASE)

	return model
end

return BrainrotFactory
