---

# Módulo 15 — Dashboard: diseño, rendimiento y publicación

> **Paso 6 del proyecto**

## 🎯 Objetivos

- Elegir los KPIs correctos y justificarlos.
- Seleccionar la visualización adecuada para cada tipo de pregunta.
- Usar filtros y segmentadores conociendo su costo.
- Aplicar principios de diseño que se sostengan en una revisión.
- Diagnosticar y resolver problemas de rendimiento.
- Publicar con actualización programada.
- Entender la seguridad a nivel de fila.

---

## 📖 Teoría

### 15.1 Elegir los KPIs

**El error más frecuente: mostrar todo lo que se puede calcular.**

Un dashboard con 30 números no informa: obliga a buscar. Uno con 5 números bien elegidos comunica.

**El criterio, en tres preguntas por cada métrica:**

1. **¿Alguien va a tomar una decisión con esto?** Si no, es curiosidad, no un KPI.
2. **¿Se puede actuar sobre ella?** "Ventas totales" informa; "ventas por vendedor comparadas con su objetivo" **se puede accionar**.
3. **¿Tiene contexto?** Un número solo no dice nada. "$1,2M" no significa nada; "$1,2M, +8% vs el año anterior, 95% del objetivo" sí.

**Los KPIs de este proyecto:**

| KPI | Por qué |
|---|---|
| **Ventas totales** | La métrica principal del negocio |
| **Variación vs año anterior** | Contexto temporal: ¿mejoramos? |
| **Cantidad de pedidos** | Volumen de actividad |
| **Ticket promedio** | Eficiencia comercial |
| **Clientes activos** | Base de negocio |

Cinco. Y cada uno con su comparación.

> **✅ La regla de los 5 segundos:** alguien que nunca vio el dashboard debería entender **el estado general del negocio** en cinco segundos. Si tiene que leer etiquetas y buscar, el diseño falló. Todo lo demás —el detalle, la exploración— va debajo o en otra página.

---

### 15.2 Qué visualización para qué

| Pregunta | Visualización | Por qué |
|---|---|---|
| ¿Cuánto en total? | Tarjeta / KPI | Un número grande y legible |
| ¿Cómo evolucionó? | Línea | El eje X temporal es lo natural |
| ¿Cómo se comparan categorías? | Barras **horizontales** | Las etiquetas se leen sin girar la cabeza |
| ¿Cuál es la composición? | Barras apiladas · **rara vez torta** | La torta solo funciona con 2-3 partes |
| ¿Dónde geográficamente? | Mapa | Cuando la geografía importa de verdad |
| ¿Qué relación hay entre dos medidas? | Dispersión | Correlación |
| ¿Cuáles son los detalles? | Tabla / matriz | Cuando se necesita el número exacto |
| ¿Qué contribuyó al cambio? | Cascada | Descomposición de una variación |

**Las cinco reglas que casi nadie sigue:**

1. **Barras horizontales, no verticales, cuando las etiquetas son largas.** Nadie debería girar la cabeza para leer.
2. **Ordená las barras por valor**, no alfabéticamente. El orden por valor **es información**; el alfabético es ruido.
3. **Gráficos de torta: máximo 3 partes.** El ojo humano compara ángulos muy mal. Con 8 categorías, una barra siempre gana.
4. **El eje Y empieza en cero** en gráficos de barras. Empezarlo más arriba exagera diferencias — es distorsión, no diseño.
5. **Máximo 6-8 visualizaciones por página.** Más que eso es una página que nadie mira entera.

---

### 15.3 Filtros y segmentadores

**Los cuatro niveles, del más amplio al más acotado:**

1. **Filtros de informe** — aplican a todas las páginas.
2. **Filtros de página** — a todas las visualizaciones de esa página.
3. **Filtros de visualización** — a una sola.
4. **Segmentadores** — controles visibles que el usuario manipula.

**Buenas prácticas:**

- **Pocos segmentadores.** 3 o 4 por página. Diez segmentadores paralizan: el usuario no sabe por dónde empezar.
- **Segmentadores de fecha como rango**, no como lista de 4.000 días.
- **Jerárquicos**: País → Provincia → Ciudad, encadenados.
- **Mostrar la selección activa.** Un usuario que no ve qué filtró interpreta mal los números — y ese es un error de datos causado por un problema de diseño.

> **⚠️ El costo oculto de los segmentadores.** Cada segmentador es **una consulta DAX más** en cada actualización de la página. Un segmentador sobre una columna de alta cardinalidad (4.000 clientes) es lento de renderizar y de usar.
>
> Para casos así, preferí un filtro con búsqueda antes que una lista completa.

---

### 15.4 Principios de diseño

**Jerarquía visual.** Lo importante arriba a la izquierda. Los idiomas occidentales se leen en Z: esa esquina es lo primero que ve el ojo.

```
┌─────────────────────────────────────────────┐
│  [KPI]  [KPI]  [KPI]  [KPI]  [KPI]          │  ← el resumen
├──────────────────────┬──────────────────────┤
│  Evolución temporal  │  Top categorías      │  ← las tendencias
├──────────────────────┴──────────────────────┤
│  Tabla de detalle                           │  ← el detalle
└─────────────────────────────────────────────┘
```

**Consistencia.** Los mismos colores para los mismos conceptos en todas las páginas. Si "Bebidas" es azul en un gráfico, es azul en todos.

**Color con propósito.**
- Máximo 5-6 colores distintos.
- **Rojo/verde solo para bueno/malo**, nunca decorativo.
- **8% de los hombres tiene daltonismo rojo-verde.** No transmitas información **solo** por color: agregá una flecha, un signo o una etiqueta.

**Espacio en blanco.** Los elementos apretados se leen peor. El espacio vacío no es desperdicio: es lo que hace legible lo demás.

**Números formateados para humanos.** `$1,2M` en vez de `1234567,89`. Nadie cuenta dígitos.

**Títulos que digan algo.** "Ventas mensuales 2026 vs 2025" en vez de "Suma de SalesAmount por MesNombre".

> **✅ Y el elemento que casi ningún dashboard tiene y todos deberían: la frescura del dato.** Una tarjeta discreta con **"Datos actualizados: 10/08/2026 02:04"**, alimentada por `etl.LoadBatch`.
>
> Cuesta cinco minutos y resuelve dos problemas: le da al usuario el contexto para interpretar lo que ve, y **convierte a cada persona que abre el dashboard en un detector de pipelines caídos**. Es la solución más barata al problema del Módulo 5.

---

### 15.5 Rendimiento

**Diagnóstico:** `Ver → Analizador de rendimiento`. Muestra cuánto tarda cada visualización, desglosado en consulta DAX, renderizado y otros.

**Las causas más frecuentes, en orden:**

| Problema | Solución |
|---|---|
| Demasiadas visualizaciones por página | Reducir a 6-8; usar páginas de detalle |
| Medidas con `FILTER` sobre la fact table | Filtrar la dimensión |
| `DISTINCTCOUNT` de alta cardinalidad | Precalcular en el warehouse si se puede |
| Columnas de alta cardinalidad | Quitarlas; reducir precisión de fechas |
| Relaciones bidireccionales | Cambiar a simples + `CROSSFILTER` |
| Segmentadores de alta cardinalidad | Filtro con búsqueda |
| Jerarquía automática de fechas | Desactivarla |
| Visualizaciones personalizadas | Preferir las nativas |
| DirectQuery innecesario | Pasar a Import |

**El orden de optimización, y es importante:**

1. **Medí** con el Analizador. No supongas.
2. **Reducí el modelo** — columnas, cardinalidad. Es lo que más rinde.
3. **Optimizá las medidas** — `VAR`, filtrar dimensiones.
4. **Simplificá las páginas.**

> **✅ El punto 2 es el de mayor retorno y el que menos se hace.** Quitar 10 columnas que nadie usa puede reducir el modelo un 40% y acelerar **todo** el informe. Optimizar una medida acelera esa medida.

---

### 15.6 Publicación y actualización

> ➕ **Tema adicional recomendado:** publicación y gateway
> **Por qué necesito aprenderlo:** un informe que no se actualiza solo no está terminado.
> **En qué parte del proyecto lo utilizaremos:** al cerrar el paso 6.

**Publicar:** `Inicio → Publicar → elegir área de trabajo`

**Para que se actualice contra tu SQL Server local hacen falta tres cosas:**

1. **On-premises Data Gateway** instalado en una máquina con acceso al servidor. Modo **estándar** (no personal) si el informe es compartido.
2. **Credenciales configuradas** en el conjunto de datos del servicio.
3. **Actualización programada** — hasta 8 veces por día con licencia Pro; 48 con Premium.

> **⚠️ El orden de la actualización importa y casi siempre se configura mal.** El job de SQL Server termina a las 2:15. Si Power BI actualiza a las 2:00, **está leyendo los datos de ayer** — todos los días, en silencio.
>
> Programá la actualización con margen: 3:00 AM. Y mejor todavía: **disparala desde el propio pipeline** cuando termine, usando la API REST de Power BI desde un paso del job. Así la dependencia es real y no una apuesta sobre duraciones — es exactamente el argumento del Módulo 5 aplicado a la última capa.

**Compartir:**
- **Áreas de trabajo** para colaborar entre quienes construyen.
- **Aplicaciones** para distribuir a consumidores.
- Compartir un informe individual funciona y no escala.

---

### 15.7 Seguridad a nivel de fila

> ➕ **Tema adicional recomendado:** RLS
> **Por qué necesito aprenderlo:** casi todo despliegue real lo necesita, y es una pregunta de entrevista frecuente.
> **En qué parte del proyecto lo utilizaremos:** si quisieras que cada vendedor vea solo sus ventas.

**RLS** (*Row-Level Security*) filtra los datos según quién mira el informe.

**En Power BI Desktop:** `Modelado → Administrar roles`

```dax
-- Rol "Vendedor": solo ve sus propias ventas
[NombreCompleto] = USERPRINCIPALNAME()

-- Rol "Gerente de país": solo su país
[Pais] = LOOKUPVALUE(
    Usuarios[Pais],
    Usuarios[Email], USERPRINCIPALNAME()
)
```

`USERPRINCIPALNAME()` devuelve el correo del usuario conectado.

**Cómo funciona:** el filtro se aplica a la tabla del rol y **se propaga por las relaciones**, igual que cualquier filtro. Por eso un filtro en `DimSalesperson` alcanza para restringir `FactSales`.

**Probarlo:** `Modelado → Ver como → elegir rol`. **Probalo siempre**: un RLS mal configurado que no filtra nada es una filtración de datos silenciosa.

> **⚠️ RLS filtra filas, no columnas.** Si un vendedor no debe ver el costo del producto, RLS no sirve — hay que quitar la columna del modelo o usar **object-level security**, que es una función aparte.
>
> Y RLS **no se aplica al creador del informe** en Desktop: hay que usar "Ver como" para verificarlo.

---

## 📌 Resumen

- **5 KPIs bien elegidos**, cada uno con su comparación. La regla de los 5 segundos.
- Barras horizontales ordenadas por valor; torta solo con 2-3 partes; eje Y desde cero.
- Pocos segmentadores; cada uno cuesta una consulta DAX.
- Jerarquía visual en Z, consistencia de color, espacio en blanco, títulos con significado.
- **Mostrá la frescura del dato.** Cinco minutos, mucho valor.
- Optimizá en orden: medir → reducir el modelo → optimizar medidas → simplificar páginas.
- Publicación: gateway + credenciales + actualización programada **con margen o disparada por el pipeline**.
- RLS filtra filas y se propaga por relaciones. **Probalo siempre con "Ver como".**

---

## 🎓 Preguntas de entrevista

1. **¿Cómo elegís qué mostrar en un dashboard?** — Las tres preguntas de 15.1. Accionabilidad ante todo.
2. **¿Tu informe está lento. Qué hacés?** — Medir con el Analizador; después modelo, medidas, páginas.
3. **¿Cómo publicás y actualizás?** — Gateway, credenciales, programación, **y el orden respecto del ETL**.
4. **¿Qué es RLS y cómo lo probás?** — Filtra filas por usuario; "Ver como".
5. **¿Cómo garantizás que el usuario sabe si los datos están frescos?** — Tarjeta de última actualización desde la tabla de control.
6. **¿Cuántas visualizaciones por página?** — 6-8; cada una es una consulta.

---

# 🔐 Soluciones — Volumen III

## Módulo 14 — Preguntas de comprensión

**1.** Se evalúa **60 veces** (12 × 5), más las celdas de totales: 12 totales de fila, 5 de columna y 1 general, así que **78 evaluaciones**. Cada una con un contexto de filtro distinto: la intersección del mes de su fila y la categoría de su columna, más cualquier segmentador activo. Las celdas de total tienen el filtro de una sola dimensión, y el total general no tiene ninguno de los dos.

**2.** `SUM` es un **agregador**: recibe una **columna** y la suma. No puede evaluar una expresión, porque no tiene contexto de fila — no sabe en qué fila está para tomar `Quantity` y `UnitPrice` de la misma. `SUMX` es un **iterador**: recibe una tabla, la recorre creando contexto de fila, evalúa la expresión en cada una, y suma los resultados.

**3.** **Contexto de fila:** en una columna calculada `Importe = FactSales[Quantity] * FactSales[UnitPrice]`, DAX sabe que está en la fila 5 y toma los valores de esa fila. **No filtra nada**: si en esa misma columna escribieras `SUM(FactSales[SalesAmount])`, obtendrías el total de toda la tabla.

**Contexto de filtro:** en la celda "Agosto / Bebidas" de una matriz, los filtros activos son `MesAnioNombre = "Ago 2026"` y `Categoria = "Bebidas"`. `SUM(FactSales[SalesAmount])` solo ve las filas que sobreviven a esos filtros, propagados desde las dimensiones por las relaciones.

**4.** **Reemplaza** el filtro anterior sobre esa columna. Si el usuario seleccionó "Confitería" y la medida es `CALCULATE([Ventas], DimProduct[Categoria] = "Bebidas")`, el resultado son las ventas de bebidas — la selección del usuario se descarta para esa columna. Para que se intersequen (y el resultado sea vacío), hay que envolver el filtro en `KEEPFILTERS`.

**5.** **`ALLSELECTED`.** Con `ALL`, el denominador serían las ventas de **todos los años**, así que los porcentajes de las categorías **no sumarían 100%** dentro de la vista de 2025 — el usuario vería porcentajes que no cierran y no entendería por qué. Con `ALLSELECTED`, el denominador respeta el segmentador de año, los porcentajes suman 100% y significan "participación dentro de lo que estoy viendo", que es lo que la gente espera.

**6.** Por la **transición de contexto**. En una columna calculada de `DimCustomer` hay contexto de fila (sabemos qué cliente es) pero **no** contexto de filtro, así que `SUM(FactSales[SalesAmount])` a secas daría el total global en cada fila. `CALCULATE` convierte la fila actual en un filtro (`CustomerKey = <este>`), ese filtro se propaga por la relación hacia `FactSales`, y el resultado es lo que compró ese cliente.

**7.** Porque **promedia precios sin ponderar por cantidad**. Si vendiste 1 unidad a $1.000 y 1.000 unidades a $1, `AVERAGE(UnitPrice)` da $500,50 — un valor que no describe nada real. El precio promedio efectivo es `DIVIDE(SUM(SalesAmount), SUM(Quantity))` = $2.000/1.001 ≈ $2. `UnitPrice` es una medida **no aditiva** (Módulo 7): hay que calcularla desde componentes aditivos, no agregarla directamente.

---

## Módulos 11–13 — Comprensión

**¿Por qué una consulta SQL nativa en el conector rompe el folding?** Porque Power Query trata la consulta como una caja negra: no puede analizarla para inyectarle filtros ni proyecciones. Todos los pasos posteriores se ejecutan localmente sobre el resultado completo. Si necesitás lógica SQL, ponela en una **vista** del servidor: Power Query la ve como una tabla y puede seguir haciendo folding sobre ella.

**¿Por qué la cardinalidad importa más que la cantidad de filas en VertiPaq?** Porque la codificación por diccionario guarda cada valor distinto **una sola vez** y las filas almacenan un índice entero. Una columna con 10 valores distintos y 10 millones de filas guarda 10 valores + 10 millones de índices de 4 bits. Una columna con 10 millones de valores distintos guarda 10 millones de valores + 10 millones de índices anchos: no comprime nada y domina el tamaño del modelo.

**¿Por qué el esquema estrella comprime mejor que una tabla plana?** Porque los atributos de dimensión se almacenan una vez por entidad, no una vez por hecho. `CustomerName` aparece 663 veces en `DimCustomer` y 0 veces en `FactSales` (que solo guarda un entero). En una tabla plana, aparecería 231.412 veces, con un diccionario que hay que recorrer en cada segmento.

---

