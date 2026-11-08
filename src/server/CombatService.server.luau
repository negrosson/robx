--!strict
-- src/server/CombatService.server.luau
-- Servicio de Combate Server-Side — Validación de Impactos, Gestión Térmica y EMP
-- Cyber Delivery Tycoon — Autoridad física 100% en el servidor
print("[CombatService] Iniciando servicio de combate...")

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Debris            = game:GetService("Debris")
local Workspace         = game:GetService("Workspace")
local TweenService      = game:GetService("TweenService")

-- Módulos compartidos (src/shared/ → ReplicatedStorage)
local DroneWeaponsModule = (ReplicatedStorage:FindFirstChild("DroneWeapons") or ReplicatedStorage:WaitForChild("DroneWeapons", 30)) :: ModuleScript
local DroneWeapons = require(DroneWeaponsModule)

----------------------------------------------------------------------
-- CONSTANTES
----------------------------------------------------------------------
local MAX_HEAT_THRESHOLD   = 100  -- % a partir del cual se activa EMP
local EMP_DURATION         = 2.0  -- segundos en caída libre tras sobrecalentamiento
local DOT_TICK_RATE        = 0.5  -- segundos entre ticks de daño térmico continuo
local IMPULSE_DECAY        = 0.6  -- duración en s del desestabilizador de orientación
local EXPLOSION_RADIUS_SCALE = 0.15  -- radio de explosión = daño * escala

-- Tabla de drones activos rastreados por el servidor {[BasePart]: DroneState}
type DroneState = {
	part           : BasePart,
	health         : number,
	maxHealth      : number,
	heat           : number,
	maxHeat        : number,
	heatCoolingRate: number,
	armorReduction : number,
	empResistance  : number,
	isEMPed        : boolean,
	empEndTime     : number,
	dotEndTime     : number,
	dotDamage      : number,
	liftReduction  : number,
	liftEndTime    : number,
	owner          : Player?,
	bounty         : number?,
	lastAttacker   : Player?,
}

local activeDrones: { [BasePart]: DroneState } = {}

----------------------------------------------------------------------
-- RemoteEvents (Garantizados de forma inmediata y segura)
----------------------------------------------------------------------
local NetworkEventsModule = ReplicatedStorage:WaitForChild("NetworkEvents", 10) :: ModuleScript
local NetworkEvents = require(NetworkEventsModule)
NetworkEvents.Init()

local function ensureRemote(name: string): RemoteEvent
	return NetworkEvents.Get(name)
end

-- Cliente → Servidor: Solicitar disparo validado
local onFireWeaponEvent     = ensureRemote(NetworkEvents.Names.OnFireWeapon)
-- Servidor → Cliente: Notificar daño recibido (HUD)
local onDamagedEvent        = ensureRemote(NetworkEvents.Names.OnDamageTaken)
-- Servidor → Cliente: Notificar estado EMP
local onEMPEvent            = ensureRemote(NetworkEvents.Names.OnEMPActivated)
-- Servidor → Cliente: Actualizar datos de calor para HUD
local onHeatUpdateEvent     = ensureRemote(NetworkEvents.Names.OnHeatUpdate)
-- Servidor → Cliente: Recompensa de caza
local onBountyEvent         = ensureRemote(NetworkEvents.Names.OnBountyAwarded)
local flightStateEvent      = ensureRemote(NetworkEvents.Names.DroneFlightState)
local droneDestroyedEvent   = ensureRemote(NetworkEvents.Names.DroneDestroyed)

----------------------------------------------------------------------
-- API PÚBLICA — Registrar un dron en el sistema de combate
----------------------------------------------------------------------
function CombatService_Register(
	part          : BasePart,
	maxHealth     : number,
	maxHeat       : number,
	heatCooling   : number,
	armorReduction: number,
	empResistance : number,
	owner         : Player?,
	bounty        : number?
)
	activeDrones[part] = {
		part           = part,
		health         = maxHealth,
		maxHealth      = maxHealth,
		heat           = 0,
		maxHeat        = maxHeat,
		heatCoolingRate = heatCooling,
		armorReduction = armorReduction,
		empResistance  = empResistance,
		isEMPed        = false,
		empEndTime     = 0,
		dotEndTime     = 0,
		dotDamage      = 0,
		liftReduction  = 0,
		liftEndTime    = 0,
		owner          = owner,
		bounty         = bounty,
		lastAttacker   = nil,
	}
	print(string.format("[CombatService] Dron registrado: %s (HP:%d / Heat:%d / Bounty:%s)", part.Name, maxHealth, maxHeat, tostring(bounty or 0)))
end

function CombatService_Unregister(part: BasePart)
	activeDrones[part] = nil
end

----------------------------------------------------------------------
-- LÓGICA INTERNA
----------------------------------------------------------------------

-- Verifica línea de visión estricta entre dos posiciones contra torres y obstáculos del mundo
local function hasLineOfSight(origin: Vector3, target: Vector3, exclude: { Instance }, targetPart: BasePart?): (boolean, Vector3, BasePart?)
	local curOrigin = origin
	local totalVec = target - origin
	local totalDist = totalVec.Magnitude
	if totalDist < 0.1 then
		return true, target, targetPart
	end

	local dir = totalVec.Unit
	local remainingDist = totalDist
	local localExclude = table.clone(exclude)

	local maxSteps = 6
	while remainingDist > 0.1 and maxSteps > 0 do
		maxSteps -= 1
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = localExclude

		local result = Workspace:Raycast(curOrigin, dir * remainingDist, params)
		if not result then
			return true, target, targetPart
		end

		local hitInstance = result.Instance
		if not hitInstance or not hitInstance:IsA("BasePart") then
			return true, target, targetPart
		end

		-- Si impactó directamente en el objetivo o sus hijos
		if hitInstance == targetPart or (targetPart and hitInstance:IsDescendantOf(targetPart)) then
			return true, result.Position, hitInstance
		end

		-- Si impactó un efecto cosmético inmaterial (haces de luz, partículas, rayos visuales)
		local name = hitInstance.Name
		if name == "HoloSkyBeam" or name == "LaserSight" or name == "LocalPlasmaBolt" 
			or name == "ServerPlasmaBolt" or name == "MicrowavePulse" or name == "MicrowaveCore"
			or name == "GaussTracer" or name == "AccentBand" or name == "CommAntenna" then
			table.insert(localExclude, hitInstance)
			curOrigin = result.Position + dir * 0.1
			remainingDist = (target - curOrigin).Magnitude
		else
			-- ¡Impacto contra un obstáculo sólido (torre, rascacielos, pilar, base, helipuerto, terreno)!
			return false, result.Position, hitInstance
		end
	end

	return true, target, targetPart
end

-- Genera explosión física al destruir un dron
local function destroyDrone(state: DroneState, killerPlayer: Player?)
	local part = state.part
	if not part or not part.Parent then return end

	local explosion = Instance.new("Explosion")
	explosion.Position       = part.Position
	explosion.BlastRadius    = 12
	explosion.BlastPressure  = 3e5
	explosion.DestroyJointRadiusPercent = 0  -- no destruye el mundo, solo aplica fuerza
	explosion.ExplosionType  = Enum.ExplosionType.NoCraters
	explosion.Parent         = Workspace
	Debris:AddItem(explosion, 3)

	if state.owner then
		-- Dron del jugador: NO destruir TestDrone físicamente; resetear a Base Central de forma atómica
		print(string.format("[CombatService] ¡DRON DESTRUIDO! Reseteando dron y piloto %s a Base Central.", state.owner.Name))
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
		part.Anchored = true
		part.CFrame = CFrame.new(0, 6.2, 0)
		state.health = state.maxHealth
		state.heat = 0
		state.isEMPed = false

		-- Reactivar ProximityPrompt diegético en el servidor
		local prompt = part:FindFirstChild("PilotPrompt") :: ProximityPrompt?
		if prompt then
			prompt.Enabled = true
		end

		-- Devolver propiedad física al servidor para evitar desincronizaciones de red
		pcall(function()
			part:SetNetworkOwnershipAuto()
		end)

		-- Teletransportar al personaje del piloto de vuelta a la estación de control en Base Central
		local char = state.owner.Character
		if char then
			local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				hrp.AssemblyLinearVelocity = Vector3.zero
				hrp.AssemblyAngularVelocity = Vector3.zero
				hrp.CFrame = CFrame.new(0, 6.5, 14) * CFrame.Angles(0, math.rad(180), 0)
			end
		end

		-- Notificar al jugador con evento de daño y eventos dedicados de desconexión / destrucción
		onDamagedEvent:FireClient(state.owner, {
			damage    = 0,
			rawDamage = 0,
			weapon    = "DESTRUIDO // RESPAWN EN BASE",
			healthPct = 1.0,
			isDestroyed = true,
		})

		if droneDestroyedEvent then
			droneDestroyedEvent:FireClient(state.owner)
		end

		if flightStateEvent then
			flightStateEvent:FireClient(state.owner, "StopFlying")
		end
	else
		-- Dron enemigo: otorgar recompensa en PELAOCOINS al killerPlayer / atacante
		local killer = killerPlayer or state.lastAttacker
		if killer and killer:IsA("Player") then
			local bounty = state.bounty or (part:GetAttribute("Bounty") :: number?)
			if not bounty or bounty <= 0 then
				if string.find(part.Name, "scav_gnats") then
					bounty = 35
				elseif string.find(part.Name, "aegis_44") then
					bounty = 80
				elseif string.find(part.Name, "kuroshio_v") then
					bounty = 120
				else
					bounty = 35
				end
			end

			local leaderstats = killer:FindFirstChild("leaderstats")
			if leaderstats then
				local coins = leaderstats:FindFirstChild("PELAOCOINS") :: IntValue?
				if coins then
					coins.Value += bounty
					print(string.format("[CombatService] Recompensa de %d PELAOCOINS acreditada a %s", bounty, killer.Name))
				end
			end

			-- Notificar al HUD del jugador
			pcall(function()
				onBountyEvent:FireClient(killer, {
					bounty = bounty,
					targetName = part.Name,
				})
			end)
		end

		-- Retirar del registro y destruir la parte física tras breve pausa
		print(string.format("[CombatService] Dron enemigo neutralizado: %s", part.Name))
		activeDrones[part] = nil
		task.delay(0.4, function()
			if part and part.Parent then
				part:Destroy()
			end
		end)
	end
end

-- Activa estado EMP: deshabilita LinearVelocity del dron 2 segundos
local function triggerEMP(state: DroneState)
	state.isEMPed  = true
	state.empEndTime = os.clock() + EMP_DURATION
	state.heat     = state.maxHeat  -- fijar al máximo

	local part = state.part
	if not part or not part.Parent then return end

	local lv = part:FindFirstChild("FlightVelocity") :: LinearVelocity?
	local ao = part:FindFirstChild("FlightOrientation") :: AlignOrientation?

	if lv then lv.Enabled = false end
	if ao then ao.Enabled = false end

	-- Notificar cliente del EMP
	if state.owner then
		onEMPEvent:FireClient(state.owner, EMP_DURATION)
	end

	print(string.format("[CombatService] EMP activado en %s — caída libre %.1fs", part.Name, EMP_DURATION))

	task.delay(EMP_DURATION, function()
		if activeDrones[part] then
			state.isEMPed = false
			state.heat    = state.maxHeat * 0.8  -- calor residual al recuperarse
			if lv and lv.Parent then lv.Enabled = true end
			if ao and ao.Parent then ao.Enabled = true end
			print(string.format("[CombatService] Sistemas restaurados en %s", part.Name))
		end
	end)
end

-- Aplica daño a un DroneState con mitigación de blindaje
local function applyDamage(state: DroneState, rawDamage: number, weaponSpec: any, attackerPlayer: Player?, sourcePos: Vector3?)
	if attackerPlayer then
		state.lastAttacker = attackerPlayer
	end

	local mitigation = math.clamp(state.armorReduction, 0, 0.90)
	local finalDmg = math.max(1, rawDamage * (1 - mitigation))
	state.health = math.max(0, state.health - finalDmg)

	-- Notificar al dueño del dron con posición del atacante para HUD direccional
	if state.owner then
		local pos = sourcePos
		if not pos and attackerPlayer and attackerPlayer.Character and attackerPlayer.Character.PrimaryPart then
			pos = attackerPlayer.Character.PrimaryPart.Position
		end

		onDamagedEvent:FireClient(state.owner, {
			damage           = finalDmg,
			rawDamage        = rawDamage,
			weapon           = weaponSpec and weaponSpec.name or "Hostil",
			healthPct        = state.health / state.maxHealth,
			attackerPosition = pos,
		})
	end

	-- Destruir dron al llegar a 0 HP
	if state.health <= 0 then
		destroyDrone(state, attackerPlayer)
	end
end

-- Aplica calor al dron, considera resistencia EMP
local function applyHeat(state: DroneState, rawHeat: number)
	local resistance = math.clamp(state.empResistance, 0, 0.90)
	local effectiveHeat = rawHeat * (1 - resistance)
	state.heat = math.min(state.maxHeat, state.heat + effectiveHeat)

	-- Verificar umbral EMP
	local heatPct = state.heat / state.maxHeat * 100
	if heatPct >= MAX_HEAT_THRESHOLD and not state.isEMPed then
		triggerEMP(state)
	end

	-- Notificar HUD de calor
	if state.owner then
		onHeatUpdateEvent:FireClient(state.owner, state.heat / state.maxHeat)
	end
end

----------------------------------------------------------------------
-- MANEJADOR DE DISPARO (Cliente → Servidor)
----------------------------------------------------------------------
-- Formato del request: { weaponId, originCFrame, targetPosition, targetPart? }
onFireWeaponEvent.OnServerEvent:Connect(function(player: Player, request: any)
	if typeof(request) ~= "table" then return end

	local weaponId      = request.weaponId
	local originPos     = request.origin        -- Vector3
	local targetPos     = request.target        -- Vector3
	local targetPart    = request.targetPart    -- BasePart? (opcional)

	if typeof(weaponId) ~= "string" then return end
	if typeof(originPos) ~= "Vector3" then return end
	if typeof(targetPos) ~= "Vector3" then return end

	local weaponSpec = DroneWeapons.ById[weaponId]
	if not weaponSpec then
		warn("[CombatService] Arma desconocida:", weaponId)
		return
	end

	-- 1. Validar distancia máxima (anti-exploit de rango)
	local distance = (targetPos - originPos).Magnitude
	if distance > weaponSpec.range * 1.1 then  -- 10% de tolerancia de red
		warn(string.format("[CombatService ANTI-EXPLOIT] %s disparó fuera de rango (%.0f > %.0f studs)", player.Name, distance, weaponSpec.range))
		return
	end

	-- 2. Validar línea de visión y colisión estricta con obstáculos (torres, rascacielos, bases)
	local shooterDrone: BasePart? = nil
	for part, state in pairs(activeDrones) do
		if state.owner == player then
			shooterDrone = part
			break
		end
	end

	local excludeList: { Instance } = {}
	if shooterDrone then table.insert(excludeList, shooterDrone) end
	local char = player.Character
	if char then table.insert(excludeList, char) end

	local hasLOS, actualHitPos, hitObstacle = hasLineOfSight(originPos, targetPos, excludeList, targetPart)
	local finalTargetPos = actualHitPos or targetPos

	if not hasLOS then
		-- El disparo impactó contra una torre o estructura sólida; no impacta al objetivo
		targetPart = nil
	end

	-- 3. Aplicar calor al PORTADOR
	if shooterDrone then
		local shooterState = activeDrones[shooterDrone]
		if shooterState then
			applyHeat(shooterState, weaponSpec.heatGenerated)
		end
	end

	-- 4. Adquisición de objetivo y raycast fallback en servidor (solo si hay LOS)
	if hasLOS and (not targetPart or not targetPart:IsA("BasePart")) then
		local rayDir = (finalTargetPos - originPos).Unit * math.min(distance + 5, weaponSpec.range)
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = excludeList

		local rayHit = Workspace:Raycast(originPos, rayDir, rayParams)
		if rayHit and rayHit.Instance then
			local hitPart = rayHit.Instance
			if activeDrones[hitPart] then
				targetPart = hitPart
				finalTargetPos = rayHit.Position
			else
				local enemyFolder = Workspace:FindFirstChild("EnemyDrones")
				if enemyFolder and hitPart:IsDescendantOf(enemyFolder) then
					local potential = if hitPart.Parent == enemyFolder then hitPart else hitPart.Parent
					if potential and potential:IsA("BasePart") and activeDrones[potential] then
						targetPart = potential
					elseif hitPart:IsA("BasePart") and activeDrones[hitPart] then
						targetPart = hitPart
					end
					finalTargetPos = rayHit.Position
				end
			end
		end
	end

	-- 5. Proyectil visible en servidor (Plasma Bolt para magma_spike y armas de proyectil)
	if weaponSpec.projectileSpeed > 0 and weaponSpec.damageType ~= "missile" then
		local bolt = Instance.new("Part")
		bolt.Name = "ServerPlasmaBolt"
		bolt.Size = Vector3.new(0.6, 0.6, 2.2)
		bolt.Material = Enum.Material.Neon
		bolt.Color = weaponSpec.projectileColor or Color3.fromRGB(255, 100, 0)
		bolt.CanCollide = false
		bolt.CastShadow = false
		bolt.Massless = true
		bolt.CFrame = CFrame.lookAt(originPos, finalTargetPos)
		bolt.Parent = Workspace
		Debris:AddItem(bolt, 3)

		local boltFlightDist = (finalTargetPos - originPos).Magnitude
		local flightDuration = math.clamp(boltFlightDist / weaponSpec.projectileSpeed, 0.05, 2.5)
		local tween = TweenService:Create(
			bolt,
			TweenInfo.new(flightDuration, Enum.EasingStyle.Linear),
			{ CFrame = CFrame.lookAt(finalTargetPos, finalTargetPos + (finalTargetPos - originPos).Unit) }
		)
		tween:Play()
		tween.Completed:Connect(function()
			if bolt.Parent then
				-- Destello e impacto en la superficie (torre o dron)
				local flash = Instance.new("Part")
				flash.Shape = Enum.PartType.Ball
				flash.Size = if not hasLOS then Vector3.new(2.4, 2.4, 2.4) else Vector3.new(1.6, 1.6, 1.6)
				flash.Material = Enum.Material.Neon
				flash.Color = if not hasLOS then Color3.fromRGB(255, 170, 30) else bolt.Color
				flash.Position = finalTargetPos
				flash.CanCollide = false
				flash.Anchored = true
				flash.Parent = Workspace
				Debris:AddItem(flash, 0.14)
				bolt:Destroy()
			end
		end)
	end

	-- 6. Procesar impacto en el objetivo
	if targetPart and typeof(targetPart) == "Instance" and targetPart:IsA("BasePart") then
		local targetState = activeDrones[targetPart]
		if not targetState and targetPart.Parent and targetPart.Parent:IsA("BasePart") then
			targetState = activeDrones[targetPart.Parent]
		end

		if targetState then
			-- Calcular daño con blindaje y asociar atacante para recompensas
			applyDamage(targetState, weaponSpec.damage, weaponSpec, player)

			-- Calor en el objetivo
			applyHeat(targetState, weaponSpec.heatOnTarget)

			-- Efectos secundarios
			local now = os.clock()
			for _, effect in ipairs(weaponSpec.effects) do
				if effect.type == "dot" then
					targetState.dotDamage  = effect.value
					targetState.dotEndTime = now + effect.duration

				elseif effect.type == "lift_reduction" then
					targetState.liftReduction = effect.value
					targetState.liftEndTime   = now + effect.duration

				elseif effect.type == "impulse" then
					-- Aplicar impulso físico para desestabilizar AlignOrientation
					local ao = targetPart:FindFirstChild("FlightOrientation") :: AlignOrientation?
					if ao then
						ao.Enabled = false
						local impactDir = (targetPart.Position - originPos).Unit
						targetPart.AssemblyLinearVelocity += impactDir * effect.value
						task.delay(IMPULSE_DECAY, function()
							if ao and ao.Parent then ao.Enabled = true end
						end)
					end

				elseif effect.type == "heat_inject" then
					applyHeat(targetState, effect.value)

				elseif effect.type == "emp" and targetState.heat >= targetState.maxHeat then
					triggerEMP(targetState)
				end
			end
		end
	end

	-- 7. Misil: generar proyectil físico en el servidor
	if weaponSpec.damageType == "missile" and weaponSpec.projectileSpeed > 0 then
		local missileVFX = Instance.new("Part")
		missileVFX.Name        = "CyberMissile"
		missileVFX.Size        = Vector3.new(0.3, 0.3, 1.5)
		missileVFX.Material    = Enum.Material.Neon
		missileVFX.Color       = weaponSpec.projectileColor
		missileVFX.CanCollide  = false
		missileVFX.Massless    = true
		missileVFX.CFrame      = CFrame.lookAt(originPos, targetPos)
		missileVFX.Parent      = Workspace
		Debris:AddItem(missileVFX, 4)

		-- Mover hacia el objetivo (guiado simple, Bézier en cliente para VFX)
		local startPos = originPos
		local endPos   = targetPos
		local duration = distance / weaponSpec.projectileSpeed
		local elapsed  = 0

		local conn: RBXScriptConnection
		conn = RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			local t = math.clamp(elapsed / duration, 0, 1)

			-- Curva Bézier cuadrática con punto de control elevado
			local ctrl = (startPos + endPos) / 2 + Vector3.new(0, 15, 0)
			local pos = (1 - t)^2 * startPos + 2*(1-t)*t * ctrl + t^2 * endPos
			missileVFX.CFrame = CFrame.lookAt(pos, endPos)

			if t >= 1 then
				conn:Disconnect()
				-- Detonar al llegar
				local exp = Instance.new("Explosion")
				exp.Position      = endPos
				exp.BlastRadius   = 15
				exp.BlastPressure = 2e5
				exp.DestroyJointRadiusPercent = 0
				exp.Parent = Workspace
				Debris:AddItem(exp, 2)
				if missileVFX.Parent then missileVFX:Destroy() end
			end
		end)
	end
end)

----------------------------------------------------------------------
-- CONTRAMEDIDA EMP [C] (Cliente → Servidor)
----------------------------------------------------------------------
local playerLastEMP: { [Player]: number } = {}
local EMP_COUNTERMEASURE_COOLDOWN = 10.0
local EMP_COUNTERMEASURE_RADIUS = 60.0
local EMP_STUN_DURATION = 3.0

onEMPEvent.OnServerEvent:Connect(function(player: Player)
	local now = os.clock()
	local lastTime = playerLastEMP[player] or 0
	if now - lastTime < EMP_COUNTERMEASURE_COOLDOWN then
		return
	end
	playerLastEMP[player] = now

	-- Localizar el dron del jugador
	local shooterDrone: BasePart? = nil
	for part, state in pairs(activeDrones) do
		if state.owner == player then
			shooterDrone = part
			break
		end
	end

	if not shooterDrone or not shooterDrone.Parent then return end
	local centerPos = shooterDrone.Position

	print(string.format("[CombatService] %s activó contramedida de pulso EMP en %s", player.Name, tostring(centerPos)))

	-- 1. Efecto visual de onda esférica cyan en el servidor (replicado)
	local shockwave = Instance.new("Part")
	shockwave.Name = "EMPShockwave"
	shockwave.Shape = Enum.PartType.Ball
	shockwave.Size = Vector3.new(2, 2, 2)
	shockwave.Position = centerPos
	shockwave.Material = Enum.Material.Neon
	shockwave.Color = Color3.fromRGB(0, 255, 230) -- Neon Cyan
	shockwave.Transparency = 0.35
	shockwave.CanCollide = false
	shockwave.Anchored = true
	shockwave.CastShadow = false
	shockwave.Parent = Workspace
	Debris:AddItem(shockwave, 1.0)

	local waveLight = Instance.new("PointLight")
	waveLight.Color = Color3.fromRGB(0, 255, 230)
	waveLight.Brightness = 8
	waveLight.Range = EMP_COUNTERMEASURE_RADIUS
	waveLight.Parent = shockwave

	local expandTween = TweenService:Create(
		shockwave,
		TweenInfo.new(0.65, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
		{
			Size = Vector3.new(EMP_COUNTERMEASURE_RADIUS * 2, EMP_COUNTERMEASURE_RADIUS * 2, EMP_COUNTERMEASURE_RADIUS * 2),
			Transparency = 1.0,
		}
	)
	expandTween:Play()

	-- 2. Localizar y deshabilitar enemigos en el radio
	local affectedCount = 0
	for part, state in pairs(activeDrones) do
		if state.owner == nil and part and part.Parent then
			local dist = (part.Position - centerPos).Magnitude
			if dist <= EMP_COUNTERMEASURE_RADIUS then
				affectedCount += 1
				local lv = part:FindFirstChild("FlightVelocity") :: LinearVelocity?
				local ao = part:FindFirstChild("FlightOrientation") :: AlignOrientation?
				if lv then lv.Enabled = false end
				if ao then ao.Enabled = false end

				local hl = Instance.new("Highlight")
				hl.Name = "EMPHighlight"
				hl.FillColor = Color3.fromRGB(0, 255, 230)
				hl.FillTransparency = 0.4
				hl.OutlineColor = Color3.fromRGB(255, 255, 255)
				hl.OutlineTransparency = 0.1
				hl.Adornee = part
				hl.Parent = part
				Debris:AddItem(hl, EMP_STUN_DURATION)

				task.delay(EMP_STUN_DURATION, function()
					if part and part.Parent and activeDrones[part] then
						if lv and lv.Parent then lv.Enabled = true end
						if ao and ao.Parent then ao.Enabled = true end
					end
				end)
			end
		end
	end

	print(string.format("[CombatService] Pulso EMP completado: %d enemigos paralizados durante %.1fs", affectedCount, EMP_STUN_DURATION))
end)

----------------------------------------------------------------------
-- BUCLE DE SIMULACIÓN — Actualiza DoT, enfriamiento y EMP a ~20 Hz
----------------------------------------------------------------------
local SIMULATION_RATE = 0.05  -- 20 Hz
local accumulator = 0

RunService.Heartbeat:Connect(function(dt: number)
	accumulator += dt
	if accumulator < SIMULATION_RATE then return end
	accumulator = 0

	local now = os.clock()

	for part, state in pairs(activeDrones) do
		-- Verificar que la part sigue existiendo
		if not part or not part.Parent then
			activeDrones[part] = nil
			continue
		end

		-- 1. Enfriamiento natural de calor
		if state.heat > 0 and not state.isEMPed then
			state.heat = math.max(0, state.heat - state.heatCoolingRate * SIMULATION_RATE)
			if state.owner then
				onHeatUpdateEvent:FireClient(state.owner, state.heat / state.maxHeat)
			end
		end

		-- 2. Daño continuo (DoT térmico)
		if now < state.dotEndTime and state.dotDamage > 0 then
			applyDamage(state, state.dotDamage * SIMULATION_RATE, nil)
		end

		-- 3. Expirar reducción de sustentación
		if now >= state.liftEndTime then
			state.liftReduction = 0
		end

		-- 4. Expirar EMP (ya manejado con task.delay, esto es seguridad extra)
		if state.isEMPed and now >= state.empEndTime then
			state.isEMPed = false
		end
	end
end)

----------------------------------------------------------------------
-- EXPONER API GLOBALMENTE PARA EnemyAIService
----------------------------------------------------------------------
-- (En Roblox, los scripts de servidor se comunican directamente por referencia de módulo,
--  pero CombatService es un Script, no un ModuleScript. Usamos _G como bus interno de servidor.)
_G.CombatService = {
	Register   = CombatService_Register,
	Unregister = CombatService_Unregister,
	ApplyDamage = function(part: BasePart, damage: number, attackerPlayer: Player?, sourcePos: Vector3?)
		local state = activeDrones[part]
		if state then applyDamage(state, damage, nil, attackerPlayer, sourcePos) end
	end,
	ApplyHeat = function(part: BasePart, heat: number)
		local state = activeDrones[part]
		if state then applyHeat(state, heat) end
	end,
	GetLiftReduction = function(part: BasePart): number
		local state = activeDrones[part]
		if state then return state.liftReduction end
		return 0
	end,
	GetHeatPct = function(part: BasePart): number
		local state = activeDrones[part]
		if state then return state.heat / state.maxHeat end
		return 0
	end,
	IsEMPed = function(part: BasePart): boolean
		local state = activeDrones[part]
		if state then return state.isEMPed end
		return false
	end,
}

-- Registro retrospectivo de cualquier enemigo ya instanciado en Workspace.EnemyDrones
task.defer(function()
	local folder = Workspace:FindFirstChild("EnemyDrones")
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("BasePart") and not activeDrones[child] then
				local bounty = child:GetAttribute("Bounty") or 35
				CombatService_Register(child, 100, 100, 10, 0.1, 0.2, nil, bounty)
			end
		end
	end
end)

print("[CombatService] Servicio de combate activo. Esperando conexiones...")

