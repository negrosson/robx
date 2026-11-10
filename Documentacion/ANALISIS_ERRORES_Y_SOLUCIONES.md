# 📘 Cyber Delivery Tycoon — Análisis Integral de Errores y Correcciones

**Proyecto:** Cyber Delivery Tycoon (Roblox Luau / Rojo)  
**Fecha de Auditoría y Corrección:** Noviembre, 2026  
**Autor:** Nexsson1 

---

## ⚡ Guía Rápida de Diagnóstico y Resolución (Índice Ejecutivo)

> [!IMPORTANT]
> **Consulta rápida para no tener que leer las 24 secciones detalladas:** Si experimentas un fallo o anomalía en Roblox Studio, ubica el síntoma en esta tabla para conocer de inmediato la causa técnica, el archivo a inspeccionar y la solución aplicada.

| Síntoma / Error | Causa Raíz Técnica | Archivo(s) Clave | Solución Aplicada | Sección |
| :--- | :--- | :--- | :--- | :--- |
| **No aparecen enemigos en el mapa** | Error de sintaxis Luau (`Table.Field: Type =`) abortaba `EnemyAIService` en require; zonas nacían apagadas. | [EnemyTypes.luau](file:///x:/Datos%20Proyectos/robx/src/shared/EnemyTypes.luau)<br>[EnemyAIService.luau](file:///x:/Datos%20Proyectos/robx/src/server/EnemyAIService.server.luau) | Asignar tipos a variables locales (`local x: T = ...; Table.x = x`) y spawn persistente en arranque. | [§21](#21-auditoría-integral-multi-fase), [§22](#22-causa-raíz-oculta) |
| **No se puede reabastecer cargamento en Base** | Split-brain de RemoteEvents (`DeliveryCompleted` iba a instancia huérfana) + bloqueo en `isLanded`. | [NetworkEvents.luau](file:///x:/Datos%20Proyectos/robx/src/shared/NetworkEvents.luau)<br>[DeliveryManager.luau](file:///x:/Datos%20Proyectos/robx/src/shared/DeliveryManager.luau)<br>[DroneController.luau](file:///x:/Datos%20Proyectos/robx/src/shared/DroneController.luau) | Instancia canónica única de RemoteEvent + Triple Capa de Restock (Touchdown, [G] manual y Auto-recarga al despegar). | [§24](#24-reabastecimiento-instantáneo-de-bodega) |
| **Ataques enemigos débiles o sin impacto** | Umbral de contacto muy estrecho (6 studs a 10 Hz) y falta de proyectiles/SFX telegrafiados. | [EnemyAIService.server.luau](file:///x:/Datos%20Proyectos/robx/src/server/EnemyAIService.server.luau) | Picado a 68 studs/s y 11 studs para Gnats; Cañón Gauss con telémetro carmesí y SFX para Aegis-44; haz dual microondas para Kuroshio. | [§23](#23-pulido-dinámico-de-combate) |
| **Dron sube al presionar tecla descender (Shift/Ctrl)** | Inversión de signo en cálculo vectorial `moveY = 1 - (-1) = +1`. | [DroneController.luau](file:///x:/Datos%20Proyectos/robx/src/shared/DroneController.luau) | Corrección a `moveY = (up) - (down)` con enteros positivos y soporte Shift/Ctrl/C. | [§2](#2-error-crítico-1) |
| **Tecla [E] no responde o queda en `CARGANDO...`** | Módulos secundarios requeridos de forma síncrona en el nivel superior (*top-level require hang*). | [DroneController.luau](file:///x:/Datos%20Proyectos/robx/src/shared/DroneController.luau)<br>[Main.client.luau](file:///x:/Datos%20Proyectos/robx/src/client/Main.client.luau) | Lazy loading con protección de errores (`pcall`) dentro de `DroneController.new()`. | [§3](#3-error-crítico-2) |
| **WASD no responde una vez en el aire** | `gameProcessedEvent` (`gpe`) de Roblox Character Controller consumía las teclas de movimiento. | [DroneController.luau](file:///x:/Datos%20Proyectos/robx/src/shared/DroneController.luau) | Bypassear filtro de `gpe` para teclas WASD/Espacio/Shift cuando `isFlying == true`. | [§4](#4-error-crítico-3) |
| **Dron tiembla o cae al suelo al despegar** | Conflicto de Network Ownership y anclaje entre personaje y `TestDrone`. | [Main.server.luau](file:///x:/Datos%20Proyectos/robx/src/server/Main.server.luau)<br>[DroneController.luau](file:///x:/Datos%20Proyectos/robx/src/shared/DroneController.luau) | Servidor desancla y transfiere propiedad física mediante `SetNetworkOwner(player)`. | [§5](#5-error-crítico-4) |
| **«SISTEMA DE ENTREGA NO DISPONIBLE» al presionar [G]** | `DeliveryManager` era `nil` en cliente por replicación asíncrona tardía de módulos. | [DroneController.luau](file:///x:/Datos%20Proyectos/robx/src/shared/DroneController.luau)<br>[DeliveryManager.luau](file:///x:/Datos%20Proyectos/robx/src/shared/DeliveryManager.luau) | Lazy recovery bajo demanda al presionar [G] y fallback automático de helipuertos. | [§11](#11-corrección-definitiva-error) |
| **Créditos no se sumaban en leaderstats** | Discrepancia en nombre de divisa (`PELAOCOINS` vs `PIGICOINS` vs `CyberCréditos`). | [Main.server.luau](file:///x:/Datos%20Proyectos/robx/src/server/Main.server.luau) | Búsqueda desacoplada por tipo (`IntValue` de leaderstats) tolerante a nombres de moneda. | [§12](#12-desacople-del-nombre-de-la-moneda) |
| **Cámara FPV se desalinea o roll excesivo** | Cálculo de inclinación lateral acumulaba pitch y yaw sin estabilización giroscópica. | [DroneController.luau](file:///x:/Datos%20Proyectos/robx/src/shared/DroneController.luau) | Giro con mouse en `FlightYaw`/`Pitch` y estabilización automática de balanceo en reposo. | [§13](#13-pulido-de-primera-persona-fpv) |
| **Radar en HUD no detectaba enemigos lejanos** | Radio máximo de radar en 250 studs (Torre A está a 257 studs de Base). | [DroneHUD.luau](file:///x:/Datos%20Proyectos/robx/src/shared/DroneHUD.luau) | Ampliación de alcance a 320 studs y acentos de color neón ámbar/rojo de alta salencia. | [§20](#20-auditoría-y-corrección-de-visibilidad) |
| **Dron se bugea tras ser destruido 2 veces** | Desincronización de estado: `isPiloting` quedaba en `true` en cliente (no escuchaba `StopFlying`/`DroneDestroyed`), y HP no se reseteaba en cliente. | [CombatService.server.luau](file:///x:/Datos%20Proyectos/robx/src/server/CombatService.server.luau)<br>[Main.client.luau](file:///x:/Datos%20Proyectos/robx/src/client/Main.client.luau)<br>[DroneController.luau](file:///x:/Datos%20Proyectos/robx/src/shared/DroneController.luau) | Callback bidireccional cliente-servidor, reseteo atómico de cámara y variables, teleport a cabina y restauración de botón [E]. | [§25](#25-resincronización-y-recuperación-robusta-tras-destrucción-de-dron) |
| **Dificultad para apuntar en 3ra persona** | Falta de retícula/mira diegética alineada al vector de cámara y dispersión angular de proyectiles. | [DroneHUD.luau](file:///x:/Datos%20Proyectos/robx/src/shared/DroneHUD.luau)<br>[DroneController.luau](file:///x:/Datos%20Proyectos/robx/src/shared/DroneController.luau) | Retícula holográfica universal centrada por `ViewportPointToRay`, escaneo cónico de 16° y fijación (*Target Lock*) de drones hostiles. | [§26](#26-mira-holográfica-universal-y-fijación-cónica-de-objetivos-en-3ra-persona-y-fpv) |
| **Sin misiles guiados ni economía de munición** | No existía sistema de proyectiles guiados de capacidad limitada ni ciclo de recarga por entregas o compra. | [DroneController.luau](file:///x:/Datos%20Proyectos/robx/src/shared/DroneController.luau)<br>[DroneHUD.luau](file:///x:/Datos%20Proyectos/robx/src/shared/DroneHUD.luau)<br>[DeliveryManager.luau](file:///x:/Datos%20Proyectos/robx/src/shared/DeliveryManager.luau)<br>[Main.server.luau](file:///x:/Datos%20Proyectos/robx/src/server/Main.server.luau) | Misiles guiados con tecla [R] (Bézier 3D), rack de 3 proyectiles, recarga automática tras 3 entregas o compra por 150 PELAOCOINS en Base [M]. | [§27](#27-sistema-de-misiles-guiados-térmicos-r-rack-de-3-municiones-y-recarga-dual) |
| **No deja ocupar el dron con la tecla [E]** | Split-brain de RemoteEvents (`CombatService` creaba `DroneFlightState` huérfano en `ReplicatedStorage` ignorado por `Main.server`), desincronización de flags `isPiloting`/`isFlying` al morir el avatar, y falta de prompt 3D. | [CombatService.server.luau](file:///x:/Datos%20Proyectos/robx/src/server/CombatService.server.luau)<br>[Main.client.luau](file:///x:/Datos%20Proyectos/robx/src/client/Main.client.luau)<br>[DroneController.luau](file:///x:/Datos%20Proyectos/robx/src/shared/DroneController.luau)<br>[Main.server.luau](file:///x:/Datos%20Proyectos/robx/src/server/Main.server.luau) | Unificación canónica vía `NetworkEvents.Get`, sincronizador bidireccional `SetOnStateChangedCallback`, guardia `isCurrentlyPiloting` y `ProximityPrompt` 3D diegético en `TestDrone`. | [§28](#28-corrección-integral-de-enlace-de-pilotaje-con-tecla-e) |
| **Disparos y láseres atraviesan las torres** | `hasLineOfSight` evaluaba `hitPart:IsDescendantOf(Workspace)` (siempre `true`), no ocluía partes de material Neon/Glass en rascacielos, proyectiles se tweeneaban sin raycast de trayectoria, y `LaserSight` era un box estático sin colisión. | [EnemyAIService.server.luau](file:///x:/Datos%20Proyectos/robx/src/server/EnemyAIService.server.luau)<br>[CombatService.server.luau](file:///x:/Datos%20Proyectos/robx/src/server/CombatService.server.luau)<br>[DroneController.luau](file:///x:/Datos%20Proyectos/robx/src/shared/DroneController.luau) | Raycast físico multi-etapa con oclusión estricta de estructuras, clamping de trayectoria en la superficie de la torre, chispas de impacto, y detonación temprana de misiles en obstáculos. | [§29](#29-oclusión-balística-y-físicas-de-impacto-contra-estructuras-y-torres) |

---

## 📑 Tabla de Contenidos Completa
1. [Resumen Ejecutivo](#1-resumen-ejecutivo)
2. [Error Crítico 1: El Dron solo sube y no puede descender (Sign Inversion Bug)](#2-error-crítico-1-el-dron-solo-sube-y-no-puede-descender)
3. [Error Crítico 2: Bloqueo de Carga y Tecla [E] Inoperativa (Top-Level Requires Hang)](#3-error-crítico-2-bloqueo-de-carga-y-tecla-e-inoperativa)
4. [Error Crítico 3: Bloqueo de Teclas WASD por el Character Controller (GPE Flag)](#4-error-crítico-3-bloqueo-de-teclas-wasd-por-el-character-controller)
5. [Error Crítico 4: Conflicto de Físicas y Network Ownership (HumanoidRootPart Anchoring)](#5-error-crítico-4-conflicto-de-físicas-y-network-ownership)
6. [Mejoras de Conducción, Físicas y Mapeo de Controles](#6-mejoras-de-conducción-físicas-y-mapeo-de-controles)
7. [Matriz de Estado y Diagnóstico de Archivos](#7-matriz-de-estado-y-diagnóstico-de-archivos)
8. [Fase de Seguridad y Arquitectura Server-Side (v4.1)](#8-fase-de-seguridad-y-arquitectura-server-side-v41)
9. [Fase 2: Catálogo de Drones, Arsenal Táctico, IA Enemiga 3D y Físicas de Inercia](#9-fase-2-catálogo-de-drones-arsenal-táctico-ia-enemiga-3d-y-físicas-de-inercia)
10. [Optimización de Helipuertos y Sistema de Desenganche Físico de Entrega con Tecla [G]](#10-optimización-de-helipuertos-y-sistema-de-desenganche-físico-de-entrega-con-tecla-g)
11. [Corrección Definitiva: Error «SISTEMA DE ENTREGA NO DISPONIBLE» y Resiliencia de Red](#11-corrección-definitiva-error-sistema-de-entrega-no-disponible-y-resiliencia-de-red)
12. [Desacople del Nombre de la Moneda («PIGICOINS») y Resiliencia en Validación Server-Side](#12-desacople-del-nombre-de-la-moneda-pigicoins-y-resiliencia-en-validación-server-side)
13. [Pulido de Primera Persona (FPV) con Giro de Mouse y Corrección Aerodinámica de Inclinación Lateral (Roll)](#13-pulido-de-primera-persona-fpv-con-giro-de-mouse-y-corrección-aerodinámica-de-inclinación-lateral-roll)
14. [Sistema Logístico de Bodega (3 Paquetes), Ciclo de Reabastecimiento en Base Central y Tolvas Receptoras en Torres](#14-sistema-logístico-de-bodega-3-paquetes-ciclo-de-reabastecimiento-en-base-central-y-tolvas-receptoras-en-torres)
15. [Fase 1 Enriquecida: Red de Rutas con Niveles de Amenaza, Despacho Táctico y Multiplicador de Rachas (Delivery Streak)](#15-fase-1-enriquecida-red-de-rutas-con-niveles-de-amenaza-despacho-táctico-y-multiplicador-de-rachas-delivery-streak)
16. [Fase 2 Enriquecida: Orquestación Espacial de IA, Particionado por Zonas y Director de Amenaza Dinámico (Threat Director)](#16-fase-2-enriquecida-orquestación-espacial-de-ia-particionado-por-zonas-y-director-de-amenaza-dinámico-threat-director)
17. [Fase 3: Arsenal Táctico del Jugador, Cañón de Plasma, Contramedida EMP y Recompensas (Bounties)](#17-fase-3-arsenal-táctico-del-jugador-cañón-de-plasma-contramedida-emp-y-recompensas-bounties)
18. [Fase 4: Telemetría HUD Avanzada, Barras de Núcleo (HP/Heat), Radar Táctico 360° y Viñeta de Daño](#18-fase-4-telemetría-hud-avanzada-barras-de-núcleo-hpheat-radar-táctico-360-y-viñeta-de-daño)
19. [Fase 5: Rutas Dinámicas, Pérdida de Carga Física por Daño Crítico y Progresión de Rango](#19-fase-5-rutas-dinámicas-pérdida-de-carga-física-por-daño-crítico-y-progresión-de-rango)
20. [Auditoría y Corrección de Visibilidad, Físicas y Patrulla de IA Hostil](#20-auditoría-y-corrección-de-visibilidad-físicas-y-patrulla-de-ia-hostil)
21. [Auditoría Integral Multi-Fase: Causa Raíz de Desaparición de Enemigos y Solución Arquitectónica Definitiva](#21-auditoría-integral-multi-fase-causa-raíz-de-desaparición-de-enemigos-y-solución-arquitectónica-definitiva)
22. [Causa Raíz Oculta: Error Fatal de Sintaxis de Luau VM (`Table.Field: Type =`)](#22-causa-raíz-oculta-error-fatal-de-sintaxis-de-luau-vm-tablefield-type-)
23. [Pulido Dinámico de Combate y Ataques de Drones Hostiles](#23-pulido-dinámico-de-combate-y-ataques-de-drones-hostiles)
24. [Reabastecimiento Instantáneo de Bodega en Base Central (Triple Capa)](#24-reabastecimiento-instantáneo-de-bodega-en-base-central-triple-capa)
25. [Resincronización y Recuperación Robusta tras Destrucción de Dron](#25-resincronización-y-recuperación-robusta-tras-destrucción-de-dron)
26. [Mira Holográfica Universal y Fijación Cónica de Objetivos en 3ra Persona y FPV](#26-mira-holográfica-universal-y-fijación-cónica-de-objetivos-en-3ra-persona-y-fpv)
27. [Sistema de Misiles Guiados Térmicos [R], Rack de 3 Municiones y Recarga Dual (3 Entregas o 150 PELAOCOINS [M])](#27-sistema-de-misiles-guiados-térmicos-r-rack-de-3-municiones-y-recarga-dual)
28. [Corrección Integral de Enlace de Pilotaje con Tecla [E]](#28-corrección-integral-de-enlace-de-pilotaje-con-tecla-e)
29. [Oclusión Balística y Físicas de Impacto contra Estructuras y Torres](#29-oclusión-balística-y-físicas-de-impacto-contra-estructuras-y-torres)

---

## 1. Resumen Ejecutivo
Durante el desarrollo del sistema de pilotaje para **Cyber Delivery Tycoon**, se detectaron fallos críticos que impedían la experiencia de vuelo:
1. El dron ascendía al presionar la tecla de descender.
2. La tecla `[E]` no activaba el dron o se quedaba permanentemente en estado `(CARGANDO...)`.
3. Una vez en el aire, el dron no respondía a los controles horizontales o se aceleraba instantáneamente sin inercia.

A continuación se detalla la causa raíz técnica de cada falla y la ingeniería aplicada para resolverla.

---

## 2. Error Crítico 1: El Dron solo sube y no puede descender

### 🔍 Causa Raíz
En el bucle de actualización física de `DroneController.luau`, el vector de entrada vertical (`moveY`) se calculaba con la siguiente expresión ternaria:

```luau
-- ❌ CÓDIGO CON ERROR:
local moveY = (if self.inputState.up then 1 else 0) - (if self.inputState.down then -1 else 0)
```

**Análisis Algebraico del Fallo:**
* Al presionar `Espacio` (Subir / Up):
  $$\text{moveY} = 1 - 0 = +1 \quad (\text{Sube})$$
* Al presionar `Shift` (Bajar / Down):
  $$\text{moveY} = 0 - (-1) = 0 + 1 = +1 \quad (\mathbf{¡Sube!})$$
* Al presionar ambas teclas:
  $$\text{moveY} = 1 - (-1) = 1 + 1 = +2 \quad (\mathbf{¡Sube\ al\ doble\ de\ velocidad!})$$

Debido a que restar un número negativo equivale a una suma ($a - (-b) = a + b$), **era matemáticamente imposible obtener un valor negativo para `moveY`**. El dron interpretaba la orden de descender como una orden de ascenso.

### 🛠️ Solución Aplicada
Se corrigió la expresión para que la sustracción opere sobre un valor positivo:

```luau
-- ✅ CÓDIGO CORREGIDO:
local moveY = (if self.inputState.up then 1 else 0) - (if self.inputState.down then 1 else 0)
```

Adicionalmente, se amplió el soporte de teclas en `BindInputs` para permitir descender con:
* `LeftShift` (Shift izquierdo)
* `LeftControl` (Control izquierdo)
* `C` (Tecla estándar de agacharse/descender)

---

## 3. Error Crítico 2: Bloqueo de Carga y Tecla [E] Inoperativa

### 🔍 Causa Raíz
En versiones anteriores de `DroneController.luau`, se invocaban módulos secundarios en el nivel superior (*top-level*) del script:

```luau
-- ❌ Invocación sincrónica bloqueante en la cabecera:
local DroneHUD = require(script.Parent:WaitForChild("DroneHUD"))
local DroneAudio = require(script.Parent:WaitForChild("DroneAudio"))
local DroneVFX = require(script.Parent:WaitForChild("DroneVFX"))
local DroneCargo = require(script.Parent:WaitForChild("DroneCargo"))
local DeliveryManager = require(script.Parent:WaitForChild("DeliveryManager"))
local CyberGoggles = require(script.Parent:WaitForChild("CyberGoggles"))
```

Si cualquiera de estos componentes demoraba en replicarse desde `ReplicatedStorage` o generaba una advertencia/yield, la ejecución del módulo completo se suspendía indefinidamente. Como consecuencia:
* `Main.client.luau` se quedaba esperando a `DroneController`.
* La variable `myDrone` nunca se instanciaba (`nil`).
* El botón permanecía en `[E] CONECTAR GAFAS FPV (CARGANDO...)` y presionar `[E]` no ejecutaba ninguna acción.

### 🛠️ Solución Aplicada
Se implementó un patrón de **Lazy Loading Seguro con Protección de Errores (`pcall`)** dentro de `DroneController.new()`:
* Ningún módulo se carga en el top-level.
* Los submódulos se importan únicamente cuando el controlador es instanciado.
* Si un subsistema secundario (por ejemplo, el audio o una partícula) sufre algún inconveniente, el sistema de vuelo principal continúa operativo al 100%.

---

## 4. Error Crítico 3: Bloqueo de Teclas WASD por el Character Controller

### 🔍 Causa Raíz
En `UserInputService.InputBegan`, se utilizaba la condición estándar:

```luau
-- ❌ gpe bloqueaba las teclas de movimiento:
self.inputBeganConn = UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    ...
```

En Roblox, el `PlayerModule` (controlador de movimiento del personaje) procesa las teclas `W`, `A`, `S`, `D` antes que los scripts del usuario y marca la bandera `gameProcessedEvent` (`gpe`) como `true`. Como resultado, el dron ignoraba completamente las pulsaciones de dirección.

### 🛠️ Solución Aplicada
1. Se deshabilitó el filtrado de `gpe` para teclas de juego durante la sesión de pilotaje.
2. Para evitar que el avatar camine en el suelo mientras pilota el dron, se neutraliza el movimiento del personaje asignando:
   ```luau
   humanoid.WalkSpeed = 0
   humanoid.JumpHeight = 0
   humanoid.JumpPower = 0
   ```
3. Se desactivan los controles nativos mediante `playerControls:Disable()`.

---

## 5. Error Crítico 4: Conflicto de Físicas y Network Ownership

### 🔍 Causa Raíz
Inicialmente se intentaba anclar el `HumanoidRootPart` del avatar desde el cliente (`root.Anchored = true`) al momento de subir al dron. Esto creaba un conflicto de sincronización entre el cliente y el servidor:
* El motor de físicas de Roblox priorizaba la simulación del personaje anclado.
* `SetNetworkOwner(player)` sobre el `TestDrone` en el servidor no lograba transferir el control suavemente porque el cliente estaba en un estado físico ambiguo.

### 🛠️ Solución Aplicada
* Se eliminó el anclaje forzado de `HumanoidRootPart` en el cliente.
* La inmovilidad del avatar se gestiona únicamente mediante `WalkSpeed = 0` y `JumpPower = 0`.
* El servidor se encarga de desanclar el `TestDrone` (`dronePart.Anchored = false`) inmediatamente antes de otorgar el `SetNetworkOwner(player)`.

---

## 6. Mejoras de Conducción, Físicas y Mapeo de Controles

### 🎛️ Tabla de Controles del Dron
| Tecla | Acción | Descripción |
|---|---|---|
| **W** | Avanzar | Empuje frontal alineado a la vista de la cámara |
| **S** | Retroceder | Empuje en reversa |
| **A** | Alabeo / Giro Izq. | Desplazamiento lateral izquierdo con inclinación |
| **D** | Alabeo / Giro Der. | Desplazamiento lateral derecho con inclinación |
| **Espacio** | Ascender | Impulso vertical positivo constante |
| **Shift / Ctrl / C** | Descender | Impulso vertical negativo suave hacia helipuerto |
| **Q** | Turbo Neón | Incrementa la velocidad de 60 a 110 studs/s |
| **X** | Freno Aéreo | Deceleración rápida asistida por propulsores |
| **V** | Alternar Cámara | Alterna entre vista FPV en cabina y vista 3ra persona |
| **E / F** | Desconectar Gafas | Regresa al avatar y ancla el dron en el helipuerto |

### 🚀 Calibración de Inercia Progresiva
* **Velocidad Crucero:** 60 studs/s (antes 75, optimizada para aterrizajes de precisión).
* **Velocidad Turbo:** 110 studs/s (con consumo de energía holográfica).
* **Tasa de Aceleración (`accelRate`):** 1.5 (suavizado progresivo mediante interpolación lineal `Lerp`).
* **Tasa de Frenado (`brakeRate`):** 3.5 con tecla `X`.

---

## 7. Matriz de Estado y Diagnóstico de Archivos

| Archivo | Estado | Responsabilidad |
|---|---|---|
| `src/server/Main.server.luau` | ✅ Operativo | Generación de helipuertos, economía (`leaderstats`), `TestDrone` y delegación de `NetworkOwnership`. |
| `src/client/Main.client.luau` | ✅ Operativo | HUD de estado en pantalla, detección de tecla `[E]`, equipamiento de gafas cyberpunk y arranque seguro. |
| `src/shared/DroneController.luau` | ✅ Operativo | Motor de física con `LinearVelocity` y `AlignOrientation`, inercia progresiva, descenso y ascenso. |
| `src/shared/DroneHUD.luau` | ✅ Operativo | Interfaz cyberpunk con velocímetro, altímetro, minimapa/waypoint, barra de turbo y popup de recompensas. |
| `src/shared/DroneAudio.luau` | ✅ Operativo | Modulación continua de pitch y volumen de turbina según velocidad y empuje. |
| `src/shared/DroneVFX.luau` | ✅ Operativo | 4 estelas de neón cian/magenta en las esquinas de los propulsores y partículas de plasma. |
| `src/shared/DroneCargo.luau` | ✅ Operativo | Contenedor acoplado en la parte inferior con rayo tractor. |
| `src/shared/DeliveryManager.luau` | ✅ Operativo | Detección de aterrizaje en helipuertos, cálculo de recompensas y asignación de rutas. |
| `src/shared/CyberGoggles.luau` | ✅ Operativo | Visor holográfico en la cabeza del avatar con lentes iluminados al conectar FPV. |
| `src/shared/NetworkEvents.luau` | ✅ Operativo | Módulo centralizado de RemoteEvents tipados para cliente y servidor. |

---

## 8. Fase de Seguridad y Arquitectura Server-Side (v4.1)

### 🛡️ 1. Validación Server-Side Anti-Exploits (`Main.server.luau`)
Anteriormente, el evento `DeliveryCompleted` aceptaba peticiones directas del cliente sin validación física, permitiendo potencialmente cobros arbitrarios. Se implementó una triple barrera en el servidor:
1. **Cooldown de Entrega:** Límite mínimo de 3 segundos entre entregas por jugador para evitar peticiones masivas en bucle.
2. **Validación de Rango Físico:** Verificación de coordenadas reales entre `TestDrone` y el helipuerto (`distancia horizontal <= 18 studs`, `desplazamiento vertical entre -2 y +10 studs`).
3. **Validación de Velocidad de Aterrizaje:** El servidor exige que la velocidad lineal del chasis (`AssemblyLinearVelocity.Magnitude`) sea inferior o igual a 20 studs/s en el momento del reclamo.
4. **Respuesta Verificada:** Solo tras superar los 3 filtros, el servidor otorga `CyberCréditos`, incrementa las entregas y dispara el evento `DeliveryConfirmed` de vuelta al cliente.

### 🌐 2. Centralización de Remotes (`NetworkEvents.luau`)
Se eliminaron las búsquedas dispersas de `RemoteEvents` con strings mágicos en el DataModel. El nuevo módulo `src/shared/NetworkEvents.luau`:
* Genera e inicializa los eventos de red en una carpeta dedicada (`CyberNetworkEvents`).
* Ofrece resolución segura con `NetworkEvents.Get(...)` para cliente y servidor con tipado estricto.

### 🧹 3. Ciclo de Vida y Limpieza de Recursos (`:Destroy()`)
Se integró el método `:Destroy()` en `DroneController.luau` y `DeliveryManager.luau`:
* Desconecta los bucles de actualización física (`RenderStepped`).
* Destruye de forma segura los ScreenGuis de la interfaz holográfica (`DroneHUD`).
* Libera sonidos de turbinas con fade out gradual (`DroneAudio`).
* Elimina emisores y estelas (`DroneVFX`), contenedores (`DroneCargo`) y desvincula eventos de entrada del teclado.

---

## 9. Fase 2: Catálogo de Drones, Arsenal Táctico, IA Enemiga 3D y Físicas de Inercia

### 🛸 1. Catálogo de Drones con Tributo Histórico (`src/shared/DroneCatalog.luau`)
Se implementó un catálogo tipado (`--!strict`) con 4 Tiers y 5 drones de autor que homenajean a pioneros de la aviación, radio y cibernética mediante códigos industriales y patentes históricas:
1. **Tel-98 «Teleautomaton» (Tier 1):** Homenaje a la patente US613809 (Nikola Tesla, 1898) sobre control remoto por radiofrecuencia. Quad experimental ligero con blindaje dieléctrico (resistencia EMP del 55%) y 1 punto de anclaje.
2. **Oehm-24 «Multicross» (Tier 2):** Homenaje al vuelo en circuito cerrado de Étienne Œhmichen (1924). Quad equilibrado con alta respuesta vertical (42 studs/s) optimizado para cañones urbanos estrechos.
3. **Breg-07 «Gyro-Wing» (Tier 2):** Homenaje al Gyroplane No.1 de Louis Breguet (1907). Rotores basculantes con velocidad crucero elevada (80 studs/s, turbo 130 studs/s) e inclinación agresiva de 26°.
4. **Skor-39 «Heavy-Lift» (Tier 3):** Homenaje al VS-300 de Igor Sikorsky (1939). Hexacóptero blindado con 280 HP, reducción pasiva de daño del 25%, gran bahía de carga y 3 anclajes de armas.
5. **W-NER «Daemon-Link» (Tier 4):** Homenaje a Norbert Wiener y la teoría cibernética (1948). Propulsión antigravedad/iónica sin hélices mecánicas, disipación de calor instantánea (22 pts/s), 80% resistencia a EMP y enlace neuronal de respuesta inmediata.

Incluye la función puente `DroneCatalog.ToControllerConfig(spec)` para traducir automáticamente cualquier ficha de dron a los parámetros de vuelo leídos por `DroneController.new()`.

### ⚡ 2. Arsenal Táctico y Tipologías de Daño (`src/shared/DroneWeapons.luau` y `CombatService.server.luau`)
Se diseñó un sistema armamentístico en 4 familias tecnológicas cyberpunk:
1. **Térmica / Plasma («Magma-Spike Mk.II»):** Lanza-plasma que aplica daño continuo (*DoT* de 6 HP/s durante 3.5s) y genera turbulencia térmica que reduce la sustentación vertical de la víctima en un 35% durante 2 segundos.
2. **Cinética / Gauss («Rail-Driver HVP»):** Cañón de riel hipersónico (*Hitscan* mediante `Raycast` autoritativo). Atraviesa cristales/paneles compuestos y aplica un impulso de 85 Newtons que colapsa momentáneamente el `AlignOrientation` del blanco provocando pérdida de control angular.
3. **Misiles Guiados («Smart Gyro-Lock M4»):** Cabeza buscadora subsónica (90 studs/s) que corrige su trayectoria hacia el objetivo mediante curvas Bézier cuadráticas y detona con onda de fragmentación (120 N de impulso).
4. **Ciberguerra / Microondas («Synapse Overheat»):** Rayo continuo de alta frecuencia (20 Hz) que inyecta calor térmico puro en el hardware enemigo. Al llegar al 100% de calor, fuerza un estado `Overheated/EMP` que apaga las restricciones de vuelo (`LinearVelocity.Enabled = false` y `AlignOrientation.Enabled = false`) durante 2 segundos provocando caída libre gravitatoria.

### 🤖 3. Facciones Hostiles e Inteligencia Artificial 3D a 10 Hz (`EnemyTypes.luau` y `EnemyAIService.server.luau`)
Se desarrolló un subsistema de IA pura sin `PathfindingService`, ejecutado en el servidor a 10 Hz mediante acumuladores sobre `RunService.Heartbeat`:
1. **Scav-Gnats (Enjambre Chatarrero):** Pequeños quads que operan en enjambre utilizando algoritmos de separación y persecución (*Seek* + *Separation*). Aplican embestidas físicas directas (*Ramming*) de 55 N para desestabilizar al dron del jugador y forzar la caída o destrucción de paquetes.
2. **Aegis-44 (Torreta Estacionaria):** Centinelas en cornisas con cono de detección angular de 120°. Realizan intercepción balística y disparan ráfagas de Rail-Driver si detectan naves sin autorización en un radio de 160 studs.
3. **Kuroshio V (Interceptores Corporativos):** Drones de intercepción ágiles (70 studs/s) que calculan vectores tangenciales para orbitar lateralmente a 100 studs del jugador mientras lo hostigan con microondas para inducir sobrecalentamiento.

### 📦 4. Acoplamiento Físico con Cargas e Inercia Real (`DroneCargo.luau` y `DroneController.luau`)
El peso de los paquetes afecta la simulación dinámica en tiempo real:
- **Penalización de Velocidad:** $\text{VelocidadEfectiva} = \frac{\text{VelocidadBase}}{1 + (\text{MasaCarga} \times \alpha)}$, garantizando una respuesta más pesada, mayor distancia de frenado y menor aceleración.
- **Detonación por Energía Cinética:** El sistema evalúa el impacto cinético ($E_k = \frac{1}{2} M_{\text{total}} \|\vec{v}\|^2$). Si una carga clasificada como inestable choca a alta velocidad superando el umbral de 4,000 Joules, se genera una detonación física con `Explosion` que destruye el contenedor y desestabiliza el dron.

---

## 10. Optimización de Helipuertos y Sistema de Desenganche Físico de Entrega con Tecla [G]

### 🏷️ 1. Simplificación de Nombres de Helipuertos y Señalética Holográfica
Para evitar confusión con lore cyberpunk en esta fase de desarrollo y ofrecer máxima claridad operativa en el mapa y la interfaz:
* **Pad_Base** (Posición: `0, 4, 0`): Helipuerto central de operaciones y recarga con rampa de acceso. Letrero holográfico 3D: `BASE`.
* **Pad_TorreA** (Posición: `160, 95, -180`, Altura: 95 studs): Rascacielos principal en neón magenta con antena de comunicaciones. Letrero holográfico 3D: `TORRE A`.
* **Pad_TorreB** (Posición: `-200, 50, 140`, Altura: 50 studs): Rascacielos intermedio en neón dorado. Letrero holográfico 3D: `TORRE B`.

Se sincronizaron de forma homogénea las definiciones en `Main.server.luau`, `DeliveryManager.luau` y `DroneHUD.luau`.

### 📦 2. Diagnóstico y Corrección Integral de la Tecla [G] y la Entrega de Carga
**Causa Raíz de que «la tecla G no dejaba el paquete»:**
1. **Falta de Desacople Físico Real:** En versiones previas, `DroneCargo.DeliverAndReload()` creaba un clon estático anclado en el helipuerto pero **nunca destruía el `WeldConstraint`** ni modificaba `self.cargoBox`. Por tanto, el jugador seguía viendo la caja pegada a la panza del dron en todo momento, dando la impresión de que presionar `[G]` no tenía ningún efecto.
2. **Tolerancias de Zona Excesivamente Rígidas:** El radio horizontal estaba fijado en 22 studs y la altura máxima en 12 studs. En helipuertos de 32 a 36 studs de ancho, si el dron sobrevolaba a 14 studs de altitud o cerca del borde exterior de la plataforma, `CheckPadZone` retornaba `false` y cancelaba la entrega sin retroalimentación visual clara.
3. **Falta de Feedback en Caso Fuera de Zona:** Si el usuario presionaba `[G]` en vuelo o en la base, no recibía un mensaje explicativo visible en pantalla.

**Solución Implementada:**
1. **Desenganche Dinámico por Gravedad:**
   * Al validarse la entrega, `self.weld:Destroy()` destruye de inmediato la unión física.
   * `self.cargoBox` activa colisión (`CanCollide = true`), desactiva massless (`Massless = false`) y se desancla (`Anchored = false`).
   * Se transfiere la velocidad lineal y angular del dron más un vector de descenso (`Vector3.new(0, -6, 0)`), haciendo que la caja caiga por gravedad real y ruede/se asiente sobre el helipuerto.
   * El haz tractor magnético se apaga temporalmente y suena un pitido de liberación magnética (`rbxassetid://9114223170`).
   * La caja liberada pasa a `Workspace` y se limpia tras 25 segundos con `Debris`.
2. **Recarga Asíncrona de Nuevo Pedido:**
   * Tras 1.5 segundos de soltar la carga, `ReloadFreshCargo()` genera automáticamente un nuevo contenedor sellado bajo el dron, restablece el `WeldConstraint`, reactiva el haz tractor magnético holográfico y asigna el siguiente destino de reparto.
3. **Ampliación de Tolerancias de Detección:**
   * Radio horizontal ampliado a **30 studs** (cubre todo el helipuerto y su borde con holgura).
   * Rango de altitud vertical ampliado de **-4 a +25 studs** (permite planear cómodamente sobre la plataforma sin peligro de colisión).
   * Velocidad máxima autorizada ampliada a **35–40 studs/s** para permitir entregas dinámicas al vuelo.
4. **Retroalimentación en Tiempo Real en HUD:**
   * Si el jugador pulsa `[G]` fuera de zona, el HUD muestra en rojo: `[G] NO DISPONIBLE: Helipuerto más cercano: Torre A a XX studs`.
   * Si pulsa `[G]` en la base inicial antes de salir, se le indica: `Ya estás en Base. Vuela hacia Torre A`.
   * Al entregar exitosamente, se muestra el popup dorado: `¡ENTREGA EXITOSA EN TORRE A! +250 CYBER-CRÉDITOS`.

---

## 11. Corrección Definitiva: Error «SISTEMA DE ENTREGA NO DISPONIBLE» y Resiliencia de Red

### 🔍 1. Diagnóstico de Causa Raíz
Al presionar la tecla `[G]`, la interfaz mostraba en rojo: **`SISTEMA DE ENTREGA NO DISPONIBLE`**. La inspección de los logs oficiales de Roblox Studio (`%LOCALAPPDATA%\Roblox\logs`) arrojó el fallo definitivo:
```
Error: ReplicatedStorage.DeliveryManager:32: Expected '->' when parsing function type, got '='
Warning: [DroneController] Falló require(DeliveryManager) bajo demanda: Requested module experienced an error while loading
```
1. **Error de Sintaxis en Tipado Luau:** En `src/shared/DeliveryManager.luau`, la definición del tipo de callback estaba escrita como `((reward: number, padName: string) => ())?` utilizando `=>` (sintaxis de TypeScript/JS) en lugar de `->` (sintaxis requerida por Luau estricto).
2. **Fallo en Tiempo de Parseo:** Roblox no podía compilar `DeliveryManager.luau` y marcaba el módulo como corrupto en memoria (`Requested module experienced an error while loading`).
3. **Cascada de Fallos:** Cualquier intento de importar `DeliveryManager` fallaba de inmediato, dejando `self.deliveryManager = nil` e impidiendo que el HUD mostrara la tarjeta de misión y que la tecla `[G]` procesara entregas.

### 🛠️ 2. Solución de Ingeniería Implementada
1. **Corrección de Tipado en `DeliveryManager.luau`:**
   * Se corrigió la signatura a `onDeliveryCallback: ((reward: number, padName: string) -> ())?`.
   * El módulo ahora compila y carga limpiamente en Luau estricto sin errores.
2. **Resolución Segura de Eventos de Red (`NetworkEvents.luau` y `DeliveryManager.luau`):**
   * Se modificó `NetworkEvents.Get()` para usar búsqueda inmediata con `FindFirstChild` antes de cualquier yield, reduciendo la latencia de arranque a 0 ms si los objetos ya están replicados.
   * Se incorporó la función auxiliar `resolveRemote()` en `DeliveryManager.luau`: comprueba `NetworkEvents.Get`, luego `CyberNetworkEvents`, y finalmente la raíz de `ReplicatedStorage`.
3. **Mecanismo de Auto-Recuperación y Blindaje de Ciclo de Vida (`DroneController.luau`):**
   * Activación garantizada en `new()`, en `StartFlying()` al presionar `[E]`, y auto-recuperación al pulsar `[G]`.
4. **Reubicación de `missionBox` en el HUD:**
   * Se reposicionó el recuadro de misión a `Y = 160` studs para evitar que la lista de jugadores de Roblox Studio lo oculte.

---

## 12. Desacople del Nombre de la Moneda («PIGICOINS») y Resiliencia en Validación Server-Side

### 🔍 1. Diagnóstico de Causa Raíz
Al modificar el nombre de la recompensa/moneda en `src/server/Main.server.luau` de `"CyberCréditos"` a `"PIGICOINS"`, las entregas dejaron de funcionar por completo.
1. **Búsqueda Rígida en el Servidor (`claimDeliveryEvent`):**
   En el evento del servidor `claimDeliveryEvent.OnServerEvent`, la lógica buscaba estrictamente:
   ```luau
   local credits = leaderstats:FindFirstChild("CyberCréditos") :: IntValue?
   local deliveries = leaderstats:FindFirstChild("Entregas") :: IntValue?

   if credits and deliveries then
       credits.Value += reward
       deliveries.Value += 1
       deliveryConfirmedEvent:FireClient(player, padName, reward)
   end
   ```
2. **Fallo Silencioso de Validación:**
   Al renombrar el valor en `leaderstats` a `"PIGICOINS"`, `FindFirstChild("CyberCréditos")` retornaba `nil`.
   Como resultado, la condición `if credits and deliveries then` se evaluaba como `false`.
3. **Bloqueo del Ciclo de Entrega en Cliente:**
   Dado que el servidor nunca ejecutaba `deliveryConfirmedEvent:FireClient()`, el cliente jamás recibía la confirmación. Sin esa confirmación:
   * La caja física nunca se desacoplaba (`weld:Destroy()` no ocurría).
   * El HUD nunca mostraba el popup de éxito ni actualizaba la misión.
   * El jugador quedaba permanentemente atascado creyendo que la entrega no funcionaba.

### 🛠️ 2. Solución de Ingeniería Implementada
1. **Centralización y Búsqueda Robusta en Servidor (`Main.server.luau`):**
   * Se definió la constante `local CURRENCY_NAME = "PIGICOINS"`.
   * En `claimDeliveryEvent`, la resolución de créditos ahora utiliza un enfoque multi-nivel:
     1. Busca `leaderstats:FindFirstChild(CURRENCY_NAME)`.
     2. Fallback a `"PIGICOINS"` y `"CyberCréditos"`.
     3. Fallback inteligente: itera cualquier `IntValue` dentro de `leaderstats` que no sea `"Entregas"`.
   * Se añadió un log de advertencia claro (`warn`) en lugar de fallar en silencio si alguna estadística no se encuentra.
2. **Sincronización Dinámica en el HUD del Cliente (`DroneHUD.luau`):**
   * Se implementó la función auxiliar `getCurrencyName()` que lee directamente el nombre de la moneda configurada en `leaderstats` del jugador local en tiempo de ejecución.
   * Todas las etiquetas del HUD (`missionRewardLabel`, `successText`) ahora muestran dinámicamente `+250 PIGICOINS` (o el nombre que el usuario asigne) sin requerir reescrituras de código.

---

## 13. Pulido de Primera Persona (FPV) con Giro de Mouse y Corrección Aerodinámica de Inclinación Lateral (Roll)

### 🔍 1. Diagnóstico de Causas Raíz
1. **Primera Persona (FPV) Bloqueada en Línea Recta:**
   * Al presionar `[V]` para pasar a primera persona, `cam.CameraType = Enum.CameraType.Scriptable` desactivaba por completo el sistema orbital de cámara nativo de Roblox.
   * `DroneController.luau` carecía de un listener de movimiento de mouse (`UserInputService.InputChanged`).
   * No se bloqueaba el cursor al centro de la pantalla (`UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter`), de modo que el puntero se movía libremente por la pantalla sin registrar giros.
   * La orientación del dron se calculaba rígidamente en un bucle circular a partir del propio LookVector del dron, impidiendo que el jugador pudiera virar o mirar hacia los lados.
2. **Inclinación Invertida hacia los Lados (Roll Invertido):**
   * En `targetRoll = moveX * self.config.tiltAngle`, al presionar `D` (`moveX = 1`), el valor de rotación en el eje Z era positivo.
   * En el sistema de coordenadas de Roblox, una rotación positiva en Z eleva el lado derecho (`RightVector.Y > 0`) hacia el cielo.
   * Esto exponía el vientre del dron al aire frontal/lateral como una cometa levantada contra el viento, generando una sensación física contraria a la aerodinámica real de un cuadricóptero (donde para desplazarse a la derecha, el dron debe ladearse hacia abajo a la derecha para dirigir el empuje).

### 🛠️ 2. Solución de Ingeniería Implementada
1. **Control Total de Giro y Mirada en Primera Persona (FPV):**
   * **Variables de Rumbo Dinámico:** Se añadieron `self.flightYaw` (rumbo horizontal en radianes) y `self.fpvPitch` (ángulo de visión vertical del piloto).
   * **Giro de Vuelo con Mouse:** Se vinculó `UserInputService.InputChanged` para capturar `MouseMovement`, permitiendo al jugador girar 360° en vuelo con el mouse con sensibilidad calibrada (`0.003` rad/px) y mirar verticalmente arriba/abajo dentro de $\pm 60^\circ$.
   * **Bloqueo Centrado del Cursor (`LockCenter`):** Al activar FPV (`[V]`), el cursor se ancla y oculta en el centro de la pantalla. Al volver a 3ra persona o detener el vuelo, se restaura a `Default`. Al hacer clic en pantalla se reasegura el anclaje si el jugador abrió algún menú.
   * **Soporte de Teclado:** Se añadió soporte para girar el rumbo también con las flechas del teclado (`Izquierda` y `Derecha`).
   * **Transición Fluida 1ra / 3ra Persona:** En 3ra persona, `flightYaw` se sincroniza automáticamente con la rotación orbital de la cámara; al entrar a FPV, el dron continúa exactamente en la misma dirección sin saltos bruscos.
   * **Sensación Cinemática de Cabina:** La cámara en FPV se posicionó en la parte delantera superior del fuselaje (`Vector3.new(0, 0.45, -size.Z * 0.5 - 0.2)`), con una inclinación física sutil sincronizada con el balanceo del fuselaje y un campo visual dinámico (FOV) que se expande de 85° a 100° con el turbo.
2. **Corrección Aerodinámica del Roll Lateral:**
   * Se invirtió la fórmula a:
     ```luau
     local targetRoll = -moveX * self.config.tiltAngle
     ```
   * Al presionar `D` (derecha), el lado derecho del dron desciende y el lado izquierdo se eleva, inclinando la aeronave hacia la derecha para dirigir los vectores de propulsión y cortar el aire aerodinámicamente.
   * Al presionar `A` (izquierda), el lado izquierdo desciende simétricamente.
   * El horizonte artificial holográfico del HUD se sincroniza automáticamente con la inclinación real.

---

## 14. Sistema Logístico de Bodega (3 Paquetes), Ciclo de Reabastecimiento en Base Central y Tolvas Receptoras en Torres

### 🔍 1. Diagnóstico y Necesidad de Diseño
* **Falta de Sentido Logístico:** El sistema original recargaba un paquete mágicamente en el aire 1.5 segundos después de cada entrega, sin límite de paquetes y sin requerir volver a la base.
* **Falta de Recepción en Torres:** Al soltar la caja en una torre, esta simplemente caía sobre el helipuerto y desaparecía tras un temporizador, sin que la torre interactuara con el paquete ni verificara físicamente la recepción.

### 🛠️ 2. Solución de Ingeniería Implementada
1. **Bahía de Carga con 3 Paquetes Físicos Individuales (`DroneCargo.luau`):**
   * El dron equipa 3 paquetes modulares visibles bajo el chasis (`Package 1`, `Package 2`, `Package 3`), cada uno con su propio contenedor metálico, aro de neón, soldadura (`WeldConstraint`) y haz tractor individual (`Beam`).
   * Al entregar en una torre, se desacopla **únicamente 1 paquete**, el cual cae por gravedad real en la plataforma con rótulo holográfico `[ENTREGADO // VERIFICADO]`.
   * Los paquetes restantes permanecen firmemente soldados bajo el dron.
   * La masa y la inercia varían dinámicamente: con 3 paquetes el dron vuela más pesado (`0.88x`), y con 0 paquetes vuela más ágil (`1.06x`).
2. **Ciclo de Reabastecimiento en Base Central (`DeliveryManager.luau`):**
   * El jugador realiza hasta 3 entregas en las torres.
   * Al entregar el último paquete (`0/3` paquetes restantes), el sistema bloquea nuevas entregas y enruta automáticamente el destino hacia la **Base Central (`Pad_Base`)**.
   * Al posarse sobre la Base Central y presionar `[G]` (o tras 0.6s de aterrizaje), se ejecuta `RestockAtBase()`, recargando los 3 paquetes bajo el chasis, otorgando un bono de ruta de **+100 PELAOCOINS**, y asignando una nueva ruta de reparto hacia las torres.
3. **Tolvas Receptoras y Pulso de Escaneo en Torres (`Main.server.luau`):**
   * En cada helipuerto de las torres se instaló una **Tolva de Descarga Receptora (`CargoDropBay`)** de neón con letrero `▼ TOLVA DE DESCARGA ▼`.
   * Al confirmarse una entrega, el servidor genera un pulso de escaneo holográfico expansivo (`ScanReceiptPulse`) que barre la superficie del helipuerto confirmando la ingesta de la carga.
4. **Indicador Visual de Bodega en Tiempo Real en HUD (`DroneHUD.luau`):**
   * La tarjeta de misión incorpora el estado de la bodega:
     * 3 paquetes: `BODEGA: [📦 📦 📦] (3/3)` en Neón Cian.
     * 2 paquetes: `BODEGA: [📦 📦 ⬝] (2/3)` en Neón Cian.
     * 1 paquete:  `BODEGA: [📦 ⬝ ⬝] (1/3) ¡ÚLTIMO!` en Neón Amarillo.
     * 0 paquetes: `BODEGA: [⬝ ⬝ ⬝] (0/3) ¡VE A BASE!` en Neón Rojo parpadeante.
   * Los popups de victoria muestran la carga restante en tiempo real y notifican el reabastecimiento en Base.

---

## 15. Fase 1 Enriquecida: Red de Rutas con Niveles de Amenaza, Despacho Táctico y Multiplicador de Rachas (Delivery Streak)

### 🔍 1. Diagnóstico y Visión de Juego
* **Rutas Homogéneas:** Anteriormente, todas las torres otorgaban la misma recompensa (250) sin importar la distancia, la altitud ni la presencia inminente de hostiles.
* **Falta de Tensión y Progresión en Vuelo:** No existía incentivo para encadenar entregas limpias ni diferenciación visual del peligro entre sectores del mapa.

### 🛠️ 2. Solución de Ingeniería Implementada (Fase 1)
1. **Tipologías y Niveles de Amenaza (`ThreatLevel`):**
   * Se definió el tipo estricto `export type ThreatLevel = "safe" | "hostile" | "black_ops"` en `DeliveryManager.luau`.
   * **Zona Segura (🟢 `safe` - Base Central):** Vuelo de despacho y reabastecimiento logístico (+100 PELAOCOINS).
   * **Sector Hostil (🟡 `hostile` - Torre A):** Vuelo a media distancia sobre zona de chatarreros (+250 PELAOCOINS).
   * **Ruta Crítica / Black Ops (🔴 `black_ops` - Torre B):** Alta altitud y larga distancia, corredor de caza Kuroshio (+400 PELAOCOINS base).
2. **Sistema Server-Authoritative de Rachas ("Delivery Streak"):**
   * Implementado en `Main.server.luau`: el servidor lleva un registro estricto `playerStreaks[player.UserId]`.
   * Cada entrega exitosa a una torre incrementa la racha en `+1`.
   * **Multiplicador de Recompensa:** `1.0 + math.clamp((streak - 1) * 0.10, 0, 0.50)` otorgando hasta un **+50% adicional** en PELAOCOINS por encadenar rutas exitosas.
   * **Preservación en Base:** Reabastecer paquetes en la Base Central preserva la racha acumulada para que el jugador continúe su cadena de envíos.
   * **Penalización por Muerte:** Si el personaje muere o el dron es destruido, la racha se reinicia automáticamente a 0 tanto en el servidor como en el cliente.
3. **Telemetría y Cabina Táctica HUD (`DroneHUD.luau`):**
   * Panel de Misión ampliado con **Threat Badge** estilizado (`[🟢 SEGURO]`, `[🟡 HOSTIL]`, `[🔴 BLACK OPS]`) con bordes neón y color temático.
   * Campo de inteligencia táctica (`INTEL: Sector industrial // Nido Scav-Gnats`).
   * **Indicador de Racha Activa:** `RACHA: x3 🔥 (+20% BONUS)`.
   * **Waypoint 3D Dinámico:** El diamante y la etiqueta holográfica en pantalla cambian automáticamente de color según la amenaza del helipuerto objetivo (Cian para seguro, Amarillo para hostil, Neón Rosa para Black Ops).
   * Popups de victoria actualizados para celebrar la racha alcanzada.
4. **Hologramas 3D en el Mundo (`Main.server.luau`):**
   * Los letreros holográficos sobre los helipuertos (`PadHoloSign`) ahora proyectan en 3D el nivel de amenaza y la recompensa asociada, visibles hasta a 1000 studs.

---

## 16. Fase 2 Enriquecida: Orquestación Espacial de IA, Particionado por Zonas y Director de Amenaza Dinámico (Threat Director)

### 🔍 1. Diagnóstico y Visión de Juego
* **IA Desactivada:** El servicio `EnemyAIService.server.luau` poseía conductas vectoriales completas (10 Hz), pero el spawner estaba comentado y no existía un sistema que activara o replegara enemigos según la ruta de vuelo del jugador.
* **Riesgo de Saturación de Rendimiento:** Un spawn descontrolado generaría caídas de frames en el servidor o persecuciones infinitas molestas que arruinarían la experiencia de entrega.
* **Falta de Feedback de Combate:** Las torretas y naves enemigas no proyectaban visualmente sus ataques, impidiendo al jugador esquivar o reaccionar.

### 🛠️ 2. Solución de Ingeniería Implementada (Fase 2)
1. **Director de Amenaza Dinámico (`Threat Director` a 1 Hz):**
   * El servidor monitorea a 1 Hz la posición del dron repartidor sin sobrecargar la CPU.
   * **Burbuja de Seguridad en Base Central (`< 90 studs`):** La Base es 100% pacífica. Cualquier enemigo activo se repliega automáticamente al regresar a la Base o al bajarse del dron.
   * **Activación y Culling por Proximidad:**
     * **Sector Industrial (Torre A - Hostil 🟡):** Se activa al entrar a $\le 220$ studs. Despliega un enjambre de 3 `Scav-Gnats` que buscan embestir el cargamento con desestabilización física y chispas de impacto. Al alejarse a $\ge 320$ studs, los agentes se repliegan y desvanecen suavemente.
     * **Sector Black Ops (Torre B - Crítico 🔴):** Se activa al entrar a $\le 250$ studs. Despliega una torreta estacionaria `Aegis-44` en una cornisa táctica y un interceptor orbital `Kuroshio-V` a gran altitud. Se repliegan a $\ge 350$ studs.
2. **Sistema de Despeje de Sector (Sector Clearing Cooldown):**
   * Si el jugador neutraliza a todos los enemigos de una zona activa, la zona queda marcada como **DESPEJADA** durante un cooldown táctico (35s en Torre A, 45s en Torre B), otorgando paso seguro como recompensa.
3. **Físicas y Telegrafiado Visual Cinematográfico:**
   * **Torreta Aegis-44:** Anclada firmemente a su montura (`Anchored = true`), rota suavemente su orientación hacia el dron mediante `CFrame:Lerp` y dispara proyectiles cinéticos con un trazador Gauss dorado brillante (`GaussTracer`).
   * **Interceptor Kuroshio-V:** Maniobra en órbita lateral a 70 studs/s inyectando microondas térmicas con un rayo violeta continuo (`MicrowavePulse`).
   * **Scav-Gnats:** Embestidas cinéticas con eyección de chispas naranjas al colisionar.
   * **Identificación Táctica Diegética:** Todos los enemigos portan un rótulo holográfico `[EnemyTag]` visible hasta a 180 studs con el color neón de su facción.
4. **Protección Anti-Despawn del Dron del Jugador (`CombatService.server.luau`):**
   * Se modificó `destroyDrone`: si un dron destruido pertenece a un jugador (`owner ~= nil`), el servidor **no destruye la parte física**, sino que genera una detonación cinemática y reubica de forma segura el dron en la Base Central, restaurando la integridad y el vuelo sin romper instancias en Workspace.

---

## 17. Fase 3: Arsenal Táctico del Jugador, Cañón de Plasma, Contramedida EMP y Recompensas (Bounties)

### Contexto y Requerimientos
La Fase 3 del Plan Maestro dota al dron de reparto de capacidades activas ofensivas y defensivas frente a la amenaza de los drones hostiles (Scav-Gnats, Aegis-44, Kuroshio-V):
1. **Cañón de Plasma Magma-Spike [MouseButton1 / LMB]:** Proyectil térmico acelerado magnéticamente que inflige daño cinético/térmico, DoT y genera calor en el chasis del jugador.
2. **Contramedida de Pulso EMP [Tecla C]:** Onda electromagnética omnidireccional en un radio de 60 studs con 10s de enfriamiento, que paraliza a los drones hostiles durante 3 segundos.
3. **Gestión Térmica Activa y Prevención de Overheat:** Generación de calor por disparo, enfriamiento continuo y bloqueo de cañón si supera el 85% de temperatura.
4. **Sistema de Recompensas de Caza (Bounties):** Acreditación server-authoritative de `PELAOCOINS` en `leaderstats` al destruir enemigos (+35 Scav-Gnat, +80 Aegis, +120 Kuroshio) con feedback diegético en el HUD.

### Implementación y Arquitectura
1. **Servidor (`CombatService.server.luau`):**
   * **Validación de Disparo y Raycast Fallback:** `OnFireWeapon` valida distancia (anti-exploit de rango) y ejecuta un raycast server-side con compensación de puntería para asegurar que el proyectil impacte enemigos en `Workspace.EnemyDrones` incluso con latencia de red.
   * **Trazabilidad de Atacante (`lastAttacker`):** Al aplicar daño, se registra el jugador atacante. Al destruirse un dron hostil (`owner == nil`), el servidor acredita la recompensa en `killer.leaderstats.PELAOCOINS` e invoca `OnBountyAwarded` al cliente.
   * **Contramedida EMP (`OnEMPActivated.OnServerEvent`):** Controla cooldown de 10s por jugador. Instancia una onda esférica de choque neón cyan expansiva (60 studs) y desactiva `LinearVelocity` y `AlignOrientation` de todos los enemigos en el área por 3.0s, aplicando un `Highlight` diegético.
2. **Cliente y Físicas (`DroneController.luau`):**
   * **Mapeo de Controles:** Se liberó la tecla `C` de la función de descenso (reservada a `LeftShift`/`LeftControl`) y se reasignó a `TriggerEMP()`. Se mapeó `MouseButton1` a `FireWeapon()`.
   * **Simulación Local Inmediata (Zero Latency VFX):** Al presionar LMB, se dispara de inmediato `LocalPlasmaBolt` hacia el punto de mira (centro en FPV o cono frontal asistido en 3ra persona) y se notifica al servidor.
   * **Disipación Continua:** En `RenderStepped`, se aplica disipación térmica constante y liberación del estado de sobrecalentamiento al bajar de 50°C.
3. **HUD y Feedback Diegético (`DroneHUD.luau`, `Main.client.luau`):**
   * Se actualizó la barra superior de telemetría: `CAM: 3RA PERSONA // [LMB] PLASMA // [C] EMP // [V] FPV // [X] FRENO`.
   * Se enlazó el evento `OnBountyAwarded` para desplegar notificaciones diegéticas doradas de recompensa en tiempo real (`¡HOSTIL NEUTRALIZADO! +XX PELAOCOINS 💰`).

---

## 18. Fase 4: Telemetría HUD Avanzada, Barras de Núcleo (HP/Heat), Radar Táctico 360° y Viñeta de Daño

### Contexto y Requerimientos
La Fase 4 del Plan Maestro implementa el pulido sensorial y la conciencia situacional espacial del piloto en cabina y tercera persona:
1. **Barras Diegéticas de Integridad HP y Calor Térmico:** Visualización continua de la salud del dron con transición de color (Verde >60% -> Amarillo 30-60% -> Rojo crítico <30%) y barra térmica de magma con avisos de sobrecalentamiento y estado de parálisis EMP.
2. **Minimapa / Radar Táctico 360° Diegético (Rango 250 studs):** Radar circular militar cyberpunk en la esquina superior izquierda con barrido radial (`RadarSweep`), proyección angular curso-arriba (course-up), blips codificados por color para helipuertos (Base cyan, Torre A amarillo, Torre B fucsia) y amenazas hostiles (Torreta Aegis ámbar, Interceptor Kuroshio carmesí, Enjambre Scav-Gnat rojo).
3. **Indicador de Daño Direccional y Viñeta de Impacto:** Flash perimetral rojo en pantalla ante impactos y flecha diegética rotada hacia el vector de origen del atacante.
4. **Pulido Sensorial VFX (`DroneVFX.luau`):** Emisión reactiva de chispas de desgaste (`PlayHitEffect`) y sobretensión de luz de chasis ante descargas EMP (`PlayEMPEffect`).

### Implementación y Arquitectura
1. **Interfaz HUD (`DroneHUD.luau`):**
   * **`CombatStatusBox`:** Panel compacto integrado sobre el velocímetro con gauges de `INTEGRIDAD HP`, `CALOR NÚCLEO` y estado del `PULSO EMP [C]`.
   * **`ThreatRadar`:** Renderizado a 60 FPS con proyección trigonométrica local (`PointToObjectSpace`) orientada según el rumbo `flightYaw` del dron, reutilizando un pool de blips pre-instanciados sin crear basura de memoria (Garbage Collection friendly).
   * **`DamageOverlay` y `DamageIndicatorArrow`:** Reacción inmediata a paquetes de daño recibidos del servidor.
2. **Controlador y Comunicación (`DroneController.luau`, `Main.client.luau`, `CombatService.server.luau`):**
   * El ciclo de render pasa telemetría en tiempo real de HP, calor, cooldown de EMP y vector de orientación del dron al HUD.
   * `CombatService` y `EnemyAIService` empaquetan el vector `attackerPosition` en los eventos de impacto para alimentar la flecha de daño direccional del cliente.
3. **Efectos Visuales (`DroneVFX.luau`):**
   * Implementación de emisores de partículas de chispas instantáneas y destellos de emergencia en el chasis.

---

## 19. Fase 5: Rutas Dinámicas, Pérdida de Carga Física por Daño Crítico y Progresión de Rango

### Contexto y Requerimientos
La Fase 5 concluye el Plan Maestro cerrando el ciclo de juego (game loop) con tensión de riesgo/recompensa, contratos de alta velocidad y progresión de maestría:
1. **Contratos de Entrega Prioritaria / Rush Orders (Temporizador y Multiplicador):**
   * Al despachar una misión hacia un helipuerto receptor (Torre A o Torre B), existe una probabilidad del 65% de activar una entrega urgente (45s estándar, 60s en Black Ops).
   * Completar la entrega antes de que expire el temporizador otorga un **+50% de bonificación en la recompensa final (`rushMultiplier = 1.5`)**, acumulable con el multiplicador de racha.
   * El HUD refleja la cuenta regresiva en tiempo real en la tarjeta de despacho superior derecha con tipografía y color neón dorado de alta visibilidad.
2. **Pérdida de Carga Física por Daño Crítico (Riesgo y Tensión Táctica):**
   * Si el dron sufre un impacto contundente ($\ge 16$ de daño) o su integridad estructural cae a zona crítica ($\le 35\%$ HP), un desacople de emergencia expulsa uno de los paquetes magnéticos transportados.
   * El paquete se desprende físicamente con corte de haz tractor y dispersión cinemática aleatoria (`AssemblyLinearVelocity` y `AssemblyAngularVelocity`), colisiones activas con el entorno y un rótulo holográfico diegético en el mundo: `CARGA DAÑADA // [EXPULSADA]` (desvaneciéndose con `Debris:AddItem` tras 25s).
   * El `DeliveryManager` y el HUD actualizan de inmediato el inventario de bodega. Si la bodega queda en 0/3 por impactos, el sistema aborta la misión y re-enruta obligatoriamente al piloto hacia la Base Central para reabastecerse.
3. **Sistema de Progresión y Rango de Piloto (Server-Authoritative):**
   * Creación del atributo `Rango` (StringValue) en `leaderstats` del jugador:
     * **Cadete Aéreo:** 0 a 5 entregas exitosas.
     * **Piloto de Corredor:** 6 a 15 entregas exitosas.
     * **As del Reparto:** 16+ entregas exitosas.
   * El rango se valida y actualiza en el servidor tras cada entrega completada, y se proyecta diegéticamente en la tarjeta de misión del HUD del piloto (`RANGO: [AS DEL REPARTO]`).

### Implementación y Arquitectura
1. **Físicas y Logística (`DroneCargo.luau`):**
   * Implementación de `DroneCargo.DropOnePackage(dropPosition)`:
     * Remueve el último elemento de la pila de paquetes.
     * Desactiva el haz tractor (`Beam`) y destruye la soldadura magnética (`Weld`).
     * Asigna propiedades físicas libres (`Massless = false`, `CanCollide = true`, `Anchored = false`).
     * Aplica el vector de velocidad del dron sumado a un vector de dispersión tridimensional y momento angular aleatorio.
     * Añade `BillboardGui` diegético con aviso de carga dañada y programa su limpieza.
     * Recalcula masa total y estabilidad del chasis en tiempo real.
2. **Despacho y Contratos Dinámicos (`DeliveryManager.luau`):**
   * Integración de campos `rushOrderActive`, `rushTimeRemaining`, `rushTotalTime` y `rushMultiplier`.
   * En `PickNextTarget`: asignación probabilística de contratos de entrega rápida según nivel de amenaza.
   * En `Update`: decremento delta-time del temporizador y restauración a entrega nominal si expira sin penalización severa.
   * En `CompleteDelivery`: comunicación cliente-servidor indicando si el reclamo se efectuó dentro de la ventana de tiempo.
   * `NotifyCargoLost`: sincronización ante eventos de desprendimiento físico y cambio automático de destino si no queda carga útil.
3. **Validación Server-Side y Economía (`Main.server.luau`):**
   * `getPilotRank(totalDeliveries)`: función determinista que clasifica al jugador.
   * `leaderstats.Rango`: inicializado en `PlayerAdded`.
   * En `claimDeliveryEvent.OnServerEvent`: validación estricta de tiempo de entrega rápida y actualización del rango del jugador en base a `deliveries.Value`, multiplicando la recompensa de `PELAOCOINS` de forma segura.
4. **Telemetría e Interfaz Diegética (`DroneHUD.luau`, `DroneController.luau`):**
   * Reorganización y expansión del contenedor `MissionBox` (de 255x156 a 260x192 px) para alojar ordenadamente `RushTimerLabel` y `RankBadge`.
   * Enlace en el loop de `RenderStepped` de `DroneController` para proyectar el temporizador activo, el estado de bodega, la racha y el rango de piloto.
   * Disparador en `ApplyDamage`: detección de impacto crítico con cooldown de 4s para prevenir desprendimiento instantáneo de todos los paquetes ante ráfagas múltiples.

---

## 20. Auditoría y Corrección de Visibilidad, Físicas y Patrulla de IA Hostil

### Diagnóstico de Causas de No-Visibilidad
Una auditoría exhaustiva reveló las causas por las cuales las unidades enemigas no eran visibles en el mundo de juego:
1. **Caída Gravitatoria al Vacío (Física Crítica):**
   * Las unidades móviles (`scav_gnats` y `kuroshio_v`) se instanciaban con `Anchored = false` pero con un `LinearVelocity.MaxForce` restrictivo ($spec.maxForce \times spec.mass = 900$ y $3,600$ N).
   * La masa real de los bloques metálicos en Roblox oscilaba entre $53$ kg y $716$ kg, lo que generaba un peso gravitatorio de $10,400$ N a $140,500$ N ($P = m \cdot g$).
   * Con una fuerza vertical incapaz de soportar el 10% del peso, las unidades se precipitaban en caída libre vertical a $\sim 180\text{ studs/s}^2$, estrellándose contra el suelo en $< 0.8$ segundos y muriendo en el vacío (`FallenPartsDestroyHeight` a $-500$) o quedando encalladas en el suelo $100$ studs por debajo del vuelo del jugador.
2. **Inactividad en Reposo y Desconexión de Rango:**
   * La zona se activaba a $220$ studs, pero `scav_gnats` tenía `detectionRadius = 90` studs.
   * Sin un objetivo a $< 90$ studs, la IA calculaba `steerForce = Vector3.zero` sin ninguna conducta de patrulla, dejándolas inertes.
3. **Descalibración del Radar en el HUD:**
   * Las coordenadas del radar para Torre A y Torre B estaban desfasadas (`(0, 100, 320)` y `(-280, 160, -180)` vs coordenadas reales `(160, 95, -180)` y `(-200, 50, 140)`), guiando al piloto en dirección contraria a los sectores con enemigos.
4. **Posicionamiento Errático de la Torreta Aegis-44:**
   * Spawneaba a $Y = 72$ (flotando 22 studs en el aire sin cornisa física sobre la azotea de Torre B a $Y = 50$), mirando hacia el sur en un cono ciego de 120° que ignoraba al jugador que se aproximaba desde la Base.
5. **Baja Salencia Visual y Rótulo Corto:**
   * Bloques metálicos oscuros sin silueta ni estela propulsora en un cielo nocturno, con un `BillboardGui` limitado a solo 180 studs de distancia.

### Solución Quirúrgica Aplicada
1. **Sustentación Anti-Gravedad Robusta (`EnemyAIService.server.luau`):**
   * Asignación de `lv.MaxForce = 1e6` (1,000,000 N) y `ao.MaxTorque = 1e6` idéntico a `TestDrone`, otorgando autoridad total sobre la gravedad y aceleración 3D fluida.
   * Asignación de `CustomPhysicalProperties = PhysicalProperties.new(0.01, 0, 0, 0, 0)` y `pcall(function() part:SetNetworkOwner(nil) end)` garantizando simulación en el servidor sin desincronización de red.
2. **Patrulla Activa en Reposo (*Idle Swarm & High Patrol*):**
   * Si el jugador aún no está al alcance directo, los Scav-Gnats patrullan activamente en enjambre orbitando Torre A con oscilación vertical sinusoidal visible desde gran distancia.
   * El interceptor Kuroshio-V patrulla en órbita alta a $Y = 80$ studs alrededor de Torre B.
   * La torreta Aegis-44 ejecuta un barrido rotativo de vigilancia de 360° con un haz láser diegético rojo (`LaserSight`).
3. **Ampliación de Detección Omnidireccional (`EnemyTypes.luau`):**
   * Scav-Gnats: `detectionRadius = 240` studs.
   * Aegis-44: `detectionRadius = 240` studs, `detectionAngle = 360` grados.
   * Kuroshio-V: `detectionRadius = 260` studs.
4. **Visibilidad Táctica Neón:**
   * Integración de componente `Highlight` neón (`OutlineColor = spec.accentColor`, `FillTransparency = 0.65`) en todos los enemigos.
   * Emisores de partículas de propulsión (`ParticleEmitter`) en toberas de escape.
   * `BillboardGui` diegético visible hasta **600 studs** de distancia con rótulos nítidos `[▼ SCAV-GNAT MK0 ▼]`.
5. **Calibración del Radar y Torre B:**
   * Helipuertos en `DroneHUD.luau` alineados a las coordenadas reales del mundo.
   * Filtrado de accesorios en el radar (`AccentBand`, `LaserSight`) para evitar blips fantasma.
   * Montaje de Aegis-44 asentada firmemente sobre la cornisa de Torre B a $Y = 52.5$ studs.

---

## 21. Auditoría Integral Multi-Fase: Causa Raíz de Desaparición de Enemigos y Solución Arquitectónica Definitiva

### Diagnóstico Forense Multi-Fase: ¿Por qué no se veían los enemigos?

Tras una revisión integral de los scripts del servidor y cliente a lo largo de las 5 fases, se identificaron los siguientes 6 bloqueos arquitectónicos simultáneos:

1. **Despawn Destructivo en el Bucle del Threat Director (`EnemyAIService.server.luau`):**
   * El bucle a 1 Hz contenía la condición:
     ```luau
     local isFlying = (not dronePart.Anchored)
     local distToBase = (dronePos - Vector3.new(0, 4, 0)).Magnitude
     if not isFlying or distToBase < 65 then
         for _, zone in pairs(threatZones) do
             if zone.isActive then deactivateZone(zone) end
         end
         continue
     end
     ```
   * Al iniciar el servidor o al reaparecer el jugador, `TestDrone.Anchored == true` (esperando que el piloto presione [E]), por lo que `isFlying == false`.
   * El bucle ejecutaba `continue` cada segundo, purgando y destruyendo con `part:Destroy()` cualquier enemigo existente y **bloqueando el código de activación**. Por ende, `Workspace.EnemyDrones` permanecía 100% vacío.
   * Incluso si el piloto lograba volar hacia Torre A y activar la zona, al regresar a Base para entregar el paquete (`distToBase < 65`) o al aterrizar (`isFlying == false`), el servidor **exterminaba instantáneamente todos los enemigos del mapa**.

2. **Despawn Forzado al Salir de FPV (`Main.server.luau`):**
   * En `flightStateEvent.OnServerEvent`, al recibir `"StopFlying"` (tecla F o desacople), el servidor ejecutaba:
     `_G.EnemyAIService.DeactivateAllZones()`
   * Si el jugador se bajaba del dron para inspeccionar el mapa o reabastecerse, todos los enemigos del mundo eran eliminados de inmediato.

3. **Ausencia de Invocación Inicial de Sectores:**
   * Las zonas tácticas (`Zone_TorreA` y `Zone_TorreB`) comenzaban con `isActive = false` y ninguna función de arranque las inicializaba al nacer el servidor.

4. **Vulnerabilidad de Timeout en `WaitForChild(..., 8)`:**
   * Tanto `EnemyAIService` como `CombatService` realizaban `require(ReplicatedStorage:WaitForChild(..., 8))`.
   * En cargas de Roblox Studio o sincronizaciones lentas de Rojo, si la réplica tardaba más de 8 segundos, arrojaba un fallo fatal `attempt to call require with nil`, terminando el script antes de registrar `_G.EnemyAIService` o `_G.CombatService`.

5. **Restricción Exclusiva a `Workspace.TestDrone`:**
   * `findNearestPlayerDrone` únicamente consultaba `Workspace:FindFirstChild("TestDrone")`. Si el desarrollador o jugador exploraba a pie o el dron estaba anclado, los enemigos no reconocían ningún objetivo.

6. **Alcance Limitado del Radar en el HUD (`DroneHUD.luau`):**
   * El radar poseía `RADAR_MAX_DIST = 250` studs. Dado que Torre A se sitúa a 257.4 studs de la Base Central (`(160, 95, -180)`), los enemigos de Torre A no aparecían en el radar mientras el jugador permanecía en la plataforma de inicio.

---

### Solución Arquitectónica Implementada

1. **Persistencia Espacial de Sectores Hostiles:**
   * Se eliminó el despawn forzado por distancia o por estar en reposo. Los sectores hostiles (Torre A y Torre B) existen persistentemente en el mundo desde el segundo cero.
   * Al iniciar el servidor, una rutina asíncrona espera la inicialización de `CombatService` y ejecuta `activateZone()` para Torre A (3 Scav-Gnats en enjambre) y Torre B (Torreta Aegis-44 e Interceptor Kuroshio-V).

2. **Burbuja de Seguridad de Base Central (Desenganche Táctico vs Despawn):**
   * En lugar de destruir a los enemigos cuando el jugador está en la Base, la Base posee un perímetro defensivo inmune ($\text{radio} = 65$ studs).
   * En `findNearestPlayerTarget`: si el objetivo (dron o piloto a pie) se encuentra a $< 65$ studs de la Base `(0, 4, 0)`, los enemigos lo ignoran por completo (`targetPart = nil`).
   * En el bucle de IA a 10 Hz: si una nave hostil se acerca a $< 70$ studs de la Base, se aplica una fuerza vectorial de repulsión hacia su `homeCenter`, impidiendo invasiones a la Base pero manteniéndola visible patrullando su sector.

3. **Ciclo de Autorreaparición Táctica Post-Combate:**
   * El bucle del Director de Amenazas a 1 Hz monitorea la salud de cada sector:
     * Si el jugador derriba a todos los enemigos de un sector, la zona pasa a estado despejado y se inicia un temporizador de enfriamiento táctico (35s en Torre A, 45s en Torre B).
     * Una vez transcurrido el cooldown, el servidor genera automáticamente una nueva oleada de refuerzos con `activateZone()`.

4. **Montaje Físico Libre de Tirones Gravitatorios:**
   * `buildEnemyPart` mantiene `Anchored = true` durante el ensamblaje de attachments, `LinearVelocity` ($10^6$ N) y `AlignOrientation` ($10^6$ N$\cdot$m), desanclando la nave únicamente al finalizar el montaje, eliminando cualquier dip gravitatorio inicial.

5. **Carga Asíncrona Robusta de Módulos:**
   * Se reemplazaron los `WaitForChild(..., 8)` por selectores elásticos `FindFirstChild(...) or WaitForChild(..., 30)`, protegiendo la ejecución ante demoras de inicialización de DataModel.

6. **Radar Táctico Ampliado a 320 Studs y Salencia Neón:**
   * Cobertura de radar en `DroneHUD.luau` ampliada a 320 studs, permitiendo visualizar los blips de Torre A (257 studs) y Torre B (248 studs) desde la base de despegue.
   * Scav-Gnats actualizados con acento neón ámbar/naranja brillante (`#FF5F00`) y escala de 0.65x, logrando una silueta diegética inconfundible en el cielo metropolitano.

---

## 22. Causa Raíz Oculta: Error Fatal de Sintaxis de Luau VM (`Table.Field: Type =`)

### Diagnóstico Forense Definitivo vía Logs de Roblox Studio
Una inspección en profundidad de los archivos de registro locales generados por Roblox Studio (`%LOCALAPPDATA%\Roblox\logs\*.log`) reveló el error fatal que impedía el arranque de los servicios del servidor:

```
[EnemyAIService] Iniciando IA de facciones hostiles...
Error: ReplicatedStorage.EnemyTypes:158: Expected identifier when parsing method name, got '{'
Error: Requested module experienced an error while loading
Info: Script 'ServerScriptService.EnemyAIService', Line 14
Info: Stack End
```

### Explicación del Error de Sintaxis
En el lenguaje Luau (Roblox), la asignación de campos en una tabla **no admite anotaciones de tipo de variable local en la clave de la tabla**:
* Código erróneo:
  ```luau
  EnemyTypes.All: { EnemySpec } = { ... }
  EnemyTypes.ById: { [string]: EnemySpec } = {}
  ```
* En la gramática de Luau, la construcción `Tabla.Campo:` se interpreta inmediatamente como la declaración o llamada a un método (`function Tabla:Metodo()`).
* Al encontrar el token `{` en lugar de un nombre de método válido, el compilador Luau de Roblox detiene la ejecución con:
  `Expected identifier when parsing method name, got '{'`
* Como consecuencia, `require(EnemyTypesModule)` lanzaba una excepción irrecuperable en la línea 14 de `EnemyAIService.server.luau`, **abortando por completo el script antes de que pudiera crear `Workspace.EnemyDrones`, registrar la API global o spawnear una sola unidad**.
* El mismo error de sintaxis existía en `DroneWeapons.luau` (línea 205) y `DroneCatalog.luau` (línea 245), bloqueando también el arranque de `CombatService.server.luau`.

### Corrección Aplicada
1. **Separación de Anotación y Asignación de Tabla:**
   Se declararon variables locales tipadas (`local allEnemies: { EnemySpec } = { ... }`, `local byId: { [string]: EnemySpec } = {}`) y posteriormente se asignaron a los campos de la tabla exportada (`EnemyTypes.All = allEnemies`, `EnemyTypes.ById = byId`).
   Se corrigió idénticamente en:
   * [EnemyTypes.luau](file:///x:/Datos%20Proyectos/robx/src/shared/EnemyTypes.luau) (líneas 158-167)
   * [DroneWeapons.luau](file:///x:/Datos%20Proyectos/robx/src/shared/DroneWeapons.luau) (líneas 205-223)
   * [DroneCatalog.luau](file:///x:/Datos%20Proyectos/robx/src/shared/DroneCatalog.luau) (líneas 245-249)
2. **Registro Retrospectivo en Combate (`CombatService.server.luau`):**
   Se añadió un barrido diferido (`task.defer`) que registra automáticamente en `activeDrones` cualquier enemigo que ya se encuentre en `Workspace.EnemyDrones`, garantizando inmunidad a condiciones de carrera entre scripts.
3. **Explorador Adelantado en Corredor Aéreo:**
   Se incorporó un cuarto Scav-Gnat en `Zone_TorreA` ubicado en el vector intermedio `(95, 65, -115)` (a 163 studs de la Base), permitiendo que el jugador observe una nave patrullando en el horizonte aéreo inmediatamente al despegar.

---

## 23. Pulido Dinámico de Combate y Ataques de Drones Hostiles

### 🔍 Diagnóstico de Ataque Inicial
1. **Scav-Gnats (Enjambre Chatarrero - Torre A):**
   * El umbral de contacto físico estaba limitado a `dist <= 6` studs. Con una frecuencia de IA de 10 Hz ($\Delta t = 0.1\text{s}$) y naves a 45–50 studs/s, los drones cruzaban de 4 a 9 studs por fotograma de cálculo, provocando que colisiones a alta velocidad no registraran embestida.
   * Tras chocar, el gnat permanecía pegado al chasis del jugador sin retroceso, sin feedback de audio y con aceleración plana.
2. **Torreta Aegis-44 (Cornisa Torre B):**
   * Disparo sin telegrafiado visual: el jugador recibía daño repentino sin advertencia anticipada.
   * Falta de efectos de boca de cañón (*muzzle flash*), retroceso sonoro e impacto cinético.
3. **Interceptor Kuroshio-V (Alta Altitud Torre B):**
   * El pulso de microondas carecía de resonancia acústica y definición volumétrica (haz plano único), reduciendo la inmersión del combate espacial.

### 🛠️ Soluciones y Mejoras de Combate Aplicadas
1. **Scav-Gnats — Picado Aéreo y Colisión Contundente:**
   * **Umbral de Impacto:** Ampliado a **11 studs** para garantizar captura a 10 Hz sin falsos negativos.
   * **Picado Aéreo en Aceleración (Dive-Bomb):** Al aproximarse a $\le 70$ studs del objetivo, la velocidad máxima se eleva a **68 studs/s**, orientando el morro y alerones en 3D directo al vector del jugador e intensificando las partículas del propulsor (`Rate = 80`, `Speed = 16-28`).
   * **Retroceso Físico (Recoil Bounce):** Tras el impacto, el gnat recibe una fuerza de rebote inversa:
     $$\mathbf{v}_{\text{gnat}} = -\hat{\mathbf{d}} \times 32 + (0, 10, 0)$$
     evitando que atraviese el chasis del jugador.
   * **SFX y FX:** Sonido de impacto metálico pesado (`rbxassetid://9114221580`), destello de choque de 3.5 studs y 180 partículas de chispa a 25–35 studs/s.
2. **Torreta Aegis-44 — Telémetro Carmesí y Cañón Gauss Pesado:**
   * **Pre-fijado Láser Diegético:** Al detectar y rastrear al jugador, la mira láser cambia de ámbar tenue (`#FFB400`) a **rojo carmesí brillante (`#FF1E1E`)**, con grosor aumentado a 0.35 studs, alertando al piloto para evadir o buscar cobertura.
   * **Detonación Gauss y SFX:** Audio de cañón de riel pesado (`rbxassetid://9114223400`), destello de boca de cañón esférico (*Muzzle Flare*) de 2.8 studs y trazador cinético dual con núcleo incandescente blanco (`#FFFFDC`).
   * **Fuerza de Impacto:** Aplica 22 HP de daño y un impulso cinético horizontal de $+32\text{ N}$ que desestabiliza temporalmente el vuelo del jugador.
3. **Kuroshio-V — Haz Dual de Microondas y Descarga Electrostática:**
   * **Sonido de Descarga:** Audio de microondas de alta frecuencia (`rbxassetid://9114223170`).
   * **Haz Dual Volumétrico:** Vaina de contención de plasma violeta (`#B400FF`) de 0.6 studs con núcleo eléctrico cian neón (`#00F0FF`) de 0.25 studs.
   * **Daño Híbrido:** Inyecta $+16$ de calor al núcleo del dron (acelerando el umbral de parada EMP) y $-8\text{ HP}$ directos con chispas de arco voltaico en el casco.

---

## 24. Reabastecimiento Instantáneo de Bodega en Base Central (Triple Capa)

### 🔍 Diagnóstico de la Falla de Reabastecimiento
Al quedarse sin paquetes en bodega (por entregas sucesivas o por pérdida física por daño crítico), los jugadores no podían recargar nuevos paquetes en la Base Central debido a tres factores concurrentes:
1. **Split-Brain de RemoteEvents (`NetworkEvents.luau`):**
   `NetworkEvents.Init()` creaba un `RemoteEvent` duplicado en la raíz de `ReplicatedStorage` mientras que el servidor escuchaba exclusivamente en `CyberNetworkEvents`. El cliente disparaba `DeliveryCompleted` en una instancia desconectada, por lo que el servidor nunca respondía con `DeliveryConfirmed`.
2. **Bloqueo de Estado `isLanded`:**
   En `DeliveryManager.luau`, si el dron ya se encontraba sobre la plataforma de la Base (`isLanded == true`) cuando se perdían los paquetes, el temporizador de aterrizaje no volvía a dispararse, impidiendo que el cliente intentara un nuevo reclamo.
3. **Dependencia Exclusiva de Confirmación de Red:**
   `DroneCargo:RestockAtBase()` únicamente se ejecutaba tras recibir el paquete de confirmación del servidor. Si había latencia, descarte de paquete o rechazo por temporizador anti-spam (2s), los 3 paquetes nunca se cargaban en el dron.

### 🛠️ Solución de Arquitectura: Reabastecimiento de Triple Capa
Se rediseñó el flujo para proveer tres mecanismos independientes y redundantes de abastecimiento:
1. **Capa 1 — Touchdown Automático de Reactividad Inmediata (`DeliveryManager.luau`):**
   * Al descender sobre la Base Central (`Pad_Base`), si `packagesRemaining < 3`, la bodega se recarga a 3/3 localmente en el instante de contacto ($0.60\text{s}$), actualizando el modelo 3D, masa de carga y HUD, mientras en paralelo se notifica al servidor para acreditar la recompensa de ruta.
   * En `NotifyCargoLost()`, se resetea automáticamente `self.isLanded = false` y `self.touchdownTimer = 0`, permitiendo un re-enganche inmediato.
2. **Capa 2 — Reabastecimiento Manual con Tecla [G] (`TryManualDeliver`):**
   * Si el jugador se sitúa en un radio holgado de hasta 42 studs de la Base Central `(0, 4, 0)` y presiona `[G]`, el sistema reabastece instantáneamente los 3 paquetes con sonido de hangar, actualiza el destino logístico y muestra en HUD: `¡Bodega reabastecida al 100%! 3 paquetes disponibles`.
3. **Capa 3 — Salvaguarda Automática al Despegar (`DroneController.StartFlying`):**
   * Al activar el enlace de vuelo (`[E]`) o retomar el control dentro de los 45 studs de la Base Central con menos de 3 paquetes en inventario, `StartFlying()` invoca automáticamente `RestockAtBase()`, garantizando que **ningún piloto pueda despegar de su base de operaciones con la bodega vacía**.

---

## 25. Resincronización y Recuperación Robusta tras Destrucción de Dron

### 🔍 Diagnóstico de la Desincronización y Bloqueo (Bug tras 2 muertes)
Al ser destruido el dron por fuego enemigo (o tras 2 muertes consecutivas), el sistema experimentaba un bloqueo crítico que impedía volver a pilotar o dejaba la interfaz congelada:
1. **Canal Desconectado en Cliente:**
   `CombatService.server.luau` emitía el evento `DroneFlightState("StopFlying")` y `DroneDestroyed`, pero `Main.client.luau` no tenía un listener asignado para `flightEvent.OnClientEvent`. Como consecuencia, la variable booleana `isPiloting` en el cliente permanecía en `true`.
2. **Inversión Lógica al Presionar [E]:**
   Cuando el jugador reaparecía en la base y se acercaba a la cabina para presionar `[E]`, `Main.client.luau` evaluaba `if isPiloting then exitDrone() else enterDrone()`. Al estar `isPiloting == true`, el script ejecutaba `exitDrone()`, cancelando la interacción sin jamás entrar en el dron.
3. **Estado de Salud y Cámara en Cero:**
   En el controlador local (`DroneController.luau`), `self.currentHealth` se quedaba en $0$ con la viñeta roja de daño crítico al 100%, el `CombatService` no restauraba la propiedad de red (`SetNetworkOwnershipAuto`) tras anclar el dron en `(0, 6.2, 0)`, y el `CameraType` podía quedar en `Scriptable` huérfano.

### 🛠️ Solución de Arquitectura y Recuperación Atómica
Se implementó un protocolo de reseteo integral y bidireccional:
1. **Server-Side (`CombatService.server.luau` - `destroyDrone`):**
   * Detención física inmediata: `part.AssemblyLinearVelocity = Vector3.zero`, `part.AssemblyAngularVelocity = Vector3.zero`, `part.Anchored = true`.
   * Reposicionamiento seguro sobre el Helipad Central: `part.CFrame = CFrame.new(0, 6.2, 0)`.
   * Restauración completa de variables de combate: `state.health = state.maxHealth`, `state.heat = 0`, `state.isEMPed = false`.
   * Liberación de propiedad física: `part:SetNetworkOwnershipAuto()`.
   * Teletransporte seguro del piloto a la consola del hangar: `character:PivotTo(CFrame.new(0, 6.5, 14) * CFrame.Angles(0, math.rad(180), 0))`.
   * Disparo garantizado de `DroneDestroyed` y `DroneFlightState("StopFlying")`.
2. **Client-Side (`Main.client.luau` & `DroneController.luau`):**
   * Se enlazó el listener de `flightEvent.OnClientEvent` y `destroyedEv.OnClientEvent`.
   * Al recibir la señal de destrucción:
     - Se invoca `exitDrone()`, sincronizando `isPiloting = false`.
     - El botón de interacción en pantalla restaura su texto a `[E] CONECTAR GAFAS FPV` en color cian neón `#00F0FF`.
     - Se ejecuta `myDrone:ResetOnDestroyed()`, el cual restaura la salud local al máximo (`self.currentHealth = self.maxHealth`), oculta la viñeta de daño, limpia bloqueos de misiles y restablece la cámara a `Enum.CameraType.Custom`.
   * Se configuró el callback `myDrone:SetOnDestroyedCallback(function() if isPiloting then exitDrone() end end)` para que cualquier destrucción detectada localmente también apague de inmediato el bucle de vuelo.

---

## 26. Mira Holográfica Universal y Fijación Cónica de Objetivos en 3ra Persona y FPV

### 🔍 Diagnóstico de Puntería en Tercera Persona
1. **Disparidad de Perspectiva (Parallax Error):**
   En tercera persona, la cámara orbita detrás y por encima del dron. Al disparar el cañón de plasma, los proyectiles salían en la dirección del morro de la nave (`part.CFrame.LookVector`), el cual no coincidía con el centro de visión del jugador en pantalla, haciendo casi imposible acertar a naves enemigas ágiles.
2. **Falta de Retícula Diegética y Telemetría:**
   No había ningún punto o cruceta central en pantalla que indicara la trayectoria real de impacto ni si un dron enemigo estaba dentro del arco efectivo de tiro.

### 🛠️ Solución: Retícula Dinámica con Proyección Raycast y Fijación Cónica (Target Lock)
1. **Retícula Holográfica en HUD (`DroneHUD.luau`):**
   * Retícula central diegética con 4 cuadrantes (`CrosshairContainer` de $32\times32$ px) y un punto central de precisión (*Pip*) de $4\times4$ px en cian neón `#00F0FF`.
   * **Tag de Fijación de Objetivo (`TargetLockTag`):** Etiqueta animada debajo de la cruceta que muestra el estado de rastreo en tiempo real:
     `[ 🎯 FIJADO: <NOMBRE_ENEMIGO> | <DISTANCIA>m ]` en rojo neón `#FF3344`.
2. **Escaneo Cónico en RenderStepped (`DroneController.luau`):**
   * Se proyecta un rayo desde el centro de la pantalla mediante `cam:ViewportPointToRay(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)`.
   * Se itera sobre todos los drones hostiles en `Workspace.EnemyDrones`:
     * Se evalúa el ángulo cónico entre el vector de mira y el vector hacia la nave enemiga:
       $$\cos(\theta) = \hat{\mathbf{d}}_{\text{mira}} \cdot \hat{\mathbf{d}}_{\text{enemigo}}$$
     * Si $\theta \le 16^\circ$ y la distancia es $\le 320\text{ studs}$ con línea de visión sin oclusión (`Raycast`), el sistema selecciona el objetivo más cercano al centro de la mira y lo fija (`self.lockedTarget`).
3. **Convergencia Balística Universal (`FireWeapon`):**
   * Tanto en FPV como en 3ra persona, los pernos de plasma calculan su vector de propagación directamente hacia el punto de impacto del rayo de la cámara o hacia el centro de masa del objetivo fijado:
     $$\mathbf{v}_{\text{plasma}} = \frac{\mathbf{P}_{\text{impacto}} - \mathbf{P}_{\text{boquilla}}}{\|\mathbf{P}_{\text{impacto}} - \mathbf{P}_{\text{boquilla}}\|} \times 240\text{ studs/s}$$
   * Esto elimina por completo el error de paralaje, permitiendo disparar exactamente hacia donde apunta el cursor en pantalla.

---

## 27. Sistema de Misiles Guiados Térmicos [R], Rack de 3 Municiones y Recarga Dual

### 🔍 Especificación del Sistema de Misiles Tácticos
Para enriquecer el combate aéreo y la economía de juego, se implementó un sistema de armamento pesado con las siguientes reglas de juego:
* **Capacidad Limitada:** Rack de **3 misiles** por dron (`missilesRemaining = 3`, `maxMissiles = 3`).
* **Disparo Guiado Condicional:** Tecla `[R]` (configurable por el usuario). Requiere tener un dron enemigo previamente fijado en la retícula (`Target Lock`).
* **Trayectoria Bézier 3D:** El misil sale eyectado hacia arriba/lateralmente y luego traza una curva suave persiguiendo activamente al objetivo hasta detonar, causando daño masivo en área.
* **Economía de Recarga Dual:**
  1. **Vía Logística (Gratuita):** Completar **3 entregas** de paquetes en torres recarga automáticamente el rack de misiles al 100% (3/3).
  2. **Vía Financiera (En Base):** Pagar **150 PELAOCOINS** presionando `[M]` en el hangar de la Base Central para reabastecimiento instantáneo.

### 🛠️ Implementación Técnica de Componentes

#### 1. Trayectoria Balística y Física de Misiles (`DroneController.luau`)
Al presionar `[R]`, si `missilesRemaining > 0` y `self.lockedTarget` es válido:
1. Se descuenta 1 misil y se reproduce sonido de eyección balística (`rbxassetid://9114223170`).
2. Se genera un proyectil local con tubo aerodinámico neón (`Neon Dark Stone Grey`), ojiva cónica ámbar y cola con partículas de humo denso y fuego.
3. Mediante `RunService.Heartbeat`, se interpola una curva Bézier cúbica tridimensional en 0.75 segundos:
   * Punto de inicio $\mathbf{P}_0$: Posición actual del dron.
   * Punto de control $\mathbf{P}_1$: Vector de elevación y dispersión lateral:
     $$\mathbf{P}_1 = \mathbf{P}_0 + \text{UpVector} \times 20 + \text{RightVector} \times (\pm 8)$$
   * Punto objetivo $\mathbf{P}_2$: Posición en tiempo real del objetivo fijado.
4. Al alcanzar al objetivo, se produce una explosión sónica con 200 partículas, destello luminoso de 6 studs y se envía el evento de daño de alto calibre (65 HP) a `CombatService.server.luau`.

#### 2. Visualización en HUD (`DroneHUD.luau`)
El panel de telemetría de combate exhibe el rack de misiles en tiempo real:
* Formato: `MISILES [R]: [ ■ ■ ■ ] (3/3)` en cian neón.
* Conforme se agotan: `[ ■ ■ □ ] (2/3)`, `[ ■ □ □ ] (1/3)` y en color carmesí `[ □ □ □ ] (0/3) SIN MUNICIÓN`.

#### 3. Ciclo de Recarga Dual (`DeliveryManager.luau` & `Main.server.luau`)
* **Contador de Entregas:** `DeliveryManager.luau` mantiene la propiedad interna `deliveriesCompletedSinceRestock`. Cada entrega exitosa a helipuertos de torres incrementa el contador. Al llegar a 3 entregas, `CheckAndConsumeMissileRestock()` devuelve `true`, resetea el contador a 0 y activa `myDrone:ReloadMissiles(3, "3 entregas completadas")`.
* **Compra en Base [M]:**
  * Presionar `[M]` a bordo del dron o en la base dispara el RemoteEvent canónico `BuyMissiles`.
  * `Main.server.luau` valida la distancia a la Base Central ($\le 55\text{ studs}$) y descuenta **150 PELAOCOINS** de `leaderstats`.
  * El servidor replica `BuyMissilesConfirmed`, recargando el rack a 3/3 con sonido de sirena de hangar y confirmación en HUD.

---

## 28. Corrección Integral de Enlace de Pilotaje con Tecla [E]

### 🔍 Diagnóstico de la Falla de Conexión
Al intentar pilotar el dron con la tecla `[E]`, se presentaban tres anomalías concurrentes que impedían el despegue o dejaban la entrada congelada:
1. **Split-Brain de RemoteEvents (`DroneFlightState`):**
   `CombatService.server.luau` creaba una instancia huérfana de `DroneFlightState` directamente en `ReplicatedStorage` mediante una función local `ensureRemote`, mientras que `Main.server.luau` escuchaba exclusivamente el evento canónico dentro de la carpeta `CyberNetworkEvents`. Cuando el cliente disparaba `"StartFlying"`, el servidor principal nunca lo recibía. Como resultado, `TestDrone` permanecía permanentemente `Anchored = true`, impidiendo todo movimiento físico.
2. **Desincronización de Banderas (`isPiloting` vs `isFlying`):**
   Si el jugador moría o se reseteaba su personaje, `DroneController` detenía el vuelo (`self.isFlying = false`), pero la variable local `isPiloting` en `Main.client.luau` permanecía en `true`. Al presionar `[E]`, el script evaluaba `if not isPiloting then enterDrone() else exitDrone()`, llamando a `exitDrone()` en vez de permitirle abordar el dron.
3. **Ausencia de Interacción Diegética 3D:**
   No existía un elemento visual en el mundo que indicara al piloto la proximidad válida para abordar el dron además del botón en pantalla.

### 🛠️ Solución Aplicada
1. **Unificación Canónica de Red (`NetworkEvents.luau` & `CombatService.server.luau`):**
   * Se retiró el `ensureRemote` local y se forzó a todos los servicios del servidor y cliente a consumir exclusivamente `NetworkEvents.Get(...)`.
   * En `NetworkEvents.Init()`, cualquier RemoteEvent existente en la raíz de `ReplicatedStorage` es automáticamente consolidado y reparentado dentro de `CyberNetworkEvents`, garantizando una única referencia en memoria.
2. **Guardia Atómica `isCurrentlyPiloting` y Sincronizador Bidireccional (`Main.client.luau`):**
   * Se implementó la guardia reactiva:
     ```luau
     local function isCurrentlyPiloting(): boolean
         return isPiloting or (myDrone and (myDrone :: any).isFlying == true)
     end
     ```
   * Se enlazó el callback `myDrone:SetOnStateChangedCallback(function(flying) ... end)`, sincronizando atómicamente el estado del botón en pantalla y las banderas de pilotaje.
   * Al morir el humanoide (`hum.Died`) o reaparecer el personaje (`CharacterAdded`), se fuerza automáticamente el reseteo a modo caminante y la restauración del botón a `[E] CONECTAR GAFAS FPV`.
3. **ProximityPrompt 3D Diegético (`Main.server.luau`):**
   * Se instaló un `ProximityPrompt` sobre `TestDrone` con texto `[E] Pilotar Dron - Cyber Drone FPV` (radio de 28 studs).
   * Se apaga dinámicamente al despegar y se reactiva al aterrizar o ser destruido.

---

## 29. Oclusión Balística y Físicas de Impacto contra Estructuras y Torres

### 🔍 Diagnóstico de Traspaso de Proyectiles y Láseres
1. **Error Fatal en Verificación de Línea de Visión de la IA Hostil (`EnemyAIService.server.luau`):**
   La condición de oclusión evaluaba:
   `local hasLOS = not result or result.Instance == agent.targetPart or result.Instance:IsDescendantOf(agent.targetPart.Parent)`
   Dado que `agent.targetPart` (`TestDrone`) es hijo directo de `Workspace`, `agent.targetPart.Parent` es `Workspace`. Como todas las torres, pilares y edificios son descendientes de `Workspace`, la expresión resultaba en **`true` para cualquier objeto impactado**, haciendo que las torretas Aegis-44 y los cazas Kuroshio dispararan a través de rascacielos enteros.
2. **Falsa Transparencia en Materiales Neon/Glass (`hasLineOfSight` en `CombatService.server.luau`):**
   Las torres y helipuertos poseen bandas de ventanas (`FloorBand`), esquineros (`NeonCorner`) y anillos perimetrales en material `Neon`. El algoritmo de validación omitía colisiones contra estos materiales tratándolos como invisibles, permitiendo que el cañón de plasma del jugador atravesara los edificios.
3. **Trayectorias Cónicas y Proyectiles sin Colisión Físico-Temporal:**
   * El cañón de plasma (`SpawnLocalPlasmaBolt`) proyectaba un tween cinemático directo desde la boquilla al objetivo sin verificar obstáculos intermedios.
   * Los misiles guiados (`SpawnLocalMissile`) seguían su curva Bézier 3D atravesando estructuras sólidas.
   * La mira láser (`LaserSight`) de la torreta Aegis-44 era un bloque rígido de 60 studs que penetraba paredes.

### 🛠️ Solución Aplicada
1. **Raycast Físico Multi-Etapa con Oclusión Estricta (`CombatService.server.luau`):**
   * Nuevo trazador autoritativo que distingue entre efectos cosméticos inmateriales (`HoloSkyBeam`, `LaserSight`, proyectiles en vuelo) y estructuras arquitectónicas sólidas (`SupportPillar`, `BasePad`, paredes, helipuertos).
   * Si el rayo choca contra una torre, `hasLOS` se vuelve `false`, `targetPart` se anula a `nil` (0 daño a la nave enemiga) y el punto terminal del disparo se recorta exactamente en la superficie del impacto (`hitPos`).
2. **Interrupción y Chispas de Impacto en Superficie (`DroneController.luau`):**
   * **Cañón de Plasma:** En `FireWeapon`, se efectúa un raycast de trayectoria previa. Si una torre interrumpe el arco de tiro, el perno de plasma local termina en la pared y genera un destello luminoso de impacto de 1.8 studs en vez de penetrar la estructura.
   * **Misiles Guiados [R]:** En `SpawnLocalMissile`, cada fotograma de la curva Bézier se realiza un raycast diferencial entre la posición previa y la actual (`seg = pos - prevPos`). Al hacer contacto con cualquier obstáculo del mapa, el misil **detona inmediatamente en la superficie del rascacielos** con 9 studs de explosión y se destruye sin traspasar.
   * **Fijación de Objetivos (Target Lock):** Se agregó un raycast de línea de visión en el escáner cónico de 16°. Si un dron enemigo se oculta tras una torre, la retícula no puede fijarlo a través del concreto.
3. **Colisión Real de Mira Láser y Armas Hostiles (`EnemyAIService.server.luau`):**
   * La mira láser (`LaserSight`) proyecta un raycast dinámico de 70 studs. Al chocar contra una torre, su longitud se acorta a la distancia exacta de impacto (`actualDist`), pintando el punto en la pared sin atravesarla.
   * En `handleFiring`, si un rascacielos bloquea el vector al jugador, el disparo de la torreta Aegis-44 o el pulso microondas de Kuroshio queda cancelado.

---

## 30. Resolución de Condición de Carrera en Activación de Pilotaje ([E] ProximityPrompt vs UserInputService)

### 🔍 Diagnóstico del Fallo de Pilotaje ("Le doy a la [E] y no ocurre nada")
Al acercarse a `TestDrone` e interactuar con la tecla `[E]`, el jugador experimentaba que el dron no despegaba ni respondía al control. El análisis de flujo de ejecución reveló una condición de carrera instantánea (*flip-flop* en el mismo fotograma):
1. **Doble Disparo No Filtrado (`gpe` omitido):**
   En `Main.client.luau`, la función `UserInputService.InputBegan` contenía una omisión deliberada de `gpe` (*gameProcessedEvent*) pensada para capturar la tecla sin restricciones:
   ```luau
   if gpe then
       local focused = UserInputService:GetFocusedTextBox()
       if focused then return end
   end
   ```
2. **Ciclo de Cancelación Inmediata en Microsegundos:**
   Al presionar `[E]` frente al dron:
   * El motor de Roblox disparaba primero `ProximityPromptService.PromptTriggered`, llamando a `enterDrone()`.
   * `enterDrone()` establecía `isPiloting = true` e iniciaba `myDrone:StartFlying()`.
   * En el mismo ciclo de despacho de eventos de entrada, `UserInputService.InputBegan` se ejecutaba para la misma pulsación de `[E]`. Al ignorar `gpe` (que era `true` porque el ProximityPrompt ya había procesado el evento), el bloque evaluaba:
     ```luau
     if not isCurrentlyPiloting() then
         enterDrone()
     else
         exitDrone()
     end
     ```
   * Dado que `isCurrentlyPiloting()` ya era `true` por el paso anterior, el script entraba inmediatamente a la rama `else` y ejecutaba `exitDrone()`.
   * Como resultado, el dron iniciaba y cancelaba el vuelo en 0 milisegundos. Visualmente, el jugador no percibía ninguna reacción ("no ocurre nada").

### 🛠️ Solución Aplicada
1. **Debounce Temporal Estricto (`PILOT_TOGGLE_COOLDOWN`):**
   * Se incorporó una compuerta de tiempo con `lastPilotToggleTime` y un cooldown de `0.5 segundos` en `enterDrone()` y `exitDrone()`.
   * Cualquier petición concurrente o rebote de evento que intente alternar el estado en menos de 0.5s es rechazada inmediatamente.
2. **Filtrado Correcto de `gpe` en `UserInputService.InputBegan`:**
   * Se restauró la verificación `if gpe then return end`.
   * Cuando el ProximityPrompt procesa la tecla `[E]`, `InputBegan` descarta el evento y no ejecuta la rama `exitDrone()`.
   * La tecla `[F]` permanece como la vía canónica de teclado para desconectar el visor FPV (`exitDrone()`), mientras que `[E]` solo conmuta si el cooldown ha expirado y no proviene de un prompt en pantalla.
3. **Gestión de Visibilidad Local del ProximityPrompt:**
   * En `enterDrone()`, el script oculta localmente el `PilotPrompt` (`prompt.Enabled = false`) para evitar interferencias visuales o capturas accidentales durante el vuelo.
   * En `exitDrone()` y al reaparecer el dron tras ser destruido (`CombatService`), el `PilotPrompt` se reactiva limpiamente (`prompt.Enabled = true`).
4. **Protección de Velocidad del Avatar (`LockPlayerCharacter` / `UnlockPlayerCharacter`):**
   * En `DroneController.luau`, se aseguró que al guardar `self.originalWalkSpeed` solo se capturen valores mayores a 0, evitando que transiciones rápidas dejen al avatar del jugador permanentemente inmóvil con `WalkSpeed = 0`.
5. **Enlace Directo de Respaldo:**
   * Se conectó `prompt.Triggered` directamente sobre la instancia de `TestDrone` además del despachador global `ProximityPromptService`, garantizando captura inmediata aún con micro-latencias de red.

---

## 31. Solución Definitiva al Bloqueo de Tecla [E] y Control Autoritativo de Pilotaje

### 🔍 Causa Raíz de la Ausencia Total de Respuesta al Pulsar [E]
A pesar de la corrección anterior, pulsar `[E]` continuaba sin generar respuesta debido a un **bloqueo triple concurrente**:
1. **Firma Omitida de `player` en LocalScripts de Roblox (`ProximityPrompt.Triggered`):**
   En el motor de Roblox, cuando `ProximityPromptService.PromptTriggered` o `ProximityPrompt.Triggered` se ejecuta dentro de un `LocalScript`, el motor **no suministra el argumento `player`** (es `nil`) ya que el script pertenece intrínsecamente al jugador local. La condición previa:
   ```luau
   if player == localPlayer and prompt.Name == "PilotPrompt" then
   ```
   evaluaba `nil == localPlayer`, resultando **siempre en `false`**. Ninguno de los listeners del cliente activaba `enterDrone()`.
2. **Bloqueo de Tecla en `UserInputService.InputBegan` por `gpe = true`:**
   Al estar el jugador cerca del dron con el prompt visible, Roblox marca `gpe = true` para la tecla `[E]`. La comprobación `if gpe then return end` descartaba silenciosamente la pulsación física del teclado.
3. **Ausencia de Escucha en el Servidor:**
   El `PilotPrompt` fue creado en el servidor (`Main.server.luau`), pero nunca se le conectó un evento `Triggered` del lado del servidor.

### 🛠️ Arquitectura de Solución Aplicada (Autoritativa y Redundante)
1. **Listener Autoritativo en el Servidor (`Main.server.luau`):**
   * Se conectó `pilotPrompt.Triggered:Connect(function(player: Player))` directamente en el servidor.
   * Al ser activado, el servidor desancla inmediatamente el dron (`dronePart.Anchored = false`), desactiva el prompt, transfiere el `NetworkOwnership` a `player`, registra el dron en `CombatService` y envía `flightStateEvent:FireClient(player, "EnterDrone")`.
2. **Recepción Canónica en el Cliente (`Main.client.luau`):**
   * El cliente escucha `action == "EnterDrone"` e invoca `enterDrone()`.
3. **Corrección de Firma en Clientes:**
   * En `ProximityPromptService.PromptTriggered` y `prompt.Triggered`, se acepta tanto `triggeredPlayer == nil` como `triggeredPlayer == localPlayer`, asegurando compatibilidad con todas las versiones del motor de Roblox.
4. **Tecla [E] Dedicada Exclusivamente a Entrada (Idempotente):**
   * En `UserInputService.InputBegan`, la tecla `[E]` ahora **únicamente llama a `enterDrone()`** si `not isCurrentlyPiloting()`. Nunca llama a `exitDrone()`.
   * La desconexión del dron se efectúa de manera limpia e inequívoca mediante la tecla `[F]` o el botón en pantalla `[F] DESCONECTAR VISOR FPV`.
   * Al no conmutar salida en `[E]`, se elimina matemáticamente cualquier posibilidad de cancelación por rebote.
5. **Garantía Física en `DroneController:StartFlying()`:**
   * Se fuerza la activación explícita de `linearVelocity.Enabled = true` y `alignOrientation.Enabled = true` y el desanclaje local inmediato.

---

## 32. Eliminación de Bloqueos en Cadena y Auto-Inicialización On-Demand del Dron

### 🔍 Diagnóstico del Mensaje "Cargando dron... espera" y Congelamiento
Al presionar `[E]`, la interfaz mostraba `[E] CARGANDO DRON... ESPERA` y no permitía volar. La auditoría profunda del flujo de carga reveló:
1. **Bloqueo Secuencial Acumulado en el Hilo de Carga:**
   `Main.client.luau` ejecutaba un hilo monolítico que realizaba `WaitForChild` secuenciales para 7 módulos, la carga del avatar y su humanoide (`setupGoggles`), y múltiples llamadas a `NetworkEvents.Get`.
2. **Timeout Dual en `NetworkEvents.Get`:**
   Al buscar un evento inexistente en la raíz de `ReplicatedStorage` cuando ya residía en `CyberNetworkEvents`, la función esperaba hasta 6 segundos por evento dos veces (12s por evento). Con 7 eventos en cadena, la inicialización podía quedar congelada hasta por un minuto.
3. **Respuesta Pasiva de `enterDrone()`:**
   Si el jugador pulsaba `[E]` antes de que concluyera la inicialización de fondo, `enterDrone()` se limitaba a mostrar `[E] CARGANDO DRON... ESPERA` y retornaba (`return`), sin forzar la inicialización ni reanudar la acción.

### 🛠️ Solución Aplicada
1. **Inicialización On-Demand Inmediata (`initializeDrone`):**
   * En `enterDrone()`, si el dron aún no está listo al pulsar `[E]`, se invoca inmediatamente `initializeDrone()`. Si concluye con éxito, el despegue se ejecuta en el acto sin demoras.
2. **Desacoplamiento en Tareas Paralelas Independientes:**
   * **Tarea A:** Inicialización del `DroneController` prioritario al arrancar.
   * **Tarea B:** Suscripción directa al `ProximityPrompt` de `TestDrone`.
   * **Tarea C:** Equipamiento cosmético de gafas FPV y escuchas del avatar en su propio hilo sin bloquear el vuelo.
   * **Tarea D:** Suscripción a eventos de red (`NetworkEvents`) en segundo plano.
3. **Optimización de Búsqueda en `NetworkEvents.luau`:**
   * Se redujo el timeout de búsqueda y se eliminó la espera innecesaria en `ReplicatedStorage` raíz cuando la carpeta canónica `CyberNetworkEvents` ya existe, resolviendo eventos en menos de 1 milisegundo.

---

## 33. Resolución del Error `ERROR require(DroneController)` y Ambigüedad Sintáctica en Luau

### 🔍 Diagnóstico del Error
Al iniciar o interactuar con el dron, el botón holográfico mostraba: `ERROR require(DroneController)`.
El análisis del analizador sintáctico de Luau (`luau-lsp analyze`) arrojó:
`src/shared/DroneController.luau(684,5): SyntaxError: Ambiguous syntax: this looks like an argument list for a function call, but could also be a start of new statement; use ';' to separate statements`

1. **Causa Sintáctica:**
   En `DroneController.luau`, la línea 683 terminaba con la expresión:
   ```luau
   local cleanName = lockedEnemy.Name:gsub("_%d+", "")
   (self.hud :: any):SetTargetLock(cleanName, lockedEnemyDist)
   ```
   En la gramática de Luau/Lua, cuando una línea comienza con un paréntesis de apertura `(` inmediatamente después de una expresión, el parser lo interpreta ambiguamente como si se estuviera llamando a la expresión anterior (`""(...)`). Esto provocó que el compilador de Luau en Roblox rechazara el archivo completo al compilarlo para el cliente.
2. **Servicio Debris No Declarado:**
   En los métodos de armas y misiles guiados (`FireMissile`, `ReloadMissiles`, `SpawnLocalMissile`), se invocaba `Debris:AddItem(...)` sin haber obtenido el servicio `Debris` a nivel de módulo (`game:GetService("Debris")`).
3. **Manejo de Errores en `Main.client.luau`:**
   El mensaje de error no diferenciaba si el `ModuleScript` no existía en `ReplicatedStorage` o si fallaba por error de ejecución/sintaxis interna.

### 🛠️ Solución Aplicada
1. **Desambiguación Sintáctica en `DroneController.luau`:**
   Se desacopló la llamada a la interfaz usando una variable tipada:
   ```luau
   local hudAny: any = self.hud
   if hudAny and hudAny.SetTargetLock then
       if lockedEnemy then
           local cleanName = lockedEnemy.Name:gsub("_%d+", "")
           hudAny:SetTargetLock(cleanName, lockedEnemyDist)
       else
           hudAny:SetTargetLock(nil)
       end
   end
   ```
2. **Declaración del Servicio `Debris`:**
   Se incorporó `local Debris = game:GetService("Debris")` en la cabecera de `DroneController.luau`.
3. **Diagnóstico Mejorado en `Main.client.luau`:**
   Se separó la verificación de existencia de la instancia `ModuleScript` en `ReplicatedStorage` de la ejecución de `require()`, reportando dinámicamente cualquier error exacto devuelto por Luau.

---

## 34. Implementación Integral del Pilar 1: Apuntado en Tercera Persona, Retícula Predictiva y Feedback Sensorial ("Game Feel")

### 🎯 Objetivos Implementados
1. **Puntería Clásica y Limpia (Eliminación de LEAD):**
   * Por preferencia de diseño y para mantener la pantalla 100% limpia y sin distracciones, se retiró por completo el círculo flotante `LEAD`.
   * El cálculo de tiro adelantado se realiza ahora puramente a ojo e intuición del piloto (estilo arcade clásico / habilidad táctica).
2. **Mira Clásica Cyberpunk Neón y Hitmarker Táctico:**
   * **Mira Clásica Siempre Activa (Cian Neón):** Se eliminó el modo intrusivo de "Rastreo Amarillo" y la etiqueta parpadeante `[ ⚡ RASTREO ]` para preservar la estética limpia y clásica de la cabina.
   * **Bloqueo Exclusivo de Misiles (`state == "locked"`):** Únicamente cuando un enemigo está perfectamente centrado en la retícula para disparar un misil guiado, se activa el rótulo `[ 🎯 LOCK-ON: (OBJETIVO) | (DIST)m ]` y el punto central en rojo carmesí.
   * **Hitmarker Táctico:** Cruz diagonal (`X`) de 4 aspas blancas que parpadea instantáneamente con sonido metálico al impactar proyectiles. En caso de impacto letal (`isKill`), la cruz es roja de mayor tamaño.
3. **Zoom y Apuntado de Precisión al Hombro (RMB / MouseButton2):**
   * Al mantener presionado el botón derecho del ratón (RMB):
     * La cámara realiza un zoom suave reduciendo el FOV (de 70 a 48 en 3ra persona y a 42 en FPV).
     * La sensibilidad del ratón se amortigua un 45% para permitir microajustes de puntería finos a larga distancia.
     * Al soltar RMB, el FOV y la sensibilidad se restauran de inmediato.
4. **Retroceso Visual, Fogonazo y Sacudida de Pantalla (*Screen Shake*):**
   * Sistema de trauma cuadrático en `DroneController`:
     * Disparo de plasma: acumula trauma (+0.16), retroceso físico en el chasis (-1.5 studs/s) y fogonazo dinámico local `PointLight` en la tobera.
     * Lanzamiento de misil guiado: trauma pesado (+0.48) y retroceso de -5.0 studs/s.
     * Daño recibido: trauma intenso (+0.65).
     * El trauma decae de manera fluida y aplica microdesplazamientos con ruido Perlin (`math.noise`) a la cámara.

---

## 35. Implementación Integral del Pilar 2: Tácticas de Combate, Disparo Cargado, Purga Térmica, Bengalas y Física de Caída EMP

### 🎯 Objetivos y Mapeo de Controles (Auditoría de Teclas)
Se respetó con estricta rigurosidad la configuración previa de teclado para evitar conflictos:
* **[C] Conservado Intacto:** Exclusivo para el pulso electromagnético (`TriggerEMP`). No fue modificado ni reasignado.
* **[LMB] Sostenido (≥ 0.65s):** Disparo Cargado (*Magma-Orb Sobrecargado*). El clic rápido (*tap* < 0.65s) mantiene la cadencia de ráfaga rápida clásica (*Magma-Spike*).
* **[Z] Purga de Calor Activa:** Asignado a tecla `[Z]` (adyacente a X y C). Libera presión criogénica y resetea el calor a 0%.
* **[T] Bengalas Térmicas / Chaff:** Asignado a tecla `[T]` (adyacente a R y G). Lanza 4 contramedidas pirotécnicas para romper fijación de amenazas.

### 🛠️ Mecánicas Implementadas

1. **Disparo Cargado (*Magma-Orb Sobrecargado*):**
   * **Carga en Tiempo Real:** Al mantener pulsado el botón izquierdo del ratón (LMB), se genera un orbe de plasma en el morro del dron que escala su tamaño y transmuta de amarillo intenso a naranja ígneo al alcanzar la carga completa (0.65s).
   * **Balística y Área de Detonación:** Al soltar LMB, dispara un proyectil pesado de 2.4 studs a 150 studs/s. Al impactar genera una esfera de detonación de 18 studs de radio que inflige 50 de daño directo, daño de salpicadura decreciente y un empuje cinético de +40 studs/s a drones hostiles adyacentes.
   * **Costo de Energía:** Genera +28 unidades de calor y aplica un fuerte retroceso físico (-3.8 studs/s) y trauma de cámara (+0.38).

2. **Purga Térmica Criogénica Activa [Z]:**
   * **Función Táctica:** Resetea el calor acumulado instantáneamente a 0% y elimina el estado de sobrecalentamiento (*Overheat*). Requiere al menos un 15% de calor o bloqueo de armas para activarse.
   * **Efectos Audiovisuales:** Expulsa dos chorros laterales de vapor criogénico neón azul cian con sonido de despresurización de alta presión.
   * **Balance:** Cooldown de 8.0 segundos gestionado con telemetría en tiempo real.

3. **Bengalas Térmicas y Contramedidas Chaff [T]:**
   * **Despliegue Pirotécnico:** Eyección propulsada de 4 bengalas luminosas que caen con estela y luces de alta intensidad (`PointLight` de 24 studs de rango).
   * **Neutralización de Amenazas:** Desorienta a la IA enemiga en un radio de 85 studs durante 3.5s mediante la etiqueta `FlaresConfused`, forzando a los drones agresores a perder el blanco y realizar maniobras evasivas.
   * **Balance:** Cooldown de 10.0 segundos con advertencia y notificación en pantalla.

4. **Pulso EMP con Física de Apagado de Motores y Caída Libre [C]:**
   * **Desactivación de Propulsión:** Al disparar el pulso electromagnético en `[C]`, los motores de los drones en un radio de 90 studs se apagan totalmente (`LinearVelocity.Enabled = false`, `AlignOrientation.Enabled = false`).
   * **Caída Física Realista:** Se aplica una velocidad de desplome hacia abajo (`AssemblyLinearVelocity.Y = -45 studs/s`) y una velocidad angular caótica, haciendo que los drones enemigos giren descontrolados y se estrellen o caigan al vacío durante los 3.5 segundos de parálisis electromagnética.

5. **Actualización de Telemetría Táctica (HUD):**
   * El panel inferior izquierdo (`CombatStatusBox`) se redimensionó para presentar el estado y contador de recarga en vivo de las 4 habilidades tácticas:
     * `PULSO EMP [C]: ¡LISTO! ⚡` / `RECARGA (%ds)`
     * `MISILES [R]: [ ■ ■ ■ ] (3/3)`
     * `PURGA [Z]: ¡LISTO! ❄` / `RECARGA (%ds)`
     * `BENGALAS [T]: ¡LISTO! 🔥` / `RECARGA (%ds)`
   * La barra superior de comandos ahora incluye la referencia completa de teclas de combate.

---
*Fin del documento de auditoría técnica del Plan Maestro, Combate y Logística.*

---

## 36. Corrección Integral de Apuntado (Lag/Desfase de Mira), Sincronización de Purga Térmica [Z] y Físicas de Impacto Cinético

### 🔍 Análisis de Causas Raíz

#### 1. Desfase y "Atascamiento" de la Mira al Disparar (~1 segundo de retraso)
* **Interferencia de Raycast con Proyectiles Previos:** Al disparar en ráfaga rápida, los proyectiles locales y de red (`LocalPlasmaBolt`, `ServerPlasmaBolt`, `LocalChargingOrb`, destellos luminosos) se creaban en `Workspace` sin configurar `CanQuery = false`. Debido a que un proyectil tarda entre 0.8s y 2.5s en recorrer su distancia máxima, el Raycast de la cámara al hacer el siguiente clic colisionaba a quemarropa con la bala anterior en el aire. El disparo quedaba "atorado" exactamente en las coordenadas del proyectil previo a 2 studs frente a la nariz del dron.
* **Pugna de Cámara (Spring Fighting en 3ra Persona):** En `Heartbeat`, el sistema de *screen shake* manipulaba directamente `cam.CFrame` mientras `CameraType == Enum.CameraType.Custom`. El script de cámara nativo de Roblox intentaba forzar de vuelta su posición y orientación mediante resortes internos, lo cual generaba un micro-congelamiento de ~1 segundo en el movimiento del ratón y desfasaba el cálculo de `flightYaw`.
* **Secuestro de Mira Primaria por Cono de Fijación Amplio:** La función `FireWeapon` contenía la línea `if self.lockedTarget and self.lockedTarget.Parent then targetPart = self.lockedTarget`. El radar fijaba drones a 40° de apertura (`dot >= 0.94`), de modo que al apuntar a otro lado, las balas primarias seguían siendo teledirigidas al objetivo anterior hasta que salía completamente del cono.

#### 2. Purga Térmica Criogénica [Z] Inoperativa
* **Desincronización Servidor-Cliente:** En `CombatService.server.luau`, la rutina `onFireWeaponEvent` no acumulaba calor en el estado del dron del tirador en el servidor.
* **Sobreescritura Cíclica a 0%:** El bucle de actualización a 20 Hz del servidor emitía `onHeatUpdateEvent:FireClient(state.owner, 0)` cada 50ms, machacando cualquier calor acumulado en el cliente y dejándolo en 0.
* **Bloqueo por Umbral en Cliente:** La función `DroneController:VentHeat` contaba con la validación `if (self.currentHeat or 0) < 15 and not self.isWeaponOverheated then return end`. Al estar el calor forzado a 0 por el servidor, la purga quedaba permanentemente inhabilitada.

---

### 🛠️ Soluciones Técnicas Aplicadas

#### A. Aislamiento Total de Raycast y Apuntado Fiel al Centro
1. **Atributo `CanQuery = false` Universal:**
   * Se aplicó `CanQuery = false` y `CanTouch = false` en todos los objetos visuales: `LocalPlasmaBolt`, `ServerPlasmaBolt`, `LocalChargingOrb`, `ChargedBlastExplosion`, `LocalEMPWave`, `EMPShockwave`, `VentSteam`, `LocalFlare`, `ThermalFlare`, `LocalSmartMissile`, `CyberMissile`, chispas y cráteres.
   * Todos los efectos visuales y proyectiles ahora se alojan dentro de una carpeta unificada `Workspace.CombatFX`.
   * Tanto el cliente en `DroneController.luau` como el servidor en `CombatService.server.luau` excluyen `CombatFX` de todos los parámetros de `RaycastParams`.
2. **Eliminación del Conflicto de Cámara:**
   * La manipulación de `cam.CFrame` por *screen shake* quedó restringida exclusivamente a FPV / Scriptable.
   * Para 3ra persona se implementó `ApplyRecoilKick(isCharged)` en `DroneHUD.luau`: aplica un sacudón vertical ultra-rápido de 3 píxeles directamente sobre el contenedor de la retícula en la interfaz, con retorno en 80ms, brindando una sensación visceral de retroceso sin interferir jamás con los resortes de la cámara de Roblox.
3. **Desacople entre Fuego Primario y Misiles:**
   * `FireWeapon` y `FireChargedWeapon` disparan con precisión milimétrica hacia el punto de impacto exacto del Raycast central de la pantalla.
   * El objetivo fijado (`lockedTarget`) quedó restringido estrictamente para los misiles guiados `[R]`, con un cono de fijación más riguroso (`dot >= 0.985`, ~10° de apertura) para evitar fijaciones accidentales.

#### B. Sincronización y Restauración de Purga Térmica [Z]
1. **Generación Autoritativa de Calor:** Al recibir la solicitud de disparo, `CombatService.server.luau` aplica inmediatamente `applyHeat(shooterState, weaponSpec.heatGenerated)` en el dron del jugador.
2. **Recepción del Evento de Purga en Servidor:**
   * Al presionar `[Z]`, el cliente valida que haya calor (`currentHeat > 0`) o que el arma esté sobrecalentada.
   * El servidor resetea `state.heat = 0` y emite `onHeatUpdateEvent:FireClient(player, 0)`.
   * El cliente actualiza instantáneamente la barra de calor y el indicador táctico del HUD a 0%, expulsando los chorros laterales de vapor criogénico neón.

#### C. Físicas de Impacto Cinético en Entorno y Objetivos
1. **Cráteres Térmicos Incandescentes (`ImpactScorch`):**
   * Al impactar contra superficies sólidas del entorno (edificios, pavimento, rascacielos), se genera una decal/pieza plana fluorescente orientada según el vector normal de la superficie.
   * Mediante `TweenService`, la marca pasa de rojo fuego incandescente a carbón mate oscuro en 1.8 segundos antes de desvanecerse.
2. **Metralla y Chispas Físicas con Rebote Real (`ImpactSparks`):**
   * Cada impacto eyecta entre 4 y 8 chispas neón con `CanCollide = true` y velocidad angular y lineal caótica.
   * Las chispas rebotan físicamente contra las paredes y el suelo con amortiguación antes de consumirse en 0.45 segundos.
3. **Impulso Cinético en Objetos no Anclados:**
   * Los props, barreras y cajas no ancladas reciben una fuerza de impacto direccional calculada mediante `targetPart:ApplyImpulseAtPosition(bulletDir * force, hitPos)` (45 N para plasma estándar, 140 N para orbe cargado), saliendo despedidos físicamente.
4. **Flinch / Reacción de Impacto en Drones Hostiles:**
   * Los drones impactados reciben momento lineal directo (`AssemblyLinearVelocity += bulletDir * hitForce`) y desestabilización angular (`AssemblyAngularVelocity += randomTumble`), produciendo una respuesta de sacudida táctil contundente.

---

## 37. Pilar 3 (Fase 1 Focalizada): Telegrafiado Láser Pre-Disparo Gauss y Dron Baluarte con Escudo Frontal Hexagonal

### 🎯 Objetivos Implementados
1. **Sistema de Apuntado Telegrafiado Láser (*Telegraphing Laser & Lock-Warning*):**
   * Elimina la punición instantánea del cañón Gauss de cornisa (`aegis_44` y `aegis_bulwark`), otorgando 1.05 segundos de ventana de reacción defensiva mediante un haz láser 3D visible, audio diegético y alerta en HUD.
   * Si el jugador se zambulle detrás de un edificio, torre o helipuerto durante el telegrafiado, la línea de visión se rompe y el disparo se cancela automáticamente (`[ ✓ FIJACIÓN ROTA // COBERTURA ASEGURADA ]`).
   * Si el jugador despliega bengalas `[T]` o impacta con EMP `[C]`, la carga se aborta inmediatamente.

2. **Dron Pesado Baluarte con Escudo Direccional (*Aegis-Bulwark Heavy Drone*):**
   * Nuevo arquetipo táctico blindado (240 HP, 180 Pelaocoins de recompensa) equipado con un escudo hexagonal frontal de energía (`ForceField`).
   * **Mecánica de Escudo Frontal:** Los impactos directos desde el cono frontal sufren un 85% de reducción de daño y hacen parpadear el panel de fuerza emitiendo sonido de rebote.
   * **Contramedidas y Vulnerabilidades Tácticas:**
     * **Flanqueo:** Disparar a sus toberas y motores traseros otorga **daño crítico x1.35**.
     * **Disparo Cargado `[LMB sostenido]`:** La detonación de área (18 studs) traspasa la barrera direccional.
     * **Misil Guiado `[R]`:** La trayectoria parabólica Bézier ataca cenitalmente por el techo, eludiendo el panel frontal.
     * **Pulso EMP `[C]`:** Colapsa el escudo totalmente durante la sobrecarga electromagnética.

### 🛠️ Archivos Modificados
* `src/shared/NetworkEvents.luau`: Registro del evento `IncomingThreatAlert`.
* `src/shared/EnemyTypes.luau`: Especificación del arquetipo `AEGIS_BULWARK`.
* `src/shared/DroneHUD.luau`: Componente visual `IncomingThreatBanner` con estados de alerta roja y despeje cian.
* `src/shared/DroneController.luau`: Receptor de `IncomingThreatAlert` con sonido de pitido agudo de cabina.
* `src/server/EnemyAIService.server.luau`: Rutinas de telegrafiado `handleRailDriverCharging` y ensamblaje de `FrontShield`.
* `src/server/CombatService.server.luau`: Cálculo de ángulo vectorial de impacto (`lookVector:Dot(toSource)`) para deflexión frontal y daño crítico en la espalda.

---

## 38. Expansión del Espacio Aéreo Metropolitano: Reubicación de Torres A y B

### 🎯 Objetivo
Alejar las torres respecto a la Base Central para proporcionar mayor escala al mundo abierto, rutas de vuelo más desafiantes e inmersivas, y suficiente espacio aéreo para combates cinéticos y uso de turbo nitro.

### 📐 Calibración Espacial
* **Base Central:** `Vector3.new(0, 4, 0)` (conservada como origen de operaciones).
* **Torre A (Sector Industrial):**
  * Posición anterior: `(160, 95, -180)` (~240 studs de distancia).
  * **Nueva posición:** `Vector3.new(300, 115, -340)` (~453 studs de distancia, altura de 115 studs).
  * Recompensa de entrega aumentada: **350 ₵** (antes 250 ₵).
* **Torre B (Sector Black Ops):**
  * Posición anterior: `(-200, 50, 140)` (~244 studs de distancia).
  * **Nueva posición:** `Vector3.new(-360, 65, 260)` (~444 studs de distancia, altura de 65 studs).
  * Recompensa de entrega aumentada: **500 ₵** (antes 400 ₵), ventana de bonus extendida a 120s.
* **Separación entre Torres A y B:** Ampliada de ~480 studs a **~892 studs** de recorrido metropolitano.

### 🛠️ Ajustes de Sistemas y Radar
1. **Radar Táctico 360° (`DroneHUD.luau`):** Se incrementó `RADAR_MAX_DIST` de 320 a **500 studs** para abarcar el nuevo perímetro urbano sin cortar los blips holográficos de los helipuertos ni de las patrullas hostiles.
2. **Director de Amenazas (`EnemyAIService.server.luau`):**
   * Centros de patrulla `Zone_TorreA` y `Zone_TorreB` anclados a las nuevas coordenadas.
   * `activationRadius` ampliado a 380 studs y `deactivationRadius` a 900 studs para persistencia fluida de patrullas.
3. **Gestor Logístico (`DeliveryManager.luau` y `Main.server.luau`):** Coordenadas sincronizadas en servidor y cliente para balizas de entrega, conos de aproximación y rótulos de helipuerto.







