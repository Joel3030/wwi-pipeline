---

# 📚 ÍNDICE GENERAL

El libro está dividido en **tres volúmenes**, que corresponden a las tres capas del pipeline. Cada volumen se puede estudiar de forma independiente una vez completado el anterior, y está pensado para unas 2 a 3 semanas de estudio a ritmo normal.

---

## VOLUMEN I — Fundamentos y la capa Bronce
### *Pasos 1, 2 y 3: del origen al staging automatizado*

**Módulo 0 — El mapa completo**
- 0.1 Qué vas a construir y por qué en ese orden
- 0.2 OLTP vs OLAP: los dos mundos
- 0.3 Qué es un pipeline de datos
- 0.4 ETL vs ELT ➕
- 0.5 La arquitectura medallón: bronce, plata, oro ➕
- 0.6 Por qué nunca se consulta producción directamente
- 0.7 El vocabulario que vas a necesitar
- Examen del Módulo 0

**Módulo 1 — WideWorldImporters y el arte de explorar una base desconocida** *(Paso 1)*
- 1.1 Qué es WideWorldImporters y por qué se usa para aprender
- 1.2 Restaurar la base: `RESTORE DATABASE` paso a paso
- 1.3 `WITH MOVE`, `RECOVERY` / `NORECOVERY`, `REPLACE`
- 1.4 Modelos de recuperación: SIMPLE, FULL, BULK_LOGGED ➕
- 1.5 Anatomía de la base: schemas y su intención de diseño
- 1.6 Cómo descubrir tablas sin documentación
- 1.7 Cómo descubrir columnas y tipos de datos
- 1.8 Cómo descubrir relaciones: Primary Keys y Foreign Keys
- 1.9 Constraints: CHECK, UNIQUE, DEFAULT, NOT NULL
- 1.10 Perfilado de datos: NULLs, cardinalidad, rangos, distribuciones
- 1.11 Detectar la trampa: relaciones muchos a muchos
- 1.12 Tablas temporales de sistema y columnas ocultas de WWI ➕
- 1.13 Qué tablas necesita *nuestro* proyecto y cómo lo decidimos
- 1.14 El kit de exploración: 12 consultas para cualquier base nueva
- Examen del Módulo 1

**Módulo 2 — La capa Staging** *(Paso 2, parte 1)*
- 2.1 El problema que nadie te cuenta hasta que lo sufrís
- 2.2 Qué es Staging y qué NO es
- 2.3 Los cinco problemas que resuelve
- 2.4 Staging alineado al origen (*source-aligned staging*)
- 2.5 Cómo diseñar una tabla de staging
- 2.6 Por qué en staging casi todo es NULL-able
- 2.7 Tipos de datos: cuándo relajarlos y cuándo no
- 2.8 Columnas de auditoría: `LoadBatchId` y `LoadedAt`
- 2.9 Base separada vs schema separado
- 2.10 Full Load vs Incremental Load ➕
- 2.11 Idempotencia: la propiedad que hace todo lo demás posible
- 2.12 `TRUNCATE` vs `DELETE` vs `DROP` + `CREATE`
- Examen del Módulo 2

**Módulo 3 — Stored Procedures para ETL** *(Paso 2, parte 2)*
- 3.1 Qué es un Stored Procedure y por qué ETL vive en uno
- 3.2 Anatomía: parámetros, variables, ámbito
- 3.3 `SET NOCOUNT ON` y `SET XACT_ABORT ON`
- 3.4 `INSERT`, `UPDATE`, `DELETE` en contexto ETL
- 3.5 `MERGE`: qué hace, cuándo sirve y por qué desconfiar de él ➕
- 3.6 Transacciones y ACID
- 3.7 `TRY` / `CATCH` y `@@TRANCOUNT`
- 3.8 `THROW` vs `RAISERROR`
- 3.9 Errores que TRY/CATCH no atrapa ➕
- 3.10 La tabla de control: `etl.LoadBatch`
- 3.11 Por qué el registro va fuera de la transacción
- 3.12 Separar carga de validación y por qué importa para las pruebas
- 3.13 Qué hacer cuando una carga falla
- 3.14 `CREATE OR ALTER` y la base como código ➕
- Examen del Módulo 3

**Módulo 4 — Validaciones y Data Quality** *(Paso 2, parte 3)*
- 4.1 Por qué las validaciones son el corazón del pipeline
- 4.2 Las seis dimensiones de la calidad de datos ➕
- 4.3 Validación de NULLs
- 4.4 Validación de duplicados
- 4.5 Integridad referencial: claves huérfanas
- 4.6 Rangos, dominios y valores fuera de escala
- 4.7 Fechas inválidas e imposibles
- 4.8 Consistencia entre campos
- 4.9 Registros incompletos y errores de formato
- 4.10 Agregación condicional: cinco validaciones en una consulta
- 4.11 El constructor de tabla `(VALUES ...)`
- 4.12 La decisión profesional: rechazar, aislar, corregir, ignorar o registrar
- 4.13 Fail fast vs log and continue
- 4.14 Validaciones de volumen y frescura: *data observability* ➕
- 4.15 Pruebas del camino negativo ➕
- Examen del Módulo 4

**Módulo 5 — SQL Server Agent** *(Paso 3)*
- 5.1 Qué es SQL Server Agent
- 5.2 Job → Step → Schedule: el modelo mental
- 5.3 Crear un Job por script y por qué no con el asistente
- 5.4 `sp_add_job`, `sp_add_jobstep`, `sp_add_jobschedule`, `sp_add_jobserver`
- 5.5 Elegir la frecuencia: latencia vs costo
- 5.6 Reintentos: qué errores los merecen y cuáles no
- 5.7 Qué pasa cuando un Step falla: flujo de control
- 5.8 Dependencias y orden de ejecución
- 5.9 Historial de ejecuciones y sus límites
- 5.10 Database Mail: cuentas, perfiles y operadores
- 5.11 Alertas: notificar solo lo accionable
- 5.12 Zonas horarias: UTC vs hora local ➕
- 5.13 Seguridad: propietario del job, contextos y credenciales ➕
- 5.14 Cómo diseñar un Job confiable: checklist
- Examen del Módulo 5
- 🔐 **Soluciones del Volumen I**

---

## VOLUMEN II — Modelado dimensional y la capa Oro
### *Pasos 4 y 5: del dato crudo al modelo de negocio*

**Módulo 6 — Data Warehouse: el porqué**
- 6.1 La consulta que rompe el modelo transaccional
- 6.2 Qué es un Data Warehouse
- 6.3 Normalización: por qué el OLTP está bien hecho
- 6.4 OLTP vs OLAP en profundidad
- 6.5 Kimball vs Inmon: las dos escuelas ➕
- 6.6 Data Warehouse, Data Mart, Data Lake, Lakehouse ➕
- 6.7 Por qué la redundancia controlada es correcta acá

**Módulo 7 — Modelado dimensional y esquema estrella** *(Paso 4, parte 1)*
- 7.1 Hechos y dimensiones: la separación fundamental
- 7.2 Cómo reconocer un hecho y cómo reconocer una dimensión
- 7.3 **Granularidad**: la decisión más importante del proyecto
- 7.4 Los cuatro pasos de Kimball
- 7.5 Métricas y medidas: aditivas, semi-aditivas y no aditivas ➕
- 7.6 Claves surrogate vs claves de negocio
- 7.7 Por qué la fact table no usa la PK del origen
- 7.8 Esquema estrella vs copo de nieve
- 7.9 Tipos de tablas de hechos: transacción, snapshot, acumulativa ➕
- 7.10 La dimensión fecha: por qué se construye a mano
- 7.11 Dimensiones degeneradas ➕
- 7.12 Manejo de muchos a muchos: tablas puente ➕
- 7.13 Slowly Changing Dimensions: tipos 0, 1, 2 y 3 ➕
- 7.14 Miembros desconocidos y filas huérfanas ➕
- Examen del Módulo 7

**Módulo 8 — Construir el modelo** *(Paso 4, parte 2)*
- 8.1 Del diagrama al DDL
- 8.2 `DimDate`: generación, atributos y jerarquías
- 8.3 `DimCustomer`: aplanando seis tablas en una
- 8.4 `DimProduct`: resolviendo el muchos a muchos
- 8.5 `DimSalesperson`: la dimensión más simple
- 8.6 `FactSales`: grano, claves y medidas
- 8.7 El orden de carga y por qué las dimensiones van primero
- 8.8 Búsqueda de claves surrogate (*surrogate key lookup*)
- 8.9 Índices en un Data Warehouse ➕
- 8.10 Índices columnstore ➕
- 8.11 Verificar el modelo: cuadre contra el origen
- Examen del Módulo 8

**Módulo 9 — La capa de resumen**
- 9.1 Qué es una capa de resumen y por qué puede sobrar
- 9.2 Datos detallados vs agregados
- 9.3 `SUM`, `COUNT`, `AVG`, `MIN`, `MAX` y sus trampas
- 9.4 `GROUP BY`, `HAVING` y el orden lógico de ejecución
- 9.5 Agregaciones por fecha, cliente, producto y vendedor
- 9.6 `GROUPING SETS`, `ROLLUP` y `CUBE` ➕
- 9.7 Funciones de ventana para métricas acumuladas ➕
- 9.8 Cómo decidir qué resumir: la regla del costo × frecuencia
- 9.9 Vistas, vistas indexadas y tablas materializadas ➕
- 9.10 Cuándo una tabla de resumen es solo duplicación
- Examen del Módulo 9

**Módulo 10 — Automatizar el Data Warehouse** *(Paso 5)*
- 10.1 El flujo completo y sus dependencias
- 10.2 Un job con muchos steps vs muchos jobs
- 10.3 Orden de ejecución y qué hacer ante un fallo intermedio
- 10.4 Carga incremental de dimensiones y hechos
- 10.5 Marcas de agua (*watermarks*) y control de fechas ➕
- 10.6 Reprocesamiento y ventanas de recarga ➕
- 10.7 Auditoría de punta a punta: linaje del dato ➕
- 10.8 Idempotencia en el modelo dimensional
- 10.9 Monitoreo: qué medir y qué alertar
- Examen del Módulo 10
- 🔐 **Soluciones del Volumen II**

---

## VOLUMEN III — Power BI y DAX
### *Paso 6: del modelo al dashboard*

**Módulo 11 — Power BI: fundamentos y conexión**
- 11.1 Qué es Power BI y cuáles son sus piezas
- 11.2 Conectar a SQL Server
- 11.3 Import vs DirectQuery vs Dual ➕
- 11.4 Por qué apuntamos al DW y nunca a staging ni a producción
- 11.5 El motor VertiPaq y por qué el modelo importa ➕

**Módulo 12 — Power Query**
- 12.1 Qué es Power Query y el lenguaje M
- 12.2 Transformaciones habituales
- 12.3 *Query folding*: la optimización que no se ve ➕
- 12.4 Parámetros y consultas reutilizables
- 12.5 **SQL vs Power Query vs DAX: dónde va cada transformación**

**Módulo 13 — El modelo de datos en Power BI**
- 13.1 Trasladar el esquema estrella a Power BI
- 13.2 Relaciones: cardinalidad y dirección de filtro
- 13.3 Filtrado cruzado bidireccional y por qué evitarlo ➕
- 13.4 Marcar la tabla de fechas
- 13.5 Ocultar columnas técnicas
- 13.6 Por qué un esquema estrella rinde mejor que uno plano ➕

**Módulo 14 — DAX**
- 14.1 Qué es DAX y cómo piensa
- 14.2 Medidas vs columnas calculadas
- 14.3 **Contexto de fila y contexto de filtro**
- 14.4 Transición de contexto ➕
- 14.5 `SUM` vs `SUMX`: agregadores e iteradores
- 14.6 `COUNT`, `COUNTROWS`, `DISTINCTCOUNT`
- 14.7 `CALCULATE`: la función que hay que entender de verdad
- 14.8 `FILTER` y cuándo hace falta
- 14.9 `ALL`, `ALLEXCEPT`, `REMOVEFILTERS`
- 14.10 `RELATED` y `RELATEDTABLE`
- 14.11 Funciones de fecha y Time Intelligence
- 14.12 Porcentajes del total y participación
- 14.13 Comparaciones: año anterior, variación, acumulados
- 14.14 `VAR`: legibilidad y rendimiento ➕
- 14.15 Métricas de negocio del proyecto
- Examen del Módulo 14

**Módulo 15 — Dashboard: diseño, rendimiento y publicación**
- 15.1 KPIs: elegir los correctos
- 15.2 Visualizaciones: cuál para qué
- 15.3 Filtros, segmentadores y su costo
- 15.4 Principios de diseño de dashboards
- 15.5 Rendimiento: diagnóstico y remedios
- 15.6 Publicación, actualización programada y gateway ➕
- 15.7 Seguridad a nivel de fila (RLS) ➕
- Examen del Módulo 15
- 🔐 **Soluciones del Volumen III**

---

## PROYECTO FINAL

- P.1 El entregable completo
- P.2 Checklist de construcción
- P.3 Checklist de explicación — *si no lo podés explicar, no lo terminaste*
- P.4 Cómo presentarlo en una entrevista
- P.5 Extensiones posibles

## APÉNDICES

- A. Kit de consultas de exploración
- B. Glosario español–inglés de términos de BI
- C. Errores reales cometidos en este proyecto y su diagnóstico
- D. Plantillas reutilizables
- E. Lecturas recomendadas

