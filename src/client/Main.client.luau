--!strict
-- src/client/Main.client.luau
-- v5.0 - Fix definitivo: gpe eliminado en tecla E, carga robusta, debug completo
print("[CLIENTE v5] Main.client.luau iniciando...")

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local Workspace          = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

----------------------------------------------------------------------
-- 1. BOTÓN HOLOGRÁFICO (creado INMEDIATAMENTE, antes de cualquier carga)
----------------------------------------------------------------------
local toggleGui = Instance.new("ScreenGui")
toggleGui.Name           = "DroneQuickToggleGui"
toggleGui.ResetOnSpawn   = false
toggleGui.IgnoreGuiInset = true
toggleGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
toggleGui.Parent         = playerGui

local toggleBtn = Instance.new("TextButton")
toggleBtn.Name                  = "ToggleFPVButton"
toggleBtn.Size                  = UDim2.fromOffset(380, 50)
toggleBtn.AnchorPoint           = Vector2.new(0.5, 1)
toggleBtn.Position              = UDim2.new(0.5, 0, 1, -28)
toggleBtn.BackgroundColor3      = Color3.fromRGB(12, 18, 28)
toggleBtn.BackgroundTransparency = 0.15
toggleBtn.BorderSizePixel       = 0
toggleBtn.Font                  = Enum.Font.Code
toggleBtn.Text                  = "[INICIANDO SISTEMA...]"
toggleBtn.TextColor3            = Color3.fromRGB(180, 180, 180)
toggleBtn.TextSize              = 14
toggleBtn.AutoButtonColor       = false
toggleBtn.Parent                = toggleGui

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 8)
btnCorner.Parent       = toggleBtn

local btnStroke = Instance.new("UIStroke")
btnStroke.Name      = "BtnStroke"
btnStroke.Color     = Color3.fromRGB(80, 80, 80)
btnStroke.Thickness = 2
btnStroke.Parent    = toggleBtn

-- Debug label (esquina superior izquierda)
local debugLabel = Instance.new("TextLabel")
debugLabel.Name                  = "DebugLabel"
debugLabel.Size                  = UDim2.new(0, 600, 0, 22)
debugLabel.Position              = UDim2.new(0, 8, 0, 8)
debugLabel.BackgroundTransparency = 1
debugLabel.Font                  = Enum.Font.Code
debugLabel.Text                  = "[DBG] Iniciando..."
debugLabel.TextColor3            = Color3.fromRGB(0, 255, 180)
debugLabel.TextSize              = 12
debugLabel.TextXAlignment        = Enum.TextXAlignment.Left
debugLabel.Parent                = toggleGui

local function dbg(msg: string)
	debugLabel.Text = "[DBG] " .. msg
	print("[CLIENTE DBG]", msg)
end

local function setBtn(text: string, r: number, g: number, b: number)
	toggleBtn.Text       = text
	toggleBtn.TextColor3 = Color3.fromRGB(r, g, b)
	btnStroke.Color      = Color3.fromRGB(r, g, b)
end

----------------------------------------------------------------------
-- 2. ESTADO GLOBAL
----------------------------------------------------------------------
local isPiloting           = false
local myDrone: any         = nil   -- DroneController instance
local droneReady           = false
local DroneController: any = nil
local CyberGoggles: any    = nil

local lastPilotToggleTime  = 0
local PILOT_TOGGLE_COOLDOWN = 0.5 -- Cooldown en segundos para prevenir rebotes de tecla o dobles eventos

local function isCurrentlyPiloting(): boolean
	return isPiloting or (myDrone and (myDrone :: any).isFlying == true)
end

----------------------------------------------------------------------
-- 3. INICIALIZACIÓN Y FUNCIONES DE VUELO
----------------------------------------------------------------------
local exitDrone: () -> ()
local initializeDrone: () -> boolean

local function setupDroneCallbacks()
	if not myDrone then return end

	-- Sincronización bidireccional de estado de vuelo
	if (myDrone :: any).SetOnStateChangedCallback then
		(myDrone :: any):SetOnStateChangedCallback(function(flying: boolean)
			isPiloting = flying
			if flying then
				setBtn("[F] DESCONECTAR VISOR FPV", 255, 220, 0)
			else
				setBtn("[E] CONECTAR GAFAS FPV (PILOTAR DRON)", 0, 255, 230)
			end
		end)
	end

	-- Callback de auto-recuperación cuando el dron es destruido en combate
	if (myDrone :: any).SetOnDestroyedCallback then
		(myDrone :: any):SetOnDestroyedCallback(function()
			dbg("Dron destruido en combate - sincronizando interfaz a modo caminante...")
			if isCurrentlyPiloting() then
				exitDrone()
			end
		end)
	end
end

function initializeDrone(): boolean
	if droneReady and myDrone ~= nil then return true end

	dbg("Buscando TestDrone en Workspace...")
	local droneEntity = Workspace:FindFirstChild("TestDrone") or Workspace:WaitForChild("TestDrone", 8) :: Instance?
	if not droneEntity then
		warn("[CLIENTE] TestDrone no encontrado en Workspace tras 8s")
		dbg("ERROR: TestDrone no encontrado en Workspace")
		setBtn("ERROR: TestDrone no encontrado", 255, 80, 80)
		return false
	end

	dbg("Cargando módulo DroneController...")
	local mod = ReplicatedStorage:FindFirstChild("DroneController") or ReplicatedStorage:WaitForChild("DroneController", 8) :: Instance?
	if not mod or not mod:IsA("ModuleScript") then
		warn("[CLIENTE] Módulo DroneController no encontrado en ReplicatedStorage tras 8s")
		dbg("ERROR: DroneController no encontrado en ReplicatedStorage")
		setBtn("ERROR: DroneController no encontrado", 255, 80, 80)
		return false
	end

	local okCtrl, ctrlMod = pcall(function()
		return require(mod :: ModuleScript)
	end)
	if not okCtrl or not ctrlMod then
		local errStr = tostring(ctrlMod)
		warn("[CLIENTE] DroneController falló al requerir:", errStr)
		dbg("ERR require: " .. errStr:sub(1, 40))
		setBtn("ERR require: " .. errStr:sub(1, 26), 255, 80, 80)
		return false
	end
	DroneController = ctrlMod

	dbg("Creando instancia DroneController.new()...")
	local okNew, newResult = pcall(function()
		return DroneController.new(droneEntity)
	end)
	if not okNew or not newResult then
		warn("[CLIENTE] DroneController.new() falló:", newResult)
		dbg("ERROR new(): " .. tostring(newResult):sub(1, 40))
		setBtn("ERROR new(): " .. tostring(newResult):sub(1, 25), 255, 80, 80)
		return false
	end

	myDrone = newResult
	droneReady = true
	dbg("¡DRON LISTO! Presiona E para pilotar.")
	setBtn("[E] CONECTAR GAFAS FPV (PILOTAR DRON)", 0, 255, 230)
	print("[CLIENTE] ¡DroneController completamente listo!")

	setupDroneCallbacks()
	return true
end

local function enterDrone()
	if isCurrentlyPiloting() then return end
	if os.clock() - lastPilotToggleTime < PILOT_TOGGLE_COOLDOWN then return end
	lastPilotToggleTime = os.clock()

	if not droneReady or myDrone == nil then
		dbg("Dron cargando... forzando inicialización ahora...")
		setBtn("[E] INICIALIZANDO DRON...", 255, 200, 0)
		if not initializeDrone() then
			return
		end
	end

	dbg("Iniciando vuelo FPV...")
	isPiloting = true
	setBtn("[F] DESCONECTAR VISOR FPV", 255, 220, 0)

	-- Ocultar prompt diegético localmente de inmediato mientras vuela
	local dronePart = Workspace:FindFirstChild("TestDrone")
	if dronePart then
		local prompt = dronePart:FindFirstChild("PilotPrompt") :: ProximityPrompt?
		if prompt then prompt.Enabled = false end
	end

	-- Activar gafas en avatar
	local char = localPlayer.Character
	if char and CyberGoggles then
		pcall(function() CyberGoggles.SetOnline(char, true) end)
	end

	-- Iniciar vuelo
	local ok, err = pcall(function() myDrone:StartFlying() end)
	if not ok then
		warn("[CLIENTE] Error en StartFlying:", err)
		isPiloting = false
		setBtn("[E] ERROR AL VOLAR - REINTENTA", 255, 80, 80)
		if dronePart then
			local prompt = dronePart:FindFirstChild("PilotPrompt") :: ProximityPrompt?
			if prompt then prompt.Enabled = true end
		end
	else
		dbg("Vuelo FPV activo! WASD=mover Space=subir Shift/C=bajar Q=turbo X=freno G=entregar V=FPV")
	end
end

function exitDrone()
	if not isCurrentlyPiloting() then return end
	if os.clock() - lastPilotToggleTime < PILOT_TOGGLE_COOLDOWN then return end
	lastPilotToggleTime = os.clock()

	isPiloting = false

	dbg("Desconectando visor FPV...")
	setBtn("[E] CONECTAR GAFAS FPV (PILOTAR DRON)", 0, 255, 230)

	-- Restaurar visibilidad del prompt diegético localmente
	local dronePart = Workspace:FindFirstChild("TestDrone")
	if dronePart then
		local prompt = dronePart:FindFirstChild("PilotPrompt") :: ProximityPrompt?
		if prompt then prompt.Enabled = true end
	end

	local char = localPlayer.Character
	if char and CyberGoggles then
		pcall(function() CyberGoggles.SetOnline(char, false) end)
	end
	if myDrone then
		pcall(function() myDrone:StopFlying() end)
	end
end

-- Click en botón inferior
toggleBtn.MouseButton1Click:Connect(function()
	if not isCurrentlyPiloting() then
		enterDrone()
	else
		exitDrone()
	end
end)

-- Interacción con ProximityPrompt 3D [E] en el mundo
local ProximityPromptService = game:GetService("ProximityPromptService")
ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeredPlayer)
	if prompt.Name == "PilotPrompt" then
		-- En LocalScripts, triggeredPlayer es nil (o localPlayer según versión de motor)
		if triggeredPlayer == nil or triggeredPlayer == localPlayer then
			if not isCurrentlyPiloting() then
				enterDrone()
			end
		end
	end
end)

----------------------------------------------------------------------
-- GESTIÓN DE ENTRADA POR TECLADO
-- Tecla [E] dedicada a entrar (no cancela ni alterna). Tecla [F] para salir.
----------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input: InputObject, _gpe: boolean)
	-- Solo ignorar si el usuario está tipeando en el chat o en un TextBox con foco
	local focused = UserInputService:GetFocusedTextBox()
	if focused then return end

	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

	if input.KeyCode == Enum.KeyCode.E then
		-- Tecla E: Siempre activar entrada a pilotaje si no está volando
		if not isCurrentlyPiloting() then
			enterDrone()
		end
	elseif input.KeyCode == Enum.KeyCode.F then
		-- Tecla F designada explícitamente para salir del modo vuelo FPV
		if isCurrentlyPiloting() then
			exitDrone()
		end
	end
end)

----------------------------------------------------------------------
-- 4. TAREAS ASÍNCRONAS EN PARALELO (NO BLOQUEANTES)
----------------------------------------------------------------------

-- Tarea A: Inicialización del Dron al arrancar
task.spawn(function()
	initializeDrone()
end)

-- Tarea B: Conexión defensiva directa al ProximityPrompt de TestDrone
task.spawn(function()
	local droneEntity = Workspace:FindFirstChild("TestDrone") or Workspace:WaitForChild("TestDrone", 8)
	if droneEntity then
		local prompt = droneEntity:FindFirstChild("PilotPrompt") or droneEntity:WaitForChild("PilotPrompt", 5) :: ProximityPrompt?
		if prompt then
			prompt.Triggered:Connect(function(triggeredPlayer)
				if triggeredPlayer == nil or triggeredPlayer == localPlayer then
					if not isCurrentlyPiloting() then
						enterDrone()
					end
				end
			end)
		end
	end
end)

-- Tarea C: Gafas Cibernéticas FPV y avatar
task.spawn(function()
	local okGoggles, gogglesResult = pcall(function()
		local mod = ReplicatedStorage:FindFirstChild("CyberGoggles") or ReplicatedStorage:WaitForChild("CyberGoggles", 5)
		return require(mod :: ModuleScript)
	end)
	if okGoggles and gogglesResult then
		CyberGoggles = gogglesResult
	end

	local function onCharacterReset()
		isPiloting = false
		if myDrone and (myDrone :: any).isFlying then
			pcall(function() (myDrone :: any):StopFlying() end)
		end
		setBtn("[E] CONECTAR GAFAS FPV (PILOTAR DRON)", 0, 255, 230)
	end

	local function setupGoggles(char: Model)
		if CyberGoggles then
			pcall(function() CyberGoggles.Attach(char) end)
		end
		local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 4) :: Humanoid?
		if hum then
			hum.Died:Connect(onCharacterReset)
		end
	end

	if localPlayer.Character then setupGoggles(localPlayer.Character) end
	localPlayer.CharacterAdded:Connect(function(char)
		onCharacterReset()
		setupGoggles(char)
	end)
end)

-- Tarea D: Suscripción a eventos de red (RemoteEvents)
task.spawn(function()
	local neMod = ReplicatedStorage:FindFirstChild("NetworkEvents") or ReplicatedStorage:WaitForChild("NetworkEvents", 8)
	if not neMod then return end

	local okNet, NetworkEvents = pcall(function()
		return require(neMod :: ModuleScript)
	end)
	if not okNet or not NetworkEvents then return end

	local flightEvent    = NetworkEvents.Get(NetworkEvents.Names.DroneFlightState)
	local destroyedEv    = NetworkEvents.Get(NetworkEvents.Names.DroneDestroyed)
	local onDmg          = NetworkEvents.Get(NetworkEvents.Names.OnDamageTaken)
	local onEMP          = NetworkEvents.Get(NetworkEvents.Names.OnEMPActivated)
	local onHeat         = NetworkEvents.Get(NetworkEvents.Names.OnHeatUpdate)
	local onBounty       = NetworkEvents.Get(NetworkEvents.Names.OnBountyAwarded)
	local buyConfirmed   = NetworkEvents.Get(NetworkEvents.Names.BuyMissilesConfirmed)

	local function handleServerStopFlight()
		dbg("Servidor ordenó StopFlying / DroneDestroyed - reseteando a Base Central")
		if isCurrentlyPiloting() then
			exitDrone()
		end
		if myDrone and (myDrone :: any).ResetOnDestroyed then
			pcall(function() (myDrone :: any):ResetOnDestroyed() end)
		end
	end

	if flightEvent then
		flightEvent.OnClientEvent:Connect(function(action: any)
			if action == "EnterDrone" then
				dbg("Servidor autorizó EnterDrone - iniciando vuelo...")
				if not isCurrentlyPiloting() then
					enterDrone()
				end
			elseif action == "StopFlying" or action == "DroneDestroyed" then
				handleServerStopFlight()
			end
		end)
	end

	if destroyedEv then
		destroyedEv.OnClientEvent:Connect(handleServerStopFlight)
	end

	if onDmg then
		onDmg.OnClientEvent:Connect(function(damageData: any)
			if myDrone then pcall(function() myDrone:ApplyDamage(damageData) end) end
		end)
	end

	if onEMP then
		onEMP.OnClientEvent:Connect(function(dur: number)
			if myDrone then pcall(function() myDrone:TriggerEMPLocal(dur) end) end
		end)
	end

	if onHeat then
		onHeat.OnClientEvent:Connect(function(heatAmt: number)
			if myDrone then pcall(function() myDrone:ApplyHeat(heatAmt) end) end
		end)
	end

	if onBounty then
		onBounty.OnClientEvent:Connect(function(data: any)
			if myDrone and myDrone.hud then
				local bounty = if typeof(data) == "table" then data.bounty else (data or 35)
				pcall(function()
					myDrone.hud:ShowHint(string.format("¡HOSTIL NEUTRALIZADO! +%d PELAOCOINS 💰", bounty), false)
				end)
			end
		end)
	end

	if buyConfirmed then
		buyConfirmed.OnClientEvent:Connect(function(count: number)
			if myDrone and (myDrone :: any).ReloadMissiles then
				(myDrone :: any):ReloadMissiles(count or 3, "compra")
			end
		end)
	end
end)
