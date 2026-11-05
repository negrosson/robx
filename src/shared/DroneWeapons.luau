--!strict
-- src/shared/DroneWeapons.luau
-- Arsenal Táctico Cyberpunk — 4 Familias de Armamento para Cyber Delivery Tycoon
-- Paleta: Base carbón #0D0D0D | Cerámico #FFFFFF | Neón Rojo #FF003F

local DroneWeapons = {}

----------------------------------------------------------------------
-- TIPOS EXPORTADOS
----------------------------------------------------------------------

-- Tipologías de daño
export type DamageType = "kinetic" | "thermal" | "missile" | "cyber"

-- Efectos secundarios que puede aplicar un arma
export type WeaponEffect = {
	type        : string,   -- "dot" | "impulse" | "heat_inject" | "lift_reduction" | "emp"
	value       : number,   -- intensidad del efecto
	duration    : number,   -- segundos que dura
}

-- Ficha completa de un arma
export type WeaponSpec = {
	id              : string,
	name            : string,
	family          : string,
	damageType      : DamageType,
	caliber         : string,  -- "light" | "medium" | "heavy" | "cyber"
	minTier         : number,  -- tier mínimo de dron para equipar

	-- Mecánicas de disparo
	damage          : number,  -- daño base por impacto
	fireRate        : number,  -- disparos por segundo
	projectileSpeed : number,  -- studs/s (0 = hitscan instantáneo)
	range           : number,  -- studs máximos de alcance
	heatGenerated   : number,  -- calor generado en el PORTADOR al disparar
	heatOnTarget    : number,  -- calor inyectado en el OBJETIVO por impacto

	-- Efectos secundarios
	effects         : { WeaponEffect },

	-- Datos de proyectil / rayo
	beamWidth       : number,  -- grosor visual del rayo/proyectil (0 si no aplica)
	beamColor       : Color3,
	projectileColor : Color3,

	-- Descripción de juego
	description     : string,
}

----------------------------------------------------------------------
-- PALETA
----------------------------------------------------------------------
local COL_PLASMA   = Color3.fromRGB(255, 100, 0)    -- naranja magma
local COL_GAUSS    = Color3.fromRGB(180, 220, 255)  -- azul frío electromagnético
local COL_MISSILE  = Color3.fromRGB(255, 230, 0)    -- amarillo guiado
local COL_MICRO    = Color3.fromRGB(180, 0,   255)  -- violeta microondas
local COL_NEON_RED = Color3.fromRGB(255, 0,   63)

----------------------------------------------------------------------
-- 1. TÉRMICA / FUEGO — "Magma-Spike"
-- Lanza-plasma: DoT 3.5s + reducción temporal de sustentación vertical
----------------------------------------------------------------------
local MAGMA_SPIKE: WeaponSpec = {
	id              = "magma_spike",
	name            = "Magma-Spike Mk.II",
	family          = "Thermal / Plasma",
	damageType      = "thermal",
	caliber         = "medium",
	minTier         = 1,

	damage          = 18,    -- daño de impacto inicial
	fireRate        = 1.8,   -- disparos/s (cadencia media-alta)
	projectileSpeed = 120,   -- studs/s (proyectil visible, no hitscan)
	range           = 180,
	heatGenerated   = 4,     -- el tirador también calienta sus sistemas
	heatOnTarget    = 12,    -- calor inyectado en el objetivo por impacto

	effects = {
		{
			type     = "dot",
			value    = 6,      -- daño/s durante la duración
			duration = 3.5,
		},
		{
			type     = "lift_reduction",
			value    = 0.35,   -- 35% menos de sustentación vertical efectiva
			duration = 2.0,    -- dura 2s por turbulencia térmica
		},
	},

	beamWidth       = 0,          -- proyectil físico, sin rayo continuo
	beamColor       = COL_PLASMA,
	projectileColor = COL_PLASMA,
	description     = "Plasma de magnesio acelerado magnéticamente. Funde los actuadores de sustentación. Cadencia media. Detonación térmica sobre superficies orgánicas y metálicas.",
}

----------------------------------------------------------------------
-- 2. CINÉTICA / GAUSS — "Rail-Driver"
-- Hitscan vía Raycast: impulso físico desestabiliza AlignOrientation
----------------------------------------------------------------------
local RAIL_DRIVER: WeaponSpec = {
	id              = "rail_driver",
	name            = "Rail-Driver HVP",
	family          = "Kinetic / Gauss",
	damageType      = "kinetic",
	caliber         = "heavy",
	minTier         = 2,

	damage          = 55,    -- alto daño de impacto directo
	fireRate        = 0.4,   -- baja cadencia (cañón de riel)
	projectileSpeed = 0,     -- 0 = hitscan instantáneo (Raycast)
	range           = 400,   -- largo alcance
	heatGenerated   = 8,     -- sobrecalentamiento considerable del portador
	heatOnTarget    = 5,     -- daño térmico secundario mínimo

	effects = {
		{
			type     = "impulse",
			value    = 85,     -- newtons de impulso aplicados al AlignOrientation del blanco
			duration = 0.6,    -- duración del desestabilizador de orientación
		},
	},

	beamWidth       = 0.15,       -- rayo hitscan delgado y brillante
	beamColor       = COL_GAUSS,
	projectileColor = COL_GAUSS,
	description     = "Proyectil ferromagnético acelerado por bobinas electromagnéticas en cascada. Traspasa cristales y paneles compuestos. El impacto aplica un torque instantáneo que colapsa la estabilización giroscópica del blanco.",
}

----------------------------------------------------------------------
-- 3. MISILES GUIADOS — "Smart Gyro-Lock"
-- Seguimiento Bézier desde cono visual de CyberGoggles
----------------------------------------------------------------------
local SMART_GYRO_LOCK: WeaponSpec = {
	id              = "smart_gyro_lock",
	name            = "Smart Gyro-Lock M4",
	family          = "Smart Missile / Tracking",
	damageType      = "missile",
	caliber         = "heavy",
	minTier         = 2,

	damage          = 80,    -- alto daño de impacto directo (explosión de área)
	fireRate        = 0.3,   -- baja cadencia (un misil a la vez)
	projectileSpeed = 90,    -- studs/s (misil guiado subsónico)
	range           = 350,
	heatGenerated   = 3,
	heatOnTarget    = 8,

	effects = {
		{
			type     = "impulse",
			value    = 120,    -- onda expansiva aplica impulso en radio 20 studs
			duration = 0.3,
		},
	},

	beamWidth       = 0,          -- misil físico
	beamColor       = COL_MISSILE,
	projectileColor = COL_MISSILE,
	description     = "Sistema de misil inteligente con cabeza de seguimiento dual. Corrige su trayectoria en vuelo mediante interpolación vectorial Bézier hasta el último cuarto de trayecto. Detonación de fragmentación al impacto.",
}

----------------------------------------------------------------------
-- 4. CIBERGUERRA / MICROONDAS — "Synapse Overheat"
-- Rayo continuo: inyecta calor hasta estado EMP (LinearVelocity.Enabled = false)
----------------------------------------------------------------------
local SYNAPSE_OVERHEAT: WeaponSpec = {
	id              = "synapse_overheat",
	name            = "Synapse Overheat Emitter",
	family          = "Cyberwarfare / Microwave",
	damageType      = "cyber",
	caliber         = "cyber",
	minTier         = 3,

	damage          = 2,     -- daño directo mínimo (el arma no mata, inhabilita)
	fireRate        = 20,    -- "dispara" 20 veces/s (rayo continuo, tick de simulación)
	projectileSpeed = 0,     -- rayo instantáneo (Raycast continuo)
	range           = 120,   -- corto-medio alcance
	heatGenerated   = 1.5,   -- el emisor también genera calor residual
	heatOnTarget    = 8,     -- 8 puntos de calor/tick × 20Hz = 160 calor/s en el blanco

	effects = {
		{
			type     = "heat_inject",
			value    = 8,      -- calor por tick (a 20 Hz = 160/s en blanco sin disipación)
			duration = 0.05,   -- por tick
		},
		{
			type     = "emp",
			value    = 1,      -- activa estado EMP al llegar al 100% de calor
			duration = 2.0,    -- el EMP dura 2 segundos en caída libre
		},
	},

	beamWidth       = 0.4,        -- rayo de microondas visible y pulsante
	beamColor       = COL_MICRO,
	projectileColor = COL_MICRO,
	description     = "Emisor de microondas de alta frecuencia dirigidas. No destruye el hardware directamente, sino que lo recaliente hasta la desactivación automática de protección. Efectivo contra drones sin blindaje dieléctrico.",
}

----------------------------------------------------------------------
-- ÍNDICE PÚBLICO
----------------------------------------------------------------------
DroneWeapons.All: { WeaponSpec } = {
	MAGMA_SPIKE,
	RAIL_DRIVER,
	SMART_GYRO_LOCK,
	SYNAPSE_OVERHEAT,
}

DroneWeapons.ById: { [string]: WeaponSpec } = {}
for _, spec in ipairs(DroneWeapons.All) do
	DroneWeapons.ById[spec.id] = spec
end

-- Mapeo de calibre a colores para HUD
DroneWeapons.CaliberColors: { [string]: Color3 } = {
	light  = Color3.fromRGB(100, 200, 100),
	medium = Color3.fromRGB(220, 180,  50),
	heavy  = Color3.fromRGB(220,  80,  40),
	cyber  = COL_MICRO,
}

-- Verifica si un arma puede montarse en un dron por calibre y tier
function DroneWeapons.CanEquip(weaponId: string, droneCalibersAllowed: { string }, droneTier: number): boolean
	local spec = DroneWeapons.ById[weaponId]
	if not spec then return false end
	if droneTier < spec.minTier then return false end
	for _, cal in ipairs(droneCalibersAllowed) do
		if cal == spec.caliber then return true end
	end
	return false
end

-- Calcula daño final aplicando reducción de blindaje del blanco
function DroneWeapons.CalculateDamage(weaponId: string, targetArmorReduction: number): number
	local spec = DroneWeapons.ById[weaponId]
	if not spec then return 0 end
	local mitigation = math.clamp(targetArmorReduction, 0, 0.90)
	return math.max(1, spec.damage * (1 - mitigation))
end

-- Devuelve los efectos de un arma filtrados por tipo
function DroneWeapons.GetEffectsByType(weaponId: string, effectType: string): { WeaponEffect }
	local spec = DroneWeapons.ById[weaponId]
	if not spec then return {} end
	local filtered: { WeaponEffect } = {}
	for _, eff in ipairs(spec.effects) do
		if eff.type == effectType then
			table.insert(filtered, eff)
		end
	end
	return filtered
end

return DroneWeapons
