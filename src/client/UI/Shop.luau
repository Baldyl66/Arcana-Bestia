-- Boutique Robux : offre de bienvenue, packs de gemmes et passes de jeu.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("ShopData"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local Shop = {}

local GEM_TOP, GEM_BOTTOM = Color3.fromRGB(160, 245, 255), Color3.fromRGB(40, 120, 230)

-- Losange de gemme, plus grand pour les gros packs.
local function gemIcon(parent: Instance, size: number, count: number)
	local holder = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromScale(0.8, 0.5),
		Parent = parent,
	})
	for i = 1, count do
		local offset = (i - (count + 1) / 2) * 0.22
		local gem = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + offset, 0.5 + math.abs(offset) * 0.35),
			Size = UDim2.fromScale(size, size),
			Rotation = 45,
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 2 + (count - math.abs(i - (count + 1) / 2)),
			Parent = holder,
		})
		UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = gem })
		UIKit.corner(gem, 6)
		UIKit.gradient(gem, GEM_TOP, GEM_BOTTOM, 90)
		UIKit.stroke(gem, Color3.fromRGB(230, 252, 255), 2, 0.1)
	end
	return holder
end

local function prompt(item, isPass: boolean, toast: (string, Color3?) -> ())
	local id = isPass and item.PassId or item.ProductId
	if id == 0 then
		toast("Cette offre arrive bientôt !", UIKit.Colors.Gold)
		return
	end
	local player = Players.LocalPlayer
	if isPass then
		if player:GetAttribute(item.Id) then
			toast("Tu possèdes déjà ce pass.", UIKit.Colors.Success)
			return
		end
		MarketplaceService:PromptGamePassPurchase(player, id)
	else
		MarketplaceService:PromptProductPurchase(player, id)
	end
end

function Shop.new(parent: Instance, toast: (string, Color3?) -> ())
	local panel = UIKit.panel(parent, "BOUTIQUE DES MERVEILLES")
	local content = panel.Content
	local player = Players.LocalPlayer

	local scroll = UIKit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = UIKit.Colors.Accent,
		Parent = content,
	})
	UIKit.new("UIListLayout", { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
	UIKit.new("UIPadding", { PaddingRight = UDim.new(0, 12), Parent = scroll })

	local function section(text: string, order: number)
		UIKit.label({
			Text = text,
			Font = UIKit.Fonts.Black,
			TextColor3 = UIKit.Colors.Gold,
			Size = UDim2.new(1, 0, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = order,
			Parent = scroll,
		}, 20)
	end

	local function priceButton(parentFrame: Instance, item, isPass: boolean, style: string)
		return UIKit.button({
			Text = item.Robux .. " R$",
			Style = style,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, -20, 0, 42),
			TextSize = 18,
			Parent = parentFrame,
			Callback = function()
				prompt(item, isPass, toast)
			end,
		})
	end

	---------------------------------------------------------------------------
	-- Offre de bienvenue
	---------------------------------------------------------------------------
	local starter = ShopData.Starter
	local banner = UIKit.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(1, 0, 0, 120),
		LayoutOrder = 1,
		Parent = scroll,
	})
	UIKit.corner(banner, 18)
	UIKit.gradient(banner, Color3.fromRGB(150, 80, 230), Color3.fromRGB(60, 25, 110), 0)
	UIKit.stroke(banner, UIKit.Colors.Gold, 2, 0)
	local bannerArt = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, 150, 1, 0), Parent = banner })
	gemIcon(bannerArt, 0.55, 3).Position = UDim2.fromScale(0.5, 0.5)
	UIKit.label({
		Text = "OFFRE DE BIENVENUE",
		Font = UIKit.Fonts.Black,
		TextColor3 = UIKit.Colors.Gold,
		Position = UDim2.fromOffset(160, 14),
		Size = UDim2.new(1, -380, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = banner,
	}, 14)
	UIKit.label({
		Text = starter.Name,
		Font = UIKit.Fonts.Title,
		Position = UDim2.fromOffset(160, 34),
		Size = UDim2.new(1, -380, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = banner,
	}, 30)
	UIKit.label({
		Text = starter.Description,
		Font = UIKit.Fonts.Body,
		TextColor3 = UIKit.Colors.Text,
		Position = UDim2.fromOffset(160, 72),
		Size = UDim2.new(1, -380, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = banner,
	}, 16)
	local starterButton = UIKit.button({
		Text = starter.Robux .. " R$",
		Style = "Gold",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -20, 0.5, 0),
		Size = UDim2.fromOffset(190, 54),
		TextSize = 22,
		Parent = banner,
		Callback = function()
			prompt(starter, false, toast)
		end,
	})

	---------------------------------------------------------------------------
	-- Packs de gemmes
	---------------------------------------------------------------------------
	section("PACKS DE GEMMES", 2)
	local packRow = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 230), LayoutOrder = 3, Parent = scroll })
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = packRow,
	})
	for index, pack in ipairs(ShopData.GemPacks) do
		local cardFrame = UIKit.new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			Size = UDim2.new(1 / #ShopData.GemPacks, -9, 1, 0),
			LayoutOrder = index,
			Parent = packRow,
		})
		UIKit.corner(cardFrame, 16)
		UIKit.gradient(cardFrame, Color3.fromRGB(40, 70, 120), UIKit.Colors.Background, 90)
		UIKit.stroke(cardFrame, Color3.fromRGB(120, 210, 255), 1.5, 0.3)
		gemIcon(cardFrame, 0.42, index)
		UIKit.label({
			Text = tostring(pack.Gems),
			Font = UIKit.Fonts.Black,
			Position = UDim2.new(0, 10, 0.62, -6),
			Size = UDim2.new(1, -20, 0, 30),
			Parent = cardFrame,
		}, 28)
		UIKit.label({
			Text = pack.Name,
			Font = UIKit.Fonts.Bold,
			TextColor3 = UIKit.Colors.SubText,
			Position = UDim2.new(0, 10, 0.62, 24),
			Size = UDim2.new(1, -20, 0, 16),
			Parent = cardFrame,
		}, 14)
		priceButton(cardFrame, pack, false, "Primary")
		if pack.Tag then
			local tag = UIKit.new("Frame", {
				BackgroundColor3 = UIKit.Colors.Danger,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0),
				Size = UDim2.new(0.85, 0, 0, 22),
				ZIndex = 5,
				Parent = cardFrame,
			})
			UIKit.corner(tag, 11)
			UIKit.label({ Text = pack.Tag, Font = UIKit.Fonts.Black, Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = tag }, 12)
		end
	end

	---------------------------------------------------------------------------
	-- Passes de jeu
	---------------------------------------------------------------------------
	section("PASSES PERMANENTS", 4)
	local passButtons = {}
	for index, pass in ipairs(ShopData.Passes) do
		local row = UIKit.new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			Size = UDim2.new(1, 0, 0, 92),
			LayoutOrder = 4 + index,
			Parent = scroll,
		})
		UIKit.corner(row, 16)
		UIKit.gradient(row, Color3.fromRGB(90, 70, 30), UIKit.Colors.Background, 0)
		UIKit.stroke(row, UIKit.Colors.Gold, 1.5, 0.35)
		local medal = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 18, 0.5, 0),
			Size = UDim2.fromOffset(60, 60),
			BackgroundColor3 = Color3.new(1, 1, 1),
			Parent = row,
		})
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = medal })
		UIKit.gradient(medal, Color3.fromRGB(255, 225, 140), Color3.fromRGB(200, 120, 30), 90)
		UIKit.stroke(medal, Color3.fromRGB(255, 245, 210), 2, 0)
		UIKit.label({ Text = string.sub(pass.Name, 1, 1) == "P" and "VIP" or "SAC", Font = UIKit.Fonts.Black, TextColor3 = Color3.fromRGB(70, 35, 5),
			Size = UDim2.fromScale(1, 1), Parent = medal }, 16)
		UIKit.label({
			Text = pass.Name,
			Font = UIKit.Fonts.Black,
			TextColor3 = UIKit.Colors.Gold,
			Position = UDim2.fromOffset(94, 14),
			Size = UDim2.new(1, -310, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		}, 20)
		UIKit.label({
			Text = pass.Description,
			Font = UIKit.Fonts.Body,
			Position = UDim2.fromOffset(94, 42),
			Size = UDim2.new(1, -310, 0, 38),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = row,
		}, 15)
		passButtons[pass.Id] = UIKit.button({
			Text = pass.Robux .. " R$",
			Style = "Gold",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -18, 0.5, 0),
			Size = UDim2.fromOffset(180, 50),
			TextSize = 20,
			Parent = row,
			Callback = function()
				prompt(pass, true, toast)
			end,
		})
	end

	-- Passes déjà possédés et offre de bienvenue déjà achetée.
	local function refreshOwned()
		for _, pass in ipairs(ShopData.Passes) do
			local button = passButtons[pass.Id]
			local owned = player:GetAttribute(pass.Id) == true
			button.Text = owned and "POSSÉDÉ" or (pass.Robux .. " R$")
			UIKit.setDimmed(button, owned)
		end
	end
	for _, pass in ipairs(ShopData.Passes) do
		player:GetAttributeChangedSignal(pass.Id):Connect(refreshOwned)
	end
	refreshOwned()

	function panel:SetProfile(profile)
		if profile then
			banner.Visible = not profile.StarterBought
		end
	end
	panel.StarterButton = starterButton

	return panel
end

return Shop
