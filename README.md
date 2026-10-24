# AnkiFlashcards para KOReader

Variante mantenida en [will-quinones/anki-flashcards-koreader](https://github.com/will-quinones/anki-flashcards-koreader),
fork de [lgallard/anki-flashcards-koreader](https://github.com/lgallard/anki-flashcards-koreader).
La rama predeterminada del fork es `local/ux-improvements`. En esta copia,
`origin` apunta al fork y `upstream` al repositorio del autor original.

Genera tarjetas mientras lees y envíalas a Anki. Esta versión incorpora dos
acciones, sin perfiles ni modos predeterminados:

| Acción | Para qué sirve | Tipo de nota en Anki |
|---|---|---|
| **Anki Vocab** | Aprender palabras y expresiones: definición, pronunciación, sinónimos y frase cloze. | `KOReader Vocabulary` (Cloze) |
| **Anki Learn** | Aprender una idea: pregunta, respuesta breve, explicación y cita del libro. | `KOReader Learn` (normal) |

> El GIF de `assets/koreader-anki-demo.gif` corresponde a la interfaz original.
> Los menús y las acciones de esta versión son los descritos aquí.

## Requisitos

- Un lector con [KOReader](https://github.com/koreader/koreader). La integración
  de los botones del diccionario usa `ReaderDictionary:addToDictButtons`,
  disponible en KOReader v2026.07.1. En versiones sin esa API se conservan
  los accesos por selección y Herramientas.
- Una API key de un proveedor de texto compatible. **No necesitas una clave
  de todos los proveedores** ni generación de imágenes.
- Para enviar/recuperar tarjetas: Anki de escritorio abierto con
  [AnkiConnect](https://ankiweb.net/shared/info/2055492159), accesible desde la
  red del lector. Crear tarjetas con IA y guardarlas en el Kobo no requiere Anki.

Las pruebas locales usan dobles de KOReader/Anki. No sustituyen una prueba
visual y de conexión en tu dispositivo; algunos cambios recientes pueden
estar en el repositorio y no en tu instalación hasta que la actualices.

## Instalación y actualización

1. Copia **solo** `AnkiFlashcards.koplugin/` a la carpeta de plugins. En Kobo:
   ```text
   /mnt/onboard/.adds/koreader/plugins/AnkiFlashcards.koplugin/
   ```
   `main.lua` y `_meta.lua` deben quedar directamente dentro de esa carpeta,
   no dentro de otra copia anidada del repositorio.
2. Reinicia KOReader completamente. Suspender el lector no recarga plugins.
3. Comprueba que **Anki Flashcards** esté activado en la gestión de complementos.
4. Abre **Herramientas → Anki Flashcards → Configuración**.
5. Elige proveedor de texto, introduce su clave y selecciona el idioma del libro.
6. Deja las imágenes apagadas si no las necesitas. Si las activas, revisa los
   costes/cuotas de tu cuenta antes de generar.

Puedes configurar todo desde el menú nativo. `configuration.lua` es opcional:
si prefieres usarlo, copia `configuration.lua.sample` a `configuration.lua`
en la carpeta del plugin. Los ajustes guardados desde el dispositivo tienen
prioridad sobre los valores del archivo.

**Al actualizar conserva tus datos**:

| Archivo/carpeta dentro de KOReader | Contenido |
|---|---|
| `plugins/AnkiFlashcards.koplugin/anki_flashcards_settings.json` | Ajustes y API keys activos. No lo publiques. |
| `plugins/AnkiFlashcards.koplugin/configuration.lua` | Configuración opcional y posibles claves. |
| `settings/ankiflashcards/anki_flashcards.json` | Tarjetas y estados de envío. |
| `settings/ankiflashcards/images/` | Imágenes locales. |
| `settings/ankiflashcards/runtime/` | Scripts auxiliares y archivos de trabajo. |

Una actualización normal no debe borrar tarjetas ni imágenes. Una limpieza
de datos debe ser una decisión explícita. Para respaldos de configuración,
conserva solo los archivos de ajustes/claves; no hace falta copiar el código.

Los ajustes se guardan en la **carpeta real del complemento**, de modo que una
sincronización de `/plugins` con ChronoSync los incluye. Si solo existe el antiguo
`koreader/anki_flashcards_settings.json`, el primer arranque lo valida y lo mueve
sin cambiar sus bytes. Si ya hay un archivo dentro del complemento (por ejemplo,
restaurado con ChronoSync), tiene prioridad y nunca se sobrescribe con el antiguo.
Un archivo local inválido no se reemplaza automáticamente. Si el traslado falla,
se conserva el archivo anterior y se muestra un aviso.

**Al instalar una actualización**, conserva tanto `configuration.lua` como
`anki_flashcards_settings.json` del dispositivo antes de sustituir la carpeta del
plugin. No empaquetes ajustes personales ni sus archivos `.tmp`: están excluidos
de Git. Las tarjetas y las imágenes antiguas se trasladan automáticamente a
`settings/ankiflashcards/`, junto con la base de sincronización y los auxiliares.
La migración no fusiona ni sobrescribe datos si ambas ubicaciones contienen
archivos: conserva ambas y muestra un aviso. Las rutas antiguas de imágenes se
resuelven al cargarlas sin modificar el contenido de las tarjetas. Las claves
permanecen en el JSON privado dentro del complemento, no en la carpeta de datos.
Durante las pruebas de esta copia no se crean respaldos automáticos.

Con esta distribución, guardar **`/plugins` y `/settings`** incluye toda la
configuración y los datos propios del complemento. Cierra KOReader antes de
restaurar o sincronizar esos archivos con ChronoSync para evitar escrituras
simultáneas. Si ChronoSync propaga eliminaciones, revisa esa política antes de
sincronizar la migración en otros dispositivos.

## Menús

```text
Herramientas → Anki Flashcards
├── Configuración
│   ├── Conexión con Anki
│   ├── Barajas y envío
│   ├── Generación de tarjetas: servicio, modelo, thinking, esfuerzo e idioma
│   ├── Extras de vocabulario: imágenes y audio
│   ├── Nube entre lectores: destino y sincronización al abrir
│   └── Ayuda: funcionamiento y tipos de nota automáticos
├── Tarjetas
│   ├── Mis tarjetas
│   ├── Recuperar desde Anki
│   ├── Enviar todas las pendientes
│   ├── Sincronizar entre lectores (si hay nube configurada)
│   ├── Crear tarjetas desde anotaciones
│   └── Borrar tarjetas del Kobo (con confirmación)
└── Estadísticas por libro
```

La configuración usa el **menú nativo de KOReader**, no un segundo panel.
Los editores de texto/claves y los avisos usan los diálogos estándar. No se
modifica el menú del firmware original Kobo/Nickel.

En **Estadísticas por libro**, mantén pulsado un libro para **Borrar tarjetas de
este libro…**. La confirmación muestra cuántas tarjetas Vocab/Learn se borrarán
del Kobo. Se conservan las notas enviadas a Anki, los subrayados y las imágenes
que todavía usan otras tarjetas. Las estadísticas se actualizan tras el borrado.

Al tocar un subrayado existente que normalmente abriría la barra compacta de
edición, se abre directamente el menú completo de acciones, también en los subrayados
morados y sin consultar la IA ni modificar las notas personales, sin pasar por
los tres puntos. **Editar subrayado** conserva la barra original de estilo,
color, notas y ajuste de límites. No se modifica el código de KOReader ni se
recrean los subrayados. Tener una tarjeta Vocab/Learn guardada no abre su modal
al tocar el subrayado: se mantiene el menú habitual y la tarjeta se abre solo
al elegir explícitamente la acción Anki correspondiente.

## Crear y usar tarjetas

1. Abre un libro y selecciona una palabra, expresión o fragmento.
2. Elige **Anki Vocab** o **Anki Learn**. Ambos aparecen en el diálogo de
   selección y en el diccionario de palabras individuales cuando la API es compatible.
3. Revisa la propuesta. **Anki Vocab y Anki Learn abren la tarjeta al iniciar la generación**
   y muestra el contenido conforme llega por streaming. Mientras se genera,
   puedes cancelar con **Cerrar**, la X, el botón de volver o tocando fuera del
   modal. Se detiene la petición y cualquier reintento pendiente; el contenido
   incompleto no se guarda. Learn muestra la pregunta mientras se genera y
   conserva la respuesta oculta hasta **Mostrar respuesta**. Para Learn, seleccionar una frase o párrafo suele
   ser más útil que seleccionar una palabra aislada.
4. **Mostrar respuesta** revela el reverso y **Mostrar pregunta** vuelve al
   anverso sin regenerar contenido. **Regenerar** está disponible en ambas
   caras de Vocab, también en tarjetas guardadas, y vuelve a generar la tarjeta
   completa con streaming. Si falla o cancelas, se conserva la versión anterior.
   El botón local alterna entre **Guardar** y **Borrar del Kobo…** según si la
   tarjeta está guardada. El borrado pide confirmación y permite volver a
   guardarla; conserva el subrayado y la nota de Anki.
   El botón dinámico de Anki también está disponible en ambas caras:
   **Enviar a Anki** si la nota no existe,
   **Eliminar de Anki…** si ya existe. El borrado siempre pide confirmación y
   conserva la copia local. Sin conexión o con un origen no verificable aparece
   **Verificar en Anki**, sin asumir que la nota falta. Se comprueba al abrir
   y antes de actuar, no mediante consultas continuas en segundo plano.
5. Guardar conserva la tarjeta en el lector. Enviar también la guarda
   localmente, con el ID de la nota y el estado de entrega.
    **Subrayar** es una acción opcional disponible en la vista previa. También
     puedes activar **Configuración → Generación de tarjetas → Subrayar al guardar
    tarjeta** para subrayar automáticamente la selección original después de
     pulsar **Guardar** y guardar correctamente una tarjeta Vocab o Learn, solo
     si la selección original contiene más de una palabra. Generar
     la vista previa no subraya. Está desactivado por
    defecto, conservando el comportamiento de esta copia instalada. Si el fragmento ya
   está subrayado aparece **✓ Subrayado** y no se duplica. Solo se permite en
   el libro original con posiciones válidas; no se reconstruyen posiciones
   inexistentes de tarjetas recuperadas desde Anki.
6. Abre **Mis tarjetas** para revisar, filtrar por libro, enviar o eliminar
   tarjetas. Ambos accesos abren todos los libros; el título indica visibles/total.
   La lista distingue `[Vocab]` y `[Learn]` y muestra el fragmento original en una
   segunda línea más pequeña, separado de la pregunta; debajo aparece el libro y la fecha.
   **↗** indica enviada a Anki y **○**, guardada solo en el Kobo (último estado confirmado).
   Las listas no tienen borde exterior y usan la flecha de retorno nativa para
   volver al apartado anterior, conservando el menú principal abierto.
   Las líneas largas se recortan con puntos suspensivos sin reducir la fuente.
   Si una tarjeta antigua no conserva su selección, aparece «Fragmento no disponible».
   Mantener pulsada una fila permite
   distinguir **Eliminar del Kobo…** de **Eliminar de Anki…**. El borrado remoto
   exige la API de AnkiConnect con protección de sesión; si no está disponible,
   se rechaza y se indica que se elimine desde Anki. No hay borrado remoto automático.

Al cerrar una tarjeta Vocab abierta desde la lectura, la selección original
parpadea dos veces para ayudarte a retomarla, refrescando solo los fragmentos
del texto y sin avanzar el contador de limpieza completa. No crea subrayados ni cambia de
página; solo se muestra si la selección corresponde al libro y la vista actuales.
Cambiar de cara, regenerar o recibir una imagen no activa el parpadeo.

El streaming de texto usa Gemini o servicios compatibles con Chat Completions
(OpenAI, OpenRouter, DeepSeek y DashScope). AnkiVocab Gateway devuelve la tarjeta
completa desde su servidor: el modal se abre y permite cancelar igualmente,
pero ese servicio no ofrece texto incremental mediante el endpoint integrado.
La interfaz y los botones definitivos aparecen después de validar la respuesta.
Las peticiones se ejecutan en un proceso separado y se cancelan también al
cerrar el libro o suspender KOReader. Las actualizaciones del modal se limitan
para evitar refrescos continuos en pantallas de tinta electrónica.

El idioma controla la tarjeta completa, no solo la traducción de una
definición. Para tarjetas monolingües en español, usa `Spanish` y texto en español.

La opción **Subrayar al guardar tarjeta** afecta solo al botón **Guardar**,
no al gesto de seleccionar texto ni al diccionario. No cambia la acción
predeterminada global de KOReader. No borra subrayados existentes o creados por
el propio lector; con la opción apagada puedes seguir usando **Subrayar** en la
vista previa. Un fallo al guardar, generar la vista previa, abrir una tarjeta existente, regenerarla,
recuperarla desde Anki o generar desde la lista de anotaciones no crea un nuevo
subrayado por esta opción. Se usan las posiciones capturadas y la API nativa,
con comprobación del libro original y sin duplicar. Si falla el subrayado, la
tarjeta queda guardada y se muestra un aviso; no se envía nada a Anki por ello.
Enviar y los guardados automáticos internos no activan este subrayado. Se conserva
el valor de la casilla anterior al actualizar, pero su efecto pasa al botón Guardar.
Una sola palabra no se subraya automáticamente; el botón manual **Subrayar**
sigue disponible. En el menú de selección solo quedan **Anki Vocab** y **Anki
Learn** como accesos Anki. Se retiraron **Anki Manage**, **My Cards** y el panel
Manage antiguo; las funciones actuales siguen en **Herramientas → Anki Flashcards**.
Los botones **Anki Vocab** y **Anki Learn** del diccionario se pueden activar,
desactivar y ordenar desde la configuración nativa **Ordenar y alternar botones**.
Si ya tenías una disposición personalizada, actívalos allí para añadirlos.

Los avisos de generación son cortos y comunes a Vocab/Learn: **Generando
tarjeta…** y **Regenerando tarjeta…**, sin repetir el fragmento seleccionado.
Los errores de saturación, conexión, límite temporal, clave, saldo o modelo
se muestran en español sin exponer la respuesta técnica completa del proveedor.
Los fallos temporales tienen como máximo un reintento; se respeta `Retry-After`
y, si exige más de 10 segundos, se pide intentar más tarde en vez de esperar.
No se reintentan automáticamente errores de clave, saldo/cuota agotada o modelo.
Un reintento de texto puede consumir cuota si la primera petición llegó al
servicio; las imágenes no reciben reintentos automáticos nuevos.

Si falla la regeneración se conserva la vista anterior. La generación por
lotes conserva las tarjetas completadas y se detiene si el servicio sigue
saturado, evitando enviar una petición fallida por cada subrayado restante.

### Generar desde las anotaciones del libro

Abre **Herramientas → Anki Flashcards → Tarjetas → Aprendizaje desde
anotaciones**, con el libro abierto. Este apartado crea exclusivamente tarjetas
de aprendizaje (Learn); Vocab sigue disponible en la selección y el diccionario.
La ventana incluye todas las anotaciones
con texto o nota asociada, paginadas para no desbordar la pantalla:

- A la izquierda: casilla de selección independiente y de ancho fijo.
- En el centro: extracto en una sola línea, con tamaño de letra y altura
  uniformes; el texto largo se recorta, no encoge. Toca o mantén pulsado el
  texto para leer el fragmento y la nota completos.
- A la derecha: icono **+** para generar y guardar, o **✓** para abrir directamente
  la tarjeta Learn ya guardada en el Kobo, sin nueva generación. No indica envío a Anki.
  No hay selector de tipo, indicadores V/L ni opciones Vocab en la pulsación larga.
- Al pie: **Generar seleccionadas (N)** y
  **Marcar todas / Desmarcar todas**. La selección abarca todas las páginas.
  Se preseleccionan las anotaciones que todavía no tienen Learn.
- Las anotaciones sin un fragmento/posición utilizables siguen visibles, pero
  no generan citas inventadas. Una nota personal sin fragmento no se considera
  texto del libro.

Antes de iniciar se confirma la cantidad y se avisa del consumo de cuota.
Las tarjetas generadas se guardan localmente para revisarlas; no se envían
automáticamente a Anki. En Learn se extrae contexto nativo y, tras el aviso,
las notas asociadas pueden orientar la pregunta, pero no sirven como citas.
El texto editado de una anotación requiere poder recuperar el fragmento
original. No se navega de página ni se crea un subrayado adicional al generar
desde una anotación existente.

Se comprueba de nuevo cada anotación y las tarjetas locales antes de llamar
a la IA y antes de guardar. Si cambias o cierras el libro, borras una anotación,
se agota la cuota, falla el guardado o persiste la saturación, se informa y se
conserva lo completado. Cancelar también impide reintentos pendientes. Tras
varias respuestas inválidas consecutivas se detiene el lote.

La detección es por tipo, origen/posiciones y referencias ya guardadas. Las
tarjetas antiguas sin procedencia completa pueden necesitar una llamada a la
IA para reconocer una forma canónica; no se crea otra tarjeta y se recuerda
la asociación para siguientes ocasiones. El almacenamiento de vocabulario
mantiene su unicidad por expresión canónica. Si las tarjetas solo están en el
ordenador, **Recuperar desde Anki** primero permite reconocerlas localmente;
la generación no consulta Anki obligatoriamente y funciona sin él abierto.

### Contexto y calidad de Anki Learn

- **EPUB:** extrae texto nativo desde la posición de la selección, hasta 180
  palabras antes y después, incluso más allá de la página visible.
- **PDF con texto:** usa extracción nativa de la página seleccionada y páginas
  vecinas. **No hace capturas de pantalla ni OCR**. En un PDF escaneado puede
  faltar contexto y será necesario seleccionar texto suficiente.
- Incluye título, autor y capítulo/ubicación cuando KOReader los proporciona.
  El título no da acceso al libro completo: la IA solo recibe el texto extraído.
- La selección se limita a 6000 bytes y el contexto total a 20000 bytes.
- Pide una pregunta autosuficiente, una respuesta breve y una cita de apoyo.
  Comprueba que la cita aparezca en el texto enviado, normalizando espacios.
  Si falta contexto o la salida es inválida, no guarda la tarjeta.

Esta validación **no garantiza que la interpretación de la IA sea correcta**.
Revisa pregunta, respuesta y cita antes de guardar. Learn no genera imágenes
ni audio. Las tarjetas Learn ya enviadas se editan en Anki para evitar
sobrescrituras silenciosas; las no enviadas pueden editarse en el lector.

## Conectar y organizar Anki

En **Configuración → conexión con Anki** introduce la IP del ordenador y
pulsa **Comprobar conexión**. Puedes introducir solo la IP; se añadirá
`http://` y el puerto `8765`.

No uses `localhost` ni la IP del Kobo. AnkiConnect debe escuchar en una
interfaz que el lector pueda alcanzar, no solo en `127.0.0.1`. Exponerlo a
la red sin autenticación permite que otros dispositivos de esa red lean o
modifiquen la colección: usa una red de confianza y restricciones de firewall;
**no lo expongas a Internet**. Este cliente no implementa `apiKey` de AnkiConnect.

Una reserva DHCP en el router ayuda a mantener estable la IP del ordenador.

### Barajas y envío

Un único selector **Organización** ofrece cuatro destinos:

- **Una sola baraja:** todas las tarjetas en la baraja elegida.
- **Por tipo:** subbarajas Vocabulario y Aprendizaje dentro de esa baraja.
- **Por libro:** `<carpeta de libros>::<título del libro>`.
- **Por libro y tipo:**
  ```text
  Spanish::<Libro>::Vocabulario
  Spanish::<Libro>::Aprendizaje
  ```
  Puedes repasar cada subbaraja o el libro completo desde la padre.

Solo se edita el destino relevante: **Baraja** o **Deck Padre**. Se
conservan los destinos anteriores al alternar. En configuraciones antiguas,
la carpeta de libros inicial sigue siendo el primer nivel de `anki.deck`,
para no cambiar las rutas existentes. Si el documento no tiene título se
usa la baraja configurada como respaldo.

Al elegir **Por tipo de tarjeta** o **Por libro y tipo** aparece un formulario
para escribir los nombres de las dos subbarajas. Se sugieren `Vocabulario` y
`Aprendizaje`, pero puedes usar, por ejemplo, `Palabras` e `Ideas`. Se guardan
la organización y ambos nombres juntos; cancelar o un error conserva la
configuración anterior. Los nombres deben ser distintos, no vacíos y sin `::`.
Para editarlos vuelve a seleccionar esa organización. **Deck Padre** admite
una ruta de barajas y se configura por separado. La vista de ejemplo utiliza
los nombres elegidos. Esto no renombra ni mueve barajas existentes en Anki.

Las **etiquetas adicionales** son opcionales. `KOReader`, `KOReader::Vocab`
y `KOReader::Learn` son automáticas y no hay que introducirlas. El envío
automático de pendientes se activa aquí; necesita Anki accesible y no es
sincronización con AnkiWeb.

El envío automático no hace HTTP, DNS ni TTS en el hilo de lectura: usa un
proceso separado de baja prioridad, con una sola tarjeta en vuelo. El primer
intento es a los 30 segundos; solo consulta el estado de Wi-Fi ya conocido por
KOReader, sin encenderlo ni hacer comprobaciones DNS desde la interfaz. No hay
peticiones si no existen tarjetas pendientes. Si Anki está cerrado o inaccesible,
falla una única comprobación y espera 1, 2, 5, 10 y hasta 30 minutos entre intentos;
no repite el mismo fallo por cada tarjeta de la cola. El siguiente intento se
programa después de terminar, no mientras otro sigue activo.

Cada proceso tiene un límite de 120 segundos y se cancela al cerrar el libro,
suspender KOReader o desactivar el ajuste. Se conservan intención y comprobante
en `settings/ankiflashcards/runtime/auto-send-*.json`, sin guardar claves API en
ellos. Solo la interfaz actualiza la colección local, y únicamente si la tarjeta
no fue borrada o modificada mientras se enviaba. Si una interrupción deja dudas
sobre una escritura remota, el envío automático se pausa hasta comprobarlo con
**Recuperar desde Anki** o resolverlo manualmente; no se reenvía a ciegas. Una
entrega ya completada puede reconciliarse al reabrir sin enviar otra vez.

Al cambiar de red, actualiza la dirección del ordenador en Conexión con Anki:
el Wi-Fi conectado no demuestra que AnkiConnect esté disponible en la IP antigua.

Las barajas se crean si faltan. Cambiar estas opciones **no mueve notas
existentes**. Al activar la separación, se reconoce vocabulario previamente
enviado a la baraja padre para evitar volver a crearlo. Learn se reconoce por
su ID estable incluso si cambias de baraja.

## Tipos de nota: creación y estructura

**Una baraja organiza tarjetas; un tipo de nota define sus campos y plantillas.**
Ambos tipos pueden estar en la misma baraja o en subbarajas separadas.

Si vienes de la versión que usaba `Vocabulary`, **renombra ese tipo existente
a `KOReader Vocabulary` y actualiza la configuración**, en lugar de crear
otro tipo duplicado. La [guía de tipos de nota](anki/README.md#actualizar-el-nombre-anterior-vocabulary)
explica la migración conservando las notas y los repasos.

- `KOReader Vocabulary` se crea automáticamente al primer envío de Vocab,
  si falta. Es de tipo **Cloze**.
- `KOReader Learn` se crea automáticamente al primer envío de Learn, si no
  existe. Es de tipo **normal** (pregunta/respuesta).
- El complemento valida los campos de ambos tipos y no modifica tipos incompatibles.
- No existe un selector de tipos de nota, ni normal ni avanzado: cada acción
  usa automáticamente su tipo. El modelo de IA se configura junto a su servicio
  y no tiene relación con el tipo de nota de Anki.
- No convierte tus notas existentes ni cambia sus repasos.

**Guía completa de campos, plantillas y creación manual:** [anki/README.md](anki/README.md).

Desde la raíz del repositorio, con Anki/AnkiConnect abiertos en el ordenador:

```bash
# Crear KOReader Vocabulary, si todavía no existe
curl http://127.0.0.1:8765 -H 'Content-Type: application/json' \
  --data-binary @anki/create-note-type.json

# Crear KOReader Learn manualmente (también se crea al primer envío)
curl http://127.0.0.1:8765 -H 'Content-Type: application/json' \
  --data-binary @anki/create-learning-note-type.json
```

Estos comandos crean **tipos**, no tarjetas de ejemplo. Si el tipo ya existe,
AnkiConnect devuelve un error de nombre existente: no lo borres ni ejecutes
una recreación para actualizarlo. Usa el tipo compatible que ya tienes.

## Envíos, duplicados y recuperación

Cada envío exitoso guarda el estado local. Si falla la conexión o el guardado,
se informa y se puede reintentar. **Enviar pendientes** distingue tarjetas
nuevas, ya existentes, ya marcadas y errores reales, con un único resumen.

- Vocab verifica frase, tipo de nota y destino.
- Learn usa `PluginID`, no el texto de la pregunta. Una versión diferente en
  Anki se informa como conflicto; no se sobrescribe.

**Tarjetas → Recuperar desde Anki** sirve para un Kobo nuevo y para revisar
las tarjetas ya vinculadas:

- Lee notas `KOReader Vocabulary` y
  `KOReader Learn` etiquetadas `KOReader`, en todas las barajas.
- Recupera los datos y, para Vocab, la primera imagen local compatible.
- Marca las tarjetas recuperadas como enviadas y evita repetir IDs importados.
- Detecta cambios de baraja (incluidas notas con tarjetas en varias barajas)
  y actualiza esos metadatos sin mover nada en Anki.
- Compara contenido de Anki y Kobo con la última revisión. Si solo cambió en
  Anki, ofrece **Actualizar cambios sin conflicto** con confirmación. Si cambió
  en ambos lados, o la vinculación antigua no tiene historial, pide revisión
  individual. Puedes ver los campos cambiados y resúmenes de ambas versiones.
- Antes de aplicar vuelve a leer ambas versiones. Si editaste la tarjeta
  después de compararla, rechaza la actualización y pide volver a recuperar.
- No borra tarjetas. Las notas no encontradas, fuera de los tipos/etiquetas
  esperados o con identidad cambiada se conservan con un aviso. No se recrean
  mediante el envío automático ni **Enviar todas**; requieren revisión.
- Revisa también los IDs ya vinculados aunque no aparezcan en la búsqueda
  inicial, para distinguir una nota borrada de un cambio de tipo o etiqueta.
- Permite cancelar conservando lo completado; un fallo de imagen conserva el texto.

Solo lee Anki. No consume APIs de IA ni cambia la programación de repasos.
Vocab antiguo puede no contener datos del libro; los subrayados/posiciones no
se reconstruyen automáticamente. Learn conserva los metadatos guardados en
sus campos. El audio de Anki no se reproduce ni se descarga para el Kobo.

Esto es **recuperación unidireccional**, no sincronización bidireccional ni
sincronización con AnkiWeb. **Conservar versión local** no sube sus cambios a
Anki. Las notas con diferencias deben resolverse antes de reenviarlas.

El origen se verifica mediante el perfil activo y los IDs de los tipos de
nota, sin usar la IP como identidad. Cambiar de IP no rompe la vinculación;
un perfil/huella diferente o un cambio durante la operación detiene las
actualizaciones. AnkiConnect debe ofrecer `getActiveProfile` y
`modelNamesAndIds`. Esta huella no es un UUID global de colección: clones con
el mismo perfil e IDs no son distinguibles, y renombrar perfiles o recrear
tipos puede requerir revisión. No se deducen borrados si el origen o la
respuesta de red no se pueden verificar.

Los cambios de referencia de imagen requieren la misma confirmación; si la
descarga falla se conserva la imagen anterior y se puede completar después.
Los archivos nuevos usan nombres por contenido, sin pisar imágenes previas.
No se detecta automáticamente que alguien reemplazó los bytes de una imagen
manteniendo exactamente el mismo nombre y sin cambiar la nota en Anki.

La nube Dropbox/WebDAV para compartir tarjetas
entre lectores es una función distinta. Se configura en **Nube entre lectores**
y se ejecuta desde **Tarjetas → Sincronizar entre lectores**. Elegir un destino
no inicia una sincronización. La sincronización al abrir está apagada salvo
que la actives explícitamente. Desvincular no borra tarjetas locales ni remotas.

## Proveedores y costes

| Proveedor | Vocab | Learn | Imágenes de Vocab |
|---|:---:|:---:|:---:|
| Gemini | Sí | Sí | Sí, con modelo/cuenta compatibles |
| OpenRouter | Sí | Sí | Sí, con modelo/cuenta compatibles |
| DeepSeek (API directa) | Sí | Sí | No |
| OpenAI | Sí | Sí | Sí |
| DashScope / Qwen | Sí | Sí | Sí |
| AnkiVocab Gateway | Sí | No | Sí |
| Pollinations, integración antigua | No | No | Experimental; puede fallar o exigir pago |

Los proveedores de texto e imágenes son independientes, pero reutilizan la
misma clave si eliges el mismo servicio. Cada apartado agrupa servicio y
**Cuenta y modelo de IA**; no existe otra zona de claves/modelos duplicada.
Las claves se ocultan en el editor y borrarlas requiere confirmación.
**Modelo de IA** permite cargar el catálogo actual del proveedor, buscar en él
y elegir un modelo. Buscar no cambia la selección. **Escribir modelo…** conserva
la entrada de identificadores personalizados y la lista incluida sirve sin
conexión. Toca el aviso de carga para cancelar. **Thinking** y **Esfuerzo** ofrecen los controles
compatibles con el modelo seleccionado y se guardan por proveedor para Vocab,
Learn y regeneración. **Generación de tarjetas → Ver configuración de proveedores**
muestra también los ajustes de los servicios inactivos, sin exponer claves.
La carga del catálogo se hace solo al pedirla; [compatibilidad y fuentes](docs/AI_PROVIDERS.md).
DeepSeek se conecta directamente a `api.deepseek.com`; se configura como
proveedor de texto con una clave DeepSeek y un identificador de modelo.
`image_provider =
"none"`, vacío o ausente omite imágenes sin error. No se presupone que una API
sea gratuita: consulta precios, cuotas y modelos vigentes en tu cuenta.
El modelo predeterminado de imágenes Gemini es `gemini-3.1-flash-image`;
un modelo antiguo ya guardado no se reemplaza automáticamente.

ElevenLabs es opcional para pronunciación de Vocab al enviar a Anki. Su cuota
y facturación son independientes. No se activa automáticamente.

## Desarrollo y pruebas

```sh
python3 tests/run_tests.py
```

El ejecutor necesita Python 3 y LuaJIT, sin dependencias Python adicionales.
Descubre todas las pruebas Lua y Python, ejecuta cada caso en un proceso
separado, informa los fallos y comprueba la sintaxis de los módulos Lua.
No omite las pruebas antiguas ni necesita una instalación de KOReader.

Las simulaciones compartidas de `tests/support/koreader.lua` proporcionan los
límites de KOReader: archivos virtuales, widgets, medidas de texto, pantalla,
eventos y transporte de red. Las pruebas conservan los módulos reales de
almacenamiento y control que comprueban; los accesos de red no preparados
fallan. Los casos antiguos usan las acciones nativas actuales y el guardado
explícito de vistas previas. Las pruebas de migración comprueban por separado
las rutas reales. El aspecto y los refrescos físicos de tinta electrónica
requieren comprobación en el lector.

Las pruebas no necesitan claves reales. [LOCAL_CHANGES.md](LOCAL_CHANGES.md)
describe los cambios de esta copia respecto al proyecto original.

## Licencia

[MIT](LICENSE). Proyecto original: [lgallard/anki-flashcards-koreader](https://github.com/lgallard/anki-flashcards-koreader).
