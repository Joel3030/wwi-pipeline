---

# 🔐 Soluciones — Volumen II

---

## Módulo 6

**1.** La causa es el **fan-out** en el join a `Warehouse.StockItemStockGroups`. Con 442 asignaciones para 227 productos, cada línea de pedido se duplica una vez por cada grupo al que pertenece su producto. Las medidas (`Quantity * UnitPrice`) se multiplican con las filas.

**2.** Porque la normalización protege contra **anomalías de actualización**, y esas anomalías requieren **actualizaciones concurrentes no coordinadas** por parte de muchos usuarios. En un warehouse, el único que escribe es el proceso de carga, de forma controlada y atómica: escribe `CityName`, `StateProvinceName` y `CountryName` juntos, en la misma operación. **El riesgo que la normalización previene no existe**, así que el costo que impone (más joins) no compra nada.

**3.** Está siguiendo a **Inmon** sin saberlo. Respuesta: no es un error, es una escuela legítima — pero para un solo origen y un solo proceso de negocio, el costo no se justifica. Inmon tiene sentido cuando hay muchos orígenes con definiciones en conflicto y la integración es el problema principal. Acá el problema es la usabilidad analítica, y para eso Kimball entrega valor mucho antes. Además, un warehouse normalizado le pasa el problema de los ocho joins al consumidor, que es exactamente lo que vinimos a resolver.

**4.** OLTP lee **pocas filas con muchas columnas** (un pedido completo: todos sus campos). OLAP lee **pocas columnas de muchísimas filas** (el importe de millones de ventas). El almacenamiento por filas favorece al primero; el almacenamiento **por columnas** favorece al segundo, porque solo trae del disco las columnas que la consulta pide y comprime mejor (valores similares juntos). La tecnología que lo aprovecha es el **índice columnstore**.

---

## Módulo 7

**1.** **b)** El grano.

**2.** **c)** Stock disponible: se suma por producto y depósito, pero **no por tiempo**.

**3.** **b)** Con SCD Tipo 2 hay varias filas por entidad, así que la clave de negocio se repite y no puede ser la PK.

**4.** **b)** Triplica sus ventas.

**5.** **b)** Sobrescribe y pierde la historia.

**6.** **b)** Permite `BETWEEN` (o rangos) sin tratar NULL como caso especial.

**7.** **b)** Un identificador guardado en la fact table sin dimensión propia.

**8.** **b)** `LEFT JOIN` con miembro desconocido.

**9.** **F** — La agregación es irreversible. Una vez que sumaste, la información individual se perdió.

**10.** **F** — `UnitPrice` es no aditiva. Sumar precios unitarios no significa nada.

**11.** **F** — Al revés: VertiPaq está optimizado para estrella, y Microsoft recomienda aplanar.

**12.** **V** — Es el único de los tres tipos que se actualiza.

**13.** **V** — Con `LEFT JOIN` desde `DimDate`, los días sin ventas aparecen con cero en vez de desaparecer del gráfico.

**14.** **F** — Promediar porcentajes ignora la ponderación por volumen. Hay que guardar los componentes aditivos y recalcular el ratio.

**15.** **V** — Esa es exactamente la propiedad que da SCD Tipo 2: los hechos apuntan a la versión vigente en su momento, así que el reporte histórico es estable.

**16.**

```sql
CREATE TABLE dw.FactSales (
    /* ═══════════════════════════════════════════════════════════
       GRANO: una fila por cada línea de pedido de venta.
       Fuente: WWI_Staging.Sales.OrderLines (231.412 filas).
       ═══════════════════════════════════════════════════════════ */
    SalesKey BIGINT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_FactSales PRIMARY KEY NONCLUSTERED,

    -- ── Claves surrogate (NOT NULL gracias al miembro desconocido) ──
    DateKey        INT NOT NULL
        CONSTRAINT FK_FactSales_Date        REFERENCES dw.DimDate(DateKey),
    CustomerKey    INT NOT NULL
        CONSTRAINT FK_FactSales_Customer    REFERENCES dw.DimCustomer(CustomerKey),
    ProductKey     INT NOT NULL
        CONSTRAINT FK_FactSales_Product     REFERENCES dw.DimProduct(ProductKey),
    SalespersonKey INT NOT NULL
        CONSTRAINT FK_FactSales_Salesperson REFERENCES dw.DimSalesperson(SalespersonKey),

    -- ── Dimensiones degeneradas: identificadores sin dimensión propia ──
    OrderID     INT NOT NULL,
    OrderLineID INT NOT NULL,

    -- ── Medidas ──
    Quantity    INT           NOT NULL,   -- aditiva
    UnitPrice   DECIMAL(18,2) NOT NULL,   -- NO aditiva (es un ratio por unidad)
    TaxRate     DECIMAL(18,3) NOT NULL,   -- NO aditiva (es un porcentaje)
    SalesAmount DECIMAL(18,2) NOT NULL,   -- aditiva
    TaxAmount   DECIMAL(18,2) NOT NULL,   -- aditiva
    TotalAmount DECIMAL(18,2) NOT NULL,   -- aditiva

    -- ── Auditoría ──
    LoadBatchId UNIQUEIDENTIFIER NOT NULL,
    CargadoEn   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT UQ_FactSales_Grano UNIQUE (OrderLineID)   -- el grano, hecho constraint
);

CREATE CLUSTERED COLUMNSTORE INDEX CCI_FactSales ON dw.FactSales;
```

Tres detalles: la PK es `NONCLUSTERED` porque el columnstore ocupa el índice agrupado; `UQ_FactSales_Grano` sobre `OrderLineID` **hace cumplir el grano físicamente** (impide duplicados por un error de SCD); y `BIGINT` en la PK porque una fact table crece indefinidamente.

**17.**

```sql
SELECT
    ol.OrderLineID,
    o.OrderDate,
    ISNULL(dc.CustomerKey, -1) AS CustomerKey
FROM Sales.OrderLines ol
JOIN Sales.Orders o ON o.OrderID = ol.OrderID
LEFT JOIN dw.DimCustomer dc
       ON dc.CustomerID  = o.CustomerID
      AND o.OrderDate   >= dc.ValidoDesde     -- rango semiabierto [desde, hasta)
      AND o.OrderDate   <  dc.ValidoHasta;
```

**Los tres puntos:** (a) se une por la **fecha del evento**, no por `EsActual`; (b) rangos **semiabiertos** para que una venta del día del cambio no coincida con dos versiones; (c) `LEFT JOIN` + `ISNULL(-1)` para no perder ventas de clientes que no están en la dimensión.

**18.** **Ambas opciones son válidas y la decisión depende del grano.**

**Opción A — Filas negativas en `FactSales`.**

Una devolución es "una venta con signo invertido". El grano se mantiene: una fila por línea de movimiento. Se agrega un atributo `TipoTransaccion` ('Venta' / 'Devolución') o una `DimTipoTransaccion`.

✅ `SUM(SalesAmount)` da automáticamente las **ventas netas**, que es lo que el negocio suele querer · Un solo lugar donde mirar · Todas las dimensiones se reutilizan

❌ Hay que tener cuidado con `COUNT(*)`: cuenta ventas y devoluciones juntas · "Ventas brutas" requiere filtrar

**Opción B — Fact table separada `FactReturns`.**

✅ Métricas propias de la devolución (motivo, estado del producto, días transcurridos) que no tienen sentido en una venta · Grano potencialmente distinto

❌ Toda métrica neta requiere combinar dos tablas · Más complejidad en el modelo y en Power BI

**Recomendación:** **opción A**, si la devolución tiene el mismo grano (una línea de producto devuelto) y las mismas dimensiones. Es el caso habitual en retail y es lo que hace la mayoría de los warehouses.

**Opción B** si la devolución tiene atributos propios significativos —motivo de devolución, quién la autorizó, estado del producto— **y** el negocio quiere analizar el proceso de devolución en sí, no solo su impacto en las ventas. En ese caso son **dos procesos de negocio distintos**, y el paso 1 de Kimball dice que cada proceso tiene su fact table.

**19.** Modelo para streaming:

**Proceso de negocio:** la reproducción de contenido.

**Grano:** *una fila por cada evento de reproducción de un contenido por un usuario.* (La alternativa "una fila por sesión de visualización" agrega y pierde el detalle de pausas y reanudaciones.)

**Dimensiones:**
- `DimFecha` y `DimHora` (separadas: la hora tiene 24 valores y combinarlas con la fecha multiplicaría `DimFecha` por 24)
- `DimUsuario` — plan, país, fecha de alta, SCD Tipo 2 para el plan
- `DimContenido` — título, tipo (película/serie), año, duración
- `DimDispositivo` — tipo, sistema operativo, marca
- `DimGenero` — **acá está el muchos a muchos**

**Medidas:**
- `SegundosReproducidos` — aditiva
- `PorcentajeCompletado` — **no aditiva** (es un ratio; guardar `SegundosReproducidos` y `DuracionContenido` y calcular)
- `EsReproduccionCompleta` (BIT) — aditiva al sumarla, da la cantidad de reproducciones completas

**Medida semi-aditiva:** **suscriptores activos**. Se puede sumar por país y por plan, pero **no por tiempo**: los suscriptores activos de enero más los de febrero no dan los del bimestre (son casi las mismas personas). Requiere `DISTINCTCOUNT` o el último valor del período.

**Muchos a muchos:** un contenido pertenece a varios géneros ("Acción", "Ciencia ficción", "Thriller"). Soluciones:
- **Género primario** en `DimContenido` — simple, pierde información, los totales cuadran.
- **Tabla puente con factor** — `BridgeContenidoGenero` con `FactorAsignacion = 1/n`. Permite "¿cuántas horas se vieron de ciencia ficción?" repartiendo correctamente.

**Recomendación:** puente con factor, porque en streaming **el análisis por género es una pregunta central del negocio** y perder la multiplicidad sería perder información valiosa. El costo de complejidad se justifica cuando la pregunta importa; en el caso de WWI, no.

**20.** **El bug:** la búsqueda usa `dc.EsActual = 1`, así que **todos los hechos apuntan a la versión actual del cliente**, sin importar cuándo ocurrió la venta.

**El efecto:** cuando un cliente cambia de categoría, la próxima recarga de hechos reasigna **todas** sus ventas históricas a la nueva versión. Los reportes del año pasado cambian. **El modelo tiene toda la estructura de Tipo 2 y se comporta exactamente como Tipo 1.**

**Por qué es tan difícil de detectar:**

1. **No produce errores.** Compila, corre, y los conteos cuadran perfectamente.
2. **Los totales generales son correctos.** Solo cambia la *distribución* entre categorías.
3. **La dimensión se ve bien.** Tiene las versiones, tiene los rangos, tiene `EsActual`. Una revisión de código de la dimensión no encuentra nada.
4. **Solo se nota comparando el mismo reporte en dos momentos distintos**, con meses de diferencia — y para entonces nadie recuerda cuál era el número original.
5. **Peor: las filas viejas de la dimensión quedan sin ningún hecho apuntándolas**, así que parecen "históricas y correctas" aunque no las use nadie.

**Cómo detectarlo activamente:**

```sql
-- Si el modelo es Tipo 2 de verdad, debería haber hechos apuntando
-- a versiones NO actuales de la dimensión.
SELECT COUNT(*) AS HechosEnVersionesHistoricas
FROM dw.FactSales f
JOIN dw.DimCustomer dc ON dc.CustomerKey = f.CustomerKey
WHERE dc.EsActual = 0;
-- Si da 0 y hay versiones históricas en la dimensión → el bug está presente.
```

**La corrección:**

```sql
LEFT JOIN dw.DimCustomer dc
       ON dc.CustomerID = o.CustomerID
      AND o.OrderDate  >= dc.ValidoDesde
      AND o.OrderDate  <  dc.ValidoHasta
```

Y después de corregir hay que **reprocesar los hechos históricos**, porque las claves ya guardadas siguen apuntando a las versiones equivocadas.

---

## Módulos 9 y 10

**Comprensión — capa de resumen**

*¿Por qué `COUNT(DISTINCT OrderID)` no es aditivo?* Porque contar elementos distintos de dos conjuntos y sumar los resultados **cuenta dos veces** los elementos que están en ambos. Si el cliente 42 compró en enero y en febrero, aparece en el conteo distinto de los dos meses; sumarlos da 2 clientes cuando hay 1. Para obtener el valor anual hay que recalcularlo desde el detalle.

*¿Por qué `NULLIF` en los denominadores?* Porque `x / 0` lanza el error 8134 y **aborta la carga entera**. `x / NULLIF(y, 0)` devuelve NULL, que se muestra como celda vacía y se puede investigar sin urgencia. Convierte un fallo en un dato.

*¿Por qué `ORDER BY` puede usar alias del `SELECT` pero `WHERE` no?* Por el orden lógico de ejecución: `WHERE` es el paso 3 y `SELECT` el 6 — cuando se evalúa el `WHERE`, el alias todavía no existe. `ORDER BY` es el paso 8, posterior al `SELECT`, así que el alias ya está definido.

**Comprensión — automatización**

*¿Por qué delete-insert por ventana es idempotente?* Porque la operación completa —borrar el rango y reinsertarlo— deja el mismo estado sin importar cuántas veces se ejecute. No acumula: cada corrida reemplaza lo que había. Un `INSERT` incremental puro no tiene esa propiedad, porque la segunda corrida agregaría lo mismo otra vez.

*¿Por qué capturar el techo de la marca de agua antes de leer los datos?* Porque si lo tomás después, las filas modificadas **durante** la carga quedan en un limbo: son posteriores a `@Desde`, pero podrían no haber entrado en tu `SELECT` y sin embargo quedar por debajo del nuevo `@Hasta`. Se perderían para siempre. Capturar el techo primero garantiza que el rango `[Desde, Hasta)` es exactamente lo que leíste.

*¿Por qué el paso de cuadre final debe poder hacer fallar el job?* Porque es la última verificación antes de que alguien tome una decisión con esos números. Si el warehouse no cuadra con el origen y el job queda en verde, el sistema está entregando datos incorrectos **con la apariencia de un proceso exitoso** — el peor fallo posible según el Módulo 0.

*¿Por qué recargar una dimensión SCD2 sin cambios no debe crear versiones?* Porque si las crea, la detección de cambios está rota (típicamente por comparar con `<>` sobre columnas nulables en lugar de `EXCEPT`). El síntoma es una dimensión que crece linealmente con la cantidad de ejecuciones: en un mes tenés 30 versiones idénticas de cada cliente, y la búsqueda por rango de fechas se vuelve ambigua.

---

**Fin del Volumen II.**

