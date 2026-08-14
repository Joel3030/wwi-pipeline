---

# Módulo 14 — DAX

> No vas a memorizar funciones. Vas a entender **cómo piensa DAX**, que es lo único que hace falta para deducir el resto.

## 🎯 Objetivos

- Explicar el modelo mental de DAX y en qué se diferencia de SQL.
- Distinguir medidas de columnas calculadas y elegir correctamente.
- **Dominar contexto de fila y contexto de filtro** — el 80% de DAX está acá.
- Entender la transición de contexto.
- Distinguir agregadores de iteradores (`SUM` vs `SUMX`).
- Usar `CALCULATE` entendiendo qué hace de verdad.
- Aplicar `FILTER`, `ALL`, `RELATED` y las funciones de tiempo.
- Escribir las métricas de negocio del proyecto.

---

## 📖 Teoría

### 14.1 Cómo piensa DAX

**DAX** (*Data Analysis Expressions*) es el lenguaje de fórmulas de Power BI, Analysis Services Tabular y Power Pivot.

**La diferencia de fondo con SQL, y hay que entenderla antes que cualquier función:**

> **SQL es imperativo sobre conjuntos: vos decís qué filas querés.**
> **DAX es evaluado en contexto: el contexto decide qué filas hay, y vos decís qué hacer con ellas.**

En SQL escribís:

```sql
SELECT SUM(SalesAmount) FROM FactSales WHERE Anio = 2025;
```

Vos ponés el `WHERE`. En DAX escribís:

```dax
Ventas = SUM(FactSales[SalesAmount])
```

**Sin ningún filtro.** Y esa misma medida devuelve:

- El total general en una tarjeta.
- Las ventas de agosto en la fila de agosto de una tabla.
- Las ventas de Argentina en la barra de Argentina de un gráfico.
- Las ventas de agosto en Argentina si el usuario filtra las dos cosas.

**Una fórmula, infinitos resultados.** El *dónde* lo pone el contexto: la visualización, los segmentadores, la fila de la tabla, los filtros de página.

> **💡 El modelo mental que hay que instalar:** cada celda de cada visualización ejecuta tu medida **de nuevo**, con un conjunto de filtros distinto. Una tabla de 12 meses × 5 categorías ejecuta la medida **60 veces**, cada vez sobre un subconjunto diferente.
>
> Si entendés eso, entendés DAX. Todo lo demás son detalles.

---

### 14.2 Medidas vs columnas calculadas

**Esta distinción es la primera fuente de errores de todo principiante.**

| | Columna calculada | Medida |
|---|---|---|
| Se evalúa | Al **actualizar** los datos | Al **consultar**, en cada celda |
| Se almacena | ✅ Ocupa memoria | ❌ No ocupa |
| Contexto | **De fila** | **De filtro** |
| Resultado | Un valor por fila | Un valor por contexto |
| Responde al filtro del usuario | ❌ No | ✅ Sí |
| Se puede usar en | Ejes, filtros, segmentadores | Valores |

**Columna calculada:**

```dax
-- En FactSales. Se calcula una vez por fila, al actualizar.
Margen = FactSales[SalesAmount] - RELATED(DimProduct[CostoUnitario]) * FactSales[Quantity]
```

**Medida:**

```dax
-- Se calcula en cada celda, sobre las filas que el contexto deje visibles.
Total Ventas = SUM(FactSales[SalesAmount])
```

**Cuándo cada una — la regla:**

> **Usá una MEDIDA salvo que necesites la columna en un eje, un filtro o un segmentador.**

**Por qué preferir medidas:**

1. **No ocupan memoria.** Una columna calculada en una tabla de 231.412 filas guarda 231.412 valores.
2. **Responden al filtro.** Una columna calculada es un valor fijo por fila; no puede cambiar según lo que el usuario seleccione.
3. **Se optimizan mejor.** El motor puede aplicar mejor la eliminación de segmentos.

**Cuándo sí una columna calculada:** cuando necesitás **agrupar o filtrar** por el valor. Por ejemplo, clasificar ventas en "Chica / Mediana / Grande" para usarlo como eje de un gráfico. Una medida no puede ir en un eje.

> **✅ Y la mejor opción de todas: hacerlo en SQL.** Una columna calculada de DAX que no depende del contexto es un cálculo que se hace mejor aguas arriba (Módulo 12). Si `Margen` no depende de filtros, ponelo en `FactSales` desde el ETL.

---

### 14.3 Contexto de fila y contexto de filtro

**Este es el corazón de DAX.** Si entendés esta sección, el resto se deduce.

#### Contexto de fila (*row context*)

> **Existe cuando DAX está recorriendo una tabla fila por fila y "sabe" en cuál está.**

Aparece en exactamente dos lugares:

1. **En una columna calculada** — se evalúa una vez por fila.
2. **Dentro de una función iteradora** (`SUMX`, `AVERAGEX`, `FILTER`, `ADDCOLUMNS`...).

```dax
-- Columna calculada: hay contexto de fila.
-- FactSales[Quantity] se refiere a la cantidad DE ESTA FILA.
Importe = FactSales[Quantity] * FactSales[UnitPrice]
```

> **⚠️ El contexto de fila NO filtra el modelo.** Solo permite referirse a los valores de la fila actual. Esta distinción es la causa de la mayoría de las confusiones — y de la necesidad de la transición de contexto (14.4).

#### Contexto de filtro (*filter context*)

> **Es el conjunto de filtros activos cuando se evalúa una expresión.**

Viene de todas partes a la vez:

- La fila y la columna de la tabla o matriz
- Los segmentadores
- Los filtros de visual, página e informe
- Los filtros que agregue `CALCULATE`
- El resaltado cruzado al hacer clic en otro gráfico

```dax
Total Ventas = SUM(FactSales[SalesAmount])
```

En la celda "Agosto 2026 / Bebidas", el contexto de filtro es `DimDate[MesAnioNombre] = "Ago 2026"` **y** `DimProduct[Categoria] = "Bebidas"`. El `SUM` opera solo sobre las filas que sobreviven a esos filtros.

#### La tabla que resume todo

| | Contexto de fila | Contexto de filtro |
|---|---|---|
| Qué es | "Estoy en esta fila" | "Estas filas están visibles" |
| Dónde nace | Columnas calculadas, iteradores | Visualizaciones, segmentadores, `CALCULATE` |
| ¿Filtra el modelo? | **No** | **Sí** |
| ¿Se propaga por relaciones? | **No** | **Sí** (de la dimensión a los hechos) |

> **🎓 Si te preguntan una sola cosa de DAX en una entrevista, va a ser esta.** La respuesta que se busca: *"El contexto de fila es saber en qué fila estás mientras iterás; no filtra nada. El contexto de filtro es el conjunto de filtros activos, y sí determina qué filas son visibles. Se propagan de forma distinta y `CALCULATE` es lo que convierte uno en otro."*

---

### 14.4 Transición de contexto

> ➕ **Tema adicional recomendado:** *context transition*
> **Por qué necesito aprenderlo:** explica comportamientos que parecen mágicos y es la pregunta de DAX de nivel intermedio-avanzado.
> **En qué parte del proyecto lo utilizaremos:** en cualquier medida que use `CALCULATE` dentro de un iterador.

> **💡 Concepto clave.** Cuando `CALCULATE` se ejecuta dentro de un contexto de fila, **convierte esa fila en un contexto de filtro**. Se llama **transición de contexto**.

```dax
-- Columna calculada en DimCustomer
Ventas del cliente = CALCULATE(SUM(FactSales[SalesAmount]))
```

Sin `CALCULATE`, `SUM(FactSales[SalesAmount])` daría **el total de todas las ventas** en cada fila, porque el contexto de fila de `DimCustomer` no filtra `FactSales`.

Con `CALCULATE`, la fila actual de `DimCustomer` se convierte en un filtro (`CustomerKey = <el de esta fila>`), ese filtro **se propaga por la relación** hasta `FactSales`, y el resultado es lo que ese cliente compró.

**Y el detalle que sorprende:** cualquier **medida** invocada dentro de un contexto de fila hace transición de contexto automáticamente, porque toda medida lleva un `CALCULATE` implícito.

```dax
-- Esto funciona: [Total Ventas] es una medida, así que hay transición implícita
Clientes grandes = COUNTROWS(FILTER(DimCustomer, [Total Ventas] > 100000))
```

> **⚠️ El costo:** la transición de contexto dentro de un iterador sobre una tabla grande es **cara**. Se ejecuta una vez por fila. Sobre `DimCustomer` (663 filas) es trivial; sobre `FactSales` (231.412) puede ser lentísimo. Es una de las primeras cosas a mirar cuando una medida tarda.

---

### 14.5 `SUM` vs `SUMX`: agregadores e iteradores

**Agregador** — opera sobre **una columna**, de una sola vez.

```dax
Total Ventas = SUM(FactSales[SalesAmount])
```

**Iterador** (terminan en `X`) — recorre **una tabla** fila por fila, evalúa una expresión en cada una, y agrega los resultados.

```dax
Total Ventas Calculado = SUMX(FactSales, FactSales[Quantity] * FactSales[UnitPrice])
```

**La diferencia crítica: `SUMX` crea contexto de fila.** Por eso puede multiplicar dos columnas — sabe en qué fila está. `SUM` no puede: solo recibe una columna.

```dax
-- ❌ ERROR: SUM no puede evaluar una expresión de varias columnas
Mal = SUM(FactSales[Quantity] * FactSales[UnitPrice])
```

**Cuándo cada uno:**

| Situación | Usar |
|---|---|
| Sumar una columna que existe | `SUM` — más rápido |
| Calcular fila por fila y después sumar | `SUMX` |
| El cálculo involucra columnas de tablas relacionadas | `SUMX` + `RELATED` |

> **⚠️ El error de sumar antes de multiplicar.** Estas dos NO son equivalentes:
>
> ```dax
> Correcto = SUMX(FactSales, FactSales[Quantity] * FactSales[UnitPrice])
> Incorrecto = SUM(FactSales[Quantity]) * SUM(FactSales[UnitPrice])
> ```
>
> La segunda multiplica el total de unidades por el total de precios: un número enorme y sin sentido. **Es la razón por la que existen los iteradores.**

**Los iteradores más usados:** `SUMX`, `AVERAGEX`, `MINX`, `MAXX`, `COUNTX`, `RANKX`, `CONCATENATEX`.

---

### 14.6 Funciones de conteo

```dax
Cantidad de líneas   = COUNTROWS(FactSales)                    -- filas de una tabla
Ventas con vendedor  = COUNT(FactSales[SalespersonKey])        -- valores NO nulos
Clientes distintos   = DISTINCTCOUNT(FactSales[CustomerKey])   -- valores distintos
Pedidos              = DISTINCTCOUNT(FactSales[OrderID])       -- dimensión degenerada
Clientes en catálogo = COUNTROWS(DimCustomer)                  -- todos, compren o no
```

**Diferencias que importan:**

- `COUNTROWS(tabla)` cuenta filas. **Es la forma preferida** de contar: más rápida y más clara que `COUNT` de una columna.
- `COUNT(columna)` cuenta valores **no vacíos**.
- `DISTINCTCOUNT` cuenta valores distintos. **Es caro** en columnas de alta cardinalidad, porque requiere materializar los valores únicos.

**El contraste que enseña:**

```dax
Clientes que compraron = DISTINCTCOUNT(FactSales[CustomerKey])
Clientes en catálogo   = COUNTROWS(DimCustomer)
Clientes sin compras   = [Clientes en catálogo] - [Clientes que compraron]
```

Ese último cálculo **es imposible con una tabla plana**: los clientes sin ventas no tendrían fila. Es el argumento práctico del esquema estrella del Módulo 13.

---

### 14.7 `CALCULATE`

> **La función más importante de DAX. La única que puede modificar el contexto de filtro.**

```dax
CALCULATE(<expresión>, <filtro1>, <filtro2>, ...)
```

**Qué hace, en tres pasos:**

1. Toma el contexto de filtro actual.
2. **Lo modifica** con los filtros que le pasás.
3. Evalúa la expresión en ese contexto nuevo.

```dax
Ventas Bebidas = CALCULATE(
    SUM(FactSales[SalesAmount]),
    DimProduct[Categoria] = "Bebidas"
)
```

**Qué pasa exactamente:** el filtro de `Categoria` **reemplaza** cualquier filtro que ya existiera sobre esa columna. Si el usuario seleccionó "Confitería", esta medida sigue devolviendo bebidas.

> **⚠️ `CALCULATE` REEMPLAZA, no acumula, cuando el filtro es sobre la misma columna.** Es el comportamiento que más sorprende, y es intencional.
>
> - Filtro sobre una columna **distinta** a las del contexto → **se agrega** (intersección).
> - Filtro sobre una columna **ya filtrada** → **reemplaza** el filtro anterior sobre esa columna.
>
> Si querés que se agregue en vez de reemplazar, usá `KEEPFILTERS`:
>
> ```dax
> CALCULATE(SUM(FactSales[SalesAmount]), KEEPFILTERS(DimProduct[Categoria] = "Bebidas"))
> ```
>
> Ahora, si el usuario filtró "Confitería", el resultado es **vacío** (la intersección de Bebidas y Confitería), que probablemente sea lo que esperabas.

**Los tres usos:**

```dax
-- 1. Agregar un filtro
Ventas 2025 = CALCULATE([Total Ventas], DimDate[Anio] = 2025)

-- 2. Quitar filtros
Ventas Totales = CALCULATE([Total Ventas], ALL(DimProduct))

-- 3. Cambiar el contexto de tiempo
Ventas Año Anterior = CALCULATE([Total Ventas], SAMEPERIODLASTYEAR(DimDate[FechaCompleta]))
```

> **💡 Y el dato que explica mucho: toda medida lleva un `CALCULATE` implícito.** Por eso `[Total Ventas]` dentro de un iterador hace transición de contexto (14.4). No es magia: es el `CALCULATE` que está ahí sin que lo escribas.

---

### 14.8 `FILTER`

`FILTER` devuelve una **tabla** con las filas que cumplen una condición. Es un iterador, así que crea contexto de fila.

```dax
Ventas Grandes = CALCULATE(
    [Total Ventas],
    FILTER(FactSales, FactSales[SalesAmount] > 1000)
)
```

**Cuándo hace falta `FILTER` y cuándo no:**

```dax
-- ✅ Filtro simple: NO necesita FILTER
CALCULATE([Total Ventas], DimProduct[Categoria] = "Bebidas")

-- ✅ Condición compleja o que compara columnas: SÍ necesita FILTER
CALCULATE([Total Ventas], FILTER(FactSales, FactSales[SalesAmount] > FactSales[Quantity] * 100))

-- ✅ Condición sobre una MEDIDA: SÍ necesita FILTER
CALCULATE([Total Ventas], FILTER(DimCustomer, [Total Ventas] > 50000))
```

> **⚠️ Rendimiento: `FILTER` sobre una tabla grande es caro.** Itera fila por fila.
>
> ```dax
> -- ❌ Lento: itera 231.412 filas
> CALCULATE([Total Ventas], FILTER(FactSales, RELATED(DimProduct[Categoria]) = "Bebidas"))
>
> -- ✅ Rápido: filtra la dimensión (227 filas) y deja que se propague
> CALCULATE([Total Ventas], DimProduct[Categoria] = "Bebidas")
> ```
>
> **Regla: filtrá la dimensión, no la fact table.** El filtro se propaga solo por la relación, y la dimensión es órdenes de magnitud más chica.

---

### 14.9 `ALL`, `ALLEXCEPT`, `REMOVEFILTERS`

Quitan filtros del contexto. Son la base de todo cálculo de porcentaje sobre el total.

```dax
-- Total sin ningún filtro del modelo
Ventas Absolutas = CALCULATE([Total Ventas], ALL(FactSales))

-- Total ignorando los filtros de producto, respetando los demás
Ventas Todos los Productos = CALCULATE([Total Ventas], ALL(DimProduct))

-- Total ignorando todo MENOS el país
Ventas del País = CALCULATE([Total Ventas], ALLEXCEPT(DimCustomer, DimCustomer[Pais]))

-- REMOVEFILTERS es sinónimo de ALL, con nombre más claro
Ventas sin filtro de fecha = CALCULATE([Total Ventas], REMOVEFILTERS(DimDate))
```

**El caso de uso central — porcentaje sobre el total:**

```dax
% del Total =
DIVIDE(
    [Total Ventas],
    CALCULATE([Total Ventas], ALL(DimProduct)),
    0
)
```

El numerador respeta el contexto (las ventas de esta categoría); el denominador quita el filtro de producto (todas las categorías). El cociente es la participación.

> **✅ Usá `DIVIDE` en lugar de `/`.** `DIVIDE(a, b, alternativa)` maneja la división por cero devolviendo el tercer argumento (o vacío) en lugar de un error. Es el equivalente de `NULLIF` en SQL, y por la misma razón.

**`ALL` vs `ALLSELECTED` — la diferencia sutil que importa:**

- `ALL(tabla)` quita **todos** los filtros, incluidos los segmentadores del usuario.
- `ALLSELECTED(tabla)` quita los filtros de la visualización pero **respeta** los segmentadores.

Ejemplo: el usuario filtró "año 2025" con un segmentador y mira una tabla por categoría.
- Con `ALL`: el denominador son las ventas de **todos los años**.
- Con `ALLSELECTED`: el denominador son las ventas de **2025**, que casi siempre es lo que el usuario espera al ver un porcentaje.

---

### 14.10 `RELATED` y `RELATEDTABLE`

**`RELATED`** — trae un valor del lado "uno" de la relación. Requiere contexto de fila.

```dax
-- Columna calculada en FactSales
Categoria = RELATED(DimProduct[Categoria])

-- Dentro de un iterador
Costo Total = SUMX(FactSales, FactSales[Quantity] * RELATED(DimProduct[CostoUnitario]))
```

**`RELATEDTABLE`** — trae las filas relacionadas del lado "muchos". Devuelve una tabla.

```dax
-- Columna calculada en DimCustomer
Cantidad de Ventas = COUNTROWS(RELATEDTABLE(FactSales))
```

> **✅ Regla mnemotécnica:** `RELATED` va **de muchos a uno** (de la fact table a la dimensión). `RELATEDTABLE` va **de uno a muchos** (de la dimensión a la fact table).
>
> Y una nota práctica: en la mayoría de los casos **no hacen falta**, porque el contexto de filtro ya se propaga por las relaciones. Solo se necesitan dentro de un contexto de fila. Si estás usando `RELATED` en una medida sin iterador, probablemente estés complicando algo simple.

---

### 14.11 Time Intelligence

Requieren una **tabla de fechas marcada** (Módulo 13). Sin eso, no funcionan o dan resultados incorrectos.

```dax
-- Mismo período del año anterior
Ventas AA = CALCULATE([Total Ventas], SAMEPERIODLASTYEAR(DimDate[FechaCompleta]))

-- Acumulado del año hasta la fecha
Ventas YTD = TOTALYTD([Total Ventas], DimDate[FechaCompleta])

-- Acumulado de trimestre y mes
Ventas QTD = TOTALQTD([Total Ventas], DimDate[FechaCompleta])
Ventas MTD = TOTALMTD([Total Ventas], DimDate[FechaCompleta])

-- Mes anterior
Ventas Mes Anterior = CALCULATE([Total Ventas], DATEADD(DimDate[FechaCompleta], -1, MONTH))

-- Acumulado desde siempre
Ventas Acumuladas = CALCULATE([Total Ventas], DATESYTD(DimDate[FechaCompleta]))

-- Media móvil de 3 meses
Media Movil 3M =
AVERAGEX(
    DATESINPERIOD(DimDate[FechaCompleta], MAX(DimDate[FechaCompleta]), -3, MONTH),
    [Total Ventas]
)
```

**Las comparaciones que el negocio pide:**

```dax
Variacion vs AA = [Total Ventas] - [Ventas AA]

% Variacion vs AA = DIVIDE([Total Ventas] - [Ventas AA], [Ventas AA])
```

> **⚠️ Dos advertencias sobre Time Intelligence:**
>
> 1. **Requieren fechas contiguas.** Si `DimDate` tiene huecos, los resultados son silenciosamente incorrectos. Es la razón por la que la dimensión fecha se genera con **todos** los días, incluidos los que no tienen ventas.
> 2. **`SAMEPERIODLASTYEAR` compara el mismo día del calendario**, no el mismo día de la semana. Para negocios con fuerte estacionalidad semanal (retail), comparar el martes 5 de agosto contra el lunes 5 de agosto del año anterior puede distorsionar. En esos casos se usan calendarios fiscales de 4-4-5 semanas y comparaciones por número de semana.

---

### 14.12 Las métricas del proyecto

**Las medidas base:**

```dax
Total Ventas   = SUM(FactSales[SalesAmount])
Total Unidades = SUM(FactSales[Quantity])
Total Impuestos= SUM(FactSales[TaxAmount])
Total con IVA  = SUM(FactSales[TotalAmount])

Cantidad Pedidos  = DISTINCTCOUNT(FactSales[OrderID])
Cantidad Lineas   = COUNTROWS(FactSales)
Clientes Activos  = DISTINCTCOUNT(FactSales[CustomerKey])
Productos Vendidos= DISTINCTCOUNT(FactSales[ProductKey])
```

**Los KPIs derivados:**

```dax
Ticket Promedio =
DIVIDE([Total Ventas], [Cantidad Pedidos], 0)

Precio Promedio =
DIVIDE([Total Ventas], [Total Unidades], 0)
-- ⚠️ NO uses AVERAGE(FactSales[UnitPrice]): eso promedia precios
-- sin ponderar por cantidad, y es una medida no aditiva (Módulo 7).

Lineas por Pedido =
DIVIDE([Cantidad Lineas], [Cantidad Pedidos], 0)

Venta Promedio por Cliente =
DIVIDE([Total Ventas], [Clientes Activos], 0)

% del Total de Categorias =
DIVIDE([Total Ventas], CALCULATE([Total Ventas], ALLSELECTED(DimProduct)), 0)
```

**Las medidas avanzadas — y acá aparece `VAR`:**

```dax
Ranking de Producto =
RANKX(
    ALL(DimProduct[ProductName]),
    [Total Ventas],
    ,
    DESC,
    DENSE
)

Top 10 Productos =
VAR RankingActual =
    RANKX(ALL(DimProduct[ProductName]), [Total Ventas], , DESC, DENSE)
RETURN
    IF(RankingActual <= 10, [Total Ventas], BLANK())

Crecimiento Interanual =
VAR VentasActuales = [Total Ventas]
VAR VentasAnteriores = CALCULATE([Total Ventas], SAMEPERIODLASTYEAR(DimDate[FechaCompleta]))
RETURN
    DIVIDE(VentasActuales - VentasAnteriores, VentasAnteriores)

Clientes Nuevos del Mes =
VAR MesActual = MAX(DimDate[FechaCompleta])
VAR ClientesHastaAhora =
    CALCULATE(
        DISTINCTCOUNT(FactSales[CustomerKey]),
        DimDate[FechaCompleta] <= MesActual,
        REMOVEFILTERS(DimDate)
    )
VAR ClientesAntes =
    CALCULATE(
        DISTINCTCOUNT(FactSales[CustomerKey]),
        DimDate[FechaCompleta] < EOMONTH(MesActual, -1) + 1,
        REMOVEFILTERS(DimDate)
    )
RETURN
    ClientesHastaAhora - ClientesAntes
```

---

### 14.13 `VAR`

> ➕ **Tema adicional recomendado:** variables en DAX
> **Por qué necesito aprenderlo:** mejoran legibilidad y rendimiento, y son la marca de código DAX profesional.
> **En qué parte del proyecto lo utilizaremos:** en toda medida con más de una línea.

```dax
-- ❌ Sin VAR: [Ventas AA] se evalúa DOS veces
Crecimiento =
DIVIDE(
    [Total Ventas] - CALCULATE([Total Ventas], SAMEPERIODLASTYEAR(DimDate[FechaCompleta])),
    CALCULATE([Total Ventas], SAMEPERIODLASTYEAR(DimDate[FechaCompleta]))
)

-- ✅ Con VAR: se evalúa UNA vez
Crecimiento =
VAR Actual = [Total Ventas]
VAR Anterior = CALCULATE([Total Ventas], SAMEPERIODLASTYEAR(DimDate[FechaCompleta]))
RETURN
    DIVIDE(Actual - Anterior, Anterior)
```

**Las tres ventajas:**

1. **Rendimiento.** Cada `VAR` se evalúa una sola vez.
2. **Legibilidad.** Los nombres documentan la intención.
3. **Depuración.** Podés cambiar el `RETURN` para ver el valor de una variable intermedia. Es el `print` de DAX.

> **⚠️ Y una propiedad crucial: las variables se evalúan en el contexto donde se DECLARAN, no donde se usan.**
>
> ```dax
> Medida =
> VAR VentasTotales = [Total Ventas]        -- ← contexto ACTUAL
> RETURN
>     CALCULATE(VentasTotales, ALL(DimProduct))
>     -- VentasTotales NO se recalcula: ya es un valor fijo.
>     -- El ALL() no tiene ningún efecto sobre él.
> ```
>
> Esto sorprende a mucha gente y a veces **es exactamente lo que querés** (congelar un valor antes de cambiar el contexto). Pero si esperabas que el `CALCULATE` afectara a la variable, el resultado va a ser desconcertante.

---

## ⚠️ Errores comunes

**Usar columnas calculadas donde va una medida.** Ocupan memoria y no responden al filtro.

**`SUM(a * b)` en lugar de `SUMX(tabla, a * b)`.** El primero ni siquiera compila con varias columnas.

**`SUM(a) * SUM(b)` en lugar de `SUMX`.** Compila y da un número sin sentido.

**`AVERAGE(UnitPrice)` como "precio promedio".** No pondera por cantidad. Usá `DIVIDE([Ventas], [Unidades])`.

**`FILTER` sobre la fact table cuando alcanza filtrar la dimensión.** Órdenes de magnitud más lento.

**`/` en lugar de `DIVIDE`.** Error de división por cero.

**`ALL` cuando corresponde `ALLSELECTED`.** El porcentaje ignora los segmentadores del usuario y confunde.

**Esperar que `CALCULATE` acumule filtros sobre la misma columna.** Reemplaza. Usá `KEEPFILTERS`.

**Time Intelligence sin tabla de fechas marcada o con huecos.** Resultados silenciosamente incorrectos.

**Esperar que una `VAR` se recalcule dentro de un `CALCULATE`.** Se evalúa donde se declara.

**Transición de contexto dentro de un iterador sobre la fact table.** Se ejecuta 231.412 veces.

**No usar `VAR` y repetir expresiones caras.** Se evalúan varias veces.

---

## 🧠 Preguntas de comprensión

1. Una tabla con 12 meses y 5 categorías muestra `[Total Ventas]`. ¿Cuántas veces se evalúa la medida y con qué contexto cada vez?
2. ¿Por qué `SUM(FactSales[Quantity] * FactSales[UnitPrice])` no funciona pero `SUMX` sí?
3. Explicá la diferencia entre contexto de fila y contexto de filtro con un ejemplo de cada uno.
4. ¿Qué hace `CALCULATE` cuando el filtro que le pasás es sobre una columna que ya está filtrada?
5. El usuario filtró 2025 y ve un porcentaje por categoría. ¿`ALL` o `ALLSELECTED`? ¿Qué muestra cada uno?
6. ¿Por qué `[Ventas del cliente] = CALCULATE(SUM(FactSales[SalesAmount]))` funciona como columna calculada en `DimCustomer`?
7. ¿Por qué `AVERAGE(FactSales[UnitPrice])` no es el precio promedio?

---

## 📝 Ejercicios

**🟢 Básico.** Escribí las 8 medidas base de 14.12 y verificá que el total cuadra con `SELECT SUM(SalesAmount) FROM dw.FactSales`.

**🟢 Básico.** Creá `Ticket Promedio` y `Precio Promedio`. Compará `Precio Promedio` contra `AVERAGE(FactSales[UnitPrice])` y explicá la diferencia.

**🟡 Intermedio.** Escribí `Ventas AA`, `Variación` y `% Variación`. Verificá contra una consulta SQL con `LAG(ventas, 12)`.

**🟡 Intermedio.** Escribí `% del Total` con `ALL` y con `ALLSELECTED`. Poné las dos en la misma tabla, agregá un segmentador de año, y documentá cuándo difieren.

**🔴 Avanzado.** Escribí una medida de **retención de clientes**: porcentaje de clientes que compraron este mes y también el mes anterior.

**🔴 Avanzado.** Escribí una medida **ABC (análisis de Pareto)**: clasificar productos en A (80% acumulado de ventas), B (siguiente 15%) y C (el resto), respetando el contexto de filtro.

**🧠 Reto.** Escribí una medida de **cohortes**: para clientes agrupados por su mes de primera compra, cuántos siguen comprando N meses después. Requiere combinar contexto de fila, transición de contexto y manipulación de fechas. Es el ejercicio de DAX más difícil que vas a encontrar en un proyecto real.

---

## 🎓 Preguntas de entrevista

1. **¿Diferencia entre medida y columna calculada?** — Cuándo se evalúa, dónde se almacena, y **si responde al filtro del usuario**.
2. **Explicá contexto de fila y contexto de filtro.** — *La* pregunta de DAX. Ver 14.3.
3. **¿Qué hace `CALCULATE`?** — Modifica el contexto de filtro. Y aclarar que **reemplaza** sobre la misma columna.
4. **¿`SUM` o `SUMX`?** — Agregador vs iterador; `SUMX` crea contexto de fila.
5. **¿Qué es la transición de contexto?** — `CALCULATE` dentro de un contexto de fila convierte esa fila en filtro.
6. **¿`ALL` o `ALLSELECTED`?** — Uno ignora los segmentadores, el otro los respeta.
7. **¿Cómo calculás el mismo período del año anterior?** — `SAMEPERIODLASTYEAR` con tabla de fechas marcada.
8. **¿Por qué usar `VAR`?** — Rendimiento, legibilidad, depuración. Y que se evalúa donde se declara.
9. **Tu medida es lenta. ¿Qué mirás?** — `FILTER` sobre la fact table, transición de contexto en iteradores, `DISTINCTCOUNT` de alta cardinalidad, expresiones repetidas sin `VAR`.

---

## 📌 Resumen

- **DAX se evalúa en contexto.** Una fórmula, un resultado distinto por celda.
- **Medidas** salvo que necesites la columna en un eje, filtro o segmentador. Y si no depende del contexto, mejor en SQL.
- **Contexto de fila** = "estoy en esta fila", no filtra. **Contexto de filtro** = qué filas son visibles, sí filtra y se propaga por relaciones.
- **Transición de contexto**: `CALCULATE` dentro de un contexto de fila lo convierte en filtro. Toda medida lo hace implícitamente.
- **Iteradores (`X`)** crean contexto de fila. `SUMX` para calcular fila por fila.
- **`SUM(a) * SUM(b)` ≠ `SUMX(t, a*b)`.** El primero da un número sin sentido.
- **`CALCULATE` reemplaza** filtros sobre la misma columna. `KEEPFILTERS` para acumular.
- **`DIVIDE`, no `/`.**
- **`ALLSELECTED`** para porcentajes que respeten los segmentadores del usuario.
- **Filtrá la dimensión, no la fact table.**
- **Time Intelligence** necesita tabla de fechas marcada y sin huecos.
- **`VAR`** para rendimiento, legibilidad y depuración; se evalúa donde se declara.

---

## 🗂️ Flashcards

| Pregunta | Respuesta |
|---|---|
| ¿Medida o columna calculada? | Medida, salvo que la necesites en un eje, filtro o segmentador. |
| ¿Cuándo se evalúa una medida? | En cada celda de cada visualización, al consultar. |
| ¿Qué es el contexto de fila? | Saber en qué fila estás mientras iterás. **No filtra.** |
| ¿Qué es el contexto de filtro? | El conjunto de filtros activos. **Sí filtra** y se propaga. |
| ¿Dónde nace el contexto de fila? | Columnas calculadas e iteradores (funciones `X`). |
| ¿Qué es la transición de contexto? | `CALCULATE` en contexto de fila convierte la fila en filtro. |
| ¿Qué hace `CALCULATE`? | Modifica el contexto de filtro y evalúa la expresión ahí. |
| ¿`CALCULATE` suma o reemplaza filtros? | Reemplaza si es la misma columna; agrega si es otra. |
| ¿Cómo hacer que acumule? | `KEEPFILTERS`. |
| ¿`SUM` vs `SUMX`? | Agregador (una columna) vs iterador (fila por fila, con expresión). |
| ¿Por qué `SUM(a)*SUM(b)` está mal? | Multiplica totales; hay que multiplicar por fila y después sumar. |
| ¿`ALL` vs `ALLSELECTED`? | `ALL` ignora los segmentadores; `ALLSELECTED` los respeta. |
| ¿`RELATED` vs `RELATEDTABLE`? | De muchos a uno vs de uno a muchos. |
| ¿Por qué `DIVIDE` y no `/`? | Maneja la división por cero sin error. |
| ¿Precio promedio correcto? | `DIVIDE([Ventas], [Unidades])`, no `AVERAGE(UnitPrice)`. |
| ¿Qué requiere Time Intelligence? | Tabla de fechas marcada, contigua y sin nulos. |
| ¿Dónde se evalúa una `VAR`? | En el contexto donde se **declara**, no donde se usa. |
| ¿Cómo depurar una medida? | Cambiar el `RETURN` para devolver una variable intermedia. |
| ¿Filtrar la dimensión o la fact table? | La dimensión: el filtro se propaga y es mucho más chica. |

