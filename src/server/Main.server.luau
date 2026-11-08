--!strict
-- src/server/Main.server.luau
-- Servidor Principal v4.1: Red de Helipuertos, Control Físico, Red Centralizada y Seguridad Anti-Exploits
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")

local NetworkEvents = require(ReplicatedStorage:WaitForChild("NetworkEvents", 5) :: ModuleScript)
NetworkEvents.Init()

local flightStateEvent       = NetworkEvents.Get(NetworkEvents.Names.DroneFlightState)
local claimDeliveryEvent     = NetworkEvents.Get(NetworkEvents.Names.ClaimDelivery)
local deliveryConfirmedEvent = NetworkEvents.Get(NetworkEvents.Names.DeliveryConfirmed)
local deliveryRejectedEvent  = NetworkEvents.Get(NetworkEvents.Names.DeliveryRejected)
local buyMissilesEvent       = NetworkEvents.Get(NetworkEvents.Names.BuyMissiles)
local buyMissilesConfirmedEv = NetworkEvents.Get(NetworkEvents.Names.BuyMissilesConfirmed)

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

		-- Tolva / Receptáculo de Entrega en el Helipuerto
		local dropBay = Instance.new("Part")
		dropBay.Name = "CargoDropBay"
		dropBay.Size = Vector3.new(8, 0.3, 8)
		dropBay.Position = position + Vector3.new(-halfW + 6, 1.65, -halfW + 6)
		dropBay.Material = Enum.Material.Neon
		dropBay.Color = Color3.fromRGB(0, 255, 180)
		dropBay.Transparency = 0.35
		dropBay.CanCollide = false
		dropBay.Anchored = true
		dropBay.Parent = model

		local baySign = Instance.new("BillboardGui")
		baySign.Name = "DropBaySign"
		baySign.Size = UDim2.fromOffset(180, 26)
		baySign.StudsOffset = Vector3.new(0, 1.8, 0)
		baySign.AlwaysOnTop = true
		baySign.MaxDistance = 120
		baySign.Parent = dropBay

		local bayText = Instance.new("TextLabel")
		bayText.Size = UDim2.fromScale(1, 1)
		bayText.BackgroundTransparency = 1
		bayText.Font = Enum.Font.Code
		bayText.Text = "▼ TOLVA DE DESCARGA ▼"
		bayText.TextColor3 = Color3.fromRGB(0, 255, 180)
		bayText.TextSize = 11
		bayText.TextStrokeTransparency = 0.3
		bayText.Parent = baySign
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
	local signText = "BASE"
	local threatSubtext = "[ZONA VERDE // REABASTECIMIENTO]"
	if name == "Pad_TorreA" then
		signText = "TORRE A"
		threatSubtext = "[AMENAZA: HOSTIL 🟡 // +250 ₵]"
	elseif name == "Pad_TorreB" then
		signText = "TORRE B"
		threatSubtext = "[AMENAZA: BLACK OPS 🔴 // +400 ₵]"
	elseif name == "Pad_Base" then
		signText = "BASE CENTRAL"
		threatSubtext = "[ZONA VERDE // REABASTECIMIENTO]"
	else
		signText = name:gsub("Pad_", ""):upper()
		threatSubtext = "[CORREDOR DE ENTREGA]"
	end
	signLabel.Text = string.format("◀ %s ▶\n%s", signText, threatSubtext)
	signLabel.TextColor3 = primaryColor
	signLabel.TextSize = 16
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

	local pad1 = createHelipad("Pad_Base", Vector3.new(0, 4, 0), Color3.fromRGB(0, 240, 255), true)
	pad1.Parent = folder

	local pad2 = createHelipad("Pad_TorreA", Vector3.new(160, 95, -180), Color3.fromRGB(255, 30, 120), false)
	pad2.Parent = folder

	local pad3 = createHelipad("Pad_TorreB", Vector3.new(-200, 50, 140), Color3.fromRGB(255, 200, 0), false)
	pad3.Parent = folder

	print("[Servidor] Red de Helipuertos (Base, Torre A, Torre B) generados en Workspace.")
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

-- ProximityPrompt diegético para interactuar con [E] de forma natural en el mundo 3D
local pilotPrompt = dronePart:FindFirstChild("PilotPrompt") :: ProximityPrompt?
if not pilotPrompt then
	pilotPrompt = Instance.new("ProximityPrompt")
	pilotPrompt.Name = "PilotPrompt"
	pilotPrompt.ActionText = "Pilotar Dron"
	pilotPrompt.ObjectText = "Cyber Drone FPV"
	pilotPrompt.KeyboardKeyCode = Enum.KeyCode.E
	pilotPrompt.HoldDuration = 0
	pilotPrompt.MaxActivationDistance = 28
	pilotPrompt.RequiresLineOfSight = false
	pilotPrompt.Parent = dronePart
end

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
		if pilotPrompt then pilotPrompt.Enabled = false end
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
		-- Desregistrar dron del jugador del servicio de combate
		if _G.CombatService and _G.CombatService.Unregister then
			_G.CombatService.Unregister(dronePart)
		end

		dronePart.AssemblyLinearVelocity = Vector3.zero
		dronePart.AssemblyAngularVelocity = Vector3.zero
		dronePart.Anchored = true
		if pilotPrompt then pilotPrompt.Enabled = true end
		pcall(function()
			dronePart:SetNetworkOwnershipAuto()
		end)
		print(string.format("[Servidor] %s se ha desconectado. TestDrone anclado.", player.Name))
	end
end)

----------------------------------------------------------------------
-- 4. ECONOMÍA Y VALIDACIÓN SERVER-SIDE ANTI-EXPLOIT (Fase 1: Amenazas & Rachas)
----------------------------------------------------------------------
local lastDeliveryTime: { [number]: number } = {}
local playerStreaks: { [number]: number } = {}
local CURRENCY_NAME = "PELAOCOINS"  -- Moneda del juego
local MIN_DELIVERY_INTERVAL = 2.0  -- Cooldown mínimo entre entregas por jugador

-- Rangos de piloto según entregas totales (Fase 5)
local function getPilotRank(totalDeliveries: number): string
	if totalDeliveries >= 16 then
		return "As del Reparto"
	elseif totalDeliveries >= 6 then
		return "Piloto de Corredor"
	else
		return "Cadete Aéreo"
	end
end

Players.PlayerAdded:Connect(function(player)
	playerStreaks[player.UserId] = 0

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local credits = Instance.new("IntValue")
	credits.Name = CURRENCY_NAME
	credits.Value = 150
	credits.Parent = leaderstats

	local deliveries = Instance.new("IntValue")
	deliveries.Name = "Entregas"
	deliveries.Value = 0
	deliveries.Parent = leaderstats

	local rank = Instance.new("StringValue")
	rank.Name = "Rango"
	rank.Value = getPilotRank(0)
	rank.Parent = leaderstats

	player.CharacterAdded:Connect(function(char)
		local hum = char:WaitForChild("Humanoid", 5) :: Humanoid?
		if hum then
			hum.Died:Connect(function()
				playerStreaks[player.UserId] = 0
				print(string.format("[Servidor] Personaje de %s murió: racha reiniciada a 0.", player.Name))
			end)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	lastDeliveryTime[player.UserId] = nil
	playerStreaks[player.UserId] = nil
end)

-- Validación estricta en el servidor para otorgar recompensas
claimDeliveryEvent.OnServerEvent:Connect(function(player: Player, padName: any, isRush: any)
	if typeof(padName) ~= "string" then return end
	if not dronePart then return end

	local now = os.clock()
	local lastTime = lastDeliveryTime[player.UserId] or 0
	if (now - lastTime) < MIN_DELIVERY_INTERVAL then
		warn(string.format("[Servidor ANTI-EXPLOIT] %s intentó cobrar entrega demasiado rápido (cooldown violado).", player.Name))
		deliveryRejectedEvent:FireClient(player, "Espera 2 segundos entre entregas")
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

	if horizDistance > 30 then
		warn(string.format("[Servidor ANTI-EXPLOIT] %s reclamó entrega pero el dron está a %.1f studs del helipuerto (máx 30).", player.Name, horizDistance))
		deliveryRejectedEvent:FireClient(player, string.format("Estás muy lejos del helipuerto (%.0f studs)", horizDistance))
		return
	end

	if vertDiff < -4 or vertDiff > 25 then
		warn(string.format("[Servidor ANTI-EXPLOIT] %s reclamó entrega pero la altura del dron es inválida (diff: %.1f studs, rango: -4 a +25).", player.Name, vertDiff))
		deliveryRejectedEvent:FireClient(player, "Altitud incorrecta respecto a la plataforma")
		return
	end

	-- 3. Validar velocidad segura de aterrizaje
	local droneSpeed = dronePart.AssemblyLinearVelocity.Magnitude
	if droneSpeed > 40 then
		warn(string.format("[Servidor ANTI-EXPLOIT] %s aterrizó a exceso de velocidad (%.1f studs/s, máx 40).", player.Name, droneSpeed))
		deliveryRejectedEvent:FireClient(player, string.format("Velocidad muy alta (%.0f studs/s, máx 40)", droneSpeed))
		return
	end

	-- 4. Otorgar recompensas legítimas
	lastDeliveryTime[player.UserId] = now

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	-- Buscar el stat de créditos de forma robusta por nombre o por tipo
	local credits: IntValue? = (leaderstats:FindFirstChild(CURRENCY_NAME) or leaderstats:FindFirstChild("PIGICOINS") or leaderstats:FindFirstChild("CyberCréditos")) :: IntValue?
	if not credits then
		for _, stat in ipairs(leaderstats:GetChildren()) do
			if stat:IsA("IntValue") and stat.Name ~= "Entregas" then
				credits = stat
				break
			end
		end
	end

	local deliveries = leaderstats:FindFirstChild("Entregas") :: IntValue?

	if credits and deliveries then
		local isBase = (padName == "Pad_Base" or padName == "Base")
		local baseReward = 250
		local threatColor = Color3.fromRGB(0, 240, 255)

		if isBase then
			baseReward = 100
			threatColor = Color3.fromRGB(0, 240, 255)
		elseif padName == "Pad_TorreB" then
			baseReward = 400
			threatColor = Color3.fromRGB(255, 30, 80)
		elseif padName == "Pad_TorreA" then
			baseReward = 250
			threatColor = Color3.fromRGB(255, 180, 0)
		end

		local currentStreak = playerStreaks[player.UserId] or 0
		local streakMultiplier = 1.0
		local rankVal = leaderstats:FindFirstChild("Rango") :: StringValue?

		if not isBase then
			currentStreak += 1
			playerStreaks[player.UserId] = currentStreak
			deliveries.Value += 1

			if rankVal then
				rankVal.Value = getPilotRank(deliveries.Value)
			end

			-- Bono de racha: +10% por entrega adicional hasta +50% máximo
			streakMultiplier = 1.0 + math.clamp((currentStreak - 1) * 0.10, 0, 0.50)
		end

		local rushMultiplier = if (isRush == true and not isBase) then 1.5 else 1.0
		local finalReward = math.round(baseReward * streakMultiplier * rushMultiplier)
		credits.Value += finalReward

		print(string.format("[Servidor SEGURO] Operación en %s para %s (+%d %s | Racha: x%d | Rush:%s | Rango: %s)",
			padName, player.Name, finalReward, credits.Name, currentStreak, tostring(isRush == true), rankVal and rankVal.Value or "N/A"))

		-- Pulso de escaneo y verificación holográfica en la torre receptora
		if not isBase and basePad then
			local scanRing = Instance.new("Part")
			scanRing.Name = "ScanReceiptPulse"
			scanRing.Size = Vector3.new(24, 0.4, 24)
			scanRing.Position = basePad.Position + Vector3.new(0, 1.8, 0)
			scanRing.Material = Enum.Material.Neon
			scanRing.Color = threatColor
			scanRing.Transparency = 0.25
			scanRing.CanCollide = false
			scanRing.Anchored = true
			scanRing.Parent = Workspace

			local tw = TweenService:Create(
				scanRing,
				TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = Vector3.new(34, 0.2, 34), Transparency = 1 }
			)
			tw:Play()
			game:GetService("Debris"):AddItem(scanRing, 1.3)
		end

		-- Confirmar al cliente para activar animaciones/HUD legítimas
		deliveryConfirmedEvent:FireClient(player, padName, finalReward, currentStreak, streakMultiplier)
	else
		warn(string.format("[Servidor] Error al premiar a %s: credits o deliveries no encontrados en leaderstats", player.Name))
	end
end)

----------------------------------------------------------------------
-- 5. REABASTECIMIENTO DE MISILES CON PELAOCOINS
----------------------------------------------------------------------
local MISSILE_PACK_COST = 150
buyMissilesEvent.OnServerEvent:Connect(function(player: Player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	local coins: IntValue? = (leaderstats:FindFirstChild(CURRENCY_NAME) or leaderstats:FindFirstChild("PIGICOINS") or leaderstats:FindFirstChild("CyberCréditos")) :: IntValue?
	if not coins then
		for _, stat in ipairs(leaderstats:GetChildren()) do
			if stat:IsA("IntValue") and stat.Name ~= "Entregas" then
				coins = stat
				break
			end
		end
	end

	if not coins then return end

	if coins.Value < MISSILE_PACK_COST then
		deliveryRejectedEvent:FireClient(player, string.format("Créditos insuficientes: necesitas %d PELAOCOINS (tienes %d)", MISSILE_PACK_COST, coins.Value))
		return
	end

	-- Verificar que el jugador/dron esté dentro del perímetro de Base Central (55 studs)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local inBase = false
	if dronePart and (dronePart.Position - Vector3.new(0, 4, 0)).Magnitude <= 55 then
		inBase = true
	elseif hrp and (hrp.Position - Vector3.new(0, 4, 0)).Magnitude <= 55 then
		inBase = true
	end

	if not inBase then
		deliveryRejectedEvent:FireClient(player, "Debes estar en Base Central para recargar misiles")
		return
	end

	coins.Value -= MISSILE_PACK_COST
	buyMissilesConfirmedEv:FireClient(player, 3)
	print(string.format("[Servidor] %s adquirió 3 misiles guiados (-%d %s | Restan: %d)", player.Name, MISSILE_PACK_COST, coins.Name, coins.Value))
end)
