-- Haunted Brainrot Manor: the cast, the rarity ladder, the mutations, the quests
-- and every tuning number. One module, one job: data. No instances, no services,
-- no side effects, so the server and the client can both require it.

local BrainrotData = {}

-- Conveyor -------------------------------------------------------------------
BrainrotData.SPAWN_INTERVAL = 8 -- seconds between brainrots leaving the Manor Gate
BrainrotData.CONVEYOR_START_Z = -88 -- the Manor Gate end of the haunted hallway
BrainrotData.CONVEYOR_END_Z = 88 -- the Crypt Gate; a brainrot that gets here despawns
BrainrotData.CONVEYOR_HEIGHT = 2.4 -- body centre height while riding the lane
BrainrotData.CONVEYOR_TIME = 25 -- seconds to walk the whole lane
BrainrotData.STORM_SPAWN_COUNT = 4 -- mutated brainrots the storm drops on the lane

-- Money ----------------------------------------------------------------------
BrainrotData.MONEY_TICK = 1 -- seconds between income ticks
BrainrotData.START_CASH = 100 -- every player starts able to afford a Dusty Doormat

-- Rebirth --------------------------------------------------------------------
BrainrotData.REBIRTH_THRESHOLD = 100000 -- totalEarned needed before Rebirth works
BrainrotData.REBIRTH_MAX_MULTIPLIER = 8 -- x2 per rebirth, stacking, capped here

-- Poltergeist Storm -----------------------------------------------------------
BrainrotData.STORM_INTERVAL = 150 -- seconds of calm between storms
BrainrotData.STORM_DURATION = 20 -- seconds the fog wall sweeps the manor grounds
BrainrotData.STORM_SLOW_SPEED = 8 -- WalkSpeed of a player caught outside their base
BrainrotData.STORM_SLOW_TIME = 10 -- seconds the slow lasts
BrainrotData.STORM_CASH_LOSS = 0.05 -- fraction of cash a caught player loses

-- The Ghost Burglar -----------------------------------------------------------
BrainrotData.BURGLAR_INTERVAL = 90 -- seconds between burglar visits
BrainrotData.BURGLAR_VISIT_TIME = 30 -- seconds a burglar stays before giving up
BrainrotData.BURGLAR_WALK_TIME = 10 -- seconds for the burglar to reach a base
BrainrotData.BURGLAR_FLEE_TIME = 12 -- seconds for the burglar to run for the exit

-- Bases, stealing, slapping ---------------------------------------------------
BrainrotData.BASE_COUNT = 6
BrainrotData.SLOTS_PER_BASE = 8
BrainrotData.LOCK_DURATION = 60 -- seconds a locked base cannot be stolen from
BrainrotData.LOCK_COOLDOWN = 120 -- seconds before the same base can lock again
BrainrotData.SLAP_COOLDOWN = 5 -- seconds between whacks
BrainrotData.SLAP_COOLDOWN_GLOVE = 2 -- whack cooldown with the Golden Glove
BrainrotData.SLAP_RANGE = 12 -- studs; a thief further away cannot be whacked
BrainrotData.SLAP_STUN_TIME = 3 -- seconds a whacked thief stands still
BrainrotData.SLAP_KNOCKBACK = 10 -- studs a whacked thief is thrown backwards
BrainrotData.CARRY_HEIGHT = 4.5 -- studs above the carrier's head while stolen

-- Upgrades -------------------------------------------------------------------
BrainrotData.SPEED_BOOTS_PRICE = 5000
BrainrotData.GOLDEN_GLOVE_PRICE = 2500
BrainrotData.BASE_WALK_SPEED = 16
BrainrotData.SPEED_BOOTS_WALK_SPEED = 24

-- Rarity ladder, in order. The rank number is what quests compare against.
BrainrotData.RARITY_ORDER = {
	"Common",
	"Uncommon",
	"Rare",
	"Epic",
	"Legendary",
	"Mythic",
	"Secret",
	"Brainrot God",
}

BrainrotData.RARITY_COLORS = {
	Common = Color3.fromRGB(170, 170, 170),
	Uncommon = Color3.fromRGB(80, 200, 80),
	Rare = Color3.fromRGB(70, 130, 255),
	Epic = Color3.fromRGB(170, 80, 255),
	Legendary = Color3.fromRGB(255, 200, 40),
	Mythic = Color3.fromRGB(255, 60, 90),
	Secret = Color3.fromRGB(255, 90, 200),
	["Brainrot God"] = Color3.fromRGB(255, 230, 120),
}

function BrainrotData.getRarityRank(rarity)
	for rank, name in ipairs(BrainrotData.RARITY_ORDER) do
		if name == rarity then
			return rank
		end
	end
	return 0
end

-- The cast: 36 haunted-house characters, 8 rarities.
-- price is always rate x 50. weight is the spawn weight; rarer brainrots show
-- up less often. accessory is the ONE extra part the factory bolts on, fully
-- described here so the factory stays data-driven: shape, size, offset from the
-- model origin, rotation in degrees, colour, material, transparency.
local function acc(shape, size, offset, rot, color, material, transparency)
	return {
		shape = shape,
		size = size,
		offset = offset,
		rot = rot,
		color = color,
		material = material or Enum.Material.SmoothPlastic,
		transparency = transparency or 0,
	}
end

BrainrotData.CAST = {
	-- Common x8: $1/s to $8/s -----------------------------------------------
	{ id = "dusty-doormat", name = "Dusty Doormat", rarity = "Common", rate = 1, weight = 40,
		bodyColor = Color3.fromRGB(150, 125, 90), headColor = Color3.fromRGB(130, 105, 75),
		accessory = acc("Block", Vector3.new(4, 0.6, 3), Vector3.new(0, 5.6, 0), Vector3.new(0, 0, 0), Color3.fromRGB(110, 85, 55)) },
	{ id = "squeaky-floorboard", name = "Squeaky Floorboard", rarity = "Common", rate = 2, weight = 40,
		bodyColor = Color3.fromRGB(160, 110, 60), headColor = Color3.fromRGB(140, 95, 50),
		accessory = acc("Block", Vector3.new(4.5, 0.8, 1.5), Vector3.new(0, 5.8, 0), Vector3.new(0, 0, 15), Color3.fromRGB(120, 80, 40)) },
	{ id = "wobbly-candelabra", name = "Wobbly Candelabra", rarity = "Common", rate = 3, weight = 40,
		bodyColor = Color3.fromRGB(220, 180, 90), headColor = Color3.fromRGB(200, 160, 70),
		accessory = acc("Cylinder", Vector3.new(2.5, 2.5, 3), Vector3.new(0, 6, 0), Vector3.new(0, 0, 90), Color3.fromRGB(240, 200, 100)) },
	{ id = "grumpy-gargoyle", name = "Grumpy Gargoyle", rarity = "Common", rate = 4, weight = 40,
		bodyColor = Color3.fromRGB(120, 120, 130), headColor = Color3.fromRGB(100, 100, 110),
		accessory = acc("Wedge", Vector3.new(3, 3, 2), Vector3.new(0, 5.8, 0), Vector3.new(0, 0, 0), Color3.fromRGB(90, 90, 100)) },
	{ id = "leaky-teapot-ghost", name = "Leaky Teapot Ghost", rarity = "Common", rate = 5, weight = 40,
		bodyColor = Color3.fromRGB(180, 210, 230), headColor = Color3.fromRGB(160, 195, 220),
		accessory = acc("Ball", Vector3.new(3, 3, 3), Vector3.new(0, 5.8, 0), Vector3.new(0, 0, 0), Color3.fromRGB(200, 225, 240)) },
	{ id = "moth-eaten-curtain", name = "Moth-Eaten Curtain", rarity = "Common", rate = 6, weight = 40,
		bodyColor = Color3.fromRGB(120, 70, 150), headColor = Color3.fromRGB(100, 55, 130),
		accessory = acc("Block", Vector3.new(3.5, 4, 0.5), Vector3.new(0, 5.5, 0), Vector3.new(-10, 0, 0), Color3.fromRGB(90, 50, 120)) },
	{ id = "creaky-rocking-chair", name = "Creaky Rocking Chair", rarity = "Common", rate = 7, weight = 40,
		bodyColor = Color3.fromRGB(110, 70, 40), headColor = Color3.fromRGB(95, 60, 35),
		accessory = acc("Block", Vector3.new(3.5, 2.5, 3), Vector3.new(0, 5.8, 0), Vector3.new(0, 0, 0), Color3.fromRGB(85, 50, 30)) },
	{ id = "sleepy-dust-bunny", name = "Sleepy Dust Bunny", rarity = "Common", rate = 8, weight = 40,
		bodyColor = Color3.fromRGB(190, 190, 200), headColor = Color3.fromRGB(175, 175, 185),
		accessory = acc("Ball", Vector3.new(2.8, 2.8, 2.8), Vector3.new(0, 5.8, 0), Vector3.new(0, 0, 0), Color3.fromRGB(210, 210, 220)) },

	-- Uncommon x7: $10/s to $40/s ---------------------------------------------
	{ id = "sir-spooksalot", name = "Sir Spooksalot", rarity = "Uncommon", rate = 10, weight = 30,
		bodyColor = Color3.fromRGB(240, 240, 245), headColor = Color3.fromRGB(225, 225, 235),
		accessory = acc("Ball", Vector3.new(3.2, 3.2, 3.2), Vector3.new(0, 5.8, 0), Vector3.new(0, 0, 0), Color3.fromRGB(255, 255, 255)) },
	{ id = "count-candelabra", name = "Count Candelabra", rarity = "Uncommon", rate = 14, weight = 30,
		bodyColor = Color3.fromRGB(180, 40, 50), headColor = Color3.fromRGB(160, 30, 40),
		accessory = acc("Cylinder", Vector3.new(2, 2, 4), Vector3.new(0, 6.5, 0), Vector3.new(0, 0, 90), Color3.fromRGB(220, 180, 80)) },
	{ id = "madame-mirror", name = "Madame Mirror", rarity = "Uncommon", rate = 18, weight = 30,
		bodyColor = Color3.fromRGB(200, 200, 210), headColor = Color3.fromRGB(185, 185, 200),
		accessory = acc("Block", Vector3.new(3, 4, 0.4), Vector3.new(0, 5.8, 0), Vector3.new(0, 20, 0), Color3.fromRGB(220, 220, 235), Enum.Material.Metal) },
	{ id = "batty-bookshelf", name = "Batty Bookshelf", rarity = "Uncommon", rate = 22, weight = 30,
		bodyColor = Color3.fromRGB(130, 85, 45), headColor = Color3.fromRGB(115, 75, 40),
		accessory = acc("Block", Vector3.new(4, 3, 1), Vector3.new(0, 5.8, 0), Vector3.new(0, 0, 0), Color3.fromRGB(100, 60, 30)) },
	{ id = "professor-portraits", name = "Professor Portraits", rarity = "Uncommon", rate = 27, weight = 30,
		bodyColor = Color3.fromRGB(200, 170, 90), headColor = Color3.fromRGB(185, 155, 75),
		accessory = acc("Block", Vector3.new(3.5, 4, 0.4), Vector3.new(0, 5.8, 0), Vector3.new(0, 0, 0), Color3.fromRGB(220, 190, 100), Enum.Material.Metal) },
	{ id = "wailing-wallpaper", name = "Wailing Wallpaper", rarity = "Uncommon", rate = 33, weight = 30,
		bodyColor = Color3.fromRGB(90, 140, 80), headColor = Color3.fromRGB(75, 125, 65),
		accessory = acc("Cylinder", Vector3.new(2, 4, 2), Vector3.new(0, 6, 0), Vector3.new(0, 0, 90), Color3.fromRGB(110, 160, 95)) },
	{ id = "captain-cobweb", name = "Captain Cobweb", rarity = "Uncommon", rate = 40, weight = 30,
		bodyColor = Color3.fromRGB(230, 230, 235), headColor = Color3.fromRGB(215, 215, 225),
		accessory = acc("Block", Vector3.new(4, 3.5, 0.4), Vector3.new(0, 5.8, 0), Vector3.new(0, 0, 0), Color3.fromRGB(245, 245, 250), Enum.Material.SmoothPlastic, 0.4) },

	-- Rare x6: $50/s to $150/s ------------------------------------------------
	{ id = "the-haunted-piano", name = "The Haunted Piano", rarity = "Rare", rate = 50, weight = 18,
		bodyColor = Color3.fromRGB(40, 40, 45), headColor = Color3.fromRGB(30, 30, 35),
		accessory = acc("Block", Vector3.new(4, 2, 3), Vector3.new(0, 5.8, 0), Vector3.new(0, 0, 0), Color3.fromRGB(25, 25, 30)) },
	{ id = "baron-von-bathtub", name = "Baron Von Bathtub", rarity = "Rare", rate = 65, weight = 18,
		bodyColor = Color3.fromRGB(235, 235, 240), headColor = Color3.fromRGB(220, 220, 230),
		accessory = acc("Block", Vector3.new(4, 2, 2.5), Vector3.new(0, 5.8, 0), Vector3.new(0, 0, 0), Color3.fromRGB(245, 245, 250)) },
	{ id = "lady-lampshade", name = "Lady Lampshade", rarity = "Rare", rate = 80, weight = 18,
		bodyColor = Color3.fromRGB(240, 170, 190), headColor = Color3.fromRGB(225, 150, 175),
		accessory = acc("Cylinder", Vector3.new(3, 2.5, 3), Vector3.new(0, 6, 0), Vector3.new(0, 0, 90), Color3.fromRGB(255, 190, 210)) },
	{ id = "duke-of-the-dustpan", name = "Duke of the Dustpan", rarity = "Rare", rate = 100, weight = 18,
		bodyColor = Color3.fromRGB(180, 180, 190), headColor = Color3.fromRGB(165, 165, 175),
		accessory = acc("Wedge", Vector3.new(3.5, 2, 3), Vector3.new(0, 5.8, 0), Vector3.new(0, 0, 0), Color3.fromRGB(200, 200, 210), Enum.Material.Metal) },
	{ id = "the-screaming-kettle", name = "The Screaming Kettle", rarity = "Rare", rate = 120, weight = 18,
		bodyColor = Color3.fromRGB(50, 50, 55), headColor = Color3.fromRGB(40, 40, 45),
		accessory = acc("Ball", Vector3.new(3, 3, 3), Vector3.new(0, 5.8, 0), Vector3.new(0, 0, 0), Color3.fromRGB(35, 35, 40)) },
	{ id = "marquis-de-mantelpiece", name = "Marquis de Mantelpiece", rarity = "Rare", rate = 150, weight = 18,
		bodyColor = Color3.fromRGB(210, 170, 80), headColor = Color3.fromRGB(195, 155, 65),
		accessory = acc("Block", Vector3.new(3.5, 3.5, 1), Vector3.new(0, 5.8, 0), Vector3.new(0, 0, 0), Color3.fromRGB(230, 190, 100), Enum.Material.Metal) },

	-- Epic x5: $180/s to $450/s -----------------------------------------------
	{ id = "phantom-butler", name = "Phantom Butler", rarity = "Epic", rate = 180, weight = 9,
		bodyColor = Color3.fromRGB(45, 45, 55), headColor = Color3.fromRGB(235, 235, 240),
		accessory = acc("Block", Vector3.new(2.5, 3.5, 1), Vector3.new(0, 5.8, 0), Vector3.new(0, 0, 0), Color3.fromRGB(30, 30, 40)) },
	{ id = "the-grand-chandelier", name = "The Grand Chandelier", rarity = "Epic", rate = 230, weight = 9,
		bodyColor = Color3.fromRGB(230, 190, 90), headColor = Color3.fromRGB(215, 175, 75),
		accessory = acc("Cylinder", Vector3.new(3.5, 1.5, 3.5), Vector3.new(0, 6, 0), Vector3.new(0, 0, 90), Color3.fromRGB(255, 215, 120), Enum.Material.Neon) },
	{ id = "witch-of-the-west-wing", name = "Witch of the West Wing", rarity = "Epic", rate = 290, weight = 9,
		bodyColor = Color3.fromRGB(120, 60, 160), headColor = Color3.fromRGB(105, 50, 145),
		accessory = acc("Wedge", Vector3.new(3.5, 3.5, 3.5), Vector3.new(0, 5.8, 0), Vector3.new(0, 0, 0), Color3.fromRGB(90, 40, 130)) },
	{ id = "sir-reginald-rattling-chains", name = "Sir Reginald Rattling Chains", rarity = "Epic", rate = 360, weight = 9,
		bodyColor = Color3.fromRGB(140, 140, 150), headColor = Color3.fromRGB(125, 125, 135),
		accessory = acc("Cylinder", Vector3.new(1, 4, 1), Vector3.new(2.4, 2, 0), Vector3.new(0, 0, 20), Color3.fromRGB(160, 160, 170), Enum.Material.Metal) },
	{ id = "the-poltergeist-piano", name = "The Poltergeist Piano", rarity = "Epic", rate = 450, weight = 9,
		bodyColor = Color3.fromRGB(80, 50, 120), headColor = Color3.fromRGB(65, 40, 105),
		accessory = acc("Wedge", Vector3.new(4, 3, 3), Vector3.new(0, 5.8, 0), Vector3.new(0, 0, 0), Color3.fromRGB(70, 45, 110)) },

	-- Legendary x4: $500/s to $1,200/s -----------------------------------------
	{ id = "headless-horsemans-horse", name = "The Headless Horseman's Horse", rarity = "Legendary", rate = 500, weight = 4,
		bodyColor = Color3.fromRGB(35, 35, 40), headColor = Color3.fromRGB(25, 25, 30),
		accessory = acc("Wedge", Vector3.new(4, 3, 2), Vector3.new(0, 5.8, 0), Vector3.new(0, 90, 0), Color3.fromRGB(20, 20, 25)) },
	{ id = "madame-zucchinis-crystal-ball", name = "Madame Zucchini's Crystal Ball", rarity = "Legendary", rate = 650, weight = 4,
		bodyColor = Color3.fromRGB(150, 90, 200), headColor = Color3.fromRGB(135, 75, 185),
		accessory = acc("Ball", Vector3.new(3.5, 3.5, 3.5), Vector3.new(0, 6, 0), Vector3.new(0, 0, 0), Color3.fromRGB(180, 110, 230), Enum.Material.Neon) },
	{ id = "the-vampire-vacuum", name = "The Vampire Vacuum", rarity = "Legendary", rate = 850, weight = 4,
		bodyColor = Color3.fromRGB(180, 40, 50), headColor = Color3.fromRGB(160, 30, 40),
		accessory = acc("Block", Vector3.new(3.5, 2.5, 2), Vector3.new(0, 5.8, 0), Vector3.new(0, 0, 0), Color3.fromRGB(200, 50, 60)) },
	{ id = "king-coffin", name = "King Coffin", rarity = "Legendary", rate = 1200, weight = 4,
		bodyColor = Color3.fromRGB(90, 60, 35), headColor = Color3.fromRGB(75, 50, 30),
		accessory = acc("Block", Vector3.new(3, 4.5, 1.2), Vector3.new(0, 5.8, 0), Vector3.new(0, 0, 10), Color3.fromRGB(110, 75, 45)) },

	-- Mythic x3: $1,500/s to $2,200/s -------------------------------------------
	{ id = "the-ghost-king", name = "The Ghost King", rarity = "Mythic", rate = 1500, weight = 2,
		bodyColor = Color3.fromRGB(240, 240, 250), headColor = Color3.fromRGB(225, 225, 240),
		accessory = acc("Cylinder", Vector3.new(3, 2, 3), Vector3.new(0, 6, 0), Vector3.new(0, 0, 90), Color3.fromRGB(255, 215, 0), Enum.Material.Neon) },
	{ id = "draculas-doorknob", name = "Dracula's Doorknob", rarity = "Mythic", rate = 1800, weight = 2,
		bodyColor = Color3.fromRGB(160, 120, 50), headColor = Color3.fromRGB(145, 105, 40),
		accessory = acc("Ball", Vector3.new(2.5, 2.5, 2.5), Vector3.new(0, 5.8, 0), Vector3.new(0, 0, 0), Color3.fromRGB(200, 150, 60), Enum.Material.Metal) },
	{ id = "the-manor-itself", name = "The Manor Itself", rarity = "Mythic", rate = 2200, weight = 2,
		bodyColor = Color3.fromRGB(100, 70, 150), headColor = Color3.fromRGB(85, 55, 135),
		accessory = acc("Block", Vector3.new(4, 3.5, 3), Vector3.new(0, 5.8, 0), Vector3.new(0, 0, 0), Color3.fromRGB(120, 85, 170)) },

	-- Secret x2: $2,500/s and $2,800/s -----------------------------------------
	{ id = "the-butler-did-it", name = "The Butler Did It", rarity = "Secret", rate = 2500, weight = 0.8,
		bodyColor = Color3.fromRGB(35, 35, 45), headColor = Color3.fromRGB(220, 220, 230),
		accessory = acc("Block", Vector3.new(1, 3.5, 0.6), Vector3.new(2.4, 1.5, 0.5), Vector3.new(0, 0, -15), Color3.fromRGB(210, 210, 220), Enum.Material.Metal) },
	{ id = "grandmas-haunted-fruitcake", name = "Grandma's Haunted Fruitcake", rarity = "Secret", rate = 2800, weight = 0.8,
		bodyColor = Color3.fromRGB(120, 75, 35), headColor = Color3.fromRGB(105, 65, 30),
		accessory = acc("Block", Vector3.new(3.5, 2, 3.5), Vector3.new(0, 5.8, 0), Vector3.new(0, 0, 0), Color3.fromRGB(140, 90, 45)) },

	-- Brainrot God x1: $3,000/s -----------------------------------------------
	{ id = "the-overlord-of-the-manor", name = "The Overlord of the Manor", rarity = "Brainrot God", rate = 3000, weight = 0.3,
		bodyColor = Color3.fromRGB(25, 20, 40), headColor = Color3.fromRGB(40, 30, 70),
		accessory = acc("Cylinder", Vector3.new(4, 2.5, 4), Vector3.new(0, 6.2, 0), Vector3.new(0, 0, 90), Color3.fromRGB(255, 200, 0), Enum.Material.Neon) },
}

-- Mutations. Rolled in order: Diamond first, then Rainbow, Molten, Spectral,
-- Golden, Frozen, so the rarest roll wins. multiplier applies to the earn rate,
-- and the price follows it (price = effective rate x 50).
BrainrotData.MUTATIONS = {
	{ name = "Diamond", prefix = "Diamond ", chance = 0.01, multiplier = 10, tint = Color3.fromRGB(200, 230, 255) },
	{ name = "Rainbow", prefix = "Rainbow ", chance = 0.02, multiplier = 5, tint = nil },
	{ name = "Molten", prefix = "Molten ", chance = 0.02, multiplier = 4, tint = Color3.fromRGB(255, 110, 30), neon = true },
	{ name = "Spectral", prefix = "Spectral ", chance = 0.03, multiplier = 3, tint = Color3.fromRGB(220, 230, 255), ghostly = true },
	{ name = "Golden", prefix = "Golden ", chance = 0.05, multiplier = 2, tint = Color3.fromRGB(255, 215, 0) },
	{ name = "Frozen", prefix = "Frozen ", chance = 0.04, multiplier = 1.5, tint = Color3.fromRGB(170, 210, 255) },
}

-- Rolls one mutation by the chances above. Returns the mutation row, or nil.
function BrainrotData.rollMutation()
	local roll = math.random()
	local running = 0
	for _, mutation in ipairs(BrainrotData.MUTATIONS) do
		running += mutation.chance
		if roll <= running then
			return mutation
		end
	end
	return nil
end

-- Forces a mutation: every storm spawn is mutated, so the roll never comes
-- back plain. Picks uniformly among the six.
function BrainrotData.rollForcedMutation()
	return BrainrotData.MUTATIONS[math.random(1, #BrainrotData.MUTATIONS)]
end

-- Picks one cast member, weighted so commons show up often and the God almost
-- never does.
function BrainrotData.pickBrainrotDef()
	local totalWeight = 0
	for _, def in ipairs(BrainrotData.CAST) do
		totalWeight += def.weight
	end
	local roll = math.random() * totalWeight
	for _, def in ipairs(BrainrotData.CAST) do
		roll -= def.weight
		if roll <= 0 then
			return def
		end
	end
	return BrainrotData.CAST[1]
end

-- The earn rate after the mutation, and the buy price that follows it.
function BrainrotData.getEffectiveRate(def, mutation)
	if mutation then
		return def.rate * mutation.multiplier
	end
	return def.rate
end

function BrainrotData.getPrice(def, mutation)
	return BrainrotData.getEffectiveRate(def, mutation) * 50
end

-- The full display name, mutation prefix included when there is one.
function BrainrotData.getDisplayName(def, mutation)
	if mutation then
		return mutation.prefix .. def.name
	end
	return def.name
end

-- Quests. id, the name the HUD shows, the target count, the cash reward.
-- Progress is counted on the server; the client only displays this table.
BrainrotData.QUESTS = {
	{ id = "grab-5", name = "Grab 5 loose brainrots", target = 5, reward = 2000 },
	{ id = "grab-15", name = "Grab 15 loose brainrots", target = 15, reward = 10000 },
	{ id = "steal-1", name = "Steal 1 brainrot", target = 1, reward = 5000 },
	{ id = "survive-2", name = "Survive 2 storms at home", target = 2, reward = 8000 },
	{ id = "whack-1", name = "Whack the Ghost Burglar", target = 1, reward = 15000 },
	{ id = "rebirth-1", name = "Rebirth once", target = 1, reward = 25000 },
	{ id = "collect-100k", name = "Collect $100,000 total", target = 100000, reward = 20000 },
	{ id = "own-legendary", name = "Own a Legendary or better", target = 1, reward = 15000 },
	{ id = "own-mythic", name = "Own a Mythic or better", target = 1, reward = 30000 },
	{ id = "full-base", name = "Fill all 8 base slots", target = 1, reward = 12000 },
	{ id = "lock-3", name = "Lock your base 3 times", target = 3, reward = 3000 },
}

function BrainrotData.getQuestById(questId)
	for _, quest in ipairs(BrainrotData.QUESTS) do
		if quest.id == questId then
			return quest
		end
	end
	return nil
end

-- Short money formatting for the HUD: 57,700,000 reads as $57.7M.
function BrainrotData.formatMoney(amount)
	if amount >= 1000000 then
		local millions = math.floor(amount / 100000) / 10
		return "$" .. millions .. "M"
	elseif amount >= 1000 then
		local thousands = math.floor(amount / 100) / 10
		return "$" .. thousands .. "K"
	else
		return "$" .. math.floor(amount)
	end
end

return BrainrotData
