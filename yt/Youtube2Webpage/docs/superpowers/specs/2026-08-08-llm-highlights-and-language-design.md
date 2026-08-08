# Youtube2Webpage v2: selección de momentos clave por LLM + fallback Whisper

**Fecha:** 2026-08-08 (revisado tras sesión de grilling)
**Estado:** Aprobado, pendiente de implementación

Términos de dominio (Momento clave, Idioma original, Idioma de subtítulos
preferido) definidos en [CONTEXT.md](../../../CONTEXT.md).

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
- No contempla vídeos sin subtítulos disponibles (ni manuales ni automáticos).

## Objetivos

1. Sustituir "una captura por línea" por "una captura por **Momento clave**"
   (cambio de sub-tema o inicio de contenido nuevo), decidido por un LLM (Claude)
   que analiza la transcripción completa y devuelve solo **timestamps** — nunca
   texto generado (ver "Decisión: el LLM no genera texto" más abajo).
2. Cubrir vídeos sin subtítulos disponibles con transcripción local vía Whisper
   (modelo `turbo`, auto-detección de idioma) en vez de abortar.
3. Soportar vídeos de 2-4 horas en una sola llamada al LLM (sin troceo por
   ventanas — ver "Decisión: sin troceo por ahora").
4. Aplicar las 5 mejoras de robustez ya acordadas: límite de calidad de vídeo
   (720p), cookies de navegador, comprobación de errores de `yt-dlp`, idioma de
   subtítulos preferido explícito, y selección de capturas por Momento clave en
   vez de por línea.

## No objetivos

- **Traducción**: por ahora (2026-08-08) el script NO traduce nada. La usuaria
  solo trabaja en inglés y español. Si en el futuro se necesita un tercer idioma,
  se añade como paso explícito aparte — no antes (YAGNI).
- **Troceo por ventanas para vídeos muy largos (8h+)**: fuera de alcance por
  ahora. Ver "Decisión: sin troceo por ahora".
- **Localización de la interfaz**: los textos fijos del HTML (título, "Source:",
  etc.) quedan siempre en inglés, sin lógica de idioma.
- No se implementa una suite de tests unitarios formal: es un script personal que
  envuelve herramientas externas (yt-dlp/ffmpeg/whisper/claude); el valor real
  está en probarlo end-to-end.
- No se gestiona el proyecto Electron anidado en `Youtube2Webpage/` (repo
  distinto, no relacionado con este script).

## Decisiones clave de esta sesión

### El LLM no genera texto, solo señala timestamps

El texto mostrado en la web es siempre una **cita literal** de la transcripción
original (vtt de yt-dlp, o vtt generado por Whisper) en el punto del Momento
clave. El LLM únicamente identifica *qué* timestamps son Momentos clave.

Motivo: evita que el modelo parafrasee o cite mal el contenido, reduce el tamaño
de la respuesta JSON, y hace que "no traducir" sea automático — no hay paso de
traducción que desactivar condicionalmente, simplemente no existe ese paso.

### Sin troceo por ventanas, por ahora

Cálculo real sobre el vídeo de referencia (1h 02m): **64.5K caracteres** de
transcripción única tras dedupe. Extrapolado: ~129K para 2h, ~258K para 4h.
El contexto de Claude es ~200K tokens (~800K caracteres). Un vídeo de 4h cabe
de sobra en una sola llamada.

Umbral de seguridad: **500K caracteres**. Si la transcripción lo supera, el
script avisa y aborta (sin generar la web) en vez de trocear — cubre el caso
real de uso (2-4h) sin construir fusión/dedupe de ventanas para un caso (8h+)
no solicitado.

### Fallback a Whisper si no hay subtítulos

Si `yt-dlp` no encuentra ningún `.vtt` (ni manual ni automático) para el vídeo,
el script transcribe el audio localmente con `whisper` (CLI `openai-whisper`,
modelo `turbo`, instalado en `/Users/marta/.local/bin/whisper`), pasándole el
vídeo ya descargado directamente (`whisper` extrae el audio vía ffmpeg
internamente) con `--output_format vtt` y sin fijar `--language` (auto-detección).
El `.vtt` resultante entra al mismo pipeline de parseo que un `.vtt` de yt-dlp.

No se pregunta el idioma hablado al usuario de antemano — es independiente de
la elección de idioma de subtítulos preferido, que solo aplica cuando sí hay
pistas de yt-dlp entre las que elegir.

### Sin guardrail de separación mínima entre momentos

Se decidió no añadir una separación mínima artificial entre Momentos clave
consecutivos (YAGNI) — se confía en que la propia definición de Momento clave
(cambio de sub-tema) evita capturas duplicadas por proximidad. Si en la
práctica el LLM genera momentos demasiado juntos, se revisita entonces.

## Diseño

### Flujo de datos

```
URL + slug
  → preguntar idioma de subtítulos preferido (interactivo, p.ej. "es" o "en")
  → yt-dlp: vídeo (cap 720p) + subtítulos, con cookies de Chrome y sleep entre
    peticiones. Comprobar código de salida; abortar con mensaje claro si falla.
  → ¿hay algún .vtt disponible (manual o auto)?
      NO → transcribir con whisper (modelo turbo, auto-detección de idioma,
           --output_format vtt) sobre el vídeo ya descargado
      SÍ → usar el .vtt del idioma preferido si existe, si no el que haya
  → parsear .vtt a lista de {timestamp, text} (dedupe de líneas consecutivas
    repetidas, igual que ahora, pero como estructura de datos, no HTML directo)
  → construir transcripción en texto plano con timestamps
  → si transcripción > 500K caracteres: avisar y abortar (sin troceo)
  → analyze_with_claude(transcript):
      - una sola llamada `claude -p ... --output-format json`
      - el prompt pide: identificar los timestamps de los Momentos clave
        del discurso (cambios de sub-tema / contenido nuevo), sin número fijo
      - respuesta esperada: JSON estricto, array de timestamps (segundos)
      - parsear `.result` como JSON; si falla el parseo o el array está
        vacío, abortar mostrando la salida cruda en stderr
  → por cada timestamp seleccionado: buscar el texto literal de la
    transcripción en ese punto + una captura ffmpeg
  → generar index.html (interfaz fija en inglés, texto citado literal)
```

### Componentes (subs dentro de `yt-to-webpage.pl`)

No se divide en múltiples ficheros — con las nuevas subs el script queda en
torno a 200-250 líneas, dentro del rango típico para un script personal.

- `prompt_subtitle_language()` — pregunta el idioma de subtítulos preferido
- `download_video_and_subs($url, $lang)` — yt-dlp con
  `-f "bv*[height<=720]+ba/b[height<=720]"`, `--cookies-from-browser chrome`,
  `--sleep-requests 1`, `--sub-lang $lang`; comprueba `$?` y aborta si falla
- `ensure_transcript($video_file)` — si no hay `.vtt` tras la descarga, invoca
  `whisper "$video_file" --model turbo --output_format vtt`; devuelve la ruta
  del `.vtt` a usar (el de yt-dlp o el de whisper)
- `parse_vtt($vtt_path)` — devuelve `@moments` de `{timestamp, text}` (mismo
  dedupe de líneas consecutivas que la versión actual)
- `analyze_with_claude(\@moments)` — construye el prompt, invoca
  `claude -p ... --output-format json`, valida y devuelve la lista de
  timestamps seleccionados como Momentos clave
- `capture_screenshot($timestamp, $video_file)` — ffmpeg por cada Momento
  clave; si falla una captura puntual, avisa por stderr y continúa
- `generate_html(\@selected_moments, $url)` — lista de `<li>` con imagen +
  texto literal + enlace al minuto, interfaz fija en inglés

### Contrato JSON con el LLM

Petición: transcripción completa con timestamps (texto plano).

Respuesta esperada (dentro de `.result` del `--output-format json` de Claude):

```json
[125, 340, 812, 1290]
```

Array de timestamps en segundos — sin texto, sin objetos anidados.

### Manejo de errores

| Fallo | Acción |
|---|---|
| `yt-dlp` código de salida != 0 | Abortar, mensaje claro en stderr |
| Sin `.vtt` tras descarga | Fallback a `whisper` (ver diseño) |
| `whisper` también falla o no produce `.vtt` | Abortar, mensaje claro |
| Transcripción > 500K caracteres | Abortar, aviso de tamaño (sin troceo) |
| `claude -p` código de salida != 0, salida vacía, o JSON no parseable | Abortar, volcar salida cruda en stderr |
| Array de timestamps vacío | Abortar (no generar página vacía) |
| `ffmpeg` falla en una captura puntual | Avisar por stderr, saltar esa imagen, continuar |

### Testing

Validar end-to-end contra el vídeo corto de `example/` (el que ya usa el
`Makefile`) antes de lanzarlo contra vídeos largos reales, para confirmar que
el pipeline completo (descarga → parseo/whisper → LLM → capturas → HTML)
funciona. Adicionalmente, probar manualmente el camino de fallback de Whisper
con algún vídeo corto sin subtítulos.

## Riesgos / preguntas abiertas

- **No determinismo del LLM**: el número de Momentos clave puede variar entre
  ejecuciones del mismo vídeo. Aceptado (sin guardrail de separación mínima).
- **Fiabilidad del JSON**: el parseo debe ser tolerante a texto extra alrededor
  del array pedido (extraer el primer bloque `[...]`), o el prompt debe ser
  muy estricto sobre "responde solo con JSON".
- **Dependencia de Whisper local**: el fallback asume `whisper` (openai-whisper,
  modelo `turbo`) ya instalado en el sistema; el script no lo instala ni lo
  valida más allá de comprobar que el comando existe.
- **Umbral de 500K caracteres sin troceo**: cubre 2-4h con margen amplio: si
  en el futuro se procesan vídeos de 8h+, este umbral se revisita.
