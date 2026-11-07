local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local BookController = {}

local player = Players.LocalPlayer
local equippedTool: Tool? = nil
local state = "hand"
local animation = nil
local openCallback: (() -> ())? = nil
local closeCallback: (() -> ())? = nil
local actionCallback: ((string) -> ())? = nil
local previousMouseIconEnabled: boolean? = nil

local function isGamepadInput(inputType: Enum.UserInputType): boolean
	return inputType == Enum.UserInputType.Gamepad1
		or inputType == Enum.UserInputType.Gamepad2
		or inputType == Enum.UserInputType.Gamepad3
		or inputType == Enum.UserInputType.Gamepad4
end

local RISE_TIME = 0.55
local OPEN_TIME = 0.8
local READING_PITCH = 22
local WALK_SPEED = 20

local function smooth(value: number): number
	value = math.clamp(value, 0, 1)
	return value * value * (3 - 2 * value)
end

local function setFrozen(frozen: boolean)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if frozen then
		ContextActionService:BindActionAtPriority(
			"ArcanaBookFreeze",
			function()
				return Enum.ContextActionResult.Sink
			end,
			false,
			Enum.ContextActionPriority.High.Value + 100,
			Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
			Enum.KeyCode.Z, Enum.KeyCode.Q, Enum.KeyCode.Up, Enum.KeyCode.Down,
			Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.Space
		)
	else
		ContextActionService:UnbindAction("ArcanaBookFreeze")
	end
	if humanoid then
		humanoid.WalkSpeed = if frozen then 0 else WALK_SPEED
		humanoid.JumpHeight = if frozen then 0 else (game:GetService("StarterPlayer").CharacterJumpHeight or 7.2)
		humanoid.AutoRotate = not frozen
	end
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.Anchored = frozen
	end
end

local function hideCharacter(hidden: boolean)
	local character = player.Character
	if not character then
		return
	end
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			descendant.LocalTransparencyModifier = if hidden then 1 else 0
		end
		-- Le personnage (tête, accessoires) est entre la caméra et le livre :
		-- il ne doit pas intercepter les clics destinés aux pages.
		if descendant:IsA("BasePart") then
			if hidden then
				descendant:SetAttribute("BookCanQuery", descendant.CanQuery)
				descendant.CanQuery = false
			elseif descendant:GetAttribute("BookCanQuery") ~= nil then
				descendant.CanQuery = descendant:GetAttribute("BookCanQuery")
				descendant:SetAttribute("BookCanQuery", nil)
			end
		end
	end
end

local function findPart(model: Model, name: string): BasePart?
	local part = model:FindFirstChild(name, true)
	if part and part:IsA("BasePart") then
		return part
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local descendantName = string.lower(descendant.Name)
			local expectedName = string.lower(name)
			if descendantName == expectedName
				or descendantName == expectedName .. "_node"
				or string.match(descendantName, "^" .. expectedName .. "_node%d*$") then
				return descendant
			end
		end
	end
	return nil
end

-- Pages intérieures dans le style du grimoire (parchemin, double cadre rouge,
-- chapitres encadrés), avec le contenu d'Arcana Bestia.
local SERIF_BOLD = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)
local SERIF_ITALIC = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Regular, Enum.FontStyle.Italic)
local INK = Color3.fromRGB(58, 36, 24)
local RED = Color3.fromRGB(140, 38, 30)
local GOLD = Color3.fromRGB(205, 160, 75)
local PAPER = Color3.fromRGB(240, 226, 196)
local CARD = Color3.fromRGB(248, 238, 215)

local function frame(parent: Instance, props: { [string]: any }, className: string?): Frame
	local f = Instance.new(className or "Frame") :: any
	if className == "TextButton" then
		f.Text = ""
		f.AutoButtonColor = false
	end
	f.BorderSizePixel = 0
	for key, value in pairs(props) do
		(f :: any)[key] = value
	end
	f.Parent = parent
	return f
end

local function label(parent: Instance, text: string, size: number, font: Font, color: Color3, position: UDim2, dimensions: UDim2,
	align: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.FontFace = font
	l.TextColor3 = color
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	l.Position = position
	l.Size = dimensions
	l.Parent = parent
	return l
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function diamond(parent: Instance, x: number, y: number, size: number, color: Color3)
	frame(parent, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(size, size),
		Rotation = 45, BackgroundColor3 = color })
end

-- Fond de page : parchemin, double filet rouge et losanges aux coins.
local function createPage(name: string, part: BasePart, numeral: string): (SurfaceGui, Frame)
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Adornee = part
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(460, 630)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Enabled = false
	gui.ResetOnSpawn = false
	-- Dans le PlayerGui (et non sur la pièce) pour recevoir les clics.
	gui.Parent = player:WaitForChild("PlayerGui")
	local page = frame(gui, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = PAPER })
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(250, 240, 215), Color3.fromRGB(226, 206, 168))
	grad.Rotation = 60
	grad.Parent = page
	local outer = frame(page, { Position = UDim2.fromOffset(18, 18), Size = UDim2.new(1, -36, 1, -36), BackgroundTransparency = 1 })
	stroke(outer, RED, 2)
	local inner = frame(page, { Position = UDim2.fromOffset(26, 26), Size = UDim2.new(1, -52, 1, -52), BackgroundTransparency = 1 })
	stroke(inner, RED, 1)
	for _, c in ipairs({ { 18, 18 }, { 442, 18 }, { 18, 612 }, { 442, 612 } }) do
		diamond(page, c[1], c[2], 9, RED)
	end
	label(page, "— " .. numeral .. " —", 16, SERIF_BOLD, Color3.fromRGB(120, 90, 70), UDim2.fromOffset(0, 40), UDim2.new(1, 0, 0, 20))
	return gui, page
end

-- Titre de page en bas : ornement, sous-titre en italique, grand titre.
local function pageTitle(page: Frame, title: string, subtitle: string)
	frame(page, { Position = UDim2.fromOffset(120, 490), Size = UDim2.fromOffset(90, 2), BackgroundColor3 = RED })
	frame(page, { Position = UDim2.fromOffset(250, 490), Size = UDim2.fromOffset(90, 2), BackgroundColor3 = RED })
	diamond(page, 230, 491, 8, RED)
	label(page, subtitle, 15, SERIF_ITALIC, Color3.fromRGB(110, 80, 60), UDim2.fromOffset(0, 504), UDim2.new(1, 0, 0, 22))
	label(page, title, 46, SERIF_BOLD, INK, UDim2.fromOffset(0, 528), UDim2.new(1, 0, 0, 56))
end

-- Clic sur un bouton du livre : petit enfoncement, puis la fonction donnée.
local function clickable(button: GuiButton, onClick: () -> ())
	button.Selectable = true
	local scale = Instance.new("UIScale")
	scale.Parent = button
	button.MouseEnter:Connect(function()
		scale.Scale = 1.03
	end)
	button.MouseLeave:Connect(function()
		scale.Scale = 1
	end)
	button.Activated:Connect(function()
		scale.Scale = 0.97
		task.delay(0.08, function()
			scale.Scale = 1
		end)
		onClick()
	end)
end

local function selectable(button: GuiButton)
	button.Selectable = true
end

local function act(action: string): () -> ()
	return function()
		if actionCallback then
			actionCallback(action)
		end
	end
end

-- Chapitre : cadre double, médaillon, titre, sous-titre et chevron.
local function chapter(page: Instance, y: number, title: string, subtitle: string, icon: string, onClick: () -> (), highlighted: boolean?)
	local box = frame(page, { Position = UDim2.fromOffset(44, y), Size = UDim2.new(1, -88, 0, 80),
		BackgroundColor3 = highlighted and RED or CARD }, "TextButton")
	clickable(box :: any, onClick)
	stroke(box, highlighted and GOLD or INK, 2)
	local inside = frame(box, { Position = UDim2.fromOffset(5, 5), Size = UDim2.new(1, -10, 1, -10), BackgroundTransparency = 1 })
	stroke(inside, highlighted and GOLD or Color3.fromRGB(150, 130, 110), 1)
	local medal = frame(box, { Position = UDim2.fromOffset(16, 12), Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = highlighted and Color3.fromRGB(120, 30, 24) or Color3.fromRGB(240, 228, 204) })
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = medal
	stroke(medal, highlighted and GOLD or Color3.fromRGB(170, 150, 125), 1)
	label(medal, icon, 28, SERIF_BOLD, highlighted and GOLD or Color3.fromRGB(150, 110, 50), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
	local text = highlighted and Color3.fromRGB(250, 235, 205) or INK
	label(box, subtitle, 13, SERIF_ITALIC, text, UDim2.fromOffset(86, 14), UDim2.new(1, -130, 0, 18), Enum.TextXAlignment.Left)
	label(box, title, 24, SERIF_BOLD, text, UDim2.fromOffset(86, 32), UDim2.new(1, -130, 0, 32), Enum.TextXAlignment.Left)
	label(box, "›", 30, SERIF_BOLD, highlighted and GOLD or RED, UDim2.new(1, -40, 0, 20), UDim2.fromOffset(24, 36))
end

-- Ligne d'offre : fanion coloré, nom, détail et cartouche rouge (prix ou action).
local function offerRow(page: Instance, y: number, height: number, title: string, detail: string, tagText: string, color: Color3,
	onClick: (() -> ())?, icon: string?)
	local box = frame(page, { Position = UDim2.fromOffset(44, y), Size = UDim2.new(1, -88, 0, height), BackgroundColor3 = CARD },
		"TextButton")
	if onClick then
		clickable(box :: any, onClick)
	else
		selectable(box :: any)
	end
	stroke(box, Color3.fromRGB(150, 130, 110), 1)
	local flagH = height - 20
	local flag = frame(box, { Position = UDim2.fromOffset(18, 10), Size = UDim2.fromOffset(math.floor(flagH * 0.68), flagH), BackgroundColor3 = color })
	stroke(flag, GOLD, 2)
	label(flag, icon or "★", math.floor(flagH * 0.4), SERIF_BOLD, GOLD, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
	local textX = 30 + math.floor(flagH * 0.68)
	label(box, detail, 13, SERIF_ITALIC, Color3.fromRGB(110, 80, 60), UDim2.fromOffset(textX, height / 2 - 22), UDim2.fromOffset(180, 18),
		Enum.TextXAlignment.Left)
	local name = label(box, title, 17, SERIF_BOLD, INK, UDim2.fromOffset(textX, height / 2 - 4), UDim2.fromOffset(180, 26), Enum.TextXAlignment.Left)
	name.TextScaled = true
	if tagText ~= "" then
		local tag = frame(box, { Position = UDim2.new(1, -112, 0.5, -20), Size = UDim2.fromOffset(98, 40), BackgroundColor3 = RED })
		stroke(tag, GOLD, 2)
		local t = label(tag, tagText, 17, SERIF_BOLD, Color3.fromRGB(250, 220, 150), UDim2.fromOffset(4, 0), UDim2.new(1, -8, 1, 0))
		t.TextScaled = true
	end
	return box
end

---------------------------------------------------------------------------
-- Chapitres du carnet : la page de gauche choisit, la page de droite affiche.
---------------------------------------------------------------------------
local CardsData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CardsData"))
local ShopData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("ShopData"))
local CardView = require(script.Parent:WaitForChild("UI"):WaitForChild("CardView"))
local UIKit = require(script.Parent:WaitForChild("UI"):WaitForChild("UIKit"))

local profile: any = nil
local selected = "Boosters"
local pages: { Left: Frame, Right: Frame, LeftContent: Frame?, RightContent: Frame? }? = nil
local CHAPTERS = {
	{ Id = "Bestiaire", Title = "BESTIAIRE", Subtitle = "Toutes tes créatures", Icon = "❖" },
	{ Id = "Recompenses", Title = "RÉCOMPENSES", Subtitle = "Cadeaux quotidiens", Icon = "♥" },
	{ Id = "Boosters", Title = "BOOSTERS", Subtitle = "Ouvre de nouveaux paquets", Icon = "★" },
	{ Id = "Boutique", Title = "BOUTIQUE", Subtitle = "Offres de gemmes", Icon = "◆" },
}

local function pageButtons(container: Frame?): { GuiButton }
	local result = {}
	if not container then
		return result
	end
	for _, child in ipairs(container:GetDescendants()) do
		if child:IsA("GuiButton") and child.Visible and child.Active then
			table.insert(result, child)
		end
	end
	return result
end

local function configureNavigation()
	if not pages then
		return
	end
	local leftButtons = pageButtons(pages.LeftContent)
	local rightButtons = pageButtons(pages.RightContent)
	for index, button in ipairs(leftButtons) do
		button.NextSelectionUp = leftButtons[index - 1] or leftButtons[#leftButtons]
		button.NextSelectionDown = leftButtons[index + 1] or leftButtons[1]
		button.NextSelectionLeft = button
		button.NextSelectionRight = rightButtons[1]
	end
	for index, button in ipairs(rightButtons) do
		if selected == "Bestiaire" then
			local column = (index - 1) % 2
			local rowStart = index - column
			button.NextSelectionUp = rightButtons[index - 2] or button
			button.NextSelectionDown = rightButtons[index + 2] or button
			button.NextSelectionLeft = if column == 0 then leftButtons[#leftButtons] else rightButtons[index - 1]
			button.NextSelectionRight = rightButtons[index + 1] or rightButtons[rowStart]
		else
			button.NextSelectionUp = rightButtons[index - 1] or rightButtons[#rightButtons]
			button.NextSelectionDown = rightButtons[index + 1] or rightButtons[1]
			button.NextSelectionLeft = leftButtons[#leftButtons]
			button.NextSelectionRight = button
		end
	end
end

local function focusSelectedChapter()
	if not pages or not pages.LeftContent then
		return
	end
	local chapterIndex = 1
	for index, info in ipairs(CHAPTERS) do
		if info.Id == selected then
			chapterIndex = index
			break
		end
	end
	local buttons = pageButtons(pages.LeftContent)
	UIKit.select(buttons[chapterIndex])
end

local render: () -> ()

local RIGHT_PAGES = {}
local showCardDetail: (any, boolean) -> ()

function RIGHT_PAGES.Boosters(content: Frame)
	offerRow(content, 76, 80, "BOOSTER ARCANA", "3 créatures", "100 ◆", Color3.fromRGB(60, 70, 140), act("Boosters"))
	offerRow(content, 172, 80, "BOOSTER ÉLÉMENTAIRE", "Chez Elya, Grand-Place", "180 ◆", Color3.fromRGB(150, 45, 35), act("Elya"))
	offerRow(content, 268, 80, "LOT DE TROIS", "Chez Elya, Grand-Place", "270 ◆", Color3.fromRGB(45, 100, 60), act("Elya"))
	offerRow(content, 364, 80, "BOOSTER MYSTIQUE", "Chez Sélène, quartier des Mages", "600 ◆", Color3.fromRGB(90, 50, 130), act("Selene"))
	return "BOOSTERS", "Chaque booster contient 3 créatures"
end

-------------------------------------------------------------------------------
-- Fiche détaillée d'une créature (clic sur une carte du bestiaire).
-------------------------------------------------------------------------------
local detailGui: ScreenGui? = nil
local closeCardDetail: () -> ()

closeCardDetail = function()
	if detailGui then
		detailGui:Destroy()
		detailGui = nil
	end
end

showCardDetail = function(card, known: boolean)
	closeCardDetail()
	UIKit.playSound("Click", 0.6, 1.1)
	local gui = Instance.new("ScreenGui")
	gui.Name = "CardDetail"
	gui.DisplayOrder = 60
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	detailGui = gui

	-- Voile : un clic en dehors ferme la fiche.
	local veil = UIKit.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), Selectable = false, Parent = gui })
	UIKit.tween(veil, 0.25, { BackgroundTransparency = 0.35 })
	veil.Activated:Connect(closeCardDetail)

	local panel = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(900, 560),
		BackgroundColor3 = Color3.fromRGB(236, 214, 165), Active = true, Parent = gui })
	UIKit.scaled(panel)
	UIKit.corner(panel, 14)
	UIKit.stroke(panel, Color3.fromRGB(140, 30, 30), 4, 0)
	panel.Position = UDim2.fromScale(0.5, 0.56)
	UIKit.tween(panel, 0.3, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Back)

	-- La carte en grand (immobile).
	local holder = UIKit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(36, 30), Size = UDim2.fromOffset(340, 497), Parent = panel })
	CardView.create(card, { Owned = known, Detailed = true, Size = UDim2.fromScale(1, 1), Parent = holder })

	local INK_DARK = Color3.fromRGB(60, 20, 15)
	local RED_DARK = Color3.fromRGB(140, 30, 30)
	local MUTED = Color3.fromRGB(125, 95, 65)
	local PARCH_DARK = Color3.fromRGB(214, 186, 132)
	local GOLD_D = Color3.fromRGB(196, 150, 60)
	local x, w = 410, 440

	local function label(parent: Instance, text: string, props: { [string]: any }, size: number): TextLabel
		props.Text = text
		props.RichText = true
		props.Font = props.Font or Enum.Font.Merriweather
		props.TextColor3 = props.TextColor3 or INK_DARK
		props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
		props.ZIndex = props.ZIndex or 4
		props.Parent = parent
		return UIKit.label(props, size)
	end
	local function tile(px: number, py: number, tw: number, th: number, color: Color3, transparency: number?): Frame
		local t = UIKit.new("Frame", { Position = UDim2.fromOffset(px, py), Size = UDim2.fromOffset(tw, th), BackgroundColor3 = color,
			BackgroundTransparency = transparency or 0, ZIndex = 3, Parent = panel })
		UIKit.corner(t, 10)
		return t
	end
	-- Pastille arrondie (élément, rareté, exemplaires). Renvoie sa largeur.
	local function chip(px: number, py: number, text: string, bg: Color3, fg: Color3, width: number): Frame
		local c = tile(px, py, width, 28, bg)
		UIKit.corner(c, 14)
		label(c, text, { Font = UIKit.Fonts.Bold, TextColor3 = fg, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1) }, 15)
		return c
	end
	local function gem(parent: Instance, pos: UDim2, sizePx: number, color: Color3, filled: boolean)
		local d = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Size = UDim2.fromOffset(sizePx, sizePx), Rotation = 45,
			BackgroundColor3 = color, BackgroundTransparency = filled and 0 or 1, ZIndex = 5, Parent = parent })
		UIKit.stroke(d, filled and Color3.new(1, 1, 1) or color, 1.5, filled and 0.4 or 0)
		return d
	end
	-- Filet décoratif avec losange central.
	local function divider(py: number)
		for _, sx in ipairs({ -1, 1 }) do
			local l = UIKit.new("Frame", { AnchorPoint = Vector2.new(sx < 0 and 1 or 0, 0.5), Position = UDim2.fromOffset(x + w / 2 + sx * 10, py),
				Size = UDim2.fromOffset(w / 2 - 14, 2), BackgroundColor3 = GOLD_D, BorderSizePixel = 0, ZIndex = 3, Parent = panel })
			UIKit.new("UIGradient", { Transparency = NumberSequence.new(sx < 0 and 1 or 0, sx < 0 and 0 or 1), Parent = l })
		end
		gem(panel, UDim2.fromOffset(x + w / 2, py), 9, GOLD_D, true)
	end

	local element = CardsData.Elements[card.Element]
	local rarity = CardsData.RarityById[card.Rarity]
	local rarityDark = rarity.Color:Lerp(Color3.new(0, 0, 0), 0.55)

	-- Pastille de rareté : libellé + un losange par niveau de rareté.
	local function rarityChip(px: number, py: number): Frame
		local c = tile(px, py, 170, 28, rarityDark)
		UIKit.corner(c, 14)
		label(c, rarity.Label, { Font = UIKit.Fonts.Bold, TextColor3 = Color3.new(1, 1, 1), Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -80, 1, 0) }, 15)
		for k = 1, 5 do
			gem(c, UDim2.new(1, -14 - (5 - k) * 13, 0.5, 0), 8, rarity.Color, k <= rarity.Order)
		end
		return c
	end

	if not known then
		label(panel, "CRÉATURE INCONNUE", { TextColor3 = RED_DARK, Position = UDim2.fromOffset(x, 40), Size = UDim2.fromOffset(w - 50, 44) }, 34)
		rarityChip(x, 96)
		divider(146)
		label(panel, "Cette créature n'a pas encore été découverte.\n\nOuvre des boosters à l'autel ou dans les boutiques de la ville pour l'ajouter à ton bestiaire !",
			{ TextWrapped = true, TextColor3 = MUTED, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(x, 170), Size = UDim2.fromOffset(w, 160) }, 19)
	else
		local xp = profile and profile.XP and profile.XP[card.Id] or 0
		local level = CardsData.levelFromXP(xp)
		local stageIndex = CardsData.stageOf(level)
		local hp, atk = CardsData.statsAt(card, level)
		local count = profile and profile.Cards and profile.Cards[card.Id] or 1

		-- En-tête : nom + pastilles.
		label(panel, string.upper(CardsData.displayName(card, level)), { TextColor3 = RED_DARK, Position = UDim2.fromOffset(x, 22),
			Size = UDim2.fromOffset(w - 50, 44) }, 36)
		chip(x, 74, element.Label, element.Color:Lerp(Color3.new(0, 0, 0), 0.25), Color3.new(1, 1, 1), 96)
		rarityChip(x + 104, 74)
		chip(x + 282, 74, "×" .. count .. (count > 1 and " exemplaires" or " exemplaire"), PARCH_DARK, INK_DARK, 158)
		divider(118)

		-- Niveau : médaillon + barre d'expérience.
		local medal = tile(x, 132, 58, 58, RED_DARK)
		UIKit.corner(medal, 29)
		UIKit.stroke(medal, GOLD_D, 3, 0)
		label(medal, "NIV.", { Font = UIKit.Fonts.Bold, TextColor3 = Color3.fromRGB(255, 225, 170), TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 12) }, 11)
		label(medal, tostring(level), { Font = UIKit.Fonts.Black, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 30) }, 26)
		local maxLevel = CardsData.Progression.MaxLevel
		local from, to = CardsData.xpForLevel(level), CardsData.xpForLevel(level + 1)
		label(panel, "<b>Expérience</b>", { Position = UDim2.fromOffset(x + 72, 138), Size = UDim2.fromOffset(160, 20) }, 16)
		label(panel, level >= maxLevel and "niveau max" or string.format("%d / %d XP", xp - from, to - from), { TextColor3 = MUTED,
			TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.fromOffset(x + w - 200, 138), Size = UDim2.fromOffset(200, 20) }, 15)
		local track = tile(x + 72, 164, w - 72, 16, Color3.fromRGB(120, 90, 55), 0.55)
		UIKit.corner(track, 8)
		local fill = UIKit.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 4, Parent = track })
		UIKit.corner(fill, 8)
		UIKit.gradient(fill, Color3.fromRGB(120, 220, 255), Color3.fromRGB(40, 110, 220), 0)
		local ratio = level >= maxLevel and 1 or math.clamp((xp - from) / math.max(1, to - from), 0, 1)
		UIKit.tween(fill, 0.9, { Size = UDim2.fromScale(math.max(ratio, 0.02), 1) }, Enum.EasingStyle.Quint)

		-- Statistiques : deux tuiles.
		local half = (w - 12) / 2
		for i, stat in ipairs({ { "POINTS DE VIE", hp, card.HP, Color3.fromRGB(190, 55, 60) }, { "ATTAQUE", atk, card.Attack, Color3.fromRGB(215, 120, 40) } }) do
			local t = tile(x + (i - 1) * (half + 12), 198, half, 62, stat[4])
			UIKit.gradient(t, stat[4], stat[4]:Lerp(Color3.new(0, 0, 0), 0.35), 90)
			label(t, stat[1], { Font = UIKit.Fonts.Bold, TextColor3 = Color3.fromRGB(255, 225, 200), Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 14) }, 12)
			label(t, tostring(stat[2]), { Font = UIKit.Fonts.Black, TextColor3 = Color3.new(1, 1, 1), Position = UDim2.fromOffset(14, 24), Size = UDim2.fromOffset(90, 32) }, 28)
			if stat[2] > stat[3] then
				label(t, "+" .. (stat[2] - stat[3]), { Font = UIKit.Fonts.Bold, TextColor3 = Color3.fromRGB(190, 255, 190), TextXAlignment = Enum.TextXAlignment.Right,
					Position = UDim2.new(1, -74, 0, 30), Size = UDim2.fromOffset(60, 22) }, 16)
			end
		end

		-- Capacité : encadré sombre, liseré de l'élément, coût en losanges d'énergie.
		local ability = card.Ability
		local box = tile(x, 272, w, 92, Color3.fromRGB(45, 22, 18))
		UIKit.stroke(box, GOLD_D, 1.5, 0.3)
		local accent = UIKit.new("Frame", { Position = UDim2.fromOffset(0, 10), Size = UDim2.new(0, 5, 1, -20), BackgroundColor3 = element.Color, BorderSizePixel = 0,
			ZIndex = 4, Parent = box })
		UIKit.corner(accent, 3)
		label(box, "CAPACITÉ", { Font = UIKit.Fonts.Bold, TextColor3 = Color3.fromRGB(200, 170, 120), Position = UDim2.fromOffset(18, 10), Size = UDim2.fromOffset(120, 14) }, 12)
		label(box, ability.Name, { TextColor3 = Color3.fromRGB(255, 220, 140), Position = UDim2.fromOffset(18, 26), Size = UDim2.new(1, -140, 0, 28) }, 22)
		for k = 1, ability.Cost do
			gem(box, UDim2.new(1, -18 - (ability.Cost - k) * 18, 0, 22), 10, Color3.fromRGB(110, 205, 255), true)
		end
		label(box, "énergie", { Font = UIKit.Fonts.Bold, TextColor3 = Color3.fromRGB(150, 200, 230), TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.new(1, -110, 0, 34), Size = UDim2.fromOffset(100, 14) }, 12)
		label(box, CardsData.abilityText(ability), { Font = UIKit.Fonts.Bold, TextColor3 = Color3.fromRGB(235, 220, 200), TextWrapped = true,
			Position = UDim2.fromOffset(18, 58), Size = UDim2.new(1, -36, 0, 26) }, 15)

		-- Description.
		label(panel, "« " .. (card.Description or "") .. " »", { TextColor3 = MUTED, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(x, 372), Size = UDim2.fromOffset(w, 40) }, 16)

		-- Évolutions : frise de trois médaillons reliés.
		divider(420)
		local stages = CardsData.Progression.Stages
		local col = w / #stages
		local link = UIKit.new("Frame", { Position = UDim2.fromOffset(x + col / 2, 451), Size = UDim2.fromOffset(col * (#stages - 1), 3),
			BackgroundColor3 = PARCH_DARK, BorderSizePixel = 0, ZIndex = 3, Parent = panel })
		local reachedTo = (stageIndex - 1) / math.max(1, #stages - 1)
		UIKit.new("Frame", { Size = UDim2.fromScale(reachedTo, 1), BackgroundColor3 = GOLD_D, BorderSizePixel = 0, ZIndex = 4, Parent = link })
		local numerals = { "I", "II", "III" }
		for i, st in ipairs(stages) do
			local reached = level >= st.Level
			local cx = x + col * (i - 0.5)
			local node = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, 452), Size = UDim2.fromOffset(36, 36),
				BackgroundColor3 = reached and RED_DARK or Color3.fromRGB(236, 214, 165), ZIndex = 5, Parent = panel })
			UIKit.corner(node, 18)
			UIKit.stroke(node, reached and GOLD_D or PARCH_DARK, 3, 0)
			label(node, numerals[i] or tostring(i), { Font = UIKit.Fonts.Black, TextColor3 = reached and Color3.new(1, 1, 1) or MUTED,
				TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 6 }, 15)
			local name = st.Label ~= "" and st.Label or "Forme de base"
			label(panel, "<b>" .. name .. "</b>", { TextColor3 = reached and INK_DARK or MUTED, TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(cx - col / 2, 476), Size = UDim2.fromOffset(col, 20) }, 15)
			label(panel, st.Bonus > 0 and string.format("niv. %d · +%d %%", st.Level, st.Bonus * 100) or "niv. 1", { Font = UIKit.Fonts.Bold,
				TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(cx - col / 2, 498), Size = UDim2.fromOffset(col, 16) }, 13)
		end
	end

	-- Bouton fermer : rond rouge avec une croix dessinée.
	local close = UIKit.new("TextButton", { Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(40, 40), BackgroundColor3 = RED_DARK, ZIndex = 6, Parent = panel })
	UIKit.corner(close, 20)
	UIKit.stroke(close, GOLD_D, 2, 0)
	for _, r in ipairs({ 45, -45 }) do
		local bar = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(18, 3), Rotation = r,
			BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 7, Parent = close })
		UIKit.corner(bar, 2)
	end
	close.MouseEnter:Connect(function()
		UIKit.tween(close, 0.15, { BackgroundColor3 = Color3.fromRGB(190, 45, 45) })
	end)
	close.MouseLeave:Connect(function()
		UIKit.tween(close, 0.15, { BackgroundColor3 = RED_DARK })
	end)
	close.Activated:Connect(closeCardDetail)
	UIKit.select(close)
end

function RIGHT_PAGES.Bestiaire(content: Frame)
	local owned = profile and profile.Cards or {}
	local found = 0
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "BestiaireScroll"
	scroll.Position = UDim2.fromOffset(12, 58)
	scroll.Size = UDim2.fromOffset(436, 422)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 0
	scroll.Parent = content
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = scroll
	local grid = Instance.new("UIGridLayout")
	-- Deux cartes par ligne, pour bien les voir.
	grid.CellSize = UDim2.fromOffset(180, 263)
	grid.CellPadding = UDim2.fromOffset(28, 22)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	for index, card in ipairs(CardsData.Cards) do
		local known = owned[card.Id] ~= nil
		if known then
			found += 1
		end
		local cell = Instance.new("TextButton")
		cell.Name = "Card_" .. card.Id
		cell.Text = ""
		cell.AutoButtonColor = false
		cell.BackgroundTransparency = 1
		cell.LayoutOrder = index
		cell.Parent = scroll
		selectable(cell)
		CardView.create(card, {
			Owned = known,
			Detailed = true,
			Size = UDim2.fromScale(1, 1),
			Parent = cell,
		})
		cell.Activated:Connect(function()
			showCardDetail(card, known)
		end)
		cell.SelectionGained:Connect(function()
			local top = cell.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y
			local bottom = top + cell.AbsoluteSize.Y
			local viewTop = scroll.CanvasPosition.Y
			local viewBottom = viewTop + scroll.AbsoluteWindowSize.Y
			if top < viewTop then
				scroll.CanvasPosition = Vector2.new(0, top)
			elseif bottom > viewBottom then
				scroll.CanvasPosition = Vector2.new(0, bottom - scroll.AbsoluteWindowSize.Y)
			end
		end)
	end
	return "BESTIAIRE", string.format("%d / %d créatures découvertes", found, #CardsData.Cards)
end

function RIGHT_PAGES.Recompenses(content: Frame)
	local rewards = CardsData.Economy.DailyRewards
	local streak = profile and profile.DailyStreak or 0
	local nextDay = profile and profile.DailyNext or 1
	local available = profile and profile.DailyAvailable
	for day, reward in ipairs(rewards) do
		local claimed = day < nextDay or (not available and day == nextDay - 1)
		local today = available and day == nextDay
		local tag = today and "RÉCUPÉRER" or (day < nextDay and "✓" or "")
		local box = offerRow(content, 64 + (day - 1) * 58, 52, "JOUR " .. day, reward.Label, tag,
			today and RED or (claimed and Color3.fromRGB(150, 120, 60) or Color3.fromRGB(90, 80, 110)),
			today and act("ClaimDaily") or nil, reward.Booster and "★" or "◆")
		if today then
			stroke(box, RED, 2)
		end
	end
	return "RÉCOMPENSES", string.format("Série en cours : %d jour%s", streak, streak > 1 and "s" or "")
end

function RIGHT_PAGES.Boutique(content: Frame)
	for index, pack in ipairs(ShopData.GemPacks) do
		offerRow(content, 76 + (index - 1) * 96, 80, string.upper(pack.Name), string.format("%d gemmes%s", pack.Gems,
			pack.Tag and (" • " .. pack.Tag) or ""), "R$ " .. pack.Robux, Color3.fromRGB(40, 90, 150), act("Buy:" .. pack.Id), "◆")
	end
	return "BOUTIQUE", "Achats sécurisés par Roblox"
end

local function clear(container: Frame)
	for _, child in ipairs(container:GetChildren()) do
		child:Destroy()
	end
end

render = function()
	if not pages then
		return
	end
	local p = pages
	-- Page de gauche : le chapitre choisi est surligné en rouge.
	if p.LeftContent then
		clear(p.LeftContent)
		for index, info in ipairs(CHAPTERS) do
			chapter(p.LeftContent, 76 + (index - 1) * 96, info.Title, info.Subtitle, info.Icon, function()
				if selected ~= info.Id then
					selected = info.Id
					render()
					if state == "open" then
						task.defer(focusSelectedChapter)
					end
				end
			end, selected == info.Id)
		end
		pageTitle(p.LeftContent, "MENU", "Choisis un chapitre")
	end
	if p.RightContent then
		clear(p.RightContent)
		local title, subtitle = RIGHT_PAGES[selected](p.RightContent)
		pageTitle(p.RightContent, title, subtitle)
	end
	configureNavigation()
end

local function attachPageContent(leftPart: BasePart, rightPart: BasePart)
	local leftGui, left = createPage("CarnetPageGauche", leftPart, "I")
	local rightGui, right = createPage("CarnetPageDroite", rightPart, "2")
	local function layer(page: Frame): Frame
		return frame(page, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Name = "Content" })
	end
	pages = { Left = left, Right = right, LeftContent = layer(left), RightContent = layer(right) }
	render()
	return leftGui, rightGui
end

-- Profil du joueur (bestiaire, série de récompenses) : la page se met à jour.
function BookController.SetProfile(newProfile)
	profile = newProfile
	render()
end

local function createBook(tool: Tool, anchor: CFrame)
	local source = tool:FindFirstChildWhichIsA("Model")
	if not source then
		return nil
	end
	local model = source:Clone()
	for _, descendant in ipairs(model:GetDescendants()) do
		-- Toutes les liaisons (soudures, articulations du modèle importé) sont
		-- retirées : chaque pièce est placée indépendamment pendant l'animation.
		if descendant:IsA("WeldConstraint") or descendant:IsA("JointInstance") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
		end
	end

	local cover = findPart(model, "couverture_avant")
	local spine = findPart(model, "dos_reliure")
	local pages = findPart(model, "pages")
	local menuLeft = findPart(model, "menu_gauche")
	local menuRight = findPart(model, "menu_droite")
	local backCover = findPart(model, "couverture_dos")
	if not (cover and spine and pages and menuLeft and menuRight and backCover) then
		warn("[BookController] Pièces du livre introuvables dans CarnetModel.")
		model:Destroy()
		return nil
	end

	local pagesFrame = cover.CFrame.Rotation + pages.Position
	local spineOffset = pagesFrame:PointToObjectSpace(spine.Position)
	local towardSpine = if spineOffset.X >= 0 then 1 else -1
	local origin = pagesFrame * CFrame.new(towardSpine * pages.Size.X / 2, 0, 0)
	local function relative(part: BasePart): CFrame
		return origin:ToObjectSpace(part.CFrame)
	end

	local fixed = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			fixed[part] = relative(part)
		end
	end
	local pagesRel = relative(pages)
	local pagesFront = pagesRel.Z - pages.Size.Z / 2
	local halfTurn = CFrame.Angles(0, math.pi, 0)
	local menuRel = relative(menuRight)
	local menuRightOpen = CFrame.new(menuRel.X, menuRel.Y, pagesFront - 0.004)
	local function board(name: string): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Size = Vector3.new(pages.Size.X + 0.12, pages.Size.Y + 0.14, 0.05)
		part.Color = Color3.fromRGB(122, 30, 28)
		part.Material = Enum.Material.Fabric
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Parent = model
		return part
	end
	local leftPages = pages:Clone()
	leftPages.Name = "pages_gauche"
	leftPages.Parent = model
	local leftBoard = board("carton_gauche")
	local rightBoard = board("carton_droit")
	local boardClosed = CFrame.new(pagesRel.X, pagesRel.Y, pagesRel.Z + pages.Size.Z / 2 + 0.03)
	local leaf = {
		{ Part = cover, Closed = fixed[cover] },
		{ Part = leftBoard, Closed = CFrame.new(boardClosed.X, boardClosed.Y, fixed[cover].Z + 0.04) },
		{ Part = leftPages, Closed = pagesRel },
		{ Part = menuLeft, Closed = halfTurn * CFrame.new(-menuRel.X, menuRel.Y, pagesFront - 0.004) },
	}
	fixed[cover] = nil
	fixed[menuLeft] = nil
	local menuRightClosed = fixed[menuRight]
	fixed[menuRight] = nil
	local spineClosed = fixed[spine]
	fixed[spine] = nil
	local spineOpen = CFrame.new(0, spineClosed.Y, pagesRel.Z + pages.Size.Z / 2 + 0.06)
		* CFrame.Angles(0, -math.pi / 2, 0)
	local shell = findPart(model, "couverture")
	-- Décor extérieur (cadre doré, gemme, fermoir) : l'anneau doré et la gemme
	-- comblent le trou de l'image de couverture, ils pivotent donc avec elle ;
	-- le tout est masqué une fois le livre grand ouvert.
	local decor = {}
	for _, name in ipairs({ "or", "gemme", "metal" }) do
		local piece = findPart(model, name)
		if piece then
			table.insert(decor, piece)
			if name ~= "metal" then
				table.insert(leaf, { Part = piece, Closed = fixed[piece] })
				fixed[piece] = nil
			end
		end
	end
	local sheets = {}
	for index = 1, 3 do
		local sheet = board("feuille_" .. index)
		sheet.Size = Vector3.new(pages.Size.X * 0.97, pages.Size.Y * 0.97, 0.012)
		sheet.Color = Color3.fromRGB(246, 240, 226)
		sheet.Material = Enum.Material.SmoothPlastic
		sheet.Transparency = 1
		table.insert(sheets, {
			Part = sheet,
			Closed = CFrame.new(pagesRel.X, pagesRel.Y, pagesFront - 0.003 - index * 0.002),
			Delay = 0.15 + (index - 1) * 0.13,
		})
	end
	-- Dans le Workspace (local à ce client) : les pages du PlayerGui ne
	-- s'affichent pas sur des pièces rangées dans la caméra.
	model.Parent = Workspace
	-- Les clics sur un SurfaceGui passent par un rayon : les pages doivent être touchables.
	-- Les pages sont affichées sur des plaques invisibles calées sur la boîte
	-- des feuilles : sur un MeshPart, le clic suit la forme du maillage (décalée)
	-- et non la boîte où le SurfaceGui est dessiné.
	local function plate(part: BasePart): Part
		local board = Instance.new("Part")
		board.Name = part.Name .. "_clic"
		board.Size = part.Size
		board.CFrame = part.CFrame
		board.Transparency = 1
		board.Anchored = true
		board.CanCollide = false
		board.CanTouch = false
		board.CanQuery = true
		board.CastShadow = false
		board.Parent = model
		return board
	end
	local plates = { { Plate = plate(menuLeft), Part = menuLeft }, { Plate = plate(menuRight), Part = menuRight } }
	local leftGui, rightGui = attachPageContent(plates[1].Plate, plates[2].Plate)
	local viewport = Workspace.CurrentCamera.ViewportSize
	local tanHalf = math.tan(math.rad(Workspace.CurrentCamera.FieldOfView / 2))
	local aspect = viewport.X / math.max(viewport.Y, 1)
	local spreadWidth = (math.abs(pagesRel.X) + pages.Size.X / 2) * 2
	local distance = math.max(spreadWidth * 1.25 / (2 * tanHalf * aspect), cover.Size.Y * 1.35 / (2 * tanHalf))
	return {
		Model = model, Fixed = fixed, Leaf = leaf, Shell = shell, Decor = decor,
		LeftGui = leftGui, RightGui = rightGui, Plates = plates,
		MenuRight = menuRight, MenuRightOpen = menuRightOpen, MenuRightClosed = menuRightClosed,
		Spine = spine, SpineClosed = spineClosed, SpineOpen = spineOpen,
		LeftPages = leftPages, Board = leftBoard, RightBoard = rightBoard,
		BoardClosed = boardClosed, Sheets = sheets, SheetAxis = CFrame.new(0, 0, pagesFront),
		HandOrigin = origin, SpreadWidth = spreadWidth, ClosedCenterX = pagesRel.X,
		Anchor = anchor, Distance = distance, Rise = 0, Open = 0,
	}
end

local function destroyAnimation()
	if animation then
		animation.Model:Destroy()
		animation.LeftGui:Destroy()
		animation.RightGui:Destroy()
		animation = nil
		pages = nil
	end
end

local function finishClose()
	destroyAnimation()
	GuiService.SelectedObject = nil
	if previousMouseIconEnabled ~= nil then
		UserInputService.MouseIconEnabled = previousMouseIconEnabled
		previousMouseIconEnabled = nil
	end
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	hideCharacter(false)
	setFrozen(false)
	state = "hand"
end

local function openBook()
	if state ~= "hand" or not equippedTool then
		return
	end
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not head or not root then
		return
	end

	local camera = Workspace.CurrentCamera
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	local eye = head.Position + Vector3.new(0, 0.2, 0)
	local anchor = CFrame.lookAt(eye, eye + look) * CFrame.Angles(math.rad(-READING_PITCH), 0, 0)
	local camera = Workspace.CurrentCamera
	local startView = camera.CFrame
	if isGamepadInput(UserInputService:GetLastInputType()) then
		previousMouseIconEnabled = UserInputService.MouseIconEnabled
		UserInputService.MouseIconEnabled = false
	end
	camera.CameraType = Enum.CameraType.Scriptable
	setFrozen(true)
	hideCharacter(true)
	animation = createBook(equippedTool, anchor)
	if not animation then
		finishClose()
		return
	end
	animation.StartView = startView
	animation.LeftGui.Enabled = false
	animation.RightGui.Enabled = false
	state = "opening"
	UIKit.playSound("BookOpen", 0.6)
end

local function closeBook()
	if state == "open" or state == "opening" then
		state = "closing"
		UIKit.playSound("PageTurn", 0.5, 0.9)
	end
end

local function toggleBook()
	if state == "hand" then
		openBook()
	elseif state == "open" or state == "opening" then
		closeBook()
	end
end

local function equipAndToggle()
	if state ~= "hand" then
		toggleBook()
		return
	end
	if equippedTool then
		openBook()
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local backpack = player:FindFirstChildOfClass("Backpack")
	local tool = backpack and backpack:FindFirstChild("Carnet")
	if not humanoid or not tool or not tool:IsA("Tool") then
		warn("[BookController] Carnet introuvable pour ouvrir le livre.")
		return
	end
	humanoid:EquipTool(tool)
	task.delay(0.1, function()
		if equippedTool and state == "hand" then
			openBook()
		end
	end)
end

local function update(dt: number)
	if not animation then
		return
	end
	if state == "opening" then
		animation.Rise = math.min(1, animation.Rise + dt / RISE_TIME)
		if animation.Rise >= 1 then
			animation.Open = math.min(1, animation.Open + dt / OPEN_TIME)
			if animation.Open >= 1 then
				state = "open"
				animation.LeftGui.Enabled = true
				animation.RightGui.Enabled = true
				GuiService.SelectedObject = nil
				task.defer(focusSelectedChapter)
				if openCallback then
					openCallback()
				end
			end
		end
	elseif state == "closing" then
		animation.Open = math.max(0, animation.Open - dt / (OPEN_TIME * 0.8))
		if animation.Open <= 0 then
			animation.Rise = math.max(0, animation.Rise - dt / (RISE_TIME * 0.8))
			if animation.Rise <= 0 then
				if closeCallback then
					closeCallback()
				end
				finishClose()
				return
			end
		end
	end

	local raise = smooth(animation.Rise)
	local opened = smooth(animation.Open)
	Workspace.CurrentCamera.CFrame = animation.StartView:Lerp(animation.Anchor, raise)
	local push = animation.SpreadWidth * 0.35 * math.sin(math.pi * opened)
	local reading = animation.Anchor
		* CFrame.new(0, 0, -animation.Distance - push)
		* CFrame.Angles(0, math.pi, 0)
		* CFrame.Angles(math.rad(6), 0, 0)
		* CFrame.new(-animation.ClosedCenterX * (1 - opened), 0, 0)
	local origin = animation.HandOrigin:Lerp(reading, raise)
		+ Vector3.new(0, math.sin(math.pi * raise) * 0.35, 0)
	for part, offset in pairs(animation.Fixed) do
		part.CFrame = origin * offset
	end
	local swing = CFrame.Angles(0, -math.pi * opened, 0)
	for _, piece in ipairs(animation.Leaf) do
		piece.Part.CFrame = origin * swing * piece.Closed
	end
	animation.Spine.CFrame = origin * animation.SpineClosed:Lerp(animation.SpineOpen, opened)
	local flipping = animation.Open > 0.01 and animation.Open < 0.99
	for _, sheet in ipairs(animation.Sheets) do
		local progress = smooth((animation.Open - sheet.Delay) / (1 - sheet.Delay))
		local turn = animation.SheetAxis * CFrame.Angles(0, -math.pi * progress, 0) * animation.SheetAxis:Inverse()
		sheet.Part.CFrame = origin * turn * sheet.Closed
		sheet.Part.Transparency = if flipping then 0 else 1
	end
	animation.MenuRight.CFrame = origin * (if opened > 0.98 then animation.MenuRightOpen else animation.MenuRightClosed)
	local inside = opened > 0.02
	if animation.Shell then
		animation.Shell.LocalTransparencyModifier = if inside then 1 else 0
	end
	local spread = opened > 0.95
	for _, piece in ipairs(animation.Decor) do
		piece.LocalTransparencyModifier = if spread then 1 else 0
	end
	animation.LeftPages.LocalTransparencyModifier = if inside then 0 else 1
	animation.Board.LocalTransparencyModifier = if inside then 0 else 1
	animation.RightBoard.CFrame = origin * animation.BoardClosed
	animation.RightBoard.LocalTransparencyModifier = if inside then 0 else 1
	for _, pair in ipairs(animation.Plates) do
		pair.Plate.CFrame = pair.Part.CFrame
	end
end

local function bindTool(tool: Instance)
	if not tool:IsA("Tool") or tool.Name ~= "Carnet" or tool:GetAttribute("BookAnimationBound") then
		return
	end
	tool:SetAttribute("BookAnimationBound", true)
	local handModel = tool:FindFirstChildWhichIsA("Model")
	if handModel then
		for _, descendant in ipairs(handModel:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.LocalTransparencyModifier = 0
			end
		end
	end
	tool.Equipped:Connect(function()
		equippedTool = tool
		state = "hand"
	end)
	tool.Unequipped:Connect(function()
		equippedTool = nil
		if state ~= "hand" then
			finishClose()
		end
	end)
	-- Un clic ouvre le livre ; une fois ouvert, les clics vont aux boutons des
	-- pages (on le referme avec E ou en rangeant le carnet).
	tool.Activated:Connect(function()
		local lastInput = UserInputService:GetLastInputType()
		if state == "hand" and not isGamepadInput(lastInput) then
			openBook()
		end
	end)
end

local function watch(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		bindTool(child)
	end
	container.ChildAdded:Connect(bindTool)
end

function BookController.Init(onOpen: () -> (), onClose: () -> (), onAction: ((string) -> ())?)
	openCallback = onOpen
	closeCallback = onClose
	actionCallback = onAction
	RunService:BindToRenderStep("ArcanaBookAnimation", Enum.RenderPriority.Camera.Value + 1, update)
	ContextActionService:BindAction("ArcanaBookToggle", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			-- Fiche d'une carte ouverte : E ferme seulement la fiche, pas le livre.
			if detailGui then
				closeCardDetail()
				return Enum.ContextActionResult.Sink
			end
			equipAndToggle()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.E, Enum.KeyCode.ButtonY)
	watch(player:WaitForChild("Backpack"))
	if player.Character then
		watch(player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		equippedTool = nil
		if state ~= "hand" then
			finishClose()
		end
		watch(character)
		watch(player:WaitForChild("Backpack"))
	end)
end

function BookController.Close()
	if state ~= "hand" then
		closeBook()
	end
end

return BookController
