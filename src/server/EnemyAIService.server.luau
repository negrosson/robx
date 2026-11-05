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
	local part = Instance.new("Part")
	part.Name         = spec.id .. "_" .. tostring(math.random(1000, 9999))
	part.Size         = spec.scale * 4.5  -- escala relativa al TestDrone estándar (4.5)
	part.Material     = Enum.Material.Metal
	part.Color        = spec.primaryColor
	part.Anchored     = false
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

	-- LinearVelocity (único motor de movimiento, NO BodyVelocity)
	local lv = Instance.new("LinearVelocity")
	lv.Name           = "FlightVelocity"
	lv.Attachment0    = att
	lv.RelativeTo     = Enum.ActuatorRelativeTo.World
	lv.MaxForce       = spec.maxForce * spec.mass
	lv.VectorVelocity = Vector3.zero
	lv.Parent         = part

	-- AlignOrientation (giroscopio — sin BodyGyro)
	local ao = Instance.new("AlignOrientation")
	ao.Name          = "FlightOrientation"
	ao.Attachment0   = att
	ao.Mode          = Enum.OrientationAlignmentMode.OneAttachment
	ao.Responsiveness = 20
	ao.MaxTorque     = 1e5
	ao.CFrame        = part.CFrame
	ao.Parent        = part

	-- Punto de luz del acento
	local pl = Instance.new("PointLight")
	pl.Color      = spec.accentColor
	pl.Brightness = 2
	pl.Range      = 12
	pl.Parent     = part

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
function EnemyAIService_Spawn(specId: string, spawnPosition: Vector3, difficulty: number?)
	local baseSpec = EnemyTypes.ById[specId]
	if not baseSpec then
		warn("[EnemyAIService] Spec no encontrado:", specId)
		return
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
	print(string.format("[EnemyAIService] Spawned %s en %s", spec.name, tostring(spawnPosition)))
end

----------------------------------------------------------------------
-- LÓGICA DE IA — Daño por embestida
----------------------------------------------------------------------
local function handleRamming(agent: EnemyAgent)
	if not agent.targetPart then return end
	local now = os.clock()
	if now - agent.lastRamTime < RAMMING_COOLDOWN then return end

	local dist = (agent.part.Position - agent.targetPart.Position).Magnitude
	if dist > 5 then return end  -- solo embestir en contacto cercano

	agent.lastRamTime = now

	-- Aplicar impulso físico al dron del jugador (desestabilización)
	local impactDir = (agent.targetPart.Position - agent.part.Position).Unit
	agent.targetPart.AssemblyLinearVelocity += impactDir * agent.spec.rammingImpulse

	-- Registrar daño en CombatService
	if _G.CombatService then
		_G.CombatService.ApplyDamage(agent.targetPart, 15)  -- daño de embestida base
	end

	print(string.format("[EnemyAIService] %s embistió al jugador (%.0f N)", agent.spec.name, agent.spec.rammingImpulse))
end

----------------------------------------------------------------------
-- LÓGICA DE IA — Disparo de torreta/interceptor
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

	-- Delegar daño al CombatService
	if _G.CombatService then
		if agent.spec.burstWeapon == "synapse_overheat" then
			-- Microondas: inyectar calor
			_G.CombatService.ApplyHeat(agent.targetPart, 12)
		elseif agent.spec.burstWeapon == "rail_driver" then
			-- Cañón de riel: daño cinético
			_G.CombatService.ApplyDamage(agent.targetPart, 30)
		end
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
			-- Estacionaria: solo rota hacia el objetivo
			if agent.targetPart then
				local lookDir = (agent.targetPart.Position - part.Position)
				if lookDir.Magnitude > 0 then
					agent.alignOrient.CFrame = CFrame.lookAt(Vector3.zero, lookDir.Unit, Vector3.yAxis)
				end
				handleFiring(agent)
			end
			-- No aplica fuerza de movimiento (estacionaria)
			steerForce = Vector3.zero

		elseif mode == "orbit" and agent.targetPart then
			-- Órbita lateral tangencial
			agent.orbitAngle += AI_TICK_RATE * 0.5  -- avanza 0.5 rad/s por tick
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
-- SPAWN DE OLEADAS DE PRUEBA (ejemplos de uso)
----------------------------------------------------------------------
-- Generador automático de enjambres en posiciones aleatorias para prueba en studio
local function spawnTestWave()
	local positions = {
		Vector3.new(30, 15, 30),
		Vector3.new(-40, 20, 50),
		Vector3.new(60, 12, -30),
	}

	-- Enjambre de gnats
	for i = 1, 3 do
		local pos = positions[math.random(#positions)] + Vector3.new(math.random(-10, 10), math.random(5, 20), math.random(-10, 10))
		EnemyAIService_Spawn("scav_gnats", pos, 0.2)
	end

	-- Interceptor orbital
	EnemyAIService_Spawn("kuroshio_v", Vector3.new(100, 30, 0), 0.3)
end

-- NOTA: Spawn de prueba automático desactivado para evitar ataques no solicitados
-- mientras el jugador está aprendiendo o realizando entregas estándar.
-- Usar _G.EnemyAIService.SpawnTestWave() o _G.EnemyAIService.Spawn(...) bajo demanda.
--[[
task.delay(10, function()
	spawnTestWave()
	print("[EnemyAIService] Oleada de prueba inicial generada.")
end)
]]

-- Exponer API global para uso desde Main.server.luau
_G.EnemyAIService = {
	Spawn = EnemyAIService_Spawn,
	GetActiveCount = function(): number
		local count = 0
		for _ in pairs(activeAgents) do count += 1 end
		return count
	end,
}

print("[EnemyAIService] Servicio de IA activo a 10 Hz.")

