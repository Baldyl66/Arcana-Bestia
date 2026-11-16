-- Carte du monde dessinée à partir du plan (VillageData.Layout) : toits,
-- jardins, rues et places de la cité. Sert à la mini-carte du HUD et à la grande carte
-- avec ses points de téléportation.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local VillageData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("VillageData"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local L = VillageData.Layout
local HALF = L.Half

local WorldMap = {}

-- Coordonnées monde (x, z) vers position relative sur la carte (0..1).
function WorldMap.toMap(x: number, z: number): Vector2
	return Vector2.new((x + HALF) / (HALF * 2), (z + HALF) / (HALF * 2))
end

local function blob(parent: Instance, center: Vector2, radius: number, color: Color3, transparency: number?, zIndex: number?): Frame
	local p = WorldMap.toMap(center.X, center.Y)
	local size = radius / HALF
	local f = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(p.X, p.Y),
		Size = UDim2.fromScale(size, size),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency or 0,
		BorderSizePixel = 0,
		ZIndex = zIndex or 2,
		Parent = parent,
	})
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = f })
	return f
end

local function line(parent: Instance, a: Vector2, b: Vector2, width: number, color: Color3, zIndex: number?)
	local pa, pb = WorldMap.toMap(a.X, a.Y), WorldMap.toMap(b.X, b.Y)
	local mid = (pa + pb) / 2
	local frame = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(mid.X, mid.Y),
		Size = UDim2.new((pb - pa).Magnitude, 0, 0, width),
		Rotation = math.deg(math.atan2(pb.Y - pa.Y, pb.X - pa.X)),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = zIndex or 3,
		Parent = parent,
	})
	UIKit.corner(frame, width)
	return frame
end

-- Relevé « vue du ciel » du vrai monde, rendu comme une carte dessinée :
-- chaque case est classée (prairie, forêt, eau, roche, route, bâtiment...),
-- les petites taches isolées sont lissées, puis on ajoute un ombrage du relief
-- en paliers, des courbes de niveau et un liseré clair sur les rives.
local GRID = 128
local survey: { { Color3 } }? = nil
local surveyDone = Instance.new("BindableEvent")
local surveying = false

local function shadeColor(c: Color3, f: number): Color3
	return Color3.new(math.clamp(c.R * f, 0, 1), math.clamp(c.G * f, 0, 1), math.clamp(c.B * f, 0, 1))
end

-- Palette de la carte (catégories de terrain).
local PALETTE = {
	Meadow = Color3.fromRGB(156, 196, 110),
	Hill = Color3.fromRGB(132, 176, 96),
	Upland = Color3.fromRGB(150, 160, 112),
	Forest = Color3.fromRGB(72, 120, 70),
	Rock = Color3.fromRGB(160, 154, 146),
	Snow = Color3.fromRGB(242, 245, 250),
	Sand = Color3.fromRGB(230, 214, 168),
	Field = Color3.fromRGB(196, 168, 108),
	Road = Color3.fromRGB(222, 204, 160),
	Plaza = Color3.fromRGB(208, 198, 178),
	Shallow = Color3.fromRGB(128, 198, 222),
	Deep = Color3.fromRGB(64, 136, 192),
	Shore = Color3.fromRGB(196, 232, 240),
}
local M = Enum.Material
local MATERIAL_CATEGORY = {
	[M.Rock] = "Rock", [M.Slate] = "Rock", [M.Basalt] = "Rock", [M.Granite] = "Rock",
	[M.Snow] = "Snow", [M.Glacier] = "Snow",
	[M.Sand] = "Sand",
	[M.Mud] = "Field",
	[M.Cobblestone] = "Plaza", [M.Pavement] = "Plaza",
}

local function runSurvey()
	if survey or surveying then
		return
	end
	surveying = true
	while not workspace:GetAttribute("VillageReady") do
		task.wait(0.5)
	end
	local terrain = workspace.Terrain
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = false
	local exclude = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	for _, name in ipairs({ "AmbientSounds" }) do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(exclude, f)
		end
	end
	local world = workspace:FindFirstChild("World")
	local treeFolders = {}
	for _, name in ipairs({ "Trees" }) do
		local f = world and world:FindFirstChild(name)
		if f then
			table.insert(treeFolders, f)
		end
	end
	params.FilterDescendantsInstances = exclude
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Include
	groundParams.FilterDescendantsInstances = { terrain }

	local heights, kinds, colors = {}, {}, {}
	local step = HALF * 2 / GRID
	for gx = 1, GRID do
		heights[gx], kinds[gx], colors[gx] = {}, {}, {}
		for gz = 1, GRID do
			local x, z = -HALF + (gx - 0.5) * step, -HALF + (gz - 0.5) * step
			local hit = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -600, 0), params)
			local kind, h, color = "Meadow", 0, nil
			if hit then
				h = hit.Position.Y
				if hit.Instance == terrain then
					if hit.Material == M.Water then
						local floor = workspace:Raycast(hit.Position - Vector3.new(0, 0.5, 0), Vector3.new(0, -60, 0), params)
						local depth = floor and (hit.Position.Y - floor.Position.Y) or 30
						kind = depth > 6 and "Deep" or "Shallow"
					else
						kind = MATERIAL_CATEGORY[hit.Material] or (h > 70 and "Upland" or h > 22 and "Hill" or "Meadow")
					end
				else
					local isTree = false
					for _, f in ipairs(treeFolders) do
						if hit.Instance:IsDescendantOf(f) then
							isTree = true
							break
						end
					end
					if isTree then
						kind = "Forest"
						-- Hauteur du sol sous l'arbre pour l'ombrage.
						local ground = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -600, 0), groundParams)
						h = ground and ground.Position.Y or h
					else
						kind = "Building"
						-- Couleur du toit, légèrement adoucie pour rester lisible.
						color = (hit.Instance :: BasePart).Color:Lerp(Color3.fromRGB(200, 185, 160), 0.25)
					end
				end
			end
			heights[gx][gz], kinds[gx][gz], colors[gx][gz] = h, kind, color
		end
		if gx % 4 == 0 then
			task.wait()
		end
	end

	-- Lissage : une case de terrain entourée d'une autre catégorie majoritaire
	-- prend cette catégorie (supprime le « bruit »). Les bâtiments sont gardés.
	local smoothKinds = {}
	for gx = 1, GRID do
		smoothKinds[gx] = {}
		for gz = 1, GRID do
			local k = kinds[gx][gz]
			if k ~= "Building" then
				local counts = {}
				for dx = -1, 1 do
					for dz = -1, 1 do
						local n = kinds[gx + dx] and kinds[gx + dx][gz + dz]
						if n and n ~= "Building" then
							counts[n] = (counts[n] or 0) + 1
						end
					end
				end
				local best, bestCount = k, counts[k] or 0
				for n, c in pairs(counts) do
					if c > bestCount + 1 then
						best, bestCount = n, c
					end
				end
				k = best
			end
			smoothKinds[gx][gz] = k
		end
	end

	local function isWater(k: string?): boolean
		return k == "Shallow" or k == "Deep"
	end
	local result = {}
	for gx = 1, GRID do
		result[gx] = {}
		for gz = 1, GRID do
			local k = smoothKinds[gx][gz]
			local c = k == "Building" and colors[gx][gz] or PALETTE[k]
			if isWater(k) then
				-- Liseré clair le long des rives.
				for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
					local n = smoothKinds[gx + d[1]] and smoothKinds[gx + d[1]][gz + d[2]]
					if n and not isWater(n) then
						c = PALETTE.Shore
						break
					end
				end
			elseif k ~= "Building" then
				-- Ombrage du relief en trois paliers (lumière du nord-ouest).
				local h = heights[gx][gz]
				local nw = heights[math.max(gx - 1, 1)][math.max(gz - 1, 1)]
				local slope = h - nw
				local f = slope > 2.5 and 1.08 or slope < -2.5 and 0.86 or 1
				-- Courbes de niveau tous les 30 studs.
				local band = math.floor(h / 30)
				local east = gx < GRID and heights[gx + 1][gz] or h
				local south = gz < GRID and heights[gx][gz + 1] or h
				if h > 14 and (math.floor(east / 30) ~= band or math.floor(south / 30) ~= band) then
					f *= 0.88
				end
				c = shadeColor(c, f)
			end
			result[gx][gz] = c
		end
	end
	survey = result
	surveyDone:Fire()
end

-- Routes : mêmes courbes lissées que le serveur (Chaikin), dessinées par-dessus.
local function drawRoads(parent: Frame, detailed: boolean)
	-- Axe de chaque rue : les toits débordent et cachent les ruelles étroites.
	for _, r in ipairs(L.Paths) do
		local size = r[2] - r[1]
		local a, b
		if size.X >= size.Y then
			a, b = Vector2.new(r[1].X, (r[1].Y + r[2].Y) / 2), Vector2.new(r[2].X, (r[1].Y + r[2].Y) / 2)
		else
			a, b = Vector2.new((r[1].X + r[2].X) / 2, r[1].Y), Vector2.new((r[1].X + r[2].X) / 2, r[2].Y)
		end
		line(parent, a, b, detailed and 4 or 2, PALETTE.Road, 4)
	end
	for _, seg in ipairs(L.StonePaths or {}) do
		line(parent, seg[1], seg[2], detailed and 3 or 1, PALETTE.Road, 4)
	end
end

-- Peint le relevé dans `canvas` : les cases voisines de même teinte sont
-- fusionnées en bandes pour limiter le nombre d'éléments d'interface.
local function paint(canvas: Frame)
	if not survey then
		surveyDone.Event:Wait()
	end
	local data = survey :: { { Color3 } }
	local function key(c: Color3): number
		return math.floor(c.R * 31) * 1024 + math.floor(c.G * 31) * 32 + math.floor(c.B * 31)
	end
	local cell = 1 / GRID
	for gz = 1, GRID do
		local gx = 1
		while gx <= GRID do
			local c = data[gx][gz]
			local k = key(c)
			local run = 1
			while gx + run <= GRID and key(data[gx + run][gz]) == k do
				run += 1
			end
			UIKit.new("Frame", {
				BorderSizePixel = 0,
				BackgroundColor3 = c,
				Position = UDim2.fromScale((gx - 1) * cell, (gz - 1) * cell),
				Size = UDim2.new(run * cell, 1, cell, 1),
				ZIndex = 1,
				Parent = canvas,
			})
			gx += run
		end
		if gz % 10 == 0 then
			task.wait()
		end
	end
end

-- Dessine la carte dans `parent` (carré). Retourne le marqueur du joueur.
function WorldMap.draw(parent: Frame, detailed: boolean): Frame
	parent.ClipsDescendants = true
	parent.BackgroundColor3 = Color3.fromRGB(40, 55, 35)
	local canvas = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = parent })
	-- Carte illustrée (VillageData.MapImage) si elle est fournie, sinon relevé
	-- vue du ciel du vrai monde.
	local image = VillageData.MapImage
	if type(image) == "string" and image ~= "" then
		UIKit.new("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Image = image, ScaleType = Enum.ScaleType.Stretch, ZIndex = 1,
			Parent = canvas })
	else
		task.spawn(runSurvey)
		task.spawn(paint, canvas)
		drawRoads(parent, detailed)
	end
	-- Vignette et cadre intérieur pour l'effet « parchemin ».
	local vignette = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = parent })
	UIKit.stroke(vignette, Color3.fromRGB(20, 15, 10), detailed and 10 or 5, 0.5)
	if detailed then
		-- Rose des vents.
		local rose = UIKit.new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 16), Size = UDim2.fromOffset(46, 46),
			BackgroundColor3 = Color3.fromRGB(30, 22, 15), BackgroundTransparency = 0.3, ZIndex = 6, Parent = parent })
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = rose })
		UIKit.stroke(rose, Color3.fromRGB(232, 190, 105), 2, 0)
		UIKit.label({ Text = "N", Font = UIKit.Fonts.Black, TextColor3 = Color3.fromRGB(255, 225, 150), Position = UDim2.fromScale(0, 0.02),
			Size = UDim2.fromScale(1, 0.5), ZIndex = 7, Parent = rose }, 16)
		local needle = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.62), Size = UDim2.fromOffset(9, 9),
			Rotation = 45, BackgroundColor3 = Color3.fromRGB(220, 60, 60), ZIndex = 7, Parent = rose })
		needle.BorderSizePixel = 0
	end

	-- Marqueur du joueur : flèche dorée orientée comme la caméra.
	local marker = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(detailed and 22 or 14, detailed and 22 or 14),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = parent,
	})
	local arrow = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.75, 0.75),
		Rotation = 45,
		BackgroundColor3 = Color3.fromRGB(255, 225, 120),
		ZIndex = 20,
		Parent = marker,
	})
	UIKit.stroke(arrow, Color3.fromRGB(60, 30, 10), 2, 0)
	local tip = UIKit.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(230, 60, 60),
		Size = UDim2.fromScale(0.5, 0.5),
		ZIndex = 21,
		Parent = arrow,
	})
	tip.Name = "Tip"
	return marker
end

-- Place le marqueur du joueur à chaque image tant que la carte est visible.
function WorldMap.track(marker: Frame, isVisible: () -> boolean)
	RunService.RenderStepped:Connect(function()
		if not isVisible() then
			return
		end
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local camera = workspace.CurrentCamera
		if not (root and camera) then
			return
		end
		local p = WorldMap.toMap(root.Position.X, root.Position.Z)
		marker.Position = UDim2.fromScale(p.X, p.Y)
		local look = camera.CFrame.LookVector
		-- La pointe (coin haut-gauche du losange) suit la direction de la caméra.
		marker.Rotation = math.deg(math.atan2(look.Z, look.X)) + 90
	end)
end

-- Grande carte : le plan illustré dans un cadre doré à gauche, la liste des
-- destinations à droite (un clic téléporte). Les points de la carte sont de
-- petits repères qui s'illuminent quand on survole leur destination.
local GOLD = Color3.fromRGB(232, 190, 105)
local INK = Color3.fromRGB(22, 15, 32)

function WorldMap.panel(parent: Instance, teleport: (id: string) -> ())
	local panel = UIKit.panel(parent, "CARTE DU MONDE")
	local content = panel.Content

	-- Carte : carré calé à gauche, sur toute la hauteur du contenu.
	local frame = UIKit.new("Frame", {
		Name = "MapFrame",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = content,
	})
	UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1, AspectType = Enum.AspectType.ScaleWithParentSize, DominantAxis = Enum.DominantAxis.Height, Parent = frame })
	UIKit.corner(frame, 10)
	UIKit.gradient(frame, Color3.fromRGB(120, 82, 46), Color3.fromRGB(66, 42, 24), 90)
	UIKit.stroke(frame, GOLD, 3, 0)
	-- Losanges dorés aux coins du cadre.
	for _, c in ipairs({ Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) }) do
		local gem = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(c.X, c.X == 0 and 7 or -7, c.Y, c.Y == 0 and 7 or -7),
			Size = UDim2.fromOffset(12, 12), Rotation = 45, BackgroundColor3 = GOLD, ZIndex = 30, Parent = frame })
		UIKit.stroke(gem, Color3.fromRGB(70, 40, 15), 1.5, 0)
	end
	local mapFrame = UIKit.new("Frame", {
		Name = "Map",
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -20, 1, -20),
		BackgroundColor3 = Color3.fromRGB(251, 246, 234),
		Parent = frame,
	})
	UIKit.corner(mapFrame, 4)
	UIKit.stroke(mapFrame, Color3.fromRGB(60, 38, 20), 2, 0)
	local marker = WorldMap.draw(mapFrame, true)
	WorldMap.track(marker, function()
		return panel.IsOpen
	end)

	-- Colonne des destinations, à droite de la carte.
	local side = UIKit.new("Frame", {
		Name = "Destinations",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 320, 1, 0),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.25,
		Parent = content,
	})
	UIKit.corner(side, 10)
	UIKit.stroke(side, GOLD, 1.5, 0.35)
	UIKit.label({ Text = "DESTINATIONS", Font = UIKit.Fonts.Title, TextColor3 = Color3.fromRGB(255, 225, 150), Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -32, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, Parent = side }, 26)
	local here = UIKit.label({ Text = "", Font = UIKit.Fonts.Bold, TextColor3 = UIKit.Colors.SubText, Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(1, -32, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, Parent = side }, 14)
	UIKit.new("Frame", { Position = UDim2.fromOffset(16, 64), Size = UDim2.new(1, -32, 0, 1), BackgroundColor3 = GOLD, BackgroundTransparency = 0.5,
		BorderSizePixel = 0, Parent = side })
	local list = UIKit.new("ScrollingFrame", {
		Position = UDim2.fromOffset(10, 72),
		Size = UDim2.new(1, -20, 1, -82),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = GOLD,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = side,
	})
	UIKit.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2),
		Parent = list })

	-- La colonne prend la largeur laissée par la carte (carré de la hauteur du
	-- contenu). Tailles en pixels « virtuels » : la fenêtre a son propre UIScale.
	local windowScale = panel.Window:FindFirstChildWhichIsA("UIScale")
	local function layout()
		local scale = windowScale and math.max(windowScale.Scale, 0.01) or 1
		local size = content.AbsoluteSize / scale
		side.Size = UDim2.new(0, math.max(240, size.X - size.Y - 18), 1, 0)
	end
	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)

	local pins = {}
	local rows = {}
	local function highlight(id: string?)
		for pid, pin in pairs(pins) do
			local on = pid == id
			UIKit.tween(pin.Scale, 0.15, { Scale = on and 1.6 or 1 }, Enum.EasingStyle.Back)
		end
		for rid, row in pairs(rows) do
			UIKit.tween(row, 0.12, { BackgroundTransparency = rid == id and 0.05 or 0.55 })
		end
	end

	for i, point in ipairs(VillageData.Teleports) do
		local color = point.Color or Color3.fromRGB(150, 235, 255)
		-- Repère sur la carte : losange coloré cerclé de brun.
		local p = WorldMap.toMap(point.Pos.X, point.Pos.Y)
		local pin = UIKit.new("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(p.X, p.Y),
			Size = UDim2.fromOffset(18, 18),
			Rotation = 45,
			BackgroundColor3 = color,
			Text = "",
			AutoButtonColor = false,
			Selectable = false,
			ZIndex = 10,
			Parent = mapFrame,
		})
		UIKit.stroke(pin, Color3.fromRGB(60, 30, 10), 2.5, 0)
		local pinScale = UIKit.new("UIScale", { Parent = pin })
		local dot = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.36, 0.36),
			BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 11, Parent = pin })
		dot.Active = false
		pins[point.Id] = { Scale = pinScale }

		-- Ligne de la liste : losange de couleur, nom, description, flèche.
		local row = UIKit.new("TextButton", {
			Name = point.Id,
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 54),
			BackgroundColor3 = Color3.fromRGB(70, 45, 105),
			BackgroundTransparency = 0.55,
			Text = "",
			AutoButtonColor = false,
			Selectable = true,
			Parent = list,
		})
		UIKit.corner(row, 8)
		UIKit.stroke(row, GOLD, 1, 0.6)
		rows[point.Id] = row
		local badge = UIKit.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(18, 18),
			Rotation = 45, BackgroundColor3 = color, Parent = row })
		UIKit.stroke(badge, Color3.fromRGB(255, 225, 150), 2, 0)
		badge.Active = false
		local name = UIKit.label({ Text = point.Label, Font = UIKit.Fonts.Black, TextColor3 = Color3.fromRGB(255, 240, 210), Position = UDim2.fromOffset(46, 7),
			Size = UDim2.new(1, -76, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, Parent = row }, 18)
		name.Active = false
		local desc = UIKit.label({ Text = point.Desc or "", Font = UIKit.Fonts.Body, TextColor3 = UIKit.Colors.SubText, Position = UDim2.fromOffset(46, 29),
			Size = UDim2.new(1, -76, 0, 17), TextXAlignment = Enum.TextXAlignment.Left, Parent = row }, 14)
		desc.Active = false
		local arrow = UIKit.label({ Text = "›", Font = UIKit.Fonts.Black, TextColor3 = GOLD, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(20, 30), Parent = row }, 28)
		arrow.Active = false

		local function travel()
			UIKit.playSound("Reveal", 0.4, 1.3)
			teleport(point.Id)
		end
		for _, b in ipairs({ row, pin }) do
			b.MouseEnter:Connect(function()
				highlight(point.Id)
			end)
			b.MouseLeave:Connect(function()
				highlight(nil)
			end)
			b.Activated:Connect(travel)
		end
		row.SelectionGained:Connect(function()
			highlight(point.Id)
		end)
	end

	-- « Tu es près de » : destination la plus proche du joueur, à l'ouverture.
	local function refreshHere()
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			here.Text = ""
			return
		end
		local flat = Vector2.new(root.Position.X, root.Position.Z)
		local best, label = math.huge, nil
		for _, point in ipairs(VillageData.Teleports) do
			local d = (flat - point.Pos).Magnitude
			if d < best then
				best, label = d, point.Label
			end
		end
		here.Text = if label then "Tu es près de : " .. label else ""
	end
	local baseOpen = panel.Open
	function panel:Open()
		refreshHere()
		highlight(nil)
		baseOpen(self)
		task.defer(layout)
	end
	task.defer(layout)
	return panel
end

return WorldMap
