# Alcance del pipeline: qué entra y qué queda afuera

Resultado del Paso 1 (exploración y perfilado con `01_kit_exploracion.sql`).

`WideWorldImporters` tiene **48 tablas en 4 schemas**: `Application` (15),
`Purchasing` (7), `Sales` (12), `Warehouse` (14). El pipeline usa una fracción.

## El criterio

> **Si no podés nombrar una pregunta de negocio que la tabla ayuda a responder, no la traigas.**

Cada tabla del pipeline es superficie de mantenimiento permanente: hay que
cargarla, validarla, versionarla y arreglarla cuando el origen cambie. Copiar
todo "por las dudas" no es prudencia — es trabajo futuro asumido sin decidirlo.

Esto es lo contrario de un data lake, donde la premisa es guardar todo crudo. Un
pipeline con destino conocido se diseña al revés: se parte de la pregunta.

## Proceso de negocio elegido: pedidos de venta

La pregunta que el dashboard tiene que responder es *"¿cómo vienen las ventas,
por producto, cliente y tiempo?"*.

**Se eligió `Sales.Orders` / `Sales.OrderLines` (pedidos), no `Sales.Invoices` /
`Sales.InvoiceLines` (facturación).** Son dos procesos distintos:

| | Pedidos | Facturas |
|---|---|---|
| Qué mide | lo que el cliente **pidió** | lo que se le **cobró** |
| Filas | 73.595 / 231.412 | 70.510 / 228.265 |

La diferencia de 3.085 pedidos son pedidos nunca facturados. **No es ruido: es la
distancia entre intención de compra e ingreso.** Por eso la medida del modelo se
llama *importe de pedidos* y no *ventas* — si el dashboard dijera "Ventas"
midiendo pedidos, estaría informando otra cosa.

Un proyecto de facturación real elegiría `Invoices`. Este eligió `Orders` porque
el objetivo es aprender el patrón, y porque es lo que ya estaba en staging.

## Tablas dentro del alcance

| Sustantivo | Tabla | Filas | Rol |
|---|---|---|---|
| Venta (detalle) | `Sales.OrderLines` | 231.412 | **Hecho** — el grano |
| Venta (cabecera) | `Sales.Orders` | 73.595 | Contexto del hecho: fecha, cliente, vendedor |
| Producto | `Warehouse.StockItems` | 227 | Dimensión |
| Categoría de producto | `Warehouse.StockGroups` + puente | 10 + 442 | Dimensión ⚠️ **M:N** |
| Cliente | `Sales.Customers` | 663 | Dimensión |
| Categoría de cliente | `Sales.CustomerCategories` | 8 | Atributo de dimensión |
| Geografía | `Cities` → `StateProvinces` → `Countries` | 37.940 / 53 / 190 | Atributo de dimensión |
| Vendedor | `Application.People` | 1.111 | Dimensión |
| Tiempo | *(ninguna)* | — | **Dimensión a construir** |

Dos cosas para notar en esa tabla:

**El "Mes" no existe en el origen.** Ninguna tabla lo representa. Es el primer
indicio de que un warehouse *agrega* estructura que el OLTP no tiene: `DimDate`
se genera, no se extrae.

**La categoría de producto es muchos a muchos.** 227 productos con 442
asignaciones a 10 grupos, vía `Warehouse.StockItemStockGroups`. Unir el hecho a
través de esa tabla puente **multiplica filas e infla los importes sin producir
ningún error**. Es el fan-out, y hay que resolverlo explícitamente al construir
`DimProduct` — está pendiente de decisión (ver README, sección Paso 4).

## Tablas excluidas, con motivo

| Excluida | Motivo | Cuándo revisarlo |
|---|---|---|
| **Schema `Purchasing`** completo (7 tablas) | Es **otro proceso de negocio**: compras a proveedores, no ventas a clientes. Tiene su propio grano, sus propias dimensiones y sus propias preguntas. | Si se pide analizar margen o rotación de inventario, que necesitan costo de compra. Sería un segundo hecho, no una extensión de éste. |
| `Sales.Invoices` / `Sales.InvoiceLines` | **Facturación no es lo mismo que pedidos.** Mezclarlos en un mismo hecho produciría doble conteo, porque un pedido facturado aparecería dos veces. | Si la pregunta pasa a ser sobre ingreso real cobrado. Ahí conviene un hecho separado, o migrar el grano a la factura. |
| `Warehouse.StockItemTransactions` | Movimientos de inventario: otro proceso, otro grano (un movimiento no es una venta). | Si se piden métricas de stock, quiebre o reposición. |
| `Application.*` salvo `People` y la cadena geográfica | Tablas de infraestructura de la aplicación: parámetros del sistema, tipos de entrega, grupos de transacción. No responden preguntas de negocio. | Si alguna resulta necesaria como atributo de una dimensión. |
| Tablas de historial (`*_Archive`) | Son las tablas históricas de las **17 tablas temporales de sistema**. No se cargan directo: se consultan con `FOR SYSTEM_TIME` si hace falta reconstruir el pasado. | Al implementar SCD Tipo 2 — el origen ya tiene el historial y evita construirlo a mano. |

## Hallazgos de calidad que condicionan el diseño

Detectados con las consultas 7, 9, 12, 13 y 14 del kit:

- **`Sales.Orders.BackorderOrderID` apunta a otro pedido sin FK declarada.** No
  hay integridad garantizada: puede referenciar pedidos inexistentes. Cualquier
  `INNER JOIN` por esa columna descartaría filas en silencio.
- **`Sales.OrderLines.UnitPrice` es NULL-able en el origen.** Es la única medida
  monetaria del modelo y la fuente admite que falte. Un `NULL` se propaga por la
  multiplicación (`Quantity * NULL = NULL`) y después `SUM` lo ignora: el total
  sale más chico **sin ningún error**.
- **`Sales.OrderLines.Description` es el nombre del producto congelado al momento
  del pedido**, no una descripción de la línea. Hoy coincide con
  `Warehouse.StockItems.StockItemName` en las 231.412 filas — porque todavía no
  renombraron ningún producto, no porque la columna sobre.
- **`Application.People.SearchName` es columna calculada**: no se puede insertar.
- **0 líneas huérfanas** hoy: todas las `OrderLines` tienen su `Order`. Una
  validación que da cero no es tiempo perdido, es una línea base.
