--!strict
-- src/shared/DroneHUD.luau
-- Interfaz de Vuelo Holográfica Cyberpunk Completa
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local DroneHUD = {}
DroneHUD.__index = DroneHUD

export type HUDInstance = {
	screenGui: ScreenGui,
	speedLabel: TextLabel,
	speedFill: Frame,
	turboFill: Frame,
	altLabel: TextLabel,
	warningLabel: TextLabel,
	camLabel: TextLabel,
	brakeIndicator: TextLabel,
	crosshair: Frame,
	horizonLine: Frame,
	waypointMarker: Frame,
	waypointLabel: TextLabel,
	missionBox: Frame,
	missionTargetLabel: TextLabel,
	missionRewardLabel: TextLabel,
	cargoStatusLabel: TextLabel,
	landingBar: Frame,
	landingFill: Frame,
	successPopup: Frame,
	successText: TextLabel,
}

local COLOR_BG = Color3.fromRGB(8, 14, 24)
local COLOR_BORDER = Color3.fromRGB(0, 240, 255)
local COLOR_NEON_CYAN = Color3.fromRGB(0, 255, 240)
local COLOR_NEON_PINK = Color3.fromRGB(255, 30, 120)
local COLOR_NEON_YELLOW = Color3.fromRGB(255, 215, 0)
local COLOR_WARN = Color3.fromRGB(255, 70, 70)
local COLOR_TEXT_MUTED = Color3.fromRGB(140, 180, 200)

local DEFAULT_CURRENCY_NAME = "PIGICOINS"

local function getCurrencyName(): string
	local player = Players.LocalPlayer
	if player then
		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats then
			for _, child in ipairs(leaderstats:GetChildren()) do
				if child:IsA("IntValue") and child.Name ~= "Entregas" then
					return child.Name
				end
			end
		end
	end
	return DEFAULT_CURRENCY_NAME
end

function DroneHUD.new(): HUDInstance
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	local existing = playerGui:FindFirstChild("CyberDroneHUD")
	if existing then
		existing:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CyberDroneHUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	local mainContainer = Instance.new("Frame")
	mainContainer.Name = "MainContainer"
	mainContainer.Size = UDim2.fromScale(1, 1)
	mainContainer.BackgroundTransparency = 1
	mainContainer.Parent = screenGui

	----------------------------------------------------------------------
	-- 1. RETÍCULA Y MIRA CENTRAL
	----------------------------------------------------------------------
	local crosshairContainer = Instance.new("Frame")
	crosshairContainer.Name = "CrosshairContainer"
	crosshairContainer.Size = UDim2.fromOffset(80, 80)
	crosshairContainer.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshairContainer.Position = UDim2.fromScale(0.5, 0.5)
	crosshairContainer.BackgroundTransparency = 1
	crosshairContainer.Parent = mainContainer

	local centerDot = Instance.new("Frame")
	centerDot.Size = UDim2.fromOffset(4, 4)
	centerDot.AnchorPoint = Vector2.new(0.5, 0.5)
	centerDot.Position = UDim2.fromScale(0.5, 0.5)
	centerDot.BackgroundColor3 = COLOR_NEON_CYAN
	centerDot.BorderSizePixel = 0
	centerDot.Parent = crosshairContainer

	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = centerDot

	local horizonLine = Instance.new("Frame")
	horizonLine.Name = "HorizonLine"
	horizonLine.Size = UDim2.fromOffset(60, 2)
	horizonLine.AnchorPoint = Vector2.new(0.5, 0.5)
	horizonLine.Position = UDim2.fromScale(0.5, 0.5)
	horizonLine.BackgroundColor3 = COLOR_NEON_CYAN
	horizonLine.BackgroundTransparency = 0.5
	horizonLine.BorderSizePixel = 0
	horizonLine.Parent = crosshairContainer

	local function createBracket(posX: number, text: string)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromOffset(16, 30)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(posX, 0.5)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.RobotoMono
		label.Text = text
		label.TextColor3 = COLOR_NEON_CYAN
		label.TextSize = 22
		label.Parent = crosshairContainer
	end
	createBracket(0.1, "[")
	createBracket(0.9, "]")

	local brakeIndicator = Instance.new("TextLabel")
	brakeIndicator.Name = "BrakeIndicator"
	brakeIndicator.Size = UDim2.fromOffset(180, 20)
	brakeIndicator.AnchorPoint = Vector2.new(0.5, 0)
	brakeIndicator.Position = UDim2.new(0.5, 0, 1, 15)
	brakeIndicator.BackgroundTransparency = 1
	brakeIndicator.Font = Enum.Font.RobotoMono
	brakeIndicator.Text = "FRENO AERODINÁMICO [X]"
	brakeIndicator.TextColor3 = COLOR_WARN
	brakeIndicator.TextSize = 12
	brakeIndicator.Visible = false
	brakeIndicator.Parent = crosshairContainer

	----------------------------------------------------------------------
	-- 2. PANEL VELOCÍMETRO & MEDIDOR DE TURBO NITRO [Q]
	----------------------------------------------------------------------
	local speedBox = Instance.new("Frame")
	speedBox.Name = "SpeedBox"
	speedBox.Size = UDim2.fromOffset(210, 105)
	speedBox.AnchorPoint = Vector2.new(0, 1)
	speedBox.Position = UDim2.new(0, 35, 1, -35)
	speedBox.BackgroundColor3 = COLOR_BG
	speedBox.BackgroundTransparency = 0.35
	speedBox.BorderSizePixel = 0
	speedBox.Parent = mainContainer

	local speedCorner = Instance.new("UICorner")
	speedCorner.CornerRadius = UDim.new(0, 6)
	speedCorner.Parent = speedBox

	local speedStroke = Instance.new("UIStroke")
	speedStroke.Color = COLOR_BORDER
	speedStroke.Thickness = 1.5
	speedStroke.Transparency = 0.2
	speedStroke.Parent = speedBox

	local speedHeader = Instance.new("TextLabel")
	speedHeader.Size = UDim2.new(1, -20, 0, 16)
	speedHeader.Position = UDim2.fromOffset(10, 8)
	speedHeader.BackgroundTransparency = 1
	speedHeader.Font = Enum.Font.RobotoMono
	speedHeader.Text = "SPD // IMPULSO CRUCERO"
	speedHeader.TextColor3 = COLOR_TEXT_MUTED
	speedHeader.TextSize = 11
	speedHeader.TextXAlignment = Enum.TextXAlignment.Left
	speedHeader.Parent = speedBox

	local speedLabel = Instance.new("TextLabel")
	speedLabel.Name = "SpeedLabel"
	speedLabel.Size = UDim2.new(1, -20, 0, 30)
	speedLabel.Position = UDim2.fromOffset(10, 24)
	speedLabel.BackgroundTransparency = 1
	speedLabel.Font = Enum.Font.Code
	speedLabel.Text = "000 STUDS/S"
	speedLabel.TextColor3 = COLOR_NEON_CYAN
	speedLabel.TextSize = 22
	speedLabel.TextXAlignment = Enum.TextXAlignment.Left
	speedLabel.Parent = speedBox

	-- Barra de velocidad
	local speedTrack = Instance.new("Frame")
	speedTrack.Size = UDim2.new(1, -20, 0, 5)
	speedTrack.Position = UDim2.fromOffset(10, 58)
	speedTrack.BackgroundColor3 = Color3.fromRGB(20, 30, 45)
	speedTrack.BorderSizePixel = 0
	speedTrack.Parent = speedBox

	local speedFill = Instance.new("Frame")
	speedFill.Name = "SpeedFill"
	speedFill.Size = UDim2.fromScale(0, 1)
	speedFill.BackgroundColor3 = COLOR_NEON_CYAN
	speedFill.BorderSizePixel = 0
	speedFill.Parent = speedTrack

	-- Barra de Nitro Turbo
	local turboLabel = Instance.new("TextLabel")
	turboLabel.Size = UDim2.new(1, -20, 0, 14)
	turboLabel.Position = UDim2.fromOffset(10, 68)
	turboLabel.BackgroundTransparency = 1
	turboLabel.Font = Enum.Font.RobotoMono
	turboLabel.Text = "NITRO TURBO [Q]"
	turboLabel.TextColor3 = COLOR_NEON_PINK
	turboLabel.TextSize = 10
	turboLabel.TextXAlignment = Enum.TextXAlignment.Left
	turboLabel.Parent = speedBox

	local turboTrack = Instance.new("Frame")
	turboTrack.Size = UDim2.new(1, -20, 0, 4)
	turboTrack.Position = UDim2.fromOffset(10, 85)
	turboTrack.BackgroundColor3 = Color3.fromRGB(20, 30, 45)
	turboTrack.BorderSizePixel = 0
	turboTrack.Parent = speedBox

	local turboFill = Instance.new("Frame")
	turboFill.Name = "TurboFill"
	turboFill.Size = UDim2.fromScale(1, 1)
	turboFill.BackgroundColor3 = COLOR_NEON_PINK
	turboFill.BorderSizePixel = 0
	turboFill.Parent = turboTrack

	----------------------------------------------------------------------
	-- 3. PANEL ALTÍMETRO Y RADAR
	----------------------------------------------------------------------
	local altBox = Instance.new("Frame")
	altBox.Name = "AltBox"
	altBox.Size = UDim2.fromOffset(200, 95)
	altBox.AnchorPoint = Vector2.new(1, 1)
	altBox.Position = UDim2.new(1, -35, 1, -35)
	altBox.BackgroundColor3 = COLOR_BG
	altBox.BackgroundTransparency = 0.35
	altBox.BorderSizePixel = 0
	altBox.Parent = mainContainer

	local altCorner = Instance.new("UICorner")
	altCorner.CornerRadius = UDim.new(0, 6)
	altCorner.Parent = altBox

	local altStroke = Instance.new("UIStroke")
	altStroke.Color = COLOR_BORDER
	altStroke.Thickness = 1.5
	altStroke.Transparency = 0.2
	altStroke.Parent = altBox

	local altHeader = Instance.new("TextLabel")
	altHeader.Size = UDim2.new(1, -20, 0, 16)
	altHeader.Position = UDim2.fromOffset(10, 8)
	altHeader.BackgroundTransparency = 1
	altHeader.Font = Enum.Font.RobotoMono
	altHeader.Text = "ALT // RADAR SUELO"
	altHeader.TextColor3 = COLOR_TEXT_MUTED
	altHeader.TextSize = 11
	altHeader.TextXAlignment = Enum.TextXAlignment.Right
	altHeader.Parent = altBox

	local altLabel = Instance.new("TextLabel")
	altLabel.Name = "AltLabel"
	altLabel.Size = UDim2.new(1, -20, 0, 32)
	altLabel.Position = UDim2.fromOffset(10, 24)
	altLabel.BackgroundTransparency = 1
	altLabel.Font = Enum.Font.Code
	altLabel.Text = "000.0 M"
	altLabel.TextColor3 = COLOR_NEON_CYAN
	altLabel.TextSize = 22
	altLabel.TextXAlignment = Enum.TextXAlignment.Right
	altLabel.Parent = altBox

	local warningLabel = Instance.new("TextLabel")
	warningLabel.Name = "WarningLabel"
	warningLabel.Size = UDim2.new(1, -20, 0, 16)
	warningLabel.Position = UDim2.fromOffset(10, 62)
	warningLabel.BackgroundTransparency = 1
	warningLabel.Font = Enum.Font.RobotoMono
	warningLabel.Text = "ESTADO: ALTITUD NOMINAL"
	warningLabel.TextColor3 = COLOR_TEXT_MUTED
	warningLabel.TextSize = 10
	warningLabel.TextXAlignment = Enum.TextXAlignment.Right
	warningLabel.Parent = altBox

	----------------------------------------------------------------------
	-- 4. BANNER SUPERIOR DE CÁMARA
	----------------------------------------------------------------------
	local topBanner = Instance.new("Frame")
	topBanner.Name = "TopBanner"
	topBanner.Size = UDim2.fromOffset(380, 38)
	topBanner.AnchorPoint = Vector2.new(0.5, 0)
	topBanner.Position = UDim2.new(0.5, 0, 0, 25)
	topBanner.BackgroundColor3 = COLOR_BG
	topBanner.BackgroundTransparency = 0.45
	topBanner.BorderSizePixel = 0
	topBanner.Parent = mainContainer

	local topCorner = Instance.new("UICorner")
	topCorner.CornerRadius = UDim.new(0, 6)
	topCorner.Parent = topBanner

	local topStroke = Instance.new("UIStroke")
	topStroke.Color = COLOR_NEON_PINK
	topStroke.Thickness = 1
	topStroke.Transparency = 0.4
	topStroke.Parent = topBanner

	local camLabel = Instance.new("TextLabel")
	camLabel.Name = "CamLabel"
	camLabel.Size = UDim2.new(1, 0, 1, 0)
	camLabel.BackgroundTransparency = 1
	camLabel.Font = Enum.Font.RobotoMono
	camLabel.Text = "CAM: 3RA PERSONA // [V] FPV // [X] FRENO"
	camLabel.TextColor3 = Color3.fromRGB(240, 240, 255)
	camLabel.TextSize = 11
	camLabel.Parent = topBanner

	----------------------------------------------------------------------
	-- 5. PANEL DE MISIÓN DE REPARTO ACTIVA (SUPERIOR DERECHA)
	----------------------------------------------------------------------
	local missionBox = Instance.new("Frame")
	missionBox.Name = "MissionBox"
	missionBox.Size = UDim2.fromOffset(240, 118)
	missionBox.AnchorPoint = Vector2.new(1, 0)
	missionBox.Position = UDim2.new(1, -25, 0, 160)
	missionBox.BackgroundColor3 = COLOR_BG
	missionBox.BackgroundTransparency = 0.35
	missionBox.BorderSizePixel = 0
	missionBox.Parent = mainContainer

	local missionCorner = Instance.new("UICorner")
	missionCorner.CornerRadius = UDim.new(0, 6)
	missionCorner.Parent = missionBox

	local missionStroke = Instance.new("UIStroke")
	missionStroke.Color = COLOR_NEON_YELLOW
	missionStroke.Thickness = 1.5
	missionStroke.Transparency = 0.3
	missionStroke.Parent = missionBox

	local missionHeader = Instance.new("TextLabel")
	missionHeader.Size = UDim2.new(1, -20, 0, 16)
	missionHeader.Position = UDim2.fromOffset(10, 8)
	missionHeader.BackgroundTransparency = 1
	missionHeader.Font = Enum.Font.RobotoMono
	missionHeader.Text = "MISIÓN DE REPARTO // DISPATCH"
	missionHeader.TextColor3 = COLOR_NEON_YELLOW
	missionHeader.TextSize = 11
	missionHeader.TextXAlignment = Enum.TextXAlignment.Left
	missionHeader.Parent = missionBox

	local missionTargetLabel = Instance.new("TextLabel")
	missionTargetLabel.Name = "TargetLabel"
	missionTargetLabel.Size = UDim2.new(1, -20, 0, 20)
	missionTargetLabel.Position = UDim2.fromOffset(10, 26)
	missionTargetLabel.BackgroundTransparency = 1
	missionTargetLabel.Font = Enum.Font.Code
	missionTargetLabel.Text = "DESTINO: Torre A"
	missionTargetLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	missionTargetLabel.TextSize = 13
	missionTargetLabel.TextXAlignment = Enum.TextXAlignment.Left
	missionTargetLabel.Parent = missionBox

	local missionRewardLabel = Instance.new("TextLabel")
	missionRewardLabel.Name = "RewardLabel"
	missionRewardLabel.Size = UDim2.new(1, -20, 0, 18)
	missionRewardLabel.Position = UDim2.fromOffset(10, 48)
	missionRewardLabel.BackgroundTransparency = 1
	missionRewardLabel.Font = Enum.Font.RobotoMono
	missionRewardLabel.Text = string.format("RECOMPENSA: +250 %s", getCurrencyName())
	missionRewardLabel.TextColor3 = COLOR_NEON_CYAN
	missionRewardLabel.TextSize = 12
	missionRewardLabel.TextXAlignment = Enum.TextXAlignment.Left
	missionRewardLabel.Parent = missionBox

	-- Estado de bodega de paquetes (3/3)
	local cargoStatusLabel = Instance.new("TextLabel")
	cargoStatusLabel.Name = "CargoStatusLabel"
	cargoStatusLabel.Size = UDim2.new(1, -20, 0, 18)
	cargoStatusLabel.Position = UDim2.fromOffset(10, 68)
	cargoStatusLabel.BackgroundTransparency = 1
	cargoStatusLabel.Font = Enum.Font.RobotoMono
	cargoStatusLabel.Text = "BODEGA: [📦 📦 📦] (3/3)"
	cargoStatusLabel.TextColor3 = COLOR_NEON_CYAN
	cargoStatusLabel.TextSize = 12
	cargoStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
	cargoStatusLabel.Parent = missionBox

	-- Barra de confirmación de aterrizaje en pad
	local landingBar = Instance.new("Frame")
	landingBar.Name = "LandingBar"
	landingBar.Size = UDim2.new(1, -20, 0, 6)
	landingBar.Position = UDim2.fromOffset(10, 96)
	landingBar.BackgroundColor3 = Color3.fromRGB(20, 30, 45)
	landingBar.BorderSizePixel = 0
	landingBar.Visible = false
	landingBar.Parent = missionBox

	local landingFill = Instance.new("Frame")
	landingFill.Name = "LandingFill"
	landingFill.Size = UDim2.fromScale(0, 1)
	landingFill.BackgroundColor3 = COLOR_NEON_YELLOW
	landingFill.BorderSizePixel = 0
	landingFill.Parent = landingBar

	----------------------------------------------------------------------
	-- 6. WAYPOINT HOLOGRÁFICO 3D EN EL MUNDO
	----------------------------------------------------------------------
	local waypointMarker = Instance.new("Frame")
	waypointMarker.Name = "WaypointMarker"
	waypointMarker.Size = UDim2.fromOffset(160, 42)
	waypointMarker.AnchorPoint = Vector2.new(0.5, 0.5)
	waypointMarker.BackgroundTransparency = 1
	waypointMarker.Visible = false
	waypointMarker.Parent = mainContainer

	local wpDiamond = Instance.new("TextLabel")
	wpDiamond.Size = UDim2.fromOffset(24, 24)
	wpDiamond.Position = UDim2.fromOffset(68, 0)
	wpDiamond.BackgroundTransparency = 1
	wpDiamond.Font = Enum.Font.RobotoMono
	wpDiamond.Text = "◆"
	wpDiamond.TextColor3 = COLOR_NEON_YELLOW
	wpDiamond.TextSize = 22
	wpDiamond.Parent = waypointMarker

	local waypointLabel = Instance.new("TextLabel")
	waypointLabel.Name = "WaypointLabel"
	waypointLabel.Size = UDim2.new(1, 0, 0, 16)
	waypointLabel.Position = UDim2.fromOffset(0, 24)
	waypointLabel.BackgroundTransparency = 1
	waypointLabel.Font = Enum.Font.RobotoMono
	waypointLabel.Text = "150 STUDS"
	waypointLabel.TextColor3 = COLOR_NEON_YELLOW
	waypointLabel.TextSize = 11
	waypointLabel.Parent = waypointMarker

	----------------------------------------------------------------------
	-- 7. POPUP DE RECOMPENSA DE ENTREGA
	----------------------------------------------------------------------
	local successPopup = Instance.new("Frame")
	successPopup.Name = "SuccessPopup"
	successPopup.Size = UDim2.fromOffset(360, 60)
	successPopup.AnchorPoint = Vector2.new(0.5, 0.5)
	successPopup.Position = UDim2.fromScale(0.5, 0.35)
	successPopup.BackgroundColor3 = COLOR_BG
	successPopup.BackgroundTransparency = 0.2
	successPopup.BorderSizePixel = 0
	successPopup.Visible = false
	successPopup.Parent = mainContainer

	local successCorner = Instance.new("UICorner")
	successCorner.CornerRadius = UDim.new(0, 8)
	successCorner.Parent = successPopup

	local successStroke = Instance.new("UIStroke")
	successStroke.Color = COLOR_NEON_YELLOW
	successStroke.Thickness = 2
	successStroke.Parent = successPopup

	local successText = Instance.new("TextLabel")
	successText.Name = "SuccessText"
	successText.Size = UDim2.new(1, 0, 1, 0)
	successText.BackgroundTransparency = 1
	successText.Font = Enum.Font.Code
	successText.Text = string.format("¡ENTREGA EXITOSA!\n+250 %s", getCurrencyName())
	successText.TextColor3 = COLOR_NEON_YELLOW
	successText.TextSize = 16
	successText.Parent = successPopup

	screenGui.Parent = playerGui

	local self: HUDInstance = {
		screenGui = screenGui,
		speedLabel = speedLabel,
		speedFill = speedFill,
		turboFill = turboFill,
		altLabel = altLabel,
		warningLabel = warningLabel,
		camLabel = camLabel,
		brakeIndicator = brakeIndicator,
		crosshair = crosshairContainer,
		horizonLine = horizonLine,
		waypointMarker = waypointMarker,
		waypointLabel = waypointLabel,
		missionBox = missionBox,
		missionTargetLabel = missionTargetLabel,
		missionRewardLabel = missionRewardLabel,
		cargoStatusLabel = cargoStatusLabel,
		landingBar = landingBar,
		landingFill = landingFill,
		successPopup = successPopup,
		successText = successText,
	}

	return setmetatable(self, DroneHUD) :: any
end

function DroneHUD.Update(
	self: HUDInstance,
	speed: number,
	maxSpeed: number,
	turboRatio: number,
	altitude: number,
	rollAngle: number,
	isFPV: boolean,
	isBraking: boolean,
	targetPosition: Vector3?,
	targetDisplayName: string?,
	targetReward: number?,
	landingProgress: number,
	cargoRemaining: number?,
	cargoMax: number?
)
	-- 1. Velocímetro e impulso
	local roundedSpeed = math.round(speed)
	self.speedLabel.Text = string.format("%03d STUDS/S", roundedSpeed)
	local speedRatio = math.clamp(speed / maxSpeed, 0, 1)
	self.speedFill.Size = UDim2.fromScale(speedRatio, 1)

	if speedRatio > 0.85 then
		self.speedFill.BackgroundColor3 = COLOR_NEON_PINK
		self.speedLabel.TextColor3 = COLOR_NEON_PINK
	else
		self.speedFill.BackgroundColor3 = COLOR_NEON_CYAN
		self.speedLabel.TextColor3 = COLOR_NEON_CYAN
	end

	-- 2. Barra de Turbo
	self.turboFill.Size = UDim2.fromScale(turboRatio, 1)

	-- 3. Altímetro y radar
	self.altLabel.Text = string.format("%05.1f STUDS", altitude)
	if altitude < 4 then
		self.warningLabel.Text = "¡PROXIMIDAD AL SUELO!"
		self.warningLabel.TextColor3 = COLOR_WARN
	else
		self.warningLabel.Text = "ESTADO: NOMINAL"
		self.warningLabel.TextColor3 = COLOR_TEXT_MUTED
	end

	-- 4. Freno de aire activo
	self.brakeIndicator.Visible = isBraking
	self.horizonLine.Rotation = -math.deg(rollAngle)

	-- 5. Modo de cámara
	if isFPV then
		self.camLabel.Text = "CAM: FPV COCKPIT // [V] 3RA PERSONA // [X] FRENO"
		self.camLabel.TextColor3 = COLOR_NEON_CYAN
	else
		self.camLabel.Text = "CAM: 3RA PERSONA // [V] FPV COCKPIT // [X] FRENO"
		self.camLabel.TextColor3 = Color3.fromRGB(240, 240, 255)
	end

	-- 6. Tarjeta de misión y estado de bodega
	if targetDisplayName then
		self.missionTargetLabel.Text = "DESTINO: " .. targetDisplayName
		self.missionRewardLabel.Text = string.format("RECOMPENSA: +%d %s", targetReward or 250, getCurrencyName())
	end

	local remaining = cargoRemaining or 3
	if remaining == 3 then
		self.cargoStatusLabel.Text = "BODEGA: [📦 📦 📦] (3/3)"
		self.cargoStatusLabel.TextColor3 = COLOR_NEON_CYAN
	elseif remaining == 2 then
		self.cargoStatusLabel.Text = "BODEGA: [📦 📦 ⬝] (2/3)"
		self.cargoStatusLabel.TextColor3 = COLOR_NEON_CYAN
	elseif remaining == 1 then
		self.cargoStatusLabel.Text = "BODEGA: [📦 ⬝ ⬝] (1/3) ¡ÚLTIMO!"
		self.cargoStatusLabel.TextColor3 = COLOR_NEON_YELLOW
	else
		self.cargoStatusLabel.Text = "BODEGA: [⬝ ⬝ ⬝] (0/3) ¡VE A BASE!"
		self.cargoStatusLabel.TextColor3 = COLOR_WARN
	end

	if landingProgress > 0 then
		self.landingBar.Visible = true
		self.landingFill.Size = UDim2.fromScale(landingProgress, 1)
		self.warningLabel.Text = "[ZONA DETECTADA] ATERRIZANDO... O PULSA [G]"
		self.warningLabel.TextColor3 = COLOR_NEON_YELLOW
	else
		self.landingBar.Visible = false
	end

	-- 7. Waypoint 3D Holográfico en el visor
	local camera = Workspace.CurrentCamera
	if targetPosition and camera then
		local screenPos, onScreen = camera:WorldToViewportPoint(targetPosition)
		local distance = (camera.CFrame.Position - targetPosition).Magnitude

		if onScreen and screenPos.Z > 0 then
			self.waypointMarker.Visible = true
			self.waypointMarker.Position = UDim2.fromOffset(screenPos.X, screenPos.Y)
			self.waypointLabel.Text = string.format("%d STUDS", math.round(distance))
		else
			-- Proyección en los bordes de la pantalla si está fuera de vista
			local viewportSize = camera.ViewportSize
			local clampedX = math.clamp(screenPos.X, 80, viewportSize.X - 80)
			local clampedY = math.clamp(screenPos.Y, 80, viewportSize.Y - 80)
			if screenPos.Z < 0 then
				clampedX = viewportSize.X - clampedX
				clampedY = viewportSize.Y - clampedY
			end
			self.waypointMarker.Visible = true
			self.waypointMarker.Position = UDim2.fromOffset(clampedX, clampedY)
			self.waypointLabel.Text = string.format("◀ %d STUDS ▶", math.round(distance))
		end
	else
		self.waypointMarker.Visible = false
	end
end

function DroneHUD.ShowSuccessPopup(self: HUDInstance, reward: number, targetName: string, remainingCargo: number?, isRestock: boolean?)
	if isRestock then
		self.successText.Text = string.format("¡BODEGA REABASTECIDA EN %s!\n+%d %s (3/3 Paquetes Listos)", targetName:upper(), reward, getCurrencyName())
		self.successText.TextColor3 = COLOR_NEON_CYAN
	elseif remainingCargo == 0 then
		self.successText.Text = string.format("¡ENTREGA EXITOSA EN %s!\n+%d %s\n¡BODEGA VACÍA! REGRESA A BASE", targetName:upper(), reward, getCurrencyName())
		self.successText.TextColor3 = COLOR_NEON_YELLOW
	else
		self.successText.Text = string.format("¡ENTREGA EXITOSA EN %s!\n+%d %s (Quedan %d en bodega)", targetName:upper(), reward, getCurrencyName(), remainingCargo or 1)
		self.successText.TextColor3 = COLOR_NEON_YELLOW
	end
	self.successPopup.Visible = true
	self.successPopup.Size = UDim2.fromOffset(360, 60)

	local tween = TweenService:Create(
		self.successPopup,
		TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(380, 68) }
	)
	tween:Play()

	task.delay(2.5, function()
		if self.successPopup then
			local fade = TweenService:Create(
				self.successPopup,
				TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Size = UDim2.fromOffset(300, 20), BackgroundTransparency = 1 }
			)
			fade:Play()
			fade.Completed:Connect(function()
				self.successPopup.Visible = false
				self.successPopup.BackgroundTransparency = 0.2
			end)
		end
	end)
end

function DroneHUD.ShowHint(self: HUDInstance, message: string, isError: boolean?)
	self.successText.Text = message
	self.successText.TextColor3 = if isError then COLOR_WARN else COLOR_NEON_YELLOW
	self.successPopup.Visible = true
	self.successPopup.Size = UDim2.fromOffset(420, 60)

	local tween = TweenService:Create(
		self.successPopup,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(440, 66) }
	)
	tween:Play()

	task.delay(2.5, function()
		if self.successPopup then
			local fade = TweenService:Create(
				self.successPopup,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Size = UDim2.fromOffset(360, 20), BackgroundTransparency = 1 }
			)
			fade:Play()
			fade.Completed:Connect(function()
				self.successPopup.Visible = false
				self.successPopup.BackgroundTransparency = 0.2
			end)
		end
	end)
end

function DroneHUD.Destroy(self: HUDInstance)
	if self.screenGui then
		self.screenGui:Destroy()
	end
end

return DroneHUD
