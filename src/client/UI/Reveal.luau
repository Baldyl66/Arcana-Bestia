-- Animation d'ouverture d'un booster : le paquet tremble, explose en
-- lumière, puis la carte apparaît avec des rayons à la couleur de sa rareté.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CardsData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CardsData"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))
local CardView = require(script.Parent:WaitForChild("CardView"))
local BoosterFX = require(script.Parent:WaitForChild("BoosterFX"))

local Reveal = {}
Reveal.__index = Reveal

type Callbacks = {
	OpenAgain: () -> (),
	Closed: () -> (),
	Shake: (intensity: number, duration: number) -> (),
}

function Reveal.new(parent: Instance, callbacks: Callbacks)
	local self = setmetatable({}, Reveal)
	self.Callbacks = callbacks
	self.IsOpen = false
	self.Busy = false

	local root = UIKit.new("Frame", {
		Name = "Reveal",
		BackgroundColor3 = Color3.fromRGB(5, 3, 12),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Active = true,
		ZIndex = 20,
		Parent = parent,
	})
	self.Root = root

	local stage = UIKit.new("Frame", {
		Name = "Stage",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(700, 620),
		Parent = root,
	})
	UIKit.scaled(stage)
	self.Stage = stage

	-- Rayons tournants derrière la carte.
	local rays = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -30),
		Size = UDim2.fromOffset(10, 10),
		Parent = stage,
	})
	self.Rays = rays
	self.RayParts = {}
	for i = 1, 12 do
		local ray = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(46, 900),
			Rotation = i * 15,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Parent = rays,
		})
		UIKit.new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.55),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = ray,
		})
		table.insert(self.RayParts, ray)
	end

	-- Paquet de cartes.
	local pack = UIKit.new("Frame", {
		Name = "Pack",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -30),
		Size = UDim2.fromOffset(230, 330),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = stage,
	})
	UIKit.corner(pack, 16)
	UIKit.gradient(pack, Color3.fromRGB(150, 80, 255), Color3.fromRGB(40, 15, 90), 90)
	UIKit.stroke(pack, UIKit.Colors.Gold, 4, 0)
	UIKit.label({ Text = "◆", Font = UIKit.Fonts.Black, TextColor3 = UIKit.Colors.Gold,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.38), Size = UDim2.fromScale(0.6, 0.35), Parent = pack }, 120)
	UIKit.label({ Text = "BOOSTER", Font = UIKit.Fonts.Title, TextColor3 = Color3.new(1, 1, 1),
		Position = UDim2.fromScale(0.05, 0.62), Size = UDim2.fromScale(0.9, 0.12), Parent = pack }, 40)
	UIKit.label({ Text = "ARCANA BESTIA", Font = UIKit.Fonts.Bold, TextColor3 = UIKit.Colors.Gold,
		Position = UDim2.fromScale(0.05, 0.76), Size = UDim2.fromScale(0.9, 0.07), Parent = pack }, 18)
	self.Pack = pack
	self.PackScale = UIKit.new("UIScale", { Parent = pack })

	-- Emplacement de la carte.
	local cardHolder = UIKit.new("Frame", {
		Name = "CardHolder",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -30),
		Size = UDim2.fromOffset(300, 417),
		Parent = stage,
	})
	self.CardHolder = cardHolder
	self.CardScale = UIKit.new("UIScale", { Scale = 0, Parent = cardHolder })

	self.Headline = UIKit.label({
		Text = "",
		Font = UIKit.Fonts.Title,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(1, 0, 0, 44),
		TextTransparency = 1,
		Parent = stage,
	}, 42)
	UIKit.new("UIStroke", { Thickness = 2, Transparency = 0.3, Parent = self.Headline })

	self.SubLine = UIKit.label({
		Text = "",
		Font = UIKit.Fonts.Bold,
		TextColor3 = UIKit.Colors.Gold,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -76),
		Size = UDim2.new(1, 0, 0, 26),
		TextTransparency = 1,
		Parent = stage,
	}, 22)

	local actions = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(560, 60),
		Visible = false,
		Parent = stage,
	})
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 16),
		Parent = actions,
	})
	self.Actions = actions
	self.ContinueButton = UIKit.button({ Text = "CONTINUER", Style = "Ghost", Size = UDim2.fromOffset(220, 56),
		Parent = actions, Callback = function()
			self:Close()
		end })
	self.AgainButton = UIKit.button({
		Text = string.format("ENCORE  •  %d ◆", CardsData.Economy.BoosterPrice),
		Style = "Gold",
		Size = UDim2.fromOffset(260, 56),
		Parent = actions,
		Callback = function()
			if not self.Busy then
				callbacks.OpenAgain()
			end
		end,
	})

	self.Flash = UIKit.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 25,
		Parent = root,
	})

	return self
end

function Reveal:Play(result)
	if self.Busy then
		return
	end
	self.Busy = true
	self.IsOpen = true

	local card = result.card
	local rarity = CardsData.RarityById[card.Rarity] or CardsData.Rarities[1]

	local root = self.Root
	root.Visible = true
	self.Actions.Visible = false
	self.Headline.TextTransparency = 1
	self.SubLine.TextTransparency = 1
	self.Rays.Visible = false
	self.CardScale.Scale = 0
	for _, child in ipairs(self.CardHolder:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	-- 0. Ouverture en vrai du booster de l'autel (animations du modèle 3D),
	-- avant d'assombrir l'écran.
	local playedWorld = false
	self.Pack.Visible = false
	if BoosterFX.Display then
		root.BackgroundTransparency = 1
		local ok, result3D = pcall(BoosterFX.playWorldOpening, rarity.Color, rarity.Order, self.Callbacks.Shake, card.Element)
		playedWorld = ok and result3D == true
		if not ok then
			warn("[BoosterFX] Ouverture sur l'autel impossible :", result3D)
		end
	end
	UIKit.tween(root, 0.25, { BackgroundTransparency = 0.25 })

	-- 1. Le paquet arrive et tremble de plus en plus fort : booster 3D si le
	-- modèle est importé, sinon le paquet dessiné.
	local pack = self.Pack
	local played3D = false
	if playedWorld then
		pack.Visible = false
		played3D = true
	elseif BoosterFX.template() then
		pack.Visible = false
		local holder = UIKit.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, -30),
			Size = UDim2.fromOffset(520, 560),
			ZIndex = 22,
			Parent = self.Stage,
		})
		local ok, result3D = pcall(BoosterFX.playOpening, holder, rarity.Color, rarity.Order, self.Callbacks.Shake)
		played3D = ok and result3D == true
		if not ok then
			warn("[BoosterFX] Ouverture 3D impossible :", result3D)
		end
		task.delay(0.4, function()
			holder:Destroy()
		end)
	end
	if not played3D then
		pack.Visible = true
		pack.Rotation = 0
		self.PackScale.Scale = 0.3
		UIKit.tween(self.PackScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back).Completed:Wait()
		local shakes = 6 + rarity.Order * 2
		for i = 1, shakes do
			local strength = 3 + i * 0.9
			UIKit.tween(pack, 0.05, { Rotation = (i % 2 == 0) and strength or -strength }).Completed:Wait()
		end
	end

	-- 2. Explosion lumineuse.
	self.Flash.BackgroundColor3 = rarity.Color:Lerp(Color3.new(1, 1, 1), 0.5)
	self.Flash.BackgroundTransparency = 0
	pack.Visible = false
	UIKit.tween(self.Flash, 0.7, { BackgroundTransparency = 1 })
	UIKit.playSound("Reveal", 0.6, 0.8 + rarity.Order * 0.1)
	if rarity.Order >= 4 then
		self.Callbacks.Shake(rarity.Order == 5 and 0.9 or 0.5, 0.6)
	end

	-- 3. La carte apparaît.
	for _, ray in ipairs(self.RayParts) do
		ray.BackgroundColor3 = rarity.Color
	end
	self.Rays.Visible = rarity.Order >= 2
	self.Rays.Rotation = 0
	local spin = RunService.RenderStepped:Connect(function(dt)
		self.Rays.Rotation += dt * (10 + rarity.Order * 6)
	end)
	self.SpinConnection = spin

	CardView.create(card, { Detailed = true, Count = result.count, Parent = self.CardHolder })
	UIKit.tween(self.CardScale, 0.6, { Scale = 1 }, Enum.EasingStyle.Back)

	self.Headline.Text = result.isNew and "NOUVELLE CRÉATURE !" or "DOUBLON"
	self.Headline.TextColor3 = result.isNew and rarity.Color or UIKit.Colors.SubText
	UIKit.tween(self.Headline, 0.4, { TextTransparency = 0 })

	if result.isNew then
		self.SubLine.Text = string.format("%s ajouté à ton bestiaire", card.Name)
	else
		self.SubLine.Text = string.format("Possédé x%d   •   +%d ◆ remboursés", result.count, result.refund or 0)
	end
	UIKit.tween(self.SubLine, 0.4, { TextTransparency = 0 })

	task.wait(0.5)
	self.Actions.Visible = true
	UIKit.focus(self.ContinueButton)
	self.Busy = false
end

function Reveal:Close()
	if not self.IsOpen or self.Busy then
		return
	end
	self.IsOpen = false
	if self.SpinConnection then
		self.SpinConnection:Disconnect()
		self.SpinConnection = nil
	end
	UIKit.tween(self.CardScale, 0.2, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	UIKit.tween(self.Headline, 0.2, { TextTransparency = 1 })
	UIKit.tween(self.SubLine, 0.2, { TextTransparency = 1 })
	self.Actions.Visible = false
	self.Rays.Visible = false
	UIKit.tween(self.Root, 0.25, { BackgroundTransparency = 1 }).Completed:Once(function()
		if not self.IsOpen then
			self.Root.Visible = false
		end
	end)
	self.Callbacks.Closed()
end

-- Enchaîner : on réinitialise la scène sans fermer l'overlay.
function Reveal:Reset()
	if self.SpinConnection then
		self.SpinConnection:Disconnect()
		self.SpinConnection = nil
	end
end

return Reveal
