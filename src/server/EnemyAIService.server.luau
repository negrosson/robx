--!strict
-- src/server/EnemyAIService.server.luau
-- Servicio de Inteligencia Artificial Enemiga — Steering Behaviors 3D a 10 Hz
-- SIN PathfindingService — conductas de dirección vectorial puras
print("[EnemyAIService] Iniciando IA de facciones hostiles...")

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")
local Debris            = game:GetService("Debris")

local EnemyTypes = require(ReplicatedStorage:WaitForChild("EnemyTypes", 8) :: ModuleScript)

----------------------------------------------------------------------
-- CONSTANTES
----------------------------------------------------------------------
local AI_TICK_RATE        = 0.1   -- 10 Hz
local RAMMING_COOLDOWN    = 1.5   -- s entre embestidas del mismo gnat
local TURRET_FIRE_RATE    = 1.2   -- s entre disparos Aegis
local ORBIT_ADJUSTMENT    = 0.08  -- factor de corrección de órbita (Lerp)
local SEPARATION_WEIGHT   = 1.5   -- peso de separación en flocking
local COHESION_WEIGHT     = 0.6   -- peso de cohesión en flocking
local ALIGNMENT_WEIGHT    = 0.4   -- peso de alineación en flocking
local MAX_GNATS_PER_SWARM = 6
local ENEMY_FOLDER        = "EnemyDrones"

----------------------------------------------------------------------
-- TIPOS
----------------------------------------------------------------------
type EnemyAgent = {
	spec          : any,          -- EnemyTypes.EnemySpec
	part          : BasePart,
	health        : number,
	velocity      : Vector3,      -- velocidad actual 3D del agente
	targetPlayer  : Player?,
	targetPart    : BasePart?,    -- dron objetivo del jugador
	lastFireTime  : number,
	lastRamTime   : number,
	orbitAngle    : number,       -- ángulo orbital actual (rad) para Kuroshio
	isAlive       : boolean,
	linearVelocity: LinearVelocity,
	alignOrient   : AlignOrientation,
}

local activeAgents: { [BasePart]: EnemyAgent } = {}
local agentFolder: Folder

----------------------------------------------------------------------
-- INICIALIZACIÓN DE CARPETA DE ENEMIGOS
----------------------------------------------------------------------
local function initFolder(): Folder
	local folder = Workspace:FindFirstChild(ENEMY_FOLDER) :: Folder?
	if not folder then
		folder = Instance.new("Folder")
		folder.Name   = ENEMY_FOLDER
		folder.Parent = Workspace
	end
	return folder :: Folder
end

agentFolder = initFolder()

----------------------------------------------------------------------
-- CONSTRUCCIÓN DE MODELO 3D DE ENEMIGO
----------------------------------------------------------------------
local function buildEnemyPart(spec: any, spawnCF: CFrame): BasePart
	local isTurret = (spec.aggressionMode == "turret")

	local part = Instance.new("Part")
	part.Name         = spec.id .. "_" .. tostring(math.random(1000, 9999))
	part.Size         = spec.scale * 4.5  -- escala relativa al TestDrone estándar (4.5)
	part.Material     = Enum.Material.Metal
	part.Color        = spec.primaryColor
	part.Anchored     = isTurret
	part.CanCollide   = true
	part.CFrame       = spawnCF
	part.Parent       = agentFolder

	-- Banda de acento neón
	local band = Instance.new("Part")
	band.Name       = "AccentBand"
	band.Size       = Vector3.new(part.Size.X * 0.95, 0.3, part.Size.Z * 0.95)
	band.Material   = Enum.Material.Neon
	band.Color      = spec.accentColor
	band.CanCollide = false
	band.Massless   = true
	band.CFrame     = part.CFrame
	band.Parent     = agentFolder  -- mismo nivel (se suelda a part)

	local weld = Instance.new("WeldConstraint")
	weld.Part0  = part
	weld.Part1  = band
	weld.Parent = part

	-- Attachment central
	local att = Instance.new("Attachment")
	att.Name   = "AIAtt"
	att.Parent = part

	-- LinearVelocity (solo para drones móviles, torreta es estacionaria)
	local lv = Instance.new("LinearVelocity")
	lv.Name           = "FlightVelocity"
	lv.Attachment0    = att
	lv.RelativeTo     = Enum.ActuatorRelativeTo.World
	lv.MaxForce       = if isTurret then 0 else (spec.maxForce * spec.mass)
	lv.VectorVelocity = Vector3.zero
	lv.Enabled        = not isTurret
	lv.Parent         = part

	-- AlignOrientation (giroscopio para unidades aéreas)
	local ao = Instance.new("AlignOrientation")
	ao.Name           = "FlightOrientation"
	ao.Attachment0    = att
	ao.Mode           = Enum.OrientationAlignmentMode.OneAttachment
	ao.Responsiveness = 20
	ao.MaxTorque      = if isTurret then 0 else 1e5
	ao.CFrame         = part.CFrame
	ao.Enabled        = not isTurret
	ao.Parent         = part

	-- Punto de luz del acento
	local pl = Instance.new("PointLight")
	pl.Color      = spec.accentColor
	pl.Brightness = 2.5
	pl.Range      = 16
	pl.Parent     = part

	-- Rótulo holográfico diegético de hostilidad
	local tagGui = Instance.new("BillboardGui")
	tagGui.Name        = "EnemyTag"
	tagGui.Size        = UDim2.fromOffset(140, 22)
	tagGui.StudsOffset = Vector3.new(0, part.Size.Y + 1.2, 0)
	tagGui.AlwaysOnTop = true
	tagGui.MaxDistance = 180
	tagGui.Parent      = part

	local tagText = Instance.new("TextLabel")
	tagText.Size                   = UDim2.fromScale(1, 1)
	tagText.BackgroundTransparency = 1
	tagText.Font                   = Enum.Font.Code
	tagText.Text                   = string.format("▼ %s ▼", spec.name:upper())
	tagText.TextColor3             = spec.accentColor
	tagText.TextSize               = 10
	tagText.TextStrokeTransparency = 0.3
	tagText.Parent                 = tagGui

	return part
end

----------------------------------------------------------------------
-- STEERING BEHAVIORS HELPER
----------------------------------------------------------------------

-- Seek: vector de dirección hacia un objetivo normalizado
local function seek(agentPos: Vector3, targetPos: Vector3, maxSpeed: number): Vector3
	local desired = (targetPos - agentPos)
	if desired.Magnitude < 0.01 then return Vector3.zero end
	return desired.Unit * maxSpeed
end

-- Flee: alejarse del objetivo
local function flee(agentPos: Vector3, threatPos: Vector3, maxSpeed: number): Vector3
	return -seek(agentPos, threatPos, maxSpeed)
end

-- Arrive: seek con desaceleración al acercarse (radio de frenado)
local function arrive(agentPos: Vector3, targetPos: Vector3, maxSpeed: number, slowRadius: number): Vector3
	local toTarget = targetPos - agentPos
	local dist = toTarget.Magnitude
	if dist < 0.1 then return Vector3.zero end
	local speed = if dist < slowRadius then (maxSpeed * dist / slowRadius) else maxSpeed
	return toTarget.Unit * speed
end

-- Tangente orbital: mantener órbita lateral alrededor de un punto
local function orbitTangent(agentPos: Vector3, targetPos: Vector3, orbitRadius: number, orbitAngle: number, maxSpeed: number): Vector3
	-- Punto ideal en la órbita
	local orbitPoint = targetPos + Vector3.new(
		math.cos(orbitAngle) * orbitRadius,
		10,  -- ligeramente elevado respecto al objetivo
		math.sin(orbitAngle) * orbitRadius
	)
	return arrive(agentPos, orbitPoint, maxSpeed, orbitRadius * 0.5)
end

-- Separación del flocking (evitar aglomeración entre gnats)
local function separation(agentPos: Vector3, neighbors: { BasePart }, minDist: number): Vector3
	local steer = Vector3.zero
	for _, n in ipairs(neighbors) do
		if n and n.Parent then
			local diff = agentPos - n.Position
			local dist = diff.Magnitude
			if dist > 0 and dist < minDist then
				steer += diff.Unit * (minDist - dist)
			end
		end
	end
	return steer
end

-- Busca el dron del jugador activo más cercano
local function findNearestPlayerDrone(agentPos: Vector3): (Player?, BasePart?)
	local bestDist = math.huge
	local bestPlayer: Player? = nil
	local bestPart: BasePart? = nil

	for _, player in ipairs(Players:GetPlayers()) do
		local dronePart = Workspace:FindFirstChild("TestDrone") :: BasePart?
		if dronePart then
			local d = (dronePart.Position - agentPos).Magnitude
			if d < bestDist then
				bestDist   = d
				bestPlayer = player
				bestPart   = dronePart
			end
		end
	end

	return bestPlayer, bestPart
end

----------------------------------------------------------------------
-- SPAWN DE AGENTE ENEMIGO
----------------------------------------------------------------------
function EnemyAIService_Spawn(specId: string, spawnPosition: Vector3, difficulty: number?, zoneId: string?): BasePart?
	local baseSpec = EnemyTypes.ById[specId]
	if not baseSpec then
		warn("[EnemyAIService] Spec no encontrado:", specId)
		return nil
	end

	local spec = EnemyTypes.Scale(baseSpec, difficulty or 0)
	local spawnCF = CFrame.new(spawnPosition)
	local part = buildEnemyPart(spec, spawnCF)

	local lv = part:FindFirstChild("FlightVelocity") :: LinearVelocity
	local ao = part:FindFirstChild("FlightOrientation") :: AlignOrientation

	local agent: EnemyAgent = {
		spec          = spec,
		part          = part,
		health        = spec.maxHealth,
		velocity      = Vector3.zero,
		targetPlayer  = nil,
		targetPart    = nil,
		lastFireTime  = 0,
		lastRamTime   = 0,
		orbitAngle    = math.random() * math.pi * 2,
		isAlive       = true,
		linearVelocity = lv,
		alignOrient    = ao,
	}

	activeAgents[part] = agent

	-- Registrar en el sistema de combate de servidor
	if _G.CombatService and _G.CombatService.Register then
		_G.CombatService.Register(
			part,
			spec.maxHealth,
			100,  -- maxHeat
			10,   -- heatCooling
			spec.armorReduction,
			0.2,  -- empResistance
			nil   -- owner (NPC)
		)
	end

	print(string.format("[EnemyAIService] Spawned %s en %s (Zona: %s)", spec.name, tostring(spawnPosition), zoneId or "Manual"))
	return part
end

----------------------------------------------------------------------
-- LÓGICA DE IA — Daño por embestida (Scav-Gnats)
----------------------------------------------------------------------
local function handleRamming(agent: EnemyAgent)
	if not agent.targetPart then return end
	local now = os.clock()
	if now - agent.lastRamTime < RAMMING_COOLDOWN then return end

	local dist = (agent.part.Position - agent.targetPart.Position).Magnitude
	if dist > 6 then return end  -- solo embestir en contacto cercano

	agent.lastRamTime = now

	-- Aplicar impulso físico al dron del jugador (desestabilización aerodinámica)
	local impactDir = (agent.targetPart.Position - agent.part.Position).Unit
	agent.targetPart.AssemblyLinearVelocity += impactDir * agent.spec.rammingImpulse

	-- Partículas de chispas en el dron embestido
	local sparkPart = Instance.new("Part")
	sparkPart.Size = Vector3.new(1, 1, 1)
	sparkPart.Position = (agent.part.Position + agent.targetPart.Position) / 2
	sparkPart.Transparency = 1
	sparkPart.Anchored = true
	sparkPart.CanCollide = false
	sparkPart.Parent = Workspace

	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 100, 30))
	pe.Size = NumberSequence.new(0.5, 0)
	pe.Lifetime = NumberRange.new(0.2, 0.35)
	pe.Rate = 120
	pe.Speed = NumberRange.new(15, 25)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Parent = sparkPart
	task.delay(0.15, function()
		if pe and pe.Parent then pe.Enabled = false end
	end)
	Debris:AddItem(sparkPart, 0.6)

	-- Registrar daño en CombatService
	if _G.CombatService and _G.CombatService.ApplyDamage then
		_G.CombatService.ApplyDamage(agent.targetPart, 14)
	end

	print(string.format("[EnemyAIService] %s embistió al jugador (%.0f N | -14 HP)", agent.spec.name, agent.spec.rammingImpulse))
end

----------------------------------------------------------------------
-- LÓGICA DE IA — Disparo de torreta/interceptor con Proyectiles Visibles
----------------------------------------------------------------------
local function handleFiring(agent: EnemyAgent)
	if agent.spec.burstWeapon == "" or not agent.targetPart then return end
	local now = os.clock()
	if now - agent.lastFireTime < TURRET_FIRE_RATE then return end

	local dist = (agent.part.Position - agent.targetPart.Position).Magnitude
	if dist > agent.spec.fireRange then return end

	agent.lastFireTime = now

	-- Verificar línea de visión básica
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { agent.part, agentFolder }

	local direction = agent.targetPart.Position - agent.part.Position
	local result = Workspace:Raycast(agent.part.Position, direction, params)

	local hasLOS = not result or result.Instance == agent.targetPart
	if not hasLOS then return end

	-- Delegar daño al CombatService y renderizar proyectil visual
	if agent.spec.burstWeapon == "synapse_overheat" then
		-- Kuroshio: Haz de microondas violeta continuo/pulsado
		local pulse = Instance.new("Part")
		pulse.Name = "MicrowavePulse"
		pulse.Size = Vector3.new(0.4, 0.4, dist)
		pulse.CFrame = CFrame.lookAt(agent.part.Position, agent.targetPart.Position) * CFrame.new(0, 0, -dist / 2)
		pulse.Anchored = true
		pulse.CanCollide = false
		pulse.Material = Enum.Material.Neon
		pulse.Color = Color3.fromRGB(180, 0, 255)
		pulse.Transparency = 0.3
		pulse.Parent = Workspace
		Debris:AddItem(pulse, 0.22)

		if _G.CombatService and _G.CombatService.ApplyHeat then
			_G.CombatService.ApplyHeat(agent.targetPart, 14)
		end
		print(string.format("[EnemyAIService] %s inyectó microondas térmicas (+14 calor)", agent.spec.name))

	elseif agent.spec.burstWeapon == "rail_driver" then
		-- Aegis: Trazador cinético Gauss dorado de alta velocidad
		local tracer = Instance.new("Part")
		tracer.Name = "GaussTracer"
		tracer.Size = Vector3.new(0.6, 0.6, dist)
		tracer.CFrame = CFrame.lookAt(agent.part.Position, agent.targetPart.Position) * CFrame.new(0, 0, -dist / 2)
		tracer.Anchored = true
		tracer.CanCollide = false
		tracer.Material = Enum.Material.Neon
		tracer.Color = Color3.fromRGB(255, 180, 0)
		tracer.Transparency = 0.15
		tracer.Parent = Workspace
		Debris:AddItem(tracer, 0.15)

		if _G.CombatService and _G.CombatService.ApplyDamage then
			_G.CombatService.ApplyDamage(agent.targetPart, 22)
		end
		print(string.format("[EnemyAIService] %s disparó Rail-Driver Gauss (-22 HP)", agent.spec.name))
	end
end

----------------------------------------------------------------------
-- BUCLE DE SIMULACIÓN — Steering Behaviors a 10 Hz (Heartbeat acumulado)
----------------------------------------------------------------------
local aiAccumulator = 0

RunService.Heartbeat:Connect(function(dt: number)
	aiAccumulator += dt
	if aiAccumulator < AI_TICK_RATE then return end
	aiAccumulator = 0

	-- Recolectar vecinos para flocking de gnats
	local gnatParts: { BasePart } = {}
	for part, agent in pairs(activeAgents) do
		if agent.spec.aggressionMode == "ramming" then
			table.insert(gnatParts, part)
		end
	end

	for part, agent in pairs(activeAgents) do
		-- Verificar existencia
		if not part or not part.Parent or not agent.isAlive then
			activeAgents[part] = nil
			continue
		end

		-- Detectar jugador más cercano en rango
		local targetPlayer, targetPart = findNearestPlayerDrone(part.Position)
		local inRange = false

		if targetPart then
			local dist = (part.Position - targetPart.Position).Magnitude
			local angleOk = true

			-- Verificar cono de detección para torretas
			if agent.spec.detectionAngle < 360 then
				local toTarget = (targetPart.Position - part.Position).Unit
				local facing   = part.CFrame.LookVector
				local dot      = facing:Dot(toTarget)
				local halfCone = math.rad(agent.spec.detectionAngle / 2)
				angleOk = (math.acos(math.clamp(dot, -1, 1)) <= halfCone)
			end

			inRange = (dist <= agent.spec.detectionRadius) and angleOk
		end

		if inRange then
			agent.targetPlayer = targetPlayer
			agent.targetPart   = targetPart
		else
			agent.targetPlayer = nil
			agent.targetPart   = nil
		end

		-- ---- CALCULAR STEERING POR MODO ----
		local steerForce = Vector3.zero
		local mode = agent.spec.aggressionMode

		if mode == "ramming" and agent.targetPart then
			-- Seek hacia el dron + separación del enjambre (flocking)
			local seekV = seek(part.Position, agent.targetPart.Position, agent.spec.maxSpeed)
			local sepV  = separation(part.Position, gnatParts, 8) * SEPARATION_WEIGHT
			steerForce  = seekV + sepV
			handleRamming(agent)

		elseif mode == "turret" then
			-- Estacionaria: rota CFrame hacia el objetivo suavemente
			if agent.targetPart then
				local toTarget = (agent.targetPart.Position - part.Position)
				if toTarget.Magnitude > 0 then
					local targetCF = CFrame.lookAt(part.Position, agent.targetPart.Position)
					part.CFrame = part.CFrame:Lerp(targetCF, 0.20)
				end
				handleFiring(agent)
			end
			-- No aplica fuerza de movimiento (estacionaria)
			steerForce = Vector3.zero

		elseif mode == "orbit" and agent.targetPart then
			-- Órbita lateral tangencial
			agent.orbitAngle += AI_TICK_RATE * 0.6  -- avanza en órbita
			steerForce = orbitTangent(
				part.Position,
				agent.targetPart.Position,
				agent.spec.orbitRadius,
				agent.orbitAngle,
				agent.spec.maxSpeed
			)
			handleFiring(agent)
		end

		-- ---- APLICAR VELOCIDAD VÍA LinearVelocity ----
		if mode ~= "turret" then
			-- Integrar steering hacia velocidad actual con inercia
			agent.velocity = agent.velocity:Lerp(steerForce, math.clamp(AI_TICK_RATE * 3, 0, 1))

			-- Limitar a velocidad máxima
			if agent.velocity.Magnitude > agent.spec.maxSpeed then
				agent.velocity = agent.velocity.Unit * agent.spec.maxSpeed
			end

			agent.linearVelocity.VectorVelocity = agent.velocity

			-- Orientar hacia la dirección de movimiento (si se mueve)
			if agent.velocity.Magnitude > 2 then
				local flatVel = Vector3.new(agent.velocity.X, 0, agent.velocity.Z)
				if flatVel.Magnitude > 0.01 then
					agent.alignOrient.CFrame = CFrame.lookAt(Vector3.zero, flatVel.Unit, Vector3.yAxis)
				end
			end
		end
	end
end)

----------------------------------------------------------------------
-- DIRECTOR DE AMENAZA Y PARTICIONADO ESPACIAL (Fase 2)
----------------------------------------------------------------------
type ThreatArchetype = {
	specId: string,
	offset: Vector3,
	difficulty: number,
}

type ThreatZone = {
	id: string,
	name: string,
	threatLevel: string,
	center: Vector3,
	activationRadius: number,
	deactivationRadius: number,
	respawnCooldown: number,
	lastClearedTime: number,
	archetypes: { ThreatArchetype },
	activeParts: { BasePart },
	isActive: boolean,
}

local threatZones: { [string]: ThreatZone } = {
	Zone_TorreA = {
		id = "Zone_TorreA",
		name = "Sector Industrial (Torre A)",
		threatLevel = "hostile",
		center = Vector3.new(160, 95, -180),
		activationRadius = 220,
		deactivationRadius = 320,
		respawnCooldown = 35,
		lastClearedTime = 0,
		archetypes = {
			{ specId = "scav_gnats", offset = Vector3.new(-25, -20, 25), difficulty = 0.1 },
			{ specId = "scav_gnats", offset = Vector3.new(25, -10, -20),  difficulty = 0.15 },
			{ specId = "scav_gnats", offset = Vector3.new(0, -30, 30),    difficulty = 0.2 },
		},
		activeParts = {},
		isActive = false,
	},
	Zone_TorreB = {
		id = "Zone_TorreB",
		name = "Sector Black Ops (Torre B)",
		threatLevel = "black_ops",
		center = Vector3.new(-200, 50, 140),
		activationRadius = 250,
		deactivationRadius = 350,
		respawnCooldown = 45,
		lastClearedTime = 0,
		archetypes = {
			-- Torreta Aegis montada en cornisa elevada cercana a la torre
			{ specId = "aegis_44",  offset = Vector3.new(20, 22, -20), difficulty = 0.25 },
			-- Interceptor orbital Kuroshio patrullando a gran altitud
			{ specId = "kuroshio_v", offset = Vector3.new(-10, 45, 10), difficulty = 0.35 },
		},
		activeParts = {},
		isActive = false,
	},
}

local function activateZone(zone: ThreatZone)
	if zone.isActive then return end
	local now = os.clock()
	if (now - zone.lastClearedTime) < zone.respawnCooldown then
		return
	end

	zone.isActive = true
	table.clear(zone.activeParts)

	for _, arch in ipairs(zone.archetypes) do
		local spawnPos = zone.center + arch.offset
		local part = EnemyAIService_Spawn(arch.specId, spawnPos, arch.difficulty, zone.id)
		if part then
			table.insert(zone.activeParts, part)
		end
	end

	print(string.format("[ThreatDirector] ¡Zona '%s' ACTIVADA! %d unidades hostiles en vuelo.", zone.name, #zone.activeParts))
end

local function deactivateZone(zone: ThreatZone)
	if not zone.isActive then return end
	zone.isActive = false

	for _, part in ipairs(zone.activeParts) do
		if part and part.Parent then
			activeAgents[part] = nil
			if _G.CombatService and _G.CombatService.Unregister then
				_G.CombatService.Unregister(part)
			end
			-- Desvanecer suavemente y destruir
			task.spawn(function()
				for i = 0, 1, 0.25 do
					if part and part.Parent then
						part.Transparency = i
					end
					task.wait(0.05)
				end
				if part and part.Parent then
					part:Destroy()
				end
			end)
		end
	end

	table.clear(zone.activeParts)
	print(string.format("[ThreatDirector] Zona '%s' replegada por distancia. Recursos liberados.", zone.name))
end

-- Bucle de Director de Amenazas (1 Hz para máximo rendimiento de servidor)
task.spawn(function()
	while true do
		task.wait(1.0)

		local dronePart = Workspace:FindFirstChild("TestDrone") :: BasePart?
		if not dronePart then continue end

		local isFlying = (not dronePart.Anchored)
		local dronePos = dronePart.Position
		local distToBase = (dronePos - Vector3.new(0, 4, 0)).Magnitude

		-- 1. Si no está volando o está en la Base Central (< 90 studs), Zona Segura Absoluta
		if not isFlying or distToBase < 90 then
			for _, zone in pairs(threatZones) do
				if zone.isActive then
					deactivateZone(zone)
				end
			end
			continue
		end

		-- 2. Evaluar cada zona según proximidad del repartidor
		for _, zone in pairs(threatZones) do
			local dist = (dronePos - zone.center).Magnitude

			if dist <= zone.activationRadius then
				if not zone.isActive then
					activateZone(zone)
				end
			elseif dist >= zone.deactivationRadius then
				if zone.isActive then
					deactivateZone(zone)
				end
			end

			-- 3. Comprobar si todos los enemigos de la zona activa fueron neutralizados en combate
			if zone.isActive and #zone.activeParts > 0 then
				local aliveCount = 0
				for _, part in ipairs(zone.activeParts) do
					if part and part.Parent and activeAgents[part] and activeAgents[part].isAlive then
						aliveCount += 1
					end
				end

				if aliveCount == 0 then
					zone.isActive = false
					zone.lastClearedTime = os.clock()
					table.clear(zone.activeParts)
					print(string.format("[ThreatDirector] ¡SECTOR '%s' DESPEJADO! Cooldown táctico de %ds activado.", zone.name, zone.respawnCooldown))
				end
			end
		end
	end
end)

-- Exponer API global para uso desde Main.server.luau
_G.EnemyAIService = {
	Spawn = EnemyAIService_Spawn,
	GetActiveCount = function(): number
		local count = 0
		for _ in pairs(activeAgents) do count += 1 end
		return count
	end,
	GetZones = function()
		return threatZones
	end,
	DeactivateAllZones = function()
		for _, zone in pairs(threatZones) do
			deactivateZone(zone)
		end
	end,
	ActivateZone = function(zoneId: string)
		local zone = threatZones[zoneId]
		if zone then activateZone(zone) end
	end,
}

print("[EnemyAIService] Servicio de IA y Director de Amenaza activo a 10 Hz / 1 Hz.")

