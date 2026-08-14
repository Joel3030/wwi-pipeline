---

# VOLUMEN II
## Modelado dimensional y la capa Oro

---

# Módulo 6 — Data Warehouse: el porqué

## 🎯 Objetivos

- Sentir el problema del modelo transaccional antes de conocer la solución.
- Definir qué es un Data Warehouse y qué lo distingue de una base de reportes.
- Explicar por qué la normalización es correcta en OLTP e inadecuada en OLAP.
- Distinguir las escuelas de Kimball e Inmon.
- Ubicar Data Warehouse, Data Mart, Data Lake y Lakehouse.
- Justificar por qué la redundancia controlada es deseable en esta capa.

---

## 📖 Teoría

### 6.1 La consulta que rompe el modelo transaccional

El negocio pide algo razonable: **"ventas por mes, por categoría de producto, por país del cliente"**.

Contra WideWorldImporters, eso requiere recorrer:

```
Sales.OrderLines                     ← acá está el dinero (Quantity × UnitPrice)
  └─ Sales.Orders                        ← la fecha y el cliente
      └─ Sales.Customers
          └─ Application.Cities
              └─ Application.StateProvinces
                  └─ Application.Countries          ← el país, al fin
  └─ Warehouse.StockItems              ← el producto
      └─ Warehouse.StockItemStockGroups    ← ⚠️ tabla puente
          └─ Warehouse.StockGroups             ← la categoría, al fin
```

**Ocho joins** para una pregunta que se formula en una frase. Y es la consulta *fácil*.

```sql
-- Lo que hay que escribir contra el OLTP
SELECT
    YEAR(o.OrderDate) AS Anio, MONTH(o.OrderDate) AS Mes,
    sg.StockGroupName AS Categoria,
    co.CountryName    AS Pais,
    SUM(ol.Quantity * ol.UnitPrice) AS Ventas
FROM Sales.OrderLines ol
JOIN Sales.Orders o                       ON o.OrderID       = ol.OrderID
JOIN Sales.Customers c                    ON c.CustomerID    = o.CustomerID
JOIN Application.Cities ci                ON ci.CityID       = c.DeliveryCityID
JOIN Application.StateProvinces sp        ON sp.StateProvinceID = ci.StateProvinceID
JOIN Application.Countries co             ON co.CountryID    = sp.CountryID
JOIN Warehouse.StockItems si              ON si.StockItemID  = ol.StockItemID
JOIN Warehouse.StockItemStockGroups sisg  ON sisg.StockItemID = si.StockItemID
JOIN Warehouse.StockGroups sg             ON sg.StockGroupID = sisg.StockGroupID
GROUP BY YEAR(o.OrderDate), MONTH(o.OrderDate), sg.StockGroupName, co.CountryName;
```

**Tres problemas, de naturaleza distinta:**

**Rendimiento.** Ocho joins sobre 231.412 líneas, cada vez que alguien mueve un filtro.

**Comprensibilidad.** Ese SQL lo escribió alguien que estudió el esquema. Un analista de negocio no puede escribirlo, y por lo tanto **no puede responder sus propias preguntas**: tiene que pedírselo a alguien de sistemas y esperar. El modelo es correcto y **inutilizable** para quien no lo diseñó.

**Y uno grave, escondido: la consulta de arriba está mal.** `Warehouse.StockItemStockGroups` tiene 442 filas para 227 productos: un producto pertenece a **varias** categorías. Cada línea se duplica una vez por categoría, y **el total de ventas sale casi al doble**.

Sin error. Sin warning. Números plausibles, categorías correctas, totales inflados. Es el **fan-out** del Módulo 1, y es cómo dos personas de la misma empresa llegan a dos cifras distintas para "las ventas del trimestre".

---

### 6.2 Qué es un Data Warehouse

La definición clásica es de **Bill Inmon**, y cada adjetivo importa:

> Un Data Warehouse es una colección de datos **orientada a temas**, **integrada**, **variante en el tiempo** y **no volátil**, que sirve de apoyo a la toma de decisiones.

- **Orientada a temas** — organizada alrededor de conceptos de negocio (ventas, clientes) y no alrededor de aplicaciones.
- **Integrada** — múltiples orígenes unificados bajo definiciones comunes. Si el CRM dice `'M'/'F'` y el ERP dice `1/2`, en el warehouse hay **una** convención.
- **Variante en el tiempo** — guarda historia. El OLTP guarda el estado actual; el warehouse guarda **cómo llegamos acá**.
- **No volátil** — no se actualiza transaccionalmente. Se carga y se lee. Un hecho registrado no cambia.

**Lo que NO es un Data Warehouse:**

| ❌ | Por qué |
|---|---|
| Una copia del OLTP | Sin remodelar, arrastra los ocho joins y la falta de historia |
| Una base de reportes | Un warehouse tiene modelo dimensional; una base de reportes puede ser cualquier cosa |
| Un montón de tablas de resumen | Los agregados son una optimización, no un modelo |
| Un Data Lake | Un lake almacena archivos crudos sin esquema impuesto |

---

### 6.3 Por qué el OLTP está bien hecho

Vale insistir porque es contraintuitivo: **el modelo de WideWorldImporters no tiene ningún defecto.**

Está **normalizado**, típicamente hasta tercera forma normal (3FN):

- **1FN** — valores atómicos, sin grupos repetidos.
- **2FN** — todos los atributos dependen de la clave completa.
- **3FN** — ningún atributo depende de otro no clave.

**Qué gana con eso:**

1. **Sin anomalías de actualización.** El nombre de un país está en **una** fila. Cambia una vez, cambia en todos lados.
2. **Sin anomalías de inserción.** Se puede crear un país sin tener clientes ahí.
3. **Sin anomalías de borrado.** Borrar el último cliente de un país no borra el país.
4. **Espacio mínimo.** Cada dato una vez.
5. **Escrituras rápidas.** Menos páginas tocadas por transacción.

**Todo eso es exactamente lo que querés en un POS.** El problema no es el diseño: es usarlo para algo para lo que no fue diseñado.

---

### 6.4 OLTP vs OLAP en profundidad

| | OLTP | OLAP |
|---|---|---|
| Unidad de trabajo | Transacción | Consulta analítica |
| Filas por operación | 1–10 | 10⁵–10⁹ |
| Columnas por consulta | Casi todas | Pocas, sobre muchas filas |
| Patrón | Aleatorio, puntual | Secuencial, masivo |
| Normalización | 3FN | Estrella / copo de nieve |
| Índices | Muchos, selectivos | Pocos; columnstore |
| Concurrencia | Alta | Moderada |
| Historia | Estado actual | Serie temporal |
| Frescura | Inmediata | Minutos a horas |
| Usuarios | Operativos + sistemas | Analistas y gerencia |
| Métrica de éxito | Transacciones/segundo | Tiempo de respuesta |

> **💡 El detalle técnico que explica el resto.** Un OLTP lee **pocas filas con muchas columnas** (un pedido completo). Un OLAP lee **pocas columnas de muchas filas** (el importe de un millón de ventas). Por eso existen los **índices columnstore**: almacenan por columna en lugar de por fila, y solo leen del disco las columnas que la consulta pide. Sobre una tabla de 40 columnas donde consultás 3, eso es leer el 7,5% de los datos.
>
> Mencionar esta asimetría fila/columna en una entrevista demuestra que entendés *por qué* existen las tecnologías analíticas, no solo que existen.

---

### 6.5 Kimball vs Inmon

> ➕ **Tema adicional recomendado:** las dos escuelas de arquitectura de DW
> **Por qué necesito aprenderlo:** son los dos nombres que aparecen en cualquier discusión de arquitectura de datos, y te van a preguntar cuál seguís.
> **En qué parte del proyecto lo utilizaremos:** el proyecto sigue Kimball; hay que saber por qué y cuál es la alternativa.

**Ralph Kimball — *bottom-up*, dimensional.**

Construir data marts dimensionales por proceso de negocio (ventas, inventario, compras) y unirlos mediante **dimensiones conformadas** — la misma `DimCustomer` compartida por todos.

✅ Resultados rápidos · Comprensible para el negocio · Se construye por partes
❌ Sin disciplina en las dimensiones conformadas, terminás con silos inconsistentes

**Bill Inmon — *top-down*, normalizado.**

Construir primero un warehouse corporativo normalizado (3FN) y derivar de él data marts dimensionales.

✅ Una única versión de la verdad · Flexible ante cambios · Menos redundancia
❌ Lento de construir · Caro · El negocio no ve valor por mucho tiempo

**Cuál sigue este proyecto: Kimball.** Un proceso de negocio (ventas), un esquema estrella, resultado visible rápido.

> **🎓 Respuesta de entrevista:** *"Seguimos Kimball porque queríamos entregar valor rápido sobre un proceso de negocio. La disciplina que exige Kimball es mantener dimensiones conformadas: cuando agreguemos compras, `DimProduct` tiene que ser la misma tabla, no una copia. Inmon tiene sentido cuando hay muchos orígenes con definiciones en conflicto y la integración es el problema principal."*

**Y hay una tercera opción moderna: Data Vault**, orientada a auditabilidad y trazabilidad (hubs, links, satellites). Vale conocerla por nombre; se usa cuando el requisito regulatorio de linaje es fuerte.

---

### 6.6 Warehouse, Mart, Lake, Lakehouse

> ➕ **Tema adicional recomendado:** taxonomía de almacenes analíticos
> **Por qué necesito aprenderlo:** son términos que se usan de forma intercambiable y equivocada; distinguirlos te posiciona bien.
> **En qué parte del proyecto lo utilizaremos:** para ubicar qué estás construyendo y qué no.

| | Qué es | Esquema | Formato | Usuario |
|---|---|---|---|---|
| **Data Warehouse** | Repositorio modelado para análisis | Al escribir | Tablas | Analistas, BI |
| **Data Mart** | Subconjunto para un área | Al escribir | Tablas | Un departamento |
| **Data Lake** | Almacenamiento crudo masivo | Al leer | Archivos (Parquet, JSON) | Ingenieros, científicos de datos |
| **Lakehouse** | Lake con transacciones y esquema | Ambos | Delta, Iceberg | Ambos |

> **💡 La distinción que de verdad importa: *schema-on-write* vs *schema-on-read*.**
>
> Un warehouse impone la estructura **al escribir**: si el dato no encaja, se rechaza. Eso garantiza consistencia y hace las consultas rápidas y predecibles.
>
> Un lake acepta cualquier cosa y la estructura se interpreta **al leer**. Eso da flexibilidad y traslada el costo de la calidad al consumidor — cada analista tiene que entender el formato crudo.
>
> **Ninguno es mejor. Resuelven problemas distintos.** Y el fracaso clásico del data lake es exactamente este: sin gobierno, se convierte en un *data swamp* — un pantano donde nadie sabe qué hay ni si es confiable.

**Lo que estás construyendo es un Data Warehouse pequeño**, o más precisamente un **data mart de ventas**: un proceso de negocio, modelado dimensionalmente, con esquema impuesto al escribir.

---

### 6.7 Por qué la redundancia controlada es correcta acá

En el warehouse vas a hacer algo que en OLTP sería un error: **repetir datos**.

`DimCustomer` va a tener `CityName`, `StateProvinceName` y `CountryName` **en la misma fila**, aunque eso repita "Estados Unidos" cientos de veces.

**Por qué está bien acá y mal allá:**

| | OLTP | Data Warehouse |
|---|---|---|
| ¿Quién actualiza? | Usuarios, todo el tiempo | Solo el ETL, una vez por carga |
| ¿Riesgo de inconsistencia? | Alto | **Nulo**: la carga escribe todo de una vez |
| ¿Costo de espacio? | Importa | Trivial frente al costo de los joins |
| ¿Beneficio? | — | Un join en lugar de tres |

**El argumento central:** la normalización protege contra **anomalías de actualización**, y las anomalías de actualización requieren **actualizaciones concurrentes no coordinadas**. En un warehouse, el único que escribe es tu proceso de carga, de forma controlada y atómica. **El riesgo que la normalización previene no existe acá.**

Por eso desnormalizar no es "hacer trampa": es aplicar el diseño correcto para las condiciones reales del sistema.

---

## 💡 Conceptos clave

- **Data Warehouse** — orientado a temas, integrado, variante en el tiempo, no volátil.
- **Normalización (3FN)** — evita anomalías de actualización; correcta en OLTP.
- **Desnormalización** — redundancia deliberada para acelerar lecturas.
- **Fan-out** — duplicación de medidas por relaciones muchos a muchos.
- **Kimball** — bottom-up, dimensional, dimensiones conformadas.
- **Inmon** — top-down, warehouse normalizado y marts derivados.
- **Schema-on-write / schema-on-read** — la diferencia de fondo entre warehouse y lake.
- **Columnstore** — almacenamiento por columna; lee solo lo que la consulta pide.

---

## 🧠 Preguntas de comprensión

1. La consulta de 6.1 devuelve ventas casi al doble. ¿Cuál es la causa exacta y en qué join ocurre?
2. ¿Por qué desnormalizar es correcto en el warehouse e incorrecto en el OLTP? La respuesta no puede ser "porque es más rápido".
3. Un compañero propone construir el warehouse normalizado en 3FN "para no repetir datos". ¿Qué escuela está siguiendo sin saberlo y qué le respondés?
4. Explicá la asimetría fila/columna entre OLTP y OLAP, y qué tecnología la aprovecha.

---

## 🎓 Preguntas de entrevista

1. **¿Qué es un Data Warehouse?** — Los cuatro adjetivos de Inmon, con un ejemplo de cada uno.
2. **¿Kimball o Inmon?** — Ver 6.5. Y mencionar la disciplina de dimensiones conformadas.
3. **¿Data Warehouse vs Data Lake?** — Schema-on-write vs schema-on-read, y qué problema resuelve cada uno.
4. **¿Por qué desnormalizar?** — Porque el riesgo que previene la normalización (actualizaciones concurrentes no coordinadas) no existe en un warehouse.
5. **¿Por qué no consultar el OLTP directamente?** — Rendimiento, comprensibilidad, y **la trampa de las relaciones muchos a muchos**.

---

## 📌 Resumen

- Una pregunta de negocio simple requiere ocho joins contra el OLTP — y la versión ingenua **da mal**.
- El OLTP está bien diseñado: la normalización previene anomalías de actualización.
- OLTP y OLAP tienen patrones de acceso opuestos: pocas filas × muchas columnas vs pocas columnas × muchas filas.
- Un DW es orientado a temas, integrado, variante en el tiempo y no volátil.
- **Kimball**: dimensional, bottom-up, dimensiones conformadas. Es lo que estás construyendo.
- Lake = schema-on-read; warehouse = schema-on-write. Resuelven problemas distintos.
- La redundancia es correcta acá porque **el único que escribe es el ETL**.

---

