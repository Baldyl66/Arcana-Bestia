-- Tutoriel illustré en 3 pages :
--   1. Contrôles : clavier, manette ou téléphone dessiné, touches colorées
--      par fonction (s'adapte au dernier périphérique utilisé).
--   2. Ton aventure : vues 3D du jeu (autel, village, sage, bestiaire).
--   3. Les habitants : portraits 3D des PNJ et un secret à découvrir.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CardsData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CardsData"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))
local CardView = require(script.Parent:WaitForChild("CardView"))

local Tutorial = {}

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
	local pivot = holderModel:GetPivot()
	holderModel:PivotTo(camera.Magnitude == 0 and (pivot - pivot.Position) or CFrame.new())
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

-- Carte illustrée : image en haut, titre et texte en dessous.
local function illustratedCard(parent: Instance, order: number, title: string, body: string, accent: Color3, fill: (image: Frame) -> boolean)
	local cardFrame = UIKit.new("Frame", {
		BackgroundColor3 = UIKit.Colors.Panel,
		BackgroundTransparency = 0.1,
		LayoutOrder = order,
		Parent = parent,
	})
	UIKit.corner(cardFrame, 16)
	UIKit.stroke(cardFrame, accent, 1.5, 0.35)
	local image = UIKit.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(0.42, -8, 1, -16),
		ClipsDescendants = true,
		Parent = cardFrame,
	})
	UIKit.stroke(image, accent, 1.5, 0.2)
	UIKit.corner(image, 12)
	UIKit.gradient(image, accent:Lerp(Color3.new(1, 1, 1), 0.35), accent:Lerp(Color3.new(0, 0, 0), 0.55), 90)
	if not fill(image) then
		UIKit.label({
			Text = string.sub(title, 1, 1),
			Font = UIKit.Fonts.Title,
			Size = UDim2.fromScale(1, 1),
			Parent = image,
		}, 64)
	end
	UIKit.label({
		Text = title,
		Font = UIKit.Fonts.Black,
		TextColor3 = UIKit.Colors.Gold,
		Position = UDim2.new(0.42, 12, 0, 14),
		Size = UDim2.new(0.58, -24, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = cardFrame,
	}, 20)
	UIKit.label({
		Text = body,
		Font = UIKit.Fonts.Body,
		Position = UDim2.new(0.42, 12, 0, 46),
		Size = UDim2.new(0.58, -24, 1, -58),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = cardFrame,
	}, 16)
end

-------------------------------------------------------------------------------
-- Panneau
-------------------------------------------------------------------------------
function Tutorial.new(parent: Instance, onFinished: () -> ())
	local panel = UIKit.panel(parent, "BIENVENUE, DRESSEUR !")
	local content = panel.Content
	local page = 1
	local pageCount = 3

	local pageTitle = UIKit.label({
		Text = "",
		Font = UIKit.Fonts.Black,
		TextColor3 = UIKit.Colors.Gold,
		Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = content,
	}, 22)

	local body = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 1, -104),
		Parent = content,
	})

	local nav = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 58),
		Parent = content,
	})
	local dots = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(100, 14),
		Parent = nav,
	})
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = dots,
	})
	local dotFrames = {}
	for i = 1, pageCount do
		local dot = UIKit.new("Frame", { BackgroundColor3 = UIKit.Colors.SubText, Size = UDim2.fromOffset(12, 12), LayoutOrder = i, Parent = dots })
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = dot })
		dotFrames[i] = dot
	end

	local render

	local prevButton = UIKit.button({
		Text = "PRÉCÉDENT",
		Style = "Ghost",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(190, 52),
		TextSize = 18,
		Parent = nav,
		Callback = function()
			page = math.max(1, page - 1)
			render()
		end,
	})
	local nextButton = UIKit.button({
		Text = "SUIVANT",
		Style = "Gold",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(220, 52),
		TextSize = 18,
		Parent = nav,
		Callback = function()
			if page < pageCount then
				page += 1
				render()
			else
				panel:Close()
			end
		end,
	})

	local function renderControls()
		local mode = UIKit.inputMode()
		local legend = if mode == "Gamepad" then gamepadLegend() else LEGENDS[mode] or LEGENDS.Keyboard
		pageTitle.Text = "LES CONTRÔLES  •  " .. legend.Title
		pageTitle.Size = UDim2.new(0.56, -8, 0, 26)

		local stage = UIKit.new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			Size = UDim2.new(0.56, -8, 1, 0),
			Parent = body,
		})
		UIKit.corner(stage, 16)
		UIKit.gradient(stage, Color3.fromRGB(50, 40, 90), Color3.fromRGB(18, 14, 34), 90)
		UIKit.stroke(stage, UIKit.Colors.Accent, 1.5, 0.4)
		UIKit.padding(stage, 16)
		if mode == "Gamepad" then
			drawGamepad(stage)
		elseif mode == "Touch" then
			drawPhone(stage)
		else
			drawKeyboard(stage)
		end

		local list = UIKit.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0.44, -8, 1, 0),
			Parent = body,
		})
		UIKit.new("UIListLayout", {
			Padding = UDim.new(0.012, 0),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Parent = list,
		})
		local count = #legend
		for index, entry in ipairs(legend) do
			local row = UIKit.new("Frame", {
				BackgroundColor3 = UIKit.Colors.Panel,
				BackgroundTransparency = 0.2,
				Size = UDim2.new(1, 0, 1 / count, -6),
				LayoutOrder = index,
				Parent = list,
			})
			UIKit.corner(row, 10)
			local chip = box(row, {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 6, 0.5, 0),
				Size = UDim2.new(0.3, 0, 1, -10),
				BackgroundColor3 = entry[1],
			}, UDim.new(0.3, 0))
			text(chip, entry[2], Color3.fromRGB(25, 15, 45), 15)
			UIKit.label({
				Text = entry[3],
				Font = UIKit.Fonts.Bold,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0.3, 16, 0.5, 0),
				Size = UDim2.new(0.7, -24, 1, -10),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = row,
			}, 16)
		end
	end

	local function grid()
		return UIKit.new("UIGridLayout", {
			CellSize = UDim2.new(0.5, -8, 0.5, -8),
			CellPadding = UDim2.fromOffset(16, 16),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = body,
		})
	end

	local function renderAdventure()
		pageTitle.Text = "TON AVENTURE"
		pageTitle.Size = UDim2.new(1, 0, 0, 26)
		grid()
		illustratedCard(body, 1, "L'autel arcanique", "Au centre de l'arène : approche-toi de l'autel pour ouvrir un booster et découvrir une créature.",
			Color3.fromRGB(110, 200, 255), function(image)
				return snapshot(image, findPath("World", "Arena"), Vector3.zero, Vector3.new(0.3, 0.55, -1), 40)
			end)
		illustratedCard(body, 2, "La cité de Brumeval", "La ville entoure l'arène : Grand-Place au sud, Artisans à l'ouest, Mages au nord, Colisée à l'est.",
			Color3.fromRGB(255, 190, 110), function(image)
				return snapshot(image, findPath("World", "Village", "Props", "Fountain"), Vector3.zero, Vector3.new(0.4, 0.45, -1), 40)
			end)
		illustratedCard(body, 3, "Les épreuves", "Maître Orin te confie des défis d'exploration et de collection, avec de belles récompenses.",
			Color3.fromRGB(140, 120, 255), function(image)
				return npcSnapshot(image, "Orin")
			end)
		illustratedCard(body, 4, "Ton grimoire", "Le livre en bas de l'écran regroupe ton bestiaire, les récompenses quotidiennes, les boosters et la boutique.",
			Color3.fromRGB(255, 205, 90), function(image)
				local card = CardsData.CardById.solaryx
				if not card then
					return false
				end
				local view = CardView.create(card, { Size = UDim2.fromScale(0.9, 0.9), Parent = image })
				view.AnchorPoint = Vector2.new(0.5, 0.5)
				view.Position = UDim2.fromScale(0.5, 0.5)
				return true
			end)
	end

	local function renderVillagers()
		pageTitle.Text = "LES HABITANTS"
		pageTitle.Size = UDim2.new(1, 0, 0, 26)
		grid()
		local people = {
			{ "Elya", "Elya, marchande", "Lots de 3 boosters et boosters d'un élément au choix.", Color3.fromRGB(220, 90, 110) },
			{ "Borin", "Borin, forgeron", "Rachète tes doublons ou les fusionne en une carte plus rare.", Color3.fromRGB(230, 140, 70) },
			{ "Varek", "Varek, maître de l'arène", "Défie les autres dresseurs ou entraîne-toi contre son mannequin.", Color3.fromRGB(110, 190, 130) },
		}
		for index, person in ipairs(people) do
			illustratedCard(body, index, person[2], person[3], person[4], function(image)
				return npcSnapshot(image, person[1])
			end)
		end
		illustratedCard(body, 4, "Sélène, gardienne des cristaux", "Dans son sanctuaire du quartier des Mages, elle vend des boosters mystiques.",
			Color3.fromRGB(80, 160, 190), function(image)
				return npcSnapshot(image, "Selene")
			end)
	end

	function render()
		for _, child in ipairs(body:GetChildren()) do
			child:Destroy()
		end
		if page == 1 then
			renderControls()
		elseif page == 2 then
			renderAdventure()
		else
			renderVillagers()
		end
		for i, dot in ipairs(dotFrames) do
			UIKit.tween(dot, 0.2, {
				BackgroundColor3 = i == page and UIKit.Colors.Gold or UIKit.Colors.SubText,
				Size = i == page and UDim2.fromOffset(28, 12) or UDim2.fromOffset(12, 12),
			})
		end
		prevButton.Visible = page > 1
		nextButton.Text = page < pageCount and "SUIVANT" or "C'EST PARTI !"
		UIKit.focus(nextButton)
	end

	-- L'illustration suit le dernier périphérique utilisé.
	local lastMode = UIKit.inputMode()
	UserInputService.LastInputTypeChanged:Connect(function()
		local mode = UIKit.inputMode()
		if panel.IsOpen and page == 1 and mode ~= lastMode then
			render()
		end
		lastMode = mode
	end)

	local baseOpen = panel.Open
	function panel:Open()
		page = 1
		baseOpen(self)
		render()
	end
	panel.OnClose = onFinished

	return panel
end

return Tutorial
