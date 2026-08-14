# Pipeline de datos — WideWorldImporters

Proyecto de aprendizaje: construcción de un pipeline de datos BI/Analytics de punta a punta
sobre SQL Server, desde una base transaccional hasta un dashboard en Power BI.

## Arquitectura

Sigue el patrón **medallion** (bronze / silver / gold):

| Capa | Base de datos | Estado |
|---|---|---|
| **Producción** (OLTP) | `WideWorldImporters` | ✅ restaurada — nunca se modifica |
| **Staging / bronze** | `WWI_Staging` | ✅ implementada y automatizada |
| **Resumen / gold** (esquema estrella) | pendiente | ⬜ |
| **Dashboard** | Power BI | ⬜ |

El dashboard se conectará **únicamente** a la capa resumen. Nunca a staging ni a producción.

## Plan de 6 pasos

1. ✅ Restaurar `WideWorldImporters` como fuente
2. ✅ Esquema de staging + stored procedure de extracción con validaciones
3. ✅ Automatizar la extracción con un SQL Server Agent Job (falta el alerting)
4. ⬜ Capa resumen con lógica de negocio y esquema estrella
5. ⬜ Automatizar la actualización de la capa resumen
6. ⬜ Conectar el dashboard a la capa resumen

## Decisiones de diseño

### Staging vive en su propia base de datos
`WWI_Staging` es una base separada, no un schema dentro de `WideWorldImporters`. Esto
mantiene producción intacta: las tablas de staging no entran en sus backups, el
`TRUNCATE`+`INSERT` diario no infla su transaction log, y los permisos se pueden separar
por capa.

### Recovery model `SIMPLE`
Los datos de staging son **reproducibles**: si se pierden, se regeneran corriendo la carga
otra vez. Pagar el costo operativo de `FULL` (backups de log periódicos, crecimiento del
log) para proteger datos regenerables gratis es desperdicio. Los datos derivados no
necesitan las mismas garantías de durabilidad que los datos de origen.

### Source-aligned staging
Los schemas de staging **espejan los del origen**: `WideWorldImporters.Sales.Orders` se
stagea como `WWI_Staging.Sales.Orders`. Renombrar es una transformación, y el principio de
la capa bronze es minimizar transformaciones — reorganizar el modelo es trabajo de la capa
resumen. Ventaja adicional: el mapeo es mecánico y predecible.

La metadata del pipeline (`ValidationLog`, `LoadBatch`) vive en un schema aparte, `etl`,
para que los schemas espejados contengan *exactamente* lo que existe en el origen.

### Tipos relajados, sin constraints, en las tablas espejadas
Todas las columnas copiadas del origen son `NULL`-ables aunque en producción sean
`NOT NULL`. El trabajo de staging es **capturar lo que venga, incluso si viene mal**; la
validación es un paso posterior. Si la tabla rechazara filas con constraints, se estaría
validando en la capa equivocada y se perdería visibilidad de qué llegó mal.

Las tablas propias del pipeline (`etl.*`) **sí** llevan constraints — son datos generados
por código propio, donde un constraint no rechaza realidad ajena sino que atrapa bugs
propios.

### Nombres de tres partes solo al cruzar bases
`WideWorldImporters.Sales.Orders` (cruza el límite de la base) vs `Sales.Orders` (local).
Hardcodear el nombre de la base en referencias locales hace que una copia restaurada bajo
otro nombre siga escribiendo en la original.

### Timestamps en UTC
Todas las columnas de fecha/hora de `etl.*` usan `SYSUTCDATETIME()`, es decir **UTC**.
SQL Server Agent, en cambio, registra su historial en **hora local**. La misma corrida
aparece con horas distintas en `etl.LoadBatch` y en `msdb.dbo.sysjobhistory` — tenerlo
presente al correlacionar ambas fuentes.

La razón de guardar en UTC es el horario de verano: un job programado a las 2 AM local se
ejecuta dos veces el día que el reloj se atrasa y ninguna el día que se adelanta. Con
timestamps locales eso produce corridas con hora duplicada o huecos inexplicables en el
historial. UTC no tiene saltos.

### Carga completa (full load) e idempotente
`TRUNCATE` + `INSERT`, envueltos en una transacción. Correr el procedure N veces siempre
deja el snapshot actual del origen, sin acumular duplicados. La alternativa —carga
incremental / delta— queda fuera de alcance por ahora.

### Estrategia de validación: log & continue
Los problemas de calidad se registran en `etl.ValidationLog` pero **no frenan la carga**.
Abortar 73.595 filas buenas por una sospechosa es mala relación costo/beneficio. El
`fail-fast` corresponde a la capa resumen, donde ya no se quieren propagar datos rotos a un
dashboard.

### Carga y validación son procedures separados
`usp_LoadSalesOrders` invoca a `usp_ValidateSalesOrders`. Están separados para que la
validación se pueda **ejecutar y probar de forma aislada** — si estuvieran juntos, probar
la validación con datos sucios sería imposible, porque el `TRUNCATE` borraría los datos de
prueba antes de que las validaciones los vieran.

## Paso 4 — Capa resumen y esquema estrella

Estado: **decidido el grano y la orquestación de staging; el modelo dimensional
todavía no.** Esta sección separa las dos cosas a propósito — lo de abajo del
subtítulo "Sin decidir" no está resuelto y no debe darse por cerrado.

### Grano de la tabla de hechos: una fila por línea de pedido

`FactSales` tiene el **grano atómico**: una fila por cada línea de producto de
cada pedido. 231.412 filas. `OrderLineID` es único en el hecho, y ése es el
control de que el grano se respeta.

**Por qué el nivel más bajo.** Agregar es fácil, desagregar es imposible. Desde
las líneas se calculan los totales por pedido con un `SUM`; al revés no hay
vuelta. Guardar una fila por pedido dejaría sin respuesta *"¿cuál fue el producto
más vendido?"* — y no lentamente, sino para siempre: el dato deja de existir.

Cada nivel de agregación que se elige es una pregunta que ya no se va a poder
responder, y el costo no se paga al construir sino meses después, cuando aparece
un análisis que no se anticipó y hay que rehacer el modelo y recargar el
histórico. El grano atómico es una apuesta sobre las preguntas que todavía no
hicieron.

**La objeción de rendimiento no cambia el grano.** 231 mil filas en vez de 73 mil
se resuelven con índices columnstore y con agregaciones construidas *encima* del
detalle. Pre-agregar para ganar velocidad es tirar información para resolver un
problema que tiene solución técnica. Una tabla agregada complementa al hecho
atómico, nunca lo reemplaza.

**Proceso de negocio: pedidos, no facturas.** Ver
`exploration/02_alcance_y_exclusiones.md`. La medida se llama *importe de
pedidos*, no *ventas*.

### Consecuencia: `Sales.OrderLines` en staging

El grano se propaga hacia atrás: no se puede construir un hecho a un grano que la
capa bronce no captura. `Sales.Orders` **no tiene ninguna columna de importe** —
la facturación es `Quantity` × `UnitPrice`, y ambas viven en `OrderLines`.

Por eso el modelado dimensional se diseña *antes* de terminar la extracción,
aunque se implemente después.

### Orquestación: procedure orquestador

Con dos tablas cargadas por dos procedures separados aparece un problema que no
existía con una sola: **cada tabla es correcta por separado y el conjunto puede
no serlo.** Si `Orders` carga y `OrderLines` falla, staging queda con 73.595
pedidos y 0 líneas; ninguna fila de `etl.LoadBatch` miente, y sin embargo quien
lea staging ve pedidos, no ve error, y concluye que las ventas fueron cero. Se
llama **integridad transversal**.

Procedures separados por tabla se mantienen — responsabilidad única, testeo
aislado, re-ejecución selectiva, aislamiento de fallos. Lo que se agrega es un
orquestador, `etl.usp_LoadSales`, que genera un identificador de corrida y llama
a los procedures de carga en orden.

**Por qué no dos pasos de Agent Job.** Funcionaría, y es la respuesta estándar en
SQL Server. Se descartó por dos razones concretas: la consistencia viviría en la
automatización y no aplicaría a ejecuciones manuales; y el estado de la corrida
quedaría en `msdb.dbo.sysjobhistory` — otra base, en hora local mientras `etl.*`
está en UTC, con purga automática y duraciones en segundos. En el Paso 5 el
procedure que carga el DW necesita preguntar *en SQL* si staging está completo, y
esa respuesta tiene que estar en `etl.*`.

**El orquestador NO abre transacción.** Es la trampa de este diseño. Los `INSERT`
a `etl.LoadBatch` están fuera de transacción a propósito, para que las corridas
fallidas dejen rastro. Si el orquestador envolviera las llamadas en una
transacción, esos `INSERT` pasarían a estar adentro y un `ROLLBACK` los borraría:
la corrida fallaría sin dejar evidencia de haber existido. Además, en SQL Server
las transacciones anidadas no son reales — `COMMIT` anida, `ROLLBACK` no: un
rollback interno deshace hasta la transacción más externa.

Consecuencia asumida: **esto da trazabilidad de la corrida, no atomicidad.** Se
va a poder saber que el conjunto quedó inconsistente, no evitar que quede así.
La atomicidad real requeriría cargar a tablas paralelas e intercambiarlas al
final; queda fuera de alcance.

### Registro de corrida: `etl.LoadRun`, tabla aparte

Modelo **cabecera-detalle**: `etl.LoadRun` una fila por corrida, `etl.LoadBatch`
una fila por tabla dentro de esa corrida — el mismo patrón que `Orders` /
`OrderLines`.

Se descartó la alternativa de una simple columna `RunId` en `LoadBatch` porque
ahí la corrida no existiría como entidad: sería una etiqueta pegada a filas que
escribieron otros, y una corrida que falla antes de llamar al primer procedure no
dejaría rastro alguno. Es literalmente el argumento que ya justifica que la fila
de `LoadBatch` se inserte al arrancar y no al terminar, aplicado un nivel más
arriba. Segundo motivo: el error del propio orquestador no tiene dónde guardarse
sin una tabla propia.

### Sin decidir

Nada de lo siguiente está resuelto. Son decisiones abiertas, no omisiones:

- **Qué dimensiones tendrá el modelo**, y con qué atributos cada una.
- **Cómo se resuelve el muchos a muchos de producto ↔ categoría.** 227 productos,
  442 asignaciones vía `Warehouse.StockItemStockGroups`. Unir el hecho a través
  de esa tabla puente multiplica filas e infla importes sin producir error
  (*fan-out*). Hay varias salidas posibles y no se eligió ninguna.
- **Qué tipo de SCD lleva la dimensión de cliente.** Dato relevante ya conocido:
  `Sales.Customers` es tabla temporal de sistema, así que el origen **ya guarda
  el historial** que normalmente hay que construir a mano. Son 17 tablas
  temporales en total.
- **Si habrá miembro desconocido**, con qué clave y para qué dimensiones.
- **Qué hace el hecho con `UnitPrice` NULL.** En staging se registra y no se
  frena (*log & continue*), pero **una medida del hecho no puede llevar `NULL`**:
  se propaga en la multiplicación y después `SUM` lo ignora en silencio. Hay que
  elegir entre rechazar la fila, mandarla a cuarentena o convertirla a 0.
- **`RunId` en `etl.LoadBatch`: `NULL`-able o `NOT NULL` con backfill** de las
  filas históricas, que corrieron sin orquestador.
- **Qué `Status` lleva una corrida donde una tabla anduvo y otra falló.** El
  `CHECK` actual de `LoadBatch` admite `Running` / `Succeeded` / `Failed`, que
  describe bien una carga de tabla; una corrida puede terminar parcial.

`docs/libro/` (módulos 7 y 8) desarrolla estos temas como material de referencia.
**No son decisiones del proyecto**: son las opciones y sus criterios.

## Estructura del repositorio

```
restore/
└── 01_restore_wideworldimporters.sql   restore del .bak (Windows y Docker Linux)
exploration/
├── 01_kit_exploracion.sql              14 consultas de exploración y perfilado
└── 02_alcance_y_exclusiones.md         qué tablas entran, cuáles no y por qué
staging/
├── 01_database.sql                     CREATE DATABASE + recovery model
├── 02_schemas.sql                      CREATE SCHEMA Sales, etl
├── 03_tables.sql                       Sales.Orders, Sales.OrderLines,
│                                       etl.ValidationLog, etl.LoadBatch
├── 04_usp_ValidateSalesOrders.sql      validaciones de calidad de datos
└── 05_usp_LoadSalesOrders.sql          extracción desde producción
automation/
├── 01_job_load_sales_orders.sql        SQL Server Agent Job (diario 02:00 hora local)
├── 02_database_mail.template.sql       plantilla SIN credenciales — se versiona
└── 03_job_notifications.sql            operador + notificación por correo
tests/
└── negative_tests.sql                  pruebas del camino de error
docs/libro/                             guía de estudio del proyecto (fuentes .md)
```

`automation/02_database_mail.local.sql` **no está en el repo** y no debe estarlo:
contiene una App Password. Se genera copiando la plantilla. Ver *Configuración local*.

Los números indican **orden de ejecución**: `02_schemas` no puede correr antes que
`01_database`. Los scripts de tablas se ejecutan una sola vez; los de procedures usan
`CREATE OR ALTER` y son re-ejecutables.

## Requisito previo: la base de origen

`WideWorldImporters-Full.bak` (121 MB) **no está en el repo** — es un archivo
binario de terceros. Se descarga del repo oficial de Microsoft:

<https://github.com/Microsoft/sql-server-samples/releases/tag/wide-world-importers-v1.0>

Un repo versiona lo que uno construyó, no lo que descargó. Es el mismo criterio
por el que se ignora `node_modules` pero se versiona `package.json`: lo que viaja
es la declaración de la dependencia, no la dependencia.

El restore está en `restore/01_restore_wideworldimporters.sql`, con los nombres
lógicos ya verificados y variantes para Windows y para Docker Linux.

## Despliegue desde cero

```sql
-- 1. Restaurar el origen
:r restore/01_restore_wideworldimporters.sql

-- 2. Construir staging, en orden, desde la carpeta staging/
:r 01_database.sql
:r 02_schemas.sql
:r 03_tables.sql
:r 04_usp_ValidateSalesOrders.sql
:r 05_usp_LoadSalesOrders.sql
```

Los scripts de `exploration/` son opcionales: no crean nada, solo leen. Sirven
para reproducir el análisis del Paso 1 sobre una base desconocida.

Luego, para ejecutar una carga a mano:

```sql
USE WWI_Staging;
EXEC etl.usp_LoadSalesOrders;
```

Para la automatización, ejecutar `automation/01_job_load_sales_orders.sql`. **Requiere que
SQL Server Agent esté habilitado y corriendo** — es un proceso separado del motor, y si
está detenido el job nunca se ejecuta, sin error ni aviso. En Express Edition no existe.

Cómo se habilita depende de la plataforma:

**Windows** — Agent es un servicio de Windows:

```powershell
Set-Service -Name SQLSERVERAGENT -StartupType Automatic
Start-Service -Name SQLSERVERAGENT
```

**Docker / Linux (SQL Server 2022)** — no hay servicios de Windows: Agent se habilita
con `mssql-conf`, la herramienta de configuración del motor en Linux, y **requiere
reiniciar el contenedor** para tomar efecto.

```bash
docker exec -u 0 <contenedor> /opt/mssql/bin/mssql-conf set sqlagent.enabled true
```

```bash
docker restart <contenedor>
```

Alternativa sin `mssql-conf`: levantar el contenedor con `-e MSSQL_AGENT_ENABLED=true`.
Verificar que quedó activo, desde cualquiera de las dos plataformas:

```sql
SELECT servicename, status_desc, startup_type_desc
FROM sys.dm_server_services;
```

En Docker sobre Apple Silicon, la imagen de SQL Server es x86-64 y corre emulada:
conviene tener habilitada la aceleración por Rosetta en Docker Desktop. Las cargas de
este proyecto son chicas, pero los tiempos no son comparables con los de Windows nativo
— la línea base de ~130 ms medida acá no aplica en ese entorno.

Para dispararlo sin esperar al horario:

```sql
EXEC msdb.dbo.sp_start_job @job_name = N'WWI Staging - Load Sales.Orders';
```

`sp_start_job` es **asincrónico**: responde `Job started successfully` de inmediato, lo
cual sólo significa que Agent aceptó la orden — no que el job haya terminado bien.

## Observabilidad

```sql
-- ¿cómo viene funcionando el pipeline?
SELECT * FROM etl.LoadBatch ORDER BY StartedAt DESC;

-- ¿qué problemas de calidad se detectaron?
SELECT * FROM etl.ValidationLog ORDER BY LoadedAt DESC;

-- ¿cuánto tarda cada corrida?
SELECT LoadBatchId, RowsLoaded, DATEDIFF(MILLISECOND, StartedAt, EndedAt) AS DuracionMs
FROM etl.LoadBatch
WHERE Status = N'Succeeded'
ORDER BY StartedAt DESC;
```

Línea base actual: ~130 ms para 73.595 filas.

El historial del Agent Job es una fuente complementaria, no redundante: sabe si el job
llegó a ejecutarse (algo que `LoadBatch` no puede saber si el procedure nunca arrancó),
pero mide duraciones en **segundos**, así que una carga de 156 ms figura como `0`.

```sql
SELECT TOP 10
    h.run_date, h.run_time, h.run_duration,
    CASE h.run_status WHEN 0 THEN 'Fallo' WHEN 1 THEN 'Exito'
                      WHEN 2 THEN 'Reintento' WHEN 3 THEN 'Cancelado' END AS Estado,
    h.message
FROM msdb.dbo.sysjobhistory h
JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
WHERE j.name = N'WWI Staging - Load Sales.Orders'
ORDER BY h.instance_id DESC;
```

## Configuración local (no viaja por git)

`automation/02_database_mail.local.sql` contiene una App Password de Gmail y está
excluido por `.gitignore`. **Nunca entró al historial del repositorio** — verificado.

En una máquina nueva ese archivo no existe, y el síntoma es silencioso: Database Mail
no queda configurado y las alertas del job no se envían. Para recrearlo:

```bash
cp automation/02_database_mail.template.sql automation/02_database_mail.local.sql
```

Completar los marcadores `<...>` y ejecutarlo. Los patrones de `.gitignore` son
amplios a propósito (`*.local`, `*.local.*`, `*local.sql`): uno más específico ya
dejó pasar una vez un archivo con credenciales.

## Pendiente conocido

- **`Sales.OrderLines` está declarada en staging pero nada la carga.** La tabla existe
  desde `ab4a269`; faltan `usp_ValidateSalesOrderLines`, `usp_LoadSalesOrderLines`, el
  orquestador `usp_LoadSales`, la tabla `etl.LoadRun` y el `RunId` en `etl.LoadBatch`.
  Hasta que estén, el pipeline sigue cargando sólo pedidos, sin ningún importe.
- **Falta `migrations/`.** `staging/03_tables.sql` describe el estado final del esquema
  y sirve para desplegar desde cero, pero contra una base ya existente falla en la
  primera línea. Hace falta el delta —los `CREATE TABLE` nuevos y el `ALTER TABLE` de
  `LoadBatch`— en un script aparte. La tensión entre script declarativo y migración
  incremental es la misma que resuelven las migrations de Entity Framework.
- **Cuando se agregue el orquestador, hay que cambiar el job.** `automation/01_job_...`
  llama hoy a `etl.usp_LoadSalesOrders`. Si no se actualiza, la carga nocturna nunca
  ejecuta el orquestador, `OrderLines` no se carga jamás, y el job queda en verde.
- **El alerting es de job, no de datos.** `03_job_notifications.sql` configura operador y
  `@notify_level_email = 2`, así que llega correo cuando el job **falla**. Pero
  `etl.ValidationLog` sigue siendo una tabla pasiva: si la carga termina bien y las
  validaciones encuentran problemas, no avisa nadie. Falta un umbral que dispare `THROW`
  cuando el porcentaje de filas problemáticas supere cierto límite.
- Si `usp_ValidateSalesOrders` falla, `etl.LoadBatch` ya quedó marcado como `Succeeded`
  (el `UPDATE` corre antes). El estado describe la carga, no el procedure completo.

## Fuentes de referencia

- Ejercicios de SQL sobre esta base: https://github.com/MyMirelHub/AdvancedSQLExercises
- Paquete SSIS oficial "Daily ETL" de Microsoft (carpeta `wwi-ssis` en
  `microsoft/sql-server-samples`) — implementación de referencia del mismo pipeline.
