-- Ambiances sonores 3D (SoundData.Ambient) et petits effets : invites,
-- notifications, plongeons et coups reçus.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local SoundData = require(Configs:WaitForChild("SoundData"))
local UIKit = require(script.Parent:WaitForChild("UI"):WaitForChild("UIKit"))
local Notify: RemoteEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notify")

local function enabled(): boolean
	return UIKit.Settings.Sound ~= false
end

-- Effets ponctuels.
local effectCache: { [string]: Sound } = {}
local function effect(name: string, pitch: number?)
	local data = SoundData.Effects[name]
	if not (data and data.Id ~= "" and enabled()) then
		return
	end
	local sound = effectCache[name]
	if not sound then
		sound = Instance.new("Sound")
		sound.SoundId = data.Id
		sound.Parent = SoundService
		effectCache[name] = sound
	end
	sound.Volume = data.Volume or 0.5
	sound.PlaybackSpeed = (data.Pitch or 1) * (pitch or 1)
	sound:Play()
end

ProximityPromptService.PromptTriggered:Connect(function()
	effect("Prompt", 0.95 + math.random() * 0.1)
end)
-- Seules les vraies récompenses sonnent ; les infos restent silencieuses.
Notify.OnClientEvent:Connect(function(_, kind: string?)
	if kind == "Gold" then
		effect("Reward")
	end
end)

local function watchCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local lastHealth = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < lastHealth - 1 then
			effect("Hurt", 0.9 + math.random() * 0.2)
		end
		lastHealth = health
	end)
	humanoid.StateChanged:Connect(function(old, new)
		if new == Enum.HumanoidStateType.Swimming and old == Enum.HumanoidStateType.Freefall then
			effect("Splash")
		end
	end)
end
local player = Players.LocalPlayer
if player.Character then
	task.spawn(watchCharacter, player.Character)
end
player.CharacterAdded:Connect(watchCharacter)

-- Ambiances en boucle, chacune sur un émetteur invisible.
while not workspace:GetAttribute("WorldReady") do
	workspace:GetAttributeChangedSignal("WorldReady"):Wait()
end
local holder = Instance.new("Folder")
holder.Name = "AmbientSounds"
holder.Parent = workspace

local loops = {}
for _, data in ipairs(SoundData.Ambient) do
	if data.Id ~= "" then
		local emitter = Instance.new("Part")
		emitter.Name = data.Name
		emitter.Anchored = true
		emitter.CanCollide = false
		emitter.CanQuery = false
		emitter.CanTouch = false
		emitter.Transparency = 1
		emitter.Size = Vector3.one
		emitter.Position = Vector3.new(data.Center.X, data.Y, data.Center.Y)
		emitter.Parent = holder
		local sound = Instance.new("Sound")
		sound.SoundId = data.Id
		sound.Looped = true
		sound.Volume = 0
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = data.Radius * 0.25
		sound.RollOffMaxDistance = data.Radius
		sound.Parent = emitter
		sound:Play()
		table.insert(loops, { Sound = sound, Data = data })
	end
end

-- Fondu jour / nuit et respect du réglage « Son ».
while true do
	local t = Lighting.ClockTime
	local night = t < 6 or t > 18
	for _, loop in ipairs(loops) do
		local d = loop.Data
		local active = enabled() and not (d.Night and not night) and not (d.Day and night)
		local target = active and d.Volume or 0
		if math.abs(loop.Sound.Volume - target) > 0.01 then
			TweenService:Create(loop.Sound, TweenInfo.new(3), { Volume = target }):Play()
		end
	end
	task.wait(2)
end
