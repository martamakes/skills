# Youtube2Webpage v2: selección de momentos clave por LLM + idioma de salida

**Fecha:** 2026-08-08
**Estado:** Aprobado, pendiente de implementación

## Contexto

`yt-to-webpage.pl` genera una web con transcripción + capturas a partir de un vídeo
de YouTube. La versión actual tiene problemas serios con vídeos largos:

- Descarga el vídeo sin límite de calidad.
- Genera **una captura de ffmpeg por cada línea única de subtítulo**. Para un vídeo
  de referencia de 1h 02m, esto son **1758 capturas** (~1 cada 2 segundos), lo que
  produce una página inmanejable y un proceso de generación de 30-90 minutos.
- No usa cookies de sesión, por lo que YouTube puede devolver `HTTP 429`.
- No fija idioma de subtítulos: coge el primer `.vtt` que encuentre con `glob`.
- No comprueba el código de salida de `yt-dlp`; si la descarga falla, el script
  sigue y falla más adelante de forma confusa.

## Objetivos

1. Sustituir "una captura por línea" por "una captura por momento importante del
   discurso", decidido por un LLM (Claude) que analiza la transcripción completa.
2. Preguntar al usuario el idioma de salida de la web en cada ejecución, y traducir
   con el LLM si el idioma pedido difiere del idioma original de los subtítulos.
3. Aplicar las 5 mejoras de robustez ya acordadas: límite de calidad de vídeo,
   cookies de navegador, comprobación de errores de `yt-dlp`, idioma de subtítulos
   explícito, y (sustituido por selección LLM) espaciado de capturas.

## No objetivos

- No se implementa una suite de tests unitarios formal: es un script personal que
  envuelve herramientas externas (yt-dlp/ffmpeg/claude); el valor real está en
  probarlo end-to-end.
- No se soporta traducción de audio/voz, solo del texto mostrado en la web.
- No se gestiona el proyecto Electron anidado en `Youtube2Webpage/` (parece un repo
  distinto, no relacionado con este script).

## Diseño

### Flujo de datos

```
URL + slug
  → preguntar idioma destino (interactivo, p.ej. "es" o "en")
  → yt-dlp: vídeo (cap 720p) + subtítulos, con cookies de Chrome y sleep entre
    peticiones. Comprobar código de salida; abortar con mensaje claro si falla.
  → parsear .vtt a lista de {timestamp, text} (dedupe de líneas consecutivas
    repetidas, igual que ahora, pero sin escribir HTML todavía)
  → construir transcripción en texto plano con timestamps
  → analyze_with_claude(transcript, idioma_destino):
      - Si transcript < ~150K caracteres: una sola llamada `claude -p`
      - Si es mayor (vídeos de varias horas): trocear en ventanas de tiempo
        con solape, una llamada por ventana, fusionar resultados y ordenar
        cronológicamente
      - El prompt pide: identificar puntos de inflexión temática relevantes
        del discurso (sin número fijo, lo decide el modelo), y devolver el
        texto de cada momento ya traducido al idioma destino si aplica
      - Respuesta esperada: JSON estricto, array de
        {timestamp_seconds: number, text: string}
      - Parsear con `--output-format json`, extraer `.result`, parsear ese
        contenido como JSON. Si falla el parseo o el array está vacío,
        abortar mostrando la salida cruda en stderr.
  → por cada momento seleccionado: una captura ffmpeg (antes: una por línea)
  → generar index.html con textos ya traducidos e interfaz localizada al
    idioma destino
```

### Componentes (subs dentro de `yt-to-webpage.pl`)

No se divide en múltiples ficheros — con las nuevas subs el script queda en
torno a 200-250 líneas, dentro del rango típico para un script personal.

- `prompt_language()` — pregunta el idioma destino al arrancar (STDIN)
- `download_video_and_subs($url)` — yt-dlp con `-f "bv*[height<=720]+ba/b[height<=720]"`,
  `--cookies-from-browser chrome`, `--sleep-requests 1`; comprueba `$?` tras
  el `system()`/backtick y aborta con mensaje si != 0
- `parse_vtt($vtt_path)` — devuelve `@moments` de `{timestamp, text}` (misma
  lógica de dedupe que la versión actual, pero como estructura de datos, no
  como HTML directamente)
- `analyze_with_claude(\@moments, $target_lang)` — construye el prompt,
  invoca `claude -p ... --output-format json`, valida y devuelve la lista
  final de momentos seleccionados (ya traducidos)
- `capture_screenshot($timestamp, $video_file)` — ffmpeg por cada momento
  seleccionado; si falla una captura puntual, avisa por stderr y continúa
  sin abortar el resto
- `generate_html(\@selected_moments, $url, $target_lang)` — igual estructura
  que ahora (lista de `<li>` con imagen + texto + enlace al minuto), con
  textos ya traducidos y strings de interfaz (p.ej. "Youtube transcript")
  localizados al idioma destino

### Contrato JSON con el LLM

Petición: transcripción completa con timestamps + idioma destino.

Respuesta esperada (dentro de `.result` del `--output-format json` de Claude):

```json
[
  { "timestamp_seconds": 125, "text": "Texto traducido del momento clave..." },
  { "timestamp_seconds": 340, "text": "..." }
]
```

### Manejo de errores

| Fallo | Acción |
|---|---|
| `yt-dlp` código de salida != 0 | Abortar, mensaje claro en stderr |
| `claude -p` código de salida != 0, salida vacía, o JSON no parseable | Abortar, volcar salida cruda en stderr para depurar |
| Array de momentos vacío | Abortar (no generar página vacía) |
| `ffmpeg` falla en una captura puntual | Avisar por stderr, saltar esa imagen, continuar |

### Testing

Validar end-to-end contra el vídeo corto de `example/` (el que ya usa el
`Makefile`) antes de lanzarlo contra vídeos largos reales, para confirmar que
el pipeline completo (descarga → parseo → LLM → capturas → HTML) funciona.

## Riesgos / preguntas abiertas

- **No determinismo del LLM**: el número de momentos seleccionados puede variar
  entre ejecuciones del mismo vídeo. Aceptado como parte del diseño (el usuario
  eligió explícitamente no fijar un número).
- **Coste/latencia**: cada ejecución lanza al menos una llamada a `claude -p`
  sobre una transcripción de varios miles de palabras. Para vídeos muy largos
  con troceo en ventanas, esto son varias llamadas secuenciales.
- **Fiabilidad del JSON**: los LLMs a veces devuelven texto extra alrededor del
  JSON pedido. El parseo debe ser tolerante (extraer el primer bloque `[...]`)
  o el prompt debe ser muy estricto sobre "responde solo con JSON".
