---

# Módulo 3 — Stored Procedures para ETL

> **Paso 2 del proyecto, parte 2 de 3**

## 🎯 Objetivos

Al terminar este módulo vas a poder:

- Explicar por qué la lógica de ETL vive en un Stored Procedure y no en un script suelto.
- Usar parámetros y variables entendiendo la diferencia entre **declaración** y **asignación**.
- Justificar `SET NOCOUNT ON` y `SET XACT_ABORT ON`.
- Envolver operaciones en transacciones y explicar qué garantiza cada letra de ACID.
- Escribir `TRY` / `CATCH` que no mienta sobre el resultado.
- Distinguir `THROW` de `RAISERROR` y saber cuál usar.
- Diseñar una tabla de control de ejecuciones y explicar por qué va **fuera** de la transacción.
- Separar carga de validación y explicar por qué eso es una decisión de **testabilidad**.
- Reconocer los errores que `TRY/CATCH` **no** atrapa.

---

## 📖 Teoría

### 3.1 Qué es un Stored Procedure y por qué el ETL vive ahí

Un **Stored Procedure** (procedimiento almacenado) es código T-SQL guardado y ejecutable dentro de la base, con nombre, parámetros y permisos propios.

Para alguien que viene de desarrollo, la analogía inmediata es "un método". Es útil, pero incompleta: un procedimiento almacenado también es una **unidad de despliegue** y una **frontera de seguridad**.

**Por qué el ETL va acá y no en un script `.sql` suelto o en código de aplicación:**

**1 — Es invocable por el orquestador.** SQL Server Agent ejecuta `EXEC etl.usp_LoadSalesOrders;`. Una línea, estable en el tiempo. Si la lógica estuviera pegada en el paso del job, **cambiarla implicaría editar el job** — y la lógica dejaría de estar en Git.

**2 — Está versionada dentro de la base.** El código vive en la base y es consultable:

```sql
SELECT OBJECT_DEFINITION(OBJECT_ID('etl.usp_LoadSalesOrders'));
```

Esa consulta responde una pregunta crítica: **¿lo que está corriendo es lo que yo creo que está corriendo?** Volveremos a esto — es una de las lecciones más caras del libro.

**3 — Encapsula permisos.** Podés dar permiso de `EXECUTE` sobre el procedimiento **sin** dar permisos sobre las tablas. Se llama **encadenamiento de propiedad** (*ownership chaining*), y es el mismo principio que exponer un método público sobre campos privados.

**4 — Se compila una vez y reutiliza el plan.** Menor sobrecarga que enviar el texto de la consulta cada vez.

**5 — Es un contrato estable.** El orquestador conoce un nombre y unos parámetros. Podés reescribir todo el interior sin tocar nada más.

> **⚠️ El contrapunto honesto.** Los procedimientos almacenados tienen mala prensa en desarrollo de aplicaciones, y con razón: lógica de negocio escondida en la base, difícil de testear, de versionar y de depurar.
>
> **En ETL la evaluación se invierte.** La "lógica de negocio" ES transformación de datos, el motor de la base es la herramienta correcta para eso, y el orquestador vive en la base. Poner transformaciones SQL en C# sería mover el dato fuera del motor para procesarlo peor.
>
> Saber **por qué la misma técnica es mala en un contexto y buena en otro** es exactamente el tipo de matiz que se busca en un candidato con experiencia.

---

### 3.2 Anatomía: parámetros, variables y ámbito

```sql
CREATE OR ALTER PROCEDURE etl.usp_ValidateSalesOrders
    @BatchId UNIQUEIDENTIFIER          -- parámetro de entrada
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RowsLoaded   INT;          -- declaración: reserva el nombre
    DECLARE @BaselineRows INT;
    DECLARE @Msg          NVARCHAR(400);

    SET @RowsLoaded = @@ROWCOUNT;       -- asignación: le da valor
END;
```

**Parámetros** — la entrada del procedimiento. Pueden ser `OUTPUT` para devolver valores, tener valores por defecto, y —muy importante— **son la defensa natural contra inyección SQL**, porque el valor nunca se concatena al texto de la consulta.

**Variables** — almacenamiento local, ámbito del lote de ejecución.

> **⚠️ Declaración vs asignación: la distinción que causa el bug más sutil de este módulo.**
>
> `DECLARE` **reserva el nombre**. Se puede poner en cualquier lugar antes del uso.
> La **asignación ocurre exactamente donde está escrita**, en orden secuencial.
>
> Combinar ambas en la misma línea parece prolijo y es una trampa:
>
> ```sql
> -- ❌ MAL: parece ordenado, agrupado con los demás DECLARE
> DECLARE @RowsLoaded INT;
> DECLARE @BaselineRows INT;
> DECLARE @Msg NVARCHAR(400) = CONCAT(
>     N'Se cargaron ', @RowsLoaded, N' filas contra ', @BaselineRows);
> -- ↑ Se evalúa AHORA. @RowsLoaded y @BaselineRows valen NULL.
> --   Además CONCAT trata NULL como cadena vacía, así que NO da error:
> --   simplemente produce un mensaje incompleto. Silencioso.
>
> -- ✅ BIEN: declarar arriba, asignar donde los datos ya existen
> DECLARE @Msg NVARCHAR(400);
> ...
> SET @RowsLoaded = @@ROWCOUNT;
> ...
> SET @Msg = CONCAT(N'Se cargaron ', @RowsLoaded, N' filas contra ', @BaselineRows);
> ```
>
> **La regla:** agrupá los `DECLARE` arriba para que se lean bien, pero **asigná donde los datos existen.**

**`@@ROWCOUNT` — la variable de sistema más traicionera de T-SQL.**

Contiene las filas afectadas por **la sentencia inmediatamente anterior**. Cualquier sentencia intermedia la pisa — incluso un `SELECT` de diagnóstico, incluso un `IF`.

```sql
INSERT INTO Sales.Orders (...) SELECT ... FROM ...;
SET @RowsLoaded = @@ROWCOUNT;   -- ✅ pegado al INSERT

-- ❌ Cualquier cosa en el medio la destruye:
INSERT INTO Sales.Orders (...) SELECT ... FROM ...;
IF @Debug = 1 SELECT 'cargado';   -- ← esto pisa @@ROWCOUNT
SET @RowsLoaded = @@ROWCOUNT;     -- ahora vale 1, no 73595
```

> **✅ Regla:** capturá `@@ROWCOUNT` en la **línea siguiente** a la sentencia que te interesa. Sin excepciones.

---

### 3.3 `SET NOCOUNT ON` y `SET XACT_ABORT ON`

Dos líneas al principio de todo procedimiento de ETL. No son ceremonia.

**`SET NOCOUNT ON`**

Suprime los mensajes "(73595 rows affected)".

- **Rendimiento:** cada mensaje es un paquete de red. En un procedimiento con muchas sentencias en bucle, la diferencia es medible.
- **Compatibilidad:** algunos clientes y drivers interpretan ese mensaje como un conjunto de resultados y se confunden.
- **Limpieza:** el historial del job queda legible.

**`SET XACT_ABORT ON`** — esta es la importante, y merece detenerse.

Por defecto, SQL Server tiene un comportamiento que sorprende a casi todo el mundo: **ante muchos errores en tiempo de ejecución, aborta la sentencia pero deja la transacción abierta y continúa con la siguiente.**

```sql
-- Con XACT_ABORT OFF (por defecto)
BEGIN TRANSACTION;
    INSERT INTO A VALUES (1);      -- ✅ ok
    INSERT INTO B VALUES ('mal');  -- ❌ error de conversión
    INSERT INTO C VALUES (3);      -- ⚠️ ¡ESTO SE EJECUTA IGUAL!
COMMIT;                            -- ⚠️ ¡Y CONFIRMA A y C!
```

Resultado: una transacción **parcialmente aplicada**. Exactamente lo que las transacciones existen para evitar.

Con `SET XACT_ABORT ON`, cualquier error en tiempo de ejecución **aborta el lote entero y revierte la transacción automáticamente**. Es el comportamiento que esperabas desde el principio.

> **✅ Regla profesional:** *todo procedimiento con transacciones lleva `SET XACT_ABORT ON`.* Sin excepciones. Es tan importante que muchos equipos lo exigen en la revisión de código.

**El efecto secundario que hay que conocer:** con `XACT_ABORT ON`, después de un error la transacción queda **condenada** (*doomed*): no acepta ninguna escritura hasta que se haga `ROLLBACK`. Esto determina el orden obligatorio dentro del `CATCH` — lo vemos en 3.11.

---

### 3.4 `INSERT`, `UPDATE`, `DELETE` en contexto ETL

**`INSERT` — siempre con lista explícita de columnas.**

```sql
-- ✅ Explícito
INSERT INTO Sales.Orders (OrderID, CustomerID, ..., LoadBatchId)
SELECT OrderID, CustomerID, ..., @BatchId
FROM WideWorldImporters.Sales.Orders;

-- ❌ Implícito
INSERT INTO Sales.Orders SELECT * FROM WideWorldImporters.Sales.Orders;
```

**Por qué la lista explícita no es opcional:**

1. Si el origen agrega una columna, la versión explícita **sigue funcionando**; la implícita se rompe.
2. Si el origen **reordena** columnas del mismo tipo, la implícita **carga datos en la columna equivocada, sin error.** Fallo silencioso de manual.
3. Sin lista explícita no podés agregar `@BatchId`, que no viene del origen.
4. Documenta el mapeo: se ve de un vistazo qué va a dónde.

**Nota sobre el orden:** en el `INSERT` el orden lo determina la lista de columnas, no la tabla. Pero mantener el mismo orden entre la lista y el `SELECT` hace que un desalineamiento sea visible a simple vista. Es higiene visual con consecuencias reales.

**`UPDATE` en ETL.** Aparece en dos lugares legítimos: actualizar el estado en la tabla de control, y aplicar SCD Tipo 1 en dimensiones (Módulo 8). **No** aparece para "arreglar" datos en staging — corregir en bronce viola la fidelidad al origen. Las correcciones van en la transformación.

**`DELETE` en ETL.** Para recargas por rango en cargas incrementales, y para purgar historial viejo de logs.

---

### 3.5 `MERGE`

> ➕ **Tema adicional recomendado:** `MERGE`
> **Por qué necesito aprenderlo:** aparece en toda entrevista de ETL y en la mayoría de los tutoriales de dimensiones; hay que saber usarlo **y** saber por qué mucha gente con experiencia lo evita.
> **En qué parte del proyecto lo utilizaremos:** en la carga de dimensiones (Módulo 8), donde plantearemos la alternativa.

`MERGE` combina `INSERT`, `UPDATE` y `DELETE` en una sentencia, según si la fila existe en el destino:

```sql
MERGE dw.DimCustomer AS destino
USING stg.Customers   AS origen
    ON destino.CustomerID = origen.CustomerID
WHEN MATCHED AND (destino.CustomerName <> origen.CustomerName) THEN
    UPDATE SET destino.CustomerName = origen.CustomerName,
               destino.UpdatedAt    = SYSUTCDATETIME()
WHEN NOT MATCHED BY TARGET THEN
    INSERT (CustomerID, CustomerName) VALUES (origen.CustomerID, origen.CustomerName)
WHEN NOT MATCHED BY SOURCE THEN
    UPDATE SET destino.IsActive = 0;   -- baja lógica
```

**Lo que tiene a favor:** una sola pasada por los datos, expresa la intención completa, es idempotente por naturaleza.

**Lo que tiene en contra — y hay que saberlo:**

1. **Historial de bugs.** `MERGE` en SQL Server ha tenido defectos documentados, algunos serios (violaciones de clave única con concurrencia, resultados incorrectos con índices filtrados). Varios se corrigieron; la reputación quedó.
2. **Bloqueos.** Toma bloqueos más amplios que las operaciones separadas, y en tablas grandes puede causar contención.
3. **Difícil de depurar.** Cuando algo sale mal, aislar cuál de las tres ramas falló es incómodo.
4. **Requiere que el origen sea único por la clave del `ON`.** Si hay duplicados, `MERGE` puede fallar o comportarse de forma inesperada.

**La alternativa habitual:** `UPDATE` seguido de `INSERT ... WHERE NOT EXISTS`. Más verboso, más predecible, más fácil de depurar y optimizar por separado.

> **🎓 Respuesta de entrevista que suele impresionar:** *"Uso `MERGE` cuando la lógica es genuinamente de tres ramas y el volumen es moderado. Para cargas grandes o críticas prefiero `UPDATE` + `INSERT` separados: son más fáciles de depurar, de optimizar individualmente, y evitan el historial de problemas de `MERGE` bajo concurrencia."*

---

### 3.6 Transacciones y ACID

Una **transacción** es una unidad de trabajo que se aplica **entera o nada**.

**ACID**, con lo que significa cada letra en la práctica:

- **Atomicidad** — todo o nada. Sin estados intermedios visibles.
- **Consistencia** — al terminar, todas las reglas (constraints, FKs) se cumplen.
- **Aislamiento** — las transacciones concurrentes no se pisan. El grado lo define el **nivel de aislamiento**.
- **Durabilidad** — lo confirmado sobrevive a un corte de energía. Se logra escribiendo el log **antes** que los datos (*write-ahead logging*).

**El problema concreto de nuestro proyecto:**

```sql
TRUNCATE TABLE Sales.Orders;        -- ← 73.595 filas desaparecen
INSERT INTO Sales.Orders (...) ...  -- ← ¿y si esto falla?
```

Sin transacción, el `TRUNCATE` se confirma solo. Si el `INSERT` falla —se cayó la red al origen, se llenó el disco, hubo un interbloqueo— **te quedás con la tabla vacía**. El dashboard de la mañana no muestra números viejos: no muestra nada.

Con transacción:

```sql
BEGIN TRANSACTION;
    TRUNCATE TABLE Sales.Orders;
    INSERT INTO Sales.Orders (...) SELECT ... FROM WideWorldImporters.Sales.Orders;
COMMIT TRANSACTION;
```

Si el `INSERT` falla, el `ROLLBACK` deshace **también el `TRUNCATE`**, y sobreviven los datos de ayer.

> **✅ Principio de BI que conviene interiorizar:** *casi siempre es preferible mostrar los datos completos de ayer que ningún dato hoy.* Una tabla vacía se ve como "no hubo ventas", que es una respuesta **incorrecta**. Datos de ayer con una marca de frescura visible es una respuesta **honesta**.

**Qué envolver y qué no:**

```
FUERA de la transacción  →  INSERT del registro de inicio en etl.LoadBatch
                            (si estuviera adentro, el ROLLBACK lo borraría
                             y las corridas fallidas no dejarían rastro)

DENTRO                   →  TRUNCATE + INSERT
                            (la operación que debe ser atómica)

DENTRO                   →  la validación de volumen
                            (para que su fallo dispare el ROLLBACK)

FUERA, después del COMMIT →  las validaciones de calidad
                            (observan datos ya confirmados; mantenerlas
                             afuera evita sostener bloqueos)
```

**Regla general:** una transacción debe ser **lo más corta posible**. Todo lo que esté adentro mantiene bloqueos, y los bloqueos son contención.

---

### 3.7 `TRY` / `CATCH` y `@@TRANCOUNT`

```sql
BEGIN TRY
    BEGIN TRANSACTION;
        -- trabajo
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    -- registrar
    THROW;
END CATCH
```

**`@@TRANCOUNT`** — cantidad de transacciones activas anidadas.

**Por qué se pregunta `IF @@TRANCOUNT > 0`:** porque el error pudo ocurrir **antes** del `BEGIN TRANSACTION`, o `XACT_ABORT` pudo revertirla ya. En cualquiera de esos casos, un `ROLLBACK` sin transacción activa lanza su propio error — que **enmascara el error original**. Y perder el error original es perder el diagnóstico.

**Funciones disponibles dentro del `CATCH`:**

| Función | Qué devuelve |
|---|---|
| `ERROR_NUMBER()` | Número del error |
| `ERROR_MESSAGE()` | Texto del error |
| `ERROR_SEVERITY()` | Severidad (16 = error de usuario) |
| `ERROR_STATE()` | Estado |
| `ERROR_LINE()` | Línea donde ocurrió |
| `ERROR_PROCEDURE()` | Procedimiento donde ocurrió |

> **⚠️ Estas funciones solo valen dentro del `CATCH`.** Fuera devuelven `NULL`. Y **cualquier error nuevo dentro del `CATCH` las reemplaza** — por eso el orden del bloque importa tanto.

---

### 3.8 `THROW` vs `RAISERROR`

**`THROW`** (SQL Server 2012+) — el moderno. Sin argumentos, **relanza el error original completo**: número, mensaje, severidad y línea.

```sql
THROW;                                  -- relanzar tal cual
THROW 50001, N'Mensaje personalizado', 1;  -- lanzar uno nuevo
```

**`RAISERROR`** (heredado) — más flexible en formato, pero **no puede relanzar preservando el número original**: los errores generados con `RAISERROR` siempre salen con número 50000, y hay que armar el mensaje a mano.

**Usá `THROW`.** `RAISERROR` solo si necesitás su formato de plantilla o compatibilidad con versiones muy viejas.

**Por qué el `THROW` final es imprescindible:**

```sql
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    UPDATE etl.LoadBatch SET Status = N'Failed' ... ;
    THROW;   -- ← SIN ESTO, EL PROCEDIMIENTO TERMINA "BIEN"
END CATCH
```

Sin `THROW`, el `CATCH` **maneja** el error y el procedimiento retorna normalmente. SQL Server Agent ve un procedimiento exitoso y **marca el job en verde**. Nadie recibe alerta. `etl.LoadBatch` dice `Failed` y el job dice `Succeeded`.

> **⚠️ Este es el fallo silencioso número uno de los pipelines caseros.** El error se registró correctamente, y nadie se enteró. Es peor que no tener manejo de errores, porque genera **confianza injustificada**.

#### 🔥 La trampa del `%` en `THROW`

Esto merece su propia sección porque cuesta horas descubrirlo.

```sql
-- ❌ El mensaje llega VACÍO
SET @Msg = N'Caída de volumen: 45.000 filas contra 73.000 (umbral 80%). Revertido.';
THROW 50001, @Msg, 1;
```

**Un `%` literal en el mensaje de `THROW` blanquea el mensaje entero.** No lo trunca en el `%`: **`ERROR_MESSAGE()` devuelve cadena vacía**, cero caracteres.

Y lo verdaderamente cruel: **`ERROR_NUMBER()` sigue devolviendo 50001 correctamente.** Así que ves que el error se lanzó, ves el número correcto, y el mensaje está en blanco. Todo apunta a un problema de la tabla de log, de la longitud de la columna, o de la transacción. Nada apunta al `%`.

La causa es que `%` es el carácter de formato heredado de `RAISERROR` (`%d`, `%s`), y el motor intenta interpretarlo.

**Las dos soluciones:**

```sql
-- Si el texto es literal: duplicar el %
SET @Msg = N'... (umbral 80%%). Revertido.';

-- Si el texto viene de datos (nombres, comentarios): escapar programáticamente
SET @Msg = REPLACE(@MsgCrudo, N'%', N'%%');
THROW 50001, @Msg, 1;
```

> **✅ Regla:** *cualquier mensaje de `THROW` construido a partir de datos debe pasar por `REPLACE(..., N'%', N'%%')`.* Un nombre de cliente con `%` blanquearía tu alerta, y la descubrirías el día que la necesites.

---

### 3.9 Errores que `TRY/CATCH` NO atrapa

> ➕ **Tema adicional recomendado:** límites de `TRY/CATCH`
> **Por qué necesito aprenderlo:** creer que `TRY/CATCH` atrapa todo produce pipelines con puntos ciegos.
> **En qué parte del proyecto lo utilizaremos:** al diseñar el manejo de errores y al decidir qué debe vigilar el orquestador.

`TRY/CATCH` **no** atrapa:

| Caso | Por qué | Qué hacer |
|---|---|---|
| **Errores de compilación** | El lote no llega a ejecutarse | Nombres correctos; probar el despliegue |
| **Resolución de nombres diferida** | La tabla no existe al ejecutar | `TRY/CATCH` en el lote **llamador** |
| **Severidad ≥ 20** | Cierran la conexión | Monitoreo externo; alertas de SQL Server |
| **Interrupción del cliente** | Se cortó la conexión | Vigilar transacciones abiertas |
| **Timeout de la aplicación** | El cliente abandona; el servidor sigue | `SET LOCK_TIMEOUT`; monitoreo |
| **Interbloqueo como víctima** | *(Sí lo atrapa — error 1205)* | Reintentar; es el caso clásico de reintento |

**La consecuencia práctica:** el manejo de errores no puede depender **solo** de `TRY/CATCH`. Hacen falta dos capas más:

1. **La tabla de control** (`etl.LoadBatch`) — si una fila queda en `Running` para siempre, algo murió sin pasar por el `CATCH`. **Un registro huérfano en `Running` es una señal, no un bug.**
2. **El orquestador** — Agent detecta que el job falló aunque el procedimiento no haya podido registrar nada.

---

### 3.10 La tabla de control: `etl.LoadBatch`

> **💡 Concepto clave — tabla de control (*control table*) o framework de auditoría de ETL.** Una tabla que registra **cada ejecución** del proceso: cuándo empezó, cuándo terminó, con qué resultado, cuántas filas y qué error si falló.

Es la diferencia entre "el pipeline anda" y "el pipeline anda, y puedo demostrarlo".

```sql
CREATE TABLE etl.LoadBatch (
    LoadBatchId  UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    SchemaName   NVARCHAR(128)    NOT NULL,
    TableName    NVARCHAR(128)    NOT NULL,
    StartedAt    DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    EndedAt      DATETIME2        NULL,
    Status       NVARCHAR(20)     NOT NULL
        CONSTRAINT CK_LoadBatch_Status CHECK (Status IN (N'Running', N'Succeeded', N'Failed')),
    RowsLoaded   INT              NULL,
    ErrorNumber  INT              NULL,
    ErrorMessage NVARCHAR(4000)   NULL
);
```

**Cada decisión de diseño, justificada:**

**`LoadBatchId` como PK** — es el mismo GUID que va en las filas de datos. Une el registro de ejecución con las filas que produjo. Eso es **linaje**.

**`SchemaName` + `TableName`** — la tabla sirve a **todo** el pipeline, no solo a `Sales.Orders`. Cuando agregues `OrderLines` y las dimensiones, todas registran acá, y podés filtrar por tabla.

> **⚠️ Error real y particularmente traicionero:** olvidar `SchemaName` en el `INSERT` de una validación. La columna es `NOT NULL`, así que **falla**... pero solo el día en que **una validación efectivamente encuentre algo**. Si tus datos están limpios, el `INSERT` nunca se ejecuta y el bug duerme durante meses. Aparece justo cuando hay un problema de datos que investigar — es decir, en el peor momento posible.
>
> Es el arquetipo del **camino de error no probado**, y es el tema recurrente de todo este libro.

**`EndedAt DATETIME2 NULL`, sin `DEFAULT`.**

```sql
-- ❌ MAL
EndedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME()
```

Ese `DEFAULT` **destruye el propósito de la columna**. `EndedAt` debe ser NULL mientras la carga corre; ese NULL es lo que hace que esta consulta sirva:

```sql
-- Cargas colgadas o muertas sin pasar por el CATCH
SELECT * FROM etl.LoadBatch
WHERE Status = N'Running'
  AND StartedAt < DATEADD(HOUR, -2, SYSUTCDATETIME());
```

Con el `DEFAULT`, `EndedAt` se llena al insertar el registro de inicio y **esa consulta no encuentra nunca nada**. Perdés justamente la capacidad de detectar procesos muertos.

**`Status` con `CHECK`** — un dominio cerrado. Sin él, aparecen `'OK'`, `'Ok'`, `'SUCCESS'` y `'Succeded'` con el correr de los meses, y ninguna consulta de monitoreo funciona.

**`ErrorNumber` + `ErrorMessage`** — el diagnóstico queda en la base, no solo en el correo. `NVARCHAR(4000)` porque los mensajes de error pueden ser largos.

---

### 3.11 Por qué el registro va fuera de la transacción

```sql
-- 1️⃣ FUERA: registrar el inicio
INSERT INTO etl.LoadBatch (LoadBatchId, SchemaName, TableName, Status)
VALUES (@BatchId, N'Sales', N'Orders', N'Running');

BEGIN TRY
    -- 2️⃣ DENTRO: el trabajo
    BEGIN TRANSACTION;
        TRUNCATE TABLE Sales.Orders;
        INSERT INTO Sales.Orders (...) SELECT ..., @BatchId FROM ...;
        SET @RowsLoaded = @@ROWCOUNT;
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    -- 3️⃣ Orden obligatorio
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

    UPDATE etl.LoadBatch
    SET EndedAt = SYSUTCDATETIME(), Status = N'Failed',
        ErrorNumber = ERROR_NUMBER(), ErrorMessage = ERROR_MESSAGE()
    WHERE LoadBatchId = @BatchId;

    THROW;
END CATCH

-- 4️⃣ FUERA: registrar el éxito
UPDATE etl.LoadBatch
SET EndedAt = SYSUTCDATETIME(), Status = N'Succeeded', RowsLoaded = @RowsLoaded
WHERE LoadBatchId = @BatchId;
```

**Por qué el registro de inicio va afuera:** si estuviera dentro, el `ROLLBACK` **lo borraría**. Las corridas fallidas no dejarían rastro, y tu tabla de auditoría solo tendría éxitos. Una tabla de auditoría que solo registra éxitos no es una tabla de auditoría.

**Por qué el orden dentro del `CATCH` es obligatorio — primero `ROLLBACK`, después registrar, al final `THROW`:**

1. Con `XACT_ABORT ON`, la transacción queda **condenada**. Cualquier escritura antes del `ROLLBACK` **falla**, y esa falla enmascara el error original.
2. Aunque no estuviera condenada, el `ROLLBACK` **borraría** el registro que acabás de escribir.
3. `THROW` va al final porque interrumpe la ejecución: nada después se ejecuta.

> **✅ Memorizá la secuencia: deshacer → registrar → relanzar.** Es contraintuitiva (uno querría registrar primero, mientras el error está "fresco") y es la única correcta.

---

### 3.12 Separar carga de validación

Este es un punto de **diseño de software**, no de SQL, y es de los más valiosos del módulo.

Se podría poner todo en un procedimiento. Lo separamos:

```sql
etl.usp_LoadSalesOrders       -- extrae y carga
etl.usp_ValidateSalesOrders   -- valida (recibe @BatchId)
```

Y el de carga llama al de validación al final:

```sql
EXEC etl.usp_ValidateSalesOrders @BatchId;
```

**Los cuatro motivos:**

**1 — Responsabilidad única.** Cargar y evaluar calidad son trabajos distintos. Si mañana agregás cinco validaciones, tocás un solo procedimiento.

**2 — Reutilización.** Podés validar sin recargar. Útil para investigar un problema sobre los datos que ya están.

**3 — Se puede probar sola.** Y este es el motivo decisivo:

```sql
-- Ensuciar UNA fila a propósito
UPDATE TOP (1) Sales.Orders SET CustomerID = NULL;

-- Ejecutar SOLO el validador, con un lote ficticio de prueba
EXEC etl.usp_ValidateSalesOrders '00000000-0000-0000-0000-000000000001';

-- Verificar que detectó
SELECT * FROM etl.ValidationLog
WHERE LoadBatchId = '00000000-0000-0000-0000-000000000001';
```

**Si la validación viviera dentro del procedimiento de carga, no podrías hacer esto sin recargar** — y la recarga **borra el dato sucio** que acabás de crear. Tendrías que ensuciar *después* de cargar y *antes* de validar, es decir, meter código de prueba dentro del procedimiento de producción.

> **⚠️ Lección de ingeniería que trasciende el SQL: el andamiaje de prueba no puede vivir dentro del código que prueba.**
>
> Poner el `UPDATE` que ensucia datos dentro del procedimiento de carga es tentador —"solo mientras pruebo"— y es un error grave. El día que se olvide ahí, tu ETL de producción corrompe una fila en cada corrida.
>
> **La separación de procedimientos es lo que hace innecesario ese andamiaje.** Es exactamente el mismo razonamiento por el que inyectás dependencias en lugar de instanciarlas: no lo hacés por elegancia, lo hacés para poder sustituirlas en una prueba.

**4 — Los bloqueos duran menos.** La validación corre fuera de la transacción, sobre datos ya confirmados.

#### La lección más cara: verificar qué está desplegado

```sql
SELECT OBJECT_DEFINITION(OBJECT_ID('etl.usp_LoadSalesOrders')) AS Codigo;

SELECT name, create_date, modify_date
FROM sys.procedures
WHERE name LIKE 'usp_%';
```

**Por qué importa tanto:** es perfectamente posible probar una versión del código y tener desplegada otra. Pasa cuando ejecutás el cuerpo del procedimiento suelto en una ventana de consulta para probarlo, y creés que probaste el procedimiento.

**No probaste el procedimiento. Probaste una copia del texto.** Si el procedimiento desplegado tiene un typo —digamos `'CustomerId_NUll'` en lugar de `'CustomerID_NULL'`— tu prueba pasa y producción falla.

**Señal de alarma concreta:** si `create_date = modify_date`, el procedimiento **nunca se modificó desde que se creó**. Si vos creés que lo editaste tres veces, lo que estás mirando no es lo que editaste.

> **✅ Práctica que vale para toda tu carrera:** *después de desplegar, verificá contra el objeto desplegado, no contra tu editor.* Y probá ejecutando el objeto real, nunca su texto copiado.

---

### 3.13 Qué hacer cuando una carga falla

Las cuatro estrategias, y cuándo corresponde cada una:

| Estrategia | Comportamiento | Cuándo |
|---|---|---|
| **Fail fast** | Aborta todo al primer error | Errores estructurales; datos críticos |
| **Log and continue** | Registra y sigue | Problemas de calidad en filas individuales |
| **Retry** | Reintenta N veces | Errores **transitorios** |
| **Circuit breaker** | Tras N fallos, deja de intentar | Origen caído; evita ruido |

**Lo que hacemos, que es una combinación deliberada:**

- **Fail fast** para errores estructurales y caídas de volumen → transacción, `ROLLBACK`, `THROW`, alerta.
- **Log and continue** para problemas de calidad de filas → validaciones que registran en `etl.ValidationLog` sin abortar.
- **Retry** para transitorios → un reintento configurado en el job (Módulo 5).

**El criterio para reintentar, que es una pregunta clásica de entrevista:**

> ✅ **Se reintenta** lo **transitorio**: interbloqueo (error 1205), timeout, red intermitente, recurso ocupado momentáneamente.
>
> ❌ **No se reintenta** lo **determinístico**: violación de constraint, error de conversión, tabla inexistente, permiso denegado. Va a fallar exactamente igual las diez veces, y cada intento retrasa la alerta.

Reintentar un error determinístico no solo es inútil: **es dañino**, porque convierte un fallo inmediato en un fallo tardío.

---

### 3.14 `CREATE OR ALTER` y la base como código

> ➕ **Tema adicional recomendado:** base de datos como código
> **Por qué necesito aprenderlo:** el SQL de un pipeline es código de producción y merece el mismo rigor que el resto.
> **En qué parte del proyecto lo utilizaremos:** en todos los scripts, desde el primero.

**`CREATE OR ALTER PROCEDURE`** (SQL Server 2016 SP1+) — crea si no existe, reemplaza si existe. Hace el script **idempotente**, igual que la carga.

Antes había que escribir:

```sql
IF OBJECT_ID('etl.usp_LoadSalesOrders') IS NOT NULL
    DROP PROCEDURE etl.usp_LoadSalesOrders;
GO
CREATE PROCEDURE etl.usp_LoadSalesOrders AS ...
```

Y `DROP` + `CREATE` **pierde los permisos otorgados sobre el objeto**. `CREATE OR ALTER` los conserva. No es un detalle menor en un entorno con roles configurados.

**`GO` — lo que hay que entender:** no es T-SQL. Es un **separador de lotes** que interpreta el cliente (SSMS, `sqlcmd`). El servidor nunca lo ve.

Y hay reglas que lo hacen obligatorio:

- `CREATE PROCEDURE`, `CREATE VIEW`, `CREATE FUNCTION`, `CREATE TRIGGER` y `CREATE SCHEMA` **deben ser la primera sentencia de su lote**.
- Por lo tanto: **dos `CREATE PROCEDURE` seguidos sin `GO` en el medio es un error de sintaxis**, y el mensaje que da SQL Server no es nada claro sobre la causa.
- Dos `CREATE SCHEMA` seguidos, lo mismo.

**Organización de los scripts — numerados por dependencia:**

```
staging/
  01_database.sql                    -- CREATE DATABASE + RECOVERY SIMPLE
  02_schemas.sql                     -- CREATE SCHEMA Sales / etl  (¡con GO!)
  03_tables.sql                      -- tablas
  04_usp_ValidateSalesOrders.sql     -- validación
  05_usp_LoadSalesOrders.sql         -- carga (llama a la anterior)
automation/
  01_job_load_sales_orders.sql
  03_job_notifications.sql
tests/
  negative_tests.sql
```

**El número indica el orden de ejecución, que está determinado por las dependencias.** La validación es `04` y la carga `05` porque la carga la invoca. Ese detalle —numerar por dependencia, no por importancia— es lo que hace que el conjunto se pueda desplegar desde cero en un entorno nuevo.

> **✅ La regla de trabajo más importante de todo el proyecto:**
>
> **Editá el archivo, después ejecutalo. Nunca modifiques la base directamente.**
>
> Si "arreglás algo rápido" en SSMS sin tocar el archivo, la base y el repositorio divergen. La próxima persona que despliegue desde el repo —o vos, en otra máquina— reintroduce el bug. Es exactamente la razón por la que no editás archivos directamente en un servidor de producción.

> **💡 Herramientas del ecosistema:** SSDT (proyectos de base de datos en Visual Studio, con comparación de esquemas), y **Flyway**, **Liquibase** o **DbUp** para migraciones versionadas. Vale conocerlas por nombre: son el equivalente de Entity Framework Migrations para bases que no nacen de un ORM.

---

## 💻 El procedimiento completo

```sql
USE WWI_Staging;
GO

CREATE OR ALTER PROCEDURE etl.usp_LoadSalesOrders
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @BatchId      UNIQUEIDENTIFIER = NEWID();
    DECLARE @RowsLoaded   INT;
    DECLARE @BaselineRows INT;
    DECLARE @Msg          NVARCHAR(400);

    /* Registro de inicio FUERA de la transacción: adentro, el ROLLBACK
       lo borraría y las corridas fallidas no dejarían rastro.
       StartedAt lo completa su DEFAULT. */
    INSERT INTO etl.LoadBatch (LoadBatchId, SchemaName, TableName, Status)
    VALUES (@BatchId, N'Sales', N'Orders', N'Running');

    BEGIN TRY
        BEGIN TRANSACTION;

        TRUNCATE TABLE Sales.Orders;

        INSERT INTO Sales.Orders (
            OrderID, CustomerID, SalespersonPersonID, PickedByPersonID,
            ContactPersonID, BackorderOrderID, OrderDate, ExpectedDeliveryDate,
            CustomerPurchaseOrderNumber, IsUndersupplyBackordered, Comments,
            DeliveryInstructions, InternalComments, PickingCompletedWhen,
            LastEditedBy, LastEditedWhen, LoadBatchId
        )
        SELECT
            OrderID, CustomerID, SalespersonPersonID, PickedByPersonID,
            ContactPersonID, BackorderOrderID, OrderDate, ExpectedDeliveryDate,
            CustomerPurchaseOrderNumber, IsUndersupplyBackordered, Comments,
            DeliveryInstructions, InternalComments, PickingCompletedWhen,
            LastEditedBy, LastEditedWhen, @BatchId
        FROM WideWorldImporters.Sales.Orders;   -- 3 partes: cruza de base

        SET @RowsLoaded = @@ROWCOUNT;   -- pegado al INSERT

        /* Validación de volumen DENTRO de la transacción, para que su
           fallo dispare el ROLLBACK y sobrevivan los datos de ayer. */
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
            SET @Msg = CONCAT(
                N'Caida de volumen en Sales.Orders: se cargaron ', @RowsLoaded,
                N' filas contra una linea base de ', @BaselineRows,
                N' (umbral 80%%). Carga revertida.');   -- ⚠️ %% obligatorio
            THROW 50001, @Msg, 1;
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        /* Orden obligatorio: deshacer → registrar → relanzar. */
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        UPDATE etl.LoadBatch
        SET EndedAt      = SYSUTCDATETIME(),
            Status       = N'Failed',
            ErrorNumber  = ERROR_NUMBER(),
            ErrorMessage = ERROR_MESSAGE()
        WHERE LoadBatchId = @BatchId;

        /* Sin THROW el procedimiento retornaría con éxito y Agent
           marcaría el job en verde tras una carga fallida. */
        THROW;
    END CATCH

    UPDATE etl.LoadBatch
    SET EndedAt    = SYSUTCDATETIME(),
        Status     = N'Succeeded',
        RowsLoaded = @RowsLoaded
    WHERE LoadBatchId = @BatchId;

    /* Validaciones de calidad DESPUÉS del COMMIT: observan datos
       confirmados y no sostienen bloqueos sobre la tabla. */
    EXEC etl.usp_ValidateSalesOrders @BatchId;
END;
GO
```

---

## 💡 Conceptos clave

- **Stored Procedure** — código T-SQL con nombre, parámetros y permisos, guardado en la base.
- **`SET XACT_ABORT ON`** — cualquier error revierte la transacción automáticamente.
- **Transacción condenada (*doomed*)** — tras un error con `XACT_ABORT ON`, no acepta escrituras hasta el `ROLLBACK`.
- **ACID** — atomicidad, consistencia, aislamiento, durabilidad.
- **`@@TRANCOUNT`** — transacciones activas; se consulta antes del `ROLLBACK`.
- **`THROW`** — lanza o relanza preservando el error original.
- **Tabla de control** — registro de cada ejecución del pipeline.
- **Fail fast / log and continue / retry / circuit breaker** — las cuatro estrategias ante fallos.
- **Error transitorio vs determinístico** — el criterio para decidir si reintentar.
- **`CREATE OR ALTER`** — despliegue idempotente que conserva permisos.

---

## ⚠️ Errores comunes

**Olvidar el `THROW` final.** El job queda en verde tras una carga fallida. El peor error del módulo.

**Un `%` literal en el mensaje de `THROW`.** Blanquea el mensaje entero mientras el número se conserva. Horas de diagnóstico.

**Registrar antes del `ROLLBACK`.** La transacción condenada rechaza la escritura y ese error tapa el original.

**`DEFAULT` en `EndedAt`.** Destruye la detección de procesos colgados.

**Asignar variables en el `DECLARE` con datos que aún no existen.** `CONCAT` no falla con NULLs: produce un mensaje incompleto, en silencio.

**Capturar `@@ROWCOUNT` con sentencias en el medio.** Cualquier cosa la pisa.

**`INSERT` sin lista de columnas.** Si el origen reordena columnas del mismo tipo, los datos entran en la columna equivocada sin error.

**Andamiaje de prueba dentro del procedimiento de producción.** El día que quede olvidado, corrompe datos en cada corrida.

**Probar el texto en vez del objeto desplegado.** Verificá con `OBJECT_DEFINITION`.

**Faltar el `GO` entre dos `CREATE PROCEDURE`.** Error de sintaxis con mensaje confuso.

**Reintentar errores determinísticos.** Retrasa la alerta sin ninguna posibilidad de éxito.

---

## ✅ Buenas prácticas

1. **`SET NOCOUNT ON` + `SET XACT_ABORT ON`** al inicio de todo procedimiento de ETL.
2. **Transacciones cortas.** Solo lo que debe ser atómico.
3. **Siempre `THROW` al final del `CATCH`.**
4. **Deshacer → registrar → relanzar.** En ese orden.
5. **`CREATE OR ALTER`** para despliegues repetibles que conservan permisos.
6. **Un procedimiento, una responsabilidad.** La testabilidad lo justifica sola.
7. **Comentá el *por qué*, no el *qué*.** `-- pegado al INSERT: cualquier statement intermedio lo pisa` vale; `-- captura el rowcount` no.
8. **Verificá lo desplegado con `OBJECT_DEFINITION`** después de cada cambio.
9. **Nombrá los constraints** para poder modificarlos en scripts.
10. **Editá el archivo, después ejecutalo.** Nunca al revés.

---

## 🧠 Preguntas de comprensión

1. ¿Qué pasa exactamente si sacás el `THROW` del `CATCH`? Describí el estado de `etl.LoadBatch` y del job de Agent.
2. ¿Por qué el `INSERT` de inicio va fuera de la transacción, y qué perderías si estuviera adentro?
3. `ERROR_NUMBER()` devuelve 50001 y `ERROR_MESSAGE()` devuelve cadena vacía. ¿Cuál es la causa más probable y cómo lo confirmás?
4. Explicá por qué separar validación de carga es una decisión de **testabilidad** y no de estilo.
5. Un compañero mueve `SET @RowsLoaded = @@ROWCOUNT;` tres líneas más abajo, después de un `SELECT` de diagnóstico. ¿Qué valor va a tener y por qué?
6. Encontrás un registro en `etl.LoadBatch` con `Status = 'Running'` de hace tres días. ¿Qué significa y qué categoría de error lo explica?

---

## 📝 Ejercicios

**🟢 Básico.** Escribí `etl.usp_LoadSalesOrders` completo, desde cero, sin copiar. Incluí los comentarios que expliquen el porqué de cada decisión.

**🟢 Básico.** Creá `etl.LoadBatch` con todos sus constraints. Verificá que el `CHECK` rechaza `'OK'` como estado.

**🟡 Intermedio.** Probá el `ROLLBACK` de verdad. Creá un trigger temporal sobre `Sales.Orders` que lance un error en el `INSERT`, ejecutá la carga, y verificá que sobrevivieron las 73.595 filas anteriores. **Después borrá el trigger** — y anotá que ese "después borrá" es exactamente el riesgo del andamiaje de prueba.

**🟡 Intermedio.** Reproducí el bug del `%`: lanzá un `THROW` con `%` literal, capturalo, y mostrá que `ERROR_NUMBER()` funciona pero `ERROR_MESSAGE()` viene vacío. Después arreglalo y verificá.

**🔴 Avanzado.** Agregá al procedimiento la capacidad de recibir un parámetro `@DryRun BIT = 0` que ejecute todo —incluidas las validaciones— pero haga `ROLLBACK` al final en vez de `COMMIT`, informando qué habría pasado. Es una técnica real para validar cambios en producción.

**🔴 Avanzado.** Escribí un procedimiento genérico `etl.usp_LoadTable @SchemaName, @TableName` que construya el `INSERT` dinámicamente desde `INFORMATION_SCHEMA`, para cualquier tabla. Cuidá la inyección SQL con `QUOTENAME()`. Después escribí un párrafo sobre **cuándo esta abstracción es mejor idea que un procedimiento por tabla, y cuándo es peor.**

**🧠 Reto.** Diseñá el manejo de errores de un pipeline con 12 tablas donde algunas son críticas (si fallan, no debe continuar) y otras opcionales (si fallan, se sigue con las demás y se avisa). Definí cómo se declara esa criticidad, cómo se propaga el estado global, y qué reporta el job al final. Tiene que soportar que dos tablas opcionales fallen y una crítica ande.

---

## 🎓 Preguntas de entrevista

1. **¿Cómo manejás errores en un ETL?** — `TRY/CATCH` + `XACT_ABORT` + tabla de control + `THROW` + el orquestador. Las cuatro capas.
2. **¿Qué es `XACT_ABORT` y por qué lo usás?** — El comportamiento por defecto puede dejar transacciones parcialmente aplicadas.
3. **¿`THROW` o `RAISERROR`?** — `THROW` es moderno y relanza preservando el error; `RAISERROR` no puede preservar el número original.
4. **¿Qué envolvés en una transacción y qué no?** — Lo que debe ser atómico adentro; auditoría y observación afuera. Transacciones cortas.
5. **¿Cómo sabés si un pipeline corrió y con qué resultado?** — Tabla de control. Y mencionar la detección de registros huérfanos en `Running`.
6. **¿Cuándo reintentar?** — Transitorio sí, determinístico no. Con ejemplos.
7. **¿`MERGE` o `UPDATE` + `INSERT`?** — Ver 3.5.
8. **¿Qué errores no atrapa `TRY/CATCH`?** — Compilación, severidad ≥ 20, desconexión. Y por eso hace falta el orquestador.
9. **¿Cómo probás el camino de error de un ETL?** — Forzándolo: triggers que fallan, datos sucios a propósito, procedimientos separados que permitan probar la validación sin recargar.

---

## 📌 Resumen

- El ETL vive en procedimientos: invocables, versionados, con permisos propios y contrato estable.
- `SET NOCOUNT ON` + `SET XACT_ABORT ON` en todos. El segundo evita transacciones a medias.
- **`DECLARE` reserva; la asignación ocurre donde está escrita.** No las mezcles con datos que aún no existen.
- Capturá `@@ROWCOUNT` en la línea siguiente. Siempre.
- Transacción alrededor de `TRUNCATE` + `INSERT`: un fallo preserva los datos de ayer.
- `CATCH`: **deshacer → registrar → relanzar**. Sin `THROW`, el job miente.
- **Un `%` literal en `THROW` blanquea el mensaje.** Escapalo con `%%` o `REPLACE`.
- `etl.LoadBatch` da observabilidad. Sin `DEFAULT` en `EndedAt`.
- Separar carga de validación es una decisión de **testabilidad**.
- **Verificá lo desplegado**, no lo que creés que desplegaste.
- Reintentar solo lo transitorio.
- **Editá el archivo, después ejecutalo.**

---

## 🗂️ Flashcards

| Pregunta | Respuesta |
|---|---|
| ¿Qué hace `SET XACT_ABORT ON`? | Cualquier error revierte la transacción automáticamente. |
| ¿Qué pasa sin él? | La transacción puede quedar parcialmente aplicada. |
| ¿Por qué `IF @@TRANCOUNT > 0` antes del `ROLLBACK`? | Un `ROLLBACK` sin transacción lanza un error que tapa el original. |
| ¿Orden dentro del `CATCH`? | ROLLBACK → registrar → THROW. |
| ¿Qué pasa si falta el `THROW`? | El procedimiento retorna con éxito y el job queda en verde. |
| ¿Qué hace un `%` literal en `THROW`? | Blanquea el mensaje entero; el número se conserva. |
| ¿Cómo se escapa? | `%%`, o `REPLACE(@Msg, N'%', N'%%')` si viene de datos. |
| ¿`THROW` vs `RAISERROR`? | `THROW` relanza preservando el error original; `RAISERROR` no. |
| ¿Por qué el registro de inicio va fuera de la transacción? | El `ROLLBACK` lo borraría y no quedaría rastro de los fallos. |
| ¿Por qué `EndedAt` sin `DEFAULT`? | El NULL es lo que permite detectar cargas colgadas. |
| ¿Por qué separar carga de validación? | Para poder probar la validación sin recargar los datos. |
| ¿Cuándo se reintenta un error? | Cuando es transitorio: interbloqueo, timeout, red. |
| ¿Cuándo NO? | Cuando es determinístico: constraint, conversión, permisos. |
| ¿Qué hace `CREATE OR ALTER`? | Crea o reemplaza conservando los permisos. |
| ¿Qué es `GO`? | Separador de lotes del cliente; el servidor no lo ve. |
| ¿Cómo verificás el código desplegado? | `OBJECT_DEFINITION(OBJECT_ID('esquema.nombre'))`. |
| ¿Qué significa `create_date = modify_date`? | Que el objeto nunca se modificó desde su creación. |
| ¿Qué errores no atrapa `TRY/CATCH`? | Compilación, severidad ≥ 20, desconexión del cliente. |

---

## ☑️ Checklist antes de avanzar

- [ ] Mi procedimiento tiene `SET NOCOUNT ON` y `SET XACT_ABORT ON`.
- [ ] El `TRUNCATE` + `INSERT` está dentro de una transacción.
- [ ] Probé el `ROLLBACK` forzando un fallo real, y quité el andamiaje.
- [ ] El `CATCH` sigue el orden deshacer → registrar → relanzar.
- [ ] Hay `THROW` al final del `CATCH`.
- [ ] `etl.LoadBatch` registra inicio, fin, estado, filas y error.
- [ ] `EndedAt` **no** tiene `DEFAULT`.
- [ ] Todos los mensajes de `THROW` tienen los `%` escapados.
- [ ] Carga y validación son procedimientos separados.
- [ ] Verifiqué con `OBJECT_DEFINITION` que lo desplegado es lo que escribí.
- [ ] Todos los scripts están en archivos versionados y numerados por dependencia.

---

## 📋 Examen del Módulo 3

### Selección múltiple

**1.** Sin `SET XACT_ABORT ON`, un error en medio de una transacción puede:
a) Revertir todo automáticamente
b) Abortar la sentencia y **continuar** con las siguientes, dejando la transacción a medias
c) Cerrar la conexión
d) Reintentar automáticamente

**2.** ¿Por qué `IF @@TRANCOUNT > 0` antes del `ROLLBACK`?
a) Por rendimiento
b) Porque un `ROLLBACK` sin transacción activa lanza un error que enmascara el original
c) Porque `ROLLBACK` no funciona dentro de `CATCH`
d) No es necesario

**3.** `ERROR_NUMBER()` da 50001 y `ERROR_MESSAGE()` da cadena vacía. La causa más probable:
a) La columna del log es muy corta
b) Un `%` literal en el mensaje del `THROW`
c) Se hizo `ROLLBACK` antes de leer el mensaje
d) `ERROR_MESSAGE()` no funciona con errores personalizados

**4.** El orden correcto dentro del `CATCH` es:
a) Registrar → ROLLBACK → THROW
b) ROLLBACK → registrar → THROW
c) THROW → ROLLBACK → registrar
d) Es indistinto

**5.** ¿Cuál NO se debe reintentar automáticamente?
a) Interbloqueo (1205)
b) Timeout de conexión
c) Violación de constraint de clave única
d) Recurso ocupado temporalmente

**6.** ¿Ventaja de `CREATE OR ALTER` sobre `DROP` + `CREATE`?
a) Es más rápido
b) Conserva los permisos otorgados sobre el objeto
c) Permite parámetros
d) No requiere `GO`

**7.** Separar carga de validación en dos procedimientos permite, sobre todo:
a) Que corran en paralelo
b) Probar la validación sin recargar los datos
c) Usar menos memoria
d) Evitar transacciones

### Verdadero / Falso

**8.** `TRY/CATCH` atrapa todos los errores de SQL Server.
**9.** Sin `THROW` en el `CATCH`, SQL Server Agent marca el job como fallido igual.
**10.** `@@ROWCOUNT` conserva su valor hasta que se lo asigne a una variable.
**11.** `DECLARE @x INT = @y + 1;` al inicio del procedimiento evalúa `@y` en ese momento.
**12.** En SQL Server, un `TRUNCATE` dentro de una transacción se puede revertir.
**13.** `GO` es una sentencia de T-SQL que el servidor ejecuta.
**14.** Un registro con `Status = 'Running'` de hace tres días indica que el proceso murió sin pasar por el `CATCH`.

### SQL

**15.** Escribí un procedimiento que cargue `Sales.OrderLines` con: transacción, `TRY/CATCH`, registro en `etl.LoadBatch` y validación de volumen. Los mensajes de error deben estar correctamente escapados.

**16.** Escribí la consulta de monitoreo que devuelva, para los últimos 7 días: cargas totales, exitosas, fallidas, duración promedio en segundos, y cargas colgadas.

### Debugging

**17.** Encontrá los **cuatro** errores:

```sql
CREATE PROCEDURE etl.usp_Cargar
AS
BEGIN
    DECLARE @BatchId UNIQUEIDENTIFIER = NEWID();
    DECLARE @Rows INT;
    DECLARE @Msg NVARCHAR(200) = CONCAT(N'Se cargaron ', @Rows, N' filas (100% del origen)');

    BEGIN TRANSACTION;
        INSERT INTO etl.LoadBatch (LoadBatchId, TableName, Status)
        VALUES (@BatchId, N'Orders', N'Running');

        TRUNCATE TABLE Sales.Orders;
        INSERT INTO Sales.Orders SELECT * FROM WideWorldImporters.Sales.Orders;
        SELECT 'Carga terminada' AS Estado;
        SET @Rows = @@ROWCOUNT;
    COMMIT TRANSACTION;
END;
```

**18.** Un procedimiento "funciona en la ventana de consulta" pero falla al ejecutarlo por su nombre. `create_date = modify_date`. Explicá qué pasó y cómo lo verificás.

### Análisis de escenario

**19.** Tu carga corre a las 2 AM. A las 8 el gerente dice que el dashboard muestra los datos de anteayer. `etl.LoadBatch` tiene un registro de anoche con `Status = 'Running'`, `EndedAt` en NULL, y el job de Agent figura como exitoso. Reconstruí qué pasó, en orden, y explicá qué defecto de diseño permite esa combinación.

### Diseño

**20.** Diseñá una extensión de `etl.LoadBatch` para soportar pipelines con **pasos múltiples** (extraer → validar → transformar → cargar dimensiones → cargar hechos), donde se pueda saber en qué paso falló y cuánto tardó cada uno. Da el DDL y explicá la relación entre las tablas.

