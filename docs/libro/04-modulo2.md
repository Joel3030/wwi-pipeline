---

# Módulo 2 — La capa Staging

> **Paso 2 del proyecto, parte 1 de 3**

## 🎯 Objetivos

Al terminar este módulo vas a poder:

- Explicar qué es staging y, sobre todo, **qué no es**.
- Nombrar los cinco problemas que resuelve y defender cada uno técnicamente.
- Diseñar tablas de staging aplicando el principio de alineación al origen.
- Justificar por qué en staging casi todo es NULL-able y los tipos se relajan.
- Diseñar columnas de auditoría útiles.
- Elegir entre base separada y schema separado con criterio.
- Explicar full load vs incremental load y elegir el correcto para un caso dado.
- Definir idempotencia y explicar por qué es la propiedad que habilita todo lo demás.

---

## 📖 Teoría

### 2.1 El problema que nadie te cuenta hasta que lo sufrís

Imaginá que salteás staging. Vas directo del OLTP a la fact table:

```sql
-- La tentación
INSERT INTO dw.FactSales (...)
SELECT ol.OrderLineID, o.OrderDate, c.CustomerName, ...
FROM WideWorldImporters.Sales.OrderLines ol
JOIN WideWorldImporters.Sales.Orders     o ON o.OrderID = ol.OrderID
JOIN WideWorldImporters.Sales.Customers  c ON c.CustomerID = o.CustomerID
-- ... cinco joins más
WHERE o.OrderDate >= '2025-01-01';
```

Funciona. La primera vez.

Ahora contá qué pasa después:

**Semana 1.** La consulta tarda 4 minutos y corre a las 2 AM. Bien.

**Mes 2.** Alguien reporta que un total no cuadra. Para investigar necesitás ver *qué había en el origen cuando corrió la carga*. **No lo tenés.** El origen ya cambió. No podés reproducir el problema.

**Mes 3.** Cambia una regla de negocio: hay que excluir los pedidos cancelados. Hay que reprocesar dos años. Volvés a golpear producción con una consulta pesada, esta vez en horario laboral porque el pedido es urgente.

**Mes 4.** El equipo del OLTP renombra una columna. Tu carga se rompe. Y como la transformación y la extracción están en la misma consulta, hay que rehacer la lógica de negocio para arreglar un problema de nombres.

**Mes 6.** Una carga falla a mitad de camino. ¿Qué filas alcanzó a procesar? ¿Se puede reintentar? Nadie sabe. Se recarga todo "por las dudas" y aparecen duplicados.

**Los cinco problemas son los cinco motivos por los que existe staging.** Y fijate que ninguno aparece el primer día: todos aparecen cuando el sistema ya está en producción y la gente depende de él.

---

### 2.2 Qué es Staging y qué NO es

**Staging** (también *landing zone*, *raw layer*, *bronce*) es una **copia de los datos del origen, fiel en estructura, almacenada en un lugar bajo tu control, sobre la que podés trabajar sin afectar a nadie.**

Desarmemos esa definición, porque cada parte carga peso:

- **"copia"** — no es una vista ni un sinónimo. Son datos físicos, materializados. Existe aunque el origen esté caído.
- **"fiel en estructura"** — mismos nombres, mismas columnas, mismo orden. Cuanto más se parezca al origen, más fácil es diagnosticar diferencias.
- **"bajo tu control"** — podés truncarla, indexarla, borrarla, romperla. No pedís permiso.
- **"sin afectar a nadie"** — nadie más consume staging. Ni Power BI, ni reportes, ni usuarios.

**Qué NO es staging:**

| ❌ No es | Por qué |
|---|---|
| Una base de reportes | Nadie consulta staging. Su consumidor es el proceso siguiente. |
| Un backup | No sirve para recuperar el origen. Está desactualizada y solo tiene parte de los datos. |
| El lugar de la lógica de negocio | Las reglas van en la transformación, no en la extracción. |
| Una copia con "mejoras" | Renombrar, reformatear o filtrar **es transformación**, y no va acá. |
| Un archivo histórico | Se sobrescribe en cada carga. La historia vive en el warehouse. |

> **✅ Regla mental que resuelve el 90% de las dudas de diseño:**
> *Si al mirar una tabla de staging no podés decir de qué tabla del origen vino y por qué se llama así, la diseñaste mal.*

---

### 2.3 Los cinco problemas que resuelve

**1 — Aislamiento del origen.** Es el más obvio: una sola consulta simple contra producción, en horario de baja actividad, en vez de decenas de consultas complejas durante todo el día. Producción ve un `SELECT * FROM Sales.Orders` y nada más.

**2 — Punto de corte consistente.** Todas las transformaciones trabajan sobre **la misma foto**. Sin staging, si el paso A lee a las 02:00 y el paso B a las 02:04, pueden ver estados distintos del mismo dato y producir un modelo internamente inconsistente. Con staging, la foto se toma una vez.

**3 — Reprocesamiento sin tocar el origen.** Si la lógica de transformación tenía un error, corregís y volvés a correr **desde staging**. El origen ni se entera. Esto es lo que hace posible el **backfill**.

**4 — Desacople de cambios.** Si el origen cambia un nombre de columna, se ajusta **solo la extracción**. Toda la lógica aguas abajo sigue igual. Es la capa anticorrupción del Módulo 0, hecha tabla.

**5 — Diagnóstico.** Cuando un número no cuadra, staging te deja comparar tres cosas: qué hay en el origen **ahora**, qué había **cuando cargaste**, y qué produjo la transformación. Sin staging solo tenés la primera y la tercera — y la diferencia entre ellas es indistinguible de un error de tu código.

> **🎓 En entrevista:** si te preguntan "¿para qué sirve staging?" y respondés solo "para no afectar producción", das el 20% de la respuesta. Los cinco motivos juntos muestran que entendés el ciclo de vida completo de un pipeline.

---

### 2.4 Staging alineado al origen

> **💡 Concepto clave — *source-aligned staging*.** La capa bronce **preserva la estructura del origen**. No renombra, no reordena, no reinterpreta.

Esto suele generar resistencia, porque el instinto de todo desarrollador es mejorar lo que toca. Si el origen tiene `cust_nm_1`, ¿por qué no ponerle `CustomerName` ya que estamos?

**Tres razones concretas:**

1. **Renombrar es transformar, y transformar en bronce mezcla responsabilidades.** El día que un número no cuadre vas a querer comparar staging contra el origen columna por columna. Si los nombres difieren, cada comparación necesita un mapeo mental, y los mapeos mentales son donde se cuelan los errores.

2. **El mapeo debe estar en un solo lugar.** Si renombrás en bronce y volvés a renombrar en oro, tenés dos capas de traducción y ninguna es autoritativa. ¿Dónde mirás cuando querés saber de dónde salió `CustomerName`?

3. **La extracción debe poder generarse automáticamente.** Si bronce refleja el origen, podés generar el DDL y el `INSERT` desde `INFORMATION_SCHEMA`. Si cada tabla tiene su criterio de renombrado, cada una es trabajo manual — y trabajo manual repetido es donde viven los errores de tipeo.

**En tu proyecto** esto se ve así: la tabla se llama `Sales.Orders` dentro de `WWI_Staging`, **con el mismo schema `Sales` que el origen**. No `dbo.Orders`, no `staging.OrdenesDeVenta`.

Y hay un beneficio adicional: el schema `Sales` de staging contiene **solo** lo que existe en `Sales` del origen. Los objetos del pipeline —tablas de control, logs, procedimientos— viven en un schema aparte, `etl`. Así el espejo es un espejo, sin cosas tuyas mezcladas.

```
WWI_Staging
├── Sales
│   └── Orders          ← espejo de WideWorldImporters.Sales.Orders
└── etl
    ├── LoadBatch       ← control de ejecuciones  (tuyo)
    ├── ValidationLog   ← resultados de validación (tuyo)
    ├── usp_LoadSalesOrders
    └── usp_ValidateSalesOrders
```

> **✅ Práctica profesional:** ese schema `etl` es lo que en la industria se llama **framework de ETL** o **metadata layer**. En herramientas comerciales viene incluido; cuando construís a mano, lo construís vos. Tenerlo es una de las señales más claras de que un pipeline fue diseñado y no improvisado.

---

### 2.5 Cómo diseñar una tabla de staging

**El método: derivarla del origen, no inventarla.**

```sql
SELECT
    COLUMN_NAME, DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH, NUMERIC_PRECISION, NUMERIC_SCALE, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'Sales' AND TABLE_NAME = 'Orders'
ORDER BY ORDINAL_POSITION;
```

Ese resultado es tu especificación. A partir de ahí, **tres modificaciones deliberadas** y ninguna más:

1. **Todas las columnas del origen quedan NULL-able** (sección 2.6).
2. **Algunos tipos se relajan** (sección 2.7).
3. **Se agregan columnas de auditoría** (sección 2.8).

**El DDL resultante:**

```sql
USE WWI_Staging;
GO

CREATE TABLE Sales.Orders (
    -- ── Columnas del origen, mismos nombres, todas NULL-able ──
    OrderID                      INT             NULL,
    CustomerID                   INT             NULL,
    SalespersonPersonID          INT             NULL,
    PickedByPersonID             INT             NULL,
    ContactPersonID              INT             NULL,
    BackorderOrderID             INT             NULL,
    OrderDate                    DATE            NULL,
    ExpectedDeliveryDate         DATE            NULL,
    CustomerPurchaseOrderNumber  NVARCHAR(20)    NULL,
    IsUndersupplyBackordered     BIT             NULL,
    Comments                     NVARCHAR(MAX)   NULL,
    DeliveryInstructions         NVARCHAR(MAX)   NULL,
    InternalComments             NVARCHAR(MAX)   NULL,
    PickingCompletedWhen         DATETIME2(7)    NULL,
    LastEditedBy                 INT             NULL,
    LastEditedWhen               DATETIME2(7)    NULL,

    -- ── Columnas de auditoría, agregadas por nosotros ──
    LoadBatchId                  UNIQUEIDENTIFIER NOT NULL,
    LoadedAt                     DATETIME2        NOT NULL
        CONSTRAINT DF_StgOrders_LoadedAt DEFAULT SYSUTCDATETIME()
);
```

> **⚠️ El error más común de todo el módulo: `SELECT ... INTO`.**
>
> ```sql
> -- ❌ NO HAGAS ESTO
> SELECT * INTO Sales.Orders FROM WideWorldImporters.Sales.Orders;
> ```
>
> Es tentador: una línea, sin escribir DDL. Y está mal por **cuatro** motivos:
>
> 1. **No es idempotente.** La segunda corrida falla porque la tabla ya existe. Un proceso que solo funciona la primera vez no es un proceso.
> 2. **Hereda las restricciones del origen**, incluido `NOT NULL`. Justo lo que **no** queremos (2.6).
> 3. **No deja lugar a columnas de auditoría.** No sabés de qué carga vino cada fila.
> 4. **La estructura queda invisible.** No hay DDL en ningún archivo: la definición de tu tabla depende de cómo estaba el origen el día que corriste eso. **La estructura deja de estar bajo control de versiones**, y con ella se va la posibilidad de reconstruir el entorno.

---

### 2.6 Por qué en staging casi todo es NULL-able

Contraintuitivo, así que vale la pena entenderlo bien.

**El razonamiento:** el trabajo de staging es **recibir el dato, sea como sea**. Si ponés `NOT NULL` en `CustomerID` y un día llega un pedido sin cliente, la carga **falla entera**. Perdés los 73.594 pedidos buenos por uno malo.

Y perdés algo más importante: **la información de que hay un problema**. Un `INSERT` que falla te dice "algo salió mal". Una fila cargada y marcada por una validación te dice "el pedido 4471 no tiene cliente", que es accionable.

> **💡 Concepto clave — validar en vez de restringir.** En staging, las reglas de calidad se aplican como **observación** (validaciones que registran hallazgos), no como **restricción** (constraints que rechazan filas). La restricción es apropiada en producción, donde evita que entre basura. En staging la basura **ya entró en otro lado** — tu trabajo es detectarla, no fingir que no existe.

Es exactamente la diferencia entre lanzar una excepción y devolver un `Result` con la lista de errores de validación. En un formulario web no querés que el primer campo inválido aborte todo: querés mostrar los siete errores juntos.

**Las dos excepciones**, y son las columnas que **vos** controlás:

- `LoadBatchId NOT NULL` — la ponés vos en cada `INSERT`. Si es NULL, es un bug de tu código, no un problema del origen.
- `LoadedAt NOT NULL` con `DEFAULT` — la pone el motor. Nunca puede faltar.

> **✅ La regla completa:** *NULL-able para lo que viene de afuera; NOT NULL para lo que controlás vos.* Es la misma frontera de confianza que aplicás cuando validás la entrada de un usuario pero confiás en tus propias constantes.

---

### 2.7 Tipos de datos: cuándo relajarlos

**Regla general: usá el mismo tipo que el origen.** El tipo correcto es documentación y evita conversiones sorpresa.

**Las excepciones, y cada una tiene su motivo:**

**Longitudes de texto — ampliar, nunca reducir.** Si el origen tiene `NVARCHAR(20)` y llega un valor de 25 caracteres (por un cambio en el origen, o por una carga desde otra fuente), un `NVARCHAR(20)` en staging **trunca o falla**. Un `NVARCHAR(50)` recibe el dato y deja que la validación lo marque.

Cuánto ampliar es un juicio: demasiado poco no protege, demasiado desperdicia y hace que `NVARCHAR(MAX)` sea tentador. Una regla razonable es ampliar donde el origen ya está cerca del límite, y dejar igual el resto.

**Tipos de fecha — considerar recibir como texto cuando el origen no es confiable.** Si extraés de un CSV o de un sistema con formatos mixtos, un `DATE` en staging **rechaza** `'2025-13-45'`. Recibirlo como `NVARCHAR(50)` te permite cargarlo, **detectarlo con `TRY_CONVERT`** y decidir qué hacer.

En este proyecto el origen es SQL Server con `DATE` real, así que no hace falta. Pero sabé que la técnica existe, porque el día que integres un archivo la vas a necesitar.

```sql
-- Detección de fechas inválidas cuando vienen como texto
SELECT COUNT(*) AS FechasInvalidas
FROM Sales.Orders
WHERE OrderDateTexto IS NOT NULL
  AND TRY_CONVERT(DATE, OrderDateTexto) IS NULL;
```

> **💡 `TRY_CONVERT` / `TRY_CAST` / `TRY_PARSE`** devuelven `NULL` en vez de fallar cuando la conversión es imposible. Son **fundamentales** en ETL: convierten un error fatal en un dato marcable.

**Lo que NO se relaja nunca:**

- **`DECIMAL` a `FLOAT` en montos.** `FLOAT` es punto flotante binario: no puede representar `0.1` exactamente. Los errores se acumulan al sumar y tus totales quedan mal por centavos que nadie puede explicar. **Dinero siempre en `DECIMAL`.**
- **`DATETIME2` a `DATETIME`.** Pierde precisión y tiene un rango menor.
- **`NVARCHAR` a `VARCHAR`.** Pierde caracteres no ASCII. Un nombre con acento llega mutilado.

---

### 2.8 Columnas de auditoría

Dos columnas, y cada una responde una pregunta que te van a hacer:

```sql
LoadBatchId  UNIQUEIDENTIFIER NOT NULL,
LoadedAt     DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
```

**`LoadBatchId`** — un identificador único **por ejecución**, no por fila. Todas las filas de la misma carga comparten el mismo valor.

*Qué responde:* "¿esta fila de qué corrida vino?", "¿cuántas filas trajo la carga que falló?", "¿este dato raro apareció en la carga de anoche o ya estaba?".

Es lo que conecta staging con `etl.LoadBatch` y `etl.ValidationLog`. Es la columna que hace posible el **linaje del dato** (*data lineage*).

*Por qué `UNIQUEIDENTIFIER` y no un `INT` autoincremental:* porque se genera con `NEWID()` **antes** de escribir nada. Un `IDENTITY` requeriría insertar primero para saber el número, y necesitás el identificador desde el primer instante — incluso si la carga falla antes de insertar una sola fila.

**`LoadedAt`** — cuándo se cargó la fila.

*Qué responde:* "¿qué tan viejos son estos datos?". Es la base de las validaciones de **frescura** (*data freshness*).

> **⚠️ `SYSUTCDATETIME()` y no `GETDATE()`.**
>
> `GETDATE()` devuelve la hora local del servidor. Eso trae **dos** problemas reales:
>
> 1. **Horario de verano.** Cuando el reloj retrocede una hora, hay 60 minutos que **ocurren dos veces**. Ordenar por `LoadedAt` da un orden incorrecto, y calcular "cuánto tardó" puede dar negativo.
> 2. **Servidores en zonas distintas.** Comparar timestamps entre sistemas deja de tener sentido.
>
> UTC es monótono y universal. **Se guarda en UTC y se convierte a local solo al mostrar.** Es la misma regla que en cualquier aplicación distribuida.
>
> **El detalle práctico que te va a confundir:** SQL Server Agent guarda su historial en **hora local**, mientras que tus tablas `etl.*` guardan **UTC**. La misma ejecución aparece con horas distintas en cada lugar. No es un error — es la consecuencia esperada de la decisión, y hay que documentarla.

---

### 2.9 Base separada vs schema separado

Tres opciones, y la respuesta correcta no es obvia:

| Opción | Ventajas | Desventajas |
|---|---|---|
| **Schema dentro de producción** | Sin configuración; joins directos | **Contamina producción**; comparte recursos, backups y modelo de recuperación |
| **Base separada, mismo servidor** | Aislada; recuperación propia; permisos propios; joins con 3 partes | Comparte CPU y memoria |
| **Servidor separado** | Aislamiento total | Necesita Linked Server o herramienta de copia; más complejidad |

**Para este proyecto: base separada en el mismo servidor.** Es el equilibrio correcto para aprender, y es una arquitectura perfectamente válida en producción para volúmenes moderados.

> **⚠️ Error de arquitectura que vale la pena señalar.** Crear el staging como un schema **dentro** de la base de producción parece práctico —los joins no necesitan tres partes— y contradice directamente la restricción "nunca tocar producción". Aunque solo leas de las tablas de negocio, estás **escribiendo** en la base: ocupás su espacio, entrás en sus backups, y compartís su modelo de recuperación. Si producción está en FULL, tus `TRUNCATE` + `INSERT` diarios inflan el log de producción.
>
> Es un error fácil de cometer y fácil de corregir temprano. Corregirlo tarde, cuando ya hay veinte objetos y procesos apuntando ahí, es un proyecto.

**Convención de nombres de tres partes — regla importante:**

> **✅ Usá nombres de tres partes (`Base.Schema.Tabla`) SOLO cuando cruzás bases.**

```sql
-- ✅ Correcto: el origen está en otra base
FROM WideWorldImporters.Sales.Orders

-- ✅ Correcto: destino local, dos partes
INSERT INTO Sales.Orders

-- ❌ Incorrecto: destino local con nombre de tres partes
INSERT INTO WWI_Staging.Sales.Orders
```

**Por qué importa:** si algún día restaurás una copia de staging con otro nombre (`WWI_Staging_Dev`, por ejemplo) para probar algo, los nombres de dos partes se resuelven contra la base actual y todo funciona. Los de tres partes **siguen apuntando a la base original** — y tu prueba de desarrollo escribe en el staging real sin que te des cuenta.

Es un fallo silencioso de manual: el procedimiento corre bien, sin error, y modifica la base equivocada.

---

### 2.10 Full Load vs Incremental Load

> ➕ **Tema adicional recomendado:** estrategias de carga
> **Por qué necesito aprenderlo:** es una decisión de diseño que aparece en cada tabla del pipeline, y la pregunta "¿cómo harías esto si fueran 500 millones de filas?" es un clásico de entrevista.
> **En qué parte del proyecto lo utilizaremos:** en la carga de staging (este módulo) y en la carga del modelo dimensional (Módulo 10).

**Full Load** — se borra todo y se carga todo, cada vez.

```sql
TRUNCATE TABLE Sales.Orders;
INSERT INTO Sales.Orders (...) SELECT ... FROM WideWorldImporters.Sales.Orders;
```

✅ Simple · Naturalmente idempotente · Se autocorrige (si una carga anterior quedó mal, la siguiente lo arregla) · Refleja borrados del origen automáticamente

❌ Costo proporcional al tamaño total · Inviable con volúmenes grandes · Golpea más el origen

**Incremental Load (delta load)** — solo lo que cambió.

```sql
DECLARE @UltimaCarga DATETIME2 = (
    SELECT MAX(LastEditedWhen) FROM Sales.Orders
);

INSERT INTO Sales.Orders (...)
SELECT ... FROM WideWorldImporters.Sales.Orders
WHERE LastEditedWhen > @UltimaCarga;
```

✅ Rápido · Escala · Poco impacto en el origen

❌ Complejo · Necesita una columna de cambio confiable · **No detecta borrados físicos** · Si falla en el medio, el estado es ambiguo · Requiere una marca de agua persistida

**Cómo se decide — en este orden:**

1. **¿Cuántas filas son?** Menos de un millón: full load casi siempre. Es más simple y la simplicidad tiene valor real.
2. **¿Cuánto tarda?** Si el full load entra en la ventana de mantenimiento, no hay problema que resolver.
3. **¿Hay columna de cambio confiable?** Sin `LastEditedWhen`, `rowversion` o Change Data Capture, el incremental es adivinanza.
4. **¿Se borran filas físicamente?** Si sí, el incremental por sí solo **no lo detecta** y tu staging acumula fantasmas.

**Decisión de este proyecto: full load.** 73.595 filas cargan en segundos. Usar incremental acá sería complejidad sin beneficio.

> **✅ Y esto es lo que hay que documentar:** *"Usamos full load porque la tabla tiene 73.595 filas y carga en segundos. Migraríamos a incremental si superara el millón de filas o si la ventana de carga excediera los 10 minutos. `Sales.Orders` tiene `LastEditedWhen`, así que la migración sería viable."*
>
> Esa frase, en un README, es lo que distingue a alguien que **eligió** de alguien que **hizo lo primero que se le ocurrió**. En una entrevista, decirlo así vale más que la decisión en sí.

> **💡 Concepto relacionado — Change Data Capture (CDC).** SQL Server puede registrar automáticamente todos los cambios de una tabla, incluidos los borrados, en tablas de cambios consultables. Es la forma robusta de hacer incremental. Requiere habilitarlo en el origen (permiso de administrador) y tiene costo de rendimiento — por eso raramente está disponible cuando lo necesitás.

---

### 2.11 Idempotencia

> **💡 Concepto clave — idempotencia.** Una operación es idempotente si **ejecutarla N veces produce el mismo resultado que ejecutarla una vez**.

El nombre viene del álgebra, pero la idea es simple. En HTTP: `GET` y `PUT` son idempotentes, `POST` no. Apretar "actualizar" en una página es seguro; apretar "pagar" dos veces, no.

**Por qué es LA propiedad central de un pipeline:**

Los procesos automatizados fallan. La red se cae, el disco se llena, un bloqueo expira. Cuando eso pasa, alguien —una persona o un reintento automático— va a volver a ejecutar el proceso.

**Si el proceso es idempotente, reintentar es gratis.** Se aprieta el botón sin pensar.

**Si no lo es, cada reintento es una decisión de riesgo.** ¿Alcanzó a insertar? ¿Cuánto? ¿Hay que limpiar antes? Esa duda, a las 3 AM, con el reporte del directorio a las 8, es cómo se toman las malas decisiones.

**Cómo se logra:**

| Estrategia | Cómo | Cuándo |
|---|---|---|
| **Truncate + Insert** | Borrar todo y recargar | Full load. **La nuestra.** |
| **Delete + Insert por rango** | Borrar la ventana y recargarla | Incremental por período |
| **MERGE / Upsert** | Actualizar si existe, insertar si no | Incremental por clave |
| **Insert con anti-join** | `WHERE NOT EXISTS` | Solo agregados, nunca cambios |

**Verificación práctica — la prueba que hay que hacer siempre:**

```sql
EXEC etl.usp_LoadSalesOrders;
SELECT COUNT(*) AS Corrida1 FROM Sales.Orders;   -- 73595

EXEC etl.usp_LoadSalesOrders;
SELECT COUNT(*) AS Corrida2 FROM Sales.Orders;   -- 73595  ✅

SELECT COUNT(DISTINCT LoadBatchId) AS Lotes FROM Sales.Orders;  -- 1  ✅
```

**Las dos comprobaciones son distintas y las dos importan.** El conteo igual prueba que no se duplicó. **El `COUNT(DISTINCT LoadBatchId) = 1` prueba que la tabla contiene el resultado de una sola carga** — es decir, que la anterior se borró de verdad y no quedaron filas viejas mezcladas.

> **🎓 Pregunta de entrevista frecuente:** *"Tu carga falló a mitad de camino. ¿Qué hacés?"* La respuesta corta y correcta: **"la vuelvo a correr"** — y explicar por qué eso es seguro. Si tenés que explicar un procedimiento de limpieza manual, el diseño tiene un problema.

---

### 2.12 `TRUNCATE` vs `DELETE` vs `DROP` + `CREATE`

| | `TRUNCATE` | `DELETE` | `DROP` + `CREATE` |
|---|---|---|---|
| Velocidad | Muy rápida | Lenta | Rápida |
| Registro en log | Mínimo (desasigna páginas) | Fila por fila | Mínimo |
| Acepta `WHERE` | ❌ | ✅ | ❌ |
| Dispara triggers | ❌ | ✅ | ❌ |
| Reinicia `IDENTITY` | ✅ | ❌ | ✅ |
| **Es transaccional** | ✅ **en SQL Server** | ✅ | ✅ (DDL en SQL Server) |
| Conserva permisos e índices | ✅ | ✅ | ❌ |
| Requiere | `ALTER TABLE` | `DELETE` | `CONTROL` |

**Elegimos `TRUNCATE`** porque es el más rápido, casi no toca el log y borra la tabla entera — que es exactamente lo que queremos en un full load.

> **⚠️ El detalle que confunde a mucha gente: `TRUNCATE` SÍ es transaccional en SQL Server.**
>
> En **Oracle y MySQL**, `TRUNCATE` es DDL con confirmación implícita: se confirma solo y **no se puede deshacer**. Mucha documentación en internet —y mucha gente con experiencia en esos motores— repite que "TRUNCATE no se puede revertir". **En SQL Server eso es falso.**
>
> ```sql
> BEGIN TRANSACTION;
>     TRUNCATE TABLE Sales.Orders;
>     SELECT COUNT(*) FROM Sales.Orders;   -- 0
> ROLLBACK TRANSACTION;
> SELECT COUNT(*) FROM Sales.Orders;       -- 73595  ✅ volvió
> ```
>
> **Esto es lo que hace posible todo el diseño del Módulo 3**: envolver `TRUNCATE` + `INSERT` en una transacción para que un fallo del insert no deje la tabla vacía. Si `TRUNCATE` no fuera reversible, habría que usar `DELETE` (mucho más lento) o cargar a una tabla temporal e intercambiar.

**Por qué NO `DROP` + `CREATE`:** perdés índices, permisos y constraints; y la estructura pasa a depender del script en vez de estar fija en la base. Si el `CREATE` tiene un error, te quedaste sin tabla.

**Cuándo sí `DELETE`:** cuando necesitás borrar **parte** de la tabla (una recarga por rango de fechas). Es la opción natural del incremental por ventana.

---

## 💡 Conceptos clave

- **Staging / bronce** — copia fiel del origen, bajo tu control, sin consumidores externos.
- **Source-aligned staging** — preservar la estructura del origen; renombrar es transformar.
- **Framework de ETL** — el schema `etl` con control, logs y procedimientos.
- **Validar en vez de restringir** — en staging se detecta, no se rechaza.
- **Columnas de auditoría** — `LoadBatchId` (linaje) y `LoadedAt` (frescura).
- **Full load / incremental load** — recargar todo vs solo lo cambiado.
- **Watermark** — marca de hasta dónde se procesó.
- **CDC** — captura automática de cambios, incluidos borrados.
- **Idempotencia** — repetir sin consecuencias acumuladas.

---

## ⚠️ Errores comunes

**`SELECT ... INTO`** — cuatro problemas, sección 2.5. El más grave es que la estructura queda fuera del control de versiones.

**`NOT NULL` en staging** — una fila mala rompe la carga entera y perdés el diagnóstico.

**Renombrar columnas en bronce** — mezcla capas y complica el diagnóstico.

**`GETDATE()` en vez de `SYSUTCDATETIME()`** — se rompe con horario de verano.

**Nombres de tres partes para objetos locales** — una copia de la base escribe en la original. Fallo silencioso.

**Staging dentro de producción** — contradice el aislamiento; infla el log de producción.

**Olvidar `LoadBatchId` en el `INSERT`** — la columna es `NOT NULL`, así que **esto sí falla ruidosamente**. Es intencional: es el único caso donde queremos que reviente, porque es un bug tuyo.

**Usar incremental "porque es más profesional"** — complejidad sin beneficio en tablas chicas. La simplicidad es una decisión de diseño válida y hay que saber defenderla.

**Consultar staging desde Power BI** — rompe el aislamiento de capas. Staging no tiene consumidores externos.

---

## ✅ Buenas prácticas

1. **DDL explícito, siempre.** En un archivo `.sql`, en Git.
2. **Un schema `etl` aparte** para todo lo que no existe en el origen.
3. **Auditoría desde el día uno.** Agregarla después obliga a recargar todo.
4. **UTC en toda la infraestructura.** Local solo al mostrar.
5. **Documentá la estrategia de carga con su umbral de revisión.**
6. **Probá la idempotencia explícitamente** — dos corridas, mismo conteo, un solo `LoadBatchId`.
7. **Nunca un índice en staging "por si acaso".** Cada índice hace más lento el `INSERT`, que es la operación dominante acá. Poné índices solo si medís una consulta lenta sobre staging.
8. **Nombrá los constraints.** `DF_StgOrders_LoadedAt` se puede modificar en un script; un nombre autogenerado (`DF__Orders__Loaded__3B75D760`) cambia en cada entorno y rompe los despliegues.

---

## 🧠 Preguntas de comprensión

1. Un compañero propone poner `NOT NULL` en `OrderID` de staging "porque en el origen es la PK y nunca puede ser nulo". ¿Qué le respondés?
2. Corrés la carga dos veces y `COUNT(*)` da 73.595 las dos veces. ¿Alcanza para afirmar que es idempotente? ¿Qué más verificarías?
3. Explicá por qué `TRUNCATE` dentro de una transacción es la base del diseño del Módulo 3, y qué habría que hacer si SQL Server se comportara como Oracle.
4. ¿Por qué `LoadBatchId` es `UNIQUEIDENTIFIER` y no `INT IDENTITY`?
5. Tu staging tiene 200 millones de filas y el full load tarda 6 horas. La ventana es de 2. Enumerá en orden las tres cosas que evaluarías antes de saltar a incremental.

---

## 📝 Ejercicios

**🟢 Básico.** Creá `WWI_Staging` con recuperación SIMPLE, los schemas `Sales` y `etl`, y la tabla `Sales.Orders` con las 16 columnas del origen más las dos de auditoría. Todo en archivos `.sql` versionados.

**🟢 Básico.** Verificá la idempotencia con las tres consultas de la sección 2.11.

**🟡 Intermedio.** Diseñá la tabla de staging para `Sales.OrderLines` (231.412 filas). Fijate qué columnas son calculadas en el origen y decidí qué hacer con ellas. Justificá cada decisión de tipo.

**🟡 Intermedio.** Escribí la versión **incremental** de la carga de `Sales.Orders` usando `LastEditedWhen`. Después listá los tres casos en los que tu versión daría un resultado incorrecto.

**🔴 Avanzado.** Escribí un procedimiento que **genere automáticamente** el DDL de staging para cualquier tabla del origen: lee `INFORMATION_SCHEMA.COLUMNS`, hace todas las columnas NULL-able, agrega las de auditoría y devuelve el `CREATE TABLE` como texto. Esto es **generación de código con metadatos**, y es cómo se construyen los frameworks de ETL de verdad.

**🔴 Avanzado.** Demostrá empíricamente que `TRUNCATE` es transaccional en SQL Server. Después demostrá que un `INSERT` fallido **sin** transacción deja la tabla vacía. Guardá ambos scripts: son la justificación del Módulo 3.

**🧠 Reto.** Diseñá una estrategia de staging para una tabla de 500 millones de filas, con borrados físicos en el origen y sin CDC disponible. Tenés que detectar inserciones, modificaciones **y borrados**, en una ventana de 2 horas. Describí la solución, su costo, y qué le pedirías al equipo del sistema origen para simplificarla. *(Pista: pensá en comparación de claves y en particionamiento por rango.)*

---

## 🎓 Preguntas de entrevista

1. **¿Para qué sirve una capa de staging?** — Los cinco motivos de 2.3.
2. **¿Full o incremental?** — El árbol de decisión de 2.10, con el umbral explícito.
3. **¿Qué es idempotencia y cómo la lográs?** — Definición + las cuatro estrategias.
4. **¿Por qué las tablas de staging permiten NULL?** — Validar en vez de restringir.
5. **¿`TRUNCATE` o `DELETE`?** — La tabla comparativa, y **destacar que en SQL Server `TRUNCATE` es transaccional**. Ese detalle sorprende y demuestra profundidad.
6. **¿Cómo sabés de qué carga vino una fila?** — `LoadBatchId`, y explicar el linaje.
7. **¿Ponés índices en staging?** — Por defecto no: la operación dominante es `INSERT` y cada índice la penaliza. Solo si se mide una necesidad.
8. **Tu carga falló a mitad. ¿Qué hacés?** — La vuelvo a correr; es idempotente. Si no lo fuera, tendría un problema de diseño.

---

## 📌 Resumen

- Staging es una copia fiel, aislada, bajo tu control y **sin consumidores externos**.
- Resuelve cinco problemas: aislamiento, consistencia, reprocesamiento, desacople y diagnóstico.
- **Alineado al origen**: mismos nombres, mismos schemas. Renombrar es transformar.
- Casi todo NULL-able: se **valida**, no se restringe. NOT NULL solo en lo que controlás vos.
- Tipos iguales al origen, con ampliaciones deliberadas. **Nunca `FLOAT` para dinero.**
- `LoadBatchId` da linaje; `LoadedAt` da frescura; ambos en **UTC**.
- Base separada, y nombres de tres partes **solo** al cruzar bases.
- Full load si la tabla es chica: la simplicidad vale, y hay que documentar el umbral de revisión.
- **Idempotencia** es la propiedad que hace seguros los reintentos.
- En SQL Server `TRUNCATE` **es transaccional** — y eso habilita todo el Módulo 3.

---

## 🗂️ Flashcards

| Pregunta | Respuesta |
|---|---|
| ¿Qué es staging? | Copia fiel del origen, aislada, bajo tu control, sin consumidores externos. |
| ¿Cinco problemas que resuelve? | Aislamiento, consistencia, reprocesamiento, desacople, diagnóstico. |
| ¿Qué es source-aligned staging? | Preservar nombres y estructura del origen en la capa bronce. |
| ¿Por qué NULL-able en staging? | Para recibir el dato y **validarlo**, en vez de rechazar la carga entera. |
| ¿Cuáles columnas sí van NOT NULL? | Las de auditoría: las controlás vos. |
| ¿Por qué `SYSUTCDATETIME()`? | UTC es monótono; la hora local se rompe con horario de verano. |
| ¿Para qué `LoadBatchId`? | Linaje: saber de qué ejecución vino cada fila. |
| ¿`SELECT INTO` para staging? | No: no es idempotente, hereda NOT NULL, sin auditoría, sin DDL versionado. |
| ¿Full load o incremental? | Full si es chica y simple; incremental si el volumen o la ventana lo exigen. |
| ¿Qué es idempotencia? | Correr N veces = correr una vez. |
| ¿Cómo se prueba la idempotencia? | Dos corridas: mismo conteo **y** un solo `LoadBatchId` distinto. |
| ¿`TRUNCATE` es reversible en SQL Server? | **Sí**, dentro de una transacción. En Oracle y MySQL no. |
| ¿Índices en staging? | No por defecto: penalizan el `INSERT`, que es la operación dominante. |
| ¿Cuándo nombres de tres partes? | Solo al cruzar bases de datos. |
| ¿Qué es CDC? | Change Data Capture: registro automático de cambios, incluidos borrados. |

---

## ☑️ Checklist antes de avanzar

- [ ] `WWI_Staging` existe, en SIMPLE, con schemas `Sales` y `etl`.
- [ ] `Sales.Orders` creada con DDL explícito y versionado.
- [ ] Todas las columnas del origen son NULL-able; las de auditoría no.
- [ ] Puedo explicar por qué, sin dudar.
- [ ] `LoadedAt` usa `SYSUTCDATETIME()` y sé por qué.
- [ ] Probé la idempotencia con las dos comprobaciones.
- [ ] Puedo defender full load con un umbral concreto de revisión.
- [ ] Sé que `TRUNCATE` es transaccional en SQL Server y lo demostré.
- [ ] No usé nombres de tres partes para objetos locales.

---

## 📋 Examen del Módulo 2

### Selección múltiple

**1.** ¿Por qué las columnas de staging son NULL-able?
a) Porque SQL Server lo exige
b) Para que una fila mala no haga fallar la carga entera y se pueda validar
c) Porque ocupan menos espacio
d) Porque el origen las tiene así

**2.** ¿Cuál NO es un problema de `SELECT * INTO`?
a) No es idempotente
b) Hereda las restricciones del origen
c) La estructura queda fuera del control de versiones
d) Es más lento que `CREATE TABLE` + `INSERT`

**3.** En SQL Server, `TRUNCATE TABLE` dentro de una transacción:
a) Confirma automáticamente y no se puede deshacer
b) Se puede revertir con `ROLLBACK`
c) Falla con error
d) Se comporta como `DELETE`

**4.** ¿Por qué `LoadBatchId` es `UNIQUEIDENTIFIER` y no `INT IDENTITY`?
a) Es más rápido
b) Se genera con `NEWID()` **antes** de insertar, y hace falta desde el inicio
c) Ocupa menos espacio
d) `IDENTITY` no funciona en staging

**5.** Nombres de tres partes (`Base.Schema.Tabla`) deben usarse:
a) Siempre, por claridad
b) Solo al cruzar bases de datos
c) Nunca
d) Solo en procedimientos almacenados

**6.** ¿Cuál es el riesgo de guardar montos en `FLOAT`?
a) Ocupa más espacio
b) No acepta negativos
c) Es punto flotante binario: acumula error al sumar
d) No se puede indexar

### Verdadero / Falso

**7.** Staging debe tener los datos ya limpios.
**8.** Es buena práctica renombrar columnas mal nombradas al pasarlas a bronce.
**9.** Power BI puede conectarse a staging si es más cómodo.
**10.** Un full load detecta automáticamente los borrados del origen.
**11.** Un incremental load basado en fecha de modificación detecta borrados físicos.
**12.** Conviene indexar las tablas de staging para acelerar las transformaciones.

### SQL

**13.** Escribí el DDL de staging para `Sales.OrderLines`, aplicando las tres modificaciones deliberadas. Incluí un comentario justificando cada decisión de tipo que se aparte del origen.

**14.** Escribí las consultas que prueban que una carga es idempotente. Deben ser **dos** comprobaciones distintas, y explicá qué demuestra cada una.

### Debugging

**15.** Este código está en un procedimiento de `WWI_Staging`. Corre sin error. ¿Qué problema tiene y en qué escenario concreto causa un desastre silencioso?

```sql
TRUNCATE TABLE WWI_Staging.Sales.Orders;
INSERT INTO WWI_Staging.Sales.Orders (...)
SELECT ... FROM WideWorldImporters.Sales.Orders;
```

**16.** Un pipeline usa `GETDATE()` en `LoadedAt`. Funcionó un año. Una madrugada de otoño el reporte de "cargas de la última hora" muestra filas duplicadas y una duración negativa. Explicá exactamente qué pasó.

### Análisis de escenario

**17.** Tu tabla de staging tiene 200 millones de filas. El full load tarda 6 horas y la ventana es de 2. El origen tiene `LastEditedWhen` pero también borra filas físicamente. Proponé una solución completa: cómo detectás inserciones, modificaciones y borrados; qué costo tiene cada parte; y qué le pedirías al equipo del origen.

### Diseño

**18.** Justificá en un párrafo, como si se lo explicaras a un arquitecto, por qué staging va en una base separada y no en un schema dentro de producción. Tiene que incluir al menos un argumento sobre el log de transacciones.

