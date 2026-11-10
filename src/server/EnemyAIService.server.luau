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

local NetworkEventsModule = (ReplicatedStorage:FindFirstChild("NetworkEvents") or ReplicatedStorage:WaitForChild("NetworkEvents", 30)) :: ModuleScript
local NetworkEvents = require(NetworkEventsModule)
local incomingThreatAlertEvent = NetworkEvents.Get(NetworkEvents.Names.IncomingThreatAlert)

local combatFXFolder = Workspace:FindFirstChild("CombatFX")
if not combatFXFolder then
	combatFXFolder = Instance.new("Folder")
	combatFXFolder.Name = "CombatFX"
	combatFXFolder.Parent = Workspace
end

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
export type SquadRole = "leader" | "flanker_left" | "flanker_right" | "reserve"

type SquadMember = {
	agent: EnemyAgent,
	role: SquadRole,
	assignedSide: number,
	strikeDelay: number,
	lastStrikeTime: number,
}

type ThreatSquad = {
	id: string,
	leaderPart: BasePart?,
	members: { [BasePart]: SquadMember },
	phase: "approach" | "flank_spread" | "converging_strike" | "disarray",
	phaseTimer: number,
	targetPlayer: Player?,
	targetPart: BasePart?,
}

type EnemyAgent = {
	spec           : any,          -- EnemyTypes.EnemySpec
	part           : BasePart,
	health         : number,
	velocity       : Vector3,      -- velocidad actual 3D del agente
	targetPlayer   : Player?,
	targetPart     : BasePart?,    -- dron objetivo del jugador
	lastFireTime   : number,
	lastRamTime    : number,
	orbitAngle     : number,       -- ángulo orbital actual (rad) para Kuroshio
	isAlive        : boolean,
	linearVelocity : LinearVelocity,
	alignOrient    : AlignOrientation,
	homeCenter     : Vector3?,     -- punto de patrulla en reposo
	isCharging     : boolean?,
	chargeStartTime: number?,
	chargeDuration : number?,
	telegraphLaser : BasePart?,
	squadId        : string?,
	squadRole      : SquadRole?,
}

local activeAgents: { [BasePart]: EnemyAgent } = {}
local activeSquads: { [string]: ThreatSquad } = {}
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

	-- Escudo frontal hexagonal de energía si el arquetipo lo especifica (Aegis-Bulwark)
	if spec.hasFrontalShield then
		part:SetAttribute("HasFrontalShield", true)
		part:SetAttribute("ShieldReduction", spec.shieldReduction or 0.85)

		local shield = Instance.new("Part")
		shield.Name = "FrontShield"
		shield.Size = Vector3.new(part.Size.X * 1.35, part.Size.Y * 1.45, 0.35)
		shield.Material = Enum.Material.ForceField
		shield.Color = spec.accentColor or Color3.fromRGB(0, 220, 255)
		shield.Transparency = 0.35
		shield.CanCollide = false
		shield.CanQuery = false
		shield.CanTouch = false
		shield.Massless = true
		shield.CFrame = part.CFrame * CFrame.new(0, 0, -part.Size.Z * 0.55)
		shield.Parent = part

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = shield
		weld.Parent = part

		local shieldLight = Instance.new("PointLight")
		shieldLight.Color = shield.Color
		shieldLight.Brightness = 3
		shieldLight.Range = 16
		shieldLight.Parent = shield
	end

	-- Rótulo holográfico diegético de hostilidad con barra de vida segmentada (pips/rayitas)
	local tagGui = Instance.new("BillboardGui")
	tagGui.Name        = "EnemyTag"
	tagGui.Size        = UDim2.fromOffset(200, 34)
	tagGui.StudsOffset = Vector3.new(0, part.Size.Y + 2.0, 0)
	tagGui.AlwaysOnTop = true
	tagGui.MaxDistance = 600
	tagGui.Parent      = part

	local tagText = Instance.new("TextLabel")
	tagText.Name                   = "NameLabel"
	tagText.Size                   = UDim2.new(1, 0, 0, 16)
	tagText.Position               = UDim2.new(0, 0, 0, 0)
	tagText.BackgroundTransparency = 1
	tagText.Font                   = Enum.Font.Code
	tagText.Text                   = string.format("▼ [%s] ▼", spec.name:upper())
	tagText.TextColor3             = spec.accentColor
	tagText.TextSize               = 11
	tagText.TextStrokeTransparency = 0.2
	tagText.Parent                 = tagGui

	-- Contenedor de "rayitas de vida" segmentadas según la dureza del dron
	local pipsCount = math.clamp(math.round(spec.maxHealth / 20), 3, 14)
	local pipsBar = Instance.new("Frame")
	pipsBar.Name = "HealthPipsBar"
	pipsBar.Size = UDim2.new(1, -24, 0, 7)
	pipsBar.Position = UDim2.new(0, 12, 0, 18)
	pipsBar.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
	pipsBar.BackgroundTransparency = 0.35
	pipsBar.BorderSizePixel = 0
	pipsBar.Parent = tagGui

	local pipsBarCorner = Instance.new("UICorner")
	pipsBarCorner.CornerRadius = UDim.new(0, 2)
	pipsBarCorner.Parent = pipsBar

	local pipsList = Instance.new("UIListLayout")
	pipsList.FillDirection = Enum.FillDirection.Horizontal
	pipsList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	pipsList.VerticalAlignment = Enum.VerticalAlignment.Center
	pipsList.Padding = UDim.new(0, 2)
	pipsList.Parent = pipsBar

	local pipWidth = (1.0 / pipsCount)
	local pips: { Frame } = {}
	for i = 1, pipsCount do
		local pip = Instance.new("Frame")
		pip.Name = "Pip_" .. tostring(i)
		pip.Size = UDim2.new(pipWidth, -2, 1, -2)
		pip.BackgroundColor3 = spec.accentColor
		pip.BorderSizePixel = 0
		pip.Parent = pipsBar

		local pipCorner = Instance.new("UICorner")
		pipCorner.CornerRadius = UDim.new(0, 1)
		pipCorner.Parent = pip

		table.insert(pips, pip)
	end

	-- Conectar actualización en vivo de rayitas de vida al recibir daño
	part:GetAttributeChangedSignal("Health"):Connect(function()
		local hp = (part:GetAttribute("Health") :: number?) or spec.maxHealth
		local maxHp = (part:GetAttribute("MaxHealth") :: number?) or spec.maxHealth
		local pct = math.clamp(hp / maxHp, 0, 1)
		local activePips = math.ceil(pct * pipsCount)

		for i, pip in ipairs(pips) do
			if i <= activePips then
				if pct > 0.5 then
					pip.BackgroundColor3 = spec.accentColor
				elseif pct > 0.25 then
					pip.BackgroundColor3 = Color3.fromRGB(255, 200, 30)
				else
					pip.BackgroundColor3 = Color3.fromRGB(255, 45, 45)
				end
				pip.BackgroundTransparency = 0
			else
				pip.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
				pip.BackgroundTransparency = 0.75
			end
		end

		-- Destello de impacto sutil en la barra
		pcall(function()
			pipsBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			task.delay(0.08, function()
				if pipsBar and pipsBar.Parent then
					pipsBar.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
				end
			end)
		end)
	end)

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
-- GESTIÓN DE ESCUADRONES EN PINZA (SQUAD PINCER ARCHITECTURE)
----------------------------------------------------------------------
local function createSquad(squadId: string, leaderAgent: EnemyAgent, flankerAgents: { EnemyAgent }): ThreatSquad
	local squad: ThreatSquad = {
		id = squadId,
		leaderPart = leaderAgent.part,
		members = {},
		phase = "approach",
		phaseTimer = 0,
		targetPlayer = nil,
		targetPart = nil,
	}

	-- 1. Asignar rol de Líder
	leaderAgent.squadId = squadId
	leaderAgent.squadRole = "leader"
	squad.members[leaderAgent.part] = {
		agent = leaderAgent,
		role = "leader",
		assignedSide = 0,
		strikeDelay = 0,
		lastStrikeTime = 0,
	}

	local tagGui = leaderAgent.part:FindFirstChild("EnemyTag")
	local nameLabel = tagGui and tagGui:FindFirstChild("NameLabel") :: TextLabel?
	if nameLabel then
		nameLabel.Text = string.format("👑 [%s // LÍDER] 👑", leaderAgent.spec.name:upper())
		nameLabel.TextColor3 = Color3.fromRGB(255, 215, 60)
	end

	-- 2. Asignar roles de Flanqueadores (Izquierda y Derecha)
	local sides = { -1, 1, -1, 1 }
	for idx, flanker in ipairs(flankerAgents) do
		local side = sides[idx] or -1
		local role: SquadRole = if side == -1 then "flanker_left" else "flanker_right"
		flanker.squadId = squadId
		flanker.squadRole = role

		squad.members[flanker.part] = {
			agent = flanker,
			role = role,
			assignedSide = side,
			strikeDelay = if side == 1 then 0.45 else 0, -- Ataque escalonado en tijera
			lastStrikeTime = 0,
		}

		local fTag = flanker.part:FindFirstChild("EnemyTag")
		local fLabel = fTag and fTag:FindFirstChild("NameLabel") :: TextLabel?
		if fLabel then
			local arrow = if side == -1 then "◄ [FLANCO IZQ]" else "[FLANCO DER] ►"
			fLabel.Text = string.format("%s %s", arrow, flanker.spec.name:upper())
		end
	end

	activeSquads[squadId] = squad
	print(string.format("[SquadAI] Escuadrón '%s' formado: Líder (%s) + %d flanqueadores.", squadId, leaderAgent.spec.name, #flankerAgents))
	return squad
end

local function dissolveSquad(squadId: string)
	local squad = activeSquads[squadId]
	if not squad then return end
	for _, member in pairs(squad.members) do
		if member.agent then
			member.agent.squadId = nil
			member.agent.squadRole = nil
		end
	end
	activeSquads[squadId] = nil
	print(string.format("[SquadAI] Escuadrón '%s' disuelto.", squadId))
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
	if dist > 11 then return end  -- Radio de contacto ampliado a 11 studs para registro consistente a 10 Hz

	agent.lastRamTime = now

	-- Aplicar impulso físico al dron del jugador (desestabilización aerodinámica)
	local impactDir = (agent.targetPart.Position - agent.part.Position).Unit
	agent.targetPart.AssemblyLinearVelocity += impactDir * (agent.spec.rammingImpulse or 55)

	-- Rebote físico de retroceso para el Scav-Gnat (evita que se pegue o traspase)
	agent.part.AssemblyLinearVelocity = -impactDir * 32 + Vector3.new(0, 10, 0)
	agent.velocity = -impactDir * 22

	-- Sonido metálico de colisión/impacto contundente
	local ramSound = Instance.new("Sound")
	ramSound.SoundId = "rbxassetid://9114221580"
	ramSound.Volume = 1.8
	ramSound.PlaybackSpeed = math.random(95, 110) / 100
	ramSound.RollOffMaxDistance = 180
	ramSound.Parent = agent.part
	ramSound:Play()
	Debris:AddItem(ramSound, 2)

	-- Destello de impacto y chispas
	local sparkPos = (agent.part.Position + agent.targetPart.Position) / 2
	local sparkPart = Instance.new("Part")
	sparkPart.Size = Vector3.new(1, 1, 1)
	sparkPart.Position = sparkPos
	sparkPart.Transparency = 1
	sparkPart.Anchored = true
	sparkPart.CanCollide = false
	sparkPart.Parent = Workspace

	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(3.5, 3.5, 3.5)
	flash.Position = sparkPos
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 140, 20)
	flash.Anchored = true
	flash.CanCollide = false
	flash.Parent = Workspace
	Debris:AddItem(flash, 0.10)

	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 120, 30))
	pe.Size = NumberSequence.new(0.6, 0)
	pe.Lifetime = NumberRange.new(0.2, 0.4)
	pe.Rate = 180
	pe.Speed = NumberRange.new(20, 35)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Parent = sparkPart
	task.delay(0.18, function()
		if pe and pe.Parent then pe.Enabled = false end
	end)
	Debris:AddItem(sparkPart, 0.6)

	-- Registrar daño en CombatService con vector de procedencia
	if _G.CombatService and _G.CombatService.ApplyDamage then
		_G.CombatService.ApplyDamage(agent.targetPart, 14, { name = "Embestida Scav-Gnat" }, nil, agent.part.Position)
	end

	print(string.format("[EnemyAIService] ¡IMPACTO! %s embistió al jugador (%.0f N | -14 HP)", agent.spec.name, agent.spec.rammingImpulse))
end

----------------------------------------------------------------------
-- LÓGICA DE IA — Telegrafiado Láser Pre-Disparo & Disparo Gauss
----------------------------------------------------------------------
local function cleanupTelegraph(agent: EnemyAgent, reason: string?)
	if agent.telegraphLaser and agent.telegraphLaser.Parent then
		agent.telegraphLaser:Destroy()
		agent.telegraphLaser = nil
	end
	agent.isCharging = false
	if agent.targetPlayer and incomingThreatAlertEvent then
		pcall(function()
			incomingThreatAlertEvent:FireClient(agent.targetPlayer, {
				threatType = "cleared",
				reason = reason,
			})
		end)
	end
end

local function handleRailDriverCharging(agent: EnemyAgent, now: number)
	if not agent.targetPart or not agent.targetPart.Parent then
		if agent.isCharging then cleanupTelegraph(agent, "Blanco perdido") end
		return
	end

	-- Si el agente está incapacitado por EMP o desorientado por bengalas térmicas
	if agent.part:FindFirstChild("EMPHighlight") or agent.part:FindFirstChild("FlaresConfused") then
		if agent.isCharging then cleanupTelegraph(agent, "Amenaza neutralizada") end
		return
	end

	local dist = (agent.part.Position - agent.targetPart.Position).Magnitude
	if dist > agent.spec.fireRange then
		if agent.isCharging then cleanupTelegraph(agent, "Fuera de alcance") end
		return
	end

	-- Verificar línea de visión estricta contra torres, pilares y estructuras sólidas
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local mExclude: { Instance } = { agent.part, agentFolder, combatFXFolder }
	params.FilterDescendantsInstances = mExclude

	local direction = agent.targetPart.Position - agent.part.Position
	local result = Workspace:Raycast(agent.part.Position, direction, params)

	local hasLOS = false
	if not result then
		hasLOS = true
	elseif result.Instance == agent.targetPart or result.Instance:IsDescendantOf(agent.targetPart) then
		hasLOS = true
	elseif agent.targetPlayer and agent.targetPlayer.Character and result.Instance:IsDescendantOf(agent.targetPlayer.Character) then
		hasLOS = true
	end

	-- FASE 1: Iniciar carga si no está cargando
	if not agent.isCharging then
		if now - agent.lastFireTime < TURRET_FIRE_RATE then return end
		if not hasLOS then return end

		agent.isCharging = true
		agent.chargeStartTime = now
		agent.chargeDuration = 1.05

		-- Haz láser de telegrafiado fino rojo en 3D
		local laser = Instance.new("Part")
		laser.Name = "TelegraphLaser"
		laser.Size = Vector3.new(0.14, 0.14, dist)
		laser.Material = Enum.Material.Neon
		laser.Color = Color3.fromRGB(255, 35, 35)
		laser.Transparency = 0.45
		laser.CanCollide = false
		laser.CanQuery = false
		laser.CanTouch = false
		laser.Anchored = true
		laser.CFrame = CFrame.lookAt(agent.part.Position, agent.targetPart.Position) * CFrame.new(0, 0, -dist / 2)
		laser.Parent = combatFXFolder
		agent.telegraphLaser = laser

		-- Sonido diegético de carga inminente
		local chargeSfx = Instance.new("Sound")
		chargeSfx.SoundId = "rbxassetid://9114223170"
		chargeSfx.Volume = 1.5
		chargeSfx.PlaybackSpeed = 1.65
		chargeSfx.RollOffMaxDistance = 260
		chargeSfx.Parent = agent.part
		chargeSfx:Play()
		Debris:AddItem(chargeSfx, 1.2)

		-- Notificar al HUD del jugador fijado
		if agent.targetPlayer and incomingThreatAlertEvent then
			pcall(function()
				incomingThreatAlertEvent:FireClient(agent.targetPlayer, {
					threatType = "sniper_laser",
					sourceName = agent.spec.name,
					distance = dist,
					duration = agent.chargeDuration,
				})
			end)
		end
		return
	end

	-- FASE 2: Si ya estaba cargando, verificar si rompió línea de visión
	if not hasLOS then
		-- ¡El jugador se cubrió detrás de un edificio o helipuerto! Rompió la fijación
		cleanupTelegraph(agent, "Cobertura asegurada")
		return
	end

	local elapsed = now - (agent.chargeStartTime or now)
	local duration = agent.chargeDuration or 1.05
	local progress = math.clamp(elapsed / duration, 0, 1)

	-- Actualizar haz de seguimiento y grosor/brillo en tiempo real
	if agent.telegraphLaser and agent.telegraphLaser.Parent then
		local curDist = (agent.part.Position - agent.targetPart.Position).Magnitude
		agent.telegraphLaser.Size = Vector3.new(0.14 + progress * 0.22, 0.14 + progress * 0.22, curDist)
		agent.telegraphLaser.CFrame = CFrame.lookAt(agent.part.Position, agent.targetPart.Position) * CFrame.new(0, 0, -curDist / 2)
		agent.telegraphLaser.Transparency = 0.45 - progress * 0.35
		if progress > 0.72 and math.random() > 0.5 then
			agent.telegraphLaser.Color = Color3.fromRGB(255, 255, 255)
		else
			agent.telegraphLaser.Color = Color3.fromRGB(255, 35, 35)
		end
	end

	-- FASE 3: Completó la carga (1.05s transcurridos sin cobertura) → DISPARO GAUSS REAL
	if progress >= 1.0 then
		cleanupTelegraph(agent, nil)
		agent.lastFireTime = now

		-- SFX disparo pesado Gauss
		local railSound = Instance.new("Sound")
		railSound.SoundId = "rbxassetid://9114223400"
		railSound.Volume = 2.4
		railSound.PlaybackSpeed = 0.92
		railSound.RollOffMaxDistance = 340
		railSound.Parent = agent.part
		railSound:Play()
		Debris:AddItem(railSound, 2.5)

		-- Muzzle Flash
		local muzzlePos = agent.part.CFrame * CFrame.new(0, 0, -3.2)
		local muzzleFlare = Instance.new("Part")
		muzzleFlare.Shape = Enum.PartType.Ball
		muzzleFlare.Size = Vector3.new(3.2, 3.2, 3.2)
		muzzleFlare.Position = muzzlePos.Position
		muzzleFlare.Material = Enum.Material.Neon
		muzzleFlare.Color = Color3.fromRGB(255, 220, 100)
		muzzleFlare.Anchored = true
		muzzleFlare.CanCollide = false
		muzzleFlare.CanQuery = false
		muzzleFlare.CanTouch = false
		muzzleFlare.Parent = combatFXFolder
		Debris:AddItem(muzzleFlare, 0.12)

		-- Trazador Gauss cinético de alta energía
		local curDist = (agent.part.Position - agent.targetPart.Position).Magnitude
		local tracer = Instance.new("Part")
		tracer.Name = "GaussTracer"
		tracer.Size = Vector3.new(0.85, 0.85, curDist)
		tracer.CFrame = CFrame.lookAt(agent.part.Position, agent.targetPart.Position) * CFrame.new(0, 0, -curDist / 2)
		tracer.Anchored = true
		tracer.CanCollide = false
		tracer.CanQuery = false
		tracer.CanTouch = false
		tracer.Material = Enum.Material.Neon
		tracer.Color = Color3.fromRGB(255, 170, 0)
		tracer.Transparency = 0.05
		tracer.Parent = combatFXFolder
		Debris:AddItem(tracer, 0.20)

		-- Núcleo incandescente
		local tracerCore = Instance.new("Part")
		tracerCore.Size = Vector3.new(0.35, 0.35, curDist)
		tracerCore.CFrame = tracer.CFrame
		tracerCore.Anchored = true
		tracerCore.CanCollide = false
		tracerCore.CanQuery = false
		tracerCore.CanTouch = false
		tracerCore.Material = Enum.Material.Neon
		tracerCore.Color = Color3.fromRGB(255, 255, 230)
		tracerCore.Parent = combatFXFolder
		Debris:AddItem(tracerCore, 0.18)

		-- Impacto cinético en el dron del jugador
		agent.targetPart.AssemblyLinearVelocity += direction.Unit * 34

		local dmg = if agent.spec.id == "aegis_bulwark" then 26 else 22
		if _G.CombatService and _G.CombatService.ApplyDamage then
			_G.CombatService.ApplyDamage(agent.targetPart, dmg, { name = agent.spec.name }, nil, agent.part.Position)
		end
		print(string.format("[EnemyAIService] %s detonó Rail-Driver Gauss (-%d HP | 34 N)", agent.spec.name, dmg))
	end
end

----------------------------------------------------------------------
-- LÓGICA DE IA — Disparo general de torreta/interceptor con Proyectiles Visibles
----------------------------------------------------------------------
local function handleFiring(agent: EnemyAgent)
	if agent.spec.burstWeapon == "" or not agent.targetPart then
		if agent.isCharging then
			cleanupTelegraph(agent, "Blanco perdido")
		end
		return
	end

	local now = os.clock()

	-- Armas con telegrafiado de disparo pesado (Gauss Rail-Driver)
	if agent.spec.burstWeapon == "rail_driver" then
		handleRailDriverCharging(agent, now)
		return
	end

	-- Armas estándar (Microondas continuas de Kuroshio-V)
	if now - agent.lastFireTime < TURRET_FIRE_RATE then return end

	local dist = (agent.part.Position - agent.targetPart.Position).Magnitude
	if dist > agent.spec.fireRange then return end

	-- Verificar línea de visión estricta contra torres, pilares y estructuras sólidas
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local mExclude: { Instance } = { agent.part, agentFolder, combatFXFolder }
	params.FilterDescendantsInstances = mExclude

	local direction = agent.targetPart.Position - agent.part.Position
	local result = Workspace:Raycast(agent.part.Position, direction, params)

	local hasLOS = false
	if not result then
		hasLOS = true
	elseif result.Instance == agent.targetPart or result.Instance:IsDescendantOf(agent.targetPart) then
		hasLOS = true
	elseif agent.targetPlayer and agent.targetPlayer.Character and result.Instance:IsDescendantOf(agent.targetPlayer.Character) then
		hasLOS = true
	end

	-- Si hay una torre, pilar o helipuerto bloqueando la línea de tiro, NO dispara a través de ella
	if not hasLOS then return end

	agent.lastFireTime = now

	-- Kuroshio-V: Haz dual de microondas ionizadas violeta/cian con audio
	if agent.spec.burstWeapon == "synapse_overheat" then
		local humSound = Instance.new("Sound")
		humSound.SoundId = "rbxassetid://9114223170"
		humSound.Volume = 1.5
		humSound.PlaybackSpeed = 1.15
		humSound.RollOffMaxDistance = 220
		humSound.Parent = agent.part
		humSound:Play()
		Debris:AddItem(humSound, 2)

		-- Haz exterior violeta
		local pulse = Instance.new("Part")
		pulse.Name = "MicrowavePulse"
		pulse.Size = Vector3.new(0.6, 0.6, dist)
		pulse.CFrame = CFrame.lookAt(agent.part.Position, agent.targetPart.Position) * CFrame.new(0, 0, -dist / 2)
		pulse.Anchored = true
		pulse.CanCollide = false
		pulse.CanQuery = false
		pulse.CanTouch = false
		pulse.Material = Enum.Material.Neon
		pulse.Color = Color3.fromRGB(180, 0, 255)
		pulse.Transparency = 0.25
		pulse.Parent = combatFXFolder
		Debris:AddItem(pulse, 0.22)

		-- Núcleo interior cian brillante
		local core = Instance.new("Part")
		core.Name = "MicrowaveCore"
		core.Size = Vector3.new(0.25, 0.25, dist)
		core.CFrame = pulse.CFrame
		core.Anchored = true
		core.CanCollide = false
		core.CanQuery = false
		core.CanTouch = false
		core.Material = Enum.Material.Neon
		core.Color = Color3.fromRGB(0, 240, 255)
		core.Transparency = 0.05
		core.Parent = combatFXFolder
		Debris:AddItem(core, 0.20)

		-- Chispas electromagnéticas en la posición del objetivo
		local sparkPart = Instance.new("Part")
		sparkPart.Size = Vector3.new(0.5, 0.5, 0.5)
		sparkPart.Position = agent.targetPart.Position
		sparkPart.Transparency = 1
		sparkPart.Anchored = true
		sparkPart.CanCollide = false
		sparkPart.CanQuery = false
		sparkPart.CanTouch = false
		sparkPart.Parent = combatFXFolder
		local pe = Instance.new("ParticleEmitter")
		pe.Color = ColorSequence.new(Color3.fromRGB(200, 50, 255))
		pe.Size = NumberSequence.new(0.4, 0)
		pe.Lifetime = NumberRange.new(0.15, 0.25)
		pe.Rate = 90
		pe.Speed = NumberRange.new(10, 20)
		pe.Parent = sparkPart
		task.delay(0.15, function() if pe and pe.Parent then pe.Enabled = false end end)
		Debris:AddItem(sparkPart, 0.5)

		if _G.CombatService and _G.CombatService.ApplyHeat then
			_G.CombatService.ApplyHeat(agent.targetPart, 16)
		end
		if _G.CombatService and _G.CombatService.ApplyDamage then
			_G.CombatService.ApplyDamage(agent.targetPart, 8, { name = "Microondas Kuroshio-V" }, nil, agent.part.Position)
		end
		print(string.format("[EnemyAIService] %s descargó microondas (+16 calor | -8 HP)", agent.spec.name))
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

	-- ---- ACTUALIZACIÓN COORDINADA DE ESCUADRONES (SQUAD COORDINATOR 10 Hz) ----
	for squadId, squad in pairs(activeSquads) do
		local leaderAlive = false
		if squad.leaderPart and squad.leaderPart.Parent then
			local lAgent = activeAgents[squad.leaderPart]
			if lAgent and lAgent.isAlive then
				leaderAlive = true
				-- Propagar objetivo prioritario del líder a todo el escuadrón
				squad.targetPlayer = lAgent.targetPlayer
				squad.targetPart = lAgent.targetPart
			end
		end

		if not leaderAlive and squad.phase ~= "disarray" then
			-- PÁNICO TÁCTICO / DESBANDADA POR MUERTE DEL LÍDER
			squad.phase = "disarray"
			squad.phaseTimer = 3.5
			print(string.format("[SquadAI] ¡LÍDER ELIMINADO en '%s'! Escuadrón roto en desbandada táctica.", squadId))

			-- Alerta HUD diegética al jugador: formación enemiga rota
			if incomingThreatAlertEvent then
				for _, p in ipairs(Players:GetPlayers()) do
					pcall(function()
						incomingThreatAlertEvent:FireClient(p, {
							threatType = "cleared",
							reason = "¡FORMACIÓN QUEBRADA // LÍDER ELIMINADO!",
						})
					end)
				end
			end

			-- Billboard de miembros supervivientes pasa a pánico desordenado
			for part, member in pairs(squad.members) do
				if part and part.Parent and part ~= squad.leaderPart then
					local tagGui = part:FindFirstChild("EnemyTag")
					local nameLabel = tagGui and tagGui:FindFirstChild("NameLabel") :: TextLabel?
					if nameLabel then
						nameLabel.Text = "⚠️ [EN DESBANDADA] ⚠️"
						nameLabel.TextColor3 = Color3.fromRGB(255, 120, 20)
					end
				end
			end
		end

		if squad.phase == "disarray" then
			squad.phaseTimer -= AI_TICK_RATE
			if squad.phaseTimer <= 0 then
				dissolveSquad(squadId)
			end
		else
			-- Ciclo de fases de la pinza táctica (Pincer State Machine)
			squad.phaseTimer += AI_TICK_RATE
			if squad.phase == "approach" and squad.phaseTimer >= 2.0 then
				squad.phase = "flank_spread"
				squad.phaseTimer = 0
			elseif squad.phase == "flank_spread" and squad.phaseTimer >= 3.0 then
				squad.phase = "converging_strike"
				squad.phaseTimer = 0
			elseif squad.phase == "converging_strike" and squad.phaseTimer >= 2.8 then
				squad.phase = "approach"
				squad.phaseTimer = 0
			end
		end
	end

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
			cleanupTelegraph(agent)
			activeAgents[part] = nil
			continue
		end

		-- Si está aturdido por EMP, deshabilitar motores y aplicar caída física con giro
		if part:FindFirstChild("EMPHighlight") then
			if agent.isCharging then
				cleanupTelegraph(agent, "Amenaza neutralizada")
			end
			agent.velocity = Vector3.new(agent.velocity.X * 0.85, -45, agent.velocity.Z * 0.85)
			part.AssemblyLinearVelocity = agent.velocity
			part.CFrame = part.CFrame * CFrame.Angles(math.rad(AI_TICK_RATE * 90), math.rad(AI_TICK_RATE * 60), 0)
			continue
		end

		-- Si fue desorientado por bengalas térmicas, romper objetivo y evadir
		if part:FindFirstChild("FlaresConfused") then
			if agent.isCharging then
				cleanupTelegraph(agent, "Fijación perdida")
			end
			agent.targetPlayer = nil
			agent.targetPart   = nil
			local steerForce   = (part.CFrame.LookVector + Vector3.new(0, 0.3, 0)).Unit * agent.spec.maxSpeed
			agent.velocity     = agent.velocity:Lerp(steerForce, math.clamp(AI_TICK_RATE * 2, 0, 1))
			part.AssemblyLinearVelocity = agent.velocity
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

		local squad = if agent.squadId then activeSquads[agent.squadId] else nil
		local member = if squad then squad.members[part] else nil

		-- Si el agente no tiene objetivo propio pero el escuadrón sí, sincronizarlo
		if not agent.targetPart and squad and squad.targetPart then
			agent.targetPart = squad.targetPart
			agent.targetPlayer = squad.targetPlayer
		end

		-- ---- CALCULAR STEERING POR MODO / COORDINACIÓN DE ESCUADRÓN ----
		local steerForce = Vector3.zero
		local mode = agent.spec.aggressionMode

		if squad and squad.phase == "disarray" and mode ~= "turret" then
			-- PÁNICO Y DESBANDADA POR BAJA DEL LÍDER: MANIOBRAS ERRÁTICAS EVASIVAS
			local threatPos = if agent.targetPart then agent.targetPart.Position else (agent.homeCenter or part.Position)
			local fleeDir = (part.Position - threatPos)
			local fleeUnit = if fleeDir.Magnitude > 0.1 then fleeDir.Unit else Vector3.yAxis
			local jitter = Vector3.new(
				math.sin(os.clock() * 14 + part.Position.X * 0.1),
				math.sin(os.clock() * 10),
				math.cos(os.clock() * 14 + part.Position.Z * 0.1)
			) * 24
			steerForce = (fleeUnit * agent.spec.maxSpeed * 1.2) + jitter

		elseif squad and member and (member.role == "flanker_left" or member.role == "flanker_right") and agent.targetPart and mode ~= "turret" then
			-- COMPORTAMIENTO TÁCTICO DE PINZA PARA FLANQUEADORES (SQUAD PINCER)
			local targetCF = agent.targetPart.CFrame
			local targetVel = agent.targetPart.AssemblyLinearVelocity
			local side = member.assignedSide

			if squad.phase == "approach" or squad.phase == "flank_spread" then
				-- Fases 1 y 2: Despliegue envolvente lateral en coordenadas relativas a la nave del jugador
				local sideOffset = targetCF.RightVector * (side * 62)
				local rearOffset = -targetCF.LookVector * 18
				local vertOffset = Vector3.new(0, 8, 0)
				local leadPrediction = targetVel * 0.35
				local flankPos = targetCF.Position + sideOffset + rearOffset + vertOffset + leadPrediction

				local sepV = separation(part.Position, gnatParts, 12) * SEPARATION_WEIGHT
				steerForce = arrive(part.Position, flankPos, agent.spec.maxSpeed, 24) + sepV

				local thrusterAtt = part:FindFirstChild("ThrusterAtt")
				local thruster = if thrusterAtt then thrusterAtt:FindFirstChild("ThrusterTrail") :: ParticleEmitter? else nil
				if thruster then
					thruster.Rate = 40
					thruster.Speed = NumberRange.new(8, 16)
				end

			elseif squad.phase == "converging_strike" then
				-- Fase 3: Ataque convergente en tijera (Scissor Dive) escalonado
				if squad.phaseTimer >= member.strikeDelay then
					-- Picado afilado con predicción de trayectoria cortando la vía de escape
					local diveLead = agent.targetPart.Position + (targetVel * 0.30)
					local strikeSpeed = math.max(agent.spec.maxSpeed, 74)
					local seekV = seek(part.Position, diveLead, strikeSpeed)
					local sepV = separation(part.Position, gnatParts, 8) * (SEPARATION_WEIGHT * 0.4)
					steerForce = seekV + sepV

					local thrusterAtt = part:FindFirstChild("ThrusterAtt")
					local thruster = if thrusterAtt then thrusterAtt:FindFirstChild("ThrusterTrail") :: ParticleEmitter? else nil
					if thruster then
						thruster.Rate = 90
						thruster.Speed = NumberRange.new(18, 30)
					end

					if mode == "ramming" then
						handleRamming(agent)
					elseif mode == "orbit" then
						handleFiring(agent)
					end
				else
					-- Retardo escalonado de tijera: aguardar en ángulo lateral antes de picar
					local holdOffset = (targetCF.RightVector * (side * 52)) + Vector3.new(0, 10, 0)
					steerForce = arrive(part.Position, targetCF.Position + holdOffset, agent.spec.maxSpeed, 18)
				end
			end

		elseif mode == "ramming" then
			if agent.targetPart then
				local distToPlayer = (part.Position - agent.targetPart.Position).Magnitude
				local diveSpeed = if distToPlayer <= 70 then 68 else agent.spec.maxSpeed

				-- Acelerar estela de propulsión durante el picado aéreo
				local thrusterAtt = part:FindFirstChild("ThrusterAtt")
				local thruster = if thrusterAtt then thrusterAtt:FindFirstChild("ThrusterTrail") :: ParticleEmitter? else nil
				if thruster then
					thruster.Rate = if distToPlayer <= 70 then 80 else 25
					thruster.Speed = if distToPlayer <= 70 then NumberRange.new(16, 28) else NumberRange.new(5, 12)
				end

				-- Seek agresivo hacia el dron del jugador + separación enjambre (flocking)
				local seekV = seek(part.Position, agent.targetPart.Position, diveSpeed)
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
			local laserSight = part:FindFirstChild("LaserSight") :: BasePart?
			if agent.targetPart then
				local toTarget = (agent.targetPart.Position - part.Position)
				if toTarget.Magnitude > 0 then
					local targetCF = CFrame.lookAt(part.Position, agent.targetPart.Position)
					part.CFrame = part.CFrame:Lerp(targetCF, 0.28)
				end
				-- Raycast físico del láser para que colisione con torres y no las atraviese
				local lOrigin = part.Position
				local lDir = part.CFrame.LookVector * 70
				local lParams = RaycastParams.new()
				lParams.FilterType = Enum.RaycastFilterType.Exclude
				lParams.FilterDescendantsInstances = { part, agentFolder }
				local lHit = Workspace:Raycast(lOrigin, lDir, lParams)

				local actualDist = if lHit then (lHit.Position - lOrigin).Magnitude else 70
				local hitPoint = if lHit then lHit.Position else (lOrigin + lDir)

				-- Alerta visual de pre-fijado: haz láser se torna rojo carmesí brillante e intenso
				if laserSight then
					laserSight.Color = Color3.fromRGB(255, 30, 30)
					laserSight.Transparency = 0.15
					laserSight.Size = Vector3.new(0.35, 0.35, actualDist)
					laserSight.CFrame = CFrame.lookAt(lOrigin, hitPoint) * CFrame.new(0, 0, -actualDist / 2)
				end
				handleFiring(agent)
			else
				-- Barrido rotativo suave de vigilancia de 360° en reposo con colisión de láser
				part.CFrame = part.CFrame * CFrame.Angles(0, math.rad(AI_TICK_RATE * 35), 0)
				local lOrigin = part.Position
				local lDir = part.CFrame.LookVector * 50
				local lParams = RaycastParams.new()
				lParams.FilterType = Enum.RaycastFilterType.Exclude
				lParams.FilterDescendantsInstances = { part, agentFolder }
				local lHit = Workspace:Raycast(lOrigin, lDir, lParams)

				local actualDist = if lHit then (lHit.Position - lOrigin).Magnitude else 50
				local hitPoint = if lHit then lHit.Position else (lOrigin + lDir)

				if laserSight then
					laserSight.Color = Color3.fromRGB(255, 180, 0)
					laserSight.Transparency = 0.50
					laserSight.Size = Vector3.new(0.2, 0.2, actualDist)
					laserSight.CFrame = CFrame.lookAt(lOrigin, hitPoint) * CFrame.new(0, 0, -actualDist / 2)
				end
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

			-- Limitar a velocidad máxima (con soporte de picado dinámico para Scav-Gnats y Tijera)
			local effectiveMaxSpeed = agent.spec.maxSpeed
			if squad and squad.phase == "converging_strike" and member and squad.phaseTimer >= member.strikeDelay then
				effectiveMaxSpeed = 74
			elseif mode == "ramming" and agent.targetPart then
				local distToPlayer = (part.Position - agent.targetPart.Position).Magnitude
				if distToPlayer <= 70 then
					effectiveMaxSpeed = 68
				end
			end

			if agent.velocity.Magnitude > effectiveMaxSpeed then
				agent.velocity = agent.velocity.Unit * effectiveMaxSpeed
			end

			agent.linearVelocity.VectorVelocity = agent.velocity

			-- Orientar hacia la dirección de movimiento o fijar morro en picado hacia el objetivo
			if agent.velocity.Magnitude > 2 then
				local lookDir = if (mode == "ramming" and agent.targetPart)
					then (agent.targetPart.Position - part.Position).Unit
					else agent.velocity.Unit

				agent.alignOrient.CFrame = CFrame.lookAt(Vector3.zero, lookDir, Vector3.yAxis)
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
		center = Vector3.new(300, 115, -340),
		activationRadius = 380,
		deactivationRadius = 900,
		respawnCooldown = 35,
		lastClearedTime = 0,
		archetypes = {
			-- Líder de escuadrón Scav-Gnat alfa con mayor dureza y agresividad (más rayitas de vida)
			{ specId = "scav_gnats", offset = Vector3.new(0, 14, 0),    difficulty = 0.50 },
			-- Flanqueadores laterales en pinza
			{ specId = "scav_gnats", offset = Vector3.new(-22, 10, 18), difficulty = 0.15 },
			{ specId = "scav_gnats", offset = Vector3.new(22, 12, -18), difficulty = 0.15 },
			-- Explorador de reserva / flanqueo secundario
			{ specId = "scav_gnats", offset = Vector3.new(-45, -15, 45), difficulty = 0.10 },
		},
		activeParts = {},
		isActive = false,
	},
	Zone_TorreB = {
		id = "Zone_TorreB",
		name = "Sector Black Ops (Torre B)",
		threatLevel = "black_ops",
		center = Vector3.new(-360, 65, 260),
		activationRadius = 380,
		deactivationRadius = 900,
		respawnCooldown = 45,
		lastClearedTime = 0,
		archetypes = {
			-- Torreta Aegis asentada firmemente sobre la cornisa de la azotea de Torre B (Y = 67.5) con telegrafiado láser
			{ specId = "aegis_44",       offset = Vector3.new(14, 2.5, 14), difficulty = 0.25 },
			-- Interceptor orbital Kuroshio patrullando en órbita alta (Y = 95)
			{ specId = "kuroshio_v",     offset = Vector3.new(-15, 28, 15), difficulty = 0.35 },
			-- Dron pesado Baluarte con Escudo Frontal Hexagonal de Energía (Aegis-Bulwark, Líder de Escuadrón)
			{ specId = "aegis_bulwark",  offset = Vector3.new(22, 16, -22), difficulty = 0.30 },
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

	local spawnedAgents: { EnemyAgent } = {}
	for _, arch in ipairs(zone.archetypes) do
		local spawnPos = zone.center + arch.offset
		local part = EnemyAIService_Spawn(arch.specId, spawnPos, arch.difficulty, zone.id)
		if part then
			table.insert(zone.activeParts, part)
			local ag = activeAgents[part]
			if ag then
				table.insert(spawnedAgents, ag)
			end
		end
	end

	-- FORMAR ESCUADRÓN TÁCTICO EN PINZA SI HAY UNIDADES MÓVILES
	local mobileAgents: { EnemyAgent } = {}
	for _, ag in ipairs(spawnedAgents) do
		if ag.spec.aggressionMode ~= "turret" then
			table.insert(mobileAgents, ag)
		end
	end

	if #mobileAgents >= 2 then
		-- Priorizar como líder al más resistente (mayor maxHealth)
		table.sort(mobileAgents, function(a, b)
			return a.spec.maxHealth > b.spec.maxHealth
		end)
		local leader = mobileAgents[1]
		local flankers: { EnemyAgent } = {}
		for i = 2, #mobileAgents do
			table.insert(flankers, mobileAgents[i])
		end
		createSquad("Squad_" .. zone.id, leader, flankers)
	end

	print(string.format("[ThreatDirector] ¡Zona '%s' ACTIVADA! %d unidades hostiles patrullando.", zone.name, #zone.activeParts))
end

local function deactivateZone(zone: ThreatZone)
	if not zone.isActive then return end
	zone.isActive = false

	dissolveSquad("Squad_" .. zone.id)

	for _, part in ipairs(zone.activeParts) do
		if part and part.Parent then
			local agent = activeAgents[part]
			if agent then cleanupTelegraph(agent) end
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

