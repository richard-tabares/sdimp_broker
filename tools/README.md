# Herramientas de prueba del Broker (SDIMP)

Herramientas para simular equipos (estaciones) que transmiten al broker y para probar el flujo completo sin necesidad de hardware real.

| Archivo | Descripción |
|---|---|
| `sim_tramas.py` | Simulador de equipos. Abre conexiones TCP al broker y envía tramas con la misma cadencia del equipo real. |
| `fake_broker.py` | Broker falso. Emula el comportamiento del broker real para probar el simulador sin abrir Processing. |
| `sim_config.json` | Valores por defecto del simulador (opcional; el CLI siempre tiene prioridad). |

Requisitos: Python 3 (solo librería estándar). No requiere dependencias externas.

---

## 1. Cómo funciona el flujo

```
┌─────────────────┐   TCP :12345    ┌───────────────┐   POST form-data   ┌─────────────────┐   SQL   ┌────────┐
│ Equipo/Estación │ ──────────────▶ │     Broker    │ ─────────────────▶ │  seguridad.php  │ ──────▶ │ MySQL  │
│ (sim_tramas.py) │ ◀────────────── │  (Processing) │                    │   (sdimp.com)   │         └────────┘
└─────────────────┘    ACK '1'      └───────────────┘                    └─────────────────┘
```

- El **equipo** es cliente TCP: se conecta al broker y envía tramas.
- El **broker** es servidor TCP (puerto 12345 en la fuente actual) y también cliente HTTP: encola cada trama y la reenvía al endpoint `seguridad.php` mediante workers HTTP, sin bloquear el `draw()`.
- El **endpoint** inserta las filas en `tbl_equipo` y `tbl_equipo_Backup`.
- El simulador **solo** habla con el broker; nunca llama al endpoint ni a la base de datos.

Puntos clave del broker:

- Atiende hasta `MaxTramasPorFrame` clientes por frame (default 10) a 5 fps: capacidad de recepción teórica de **50 tramas/s**.
- En cada lectura drena el buffer del cliente y conserva **solo la primera línea**. Si un equipo manda 2 o más líneas juntas, las extra se pierden.
- Antes de leer escribe el byte ACK `'1'` al cliente. Ese ACK significa **"leí datos de este cliente"**, no "guardé en la base de datos". Se envía incluso si la trama es inválida o si el POST falla.
- El equipo real **no lee el ACK**: solo comprueba `available()` para pintar un indicador, y nunca consume el byte. Por eso el ACK no controla el ritmo de envío ni produce reintentos.
- El POST se ejecuta en workers HTTP con conexiones persistentes. La cola es acotada: si se llena, se descarta la trama más vieja. No hay reintentos.
- El simulador drena y cuenta los ACKs solo como diagnóstico de lecturas atendidas.

---

## 2. Formato de la trama

Una sola línea de texto, 12 valores separados por un espacio, terminada en `\n`.

```
1 0.52 12.4 0.31 0.07 20.9 2026 10 15 08 15 30\n
```

| Pos | Campo | Valores | Ejemplo |
|---|---|---|---|
| 1 | id del equipo | 1..numEq (`Equipos` de `conf.txt`) | `1` |
| 2 | CO2 | % | `0.52` |
| 3 | CO | ppm | `12.4` |
| 4 | H2S | ppm | `0.31` |
| 5 | NO2 | ppm | `0.07` |
| 6 | O2 | % | `20.9` |
| 7 | año | — | `2026` |
| 8 | mes | 01–12 | `10` |
| 9 | día | 01–31 | `15` |
| 10 | hora | 00–23 | `08` |
| 11 | minuto | 00–59 | `15` |
| 12 | segundo | 00–59 | `30` |

Reglas:

- Separador exacto: un espacio. El broker escribe el byte `'1'` antes de leer.
- El `id` debe estar entre 1 y `Equipos` de `Broker/data/conf.txt`; el broker ignora ids fuera de ese rango.
- Si no hay `\n`, la trama se descarta.
- El equipo real envía los sensores y las fechas como `float`, por ejemplo `2026.0 10.0 15.0`. El simulador reproduce ese estilo con `--formato equipo` (default). Con `--formato fijo` usa fechas con ceros (`2026 10 15`). El broker acepta ambos formatos.

---

## 3. `sim_tramas.py` — simulador de equipos

### Comportamiento

- Un hilo con conexión TCP persistente por equipo.
- Envía **una trama cada 2 segundos** por equipo, igual que el equipo real.
- **No espera ACK** para enviar la siguiente trama y no reconecta por falta de ACK.
- Drena los ACKs pendientes de forma no bloqueante y los cuenta. El resumen muestra tramas enviadas, ACKs observados y pérdida estimada.
- Reconexión automática si el broker se cae o el socket falla.
- Arranque escalonado (`--ramp`) y jitter para no ir en lockstep.
- Valores con random walk: cada equipo mantiene su estado y varía los sensores de forma gradual. `--paso 0` deja los valores fijos.
- Los equipos en alarma permanecen dentro de su zona de alarma.
- Log por trama con `--verbose` y resumen cada 5 segundos.

> El conteo de ACKs es aproximado al detener: pueden quedar ACKs en vuelo o tramas pendientes en el broker. Para un conteo exacto de lecturas procesadas usa `fake_broker.py`, que imprime `PROCESADAS` y `DESCARTADAS`.

### Opciones

| Opción | Default | Descripción |
|---|---|---|
| `--host` | `127.0.0.1` | IP del broker. En producción usar la IP por LAN (p. ej. `192.168.0.100`). |
| `--puerto` | `12345` | Puerto TCP del broker. |
| `--equipos` | `1` (de `sim_config.json`) | Número de equipos a simular (ids 1..N). Avisa si N supera `Equipos` de `conf.txt`. |
| `--intervalo` | `2.0` | Segundos entre envíos por equipo. `0` envía sin espera (máxima velocidad). |
| `--jitter` | `0.05` | Segundos aleatorios extra entre envíos. |
| `--duracion` | `0.0` | Segundos de ejecución. `0` = indefinido. |
| `--ramp` | `2.0` | Segundos para escalonar el arranque de los equipos. |
| `--seed` | ninguno | Semilla aleatoria para reproducibilidad. Sin semilla, cada ejecución es distinta. |
| `--formato` | `equipo` | `equipo` (fechas como float, estilo del equipo real) o `fijo` (fechas con ceros). |
| `--paso` | `0.01` | Amplitud del random walk por trama, como fracción del rango del gas. `0` = valores fijos. |
| `--escenario` | `normal` | `normal`, `alarma`, `desconexion`. Se combinan con comas. |
| `--pct-alarma` | `30` | Porcentaje de equipos que emiten valores en alarma. |
| `--pct-desconexion` | `30` | Porcentaje de equipos que se desconectan. |
| `--desconexion-desde` | `30` | Segundos tras los cuales se desconectan esos equipos. |
| `--rango` | ver abajo | Rangos por gas: `GAS=min,max` separados por espacio. |
| `--verbose` | desactivado | Log detallado de cada trama enviada. |

Rangos por defecto (operación normal, por debajo de las alarmas del broker):

| Gas | Rango |
|---|---|
| CO2 | 0.03 – 0.8 % |
| CO | 0 – 15 ppm |
| H2S | 0 – 0.8 ppm |
| NO2 | 0 – 0.1 ppm |
| O2 | 20.0 – 21.5 % |

### Escenarios

- **`normal`**: valores con random walk dentro de los rangos configurados.
- **`alarma`**: el porcentaje indicado de equipos emite todos sus gases en zona de alarma:
  - CO2 1.0–5.0 %, CO 25–200 ppm, H2S 1–50 ppm, NO2 0.2–20 ppm, O2 17.0–19.4 o 23.6–25.0 %.
  - Cada equipo de O2 queda fijo en alarma baja o alta y su random walk se mantiene en esa zona.
  - Activa triángulos rojos y sonido en el broker.
- **`desconexion`**: el porcentaje indicado de equipos deja de transmitir a los `--desconexion-desde` segundos. Activa el círculo rojo vía `detectarConexion()` cuando transcurre `TimeoutConexion` (20 s en la configuración actual) y conserva el último valor recibido.

Al combinar `alarma,desconexion`, los equipos seleccionados pueden repetirse entre ambos grupos.

### `sim_config.json`

Si existe, sus claves reemplazan los defaults internos. Precedencia: **CLI > `sim_config.json` > defaults**.

El archivo incluido deja `equipos` en `1`. Para simular varios equipos usa `--equipos N`, pero `N` no debe superar el campo `Equipos` de `Broker/data/conf.txt`; si lo supera, el broker ignora las tramas con ids fuera de rango. La configuración actual de `data/conf.txt` usa `Equipos:5`.

Para una prueba de 15 equipos, primero ajusta `Equipos` a `15` en `Broker/data/conf.txt` y luego ejecuta `--equipos 15`.

```json
{
  "host": "127.0.0.1",
  "puerto": 12345,
  "equipos": 1,
  "intervalo": 2.0,
  "jitter": 0.05,
  "duracion": 0.0,
  "ramp": 2.0,
  "seed": null,
  "formato": "equipo",
  "paso": 0.01,
  "escenario": ["normal"],
  "pct_alarma": 30.0,
  "pct_desconexion": 30.0,
  "desconexion_desde": 30.0,
  "rangos": {
    "CO2": [0.03, 0.8],
    "CO": [0.0, 15.0],
    "H2S": [0.0, 0.8],
    "NO2": [0.0, 0.1],
    "O2": [20.0, 21.5]
  },
  "verbose": false
}
```

### Ejemplos

```bash
# Un equipo durante 60 segundos
python3 sim_tramas.py --equipos 1 --duracion 60

# Los equipos configurados en Broker/data/conf.txt (ej. 15), con cadencia real de 2 s
python3 sim_tramas.py --equipos 15

# 20 equipos durante 3 minutos, con valores y tiempos personalizados
python3 sim_tramas.py --equipos 20 --duracion 180 --intervalo 3 \
    --rango CO2=0,1.5 CO=0,40 H2S=0,3 NO2=0,0.3 O2=20.0,21.5

# 30% de equipos en alarma
python3 sim_tramas.py --equipos 15 --escenario alarma --pct-alarma 30

# 40% de equipos se desconectan a los 30 segundos
python3 sim_tramas.py --equipos 15 --escenario desconexion --pct-desconexion 40 --desconexion-desde 30

# Combinado
python3 sim_tramas.py --equipos 15 --escenario alarma,desconexion --pct-alarma 20 --pct-desconexion 20

# Formato con fechas rellenas con ceros y valores fijos
python3 sim_tramas.py --equipos 1 --formato fijo --paso 0 --verbose

# Ejecución reproducible
python3 sim_tramas.py --equipos 15 --seed 42 --duracion 60
```

---

## 4. Capacidad del broker y pérdida

El equipo real envía una trama cada ~2 segundos por estación:

```text
1 trama / 2 s = 0,5 tramas/s por equipo
30 tramas/minuto
1.800 tramas/hora
43.200 tramas/día
```

El broker recibe hasta `MaxTramasPorFrame` clientes por frame a 5 fps:

```text
5 fps × 10 clientes/frame = 50 lecturas/s de capacidad de recepción
```

Con 15 equipos la oferta es:

```text
15 × 0,5 = 7,5 tramas/s
```

Eso queda por debajo del techo de recepción. El límite real está en los workers HTTP y el endpoint: con `HttpWorkers=6` y una latencia de ~536 ms por POST, la capacidad estimada es de ~11 POST/s. Si el endpoint tarda más, la cola crece. Si la cola se llena, se descarta la trama más vieja.

El ACK cuenta **lecturas atendidas**, no filas guardadas ni POST exitosos. Se envía al leer, antes de encolar. Para medir el tramo HTTP/BD hay que mirar el resumen del broker:

```text
HTTP recibidas=... ok=... err=... 404=... cola=... descartadas=... latencia=...ms
```

Cuando un equipo tiene dos líneas acumuladas, el broker conserva la primera (la más vieja) y descarta la más nueva. Con la capacidad actual de recepción esto solo debería ocurrir si el broker queda bloqueado o hay una ráfaga anormal.

---

## 5. `fake_broker.py` — broker falso

Emula el comportamiento de recepción del broker para trabajar sin Processing:

- Acepta múltiples clientes TCP.
- Atiende 1 cliente por frame a 5 fps, en round-robin entre los que tienen datos.
- Envía el byte ACK `'1'`, drena el buffer del cliente y conserva solo la primera línea, reproduciendo la pérdida en ráfagas.
- No emula la cola ni los workers HTTP del broker actual.
- Al finalizar imprime `PROCESADAS`, `DESCARTADAS` y la tasa.

| Opción | Default | Descripción |
|---|---|---|
| `--host` | `127.0.0.1` | IP de escucha. |
| `--puerto` | `12345` | Puerto TCP de escucha. |
| `--duracion` | `0.0` | Segundos de ejecución. `0` = indefinido. |
| `--verbose` | desactivado | Imprime cada trama recibida. |

Ejemplos:

```bash
# Terminal 1: broker falso durante 30 s
python3 fake_broker.py --duracion 30 --verbose

# Terminal 2: simulador de 5 equipos durante 20 s
python3 sim_tramas.py --equipos 5 --duracion 20 --ramp 1
```

En el broker falso, `PROCESADAS` es la referencia exacta de lecturas atendidas; el ACK del simulador puede quedar corto al detener por ACKs en vuelo.

---

## 6. Interpretación de resultados

| Señal | Significado |
|---|---|
| ACKs ≈ tramas enviadas | El broker leyó todas las tramas. |
| ACKs < tramas enviadas | Alguna conexión o cliente no fue atendido, o se detuvo con ACKs en vuelo. No mide por sí solo el resultado del POST. |
| Cola HTTP creciente o `descartadas > 0` | El endpoint no da abasto; revisar `HttpWorkers`, latencia y errores. |
| `HTTP err > 0` | Fallos de red o HTTP. Sin reintentos, esas tramas no llegan a la BD. |
| Equipos activos < total en el resumen | Equipos aún arrancando (ramp) o desconectados por escenario. |
| Punto verde / rojo en el broker | Equipo transmitiendo / sin transmitir dentro de `TimeoutConexion`. |
| Triángulo rojo + sonido | Gas en umbral bajo (o alto, en O2). |

Umbrales de alarma del broker (referencia):

| Gas | Baja | Alta |
|---|---|---|
| CO2 | 1 % | 3 % |
| CO | 25 ppm | 75 ppm |
| H2S | 1 ppm | 5 ppm |
| NO2 | 0.2 ppm | 5 ppm |
| O2 | 19.5 % | 23.5 % |

---

## 7. Solución de problemas

- **`Connection refused` al iniciar**: el broker no está escuchando. Verifica que Processing esté corriendo el sketch (puerto 12345) o levanta `fake_broker.py`.
- **La pantalla no cambia**: revisa `--host`/`--puerto` y que el broker sea la versión nueva (12345). La versión vieja de `linux-arm` usa 24689.
- **Aviso "el broker ignorara ids > N"**: `--equipos` supera el campo `Equipos` de `conf.txt`. Ajusta uno de los dos.
- **Cola HTTP creciente o descartadas con 15 equipos a 2 s**: el cuello de botella está en el endpoint/BD, no en la recepción. Revisa `HttpWorkers`, la latencia y los errores del broker.
- **ACKs menores que las tramas enviadas**: normal si alguna conexión no fue atendida o si se detuvo la ejecución con ACKs en vuelo. Para pérdida HTTP/BD usa el resumen `HTTP` del broker.
- **El endpoint responde 404 (no guarda en BD)**: falta la mina (`tbl_mina.IP`) o el dispositivo (`tbl_dispositivo`) correspondiente al id. La pantalla del broker sí se actualiza. El simulador no llama al endpoint; solo envía al broker.
- **Sin valores o valores poco realistas**: revisa `--rango`, `--paso` y `--escenario`.

Nota: el broker ahora desacopla la recepción del envío HTTP mediante cola y workers. Las herramientas de simulación viven en `Broker/tools/` y no llaman al endpoint ni a la BD.
