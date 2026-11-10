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
	wpDiamond: TextLabel,
	missionBox: Frame,
	missionTargetLabel: TextLabel,
	missionRewardLabel: TextLabel,
	cargoStatusLabel: TextLabel,
	threatBadge: TextLabel,
	hazardLabel: TextLabel,
	streakBadge: TextLabel,
	landingBar: Frame,
	landingFill: Frame,
	successPopup: Frame,
	successText: TextLabel,
	-- Fase 4: Combate, Telemetría Táctica y Radar
	combatBox: Frame,
	hpLabel: TextLabel,
	hpFill: Frame,
	heatLabel: TextLabel,
	heatFill: Frame,
	empStatusLabel: TextLabel,
	damageOverlay: Frame,
	damageIndicatorArrow: Frame,
	radarFrame: Frame,
	radarSweep: Frame,
	radarBlipPool: { Frame },
	radarPadBlips: { [string]: Frame },
	-- Fase 5: Rush Orders y Rango
	rushTimerLabel: TextLabel,
	rankBadge: TextLabel,
	-- Combate en Tercera Persona y Misiles Guiados
	targetLockTag: TextLabel,
	centerDot: Frame,
	missileStatusLabel: TextLabel,
	leftBracket: TextLabel,
	rightBracket: TextLabel,
	hitmarkerFrame: Frame,
	hitmarkerTicks: { Frame },
	hitSound: Sound,
	leadIndicator: Frame,
	leadStroke: UIStroke,
	leadDot: Frame,
	leadTag: TextLabel,
}

local COLOR_BG = Color3.fromRGB(8, 14, 24)
local COLOR_BORDER = Color3.fromRGB(0, 240, 255)
local COLOR_NEON_CYAN = Color3.fromRGB(0, 255, 240)
local COLOR_NEON_PINK = Color3.fromRGB(255, 30, 120)
local COLOR_NEON_YELLOW = Color3.fromRGB(255, 215, 0)
local COLOR_WARN = Color3.fromRGB(255, 70, 70)
local COLOR_TEXT_MUTED = Color3.fromRGB(140, 180, 200)

local COLOR_HEALTH_NOMINAL = Color3.fromRGB(0, 255, 170)
local COLOR_HEALTH_MID     = Color3.fromRGB(255, 200, 0)
local COLOR_HEALTH_CRIT    = Color3.fromRGB(255, 45, 45)
local COLOR_HEAT_FIRE      = Color3.fromRGB(255, 120, 0)
local COLOR_HEAT_CRIT      = Color3.fromRGB(255, 20, 60)

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

	local function createBracket(posX: number, text: string): TextLabel
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
		return label
	end
	local leftBracket = createBracket(0.1, "[")
	local rightBracket = createBracket(0.9, "]")

	-- Hitmarker táctico dinámico (4 aspas diagonales + sonido de confirmación)
	local hitmarkerFrame = Instance.new("Frame")
	hitmarkerFrame.Name = "HitmarkerFrame"
	hitmarkerFrame.Size = UDim2.fromOffset(36, 36)
	hitmarkerFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	hitmarkerFrame.Position = UDim2.fromScale(0.5, 0.5)
	hitmarkerFrame.BackgroundTransparency = 1
	hitmarkerFrame.Visible = false
	hitmarkerFrame.Parent = crosshairContainer

	local hitmarkerTicks: { Frame } = {}
	local tickOffsets = {
		{ -7, -7,  45 },
		{  7, -7, -45 },
		{ -7,  7, -45 },
		{  7,  7,  45 },
	}
	for _, cfg in ipairs(tickOffsets) do
		local tick = Instance.new("Frame")
		tick.Name = "HitTick"
		tick.Size = UDim2.fromOffset(2, 8)
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Position = UDim2.new(0.5, cfg[1], 0.5, cfg[2])
		tick.Rotation = cfg[3]
		tick.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		tick.BorderSizePixel = 0
		tick.Parent = hitmarkerFrame
		table.insert(hitmarkerTicks, tick)
	end

	local hitSound = Instance.new("Sound")
	hitSound.Name = "HitSound"
	hitSound.SoundId = "rbxassetid://9114223170"
	hitSound.Volume = 0.8
	hitSound.PlaybackSpeed = 1.8
	hitSound.Parent = crosshairContainer

	-- Retícula predictiva adelantada (Lead Indicator) en espacio de pantalla
	local leadIndicator = Instance.new("Frame")
	leadIndicator.Name = "LeadIndicator"
	leadIndicator.Size = UDim2.fromOffset(26, 26)
	leadIndicator.AnchorPoint = Vector2.new(0.5, 0.5)
	leadIndicator.Position = UDim2.fromScale(0.5, 0.5)
	leadIndicator.BackgroundTransparency = 1
	leadIndicator.Visible = false
	leadIndicator.Parent = mainContainer

	local leadStroke = Instance.new("UIStroke")
	leadStroke.Name = "LeadStroke"
	leadStroke.Thickness = 1.5
	leadStroke.Color = COLOR_NEON_CYAN
	leadStroke.Parent = leadIndicator

	local leadCorner = Instance.new("UICorner")
	leadCorner.CornerRadius = UDim.new(1, 0)
	leadCorner.Parent = leadIndicator

	local leadDot = Instance.new("Frame")
	leadDot.Name = "LeadDot"
	leadDot.Size = UDim2.fromOffset(4, 4)
	leadDot.AnchorPoint = Vector2.new(0.5, 0.5)
	leadDot.Position = UDim2.fromScale(0.5, 0.5)
	leadDot.BackgroundColor3 = COLOR_NEON_CYAN
	leadDot.BorderSizePixel = 0
	leadDot.Parent = leadIndicator

	local leadDotCorner = Instance.new("UICorner")
	leadDotCorner.CornerRadius = UDim.new(1, 0)
	leadDotCorner.Parent = leadDot

	local leadTag = Instance.new("TextLabel")
	leadTag.Name = "LeadTag"
	leadTag.Size = UDim2.fromOffset(90, 14)
	leadTag.AnchorPoint = Vector2.new(0.5, 0)
	leadTag.Position = UDim2.new(0.5, 0, 1, 2)
	leadTag.BackgroundTransparency = 1
	leadTag.Font = Enum.Font.Code
	leadTag.Text = "LEAD // MIRA"
	leadTag.TextColor3 = COLOR_NEON_CYAN
	leadTag.TextSize = 10
	leadTag.Parent = leadIndicator

	-- Rótulo de Fijado de Objetivo (Lock-On para Combate en 3ra Persona y Misiles)
	local targetLockTag = Instance.new("TextLabel")
	targetLockTag.Name = "TargetLockTag"
	targetLockTag.Size = UDim2.fromOffset(260, 20)
	targetLockTag.AnchorPoint = Vector2.new(0.5, 1)
	targetLockTag.Position = UDim2.new(0.5, 0, 0, -8)
	targetLockTag.BackgroundTransparency = 1
	targetLockTag.Font = Enum.Font.Code
	targetLockTag.Text = "[ 🎯 FIJADO: OBJETIVO | 100m ]"
	targetLockTag.TextColor3 = Color3.fromRGB(255, 35, 60)
	targetLockTag.TextSize = 12
	targetLockTag.TextStrokeTransparency = 0.2
	targetLockTag.Visible = false
	targetLockTag.Parent = crosshairContainer

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
	-- 2B. PANEL DE COMBATE: INTEGRIDAD HP & CALOR TÉRMICO (INFERIOR IZQ)
	----------------------------------------------------------------------
	local combatBox = Instance.new("Frame")
	combatBox.Name = "CombatStatusBox"
	combatBox.Size = UDim2.fromOffset(210, 108)
	combatBox.AnchorPoint = Vector2.new(0, 1)
	combatBox.Position = UDim2.new(0, 35, 1, -148)
	combatBox.BackgroundColor3 = COLOR_BG
	combatBox.BackgroundTransparency = 0.35
	combatBox.BorderSizePixel = 0
	combatBox.Parent = mainContainer

	local combatCorner = Instance.new("UICorner")
	combatCorner.CornerRadius = UDim.new(0, 6)
	combatCorner.Parent = combatBox

	local combatStroke = Instance.new("UIStroke")
	combatStroke.Name = "CombatStroke"
	combatStroke.Color = COLOR_BORDER
	combatStroke.Thickness = 1.2
	combatStroke.Transparency = 0.3
	combatStroke.Parent = combatBox

	local combatHeader = Instance.new("TextLabel")
	combatHeader.Size = UDim2.new(1, -20, 0, 13)
	combatHeader.Position = UDim2.fromOffset(10, 5)
	combatHeader.BackgroundTransparency = 1
	combatHeader.Font = Enum.Font.RobotoMono
	combatHeader.Text = "SISTEMAS DE NÚCLEO // COMBAT LOG"
	combatHeader.TextColor3 = COLOR_TEXT_MUTED
	combatHeader.TextSize = 10
	combatHeader.TextXAlignment = Enum.TextXAlignment.Left
	combatHeader.Parent = combatBox

	-- Barra HP
	local hpLabel = Instance.new("TextLabel")
	hpLabel.Name = "HPLabel"
	hpLabel.Size = UDim2.new(1, -20, 0, 13)
	hpLabel.Position = UDim2.fromOffset(10, 20)
	hpLabel.BackgroundTransparency = 1
	hpLabel.Font = Enum.Font.RobotoMono
	hpLabel.Text = "INTEGRIDAD HP: 100%"
	hpLabel.TextColor3 = COLOR_HEALTH_NOMINAL
	hpLabel.TextSize = 11
	hpLabel.TextXAlignment = Enum.TextXAlignment.Left
	hpLabel.Parent = combatBox

	local hpTrack = Instance.new("Frame")
	hpTrack.Size = UDim2.new(1, -20, 0, 5)
	hpTrack.Position = UDim2.fromOffset(10, 35)
	hpTrack.BackgroundColor3 = Color3.fromRGB(20, 30, 45)
	hpTrack.BorderSizePixel = 0
	hpTrack.Parent = combatBox

	local hpFill = Instance.new("Frame")
	hpFill.Name = "HPFill"
	hpFill.Size = UDim2.fromScale(1, 1)
	hpFill.BackgroundColor3 = COLOR_HEALTH_NOMINAL
	hpFill.BorderSizePixel = 0
	hpFill.Parent = hpTrack

	-- Barra Heat
	local heatLabel = Instance.new("TextLabel")
	heatLabel.Name = "HeatLabel"
	heatLabel.Size = UDim2.new(1, -20, 0, 13)
	heatLabel.Position = UDim2.fromOffset(10, 43)
	heatLabel.BackgroundTransparency = 1
	heatLabel.Font = Enum.Font.RobotoMono
	heatLabel.Text = "CALOR NÚCLEO: 0%"
	heatLabel.TextColor3 = COLOR_HEAT_FIRE
	heatLabel.TextSize = 11
	heatLabel.TextXAlignment = Enum.TextXAlignment.Left
	heatLabel.Parent = combatBox

	local heatTrack = Instance.new("Frame")
	heatTrack.Size = UDim2.new(1, -20, 0, 5)
	heatTrack.Position = UDim2.fromOffset(10, 58)
	heatTrack.BackgroundColor3 = Color3.fromRGB(20, 30, 45)
	heatTrack.BorderSizePixel = 0
	heatTrack.Parent = combatBox

	local heatFill = Instance.new("Frame")
	heatFill.Name = "HeatFill"
	heatFill.Size = UDim2.fromScale(0, 1)
	heatFill.BackgroundColor3 = COLOR_HEAT_FIRE
	heatFill.BorderSizePixel = 0
	heatFill.Parent = heatTrack

	-- Estado de contramedida EMP
	local empStatusLabel = Instance.new("TextLabel")
	empStatusLabel.Name = "EMPStatusLabel"
	empStatusLabel.Size = UDim2.new(1, -20, 0, 14)
	empStatusLabel.Position = UDim2.fromOffset(10, 68)
	empStatusLabel.BackgroundTransparency = 1
	empStatusLabel.Font = Enum.Font.RobotoMono
	empStatusLabel.Text = "PULSO EMP [C]: LISTO ⚡"
	empStatusLabel.TextColor3 = COLOR_NEON_CYAN
	empStatusLabel.TextSize = 10
	empStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
	empStatusLabel.Parent = combatBox

	-- Módulo de Munición de Misiles Guiados [R]
	local missileStatusLabel = Instance.new("TextLabel")
	missileStatusLabel.Name = "MissileStatusLabel"
	missileStatusLabel.Size = UDim2.new(1, -20, 0, 14)
	missileStatusLabel.Position = UDim2.fromOffset(10, 85)
	missileStatusLabel.BackgroundTransparency = 1
	missileStatusLabel.Font = Enum.Font.RobotoMono
	missileStatusLabel.Text = "MISILES [R]: [ ■ ■ ■ ] (3/3)"
	missileStatusLabel.TextColor3 = Color3.fromRGB(255, 180, 0)
	missileStatusLabel.TextSize = 10
	missileStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
	missileStatusLabel.Parent = combatBox

	----------------------------------------------------------------------
	-- 2C. RADAR TÁCTICO DE AMENAZAS 360° (SUPERIOR IZQUIERDA)
	----------------------------------------------------------------------
	local radarFrame = Instance.new("Frame")
	radarFrame.Name = "ThreatRadar"
	radarFrame.Size = UDim2.fromOffset(130, 130)
	radarFrame.AnchorPoint = Vector2.new(0, 0)
	radarFrame.Position = UDim2.new(0, 30, 0, 30)
	radarFrame.BackgroundColor3 = COLOR_BG
	radarFrame.BackgroundTransparency = 0.35
	radarFrame.BorderSizePixel = 0
	radarFrame.ClipsDescendants = true
	radarFrame.Parent = mainContainer

	local radarCorner = Instance.new("UICorner")
	radarCorner.CornerRadius = UDim.new(0.5, 0)
	radarCorner.Parent = radarFrame

	local radarStroke = Instance.new("UIStroke")
	radarStroke.Color = COLOR_BORDER
	radarStroke.Thickness = 1.5
	radarStroke.Transparency = 0.2
	radarStroke.Parent = radarFrame

	local innerRing = Instance.new("Frame")
	innerRing.Size = UDim2.fromScale(0.5, 0.5)
	innerRing.AnchorPoint = Vector2.new(0.5, 0.5)
	innerRing.Position = UDim2.fromScale(0.5, 0.5)
	innerRing.BackgroundTransparency = 1
	innerRing.BorderSizePixel = 0
	innerRing.Parent = radarFrame

	local innerCorner = Instance.new("UICorner")
	innerCorner.CornerRadius = UDim.new(0.5, 0)
	innerCorner.Parent = innerRing

	local innerStroke = Instance.new("UIStroke")
	innerStroke.Color = COLOR_BORDER
	innerStroke.Thickness = 1
	innerStroke.Transparency = 0.65
	innerStroke.Parent = innerRing

	local axisH = Instance.new("Frame")
	axisH.Size = UDim2.new(1, 0, 0, 1)
	axisH.Position = UDim2.new(0, 0, 0.5, 0)
	axisH.BackgroundColor3 = COLOR_BORDER
	axisH.BackgroundTransparency = 0.75
	axisH.BorderSizePixel = 0
	axisH.Parent = radarFrame

	local axisV = Instance.new("Frame")
	axisV.Size = UDim2.new(0, 1, 1, 0)
	axisV.Position = UDim2.new(0.5, 0, 0, 0)
	axisV.BackgroundColor3 = COLOR_BORDER
	axisV.BackgroundTransparency = 0.75
	axisV.BorderSizePixel = 0
	axisV.Parent = radarFrame

	local radarSweep = Instance.new("Frame")
	radarSweep.Name = "RadarSweep"
	radarSweep.Size = UDim2.new(0.5, 0, 0, 2)
	radarSweep.AnchorPoint = Vector2.new(0, 0.5)
	radarSweep.Position = UDim2.fromScale(0.5, 0.5)
	radarSweep.BackgroundColor3 = COLOR_NEON_CYAN
	radarSweep.BackgroundTransparency = 0.4
	radarSweep.BorderSizePixel = 0
	radarSweep.Parent = radarFrame

	local centerPlayer = Instance.new("TextLabel")
	centerPlayer.Size = UDim2.fromOffset(14, 14)
	centerPlayer.AnchorPoint = Vector2.new(0.5, 0.5)
	centerPlayer.Position = UDim2.fromScale(0.5, 0.5)
	centerPlayer.BackgroundTransparency = 1
	centerPlayer.Font = Enum.Font.RobotoMono
	centerPlayer.Text = "▲"
	centerPlayer.TextColor3 = Color3.fromRGB(255, 255, 255)
	centerPlayer.TextSize = 10
	centerPlayer.ZIndex = 3
	centerPlayer.Parent = radarFrame

	local radarTitle = Instance.new("TextLabel")
	radarTitle.Size = UDim2.new(1, 0, 0, 14)
	radarTitle.Position = UDim2.new(0, 0, 1, 4)
	radarTitle.BackgroundTransparency = 1
	radarTitle.Font = Enum.Font.RobotoMono
	radarTitle.Text = "RADAR TÁCTICO // 250m"
	radarTitle.TextColor3 = COLOR_NEON_CYAN
	radarTitle.TextSize = 9
	radarTitle.Parent = radarFrame

	local radarBlipPool: { Frame } = {}
	for i = 1, 12 do
		local blip = Instance.new("Frame")
		blip.Name = "EnemyBlip_" .. i
		blip.Size = UDim2.fromOffset(6, 6)
		blip.AnchorPoint = Vector2.new(0.5, 0.5)
		blip.Position = UDim2.fromScale(0.5, 0.5)
		blip.BackgroundColor3 = Color3.fromRGB(255, 40, 60)
		blip.BorderSizePixel = 0
		blip.Visible = false
		blip.ZIndex = 4

		local blipCorner = Instance.new("UICorner")
		blipCorner.CornerRadius = UDim.new(0.5, 0)
		blipCorner.Parent = blip

		blip.Parent = radarFrame
		table.insert(radarBlipPool, blip)
	end

	local radarPadBlips: { [string]: Frame } = {}
	local padDefs = {
		{ id = "Base", col = COLOR_NEON_CYAN },
		{ id = "TorreA", col = COLOR_NEON_YELLOW },
		{ id = "TorreB", col = COLOR_NEON_PINK },
	}
	for _, pDef in ipairs(padDefs) do
		local pBlip = Instance.new("Frame")
		pBlip.Name = "PadBlip_" .. pDef.id
		pBlip.Size = UDim2.fromOffset(7, 7)
		pBlip.AnchorPoint = Vector2.new(0.5, 0.5)
		pBlip.Position = UDim2.fromScale(0.5, 0.5)
		pBlip.BackgroundColor3 = pDef.col
		pBlip.BorderSizePixel = 0
		pBlip.Visible = false
		pBlip.ZIndex = 2

		local pCorner = Instance.new("UICorner")
		pCorner.CornerRadius = UDim.new(0, 2)
		pCorner.Parent = pBlip

		pBlip.Parent = radarFrame
		radarPadBlips[pDef.id] = pBlip
	end

	----------------------------------------------------------------------
	-- 2D. VIÑETA Y ALERTA DIRECCIONAL DE DAÑO
	----------------------------------------------------------------------
	local damageOverlay = Instance.new("Frame")
	damageOverlay.Name = "DamageOverlay"
	damageOverlay.Size = UDim2.fromScale(1, 1)
	damageOverlay.BackgroundColor3 = Color3.fromRGB(255, 0, 40)
	damageOverlay.BackgroundTransparency = 1
	damageOverlay.BorderSizePixel = 0
	damageOverlay.ZIndex = 5
	damageOverlay.Parent = mainContainer

	local damageIndicatorArrow = Instance.new("Frame")
	damageIndicatorArrow.Name = "DamageIndicatorArrow"
	damageIndicatorArrow.Size = UDim2.fromOffset(140, 140)
	damageIndicatorArrow.AnchorPoint = Vector2.new(0.5, 0.5)
	damageIndicatorArrow.Position = UDim2.fromScale(0.5, 0.5)
	damageIndicatorArrow.BackgroundTransparency = 1
	damageIndicatorArrow.Visible = false
	damageIndicatorArrow.Parent = mainContainer

	local arrowLabel = Instance.new("TextLabel")
	arrowLabel.Size = UDim2.fromOffset(70, 20)
	arrowLabel.AnchorPoint = Vector2.new(0.5, 0)
	arrowLabel.Position = UDim2.new(0.5, 0, 0, -12)
	arrowLabel.BackgroundTransparency = 1
	arrowLabel.Font = Enum.Font.RobotoMono
	arrowLabel.Text = "▲ IMPACTO ▲"
	arrowLabel.TextColor3 = Color3.fromRGB(255, 40, 60)
	arrowLabel.TextSize = 11
	arrowLabel.TextStrokeTransparency = 0.2
	arrowLabel.Parent = damageIndicatorArrow

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
	camLabel.Text = "CAM: 3RA PERSONA // [LMB] PLASMA // [C] EMP // [V] FPV // [X] FRENO"
	camLabel.TextColor3 = Color3.fromRGB(240, 240, 255)
	camLabel.TextSize = 10
	camLabel.Parent = topBanner

	----------------------------------------------------------------------
	-- 5. PANEL DE MISIÓN DE REPARTO ACTIVA (SUPERIOR DERECHA)
	----------------------------------------------------------------------
	local missionBox = Instance.new("Frame")
	missionBox.Name = "MissionBox"
	missionBox.Size = UDim2.fromOffset(260, 192)
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
	missionStroke.Name = "MissionStroke"
	missionStroke.Color = COLOR_NEON_YELLOW
	missionStroke.Thickness = 1.5
	missionStroke.Transparency = 0.3
	missionStroke.Parent = missionBox

	local missionHeader = Instance.new("TextLabel")
	missionHeader.Size = UDim2.new(1, -20, 0, 14)
	missionHeader.Position = UDim2.fromOffset(10, 6)
	missionHeader.BackgroundTransparency = 1
	missionHeader.Font = Enum.Font.RobotoMono
	missionHeader.Text = "MISIÓN DE REPARTO // DISPATCH"
	missionHeader.TextColor3 = COLOR_NEON_YELLOW
	missionHeader.TextSize = 10
	missionHeader.TextXAlignment = Enum.TextXAlignment.Left
	missionHeader.Parent = missionBox

	-- Insignia/Pill del nivel de amenaza táctica
	local threatBadge = Instance.new("TextLabel")
	threatBadge.Name = "ThreatBadge"
	threatBadge.Size = UDim2.new(1, -20, 0, 18)
	threatBadge.Position = UDim2.fromOffset(10, 22)
	threatBadge.BackgroundColor3 = Color3.fromRGB(15, 30, 25)
	threatBadge.BackgroundTransparency = 0.4
	threatBadge.BorderSizePixel = 0
	threatBadge.Font = Enum.Font.Code
	threatBadge.Text = " [🟢 AMENAZA: SEGURO]"
	threatBadge.TextColor3 = Color3.fromRGB(0, 255, 180)
	threatBadge.TextSize = 10
	threatBadge.TextXAlignment = Enum.TextXAlignment.Left
	threatBadge.Parent = missionBox

	local threatCorner = Instance.new("UICorner")
	threatCorner.CornerRadius = UDim.new(0, 4)
	threatCorner.Parent = threatBadge

	local threatStroke = Instance.new("UIStroke")
	threatStroke.Name = "ThreatStroke"
	threatStroke.Color = Color3.fromRGB(0, 255, 180)
	threatStroke.Thickness = 1
	threatStroke.Transparency = 0.4
	threatStroke.Parent = threatBadge

	-- Inteligencia de peligro / hazard
	local hazardLabel = Instance.new("TextLabel")
	hazardLabel.Name = "HazardLabel"
	hazardLabel.Size = UDim2.new(1, -20, 0, 14)
	hazardLabel.Position = UDim2.fromOffset(10, 42)
	hazardLabel.BackgroundTransparency = 1
	hazardLabel.Font = Enum.Font.RobotoMono
	hazardLabel.Text = "INTEL: Vuelo comercial nominal"
	hazardLabel.TextColor3 = COLOR_TEXT_MUTED
	hazardLabel.TextSize = 9
	hazardLabel.TextXAlignment = Enum.TextXAlignment.Left
	hazardLabel.Parent = missionBox

	local missionTargetLabel = Instance.new("TextLabel")
	missionTargetLabel.Name = "TargetLabel"
	missionTargetLabel.Size = UDim2.new(1, -20, 0, 18)
	missionTargetLabel.Position = UDim2.fromOffset(10, 58)
	missionTargetLabel.BackgroundTransparency = 1
	missionTargetLabel.Font = Enum.Font.Code
	missionTargetLabel.Text = "DESTINO: Torre A"
	missionTargetLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	missionTargetLabel.TextSize = 12
	missionTargetLabel.TextXAlignment = Enum.TextXAlignment.Left
	missionTargetLabel.Parent = missionBox

	local missionRewardLabel = Instance.new("TextLabel")
	missionRewardLabel.Name = "RewardLabel"
	missionRewardLabel.Size = UDim2.new(1, -20, 0, 16)
	missionRewardLabel.Position = UDim2.fromOffset(10, 76)
	missionRewardLabel.BackgroundTransparency = 1
	missionRewardLabel.Font = Enum.Font.RobotoMono
	missionRewardLabel.Text = string.format("RECOMPENSA: +250 %s", getCurrencyName())
	missionRewardLabel.TextColor3 = COLOR_NEON_CYAN
	missionRewardLabel.TextSize = 11
	missionRewardLabel.TextXAlignment = Enum.TextXAlignment.Left
	missionRewardLabel.Parent = missionBox

	-- Orden Prioritaria / Rush Order Timer (Fase 5)
	local rushTimerLabel = Instance.new("TextLabel")
	rushTimerLabel.Name = "RushTimerLabel"
	rushTimerLabel.Size = UDim2.new(1, -20, 0, 16)
	rushTimerLabel.Position = UDim2.fromOffset(10, 92)
	rushTimerLabel.BackgroundTransparency = 1
	rushTimerLabel.Font = Enum.Font.Code
	rushTimerLabel.Text = "RUSH: ⏱️ 45s (+50% BONUS)"
	rushTimerLabel.TextColor3 = COLOR_NEON_YELLOW
	rushTimerLabel.TextSize = 10
	rushTimerLabel.TextXAlignment = Enum.TextXAlignment.Left
	rushTimerLabel.Visible = false
	rushTimerLabel.Parent = missionBox

	-- Estado de bodega de paquetes (3/3)
	local cargoStatusLabel = Instance.new("TextLabel")
	cargoStatusLabel.Name = "CargoStatusLabel"
	cargoStatusLabel.Size = UDim2.new(1, -20, 0, 16)
	cargoStatusLabel.Position = UDim2.fromOffset(10, 110)
	cargoStatusLabel.BackgroundTransparency = 1
	cargoStatusLabel.Font = Enum.Font.RobotoMono
	cargoStatusLabel.Text = "BODEGA: [📦 📦 📦] (3/3)"
	cargoStatusLabel.TextColor3 = COLOR_NEON_CYAN
	cargoStatusLabel.TextSize = 11
	cargoStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
	cargoStatusLabel.Parent = missionBox

	-- Indicador de Racha (Streak)
	local streakBadge = Instance.new("TextLabel")
	streakBadge.Name = "StreakBadge"
	streakBadge.Size = UDim2.new(1, -20, 0, 16)
	streakBadge.Position = UDim2.fromOffset(10, 128)
	streakBadge.BackgroundTransparency = 1
	streakBadge.Font = Enum.Font.RobotoMono
	streakBadge.Text = "RACHA: x1 (BONO AL ENCADENAR)"
	streakBadge.TextColor3 = COLOR_TEXT_MUTED
	streakBadge.TextSize = 10
	streakBadge.TextXAlignment = Enum.TextXAlignment.Left
	streakBadge.Parent = missionBox

	-- Rango del Piloto (Fase 5)
	local rankBadge = Instance.new("TextLabel")
	rankBadge.Name = "RankBadge"
	rankBadge.Size = UDim2.new(1, -20, 0, 16)
	rankBadge.Position = UDim2.fromOffset(10, 146)
	rankBadge.BackgroundTransparency = 1
	rankBadge.Font = Enum.Font.RobotoMono
	rankBadge.Text = "RANGO: [CADETE AÉREO]"
	rankBadge.TextColor3 = COLOR_NEON_CYAN
	rankBadge.TextSize = 10
	rankBadge.TextXAlignment = Enum.TextXAlignment.Left
	rankBadge.Parent = missionBox

	-- Barra de confirmación de aterrizaje en pad
	local landingBar = Instance.new("Frame")
	landingBar.Name = "LandingBar"
	landingBar.Size = UDim2.new(1, -20, 0, 6)
	landingBar.Position = UDim2.fromOffset(10, 168)
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
	wpDiamond.Name = "WpDiamond"
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
		wpDiamond = wpDiamond,
		missionBox = missionBox,
		missionTargetLabel = missionTargetLabel,
		missionRewardLabel = missionRewardLabel,
		cargoStatusLabel = cargoStatusLabel,
		threatBadge = threatBadge,
		hazardLabel = hazardLabel,
		streakBadge = streakBadge,
		landingBar = landingBar,
		landingFill = landingFill,
		successPopup = successPopup,
		successText = successText,
		-- Fase 4: Combate, Telemetría Táctica y Radar
		combatBox = combatBox,
		hpLabel = hpLabel,
		hpFill = hpFill,
		heatLabel = heatLabel,
		heatFill = heatFill,
		empStatusLabel = empStatusLabel,
		damageOverlay = damageOverlay,
		damageIndicatorArrow = damageIndicatorArrow,
		radarFrame = radarFrame,
		radarSweep = radarSweep,
		radarBlipPool = radarBlipPool,
		radarPadBlips = radarPadBlips,
		-- Fase 5: Rush Orders y Rango
		rushTimerLabel = rushTimerLabel,
		rankBadge = rankBadge,
		-- Combate en Tercera Persona y Misiles Guiados
		targetLockTag = targetLockTag,
		centerDot = centerDot,
		missileStatusLabel = missileStatusLabel,
		leftBracket = leftBracket,
		rightBracket = rightBracket,
		hitmarkerFrame = hitmarkerFrame,
		hitmarkerTicks = hitmarkerTicks,
		hitSound = hitSound,
		leadIndicator = leadIndicator,
		leadStroke = leadStroke,
		leadDot = leadDot,
		leadTag = leadTag,
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
	cargoMax: number?,
	threatLevel: string?,
	hazardInfo: string?,
	deliveryStreak: number?,
	streakMultiplier: number?,
	healthRatio: number?,
	heatRatio: number?,
	isEMPed: boolean?,
	empCooldownRemaining: number?,
	playerDronePos: Vector3?,
	playerDroneYaw: number?,
	dt: number?,
	rushActive: boolean?,
	rushRemaining: number?,
	pilotRank: string?
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

	-- 5. Modo de cámara y controles de arsenal
	if isFPV then
		self.camLabel.Text = "CAM: FPV COCKPIT // [LMB] PLASMA // [C] EMP // [V] 3RA PERSONA // [X] FRENO"
		self.camLabel.TextColor3 = COLOR_NEON_CYAN
	else
		self.camLabel.Text = "CAM: 3RA PERSONA // [LMB] PLASMA // [C] EMP // [V] FPV // [X] FRENO"
		self.camLabel.TextColor3 = Color3.fromRGB(240, 240, 255)
	end

	-- 6. Tarjeta de misión, amenaza, racha y estado de bodega
	local tLevel = threatLevel or "safe"
	local wpColor = Color3.fromRGB(0, 255, 180)

	if tLevel == "black_ops" then
		wpColor = COLOR_NEON_PINK
		self.threatBadge.Text = " [🔴 AMENAZA: BLACK OPS]"
		self.threatBadge.TextColor3 = COLOR_NEON_PINK
		local stroke = self.threatBadge:FindFirstChild("ThreatStroke") :: UIStroke?
		if stroke then stroke.Color = COLOR_NEON_PINK end
	elseif tLevel == "hostile" then
		wpColor = COLOR_NEON_YELLOW
		self.threatBadge.Text = " [🟡 AMENAZA: HOSTIL]"
		self.threatBadge.TextColor3 = COLOR_NEON_YELLOW
		local stroke = self.threatBadge:FindFirstChild("ThreatStroke") :: UIStroke?
		if stroke then stroke.Color = COLOR_NEON_YELLOW end
	else
		wpColor = Color3.fromRGB(0, 255, 180)
		self.threatBadge.Text = " [🟢 AMENAZA: SEGURO]"
		self.threatBadge.TextColor3 = Color3.fromRGB(0, 255, 180)
		local stroke = self.threatBadge:FindFirstChild("ThreatStroke") :: UIStroke?
		if stroke then stroke.Color = Color3.fromRGB(0, 255, 180) end
	end

	self.hazardLabel.Text = "INTEL: " .. (hazardInfo or "Vuelo nominal")

	if targetDisplayName then
		self.missionTargetLabel.Text = "DESTINO: " .. targetDisplayName
		self.missionRewardLabel.Text = string.format("RECOMPENSA: +%d %s", targetReward or 250, getCurrencyName())
	end

	local streak = deliveryStreak or 0
	local mult = streakMultiplier or 1.0
	if streak > 1 then
		self.streakBadge.Text = string.format("RACHA: x%d 🔥 (+%.0f%% BONUS)", streak, (mult - 1) * 100)
		self.streakBadge.TextColor3 = COLOR_NEON_YELLOW
	else
		self.streakBadge.Text = "RACHA: x1 (BONO AL ENCADENAR)"
		self.streakBadge.TextColor3 = COLOR_TEXT_MUTED
	end

	-- 6b. Rush Timer y Rango de Piloto (Fase 5)
	if rushActive and rushRemaining and rushRemaining > 0 then
		self.rushTimerLabel.Visible = true
		self.rushTimerLabel.Text = string.format("RUSH: ⏱️ %02ds (+50%% BONUS)", math.ceil(rushRemaining))
		self.rushTimerLabel.TextColor3 = COLOR_NEON_YELLOW
	else
		self.rushTimerLabel.Visible = false
	end

	self.rankBadge.Text = string.format("RANGO: [%s]", (pilotRank or "CADETE AÉREO"):upper())

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

	-- 7. Waypoint 3D Holográfico en el visor teñido según el nivel de amenaza
	self.wpDiamond.TextColor3 = wpColor
	self.waypointLabel.TextColor3 = wpColor

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

	-- 8. Telemetría de Combate: Integridad HP y Calor Térmico
	local hp = math.clamp(healthRatio or 1.0, 0, 1)
	self.hpFill.Size = UDim2.fromScale(hp, 1)
	self.hpLabel.Text = string.format("INTEGRIDAD HP: %d%%", math.round(hp * 100))

	if hp > 0.6 then
		self.hpFill.BackgroundColor3 = COLOR_HEALTH_NOMINAL
		self.hpLabel.TextColor3 = COLOR_HEALTH_NOMINAL
	elseif hp > 0.3 then
		self.hpFill.BackgroundColor3 = COLOR_HEALTH_MID
		self.hpLabel.TextColor3 = COLOR_HEALTH_MID
	else
		self.hpFill.BackgroundColor3 = COLOR_HEALTH_CRIT
		self.hpLabel.TextColor3 = COLOR_HEALTH_CRIT
	end

	local heat = math.clamp(heatRatio or 0.0, 0, 1)
	self.heatFill.Size = UDim2.fromScale(heat, 1)

	if isEMPed then
		self.heatLabel.Text = "CALOR: ¡EMP ACTIVO! ⚡"
		self.heatLabel.TextColor3 = COLOR_NEON_CYAN
		self.heatFill.BackgroundColor3 = COLOR_NEON_CYAN
	elseif heat >= 0.85 then
		self.heatLabel.Text = string.format("CALOR: %d%% ¡OVERHEAT! ⚠️", math.round(heat * 100))
		self.heatLabel.TextColor3 = COLOR_HEAT_CRIT
		self.heatFill.BackgroundColor3 = COLOR_HEAT_CRIT
	else
		self.heatLabel.Text = string.format("CALOR NÚCLEO: %d%%", math.round(heat * 100))
		self.heatLabel.TextColor3 = COLOR_HEAT_FIRE
		self.heatFill.BackgroundColor3 = COLOR_HEAT_FIRE
	end

	local empCD = empCooldownRemaining or 0
	if empCD > 0.1 then
		self.empStatusLabel.Text = string.format("PULSO EMP [C]: RECARGA (%ds)", math.ceil(empCD))
		self.empStatusLabel.TextColor3 = COLOR_TEXT_MUTED
	else
		self.empStatusLabel.Text = "PULSO EMP [C]: ¡LISTO! ⚡"
		self.empStatusLabel.TextColor3 = COLOR_NEON_CYAN
	end

	-- 9. Radar Táctico de Amenazas 360° (Rango: 320 studs para cobertura total del sector metropolitano)
	local RADAR_MAX_DIST = 320
	local RADAR_RADIUS_PX = 52
	local delta = dt or 0.016

	self.radarSweep.Rotation = (self.radarSweep.Rotation + delta * 180) % 360

	if playerDronePos and playerDroneYaw then
		-- Helipuertos conocidos (calibrados con las coordenadas reales del mapa)
		local helipads = {
			Base   = Vector3.new(0, 4, 0),
			TorreA = Vector3.new(160, 95, -180),
			TorreB = Vector3.new(-200, 50, 140),
		}

		for padName, padPos in pairs(helipads) do
			local pBlip = self.radarPadBlips[padName]
			if pBlip then
				local toPad = padPos - playerDronePos
				local distH = Vector3.new(toPad.X, 0, toPad.Z).Magnitude
				if distH <= RADAR_MAX_DIST * 1.5 then
					local relCF = CFrame.Angles(0, playerDroneYaw, 0)
					local localVec = relCF:PointToObjectSpace(toPad)
					local normX = math.clamp(localVec.X / RADAR_MAX_DIST, -1, 1)
					local normY = math.clamp(-localVec.Z / RADAR_MAX_DIST, -1, 1)
					local vLen = math.sqrt(normX*normX + normY*normY)
					if vLen > 1 then
						normX = (normX / vLen) * 0.95
						normY = (normY / vLen) * 0.95
					end
					pBlip.Position = UDim2.new(0.5, normX * RADAR_RADIUS_PX, 0.5, -normY * RADAR_RADIUS_PX)
					pBlip.Visible = true
				else
					pBlip.Visible = false
				end
			end
		end

		-- Enemigos hostiles en Workspace.EnemyDrones (filtrando accesorios)
		local enemyFolder = Workspace:FindFirstChild("EnemyDrones")
		local enemyParts: { BasePart } = {}
		if enemyFolder then
			for _, child in ipairs(enemyFolder:GetChildren()) do
				if child:IsA("BasePart") and child.Name ~= "AccentBand" and child.Name ~= "LaserSight" then
					table.insert(enemyParts, child)
				end
			end
		end

		for i, blip in ipairs(self.radarBlipPool) do
			local enemy = enemyParts[i]
			if enemy and enemy.Parent then
				local toEnemy = enemy.Position - playerDronePos
				local dist = toEnemy.Magnitude
				if dist <= RADAR_MAX_DIST then
					local relCF = CFrame.Angles(0, playerDroneYaw, 0)
					local localVec = relCF:PointToObjectSpace(toEnemy)
					local normX = math.clamp(localVec.X / RADAR_MAX_DIST, -1, 1)
					local normY = math.clamp(-localVec.Z / RADAR_MAX_DIST, -1, 1)
					local vLen = math.sqrt(normX*normX + normY*normY)
					if vLen > 1 then
						normX = (normX / vLen) * 0.95
						normY = (normY / vLen) * 0.95
					end
					blip.Position = UDim2.new(0.5, normX * RADAR_RADIUS_PX, 0.5, -normY * RADAR_RADIUS_PX)
					blip.Visible = true

					if string.find(enemy.Name, "aegis") then
						blip.BackgroundColor3 = Color3.fromRGB(255, 180, 0)
					elseif string.find(enemy.Name, "kuroshio") then
						blip.BackgroundColor3 = Color3.fromRGB(255, 0, 80)
					else
						blip.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
					end
				else
					blip.Visible = false
				end
			else
				blip.Visible = false
			end
		end
	end
end

-- ═══ Pulido Sensorial: Viñeta de daño e indicador direccional de impacto ═══
function DroneHUD.FlashDamageVignette(self: HUDInstance, damage: number, attackerPos: Vector3?, playerDronePos: Vector3?, playerYaw: number?)
	if not self.damageOverlay then return end

	-- Flash en viñeta roja
	self.damageOverlay.BackgroundTransparency = 0.55
	local fadeTween = TweenService:Create(
		self.damageOverlay,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	)
	fadeTween:Play()

	-- Indicador de procedencia de daño si se dispone de vector atacante
	if attackerPos and playerDronePos and playerYaw and self.damageIndicatorArrow then
		local toAttacker = attackerPos - playerDronePos
		local relCF = CFrame.Angles(0, playerYaw, 0)
		local localVec = relCF:PointToObjectSpace(toAttacker)

		local angle = math.deg(math.atan2(localVec.X, -localVec.Z))
		self.damageIndicatorArrow.Rotation = angle
		self.damageIndicatorArrow.Visible = true

		task.delay(0.6, function()
			if self.damageIndicatorArrow then
				self.damageIndicatorArrow.Visible = false
			end
		end)
	end
end

function DroneHUD.SetHealthDisplay(self: HUDInstance, pct: number)
	local hp = math.clamp(pct, 0, 1)
	self.hpFill.Size = UDim2.fromScale(hp, 1)
	self.hpLabel.Text = string.format("INTEGRIDAD HP: %d%%", math.round(hp * 100))
	if hp > 0.6 then
		self.hpFill.BackgroundColor3 = COLOR_HEALTH_NOMINAL
		self.hpLabel.TextColor3 = COLOR_HEALTH_NOMINAL
	elseif hp > 0.3 then
		self.hpFill.BackgroundColor3 = COLOR_HEALTH_MID
		self.hpLabel.TextColor3 = COLOR_HEALTH_MID
	else
		self.hpFill.BackgroundColor3 = COLOR_HEALTH_CRIT
		self.hpLabel.TextColor3 = COLOR_HEALTH_CRIT
	end
end

function DroneHUD.SetHeatDisplay(self: HUDInstance, pct: number)
	local heat = math.clamp(pct, 0, 1)
	self.heatFill.Size = UDim2.fromScale(heat, 1)
	self.heatLabel.Text = string.format("CALOR NÚCLEO: %d%%", math.round(heat * 100))
end

function DroneHUD.SetCrosshairState(
	self: HUDInstance,
	state: "neutral" | "targeting" | "locked",
	targetName: string?,
	distance: number?,
	isAiming: boolean?
)
	local targetColor: Color3
	local containerSize: number
	local horizonWidth: number
	local dotSize: number

	if state == "locked" then
		targetColor = COLOR_WARN
		containerSize = if isAiming then 48 else 58
		horizonWidth = 40
		dotSize = 5
		self.targetLockTag.Visible = true
		self.targetLockTag.TextColor3 = COLOR_WARN
		self.targetLockTag.Text = string.format("[ 🎯 LOCK-ON: %s | %.0fm ]", (targetName or "OBJETIVO"):upper(), distance or 0)
	elseif state == "targeting" then
		targetColor = COLOR_NEON_YELLOW
		containerSize = if isAiming then 54 else 68
		horizonWidth = 50
		dotSize = 4
		self.targetLockTag.Visible = true
		self.targetLockTag.TextColor3 = COLOR_NEON_YELLOW
		self.targetLockTag.Text = string.format("[ ⚡ RASTREO: %s | %.0fm ]", (targetName or "OBJETIVO"):upper(), distance or 0)
	else
		targetColor = COLOR_NEON_CYAN
		containerSize = if isAiming then 64 else 80
		horizonWidth = 60
		dotSize = 4
		self.targetLockTag.Visible = false
	end

	self.centerDot.BackgroundColor3 = targetColor
	self.centerDot.Size = UDim2.fromOffset(dotSize, dotSize)
	self.horizonLine.BackgroundColor3 = targetColor
	self.horizonLine.Size = UDim2.fromOffset(horizonWidth, 2)
	self.crosshair.Size = UDim2.fromOffset(containerSize, containerSize)
	if self.leftBracket then self.leftBracket.TextColor3 = targetColor end
	if self.rightBracket then self.rightBracket.TextColor3 = targetColor end
end

function DroneHUD.SetLeadIndicator(self: HUDInstance, screenPos: Vector2?, isAligned: boolean?)
	if screenPos then
		self.leadIndicator.Visible = true
		self.leadIndicator.Position = UDim2.fromOffset(screenPos.X, screenPos.Y)
		local col = if isAligned then COLOR_NEON_YELLOW else COLOR_NEON_CYAN
		self.leadStroke.Color = col
		self.leadDot.BackgroundColor3 = col
		self.leadTag.TextColor3 = col
		self.leadTag.Text = if isAligned then "TARGET ALIGNED" else "LEAD // MIRA"
		self.leadIndicator.Size = if isAligned then UDim2.fromOffset(22, 22) else UDim2.fromOffset(26, 26)
	else
		self.leadIndicator.Visible = false
	end
end

function DroneHUD.TriggerHitmarker(self: HUDInstance, isKill: boolean)
	local col = if isKill then Color3.fromRGB(255, 45, 45) else Color3.fromRGB(255, 255, 255)
	local tickSize = if isKill then UDim2.fromOffset(3, 11) else UDim2.fromOffset(2, 8)

	for _, tick in ipairs(self.hitmarkerTicks) do
		tick.BackgroundColor3 = col
		tick.Size = tickSize
		tick.BackgroundTransparency = 0
	end
	self.hitmarkerFrame.Visible = true

	if self.hitSound then
		self.hitSound.PlaybackSpeed = if isKill then 1.3 else 1.9
		self.hitSound.Volume = if isKill then 1.0 else 0.75
		self.hitSound:Play()
	end

	task.spawn(function()
		task.wait(0.06)
		local twInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for _, tick in ipairs(self.hitmarkerTicks) do
			TweenService:Create(tick, twInfo, { BackgroundTransparency = 1 }):Play()
		end
		task.wait(0.12)
		self.hitmarkerFrame.Visible = false
	end)
end

function DroneHUD.SetTargetLock(self: HUDInstance, targetName: string?, distance: number?)
	if targetName then
		self:SetCrosshairState("locked", targetName, distance, false)
	else
		self:SetCrosshairState("neutral", nil, nil, false)
	end
end

function DroneHUD.SetMissilesDisplay(self: HUDInstance, remaining: number, maxMissiles: number)
	local maxM = maxMissiles or 3
	local rem = math.clamp(remaining, 0, maxM)
	local pips = ""
	for i = 1, maxM do
		if i <= rem then
			pips = pips .. "■ "
		else
			pips = pips .. "□ "
		end
	end
	pips = pips:gsub("%s+$", "")
	if rem > 0 then
		self.missileStatusLabel.Text = string.format("MISILES [R]: [ %s ] (%d/%d)", pips, rem, maxM)
		self.missileStatusLabel.TextColor3 = Color3.fromRGB(255, 180, 0)
	else
		self.missileStatusLabel.Text = "MISILES [R]: [ □ □ □ ] (0/3 - VACÍO)"
		self.missileStatusLabel.TextColor3 = Color3.fromRGB(255, 60, 60)
	end
end

function DroneHUD.ShowSuccessPopup(
	self: HUDInstance,
	reward: number,
	targetName: string,
	remainingCargo: number?,
	isRestock: boolean?,
	streak: number?,
	multiplier: number?
)
	local currency = getCurrencyName()
	if isRestock then
		local rachaTxt = if streak and streak > 1 then string.format(" (Racha x%d conservada)", streak) else ""
		self.successText.Text = string.format("¡BODEGA REABASTECIDA EN %s!\n+%d %s (3/3 Paquetes Listos)%s", targetName:upper(), reward, currency, rachaTxt)
		self.successText.TextColor3 = COLOR_NEON_CYAN
	elseif remainingCargo == 0 then
		local streakTxt = if streak and streak > 1 then string.format(" (¡Racha x%d! 🔥)", streak) else ""
		self.successText.Text = string.format("¡ENTREGA EXITOSA EN %s!\n+%d %s%s\n¡BODEGA VACÍA! REGRESA A BASE", targetName:upper(), reward, currency, streakTxt)
		self.successText.TextColor3 = COLOR_NEON_YELLOW
	else
		local streakTxt = if streak and streak > 1 then string.format(" (¡Racha x%d! 🔥)", streak) else ""
		self.successText.Text = string.format("¡ENTREGA EXITOSA EN %s!\n+%d %s%s (Quedan %d en bodega)", targetName:upper(), reward, currency, streakTxt, remainingCargo or 1)
		self.successText.TextColor3 = COLOR_NEON_YELLOW
	end
	self.successPopup.Visible = true
	self.successPopup.Size = UDim2.fromOffset(380, 64)

	local tween = TweenService:Create(
		self.successPopup,
		TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(400, 72) }
	)
	tween:Play()

	task.delay(2.5, function()
		if self.successPopup then
			local fade = TweenService:Create(
				self.successPopup,
				TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Size = UDim2.fromOffset(320, 20), BackgroundTransparency = 1 }
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
