---

# Módulo 5 — SQL Server Agent

> **Paso 3 del proyecto**

## 🎯 Objetivos

Al terminar este módulo vas a poder:

- Explicar qué es SQL Server Agent y por qué es un servicio separado del motor.
- Modelar la relación Job → Step → Schedule.
- Crear un job por script, de forma reproducible y versionable.
- Elegir frecuencia y horario con criterio de negocio.
- Configurar reintentos distinguiendo errores transitorios de determinísticos.
- Diseñar el flujo de control ante fallos de un paso.
- Consultar el historial y conocer sus límites.
- Configurar Database Mail y alertas que la gente efectivamente lea.
- Aplicar un checklist de confiabilidad a cualquier job.

---

## 📖 Teoría

### 5.1 Qué es SQL Server Agent

**SQL Server Agent** es el planificador y ejecutor de tareas de SQL Server. Corre trabajos programados: cargas de ETL, backups, mantenimiento de índices, alertas.

**El dato que sorprende a mucha gente: es un servicio de Windows separado del motor.**

```
SQL Server (MSSQLSERVER)      ← el motor de base de datos
SQL Server Agent (SQLSERVERAGENT)  ← el planificador
```

Son procesos distintos. El motor puede estar corriendo perfectamente mientras Agent está detenido — y en ese caso **tus jobs no corren, sin ningún error visible en la base**.

> **⚠️ Este es el primer problema que vas a tener, garantizado.** En muchas instalaciones (especialmente Developer Edition), el servicio Agent viene con tipo de inicio **Manual** y detenido. Creás el job, esperás la hora programada, y no pasa nada. No hay error, no hay entrada en el historial. Simplemente nada.
>
> Verificalo:
>
> ```sql
> SELECT servicename, status_desc, startup_type_desc
> FROM sys.dm_server_services;
> ```
>
> Tiene que decir `Running` y `Automatic`. Si dice `Manual`, arreglalo — porque tras un reinicio del servidor, Agent no vuelve solo y tus cargas dejan de correr en silencio.
>
> Cambiar el tipo de inicio requiere **privilegios de administrador** y se hace desde SQL Server Configuration Manager, desde `services.msc`, o desde PowerShell elevado. No se puede desde una consulta.

**Ediciones:** Agent existe en Standard, Enterprise y Developer. **No existe en Express.** Si trabajás con Express, hay que orquestar con el Programador de tareas de Windows llamando a `sqlcmd`.

**Alternativas modernas que vale conocer:** Azure Data Factory, Apache Airflow, Dagster, Prefect. Todas resuelven el mismo problema con más capacidad de expresar dependencias complejas entre tareas de sistemas distintos. **Agent es el estándar cuando todo vive en SQL Server**, y los conceptos se trasladan a cualquiera de ellas.

---

### 5.2 Job → Step → Schedule

El modelo mental de Agent tiene tres piezas y una cuarta que se olvida:

```
JOB  "WWI Staging - Load Sales.Orders"
 ├── STEP 1  "Cargar Sales.Orders"   → EXEC etl.usp_LoadSalesOrders;
 ├── STEP 2  "Cargar OrderLines"     → EXEC etl.usp_LoadSalesOrderLines;
 ├── SCHEDULE  "Diario 02:00"
 └── JOBSERVER  (local)   ← ¡el que todos olvidan!
```

**Job** — la unidad de trabajo. Tiene nombre, propietario, categoría y estado.

**Step** — un paso. Un job puede tener muchos, ejecutados **en secuencia**. Cada uno tiene su tipo (T-SQL, PowerShell, CmdExec, SSIS), su base de datos de contexto, y **su propio flujo de control ante éxito o fallo**.

**Schedule** — cuándo corre. Un job puede tener varios (por ejemplo: diario a las 2 AM **y** los lunes a las 6 AM). Un schedule también puede compartirse entre jobs.

**Jobserver** — a qué servidor se asigna el job. **Sin esto, el job existe pero nunca se ejecuta.**

> **⚠️ `sp_add_jobserver` es la llamada más olvidada de SQL Server Agent.** El job aparece en SSMS, se ve perfecto, se puede editar... y jamás corre. Es un residuo del modelo de administración multiservidor (*master/target*), donde un servidor maestro distribuye jobs a servidores destino. Aunque no uses esa arquitectura, **la asignación sigue siendo obligatoria**.
>
> Si tu job no corre y ya verificaste que el servicio está arriba, esto es lo segundo que hay que revisar.

**Todo esto vive en la base `msdb`**, no en tu base de datos. Es una implicancia práctica importante: **si restaurás `WWI_Staging` en otro servidor, los jobs no van con ella.** Por eso los jobs se crean por script y el script se versiona.

---

### 5.3 Crear el job por script

**Por qué no con el asistente de SSMS**, aunque sea más cómodo:

| | Asistente | Script |
|---|---|---|
| Reproducible | ❌ | ✅ |
| Versionable en Git | ❌ | ✅ |
| Revisable por otro | ❌ | ✅ |
| Desplegable en otro servidor | ❌ | ✅ |
| Documenta las decisiones | ❌ | ✅ (comentarios) |

Es exactamente el argumento de "infraestructura como código". Un job creado a mano existe **solo** en ese servidor, y su configuración solo se puede conocer abriendo ventanas de propiedades.

> **💡 Truco práctico:** SSMS puede generar el script de un job existente (clic derecho → *Script Job as* → *CREATE To*). Sirve para aprender la sintaxis y para rescatar jobs creados a mano. Pero el script generado es verboso y sin comentarios: usalo como punto de partida, no como entregable.

---

### 5.4 Los cuatro procedimientos

```sql
USE msdb;
GO

/* Idempotencia: borrar si existe, para poder re-ejecutar el script.
   Igual que CREATE OR ALTER en los procedimientos. */
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'WWI Staging - Load Sales.Orders')
    EXEC msdb.dbo.sp_delete_job @job_name = N'WWI Staging - Load Sales.Orders';
GO

-- 1️⃣ El job
EXEC msdb.dbo.sp_add_job
    @job_name    = N'WWI Staging - Load Sales.Orders',
    @enabled     = 1,
    @description = N'Carga completa de WideWorldImporters.Sales.Orders hacia WWI_Staging.',
    @owner_login_name = N'sa';

-- 2️⃣ El paso
EXEC msdb.dbo.sp_add_jobstep
    @job_name         = N'WWI Staging - Load Sales.Orders',
    @step_name        = N'Ejecutar etl.usp_LoadSalesOrders',
    @step_id          = 1,
    @subsystem        = N'TSQL',
    @database_name    = N'WWI_Staging',
    @command          = N'EXEC etl.usp_LoadSalesOrders;',
    @retry_attempts   = 1,
    @retry_interval   = 5,      -- minutos
    @on_success_action = 1,     -- 1 = salir con éxito
    @on_fail_action    = 2;     -- 2 = salir con fallo

-- 3️⃣ El horario
EXEC msdb.dbo.sp_add_jobschedule
    @job_name           = N'WWI Staging - Load Sales.Orders',
    @name               = N'Diario 02:00',
    @freq_type          = 4,        -- 4 = diario
    @freq_interval      = 1,        -- cada 1 día
    @active_start_time  = 020000;   -- HHMMSS → 02:00:00

-- 4️⃣ La asignación al servidor  ← ¡EL QUE SE OLVIDA!
EXEC msdb.dbo.sp_add_jobserver
    @job_name    = N'WWI Staging - Load Sales.Orders',
    @server_name = N'(local)';
GO
```

**Los parámetros que importan:**

**`@owner_login_name`** — bajo qué cuenta corre. Si el propietario es miembro de `sysadmin`, el paso corre bajo la cuenta del servicio de Agent. Si no, hace falta un **proxy**. Ver 5.13.

**`@subsystem`** — el tipo de paso: `TSQL`, `PowerShell`, `CmdExec`, `SSIS`, `ANALYSISQUERY`, entre otros.

**`@database_name`** — el contexto. Esto es lo que permite escribir `EXEC etl.usp_LoadSalesOrders;` con dos partes en vez de tres.

**`@freq_type`** — los valores que vas a usar:

| Valor | Significado |
|---|---|
| 1 | Una sola vez |
| 4 | Diario |
| 8 | Semanal |
| 16 | Mensual |
| 64 | Al iniciar Agent |

**`@active_start_time`** — formato `HHMMSS` **como número entero**. `020000` = 2:00:00 AM. Es un formato incómodo y una fuente clásica de errores: `200` no es las 2 AM, es las 00:02:00.

**Para ejecución intradiaria** (por ejemplo, cada 4 horas):

```sql
@freq_type = 4,                    -- diario
@freq_subday_type = 8,             -- 8 = horas (4 = minutos)
@freq_subday_interval = 4,         -- cada 4
@active_start_time = 060000,       -- desde las 6 AM
@active_end_time = 220000          -- hasta las 10 PM
```

**Ejecutar a mano para probar:**

```sql
EXEC msdb.dbo.sp_start_job @job_name = N'WWI Staging - Load Sales.Orders';
```

> **⚠️ `sp_start_job` es asíncrono.** Devuelve "Job started successfully" de inmediato, **antes** de que el job termine. Ese mensaje **no** significa que la carga funcionó: significa que Agent aceptó la orden. Para saber el resultado hay que consultar el historial.
>
> Es un malentendido muy común: "el job dijo que salió bien" cuando en realidad dijo "arranqué".

---

### 5.5 Elegir la frecuencia

**La pregunta correcta no es técnica.** Es: *¿con qué frecuencia se toman decisiones con estos datos?*

| Frecuencia | Latencia | Costo | Cuándo tiene sentido |
|---|---|---|---|
| Cada 5 min | Muy baja | Alto | Operaciones en vivo; monitoreo |
| Cada hora | Baja | Medio | Seguimiento intradiario |
| Diaria | Hasta 24 h | Bajo | **Reportes de gestión. Lo normal.** |
| Semanal | Hasta 7 días | Muy bajo | Análisis de tendencia |

**El razonamiento correcto, y conviene poder articularlo así:**

> *"Cada 5 minutos da datos frescos pero el costo es mayor: más carga sobre el origen, más consumo del servidor y más ventanas donde algo puede fallar. Lo ideal depende de si alguien realmente toma decisiones cada 5 minutos. Para un dashboard de gestión, diario alcanza."*

**Por qué las 2 AM:**

1. **Fuera del horario laboral** — no compite con el sistema transaccional.
2. **Después del cierre del día** — los datos del día anterior están completos.
3. **Margen antes de la jornada** — si falla a las 2:00 y reintenta a las 2:05, todavía hay horas para que alguien lo arregle antes de las 8.

Ese tercer punto es el que más se olvida y el más valioso: **la hora de la carga define cuánto tiempo tenés para reaccionar.** Programarla a las 7:30 AM para "tener datos más frescos" significa que un fallo llega sin margen.

> **⚠️ Cuidado con las cargas encadenadas.** Si el job A tarda 20 minutos y el job B empieza a los 15, se pisan. Con dependencias reales, **usá pasos del mismo job** en vez de dos jobs con horarios calculados. El horario no es un mecanismo de dependencia — es una apuesta sobre la duración.

---

### 5.6 Reintentos

```sql
@retry_attempts = 1,     -- cuántas veces reintentar
@retry_interval = 5      -- minutos entre intentos
```

**El criterio, que es la pregunta de entrevista de esta sección:**

> ✅ **Reintentar lo transitorio** — desaparece solo con el tiempo.
> ❌ **No reintentar lo determinístico** — va a fallar igual las diez veces.

| Error | ¿Reintentar? | Por qué |
|---|---|---|
| Interbloqueo (1205) | ✅ | Depende de la concurrencia del momento |
| Timeout de conexión | ✅ | Red o carga momentánea |
| Origen inalcanzable | ✅ | Puede estar reiniciándose |
| Base en recuperación | ✅ | Termina sola |
| Violación de constraint | ❌ | Los datos no cambian entre intentos |
| Error de conversión | ❌ | Igual |
| Tabla no existe | ❌ | Igual |
| Permiso denegado | ❌ | Igual |

**Por qué solo 1 reintento y no 5:** con 5 intentos cada 5 minutos, un error determinístico tarda **25 minutos** en avisar. Ese retraso es puro costo. Un solo reintento cubre la mayoría de los casos transitorios sin demorar la alerta.

> **✅ La forma sofisticada, para cuando quieras ir más lejos:** reintentar **dentro del procedimiento**, inspeccionando `ERROR_NUMBER()`, y solo para números conocidos como transitorios (1205, 1204, -2, 40197...). Así el reintento es selectivo en vez de ciego. El reintento de Agent es un martillo; el del procedimiento es un bisturí.

---

### 5.7 Qué pasa cuando un Step falla

Cada paso define su comportamiento ante éxito y fallo:

```sql
@on_success_action = 1,   -- 1 = salir con éxito
                          -- 3 = ir al siguiente paso
                          -- 4 = ir al paso @on_success_step_id
@on_fail_action    = 2    -- 2 = salir con fallo
                          -- 3 = ir al siguiente paso  ⚠️
                          -- 4 = ir al paso @on_fail_step_id
```

**Esto es un grafo de flujo de control**, y da más poder del que parece.

**Patrón 1 — Secuencia estricta (el nuestro).** Si algo falla, se detiene todo.

```
Paso 1 → éxito → Paso 2 → éxito → Paso 3 → fin
   ↓ fallo          ↓ fallo          ↓ fallo
  FIN CON FALLO
```

**Patrón 2 — Continuar ante fallo.** Para pasos opcionales.

```
Paso 1 (crítico) → fallo → FIN CON FALLO
Paso 2 (opcional) → fallo → continúa al Paso 3
```

**Patrón 3 — Paso de limpieza ante fallo.**

```
Paso 1 → fallo → salta al Paso 9 (notificar/limpiar) → FIN CON FALLO
```

> **⚠️ La trampa de `@on_fail_action = 3`.** Si el último paso tiene "ir al siguiente" ante fallo y no hay siguiente, **el job termina reportando éxito aunque el paso haya fallado.** Es el mismo fallo silencioso del `THROW` faltante del Módulo 3, un nivel más arriba. Revisá siempre qué reporta el job, no solo qué hace cada paso.

---

### 5.8 Dependencias y orden de ejecución

Cuando agregues el modelo dimensional (Módulo 10), vas a tener dependencias reales:

```
Staging Orders  ─┐
                 ├─→ Dimensiones ─→ Tabla de hechos ─→ Resumen
Staging Lines   ─┘
```

**Dos opciones, y la elección importa:**

**Opción A — Un job, muchos pasos.**

✅ El orden está garantizado · Si un paso falla, se detiene la cadena · Una sola alerta · Un historial coherente
❌ Todo en el mismo hilo, sin paralelismo · Un solo horario para todo

**Opción B — Muchos jobs encadenados**, donde el último paso de cada uno inicia el siguiente con `sp_start_job`.

✅ Cada job se puede correr por separado · Permite reutilización
❌ **`sp_start_job` es asíncrono**: el job A "termina" en el instante en que dispara al B, así que el A queda en verde aunque el B falle. Se pierde el encadenamiento de fallos.

> **✅ Recomendación:** **un job con muchos pasos**, salvo que necesites correr partes por separado. La regla es: *si B no tiene sentido sin A, son pasos del mismo job.* Coordinar dos jobs por horario es una apuesta sobre cuánto tarda el primero, y esa apuesta se pierde el día que el volumen crece.

---

### 5.9 Historial de ejecuciones

```sql
SELECT
    j.name                                   AS Job,
    h.step_id,
    h.step_name,
    CASE h.run_status
        WHEN 0 THEN N'Fallo'
        WHEN 1 THEN N'Exito'
        WHEN 2 THEN N'Reintento'
        WHEN 3 THEN N'Cancelado'
        WHEN 4 THEN N'En progreso'
    END                                      AS Estado,
    msdb.dbo.agent_datetime(h.run_date, h.run_time) AS FechaHora,
    h.run_duration                           AS Duracion,   -- HHMMSS
    h.message                                AS Mensaje
FROM msdb.dbo.sysjobhistory h
JOIN msdb.dbo.sysjobs       j ON j.job_id = h.job_id
WHERE j.name = N'WWI Staging - Load Sales.Orders'
ORDER BY h.run_date DESC, h.run_time DESC;
```

**Las cinco rarezas de `sysjobhistory` que hay que conocer:**

1. **`run_date` y `run_time` son enteros**, no fechas: `20260810` y `20000` (= 02:00:00). Se combinan con `msdb.dbo.agent_datetime()`.
2. **`run_duration` es `HHMMSS` como entero**: `125` son 1 minuto 25 segundos, **no** 125 segundos. Un error de lectura muy común.
3. **`step_id = 0` es el resultado del JOB completo**; los demás son los pasos individuales.
4. **Está en hora LOCAL del servidor.** Tus tablas `etl.*` están en UTC. **La misma ejecución aparece con horas distintas en cada lugar.** No es un error: es la consecuencia esperada de la decisión del Módulo 2, y hay que documentarla para que nadie pierda una tarde investigándola.
5. **Se purga automáticamente.** Por defecto conserva 1.000 filas en total y 100 por job. **Tu historial de hace tres meses no existe.**

> **✅ Y por eso `etl.LoadBatch` no es opcional.** El historial de Agent es efímero y está en un formato incómodo. Tu tabla de control es permanente, está en UTC, tiene el conteo de filas y el mensaje de error completo, y podés consultarla con SQL normal.
>
> Cuando alguien pregunte "¿cuántas filas cargamos en marzo?", Agent no te va a poder responder. `etl.LoadBatch`, sí.

**La consulta de monitoreo que conviene tener a mano:**

```sql
-- Estado del pipeline en los últimos 7 días
SELECT
    CAST(StartedAt AS DATE)                                        AS Dia,
    COUNT(*)                                                       AS Corridas,
    SUM(CASE WHEN Status = N'Succeeded' THEN 1 ELSE 0 END)         AS Exitosas,
    SUM(CASE WHEN Status = N'Failed'    THEN 1 ELSE 0 END)         AS Fallidas,
    SUM(CASE WHEN Status = N'Running'   THEN 1 ELSE 0 END)         AS Colgadas,
    AVG(DATEDIFF(SECOND, StartedAt, EndedAt))                      AS SegPromedio,
    AVG(RowsLoaded)                                                AS FilasPromedio
FROM etl.LoadBatch
WHERE StartedAt >= DATEADD(DAY, -7, SYSUTCDATETIME())
GROUP BY CAST(StartedAt AS DATE)
ORDER BY Dia DESC;
```

---

### 5.10 Database Mail

Para que Agent avise por correo hace falta configurar **Database Mail**, que es un subsistema aparte.

**Su arquitectura, que explica su comportamiento:**

```
sp_send_dbmail  →  cola de Service Broker  →  proceso externo (DatabaseMail.exe)  →  SMTP
```

**Es asíncrono y basado en colas.** `sp_send_dbmail` **encola** el mensaje y retorna de inmediato; un proceso externo lo envía después.

**Tres consecuencias prácticas:**

1. **Que el procedimiento no dé error no significa que el correo salió.** Solo significa que se encoló.
2. **Un fallo de SMTP no rompe tu transacción.** Es una buena propiedad: el correo no debería poder tumbar la carga.
3. **Para diagnosticar hay que mirar las tablas de estado**, no la salida del procedimiento.

**La indirección cuenta/perfil, que confunde a todo el mundo:**

- **Cuenta** (*account*) — los datos técnicos: servidor SMTP, puerto, credenciales, dirección del remitente.
- **Perfil** (*profile*) — un nombre lógico que agrupa una o más cuentas.
- Los jobs y procedimientos referencian **el perfil**, nunca la cuenta.

**¿Por qué esa capa extra?** Porque un perfil puede tener **varias cuentas con prioridad**: si la primera falla, intenta con la segunda. Y porque podés cambiar de proveedor SMTP sin tocar ninguno de los procedimientos que envían correo. **Es inyección de dependencias aplicada al correo.**

**Verificar que funciona:**

```sql
-- Prueba
EXEC msdb.dbo.sp_send_dbmail
    @profile_name = N'WWI Pipeline Alerts',
    @recipients   = N'tu@correo.com',
    @subject      = N'Prueba de Database Mail',
    @body         = N'Si leés esto, funciona.';

-- Estado real de los envíos
SELECT mailitem_id, recipients, subject, sent_status, sent_date
FROM msdb.dbo.sysmail_allitems
ORDER BY mailitem_id DESC;

-- Si sent_status = 'failed', el motivo está acá
SELECT * FROM msdb.dbo.sysmail_event_log ORDER BY log_date DESC;
```

> **⚠️ Credenciales: nunca en el repositorio.**
>
> El script de configuración de Database Mail contiene una contraseña. **Ese archivo no puede ir a control de versiones**, y menos a un repositorio público.
>
> El `.gitignore` tiene que ser **deliberadamente amplio**, porque un patrón demasiado específico deja pasar variantes:
>
> ```gitignore
> *.local
> *.local.*
> *local.sql
> secrets*
> credentials*
> *.key
> *.pfx
> appsettings.Development.json
> ```
>
> **Por qué tres patrones para "local":** un patrón como `*.local.sql` **no** protege un archivo llamado `02_database_mail.local` (sin la extensión `.sql`). Ese archivo pasa el filtro, entra en un `git add .`, y la contraseña queda en el historial público. Y **borrar el archivo después no la saca del historial** — hay que reescribirlo y, en la práctica, rotar la credencial.
>
> **Regla:** en `.gitignore`, ante la duda, sé más amplio. Un falso positivo cuesta un `git add -f`; un falso negativo cuesta una credencial filtrada.
>
> **Verificación antes de cada commit:**
>
> ```bash
> git status --porcelain
> ```
>
> Y revisá que ningún archivo con credenciales aparezca como no rastreado pero visible.

**Para Gmail** hay que usar una **contraseña de aplicación**, no la del correo, y tener verificación en dos pasos activada. Puerto 587 con TLS.

---

### 5.11 Alertas

**Operador** — un destinatario con nombre.

```sql
EXEC msdb.dbo.sp_add_operator
    @name                = N'Joel',
    @enabled             = 1,
    @email_address       = N'tu@correo.com';
```

**Asociarlo al job:**

```sql
EXEC msdb.dbo.sp_update_job
    @job_name           = N'WWI Staging - Load Sales.Orders',
    @notify_level_email = 2,          -- 0=nunca 1=éxito 2=fallo 3=siempre
    @notify_email_operator_name = N'Joel';
```

> **✅ `@notify_level_email = 2` (solo fallos), y esto es una decisión de diseño, no una preferencia.**
>
> Notificar cada éxito significa 365 correos por año que dicen "todo bien". Nadie los lee. Y cuando llegue el que dice "todo mal", va a estar enterrado entre los otros o filtrado a una carpeta.
>
> **Un canal de alertas con ruido es un canal apagado.** Notificá solo lo accionable.

**La limitación que hay que aceptar conscientemente:**

El correo automático de Agent dice qué job falló y en qué paso. **No incluye el mensaje de error.** Para eso haría falta un segundo paso que consulte `etl.LoadBatch` y envíe el detalle con `sp_send_dbmail`.

**Decisión de este proyecto:** aceptamos la limitación. El detalle vive en `etl.LoadBatch` y el correo es un disparador para ir a mirar. Es una simplificación **consciente y documentada**, que es muy distinto de una omisión.

**Si quisieras cerrar esa brecha**, sería un paso adicional con `@on_fail_action` apuntando a él:

```sql
DECLARE @Err NVARCHAR(4000), @Body NVARCHAR(MAX);

SELECT TOP 1 @Err = ErrorMessage
FROM WWI_Staging.etl.LoadBatch
WHERE Status = N'Failed'
ORDER BY StartedAt DESC;

SET @Body = CONCAT(N'La carga falló con el error: ', ISNULL(@Err, N'(sin detalle)'));

EXEC msdb.dbo.sp_send_dbmail
    @profile_name = N'WWI Pipeline Alerts',
    @recipients   = N'tu@correo.com',
    @subject      = N'[FALLO] Carga de Sales.Orders',
    @body         = @Body;
```

---

### 5.12 Zonas horarias

> ➕ **Tema adicional recomendado:** manejo de zonas horarias en orquestación
> **Por qué necesito aprenderlo:** produce discrepancias que parecen bugs y no lo son, y hace perder tardes enteras.
> **En qué parte del proyecto lo utilizaremos:** al correlacionar el historial de Agent con `etl.LoadBatch`.

**El hecho:**

| Componente | Zona horaria |
|---|---|
| `etl.LoadBatch.StartedAt` | **UTC** (`SYSUTCDATETIME()`) |
| `Sales.Orders.LoadedAt` | **UTC** |
| `msdb.dbo.sysjobhistory` | **Local del servidor** |
| Horario del schedule | **Local del servidor** |

**La misma ejecución aparece con horas distintas** según dónde la mires. Con UTC-4, una carga que Agent registra a las 21:11 aparece en `etl.LoadBatch` como 01:11 del día siguiente.

**Para correlacionar:**

```sql
SELECT
    StartedAt                                            AS UTC_,
    StartedAt AT TIME ZONE 'UTC'
              AT TIME ZONE 'SA Western Standard Time'    AS HoraLocal,
    Status, RowsLoaded
FROM etl.LoadBatch
ORDER BY StartedAt DESC;
```

`AT TIME ZONE` está disponible desde SQL Server 2016 y **maneja el horario de verano automáticamente**, que es la razón principal para usarlo en vez de sumar horas a mano. Los nombres de zona se consultan en `sys.time_zone_info`.

> **✅ La regla que resuelve el problema:** *almacená siempre en UTC; convertí a local solo al mostrar.* Y **documentá esta discrepancia en el README**, porque es lo primero que va a confundir a quien mire el pipeline por primera vez — incluido vos, dentro de seis meses.

---

### 5.13 Seguridad del job

> ➕ **Tema adicional recomendado:** contexto de seguridad de Agent
> **Por qué necesito aprenderlo:** es la causa de los errores de permisos más confusos, y es un tema de entrevista para roles con responsabilidad de producción.
> **En qué parte del proyecto lo utilizaremos:** al elegir el propietario del job y al acceder a la base de origen.

**Bajo qué cuenta corre un paso — la regla:**

- Si el **propietario del job es `sysadmin`** → el paso corre bajo la **cuenta del servicio de SQL Server Agent**.
- Si **no** es `sysadmin` → corre bajo el contexto del propietario, y para subsistemas fuera de T-SQL hace falta un **proxy**.

**Qué es un proxy:** un objeto que asocia un subsistema (CmdExec, PowerShell, SSIS) con una **credencial** (una cuenta de Windows). Permite que un paso acceda a recursos externos —una carpeta de red, un servidor FTP— sin que el servicio de Agent tenga esos permisos de forma permanente.

**Implicancias prácticas para este proyecto:**

1. El paso lee de `WideWorldImporters` y escribe en `WWI_Staging`. La cuenta necesita permisos en **ambas**.
2. Con propietario `sa` funciona sin configurar nada, y **está bien para aprender**.
3. **En producción esto sería una mala práctica.** Lo correcto es una cuenta de servicio dedicada con permisos mínimos: `SELECT` sobre las tablas del origen, `db_datawriter` + `EXECUTE` sobre staging. Nada más.

> **🎓 Buena respuesta de entrevista:** *"En mi proyecto de aprendizaje usé `sa` como propietario por simplicidad. En producción usaría una cuenta de servicio dedicada con permisos mínimos: solo `SELECT` sobre las tablas del origen y `EXECUTE` sobre los procedimientos de staging, siguiendo el principio de menor privilegio."*
>
> **Reconocer la diferencia entre lo que hiciste y lo que corresponde en producción demuestra más criterio que haberlo hecho perfecto sin poder explicarlo.**

---

### 5.14 Cómo diseñar un Job confiable

**El checklist completo:**

**Antes de crearlo**
- [ ] El procedimiento funciona ejecutado a mano.
- [ ] Es idempotente (probado con dos corridas).
- [ ] El camino de error está probado (rollback forzado).
- [ ] Los errores se registran en una tabla de control.
- [ ] Relanza con `THROW` para que el fallo se propague.

**Al crearlo**
- [ ] Está en un script versionado, no hecho a mano.
- [ ] El script es idempotente (`sp_delete_job` si existe).
- [ ] Nombre descriptivo, con la base y la tabla.
- [ ] Descripción que explique qué hace.
- [ ] Contexto de base correcto.
- [ ] Reintentos configurados **para errores transitorios**.
- [ ] **`sp_add_jobserver` ejecutado.**

**Antes de confiar en él**
- [ ] El servicio Agent está `Running` y `Automatic`.
- [ ] Se probó con `sp_start_job` y se verificó el historial.
- [ ] Se probó **un fallo real** y llegó la alerta.
- [ ] El horario es correcto (¡formato `HHMMSS`!).
- [ ] Las credenciales de correo están fuera del repositorio.
- [ ] La discrepancia UTC/local está documentada.

**En operación**
- [ ] Hay una consulta de monitoreo lista para usar.
- [ ] Se detectan cargas colgadas (`Running` antiguo).
- [ ] Las alertas llegan solo ante fallos.
- [ ] Se revisan tendencias de `etl.ValidationLog`, no solo eventos.

> **⚠️ El punto más importante de toda la lista: probar un fallo real y verificar que llega la alerta.**
>
> Un sistema de alertas que nunca se probó es un sistema de alertas que no sabés si funciona — exactamente el mismo argumento del Módulo 4 aplicado a la infraestructura. La forma de probarlo es forzar un fallo: renombrar temporalmente el procedimiento, o lanzar un `THROW` deliberado, y confirmar que el correo llega a la bandeja de entrada (¡y no a spam!).

---

## 💡 Conceptos clave

- **SQL Server Agent** — planificador; **servicio separado** del motor.
- **Job / Step / Schedule / Jobserver** — las cuatro piezas. La última se olvida.
- **`msdb`** — donde viven los jobs. No viajan con tu base.
- **Error transitorio vs determinístico** — el criterio para reintentar.
- **Flujo de control de pasos** — `@on_success_action` / `@on_fail_action`.
- **Database Mail** — subsistema asíncrono basado en colas.
- **Cuenta vs perfil** — datos técnicos vs nombre lógico; indirección deliberada.
- **Operador** — destinatario con nombre.
- **Proxy y credencial** — contexto de seguridad para subsistemas externos.
- **`AT TIME ZONE`** — conversión con manejo automático de horario de verano.

---

## ⚠️ Errores comunes

**El servicio Agent detenido o en Manual.** Los jobs no corren y no hay error. Verificalo primero, siempre.

**Olvidar `sp_add_jobserver`.** El job existe y nunca corre.

**Interpretar "Job started successfully" como éxito.** Es asíncrono: significa "arrancó".

**`@active_start_time` mal formateado.** `200` es 00:02:00, no las 2 AM.

**Reintentar errores determinísticos.** Retrasa la alerta sin posibilidad de éxito.

**`@on_fail_action = 3` en el último paso.** El job reporta éxito tras un paso fallido.

**Encadenar jobs con `sp_start_job`.** Asíncrono: se pierde la propagación de fallos.

**Coordinar dependencias por horario.** Es una apuesta sobre la duración, y se pierde cuando crece el volumen.

**Notificar también los éxitos.** El canal se convierte en ruido y nadie lee la alerta importante.

**Confiar en el historial de Agent para análisis histórico.** Se purga automáticamente.

**Leer `run_duration` como segundos.** Es `HHMMSS`.

**Comparar horas de Agent con `etl.*` sin convertir.** Una está en local, la otra en UTC.

**Commitear el script de Database Mail.** Contiene la contraseña. Y borrar el archivo **no** limpia el historial de Git.

**Un `.gitignore` demasiado específico.** `*.local.sql` no protege `archivo.local`.

**No probar nunca una alerta real.** No sabés si funciona hasta que la necesitás.

---

## ✅ Buenas prácticas

1. **Todo por script, versionado, idempotente.**
2. **Un job con muchos pasos** cuando hay dependencias reales.
3. **Nombres descriptivos:** `WWI Staging - Load Sales.Orders`, no `Job1`.
4. **Descripción que explique el propósito.**
5. **Reintentos solo para lo transitorio, y pocos.**
6. **Notificar solo fallos.**
7. **Probar el fallo y verificar que la alerta llega** a la bandeja de entrada.
8. **La tabla de control es la fuente de verdad histórica**, no el historial de Agent.
9. **Credenciales fuera del repositorio**, con `.gitignore` amplio.
10. **Documentar la discrepancia UTC/local** en el README.
11. **Verificar `git status` antes de cada commit.**

---

## 🧠 Preguntas de comprensión

1. Creaste el job, esperaste la hora, y no pasó nada — sin errores ni historial. Enumerá en orden las tres cosas que revisás.
2. ¿Por qué `sp_start_job` devuelve éxito inmediato y qué implica para probar un job?
3. Un job tiene 5 reintentos cada 5 minutos y falla por una violación de constraint. ¿Cuánto tarda en avisar y qué se ganó con los reintentos?
4. Agent dice que la carga corrió a las 21:11 y `etl.LoadBatch` dice 01:11 del día siguiente. ¿Hay un bug?
5. ¿Por qué `etl.LoadBatch` no es redundante con el historial de Agent? Dá tres motivos.
6. Tu job encadena a otro con `sp_start_job` en su último paso. El segundo falla. ¿Qué reporta el primero y por qué es un problema?

---

## 📝 Ejercicios

**🟢 Básico.** Creá el job completo por script, con los cuatro procedimientos. Verificá que aparece en SSMS y que tiene servidor asignado.

**🟢 Básico.** Ejecutalo con `sp_start_job` y consultá el historial. Interpretá `run_duration` correctamente.

**🟡 Intermedio.** Configurá Database Mail, el operador y la notificación. **Forzá un fallo real** y verificá que el correo llega. Confirmá también que no cayó en spam.

**🟡 Intermedio.** Escribí la consulta de monitoreo de 5.9 y agregá una columna que indique si la última carga está retrasada respecto de lo esperado.

**🔴 Avanzado.** Agregá un segundo paso al job que, **ante fallo del primero**, consulte `etl.LoadBatch` y envíe un correo con el `ErrorMessage` completo. Configurá el flujo de control para que ese paso corra solo ante fallo y el job reporte fallo igualmente.

**🔴 Avanzado.** Implementá un **circuit breaker**: si el job falló las últimas 3 corridas, que deje de intentar y envíe una alerta distinta ("el pipeline está caído, no se seguirá reintentando"). Pensá dónde vive el estado y cómo se rearma.

**🧠 Reto.** Diseñá la orquestación completa del pipeline final: staging de 2 tablas, 4 dimensiones, 1 fact table y 2 tablas de resumen. Definí qué es un paso y qué es un job, el orden, qué pasa si falla cada uno, qué se notifica, y cómo se reprocesa un día puntual sin correr todo. Justificá cada agrupación.

---

## 🎓 Preguntas de entrevista

1. **¿Cómo automatizás un proceso de ETL en SQL Server?** — Agent: job, pasos, schedule, jobserver. Y mencionar que es un servicio separado.
2. **¿Cómo manejás dependencias entre procesos?** — Pasos del mismo job con flujo de control. Explicar por qué no por horario.
3. **¿Cuándo configurás reintentos?** — Solo transitorios, con ejemplos de ambos tipos.
4. **¿Cómo sabés que un job falló?** — Notificación + tabla de control + consulta de monitoreo. Y que probaste que la alerta funciona.
5. **¿Por qué no alcanza el historial de Agent?** — Se purga, está en local, formato incómodo, sin conteo de filas.
6. **¿Cómo manejás las credenciales de los jobs?** — Fuera del repositorio, cuenta de servicio con menor privilegio, proxies para subsistemas externos.
7. **¿Qué alternativas hay a Agent?** — ADF, Airflow, Dagster. Y cuándo conviene cada una.
8. **¿Cómo probás que tus alertas funcionan?** — Forzando un fallo real y verificando la recepción.

---

## 📌 Resumen

- Agent es un **servicio separado**: si está detenido, los jobs no corren y no hay error.
- Job → Step → Schedule → **Jobserver**. El último se olvida y sin él nada corre.
- Los jobs viven en `msdb` y **no viajan** con tu base: por eso van en scripts versionados.
- `sp_start_job` es **asíncrono**: "started" no es "succeeded".
- La frecuencia se decide por negocio; el horario define **cuánto margen tenés para reaccionar**.
- Reintentar solo lo transitorio, y pocas veces.
- Dependencias reales → pasos del mismo job. Nunca coordinar por horario.
- El historial de Agent es **efímero, local y de formato incómodo**: `etl.LoadBatch` es la fuente de verdad.
- Database Mail es **asíncrono**: encolar no es enviar.
- Notificar **solo fallos**. El ruido apaga el canal.
- Credenciales fuera del repositorio, con `.gitignore` amplio.
- **Una alerta no probada es una alerta que no sabés si funciona.**

---

## 🗂️ Flashcards

| Pregunta | Respuesta |
|---|---|
| ¿Agent es parte del motor? | No, es un servicio de Windows separado. |
| ¿Qué pasa si Agent está detenido? | Los jobs no corren y no hay error visible. |
| ¿Las cuatro piezas de un job? | Job, Step, Schedule y **Jobserver**. |
| ¿Cuál se olvida siempre? | `sp_add_jobserver`. Sin ella el job nunca corre. |
| ¿Dónde viven los jobs? | En `msdb`, no en tu base de datos. |
| ¿`sp_start_job` es síncrono? | No. Devuelve al encolar, no al terminar. |
| ¿Formato de `@active_start_time`? | `HHMMSS` como entero: `020000` = 2 AM. |
| ¿Cuándo reintentar? | Solo errores transitorios: 1205, timeouts, red. |
| ¿Formato de `run_duration`? | `HHMMSS`. `125` = 1 min 25 seg. |
| ¿Qué es `step_id = 0` en el historial? | El resultado del job completo. |
| ¿En qué zona está el historial de Agent? | Hora local del servidor; `etl.*` está en UTC. |
| ¿Se conserva el historial de Agent? | No: se purga automáticamente. |
| ¿Database Mail es síncrono? | No: encola y un proceso externo envía. |
| ¿Diferencia entre cuenta y perfil? | Cuenta = datos SMTP; perfil = nombre lógico que agrupa cuentas. |
| ¿Qué `@notify_level_email` usar? | 2, solo fallos. Notificar éxitos apaga el canal. |
| ¿El correo de Agent incluye el error? | No, solo qué job y qué paso falló. |
| ¿Bajo qué cuenta corre un paso? | La del servicio de Agent si el propietario es `sysadmin`. |
| ¿Qué es un proxy de Agent? | Asociación de un subsistema con una credencial de Windows. |
| ¿Cómo se convierte UTC a local? | `AT TIME ZONE 'UTC' AT TIME ZONE '<zona>'`. |

---

## ☑️ Checklist antes de avanzar

- [ ] El servicio Agent está `Running` y `Automatic`.
- [ ] El job está creado **por script versionado**.
- [ ] `sp_add_jobserver` fue ejecutado.
- [ ] Lo probé con `sp_start_job` y verifiqué el historial.
- [ ] Database Mail funciona (probado con `sp_send_dbmail`).
- [ ] El operador está configurado con `@notify_level_email = 2`.
- [ ] **Forcé un fallo real y el correo llegó.**
- [ ] Las credenciales están fuera del repositorio y verifiqué `git status`.
- [ ] Documenté la discrepancia UTC/local.
- [ ] Tengo la consulta de monitoreo lista.
- [ ] No hay filas de prueba en `etl.LoadBatch`.

---

## 📋 Examen del Módulo 5

### Selección múltiple

**1.** Creaste el job, llegó la hora y no pasó nada. No hay entrada en el historial. La causa más probable:
a) El procedimiento tiene un error
b) El servicio Agent está detenido, o falta `sp_add_jobserver`
c) El horario está mal
d) Falta configurar Database Mail

**2.** `sp_start_job` devuelve "Job started successfully". Eso significa:
a) El job terminó correctamente
b) Agent aceptó la orden de iniciarlo
c) El procedimiento se ejecutó sin errores
d) El correo de confirmación se envió

**3.** ¿Cuál NO se debe reintentar?
a) Interbloqueo (1205)
b) Timeout de conexión
c) Violación de clave primaria
d) Base en recuperación

**4.** `run_duration = 125` en `sysjobhistory` significa:
a) 125 segundos
b) 125 milisegundos
c) 1 minuto 25 segundos
d) 12,5 segundos

**5.** ¿Por qué `@notify_level_email = 2` y no 3?
a) Es más rápido
b) Notificar éxitos genera ruido que apaga el canal de alertas
c) El 3 no funciona
d) Consume más recursos

**6.** Dos jobs con dependencia real deberían implementarse como:
a) Dos jobs con horarios calculados
b) Dos jobs encadenados con `sp_start_job`
c) Un job con dos pasos
d) Dos jobs con el mismo schedule

**7.** Los jobs de SQL Server Agent se almacenan en:
a) La base de la aplicación   b) `master`   c) `msdb`   d) `tempdb`

### Verdadero / Falso

**8.** Si el servicio Agent está detenido, los jobs quedan encolados y corren al reiniciarlo.
**9.** El historial de Agent se conserva indefinidamente.
**10.** Database Mail envía el correo antes de que `sp_send_dbmail` retorne.
**11.** El correo automático de fallo de Agent incluye el mensaje de error del procedimiento.
**12.** Restaurar `WWI_Staging` en otro servidor lleva también sus jobs.
**13.** El historial de Agent y `etl.LoadBatch` muestran la misma hora para la misma ejecución.
**14.** `@on_fail_action = 3` en el último paso puede hacer que el job reporte éxito tras un fallo.

### SQL

**15.** Escribí el script completo e idempotente de un job con **dos** pasos (cargar Orders, cargar OrderLines) donde el segundo solo corre si el primero tuvo éxito, con reintentos y notificación configurados.

**16.** Escribí una consulta que combine el historial de Agent con `etl.LoadBatch`, convirtiendo las horas a una zona común, para mostrar qué pasó en cada ejecución de los últimos 7 días.

### Debugging

**17.** Un job está configurado con `@active_start_time = 200`. El equipo esperaba que corriera a las 2 AM y corre a otra hora. ¿A qué hora corre y por qué?

**18.** El job aparece como exitoso en SSMS pero `etl.LoadBatch` tiene un registro `Failed` de la misma corrida. Dá las **dos** explicaciones posibles y cómo distinguirlas.

### Análisis de escenario

**19.** El pipeline funcionó seis meses. Se reinició el servidor por una actualización. Tres días después, alguien nota que el dashboard está desactualizado. Reconstruí qué pasó, por qué nadie se enteró antes, y proponé **dos** cambios que lo habrían detectado el primer día.

### Diseño

**20.** Diseñá el sistema de notificaciones completo para un pipeline crítico: qué se notifica, a quién, por qué canal, con qué urgencia, y cómo evitás la fatiga de alertas. Incluí qué **no** se notifica y por qué esa decisión es tan importante como qué sí.

