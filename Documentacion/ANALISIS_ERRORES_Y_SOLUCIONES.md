# 📘 Cyber Delivery Tycoon — Análisis Integral de Errores y Correcciones

**Proyecto:** Cyber Delivery Tycoon (Roblox Luau / Rojo)  
**Fecha de Auditoría y Corrección:** 5 de Noviembre, 2026  
**Autor:** Nexsson1 & Antigravity AI  

---

## 📑 Tabla de Contenidos
1. [Resumen Ejecutivo](#1-resumen-ejecutivo)
2. [Error Crítico 1: El Dron solo sube y no puede descender (Sign Inversion Bug)](#2-error-crítico-1-el-dron-solo-sube-y-no-puede-descender)
3. [Error Crítico 2: Bloqueo de Carga y Tecla [E] Inoperativa (Top-Level Requires Hang)](#3-error-crítico-2-bloqueo-de-carga-y-tecla-e-inoperativa)
4. [Error Crítico 3: Bloqueo de Teclas WASD por el Character Controller (GPE Flag)](#4-error-crítico-3-bloqueo-de-teclas-wasd-por-el-character-controller)
5. [Error Crítico 4: Conflicto de Físicas y Network Ownership (HumanoidRootPart Anchoring)](#5-error-crítico-4-conflicto-de-físicas-y-network-ownership)
6. [Mejoras de Conducción, Físicas y Mapeo de Controles](#6-mejoras-de-conducción-físicas-y-mapeo-de-controles)
7. [Matriz de Estado y Diagnóstico de Archivos](#7-matriz-de-estado-y-diagnóstico-de-archivos)

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
*Fin del documento de auditoría técnica del Plan Maestro y Sistema de Hostilidad.*




