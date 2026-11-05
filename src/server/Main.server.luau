--!strict
-- src/server/Main.server.luau
-- Servidor Principal v4.1: Red de Helipuertos, Control Físico, Red Centralizada y Seguridad Anti-Exploits
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local NetworkEvents = require(ReplicatedStorage:WaitForChild("NetworkEvents", 5) :: ModuleScript)
NetworkEvents.Init()

local flightStateEvent       = NetworkEvents.Get(NetworkEvents.Names.DroneFlightState)
local claimDeliveryEvent     = NetworkEvents.Get(NetworkEvents.Names.ClaimDelivery)
local deliveryConfirmedEvent = NetworkEvents.Get(NetworkEvents.Names.DeliveryConfirmed)

----------------------------------------------------------------------
-- 1. GENERADOR DE HELIPUERTOS Y RAMPA DE ACCESO
----------------------------------------------------------------------
local function createHelipad(name: string, position: Vector3, primaryColor: Color3, hasRamp: boolean): Model
	local model = Instance.new("Model")
	model.Name = name

	local base = Instance.new("Part")
	base.Name = "BasePad"
	base.Size = Vector3.new(28, 3, 28)
	base.Position = position
	base.Anchored = true
	base.Material = Enum.Material.Metal
	base.Color = Color3.fromRGB(25, 30, 40)
	base.TopSurface = Enum.SurfaceType.Smooth
	base.Parent = model

	local ring = Instance.new("Part")
	ring.Name = "NeonRing"
	ring.Size = Vector3.new(26, 0.4, 26)
	ring.Position = position + Vector3.new(0, 1.6, 0)
	ring.Anchored = true
	ring.CanCollide = false
	ring.Material = Enum.Material.Neon
	ring.Color = primaryColor
	ring.Parent = model

	local beacon = Instance.new("PointLight")
	beacon.Name = "PadBeacon"
	beacon.Color = primaryColor
	beacon.Brightness = 4
	beacon.Range = 35
	beacon.Shadows = true
	beacon.Parent = ring

	local pillar = Instance.new("Part")
	pillar.Name = "SupportPillar"
	local pillarHeight = math.max(position.Y, 2)
	pillar.Size = Vector3.new(12, pillarHeight, 12)
	pillar.Position = Vector3.new(position.X, position.Y / 2, position.Z)
	pillar.Anchored = true
	pillar.Material = Enum.Material.Concrete
	pillar.Color = Color3.fromRGB(15, 18, 25)
	pillar.Parent = model

	if hasRamp then
		local ramp = Instance.new("Part")
		ramp.Name = "AccessRamp"
		ramp.Size = Vector3.new(10, 0.6, 18)
		local rampAngle = math.rad(-14)
		ramp.CFrame = CFrame.new(position.X, position.Y * 0.5, position.Z + 21) * CFrame.Angles(rampAngle, 0, 0)
		ramp.Anchored = true
		ramp.Material = Enum.Material.Metal
		ramp.Color = Color3.fromRGB(20, 25, 35)
		ramp.Parent = model
	end

	model.PrimaryPart = base
	return model
end

local function setupHelipads()
	local folder = Workspace:FindFirstChild("LandingPads") :: Folder?
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "LandingPads"
		folder.Parent = Workspace

		local pad1 = createHelipad("Pad_HangarCentral", Vector3.new(0, 4, 0), Color3.fromRGB(0, 240, 255), true)
		pad1.Parent = folder

		local pad2 = createHelipad("Pad_TorreArasaka", Vector3.new(160, 95, -180), Color3.fromRGB(255, 30, 120), false)
		pad2.Parent = folder

		local pad3 = createHelipad("Pad_DistritoNeon", Vector3.new(-200, 50, 140), Color3.fromRGB(255, 200, 0), false)
		pad3.Parent = folder

		print("[Servidor] Red de Helipuertos y Rampa generados en Workspace.")
	end
end

setupHelipads()

----------------------------------------------------------------------
-- 2. GESTIÓN DE TESTDRONE Y RESTRICCIONES DE FÍSICA
----------------------------------------------------------------------
local dronePart = Workspace:FindFirstChild("TestDrone") :: BasePart?
if not dronePart then
	dronePart = Instance.new("Part")
	dronePart.Name = "TestDrone"
	dronePart.Size = Vector3.new(4.5, 1.2, 4.5)
	dronePart.Material = Enum.Material.Metal
	dronePart.Color = Color3.fromRGB(0, 240, 255)
	dronePart.CanCollide = true
	dronePart.Parent = Workspace
	print("[Servidor] 'TestDrone' creado en Workspace.")
end

dronePart.Anchored = true
dronePart.CFrame = CFrame.new(0, 6.2, 0)
dronePart.AssemblyLinearVelocity = Vector3.zero
dronePart.AssemblyAngularVelocity = Vector3.zero

-- Restricciones físicas en el servidor
local attachment = dronePart:FindFirstChild("FlightAttachment") :: Attachment?
if not attachment then
	attachment = Instance.new("Attachment")
	attachment.Name = "FlightAttachment"
	attachment.Position = Vector3.zero
	attachment.Parent = dronePart
end

local linearVelocity = dronePart:FindFirstChild("FlightVelocity") :: LinearVelocity?
if not linearVelocity then
	linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "FlightVelocity"
	linearVelocity.Attachment0 = attachment
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.MaxForce = 1e6
	linearVelocity.VectorVelocity = Vector3.zero
	linearVelocity.Enabled = true
	linearVelocity.Parent = dronePart
end

local alignOrientation = dronePart:FindFirstChild("FlightOrientation") :: AlignOrientation?
if not alignOrientation then
	alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "FlightOrientation"
	alignOrientation.Attachment0 = attachment
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Responsiveness = 25
	alignOrientation.MaxTorque = 1e6
	alignOrientation.CFrame = dronePart.CFrame
	alignOrientation.Enabled = true
	alignOrientation.Parent = dronePart
end

----------------------------------------------------------------------
-- 3. CONTROL DE ENLACE DE VUELO Y NETWORK OWNERSHIP
----------------------------------------------------------------------
flightStateEvent.OnServerEvent:Connect(function(player: Player, state: any)
	if not dronePart then return end

	if state == "StartFlying" then
		dronePart.Anchored = false
		local success, err = pcall(function()
			dronePart:SetNetworkOwner(player)
		end)
		if success then
			print(string.format("[Servidor] %s ha tomado el control físico total de TestDrone.", player.Name))
		else
			warn(string.format("[Servidor] Error al transferir propiedad física a %s: %s", player.Name, tostring(err)))
		end
	elseif state == "StopFlying" then
		dronePart.AssemblyLinearVelocity = Vector3.zero
		dronePart.AssemblyAngularVelocity = Vector3.zero
		dronePart.Anchored = true
		pcall(function()
			dronePart:SetNetworkOwnershipAuto()
		end)
		print(string.format("[Servidor] %s se ha desconectado. TestDrone anclado.", player.Name))
	end
end)

----------------------------------------------------------------------
-- 4. ECONOMÍA Y VALIDACIÓN SERVER-SIDE ANTI-EXPLOIT
----------------------------------------------------------------------
local lastDeliveryTime: { [number]: number } = {}
local MIN_DELIVERY_INTERVAL = 3.0  -- Cooldown mínimo entre entregas por jugador

Players.PlayerAdded:Connect(function(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local credits = Instance.new("IntValue")
	credits.Name = "CyberCréditos"
	credits.Value = 150
	credits.Parent = leaderstats

	local deliveries = Instance.new("IntValue")
	deliveries.Name = "Entregas"
	deliveries.Value = 0
	deliveries.Parent = leaderstats
end)

Players.PlayerRemoving:Connect(function(player)
	lastDeliveryTime[player.UserId] = nil
end)

-- Validación estricta en el servidor para otorgar recompensas
claimDeliveryEvent.OnServerEvent:Connect(function(player: Player, padName: any)
	if typeof(padName) ~= "string" then return end
	if not dronePart then return end

	local now = os.clock()
	local lastTime = lastDeliveryTime[player.UserId] or 0
	if (now - lastTime) < MIN_DELIVERY_INTERVAL then
		warn(string.format("[Servidor ANTI-EXPLOIT] %s intentó cobrar entrega demasiado rápido (cooldown violado).", player.Name))
		return
	end

	-- 1. Verificar existencia del helipuerto
	local padsFolder = Workspace:FindFirstChild("LandingPads") :: Folder?
	if not padsFolder then return end

	local padModel = padsFolder:FindFirstChild(padName) :: Model?
	if not padModel then
		warn(string.format("[Servidor ANTI-EXPLOIT] Helipuerto '%s' inexistente reclamado por %s.", padName, player.Name))
		return
	end

	local basePad = padModel:FindFirstChild("BasePad") :: BasePart?
	if not basePad then return end

	-- 2. Validar distancia física real entre TestDrone y el helipuerto
	local dronePos = dronePart.Position
	local padPos   = basePad.Position
	local horizDistance = Vector3.new(dronePos.X - padPos.X, 0, dronePos.Z - padPos.Z).Magnitude
	local vertDiff = dronePos.Y - padPos.Y

	if horizDistance > 18 then
		warn(string.format("[Servidor ANTI-EXPLOIT] %s reclamó entrega pero el dron está a %.1f studs del helipuerto (máx 18).", player.Name, horizDistance))
		return
	end

	if vertDiff < -2 or vertDiff > 10 then
		warn(string.format("[Servidor ANTI-EXPLOIT] %s reclamó entrega pero la altura del dron es inválida (diff: %.1f studs).", player.Name, vertDiff))
		return
	end

	-- 3. Validar velocidad segura de aterrizaje
	local droneSpeed = dronePart.AssemblyLinearVelocity.Magnitude
	if droneSpeed > 20 then
		warn(string.format("[Servidor ANTI-EXPLOIT] %s aterrizó a exceso de velocidad (%.1f studs/s, máx 20).", player.Name, droneSpeed))
		return
	end

	-- 4. Otorgar recompensas legítimas
	lastDeliveryTime[player.UserId] = now

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	local credits = leaderstats:FindFirstChild("CyberCréditos") :: IntValue?
	local deliveries = leaderstats:FindFirstChild("Entregas") :: IntValue?

	if credits and deliveries then
		local reward = 250
		credits.Value += reward
		deliveries.Value += 1
		print(string.format("[Servidor SEGURO] Entrega validada en %s para %s (+%d ₵)", padName, player.Name, reward))

		-- Confirmar al cliente para activar animaciones/HUD legítimas
		deliveryConfirmedEvent:FireClient(player, padName, reward)
	end
end)
