--!strict
-- src/shared/CyberGoggles.luau
-- Visor Cibernético FPV para el Operador de Drones
local CyberGoggles = {}

local COLOR_FRAME = Color3.fromRGB(18, 22, 30)
local COLOR_NEON_ACTIVE = Color3.fromRGB(0, 255, 230)
local COLOR_NEON_STANDBY = Color3.fromRGB(40, 50, 65)

function CyberGoggles.Attach(character: Model): Model?
	local head = character:WaitForChild("Head", 5) :: BasePart?
	if not head then
		warn("[CyberGoggles] Head no disponible para equipar gafas.")
		return nil
	end

	local existing = character:FindFirstChild("CyberFPVVisor")
	if existing then
		existing:Destroy()
	end

	local visorModel = Instance.new("Model")
	visorModel.Name = "CyberFPVVisor"

	-- Marco exterior de las gafas cibernéticas
	local frame = Instance.new("Part")
	frame.Name = "VisorFrame"
	frame.Size = Vector3.new(1.6, 0.45, 0.5)
	frame.Material = Enum.Material.Metal
	frame.Color = COLOR_FRAME
	frame.CanCollide = false
	frame.Massless = true
	frame.CFrame = head.CFrame * CFrame.new(0, 0.12, -0.65)
	frame.Parent = visorModel

	local frameWeld = Instance.new("WeldConstraint")
	frameWeld.Part0 = head
	frameWeld.Part1 = frame
	frameWeld.Parent = frame

	-- Lente holográfica frontal de neón
	local lens = Instance.new("Part")
	lens.Name = "VisorLens"
	lens.Size = Vector3.new(1.45, 0.35, 0.15)
	lens.Material = Enum.Material.Neon
	lens.Color = COLOR_NEON_STANDBY
	lens.CanCollide = false
	lens.Massless = true
	lens.CFrame = frame.CFrame * CFrame.new(0, 0, -0.2)
	lens.Parent = visorModel

	local lensWeld = Instance.new("WeldConstraint")
	lensWeld.Part0 = frame
	lensWeld.Part1 = lens
	lensWeld.Parent = lens

	-- Antena transmisora lateral
	local antenna = Instance.new("Part")
	antenna.Name = "Antenna"
	antenna.Size = Vector3.new(0.12, 0.6, 0.12)
	antenna.Material = Enum.Material.Neon
	antenna.Color = COLOR_NEON_STANDBY
	antenna.CanCollide = false
	antenna.Massless = true
	antenna.CFrame = frame.CFrame * CFrame.new(-0.85, 0.3, 0.1)
	antenna.Parent = visorModel

	local antWeld = Instance.new("WeldConstraint")
	antWeld.Part0 = frame
	antWeld.Part1 = antenna
	antWeld.Parent = antenna

	-- Luz que ilumina el rostro del personaje en modo activo
	local faceLight = Instance.new("PointLight")
	faceLight.Name = "VisorGlow"
	faceLight.Color = COLOR_NEON_ACTIVE
	faceLight.Brightness = 0
	faceLight.Range = 8
	faceLight.Shadows = false
	faceLight.Parent = lens

	visorModel.Parent = character
	print("[CyberGoggles] Gafas FPV cibernéticas equipadas en el avatar.")
	return visorModel
end

function CyberGoggles.SetOnline(character: Model, isOnline: boolean)
	local visorModel = character:FindFirstChild("CyberFPVVisor")
	if not visorModel then return end

	local lens = visorModel:FindFirstChild("VisorLens") :: BasePart?
	local antenna = visorModel:FindFirstChild("Antenna") :: BasePart?
	local glow = lens and lens:FindFirstChild("VisorGlow") :: PointLight?

	if isOnline then
		if lens then lens.Color = COLOR_NEON_ACTIVE end
		if antenna then antenna.Color = COLOR_NEON_ACTIVE end
		if glow then glow.Brightness = 3 end
	else
		if lens then lens.Color = COLOR_NEON_STANDBY end
		if antenna then antenna.Color = COLOR_NEON_STANDBY end
		if glow then glow.Brightness = 0 end
	end
end

function CyberGoggles.Remove(character: Model)
	local visorModel = character:FindFirstChild("CyberFPVVisor")
	if visorModel then
		visorModel:Destroy()
	end
end

return CyberGoggles
