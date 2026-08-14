# Guía de estudio — "De OLTP a Dashboard"

Libro de ~82.000 palabras sobre este proyecto: 3 volúmenes, 16 módulos, en español.
Cubre los 6 pasos del pipeline, con exámenes, soluciones en sección aparte,
proyecto final y apéndices.

**Versión publicada (se abre desde cualquier máquina):**
https://claude.ai/code/artifact/142bc7c0-cc5b-483e-86bf-42ad029b8a3a

## Qué hay acá

| Archivo | Qué es |
|---|---|
| `00-portada.md` … `17-proyecto-apendices.md` | Las fuentes. Se concatenan **por orden de número de archivo** |
| `build.js` | Generador Markdown → HTML (Node + `marked`) |
| `package.json` | La única dependencia es `marked` |

El HTML generado **no está versionado** (ver `.gitignore`): pesa ~720 KB, se
regenera en segundos y cambiaría entero en cada build, volviendo los diffs
ilegibles. La fuente es el `.md`; el HTML es el compilado.

## Regenerar

```bash
cd docs/libro
npm install
node build.js
```

Produce dos salidas:

- `guia-pipeline-datos-bi.html` — documento completo y autocontenido. Se abre sin
  conexión y se imprime a PDF desde el navegador.
- `guia-web.html` — solo el fragmento (`<title>` + contenido), para publicar como
  artifact, donde el wrapper lo pone la plataforma.

## Agregar contenido

Un módulo nuevo es un archivo `.md` más, con prefijo numérico en la posición que
le corresponda. `build.js` los toma por orden de nombre; no hay índice manual que
mantener — el índice de navegación se arma solo desde los `h1` y `h2`.

Si se agrega un módulo, actualizar también `01-indice.md`, que es el índice
general que lee la persona (distinto del de navegación, que se genera).

## Republicar

Para conservar el mismo enlace hay que pasar la URL de arriba al publicar. Si no,
se genera un artifact nuevo con otra dirección.
