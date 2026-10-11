# elTOQUE Cliente — integración compartida en desarrollo

Admin coordina contratos, configuración y SQL. Supabase ejecuta un único emisor
`send-push-notifications`, alojado actualmente en tuktuk-control, sobre la
referencia operativa v16. Se reutilizan Firebase, Google OAuth y el cron
`tuktuk-push-dispatch`; no hay cron ni emisor nuevos.

El borrador independiente `marketplace-customer-rate-push` queda sustituido:
se retiraron su código de envío y la propuesta de cron. No desplegarlo.
El esquema de preactivación `20261011141714` ya está aplicado y se concilia
en Admin como documento, fuera del directorio de migraciones automáticas.
El SQL pendiente de trigger/verificación/reversión pertenece a Admin.

## Registro y baja

`supabase/functions/marketplace-customer-push-registration` solo admite
subscribe/unsubscribe. No contiene lógica Firebase de servicio, FCM ni claim.
Primera alta: Turnstile verificado en servidor para www.vrixora.com y acción
customer-rate-subscribe. Claves: CUSTOMER_TURNSTILE_SITE_KEY pública en Flutter;
TUKTUK_CUSTOMER_TURNSTILE_SECRET protegida en Edge. No se extrajeron valores.
Origin/IP no autorizan registros. Renovación/rotación/baja exigen posesión del
secreto aleatorio de 32 bytes, cuyo hash se guarda en el servidor.
Las actualizaciones comparan el token anterior y comprueban filas afectadas
para detectar carreras. La baja deshabilita sin borrar historial.

Flutter conserva el secreto antes de registrar para tolerar respuestas perdidas;
solo marca la suscripción activa después de confirmación. La recuperación de
un registro ausente puede pedir desafío durante opt-in explícito. Refresh
silencioso falla sin bloquear reservas. El permiso push es voluntario y la
consulta de cabecera sigue siendo independiente.

## Compatibilidad y límites

Firebase/VAPID y service worker permanecen bajo /cliente/tuk/. No se cambian
precios, reservas, mapas ni la app Flutter Conductor. El mensaje conserva
customer_exchange_rate_update y rate_history_id; el worker mantiene su tag por
cambio. Envío es al menos una vez: un fallo al confirmar FCM puede reintentarse;
no se afirma entrega exactamente una vez ni recepción visible.

La revocación evita nuevos envíos tras la comprobación del servidor; no puede
cancelar una petición FCM ya en vuelo. Mantener límites de abuso perimetrales
antes de activar producción; Turnstile no sustituye una política de capacidad.

## Validación local

Desde este repositorio:

```powershell
deno test --no-config --no-lock supabase/functions/marketplace-customer-push-registration/registration_test.ts
flutter pub get --offline
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub
```

Los tests backend usan tokens y secretos sintéticos, fetch simulado y ninguna
conexión de red. La comprobación real del widget Turnstile, suscripción en Edge,
FCM y navegador cerrado requiere una fase posterior autorizada.

No se autoriza merge, publicación, migración remota ni despliegue mediante este
documento. Revisar el informe central de Admin y los tres commits antes de
proponer una activación.
