-- « Le Grimoire du Dresseur » : tutoriel plein écran, illustré, en chapitres.
--   • fond arcanique animé (étoiles, rayons, cercle magique tournant) ;
--   • à gauche, une grande illustration par chapitre (cartes, vues 3D du
--     monde, portraits des habitants, clavier / manette / téléphone) ;
--   • à droite, chapitre, titre, texte et trois points clés ;
--   • frise des chapitres cliquable, flèches, manette, balayage tactile.
-- La scène fait 1280 × 720 et s'adapte à l'écran (PC, tablette, téléphone).
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CardsData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CardsData"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))
local CardView = require(script.Parent:WaitForChild("CardView"))

local Tutorial = {}

local W, H = 1280, 720
local GOLD = Color3.fromRGB(255, 215, 120)
local GOLD_DARK = Color3.fromRGB(170, 110, 35)
local CREAM = Color3.fromRGB(255, 244, 220)
local MUTED = Color3.fromRGB(185, 175, 215)
local INK = Color3.fromRGB(14, 10, 24)

-- Couleur par fonction, partagée entre l'illustration et la légende.
local C = {
	Move = Color3.fromRGB(150, 110, 255),
	Jump = Color3.fromRGB(255, 200, 80),
	Run = Color3.fromRGB(80, 205, 255),
	Camera = Color3.fromRGB(215, 215, 235),
	Interact = Color3.fromRGB(110, 225, 150),
	Booster = Color3.fromRGB(255, 145, 70),
	Collection = Color3.fromRGB(255, 120, 190),
	Menu = Color3.fromRGB(110, 150, 255),
}
local KEY_BASE = Color3.fromRGB(58, 50, 88)

local function gamepadLabel(keyCode: Enum.KeyCode, fallback: string): string
	local ok, label = pcall(UserInputService.GetStringForKeyCode, UserInputService, keyCode)
	if ok and label ~= "" and not string.match(label, "^Button") then
		return label
	end
	return fallback
end

local function gamepadLegend()
	return {
		Title = "MANETTE",
		{ C.Move, "Stick G", "Se déplacer" },
		{ C.Run, "L3", "Courir (cliquer le stick)" },
		{ C.Camera, "Stick D", "Tourner la caméra" },
		{ C.Jump, gamepadLabel(Enum.KeyCode.ButtonA, "Croix"), "Sauter" },
		{ C.Interact, gamepadLabel(Enum.KeyCode.ButtonX, "Carré"), "Parler, utiliser l'autel" },
		{ C.Booster, "R1", "Ouvrir un booster" },
		{ C.Collection, gamepadLabel(Enum.KeyCode.ButtonY, "Triangle"), "Ouvrir le livre" },
		{ C.Menu, gamepadLabel(Enum.KeyCode.ButtonB, "Rond"), "Retour / fermer" },
	}
end

local LEGENDS = {
	Keyboard = {
		Title = "CLAVIER & SOURIS",
		{ C.Move, "Z Q S D", "Se déplacer" },
		{ C.Jump, "Espace", "Sauter" },
		{ C.Run, "Maj", "Courir (maintenir)" },
		{ C.Camera, "Clic droit", "Tourner la caméra, molette pour zoomer" },
		{ C.Interact, "E", "Parler, utiliser l'autel" },
		{ C.Booster, "B", "Ouvrir un booster" },
		{ C.Collection, "1", "Ouvrir ton grimoire" },
	},
	Touch = {
		Title = "ÉCRAN TACTILE",
		{ C.Move, "Joystick", "Se déplacer" },
		{ C.Jump, "Saut", "Sauter" },
		{ C.Run, "Courir", "Activer / couper la course" },
		{ C.Camera, "Glisser", "Tourner la caméra, pincer pour zoomer" },
		{ C.Interact, "Invite", "Toucher pour parler ou ouvrir un booster" },
		{ C.Collection, "Livre", "Ouvrir ton grimoire (case en bas)" },
		{ C.Menu, "?", "Revoir ce tutoriel" },
	},
}

-------------------------------------------------------------------------------
-- Petits outils de dessin
-------------------------------------------------------------------------------
local function box(parent: Instance, props: { [string]: any }, radius: UDim?): Frame
	local frame = UIKit.new("Frame", props)
	frame.Parent = parent
	UIKit.new("UICorner", { CornerRadius = radius or UDim.new(0.2, 0), Parent = frame })
	return frame
end

local function text(parent: Instance, value: string, color: Color3?, max: number?)
	return UIKit.label({
		Text = value,
		Font = UIKit.Fonts.Black,
		TextColor3 = color or Color3.new(1, 1, 1),
		Size = UDim2.fromScale(0.9, 0.7),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Parent = parent,
	}, max or 18)
end

-- Touche ou bouton : coloré s'il a une fonction, sinon discret.
local function key(parent: Instance, label: string, color: Color3?, props: { [string]: any }, round: boolean?)
	local active = color ~= nil
	props.BackgroundColor3 = Color3.new(1, 1, 1)
	local frame = box(parent, props, round and UDim.new(0.5, 0) or UDim.new(0.22, 0))
	local base = color or KEY_BASE
	UIKit.gradient(frame, base:Lerp(Color3.new(1, 1, 1), active and 0.25 or 0.08), base:Lerp(Color3.new(0, 0, 0), 0.25), 90)
	UIKit.stroke(frame, active and Color3.new(1, 1, 1) or Color3.fromRGB(95, 85, 135), active and 2 or 1, active and 0.1 or 0.3)
	if label ~= "" then
		text(frame, label, active and Color3.fromRGB(25, 15, 45) or Color3.fromRGB(170, 160, 200), 16)
	end
	return frame
end

-------------------------------------------------------------------------------
-- Illustrations des périphériques
-------------------------------------------------------------------------------
local function drawKeyboard(stage: Frame)
	local board = box(stage, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.02, 0.5),
		Size = UDim2.fromScale(0.76, 0.62),
		BackgroundColor3 = Color3.fromRGB(28, 24, 44),
	}, UDim.new(0.06, 0))
	UIKit.stroke(board, Color3.fromRGB(110, 95, 160), 2, 0.3)

	local highlight = {
		Z = C.Move, Q = C.Move, S = C.Move, D = C.Move, E = C.Interact,
		B = C.Booster, ["1"] = C.Collection, Maj = C.Run, Espace = C.Jump,
	}
	local rows = {
		{ { "1" }, { "2" }, { "3" }, { "4" }, { "5" }, { "6" }, { "7" }, { "8" }, { "9" }, { "0" } },
		{ { "A" }, { "Z" }, { "E" }, { "R" }, { "T" }, { "Y" }, { "U" }, { "I" }, { "O" }, { "P" } },
		{ { "Q" }, { "S" }, { "D" }, { "F" }, { "G" }, { "H" }, { "J" }, { "K" }, { "L" }, { "M" } },
		{ { "Maj", 1.9 }, { "W" }, { "X" }, { "C" }, { "V" }, { "B" }, { "N" }, { "", 1.1 } },
		{ { "", 2.5 }, { "Espace", 5 }, { "", 2.5 } },
	}
	local unit, gap = 1 / 10.6, 0.006
	for r, row in ipairs(rows) do
		local x = 0.03 + (r == 3 and unit * 0.3 or 0)
		for _, k in ipairs(row) do
			local w = (k[2] or 1) * unit
			key(board, k[1], highlight[k[1]], {
				Position = UDim2.fromScale(x, 0.05 + (r - 1) * 0.185),
				Size = UDim2.fromScale(w - gap * 2, 0.16),
			})
			x += w
		end
	end

	-- Souris : bouton droit pour la caméra.
	local mouse = box(stage, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.82, 0.5),
		Size = UDim2.fromScale(0.15, 0.5),
		BackgroundColor3 = Color3.fromRGB(28, 24, 44),
	}, UDim.new(0.45, 0))
	UIKit.stroke(mouse, Color3.fromRGB(110, 95, 160), 2, 0.3)
	key(mouse, "", nil, { Position = UDim2.fromScale(0.08, 0.06), Size = UDim2.fromScale(0.4, 0.38) })
	key(mouse, "", C.Camera, { Position = UDim2.fromScale(0.52, 0.06), Size = UDim2.fromScale(0.4, 0.38) })
	box(mouse, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.1), Size = UDim2.fromScale(0.12, 0.22),
		BackgroundColor3 = C.Camera }, UDim.new(0.5, 0))
end

local function drawGamepad(stage: Frame)
	local pad = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromScale(0.82, 0.7),
		Parent = stage,
	})
	-- Gâchettes.
	key(pad, "L1", nil, { Position = UDim2.fromScale(0.12, -0.04), Size = UDim2.fromScale(0.2, 0.12) })
	key(pad, "R1", C.Booster, { Position = UDim2.fromScale(0.68, -0.04), Size = UDim2.fromScale(0.2, 0.12) })
	-- Corps et poignées.
	for _, x in ipairs({ 0.02, 0.68 }) do
		local grip = box(pad, { Position = UDim2.fromScale(x, 0.35), Size = UDim2.fromScale(0.3, 0.65), BackgroundColor3 = Color3.fromRGB(34, 29, 54) },
			UDim.new(0.5, 0))
		UIKit.stroke(grip, Color3.fromRGB(110, 95, 160), 2, 0.3)
	end
	local body = box(pad, { Position = UDim2.fromScale(0.05, 0.08), Size = UDim2.fromScale(0.9, 0.62), BackgroundColor3 = Color3.fromRGB(34, 29, 54) },
		UDim.new(0.3, 0))
	UIKit.stroke(body, Color3.fromRGB(110, 95, 160), 2, 0.3)

	local function stick(x: number, y: number, label: string, color: Color3)
		local ring = key(body, "", nil, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(0.17, 0.17) }, true)
		UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = ring })
		local cap = key(ring, label, color, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.7, 0.7) }, true)
		_ = cap
	end
	stick(0.22, 0.36, "L3", C.Move)
	stick(0.64, 0.7, "R", C.Camera)
	-- Croix directionnelle.
	key(body, "", nil, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.36, 0.7), Size = UDim2.fromScale(0.05, 0.3) })
	key(body, "", nil, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.36, 0.7), Size = UDim2.fromScale(0.13, 0.11) })
	-- Boutons ABXY.
	local function face(x: number, y: number, label: string, color: Color3)
		local b = key(body, label, color, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(0.09, 0.09) }, true)
		UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = b })
	end
	face(0.71, 0.38, gamepadLabel(Enum.KeyCode.ButtonX, "Carré"), C.Interact)
	face(0.85, 0.38, gamepadLabel(Enum.KeyCode.ButtonB, "Rond"), C.Menu)
	face(0.78, 0.56, gamepadLabel(Enum.KeyCode.ButtonA, "Croix"), C.Jump)
end

local function drawPhone(stage: Frame)
	local phone = box(stage, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.8),
		BackgroundColor3 = Color3.fromRGB(20, 18, 30),
	}, UDim.new(0.12, 0))
	UIKit.stroke(phone, Color3.fromRGB(110, 95, 160), 3, 0.2)
	local screen = box(phone, {
		Position = UDim2.fromScale(0.05, 0.08),
		Size = UDim2.fromScale(0.9, 0.84),
		BackgroundColor3 = Color3.new(1, 1, 1),
	}, UDim.new(0.06, 0))
	UIKit.gradient(screen, Color3.fromRGB(120, 170, 230), Color3.fromRGB(80, 140, 80), 90)

	-- Joystick.
	local stickBase = box(screen, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.16, 0.7), Size = UDim2.fromScale(0.3, 0.3),
		BackgroundColor3 = C.Move, BackgroundTransparency = 0.45 }, UDim.new(0.5, 0))
	UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = stickBase })
	UIKit.stroke(stickBase, Color3.new(1, 1, 1), 2, 0.2)
	box(stickBase, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.45, 0.45), BackgroundColor3 = C.Move },
		UDim.new(0.5, 0))
	-- Saut et course.
	local jump = key(screen, "Saut", C.Jump, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.88, 0.72), Size = UDim2.fromScale(0.2, 0.2) }, true)
	UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = jump })
	local run = key(screen, "Courir", C.Run, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.72, 0.8), Size = UDim2.fromScale(0.15, 0.15) }, true)
	UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = run })
	-- Boutons du haut.
	key(screen, "?", C.Menu, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(0.96, 0.06), Size = UDim2.fromScale(0.08, 0.12) })
	-- Invite d'interaction.
	key(screen, "Parler", C.Interact, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.18, 0.13) })
	-- Geste de caméra (traînée pointillée).
	for i = 0, 5 do
		box(screen, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.42 + i * 0.045, 0.72 - i * 0.02), Size = UDim2.fromScale(0.022, 0.04),
			BackgroundColor3 = C.Camera, BackgroundTransparency = 0.1 + i * 0.12 }, UDim.new(0.5, 0))
	end
end

-------------------------------------------------------------------------------
-- Vues 3D tirées du monde
-------------------------------------------------------------------------------
local function snapshot(parent: Instance, source: Instance?, camera: Vector3, focus: Vector3, fov: number, silhouette: boolean?): boolean
	if not source then
		return false
	end
	local ok, clone = pcall(function()
		return source:Clone()
	end)
	if not ok or not clone then
		return false
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BillboardGui") or d:IsA("ProximityPrompt") or d:IsA("LuaSourceContainer") or d:IsA("SurfaceGui") then
			d:Destroy()
		end
	end
	local holder = clone
	if not clone:IsA("Model") then
		holder = Instance.new("Model")
		clone.Parent = holder
	end
	-- Cadrage automatique : on garde l'orientation réelle de l'objet ;
	-- sinon (PNJ), on le remet face à la caméra prévue.
	local holderModel = holder :: Model
	if camera.Magnitude == 0 then
		-- Lieu du monde : repère aligné sur le monde (sinon un modèle dont le
		-- pivot est tourné serait vu de travers), recentré à l'origine.
		holderModel.WorldPivot = CFrame.new(holderModel:GetPivot().Position)
		holderModel:PivotTo(CFrame.new())
	else
		holderModel:PivotTo(CFrame.new())
	end
	if camera.Magnitude == 0 then
		local boxCf, size = (holder :: Model):GetBoundingBox()
		local radius = size.Magnitude / 2
		local dir = (focus.Magnitude > 0 and focus or Vector3.new(0.5, 0.35, -1)).Unit
		focus = boxCf.Position
		camera = focus + dir * (radius / math.tan(math.rad(fov / 2)) * 0.85)
	end
	local viewport = UIKit.new("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = silhouette and Color3.new(0, 0, 0) or Color3.fromRGB(165, 160, 185),
		LightColor = silhouette and Color3.new(0, 0, 0) or Color3.fromRGB(255, 245, 225),
		LightDirection = Vector3.new(-0.6, -1, -0.7),
		Parent = parent,
	})
	holder.Parent = viewport
	local cam = Instance.new("Camera")
	cam.FieldOfView = fov
	cam.CFrame = CFrame.lookAt(camera, focus)
	cam.Parent = viewport
	viewport.CurrentCamera = cam
	return true
end

local function npcSnapshot(parent: Instance, id: string, silhouette: boolean?): boolean
	local world = workspace:FindFirstChild("World")
	local folder = world and world:FindFirstChild("NPCs")
	local npc = folder and folder:FindFirstChild(id)
	if not npc or not npc:FindFirstChild("Head") then
		return false
	end
	local headOffset = npc:GetPivot():PointToObjectSpace(npc.Head.Position)
	local focus = headOffset - Vector3.new(0, 0.9, 0)
	return snapshot(parent, npc, focus + Vector3.new(1.6, 0.4, -7.5), focus, 34, silhouette)
end

local function findPath(...: string): Instance?
	local current: Instance? = workspace
	for _, name in ipairs({ ... }) do
		current = current and current:FindFirstChild(name)
	end
	return current
end

-------------------------------------------------------------------------------
-- Illustrations des chapitres
-------------------------------------------------------------------------------
-- Éventail de cartes qui flottent doucement.
local function cardFan(parent: Instance, ids: { string }, spread: number?)
	local holder = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = parent })
	local n = #ids
	local cards = {}
	for i, id in ipairs(ids) do
		local card = CardsData.CardById[id]
		if card then
			local k = i - (n + 1) / 2
			local slot = UIKit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5 + k * (spread or 0.24), 0.52 + math.abs(k) * 0.05), Size = UDim2.fromScale(0.36, 0.7),
				Rotation = k * 11, ZIndex = 10 - math.abs(k), Parent = holder })
			local view = CardView.create(card, { Detailed = true, Parent = slot })
			view.AnchorPoint = Vector2.new(0.5, 0.5)
			view.Position = UDim2.fromScale(0.5, 0.5)
			-- Calques : la carte du centre passe devant ses voisines.
			local layer = 40 + (10 - math.abs(k) * 2) * 12
			slot.ZIndex = layer
			for _, d in ipairs(slot:GetDescendants()) do
				if d:IsA("GuiObject") then
					d.ZIndex += layer
				end
			end
			table.insert(cards, { Slot = slot, Base = slot.Position, Phase = i * 1.3 })
		end
	end
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not holder.Parent then
			conn:Disconnect()
			return
		end
		local t = os.clock()
		for _, c in ipairs(cards) do
			c.Slot.Position = c.Base + UDim2.fromOffset(0, math.sin(t * 1.4 + c.Phase) * 6)
		end
	end)
	return holder
end

-- Duel : deux cartes face à face, médaillon VS, jauge d'énergie et statuts.
local function duelScene(parent: Instance)
	local holder = cardFan(parent, { "flamichat", "gouttelin" }, 0.46)
	local medal = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48), Size = UDim2.fromOffset(92, 92),
		Rotation = 45, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 200, Parent = holder })
	UIKit.corner(medal, 14)
	UIKit.gradient(medal, Color3.fromRGB(255, 225, 140), Color3.fromRGB(175, 105, 30), 90)
	UIKit.stroke(medal, Color3.fromRGB(60, 25, 5), 4, 0)
	local vs = UIKit.label({ Text = "VS", Font = UIKit.Fonts.Title, TextColor3 = CREAM, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.9), Rotation = -45, ZIndex = 201, Parent = medal }, 44)
	UIKit.new("UIStroke", { Color = Color3.fromRGB(40, 15, 5), Thickness = 3, Parent = vs })
	-- Énergie.
	local pips = UIKit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.97), Size = UDim2.fromOffset(200, 26),
		ZIndex = 200, Parent = holder })
	UIKit.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 14), Parent = pips })
	for i = 1, 5 do
		local pip = UIKit.new("Frame", { Size = UDim2.fromOffset(16, 16), Rotation = 45, BackgroundColor3 = Color3.fromRGB(130, 215, 255),
			BackgroundTransparency = i <= 3 and 0 or 0.8, ZIndex = 200, LayoutOrder = i, Parent = pips })
		UIKit.stroke(pip, Color3.fromRGB(130, 215, 255), 1.5, 0.2)
	end
	-- Statuts qui flottent au-dessus.
	local statuses = { "Burn", "Freeze", "Shield", "Poison" }
	for i, kind in ipairs(statuses) do
		local st = CardsData.Statuses[kind]
		local chip = UIKit.label({ Text = st.Icon, Font = UIKit.Fonts.Black, TextColor3 = st.Color, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.14 + (i - 1) * 0.24, 0.06), Size = UDim2.fromOffset(44, 44), BackgroundTransparency = 0, BackgroundColor3 = INK,
			ZIndex = 200, Parent = holder }, 26)
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = chip })
		UIKit.stroke(chip, st.Color, 2, 0)
	end
	return holder
end

-- Grille de portraits 3D des habitants.
local function villagers(parent: Instance)
	local holder = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = parent })
	UIKit.new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -10, 0.5, -10), CellPadding = UDim2.fromOffset(14, 14),
		HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Parent = holder })
	local people = {
		{ "Elya", "Elya", Color3.fromRGB(220, 90, 110) },
		{ "Borin", "Borin", Color3.fromRGB(230, 140, 70) },
		{ "Varek", "Varek", Color3.fromRGB(200, 70, 80) },
		{ "Oswin", "Oswin", Color3.fromRGB(200, 140, 60) },
		{ "Maelis", "Maelis", Color3.fromRGB(150, 90, 200) },
		{ "Gaelle", "Gaëlle", Color3.fromRGB(110, 170, 90) },
	}
	for i, person in ipairs(people) do
		local cell = UIKit.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = i, ClipsDescendants = true, Parent = holder })
		UIKit.corner(cell, 14)
		UIKit.gradient(cell, person[3]:Lerp(Color3.new(1, 1, 1), 0.3), person[3]:Lerp(Color3.new(0, 0, 0), 0.6), 90)
		UIKit.stroke(cell, GOLD, 2, 0.2)
		local view = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -26), Parent = cell })
		if not npcSnapshot(view, person[1]) then
			UIKit.label({ Text = string.sub(person[2], 1, 1), Font = UIKit.Fonts.Title, Size = UDim2.fromScale(1, 1), Parent = view }, 60)
		end
		local name = UIKit.label({ Text = person[2], Font = UIKit.Fonts.Black, TextColor3 = CREAM, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 0.25, BackgroundColor3 = INK, Parent = cell }, 17)
		_ = name
	end
	return holder
end

-- Vue 3D d'un lieu du monde, ou des cartes si le lieu n'est pas chargé.
local function place(parent: Instance, path: { string }, dir: Vector3, fallback: { string })
	local holder = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = parent })
	if not snapshot(holder, findPath(table.unpack(path)), Vector3.zero, dir, 38) then
		holder:Destroy()
		return cardFan(parent, fallback)
	end
	return holder
end

-------------------------------------------------------------------------------
-- Chapitres
-------------------------------------------------------------------------------
type Point = { Icon: string, Color: Color3, Title: string, Text: string }
type Chapter = { Key: string, Icon: string, Accent: Color3, Title: string, Text: string, Points: { Point }?, Draw: (Frame) -> () }

local CHAPTERS: { Chapter } = {
	{
		Key = "Bienvenue", Icon = "★", Accent = Color3.fromRGB(170, 120, 255),
		Title = "Bienvenue à Brumeval",
		Text = "Les bêtes arcaniques s'éveillent. Ouvre des boosters, capture des Anima légendaires, affronte les autres dresseurs et complète ton grimoire.",
		Points = {
			{ Icon = "◆", Color = Color3.fromRGB(130, 215, 255), Title = "Les gemmes", Text = "La monnaie du royaume : quêtes, duels et récompenses du jour en rapportent." },
			{ Icon = "★", Color = GOLD, Title = "30 créatures", Text = "De Commun à Légendaire, chacune avec sa capacité unique." },
			{ Icon = "♥", Color = Color3.fromRGB(255, 130, 170), Title = "Ton grimoire", Text = "Le livre en bas de l'écran garde ta collection et tes trésors." },
		},
		Draw = function(f)
			cardFan(f, { "pyrogriff", "solaryx", "glacimar" })
		end,
	},
	{
		Key = "Contrôles", Icon = "◎", Accent = Color3.fromRGB(110, 150, 255),
		Title = "Les contrôles",
		Text = "",
		Draw = function(f)
			local mode = UIKit.inputMode()
			if mode == "Gamepad" then
				drawGamepad(f)
			elseif mode == "Touch" then
				drawPhone(f)
			else
				drawKeyboard(f)
			end
		end,
	},
	{
		Key = "Boosters", Icon = "◆", Accent = Color3.fromRGB(255, 160, 80),
		Title = "Ouvre des boosters",
		Text = "Au cœur de la cité, l'autel arcanique libère trois créatures par booster. Touche le paquet, déchire-le, et retourne tes cartes une à une !",
		Points = {
			{ Icon = "★", Color = Color3.fromRGB(255, 160, 80), Title = "L'autel arcanique", Text = "Au centre de la place, appuie sur E (ou touche l'invite) pour l'utiliser." },
			{ Icon = "◆", Color = Color3.fromRGB(130, 215, 255), Title = "100 gemmes", Text = "Trois créatures par booster. Elya vend aussi des lots et des boosters d'un élément." },
			{ Icon = "×2", Color = Color3.fromRGB(150, 230, 150), Title = "Les doublons", Text = "Borin les rachète ou les fusionne en une carte plus rare." },
		},
		Draw = function(f)
			place(f, { "World", "Arena" }, Vector3.new(0.3, 0.55, -1), { "flamichat", "voltigeai", "umbrelune" })
		end,
	},
	{
		Key = "Duels", Icon = "⚔", Accent = Color3.fromRGB(255, 100, 90),
		Title = "L'art du duel",
		Text = "Trois créatures contre trois, chacun son tour. Chaque Anima a sa propre capacité : à toi de choisir le bon moment.",
		Points = {
			{ Icon = "◆", Color = Color3.fromRGB(130, 215, 255), Title = "L'énergie", Text = "Attaque (+1) et Garde (+2) remplissent ta jauge ; ta capacité la dépense." },
			{ Icon = "★", Color = GOLD, Title = "Statuts", Text = "Brûlure, poison, gel, bouclier, miroir... chaque créature a son effet." },
			{ Icon = "↔", Color = Color3.fromRGB(190, 160, 255), Title = "Les éléments", Text = "Feu > Nature > Eau > Feu. Change de créature pour prendre l'avantage !" },
		},
		Draw = function(f)
			duelScene(f)
		end,
	},
	{
		Key = "Cercle", Icon = "◈", Accent = Color3.fromRGB(150, 110, 255),
		Title = "Le Cercle des Arcanes",
		Text = "À l'est de la cité, le cercle magique accueille les duels. Tu y entres avec ton Anima, sous les yeux des autres dresseurs.",
		Points = {
			{ Icon = "⚔", Color = Color3.fromRGB(255, 120, 100), Title = "Varek", Text = "Défie un autre joueur ou entraîne-toi contre son mannequin." },
			{ Icon = "★", Color = GOLD, Title = "Défi du jour", Text = "Capitaine Rhéa, à la caserne, récompense ta première victoire de la journée." },
			{ Icon = "◎", Color = Color3.fromRGB(130, 215, 255), Title = "Spectateur", Text = "Approche-toi du cercle pendant un duel pour le regarder en direct." },
		},
		Draw = function(f)
			place(f, { "World", "Colosseum" }, Vector3.new(0.55, 0.6, -1), { "umbrelune", "nyxaria", "tonnerrhin" })
		end,
	},
	{
		Key = "Échanges", Icon = "↔", Accent = Color3.fromRGB(110, 210, 160),
		Title = "Le Comptoir des Échanges",
		Text = "Sur la Grand-Place, trois tables attendent les dresseurs. Installez-vous chacun sur un cercle de la même table : l'échange s'ouvre.",
		Points = {
			{ Icon = "◎", Color = Color3.fromRGB(110, 230, 150), Title = "Face à face", Text = "Le cercle devient vert quand tu es dessus. Le quitter annule l'échange." },
			{ Icon = "OK", Color = GOLD, Title = "Prêt, puis Confirmer", Text = "Les offres se verrouillent et un compte à rebours te laisse tout vérifier." },
			{ Icon = "◈", Color = Color3.fromRGB(130, 200, 255), Title = "Protégé", Text = "Une offre modifiée annule les validations : impossible de te piéger." },
		},
		Draw = function(f)
			place(f, { "World", "ComptoirDesEchanges" }, Vector3.new(0.2, 0.7, 1), { "ronceloup", "aquatortue" })
		end,
	},
	{
		Key = "Habitants", Icon = "☺", Accent = Color3.fromRGB(255, 190, 110),
		Title = "Les habitants",
		Text = "Chaque quartier a son habitant : parle-leur (touche E), ils ont tous quelque chose à t'offrir.",
		Points = {
			{ Icon = "◆", Color = Color3.fromRGB(255, 190, 110), Title = "Oswin, aux entrepôts", Text = "Son étal change chaque jour : trois créatures choisies." },
			{ Icon = "★", Color = Color3.fromRGB(190, 140, 255), Title = "Maelis, au donjon", Text = "Réunis toutes les créatures d'un élément pour une belle récompense." },
			{ Icon = "♥", Color = Color3.fromRGB(150, 210, 110), Title = "Gaëlle, à la ferme", Text = "Un panier de gemmes t'attend chaque jour." },
		},
		Draw = function(f)
			villagers(f)
		end,
	},
}

-------------------------------------------------------------------------------
-- Construction
-------------------------------------------------------------------------------
-- L'interface du jeu est en ZIndex global : tout ce qui est dans le tutoriel
-- doit passer au-dessus de son propre fond (ZIndex 30+).
local BASE_Z = 33
local function raise(inst: Instance)
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("GuiObject") and d.ZIndex < BASE_Z - 2 then
			d.ZIndex += BASE_Z
		end
	end
end
function Tutorial.new(parent: Instance, onFinished: () -> ())
	local self = { IsOpen = false, OnClose = onFinished }
	local index = 1
	local busy = false

	local root = UIKit.new("Frame", { Name = "Grimoire", BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), Visible = false,
		Active = true, ZIndex = 30, Parent = parent })
	UIKit.gradient(root, Color3.fromRGB(32, 18, 60), Color3.fromRGB(6, 4, 14), 90)
	self.Root = root

	-- Rayons de lumière qui tournent lentement.
	local rays = {}
	for i = 1, 3 do
		local ray = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.28, 0.45), Size = UDim2.new(0, 120, 2.4, 0),
			BackgroundColor3 = Color3.fromRGB(190, 150, 255), BackgroundTransparency = 0.88, BorderSizePixel = 0, Rotation = i * 60, ZIndex = 30, Parent = root })
		UIKit.new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(1, 1) }), Parent = ray })
		table.insert(rays, ray)
	end
	-- Ciel étoilé scintillant.
	local stars = {}
	for _ = 1, 70 do
		local s = math.random(2, 4)
		local star = UIKit.new("Frame", { Position = UDim2.fromScale(math.random(), math.random()), Size = UDim2.fromOffset(s, s),
			BackgroundColor3 = math.random() < 0.3 and GOLD or Color3.fromRGB(220, 210, 255), BorderSizePixel = 0, ZIndex = 30, Parent = root })
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = star })
		table.insert(stars, { Frame = star, Phase = math.random() * 6, Speed = 0.6 + math.random() * 1.4 })
	end
	-- Vignette.
	local vignette = UIKit.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.fromScale(1, 1), ZIndex = 30, BorderSizePixel = 0, Parent = root })
	UIKit.new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.25, 1),
		NumberSequenceKeypoint.new(0.75, 1), NumberSequenceKeypoint.new(1, 0.2) }), Parent = vignette })

	-- Scène 1280 × 720 adaptée à l'écran.
	local stage = UIKit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(W, H), ZIndex = 31, Parent = root })
	local stageScale = UIKit.new("UIScale", { Parent = stage })
	local function fit()
		local camera = workspace.CurrentCamera
		local v = camera and camera.ViewportSize or Vector2.new(W, H)
		stageScale.Scale = math.clamp(math.min(v.X / W, v.Y / H), 0.4, 1.5)
	end
	fit()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end

	-- Bandeau supérieur.
	local crest = UIKit.label({ Text = "◆  LE GRIMOIRE DU DRESSEUR  ◆", Font = UIKit.Fonts.Black, TextColor3 = GOLD, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(W / 2, 34), Size = UDim2.fromOffset(520, 26), ZIndex = 32, Parent = stage }, 18)
	_ = crest
	local skip = UIKit.button({ Text = "PASSER  ›", Style = "Ghost", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(W - 60, 20),
		Size = UDim2.fromOffset(170, 46), TextSize = 16, Parent = stage, Callback = function()
			self:Close()
		end })
	skip.ZIndex = 32

	-- Vitrine (illustration) : cadre doré et cercle magique tournant derrière.
	local showcase = UIKit.new("Frame", { Position = UDim2.fromOffset(60, 92), Size = UDim2.fromOffset(560, 470), BackgroundColor3 = Color3.new(1, 1, 1),
		ClipsDescendants = true, ZIndex = 32, Parent = stage })
	UIKit.corner(showcase, 22)
	local showcaseGradient = UIKit.gradient(showcase, Color3.fromRGB(70, 50, 120), Color3.fromRGB(16, 10, 32), 90)
	local showcaseStroke = UIKit.stroke(showcase, GOLD, 3, 0)
	local circle = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(440, 440),
		BackgroundTransparency = 1, ZIndex = 32, Parent = showcase })
	UIKit.new("UIAspectRatioConstraint", { Parent = circle })
	for i, r in ipairs({ 1, 0.78, 0.5 }) do
		local ring = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(r, r),
			BackgroundTransparency = 1, ZIndex = 32, Parent = circle })
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = ring })
		UIKit.stroke(ring, Color3.fromRGB(255, 225, 160), i == 1 and 2 or 1, 0.6 + i * 0.08)
	end
	for k = 0, 2 do
		local bar = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.86, 0, 0, 1),
			Rotation = k * 60, BackgroundColor3 = Color3.fromRGB(255, 225, 160), BackgroundTransparency = 0.75, BorderSizePixel = 0, ZIndex = 32, Parent = circle })
		_ = bar
	end
	-- Coins dorés.
	for _, c in ipairs({ Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) }) do
		local jewel = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(c.X, c.X == 0 and 16 or -16, c.Y, c.Y == 0 and 16 or -16),
			Size = UDim2.fromOffset(14, 14), Rotation = 45, BackgroundColor3 = Color3.fromRGB(200, 35, 60), ZIndex = 40, Parent = showcase })
		UIKit.stroke(jewel, GOLD, 2, 0)
	end
	local art = UIKit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(24, 24), Size = UDim2.new(1, -48, 1, -48), ZIndex = 33, Parent = showcase })

	-- Colonne de texte.
	local column = UIKit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(670, 92), Size = UDim2.fromOffset(550, 470), ZIndex = 32, Parent = stage })

	-- Frise des chapitres.
	local timeline = UIKit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(300, 590), Size = UDim2.fromOffset(680, 80), ZIndex = 32, Parent = stage })
	local track = UIKit.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 30, 0, 26), Size = UDim2.new(1, -60, 0, 3),
		BackgroundColor3 = Color3.fromRGB(80, 65, 120), BorderSizePixel = 0, ZIndex = 32, Parent = timeline })
	local progress = UIKit.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 33, Parent = track })
	local nodes = {}
	local goTo

	for i, chapter in ipairs(CHAPTERS) do
		local x = (i - 1) / (#CHAPTERS - 1)
		local node = UIKit.new("TextButton", { Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(x, 30 - x * 60, 0, 26), Size = UDim2.fromOffset(40, 40), BackgroundColor3 = Color3.fromRGB(40, 30, 70), ZIndex = 34,
			Selectable = true, Parent = timeline })
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = node })
		local stroke = UIKit.stroke(node, Color3.fromRGB(110, 95, 160), 2, 0)
		local icon = UIKit.label({ Text = chapter.Icon, Font = UIKit.Fonts.Black, TextColor3 = MUTED, Size = UDim2.fromScale(1, 1), ZIndex = 35, Parent = node }, 18)
		local label = UIKit.label({ Text = chapter.Key, Font = UIKit.Fonts.Bold, TextColor3 = MUTED, AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(x, 30 - x * 60, 0, 52), Size = UDim2.fromOffset(110, 18), ZIndex = 34, Parent = timeline }, 13)
		local scale = UIKit.new("UIScale", { Parent = node })
		node.Activated:Connect(function()
			goTo(i)
		end)
		nodes[i] = { Node = node, Stroke = stroke, Icon = icon, Label = label, Scale = scale }
	end

	local prev = UIKit.button({ Text = "‹  PRÉCÉDENT", Style = "Ghost", Position = UDim2.fromOffset(60, 604), Size = UDim2.fromOffset(200, 54), TextSize = 17,
		Parent = stage, Callback = function()
			goTo(index - 1)
		end })
	local nextButton = UIKit.button({ Text = "SUIVANT  ›", Style = "Gold", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(W - 60, 604),
		Size = UDim2.fromOffset(220, 54), TextSize = 18, Parent = stage, Callback = function()
			if index < #CHAPTERS then
				goTo(index + 1)
			else
				self:Close()
			end
		end })

	raise(stage)

	-- Point clé : pastille d'icône, titre, texte.
	local function point(parent: Instance, p: Point, order: number)
		local row = UIKit.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, Size = UDim2.new(1, 0, 0, 78), LayoutOrder = order,
			ZIndex = 33, Parent = parent })
		UIKit.corner(row, 14)
		UIKit.gradient(row, Color3.fromRGB(46, 34, 80), Color3.fromRGB(22, 16, 40), 0)
		UIKit.stroke(row, p.Color, 1.5, 0.55)
		local chip = UIKit.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(50, 50),
			BackgroundColor3 = p.Color, ZIndex = 34, Parent = row })
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = chip })
		UIKit.gradient(chip, p.Color:Lerp(Color3.new(1, 1, 1), 0.3), p.Color:Lerp(Color3.new(0, 0, 0), 0.35), 90)
		UIKit.stroke(chip, Color3.new(1, 1, 1), 2, 0.3)
		UIKit.label({ Text = p.Icon, Font = UIKit.Fonts.Black, TextColor3 = INK, Size = UDim2.fromScale(1, 1), ZIndex = 35, Parent = chip }, 24)
		UIKit.label({ Text = p.Title, Font = UIKit.Fonts.Black, TextColor3 = CREAM, Position = UDim2.fromOffset(80, 10), Size = UDim2.new(1, -96, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34, Parent = row }, 19)
		UIKit.label({ Text = p.Text, Font = UIKit.Fonts.Body, TextColor3 = MUTED, Position = UDim2.fromOffset(80, 34), Size = UDim2.new(1, -96, 0, 36),
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 34, Parent = row }, 15)
	end

	-- Légende des contrôles (chapitre 2), en pastilles colorées.
	local function controls(parent: Instance)
		local mode = UIKit.inputMode()
		local legend = if mode == "Gamepad" then gamepadLegend() else LEGENDS[mode] or LEGENDS.Keyboard
		local list = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 300), LayoutOrder = 3, ZIndex = 33, Parent = parent })
		UIKit.new("UIGridLayout", { CellSize = UDim2.new(0.5, -6, 0, 52), CellPadding = UDim2.fromOffset(12, 10), SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = list })
		for i, entry in ipairs(legend) do
			local row = UIKit.new("Frame", { BackgroundColor3 = Color3.fromRGB(32, 24, 58), LayoutOrder = i, ZIndex = 33, Parent = list })
			UIKit.corner(row, 12)
			local chip = UIKit.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0), Size = UDim2.new(0.36, 0, 1, -12),
				BackgroundColor3 = entry[1], ZIndex = 34, Parent = row })
			UIKit.corner(chip, 9)
			UIKit.label({ Text = entry[2], Font = UIKit.Fonts.Black, TextColor3 = INK, Size = UDim2.fromScale(1, 1), ZIndex = 35, Parent = chip }, 14)
			UIKit.label({ Text = entry[3], Font = UIKit.Fonts.Bold, TextColor3 = CREAM, Position = UDim2.new(0.36, 14, 0, 4), Size = UDim2.new(0.64, -20, 1, -8),
				TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34, Parent = row }, 14)
		end
		return legend.Title
	end

	local current: Frame? = nil
	local function render(direction: number)
		local chapter = CHAPTERS[index]
		-- Ancienne page : glisse et s'efface.
		local old = current
		if old then
			UIKit.fade(old, false, 0.2)
			UIKit.tween(old, 0.25, { Position = UDim2.fromOffset(-40 * direction, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(0.26, function()
				old:Destroy()
			end)
		end
		for _, child in ipairs(art:GetChildren()) do
			child:Destroy()
		end

		-- Couleurs de la vitrine.
		local a = chapter.Accent
		showcaseGradient.Color = ColorSequence.new(a:Lerp(Color3.new(0, 0, 0), 0.35), Color3.fromRGB(14, 9, 28))
		UIKit.tween(showcaseStroke, 0.3, { Color = a:Lerp(GOLD, 0.5) })
		local ok, err = pcall(chapter.Draw, art)
		if not ok then
			warn("[Tutorial]", err)
		end
		raise(art)
		local pop = art:FindFirstChildOfClass("UIScale") or UIKit.new("UIScale", { Parent = art })
		pop.Scale = 0.9
		UIKit.tween(pop, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)

		-- Nouvelle page de texte.
		local page = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(50 * direction, 0), ZIndex = 32,
			Parent = column })
		UIKit.new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })
		UIKit.label({ Text = string.format("CHAPITRE %02d  /  %02d", index, #CHAPTERS), Font = UIKit.Fonts.Black, TextColor3 = a:Lerp(Color3.new(1, 1, 1), 0.3),
			Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1, ZIndex = 33, Parent = page }, 16)
		local title = UIKit.label({ Text = chapter.Title, Font = UIKit.Fonts.Title, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, 0, 0, 64),
			TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2, ZIndex = 33, Parent = page }, 54)
		UIKit.new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 248, 225), GOLD), Rotation = 90, Parent = title })
		UIKit.new("UIStroke", { Color = Color3.fromRGB(50, 20, 8), Thickness = 2, Parent = title })
		if chapter.Key == "Contrôles" then
			local device = controls(page)
			UIKit.label({ Text = "Tu joues avec : " .. string.lower(device) .. ". L'illustration suit ta manette, ton clavier ou ton écran.", Font = UIKit.Fonts.Body,
				TextColor3 = MUTED, Size = UDim2.new(1, 0, 0, 40), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 4, ZIndex = 33, Parent = page }, 16)
		else
			UIKit.label({ Text = chapter.Text, Font = UIKit.Fonts.Body, TextColor3 = CREAM, Size = UDim2.new(1, 0, 0, 70), TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = 3, ZIndex = 33, Parent = page }, 19)
			for i, p in ipairs(chapter.Points or {}) do
				point(page, p, 3 + i)
			end
		end
		raise(page)
		UIKit.fade(page, true, 0.35)
		UIKit.tween(page, 0.4, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quint)
		current = page

		-- Frise, boutons.
		UIKit.tween(progress, 0.4, { Size = UDim2.fromScale((index - 1) / (#CHAPTERS - 1), 1) }, Enum.EasingStyle.Quint)
		for i, n in ipairs(nodes) do
			local active, done = i == index, i < index
			UIKit.tween(n.Node, 0.25, { BackgroundColor3 = active and CHAPTERS[i].Accent or (done and GOLD_DARK or Color3.fromRGB(40, 30, 70)) })
			n.Stroke.Color = (active or done) and GOLD or Color3.fromRGB(110, 95, 160)
			n.Icon.TextColor3 = (active or done) and INK or MUTED
			n.Label.TextColor3 = active and GOLD or (done and CREAM or MUTED)
			UIKit.tween(n.Scale, 0.3, { Scale = active and 1.3 or 1 }, Enum.EasingStyle.Back)
		end
		prev.Visible = index > 1
		local label = nextButton:FindFirstChild("Label")
		if label then
			label.Text = index < #CHAPTERS and "SUIVANT  ›" or "C'EST PARTI !"
		end
		UIKit.focus(nextButton)
	end

	function goTo(i: number)
		if busy or i < 1 or i > #CHAPTERS or i == index then
			return
		end
		busy = true
		local direction = i > index and 1 or -1
		index = i
		UIKit.playSound("PageTurn", 0.35, 1.1)
		render(direction)
		task.delay(0.3, function()
			busy = false
		end)
	end

	-- Accès direct à un chapitre (ex. « Revoir les duels » depuis un PNJ).
	function self:GoTo(i: number)
		goTo(i)
	end

	-- Animation du décor.
	RunService.RenderStepped:Connect(function(dt)
		if not root.Visible then
			return
		end
		local t = os.clock()
		circle.Rotation += dt * 8
		for i, ray in ipairs(rays) do
			ray.Rotation += dt * (3 + i)
		end
		for _, s in ipairs(stars) do
			s.Frame.BackgroundTransparency = 0.35 + 0.55 * (0.5 + 0.5 * math.sin(t * s.Speed + s.Phase))
		end
	end)

	-- Clavier, manette, balayage tactile.
	UserInputService.InputBegan:Connect(function(input, processed)
		if not self.IsOpen then
			return
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.Right or k == Enum.KeyCode.D or k == Enum.KeyCode.ButtonR1 then
			goTo(index + 1)
		elseif k == Enum.KeyCode.Left or k == Enum.KeyCode.Q or k == Enum.KeyCode.ButtonL1 then
			goTo(index - 1)
		elseif (k == Enum.KeyCode.Escape or k == Enum.KeyCode.ButtonB) and not processed then
			self:Close()
		end
	end)
	UserInputService.TouchSwipe:Connect(function(direction)
		if not self.IsOpen then
			return
		end
		if direction == Enum.SwipeDirection.Left then
			goTo(index + 1)
		elseif direction == Enum.SwipeDirection.Right then
			goTo(index - 1)
		end
	end)
	-- L'illustration des contrôles suit le dernier périphérique utilisé.
	local lastMode = UIKit.inputMode()
	UserInputService.LastInputTypeChanged:Connect(function()
		local mode = UIKit.inputMode()
		if self.IsOpen and CHAPTERS[index].Key == "Contrôles" and mode ~= lastMode then
			render(0)
		end
		lastMode = mode
	end)

	function self:Open()
		if self.IsOpen then
			return
		end
		self.IsOpen = true
		index = 1
		root.Visible = true
		fit()
		UIKit.fade(root, true, 0.4)
		stage.Position = UDim2.fromScale(0.5, 0.53)
		UIKit.tween(stage, 0.6, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Quint)
		render(1)
		UIKit.playSound("BookOpen", 0.5)
	end

	function self:Close()
		if not self.IsOpen then
			return
		end
		self.IsOpen = false
		UIKit.fade(root, false, 0.3)
		task.delay(0.32, function()
			if not self.IsOpen then
				root.Visible = false
			end
		end)
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(root) then
			GuiService.SelectedObject = nil
		end
		if self.OnClose then
			self.OnClose()
		end
	end

	return self
end

return Tutorial
