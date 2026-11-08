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

local EnemyTypesModule = (ReplicatedStorage:FindFirstChild("EnemyTypes") or ReplicatedStorage:WaitForChild("EnemyTypes", 30)) :: ModuleScript
local EnemyTypes = require(EnemyTypesModule)

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
	homeCenter    : Vector3?,     -- punto de patrulla en reposo
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
	part.Anchored     = true              -- Mantener anclado temporalmente durante ensamblaje
	part.CanCollide   = false             -- Evita atascos de colisión física con edificios o drones
	part.CustomPhysicalProperties = PhysicalProperties.new(0.01, 0, 0, 0, 0) -- Densidad ultra-ligera
	part.CFrame       = spawnCF
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	part.Parent       = agentFolder

	-- Banda de acento neón (embebida directamente como hija para no duplicar blips en el radar)
	local band = Instance.new("Part")
	band.Name       = "AccentBand"
	band.Size       = Vector3.new(part.Size.X * 0.95, 0.35, part.Size.Z * 0.95)
	band.Material   = Enum.Material.Neon
	band.Color      = spec.accentColor
	band.CanCollide = false
	band.Massless   = true
	band.CFrame     = part.CFrame
	band.Parent     = part

	local weld = Instance.new("WeldConstraint")
	weld.Part0  = part
	weld.Part1  = band
	weld.Parent = part

	-- Attachment central
	local att = Instance.new("Attachment")
	att.Name   = "AIAtt"
	att.Parent = part

	-- LinearVelocity con fuerza de sustentación completa (1e6 Newtons, inmune a caída por gravedad)
	local lv = Instance.new("LinearVelocity")
	lv.Name           = "FlightVelocity"
	lv.Attachment0    = att
	lv.RelativeTo     = Enum.ActuatorRelativeTo.World
	lv.MaxForce       = if isTurret then 0 else 1e6
	lv.VectorVelocity = Vector3.zero
	lv.Enabled        = not isTurret
	lv.Parent         = part

	-- AlignOrientation (giroscopio para unidades aéreas con torque de 1e6)
	local ao = Instance.new("AlignOrientation")
	ao.Name           = "FlightOrientation"
	ao.Attachment0    = att
	ao.Mode           = Enum.OrientationAlignmentMode.OneAttachment
	ao.Responsiveness = 25
	ao.MaxTorque      = if isTurret then 0 else 1e6
	ao.CFrame         = part.CFrame
	ao.Enabled        = not isTurret
	ao.Parent         = part

	-- Una vez vinculados los actuadores, desanclar si es unidad móvil
	part.Anchored = isTurret
	if not isTurret then
		pcall(function()
			part:SetNetworkOwner(nil)
		end)
	end

	-- Punto de luz del acento
	local pl = Instance.new("PointLight")
	pl.Color      = spec.accentColor
	pl.Brightness = 4.5
	pl.Range      = 28
	pl.Parent     = part

	-- Silueta Highlight neón diegética para visibilidad impecable a larga distancia
	local hl = Instance.new("Highlight")
	hl.Name = "EnemyHighlight"
	hl.Adornee = part
	hl.FillColor = spec.accentColor
	hl.FillTransparency = 0.55
	hl.OutlineColor = spec.accentColor
	hl.OutlineTransparency = 0.0
	hl.Parent = part

	-- Efectos específicos por arquetipo
	if not isTurret then
		-- Estela de propulsión para drones móviles
		local thrusterAtt = Instance.new("Attachment")
		thrusterAtt.Name = "ThrusterAtt"
		thrusterAtt.Position = Vector3.new(0, 0, part.Size.Z * 0.45)
		thrusterAtt.Parent = part

		local pe = Instance.new("ParticleEmitter")
		pe.Name = "ThrusterTrail"
		pe.Rate = 25
		pe.Lifetime = NumberRange.new(0.2, 0.4)
		pe.Speed = NumberRange.new(5, 12)
		pe.Color = ColorSequence.new(spec.accentColor)
		pe.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8),
			NumberSequenceKeypoint.new(1, 0),
		})
		pe.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		pe.LightEmission = 1
		pe.Parent = thrusterAtt
	else
		-- Haz láser de escaneo para la torreta Aegis-44
		local laserBeam = Instance.new("Part")
		laserBeam.Name = "LaserSight"
		laserBeam.Size = Vector3.new(0.2, 0.2, 60)
		laserBeam.Material = Enum.Material.Neon
		laserBeam.Color = spec.accentColor
		laserBeam.Transparency = 0.4
		laserBeam.CanCollide = false
		laserBeam.Anchored = true
		laserBeam.CFrame = part.CFrame * CFrame.new(0, 0, -30)
		laserBeam.Parent = part
	end

	-- Rótulo holográfico diegético de hostilidad visible hasta 600 studs
	local tagGui = Instance.new("BillboardGui")
	tagGui.Name        = "EnemyTag"
	tagGui.Size        = UDim2.fromOffset(180, 26)
	tagGui.StudsOffset = Vector3.new(0, part.Size.Y + 1.8, 0)
	tagGui.AlwaysOnTop = true
	tagGui.MaxDistance = 600
	tagGui.Parent      = part

	local tagText = Instance.new("TextLabel")
	tagText.Size                   = UDim2.fromScale(1, 1)
	tagText.BackgroundTransparency = 1
	tagText.Font                   = Enum.Font.Code
	tagText.Text                   = string.format("▼ [%s] ▼", spec.name:upper())
	tagText.TextColor3             = spec.accentColor
	tagText.TextSize               = 11
	tagText.TextStrokeTransparency = 0.2
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

-- Busca el objetivo del jugador activo más cercano (dron en vuelo o piloto fuera de Base)
local function findNearestPlayerTarget(agentPos: Vector3): (Player?, BasePart?)
	local bestDist = math.huge
	local bestPlayer: Player? = nil
	local bestPart: BasePart? = nil
	local baseSafeCenter = Vector3.new(0, 4, 0)

	for _, player in ipairs(Players:GetPlayers()) do
		local dronePart = Workspace:FindFirstChild("TestDrone") :: BasePart?
		local char = player.Character
		local charRoot = char and (char.PrimaryPart or char:FindFirstChild("HumanoidRootPart") :: BasePart?)

		-- Priorizar dron si está activo/volando; de lo contrario el personaje del jugador
		local candidate: BasePart? = nil
		if dronePart and not dronePart.Anchored then
			candidate = dronePart
		elseif charRoot then
			candidate = charRoot
		elseif dronePart then
			candidate = dronePart
		end

		if candidate then
			-- Escudo defensivo de Base Central (< 65 studs): no adquirir objetivo dentro de Base
			local distToBase = (candidate.Position - baseSafeCenter).Magnitude
			if distToBase >= 65 then
				local d = (candidate.Position - agentPos).Magnitude
				if d < bestDist then
					bestDist   = d
					bestPlayer = player
					bestPart   = candidate
				end
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
	part:SetAttribute("EnemySpecId", spec.id)
	part:SetAttribute("Bounty", spec.creditReward)

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
		homeCenter     = spawnPosition,
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
			nil,  -- owner (NPC)
			spec.creditReward -- recompensa en PELAOCOINS
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

	-- Registrar daño en CombatService con vector de procedencia
	if _G.CombatService and _G.CombatService.ApplyDamage then
		_G.CombatService.ApplyDamage(agent.targetPart, 14, nil, agent.part.Position)
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
			_G.CombatService.ApplyDamage(agent.targetPart, 22, nil, agent.part.Position)
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

		-- Detectar jugador más cercano en rango (fuera del perímetro seguro de Base)
		local targetPlayer, targetPart = findNearestPlayerTarget(part.Position)
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

		if mode == "ramming" then
			if agent.targetPart then
				-- Seek agresivo hacia el dron del jugador + separación enjambre (flocking)
				local seekV = seek(part.Position, agent.targetPart.Position, agent.spec.maxSpeed)
				local sepV  = separation(part.Position, gnatParts, 8) * SEPARATION_WEIGHT
				steerForce  = seekV + sepV
				handleRamming(agent)
			else
				-- Patrulla activa en reposo: vuelo orbital y oscilación vertical en enjambre
				agent.orbitAngle += AI_TICK_RATE * 0.9
				local home = agent.homeCenter or part.Position
				local patrolTarget = home + Vector3.new(
					math.cos(agent.orbitAngle) * 32,
					math.sin(agent.orbitAngle * 1.8) * 8,
					math.sin(agent.orbitAngle) * 32
				)
				local sepV = separation(part.Position, gnatParts, 10) * SEPARATION_WEIGHT
				steerForce = arrive(part.Position, patrolTarget, 28, 15) + sepV
			end

		elseif mode == "turret" then
			if agent.targetPart then
				local toTarget = (agent.targetPart.Position - part.Position)
				if toTarget.Magnitude > 0 then
					local targetCF = CFrame.lookAt(part.Position, agent.targetPart.Position)
					part.CFrame = part.CFrame:Lerp(targetCF, 0.20)
				end
				handleFiring(agent)
			else
				-- Barrido rotativo suave de vigilancia de 360° en reposo
				part.CFrame = part.CFrame * CFrame.Angles(0, math.rad(AI_TICK_RATE * 35), 0)
			end

			-- Sincronizar haz láser de la torreta
			local laserSight = part:FindFirstChild("LaserSight") :: BasePart?
			if laserSight then
				laserSight.CFrame = part.CFrame * CFrame.new(0, 0, -30)
			end
			steerForce = Vector3.zero

		elseif mode == "orbit" then
			if agent.targetPart then
				-- Órbita lateral agresiva alrededor del jugador atacando con microondas
				agent.orbitAngle += AI_TICK_RATE * 0.7
				steerForce = orbitTangent(
					part.Position,
					agent.targetPart.Position,
					agent.spec.orbitRadius,
					agent.orbitAngle,
					agent.spec.maxSpeed
				)
				handleFiring(agent)
			else
				-- Patrulla de gran altitud en órbita alrededor de su punto base
				agent.orbitAngle += AI_TICK_RATE * 0.5
				local home = agent.homeCenter or part.Position
				local patrolTarget = home + Vector3.new(
					math.cos(agent.orbitAngle) * 50,
					math.sin(agent.orbitAngle) * 6,
					math.sin(agent.orbitAngle) * 50
				)
				steerForce = arrive(part.Position, patrolTarget, 38, 20)
			end
		end

		-- Escudo de seguridad perimetral de Base Central: si una nave enemiga se aproxima a < 70 studs, forzar retirada
		if mode ~= "turret" then
			local distToBase = (part.Position - Vector3.new(0, 4, 0)).Magnitude
			if distToBase < 70 then
				local toHome = (agent.homeCenter or part.Position) - part.Position
				if toHome.Magnitude > 1 then
					steerForce = toHome.Unit * agent.spec.maxSpeed
				else
					local fleeBase = (part.Position - Vector3.new(0, 4, 0)).Unit
					steerForce = fleeBase * agent.spec.maxSpeed
				end
				agent.targetPart = nil
				agent.targetPlayer = nil
			end
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
		activationRadius = 260,
		deactivationRadius = 600,
		respawnCooldown = 35,
		lastClearedTime = 0,
		archetypes = {
			-- Enjambre Scav-Gnats sobrevolando en patrulla aérea continua sobre Torre A
			{ specId = "scav_gnats", offset = Vector3.new(-16, 12, 16), difficulty = 0.1 },
			{ specId = "scav_gnats", offset = Vector3.new(16, 16, -14), difficulty = 0.15 },
			{ specId = "scav_gnats", offset = Vector3.new(0, 10, 20),   difficulty = 0.2 },
		},
		activeParts = {},
		isActive = false,
	},
	Zone_TorreB = {
		id = "Zone_TorreB",
		name = "Sector Black Ops (Torre B)",
		threatLevel = "black_ops",
		center = Vector3.new(-200, 50, 140),
		activationRadius = 280,
		deactivationRadius = 600,
		respawnCooldown = 45,
		lastClearedTime = 0,
		archetypes = {
			-- Torreta Aegis asentada firmemente sobre la cornisa de la azotea de Torre B (Y = 52.5)
			{ specId = "aegis_44",  offset = Vector3.new(14, 2.5, 14), difficulty = 0.25 },
			-- Interceptor orbital Kuroshio patrullando en órbita alta (Y = 78)
			{ specId = "kuroshio_v", offset = Vector3.new(-15, 28, 15), difficulty = 0.35 },
		},
		activeParts = {},
		isActive = false,
	},
}

local function activateZone(zone: ThreatZone)
	if zone.isActive then return end
	local now = os.clock()
	if zone.lastClearedTime > 0 and (now - zone.lastClearedTime) < zone.respawnCooldown then
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

	print(string.format("[ThreatDirector] ¡Zona '%s' ACTIVADA! %d unidades hostiles patrullando.", zone.name, #zone.activeParts))
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
	print(string.format("[ThreatDirector] Zona '%s' replegada. Recursos liberados.", zone.name))
end

-- Bucle de Director de Amenazas (1 Hz): Monitoreo de combate y autorreaparición táctica
task.spawn(function()
	while true do
		task.wait(1.0)
		local now = os.clock()

		for _, zone in pairs(threatZones) do
			if zone.isActive then
				-- Contar unidades supervivientes en la zona
				local aliveCount = 0
				for _, part in ipairs(zone.activeParts) do
					if part and part.Parent and activeAgents[part] and activeAgents[part].isAlive then
						aliveCount += 1
					end
				end

				-- Si todas las unidades fueron destruidas por el jugador en combate
				if aliveCount == 0 and #zone.activeParts > 0 then
					zone.isActive = false
					zone.lastClearedTime = now
					table.clear(zone.activeParts)
					print(string.format("[ThreatDirector] ¡SECTOR '%s' DESPEJADO POR EL PILOTO! Cooldown táctico de %ds antes de refuerzos.", zone.name, zone.respawnCooldown))
				end
			else
				-- Autorreaparición: al expirar el cooldown de sector despejado, desplegar nueva patrulla
				if (now - zone.lastClearedTime) >= zone.respawnCooldown then
					activateZone(zone)
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

-- Inicialización diferida garantizada: esperar a CombatService y desplegar patrullas en el mundo
task.spawn(function()
	local waitStart = os.clock()
	while not _G.CombatService and (os.clock() - waitStart < 5) do
		task.wait(0.1)
	end

	activateZone(threatZones.Zone_TorreA)
	activateZone(threatZones.Zone_TorreB)

	local totalEnemies = _G.EnemyAIService.GetActiveCount()
	print(string.format("[EnemyAIService] ¡MUNDO HOSTIL INICIALIZADO! %d enemigos activos patrullando Torre A y Torre B.", totalEnemies))
end)

print("[EnemyAIService] Servicio de IA y Director de Amenaza activo a 10 Hz / 1 Hz.")

