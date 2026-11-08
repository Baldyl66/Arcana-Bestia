-- Menu d'accueil : caméra cinématique autour de l'arène, titre, chargement
-- du monde et navigation (souris, tactile et manette).
local RunService = game:GetService("RunService")

local UIKit = require(script.Parent:WaitForChild("UIKit"))

local MainMenu = {}
MainMenu.__index = MainMenu

type Callbacks = {
	Play: () -> (),
	Collection: () -> (),
	Settings: () -> (),
	Help: () -> (),
}

function MainMenu.new(parent: Instance, callbacks: Callbacks)
	local self = setmetatable({}, MainMenu)
	self.Ready = false

	local root = UIKit.new("Frame", {
		Name = "MainMenu",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = parent,
	})
	self.Root = root

	-- Vignettes pour la lisibilité du texte sur la scène 3D.
	-- Elles débordent largement de l'écran : sur téléphone, la zone sûre
	-- (encoche) laissait une bande non couverte et une coupure nette.
	local left = UIKit.new("Frame", {
		BackgroundColor3 = UIKit.Colors.Background,
		Position = UDim2.new(-0.2, 0, -0.2, 0),
		Size = UDim2.fromScale(0.9, 1.4),
		BorderSizePixel = 0,
		Parent = root,
	})
	UIKit.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(0.45, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = left,
	})
	local bottom = UIKit.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(-0.2, 0, 1.2, 0),
		Size = UDim2.fromScale(1.4, 0.5),
		BorderSizePixel = 0,
		Parent = root,
	})
	UIKit.new("UIGradient", {
		Rotation = -90,
		Transparency = NumberSequence.new(0.45, 1),
		Parent = bottom,
	})

	-- Particules arcaniques flottantes.
	local particles = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = root })
	-- Les particules gèrent leur propre transparence.
	particles:SetAttribute("NoFade", true)
	self.Particles = particles
	for _ = 1, 22 do
		local size = math.random(3, 7)
		local dot = UIKit.new("Frame", {
			BackgroundColor3 = math.random() < 0.5 and UIKit.Colors.Gold or UIKit.Colors.Accent,
			BackgroundTransparency = 0.3,
			Size = UDim2.fromOffset(size, size),
			Position = UDim2.fromScale(math.random(), 1.05),
			Parent = particles,
		})
		UIKit.corner(dot, 10)
		task.spawn(function()
			task.wait(math.random() * 6)
			while dot.Parent do
				local x = math.random()
				dot.Position = UDim2.fromScale(x, 1.05)
				dot.BackgroundTransparency = 0.2
				local duration = math.random(8, 16)
				UIKit.tween(dot, duration, {
					Position = UDim2.fromScale(x + (math.random() - 0.5) * 0.2, -0.05),
					BackgroundTransparency = 0.9,
				}, Enum.EasingStyle.Linear).Completed:Wait()
			end
		end)
	end

	-- Contenu principal.
	local content = UIKit.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.06, 0, 0.5, 0),
		Size = UDim2.fromOffset(560, 600),
		Parent = root,
	})
	-- Échelle propre au menu (voir :Layout) : il remplit l'écran au lieu de
	-- suivre l'échelle globale, trop petite sur téléphone.
	self.ContentScale = UIKit.new("UIScale", { Parent = content })
	self.Content = content

	UIKit.label({
		Text = "◆  LE SANCTUAIRE DES BÊTES  ◆",
		Font = UIKit.Fonts.Bold,
		TextColor3 = UIKit.Colors.SubText,
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = content,
	}, 20)

	local title = UIKit.label({
		Text = "ARCANA",
		Font = UIKit.Fonts.Title,
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 120),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = content,
	}, 130)
	UIKit.gradient(title, Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 170, 255), 90)
	UIKit.new("UIStroke", { Color = UIKit.Colors.AccentDark, Thickness = 3, Transparency = 0.2, Parent = title })

	local subtitle = UIKit.label({
		Text = "BESTIA",
		Font = UIKit.Fonts.Title,
		Position = UDim2.fromOffset(6, 136),
		Size = UDim2.new(1, 0, 0, 90),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = content,
	}, 96)
	UIKit.gradient(subtitle, Color3.fromRGB(255, 235, 170), UIKit.Colors.GoldDark, 90)
	UIKit.new("UIStroke", { Color = Color3.fromRGB(60, 30, 5), Thickness = 3, Transparency = 0.2, Parent = subtitle })

	self.Description = UIKit.label({
		Text = "Ouvre des boosters, capture des créatures légendaires et complète ton bestiaire.",
		Font = UIKit.Fonts.Body,
		TextColor3 = UIKit.Colors.Text,
		TextTransparency = 0.15,
		Position = UDim2.fromOffset(2, 236),
		Size = UDim2.new(0.9, 0, 0, 44),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = content,
	}, 18)

	-- Boutons.
	local buttons = UIKit.new("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 300),
		Size = UDim2.fromOffset(380, 300),
		Visible = false,
		Parent = content,
	})
	self.ButtonList = UIKit.new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = buttons })
	self.Buttons = buttons

	self.PlayButton = UIKit.button({ Text = "JOUER", Style = "Gold", Align = "Left",
		Size = UDim2.fromOffset(380, 68), TextSize = 30, LayoutOrder = 1, Parent = buttons, Callback = callbacks.Play })
	self.SecondaryButtons = {
		UIKit.button({ Text = "COLLECTION", Style = "Ghost", Align = "Left", Size = UDim2.fromOffset(340, 54),
			LayoutOrder = 2, Parent = buttons, Callback = callbacks.Collection }),
		UIKit.button({ Text = "PARAMÈTRES", Style = "Ghost", Align = "Left", Size = UDim2.fromOffset(340, 54),
			LayoutOrder = 3, Parent = buttons, Callback = callbacks.Settings }),
		UIKit.button({ Text = "AIDE & CRÉDITS", Style = "Ghost", Align = "Left", Size = UDim2.fromOffset(340, 54),
			LayoutOrder = 4, Parent = buttons, Callback = callbacks.Help }),
	}

	-- Barre de chargement pendant la génération du monde.
	local loading = UIKit.new("Frame", {
		Name = "Loading",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 310),
		Size = UDim2.fromOffset(400, 70),
		Parent = content,
	})
	self.LoadingLabel = UIKit.label({
		Text = "Invocation du monde...",
		Font = UIKit.Fonts.Bold,
		TextColor3 = UIKit.Colors.SubText,
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = loading,
	}, 18)
	local track = UIKit.new("Frame", {
		BackgroundColor3 = UIKit.Colors.Panel,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = loading,
	})
	UIKit.corner(track, 8)
	UIKit.stroke(track, UIKit.Colors.Accent, 1, 0.5)
	self.LoadingFill = UIKit.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromScale(0, 1),
		Parent = track,
	})
	UIKit.corner(self.LoadingFill, 8)
	UIKit.gradient(self.LoadingFill, UIKit.Colors.Accent, UIKit.Colors.Gold, 0)
	self.Loading = loading

	local function watch(camera: Camera?)
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				self:Layout()
			end)
		end
		self:Layout()
	end
	watch(workspace.CurrentCamera)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		watch(workspace.CurrentCamera)
	end)

	return self
end

-- Mise en page adaptative : sur un écran bas (téléphone en paysage) on passe
-- en mode compact (description masquée, boutons en grille 2 colonnes) et le
-- bloc est agrandi pour occuper la hauteur disponible.
function MainMenu:Layout()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1366, 768)
	if viewport.X < 2 or viewport.Y < 2 then
		return
	end
	-- Compact uniquement sur les écrans vraiment bas (téléphone en paysage).
	-- Même disposition partout (le mode compact des téléphones est abandonné :
	-- le bloc est simplement mis à l'échelle).
	local compact = false
	if compact ~= self.Compact then
		self.Compact = compact
		self.Description.Visible = not compact
		local list = self.ButtonList
		if compact then
			-- JOUER large en haut, les 3 autres en ligne dessous.
			self.Buttons.Position = UDim2.fromOffset(0, 236)
			self.Buttons.Size = UDim2.fromOffset(560, 150)
			self.PlayButton.Size = UDim2.fromOffset(560, 72)
			list.FillDirection = Enum.FillDirection.Vertical
			local row = self.Row or UIKit.new("Frame", { Name = "Row", BackgroundTransparency = 1, Size = UDim2.fromOffset(560, 64), LayoutOrder = 2 })
			self.Row = row
			row.Parent = self.Buttons
			if not row:FindFirstChildOfClass("UIListLayout") then
				UIKit.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = row })
			end
			for _, b in ipairs(self.SecondaryButtons) do
				b.Size = UDim2.fromOffset(180, 64)
				b.Parent = row
			end
			self.Loading.Position = UDim2.fromOffset(0, 250)
		else
			self.Buttons.Position = UDim2.fromOffset(0, 300)
			self.Buttons.Size = UDim2.fromOffset(380, 300)
			self.PlayButton.Size = UDim2.fromOffset(380, 68)
			for _, b in ipairs(self.SecondaryButtons) do
				b.Size = UDim2.fromOffset(340, 54)
				b.Parent = self.Buttons
			end
			if self.Row then
				self.Row.Parent = nil
			end
			self.Loading.Position = UDim2.fromOffset(0, 310)
		end
	end
	-- Hauteur utile du bloc : 600 (normal) ou ~390 (compact).
	-- Part de la hauteur occupée : le bloc reste aéré (le décor 3D doit se voir),
	-- surtout sur téléphone où l'écran est petit.
	local contentH = compact and 390 or 600
	-- Le cadre prend la hauteur réelle du contenu (sinon, centré, il remonte
	-- sous la barre Roblox), et on décale le centre sous cette barre.
	self.Content.Size = UDim2.fromOffset(560, contentH)
	local inset = game:GetService("GuiService"):GetGuiInset().Y
	self.ContentPosition = UDim2.new(0.06, 0, 0.5, inset / 2)
	if self.Showing then
		self.Content.Position = self.ContentPosition
	end
	-- Sur un écran bas (téléphone), le bloc occupe un peu plus de hauteur.
	local share = if viewport.Y < 500 then 0.86 else 0.72
	local scale = math.min((viewport.Y - inset) * share / contentH, viewport.X * 0.45 / 560)
	self.ContentScale.Scale = math.clamp(scale, 0.4, 1) * (UIKit.Settings.UIScale or 1)
end

function MainMenu:SetProgress(progress: number)
	if self.Ready then
		return
	end
	UIKit.tween(self.LoadingFill, 0.3, { Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1) })
	self.LoadingLabel.Text = string.format("Invocation du monde...  %d%%", math.floor(progress * 100))
end

function MainMenu:SetReady()
	if self.Ready then
		return
	end
	self.Ready = true
	self.Loading.Visible = false
	self.Buttons.Visible = true
	if self.Root.Visible then
		UIKit.focus(self.PlayButton)
	end
end

function MainMenu:StartCinematic()
	RunService:UnbindFromRenderStep("ArcanaMenuCamera")
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local angle = math.random() * math.pi * 2
	local elapsed = 0
	RunService:BindToRenderStep("ArcanaMenuCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		elapsed += dt
		angle += dt * 0.045
		-- Au-dessus des toits de la cité, l'arène au centre de l'image.
		local radius = 135 + math.sin(elapsed * 0.11) * 20
		local height = 68 + math.sin(elapsed * 0.17) * 10
		local position = Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
		camera.CFrame = CFrame.lookAt(position, Vector3.new(0, 12, 0))
		camera.FieldOfView = 55
	end)
end

function MainMenu:StopCinematic()
	RunService:UnbindFromRenderStep("ArcanaMenuCamera")
	workspace.CurrentCamera.FieldOfView = 70
end

function MainMenu:Show()
	self:Layout()
	self.Showing = true
	self.Root.Visible = true
	self.Particles.Visible = true
	local target = self.ContentPosition or UDim2.new(0.06, 0, 0.5, 0)
	self.Content.Position = target - UDim2.fromScale(0.025, 0)
	UIKit.fade(self.Root, true, 1)
	UIKit.tween(self.Content, 1.2, { Position = target }, Enum.EasingStyle.Quint)
	-- Joystick et bouton de saut masqués sur le menu (mobile).
	pcall(function()
		game:GetService("GuiService").TouchControlsEnabled = false
	end)
	self:StartCinematic()
	if self.Ready then
		UIKit.focus(self.PlayButton)
	end
end

function MainMenu:Hide()
	self:StopCinematic()
	self.Showing = false
	self.Particles.Visible = false
	pcall(function()
		game:GetService("GuiService").TouchControlsEnabled = true
	end)
	UIKit.fade(self.Root, false, 0.45)
	task.delay(0.5, function()
		if not self.Showing then
			self.Root.Visible = false
		end
	end)
end

return MainMenu
