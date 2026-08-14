---

# Módulo 1 — WideWorldImporters y el arte de explorar una base desconocida

> **Paso 1 del proyecto**

## 🎯 Objetivos

Al terminar este módulo vas a poder:

- Restaurar una base desde un `.bak` y explicar cada cláusula del `RESTORE`.
- Elegir el modelo de recuperación correcto y justificarlo.
- Describir la organización de WideWorldImporters y la intención de diseño detrás de sus schemas.
- **Explorar cualquier base de datos que nunca viste**, usando solo el catálogo del sistema.
- Descubrir tablas, columnas, tipos, claves, relaciones y constraints sin documentación.
- Perfilar la calidad de los datos antes de escribir una línea de ETL.
- Detectar relaciones muchos a muchos y explicar por qué son una trampa para la analítica.
- Decidir, con criterio, qué tablas necesita un proyecto y cuáles no.

---

## 📖 Teoría

### 1.1 Qué es WideWorldImporters

**WideWorldImporters (WWI)** es la base de datos de ejemplo oficial de Microsoft para SQL Server 2016 en adelante. Reemplazó a las viejas `AdventureWorks` y `Northwind`.

Modela una empresa ficticia importadora y distribuidora mayorista de artículos de novedad: compra a proveedores, almacena, vende a clientes minoristas y despacha. Nada exótico — y eso es justamente el punto.

**Por qué es un buen material de aprendizaje:**

1. **Es realista en tamaño.** 73.595 pedidos y 231.412 líneas de pedido: suficiente para que los problemas de rendimiento sean reales, poco para que quepa en cualquier máquina.
2. **Es realista en complejidad.** 48 tablas en 4 schemas, con relaciones muchos a muchos, jerarquías geográficas y datos sucios a propósito.
3. **Usa características modernas** que vas a encontrar en producción: tablas temporales con versionado de sistema, columnas calculadas, tipos espaciales, `NVARCHAR(MAX)`, y hasta un filegroup optimizado en memoria.
4. **Tiene una versión DW oficial** (`WideWorldImportersDW`) que podés comparar contra tu diseño al final. Es un examen corregido esperándote.

> **⚠️ Importante:** no instales `WideWorldImportersDW` al empezar. El valor del proyecto está en **llegar** al modelo dimensional razonando, no en copiarlo. Guardalo para el final y compará: las diferencias que encuentres son las lecciones más caras de todo el libro.

**Qué tipo de base es:** **OLTP**, normalizada, con integridad referencial completa. Es exactamente el tipo de base contra el que vas a trabajar en el mundo real.

---

### 1.2 Restaurar la base

Un archivo `.bak` es un backup nativo de SQL Server: contiene los datos, la estructura y **las rutas físicas originales** de la máquina donde se hizo. Esas rutas casi nunca existen en tu máquina, y ahí está el primer obstáculo.

**Paso 1 — Averiguar qué contiene el backup.**

```sql
RESTORE FILELISTONLY
FROM DISK = N'C:\ruta\WideWorldImporters-Full.bak';
```

Esto no restaura nada: **lee el encabezado** y lista los archivos lógicos que hay adentro. En WWI vas a ver cuatro:

| LogicalName | Type | Qué es |
|---|---|---|
| `WWI_Primary` | D | Archivo de datos principal (`.mdf`) |
| `WWI_UserData` | D | Datos de usuario (`.ndf`) |
| `WWI_Log` | L | Log de transacciones (`.ldf`) |
| `WWI_InMemory_Data_1` | S | **Filegroup optimizado en memoria** |

Esos `LogicalName` son los que necesitás para el siguiente paso. El tipo `S` es una particularidad de WWI que vale conocer: es un filegroup de **In-Memory OLTP** (nombre en clave *Hekaton*), una característica que permite tablas residentes en memoria con estructuras sin bloqueos. WWI la usa para `Warehouse.VehicleTemperatures`. Para nuestro proyecto es irrelevante, pero explica por qué el `RESTORE` tiene un archivo raro.

**Paso 2 — Averiguar dónde poner los archivos.**

```sql
SELECT SERVERPROPERTY('InstanceDefaultDataPath') AS DataPath,
       SERVERPROPERTY('InstanceDefaultLogPath')  AS LogPath;
```

**Paso 3 — Restaurar redirigiendo las rutas.**

```sql
RESTORE DATABASE WideWorldImporters
FROM DISK = N'C:\ruta\WideWorldImporters-Full.bak'
WITH
    MOVE N'WWI_Primary'          TO N'C:\...\DATA\WideWorldImporters.mdf',
    MOVE N'WWI_UserData'         TO N'C:\...\DATA\WideWorldImporters_UserData.ndf',
    MOVE N'WWI_Log'              TO N'C:\...\DATA\WideWorldImporters.ldf',
    MOVE N'WWI_InMemory_Data_1'  TO N'C:\...\DATA\WideWorldImporters_InMemory_Data_1',
    RECOVERY,
    STATS = 10;
```

---

### 1.3 Qué significa cada cláusula

**`MOVE 'nombre_lógico' TO 'ruta_física'`** — Redirige cada archivo a una ruta que sí existe en tu máquina. **Sin esto el restore falla** con "directory lookup failed", porque intenta escribir en la ruta de la máquina original de Microsoft.

**`RECOVERY` vs `NORECOVERY`** — Acá está la sutileza que casi nadie explica bien.

Un `RESTORE` puede ser **un paso de una cadena**: primero un backup completo, después uno diferencial, después varios de log. Mientras la cadena no termina, la base no puede abrirse: hay transacciones a medio aplicar.

- **`NORECOVERY`** — "no termines todavía, viene más". La base queda en estado *Restoring*, inaccesible.
- **`RECOVERY`** (por defecto) — "terminá": aplica el *redo* de las transacciones confirmadas, deshace el *undo* de las abiertas, y abre la base.

Como tenemos un único backup completo, va `RECOVERY`.

> **💡 Concepto clave — proceso de recuperación (*recovery*).** Es el mismo mecanismo que corre cuando SQL Server arranca tras una caída: rehacer lo confirmado, deshacer lo abierto. Es la garantía de **durabilidad** y **atomicidad** de ACID hecha operación concreta. Volvemos a esto en el Módulo 3.

**`REPLACE`** — Sobrescribe una base existente con el mismo nombre. **Es destructivo.** SQL Server lo exige justamente para que no puedas pisar una base por accidente. Si lo estás escribiendo, parate un segundo y confirmá que sabés qué estás sobrescribiendo.

**`STATS = 10`** — Informa el progreso cada 10%. Cosmético, pero útil en restores largos.

**Verificación:**

```sql
SELECT name, state_desc, recovery_model_desc
FROM sys.databases
WHERE name = 'WideWorldImporters';
```

Debe decir `ONLINE`.

---

### 1.4 Modelos de recuperación

> ➕ **Tema adicional recomendado:** modelos de recuperación
> **Por qué necesito aprenderlo:** determina si podés recuperar a un punto en el tiempo y cuánto crece el log; es decisión de todo proyecto con base propia.
> **En qué parte del proyecto lo utilizaremos:** al crear `WWI_Staging` vas a elegir SIMPLE, y hay que saber defender por qué.

| Modelo | Log de transacciones | Recuperación a un punto en el tiempo | Uso típico |
|---|---|---|---|
| **SIMPLE** | Se trunca solo en cada checkpoint | ❌ No | Staging, DW, dev |
| **FULL** | Crece hasta que se respalda el log | ✅ Sí | Producción OLTP |
| **BULK_LOGGED** | Mínimo para operaciones masivas | ⚠️ Parcial | Cargas masivas puntuales |

**Cómo se decide, y la regla mental:**

> ¿Puedo reconstruir estos datos desde otra fuente?
> **Sí** → SIMPLE. **No** → FULL.

Producción va FULL: si se pierde una hora de pedidos, esos pedidos **no existen en ningún otro lado**.

Staging va SIMPLE: si se pierde, se vuelve a correr la carga y en segundos está de nuevo. Pagar el costo de FULL —backups de log, administración, crecimiento del archivo— por datos **derivados** es tirar recursos.

Y hay un beneficio operativo concreto: en SIMPLE, tu `TRUNCATE` + `INSERT` diario **no infla el log** indefinidamente. En FULL, sin backups de log regulares, el `.ldf` crece hasta llenar el disco. Es una de las formas más comunes de romper un servidor sin querer.

```sql
ALTER DATABASE WWI_Staging SET RECOVERY SIMPLE;
```

---

### 1.5 Anatomía de WideWorldImporters

WWI organiza sus 48 tablas en **4 schemas**, y la división no es decorativa: cada schema es un **área funcional del negocio**.

| Schema | Tablas | De qué se ocupa |
|---|---|---|
| `Application` | 15 | Datos transversales: personas, ciudades, países, parámetros |
| `Sales` | 12 | Ciclo de venta: clientes, pedidos, facturas, cobros |
| `Purchasing` | 7 | Ciclo de compra: proveedores, órdenes de compra |
| `Warehouse` | 14 | Inventario: productos, existencias, transacciones de stock |

> **💡 Concepto clave — schema como frontera.** Un schema en SQL Server es un **espacio de nombres** y también una **unidad de permisos**. Podés dar `SELECT` sobre todo `Sales` a un rol sin exponer `Purchasing`. Es el equivalente a los *namespaces* de C# combinados con modificadores de acceso: organización **y** control. Por eso tu staging usa `etl` para los objetos del pipeline y `Sales` para las tablas espejo — así el schema espejado contiene *solo* lo que existe en el origen.

#### Las tablas centrales del ciclo de venta

```
Application.Countries  (190)
        ▲
Application.StateProvinces  (53)
        ▲
Application.Cities  (37.940)
        ▲
Sales.Customers  (663)  ──► Sales.CustomerCategories (8)
        ▲                └─► Sales.BuyingGroups (2)
        │
Sales.Orders  (73.595)  ──► Application.People (vendedor, 1.111)
        ▲
Sales.OrderLines  (231.412)  ──► Warehouse.StockItems (227)
                                        ▲
                              Warehouse.StockItemStockGroups (442)
                                        ▲
                              Warehouse.StockGroups (10)
```

Leé la flecha como "apunta a". `Sales.OrderLines` es la tabla más profunda y más grande — y no por casualidad: **es donde vive el detalle del negocio.** Retené eso, porque en el Módulo 7 va a ser el corazón de la decisión de grano.

#### El dato que cambia todo el proyecto

```sql
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'Sales' AND TABLE_NAME = 'Orders';
```

Mirá el resultado con atención: **`Sales.Orders` no tiene ninguna columna de monto.** Ni total, ni subtotal, ni importe.

No es un olvido de Microsoft, es diseño normalizado correcto: el monto de un pedido es una **función derivada** de sus líneas (`SUM(Quantity × UnitPrice)`). Guardarlo también en la cabecera sería redundancia, y la redundancia en OLTP es riesgo de inconsistencia.

Consecuencia práctica: **no podés construir ni una sola métrica de ventas sin `Sales.OrderLines`.** Esta observación —hecha antes de escribir código— es exactamente el tipo de hallazgo que justifica todo el trabajo de exploración que sigue.

---

### 1.6 Cómo descubrir tablas sin documentación

Acá empieza la parte que te va a servir el resto de tu carrera. **En el trabajo real casi nunca hay documentación**, o la hay y está desactualizada, que es peor.

SQL Server expone su propia estructura como tablas consultables. Hay dos familias:

- **`INFORMATION_SCHEMA.*`** — vistas del estándar ANSI. Portables a otros motores, pero limitadas: no ven índices, ni tablas temporales, ni particiones.
- **`sys.*`** — catálogo nativo de SQL Server. Lo ve todo, pero es específico del motor.

> **✅ Regla práctica:** usá `INFORMATION_SCHEMA` para lo básico y portable; pasate a `sys.*` cuando necesites algo que solo SQL Server tiene. En una entrevista, saber que existen **las dos** y por qué, ya te distingue.

**Consulta 1 — Todas las tablas con su conteo de filas (sin escanearlas):**

```sql
SELECT
    s.name  AS SchemaName,
    t.name  AS TableName,
    p.rows  AS RowCounts
FROM sys.tables      t
JOIN sys.schemas     s ON s.schema_id = t.schema_id
JOIN sys.partitions  p ON p.object_id = t.object_id
                      AND p.index_id IN (0, 1)   -- heap o índice agrupado
ORDER BY p.rows DESC;
```

**Por qué así y no con `COUNT(*)`:** `sys.partitions` guarda un conteo **mantenido por el motor**. Es instantáneo aunque la tabla tenga cien millones de filas. Un `COUNT(*)` tendría que recorrerla entera y tomar bloqueos.

El filtro `index_id IN (0,1)` es imprescindible: `0` es un *heap* (tabla sin índice agrupado), `1` es el índice agrupado. Los `index_id >= 2` son índices no agrupados, y **contarlos también multiplicaría las filas** por la cantidad de índices.

> **⚠️ Advertencia:** ese conteo es *casi* exacto. Puede desviarse ligeramente tras cargas masivas o fallos. Para un inventario inicial es perfecto; para cuadrar una carga contra el origen, usá `COUNT(*)`.

**Lo primero que hay que mirar: el orden por tamaño.** Las tablas grandes son casi siempre los **hechos** del negocio (transacciones, eventos, movimientos). Las chicas son casi siempre **dimensiones** (catálogos, maestros). En WWI: `OrderLines` 231.412 e `InvoiceLines` 228.265 arriba; `BuyingGroups` con 2 filas abajo. Ese solo ordenamiento ya te dibuja el modelo dimensional en la cabeza — antes de saber nada del negocio.

---

### 1.7 Cómo descubrir columnas y tipos de datos

**Consulta 2 — Estructura completa de una tabla:**

```sql
SELECT
    ORDINAL_POSITION          AS Pos,
    COLUMN_NAME               AS Columna,
    DATA_TYPE                 AS Tipo,
    CHARACTER_MAXIMUM_LENGTH  AS Largo,
    NUMERIC_PRECISION         AS Precision,
    NUMERIC_SCALE             AS Escala,
    IS_NULLABLE               AS AceptaNull,
    COLUMN_DEFAULT            AS ValorPorDefecto
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'Sales'
  AND TABLE_NAME   = 'Orders'
ORDER BY ORDINAL_POSITION;
```

**Qué leer en ese resultado — cuatro señales:**

1. **`IS_NULLABLE = 'NO'`** → el origen garantiza que hay valor. Es una **promesa del sistema fuente**, y es información valiosísima para diseñar tus validaciones.
2. **`CHARACTER_MAXIMUM_LENGTH = -1`** → es un tipo `MAX` (`NVARCHAR(MAX)`). Ojo: no se puede indexar de la forma habitual y pesa en las cargas.
3. **`NUMERIC_SCALE`** en montos → cuántos decimales. `DECIMAL(18,2)` es dinero; `FLOAT` para dinero es **un error grave** (aritmética binaria aproximada). Si ves `FLOAT` en un monto, anotalo como riesgo.
4. **`COLUMN_DEFAULT`** → revela reglas de negocio implícitas.

**Consulta 3 — Buscar una columna en toda la base.** Cuando te dicen "el dato de la sucursal" y no sabés dónde vive:

```sql
SELECT TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE COLUMN_NAME LIKE '%Customer%'
ORDER BY TABLE_SCHEMA, TABLE_NAME;
```

Esta consulta, sola, resuelve la mitad de los "no sé dónde está ese dato" de la vida real.

**Consulta 4 — Columnas calculadas** (las que `INFORMATION_SCHEMA` no distingue):

```sql
SELECT
    OBJECT_SCHEMA_NAME(c.object_id) + '.' + OBJECT_NAME(c.object_id) AS Tabla,
    c.name        AS Columna,
    cc.definition AS Formula,
    cc.is_persisted
FROM sys.computed_columns cc
JOIN sys.columns c ON c.object_id = cc.object_id
                  AND c.column_id = cc.column_id;
```

**Por qué importa para ETL:** una columna calculada **no se puede insertar**. Si la incluís en el `INSERT` de tu carga, falla. En WWI, `Application.People.SearchName` es una — y es exactamente el tipo de sorpresa que aparece a las 3 AM.

---

### 1.8 Cómo descubrir relaciones: claves primarias y foráneas

**Consulta 5 — Todas las claves primarias:**

```sql
SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    i.name AS ConstraintName,
    STRING_AGG(c.name, ', ') WITHIN GROUP (ORDER BY ic.key_ordinal) AS Columnas
FROM sys.indexes i
JOIN sys.tables  t ON t.object_id = i.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE i.is_primary_key = 1
GROUP BY s.name, t.name, i.name
ORDER BY s.name, t.name;
```

Fijate en la columna `Columnas`: si aparece **más de un campo**, es una **clave compuesta**. Las claves compuestas complican el ETL (los joins necesitan todas las partes) y son uno de los argumentos a favor de las claves surrogate del Módulo 7. Anotá cuáles hay.

**Consulta 6 — El mapa de relaciones (la consulta más valiosa del módulo):**

```sql
SELECT
    OBJECT_SCHEMA_NAME(fk.parent_object_id) + '.' +
    OBJECT_NAME(fk.parent_object_id)                    AS TablaHija,
    cp.name                                             AS ColumnaHija,
    OBJECT_SCHEMA_NAME(fk.referenced_object_id) + '.' +
    OBJECT_NAME(fk.referenced_object_id)                AS TablaPadre,
    cr.name                                             AS ColumnaPadre,
    fk.name                                             AS NombreFK,
    fk.delete_referential_action_desc                   AS AlBorrar
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns cp ON cp.object_id = fkc.parent_object_id
                   AND cp.column_id = fkc.parent_column_id
JOIN sys.columns cr ON cr.object_id = fkc.referenced_object_id
                   AND cr.column_id = fkc.referenced_column_id
ORDER BY TablaHija, NombreFK;
```

**Esto es el diagrama entidad-relación, en texto y siempre actualizado.** Con este resultado podés reconstruir el modelo completo sin abrir una sola herramienta gráfica.

**Cómo leerlo estratégicamente — dos preguntas:**

1. **¿Qué tabla tiene MÁS claves foráneas salientes?** Esa es tu candidata a **tabla de hechos**: un hecho es un evento que referencia mucho contexto. En WWI, `Sales.Orders` y `Sales.OrderLines` lideran.
2. **¿Qué tabla es MÁS referenciada por otras?** Esas son tus **dimensiones**: contexto reutilizado por muchos eventos.

> **🎓 Esto es dinamita en una entrevista.** Si te dan una base desconocida y te piden un modelo dimensional, contar FKs entrantes y salientes te da un primer borrador en dos minutos. No es adivinanza — es que la topología del modelo relacional ya codifica la distinción hecho/dimensión.

**Consulta 7 — Buscar FKs faltantes (el hallazgo que nadie espera):**

```sql
-- Columnas que se llaman como una clave pero no tienen FK declarada
SELECT
    OBJECT_SCHEMA_NAME(c.object_id) + '.' + OBJECT_NAME(c.object_id) AS Tabla,
    c.name AS Columna
FROM sys.columns c
JOIN sys.tables  t ON t.object_id = c.object_id
WHERE c.name LIKE '%ID'
  AND c.name NOT LIKE '%RowID'
  AND NOT EXISTS (
      SELECT 1
      FROM sys.foreign_key_columns fkc
      WHERE fkc.parent_object_id = c.object_id
        AND fkc.parent_column_id = c.column_id
  )
  AND NOT EXISTS (
      SELECT 1
      FROM sys.index_columns ic
      JOIN sys.indexes i ON i.object_id = ic.object_id AND i.index_id = ic.index_id
      WHERE ic.object_id = c.object_id
        AND ic.column_id = c.column_id
        AND i.is_primary_key = 1
  )
ORDER BY 1, 2;
```

**Por qué importa muchísimo:** una columna que *parece* una clave foránea pero no lo es, **no tiene integridad garantizada**. Puede contener identificadores que ya no existen. En WWI vas a encontrar `Sales.Orders.BackorderOrderID`: apunta a otro pedido pero sin FK declarada. En tu ETL eso es una validación obligatoria — y si no la ponés, el `INNER JOIN` de tu fact table va a descartar filas silenciosamente.

**Ese es, literalmente, uno de los cinco fallos silenciosos que este libro te va a enseñar a cazar.**

---

### 1.9 Constraints

Las FKs son un tipo de constraint. Hay más, y cada una es **documentación ejecutable** de una regla de negocio.

**Consulta 8 — CHECK constraints:**

```sql
SELECT
    OBJECT_SCHEMA_NAME(cc.parent_object_id) + '.' +
    OBJECT_NAME(cc.parent_object_id) AS Tabla,
    cc.name       AS Constraint_,
    cc.definition AS Regla
FROM sys.check_constraints cc
ORDER BY 1;
```

Cada `CHECK` te está diciendo una regla que el negocio considera inviolable. Si el origen garantiza `Quantity > 0`, tu validación de rango puede confiar en eso... **mientras el dato venga de ahí.** Si mañana entra por una carga masiva con `WITH (CHECK_CONSTRAINTS OFF)`, la garantía se rompe.

**Consulta 9 — Constraints no confiables (el chequeo que casi nadie hace):**

```sql
SELECT name, is_not_trusted, 'CHECK' AS Tipo
FROM sys.check_constraints WHERE is_not_trusted = 1
UNION ALL
SELECT name, is_not_trusted, 'FOREIGN KEY'
FROM sys.foreign_keys WHERE is_not_trusted = 1;
```

> **💡 Concepto clave — constraint *not trusted*.** Cuando un constraint se deshabilita y luego se rehabilita **sin verificar** los datos existentes (`WITH NOCHECK` en vez de `WITH CHECK`), SQL Server lo marca como no confiable. Sigue aplicándose a filas nuevas, pero **el optimizador deja de usarlo** para generar planes, y —más grave para vos— **puede haber filas viejas que lo violan**. Una FK *not trusted* significa que puede haber huérfanos ahora mismo. Es un hallazgo de auditoría de primer nivel.

**Tipos de constraint y qué garantiza cada uno:**

| Constraint | Garantiza | Riesgo si falta |
|---|---|---|
| `PRIMARY KEY` | Unicidad + no nulo | Duplicados en el grano |
| `FOREIGN KEY` | El referenciado existe | Huérfanos; filas perdidas en joins |
| `UNIQUE` | Sin repetidos | Duplicados lógicos |
| `CHECK` | Valor dentro de un dominio | Valores imposibles |
| `NOT NULL` | Siempre hay valor | Agregaciones incompletas |
| `DEFAULT` | Valor si no se especifica | Nulos inesperados |

---

### 1.10 Perfilado de datos

Conocer la **estructura** no alcanza. Hay que conocer el **contenido**. A esto se le llama **data profiling** — perfilado de datos — y es un paso formal en cualquier proyecto serio de integración.

**Consulta 10 — Perfil de completitud de una tabla:**

```sql
SELECT
    COUNT(*)                                                        AS TotalFilas,
    SUM(CASE WHEN CustomerID           IS NULL THEN 1 ELSE 0 END)   AS CustomerID_Null,
    SUM(CASE WHEN SalespersonPersonID  IS NULL THEN 1 ELSE 0 END)   AS Salesperson_Null,
    SUM(CASE WHEN PickedByPersonID     IS NULL THEN 1 ELSE 0 END)   AS PickedBy_Null,
    SUM(CASE WHEN BackorderOrderID     IS NULL THEN 1 ELSE 0 END)   AS Backorder_Null,
    SUM(CASE WHEN Comments             IS NULL THEN 1 ELSE 0 END)   AS Comments_Null
FROM Sales.Orders;
```

> **⚠️ Detalle técnico que importa más de lo que parece.** Usamos `SUM(CASE ... ELSE 0 END)` y **no** `COUNT(CASE ... END)`. Ambos dan el mismo número, pero `COUNT` sobre una expresión que produce `NULL` emite el **warning 8153** ("Null value is eliminated by an aggregate"). En una consulta interactiva es ruido; dentro de un job nocturno, ese warning **contamina el historial de ejecución** y entrena al equipo a ignorar avisos. La higiene de las alertas es parte del diseño.

**Cómo interpretar el resultado — la lectura es lo importante:**

- `PickedByPersonID` con muchos nulos → **no es un error**. Significa "el pedido todavía no fue preparado". El NULL codifica un **estado del proceso**.
- `BackorderOrderID` casi todo nulo → **normal**. Solo unos pocos pedidos son reposiciones.
- `CustomerID` con un solo nulo → **eso sí es alarma**. Un pedido sin cliente es un dato roto.

> **✅ Lección central:** *un NULL no es un error hasta que entendés qué significa en el negocio.* La misma columna vacía puede ser un estado válido o un dato corrupto. **Esa distinción no la podés hacer desde el catálogo del sistema — hay que preguntarle a alguien.** Aprender a hacer esa pregunta vale más que cualquier consulta de este módulo.

**Consulta 11 — Cardinalidad y selectividad:**

```sql
SELECT
    COUNT(*)                        AS Filas,
    COUNT(DISTINCT CustomerID)      AS ClientesDistintos,
    COUNT(DISTINCT SalespersonPersonID) AS VendedoresDistintos,
    MIN(OrderDate)                  AS FechaMin,
    MAX(OrderDate)                  AS FechaMax,
    DATEDIFF(DAY, MIN(OrderDate), MAX(OrderDate)) AS DiasCubiertos
FROM Sales.Orders;
```

**Qué revela:**

- **Cardinalidad baja** (pocos valores distintos) → buena candidata a dimensión o a columna de filtro.
- **Cardinalidad alta** (casi tantos valores como filas) → es un identificador.
- **Rango de fechas** → define el alcance de tu `DimDate`. No la generes desde 1900 "por las dudas": generala para el rango real más un margen.
- **Días cubiertos vs filas** → te da el volumen diario promedio, que es el insumo para dimensionar la carga incremental.

**Consulta 12 — Distribución de valores (detección de sesgo y de basura):**

```sql
SELECT TOP (20)
    IsUndersupplyBackordered,
    COUNT(*) AS Cantidad,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS Porcentaje
FROM Sales.Orders
GROUP BY IsUndersupplyBackordered
ORDER BY Cantidad DESC;
```

Cambiá la columna y repetí. Es tedioso y **es exactamente lo que hay que hacer**. Buscás:

- **Valores centinela** — `'N/A'`, `'SIN DATO'`, `-1`, `'1900-01-01'`, `'XXX'`. Son NULLs disfrazados, y como no son NULL, **ninguna validación de nulos los detecta**. Envenenan promedios y aparecen como categorías propias en el dashboard.
- **Sesgo extremo** — un valor con el 99% de las filas. La columna casi no informa.
- **Errores de formato** — `'ARGENTINA'`, `'Argentina'` y `'argentina '` como tres categorías distintas. Espacios al final y diferencias de mayúsculas son el clásico.

---

### 1.11 La trampa: relaciones muchos a muchos

Corré esto:

```sql
SELECT COUNT(*) AS Productos          FROM Warehouse.StockItems;            -- 227
SELECT COUNT(*) AS Grupos             FROM Warehouse.StockGroups;           -- 10
SELECT COUNT(*) AS Asignaciones       FROM Warehouse.StockItemStockGroups;  -- 442
```

**442 asignaciones para 227 productos.** Es decir: **un producto pertenece en promedio a casi dos categorías.**

Ahora mirá qué pasa si hacés el join ingenuo:

```sql
-- ❌ INCORRECTO: infla las ventas
SELECT sg.StockGroupName, SUM(ol.Quantity * ol.UnitPrice) AS Ventas
FROM Sales.OrderLines ol
JOIN Warehouse.StockItems si            ON si.StockItemID  = ol.StockItemID
JOIN Warehouse.StockItemStockGroups sisg ON sisg.StockItemID = si.StockItemID
JOIN Warehouse.StockGroups sg           ON sg.StockGroupID  = sisg.StockGroupID
GROUP BY sg.StockGroupName;
```

Cada línea de pedido se **duplica una vez por cada grupo** al que pertenece su producto. Si sumás todas las categorías, el total va a ser **casi el doble de las ventas reales**.

Y acá está lo grave: **la consulta no falla.** No hay error, no hay warning. Devuelve números plausibles, con la categoría correcta, y todos inflados. Es el fallo silencioso en su forma más pura.

> **💡 Concepto clave — *fan-out* (o *fan trap*).** La multiplicación de filas al unir por una relación de uno a muchos en dirección equivocada. Es la causa número uno de "el dashboard no cuadra con el sistema" en proyectos de BI. En el Módulo 7 vemos las tres soluciones: elegir un grupo primario, usar una tabla puente con factor de asignación, o cambiar el grano.

**Cómo detectarlo sistemáticamente en cualquier base:**

```sql
-- Toda tabla cuya PK esté compuesta SOLO por columnas que son FK
-- es, casi con certeza, una tabla puente de muchos a muchos.
SELECT
    OBJECT_SCHEMA_NAME(t.object_id) + '.' + OBJECT_NAME(t.object_id) AS TablaPuente
FROM sys.tables t
WHERE EXISTS (SELECT 1 FROM sys.indexes i
              WHERE i.object_id = t.object_id AND i.is_primary_key = 1)
  AND (SELECT COUNT(*) FROM sys.foreign_keys fk
       WHERE fk.parent_object_id = t.object_id) >= 2
ORDER BY 1;
```

Ejecutala en toda base nueva. Cada resultado es una trampa potencial esperándote.

---

### 1.12 Tablas temporales de sistema

> ➕ **Tema adicional recomendado:** tablas temporales con versionado de sistema
> **Por qué necesito aprenderlo:** WWI las usa en 17 tablas, aparecen en tus consultas de exploración, y son la implementación nativa de historia que se conecta directo con Slowly Changing Dimensions.
> **En qué parte del proyecto lo utilizaremos:** al extraer dimensiones (Módulo 8) y al discutir SCD Tipo 2 (Módulo 7).

```sql
SELECT
    s.name + '.' + t.name AS Tabla,
    t.temporal_type_desc,
    OBJECT_SCHEMA_NAME(t.history_table_id) + '.' +
    OBJECT_NAME(t.history_table_id) AS TablaHistorica
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE t.temporal_type = 2
ORDER BY 1;
```

En WWI esto devuelve **17 tablas**, entre ellas `Sales.Customers`, `Warehouse.StockItems`, `Application.Cities` y `Application.People`.

**Qué es una tabla temporal de sistema:** SQL Server mantiene **automáticamente** una tabla histórica paralela. Cada `UPDATE` o `DELETE` guarda la versión anterior con su período de validez (`ValidFrom` / `ValidTo`). Podés consultar el pasado:

```sql
SELECT CustomerID, CustomerName, CustomerCategoryID
FROM Sales.Customers
FOR SYSTEM_TIME AS OF '2015-06-01'
WHERE CustomerID = 1;
```

**Por qué importa para tu proyecto — tres implicaciones concretas:**

1. **Las columnas de período son ocultas.** `ValidFrom` y `ValidTo` no aparecen en `SELECT *`, pero **sí** aparecen en `INFORMATION_SCHEMA.COLUMNS`. Si armás tu `INSERT` desde esa lista, vas a intentar insertar columnas que no podés — y en una tabla temporal de destino, son de generación automática.
2. **Son un regalo para SCD Tipo 2.** El origen ya guarda el historial de cambios de tus dimensiones. En vez de detectar cambios comparando snapshots, podés **leer el historial directamente**. Poca gente aprovecha esto.
3. **No las copies a staging por defecto.** Multiplican el volumen y casi nunca las necesitás para la carga diaria. Copiá la tabla actual; recurrí al historial solo cuando construyas SCD.

> **🎓 Pregunta de entrevista de alto nivel:** *"¿Cómo implementarías una dimensión SCD Tipo 2 si el sistema origen ya usa tablas temporales?"* La respuesta que impresiona: *"Usaría `FOR SYSTEM_TIME ALL` para leer las versiones y mapearlas directamente a las filas de la dimensión, en vez de hacer detección de cambios por comparación. El origen ya resolvió el problema difícil; replicarlo sería duplicar lógica."*

---

### 1.13 Qué tablas necesita nuestro proyecto

Toda la exploración anterior sirve para responder **una** pregunta: ¿qué traemos?

**El método, en cuatro pasos.** No se empieza por las tablas — se empieza por las preguntas.

**Paso 1 — Escribí las preguntas de negocio.** Para este proyecto:

- ¿Cuánto vendimos por mes?
- ¿Qué productos se venden más?
- ¿Qué clientes compran más?
- ¿Qué vendedores rinden mejor?
- ¿Cómo se distribuyen las ventas geográficamente?

**Paso 2 — Extraé los sustantivos.** Venta, mes, producto, cliente, vendedor, geografía.

**Paso 3 — Mapeá cada sustantivo a tablas.**

| Sustantivo | Tabla | Filas | Rol probable |
|---|---|---|---|
| Venta (importe) | `Sales.OrderLines` | 231.412 | **Hecho** |
| Venta (cabecera) | `Sales.Orders` | 73.595 | Hecho / contexto |
| Producto | `Warehouse.StockItems` | 227 | Dimensión |
| Categoría | `Warehouse.StockGroups` + puente | 10 + 442 | Dimensión (⚠️ M:N) |
| Cliente | `Sales.Customers` | 663 | Dimensión |
| Categoría de cliente | `Sales.CustomerCategories` | 8 | Atributo de dimensión |
| Geografía | `Cities` → `StateProvinces` → `Countries` | 37.940 / 53 / 190 | Atributo de dimensión |
| Vendedor | `Application.People` | 1.111 | Dimensión |
| Mes | *(ninguna)* | — | **Dimensión a construir** |

**Paso 4 — Aplicá el criterio de exclusión.** Y este paso es el que separa a un profesional de alguien que copia todo "por las dudas":

> **✅ Regla:** si no podés nombrar una pregunta de negocio que la tabla ayuda a responder, **no la traigas**. Cada tabla en el pipeline es superficie de mantenimiento permanente: hay que cargarla, validarla, versionarla y arreglarla cuando el origen cambie.

Por eso quedan afuera `Purchasing` (compras — otro proceso de negocio), `Sales.Invoices` (facturación, que no es lo mismo que pedidos), y `Warehouse.StockItemTransactions` (movimientos de inventario). Todas son válidas y todas serían un proyecto propio.

Fijate también en la última fila de la tabla: **"Mes" no existe como tabla en el origen.** Eso no es un problema — es el primer indicio de que un warehouse **agrega** estructura que el OLTP no tiene. Lo vemos en 7.10.

---

### 1.14 El kit de exploración

Guardá estas doce consultas. Son tu primer día en cualquier base desconocida, en cualquier trabajo.

| # | Qué responde |
|---|---|
| 1 | ¿Qué tablas hay y de qué tamaño? |
| 2 | ¿Qué columnas y tipos tiene esta tabla? |
| 3 | ¿Dónde vive una columna con cierto nombre? |
| 4 | ¿Qué columnas son calculadas? *(no se pueden insertar)* |
| 5 | ¿Cuáles son las claves primarias? ¿Hay compuestas? |
| 6 | ¿Cómo se relacionan las tablas? |
| 7 | ¿Qué claves no tienen FK declarada? *(sin integridad)* |
| 8 | ¿Qué reglas de negocio hay en CHECK constraints? |
| 9 | ¿Hay constraints no confiables? *(pueden estar violados)* |
| 10 | ¿Qué tan completos están los datos? |
| 11 | ¿Cuál es la cardinalidad y el rango de fechas? |
| 12 | ¿Cómo se distribuyen los valores? ¿Hay centinelas? |
| + | ¿Qué tablas puente de muchos a muchos hay? |

**El orden importa.** De estructura a contenido, de lo general a lo específico. Y las tres más subestimadas son la **7** (FKs faltantes), la **9** (constraints no confiables) y la de **tablas puente** — son las que encuentran los problemas que después explotan en producción.

---

## 💡 Conceptos clave

- **`RESTORE FILELISTONLY`** — lee el contenido del backup sin restaurar.
- **`WITH MOVE`** — redirige archivos a rutas existentes en tu máquina.
- **`RECOVERY` / `NORECOVERY`** — cerrar la cadena de restore o dejarla abierta.
- **Modelo de recuperación** — SIMPLE para datos reconstruibles, FULL para datos irremplazables.
- **`INFORMATION_SCHEMA` vs `sys.*`** — estándar portable vs catálogo completo de SQL Server.
- **Data profiling** — analizar el contenido, no solo la estructura, antes de diseñar el ETL.
- **Cardinalidad** — cantidad de valores distintos de una columna.
- **Valor centinela** — un valor que representa "sin dato" sin ser NULL.
- **Fan-out / fan trap** — multiplicación de filas al unir por una relación muchos a muchos.
- **Constraint *not trusted*** — constraint rehabilitado sin verificar: puede estar violado ahora mismo.
- **Tabla temporal de sistema** — tabla con historial automático de versiones.

---

## ⚠️ Errores comunes

**Restaurar sin `MOVE`.** Falla con "directory lookup failed". La causa es que el `.bak` guarda las rutas de la máquina de origen.

**Usar `COUNT(*)` para inventariar tablas grandes.** Escanea, bloquea y tarda. Usá `sys.partitions`.

**Olvidar `index_id IN (0,1)`.** Multiplica el conteo por la cantidad de índices. Un error silencioso clásico: los números "casi" cuadran.

**Confiar en `SELECT *` para conocer una tabla.** No muestra columnas ocultas de tablas temporales, no dice qué es calculado, no revela constraints ni nulabilidad.

**Asumir que existe FK porque la columna se llama `AlgoID`.** La consulta 7 existe por esto.

**Saltear el perfilado y diseñar desde la estructura.** La estructura dice qué *puede* haber; el perfilado dice qué *hay*. Diseñar sin perfilar es cómo se descubre en producción que el 30% de una columna obligatoria trae `'N/A'`.

**Traer todas las tablas "por las dudas".** Cada tabla es mantenimiento eterno. Sin pregunta de negocio, no entra.

**Ignorar las tablas puente.** El fan-out no da error. Te enterás cuando el gerente dice "esto no cuadra".

---

## ✅ Buenas prácticas

1. **Documentá los hallazgos mientras explorás**, no después. Un archivo `exploracion.md` con "`BackorderOrderID` no tiene FK — validar" vale más que la mejor memoria.
2. **Perfilá antes de diseñar. Siempre.** Es la diferencia entre un ETL que funciona el primer día y uno que descubre sorpresas durante seis meses.
3. **Preguntá el significado de los NULLs a alguien de negocio.** Ninguna consulta lo responde.
4. **Guardá el kit de exploración en un archivo versionado.** Lo vas a usar en cada proyecto nuevo.
5. **Verificá el restore con datos, no solo con el estado.** `state_desc = ONLINE` no garantiza que las tablas tengan filas. Contá algo conocido.
6. **Nunca modifiques el origen.** Ni un índice "para que ande más rápido". Producción es de solo lectura para vos, y esa disciplina se nota.

---

## 🧠 Preguntas de comprensión

1. ¿Por qué `Sales.Orders` no tiene columna de monto, y qué consecuencia concreta tiene para tu pipeline?
2. Encontrás una columna `CountryID` sin FK declarada. ¿Qué dos validaciones agregarías a tu ETL, y qué pasaría en tu fact table si no las agregás?
3. `PickedByPersonID` tiene 3.085 nulos de 73.595. ¿Es un problema de calidad? ¿Qué necesitás saber para responder?
4. Si `sys.partitions` dice 231.412 filas y `COUNT(*)` dice 231.410, ¿cuál creés y por qué?
5. Explicá por qué 442 asignaciones para 227 productos es un riesgo, y describí el síntoma que verías en el dashboard.

---

## 📝 Ejercicios

**🟢 Básico.** Ejecutá las 12 consultas del kit sobre WideWorldImporters. Guardá los resultados en un archivo. No interpretes todavía — solo generá el material.

**🟢 Básico.** Encontrá las cinco tablas más grandes y las cinco más chicas. Sin saber nada del negocio, clasificá cada una como probable hecho o probable dimensión, y escribí por qué.

**🟡 Intermedio.** Perfilá `Sales.OrderLines` completa: nulos por columna, cardinalidad, rango de `Quantity` y `UnitPrice`, y distribución de `PackageTypeID`. Escribí tres observaciones que afectarían tu diseño de ETL.

**🟡 Intermedio.** Corré la consulta 7 sobre toda WWI. Para cada columna sin FK, decidí si es un riesgo real o un falso positivo, y justificá.

**🔴 Avanzado.** Escribí una consulta que, para **cualquier** tabla que le pases, genere automáticamente el SQL de perfilado de nulos de todas sus columnas. Pista: `INFORMATION_SCHEMA.COLUMNS` + `STRING_AGG` + SQL dinámico. Esto se llama **generación de código con metadatos** y es una técnica central del oficio.

**🔴 Avanzado.** Demostrá el fan-out empíricamente: calculá las ventas totales de `Sales.OrderLines` sin joins, después con el join a `StockGroups`, y cuantificá exactamente la diferencia. Explicá de dónde sale cada peso de más.

**🧠 Reto.** Elegí una base de tu trabajo que no conozcas bien. Aplicá el kit completo y escribí un informe de dos páginas: qué hace la base, cuáles son sus entidades centrales, qué problemas de calidad tiene y qué tres tablas usarías para un warehouse. **Este ejercicio es, esencialmente, la primera semana de un trabajo de datos.**

---

## 🎓 Preguntas de entrevista

1. **Te dan acceso a una base que nadie conoce y una semana para proponer un modelo analítico. ¿Cómo arrancás?** — Describí el método: inventario por tamaño → mapa de FKs → contar FKs entrantes/salientes para separar hechos de dimensiones → perfilado → **preguntas de negocio** → alcance. Mencionar las preguntas de negocio antes que las tablas es lo que distingue la respuesta.
2. **¿Cómo identificás la tabla de hechos candidata?** — La más grande, la de más FKs salientes, y la que contiene medidas numéricas aditivas. Las tres señales juntas.
3. **¿Diferencia entre `INFORMATION_SCHEMA` y `sys`?** — Estándar ANSI portable pero limitado, vs catálogo nativo completo.
4. **¿Cómo contás filas de una tabla de mil millones sin afectar producción?** — `sys.partitions` con `index_id IN (0,1)`. Y aclarar que es aproximado.
5. **¿Qué es data profiling y por qué se hace antes de diseñar?** — Ver 1.10.
6. **¿Qué hacés si encontrás una FK marcada como *not trusted*?** — Verificar si hay filas que la violan, reportarlo al dueño del sistema, y **no** asumir integridad en el ETL.
7. **¿Qué problema traen las relaciones muchos a muchos en un modelo dimensional?** — Fan-out: duplicación de medidas. Y que no da error.

---

## 📌 Resumen

- WWI es una base OLTP realista: 48 tablas, 4 schemas, 17 tablas temporales, y datos sucios a propósito.
- Restaurar requiere `FILELISTONLY` para conocer los archivos lógicos y `WITH MOVE` para redirigirlos.
- SIMPLE para datos reconstruibles; FULL para datos que no existen en otro lado.
- El catálogo del sistema (`sys.*`, `INFORMATION_SCHEMA.*`) es la documentación que siempre está actualizada.
- La topología de FKs ya codifica la distinción hecho/dimensión: contá entrantes y salientes.
- **Perfilar es obligatorio.** La estructura dice qué puede haber; el contenido dice qué hay.
- Los NULLs no son errores hasta que el negocio dice que lo son.
- Las tablas puente causan fan-out, y el fan-out **no da error**.
- `Sales.Orders` no tiene montos: sin `OrderLines` no hay métricas.
- Se traen las tablas que responden preguntas de negocio. El resto es deuda.

---

## 🗂️ Flashcards

| Pregunta | Respuesta |
|---|---|
| ¿Qué hace `RESTORE FILELISTONLY`? | Lista los archivos lógicos del backup sin restaurar. |
| ¿Para qué sirve `WITH MOVE`? | Redirigir los archivos a rutas que existen en tu máquina. |
| ¿`RECOVERY` vs `NORECOVERY`? | Cerrar la cadena y abrir la base, vs dejarla abierta para más restores. |
| ¿Cuándo SIMPLE y cuándo FULL? | SIMPLE si podés reconstruir el dato; FULL si no. |
| ¿Cómo contar filas sin escanear? | `sys.partitions` con `index_id IN (0,1)`. |
| ¿Por qué el filtro `index_id IN (0,1)`? | Sin él se cuentan también los índices no agrupados. |
| ¿Cómo encontrar todas las FKs? | `sys.foreign_keys` + `sys.foreign_key_columns`. |
| ¿Cómo se detecta una tabla de hechos candidata? | La más grande, con más FKs salientes y con medidas numéricas. |
| ¿Qué es un valor centinela? | Un valor que significa "sin dato" sin ser NULL: `'N/A'`, `-1`. |
| ¿Qué es fan-out? | Duplicación de filas al unir por una relación muchos a muchos. |
| ¿Qué es una FK *not trusted*? | Rehabilitada sin verificar: puede haber huérfanos existentes. |
| ¿Cuántas tablas temporales tiene WWI? | 17 tablas con versionado de sistema. |
| ¿Por qué `SUM(CASE)` y no `COUNT(CASE)`? | `COUNT` emite el warning 8153 y ensucia el historial del job. |
| ¿`Sales.Orders` tiene columna de monto? | No. El importe sale de `OrderLines`: `Quantity × UnitPrice`. |
| ¿Criterio para traer una tabla a staging? | Que responda una pregunta de negocio concreta. |

---

## ☑️ Checklist antes de avanzar

- [ ] Restauré WWI y verifiqué que está `ONLINE` **con datos**.
- [ ] Puedo explicar `MOVE`, `RECOVERY` y `REPLACE` sin buscar.
- [ ] Sé elegir el modelo de recuperación y justificarlo.
- [ ] Ejecuté las 12 consultas del kit y guardé los resultados.
- [ ] Identifiqué las tablas relevantes para el proyecto **y las que quedan afuera, con motivo**.
- [ ] Encontré la relación muchos a muchos de productos y entiendo su riesgo.
- [ ] Sé que `Sales.Orders` no tiene montos y qué implica.
- [ ] Perfilé nulos y cardinalidad de las tablas que voy a usar.
- [ ] Tengo el kit de exploración guardado para el próximo proyecto.

---

## 📋 Examen del Módulo 1

### Selección múltiple

**1.** El `RESTORE` falla con "directory lookup failed". La causa más probable es:
a) El `.bak` está corrupto
b) Faltó `WITH MOVE` y apunta a rutas de la máquina original
c) La base ya existe
d) Falta `WITH RECOVERY`

**2.** ¿Cuál cuenta filas sin escanear la tabla?
a) `SELECT COUNT(*) FROM tabla`
b) `SELECT COUNT(1) FROM tabla WITH (NOLOCK)`
c) `sys.partitions` filtrando `index_id IN (0,1)`
d) `SELECT @@ROWCOUNT`

**3.** Una columna `SupplierID` sin FK declarada significa:
a) Que no se relaciona con nada
b) Que la relación existe conceptualmente pero **sin integridad garantizada**
c) Que SQL Server la infiere sola
d) Que es una clave primaria

**4.** ¿Cuántas tablas del catálogo de WWI son temporales con versionado de sistema?
a) 4   b) 12   c) 17   d) 48

**5.** `Warehouse.StockItemStockGroups` tiene 442 filas para 227 productos. Al unirla en una consulta de ventas:
a) No pasa nada, es una relación normal
b) Se pierden filas por el join
c) Las medidas se duplican y las ventas se inflan
d) SQL Server avisa con un warning

**6.** El modelo de recuperación adecuado para una base de staging reconstruible es:
a) FULL, siempre   b) SIMPLE   c) BULK_LOGGED   d) Depende del tamaño

**7.** ¿Por qué usar `SUM(CASE WHEN x IS NULL THEN 1 ELSE 0 END)` en vez de `COUNT(CASE WHEN x IS NULL THEN 1 END)`?
a) Es más rápido
b) `COUNT` da un número distinto
c) `COUNT` emite el warning 8153 que ensucia el historial del job
d) `COUNT` no acepta `CASE`

### Verdadero / Falso

**8.** `SELECT *` muestra las columnas de período de una tabla temporal de sistema.
**9.** Una columna calculada se puede incluir en el `INSERT` de una carga.
**10.** Todo NULL en una tabla origen indica un problema de calidad de datos.
**11.** El conteo de `sys.partitions` es exacto en todo momento.
**12.** Un constraint *not trusted* garantiza que los datos existentes lo cumplen.
**13.** La tabla con más claves foráneas salientes es candidata a tabla de hechos.

### SQL

**14.** Escribí una consulta que devuelva, para cada tabla de WWI, su cantidad de filas y su cantidad de claves foráneas salientes, ordenada de forma que las candidatas a hecho queden arriba.

**15.** Escribí una consulta que detecte valores centinela en `Sales.Orders.CustomerPurchaseOrderNumber`: valores que se repiten sospechosamente, con espacios sobrantes o que parecen marcadores de "sin dato".

### Debugging

**16.** Un compañero escribió esto para inventariar tablas y los números le dan raro — algunas tablas muestran el triple de filas de las que tienen. ¿Cuál es el error?

```sql
SELECT s.name, t.name, p.rows
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.partitions p ON p.object_id = t.object_id
ORDER BY p.rows DESC;
```

**17.** Este `INSERT` a una copia de `Application.People` falla con "The column cannot be modified because it is either a computed column or is the result of a UNION operator". ¿Cómo lo diagnosticás y qué consulta del kit lo habría evitado?

### Análisis de escenario

**18.** Entrás a un proyecto nuevo. La base tiene 300 tablas, no hay documentación y la persona que la diseñó se fue. Te piden un dashboard de ventas para dentro de tres semanas. Describí tu plan para la primera semana, en orden, con lo que hacés cada día y qué entregable produce.

### Diseño

**19.** Explicá por qué el proyecto excluye el schema `Purchasing`, y bajo qué circunstancia concreta esa decisión debería revisarse. Tu respuesta debe mencionar el criterio de la sección 1.13.

