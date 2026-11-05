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
*Fin del documento de auditoría técnica.*

