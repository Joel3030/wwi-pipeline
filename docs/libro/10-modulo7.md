---

# Módulo 7 — Modelado dimensional y esquema estrella

> **Paso 4 del proyecto, parte 1 de 2**
> Este es el módulo más importante del libro. Si solo pudieras estudiar uno, sería este.

## 🎯 Objetivos

- Separar hechos de dimensiones y reconocer cada uno en datos nuevos.
- **Definir el grano de una tabla de hechos** y explicar por qué es la decisión número uno.
- Aplicar los cuatro pasos de Kimball a cualquier proceso de negocio.
- Clasificar medidas en aditivas, semi-aditivas y no aditivas.
- Justificar las claves surrogate frente a las claves de negocio.
- Distinguir estrella de copo de nieve y elegir con criterio.
- Reconocer los tres tipos de tabla de hechos.
- Diseñar una dimensión fecha y explicar por qué se construye a mano.
- Manejar relaciones muchos a muchos sin inflar las medidas.
- Explicar y elegir entre SCD tipo 0, 1, 2 y 3.
- Usar miembros desconocidos para no perder hechos huérfanos.

---

## 📖 Teoría

### 7.1 Hechos y dimensiones

Mirá los datos que necesita la consulta del módulo anterior. Se parten en **dos naturalezas**:

**Cosas que se miden** — cantidad, precio unitario, importe. Son numéricas, **se acumulan** (sumar enero y febrero da el bimestre), y hay muchísimas: una por cada línea de cada pedido.

**Cosas que describen el contexto** — qué producto, qué cliente, qué fecha, qué vendedor. Son mayormente textuales, **no se suman** (sumar dos códigos de producto no significa nada), y son relativamente pocas: 227 productos, 663 clientes.

> **💡 Concepto clave.** Lo primero se llama **hechos** (*facts*), lo segundo **dimensiones** (*dimensions*). El modelo resultante —una tabla de hechos al centro, rodeada de dimensiones **a un solo join de distancia**— se llama **esquema estrella** (*star schema*).

```
                 ┌──────────────┐
                 │   DimDate    │
                 └──────┬───────┘
                        │
┌──────────────┐  ┌─────┴────────┐  ┌──────────────────┐
│ DimCustomer  ├──┤  FactSales   ├──┤   DimProduct     │
└──────────────┘  └─────┬────────┘  └──────────────────┘
                        │
                 ┌──────┴────────┐
                 │DimSalesperson │
                 └───────────────┘
```

Los ocho joins encadenados se convierten en **cuatro joins directos** desde el centro. Y el analista no necesita saber por dónde pasa nada: todo cuelga del hecho.

**La misma consulta, contra el modelo dimensional:**

```sql
SELECT d.Anio, d.MesNombre, p.CategoriaPrincipal, c.Pais,
       SUM(f.SalesAmount) AS Ventas
FROM dw.FactSales f
JOIN dw.DimDate     d ON d.DateKey     = f.DateKey
JOIN dw.DimProduct  p ON p.ProductKey  = f.ProductKey
JOIN dw.DimCustomer c ON c.CustomerKey = f.CustomerKey
GROUP BY d.Anio, d.MesNombre, p.CategoriaPrincipal, c.Pais;
```

**Tres joins, todos directos, y se lee como la pregunta de negocio.**

---

### 7.2 Cómo reconocer cada uno

| Señal | Hecho | Dimensión |
|---|---|---|
| Responde a | "¿Cuánto?" | "¿Quién? ¿Qué? ¿Cuándo? ¿Dónde?" |
| Tipo de dato | Numérico | Texto, fecha, código |
| ¿Se suma? | Sí | No |
| Volumen | Millones | Cientos o miles |
| Crecimiento | Constante | Lento |
| Cambios | Nunca (es un evento) | Ocasionales |
| En el diagrama de FKs | Muchas FKs salientes | Muchas FKs entrantes |

**La prueba de una línea:** *si sumarlo da un número con sentido de negocio, es una medida. Si no, es un atributo de dimensión.*

`SUM(Quantity)` = unidades vendidas ✅ medida
`SUM(CustomerID)` = un número sin significado ❌ atributo

> **⚠️ El caso que confunde a todo el mundo: los números que no son medidas.**
>
> `CustomerID`, `OrderID`, `StockItemID`, códigos postales, años. Son numéricos y **no son medidas**: son identificadores o atributos. La prueba de la suma los descarta a todos.
>
> Y el inverso: `UnitPrice` es numérico, se puede sumar... pero **sumar precios unitarios no significa nada**. Es una medida **no aditiva** (7.5). El precio se promedia o se usa para calcular, no se suma.

---

### 7.3 Granularidad — la decisión número uno

> **💡 Concepto clave — grano (*grain*).** El grano de una tabla de hechos es **qué representa exactamente una fila**.

Kimball insiste en que esta es la primera decisión, antes que las columnas y antes que las dimensiones, porque **todo lo demás se deriva de ella** y equivocarla obliga a rehacer el modelo.

**Para nuestro caso, tres opciones:**

| Opción | Grano | Filas | Qué se puede responder |
|---|---|---|---|
| **A** | Una fila por **línea de pedido** | 231.412 | Todo |
| **B** | Una fila por **pedido** | 73.595 | Nada por producto |
| **C** | Una fila por producto/cliente/día | ~menos | Nada individual |

**La regla, y conviene grabarla:**

> **Cada nivel de agregación que elegís es una pregunta que ya no vas a poder responder.**

Con el grano B (una fila por pedido), tenés que sumar los importes de las líneas para obtener el total. Perdés qué productos tenía el pedido. **"¿Cuál fue el producto más vendido?" pasa a ser incontestable**, y esa es una de las cinco preguntas de negocio del proyecto.

**La respuesta correcta es A: una fila por línea de pedido.**

**Los tres argumentos:**

1. **Es el máximo detalle disponible.** Siempre se puede agregar hacia arriba; nunca se puede desagregar hacia abajo.
2. **Preserva todas las preguntas.** Incluidas las que nadie hizo todavía — y en BI, las preguntas futuras son la mayoría.
3. **El costo es asumible.** 231.412 filas es nada. El argumento del volumen solo aparece con cientos de millones.

> **✅ La regla de oro de Kimball, textual:** *"Declarar el grano al nivel de detalle más atómico posible."*
>
> Y el corolario práctico: **si dudás, elegí el grano más fino.** El costo de equivocarse hacia el detalle es espacio en disco; el costo de equivocarse hacia el agregado es rehacer el modelo cuando aparezca la primera pregunta que no podés responder.

**Cómo se declara el grano.** En una frase, en el README, antes de escribir una sola columna:

> **Grano de `FactSales`:** una fila por cada línea de pedido de venta.

Si esa frase necesita un "y a veces también..." o un "excepto cuando...", **el grano está mal definido** y el modelo va a tener problemas.

> **⚠️ El error de mezclar granos.** Poner en la misma tabla filas por línea de pedido **y** filas de resumen por pedido (por ejemplo, el costo de envío que solo existe a nivel cabecera) hace que cualquier `SUM` sea incorrecto: suma detalle y resumen juntos.
>
> **La solución:** dos tablas de hechos con granos distintos. El envío va en `FactOrderHeader` con grano "una fila por pedido". Es el patrón correcto y se llama tener **hechos de distinto grano**, no un defecto de diseño.

---

### 7.4 Los cuatro pasos de Kimball

El método completo, aplicable a cualquier proceso de negocio:

**Paso 1 — Elegir el proceso de negocio.**
No "hacer un dashboard", sino un proceso concreto con eventos medibles. Acá: **la venta**. Otros serían: la compra, el movimiento de inventario, la facturación.

**Paso 2 — Declarar el grano.**
Una frase. *"Una fila por línea de pedido de venta."*

**Paso 3 — Identificar las dimensiones.**
Preguntá: **¿qué contexto describe este evento?** Cada respuesta es una dimensión.

Para una línea de pedido: **cuándo** (DimDate), **a quién** (DimCustomer), **qué** (DimProduct), **quién vendió** (DimSalesperson). Y podrían agregarse: cómo se entregó, tipo de empaque, promoción aplicada.

**Paso 4 — Identificar los hechos (medidas).**
Preguntá: **¿qué se mide en este evento?**

`Quantity`, `UnitPrice`, `TaxRate`, y la calculada `SalesAmount = Quantity × UnitPrice`.

> **✅ El orden es obligatorio.** Empezar por las dimensiones sin haber declarado el grano lleva a modelos donde no está claro qué es una fila. Y ese error no se nota hasta que los números no cuadran.

---

### 7.5 Medidas: aditivas, semi-aditivas y no aditivas

> ➕ **Tema adicional recomendado:** aditividad de medidas
> **Por qué necesito aprenderlo:** determina qué agregaciones son válidas, y sumar una medida no aditiva es una de las formas más comunes de producir números incorrectos.
> **En qué parte del proyecto lo utilizaremos:** al elegir las columnas de `FactSales` y al escribir las medidas DAX del Módulo 14.

| Tipo | Se puede sumar | Ejemplos |
|---|---|---|
| **Aditiva** | Por **todas** las dimensiones | `SalesAmount`, `Quantity` |
| **Semi-aditiva** | Por algunas, **no por tiempo** | Saldo de cuenta, stock, headcount |
| **No aditiva** | Por ninguna | `UnitPrice`, `TaxRate`, porcentajes, ratios |

**Semi-aditiva — el caso clásico y por qué importa:**

Si tenés stock de 100 unidades el lunes y 100 el martes, **no tenés 200**. El stock es un *nivel*, no un *flujo*. Se puede sumar por producto y por depósito, pero por tiempo hay que tomar el **último valor** o el promedio.

En DAX esto se resuelve con `LASTNONBLANK` o `CLOSINGBALANCEMONTH`, y es un tema que aparece en entrevistas de Power BI.

**No aditiva — el error más frecuente del oficio:**

```sql
-- ❌ MAL: sumar precios unitarios
SELECT SUM(UnitPrice) FROM dw.FactSales;   -- número sin ningún significado

-- ❌ MAL: promediar porcentajes
SELECT AVG(MargenPorcentaje) FROM dw.FactSales;  -- no pondera por volumen

-- ✅ BIEN: recalcular el ratio desde sus componentes aditivos
SELECT SUM(Margen) / NULLIF(SUM(Ventas), 0) AS MargenPorcentaje FROM dw.FactSales;
```

> **✅ La regla que evita el 90% de los errores de métricas:** *guardá en la tabla de hechos los **componentes aditivos**, y calculá los ratios en el momento de consultar.* Nunca guardes el porcentaje ya calculado por fila, porque promediar porcentajes de filas con volúmenes distintos da un resultado incorrecto.
>
> Ejemplo concreto: dos ventas, una con 50% de margen sobre $10 y otra con 10% sobre $1.000. El promedio de los porcentajes da 30%. El margen real es $105 sobre $1.010 = **10,4%**. La diferencia no es sutil.

---

### 7.6 Claves surrogate

> **💡 Concepto clave — clave surrogate (*surrogate key*).** Una clave artificial, sin significado de negocio, generada por el warehouse — típicamente un `INT IDENTITY`. Se distingue de la **clave de negocio** (*business key* o *natural key*), que es la del sistema origen: `CustomerID`, `StockItemID`.

```sql
CREATE TABLE dw.DimCustomer (
    CustomerKey  INT IDENTITY(1,1) PRIMARY KEY,  -- surrogate: la del warehouse
    CustomerID   INT NOT NULL,                   -- clave de negocio: la del origen
    CustomerName NVARCHAR(100) NOT NULL,
    ...
);
```

**Las cinco razones, en orden de importancia:**

**1 — Habilitan SCD Tipo 2, y esta sola razón alcanza.** Para guardar historia necesitás **varias filas por el mismo cliente**: una por cada versión. La clave de negocio ya no puede ser la PK porque se repite. La surrogate distingue las versiones.

```
CustomerKey  CustomerID  CustomerName  Categoria      ValidoDesde  ValidoHasta
    1            42       Tailspin      Novelty Shop   2020-01-01   2024-06-15
    2            42       Tailspin      Wholesaler     2024-06-15   9999-12-31
```

Un hecho de 2023 apunta a `CustomerKey = 1` y sigue diciendo "Novelty Shop" para siempre. **Ese es el problema del Módulo 0 resuelto.**

**2 — Aíslan del origen.** Si el sistema origen migra y cambia sus identificadores, se remapea en la dimensión y **la fact table no se toca**.

**3 — Manejan claves compuestas.** Si el origen tiene PK de tres columnas, la fact table necesitaría las tres. Con surrogate, una.

**4 — Permiten integrar múltiples orígenes.** El mismo cliente con `ID 4471` en el CRM y `ABC-88` en el ERP se unifica en una `CustomerKey`.

**5 — Rendimiento.** Un `INT` de 4 bytes es más rápido de unir que un `NVARCHAR(20)`, y hace la fact table más chica — que en una tabla de mil millones de filas es una diferencia real.

> **⚠️ La regla absoluta:** *la tabla de hechos referencia SIEMPRE claves surrogate, nunca claves de negocio.* Si ves una fact table con `CustomerID` en lugar de `CustomerKey`, el modelo no puede manejar historia. Es la señal más rápida para detectar un modelo dimensional mal hecho.

---

### 7.7 Esquema estrella vs copo de nieve

**Estrella** — dimensiones **desnormalizadas**, cada una en una sola tabla.

```
DimCustomer: CustomerKey, CustomerID, CustomerName, Categoria,
             Ciudad, Provincia, Pais          ← todo aplanado
```

**Copo de nieve (*snowflake*)** — dimensiones **normalizadas** en varias tablas.

```
DimCustomer → DimCity → DimStateProvince → DimCountry
```

| | Estrella | Copo de nieve |
|---|---|---|
| Joins por consulta | 1 por dimensión | Varios por dimensión |
| Comprensible para el negocio | ✅ Mucho | ❌ Poco |
| Espacio | Más | Menos |
| Rendimiento | Mejor | Peor |
| Power BI | ✅ Óptimo | ⚠️ Subóptimo |

**Usá estrella.** Casi siempre.

**Las tres excepciones legítimas** para normalizar una dimensión:

1. **Dimensión enorme con atributos muy repetidos** — una dimensión de 100 millones de filas donde el 90% del espacio son textos repetidos.
2. **Un atributo cambia muchísimo más rápido que el resto** — separarlo evita reescribir la dimensión completa. Se llama **mini-dimensión** o *outrigger*.
3. **Jerarquía compartida por muchas dimensiones** — geografía usada por clientes, proveedores y sucursales, donde mantenerla en un solo lugar tiene valor real.

> **🎓 Nota práctica sobre Power BI:** el motor VertiPaq está optimizado para esquemas estrella. Un copo de nieve degrada el rendimiento y complica el modelo. **En Power BI, aplanar es casi siempre la respuesta correcta** — y esa es una recomendación explícita de Microsoft.

---

### 7.8 Tipos de tabla de hechos

> ➕ **Tema adicional recomendado:** los tres tipos de fact table
> **Por qué necesito aprenderlo:** elegir el tipo equivocado produce modelos que no pueden responder las preguntas que se les piden.
> **En qué parte del proyecto lo utilizaremos:** `FactSales` es de transacción; conocer los otros dos permite proponer extensiones con criterio.

**1 — Transaccional (*transaction fact table*).** Una fila por evento. **La nuestra.**

- Grano: el evento atómico.
- Se inserta, nunca se actualiza.
- Aditiva en todas las dimensiones.
- **Es la más común y la más flexible.**

**2 — Snapshot periódico (*periodic snapshot*).** Una fila por entidad, por período.

- Ejemplo: saldo de cada cuenta al cierre de cada mes; stock de cada producto al final de cada día.
- Medidas típicamente **semi-aditivas**.
- Responde "¿cuánto había?" en vez de "¿qué pasó?".

**3 — Snapshot acumulativo (*accumulating snapshot*).** Una fila por instancia de un proceso con etapas, **que se actualiza** a medida que avanza.

- Ejemplo: una fila por pedido, con `FechaPedido`, `FechaPreparado`, `FechaEnviado`, `FechaEntregado`, y las duraciones entre etapas.
- **Es la única que se actualiza.**
- Ideal para analizar **cuellos de botella** en procesos.

> **💡 Aplicación directa a WideWorldImporters.** `Sales.Orders` tiene `OrderDate`, `PickingCompletedWhen` y `ExpectedDeliveryDate`. Eso es exactamente un candidato a **snapshot acumulativo**: permitiría responder "¿cuánto tardamos en preparar los pedidos?" y "¿qué porcentaje se entrega en fecha?".
>
> Proponer esto como extensión del proyecto muestra que entendés el catálogo de patrones, no solo el que usaste.

---

### 7.9 La dimensión fecha

**Por qué se construye a mano** y no se usa la fecha directamente:

**1 — Atributos que la fecha no tiene.** Trimestre fiscal, si es feriado, si es día hábil, semana del año, nombre del mes **en español**. Nada de eso sale de un `DATE`.

**2 — Consistencia.** Si cada consulta calcula `MONTH(OrderDate)`, cada analista puede usar convenciones distintas — sobre todo con semanas y trimestres fiscales. Una dimensión fecha impone **una** definición.

**3 — Rendimiento.** `WHERE d.Anio = 2025` usa un índice; `WHERE YEAR(OrderDate) = 2025` aplica una función a la columna y **anula el índice**. A eso se le llama hacer la consulta **no sargable** (*non-SARGable*), y es una de las causas más comunes de consultas lentas.

**4 — Fechas sin actividad.** Si el 25 de diciembre no hubo ventas, un `GROUP BY OrderDate` **omite el día**. El gráfico salta de 24 a 26 y parece que el tiempo se comprimió. Con `DimDate` y un `LEFT JOIN`, el día aparece con cero.

**5 — Time Intelligence en Power BI lo exige.** Las funciones `SAMEPERIODLASTYEAR`, `DATESYTD` y compañía **requieren** una tabla de fechas marcada como tal, con fechas contiguas sin huecos.

**Estructura típica:**

```sql
CREATE TABLE dw.DimDate (
    DateKey        INT         NOT NULL PRIMARY KEY,   -- 20260810
    FechaCompleta  DATE        NOT NULL,
    Anio           SMALLINT    NOT NULL,
    Trimestre      TINYINT     NOT NULL,
    TrimestreNombre NVARCHAR(10) NOT NULL,             -- 'Q3'
    Mes            TINYINT     NOT NULL,
    MesNombre      NVARCHAR(20) NOT NULL,              -- 'Agosto'
    MesAnioNombre  NVARCHAR(20) NOT NULL,              -- 'Ago 2026'
    Dia            TINYINT     NOT NULL,
    DiaSemana      TINYINT     NOT NULL,
    DiaSemanaNombre NVARCHAR(20) NOT NULL,             -- 'Lunes'
    SemanaAnio     TINYINT     NOT NULL,
    EsFinDeSemana  BIT         NOT NULL,
    EsFeriado      BIT         NOT NULL DEFAULT 0,
    EsDiaHabil     BIT         NOT NULL,
    -- Orden numérico para que Power BI no ordene los meses alfabéticamente
    MesAnioOrden   INT         NOT NULL                -- 202608
);
```

> **💡 `DateKey` como entero `AAAAMMDD` en vez de `DATE`.** Es la convención de Kimball. Motivos: ocupa 4 bytes (igual que `DATE`, pero se une más rápido que comparar fechas), es legible a simple vista (`20260810` se entiende), y **permite reservar valores especiales**: `-1` para "fecha desconocida", `19000101` para "sin fecha". Con un `DATE` no hay forma limpia de expresar "no sabemos".

> **⚠️ `MesAnioOrden` no es opcional.** Sin una columna numérica de ordenamiento, Power BI ordena `MesNombre` **alfabéticamente**: Abril, Agosto, Diciembre, Enero... En Power BI esto se resuelve con "Ordenar por columna", y sin la columna auxiliar no hay por qué ordenar. Es de los primeros problemas que vas a encontrar en el Módulo 13.

---

### 7.10 Dimensiones degeneradas

> ➕ **Tema adicional recomendado:** dimensión degenerada
> **Por qué necesito aprenderlo:** aparece en casi todo modelo de ventas y confunde si no se conoce el término.
> **En qué parte del proyecto lo utilizaremos:** el número de pedido en `FactSales`.

> **💡 Concepto clave — dimensión degenerada (*degenerate dimension*).** Un identificador del sistema origen que se guarda **en la tabla de hechos**, sin tabla de dimensión propia, porque no tiene atributos que describir.

`OrderID` es el ejemplo perfecto. Es un identificador con valor analítico —permite agrupar líneas del mismo pedido y contar pedidos distintos— pero una `DimOrder` solo tendría `OrderKey` y `OrderID`. **Una dimensión sin atributos no aporta nada.**

```sql
CREATE TABLE dw.FactSales (
    ...
    OrderID     INT NOT NULL,   -- dimensión degenerada
    OrderLineID INT NOT NULL,   -- dimensión degenerada
    ...
);
```

**Para qué sirve concretamente:**

```sql
-- Cantidad de pedidos (no de líneas)
SELECT COUNT(DISTINCT OrderID) FROM dw.FactSales;

-- Ticket promedio
SELECT SUM(SalesAmount) / COUNT(DISTINCT OrderID) FROM dw.FactSales;

-- Trazabilidad: encontrar el pedido original en el OLTP
SELECT * FROM dw.FactSales WHERE OrderID = 12345;
```

Ese último uso es importante y se subestima: **es cómo se investiga cuando alguien dice "este número está mal"**.

---

### 7.11 Muchos a muchos: la tabla puente

> ➕ **Tema adicional recomendado:** manejo de relaciones muchos a muchos
> **Por qué necesito aprenderlo:** es la trampa que infla las ventas silenciosamente, y aparece en tu proyecto de forma concreta.
> **En qué parte del proyecto lo utilizaremos:** en `DimProduct`, con las 442 asignaciones producto-categoría.

**El problema recordado:** 227 productos, 442 asignaciones a grupos. Un join ingenuo duplica las medidas.

**Las tres soluciones:**

**Opción 1 — Categoría primaria (la que usa este proyecto).**

Elegir **una** categoría por producto según una regla determinística, y guardarla como atributo de `DimProduct`.

```sql
-- Regla: el grupo de menor ID es el primario
SELECT si.StockItemID,
       (SELECT TOP 1 sg.StockGroupName
        FROM Warehouse.StockItemStockGroups sisg
        JOIN Warehouse.StockGroups sg ON sg.StockGroupID = sisg.StockGroupID
        WHERE sisg.StockItemID = si.StockItemID
        ORDER BY sg.StockGroupID) AS CategoriaPrincipal
FROM Warehouse.StockItems si;
```

✅ Simple · Sin fan-out posible · Los totales siempre cuadran
❌ Se pierde información: un producto en 3 categorías solo cuenta en una

**⚠️ Y la regla tiene que ser una decisión de negocio, no "el de menor ID".** "El de menor ID" es arbitrario y produce categorizaciones que no significan nada. Lo correcto es preguntar: *"si tuvieras que poner este producto en un solo lugar del catálogo, ¿cuál sería?"*. Si el negocio no puede responder, esa es información valiosa: significa que la categoría no es un concepto bien definido.

**Opción 2 — Tabla puente con factor de asignación.**

```sql
CREATE TABLE dw.BridgeProductGroup (
    ProductKey       INT NOT NULL,
    GroupKey         INT NOT NULL,
    FactorAsignacion DECIMAL(5,4) NOT NULL,   -- suma 1.0 por producto
    PRIMARY KEY (ProductKey, GroupKey)
);

-- Consulta que NO infla:
SELECT g.GroupName, SUM(f.SalesAmount * b.FactorAsignacion) AS Ventas
FROM dw.FactSales f
JOIN dw.BridgeProductGroup b ON b.ProductKey = f.ProductKey
JOIN dw.DimProductGroup g    ON g.GroupKey   = b.GroupKey
GROUP BY g.GroupName;
```

Un producto en 2 grupos tiene factor 0,5 en cada uno. Las ventas se **reparten** en vez de duplicarse, y **el total sigue cuadrando**.

✅ No pierde información · El total es correcto
❌ Más complejo · **El total por categoría deja de ser intuitivo** (un producto aporta "medias ventas" a cada una) · Requiere definir los factores, que es una decisión de negocio difícil

**Opción 3 — Cambiar el grano.** Aceptar la duplicación y declarar el grano como "una fila por línea de pedido **por categoría**". Honesto pero peligroso: cualquiera que sume sin filtrar por categoría obtiene el número inflado.

> **✅ Recomendación para este proyecto: opción 1.** Es la más simple, los totales siempre cuadran, y la pérdida de información es aceptable para el objetivo. **Documentá la regla de selección en el README**, porque es una decisión de negocio que alguien va a cuestionar.

---

### 7.12 Slowly Changing Dimensions

> ➕ **Tema adicional recomendado:** SCD
> **Por qué necesito aprenderlo:** es **el** tema de modelado dimensional en entrevistas, y resuelve el problema de la historia que motivó todo el warehouse.
> **En qué parte del proyecto lo utilizaremos:** en `DimCustomer` y `DimProduct` (Módulo 8).

**El problema:** un cliente pasa de "Novelty Shop" a "Wholesaler". ¿Qué le pasa a las ventas históricas?

**Tipo 0 — Retener el original.** El atributo nunca cambia. Para cosas como fecha de alta o cohorte de origen.

**Tipo 1 — Sobrescribir.**

```sql
UPDATE dw.DimCustomer
SET Categoria = 'Wholesaler'
WHERE CustomerID = 42;
```

✅ Simple · Una fila por entidad
❌ **Se pierde la historia.** Todas las ventas pasadas se reatribuyen. Los reportes del año pasado cambian solos.

**Cuándo usarlo:** correcciones de errores (un nombre mal escrito), o atributos donde la historia no importa.

**Tipo 2 — Nueva fila por versión. El más importante.**

```sql
CREATE TABLE dw.DimCustomer (
    CustomerKey  INT IDENTITY(1,1) PRIMARY KEY,  -- surrogate
    CustomerID   INT NOT NULL,                   -- clave de negocio
    CustomerName NVARCHAR(100) NOT NULL,
    Categoria    NVARCHAR(50)  NOT NULL,
    ValidoDesde  DATE NOT NULL,
    ValidoHasta  DATE NOT NULL DEFAULT '9999-12-31',
    EsActual     BIT  NOT NULL DEFAULT 1
);
```

```
CustomerKey  CustomerID  Categoria      ValidoDesde  ValidoHasta  EsActual
    1            42       Novelty Shop   2020-01-01   2024-06-15      0
    2            42       Wholesaler     2024-06-15   9999-12-31      1
```

**Cómo funciona:** el hecho apunta a la `CustomerKey` **vigente al momento del evento**. Una venta de 2023 apunta a `CustomerKey = 1` y **para siempre** va a decir "Novelty Shop".

✅ **Historia completa y precisa.** Los reportes históricos no cambian.
❌ La dimensión crece · La carga es más compleja · Hay que resolver la clave vigente al momento del hecho

**Los tres detalles de implementación que hay que conocer:**

- **`ValidoHasta = '9999-12-31'` en lugar de `NULL`.** Permite escribir `WHERE @Fecha BETWEEN ValidoDesde AND ValidoHasta` sin casos especiales. Con `NULL` haría falta `OR ValidoHasta IS NULL` en cada consulta.
- **`EsActual`** es redundante con las fechas, y se agrega igual porque `WHERE EsActual = 1` es mucho más simple y rápido que comparar rangos. Redundancia deliberada, coherente con 6.7.
- **La búsqueda de clave** en la carga de hechos debe usar la fecha del evento, no la fecha actual. Es el error más común al implementar Tipo 2 (Módulo 8).

**Tipo 3 — Columna adicional con el valor anterior.**

```
CustomerID  CategoriaActual  CategoriaAnterior  FechaCambio
   42        Wholesaler       Novelty Shop       2024-06-15
```

✅ Permite comparar "como es ahora" vs "como era antes"
❌ **Solo guarda un cambio.** El segundo pisa al primero. Poco usado.

**Cómo elegir — la pregunta clave:**

> **¿Los reportes históricos deben mostrar cómo era entonces, o cómo es ahora?**

- "Como era entonces" → **Tipo 2**
- "Como es ahora" → **Tipo 1**
- "Quiero las dos" → Tipo 2 + una columna con el valor actual (a veces llamado **Tipo 6** o *híbrido*)

> **💡 Y el atajo que casi nadie usa:** WideWorldImporters tiene **tablas temporales de sistema** (Módulo 1). El origen **ya guarda el historial** de `Sales.Customers`. Podés leerlo con `FOR SYSTEM_TIME ALL` y mapearlo directamente a las filas de la dimensión, en vez de detectar cambios comparando snapshots.
>
> **Esa respuesta en una entrevista es de nivel senior**, porque muestra que buscás dónde ya está resuelto el problema en lugar de reimplementarlo.

---

### 7.13 Miembros desconocidos

> ➕ **Tema adicional recomendado:** *unknown member*
> **Por qué necesito aprenderlo:** es la solución estándar a los hechos huérfanos, y evita la pérdida silenciosa de ventas.
> **En qué parte del proyecto lo utilizaremos:** en toda dimensión referenciada por `FactSales`.

**El problema (Módulo 4):** un `INNER JOIN` entre la fact table y una dimensión **descarta silenciosamente** los hechos cuyo cliente no está.

**La solución de Kimball:** una fila especial en cada dimensión.

```sql
SET IDENTITY_INSERT dw.DimCustomer ON;
INSERT INTO dw.DimCustomer (CustomerKey, CustomerID, CustomerName, Categoria, Pais)
VALUES (-1, -1, N'Desconocido', N'Desconocido', N'Desconocido');
SET IDENTITY_INSERT dw.DimCustomer OFF;
```

**Y la carga usa `LEFT JOIN` con sustitución:**

```sql
INSERT INTO dw.FactSales (CustomerKey, ProductKey, ...)
SELECT
    ISNULL(dc.CustomerKey, -1),    -- ← si no encuentra, va a Desconocido
    ISNULL(dp.ProductKey, -1),
    ...
FROM stg.OrderLines ol
JOIN stg.Orders o        ON o.OrderID    = ol.OrderID
LEFT JOIN dw.DimCustomer dc ON dc.CustomerID  = o.CustomerID AND dc.EsActual = 1
LEFT JOIN dw.DimProduct  dp ON dp.StockItemID = ol.StockItemID;
```

**Las tres ventajas, y son grandes:**

1. **No se pierde ninguna venta.** Los totales siempre cuadran contra el origen.
2. **El problema queda visible.** Aparece "Desconocido" en el dashboard con su monto, y alguien pregunta. **Un problema visible se arregla; uno silencioso no.**
3. **La fact table puede tener FKs `NOT NULL`** hacia todas las dimensiones, lo que permite declarar las relaciones y ayuda al optimizador.

> **✅ Regla:** *nunca uses `INNER JOIN` en la carga de una fact table.* Siempre `LEFT JOIN` con miembro desconocido. Es una regla dura y vale la pena tratarla como tal.

---

## 🔧 El modelo del proyecto

```
                    ┌─────────────────────┐
                    │      DimDate        │
                    │ DateKey (PK)        │
                    │ Anio, Trimestre     │
                    │ Mes, MesNombre      │
                    │ DiaSemanaNombre     │
                    │ EsDiaHabil          │
                    └──────────┬──────────┘
                               │
┌──────────────────┐   ┌───────┴──────────┐   ┌──────────────────┐
│   DimCustomer    │   │    FactSales     │   │   DimProduct     │
│ CustomerKey (PK) ├───┤ SalesKey (PK)    ├───┤ ProductKey (PK)  │
│ CustomerID       │   │ DateKey (FK)     │   │ StockItemID      │
│ CustomerName     │   │ CustomerKey (FK) │   │ ProductName      │
│ Categoria        │   │ ProductKey (FK)  │   │ CategoriaPrincipal│
│ GrupoCompra      │   │ SalespersonKey   │   │ Color, Marca     │
│ Ciudad           │   │ OrderID    (DD)  │   │ TamañoPaquete    │
│ Provincia        │   │ OrderLineID(DD)  │   │ PrecioLista      │
│ Pais             │   │ Quantity         │   │ CostoUnitario    │
│ ValidoDesde      │   │ UnitPrice        │   └──────────────────┘
│ ValidoHasta      │   │ TaxRate          │
│ EsActual         │   │ SalesAmount      │   DD = dimensión degenerada
└──────────────────┘   │ TaxAmount        │
                       │ TotalAmount      │
                       └───────┬──────────┘
                               │
                    ┌──────────┴──────────┐
                    │  DimSalesperson     │
                    │ SalespersonKey (PK) │
                    │ PersonID            │
                    │ NombreCompleto      │
                    │ EsVendedor          │
                    └─────────────────────┘
```

**Grano declarado:** una fila por línea de pedido de venta.

**Medidas:** `Quantity` (aditiva), `UnitPrice` (**no aditiva**), `TaxRate` (**no aditiva**), `SalesAmount` (aditiva), `TaxAmount` (aditiva), `TotalAmount` (aditiva).

**Decisiones documentadas:**
- Producto-categoría resuelto con **categoría primaria** (opción 1 de 7.11).
- `DimCustomer` con **SCD Tipo 2**; `DimProduct` con Tipo 1 (los atributos de producto rara vez requieren historia en este negocio).
- **Miembro desconocido `-1`** en todas las dimensiones.
- Geografía **aplanada** en `DimCustomer` (estrella, no copo de nieve).

---

## ⚠️ Errores comunes

**No declarar el grano antes de empezar.** El error raíz del que se derivan casi todos los demás.

**Elegir un grano agregado "para ahorrar espacio".** Se pierden preguntas para siempre y el ahorro casi nunca importa.

**Mezclar granos en la misma tabla.** Cualquier `SUM` queda mal.

**Usar la clave de negocio como PK de la dimensión.** Imposibilita SCD Tipo 2.

**Poner `CustomerID` en la fact table en lugar de `CustomerKey`.** Señal inequívoca de modelo mal hecho.

**Guardar porcentajes calculados en la fact table.** Promediar porcentajes ignora la ponderación.

**Sumar medidas no aditivas.** `SUM(UnitPrice)` no significa nada.

**`INNER JOIN` en la carga de hechos.** Pérdida silenciosa. Usá miembro desconocido.

**Usar la fecha en lugar de `DimDate`.** Sin trimestres fiscales, sin feriados, sin días sin actividad, y las consultas quedan no sargables.

**Olvidar la columna de ordenamiento de meses.** Power BI ordena alfabéticamente.

**Ignorar el fan-out de las tablas puente.** Las ventas se duplican sin error.

**SCD Tipo 2 con búsqueda de clave por fecha actual.** Todos los hechos apuntan a la versión vigente y la historia no sirve de nada — el modelo *parece* Tipo 2 y se comporta como Tipo 1.

---

## 🧠 Preguntas de comprensión

1. Elegís grano "una fila por pedido". Listá tres preguntas de negocio que dejás de poder responder.
2. ¿Por qué la fact table no puede usar `CustomerID` si querés SCD Tipo 2?
3. Dos ventas: 50% de margen sobre $10 y 10% sobre $1.000. Calculá el promedio de porcentajes y el margen real. Explicá la diferencia.
4. ¿Por qué `ValidoHasta = '9999-12-31'` y no `NULL`?
5. Un producto está en 3 categorías. Explicá qué pasa con las ventas totales en cada una de las tres soluciones de 7.11.
6. ¿Por qué `WHERE YEAR(OrderDate) = 2025` es más lento que `WHERE d.Anio = 2025`?
7. Tu `DimCustomer` es Tipo 2, pero la carga de hechos une con `dc.EsActual = 1`. ¿Qué comportamiento real tiene el modelo?

---

## 📝 Ejercicios

**🟢 Básico.** Declará en una frase el grano de `FactSales`. Después escribí tres preguntas que ese grano permite responder y una que no.

**🟢 Básico.** Clasificá cada una como aditiva, semi-aditiva o no aditiva: importe de venta, cantidad, precio unitario, stock disponible, tasa de impuesto, cantidad de clientes distintos, saldo de cuenta.

**🟡 Intermedio.** Diseñá `DimProduct` completa: qué atributos traés de qué tablas del origen, cómo resolvés la categoría, y qué tipo de SCD aplicás a cada atributo. Justificá.

**🟡 Intermedio.** Diseñá un modelo dimensional para el proceso de **compras** (`Purchasing`). Grano, dimensiones, medidas. Indicá qué dimensiones son **conformadas** con el modelo de ventas.

**🔴 Avanzado.** Implementá `DimCustomer` con SCD Tipo 2 usando las **tablas temporales** del origen: `FOR SYSTEM_TIME ALL` para obtener todas las versiones y generar las filas con sus rangos de validez.

**🔴 Avanzado.** Diseñá un **snapshot acumulativo** para el ciclo de vida del pedido: fechas de cada etapa, duraciones entre etapas, y las medidas que permitan responder "¿cuál es nuestro tiempo promedio de preparación?" y "¿qué porcentaje se entrega en fecha?". Explicá por qué esta tabla **se actualiza**, a diferencia de `FactSales`.

**🧠 Reto.** Un producto puede estar en varias categorías **y** las categorías cambian con el tiempo. Diseñá una solución que (a) no infle las ventas, (b) permita ver la categorización histórica correcta, y (c) sea consultable desde Power BI sin que el analista tenga que entender el mecanismo. Discutí los compromisos honestamente — no hay una solución sin costo.

---

## 🎓 Preguntas de entrevista

1. **¿Qué es el grano de una tabla de hechos y por qué es la decisión más importante?** — Ver 7.3. Es *la* pregunta de modelado dimensional.
2. **¿Qué es una clave surrogate y por qué usarla?** — Las cinco razones, empezando por SCD Tipo 2.
3. **Explicá SCD y sus tipos.** — 0, 1, 2, 3. Y la pregunta que decide: ¿como era entonces o como es ahora?
4. **¿Estrella o copo de nieve?** — Estrella casi siempre; las tres excepciones; y que Power BI está optimizado para estrella.
5. **¿Qué es una medida semi-aditiva?** — Stock, saldo. No se suma por tiempo.
6. **¿Por qué una dimensión fecha en vez de la columna de fecha?** — Las cinco razones de 7.9.
7. **¿Cómo manejás relaciones muchos a muchos?** — Las tres opciones, con sus compromisos.
8. **¿Qué es una dimensión degenerada?** — Identificador en la fact table sin dimensión propia.
9. **¿Qué pasa con los hechos cuya dimensión no existe?** — Miembro desconocido. Nunca `INNER JOIN`.
10. **¿Cómo evitás que los reportes históricos cambien cuando un cliente cambia de categoría?** — SCD Tipo 2, y explicar la búsqueda de clave por fecha del evento.

---

## 📌 Resumen

- **Hechos** = lo que se mide (numérico, aditivo, muchas filas). **Dimensiones** = el contexto (textual, no aditivo, pocas filas).
- **Esquema estrella**: hechos al centro, dimensiones a un join.
- **El grano es la decisión número uno.** Se declara en una frase antes de escribir nada. **Ante la duda, el más fino.**
- Cada agregación es una pregunta que perdés para siempre.
- **Cuatro pasos de Kimball:** proceso → grano → dimensiones → medidas. En ese orden.
- Medidas **aditivas**, **semi-aditivas** (no por tiempo) y **no aditivas** (ratios). Guardá componentes, calculá ratios al consultar.
- **Claves surrogate siempre.** Habilitan SCD Tipo 2, aíslan del origen, unifican orígenes.
- **Estrella sobre copo de nieve**, salvo tres excepciones concretas.
- **Tres tipos de fact table:** transacción, snapshot periódico, snapshot acumulativo.
- **`DimDate` se construye a mano**, con `DateKey` entero y columna de ordenamiento.
- **Dimensión degenerada:** `OrderID` en la fact table, sin dimensión propia.
- **Muchos a muchos:** categoría primaria (simple), puente con factor (preciso), o cambiar el grano.
- **SCD Tipo 2** para preservar historia. `ValidoHasta = '9999-12-31'`, no NULL.
- **Miembro desconocido `-1` y `LEFT JOIN`.** Nunca `INNER JOIN` en la carga de hechos.

---

## 🗂️ Flashcards

| Pregunta | Respuesta |
|---|---|
| ¿Qué es el grano? | Qué representa exactamente una fila de la tabla de hechos. |
| ¿Cuándo se declara? | Antes que las dimensiones y antes que las medidas. |
| ¿Regla ante la duda? | Elegir el grano más fino: siempre se puede agregar, nunca desagregar. |
| ¿Cuatro pasos de Kimball? | Proceso de negocio → grano → dimensiones → medidas. |
| ¿Prueba para distinguir medida de atributo? | Si sumarlo da un número con sentido, es medida. |
| ¿Qué es una medida semi-aditiva? | Se suma por algunas dimensiones pero **no por tiempo**. Stock, saldo. |
| ¿Se puede sumar `UnitPrice`? | No: es no aditiva. |
| ¿Por qué no guardar porcentajes por fila? | Promediar porcentajes ignora la ponderación por volumen. |
| ¿Qué es una clave surrogate? | Clave artificial sin significado de negocio, generada por el warehouse. |
| ¿Razón principal para usarla? | Habilita SCD Tipo 2: varias filas por la misma entidad. |
| ¿Qué referencia la fact table? | Siempre claves surrogate, nunca claves de negocio. |
| ¿Estrella vs copo de nieve? | Estrella: dimensiones aplanadas, un join. Copo: normalizadas, varios. |
| ¿Cuál prefiere Power BI? | Estrella: VertiPaq está optimizado para ella. |
| ¿Tres tipos de fact table? | Transacción, snapshot periódico, snapshot acumulativo. |
| ¿Cuál se actualiza? | El snapshot acumulativo. |
| ¿Por qué `DateKey` entero AAAAMMDD? | Legible, rápido de unir, y admite valores especiales como `-1`. |
| ¿Por qué una `DimDate` y no la fecha? | Atributos extra, consistencia, sargabilidad, días sin actividad, Time Intelligence. |
| ¿Qué es una dimensión degenerada? | Identificador guardado en la fact table sin dimensión propia. |
| ¿SCD Tipo 1? | Sobrescribe. Se pierde la historia. |
| ¿SCD Tipo 2? | Nueva fila por versión con rango de validez. Preserva historia. |
| ¿Por qué `ValidoHasta = '9999-12-31'`? | Permite `BETWEEN` sin tratar NULL como caso especial. |
| ¿Qué es un miembro desconocido? | Fila `-1` "Desconocido" que evita perder hechos huérfanos. |
| ¿Qué join usar al cargar hechos? | `LEFT JOIN` con `ISNULL(key, -1)`. Nunca `INNER`. |
| ¿Qué es fan-out? | Duplicación de medidas por relaciones muchos a muchos. |

---

## ☑️ Checklist antes de avanzar

- [ ] Declaré el grano de `FactSales` en una frase, sin excepciones.
- [ ] Puedo nombrar los cuatro pasos de Kimball en orden.
- [ ] Clasifiqué cada medida por aditividad.
- [ ] Todas las dimensiones tienen clave surrogate.
- [ ] La fact table referencia solo claves surrogate.
- [ ] Decidí qué tipo de SCD lleva cada dimensión, con justificación.
- [ ] Resolví el muchos a muchos de producto-categoría y documenté la regla.
- [ ] Diseñé `DimDate` con `DateKey` entero y columna de ordenamiento.
- [ ] Toda dimensión tiene miembro desconocido `-1`.
- [ ] No hay porcentajes calculados guardados en la fact table.

---

## 📋 Examen del Módulo 7

### Selección múltiple

**1.** La primera decisión al diseñar una tabla de hechos es:
a) Qué dimensiones incluir   b) **El grano**   c) Qué medidas guardar   d) Qué índices crear

**2.** ¿Cuál es semi-aditiva?
a) Importe de venta   b) Cantidad vendida   c) **Stock disponible**   d) Cantidad de líneas

**3.** ¿Por qué la fact table usa claves surrogate?
a) Ocupan menos espacio
b) Porque con SCD Tipo 2 hay varias filas por entidad y la clave de negocio se repite
c) Porque SQL Server lo exige
d) Para poder usar `IDENTITY`

**4.** Un producto en 3 categorías, unido sin precaución a la fact table:
a) Pierde ventas   b) **Triplica sus ventas**   c) Da error   d) No pasa nada

**5.** SCD Tipo 1:
a) Crea una nueva fila por versión
b) **Sobrescribe y pierde la historia**
c) Agrega una columna con el valor anterior
d) Nunca cambia

**6.** ¿Por qué `ValidoHasta = '9999-12-31'` y no NULL?
a) Ocupa menos   b) **Permite `BETWEEN` sin casos especiales**   c) Es más rápido   d) NULL no se admite en fechas

**7.** Una dimensión degenerada es:
a) Una dimensión con pocos atributos
b) **Un identificador guardado en la fact table sin dimensión propia**
c) Una dimensión que cambió de estructura
d) Una dimensión sin clave surrogate

**8.** Al cargar la fact table hay que usar:
a) `INNER JOIN`, para garantizar integridad
b) **`LEFT JOIN` con miembro desconocido**
c) `CROSS JOIN`
d) `FULL OUTER JOIN`

### Verdadero / Falso

**9.** Siempre se puede desagregar una tabla de hechos a un grano más fino.
**10.** `SUM(UnitPrice)` es una métrica válida de negocio.
**11.** El esquema copo de nieve rinde mejor que el estrella en Power BI.
**12.** El snapshot acumulativo se actualiza a medida que avanza el proceso.
**13.** Una dimensión fecha permite mostrar días sin actividad.
**14.** Guardar el porcentaje de margen por fila permite promediarlo después correctamente.
**15.** Con SCD Tipo 2, un reporte del año pasado da el mismo resultado hoy que hace un año.

### SQL

**16.** Escribí el DDL completo de `FactSales` con el grano declarado en un comentario, todas las FKs, las dimensiones degeneradas y las medidas correctamente tipadas.

**17.** Escribí la consulta de búsqueda de clave surrogate para SCD Tipo 2: dada una venta con su fecha, encontrar la `CustomerKey` **vigente en ese momento**, no la actual.

### Diseño

**18.** El negocio quiere analizar devoluciones. Diseñá: ¿es una nueva fact table o filas negativas en `FactSales`? Justificá con el concepto de grano y discutí ambas opciones.

**19.** Diseñá el modelo dimensional para una empresa de streaming: reproducciones de contenido por usuario. Grano, dimensiones, medidas. Identificá al menos una medida semi-aditiva y una relación muchos a muchos, y resolvé ambas.

### Debugging

**20.** Un modelo tiene `DimCustomer` con SCD Tipo 2 correctamente implementada. Pero los reportes históricos siguen cambiando cuando un cliente cambia de categoría. La búsqueda en la carga de hechos es:

```sql
LEFT JOIN dw.DimCustomer dc
    ON dc.CustomerID = o.CustomerID AND dc.EsActual = 1
```

Explicá el bug, por qué es tan difícil de detectar, y escribí la corrección.

