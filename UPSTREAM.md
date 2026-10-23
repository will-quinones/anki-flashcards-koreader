# Seguimiento del proyecto original

Fork: https://github.com/will-quinones/anki-flashcards-koreader

Upstream: https://github.com/lgallard/anki-flashcards-koreader

La compatibilidad de producto se define en AGENTS.md y README.md. Este registro
permite distinguir cambios revisados de cambios pendientes aunque el fork
incorpore solo una parte del historial original.

## Base integrada y limpieza del 2026-10-23

La integración antigua `6f2d8f1` incorporó el original hasta
`0abda66` (publicación de v1.3.0). La revisión conserva las funciones útiles
y adapta su comportamiento a esta variante:

| Cambio original | Decisión del fork |
| --- | --- |
| Generación sin imágenes (v1.1.0) | Conservar: extras opcionales, Learn sin imágenes/audio. |
| Exportación CSV/TSV (v1.2.0) | Conservar dentro del menú nativo de Tarjetas. |
| Guardado automático de vistas previas (v1.3.0) | Excluir: se mantiene Guardar explícito y cancelar sin persistir. |
| Persistencia atómica e identidad de tarjetas (v1.3.0) | Conservar y comprobar con las simulaciones actuales. |
| Protección de imágenes y respuestas tardías (v1.3.0) | Conservar y adaptar a edición, regeneración y cierre de esta variante. |
| Panel Anki Manage, accesos My Cards y apertura automática al tocar subrayados | Mantener retirados; solo menús nativos y acciones explícitas. |
| Consulta automática por subrayado morado | Retirar: los colores comparten el menú nativo y preservan las notas personales. |
| Configuración y contexto duplicados | Centralizar la configuración y mantener un extractor de contexto local al módulo. |

## Última revisión: 2026-10-23

Revisado el original hasta `e452539f7d29ad551bbef2c7128a86b4ff0e4a1c`.
Las únicas novedades desde la base anterior son:

| Commit original | Decisión del fork |
| --- | --- |
| `ff68843` — borrado por libro | Incorporar la persistencia y adaptar la acción a Estadísticas por libro. Pulsación larga y confirmación en español; borra Vocab/Learn solo del Kobo, preserva imágenes compartidas, notas de Anki y subrayados. |
| `3ecba2e` — integración de esa función | Revisado; no aporta cambios adicionales a la función adaptada. |
| `8c0038e` — versión 1.4.0 | No importar metadatos de versión, manifiesto ni changelog como publicación propia. |
| `e452539` — integración de la versión | Revisado; no aporta código funcional adicional. |

La adaptación conserva el menú nativo, su navegación de vuelta y el recuento
separado de tarjetas enviadas, pendientes y por revisar. No incorpora el antiguo
panel de gestión ni el guardado automático. La batería completa pasa: 54 pruebas,
sin omisiones, más la comprobación de sintaxis de los 36 módulos Lua.

Al adoptar cambios parcialmente, los commits originales pueden seguir apareciendo
en `git log HEAD..upstream/main`: eso no indica que falte revisar su contenido.
La siguiente comparación de novedades parte de la revisión registrada arriba.

## Procedimiento de actualización

1. Consultar las novedades con `git fetch upstream`.
2. Comparar los commits pendientes con la última revisión registrada aquí.
3. Aplicar las mejoras compatibles en una rama de mantenimiento, con referencia
   al commit original y sus dependencias. Adaptar las pruebas a las APIs reales
   de esta variante sin relajar las garantías que comprueban.
4. Ejecutar `python3 tests/run_tests.py`, revisar el diff y publicar la revisión
   validada en la rama personalizada del fork.

Los commits de versión, changelog y empaquetado del autor no se importan como
versiones propias. Una revisión pendiente se registra antes de la siguiente
integración; no se utiliza un pull automático para sustituir los flujos locales.
