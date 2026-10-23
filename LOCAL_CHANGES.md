# Cambios locales

## Fork propio y mantenimiento (2026-10-23)

Esta variante se publica en https://github.com/will-quinones/anki-flashcards-koreader,
con `local/ux-improvements` como rama predeterminada. El remoto `origin` apunta
al fork propio y `upstream` conserva https://github.com/lgallard/anki-flashcards-koreader.git.
Se mantienen el historial original y las mejoras locales anteriores.

Las novedades del autor se consultan con `git fetch upstream` y se integran
en una rama de revisión, evaluando sus dependencias y las decisiones de esta
variante: guardado explícito, menús nativos, streaming y cancelación. Antes
de incorporar una actualización se ejecuta `python3 tests/run_tests.py` y se
comprueba su comportamiento en el lector. Las claves y los ajustes privados
permanecen excluidos de Git.

## Streaming de Vocab y batería completa de pruebas (2026-10-23)

La vista previa se abre al empezar la generación y muestra texto incremental
con Gemini y servicios compatibles con Chat Completions. Cerrar cancela la
petición y los reintentos; también se cancela al cerrar el libro o suspender
KOReader. El gateway AnkiVocab conserva su respuesta completa sin incrementos.
Regenerar está disponible en ambas caras y conserva la propuesta anterior
si falla o se cancela. El botón local alterna Guardar/Borrar del Kobo y la
selección original parpadea dos veces al volver a la lectura.

Se completaron las simulaciones de KOReader y se actualizaron los escenarios
antiguos a los menús y el guardado explícito actuales. Se corrigieron avisos
incorrectos tras fallos de borrado, colisiones de nombres de imágenes y
respuestas tardías de imágenes/audio/IPA. El ejecutor único comprueba las
52 pruebas sin fallos ni omisiones y la sintaxis de los 36 módulos Lua.
La validación visual de estas mejoras en el Kobo sigue pendiente.

## Botones Anki configurables en el diccionario

Anki Vocab y Anki Learn se registran como botones persistentes con menu_text,
no como filas transitorias conditional. Aparecen en Ordenar y alternar botones
y conservan sus IDs y show_func para selecciones válidas fuera de Wikipedia.
No se reescribe dict_button_config ni se impone un orden o activación nuevos.

## Solo varias palabras y retirada del menú antiguo

El subrayado opcional tras Guardar requiere más de una palabra en la selección
original capturada, no en el contexto o pregunta generada. Reconoce espacios
Unicode e ignora signos de puntuación sueltos. No limita el subrayado manual.
Retirados los registros Anki Manage y My Cards del menú de selección y eliminado
el constructor/show_manage del panel antiguo. menu_items devuelve directamente
las acciones al menú nativo actual. Se conservan gestión, recuperación, tarjetas,
anotaciones, configuración y envíos desde Herramientas → Anki Flashcards.
Instalados y verificados los cuatro módulos afectados en el Kobo; suites Lua y
Python completas y cinco pruebas simuladas en LuaJIT del dispositivo correctas.
Configuración privada, tarjetas y medios conservaron sus hashes; sin respaldos.

## Subrayado opcional al guardar tarjetas

Ajuste `highlight_on_save` en Configuración → Generación de tarjetas →
Subrayar al guardar tarjeta. Valor predeterminado falso, preservando la copia
instalada que dejaba el subrayado a la acción explícita de la vista previa.
Se consulta solo después de guardar correctamente con el botón Guardar Vocab o Learn y se
usa annotation_tools.highlight con el snapshot original, deduplicación EPUB/PDF
y comprobación de libro/posiciones/cierre del lector. Un error de subrayado no
impide conservar la tarjeta guardada. No hay anotaciones nuevas por generar la
vista previa, abrir, regenerar, enviar, recuperar o seleccionar texto, ni cambios
de la acción global de KOReader. Un guardado fallido tampoco subraya.

La petición final se aclaró como subrayado al GUARDAR tarjeta, no al generarla;
se retiró el disparador de generación y se conserva la preferencia anterior
`highlight_on_generate` mediante migración en memoria si falta `highlight_on_save`.
el intento local de interceptar selección se retiró antes de instalar nada.
Instalados y verificados los cinco módulos afectados en el Kobo 192.168.50.132;
configuración privada y tarjetas conservaron sus hashes. Suites Lua/Python
completas y pruebas de generación simulada en el dispositivo correctas.
No se crearon respaldos, no se enviaron tarjetas ni se subrayaron libros reales
durante las pruebas. Las demás modificaciones previas del árbol se preservan.

## Envío automático sin bloquear la lectura

Sustituido el lote síncrono del temporizador por auto_send.lua y un proceso
de baja prioridad gestionado por ffi/util. Toda red/DNS/TTS queda fuera del hilo
de UI, también la prueba de conexión. En UI se usa solo el estado Wi-Fi cacheado.
Una tarjeta/proceso, sin solapamientos; pausas 1/2/5/10/30 minutos tras fallos,
límite 120 s y cancelación/recolección al salir, suspender o desactivar el ajuste.

El hijo devuelve recibos sin escribir la colección local; card_storage aplica
solo los que aún coinciden con la instantánea pendiente. Los diarios persistentes
en settings/ankiflashcards/runtime permiten reconciliar tras un cierre y pausan
escrituras inciertas sin reenvío ciego. No se guardan claves API en el diario.
Se protegen tarjetas editadas/borradas durante el trabajo.

Diagnóstico del Kobo en 192.168.0.141: 8 pendientes, automático desactivado y
Anki aún apuntando a 192.168.50.213. El Mac está ahora en 192.168.0.100.
No se cambió esa configuración ni se enviaron tarjetas reales en las pruebas.

Instalado en 192.168.0.141 el 2026-10-15 (`20261015-100645`), sin respaldos.
Prueba nativa de solo lectura: fork en 0,014 s, 51 sondeos no bloqueantes del
padre durante una espera de red de 5,14 s. Cero envíos de tarjetas en las pruebas.
Configuración y datos verificados sin cambios; el envío automático sigue
desactivado y no se cambió la URL guardada de Anki.

## Todos los datos dentro de plugins o settings

La configuración privada sigue dentro del complemento. Las tarjetas, imágenes,
base de sincronización y archivos auxiliares pasan a `settings/ankiflashcards/`.
storage_paths.lua centraliza rutas y una migración por renombrado, sin cambios
de bytes ni mezcla destructiva de datos restaurados. Se trasladan también los
tres scripts auxiliares antiguos de /tmp si existen. Imágenes generadas,
recuperadas de Anki y sincronización usan las mismas rutas nuevas.

Las referencias antiguas a imágenes se resuelven al cargar; solo se actualiza
la huella local si antes estaba limpia, sin ocultar cambios genuinos de contenido.
No se tocan anotaciones del libro ni datos de otros complementos.

Instalado y migrado en el Kobo el 2026-10-15 (`20261015-004401`), sin respaldos.
Configuración conservada y hashes de datos trasladados idénticos. La raíz ya no
contiene entradas Anki. El archivo de tarjetas de origen ya estaba vacío (2 bytes,
fecha anterior al traslado); se conservó exactamente, sin recuperación automática.
Requiere reiniciar KOReader antes de continuar para abandonar las rutas antiguas
del código aún cargado en memoria.

## Ajustes dentro de la carpeta del complemento

La configuración activa pasa a `AnkiFlashcards.koplugin/anki_flashcards_settings.json`,
resuelta desde la ubicación real de card_storage.lua para admitir instalaciones
externas o carpetas renombradas. Se migra por renombrado el archivo antiguo solo
si falta el local y contiene JSON válido. Se preservan bytes, claves y valores;
un archivo local restaurado con ChronoSync siempre tiene prioridad. Fallos de
traslado conservan el archivo anterior utilizable y generan un aviso.

El JSON activo y su temporal quedan ignorados por Git. Las siguientes instalaciones
deben excluirlos del paquete local y preservar el JSON remoto, igual que
configuration.lua. Tarjetas e imágenes conservan sus ubicaciones actuales.

Instalado y migrado en el Kobo el 2026-10-15 (`20261015-003144`), sin respaldos.
Se verificó igualdad de bytes del JSON antes/después y que el archivo antiguo
ya no existe. Tarjetas e imágenes sin cambios. Reiniciar KOReader antes de
editar ajustes para reemplazar el código antiguo aún cargado en memoria.

## Corrección de superposición en Mis tarjetas (IMG_0408)

Se usaba `perpage`, que KOReader recalcula desde la preferencia global y por
tanto ignora como ajuste de entrada. Se sustituye por `items_per_page`, calculado
con la altura real de las tres fuentes y margen vertical, y refinado con el área
disponible del menú. Ya no se asigna a tres líneas el espacio de una fila simple.
La flecha nativa de retorno se mantiene habilitada para este padre externo.

Corrección instalada en el Kobo el 2026-10-15 (`20261015-001345`), sin respaldos.
Archivos/sintaxis validados y configuración, tarjetas e imágenes sin cambios.
Requiere reiniciar KOReader completamente para reemplazar el código ya cargado.

## Diseño minimalista de los dos tipos de Anki

Vocab corregido mediante MCP para evitar el salto al revelar: mismo encabezado,
definición y ejercicio en ambas caras; palabra e IPA pasan debajo de la frase
y los sinónimos. Se conserva el cloze y no se cambia contenido de las notas.

Refinado en Learn mediante MCP: títulos «Explicación» y «Cita del libro» con
separación adicional; si solo hay selección, se etiqueta «Fragmento seleccionado».
Los títulos opcionales desaparecen junto con su campo vacío. No se cambió el
contenido ni el diseño de Vocabulary en este refinamiento.

Aplicado mediante MCP de Anki a KOReader Vocabulary y KOReader Learn: tipografía
de sistema, columna legible, fondo marfil, acento verde y modo nocturno. Móvil
sin desbordamiento horizontal. Learn conserva la pregunta sola delante y la
respuesta destacada detrás, con explicación/cita/procedencia y selección original
desplegable. Vocab mantiene cloze, pronunciación, imágenes/audio y enlace de fuente.
No se modificaron campos, notas ni programación de repasos. No se sincronizó con AnkiWeb.

Definición compartida en card_design.lua y payloads JSON actualizados, con pruebas
de igualdad, separación pregunta/respuesta, referencias de campos y contraste.
Los archivos locales del plugin aún no se han actualizado en el Kobo; los tipos
actuales de Anki ya tienen el diseño y no requieren reinstalar el plugin.

## Navegación y filas nativas sin borde

Las listas Mis tarjetas, gestión, recuperación y estadísticas usan el modo
oficial `is_borderless` y la flecha nativa `onReturn`. Desde el menú principal
se conserva abierto el apartado anterior; desde el menú de subrayado se restaura
su selección al volver. El listado usa «↗» para enviada y «○» para solo Kobo,
con leyenda en el subtítulo, en vez de `[Enviada]`.

Se corrige el aplanado de saltos de línea que realiza MenuItem: solo se sustituye
su contenido de texto por tres renglones, conservando foco, gestos y paginación
nativos. Pregunta a 20, fragmento en segunda línea a 17, libro/fecha a 15.

Instalado en el Kobo el 2026-10-14 (revisión local `20261014-235055`), sin
crear respaldos. Sintaxis y archivos verificados; configuración, tarjetas e
imágenes sin cambios. Pendiente de reiniciar KOReader y validar visualmente.

## Respaldos durante el desarrollo

Por petición del usuario se eliminó `/mnt/onboard/.adds/ankiflashcards-config-backups`
del Kobo. Durante esta fase de desarrollo y pruebas no crear nuevos respaldos
de configuración al instalar. Seguir conservando configuración, claves,
tarjetas e imágenes y verificar su integridad antes/después de actualizar.

## Mis tarjetas y estado de Anki

Ambos accesos a Mis tarjetas abren todos los libros y los dos tipos. El título
muestra visibles/total y el filtro indica su ámbito. El visor consulta Anki al
abrirse y antes de actuar: «Eliminar de Anki…» si la nota existe, «Enviar a Anki»
si no existe, o «Verificar en Anki» si no se pudo comprobar. Funciona en ambas
caras. Una caída de red nunca se interpreta como una nota ausente, ni un cambio
de estado convierte un toque de Enviar en un borrado o viceversa.

Mantener pulsada una fila permite «Eliminar de Anki…» con confirmación, validación
de perfil/tipo/identidad, sesión protegida y revalidación de cambios. Conserva
la copia local y bloquea reenvíos automáticos. «Eliminar del Kobo…» se distingue
del borrado remoto. Si AnkiConnect no admite la API protegida, el borrado se
rechaza sin recurrir a la operación antigua sin protección.

Instalado en el Kobo el 2026-10-14 (revisión local `20261014-233905`).
Configuración, tarjetas e imágenes verificadas sin cambios; no se han borrado
notas reales. Pendiente de reiniciar KOReader y validar visualmente.

Al tocar un subrayado con Vocab, Learn o ambos ya guardados se abre el menú de
acciones habitual. La tarjeta solo se abre al elegir una acción Anki explícita;
no se alteran los subrayados ni el atajo de consulta rápida de los no asociados.

## Anotaciones exclusivamente de aprendizaje

La opción se llama «Aprendizaje desde anotaciones» y genera solo Learn, sin
selector ni acciones Vocab ocultas. Las tres columnas separan casilla, extracto
y acción: «+» genera/guarda; «✓» abre directamente la tarjeta Learn guardada.
No hay indicadores V/L ni etiquetas de estado junto al texto. Casillas e iconos
tienen anchos fijos, todas las celdas la misma altura y los extractos una fuente
única sin encogimiento ni salto de línea. El texto completo se abre al tocarlo
o mantenerlo pulsado. Se preseleccionan las pendientes y se desmarcan las
completadas al terminar. Las acciones manuales de selección/diccionario
conservan Anki Vocab y Anki Learn sin cambios.

Mis tarjetas usa filas de fuente fija con pregunta/estado, fragmento original
en su propia línea, y libro/fecha. Cada línea se ajusta por ancho real sin
reducir la fuente. Se usa selected_text o la selección de procedencia local;
para Learn antiguo sin selección se indica que el fragmento no está disponible.

Instalado en el Kobo el 2026-10-14 (revisión local `20261014-233905`).
Pendiente de reiniciar KOReader y validar visualmente.

## Subrayado opcional y anotaciones por lote

Guardar/Enviar tienen al lado **Subrayar** en la vista previa cuando existe
una selección vinculada. Usa la API nativa, restaura la selección anterior,
verifica el libro y no duplica subrayados existentes (incluidas posiciones
PDF restauradas desde JSON). Generar Vocab ya no subraya automáticamente.

La ventana de anotaciones usa filas con selección/extracto a la izquierda y
acción de aprendizaje a la derecha, paginación y controles generales al pie.
Permite abrir tarjetas Learn existentes, seleccionar todas o solo algunas.
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

Esta copia conserva el historial del repositorio original. Desde el 2026-10-23
se publica en el fork propio descrito al inicio. No incluye tus claves ni
`configuration.lua`.

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
