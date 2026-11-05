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
local deliveryRejectedEvent  = NetworkEvents.Get(NetworkEvents.Names.DeliveryRejected)

----------------------------------------------------------------------
-- 1. GENERADOR DE HELIPUERTOS Y RAMPA DE ACCESO
----------------------------------------------------------------------
local function createHelipad(name: string, position: Vector3, primaryColor: Color3, hasRamp: boolean): Model
	local model = Instance.new("Model")
	model.Name = name

	local isTower = position.Y > 15
	local padWidth = if isTower then 32 else 36

	-- 1. BASE DE ATERRIZAJE (BasePad)
	local base = Instance.new("Part")
	base.Name = "BasePad"
	base.Size = Vector3.new(padWidth, 3, padWidth)
	base.Position = position
	base.Anchored = true
	base.Material = Enum.Material.Metal
	base.Color = Color3.fromRGB(20, 24, 32)
	base.TopSurface = Enum.SurfaceType.Smooth
	base.Parent = model

	-- 2. ANILLO PERIMETRAL DE NEÓN
	local ring = Instance.new("Part")
	ring.Name = "NeonRing"
	ring.Size = Vector3.new(padWidth - 2, 0.5, padWidth - 2)
	ring.Position = position + Vector3.new(0, 1.6, 0)
	ring.Anchored = true
	ring.CanCollide = false
	ring.Material = Enum.Material.Neon
	ring.Color = primaryColor
	ring.Parent = model

	-- Marcador 'H' o cruz luminosa en la superficie
	local crossH = Instance.new("Part")
	crossH.Name = "LandingCrossH"
	crossH.Size = Vector3.new(12, 0.15, 3)
	crossH.Position = position + Vector3.new(0, 1.62, 0)
	crossH.Anchored = true
	crossH.CanCollide = false
	crossH.Material = Enum.Material.Neon
	crossH.Color = Color3.fromRGB(255, 255, 255)
	crossH.Parent = model

	local crossV = Instance.new("Part")
	crossV.Name = "LandingCrossV"
	crossV.Size = Vector3.new(3, 0.15, 12)
	crossV.Position = position + Vector3.new(0, 1.62, 0)
	crossV.Anchored = true
	crossV.CanCollide = false
	crossV.Material = Enum.Material.Neon
	crossV.Color = Color3.fromRGB(255, 255, 255)
	crossV.Parent = model

	-- 3. ILUMINACIÓN Y BALIZA DE HELIPUERTO
	local beacon = Instance.new("PointLight")
	beacon.Name = "PadBeacon"
	beacon.Color = primaryColor
	beacon.Brightness = 8
	beacon.Range = 60
	beacon.Shadows = false
	beacon.Parent = ring

	-- 4. EDIFICIO / RASCACIELOS / PILAR
	local pillarHeight = math.max(position.Y, 4)
	local towerWidth = if isTower then 30 else 38

	local pillar = Instance.new("Part")
	pillar.Name = "SupportPillar"
	pillar.Size = Vector3.new(towerWidth, pillarHeight, towerWidth)
	pillar.Position = Vector3.new(position.X, pillarHeight / 2, position.Z)
	pillar.Anchored = true
	pillar.Material = Enum.Material.Metal
	pillar.Color = Color3.fromRGB(15, 18, 26)
	pillar.Parent = model

	-- Si es una torre alta, agregar arquitectura cyberpunk visible desde lejos
	if isTower then
		local halfW = towerWidth / 2
		local cornerOffsets = {
			Vector3.new(-halfW, 0, -halfW),
			Vector3.new( halfW, 0, -halfW),
			Vector3.new(-halfW, 0,  halfW),
			Vector3.new( halfW, 0,  halfW),
		}

		-- Tiras de neón en las 4 esquinas del rascacielos
		for i, offset in ipairs(cornerOffsets) do
			local cornerStrip = Instance.new("Part")
			cornerStrip.Name = "NeonCorner_" .. tostring(i)
			cornerStrip.Size = Vector3.new(1.4, pillarHeight, 1.4)
			cornerStrip.Position = Vector3.new(position.X + offset.X, pillarHeight / 2, position.Z + offset.Z)
			cornerStrip.Material = Enum.Material.Neon
			cornerStrip.Color = primaryColor
			cornerStrip.Anchored = true
			cornerStrip.CanCollide = false
			cornerStrip.Parent = model
		end

		-- Bandas horizontales de ventanas iluminadas cada 20 studs
		local floorCount = math.floor(pillarHeight / 20)
		for f = 1, floorCount do
			local floorY = f * 20
			local band = Instance.new("Part")
			band.Name = "FloorBand_" .. tostring(f)
			band.Size = Vector3.new(towerWidth + 0.6, 1.8, towerWidth + 0.6)
			band.Position = Vector3.new(position.X, floorY, position.Z)
			band.Material = Enum.Material.Neon
			band.Color = primaryColor
			band.Transparency = 0.35
			band.Anchored = true
			band.CanCollide = false
			band.Parent = model
		end

		-- Antena de comunicaciones en la esquina del techo con baliza aérea
		local antenna = Instance.new("Part")
		antenna.Name = "CommAntenna"
		antenna.Size = Vector3.new(1.2, 35, 1.2)
		antenna.Position = position + Vector3.new(halfW - 2, 17.5, halfW - 2)
		antenna.Material = Enum.Material.Metal
		antenna.Color = Color3.fromRGB(40, 45, 55)
		antenna.Anchored = true
		antenna.CanCollide = false
		antenna.Parent = model

		local antennaLight = Instance.new("PointLight")
		antennaLight.Color = Color3.fromRGB(255, 0, 50)
		antennaLight.Brightness = 8
		antennaLight.Range = 40
		antennaLight.Parent = antenna

		-- Haz de luz vertical hacia la estratosfera (colocado en la antena, no en el centro)
		local skyBeam = Instance.new("Part")
		skyBeam.Name = "HoloSkyBeam"
		skyBeam.Size = Vector3.new(3.0, 300, 3.0)
		skyBeam.Position = position + Vector3.new(halfW - 2, 150, halfW - 2)
		skyBeam.Material = Enum.Material.Neon
		skyBeam.Color = primaryColor
		skyBeam.Transparency = 0.25
		skyBeam.CanCollide = false
		skyBeam.Anchored = true
		skyBeam.Parent = model
	end

	-- 5. LETRERO HOLOGRÁFICO 3D (visible hasta 1000 studs)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PadHoloSign"
	billboard.Size = UDim2.fromOffset(300, 65)
	billboard.StudsOffset = Vector3.new(0, 10, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 1000
	billboard.Parent = base

	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.fromScale(1, 1)
	signLabel.BackgroundTransparency = 1
	signLabel.Font = Enum.Font.Code
	signLabel.Text = string.format("◀ %s ▶\n[ZONA DE ATERRIZAJE]", name:gsub("Pad_", ""):gsub("(%u)", " %1"):gsub("^%s+", ""):upper())
	signLabel.TextColor3 = primaryColor
	signLabel.TextSize = 15
	signLabel.TextStrokeTransparency = 0.2
	signLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	signLabel.Parent = billboard

	-- 6. RAMPA DE ACCESO (si aplica)
	if hasRamp then
		local ramp = Instance.new("Part")
		ramp.Name = "AccessRamp"
		ramp.Size = Vector3.new(12, 0.6, 20)
		local rampAngle = math.rad(-14)
		ramp.CFrame = CFrame.new(position.X, position.Y * 0.5, position.Z + 24) * CFrame.Angles(rampAngle, 0, 0)
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
	if folder then
		folder:ClearAllChildren()
	else
		folder = Instance.new("Folder")
		folder.Name = "LandingPads"
		folder.Parent = Workspace
	end

	local pad1 = createHelipad("Pad_HangarCentral", Vector3.new(0, 4, 0), Color3.fromRGB(0, 240, 255), true)
	pad1.Parent = folder

	local pad2 = createHelipad("Pad_TorreArasaka", Vector3.new(160, 95, -180), Color3.fromRGB(255, 30, 120), false)
	pad2.Parent = folder

	local pad3 = createHelipad("Pad_DistritoNeon", Vector3.new(-200, 50, 140), Color3.fromRGB(255, 200, 0), false)
	pad3.Parent = folder

	print("[Servidor] Red de Helipuertos y Rascacielos Cyberpunk generados en Workspace.")
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

		-- Registrar dron del jugador en el servicio de combate
		if _G.CombatService and _G.CombatService.Register then
			_G.CombatService.Register(dronePart, 100, 100, 8, 0.0, 0.55, player)
		end
	elseif state == "StopFlying" then
		-- Desregistrar del servicio de combate
		if _G.CombatService and _G.CombatService.Unregister then
			_G.CombatService.Unregister(dronePart)
		end

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
		deliveryRejectedEvent:FireClient(player, "Espera 3 segundos entre entregas")
		return
	end

	-- 1. Verificar existencia del helipuerto
	local padsFolder = Workspace:FindFirstChild("LandingPads") :: Folder?
	if not padsFolder then return end

	local padModel = padsFolder:FindFirstChild(padName) :: Model?
	if not padModel then
		warn(string.format("[Servidor ANTI-EXPLOIT] Helipuerto '%s' inexistente reclamado por %s.", padName, player.Name))
		deliveryRejectedEvent:FireClient(player, "Helipuerto no registrado en la red")
		return
	end

	local basePad = padModel:FindFirstChild("BasePad") :: BasePart?
	if not basePad then return end

	-- 2. Validar distancia física real entre TestDrone y el helipuerto
	local dronePos = dronePart.Position
	local padPos   = basePad.Position
	local horizDistance = Vector3.new(dronePos.X - padPos.X, 0, dronePos.Z - padPos.Z).Magnitude
	local vertDiff = dronePos.Y - padPos.Y

	if horizDistance > 25 then
		warn(string.format("[Servidor ANTI-EXPLOIT] %s reclamó entrega pero el dron está a %.1f studs del helipuerto (máx 25).", player.Name, horizDistance))
		deliveryRejectedEvent:FireClient(player, string.format("Estás muy lejos del helipuerto (%.0f studs)", horizDistance))
		return
	end

	if vertDiff < -3 or vertDiff > 16 then
		warn(string.format("[Servidor ANTI-EXPLOIT] %s reclamó entrega pero la altura del dron es inválida (diff: %.1f studs, rango: -3 a +16).", player.Name, vertDiff))
		deliveryRejectedEvent:FireClient(player, "Altitud incorrecta respecto a la plataforma")
		return
	end

	-- 3. Validar velocidad segura de aterrizaje
	local droneSpeed = dronePart.AssemblyLinearVelocity.Magnitude
	if droneSpeed > 30 then
		warn(string.format("[Servidor ANTI-EXPLOIT] %s aterrizó a exceso de velocidad (%.1f studs/s, máx 30).", player.Name, droneSpeed))
		deliveryRejectedEvent:FireClient(player, string.format("Velocidad muy alta (%.0f studs/s, máx 30)", droneSpeed))
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
