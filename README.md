# Fonococo — base iPhone/iPad

Abre `Fonococo.xcodeproj`, selecciona el esquema Fonococo y un destino iOS 17 o posterior. El target Universal usa el paquete local `Package.swift`; FirebaseCore, FirebaseAuth y FirebaseDatabase se resuelven mediante SPM (Firebase 12.x). El código reutilizable está en Sources y el punto de entrada en App.

## Configuración

1. Copia `Config/Secrets.xcconfig.example` a `Config/Secrets.xcconfig`. Completa base URL HTTPS, clave cliente y rutas relativas de frases/avatares. `Config/App.xcconfig` ya incluye opcionalmente ese archivo; `Config/Info.plist` expone las variables a Bundle.main. Escribe URLs como `https:/$()/host` en xcconfig para evitar el comentario `//`.
2. Cambia el Bundle Identifier `com.example.fonococo` y el equipo de firma del target. Descarga desde tu proyecto Firebase el GoogleService-Info.plist real y colócalo en `App/GoogleService-Info.plist`; Xcode lo incorpora al bundle por el grupo sincronizado. La plantilla ilustra campos, no sustituye el archivo generado por Firebase. Activa Auth anónimo y configura Realtime Database.
3. Al faltar el plist o sus valores obligatorios, la app muestra el error de configuración antes de construir servicios Firebase. No se utiliza try!, force unwrap ni FirebaseApp.configure() sin validación previa.
4. Micrófono y guardado en Fotos tienen textos de permisos en Info.plist. Se solicitan al usar la función. No es necesario otorgarlos para entrar al lobby.

Las claves empaquetadas en una app no son secretos frente al usuario del dispositivo. Las claves privilegiadas permanecen en tu backend; restringe las claves cliente por aplicación/API y protege Firebase mediante autenticación y reglas. Ninguna credencial se incluye en el repositorio.

## Contrato propio del backend

La investigación REA fue bloqueada por Cloudflare. Consulta `arquitectura_gartic.md` y `rea_evidence.json`. Ningún estado/evento o algoritmo en Swift se atribuye a Gartic Phone.

El cliente consume `rooms/{roomID}/snapshot` con RoomSnapshot Codable: id, phase, players, turns, chains, deadline opcional (segundos Unix), settings opcional. Cada turno tiene id, playerID, chainID, round y kind; el servidor publica sólo las asignaciones activas y el contenido que corresponde ver al jugador. Las listas vacías omitidas por Firebase se normalizan.

Las contribuciones se escriben en `rooms/{roomID}/submissions/{turnID}/{authorID}`. El backend debe autenticar miembros, validar autor/turno/plazo, impedir sobrescrituras, asignar cadenas y avanzar rondas de forma atómica. El cliente nunca decide la rotación ni inicia rondas al terminar su timer. La creación de salas, admisión de miembros y motor autoritativo son trabajo de backend pendiente: esta entrega es arquitectura cliente, no un servicio multijugador desplegado.

Los medios se guardan en RTDB bajo `rooms/{roomID}/media/{uuid}`. Configura reglas por miembro/autor, tamaños y tipo MIME. Los límites de subida en Swift son decisiones propias. El servidor debe proteger la lectura por fase para evitar revelar cadenas antes de tiempo.

REST usa rutas relativas configuradas, GET y cabecera X-API-Key, respuesta de frase `{ "text": "..." }` y avatares `[{ "id": "...", "url": "..." }]`. No existe endpoint público elegido ni credencial de demostración. El cliente REST queda desacoplado de Firebase.

## Capas

- Etapa 1 (SwiftUI): splash, sesión invitada local, autenticación Firebase disponible, lobby, salas privadas locales de 2–8, búsqueda aleatoria demostrativa, perfil, progreso y amigos locales. Las salas locales y matchmaking no conectan dispositivos.
- Config: carga de Bundle e inicialización Firebase.
- Models: datos Codable y estados propios.
- Services: protocolos/adaptadores Firebase, REST y audio.
- ViewModels: autenticación, snapshots/turnos, timer y lienzo; errores explícitos y cancelación.
- Persistence: álbumes SwiftData y respaldos de trazos Core Data con modelo programático.
- Views/SwiftUI: wireframes nativos, sin estilos.
- Views/UIKit: PencilKit, historial con segue y temporizador animado; componentes representables.

PencilKit serializa su propio PKDrawing; esos bytes son la copia de recuperación en Core Data. El PNG es el formato de intercambio y CGPoint expone coordenadas locales. Ese formato no representa el protocolo de Gartic. La consulta @Query actualiza el historial de álbumes persistidos.

## Verificación

Se validan sintaxis Swift y formato de plist/proyecto. Todos los modelos, ViewModels, vistas, persistencia (incluidas macros SwiftData), protocolos y audio pasaron typecheck contra el SDK iOS Simulator con destino iOS 17. La compilación completa requiere resolver Firebase; SwiftPM falló al obtener la dependencia y Xcode no pudo escribir su caché de manifiestos en este entorno. No se afirma que haya pasado una compilación completa ni una sesión multijugador real. Ejecuta Build en Xcode después de resolver los paquetes y proporcionar la configuración.

Fuentes de integración: [Firebase para Apple](https://firebase.google.com/docs/ios/setup), [Realtime Database: lectura/escritura](https://firebase.google.com/docs/database/ios/read-and-write).

Los álbumes guardados incluyen bytes de PNG y audio; si falla alguna descarga, el guardado falla de forma explícita. Las reacciones subidas se asocian a la copia local; su difusión a otros jugadores requiere definir un contrato propio de backend. Los wireframes muestran textos y referencias a medios; un visor/reproductor final queda para la siguiente capa de interfaz.

## Motor clásico implementado

GameEngine implementa reglas propias solicitadas: N participantes fijos, N rondas (índice r=0...N−1), libro asignado a i = (i+r)%N, escritura en índices pares y dibujo en impares. Cada libro termina con N entradas de N autores distintos. La fórmula usa índices cero; la ronda visible 2 corresponde a r=1. Un turno vencido conserva una entrada vacía para no romper la cadena.

El flujo SwiftUI de Etapa 1 limita la creación y los ajustes de sala a 2–8 participantes. Las salas locales se identifican como demostración y no admiten conexión entre dispositivos. El motor y FirebaseRoomService conservan sus modelos y compatibilidad; sus valores históricos contemplan hasta 12 participantes y sus operaciones remotas requieren configuración Firebase. FirebaseRoomService ejecuta creación, admisión, inicio, contribución y avance como transacciones sobre rooms/{id}/snapshot. RealtimeMediaService comprime el dibujo y guarda Base64 antes de intentar confirmar el turno; si éste venció, la entrega se rechaza (el archivo puede quedar huérfano y requiere política de limpieza).

Esta implementación sustituye el contrato anterior de submissions: el motor Swift modifica snapshots completos mediante transacciones. Las reglas Firebase del proyecto deben permitir esas operaciones a los miembros autenticados. Es un motor coordinado por clientes, no una Cloud Function autoritativa: necesita al menos un cliente conectado para cerrar el plazo, usa reloj de dispositivo y el snapshot contiene libros completos. Para partidas adversariales se debe mover la misma lógica a servidor y restringir lectura por jugador; no desplegar reglas públicas para habilitarlo. Los participantes quedan fijos al iniciar y los desconectados completan por timeout.

Validación local reproducible: compilar Tests/GameEngineChecks.swift junto con GameModels.swift, ServiceProtocols.swift y GameEngine.swift. Comprueba N=2...8, rotación, autores únicos por libro, transición por entrega y por timeout. No requiere Firebase ni internet.


## Corrección RTDB y medios Base64

RoomSnapshotCodec se utiliza tanto al observar como en las transacciones. Escribe colecciones ordenadas con claves item000000, item000001, etc.; omite arrays y mapas vacíos y campos nulos. Lee formatos antiguos de arrays, mapas numéricos y campos ausentes. Los timestamps permanecen en segundos Unix. Los errores de serialización ya no se sustituyen por un error genérico al abortar una transacción; una caché vacía puede reconciliarse con el servidor.

FirebaseServiceFactory selecciona explícitamente Database.database(app:url:) con app.options.databaseURL, cargado del GoogleService-Info.plist. STORAGE_BUCKET ya no es obligatorio y FirebaseStorage se eliminó de Package.swift. No se modificaron credenciales ni reglas desplegadas.

RealtimeMediaService escribe JPEG (máximo 1024 px, calidad 0.65, límite binario 512 KB) y audio AAC/m4a (máximo 2 MB) codificados en Base64, junto con mimeType, encoding, byteCount y ownerID. Los identificadores rtdb-media://rooms/{room}/media/{id} son referencias internas, no URLs HTTP. Las vistas y álbumes offline los descargan mediante el SDK autenticado. Las URLs históricas de Firebase Storage no se migran automáticamente.

Las reglas RTDB deben permitir a los miembros la lectura y escritura autorizada del subárbol media además del snapshot. Esto elimina la dependencia de Cloud Storage, pero sigue consumiendo la cuota de datos y transferencia de RTDB; Base64 añade aproximadamente un tercio al tamaño binario. No se verificó una partida contra Firebase en el dispositivo durante esta corrección.

Pruebas locales: Tests/RoomSnapshotCodecChecks.swift cubre creación de lobby, colecciones ausentes, mapas ordenados, formatos antiguos, fecha y turnos vacíos. Typecheck del subconjunto sin SDK Firebase aprobado.
