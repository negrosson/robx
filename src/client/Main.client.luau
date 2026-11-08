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
local isPiloting        = false
local myDrone: any      = nil   -- DroneController instance
local droneReady        = false
local DroneController: any = nil
local CyberGoggles: any    = nil

local function isCurrentlyPiloting(): boolean
	return isPiloting or (myDrone and (myDrone :: any).isFlying == true)
end

----------------------------------------------------------------------
-- 3. FUNCIONES DE VUELO
----------------------------------------------------------------------
local function enterDrone()
	if isCurrentlyPiloting() then return end

	if not droneReady or myDrone == nil then
		dbg("Dron NO listo aún, espera...")
		setBtn("[E] CARGANDO DRON... ESPERA", 255, 200, 0)
		return
	end

	dbg("Iniciando vuelo FPV...")
	isPiloting = true
	setBtn("[F] DESCONECTAR VISOR FPV", 255, 220, 0)

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
	else
		dbg("Vuelo FPV activo! WASD=mover Space=subir Shift/C=bajar Q=turbo X=freno G=entregar V=FPV")
	end
end

local function exitDrone()
	if not isCurrentlyPiloting() then return end
	isPiloting = false

	dbg("Desconectando visor FPV...")
	setBtn("[E] CONECTAR GAFAS FPV (PILOTAR DRON)", 0, 255, 230)

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
	if not isCurrentlyPiloting() then enterDrone() else exitDrone() end
end)

-- Interacción con ProximityPrompt 3D [E] en el mundo
local ProximityPromptService = game:GetService("ProximityPromptService")
ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
	if player == localPlayer and prompt.Name == "PilotPrompt" then
		if not isCurrentlyPiloting() then
			enterDrone()
		end
	end
end)

----------------------------------------------------------------------
-- FIX CRÍTICO: Tecla E sin filtro gpe para permitir captura siempre.
-- Se sincroniza con isCurrentlyPiloting() para evitar desfasajes.
----------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input: InputObject, gpe: boolean)
	-- Solo bloquear si está escribiendo en el chat (TextBox con foco)
	if gpe then
		local focused = UserInputService:GetFocusedTextBox()
		if focused then return end
	end

	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

	if input.KeyCode == Enum.KeyCode.E then
		if not isCurrentlyPiloting() then
			enterDrone()
		else
			exitDrone()
		end
	elseif input.KeyCode == Enum.KeyCode.F then
		if isCurrentlyPiloting() then
			exitDrone()
		end
	end
end)

----------------------------------------------------------------------
-- 4. CARGA ASÍNCRONA (task.spawn = no bloquea UI)
----------------------------------------------------------------------
task.spawn(function()
	dbg("Esperando que el servidor inicialice ReplicatedStorage...")

	-- Esperar NetworkEvents primero (indica que el servidor corrió)
	local neModule = ReplicatedStorage:WaitForChild("NetworkEvents", 30)
	if not neModule then
		warn("[CLIENTE] TIMEOUT esperando NetworkEvents - servidor no inició")
		setBtn("ERROR: Servidor no respondió", 255, 80, 80)
		return
	end
	dbg("NetworkEvents OK")

	-- Lista de módulos que DEBEN existir en ReplicatedStorage
	local rsModules = {
		"DroneController",
		"DroneHUD",
		"DroneAudio",
		"DroneVFX",
		"DroneCargo",
		"DeliveryManager",
		"CyberGoggles",
	}

	for _, modName in rsModules do
		local child = ReplicatedStorage:WaitForChild(modName, 15)
		if not child then
			warn("[CLIENTE] TIMEOUT esperando módulo:", modName)
			setBtn("ERROR: falta " .. modName, 255, 80, 80)
			return
		end
		dbg("OK: " .. modName)
	end

	-- Cargar CyberGoggles
	local okGoggles, gogglesResult = pcall(function()
		return require(ReplicatedStorage:WaitForChild("CyberGoggles", 5) :: ModuleScript)
	end)
	if okGoggles then
		CyberGoggles = gogglesResult
		dbg("CyberGoggles cargado OK")
	else
		warn("[CLIENTE] CyberGoggles falló:", gogglesResult)
	end

	-- Equipar gafas en avatar actual y futuros spawns, y conectar reseteo de muerte
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
		local hum = char:WaitForChild("Humanoid", 5) :: Humanoid?
		if hum then
			hum.Died:Connect(onCharacterReset)
		end
	end

	if localPlayer.Character then setupGoggles(localPlayer.Character) end
	localPlayer.CharacterAdded:Connect(function(char)
		onCharacterReset()
		setupGoggles(char)
	end)

	-- Cargar DroneController
	local okCtrl, ctrlResult = pcall(function()
		return require(ReplicatedStorage:WaitForChild("DroneController", 5) :: ModuleScript)
	end)
	if not okCtrl then
		warn("[CLIENTE] DroneController no cargó:", ctrlResult)
		setBtn("ERROR DroneController", 255, 80, 80)
		return
	end
	DroneController = ctrlResult
	dbg("DroneController módulo OK")

	-- Esperar el dron en Workspace — con reintentos cada segundo hasta 30s
	dbg("Esperando TestDrone en Workspace...")
	local droneEntity: Instance? = nil
	local waitStart = os.clock()
	while os.clock() - waitStart < 30 do
		droneEntity = Workspace:FindFirstChild("TestDrone")
		if droneEntity then break end
		task.wait(0.5)
	end

	if not droneEntity then
		warn("[CLIENTE] TestDrone no encontrado en Workspace tras 30s!")
		setBtn("ERROR: TestDrone no encontrado", 255, 80, 80)
		return
	end
	dbg("TestDrone encontrado: " .. droneEntity:GetFullName())

	-- Resolver eventos de red canónicos mediante NetworkEvents
	local NetworkEvents = require(neModule :: ModuleScript)
	local flightEvent   = NetworkEvents.Get(NetworkEvents.Names.DroneFlightState)
	local destroyedEv   = NetworkEvents.Get(NetworkEvents.Names.DroneDestroyed)
	local onDmg         = NetworkEvents.Get(NetworkEvents.Names.OnDamageTaken)
	local onEMP         = NetworkEvents.Get(NetworkEvents.Names.OnEMPActivated)
	local onHeat        = NetworkEvents.Get(NetworkEvents.Names.OnHeatUpdate)
	local onBounty      = NetworkEvents.Get(NetworkEvents.Names.OnBountyAwarded)
	local buyConfirmed  = NetworkEvents.Get(NetworkEvents.Names.BuyMissilesConfirmed)

	-- Crear instancia del controlador (con timeout de protección)
	dbg("Creando DroneController.new()...")
	local okNew, newResult = pcall(function()
		return DroneController.new(droneEntity)
	end)
	if not okNew then
		warn("[CLIENTE] DroneController.new() falló:", newResult)
		setBtn("ERROR new(): " .. tostring(newResult):sub(1, 40), 255, 80, 80)
		return
	end

	myDrone    = newResult
	droneReady = true
	dbg("¡DRON LISTO! Presiona E para pilotar.")
	setBtn("[E] CONECTAR GAFAS FPV (PILOTAR DRON)", 0, 255, 230)
	print("[CLIENTE v5] ¡Sistema de vuelo completamente inicializado!")

	-- Sincronización bidireccional de estado de vuelo
	if myDrone and (myDrone :: any).SetOnStateChangedCallback then
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
	if myDrone and (myDrone :: any).SetOnDestroyedCallback then
		(myDrone :: any):SetOnDestroyedCallback(function()
			dbg("Dron destruido en combate - sincronizando interfaz a modo caminante...")
			if isCurrentlyPiloting() then
				exitDrone()
			end
		end)
	end

	-- Listener de desconexión y destrucción emitida por el servidor
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
			if action == "StopFlying" or action == "DroneDestroyed" then
				handleServerStopFlight()
			end
		end)
	end

	if destroyedEv then
		destroyedEv.OnClientEvent:Connect(function()
			handleServerStopFlight()
		end)
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
