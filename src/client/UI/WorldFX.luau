-- Effets locaux du monde : cristal de l'autel, PNJ qui se tournent vers le
-- joueur, bulles de parole au-dessus des villageois et indicateur de quête.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local VillageData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("VillageData"))

local WorldFX = {}

local player = Players.LocalPlayer

local villagerLines: { [string]: { string } } = {}
for _, list in ipairs({ VillageData.Villagers }) do
	for _, villager in ipairs(list) do
		villagerLines[villager.Name] = villager.Lines
	end
end

local function tween(inst: Instance, duration: number, goal, style: Enum.EasingStyle?)
	local t = TweenService:Create(inst, TweenInfo.new(duration, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

-- Bulle de parole flottante (taille en studs : elle suit la perspective).
function WorldFX.bubble(head: BasePart, text: string, duration: number?)
	local existing = head:FindFirstChild("SpeechBubble")
	if existing then
		existing:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "SpeechBubble"
	gui.Adornee = head
	gui.Size = UDim2.new(10, 0, 3, 0)
	gui.StudsOffset = Vector3.new(0, 4.6, 0)
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	gui.Parent = head

	local holder = Instance.new("CanvasGroup")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.GroupTransparency = 1
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = holder

	-- Ombre douce.
	local shadow = Instance.new("Frame")
	shadow.BackgroundColor3 = Color3.new(0, 0, 0)
	shadow.BackgroundTransparency = 0.75
	shadow.Position = UDim2.fromScale(0.02, 0.1)
	shadow.Size = UDim2.fromScale(0.98, 0.72)
	shadow.Parent = holder
	local shadowCorner = Instance.new("UICorner")
	shadowCorner.CornerRadius = UDim.new(0.35, 0)
	shadowCorner.Parent = shadow

	local tail = Instance.new("Frame")
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.fromScale(0.5, 0.74)
	tail.Size = UDim2.fromScale(0.06, 0.2)
	tail.Rotation = 45
	tail.BackgroundColor3 = Color3.fromRGB(246, 242, 255)
	tail.BorderSizePixel = 0
	tail.Parent = holder
	local tailStroke = Instance.new("UIStroke")
	tailStroke.Color = Color3.fromRGB(190, 160, 255)
	tailStroke.Thickness = 2
	tailStroke.Parent = tail
	local tailRatio = Instance.new("UIAspectRatioConstraint")
	tailRatio.AspectRatio = 1
	tailRatio.Parent = tail

	local bubble = Instance.new("Frame")
	bubble.Size = UDim2.fromScale(1, 0.72)
	bubble.BackgroundColor3 = Color3.new(1, 1, 1)
	bubble.Parent = holder
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.35, 0)
	corner.Parent = bubble
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(232, 224, 252))
	gradient.Rotation = 90
	gradient.Parent = bubble
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(190, 160, 255)
	stroke.Thickness = 2
	stroke.Parent = bubble

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.07, 0.12)
	label.Size = UDim2.fromScale(0.86, 0.76)
	label.Text = text
	label.TextScaled = true
	label.TextWrapped = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(45, 32, 75)
	label.Parent = bubble
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 40
	constraint.Parent = label

	tween(holder, 0.25, { GroupTransparency = 0 })
	tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(duration or 4, function()
		if gui.Parent then
			tween(holder, 0.3, { GroupTransparency = 1 })
			tween(scale, 0.3, { Scale = 0.7 }).Completed:Wait()
			gui:Destroy()
		end
	end)
end

function WorldFX.start(getQuestsReady: () -> number)
	local world = workspace:WaitForChild("World", 180)
	if not world then
		return
	end

	-- Cristal flottant de l'autel.
	task.spawn(function()
		local arena = world:WaitForChild("Arena", 60)
		local crystal = arena and arena:WaitForChild("ArcanaCrystal", 60)
		if not crystal then
			return
		end
		local base = crystal.CFrame
		local rotation = base - base.Position
		local t = 0
		RunService.RenderStepped:Connect(function(dt)
			t += dt
			crystal.CFrame = CFrame.new(base.Position + Vector3.new(0, math.sin(t * 1.4) * 0.8, 0)) * CFrame.Angles(0, t * 0.8, 0) * rotation
		end)
	end)

	-- PNJ fixes : ils se tournent vers le joueur proche + indicateur de quête.
	task.spawn(function()
		local folder = world:WaitForChild("NPCs", 300)
		if not folder then
			return
		end
		task.wait(2)
		local npcs = {}
		for _, model in ipairs(folder:GetChildren()) do
			local root = model:FindFirstChild("HumanoidRootPart")
			if root then
				table.insert(npcs, { Root = root, Home = root.CFrame, Current = root.CFrame })
			end
		end

		local orin = folder:FindFirstChild("Orin")
		local marker = nil
		if orin and orin:FindFirstChild("Head") then
			marker = Instance.new("BillboardGui")
			marker.Size = UDim2.fromOffset(64, 64)
			marker.StudsOffset = Vector3.new(0, 7, 0)
			marker.AlwaysOnTop = true
			marker.MaxDistance = 300
			marker.Adornee = orin.Head
			marker.Enabled = false
			marker.Parent = orin
			local badge = Instance.new("Frame")
			badge.AnchorPoint = Vector2.new(0.5, 0.5)
			badge.Position = UDim2.fromScale(0.5, 0.5)
			badge.Size = UDim2.fromScale(0.8, 0.8)
			badge.BackgroundColor3 = Color3.fromRGB(255, 205, 90)
			badge.Parent = marker
			local badgeCorner = Instance.new("UICorner")
			badgeCorner.CornerRadius = UDim.new(0.5, 0)
			badgeCorner.Parent = badge
			local badgeStroke = Instance.new("UIStroke")
			badgeStroke.Color = Color3.fromRGB(120, 60, 10)
			badgeStroke.Thickness = 3
			badgeStroke.Parent = badge
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.Text = "!"
			label.TextScaled = true
			label.Font = Enum.Font.GothamBlack
			label.TextColor3 = Color3.fromRGB(90, 40, 5)
			label.Parent = badge
		end

		local t = 0
		RunService.Heartbeat:Connect(function(dt)
			t += dt
			if marker then
				marker.Enabled = getQuestsReady() > 0
				marker.StudsOffset = Vector3.new(0, 7 + math.sin(t * 3) * 0.35, 0)
			end
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			for _, npc in ipairs(npcs) do
				local home: CFrame = npc.Home
				local target = home
				if hrp and (hrp.Position - home.Position).Magnitude < 16 then
					local flat = Vector3.new(hrp.Position.X, home.Position.Y, hrp.Position.Z)
					if (flat - home.Position).Magnitude > 0.5 then
						target = CFrame.lookAt(home.Position, flat)
					end
				end
				npc.Current = npc.Current:Lerp(target, math.min(1, dt * 5))
				npc.Root.CFrame = npc.Current
			end
		end)
	end)

	-- Bulles de parole ambiantes autour du joueur.
	task.spawn(function()
		local npcFolder = world:WaitForChild("NPCs", 300)
		local walkerFolder = world:WaitForChild("Walkers", 300)
		while true do
			task.wait(math.random(40, 80) / 10)
			local camera = workspace.CurrentCamera
			local candidates = {}
			for _, folder in ipairs({ npcFolder, walkerFolder }) do
				if folder then
					for _, model in ipairs(folder:GetChildren()) do
						local head = model:FindFirstChild("Head")
						if head and camera and (head.Position - camera.CFrame.Position).Magnitude < 70 and not head:FindFirstChild("SpeechBubble") then
							local id = model:GetAttribute("NpcId")
							local lines = id and VillageData.Npcs[id] and VillageData.Npcs[id].Lines or villagerLines[model.Name]
							if lines then
								table.insert(candidates, { Head = head, Lines = lines })
							end
						end
					end
				end
			end
			if #candidates > 0 then
				local pick = candidates[math.random(#candidates)]
				WorldFX.bubble(pick.Head, pick.Lines[math.random(#pick.Lines)])
			end
		end
	end)
end

return WorldFX
