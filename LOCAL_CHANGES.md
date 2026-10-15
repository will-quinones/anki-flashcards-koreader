# Cambios locales

## Subrayado opcional y anotaciones por lote

Guardar/Enviar tienen al lado **Subrayar** en la vista previa cuando existe
una selección vinculada. Usa la API nativa, restaura la selección anterior,
verifica el libro y no duplica subrayados existentes (incluidas posiciones
PDF restauradas desde JSON). Generar Vocab ya no subraya automáticamente.

La ventana de anotaciones usa filas con selección/extracto a la izquierda y
acción Anki a la derecha, paginación y controles generales al pie. Muestra
estados Vocab/Learn, permite abrir tarjetas existentes, seleccionar todas o
solo algunas y elegir el tipo para la operación sin perfiles ni defaults.
Incluye notas con texto; las no ancladas a fragmentos válidos se señalan.

El lote confirma consumo, usa contexto directo del documento, guarda sin
enviar y admite cancelación incluso durante la espera de reintento. Revalida
libro/anotación, omite duplicados por tipo y procedencia, registra alias de
formas canónicas antiguas sin sobrescribir tarjetas y conserva lo completado
al fallar proveedor o almacenamiento. Las notas personales solo orientan
Learn tras el aviso; nunca se validan como citas del libro. La apariencia
visual debe comprobarse en el lector después de actualizar y reiniciar KOReader.

Pruebas: `test_annotation_tools.lua`, `test_annotation_generation.lua`,
`test_annotation_preview.lua` y las de visor/errores por lote.

## Acceso directo al menú completo de subrayados

El toque nativo que abría la barra compacta ahora prepara una copia de la
selección y abre el menú completo, como el botón de tres puntos. La
redirección solo dura durante ese toque; edición de límites y llamadas
explícitas siguen usando la barra original. El menú completo ofrece
**Editar subrayado**. Se preservan los botones de otros plugins y no se
modifican anotaciones ni archivos del núcleo de KOReader. Las tarjetas
asociadas y los subrayados con nota mantienen sus accesos previos.

Prueba: `test_highlight_menu.lua`. Se carga al actualizar el plugin y reiniciar KOReader.

## Recuperación con revisión de cambios

La recuperación ahora audita la unión de la búsqueda KOReader y los IDs
locales vinculados. Detecta movimientos/múltiples barajas, notas ausentes,
cambios de tipo/etiqueta, ediciones remotas, cambios locales y conflictos.
No hay borrados automáticos ni se reenvían en lote las tarjetas por revisar.

Los metadatos de ubicación se actualizan sin tocar contenido. Las versiones
de contenido usan huellas de la última comparación y confirmación por lote
sin conflictos o por tarjeta conflictiva. Se verifican origen, versión Anki
y estado local otra vez antes de guardar, con persistencia atómica. El libro
y las posiciones locales de vocabulario se preservan. Las imágenes nuevas
no pisan archivos existentes y los fallos conservan el texto/imagen anterior.

El origen usa perfil + IDs de tipos (no IP), con comprobaciones durante la
operación. Es una comprobación conservadora de linaje, no un UUID global:
no distingue clones que conserven esos datos. Los enlaces antiguos sin base
de comparación requieren revisión cuando el contenido difiere. Nunca escribe
en Anki ni cambia su programación de repasos. La interfaz muestra detalles
y resúmenes; los campos largos completos se revisan en Anki.

Pruebas nuevas: `test_anki_reconciliation.lua`, `test_recovery_images.lua` y
`test_recovery_review_ui.lua`. Mejora instalada por SSH, con sintaxis y
verificación de origen comprobadas desde el Kobo contra Anki en modo lectura.
Se conservaron tarjetas/configuración y solo se respaldaron ajustes. Es
necesario reiniciar KOReader para cargarla.

> Las secciones siguientes incluyen la evolución del complemento. Para los
> menús actuales consulta el README. Ya no hay selector de tipos de nota ni
> un apartado Avanzado que reúna ajustes sin relación.

## Organización actual de la configuración

- **Conexión con Anki:** dirección y prueba de conexión.
- **Barajas y envío:** un selector de organización (una baraja / por tipo /
  por libro / por libro y tipo), destino relevante, envío automático y etiquetas extra.
- **Generación de tarjetas:** servicio, cuenta/modelo de IA e idioma compartidos.
- **Extras de vocabulario:** imágenes y audio; no afectan a Learn.
- **Nube entre lectores:** destino y sincronización al abrir, desactivada por defecto.
- **Ayuda:** información de uso y tipos automáticos, sin controles técnicos.

KOReader Vocabulary y KOReader Learn se preparan y validan automáticamente al
enviar. No son ajustes normales ni avanzados. Las claves de configuración
obsoletas de tipos se retiran al guardar, manteniendo las API keys. La versión
de ajustes distingue inequívocamente el antiguo `model` de nota del modelo de IA.

Las acciones de envío, recuperación, sincronización manual y estadísticas
permanecen fuera de Configuración. Configurar nube no inicia sincronización;
desvincularla elimina también el estado en memoria, sin borrar tarjetas.
Las claves se ocultan en el editor y borrarlas requiere confirmación. Los
modelos vacíos usan de verdad su valor predeterminado. Se preservan rutas de
barajas antiguas; el nuevo `book_parent` solo se guarda al editar ese destino.

Esta reorganización está instalada por SSH, con sintaxis validada en el Kobo.
Requiere reiniciar KOReader para cargarla; se conservaron configuración y tarjetas.

### Nombres de barajas por tipo

Las opciones **Por tipo de tarjeta** y **Por libro y tipo** piden los nombres
de las subbarajas Vocab/Learn en un formulario nativo. Organización y nombres
se guardan juntos, sin cambios parciales al cancelar o fallar la escritura.
Se conservan los nombres para futuras selecciones y se validan para evitar
vacíos, nombres iguales y separadores de jerarquía. Las rutas de envío y los
ejemplos usan los nombres elegidos. El campo anterior «Carpeta de libros» se
llama **Deck Padre**, también al usar una baraja única con subbarajas por tipo.
El vocabulario existente dentro del mismo contenedor sigue reconociéndose
aunque cambie el nombre de su subbaraja; no se mueve ni se vuelve a crear.

Este ajuste de nombres está instalado por SSH; requiere reiniciar KOReader.

### Mensajes, errores y ambas caras

La generación de Vocab/Learn usa un controlador común con avisos cortos en
español, sin incluir el fragmento en la notificación. Clasifica fallos de
saturación, límites temporales, cuota/saldo, autenticación, modelo y conexión.
El texto tiene como máximo un reintento para fallos temporales; no reintenta
errores permanentes ni espera automáticamente más de 10 segundos indicados
por el proveedor. Los errores HTTP 200 con cuerpo de error también se manejan.
No se muestran cuerpos JSON, URLs con claves ni trazas de excepciones.

La regeneración fallida conserva la tarjeta anterior. Los lotes se detienen
ante una caída del servicio conservando lo completado. Las imágenes muestran
errores breves sin añadir reintentos automáticos de operaciones de pago.

El reverso incluye **Mostrar pregunta** y el anverso **Mostrar respuesta**.
Guardar/Enviar, navegación y edición están separados para evitar botones
demasiado comprimidos. Cambiar de cara conserva los datos y no llama a la IA.

Pruebas: `test_generation_feedback.lua`, `test_inbox_generation_errors.lua`
y las pruebas existentes de generación/controlador/visor.

Instalado por SSH con sintaxis y clasificación de saturación verificadas en
el Kobo. Se conservaron tarjetas y configuración; respaldo solo de ajustes.

Esta copia conserva el historial y el remoto del repositorio original. No es
un fork publicado en GitHub. No incluye tus claves ni `configuration.lua`.

## Accesos

- **Herramientas → Anki Flashcards**: gestión/ajustes y tarjetas guardadas,
  también desde el explorador de archivos, sin seleccionar texto.
- **Herramientas → Anki Flashcards → Ajustes** abre el panel nuevo directamente.
- Al seleccionar una palabra y abrir el diccionario, aparece **Anki Card**.
  Usa la selección del libro y su contexto sin crear un subrayado permanente.
- Se conservan los accesos originales del diálogo de subrayado.
- El botón del diccionario requiere la API `ReaderDictionary:addToDictButtons`
  (disponible en KOReader v2026.07.1). Versiones sin esa API siguen cargando
  el plugin y mantienen los accesos por subrayado/Herramientas.

## Imágenes opcionales

En ajustes → AI Providers, selecciona **Image: none** para desactivarlas.
`image_provider = "none"`, una cadena vacía o un proveedor ausente omiten
la generación sin error, sin petición de red y sin mostrar regeneración de
imagen. Un nombre de proveedor desconocido sí sigue mostrando un error.

## Pruebas e instalación

Desde la raíz del repositorio:

```sh
luajit tests/test_local_ux.lua
python3 -m pytest -q
```

Las pruebas Lua usan dobles de KOReader; no sustituyen una prueba visual en
el Kobo. Las pruebas Python originales requieren pytest; en esta sesión se
ejecutaron sus cuatro funciones directamente con `runpy`, sin instalarlo.
Para instalar, respalda solo tus configuraciones y claves y copia los archivos de
`AnkiFlashcards.koplugin/` sobre el plugin, conservando tu `configuration.lua`.
Reinicia KOReader completamente.

## Organización de barajas

En **Anki Connection → Deck organization** puedes alternar entre:

- **By book** (`anki.deck_mode = "book"`, predeterminado): conserva el
  comportamiento original. Con `deck = "Spanish::Koreader"` y título
  «Los códigos secretos», envía a `Spanish::Los códigos secretos`.
- **Configured deck** (`anki.deck_mode = "configured"`): envía todas las
  tarjetas a la baraja exacta configurada, por ejemplo `Spanish::Koreader`.

Sin título de libro, ambos usan la baraja configurada. Antes de enviar se
crea la baraja si falta, incluidos sus padres. El modo se guarda en los
ajustes del dispositivo y solo afecta los envíos futuros: no mueve tarjetas
ya enviadas. La detección de duplicados sigue siendo por baraja, como en el
original; reenviar una tarjeta en otro modo podría crear otra copia.

Prueba de envío sin red: `luajit tests/test_deck_modes.lua`.

## Nuevo panel de ajustes

La interfaz anterior de configuración ya no se carga. El panel nuevo usa
listas paginadas de KOReader, etiquetas en español, navegación atrás y
selectores explícitos (no rotación de proveedores al tocar un botón).

- **Primeros pasos**: guía breve para conectar, configurar la IA y probar.
- **Anki**: dirección del ordenador, comprobación real de conexión, baraja
  y organización. Se puede introducir solo la IP; se añade `http://` y el
  puerto `8765`. Rechaza localhost y puertos inválidos.
- **Texto**: proveedor, clave e idioma. Las claves no se muestran en las listas;
  se editan en su diálogo dedicado. Los placeholders no cuentan como claves.
- **Imágenes**: apagadas o proveedor elegido, clave y aviso sobre costes.
- **Avanzado**: modelos, tipo de nota, etiquetas, audio, envío automático,
  nube y AnkiVocab. No habilita servicios de pago ni realiza pruebas de IA
  automáticamente. El saldo de AnkiVocab se consulta en su web.

Se conservan las claves y ajustes existentes y se aplican los cambios sin
reiniciar. El guardado usa un archivo temporal y reemplazo atómico; un error
de escritura conserva el archivo anterior y se muestra al usuario.
La comprobación de Anki usa `version` y muestra los errores reales, incluida
autenticación, en lugar de declarar éxito solo por `requestPermission`.

El modelo predeterminado de imágenes Gemini pasa a `gemini-3.1-flash-image`.
Los modelos personalizados ya guardados no se cambian automáticamente.

Pruebas adicionales:

```sh
luajit tests/test_friendly_settings.lua
luajit tests/test_atomic_settings.lua
```

Instalado por SSH en el Kobo con sintaxis validada en el dispositivo. Falta validar allí la
apariencia y la navegación con una prueba visual. La UI anterior queda solo
como fixture de compatibilidad en `tests/fixtures/`, fuera del plugin.

### Integración nativa del menú

La configuración se integra ahora como submenús del **TouchMenu original de
KOReader**, sin abrir un segundo widget Menu. La ruta única es:

```
Herramientas → Anki Flashcards
├── Configuración
│   ├── Primeros pasos
│   ├── Conexión con Anki
│   ├── Texto e idioma
│   ├── Imágenes
│   └── Avanzado
├── Tarjetas
│   ├── Mis tarjetas
│   ├── Enviar pendientes
│   ├── Crear desde subrayados (con un libro abierto)
│   └── Borrar del Kobo (con confirmación)
└── Estadísticas por libro
```

Se eliminó el acceso duplicado a ajustes desde el gestor de tarjetas. Las
estadísticas no son ajustes y quedan fuera de Configuración. La navegación
y los selectores usan el menú nativo; solo introducir texto/claves, consultar
ayuda o elegir un servidor de nube requiere los diálogos estándar de KOReader.
Esto no modifica la interfaz del firmware Kobo/Nickel.

## Recuperar tarjetas desde Anki

**Herramientas → Anki Flashcards → Tarjetas → Recuperar desde Anki** recupera
las notas del tipo configurado (por defecto `KOReader Vocabulary`) con etiqueta
`KOReader`, en todas las barajas. Requiere Anki abierto y accesible.

- Solo lee Anki; nunca crea, modifica o elimina notas allí.
- Conserva los campos de texto, la imagen principal si está en los medios
  locales de Anki, el ID de nota, la baraja y el estado «ya enviada».
- Una segunda recuperación omite los IDs ya importados y puede completar
  imágenes que faltaban por un fallo anterior.
- No sobrescribe tarjetas locales. Si otra nota comparte la misma frase,
  informa del conflicto (la colección local actual es única por frase).
- Trabaja una nota por turno, muestra progreso, permite cancelar y conserva
  lo ya guardado. Un fallo de imagen conserva el texto con un aviso.
- No infiere el libro ni la posición original del subrayado. Las recuperadas
  aparecen en **Mis tarjetas → Todos los libros**.
- No usa proveedores de IA ni cambia la programación de repasos en Anki.

La referencia de audio se conserva como dato, pero no se descarga ni reproduce
audio en el Kobo. Solo se recupera la primera imagen compatible por nota.
Esto es una recuperación unidireccional, no una sincronización bidireccional
ni una sincronización con AnkiWeb.

Prueba sin dispositivo: `luajit tests/test_anki_import.lua`.

## Acciones desde ambas caras

El visor muestra una fila independiente con **Guardar** y **Enviar a Anki**
tanto en el anverso como en el reverso, sin tener que revelar la respuesta.
Los controles de edición permanecen en el reverso. Guardar o enviar no cambia
la cara visible y un error de envío permite reintentar. Tras guardar (también
mediante el envío), el botón refleja el estado «Guardada».

Prueba: `luajit tests/test_viewer_delivery.lua`.

## Anki Vocab / Anki Learn: dos acciones, sin perfiles

Los menús de selección y diccionario ofrecen **Anki Vocab** y **Anki Learn**.
La elección solo afecta a esa tarjeta. Comparten proveedor/clave/idioma;
no se guarda un modo de libro ni se añade configuración de perfiles.

Learn extrae texto nativo del documento:

- EPUB: hasta 180 palabras antes y después mediante los XPointers de la
  selección, incluso fuera de la página visible, restaurando la selección.
- PDF con texto: página seleccionada y páginas vecinas mediante extracción
  nativa. No captura imágenes ni usa OCR.
- Conserva selección, contexto, título, autor, capítulo/ubicación disponibles.
  La selección se limita a 6000 bytes y el contexto total a 20000 bytes para evitar
  enviar el libro entero. Si no hay contexto se indica y una palabra aislada
  sin contexto se rechaza antes de llamar a la IA.

Genera una pregunta autosuficiente, respuesta breve, explicación opcional y
una cita de apoyo. Valida que la cita esté presente en el texto enviado
(normalizando espacios). Puede rechazar el fragmento por falta de contexto.
Esto no demuestra automáticamente que la interpretación sea correcta: hay
que revisar la vista previa. No genera imágenes ni audio para Learn.
AnkiVocab Gateway no acepta esta tarea; los proveedores de texto generales sí.

Las tarjetas Learn tienen un ID estable por libro/capítulo/selección. No usan
la pregunta como identidad: editarla no crea otra nota. El visor muestra
pregunta delante y respuesta/cita/fuente detrás; Guardar y Enviar están en
ambas caras. Una tarjeta enviada se edita en Anki para evitar sobrescrituras.

### Organización en Anki

**Configuración → conexión con Anki → Separar Vocabulario y Aprendizaje** añade:

```
Spanish::<Libro>::Vocabulario
Spanish::<Libro>::Aprendizaje
```

También funciona bajo la baraja única configurada. La opción está apagada
por defecto y no mueve notas existentes. Al activarla reconoce vocabulario
ya enviado a la baraja padre sin crear otra copia. Learn se reconoce por ID
en todas las barajas; una versión distinta en Anki se reporta, nunca se pisa.

Vocab usa el tipo de nota existente; Learn usa **KOReader Learn**, que se crea
al primer envío y se valida sin modificar tipos incompatibles. Las notas
llevan `KOReader` y `KOReader::Vocab` / `KOReader::Learn`. La recuperación desde
Anki admite ambos tipos y conserva los metadatos de Learn. La nube utiliza
su ID estable. Los formatos y tarjetas de vocabulario existentes se mantienen.

Pruebas: `test_learning_generation.lua`, `test_learning_anki.lua`,
`test_learning_viewer.lua` y las pruebas de almacenamiento/recuperación.
Estos cambios Learn se instalaron por SSH, con sintaxis validada en el Kobo.
Es necesario reiniciar KOReader para cargarlos y comprobarlos visualmente.

## Nombres consistentes de tipos de nota

Los nombres predeterminados son **KOReader Vocabulary** (Cloze) y
**KOReader Learn** (normal). Código, configuración de ejemplo, documentación
y payloads JSON usan esos nombres. Se siguen respetando nombres personalizados
configurados explícitamente. Al migrar el anterior `Vocabulary`, se renombra
el tipo existente en Anki y se actualiza `anki.model` / `anki_model`; no se
crea una copia ni se modifican sus campos o la programación de repasos.

## Envíos idempotentes y recuperación de estados antiguos

Todos los envíos (individuales, por lote y automáticos) guardan ahora el estado
de entrega junto al ID de la nota, la baraja y el tipo de nota. Antes de enviar
se comprueba si Anki ya contiene la misma frase en el mismo tipo y la baraja
exacta. Si existe, se recupera el estado local sin crear otra nota ni volver a
subir medios/generar audio. No se modifican las notas existentes.

«Enviar todas» distingue nuevas, ya existentes, ya marcadas y errores reales,
con un único resumen. Los estados «pendientes» de versiones anteriores se
reconcilian al enviarlos. Un fallo al guardar el estado local se notifica y
puede recuperarse al reintentar. Tarjetas y ajustes usan guardado atómico.

```sh
luajit tests/test_send_reconciliation.lua
luajit tests/test_delivery_storage.lua
```
