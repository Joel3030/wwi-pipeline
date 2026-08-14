---

# VOLUMEN I
## Fundamentos y la capa Bronce

---

# Módulo 0 — El mapa completo

## 🎯 Objetivos

Al terminar este módulo vas a poder:

- Explicar qué es un pipeline de datos y qué problema resuelve, sin usar la palabra "pipeline".
- Distinguir un sistema OLTP de uno OLAP y justificar por qué no se pueden servir con el mismo diseño.
- Explicar la diferencia entre ETL y ELT y decir cuál corresponde a este proyecto.
- Describir la arquitectura medallón y qué garantiza cada capa.
- Justificar técnicamente por qué un reporte no debe consultar la base de producción.
- Ubicar cada uno de los seis pasos del proyecto dentro de una arquitectura de datos profesional.

---

## 📖 Teoría

### 0.1 Qué vas a construir y por qué en ese orden

Empecemos por el final. Cuando termines este libro vas a tener un dashboard donde alguien puede filtrar "ventas del último trimestre, categoría Bebidas, país Estados Unidos" y obtener un número en menos de un segundo.

Eso es lo visible. Debajo hay siete capas, y **cada una existe porque la anterior dejó un problema sin resolver**.

Ese encadenamiento es lo importante de este módulo. Si lo entendés, el resto del libro es ejecución.

| # | Capa | Problema que arrastra la anterior | Qué garantiza |
|---|---|---|---|
| 1 | **Origen** (WideWorldImporters) | — | La verdad del negocio |
| 2 | **Staging** | Consultar el origen lo pone en riesgo | Una copia aislada y estable |
| 3 | **Validaciones** | Una copia fiel copia también la basura | Que sepamos en qué confiar |
| 4 | **Transformaciones** | El dato validado sigue con forma de OLTP | Forma utilizable por el negocio |
| 5 | **Modelo dimensional** | Sin estructura común, cada consulta se reinventa | Un lenguaje compartido |
| 6 | **Automatización** | Nada de lo anterior sirve si hay que correrlo a mano | Datos frescos sin intervención |
| 7 | **Power BI** | Las tablas no responden preguntas, las personas sí | Acceso a quien toma decisiones |

Fijate que el orden no es arbitrario ni "de fácil a difícil". Es **causal**. No podés validar lo que no copiaste, no podés transformar lo que no validaste, y no tiene sentido automatizar algo que todavía no funciona a mano.

> **Analogía para quien viene de desarrollo de software:** es exactamente la razón por la que una aplicación tiene capa de datos, capa de dominio y capa de presentación. No es burocracia — es que cada capa resuelve una preocupación distinta y te deja cambiar una sin romper las otras. Un pipeline de datos es arquitectura en capas aplicada al dato en movimiento.

---

### 0.2 OLTP vs OLAP: los dos mundos

Esta distinción es la piedra fundacional de todo el campo. Si te la preguntan en una entrevista y titubeás, se nota.

**OLTP** = *Online Transaction Processing*. Sistemas que **registran** lo que pasa: el POS que cobra, el ERP que factura, el e-commerce que toma el pedido. WideWorldImporters es OLTP. El sistema en el que trabajás todos los días, casi con seguridad, también.

**OLAP** = *Online Analytical Processing*. Sistemas que **analizan** lo que pasó: el reporte de ventas, el dashboard del gerente, el modelo de proyección.

Y ahora lo que de verdad importa, porque acá es donde la mayoría se queda en la definición de manual:

| | OLTP | OLAP |
|---|---|---|
| **Pregunta típica** | "¿Cuál es el saldo del pedido 12345?" | "¿Cómo evolucionaron las ventas por región en 3 años?" |
| **Filas por operación** | Una, o muy pocas | Millones |
| **Operación dominante** | Escritura (INSERT/UPDATE) | Lectura (SELECT con agregación) |
| **Concurrencia** | Cientos o miles de usuarios | Decenas |
| **Latencia aceptable** | Milisegundos | Segundos, a veces minutos |
| **Diseño** | Normalizado (3FN) | Desnormalizado (estrella) |
| **Redundancia** | Se evita a toda costa | Se introduce a propósito |
| **Historia** | Se guarda el estado *actual* | Se guarda el estado *a lo largo del tiempo* |
| **Si se cae** | El negocio se detiene | Alguien no ve su reporte hoy |

Leé de nuevo la última fila. **Esa** es la razón práctica por la que se separan.

#### Por qué no se puede servir a los dos con el mismo diseño

No es una cuestión de recursos. Es que los objetivos son **matemáticamente opuestos**.

Para escribir rápido y sin inconsistencias, querés que cada dato viva en **un solo lugar**. Si el cliente cambia de ciudad, actualizás una fila y listo. Eso es normalización.

Para leer rápido, querés que cada dato esté **al alcance de la mano**, aunque haya que repetirlo. Si voy a agrupar ventas por país un millón de veces por día, no quiero recorrer cinco tablas cada vez para llegar al país.

No hay diseño que optimice ambas cosas. Por eso hay **dos sistemas y un proceso que los une** — y ese proceso es lo que vas a construir.

> **💡 Concepto clave — HTAP.** Existen sistemas *Hybrid Transactional/Analytical Processing* que intentan servir ambas cargas sobre el mismo dato (SQL Server con índices columnstore no agrupados sobre tablas OLTP es un ejemplo). Sirven para analítica operacional en tiempo real. **No reemplazan un Data Warehouse**, porque no resuelven historia, integración de múltiples orígenes ni conformidad de dimensiones. Mencionarlo en una entrevista muestra profundidad; proponerlo como reemplazo, lo contrario.

---

### 0.3 Qué es un pipeline de datos

Un **pipeline de datos** es un proceso automatizado que mueve datos desde uno o más orígenes hacia un destino, aplicando validaciones y transformaciones en el camino.

Definición correcta, y bastante inútil. Probemos con otra.

> Un pipeline es la respuesta a: *"¿cómo hago para que el dato que se generó en el sistema A esté disponible, confiable y con la forma correcta en el sistema B, todos los días, sin que nadie tenga que acordarse?"*

Las cuatro palabras que cargan el peso:

- **Disponible** — que esté ahí. Problema de extracción y carga.
- **Confiable** — que se pueda creer. Problema de validación.
- **Forma correcta** — que se pueda usar sin diez joins. Problema de modelado.
- **Sin que nadie se acuerde** — problema de orquestación.

Cada una de esas palabras es un paso de tu proyecto. Si un pipeline resuelve tres de las cuatro, no sirve: un pipeline con datos frescos, bien modelados y automatizados pero con datos incorrectos es **peor que no tener nada**, porque genera decisiones equivocadas con la confianza de un número en pantalla.

> **⚠️ La verdad incómoda del oficio:** el fallo más caro en BI no es el pipeline que se rompe. Es el que **sigue funcionando mientras entrega datos incorrectos**. Un pipeline caído lo nota todo el mundo en una hora. Uno que suma mal se descubre en la reunión de directorio tres meses después. Todo el Módulo 4 existe por esta frase.

---

### 0.4 ETL vs ELT

> ➕ **Tema adicional recomendado:** ETL vs ELT
> **Por qué necesito aprenderlo:** es la primera pregunta de arquitectura en casi toda entrevista de datos, y determina dónde vive tu lógica de transformación.
> **En qué parte del proyecto lo utilizaremos:** define por qué las transformaciones de este proyecto van en Stored Procedures dentro de SQL Server y no en una herramienta externa.

**ETL** = Extract → Transform → Load. Se extrae del origen, se transforma **fuera** de la base destino (en un servidor o herramienta intermedia: SSIS, Informatica, Talend), y se carga ya transformado.

**ELT** = Extract → Load → Transform. Se extrae, se carga **crudo** en el destino, y se transforma **dentro** del destino usando su motor SQL.

| | ETL | ELT |
|---|---|---|
| Dónde transforma | Motor intermedio | La base destino |
| El dato crudo | Se pierde | Se conserva |
| Requiere | Servidor ETL | Destino potente |
| Época dorada | 1990–2010 | 2015–hoy |
| Herramientas | SSIS, Informatica | dbt, Snowflake, BigQuery |

**Por qué cambió la industria hacia ELT:** cuando el almacenamiento era caro y los motores lentos, tenía sentido transformar antes y guardar solo lo necesario. Hoy el almacenamiento es barato y los motores son masivamente paralelos, así que conviene guardar todo crudo y transformar con la potencia del destino. Además — y esto es lo importante — **si conservás el dato crudo podés reprocesar cuando descubrís un error en la lógica.** Con ETL puro, ese dato ya no existe.

**Qué hace tu proyecto:** es **ELT**, con matices. Cargás `Sales.Orders` casi crudo a staging (extract + load), y recién después transformás con SQL dentro de SQL Server (transform). El único detalle es que origen y destino son el mismo motor, lo que hace la frontera menos visible que en la nube.

> **🎓 Respuesta de entrevista:** *"Es un ELT. Cargamos el dato del OLTP a staging preservando la estructura del origen, y las transformaciones ocurren después, en SQL, dentro del warehouse. Elegimos ELT porque nos deja reprocesar desde el dato crudo cuando cambia una regla de negocio, sin volver a golpear el sistema transaccional."*

---

### 0.5 La arquitectura medallón

> ➕ **Tema adicional recomendado:** arquitectura medallón (*medallion architecture*)
> **Por qué necesito aprenderlo:** es el vocabulario estándar para describir capas de un pipeline; lo vas a escuchar en cualquier equipo de datos moderno.
> **En qué parte del proyecto lo utilizaremos:** es el nombre de la arquitectura que estás construyendo, capa por capa.

Popularizada por Databricks, hoy es lenguaje común. Tres capas, nombradas por metales:

**🥉 Bronce (*bronze* / raw / staging)** — El dato tal como llegó. Sin limpiar, sin renombrar, sin reglas de negocio. Su único trabajo es **existir y ser fiel al origen**. Si el origen tiene una columna con nombre horrible, en bronce sigue con ese nombre.

**🥈 Plata (*silver* / cleansed / conformed)** — El dato validado, limpio, con tipos correctos, deduplicado e integrado entre orígenes. Acá empiezan a aplicarse reglas de negocio y nombres con sentido.

**🥇 Oro (*gold* / curated / presentation)** — El dato modelado para consumo: esquema estrella, agregados, métricas de negocio. Es lo que ve Power BI.

Tu proyecto mapea así:

```
WideWorldImporters   →  origen (fuera de las capas)
WWI_Staging          →  🥉 BRONCE   (Pasos 2 y 3)
Dimensiones + hechos →  🥇 ORO      (Paso 4)
Capa de resumen      →  🥇 ORO      (Paso 4)
Power BI             →  consumo     (Paso 6)
```

**Nota honesta:** en este proyecto la capa plata está comprimida dentro del paso a oro. Es una decisión razonable para un warehouse de un solo origen — la plata cobra valor real cuando hay que **integrar varios sistemas** y necesitás un lugar donde "cliente" signifique lo mismo viniendo del CRM que del ERP. Sabé que existe y sabé por qué la salteaste; eso es más valioso que haberla construido por inercia.

> **✅ Regla de oro de bronce:** *si podés reconstruir la capa desde el origen, no hace falta que sea perfecta. Si no podés, hacela inmutable.* Bronce es reconstruible por diseño, y por eso puede vivir con `TRUNCATE` + `INSERT` y en modo de recuperación SIMPLE.

---

### 0.6 Por qué nunca se consulta producción directamente

Esta es la restricción más importante del proyecto, y merece una defensa técnica en vez de un "porque sí".

**Razón 1 — Bloqueos.** Un `SELECT` sobre millones de filas toma bloqueos compartidos. En el nivel de aislamiento por defecto de SQL Server (`READ COMMITTED` con bloqueo), esos bloqueos hacen esperar a las escrituras. Tu reporte de ventas puede literalmente frenar una venta.

**Razón 2 — Competencia por recursos.** CPU, memoria y E/S son finitos. Una consulta analítica pesada desaloja del *buffer pool* las páginas calientes del OLTP, y de golpe las operaciones normales van a disco.

**Razón 3 — El dato se mueve bajo tus pies.** Corrés el reporte a las 10:00 y da 1.000 pedidos. Lo corrés a las 10:05 y da 1.003. ¿Cuál está bien? Los dos, y ninguno sirve para comparar. Un warehouse ofrece un **punto de corte consistente**.

**Razón 4 — Sin historia.** El OLTP guarda el estado *actual*. Cuando un cliente cambia de categoría, la anterior desaparece. Todas las ventas históricas de ese cliente se reatribuyen retroactivamente a la nueva categoría y **tus reportes del año pasado cambian solos**. (La solución tiene nombre — Slowly Changing Dimensions — y está en el Módulo 7.)

**Razón 5 — Acoplamiento.** Si veinte reportes apuntan a tablas de producción, nadie puede refactorizar producción. El pipeline es una **capa anticorrupción**: cambia el origen, ajustás la extracción, y los veinte reportes ni se enteran.

> **Traducción a lenguaje de desarrollo:** las razones 1 y 2 son *resource contention*, la 3 es falta de *snapshot isolation*, la 4 es falta de *temporal modeling*, y la 5 es **exactamente** el patrón *Anti-Corruption Layer* de Domain-Driven Design. Es el mismo motivo por el que no exponés tus entidades de EF Core directamente en la API.

---

### 0.7 El vocabulario que vas a necesitar

Estos términos aparecen sin traducción en documentación, entrevistas y equipos. Aprendelos en inglés — así los vas a encontrar cuando busques.

| Término | Qué significa |
|---|---|
| **Source system** | El sistema de origen. Acá: WideWorldImporters. |
| **Staging area** | Zona de aterrizaje del dato crudo. |
| **Data lineage** | Linaje: de dónde vino cada dato y qué le pasó en el camino. |
| **Data freshness** | Frescura: cuán viejo es el dato más reciente. |
| **Latency** | Retraso entre que algo ocurre y que aparece en el reporte. |
| **Batch processing** | Procesamiento por lotes, a intervalos. Lo que vas a hacer. |
| **Streaming** | Procesamiento continuo, evento por evento. |
| **Idempotency** | Correrlo N veces deja el mismo resultado que correrlo una. |
| **Backfill** | Recargar datos históricos tras un cambio o un error. |
| **Watermark** | Marca de hasta dónde se procesó, para cargas incrementales. |
| **Orchestration** | Coordinar qué corre, en qué orden y bajo qué condiciones. |
| **Data contract** | Acuerdo explícito de estructura y semántica entre productor y consumidor. |
| **Single source of truth** | Un único lugar autoritativo para cada métrica. |

---

## 💡 Conceptos clave

- **OLTP** — sistema optimizado para registrar transacciones; normalizado, muchas escrituras chicas.
- **OLAP** — sistema optimizado para analizar; desnormalizado, pocas lecturas enormes.
- **Pipeline de datos** — proceso automatizado que hace que el dato esté disponible, confiable y con forma útil en el destino.
- **ETL / ELT** — transformar antes de cargar vs cargar y transformar en el destino.
- **Arquitectura medallón** — bronce (crudo), plata (limpio), oro (modelado).
- **Capa anticorrupción** — capa intermedia que aísla a los consumidores de los cambios del origen.
- **Idempotencia** — propiedad de un proceso que puede repetirse sin efectos acumulados.

---

## 🔧 Ejemplo práctico

No hace falta escribir nada todavía. Hacé este ejercicio mental sobre el sistema en el que trabajás:

1. Nombrá **tres consultas** que alguien de negocio pida seguido.
2. Para cada una, contá cuántas tablas hay que tocar.
3. Preguntate: si esa consulta corriera cada 30 segundos desde un dashboard con 50 usuarios, ¿qué pasaría con el sistema?

Ese ejercicio, hecho en serio, es la mejor justificación de todo el libro. La mayoría de los desarrolladores que "no ven para qué sirve un warehouse" cambian de opinión en el punto 3.

---

## ⚠️ Errores comunes

**"Le pongo índices al OLTP y listo."** Los índices aceleran la lectura pero **penalizan cada escritura** — cada `INSERT` mantiene todos los índices de la tabla. Además no resuelven ni historia, ni consistencia del punto de corte, ni acoplamiento.

**"Uso una réplica de solo lectura y ya está."** Resuelve bloqueos y competencia de recursos (razones 1 y 2), pero no la 3, la 4 ni la 5. Una réplica sigue siendo un modelo OLTP: sin historia y con ocho joins. Es una mejora de infraestructura, no de arquitectura.

**"Empiezo por el dashboard, que es lo que se ve."** Termina en un dashboard que se alimenta de consultas frágiles contra producción. Cuando el volumen crece hay que rehacer todo. El orden de este libro es el orden de construcción por una razón.

**Confundir "capa" con "base de datos".** Las capas son un concepto lógico. Pueden vivir en bases distintas, en schemas distintos o incluso en la misma tabla con una columna de estado. Lo que importa son las garantías, no el envase.

**Copiar los nombres del origen a oro.** Bronce **debe** preservar los nombres del origen. Oro **debe** usar el lenguaje del negocio. Confundirlos deja un warehouse que solo entienden quienes conocen el sistema fuente — y ese es exactamente el problema que vinimos a resolver.

---

## ✅ Buenas prácticas

1. **Documentá la decisión, no solo el resultado.** Un README que dice "usamos full load" vale poco. Uno que dice "usamos full load porque la tabla tiene 73.595 filas y carga en segundos; migraríamos a incremental si superara el millón" vale mucho.
2. **Empezá por el caso más simple de punta a punta.** Una tabla, una dimensión, un gráfico. Un pipeline completo y chico enseña más que uno enorme a medias.
3. **Todo en control de versiones desde el día uno.** El SQL de un pipeline es código de producción: merece Git, revisión y despliegue reproducible.
4. **Nombrá las capas explícitamente** en schemas o bases (`WWI_Staging`, `etl`, `dw`). Un nombre bien puesto es documentación que no se desactualiza.
5. **Definí la frecuencia con el negocio, no con la tecnología.** "Cada cuánto necesitás el dato" es pregunta de negocio; "cada cuánto podemos" es de infraestructura. La primera manda.

---

## 🧠 Preguntas de comprensión

1. Un compañero propone: "en vez de todo esto, hagamos una vista en producción con los joins y que Power BI consulte la vista". ¿Cuáles de las cinco razones de la sección 0.6 quedan sin resolver?
2. ¿Por qué la capa bronce puede usar modelo de recuperación SIMPLE mientras producción usa FULL?
3. Un pipeline corre puntual todos los días, jamás falló y entrega un número de ventas 8% mayor al real. ¿Es un pipeline exitoso? Justificá.
4. Explicá con tus palabras por qué normalizar es correcto en OLTP e incorrecto en OLAP, sin usar las palabras "rápido" ni "lento".

---

## 📝 Ejercicios

**🟢 Básico.** Escribí en una hoja las siete capas de la sección 0.1 de memoria, y al lado de cada una el problema que resuelve. Sin mirar.

**🟡 Intermedio.** Tomá tres reportes reales de tu trabajo. Para cada uno: ¿qué tablas toca, con qué frecuencia se pide, y cuánto tarda? Ordenalos por (frecuencia × costo). El primero de la lista es el mejor candidato a warehouse — y ese razonamiento es exactamente el que se usa en la vida profesional.

**🔴 Avanzado.** Diseñá en papel la arquitectura medallón para un sistema con **dos** orígenes que tienen clientes en común con identificadores distintos. ¿En qué capa resolvés que "cliente 4471 del CRM" y "cliente ABC-88 del ERP" son la misma persona? ¿Por qué ahí y no antes ni después?

**🧠 Reto.** Tu gerente dice: *"El dashboard tiene que mostrar las ventas en tiempo real, con menos de 5 segundos de retraso."* Escribí una respuesta de máximo 200 palabras que (a) no diga que no, (b) explique el costo real de esa exigencia, (c) proponga al menos dos alternativas con su compromiso, y (d) haga una pregunta que revele si "tiempo real" es un requisito genuino o una expresión de deseo. Esta habilidad — traducir un pedido en requisitos — se paga mejor que el SQL.

---

## 🎓 Preguntas de entrevista

1. **¿Cuál es la diferencia entre OLTP y OLAP?** — No recites la tabla. Cerrá con: *"la diferencia de fondo es que optimizan objetivos opuestos: uno minimiza redundancia para escribir consistente, el otro la introduce para leer rápido."*
2. **¿ETL o ELT, y por qué?** — Ver sección 0.4.
3. **¿Por qué no consultar directo el sistema transaccional?** — Dá las cinco razones. Si solo decís "por rendimiento", quedás en la mitad.
4. **¿Qué es idempotencia y por qué importa en ETL?** — Porque los procesos fallan y hay que reintentarlos. Sin idempotencia, cada reintento es una decisión de riesgo.
5. **¿Qué es la arquitectura medallón?** — Las tres capas y, sobre todo, la garantía de cada una.
6. **Contame de un pipeline que hayas construido.** — Estructurá: problema de negocio → origen → capas → validaciones → orquestación → consumo → **una decisión difícil que tomaste y por qué**. Esa última parte es la que distingue a un candidato.

---

## 📌 Resumen

- Existen dos mundos, OLTP y OLAP, con objetivos **opuestos**; ningún diseño sirve para ambos.
- El pipeline es el puente: hace que el dato esté **disponible, confiable, con forma útil y sin intervención humana**.
- Cada capa existe porque la anterior dejó un problema. El orden es causal, no arbitrario.
- **ELT** es el patrón moderno y es el de este proyecto: cargar crudo, transformar en el destino, poder reprocesar.
- **Medallón**: bronce fiel al origen, plata limpio e integrado, oro modelado para consumo.
- No se consulta producción por bloqueos, recursos, inconsistencia, falta de historia y acoplamiento.
- Un pipeline confiable pero incorrecto es **peor** que ninguno.

---

## 🗂️ Flashcards

| Pregunta | Respuesta |
|---|---|
| ¿Qué significa OLTP? | Online Transaction Processing — sistema que registra transacciones. |
| ¿Qué significa OLAP? | Online Analytical Processing — sistema que analiza datos. |
| ¿Diferencia de fondo entre ambos? | Optimizan objetivos opuestos: minimizar vs introducir redundancia. |
| ¿Qué es ELT? | Extract, Load, Transform — cargar crudo y transformar en el destino. |
| ¿Ventaja principal de ELT sobre ETL? | Conserva el dato crudo, y por lo tanto permite reprocesar. |
| ¿Las tres capas del medallón? | Bronce (crudo), plata (limpio/integrado), oro (modelado). |
| ¿Qué garantiza bronce? | Fidelidad al origen. No limpia ni renombra. |
| ¿Qué es idempotencia? | Que correr el proceso N veces dé el mismo resultado que una vez. |
| ¿Cinco razones para no consultar producción? | Bloqueos, recursos, inconsistencia, sin historia, acoplamiento. |
| ¿Qué es una capa anticorrupción? | Capa que aísla a los consumidores de los cambios del origen. |
| ¿Qué es data freshness? | Cuán reciente es el dato más nuevo disponible. |
| ¿Qué es un backfill? | Recarga de datos históricos tras un cambio o error. |
| ¿Peor fallo posible en un pipeline? | Que funcione sin errores entregando datos incorrectos. |

---

## ☑️ Checklist antes de avanzar

- [ ] Puedo explicar OLTP vs OLAP sin leer.
- [ ] Puedo nombrar las cinco razones para no consultar producción.
- [ ] Entiendo por qué el orden de las capas es causal.
- [ ] Sé qué es ELT y por qué este proyecto lo es.
- [ ] Puedo nombrar las tres capas del medallón y la garantía de cada una.
- [ ] Entiendo que un pipeline incorrecto es peor que ninguno.
- [ ] Puedo explicar idempotencia con un ejemplo propio.

---

## 📋 Examen del Módulo 0

### Selección múltiple

**1.** ¿Cuál NO es una razón válida para separar el sistema analítico del transaccional?
a) Las consultas analíticas toman bloqueos que frenan escrituras
b) El OLTP no conserva historia de los cambios
c) SQL Server no puede ejecutar consultas con agregación
d) Reportes apuntando a producción impiden refactorizarla

**2.** En la arquitectura medallón, ¿qué debería pasar con una columna del origen llamada `cust_nm_1` en la capa bronce?
a) Renombrarse a `CustomerName`
b) Mantenerse como `cust_nm_1`
c) Eliminarse por poco descriptiva
d) Dividirse en dos columnas

**3.** ¿Cuál describe mejor ELT?
a) Transformar antes de cargar, para ahorrar espacio
b) Cargar crudo y transformar con el motor del destino
c) Extraer, cargar y transformar, siempre en herramientas distintas
d) Un sinónimo moderno de ETL

**4.** ¿Cuál es la consecuencia más grave de un pipeline no idempotente?
a) Corre más lento
b) Un reintento tras un fallo puede duplicar datos
c) Ocupa más disco
d) No se puede automatizar

**5.** Una réplica de solo lectura de producción resuelve:
a) Los cinco problemas de la sección 0.6
b) Bloqueos y competencia de recursos, nada más
c) Solo la falta de historia
d) Nada, es equivalente a consultar producción

### Verdadero / Falso

**6.** La capa bronce debe tener los datos ya limpios y validados.
**7.** La normalización es un defecto de diseño de los sistemas OLTP.
**8.** Un pipeline que nunca falló es necesariamente un buen pipeline.
**9.** La arquitectura medallón obliga a usar tres bases de datos distintas.
**10.** ELT permite reprocesar datos históricos sin volver a consultar el origen.

### Preguntas abiertas

**11.** Explicá por qué "le agrego índices al OLTP" no reemplaza a un Data Warehouse. Mencioná al menos tres problemas que no resuelve.

**12.** Un cliente cambia de categoría de "Novelty Shop" a "Wholesaler". Describí qué le pasa a los reportes históricos si se consultan directo del OLTP, y por qué eso es un problema de negocio y no solo técnico.

### Análisis de escenario

**13.** Una empresa tiene un dashboard que consulta producción con una vista de nueve joins. Funciona bien. La empresa crece y triplica su volumen en un año. Enumerá, en orden de aparición, los tres síntomas que van a observar, y qué van a intentar primero (que no va a alcanzar) antes de aceptar que necesitan un warehouse.

### Diseño

**14.** Diseñá en texto plano el flujo de capas para: una cadena de farmacias con 40 sucursales, cada una con su propio POS que sincroniza a una base central cada noche, que quiere un dashboard de ventas por sucursal, producto y día. Indicá qué capa resuelve qué, y en cuál aparece el problema más difícil.

---

*(Las soluciones de todos los exámenes del Volumen I están al final del volumen, en la sección 🔐 Soluciones.)*

