# De OLTP a Dashboard

## Guía completa de construcción de un pipeline de datos con SQL Server, Data Warehouse y Power BI

**Proyecto de referencia:** WideWorldImporters → Staging → Data Warehouse → Power BI

---

> *"No quiero aprender solamente cómo hacer un Stored Procedure. Quiero poder explicar por qué usamos un Stored Procedure en esta parte del pipeline, cómo validamos los datos, cómo controlamos errores, cómo automatizamos su ejecución y cómo esos datos terminan alimentando nuestro modelo dimensional y posteriormente Power BI."*

Esa frase es el criterio con el que está escrito cada capítulo de este libro.

---

## Cómo usar esta guía

Este no es un manual de referencia para consultar salteado. Es un **curso secuencial**: cada módulo asume el anterior. El orden de los capítulos es el orden en que se construye el pipeline, y eso no es casualidad — es la única forma de que entiendas *por qué* cada capa existe, ya que cada una nace de un problema que dejó la anterior.

**Tres reglas de uso:**

1. **No leas el código antes que el problema.** Cada capítulo presenta primero la pregunta de negocio o el fallo técnico, y solo después la solución. Si saltás directo al SQL vas a poder copiarlo, pero no vas a poder defenderlo en una entrevista.

2. **Hacé los ejercicios antes de mirar las soluciones.** Los exámenes al final de cada volumen tienen las respuestas en una sección aparte, separada a propósito. El valor está en el intento fallido, no en la respuesta.

3. **Escribí el SQL vos.** Todo el código de este libro está probado y funciona. Justamente por eso es peligroso: leerlo produce una sensación de comprensión que no sobrevive a una hoja en blanco.

### Símbolos que vas a encontrar

| Símbolo | Significado |
|---|---|
| 🎯 | Objetivos del capítulo |
| 📖 | Teoría |
| 💡 | Conceptos clave — el vocabulario de la industria |
| 🔧 | Ejemplo práctico sobre WideWorldImporters |
| 💻 | Código |
| ⚠️ | Errores comunes |
| ✅ | Buenas prácticas |
| 🧠 | Preguntas de comprensión |
| 📝 | Ejercicios (🟢 básico · 🟡 intermedio · 🔴 avanzado · 🧠 reto) |
| 🎓 | Preguntas de entrevista |
| 📌 | Resumen |
| 🗂️ | Flashcards |
| ☑️ | Checklist antes de avanzar |
| ➕ | Tema adicional recomendado (fuera de los seis pasos, con justificación) |

### Convención sobre el código

Todo el SQL de este libro está escrito para **SQL Server 2016 o superior** y probado contra la versión completa de `WideWorldImporters`. Los números que aparecen (73.595 pedidos, 231.412 líneas, 663 clientes, 227 productos) son los reales de esa base — si tus consultas devuelven otra cosa, algo cambió y vale la pena averiguar qué.

---

## Los seis pasos

Todo el libro gira alrededor de esta ruta. Si en algún momento te perdés, volvé a esta tabla y ubicá dónde estás.

| Paso | Tema | Módulos |
|------|------|---------|
| **1** | Restaurar WideWorldImporters | 1 |
| **2** | Staging + Stored Procedure con validaciones | 2, 3, 4 |
| **3** | Automatizar con SQL Server Agent Job | 5 |
| **4** | Capa de resumen + esquema estrella | 6, 7, 8, 9 |
| **5** | Automatizar la capa de resumen | 10 |
| **6** | Dashboard en Power BI | 11, 12, 13, 14, 15 |

Y este es el flujo que vas a haber construido cuando termines:

```
WideWorldImporters  (OLTP, producción — nunca se toca)
        │
        ▼
   Staging / Bronce  ── validaciones ──► etl.ValidationLog
        │                                etl.LoadBatch
        ▼
  Transformaciones
        │
        ▼
   Dimensiones ──► Tabla de hechos  (Data Warehouse / Oro)
        │
        ▼
   Capa de resumen  (agregados)
        │
        ▼
     Power BI  ──► DAX ──► Dashboard
        │
        └── todo orquestado por SQL Server Agent
```

