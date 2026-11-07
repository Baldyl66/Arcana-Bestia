-- Limite douce du monde : en approchant du bord, l'écran s'assombrit et se
-- désature, un message invite à faire demi-tour, puis le joueur est
-- doucement repoussé vers l'intérieur (les murs invisibles ne sont qu'un
-- dernier filet de sécurité).
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local L = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("VillageData")).Layout

-- Les remparts sont le bord de la carte : ceci ne sert que si un joueur passe derrière.
local HALF = L.Half + 10
local FADE_START = HALF - 8 -- début de l'assombrissement
local PUSH_START = HALF - 5 -- début de la poussée vers l'intérieur

local player = Players.LocalPlayer

local grade = Instance.new("ColorCorrectionEffect")
grade.Name = "BoundaryGrade"
grade.Parent = Lighting

local gui = Instance.new("ScreenGui")
gui.Name = "Boundary"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")

-- Voile sombre avec vignettage sur les bords.
local veil = Instance.new("Frame")
veil.Size = UDim2.fromScale(1, 1)
veil.BackgroundColor3 = Color3.fromRGB(8, 10, 22)
veil.BackgroundTransparency = 1
veil.BorderSizePixel = 0
veil.Parent = gui
local vignette = Instance.new("UIGradient")
vignette.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.7), NumberSequenceKeypoint.new(0.5, 0.85),
	NumberSequenceKeypoint.new(0.7, 0.7), NumberSequenceKeypoint.new(1, 0),
})
vignette.Parent = veil

local message = Instance.new("TextLabel")
message.AnchorPoint = Vector2.new(0.5, 0.5)
message.Position = UDim2.fromScale(0.5, 0.36)
message.Size = UDim2.fromScale(0.7, 0.08)
message.BackgroundTransparency = 1
message.Font = Enum.Font.Fantasy
message.TextScaled = true
message.TextColor3 = Color3.fromRGB(235, 225, 200)
message.TextStrokeColor3 = Color3.fromRGB(20, 15, 10)
message.Text = "Ces terres sont encore inexplorées..."
message.TextTransparency = 1
message.TextStrokeTransparency = 1
message.Parent = gui
local sub = message:Clone()
sub.Position = UDim2.fromScale(0.5, 0.43)
sub.Size = UDim2.fromScale(0.5, 0.045)
sub.Text = "Fais demi-tour, voyageur."
sub.Parent = gui

local current = 0
RunService.RenderStepped:Connect(function(dt)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local target = 0
	if root then
		local p = root.Position
		local reach = math.max(math.abs(p.X), math.abs(p.Z))
		target = math.clamp((reach - FADE_START) / (HALF - 6 - FADE_START), 0, 1)
		-- Poussée douce vers l'intérieur, de plus en plus forte.
		if reach > PUSH_START then
			local inward = Vector3.new(
				math.abs(p.X) >= reach - 0.01 and -math.sign(p.X) or 0, 0,
				math.abs(p.Z) >= reach - 0.01 and -math.sign(p.Z) or 0)
			local strength = math.clamp((reach - PUSH_START) / (HALF - PUSH_START), 0, 1)
			local v = root.AssemblyLinearVelocity
			local along = v:Dot(inward)
			local wanted = 6 + 30 * strength
			if along < wanted then
				root.AssemblyLinearVelocity = v + inward * (wanted - along) * math.clamp(dt * 8, 0, 1)
			end
		end
	end
	current += (target - current) * math.clamp(dt * 4, 0, 1)
	local t = current * current * (3 - 2 * current)
	grade.Brightness = -0.28 * t
	grade.Saturation = -0.55 * t
	grade.Contrast = 0.1 * t
	grade.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(190, 200, 235), t)
	veil.BackgroundTransparency = 1 - 0.55 * t
	local text = 1 - math.clamp((t - 0.25) / 0.5, 0, 1)
	message.TextTransparency, message.TextStrokeTransparency = text, math.max(text, 0.4)
	sub.TextTransparency, sub.TextStrokeTransparency = text, math.max(text, 0.4)
end)
