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

## Estructura del repositorio

```
staging/
├── 01_database.sql                  CREATE DATABASE + recovery model
├── 02_schemas.sql                   CREATE SCHEMA Sales, etl
├── 03_tables.sql                    Sales.Orders, etl.ValidationLog, etl.LoadBatch
├── 04_usp_ValidateSalesOrders.sql   validaciones de calidad de datos
└── 05_usp_LoadSalesOrders.sql       extracción desde producción
automation/
└── 01_job_load_sales_orders.sql     SQL Server Agent Job (diario 02:00 hora local)
tests/
└── negative_tests.sql               pruebas del camino de error
```

Los números indican **orden de ejecución**: `02_schemas` no puede correr antes que
`01_database`. Los scripts de tablas se ejecutan una sola vez; los de procedures usan
`CREATE OR ALTER` y son re-ejecutables.

## Despliegue desde cero

```sql
-- en orden, desde la carpeta staging/
:r 01_database.sql
:r 02_schemas.sql
:r 03_tables.sql
:r 04_usp_ValidateSalesOrders.sql
:r 05_usp_LoadSalesOrders.sql
```

Luego, para ejecutar una carga a mano:

```sql
USE WWI_Staging;
EXEC etl.usp_LoadSalesOrders;
```

Para la automatización, ejecutar `automation/01_job_load_sales_orders.sql`. **Requiere que
el servicio SQL Server Agent esté corriendo y en modo de inicio `Automatic`** — es un
servicio de Windows separado del motor, y si está detenido el job nunca se ejecuta, sin
error ni aviso. En Express Edition no existe: habría que orquestar con el Programador de
tareas de Windows.

```powershell
Set-Service -Name SQLSERVERAGENT -StartupType Automatic
Start-Service -Name SQLSERVERAGENT
```

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

## Pendiente conocido

- Solo se stagea `Sales.Orders`. Para un dashboard de ventas falta `Sales.OrderLines`:
  **`Sales.Orders` no tiene ninguna columna de monto** — la facturación se calcula como
  `Quantity` × `UnitPrice` desde `OrderLines` (231.412 filas).
- No hay alerting. `etl.ValidationLog` es una tabla pasiva: solo sirve si alguien la
  consulta. El paso natural es SQL Server Agent + Database Mail, con un umbral que dispare
  `THROW` cuando el porcentaje de filas problemáticas supere cierto límite.
- Si `usp_ValidateSalesOrders` falla, `etl.LoadBatch` ya quedó marcado como `Succeeded`
  (el `UPDATE` corre antes). El estado describe la carga, no el procedure completo.

## Fuentes de referencia

- Ejercicios de SQL sobre esta base: https://github.com/MyMirelHub/AdvancedSQLExercises
- Paquete SSIS oficial "Daily ETL" de Microsoft (carpeta `wwi-ssis` en
  `microsoft/sql-server-samples`) — implementación de referencia del mismo pipeline.
