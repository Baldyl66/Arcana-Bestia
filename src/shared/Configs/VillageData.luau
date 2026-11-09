-- PNJ du village de Brumeval, prix de la boutique, fusion et quêtes.
local VillageData = {}

VillageData.Name = "Brumeval"

VillageData.MysticPrice = 600

VillageData.Shop = {
	BundleCount = 3,
	BundlePrice = 270,
	ElementPrice = 180,
}

-- Nombre de doublons d'une rareté consommés pour obtenir une carte de la rareté suivante.
VillageData.FusionCost = 4
VillageData.SellBonus = 1.5

-- Plan du château (X = est, Z = sud, coordonnées monde). Lu par World et Village.
-- L'arène de l'autel occupe le centre d'une grande place ronde ; autour, les
-- quartiers du château (forge, marché, donjon, entrepôt, champs, bergerie,
-- potager) dans une enceinte carrée entourée de douves. Hors les murs : prairie,
-- sapins, chemins de terre et petit colisée à l'est.
local function rect(x0: number, z0: number, x1: number, z1: number)
	return { Vector2.new(math.min(x0, x1), math.min(z0, z1)), Vector2.new(math.max(x0, x1), math.max(z0, z1)) }
end

VillageData.Layout = {
	-- Les remparts sont le bord de la carte : de Wall à Wall + WallThickness.
	Wall = 330,
	WallThickness = 10,
	WallHeight = 26,
	Ground = 0,
	-- Douves (décor, hors d'atteinte) et collines au-delà.
	MoatInner = 345,
	MoatOuter = 367,
	Hills = 400,
	-- Boulevard autour de l'arène et grande place ronde pavée.
	RingInner = 79,
	RingOuter = 93,
	Plaza = 112,
	-- Grille 3 × 3 : l'arène au centre, huit quartiers autour, séparés par un
	-- boulevard carré (119 à 131 du centre) et deux grandes avenues.
	-- Nord : donjon et cour d'honneur.
	Keep = Vector2.new(0, -280),
	HonorCourt = rect(-90, -235, 90, -140),
	-- Sud : Grand-Place du marché.
	MarketSquare = rect(-112, 140, 112, 318),
	Fountain = Vector2.new(0, 212),
	-- Ouest : arènes de l'ouest (ancien quartier des artisans), sur tout le bloc.
	ArtisanYard = rect(-322, -112, -140, 112),
	-- Forge de Borin : dans le quartier des maisons (sud-ouest), au sud de la rue.
	Forge = Vector2.new(-177, 246),
	-- Nord-est : caserne (logis des gardes, entraînement, écurie).
	BarracksYard = rect(140, -322, 322, -234),
	TrainingYard = rect(140, -210, 240, -140),
	StableYard = rect(250, -210, 322, -140),
	-- Sud-est : entrepôts et potager.
	WarehouseYard = rect(140, 140, 322, 210),
	VegetableGarden = rect(146, 236, 318, 318),
	-- Sud-ouest : quartier des maisons.
	Houses = rect(-322, 140, -140, 322),
	-- Nord-ouest : ferme.
	Fields = rect(-322, -322, -140, -236),
	SheepPen = rect(-322, -210, -210, -140),
	Windmill = Vector2.new(-168, -175),
	-- Jardins fleuris aux angles du carré central.
	Gardens = { Vector2.new(-100, -100), Vector2.new(100, -100), Vector2.new(-100, 100), Vector2.new(100, 100) },
	-- Rues pavées (rectangles min/max).
	Paths = {
		-- Boulevard carré autour de la place.
		rect(-131, -131, 131, -119), rect(-131, 119, 131, 131), rect(-131, -131, -119, 131), rect(119, -131, 131, 131),
		-- Avenues. La nord s'arrête à la porte du donjon ; la sud s'interrompt
		-- autour de la fontaine pour qu'elle trône au milieu de la place.
		rect(-8, -258, 8, -112), rect(-8, 112, 8, 182), rect(-8, 242, 8, 322), rect(-162, -8, -112, 8), rect(112, -8, 162, 8),
		-- Rues secondaires des coins (celle du sud-ouest est la rue des maisons).
		rect(-322, -226, -131, -218), rect(131, -226, 322, -218), rect(-322, 187, -131, 195), rect(131, 218, 322, 226),
	},
	-- Allées en dalles de pierre { départ, arrivée, largeur } : relient les rues
	-- des coins au boulevard, et la place aux jardins d'angle puis au boulevard.
	StonePaths = {
		{ Vector2.new(-125, 131), Vector2.new(-125, 187), 8 },
		{ Vector2.new(125, 131), Vector2.new(125, 218), 8 },
		{ Vector2.new(-125, -131), Vector2.new(-125, -218), 8 },
		{ Vector2.new(125, -131), Vector2.new(125, -218), 8 },
		-- Chapelle et square, au sud de la rue des maisons.
		{ Vector2.new(-225, 195), Vector2.new(-225, 300), 6 },
	},
	-- Arènes des Champions : deux zones de trois arènes rectangulaires, l'une à l'est
	-- (« Colosseum », nom historique), l'autre à l'ouest. Gate = direction de l'entrée
	-- de la zone (degrés, vers la ville). Voir VillageData.arenaSlots().
	Colosseum = Vector2.new(231, 0),
	ColosseumRadius = 72,
	ColosseumGate = 180,
	ArenaWest = Vector2.new(-231, 0),
	ArenaWestGate = 0,
}

-- Les six arènes de duel. Chaque arène est un rectangle allongé dans l'axe de la
-- zone (on y entre par un bout) ; les duellistes se font face sur cet axe.
-- Center / Axis en Vector2 (X, Z monde). Dimensions partagées par le serveur
-- (construction, placement) et le client (Arena3D).
VillageData.Arena = {
	Length = 84, -- le long de l'axe des duellistes (bouts à ±42)
	Width = 38, -- en travers (parapets à ±19)
	Spacing = 90, -- entre les centres de deux arènes voisines (≈ 52 studs libres entre elles)
	FloorHeight = 1.5, -- dessus du sol de combat au-dessus du sol extérieur
	-- Dallage de la zone : tout le bloc de la ville (182 × 280 studs, marges comprises).
	ZoneFront = 87, -- vers l'entrée (estrade de Varek, enseigne)
	ZoneBack = 87, -- vers le fond (étendards)
	ZoneHalfWidth = 132, -- en travers, de part et d'autre du centre
}
local slots = nil
function VillageData.arenaSlots(): { any }
	if slots then
		return slots
	end
	slots = {}
	local L = VillageData.Layout
	for _, zone in ipairs({ { "Est", L.Colosseum, L.ColosseumGate }, { "Ouest", L.ArenaWest, L.ArenaWestGate } }) do
		local g = math.rad(zone[3])
		local gate = Vector2.new(math.cos(g), math.sin(g))
		local across = Vector2.new(-gate.Y, gate.X)
		for i = 1, 3 do
			table.insert(slots, {
				Id = zone[1] .. i,
				Zone = zone[1],
				Center = zone[2] + across * (i - 2) * VillageData.Arena.Spacing,
				Axis = gate, -- axe des duellistes = axe de la zone
				Gate = gate, -- côté de l'entrée de la zone
			})
		end
	end
	return slots
end
function VillageData.arenaSlot(id: string?): any?
	for _, s in ipairs(VillageData.arenaSlots()) do
		if s.Id == id then
			return s
		end
	end
	return nil
end
-- Zones d'arènes (centre, direction de l'entrée), pour le terrain et le décor.
function VillageData.arenaZones(): { { Center: Vector2, Gate: Vector2, Id: string } }
	local L = VillageData.Layout
	local out = {}
	for _, zone in ipairs({ { "Est", L.Colosseum, L.ColosseumGate }, { "Ouest", L.ArenaWest, L.ArenaWestGate } }) do
		local g = math.rad(zone[3])
		table.insert(out, { Id = zone[1], Center = zone[2], Gate = Vector2.new(math.cos(g), math.sin(g)) })
	end
	return out
end
VillageData.Layout.Half = VillageData.Layout.Wall + VillageData.Layout.WallThickness

-- Diagonales : sentier naturel continu de la place au coin du boulevard,
-- à travers le jardin d'angle (4e champ « Natural » : lampadaires face à face, sans dalles).
for _, g in ipairs(VillageData.Layout.Gardens) do
	local u = g.Unit
	table.insert(VillageData.Layout.StonePaths, { u * (VillageData.Layout.Plaza - 2), u * (119 * math.sqrt(2)), 7, "Natural" })
	-- Raccord propre entre le bout du sentier et l'allée qui part vers le quartier du coin.
	local corner = Vector2.new(math.sign(g.X) * 119, math.sign(g.Y) * 119)
	table.insert(VillageData.Layout.StonePaths, { corner - u * 4, Vector2.new(math.sign(g.X) * 125, math.sign(g.Y) * 135), 8, "Natural" })
end

-- Quartiers, pour les indices de Pip.
VillageData.Districts = {
	{ Label = "la Grand-Place", Center = VillageData.Layout.Fountain },
	{ Label = "la forge de Borin", Center = VillageData.Layout.Forge },
	{ Label = "les arènes de l'ouest", Center = VillageData.Layout.ArenaWest },
	{ Label = "la cour d'honneur du donjon", Center = Vector2.new(0, -190) },
	{ Label = "la caserne", Center = Vector2.new(230, -230) },
	{ Label = "les entrepôts", Center = Vector2.new(230, 175) },
	{ Label = "le potager", Center = Vector2.new(230, 277) },
	{ Label = "le quartier des maisons", Center = Vector2.new(-230, 230) },
	{ Label = "la ferme", Center = Vector2.new(-230, -230) },
	{ Label = "les arènes de l'est", Center = VillageData.Layout.Colosseum },
}

-- Tenues : couleurs du corps (peau, haut, manches, pantalon) + vêtements en pièces.
VillageData.Npcs = {
	Elya = {
		Name = "Elya",
		Role = "Marchande",
		Skin = Color3.fromRGB(234, 190, 150),
		Shirt = Color3.fromRGB(150, 40, 60),
		Sleeves = Color3.fromRGB(240, 230, 210),
		Pants = Color3.fromRGB(90, 35, 45),
		Outfit = "Merchant",
		Greeting = "Bienvenue à ma boutique, voyageur ! Mes boosters viennent des quatre coins du royaume.",
		Lines = { "Boosters frais du jour !", "Approchez, approchez !", "Un booster élémentaire, peut-être ?" },
	},
	Borin = {
		Name = "Borin",
		Role = "Forgeron alchimiste",
		Skin = Color3.fromRGB(200, 150, 110),
		Shirt = Color3.fromRGB(90, 80, 70),
		Sleeves = Color3.fromRGB(200, 150, 110),
		Pants = Color3.fromRGB(55, 45, 40),
		Outfit = "Smith",
		Greeting = "Hmpf. Des doublons qui dorment dans ton sac ? Mon creuset peut en faire quelque chose de bien plus précieux.",
		Lines = { "*CLANG* *CLANG*", "Le creuset est chaud !", "Apporte-moi tes doublons." },
	},
	Orin = {
		Name = "Maître Orin",
		Role = "Sage des épreuves",
		Skin = Color3.fromRGB(225, 185, 160),
		Shirt = Color3.fromRGB(40, 45, 110),
		Sleeves = Color3.fromRGB(40, 45, 110),
		Pants = Color3.fromRGB(30, 34, 85),
		Outfit = "Sage",
		Greeting = "Les bêtes arcaniques ne se livrent qu'aux âmes persévérantes. Accomplis mes épreuves et tu seras récompensé.",
		Lines = { "Les étoiles parlent, ce soir...", "As-tu relevé mes épreuves ?", "La patience est une magie." },
	},
	Selene = {
		Name = "Sélène",
		Role = "Gardienne des cristaux",
		Skin = Color3.fromRGB(205, 215, 235),
		Shirt = Color3.fromRGB(70, 150, 170),
		Sleeves = Color3.fromRGB(70, 150, 170),
		Pants = Color3.fromRGB(40, 70, 100),
		Outfit = "CrystalKeeper",
		Greeting = "Les cristaux du sanctuaire m'ont annoncé ta venue. Auprès d'eux, les bêtes les plus rares se laissent approcher.",
		Lines = { "Les cristaux chantent...", "Bienvenue au sanctuaire.", "Chut... écoute les cristaux." },
	},
	Varek = {
		Name = "Varek",
		Role = "Maître de l'arène",
		Skin = Color3.fromRGB(200, 150, 115),
		Shirt = Color3.fromRGB(120, 30, 35),
		Sleeves = Color3.fromRGB(200, 150, 115),
		Pants = Color3.fromRGB(60, 45, 35),
		Outfit = "Champion",
		Greeting = "Bienvenue dans l'Arène des Champions ! Ici, les dresseurs se mesurent les uns aux autres. Choisis ton adversaire et que le meilleur gagne !",
		Lines = { "Qui ose relever le défi ?", "L'arène a soif de gloire !", "Approche, champion !" },
	},
	-- PNJ des quartiers.
	Rhea = {
		Name = "Capitaine Rhéa",
		Role = "Instructrice de la caserne",
		Skin = Color3.fromRGB(210, 165, 130),
		Shirt = Color3.fromRGB(60, 70, 120),
		Sleeves = Color3.fromRGB(60, 70, 120),
		Pants = Color3.fromRGB(45, 45, 55),
		Outfit = "Guard",
		Greeting = "Garde-à-vous, dresseur ! Chaque jour, je récompense ceux qui remportent un entraînement au Cercle des Arcanes.",
		Lines = { "Un, deux ! Un, deux !", "La discipline forge les champions.", "Prêt pour le défi du jour ?" },
	},
	Oswin = {
		Name = "Oswin",
		Role = "Marchand de cartes",
		Skin = Color3.fromRGB(225, 180, 140),
		Shirt = Color3.fromRGB(110, 70, 30),
		Sleeves = Color3.fromRGB(235, 220, 190),
		Pants = Color3.fromRGB(60, 45, 35),
		Outfit = "Merchant",
		Greeting = "Ah, un connaisseur ! Mon étal change chaque jour : des créatures choisies, au prix juste... ou presque.",
		Lines = { "Cartes rares, cartes fraîches !", "L'étal du jour vaut le détour !", "Je n'en ai qu'une de chaque !" },
	},
	Maelis = {
		Name = "Maelis",
		Role = "Archiviste du donjon",
		Skin = Color3.fromRGB(235, 205, 180),
		Shirt = Color3.fromRGB(90, 40, 110),
		Sleeves = Color3.fromRGB(90, 40, 110),
		Pants = Color3.fromRGB(50, 25, 65),
		Outfit = "Sage",
		Greeting = "Les archives du donjon recensent chaque bête arcanique. Réunis toutes les créatures d'un élément, et le royaume saura te remercier.",
		Lines = { "Chut, on archive...", "Il me manque encore des pages.", "Chaque élément a son histoire." },
	},
	Gaelle = {
		Name = "Gaëlle",
		Role = "Fermière",
		Skin = Color3.fromRGB(200, 150, 110),
		Shirt = Color3.fromRGB(110, 140, 70),
		Sleeves = Color3.fromRGB(240, 230, 210),
		Pants = Color3.fromRGB(90, 70, 50),
		Outfit = "Farmer",
		Greeting = "Bonjour bonjour ! La récolte a été bonne, j'ai préparé un panier pour chaque visiteur. Reviens demain, il y en aura un autre !",
		Lines = { "Les moutons sont sages aujourd'hui.", "Un panier pour toi ?", "Le moulin tourne, la vie est belle !" },
	},
	Odile = {
		Name = "Grand-mère Odile",
		Role = "Conteuse du quartier",
		Skin = Color3.fromRGB(235, 200, 175),
		Shirt = Color3.fromRGB(150, 110, 160),
		Sleeves = Color3.fromRGB(150, 110, 160),
		Pants = Color3.fromRGB(150, 110, 160),
		Outfit = "Lady",
		Greeting = "Viens t'asseoir, petit. À mon âge, on en a vu, des bêtes arcaniques... Veux-tu un conseil ou une histoire ?",
		Lines = { "Viens écouter une histoire...", "De mon temps, les Anima étaient sauvages !", "Ah, la jeunesse..." },
	},
}

-- Étal du jour d'Oswin : prix par rareté.
VillageData.StallPrices = { Commun = 70, PeuCommun = 150, Rare = 380, Epique = 950, Legendaire = 2400 }
-- Défi quotidien de Rhéa, panier de Gaëlle, collections de Maelis.
VillageData.DailyDuelReward = 150
VillageData.FarmBasket = { Min = 40, Max = 90 }
VillageData.ElementSetReward = 450

-- Les 3 créatures de l'étal du jour (identiques pour tous, changent chaque jour).
function VillageData.stallFor(day: number): { string }
	local rng = Random.new(day * 7919 + 17)
	local tiers = { { "Commun", "PeuCommun" }, { "PeuCommun", "Rare" }, { "Rare", "Epique" } }
	local CardsData = require(script.Parent:WaitForChild("CardsData"))
	local picked = {}
	for _, tier in ipairs(tiers) do
		local pool = {}
		for _, c in ipairs(CardsData.Cards) do
			if table.find(tier, c.Rarity) and not table.find(picked, c.Id) then
				table.insert(pool, c.Id)
			end
		end
		if #pool > 0 then
			table.insert(picked, pool[rng:NextInteger(1, #pool)])
		end
	end
	-- Un jour sur sept, une Légendaire remplace la troisième carte.
	if day % 7 == 3 then
		local legends = {}
		for _, c in ipairs(CardsData.Cards) do
			if c.Rarity == "Legendaire" then
				table.insert(legends, c.Id)
			end
		end
		picked[3] = legends[rng:NextInteger(1, #legends)]
	end
	return picked
end

for id, npc in pairs(VillageData.Npcs) do
	npc.Id = id
end

-- Villageois qui se promènent.
VillageData.Villagers = {
	{ Name = "Gaspard", Outfit = "Guard", Skin = Color3.fromRGB(225, 180, 150), Shirt = Color3.fromRGB(120, 30, 40), Sleeves = Color3.fromRGB(120, 30, 40), Pants = Color3.fromRGB(50, 50, 60),
		Lines = { "Tout est calme en ville.", "Halte ! ... Ah, c'est toi." } },
	{ Name = "Lina", Outfit = "Baker", Skin = Color3.fromRGB(240, 205, 175), Shirt = Color3.fromRGB(235, 225, 205), Sleeves = Color3.fromRGB(235, 225, 205), Pants = Color3.fromRGB(120, 90, 70),
		Lines = { "Le pain est presque prêt !", "Ça sent bon la brioche !" } },
	{ Name = "Tobias", Outfit = "Farmer", Skin = Color3.fromRGB(190, 140, 100), Shirt = Color3.fromRGB(200, 70, 60), Sleeves = Color3.fromRGB(200, 70, 60), Pants = Color3.fromRGB(60, 80, 130),
		Lines = { "Belle récolte au jardin du Prieuré.", "Des choux, des citrouilles, du bon pain !" } },
	{ Name = "Mira", Outfit = "Lady", Skin = Color3.fromRGB(150, 105, 75), Shirt = Color3.fromRGB(70, 130, 110), Sleeves = Color3.fromRGB(70, 130, 110), Pants = Color3.fromRGB(70, 130, 110),
		Lines = { "Quelle belle journée !", "As-tu vu la fontaine ?" } },
	{ Name = "Nell", Outfit = "Child", Skin = Color3.fromRGB(245, 210, 180), Shirt = Color3.fromRGB(240, 180, 60), Sleeves = Color3.fromRGB(240, 180, 60), Pants = Color3.fromRGB(80, 110, 170),
		Lines = { "J'ai eu un Pyxel !", "Tu joues avec moi ?" } },
	{ Name = "Bram", Outfit = "Guard", Skin = Color3.fromRGB(200, 155, 120), Shirt = Color3.fromRGB(60, 70, 120), Sleeves = Color3.fromRGB(60, 70, 120), Pants = Color3.fromRGB(45, 45, 55),
		Lines = { "Le donjon est bien gardé.", "Rien à signaler, dresseur." } },
	{ Name = "Elise", Outfit = "Lady", Skin = Color3.fromRGB(235, 200, 170), Shirt = Color3.fromRGB(170, 90, 130), Sleeves = Color3.fromRGB(170, 90, 130), Pants = Color3.fromRGB(170, 90, 130),
		Lines = { "Les cloches de la chapelle sonnent bientôt.", "Quelle jolie rue, n'est-ce pas ?" } },
	{ Name = "Odo", Outfit = "Farmer", Skin = Color3.fromRGB(180, 130, 95), Shirt = Color3.fromRGB(110, 140, 70), Sleeves = Color3.fromRGB(110, 140, 70), Pants = Color3.fromRGB(90, 70, 50),
		Lines = { "Les chevaux ont faim.", "Le moulin tourne bien aujourd'hui !" } },
	{ Name = "Timo", Outfit = "Child", Skin = Color3.fromRGB(230, 190, 150), Shirt = Color3.fromRGB(80, 170, 200), Sleeves = Color3.fromRGB(80, 170, 200), Pants = Color3.fromRGB(70, 70, 90),
		Lines = { "Je fais la course autour de l'arène !", "Un jour je combattrai au colisée !" } },
}

-- Stat : "BoostersOpened" | "Discovered" | "Talked" | "Treasures" | "Legendary" | "Visited:<lieu>"
VillageData.Quests = {
	{ Id = "talk", Text = "Parler à tous les villageois", Stat = "Talked", Goal = 4, Reward = 100 },
	{ Id = "open5", Text = "Ouvrir 5 boosters", Stat = "BoostersOpened", Goal = 5, Reward = 150 },
	{ Id = "discover5", Text = "Découvrir 5 créatures", Stat = "Discovered", Goal = 5, Reward = 200 },
	{ Id = "market", Text = "Flâner au marché", Stat = "Visited:market", Goal = 1, Reward = 120 },
	{ Id = "forge", Text = "Visiter la forge de Borin", Stat = "Visited:forge", Goal = 1, Reward = 120 },
	{ Id = "keep", Text = "Approcher le donjon", Stat = "Visited:keep", Goal = 1, Reward = 150 },
	{ Id = "colosseum", Text = "Visiter l'Arène des Champions", Stat = "Visited:colosseum", Goal = 1, Reward = 150 },
	{ Id = "open25", Text = "Ouvrir 25 boosters", Stat = "BoostersOpened", Goal = 25, Reward = 600 },
	{ Id = "discover10", Text = "Découvrir 10 créatures", Stat = "Discovered", Goal = 10, Reward = 500 },
	{ Id = "legendary", Text = "Obtenir une créature Légendaire", Stat = "Legendary", Goal = 1, Reward = 1000 },
	{ Id = "discoverAll", Text = "Compléter le bestiaire", Stat = "Discovered", Goal = 30, Reward = 2500 },
}

VillageData.Places = {
	market = { Label = "La Grand-Place", Center = VillageData.Layout.Fountain, Radius = 60 },
	forge = { Label = "La forge de Borin", Center = VillageData.Layout.Forge, Radius = 40 },
	keep = { Label = "Le donjon", Center = Vector2.new(0, -230), Radius = 50 },
	farm = { Label = "La ferme", Center = Vector2.new(-230, -260), Radius = 60 },
	colosseum = { Label = "Les Arènes des Champions", Center = VillageData.Layout.Colosseum, Radius = 60 },
}

-- Points de téléportation de la carte du monde (coordonnées x, z au sol).
-- Carte illustrée pour la mini-carte et la grande carte : colle ici
-- l'identifiant de l'image importée (ex. "rbxassetid://123456789").
-- Elle doit couvrir tout le monde, nord en haut. Vide = relevé automatique.
VillageData.MapImage = ""

VillageData.Teleports = {
	{ Id = "arena", Label = "Autel arcanique", Pos = Vector2.new(0, 48), Side = "Right" },
	{ Id = "market", Label = "Grand-Place", Pos = Vector2.new(0, 150), Side = "Bottom" },
	{ Id = "forge", Label = "Arènes Ouest", Pos = Vector2.new(-150, 0), Side = "Left" },
	{ Id = "keep", Label = "Donjon", Pos = Vector2.new(0, -150), Side = "Top" },
	{ Id = "colosseum", Label = "Arènes Est", Pos = Vector2.new(150, 0), Side = "Right" },
	{ Id = "barracks", Label = "Caserne", Pos = Vector2.new(150, -222), Side = "Right" },
	{ Id = "houses", Label = "Maisons", Pos = Vector2.new(-150, 191), Side = "Left" },
}

VillageData.Treasure = {
	MinReward = 80,
	MaxReward = 220,
	RespawnDelay = 20,
}

-- Valeur actuelle d'une statistique de quête pour un profil.
function VillageData.statValue(profile, stat: string): number
	local place = stat:match("^Visited:(.+)$")
	if place then
		return (profile.Visited and profile.Visited[place]) and 1 or 0
	elseif stat == "BoostersOpened" then
		return profile.BoostersOpened or 0
	elseif stat == "Treasures" then
		return profile.Treasures or 0
	end
	local count = 0
	if stat == "Talked" then
		for _ in pairs(profile.Talked or {}) do
			count += 1
		end
	elseif stat == "Discovered" then
		for _ in pairs(profile.Cards or {}) do
			count += 1
		end
	elseif stat == "Legendary" then
		local CardsData = require(script.Parent:WaitForChild("CardsData"))
		for id in pairs(profile.Cards or {}) do
			local card = CardsData.CardById[id]
			if card and card.Rarity == "Legendaire" then
				count += 1
			end
		end
	end
	return count
end

-- Liste des quêtes avec progression et état.
function VillageData.questStates(profile)
	local list = {}
	for _, quest in ipairs(VillageData.Quests) do
		local value = VillageData.statValue(profile, quest.Stat)
		table.insert(list, {
			Id = quest.Id,
			Text = quest.Text,
			Reward = quest.Reward,
			Goal = quest.Goal,
			Progress = math.min(value, quest.Goal),
			Done = value >= quest.Goal,
			Claimed = (profile.Quests and profile.Quests[quest.Id]) == true,
		})
	end
	return list
end

function VillageData.readyCount(profile): number
	local count = 0
	for _, state in ipairs(VillageData.questStates(profile)) do
		if state.Done and not state.Claimed then
			count += 1
		end
	end
	return count
end

return VillageData
