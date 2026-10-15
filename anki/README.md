# Tipos de nota de Anki

Una **nota** contiene campos; su **tipo de nota** define esos campos y las
plantillas que generan tarjetas. Una **baraja** determina dónde se repasan.
Este complemento utiliza dos tipos internos automáticos, no perfiles ni
ajustes configurables. Ambos se crean al primer envío si faltan y se validan
sin sobrescribir tipos existentes. Las instrucciones manuales son opcionales.

## Diseño de lectura

Los dos tipos comparten un diseño minimalista: fondo marfil, texto oscuro,
acento verde discreto, alineación izquierda y una columna de hasta 640 px.
La tipografía y el espaciado se adaptan a móvil; el modo nocturno de Anki cambia
a una paleta oscura con contraste equivalente. No se descargan fuentes ni se
ejecuta JavaScript. Los campos opcionales vacíos no dejan etiquetas sueltas.

Learn reserva el anverso para la pregunta. En el reverso destacan la respuesta
y la explicación, seguidas de la cita comprobada y su procedencia. Los bloques
«Explicación» y «Cita del libro» tienen títulos discretos y separación adicional
para distinguir la explicación generada de la cita literal. La selección
original se puede desplegar, sin mostrar el contexto completo ni PluginID.
Vocab prioriza significado y frase con hueco; el reverso revela la expresión,
pronunciación y sus extras opcionales (imagen/audio/fuente). Encabezado,
definición y posición inicial de la frase se conservan al revelar; la palabra
y el IPA aparecen debajo del ejercicio, nunca insertados antes de él.

La definición visual compartida vive en
[`card_design.lua`](../AnkiFlashcards.koplugin/card_design.lua); los JSON de esta
carpeta contienen el mismo diseño, verificado por pruebas. Editar estos archivos
no sobrescribe tipos ya existentes: los cambios en Anki se aplican expresamente
a sus plantillas y CSS, sin renombrar campos, recrear notas ni alterar repasos.

## KOReader Vocabulary — Anki Vocab

**Tipo: Cloze**, con una plantilla que utiliza `{{cloze:Text}}`. No lo crees
como Basic/normal: el filtro cloze necesita el tipo adecuado.

| Orden | Campo | Contenido |
|---|---|---|
| 1 | `Phrase` | Palabra/expresión canónica; primer campo para duplicados. |
| 2 | `IPA` | Pronunciación apropiada al idioma. |
| 3 | `Definition` | Definición según el contexto. |
| 4 | `Synonyms` | Sinónimos. |
| 5 | `Text` | Frase con `{{c1::...}}`. |
| 6 | `Source` | Referencia; puede ser una URL de diccionario. |
| 7 | `ImageFront` | Referencia HTML a la imagen del anverso, opcional. |
| 8 | `ImageBack` | Referencia HTML a la imagen del reverso, opcional. |
| 9 | `Sound` | Referencia `[sound:archivo.mp3]`, opcional. |

El anverso muestra definición, sinónimos, imagen y hueco. El reverso revela
la expresión y añade pronunciación, imagen, fuente y audio cuando existan.

### Crear con AnkiConnect

Desde la raíz del repositorio:

```bash
curl http://127.0.0.1:8765 -H 'Content-Type: application/json' \
  --data-binary @anki/create-note-type.json
```

El archivo es JSON válido y declara `isCloze: true`.

### Crear manualmente en Anki

1. **Herramientas → Gestionar tipos de nota → Añadir**.
2. Elige **Cloze / Respuesta anidada**, no Basic.
3. Nómbralo `KOReader Vocabulary`.
4. En **Campos**, adapta los campos a la lista anterior, respetando nombres
   y orden; elimina los campos de la plantilla base que no correspondan.
5. En **Tarjetas**, copia `Front`, `Back` y `css` desde `create-note-type.json`.

Si tienes notas en un tipo distinto, como `English`, no se borran ni convierten.
Esta versión envía Vocab a `KOReader Vocabulary`; no tiene un selector de tipos.
No renombres ni conviertas tipos con notas sin comprobar antes su estructura.

### Actualizar el nombre anterior `Vocabulary`

Si ya tenías el tipo `Vocabulary` de esta copia, no crees uno nuevo:

1. En Anki, **Gestionar tipos de nota → Vocabulary → Renombrar**.
2. Cambia el nombre a **KOReader Vocabulary**. El ID del tipo, sus notas y
   la programación de repasos se conservan; no cambies campos ni plantillas.
3. Actualiza el complemento y reinicia KOReader. No hay que elegir el tipo:
   el nombre correspondiente a cada acción es automático.
4. Las claves antiguas `anki.model` / `anki_model` ya no seleccionan un tipo.
   La configuración guardada las retira sin borrar API keys; los modelos de IA
   se conservan por separado mediante una versión explícita de los ajustes.

Si ya existe `KOReader Vocabulary` además del antiguo, no borres ni fusiones
tipos automáticamente: revisa cuál contiene tus notas antes de migrar.

## KOReader Learn — Anki Learn

**Tipo: normal / Basic**, una tarjeta de pregunta/respuesta, sin cloze.
El complemento lo crea al primer envío si falta. No necesita elegir otro
perfil, idioma o proveedor por separado.

| Orden | Campo | Contenido |
|---|---|---|
| 1 | `PluginID` | ID estable generado por el complemento. No lo edites; identifica la tarjeta y evita duplicados. |
| 2 | `Question` | Pregunta autosuficiente. |
| 3 | `Answer` | Respuesta breve. |
| 4 | `Explanation` | Explicación opcional. |
| 5 | `SelectedText` | Selección original del lector. |
| 6 | `SourceExcerpt` | Cita de apoyo comprobada contra el texto recibido. |
| 7 | `BookTitle` | Título del libro, si está disponible. |
| 8 | `Author` | Autor, si está disponible. |
| 9 | `Chapter` | Capítulo, si KOReader puede identificarlo. |
| 10 | `Location` | Ubicación/página disponible. |
| 11 | `Context` | Texto circundante realmente enviado a la IA; no el libro completo. |
| 12 | `ContextQuality` | `document`, `pages` o `selection`, según la extracción disponible. |

**Anverso:** `Question` solamente. **Reverso:** pregunta, respuesta,
explicación y cita con título/autor/capítulo/ubicación. Los demás campos
permiten conservar la procedencia y recuperar la tarjeta en otro lector.

La plantilla no muestra `PluginID` ni `Context` completo durante el repaso.
El primer campo sigue siendo `PluginID` aunque no aparezca visualmente.

### Crear con AnkiConnect

```bash
curl http://127.0.0.1:8765 -H 'Content-Type: application/json' \
  --data-binary @anki/create-learning-note-type.json
```

Esto es opcional: también se crea al primer envío de Learn. Si el nombre ya
existe, no se recrea ni sobrescribe. El complemento comprueba los campos y
requiere `PluginID` como primer campo; informa si el esquema es incompatible.

### Crear manualmente en Anki

1. **Herramientas → Gestionar tipos de nota → Añadir → Basic / Básico**.
2. Nómbralo exactamente `KOReader Learn`.
3. Adapta los campos a la lista de doce nombres en ese orden.
4. Copia `Front`, `Back` y `css` desde `create-learning-note-type.json`.
5. Conserva una sola plantilla, **Pregunta**. No actives cloze ni una tarjeta
   inversa adicional: el complemento espera pregunta delante y respuesta detrás.

En Lua, la definición canónica está en
[`learning_card.lua`](../AnkiFlashcards.koplugin/learning_card.lua).
Los ejemplos JSON se comprueban contra esa definición en las pruebas.

## Usar y recuperar

- En KOReader selecciona texto → **Anki Vocab** o **Anki Learn**.
- Revisa la propuesta; **Guardar** y **Enviar a Anki** están en ambas caras.
- Las notas nuevas llevan `KOReader` y `KOReader::Vocab` / `KOReader::Learn`.
- **Recuperar desde Anki** lee `KOReader Vocabulary` y `KOReader Learn` con etiqueta `KOReader` y conserva
  sus IDs. Revisa movimientos y cambios de notas vinculadas aunque salgan de
  ese filtro; los cambios de contenido local solo se aplican con confirmación.
  No borra tarjetas locales ni modifica notas de Anki.
- Vocab antiguo puede no tener metadatos de libro. Learn conserva los campos
  de procedencia, pero no reconstruye automáticamente subrayados del documento.
- El complemento no cambia la programación de repasos de notas existentes.

Las dos clases pueden compartir baraja. En **Barajas y envío → Organización**
elige **Por libro y tipo** para usar `<Libro>::Vocabulario` y
`<Libro>::Aprendizaje`. Eso no mueve tarjetas existentes.

## Precauciones

- Ejecuta los comandos en el ordenador con Anki abierto; `127.0.0.1` es local
  a ese ordenador, no una dirección que pueda usar el Kobo.
- Crear un tipo de nota no crea contenido ni tarjetas de prueba.
- No borres un tipo que ya contiene notas para aplicar estas instrucciones.
- Si utilizas autenticación de AnkiConnect, los ejemplos necesitarían la clave;
  el cliente actual del plugin no implementa esa autenticación.
- La cita validada demuestra que ese texto estaba disponible, no que toda la
  interpretación de la IA sea correcta. Revisa las tarjetas Learn.
