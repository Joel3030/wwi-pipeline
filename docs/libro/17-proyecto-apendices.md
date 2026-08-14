---

# PROYECTO FINAL

## P.1 El entregable completo

Cuando termines, tenés que tener esto funcionando de punta a punta:

```
WideWorldImporters (OLTP, intacta)
        │
        ▼  etl.usp_LoadSalesOrders / usp_LoadSalesOrderLines
   WWI_Staging.Sales.*        🥉 BRONCE
        │
        ▼  etl.usp_Validate*
   etl.ValidationLog + etl.LoadBatch
        │
        ▼  dw.usp_LoadDim* / usp_LoadFactSales
   dw.DimDate · DimCustomer · DimProduct · DimSalesperson · FactSales   🥇 ORO
        │
        ▼  dw.usp_LoadAggregates
   dw.AggVentasMensuales
        │
        ▼  dw.usp_ValidateWarehouse   ← cuadre contra el origen
        │
        ▼  SQL Server Agent Job "WWI - Pipeline completo" (diario 02:00)
        │
        ▼  Power BI (Import) + medidas DAX
   Dashboard publicado con actualización programada
```

**El repositorio:**

```
wwi-pipeline/
├── README.md                          ← las decisiones y su porqué
├── .gitignore                         ← amplio, credenciales fuera
├── staging/
│   ├── 01_database.sql
│   ├── 02_schemas.sql
│   ├── 03_tables.sql
│   ├── 04_usp_ValidateSalesOrders.sql
│   └── 05_usp_LoadSalesOrders.sql
├── warehouse/
│   ├── 10_DimDate.sql … 20_FactSales.sql
│   └── 30_usp_LoadDimDate.sql … 50_usp_LoadWarehouse.sql
├── automation/
│   ├── 01_job_pipeline_completo.sql
│   ├── 02_database_mail.local.sql     ← GITIGNORED
│   └── 03_job_notifications.sql
├── tests/
│   └── negative_tests.sql
└── powerbi/
    ├── WWI_Ventas.pbix
    └── medidas.dax                    ← las medidas en texto, versionables
```

---

## P.2 Checklist de construcción

**Paso 1 — WideWorldImporters**
- [ ] Restaurada, `ONLINE`, con datos verificados
- [ ] Kit de exploración ejecutado y resultados guardados
- [ ] Tablas relevantes identificadas **y las excluidas, con motivo**
- [ ] Perfilado de calidad hecho

**Paso 2 — Staging + validaciones**
- [ ] `WWI_Staging` en SIMPLE, schemas `Sales` y `etl`
- [ ] Tablas con DDL explícito y versionado; columnas del origen NULL-able
- [ ] `etl.LoadBatch` sin `DEFAULT` en `EndedAt`
- [ ] `etl.ValidationLog`
- [ ] Procedimientos de carga con transacción, `TRY/CATCH`, `THROW`
- [ ] Validador separado, con agregación condicional y constructor de tabla
- [ ] Validación de volumen dentro de la transacción, con `%%` escapado
- [ ] Idempotencia probada (dos corridas, un solo `LoadBatchId`)
- [ ] Rollback probado forzando un fallo, y el andamiaje removido

**Paso 3 — Agent**
- [ ] Servicio `Running` y `Automatic`
- [ ] Job por script idempotente, con `sp_add_jobserver`
- [ ] Database Mail funcionando
- [ ] Operador con `@notify_level_email = 2`
- [ ] **Fallo real forzado y correo recibido**
- [ ] Credenciales fuera del repositorio (`git status` verificado)

**Paso 4 — Modelo dimensional**
- [ ] Grano declarado en una frase
- [ ] `DimDate` generada, con miembro desconocido
- [ ] Tres dimensiones cargadas, cada una con `-1`
- [ ] `DimProduct` con el muchos a muchos resuelto (227 filas + 1)
- [ ] `DimCustomer` con SCD Tipo 2 y detección por `EXCEPT`
- [ ] `FactSales` con 231.412 filas
- [ ] Búsqueda SCD2 **por rango de fechas**, no por `EsActual`
- [ ] **Las cinco verificaciones de cuadre pasan**
- [ ] Índices creados

**Paso 5 — Automatización completa**
- [ ] Un job con todos los pasos en orden de dependencia
- [ ] Paso final de cuadre que puede hacer fallar el job
- [ ] Recargar una dimensión SCD2 sin cambios **no** crea versiones
- [ ] Marca de estado del warehouse

**Paso 6 — Power BI**
- [ ] Import, conectado solo al schema `dw`
- [ ] Relaciones 1:* con filtro simple
- [ ] Tabla de fechas marcada; fecha/hora automática desactivada
- [ ] Meses ordenados por número
- [ ] Claves ocultas, campos renombrados y formateados
- [ ] Medidas base y KPIs escritos
- [ ] **Tarjeta de frescura del dato**
- [ ] Publicado con actualización programada **posterior al ETL**

---

## P.3 Checklist de explicación

> **Si no lo podés explicar, no lo terminaste.**

Esta es la parte que convierte un proyecto en una credencial. Grabate explicando cada punto en voz alta, en menos de dos minutos cada uno.

- [ ] **Qué construí.** El flujo completo en 60 segundos, sin jerga innecesaria.
- [ ] **Por qué existe cada capa.** Qué problema resuelve cada una y qué pasaría sin ella.
- [ ] **Por qué no consulté producción.** Las cinco razones.
- [ ] **Por qué staging permite NULL.** Validar en vez de restringir.
- [ ] **Por qué elegí full load.** Con el umbral concreto de revisión.
- [ ] **Qué es idempotencia y cómo la garantizo.** Con la prueba que la demuestra.
- [ ] **Cómo manejo los errores.** Las cuatro capas: `TRY/CATCH`, `XACT_ABORT`, tabla de control, orquestador.
- [ ] **Qué hago con un dato inválido.** El marco de las cuatro preguntas.
- [ ] **Cómo detecto que faltan datos si cada fila es válida.** Validación de volumen.
- [ ] **Cuál es el grano de mi fact table y por qué ese.** La decisión número uno.
- [ ] **Por qué claves surrogate.** Empezando por SCD Tipo 2.
- [ ] **Cómo preservo la historia.** SCD Tipo 2 y la búsqueda por fecha del evento.
- [ ] **Cómo evité el fan-out.** El muchos a muchos de producto y la opción elegida.
- [ ] **Cómo garantizo que no pierdo ventas.** Miembro desconocido y `LEFT JOIN`.
- [ ] **Cómo sé que el warehouse cuadra.** Las cinco verificaciones.
- [ ] **Dónde va cada transformación.** SQL / Power Query / DAX y la pregunta que lo decide.
- [ ] **Cómo piensa DAX.** Contexto de fila vs contexto de filtro.
- [ ] **Una decisión difícil que tomé y por qué.** ← **La más importante de todas.**

---

## P.4 Cómo presentarlo en una entrevista

**La estructura de 2 minutos:**

> *"Construí un pipeline de datos completo sobre SQL Server, desde una base OLTP hasta un dashboard en Power BI.*
>
> *El **problema**: responder preguntas de negocio sobre ventas requería ocho joins contra el sistema transaccional, y la consulta ingenua daba mal por una relación muchos a muchos entre productos y categorías.*
>
> *La **solución** tiene tres capas. Una capa de staging que aísla el origen y permite reprocesar; un conjunto de validaciones que incluye completitud, unicidad, integridad referencial **y anomalías de volumen**; y un modelo dimensional en esquema estrella con grano a nivel de línea de pedido.*
>
> *Todo está orquestado con SQL Server Agent, con una tabla de control que registra cada ejecución y alertas por correo ante fallos.*
>
> *La **decisión más difícil** fue el grano de la tabla de hechos. Elegí una fila por línea de pedido en lugar de una por pedido, porque agregar es irreversible: con el grano de pedido no podría responder cuál es el producto más vendido, que es una de las preguntas centrales del negocio.*
>
> *Y lo que más aprendí fue que **el fallo más caro de un pipeline no es que se caiga, sino que siga funcionando entregando datos incorrectos**. Por eso agregué validación de volumen contra línea base histórica: detecta que faltan datos aunque cada fila individual sea perfectamente válida."*

**Por qué funciona esa estructura:** problema → solución → **una decisión con su justificación** → una lección. La decisión y la lección son lo que distingue a alguien que construyó algo de alguien que siguió un tutorial.

**Prepará estas cinco historias concretas:**

1. **Un bug que te costó horas y cómo lo aislaste.** (El `%` en `THROW` es perfecto: síntoma engañoso, diagnóstico sistemático, causa no obvia.)
2. **Una decisión donde elegiste lo simple sobre lo sofisticado.** (Full load, categoría primaria.)
3. **Un error tuyo que corregiste.** (Staging dentro de producción, andamiaje de prueba olvidado.)
4. **Algo que descubriste explorando y cambió el diseño.** (`Sales.Orders` sin columna de monto.)
5. **Algo que dejaste sin hacer y por qué.** (El correo de Agent sin detalle del error; la capa plata.)

> **La quinta es la que más impresiona.** Reconocer una limitación aceptada conscientemente, con su justificación y su plan de mejora, demuestra criterio de ingeniería. Fingir que todo está perfecto demuestra lo contrario.

---

## P.5 Extensiones posibles

Cuando quieras seguir, en orden de valor:

1. **Comparar contra `WideWorldImportersDW`.** Instalá el warehouse oficial de Microsoft y compará su modelo con el tuyo. Las diferencias son las lecciones.
2. **Agregar el proceso de compras.** Segunda fact table, **dimensiones conformadas** (la misma `DimProduct`). Habilita el análisis de margen.
3. **Snapshot acumulativo del ciclo del pedido.** Tiempos entre etapas, cumplimiento de entrega.
4. **Carga incremental.** Marcas de agua, ventana de recarga, y probar la idempotencia.
5. **Migrar el ETL a dbt.** Es la herramienta estándar del ELT moderno y se aprende rápido teniendo esta base.
6. **Llevarlo a la nube.** Azure SQL + Azure Data Factory, o Fabric.
7. **Pruebas automatizadas** con tSQLt para los procedimientos.

---

# APÉNDICES

## A. Kit de consultas de exploración

```sql
-- 1. Inventario de tablas por tamaño
SELECT s.name AS SchemaName, t.name AS TableName, p.rows
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
ORDER BY p.rows DESC;

-- 2. Estructura de una tabla
SELECT ORDINAL_POSITION, COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH,
       NUMERIC_PRECISION, NUMERIC_SCALE, IS_NULLABLE, COLUMN_DEFAULT
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'Sales' AND TABLE_NAME = 'Orders'
ORDER BY ORDINAL_POSITION;

-- 3. Buscar una columna en toda la base
SELECT TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE COLUMN_NAME LIKE '%Customer%'
ORDER BY TABLE_SCHEMA, TABLE_NAME;

-- 4. Columnas calculadas (no se pueden insertar)
SELECT OBJECT_SCHEMA_NAME(c.object_id) + '.' + OBJECT_NAME(c.object_id) AS Tabla,
       c.name AS Columna, cc.definition AS Formula, cc.is_persisted
FROM sys.computed_columns cc
JOIN sys.columns c ON c.object_id = cc.object_id AND c.column_id = cc.column_id;

-- 5. Claves primarias (¿hay compuestas?)
SELECT s.name AS SchemaName, t.name AS TableName, i.name AS ConstraintName,
       STRING_AGG(c.name, ', ') WITHIN GROUP (ORDER BY ic.key_ordinal) AS Columnas
FROM sys.indexes i
JOIN sys.tables t ON t.object_id = i.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE i.is_primary_key = 1
GROUP BY s.name, t.name, i.name ORDER BY s.name, t.name;

-- 6. Mapa de relaciones (el diagrama, en texto)
SELECT OBJECT_SCHEMA_NAME(fk.parent_object_id) + '.' + OBJECT_NAME(fk.parent_object_id) AS TablaHija,
       cp.name AS ColumnaHija,
       OBJECT_SCHEMA_NAME(fk.referenced_object_id) + '.' + OBJECT_NAME(fk.referenced_object_id) AS TablaPadre,
       cr.name AS ColumnaPadre, fk.name AS NombreFK,
       fk.delete_referential_action_desc AS AlBorrar
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns cp ON cp.object_id = fkc.parent_object_id AND cp.column_id = fkc.parent_column_id
JOIN sys.columns cr ON cr.object_id = fkc.referenced_object_id AND cr.column_id = fkc.referenced_column_id
ORDER BY TablaHija, NombreFK;

-- 7. Claves sin FK declarada (sin integridad garantizada)
SELECT OBJECT_SCHEMA_NAME(c.object_id) + '.' + OBJECT_NAME(c.object_id) AS Tabla, c.name AS Columna
FROM sys.columns c JOIN sys.tables t ON t.object_id = c.object_id
WHERE c.name LIKE '%ID' AND c.name NOT LIKE '%RowID'
  AND NOT EXISTS (SELECT 1 FROM sys.foreign_key_columns fkc
                  WHERE fkc.parent_object_id = c.object_id AND fkc.parent_column_id = c.column_id)
  AND NOT EXISTS (SELECT 1 FROM sys.index_columns ic
                  JOIN sys.indexes i ON i.object_id = ic.object_id AND i.index_id = ic.index_id
                  WHERE ic.object_id = c.object_id AND ic.column_id = c.column_id AND i.is_primary_key = 1)
ORDER BY 1, 2;

-- 8. CHECK constraints (reglas de negocio ejecutables)
SELECT OBJECT_SCHEMA_NAME(cc.parent_object_id) + '.' + OBJECT_NAME(cc.parent_object_id) AS Tabla,
       cc.name AS Constraint_, cc.definition AS Regla
FROM sys.check_constraints cc ORDER BY 1;

-- 9. Constraints no confiables (pueden estar violados AHORA)
SELECT name, is_not_trusted, 'CHECK' AS Tipo FROM sys.check_constraints WHERE is_not_trusted = 1
UNION ALL
SELECT name, is_not_trusted, 'FOREIGN KEY' FROM sys.foreign_keys WHERE is_not_trusted = 1;

-- 10. Perfil de completitud (adaptar columnas)
SELECT COUNT(*) AS Total,
       SUM(CASE WHEN CustomerID IS NULL THEN 1 ELSE 0 END) AS CustomerID_Null
FROM Sales.Orders;

-- 11. Cardinalidad y rango de fechas
SELECT COUNT(*) AS Filas, COUNT(DISTINCT CustomerID) AS Clientes,
       MIN(OrderDate) AS Desde, MAX(OrderDate) AS Hasta,
       DATEDIFF(DAY, MIN(OrderDate), MAX(OrderDate)) AS Dias
FROM Sales.Orders;

-- 12. Distribución de valores (detectar centinelas)
SELECT TOP (20) IsUndersupplyBackordered, COUNT(*) AS Cantidad,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS Pct
FROM Sales.Orders GROUP BY IsUndersupplyBackordered ORDER BY Cantidad DESC;

-- 13. Tablas puente de muchos a muchos (trampas de fan-out)
SELECT OBJECT_SCHEMA_NAME(t.object_id) + '.' + OBJECT_NAME(t.object_id) AS TablaPuente
FROM sys.tables t
WHERE EXISTS (SELECT 1 FROM sys.indexes i WHERE i.object_id = t.object_id AND i.is_primary_key = 1)
  AND (SELECT COUNT(*) FROM sys.foreign_keys fk WHERE fk.parent_object_id = t.object_id) >= 2
ORDER BY 1;

-- 14. Tablas temporales de sistema (historial gratis para SCD)
SELECT s.name + '.' + t.name AS Tabla,
       OBJECT_SCHEMA_NAME(t.history_table_id) + '.' + OBJECT_NAME(t.history_table_id) AS TablaHistorica
FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE t.temporal_type = 2 ORDER BY 1;
```

---

## B. Glosario español–inglés

| Español | Inglés | Qué es |
|---|---|---|
| Almacén de datos | Data Warehouse | Repositorio analítico |
| Capa de aterrizaje | Staging / Landing zone | Copia cruda del origen |
| Carga completa | Full load | Recargar todo |
| Carga incremental | Incremental / Delta load | Solo lo que cambió |
| Clave de negocio | Business / Natural key | Identificador del origen |
| Clave surrogate | Surrogate key | Clave artificial del warehouse |
| Cuadre | Reconciliation | Verificar totales contra el origen |
| Dimensión degenerada | Degenerate dimension | Identificador en la fact table |
| Dimensiones conformadas | Conformed dimensions | Compartidas entre procesos |
| Esquema estrella | Star schema | Hechos rodeados de dimensiones |
| Frescura | Freshness | Antigüedad del dato más reciente |
| Grano | Grain | Qué representa una fila de hechos |
| Linaje | Lineage | De dónde vino cada dato |
| Marca de agua | Watermark | Hasta dónde se procesó |
| Miembro desconocido | Unknown member | Fila `-1` para huérfanos |
| Multiplicación de filas | Fan-out / Fan trap | Duplicación por muchos a muchos |
| Recarga histórica | Backfill | Reprocesar el pasado |
| Tabla de hechos | Fact table | Los eventos medidos |
| Tabla puente | Bridge table | Resuelve muchos a muchos |
| Valor centinela | Sentinel value | "Sin dato" sin ser NULL |

---

## C. Errores reales de este proyecto y su diagnóstico

| Error | Síntoma | Causa | Lección |
|---|---|---|---|
| `%` literal en `THROW` | `ERROR_MESSAGE()` vacío, `ERROR_NUMBER()` correcto | `%` es carácter de formato heredado | Escapar con `%%` o `REPLACE` |
| `SchemaName` faltante en el `INSERT` de validación | Nada, durante meses | La rama solo corre si hay hallazgos | **Todo camino de error no ejecutado está sin probar** |
| Andamiaje de prueba olvidado | El job falla todas las noches | 10 filas con `RowsLoaded = 500000` envenenaron la línea base | Limpieza escrita junto con la prueba |
| Staging dentro de producción | Funcionaba | Se contradice el aislamiento; infla el log de producción | Corregir temprano cuesta poco |
| Probar el texto en vez del objeto | La prueba pasa, producción falla | Se ejecutó el cuerpo en una ventana de consulta | `OBJECT_DEFINITION` después de desplegar |
| `create_date = modify_date` | El código desplegado no es el editado | El `CREATE OR ALTER` nunca corrió | Verificar contra el objeto, no el editor |
| Falta `GO` entre dos `CREATE PROCEDURE` | Error de sintaxis confuso | Deben ser la primera sentencia del lote | Numerar y separar por lotes |
| `DEFAULT` en `EndedAt` | No se detectan cargas colgadas | El NULL era la señal | El diseño de una columna incluye su ausencia |
| Asignación en el `DECLARE` | Mensaje incompleto, sin error | `CONCAT` trata NULL como vacío | Declarar arriba, asignar donde hay datos |
| `.gitignore` demasiado específico | Casi se commitea una contraseña | `*.local.sql` no cubre `archivo.local` | Ante la duda, patrón más amplio |
| Servicio Agent en Manual | Los jobs dejan de correr tras un reinicio | Sin errores ni historial | Frescura monitoreada **fuera** de Agent |

---

## D. Plantillas reutilizables

**Procedimiento de carga (esqueleto):**

```sql
CREATE OR ALTER PROCEDURE etl.usp_LoadXXX
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @BatchId UNIQUEIDENTIFIER = NEWID();
    DECLARE @RowsLoaded INT, @BaselineRows INT, @Msg NVARCHAR(400);

    INSERT INTO etl.LoadBatch (LoadBatchId, SchemaName, TableName, Status)
    VALUES (@BatchId, N'<schema>', N'<tabla>', N'Running');

    BEGIN TRY
        BEGIN TRANSACTION;
            TRUNCATE TABLE <destino>;
            INSERT INTO <destino> (<cols>, LoadBatchId)
            SELECT <cols>, @BatchId FROM <origen>;
            SET @RowsLoaded = @@ROWCOUNT;
            -- validación de volumen acá
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

    EXEC etl.usp_ValidateXXX @BatchId;
END;
GO
```

**Prueba negativa (esqueleto):**

```sql
-- ══ PREPARAR ══
<crear la condición de fallo>

-- ══ EJECUTAR ══
BEGIN TRY EXEC <procedimiento>; END TRY
BEGIN CATCH SELECT ERROR_NUMBER(), ERROR_MESSAGE(); END CATCH

-- ══ VERIFICAR ══
<consultas que prueban el comportamiento esperado>

-- ══ LIMPIAR ══  ⚠️ OBLIGATORIO — escribir junto con la prueba
<deshacer todo>
```

---

## E. Lecturas recomendadas

**Libros**
- Ralph Kimball, *The Data Warehouse Toolkit* — la referencia canónica de modelado dimensional.
- Marco Russo & Alberto Ferrari, *The Definitive Guide to DAX* — el libro de DAX.
- Martin Kleppmann, *Designing Data-Intensive Applications* — fundamentos de sistemas de datos.

**Sitios**
- `sqlbi.com` — Russo y Ferrari. El mejor material de DAX y modelado en Power BI, gratis.
- `kimballgroup.com/data-warehouse-business-intelligence-resources/kimball-techniques/` — las 34 técnicas de Kimball, resumidas.
- `learn.microsoft.com/power-bi/guidance/` — guía oficial de buenas prácticas.
- `brentozar.com` — rendimiento de SQL Server.

**Para practicar**
- `github.com/microsoft/sql-server-samples` — incluye el paquete SSIS "Daily ETL" oficial de WWI: una implementación de referencia del mismo pipeline. **Compará tu diseño con el de ellos cuando termines.**
- `WideWorldImportersDW` — el warehouse oficial. Tu examen corregido.

---

# Palabras finales

Empezaste este libro con una pregunta de negocio que requería ocho joins y daba mal.

Si llegaste hasta acá con el proyecto construido, ahora tenés un sistema que la responde en una consulta de tres joins, con datos validados, cargados automáticamente todas las noches, con historial de cada ejecución, alertas ante fallos, y un modelo que cualquier analista puede usar sin conocer el esquema del origen.

Pero lo que vale no es el sistema.

Lo que vale es que podés explicar **por qué cada pieza está donde está**. Por qué staging permite NULL. Por qué el grano es una fila por línea de pedido. Por qué las claves son surrogate. Por qué las alertas solo avisan de los fallos. Por qué un `%` puede borrar un mensaje de error entero.

Esa capacidad —razonar decisiones técnicas en voz alta, con sus alternativas y sus compromisos— es lo que separa a alguien que hace tareas de alguien en quien se confía para diseñar.

Y si tuviera que dejarte una sola frase de todo el libro, sería esta:

> **El fallo más caro de un sistema de datos no es que se caiga. Es que siga funcionando mientras entrega números incorrectos.**

Todo lo demás —las validaciones, las transacciones, el cuadre, las pruebas del camino negativo, la tarjeta de frescura en el dashboard— son consecuencias de tomarse esa frase en serio.

Ahora andá a construirlo.

