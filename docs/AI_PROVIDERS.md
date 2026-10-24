# Modelos y razonamiento por proveedor

Revisado el 23 de octubre de 2026. La lista incluida funciona sin conexión;
**Cargar catálogo del proveedor** consulta los modelos actuales cuando lo pides.
Ninguna lista garantiza acceso en todas las cuentas o regiones.
Un modelo guardado siempre aparece en la lista aunque sea personalizado. Elegir
**Escribir modelo…** permite introducir otro identificador o una versión exacta.
Abrir los ajustes y buscar no hace peticiones ni escribe configuración.

## Uso

En **Configuración → Generación de tarjetas → Cuenta y modelo de IA**:

- **Modelo de IA** abre una lista y permite escribir un modelo personalizado.
  **Cargar catálogo del proveedor** actualiza la lista mediante una consulta
  en segundo plano. Tocar el aviso cancela la consulta; también se cancela al
  suspender o cerrar el documento. No genera tarjetas ni consume una llamada
  de generación. Si falla la actualización, conserva la lista anterior.
- **Buscar modelos…** filtra localmente por palabras, sin distinguir mayúsculas
  y conservando los identificadores exactos, incluido `:free`. Buscar o cargar
  no cambia el modelo activo: hace falta elegirlo. **Mostrar todos los modelos**
  quita el filtro; **Usar lista incluida** recupera las opciones sin conexión.
- **Thinking** ofrece el valor predeterminado, activado y, si es compatible,
  desactivado. Volver al predeterminado también restablece el esfuerzo.
- **Esfuerzo** muestra solo los niveles compatibles con la familia del modelo.
  Elegir un nivel activa thinking. Apagarlo conserva el nivel elegido, que no se
  envía mientras esté apagado.
- **Ver configuración de este proveedor** muestra el modelo y los controles
  efectivos. **Ver configuración de proveedores**, en Generación de tarjetas,
  permite consultar también los servicios inactivos, sin revelar claves.

Las preferencias se guardan por proveedor y se aplican a Vocab, Learn y la
regeneración de frases. Cambiar de servicio no borra sus preferencias. Cambiar
a un modelo incompatible devuelve las opciones no admitidas a su valor
predeterminado. Los modelos personalizados sin compatibilidad conocida siguen
siendo utilizables con los valores del servicio, sin enviar controles supuestos.
La selección de modelos también está disponible en las cuentas de imágenes;
los controles de thinking de esta pantalla se aplican al texto.

El selector toma como referencia `model_browser.py` y la carga de catálogos de
Anki AI Tutor: selección explícita, búsqueda local, modelo actual visible y
rechazo de resultados antiguos al cambiar la clave. La adaptación utiliza los
menús nativos y procesos cancelables de KOReader. El catálogo vive solo en
memoria durante la sesión del menú; se invalida al cambiar la clave o la
dirección del servicio. Las claves no se escriben en los archivos temporales
del trabajador ni aparecen en errores o en el resumen de configuración.

Gemini pagina `models.list` y filtra `generateContent`; OpenRouter filtra las
modalidades de entrada/salida. OpenAI enumera `/v1/models` y filtra familias
compatibles con la integración de texto o imágenes; la API no proporciona
capacidades completas por endpoint. DeepSeek consulta `/models`. Qwen usa
`/api/v1/models`, su paginación y modalidades, respetando el servidor configurado.
Una dirección Qwen personalizada sin esa ruta conserva lista incluida y entrada
manual. El catálogo tiene límites de 30 segundos por trabajador, 8 MiB, 20 páginas
y 5000 modelos. AnkiVocab y Pollinations no ofrecen selector en esta integración.

## Correspondencia con las API

| Servicio | Configuración enviada |
| --- | --- |
| DeepSeek | `thinking.type=enabled/disabled`; esfuerzo `low`, `high` o `max` al activarlo. |
| OpenAI | `reasoning_effort`; apagar usa `none` solo en familias que lo admiten. GPT-6.1 Sol y GPT-6 Astra no ofrecen apagado. |
| Gemini 3/4 | `generationConfig.thinkingConfig.thinkingLevel`; los niveles dependen del modelo. No se presenta mínimo como apagado. |
| Gemini 2.5 | `thinkingBudget`: apagado 0 si es compatible, dinámico -1 o presupuestos de 1024/4096/8192 para bajo/medio/alto. Pro no ofrece apagado. |
| OpenRouter | Objeto `reasoning` con `enabled`, `effort` y `exclude=true`. El router adapta los controles a la familia y al proveedor del modelo. |
| Qwen 3.8 | `enable_thinking` y `reasoning_effort=low/medium/xhigh`; nunca se combina esfuerzo con `thinking_budget`. |
| Otros Qwen híbridos compatibles | `enable_thinking` y presupuestos 1024/4096/8192. Si necesitan thinking, se consume SSE también en operaciones sin vista incremental. |
| AnkiVocab | Modelo y razonamiento gestionados por el servicio; no se envían parámetros que el gateway no ofrece. |
| Pollinations | Integración de imágenes con modelo gestionado por el servicio; sin controles de razonamiento del texto. |

**Predeterminado del modelo** omite los controles opcionales. Las excepciones
necesarias para activar thinking explícitamente se traducen al contrato de cada
API. La salida de razonamiento no aparece como contenido de la tarjeta. Los
límites de 45 segundos por operación de red, 90 segundos por trabajador y 8 MiB
de tráfico SSE siguen vigentes; cerrar el modal cancela la generación.

El valor de imágenes OpenAI para nuevas configuraciones pasa a `gpt-image-1.5`;
se conservan los identificadores que ya estén guardados explícitamente.

## Fuentes oficiales

- [OpenAI: modelos de razonamiento](https://developers.openai.com/api/docs/guides/reasoning?api-mode=chat)
- [OpenAI: GPT-5.6 Luna](https://developers.openai.com/api/docs/models/gpt-5.6-luna)
- [OpenAI: GPT-5.4](https://developers.openai.com/api/docs/models/gpt-5.4)
- [OpenAI: API de imágenes](https://developers.openai.com/api/reference/resources/images/methods/generate)
- [OpenAI: catálogo de modelos](https://developers.openai.com/api/reference/resources/models/methods/list)
- [DeepSeek: thinking y esfuerzo](https://api-docs.deepseek.com/guides/thinking_mode/)
- [DeepSeek: modelos](https://api-docs.deepseek.com/api/list-models/)
- [Gemini: catálogo](https://ai.google.dev/gemini-api/docs/models)
- [Gemini: paginación del catálogo](https://ai.google.dev/api/models#method:-models.list)
- [Gemini: controles de thinking](https://ai.google.dev/gemini-api/docs/generate-content/thinking)
- [OpenRouter: controles de razonamiento](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens)
- [OpenRouter: catálogo público](https://openrouter.ai/api/v1/models)
- [OpenRouter: modalidades del catálogo](https://openrouter.ai/docs/api/api-reference/models/list-all-models-and-their-properties)
- [Model Studio: API compatible con OpenAI](https://www.alibabacloud.com/help/en/model-studio/qwen-api-via-openai-chat-completions)
- [Model Studio: thinking](https://www.alibabacloud.com/help/en/model-studio/deep-thinking)
- [Model Studio: modelos de imágenes](https://www.alibabacloud.com/help/en/model-studio/image-model/)
- [Model Studio: catálogo y paginación](https://www.alibabacloud.com/help/en/model-studio/list-models)
