# Investigación de Gartic Phone y arquitectura propuesta

## Fase 1: resultado parcial, bloqueado

Objetivo: https://garticphone.com, 14 de noviembre de 2026.
REA capture_browser_scenario abrió el sitio con Chrome 157.0.8103.51 en un perfil temporal, esperó 3 segundos y capturó DOM, accesibilidad y red. Cloudflare respondió «Sorry, you have been blocked». No se introdujo apodo, no se creó sala y no se alcanzó el lobby. REA cerró el navegador temporal al terminar.

Evidencia real: `rea_evidence.json`, registro `ev_b3a6d76228b9650147c3accb0730a4c45c83f98da9f91ff506502bd8d0c4f630`; resumen `ev_07794dab4093984b3a8fa03d990fd54b51ced5a1821a1b64023c319f4c5fcc01`. Se capturaron 4 transacciones: documento, dos imágenes y CSS; una respuesta 4xx y tres 2xx. No se descargó JavaScript de Gartic Phone en esta captura. El tráfico corresponde a la página de bloqueo. Ray ID: a5a937d92a224af0.

| Pregunta | Resultado respaldado |
| --- | --- |
| Estados exactos, temporización, timeout y álbum | No verificados |
| Asignación y rotación entre N jugadores | No verificadas; podrían depender del servidor |
| Tiempos y límite de jugadores de Gartic | No verificados |
| Formato de trazos, colores, grosor, borrador y undo de Gartic | No verificado |
| Eventos de red del juego | Ninguno observado |

No se atribuye a Gartic ningún evento, algoritmo ni estructura inventados. Para completar esta fase se necesita una sesión accesible mediante CDP o una captura autorizada del sitio con sus bundles y tráfico. Detener la navegación en lobby tampoco permite verificar dinámicamente rondas posteriores; estas necesitan evidencia estática suficiente, y la lógica exclusivamente servidor seguirá siendo desconocida.

## Fases 2 y 3: diseño propio de Fonococo

El código Swift es una base independiente derivada de los requisitos del usuario, no código extraído ni un protocolo compatible con Gartic. Los estados idle/loading/lobby/writing/drawing/revealing/error son estados locales solicitados. El tiempo agotado se representa localmente y no permite al cliente avanzar la ronda autoritativa.

Los límites, duración, orden de participantes, turnos y cadenas llegan del backend propio. No se implementa una supuesta rotación de Gartic. Firebase Realtime Database observa snapshots y recibe contribuciones con identificadores idempotentes; las transiciones y asignaciones requieren un backend autoritativo con reglas de acceso. PencilKit conserva su formato nativo para deshacer y restaurar, y expone puntos para interoperabilidad local. SwiftData conserva álbumes completos y Core Data respalda dibujos en curso.

La configuración procede de Info.plist y de GoogleService-Info.plist local; no existen claves ni endpoints privados incrustados en Swift. Una clave distribuida en una app es recuperable del binario: las credenciales privilegiadas deben permanecer en el servidor.

## Actualización: motor clásico solicitado por el usuario

Se implementó GameEngine independiente de Gartic: N rondas, r indexado desde cero, libro (i+r)%N, alternancia escritura/dibujo, entradas vacías por plazo y revelación final. FirebaseRoomService confirma cambios mediante transacciones de snapshots; Storage almacena PNG antes de la entrega. La antigua descripción de motor pendiente/submissions queda reemplazada por este contrato. No es evidencia de ingeniería inversa: es implementación de la mecánica proporcionada explícitamente por el usuario. El motor ejecuta en clientes cooperativos, con reloj local; no constituye un backend autoritativo ni oculta datos frente a clientes modificados.
