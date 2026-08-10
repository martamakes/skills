# Youtube2Webpage

Genera una página web navegable (transcripción + capturas) a partir de un vídeo de
YouTube o de un vídeo local, usando un LLM para decidir qué momentos del discurso
merecen una captura.

## Language

**Momento clave**:
Un cambio de sub-tema o el inicio de una unidad de contenido nueva dentro del
discurso (p.ej. pasa de explicar un concepto a otro, o arranca una demo/ejemplo
nuevo). No es una frase suelta ni una cita puntual dentro del mismo bloque temático.
_Avoid_: momento importante, punto destacado, highlight

**Idioma original**:
El código de idioma del fichero `.vtt` que descarga yt-dlp (p.ej. `en` en
`video.en.vtt`). No se intenta detectar el idioma real del audio; si el vídeo
está doblado y los subtítulos corresponden al doblaje, el "idioma original" es
el del doblaje, no el del audio primario.
_Avoid_: idioma del vídeo, idioma del audio

**Idioma de subtítulos preferido**:
El idioma que el usuario pide de forma interactiva al arrancar el script, usado
solo para elegir qué pista de subtítulos descargar cuando el vídeo tiene varias
disponibles (p.ej. `.en.vtt` y `.es.vtt`). No implica traducción — si no hay
pista en ese idioma, se usa la que haya, o se cae al fallback de Whisper si no
hay ninguna. Solo aplica cuando la **Fuente de vídeo** es una URL de YouTube —
un **Vídeo local** no tiene pistas de subtítulos que elegir, así que la pregunta
no se hace y siempre se transcribe con Whisper.
_Avoid_: idioma destino, idioma de salida, idioma de traducción

**Fuente de vídeo**:
De dónde viene el vídeo a procesar: una URL de YouTube o un **Vídeo local**.
Determina cómo se obtienen el vídeo y los subtítulos, pero no afecta al resto
del pipeline (selección de momentos clave, capturas).
_Avoid_: origen, input

**Vídeo local**:
Un fichero de vídeo ya existente en disco, nunca subido a YouTube (p.ej. un
documental propio). Se referencia por su ruta absoluta sin copiarlo al
directorio del proyecto. Al no tener subtítulos de YouTube que descargar,
siempre se transcribe con Whisper. La página generada muestra su nombre de
fichero como texto plano (sin enlace de reproducción, a diferencia de una
**Fuente de vídeo** de YouTube).
_Avoid_: vídeo propio, fichero de vídeo

## Relationships

- Un **Vídeo** tiene exactamente una **Fuente de vídeo** (URL de YouTube o **Vídeo local**)
- Un **Vídeo** se descompone en una secuencia de **Momentos clave**
- Cada **Momento clave** tiene exactamente una **Captura** (imagen) asociada
- El LLM solo señala el **timestamp** de cada **Momento clave**; el texto mostrado
  siempre es una cita literal de la transcripción original en ese punto — el LLM
  nunca genera ni reescribe el texto mostrado

## Example dialogue

> **Dev:** "¿Capturamos también cuando dice una frase potente dentro del mismo tema?"
> **Domain expert:** "No — un **Momento clave** es solo cuando cambia de sub-tema o
> empieza contenido nuevo, no una cita suelta dentro del mismo bloque."

## Flagged ambiguities

- **Traducción**: por ahora (2026-08-08) el script NO traduce nada. La usuaria
  solo trabaja en inglés y español, así que no hace falta un paso de traducción.
  Si en el futuro se necesita un tercer idioma, se añadirá como un paso explícito
  aparte — no antes (YAGNI). Resuelto: "idioma destino" se redefine como
  **Idioma de subtítulos preferido**, sin implicar traducción.
