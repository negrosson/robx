--!strict
-- src/shared/DroneController.luau
-- v4.0 - Vuelo físico con inercia suave, requires LAZY dentro de new()
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")

-- ContextActionService eliminado (causaba conflictos con el character controller)

local DroneController = {}
DroneController.__index = DroneController

----------------------------------------------------------------------
-- TIPOS
----------------------------------------------------------------------
export type DroneConfig = {
	cruiseSpeed         : number,
	turboSpeed          : number,
	verticalSpeed       : number,
	-- Tasas de interpolación (Lerp alpha por segundo)
	accelRate           : number,  -- al presionar tecla
	decelRate           : number,  -- al soltar tecla
	brakeRate           : number,  -- al presionar X (airbrake)
	vertAccelRate       : number,
	vertDecelRate       : number,
	tiltAngle           : number,
	tiltSpeed           : number,
	baseFOV             : number,
	maxFOV              : number,
	mouseSensitivity    : number?,
}

export type InputState = {
	forward   : boolean,
	backward  : boolean,
	left      : boolean,
	right     : boolean,
	up        : boolean,
	down      : boolean,
	turbo     : boolean,
	brake     : boolean,
	turnLeft  : boolean,
	turnRight : boolean,
}

----------------------------------------------------------------------
-- CONFIG POR DEFECTO
-- cruiseSpeed = velocidad máxima crucero (studs/s)
-- accelRate   = qué tan rápido LLEGA a esa velocidad (Lerp factor/s)
--               1.0 = llega en ~1s, 0.3 = llega en ~3s (más suave)
----------------------------------------------------------------------
local DEFAULT_CONFIG: DroneConfig = {
	cruiseSpeed      = 60,    -- velocidad crucero
	turboSpeed       = 110,   -- velocidad turbo (Q)
	verticalSpeed    = 35,    -- velocidad subir/bajar
	accelRate        = 1.5,   -- aceleración horizontal suave (era 2.4 → muy rápido)
	decelRate        = 0.8,   -- desaceleración al soltar
	brakeRate        = 3.5,   -- frenado con X
	vertAccelRate    = 1.8,   -- aceleración vertical
	vertDecelRate    = 1.0,   -- desaceleración vertical
	tiltAngle        = math.rad(18),
	tiltSpeed        = 8,
	baseFOV          = 70,
	maxFOV           = 85,
	mouseSensitivity = 0.003,
}

----------------------------------------------------------------------
-- CONSTRUCTOR
----------------------------------------------------------------------
function DroneController.new(droneEntity: Instance, customConfig: DroneConfig?)
	print("[DroneController v4] Inicializando...")

	-- 1. Obtener BasePart del dron
	local rootPart: BasePart
	if droneEntity:IsA("BasePart") then
		rootPart = droneEntity
	elseif droneEntity:IsA("Model") then
		local pp = (droneEntity :: Model).PrimaryPart
		rootPart = pp or (droneEntity:FindFirstChildWhichIsA("BasePart") :: BasePart)
		assert(rootPart, "[DroneController] Modelo sin BasePart.")
	else
		error("[DroneController] Instancia inválida: " .. droneEntity.ClassName)
	end
	print("[DroneController] rootPart =", rootPart:GetFullName())

	-- 2. Obtener/crear constraints de vuelo (el servidor los crea, pero si no existen los creamos)
	local attachment = rootPart:FindFirstChild("FlightAttachment") :: Attachment?
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name     = "FlightAttachment"
		attachment.Position = Vector3.zero
		attachment.Parent   = rootPart
		print("[DroneController] FlightAttachment creado por cliente")
	end

	local linearVelocity = rootPart:FindFirstChild("FlightVelocity") :: LinearVelocity?
	if not linearVelocity then
		linearVelocity = Instance.new("LinearVelocity")
		linearVelocity.Name           = "FlightVelocity"
		linearVelocity.Attachment0    = attachment
		linearVelocity.RelativeTo     = Enum.ActuatorRelativeTo.World
		linearVelocity.MaxForce       = 1e6
		linearVelocity.VectorVelocity = Vector3.zero
		linearVelocity.Enabled        = true   -- asegurar habilitado
		linearVelocity.Parent         = rootPart
		print("[DroneController] FlightVelocity creado por cliente")
	else
		-- Si ya existía, asegurarse de que esté habilitado
		linearVelocity.Enabled = true
	end

	local alignOrientation = rootPart:FindFirstChild("FlightOrientation") :: AlignOrientation?
	if not alignOrientation then
		alignOrientation = Instance.new("AlignOrientation")
		alignOrientation.Name        = "FlightOrientation"
		alignOrientation.Attachment0 = attachment
		alignOrientation.Mode        = Enum.OrientationAlignmentMode.OneAttachment
		alignOrientation.Responsiveness = 25
		alignOrientation.MaxTorque   = 1e6
		alignOrientation.CFrame      = rootPart.CFrame
		alignOrientation.Enabled     = true   -- asegurar habilitado
		alignOrientation.Parent      = rootPart
		print("[DroneController] FlightOrientation creado por cliente")
	else
		alignOrientation.Enabled = true
	end

	-- 3. RemoteEvent del servidor
	local flightStateEvent: RemoteEvent? = nil
	local okNet, NetworkEvents = pcall(function()
		return require(script.Parent:WaitForChild("NetworkEvents", 5) :: ModuleScript)
	end)
	if okNet and NetworkEvents then
		flightStateEvent = (NetworkEvents :: any).Get((NetworkEvents :: any).Names.DroneFlightState)
	else
		flightStateEvent = ReplicatedStorage:FindFirstChild("DroneFlightState") :: RemoteEvent?
		if not flightStateEvent then
			flightStateEvent = ReplicatedStorage:WaitForChild("DroneFlightState", 5) :: RemoteEvent?
		end
	end
	if flightStateEvent then
		print("[DroneController] DroneFlightState RemoteEvent OK")
	else
		warn("[DroneController] DroneFlightState no encontrado - el dron puede no desanclarse")
	end

	-- 4. PlayerControls (para deshabilitar movimiento del personaje)
	local playerControls: any = nil
	local localPlayer = Players.LocalPlayer
	if localPlayer then
		pcall(function()
			local ps = localPlayer:WaitForChild("PlayerScripts", 3)
			if ps then
				local pm = ps:FindFirstChild("PlayerModule")
				if pm and pm:IsA("ModuleScript") then
					local mod = require(pm :: ModuleScript)
					playerControls = (mod :: any):GetControls()
				end
			end
		end)
	end

	-- 5. CARGA LAZY de subsistemas (cada uno en pcall independiente)
	--    Los módulos se requieren AQUÍ, no en el top-level del archivo.

	local function lazyRequire(name: string): any
		local ok, result = pcall(function()
			local mod = ReplicatedStorage:FindFirstChild(name) :: ModuleScript?
			if not mod then
				mod = ReplicatedStorage:WaitForChild(name, 5) :: ModuleScript?
			end
			assert(mod, "Módulo no encontrado: " .. name)
			return require(mod)
		end)
		if ok then
			print("[DroneController] Módulo cargado: " .. name)
			return result
		else
			warn("[DroneController] Error cargando " .. name .. ":", result)
			return nil
		end
	end

	local DroneHUD       = lazyRequire("DroneHUD")
	local DroneAudio     = lazyRequire("DroneAudio")
	local DroneVFX       = lazyRequire("DroneVFX")
	local DroneCargo     = lazyRequire("DroneCargo")
	local DeliveryMgr    = lazyRequire("DeliveryManager")
	local CyberGoggles   = lazyRequire("CyberGoggles")

	-- Instanciar subsistemas
	local hud: any = nil
	if DroneHUD then pcall(function() hud = DroneHUD.new() end) end

	local audio: any = nil
	if DroneAudio then pcall(function() audio = DroneAudio.new(rootPart) end) end

	local vfx: any = nil
	if DroneVFX then pcall(function() vfx = DroneVFX.new(rootPart) end) end

	local cargo: any = nil
	if DroneCargo then pcall(function() cargo = DroneCargo.new(rootPart) end) end

	local deliveryManager: any = nil
	if DeliveryMgr then
		local okDm, dmResult = pcall(function()
			return DeliveryMgr.new()
		end)
		if okDm and dmResult then
			deliveryManager = dmResult
			print("[DroneController] DeliveryManager instanciado con éxito.")
		else
			warn("[DroneController] ¡ERROR AL INSTANCIAR DeliveryManager!:", dmResult)
		end
	else
		warn("[DroneController] ¡ERROR! DeliveryMgr módulo es NIL (lazyRequire falló).")
	end

	-- 6. Construir instancia
	local self = setmetatable({
		rootPart          = rootPart,
		attachment        = attachment,
		linearVelocity    = linearVelocity,
		alignOrientation  = alignOrientation,
		config            = customConfig or DEFAULT_CONFIG,

		-- estado de inputs
		inputState = {
			forward   = false,
			backward  = false,
			left      = false,
			right     = false,
			up        = false,
			down      = false,
			turbo     = false,
			brake     = false,
			turnLeft  = false,
			turnRight = false,
		} :: InputState,

		-- física
		currentVelocity  = Vector3.zero,
		currentPitch     = 0,
		currentRoll      = 0,
		flightYaw        = 0,
		fpvPitch         = 0,
		turboEnergy      = 100,

		-- ═══ NUEVO: estado de combate y daño ═══
		currentHealth    = 100,       -- HP del dron del jugador
		maxHealth        = 100,
		currentHeat      = 0,         -- calor acumulado (0–maxHeat)
		maxHeat          = 100,
		isEMPed          = false,     -- estado de caída libre por sobrecalentamiento
		empEndTime       = 0,         -- os.clock() cuando termina el EMP
		armorReduction   = 0.0,       -- mitigación de daño (del DroneCatalog.spec)
		empResistance    = 0.0,       -- resistencia a microondas (del DroneCatalog.spec)
		heatCoolingRate  = 8,         -- puntos de calor/s que se disipan
		droneMassKg      = 5,         -- kg del chasis (para Ek de impacto)
		cargoSpeedMult   = 1.0,       -- multiplicador de velocidad por carga (DroneCargo)

		-- ═══ Arsenal Táctico y Contramedidas ═══
		lastWeaponFire     = 0,
		weaponCooldown     = 0.35,      -- cadencia de disparo (segundos)
		lastEMPTime        = 0,
		empCooldown        = 10.0,      -- recarga de pulso EMP (segundos)
		isWeaponOverheated = false,
		lastCargoDropTime  = 0,         -- Fase 5: cooldown entre expulsiones de carga por daño crítico

		-- ═══ Sistema de Misiles Guiados y Fijación de Objetivos ═══
		missilesRemaining   = 3,
		maxMissiles         = 3,
		lastMissileFire     = 0,
		missileCooldown     = 1.0,
		missileKey          = Enum.KeyCode.R,
		lockedTarget        = nil :: BasePart?,
		onDestroyedCallback = nil :: (() -> ())?,

		-- estado
		isFPV      = false,
		isFlying   = false,

		-- conexiones
		connection       = nil :: RBXScriptConnection?,
		inputBeganConn   = nil :: RBXScriptConnection?,
		inputEndedConn   = nil :: RBXScriptConnection?,
		mouseMoveConn    = nil :: RBXScriptConnection?,
		charDiedConn     = nil :: RBXScriptConnection?,

		-- camera
		originalWalkSpeed  = 16,
		originalJumpHeight = 7.2,

		-- subsistemas
		hud             = hud,
		audio           = audio,
		vfx             = vfx,
		cargo           = cargo,
		deliveryManager = deliveryManager,
		cyberGoggles    = CyberGoggles,
		playerControls  = playerControls,
		flightStateEvent = flightStateEvent,
		networkEvents   = if okNet then NetworkEvents else nil,
		onStateChangedCallback = nil :: ((boolean) -> ())?,
	}, DroneController)

	-- Callback de entrega y logística
	self:SetupDeliveryCallback()

	print("[DroneController v5] Listo!")
	return self
end

function DroneController:SetOnStateChangedCallback(callback: (boolean) -> ())
	self.onStateChangedCallback = callback
end

function DroneController:GetRemoteEvent(name: string): RemoteEvent?
	if self.networkEvents and (self.networkEvents :: any).Get then
		local ok, ev = pcall(function() return (self.networkEvents :: any).Get(name) end)
		if ok and ev then return ev end
	end
	local folder = ReplicatedStorage:FindFirstChild("CyberNetworkEvents")
	if folder then
		local ev = folder:FindFirstChild(name) :: RemoteEvent?
		if ev then return ev end
	end
	return ReplicatedStorage:FindFirstChild(name) :: RemoteEvent?
end

function DroneController:SetupDeliveryCallback()
	if not self.deliveryManager or not (self.deliveryManager :: any).SetOnDeliveryCallback then return end
	(self.deliveryManager :: any):SetOnDeliveryCallback(function(reward: number, padName: string, streak: number?, multiplier: number?)
		local isBase = (padName == "Base" or padName == "Pad_Base" or string.find(padName, "Base") ~= nil)
		local remaining = 0
		if isBase then
			if self.cargo and (self.cargo :: any).RestockAtBase then
				_, remaining = (self.cargo :: any):RestockAtBase()
			end

			-- Vía A: Si se completaron 3 entregas con éxito, recarga gratuita de 3 misiles
			if self.deliveryManager and (self.deliveryManager :: any).CheckAndConsumeMissileRestock then
				local earnedMissiles = (self.deliveryManager :: any):CheckAndConsumeMissileRestock()
				if earnedMissiles then
					self:ReloadMissiles(3, "3 entregas completadas")
				end
			end

			if self.hud then
				pcall(function()
					self.hud:ShowSuccessPopup(reward, "BASE CENTRAL", remaining, true, streak, multiplier)
				end)
			end
		else
			if self.cargo and (self.cargo :: any).DeliverOnePackage then
				_, remaining = (self.cargo :: any):DeliverOnePackage(self.rootPart.Position)
			elseif self.cargo then
				pcall(function() self.cargo:DeliverAndReload(self.rootPart.Position) end)
			end
			if self.hud then
				pcall(function()
					self.hud:ShowSuccessPopup(reward, padName, remaining, false, streak, multiplier)
				end)
			end
		end
	end)
end

----------------------------------------------------------------------
-- INICIAR VUELO
----------------------------------------------------------------------
function DroneController:StartFlying()
	if self.isFlying then
		print("[DroneController] Ya estaba volando.")
		return
	end
	print("[DroneController] StartFlying() llamado")
	self.isFlying = true

	-- Asegurar que las restricciones físicas de vuelo estén habilitadas
	if self.linearVelocity then self.linearVelocity.Enabled = true end
	if self.alignOrientation then self.alignOrientation.Enabled = true end

	-- Inicializar rumbo a la orientación actual del dron
	local _, initialYaw, _ = self.rootPart.CFrame:ToOrientation()
	self.flightYaw = initialYaw
	self.fpvPitch  = 0

	-- Notificar servidor para desanclar y transferir network ownership
	if self.flightStateEvent then
		print("[DroneController] Disparando StartFlying al servidor...")
		self.flightStateEvent:FireServer("StartFlying")
	end
	pcall(function() self.rootPart.Anchored = false end)

	-- Pequeña espera para que el servidor procese el desanclado
	task.delay(0.15, function()
		if self.isFlying and self.rootPart.Anchored then
			warn("[DroneController] Dron aún anclado tras 0.15s - servidor no respondió?")
		end
	end)

	-- Bloquear personaje (WalkSpeed=0, JumpPower=0)
	self:LockPlayerCharacter()

	-- Deshabilitar sistema de movimiento de Roblox
	if self.playerControls and self.playerControls.Disable then
		pcall(function() self.playerControls:Disable() end)
	end

	-- Activar gafas
	local localPlayer = Players.LocalPlayer
	local char = localPlayer and localPlayer.Character
	if char and self.cyberGoggles then
		pcall(function() self.cyberGoggles.SetOnline(char, true) end)
	end

	-- Auto-detener vuelo si el personaje muere y reiniciar racha
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			self.charDiedConn = hum.Died:Connect(function()
				if self.deliveryManager and (self.deliveryManager :: any).ResetStreak then
					pcall(function() (self.deliveryManager :: any):ResetStreak() end)
				end
				self:StopFlying()
			end)
		end
	end

	-- Configurar cámara según modo inicial
	local camera = Workspace.CurrentCamera
	if camera then
		if self.isFPV then
			camera.CameraType = Enum.CameraType.Scriptable
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		else
			camera.CameraType    = Enum.CameraType.Custom
			camera.CameraSubject = self.rootPart
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end

	-- Asegurar que DeliveryManager esté activo para misiones y entregas
	if not self.deliveryManager then
		local DelivMod = ReplicatedStorage:FindFirstChild("DeliveryManager") :: ModuleScript?
		if DelivMod then
			local okReq, mod = pcall(function() return require(DelivMod) end)
			if okReq and mod then
				local okNew, inst = pcall(function() return mod.new() end)
				if okNew and inst then
					self.deliveryManager = inst
					self:SetupDeliveryCallback()
					print("[DroneController] DeliveryManager activado al iniciar vuelo.")
				end
			end
		end
	end

	-- Auto-recarga garantizada en despegue de Base Central:
	local baseDist = (Vector3.new(self.rootPart.Position.X, 0, self.rootPart.Position.Z) - Vector3.new(0, 0, 0)).Magnitude
	if baseDist <= 45 then
		local currentCargoCount = if self.cargo and (self.cargo :: any).GetPackageCount then (self.cargo :: any):GetPackageCount() else 0
		local dmPkgs = if self.deliveryManager and (self.deliveryManager :: any).GetPackagesRemaining then (self.deliveryManager :: any):GetPackagesRemaining() else 0
		if currentCargoCount < 3 or dmPkgs < 3 then
			print(string.format("[DroneController] Despegando de Base Central con bodega incompleta (Cargo:%d, DM:%d). ¡Auto-reabasteciendo a 3/3!", currentCargoCount, dmPkgs))
			if self.cargo and (self.cargo :: any).RestockAtBase then
				(self.cargo :: any):RestockAtBase()
			end
			if self.deliveryManager then
				(self.deliveryManager :: any).packagesRemaining = 3
				(self.deliveryManager :: any).originPadName = "Pad_Base"
				if (self.deliveryManager :: any).PickNextTarget then
					(self.deliveryManager :: any):PickNextTarget("Pad_Base")
				end
			end
			if self.hud and (self.hud :: any).ShowHint then
				pcall(function()
					(self.hud :: any):ShowHint("¡BODEGA REABASTECIDA (3/3 PAQUETES)!", false)
				end)
			end
		end
	end

	-- Vincular inputs de vuelo
	self:BindInputs()

	-- Iniciar loop de física
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	self.connection = RunService.RenderStepped:Connect(function(dt: number)
		dt = math.clamp(dt, 0, 0.1)

		-- ═══ GUARD EMP: si el dron está apagado por EMP, caída libre ═══
		if self.isEMPed then
			self.currentVelocity = Vector3.zero
			-- LinearVelocity ya desactivado por TriggerEMPLocal, no forzar aquí
			return
		end

		-- Actualizar lista de exclusión para raycast
		local filterList: { Instance } = { self.rootPart }
		local lp = Players.LocalPlayer
		if lp and lp.Character then
			table.insert(filterList, lp.Character)
		end
		raycastParams.FilterDescendantsInstances = filterList

		-- Disipación natural de calor en el cliente
		if self.currentHeat and self.currentHeat > 0 and not self.isEMPed then
			self.currentHeat = math.max(0, self.currentHeat - (self.heatCoolingRate or 8) * dt)
			if self.currentHeat < 50 then
				self.isWeaponOverheated = false
			end
		end

		-- Turbo energy
		local isBoosting = self.inputState.turbo and (self.turboEnergy > 5)
		if isBoosting then
			self.turboEnergy = math.max(0, self.turboEnergy - dt * 25)
		else
			self.turboEnergy = math.min(100, self.turboEnergy + dt * 12)
		end

		local maxSpeed = (if isBoosting then self.config.turboSpeed else self.config.cruiseSpeed) * (self.cargoSpeedMult or 1.0)

		-- Actualizar rumbo y orientación de vuelo
		local cam = Workspace.CurrentCamera
		if cam and not self.isFPV then
			-- En 3ra persona: el rumbo del dron sigue la dirección orbital de la cámara
			local camCF = cam.CFrame
			local rawLook  = camCF.LookVector
			local flatLook = Vector3.new(rawLook.X, 0, rawLook.Z)
			if flatLook.Magnitude > 0.001 then
				self.flightYaw = math.atan2(-flatLook.X, -flatLook.Z)
			end
		end

		-- Giro con teclado (flechas izquierda/derecha)
		local keyTurn = (if self.inputState.turnLeft then 1 else 0) - (if self.inputState.turnRight then 1 else 0)
		if keyTurn ~= 0 then
			self.flightYaw = self.flightYaw + keyTurn * (math.rad(90) * dt)
		end

		-- Vectores de movimiento horizontal derivados del rumbo actual
		local yawCF = CFrame.Angles(0, self.flightYaw, 0)
		local fwd = yawCF.LookVector
		local rgt = yawCF.RightVector

		-- Input direccional
		local moveZ = (if self.inputState.forward then 1 else 0) - (if self.inputState.backward then 1 else 0)
		local moveX = (if self.inputState.right then 1 else 0) - (if self.inputState.left then 1 else 0)
		local moveY = (if self.inputState.up then 1 else 0) - (if self.inputState.down then 1 else 0)
		-- Nota: forward = W = fwd (delante según el rumbo del piloto)

		local isBraking    = self.inputState.brake
		local isThrottling = (math.abs(moveZ) + math.abs(moveX)) > 0.01

		-- Calcular horizontal objetivo
		local moveDir = (fwd * moveZ) + (rgt * moveX)
		if moveDir.Magnitude > 0 then moveDir = moveDir.Unit end
		local targetH = moveDir * maxSpeed

		-- Seleccionar tasa de interpolación horizontal
		local hRate: number
		if isBraking then
			hRate   = self.config.brakeRate
			targetH = Vector3.zero
		elseif isThrottling then
			hRate = self.config.accelRate
		else
			hRate = self.config.decelRate
		end

		-- Lerp horizontal
		local curH = Vector3.new(self.currentVelocity.X, 0, self.currentVelocity.Z)
		local newH = curH:Lerp(targetH, math.clamp(dt * hRate, 0, 1))

		-- Calcular vertical objetivo
		local targetY = moveY * self.config.verticalSpeed
		local vRate: number
		if isBraking then
			vRate   = self.config.brakeRate
			targetY = 0
		elseif math.abs(moveY) > 0.01 then
			vRate = self.config.vertAccelRate
		else
			vRate = self.config.vertDecelRate
		end

		local newY = self.currentVelocity.Y + (targetY - self.currentVelocity.Y) * math.clamp(dt * vRate, 0, 1)

		-- Aplicar velocidad
		self.currentVelocity = Vector3.new(newH.X, newY, newH.Z)
		self.linearVelocity.VectorVelocity = self.currentVelocity

		-- Inclinación física del dron (tilt)
		-- targetPitch: morro baja al acelerar adelante (-moveZ)
		-- targetRoll: signo NEGATIVO para que al moverse a la derecha el dron incline su lado derecho abajo (aerodinámica real, no levanta el ala contra el viento)
		local speedRatio  = math.clamp(self.currentVelocity.Magnitude / self.config.cruiseSpeed, 0, 1)
		local targetPitch = -moveZ * self.config.tiltAngle * math.max(0.3, speedRatio)
		local targetRoll  = -moveX * self.config.tiltAngle

		local tFactor = math.clamp(dt * self.config.tiltSpeed, 0, 1)
		self.currentPitch = self.currentPitch + (targetPitch - self.currentPitch) * tFactor
		self.currentRoll  = self.currentRoll  + (targetRoll  - self.currentRoll)  * tFactor

		self.alignOrientation.CFrame = yawCF * CFrame.Angles(self.currentPitch, 0, self.currentRoll)

		-- Cámara FPV / Chase (3ra persona)
		if cam then
			if self.isFPV then
				cam.CameraType = Enum.CameraType.Scriptable
				-- Posición en cabina delantera ligeramente elevada
				local cockpitOffset = Vector3.new(0, 0.45, -self.rootPart.Size.Z * 0.5 - 0.2)
				local eyePos = self.rootPart.CFrame:PointToWorldSpace(cockpitOffset)

				-- Orientación: rumbo del dron + pitch de vista de piloto (mouse) + sutil inclinación física
				local camRot = CFrame.Angles(0, self.flightYaw, 0)
					* CFrame.Angles(self.currentPitch * 0.5 + self.fpvPitch, 0, self.currentRoll * 0.35)

				cam.CFrame = CFrame.new(eyePos) * camRot

				-- FOV dinámico en FPV para dar sensación de velocidad inmersiva
				local targetFOV = 85 + (100 - 85) * speedRatio
				cam.FieldOfView = cam.FieldOfView + (targetFOV - cam.FieldOfView) * math.clamp(dt * 6, 0, 1)
			else
				if cam.CameraType ~= Enum.CameraType.Custom then
					cam.CameraType = Enum.CameraType.Custom
				end
				if cam.CameraSubject ~= self.rootPart then
					cam.CameraSubject = self.rootPart
				end
				local targetFOV = self.config.baseFOV + (self.config.maxFOV - self.config.baseFOV) * speedRatio
				cam.FieldOfView = cam.FieldOfView + (targetFOV - cam.FieldOfView) * math.clamp(dt * 5, 0, 1)
			end
		end

		-- Target Lock Detection (Detección cónica para mira central en 3ra Persona y FPV)
		local lockedEnemy: BasePart? = nil
		local lockedEnemyDist = 320
		local enemyFolder = Workspace:FindFirstChild("EnemyDrones")

		if cam and enemyFolder then
			local aimRay = cam:ViewportPointToRay(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
			local aimOrigin = aimRay.Origin
			local aimDir = aimRay.Direction

			for _, enemy in ipairs(enemyFolder:GetChildren()) do
				if enemy:IsA("BasePart") and enemy.Name ~= "AccentBand" and enemy.Name ~= "LaserSight" then
					local toEnemy = enemy.Position - aimOrigin
					local dist = toEnemy.Magnitude
					if dist <= lockedEnemyDist and dist > 1.0 then
						local dot = aimDir:Dot(toEnemy.Unit)
						-- Cono de ~16 grados de tolerancia respecto al centro de la retícula
						if dot >= 0.96 then
							-- Comprobar línea de visión física (no fijar enemigos detrás de torres o edificios)
							local losParams = RaycastParams.new()
							losParams.FilterType = Enum.RaycastFilterType.Exclude
							local losExclude = { self.rootPart }
							if lp and lp.Character then table.insert(losExclude, lp.Character) end
							losParams.FilterDescendantsInstances = losExclude

							local losHit = Workspace:Raycast(aimOrigin, toEnemy, losParams)
							if not losHit or losHit.Instance == enemy or losHit.Instance:IsDescendantOf(enemy) then
								lockedEnemyDist = dist
								lockedEnemy = enemy
							end
						end
					end
				end
			end
		end

		self.lockedTarget = lockedEnemy
		if self.hud and (self.hud :: any).SetTargetLock then
			if lockedEnemy then
				local cleanName = lockedEnemy.Name:gsub("_%d+", "")
				(self.hud :: any):SetTargetLock(cleanName, lockedEnemyDist)
			else
				(self.hud :: any):SetTargetLock(nil)
			end
		end

		-- Altímetro por raycast
		local rayResult = Workspace:Raycast(self.rootPart.Position, Vector3.new(0, -600, 0), raycastParams)
		local altitude  = if rayResult then (self.rootPart.Position.Y - rayResult.Position.Y) else 600

		-- Delivery manager
		local landingProgress = 0
		local currentTarget: any = nil
		if self.deliveryManager then
			pcall(function()
				local _, prog = self.deliveryManager:Update(dt, self.rootPart.Position, self.currentVelocity)
				landingProgress = prog or 0
				currentTarget   = self.deliveryManager:GetCurrentTarget()
			end)
		end

		local cargoCount = if self.cargo and (self.cargo :: any).GetPackageCount then (self.cargo :: any):GetPackageCount() else 3
		local maxCargo = if self.cargo and (self.cargo :: any).GetMaxPackages then (self.cargo :: any):GetMaxPackages() else 3
		if self.cargo and (self.cargo :: any).GetSpeedMultiplier then
			self.cargoSpeedMult = (self.cargo :: any):GetSpeedMultiplier()
		end

		local streakCount = if self.deliveryManager and (self.deliveryManager :: any).GetDeliveryStreak then (self.deliveryManager :: any):GetDeliveryStreak() else 0
		local streakMult = if self.deliveryManager and (self.deliveryManager :: any).GetStreakMultiplier then (self.deliveryManager :: any):GetStreakMultiplier() else 1.0

		local hpRatio = (self.currentHealth or 100) / (self.maxHealth or 100)
		local heatRatio = (self.currentHeat or 0) / (self.maxHeat or 100)
		local empRemaining = math.max(0, (self.empCooldown or 10.0) - (os.clock() - (self.lastEMPTime or 0)))

		local rushActive, rushRemaining, _ = false, 0, 1.0
		if self.deliveryManager and (self.deliveryManager :: any).GetRushInfo then
			rushActive, rushRemaining, _ = (self.deliveryManager :: any):GetRushInfo()
		end

		local pilotRank = "Cadete Aéreo"
		local localPlr = Players.LocalPlayer
		if localPlr then
			local leaderstats = localPlr:FindFirstChild("leaderstats")
			if leaderstats then
				local rVal = leaderstats:FindFirstChild("Rango")
				if rVal and rVal:IsA("StringValue") then
					pilotRank = rVal.Value
				end
			end
		end

		-- HUD
		if self.hud then
			pcall(function()
				self.hud:Update(
					self.currentVelocity.Magnitude,
					self.config.cruiseSpeed,
					self.turboEnergy / 100,
					altitude,
					self.currentRoll,
					self.isFPV,
					isBraking,
					currentTarget and currentTarget.position or nil,
					currentTarget and currentTarget.displayName or nil,
					currentTarget and currentTarget.reward or 250,
					landingProgress,
					cargoCount,
					maxCargo,
					currentTarget and currentTarget.threatLevel or "safe",
					currentTarget and currentTarget.hazardInfo or "ZONA NOMINAL",
					streakCount,
					streakMult,
					hpRatio,
					heatRatio,
					self.isEMPed,
					empRemaining,
					self.rootPart.Position,
					self.flightYaw,
					dt,
					rushActive,
					rushRemaining,
					pilotRank
				)
			end)
		end

		-- Audio y VFX
		if self.audio then pcall(function() self.audio:Update(speedRatio, moveY, dt) end) end
		if self.vfx   then pcall(function() self.vfx:Update(speedRatio, moveY)      end) end
	end)

	print("[DroneController] ¡Loop de vuelo iniciado!")
	if self.onStateChangedCallback then
		pcall(self.onStateChangedCallback, true)
	end
end

----------------------------------------------------------------------
-- DETENER VUELO
----------------------------------------------------------------------
function DroneController:StopFlying()
	if not self.isFlying then return end
	self.isFlying = false
	print("[DroneController] StopFlying() llamado")

	-- Parar loop
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end

	-- Desconectar listener de muerte de personaje
	if self.charDiedConn then
		self.charDiedConn:Disconnect()
		self.charDiedConn = nil
	end

	-- Parar velocidad
	self.currentVelocity = Vector3.zero
	self.linearVelocity.VectorVelocity = Vector3.zero

	-- Notificar servidor
	if self.flightStateEvent then
		self.flightStateEvent:FireServer("StopFlying")
	else
		pcall(function()
			self.rootPart.AssemblyLinearVelocity = Vector3.zero
			self.rootPart.Anchored = true
		end)
	end

	-- Desactivar gafas
	local lp = Players.LocalPlayer
	local char = lp and lp.Character
	if char and self.cyberGoggles then
		pcall(function() self.cyberGoggles.SetOnline(char, false) end)
	end

	-- Desconectar inputs
	self:UnbindInputs()

	-- Restaurar cursor y estado de cámara FPV
	pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
	self.isFPV = false
	self.fpvPitch = 0

	-- Restaurar personaje
	self:UnlockPlayerCharacter()
	if self.playerControls and self.playerControls.Enable then
		pcall(function() self.playerControls:Enable() end)
	end

	-- Restaurar cámara al personaje
	local camera = Workspace.CurrentCamera
	if camera and char then
		camera.CameraType = Enum.CameraType.Custom
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then camera.CameraSubject = hum end
		camera.FieldOfView = self.config.baseFOV
	end

	if self.onStateChangedCallback then
		pcall(self.onStateChangedCallback, false)
	end
end

----------------------------------------------------------------------
-- BLOQUEAR / DESBLOQUEAR PERSONAJE
----------------------------------------------------------------------
function DroneController:LockPlayerCharacter()
	local lp   = Players.LocalPlayer
	local char = lp and lp.Character
	if not char then return end

	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		if hum.WalkSpeed > 0 then
			self.originalWalkSpeed = hum.WalkSpeed
		end
		if hum.JumpHeight > 0 then
			self.originalJumpHeight = hum.JumpHeight
		end
		hum.WalkSpeed  = 0
		hum.JumpHeight = 0
		hum.JumpPower  = 0
	end
	-- NO anclamos HumanoidRootPart: causa problemas con la física del servidor
end

function DroneController:UnlockPlayerCharacter()
	local lp   = Players.LocalPlayer
	local char = lp and lp.Character
	if not char then return end

	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed  = if (self.originalWalkSpeed and self.originalWalkSpeed > 0) then self.originalWalkSpeed else 16
		hum.JumpHeight = if (self.originalJumpHeight and self.originalJumpHeight > 0) then self.originalJumpHeight else 7.2
		hum.JumpPower  = 50
	end
end

----------------------------------------------------------------------
-- VINCULAR / DESVINCULAR INPUTS DE VUELO
----------------------------------------------------------------------
function DroneController:BindInputs()
	self:UnbindInputs()
	print("[DroneController] BindInputs() - WASD/Flechas/Space/Shift/Q/X/V/LMB/C activos")

	self.inputBeganConn = UserInputService.InputBegan:Connect(function(input: InputObject, _gpe: boolean)
		local focused = UserInputService:GetFocusedTextBox()
		if focused then return end

		-- Disparo táctico con MouseButton1 (LMB)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if self.isFlying then
				if self.isFPV then
					UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
				end
				self:FireWeapon()
			end
			return
		end

		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		local k = input.KeyCode

		if     k == Enum.KeyCode.W          then self.inputState.forward   = true
		elseif k == Enum.KeyCode.S          then self.inputState.backward  = true
		elseif k == Enum.KeyCode.A          then self.inputState.left      = true
		elseif k == Enum.KeyCode.D          then self.inputState.right     = true
		elseif k == Enum.KeyCode.Space      then self.inputState.up        = true
		elseif k == Enum.KeyCode.LeftShift or k == Enum.KeyCode.LeftControl then self.inputState.down = true
		elseif k == Enum.KeyCode.C          then self:TriggerEMP()
		elseif k == Enum.KeyCode.Q          then self.inputState.turbo     = true
		elseif k == Enum.KeyCode.X          then self.inputState.brake     = true
		elseif k == Enum.KeyCode.Left       then self.inputState.turnLeft  = true
		elseif k == Enum.KeyCode.Right      then self.inputState.turnRight = true
		elseif k == Enum.KeyCode.V          then
			self.isFPV = not self.isFPV
			local camera = Workspace.CurrentCamera
			if self.isFPV then
				UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
				self.fpvPitch = 0
				if camera then
					camera.CameraType = Enum.CameraType.Scriptable
				end
			else
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				if camera then
					camera.CameraType = Enum.CameraType.Custom
					camera.CameraSubject = self.rootPart
					camera.FieldOfView = self.config.baseFOV
				end
			end
		elseif k == Enum.KeyCode.G          then
			-- Auto-recuperación: si deliveryManager era nil por latencia de carga inicial, reintentar ahora
			if not self.deliveryManager then
				print("[DroneController] deliveryManager era nil, intentando inicializar bajo demanda...")
				local DelivMod = ReplicatedStorage:FindFirstChild("DeliveryManager") :: ModuleScript?
				if DelivMod then
					local okReq, modResult = pcall(function() return require(DelivMod) end)
					if okReq and modResult then
						local okNew, inst = pcall(function() return modResult.new() end)
						if okNew and inst then
							self.deliveryManager = inst
							self:SetupDeliveryCallback()
							print("[DroneController] ¡deliveryManager inicializado bajo demanda con éxito!")
						else
							warn("[DroneController] Falló modResult.new() bajo demanda:", inst)
						end
					else
						warn("[DroneController] Falló require(DeliveryManager) bajo demanda:", modResult)
					end
				end
			end

			if self.deliveryManager and (self.deliveryManager :: any).TryManualDeliver then
				local ok, success, hint = pcall(function()
					return (self.deliveryManager :: any):TryManualDeliver(self.rootPart.Position, self.currentVelocity)
				end)
				if ok then
					if success then
						if self.hud and (self.hud :: any).ShowHint then
							pcall(function() (self.hud :: any):ShowHint("[G] ¡SOLICITUD DE ENTREGA ENVIADA!", false) end)
						end
					else
						local msg = if typeof(hint) == "string" then hint else "Debes estar sobre un helipuerto"
						if self.hud and (self.hud :: any).ShowHint then
							pcall(function() (self.hud :: any):ShowHint("[G] NO DISPONIBLE: " .. msg, true) end)
						end
					end
				end
			else
				warn("[DroneController] DeliveryManager no disponible al presionar G")
				if self.hud and (self.hud :: any).ShowHint then
					pcall(function() (self.hud :: any):ShowHint("SISTEMA DE ENTREGA NO DISPONIBLE", true) end)
				end
			end
		elseif k == (self.missileKey or Enum.KeyCode.R) then
			-- Disparo de Misil Guiado [R]
			self:FireMissile()
		elseif k == Enum.KeyCode.M then
			-- Compra táctica de recarga de misiles en Base Central por 150 PELAOCOINS
			local buyMissilesEv = self:GetRemoteEvent("BuyMissiles")
			if buyMissilesEv then
				buyMissilesEv:FireServer()
			else
				warn("[DroneController] BuyMissiles RemoteEvent no encontrado")
			end
		end
	end)

	self.inputEndedConn = UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		local k = input.KeyCode

		if     k == Enum.KeyCode.W          then self.inputState.forward   = false
		elseif k == Enum.KeyCode.S          then self.inputState.backward  = false
		elseif k == Enum.KeyCode.A          then self.inputState.left      = false
		elseif k == Enum.KeyCode.D          then self.inputState.right     = false
		elseif k == Enum.KeyCode.Space      then self.inputState.up        = false
		elseif k == Enum.KeyCode.LeftShift or k == Enum.KeyCode.LeftControl then self.inputState.down = false
		elseif k == Enum.KeyCode.Q          then self.inputState.turbo     = false
		elseif k == Enum.KeyCode.X          then self.inputState.brake     = false
		elseif k == Enum.KeyCode.Left       then self.inputState.turnLeft  = false
		elseif k == Enum.KeyCode.Right      then self.inputState.turnRight = false
		end
	end)

	-- Giro suave con el mouse en primera persona (FPV)
	self.mouseMoveConn = UserInputService.InputChanged:Connect(function(input: InputObject, _gpe: boolean)
		if not self.isFlying then return end
		if not self.isFPV then return end

		if input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Delta
			local sens = self.config.mouseSensitivity or 0.003
			self.flightYaw = self.flightYaw - delta.X * sens
			self.fpvPitch  = math.clamp(self.fpvPitch - delta.Y * sens, math.rad(-60), math.rad(60))
		end
	end)
end

function DroneController:UnbindInputs()
	if self.inputBeganConn then self.inputBeganConn:Disconnect(); self.inputBeganConn = nil end
	if self.inputEndedConn then self.inputEndedConn:Disconnect(); self.inputEndedConn = nil end
	if self.mouseMoveConn  then self.mouseMoveConn:Disconnect();  self.mouseMoveConn  = nil end

	-- Resetear todos los estados de input
	self.inputState.forward   = false
	self.inputState.backward  = false
	self.inputState.left      = false
	self.inputState.right     = false
	self.inputState.up        = false
	self.inputState.down      = false
	self.inputState.turbo     = false
	self.inputState.brake     = false
	self.inputState.turnLeft  = false
	self.inputState.turnRight = false
end

----------------------------------------------------------------------
-- ═══════════════════════════════════════════════════════════════════
-- EXTENSIONES DE COMBATE — ApplyDamage, ApplyHeat, SetCargoMass
-- ═══════════════════════════════════════════════════════════════════
----------------------------------------------------------------------

-- Aplica daño al dron del jugador (recibido del servidor via RemoteEvent)
function DroneController:ApplyDamage(finalDamage: any, attackerPos: Vector3?)
	local dmg = 0
	if typeof(finalDamage) == "number" then
		dmg = finalDamage
	elseif typeof(finalDamage) == "table" and typeof(finalDamage.damage) == "number" then
		dmg = finalDamage.damage
		if typeof((finalDamage :: any).attackerPosition) == "Vector3" then
			attackerPos = (finalDamage :: any).attackerPosition
		end
	end
	if dmg <= 0 then return end

	self.currentHealth = math.max(0, (self.currentHealth or self.maxHealth) - dmg)
	local hpPct = self.currentHealth / (self.maxHealth or 100)

	if self.hud then
		pcall(function()
			if (self.hud :: any).SetHealthDisplay then
				(self.hud :: any):SetHealthDisplay(hpPct)
			end
			if (self.hud :: any).FlashDamageVignette then
				(self.hud :: any):FlashDamageVignette(dmg, attackerPos, self.rootPart.Position, self.flightYaw)
			end
		end)
	end
	if self.vfx then
		pcall(function()
			if (self.vfx :: any).PlayHitEffect then
				(self.vfx :: any):PlayHitEffect(dmg)
			end
		end)
	end

	-- Fase 5: Pérdida de Carga Física por Daño Crítico o Impacto Fuerte
	local now = os.clock()
	if (dmg >= 16 or self.currentHealth <= 35) and (now - (self.lastCargoDropTime or 0) > 4.0) then
		if self.cargo and (self.cargo :: any).DropOnePackage then
			local okDrop, dropped = pcall(function()
				return (self.cargo :: any):DropOnePackage(self.rootPart.Position)
			end)
			if okDrop and dropped then
				self.lastCargoDropTime = now
				local remaining = if (self.cargo :: any).GetPackageCount then (self.cargo :: any):GetPackageCount() else 0
				if self.deliveryManager and (self.deliveryManager :: any).NotifyCargoLost then
					(self.deliveryManager :: any):NotifyCargoLost(remaining)
				end
				if self.hud and (self.hud :: any).ShowHint then
					pcall(function()
						(self.hud :: any):ShowHint("¡ALERTA! ¡PAQUETE EXPULSADO POR IMPACTO CRÍTICO!", true)
					end)
				end
			end
		end
	end

	if self.currentHealth <= 0 then
		warn("[DroneController] ¡Dron destruido! Desconectando enlace y reseteando estado a Base Central...")
		self:ResetOnDestroyed()
		if self.onDestroyedCallback then
			pcall(self.onDestroyedCallback)
		end
	end
end

-- Dispara el cañón de plasma frontal [MouseButton1]
function DroneController:FireWeapon()
	if not self.isFlying then return end
	if self.isEMPed then return end
	if self.isWeaponOverheated then
		if self.hud and (self.hud :: any).ShowHint then
			pcall(function() (self.hud :: any):ShowHint("¡CAÑÓN SOBRECALENTADO! DISIPANDO CALOR...", true) end)
		end
		return
	end

	local now = os.clock()
	if now - (self.lastWeaponFire or 0) < (self.weaponCooldown or 0.35) then
		return
	end
	self.lastWeaponFire = now

	-- Calcular origen y convergencia (prioriza el objetivo fijado por la retícula)
	local cam = Workspace.CurrentCamera
	local originPos = self.rootPart.Position + self.rootPart.CFrame.LookVector * (self.rootPart.Size.Z * 0.5 + 0.5)
	local targetPos: Vector3
	local targetPart: BasePart? = nil

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local lp = Players.LocalPlayer
	local excludeList: { Instance } = { self.rootPart }
	if lp and lp.Character then table.insert(excludeList, lp.Character) end
	rayParams.FilterDescendantsInstances = excludeList

	if self.lockedTarget and self.lockedTarget.Parent then
		targetPart = self.lockedTarget
		targetPos = self.lockedTarget.Position
	elseif cam then
		local unitRay = cam:ViewportPointToRay(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
		local hit = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 240, rayParams)
		if hit then
			targetPos = hit.Position
			if hit.Instance and hit.Instance:IsA("BasePart") then
				targetPart = hit.Instance
			end
		else
			targetPos = unitRay.Origin + unitRay.Direction * 200
		end
	else
		targetPos = originPos + self.rootPart.CFrame.LookVector * 180
	end

	-- Comprobar colisión estricta de trayectoria entre la boquilla y targetPos contra torres y obstáculos
	local toTarget = targetPos - originPos
	if toTarget.Magnitude > 0.5 then
		local trajHit = Workspace:Raycast(originPos, toTarget, rayParams)
		if trajHit and trajHit.Instance then
			local hitObj = trajHit.Instance
			-- Si impactó una torre, pared, helipuerto o edificio antes de llegar a la nave enemiga
			if hitObj ~= targetPart and not (targetPart and hitObj:IsDescendantOf(targetPart)) then
				targetPos = trajHit.Position
				targetPart = hitObj
			end
		end
	end

	-- Simulación de proyectil local inmediata para feedback visual sin lag de red
	self:SpawnLocalPlasmaBolt(originPos, targetPos)

	-- Generar calor en el chasis
	self.currentHeat = math.min(self.maxHeat or 100, (self.currentHeat or 0) + 4)
	if self.currentHeat >= 85 then
		self.isWeaponOverheated = true
	end

	-- Notificar servidor para validación autoritativa de daño y efectos
	local onFireEv = self:GetRemoteEvent("OnFireWeapon")
	if onFireEv then
		onFireEv:FireServer({
			weaponId   = "magma_spike",
			origin     = originPos,
			target     = targetPos,
			targetPart = targetPart,
		})
	end
end

-- Simula el proyectil de plasma en el cliente
function DroneController:SpawnLocalPlasmaBolt(startPos: Vector3, endPos: Vector3)
	local bolt = Instance.new("Part")
	bolt.Name = "LocalPlasmaBolt"
	bolt.Size = Vector3.new(0.5, 0.5, 2.0)
	bolt.Material = Enum.Material.Neon
	bolt.Color = Color3.fromRGB(255, 100, 0)
	bolt.CanCollide = false
	bolt.CastShadow = false
	bolt.Massless = true
	bolt.CFrame = CFrame.lookAt(startPos, endPos)
	bolt.Parent = Workspace

	local dist = (endPos - startPos).Magnitude
	local duration = math.clamp(dist / 140, 0.05, 1.5)

	local tween = TweenService:Create(
		bolt,
		TweenInfo.new(duration, Enum.EasingStyle.Linear),
		{ CFrame = CFrame.lookAt(endPos, endPos + (endPos - startPos).Unit) }
	)
	tween:Play()
	tween.Completed:Connect(function()
		if bolt.Parent then
			-- Destello de impacto y chispas al colisionar contra la torre o nave
			local flash = Instance.new("Part")
			flash.Shape = Enum.PartType.Ball
			flash.Size = Vector3.new(1.8, 1.8, 1.8)
			flash.Material = Enum.Material.Neon
			flash.Color = Color3.fromRGB(255, 160, 40)
			flash.Position = endPos
			flash.CanCollide = false
			flash.Anchored = true
			flash.Parent = Workspace
			Debris:AddItem(flash, 0.10)
			bolt:Destroy()
		end
	end)
end

-- Activa la contramedida de pulso electromagnético [C]
function DroneController:TriggerEMP()
	if not self.isFlying then return end
	if self.isEMPed then return end

	local now = os.clock()
	local elapsed = now - (self.lastEMPTime or 0)
	if elapsed < (self.empCooldown or 10.0) then
		local remaining = math.ceil((self.empCooldown or 10.0) - elapsed)
		if self.hud and (self.hud :: any).ShowHint then
			pcall(function() (self.hud :: any):ShowHint(string.format("PULSO EMP EN RECARGA (%ds)", remaining), true) end)
		end
		return
	end
	self.lastEMPTime = now

	-- Onda expansiva esférica cyan local
	self:SpawnLocalEMPWave(self.rootPart.Position)

	if self.hud and (self.hud :: any).ShowHint then
		pcall(function() (self.hud :: any):ShowHint("¡CONTRAMEDIDA EMP ACTIVADA! PARALIZANDO AMENAZAS", false) end)
	end

	-- Notificar servidor para aplicar contramedida autoritativa
	local onEMPEv = self:GetRemoteEvent("OnEMPActivated")
	if onEMPEv then
		onEMPEv:FireServer()
	end
end

-- Simula onda expansiva de pulso electromagnético local
function DroneController:SpawnLocalEMPWave(centerPos: Vector3)
	local sphere = Instance.new("Part")
	sphere.Name = "LocalEMPWave"
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(2, 2, 2)
	sphere.Position = centerPos
	sphere.Material = Enum.Material.Neon
	sphere.Color = Color3.fromRGB(0, 255, 230)
	sphere.Transparency = 0.4
	sphere.CanCollide = false
	sphere.Anchored = true
	sphere.CastShadow = false
	sphere.Parent = Workspace

	local tween = TweenService:Create(
		sphere,
		TweenInfo.new(0.6, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
		{ Size = Vector3.new(120, 120, 120), Transparency = 1 }
	)
	tween:Play()
	tween.Completed:Connect(function()
		if sphere.Parent then sphere:Destroy() end
	end)
end

-- Aplica calor y gestiona estado EMP en el cliente (eco del servidor)
function DroneController:ApplyHeat(heatAmount: number)
	local maxH = self.maxHeat or 100
	self.currentHeat = math.min(maxH, (self.currentHeat or 0) + heatAmount)
	local heatPct = self.currentHeat / maxH

	if self.hud then
		pcall(function()
			if (self.hud :: any).SetHeatDisplay then
				(self.hud :: any):SetHeatDisplay(heatPct)
			end
		end)
	end

	if heatPct >= 1.0 and not self.isEMPed then
		self:TriggerEMPLocal(2.0)
	end
end

-- Activa EMP local: congela física cliente y espera restauración
function DroneController:TriggerEMPLocal(duration: number)
	if self.isEMPed then return end
	self.isEMPed = true
	self.empEndTime = os.clock() + duration
	self.currentVelocity = Vector3.zero
	if self.linearVelocity then
		self.linearVelocity.VectorVelocity = Vector3.zero
		self.linearVelocity.Enabled = false   -- caída libre real
	end
	if self.alignOrientation then
		self.alignOrientation.Enabled = false  -- pierde orientación
	end
	if self.vfx then
		pcall(function()
			if (self.vfx :: any).PlayEMPEffect then (self.vfx :: any):PlayEMPEffect() end
		end)
	end
	print(string.format("[DroneController] EMP activo %.1fs", duration))
	task.delay(duration, function()
		self.isEMPed = false
		self.currentHeat = (self.maxHeat or 100) * 0.8
		-- Restaurar constraints
		if self.linearVelocity then self.linearVelocity.Enabled = true end
		if self.alignOrientation then self.alignOrientation.Enabled = true end
		print("[DroneController] Sistemas restaurados.")
	end)
end

-- Configura la masa de la carga y actualiza el multiplicador de velocidad
-- VelocidadEfectiva = Base / (1 + masaCarga * α)
function DroneController:SetCargoMass(massKg: number, inertiaAlpha: number?, unstable: boolean?)
	local alpha = inertiaAlpha or 0.040
	self.cargoSpeedMult = math.max(0.3, 1.0 / (1 + massKg * alpha))
	if self.cargo then
		pcall(function()
			if (self.cargo :: any).SetCargo then
				(self.cargo :: any):SetCargo(massKg, alpha, unstable or false)
			end
		end)
	end
	print(string.format("[DroneController] Carga %.1f kg | Mult. velocidad %.2fx", massKg, self.cargoSpeedMult))
end

-- Aplica estadísticas de un DroneSpec al controlador (para cambio de dron)
function DroneController:ApplySpec(spec: { [string]: any })
	self.maxHealth       = (spec.maxHealth :: number?) or 100
	self.currentHealth   = self.maxHealth
	self.maxHeat         = (spec.maxHeat :: number?) or 100
	self.currentHeat     = 0
	self.heatCoolingRate = (spec.heatCoolingRate :: number?) or 8
	self.armorReduction  = (spec.armorReduction :: number?) or 0
	self.empResistance   = (spec.empResistance :: number?) or 0
	self.droneMassKg     = (spec.mass :: number?) or 5
	self.config.cruiseSpeed   = (spec.maxSpeed :: number?) or self.config.cruiseSpeed
	self.config.turboSpeed    = (spec.turboSpeed :: number?) or self.config.turboSpeed
	self.config.verticalSpeed = (spec.verticalSpeed :: number?) or self.config.verticalSpeed
	self.config.accelRate     = (spec.accelRate :: number?) or self.config.accelRate
	self.config.decelRate     = (spec.decelRate :: number?) or self.config.decelRate
	self.config.brakeRate     = (spec.brakeRate :: number?) or self.config.brakeRate
	self.config.tiltAngle     = (spec.tiltAngle :: number?) or self.config.tiltAngle
	print(string.format("[DroneController] Spec aplicada: %s | HP:%d | Calor:%d | Vel:%.0f",
		tostring(spec.name), self.maxHealth, self.maxHeat, self.config.cruiseSpeed))
end

----------------------------------------------------------------------
-- GESTIÓN DE MISILES GUIADOS [R]
----------------------------------------------------------------------
function DroneController:FireMissile()
	if not self.isFlying then return end
	if self.isEMPed then return end

	local now = os.clock()
	if now - (self.lastMissileFire or 0) < (self.missileCooldown or 1.0) then return end

	if (self.missilesRemaining or 0) <= 0 then
		if self.hud and (self.hud :: any).ShowHint then
			pcall(function()
				(self.hud :: any):ShowHint("¡SIN MISILES! Haz 3 entregas o recarga en Base con [M] (150 ₵)", true)
			end)
		end
		return
	end

	if not self.lockedTarget or not self.lockedTarget.Parent then
		if self.hud and (self.hud :: any).ShowHint then
			pcall(function()
				(self.hud :: any):ShowHint("¡SIN OBJETIVO FIJADO! Centra la mira sobre un dron hostil.", true)
			end)
		end
		return
	end

	self.lastMissileFire = now
	self.missilesRemaining = math.max(0, (self.missilesRemaining or 3) - 1)

	if self.hud and (self.hud :: any).SetMissilesDisplay then
		pcall(function()
			(self.hud :: any):SetMissilesDisplay(self.missilesRemaining, self.maxMissiles or 3)
		end)
	end

	local originPos = self.rootPart.Position + Vector3.new(0, 1.2, 0)
	local targetPart = self.lockedTarget
	local targetPos = targetPart.Position

	-- Simulación de proyectil local inmediata con feedback visual y curva Bézier
	self:SpawnLocalMissile(originPos, targetPart)

	-- Sonido de lanzamiento de cohete pesado
	local launchSound = Instance.new("Sound")
	launchSound.SoundId = "rbxassetid://9114223400"
	launchSound.Volume = 2.0
	launchSound.PlaybackSpeed = 1.35
	launchSound.Parent = self.rootPart
	launchSound:Play()
	Debris:AddItem(launchSound, 2)

	-- Notificar servidor para autorizar trayectoria y daño
	local onFireEv = self:GetRemoteEvent("OnFireWeapon")
	if onFireEv then
		onFireEv:FireServer({
			weaponId   = "smart_gyro_lock",
			origin     = originPos,
			target     = targetPos,
			targetPart = targetPart,
		})
	end
end

function DroneController:SpawnLocalMissile(startPos: Vector3, targetPart: BasePart)
	local missile = Instance.new("Part")
	missile.Name = "LocalSmartMissile"
	missile.Size = Vector3.new(0.4, 0.4, 2.0)
	missile.Material = Enum.Material.Neon
	missile.Color = Color3.fromRGB(255, 120, 0)
	missile.CanCollide = false
	missile.CastShadow = false
	missile.Massless = true
	missile.CFrame = CFrame.lookAt(startPos, startPos + Vector3.new(0, 5, 0))
	missile.Parent = Workspace
	Debris:AddItem(missile, 3.5)

	-- Estela de humo / propulsión
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 140, 20))
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	pe.Lifetime = NumberRange.new(0.25, 0.45)
	pe.Rate = 90
	pe.Speed = NumberRange.new(8, 15)
	pe.LightEmission = 1
	pe.Parent = missile

	local duration = math.clamp((targetPart.Position - startPos).Magnitude / 90, 0.4, 2.8)
	local elapsed = 0
	local initialPos = startPos
	local prevPos = startPos
	local ctrlOffset = Vector3.new(0, 18, 0) + self.rootPart.CFrame.RightVector * math.random(-8, 8)

	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt: number)
		elapsed += dt
		local t = math.clamp(elapsed / duration, 0, 1)
		local currentTargetPos = if targetPart and targetPart.Parent then targetPart.Position else initialPos + Vector3.new(0, 20, 100)
		local ctrl = (initialPos + currentTargetPos) / 2 + ctrlOffset

		-- Curva Bézier cuadrática de seguimiento guiado
		local pos = (1 - t)^2 * initialPos + 2 * (1 - t) * t * ctrl + t^2 * currentTargetPos
		local nextT = math.clamp(t + 0.05, 0, 1)
		local nextPos = (1 - nextT)^2 * initialPos + 2 * (1 - nextT) * nextT * ctrl + nextT^2 * currentTargetPos

		-- Comprobar colisión estricta en tiempo real contra torres y obstáculos del mundo
		local seg = pos - prevPos
		if seg.Magnitude > 0.05 then
			local mParams = RaycastParams.new()
			mParams.FilterType = Enum.RaycastFilterType.Exclude
			local lp = Players.LocalPlayer
			local mExclude = { self.rootPart, missile }
			if lp and lp.Character then table.insert(mExclude, lp.Character) end
			mParams.FilterDescendantsInstances = mExclude

			local mHit = Workspace:Raycast(prevPos, seg, mParams)
			if mHit and mHit.Instance then
				local hitObj = mHit.Instance
				-- Si golpeó una torre, pared, helipuerto o edificio, detonar inmediatamente
				conn:Disconnect()
				if missile.Parent then
					local boom = Instance.new("Part")
					boom.Shape = Enum.PartType.Ball
					boom.Size = Vector3.new(9, 9, 9)
					boom.Position = mHit.Position
					boom.Material = Enum.Material.Neon
					boom.Color = Color3.fromRGB(255, 120, 20)
					boom.CanCollide = false
					boom.Anchored = true
					boom.Parent = Workspace
					Debris:AddItem(boom, 0.2)
					missile:Destroy()
				end
				return
			end
		end
		prevPos = pos

		if (nextPos - pos).Magnitude > 0.01 then
			missile.CFrame = CFrame.lookAt(pos, nextPos)
		else
			missile.Position = pos
		end

		if t >= 1 then
			conn:Disconnect()
			if missile.Parent then
				-- Destello y explosión local al alcanzar el objetivo
				local boom = Instance.new("Part")
				boom.Shape = Enum.PartType.Ball
				boom.Size = Vector3.new(8, 8, 8)
				boom.Position = currentTargetPos
				boom.Material = Enum.Material.Neon
				boom.Color = Color3.fromRGB(255, 100, 20)
				boom.CanCollide = false
				boom.Anchored = true
				boom.Parent = Workspace
				Debris:AddItem(boom, 0.15)
				missile:Destroy()
			end
		end
	end)
end

function DroneController:ReloadMissiles(count: number, reason: string)
	self.missilesRemaining = math.clamp(count or 3, 0, self.maxMissiles or 3)
	if self.hud and (self.hud :: any).SetMissilesDisplay then
		pcall(function()
			(self.hud :: any):SetMissilesDisplay(self.missilesRemaining, self.maxMissiles or 3)
		end)
	end
	if self.hud and (self.hud :: any).ShowHint then
		pcall(function()
			(self.hud :: any):ShowHint(string.format("¡3 MISILES GUIADOS REABASTECIDOS! (%s)", reason), false)
		end)
	end
	-- Sonido de reabastecimiento en hangar
	local reloadSfx = Instance.new("Sound")
	reloadSfx.SoundId = "rbxassetid://9114223170"
	reloadSfx.Volume = 1.3
	reloadSfx.PlaybackSpeed = 1.1
	reloadSfx.Parent = self.rootPart
	reloadSfx:Play()
	Debris:AddItem(reloadSfx, 2)
	print(string.format("[DroneController] Misiles reabastecidos al 100%% (%s).", reason))
end

----------------------------------------------------------------------
-- GESTIÓN DE DESTRUCCIÓN Y RESPAWN LIMPIO EN BASE CENTRAL
----------------------------------------------------------------------
function DroneController:SetOnDestroyedCallback(callback: () -> ())
	self.onDestroyedCallback = callback
end

function DroneController:ResetOnDestroyed()
	print("[DroneController] ResetOnDestroyed() llamado - restaurando estado a 100%")
	self:StopFlying()
	self.currentHealth = self.maxHealth
	self.currentHeat   = 0
	self.isEMPed       = false
	self.isWeaponOverheated = false
	self.lockedTarget  = nil
	self.currentVelocity = Vector3.zero

	if self.linearVelocity then
		self.linearVelocity.VectorVelocity = Vector3.zero
	end
	if self.alignOrientation then
		self.alignOrientation.CFrame = self.rootPart.CFrame
	end

	pcall(function()
		self.rootPart.AssemblyLinearVelocity = Vector3.zero
		self.rootPart.AssemblyAngularVelocity = Vector3.zero
		self.rootPart.Anchored = true
		self.rootPart.CFrame = CFrame.new(0, 6.2, 0)
	end)

	if self.cargo and (self.cargo :: any).RestockAtBase then
		pcall(function() (self.cargo :: any):RestockAtBase() end)
	end

	if self.deliveryManager then
		pcall(function()
			(self.deliveryManager :: any).packagesRemaining = 3
			(self.deliveryManager :: any).isLanded = false
			(self.deliveryManager :: any).touchdownTimer = 0
			if (self.deliveryManager :: any).PickNextTarget then
				(self.deliveryManager :: any):PickNextTarget("Pad_Base")
			end
		end)
	end

	if self.hud then
		pcall(function()
			if (self.hud :: any).SetHealthDisplay then
				(self.hud :: any):SetHealthDisplay(1.0)
			end
			if (self.hud :: any).SetHeatDisplay then
				(self.hud :: any):SetHeatDisplay(0.0)
			end
			if (self.hud :: any).SetTargetLock then
				(self.hud :: any):SetTargetLock(nil)
			end
			if (self.hud :: any).ShowHint then
				(self.hud :: any):ShowHint("¡DRON RECONSTRUIDO EN BASE CENTRAL!", false)
			end
		end)
	end
end

----------------------------------------------------------------------
-- DESTRUCTOR Y LIMPIEZA UNIFICADA DE RECURSOS
----------------------------------------------------------------------
function DroneController:Destroy()
	self:StopFlying()
	if self.hud and self.hud.Destroy then
		pcall(function() self.hud:Destroy() end)
		self.hud = nil
	end
	if self.audio and self.audio.Destroy then
		pcall(function() self.audio:Destroy() end)
		self.audio = nil
	end
	if self.vfx and self.vfx.Destroy then
		pcall(function() self.vfx:Destroy() end)
		self.vfx = nil
	end
	if self.cargo and self.cargo.Destroy then
		pcall(function() self.cargo:Destroy() end)
		self.cargo = nil
	end
	if self.deliveryManager and self.deliveryManager.Destroy then
		pcall(function() self.deliveryManager:Destroy() end)
		self.deliveryManager = nil
	end
	print("[DroneController] Instancia destruida y recursos liberados.")
end

return DroneController
