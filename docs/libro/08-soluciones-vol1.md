---

# 🔐 Soluciones — Volumen I

> **No leas esto antes de intentar los exámenes.** El valor está en el intento fallido: un error que cometiste y corregiste se retiene; una respuesta que leíste, no.

---

## Módulo 0

**1.** **c)** SQL Server ejecuta agregaciones perfectamente. El problema no es de capacidad sino de diseño: optimizar escritura y lectura analítica son objetivos opuestos.

**2.** **b)** Bronce preserva la estructura del origen. Renombrar es transformar y pertenece a plata u oro.

**3.** **b)** ELT carga crudo y transforma con el motor del destino.

**4.** **b)** Sin idempotencia, un reintento tras un fallo parcial puede duplicar datos — y peor, obliga a decidir manualmente si es seguro reintentar.

**5.** **b)** Resuelve bloqueos y competencia de recursos. Sigue sin historia, sigue con ocho joins, sigue acoplando reportes al modelo del origen, y sigue sin punto de corte consistente.

**6.** **F** — Bronce recibe el dato crudo. Limpiarlo ahí mezcla responsabilidades y elimina la posibilidad de reprocesar desde el original.

**7.** **F** — Es un acierto de diseño para OLTP: minimiza redundancia y por lo tanto inconsistencia. Solo es inadecuada para cargas analíticas.

**8.** **F** — Un pipeline que nunca falló pero suma mal es peor que uno caído: genera decisiones equivocadas con la confianza de un número en pantalla.

**9.** **F** — Las capas son un concepto lógico. Pueden convivir en bases distintas, schemas distintos, o incluso en la misma tabla con una columna de estado. Lo que define la capa es la garantía, no el envase.

**10.** **V** — Es la ventaja principal de ELT: el dato crudo persiste, así que un cambio de regla se puede aplicar retroactivamente sin volver a golpear el origen.

**11.** Los índices aceleran lecturas pero **penalizan cada escritura** (todo `INSERT` mantiene todos los índices). Y no resuelven: (1) **historia** — el OLTP sigue guardando solo el estado actual; (2) **punto de corte consistente** — dos consultas a distinta hora siguen dando resultados distintos; (3) **acoplamiento** — los reportes siguen atados al modelo del origen, que ya no se puede refactorizar; (4) **complejidad de consulta** — los ocho joins siguen ahí, solo que más rápidos. Un índice es una optimización; un warehouse es un cambio de arquitectura.

**12.** Consultado directo del OLTP, **todas las ventas históricas del cliente se reatribuyen a "Wholesaler"**, incluidas las que ocurrieron cuando era "Novelty Shop". El reporte de ventas por categoría del año pasado **cambia solo**, sin que nadie haya modificado nada.

Es un problema de negocio, no técnico, por dos motivos: (a) **invalida comparaciones históricas** — no se puede evaluar si una estrategia dirigida a Novelty Shops funcionó, porque los clientes se fueron de la categoría; (b) **destruye la confianza** — un reporte que da distinto cada vez que se corre deja de ser un reporte. La solución tiene nombre: **Slowly Changing Dimension Tipo 2** (Módulo 7).

**13.** Los tres síntomas, en orden:

1. **El dashboard se pone lento.** De 2 a 20 segundos. Se tolera.
2. **El sistema transaccional se pone lento cuando alguien abre el dashboard.** Los bloqueos de la vista frenan las escrituras. Aparecen quejas de los usuarios del POS, aparentemente sin relación.
3. **Timeouts e interbloqueos.** El dashboard falla, o peor, hace fallar transacciones de negocio.

**Lo que van a intentar primero (y no alcanza):**

- **Agregar índices** — ayuda un poco y hace más lentas las escrituras, empeorando el síntoma 2.
- **`WITH (NOLOCK)`** — quita los bloqueos y **agrega lecturas sucias**: el dashboard empieza a mostrar datos de transacciones no confirmadas, e incluso puede leer filas duplicadas o saltadas. Cambia un problema visible por uno invisible.
- **Una réplica de solo lectura** — resuelve los síntomas 2 y 3, no el 1, y no resuelve historia ni acoplamiento. Es la solución que más lejos llega antes de rendirse.
- **Más hardware** — compra tiempo proporcional al dinero.

Recién después se acepta que el problema es arquitectónico.

**14.** Un diseño posible:

```
40 POS locales → (sincronización nocturna) → Base central OLTP
                                                    │
                                              🥉 STAGING
                                    copia cruda de ventas, productos,
                                    sucursales, con LoadBatchId
                                                    │
                                              VALIDACIONES
                                    completitud, duplicados por
                                    (sucursal, ticket), volumen por sucursal
                                                    │
                                              🥈 PLATA
                                    integración: unificar códigos de producto
                                    entre sucursales, normalizar sucursal
                                                    │
                                              🥇 ORO
                                    DimFecha, DimProducto, DimSucursal
                                    FactVentas (grano: línea de ticket)
                                                    │
                                              POWER BI
```

**El problema más difícil aparece en la validación y se arrastra a plata: la sincronización parcial.** Si 38 sucursales sincronizaron y 2 no, los datos son **completos y válidos** —cada fila es perfecta— pero el total del día está mal. Ninguna validación de fila lo detecta.

La solución es una validación de **completitud por sucursal**: verificar que las 40 reportaron, y fallar (o marcar el día como parcial) si falta alguna. Es exactamente la validación de volumen del Módulo 4, aplicada por partición en lugar de al total.

---

## Módulo 1

**1.** **b)** Sin `WITH MOVE`, el restore intenta escribir en las rutas físicas de la máquina donde se hizo el backup.

**2.** **c)** `sys.partitions` con `index_id IN (0,1)` usa el conteo mantenido por el motor, sin escanear ni bloquear.

**3.** **b)** La relación existe conceptualmente pero **sin integridad garantizada**: puede contener identificadores que ya no existen.

**4.** **c)** 17 tablas con versionado de sistema.

**5.** **c)** Fan-out: cada línea se duplica una vez por cada grupo del producto, y las ventas se inflan. Sin error ni warning.

**6.** **b)** SIMPLE: el dato es reconstruible, así que pagar el costo de FULL es desperdicio.

**7.** **c)** El warning 8153 ensucia el historial del job y entrena al equipo a ignorar avisos.

**8.** **F** — Las columnas de período son ocultas: no aparecen en `SELECT *` pero sí en `INFORMATION_SCHEMA.COLUMNS`.

**9.** **F** — Una columna calculada no se puede insertar. Incluirla en el `INSERT` produce error.

**10.** **F** — Un NULL puede codificar un estado válido del proceso (`PickedByPersonID` = "no preparado aún").

**11.** **F** — Es casi exacto; puede desviarse tras cargas masivas o fallos. Para cuadrar, usá `COUNT(*)`.

**12.** **F** — Al revés: *not trusted* significa que se rehabilitó **sin verificar**, así que puede haber filas que lo violan ahora mismo.

**13.** **V** — Un hecho es un evento que referencia mucho contexto, por eso acumula FKs salientes.

**14.**

```sql
SELECT
    s.name + '.' + t.name AS Tabla,
    p.rows                AS Filas,
    (SELECT COUNT(*) FROM sys.foreign_keys fk
     WHERE fk.parent_object_id = t.object_id) AS FKsSalientes,
    (SELECT COUNT(*) FROM sys.foreign_keys fk
     WHERE fk.referenced_object_id = t.object_id) AS FKsEntrantes
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
ORDER BY FKsSalientes DESC, p.rows DESC;
```

Las candidatas a hecho quedan arriba: muchas FKs salientes **y** muchas filas. Las candidatas a dimensión son las de muchas FKs entrantes y pocas filas.

**15.**

```sql
SELECT TOP (30)
    CustomerPurchaseOrderNumber                     AS Valor,
    COUNT(*)                                        AS Veces,
    DATALENGTH(CustomerPurchaseOrderNumber)         AS Bytes,
    CASE WHEN CustomerPurchaseOrderNumber <> LTRIM(RTRIM(CustomerPurchaseOrderNumber))
         THEN 'SI' ELSE 'NO' END                    AS TieneEspacios,
    CASE WHEN UPPER(LTRIM(RTRIM(CustomerPurchaseOrderNumber)))
              IN (N'N/A', N'NA', N'NULL', N'-', N'.', N'SIN DATO', N'XXX', N'0')
         THEN 'SI' ELSE 'NO' END                    AS PareceCentinela
FROM Sales.Orders
WHERE CustomerPurchaseOrderNumber IS NOT NULL
GROUP BY CustomerPurchaseOrderNumber
ORDER BY COUNT(*) DESC;
```

Ordenar por frecuencia es la clave: un valor legítimo de orden de compra debería ser casi único. **Si uno aparece 4.000 veces, es un centinela.**

**16.** Falta `AND p.index_id IN (0,1)`. Sin ese filtro se unen también los índices no agrupados, y cada tabla aparece una vez por índice, multiplicando el conteo. Una tabla con dos índices no agrupados muestra el triple de filas.

**17.** `Application.People.SearchName` es una **columna calculada**: se deriva de otras y no se puede insertar. La consulta 4 del kit (`sys.computed_columns`) lo habría detectado antes de escribir el `INSERT`. La solución es excluirla de la lista de columnas — y si el destino la necesita, definirla también como calculada allá.

**18.** Un plan razonable:

- **Día 1 — Inventario.** Kit de exploración completo, consultas 1 a 9. *Entregable:* listado de tablas por tamaño y mapa de FKs.
- **Día 2 — Topología.** Contar FKs entrantes y salientes; identificar candidatas a hechos y dimensiones; detectar tablas puente. *Entregable:* borrador del modelo con hipótesis marcadas como tales.
- **Día 3 — Negocio.** **Reuniones, no SQL.** ¿Qué preguntas quieren responder? ¿Qué significa cada NULL? ¿Qué reportes usan hoy y cuáles no confían? *Entregable:* lista priorizada de preguntas de negocio.
- **Día 4 — Perfilado.** Solo de las tablas que sobrevivieron al día 3. Nulos, cardinalidad, rangos, centinelas. *Entregable:* informe de calidad con riesgos.
- **Día 5 — Alcance y propuesta.** Qué entra, qué queda afuera, qué riesgos hay, qué se necesita del equipo del origen. *Entregable:* propuesta de alcance con supuestos explícitos.

**Lo importante:** el día 3 es de conversación, no de SQL. Es el día que más determina el éxito del proyecto y el que más se saltea.

**19.** `Purchasing` queda afuera porque **ninguna de las cinco preguntas de negocio de la sección 1.13 lo requiere**. Todas son sobre ventas: cuánto vendimos, qué productos, qué clientes, qué vendedores, qué geografía. El ciclo de compras es un **proceso de negocio distinto**, con su propio grano, sus propias dimensiones y sus propias métricas.

Traerlo "por las dudas" agregaría 7 tablas al pipeline: 7 cargas que mantener, 7 conjuntos de validaciones, 7 puntos de falla — sin ninguna pregunta que responder.

**Cuándo revisar la decisión:** cuando aparezca una pregunta de negocio que cruce ambos procesos. El caso típico es **margen**: "¿cuál es la rentabilidad por producto?" requiere el precio de venta (`Sales`) **y** el costo de compra (`Purchasing`). Esa pregunta convierte a `Purchasing` en necesario, y además introduce un problema de modelado interesante: dos procesos de negocio con granos distintos que hay que relacionar por dimensiones conformadas.

---

## Módulo 2

**1.** **b)** Para que una fila mala no rompa la carga entera y el problema se pueda **detectar** en lugar de simplemente hacer fallar todo.

**2.** **d)** La velocidad no es el problema. Los tres reales son la falta de idempotencia, la herencia de restricciones y la pérdida del DDL versionado (que arrastra la imposibilidad de agregar auditoría).

**3.** **b)** En SQL Server `TRUNCATE` es transaccional y se revierte con `ROLLBACK`.

**4.** **b)** `NEWID()` genera el valor **antes** de escribir nada, y el identificador hace falta desde el primer instante — incluso si la carga falla antes de insertar una fila.

**5.** **b)** Solo al cruzar bases. Para objetos locales, dos partes, para que una copia de la base no escriba en la original.

**6.** **c)** `FLOAT` es punto flotante binario y no representa exactamente valores como `0.1`. El error se acumula al sumar.

**7.** **F** — Staging recibe el dato crudo; la limpieza pertenece a las capas siguientes.

**8.** **F** — Renombrar es transformar. En bronce se preservan los nombres del origen.

**9.** **F** — Staging no tiene consumidores externos. Power BI se conecta a la capa oro.

**10.** **V** — Al truncar y recargar, lo que ya no está en el origen tampoco queda en staging.

**11.** **F** — Un borrado físico no deja rastro en la fecha de modificación. Es la limitación principal del incremental.

**12.** **F** — Cada índice penaliza el `INSERT`, que es la operación dominante en staging. Solo se agregan si se mide una consulta lenta.

**13.**

```sql
CREATE TABLE Sales.OrderLines (
    OrderLineID       INT             NULL,
    OrderID           INT             NULL,
    StockItemID       INT             NULL,
    Description       NVARCHAR(200)   NULL,  -- origen NVARCHAR(100): ampliado
                                             -- por si el origen crece el largo
    PackageTypeID     INT             NULL,
    Quantity          INT             NULL,
    UnitPrice         DECIMAL(18,2)   NULL,  -- DECIMAL, nunca FLOAT: es dinero
    TaxRate           DECIMAL(18,3)   NULL,  -- igual que el origen: 3 decimales
                                             -- son significativos en impuestos
    PickedQuantity    INT             NULL,
    PickingCompletedWhen DATETIME2(7) NULL,  -- DATETIME2, no DATETIME:
                                             -- no se pierde precisión ni rango
    LastEditedBy      INT             NULL,
    LastEditedWhen    DATETIME2(7)    NULL,

    LoadBatchId       UNIQUEIDENTIFIER NOT NULL,
    LoadedAt          DATETIME2        NOT NULL
        CONSTRAINT DF_StgOrderLines_LoadedAt DEFAULT SYSUTCDATETIME()
);
```

Nota: `Sales.OrderLines` en WWI **no** tiene columnas calculadas, pero verificarlo antes de escribir el DDL es parte del método (consulta 4 del kit).

**14.**

```sql
EXEC etl.usp_LoadSalesOrders;
SELECT COUNT(*) AS Corrida1 FROM Sales.Orders;

EXEC etl.usp_LoadSalesOrders;
SELECT COUNT(*) AS Corrida2 FROM Sales.Orders;

SELECT COUNT(DISTINCT LoadBatchId) AS LotesDistintos FROM Sales.Orders;
```

**Qué demuestra cada una:**
- **Conteos iguales** → no se acumularon filas; no hay duplicación.
- **`COUNT(DISTINCT LoadBatchId) = 1`** → la tabla contiene el resultado de **una sola** carga. Prueba que el `TRUNCATE` borró de verdad las filas anteriores.

Sin la segunda, un `DELETE` mal filtrado que borrara exactamente tantas filas como inserta pasaría la primera prueba.

**15.** Usa **nombres de tres partes para el destino local**. Funciona perfectamente en `WWI_Staging`.

**El desastre silencioso:** si restaurás una copia de la base como `WWI_Staging_Dev` para probar un cambio, ejecutás el procedimiento en esa copia y **el `TRUNCATE` y el `INSERT` van a `WWI_Staging` — la base real de producción**. Tu prueba de desarrollo pisa el staging productivo. Sin error, sin advertencia, y el procedimiento reporta éxito.

Con nombres de dos partes, el destino se resuelve contra la base actual y la prueba queda contenida donde corresponde.

**16.** El horario de verano retrocedió el reloj una hora. Ese lapso de 60 minutos **ocurrió dos veces**, así que hay filas con `LoadedAt` de 01:30 pertenecientes a dos momentos distintos.

Consecuencias: (a) el reporte de "cargas de la última hora" muestra filas de ambos pasajes, que parecen duplicados; (b) `DATEDIFF(SECOND, StartedAt, EndedAt)` puede dar **negativo** si la carga cruzó el cambio de hora, porque el final tiene una marca anterior al inicio.

`SYSUTCDATETIME()` no tiene el problema: UTC es monótono y no tiene horario de verano.

**17.** Una solución completa:

**Inserciones y modificaciones** — incremental por `LastEditedWhen`, con una marca de agua persistida en `etl.LoadWatermark`. Se toma un margen de seguridad (por ejemplo, desde `watermark - 1 hora`) para cubrir transacciones largas que confirmaron después de haber sido registradas. Costo: proporcional a los cambios del día, minutos.

**Borrados** — requieren comparar el conjunto de claves, no las filas:

```sql
-- Traer SOLO las claves del origen: mucho más liviano que las filas completas
SELECT OrderID INTO #ClavesOrigen FROM WideWorldImporters.Sales.Orders;
CREATE CLUSTERED INDEX IX ON #ClavesOrigen (OrderID);

DELETE s
FROM Sales.Orders s
WHERE NOT EXISTS (SELECT 1 FROM #ClavesOrigen o WHERE o.OrderID = s.OrderID);
```

Costo: traer 200 millones de enteros (~800 MB) es mucho más barato que 200 millones de filas completas, y se puede particionar por rango de fechas para procesar solo las particiones activas.

**Qué pedirle al equipo del origen**, en orden de preferencia:

1. **Habilitar Change Data Capture** — resuelve el problema completo, incluidos borrados. Es la solución correcta.
2. **Borrado lógico** (`IsDeleted BIT`) en lugar de físico — convierte los borrados en modificaciones, que el incremental ya detecta.
3. **Una columna `rowversion`** — más confiable que un `DATETIME2` que la aplicación podría no actualizar en todos los caminos de código.

**Y el punto importante:** pedir esto no es delegar el problema. Es reconocer que **el diseño del origen determina el costo del pipeline**, y que una conversación de 20 minutos puede ahorrar semanas de ingeniería defensiva.

**18.** Ejemplo de respuesta:

> Staging va en una base separada porque escribir dentro de producción contradice el aislamiento que justifica la capa. Aunque solo leamos las tablas de negocio, **estamos escribiendo en la base**: ocupamos su espacio, entramos en su plan de backups, y —el punto crítico— compartimos su **modelo de recuperación**.
>
> Producción está en FULL, porque sus datos no existen en ningún otro lado y hay que poder recuperar a un punto en el tiempo. En FULL, cada `TRUNCATE` + `INSERT` de 73.595 filas queda registrado en el log de transacciones, que solo se trunca al hacer backup de log. Nuestro proceso diario **inflaría el log de producción** y, si los backups de log no siguen el ritmo, puede llenar el disco y detener el sistema transaccional.
>
> Con una base separada en SIMPLE, el log se recicla solo en cada checkpoint, el costo de administración es cero, y los datos derivados no contaminan la estrategia de continuidad de los datos que sí son irremplazables.

---

## Módulo 3

**1.** **b)** Sin `XACT_ABORT ON`, muchos errores abortan solo la sentencia y la ejecución continúa con la transacción abierta, permitiendo un `COMMIT` parcial.

**2.** **b)** Un `ROLLBACK` sin transacción activa lanza su propio error, que reemplaza al original y destruye el diagnóstico.

**3.** **b)** Un `%` literal en el mensaje del `THROW`. `ERROR_NUMBER()` sigue funcionando; el mensaje sale vacío.

**4.** **b)** ROLLBACK → registrar → THROW.

**5.** **c)** Una violación de constraint es determinística: los datos no cambian entre intentos.

**6.** **b)** Conserva los permisos otorgados sobre el objeto; `DROP` + `CREATE` los pierde.

**7.** **b)** Permite probar la validación sin recargar — y la recarga borraría los datos sucios de la prueba.

**8.** **F** — No atrapa errores de compilación, severidad ≥ 20, ni desconexiones del cliente.

**9.** **F** — Sin `THROW`, el `CATCH` maneja el error, el procedimiento retorna normalmente y Agent marca el job en verde.

**10.** **F** — La pisa cualquier sentencia posterior, incluido un `SELECT` o un `IF`.

**11.** **V** — La asignación ocurre donde está escrita. Si `@y` es NULL en ese punto, el resultado usa NULL.

**12.** **V** — En SQL Server `TRUNCATE` es transaccional (a diferencia de Oracle y MySQL).

**13.** **F** — `GO` es un separador de lotes del cliente. El servidor nunca lo recibe.

**14.** **V** — Un registro que quedó en `Running` indica que el proceso murió sin poder ejecutar el `CATCH`: severidad ≥ 20, desconexión, o el servicio se detuvo.

**15.**

```sql
USE WWI_Staging;
GO
CREATE OR ALTER PROCEDURE etl.usp_LoadSalesOrderLines
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @BatchId      UNIQUEIDENTIFIER = NEWID();
    DECLARE @RowsLoaded   INT;
    DECLARE @BaselineRows INT;
    DECLARE @Msg          NVARCHAR(400);

    INSERT INTO etl.LoadBatch (LoadBatchId, SchemaName, TableName, Status)
    VALUES (@BatchId, N'Sales', N'OrderLines', N'Running');

    BEGIN TRY
        BEGIN TRANSACTION;

        TRUNCATE TABLE Sales.OrderLines;

        INSERT INTO Sales.OrderLines (
            OrderLineID, OrderID, StockItemID, Description, PackageTypeID,
            Quantity, UnitPrice, TaxRate, PickedQuantity,
            PickingCompletedWhen, LastEditedBy, LastEditedWhen, LoadBatchId
        )
        SELECT
            OrderLineID, OrderID, StockItemID, Description, PackageTypeID,
            Quantity, UnitPrice, TaxRate, PickedQuantity,
            PickingCompletedWhen, LastEditedBy, LastEditedWhen, @BatchId
        FROM WideWorldImporters.Sales.OrderLines;

        SET @RowsLoaded = @@ROWCOUNT;

        SELECT @BaselineRows = AVG(RowsLoaded)
        FROM (
            SELECT TOP (5) RowsLoaded
            FROM etl.LoadBatch
            WHERE SchemaName = N'Sales' AND TableName = N'OrderLines'
              AND Status = N'Succeeded' AND RowsLoaded IS NOT NULL
            ORDER BY StartedAt DESC
        ) AS h;

        IF @BaselineRows IS NOT NULL AND @RowsLoaded < @BaselineRows * 0.8
        BEGIN
            SET @Msg = CONCAT(
                N'Caida de volumen en Sales.OrderLines: ', @RowsLoaded,
                N' filas contra linea base de ', @BaselineRows,
                N' (umbral 80%%). Carga revertida.');   -- %% escapado
            THROW 50001, @Msg, 1;
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        UPDATE etl.LoadBatch
        SET EndedAt = SYSUTCDATETIME(), Status = N'Failed',
            ErrorNumber = ERROR_NUMBER(), ErrorMessage = ERROR_MESSAGE()
        WHERE LoadBatchId = @BatchId;

        THROW;
    END CATCH

    UPDATE etl.LoadBatch
    SET EndedAt = SYSUTCDATETIME(), Status = N'Succeeded', RowsLoaded = @RowsLoaded
    WHERE LoadBatchId = @BatchId;
END;
GO
```

**16.**

```sql
SELECT
    SchemaName + N'.' + TableName                                  AS Tabla,
    COUNT(*)                                                       AS Corridas,
    SUM(CASE WHEN Status = N'Succeeded' THEN 1 ELSE 0 END)         AS Exitosas,
    SUM(CASE WHEN Status = N'Failed'    THEN 1 ELSE 0 END)         AS Fallidas,
    SUM(CASE WHEN Status = N'Running'
              AND StartedAt < DATEADD(HOUR, -2, SYSUTCDATETIME())
             THEN 1 ELSE 0 END)                                    AS Colgadas,
    AVG(CASE WHEN Status = N'Succeeded'
             THEN DATEDIFF(SECOND, StartedAt, EndedAt) END)        AS SegPromedio,
    AVG(CASE WHEN Status = N'Succeeded' THEN RowsLoaded END)       AS FilasPromedio
FROM etl.LoadBatch
WHERE StartedAt >= DATEADD(DAY, -7, SYSUTCDATETIME())
GROUP BY SchemaName, TableName
ORDER BY Fallidas DESC, Tabla;
```

Notá el `CASE` dentro de los `AVG`: promediar la duración de corridas fallidas mezclaría "tardó 3 segundos porque explotó" con "tardó 40 segundos porque funcionó".

**17.** Los cuatro errores:

1. **`DECLARE @Msg ... = CONCAT(..., @Rows, ...)`** — se evalúa al declarar, cuando `@Rows` es NULL. Además `CONCAT` trata NULL como cadena vacía, así que **no da error**: produce un mensaje incompleto en silencio. *(Y de paso, el `100%` literal blanquearía el mensaje si se usara en un `THROW`.)*
2. **El `INSERT` a `etl.LoadBatch` está DENTRO de la transacción** — un `ROLLBACK` lo borraría y las corridas fallidas no dejarían rastro. Además falta `SchemaName`, que es `NOT NULL`.
3. **`INSERT ... SELECT *` sin lista de columnas** — se rompe si el origen agrega columnas, y **carga datos en la columna equivocada** si las reordena. Tampoco permite agregar `@BatchId`.
4. **`SELECT 'Carga terminada'` pisa `@@ROWCOUNT`** — `@Rows` termina valiendo 1, no 73.595.

Y transversalmente: **no hay `TRY`/`CATCH`, no hay `SET XACT_ABORT ON`, y no hay `THROW`.** Si algo falla, la transacción queda abierta y el error se propaga sin registrarse.

**18.** Lo que pasó: se ejecutó **el cuerpo** del procedimiento en una ventana de consulta y funcionó, pero el `CREATE OR ALTER` nunca se ejecutó — o se ejecutó una versión anterior. `create_date = modify_date` confirma que **el objeto nunca se modificó desde que se creó**.

Cómo verificarlo:

```sql
SELECT OBJECT_DEFINITION(OBJECT_ID('etl.usp_Cargar')) AS CodigoDesplegado;

SELECT name, create_date, modify_date
FROM sys.procedures WHERE name = 'usp_Cargar';
```

Comparar el texto devuelto contra el archivo del repositorio. **La lección: probá ejecutando el objeto por su nombre, nunca copiando su cuerpo a una ventana de consulta.**

**19.** Reconstrucción:

1. La carga arrancó a las 2:00 y escribió el registro `Running` en `etl.LoadBatch`.
2. Durante el `TRUNCATE`/`INSERT` ocurrió un error **que `TRY/CATCH` no puede atrapar**: severidad ≥ 20, la conexión se cerró, o el servicio se detuvo. Por eso `EndedAt` quedó NULL y el estado nunca pasó a `Failed`.
3. Como el `CATCH` nunca corrió, tampoco corrió el `THROW`.
4. **Y acá está el defecto de diseño:** el paso del job debía tener `@on_fail_action = 3` ("ir al siguiente"), o el error no se propagó al nivel del paso, así que Agent registró éxito.
5. La transacción se revirtió por la desconexión, así que los datos quedaron como el día anterior — de ahí "datos de anteayer".
6. Nadie recibió alerta porque el job estaba en verde.

**El defecto de fondo:** no hay ninguna verificación que compare el estado de Agent contra `etl.LoadBatch`. La corrección es una **validación de frescura independiente** que corra por separado y alerte si el dato más reciente supera cierta antigüedad, sin importar qué diga el job.

**20.**

```sql
-- Cabecera: una fila por ejecución del pipeline completo
CREATE TABLE etl.PipelineRun (
    PipelineRunId UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    PipelineName  NVARCHAR(128)    NOT NULL,
    StartedAt     DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    EndedAt       DATETIME2        NULL,
    Status        NVARCHAR(20)     NOT NULL
        CONSTRAINT CK_PipelineRun_Status CHECK (Status IN (N'Running', N'Succeeded', N'Failed')),
    FailedStepName NVARCHAR(128)   NULL      -- qué paso lo tumbó
);

-- Detalle: una fila por paso de esa ejecución
CREATE TABLE etl.PipelineStep (
    PipelineStepId INT IDENTITY(1,1) PRIMARY KEY,
    PipelineRunId  UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FK_PipelineStep_Run REFERENCES etl.PipelineRun(PipelineRunId),
    StepOrder      INT              NOT NULL,
    StepName       NVARCHAR(128)    NOT NULL,
    StartedAt      DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    EndedAt        DATETIME2        NULL,
    Status         NVARCHAR(20)     NOT NULL
        CONSTRAINT CK_PipelineStep_Status CHECK (Status IN (N'Running', N'Succeeded', N'Failed', N'Skipped')),
    RowsAffected   INT              NULL,
    ErrorNumber    INT              NULL,
    ErrorMessage   NVARCHAR(4000)   NULL,
    CONSTRAINT UQ_PipelineStep UNIQUE (PipelineRunId, StepOrder)
);
```

**La relación:** uno a muchos. `PipelineRun` es la ejecución completa; `PipelineStep` cada etapa. `etl.LoadBatch` pasa a ser un caso particular de `PipelineStep` — de hecho, se podría reemplazar agregando `SchemaName` y `TableName` al detalle.

**Detalles de diseño:** el estado `Skipped` permite registrar pasos que no corrieron porque uno anterior falló, distinguiéndolos de los que sí se intentaron. `FailedStepName` en la cabecera evita tener que buscar en el detalle para saber dónde se cortó. Y `UQ (PipelineRunId, StepOrder)` impide registrar dos veces el mismo paso de la misma corrida.

**Consulta de duración por paso:**

```sql
SELECT StepName,
       AVG(DATEDIFF(SECOND, StartedAt, EndedAt)) AS SegPromedio,
       MAX(DATEDIFF(SECOND, StartedAt, EndedAt)) AS SegMaximo
FROM etl.PipelineStep
WHERE Status = N'Succeeded'
GROUP BY StepName, StepOrder
ORDER BY StepOrder;
```

Eso te dice **dónde está el cuello de botella** — la pregunta que se hace apenas el pipeline empieza a tardar.

---

## Módulo 4

**1.** **b)** Validación de volumen. Las validaciones de fila evalúan cada fila por separado; el problema está en el conjunto.

**2.** **c)** `COUNT` emite el warning 8153 y ensucia el historial del job en cada corrida.

**3.** **c)** Escalabilidad no es una dimensión de calidad de datos.

**4.** **b)** Descarta silenciosamente esas filas. Sin error ni warning.

**5.** **b)** Para que una corrida anómala no envenene la comparación del día siguiente.

**6.** **b)** Completitud disfrazada: el dato falta, pero no como NULL, así que las validaciones de nulos no lo ven.

**7.** **c)** Exactitud. Requiere una fuente externa de verdad.

**8.** **F** — Puede ser un estado válido del proceso.

**9.** **F** — Una validación que nunca se disparó es una hipótesis. Hay que forzar el caso.

**10.** **V** — Fuera de la transacción, detectaría el problema después de haber pisado los datos buenos.

**11.** **F** — `LEN()` ignora los espacios finales: devuelve 3. Para detectarlos usá `DATALENGTH()` o compará contra `RTRIM()`.

**12.** **F** — Inventar datos es peor que un nulo, porque el valor inventado es **indistinguible de un dato real** y contamina el análisis sin dejar rastro.

**13.** **V** — En el exacto sabés cuál conservar (son idénticos); en el lógico hay versiones distintas y hace falta una regla de negocio para elegir.

**14.** **F** — Una cuarentena que nadie revisa es un cementerio. Si no hay proceso de revisión, es mejor registrar y alertar.

**15.**

```sql
CREATE OR ALTER PROCEDURE etl.usp_ValidateSalesOrderLines
    @BatchId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @OrderIDNull INT, @StockItemNull INT, @QtyNull INT, @PriceNull INT,
            @QtyNoPositiva INT, @PrecioNegativo INT, @DescVacia INT,
            @DescConEspacios INT, @FechaIncoherente INT,
            @Duplicados INT, @Huerfanos INT;

    -- Completitud + validez + consistencia: una sola pasada
    SELECT
        @OrderIDNull      = SUM(CASE WHEN OrderID     IS NULL THEN 1 ELSE 0 END),
        @StockItemNull    = SUM(CASE WHEN StockItemID IS NULL THEN 1 ELSE 0 END),
        @QtyNull          = SUM(CASE WHEN Quantity    IS NULL THEN 1 ELSE 0 END),
        @PriceNull        = SUM(CASE WHEN UnitPrice   IS NULL THEN 1 ELSE 0 END),
        @QtyNoPositiva    = SUM(CASE WHEN Quantity  <= 0 THEN 1 ELSE 0 END),
        @PrecioNegativo   = SUM(CASE WHEN UnitPrice <  0 THEN 1 ELSE 0 END),
        @DescVacia        = SUM(CASE WHEN LTRIM(RTRIM(ISNULL(Description, N''))) = N''
                                     THEN 1 ELSE 0 END),
        @DescConEspacios  = SUM(CASE WHEN Description <> LTRIM(RTRIM(Description))
                                     THEN 1 ELSE 0 END),
        @FechaIncoherente = SUM(CASE WHEN PickedQuantity > 0
                                      AND PickingCompletedWhen IS NULL
                                     THEN 1 ELSE 0 END)
    FROM Sales.OrderLines;

    -- Unicidad: clave de negocio (OrderID, StockItemID)
    SELECT @Duplicados = COUNT(*)
    FROM (
        SELECT OrderID, StockItemID
        FROM Sales.OrderLines
        GROUP BY OrderID, StockItemID
        HAVING COUNT(*) > 1
    ) AS d;

    -- Integridad referencial
    SELECT @Huerfanos = COUNT(*)
    FROM Sales.OrderLines ol
    WHERE ol.StockItemID IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM WideWorldImporters.Warehouse.StockItems si
          WHERE si.StockItemID = ol.StockItemID
      );

    INSERT INTO etl.ValidationLog
        (LoadBatchId, SchemaName, TableName, RuleName, AffectedRowCount)
    SELECT @BatchId, N'Sales', N'OrderLines', v.RuleName, v.AffectedRowCount
    FROM (VALUES
        (N'OrderID_NULL',            @OrderIDNull),
        (N'StockItemID_NULL',        @StockItemNull),
        (N'Quantity_NULL',           @QtyNull),
        (N'UnitPrice_NULL',          @PriceNull),
        (N'Quantity_NO_POSITIVA',    @QtyNoPositiva),
        (N'UnitPrice_NEGATIVO',      @PrecioNegativo),
        (N'Description_VACIA',       @DescVacia),
        (N'Description_ESPACIOS',    @DescConEspacios),
        (N'PICKING_INCOHERENTE',     @FechaIncoherente),
        (N'CLAVE_DUPLICADA',         @Duplicados),
        (N'StockItem_HUERFANO',      @Huerfanos)
    ) AS v(RuleName, AffectedRowCount)
    WHERE v.AffectedRowCount > 0;
END;
GO
```

**Nota sobre la clave de duplicados:** se eligió `(OrderID, StockItemID)` asumiendo que el negocio no permite dos líneas del mismo producto en un pedido. **Si esa regla no está confirmada, la clave correcta es `OrderLineID`.** Es una decisión de negocio y hay que preguntarla — usar la clave equivocada genera falsos positivos permanentes que terminan haciendo que se ignore la validación.

**16.**

```sql
WITH PorDia AS (
    SELECT RuleName,
           CAST(LoadedAt AS DATE) AS Dia,
           SUM(AffectedRowCount)  AS Afectadas
    FROM etl.ValidationLog
    WHERE LoadedAt >= DATEADD(DAY, -30, SYSUTCDATETIME())
    GROUP BY RuleName, CAST(LoadedAt AS DATE)
),
Resumen AS (
    SELECT RuleName,
           COUNT(*)        AS DiasConProblema,
           AVG(Afectadas)  AS PromedioDiario,
           MAX(Afectadas)  AS Maximo,
           AVG(CASE WHEN Dia >= DATEADD(DAY, -7,  CAST(SYSUTCDATETIME() AS DATE))
                    THEN Afectadas END) AS UltimaSemana,
           AVG(CASE WHEN Dia <  DATEADD(DAY, -7,  CAST(SYSUTCDATETIME() AS DATE))
                    THEN Afectadas END) AS SemanasAnteriores
    FROM PorDia
    GROUP BY RuleName
)
SELECT *,
       CASE
           WHEN SemanasAnteriores IS NULL         THEN N'Nuevo'
           WHEN UltimaSemana IS NULL              THEN N'Resuelto'
           WHEN UltimaSemana > SemanasAnteriores * 1.2 THEN N'⬆ Empeorando'
           WHEN UltimaSemana < SemanasAnteriores * 0.8 THEN N'⬇ Mejorando'
           ELSE N'= Estable'
       END AS Tendencia
FROM Resumen
ORDER BY PromedioDiario DESC;
```

**17.** Falta **`SchemaName`**, que es `NOT NULL` en `etl.ValidationLog`. El `INSERT` va a fallar con "Cannot insert the value NULL into column 'SchemaName'".

**Por qué no se manifestó en tres meses:** está dentro de un `IF @CustomerNull > 0`. Con datos limpios, `@CustomerNull` siempre valió 0 y **la línea nunca se ejecutó**. El código se desplegó, pasó todas las revisiones, y el bug quedó dormido.

**Cuándo se va a manifestar:** el primer día en que aparezca un pedido sin cliente. Es decir, **exactamente cuando haya un problema de datos que investigar**, y la herramienta de diagnóstico va a ser la que falle. Peor: como el procedimiento lanza el error, la carga completa puede fallar por un problema de calidad que solo debía registrarse.

**Esto es el arquetipo del camino de error no probado**, y es la razón de ser de la sección 4.15.

**18.** Hay **filas de prueba en `etl.LoadBatch`** con valores altos de `RowsLoaded`.

Con 10 filas de `RowsLoaded = 500000`, el promedio de las últimas 5 exitosas da 158.876, y el umbral del 80% queda en **127.100**. La carga real trae 73.595, que es menor → `THROW 50001` → `ROLLBACK` → job fallido. **Y se repite todas las noches**, porque las filas falsas no se van solas.

Diagnóstico y corrección:

```sql
-- Ver qué hay en la línea base
SELECT TOP (10) LoadBatchId, StartedAt, RowsLoaded, Status
FROM etl.LoadBatch
WHERE SchemaName = N'Sales' AND TableName = N'Orders' AND Status = N'Succeeded'
ORDER BY StartedAt DESC;

-- Borrar las de prueba (identificadas por su valor absurdo)
DELETE FROM etl.LoadBatch WHERE RowsLoaded = 500000;
```

**La prevención:** todo script de prueba lleva su bloque de limpieza escrito **al mismo tiempo** que la prueba, y hay que verificar que corrió. Es el mismo problema del trigger de simulación de fallo del Módulo 3.

**19.** Las cinco causas, en orden de probabilidad:

1. **Fan-out por relación muchos a muchos** — el más probable, aunque acá inflaría en vez de reducir. Si el dashboard muestra **menos**, descartarlo primero:
   ```sql
   SELECT SUM(Quantity * UnitPrice) FROM stg.OrderLines;
   SELECT SUM(SalesAmount) FROM dw.FactSales;
   ```

2. **`INNER JOIN` que descarta huérfanos** — la causa más común de faltantes:
   ```sql
   SELECT COUNT(*) FROM stg.OrderLines ol
   JOIN stg.Orders o ON o.OrderID = ol.OrderID
   WHERE NOT EXISTS (SELECT 1 FROM dw.DimCustomer dc
                     WHERE dc.CustomerID = o.CustomerID);
   ```

3. **Un filtro en la carga de la fact table** — un `WHERE` heredado de una prueba, o una condición de fecha que excluye datos:
   ```sql
   SELECT MIN(OrderDate), MAX(OrderDate), COUNT(*) FROM dw.FactSales;
   -- comparar contra el mismo rango en staging
   ```

4. **Filtro en Power Query o en el modelo de Power BI** — filas filtradas después del warehouse. Revisar los pasos aplicados de la consulta y los filtros a nivel de reporte/página.

5. **Diferencia de definición de la métrica** — el sistema transaccional puede incluir impuestos, envío o notas de crédito que el warehouse no. **No es un bug: es un desacuerdo de definición**, y es sorprendentemente común. Se resuelve con un glosario de métricas, no con SQL.

**El orden importa:** las causas 1 a 3 se descartan con consultas en minutos. La 5 requiere una conversación. Empezar por la 5 hace perder tiempo; terminar sin considerarla hace buscar un bug que no existe.

**20.**

| Campo | Validación | Severidad | Acción |
|---|---|---|---|
| **Monto** | NULL, ≤ 0, atípicos > 3σ | 🔴 Crítica (NULL/≤0) · 🟡 Advertencia (atípico) | NULL o ≤ 0 → **cuarentena**: sin monto el registro no aporta a ninguna métrica y contaminaría los totales. Atípico → cargar y registrar; puede ser legítimo. |
| **Referencia externa** | NULL | 🟢 Informativa | **Cargar normalmente.** Puede faltar legítimamente. Registrar el porcentaje para detectar si sube (eso sí sería una señal). |
| **País** | Formato inconsistente | 🟡 Advertencia | **Corregir de forma determinística**: `LTRIM(RTRIM(UPPER(...)))` + tabla de mapeo `'USA'/'U.S.A.'/'ESTADOS UNIDOS' → 'US'`. Lo que **no** mapee → cargar con `'DESCONOCIDO'` y registrar el valor original. **Nunca inventar** un país por defecto. |
| **Fecha futura (2%)** | `Fecha > hoy` | 🟡 Advertencia con **umbral** | **Cargar y registrar.** Es un problema conocido con fecha de corrección. Configurar el umbral en 3%: si supera eso, escalar a error, porque significa que el problema empeoró. |

**Justificación con el marco de 4.12:**

1. **¿Es crítico para la métrica principal?** El monto sí (aísla). El resto no.
2. **¿Se corrige de forma determinística?** El país sí, con una tabla de mapeo explícita y auditable. La fecha no —no se puede saber cuál era la correcta— así que se registra.
3. **¿Cuántos afecta?** El 2% de fechas futuras es tolerable y conocido. **El umbral del 3% es lo importante**: convierte un problema aceptado en una alerta si se degrada.
4. **¿Alguien va a mirar la cuarentena?** Solo va a cuarentena el monto, que es crítico y por lo tanto **tiene dueño**. Todo lo demás se registra en `etl.ValidationLog` con revisión de tendencia, porque una cuarentena de referencias externas faltantes nadie la abriría.

**El punto de diseño más importante de la respuesta:** aceptar el 2% de fechas futuras **con un umbral configurado** es distinto de ignorarlo. Se documenta la excepción, se le pone fecha de vencimiento (los tres meses), y se instrumenta la detección de que empeore. Eso es gestionar deuda técnica de datos en lugar de acumularla.

---

## Módulo 5

**1.** **b)** El servicio detenido o `sp_add_jobserver` sin ejecutar. Ambos producen "nada pasa, sin error".

**2.** **b)** Agent aceptó la orden. Es asíncrono.

**3.** **c)** Violación de clave primaria: determinística.

**4.** **c)** `run_duration` es `HHMMSS`: `125` = 1 minuto 25 segundos.

**5.** **b)** Notificar éxitos genera ruido y el canal deja de leerse.

**6.** **c)** Un job con dos pasos. Garantiza el orden y propaga el fallo.

**7.** **c)** `msdb`.

**8.** **F** — No hay cola. Las ejecuciones programadas durante la parada simplemente no ocurren.

**9.** **F** — Se purga automáticamente (por defecto 1.000 filas totales, 100 por job).

**10.** **F** — Encola en Service Broker; un proceso externo envía después.

**11.** **F** — Solo indica qué job y qué paso falló.

**12.** **F** — Los jobs viven en `msdb`, no en tu base.

**13.** **F** — Agent está en hora local; `etl.*` en UTC.

**14.** **V** — Si el último paso tiene "ir al siguiente" ante fallo y no hay siguiente, el job termina reportando éxito.

**15.**

```sql
USE msdb;
GO

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'WWI Staging - Carga completa')
    EXEC msdb.dbo.sp_delete_job @job_name = N'WWI Staging - Carga completa';
GO

EXEC msdb.dbo.sp_add_job
    @job_name         = N'WWI Staging - Carga completa',
    @enabled          = 1,
    @description      = N'Carga Sales.Orders y Sales.OrderLines desde WideWorldImporters. El paso 2 solo corre si el 1 tuvo exito.',
    @owner_login_name = N'sa',
    @notify_level_email = 2,
    @notify_email_operator_name = N'Joel';

-- Paso 1: si tiene éxito va al paso 2; si falla, termina el job con fallo
EXEC msdb.dbo.sp_add_jobstep
    @job_name          = N'WWI Staging - Carga completa',
    @step_name         = N'1 - Cargar Sales.Orders',
    @step_id           = 1,
    @subsystem         = N'TSQL',
    @database_name     = N'WWI_Staging',
    @command           = N'EXEC etl.usp_LoadSalesOrders;',
    @retry_attempts    = 1,
    @retry_interval    = 5,
    @on_success_action = 3,   -- 3 = ir al siguiente paso
    @on_fail_action    = 2;   -- 2 = salir con fallo

-- Paso 2: último paso. Ambas acciones terminan el job.
EXEC msdb.dbo.sp_add_jobstep
    @job_name          = N'WWI Staging - Carga completa',
    @step_name         = N'2 - Cargar Sales.OrderLines',
    @step_id           = 2,
    @subsystem         = N'TSQL',
    @database_name     = N'WWI_Staging',
    @command           = N'EXEC etl.usp_LoadSalesOrderLines;',
    @retry_attempts    = 1,
    @retry_interval    = 5,
    @on_success_action = 1,   -- 1 = salir con éxito
    @on_fail_action    = 2;   -- 2 = salir con fallo  ⚠️ NO 3

EXEC msdb.dbo.sp_add_jobschedule
    @job_name          = N'WWI Staging - Carga completa',
    @name              = N'Diario 02:00',
    @freq_type         = 4,
    @freq_interval     = 1,
    @active_start_time = 020000;

EXEC msdb.dbo.sp_add_jobserver
    @job_name    = N'WWI Staging - Carga completa',
    @server_name = N'(local)';
GO
```

**16.**

```sql
WITH Agent AS (
    SELECT
        h.step_id,
        h.step_name,
        msdb.dbo.agent_datetime(h.run_date, h.run_time) AS HoraLocal,
        CASE h.run_status WHEN 0 THEN N'Fallo' WHEN 1 THEN N'Exito'
                          WHEN 2 THEN N'Reintento' WHEN 3 THEN N'Cancelado'
                          ELSE N'En progreso' END      AS EstadoAgent,
        h.run_duration
    FROM msdb.dbo.sysjobhistory h
    JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
    WHERE j.name = N'WWI Staging - Load Sales.Orders'
      AND h.step_id = 0                                  -- resultado del job
),
Control AS (
    SELECT
        -- UTC → local, con manejo automático de horario de verano
        CAST(StartedAt AT TIME ZONE 'UTC'
                       AT TIME ZONE 'SA Western Standard Time' AS DATETIME2) AS HoraLocal,
        Status, RowsLoaded, ErrorNumber, ErrorMessage
    FROM etl.LoadBatch
    WHERE SchemaName = N'Sales' AND TableName = N'Orders'
)
SELECT
    a.HoraLocal        AS AgentHora,
    a.EstadoAgent,
    a.run_duration     AS DuracionHHMMSS,
    c.Status           AS EstadoControl,
    c.RowsLoaded,
    c.ErrorMessage
FROM Agent a
LEFT JOIN Control c
    -- ventana de 2 minutos: las marcas de tiempo no coinciden exactamente
    ON ABS(DATEDIFF(SECOND, a.HoraLocal, c.HoraLocal)) < 120
WHERE a.HoraLocal >= DATEADD(DAY, -7, SYSDATETIME())
ORDER BY a.HoraLocal DESC;
```

**La ventana de tolerancia es necesaria:** Agent registra cuándo arrancó el paso y el procedimiento registra cuándo escribió su primera fila. Nunca son el mismo instante.

**17.** `@active_start_time` es `HHMMSS` como entero. `200` se interpreta como `000200`, es decir **00:02:00 — dos minutos después de la medianoche**. Para las 2 AM hay que escribir `020000`.

Es un error clásico porque el valor "se ve" como 2:00 si uno piensa en horas y minutos. La regla mnemotécnica: **siempre seis dígitos**.

**18.** Las dos explicaciones:

**(a) Falta el `THROW` en el `CATCH` del procedimiento.** El `CATCH` registró `Failed` en `etl.LoadBatch`, pero sin `THROW` el procedimiento retornó normalmente. Agent nunca vio un error.

**(b) El paso tiene `@on_fail_action = 3`** ("ir al siguiente paso") y es el último, así que el job terminó reportando éxito aunque el paso falló.

**Cómo distinguirlas:**

```sql
-- Si el procedimiento tiene THROW, aparece en su definición
SELECT OBJECT_DEFINITION(OBJECT_ID('etl.usp_LoadSalesOrders'));

-- Estado de cada paso individual (no solo el step_id = 0 del job)
SELECT step_id, step_name, run_status, message
FROM msdb.dbo.sysjobhistory h
JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
WHERE j.name = N'WWI Staging - Load Sales.Orders'
ORDER BY h.run_date DESC, h.run_time DESC;

-- Configuración del flujo de control del paso
SELECT step_id, step_name, on_success_action, on_fail_action, retry_attempts
FROM msdb.dbo.sysjobsteps s
JOIN msdb.dbo.sysjobs j ON j.job_id = s.job_id
WHERE j.name = N'WWI Staging - Load Sales.Orders';
```

**Si el paso individual figura como fallido pero el job como exitoso** → es la causa (b). **Si el paso también figura exitoso** → es la (a): Agent nunca supo del error.

**19.** Reconstrucción:

1. El servidor se reinició por la actualización.
2. **El servicio de SQL Server Agent estaba configurado como `Manual`** — funcionaba desde que alguien lo inició a mano meses atrás, y nadie verificó el tipo de inicio.
3. Al reiniciar, el motor arrancó (es `Automatic`) pero **Agent no**.
4. Los jobs dejaron de correr. **No hubo errores, no hubo entradas en el historial, no hubo alertas** — porque las alertas las envía Agent, que estaba apagado.
5. El dashboard siguió mostrando los últimos datos cargados, sin ninguna indicación de que estaban viejos.
6. A los tres días, alguien notó que un número no cambiaba.

**Por qué nadie se enteró:** el sistema de alertas depende del mismo componente que falló. **Es un punto único de fallo en el monitoreo**, y es un error de diseño clásico: *"¿quién vigila al vigilante?"*.

**Dos cambios que lo habrían detectado el primer día:**

1. **Validación de frescura independiente de Agent.** Una consulta que verifique `DATEDIFF(HOUR, MAX(LoadedAt), SYSUTCDATETIME()) > 26` y alerte, ejecutada por un mecanismo **distinto** — el Programador de tareas de Windows llamando a `sqlcmd`, un monitor externo, o incluso una tarjeta visible en el propio dashboard de Power BI mostrando "Datos actualizados hace X horas".

2. **Poner el servicio en `Automatic` y monitorearlo.** Lo primero es una corrección puntual; lo segundo es lo que evita la reincidencia:
   ```sql
   SELECT servicename, status_desc, startup_type_desc
   FROM sys.dm_server_services;
   ```

**Y el cambio conceptual más valioso:** mostrar la **frescura del dato en el propio dashboard**. Una etiqueta "Datos al 10/08/2026 02:00" convierte a cada usuario en un detector de datos viejos, sin ninguna infraestructura de monitoreo. Es la solución más barata y la más efectiva.

**20.** Un diseño posible:

**Qué se notifica:**

| Evento | Canal | Urgencia | Destinatario |
|---|---|---|---|
| Job fallido | Correo | Alta | Equipo de datos |
| Job fallido 2 veces seguidas | Correo + mensajería | Crítica | Equipo + responsable |
| Carga colgada (`Running` > 2 h) | Correo | Alta | Equipo de datos |
| Caída de volumen > 20% | Correo | Alta | Equipo + negocio |
| Datos con más de 26 h | Correo | Alta | Equipo de datos |
| Validaciones **empeorando** en tendencia | Resumen semanal | Baja | Equipo de datos |

**Qué NO se notifica, y por qué esto importa tanto:**

- **Ejecuciones exitosas.** 365 correos por año que dicen "todo bien" entrenan a la gente a archivar sin leer. Cuando llegue el que importa, va a estar en la misma carpeta ignorada.
- **Validaciones que encontraron algo pero dentro de lo normal.** Tres nulos de 73.595 no requieren que alguien se despierte. Van al log y aparecen en el resumen semanal **solo si la tendencia empeora**.
- **Reintentos que después tuvieron éxito.** El sistema se recuperó solo. Eso es exactamente lo que debía pasar. Notificarlo enseña que las alertas no significan nada.

**Cómo se evita la fatiga de alertas:**

1. **Cada alerta debe ser accionable.** Si al recibirla no hay nada que hacer, no debería existir. Es el criterio más importante y el más violado.
2. **Agrupar.** Un resumen semanal de tendencias, no un correo por hallazgo.
3. **Escalar por repetición**, no por gravedad inicial. Un fallo es correo; tres fallos seguidos es una llamada.
4. **Umbrales calibrados con datos reales**, no con intuición. Un umbral que genera falsos positivos se desactiva, y entonces no hay umbral.
5. **Revisar periódicamente qué alertas se ignoran.** Una alerta que nadie atendió en seis meses debe eliminarse o corregirse. Dejarla es peor que no tenerla, porque contribuye al ruido que oculta a las demás.

> **El principio de fondo:** el valor de un canal de alertas es inversamente proporcional a su volumen. Cada alerta innecesaria devalúa a todas las demás.

---

**Fin del Volumen I.**

Si respondiste correctamente el 80% de los exámenes sin consultar esta sección, estás en condiciones de defender la capa bronce completa en una entrevista técnica. Si no, volvé sobre los módulos donde fallaste **antes** de seguir: el Volumen II asume que todo esto está sólido.

