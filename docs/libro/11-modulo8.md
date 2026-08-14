---

# Módulo 8 — Construir el modelo

> **Paso 4 del proyecto, parte 2 de 2**

## 🎯 Objetivos

- Traducir el diseño dimensional a DDL y procedimientos de carga.
- Generar `DimDate` sin depender de una tabla de números externa.
- Aplanar seis tablas del origen en una sola dimensión de cliente.
- Resolver el muchos a muchos de producto en la carga.
- Implementar la búsqueda de claves surrogate correctamente, incluida la variante SCD Tipo 2.
- Ordenar la carga respetando las dependencias.
- Elegir índices apropiados para un warehouse.
- **Cuadrar el modelo contra el origen** y explicar cualquier diferencia.

---

## 📖 Teoría

### 8.1 Del diagrama al DDL

**El orden de construcción tiene una sola regla:** las dimensiones primero, los hechos después. La fact table referencia claves surrogate que **todavía no existen** hasta que las dimensiones estén cargadas.

```
1. dw.DimDate          ← independiente, se genera
2. dw.DimCustomer      ← depende de staging
3. dw.DimProduct       ← depende de staging
4. dw.DimSalesperson   ← depende de staging
5. dw.FactSales        ← depende de las cuatro anteriores
```

**Estructura de archivos:**

```
warehouse/
  01_database.sql          -- CREATE DATABASE WWI_DW (o schema dw en staging)
  02_schemas.sql           -- CREATE SCHEMA dw
  10_DimDate.sql
  11_DimCustomer.sql
  12_DimProduct.sql
  13_DimSalesperson.sql
  20_FactSales.sql
  30_usp_LoadDimDate.sql
  31_usp_LoadDimCustomer.sql
  32_usp_LoadDimProduct.sql
  33_usp_LoadDimSalesperson.sql
  40_usp_LoadFactSales.sql
  50_usp_LoadWarehouse.sql -- orquestador que llama a todos en orden
```

**Numeración por decenas:** deja lugar para insertar pasos intermedios sin renumerar todo. Es una convención chica que ahorra molestias reales.

> **💡 Decisión de arquitectura: ¿base separada o schema `dw` dentro de staging?**
>
> Ambas son defendibles. **Base separada** (`WWI_DW`) da aislamiento completo, permisos y backups independientes, y es lo que harías en producción. **Schema `dw` dentro de `WWI_Staging`** evita nombres de tres partes en la carga de hechos, que es la operación que más joins hace entre capas.
>
> Para este proyecto, **schema `dw` dentro de `WWI_Staging`** es la opción pragmática: menos fricción, y la separación lógica está igual de clara. Documentá la decisión y el criterio para revisarla (si el warehouse crece o si necesita permisos distintos, se separa).

---

### 8.2 `DimDate`

Es la única dimensión que **no viene de ningún origen**: se genera.

```sql
CREATE TABLE dw.DimDate (
    DateKey         INT          NOT NULL PRIMARY KEY,
    FechaCompleta   DATE         NOT NULL,
    Anio            SMALLINT     NOT NULL,
    Trimestre       TINYINT      NOT NULL,
    TrimestreNombre NVARCHAR(10) NOT NULL,
    Mes             TINYINT      NOT NULL,
    MesNombre       NVARCHAR(20) NOT NULL,
    MesAnioNombre   NVARCHAR(20) NOT NULL,
    MesAnioOrden    INT          NOT NULL,
    Dia             TINYINT      NOT NULL,
    DiaSemana       TINYINT      NOT NULL,
    DiaSemanaNombre NVARCHAR(20) NOT NULL,
    SemanaAnio      TINYINT      NOT NULL,
    EsFinDeSemana   BIT          NOT NULL,
    EsDiaHabil      BIT          NOT NULL
);
```

**La generación, sin tabla de números:**

```sql
CREATE OR ALTER PROCEDURE dw.usp_LoadDimDate
    @FechaInicio DATE = '2013-01-01',
    @FechaFin    DATE = '2030-12-31'
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM dw.DimDate)
        RETURN;   -- DimDate se genera una sola vez; no se recarga

    /* Generador de secuencia con CTEs recursivos por multiplicación:
       cada nivel eleva al cuadrado la cantidad de filas.
       4 → 16 → 256 → 65.536, suficiente para 179 años.
       Es más rápido que un CTE recursivo fila por fila. */
    WITH
    L0 AS (SELECT 1 AS c UNION ALL SELECT 1),
    L1 AS (SELECT 1 AS c FROM L0 a CROSS JOIN L0 b),   -- 4
    L2 AS (SELECT 1 AS c FROM L1 a CROSS JOIN L1 b),   -- 16
    L3 AS (SELECT 1 AS c FROM L2 a CROSS JOIN L2 b),   -- 256
    L4 AS (SELECT 1 AS c FROM L3 a CROSS JOIN L3 b),   -- 65.536
    Numeros AS (
        SELECT TOP (DATEDIFF(DAY, @FechaInicio, @FechaFin) + 1)
               ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
        FROM L4
    ),
    Fechas AS (
        SELECT DATEADD(DAY, n, @FechaInicio) AS f FROM Numeros
    )
    INSERT INTO dw.DimDate (
        DateKey, FechaCompleta, Anio, Trimestre, TrimestreNombre,
        Mes, MesNombre, MesAnioNombre, MesAnioOrden, Dia,
        DiaSemana, DiaSemanaNombre, SemanaAnio, EsFinDeSemana, EsDiaHabil
    )
    SELECT
        YEAR(f) * 10000 + MONTH(f) * 100 + DAY(f),          -- 20260810
        f,
        YEAR(f),
        DATEPART(QUARTER, f),
        N'Q' + CAST(DATEPART(QUARTER, f) AS NVARCHAR(1)),
        MONTH(f),
        DATENAME(MONTH, f),
        LEFT(DATENAME(MONTH, f), 3) + N' ' + CAST(YEAR(f) AS NVARCHAR(4)),
        YEAR(f) * 100 + MONTH(f),                            -- 202608
        DAY(f),
        DATEPART(WEEKDAY, f),
        DATENAME(WEEKDAY, f),
        DATEPART(WEEK, f),
        CASE WHEN DATEPART(WEEKDAY, f) IN (1, 7) THEN 1 ELSE 0 END,
        CASE WHEN DATEPART(WEEKDAY, f) IN (1, 7) THEN 0 ELSE 1 END
    FROM Fechas;

    -- Miembro desconocido
    INSERT INTO dw.DimDate (
        DateKey, FechaCompleta, Anio, Trimestre, TrimestreNombre,
        Mes, MesNombre, MesAnioNombre, MesAnioOrden, Dia,
        DiaSemana, DiaSemanaNombre, SemanaAnio, EsFinDeSemana, EsDiaHabil
    )
    VALUES (-1, '1900-01-01', 1900, 1, N'N/D', 1, N'Desconocido',
            N'Desconocido', 190001, 1, 1, N'Desconocido', 1, 0, 0);
END;
GO
```

> **⚠️ `DATEPART(WEEKDAY, ...)` depende de `SET DATEFIRST`**, que a su vez depende del idioma del login. En un servidor en inglés, domingo = 1; en otras configuraciones puede cambiar, y tu columna `EsFinDeSemana` sale mal **sin ningún error**.
>
> Para código robusto, usá una expresión independiente de la configuración:
>
> ```sql
> ((DATEDIFF(DAY, '19000101', f) + 6) % 7) + 1   -- 1 = domingo, siempre
> ```
>
> Es fea y es correcta en cualquier servidor. Lo mismo aplica a `DATENAME(MONTH, ...)`, que devuelve el nombre **en el idioma del login**: en un servidor en inglés vas a obtener "August", no "Agosto". Si querés nombres en español garantizados, usá una tabla de mapeo o `FORMAT(f, 'MMMM', 'es-ES')` — aunque `FORMAT` es notablemente lento en volumen, así que para 6.000 filas está bien y para millones no.

**Por qué el `RETURN` si ya tiene datos:** `DimDate` es estática. Recargarla en cada corrida sería trabajo inútil y —peor— cambiaría las `DateKey` si usara `IDENTITY`, rompiendo todas las referencias de la fact table. Acá `DateKey` se calcula de la fecha, así que sería estable, pero el hábito de no recargar lo inmutable es correcto.

---

### 8.3 `DimCustomer`

Acá se ve el valor real del warehouse: **seis tablas del origen se convierten en una**.

```sql
CREATE TABLE dw.DimCustomer (
    CustomerKey   INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    CustomerID    INT           NOT NULL,     -- clave de negocio
    CustomerName  NVARCHAR(100) NOT NULL,
    Categoria     NVARCHAR(50)  NOT NULL,
    GrupoCompra   NVARCHAR(50)  NOT NULL,
    Ciudad        NVARCHAR(50)  NOT NULL,
    Provincia     NVARCHAR(50)  NOT NULL,
    Pais          NVARCHAR(60)  NOT NULL,
    -- SCD Tipo 2
    ValidoDesde   DATE NOT NULL,
    ValidoHasta   DATE NOT NULL DEFAULT '9999-12-31',
    EsActual      BIT  NOT NULL DEFAULT 1,
    CargadoEn     DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE INDEX IX_DimCustomer_Lookup
    ON dw.DimCustomer (CustomerID, ValidoDesde, ValidoHasta)
    INCLUDE (CustomerKey);
```

**La consulta que aplana la jerarquía:**

```sql
SELECT
    c.CustomerID,
    c.CustomerName,
    ISNULL(cc.CustomerCategoryName, N'Sin categoria') AS Categoria,
    ISNULL(bg.BuyingGroupName,      N'Sin grupo')     AS GrupoCompra,
    ISNULL(ci.CityName,             N'Desconocida')   AS Ciudad,
    ISNULL(sp.StateProvinceName,    N'Desconocida')   AS Provincia,
    ISNULL(co.CountryName,          N'Desconocido')   AS Pais
FROM WideWorldImporters.Sales.Customers c
LEFT JOIN WideWorldImporters.Sales.CustomerCategories cc
       ON cc.CustomerCategoryID = c.CustomerCategoryID
LEFT JOIN WideWorldImporters.Sales.BuyingGroups bg
       ON bg.BuyingGroupID = c.BuyingGroupID
LEFT JOIN WideWorldImporters.Application.Cities ci
       ON ci.CityID = c.DeliveryCityID
LEFT JOIN WideWorldImporters.Application.StateProvinces sp
       ON sp.StateProvinceID = ci.StateProvinceID
LEFT JOIN WideWorldImporters.Application.Countries co
       ON co.CountryID = sp.CountryID;
```

**Tres decisiones visibles en ese código:**

1. **`LEFT JOIN` en todos lados.** `BuyingGroupID` es nulo para muchos clientes (no todos pertenecen a un grupo de compra). Un `INNER JOIN` los descartaría y perderías clientes reales.
2. **`ISNULL` con texto descriptivo, no con NULL.** En un dashboard, un NULL aparece como "(en blanco)". `'Sin grupo'` comunica que **la ausencia es la información**, no que falte el dato.
3. **La jerarquía geográfica queda aplanada** en tres columnas de la misma fila. Eso es el esquema estrella en acción.

**La carga con SCD Tipo 2:**

```sql
CREATE OR ALTER PROCEDURE dw.usp_LoadDimCustomer
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Hoy DATE = CAST(SYSUTCDATETIME() AS DATE);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Snapshot actual del origen, aplanado
        SELECT ... INTO #Origen FROM ... ;   -- la consulta de arriba

        /* PASO 1 — Cerrar las versiones cuyos atributos cambiaron.
           Se comparan los atributos con EXISTS/EXCEPT en vez de con
           una cadena de <> porque EXCEPT trata NULL = NULL como igual,
           evitando falsos cambios en columnas nulables. */
        UPDATE d
        SET ValidoHasta = @Hoy, EsActual = 0
        FROM dw.DimCustomer d
        JOIN #Origen o ON o.CustomerID = d.CustomerID
        WHERE d.EsActual = 1
          AND EXISTS (
              SELECT o.CustomerName, o.Categoria, o.GrupoCompra,
                     o.Ciudad, o.Provincia, o.Pais
              EXCEPT
              SELECT d.CustomerName, d.Categoria, d.GrupoCompra,
                     d.Ciudad, d.Provincia, d.Pais
          );

        /* PASO 2 — Insertar la versión nueva de los que cambiaron
           y los clientes que aparecen por primera vez. */
        INSERT INTO dw.DimCustomer (
            CustomerID, CustomerName, Categoria, GrupoCompra,
            Ciudad, Provincia, Pais, ValidoDesde, ValidoHasta, EsActual)
        SELECT
            o.CustomerID, o.CustomerName, o.Categoria, o.GrupoCompra,
            o.Ciudad, o.Provincia, o.Pais, @Hoy, '9999-12-31', 1
        FROM #Origen o
        WHERE NOT EXISTS (
            SELECT 1 FROM dw.DimCustomer d
            WHERE d.CustomerID = o.CustomerID AND d.EsActual = 1
        );

        -- Miembro desconocido, solo la primera vez
        IF NOT EXISTS (SELECT 1 FROM dw.DimCustomer WHERE CustomerKey = -1)
        BEGIN
            SET IDENTITY_INSERT dw.DimCustomer ON;
            INSERT INTO dw.DimCustomer (
                CustomerKey, CustomerID, CustomerName, Categoria, GrupoCompra,
                Ciudad, Provincia, Pais, ValidoDesde, ValidoHasta, EsActual)
            VALUES (-1, -1, N'Desconocido', N'Desconocido', N'Desconocido',
                    N'Desconocido', N'Desconocido', N'Desconocido',
                    '1900-01-01', '9999-12-31', 1);
            SET IDENTITY_INSERT dw.DimCustomer OFF;
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
```

> **⚠️ El orden de los dos pasos es obligatorio, y es sutil.** Primero se cierran las versiones viejas (`UPDATE`), después se insertan las nuevas. Si se hiciera al revés, el `UPDATE` cerraría también la fila recién insertada, porque también tendría `EsActual = 1` y sus atributos serían iguales a los del origen... es decir, no entraría por el `EXISTS/EXCEPT`. El resultado sería impredecible según el plan de ejecución.
>
> **Y el `EXCEPT` en lugar de `<>` no es un capricho:** con `d.GrupoCompra <> o.GrupoCompra`, una fila donde ambos son `NULL` da `UNKNOWN` y **no se detecta el cambio**; y una fila donde uno es NULL y el otro no, tampoco. `EXCEPT` compara tratando NULL como un valor más, que es lo que necesitás para detección de cambios. Es una de esas diferencias que producen bugs de datos silenciosos durante meses.

---

### 8.4 `DimProduct` y el muchos a muchos

```sql
CREATE TABLE dw.DimProduct (
    ProductKey         INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    StockItemID        INT           NOT NULL,
    ProductName        NVARCHAR(100) NOT NULL,
    CategoriaPrincipal NVARCHAR(50)  NOT NULL,
    Color              NVARCHAR(20)  NOT NULL,
    TipoPaquete        NVARCHAR(50)  NOT NULL,
    Marca              NVARCHAR(50)  NOT NULL,
    PrecioLista        DECIMAL(18,2) NULL,
    CostoUnitario      DECIMAL(18,2) NULL,
    EsPerecedero       BIT           NOT NULL,
    CargadoEn          DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
);
```

**La resolución del muchos a muchos, con la regla explícita:**

```sql
/* Regla de categoría primaria: se toma el grupo de menor StockGroupID.
   ⚠️ Es una regla ARBITRARIA elegida por simplicidad. Lo correcto sería
   que el negocio defina cuál es la categoría principal de cada producto.
   Documentado acá para que quien lo lea sepa que es una decisión pendiente
   de confirmación, y no un hecho del dominio. */
WITH CategoriaPrimaria AS (
    SELECT
        sisg.StockItemID,
        sg.StockGroupName,
        ROW_NUMBER() OVER (PARTITION BY sisg.StockItemID
                           ORDER BY sg.StockGroupID) AS rn
    FROM WideWorldImporters.Warehouse.StockItemStockGroups sisg
    JOIN WideWorldImporters.Warehouse.StockGroups sg
      ON sg.StockGroupID = sisg.StockGroupID
)
SELECT
    si.StockItemID,
    si.StockItemName,
    ISNULL(cp.StockGroupName, N'Sin categoria') AS CategoriaPrincipal,
    ISNULL(c.ColorName,       N'Sin color')     AS Color,
    ISNULL(pt.PackageTypeName,N'Sin tipo')      AS TipoPaquete,
    ISNULL(si.Brand,          N'Sin marca')     AS Marca,
    si.RecommendedRetailPrice,
    si.UnitPrice,
    si.IsChillerStock
FROM WideWorldImporters.Warehouse.StockItems si
LEFT JOIN CategoriaPrimaria cp ON cp.StockItemID = si.StockItemID AND cp.rn = 1
LEFT JOIN WideWorldImporters.Warehouse.Colors c
       ON c.ColorID = si.ColorID
LEFT JOIN WideWorldImporters.Warehouse.PackageTypes pt
       ON pt.PackageTypeID = si.UnitPackageID;
```

**`ROW_NUMBER() OVER (PARTITION BY ... ORDER BY ...)` con `rn = 1`** es el patrón estándar para "elegir una fila por grupo". Vale memorizarlo: aparece constantemente en ETL.

> **✅ El resultado clave: 227 productos entran, 227 filas salen.** Sin fan-out posible, porque la categoría se resolvió **antes** de tocar la fact table. Verificalo siempre después de cargar una dimensión que involucre un muchos a muchos.

**`DimProduct` usa SCD Tipo 1** (sobrescribir). Justificación: los atributos de un producto —color, tipo de empaque, marca— rara vez cambian de forma analíticamente significativa en este negocio, y cuando cambian suele ser una corrección. Si el negocio pidiera analizar "ventas por el color que tenía el producto entonces", habría que pasar a Tipo 2.

---

### 8.5 `DimSalesperson`

La más simple, y tiene un detalle que enseña algo:

```sql
CREATE TABLE dw.DimSalesperson (
    SalespersonKey INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    PersonID       INT           NOT NULL,
    NombreCompleto NVARCHAR(50)  NOT NULL,
    NombrePreferido NVARCHAR(50) NOT NULL,
    EsVendedor     BIT           NOT NULL,
    CargadoEn      DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
);
```

```sql
SELECT PersonID, FullName, PreferredName, IsSalesperson
FROM WideWorldImporters.Application.People
WHERE IsSalesperson = 1;
```

> **⚠️ El detalle: ¿filtrar `IsSalesperson = 1` o traer las 1.111 personas?**
>
> Filtrar parece obvio y **tiene un riesgo**: si alguien dejó de ser vendedor, `IsSalesperson` pasa a 0, la persona **desaparece de la dimensión**, y todas sus ventas históricas quedan huérfanas → van a "Desconocido". Las ventas históricas de ese vendedor se pierden del análisis.
>
> **La solución correcta:** traer todas las personas que **alguna vez** aparecieron como vendedor en un pedido:
>
> ```sql
> SELECT p.PersonID, p.FullName, p.PreferredName, p.IsSalesperson
> FROM WideWorldImporters.Application.People p
> WHERE p.IsSalesperson = 1
>    OR EXISTS (SELECT 1 FROM WWI_Staging.Sales.Orders o
>               WHERE o.SalespersonPersonID = p.PersonID);
> ```
>
> Este es un ejemplo perfecto de por qué el modelado dimensional requiere pensar en **el tiempo**, no solo en el estado actual. Es la misma lección de SCD, aplicada a la existencia de la fila en lugar de a sus atributos.

---

### 8.6 `FactSales`

```sql
CREATE TABLE dw.FactSales (
    /* GRANO: una fila por cada línea de pedido de venta. */
    SalesKey       BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,

    -- Claves foráneas a dimensiones (surrogate, NOT NULL)
    DateKey        INT NOT NULL
        CONSTRAINT FK_FactSales_Date        REFERENCES dw.DimDate(DateKey),
    CustomerKey    INT NOT NULL
        CONSTRAINT FK_FactSales_Customer    REFERENCES dw.DimCustomer(CustomerKey),
    ProductKey     INT NOT NULL
        CONSTRAINT FK_FactSales_Product     REFERENCES dw.DimProduct(ProductKey),
    SalespersonKey INT NOT NULL
        CONSTRAINT FK_FactSales_Salesperson REFERENCES dw.DimSalesperson(SalespersonKey),

    -- Dimensiones degeneradas
    OrderID        INT NOT NULL,
    OrderLineID    INT NOT NULL,

    -- Medidas
    Quantity       INT           NOT NULL,   -- aditiva
    UnitPrice      DECIMAL(18,2) NOT NULL,   -- NO aditiva
    TaxRate        DECIMAL(18,3) NOT NULL,   -- NO aditiva
    SalesAmount    DECIMAL(18,2) NOT NULL,   -- aditiva
    TaxAmount      DECIMAL(18,2) NOT NULL,   -- aditiva
    TotalAmount    DECIMAL(18,2) NOT NULL,   -- aditiva

    LoadBatchId    UNIQUEIDENTIFIER NOT NULL,
    CargadoEn      DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
```

**Tres decisiones que vale explicar:**

**`BIGINT` para `SalesKey`.** 231.412 filas caben de sobra en `INT`, pero una fact table crece indefinidamente y `INT` se agota en 2.147 millones. Cambiar el tipo de la PK de una tabla grande en producción es una operación dolorosa. **Es la única columna donde vale la pena sobredimensionar de entrada.**

**`SalesAmount` precalculada** en vez de calcular `Quantity * UnitPrice` al consultar. Se guarda porque (a) se consulta constantemente, (b) evita que cada analista aplique su propia fórmula, y (c) el costo de almacenamiento es trivial. **Es desnormalización deliberada**, coherente con 6.7.

**Todas las FKs `NOT NULL`.** Es posible gracias al miembro desconocido: si no encontramos la dimensión, va a `-1`, nunca a NULL. Eso permite declarar las FKs, que documentan el modelo y ayudan al optimizador.

---

### 8.7 Búsqueda de claves surrogate

**El corazón de la carga de hechos.** Cada fila de staging trae claves de negocio; hay que traducirlas a claves surrogate.

```sql
CREATE OR ALTER PROCEDURE dw.usp_LoadFactSales
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @BatchId    UNIQUEIDENTIFIER = NEWID();
    DECLARE @RowsLoaded INT;

    INSERT INTO etl.LoadBatch (LoadBatchId, SchemaName, TableName, Status)
    VALUES (@BatchId, N'dw', N'FactSales', N'Running');

    BEGIN TRY
        BEGIN TRANSACTION;

        TRUNCATE TABLE dw.FactSales;

        INSERT INTO dw.FactSales (
            DateKey, CustomerKey, ProductKey, SalespersonKey,
            OrderID, OrderLineID,
            Quantity, UnitPrice, TaxRate, SalesAmount, TaxAmount, TotalAmount,
            LoadBatchId
        )
        SELECT
            -- DateKey se calcula, no se busca: es determinística
            ISNULL(CONVERT(INT, CONVERT(CHAR(8), o.OrderDate, 112)), -1),
            ISNULL(dc.CustomerKey,    -1),
            ISNULL(dp.ProductKey,     -1),
            ISNULL(ds.SalespersonKey, -1),

            ol.OrderID,
            ol.OrderLineID,

            ol.Quantity,
            ol.UnitPrice,
            ol.TaxRate,
            ol.Quantity * ol.UnitPrice                                  AS SalesAmount,
            ol.Quantity * ol.UnitPrice * ol.TaxRate / 100.0             AS TaxAmount,
            ol.Quantity * ol.UnitPrice * (1 + ol.TaxRate / 100.0)       AS TotalAmount,

            @BatchId
        FROM Sales.OrderLines ol
        JOIN Sales.Orders o ON o.OrderID = ol.OrderID

        /* ⚠️ SIEMPRE LEFT JOIN. Un INNER JOIN descartaría en silencio
           las ventas cuya dimensión falte, y los totales no cuadrarían
           sin que nada lo indique. */
        LEFT JOIN dw.DimCustomer dc
               ON dc.CustomerID = o.CustomerID
              /* SCD Tipo 2: la versión VIGENTE AL MOMENTO DE LA VENTA,
                 no la actual. Este es el punto donde SCD Tipo 2 se
                 implementa bien o se arruina. */
              AND o.OrderDate >= dc.ValidoDesde
              AND o.OrderDate <  dc.ValidoHasta

        LEFT JOIN dw.DimProduct dp
               ON dp.StockItemID = ol.StockItemID   -- Tipo 1: sin fechas

        LEFT JOIN dw.DimSalesperson ds
               ON ds.PersonID = o.SalespersonPersonID;

        SET @RowsLoaded = @@ROWCOUNT;

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

    EXEC dw.usp_ValidateFactSales @BatchId;
END;
GO
```

**Los cuatro puntos críticos de esa consulta:**

**1 — `DateKey` se calcula, no se busca.** `CONVERT(CHAR(8), fecha, 112)` da `'20260810'`. El estilo 112 es `AAAAMMDD` sin separadores. Es determinístico y evita un join.

**2 — La búsqueda de SCD Tipo 2 usa la fecha del evento.** Las dos condiciones de fecha son lo que hace que un hecho de 2023 encuentre la versión del cliente que estaba vigente en 2023.

> **⚠️ El bug más sutil de todo el modelado dimensional:**
>
> ```sql
> LEFT JOIN dw.DimCustomer dc
>     ON dc.CustomerID = o.CustomerID AND dc.EsActual = 1   -- ❌
> ```
>
> Esto **compila, corre, y produce números plausibles**. Pero todos los hechos apuntan a la versión actual, así que los reportes históricos cambian cuando un cliente cambia de categoría — **exactamente el problema que SCD Tipo 2 venía a resolver.**
>
> El modelo *parece* Tipo 2 (tiene las columnas, tiene las versiones) y *se comporta* como Tipo 1. Es casi imposible de detectar mirando el código o los resultados: solo se nota cuando alguien compara un reporte de hace meses con el mismo reporte de hoy.

**3 — Uso de `>=` y `<`, no `BETWEEN`.** Con `BETWEEN ValidoDesde AND ValidoHasta`, una venta ocurrida exactamente el día del cambio **coincide con dos versiones** y la fila se duplica. Los rangos semiabiertos `[desde, hasta)` eliminan la ambigüedad. Es la misma razón por la que se usan rangos semiabiertos para filtrar por fechas con hora.

**4 — `ISNULL(..., -1)` en las cuatro claves.** Sin eso, un `LEFT JOIN` sin coincidencia daría NULL y violaría el `NOT NULL` de la columna, haciendo fallar toda la carga por una fila huérfana.

---

### 8.8 Índices en un Data Warehouse

> ➕ **Tema adicional recomendado:** estrategia de índices para OLAP
> **Por qué necesito aprenderlo:** los índices de un warehouse son distintos de los de un OLTP, y aplicar la intuición de OLTP produce modelos lentos.
> **En qué parte del proyecto lo utilizaremos:** después de cargar el modelo, antes de conectar Power BI.

**En OLTP:** muchos índices no agrupados, selectivos, para buscar pocas filas.

**En OLAP:** pocos índices, orientados a escanear muchas filas de pocas columnas.

**Recomendación práctica:**

```sql
-- Dimensiones: PK agrupada (por la surrogate) + índice de búsqueda
CREATE INDEX IX_DimCustomer_Lookup
    ON dw.DimCustomer (CustomerID, ValidoDesde, ValidoHasta)
    INCLUDE (CustomerKey);

CREATE INDEX IX_DimProduct_Lookup
    ON dw.DimProduct (StockItemID) INCLUDE (ProductKey);
```

Esos índices no son para las consultas del dashboard: son para **la carga**, que hace millones de búsquedas por clave de negocio. Sin ellos, la carga de hechos hace un escaneo completo de la dimensión por cada fila.

**Para la fact table — índice columnstore agrupado:**

```sql
CREATE CLUSTERED COLUMNSTORE INDEX CCI_FactSales ON dw.FactSales;
```

> **💡 Concepto clave — *clustered columnstore index*.** Almacena los datos **por columna** en lugar de por fila, y los comprime.
>
> **Por qué es transformador en analítica:**
> - **Compresión de 10x o más.** Los valores de una columna se parecen entre sí, así que comprimen muy bien.
> - **Eliminación de segmentos.** Guarda mínimo y máximo por bloque de un millón de filas, y salta bloques enteros que no pueden contener el resultado.
> - **Solo lee las columnas que la consulta pide.** Con 15 columnas y una consulta que usa 4, lee el 27%.
> - **Modo por lotes** (*batch mode*): procesa 900 filas por operación de CPU en lugar de una.
>
> **Cuándo NO usarlo:** en tablas chicas (menos de ~100.000 filas el beneficio es marginal), o cuando hay muchas búsquedas puntuales de una sola fila.
>
> Con 231.412 filas, tu `FactSales` está en el límite inferior. **Ponelo igual**: el objetivo acá es aprender la técnica, y el comportamiento se ve aunque la ganancia sea modesta.

> **⚠️ Un columnstore agrupado y una PK agrupada son incompatibles**: una tabla tiene un solo índice agrupado. Si creás el columnstore, la `PRIMARY KEY` tiene que ser no agrupada (`PRIMARY KEY NONCLUSTERED`). Es un error de despliegue común.

---

### 8.9 Verificar el modelo

**Esta sección no es opcional.** Un modelo sin cuadrar es un modelo en el que no podés confiar.

**Verificación 1 — Conteo de filas.**

```sql
SELECT
    (SELECT COUNT(*) FROM Sales.OrderLines) AS Staging,
    (SELECT COUNT(*) FROM dw.FactSales)     AS Warehouse;
-- Deben ser IGUALES: 231.412
```

Si el warehouse tiene **menos**, hay un `INNER JOIN` en algún lado o un filtro escondido.
Si tiene **más**, hay fan-out — probablemente el join a `DimCustomer` con rangos que se solapan.

**Verificación 2 — Suma de la medida principal.**

```sql
SELECT
    (SELECT SUM(Quantity * UnitPrice) FROM Sales.OrderLines) AS Staging,
    (SELECT SUM(SalesAmount)          FROM dw.FactSales)     AS Warehouse;
-- Deben ser IGUALES
```

**Es la verificación más importante del módulo.** Si los conteos cuadran pero las sumas no, hay un error de cálculo o de tipos.

**Verificación 3 — Huérfanos asignados a desconocido.**

```sql
SELECT
    SUM(CASE WHEN CustomerKey    = -1 THEN 1 ELSE 0 END) AS ClienteDesconocido,
    SUM(CASE WHEN ProductKey     = -1 THEN 1 ELSE 0 END) AS ProductoDesconocido,
    SUM(CASE WHEN SalespersonKey = -1 THEN 1 ELSE 0 END) AS VendedorDesconocido,
    SUM(CASE WHEN DateKey        = -1 THEN 1 ELSE 0 END) AS FechaDesconocida,
    COUNT(*)                                             AS Total
FROM dw.FactSales;
```

> **✅ Un valor distinto de cero acá no es necesariamente un error — es información.** Significa que hay hechos cuya dimensión no se encontró. Lo importante es que **el número sea conocido, esperado y monitoreado**. Si sube de un día para otro, algo cambió en el origen.
>
> El fracaso no es tener huérfanos: es **no saber cuántos tenés**.

**Verificación 4 — Sin duplicación por SCD.**

```sql
SELECT OrderLineID, COUNT(*) AS Veces
FROM dw.FactSales
GROUP BY OrderLineID
HAVING COUNT(*) > 1;
-- Debe devolver VACÍO
```

Si devuelve filas, los rangos de validez de alguna dimensión **se solapan**. Es el síntoma de haber usado `BETWEEN` en lugar de `>=` y `<`.

**Verificación 5 — Integridad de las dimensiones.**

```sql
-- Ninguna dimensión debería tener dos versiones actuales del mismo negocio
SELECT CustomerID, COUNT(*) AS VersionesActuales
FROM dw.DimCustomer
WHERE EsActual = 1
GROUP BY CustomerID
HAVING COUNT(*) > 1;
-- Debe devolver VACÍO
```

---

## ⚠️ Errores comunes

**Cargar hechos antes que dimensiones.** Todas las claves caen en `-1`.

**`INNER JOIN` en la carga de hechos.** Pérdida silenciosa.

**Buscar la dimensión SCD2 con `EsActual = 1`.** El modelo parece Tipo 2 y actúa como Tipo 1.

**`BETWEEN` en los rangos de validez.** Duplica las filas del día del cambio.

**Insertar antes de cerrar en SCD Tipo 2.** El `UPDATE` afecta la fila recién insertada.

**Comparar atributos con `<>` en vez de `EXCEPT`.** Los NULLs no se detectan como cambio.

**`INT` para la PK de la fact table.** Se agota; migrar después es doloroso.

**Filtrar `IsSalesperson = 1` sin considerar exvendedores.** Las ventas históricas quedan huérfanas.

**Olvidar el miembro desconocido.** Las FKs `NOT NULL` hacen fallar la carga con una sola fila huérfana.

**No cuadrar contra el origen.** Sin las cinco verificaciones, no sabés si el modelo está bien.

**Columnstore agrupado con PK agrupada.** Incompatibles: la PK debe ser `NONCLUSTERED`.

**Confiar en `DATEPART(WEEKDAY)` o `DATENAME(MONTH)` sin controlar la configuración regional.**

---

## 🧠 Preguntas de comprensión

1. El conteo de `FactSales` da 245.000 y staging tiene 231.412. ¿Qué pasó y dónde lo buscás?
2. ¿Por qué la búsqueda de `DimCustomer` usa dos condiciones de fecha y no `EsActual = 1`?
3. ¿Por qué `>=` y `<` en lugar de `BETWEEN`?
4. En SCD Tipo 2, ¿por qué hay que cerrar antes de insertar?
5. ¿Por qué `DateKey` se calcula en vez de buscarse en `DimDate`?
6. 4.500 filas con `CustomerKey = -1`. ¿Es un error? ¿Qué hacés?
7. ¿Por qué el índice de búsqueda de `DimCustomer` incluye `ValidoDesde` y `ValidoHasta`?

---

## 📝 Ejercicios

**🟢 Básico.** Creá y cargá `DimDate` para 2013–2030. Verificá que tiene la cantidad correcta de filas más el miembro desconocido.

**🟢 Básico.** Cargá las cuatro dimensiones y verificá que `DimProduct` tiene exactamente 227 filas más el desconocido — es decir, que resolviste el muchos a muchos.

**🟡 Intermedio.** Cargá `FactSales` y corré las **cinco** verificaciones de 8.9. Documentá cualquier diferencia y su causa.

**🟡 Intermedio.** Escribí `dw.usp_ValidateFactSales`: cuadre contra staging, conteo de huérfanos por dimensión, medidas negativas, y duplicados por `OrderLineID`.

**🔴 Avanzado.** Demostrá el bug de SCD Tipo 2 empíricamente: cambiá la categoría de un cliente en el origen, recargá la dimensión, recargá los hechos con **ambas** versiones de la búsqueda (por `EsActual` y por rango de fechas), y compará el reporte de ventas por categoría del año anterior. Documentá la diferencia.

**🔴 Avanzado.** Convertí la carga de `FactSales` a **incremental**: solo las líneas de pedidos modificados desde la última carga, con marca de agua. Cuidá la idempotencia — recargar el mismo día dos veces no debe duplicar.

**🧠 Reto.** Implementá `DimCustomer` como **SCD Tipo 6 (híbrido)**: Tipo 2 para la historia más columnas `CategoriaActual`, que permiten analizar tanto "como era entonces" como "como es ahora" desde el mismo modelo. Explicá qué consulta usa cada una y por qué el negocio pide las dos.

---

## 📌 Resumen

- Dimensiones primero, hechos después. Siempre.
- `DimDate` se genera, se carga una vez, y `DateKey` se calcula de la fecha.
- Aplanar la jerarquía geográfica es el esquema estrella en acción; usá `LEFT JOIN` + `ISNULL` con texto descriptivo.
- El muchos a muchos se resuelve **antes** de la fact table, con `ROW_NUMBER()`.
- **La búsqueda SCD Tipo 2 usa la fecha del evento**, con rangos semiabiertos `[desde, hasta)`.
- SCD Tipo 2: cerrar primero, insertar después. Comparar con `EXCEPT`, no con `<>`.
- Miembro desconocido `-1` + `LEFT JOIN` + `ISNULL` = ninguna venta perdida.
- `BIGINT` para la PK de la fact table.
- Columnstore agrupado para la fact table; índices de búsqueda para las dimensiones.
- **Las cinco verificaciones no son opcionales.**

---

## ☑️ Checklist antes de avanzar

- [ ] Las cuatro dimensiones están cargadas, cada una con su miembro `-1`.
- [ ] `DimProduct` tiene 227 filas + 1: resolví el muchos a muchos.
- [ ] `FactSales` tiene exactamente 231.412 filas.
- [ ] La suma de `SalesAmount` cuadra con staging al centavo.
- [ ] No hay duplicados por `OrderLineID`.
- [ ] Sé cuántos huérfanos hay por dimensión y por qué.
- [ ] La búsqueda de `DimCustomer` usa rangos de fecha, no `EsActual`.
- [ ] Ningún cliente tiene dos versiones actuales.
- [ ] Los índices de búsqueda están creados.

