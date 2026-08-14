---

# Módulo 9 — La capa de resumen

## 🎯 Objetivos

- Explicar qué es una capa de resumen y **cuándo no hace falta**.
- Distinguir datos detallados de agregados y las preguntas que responde cada uno.
- Dominar las funciones de agregación y sus trampas.
- Usar `GROUP BY`, `HAVING` y entender el orden lógico de ejecución.
- Aplicar `GROUPING SETS`, `ROLLUP` y `CUBE`.
- Usar funciones de ventana para métricas acumuladas.
- **Decidir qué resumir** con un criterio reproducible.
- Elegir entre vista, vista indexada y tabla materializada.

---

## 📖 Teoría

### 9.1 Qué es y cuándo NO hace falta

Una **capa de resumen** (*aggregate layer*, *summary tables*) son tablas con datos **pre-agregados** a un grano más grueso que la fact table.

```
FactSales           231.412 filas   (grano: línea de pedido)
        ↓
AggVentasMensuales    ~2.000 filas  (grano: mes × categoría × país)
```

**Empecemos por lo contraintuitivo: en este proyecto, probablemente no hace falta.**

231.412 filas es **nada** para SQL Server, y Power BI las importa en memoria comprimida sin ningún esfuerzo. Una consulta con `GROUP BY` sobre esa fact table responde en milisegundos.

> **⚠️ Agregar una capa de resumen "porque corresponde" es un error real y frecuente.** Cada tabla de resumen es: más código de carga, más validaciones, más superficie de falla, y —lo peor— **una oportunidad de que dos números no coincidan**. Si el dashboard muestra un total del resumen y el detalle da otro, perdiste la confianza que venías construyendo.

**Cuándo SÍ tiene sentido:**

| Situación | ¿Resumen? |
|---|---|
| Fact table de más de 100 millones de filas | ✅ Sí |
| Consultas que tardan más de 5 segundos | ✅ Sí |
| El mismo cálculo pesado repetido constantemente | ✅ Sí |
| Cálculos complejos (ventanas, autojoins) | ✅ Sí |
| Necesidad de congelar un número histórico | ✅ Sí |
| 231.412 filas y consultas de 200 ms | ❌ **No** |

**Lo hacemos igual en este proyecto**, con un objetivo declarado: **aprender la técnica y las funciones de agregación**. Esa es una razón legítima en un proyecto de aprendizaje, y decirlo así en una entrevista es mucho mejor que fingir una justificación de rendimiento que no se sostiene.

> **🎓 Y esta es una gran respuesta de entrevista:** *"Construí una capa de resumen, pero en ese volumen no era necesaria por rendimiento. La incluí para practicar la técnica. En un caso real la justificaría midiendo primero: si la consulta contra el detalle responde rápido, agregar una capa de resumen suma complejidad y riesgo de inconsistencia sin beneficio."* Eso demuestra criterio, que vale más que la implementación.

---

### 9.2 Detallado vs agregado

| | Detallado (`FactSales`) | Agregado |
|---|---|---|
| Grano | Línea de pedido | Mes × categoría × país |
| Filas | 231.412 | ~2.000 |
| Responde | Cualquier pregunta | Solo las de su grano |
| "¿Qué compró el cliente 42 el martes?" | ✅ | ❌ |
| "¿Ventas de agosto por categoría?" | ✅ (calculando) | ✅ (leyendo) |
| Flexibilidad | Total | Ninguna |
| Velocidad | Depende del volumen | Máxima |

**El compromiso es siempre el mismo: velocidad a cambio de flexibilidad.** Y la flexibilidad perdida no se recupera.

> **✅ Regla de arquitectura:** *el agregado nunca reemplaza al detalle, lo complementa.* Si borrás el detalle y te quedás con el resumen, cualquier pregunta nueva es incontestable. Y las preguntas nuevas son la mayoría de las preguntas.

---

### 9.3 Funciones de agregación y sus trampas

```sql
SELECT
    COUNT(*)                       AS Filas,          -- cuenta filas
    COUNT(SalespersonKey)          AS NoNulos,        -- ⚠️ IGNORA NULLs
    COUNT(DISTINCT CustomerKey)    AS Clientes,       -- valores distintos
    SUM(SalesAmount)               AS Ventas,
    AVG(SalesAmount)               AS Promedio,       -- ⚠️ IGNORA NULLs
    MIN(SalesAmount)               AS Minimo,
    MAX(SalesAmount)               AS Maximo,
    STDEV(SalesAmount)             AS Desvio
FROM dw.FactSales;
```

**Las cuatro trampas:**

**1 — `COUNT(*)` vs `COUNT(columna)`.** El primero cuenta filas; el segundo cuenta **valores no nulos**. Es la diferencia entre "cuántas ventas hubo" y "cuántas ventas tienen vendedor asignado". Ambas son preguntas legítimas y hay que saber cuál estás respondiendo.

**2 — `AVG` ignora los NULLs, y eso cambia el denominador.**

```sql
-- Valores: 10, 20, NULL, 30
AVG(x)                    -- = 20   (60 / 3)
SUM(x) / COUNT(*)         -- = 15   (60 / 4)
```

**Ninguno está mal. Responden preguntas distintas.** ¿El promedio de las ventas que tienen monto, o el promedio incluyendo las que no lo tienen como cero? Tenés que saber cuál pediste.

**3 — `AVG` sobre enteros hace división entera.**

```sql
SELECT AVG(Quantity) FROM dw.FactSales;               -- entero: 7
SELECT AVG(CAST(Quantity AS DECIMAL(18,4))) FROM ...; -- 7.4382
```

Silencioso y equivocado. El promedio de 7 y 8 da 7.

**4 — Promediar promedios.**

```sql
-- ❌ MAL
SELECT AVG(PromedioMensual) FROM (
    SELECT AVG(SalesAmount) AS PromedioMensual
    FROM dw.FactSales GROUP BY DateKey / 100
) AS m;

-- ✅ BIEN: recalcular desde los componentes
SELECT SUM(SalesAmount) / COUNT(*) FROM dw.FactSales;
```

Un mes con 10.000 ventas y otro con 100 pesan **igual** en el primer cálculo. Es la misma trampa de la aditividad del Módulo 7.

---

### 9.4 `GROUP BY`, `HAVING` y el orden lógico

```sql
SELECT   d.Anio, d.Mes, SUM(f.SalesAmount) AS Ventas
FROM     dw.FactSales f
JOIN     dw.DimDate d ON d.DateKey = f.DateKey
WHERE    d.Anio >= 2015                      -- filtra FILAS, antes de agrupar
GROUP BY d.Anio, d.Mes
HAVING   SUM(f.SalesAmount) > 100000         -- filtra GRUPOS, después
ORDER BY d.Anio, d.Mes;
```

**El orden lógico de ejecución** (distinto del orden en que se escribe):

```
1. FROM      →  6. SELECT
2. ON/JOIN   →  7. DISTINCT
3. WHERE     →  8. ORDER BY
4. GROUP BY  →  9. TOP / OFFSET-FETCH
5. HAVING
```

**Tres consecuencias prácticas que explican errores comunes:**

1. **`WHERE` no puede usar agregados.** Se ejecuta antes de `GROUP BY`, cuando los grupos no existen. Para eso está `HAVING`.
2. **`SELECT` se evalúa en el paso 6**, después de `GROUP BY` y `HAVING`. Por eso no se puede usar un alias del `SELECT` en el `WHERE`, ni en el `GROUP BY`.
3. **`ORDER BY` es el paso 8**, después del `SELECT`. **Por eso sí se puede usar un alias en `ORDER BY`.** Es la excepción que confunde a todo el mundo, y ahora sabés por qué existe.

> **✅ Rendimiento:** poné en `WHERE` todo lo que puedas. Filtrar antes de agrupar reduce el trabajo; filtrar después con `HAVING` ya pagó el costo de agrupar filas que se descartan.

---

### 9.5 Las agregaciones del proyecto

**Por fecha:**

```sql
SELECT d.Anio, d.Mes, d.MesNombre,
       COUNT(DISTINCT f.OrderID)  AS Pedidos,
       COUNT(*)                   AS Lineas,
       SUM(f.Quantity)            AS Unidades,
       SUM(f.SalesAmount)         AS Ventas,
       SUM(f.SalesAmount) / NULLIF(COUNT(DISTINCT f.OrderID), 0) AS TicketPromedio
FROM dw.FactSales f
JOIN dw.DimDate  d ON d.DateKey = f.DateKey
GROUP BY d.Anio, d.Mes, d.MesNombre
ORDER BY d.Anio, d.Mes;
```

> **⚠️ `NULLIF(x, 0)` en todo denominador.** Convierte el 0 en NULL, y dividir por NULL da NULL en lugar de lanzar "Divide by zero". **Un error de división por cero en un job nocturno tumba la carga entera**; un NULL se muestra como celda vacía y se puede investigar tranquilo. Es una de las defensas más baratas y más rentables del oficio.

**Por producto, cliente y vendedor** siguen el mismo patrón. Lo que cambia es el `GROUP BY`.

**La tabla de resumen resultante:**

```sql
CREATE TABLE dw.AggVentasMensuales (
    Anio               SMALLINT      NOT NULL,
    Mes                TINYINT       NOT NULL,
    CategoriaProducto  NVARCHAR(50)  NOT NULL,
    PaisCliente        NVARCHAR(60)  NOT NULL,
    Pedidos            INT           NOT NULL,
    Lineas             INT           NOT NULL,
    Unidades           INT           NOT NULL,
    Ventas             DECIMAL(18,2) NOT NULL,
    Impuestos          DECIMAL(18,2) NOT NULL,
    CargadoEn          DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_AggVentasMensuales
        PRIMARY KEY (Anio, Mes, CategoriaProducto, PaisCliente)
);
```

> **✅ La PK compuesta es el grano hecho constraint.** Declara qué representa una fila **y** impide físicamente insertar duplicados. Es documentación que el motor hace cumplir — la mejor clase de documentación.

> **⚠️ Y una advertencia sobre `COUNT(DISTINCT OrderID)`: no es aditivo.** Si guardás `Pedidos` por mes y después sumás doce meses para obtener el año, **el resultado está mal** cuando un mismo pedido cruza meses (raro acá) o, más comúnmente, cuando el conteo distinto se hace sobre clientes: la cantidad de clientes distintos del año **no** es la suma de los de cada mes.
>
> Es el error más común de las tablas de resumen. Los conteos distintos hay que recalcularlos desde el detalle en cada nivel de agregación.

---

### 9.6 `GROUPING SETS`, `ROLLUP` y `CUBE`

> ➕ **Tema adicional recomendado:** agregaciones multinivel
> **Por qué necesito aprenderlo:** producen subtotales y totales en una sola consulta, y aparecen en entrevistas de SQL avanzado.
> **En qué parte del proyecto lo utilizaremos:** al generar tablas de resumen con varios niveles de agregación.

**`ROLLUP`** — jerárquico: subtotales de derecha a izquierda.

```sql
SELECT d.Anio, d.Mes, SUM(f.SalesAmount) AS Ventas
FROM dw.FactSales f JOIN dw.DimDate d ON d.DateKey = f.DateKey
GROUP BY ROLLUP (d.Anio, d.Mes);
```

Devuelve: cada año-mes, **subtotal por año**, y **total general**.

**`CUBE`** — todas las combinaciones posibles.

```sql
GROUP BY CUBE (d.Anio, p.CategoriaPrincipal)
```

Devuelve: cada combinación, total por año, total por categoría, y total general. Con *n* columnas produce 2ⁿ niveles — cuidado con la explosión combinatoria.

**`GROUPING SETS`** — control explícito de qué niveles querés.

```sql
GROUP BY GROUPING SETS (
    (d.Anio, d.Mes, p.CategoriaPrincipal),   -- máximo detalle
    (d.Anio, p.CategoriaPrincipal),          -- por año y categoría
    (d.Anio),                                -- solo por año
    ()                                       -- total general
)
```

> **⚠️ Distinguir un subtotal de un NULL real.** En las filas de subtotal, las columnas agrupadas vienen NULL. Si la columna **también puede ser NULL en los datos**, no podés distinguir "subtotal" de "sin categoría". Para eso está `GROUPING()`:
>
> ```sql
> SELECT
>     CASE WHEN GROUPING(d.Anio) = 1 THEN N'TOTAL'
>          ELSE CAST(d.Anio AS NVARCHAR(4)) END AS Anio,
>     SUM(f.SalesAmount) AS Ventas
> FROM dw.FactSales f JOIN dw.DimDate d ON d.DateKey = f.DateKey
> GROUP BY ROLLUP (d.Anio);
> ```
>
> `GROUPING(col)` devuelve 1 si la fila es un subtotal para esa columna, 0 si es un valor real.

---

### 9.7 Funciones de ventana

> ➕ **Tema adicional recomendado:** funciones de ventana
> **Por qué necesito aprenderlo:** son la herramienta central del SQL analítico moderno y una de las preguntas técnicas más frecuentes en entrevistas de datos.
> **En qué parte del proyecto lo utilizaremos:** en métricas acumuladas, variaciones mes a mes y rankings.

**La diferencia con `GROUP BY`:** `GROUP BY` **colapsa** filas; una función de ventana **conserva** todas las filas y agrega una columna calculada sobre un conjunto relacionado.

```sql
WITH Mensual AS (
    SELECT d.Anio, d.Mes, SUM(f.SalesAmount) AS Ventas
    FROM dw.FactSales f JOIN dw.DimDate d ON d.DateKey = f.DateKey
    GROUP BY d.Anio, d.Mes
)
SELECT
    Anio, Mes, Ventas,

    -- Acumulado del año
    SUM(Ventas) OVER (PARTITION BY Anio ORDER BY Mes
                      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS AcumAnio,

    -- Mes anterior y variación
    LAG(Ventas, 1) OVER (ORDER BY Anio, Mes)                            AS MesAnterior,
    Ventas - LAG(Ventas, 1) OVER (ORDER BY Anio, Mes)                   AS Variacion,

    -- Mismo mes del año anterior
    LAG(Ventas, 12) OVER (ORDER BY Anio, Mes)                           AS MismoMesAnioAnt,

    -- Media móvil de 3 meses
    AVG(Ventas) OVER (ORDER BY Anio, Mes
                      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)         AS MediaMovil3,

    -- Ranking dentro del año
    RANK() OVER (PARTITION BY Anio ORDER BY Ventas DESC)                AS RankingMes,

    -- Participación sobre el total del año
    100.0 * Ventas / SUM(Ventas) OVER (PARTITION BY Anio)               AS PctDelAnio
FROM Mensual
ORDER BY Anio, Mes;
```

**Las tres piezas de una ventana:**

- **`PARTITION BY`** — reinicia el cálculo por grupo. Sin él, la ventana abarca todo.
- **`ORDER BY`** — define el orden dentro de la partición. Imprescindible para acumulados, `LAG` y `RANK`.
- **Marco (*frame*)** — `ROWS BETWEEN ... AND ...` define qué filas entran.

> **⚠️ La trampa del marco por defecto.** Si ponés `ORDER BY` sin especificar el marco, el implícito es `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`.
>
> **`RANGE` y `ROWS` no son lo mismo:** `RANGE` incluye **todas las filas con el mismo valor de orden** (empates), `ROWS` cuenta filas físicas. Si hay empates en la columna de orden, el acumulado "salta" incluyendo todos los empatados de golpe.
>
> **Sé explícito con `ROWS` siempre que quieras un acumulado fila a fila.** Además, `ROWS` suele ser más rápido porque no requiere resolver empates.

**`RANK` vs `DENSE_RANK` vs `ROW_NUMBER`:**

| Valores | `ROW_NUMBER` | `RANK` | `DENSE_RANK` |
|---|---|---|---|
| 100 | 1 | 1 | 1 |
| 90 | 2 | 2 | 2 |
| 90 | 3 | 2 | 2 |
| 80 | 4 | **4** | **3** |

`RANK` deja huecos tras un empate; `DENSE_RANK` no; `ROW_NUMBER` nunca empata (y es no determinístico entre filas iguales, salvo que desempates en el `ORDER BY`).

---

### 9.8 Cómo decidir qué resumir

**La regla del costo × frecuencia:**

> **Valor de un agregado = (costo de calcularlo al vuelo) × (veces que se pide)**

- Consulta de 200 ms pedida 50 veces por día → **no** vale la pena.
- Consulta de 45 segundos pedida 500 veces por día → **claramente** sí.

**Las cinco preguntas, en orden:**

1. **¿Se pide seguido?** Si es mensual, no.
2. **¿Es lenta contra el detalle?** **Medila.** No supongas.
3. **¿El grano del resumen sirve para varias preguntas?** Si sirve para una sola, es un reporte disfrazado de tabla.
4. **¿Se puede mantener consistente con el detalle?** Si el resumen puede desincronizarse, vas a tener dos números distintos.
5. **¿Vale más que su costo de mantenimiento?** Carga, validación, documentación, y la explicación cuando alguien pregunte por qué hay dos tablas.

> **✅ El orden importa: medí antes de optimizar.** La optimización prematura en BI es tan cara como en desarrollo, con el agravante de que introduce **riesgo de inconsistencia numérica**, que es el peor tipo de deuda en un sistema de datos.

---

### 9.9 Vista, vista indexada o tabla

| | Vista | Vista indexada | Tabla materializada |
|---|---|---|---|
| Almacena datos | ❌ | ✅ | ✅ |
| Actualización | Instantánea | Automática | Por ETL |
| Costo de escritura en la base | Ninguno | **Alto** | Ninguno |
| Control sobre cuándo se calcula | — | Ninguno | **Total** |
| Restricciones | Pocas | **Muchas** | Ninguna |

**Vista** — solo una consulta guardada. Sin costo de almacenamiento y sin ganancia de rendimiento. Útil para encapsular lógica.

**Vista indexada** (*indexed view*, el equivalente a las vistas materializadas de Oracle) — se materializa y **SQL Server la mantiene automáticamente** en cada cambio de las tablas base.

✅ Siempre consistente, sin código de mantenimiento
❌ **Cada `INSERT` en la fact table actualiza la vista** — en una carga masiva eso es carísimo. Y tiene restricciones severas: `SCHEMABINDING` obligatorio, sin `COUNT(*)` (hay que usar `COUNT_BIG(*)`), sin subconsultas, sin `OUTER JOIN`, sin funciones no determinísticas.

**Tabla materializada por ETL** — una tabla común que carga tu proceso.

✅ **Control total** sobre cuándo y cómo se calcula · Sin restricciones · Sin costo en las cargas
❌ Puede quedar desactualizada respecto del detalle · Hay que escribir y mantener la carga

**Para este proyecto: tabla materializada por ETL.** Encaja con el resto de la arquitectura (todo se carga en el mismo job, en orden controlado), no penaliza la carga de hechos, y no tiene restricciones. Además es lo que vas a encontrar en la mayoría de los warehouses reales.

---

### 9.10 Cuándo el resumen es solo duplicación

**Señales de que sobra:**

- El resumen tiene casi tantas filas como el detalle. Si `FactSales` tiene 231.412 y tu agregado 180.000, **no estás agregando nada**: elegiste un grano demasiado fino.
- La consulta contra el detalle ya responde rápido.
- Solo lo usa un reporte.
- Se desincroniza y nadie lo nota.
- Nadie sabe explicar por qué existe.

> **⚠️ Y el peor escenario posible: dos números distintos para la misma pregunta.** Si el dashboard muestra el total del resumen y alguien calcula el mismo total desde el detalle y da diferente, **perdiste toda la credibilidad del proyecto** — y el problema no es el número, es que ahora nadie sabe cuál creer.
>
> **Por eso toda tabla de resumen necesita su propia validación de cuadre**, que compare sus totales contra el detalle en cada carga. Sin eso, el resumen es un pasivo.

---

# Módulo 10 — Automatizar el Data Warehouse

> **Paso 5 del proyecto**

## 🎯 Objetivos

- Diseñar el flujo completo con sus dependencias.
- Elegir entre un job con muchos pasos y muchos jobs.
- Definir qué pasa ante un fallo intermedio.
- Implementar carga incremental de dimensiones y hechos.
- Usar marcas de agua para el control de fechas.
- Diseñar el reprocesamiento y las ventanas de recarga.
- Implementar auditoría de punta a punta.
- Garantizar idempotencia en el modelo dimensional.

---

## 📖 Teoría

### 10.1 El flujo completo y sus dependencias

```
                    ┌──────────────────────┐
                    │  WideWorldImporters  │
                    └──────────┬───────────┘
                               │
              ┌────────────────┴────────────────┐
              ▼                                 ▼
   ┌──────────────────┐              ┌──────────────────┐
   │ stg Sales.Orders │              │ stg OrderLines   │   ← pueden ir en paralelo
   └────────┬─────────┘              └────────┬─────────┘
            └────────────────┬────────────────┘
                             ▼
                  ┌────────────────────┐
                  │    VALIDACIONES    │   ← si fallan grave, se detiene
                  └─────────┬──────────┘
                            ▼
   ┌────────────┬───────────┴────────┬──────────────┐
   ▼            ▼                    ▼              ▼
DimDate    DimCustomer          DimProduct    DimSalesperson  ← paralelizables
   └────────────┴────────────────────┴──────────────┘
                            ▼
                     ┌─────────────┐
                     │  FactSales  │   ← requiere TODAS las dimensiones
                     └──────┬──────┘
                            ▼
                  ┌──────────────────┐
                  │ Tablas resumen   │
                  └────────┬─────────┘
                           ▼
                  ┌──────────────────┐
                  │ VALIDACIÓN FINAL │   ← cuadre contra el origen
                  └────────┬─────────┘
                           ▼
                     ┌──────────┐
                     │ Power BI │   ← actualización programada
                     └──────────┘
```

**Las cuatro reglas de dependencia:**

1. **Las dimensiones antes que los hechos.** Sin excepción: la fact table busca claves que deben existir.
2. **Staging antes que las dimensiones.** Las dimensiones leen de staging.
3. **Los hechos antes que el resumen.** Obvio pero fácil de romper si se separan en jobs.
4. **Validar antes de propagar.** Un problema detectado tarde ya contaminó todo lo de abajo.

---

### 10.2 Un job con muchos pasos

**La decisión, retomando el Módulo 5:** un solo job con pasos secuenciales.

**Por qué, en tres razones:**

1. **El orden queda garantizado** por construcción, no por una apuesta sobre duraciones.
2. **Un fallo detiene la cadena.** Si staging falla, no tiene sentido cargar dimensiones con datos viejos y hechos que apunten a ellas.
3. **Una sola alerta y un solo historial.** No hay que correlacionar seis jobs para entender qué pasó.

```sql
EXEC msdb.dbo.sp_add_job
    @job_name = N'WWI - Pipeline completo',
    @description = N'Staging -> Validaciones -> Dimensiones -> Hechos -> Resumen',
    @owner_login_name = N'sa',
    @notify_level_email = 2,
    @notify_email_operator_name = N'Joel';

-- Pasos 1..N, todos con @on_success_action = 3 (siguiente)
-- y @on_fail_action = 2 (salir con fallo), salvo el último
```

**Los pasos:**

| # | Paso | Comando | Ante fallo |
|---|---|---|---|
| 1 | Staging Orders | `EXEC etl.usp_LoadSalesOrders` | Detener |
| 2 | Staging OrderLines | `EXEC etl.usp_LoadSalesOrderLines` | Detener |
| 3 | DimDate | `EXEC dw.usp_LoadDimDate` | Detener |
| 4 | DimCustomer | `EXEC dw.usp_LoadDimCustomer` | Detener |
| 5 | DimProduct | `EXEC dw.usp_LoadDimProduct` | Detener |
| 6 | DimSalesperson | `EXEC dw.usp_LoadDimSalesperson` | Detener |
| 7 | FactSales | `EXEC dw.usp_LoadFactSales` | Detener |
| 8 | Resumen | `EXEC dw.usp_LoadAggregates` | Detener |
| 9 | Cuadre final | `EXEC dw.usp_ValidateWarehouse` | Detener |

> **✅ El paso 9 es el más importante y el que más se omite.** Después de cargar todo, verificar que el warehouse cuadra con el origen. Si no cuadra, **el job debe fallar** aunque todos los pasos anteriores hayan salido bien. Es la última red de seguridad antes de que alguien tome una decisión con esos números.

**Alternativa: un procedimiento orquestador.**

```sql
CREATE OR ALTER PROCEDURE dw.usp_LoadWarehouse
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC etl.usp_LoadSalesOrders;
    EXEC etl.usp_LoadSalesOrderLines;
    EXEC dw.usp_LoadDimDate;
    EXEC dw.usp_LoadDimCustomer;
    EXEC dw.usp_LoadDimProduct;
    EXEC dw.usp_LoadDimSalesperson;
    EXEC dw.usp_LoadFactSales;
    EXEC dw.usp_LoadAggregates;
    EXEC dw.usp_ValidateWarehouse;
END;
GO
```

**Compromiso honesto:** el orquestador es más simple y versionable, pero **pierde la granularidad del historial de Agent** — todo aparece como un solo paso, y no sabés cuál falló sin mirar `etl.LoadBatch`. Con una tabla de control bien hecha, es un costo aceptable. Sin ella, no.

---

### 10.3 Qué hacer ante un fallo intermedio

**El escenario:** falla `FactSales` (paso 7). Las dimensiones ya se actualizaron.

**El problema:** el warehouse queda **inconsistente**. `DimCustomer` tiene las versiones nuevas; `FactSales` sigue con los datos de ayer y apunta a claves de ayer.

**Las tres estrategias:**

**A — Transacción global.** Envolver todo en una transacción.

✅ Consistencia total
❌ **Inviable en la práctica**: una transacción de horas mantiene bloqueos sobre todo el warehouse, infla el log, y bloquea a Power BI durante la carga.

**B — Compensación.** Cada paso sabe deshacer lo suyo.

✅ Consistencia sin transacciones largas
❌ Complejo, propenso a errores. Rara vez vale la pena.

**C — Idempotencia + reintento (la recomendada).** Cada paso es idempotente; ante un fallo se arregla la causa y se corre todo de nuevo desde el principio.

✅ Simple · Robusto · Es la propiedad que ya venís construyendo
❌ El warehouse queda temporalmente inconsistente hasta que se corrija

> **✅ Estrategia C, con una salvaguarda que la hace aceptable: una marca de estado.**
>
> ```sql
> CREATE TABLE dw.WarehouseStatus (
>     Id            TINYINT   NOT NULL PRIMARY KEY DEFAULT 1,
>     UltimaCarga   DATETIME2 NULL,
>     EsConsistente BIT       NOT NULL DEFAULT 0,
>     Mensaje       NVARCHAR(400) NULL,
>     CONSTRAINT CK_WarehouseStatus_Single CHECK (Id = 1)
> );
> ```
>
> El primer paso la pone en 0; el último, tras el cuadre, en 1. **Power BI muestra esa marca**: si es 0, el dashboard advierte "datos en actualización o inconsistentes". El usuario ve el estado en lugar de números en los que no debería confiar.
>
> Es mucho más barato que la consistencia transaccional y resuelve el problema real, que es **no engañar a quien mira**.

---

### 10.4 Carga incremental

**Full load** —lo que hacemos— es lo correcto en este volumen. Pero hay que saber diseñar el incremental.

**Dimensiones — SCD Tipo 2 ya es incremental por naturaleza:** solo inserta versiones nuevas y cierra las que cambiaron. Se puede acotar el origen a lo modificado:

```sql
WHERE c.LastEditedWhen > @UltimaCargaDim
```

**Hechos — el patrón de ventana de recarga (*delete-insert*):**

```sql
DECLARE @Desde DATE = DATEADD(DAY, -7, CAST(SYSUTCDATETIME() AS DATE));

BEGIN TRANSACTION;

    -- 1. Borrar la ventana
    DELETE f
    FROM dw.FactSales f
    JOIN dw.DimDate d ON d.DateKey = f.DateKey
    WHERE d.FechaCompleta >= @Desde;

    -- 2. Reinsertar la ventana
    INSERT INTO dw.FactSales (...)
    SELECT ...
    FROM Sales.OrderLines ol
    JOIN Sales.Orders o ON o.OrderID = ol.OrderID
    LEFT JOIN dw.DimCustomer dc ON ... 
    WHERE o.OrderDate >= @Desde;

COMMIT TRANSACTION;
```

> **✅ Por qué borrar e insertar en lugar de `MERGE`:** es **idempotente por construcción**. Correrlo N veces deja exactamente el mismo resultado. Es la técnica más simple y más robusta para hechos, y es lo que se usa en la mayoría de los warehouses reales.

**Por qué una ventana de 7 días y no solo el día anterior:** porque los pedidos se modifican después de creados (se cancelan líneas, se corrigen cantidades). Una ventana de recarga captura esas correcciones **sin necesidad de detectarlas**. El ancho de la ventana se define con el negocio: *"¿cuántos días después de creado puede cambiar un pedido?"*.

---

### 10.5 Marcas de agua

> ➕ **Tema adicional recomendado:** *watermark*
> **Por qué necesito aprenderlo:** es el mecanismo estándar de control de cargas incrementales.
> **En qué parte del proyecto lo utilizaremos:** al migrar a incremental.

```sql
CREATE TABLE etl.LoadWatermark (
    SchemaName    NVARCHAR(128) NOT NULL,
    TableName     NVARCHAR(128) NOT NULL,
    WatermarkValue DATETIME2    NOT NULL,
    UpdatedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_LoadWatermark PRIMARY KEY (SchemaName, TableName)
);
```

**El patrón correcto — y el orden es lo importante:**

```sql
-- 1. Leer la marca anterior
DECLARE @Desde DATETIME2 = (SELECT WatermarkValue FROM etl.LoadWatermark
                            WHERE SchemaName = N'Sales' AND TableName = N'Orders');

-- 2. Capturar el techo ANTES de leer datos
DECLARE @Hasta DATETIME2 = SYSUTCDATETIME();

-- 3. Cargar el rango [Desde, Hasta)
INSERT INTO ... SELECT ... WHERE LastEditedWhen >= @Desde AND LastEditedWhen < @Hasta;

-- 4. Avanzar la marca SOLO si todo salió bien
UPDATE etl.LoadWatermark SET WatermarkValue = @Hasta, UpdatedAt = SYSUTCDATETIME()
WHERE SchemaName = N'Sales' AND TableName = N'Orders';
```

**Los tres errores clásicos de las marcas de agua:**

1. **Usar `MAX(LastEditedWhen)` de lo cargado como nueva marca.** Si no vino nada, la marca no avanza y en la siguiente corrida se recarga lo mismo. Peor: si el reloj del origen difiere, se pueden perder filas.
2. **Avanzar la marca antes de confirmar la carga.** Si la carga falla después, esos datos **nunca se vuelven a leer**. Pérdida silenciosa y permanente.
3. **Usar rangos cerrados `BETWEEN`.** Una fila con timestamp exactamente igual al límite se procesa **dos veces**. Usá `[desde, hasta)`.

---

### 10.6 Reprocesamiento

**El escenario real:** descubrís que la lógica de `SalesAmount` estaba mal durante tres meses.

**Lo que necesitás poder hacer:**

```sql
CREATE OR ALTER PROCEDURE dw.usp_ReprocessFactSales
    @Desde DATE,
    @Hasta DATE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Guardas: un reproceso mal parametrizado puede borrar años
    IF @Desde IS NULL OR @Hasta IS NULL
        THROW 50010, N'Ambas fechas son obligatorias.', 1;

    IF @Hasta < @Desde
        THROW 50011, N'La fecha final no puede ser anterior a la inicial.', 1;

    IF DATEDIFF(DAY, @Desde, @Hasta) > 400
        THROW 50012, N'El rango supera 400 dias. Reprocesar en tramos.', 1;

    BEGIN TRANSACTION;
        DELETE f FROM dw.FactSales f
        JOIN dw.DimDate d ON d.DateKey = f.DateKey
        WHERE d.FechaCompleta BETWEEN @Desde AND @Hasta;

        INSERT INTO dw.FactSales (...)
        SELECT ... WHERE o.OrderDate BETWEEN @Desde AND @Hasta;
    COMMIT TRANSACTION;
END;
GO
```

> **✅ Las guardas no son paranoia.** Un reproceso es una operación destructiva ejecutada bajo presión, normalmente por alguien apurado. `@Desde` en NULL sin validación borraría **todo**. El límite de 400 días evita que un typo de año inicie una operación de horas que bloquea el warehouse.
>
> **Toda operación destructiva parametrizada necesita guardas explícitas.** Es la misma disciplina que confirmar antes de un `DELETE` sin `WHERE`.

**Y la advertencia sobre SCD Tipo 2:** al reprocesar hechos viejos, la búsqueda por rango de fechas los va a asociar a las versiones **correctas de la dimensión** — siempre que la dimensión conserve el historial. Si `DimCustomer` fuera Tipo 1, reprocesar historia le aplicaría los atributos actuales y **cambiaría los reportes históricos**. Es una razón más para Tipo 2 en las dimensiones que importan.

---

### 10.7 Auditoría de punta a punta

> ➕ **Tema adicional recomendado:** linaje del dato
> **Por qué necesito aprenderlo:** responde "¿de dónde salió este número?", que es la pregunta que llega cuando algo no cuadra.
> **En qué parte del proyecto lo utilizaremos:** `LoadBatchId` viaja desde staging hasta la fact table.

**La cadena completa:**

```
etl.LoadBatch (staging)  ──LoadBatchId──►  Sales.Orders
                                                │
etl.LoadBatch (fact)     ──LoadBatchId──►  dw.FactSales
```

**La consulta que responde "¿de dónde salió este número?":**

```sql
SELECT
    f.OrderID, f.OrderLineID, f.SalesAmount,
    f.LoadBatchId                AS LoteHechos,
    lb.StartedAt                 AS CuandoSeCargo,
    lb.RowsLoaded                AS FilasDelLote,
    dc.CustomerName, dc.ValidoDesde, dc.ValidoHasta,   -- qué versión se usó
    dp.ProductName, dp.CategoriaPrincipal
FROM dw.FactSales f
JOIN etl.LoadBatch    lb ON lb.LoadBatchId = f.LoadBatchId
JOIN dw.DimCustomer   dc ON dc.CustomerKey = f.CustomerKey
JOIN dw.DimProduct    dp ON dp.ProductKey  = f.ProductKey
WHERE f.OrderID = 12345;
```

Con eso podés reconstruir: cuándo se cargó, en qué lote, qué versión del cliente se usó, y comparar contra el origen. **Es la diferencia entre "no sé por qué da eso" y "da eso porque el 15 de junio el cliente cambió de categoría".**

---

### 10.8 Idempotencia en el modelo dimensional

**Cada capa tiene su estrategia, y las cuatro deben cumplirse:**

| Capa | Estrategia | Verificación |
|---|---|---|
| Staging | `TRUNCATE` + `INSERT` | Mismo conteo, un solo `LoadBatchId` |
| `DimDate` | `RETURN` si ya tiene datos | Misma cantidad de filas |
| Dimensiones SCD2 | Insertar solo si cambió | **No se crean versiones nuevas si nada cambió** |
| `FactSales` | `TRUNCATE` + `INSERT` (o delete-insert por ventana) | Mismo conteo, misma suma |
| Resumen | `TRUNCATE` + `INSERT` | Mismo conteo, misma suma |

> **⚠️ El riesgo específico de SCD Tipo 2: la explosión de versiones.**
>
> Si la detección de cambios está mal —por ejemplo, comparando con `<>` sobre columnas nulables (8.3)— **cada corrida crea una versión nueva de cada cliente**, aunque nada haya cambiado. La dimensión crece linealmente con la cantidad de ejecuciones y en un mes tenés 30 versiones idénticas de cada cliente.
>
> **La prueba de idempotencia:**
>
> ```sql
> SELECT COUNT(*) FROM dw.DimCustomer;   -- anotar
> EXEC dw.usp_LoadDimCustomer;
> SELECT COUNT(*) FROM dw.DimCustomer;   -- DEBE ser igual
> ```
>
> Si crece sin que nada haya cambiado en el origen, la detección de cambios está rota. **Es la prueba más importante de toda la carga dimensional**, y la que casi nadie hace.

---

### 10.9 Monitoreo

**Qué medir en cada corrida:**

```sql
CREATE OR ALTER VIEW dw.vw_PipelineHealth
AS
SELECT
    lb.SchemaName + N'.' + lb.TableName                       AS Objeto,
    lb.StartedAt,
    DATEDIFF(SECOND, lb.StartedAt, lb.EndedAt)                AS DuracionSeg,
    lb.Status,
    lb.RowsLoaded,
    -- Comparación contra el promedio histórico
    AVG(lb.RowsLoaded) OVER (PARTITION BY lb.SchemaName, lb.TableName
                             ORDER BY lb.StartedAt
                             ROWS BETWEEN 5 PRECEDING AND 1 PRECEDING) AS PromedioPrevio,
    lb.ErrorMessage
FROM etl.LoadBatch lb
WHERE lb.StartedAt >= DATEADD(DAY, -30, SYSUTCDATETIME());
```

**Las cuatro señales que hay que vigilar, y qué significa cada una:**

1. **Duración creciente** — el volumen crece o hay degradación. Predice cuándo la carga va a salirse de la ventana de mantenimiento.
2. **Volumen anómalo** — la validación del Módulo 4, aplicada a cada objeto.
3. **Cargas colgadas** — `Running` antiguo.
4. **Cuadre roto** — el warehouse no coincide con el origen. **La más importante y la que hay que alertar con más urgencia.**

---

## 📌 Resumen (Módulos 9 y 10)

- Una capa de resumen **no siempre hace falta**. Medí antes de agregarla; su costo es complejidad y riesgo de inconsistencia.
- El agregado **complementa** al detalle, nunca lo reemplaza.
- Cuidado con `AVG` (ignora NULLs, división entera), promediar promedios, y **`COUNT(DISTINCT)` que no es aditivo**.
- El orden lógico de ejecución explica por qué `WHERE` no ve agregados y `ORDER BY` sí ve alias.
- `NULLIF(x, 0)` en todo denominador.
- Las funciones de ventana conservan las filas; sé explícito con `ROWS` en el marco.
- **Un job con muchos pasos**, con un paso final de cuadre que puede hacer fallar todo.
- Ante un fallo intermedio: **idempotencia + reintento**, con una marca de estado que Power BI muestre.
- Delete-insert por ventana es idempotente por construcción; la ventana la define el negocio.
- Marcas de agua: capturar el techo **antes** de leer, avanzar **después** de confirmar, rangos semiabiertos.
- Toda operación de reproceso necesita **guardas explícitas**.
- **Probá que recargar una dimensión SCD2 sin cambios no crea versiones nuevas.**

---

## 🎓 Preguntas de entrevista (Módulos 9 y 10)

1. **¿Cuándo crearías una tabla de resumen?** — Costo × frecuencia, medido. Y decir cuándo **no** lo harías.
2. **¿Qué diferencia hay entre `WHERE` y `HAVING`?** — Filas vs grupos, y el orden lógico que lo explica.
3. **¿Qué es una función de ventana?** — Conserva filas en vez de colapsarlas. Con un ejemplo de acumulado.
4. **¿`ROWS` o `RANGE`?** — `RANGE` incluye empates; `ROWS` cuenta filas físicas. Sé explícito.
5. **¿Cómo orquestás un pipeline con dependencias?** — Pasos del mismo job, orden por dependencia, cuadre final.
6. **¿Qué pasa si falla un paso intermedio?** — Idempotencia + reintento + marca de estado visible.
7. **¿Cómo hacés una carga incremental de hechos?** — Delete-insert por ventana; por qué es idempotente.
8. **¿Qué es un watermark y cuáles son sus errores clásicos?** — Ver 10.5.
9. **¿Cómo rastreás de dónde salió un número?** — `LoadBatchId` de punta a punta + versión de la dimensión.
10. **¿Cómo verificás que una carga SCD2 es idempotente?** — Recargar sin cambios no debe crear versiones.

