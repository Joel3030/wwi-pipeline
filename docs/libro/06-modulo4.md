---

# Módulo 4 — Validaciones y Data Quality

> **Paso 2 del proyecto, parte 3 de 3**

## 🎯 Objetivos

Al terminar este módulo vas a poder:

- Explicar por qué las validaciones son el componente más importante de un pipeline.
- Nombrar y aplicar las seis dimensiones de la calidad de datos.
- Escribir validaciones de nulos, duplicados, integridad referencial, rango, fecha, consistencia y formato.
- Usar agregación condicional para ejecutar muchas validaciones en una sola pasada.
- **Decidir profesionalmente qué hacer con un registro inválido**, con un marco de decisión reproducible.
- Distinguir fail fast de log and continue y aplicar cada uno donde corresponde.
- Implementar validaciones de volumen y frescura (*data observability*).
- Probar el camino negativo, que es la única forma de saber que una validación funciona.

---

## 📖 Teoría

### 4.1 Por qué las validaciones son el corazón del pipeline

Vale la pena repetir la frase del Módulo 0, porque este módulo entero se deriva de ella:

> **Un pipeline que falla se arregla. Un pipeline que entrega datos incorrectos destruye la confianza en todo el sistema.**

Y la confianza, una vez perdida, es casi imposible de recuperar. Cuando un gerente descubre un número mal, no deja de creer en ese número: deja de creer en **el dashboard**. Después vuelve a pedir sus reportes en Excel, y todo el proyecto se convierte en un costo sin beneficio.

**El asimetría es brutal:**

| | Pipeline caído | Pipeline con datos malos |
|---|---|---|
| ¿Cuándo se detecta? | Inmediato | Semanas o meses |
| ¿Quién lo detecta? | Monitoreo automático | Alguien que nota algo raro |
| ¿Qué se arregla? | El proceso | El proceso **y** todas las decisiones tomadas |
| Costo | Horas | Reputación del proyecto |

Por eso las validaciones no son "una buena práctica más". Son **el producto**.

---

### 4.2 Las seis dimensiones de la calidad de datos

> ➕ **Tema adicional recomendado:** dimensiones de calidad de datos
> **Por qué necesito aprenderlo:** es el marco estándar de la industria para clasificar problemas de datos; te da un vocabulario para hablar con no técnicos y una lista de verificación para no olvidarte de nada.
> **En qué parte del proyecto lo utilizaremos:** organiza todas las validaciones de este módulo y las del modelo dimensional.

| Dimensión | Pregunta que responde | Cómo se mide |
|---|---|---|
| **Completitud** | ¿Están todos los datos que deberían estar? | % de nulos en campos obligatorios |
| **Unicidad** | ¿Hay duplicados? | Filas repetidas por clave de negocio |
| **Validez** | ¿Los valores están en su dominio? | Fuera de rango, formato incorrecto |
| **Exactitud** | ¿Reflejan la realidad? | Comparación con una fuente externa |
| **Consistencia** | ¿Concuerdan entre sí? | Reglas cruzadas entre campos o tablas |
| **Oportunidad** | ¿Están disponibles a tiempo? | Frescura, retraso respecto de lo esperado |

> **⚠️ La incómoda: exactitud.** Es la única que **no se puede validar dentro del sistema**. Si el operador cargó `1.000` en vez de `100`, el dato es completo, único, válido, consistente y oportuno — **y está mal**. Detectarlo requiere una fuente externa de verdad o análisis estadístico de anomalías.
>
> Decir esto en una entrevista muestra que entendés los límites de lo que construís, y eso genera más confianza que afirmar que tu pipeline garantiza datos correctos.

---

### 4.3 Validación de NULLs (completitud)

**La forma directa:**

```sql
SELECT COUNT(*) AS CustomerID_Null
FROM Sales.Orders
WHERE CustomerID IS NULL;
```

Correcta, pero si tenés cinco columnas necesitás cinco pasadas por la tabla. Con 231.412 filas eso son cinco escaneos completos. Lo resolvemos en 4.10.

**Lo que hay que decidir antes de escribir la validación — y no es técnico:**

> **¿Qué significa NULL en esta columna?**

| Columna | NULLs | ¿Problema? |
|---|---|---|
| `CustomerID` | 1 | 🔴 **Sí.** Un pedido sin cliente está roto. |
| `PickedByPersonID` | muchos | 🟢 No. Significa "no preparado todavía". Es un estado. |
| `BackorderOrderID` | casi todos | 🟢 No. Solo unos pocos pedidos son reposiciones. |
| `Comments` | muchos | 🟢 No. Es opcional por diseño. |

**La misma técnica, tres conclusiones distintas.** La diferencia no está en el SQL: está en el conocimiento del negocio.

> **✅ Práctica profesional:** antes de escribir la primera validación, hacé una tabla con cada columna, su porcentaje de nulos, y **qué significa ese nulo**. Las que no puedas completar son preguntas para alguien del negocio. Esa conversación es parte del trabajo, no una interrupción.

**El caso que engaña: NULLs disfrazados.**

```sql
SELECT COUNT(*) AS VaciosDisfrazados
FROM Sales.Orders
WHERE CustomerPurchaseOrderNumber IS NULL
   OR LTRIM(RTRIM(CustomerPurchaseOrderNumber)) = N''
   OR UPPER(LTRIM(RTRIM(CustomerPurchaseOrderNumber))) IN (N'N/A', N'NA', N'NULL', N'-', N'SIN DATO', N'.');
```

Una cadena vacía, un espacio o `'N/A'` **no son NULL** y ninguna validación de nulos los detecta. Pero para el negocio significan exactamente lo mismo: no hay dato. Y como sí tienen valor, aparecen en el dashboard como una categoría propia llamada "N/A" con 4.000 registros.

---

### 4.4 Validación de duplicados (unicidad)

```sql
SELECT OrderID, COUNT(*) AS Repeticiones
FROM Sales.Orders
GROUP BY OrderID
HAVING COUNT(*) > 1;
```

**Y el conteo agregado, que es lo que va al log:**

```sql
SELECT COUNT(*) AS ClavesDuplicadas
FROM (
    SELECT OrderID
    FROM Sales.Orders
    GROUP BY OrderID
    HAVING COUNT(*) > 1
) AS d;
```

> **⚠️ Fijate qué cuenta esa consulta: claves duplicadas, no filas sobrantes.** Si `OrderID = 5` aparece tres veces, esto devuelve **1** (una clave con problema), no 2 (filas de más) ni 3 (filas totales). Las tres métricas son defendibles; lo que **no** es defendible es no saber cuál estás reportando. Documentalo en el nombre de la regla.

**Lo importante: ¿duplicado según qué?**

Un duplicado se define contra una **clave de negocio** (*business key* o *natural key*), y esa clave no siempre es una sola columna:

- `Sales.Orders` → `OrderID`
- `Sales.OrderLines` → `OrderLineID`, o `(OrderID, StockItemID)` si la regla es "un producto una sola vez por pedido"

Esas dos opciones para `OrderLines` **dan resultados distintos** y ambas pueden ser correctas: depende de si el negocio permite dos líneas del mismo producto en un pedido. **No es una decisión técnica.**

**Duplicados exactos vs lógicos:**

```sql
-- Exactos: todas las columnas iguales (típicamente un error de carga)
SELECT OrderID, CustomerID, OrderDate, COUNT(*)
FROM Sales.Orders
GROUP BY OrderID, CustomerID, OrderDate
HAVING COUNT(*) > 1;

-- Lógicos: misma entidad, atributos distintos (mucho peor)
SELECT OrderID, COUNT(*) AS Versiones, COUNT(DISTINCT CustomerID) AS ClientesDistintos
FROM Sales.Orders
GROUP BY OrderID
HAVING COUNT(*) > 1;
```

**El duplicado lógico es más grave**, porque no sabés cuál versión es la buena. Un duplicado exacto se resuelve con `DISTINCT`; uno lógico requiere una regla de negocio ("gana el de `LastEditedWhen` más reciente") y esa regla hay que preguntarla.

---

### 4.5 Integridad referencial: claves huérfanas

```sql
-- Pedidos cuyo cliente no existe
SELECT COUNT(*) AS ClientesHuerfanos
FROM Sales.Orders o
WHERE o.CustomerID IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM WideWorldImporters.Sales.Customers c
      WHERE c.CustomerID = o.CustomerID
  );
```

> **⚠️ El `IS NOT NULL` no es opcional.** Sin él, cada fila con `CustomerID` nulo cuenta como huérfana, y mezclás dos problemas distintos en una sola métrica. Un nulo es "falta el dato"; un huérfano es "el dato apunta a algo inexistente". Requieren respuestas diferentes.

**Por qué esto puede fallar aunque el origen tenga FKs:**

1. **Cargas incrementales desfasadas.** Cargaste `Orders` a las 2:00 y `Customers` a las 2:05. Un cliente creado a las 2:02 tiene pedidos que apuntan a un cliente que tu staging no tiene todavía. **El origen es consistente; tu copia no.** Este es el caso más común y el más olvidado.
2. **La FK no existe.** `Sales.Orders.BackorderOrderID` en WWI no tiene FK declarada (Módulo 1, consulta 7).
3. **La FK está *not trusted*.** Puede haber violaciones preexistentes.
4. **Borrados en el origen** entre una carga y la siguiente.

**Por qué importa muchísimo para el modelo dimensional:**

```sql
-- En el Módulo 8 vas a escribir algo así:
INSERT INTO dw.FactSales (CustomerKey, ...)
SELECT dc.CustomerKey, ...
FROM stg.OrderLines ol
JOIN stg.Orders     o  ON o.OrderID = ol.OrderID
JOIN dw.DimCustomer dc ON dc.CustomerID = o.CustomerID;   -- ← INNER JOIN
```

**Ese `INNER JOIN` descarta silenciosamente toda venta cuyo cliente no esté en la dimensión.** Sin error, sin warning. Tus ventas totales quedan por debajo de la realidad y nadie sabe por qué.

**Las tres soluciones, en orden de preferencia:**

1. **Validar antes y fallar** si hay huérfanos por encima de un umbral.
2. **Miembro desconocido** — una fila `-1` "Desconocido" en la dimensión, y `LEFT JOIN` con `ISNULL(dc.CustomerKey, -1)`. La venta se conserva y el problema queda visible en el dashboard como categoría "Desconocido". **Es la solución estándar de Kimball** y la veremos en 7.14.
3. **Descartar y registrar** cuántas filas se descartaron. Aceptable solo si el número queda registrado y monitoreado.

**Lo inaceptable es `INNER JOIN` sin saber cuántas filas pierde.**

---

### 4.6 Rangos, dominios y valores fuera de escala (validez)

```sql
SELECT
    SUM(CASE WHEN Quantity <= 0                    THEN 1 ELSE 0 END) AS CantidadNoPositiva,
    SUM(CASE WHEN UnitPrice < 0                    THEN 1 ELSE 0 END) AS PrecioNegativo,
    SUM(CASE WHEN UnitPrice > 100000               THEN 1 ELSE 0 END) AS PrecioSospechoso,
    SUM(CASE WHEN TaxRate NOT BETWEEN 0 AND 100    THEN 1 ELSE 0 END) AS ImpuestoInvalido
FROM Sales.OrderLines;
```

**Tres tipos de regla, y la distinción importa:**

- **Imposible** — `Quantity = 0` en una venta, `UnitPrice < 0`. Viola la definición. **Error.**
- **Improbable** — `UnitPrice > 100.000` para artículos de novedad. Puede ser legítimo. **Advertencia.**
- **Fuera de política** — descuento mayor al 50% sin autorización. Depende de reglas cambiantes. **Excepción de negocio.**

> **✅ Mezclarlos es el error clásico.** Si tratás lo improbable como error, tu pipeline falla por datos legítimos y el equipo aprende a ignorar las alertas. Si tratás lo imposible como advertencia, la basura entra al warehouse. **Cada regla necesita su nivel de severidad declarado explícitamente.**

**Detección estadística de valores atípicos**, para cuando no conocés los límites:

```sql
WITH Stats AS (
    SELECT AVG(CAST(UnitPrice AS FLOAT)) AS Media,
           STDEV(CAST(UnitPrice AS FLOAT)) AS Desvio
    FROM Sales.OrderLines
)
SELECT COUNT(*) AS AtipicosMas3Sigma
FROM Sales.OrderLines ol
CROSS JOIN Stats s
WHERE ABS(ol.UnitPrice - s.Media) > 3 * s.Desvio;
```

Tres desvíos estándar cubren ~99,7% de una distribución normal. **Ojo:** los precios rara vez se distribuyen normalmente (suelen tener sesgo a la derecha), así que este método marca falsos positivos. Para distribuciones sesgadas, el rango intercuartílico es mejor. Es un punto de partida para explorar, no una regla de producción.

---

### 4.7 Fechas inválidas e imposibles

Las fechas concentran una cantidad desproporcionada de problemas.

```sql
SELECT
    SUM(CASE WHEN OrderDate > CAST(SYSDATETIME() AS DATE)         THEN 1 ELSE 0 END) AS FechaFutura,
    SUM(CASE WHEN OrderDate < '2000-01-01'                        THEN 1 ELSE 0 END) AS FechaMuyAntigua,
    SUM(CASE WHEN ExpectedDeliveryDate < OrderDate                THEN 1 ELSE 0 END) AS EntregaAntesDePedido,
    SUM(CASE WHEN PickingCompletedWhen < CAST(OrderDate AS DATETIME2) THEN 1 ELSE 0 END) AS PreparadoAntesDePedido,
    SUM(CASE WHEN OrderDate IN ('1900-01-01','1899-12-30','0001-01-01') THEN 1 ELSE 0 END) AS FechasCentinela
FROM Sales.Orders;
```

**Los cinco problemas típicos:**

1. **Fechas futuras** — error de carga o de zona horaria. Un pedido de mañana no existe.
2. **Fechas centinela** — `1900-01-01` es el clásico "sin fecha" de sistemas viejos; `1899-12-30` es el cero de Excel; `0001-01-01` es `default(DateTime)` de .NET. **Los tres son NULLs disfrazados** y arruinan cualquier gráfico de línea de tiempo, porque estiran el eje X años hacia atrás.
3. **Orden lógico violado** — entrega antes del pedido. Imposible por definición.
4. **Formato inválido** cuando la fecha viene como texto → `TRY_CONVERT`.
5. **Confusión de zona horaria** — un pedido a las 23:30 local se guarda como el día siguiente en UTC. Las ventas del último día del mes se corren al mes siguiente. **Este error puede desplazar un cierre contable.**

> **⚠️ El más difícil de detectar es el 5**, porque los datos parecen perfectamente válidos. Solo se descubre comparando totales por período contra otra fuente. Es un caso donde la validación técnica no alcanza y hace falta un **cuadre** (*reconciliation*) contra el sistema origen.

---

### 4.8 Consistencia entre campos

Reglas que involucran más de una columna o más de una tabla:

```sql
-- Un pedido preparado debe tener quién lo preparó
SELECT COUNT(*) AS InconsistenciaPreparacion
FROM Sales.Orders
WHERE PickingCompletedWhen IS NOT NULL
  AND PickedByPersonID IS NULL;

-- Marcado como backorder pero sin pedido de referencia
SELECT COUNT(*) AS BackorderInconsistente
FROM Sales.Orders
WHERE IsUndersupplyBackordered = 1
  AND BackorderOrderID IS NULL;
```

**Y la validación más importante de todas — el cuadre contra el origen:**

```sql
SELECT
    (SELECT COUNT(*) FROM Sales.Orders)                        AS Staging,
    (SELECT COUNT(*) FROM WideWorldImporters.Sales.Orders)     AS Origen,
    (SELECT COUNT(*) FROM Sales.Orders)
  - (SELECT COUNT(*) FROM WideWorldImporters.Sales.Orders)     AS Diferencia;
```

> **✅ Esta validación —el *reconciliation check*— es la que más problemas encuentra en la vida real, y es la que más gente omite.** Comparar el conteo, y también la suma de una columna numérica clave, contra el origen. Si no cuadran, todo lo demás es irrelevante.

Para el modelo dimensional (Módulo 8) la versión importante es:

```sql
SELECT
    (SELECT SUM(Quantity * UnitPrice) FROM stg.OrderLines)  AS TotalStaging,
    (SELECT SUM(SalesAmount)          FROM dw.FactSales)    AS TotalWarehouse;
```

Si esos dos números difieren, tenés un fan-out, un join que descarta filas, o un filtro que no debería estar. **Los tres son invisibles sin este cuadre.**

---

### 4.9 Registros incompletos y errores de formato

```sql
SELECT
    -- Espacios sobrantes: 'Argentina ' y 'Argentina' son categorías distintas
    SUM(CASE WHEN CustomerPurchaseOrderNumber <> LTRIM(RTRIM(CustomerPurchaseOrderNumber))
             THEN 1 ELSE 0 END) AS ConEspacios,

    -- Caracteres de control invisibles (tabs, saltos de línea)
    SUM(CASE WHEN CustomerPurchaseOrderNumber LIKE N'%' + CHAR(9)  + N'%'
               OR CustomerPurchaseOrderNumber LIKE N'%' + CHAR(10) + N'%'
               OR CustomerPurchaseOrderNumber LIKE N'%' + CHAR(13) + N'%'
             THEN 1 ELSE 0 END) AS ConCaracteresControl,

    -- Texto donde se espera algo parecido a un número
    SUM(CASE WHEN CustomerPurchaseOrderNumber IS NOT NULL
              AND TRY_CONVERT(INT, CustomerPurchaseOrderNumber) IS NULL
             THEN 1 ELSE 0 END) AS NoNumerico
FROM Sales.Orders;
```

> **⚠️ El error de formato más caro de la industria es el espacio al final.** Es invisible al ojo, sobrevive a todas las validaciones obvias, y produce categorías duplicadas en el dashboard: `'Argentina'` y `'Argentina '` aparecen como dos países. Nadie lo detecta mirando la pantalla, porque **se ven idénticos**.
>
> Cuidado también con `LEN()`: en SQL Server **ignora los espacios finales**. `LEN('abc ')` devuelve 3. Para detectar espacios al final usá `DATALENGTH()` o compará contra `RTRIM()` como arriba.

---

### 4.10 Agregación condicional

**El problema:** cinco validaciones son cinco `SELECT COUNT(*)`, es decir **cinco escaneos** de la tabla.

**La solución:**

```sql
SELECT
    SUM(CASE WHEN CustomerID          IS NULL THEN 1 ELSE 0 END) AS CustomerID_Null,
    SUM(CASE WHEN SalespersonPersonID IS NULL THEN 1 ELSE 0 END) AS Salesperson_Null,
    SUM(CASE WHEN ContactPersonID     IS NULL THEN 1 ELSE 0 END) AS ContactPerson_Null,
    SUM(CASE WHEN OrderDate           IS NULL THEN 1 ELSE 0 END) AS OrderDate_Null
FROM Sales.Orders;
```

**Una sola pasada, cuatro resultados.** Se llama **agregación condicional** (*conditional aggregation*) y es una de las técnicas más útiles de SQL analítico. La vas a volver a usar para pivotear datos en el Módulo 9.

> **⚠️ `SUM(CASE ... ELSE 0 END)` y no `COUNT(CASE ... END)`.**
>
> Ambos dan el mismo número. Pero `COUNT` sobre una expresión que produce `NULL` emite el **warning 8153**: *"Null value is eliminated by an aggregate or other SET operation"*.
>
> En una consulta interactiva es ruido inofensivo. **Dentro de un job nocturno, ese warning se escribe en el historial de ejecución en cada corrida.** El efecto real no es técnico sino humano: el equipo se acostumbra a ver avisos en el historial y deja de mirarlos. El día que aparezca un aviso importante, nadie lo va a ver.
>
> **La higiene de las alertas es parte del diseño del sistema.** Un canal de alertas con ruido es un canal apagado.

---

### 4.11 El constructor de tabla `(VALUES ...)`

Ya tenemos los conteos. Ahora hay que registrarlos, pero **solo los que encontraron algo**.

**La forma ingenua** — un `IF` y un `INSERT` por cada regla:

```sql
IF @CustomerNull > 0
    INSERT INTO etl.ValidationLog (...) VALUES (..., N'CustomerID_NULL', @CustomerNull);
IF @SalespersonNull > 0
    INSERT INTO etl.ValidationLog (...) VALUES (..., N'Salesperson_NULL', @SalespersonNull);
-- ... y así cinco veces
```

Funciona, y es cinco veces la misma estructura. Cada copia es una oportunidad de olvidarse una columna.

**La forma elegante:**

```sql
INSERT INTO etl.ValidationLog (LoadBatchId, SchemaName, TableName, RuleName, AffectedRowCount)
SELECT @BatchId, N'Sales', N'Orders', v.RuleName, v.AffectedRowCount
FROM (VALUES
    (N'CustomerID_NULL',           @CustomerNull),
    (N'SalespersonPersonID_NULL',  @SalespersonNull),
    (N'ContactPersonID_NULL',      @ContactNull),
    (N'OrderDate_NULL',            @OrderDateNull),
    (N'OrderID_DUPLICADO',         @Duplicados)
) AS v(RuleName, AffectedRowCount)
WHERE v.AffectedRowCount > 0;
```

**`(VALUES ...) AS v(cols)`** es un **constructor de tabla** (*table value constructor*): construye una tabla derivada al vuelo a partir de literales. Está disponible desde SQL Server 2008.

**Las ventajas concretas:**

- **Un solo `INSERT`.** Agregar una validación es agregar una línea.
- **El `WHERE` se aplica una vez** para todas las reglas. Imposible olvidarlo en una.
- **Imposible desalinear columnas.** Con cinco `INSERT` separados podés escribir mal uno solo.

> **⚠️ Y acá el error real que ilustra todo el libro.** Si al escribir los cinco `INSERT` separados omitís `SchemaName` (que es `NOT NULL`) en todos ellos, el código **compila y se despliega sin problema**. Nunca falla... hasta el día en que una validación **efectivamente encuentre algo**. Con datos limpios, esas líneas nunca se ejecutan.
>
> Es decir: el bug se manifiesta **exactamente cuando hay un problema de datos que investigar**. En el peor momento posible, tu herramienta de diagnóstico es la que falla.
>
> **Todo camino de error no ejecutado es un camino de error no probado.** Por eso existe la sección 4.15.

---

### 4.12 La decisión profesional: qué hacer con un registro inválido

Esta es la sección que el usuario de este libro más va a usar en su trabajo, porque es la pregunta que se hace en cada proyecto y casi nunca se responde con método.

**Las cinco opciones:**

| Opción | Qué hace | Cuándo | Riesgo |
|---|---|---|---|
| **Rechazar todo** | Aborta la carga | Error estructural; datos críticos | Un registro malo bloquea todo |
| **Aislar** | Va a una tabla de cuarentena | Problemas de fila individual | Alguien tiene que revisarla |
| **Corregir** | Aplica una regla automática | Reglas claras y sin ambigüedad | Ocultás el problema de origen |
| **Ignorar** | Se descarta | Datos irrelevantes | **Pérdida silenciosa** |
| **Registrar y continuar** | Carga y anota | Calidad monitoreada | Datos malos en el warehouse |

**El marco de decisión — cuatro preguntas, en orden:**

**1. ¿El dato es crítico para la métrica principal?**
Si sin él la métrica está mal → rechazar o aislar. Un pedido sin importe rompe "ventas totales".

**2. ¿Se puede corregir con una regla determinística y defendible?**
`LTRIM(RTRIM())` sí. "Si falta el país, poner Estados Unidos" no — eso es **inventar datos**, y es peor que un nulo porque es indistinguible de un dato real.

**3. ¿Cuántos registros afecta?**
Uno de 73.595 → registrar y seguir. El 30% → parar todo; hay un problema sistémico y cargar sería propagar basura.

**4. ¿Alguien va a mirar la cuarentena?**
Si la respuesta honesta es no, la cuarentena es un cementerio. **Mejor registrar y alertar** que aislar en una tabla que nadie abre. Esta pregunta es organizacional, no técnica, y es la que más se omite.

**Lo que hace este proyecto, explícito:**

| Situación | Decisión | Por qué |
|---|---|---|
| Nulos en columnas opcionales | Registrar y continuar | No afectan las métricas |
| Nulos en `CustomerID` | Registrar y alertar | Raro; necesita investigación humana |
| Duplicados de `OrderID` | Registrar y alertar | Indica un problema serio de origen |
| Caída de volumen > 20% | **Rechazar todo** | Síntoma de fallo sistémico |
| Error estructural | **Rechazar todo** | El pipeline está roto |

> **🎓 Cómo responder esto en una entrevista.** No des una respuesta única. Decí: *"Depende de la criticidad del dato, de si la corrección es determinística, del volumen afectado, y de si hay un proceso real que revise la cuarentena. En mi proyecto usé log-and-continue para problemas de fila y fail-fast para anomalías de volumen, porque una caída del 20% indica un fallo sistémico y no un dato malo."* Esa respuesta muestra criterio, que es lo que se está evaluando.

---

### 4.13 Fail fast vs log and continue

**Fail fast** — abortar al primer problema.

✅ Nada malo entra · El problema es visible de inmediato · Estado consistente
❌ Un registro malo bloquea todo · Puede causar interrupciones evitables

**Log and continue** — registrar y seguir.

✅ Los datos buenos llegan · Se ven **todos** los problemas de una vez, no solo el primero
❌ Datos malos en el warehouse · Requiere que alguien mire los logs

**La combinación correcta, y el criterio para elegir:**

> **Fail fast** para lo que indica que **el proceso está roto**.
> **Log and continue** para lo que indica que **un dato está mal**.

Un `TRUNCATE` que falla, un origen inalcanzable, una caída de volumen del 40%: el proceso está roto → **parar**.

Tres pedidos sin número de orden de compra de 73.595: el proceso funciona, hay datos imperfectos → **registrar y seguir**.

Y notá la ventaja subestimada de log and continue: **ves todos los problemas de una corrida**. Con fail fast arreglás uno, volvés a correr, aparece el siguiente. Es la diferencia entre un compilador que reporta un error por vez y uno que los reporta todos.

---

### 4.14 Validaciones de volumen y frescura

> ➕ **Tema adicional recomendado:** *data observability*
> **Por qué necesito aprenderlo:** hay una clase entera de fallos que ninguna validación fila-por-fila puede detectar.
> **En qué parte del proyecto lo utilizaremos:** ya está implementada en el procedimiento de carga; acá está el porqué.

**El fallo que ninguna validación anterior detecta:**

Un día el origen devuelve 40.000 pedidos en vez de 73.595. Corré todas las validaciones del módulo:

- ¿Nulos? Ninguno.
- ¿Duplicados? Ninguno.
- ¿Huérfanos? Ninguno.
- ¿Rangos? Todo correcto.
- ¿Fechas? Válidas.

**Todo pasa. Y faltan 33.595 pedidos.**

Cada fila es perfecta. El problema no está en las filas: está en **el conjunto**. Un filtro mal puesto, una carga incremental que se cortó, una tabla particionada donde una partición no vino.

> **💡 Concepto clave — *data observability*.** Monitorear propiedades **agregadas** del conjunto de datos —volumen, frescura, distribución, esquema— en lugar de solo validar filas individuales. Las cuatro señales clásicas son: **volumen** (¿cuántas filas?), **frescura** (¿qué tan reciente?), **distribución** (¿cambiaron las proporciones?) y **esquema** (¿cambiaron las columnas?).
>
> Herramientas como Monte Carlo, Great Expectations o dbt tests existen para esto. Vos lo estás construyendo a mano, que es la mejor forma de entender qué hacen.

**Validación de volumen contra línea base histórica:**

```sql
SELECT @BaselineRows = AVG(RowsLoaded)
FROM (
    SELECT TOP (5) RowsLoaded
    FROM etl.LoadBatch
    WHERE SchemaName = N'Sales' AND TableName = N'Orders'
      AND Status = N'Succeeded' AND RowsLoaded IS NOT NULL
    ORDER BY StartedAt DESC
) AS h;

IF @BaselineRows IS NOT NULL AND @RowsLoaded < @BaselineRows * 0.8
BEGIN
    SET @Msg = CONCAT(N'Caida de volumen: ', @RowsLoaded,
                      N' filas contra linea base de ', @BaselineRows,
                      N' (umbral 80%%). Carga revertida.');
    THROW 50001, @Msg, 1;
END
```

**Cada decisión de diseño, justificada:**

**¿Por qué el promedio de las últimas 5 y no la última?** Una sola corrida anómala envenenaría la comparación del día siguiente. El promedio suaviza. Cinco es suficiente para estabilizar sin quedar tan atrás que no siga el crecimiento natural del negocio.

**¿Por qué solo las `Succeeded`?** Una corrida fallida puede tener `RowsLoaded` nulo o parcial. Incluirla bajaría la línea base artificialmente y **el umbral dejaría de detectar nada**.

**¿Por qué `IF @BaselineRows IS NOT NULL`?** La primera vez que corre no hay historia. Sin esa condición, comparar contra `NULL` da `UNKNOWN`, el `IF` no entra, y **la validación simplemente no existe** — silenciosamente. Peor: si alguien la escribe al revés, la primera carga falla siempre.

**¿Por qué 80% y no 95%?** Es una decisión de negocio, no técnica. Muy estricto → falsos positivos en días de poca actividad (feriados, fin de año) y el equipo apaga la alerta. Muy laxo → no detecta nada. 20% de caída es difícil de explicar por variación natural en un negocio estable.

**¿Por qué dentro de la transacción?** Para que el `THROW` dispare el `ROLLBACK` y sobrevivan los datos de ayer. Si estuviera afuera, detectaría el problema **después** de haber pisado los datos buenos: sabrías que algo anda mal y ya no tendrías los datos correctos.

> **⚠️ La trampa de la línea base — y es un desastre real esperando a pasar.** Si en tus pruebas insertás registros falsos en `etl.LoadBatch` con valores altos de `RowsLoaded`, esos registros **entran en la línea base**.
>
> Ejemplo concreto: 10 filas de prueba con `RowsLoaded = 500000`. La línea base pasa a 158.876 y el umbral a 127.100. La carga real trae 73.595. **73.595 < 127.100 → el job falla.** Y falla **todas las noches, para siempre**, hasta que alguien encuentre las filas de prueba.
>
> **Es el mismo problema del Módulo 3: el andamiaje de prueba que sobrevive.** Todo script de prueba debe tener su bloque de limpieza, y hay que ejecutarlo.

**Validación de frescura:**

```sql
SELECT DATEDIFF(HOUR, MAX(LoadedAt), SYSUTCDATETIME()) AS HorasDesdeUltimaCarga
FROM Sales.Orders;
-- Si supera 26 en un proceso diario → alerta
```

**Por qué 26 y no 24:** hay que dejar margen para la duración de la carga y para desfasajes del planificador. Un umbral exactamente igual al período genera falsos positivos constantes.

---

### 4.15 Pruebas del camino negativo

> ➕ **Tema adicional recomendado:** *negative path testing*
> **Por qué necesito aprenderlo:** es la única forma de saber que tu manejo de errores funciona. Y es lo que separa un pipeline profesional de uno que "anda".
> **En qué parte del proyecto lo utilizaremos:** en `tests/negative_tests.sql`, y cada vez que agregues una validación.

**El principio, y vale enmarcarlo:**

> **Una validación que nunca se disparó es una validación que no sabés si funciona.**

Es exactamente lo mismo que una rama `catch` sin prueba unitaria. Podés tener el código más cuidado del mundo: si nunca se ejecutó, es una hipótesis, no una garantía.

**Las tres pruebas del proyecto:**

**Prueba 1 — Idempotencia.**

```sql
EXEC etl.usp_LoadSalesOrders;
SELECT COUNT(*) AS Corrida1 FROM Sales.Orders;          -- 73595

EXEC etl.usp_LoadSalesOrders;
SELECT COUNT(*) AS Corrida2 FROM Sales.Orders;          -- 73595  ✅
SELECT COUNT(DISTINCT LoadBatchId) AS Lotes FROM Sales.Orders;  -- 1  ✅
```

**Prueba 2 — Rollback ante fallo.**

```sql
-- Andamiaje: un trigger que hace fallar el INSERT
CREATE TRIGGER Sales.trg_SimularFallo ON Sales.Orders AFTER INSERT
AS
BEGIN
    THROW 50000, N'Fallo simulado para probar el rollback', 1;
END;
GO

BEGIN TRY
    EXEC etl.usp_LoadSalesOrders;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS Num, ERROR_MESSAGE() AS Msj;
END CATCH

-- ✅ Deben seguir las 73.595 filas anteriores
SELECT COUNT(*) AS FilasSobrevivientes FROM Sales.Orders;

-- ✅ Debe haber un registro Failed con el error
SELECT TOP 1 Status, ErrorNumber, ErrorMessage
FROM etl.LoadBatch ORDER BY StartedAt DESC;

-- ⚠️ LIMPIEZA OBLIGATORIA
DROP TRIGGER Sales.trg_SimularFallo;
GO
```

**Prueba 3 — Detección de calidad.**

```sql
-- Ensuciar una fila
UPDATE TOP (1) Sales.Orders SET CustomerID = NULL;

-- Validar con un lote de prueba identificable
EXEC etl.usp_ValidateSalesOrders '00000000-0000-0000-0000-000000000001';

-- ✅ Debe aparecer CustomerID_NULL con AffectedRowCount = 1
SELECT * FROM etl.ValidationLog
WHERE LoadBatchId = '00000000-0000-0000-0000-000000000001';

-- ⚠️ LIMPIEZA
DELETE FROM etl.ValidationLog
WHERE LoadBatchId = '00000000-0000-0000-0000-000000000001';
EXEC etl.usp_LoadSalesOrders;   -- recarga y deja los datos limpios
```

**Fijate en el GUID de prueba: `00000000-...-0001`.** Es identificable a simple vista y trivial de limpiar. Si usaras `NEWID()` tendrías que buscarlo después. Es un detalle chico con gran efecto práctico.

> **⚠️ Las tres reglas del andamiaje de prueba:**
>
> 1. **Vive en `tests/`, nunca en el procedimiento de producción.**
> 2. **Cada bloque tiene su limpieza, escrita al mismo tiempo que la prueba.**
> 3. **Verificá que la limpieza corrió.** Un trigger olvidado rompe el pipeline; filas falsas en `etl.LoadBatch` envenenan la línea base durante meses.

**Qué probar cuando agregás una validación nueva — el checklist:**

- [ ] ¿Detecta el problema cuando existe? (falso negativo)
- [ ] ¿**No** se dispara cuando no existe? (falso positivo)
- [ ] ¿Se registra con el nombre y el conteo correctos?
- [ ] ¿La limpieza dejó todo como estaba?

---

## 💻 El validador completo

```sql
USE WWI_Staging;
GO

CREATE OR ALTER PROCEDURE etl.usp_ValidateSalesOrders
    @BatchId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CustomerNull    INT,
            @SalespersonNull INT,
            @ContactNull     INT,
            @OrderDateNull   INT,
            @Duplicados      INT;

    /* Agregación condicional: una sola pasada por la tabla para las
       cuatro reglas de completitud.
       SUM(CASE...ELSE 0) y no COUNT(CASE...): COUNT emite el warning 8153
       y ensuciaría el historial del job todas las noches. */
    SELECT
        @CustomerNull    = SUM(CASE WHEN CustomerID          IS NULL THEN 1 ELSE 0 END),
        @SalespersonNull = SUM(CASE WHEN SalespersonPersonID IS NULL THEN 1 ELSE 0 END),
        @ContactNull     = SUM(CASE WHEN ContactPersonID     IS NULL THEN 1 ELSE 0 END),
        @OrderDateNull   = SUM(CASE WHEN OrderDate           IS NULL THEN 1 ELSE 0 END)
    FROM Sales.Orders;

    /* Los duplicados necesitan su propia consulta: agrupan, no agregan
       sobre la fila. Cuenta CLAVES con problema, no filas sobrantes. */
    SELECT @Duplicados = COUNT(*)
    FROM (
        SELECT OrderID
        FROM Sales.Orders
        GROUP BY OrderID
        HAVING COUNT(*) > 1
    ) AS d;

    /* Un solo INSERT con constructor de tabla.
       El WHERE se aplica una vez a todas las reglas: solo se registra
       lo que efectivamente encontró algo. */
    INSERT INTO etl.ValidationLog
        (LoadBatchId, SchemaName, TableName, RuleName, AffectedRowCount)
    SELECT @BatchId, N'Sales', N'Orders', v.RuleName, v.AffectedRowCount
    FROM (VALUES
        (N'CustomerID_NULL',          @CustomerNull),
        (N'SalespersonPersonID_NULL', @SalespersonNull),
        (N'ContactPersonID_NULL',     @ContactNull),
        (N'OrderDate_NULL',           @OrderDateNull),
        (N'OrderID_DUPLICADO',        @Duplicados)
    ) AS v(RuleName, AffectedRowCount)
    WHERE v.AffectedRowCount > 0;
END;
GO
```

**La tabla de log:**

```sql
CREATE TABLE etl.ValidationLog (
    ValidationLogID  INT IDENTITY(1,1) PRIMARY KEY,
    LoadBatchId      UNIQUEIDENTIFIER NOT NULL,
    SchemaName       NVARCHAR(128)    NOT NULL,
    TableName        NVARCHAR(128)    NOT NULL,
    RuleName         NVARCHAR(100)    NOT NULL,
    AffectedRowCount INT              NOT NULL,
    LoadedAt         DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
);
```

> **💡 Por qué `etl.ValidationLog` es una tabla y no un correo.** Un correo se lee una vez y se pierde. Una tabla permite preguntar *"¿los nulos de `CustomerID` vienen aumentando?"*. **Los problemas de calidad tienen tendencia**, y la tendencia es más informativa que el evento aislado. Tres nulos hoy no dicen nada; tres nulos hoy, dos ayer y ninguno hace un mes dicen que algo cambió en el origen.

---

## 💡 Conceptos clave

- **Seis dimensiones de calidad** — completitud, unicidad, validez, exactitud, consistencia, oportunidad.
- **Clave de negocio** — la que define la identidad de una entidad en el mundo real.
- **Registro huérfano** — el que referencia una clave inexistente.
- **Miembro desconocido** — fila especial de la dimensión para preservar hechos huérfanos.
- **Valor centinela** — valor que significa "sin dato" sin ser NULL.
- **Agregación condicional** — muchas métricas en una sola pasada con `SUM(CASE...)`.
- **Constructor de tabla** — `(VALUES ...) AS v(cols)`.
- **Fail fast / log and continue** — abortar vs registrar y seguir.
- **Data observability** — monitorear volumen, frescura, distribución y esquema.
- **Reconciliation** — cuadre de totales contra el origen.
- **Prueba del camino negativo** — forzar el fallo para verificar que se detecta.

---

## ⚠️ Errores comunes

**Validar sin saber qué significa un NULL.** Se reportan como problemas cosas que son estados válidos, y el equipo aprende a ignorar el log.

**Confundir NULL con vacío.** `''`, `' '` y `'N/A'` no son NULL y necesitan su propia validación.

**`COUNT(CASE...)` en vez de `SUM(CASE...)`.** Warning 8153 en cada corrida nocturna.

**Olvidar `IS NOT NULL` en la validación de huérfanos.** Mezcla dos problemas distintos.

**`INNER JOIN` sin medir cuántas filas descarta.** Pérdida silenciosa de ventas.

**No validar volumen.** Todas las validaciones de fila pasan y faltan 33.000 pedidos.

**Comparar la línea base contra la última corrida.** Una anomalía envenena el día siguiente.

**Olvidar `IF @BaselineRows IS NOT NULL`.** La validación no existe la primera vez, en silencio.

**Filas de prueba en `etl.LoadBatch`.** Envenenan la línea base y hacen fallar el job todas las noches.

**Umbral demasiado estricto.** Falsos positivos → el equipo apaga la alerta → no hay alerta.

**Escribir validaciones sin probarlas contra datos sucios.** Sección 4.15 completa.

**Cuarentena que nadie mira.** Es un cementerio con formato de tabla.

**Corregir inventando datos.** "Si falta el país, poner Estados Unidos" es peor que un nulo: es indistinguible de un dato real.

---

## ✅ Buenas prácticas

1. **Documentá qué significa cada NULL** antes de validarlo. Preguntá al negocio lo que no sepas.
2. **Una validación, un nombre estable.** `RuleName` es una clave lógica: si lo cambiás, perdés la serie histórica.
3. **Declará la severidad de cada regla.** No todo es un error.
4. **Agregación condicional** para todo lo que se pueda resolver en una pasada.
5. **Registrá solo lo que encontró algo.** Un log lleno de ceros no se lee.
6. **Validá volumen y frescura**, no solo filas.
7. **Cuadrá contra el origen.** Conteo y suma de una columna clave.
8. **Probá cada validación con datos sucios a propósito**, y limpiá después.
9. **El andamiaje vive en `tests/`.**
10. **Revisá tendencias, no eventos.** `etl.ValidationLog` es una serie temporal.

---

## 🧠 Preguntas de comprensión

1. Todas las validaciones de fila pasan y faltan 33.000 pedidos. ¿Qué clase de validación falta y por qué las de fila no pueden detectarlo?
2. ¿Por qué la línea base usa el promedio de 5 corridas exitosas y no la última?
3. Un compañero valida huérfanos sin `IS NOT NULL`. ¿Qué está contando de más y por qué importa la distinción?
4. Explicá por qué `COUNT(CASE ... END)` en un job nocturno es un problema **organizacional** y no solo técnico.
5. ¿Cuándo es peor corregir un dato que dejarlo malo? Dá un ejemplo concreto.
6. Tenés 10 filas de prueba con `RowsLoaded = 500000` en `etl.LoadBatch` y la carga real trae 73.595. Calculá la línea base, el umbral, y explicá qué le pasa al job.

---

## 📝 Ejercicios

**🟢 Básico.** Escribí `etl.usp_ValidateSalesOrders` completo con agregación condicional y constructor de tabla.

**🟢 Básico.** Corré la prueba 3 de la sección 4.15 y verificá que detecta el nulo. Después limpiá y comprobá que quedó todo como estaba.

**🟡 Intermedio.** Agregá tres validaciones: fechas futuras, entrega anterior al pedido, y `CustomerPurchaseOrderNumber` con espacios sobrantes. Probá cada una con datos sucios a propósito.

**🟡 Intermedio.** Escribí el validador de `Sales.OrderLines`: nulos, duplicados por `(OrderID, StockItemID)`, `Quantity <= 0`, `UnitPrice < 0`, y huérfanos contra `StockItems`. Justificá la elección de clave de duplicados.

**🔴 Avanzado.** Implementá una tabla de **cuarentena**: las filas que fallan validaciones críticas van a `etl.QuarantineOrders` con el motivo, y no entran al flujo principal. Agregá el procedimiento de reproceso que las reintenta cuando se corrigen. Después respondé: ¿quién va a mirar esa tabla, y qué hace tu diseño para que efectivamente la miren?

**🔴 Avanzado.** Implementá validación de **distribución**: detectar que la proporción de pedidos por categoría de cliente cambió más de X% respecto del promedio histórico. Esto detecta problemas que ni el volumen ni las validaciones de fila ven.

**🧠 Reto.** Diseñá un sistema de validaciones **configurable por metadatos**: una tabla `etl.ValidationRule` con `SchemaName`, `TableName`, `RuleName`, `RuleType`, `Expression`, `Severity`, `Threshold`, y un procedimiento genérico que las ejecute todas. Agregar una validación pasa a ser un `INSERT` en vez de un cambio de código.
>
> Después escribí un párrafo honesto sobre **el costo de esa abstracción**: qué se pierde en legibilidad, en depuración y en control de versiones cuando la lógica vive en filas en lugar de en archivos. Es una decisión real de arquitectura y ambas opciones son defendibles.

---

## 🎓 Preguntas de entrevista

1. **¿Cómo garantizás la calidad de los datos?** — Las seis dimensiones + validaciones de fila + observabilidad + cuadre. Y aclarar que la exactitud no se puede validar internamente.
2. **¿Qué hacés con un registro inválido?** — El marco de cuatro preguntas de 4.12. Nunca una respuesta única.
3. **¿Fail fast o log and continue?** — Fail fast si el proceso está roto, log and continue si un dato está mal.
4. **¿Cómo detectás que faltan datos si cada fila es válida?** — Validación de volumen contra línea base. Es la pregunta que separa a los que leyeron un tutorial de los que operaron un pipeline.
5. **¿Cómo probás tus validaciones?** — Forzando el fallo. Una validación que nunca se disparó es una hipótesis.
6. **¿Qué es data observability?** — Volumen, frescura, distribución, esquema.
7. **¿Cómo sabés que tu warehouse cuadra con el origen?** — Reconciliation: conteo y suma de una columna clave.
8. **¿Qué problema traen los INNER JOIN en la carga de hechos?** — Descartan silenciosamente los huérfanos. Solución: miembro desconocido.

---

## 📌 Resumen

- Un pipeline confiable pero incorrecto destruye la confianza en todo el sistema.
- **Seis dimensiones**: completitud, unicidad, validez, exactitud, consistencia, oportunidad. La exactitud no se valida internamente.
- Un NULL no es un error hasta que el negocio lo dice. **Preguntá.**
- Los NULLs disfrazados (`''`, `'N/A'`, `1900-01-01`) escapan a las validaciones de nulos.
- Los huérfanos se pierden silenciosamente en los `INNER JOIN` de la fact table.
- **Agregación condicional**: muchas validaciones, una pasada. `SUM(CASE)`, no `COUNT(CASE)`.
- **Constructor de tabla**: un `INSERT` para todas las reglas, con `WHERE > 0`.
- La decisión sobre un registro inválido depende de criticidad, determinismo, volumen y **si alguien va a mirar**.
- **Validá el conjunto, no solo las filas**: volumen y frescura.
- La línea base usa el promedio de corridas exitosas, ignora la primera vez, y **se envenena con filas de prueba**.
- **Una validación no probada es una hipótesis.** Forzá el fallo.
- El andamiaje de prueba vive en `tests/` y se limpia siempre.

---

## 🗂️ Flashcards

| Pregunta | Respuesta |
|---|---|
| ¿Seis dimensiones de calidad? | Completitud, unicidad, validez, exactitud, consistencia, oportunidad. |
| ¿Cuál no se puede validar internamente? | Exactitud: requiere una fuente externa de verdad. |
| ¿Qué es un valor centinela? | Un valor que significa "sin dato" sin ser NULL. |
| ¿Tres fechas centinela típicas? | `1900-01-01`, `1899-12-30` (Excel), `0001-01-01` (.NET). |
| ¿Qué es un registro huérfano? | El que referencia una clave que no existe. |
| ¿Por qué son peligrosos en la fact table? | El `INNER JOIN` los descarta sin avisar. |
| ¿Solución estándar de Kimball? | Miembro desconocido (`-1`) y `LEFT JOIN`. |
| ¿Qué es agregación condicional? | `SUM(CASE WHEN ... THEN 1 ELSE 0 END)` para varias métricas en una pasada. |
| ¿Por qué no `COUNT(CASE)`? | Emite el warning 8153 y ensucia el historial del job. |
| ¿Qué es un constructor de tabla? | `(VALUES (...),(...)) AS v(col1, col2)`. |
| ¿Fail fast vs log and continue? | Proceso roto → parar. Dato malo → registrar y seguir. |
| ¿Qué detecta la validación de volumen? | Que faltan datos aunque cada fila sea válida. |
| ¿Por qué promedio de 5 y no la última? | Una corrida anómala envenenaría la comparación siguiente. |
| ¿Por qué solo corridas `Succeeded`? | Las fallidas tienen rowcount parcial o nulo. |
| ¿Por qué `IF @Baseline IS NOT NULL`? | La primera vez no hay historia; sin eso la validación no existe. |
| ¿Qué es data observability? | Monitorear volumen, frescura, distribución y esquema. |
| ¿Qué es reconciliation? | Cuadrar conteos y sumas contra el origen. |
| ¿Cómo se prueba una validación? | Ensuciando datos a propósito y verificando que se dispara. |
| ¿Dónde vive el andamiaje de prueba? | En `tests/`, nunca en el procedimiento de producción. |
| ¿Por qué `LEN()` no detecta espacios finales? | Porque los ignora. Usá `DATALENGTH()` o compará con `RTRIM()`. |

---

## ☑️ Checklist antes de avanzar

- [ ] Documenté qué significa el NULL de cada columna que valido.
- [ ] Mi validador usa agregación condicional y `SUM(CASE)`.
- [ ] Registro con un solo `INSERT` y constructor de tabla.
- [ ] Solo se registra lo que encontró algo (`WHERE > 0`).
- [ ] `SchemaName` está en el `INSERT` (verificado ejecutándolo con datos sucios).
- [ ] Tengo validación de volumen con línea base histórica.
- [ ] La validación de volumen está **dentro** de la transacción.
- [ ] Verifiqué que no hay filas de prueba en `etl.LoadBatch`.
- [ ] Probé cada validación forzando el problema.
- [ ] Cada prueba tiene su limpieza y la ejecuté.
- [ ] Puedo explicar mi decisión sobre registros inválidos con el marco de 4.12.

---

## 📋 Examen del Módulo 4

### Selección múltiple

**1.** Todas las validaciones de fila pasan pero faltan 33.000 pedidos. ¿Qué validación falta?
a) Integridad referencial
b) Validación de volumen contra línea base histórica
c) Validación de rango
d) Validación de duplicados

**2.** ¿Por qué `SUM(CASE ... ELSE 0 END)` y no `COUNT(CASE ... END)`?
a) Da un resultado distinto
b) Es más rápido
c) `COUNT` emite el warning 8153 y ensucia el historial del job
d) `COUNT` no funciona con `CASE`

**3.** ¿Cuál NO es una dimensión de la calidad de datos?
a) Completitud   b) Unicidad   c) **Escalabilidad**   d) Oportunidad

**4.** Un `INNER JOIN` entre la fact table y una dimensión con huérfanos:
a) Falla con error
b) Descarta silenciosamente esas filas
c) Las carga con NULL
d) Emite un warning

**5.** ¿Por qué la línea base usa el promedio de las últimas 5 corridas exitosas?
a) Es más rápido
b) Para que una corrida anómala no envenene la comparación siguiente
c) SQL Server lo requiere
d) Para usar menos memoria

**6.** `'N/A'` en un campo obligatorio es un problema de:
a) Unicidad   b) Completitud disfrazada   c) Consistencia   d) Oportunidad

**7.** ¿Cuál dimensión NO se puede validar dentro del sistema?
a) Completitud   b) Validez   c) **Exactitud**   d) Unicidad

### Verdadero / Falso

**8.** Todo NULL en una tabla de staging es un problema de calidad.
**9.** Una validación que nunca se disparó está probada si el código se ve correcto.
**10.** La validación de volumen debe estar dentro de la transacción para que el rollback preserve los datos anteriores.
**11.** `LEN('abc   ')` en SQL Server devuelve 6.
**12.** Corregir automáticamente un dato faltante con un valor por defecto siempre es mejor que dejarlo nulo.
**13.** Un duplicado lógico es más grave que uno exacto.
**14.** Una tabla de cuarentena resuelve el problema aunque nadie la revise.

### SQL

**15.** Escribí un validador para `Sales.OrderLines` que cubra las seis dimensiones aplicables, con agregación condicional y un solo `INSERT`.

**16.** Escribí una consulta que muestre la **tendencia** de cada regla de validación en los últimos 30 días: regla, promedio diario, máximo, y si viene creciendo.

### Debugging

**17.** Este validador se desplegó hace tres meses y nunca falló. Encontrá el bug y explicá **por qué no se manifestó antes** y cuándo se va a manifestar.

```sql
IF @CustomerNull > 0
    INSERT INTO etl.ValidationLog (LoadBatchId, TableName, RuleName, AffectedRowCount)
    VALUES (@BatchId, N'Orders', N'CustomerID_NULL', @CustomerNull);
```

**18.** El job falla todas las noches con "Caida de volumen: se cargaron 73595 filas contra una linea base de 158876". El origen no cambió y los datos están bien. ¿Qué pasó y cómo lo arreglás?

### Análisis de escenario

**19.** Un dashboard muestra ventas 12% por debajo del sistema transaccional. Las validaciones de staging pasan todas y el conteo de filas de staging cuadra con el origen. Enumerá, en orden de probabilidad, las cinco causas posibles y qué consulta usarías para descartar cada una.

### Diseño

**20.** Diseñá la estrategia de validación para una tabla de pagos donde: el monto es crítico, la referencia externa puede faltar legítimamente, el país viene de un sistema con formato inconsistente, y el 2% de los registros llega con fecha futura por un problema conocido de zona horaria que se va a corregir en tres meses. Para cada campo: qué validás, con qué severidad, y qué hacés con los registros que fallan. Justificá con el marco de 4.12.

